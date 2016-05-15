# vim: syntax=perl

requires 'Term::ANSIColor';
requires perl => '5.006';
suggests 'Sub::Util';


on test => sub {
  requires 'Log::Contextual';
  requires 'Test::More' => '0.89';
  requires 'Test::Differences';
  requires 'Term::ANSIColor' => '2.01'; # colorstrip
  recommends 'Sub::Util';
};
