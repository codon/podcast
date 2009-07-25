package MyPodcasts;

use strict;
use warnings;

use XML::RSS;
use MP3::Tag;
use LWP::Simple;
use Lingua::EN::NameCase qw( nc ) ;

use constant 'MIN'  => 60          ; # seconds in an minute
use constant 'HRS'  => 60 * 60     ; # seconds in an hour
use constant 'DAYS' => 60 * 60 * 24; # seconds in a day

{
	( my $conf_dir = __FILE__ ) =~ s/\.pm$//;
	my $config = {};
	eval {
		if ( -d $conf_dir && -r $conf_dir ) {
			opendir my $dir, $conf_dir or die "cannot open $conf_dir: $!\n";
			for my $file ( grep { -f "$conf_dir/$_" } readdir $dir ) {
				my $tmp_config = do "$conf_dir/$file";

				if ( defined $tmp_config and not ( ref($tmp_config) eq 'HASH' ) ) {
					warn "$conf_dir/$file: invalid podcast file\n";
					next;
				}

				$config->{ $file } = $tmp_config;
			}
		}
	};
	if ($@) {
		warn "WARNING: $@\n";
		$config = {};
	}

	my %month = (
		0  => undef,
		1  => 'January',
		2  => 'February',
		3  => 'March',
		4  => 'April',
		5  => 'May',
		6  => 'June',
		7  => 'July',
		8  => 'August',
		9  => 'September',
		10 => 'October',
		11 => 'November',
		12 => 'December',
	);
	my %day = (
		0 => 'Sun',
		1 => 'Mon',
		2 => 'Tue',
		3 => 'Wed',
		4 => 'Thu',
		5 => 'Fri',
		6 => 'Sat',
	);

	sub getConfig {
		my ($pkg, $podcast, $daysago) = (@_,0);

		my %config = %{ $config->{$podcast} };

		my ($mday,$mon,$year) = (localtime(time() - ($daysago * DAYS)))[3 .. 5];
		$mon++; $year+=1900;

		$config{'title'}    = sprintf('%s for %s %02d, %4d',$config{'name'},$month{$mon},$mday,$year);
		$config{'filename'} = sprintf('%s-%4d-%02d-%02d.mp3',$config{'name'},$year,$mon,$mday);
		$config{'filename'} =~ s/\s+/_/g;
		$config{'dumpfile'} = "/tmp/$config{filename}";
		$config{'rss_file'} = "$ENV{HOME}/podcasts/$podcast.xml";
		$config{'destfile'} = "$ENV{HOME}/podcasts/$podcast/$config{'filename'}";

		return %config;
	}

	sub listPodcasts {
		return keys %$config;
	}

	sub buildRSS {
		my ($pkg, $podcast, $daysago) = @_;

		my %config = $pkg->getConfig( $podcast, $daysago );

		my $rss = XML::RSS->new( version => '2.0' );
		$rss->add_module(
			prefix   => 'itunes',
			uri      => 'http://www.itunes.com/dtds/podcast-1.0.dtd',
			version  => '2.0',
		);

		if ( -e $config{'rss_file'} and -s $config{'rss_file'} > 0 ) {
			link( $config{'rss_file'}, "$config{'rss_file'}.bak" );
			$rss->parsefile($config{'rss_file'});
			if (@{$rss->{'items'}} == 5) {
				my $last_item = pop(@{$rss->{'items'}});
				my $url = $last_item->{'enclosure'}->{'url'} || '';
				$url =~ s[^http://example\.com/][];
				unlink "$ENV{HOME}/$url" if ($url);
			}
		}
		else {
			$rss->channel(
				title          => $config{'name'},
				link           => $config{'home_page'},
				language       => 'en-us',
				itunes         => { map { $_ => $config{$_} } qw( subtitle summary author ) },
				description    => $config{'description'},
				copyright      => $config{'copyright'},
			);
		}

		my $size = (stat $config{'destfile'})[7];
		my %extraction = $config{'extract'}->( $config{'home_page'} );
		$extraction{'duration'} = _estimate_duration( $size );
		my $description = delete $extraction{'summary'};
		$rss->add_item(
			title       => $extraction{'title'} || $extraction{'subtitle'},
			itunes      => { %extraction },
			description => $description,
			category    => 'podcasts',
			enclosure   => {
				'url'    => sprintf('http://example.com/podcasts/%s/%s',$podcast,$config{'filename'}),
				'type'   => "audio/mpeg",
				'length' => $size,
			},
			mode        => 'insert',
		);

		if (scalar @{ $rss->{'items'} || [] } > 1  and
			length($rss->{'items'}[0]{'itunes'}{'summary'}) > 0 and
			$rss->{'items'}[0]{'itunes'}{'summary'} eq $rss->{'items'}[1]{'itunes'}{'summary'}
		) {
			die "$config{'home_page'} has not been updated\n";
		}

		eval {
			$rss->save($config{'rss_file'});
		};

		if ($@) {
			warn $@;
			if ( -e "$config{'rss_file'}.bak" ) {
				rename( "$config{'rss_file'}.bak", $config{'rss_file'} );
			}
		}
		else {
			if ( -e "$config{'rss_file'}.bak" ) {
				unlink( "$config{'rss_file'}.bak" );
			}
		}

		return;
	}

	sub add_ID3_tag {
		my ($pkg, $podcast, $daysago) = @_;

		my %config = $pkg->getConfig( $podcast, $daysago );

		my $mp3_file = MP3::Tag->new($config{destfile}) || die "could not instatiate MP3::Tag: $!";
		my $id3v2 = $mp3_file->new_tag('ID3v2');
		$id3v2->add_frame('TIT1','Podcast');
		$id3v2->add_frame('TIT2',$config{title});
		$id3v2->add_frame('TPOE',$config{artist});
		$id3v2->write_tag();

		return;
	}

	sub get_pubDate {
		my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime;
		# pubDate should be of the format: Sat, 9 Jun 2007 17:00:00 -0700
		return sprintf('%3s, %d %s %4d %02d:%02d:%02d -0700',
			$day{$wday}, $mday, $month{++$mon}, ($year + 1900), $hour, $min, $sec );
	}
}

sub _estimate_duration {
	my $size = shift;
	my $duration = ($size * 8) / (128 * 1024);
	(my $hours, $duration) = ( ($duration / ( HRS )), ($duration % ( HRS )) );
	(my $minutes, $duration) = ( ($duration / ( MIN )), ($duration % ( MIN )) );
	return sprintf( '%02d:%02d:%02d', $hours, $minutes, $duration );
}

1;

__END__

=head1 NAME

MyPodcasts - Collects and builds Podcast information into an RSS stream

=head1 SYNOPSIS

	use MyPodcasts;

	my @podcasts = MyPodcasts->listPodcasts();

	my $podcast = MyPodcasts->getConfig('foo');

	MyPodcasts->add_ID3_tag($podcast);

	MyPodcasts->buildRSS( $podcast );

=head1 DESCRIPTION

	The main part of this module is it's config hash. It contains pieces of information to extract the
	description information from a radio show's website and build a valid iTunes podcast feed. The value
	of the 'extract' key must be an anonymous subroutine. All other values should be scalars.

=cut
