#!/usr/bin/env perl

use strict;
use warnings;
use File::Basename qw/dirname basename/;
use Getopt::Long qw/GetOptions/;
use Data::Dumper;

# noncore modules
use FindBin qw/$RealBin/;
use lib "$RealBin/../lib/perl5";
use File::Which qw/which/;

use Test::More tests => 1;

my $scriptDir = dirname $0;
local $0 = basename $0;

# Prioritize this scripts folder in the path
# because we are testing this script in particular
$ENV{PATH}="$scriptDir/../scripts:$ENV{PATH}";

my $parseBruker = which("parseBruker.pl");
if(! -e $parseBruker){
  note "PATH is";
  note "  $ENV{PATH}";
  BAIL_OUT("Could not find parseBruker.pl in PATH");
}
note "executable is at $parseBruker";

my $tmpdir = "$scriptDir/tmp";
mkdir $tmpdir;

subtest 'basic' => sub{
  plan tests => 5;

  # Parse each raw file and see if we get what's expected
  for my $rawfile(glob("$scriptDir/raw/*.xlsx")){
    my $target = "$tmpdir/".basename($rawfile,".xlsx").".tsv";
    my $expectedfile = "$scriptDir/expected/".basename($rawfile,".xlsx").".tsv";
    system("$parseBruker $rawfile > $target");
    my $expected = readTsv($expectedfile);
    my $observed = readTsv($target);

    is_deeply($observed, $expected, "Check $rawfile against $expectedfile");
  }

};

sub readTsv{
  my($file) = @_;
  my %tsv;

  open(my $fh, $file) or BAIL_OUT "ERROR: could not read $file: $!";
  my $header = <$fh>;
  chomp($header);
  my @header = split(/\t/, $header);
  while(<$fh>){
    chomp;
    my %F;
    my @F = split /\t/;

    # Read in the line and index it according to the header
    @F{@header} = @F;

    # The special key for these spreadsheets is plate + isolate
    # Use a triple tilde because it probably is not in any
    # sample name or plate name.
    my $key = join("~~~", $F{plate}, $F{sample}, $F{acquisition});

    $tsv{$key} = \%F;
  }
  close $fh;

  return \%tsv;
}
