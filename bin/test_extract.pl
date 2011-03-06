#! /usr/bin/perl

use strict;
use warnings;

use File::Path qw(mkpath);
use Getopt::Long;
use Time::HiRes qw( time sleep );

use MyPodcasts;

my $podcast;
my $basedir;

GetOptions(
    'podcast=s' => \$podcast,
    'basedir=s' => \$basedir,
);

unless ($podcast) {
    die "$0 --podcast <name>\n";
}

my $Podcast = MyPodcasts->new(
    podcast => $podcast,
    basedir => $basedir,
);

# look up podcast in $Podcast
my %config = $Podcast->get_Config();

die "Can't get config for $podcast\n" unless (keys %config);

my %extraction = $config{'extract'}->( $Podcast, $config{'home_page'} ); # fake an OO call

use Data::Dumper;
warn Dumper(\%extraction);

exit;
