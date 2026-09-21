#!/usr/bin/env python3
"""Merge nicks that belong to the same person, from what the logs already say.

On networks with account services (Undernet: X), an authenticated user's host is fixed by the
service, for example  chatte.users.undernet.org . Nicks that were seen with the same such host
are the same person: nobody can borrow another account's host. This script reads the join, part
and quit lines of your logs, groups nicks by that host, and writes a pisg config file with one
<user nick="..." alias="..."> line per group.

    pisg-autoalias.py --logdir ~/eggdrop/logs --prefix example.log. \\
        --manual ~/pisg/pisg.cfg --manual ~/pisg/users.cfg --out ~/pisg/aliases.auto.cfg

Then, in pisg.cfg (a config can include other files, but an included file cannot include another):

    <include="/home/you/pisg/aliases.auto.cfg">

It is safe to run before every pisg run: the output is rewritten each time.

Rules
  * Only hosts matching --hosts (default *.users.undernet.org) count. Shared IPs, gateways and
    bouncers are never merged automatically: they prove nothing about who is behind them.
  * Anything you define by hand wins. A group that touches one <user nick=...> of yours is added
    to that entry (its nick becomes the name); a group that touches two of your entries is
    skipped and reported, because you said they are different people.
  * The name of a group is its busiest nick (most chat lines in the logs).
  * Groups larger than --max-group are skipped and reported (a shared account, most likely).
"""
import argparse
import fnmatch
import glob
import os
import re
import sys
import tempfile
import time
from collections import Counter, defaultdict

ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
ap.add_argument("--logdir", action="append", default=[], help="folder of logs (repeatable)")
ap.add_argument("--prefix", default="", help="only files whose name starts with this")
ap.add_argument("--logfile", action="append", default=[], help="a single log file (repeatable)")
ap.add_argument("--manual", action="append", default=[], help="pisg config files whose <user> lines are yours (repeatable)")
ap.add_argument("--out", help="file to write (default: print to stdout)")
ap.add_argument("--hosts", action="append", default=[], help="host pattern that identifies an account (default *.users.undernet.org)")
ap.add_argument("--max-group", type=int, default=30)
ap.add_argument("--report", action="store_true", help="print what was merged, and what was skipped and why")
args = ap.parse_args()
patterns = [h.lower() for h in (args.hosts or ["*.users.undernet.org"])]

PREFIX = "@+%~&"
# eggdrop format:  [12:34:56] nick (ident@host) joined #chan.   /  left #chan.   /  left irc: reason
HOSTLINE = re.compile(r"^\[[\d:]+\] [" + re.escape(PREFIX) + r"]?([^\s()]+) \(([^)@\s]*)@([^)\s]+)\) (?:joined|left)\b")
CHATLINE = re.compile(r"^\[[\d:]+\] <[" + re.escape(PREFIX) + r"]?([^>\s]+)> ")


def log_files():
    files = list(args.logfile)
    for d in args.logdir:
        d = os.path.expanduser(d)
        for f in sorted(glob.glob(os.path.join(d, args.prefix + "*"))):
            base = os.path.basename(f)
            if os.path.isfile(f) and not base.startswith(".") and not base.endswith(".tmp"):
                files.append(f)
    return files


def read_manual():
    """nick or alias (lower case) -> the manual entry's name, for every <user ...> line you wrote."""
    owner, entries = {}, set()
    for path in args.manual:
        path = os.path.expanduser(path)
        if not os.path.exists(path):
            continue
        for line in open(path, encoding="utf-8", errors="replace"):
            if line.lstrip().startswith("#") or "<user" not in line:
                continue
            m = re.search(r"\bnick=([\"'])(.+?)\1", line)
            if not m:
                continue
            name = m.group(2)
            entries.add(name.lower())
            owner.setdefault(name.lower(), name)
            a = re.search(r"\balias=([\"'])(.+?)\1", line)
            for al in (a.group(2).split() if a else []):
                if "*" not in al:
                    owner.setdefault(al.lower(), name)
    return owner, entries


def main():
    hosts = defaultdict(set)          # host -> nicks seen with it
    chat = Counter()                  # nick -> chat lines
    seen_join = Counter()             # nick -> join/part lines (tie-break)
    files = log_files()
    if not files:
        sys.exit("no log files found")
    for f in files:
        try:
            fh = open(f, encoding="utf-8", errors="replace")
        except OSError:
            continue
        with fh:
            for line in fh:
                m = CHATLINE.match(line)
                if m:
                    chat[m.group(1)] += 1
                    continue
                m = HOSTLINE.match(line)
                if m:
                    nick, host = m.group(1), m.group(3).lower()
                    if any(fnmatch.fnmatchcase(host, p) for p in patterns):
                        hosts[host].add(nick)
                        seen_join[nick] += 1

    manual_owner, manual_entries = read_manual()
    written, skipped = [], []
    for host in sorted(hosts):
        nicks = hosts[host]
        if len(nicks) < 2:
            continue
        acct = host.split(".")[0]
        if len(nicks) > args.max_group:
            skipped.append((acct, sorted(nicks), f"{len(nicks)} nicks, more than --max-group ({args.max_group})"))
            continue
        # which of your own entries does this group touch?
        touched = {manual_owner[n.lower()] for n in nicks if n.lower() in manual_owner}
        if len(touched) > 1:
            skipped.append((acct, sorted(nicks), "touches " + " and ".join(sorted(touched)) + ", which you defined as different people"))
            continue
        if touched:
            name = next(iter(touched))
        else:
            name = max(nicks, key=lambda n: (chat[n], seen_join[n], n.lower() == n, n))
        aliases = sorted((n for n in nicks if n.lower() != name.lower() and manual_owner.get(n.lower()) in (None, name)),
                         key=str.lower)
        if not aliases:
            continue
        written.append((acct, name, aliases, bool(touched)))

    lines = [
        "# Generated by scripts/pisg-autoalias.py on " + time.strftime("%Y-%m-%d %H:%M:%S UTC", time.gmtime()) + ".",
        "# Do not edit: this file is rewritten on every run. To change a result, define the nick yourself",
        "# in pisg.cfg or users.cfg; a <user> line of yours always wins.",
        f"# Nicks seen with the same authenticated host ({', '.join(patterns)}) are one person.",
        "",
    ]
    for acct, name, aliases, joined in written:
        lines.append(f'<user nick="{name}" alias="{" ".join(aliases)}">')
    text = "\n".join(lines) + "\n"

    if args.out:
        out = os.path.expanduser(args.out)
        d = os.path.dirname(os.path.abspath(out))
        fd, tmp = tempfile.mkstemp(dir=d, prefix=".autoalias.")
        with os.fdopen(fd, "w", encoding="utf-8") as fh:
            fh.write(text)
        os.chmod(tmp, 0o644)
        os.replace(tmp, out)              # atomic: pisg never sees a half-written file
    else:
        sys.stdout.write(text)

    if args.report or not args.out:
        print(f"\n{len(files)} log files, {len(hosts)} authenticated hosts, "
              f"{len(written)} groups merged ({sum(len(a) for _, _, a, _ in written)} nicks folded in), "
              f"{len(skipped)} skipped", file=sys.stderr)
        for acct, name, aliases, joined in sorted(written, key=lambda w: -len(w[2]))[:200]:
            print(f"  {acct:<16} -> {name}{'  (your entry)' if joined else ''}: {', '.join(aliases)}", file=sys.stderr)
        for acct, nicks, why in skipped:
            print(f"  SKIPPED {acct}: {why}: {', '.join(nicks[:8])}", file=sys.stderr)


main()
