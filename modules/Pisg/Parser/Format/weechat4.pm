package Pisg::Parser::Format::weechat4;

# Documentation for the Pisg::Parser::Format modules is found in Template.pm
#
# Parser for WeeChat logs since WeeChat 4.8.0 (it also reads the older format).
#
# WeeChat 4.8.0 (2025-11-30) changed the default of logger.file.time_format from
# "%Y-%m-%d %H:%M:%S" to "%@%F %T.%fZ": the time in UTC, with fractional seconds and a
# trailing "Z". weechat3.pm expects a tab right after the seconds, so it no longer matches
# a single line of such a log. Example of what WeeChat writes now:
#
#   2026-08-17 12:34:56.123456Z	nick	hello there
#   2026-08-17 12:34:56.123456Z	 *	nick waves
#   2026-08-17 12:34:56.123456Z	-->	nick (user@host) has joined #channel
#   2026-08-17 12:34:56.123456Z	<--	nick (user@host) has quit (Ping timeout)
#
# The message bodies (joins, quits, kicks, nick changes, topics, modes) did not change, so
# this is weechat3.pm with a timestamp pattern that accepts the optional ".ffffff" and "Z"
# (logs from WeeChat before 4.8.0 still parse), plus a few fixes that apply to weechat3 as well:
#
#   * a nick of one letter (Q, X, z ...) is a nick;
#   * the mode prefix that WeeChat writes in front of the nick in /me lines ("@nick waves")
#     is not part of the nick;
#   * a topic that contains quotes is kept whole.
#
# Only the default prefixes are understood ("-->", "<--", "--", " *"). If you changed
# weechat.look.prefix_action & co., or logger.file.time_format to something else, the
# lines will not match.

use strict;
$^W = 1;

sub new
{
    my ($type, %args) = @_;
    my $self = {
        cfg => $args{cfg},
        # A nick may be a single letter (Q, X, z), so "\S*" and not "\S+" after its first
        # character; the first character can be neither a space, a tab (empty prefix, e.g. a
        # day-change line), "<" nor "-" (the "<--", "-->" and "--" prefixes).
        normalline => '^\d+-\d+-\d+ (\d+):\d+:\d+(?:\.\d+)?Z?\t[@%+~&]?([^ \t<-]\S*)\t(.*)',
        # /me lines carry the mode prefix too ("@nick waves"): it is not part of the nick.
        actionline => '^\d+-\d+-\d+ (\d+):\d+:\d+(?:\.\d+)?Z?\t \*\t[@%+~&]?(\S+) (.*)',
        thirdline  => '^\d+-\d+-\d+ (\d+):(\d+):\d+(?:\.\d+)?Z?\t(?:--|<--|-->)\t(\S+) (\S+) (\S+) (\S+) (\S+)(.*)',
    };

    bless($self, $type);
    return $self;
}

sub normalline
{
    my ($self, $line, $lines) = @_;
    my %hash;

    if ($line =~ /$self->{normalline}/o) {

        $hash{hour}   = $1;
        $hash{nick}   = $2;
        $hash{saying} = $3;

        return \%hash;
    } else {
        return;
    }
}

sub actionline
{
    my ($self, $line, $lines) = @_;
    my %hash;

    if ($line =~ /$self->{actionline}/o) {

        $hash{hour}   = $1;
        $hash{nick}   = $2;
        $hash{saying} = $3;

        return \%hash;
    } else {
        return;
    }
}

sub thirdline
{
    my ($self, $line, $lines) = @_;
    my %hash;

    if ($line =~ /$self->{thirdline}/o) {

        $hash{hour} = $1;
        $hash{min}  = $2;
        $hash{nick} = $3;

        if (($4.$5) eq 'haskicked') {
            $hash{nick} = $6;
            $hash{kicker} = $3;

        } elsif ($4.$5.$6 eq 'haschangedtopic') {
            # WeeChat writes  ... for #chan from "old" to "new"   or   ... for #chan to "new".
            # The new topic is everything between the first ' to "' and the final quote, so a
            # topic that itself contains quotes is kept whole.
            my $tail = $7 . $8;
            if ($tail =~ /(?:^|\s)to "(.*)"\s*$/) {
                $hash{newtopic} = $1;
            }

        } elsif ($3 eq 'Mode') {
            $hash{newmode} = substr($5, 1);
            $hash{nick} = $8 || $7;
            $hash{nick} =~ s/.* (\S+)$/$1/; # Get the last word of the string

        } elsif (($5.$6) eq 'hasjoined') {
            $hash{newjoin} = $3;

        } elsif (($5.$6) eq 'nowknown') {
            if ($8 =~ /^\s+(\S+)/) {
                $hash{newnick} = $1;
            }
        }

        return \%hash;

    } else {
        return;
    }
}

1;
