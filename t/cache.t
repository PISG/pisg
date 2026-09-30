#!/usr/bin/perl
# Regression tests for LogCacheDir: statistics must survive the deletion of old logs.
#
# Runs the real pisg script over a LogDir of daily logs, deletes logs after they were read
# once, and checks that the report (days, lines, nicks) is the same as if they were all still there.

use strict;
use warnings;
use FindBin;
use File::Temp qw(tempdir);
use Test::More;

my $pisg = "$FindBin::Bin/../pisg";
plan skip_all => 'pisg script not found' unless -f $pisg;

my $work = tempdir(CLEANUP => 1);
mkdir "$work/$_" for qw(logs cache archive out other shared);

sub write_file {
    my ($path, $text) = @_;
    open my $fh, '>', $path or die "$path: $!";
    print $fh $text;
    close $fh;
}

# One eggdrop log per day: 3 lines, morning to night, so every new file starts a new day.
sub add_log {
    my ($dir, $day, @nicks) = @_;
    my ($a, $b) = @nicks;
    write_file("$dir/chan-2026-01-$day.log",
        "[08:00] <$a> hello world today\n"
      . "[12:01] <$b> hi $a how are you\n"
      . "[22:02] <$a> fine thanks $b\n");
}

sub net_log {
    my ($net, $nick) = @_;
    write_file("$work/shared/$net-chan.log", "[08:00] <$nick> hello from $net\n[12:00] <$nick> and again\n");
}

# $opt: archive => 0 leaves LogCacheDir out, prefix => LogPrefix, cache => 0 leaves CacheDir out
sub config {
    my ($dir, $out, %opt) = @_;
    my $prefix  = defined $opt{prefix} ? $opt{prefix} : '';
    my $cache   = exists $opt{cache}   && !$opt{cache}   ? '' : qq{<set CacheDir="$work/cache">\n};
    my $archive = exists $opt{archive} && !$opt{archive} ? '' : qq{<set LogCacheDir="$work/archive">\n};
    write_file("$work/pisg.cfg", <<"CFG");
$cache$archive<set Format="eggdrop">
<set OutputFile="$work/out/$out.html">
<channel="#chan">
  LogDir="$work/$dir/"
  LogPrefix="$prefix"
</channel>
CFG
}

# Returns (days, lines, nicks) from the generated page.
sub report {
    my ($out) = @_;
    system($^X, "-I$FindBin::Bin/../modules", $pisg, '-co', "$work/pisg.cfg", '--silent') == 0
        or die "pisg failed: $?";
    open my $fh, '<', "$work/out/$out.html" or die "$out.html: $!";
    my $html = do { local $/; <$fh> };
    my ($days)  = $html =~ /During this (\d+)-day/;
    my ($nicks) = $html =~ /a total of\s*(?:<[^>]+>)?\s*(\d+)/;
    my ($lines) = $html =~ /id="totallines">[^\d<]*(\d+)/;
    return ($days, $lines, $nicks);
}

add_log("$work/logs", $_, 'alice', 'bob') for qw(01 02 03);
config('logs', 'chan');
is_deeply([report('chan')], [3, 9, 2], 'three logs: 3 days, 9 lines, 2 nicks');

unlink "$work/logs/chan-2026-01-01.log";
is_deeply([report('chan')], [3, 9, 2], 'the oldest log is deleted: nothing changes');

add_log("$work/logs", '04', 'alice', 'carol');
is_deeply([report('chan')], [4, 12, 3], 'a new log is added: days, lines and nicks keep growing');

unlink "$work/logs/chan-2026-01-02.log", "$work/logs/chan-2026-01-03.log";
is_deeply([report('chan')], [4, 12, 3], 'more logs are deleted: still the same');

unlink "$work/logs/chan-2026-01-04.log";
is_deeply([report('chan')], [4, 12, 3], 'every log is deleted: the archive alone is enough');

# CacheDir is only a speed-up: it may be deleted at any time without losing the history.
unlink glob("$work/cache/*");
is_deeply([report('chan')], [4, 12, 3], 'CacheDir is wiped: the history is in LogCacheDir');

# A log that is still being written keeps being archived as it grows.
add_log("$work/logs", '05', 'alice', 'bob');
is_deeply([report('chan')], [5, 15, 3], 'a fifth log is read');
open my $fh, '>>', "$work/logs/chan-2026-01-05.log" or die $!;
print $fh "[23:00] <dave> late one\n";
close $fh;
is_deeply([report('chan')], [5, 16, 4], 'the log grows: the new line and nick are counted');
unlink "$work/logs/chan-2026-01-05.log";
is_deeply([report('chan')], [5, 16, 4], 'then it is deleted: the grown version is what was kept');

# Another channel with its own log directory shares the directories: it must not see these logs.
write_file("$work/other/x.log", "[08:00] <zed> some other channel line\n");
config('other', 'other');
is((report('other'))[2], 1, 'a channel in another directory does not inherit deleted logs');

# Deleting the two archive files of a log is how to forget it.
config('logs', 'chan');
unlink glob("$work/archive/*chan-2026-01-05_log.*");
is_deeply([report('chan')], [4, 12, 3], 'removing the archive of a log removes its statistics');

# Without LogCacheDir nothing changes: CacheDir alone does not keep deleted logs, so with every
# log deleted pisg finds nothing to read and writes no page.
config('logs', 'nolog', archive => 0);
system($^X, "-I$FindBin::Bin/../modules", $pisg, '-co', "$work/pisg.cfg", '--silent');
ok(!-e "$work/out/nolog.html", 'no LogCacheDir: deleted logs are not counted, as before');

# Two networks whose logs live in ONE directory (WeeChat does this) are told apart by LogPrefix.
net_log('libera', 'lena');
net_log('oftc', 'omar');
config('shared', 'libera', prefix => 'libera-');
is((report('libera'))[2], 1, 'network one: its own nick only');
config('shared', 'oftc', prefix => 'oftc-');
is((report('oftc'))[2], 1, 'network two: its own nick only');
unlink "$work/shared/libera-chan.log", "$work/shared/oftc-chan.log";
config('shared', 'libera', prefix => 'libera-');
is_deeply([(report('libera'))[1,2]], [2, 1], 'network one after both logs are deleted: still only its own');
config('shared', 'oftc', prefix => 'oftc-');
is_deeply([(report('oftc'))[1,2]], [2, 1], 'network two after both logs are deleted: still only its own');

done_testing;
