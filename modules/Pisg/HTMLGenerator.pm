package Pisg::HTMLGenerator;

# $Id$
#
# Copyright and license, as well as documentation(POD) for this module is
# found at the end of the file.

use strict;
use Encode ();
use Pisg::Insights;
$^W = 1;

# test for Text::Iconv
my $has_iconv = 1;
eval 'use Text::Iconv';
$has_iconv = 0 if $@;

sub new
{
    my $type = shift;
    my %args = @_;
    my $self = {
        cfg => $args{cfg},
        stats => $args{stats},
        users => $args{users},
        tmps => $args{tmps},
        topactive => {},
    };

    # Import common functions in Pisg::Common
    require Pisg::Common;
    Pisg::Common->import();

    bless($self, $type);
    return $self;
}

# The page is written to a temporary file and moved into place only when it is complete,
# so an error part-way through can never leave a half-written page where the good one was.
sub create_output
{
    my ($self, $lang) = @_;
    my $ok = eval { $self->_create_output_inner($lang); 1 };
    my $err = $@;
    my ($tmp, $final) = @{$self}{qw(outfile_tmp outfile_final)};
    close(OUTPUT);
    if (defined $tmp and -e $tmp) {
        if ($ok) {
            rename($tmp, $final) or do { unlink($tmp); die("$0: Unable to write $final: $!\n"); };
        } else {
            unlink($tmp);
        }
    }
    delete @{$self}{qw(outfile_tmp outfile_final)};
    die $err unless $ok;
}

sub _create_output_inner
{
    # This subroutine calls all the subroutines which create their
    # individual stats. The name of the functions is somewhat saying - if
    # you don't understand it, most subs have a better explanation in the
    # sub itself.

    my $self = shift;
    $self->{cfg}->{lang} = shift;

    # save table width as multiplie files would just increase tablewidth
    my $tablewidth_original = $self->{cfg}->{tablewidth};
    
    # remove old iconv if it exist as it could mess up recode.
    delete $self->{iconv} if $self->{iconv};

    my $lang_charset = $self->{tmps}->{$self->{cfg}->{lang}}{lang_charset};
    if($lang_charset and $lang_charset ne $self->{cfg}->{charset}) {
        if($has_iconv) {
            # convert from template charset to our
            $self->{iconv} = Text::Iconv->new($lang_charset, $self->{cfg}->{charset});
        } else {
            print "Text::Iconv is not installed, skipping charset conversion of language templates\n"
                unless ($self->{cfg}->{silent});
        }
    }

    $self->_topactive();

    if($self->{cfg}->{bignumbersthreshold} =~ /^sqrt/) {
        $self->{cfg}->{bignumbersthreshold} = int(sqrt($self->{stats}->{topactive_lines}));
    }

    my $fname = $self->{cfg}->{outputfile};
    $fname =~ s/\%t/$self->{cfg}->{outputtag}/g;
    $fname =~ s/\%l/$self->{cfg}->{lang}/g;
    print "Now generating HTML ($self->{cfg}->{lang}) in $fname...\n"
        unless ($self->{cfg}->{silent});

    $self->{outfile_final} = $fname;
    $self->{outfile_tmp} = "$fname.tmp$$";
    open (OUTPUT, "> $self->{outfile_tmp}") or
        die("$0: Unable to open outputfile($fname): $!\n");

    if ($self->{cfg}->{showlines}) {
        $self->{cfg}->{tablewidth} += 40;
    }
    if ($self->{cfg}->{showtime}) {
        $self->{cfg}->{tablewidth} += 40;
    }
    if ($self->{cfg}->{showlinetime}) {
        $self->{cfg}->{tablewidth} += 100;
    }
    if ($self->{cfg}->{showwordtime}) {
        $self->{cfg}->{tablewidth} += 100;
    }
    if ($self->{cfg}->{showwords}) {
        $self->{cfg}->{tablewidth} += 40;
    }
    if ($self->{cfg}->{showwpl}) {
        $self->{cfg}->{tablewidth} += 40;
    }
    if ($self->{cfg}->{showcpl}) {
        $self->{cfg}->{tablewidth} += 40;
    }
    if ($self->{cfg}->{userpics}) {
        $self->{cfg}->{tablewidth} += $self->{cfg}->{userpics} * ($self->{cfg}->{picwidth} || 60);
    }
    $self->{cfg}->{headwidth} = $self->{cfg}->{tablewidth} - 4;
    $self->{card_open} = 0;
    $self->{nav} = [];
    $self->{ins_script_relmap} = 0;
    $self->_htmlheader();
    $self->_pageheader()
        if ($self->{cfg}->{pagehead} ne 'none');

    $self->_ins_safe('_insights_overview') if $self->{cfg}->{showoverview};

    if ($self->{cfg}->{dailyactivity}) {
        $self->_activedays();
    }

    if ($self->{cfg}->{showactivetimes}) {
        $self->_activetimes();
    }

    if ($self->{cfg}->{showactivenicks}) {
        $self->_activenicks();
    }

    $self->_ins_safe('_insights_relations') if $self->{cfg}->{showrelations};

    if ($self->{cfg}->{showmostactivebyhour}) {
        $self->_mostactivebyhour();
    }

    $self->_ins_safe('_insights_personalities') if $self->{cfg}->{showtimepersonalities};
    $self->_ins_safe('_insights_concentration') if $self->{cfg}->{showconcentration};
    $self->_ins_safe('_insights_signature') if $self->{cfg}->{showsignaturewords};

    if ($self->{cfg}->{showbignumbers}) {
        $self->_headline($self->_template_text('bignumtopic'), undef, undef, 'bignumtopic');
        _html("<table width=\"$self->{cfg}->{tablewidth}\">"); # Needed for sections
        $self->_questions();
        $self->_shoutpeople();
        $self->_capspeople();
        $self->_violent();
        $self->_mostsmiles();
        $self->_mostsad();
        $self->_linelengths();
        $self->_mostwords();
        $self->_mostwordsperline();
        _html("</table>"); # Needed for sections
    }

    if ($self->{cfg}->{showmostnicks}) {
        $self->_mostnicks();
    }

    if ($self->{cfg}->{showactivegenders}) {
        $self->_activegenders();
    }

    if ($self->{cfg}->{showmuw}) {
        $self->_mostusedword();
    }

    if ($self->{cfg}->{showmrn}) {
        $self->_mostreferencednicks();
    }

    if ($self->{cfg}->{showsmileys}) {
        $self->_smileys();
    }

    if ($self->{cfg}->{showkarma}) {
        $self->_karma();
    }

    if ($self->{cfg}->{showmru}) {
        $self->_mosturls();
    }

    if ($self->{cfg}->{showcharts}) {
        $self->_charts();
    }

    if ($self->{cfg}->{showbignumbers}) {
        $self->_headline($self->_template_text('othernumtopic'), undef, undef, 'othernumtopic');
        _html("<table width=\"$self->{cfg}->{tablewidth}\">"); # Needed for sections
        $self->_gotkicks();
        $self->_mostkicks();
        $self->_mostop() if $self->{cfg}->{showops};
        $self->_mosthalfop() if $self->{cfg}->{showhalfops};
        $self->_mostvoice() if $self->{cfg}->{showvoices};
        $self->_mostactions();
        $self->_mostmonologues();
        $self->_mostjoins();
        $self->_mostfoul();
        _html("</table>"); # Needed for sections
    }

    if ($self->{cfg}->{showtopics}) {
        $self->_headline($self->_template_text('latesttopic'), undef, undef, 'latesttopic');
        _html("<table width=\"$self->{cfg}->{tablewidth}\">"); # Needed for sections

        $self->_lasttopics();

        _html("</table>"); # Needed for sections
    }

    _html('</div>') if $self->{card_open};
    $self->{card_open} = 0;
    $self->_insights_scripts();

    my %hash = ( lines => $self->{stats}->{parsedlines} );
    _html('<div id="totallines">' . $self->_template_text('totallines', %hash) . '</div>');

    $self->_pagefooter()
        if ($self->{cfg}->{pagefoot} ne 'none');

    $self->_htmlfooter();

    close(OUTPUT);

    $self->_insert_navbar();
    $self->_update_channel_index();

    # restore tablewidth
    $self->{cfg}->{tablewidth} = $tablewidth_original;
}

# Keep a small JSON list of the channels found in the output directory, so a
# landing page can offer a channel dropdown straight from pisg's own knowledge
# (no scanning or scraping of the generated HTML). Each run updates only this
# channel's entry, so running channels one at a time works too. Disable with
# ChannelIndex="none".
sub _update_channel_index
{
    my $self = shift;
    my $name = $self->{cfg}->{channelindex};
    return if !defined $name or $name eq '' or lc($name) eq 'none';
    return unless eval { require JSON::PP; 1 };

    my $out = $self->{outfile_final} || $self->{cfg}->{outputfile};
    my ($dir, $file) = $out =~ m{^(.*)/([^/]+)$} ? ($1, $2) : ('.', $out);
    $dir = '/' if $dir eq '';
    my $path = "$dir/$name";
    # No utf8 layer: names come from the config as bytes and go back out as bytes.
    my $json = JSON::PP->new->canonical->pretty;

    my @channels;
    if (open(my $in, '<', $path)) {
        local $/;
        my $data = <$in>;
        close($in);
        my $old = eval { $json->decode($data) };
        @channels = @{ $old->{channels} }
            if ref $old eq 'HASH' and ref $old->{channels} eq 'ARRAY';
    }
    # Replace this channel's entry; forget pages that no longer exist.
    @channels = grep { ref $_ eq 'HASH' and defined $_->{file}
                       and $_->{file} ne $file and -e "$dir/$_->{file}" } @channels;

    my @t = gmtime();
    push @channels, {
        name    => $self->{cfg}->{channel},
        file    => $file,
        network => $self->{cfg}->{network},
        updated => sprintf("%04d-%02d-%02dT%02d:%02d:%02dZ", $t[5] + 1900, $t[4] + 1, @t[3, 2, 1, 0]),
        days    => 0 + ($self->{stats}->{days} || 0),
        nicks   => 0 + scalar(keys %{ $self->{stats}->{lines} || {} }),
        lines   => 0 + ($self->{stats}->{parsedlines} || 0),
        %{ $self->_channel_index_extras },
    };
    @channels = sort { lc($a->{name}) cmp lc($b->{name}) } @channels;

    my $tmp = "$path.tmp$$";
    if (open(my $fh, '>', $tmp)) {
        print $fh $json->encode({ version => 1, channels => \@channels });
        close($fh);
        rename($tmp, $path) or unlink($tmp);
    } else {
        print STDERR "Warning: cannot write channel index $path: $!\n" unless $self->{cfg}->{silent};
    }
}

# A few numbers per channel for the landing page, which shows the statistics of the statistics:
# what the channel is busy with hour by hour, how the last weeks went, who talks most.
sub _channel_index_extras
{
    my $self = shift;
    my $st = $self->{stats};
    my %x;
    my $sum = sub { my $t = 0; $t += $_ for values %{ $_[0] || {} }; return $t; };
    $x{words}     = 0 + $sum->($st->{words});
    $x{questions} = 0 + $sum->($st->{questions});
    $x{joins}     = 0 + $sum->($st->{joins});
    $x{links}     = 0 + $sum->($st->{urlcounts});
    $x{hours}     = [ map { 0 + ($st->{times}{ sprintf('%02d', $_) } || 0) } 0 .. 23 ];

    # Lines on each of the last 30 days of the log (days are counted as pisg counts them everywhere).
    my $dl = $st->{day_lines} || [];
    my $last = $#$dl;
    my $first = $last - 29; $first = 1 if $first < 1;
    $x{recent} = [ map { 0 + ($dl->[$_] || 0) } $first .. $last ] if $last >= 1;

    # Top talkers, bots left out. Names go out as valid UTF-8 whatever the log's charset was.
    my @top;
    my $humans = eval { $self->_ins_humans } || [];
    for my $n (@$humans[0 .. ($#$humans > 4 ? 4 : $#$humans)]) {
        next unless defined $n;
        my $clean = Encode::encode('UTF-8', Encode::decode('UTF-8', $n, Encode::FB_DEFAULT | Encode::LEAVE_SRC));
        push @top, { nick => $clean, lines => 0 + ($st->{lines}{$n} || 0) };
    }
    $x{top} = \@top;
    return \%x;
}

sub _htmlheader
{
    my $self = shift;
    my %hash = (
        network    => $self->{cfg}->{network},
        maintainer => $self->{cfg}->{maintainer},
        days       => $self->{stats}->{days},
        nicks      => scalar keys %{ $self->{stats}->{lines} }
    );

    my $CSS;
    if($self->{cfg}->{colorscheme} =~ /([^\/.]+)\.[^\/]+$/) { # use external CSS file
        $CSS = "<link rel=\"stylesheet\" type=\"text/css\" title=\"$1\" href=\"$self->{cfg}->{colorscheme}\" />";
    } elsif($self->{cfg}->{colorscheme} ne "none") { # read the chosen CSS file
        my $css_file = $self->{cfg}->{cssdir} . $self->{cfg}->{colorscheme} . ".css";
        open(FILE, $css_file) or open (FILE, $self->{cfg}->{search_path} . "/$css_file") or die("$0: Unable to open stylesheet $css_file: $!\n");
        {
            local $/; # enable "slurp" mode
            $CSS = "<style type=\"text/css\" title=\"$self->{cfg}->{colorscheme}\">\n". <FILE>. "</style>";
			$CSS =~ s/\/\*/\/\* <!--/g;
			$CSS =~ s/\*\//--> \*\//g;
        }
        close FILE;
    }

    # use alternate CSS file
    if($self->{cfg}->{altcolorscheme} ne "none" and $self->{cfg}->{altcolorscheme} =~ /[^\w]/) {
        foreach (split /\s+/, $self->{cfg}->{altcolorscheme}) {
            /([^\/.]+)\.[^\/]+$/;
            $CSS .= "\n<link rel=\"alternate stylesheet\" type=\"text/css\" title=\"$1\" href=\"$_\" />";
        }
    }

    # Styles for the newer sections, so any theme (even a 2003 one) shows them decently;
    # a theme that styles them comes later and wins.
    if ($self->{cfg}->{colorscheme} ne "none") {
        my $base = $self->_ins_basecss;
        $CSS = "<style type=\"text/css\" id=\"pisg-base\">\n$base</style>\n" . $CSS if length $base;
    }

    my $title = $self->_template_text('pagetitle1', %hash);
    if($self->{cfg}->{colorscheme} ne "none") {
        _html( <<HTML );
<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Transitional//EN" "http://www.w3.org/TR/xhtml1/DTD/xhtml1-transitional.dtd">
<html xmlns="http://www.w3.org/1999/xhtml">
<head>
<meta http-equiv="Content-Type" content="text/html; charset=$self->{cfg}->{charset}" />
<meta name="viewport" content="width=device-width, initial-scale=1" />
<title>$title</title>
$CSS
</head>
<body>
<div align="center">
HTML
    }
    # Optional way back to the landing page (option HomeLink): a relative page or an http(s) address.
    my $home = $self->{cfg}->{homelink};
    if (defined $home and $home =~ m{^(?:[\w.\-/]+|https?://[^\s"'<>]+)$} and lc($home) ne 'none' and $self->{cfg}->{colorscheme} ne 'none') {
        _html('<p class="homebar"><a class="homebtn" id="homebtn" href="' . $home . '"><span aria-hidden="true">&larr;</span> '
              . $self->_template_text('home_label') . '</a></p>');
    }
    _html('<h1 class="title" id="pagetitle1">' . $title . '</h1>');
    _html('<p class="subtitle"><span id="pagetitle2">' . $self->_template_text('pagetitle2', %hash) . ' ' . $self->get_time() . '</span><br />');
    _html('<span id="pagetitle3">' . $self->_template_text('pagetitle3', %hash) . '</span></p>');
    $self->_nav_marker;

}

sub get_time
{
    my $self = shift;
    my ($tday, %hash);

    my $month = $self->_template_text('month', %hash);
    my $day = $self->_template_text('day', %hash);

    my @month = split(" ", $month);
    my @day = split(" ", $day);

    # Get the Date from the users computer
    my $timezone = $self->{cfg}->{timeoffset} * 3600;
    my ($sec,$min,$hour,$mday,$mon,$year,$wday) = localtime(time+$timezone);

    $year += 1900;                    # Y2K Patch

    $min =~ s/^(.)$/0$1/;             # Fixes the display of mins/secs below
    $sec =~ s/^(.)$/0$1/;             # it displays 03 instead of 3

    if ($hour > '23') {               # Checks to see if it Midnight
        $hour = 12;                   # Makes it display the hour 12
        $tday = "AM";                 # Display AM
    } elsif($hour > '12') {           # Get rid of the Military time and
        $hour -= 12;                  # put it into normal time
        $tday = "PM";                 # If past Noon and before Midnight set
    } else {
        $tday = "AM";                 # If it's past Midnight and before Noon
    }                                 # set the time as AM

    # Use 24 hours pr. day
    if ($tday eq "PM" && $hour < '12') {
        $hour += 12;
    }

    return "$day[$wday] $mday $month[$mon] $year - $hour:$min:$sec";
}


sub _htmlfooter
{
    my $self = shift;

    my %hash;

    my $pisg_hp = $self->_template_text('pisghomepage');
    $hash{pisg_url} = '<a href="https://pisg.github.io/" title="' . $pisg_hp . '" class="background">pisg</a>';

    $hash{version} = $self->{cfg}->{version};

    my $hours = $self->_template_text('hours');
    my $mins = $self->_template_text('minutes');
    my $secs = $self->_template_text('seconds');
    my $and = $self->_template_text('and');

    my $h = $self->{stats}->{processtime}{hours};
    my $m = $self->{stats}->{processtime}{mins};
    my $s = $self->{stats}->{processtime}{secs};
    $hash{time} = "$h $hours $m $mins $and $s $secs";

    my $stats_gen = $self->_template_text('stats_gen_by', %hash);
    my $stats_text = $self->_template_text('stats_gen_in', %hash);

    _html( <<HTML );
<div id="footer" class="small">
	<div id="stats_gen">$stats_gen</div>
	<div id="stats_text">$stats_text</div>
</div>
HTML

    _html( sprintf( qq(<!-- NFiles = "%s"; Format = "%s"; Lang = "%s"; LangFile = "%s"; Charset = "%s"; LogCharset = "%s"; LogCharsetFallback = "%s"; LogPrefix = "%s"; LogSuffix = "%s"; NickTracking = "%s"; TimeOffset = "%s" -->),
        $self->{cfg}->{nfiles},
        $self->{cfg}->{format},
        $self->{cfg}->{lang},
        $self->{cfg}->{langfile},
        $self->{cfg}->{charset},
        $self->{cfg}->{logcharset},
        $self->{cfg}->{logcharsetfallback},
        $self->{cfg}->{logprefix},
        $self->{cfg}->{logsuffix},
        $self->{cfg}->{nicktracking},
        $self->{cfg}->{timeoffset}
    ));
    
    if($self->{cfg}->{colorscheme} ne "none") {
        _html( <<HTML );
</div>
</body>
</html>
HTML
    }
}

sub _headline
{
    my $self = shift;
    my ($title, $id, $label, $key) = (@_);
    # Wrap each section in a <div class="card"> so themes can box sections up.
    # Themes that don't style .card render exactly as before. The id is what the
    # navbar links to.
    $id = $self->_nav_register($title, $id, $label);
    _html('</div>') if $self->{card_open};
    _html('<div class="card' . ($self->_card_is_half($key) ? ' half' : '') . '" id="' . $id . '">');
    $self->{card_open} = 1;
    _html( <<HTML );
   <br />
   <table width="$self->{cfg}->{headwidth}" cellpadding="1" cellspacing="0" border="0">
    <tr>
     <td class="headlinebg">
      <table width="100%" cellpadding="2" cellspacing="0" border="0">
       <tr>
        <td class="headtext">$title</td>
       </tr>
      </table>
     </td>
    </tr>
   </table>
HTML
}

sub _pageheader
{
    my $self = shift;
    unless(open(PAGEHEAD, $self->{cfg}->{pagehead})) {
        warn("$0: Unable to open $self->{cfg}->{pagehead} for reading: $!\n");
        return;
    }
    while (<PAGEHEAD>) {
        chomp;
        _html($_);
    }
    close(PAGEHEAD);
}

sub _pagefooter
{
    my $self = shift;
    unless(open(PAGEFOOT, $self->{cfg}->{pagefoot})) {
        warn("$0: Unable to open $self->{cfg}->{pagefoot} for reading: $!\n");
        return;
    }
    while (<PAGEFOOT>) {
        chomp;
        _html($_);
    }
    close(PAGEFOOT);
}

sub _activedays
{
    # The most actives days on the channel
    my $self = shift;
    my $days = $self->{stats}->{days};
    my $ndays = $self->{cfg}->{dailyactivity};

    my $highest_value = 1;
    for (my $day = $days; $day > $days - $ndays ; $day--) {
        if (defined($self->{stats}->{day_lines}->[$day])) {
            if ($self->{stats}->{day_lines}->[$day] > $highest_value) {
                $highest_value = $self->{stats}->{day_lines}->[$day];
            }
        } else {
            #there are only $days - $day days :)
            $ndays = $days - $day;
            last;
        }
    }

    my %hash = (
        n => $ndays
    );
    $self->_headline($self->_template_text('dailyactivitytopic', %hash), undef, undef, 'dailyactivitytopic');

    _html("<table border=\"0\"><tr>");

    my $peak_done = 0;
    for (my $day = $days - $ndays + 1; $day <= $days ; $day++) {
        my $lines = $self->{stats}->{day_lines}[$day];
        my $pk = ($lines == $highest_value && !$peak_done++) ? ' pk' : '';   # only the busiest day keeps its number
        _html("<td align=\"center\" valign=\"bottom\" class=\"asmall\"><span class=\"v$pk\">$lines</span><br />");
        for (my $time = 4; $time >= 0; $time--) {
            if (defined($self->{stats}->{day_times}[$day][$time])) {
                my $size = int(($self->{stats}->{day_times}[$day][$time] / $highest_value) * 130);

                my $image = "pic_v_".$time*6;
                $image = $self->{cfg}->{$image};
                _html("<img id=\"$image\" src=\"data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABAQMAAAAl21bKAAAAA1BMVEUAAACnej3aAAAAAXRSTlMAQObYZgAAAApJREFUCNdjYAAAAAIAAeIhvDMAAAAASUVORK5CYII=
\" width=\"15\" height=\"$size\" alt=\"$self->{stats}->{day_times}[$day][$time]\" title=\"$self->{stats}->{day_times}[$day][$time]\" /><br />") if $size;

            }
        }
        _html("</td>");
    }

    _html("</tr><tr>");

    for (my $day = $ndays - 1; $day >= 0 ; $day--) {
        my $skip = ($day % 5 == 0) ? '' : ' skip';                   # label every 5th day only
        _html("<td class=\"rankc10center$skip\" align=\"center\">$day</td>");
    }

    _html("</tr></table>");

    if($self->{cfg}->{showlegend} == 1) {
        $self->_legend();
    }
}

sub _activetimes
{
    # The most actives times on the channel
    my $self = shift;

    my (%output);

    $self->_headline($self->_template_text('activetimestopic'), undef, undef, 'activetimestopic');

    my @toptime = sort { $self->{stats}->{times}{$b} <=> $self->{stats}->{times}{$a} } keys %{ $self->{stats}->{times} };

    my $highest_value = $self->{stats}->{times}{$toptime[0]};

    my $peak_done = 0;
    for my $hour (sort keys %{ $self->{stats}->{times} }) {

        my $size = int(($self->{stats}->{times}{$hour} / $highest_value) * 110);
        my $percent = sprintf("%.1f", ($self->{stats}->{times}{$hour} / $self->{stats}->{parsedlines}) * 100);
        my $lines_per_hour = $self->{stats}->{times}{$hour};
        my $pk = ($lines_per_hour == $highest_value && !$peak_done++) ? ' pk' : '';   # only the peak hour keeps its label

        my $image = "pic_v_".(int($hour/6)*6);
        $image = $self->{cfg}->{$image};

        $output{$hour} = "<td align=\"center\" valign=\"bottom\" class=\"asmall\"><span class=\"v$pk\">$percent%</span><br /><img id=\"$image\" src=\"data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABAQMAAAAl21bKAAAAA1BMVEUAAACnej3aAAAAAXRSTlMAQObYZgAAAApJREFUCNdjYAAAAAIAAeIhvDMAAAAASUVORK5CYII=
\" width=\"15\" height=\"$size\" alt=\"$lines_per_hour\" title=\"$lines_per_hour\"/></td>" if $size;
    }

    _html("<table border=\"0\"><tr>");

    for ($b = 0; $b < 24; $b++) {
        $a = sprintf("%02d", $b);

        if (!defined($output{$a})) {
            _html("<td align=\"center\" valign=\"bottom\" class=\"asmall\"><span class=\"v\">0%</span></td>");
        } else {
            _html($output{$a});
        }
    }

    _html("</tr><tr>");

    # Remove leading zero
    $toptime[0] =~ s/^0//;

    for ($b = 0; $b < 24; $b++) {
        # Highlight the top time
        my $class = $toptime[0] == $b ? 'hirankc10center' : 'rankc10center';
        _html("<td class=\"$class hr\" align=\"center\">$b</td>");
    }

    _html("</tr></table>");

    if($self->{cfg}->{showlegend} == 1) {
        $self->_legend();
    }
}

sub _activenicks
{
    # The most active nicks (those who wrote most lines)
    my $self = shift;

    $self->_headline($self->_template_text('activenickstopic'), undef, undef, 'activenickstopic');

    my $output = "";
    $output .= "<table border=\"0\" width=\"$self->{cfg}->{tablewidth}\"><tr>";
    $output .= "<td>&nbsp;</td>";
    $output .= "<td class=\"tdtop\"><b>" . $self->_template_text('nick') . "</b></td>";

    $output .= "<td class=\"tdtop\"><b>" . $self->_template_text('numberlines') . "</b></td>"   if ($self->{cfg}->{showlines});
    $output .= "<td class=\"tdtop\"><b>" . $self->_template_text('show_time') . "</b></td>"     if ($self->{cfg}->{showtime});
    $output .= "<td class=\"tdtop\"><b>" . $self->_template_text('show_words') . "</b></td>"    if ($self->{cfg}->{showwords});
    $output .= "<td class=\"tdtop\"><b>" . $self->_template_text('show_wpl') . "</b></td>"      if ($self->{cfg}->{showwpl});
    $output .= "<td class=\"tdtop\"><b>" . $self->_template_text('show_cpl') . "</b></td>"      if ($self->{cfg}->{showcpl});
    $output .= "<td class=\"tdtop\"><b>" . $self->_template_text('show_lastseen') . "</b></td>" if ($self->{cfg}->{showlastseen});
    $output .= "<td class=\"tdtop\"><b>" . $self->_template_text('randquote') . "</b></td>"     if ($self->{cfg}->{showrandquote});
    
    $output .= "\n";

    my @active;
    my $nicks;
    if ($self->{cfg}->{sortbywords}) {
        @active = sort { $self->{stats}->{words}{$b} <=> $self->{stats}->{words}{$a} } keys %{ $self->{stats}->{words} };
        $nicks = scalar keys %{ $self->{stats}->{words} };
    } else {
        @active = sort { $self->{stats}->{lines}{$b} <=> $self->{stats}->{lines}{$a} } keys %{ $self->{stats}->{lines} };
        $nicks = scalar keys %{ $self->{stats}->{lines} };
    }

    if ($self->{cfg}->{activenicks} > $nicks) { $self->{cfg}->{activenicks} = $nicks; }

    for (my $c = 0; $c < $self->{cfg}->{activenicks}; $c++) {
        last unless $self->{cfg}->{userpics};
        my $nick = $active[$c];
        if ($self->{users}->{userpics}{$nick} or $self->{cfg}->{defaultpic}) {
            $output .= "<td class=\"tdtop\"";
            $output .= " colspan=\"$self->{cfg}->{userpics}\""  if ($self->{cfg}->{userpics} > 1);
            $output .= "><b>" . $self->_template_text('userpic') ."</b></td>";
            last;
        }
    }

    $output .= "\n</tr>";
    _html($output);
    undef $output;

    for (my $i = 0; $i < $self->{cfg}->{activenicks}; $i++) {
        my $c = $i + 1;
        my $nick = $active[$i];
        my $visiblenick;

        my $randomline;
        if (not defined $self->{stats}->{sayings}{$nick}) {
            if ($self->{stats}->{actions}{$nick}) {
                $randomline = $self->{stats}->{actionlines}{$nick};
            } else {
                $randomline = "";
            }
        } else {
            $randomline = $self->{stats}->{sayings}{$nick};
        }

        if ($randomline) {
            $randomline = $self->_format_line($randomline);
        }

        # Add a link to the nick if there is any and quote nick
        if ($self->{users}->{userlinks}{$nick}) {
            $visiblenick = $self->_format_word($self->{users}->{userlinks}{$nick}, $nick);
        } else {
            $visiblenick = $self->_format_word($nick);
        }

        my $style = $self->generate_colors($c);

        my $class = 'rankc';
        if ($c == 1) {
            $class = 'hirankc';
        }

        my $lastseen;

        if ($self->{cfg}->{showlastseen}) {
            $lastseen = $self->{stats}->{days} - $self->{stats}->{lastvisited}{$nick};
            my %hash = ( days => $lastseen );
            if ($lastseen == 0) {
                $lastseen = $self->_template_text('today');
            } elsif ($lastseen == 1) {
                $lastseen = $self->_template_text('lastseen1', %hash);
            } else {
                $lastseen = $self->_template_text('lastseen2', %hash);
            }
        }

        _html("<tr><td class=\"$class\" align=\"left\">$c</td>");

        my $line = $self->{stats}->{lines}{$nick};
        my $w = $self->{stats}->{words}{$nick} ? $self->{stats}->{words}{$nick} : 0;
        my $ch   = $self->{stats}->{lengths}{$nick};
        my $sex = $self->{users}->{sex}{$nick};
        
        my $output = '';
        $output .= "<td $style>";

        # Hilight nick with gendercolors
        if ($sex and $sex eq 'm') {
            $output .= '<span class="male">';
        } elsif ($sex and $sex eq 'f') {
            $output .= '<span class="female">';
        } elsif ($sex and $sex eq 'b') {
            $output .= '<span class="bot">';
        } else {
            $output .= '<span>';
        }
        $output .= $visiblenick;
        $output .= '</span></td>';

        if ($self->{cfg}->{showlines}) {
            if ($self->{cfg}->{showlinetime}) {
                $output .= "<td $style nowrap=\"nowrap\">" . $self->_user_linetimes($nick,$active[0]) . "</td>";
            } else {
                $output .= "<td $style>$line</td>";
            }
        }

        $output .= "<td $style>" . $self->_user_times($nick) . "</td>" if ($self->{cfg}->{showtime});

        if ($self->{cfg}->{showwords}) {
            if ($self->{cfg}->{showwordtime}) {
                $output .= "<td $style nowrap=\"nowrap\">" . $self->_user_wordtimes($nick,$active[0]) . "</td>";
            } else {
                $output .= "<td $style>$w</td>";
            }
        }
        
        $output .= "<td $style>" . sprintf("%.1f", $w/$line) . "</td>"  if ($self->{cfg}->{showwpl});
        $output .= "<td $style>" . sprintf("%.1f", $ch/$line) . "</td>" if ($self->{cfg}->{showcpl});
        $output .= "<td $style class=\"lastseen\">$lastseen</td>"        if ($self->{cfg}->{showlastseen});
        $output .= "<td $style class=\"quote\">\"$randomline\"</td>"      if ($self->{cfg}->{showrandquote});

        _html($output);
        undef $output;


        if ($self->{cfg}->{userpics} && $i % $self->{cfg}->{userpics} == 0) {
            for my $ii (0 .. $self->{cfg}->{userpics} - 1) {
                last if $i + $ii >= $self->{cfg}->{activenicks};
                $self->_user_pic($active[$i + $ii], $style);
            }
        }
        _html("</tr>");
    }

    _html("</table><br />");

    # Almost as active nicks ('These didn't make it to the top..')

    my $toshow = $self->{cfg}->{activenicks2} - $self->{cfg}->{activenicks};
    my $remain = $self->{cfg}->{activenicks} + $toshow;

    unless ($toshow > $nicks) {
        $remain = $self->{cfg}->{activenicks} + $self->{cfg}->{activenicks2};
        if ($remain > $nicks) {
            $remain = $nicks;
        }

        if ($self->{cfg}->{activenicks} <  $remain) {
            _html("<br /><b><i>" . $self->_template_text('nottop') . "</i></b><table><tr>");
            for (my $i = $self->{cfg}->{activenicks}; $i < $remain; $i++) {
                my $visiblenick;
                my $nick = $active[$i];
                if ($i != $self->{cfg}->{activenicks} and ($i - $self->{cfg}->{activenicks}) % 5 == 0) {
                    _html("</tr><tr>");
                }
                my $items;
                if ($self->{users}->{userlinks}{$nick}) {
                    $visiblenick = $self->_format_word($self->{users}->{userlinks}{$nick}, $nick);
                } else {
                    $visiblenick = $self->_format_word($nick);
                }
                if ($self->{cfg}->{sortbywords}) {
                    $items = $self->{stats}->{words}{$active[$i]};
                } else {
                    $items = $self->{stats}->{lines}{$active[$i]};
                }
                my $sex = $self->{users}->{sex}{$active[$i]};

                my $output = "";
                $output .= "<td class=\"rankc10\">";

                if ($sex and $sex eq 'm') {
                    $output .= "<span class=\"male\">";
                } elsif ($sex and $sex eq 'f') {
                    $output .= "<span class=\"female\">";
                } elsif ($sex and $sex eq 'b') {
                    $output .= "<span class=\"bot\">";
                } else {
                    $output .= "<span>";
                }
                $output .= "$visiblenick ($items)";
                $output .= "</span></td>";

                _html($output);
                undef $output;

            }
            _html("</tr></table>");
        }
    }

    my %hash;
    $hash{totalnicks} = $nicks - $remain;
    if ($hash{totalnicks} > 0) {
        _html("<br /><b>" . $self->_template_text('totalnicks', %hash) . "</b><br />");
    }
}

sub generate_colors
{
    my $self = shift;
    my $c = shift;

    # if hicell or hicell2 is "", do not print the class as it could mess up the gendercode
    return "" if not (length $self->{cfg}->{hicell} and length $self->{cfg}->{hicell2});

    my $h = $self->{cfg}->{hicell} or return "class=\"hicell\"";
    $h =~ s/^#//;
    $h = hex $h;
    my $h2 = $self->{cfg}->{hicell2} or return "class=\"hicell\"";
    $h2 =~ s/^#//;
    $h2 = hex $h2;
    my $f_b = $h & 0xff;
    my $f_g = ($h & 0xff00) >> 8;
    my $f_r = ($h & 0xff0000) >> 16;
    my $t_b = $h2 & 0xff;
    my $t_g = ($h2 & 0xff00) >> 8;
    my $t_r = ($h2 & 0xff0000) >> 16;
    my $blue  = sprintf "%0.2x", abs int(((($t_b - $f_b) / $self->{cfg}->{activenicks}) * +$c) + $f_b);
    my $green  = sprintf "%0.2x", abs int(((($t_g - $f_g) / $self->{cfg}->{activenicks}) * +$c) + $f_g);
    my $red  = sprintf "%0.2x", abs int(((($t_r - $f_r) / $self->{cfg}->{activenicks}) * +$c) + $f_r);

    return "style=\"background-color: #$red$green$blue\"";
}

sub _html
{
    my $html = shift;
    print OUTPUT "$html\n" or die "Could not write to disk: $!\n";
}

sub _questions
{
    # Persons who asked the most questions
    my $self = shift;

    my %qpercent;

    foreach my $nick (sort keys %{ $self->{stats}->{questions} }) {
        if ($self->{topactive}{$nick} || !$self->{cfg}->{showonlytop}) {
          if ($self->{stats}->{lines}{$nick} > $self->{cfg}->{bignumbersthreshold}) {
              $qpercent{$nick} = sprintf("%.1f", ($self->{stats}->{questions}{$nick} / $self->{stats}->{lines}{$nick}) * 100);
          }
        }
    }

    my @question = sort { $qpercent{$b} <=> $qpercent{$a} } keys %qpercent;

    if (@question) {
        my %hash = (
            nick => $question[0],
            per  => $qpercent{$question[0]}
        );

        my $text = $self->_template_text('question1', %hash);
        _html("<tr><td class=\"hicell\">$text");
        if (@question >= 2) {
            my %hash = (
                nick => $question[1],
                per => $qpercent{$question[1]}
            );

            my $text = $self->_template_text('question2', %hash);
            _html("<br /><span class=\"small\">$text</span>");
        }
        _html("</td></tr>");

    } else {
        _html("<tr><td class=\"hicell\">" . $self->_template_text('question3') . "</td></tr>");
    }
}

sub _shoutpeople
{
    # The ones who speak with exclamation marks!
    my $self = shift;

    my %spercent;

    foreach my $nick (sort keys %{ $self->{stats}->{shouts} }) {
        if ($self->{topactive}{$nick} || !$self->{cfg}->{showonlytop}) {
          if ($self->{stats}->{lines}{$nick} > $self->{cfg}->{bignumbersthreshold}) {
              $spercent{$nick} = sprintf("%.1f", ($self->{stats}->{shouts}{$nick} / $self->{stats}->{lines}{$nick}) * 100);
          }
        }
    }

    my @shout = sort { $spercent{$b} <=> $spercent{$a} } keys %spercent;

    if (@shout) {
        my %hash = (
            nick => $shout[0],
            per  => $spercent{$shout[0]}
        );

        my $text = $self->_template_text('shout1', %hash);
        _html("<tr><td class=\"hicell\">$text");
        if (@shout >= 2) {
            my %hash = (
                nick => $shout[1],
                per  => $spercent{$shout[1]}
            );

            my $text = $self->_template_text('shout2', %hash);
            _html("<br /><span class=\"small\">$text</span>");
        }
        _html("</td></tr>");

    } else {
        my $text = $self->_template_text('shout3');
        _html("<tr><td class=\"hicell\">$text</td></tr>");
    }

}

sub _capspeople
{
    # The ones who speak ALL CAPS.
    my $self = shift;

    my %cpercent;

    foreach my $nick (sort keys %{ $self->{stats}->{allcaps} }) {
        if ($self->{topactive}{$nick} || !$self->{cfg}->{showonlytop}) {
          if ($self->{stats}->{lines}{$nick} > $self->{cfg}->{bignumbersthreshold}) {
              $cpercent{$nick} = sprintf("%.1f", $self->{stats}->{allcaps}{$nick} / $self->{stats}->{lines}{$nick} * 100);
          }
        }
    }

    my @caps = sort { $cpercent{$b} <=> $cpercent{$a} } keys %cpercent;

    if (@caps) {
        my %hash = (
            nick => $caps[0],
            per  => $cpercent{$caps[0]},
            line => $self->_format_line($self->{stats}->{allcaplines}{$caps[0]})
        );

        my $text = $self->_template_text('allcaps1', %hash);
        if($self->{cfg}->{showshoutline}) {
            my $exttext = $self->_template_text('allcapstext', %hash);
            _html("<tr><td class=\"hicell\">$text<br /><span class=\"small\">$exttext</span>");
        } else {
            _html("<tr><td class=\"hicell\">$text");
        }
        if (@caps >= 2) {
            my %hash = (
                nick => $caps[1],
                per  => $cpercent{$caps[1]}
            );

            my $text = $self->_template_text('allcaps2', %hash);
            _html("<br /><span class=\"small\">$text</span>");
        }
        _html("</td></tr>");

    } else {
        my $text = $self->_template_text('allcaps3');
        _html("<tr><td class=\"hicell\">$text</td></tr>");
    }
}

sub _violent
{
    # They attacked others (words defined by $self->{cfg}->{violent})
    my $self = shift;

    my @aggressors = sort { $self->{stats}->{violence}{$b} <=> $self->{stats}->{violence}{$a} }
                         keys %{ $self->{stats}->{violence} };

    @aggressors = $self->_istoponly(@aggressors);

    if(@aggressors) {
        my %hash = (
            nick    => $aggressors[0],
            attacks => $self->{stats}->{violence}{$aggressors[0]},
            line    => $self->_format_line($self->{stats}->{violencelines}{$aggressors[0]})
        );
        my $text = $self->_template_text('violent1', %hash);
        if($self->{cfg}->{showviolentlines}) {
            my $exttext = $self->_template_text('violenttext', %hash);
            _html("<tr><td class=\"hicell\">$text<br /><span class=\"small\">$exttext</span>");
        } else {
            _html("<tr><td class=\"hicell\">$text");
        }
        if (@aggressors >= 2) {
            my %hash = (
                nick    => $aggressors[1],
                attacks => $self->{stats}->{violence}{$aggressors[1]}
            );

            my $text = $self->_template_text('violent2', %hash);
            _html("<br /><span class=\"small\">$text</span>");
        }
        _html("</td></tr>");
    } else {
        my $text = $self->_template_text('violent3');
        _html("<tr><td class=\"hicell\">$text</td></tr>");
    }


    # They got attacked
    my @victims = sort { $self->{stats}->{attacked}{$b} <=> $self->{stats}->{attacked}{$a} }
                    keys %{ $self->{stats}->{attacked} };

    @victims = $self->_istoponly(@victims);

    if(@victims) {
        my %hash = (
            nick    => $victims[0],
            attacks => $self->{stats}->{attacked}{$victims[0]},
            line    => $self->_format_line($self->{stats}->{attackedlines}{$victims[0]})
        );
        my $text = $self->_template_text('attacked1', %hash);
        if($self->{cfg}->{showviolentlines}) {
            my $exttext = $self->_template_text('attackedtext', %hash);
            _html("<tr><td class=\"hicell\">$text<br /><span class=\"small\">$exttext</span>");
        } else {
            _html("<tr><td class=\"hicell\">$text");
        }
        if (@victims >= 2) {
            my %hash = (
                nick    => $victims[1],
                attacks => $self->{stats}->{attacked}{$victims[1]}
            );

            my $text = $self->_template_text('attacked2', %hash);
            _html("<br /><span class=\"small\">$text</span>");
        }
        _html("</td></tr>");
    }
}

sub _gotkicks
{
    # The persons who got kicked the most
    my $self = shift;

    my @gotkick = sort { $self->{stats}->{gotkicked}{$b} <=> $self->{stats}->{gotkicked}{$a} }
                       keys %{ $self->{stats}->{gotkicked} };

    @gotkick = $self->_istoponly(@gotkick);

    if (@gotkick) {
        my %hash = (
            nick  => $gotkick[0],
            kicks => $self->{stats}->{gotkicked}{$gotkick[0]},
            line  => $self->_format_line($self->{stats}->{kicklines}{$gotkick[0]})
        );

        my $text = $self->_template_text('gotkick1', %hash);

        if ($self->{cfg}->{showkickline}) {
            my $exttext = $self->_template_text('kicktext', %hash);
            _html("<tr><td class=\"hicell\">$text<br /><span class=\"small\">$exttext</span>");
        } else {
            _html("<tr><td class=\"hicell\">$text");
        }

        if (@gotkick >= 2) {
            my %hash = (
                nick  => $gotkick[1],
                kicks => $self->{stats}->{gotkicked}{$gotkick[1]}
            );

            my $text = $self->_template_text('gotkick2', %hash);
            _html("<br /><span class=\"small\">$text</span>");
        }
        _html("</td></tr>");
    }
}

sub _mostjoins
{
    my $self = shift;

    my @joins = sort { $self->{stats}->{joins}{$b} <=> $self->{stats}->{joins}{$a} }
                     keys %{ $self->{stats}->{joins} };

    @joins = $self->_istoponly(@joins);

    if (@joins) {
        my %hash = (
            nick  => $joins[0],
            joins => $self->{stats}->{joins}{$joins[0]}
        );

        my $text = $self->_template_text('joins', %hash);

        _html("<tr><td class=\"hicell\">$text</td></tr>");
    }
}

sub _mostwords
{
    # The person who got words the most
    my $self = shift;

    my @words = sort { $self->{stats}->{words}{$b} <=> $self->{stats}->{words}{$a} }
                      keys %{ $self->{stats}->{words} };

    @words = $self->_istoponly(@words);

    if (@words) {
        my %hash = (
            nick  => $words[0],
            words => $self->{stats}->{words}{$words[0]}
        );

        my $text = $self->_template_text('words1', %hash);
        _html("<tr><td class=\"hicell\">$text");

        if (@words >= 2) {
            my %hash = (
                oldnick => $words[0],
                nick    => $words[1],
                words   => $self->{stats}->{words}{$words[1]}
            );

            my $text = $self->_template_text('words2', %hash);
            _html("<br /><span class=\"small\">$text</span>");
        }
        _html("</td></tr>");
    } else {
        my $text = $self->_template_text('words3');
        _html("<tr><td class=\"hicell\">$text</td></tr>");
    }
}

sub _mostkicks
{
    # The person who kicked the most
    my $self = shift;

    my @kicked = sort { $self->{stats}->{kicked}{$b} <=> $self->{stats}->{kicked}{$a} }
                        keys %{ $self->{stats}->{kicked} };

    @kicked = $self->_istoponly(@kicked);

    if (@kicked) {
        my %hash = (
            nick   => $kicked[0],
            kicked => $self->{stats}->{kicked}{$kicked[0]}
        );

        my $text = $self->_template_text('kick1', %hash);
        _html("<tr><td class=\"hicell\">$text");

        if (@kicked >= 2) {
            my %hash = (
                oldnick => $kicked[0],
                nick    => $kicked[1],
                kicked  => $self->{stats}->{kicked}{$kicked[1]}
            );

            my $text = $self->_template_text('kick2', %hash);
            _html("<br /><span class=\"small\">$text</span>");
        }
        _html("</td></tr>");
    } else {
        my $text = $self->_template_text('kick3');
        _html("<tr><td class=\"hicell\">$text</td></tr>");
    }
}

sub _mostmonologues
{
    # The person who had the most monologues (speaking to himself)
    my $self = shift;

    my @monologue = sort { $self->{stats}->{monologues}{$b} <=> $self->{stats}->{monologues}{$a} } 
                           keys %{ $self->{stats}->{monologues} };

    @monologue = $self->_istoponly(@monologue);

    if (@monologue) {
        my %hash = (
            nick  => $monologue[0],
            monos => $self->{stats}->{monologues}{$monologue[0]}
        );

        my $text = $self->_template_text('mono1', %hash);

        _html("<tr><td class=\"hicell\">$text");
        if (@monologue >= 2) {
            my %hash = (
                nick  => $monologue[1],
                monos => $self->{stats}->{monologues}{$monologue[1]}
            );

            my $text = $self->_template_text('mono2', %hash);
            _html("<br /><span class=\"small\">$text</span>");
        }
        _html("</td></tr>");
    }
}

sub _linelengths
{
    # The person(s) who wrote the longest lines
    my $self = shift;

    my %len;

    foreach my $nick (sort keys %{ $self->{stats}->{lengths} }) {
        if ($self->{topactive}{$nick} || !$self->{cfg}->{showonlytop}) {
          if ($self->{stats}->{lines}{$nick} > $self->{cfg}->{bignumbersthreshold}) {
              $len{$nick} = sprintf("%.1f", $self->{stats}->{lengths}{$nick} / $self->{stats}->{lines}{$nick});
          }
        }
    }

    my @len = sort { $len{$b} <=> $len{$a} } keys %len;

    my $all_lines = 0;
    my $totallength;
    foreach my $nick (keys %{ $self->{stats}->{lines} }) {
        $all_lines   += $self->{stats}->{lines}{$nick};
        $totallength += $self->{stats}->{lengths}{$nick};
    }

    my $totalaverage;

    if ($all_lines > 0) {
        $totalaverage = sprintf("%.1f", $totallength / $all_lines);
    }

    if (@len) {
        my %hash = (
            nick    => $len[0],
            letters => $len{$len[0]}
        );

        my $text = $self->_template_text('long1', %hash);
        _html("<tr><td class=\"hicell\">$text<br />");

        if (@len >= 2) {
            %hash = (
                avg => $totalaverage
            );

            $text = $self->_template_text('long2', %hash);
            _html("<span class=\"small\">$text</span></td></tr>");
        } else {
            _html("</td></tr>");
        }
    }

    # The person(s) who wrote the shortest lines

    if (@len) {
        my %hash = (
            nick => $len[$#len],
            letters => $len{$len[$#len]}
        );

        my $text = $self->_template_text('short1', %hash);
        _html("<tr><td class=\"hicell\">$text<br />");

        if (@len >= 2) {
            %hash = (
                nick => $len[$#len - 1],
                letters => $len{$len[$#len - 1]}
            );

            $text = $self->_template_text('short2', %hash);
            _html("<span class=\"small\">$text</span></td></tr>");
        } else {
            _html("</td></tr>");
        }
    }
}

sub _mostfoul
{
    my $self = shift;

    my %spercent;

    foreach my $nick (sort keys %{ $self->{stats}->{foul} }) {
        if ($self->{topactive}{$nick} || !$self->{cfg}->{showonlytop}) {
          if ($self->{stats}->{lines}{$nick} > 15) {
              my $dec = $self->{cfg}->{showfouldecimals};
              $dec = 1 if($dec < 0); # default to 1
              $spercent{$nick} = sprintf("%.${dec}f", $self->{stats}->{foul}{$nick} / $self->{stats}->{words}{$nick} * 100);
          }
        }
    }

    my @foul = sort { $spercent{$b} <=> $spercent{$a} } keys %spercent;

    if (@foul) {

        my %hash = (
            nick => $foul[0],
            per  => $spercent{$foul[0]},
            line => $self->_format_line($self->{stats}{foullines}{$foul[0]}),
        );

        my $text = $self->_template_text('foul1', %hash);

        if($self->{cfg}->{showfoulline}) {
            my $exttext = $self->_template_text('foultext', %hash);
            _html("<tr><td class=\"hicell\">$text<br /><span class=\"small\">$exttext</span>");
        } else {
            _html("<tr><td class=\"hicell\">$text");
        }

        if (@foul >= 2) {
            my %hash = (
                nick => $foul[1],
                per  => $spercent{$foul[1]}
            );

            my $text = $self->_template_text('foul2', %hash);
            _html("<br /><span class=\"small\">$text</span>");
        }

        _html("</td></tr>");
    } else {
        my $text = $self->_template_text('foul3');

        _html("<tr><td class=\"hicell\">$text</td></tr>");
    }
}


sub _mostsad
{
    my $self = shift;

    my %spercent;

    foreach my $nick (sort keys %{ $self->{stats}->{frowns} }) {
        if ($self->{topactive}{$nick} || !$self->{cfg}->{showonlytop}) {
          if ($self->{stats}->{lines}{$nick} > $self->{cfg}->{bignumbersthreshold}) {
              $spercent{$nick} = sprintf("%.1f", $self->{stats}->{frowns}{$nick} / $self->{stats}->{lines}{$nick} * 100);
          }
        }
    }

    my @sadface = sort { $spercent{$b} <=> $spercent{$a} } keys %spercent;


    if (@sadface) {
        my %hash = (
            nick => $sadface[0],
            per  => $spercent{$sadface[0]}
        );

        my $text = $self->_template_text('sad1', %hash);
        _html("<tr><td class=\"hicell\">$text");

        if (@sadface >= 2) {
            my %hash = (
                nick => $sadface[1],
                per  => $spercent{$sadface[1]}
            );

            my $text = $self->_template_text('sad2', %hash);

            _html("<br /><span class=\"small\">$text</span>");
        }
        _html("</td></tr>");
    } else {
        my $text = $self->_template_text('sad3');
        _html("<tr><td class=\"hicell\">$text</td></tr>");
    }
}


sub _mostop
{
    my $self = shift;

    my @ops   = sort { $self->{stats}->{gaveops}{$b} <=> $self->{stats}->{gaveops}{$a} }
                     keys %{ $self->{stats}->{gaveops} };

    @ops = $self->_istoponly(@ops);

    my @deops = sort { $self->{stats}->{tookops}{$b} <=> $self->{stats}->{tookops}{$a} }
                     keys %{ $self->{stats}->{tookops} };

    @deops = $self->_istoponly(@deops);

    if (@ops) {
        my %hash = (
            nick => $ops[0],
            ops  => $self->{stats}->{gaveops}{$ops[0]}
        );

        my $text = $self->_template_text('mostop1', %hash);

        _html("<tr><td class=\"hicell\">$text");

        if (@ops >= 2) {
            my %hash = (
                nick => $ops[1],
                ops  => $self->{stats}->{gaveops}{$ops[1]}
            );

            my $text = $self->_template_text('mostop2', %hash);
            _html("<br /><span class=\"small\">$text</span>");
        }
        _html("</td></tr>");
    } else {
        my $text = $self->_template_text('mostop3');
        _html("<tr><td class=\"hicell\">$text</td></tr>");
    }

    if (@deops) {
        my %hash = (
            nick  => $deops[0],
            deops => $self->{stats}->{tookops}{$deops[0]}
        );
        my $text = $self->_template_text('mostdeop1', %hash);

        _html("<tr><td class=\"hicell\">$text");

        if (@deops >= 2) {
            my %hash = (
                nick  => $deops[1],
                deops => $self->{stats}->{tookops}{$deops[1]}
            );
            my $text = $self->_template_text('mostdeop2', %hash);

            _html("<br /><span class=\"small\">$text</span>");
        }
        _html("</td></tr>");
    } else {
        my $text = $self->_template_text('mostdeop3');
        _html("<tr><td class=\"hicell\">$text</td></tr>");
    }
}

sub _mostvoice
{
    my $self = shift;

    my @voice   = sort { $self->{stats}->{gavevoice}{$b} <=> $self->{stats}->{gavevoice}{$a} }
                     keys %{ $self->{stats}->{gavevoice} };

    @voice = $self->_istoponly(@voice);

    my @devoice = sort { $self->{stats}->{tookvoice}{$b} <=> $self->{stats}->{tookvoice}{$a} }
                     keys %{ $self->{stats}->{tookvoice} };

    @devoice = $self->_istoponly(@devoice);

    if (@voice) {
        my %hash = (
            nick => $voice[0],
            voices  => $self->{stats}->{gavevoice}{$voice[0]}
        );

        my $text = $self->_template_text('mostvoice1', %hash);

        _html("<tr><td class=\"hicell\">$text");

        if (@voice >= 2) {
            my %hash = (
                nick => $voice[1],
                voices  => $self->{stats}->{gavevoice}{$voice[1]}
            );

            my $text = $self->_template_text('mostvoice2', %hash);
            _html("<br /><span class=\"small\">$text</span>");
        }
        _html("</td></tr>");
    } else {
        my $text = $self->_template_text('mostvoice3');
        _html("<tr><td class=\"hicell\">$text</td></tr>");
    }

    if (@devoice) {
        my %hash = (
            nick  => $devoice[0],
            devoices => $self->{stats}->{tookvoice}{$devoice[0]}
        );
        my $text = $self->_template_text('mostdevoice1', %hash);

        _html("<tr><td class=\"hicell\">$text");

        if (@devoice >= 2) {
            my %hash = (
                nick  => $devoice[1],
                devoices => $self->{stats}->{tookvoice}{$devoice[1]}
            );
            my $text = $self->_template_text('mostdevoice2', %hash);

            _html("<br /><span class=\"small\">$text</span>");
        }
        _html("</td></tr>");
    } else {
        my $text = $self->_template_text('mostdevoice3');
        _html("<tr><td class=\"hicell\">$text</td></tr>");
    }

}

sub _mosthalfop
{
    my $self = shift;

    my @halfops   = sort { $self->{stats}->{gavehalfops}{$b} <=> $self->{stats}->{gavehalfops}{$a} }
                     keys %{ $self->{stats}->{gavehalfops} };

    @halfops = $self->_istoponly(@halfops);

    my @dehalfops = sort { $self->{stats}->{tookhalfops}{$b} <=> $self->{stats}->{tookhalfops}{$a} }
                     keys %{ $self->{stats}->{tookhalfops} };

    @dehalfops = $self->_istoponly(@dehalfops);

    if (@halfops) {
        my %hash = (
            nick => $halfops[0],
            halfops  => $self->{stats}->{gavehalfops}{$halfops[0]}
        );

        my $text = $self->_template_text('mosthalfop1', %hash);

        _html("<tr><td class=\"hicell\">$text");

        if (@halfops >= 2) {
            my %hash = (
                nick => $halfops[1],
                halfops  => $self->{stats}->{gavehalfops}{$halfops[1]}
            );

            my $text = $self->_template_text('mosthalfop2', %hash);
            _html("<br /><span class=\"small\">$text</span>");
        }
        _html("</td></tr>");
    } else {
        my $text = $self->_template_text('mosthalfop3');
        _html("<tr><td class=\"hicell\">$text</td></tr>");
    }

    if (@dehalfops) {
        my %hash = (
            nick  => $dehalfops[0],
            dehalfops => $self->{stats}->{tookhalfops}{$dehalfops[0]}
        );
        my $text = $self->_template_text('mostdehalfop1', %hash);

        _html("<tr><td class=\"hicell\">$text");

        if (@dehalfops >= 2) {
            my %hash = (
                nick  => $dehalfops[1],
                dehalfops => $self->{stats}->{tookhalfops}{$dehalfops[1]}
            );
            my $text = $self->_template_text('mostdehalfop2', %hash);

            _html("<br /><span class=\"small\">$text</span>");
        }
        _html("</td></tr>");
    } else {
        my $text = $self->_template_text('mostdehalfop3');
        _html("<tr><td class=\"hicell\">$text</td></tr>");
    }
}

sub _mostactions
{
    # The person who did the most /me's
    my $self = shift;

    my @actions = sort { $self->{stats}->{actions}{$b} <=> $self->{stats}->{actions}{$a} }
                        keys %{ $self->{stats}->{actions} };

    @actions = $self->_istoponly(@actions);

    if (@actions) {
        my %linehash =
        my %hash = (
            nick    => $actions[0],
            actions => $self->{stats}->{actions}{$actions[0]},
            line    => $self->_format_line($self->{stats}->{actionlines}{$actions[0]})
        );
        my $text = $self->_template_text('action1', %hash);
        if($self->{cfg}->{showactionline}) {
            my $exttext = $self->_template_text('actiontext', %hash);
            _html("<tr><td class=\"hicell\">$text<br /><span class=\"small\">$exttext</span>");
        } else {
            _html("<tr><td class=\"hicell\">$text");
        }

        if (@actions >= 2) {
            my %hash = (
                nick    => $actions[1],
                actions => $self->{stats}->{actions}{$actions[1]}
            );

            my $text = $self->_template_text('action2', %hash);
            _html("<br /><span class=\"small\">$text</span>");
        }
        _html("</td></tr>");
    } else {
        my $text = $self->_template_text('action3');
        _html("<tr><td class=\"hicell\">$text</td></tr>");
    }
}


sub _mostsmiles
{
    # The person(s) who smiled the most :-)
    my $self = shift;

    my %spercent;

    foreach my $nick (sort keys %{ $self->{stats}->{smiles} }) {
        if ($self->{topactive}{$nick} || !$self->{cfg}->{showonlytop}) {
          if ($self->{stats}->{lines}{$nick} > $self->{cfg}->{bignumbersthreshold}) {
              $spercent{$nick} = sprintf("%.1f", $self->{stats}->{smiles}{$nick} / $self->{stats}->{lines}{$nick} * 100);
          }
        }
    }

    my @smiles = sort { $spercent{$b} <=> $spercent{$a} } keys %spercent;


    if (@smiles) {
        my %hash = (
            nick => $smiles[0],
            per  => $spercent{$smiles[0]}
        );

        my $text = $self->_template_text('smiles1', %hash);

        _html("<tr><td class=\"hicell\">$text");
        if (@smiles >= 2) {
            my %hash = (
                nick => $smiles[1],
                per  => $spercent{$smiles[1]}
            );

            my $text = $self->_template_text('smiles2', %hash);
            _html("<br /><span class=\"small\">$text</span>");
        }
        _html("</td></tr>");

    } else {

        my $text = $self->_template_text('smiles3');
        _html("<tr><td class=\"hicell\">$text</td></tr>");
    }
}

sub _lasttopics
{
    my $self = shift;

    if ($self->{stats}->{topics}) {

        my %topic_seen;

        my %hash = (
            total => scalar @{ $self->{stats}->{topics} }
        );

        my $ltopic = $#{ $self->{stats}->{topics} };
        my $tlimit = 0;

        $self->{cfg}->{topichistory} -= 1;

        if ($ltopic > $self->{cfg}->{topichistory}) {
            $tlimit = $ltopic - $self->{cfg}->{topichistory};
        }

        for (my $i = $ltopic; $i >= $tlimit; $i--) {
            my $topic = $self->{stats}->{topics}[$i]{topic};
            # This code makes sure that we don't see the same topic twice
            next if ($topic_seen{$topic});
            $topic_seen{$topic} = 1;

            # Strip off the quotes (')
            $topic =~ s/^\'(.*)\'$/$1/;

            my $nick = $self->{stats}->{topics}[$i]{nick};
            my $hour = $self->{stats}->{topics}[$i]{hour};
            my $min  = $self->{stats}->{topics}[$i]{min};

            $hash{nick} = $nick;
            $hash{time} = "$hour:$min";
            $hash{days} = $self->{stats}->{days} - $self->{stats}->{topics}[$i]{days};
            if ($hash{days} == 0) {
                $hash{date} = $self->_template_text('today');
            } elsif ($hash{days} == 1) {
                $hash{date} = $self->_template_text('lastseen1', %hash);
            } else {
                $hash{date} = $self->_template_text('lastseen2', %hash);
            }

            _html('<tr><td class="hicell"><i>' . $self->_format_line($topic) . '</i></td>');
            _html('<td class="hicell"><b>' . $self->_template_text('bylinetopic', %hash) . '</b></td></tr>');
        }
        _html("<tr><td align=\"center\" colspan=\"2\" class=\"asmall\">" . $self->_template_text('totaltopic', %hash) . "</td></tr>");
    } else {
        _html("<tr><td class=\"hicell\">" . $self->_template_text('notopic') ."</td></tr>");
    }
}

sub _template_text
{
    # This function is for the homemade template system. It receives a name
    # of a template and a hash with the fields in the template to update to
    # its corresponding value
    my $self = shift;
    my $template = shift;
    my %hash = @_;

    my $text;

    unless ($text = $self->{tmps}->{$self->{cfg}->{lang}}{$template}) {
        # Fall back to English if the language template doesn't exist

        if ($text = $self->{tmps}->{EN}{$template}) {
            print "Note: No translation in '$self->{cfg}->{lang}' for '$template' - falling back to English.\n"
                unless ($self->{cfg}->{silent});
        } else {
            die("No template for '$template' in language file.\n");
        }
    }
    if($self->{iconv}) {
        $text = $self->{iconv}->convert($text);
        die("Could not convert charset for template '$template'.\n") unless $text;
    }

    $hash{channel} = $self->{cfg}->{channel};
    # the nick is sanitized here, everything else outside of _template_text
    $hash{nick} = $self->_format_word($hash{nick}) if $hash{nick};

    foreach my $key (sort keys %hash) {
        $text =~ s/\[:$key\]/$hash{$key}/;
    }

    if ($text =~ /\[:[^:]*?:[^:]*?:[^:]*?:\]/o) {
        $text =~ s/\[:([^:]*?):([^:]*?):([^:]*?):\]/$self->_get_subst($1,$2,$3,\%hash)/geo;
    }
    if ($text =~ /\[:[^:]*?:[^:]*?:]/o) {
        $text =~ s/\[:([^:]*?):([^:]*?):]/$self->_get_subst($1,$2,undef,\%hash)/geo;
    }

    return $text;
}

sub _format_word
{
    # This function formats a word -- should ONLY be called on words used alone (EG: not whole line printed)
    my ($self, $word, $nick) = @_; # nick is only defined for user links in top table

    $word = htmlentities($word, $self->{cfg}->{charset});
    $word = $self->_replace_links($word, $nick);
    return $word;
}

sub _format_line
{
    # This function formats a action/normal line to be more readable, and calls any other function
    # that should be executed on every line.
    my ($self, $line) = @_;
    my $hashref;
    if ($hashref = $self->{cfg}->{analyzer}->{parser}->normalline($line)) {
        $line = '<' . $hashref->{nick} . '> ' . $hashref->{saying};
    } elsif ($hashref = $self->{cfg}->{analyzer}->{parser}->actionline($line)) {
        $line = '* ' . $hashref->{nick} . ' ' . $hashref->{saying};
    } elsif ($hashref = $self->{cfg}->{analyzer}->{parser}->thirdline($line)) {
        if (defined($hashref->{kicker})) {
            $line = '*** ' . $hashref->{nick} . ' was kicked by ' . $hashref->{kicker};
            $line .= ' (' . $hashref->{kicktext} . ')' 
                if (defined($hashref->{kicktext}));
        } elsif (defined($hashref->{newtopic})) {
            $line = '*** ' . $hashref->{nick} . ' changes topic to \'' . $hashref->{newtopic} . '\'';
        } elsif (defined($hashref->{newmode})) {
            $line = '*** ' . $hashref->{nick} . ' sets mode ' . $hashref->{newmode};
            $line .= ' ' . $hashref->{modechanges}
                if (defined($hashref->{kicktext}));
        } elsif (defined($hashref->{newjoin})) {
            $line = '*** Joins: ' . $hashref->{nick};
        } elsif (defined($hashref->{newnick})) {
            $line = '*** ' . $hashref->{nick} . ' is now known as ' . $hashref->{newnick};
        } elsif (defined($hashref->{newtopic})) {
            $line = '*** ' . $hashref->{nick} . ' changes topic to: ' . $hashref->{newtopic};
        }
    }
    $line = htmlentities($line, $self->{cfg}->{charset});
    $line = $self->_replace_links($line);
    return $line;
}

sub _get_subst
{
    # This function looks at the user definition and see if there is sex
    # defined. If yes, return the appropriate value. If no, just return the
    # default he/she value.
    my $self = shift;
    my ($m,$f,$d,$hash) = @_;
    if ($hash->{nick} && $self->{users}->{sex}{$hash->{nick}}) {
        if ($self->{users}->{sex}{$hash->{nick}} eq 'm') {
            return $m;
        } elsif ($self->{users}->{sex}{$hash->{nick}} eq 'f') {
            return $f;
        }
    }
    return defined($d) ? $d : "$m/$f";
}

sub _mostusedword
{
    # Word usage statistics
    my $self = shift;

    my %usages;

    foreach my $word (keys %{ $self->{stats}->{wordcounts} }) {
        # Skip people's nicks.
        next if is_nick($word, $self->{cfg}->{cachedir});
        next if (length($word) < $self->{cfg}->{wordlength});
        next unless $self->_has_letters($word);          # ASCII art and punctuation are not words
        $usages{$word} = $self->{stats}->{wordcounts}{$word};
    }


    my @popular = sort { $usages{$b} <=> $usages{$a} } keys %usages;

    if (@popular) {
        $self->_headline($self->_template_text('mostwordstopic'), undef, undef, 'mostwordstopic');

        _html("<table border=\"0\" width=\"$self->{cfg}->{tablewidth}\"><tr>");
        _html("<td>&nbsp;</td><td class=\"tdtop\"><b>" . $self->_template_text('word') . "</b></td>");
        _html("<td class=\"tdtop\"><b>" . $self->_template_text('numberuses') . "</b></td>");
        _html("<td class=\"tdtop\"><b>" . $self->_template_text('lastused') . "</b></td></tr>");


        my $count = 0;
        for(my $i = 0; $count < $self->{cfg}->{wordhistory}; $i++) {
            last unless $i < $#popular+1;
            # Skip nicks.  It's far more efficient to do this here than when
            # @popular is created.
            next if is_ignored($popular[$i]);

            my $a = $count + 1;
            my $popular = $self->_format_word($self->{stats}->{word_upcase}{$popular[$i]});
            my $wordcount = $self->{stats}->{wordcounts}{$popular[$i]};
            my $lastused = $self->_format_word($self->{stats}->{wordnicks}{$popular[$i]});
            my $class;
            if ($a == 1) {
                $class = 'hirankc';
            } else {
                $class = 'rankc';
            }
            _html("<tr><td class=\"$class\">$a</td>");
            _html("<td class=\"hicell\">$popular</td>");
            _html("<td class=\"hicell\">$wordcount</td>");
            _html("<td class=\"hicell\">$lastused</td>");
            _html("</tr>");
            $count++;
        }

        _html("</table>");
    }
}

sub _mostwordsperline
{
    # The person who got the most words per line
    my $self = shift;

    my %wpl = ();
    my $numlines = 0;
    my ($avg, $numwords);
    foreach my $nick (keys %{ $self->{stats}->{words} }) {
        if ($self->{topactive}{$nick} || !$self->{cfg}->{showonlytop}) {
          $wpl{$nick} = sprintf("%.2f", $self->{stats}->{words}{$nick}/$self->{stats}->{lines}{$nick});
          $numlines += $self->{stats}->{lines}{$nick};
          $numwords += $self->{stats}->{words}{$nick};
        }
    }
    if ($numlines > 0) {
        $avg = sprintf("%.2f", $numwords/$numlines);
    }

    my @wpl = sort { $wpl{$b} <=> $wpl{$a} } keys %wpl;

    if (@wpl) {
        my %hash = (
            nick => $wpl[0],
            wpl  => $wpl{$wpl[0]}
        );

        my $text = $self->_template_text('wpl1', %hash);
        _html("<tr><td class=\"hicell\">$text");

        $hash{avg} = $avg;

        $text = $self->_template_text('wpl2', %hash);
        _html("<br /><span class=\"small\">$text</span>");
        _html("</td></tr>");
    }
}

sub _mostreferencednicks
{
    # List showing the most referenced nicks
    my $self = shift;

    my %usages;

    foreach my $word (sort keys %{ $self->{stats}->{wordcounts} }) {
        next if is_ignored($word);
        my $nick = is_nick($word) or next;
        next if !exists $self->{stats}->{lines}{$nick};
        $usages{$word} = $self->{stats}->{wordcounts}{$word};
    }

    my @popular = sort { $usages{$b} <=> $usages{$a} } keys %usages;

    if (@popular) {

        $self->_headline($self->_template_text('referencetopic'), undef, undef, 'referencetopic');

        _html("<table border=\"0\" width=\"$self->{cfg}->{tablewidth}\"><tr>");
        _html("<td>&nbsp;</td><td class=\"tdtop\"><b>" . $self->_template_text('nick') . "</b></td>");
        _html("<td class=\"tdtop\"><b>" . $self->_template_text('numberuses') . "</b></td>");
        _html("<td class=\"tdtop\"><b>" . $self->_template_text('lastused') . "</b></td></tr>");

        for(my $i = 0; $i < $self->{cfg}->{nickhistory}; $i++) {
            last if $i >= @popular;
            my $a = $i + 1;
            my $popular   = $self->_format_word(is_nick($popular[$i]));
            my $wordcount = $self->{stats}->{wordcounts}{$popular[$i]};
            my $lastused  = $self->_format_word($self->{stats}->{wordnicks}{$popular[$i]} || "");
            # this is undefined when a nick is referenced before being used
            # first (this is a minor bug we ignore here, see test/01.cfg)

            my $class;
            if ($a == 1) {
                $class = 'hirankc';
            } else {
                $class = 'rankc';
            }
            _html("<tr><td class=\"$class\">$a</td>");
            _html("<td class=\"hicell\">$popular</td>");
            _html("<td class=\"hicell\">$wordcount</td>");
            _html("<td class=\"hicell\">$lastused</td>");
            _html("</tr>");
        }
        _html("</table>");
    }
}

sub _smileys
{
    my $self = shift;

    my %usages;
    foreach my $smiley (sort keys %{ $self->{stats}->{smileys} }) {
        $usages{$smiley} = $self->{stats}->{smileys}{$smiley};
    }
    my @popular = sort { $usages{$b} <=> $usages{$a} } keys %usages;
    return unless @popular;

    $self->_headline($self->_template_text('smileytopic'), undef, undef, 'smileytopic');

    _html("<table border=\"0\" width=\"$self->{cfg}->{tablewidth}\"><tr>");
    _html("<td>&nbsp;</td><td class=\"tdtop\"><b>" . $self->_template_text('smiley') . "</b></td>");
    _html("<td class=\"tdtop\"><b>" . $self->_template_text('numberuses') . "</b></td>");
    _html("<td class=\"tdtop\"><b>" . $self->_template_text('lastused') . "</b></td></tr>");

    for(my $i = 0; $i < $self->{cfg}->{smileyhistory}; $i++) {
        last if $i >= @popular;
        my $a = $i + 1;
        my $popular   = $self->_format_word($popular[$i]);
        my $count     = $self->{stats}->{smileys}{$popular[$i]};
        my $lastused  = $self->_format_word($self->{stats}->{smileynicks}{$popular[$i]} || "");

        my $class = ($a == 1) ? 'hirankc' : 'rankc';
        _html("<tr><td class=\"$class\">$a</td>");
        _html("<td class=\"hicell\">$popular</td>");
        _html("<td class=\"hicell\">$count</td>");
        _html("<td class=\"hicell\">$lastused</td>");
        _html("</tr>");
    }
    _html("</table>");
}

sub _karma
{
    # List showing the most referenced nicks
    my $self = shift;

    my %karma;

    foreach my $thing (sort keys %{ $self->{stats}->{karma} }) {
        my $Thing = lc(is_nick($thing) || $thing); # FIXME: this is ugly
        foreach my $nick (keys %{ $self->{stats}->{karma}{$thing} }) {
            $karma{$Thing} += $self->{stats}->{karma}{$thing}{$nick};
        }
    }

    my @popular = sort { $karma{$b} <=> $karma{$a} } keys %karma;
    return unless @popular;

    $self->_headline($self->_template_text('karmatopic'), undef, undef, 'karmatopic');

    _html("<table border=\"0\" width=\"$self->{cfg}->{tablewidth}\"><tr>");
    _html("<td>&nbsp;</td><td class=\"tdtop\"><b>" . $self->_template_text('nick') . "</b></td>");
    _html("<td class=\"tdtop\"><b>" . $self->_template_text('karma') . "</b></td>");
    _html("<td class=\"tdtop\"><b>" . $self->_template_text('goodkarma') . "</b></td>");
    _html("<td class=\"tdtop\"><b>" . $self->_template_text('badkarma') . "</b></td></tr>");

    my @goodpos = grep { $karma{$_} > 0 } @popular;
    splice @goodpos, $self->{cfg}->{karmahistory}, @goodpos
        if @goodpos > $self->{cfg}->{karmahistory};
    my @badpos = grep { $karma{$_} < 0 } @popular;
    splice @badpos, 0, @badpos - $self->{cfg}->{karmahistory}
        if @badpos > $self->{cfg}->{karmahistory};

    my $pos = 0;
    foreach my $thing (@goodpos) {
        my $class = ($pos++ == 0) ? 'hirankc' : 'rankc';
        my $Thing = $self->_format_word(is_nick($thing) || $thing); # ugliness #2
        _html("<tr><td class=\"$class\">$pos</td>");
        _html("<td class=\"hicell\">$Thing</td>");
        _html("<td class=\"hicell\">$karma{$thing}</td>");

        my @k = grep { $self->{stats}->{karma}{$thing}{$_} > 0 }
            (keys %{ $self->{stats}->{karma}{$thing} });
        @k = $self->_trimlist(@k);
        my $n = join ', ', map { $self->_format_word($_) } @k;
        _html("<td class=\"hicell\">$n</td>");

        @k = grep { $self->{stats}->{karma}{$thing}{$_} < 0 }
            (keys %{ $self->{stats}->{karma}{$thing} });
        @k = $self->_trimlist(@k);
        $n = join ', ', map { $self->_format_word($_) } @k;
        _html("<td class=\"hicell\">$n</td>");
        _html("</tr>");
    }

    if (@goodpos and @badpos) {
            _html("<tr><td class=\"rankc\"></td>");
            _html("<td class=\"hicell\" colspan=\"4\"></td>");
        _html("</tr>");
    }

    $pos = @badpos;
    foreach my $thing (@badpos) {
        my $class = ($pos == 1) ? 'hirankc' : 'rankc';
        my $Thing = $self->_format_word(is_nick($thing) || $thing);
        _html("<tr><td class=\"$class\">". ($pos--) ."</td>");
        _html("<td class=\"hicell\">$Thing</td>");
        _html("<td class=\"hicell\">$karma{$thing}</td>");

        my @k = grep { $self->{stats}->{karma}{$thing}{$_} > 0 }
            (keys %{ $self->{stats}->{karma}{$thing} });
        @k = $self->_trimlist(@k);
        my $n = join ', ', map { $self->_format_word($_) } @k;
        _html("<td class=\"hicell\">$n</td>");

        @k = grep { $self->{stats}->{karma}{$thing}{$_} < 0 }
            (keys %{ $self->{stats}->{karma}{$thing} });
        @k = $self->_trimlist(@k);
        $n = join ', ', map { $self->_format_word($_) } @k;
        _html("<td class=\"hicell\">$n</td>");
        _html("</tr>");
    }
    _html("</table>");
}

sub _mosturls
{
    # List showing the most referenced URLs
    my $self = shift;

    my @sorturls = sort { $self->{stats}->{urlcounts}{$b} <=> $self->{stats}->{urlcounts}{$a} }
                        keys %{ $self->{stats}->{urlcounts} };

    if (@sorturls) {

        $self->_headline($self->_template_text('urlstopic'), undef, undef, 'urlstopic');

        _html("<table border=\"0\" width=\"$self->{cfg}->{tablewidth}\"><tr>");
        _html("<td>&nbsp;</td><td class=\"tdtop\"><b>" . $self->_template_text('url') . "</b></td>");
        _html("<td class=\"tdtop\"><b>" . $self->_template_text('numberuses') . "</b></td>");
        _html("<td class=\"tdtop\"><b>" . $self->_template_text('lastused') . "</b></td></tr>");

        for(my $i = 0; $i < $self->{cfg}->{urlhistory}; $i++) {
            last unless $i < @sorturls;
            my $a = $i + 1;
            my $urlcount = $self->{stats}->{urlcounts}{$sorturls[$i]};
            my $lastused = $self->{stats}->{urlnicks}{$sorturls[$i]};
            my $printurl = $sorturls[$i];
            if ($printurl and length($printurl) > 60) {
                $printurl = substr($printurl, 0, 60);
            }
            $printurl = htmlentities($printurl, $self->{cfg}->{charset});
            my $linkurl = urlencode($sorturls[$i]);
            my $class = ($a == 1) ? 'hirankc' : 'rankc';
            _html("<tr><td class=\"$class\">$a</td>");
            _html("<td class=\"hicell\"><a href=\"$linkurl\">$printurl</a></td>");
            _html("<td class=\"hicell\">$urlcount</td>");
            _html("<td class=\"hicell\">$lastused</td>");
            _html("</tr>");
        }
        _html("</table>");
    }
}

sub _charts
{
    # List showing the most played songs
    my $self = shift;

    my @sortcharts = sort { $self->{stats}->{chartcounts}{$b} <=> $self->{stats}->{chartcounts}{$a} }
                        keys %{ $self->{stats}->{chartcounts} };

    if (@sortcharts) {

        $self->_headline($self->_template_text('chartstopic'), undef, undef, 'chartstopic');

        _html("<table border=\"0\" width=\"$self->{cfg}->{tablewidth}\"><tr>");
        _html("<td>&nbsp;</td><td class=\"tdtop\"><b>" . $self->_template_text('song') . "</b></td>");
        _html("<td class=\"tdtop\"><b>" . $self->_template_text('numberplayed') . "</b></td>");
        _html("<td class=\"tdtop\"><b>" . $self->_template_text('playedby') . "</b></td></tr>");

        for(my $i = 0; $i < $self->{cfg}->{chartshistory}; $i++) {
            last unless $i < @sortcharts;
            my $a = $i + 1;
            my $song = $sortcharts[$i];
            my $chartcount = $self->{stats}->{chartcounts}{$song};
            my $lastused = $self->{stats}->{chartnicks}{$song};
            $song = $self->{stats}->{word_upcase}{$song};
            $song = substr($song, 0, 60) if (length($song) > 60);
            $song = $self->_format_word($song);
            my $class = ($a == 1) ? 'hirankc' : 'rankc';
            _html("<tr><td class=\"$class\">$a</td>");
            _html("<td class=\"hicell\">$song</td>");
            _html("<td class=\"hicell\">$chartcount</td>");
            _html("<td class=\"hicell\">$lastused</td>");
            _html("</tr>");
        }
        _html("</table>");
    }
}

sub _legend
{
    # A legend showing the timebars and their associated time.
    my $self = shift;
    _html("<table align=\"center\" border=\"0\" width=\"520\"><tr>");
    _html("<td align=\"center\" class=\"asmall\"><img src=\"data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABAQMAAAAl21bKAAAAA1BMVEUAAACnej3aAAAAAXRSTlMAQObYZgAAAApJREFUCNdjYAAAAAIAAeIhvDMAAAAASUVORK5CYII=
\" id=\"$self->{cfg}->{pic_h_0}\" width=\"40\" height=\"15\" align=\"middle\" alt=\"0-5\" /> = 0-5</td>");
    _html("<td align=\"center\" class=\"asmall\"><img src=\"data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABAQMAAAAl21bKAAAAA1BMVEUAAACnej3aAAAAAXRSTlMAQObYZgAAAApJREFUCNdjYAAAAAIAAeIhvDMAAAAASUVORK5CYII=
\" id=\"$self->{cfg}->{pic_h_6}\" width=\"40\" height=\"15\" align=\"middle\" alt=\"6-11\" /> = 6-11</td>");
    _html("<td align=\"center\" class=\"asmall\"><img src=\"data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABAQMAAAAl21bKAAAAA1BMVEUAAACnej3aAAAAAXRSTlMAQObYZgAAAApJREFUCNdjYAAAAAIAAeIhvDMAAAAASUVORK5CYII=
\" id=\"$self->{cfg}->{pic_h_12}\" width=\"40\" height=\"15\" align=\"middle\" alt=\"12-17\" /> = 12-17</td>");
    _html("<td align=\"center\" class=\"asmall\"><img src=\"data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABAQMAAAAl21bKAAAAA1BMVEUAAACnej3aAAAAAXRSTlMAQObYZgAAAApJREFUCNdjYAAAAAIAAeIhvDMAAAAASUVORK5CYII=
\" id=\"$self->{cfg}->{pic_h_18}\" width=\"40\" height=\"15\" align=\"middle\" alt=\"18-23\" /> = 18-23</td>");
    _html("</tr></table>");
}


sub _replace_url # used internally by _replace_links
{
    my ($self, $url, $www, $ftp, $text) = @_;
    $url = "http://$url" if $www;
    $url = "ftp://$url" if $ftp;
    my $texturl = $self->_template_text("newwindow");
    return "<a href=\"$url\" target=\"_blank\" title=\"$texturl $url\">" . $self->_split_long_text($text) . '</a>';
}


sub _replace_email # used internally by _replace_links
{
    my ($self, $mailto, $user, $domain, $nick) = @_;
    $mailto = '' if $nick or not $mailto;
    $nick ||= "$user&#64;$domain"; # obfuscate mail address
    my $textmail = $self->_template_text("mailto");
    return "<a href=\"mailto:$user&#64;$domain\" title=\"$textmail $nick\">" . $self->_split_long_text($mailto . $nick) . "<\/a>";
}


sub _replace_links
{
    # replace URLs and email addresses by links
    my ($self, $str, $nick) = @_; # nick is only defined for user links in top table

    # Regular expressions are taken from match_urls() and match_email() in
    # Common.pm

    my (@str) = split(/ /,$str);

    foreach (@str) {
        s/((?:(?:https?|ftp|telnet|news):\/\/|(?:(?:(www)|(ftp))[\w-]*\.))[-\w\/~\@:]+\.\S+[^\s]+)/$self->_replace_url($1, $2, $3, $nick || $1)/egio
            or s/(mailto:)?([-\w.]+)@([-\w]+\.[-\w.]+)/$self->_replace_email($1, $2, $3, $nick)/egio
            or $_ = $self->_split_long_text($_);
     }

    return join(' ', @str);
}

sub _split_long_text
{
    my ($self, $str) = @_;
    $str =~ s/(\S{$self->{cfg}->{quotewidth}})(?!\s)/$1-<br \/>/og;

    return($str);
}

sub _user_linetimes
{
    my $self = shift;
    my $nick  = shift;
    my $top   = shift;

    my $bar      = "";
    my $len      = ($self->{stats}->{lines}{$nick} / $self->{stats}->{lines}{$top}) * 100;

    for (my $i = 0; $i <= 3; $i++) {
        my $l = $self->{stats}->{line_times}{$nick}[$i];
        next if not defined $l;
        my $w = int(($l / $self->{stats}->{lines}{$nick}) * $len);
        if ($w) {
            my $pic = 'pic_h_'.(6*$i);
            $bar .= "<img src=\"data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABAQMAAAAl21bKAAAAA1BMVEUAAACnej3aAAAAAXRSTlMAQObYZgAAAApJREFUCNdjYAAAAAIAAeIhvDMAAAAASUVORK5CYII=
\" id=\"$self->{cfg}->{$pic}\" border=\"0\" width=\"$w\" height=\"15\" align=\"middle\" alt=\"$l\" title=\"$l\" />";
        }
    }
    return "$bar&nbsp;$self->{stats}->{lines}{$nick}";
}

sub _user_wordtimes
{
    my $self = shift;
    my $nick  = shift;
    my $top   = shift;

    $self->{stats}->{words}{$nick} ||= 0;
    my $len = ($self->{stats}->{words}{$nick} / $self->{stats}->{words}{$top}) * 100;

    my $bar = "";
    for (my $i = 0; $i <= 3; $i++) {
        next if not defined $self->{stats}->{word_times}{$nick}[$i];
        my $w = int(($self->{stats}->{word_times}{$nick}[$i] / $self->{stats}->{words}{$nick}) * $len);
        if ($w) {
            my $pic = 'pic_h_'.(6*$i);
            $bar .= "<img src=\"data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABAQMAAAAl21bKAAAAA1BMVEUAAACnej3aAAAAAXRSTlMAQObYZgAAAApJREFUCNdjYAAAAAIAAeIhvDMAAAAASUVORK5CYII=
\" id=\"$self->{cfg}->{$pic}\" border=\"0\" width=\"$w\" height=\"15\" align=\"middle\" alt=\"\" />";
        }
    }
    return "$bar&nbsp;$self->{stats}->{words}{$nick}";
}

sub _user_times
{
    my $self = shift;
    my ($nick) = @_;

    my $bar = "";
    
    my $itemstat = ($self->{cfg}->{sortbywords} ? 'words' : 'lines');
    my $timestat = ($self->{cfg}->{sortbywords} ? 'word_times' : 'line_times');
    
    for (my $i = 0; $i <= 3; $i++) {
        my $l = $self->{stats}->{$timestat}{$nick}[$i];
        next if not defined $l;
        my $w = int(($l / $self->{stats}->{$itemstat}{$nick}) * 40);
        if ($w) {
            my $pic = 'pic_h_'.(6*$i);
            $bar .= "<img src=\"data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABAQMAAAAl21bKAAAAA1BMVEUAAACnej3aAAAAAXRSTlMAQObYZgAAAApJREFUCNdjYAAAAAIAAeIhvDMAAAAASUVORK5CYII=
\" id=\"$self->{cfg}->{$pic}\" border=\"0\" width=\"$w\" height=\"15\" alt=\"$l\" title=\"$l\" />";
        }
    }
    return $bar;
}

sub _user_pic
{
    my $self = shift;
    my $nick  = shift;
    my $style  = shift;

    return unless $self->{users}->{userpics}{$nick} or $self->{cfg}->{defaultpic};

    my $rowspan = $self->{cfg}->{userpics} ? " rowspan=\"$self->{cfg}->{userpics}\"" : "";
    my $output = "<td $style align=\"center\" valign=\"middle\"$rowspan>";

    my $biguserpic = $self->{users}->{biguserpics}{$nick};
    if ($biguserpic) {
        $biguserpic = $self->{cfg}->{imagepath} .
            randomglob($biguserpic, $self->{cfg}->{imageglobpath}, $nick)
                if $biguserpic !~ /^http:\/\//i;
        $output .= "<a href=\"$biguserpic\">";
    }

    my $pic = $self->{users}->{userpics}{$nick} || $self->{cfg}->{defaultpic};
    $pic = $self->{cfg}->{imagepath} .
        randomglob($pic, $self->{cfg}->{imageglobpath}, $nick)
        unless $pic =~ /^http:\/\//i;
    my $height = $self->{cfg}->{picheight} ? " height=\"$self->{cfg}->{picheight}\"" : "";
    my $width = $self->{cfg}->{picwidth} ? " width=\"$self->{cfg}->{picwidth}\"" : "";
    my $alt = $self->{users}->{userpics}{$nick} ? " alt=\"$nick\" title=\"$nick\"" : ' alt=""';
    my $border = $biguserpic ? ' border="0"' : '';
    my $cls = $self->{users}->{userpics}{$nick} ? '' : ' class="defpic"';      # the shared default picture, so themes can tone it down
    $output .= "<img src=\"$pic\"$cls$width$height$alt$border />";

    $output .= "</a>" if $biguserpic;
    _html("$output</td>");
}

sub _mostnicks
{
    # List showing the user with most used nicks
    my $self = shift;

    my @sortnicks = sort { keys %{ $self->{stats}->{nicks}->{$b} } <=> keys %{ $self->{stats}->{nicks}->{$a} } } 
                                keys %{ $self->{stats}->{nicks} };

    if (keys %{ $self->{stats}->{nicks}->{$sortnicks[0]} } > 1) {

        $self->_headline($self->_template_text('mostnickstopic'), undef, undef, 'mostnickstopic');

        my $names1 = $self->_template_text('names1');
        my $names2 = $self->_template_text('names2');
        my $nick_txt = $self->_template_text('nick');
        my $names_txt = $self->_template_text('names');
        _html("<table border=\"0\" width=\"$self->{cfg}->{tablewidth}\"><tr>");
        _html("<td>&nbsp;</td><td class=\"tdtop\"><b>$nick_txt</b></td>");
        _html("<td class=\"tdtop\"><b>$names_txt</b></td></tr>");

        my $a = 0;
        foreach my $nick (@sortnicks) {
            next if is_ignored($nick);
            my $nickcount = keys %{ $self->{stats}->{nicks}->{$nick} };
            my @nicks = values %{ $self->{stats}->{nicks}->{$nick} };
            my $nickused = join(", ", $self->_trimlist(@nicks));

            last unless ($nickcount > 1);

            $a++;
            my $class = $a == 1 ? 'hirankc' : 'rankc';
            my $n = $nickcount > 1 ? $names1 : $names2;

            _html("<tr><td class=\"$class\">$a</td>");
            if ($self->{cfg}->{mostnicksverbose}) { 
                _html("<td class=\"hicell\">$nick ($nickcount $n)</td>");
                _html("<td class=\"hicell\" valign='top'>$nickused</td>");
            } else {
                _html("<td class=\"hicell\">$nick</td>");
                _html("<td class=\"hicell\" valign='top'>$nickcount $n</td>");
            }
            _html("</tr>");
            last if $a >= $self->{cfg}->{mostnickshistory};
        }
        _html("</table>");
    }
}

sub _mostactivebyhour
{
    # Charts for most active nicks by hour (0-5, 6-11, 12-17, 18-23)
    my $self = shift;

    my $sortnicks;

    my $lastline=-1;
    my $maxlines=0;

    foreach my $period (0,1,2,3) {
        my @sortnicks =
        sort
        {
              (defined $self->{stats}->{line_times}{$b}[$period]?$self->{stats}->{line_times}{$b}[$period]:0)
              <=>
              (defined $self->{stats}->{line_times}{$a}[$period]?$self->{stats}->{line_times}{$a}[$period]:0)
        }
        keys %{ $self->{stats}->{line_times} } ;

        for(my $i = 0; $i < $self->{cfg}->{activenicksbyhour}; $i++) {
            next if ! $sortnicks[$i];
            next if is_ignored($sortnicks[$i]);
            last unless $i < @sortnicks;

            my $nick=$sortnicks[$i];
            my $count=$self->{stats}->{line_times}{$nick}[$period] || 0;

            last unless $nick;
            last unless $count;

            $sortnicks->[$period][$i]=$nick;

            if ($lastline<$i) {
              $lastline=$i;
            }


            if ($maxlines<$count) {
              $maxlines=$count;
            }
        }
    }

    if ($lastline>=0) {

        $self->_headline($self->_template_text('activenickbyhourtopic'), undef, undef, 'activenickbyhourtopic');

        _html("<table border=\"0\" width=\"$self->{cfg}->{tablewidth}\"><tr>");
        _html("<td>&nbsp;</td>");
        _html("<td class=\"tdtop\"><b>0-5</b></td>");
        _html("<td class=\"tdtop\"><b>6-11</b></td>");
        _html("<td class=\"tdtop\"><b>12-17</b></td>");
        _html("<td class=\"tdtop\"><b>18-23</b></td>");
        _html("</tr>");

        for(my $i = 0; $i <= $lastline; $i++) {

            my $a = $i + 1;
            my $class = $a == 1 ? 'hirankc' : 'rankc';

            _html("<tr><td class=\"$class\">$a</td>");
            foreach my $period (0,1,2,3) {
                my $nick=$sortnicks->[$period][$i];
                if ($nick) {
                    my $count=$self->{stats}->{line_times}{$nick}[$period];
                    if ($count) {
                        _html("<td class=\"hicell\">");
                        if ($self->{cfg}->{showmostactivebyhourgraph}) {
                            my $pic = 'pic_h_'.(6*$period);
                            my $w = int(($count / $maxlines) * 100) || 1;
                            _html("<img src=\"data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABAQMAAAAl21bKAAAAA1BMVEUAAACnej3aAAAAAXRSTlMAQObYZgAAAApJREFUCNdjYAAAAAIAAeIhvDMAAAAASUVORK5CYII=
\" id=\"$self->{cfg}->{$pic}\" border=\"0\" width=\"$w\" height=\"15\" align=\"middle\" alt=\"\" />");
                        }
                        _html($self->_format_word($nick)." - ".$count);
                        _html("</td>");
                    } else {
                        _html("<td class=\"hicell\">&nbsp;</td>");
                    }
                } else {
                  _html("<td class=\"hicell\">&nbsp;</td>");
                }
            }
            _html("</tr>");
        }
        _html("</table>");
    }
}

sub _topactive {
    my $self = shift;
    my @top_active;
    my $top_nicks;

    if ($self->{cfg}->{sortbywords}) {
        @top_active = sort { $self->{stats}->{words}{$b} <=> $self->{stats}->{words}{$a} } 
                             keys %{ $self->{stats}->{words} };
        $top_nicks = scalar keys %{ $self->{stats}->{words} };
    } else {
        @top_active = sort { $self->{stats}->{lines}{$b} <=> $self->{stats}->{lines}{$a} } 
                             keys %{ $self->{stats}->{lines} };
        $top_nicks = scalar keys %{ $self->{stats}->{lines} };
    }   
            
    if ($self->{cfg}->{activenicks} > $top_nicks) {
        $self->{cfg}->{activenicks} = $top_nicks;
    } 
    if (($self->{cfg}->{activenicks}+$self->{cfg}->{activenicks2}) > $top_nicks) {
        $self->{cfg}->{activenicks2} = $top_nicks-$self->{cfg}->{activenicks};
    }
            
    (@top_active) = @top_active[0..($self->{cfg}->{activenicks}-1)];
    $self->{stats}->{topactive_lines} = @top_active ? $self->{stats}->{lines}{$top_active[0]} : 1;
            
    foreach (@top_active) {
        $self->{topactive}{$_} = 1;
    }
} 


sub _istoponly {
    my $self = shift;
    my (@nicks_tmp) = @_;
    my @nicks;
    my $cnt=0;

    if ($self->{cfg}->{showonlytop}) {
        foreach my $nick (@nicks_tmp) {
            if ($self->{topactive}{$nick}) {
                push(@nicks, $nick);
            }
        }
        return(@nicks);
    } else {
        return(@nicks_tmp);
    }
}

sub _trimlist {
    my $self = shift;
    return @_ unless $self->{cfg}->{nicklimit};
    splice @_, $self->{cfg}->{nicklimit}, @_, qw/.../ if @_ > $self->{cfg}->{nicklimit};
    return @_;
}

sub _activegenders {
    # The most active gender in the channel
    my $self = shift;
    my @topgender = sort {$self->{stats}->{sex_lines}{$b} <=> $self->{stats}->{sex_lines}{$a}} keys %{$self->{stats}->{sex_lines}};

    return unless @topgender;

    $self->_headline($self->_template_text('activegenderstopic'), undef, undef, 'activegenderstopic');
    _html("<table border=\"0\" width=\"$self->{cfg}->{tablewidth}\"><tr>");
    _html(" <td>&nbsp;</td>"
    . "<td class=\"tdtop\"><b>" . $self->_template_text('gender') . "</b></td>"
    . "<td class=\"tdtop\"><b>" . $self->_template_text('numberlines') . "</b></td>"
    . "<td class=\"tdtop\"><b>" . $self->_template_text('nick') . "</b></td>"
    );

    my $i = 1;
    for my $gender (@topgender) {
        my $bar = "";
        my $len = ($self->{stats}->{sex_lines}{$gender} / $self->{stats}->{sex_lines}{$topgender[0]}) * 100;

        for (0 .. 3) {
            next if not defined $self->{stats}->{sex_line_times}{$gender}[$_];
            my $w = int(($self->{stats}->{sex_line_times}{$gender}[$_] / $self->{stats}->{sex_lines}{$gender}) * $len);
            if ($w) {
                my $pic = 'pic_h_'.(6*$_);
                $bar .= "<img src=\"data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABAQMAAAAl21bKAAAAA1BMVEUAAACnej3aAAAAAXRSTlMAQObYZgAAAApJREFUCNdjYAAAAAIAAeIhvDMAAAAASUVORK5CYII=
\" id=\"$self->{cfg}->{$pic}\" border=\"0\" width=\"$w\" height=\"15\" align=\"middle\" alt=\"$self->{stats}->{sex_line_times}{$gender}[$_]\" />";
            }
        }

        my @top_active = sort { $self->{stats}->{lines}{$b} <=> $self->{stats}->{lines}{$a} }
            grep { $self->{users}->{sex}{$_} and $self->{users}->{sex}{$_} eq $gender }
            keys %{ $self->{stats}->{lines} };
        my $nicklist = join ", ",
            map { $_ . ($self->{stats}->{lines}{$_} ? " ($self->{stats}->{lines}{$_})" : "") }
            $self->_trimlist(@top_active);

        my $class = ($i == 1 ? "hirankc" : "rankc");
        my $span_class = $gender eq 'm' ? "male" : ($gender eq 'f' ? "female" : "bot");
        _html("</tr><tr>");
        _html(" <td class=\"$class\" align=\"left\">$i</td>");
        _html(" <td class=\"hicell\"><span class=\"$span_class\">" . $self->_template_text("gender_$gender") . "</span></td>");
        _html(" <td class=\"hicell\"><span style=\"white-space:nowrap;\">$bar</span> $self->{stats}->{sex_lines}{$gender}</td>");
        _html(" <td class=\"hicell\">$nicklist</td>");
        $i++;
    }

    _html("</tr></table>");
}

1;

__END__

=head1 NAME

Pisg::HTMLGenerator - class to create a static HTML page out of data parsed

=head1 DESCRIPTION

C<Pisg::HTMLGenerator> uses the hash returned by Pisg::Parser::Logfile and turns it into a static HTML page.

=head1 SYNOPSIS

    use Pisg::HTMLGenerator;

    $generator = new Pisg::HTMLGenerator(
        cfg => $cfg,
        stats => $stats,
        users => $users,
        tmps => $tmps
    );

=head1 CONSTRUCTOR

=over 4

=item new ( [ OPTIONS ] )

This is the constructor for a new Pisg::HTMLGenerator object. C<OPTIONS> are passed in a hash like fashion using key and value pairs.

Possible options are:

B<cfg> - hashref containing configuration variables, created by the Pisg module.

B<stats> - reference to the hash returned by Pisg::Parser::Logfile containing all stats.

B<users> - reference to a hash containg user information

B<tmps> - reference to a hash containing the language templates.

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
