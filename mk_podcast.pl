#! /usr/bin/perl

use strict;
use warnings;

use Getopt::Long;
use Time::HiRes qw( time sleep );

use MyPodcasts;

my ($podcast, $capture, $feed, $list) = (undef, 1, 1, undef);

GetOptions(
	"podcast=s" => \$podcast,
	"capture!"  => \$capture,
	"feed!"     => \$feed,
	"list"      => \$list,
);

if ( $list ) {
	print "Known Podcasts: \n\t".join("\n\t", MyPodcasts->listPodcasts())."\n";
	exit(0);
}

# look up podcast in MyPodcasts
my %podcast = ($podcast) ? MyPodcasts->getConfig( $podcast ) : ();

die "$podcast: invalid podcast\n" unless $podcast{'source'};

capture_stream($podcast) if ($capture);
build_feed(    $podcast) if ($feed);

exit(0);

sub capture_stream {
	if ( my $pid = fork() ) {
		# parent
		my $start_time = time;
		sleep( $podcast{'duration'} - (time() - $start_time) );
		kill 'INT', $pid;

		# use MP3::ID3v1Tag to set Name, source, description, title, artist, etc.
		MyPodcasts->add_ID3_tag( $podcast );
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
	die "cannot build feed for $podcast{'name'}: $podcast{'dumpfile'} does not exist\n"
			unless (-e $podcast{'dumpfile'});

	# move dump file to appropriate destination
	mkdir qq|$ENV{HOME}/podcasts/$podcast| unless ( -d qq|$ENV{HOME}/podcasts/$podcast| );
	link $podcast{'dumpfile'}, qq|$ENV{HOME}/podcasts/$podcast/$podcast{'filename'}|;

	# update the RSS file
	MyPodcasts->buildRSS($podcast);

	# remove the dump file
	unlink $podcast{'dumpfile'};
}

