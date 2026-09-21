#!/usr/bin/perl
# setup.pl - guided setup for pisg. Run it with:   perl setup.pl
#
# It looks for IRC logs that already exist on this computer (eggdrop, ZNC, irssi, WeeChat, HexChat,
# mIRC / AdiIRC), asks a few questions, writes pisg.cfg, makes the first stats page, and helps you
# run it on a schedule and put it on the web for free. Nothing is changed without asking, and an
# existing pisg.cfg is never overwritten (it is backed up first, if you choose to replace it).
#
#   perl setup.pl --dry-run     show what would be written, change nothing
#   perl setup.pl --help
use strict;
use warnings;
use File::Basename qw(dirname basename);
use File::Spec;
use File::Path qw(make_path);
use Cwd qw(abs_path);
use POSIX qw(strftime);

my $WIN      = $^O eq 'MSWin32';
my $HOME     = $ENV{HOME} || $ENV{USERPROFILE} || '.';
my $APPDATA  = $ENV{APPDATA} || '';
my $HERE     = dirname(abs_path($0));
my $DRY      = grep { $_ eq '--dry-run' } @ARGV;
if (grep { $_ eq '--help' || $_ eq '-h' } @ARGV) { print "Usage: perl setup.pl [--dry-run]\n"; exit 0; }

$| = 1;
sub say_ { print @_, "\n" }
sub rule { say_ "\n" . ('-' x 72) }
sub ask {
    my ($q, $def) = @_;
    print $q . (defined $def && length $def ? " [$def]" : '') . ' ';
    my $a = <STDIN>;
    exit 0 unless defined $a;                       # end of input: stop quietly
    $a =~ s/^\s+|\s+$//g;
    return length $a ? $a : (defined $def ? $def : '');
}
sub yes {
    my ($q, $def) = @_;
    my $a = lc ask("$q (y/n)", $def ? 'y' : 'n');
    return $a =~ /^y/;
}
sub slash { my $p = shift; $p =~ s{\\}{/}g; return $p }          # pisg.cfg accepts / everywhere, Windows too
sub clean { my $v = shift; $v =~ s/["\r\n]//g; return $v }        # a value goes between quotes in pisg.cfg
sub count_files { my ($dir, $prefix) = @_; my @f = grep { -f } glob(quotemeta_glob("$dir/$prefix") . '*'); return scalar @f }
sub quotemeta_glob { my $s = shift; $s =~ s/([\[\]{}*?\\ ])/\\$1/g; return $s }

# ---- what formats does this pisg know? --------------------------------------------------------
my @FORMATS = sort map { basename($_, '.pm') } glob("$HERE/modules/Pisg/Parser/Format/*.pm");
@FORMATS = grep { $_ ne 'Template' } @FORMATS;

# ---- looking for logs ---------------------------------------------------------------------------
# Each candidate: { app, channel, network, format, dir | file, prefix, note }
my @found;
sub add { push @found, { @_ } }

sub detect_eggdrop {
    my %seen;
    my @confs = grep { -f } (glob("$HOME/eggdrop*/eggdrop.conf"), glob("$HOME/*/eggdrop.conf"), glob("$HOME/*/*/eggdrop.conf"));
    for my $conf (grep { !$seen{$_}++ } @confs) {
        my $base = dirname($conf);
        open(my $fh, '<', $conf) or next;
        my @lines = <$fh>; close $fh;
        my $keep = (grep { /^\s*set\s+keep-all-logs\s+1/ } @lines) ? 1 : 0;
        for (@lines) {
            next unless /^\s*logfile\s+\S+\s+(\S+)\s+"?([^"\s]+)"?/;
            my ($chan, $path) = ($1, $2);
            next unless $chan =~ /^[#&]/;
            $path = File::Spec->catfile($base, $path) unless File::Spec->file_name_is_absolute($path);
            add(app => 'eggdrop', channel => $chan, network => '', format => 'eggdrop',
                dir => dirname($path), prefix => basename($path) . '.',
                note => $keep ? '' : "eggdrop keeps only the current log. For a long history add these to eggdrop.conf and .rehash:\n"
                                   . "      set keep-all-logs 1\n      set logfile-suffix \".%Y%m%d\"\n      set switch-logfiles-at 300");
        }
    }
}

sub detect_znc {
    my %roots = map { $_ => 1 } grep { -d } ($ENV{ZNC_DATADIR} || '', "$HOME/.znc", ($APPDATA ? "$APPDATA/znc" : ()));
    for my $root (keys %roots) {
        # user scope:  users/<user>/moddata/log/<network>/<#channel>/YYYY-MM-DD.log
        for my $d (glob("$root/users/*/moddata/log/*/*")) {
            next unless -d $d && basename($d) =~ /^[#&]/;
            add(app => 'ZNC', channel => basename($d), network => basename(dirname($d)), format => 'energymech', dir => $d, prefix => '', note => '');
        }
        # network scope:  users/<user>/networks/<network>/moddata/log/<#channel>/...
        for my $d (glob("$root/users/*/networks/*/moddata/log/*")) {
            next unless -d $d && basename($d) =~ /^[#&]/;
            (my $net = $d) =~ s{.*/networks/([^/]+)/moddata/log/.*}{$1};
            add(app => 'ZNC', channel => basename($d), network => $net, format => 'energymech', dir => $d, prefix => '', note => '');
        }
        # global scope:  moddata/log/<user>/<network>/<#channel>/...
        for my $d (glob("$root/moddata/log/*/*/*")) {
            next unless -d $d && basename($d) =~ /^[#&]/;
            add(app => 'ZNC', channel => basename($d), network => basename(dirname($d)), format => 'energymech', dir => $d, prefix => '', note => '');
        }
    }
}

# One log file per channel (irssi, WeeChat, HexChat, mIRC ...): the name holds the channel.
sub file_candidates {
    my ($app, $format, $dir, $rx, $network) = @_;
    return unless -d $dir;
    opendir(my $dh, $dir) or return;
    for my $f (sort grep { !/^\./ && -f "$dir/$_" } readdir $dh) {
        my $chan = $f =~ $rx ? $1 : next;
        add(app => $app, channel => $chan, network => ($network // ''), format => $format, file => "$dir/$f", note => '');
    }
    closedir $dh;
}

sub detect_clients {
    # irssi: ~/irclogs/<network>/<#channel>.log (autolog default)
    for my $n (grep { -d } glob("$HOME/irclogs/*")) {
        file_candidates('irssi', 'irssi', $n, qr/^([#&][^.]*)\.log$/, basename($n));
    }
    # WeeChat: irc.<server>.<#channel>.weechatlog
    for my $d ("$HOME/.local/share/weechat/logs", "$HOME/.weechat/logs") {
        file_candidates('WeeChat', 'weechat3', $d, qr/^irc\.[^.]+\.([#&].+)\.weechatlog$/);
    }
    # HexChat / XChat: logs/<NETWORK>/<#channel>.log
    for my $r ("$HOME/.config/hexchat/logs", "$HOME/.xchat2/xchatlogs", ($APPDATA ? "$APPDATA/HexChat/logs" : ())) {
        for my $n (grep { -d } glob("$r/*")) { file_candidates('HexChat', 'xchat', $n, qr/^([#&].+)\.log$/, basename($n)) }
    }
    # mIRC / AdiIRC on Windows: <#channel>.<network>.log or <#channel>.log
    for my $d (($APPDATA ? ("$APPDATA/mIRC/logs", "$APPDATA/AdiIRC/Logs") : ()), "$HOME/.wine/drive_c/mIRC/logs") {
        file_candidates('mIRC/AdiIRC', 'mIRC', $d, qr/^([#&][^.]+)(?:\..+)?\.log$/);
        for my $n (grep { -d } glob("$d/*")) { file_candidates('mIRC/AdiIRC', 'mIRC', $n, qr/^([#&][^.]+)(?:\..+)?\.log$/, basename($n)) }
    }
}

# ---- go -----------------------------------------------------------------------------------------
rule();
say_ "pisg setup" . ($DRY ? "  (dry run: nothing will be written)" : '');
say_ "";
say_ "pisg turns IRC chat logs into a web page of statistics: who talks most, when the channel is";
say_ "busy, who talks to whom. I will look for logs on this computer, ask a few questions and write";
say_ "the configuration for you. You can stop at any time with Ctrl+C; nothing is changed until the";
say_ "end.";

detect_eggdrop(); detect_znc(); detect_clients();

my @chosen;
rule();
say_ "Step 1 of 4: which channels do you want statistics for?";
say_ "";
if (@found) {
    say_ "I found these logs:";
    my $i = 0;
    for my $c (@found) {
        $i++;
        my $where = $c->{dir} ? $c->{dir} : $c->{file};
        my $n = $c->{dir} ? count_files($c->{dir}, $c->{prefix} // '') . " files" : (-s $c->{file} ? int((-s $c->{file}) / 1024) . " KB" : 'empty');
        printf "  %2d) %-14s %-16s %-10s %s (%s)\n", $i, $c->{app}, $c->{channel}, $c->{network}, $where, $n;
    }
    say_ "";
    my $pick = ask("Type the numbers you want, separated by commas (for example 1,3), or 0 to type a folder yourself:", '1');
    for my $n (grep { /^\d+$/ && $_ >= 1 && $_ <= @found } split /\s*,\s*/, $pick) { push @chosen, { %{ $found[$n - 1] } } }
} else {
    say_ "I did not find any IRC logs in the usual places.";
    say_ "";
    say_ "  * Using a bouncer or a bot? Turn logging on first: eggdrop needs a 'logfile' line, ZNC needs the";
    say_ "    'log' module (/msg *status LoadMod log), irssi needs /set autolog on. Then run this again.";
    say_ "  * Already have logs somewhere else? Type the folder below.";
}
if (!@chosen) {
    say_ "";
    my $where = ask("Folder or file with your logs (leave empty to stop):", '');
    if (!length $where) { say_ "Nothing to do. Run this again once you have logs."; exit 0; }
    $where =~ s/^~(?=\/|$)/$HOME/;
    if (!-e $where) { say_ "That does not exist: $where"; exit 1; }
    say_ "";
    say_ "Which program wrote them? Formats pisg understands:";
    say_ "  " . join(', ', @FORMATS);
    my $fmt = ask("Format:", 'eggdrop');
    my $chan = ask("Channel name (for example #mychannel):", '#mychannel');
    push @chosen, { app => 'your logs', channel => $chan, network => '', format => $fmt,
                    (-d $where ? (dir => $where, prefix => ask("Only files whose name starts with (empty: all of them):", '')) : (file => $where)), note => '' };
}

rule();
say_ "Step 2 of 4: a few details";
say_ "";
my $maintainer = clean(ask("Your name or nick, shown as the maintainer of the page:", $ENV{USER} || $ENV{USERNAME} || 'me'));
my $network    = clean(ask("Name of the IRC network (for example Undernet, Libera):", $chosen[0]{network} || 'IRC'));
say_ "";
say_ "Look of the pages:  modern (light and dark, follows your system)  midnight  amoled  terminal  default";
my $scheme = clean(ask("Colour scheme:", 'modern'));
my $outdir = ask("Folder for the finished pages:", File::Spec->catdir($HERE, 'output'));
$outdir =~ s/^~(?=\/|$)/$HOME/;
my $landing = @chosen > 1 || yes("Add a front page (index.html) that links to your channel pages?", 1);

my $cfg = File::Spec->catfile($HERE, 'pisg.cfg');
my @out;
push @out, "# Written by setup.pl on " . strftime('%Y-%m-%d %H:%M', localtime) . ". Every option is explained in pisg.cfg.example.";
push @out, qq(<set maintainer="$maintainer">), qq(<set ColorScheme="$scheme">), qq(<set Charset="utf-8">);
push @out, qq(<set HomeLink="index.html">) if $landing;
push @out, '';
my %usedfile;
for my $c (@chosen) {
    my $slug = lc(clean($c->{channel})); $slug =~ s/^[#&]+//; $slug =~ s/[^a-z0-9._-]+/-/g; $slug ||= 'channel';
    $slug .= '-' . (++$usedfile{$slug}) if $usedfile{$slug}++;
    push @out, '<channel="' . clean($c->{channel}) . '">';
    if ($c->{dir}) {
        push @out, '  LogDir="' . clean(slash($c->{dir})) . '"';
        push @out, '  LogPrefix="' . clean($c->{prefix}) . '"' if length($c->{prefix} // '');
    } else {
        push @out, '  Logfile="' . clean(slash($c->{file})) . '"';
    }
    push @out, '  Format="' . clean($c->{format}) . '"';
    push @out, '  Network="' . ($c->{network} && $network eq 'IRC' ? clean($c->{network}) : $network) . '"';
    push @out, '  OutputFile="' . clean(slash(File::Spec->catfile($outdir, "$slug.html"))) . '"';
    push @out, '</channel>', '';
}
my $text = join("\n", @out) . "\n";

rule();
say_ "Step 3 of 4: this is the configuration I will write";
say_ "";
say_ "  $cfg";
say_ "";
say_ join("\n", map { "    $_" } @out);
for my $c (@chosen) { say_ "  Note for $c->{channel}: $c->{note}\n" if $c->{note} }
if ($DRY) { say_ "Dry run: nothing written."; exit 0; }
exit 0 unless yes("Write it?", 1);

if (-e $cfg) {
    say_ "";
    say_ "There is already a pisg.cfg here.";
    if (yes("Back it up (pisg.cfg.bak-DATE) and replace it? If not, the new one is saved as pisg.cfg.new", 0)) {
        my $bak = "$cfg.bak-" . strftime('%Y%m%d-%H%M%S', localtime);
        rename($cfg, $bak) or do { say_ "Could not back it up: $!"; exit 1 };
        say_ "  old file kept as $bak";
    } else {
        $cfg .= '.new';
    }
}
make_path($outdir) unless -d $outdir;
open(my $out, '>', $cfg) or do { say_ "Could not write $cfg: $!"; exit 1 };
print $out $text; close $out;
say_ "Wrote $cfg";
say_ "  To use it instead of your current configuration:  mv pisg.cfg.new pisg.cfg" if $cfg =~ /\.new$/;
if ($landing) {
    my ($src, $dst) = ("$HERE/site/index.html", File::Spec->catfile($outdir, 'index.html'));
    if (-f $src && !-e $dst) { require File::Copy; File::Copy::copy($src, $dst) and say_ "Copied the front page to $dst" }
}

# first run
say_ "";
if (yes("Make the first statistics now?", 1)) {
    say_ "Running pisg (this can take a little while with a lot of logs) ...";
    my $perl = $^X;
    my $rc = system($perl, File::Spec->catfile($HERE, 'pisg'), ($cfg =~ /\.new$/ ? ('-co', $cfg) : ()));
    if ($rc == 0) {
        say_ "";
        say_ "Done. Your page is in: $outdir";
        say_ "  " . slash(File::Spec->catfile($outdir, 'index.html')) if $landing;
    } else {
        say_ "";
        say_ "pisg reported a problem (above). Common causes: the wrong format for these logs, or logs with";
        say_ "no timestamps. Run  perl setup.pl  again and pick another format, or ask on GitHub: https://github.com/PISG/pisg";
    }
}

# scheduling
rule();
say_ "Step 4 of 4: keep the statistics up to date";
say_ "";
say_ "pisg makes a fresh page each time it runs. Run it on a schedule so the page stays current.";
my $hours = ask("How often, in hours (1, 3, 6 or 12)?", '3');
$hours = 3 unless $hours =~ /^(1|2|3|4|6|8|12|24)$/;
if ($WIN) {
    my $cmd = qq(schtasks /Create /SC HOURLY /MO $hours /TN "pisg" /TR "cmd /c cd /d \\"$HERE\\" && \\"$^X\\" pisg" /F);
    say_ "";
    say_ "  $cmd";
    if (yes("Create this Windows scheduled task now?", 0)) { system($cmd) }
    else { say_ "  (run the line above in a command prompt when you want it.)" }
    say_ "  The computer must be on for it to run.";
} else {
    my $line = "5 */$hours * * * cd '$HERE' && '$^X' pisg >> pisg_cron.log 2>&1";
    say_ "";
    say_ "  $line";
    if (yes("Add this line to your crontab now?", 0)) {
        my $old = `crontab -l 2>/dev/null` // '';
        if ($old =~ /pisg_cron\.log/) { say_ "  There is already a pisg line in your crontab; not adding another." }
        elsif (open(my $c, '|-', 'crontab', '-')) {
            print $c $old, (length $old && $old !~ /\n\z/ ? "\n" : ''), "$line\n";
            close $c;
            say_ "  Added.";
        } else { say_ "  Could not run crontab: $!" }
    } else { say_ "  (add it yourself with:  crontab -e )" }
}

rule();
say_ "Put the pages on the web (free)";
say_ "";
say_ "Your pages are plain files, so any static host works. Good free choices:";
say_ "";
say_ "  * GitHub Pages     free, simple, and it can publish straight from a git repository.";
say_ "                     1) create a free account at github.com and a repository named  YOURNAME.github.io";
say_ "                     2) put the contents of your output folder in it and push";
say_ "                     3) your stats are then at  https://YOURNAME.github.io/";
say_ "  * Cloudflare Pages free, fast everywhere; upload the folder by drag and drop or connect a repository.";
say_ "  * Netlify          free plan; drag the output folder onto app.netlify.com/drop.";
say_ "  * GitLab Pages     free, like GitHub Pages (uses a .gitlab-ci.yml file).";
say_ "  * Your own server  point Apache or nginx at the output folder.";
say_ "";
say_ "Two things to know:";
say_ "  * The front page reads channels.json, so it needs a web server. Opening index.html straight from";
say_ "    your disk will not list the channels. To try it on your own computer, run this inside the output";
say_ "    folder, then open http://localhost:8000/ :   python3 -m http.server 8000";
say_ "  * The pages show nicknames and a random line from the chat. Tell your channel that stats are";
say_ "    published, and use BadUrls, <user ... ignore=\"y\"> or a private host if that matters to you.";
say_ "";
say_ "More: pisg.cfg.example lists every option, docs/pisg-doc.html is the whole manual.";
say_ "Change your answers any time by editing pisg.cfg, or run  perl setup.pl  again.";
