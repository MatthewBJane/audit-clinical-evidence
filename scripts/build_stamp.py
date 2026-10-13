#!/usr/bin/env python3
"""
Freshness stamp for every page (runs after every render, after cache_bust.py).

GitHub Pages tells browsers they may reuse a page for 10 minutes without
asking whether it changed, and that cannot be configured. So a visitor who
opened the site shortly before a publish could keep seeing the previous
version for a while. To stop that:

  1. every page gets <meta name="ace-build" content="..."> in its head: a
     fingerprint of that page as built (its text, which already carries the
     version tags cache_bust.py put on its CSS, scripts and images, so a
     changed stylesheet changes the fingerprint too);
  2. docs/version.json lists the fingerprint of every page.

A small script in the head of every page (_quarto.yml, include-in-header)
fetches version.json past the cache on each visit. If the page's own stamp
differs from the published one, the page is a leftover copy: it fetches the
current page and reloads. Pages that have not changed keep their fingerprint,
so publishing never reloads a page for nothing. Safe to run repeatedly.
"""
import hashlib
import json
import os
import re
from pathlib import Path

OUT = Path(os.environ.get("QUARTO_PROJECT_OUTPUT_DIR", "docs")).resolve()
# never published (see .gitignore), so never listed in version.json
SKIP = {"site_libs", "_to_delete"}
META = re.compile(r'\s*<meta name="ace-build" content="[0-9a-f]*">')
HEAD = re.compile(r"<head[^>]*>", re.I)

pages = {}
for page in sorted(OUT.rglob("*.html")):
    rel = page.relative_to(OUT)
    if SKIP & set(rel.parts):
        continue
    text = META.sub("", page.read_text(encoding="utf-8"))
    m = HEAD.search(text)
    if not m:
        continue
    stamp = hashlib.md5(text.encode("utf-8")).hexdigest()[:10]
    stamped = text[:m.end()] + '\n<meta name="ace-build" content="%s">' % stamp + text[m.end():]
    if stamped != page.read_text(encoding="utf-8"):
        page.write_text(stamped, encoding="utf-8")
    pages[rel.as_posix()] = stamp

(OUT / "version.json").write_text(
    json.dumps({"pages": pages}, sort_keys=True, separators=(",", ":")) + "\n",
    encoding="utf-8")
print("build_stamp: %d pages stamped, version.json written" % len(pages))
