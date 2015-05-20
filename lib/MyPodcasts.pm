package MyPodcasts;

use strict;
use warnings;

use File::Copy;

use XML::RSS;
use MP3::Tag;
use LWP::Simple qw(get);
use Lingua::EN::NameCase qw( nc ) ;
use File::Path qw(mkpath);

use constant 'MIN'  => 60          ; # seconds in an minute
use constant 'HRS'  => 60 * 60     ; # seconds in an hour
use constant 'DAYS' => 60 * 60 * 24; # seconds in a day

our %month = ( 0  => undef,
    1  => 'January', 2  => 'February', 3  => 'March', 4  => 'April', 5  => 'May', 6  => 'June',
    7  => 'July', 8  => 'August', 9  => 'September', 10 => 'October', 11 => 'November', 12 => 'December',
);
our %day = ( 0 => 'Sun', 1 => 'Mon', 2 => 'Tue', 3 => 'Wed', 4 => 'Thu', 5 => 'Fri', 6 => 'Sat' );

sub new {
    my($class, @args) = @_;
    my $self = bless {@args}, $class;
    $self->{'config'} = $self->_find_confs();
    $self->{'daysago'} ||= 0; # default to today (now);
    $self->{'basedir'} ||= "$ENV{HOME}/podcasts";
    $self->{'baseurl'} ||= 'http://example.com/podcasts';

    if ( defined $self->{'podcast'} and exists $self->{'config'}{ $self->{'podcast'} } ) {
        my %config = $self->get_Config();
        @$self{keys %config} = values %config;
    }
    return $self;
}

sub _parse_conf {
    my ( $self, $file ) = @_;

    my $config = eval {
        unless ( -e $file ) {
            warn "$file: no known podcast matches that name\n";
            return;
        }

        my $tmp_config = do "$file";

        if ( defined $tmp_config and not ( ref($tmp_config) eq 'HASH' ) ) {
            warn "$file: invalid podcast file\n";
            return;
        }

        return $tmp_config;
    };
    if ($@) {
        warn "WARNING: $@\n";
        $config = {};
    }

    return $config;
}

sub _find_confs {
    my ( $self ) = @_;

    # currently confs are in a MyPodcasts dir beside this file
    ( my $conf_dir = __FILE__ ) =~ s/\.pm$//;

    my %kampf;
    if ( -d $conf_dir && -r $conf_dir ) {
        opendir my $dir, $conf_dir or die "cannot open $conf_dir: $!\n";
        %kampf =
            map  { @$_ }                      # expand the transform into a hash
            grep { -f $_->[1] }               # make sure that it is a file
            map  { [ $_ => "$conf_dir/$_" ] } # use the Shwartz(-ian transform)
            grep { /^\w/ }                    # require conf filenames to start with a word character
            readdir $dir;                     # get everything in the confdir
    }

    return \%kampf
}

sub get_Config {
    my ($self) = (@_);

    # if we didn't get a podcast name, we can't really come up with its config
    my $podcast = $self->{'podcast'} || return;

    # skip this work if we've already parsed this config
    return ( %{ $self->{'config'}{$podcast} } ) if ( ref( $self->{'config'}{$podcast} ) );

    # If we don't know what you're talking about, we can't help you
    my $file = $self->{'config'}{$podcast} || return;
    my $config = $self->_parse_conf( $file );

    my ($mday,$mon,$year) = (localtime(time() - ($self->{'daysago'} * DAYS)))[3 .. 5];
    $mon++; $year+=1900;

    $config->{'title'}    = sprintf('%s for %s %02d, %4d', $config->{'name'},$month{$mon},$mday,$year);
    $config->{'filename'} = sprintf('%s-%4d-%02d-%02d.mp3',$config->{'name'},$year, $mon, $mday);
    $config->{'filename'} =~ s/\s+/_/g;
    $config->{'rss_file'} = "$self->{'basedir'}/$podcast.xml";
    $config->{'destfile'} = "$self->{'basedir'}/$podcast/$config->{'filename'}";

    # Ensure the destination dir exists
    mkpath( "$self->{'basedir'}/$podcast" ) unless ( -d "$self->{'basedir'}/$podcast" );

    $self->{'config'}{$podcast} = $config;
    return %$config;
}

sub list {
    return keys %{ $_[0]->{'config'} };
}

sub build_RSS {
    my ($self) = @_;

    my %config = $self->get_Config();

    my $rss = XML::RSS->new( version => '2.0' );
    $rss->add_module(
        prefix   => 'itunes',
        uri      => 'http://www.itunes.com/dtds/podcast-1.0.dtd',
        version  => '2.0',
    );

    if ( -e $config{'rss_file'} and -s $config{'rss_file'} > 0 ) {
        copy( $config{'rss_file'}, "$config{'rss_file'}.bak" );
        $rss->parsefile($config{'rss_file'});
        if (@{$rss->{'items'}} == 5) {
            my $last_item = pop(@{$rss->{'items'}});
            my $url = $last_item->{'enclosure'}->{'url'} || '';
            $url =~ s[^$self->{'baseurl'}][$self->{'basedir'}/];
            if ( -e $url ) {
                unlink $url || warn "failed to unlink '$url': $!\n";
            }
            else {
                warn "cannot unlink '$url': path does not exist\n";
            }
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
    my %extraction = $config{'extract'}->( $self, $config{'home_page'} ); # fake an OO call
    $extraction{'duration'} = _estimate_duration( $size );
    my $description = delete $extraction{'summary'};
    $rss->add_item(
        title       => $extraction{'title'} || $extraction{'subtitle'},
        itunes      => { %extraction },
        description => $description,
        category    => 'podcasts',
        enclosure   => {
            'url'    => sprintf('%s/%s/%s',$self->{'baseurl'},$self->{'podcast'},$config{'filename'}),
            'type'   => "audio/mpeg",
            'length' => $size,
        },
        mode        => 'insert',
    );

    if (scalar @{ $rss->{'items'} || [] } > 1) {
        my ($thing1,$thing2) = map {
            $_->{'itunes'}{'summary'} || $_->{'description'} || ''
        } @{$rss->{'items'}||[]}[0,1];
        if ( length($thing1) > 0 and $thing1 eq $thing2) {
            die "$config{'home_page'} has not been updated\n";
        }
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
    my ($self) = @_;

    my %config = $self->get_Config();

    my $mp3_file = MP3::Tag->new($config{'destfile'}) || die "could not instatiate MP3::Tag: $!";
    my $id3v2 = $mp3_file->new_tag('ID3v2');
    $id3v2->add_frame('TIT1','Podcast');
    $id3v2->add_frame('TIT2',$config{'title'});
    $id3v2->add_frame('TOPE',$config{'artist'});
    $id3v2->write_tag();

    return;
}

sub add_Lyrics {
    my ($file,$lyrics) = @_;

    my $mp3_file = MP3::Tag->new($file) || die "could not instatiate MP3::Tag: $!";
    my $id3v2 = $mp3_file->new_tag('ID3v2');
    $id3v2->add_frame('USLT','ASCII','en-US',$lyrics,$lyrics);
    $id3v2->write_tag();

    return;
}

sub get_pubDate {
    my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime;
    # pubDate should be of the format: Sat, 9 Jun 2007 17:00:00 -0700
    return sprintf('%3s, %d %s %4d %02d:%02d:%02d -0700',
        $day{$wday}, $mday, $month{++$mon}, ($year + 1900), $hour, $min, $sec );
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

    my @podcasts = MyPodcasts->list();

    my $podcast = MyPodcasts->get_Config('foo');

    MyPodcasts->add_ID3_tag($podcast);

    MyPodcasts->buildRSS( $podcast );

=head1 DESCRIPTION

    The main part of this module is it's config hash. It contains pieces of information to extract the
    description information from a radio show's website and build a valid iTunes podcast feed. The value
    of the 'extract' key must be an anonymous subroutine. All other values should be scalars.

=cut
