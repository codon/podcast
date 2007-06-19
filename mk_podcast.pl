#! /usr/bin/perl

use strict;
use warnings;

use Getopt::Long;

use MP3::ID3v1Tag;
#use XML::RSS;
#use MP3::Tag;
#see source for MP3::Podcast for some usage pointers

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
	
	# use MP3::ID3v1Tag to set Name, source, description, title, artist, etc.
	my $mp3_file = new MP3::ID3v1Tag($podcast{dumpfile});
	$mp3_file->set_title($podcast{title});
	$mp3_file->set_artist($podcast{artist});
	$mp3_file->set_album($podcast{name});
	$mp3_file->set_comment($podcast{source});
	$mp3_file->set_genre('Podcast');
	$mp3_file->save();

	# TBD: need to post dump file to appropriate blog
	# TBD: remove dumpfile
	# XXX: This is temporary!
	rename $podcast{dumpfile}, "podcasts/$podcast{filename}";
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
