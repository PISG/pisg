#!/usr/bin/env python3
"""Generate the modern pisg themes (layout/<name>.css) from one shared stylesheet.

pisg inlines exactly one CSS file into the page, so every theme must be self-contained. The
shared rules live here once and each theme is just a palette.

Design: ink on cool paper, and colour reserved for data. The interface is monochrome; the four
time-of-day colours (night violet, morning yellow, afternoon aqua, evening orange) are the only
hues on the page besides one series colour. They were checked with the dataviz palette validator
in light, dark and on pure black (colour-blind separation, contrast, lightness band), so they
can be trusted. Nicks and figures are set in monospace, like an IRC client. Sections are
separated by a hairline and space, not boxed.

Usage: python3 layout/build-themes.py      (rewrites the generated .css files)
Add a theme: add an entry to THEMES below and re-run, then use <set ColorScheme="yourtheme">.
The old themes (default, darkred, ocean, ...) are untouched.
"""
from pathlib import Path

out_dir = Path(__file__).resolve().parent

# Palette keys
#  bg page | surface panels (map canvas, menu) | fg text | muted secondary text
#  line hairlines | line2 stronger rules | hover row hover | mark single-series colour
#  t0..t3 hours 0-5 / 6-11 / 12-17 / 18-23 | male / female nick colours | shadow menu shadow
LIGHT = dict(bg="#f6f7f9", surface="#ffffff", fg="#171b21", muted="#59626d", line="#e0e3e8",
             line2="#c6ccd4", hover="#eceff3", mark="#2a78d6",
             t0="#4a3aa7", t1="#eda100", t2="#1baf7a", t3="#eb6834",
             male="#2a5fb0", female="#b03a72",
             shadow="0 18px 32px -14px rgba(20,24,30,.28)")
DARK = dict(bg="#0f1318", surface="#171c23", fg="#e8ebef", muted="#98a2ae", line="#252c35",
            line2="#38414c", hover="#1b2129", mark="#3987e5",
            t0="#9085e9", t1="#c98500", t2="#199e70", t3="#d95926",
            male="#7aa7ea", female="#e58ab5",
            shadow="0 18px 32px -14px rgba(0,0,0,.6)")

SANS = 'system-ui, -apple-system, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif'
MONO = 'ui-monospace, "SF Mono", "Cascadia Mono", "JetBrains Mono", Menlo, Consolas, "Liberation Mono", monospace'

THEMES = {
    # Follows the visitor's OS setting: light by day, dark by night.
    "modern": dict(desc="Ink on paper, colour only for data; follows the visitor's light/dark setting",
                   scheme="light dark", light=LIGHT, dark=DARK, sans=SANS, mono=MONO),
    "midnight": dict(desc="Blue-black, always dark", scheme="dark", light=DARK, dark=None,
                     sans=SANS, mono=MONO),
    "amoled": dict(desc="Pure black, always dark", scheme="dark", dark=None,
                   light=dict(DARK, bg="#000000", surface="#0a0b0d", line="#1c2027", line2="#2c323b",
                              hover="#101216", shadow="0 18px 32px -14px rgba(0,0,0,.9)"),
                   sans=SANS, mono=MONO),
    "terminal": dict(desc="Everything in monospace, green on black, like a console",
                     scheme="dark", dark=None,
                     light=dict(DARK, bg="#060a07", surface="#0b120d", fg="#b9f3c4", muted="#6ea77a",
                                line="#17301c", line2="#24492b", hover="#0f1a12", mark="#3ddc84",
                                male="#7fd6ff", female="#ff9ad0"),
                     sans=MONO, mono=MONO),
    # Red and white, for #canada.
    "canada": dict(desc="Warm paper with a maple-red series colour; dark variant follows the visitor's setting",
                   scheme="light dark", sans=SANS, mono=MONO,
                   light=dict(LIGHT, bg="#faf6f5", line="#e8dcdb", line2="#d3c2c1", hover="#f3eae9", mark="#c8102e"),
                   dark=dict(DARK, bg="#150d0e", surface="#1e1416", line="#33232a", line2="#4a3239", hover="#231719", mark="#ff5a6d")),
}

KEYS = ["bg", "surface", "fg", "muted", "line", "line2", "hover", "mark",
        "t0", "t1", "t2", "t3", "male", "female", "shadow"]


def vars_block(p, indent="  "):
    return "\n".join(f"{indent}--{k}: {p[k]};" for k in KEYS)


BASE = r"""
/* pisg output is table markup, so these rules restyle the existing classes (headtext, hicell,
   tdtop, rankc ...). The generator wraps each section in <div class="card" id="...">. */

html { -webkit-text-size-adjust: 100%; scroll-behavior: smooth; }

body {
  margin: 0;
  padding: 32px 24px 96px;
  background: var(--bg);
  color: var(--fg);
  font-family: __SANS__;
  font-size: 15px;
  line-height: 1.55;
}
body > div { max-width: 1040px; margin: 0 auto; text-align: left; }   /* pisg centres it with align=center */

/* Fixed 925/929px table widths are attributes, so plain CSS overrides them. */
table { border-collapse: separate; border-spacing: 0; max-width: 100%; }
table[width] { width: 100%; }
table[width="520"] { width: auto; margin: 10px 0 0; }
td { color: var(--fg); font-family: inherit; font-size: 14px; text-align: left; padding: 9px 10px; vertical-align: middle; overflow-wrap: anywhere; }   /* long URLs and nicks wrap instead of forcing a scrollbar */

a, a:link, a:visited { color: inherit; font-weight: 600; text-decoration: underline; text-decoration-color: var(--line2); text-underline-offset: 3px; }
a:hover { text-decoration-color: currentColor; }
a:focus-visible, summary:focus-visible, button:focus-visible { outline: 2px solid var(--fg); outline-offset: 2px; }
a.background, a.background:link, a.background:visited { color: var(--muted); font-weight: 500; }

/* ---- Masthead: reads like an IRC header, "#channel @ network" ---- */
.title, #pagetitle1 {
  margin: 4px 0 8px;
  font-family: __MONO__;
  font-size: clamp(24px, 4.6vw, 40px);
  line-height: 1.15;
  font-weight: 700;
  letter-spacing: -0.035em;
  color: var(--fg);
  overflow-wrap: anywhere;
}
.subtitle { margin: 0 0 18px; color: var(--muted); font-size: 14px; }
.subtitle b { color: var(--fg); font-weight: 600; }

/* ---- Sections: a rule and space, no boxes ---- */
.card { margin: 56px 0 0; padding: 20px 0 0; border-top: 1px solid var(--line2); overflow-x: auto; text-align: left; scroll-margin-top: 64px; }
.card > br { display: none; }
.pisg-nav + .card { margin-top: 28px; border-top: 0; padding-top: 0; }
#overview .headlinebg { position: absolute; width: 1px; height: 1px; overflow: hidden; clip: rect(0 0 0 0); }   /* the sentence below is its headline; the menu still links here */
.card > table:first-of-type { margin-bottom: 8px; }
.headlinebg { background: none; padding: 0; }
.headtext { margin: 0; padding: 0; border: 0; background: none; color: var(--fg);
            font-size: 20px; line-height: 1.25; font-weight: 650; letter-spacing: -0.01em; text-align: left; }
.intro { margin: 2px 0 16px; max-width: 68ch; color: var(--muted); }

/* ---- Wide screens: a menu down the left, the page fills the rest ---- */
body { container-type: inline-size; }
.nav-side { display: none; }
@media (min-width: 1000px) {
  body { padding-left: 272px; padding-right: 28px; }
  body > div { max-width: 1720px; }
  .pisg-nav { box-sizing: border-box; position: fixed; top: 0; left: 0; bottom: 0; width: 232px; margin: 0; padding: 26px 12px 24px 24px;
              border: 0; border-right: 1px solid var(--line2); background: var(--bg); overflow-y: auto; z-index: 30; }
  .nav-menu { display: none; }
  .nav-side { display: block; }
  .nav-brand, .nav-brand:link, .nav-brand:visited { display: block; margin: 0 0 18px; font-family: __MONO__; font-size: 18px; font-weight: 700;
              letter-spacing: -0.02em; text-decoration: none; overflow-wrap: anywhere; }
  .nav-side-list { margin: 0; padding: 0; list-style: none; }
  .nav-side-list a, .nav-side-list a:link, .nav-side-list a:visited { display: block; margin-left: -10px; padding: 6px 10px; border-left: 2px solid transparent;
              color: var(--muted); font-size: 14px; font-weight: 500; text-decoration: none; }
  .nav-side-list a:hover { color: var(--fg); background: var(--hover); }
  .nav-side-list a.active { color: var(--fg); font-weight: 650; border-left-color: var(--mark); }
  .card { scroll-margin-top: 24px; }
  .card td:not(.headtext):not(.headlinebg) { padding-left: 8px; padding-right: 8px; }   /* the 10-column nick table just fits beside the menu */
  .pisg-nav + .card { margin-top: 20px; }
}
/* Two short sections share a row when the page is wide enough (measured on the page, so it also holds inside a frame). */
@container (min-width: 1080px) {
  body > div { display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); column-gap: 56px; grid-auto-flow: dense; }
  body > div > * { grid-column: 1 / -1; }
  body > div > .card.half { grid-column: auto; }
}

/* Way back to the landing page (option HomeLink) */
.homebar { margin: 0 0 14px; text-align: left; }
.homebtn, .homebtn:link, .homebtn:visited { display: inline-flex; align-items: center; gap: 6px; padding: 5px 12px; border: 1px solid var(--line2); border-radius: 6px;
  background: var(--surface); color: var(--fg); font-size: 13px; font-weight: 600; line-height: 1.3; text-decoration: none; }
.homebtn:hover { background: var(--hover); border-color: var(--fg); }

/* Column titles */
.tdtop { background: none; color: var(--muted); font-size: 11px; font-weight: 600; letter-spacing: .08em;
         text-transform: uppercase; border-bottom: 1px solid var(--line2); padding: 8px 10px; }
.tdtop { white-space: nowrap; }   /* column titles stay on one line; the table scrolls instead */
.tdtop b { font-weight: 600; }

/* Rows: one hairline each */
.hicell { background: none; border-bottom: 1px solid var(--line); border-radius: 0; padding: 11px 10px; }
.hicell10 { background: none; font-size: 12px; border-bottom: 1px solid var(--line); }
tr:last-child > .hicell { border-bottom: 0; }
/* pisg writes an inline colour gradient on the top-nicks rows (HiCell/HiCell2); the theme owns colour. */
td[style*="background-color"] { background: transparent !important; border-bottom: 1px solid var(--line); }
tr:hover > td[style*="background-color"], tr:hover > .rankc, tr:hover > .hirankc { background: var(--hover) !important; }

.rankc, .hirankc, .rankc10 { background: transparent; color: var(--muted); font-family: __MONO__; font-size: 12px;
                              font-weight: 500; text-align: center; border-bottom: 1px solid var(--line); }
.hirankc { color: var(--fg); font-weight: 700; }
.rankc, .hirankc, .rankc10 { white-space: nowrap; }
.rankc10 { text-align: left; }
/* nicks are set in monospace, as in an IRC client */
.rankc + td, .hirankc + td { font-family: __MONO__; font-weight: 600; }
.small, .asmall { color: var(--muted); font-family: inherit; font-size: 12px; }
.asmall { text-align: center; }

/* ---- Bar charts (marks: thin, 4px rounded data end, 2px gap between segments) ---- */
table:not([width]) { width: 100%; table-layout: fixed; margin: 6px 0; }
td.asmall { padding: 0 2px; line-height: 1.3; vertical-align: bottom; }   /* bars stand on one baseline */
table:not([width]) tr:first-child > td.asmall { border-bottom: 1px solid var(--line2); }
td.asmall br { display: none; }
td.rankc10center, td.hirankc10center { background: none; border: 0; color: var(--muted); font-family: __MONO__;
                                         font-size: 11px; text-align: center; padding: 6px 0 0; min-width: 0; letter-spacing: -0.02em; }   /* no side padding: 24 narrow columns must not poke out of the table */
td.hirankc10center { color: var(--fg); font-weight: 700; }
/* a number over every bar is noise: the peak keeps its label, the rest are in the tooltip */
td.asmall .v { display: none; }
td.asmall .v.pk { display: block; color: var(--fg); font-family: __MONO__; font-weight: 600; }
.rankc10center.skip { visibility: hidden; }

img[id$="-v"] { display: block; width: min(64%, 22px); margin: 0 auto; border-radius: 0; }
img[id$="-v"]:first-of-type { border-radius: 4px 4px 0 0; }
img[id$="-v"]:not(:first-of-type) { margin-top: 2px; }
img[id$="-v"]:only-of-type { border-radius: 4px 4px 0 0; }
img[id$="-h"] { height: 8px; vertical-align: middle; margin: 0 1px 0 0; border-radius: 0; }
td[nowrap] img[id$="-h"] { background: var(--mark); margin-right: 0; }   /* lines: one value, one colour; the "when" column keeps the four */
img[id$="-h"]:first-of-type { border-radius: 4px 0 0 4px; }
img[id$="-h"]:last-of-type { margin-right: 0; border-radius: 0 4px 4px 0; }
img[id$="-h"]:only-of-type { border-radius: 4px; }
td.asmall img[id$="-h"] { margin-right: 6px; }
table[width="520"] img[id$="-h"] { width: 14px; height: 8px; border-radius: 2px; }   /* legend: a colour key, not a bar */
table[width="520"] td.asmall { text-align: left; padding: 0 14px 0 0; white-space: nowrap; }
/* the colour key wraps instead of forcing a sideways scrollbar on a narrow screen */
table[width="520"] { display: flex; flex-wrap: wrap; gap: 4px 0; width: auto; max-width: 100%; }
table[width="520"] tbody, table[width="520"] tr { display: contents; }
img[id="blue-h"],   img[id="blue-v"]   { background: var(--t0); }
img[id="green-h"],  img[id="green-v"]  { background: var(--t1); }
img[id="yellow-h"], img[id="yellow-v"] { background: var(--t2); }
img[id="red-h"],    img[id="red-v"]    { background: var(--t3); }

td[rowspan] img { width: 36px; height: 36px; object-fit: cover; border-radius: 50%; display: block; margin: 0 auto; }
td[rowspan] img.defpic { width: 26px; height: 26px; opacity: .3; }   /* the shared default picture: a quiet placeholder */

/* ranked tables: one left edge, and no stray rule under the last row */
tr:first-child > td:not([class]):first-child { border-bottom: 1px solid var(--line2); }
tr:last-child > .rankc, tr:last-child > .hirankc, tr:last-child > td[style*="background-color"] { border-bottom: 0; }
.rankc, .hirankc { width: 44px; }
td[style*="background-color"] { white-space: nowrap; }          /* "3 days ago" stays on one line ... */
td[style*="background-color"].quote { white-space: normal; }    /* ... only the quote may wrap */
.male, .male a { color: var(--male); }
.female, .female a { color: var(--female); }
.bot, .bot a { color: var(--muted); font-style: italic; }

/* single-series bars */
.bar { display: inline-block; vertical-align: middle; width: 140px; max-width: 100%; height: 8px; border-radius: 4px; background: var(--line); overflow: hidden; }
.bar span { display: block; height: 100%; border-radius: 4px; background: var(--mark); opacity: 1; }
.sigword { font-family: __MONO__; font-weight: 600; }

/* "These didn't make it to the top:" is a bare <b><i> under the table; give it the same voice as a column title */
.card > b { display: block; margin: 26px 0 4px; color: var(--muted); font-size: 11px; font-weight: 600; letter-spacing: .08em; text-transform: uppercase; }
.card > b > i { font-style: normal; }

#totallines { margin-top: 56px; padding-top: 14px; border-top: 1px solid var(--line2); color: var(--muted); font-size: 12px; }
#footer { margin-top: 2px; color: var(--muted); }
#footer .small { font-size: 12px; }
::selection { background: var(--fg); color: var(--bg); }

/* ---- Section menu: one slim bar, one panel ---- */
.pisg-nav { background: var(--bg); border-bottom-color: var(--line2); margin-bottom: 0; }
.nav-current { color: var(--fg); font-weight: 650; }
.nav-toggle { color: var(--muted); opacity: 1; }
.nav-list { background: var(--surface); border-color: var(--line2); box-shadow: var(--shadow); }
.nav-list a, .nav-list a:link, .nav-list a:visited { color: var(--fg); font-weight: 500; text-decoration: none; }
.nav-list a:hover { background: var(--hover); }
.nav-list a.active { font-weight: 700; }

/* ---- Overview: a sentence and a list of facts, not a wall of tiles ---- */
.hero { margin: 2px 0 22px; font-size: clamp(20px, 2.6vw, 26px); line-height: 1.3; font-weight: 650; letter-spacing: -0.02em; text-wrap: balance; }
.hero b { font-family: __MONO__; font-weight: 700; letter-spacing: -0.05em; }
.facts { display: grid; grid-template-columns: repeat(auto-fit, minmax(300px, 1fr)); gap: 0 56px; margin: 0; }
.fact { display: flex; align-items: baseline; justify-content: space-between; gap: 16px; padding: 11px 0; border-bottom: 1px solid var(--line); }
.fact dt { color: var(--muted); }
.fact dd { margin: 0; text-align: right; font-family: __MONO__; font-weight: 600; font-variant-numeric: tabular-nums; }
.fact dd small { display: block; color: var(--muted); font-family: __SANS__; font-size: 12px; font-weight: 400; }

/* ---- Roles, personalities: columns split by a rule, no boxes ---- */
.cardgrid { display: grid; grid-template-columns: repeat(auto-fit, minmax(168px, 1fr)); gap: 28px 32px; margin: 8px 0 0; }
.minicard { display: flex; flex-direction: column; gap: 3px; padding: 12px 0 0; border: 0; border-top: 1px solid var(--line2); border-radius: 0; background: none; text-align: left; }
.mc-title { color: var(--muted); font-size: 11px; font-weight: 600; letter-spacing: .08em; text-transform: uppercase; }
.mc-name { font-family: __MONO__; font-size: 19px; font-weight: 700; line-height: 1.3; overflow-wrap: anywhere; }
.mc-desc { color: var(--muted); font-size: 13px; }
.mc-value { margin-top: 6px; font-size: 13px; font-weight: 600; }
.mc-list { margin: 8px 0 0; padding: 0; list-style: none; }
.mc-list li { display: flex; justify-content: space-between; gap: 8px; padding: 5px 0; border-top: 1px solid var(--line); font-family: __MONO__; font-size: 13px; }
.mc-list span { color: var(--muted); }
.minicard.t0 { border-top: 3px solid var(--t0); } .minicard.t1 { border-top: 3px solid var(--t1); }
.minicard.t2 { border-top: 3px solid var(--t2); } .minicard.t3 { border-top: 3px solid var(--t3); }

/* ---- Relation map: the one lifted surface ---- */
.relmap-canvas svg { box-sizing: border-box; background: var(--surface); border: 1px solid var(--line2); border-radius: 8px; }   /* width:100% must include the border */
.relmap-info { background: none; border: 0; border-top: 1px solid var(--line2); border-radius: 0; padding: 12px 0 0; }
.relmap-legend { color: var(--muted); }
.ri-title { font-family: __MONO__; color: var(--fg); }
.ri-sub, .ri-num { color: var(--muted); opacity: 1; }
.ri-list li { border-top-color: var(--line); }
.ri-link { color: var(--fg); font-family: __MONO__; text-decoration-color: var(--line2); }
.lg0 i, .rm-node.t0 circle { background: var(--t0); fill: var(--t0); } .lg1 i, .rm-node.t1 circle { background: var(--t1); fill: var(--t1); }
.lg2 i, .rm-node.t2 circle { background: var(--t2); fill: var(--t2); } .lg3 i, .rm-node.t3 circle { background: var(--t3); fill: var(--t3); }
.rm-line { stroke: var(--muted); }
.rm-node circle { stroke: var(--surface); }
.rm-node text { fill: var(--fg); stroke: var(--surface); font-family: __MONO__; font-size: 12px; }
.rm-edge.sel .rm-line { stroke: var(--fg); }
.rm-node:focus-visible circle, .rm-node.sel circle { stroke: var(--fg); }

@media (max-width: 720px) {
  body { padding: 20px 16px 72px; font-size: 14px; }
  .hr.rankc10center:nth-child(even) { visibility: hidden; }     /* every second hour label on a phone */
  td { padding: 7px 6px; font-size: 13px; }
  .bar { width: 64px; }
  .card { margin-top: 44px; }
  .facts { grid-template-columns: 1fr; }
  td[rowspan] img { width: 30px; height: 30px; }
}
"""


def theme_css(name, t):
    head = f"/* pisg theme: {name} - {t['desc']}.\n   Generated by layout/build-themes.py, edit the palette there. */\n"
    root = f":root {{\n  color-scheme: {t['scheme']};\n{vars_block(t['light'])}\n}}\n"
    if t["dark"]:
        root += ("@media (prefers-color-scheme: dark) {\n  :root {\n"
                 + vars_block(t["dark"], "    ") + "\n  }\n}\n")
    return head + root + BASE.replace("__SANS__", t["sans"]).replace("__MONO__", t["mono"])


for name, t in THEMES.items():
    path = out_dir / f"{name}.css"
    path.write_text(theme_css(name, t), encoding="utf-8")
    print(f"wrote {path.name} ({path.stat().st_size} bytes) - {t['desc']}")
