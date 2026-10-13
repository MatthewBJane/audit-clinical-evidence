#!/usr/bin/env python3
"""
Cache-busting for the site's own files (runs after every render).

GitHub Pages lets browsers reuse a file for up to 10 minutes, and our own files
(styles.css, simulator scripts, CV.pdf, report PDFs, figures, logos) keep the
same name from one render to the next. A returning visitor can then get a new
page with an old stylesheet, an old PDF, or an old figure. This adds a version
tag based on each file's contents to every link to it, e.g.

    href="styles.css"   ->  href="styles.css?v=3f9a1c2e"
    href="CV.pdf"       ->  href="CV.pdf?v=91be0c7d"
    url("images/x.svg") ->  url("images/x.svg?v=0a1b2c3d")   (inside our CSS)

When a file changes, its tag changes and browsers fetch the new copy at once;
when it doesn't, the tag stays the same and the cached copy is still used.
Quarto's own libraries (site_libs/: quarto.js, the compiled Bootstrap theme,
search, listings) get tags too: most of them keep the same file name from one
Quarto version to the next, so after an upgrade or a theme change a returning
visitor could otherwise mix new pages with old scripts. Links to other
websites are left alone. Safe to run repeatedly.
"""
import hashlib
import os
import re
from pathlib import Path

OUT = Path(os.environ.get("QUARTO_PROJECT_OUTPUT_DIR", "docs")).resolve()
EXT = r"(?:css|js|pdf|png|jpe?g|svg|webp|gif|ico|avif|mp4|webm|csv|zip|woff2?|otf|ttf)"
HTML_LINK = re.compile(r'((?:href|src)=")([^"#?]+\.' + EXT + r')(\?v=[0-9a-f]+)?(")', re.I)
CSS_URL = re.compile(r'(url\(\s*["\']?)([^"\')?#]+\.' + EXT + r')(\?v=[0-9a-f]+)?(["\']?\s*\))', re.I)
_hash = {}


def version(path: Path):
    key = str(path)
    if key not in _hash:
        _hash[key] = hashlib.md5(path.read_bytes()).hexdigest()[:8] if path.is_file() else None
    return _hash[key]


def tagged(base: Path, m: re.Match) -> str:
    url = m.group(2).strip()
    if "://" in url or url.startswith(("//", "data:", "mailto:")):
        return m.group(0)
    target = (OUT / url.lstrip("/")) if url.startswith("/") else (base / url)
    v = version(target.resolve())
    if not v:
        return m.group(0)
    return f"{m.group(1)}{m.group(2)}?v={v}{m.group(4)}"


def ours(p: Path) -> bool:
    return "site_libs" not in p.relative_to(OUT).parts


# 1) images referenced from CSS, ours and Quarto's (before hashing the CSS itself)
for css in sorted(OUT.rglob("*.css")):
    t = css.read_text(encoding="utf-8")
    n = CSS_URL.sub(lambda m: tagged(css.parent, m), t)
    if n != t:
        css.write_text(n, encoding="utf-8")

# 2) every link to our files from every page
changed = 0
for page in sorted(OUT.rglob("*.html")):
    if not ours(page):
        continue
    t = page.read_text(encoding="utf-8")
    n = HTML_LINK.sub(lambda m: tagged(page.parent, m), t)
    if n != t:
        page.write_text(n, encoding="utf-8")
        changed += 1
print(f"cache_bust: version tags updated in {changed} page(s)")
