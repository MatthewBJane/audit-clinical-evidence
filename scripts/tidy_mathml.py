#!/usr/bin/env python3
"""
Tidy pandoc's MathML (runs after every render, before cache_bust.py).

Pandoc marks every bracket as stretchy, so a plain $2(n-1)$ comes out with
<mo stretchy="true">( ... )</mo>, the markup for \\left( ... \\right). Browsers
then draw those brackets as if they had to grow, with extra space inside
them ("2 ( n − 1 )"). For any formula whose TeX has no \\left, \\right or
\\big-type sizing, this marks the brackets as ordinary again. Formulas that
ask for growing brackets are left as pandoc wrote them. Safe to run
repeatedly.
"""
import os
import re
from pathlib import Path

OUT = Path(os.environ.get("QUARTO_PROJECT_OUTPUT_DIR", "docs")).resolve()
SKIP = {"site_libs", "_to_delete"}
MATH = re.compile(r"<math\b.*?</math>", re.S)
TEX = re.compile(r'<annotation encoding="application/x-tex">(.*?)</annotation>', re.S)
SIZED = re.compile(r"\\(left|right|middle|[bB]igg?[lrm]?)\b")
FENCE = re.compile(r'<mo stretchy="true" form="(prefix|postfix)">')


def tidy(m):
    block = m.group(0)
    tex = TEX.search(block)
    if tex and SIZED.search(tex.group(1)):
        return block
    return FENCE.sub(r'<mo stretchy="false" form="\1">', block)


changed = 0
for page in sorted(OUT.rglob("*.html")):
    if SKIP & set(page.relative_to(OUT).parts):
        continue
    text = page.read_text(encoding="utf-8")
    if "<math" not in text:
        continue
    new = MATH.sub(tidy, text)
    if new != text:
        page.write_text(new, encoding="utf-8")
        changed += 1
print("tidy_mathml: brackets fixed in %d page(s)" % changed)
