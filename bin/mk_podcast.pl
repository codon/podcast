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
);

use MyPodcasts;

my ($podcast, $capture, $feed, $list, $daysago, $help) = (undef, 1, 1, undef, 0, 0);

GetOptions(
	"podcast=s" => \$podcast,
	"capture!"  => \$capture,
	"feed!"     => \$feed,
	"list"      => \$list,
	"daysago=i" => \$daysago,
	"help"      => \$help,
);

if ( $list ) {
	print "Known Podcasts: \n\t".join("\n\t", MyPodcasts->list())."\n";
	exit(0);
}

# look up podcast in MyPodcasts
my %podcast = ($podcast) ? MyPodcasts->get_Config( $podcast, $daysago ) : ();

if ( $help || !$podcast{'source'} ) {
	warn "$podcast: invalid podcast\n" unless $podcast{'source'};
	die usage();
}

capture_stream($podcast) if ($capture);
build_feed(    $podcast) if ($feed);

exit(0);

sub capture_stream {
	my $podcast = shift;

	# Ensure the destination dir exists
	mkpath( qq|$ENV{HOME}/podcasts/$podcast| ) unless ( -d qq|$ENV{HOME}/podcasts/$podcast| );

	# open the destination file
	open my $mp3, '>', $podcast{'destfile'} or die "could not open destination file: $!\n";

	# instatiate and set up the Curl client
	my $curl = WWW::Curl::Easy->new();
	$curl->setopt(CURLOPT_BUFFERSIZE,0);                   # do not buffer; write straight to disk
	$curl->setopt(CURLOPT_TIMEOUT,$podcast{'duration'});   # how long to capture the stream (in seconds)
	$curl->setopt(CURLOPT_WRITEDATA,$mp3);                 # where to write the data
	$curl->setopt(CURLOPT_URL,$podcast{'source'});         # the url to capture

	# make the call
	my $rc = $curl->perform();

	if ( 28 == $rc ) { # expect a timeout; this is a continuous stream we're grabbing...
		# ok
		MyPodcasts->add_ID3_tag( $podcast, $daysago );
	}
	else {
		# problems XXX TBD Better error handling?
		$curl->strerror($rc);
	}

	return;
}

sub build_feed {
	my $podcast = shift;

	die "cannot build feed for $podcast{'name'}: $podcast{'destfile'} does not exist\n"
			unless (-e $podcast{'destfile'});

	# update the RSS file
	MyPodcasts->build_RSS($podcast, $daysago);
}

sub usage {
	return qq{
		--podcast=<string>       Specify a podcast
		--nocapture              Do not capture the stream
		--nofeed                 Do not build the RSS feed
		--list                   List all known podcasts
		--daysago=n              Look for media file N days ago
		--help                   Print this usage
	\n};
}
