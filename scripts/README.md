# Zenodo deposition workflow

Each ACE report is archived as its own Zenodo record. Zenodo issues two DOIs per
report:

- **concept DOI** — permanent, always resolves to the newest version. This is the
  DOI to cite and to give to journals.
- **version DOI** — pins one specific revision. Use this in correction notices and
  anywhere the exact published wording matters.

## One-time setup

1. Create a Zenodo account and a **sandbox** account (they are separate):
   https://zenodo.org and https://sandbox.zenodo.org
2. In each, go to Applications → Personal access tokens → New token, with the
   `deposit:write` and `deposit:actions` scopes.
3. Export the token in your shell. **Never commit it.**

   ```sh
   export ZENODO_TOKEN=...        # sandbox token while rehearsing
   ```

4. Fill in `scripts/zenodo.yml`: ORCIDs, and the community identifier once the
   ACE community exists.

No dependencies to install: the script uses only the Python standard library.
(If PyYAML happens to be present it will use it; if not, a built-in parser is used.)

## The four commands

```sh
python3 scripts/zenodo.py status                           # what exists, and its DOIs
python3 scripts/zenodo.py new auto                         # scaffold the next report
python3 scripts/zenodo.py deposit reports/ACE2026002.qmd   # first publication
python3 scripts/zenodo.py revise  reports/ACE2026001.qmd   # a new version of one already published
```

Everything targets the **sandbox** unless you add `--live`.

---

## Runbook: publishing a new report

Start to finish. Steps 4 and 8 are the ones with consequences.

1. **Scaffold it.**

   ```sh
   python3 scripts/zenodo.py new auto
   ```

   Creates the next `ACE<year><nnn>.qmd` with id, filenames, dates and the PDF
   button already filled in.

2. **Write the report** in that file.

3. **List the audited papers.** In the front matter, put the DOI of every paper
   the report audits under `audited:`. These become Zenodo `reviews` relations,
   which is what links the audit to the audited work in the DataCite graph. Get
   them right.

   ```yaml
   audited:
     - "10.1097/MD.0000000000015344"
   ```

   Everything the report cites is picked up automatically from the citation keys
   in the body plus `references/references.bib` - there is no second list to keep
   in sync.

4. **Rehearse on the sandbox.**

   ```sh
   export ZENODO_TOKEN=your_sandbox_token
   python3 scripts/zenodo.py deposit reports/ACE2026002.qmd
   ```

   This reserves the DOI, renders the report so the PDF carries it, uploads and
   publishes. **Read the DOI verification block it prints** - it resolves each
   audited DOI against Crossref and shows the title. A transposed digit would
   attach your audit to an innocent paper.

5. **Open the sandbox record** and check the authors, abstract, files, and that
   the audited papers appear under "Reviews".

6. **Reset the sandbox values** so the live deposit creates a fresh record:

   ```sh
   sed -i '' -e 's/^zenodo-id:.*/zenodo-id: ""/' -e 's/^doi:.*/doi: ""/' \
             -e 's/^concept-doi:.*/concept-doi: ""/' reports/ACE2026002.qmd
   ```

7. **Fill the Version history table** in the report: version 1, today's date,
   "Initial publication."

8. **Publish for real.**

   ```sh
   export ZENODO_TOKEN=your_live_token
   python3 scripts/zenodo.py deposit reports/ACE2026002.qmd --live
   ```

   Irreversible. The script refuses if an author has no ORCID and makes you type
   the report id to confirm.

9. **Render the whole site** so the listing and citation block pick up the new
   DOI:

   ```sh
   quarto render
   ```

10. **Commit and push.**

    ```sh
    git add -A && git commit -m "Publish ACE2026002" && git push
    ```

---

## Runbook: updating a report that is already published

### First, pick the right command

| What changed | Command | Effect |
|---|---|---|
| Anything in the report text, figures, or PDF - **including typos** | `revise` | New version DOI. Concept DOI unchanged. |
| Only Zenodo metadata: keywords, an ORCID, a related identifier | `update` | Same DOI. No new version. |

The dividing line is not how important the change is - it is whether the
**files** change. Zenodo files are immutable once published, so any edit that
alters the PDF requires a new version, even a one-character fix.

### A. The report itself changed - use `revise`

1. **Edit the report.**

2. **Add a Version history row first.** Version number, date, and what changed.
   Do this before depositing, so the archived PDF documents its own revision.

   ```
   | 2 | 2026-09-14 | (version DOI) | Corrected the PHQ-9 SD for study 2; RIV count unchanged. |
   ```

3. **Deposit the new version.**

   ```sh
   export ZENODO_TOKEN=your_live_token
   python3 scripts/zenodo.py revise reports/ACE2026001.qmd --live
   ```

   Creates the new Zenodo version, bumps `version:`, sets `date-modified` to
   today, re-renders, uploads and publishes. The new version DOI is written back
   into the front matter.

4. **Paste the new version DOI** into the Version history row you added.

5. **Render the whole site and push.**

   ```sh
   quarto render
   git add -A && git commit -m "ACE2026001 v2: corrected PHQ-9 SD" && git push
   ```

   Use a commit message that says what changed. The git history of a site making
   misconduct findings is part of the record.

### B. Only the metadata changed - use `update`

```sh
python3 scripts/zenodo.py update reports/ACE2026001.qmd --live
```

Reopens the published record, re-sends the metadata, republishes under the same
DOI. Nothing about the report or the site changes, so there is nothing to render
or commit unless you also edited the front matter.

---

## Going live

`--live` is irreversible: published Zenodo records cannot be deleted, only
withdrawn by Zenodo staff. Rehearse every new report type on the sandbox first.

Before the first live deposit, `scripts/zenodo.yml` needs ORCIDs for both authors
and the Zenodo community identifier. The script blocks a live run without ORCIDs.

## Where state lives

The report front matter carries only what belongs in the document: title,
authors, dates, abstract, categories, `ace-id`, and the `audited:` DOIs.

Deposition ids and version numbers are plumbing and live in
`scripts/zenodo-records.json`, keyed by report and by target, so a sandbox
rehearsal is never confused with the live record and nothing needs resetting
between the two. Zenodo is the authority on version numbers.

Only a `--live` publish writes back into the document, and only the DOIs -
because those get printed in the PDF and cited by other people.

## Editorial policy this workflow assumes

- A change to any finding, RIV count, or recommendation creates a **new version**
  with a new version DOI and a dated Version history entry stating what changed.
- Typographical and formatting fixes also create a new version, because Zenodo
  files are immutable once published - but their Version history entry should say
  plainly that no finding changed.
- **Nothing published about a named researcher is ever silently altered.**
  Superseded versions stay permanently resolvable at their version DOIs.
