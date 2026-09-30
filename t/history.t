#!/usr/bin/perl
# Regression tests for HistoryDir: the statistics must survive the deletion of old logs, and a log
# that is read again (it grew, was compressed, renamed) must not be counted twice.
#
# Runs the real pisg script over eggdrop logs and reads days, lines and nicks off the page.

use strict;
use warnings;
use FindBin;
use File::Temp qw(tempdir);
use Fcntl qw(:flock);
use Data::Dumper;
use Test::More;

my $pisg = "$FindBin::Bin/../pisg";
plan skip_all => 'pisg script not found' unless -f $pisg;

my $work = tempdir(CLEANUP => 1);
mkdir "$work/$_" for qw(logs history out other shared);

sub write_file {
    my ($path, $text) = @_;
    open my $fh, '>', $path or die "$path: $!";
    print $fh $text;
    close $fh;
}

sub append_file {
    my ($path, $text) = @_;
    open my $fh, '>>', $path or die "$path: $!";
    print $fh $text;
    close $fh;
}

sub read_file {
    my ($path) = @_;
    open my $fh, '<', $path or die "$path: $!";
    local $/;
    return <$fh>;
}

# One eggdrop log per day, 3 lines, morning to night so that each file starts a new day. The text
# differs from day to day, as in a real log.
sub add_log {
    my ($dir, $day, @nicks) = @_;
    my ($a, $b) = @nicks ? @nicks : ('alice', 'bob');
    write_file("$dir/chan-2026-01-$day.log",
        "[08:00] <$a> hello world today (day $day)\n"
      . "[12:01] <$b> hi $a how are you\n"
      . "[22:02] <$a> fine thanks $b\n");
}

# %opt: dir, out, history (0 = no HistoryDir), network, channel, rebuild, prefix, logfile, dump
sub config {
    my (%opt) = @_;
    my $dir = defined $opt{dir} ? $opt{dir} : 'logs';
    my $out = defined $opt{out} ? $opt{out} : 'chan';
    my $hist = exists $opt{history} && !$opt{history} ? '' : qq{<set HistoryDir="$work/history">\n};
    my $rebuild = $opt{rebuild} ? qq{<set HistoryRebuild="1">\n} : '';
    my $net = defined $opt{network} ? $opt{network} : 'TestNet';
    my $chan = defined $opt{channel} ? $opt{channel} : '#chan';
    my $prefix = defined $opt{prefix} ? qq{  LogPrefix="$opt{prefix}"\n} : '';
    my $dump = defined $opt{dump} ? qq{<set StatsDump="$opt{dump}">\n} : '';
    my $where = defined $opt{logfile} ? qq{  Logfile="$opt{logfile}"} : qq{  LogDir="$work/$dir/"};
    write_file("$work/pisg.cfg", qq{$hist$rebuild$dump<set Format="eggdrop">\n<set OutputFile="$work/out/$out.html">\n}
        . qq{<channel="$chan">\n  Network="$net"\n$where\n$prefix</channel>\n});
}

# Runs pisg; returns its exit status and what it printed on stderr.
sub run_pisg {
    my $err = "$work/err.txt";
    my $rc = system("$^X -I$FindBin::Bin/../modules $pisg -co $work/pisg.cfg --silent 2>$err");
    return ($rc, read_file($err));
}

# Returns (days, lines, nicks) from the generated page.
sub report {
    my ($out) = @_;
    unlink "$work/out/$out.html";
    my ($rc, $err) = run_pisg();
    die "pisg failed: $rc $err" if $rc;
    open my $fh, '<', "$work/out/$out.html" or die "$out.html: $!";
    my $html = do { local $/; <$fh> };
    my ($days)  = $html =~ /During this (\d+)-day/;
    my ($nicks) = $html =~ /a total of\s*(?:<[^>]+>)?\s*(\d+)/;
    my ($lines) = $html =~ /id="totallines">[^\d<]*(\d+)/;
    return ($days, $lines, $nicks);
}

sub page { my ($out) = @_; return -e "$work/out/$out.html" ? read_file("$work/out/$out.html") : undef }

sub history_files { return sort map { s{.*/}{}r } glob("$work/history/*.pisghist") }

# ---- deleting old logs --------------------------------------------------------------------------
add_log("$work/logs", $_) for qw(01 02 03);
config();
is_deeply([report('chan')], [3, 9, 2], 'three logs: 3 days, 9 lines, 2 nicks');
is_deeply([history_files()], ['testnet.%23chan.pisghist'], 'the history is one file, named after network and channel');

unlink "$work/logs/chan-2026-01-01.log";
is_deeply([report('chan')], [3, 9, 2], 'the oldest log is deleted: nothing changes');

add_log("$work/logs", '04', 'alice', 'carol');
is_deeply([report('chan')], [4, 12, 3], 'a new log is added: days, lines and nicks keep growing');

unlink "$work/logs/chan-2026-01-02.log", "$work/logs/chan-2026-01-03.log";
is_deeply([report('chan')], [4, 12, 3], 'more logs are deleted: still the same');

unlink "$work/logs/chan-2026-01-04.log";
is_deeply([report('chan')], [4, 12, 3], 'every log is deleted: the history alone is enough');

my $before = -s "$work/history/testnet.%23chan.pisghist";
report('chan');
is(-s "$work/history/testnet.%23chan.pisghist", $before, 'nothing new: the history is not rewritten');

# ---- a log that grows ---------------------------------------------------------------------------
add_log("$work/logs", '05');
is_deeply([report('chan')], [5, 15, 3], 'a fifth log is read');
append_file("$work/logs/chan-2026-01-05.log", "[23:00] <dave> late one\n");
is_deeply([report('chan')], [5, 16, 4], 'the log grows: only the new line is added, and its new nick');
append_file("$work/logs/chan-2026-01-05.log", "[23:30] <dave> and another\n[23:40] <alice> good night\n");
is_deeply([report('chan')], [5, 18, 4], 'it grows again: still no line counted twice');
unlink "$work/logs/chan-2026-01-05.log";
is_deeply([report('chan')], [5, 18, 4], 'then it is deleted: the grown version is what was kept');

# ---- a log that is compressed or renamed ------------------------------------------------------------
mkdir "$work/rot";
config(dir => 'rot', out => 'rot', channel => '#rot', network => 'RotNet');
write_file("$work/rot/a.log", "[08:00] <alice> first line of a\n[09:00] <bob> second line\n[10:00] <alice> third line\n");
is_deeply([report('rot')], [1, 3, 2], 'a plain log: 3 lines');
system("gzip $work/rot/a.log");
is_deeply([report('rot')], [1, 3, 2], 'it is compressed: it is the same log, not counted again');
rename "$work/rot/a.log.gz", "$work/rot/b.log.gz";
is_deeply([report('rot')], [1, 3, 2], 'and renamed: still the same log');

write_file("$work/rot/c.log", "[08:00] <carol> a log that grows\n[09:00] <carol> second\n[10:00] <dave> third\n");
is_deeply([report('rot')], [2, 6, 4], 'a second log');
append_file("$work/rot/c.log", "[11:00] <carol> added just before compressing\n[12:00] <dave> and this\n");
system("gzip $work/rot/c.log");
is_deeply([report('rot')], [2, 8, 4], 'a log grows and is compressed before the next run: only the new lines are added');

write_file("$work/rot/b.log.gz.tmp", '');   # unrelated file that is not a log: ignored
unlink "$work/rot/b.log.gz.tmp";

# a different log under an old name is new
write_file("$work/rot/c.log", "[08:00] <erin> a new log that reuses the name\n[09:00] <erin> line two\n");
is_deeply([report('rot')], [3, 10, 5], 'a different log under an old name is a new log');

# two logs that start with the same line are not the same log
mkdir "$work/same";
config(dir => 'same', out => 'same', channel => '#same', network => 'SameNet');
write_file("$work/same/one.log", "[08:00] <bot> hourly announcement\n[09:00] <alice> only in the first\n");
is_deeply([report('same')], [1, 2, 2], 'first of two logs that start with the same line');
unlink "$work/same/one.log";
write_file("$work/same/two.log", "[08:00] <bot> hourly announcement\n[09:00] <bob> only in the second\n[10:00] <bob> and more\n");
is_deeply([report('same')], [2, 5, 3], 'the second one is a different log, not a renamed first one');

# the same name, the same first line, other content: a new log (as with a log that is rotated by
# copying and truncating, and a bot that says the same thing at the start of every one)
mkdir "$work/rotated";
config(dir => 'rotated', out => 'rotated', channel => '#rotated', network => 'RotatedNet');
write_file("$work/rotated/r.log", "[08:00] <bot> hourly announcement\n[09:00] <alice> old content here\n");
is_deeply([report('rotated')], [1, 2, 2], 'a log with a first line that is common');
write_file("$work/rotated/r.log", "[08:00] <bot> hourly announcement\n[09:00] <bob> different content and a longer line\n[10:00] <bob> yet more\n");
is_deeply([report('rotated')], [2, 5, 3], 'replaced by another log with the same first line: it is a new log');

# ---- a line that is still being written ---------------------------------------------------------
mkdir "$work/live";
config(dir => 'live', out => 'live', channel => '#live', network => 'LiveNet');
write_file("$work/live/l.log", "[08:00] <alice> first complete line here\n[09:00] <bob> and a half writ");
is_deeply([report('live')], [1, 1, 1], 'a last line without a newline is left until it is complete');
append_file("$work/live/l.log", "ten line\n[10:00] <alice> next one\n");
is_deeply([report('live')], [1, 3, 2], 'then it is counted, once');

# ---- channels and networks share the directory -----------------------------------------------------
write_file("$work/other/x.log", "[08:00] <zed> some other channel line\n");
config(dir => 'other', out => 'other', channel => '#chan', network => 'OtherNet');
is((report('other'))[2], 1, 'the same channel name on another network has its own history');
config(dir => 'other', out => 'other2', channel => '#chan2', network => 'TestNet');
is((report('other2'))[2], 1, 'another channel on the same network has its own history');
is(scalar(() = history_files()) >= 4, 1, 'one history file each');

# ---- the file is damaged -------------------------------------------------------------------------
config();
my $file = "$work/history/testnet.%23chan.pisghist";
my $good = read_file($file);
write_file($file, "this is not a history\n");
unlink "$work/out/chan.html";
my ($rc, $err) = run_pisg();
like($err, qr/damaged|Using the previous copy/, 'a damaged history is noticed');
ok(-e "$work/history/testnet.%23chan.pisghist.bak", 'the previous copy is there');
is_deeply([report('chan')], [5, 16, 4], 'and it is used: the state before the last change');

write_file($file, "still not a history\n");
unlink "$file.bak";
unlink "$work/out/chan.html";
($rc, $err) = run_pisg();
like($err, qr/Not starting a new history/, 'no readable history at all: it is not replaced by an empty one');
ok(!-e "$work/out/chan.html", 'and no page is made from nothing');
is(read_file($file), "still not a history\n", 'the damaged file is left alone');
write_file($file, $good);

# ---- two runs at once -----------------------------------------------------------------------------
open my $lock, '>>', "$file.lock" or die $!;
flock($lock, LOCK_EX | LOCK_NB) or die "test could not lock";
unlink "$work/out/chan.html";
($rc, $err) = run_pisg();
like($err, qr/in use by another pisg/, 'a history that is in use is skipped');
ok(!-e "$work/out/chan.html", 'and nothing is written');
close $lock;
is_deeply([report('chan')], [5, 18, 4], 'when it is free again it works');

# ---- start again --------------------------------------------------------------------------------
add_log("$work/logs", '09');
config(rebuild => 1);
is_deeply([report('chan')], [1, 3, 2], 'HistoryRebuild: only the logs that still exist');
my @old = glob("$work/history/testnet.%23chan.pisghist.*.old");
ok(scalar(@old) >= 1, 'the old history is kept aside');
config();
is_deeply([report('chan')], [1, 3, 2], 'and it goes on from there');

# ---- without HistoryDir nothing changes ---------------------------------------------------------------
unlink "$work/logs/chan-2026-01-09.log";
config(history => 0, out => 'nohist');
unlink "$work/out/nohist.html";
run_pisg();
ok(!-e "$work/out/nohist.html", 'without HistoryDir deleted logs are not counted (no logs, no page)');

# ---- rare words are kept over many small runs ---------------------------------------------------------
mkdir "$work/words";
config(dir => 'words', out => 'words', channel => '#words', network => 'WordNet', dump => "$work/dump.txt");
for my $run (1 .. 6) {
    my $t = sprintf('%02d', 8 + $run);
    my $c = $run == 1 ? '>' : '>>';
    open my $fh, $c, "$work/words/w.log" or die $!;
    print $fh "[$t:00] <alice> some filler text words number$run and zebrafish here\n";
    close $fh;
    report('words');
}
my ($counts) = read_file("$work/dump.txt") =~ /'wordcounts' => \{(.*?)\n  \}/s;
my ($count) = $counts =~ /'zebrafish' => (\d+)/;
is($count, 6, 'a word used once per run is counted over all the runs, not dropped every time');
ok($counts !~ /'number3'/, 'while a word seen once and never again is dropped');

# ---- the same statistics as reading everything at once ---------------------------------------------
# A history built in small steps (each log read half way, then completed, run after run) must hold
# what one run over all the logs gives, apart from the rare words that are dropped from the sum.
{
    srand(5);
    my @nicks = qw(alice bob carol dave erin frank);
    my @words = qw(hello world today nothing really matters banana keyboard coffee weather server network
                   channel morning evening kicked joined quit);
    mkdir "$work/equal";
    mkdir "$work/equal/all";
    mkdir "$work/equal/steps";
    for my $day (1 .. 8) {
        my ($h, @lines) = (6);
        for (1 .. 15 + int(rand(25))) {
            $h += (0, 0, 1)[int rand 3];
            $h = 23 if $h > 23;
            my $stamp = sprintf('[%02d:%02d]', $h, int rand 60);
            my $nick = $nicks[int rand @nicks];
            my $kind = rand;
            my @say = map { $words[int rand @words] } 1 .. 2 + int rand 7;
            if    ($kind < 0.08) { push @lines, "$stamp Action: $nick $say[0]" }
            elsif ($kind < 0.15) { push @lines, "$stamp <$nick> $nicks[int rand @nicks]: @say[0 .. 3]?" }
            elsif ($kind < 0.20) { push @lines, "$stamp <$nick> @say :-)" }
            else                 { push @lines, "$stamp <$nick> @say" }
        }
        write_file(sprintf("$work/equal/all/chan-2026-02-%02d.log", $day), join("\n", @lines) . "\n");
    }

    my $dump = sub {
        my ($file) = @_;
        my $text = read_file($file);
        our ($stats, $lines);
        eval $text;
        die $@ if $@;
        return $stats;
    };

    config(dir => 'equal/all', out => 'equal', channel => '#equal', network => 'EqualNet',
           history => 0, dump => "$work/equal-all.txt");
    run_pisg();

    for my $day (1 .. 8) {
        my $name = sprintf('chan-2026-02-%02d.log', $day);
        my @lines = split /^/, read_file("$work/equal/all/$name");
        write_file("$work/equal/steps/$name", join('', @lines[0 .. int(@lines / 2) - 1]));
        config(dir => 'equal/steps', out => 'equal', channel => '#equal', network => 'EqualNet',
               dump => "$work/equal-steps.txt");
        run_pisg();
        write_file("$work/equal/steps/$name", join('', @lines));
        run_pisg();
    }

    local $Data::Dumper::Sortkeys = 1;
    my ($all, $steps) = ($dump->("$work/equal-all.txt"), $dump->("$work/equal-steps.txt"));
    my %skip = map { $_ => 1 } qw(processtime wordcounts wordnicks word_upcase words wordlines chartcounts);
    my @different = grep { !$skip{$_} and Dumper($all->{$_}) ne Dumper($steps->{$_}) } sort keys %$all;
    is_deeply(\@different, [], 'built in small steps, the history holds what one run over all the logs gives');
    is($steps->{parsedlines}, $all->{parsedlines}, '... the same number of lines');
    is($steps->{days}, $all->{days}, '... and of days');
}

done_testing;
