package Pisg;

# Documentation(POD) for this module is found at the end of the file.

# Copyright (C) 2001-2012  The pisg project
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA

use strict;
$^W = 1;

sub new
{
    my $type = shift;
    my %args = @_;
    my $self = {
        override_cfg => $args{override_cfg},
        use_configfile => $args{use_configfile},
        search_path => $args{search_path},
        chans => [],
        users => {},
        cfg => {},
        tmps => {},
    };

    # Set the default configuration settings.
    get_default_config_settings($self);

    # Import common functions in Pisg::Common
    require Pisg::Common;
    Pisg::Common->import();

    bless($self, $type);
    return $self;
}

sub run
{
    my $self = shift;

    print "pisg v$self->{cfg}->{version} - Perl IRC Statistics Generator\n\n"
        unless ($self->{cfg}->{silent});

    # Init the configuration file (aliases, ignores, channels, etc)
    my $r;
    if ($self->{use_configfile}) {
        foreach my $c ($self->{cfg}->{configfile}, $self->{search_path} . "/$self->{cfg}->{configfile}") {
            if (open(CONFIG, $c)) {
                $self->{cfg}->{configfile} = $c;
                print "Using config file: $self->{cfg}->{configfile}\n\n"
                    unless ($self->{cfg}->{silent});
                $r = $self->init_config(\*CONFIG);
                last;
            } else {
                print STDERR "Warning: $c: $!\n\n" if -e $c;
            }
        }
    }

    # Get translations from langfile
    $self->get_language_templates();

    # Parse any channels in <channel> statements
    $self->parse_channels();

    # Optionaly parse the channel we were given in override_cfg.
    $self->do_channel()
        if (!$self->{cfg}->{chan_done}{$self->{cfg}->{channel}});

}

sub get_default_config_settings
{
    my $self = shift;

    # This is all the default settings of pisg. They can be overriden by the
    # pisg.cfg file, or by using the override_cfg argument to the new
    # constructor.

    $self->{cfg} = {
        channel => '',
        logtype => 'Logfile',
        logfile => [],
        format => '',
        network => 'SomeIRCNet',
        outputfile => 'index.html',
        outputtag => '',
        maintainer => 'MAINTAINER',
        pagehead => 'none',
        pagefoot => 'none',
        configfile => 'pisg.cfg',
        imagepath => '',
        imageglobpath => '',
        defaultpic => '',
        logdir => [],
        nfiles => 0,
        lang => 'EN',
        langfile => 'lang.txt',
        cssdir => 'layout/',
        colorscheme => 'default',
        altcolorscheme => 'none',
        logprefix => '',
        logsuffix => '',
        silent => 0,
        cachedir => '',
        channelindex => 'channels.json',
        userpics => 'y',

        # Colors / Layout

        hicell => '#BABADD', # FIXME 
        hicell2 => '#CCCCCC', # FIXME

        picwidth => '',
        picheight => '',

        pic_v_0 => 'blue-v',
        pic_v_6 => 'green-v',
        pic_v_12 => 'yellow-v',
        pic_v_18 => 'red-v',
        pic_h_0 => 'blue-h',
        pic_h_6 => 'green-h',
        pic_h_12 => 'yellow-h',
        pic_h_18 => 'red-h',
        piclocation => '.',

        # Stats settings

        showactivetimes => 1,
        showactivenicks => 1,
        showbignumbers => 1,
        showtopics => 1,
        showlinetime => 0,
        showwordtime => 0,
        showlines => 1,
        showtime => 1,
        showwords => 0,
        showwpl => 0,
        showcpl => 0,
        showlastseen => 1,
        showlegend => 1,
        showkickline => 1,
        showactionline => 1,
        showfoulline => 0,
        showfouldecimals => 1,
        showshoutline => 1,
        showviolentlines => 1,
        showrandquote => 1,
        showmuw => 1,
        showmrn => 1,
        showsmileys => 0,
        showkarma => 0,
        showmru => 1,
        showcharts => 0,
        showops => 1,
        showvoices => 0,
        showhalfops => 0,
        showmostnicks => 0,
        showactivegenders => 0,
        showmostactivebyhour => 0,
        showmostactivebyhourgraph => 1,
        showonlytop => 0,

        # Less important things

        timeoffset => '+0',
        minquote => 25,
        maxquote => 65,
        quotewidth => 80,
        bignumbersthreshold => 'sqrt',
        wordlength => 5,
        dailyactivity => 0,
        activenicks => 25,
        activenicks2 => 30,
        activenicksbyhour => 10,
        topichistory => 3,
        urlhistory => 5,
        chartshistory => 5,
        nickhistory => 5,
        smileyhistory => 10,
        karmahistory => 5,
        wordhistory => 10,
        mostnickshistory => 5,
        mostnicksverbose => 1,
        nicklimit => 10,
        nicktracking => 0,
        charset => 'iso-8859-1',
        logcharset => '',
        logcharsetfallback => '',

        # sorting
        sortbywords => 0,

        # Misc settings

        foulwords => 'ass fuck bitch shit scheisse scheiße kacke arsch ficker ficken schlampe',
        violentwords => 'slaps beats smacks',
        chartsregexp => '(?:is )?(?:np:|(?:now )?playing:? |listening to:? )(?:MPEG stream from)?\s*(.*)',
        ignorewords => '',
        badurls => '',
        shownavbar => 1,
        homelink => '',
        showoverview => 1,
        showrelations => 1,
        relationnicks => 30,
        relationminweight => 3,
        showtimepersonalities => 1,
        showconcentration => 1,
        showsignaturewords => 1,
        noignoredquotes => 0,
        tablewidth => 574,
        regexpaliases => 0,

        botnicks => '',            # Needed for DCpp format (non-irc)

        statsdump => '',           # Debug option
        modules_dir => '',         # set in get_cmdline_options
        cchannels => '',           # set in get_cmdline_options

        version => "1.0a"
    };

    # This enables us to use the search_path in other modules
    $self->{cfg}->{search_path} = $self->{search_path};

    # Parse the optional overriden configuration variables
    foreach my $key (keys %{$self->{override_cfg}}) {
        if ($self->{override_cfg}->{$key}) {
            unless (defined($self->{cfg}->{$key})) {
                print STDERR "Warning: No such configuration option: -cfg $key\n";
                next;
            }
            $self->{cfg}->{$key} = $self->{override_cfg}->{$key};
        }
    }
}

sub get_language_templates
{
    my $self = shift;

    open(FILE, $self->{cfg}->{langfile}) or open (FILE, $self->{search_path} . "/$self->{cfg}->{langfile}") or die("$0: Unable to open language file($self->{cfg}->{langfile}): $!\n");

    while (my $line = <FILE>)
    {
        next if ($line =~ /^#/);

        if ($line =~ /<lang name=\"([^"]+)\"(?: charset=\"(.*)\")?>/i) {
            # Found start tag, setting the current language
            my $current_lang = uc($1);
            $self->{tmps}->{$current_lang}{lang_charset} = lc($2);

            while (<FILE>) {
                next if ($_ =~ /^#/);
                last if ($_ =~ /<\/lang>/i);

                # Get 'template = "Text"' in language file:
                if ($_ =~ /^(\w+)\s*=\s*"(.*)"\s*$/) {
                    warn "duplicate translation $1 -> $2"
                        if $self->{tmps}->{$current_lang}{$1} and !$self->{cfg}->{silent};
                    $self->{tmps}->{$current_lang}{$1} = $2;
                }
            }

        }

    }

    close(FILE);
}

sub init_config
{
    my $self = shift;
    my $fh   = shift;
    while (my $line = <$fh>)
    {
        next if ($line =~ /^\s*#/);
        chomp $line;

        if ($line =~ /<user.*>/) {
            my $nick;

            if ($line =~ /\bnick=(["'])(.+?)\1/) {
                $nick = $2;
                add_alias($nick, $nick);
            } else {
                print STDERR "Warning: $self->{cfg}->{configfile}, line $.: No nick specified\n";
                next;
            }

            if ($line =~ /\balias=(["'])(.+?)\1/) {
                my @thisalias = split(/\s+/, lc($2));
                foreach (@thisalias) {
                    if ($self->{cfg}->{regexpaliases} and /[\|\[\]\{\}\(\)\?\+\.\*\^\\]/) {
                        add_aliaswild($nick, $_);
                    } elsif (not $self->{cfg}->{regexpaliases} and s/\*/\.\*/g) {
                        # quote it if it is a wildcard
                        s/([\|\[\]\{\}\(\)\?\+\^\\])/\\$1/g;
                        add_aliaswild($nick, $_);
                    } else {
                        add_alias($nick, $_);
                    }
                }
            }

            if ($line =~ /\bpic=(["'])(.+?)\1/) {
                $self->{users}->{userpics}{$nick} = $2;
            }

            if ($line =~ /\bbigpic=(["'])(.+?)\1/) {
                $self->{users}->{biguserpics}{$nick} = $2;
            }

            if ($line =~ /\blink=(["'])(.+?)\1/) {
                $self->{users}->{userlinks}{$nick} = $2;
            }

            if ($line =~ /\bignore=(["'])Y\1/i) {
                add_ignore($nick);
            }

            if ($line =~ /\bsex=(["'])([MmFfBb])\1/) {
                $self->{users}->{sex}{$nick} = lc($2);
            }
        } elsif ($line =~ /<link(.*)>/) {

            if ($line =~ /\burl=(["'])(.+?)\1/) {
                my $url = $2;
                if ($line =~ /ignore="Y"/i) {
                    add_url_ignore($url);
                }
            } else {
                print STDERR "Warning: $self->{cfg}->{configfile}, line $.: No URL specified\n";
            }


        } elsif ($line =~ /<set(.*)>/) {

            my $settings = $1;
            if ($settings !~ /=["'](.*)["']/ || $settings =~ /(\w)>/ ) {
                print STDERR "Warning: $self->{cfg}->{configfile}, line $.: Missing or wrong quotes near $1\n";
            }

            while ($settings =~ s/[ \t]([^=]+?)=(["'])(.*?)\2//) {
                my $var = lc($1);
                my $val = $3;
                $var =~ s/ //; # Remove whitespace

                if (!defined($self->{cfg}->{$var})) {
                    print STDERR "Warning: $self->{cfg}->{configfile}, line $.: No such configuration option: '$var'\n";
                    next;
                }

                unless (($self->{cfg}->{$var} eq $val) || $self->{override_cfg}->{$var}) {
                    $self->{cfg}->{$var} = $val;
                }
            }

        } elsif ($line =~ /<channel=(['"])(.+?)\1(.*)>/i) {
            my ($channel, $settings, $tmp) = ($2, $3, {});
            $tmp->{$channel}->{channel} = $channel;
            $self->{cfg}->{chan_done}{$self->{cfg}->{channel}} = 1; # don't parse channel in $self->{cfg}->{channel} if a channel statement is present
            while ($settings =~ s/\s([^=]+)=(["'])(.*?)\2//) {
                my $var = lc($1);
                my $val = $3;
                if ($var eq "logdir" || $var eq "logfile") {
                    push(@{$tmp->{$channel}{$var}}, $val);
                } else {
                    $tmp->{$channel}{$var} = $val;
                }
            }
            while (<$fh>) {
                next if /^\s*#/;
                if ($_ =~ /<\/*channel>/i) {
                    push @{ $self->{chans} }, $tmp;
                    last;
                }
                if ($_ =~ /^\s*(\w+)\s*=\s*(["'])(.*?)\2/) {
                    my $var = lc($1);
                    my $val = $3;
                    unless ((($var eq "logdir" || $var eq "logfile") && scalar(@{$self->{override_cfg}->{$var}}) > 0) || (($var ne "logdir" && $var ne "logfile") && $self->{override_cfg}->{$var})) {

                        if($var eq "logdir" || $var eq "logfile") {
                            push @{$tmp->{$channel}{$var}}, $val;
                        } else {
                            $tmp->{$channel}{$var} = $val;
                        }

                    }
                } elsif ($_ !~ /^$/) {
                    print STDERR "Warning: $self->{cfg}->{configfile}, line $.: Unrecognized line: $_";
                }
            }
        } elsif ($line =~ /<include\s*=\s*(["'])(.+?)\1\s*>/) {
            my $include_cfg = $2;
            my $backup_cfg = $self->{cfg}->{configfile};
            $self->{cfg}->{configfile} = $include_cfg;
            my $r;
            foreach my $c ($self->{cfg}->{configfile}, $self->{search_path} . "/$self->{cfg}->{configfile}") {
                if (open(INCLUDE, $c)) {
                    $self->{cfg}->{configfile} = $c;
                    $r = $self->init_config(\*INCLUDE);
                    last;
                } else {
                    print STDERR "Warning: $backup_cfg, line $.: $c: $!\n"
                        if -e $c;
                }
            }
            print "Included config file: $self->{cfg}->{configfile}\n\n"
                if ($r && !$self->{cfg}->{silent});
            print STDERR "Warning: $backup_cfg, line $.: $self->{cfg}->{configfile} not found\n"
                if (!$r);
            $self->{cfg}->{configfile} = $backup_cfg;
        } elsif ($line =~ /<(\w+)?.*[^>]$/) {
            print STDERR "Warning: $self->{cfg}->{configfile}, line $.: Missing end on element <$1 (probably multi-line?)\n";
        } elsif ($line =~ /\S/) {
            $line =~ s/\n//;
            print STDERR "Warning: $self->{cfg}->{configfile}, line $.: Unrecognized line: $line\n";
        }
    }

    close($fh);
}

sub init_pisg
{
    my $self = shift;

    my $timestamp = time();
    $self->{cfg}->{start} = time();

    if ($self->{cfg}->{timeoffset} =~ /\+(\d+)/) {
        # We must plus some hours to the time
        $timestamp += 3600 * $1; # 3600 seconds per hour

    } elsif ($self->{cfg}->{timeoffset} =~ /-(\d+)/) {
        # We must remove some hours from the time
        $timestamp -= 3600 * $1; # 3600 seconds per hour
    }
    $self->{cfg}->{timestamp} = $timestamp;

    # convert wordlists
    $self->{cfg}->{foulwords} = wordlist_regexp($self->{cfg}->{foulwords}, $self->{cfg}->{regexpaliases});
    $self->{cfg}->{ignorewords} = wordlist_regexp($self->{cfg}->{ignorewords}, $self->{cfg}->{regexpaliases});
    $self->{cfg}->{violentwords} = wordlist_regexp($self->{cfg}->{violentwords}, $self->{cfg}->{regexpaliases});

    # Add trailing slash when it's not there..
    $self->{cfg}->{imagepath} =~ s/([^\/])$/$1\//;
    # Set ImageGlobPath default
    $self->{cfg}->{imageglobpath} ||= $self->{cfg}->{imagepath};
    $self->{cfg}->{imageglobpath} =~ s/([^\/])$/$1\//;

    # Set number of picture columns to show
    if ($self->{cfg}->{userpics} =~ /^n/i) {
        $self->{cfg}->{userpics} = 0;
    } elsif ($self->{cfg}->{userpics} =~ /^y/i) {
        $self->{cfg}->{userpics} = 1;
    } elsif ($self->{cfg}->{userpics} !~ /^\d+$/) {
        print STDERR "Warning: $self->{cfg}->{configfile}, line $.: Invalid UserPics setting\n";
    }

    unless ($self->{cfg}->{silent}) {
        print "Statistics for channel $self->{cfg}->{channel} \@ $self->{cfg}->{network} by $self->{cfg}->{maintainer}\n\n";
    }
}

sub do_channel
{
    my $self = shift;
    if (!$self->{cfg}->{channel}) {
        print STDERR "No channels defined.\n";
    } elsif ((!@{$self->{cfg}->{logfile}}) && (!@{$self->{cfg}->{logdir}})) {
        print STDERR "No logfile or logdir defined for " . $self->{cfg}->{channel} . "\n";
    } elsif (!$self->{cfg}->{format}) {
        print STDERR "No format defined for $self->{cfg}->{channel}.\n";
    } else {
        $self->init_pisg();        # Init some general things

        $self->{aliases_stored} = 1;
        store_aliases();           # Save the aliases so we can restore them
                                   # later, we don't want to add the aliases
                                   # for this channel to the next channel

        # Pick our stats generator.
        my $analyzer;
        eval <<_END;
use Pisg::Parser::$self->{cfg}->{logtype};
\$analyzer = new Pisg::Parser::$self->{cfg}->{logtype}(
    { cfg => \$self->{cfg}, users => \$self->{users} }
);
_END
        if ($@) {
            print STDERR "Could not load stats analyzer for '$self->{cfg}->{logtype}': $@\n";
            return undef;
        }

        my $stats = $analyzer->analyze();
        $self->{cfg}->{analyzer} = $analyzer; # we need the parser in _format_line

        # Initialize HTMLGenerator object
        my $generator;
        eval <<_END;
use Pisg::HTMLGenerator;
\$generator = new Pisg::HTMLGenerator(
    cfg => \$self->{cfg},
    stats => \$stats,
    users => \$self->{users},
    tmps => \$self->{tmps}
);
_END

        if ($@) {
            print STDERR "Could not load stats generator (Pisg::HTMLGenerator): $@\n";
            return undef;
        }

        # Create our HTML page if the logfile has any data.
        if (defined $stats) {
            if ($stats->{parsedlines} > 0) {
                foreach my $lang (split /\s*,\s*/, uc $self->{cfg}->{lang}) {
                    $lang =~ s/-/_/g; # PT_BR was called PT-BR before
                    die sprintf "No such language: %s\n", $_ unless $self->{tmps}->{$lang};
                    $generator->create_output($lang);
                }
            } else {
                print STDERR <<_END unless $self->{cfg}->{silent};
No parseable lines found in logfile ($stats->{totallines} total lines). Skipping.
-> You might be using the wrong format.
-> A common error is that the logs do not contain timestamps for each line.
_END
            }
        }

        restore_aliases();
        $self->{aliases_stored} = 0;

        $self->{cfg}->{chan_done}{$self->{cfg}->{channel}} = 1;
    }
}

sub parse_channels
{
    my $self = shift;
    my %origcfg = %{ $self->{cfg} };
    
    # make a list of channels to do
    my @chanlist;
    if (scalar @ {$self->{cfg}->{cchannels} } > 0) {
        foreach my $channel (@{ $self->{cfg}->{cchannels} }) {
            my $hits = 0;
            foreach ( @{ $self->{chans} }) {
                my $chan = (keys %{ $_ })[0];
                if (lc($channel) eq lc($chan)) {
                    push @chanlist, $_;
                    $hits++;
                }
            }
            if ($hits < 1) {
                print STDERR "Channel $channel not in config file, ignoring\n";
            }
        }
    } else {
        push @chanlist, $_ foreach (@{ $self->{chans} });
    }

    foreach my $channel (@chanlist) {
        foreach my $chan (keys %{ $channel }) { # import channel specific config
            $self->{cfg}->{$_} = $channel->{$chan}->{$_} foreach (keys %{ $channel->{$chan} });
        }
        # One channel that cannot be read (a missing log folder, a bad format) must not stop the others:
        # say so, carry on, and let the exit status tell cron that something failed.
        my $name = $self->{cfg}->{channel};
        unless (eval { $self->do_channel(); 1 }) {
            my $why = $@; $why =~ s/\s+$//;
            print STDERR "Skipped channel $name: $why\n";
            $self->{failed_channels}++;
            restore_aliases() if $self->{aliases_stored};
            $self->{aliases_stored} = 0;
        }
        $origcfg{chan_done} = $self->{cfg}->{chan_done};
        %{ $self->{cfg} } = %origcfg;
    }
}

1;

__END__

=head1 NAME

Pisg - Perl IRC Statistics Generator main module

=head1 SYNOPSIS

    use Pisg;

    $pisg = new Pisg(
        use_configfile => '1',
        override_cfg => { network => 'MyNetwork', format => 'eggdrop' }
    );

    $pisg->run();

=head1 DESCRIPTION

C<Pisg> is a statistic generator for IRC logfiles or the like, delivering
the results in a HTML page.

=head1 CONSTRUCTOR

=over 4

=item new ( [ OPTIONS ] )

This is the constructor for a new Pisg object. C<OPTIONS> are passed in a hash like fashion, using key and value pairs.

Possible options are:

B<use_configfile> - When set to 1, pisg will look up it's channels in it's
configuration file, defined by the configuration option 'configfile'.

B<override_cfg> - This defines whichever configuration variables you want to
override from the configuration file. If you set use_configfile to 0, then
you'll have to set at least channel and logfile here.

B<search_path> - This defines an optional search path. It's used when you want to hardcode an alternative path where pisg should look after its language and config file.

=back

=head1 AUTHOR

Morten Brix Pedersen <morten@wtf.dk>
Christoph Berg <cb@df7cb.de>
James "HM2K" <james@hm2k.org>

=head1 COPYRIGHT

Copyright (C) 2001-2012 The pisg project. All rights reserved.
This program is free software; you can redistribute it and/or modify it
under the terms of the GPL, license is included with the distribution of
this file.

=cut
