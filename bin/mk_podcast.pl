#! /usr/bin/perl

use strict;
use warnings;

use File::Path qw(mkpath);
use Getopt::Long;
use Time::HiRes qw( time sleep );
use WWW::Curl::Easy qw(
    CURLOPT_BUFFERSIZE
    CURLOPT_TIMEOUT
    CURLOPT_WRITEDATA
    CURLOPT_URL
    CURLOPT_FOLLOWLOCATION
);

use MyPodcasts;

my ($podcast, $capture, $feed, $list, $daysago, $basedir, $baseurl, $help, $overwrite,) =
   ( undef,    1,        1,    undef,  0,        undef,    undef,    0,     0);

GetOptions(
    'podcast=s' => \$podcast,
    'capture!'  => \$capture,
    'feed!'     => \$feed,
    'list'      => \$list,
    'basedir=s' => \$basedir,
    'baseurl=s' => \$baseurl,
    'daysago=i' => \$daysago,
    'help'      => \$help,
    overwrite   => \$overwrite,
);

my $Podcast = MyPodcasts->new(
    podcast => $podcast,
    basedir => $basedir,
    baseurl => $baseurl,
    daysago => $daysago,
);

if ( $list ) {
    print "Known Podcasts: \n\t".join("\n\t", $Podcast->list())."\n";
    exit(0);
}

# look up podcast in $Podcast
my %podcast = ($podcast) ? $Podcast->get_Config() : ();

if ( $help || !$podcast{'source'} ) {
    warn "$podcast: invalid podcast\n" if ($podcast && !$podcast{'source'});
    die usage();
}

capture_stream($Podcast) if ($capture);
build_feed(    $Podcast) if ($feed);

exit(0);

sub capture_stream {
    my $podcast = shift;

    if ( -e $podcast->{'destfile'} && ! $overwrite ) {
        die "$podcast->{'destfile'} already exists!";
    }
    # open the destination file
    open my $mp3, '>', $podcast->{'destfile'} or die "could not open destination file: $!\n";

    # instatiate and set up the Curl client
    my $curl = WWW::Curl::Easy->new();
    $curl->setopt(CURLOPT_BUFFERSIZE,0);                     # do not buffer; write straight to disk
    $curl->setopt(CURLOPT_TIMEOUT,$podcast->{'duration'});   # how long to capture the stream (in seconds)
    $curl->setopt(CURLOPT_WRITEDATA,$mp3);                   # where to write the data
    $curl->setopt(CURLOPT_URL,$podcast->{'source'});         # the url to capture
    $curl->setopt(CURLOPT_FOLLOWLOCATION,1);                 # follow Location: header redirects

    # make the call
    my $rc = $curl->perform();

    if ( 0 == $rc || 28 == $rc ) { # expect a timeout; this is a continuous stream we're grabbing...
        # ok
        $podcast->add_ID3_tag( $daysago );
    }
    else {
        # problems XXX TBD Better error handling?
        warn "libCurl returned [$rc]: ".$curl->strerror($rc);
    }

    return;
}

sub build_feed {
    my $podcast = shift;

    die "cannot build feed for $podcast{'name'}: $podcast{'destfile'} does not exist\n"
            unless (-e $podcast{'destfile'});

    # update the RSS file
    $Podcast->build_RSS($podcast, $daysago);
}

sub usage {
    return qq{
        --podcast=<string>                          Specify a podcast
        --nocapture                                 Do not capture the stream
        --nofeed                                    Do not build the RSS feed
        --list                                      List all known podcasts
        --basedir=<path/to/save/dir>                Base directory for saving streams
        --baseurl=<http://example.com/examples>     Base url for RSS feed
        --daysago=n                                 Look for media file N days ago
        --help                                      Print this usage
    \n};
}
