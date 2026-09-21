#!/usr/bin/env python3
"""Convert an AdiIRC channel log to eggdrop log format, so pisg can read it.

    adiirc2eggdrop.py mychannel.log OUTDIR --channel '#example' --nick YourNick \\
        --tz Europe/Paris --before '2026-01-31 03:00' --prefix example.log.

What it does
  * Keeps only PUBLIC channel events (messages, actions, joins, parts, quits,
    kicks, nick changes, mode and topic changes). Everything else in a client
    log - /whois output, notices, private messages to services/users, server
    text - is dropped on purpose: it is not channel history and may contain
    private data. This is a whitelist, not a blacklist.
  * Converts the client's local time to UTC (eggdrop logs are in server time),
    using --tz. Rules such as daylight saving come from the tz database.
  * Only writes events strictly before --before (UTC), so the import stops where
    eggdrop's own logging starts and nothing is counted twice.
  * Splits output into one file per eggdrop log day. Eggdrop rotates at
    03:00 (switch-logfiles-at 300), so file YYYYMMDD holds YYYYMMDD 03:00 up to
    the next day 02:59:59, matching the names eggdrop writes with
    logfile-suffix ".%Y%m%d".
  * Never overwrites: an existing output file is skipped and reported.

pisg reads these with  LogDir=... LogPrefix="example.log."  in alphabetical
order, which is chronological with the YYYYMMDD suffix.
"""
import argparse
import datetime as dt
import re
import sys
import zoneinfo
from collections import Counter
from pathlib import Path

ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
ap.add_argument("infile")
ap.add_argument("outdir")
ap.add_argument("--channel", required=True, help="channel name as eggdrop writes it, e.g. '#example'")
ap.add_argument("--nick", required=True, help="your own nick (used for 'You were kicked')")
ap.add_argument("--tz", required=True, help="timezone the client logged in, e.g. Europe/Paris or America/New_York (IANA name)")
ap.add_argument("--before", required=True, help="UTC cutoff 'YYYY-MM-DD HH:MM'; later events are skipped")
ap.add_argument("--first-date", help="local date of the first line, YYYY-MM-DD. Optional: by default it is "
                "worked out from the first 'Day changed' marker in the log")
ap.add_argument("--prefix", default="channel.log.", help="output file name prefix (default %(default)s)")
ap.add_argument("--format", choices=("eggdrop", "znc"), default="eggdrop",
                help="eggdrop (default): eggdrop log days, 03:00 rotation. znc: what ZNC's log module writes "
                     "(energymech format, one YYYY-MM-DD.log per calendar day), for pisg Format=\"energymech\"")
ap.add_argument("--znc-tz", default="UTC", help="timezone ZNC writes its time stamps in (default %(default)s); --format znc only")
ap.add_argument("--dry-run", action="store_true", help="report only, write nothing")
ap.add_argument("--show-actions", action="store_true", help="print the lines treated as /me actions")
args = ap.parse_args()

CH = args.channel
TZ = zoneinfo.ZoneInfo(args.tz)
UTC = dt.timezone.utc
CUTOFF = dt.datetime.strptime(args.before, "%Y-%m-%d %H:%M").replace(tzinfo=UTC)
JITTER = 300                                      # seconds; smaller backwards steps are clock jitter
ROTATE = dt.timedelta(hours=3)                    # eggdrop switch-logfiles-at 300
MONTHS = {m: i for i, m in enumerate("Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec".split(), 1)}
P = r"[@+%~&!.]?"                                 # channel status prefix on a nick

COLOUR = re.compile(r"\x03\d{0,2}(?:,\d{1,2})?|[\x02\x0f\x16\x1d\x1f]")
LINE = re.compile(r"^\[(\d\d):(\d\d):(\d\d)\] (.*)$")
DAY = re.compile(r"\* Day changed to \w+, (\d+)\. (\w+) (\d+)$")

# Text of "* nick ..." lines that are WHOIS/server output, not a /me action.
NOT_ACTION = re.compile(
    r"^\* \S+ (?:is \S+@\S+ \*|on <?[@+%~&]*#|using \S+ |is logged in|has been idle|End of /WHOIS"
    r"|has modes|created on|is now known as|sets mode|changes topic|was kicked)"
    r"|^\* (?:#\S+ (?:has modes|created on)|Scanning|Topic |Now talking|Rejoin|Disconnected|Attempting|Connect"
    r"|You |Joins:|Parts:|Quits:)"
    r"|^\* \S+ (?:#\S+ ){2,}"
    r"|^\* \S+ (?:invites you|has been invited|is away|is back|is an IRC|is a |End of /NAMES)"
    r"|^\* [#/]"
)

PARTICIPANTS = set()   # nicks seen speaking/joining/changing nick: only they can /me


def collect_participants(text):
    for raw_line in text.split("\n"):
        b = COLOUR.sub("", raw_line.rstrip("\r"))
        mm = LINE.match(b)
        if not mm:
            continue
        b = mm.group(4)
        for rx in (rf"<{P}([^>\s]+)> ", rf"\* Joins: {P}(\S+) ", rf"\* Parts: {P}(\S+) ", rf"\* Quits: {P}(\S+) ",
                   rf"\* {P}(\S+) is now known as {P}(\S+)$"):
            x = re.match(rx, b)
            if x:
                PARTICIPANTS.update(g for g in x.groups() if g)
                break


kept = Counter()
dropped = Counter()
events = []          # (utc datetime, eggdrop text)
actions_seen = []
order_debug = []


ZNC = args.format == "znc"


def convert(body):
    """Return (text, kind) for a whitelisted event, else (None, reason). The text is in the chosen output format."""
    m = re.match(rf"<{P}([^>\s]+)> (.*)$", body)
    if m:
        return f"<{m.group(1)}> {m.group(2)}", "message"
    m = re.match(rf"\* Joins: {P}(\S+) \((\S+)\)$", body)
    if m:
        return (f"*** Joins: {m.group(1)} ({m.group(2)})" if ZNC else f"{m.group(1)} ({m.group(2)}) joined {CH}."), "join"
    m = re.match(rf"\* Parts: {P}(\S+) \((\S+)\)(?: \((.*)\))?$", body)
    if m:
        why = f" ({m.group(3)})" if m.group(3) else ""
        return (f"*** Parts: {m.group(1)} ({m.group(2)}){why}" if ZNC else f"{m.group(1)} ({m.group(2)}) left {CH}.{why}"), "part"
    m = re.match(rf"\* Quits: {P}(\S+) \((\S+)\) \((.*)\)$", body)
    if m:
        return (f"*** Quits: {m.group(1)} ({m.group(2)}) ({m.group(3)})" if ZNC else f"{m.group(1)} ({m.group(2)}) left irc: {m.group(3)}"), "quit"
    m = re.match(rf"\* {P}(\S+) is now known as {P}(\S+)$", body)
    if m:
        return (f"*** {m.group(1)} is now known as {m.group(2)}" if ZNC else f"Nick change: {m.group(1)} -> {m.group(2)}"), "nick"
    m = re.match(rf"\* {P}(\S+) was kicked from (#\S+) by {P}(\S+) \((.*)\)$", body)
    if m:
        return (f"*** {m.group(1)} was kicked by {m.group(3)} ({m.group(4)})" if ZNC else f"{m.group(1)} kicked from {CH} by {m.group(3)}: {m.group(4)}"), "kick"
    m = re.match(rf"\* You were kicked by {P}(\S+) \((.*)\)$", body)
    if m:
        return (f"*** {args.nick} was kicked by {m.group(1)} ({m.group(2)})" if ZNC else f"{args.nick} kicked from {CH} by {m.group(1)}: {m.group(2)}"), "kick"
    m = re.match(rf"\* {P}(\S+) sets mode: (.+)$", body)
    if m:
        return (f"*** {m.group(1)} sets mode: {m.group(2)}" if ZNC else f"{CH}: mode change '{m.group(2)}' by {m.group(1)}!*@*"), "mode"
    m = re.match(rf"\* {P}(\S+) changes topic to: (.*)$", body)
    if m:
        return (f"*** {m.group(1)} changes topic to '{m.group(2)}'" if ZNC else f"Topic changed on {CH} by {m.group(1)}!*@*: {m.group(2)}"), "topic"
    m = re.match(rf"\* {P}(\S+) (.+)$", body)
    if m and not NOT_ACTION.match(body) and m.group(1) in PARTICIPANTS:
        if args.show_actions:
            actions_seen.append(body)
        return (f"* {m.group(1)} {m.group(2)}" if ZNC else f"Action: {m.group(1)} {m.group(2)}"), "action"
    return None, "other"


prev = None
raw = Path(args.infile).read_text(encoding="utf-8", errors="replace")
collect_participants(raw)


def derive_first_date(text):
    """The log only carries dates in 'Day changed' markers. Work the start date back
    from the first marker: every backwards step of the clock before it is a new
    session on a later day, so start + steps = marker date - 1."""
    steps, last = 0, None
    for raw_line in text.split("\n"):
        mm = LINE.match(COLOUR.sub("", raw_line.rstrip("\r")))
        if not mm:
            continue
        dd = DAY.match(mm.group(4))
        if dd:
            first_marker = dt.date(int(dd[3]), MONTHS[dd[2]], int(dd[1]))
            return first_marker - dt.timedelta(days=1 + steps)
        tod = dt.time(int(mm[1]), int(mm[2]), int(mm[3]))
        if last is not None and tod < last:
            steps += 1
        last = tod
    sys.exit("no 'Day changed' marker found; pass --first-date")


local_date = dt.date.fromisoformat(args.first_date) if args.first_date else derive_first_date(raw)
print(f"log starts on local date {local_date}")
prev_tod = None          # previous line's local time of day
last_line = None
rollovers = 0
marker_conflicts = 0
for ln in raw.split("\n"):
    ln = COLOUR.sub("", ln.rstrip("\r"))
    m = LINE.match(ln)
    if not m:
        if ln.strip():
            dropped["unparsed (no timestamp)"] += 1
        continue
    h, mi, s, body = int(m[1]), int(m[2]), int(m[3]), m[4]
    d = DAY.match(body)
    if d:
        new_date = dt.date(int(d[3]), MONTHS[d[2]], int(d[1]))
        if new_date < local_date:
            marker_conflicts += 1        # our inferred date had already run ahead
        local_date = new_date
        prev_tod = dt.time(0, 0, 0)
        continue
    tod = dt.time(h, mi, s)
    if prev_tod is not None and tod < prev_tod:
        back = (dt.datetime.combine(dt.date.min, prev_tod) - dt.datetime.combine(dt.date.min, tod)).total_seconds()
        if back > JITTER:
            # Clock jumped backwards with no "Day changed": a new client session on
            # a later day (the client only writes the marker when connected at midnight).
            local_date += dt.timedelta(days=1)
            rollovers += 1
            prev_tod = tod
        # else: a second or two of jitter between near-simultaneous events; same day
    else:
        prev_tod = tod
    text, kind = convert(body)
    if text is not None and kind != "message" and ln == last_line:
        dropped["duplicate state event (two windows logging)"] += 1
        continue
    last_line = ln
    if text is None:
        last_line = ln
    # (text, kind) handled below
    if text is None:
        dropped[kind] += 1
        continue
    local = dt.datetime.combine(local_date, dt.time(h, mi, s), tzinfo=TZ)
    utc = local.astimezone(UTC)
    if prev and utc < prev - dt.timedelta(seconds=JITTER):
        dropped["out-of-order (skipped)"] += 1
        if len(order_debug) < 12:
            order_debug.append(f"local {local:%Y-%m-%d %H:%M:%S} is before previous kept event {prev.astimezone(TZ):%Y-%m-%d %H:%M:%S}: {body[:60]}")
        continue
    prev = utc if prev is None else max(prev, utc)
    if utc >= CUTOFF:
        dropped["after cutoff (eggdrop has these)"] += 1
        continue
    kept[kind] += 1
    events.append((utc, text))

# Group into log days and write.
files = {}
if ZNC:
    ZTZ = zoneinfo.ZoneInfo(args.znc_tz)
    for utc, text in events:
        local_z = utc.astimezone(ZTZ)
        files.setdefault(local_z.date(), []).append((local_z, text))
else:
    # eggdrop log days run 03:00 to 02:59:59
    for utc, text in events:
        files.setdefault((utc - ROTATE).date(), []).append((utc, text))

out = Path(args.outdir)
out.mkdir(parents=True, exist_ok=True)
written = skipped = 0
for day in sorted(files):
    name = f"{day:%Y-%m-%d}.log" if ZNC else f"{args.prefix}{day:%Y%m%d}"
    lines = []
    if not ZNC:
        first_utc = files[day][0][0]
        lines.append(f"[03:00:00] --- {first_utc:%a %b %d %Y}")      # self-describing header
    cur = files[day][0][0].date()
    for utc, text in files[day]:
        if not ZNC and utc.date() != cur:
            cur = utc.date()
            lines.append(f"[00:00:00] --- {utc:%a %b %d %Y}")    # midnight, like eggdrop
        lines.append(f"[{utc:%H:%M:%S}] {text}")
    if args.dry_run:
        written += 1
        continue
    target = out / name
    if target.exists():
        print(f"SKIP existing {target}")
        skipped += 1
        continue
    with open(target, "x", encoding="utf-8", newline="\n") as fh:   # "x": refuse to overwrite
        fh.write("\n".join(lines) + "\n")
    written += 1

print(f"\nkept {sum(kept.values())} events: {dict(kept)}")
print(f"dropped: {dict(dropped)}")
if events:
    print(f"range (UTC): {events[0][0]:%Y-%m-%d %H:%M} .. {events[-1][0]:%Y-%m-%d %H:%M}; {len(files)} log days")
print(f"date rollovers inferred from a backwards clock: {rollovers}; "
      f"'Day changed' markers that disagreed with the inferred date: {marker_conflicts}")
print(f"{'would write' if args.dry_run else 'wrote'} {written} files, skipped {skipped}")
if order_debug:
    print("\nfirst out-of-order events:\n  " + "\n  ".join(order_debug))
if args.show_actions:
    print("\n--- lines treated as actions ---")
    print("\n".join(a[:120] for a in actions_seen))
