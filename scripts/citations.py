#!/usr/bin/env python3
"""Citation counts for the papers a report audits, from OpenAlex.

    python3 scripts/citations.py reports/ACE2026001/index.qmd

Reads the `audited:` DOIs from the report's front matter, asks OpenAlex for
each paper's citing works, flags the ones that are meta-analyses or reviews,
and writes two CSVs into the report folder:

    reports/<ID>/data/citations.csv          one row per audited paper (for Table 1)
    reports/<ID>/data/citations_detail.csv   one row per citing work (the evidence)
    reports/<ID>/data/citations_downstream.csv  (--deep only) every work citing a
                                                flagged review, de-duplicated

Downstream reach: each citing work's own citation count comes back with it, so
`reviews_downstream` in the summary is the sum of citations received by the
meta-analyses/reviews that cite the paper (a review cited by two of the audited
papers is counted for each). With --deep the script also fetches the citers of
every flagged review and reports the de-duplicated number of distinct works
(`downstream_unique`), per paper and across the report. Deep mode can mean
thousands of records for a heavily cited review; it pages at 200 per request.

The report reads the summary CSV (helpers: citation_tt()), so rendering never
touches the network and the numbers in a published version are frozen with it.
Re-run this script to refresh; the retrieval date is recorded in the CSV.

Classification: a citing work counts as a meta-analysis/review when OpenAlex
types it as "review" OR its title matches the REVIEW_PATTERN below. Check the
detail file for a new report; adjust the pattern if a title slips through.

OpenAlex is free and needs no key. The `mailto` puts requests in the polite
pool (faster, more reliable); set OPENALEX_MAILTO to override.
"""
import csv
import datetime as dt
import json
import os
import re
import sys
import time
import urllib.parse
import urllib.request
from pathlib import Path

API = "https://api.openalex.org"
MAILTO = os.environ.get("OPENALEX_MAILTO", "contact@auditclinicalevidence.org")
# Clinical guidelines / policy statements published in journals (OpenAlex sees
# these; grey-literature policy from WHO/NICE/governments needs Overton or
# Altmetric, both key-gated, so they are out of scope here).
GUIDELINE_PATTERN = re.compile(
    r"guideline|consensus statement|consensus recommendation|position (statement|paper)|"
    r"practice parameter|clinical practice|expert consensus|standards? of care|"
    r"policy statement|scientific statement|practice advisory|recommendations? (for|on) the "
    r"(management|treatment|diagnosis|prevention)",
    re.I,
)
REVIEW_PATTERN = re.compile(
    r"meta-?analy|systematic review|umbrella review|scoping review|narrative review|"
    r"network meta|pooled analysis|\breview\b|evidence synthesis|overview of reviews",
    re.I,
)


def get(url: str, params: dict) -> dict:
    params = dict(params, mailto=MAILTO)
    full = url + "?" + urllib.parse.urlencode(params)
    req = urllib.request.Request(full, headers={"User-Agent": f"ACE citations.py (mailto:{MAILTO})"})
    for attempt in range(5):
        try:
            with urllib.request.urlopen(req, timeout=60) as r:
                return json.load(r)
        except urllib.error.HTTPError as e:
            if e.code == 429 and attempt < 4:
                time.sleep(2 * (attempt + 1))
                continue
            raise
    raise RuntimeError("OpenAlex: too many retries")


def audited_dois(qmd: Path) -> list[str]:
    text = qmd.read_text(encoding="utf-8")
    m = re.search(r"^audited:\s*\n((?:\s+-\s+.*\n)+)", text, re.M)
    if not m:
        sys.exit(f"No `audited:` list found in {qmd}")
    return [re.sub(r'^\s*-\s*"?|"?\s*$', "", line) for line in m.group(1).splitlines() if line.strip()]


def work_for_doi(doi: str) -> dict:
    return get(f"{API}/works/doi:{doi}", {
        "select": "id,doi,title,publication_year,cited_by_count,authorships"})


def citing_works(openalex_id: str):
    wid = openalex_id.rsplit("/", 1)[-1]
    cursor = "*"
    while cursor:
        page = get(f"{API}/works", {
            "filter": f"cites:{wid}", "per-page": 200, "cursor": cursor,
            "select": "id,doi,title,type,publication_year,primary_location,cited_by_count"})
        for w in page.get("results", []):
            yield w
        cursor = page.get("meta", {}).get("next_cursor")
        time.sleep(0.2)


def is_review(w: dict) -> bool:
    title = w.get("title") or ""
    # "peer review" / "peer-reviewed" is not a review article
    title = re.sub(r"peer[- ]review\w*", "", title, flags=re.I)
    return w.get("type") == "review" or bool(REVIEW_PATTERN.search(title))


def is_guideline(w: dict) -> bool:
    return bool(GUIDELINE_PATTERN.search(w.get("title") or ""))


def first_author_family(work: dict) -> str:
    auths = work.get("authorships") or []
    if not auths:
        return "Unknown"
    name = auths[0].get("author", {}).get("display_name", "Unknown")
    return name.split()[-1]


def citers_of(openalex_id: str):
    """Yield the OpenAlex ids of works citing a work (for --deep)."""
    wid = openalex_id.rsplit("/", 1)[-1]
    cursor = "*"
    while cursor:
        page = get(f"{API}/works", {"filter": f"cites:{wid}", "per-page": 200,
                                    "cursor": cursor, "select": "id,doi,title,publication_year,type"})
        for w in page.get("results", []):
            yield w
        cursor = page.get("meta", {}).get("next_cursor")
        time.sleep(0.2)


def write_impact(qmd: Path, cited: int, reviews: int, guidelines: int, today: str) -> None:
    """Write/replace an `impact:` block in the report front matter so the site
    listing can show the totals without reading the CSV."""
    text = qmd.read_text(encoding="utf-8")
    block = ("impact:                      # written by scripts/citations.py (OpenAlex)\n"
             f"  cited: {cited}\n"
             f"  infected-reviews: {reviews}\n"
             f"  spread-guidelines: {guidelines}\n"
             f"  retrieved: \"{today}\"\n")
    if re.search(r"^impact:.*\n(?:  .*\n)+", text, re.M):
        text = re.sub(r"^impact:.*\n(?:  .*\n)+", block, text, count=1, flags=re.M)
    else:
        # after the audited: list (which must exist, we read it above)
        text = re.sub(r"(^audited:\s*\n(?:\s+-\s+.*\n)+)", r"\1\n" + block.replace("\\", "\\\\"), text,
                      count=1, flags=re.M)
    qmd.write_text(text, encoding="utf-8")


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    deep = "--deep" in sys.argv
    qmd = Path([a for a in sys.argv[1:] if not a.startswith("--")][0]).resolve()
    out_dir = qmd.parent / "data"
    out_dir.mkdir(exist_ok=True)
    today = dt.date.today().isoformat()

    summary, detail, downstream_rows, all_downstream = [], [], [], set()
    for doi in audited_dois(qmd):
        work = work_for_doi(doi)
        label = f"{first_author_family(work)} ({work.get('publication_year')})"
        print(f"{doi}: {work.get('cited_by_count')} citations in OpenAlex ...", end=" ", flush=True)
        n_total = n_review = n_guide = downstream = 0
        review_ids, direct_guideline_ids = [], set()
        for w in citing_works(work["id"]):
            rev = is_review(w)
            guide = is_guideline(w)
            n_total += 1
            n_review += rev
            n_guide += guide
            if rev:
                downstream += w.get("cited_by_count") or 0
                review_ids.append(w["id"])
            if guide:
                direct_guideline_ids.add(w["id"])
            venue = ((w.get("primary_location") or {}).get("source") or {}).get("display_name", "")
            detail.append({
                "audited_doi": doi, "openalex_id": w["id"],
                "citing_doi": (w.get("doi") or "").replace("https://doi.org/", ""),
                "year": w.get("publication_year"), "openalex_type": w.get("type"),
                "is_review": int(rev), "is_guideline": int(guide),
                "cited_by_count": w.get("cited_by_count") or 0,
                "title": w.get("title") or "", "venue": venue,
            })
        print(f"{n_total} listed, {n_review} meta-analyses/reviews, {n_guide} guidelines, "
              f"reviews cited {downstream} times downstream")
        row = {
            "audited_doi": doi, "label": label, "title": work.get("title") or "",
            "year": work.get("publication_year"), "total": n_total, "reviews": n_review,
            "guidelines": n_guide, "reviews_downstream": downstream,
            # Guidelines reached either directly or through an infected review,
            # de-duplicated by OpenAlex id. Without --deep this equals `guidelines`.
            "spread_guidelines": len(direct_guideline_ids),
            "retrieved": today, "source": "OpenAlex",
        }
        if deep:
            seen = {}
            for rid in review_ids:
                for w in citers_of(rid):
                    seen.setdefault(w["id"], {"via_review": rid, "audited_doi": doi,
                                              "doi": (w.get("doi") or "").replace("https://doi.org/", ""),
                                              "year": w.get("publication_year"), "type": w.get("type"),
                                              "is_guideline": int(is_guideline(w)),
                                              "title": w.get("title") or ""})
            row["downstream_unique"] = len(seen)
            row["downstream_guidelines"] = sum(v["is_guideline"] for v in seen.values())
            row["spread_guidelines"] = len(direct_guideline_ids |
                                           {k for k, v in seen.items() if v["is_guideline"]})
            downstream_rows.extend(seen.values())
            all_downstream.update(seen.keys())
            print(f"    deep: {len(seen)} distinct downstream works, "
                  f"{row['downstream_guidelines']} guideline-like")
        summary.append(row)

    with (out_dir / "citations.csv").open("w", newline="", encoding="utf-8") as f:
        wr = csv.DictWriter(f, fieldnames=list(summary[0].keys()))
        wr.writeheader(); wr.writerows(summary)
    with (out_dir / "citations_detail.csv").open("w", newline="", encoding="utf-8") as f:
        wr = csv.DictWriter(f, fieldnames=list(detail[0].keys()) if detail else
                            ["audited_doi", "openalex_id", "citing_doi", "year", "openalex_type",
                             "is_review", "is_guideline", "cited_by_count", "title", "venue"])
        wr.writeheader(); wr.writerows(detail)
    if deep:
        with (out_dir / "citations_downstream.csv").open("w", newline="", encoding="utf-8") as f:
            cols = ["audited_doi", "via_review", "doi", "year", "type", "is_guideline", "title"]
            wr = csv.DictWriter(f, fieldnames=cols)
            wr.writeheader(); wr.writerows(downstream_rows)
        print(f"deep: {len(all_downstream)} distinct downstream works across the report "
              f"(union over audited papers)")
    write_impact(qmd, sum(r["total"] for r in summary), sum(r["reviews"] for r in summary),
                 sum(r.get("spread_guidelines", 0) for r in summary), today)
    print(f"\nWrote {out_dir / 'citations.csv'} and citations_detail.csv (retrieved {today}),")
    print(f"and the `impact:` totals into {qmd.name} for the site listing.")
    print("Review the detail file: the review/meta-analysis flag is title-based and OpenAlex's")
    print("`type`, so check it once per report and edit REVIEW_PATTERN if needed.")


if __name__ == "__main__":
    main()
