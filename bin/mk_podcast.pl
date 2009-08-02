#! /usr/bin/perl

use strict;
use warnings;

use File::Path;
use Getopt::Long;
use Time::HiRes qw( time sleep );

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
	print "Known Podcasts: \n\t".join("\n\t", MyPodcasts->listPodcasts())."\n";
	exit(0);
}

# look up podcast in MyPodcasts
my %podcast = ($podcast) ? MyPodcasts->getConfig( $podcast, $daysago ) : ();

if ( $help || !$podcast{'source'} ) {
	warn "$podcast: invalid podcast\n" unless $podcast{'source'};
	die usage();
}

capture_stream($podcast) if ($capture);
build_feed(    $podcast) if ($feed);

exit(0);

sub capture_stream {
	my $podcast = shift;

	if ( my $pid = fork() ) {
		# parent
		my $start_time = time;
		sleep( $podcast{'duration'} - (time() - $start_time) );
		kill 'INT', $pid;

	# Ensure the destination dir exists
	mkpath( qq|$ENV{HOME}/podcasts/$podcast| ) unless ( -d qq|$ENV{HOME}/podcasts/$podcast| );
		# move dump file to appropriate destination
		link $podcast{'dumpfile'}, $podcast{'destfile'};

		# remove the dump file
		unlink $podcast{'dumpfile'};

		# use MP3::ID3v1Tag to set Name, source, description, title, artist, etc.
		MyPodcasts->add_ID3_tag( $podcast, $daysago );
	}
	elsif ( defined $pid ) {
		# child
		my @cmd = ( qw( /usr/bin/mplayer -really-quiet -msglevel all=-1 -dumpstream -dumpfile ),
			$podcast{'dumpfile'},
			$podcast{'source'},
		);
		exec( @cmd ) || die "failed to capture stream: $!\n";
	}
	else {
		# error
		die "Failed to fork(): $!\n";
	}
}

sub build_feed {
	my $podcast = shift;

	die "cannot build feed for $podcast{'name'}: $podcast{'dumpfile'} does not exist\n"
			unless (-e qq|$ENV{HOME}/podcasts/$podcast/$podcast{'filename'}|);

	# update the RSS file
	MyPodcasts->buildRSS($podcast, $daysago);
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
