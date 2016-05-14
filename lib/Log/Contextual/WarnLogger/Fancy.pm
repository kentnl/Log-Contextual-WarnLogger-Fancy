use 5.006;    # our
use strict;
use warnings;

package Log::Contextual::WarnLogger::Fancy;

our $VERSION = '0.001000';

# This class provides a few patterns not in the Log::Contextual::Easy::Default
# and Log::Contextual::WarnLogger features.
#
# 1. Has a shared prefix for all compontents that use it, which is used
#    when the per-package prefix is omitted. This is mostly just to simplify "All on"
#    and "All off" behaviours will still allowing fine-grained control for precision tracing.
#
# 2. Has a "default" upto level of "warn", so that warn levels and higher can be used like
#    normal warnings and be user visible.
#
# 3. Has a "logger label" which provides a compacted module name that is infix-compacted
#    to 21 characters to make flow more obvious in conjunction with the "shared prefix"
#    option.
#
# 4. Has ANSI Color tinting of log messages for easy skimming, which incidentally makes any app
#    that uses this look much more modern.
#
# The biggest downside of doing this has been the details are so specific that I had to
#    rewrite all the existing logic to support it :/
#
# Also, this class intentionally nuked all "custom levels" support to keep the complexity
# and to avoid AUTOLOAD shenianigans.

use strict;
use warnings;
use Carp qw( croak );

use Term::ANSIColor qw( colored );

delete $Log::Contextual::WarnLogger::Fancy::{$_}
  for qw( croak colored );    # namespace clean

delete $Log::Contextual::WarnLogger::Fancy::{$_}
  for qw( _gen_level_sub _gen_is_level_sub _name_sub _can_name_sub _elipsis )
  ;                           # not for external use cleaning

BEGIN {
    # Lazily find the best XS Sub naming implementation possible.
    # Preferring an already loaded implementation where possible.
    #<<< Tidy Guard
    my $impl = ( $INC{'Sub/Util.pm'}           and defined &Sub::Util::set_subname )  ? 'SU'
             : ( $INC{'Sub/Name.pm'}           and defined &Sub::Name::subname     )  ? 'SN'
             : ( eval { require Sub::Util; 1 } and defined &Sub::Util::set_subname )  ? 'SU'
             : ( eval { require Sub::Name; 1 } and defined &Sub::Name::subname     )  ? 'SN'
             :                                                                          '';
    *_name_sub = $impl eq 'SU'   ? \&Sub::Util::set_subname
               : $impl eq 'SN'   ? \&Sub::Name::subname
               :                   sub { $_[1] };
    #>>>
    *_can_name_sub = $impl ? sub() { 1 } : sub () { 0 };
}

_gen_level($_) for (qw( trace debug info warn error fatal ));

# Hack Notes: Custom levels are not currently recommended, but doing the following *should* work:
#
# Log::Contextual::WarnLogger::Fancy::_gen_level('custom');
# $logger->{levels} = [ @{ $logger->{levels}, 'custom' ];
# $logger->{level_nums}->{ 'custom' } = 1;
# $logger->{level_labels}->{ 'custom' } = 'custo';

sub new {
    my ( $class, $args ) = @_;

    my $self = bless {}, $class;

    $self->{env_prefix} = $args->{env_prefix}
      or die 'no env_prefix passed to ' . __PACKAGE__ . '->new';

    for my $field (qw( group_env_prefix default_upto label label_length )) {
        $self->{$field} = $args->{$field} if exists $args->{$field};
    }
    if ( defined $self->{label} and length $self->{label} ) {
        $self->{label_length} = 16 unless exists $args->{label_length};
        $self->{effective_label} =
          _elipsis( $self->{label}, $self->{label_length} );
    }
    my @levels       = qw( trace debug info warn error fatal );
    my %level_colors = (
        trace => [],
        debug => ['blue'],
        info  => ['white'],
        warn  => ['yellow'],
        error => ['magenta'],
        fatal => ['red'],
    );

    $self->{levels} = [@levels];
    @{ $self->{level_nums} }{@levels} = ( 0 .. $#levels );
    for my $level (@levels) {
        $self->{level_labels}->{$level} = sprintf "%-5s", $level;
        if ( @{ $level_colors{$level} || [] } ) {
            $self->{level_labels}->{$level} =
              colored( $level_colors{$level}, $self->{level_labels}->{$level} );
        }
    }

    unless ( exists $self->{default_upto} ) {
        $self->{default_upto} = 'warn';
    }
    return $self;
}

# TODO: Work out how to savely use Unicode \x{2026}, and then elipsis_width
# becomes 1. Otherwise utf8::encode() here after computing width might have to do.
my $elipsis_char  = chr(166);               #"\x{183}";
my $elipsis_width = length $elipsis_char;

sub _elipsis {
    my ( $text, $length ) = @_;
    return sprintf "%" . $length . "s", $text if ( length $text ) <= $length;

 # Because the elipsis doesn't count for our calculations because its logically
 # "in the middle". Subsequent math should be done assuming there is no elipsis.
    my $pad_space = $length - $elipsis_width;
    return '' if $pad_space <= 0;

    # Doing it this way handles a not entirely balanced case automatically.
    #   trimming   asdfghij to length 6 with a 1 character elipis
    #   ->  "....._"
    #   ->  ".._..."
    # so left gets a few less than the right here to have room for elipsis.
    #
    # When pad_space is even, it all works out in the end due to int truncation.
    my $lw = int( $pad_space / 2 );
    my $rw = $pad_space - $lw;

    return sprintf "%s%s%s", ( substr $text, 0, $lw ), $elipsis_char,
      ( substr $text, -$rw, $rw );
}

sub _log {
    my $self    = shift;
    my $level   = shift;
    my $message = join( "\n", @_ );
    $message .= qq[\n] unless $message =~ /\n\z/;
    my $label = $self->{level_labels}->{$level};

    $label .= ' ' . $self->{effective_label} if $self->{effective_label};
    warn "[${label}] $message";
}

sub _gen_level_sub {
    my ( $level, $is_name ) = @_;
    return sub {
        my $self = shift;
        return unless $self->$is_name;
        $self->_log( $level, @_ );
    };
}

sub _gen_is_level_sub {
    my ($level) = @_;
    my $ulevel = '_' . uc $level;
    return sub {
        my $self = shift;

        my ( $ep, $gp ) = @{$self}{qw( env_prefix group_env_prefix )};

        my ( $ep_level, $ep_upto ) = ( $ep . $ulevel, $ep . '_UPTO' );

        my ( $gp_level, $gp_upto ) = ( $gp . $ulevel, $gp . '_UPTO' )
          if defined $gp;

        # Explicit true/false takes precedence
        return !!$ENV{$ep_level} if defined $ENV{$ep_level};

        # Explicit true/false takes precedence
        return !!$ENV{$gp_level} if $gp_level and defined $ENV{$gp_level};

        my $upto;

        if ( defined $ENV{$ep_upto} ) {
            $upto = lc $ENV{$ep_upto};
            croak "Unrecognized log level '$upto' in \$ENV{$ep_upto}"
              if not defined $self->{level_nums}->{$upto};
        }
        elsif ( $gp_upto and defined $ENV{$gp_upto} ) {
            $upto = lc $ENV{$gp_upto};
            croak "Unrecognized log level '$upto' in \$ENV{$gp_upto}"
              if not defined $self->{level_nums}->{$upto};
        }
        elsif ( exists $self->{default_upto} ) {
            $upto = $self->{default_upto};
        }
        else {
            return 0;
        }
        return $self->{level_nums}->{$level} >= $self->{level_nums}->{$upto};
    };
}

sub _gen_level {
    my ($level) = @_;
    my $is_name = "is_$level";

    my $level_sub = _gen_level_sub( $level, $is_name );
    my $is_level_sub = _gen_is_level_sub($level);

    _can_name_sub and _name_sub( "$level",   $level_sub );
    _can_name_sub and _name_sub( "$is_name", $is_level_sub );

    no strict 'refs';
    *{$level}   = $level_sub;
    *{$is_name} = $is_level_sub;
}

1;

__END__

=head1 NAME

Log::Contextual::WarnLogger::Fancy - A modernish default lightweight logger

=head1 AUTHOR

Kent Fredric C<kentnl@cpan.org>

=head1 COPYRIGHT AND LICENSE

This software is copyright (c) 2016 by Kent Fredric

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

=cut
