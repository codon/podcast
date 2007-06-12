#! /usr/bin/perl

use strict;
use warnings;

use Getopt::Long;

use MyPodcasts;

my ($podcast, $list);

GetOptions(
	"podcast=s" => \$podcast,
	"list"      => \$list,
);

if ( $list ) {
	print "Known Podcasts: \n\t".join("\n\t", MyPodcasts->listPodcasts())."\n";
	exit(0);
}

warn "looking up $podcast\n";
my %podcast = ($podcast) ? MyPodcasts->getConfig( $podcast ) : ();

die "$podcast: invalid podcast\n" unless $podcast{'source'};


if ( my $pid = fork() ) {
	# parent
	sleep( $podcast{'duration'} + 5 ); # Add promo time
	kill 'INT', $pid;
	
	# XXX: This is temporary!
	rename $podcast{dumpfile}, "podcasts/$podcast{filename}";

	# TBD: use MP3::ID3v1Tag to set Name, source, description, title, artist, etc.
	# TBD: need to post dump file to appropriate blog
	# TBD: remove dumpfile
}
elsif ( defined $pid ) {
	# child
	my @cmd = ( qw( /usr/bin/mplayer -msglevel all=-1 -dumpstream -dumpfile ),
		$podcast{'dumpfile'},
		$podcast{'source'},
	);
	warn join(' ',@cmd);
	exec( @cmd ) || die "failed to capture stream: $!\n";
}
else {
	# error
	die "Failed to fork(): $!\n";
}

exit(0);
