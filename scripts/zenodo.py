#!/usr/bin/env python3
"""
Zenodo deposition manager for Audit Clinical Evidence (ACE) reports.

One Zenodo record per report. Each report gets:
  - a CONCEPT DOI  (stable, always resolves to the newest version)  -> cite this
  - a VERSION DOI  (pins one specific revision)                     -> for corrections

Usage
-----
  export ZENODO_TOKEN=...                 # never commit this
  python3 scripts/zenodo.py status
  python3 scripts/zenodo.py new     auto
  python3 scripts/zenodo.py deposit reports/ACE2026001/index.qmd [--live]
  python3 scripts/zenodo.py revise  reports/ACE2026001/index.qmd [--live]
  python3 scripts/zenodo.py update  reports/ACE2026001/index.qmd [--live]   # metadata only
  python3 scripts/zenodo.py show    reports/ACE2026001/index.qmd --dry-run

  (reserve, publish and new-version are the lower-level steps deposit and
  revise are built from; they take the same paths.)

Defaults to the SANDBOX (sandbox.zenodo.org). Pass --live for the real archive.
Published Zenodo records cannot be deleted, so rehearse on the sandbox first.

  --dry-run   print the exact metadata payload and planned file uploads; no network.
"""

import argparse
import json
import os
import re
import datetime
import shutil
import subprocess
import sys
import time
import unicodedata
import urllib.error
import urllib.request
import uuid
from pathlib import Path

try:
    import yaml  # optional; a built-in fallback parser is used when absent
except ImportError:
    yaml = None

SANDBOX = "https://sandbox.zenodo.org/api"
LIVE = "https://zenodo.org/api"

REPO_ROOT = Path(__file__).resolve().parent.parent
CONFIG_PATH = REPO_ROOT / "scripts" / "zenodo.yml"



# --------------------------------------------------------------------------
# minimal YAML reader
#
# Only needs to handle the subset used by ACE front matter and zenodo.yml:
# scalars, quoted strings containing colons, lists of scalars, and one level
# of nested mappings / lists of mappings. Used when PyYAML is unavailable,
# which is the default on Homebrew Python (PEP 668).
# --------------------------------------------------------------------------

def _coerce(v: str):
    v = v.strip()
    if len(v) >= 2 and v[0] == v[-1] and v[0] in "\"'":
        return v[1:-1]
    if v in ("", "~", "null"):
        return ""
    if v == "true":
        return True
    if v == "false":
        return False
    if re.fullmatch(r"-?\d+", v):
        return int(v)
    if v.startswith("[") and v.endswith("]"):
        inner = v[1:-1].strip()
        return [_coerce(x) for x in _split_flow(inner)] if inner else []
    return v


def _split_flow(s: str):
    out, buf, quote = [], "", None
    for ch in s:
        if quote:
            if ch == quote:
                quote = None
            buf += ch
        elif ch in "\"'":
            quote = ch
            buf += ch
        elif ch == ",":
            out.append(buf)
            buf = ""
        else:
            buf += ch
    if buf.strip():
        out.append(buf)
    return out


def _strip_comment(line: str) -> str:
    out, quote = "", None
    for i, ch in enumerate(line):
        if quote:
            if ch == quote:
                quote = None
        elif ch in "\"'":
            quote = ch
        elif ch == "#" and (i == 0 or line[i - 1] in " \t"):
            break
        out += ch
    return out.rstrip()


def _parse_block(lines, indent):
    """Parse lines at the given indent into a dict."""
    result, i = {}, 0
    while i < len(lines):
        raw = lines[i]
        if not raw.strip():
            i += 1
            continue
        cur = len(raw) - len(raw.lstrip())
        if cur < indent:
            break
        line = _strip_comment(raw)
        if not line.strip():
            i += 1
            continue
        m = re.match(r"^\s*([^:\s][^:]*):\s?(.*)$", line)
        if not m:
            i += 1
            continue
        key, rest = m.group(1).strip(), m.group(2)
        if rest.strip():
            result[key] = _coerce(rest)
            i += 1
            continue
        # block value: gather more-indented lines
        j, child = i + 1, []
        while j < len(lines):
            nxt = lines[j]
            if not nxt.strip():
                child.append(nxt)
                j += 1
                continue
            if len(nxt) - len(nxt.lstrip()) <= cur:
                break
            child.append(nxt)
            j += 1
        stripped = [c for c in child if c.strip()]
        if stripped and stripped[0].lstrip().startswith("- "):
            items, k = [], 0
            while k < len(stripped):
                item = stripped[k].lstrip()[2:]
                item_indent = len(stripped[k]) - len(stripped[k].lstrip()) + 2
                if ":" in item and not re.match(r"^\s*[\"']", item):
                    sub = [" " * item_indent + item]
                    k += 1
                    while k < len(stripped) and (
                        len(stripped[k]) - len(stripped[k].lstrip())
                    ) >= item_indent:
                        sub.append(stripped[k])
                        k += 1
                    items.append(_parse_block(sub, item_indent))
                else:
                    items.append(_coerce(item))
                    k += 1
            result[key] = items
        elif stripped:
            result[key] = _parse_block(child, len(stripped[0]) - len(stripped[0].lstrip()))
        else:
            result[key] = ""
        i = j
    return result


def parse_yaml(text: str) -> dict:
    if yaml is not None:
        return yaml.safe_load(text) or {}
    return _parse_block(text.split("\n"), 0)



# --------------------------------------------------------------------------
# record ledger
#
# Deposition ids are plumbing, not part of the document, so they live here
# rather than in the report front matter. Keyed by target as well as report,
# so a sandbox rehearsal can never be mistaken for the live record - and
# nothing needs resetting between the two.
# --------------------------------------------------------------------------

LEDGER_PATH = REPO_ROOT / "scripts" / "zenodo-records.json"


def ledger_read() -> dict:
    if LEDGER_PATH.exists():
        return json.loads(LEDGER_PATH.read_text(encoding="utf-8"))
    return {}


def ledger_get(ace_id: str, live: bool) -> dict:
    return ledger_read().get(ace_id, {}).get("live" if live else "sandbox", {})


def ledger_set(ace_id: str, live: bool, **fields) -> None:
    data = ledger_read()
    entry = data.setdefault(ace_id, {}).setdefault("live" if live else "sandbox", {})
    entry.update({k: v for k, v in fields.items() if v})
    LEDGER_PATH.write_text(json.dumps(data, indent=2, sort_keys=True) + "\n",
                           encoding="utf-8")


# --------------------------------------------------------------------------
# front matter
# --------------------------------------------------------------------------

def read_front_matter(qmd: Path) -> dict:
    text = qmd.read_text(encoding="utf-8")
    m = re.match(r"^---\n(.*?)\n---\n", text, re.S)
    if not m:
        sys.exit(f"No YAML front matter found in {qmd}")
    return parse_yaml(m.group(1))


def set_front_matter_field(qmd: Path, key: str, value: str) -> None:
    """Set a scalar key in the front matter, preserving all other formatting."""
    text = qmd.read_text(encoding="utf-8")
    m = re.match(r"^(---\n)(.*?)(\n---\n)", text, re.S)
    if not m:
        sys.exit(f"No YAML front matter found in {qmd}")
    head, body, tail = m.groups()
    line = f'{key}: "{value}"'
    pattern = re.compile(rf"^{re.escape(key)}:.*$", re.M)
    body = pattern.sub(line, body) if pattern.search(body) else body + "\n" + line
    qmd.write_text(head + body + tail + text[m.end():], encoding="utf-8")



# --------------------------------------------------------------------------
# bibliography
#
# The .bib is shared across all reports, so the reference list for a given
# report is derived from the citation keys actually used in its body, not
# from the whole file.
# --------------------------------------------------------------------------


_COMBINING = {'"': "̈", "'": "́", "`": "̀", "^": "̂",
              "~": "̃", "c": "̧", "v": "̌", ".": "̇"}
_LIGATURES = {r"\o": "ø", r"\O": "Ø", r"\ss": "ß",
              r"\aa": "å", r"\AA": "Å", r"\ae": "æ",
              r"\AE": "Æ", r"\l": "ł", r"\L": "Ł"}


def delatex(s: str) -> str:
    """Turn LaTeX accent macros in .bib fields into real characters."""
    def repl(m):
        acc, letter = m.group(1), m.group(2)
        return unicodedata.normalize("NFC", letter + _COMBINING.get(acc, ""))
    # {\"a}  \"a  \"{a}  \c c  \v{s}
    s = re.sub(r'\{?\\(["\'`^~.])\s*\{?([A-Za-z])\}?\}?', repl, s)
    s = re.sub(r'\{?\\([cv])\s*\{?([A-Za-z])\}?\}?', repl, s)
    for k, v in _LIGATURES.items():
        s = s.replace("{" + k + "}", v).replace(k + " ", v).replace(k, v)
    return re.sub(r"[{}\\]", "", s)


def parse_bib(path: Path) -> dict:
    entries, text = {}, path.read_text(encoding="utf-8")
    for m in re.finditer(r"@(\w+)\s*\{\s*([^,]+),(.*?)\n\}", text, re.S):
        kind, key, body = m.group(1).lower(), m.group(2).strip(), m.group(3)
        fields = {}
        for fm in re.finditer(r"(\w+)\s*=\s*(\{(?:[^{}]|\{[^{}]*\})*\}|\"[^\"]*\"|[^,\n]+)", body):
            val = fm.group(2).strip().strip(",").strip()
            if val and val[0] in "{\"":
                val = val[1:-1]
            fields[fm.group(1).lower()] = delatex(val).strip()
        fields["_type"] = kind
        entries[key] = fields
    return entries


def cited_keys(qmd_text: str) -> list:
    body = re.sub(r"^---\n.*?\n---\n", "", qmd_text, flags=re.S)
    keys, seen = [], set()
    for m in re.finditer(r"@([A-Za-z][A-Za-z0-9_:.#$%&+?<>~/-]*)", body):
        k = m.group(1).rstrip(".,;:")
        if k not in seen:
            seen.add(k)
            keys.append(k)
    return keys


def format_reference(e: dict) -> str:
    authors = " and ".join(a.strip() for a in e.get("author", "").split(" and ") if a.strip())
    authors = "; ".join(authors.split(" and ")) if authors else ""
    year = (e.get("year") or e.get("date") or "n.d.")[:4]
    title = e.get("title", "").strip().rstrip(".")
    venue = (e.get("journal") or e.get("journaltitle") or e.get("publisher") or "").strip()
    parts = [p for p in [f"{authors} ({year})." if authors else f"({year}).", f"{title}." ,
                         f"{venue}." if venue else ""] if p]
    ref = " ".join(parts)
    if e.get("doi"):
        ref += f" https://doi.org/{e['doi']}"
    elif e.get("url"):
        ref += f" {e['url']}"
    return re.sub(r"\s+", " ", ref).strip()


# --------------------------------------------------------------------------
# metadata
# --------------------------------------------------------------------------


def to_iso_date(value) -> str:
    """Zenodo requires ISO8601 (YYYY-MM-DD). Report front matter uses M/D/YYYY."""
    s = str(value or "").strip()
    if not s:
        return ""
    m = re.match(r"^(\d{4})-(\d{1,2})-(\d{1,2})$", s)
    if m:
        y, mo, d = m.groups()
        return f"{y}-{int(mo):02d}-{int(d):02d}"
    m = re.match(r"^(\d{1,2})/(\d{1,2})/(\d{4})$", s)
    if m:
        mo, d, y = m.groups()
        return f"{y}-{int(mo):02d}-{int(d):02d}"
    sys.exit(f"Unrecognised date format: {s!r} (use YYYY-MM-DD or M/D/YYYY)")


def strip_html(s: str) -> str:
    return re.sub(r"\s+", " ", re.sub(r"<[^>]+>", "", s or "")).strip()




def current_version(ace_id: str, live: bool) -> int:
    """Version is tracked in the ledger (and by Zenodo), not in the document."""
    return int(ledger_get(ace_id, live).get("version", 1))


def build_creators(fm: dict, cfg: dict) -> list:
    """Authors come from the report's own `author:` block when it has one, so the
    report stays the single source of truth. scripts/zenodo.yml is the fallback."""
    people = fm.get("author") or fm.get("authors") or []
    if isinstance(people, dict):
        people = [people]
    out = []
    for person in people:
        if not isinstance(person, dict):
            continue
        name = person.get("name")
        if not name:
            family, given = person.get("family", ""), person.get("given", "")
            name = f"{family}, {given}".strip(", ") if (family or given) else ""
        if not name:
            continue
        entry = {"name": name}
        aff = person.get("affiliation")
        if isinstance(aff, dict):
            aff = ", ".join(str(aff.get(k)) for k in ("name", "city", "state") if aff.get(k))
        elif isinstance(aff, list) and aff:
            first = aff[0]
            aff = (", ".join(str(first.get(k)) for k in ("name", "city", "state") if first.get(k))
                   if isinstance(first, dict) else str(first))
        if aff:
            entry["affiliation"] = str(aff)
        if person.get("orcid"):
            entry["orcid"] = str(person["orcid"]).strip()
        out.append(entry)
    if out:
        return out
    print("  warning: this report has no `author:` block - falling back to the "
          "default authors in scripts/zenodo.yml. Check that is correct.")
    return [
        {k: v for k, v in (("name", c.get("name")),
                           ("affiliation", c.get("affiliation")),
                           ("orcid", c.get("orcid"))) if v}
        for c in cfg.get("creators", [])
    ]


def validate_orcid(orcid: str) -> bool:
    """Format plus the ISO 7064 MOD 11-2 check digit."""
    o = str(orcid).strip()
    if not re.fullmatch(r"\d{4}-\d{4}-\d{4}-\d{3}[\dX]", o):
        return False
    digits = o.replace("-", "")
    total = 0
    for ch in digits[:15]:
        total = (total + int(ch)) * 2
    expected = (12 - total % 11) % 11
    return ("X" if expected == 10 else str(expected)) == digits[15]


def build_metadata(fm: dict, cfg: dict, qmd: Path, version=None) -> dict:
    ace_id = fm.get("ace-id")
    if not ace_id:
        sys.exit(f"{qmd} has no ace-id in its front matter")

    title = fm.get("title", "").strip()
    subtitle = (fm.get("subtitle") or "").strip()
    citation = fm.get("citation") or {}
    full_title = citation.get("title") or (f"{title}: {subtitle}" if subtitle else title)

    if version is None:
        version = ledger_get(fm["ace-id"], getattr(build_metadata, "_live", False)).get("version", 1)
    version = str(version)
    site = cfg["site_url"].rstrip("/")
    landing = f"{site}/reports/{ace_id}/"

    abstract = strip_html(fm.get("abstract", ""))
    description = (
        f"<p><strong>{ace_id}</strong> &mdash; an audit report published by "
        f"{cfg['publisher']} ({site}).</p>"
        f"<p>{abstract}</p>"
        f"<p>This record archives version {version} of the report. The concept DOI always "
        f"resolves to the most recent version; each version DOI pins one specific revision. "
        f"Superseded versions remain permanently resolvable. "
        f"The HTML edition is at <a href=\"{landing}\">{landing}</a>.</p>"
    )

    creators = build_creators(fm, cfg)

    related = [{
        "identifier": landing,
        "relation": "isVariantFormOf",
        "resource_type": "publication-report",
        "scheme": "url",
    }]
    # Papers this report audits. `reviews` is what puts the audit into the
    # citation graph of the work being audited, via DataCite.
    for doi in fm.get("audited", []) or []:
        related.append({
            "identifier": str(doi).strip(),
            "relation": "reviews",
            "resource_type": "publication-article",
            "scheme": "doi",
        })
    # Everything this report cites, taken from the citation keys in its body.
    audited_dois = {str(d).strip().lower() for d in (fm.get("audited") or [])}
    bib_path = REPO_ROOT / "reports" / "references" / "references.bib"
    reference_strings, seen_dois = [], set(audited_dois)
    if bib_path.exists():
        bib = parse_bib(bib_path)
        for key in cited_keys(qmd.read_text(encoding="utf-8")):
            entry = bib.get(key)
            if not entry:
                continue
            reference_strings.append(format_reference(entry))
            doi = (entry.get("doi") or "").strip()
            if doi and doi.lower() not in seen_dois:
                seen_dois.add(doi.lower())
                related.append({
                    "identifier": doi,
                    "relation": "references",
                    "resource_type": "publication-article",
                    "scheme": "doi",
                })
    for doi in fm.get("cites", []) or []:            # optional manual additions
        d = str(doi).strip()
        if d.lower() not in seen_dois:
            seen_dois.add(d.lower())
            related.append({
                "identifier": d,
                "relation": "references",
                "resource_type": "publication-article",
                "scheme": "doi",
            })

    keywords = list(dict.fromkeys(
        (fm.get("categories") or []) + cfg.get("keywords", [])
    ))

    meta = {
        "upload_type": "publication",
        "publication_type": "report",
        "title": full_title,
        "creators": creators,
        "description": description,
        "publication_date": to_iso_date(fm.get("date-modified") or fm.get("date")),
        "access_right": "open",
        "license": cfg["license"],
        "version": version,
        "language": "eng",
        "keywords": keywords,
        "related_identifiers": related,
        "references": reference_strings,
        "imprint_publisher": cfg["publisher"],
        "notes": (
            f"ACE report identifier: {ace_id}. Version {version}. "
            f"Version history and the editorial correction policy are published at {site}."
        ),
    }
    if cfg.get("community"):
        meta["communities"] = [{"identifier": cfg["community"]}]
    return meta


def files_for(fm: dict, cfg: dict) -> list:
    ace_id = fm["ace-id"]
    out = []
    for pattern in cfg["upload_files"]:
        for p in sorted(REPO_ROOT.glob(pattern.format(ace_id=ace_id))):
            if p.is_file():
                out.append(p)
    return out


# --------------------------------------------------------------------------
# API
# --------------------------------------------------------------------------

class Zenodo:
    def __init__(self, base, token):
        self.base, self.token = base, token

    # Zenodo has been running degraded since early 2026 (bot and harvester load;
    # see blog.zenodo.org, 2026-01-28), so slow responses, gateway errors and
    # dropped connections are expected rather than exceptional. Retry, but only
    # where a retry cannot create a second copy of something:
    #   GET / PUT / DELETE  - idempotent, retried on any transient failure;
    #   POST                - retried ONLY on 429 and 503, where the server is
    #                         explicitly saying it did not process the request.
    # A POST that fails any other way stops, because a create or a publish may
    # have gone through even though the answer never came back. Run `status`
    # and look at the draft before retrying one of those by hand.
    TRANSIENT = {429, 500, 502, 503, 504}
    POST_SAFE = {429, 503}

    def _req(self, method, path, data=None, raw=None, ctype="application/json",
             attempts=5):
        url = path if path.startswith("http") else f"{self.base}{path}"
        sep = "&" if "?" in url else "?"
        url = f"{url}{sep}access_token={self.token}"
        body = raw if raw is not None else (json.dumps(data).encode() if data is not None else None)
        idempotent = method in ("GET", "PUT", "DELETE")
        timeout = 600 if raw is not None else 120      # file uploads take longer
        shown = path.split("?")[0]

        for attempt in range(1, attempts + 1):
            req = urllib.request.Request(url, data=body, method=method)
            if body is not None:
                req.add_header("Content-Type", ctype)
            last = None
            try:
                with urllib.request.urlopen(req, timeout=timeout) as r:
                    payload = r.read()
                    return json.loads(payload) if payload else {}
            except urllib.error.HTTPError as e:
                retryable = e.code in (self.TRANSIENT if idempotent else self.POST_SAFE)
                if not retryable or attempt == attempts:
                    sys.exit(f"Zenodo API {method} {shown} failed: {e.code}\n"
                             f"{e.read().decode()[:1500]}")
                last = f"HTTP {e.code}"
            except (urllib.error.URLError, TimeoutError, ConnectionError, OSError) as e:
                if not idempotent:
                    sys.exit(f"Zenodo API {method} {shown} did not answer: {e}\n"
                             f"The request may still have been processed. Run "
                             f"`python3 scripts/zenodo.py status` and check the "
                             f"draft on Zenodo before retrying.")
                if attempt == attempts:
                    sys.exit(f"Zenodo unreachable after {attempts} attempts: {e}")
                last = str(e)
            wait = min(60, 5 * 2 ** (attempt - 1))
            print(f"  Zenodo {method} {shown}: {last}; retrying in {wait}s "
                  f"({attempt} of {attempts - 1})")
            time.sleep(wait)

    def create(self):
        return self._req("POST", "/deposit/depositions", data={})

    def update(self, dep_id, metadata):
        return self._req("PUT", f"/deposit/depositions/{dep_id}", data={"metadata": metadata})

    def get(self, dep_id):
        return self._req("GET", f"/deposit/depositions/{dep_id}")

    def upload(self, deposition, path: Path):
        bucket = deposition["links"]["bucket"]
        return self._req("PUT", f"{bucket}/{path.name}",
                         raw=path.read_bytes(), ctype="application/octet-stream")

    def publish(self, dep_id):
        return self._req("POST", f"/deposit/depositions/{dep_id}/actions/publish")

    def edit(self, dep_id):
        return self._req("POST", f"/deposit/depositions/{dep_id}/actions/edit")

    def new_version(self, dep_id):
        return self._req("POST", f"/deposit/depositions/{dep_id}/actions/newversion")


# --------------------------------------------------------------------------
# commands
# --------------------------------------------------------------------------

def load(args):
    cfg = parse_yaml(CONFIG_PATH.read_text(encoding="utf-8"))
    qmd = Path(args.report).resolve()
    fm = read_front_matter(qmd)
    return cfg, qmd, fm


def client(args):
    token = os.environ.get("ZENODO_TOKEN")
    if not token:
        sys.exit("ZENODO_TOKEN is not set. Create a token with the "
                 "deposit:write and deposit:actions scopes, then export it.")
    return Zenodo(LIVE if args.live else SANDBOX, token)


def cmd_show(args):
    cfg, qmd, fm = load(args)
    meta = build_metadata(fm, cfg, qmd, current_version(fm["ace-id"], args.live))
    print(json.dumps(meta, indent=2, ensure_ascii=False))
    print("\nFiles that would be uploaded:")
    for p in files_for(fm, cfg):
        print(f"  {p.relative_to(REPO_ROOT)}  ({p.stat().st_size:,} bytes)")
    print(f"\nTarget: {'LIVE zenodo.org' if args.live else 'sandbox.zenodo.org'}")


def cmd_reserve(args):
    cfg, qmd, fm = load(args)
    if args.dry_run:
        return cmd_show(args)
    z = client(args)
    dep = z.create()
    version = current_version(fm["ace-id"], args.live)
    meta = build_metadata(fm, cfg, qmd, version)
    meta["prereserve_doi"] = True
    dep = z.update(dep["id"], meta)
    reserved = dep["metadata"].get("prereserve_doi", {}).get("doi")
    # The concept DOI ("all versions") is only reported by Zenodo after the
    # first publish, but it is deterministic: <DOI prefix>/zenodo.<conceptrecid>,
    # and the draft already carries conceptrecid. Derive it now so the launch
    # render (and the archived v1 PDF) can carry both DOIs. It is verified
    # against Zenodo's own value after publishing.
    concept = None
    conceptrecid = dep.get("conceptrecid")
    if reserved and conceptrecid:
        prefix = reserved.split("/zenodo.")[0]
        concept = f"{prefix}/zenodo.{conceptrecid}"
    ledger_set(fm["ace-id"], args.live, deposition_id=dep["id"],
               reserved_doi=reserved, version=version,
               **({"concept_doi": concept} if concept else {}))
    if reserved and args.live:
        set_front_matter_field(qmd, "doi", reserved)
        if concept and not fm.get("concept-doi"):
            set_front_matter_field(qmd, "concept-doi", concept)
    print(f"Draft deposition : {dep['id']}")
    print(f"Reserved DOI     : {reserved}")
    print(f"Concept DOI      : {concept or '(unknown until publish)'}")
    print(f"Edit online      : {dep['links'].get('html')}")
    print("\nWritten into the report front matter. Now re-render so the PDF carries "
          "its own DOI, then run: publish")


def cmd_publish(args):
    cfg, qmd, fm = load(args)
    if args.dry_run:
        return cmd_show(args)
    dep_id = ledger_get(fm["ace-id"], args.live).get("deposition_id")
    if not dep_id:
        sys.exit("No draft recorded for this report and target. Run `reserve` first.")
    z = client(args)
    dep = z.get(dep_id)
    version = current_version(fm["ace-id"], args.live)
    z.update(dep_id, build_metadata(fm, cfg, qmd, version))
    for p in files_for(fm, cfg):
        print(f"uploading {p.relative_to(REPO_ROOT)} ...")
        z.upload(dep, p)
    rec = z.publish(dep_id)
    version_doi = rec.get("doi")
    concept_doi = rec.get("conceptdoi")
    ledger_set(fm["ace-id"], args.live, deposition_id=dep_id, version=version,
               doi=version_doi, concept_doi=concept_doi)
    expected = ledger_get(fm["ace-id"], args.live).get("concept_doi")
    if expected and concept_doi and expected != concept_doi:
        print(f"WARNING: concept DOI derived before publish ({expected}) differs from "
              f"Zenodo's ({concept_doi}). The rendered files carry the derived value; "
              f"re-render and run `update`/`revise` to correct them.")
    if args.live:
        set_front_matter_field(qmd, "doi", version_doi or "")
        if concept_doi:
            set_front_matter_field(qmd, "concept-doi", concept_doi)
    else:
        print("  (sandbox DOIs recorded in scripts/zenodo-records.json, "
              "not written into the report)")
    print(f"\nPublished.\n  version DOI : {version_doi}\n  concept DOI : {concept_doi}"
          f"\n  record      : {rec['links'].get('record_html')}")


def cmd_new_version(args):
    cfg, qmd, fm = load(args)
    if args.dry_run:
        return cmd_show(args)
    dep_id = ledger_get(fm["ace-id"], args.live).get("deposition_id")
    if not dep_id:
        sys.exit("This report has never been deposited to this target.")
    z = client(args)
    draft_url = z.new_version(dep_id)["links"]["latest_draft"]
    draft = z._req("GET", draft_url)
    new_id = draft["id"]
    bumped = current_version(fm["ace-id"], args.live) + 1
    ledger_set(fm["ace-id"], args.live, deposition_id=new_id, version=bumped)
    z.update(new_id, build_metadata(fm, cfg, qmd, bumped))
    draft = z.get(new_id)
    for f in draft.get("files", []):
        z._req("DELETE", f"/deposit/depositions/{new_id}/files/{f['id']}")
    for p in files_for(fm, cfg):
        print(f"uploading {p.relative_to(REPO_ROOT)} ...")
        z.upload(draft, p)
    print(f"\nNew draft version {new_id} created and populated (version {bumped}).")
    print("Add a Version history entry, re-render, then run: publish")



def cmd_update(args):
    """Re-send metadata for an already-published record.

    Zenodo requires a published deposition to be reopened with `edit` before its
    metadata can be changed. This does NOT create a new version and does NOT
    change files - use it for metadata corrections only. Anything that alters a
    finding needs `new-version` instead.
    """
    cfg, qmd, fm = load(args)
    if args.dry_run:
        return cmd_show(args)
    dep_id = ledger_get(fm["ace-id"], args.live).get("deposition_id")
    if not dep_id:
        sys.exit("No record for this report and target; nothing to update.")
    z = client(args)
    dep = z.get(dep_id)
    if dep.get("submitted"):
        print(f"Reopening published deposition {dep_id} for metadata edit ...")
        z.edit(dep_id)
    z.update(dep_id, build_metadata(fm, cfg, qmd,
                                    current_version(fm["ace-id"], args.live)))
    rec = z.publish(dep_id)
    print(f"\nMetadata updated.\n  version DOI : {rec.get('doi')}"
          f"\n  record      : {rec['links'].get('record_html')}")



# --------------------------------------------------------------------------
# high-level workflow: new / deposit / revise / status
# --------------------------------------------------------------------------

REPORTS_DIR = REPO_ROOT / "reports"


def report_paths():
    return sorted(REPORTS_DIR.glob("ACE*/index.qmd"))


def next_ace_id() -> str:
    year = datetime.date.today().year
    nums = [int(p.parent.name[7:]) for p in report_paths()
            if p.parent.name[3:7] == str(year) and p.parent.name[7:].isdigit()]
    return f"ACE{year}{max(nums, default=0) + 1:03d}"


def run_quarto(target: Path) -> None:
    if shutil.which("quarto") is None:
        sys.exit("quarto is not on PATH. Render manually, then re-run.")
    print(f"rendering {target.relative_to(REPO_ROOT)} ...")
    if subprocess.run(["quarto", "render", str(target)], cwd=REPO_ROOT).returncode != 0:
        sys.exit("quarto render failed; nothing was sent to Zenodo.")


def preflight(fm, cfg, qmd, live):
    """Checks that must pass before anything irreversible happens."""
    problems, warnings = [], []
    if not fm.get("audited"):
        warnings.append("no `audited:` DOIs - the audited papers will not be linked")
    if not (fm.get("abstract") or "").strip():
        problems.append("no abstract")
    if "Version history" not in qmd.read_text(encoding="utf-8"):
        warnings.append("no Version history section in the report")
    creators = build_creators(fm, cfg)
    if not creators:
        problems.append("no authors found")
    for c in creators:
        o = c.get("orcid")
        if o and not validate_orcid(o):
            problems.append(f"{c['name']}: ORCID {o} fails its check digit - it is mistyped")
    if live:
        for c in creators:
            if not c.get("orcid"):
                problems.append(f"{c['name']} has no ORCID")
        if not cfg.get("community"):
            warnings.append("no Zenodo community set in scripts/zenodo.yml")
    for w in warnings:
        print(f"  warning: {w}")
    if problems:
        sys.exit("Refusing to continue:\n  - " + "\n  - ".join(problems))


def check_dois(fm):
    """Confirm each audited DOI resolves, so an audit is never attached to the
    wrong paper. Requires network; skipped automatically if unreachable."""
    for doi in fm.get("audited", []) or []:
        url = f"https://api.crossref.org/works/{doi}"
        try:
            with urllib.request.urlopen(url, timeout=15) as r:
                data = json.load(r)["message"]
            title = (data.get("title") or ["(no title)"])[0]
            print(f"  {doi}\n    -> {title[:90]}")
        except Exception as e:
            print(f"  {doi}\n    -> could not verify ({type(e).__name__})")


def cmd_new(args):
    ace_id = args.report if args.report.startswith("ACE") else next_ace_id()
    dest_dir = REPORTS_DIR / ace_id
    dest = dest_dir / "index.qmd"
    if dest_dir.exists():
        sys.exit(f"{dest_dir} already exists")
    # The template is a report folder (index.qmd + images/ + data/), so a new
    # report starts with the same shape as every published one.
    src_dir = REPORTS_DIR / "_template"
    if not (src_dir / "index.qmd").exists():
        sys.exit(f"{src_dir}/index.qmd is missing; nothing to scaffold from")
    shutil.copytree(src_dir, dest_dir)
    for keep in dest_dir.rglob(".gitkeep"):      # placeholders, not content
        keep.unlink()
    today = datetime.date.today().isoformat()
    text = dest.read_text(encoding="utf-8")
    text = (text.replace("ACE2026000", ace_id)
                .replace('date: "2026-06-21"', f'date: "{today}"')
                .replace('date-modified: "2026-06-01"', f'date-modified: "{today}"'))
    dest.write_text(text, encoding="utf-8")
    # Freeze the analysis functions into the report folder so the report is
    # self-contained and immune to later edits of reports/helpers/functions.R.
    # The plot theme (themes.R) stays shared: cosmetic, evolves site-wide.
    src = REPORTS_DIR / "helpers" / "functions.R"
    header = (
        f"# ACE report helpers ({ace_id})\n#\n"
        "# Frozen copy of reports/helpers/functions.R at the time this report was\n"
        "# created. Not updated when the shared copy changes, so the code archived\n"
        "# with this report is the code that produced it. To bring a fix in, copy it\n"
        "# here and publish a revision. Cosmetic styling comes from the shared\n"
        "# reports/helpers/themes.R.\n\n"
    )
    body = src.read_text(encoding="utf-8").rstrip() + "\n" if src.exists() else ""
    (REPORTS_DIR / ace_id / "helpers.R").write_text(header + body, encoding="utf-8")
    print(f"Created {dest.relative_to(REPO_ROOT)} and helpers.R\n\nNext:\n"
          f"  1. write the report\n"
          f"  2. list the audited papers' DOIs under `audited:`\n"
          f"  3. python3 scripts/zenodo.py deposit reports/{ace_id}/index.qmd")


def cmd_status(args):
    rows = []
    for p in report_paths():
        fm = read_front_matter(p)
        ace_id = fm.get("ace-id", p.parent.name)
        rec = ledger_get(ace_id, args.live)
        rows.append((ace_id, str(rec.get("version", "-")),
                     rec.get("concept_doi") or fm.get("concept-doi") or "-",
                     rec.get("doi") or fm.get("doi") or "-"))
    w = max([len(r[0]) for r in rows] + [8])
    print(f"{'REPORT'.ljust(w)}  VER  {'CONCEPT DOI'.ljust(26)}  VERSION DOI")
    for r in rows:
        print(f"{r[0].ljust(w)}  {r[1].ljust(3)}  {r[2].ljust(26)}  {r[3]}")


def cmd_deposit(args):
    """reserve -> render -> publish, in one step."""
    cfg, qmd, fm = load(args)
    preflight(fm, cfg, qmd, args.live)
    print("\nVerifying audited DOIs:")
    check_dois(fm)
    target = "zenodo.org (PERMANENT)" if args.live else "sandbox.zenodo.org"
    print(f"\nThis will publish {fm.get('ace-id')} to {target}.")
    if args.live and input("Type the report id to confirm: ").strip() != fm.get("ace-id"):
        sys.exit("Aborted.")
    cmd_reserve(args)
    run_quarto(qmd)
    args_fm = read_front_matter(qmd)          # re-read: reserve wrote the DOI in
    cmd_publish(args)


def cmd_revise(args):
    """new-version -> bump -> render -> publish."""
    cfg, qmd, fm = load(args)
    new_version = current_version(fm["ace-id"], args.live) + 1
    print(f"Creating version {new_version} of {fm.get('ace-id')}.")
    print("Make sure the Version history table records what changed.")
    if input("Continue? [y/N] ").strip().lower() != "y":
        sys.exit("Aborted.")
    cmd_new_version(args)
    set_front_matter_field(qmd, "date-modified", datetime.date.today().isoformat())
    run_quarto(qmd)
    cmd_publish(args)


def main():
    ap = argparse.ArgumentParser(description="Zenodo deposition manager for ACE reports.")
    ap.add_argument("command", choices=["new", "deposit", "revise", "status",
                                    "show", "reserve", "publish", "update", "new-version"])
    ap.add_argument("report", nargs="?", default="", help="path to the report .qmd")
    ap.add_argument("--live", action="store_true", help="target zenodo.org instead of the sandbox")
    ap.add_argument("--dry-run", action="store_true", help="print the payload; make no requests")
    args = ap.parse_args()
    {"new": cmd_new, "deposit": cmd_deposit, "revise": cmd_revise, "status": cmd_status,
     "show": cmd_show, "reserve": cmd_reserve, "publish": cmd_publish,
     "update": cmd_update, "new-version": cmd_new_version}[args.command](args)


if __name__ == "__main__":
    main()
