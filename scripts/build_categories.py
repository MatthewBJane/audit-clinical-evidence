#!/usr/bin/env python3
"""Faceted report categories.

Every ACE report describes what it audits with four fields in its front
matter:

    population: ["Heart Disease"]
    treatment:  ["Exercise"]
    outcome:    ["Depression"]
    design:     ["RCT"]

Quarto's listing machinery (the sidebar list, the keyword filter, the RSS
feed) only understands a single flat `categories` field, so this script runs
before every render (project: pre-render in _quarto.yml) and does two things:

  1. writes each report's `categories:` line from its four facet fields, in
     facet order, so the flat list is never maintained by hand;
  2. writes _includes/category-facets.html, a small script that hands the
     page a term -> facet map, which styles.css and the sidebar grouping
     script use to tint the chips and split the category list into
     Population / Treatment / Outcome / Design.

Edit the four fields; everything downstream follows. A term used under two
different facets is reported as a problem, since the map cannot be built.
"""
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
# ACE* rather than * so reports/_template/ is left alone
REPORTS = sorted(ROOT.glob("reports/ACE*/index.qmd"))
FACETS = ["population", "treatment", "outcome", "design"]
OUT = ROOT / "_includes" / "category-facets.html"

FM = re.compile(r"\A(---\n)(.*?\n)(---\n)", re.S)


def split_front_matter(text):
    m = FM.match(text)
    if not m:
        return None, text
    return m.group(2), text[m.end():]


def read_field(fm, name):
    """Values of a top-level front-matter field, flow or block style."""
    lines = fm.split("\n")
    for i, line in enumerate(lines):
        m = re.match(r"^(%s)\s*:\s*(.*)$" % re.escape(name), line)
        if not m:
            continue
        rest = m.group(2).strip()
        if rest.startswith("["):                      # flow list on one line
            return [v.strip().strip('"\'') for v in
                    re.findall(r'"[^"]*"|\'[^\']*\'|[^,\[\]]+', rest[1:rest.rfind("]")])
                    if v.strip()]
        if rest:                                      # single scalar
            return [rest.strip('"\'')]
        vals = []                                     # block list underneath
        for nxt in lines[i + 1:]:
            if re.match(r"^\s*-\s+", nxt):
                vals.append(re.sub(r"^\s*-\s+", "", nxt).strip().strip('"\''))
            elif nxt.strip() == "" or nxt.startswith(("#",)):
                continue
            else:
                break
        return vals
    return None


def drop_field(fm, name):
    """Remove a top-level field and any block list under it."""
    lines = fm.split("\n")
    out, i = [], 0
    while i < len(lines):
        if re.match(r"^%s\s*:" % re.escape(name), lines[i]):
            i += 1
            while i < len(lines) and re.match(r"^\s*-\s+", lines[i]):
                i += 1
            continue
        out.append(lines[i])
        i += 1
    return "\n".join(out)


def flow(values):
    return "[" + ", ".join('"%s"' % v for v in values) + "]"


def main():
    facet_of, problems, notes, changed = {}, [], [], 0

    for qmd in REPORTS:
        rel = qmd.relative_to(ROOT)
        text = qmd.read_text(encoding="utf-8")
        fm, body = split_front_matter(text)
        if fm is None:
            problems.append("%s: no front matter" % rel)
            continue

        terms, missing = [], []
        for facet in FACETS:
            vals = read_field(fm, facet)
            if vals is None:
                missing.append(facet)
                continue
            for v in vals:
                if facet_of.get(v, facet) != facet:
                    problems.append("%s: \"%s\" is %s here but %s elsewhere"
                                    % (rel, v, facet, facet_of[v]))
                facet_of[v] = facet
                if v not in terms:
                    terms.append(v)
        if missing:
            notes.append("%s: no %s field" % (rel, ", ".join(missing)))
        if not terms:
            continue

        line = "categories: %s" % flow(terms)
        if read_field(fm, "categories") == terms and re.search(
                r"^%s$" % re.escape(line), fm, re.M):
            continue

        # rewrite: drop the old field, put the generated one under `design:`
        new_fm = drop_field(fm, "categories")
        lines = new_fm.split("\n")
        anchor = max((i for i, l in enumerate(lines)
                      if any(re.match(r"^%s\s*:" % f, l) for f in FACETS)), default=None)
        if anchor is None:
            problems.append("%s: nowhere to write categories" % rel)
            continue
        while anchor + 1 < len(lines) and re.match(r"^\s*-\s+", lines[anchor + 1]):
            anchor += 1
        lines.insert(anchor + 1, line)
        qmd.write_text("---\n" + "\n".join(lines) + "---\n" + body, encoding="utf-8")
        changed += 1

    OUT.parent.mkdir(exist_ok=True)
    OUT.write_text(
        "<!-- GENERATED by scripts/build_categories.py; edit the reports, not this file. -->\n"
        "<script>window.aceCategoryFacets = %s;</script>\n"
        % json.dumps(facet_of, sort_keys=True),
        encoding="utf-8")

    print("categories: %d terms across %d reports (%d rewritten)"
          % (len(facet_of), len(REPORTS), changed))
    for n in notes:
        print("  note: %s" % n)
    for p in problems:
        print("  PROBLEM: %s" % p)
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
