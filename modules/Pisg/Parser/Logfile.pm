package Pisg::Parser::Logfile;

# Copyright and license, as well as documentation(POD) for this module is
# found at the end of the file.

use strict;
use Encode ();
use Storable;
use Digest::MD5 qw(md5_hex);
use Fcntl qw(:flock);
use File::Spec;

$^W = 1;

# the log cache
use Data::Dumper;
$Data::Dumper::Indent = 1;
my $cache;

# test for Text::Iconv
my $have_iconv = 1;
eval 'use Text::Iconv';
$have_iconv = 0 if $@;

sub new
{
    my $type = shift;
    my $self = shift; # get cfg and users

    # Import common functions in Pisg::Common
    require Pisg::Common;
    Pisg::Common->import();

    bless($self, $type);

    # Pick our parser.
    $self->{parser} = $self->_choose_format($self->{cfg}->{format});

    if($self->{cfg}->{logcharsetfallback} and not $self->{cfg}->{logcharset}) {
        print "LogCharset undefined, assuming LogCharset = LogCharsetFallback\n"
            unless ($self->{cfg}->{silent});
        $self->{cfg}->{logcharset} = $self->{cfg}->{logcharsetfallback};
    }

    if($self->{cfg}->{logcharset}) {
        if($have_iconv) {
            # use converter if charsets differ or there is a fallback charset
            # (in the latter case the converter is also used to test if the
            # line is in the proper charset)
            if(($self->{cfg}->{logcharset} ne $self->{cfg}->{charset}) or $self->{cfg}->{logcharsetfallback}) {
                $self->{iconv} = Text::Iconv->new($self->{cfg}->{logcharset}, $self->{cfg}->{charset});
            }
            if($self->{cfg}->{logcharsetfallback}) {
                $self->{iconvfallback} = Text::Iconv->new($self->{cfg}->{logcharsetfallback}, $self->{cfg}->{charset});
            }
        } else {
            print "Text::Iconv is not installed, skipping charset conversion of logfiles\n"
                unless ($self->{cfg}->{silent});
        }
    }

    # precompile the regexps used (we can't use /o since the config might be different per channel)
    $self->{foulwords_regexp} = qr/($self->{cfg}->{foulwords})/i if $self->{cfg}->{foulwords};
    $self->{ignorewords_regexp} = qr/$self->{cfg}->{ignorewords}/i if $self->{cfg}->{ignorewords};
    # BadUrls: a URL containing any of these words (case-insensitive, anywhere in the
    # URL) is left out of the URL statistics. Everything is literal text except the
    # wildcards * (any characters) and ? (one character), so it is not a regexp.
    my @badurls = grep { length } split(/\s+/, $self->{cfg}->{badurls} || '');
    if (@badurls) {
        my $alt = join '|', map { my $w = quotemeta; $w =~ s/\\\*/.*/g; $w =~ s/\\\?/./g; $w } @badurls;
        $self->{badurls_regexp} = qr/$alt/i;
    }
    # Who talks to whom (relation map, best friends, signature words) needs extra data per
    # line. Only collect it when one of those sections is switched on.
    $self->{rel_on} = ($self->{cfg}->{showrelations} || $self->{cfg}->{showsignaturewords}) ? 1 : 0;
    $self->{violentwords_regexp} = qr/^($self->{cfg}->{violentwords}) (\S+)(.*)/i if $self->{cfg}->{violentwords};
    $self->{chartsregexp} = qr/^$self->{cfg}->{chartsregexp}/i if $self->{cfg}->{chartsregexp};

    return $self;
}

# The function to choose which module to use.
sub _choose_format
{
    my $self = shift;
    my $format = shift;
    $self->{parser} = undef;
    eval <<_END;
use lib '$self->{cfg}->{modules_dir}';
use Pisg::Parser::Format::$format;
\$self->{parser} = new Pisg::Parser::Format::$format(
    cfg => \$self->{cfg},
);
_END
    if ($@) {
        print STDERR "Could not load parser for '$format': $@\n";
        return undef;
    }
    return $self->{parser};
}

sub analyze
{
    my $self = shift;

    unless (defined $self->{parser}) {
        print STDERR "Skipping channel '$self->{cfg}->{channel}' due to lack of parser.\n";
        return undef
    }

    my $starttime = time();

    # HistoryDir: the statistics of every log read so far are kept in a file of their own, so
    # that logs can be deleted without the statistics changing.
    my $history;
    if ($self->{cfg}->{historydir}) {
        $history = $self->_history_open() or return undef;
    }

    my @logfiles = @{$self->{cfg}->{logfile}};
    # expand wildcards
    @logfiles = map { if(/[\[*?]/) { glob; } else { $_; } } @logfiles;

    foreach my $logdir (@{$self->{cfg}->{logdir}}) {
        push @logfiles, $self->_parse_dir($logdir); # get all files in dir
    }

    my $count = @logfiles;
    my $shift = 0;
    if($self->{cfg}->{nfiles} > 0) { # chop list to maximal length
        $shift = @logfiles - $self->{cfg}->{nfiles};
        splice(@logfiles, 0, $shift) if $shift > 0;
    }

    unless ($self->{cfg}->{silent}) {
        my $msg = "";
        $msg = ", parsing the last $self->{cfg}->{nfiles}" if ($shift > 0);
        print "$count logfile(s) found$msg, using $self->{cfg}->{format} format...\n\n"
    }

    my (%stats, %lines);
    %stats = (
        oldtime => 24,
        days => 0,
        lastnick   => '',
        monocount  => 0,
        day_lines => [ undef ],
        day_times => [ undef ],
        parsedlines => 0,
        totallines => 0,
    );
    my %touched;    # words seen in the logs read by this run (see _history_prune)

    if ($history) {
        # start from what earlier runs kept
        %stats = %{ $history->{stats} };
        %lines = %{ $history->{lines} };
        foreach (keys %{$stats{lastvisited}}) {
            find_alias($_);
        }
    }

    if ($self->{cfg}->{cachedir} and not -d $self->{cfg}->{cachedir}) {
        print STDERR "CacheDir \"$self->{cfg}->{cachedir}\" not found. Skipping caching.\n";
        delete $self->{cfg}->{cachedir};
    }

    foreach my $logfile (@logfiles) {
        # Run through the logfile
        print "Analyzing log $logfile... " unless ($self->{cfg}->{silent});

        if ($history) {
            # only what was added to the log since the last run is read
            my ($hs, $hl) = $self->_history_delta($history, $logfile);
            if ($hs) {
                $touched{$_} = 1 foreach keys %{$hs->{wordcounts}};
                $self->_merge_stats(\%stats, $hs);
                $self->_merge_lines(\%lines, $hl);
            }
            print "$stats{days} days, $stats{parsedlines} lines total\n"
                unless ($self->{cfg}->{silent});
            next;
        }

        my $s = {
            oldtime => 24,
            days => 0,
            firsttime => 0,
            lastnick => '',
            parsedlines => 0,
            totallines => 0,
        };
        my $l = {};

        if ($self->{cfg}->{cachedir} and $self->_read_cache(\$s, \$l, $logfile)) {
            # take care of false nicks/words, this only happens with cache
            foreach (keys %{$s->{lastvisited}}) {
                find_alias($_);
            }
        } else {
            $self->_parse_file($s, $l, $logfile);
            if ($self->{cfg}->{cachedir}) {
                $self->_update_cache($s, $l, $logfile);
            }
        }
        $self->_merge_stats(\%stats, $s); # merge per-file stats into global stats
        $self->_merge_lines(\%lines, $l);

        print "$stats{days} days, $stats{parsedlines} lines total\n"
            unless ($self->{cfg}->{silent});
    }

    if ($history) {
        # what is kept is what was read, before the page-only processing below
        $self->_history_prune(\%stats, \%touched);
        $self->_history_save($history, \%stats, \%lines) if $history->{dirty};
        $self->_history_close($history);
    }

    if ($self->{cfg}->{statsdump}) {
        open C, "> $self->{cfg}->{statsdump}" or die "$self->{cfg}->{statsdump}: $!";
        print C Data::Dumper->Dump([\%stats, \%lines], ["stats", "lines"]);
        close C;
    }

    $self->_pick_random_lines(\%stats, \%lines);
    _uniquify_nicks(\%stats);
    $self->_resolve_relations(\%stats) if $self->{rel_on};

    my ($sec,$min,$hour) = gmtime(time() - $starttime);
    my $processtime = sprintf('%02d hours, %02d minutes and %02d seconds', $hour, $min, $sec);

    $stats{processtime}{hours} = sprintf('%02d', $hour);
    $stats{processtime}{mins} = sprintf('%02d', $min);
    $stats{processtime}{secs} = sprintf('%02d', $sec);

    print "Channel analyzed successfully in $processtime on ",
    scalar localtime(time()), "\n\n"
        unless ($self->{cfg}->{silent});

    return \%stats;
}

sub _parse_dir
{
    my $self = shift;
    my $logdir = shift;

        # Add trailing slash when it's not there..
        $logdir =~ s/([^\/])$/$1\//;

        unless ($self->{cfg}->{silent}) {
            print "Looking for logfiles in $logdir...\n\n"
        }
        my @filesarray;
        opendir(LOGDIR, $logdir) or
        die("Can't opendir ${logdir}: $!");
        unless(@filesarray = grep {
            /^[^\.]/ && /^$self->{cfg}->{logprefix}/ && -f "$logdir/$_"
            } readdir(LOGDIR)) {
                print ("No files in \"$logdir\" matched prefix \"$self->{cfg}->{logprefix}\"\n");
                return;
        }
        closedir(LOGDIR);

        if ($self->{cfg}->{logsuffix} ne '') {
            my @temparray;
            my %months = (
                'jan' => '0',
                'feb' => '1',
                'mar' => '2',
                'apr' => '3',
                'may' => '4',
                'jun' => '5',
                'jul' => '6',
                'aug' => '7',
                'sep' => '8',
                'oct' => '9',
                'nov' => '10',
                'dec' => '11',
            );
            my ($mreg, $dreg, $yreg) = split(/\|\|/, $self->{cfg}->{logsuffix});
            my (@month, @day, @year);
            for my $file (@filesarray) {
                LOOPSTART:
                if ($file =~ /$mreg/) {
                    my $month = $1;
                    $month = lc $month;
                    $month = $months{$month}
                        if (defined $months{$month});
                    push @month, $month;
                } else {
                    splice(@filesarray,$#month + 1, 1);
                    if ($file = $filesarray[$#month + 1]) {
                        goto LOOPSTART;
                    } else {
                        last;
                    }
                }
                if ($file =~ /$dreg/) {
                    push @day, $1;
                } else {
                    splice(@filesarray,$#day + 1, 1);
                    splice(@month,$#day + 1);
                    if ($file = $filesarray[$#day + 1]) {
                        goto LOOPSTART;
                    } else {
                        last;
                    }
                }
                if ($file =~ /$yreg/) {
                    push @year, $1;
                } else {
                    splice(@filesarray,$#year + 1, 1);
                    splice(@month,$#year + 1);
                    splice(@day,$#year + 1);
                    if ($file = $filesarray[$#year + 1]) {
                        goto LOOPSTART;
                    } else {
                        last;
                    }
                }
            }
            @filesarray = @filesarray[ sort {
                                        $year[$a] <=> $year[$b]
                                                ||
                                        $month[$a] <=> $month[$b]
                                                ||
                                        $day[$a] <=> $day[$b]
                                    } 0..$#filesarray ];
        } else {
            @filesarray = sort {lc($a) cmp lc($b)} @filesarray;
        }

        return map { "$logdir$_" } @filesarray;
}

# This parses the file...
# substr() cuts at a byte offset, which can split a multi-byte UTF-8 character in
# two and leave invalid UTF-8 in the page. For UTF-8 output, back up to a
# character boundary; for other charsets this is a plain substr().
sub _truncate
{
    my ($self, $text, $len) = @_;
    my $t = substr($text, 0, $len);
    if ($self->{cfg}->{charset} =~ /^utf-?8$/i and $t =~ /([\xC0-\xFF])([\x80-\xBF]*)\z/) {
        my ($lead, $have) = (ord($1), length($2));
        my $need = $lead >= 0xF0 ? 3 : $lead >= 0xE0 ? 2 : 1;
        $t = substr($t, 0, length($t) - 1 - $have) if $have < $need;
    }
    return $t;
}

# Open a log for reading: plain, or through the decompressor for .bz2, .gz and .xz.
# The decompressor is run without a shell, so no file name can be misread as a command.
sub _open_log
{
    my ($self, $file) = @_;
    my $fh;
    if ($file =~ /\.bz2?$/ && -f $file) {
        open ($fh, '-|', 'bunzip2', '-c', $file) or
        die("$0: Unable to open logfile($file): $!\n");
    } elsif ($file =~ /\.gz$/ && -f $file) {
        open ($fh, '-|', 'gunzip', '-c', $file) or
        die("$0: Unable to open logfile($file): $!\n");
    } elsif ($file =~ /\.xz$/ && -f $file) {
        open ($fh, '-|', 'unxz', '-c', $file) or
        die("$0: Unable to open logfile($file): $!\n");
    } else {
        open ($fh, '<', $file) or
        die("$0: Unable to open logfile($file): $!\n");
    }
    return $fh;
}

sub _is_compressed { return $_[0] =~ /\.(?:bz2?|gz|xz)$/ }

# $skip and $progress are for HistoryDir: the first $skip bytes were read by an earlier run and
# are passed over, and $progress (a hash) gets back how far the log was read:
#   offset  bytes read, counted in the (decompressed) text, up to the end of the last line used
#   tail, taillen  checksum and length of that last line (only if a line was read)
#   short   1 if the log has fewer than $skip bytes
#   partial 1 if a last line without a newline was left for later (a log that is still being written)
sub _parse_file
{
    my $self = shift;
    my ($stats, $lines, $file, $skip, $progress) = @_;

    my $fh = $self->_open_log($file);
    my ($offset, $physical, $hold, $last) = (0, 0, 0, undef);
    if ($progress) {
        # a last line without a newline is probably still being written: leave it until it is complete
        $hold = !_is_compressed($file) && (time - (stat($file))[9]) < 120;
        if ($skip) {
            if (_is_compressed($file)) {
                my $left = $skip;
                while ($left > 0) {
                    my $n = read($fh, my $buf, $left > 65536 ? 65536 : $left);
                    last unless $n;
                    $left -= $n;
                }
                $offset = $skip - $left;
            } else {
                seek($fh, $skip, 0) or die("$0: Unable to seek in logfile($file): $!\n");
                $offset = $skip;
            }
            if ($offset < $skip) {
                $progress->{short} = 1;
                close($fh);
                return;
            }
        }
    }

    while(my $line = <$fh>) {
        if ($progress) {
            if ($line !~ /\n\z/ and $hold) {
                $progress->{partial} = 1;
                last;
            }
            $offset += length($line);
            $physical++;
            $last = $line;
        }
        $line = _strip_mirccodes($line);
        $line =~ s/\r+$//;       # Strip DOS Formatting

        if($self->{iconv}) { # iconv is defined only if LogCharset is set
            my $line2 = $self->{iconv}->convert($line);
            if(not $line2 and $self->{iconvfallback}) {
                $line2 = $self->{iconvfallback}->convert($line);
            }
            if($line2) {
                $line = $line2;
            } else {
                print "Charset conversion failed for '$line'\n"
                    unless ($self->{cfg}->{silent});
            }
        }

        my $hashref;

        # Match normal lines.
        if ($hashref = $self->{parser}->normalline($line, $.)) {

            my $repeated = 0;
            if (defined $hashref->{repeated}) {
                $repeated = $hashref->{repeated};
            }

            my ($hour, $nick, $saying, $i);

            for ($i = 0; $i <= $repeated; $i++) {

                if ($i > 0) {
                    $hashref = $self->{parser}->normalline($stats->{lastnormal}, $.);
                    #Increment number of lines for repeated lines
                }

                $hour   = $self->_adjusttimeoffset($hashref->{hour});
                $nick   = find_alias($hashref->{nick});
                checkname($hashref->{nick}, $nick, $stats) if ($self->{cfg}->{showmostnicks});
                $saying = $hashref->{saying};

                if ($hour < $stats->{oldtime}) {
                    $stats->{firsttime} = $hour if $stats->{oldtime} == 24; # save stamp for merging
                    $stats->{days}++;
                    @{$stats->{day_times}[$stats->{days}]} = (0, 0, 0, 0);
                    $stats->{day_lines}->[$stats->{days}] = 0;
                }
                $stats->{oldtime} = $hour;

                if (!is_ignored($nick)) {
                    $stats->{parsedlines}++;

                    # Timestamp collecting
                    $stats->{times}{$hour}++;
                    $stats->{day_times}[$stats->{days}][int($hour/6)]++;
                    $stats->{day_lines}->[$stats->{days}]++;

                    $stats->{lines}{$nick}++;
                    $stats->{lastvisited}{$nick} = $stats->{days};
                    $stats->{line_times}{$nick}[int($hour/6)]++;

                    # Count up monologues
                    if ($stats->{lastnick} eq $nick) {
                        $stats->{monocount}++;

                        if ($stats->{monocount} == 5) {
                            $stats->{monologues}{$nick}++;
                        }
                    } else {
                        $stats->{monocount} = 0;
                    }
                    $stats->{lastnick} = $nick;

                    if ($self->{rel_on}) {
                        # Turn taking: this nick spoke right after another one.
                        my $prev = $stats->{rel_lastnick};
                        $stats->{rel_turns}{$prev}{$nick}++ if defined $prev and $prev ne '' and $prev ne $nick;
                        $stats->{rel_lastnick} = $nick;

                        # "nick: text" / "nick, text" talks to that nick (checked against real nicks later).
                        if ($saying =~ /^\s*[\@+%~&]?([\w\[\]\\`^{|}\x80-\xFF-]{2,30})\s*[:,]/) {
                            $stats->{rel_direct}{$nick}{lc $1}++;
                        }
                        # Every word (links removed), to find nicks mentioned and words a nick favours.
                        (my $plain = $saying) =~ s{\S+://\S+|\bwww\.\S+}{ }gi;
                        foreach my $w ($plain =~ /([\w\[\]\\`^{|}\x80-\xFF-]{2,30})/g) {   # bytes >= 0x80 keep UTF-8 letters whole
                            next if $w =~ /^\d+$/;
                            $stats->{rel_words}{$nick}{lc $w}++;
                        }
                    }

                    my $len = length($saying);
                    if ($len > $self->{cfg}->{minquote} && $len < $self->{cfg}->{maxquote}) {
                        push @{ $lines->{sayings}{$nick} }, $saying;
                    } elsif (!$lines->{sayings}{$nick}) {
                        # Just fill the users first saying in if he hasn't
                        # said anything yet, to get rid of empty quotes.
                        if ($len > $self->{cfg}->{maxquote} - 3) {
                            push @{ $lines->{sayings}{$nick} }, $self->_truncate($saying, $self->{cfg}->{maxquote} - 3) . '...';
                        } else {
                            push @{ $lines->{sayings}{$nick} }, $saying;
                        }
                    }

                    $stats->{lengths}{$nick} += $len;

                    $stats->{questions}{$nick}++
                        if (index($saying, '?') > -1);

                    $stats->{shouts}{$nick}++
                        if (index($saying, '!') > -1);

                    if ($saying !~ /[a-z]/o && $saying =~ /[A-Z]/o) {
                        # Ignore single smileys on a line. eg. '<user> :P'
                        if ($saying !~ /^[8;:=][ ^-o]?[)pPD\}\]>]$/o) {
                            $stats->{allcaps}{$nick}++;
                            push @{ $lines->{allcaplines}{$nick} }, $line;
                        }
                    }

                    if ($self->{foulwords_regexp} and my @foul = $saying =~ /$self->{foulwords_regexp}/) {
                        $stats->{foul}{$nick} += scalar @foul;
                        push @{ $lines->{foullines}{$nick} }, $line;
                    }

                    # Who smiles the most?
                    my $e = '[8;:=%]'; # eyes
                    my $n = '[-oc*^]'; # nose
                    # smileys including asian-style (^^ ^_^' ^^; \o/)
                    if ($saying =~ /(>?$e'?$n[\)pPD\}\]>]|[\(\{\[<]$n'?$e<?|[;:][\)pPD\}\]\>]|\([;:]|\^[_o-]*\^[';]|\\[o.]\/)/o) {
                        $stats->{smiles}{$nick}++;
                        $stats->{smileys}{$1}++;
                        $stats->{smileynicks}{$1} = $nick;
                    }

                    # asian frown: ;_;
                    if ($saying =~ /($e'?$n[\(\[\\\/\{|]|[\)\]\\\/\}|]$n'?$e|[;:][\(\/]|[\)D]:|;_+;|T_+T|-[._]+-)/o and
                        $saying !~ /\w+:\/\//o) {
                        $stats->{frowns}{$nick}++;
                        $stats->{smileys}{$1}++;
                        $stats->{smileynicks}{$1} = $nick;
                    }

                    # require 2 chars (catches C++), nick must not end in [+=-]
                    if ($saying =~ /^(\S+[^\s+=-])(\+\+|==|--)$/) {
                        my $thing = lc $1;
                        my $k = $2 eq "++" ? 1 : ($2 eq "==" ? 0 : -1);
                        $stats->{karma}{$thing}{$nick} = $k
                            if $thing =~ /\w\W*?\w/ and !is_ignored($thing) and $thing ne lc($nick);
                    }

                    # Find URLs
                    if (my @urls = match_urls($saying)) {
                        foreach my $url (@urls) {
                            if(!url_is_ignored($url) and !($self->{badurls_regexp} and $url =~ $self->{badurls_regexp})) {
                                $stats->{urlcounts}{$url}++;
                                $stats->{urlnicks}{$url} = $nick;
                            }
                        }
                    }

                    if ($saying =~ /$self->{chartsregexp}/i) {
                        $self->_charts($stats, $1, $nick);
                    }

                    if (my $s = $self->{users}->{sex}{$nick}) {
                        $stats->{sex_lines}{$s}++;
                        $stats->{sex_line_times}{$s}[int($hour/6)]++;
                    }

                    _parse_words($stats, $saying, $nick, $self->{ignorewords_regexp}, $hour);
                } # ignored
            } # repeated
            $stats->{lastnormal} = $line;
            $repeated = 0;
        } # normal lines

        # Match action lines.
        elsif ($hashref = $self->{parser}->actionline($line, $.)) {
            $stats->{parsedlines}++;

            my ($hour, $nick, $saying);

            $hour   = $self->_adjusttimeoffset($hashref->{hour});
            $nick   = find_alias($hashref->{nick});
            checkname($hashref->{nick}, $nick, $stats) if ($self->{cfg}->{showmostnicks});
            $saying = $hashref->{saying};

            if ($hour < $stats->{oldtime}) {
                $stats->{firsttime} = $hour if $stats->{oldtime} == 24; # save stamp for merging
                $stats->{days}++;
                @{$stats->{day_times}[$stats->{days}]} = (0, 0, 0, 0);
                $stats->{day_lines}->[$stats->{days}] = 0;
            }

            $stats->{oldtime} = $hour;

            if (!is_ignored($nick)) {
                # Timestamp collecting
                $stats->{times}{$hour}++;
                $stats->{day_times}[$stats->{days}][int($hour/6)]++;
                $stats->{day_lines}->[$stats->{days}]++;

                $stats->{actions}{$nick}++;
                push @{ $lines->{actionlines}{$nick} }, $line;
                $stats->{lines}{$nick}++;
                $stats->{lastvisited}{$nick} = $stats->{days};
                $stats->{line_times}{$nick}[int($hour/6)]++;

                if ($self->{violentwords_regexp} and $saying =~ /$self->{violentwords_regexp}/) {
                    my $victim;
                    unless ($victim = is_nick($2)) {
                        foreach my $trynick (split(/\s+/, $3)) {
                            last if ($victim = is_nick($trynick));
                        }
                        unless ($victim) {
                            $victim = $2;
                        }
                    }
                    if (!is_ignored($victim)) {
                        $stats->{violence}{$nick}++;
                        $stats->{attacked}{$victim}++;
                        push @{ $lines->{violencelines}{$nick} }, $line;
                        push @{ $lines->{attackedlines}{$victim} }, $line;
                    }
                }

                if ($saying =~ /$self->{chartsregexp}/i) {
                    $self->_charts($stats, $1, $nick);
                }

                $stats->{lengths}{$nick} += length($saying);

                if (my $s = $self->{users}->{sex}{$nick}) {
                    $stats->{sex_lines}{$s}++;
                    $stats->{sex_line_times}{$s}[int($hour/6)]++;
                }

                _parse_words($stats, $saying, $nick, $self->{ignorewords_regexp}, $hour);
            } # ignored
        } # action lines

        # Match *** lines.
        elsif (($hashref = $self->{parser}->thirdline($line, $.)) and $hashref->{nick}) {
            $stats->{parsedlines}++;

            my ($hour, $min, $nick, $kicker, $newtopic, $newmode, $newjoin);
            my ($newnick);

            $hour     = $self->_adjusttimeoffset($hashref->{hour});
            $min      = $hashref->{min};
            $nick     = find_alias($hashref->{nick});
            checkname($hashref->{nick}, $nick, $stats) if ($self->{cfg}->{showmostnicks});
            $kicker   = find_alias($hashref->{kicker})
                if ($hashref->{kicker});
            $newtopic = $hashref->{newtopic};
            $newmode  = $hashref->{newmode};
            $newjoin  = $hashref->{newjoin};
            $newnick  = $hashref->{newnick};

            if ($hour < $stats->{oldtime}) {
                $stats->{firsttime} = $hour if $stats->{oldtime} == 24; # save stamp for merging
                $stats->{days}++;
                @{$stats->{day_times}[$stats->{days}]} = (0, 0, 0, 0);
                $stats->{day_lines}->[$stats->{days}] = 0;
            }

            $stats->{oldtime} = $hour;

            if (!is_ignored($nick)) {
                # Timestamp collecting
                $stats->{times}{$hour}++;
                $stats->{day_times}[$stats->{days}][int($hour/6)]++;
                $stats->{day_lines}->[$stats->{days}]++;

                $stats->{lastvisited}{$nick} = $stats->{days};

                if (defined($kicker)) {
                    if (!is_ignored($kicker)) {
                        $stats->{kicked}{$kicker}++;
                        $stats->{gotkicked}{$nick}++;
                        push @{ $lines->{kicklines}{$nick} }, $line;
                    }

                } elsif (defined($newtopic) && $newtopic ne '') {
                    push @{$stats->{topics}}, {
                        topic => $newtopic,
                        nick  => $nick,
                        hour  => $hour,
                        min   => $min,
                        days  => $stats->{days},
                    };

                } elsif (defined($newmode)) {
                    _modechanges($stats, $newmode, $nick);

                } elsif (defined($newjoin)) {
                    $stats->{joins}{$nick}++;

                } elsif (defined($newnick) and ($self->{cfg}->{nicktracking} == 1)) {
                    # Resolve new nick to the correct alias (this will create a hard-alias if it is using a regex)
                    $newnick = find_alias($newnick);
                    add_alias($nick, $newnick);
                    checkname($nick, $newnick, $stats) if ($self->{cfg}->{showmostnicks});
                }
            }
        } # *** lines

        unless ($stats->{parsedlines} % 10000) { # keep only recent quotes to save memory
            $self->_trim_lines($lines);
        }
    } # while(my $line = <$fh>)

    $self->_trim_lines($lines);

    if ($progress) {
        # a part of a log is not the place to drop the rare words: that is done on the sum, see _history_prune
        $stats->{totallines} = $physical;
        $progress->{offset} = $offset;
        if (defined $last) {                 # the end of what was read, to recognise the log again
            $progress->{tail} = md5_hex($last);
            $progress->{taillen} = length($last);
        }
    } else {
        $self->_prune_words($stats);
        $stats->{totallines} = $.;
    }

    close($fh);
}

# remove less frequent words
sub _prune_words
{
    my ($self, $stats, $keep) = @_;
    my $wordcount = sqrt(sqrt(keys %{$stats->{wordcounts}}));
    foreach my $word (keys %{$stats->{wordcounts}}) {
        if ($stats->{wordcounts}->{$word} < $wordcount) {
            next if defined $stats->{chartcounts}{$word};
            next if $keep and $keep->{$word};
            delete $stats->{wordcounts}->{$word};
            delete $stats->{wordnicks}->{$word};
            delete $stats->{word_upcase}->{$word};
        }
    }
}

sub _modechanges
{
    my $stats = shift;
    my $newmode = shift;
    my $nick = shift;

    my (@voice, @halfops, @ops, $plus);
    foreach (split(//, $newmode)) {
        if ($_ eq 'o') {
            $ops[$plus]++;
        } elsif ($_ eq 'h') {
            $halfops[$plus]++;
        } elsif ($_ eq 'v') {
            $voice[$plus]++;
        } elsif ($_ eq '+') {
            $plus = 0;
        } elsif ($_ eq '-') {
            $plus = 1;
        }
    }
    $stats->{gaveops}{$nick} += $ops[0] if $ops[0];
    $stats->{tookops}{$nick} += $ops[1] if $ops[1];
    $stats->{gavehalfops}{$nick} += $halfops[0] if $halfops[0];
    $stats->{tookhalfops}{$nick} += $halfops[1] if $halfops[1];
    $stats->{gavevoice}{$nick} += $voice[0] if $voice[0];
    $stats->{tookvoice}{$nick} += $voice[1] if $voice[1];
}

sub _parse_words
{
    my ($stats, $saying, $nick, $ignorewords_regexp, $hour) = @_;
    # Cache time of day
    my $tod = int($hour/6);

    foreach my $word (split(/[\s,!?.:;)(\"]+/o, $saying)) {
        # ignore if $word is empty
        next if $word eq "";

        $stats->{words}{$nick}++;
        $stats->{word_times}{$nick}[$tod]++;
        # remove uninteresting words
        next if $ignorewords_regexp and $word =~ m/$ignorewords_regexp/i;

        # ignore contractions
        next if ($word =~ m/'.{1,2}$/o);

        # Also ignore stuff from URLs.
        next if ($word =~ m/^https?$|^\/\//o);

        my $lcword = lc $word;
        $stats->{wordcounts}{$lcword}++;
        $stats->{wordnicks}{$lcword} = $nick;
        $stats->{word_upcase}{$lcword} ||= $word; # remember first-seen case
    }
}

sub _charts
{
    my ($self, $stats, $Song, $nick) = @_;
    unless (defined $Song) {
        warn "Your ChartsRegexp is b0rked. Read the manual! This happened";
        return;
    }
    $Song =~ s/_/ /g;
    $Song =~ s/\d+ ?- ?//;
    $Song =~ s/\.(mp3|ogg|wma)//ig;
    $Song =~ s/\[[^\] ]*\]/ /g; # strip stuff in brackets [44kbps]
    $Song =~ s/^ *[^\w]* *| *[^\w]* *$//g;

    return unless length $Song;
    
    my $song = lc $Song;
    $stats->{word_upcase}{$song} = $Song;
    $stats->{chartcounts}{$song}++;
    $stats->{chartnicks}{$song} = $nick;
}

sub _trim_lines
{
    my ($self, $lines) = @_;

    foreach my $n (keys %{$lines->{sayings}}) {
        my $x = @{$lines->{sayings}->{$n}};
        splice(@{$lines->{sayings}->{$n}}, 0, ($x - 15)) if ($x > 30);
    }
    foreach my $n (keys %{$lines->{actionlines}}) {
        my $x = @{$lines->{actionlines}->{$n}};
        splice(@{$lines->{actionlines}->{$n}}, 0, ($x - 15)) if ($x > 30);
    }
}

sub _pick_random_lines
{
    my ($self, $stats, $lines) = @_;

    foreach my $key (keys %{ $lines }) {
        foreach my $nick (keys %{ $lines->{$key} }) {
            $stats->{$key}{$nick} = $self->_random_line($lines, $key, $nick);
        }
    }
}

sub _random_line
{
    my ($self, $lines, $key, $nick) = @_;
    my $count = 0;
    my ($random, $out, $out2) = ("", "", "");
    #warn "$nick did not say anything" unless @{ $lines->{$key}{$nick} };
    while (++$count < 20) {
        $random = ${ $lines->{$key}{$nick} }[rand @{ $lines->{$key}{$nick} }];
        if (length($random) < $self->{cfg}->{minquote} or length($random) > $self->{cfg}->{maxquote}) {
            $out2 = $random; # 2nd best choice
            next;
        }
        next if ($self->{cfg}->{noignoredquotes} and $self->{ignorewords_regexp} and
                 $random =~ /$self->{ignorewords_regexp}/i);
        $out = $random;
    }
    return $out || $out2;
}

# Turn the raw per-line data into who-talks-to-whom, once every nick is known (a nick
# can be mentioned before it ever speaks).
#   $stats->{relations}{$from}{$to} = [direct, mentions, replies]
#     direct   - lines that start "to: ..." or "to, ..."
#     mentions - other times "to" (or an alias) appears in a line
#     replies  - times "to" spoke right after "from"
#   $stats->{signature}{$nick} = [word, uses, share]   the word a nick owns most
sub _resolve_relations
{
    my ($self, $stats) = @_;
    my %canon;
    my $resolve = sub {
        my $tok = shift;
        return $canon{$tok} if exists $canon{$tok};
        my $n = is_nick($tok);
        return $canon{$tok} = ($n and exists $stats->{lines}{$n} and !is_ignored($n)) ? $n : '';
    };

    # The channel's own name ("canada" in #Canada) is said all the time and is not a nick.
    (my $chanword = lc($self->{cfg}->{channel} || '')) =~ s/^#+//;

    my (%rel, %mentioned);
    foreach my $from (keys %{ $stats->{rel_words} || {} }) {
        next if is_ignored($from);
        my $direct = $stats->{rel_direct}{$from} || {};
        foreach my $tok (keys %{ $stats->{rel_words}{$from} }) {
            my $to = $resolve->($tok) or next;
            next if $to eq $from;
            my $d = $direct->{$tok} || 0;
            my $m = $stats->{rel_words}{$from}{$tok} - $d;
            $m = 0 if $m < 0 or length($tok) < 3 or $tok eq $chanword;   # 1-2 letter nicks are too often ordinary words
            $rel{$from}{$to}[0] += $d;
            $rel{$from}{$to}[1] += $m;
            $mentioned{$to} += $m;
        }
    }
    # A nick "mentioned" far more often than its activity explains is most likely an ordinary
    # word (Dude, Guest, Canada ...), not a person: keep the direct addresses, drop the mentions.
    my %wordlike = map { $_ => 1 }
        grep { $mentioned{$_} > 5 * ($stats->{lines}{$_} || 0) + 30 } keys %mentioned;
    if (%wordlike) {
        foreach my $from (keys %rel) {
            foreach my $to (keys %{ $rel{$from} }) {
                $rel{$from}{$to}[1] = 0 if $wordlike{$to};
            }
        }
    }
    foreach my $from (keys %{ $stats->{rel_turns} || {} }) {
        next if is_ignored($from) or !exists $stats->{lines}{$from};
        foreach my $to (keys %{ $stats->{rel_turns}{$from} }) {
            next if is_ignored($to) or !exists $stats->{lines}{$to};
            $rel{$from}{$to}[2] += $stats->{rel_turns}{$from}{$to};
        }
    }
    foreach my $from (keys %rel) {
        foreach my $to (keys %{ $rel{$from} }) {
            $_ ||= 0 for @{ $rel{$from}{$to} }[0 .. 2];
        }
    }
    $stats->{relations} = \%rel;

    # Signature word: used a lot by this nick and hardly by anyone else.
    my (%global, %sig);
    foreach my $n (keys %{ $stats->{rel_words} || {} }) {
        $global{$_} += $stats->{rel_words}{$n}{$_} for keys %{ $stats->{rel_words}{$n} };
    }
    my $minlen = $self->{cfg}->{wordlength} > 4 ? $self->{cfg}->{wordlength} : 4;
    foreach my $n (keys %{ $stats->{rel_words} || {} }) {
        next if is_ignored($n) or ($stats->{lines}{$n} || 0) < 30;
        my ($best, $bestscore, $bc, $bs) = ('', 0, 0, 0);
        foreach my $w (keys %{ $stats->{rel_words}{$n} }) {
            my $c = $stats->{rel_words}{$n}{$w};
            next if $c < 4 or length($w) < $minlen or is_nick($w);      # a nick (even an ignored bot) is a name, not a word
            # needs real letters (not ASCII art or punctuation): decode UTF-8 to tell, else use the bytes
            my $u = eval { Encode::decode('UTF-8', $w, Encode::FB_CROAK | Encode::LEAVE_SRC) };   # LEAVE_SRC: keep $w intact
            $u = $w unless defined $u;
            next unless $u =~ /\p{L}{3}/;
            next if $self->{ignorewords_regexp} and $w =~ /$self->{ignorewords_regexp}/;
            my $total = $global{$w} or next;
            my $share = $c / $total;
            next if $share < 0.4;
            my $score = $c * $share;
            ($best, $bestscore, $bc, $bs) = ($w, $score, $c, $share) if $score > $bestscore;
        }
        $sig{$n} = [$best, $bc, int($bs * 100 + 0.5)] if length $best;
    }
    $stats->{signature} = \%sig;

    delete @{$stats}{qw(rel_words rel_direct rel_turns rel_lastnick)};   # raw data no longer needed
}

sub _uniquify_nicks {
    my ($stats) = @_;

    foreach my $word (keys %{ $stats->{wordcounts} }) {
        if (my $realnick = lc(is_nick($word))) {
            if ($realnick ne $word) { # word is always lc
                $stats->{wordcounts}{$realnick} += $stats->{wordcounts}{$word};
                $stats->{wordnicks}{$realnick} ||= $stats->{wordnicks}{$word};
                $stats->{word_upcase}{$realnick} ||= $stats->{word_upcase}{$word};
                delete $stats->{wordcounts}{$word};
                delete $stats->{wordnicks}{$word};
                # We need the word case translation around if it is used as a
                # song name.
                if (!defined $stats->{chartcounts}{$word}) {
                  delete $stats->{word_upcase}{$word};
                }
            }
        }
    }
}

sub _strip_mirccodes
{
    my $line = shift;

    # boldcode = chr(2) = oct 001
    # colorcode = chr(3) = oct 003
    # plaincode = chr(15) = oct 017
    # reversecode = chr(22) = oct 026
    # underlinecode = chr(31) = oct 037

    # Strip mIRC color codes
    $line =~ s/\003\d{1,2},\d{1,2}//go;
    $line =~ s/\003\d{0,2}//go;
    # Strip mIRC bold, plain, reverse and underline codes
    $line =~ s/[\002\017\026\037]//go;

    return $line;
}

sub checkname {
    # This function tracks nickchanges and puts them all in a hash->array,
    # so we can show all nicks that a user had later (only works properly
    # when nicktracking is enabled)
    my ($nick, $newnick, $stats) = @_;

    $stats->{nicks}{$newnick}{lc($nick)} = $nick;
}

sub _adjusttimeoffset
{
    my ($self, $hour) = @_;

    if ($self->{cfg}{timeoffset} != 0) {
        # Adjust time
        $hour += $self->{cfg}{timeoffset};
        $hour = $hour % 24;
    }

    return sprintf('%02d', $hour);
}

sub _read_cache
{
    my ($self, $statsref, $linesref, $logfile) = @_;
    my $csum = (split(' ', `sum -s $logfile`))[0];
    my $cachefile = $logfile;
    $cachefile =~ s/[^\w-]/_/go;
    $cachefile = "$self->{cfg}->{cachedir}/$cachefile";

    return undef unless -e "$cachefile.pisglines";
    return undef unless -e "$cachefile.pisgstats";

    my $lines = retrieve("$cachefile.pisglines");
    my $stats = retrieve("$cachefile.pisgstats");

    return undef if $stats->{version} and $stats->{version} ne $self->{cfg}->{version};
    return undef unless $stats->{logfile} eq $logfile; # the name might be ambigous
    return undef if $stats->{logfile_csum} != $csum; # file has changed

    print "cached, " unless $self->{cfg}->{silent};
    $$statsref = $stats;
    $$linesref = $lines;

    return 1;
}

sub _update_cache
{
    my ($self, $stats, $lines, $logfile) = @_;
    my $csum = (split(' ', `sum -s $logfile`))[0];
    my $cachefile = $logfile;
    $cachefile =~ s/[^\w-]/_/g;
    $cachefile = "$self->{cfg}->{cachedir}/$cachefile";

    $stats->{logfile} = $logfile;
    $stats->{logfile_csum} = $csum;

    store $stats, "$cachefile.pisgstats";
    store $lines, "$cachefile.pisglines";
}

# ---- HistoryDir -----------------------------------------------------------------------------
#
# One file per network and channel keeps everything the logs told pisg so far: the statistics,
# the quote lines, and for every log how much of it was read (its "manifest"). Each run reads
# only what was added since, adds it and saves the file again. The logs themselves are not needed
# after that, so old ones can be deleted or rotated away without the statistics changing.
#
#   { format => 1, version => pisg version, stats => {...}, lines => {...},
#     logs => { $path => { fp, offset, tail, taillen, size, mtime, state } } }
#
#   fp      a checksum of the first line of the log (of the text, not of a compressed file)
#   offset  how many bytes of the (decompressed) text were read
#   tail, taillen  a checksum and the length of the last line that was read: a log is the same log
#           only if its text ends the part that was read with that line. With fp this tells a log
#           that was renamed, moved or compressed from a different log that starts the same way
#   state   who spoke last and the like, so that a log that is read on goes on where it stopped
#   size, mtime  of the file when it was read: a log that has not changed is not looked at again

my $HISTORY_FORMAT = 1;

sub _history_file
{
    my ($self) = @_;
    my $name = join '.', map {
        my $n = lc(defined $_ ? $_ : '');
        $n =~ s/([^A-Za-z0-9_.-])/sprintf('%%%02X', ord($1))/ge;
        $n;
    } $self->{cfg}->{network}, $self->{cfg}->{channel};
    return "$self->{cfg}->{historydir}/$name.pisghist";
}

sub _history_new
{
    return {
        format => $HISTORY_FORMAT,
        stats => {
            oldtime => 24, days => 0, lastnick => '', monocount => 0,
            day_lines => [ undef ], day_times => [ undef ],
            parsedlines => 0, totallines => 0,
        },
        lines => {},
        logs => {},
        dirty => 1,
    };
}

# Read one history file; returns the history, or undef if it cannot be used (and says why).
sub _history_load
{
    my ($self, $file) = @_;
    my $h = eval { retrieve($file) };
    unless (ref $h eq 'HASH' and ref $h->{stats} eq 'HASH' and ref $h->{lines} eq 'HASH'
            and ref $h->{logs} eq 'HASH' and defined $h->{format}) {
        print STDERR "History file $file is damaged or not a history file.\n";
        return undef;
    }
    if ($h->{format} > $HISTORY_FORMAT) {
        print STDERR "History file $file is from a newer pisg (format $h->{format}); this pisg reads format $HISTORY_FORMAT.\n";
        return undef;
    }
    if ($h->{version} and $h->{version} ne $self->{cfg}->{version}) {
        print STDERR "Warning: history file $file was written by pisg $h->{version}, this is "
                   . "$self->{cfg}->{version}; using it anyway.\n";
    }
    return $h;
}

# Lock and read the history of this channel. Returns undef (after saying why) if the channel
# should be skipped: a history that cannot be read is never replaced by an empty one, and two runs
# on the same history at once would overwrite each other.
sub _history_open
{
    my ($self) = @_;
    my $dir = $self->{cfg}->{historydir};
    unless (-d $dir) {
        print STDERR "HistoryDir \"$dir\" not found. Skipping channel $self->{cfg}->{channel}.\n";
        return undef;
    }
    my $file = $self->_history_file();

    open(my $lock, '>>', "$file.lock") or do {
        print STDERR "Cannot write in HistoryDir \"$dir\": $!. Skipping channel $self->{cfg}->{channel}.\n";
        return undef;
    };
    unless (flock($lock, LOCK_EX | LOCK_NB)) {
        print STDERR "The history of $self->{cfg}->{channel} ($file) is in use by another pisg. Skipping it.\n";
        close $lock;
        return undef;
    }

    my $h;
    if ($self->{cfg}->{historyrebuild}) {
        # start again from the logs that still exist; the old history is kept aside
        my $stamp = time;
        foreach my $f ($file, "$file.bak") {
            rename($f, "$f.$stamp.old") if -e $f;
        }
        print STDERR "HistoryRebuild: the old history of $self->{cfg}->{channel} is kept as $file.$stamp.old; "
                   . "what only it contained is gone from the new one.\n" unless $self->{cfg}->{silent};
        $h = _history_new();
    } elsif (-e $file or -e "$file.bak") {
        $h = -e $file ? $self->_history_load($file) : undef;
        unless ($h) {
            if (-e "$file.bak") {
                print STDERR "Using the previous copy, $file.bak.\n";
                $h = $self->_history_load("$file.bak");
                if ($h) {
                    $h->{dirty} = 1;
                    $h->{from_bak} = 1;
                }
            }
        }
        unless ($h) {
            print STDERR "Not starting a new history over one that cannot be read. Skipping channel "
                       . "$self->{cfg}->{channel}; fix or remove $file, or run with HistoryRebuild=1.\n";
            close $lock;
            return undef;
        }
    } else {
        $h = _history_new();
        print "No history yet for $self->{cfg}->{channel}: starting one in $file\n" unless $self->{cfg}->{silent};
    }
    $h->{file} = $file;
    $h->{lock} = $lock;
    return $h;
}

sub _history_close
{
    my ($self, $h) = @_;
    close $h->{lock} if $h->{lock};     # releases the lock
}

# Write the history so that a run that is interrupted never leaves a half-written file: the new
# copy is written aside, the old one becomes .bak, then the new one takes its place.
sub _history_save
{
    my ($self, $h, $stats, $lines) = @_;
    my $file = $h->{file};
    my $tmp = "$file.tmp$$";
    my %copy = (
        format => $HISTORY_FORMAT, version => $self->{cfg}->{version},
        stats => $stats, lines => $lines, logs => $h->{logs},
    );
    eval { Storable::nstore(\%copy, $tmp); 1 } or do {
        unlink $tmp;
        die "Cannot write the history $file: $@";
    };
    if (-e $file) {
        if ($h->{from_bak}) {
            rename($file, "$file.damaged." . time);     # the .bak is the good one: keep it
        } else {
            rename($file, "$file.bak");
        }
    }
    rename($tmp, $file) or die "Cannot write the history $file: $!\n";
    $h->{dirty} = 0;
}

# Rare words are dropped from the sum, not from a part of a log (see _parse_file). Words seen in
# this run stay: a word used a few times every day never reaches the threshold in one run.
sub _history_prune
{
    my ($self, $stats, $touched) = @_;
    $self->_prune_words($stats, $touched);
}

# The first line of a log, as a checksum; undef if the log has no complete line yet.
sub _fingerprint
{
    my ($self, $file) = @_;
    my $fh = $self->_open_log($file);
    my $first = <$fh>;
    close $fh;
    return undef unless defined $first and $first =~ /\n\z/;
    return md5_hex($first);
}

# The size of the text in a .gz file, from the last 4 bytes of the file (mod 2**32).
sub _gz_text_size
{
    my ($file) = @_;
    open(my $fh, '<:raw', $file) or return undef;
    seek($fh, -4, 2) or return undef;
    read($fh, my $bytes, 4) == 4 or return undef;
    return unpack('V', $bytes);
}

# Is the text of $file the log described by history entry $e? True if the part that was read
# of it ends with the line that ended it before.
sub _same_log
{
    my ($self, $file, $e) = @_;
    return 1 unless $e->{offset};                   # nothing was read of it: nothing to compare
    return 0 unless $e->{taillen} and defined $e->{tail} and $e->{offset} >= $e->{taillen};
    my $fh = $self->_open_log($file);
    my $before = $e->{offset} - $e->{taillen};
    if (_is_compressed($file)) {
        my $left = $before;
        while ($left > 0) {
            my $n = read($fh, my $skipped, $left > 65536 ? 65536 : $left);
            last unless $n;
            $left -= $n;
        }
        if ($left) { close $fh; return 0; }
    } else {
        unless (seek($fh, $before, 0)) { close $fh; return 0; }
    }
    my $got = read($fh, my $buf, $e->{taillen});
    close $fh;
    return (defined $got and $got == $e->{taillen} and md5_hex($buf) eq $e->{tail}) ? 1 : 0;
}

# What was added to a log since the last run, as (stats, lines) of just that part; an empty list
# if there is nothing new. Records how far the log was read in the history.
sub _history_delta
{
    my ($self, $h, $file) = @_;
    $file = File::Spec->rel2abs($file);
    my @st = stat($file) or return;                 # gone: its statistics are in the history
    my ($size, $mtime) = @st[7, 9];
    my $logs = $h->{logs};

    my $e = $logs->{$file};
    return if $e and $e->{size} == $size and $e->{mtime} == $mtime;     # not changed

    my $fp = $self->_fingerprint($file);
    return unless defined $fp;                      # empty, or the first line is not complete yet

    # which log is this: the one that was read under this name, or one that was renamed,
    # compressed or moved (its old name is gone), or a new one?
    my $known;
    if ($e) {
        if ($e->{fp} eq $fp and $self->_same_log($file, $e)) {
            $known = $e;
        } else {
            print "replaced by a new log, " unless $self->{cfg}->{silent};
            delete $logs->{$file};
        }
    }
    unless ($known) {
        foreach my $path (sort keys %$logs) {
            my $c = $logs->{$path};
            next unless $c->{fp} eq $fp and $c->{offset};
            next if -e $path;                       # still there under its own name: a different log
            next unless $self->_same_log($file, $c);
            $known = delete $logs->{$path};
            print "same log as $path, " unless $self->{cfg}->{silent};
            last;
        }
    }

    my $skip = $known ? $known->{offset} : 0;
    if ($skip) {
        my $text = _is_compressed($file) ? ($file =~ /\.gz$/ ? _gz_text_size($file) : undef) : $size;
        if (defined $text and $text == $skip % 4294967296) {
            # everything in it was read already
            $logs->{$file} = { %$known, size => $size, mtime => $mtime };
            $h->{dirty} = 1;
            return;
        }
    }

    my %progress;
    my $s = {
        oldtime => 24, days => 0, firsttime => 0, lastnick => '',
        parsedlines => 0, totallines => 0,
    };
    my $l = {};
    # a log that goes on where it stopped goes on with who spoke last, too
    if ($known and ref $known->{state} eq 'HASH') {
        $s->{$_} = $known->{state}{$_} foreach keys %{$known->{state}};
    }
    $self->_parse_file($s, $l, $file, $skip, \%progress);
    if ($progress{short}) {
        print STDERR "Warning: $file is shorter than what was read of it before; leaving it as it was.\n";
        $logs->{$file} = $known if $known;
        return;
    }

    # a log that ends in a line still being written is looked at again next time, whatever its size
    $logs->{$file} = {
        fp => $fp, offset => $progress{offset},
        tail => (defined $progress{tail} ? $progress{tail} : ($known && $known->{tail})),
        taillen => (defined $progress{tail} ? $progress{taillen} : ($known && $known->{taillen})),
        size => ($progress{partial} ? -1 : $size), mtime => $mtime,
        state => { map { defined $s->{$_} ? ($_ => $s->{$_}) : () } qw(lastnick monocount lastnormal rel_lastnick) },
    };
    $h->{dirty} = 1;
    return unless $s->{days};                       # no line of it was used
    return ($s, $l);
}

sub _merge_stats
{
    my ($self, $stats, $s) = @_;

    my $days_offset = $stats->{days};
    my $days_rollover = $stats->{oldtime} > $s->{firsttime};
    $stats->{days} += $s->{days} - 1 + $days_rollover;

    foreach my $key (keys %$s) {
        #print "$key -> $s->{$key}\n";
        if ($key =~ /^(logfile|firsttime|days|version)/) { # don't merge these
            next;
        } elsif ($key =~ /^(rel_words|rel_direct|rel_turns)$/) { # {key}->{}->{} = int: add
            foreach my $subkey (keys %{$s->{$key}}) {
                foreach my $value (keys %{$s->{$key}->{$subkey}}) {
                    $stats->{$key}->{$subkey}->{$value} += $s->{$key}->{$subkey}->{$value};
                }
            }
        } elsif ($key eq 'rel_lastnick') { # str: copy
            $stats->{$key} = $s->{$key};
        } elsif ($key =~ /^(oldtime|lastnick|lastnormal|monocount)$/) { # {key} = int/str: copy
            $stats->{$key} = $s->{$key};
        } elsif ($key =~ /^(parsedlines|totallines)$/) { # {key} = int: add
            $stats->{$key} += $s->{$key};
        } elsif ($key =~ /^(wordnicks|word_upcase|urlnicks|chartnicks|smileynicks)$/) { # {key}->{} = str: copy
            foreach my $subkey (keys %{$s->{$key}}) {
                $stats->{$key}->{$subkey} = $s->{$key}->{$subkey};
            }
        } elsif ($key =~ /^(nicks|karma)$/) { # {key}->{}->{} = str: copy
            foreach my $subkey (keys %{$s->{$key}}) {
                foreach my $value (keys %{$s->{$key}->{$subkey}}) {
                    $stats->{$key}->{$subkey}->{$value} = $s->{$key}->{$subkey}->{$value};
                }
            }
        } elsif ($key =~ /^(word|line|sex_line)_times$/) { # {key}->{}->[] = int: add
            foreach my $subkey (keys %{$s->{$key}}) {
                foreach my $pos (0 .. @{$s->{$key}->{$subkey}} - 1) {
                    $stats->{$key}->{$subkey}->[$pos] += $s->{$key}->{$subkey}->[$pos]
                        if $s->{$key}->{$subkey}->[$pos];
                }
            }
        } elsif ($key eq 'lastvisited') { # {key}->{} = int: copy
            foreach my $nick (keys %{$s->{lastvisited}}) {
                $stats->{lastvisited}->{$nick} =
                    $days_offset + $s->{lastvisited}->{$nick} - 1 + $days_rollover;
            }
        } elsif ($s->{$key} =~ /^HASH/) { # {key}->{} = int: add
            foreach my $subkey (keys %{$s->{$key}}) {
                die "$key -> $subkey" unless $s->{$key}->{$subkey} =~ /^\d+/; # assert
                $stats->{$key}->{$subkey} += $s->{$key}->{$subkey};
            }
        } elsif ($key =~ /^topics$/) { # {key}->[] = topic hash: append
            push @{$stats->{$key}}, map {
                my %a = %$_; $a{days} += $days_offset - 1 + $days_rollover; \%a; # make new hash
            } @{$s->{$key}};
        } elsif ($key =~ /^day_lines$/) { # {key}->[] = int: append
            my @list = @{$s->{day_lines}};
            die if splice @list, 0, 1; # first element is always undef
            unless ($days_rollover) {
                $stats->{day_lines}->[$days_offset] += splice @list, 0, 1;
            }
            push @{$stats->{day_lines}}, @list;
        } elsif ($key =~ /^day_times$/) { # {key}->[]->[] = int: append outer list
            my @list = @{$s->{day_times}};
            die if splice @list, 0, 1;
            if (not $days_rollover) {
                my @first = @{splice @list, 0, 1};
                foreach my $pos (0 .. @first - 1) {
                    $stats->{day_times}[$days_offset][$pos] += $first[$pos];
                }
            }
            push @{$stats->{day_times}}, map { my @a = @$_; \@a; } @list;
        } else {
            die "unknown key format $key -> $s->{$key}";
        }
    }
}

sub _merge_lines
{
    my ($self, $lines, $l) = @_;

    foreach my $key (keys %$l) { # sayings, actionlines, etc.
        foreach my $subkey (keys %{$l->{$key}}) {
            push @{$lines->{$key}->{$subkey}}, @{$l->{$key}->{$subkey}};
            my $x = @{$lines->{$key}->{$subkey}};
            splice(@{$lines->{$key}->{$subkey}}, 0, ($x - 15)) if ($x > 30);
        }
    }
}

1;

__END__

=head1 NAME

Pisg::Parser::Logfile - class to parse a normal logfile

=head1 DESCRIPTION

C<Pisg::Parser::Logfile> parses a logfile using the configuration variables set in the 'cfg' option passed to the constructor.

=head1 SYNOPSIS

    use Pisg::Parser::Logfile;

    $analyzer = new Pisg::Parser::Logfile(
        { cfg => $self->{cfg}, users => $self->{users} }
    );

=head1 CONSTRUCTOR

=over 4

=item new ( [ OPTIONS ] )

This is the constructor for a new Pisg::Parser::Logfile object.

The first option must be a reference to a hash containing the cfg and users structures.

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
