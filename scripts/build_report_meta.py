#!/usr/bin/env python3
"""Listing fields and the home page taxonomy grid, generated on every render.

Runs before every render (project: pre-render in _quarto.yml), after
build_categories.py. For each report it writes two generated lines into the
front matter, directly under `categories:`, so the listing cards and the home
page can show them without anyone keeping them in step by hand:

    violations: {total: 29}
    recommendation: "retraction"

  * `violations` counts the instance declarations in the report body, the
    same `N-@riv-x.y` syntax riv_summary_table() in reports/helpers/functions.R
    reads, so the card always agrees with the report's own summary table.
    HTML comments are ignored, as they are there.
  * `recommendation` is copied from correspondence.yml (the one place it is
    recorded). Reports that are not in that file get no line.

It also writes _includes/home-riv.md, the ACE-RIV grid on the home page:
every category in riv.yml, and the number of instances documented across
published reports (drafts are left out, as they are from the listings).
Severity tiers are deliberately not shown there.

Edit the reports, riv.yml or correspondence.yml; everything here follows.
"""
import html
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from build_categories import split_front_matter, read_field  # noqa: E402

# PyYAML if it is installed, otherwise the stdlib parser zenodo.py carries,
# so the render never needs anything installed.
from zenodo import parse_yaml  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
REPORTS = sorted(ROOT.glob("reports/ACE*/index.qmd"))
RIV = ROOT / "riv.yml"
CORR = ROOT / "correspondence.yml"
OUT = ROOT / "_includes" / "home-riv.md"

DECL = re.compile(r"(?<![0-9A-Za-z])([0-9]+)-@riv-([0-9]+\.[0-9]+)(?![0-9.]*[0-9])")
COMMENT = re.compile(r"<!--.*?-->", re.S)
GENERATED = "# violations, recommendation and citation: written by scripts/build_report_meta.py; do not edit."
SITE = "https://auditclinicalevidence.org"
PUBLISHER = "Audit Clinical Evidence"


def load_yaml(path):
    return parse_yaml(path.read_text(encoding="utf-8"))


def taxonomy():
    """[(section number, section title, [(number, name), ...]), ...]"""
    data = load_yaml(RIV)
    out = []
    for s in data["sections"]:
        out.append((s["number"], s["title"],
                    [(str(c["number"]), c["name"]) for c in s["categories"]]))
    return data.get("version", ""), out


def recommendations():
    if not CORR.exists():
        return {}
    data = load_yaml(CORR) or {}
    audits = (data.get("correspondence") or {}).get("audits") or []
    return {a.get("ace-id"): (a.get("recommendation") or "").strip()
            for a in audits if a.get("ace-id")}


def count(body):
    found = {}
    for n, k in DECL.findall(COMMENT.sub("", body)):
        found[k] = found.get(k, 0) + int(n)
    return found


def rewrite(fm, lines_to_add):
    """Drop earlier generated lines, then put the new ones under `categories:`
    (or under the last facet field if there is no categories line yet)."""
    keep = [l for l in fm.split("\n")
            if not re.match(r"^(violations|recommendation|citation)\s*:", l)
            and not l.startswith("# violations and recommendation:") and l != GENERATED]
    anchor = None
    for i, l in enumerate(keep):
        if re.match(r"^(categories|population|treatment|outcome|design)\s*:", l):
            anchor = i
    if anchor is None:
        return None
    while anchor + 1 < len(keep) and re.match(r"^\s*-\s+", keep[anchor + 1]):
        anchor += 1
    keep[anchor + 1:anchor + 1] = [GENERATED] + lines_to_add
    return "\n".join(keep)


def yq(v):
    """A double-quoted YAML scalar."""
    return '"%s"' % v.replace("\\", "\\\\").replace('"', '\\"')


def plain(text):
    """Abstract text for indexers: no citation syntax or markdown."""
    text = re.sub(r"\[-?@[^\]]*\]", "", text)          # [-@key; -@key]
    text = re.sub(r"(?<![\w.])@[A-Za-z][\w:-]*", "the audited study", text)
    text = re.sub(r"[*_`]", "", text)
    return re.sub(r"\s+([.,;:])", r"\1", re.sub(r"\s{2,}", " ", text)).strip()


def citation_line(fm, ace_id):
    """Google Scholar reads the citation_* meta tags Quarto writes from this
    block: the full title (title: subtitle), ACE as the journal and publisher,
    the report number, the page, the PDF, and the DOI once there is one."""
    title = (read_field(fm, "title") or [""])[0]
    sub = (read_field(fm, "subtitle") or [""])[0]
    full = "%s: %s" % (title, sub) if sub else title
    doi = (read_field(fm, "doi") or [""])[0]
    abstract = (read_field(fm, "abstract") or [""])[0]
    parts = ["type: article-journal", "title: %s" % yq(full),
             "container-title: %s" % yq(PUBLISHER), "publisher: %s" % yq(PUBLISHER),
             "number: %s" % yq(ace_id),
             "url: %s" % yq("%s/reports/%s/" % (SITE, ace_id)),
             "pdf-url: %s" % yq("%s/reports/%s/%s.pdf" % (SITE, ace_id, ace_id))]
    if doi:
        parts.append("doi: %s" % yq(doi))
    if abstract:
        parts.append("abstract: %s" % yq(plain(abstract)))
    return "citation: {%s}" % ", ".join(parts)


def grid_html(version, tax, found):
    n_cats = sum(len(c) for _, _, c in tax)
    rows = []
    for num, title, cats in tax:
        cells = []
        for k, name in cats:
            c = found.get(k, 0)
            badge = '<span class="ace-rc-count">%d</span>' % c if c else ""
            cells.append(
                '<button type="button" class="ace-rc%s" data-riv="%s" data-name="%s" '
                'data-count="%d" aria-label="RIV %s: %s">%s%s</button>'
                % (" is-found" if c else "", k, html.escape(name, quote=True), c, k,
                   html.escape(name, quote=True), k, badge))
        rows.append('<div class="ace-riv-row"><span class="ace-riv-row-title"><b>%s</b>%s</span>'
                    '<div class="ace-riv-cells">%s</div></div>'
                    % (num, html.escape(title), "".join(cells)))
    # resting state of the readout: the most documented category
    top = max(found, key=found.get) if found else tax[0][2][0][0]
    name = {k: n for _, _, cats in tax for k, n in cats}
    t_name = name[top]
    t_c = found.get(top, 0)
    readout = ('<span class="ace-riv-readout-key">RIV %s</span>'
               '<span class="ace-riv-readout-name">%s</span>'
               '<span class="ace-riv-readout-count">%s</span>'
               % (top, html.escape(t_name),
                  ("%d instance%s documented so far" % (t_c, "" if t_c == 1 else "s"))
                  if t_c else "Not yet documented in a published report"))
    return (
        "<!-- GENERATED by scripts/build_report_meta.py from riv.yml and the published reports; "
        "edit those, not this file. -->\n"
        "```{=html}\n"
        '<div class="ace-home-head">\n'
        '  <div><span class="ace-eyebrow">ACE-RIV v%s</span>'
        '<h2 class="ace-home-h2">The ACE Taxonomy of Research Integrity Violations</h2></div>\n'
        "  <p>Every finding in every report maps to a numbered category. Select one to see it. "
        "Badges count the instances documented so far.</p>\n"
        "</div>\n"
        '<div class="ace-riv-grid" id="ace-riv-grid">%s</div>\n'
        '<div class="ace-riv-readout" id="ace-riv-readout" aria-live="polite">%s</div>\n'
        '<div class="ace-riv-legend">'
        '<span><i class="is-found"></i>Documented in a published report</span>'
        '<span><i></i>Not yet documented</span>'
        '<a class="ace-ui ace-arrow-link" href="riv.html">Read the taxonomy <span aria-hidden="true">→</span></a>'
        "</div>\n"
        "```\n"
        % (version, "".join(rows), readout))


def main():
    version, tax = taxonomy()
    known = {k for _, _, cats in tax for k, _ in cats}
    recs = recommendations()
    published, problems, changed = {}, [], 0

    for qmd in REPORTS:
        rel = qmd.relative_to(ROOT)
        text = qmd.read_text(encoding="utf-8")
        fm, body = split_front_matter(text)
        if fm is None:
            problems.append("%s: no front matter" % rel)
            continue
        found = count(body)
        unknown = sorted(set(found) - known)
        if unknown:
            problems.append("%s: not in riv.yml: %s" % (rel, ", ".join(unknown)))

        ace_id = (read_field(fm, "ace-id") or [qmd.parent.name])[0]
        add = ["violations: {total: %d}" % sum(found.values())]
        if recs.get(ace_id):
            add.append('recommendation: "%s"' % recs[ace_id])
        add.append(citation_line(fm, ace_id))

        new_fm = rewrite(fm, add)
        if new_fm is None:
            problems.append("%s: no categories or facet field to write under" % rel)
            continue
        if new_fm != fm:
            qmd.write_text("---\n" + new_fm + "---\n" + body, encoding="utf-8")
            changed += 1

        draft = (read_field(fm, "draft") or ["false"])[0].lower() == "true"
        if not draft:
            for k, n in found.items():
                published[k] = published.get(k, 0) + n

    OUT.parent.mkdir(exist_ok=True)
    OUT.write_text(grid_html(version, tax, published), encoding="utf-8")

    print("report meta: %d reports (%d rewritten), %d instances on the home page grid"
          % (len(REPORTS), changed, sum(published.values())))
    for p in problems:
        print("  PROBLEM: %s" % p)
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
