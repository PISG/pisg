#!/usr/bin/env python3
"""Convert docs/pisg-doc.xml (DocBook subset) into a single self-contained HTML page.

Usage: python3 docs/xml2html.py [input.xml] [output.html]
Defaults: docs/pisg-doc.xml -> docs/pisg-doc.html
"""
import html
import re
import sys
import textwrap
import urllib.parse
import xml.etree.ElementTree as ET
from pathlib import Path

here = Path(__file__).resolve().parent
src = Path(sys.argv[1]) if len(sys.argv) > 1 else here / "pisg-doc.xml"
dst = Path(sys.argv[2]) if len(sys.argv) > 2 else here / "pisg-doc.html"

raw = src.read_text(encoding="utf-8", errors="replace")
# The file starts with a comment before the XML declaration and references a
# DTD we don't have; drop both so a plain XML parser accepts it.
raw = re.sub(r"^\s*<!--.*?-->\s*", "", raw, count=1, flags=re.S)
raw = re.sub(r"<\?xml[^>]*\?>", "", raw, count=1)
raw = re.sub(r"<!DOCTYPE.*?>", "", raw, count=1, flags=re.S)
root = ET.fromstring(raw)

esc = html.escape

# id -> display text, used to resolve <xref linkend=...>
labels = {}
for el in root.iter():
    i = el.get("id")
    if not i:
        continue
    if el.tag == "refentry":
        labels[i] = el.findtext("refnamediv/refname") or i
    else:
        labels[i] = (el.findtext("title") or i).strip()

chapter_no = 0


def inline(el):
    """Render an element's mixed content (text + children + tails)."""
    out = [esc(el.text or "")]
    for ch in el:
        out.append(node(ch))
        out.append(esc(ch.tail or ""))
    return "".join(out)


def node(el):
    global chapter_no
    t = el.tag
    if t == "para":
        return "<p>" + inline(el).strip() + "</p>\n"
    if t in ("programlisting", "screen"):
        text = "".join(el.itertext()).strip("\n")
        text = re.sub(r"^\s*\n", "", text)
        return "<pre>" + esc(textwrap.dedent(text).rstrip()) + "</pre>\n"
    if t == "itemizedlist":
        return "<ul>\n" + "".join(node(c) for c in el) + "</ul>\n"
    if t == "listitem":
        body = "".join(node(c) for c in el)
        return "<li>" + body + "</li>\n"
    if t == "xref":
        i = el.get("linkend", "")
        return f'<a href="#{esc(i)}">{esc(labels.get(i, i))}</a>'
    if t == "link":
        i = el.get("linkend")
        if i:
            return f'<a href="#{esc(i)}">{inline(el)}</a>'
        return inline(el)
    if t == "ulink":
        return f'<a href="{esc(el.get("url", ""))}">{inline(el).strip()}</a>'
    if t in ("command", "filename", "userinput", "prompt"):
        return "<code>" + inline(el) + "</code>"
    if t == "emphasis":
        return "<em>" + inline(el) + "</em>"
    if t == "chapter":
        chapter_no += 1
        title = el.findtext("title") or ""
        body = "".join(node(c) for c in el if c.tag != "title")
        return (f'<section class="chapter" id="{esc(el.get("id", ""))}">'
                f"<h2>{chapter_no}. {esc(title.strip())}</h2>\n{body}</section>\n")
    if t == "sect1":
        title = el.findtext("title") or ""
        body = "".join(node(c) for c in el if c.tag != "title")
        return (f'<section id="{esc(el.get("id", ""))}">'
                f"<h3>{esc(title.strip())}</h3>\n{body}</section>\n")
    if t == "refentry":
        name = el.findtext("refnamediv/refname") or ""
        purpose = el.findtext("refnamediv/refpurpose") or ""
        parts = [f'<section class="option" id="{esc(el.get("id", ""))}">',
                 f"<h3>{esc(name.strip())}"
                 f' <span class="purpose">{esc(" ".join(purpose.split()))}</span></h3>\n']
        syn = el.find("refsynopsisdiv")
        if syn is not None:
            parts.append("".join(node(c) for c in syn))
        for rs in el.findall("refsect1"):
            parts.append(node(rs))
        parts.append("</section>\n")
        return "".join(parts)
    if t == "refsect1":
        title = el.findtext("title") or ""
        body = "".join(node(c) for c in el if c.tag != "title")
        return f"<h4>{esc(title.strip())}</h4>\n{body}"
    if t in ("toc", "title", "subtitle", "bookinfo"):
        return ""
    # Unknown element: keep its text so nothing silently disappears.
    return inline(el)


def toc():
    rows = []
    n = 0
    for ch in root.findall("chapter"):
        n += 1
        rows.append(f'<li><a href="#{esc(ch.get("id", ""))}">{n}. {esc(ch.findtext("title").strip())}</a>')
        subs = [(s.get("id"), (s.findtext("title") or "").strip()) for s in ch.findall("sect1")]
        subs += [(r.get("id"), (r.findtext("refnamediv/refname") or "").strip()) for r in ch.findall("refentry")]
        if subs:
            if len(subs) > 12:  # long option lists: compact inline index
                rows.append('<div class="opts">' + " ".join(
                    f'<a href="#{esc(i)}">{esc(s)}</a>' for i, s in subs) + "</div>")
            else:
                rows.append("<ul>" + "".join(
                    f'<li><a href="#{esc(i)}">{esc(s)}</a></li>' for i, s in subs) + "</ul>")
        rows.append("</li>")
    rows.append(example_toc)
    return "<ul>" + "".join(rows) + "</ul>"


body = "".join(node(c) for c in root if c.tag == "chapter")   # numbers the chapters first

# Final chapter: the complete example configuration, straight from pisg.cfg.example
# (regenerate that with docs/gen-example-config.py). Skipped if the file is absent.
example_file = here.parent / "pisg.cfg.example"
example_html = ""
example_toc = ""
if example_file.exists():
    cfg_text = example_file.read_text(encoding="utf-8")
    chapter_no += 1
    download = "data:text/plain;charset=utf-8," + urllib.parse.quote(cfg_text)
    example_toc = (f'<li><a href="#example-config">{chapter_no}. Complete example configuration</a></li>')
    example_html = f"""<section class="chapter" id="example-config">
<h2>{chapter_no}. Complete example configuration</h2>
<p>A ready-to-use <code>pisg.cfg</code> for a channel called <code>#example</code>. It lists every
option pisg understands, with what it does, so you can copy it and change only the lines marked
<code>EDIT</code>: the log file, its format, the network name, the output file and your name.
Options are at pisg's own defaults unless the comment says <em>recommended</em>.</p>
<ol>
<li>Copy the file below (or download it) and save it as <code>pisg.cfg</code> next to <code>pisg</code>.</li>
<li>Change the <code>EDIT</code> values in the <code>&lt;channel&gt;</code> block.</li>
<li>Run <code>./pisg</code>.</li>
</ol>
<div class="codewrap">
<div class="codebar"><span>pisg.cfg</span>
<a class="btn" href="{download}" download="pisg.cfg">Download</a>
<button class="btn copy" type="button" data-target="cfg-example">Copy</button></div>
<pre id="cfg-example" class="cfg">{esc(cfg_text)}</pre>
</div>
</section>
"""

title = root.findtext("bookinfo/title") or "pisg documentation"
subtitle = root.findtext("bookinfo/subtitle") or ""
body += example_html

page = f"""<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{esc(title)}</title>
<style>
:root {{ --bg:#fff; --fg:#1d2329; --muted:#5b6672; --line:#d9dee3; --code:#f3f5f7; --link:#0b6b3a; }}
@media (prefers-color-scheme: dark) {{
  :root {{ --bg:#14181c; --fg:#e3e8ec; --muted:#98a4af; --line:#2a3138; --code:#1d2329; --link:#5fd08e; }}
}}
body {{ margin:0; background:var(--bg); color:var(--fg);
  font:16px/1.6 system-ui,-apple-system,"Segoe UI",Roboto,sans-serif; }}
main {{ max-width:60rem; margin:0 auto; padding:2rem 1rem 4rem; }}
a {{ color:var(--link); }}
h1 {{ margin-bottom:.2rem; }} .sub {{ color:var(--muted); margin-top:0; }}
h2 {{ margin-top:3rem; padding-bottom:.3rem; border-bottom:2px solid var(--line); }}
h3 {{ margin-top:2rem; }} h4 {{ margin:1rem 0 .2rem; color:var(--muted);
  text-transform:uppercase; font-size:.8rem; letter-spacing:.06em; }}
.purpose {{ font-weight:400; font-size:.85rem; color:var(--muted); margin-left:.5rem; }}
section.option {{ border-top:1px solid var(--line); padding-top:.5rem; }}
pre {{ background:var(--code); border:1px solid var(--line); border-radius:6px;
  padding:.75rem 1rem; overflow-x:auto; font-size:.85rem; }}
code {{ background:var(--code); padding:.1em .3em; border-radius:4px; font-size:.9em; }}
nav {{ border:1px solid var(--line); border-radius:8px; padding:.5rem 1.2rem; margin:1.5rem 0; }}
/* example config: code block with copy/download bar */
.codewrap {{ border:1px solid var(--line); border-radius:8px; overflow:hidden; margin:1rem 0; }}
.codebar {{ display:flex; align-items:center; gap:.5rem; padding:.4rem .75rem; background:var(--code);
  border-bottom:1px solid var(--line); font-size:.85rem; color:var(--muted); }}
.codebar span {{ flex:1; font-family:ui-monospace,Menlo,Consolas,monospace; }}
.btn {{ font:inherit; font-size:.8rem; padding:.25rem .7rem; border:1px solid var(--line); border-radius:6px;
  background:var(--bg); color:var(--fg); cursor:pointer; text-decoration:none; }}
.btn:hover {{ border-color:var(--link); color:var(--link); }}
pre.cfg {{ margin:0; border:0; border-radius:0; max-height:36rem; overflow:auto; font-size:.8rem; line-height:1.45; }}
nav .opts a {{ display:inline-block; margin:.1rem .6rem .1rem 0; font-size:.85rem; }}
</style>
</head>
<body>
<main>
<h1>{esc(title)}</h1>
<p class="sub">{esc(subtitle)}</p>
<nav aria-label="Contents">{toc()}</nav>
{body}</main>
<script>
document.querySelectorAll('.copy').forEach(function (b) {{
  b.addEventListener('click', function () {{
    var pre = document.getElementById(b.dataset.target), text = pre.textContent;
    function done(ok) {{ var old = b.textContent; b.textContent = ok ? 'Copied!' : 'Press Ctrl+C';
      setTimeout(function () {{ b.textContent = old; }}, 1800); }}
    function fallback() {{ var r = document.createRange(); r.selectNodeContents(pre);
      var s = window.getSelection(); s.removeAllRanges(); s.addRange(r);
      var ok = false; try {{ ok = document.execCommand('copy'); }} catch (e) {{}} done(ok); }}
    if (navigator.clipboard && window.isSecureContext) {{ navigator.clipboard.writeText(text).then(function () {{ done(true); }}, fallback); }}
    else {{ fallback(); }}
  }});
}});
</script>
</body>
</html>
"""
dst.write_text(page, encoding="utf-8")
print(f"wrote {dst} ({len(page)//1024} KiB, {chapter_no} chapters)")
