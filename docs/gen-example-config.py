#!/usr/bin/env python3
"""Generate pisg.cfg.example: a complete, ready-to-use configuration.

Every option comes from two sources so nothing can be missed or drift:
  * docs/pisg-doc.xml   - name, description, documented default, grouping
  * modules/Pisg.pm     - the real default value used by the code
Options the old docs never mention (BotNicks, TableWidth, the bar image
options) are described in EXTRA below.

Usage: python3 docs/gen-example-config.py      -> writes pisg.cfg.example
Then:  python3 docs/xml2html.py                -> embeds it in pisg-doc.html
"""
import re
import textwrap
import xml.etree.ElementTree as ET
from pathlib import Path

root_dir = Path(__file__).resolve().parent.parent
xml_raw = (root_dir / "docs" / "pisg-doc.xml").read_text(encoding="utf-8")
xml_raw = re.sub(r"^\s*<!--.*?-->\s*", "", xml_raw, count=1, flags=re.S)
xml_raw = re.sub(r"<\?xml[^>]*\?>", "", xml_raw, count=1)
xml_raw = re.sub(r"<!DOCTYPE.*?>", "", xml_raw, count=1, flags=re.S)
tree = ET.fromstring(xml_raw)

# ---- real defaults from the code ------------------------------------------------
code = (root_dir / "modules" / "Pisg.pm").read_text(encoding="utf-8")
block = code[code.index("$self->{cfg} = {"):code.index("version =>")]
DEFAULTS = {}
for m in re.finditer(r"^\s+(\w+)\s*=>\s*(?:'((?:[^'\\]|\\.)*)'|\"([^\"]*)\"|(-?\d+)|(\[\]))", block, re.M):
    val = next((g for g in m.groups()[1:] if g is not None), "")
    DEFAULTS[m.group(1).lower()] = "" if val == "[]" else val.replace("\\\\", "\\").replace("\\'", "'")

# ---- options the old documentation does not cover --------------------------------
EXTRA = {
    "BotNicks": "nicks of bots, for log formats that cannot tell bots from people (DCpp)",
    "TableWidth": "width in pixels of the statistics tables",
    "Pic_H_0": "image id of the horizontal bar for hours 0-5",
    "Pic_H_6": "image id of the horizontal bar for hours 6-11",
    "Pic_H_12": "image id of the horizontal bar for hours 12-17",
    "Pic_H_18": "image id of the horizontal bar for hours 18-23",
    "Pic_V_0": "image id of the vertical bar for hours 0-5",
    "Pic_V_6": "image id of the vertical bar for hours 6-11",
    "Pic_V_12": "image id of the vertical bar for hours 12-17",
    "Pic_V_18": "image id of the vertical bar for hours 18-23",
}

# ---- choices for the example ---------------------------------------------------------
# Recommended values that differ from pisg's stock defaults, with the reason.
RECOMMENDED = {
    "ColorScheme": ("modern", "modern, light/dark theme; try midnight, amoled, terminal, or default"),
    "Charset": ("utf-8", "UTF-8 shows accents, emoji and non-Latin scripts correctly"),
    "NickTracking": ("1", "follow nick changes so Alice, Alice_ and Alice- count as one person"),
    "DailyActivity": ("14", "show the last 14 days as a bar chart"),
    "ShowWords": ("1", "also show total words"),
    "ShowWpl": ("1", "also show words per line"),
    "ShowCpl": ("1", "also show characters per line"),
    "ShowMostNicks": ("1", "show who changed nick most often"),
    "ShowSmileys": ("1", "show the most used smileys"),
    "ShowKarma": ("1", "show karma (nick++ / nick--)"),
    "ShowMostActiveByHour": ("1", "show the most active nicks by time of day"),
    "TopicHistory": ("5", "show the last 5 topics"),
}

# Options that are alternatives, need a file, or are off/empty by default. They stay
# commented out with an example value so the file still works exactly as it stands.
COMMENTED = {
    "LogDir": ("/path/to/logs/", "use INSTEAD of Logfile to read a whole folder of dated logs"),
    "LogPrefix": ("example.log.", "with LogDir: only read files starting with this"),
    "LogSuffix": (".%d%b%Y", "with LogDir: date format at the end of the file names, so they sort by date"),
    "NFiles": ("30", "with LogDir: only parse the newest N files (0 = all)"),
    "OutputTag": ("-week", "replaces %t in OutputFile; used with the -nf / -t command line options"),
    "AltColorScheme": ("midnight.css amoled.css", "extra stylesheets the visitor can switch to"),
    "PageHead": ("header.html", "HTML file inserted above the statistics"),
    "PageFoot": ("footer.html", "HTML file inserted below the statistics"),
    "CacheDir": ("cache/", "cache parsed logs here to speed up runs (delete it when you change settings)"),
    "IgnoreWords": ("badword otherword", "words to leave out of the word statistics"),
    "BadUrls": ("imagetwist imgur.com postimg.cc/*", "matched anywhere in a URL, any case; * = any characters, ? = one; for spam and unwanted image hosts"),
    "DefaultPic": ("images/nobody.png", "picture shown for users who have none"),
    "ImagePath": ("images/", "folder of user pictures, as seen by the web page"),
    "ImageGlobPath": ("/var/www/pisg/images/", "folder of user pictures, as seen by pisg (for pic=\"x_*.jpg\" globs)"),
    "PicWidth": ("55", "show every user picture this wide, in pixels"),
    "PicHeight": ("55", "show every user picture this tall, in pixels"),
    "LogCharset": ("iso-8859-1", "convert logs from this charset (needs the Text::Iconv perl module)"),
    "LogCharsetFallback": ("iso-8859-1", "used for lines that are not valid in LogCharset (needs Text::Iconv)"),
    "BotNicks": ("bot1 bot2", "only needed for the DCpp log format"),
    "StatsDump": ("stats.dump", "debugging: dump the raw statistics to this file"),
}

# Options that live in the <channel> block (set per channel), in display order.
CHANNEL_OPTS = ["Logfile", "LogDir", "LogPrefix", "LogSuffix", "NFiles", "Format", "Network",
                "OutputFile", "OutputTag", "Maintainer", "LogType"]
CHANNEL_VALUES = {
    "Logfile": ("/path/to/example.log", "the log to read; you can list several Logfile lines"),
    "Format": ("eggdrop", "your log format: eggdrop, mIRC, xchat, irssi, ... (see docs/FORMATS)"),
    "Network": ("ExampleNet", "the IRC network, shown on the page"),
    "OutputFile": ("/var/www/html/example.html", "the page pisg writes"),
    "Maintainer": ("Your Name", "who is named as maintainer on the page"),
    "LogType": ("Logfile", "only \"Logfile\" exists, leave it"),
}


def parse_options():
    """[(section title, [(name, purpose, documented default)])] in document order."""
    out = []
    for ch in tree.findall("chapter"):
        items = []
        for r in ch.findall("refentry"):
            name = r.findtext("refnamediv/refname").strip()
            purpose = " ".join((r.findtext("refnamediv/refpurpose") or "").split())
            dflt = ""
            for rs in r.findall("refsect1"):
                if (rs.findtext("title") or "").strip() == "Default":
                    dflt = " ".join("".join(rs.find("para").itertext()).split())
            for n in [x.strip() for x in name.split(",")]:      # "HiCell, HiCell2"
                items.append((n, purpose, dflt))
        if items:
            out.append((ch.findtext("title").strip(), items))
    return out


def comment(text, indent=""):
    return "\n".join(textwrap.wrap(text, 88, initial_indent=indent + "# ", subsequent_indent=indent + "# "))


def value_for(name):
    if name in RECOMMENDED:
        return RECOMMENDED[name][0]
    v = DEFAULTS.get(name.lower(), "")
    return "1" if (name == "UserPics" and v == "y") else v


lines = []
add = lines.append

add("""\
# pisg.cfg.example - a complete configuration for pisg, ready to copy.
#
#   1. Copy this file to pisg.cfg
#   2. Change the values marked  EDIT  (log path, format, network, output file, name)
#   3. Run ./pisg
#
# Every option pisg understands is listed below with its meaning. Options are set to
# pisg's own default unless the comment says "recommended". Lines starting with # are
# comments; an option shown commented out is off/unset - remove the # to use it.
#
# Syntax reminders:
#   <set Name="value">      a global option, applies to every channel
#   <channel="#name"> ... </channel>   settings for one channel (they override <set>)
#   <user nick="..." ...>   per-user settings
# Each <set> must be on one line, and every value must be in quotes.
""")

sections = parse_options()
documented = {n for _, items in sections for n, _, _ in items}
documented |= set(CHANNEL_VALUES)

add("")
add("#" * 78)
add("#  GLOBAL OPTIONS - apply to every channel below")
add("#" * 78)

seen = set(CHANNEL_OPTS) | {"Channel"}
emitted = set()
for title, items in sections:
    body = [(n, p, d) for n, p, d in items if n not in seen]
    if title.startswith("General"):
        title = "General options"
    if not body:
        continue
    add("")
    add(f"# ---- {title} " + "-" * max(4, 70 - len(title)))
    for name, purpose, dflt in body:
        emitted.add(name)
        add("")
        if name in RECOMMENDED:
            add(comment(f"{purpose} - recommended: {RECOMMENDED[name][1]}"))
        elif name in COMMENTED:
            add(comment(f"{purpose} - {COMMENTED[name][1]}"))
        else:
            add(comment(purpose))
        if name in COMMENTED:
            add(f'#<set {name}="{COMMENTED[name][0]}">')
        else:
            add(f'<set {name}="{value_for(name)}">')
            if name == "HiCell":            # documented together with HiCell2
                add(f'<set HiCell2="{DEFAULTS["hicell2"]}">')
                emitted.add("HiCell2")

# options that exist in the code but not in the old docs
add("")
add("# ---- Advanced (not in the original documentation) " + "-" * 25)
for name, purpose in EXTRA.items():
    add("")
    add(comment(purpose))
    if name in COMMENTED:
        add(f'#<set {name}="{COMMENTED[name][0]}">')
    else:
        add(f'<set {name}="{value_for(name)}">')
    emitted.add(name)

add("")
add("")
add("#" * 78)
add("#  YOUR CHANNEL - copy this block for each extra channel")
add("#" * 78)
add("")
add('<channel="#example">')
by_name = {n: (p, d) for _, items in sections for n, p, d in items}
for name in CHANNEL_OPTS:
    purpose = by_name[name][0] if name in by_name else ""
    if name in CHANNEL_VALUES:
        val, note = CHANNEL_VALUES[name]
        add(comment(f"{name}: {note}" + ("  EDIT" if name in ("Logfile", "Format", "Network", "OutputFile", "Maintainer") else ""), "  "))
        add(f'  {name}="{val}"')
    else:
        val, note = COMMENTED[name]
        add(comment(f"{name}: {note}", "  "))
        add(f'  #{name}="{val}"')
    add("")
add(comment("Any global option can be overridden for this channel only, for example:", "  "))
add('  #Lang="FR"')
add('  #ColorScheme="midnight"')
add("</channel>")

add("""

##############################################################################
#  USERS - link nicks together, add pictures, mark bots
##############################################################################
# nick    the name shown in the stats (required)
# alias   other nicks of the same person, space separated; * matches anything
#         (Joe* also counts Joe_, Joe^away ...). NickTracking="1" also finds many
# pic     picture shown next to the user      bigpic  larger picture it links to
# link    a web address or e-mail address      sex     m, f or b (bot)
# ignore  y = leave this nick out of the stats altogether (for bots)

<user nick="Alice" alias="Alice_ Alice-* AliceAway" pic="alice.png" link="https://example.com/alice" sex="f">
<user nick="Bob" alias="Bob_ Bobby" pic="bob.png" bigpic="bob-big.png" link="bob@example.com" sex="m">
<user nick="ChanBot" sex="b" ignore="y">

##############################################################################
#  LINKS - keep addresses out of "Most referenced URLs"
##############################################################################
<link url="https://example.com/spam" ignore="y">

##############################################################################
#  INCLUDE - share users between channels or config files
##############################################################################
# Put your <user> lines in users.cfg and load them here (an included file cannot
# include another file):
#<include="users.cfg">
""")

text = "\n".join(lines).rstrip() + "\n"

# completeness check: every documented option + every code default a user can set
internal = {"configfile", "cchannels", "modules_dir", "channel"}
present = {m.lower() for m in re.findall(r'^#?\s*<set (\w+)=', text, re.M)}
present |= {m.lower() for m in re.findall(r'^\s+#?(\w+)="', text, re.M)}
missing = sorted(k for k in DEFAULTS if k not in present and k not in internal)
assert not missing, f"options missing from the example: {missing}"

(root_dir / "pisg.cfg.example").write_text(text, encoding="utf-8")
print(f"wrote pisg.cfg.example: {len(text.splitlines())} lines, "
      f"{len(present)} options ({len(DEFAULTS)} defaults in code)")
