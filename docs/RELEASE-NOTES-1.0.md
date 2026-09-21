# pisg 1.0: what changed since 0.80-preview2

pisg 1.0 keeps everything 0.80-preview2 does: the same parsers, the same statistics, the same
`pisg.cfg`. On top of that it has a new look, a set of new sections, a way to run several channels
from one folder, safer output, a guided setup, and tools to keep the statistics tidy without editing files
by hand.

Nothing you have set up has to change. The default colour scheme is still `default`, and every old theme
looks as it did. Everything new is opt-in through a colour scheme or an option, except the extra
sections, which are on by default (see [Upgrading](#upgrading)).

## Highlights

- **A guided setup**: `perl setup.pl` finds your logs, writes the configuration, makes the first page and
  explains how to run it on a schedule and host it for free. Made for people new to IRC tools.
- **Five modern themes**, light and dark, that follow the reader's system setting: `modern`, `midnight`,
  `amoled`, `terminal` and `canada`.
- **Seven new sections**: an overview, an interactive *who talks to whom* map, closest pairs, social roles,
  time personalities, *who carries the channel* and signature words.
- **Section navigation**: a menu down the left side on wide screens, a slim bar on phones.
- **A landing page** with the statistics of your statistics: totals, a comparison of every channel, and a
  button to open each one.
- **Several channels, one run**: a channel that cannot be read no longer stops the others.
- **Profiles people manage themselves** from IRC (`!pisginfo`, `!pisgmerge` ...) and **automatic nick
  merging** for networks with account services.
- **Safer**: a page is replaced only when it is complete, and pisg exits with an error status when it fails.

## Guided setup

`perl setup.pl` is the easy way in. It needs nothing but Perl, so it works on Linux, macOS and Windows.

1. **Finds your logs.** It looks for eggdrop (reads `eggdrop.conf` for the log files), ZNC (all three
   log-module layouts), irssi, WeeChat, HexChat/XChat and mIRC/AdiIRC, and shows what it found. If it finds
   nothing it says how to turn logging on, or lets you point it at a folder and pick the log format.
2. **Asks a few questions** (channels, your name, network name, colour scheme, output folder) and shows the
   configuration before it writes anything.
3. **Writes `pisg.cfg`**, never overwriting an existing one (it backs it up first, or saves the new one as
   `pisg.cfg.new`), copies the landing page, and makes the first statistics.
4. **Schedules it**: prints the cron line (and adds it if you say yes) on Linux and macOS, or the
   `schtasks` command on Windows.
5. **Explains free hosting**: GitHub Pages, Cloudflare Pages, Netlify, GitLab Pages or your own server,
   with a reminder that the pages need a web server for the landing page to list the channels, and that they
   show nicknames and a random line from the chat.

`perl setup.pl --dry-run` shows what would be written without changing anything.

## New look

- Five new colour schemes, all generated from one stylesheet (`layout/build-themes.py`), so they stay
  consistent. Use one with `<set ColorScheme="modern">`. The old themes are unchanged.
- Design: ink on paper with colour kept for data. Sections are separated by a thin rule instead of boxes,
  nicks and figures are set in a monospace face, bars stand on one baseline, and the peak of a chart is the
  only value labelled.
- Four time-of-day colours (night, morning, afternoon, evening) used the same way in every chart. They
  were checked for colour-blind safety on light, dark and pure black backgrounds.
- Responsive from 360 px phones to wide desktop screens. Wide screens get a fixed menu on the left, use
  the full width, and put short sections side by side in two columns. Wide tables scroll inside their own
  section and never make the whole page scroll sideways.
- A viewport tag, so pages scale correctly on phones.
- Full UTF-8 handling with `<set Charset="utf-8">`: quotes, words and nicks in the new sections keep their
  accented and non-Latin letters.
- Column titles stay on one line, tables share one left edge, "3 days ago" no longer breaks, and the shared
  default avatar is shown small and faded.

## New sections

All are on by default and can be switched off individually.

| Section | What it shows | Option |
|---|---|---|
| Channel overview | A headline sentence and the key facts: words, lines per day, busiest and quietest hour, questions, links, top talker, joins, kicks | `ShowOverview` |
| Who talks to whom | An interactive map of who addresses, mentions or answers whom. Click a nick or a line for details. Bots are left out | `ShowRelations`, `RelationNicks`, `RelationMinWeight` |
| Closest pairs | The strongest two-way conversations, with how they talk | `ShowRelations` |
| Social roles | Most talked to, most outgoing, connector, best listener, lone wolf | `ShowRelations` |
| Time personalities | Who owns the night, morning, afternoon and evening | `ShowTimePersonalities` |
| Who carries the channel | How much of the talk comes from the top 1, 3, 5, 10 and 20 | `ShowConcentration` |
| Signature words | The word each person uses a lot and hardly anyone else does | `ShowSignatureWords` |

The relation map spaces its nicks by how close they are, not to scale, so a busy channel does not crush
the middle of the map. Nicks marked `sex="b"` or `ignore="y"` are treated as bots.

English and French texts are included. Other languages fall back to English.

## Navigation

- **Left menu** on screens 1000 px and wider: the channel name, every section, and a marker on the section
  you are reading.
- **Section bar** on narrower screens: a slim bar showing where you are, with a "Sections" button that opens
  the whole list. It works without JavaScript. (`ShowNavBar`, on by default)
- **Back button** (`HomeLink`): an "All channels" button above the title of every stats page that leads to
  your landing page.

## Landing page

`site/index.html` is a single static file: no PHP, no cron job, no libraries. It works on any static host,
including GitHub Pages. Copy it next to your stats pages.

pisg writes `channels.json` beside each page (option `ChannelIndex`) and the landing page turns it into
the statistics of the statistics:

- a headline (lines, channels, days of history) and facts across every channel;
- one row per channel: share of all lines, nicks, lines per day, its busiest hour, a 24-hour profile in
  the time-of-day colours, a small chart of the last 30 days, and a **View stats** button;
- the five busiest people in each channel.

Old links such as `index.html#canada` still jump to that channel. Names from the JSON are always shown as
plain text, and only plain relative `.html` paths are accepted as links.

## New options

| Option | Default | What it does |
|---|---|---|
| `ShowOverview` | on | The channel overview section |
| `ShowRelations` | on | The relation map, closest pairs and social roles |
| `RelationNicks` | 30 | How many nicks the relation map shows |
| `RelationMinWeight` | 3 | How strong a connection must be to be drawn |
| `ShowTimePersonalities` | on | Time personalities section |
| `ShowConcentration` | on | *Who carries the channel* section |
| `ShowSignatureWords` | on | Signature words section |
| `ShowNavBar` | on | The section bar and left menu |
| `HomeLink` | empty | Page the "All channels" button leads to (`index.html`, or an http(s) address). Empty or `none`: no button |
| `BadUrls` | empty | Words that keep a URL out of the URL statistics. Case-insensitive, matched anywhere in the URL, with `*` and `?` wildcards (for example `postimg.cc/*`) |
| `ChannelIndex` | `channels.json` | File pisg writes for the landing page. `none` turns it off |

`pisg.cfg.example` now lists every option with what it does, so it can be copied and used at once.

## Tools for the people who run the channel

These are optional and live in `scripts/`.

- **`eggdrop-pisg.tcl`**: profile commands for an eggdrop, in the channel (`!pisg...`) and in a private
  message (`pisg...`). Nothing is stored in pisg itself: the bot writes `users.cfg`, which pisg reads
  with `<include="users.cfg">`.
  - `!pisghelp [command]`: explains each command.
  - `!pisginfo`: set your sex, picture and link.
  - `!pisgmerge` / `!pisgunmerge`: count your other nicks as one person, or stop.
  - `!pisgshow`, `!pisgdel`, and `!pisgdeluser` (bot masters only).
  - `!pisgstats`: replies with the address of the stats page. It is open to everyone, and it no longer runs
    pisg inside the bot.
  - Your own settings (paths, the address of your stats) go in `pisg.local.tcl` next to the script, so an
    update never overwrites them.
  - People are identified by their network account (`getaccount`, or the account host on Undernet),
    can only claim the nick they are using, and cannot overwrite a `<user>` line you wrote by hand.
    Changes are rate limited. There is a test suite: `eggdrop-pisg-test.tcl` (107 checks).
- **`pisg-autoalias.py`**: nicks seen with the same authenticated host (`*.users.undernet.org`) are one
  person. It writes a file for pisg to include and can run before every pisg run. Your own `<user>` lines
  always win. Shared hosts, gateways and bouncers are never merged. Test suite included.
- **`adiirc2eggdrop.py`**: turns an AdiIRC (or similar) channel log into eggdrop or **ZNC** logs, so old history
  can be added to the statistics. It keeps public events only, converts local time to UTC, never
  overwrites a file, and stops at the moment your real logging starts. `--format znc` writes what the ZNC
  log module writes (one file per day, `energymech` format).
- **`znc-setup.sh`**: puts converted logs into a ZNC account's log folder and lets pisg, which runs as a different
  Unix user, read only the channel folders it needs. It shows what it would do before it changes anything.
- pisg reads ZNC logs with `Format="energymech"` and a `LogDir` per channel.

## Running several channels

- One `pisg.cfg` can hold any number of `<channel>` blocks. If a channel cannot be read (a missing log
  folder, a wrong format), pisg prints `Skipped channel #name: reason`, carries on with the others, and exits
  with status 1 so cron or monitoring notices.
- An error in one channel no longer leaks that channel's nick aliases into the next one.
- Each channel reads its own `LogDir` (a folder of dated log files, read in date order), so eggdrop's daily
  logs and ZNC's one-file-a-day logs can sit side by side in one config.

## Reliability

- A page is written to a temporary file and moved into place only once it is complete, so an error can
  never leave a half-written page where the good one was.
- pisg now exits with status 1 when it fails (it used to exit 0).
- A section that fails is skipped with a warning; the rest of the page is still written.
- Long quotes are shortened on a character boundary, so UTF-8 text is no longer cut in half.
- "Most used words" no longer lists punctuation or ASCII art.
- URL statistics honour `BadUrls`, so spam and image-host links can be left out.

## Documentation

- `docs/pisg-doc.html`: the whole manual as one web page, with a complete example configuration for a
  `#example` channel at the end. Built from `docs/pisg-doc.xml` by `docs/xml2html.py`.
- `pisg.cfg.example`: every option, built by `docs/gen-example-config.py`.
- New options are documented in the manual, and `README.md` has a short "what's new".

## Upgrading

1. Replace the program files. Your `pisg.cfg` keeps working as it is. (New to pisg? Run `perl setup.pl`.)
2. **The new sections are on by default**, in every colour scheme (the old ones show them in a plain
   style). If you want the old page exactly, set `ShowOverview`, `ShowRelations`, `ShowTimePersonalities`,
   `ShowConcentration`, `ShowSignatureWords` and `ShowNavBar` to `0`.
3. To use the new look, add `<set ColorScheme="modern">` (or `midnight`, `amoled`, `terminal`, `canada`).
4. `pisg` now returns exit status 1 on failure. If a script or cron job treated any exit as success,
   check what it does with the error.
5. For the landing page, copy `site/index.html` into your output folder and run pisg once so
   `channels.json` exists. Add `<set HomeLink="index.html">` for the back button.

**Requirements** are unchanged for pisg itself (Perl). The optional tools need Python 3 (converter, alias
generator), Tcl 8.6 and an eggdrop (the bot script), and `JSON::PP`, part of core Perl, for `ChannelIndex`.
