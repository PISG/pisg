package Pisg::HTMLGenerator;

# Extra sections for the stats page, added to Pisg::HTMLGenerator:
#
#   overview            key numbers at a glance
#   relations           who talks to whom: interactive map, closest pairs, social roles
#   time personalities  night owls, early birds ...
#   concentration       how much of the channel the top talkers write
#   signature words     the word each regular owns
#   navbar              a sticky bar to jump to any section
#
# Everything here reads data pisg already collected (plus who-talks-to-whom from
# Pisg::Parser::Logfile). Each section has its own Show... option.

use strict;
use warnings;
use Pisg::Common;
use JSON::PP ();
use Encode ();

my @BUCKET_KEYS = qw(rel_time0 rel_time1 rel_time2 rel_time3);

# ---- small helpers ---------------------------------------------------------------

# Run one of the extra sections; if it fails, say so and carry on. The rest of the page
# is more important than any one extra section.
sub _ins_safe
{
    my ($self, $method) = @_;
    return if eval { $self->$method(); 1 };
    my $err = $@;
    $err =~ s/\s+$//;
    print STDERR "Warning: skipped the '$method' section: $err\n";
}

sub _ins_num
{
    my ($self, $n) = @_;
    $n = int($n + 0.5);
    1 while $n =~ s/^(-?\d+)(\d{3})/$1,$2/;
    return $n;
}

sub _ins_esc { my ($self, $t) = @_; return htmlentities($t, $self->{cfg}->{charset}); }

# A "word" needs at least two real letters: ASCII art, punctuation and lone symbols are not words.
sub _has_letters
{
    my ($self, $w) = @_;
    my $u = eval { Encode::decode('UTF-8', $w, Encode::FB_CROAK | Encode::LEAVE_SRC) };
    $u = $w unless defined $u;
    return $u =~ /\p{L}{2}/ ? 1 : 0;
}

sub _ins_isbot
{
    my ($self, $nick) = @_;
    return 1 if is_ignored($nick);
    my $sex = $self->{users}->{sex}{$nick};
    return ($sex && $sex eq 'b') ? 1 : 0;
}

# Nicks that are people (not ignored, not marked as bots), busiest first.
sub _ins_humans
{
    my $self = shift;
    return $self->{ins_humans} ||= do {
        my $l = $self->{stats}->{lines};
        [ sort { $l->{$b} <=> $l->{$a} or $a cmp $b } grep { !$self->_ins_isbot($_) } keys %$l ];
    };
}

# How many lines a nick needs before we rank it on things like "night owl".
sub _ins_minlines
{
    my $self = shift;
    my $t = $self->{cfg}->{bignumbersthreshold};
    $t = 0 unless defined $t and $t =~ /^\d+(?:\.\d+)?$/;
    return $t < 20 ? 20 : ($t > 100 ? 100 : $t);
}

sub _ins_json
{
    my ($self, $data) = @_;
    # Bytes in, bytes out (no utf8 layer), like the rest of the page. The escapes stop
    # anything in a nick from closing the <script> element or starting a tag.
    my $json = JSON::PP->new->canonical->encode($data);
    $json =~ s/</\\u003c/g;
    $json =~ s/>/\\u003e/g;
    $json =~ s/&/\\u0026/g;
    return $json;
}

# Small CSS/JS files live next to the themes (layout/). Read like a stylesheet.
sub _ins_slurp
{
    my ($self, $name) = @_;
    my $file = $self->{cfg}->{cssdir} . $name;
    my $fh;
    open($fh, '<', $file) or open($fh, '<', $self->{cfg}->{search_path} . "/$file") or return '';
    local $/;
    my $text = <$fh>;
    close($fh);
    return $text;
}

# ---- navbar ----------------------------------------------------------------------

# Sections that read fine in half the width. On a wide screen two of them sit side by side; the tables
# and charts that need the whole width keep it. The key is the language-independent template name.
my %HALF = map { $_ => 1 } qw(bignumtopic othernumtopic latesttopic mostwordstopic referencetopic
    smileytopic karmatopic urlstopic chartstopic mostnickstopic activegenderstopic
    concentrationtopic signaturetopic);
sub _card_is_half { my ($self, $key) = @_; return defined $key && $HALF{$key} ? 1 : 0; }

# Shorten a label to $max characters, at a word boundary, without ever cutting a
# multi-byte UTF-8 character in half.
sub _ins_cut
{
    my ($self, $text, $max) = @_;
    my $utf8 = $self->{cfg}->{charset} =~ /^utf-?8$/i;
    my $chars = $utf8 ? Encode::decode('UTF-8', $text, Encode::FB_DEFAULT) : $text;
    return $text if length($chars) <= $max;
    $chars = substr($chars, 0, $max);
    $chars =~ s/\s+\S*$// if $chars =~ /\s/;              # back up to the last whole word
    $chars .= '...';
    return $utf8 ? Encode::encode('UTF-8', $chars) : $chars;
}

# Called by _headline for every section: remember it so the navbar can link to it.
sub _nav_register
{
    my ($self, $title, $id, $label) = @_;
    my $plain = $title;
    $plain =~ s/<[^>]*>//g;
    unless (defined $label and length $label) {
        $label = $plain;
        $label =~ s/\s*\(.*$//;                     # "Daily activity (last 31 days)" -> "Daily activity"
        $label =~ s/^\s+|\s+$//g;
        $label = $self->_ins_cut($label, 30);
    }
    my $n = scalar @{ $self->{nav} ||= [] } + 1;
    unless (defined $id and length $id) {
        # A readable id from the title, but not when the title has accents or another script
        # (they would be mangled): those get a plain number instead.
        if ($plain =~ /[\x80-\xFF]/) {
            $id = '';
        } else {
            ($id = lc $plain) =~ s/[^a-z0-9]+/-/g;
            $id =~ s/^-+|-+$//g;
        }
    }
    $id = "section-$n" unless length $id;
    $id = "$id-$n" if grep { $_->{id} eq $id } @{ $self->{nav} };
    push @{ $self->{nav} }, { id => $id, label => $label, full => $plain };
    return $id;
}

# The marker sits where the bar goes; it is replaced once every section is known.
sub _nav_marker { my $self = shift; _html('<!--PISG_NAV-->') if $self->_nav_wanted; }

sub _nav_wanted
{
    my $self = shift;
    return $self->{cfg}->{shownavbar} && $self->{cfg}->{colorscheme} ne 'none';
}

sub _insert_navbar
{
    my $self = shift;
    return unless $self->_nav_wanted;
    my @items = @{ $self->{nav} || [] };
    my $path = $self->{outfile_tmp} or return;            # the page is finished in a temp file, see create_output
    open(my $in, '<', $path) or return;
    local $/;
    my $page = <$in>;
    close($in);

    my $bar = '';
    if (@items > 1) {
        # Two lists from the same links; the stylesheet shows one of them.
        #  * narrow screens: one slim bar (where you are + a button that opens the whole list), a
        #    native <details>, so it works even without JavaScript;
        #  * wide screens: a fixed menu down the left side, always open.
        my $label = $self->_template_text('nav_label');
        my $chan  = $self->_ins_esc($self->{cfg}->{channel});
        my $links = join('', map { '<li><a href="#' . $_->{id} . '" title="' . $self->_ins_esc($_->{full} || $_->{label}) . '">'
                                   . $self->_ins_esc($_->{label}) . '</a></li>' } @items);
        $bar = '<nav class="pisg-nav" id="pisg-nav" aria-label="' . $label . '"><details class="nav-menu">'
             . '<summary><span class="nav-current" id="nav-current">' . $self->_ins_esc($items[0]{label}) . '</span>'
             . '<span class="nav-toggle">' . $label . '</span></summary><ul class="nav-list">' . $links . '</ul></details>'
             . '<div class="nav-side"><a class="nav-brand" href="#pagetitle1">' . $chan . '</a>'
             . '<ul class="nav-side-list">' . $links . '</ul></div></nav>';
    }
    $page =~ s/<!--PISG_NAV-->/$bar/;

    if (open(my $out, '>', $path)) {
        print $out $page;
        close($out);
    }
}

# ---- CSS for pages whose theme has never heard of these sections ---------------------

sub _ins_basecss { my $self = shift; return $self->_ins_slurp('insights-base.css'); }

# ---- overview --------------------------------------------------------------------

sub _insights_overview
{
    my $self = shift;
    my $st = $self->{stats};
    my $humans = $self->_ins_humans;
    return unless @$humans;

    my ($lines, $words, $questions, $joins, $kicks, $links, $distinct) = (0) x 7;
    $lines += $_ for values %{ $st->{lines} || {} };
    $words += $_ for values %{ $st->{words} || {} };
    $questions += $_ for values %{ $st->{questions} || {} };
    $joins += $_ for values %{ $st->{joins} || {} };
    $kicks += $_ for values %{ $st->{kicked} || {} };
    for my $u (values %{ $st->{urlcounts} || {} }) { $links += $u; $distinct++; }
    return unless $lines;

    my $days = $st->{days} || 1;
    my $times = $st->{times} || {};
    my $total = 0;
    $total += $_ for values %$times;
    my ($busy, $quiet) = (0, 0);
    my ($bmax, $qmin) = (-1, undef);
    for my $h (0 .. 23) {
        my $v = $times->{ sprintf('%02d', $h) } || 0;
        ($bmax, $busy) = ($v, $h) if $v > $bmax;
        ($qmin, $quiet) = ($v, $h) if !defined $qmin or $v < $qmin;
    }
    my $pct = sub { my ($n, $d) = @_; return $d ? sprintf('%.1f', 100 * $n / $d) : '0.0' };
    my $hourfmt = sub { my $h = shift; return sprintf('%02d:00-%02d:00', $h, ($h + 1) % 24) };
    my $top = $humans->[0];

    # The first three numbers become the headline sentence; the rest is a list of facts.
    my @facts = (
        [ 'ov_words',     $self->_ins_num($words),                  '' ],
        [ 'ov_lpd',       $self->_ins_num($lines / $days),          '' ],
        [ 'ov_busy',      $hourfmt->($busy),  $self->_template_text('ov_pct_sub', pct => $pct->($bmax, $total)) ],
        [ 'ov_quiet',     $hourfmt->($quiet), $self->_template_text('ov_pct_sub', pct => $pct->($qmin, $total)) ],
        [ 'ov_questions', $self->_ins_num($questions), $self->_template_text('ov_pct_lines_sub', pct => $pct->($questions, $lines)) ],
        [ 'ov_links',     $self->_ins_num($links),     $self->_template_text('ov_links_sub', distinct => $self->_ins_num($distinct)) ],
        [ 'ov_top',       $self->_ins_esc($top),       $self->_template_text('ov_pct_lines_sub', pct => $pct->($st->{lines}{$top}, $lines)) ],
    );
    push @facts, [ 'ov_joins', $self->_ins_num($joins), '' ] if $joins;
    push @facts, [ 'ov_kicks', $self->_ins_num($kicks), '' ] if $kicks;

    $self->_headline($self->_template_text('overviewtopic'), 'overview');
    _html('<p class="hero">' . $self->_template_text('ov_hero',
        lines => '<b>' . $self->_ins_num($lines) . '</b>',
        nicks => '<b>' . $self->_ins_num(scalar keys %{ $st->{lines} }) . '</b>',
        days  => '<b>' . $self->_ins_num($days) . '</b>') . '</p>');
    _html('<dl class="facts">');
    for my $f (@facts) {
        _html('<div class="fact"><dt>' . $self->_template_text($f->[0]) . '</dt><dd>' . $f->[1]
            . (length $f->[2] ? '<small>' . $f->[2] . '</small>' : '') . '</dd></div>');
    }
    _html('</dl>');
}

# ---- who talks to whom -------------------------------------------------------------

# Strength of a connection: a line addressed to someone counts most, then a mention,
# then answering right after them.
sub _ins_strength { my ($self, $d, $m, $x) = @_; return 3 * $d + $m + $x; }

# Everything the relation sections need, worked out once.
sub _ins_relations
{
    my $self = shift;
    return $self->{ins_rel} if $self->{ins_rel};

    my $st = $self->{stats};
    my $rel = $st->{relations} || {};
    my %isbot;
    my %pair;                                   # "a\0b" (a lt b) => {a,b, ab=>[d,m,x], ba=>[d,m,x]}
    my (%in, %out, %listen, %partners);         # per nick

    for my $from (keys %$rel) {
        next if $isbot{$from} //= $self->_ins_isbot($from);
        for my $to (keys %{ $rel->{$from} }) {
            next if $isbot{$to} //= $self->_ins_isbot($to);
            my ($d, $m, $x) = @{ $rel->{$from}{$to} };
            my ($lo, $hi) = $from lt $to ? ($from, $to) : ($to, $from);
            my $p = $pair{"$lo\0$hi"} ||= { a => $lo, b => $hi, ab => [0, 0, 0], ba => [0, 0, 0] };
            my $slot = $from eq $lo ? 'ab' : 'ba';
            my @v = ($d, $m, $x);
            $p->{$slot}[$_] += $v[$_] for 0 .. 2;
        }
    }
    for my $p (values %pair) {
        my ($ab, $ba) = ($p->{ab}, $p->{ba});
        $p->{w} = $self->_ins_strength($ab->[0] + $ba->[0], $ab->[1] + $ba->[1], $ab->[2] + $ba->[2]);
        my ($lo, $hi) = ($p->{a}, $p->{b});
        $out{$lo} += 3 * $ab->[0] + $ab->[1];   $out{$hi} += 3 * $ba->[0] + $ba->[1];
        $in{$hi}  += 3 * $ab->[0] + $ab->[1];   $in{$lo}  += 3 * $ba->[0] + $ba->[1];
        $listen{$hi} += $ab->[2];               $listen{$lo} += $ba->[2];   # x for lo->hi = hi answered lo
        push @{ $partners{$lo} }, [$hi, $p->{w}];
        push @{ $partners{$hi} }, [$lo, $p->{w}];
    }
    $self->{ins_rel} = { pair => \%pair, in => \%in, out => \%out, listen => \%listen, partners => \%partners };
    return $self->{ins_rel};
}

sub _insights_relations
{
    my $self = shift;
    my $st = $self->{stats};
    return unless $st->{relations} and %{ $st->{relations} };
    my $r = $self->_ins_relations;
    my $humans = $self->_ins_humans;
    my $limit = $self->{cfg}->{relationnicks} || 30;
    my @nodes = @$humans[0 .. ($limit > @$humans ? $#$humans : $limit - 1)];
    return if @nodes < 2;
    my %idx;
    @idx{@nodes} = 0 .. $#nodes;
    my $minw = $self->{cfg}->{relationminweight};

    my @edges;
    for my $p (sort { $b->{w} <=> $a->{w} } values %{ $r->{pair} }) {
        next unless exists $idx{ $p->{a} } and exists $idx{ $p->{b} } and $p->{w} >= $minw;
        push @edges, { a => $idx{ $p->{a} }, b => $idx{ $p->{b} }, w => $p->{w}, ab => $p->{ab}, ba => $p->{ba} };
        last if @edges >= 150;
    }
    return unless @edges;

    my @jnodes;
    for my $n (@nodes) {
        my @top = sort { $b->[1] <=> $a->[1] } @{ $r->{partners}{$n} || [] };
        splice(@top, 5) if @top > 5;
        push @jnodes, {
            id       => $n,
            lines    => 0 + $st->{lines}{$n},
            words    => 0 + ($st->{words}{$n} || 0),
            hours    => [ map { 0 + ($_ || 0) } @{ $st->{line_times}{$n} || [] }[0 .. 3] ],
            partners => [ map { [ $_->[0], 0 + $_->[1] ] } @top ],
        };
    }
    my $i18n = { map { $_ => $self->_template_text($_) } qw(
        rel_pick rel_lines rel_words rel_active rel_partners rel_between rel_toward rel_strength
        rel_direct rel_mentions rel_replies rel_time0 rel_time1 rel_time2 rel_time3 rel_nolinks ) };

    $self->_headline($self->_template_text('relationstopic'), 'relations');
    _html('<p class="intro">' . $self->_template_text('rel_intro') . '</p>');
    _html('<div class="relmap" id="relmap">'
        . '<div class="relmap-canvas"><svg id="relmap-svg" role="img" aria-label="' . $self->_template_text('relationstopic')
        . '" viewBox="0 0 960 620" preserveAspectRatio="xMidYMid meet"></svg></div>'
        . '<div class="relmap-side"><div class="relmap-legend">'
        . join('', map { '<span class="lg lg' . $_ . '"><i></i>' . $self->_template_text($BUCKET_KEYS[$_]) . '</span>' } 0 .. 3)
        . '</div><div class="relmap-info" id="relmap-info" aria-live="polite">' . $self->_template_text('rel_pick') . '</div></div>'
        . '</div>');
    _html('<noscript><p class="intro">' . $self->_template_text('rel_nojs') . '</p></noscript>');
    _html('<script type="application/json" id="relmap-data">' . $self->_ins_json({ nodes => \@jnodes, edges => \@edges, i18n => $i18n }) . '</script>');
    $self->{ins_script_relmap} = 1;

    $self->_insights_pairs;
    $self->_insights_roles;
}

sub _insights_pairs
{
    my $self = shift;
    my $r = $self->_ins_relations;
    my @top = sort { $b->{w} <=> $a->{w} or $a->{a} cmp $b->{a} } values %{ $r->{pair} };
    my $max = $self->{cfg}->{nickhistory} > 10 ? $self->{cfg}->{nickhistory} : 10;
    splice(@top, $max) if @top > $max;
    return unless @top;

    $self->_headline($self->_template_text('pairstopic'), 'pairs');
    _html('<table border="0" width="' . $self->{cfg}->{tablewidth} . '"><tr><td>&nbsp;</td>'
        . '<td class="tdtop"><b>' . $self->_template_text('pair') . '</b></td>'
        . '<td class="tdtop"><b>' . $self->_template_text('rel_strength') . '</b></td>'
        . '<td class="tdtop"><b>' . $self->_template_text('pair_detail') . '</b></td></tr>');
    my $i = 0;
    for my $p (@top) {
        $i++;
        my $wid = int(100 * $p->{w} / $top[0]{w});
        my ($ab, $ba) = ($p->{ab}, $p->{ba});
        my $detail = $self->_template_text('pair_line', a => $self->_ins_esc($p->{a}), b => $self->_ins_esc($p->{b}),
            ad => $ab->[0], am => $ab->[1], bd => $ba->[0], bm => $ba->[1], replies => $ab->[2] + $ba->[2]);
        _html('<tr><td class="' . ($i == 1 ? 'hirankc' : 'rankc') . '" align="left">' . $i . '</td>'
            . '<td class="hicell"><b>' . $self->_ins_esc($p->{a}) . '</b> &harr; <b>' . $self->_ins_esc($p->{b}) . '</b></td>'
            . '<td class="hicell"><div class="bar"><span style="width:' . ($wid || 1) . '%"></span></div> ' . $self->_ins_num($p->{w}) . '</td>'
            . '<td class="hicell small">' . $detail . '</td></tr>');
    }
    _html('</table>');
}

sub _insights_roles
{
    my $self = shift;
    my $st = $self->{stats};
    my $r = $self->_ins_relations;
    my $min = $self->_ins_minlines;
    my @pool = grep { $st->{lines}{$_} >= $min } @{ $self->_ins_humans };
    return unless @pool >= 3;

    my $best = sub {
        my ($score, $desc) = @_;              # highest score wins
        my ($win, $ws) = (undef, undef);
        for my $n (@pool) {
            my $s = $score->($n);
            ($win, $ws) = ($n, $s) if defined $s and (!defined $ws or $s > $ws);
        }
        return ($win, $ws);
    };
    my $strong = sub {                        # partners with a real connection
        my $n = shift;
        return scalar grep { $_->[1] >= 5 } @{ $r->{partners}{$n} || [] };
    };
    my @roles;
    my ($n, $v);
    ($n, $v) = $best->(sub { $r->{in}{ $_[0] } || 0 });
    push @roles, [ 'role_talkedto', $n, $self->_template_text('role_talkedto_v', n => $self->_ins_num($v)) ] if $n and $v;
    ($n, $v) = $best->(sub { $r->{out}{ $_[0] } ? 100 * $r->{out}{ $_[0] } / (3 * $st->{lines}{ $_[0] }) : 0 });
    push @roles, [ 'role_outgoing', $n, $self->_template_text('role_outgoing_v', pct => sprintf('%.0f', $v)) ] if $n and $v;
    ($n, $v) = $best->(sub { $strong->($_[0]) });
    push @roles, [ 'role_connector', $n, $self->_template_text('role_connector_v', n => $v) ] if $n and $v;
    ($n, $v) = $best->(sub { $r->{listen}{ $_[0] } || 0 });
    push @roles, [ 'role_listener', $n, $self->_template_text('role_listener_v', n => $self->_ins_num($v)) ] if $n and $v;
    ($n, $v) = $best->(sub { $st->{lines}{ $_[0] } / (1 + $strong->($_[0])) });
    push @roles, [ 'role_lonewolf', $n, $self->_template_text('role_lonewolf_v', lines => $self->_ins_num($st->{lines}{$n}), n => $strong->($n)) ] if $n;
    return unless @roles;

    $self->_headline($self->_template_text('rolestopic'), 'roles');
    _html('<div class="cardgrid">');
    for my $ro (@roles) {
        _html('<div class="minicard"><span class="mc-title">' . $self->_template_text($ro->[0]) . '</span>'
            . '<span class="mc-name">' . $self->_ins_esc($ro->[1]) . '</span>'
            . '<span class="mc-desc">' . $self->_template_text($ro->[0] . '_d') . '</span>'
            . '<span class="mc-value">' . $ro->[2] . '</span></div>');
    }
    _html('</div>');
}

# ---- time personalities -------------------------------------------------------------

sub _insights_personalities
{
    my $self = shift;
    my $st = $self->{stats};
    my $min = $self->_ins_minlines;
    my @pool = grep { $st->{lines}{$_} >= $min and $st->{line_times}{$_} } @{ $self->_ins_humans };
    return unless @pool >= 4;

    my @cols;
    for my $bk (0 .. 3) {
        my @rank;
        for my $n (@pool) {
            my $sum = 0;
            $sum += $_ || 0 for @{ $st->{line_times}{$n} }[0 .. 3];
            next unless $sum;
            push @rank, [ $n, 100 * ($st->{line_times}{$n}[$bk] || 0) / $sum ];
        }
        @rank = sort { $b->[1] <=> $a->[1] or $st->{lines}{ $b->[0] } <=> $st->{lines}{ $a->[0] } or $a->[0] cmp $b->[0] } @rank;
        splice(@rank, 3) if @rank > 3;
        push @cols, \@rank;
    }
    $self->_headline($self->_template_text('persontopic'), 'personalities');
    _html('<div class="cardgrid">');
    my @names = qw(per_night per_morning per_afternoon per_evening);
    for my $bk (0 .. 3) {
        my ($from, $to) = ($bk * 6, $bk * 6 + 5);
        _html('<div class="minicard t' . $bk . '"><span class="mc-title">' . $self->_template_text($names[$bk]) . '</span>'
            . '<span class="mc-desc">' . $self->_template_text('per_range', from => $from, to => $to) . '</span><ol class="mc-list">'
            . join('', map { '<li><b>' . $self->_ins_esc($_->[0]) . '</b> <span>' . sprintf('%.0f', $_->[1]) . '%</span></li>' } @{ $cols[$bk] })
            . '</ol></div>');
    }
    _html('</div>');
}

# ---- concentration ------------------------------------------------------------------

sub _insights_concentration
{
    my $self = shift;
    my $st = $self->{stats};
    my @humans = @{ $self->_ins_humans };
    return unless @humans >= 3;
    my $total = 0;
    $total += $st->{lines}{$_} for @humans;
    return unless $total;

    my ($run, $half, %at) = (0, 0);
    my $i = 0;
    for my $n (@humans) {
        $run += $st->{lines}{$n};
        $i++;
        $at{$i} = 100 * $run / $total;
        $half ||= $i if $run * 2 >= $total;
    }
    my @steps = grep { $_ <= @humans } (1, 3, 5, 10, 20);
    $self->_headline($self->_template_text('concentrationtopic'), 'concentration', undef, 'concentrationtopic');
    _html('<p class="intro">' . $self->_template_text('conc_half', n => $half) . '</p>');
    _html('<table border="0" width="' . $self->{cfg}->{tablewidth} . '">');
    for my $s (@steps) {
        _html('<tr><td class="hicell" style="width:9em">' . $self->_template_text('conc_top', n => $s) . '</td>'
            . '<td class="hicell"><div class="bar"><span style="width:' . sprintf('%.1f', $at{$s}) . '%"></span></div></td>'
            . '<td class="hicell" style="width:5em">' . sprintf('%.1f', $at{$s}) . '%</td></tr>');
    }
    _html('</table>');
}

# ---- signature words ------------------------------------------------------------------

sub _insights_signature
{
    my $self = shift;
    my $st = $self->{stats};
    my $sig = $st->{signature} || {};
    my @nicks = grep { $sig->{$_} and !$self->_ins_isbot($_) } @{ $self->_ins_humans };
    return unless @nicks;
    splice(@nicks, 15) if @nicks > 15;

    $self->_headline($self->_template_text('signaturetopic'), 'signature', undef, 'signaturetopic');
    _html('<p class="intro">' . $self->_template_text('sig_intro') . '</p>');
    _html('<table border="0" width="' . $self->{cfg}->{tablewidth} . '"><tr><td>&nbsp;</td>'
        . '<td class="tdtop"><b>' . $self->_template_text('nick') . '</b></td>'
        . '<td class="tdtop"><b>' . $self->_template_text('sig_word') . '</b></td>'
        . '<td class="tdtop"><b>' . $self->_template_text('sig_uses') . '</b></td>'
        . '<td class="tdtop"><b>' . $self->_template_text('sig_share') . '</b></td></tr>');
    my $i = 0;
    for my $n (@nicks) {
        my ($word, $uses, $share) = @{ $sig->{$n} };
        $i++;
        _html('<tr><td class="' . ($i == 1 ? 'hirankc' : 'rankc') . '" align="left">' . $i . '</td>'
            . '<td class="hicell"><b>' . $self->_ins_esc($n) . '</b></td>'
            . '<td class="hicell sigword">' . $self->_ins_esc($word) . '</td>'
            . '<td class="hicell">' . $self->_ins_num($uses) . '</td>'
            . '<td class="hicell"><div class="bar"><span style="width:' . $share . '%"></span></div> ' . $share . '%</td></tr>');
    }
    _html('</table>');
}

# ---- scripts, written once near the end of the page --------------------------------------

sub _insights_scripts
{
    my $self = shift;
    return unless $self->_nav_wanted or $self->{ins_script_relmap};
    if ($self->{ins_script_relmap}) {
        my $js = $self->_ins_slurp('relmap.js');
        _html("<script>\n$js\n</script>") if length $js;
    }
    if ($self->_nav_wanted) {
        my $js = $self->_ins_slurp('pagenav.js');
        _html("<script>\n$js\n</script>") if length $js;
    }
}

1;
