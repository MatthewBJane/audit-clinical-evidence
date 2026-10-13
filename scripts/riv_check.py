#!/usr/bin/env python3
"""Check the ACE-RIV taxonomy and every report for drift.

    python3 scripts/riv_check.py            # riv.yml vs riv.qmd vs reports/*/index.qmd
    python3 scripts/riv_check.py --quiet    # only print problems

riv.yml is the source of truth (numbers, names, counting unit).
The script verifies that

  * riv.qmd has exactly one entry per category, with the same number, name
    as riv.yml, no severity badge (removed in v1.1), the anchor {#riv-x-y}, and a reference
    block with Criteria, Typical evidence and Counting;
  * every **Name (RIV x.y)** label in every report uses the exact name and
    number from riv.yml;
  * every @riv-x.y reference exists in riv.yml, every referenced RIV has at
    least one declaration "N-@riv-x.y" (the count in front of a reference,
    stripped from the rendered page), and the abstract's "N instances" (if
    present) equals the declared total;
  * a report that still carries a hand-written summary table agrees with the
    statements in its text.

Exit status is 1 if anything is wrong, so it can run in CI or before a push.
"""
import glob
import re
import sys
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parent.parent
WORDS = {w: i + 1 for i, w in enumerate(
    "one two three four five six seven eight nine ten eleven twelve thirteen fourteen "
    "fifteen sixteen seventeen eighteen nineteen twenty".split())}
LABEL = re.compile(r"\*\*([^*]+?) \(RIV (\d+\.\d+)\)\*\*")
DECL = re.compile(r"(?<![0-9A-Za-z])(\d+)-@riv-(\d+\.\d+)(?![\d.]*\d)")   # N-@riv-x.y declares N instances
REF = re.compile(r"@riv-(\d+\.\d+)(?![\d.]*\d)")
TABLE_ROW = re.compile(r"^\| \*\*RIV (\d+\.\d+)\*\* \| (.+?) \| (\d+) \|", re.M)

problems = []


def problem(where, msg):
    problems.append(f"{where}: {msg}")


def load_taxonomy():
    tax = yaml.safe_load((ROOT / "riv.yml").read_text(encoding="utf-8"))
    cats = {}
    for s in tax["sections"]:
        for k in s["categories"]:
            cats[str(k["number"])] = k
    return tax, cats


def check_page(tax, cats):
    text = (ROOT / "riv.qmd").read_text(encoding="utf-8")
    heads = re.findall(r"^#### RIV (\d+\.\d+): (.+?) \{#riv-(\d+)-(\d+)\}$", text, re.M)
    seen = {}
    for num, name, a, b in heads:
        seen[num] = name
        k = cats.get(num)
        if not k:
            problem("riv.qmd", f"RIV {num} is on the page but not in riv.yml"); continue
        if name != k["name"]:
            problem("riv.qmd", f"RIV {num} name is '{name}' but riv.yml says '{k['name']}'")
        if f"{a}.{b}" != num:
            problem("riv.qmd", f"RIV {num} anchor is #riv-{a}-{b}")
    for num in cats:
        if num not in seen:
            problem("riv.qmd", f"RIV {num} ({cats[num]['name']}) is in riv.yml but has no entry on the page")
    # every entry has the three-part reference block
    for blk in re.finditer(r"^#### RIV (\d+\.\d+):(.*?)(?=^#### RIV |^## |\Z)", text, re.M | re.S):
        num, body = blk.group(1), blk.group(2)
        for key in ("[Criteria]{.ace-riv-key}", "[Typical evidence]{.ace-riv-key}", "[Counting]{.ace-riv-key}"):
            if key not in body:
                problem("riv.qmd", f"RIV {num} lacks {key}")
    # severity tiers were removed in v1.1; none should come back by accident
    if re.search(r"\.ace-sev\b|Severity:|Escalates to Critical|Reduced to Minor", text):
        problem("riv.qmd", "contains severity-tier language, removed in ACE-RIV v1.1")
    m = re.search(r'subtitle:\s*"[^"]*version (\d+\.\d+)', text)
    if m and m.group(1) != str(tax["version"]):
        problem("riv.qmd", f"subtitle says version {m.group(1)} but riv.yml is {tax['version']}")


def strip_comments(text):
    """Drop HTML comments. A RIV named in a commented-out draft, or in the
    instructions carried by reports/_template/index.qmd, is not a finding."""
    return re.sub(r"<!--.*?-->", "", text, flags=re.S)


def check_report(path, tax, cats):
    text = strip_comments(Path(path).read_text(encoding="utf-8"))
    rel = str(Path(path).relative_to(ROOT))
    for name, num in LABEL.findall(text):
        k = cats.get(num)
        if not k:
            problem(rel, f"label **{name} (RIV {num})**: RIV {num} does not exist in riv.yml")
        elif name != k["name"]:
            problem(rel, f"label **{name} (RIV {num})** should be **{k['name']} (RIV {num})**")
    for num in REF.findall(text):
        if num not in cats:
            problem(rel, f"@riv-{num} is not a category in riv.yml")
    # declarations (outside code blocks), summed per RIV
    body = re.sub(r"^```.*?^```", "", text, flags=re.M | re.S)
    counts = {}
    for n, num in DECL.findall(body):
        counts[num] = counts.get(num, 0) + int(n)
    total = sum(counts.values())
    # referenced but never declared
    mentioned = set(num for _, num in LABEL.findall(body)) | set(REF.findall(body))
    for num in sorted(mentioned - set(counts), key=lambda s: [int(x) for x in s.split(".")]):
        problem(rel, f"RIV {num} is referenced but never declared (no 'N-@riv-{num}' in the text)")
    # abstract total
    m = re.search(r"identifies (\d+) instances? of Research Integrity Violations", text)
    if m and int(m.group(1)) != total:
        problem(rel, f"abstract says {m.group(1)} instances but the declarations total {total}")
    # hand-written table, if any
    rows = TABLE_ROW.findall(text)
    if rows:
        for num, name, n in rows:
            if num not in counts:
                problem(rel, f"summary table lists RIV {num} but the text never states it")
            elif int(n) != counts[num]:
                problem(rel, f"summary table gives RIV {num} = {n} but the declarations total {counts[num]}")
            if cats.get(num) and name.strip() != cats[num]["name"]:
                problem(rel, f"summary table names RIV {num} '{name.strip()}'; riv.yml says '{cats[num]['name']}'")
        tm = re.search(r"\| \*\*\*Total\*\*\* \|\s*\| \*\*\*(\d+)\*\*\* \|", text)
        if tm and int(tm.group(1)) != total:
            problem(rel, f"summary table total is {tm.group(1)} but the declarations total {total}")
    m = re.search(r"version (\d+\.\d+) of the \[ACE Research Integrity Violations taxonomy", text)
    # a report written under an earlier version reads that version, which
    # must be kept in _riv-versions/ (its frozen helpers.R points there)
    if m and m.group(1) != str(tax["version"]):
        if not (ROOT / "_riv-versions" / f"riv-{m.group(1)}.yml").exists():
            problem(rel, f"report cites ACE-RIV v{m.group(1)} but _riv-versions/riv-{m.group(1)}.yml is missing")
    return counts, total


def main():
    quiet = "--quiet" in sys.argv
    tax, cats = load_taxonomy()
    check_page(tax, cats)
    reports = sorted(glob.glob(str(ROOT / "reports" / "ACE*" / "index.qmd")))
    for r in reports:
        counts, total = check_report(r, tax, cats)
        if not quiet:
            summary = ", ".join(f"{k}×{v}" for k, v in sorted(counts.items(),
                                key=lambda kv: [int(x) for x in kv[0].split(".")]))
            print(f"{Path(r).parent.name}: {total} instances ({summary})")
    if not quiet:
        print(f"ACE-RIV v{tax['version']}: {len(cats)} categories; riv.qmd and {len(reports)} report(s) checked.")
    if problems:
        print("\nPROBLEMS:")
        for p in problems:
            print("  " + p)
        sys.exit(1)
    if not quiet:
        print("No problems found.")


if __name__ == "__main__":
    main()
