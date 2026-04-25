---
name: ingest-evidence
description: Ingest penetration-testing evidence from pasted tool output, file paths, screenshots, binaries, command output, logs, or mixed input into the engagement evidence store. Use when the operator asks to ingest, save, file, capture, preserve, or cross-reference evidence, including explicit `/ingest-evidence` use or implicit evidence handoff from tools such as Nessus, Burp, nmap, curl, jq, scanners, logs, or API responses. The skill preserves raw evidence under `raw/`, derives terse machine-readable `parsed/` extracts when useful, updates the manifest, reconciles findings and planning notes, and proposes read-only-safe next steps.
---

# Ingest Evidence

Ingest new penetration-testing evidence into the engagement workspace, preserve the raw artifact, derive compact machine-readable parsed artifacts when useful, and update the current test state.

Respect all project instructions first, especially engagement scope and read-only constraints.

## Core Rules

- Preserve raw evidence exactly. Do not redact, normalize, summarize, or rewrite raw evidence.
- Copy referenced evidence files into `raw/`. Do not leave manifest entries that only point to original files because originals may be deleted.
- Store derived, token-efficient artifacts in `parsed/` when they will reduce future context usage.
- Use descriptive filenames only. Do not use timestamps, numeric evidence IDs, or opaque IDs in filenames.
- Avoid duplicates. If identical evidence already exists, skip creating a duplicate and reuse the existing raw artifact.
- If a filename, command output, source, or artifact appears to represent the same evidence but the content differs, stop and flag the conflict to the operator instead of inventing a suffix.
- Update the manifest and relevant markdown state files directly.
- Treat target-side state-changing actions as forbidden unless the engagement notes clearly allow them.
- Use project-local `tmp/` for intermediate files.
- Run shell scripts through `shellcheck` unless there is a strong reason not to.

## Workspace Discovery

Start from the current working directory and identify the engagement root.

Use the current directory as the root if it contains engagement files such as `raw/`, `parsed/`, `findings/`, `plan.md`, `scope.md`, `todo.md`, `decisions.md`, component notes, or other relevant `*.md` files.

If the root is unclear, look around briefly, including one level up and obvious sibling directories. If still unclear, ask the operator before creating directories or files.

Create these directories automatically if missing once the engagement root is identified:

- `raw/`
- `parsed/`
- `findings/`
- `tmp/`

## Raw Evidence Handling

For pasted evidence:

- Save the exact pasted content into `raw/`.
- Infer the extension from content when obvious:
  - JSON beginning with `{` or `[`: `.json`
  - YAML: `.yaml`
  - XML beginning with `<?xml` or XML-like structure: `.xml`
  - HTML beginning with `<html`, `<!doctype html`, or similar: `.html`
  - HTTP request/response transcript: `.http`
  - CSV/TSV: `.csv` or `.tsv`
  - Plain command output or logs: `.txt`
- Choose a descriptive filename based on the source, target, tool, command, or operator-provided context.

For referenced files:

- Copy the file bytes into `raw/`.
- Preserve the original extension.
- Use the original filename if it is descriptive and unambiguous.
- Rename to a clearer descriptive filename if the original name is generic, such as `output.json`, `results.txt`, `dump.log`, `export.csv`, or `response.txt`.

For screenshots, pcaps, archives, and other binary evidence:

- Copy the file into `raw/` unchanged.
- Record the content type as `image`, `pcap`, `archive`, `binary`, or another specific type when obvious.
- Usually do not create a parsed artifact unless metadata, OCR text, packet summaries, archive listings, or extracted structured contents would be useful later.

For mixed input:

- If the operator provides multiple clearly separate artifacts, save them as separate raw files.
- If boundaries are ambiguous, save one raw transcript and derive parsed files for the separable facts.

Raw filename examples:

- `nessus-export-prod-web-tier.csv`
- `burp-login-response-admin-portal-bypass-attempt.http`
- `nmap-tcp-syn-scan-10.0.0.0-24-top1000.xml`
- `curl-admin-api-users-response.json`
- `screenshot-stored-xss-comments-page.png`
- `tableau-site-permissions-export.json`

Before writing a raw file:

1. Compute the SHA-256 hash of the incoming evidence.
2. Check the manifest and existing files in `raw/` for the same hash.
3. If an identical raw artifact exists, do not write a duplicate. Reuse the existing raw artifact and mention the reuse in the final summary when relevant.
4. If the intended filename exists with different content, stop and ask the operator how to proceed.
5. If another filename appears to represent the same command, tool output, source, or artifact but has different content, flag the ambiguity before saving.

## Manifest

Maintain `evidence-manifest.json` at the engagement root.

Use JSON because it is easy for agents and tools such as `jq` to query. Keep it machine-oriented rather than prose-oriented.

Use raw and parsed paths as stable identifiers. Do not create separate opaque IDs. Evidence identity is path plus hash. `ingested_at` is metadata only, not an ID.

Suggested structure:

```json
{
  "schema": "ingest-evidence.v1",
  "raw": {
    "raw/descriptive-evidence-name.json": {
      "sha256": "hex",
      "ingested_at": "ISO-8601 UTC timestamp",
      "source": {
        "kind": "pasted-text | copied-file | mixed-input | screenshot | binary",
        "original_path": "path if copied from a file, otherwise null",
        "description": "short source description"
      },
      "content_type": "json | yaml | xml | html | http | csv | text | image | pcap | archive | binary | other",
      "targets": [
        "host, asset, URL, tenant, application, or component"
      ],
      "tags": [
        "freeform agent-queryable labels"
      ],
      "parsed": [
        "parsed/descriptive-evidence-name.relevant-slice.json"
      ],
      "related_findings": [
        "findings/2-example-finding.md"
      ],
      "notes": "short agent-facing note if useful"
    }
  },
  "parsed": {
    "parsed/descriptive-evidence-name.relevant-slice.json": {
      "derived_from": [
        "raw/descriptive-evidence-name.json"
      ],
      "purpose": "what future question this artifact answers",
      "method": "jq/python/tool/manual extraction description",
      "content_type": "json | csv | tsv | txt | xml | other",
      "targets": [
        "host, asset, URL, tenant, application, or component"
      ],
      "tags": [
        "freeform agent-queryable labels"
      ],
      "related_findings": [
        "findings/2-example-finding.md"
      ]
    }
  }
}
```

When updating the manifest, keep paths relative to the engagement root.

If the manifest is missing, create it. If it exists but uses an older compatible shape, preserve existing data and migrate only as much as needed for the new entry.

## Parsed Evidence

Create parsed artifacts when raw evidence is large, noisy, repetitive, or expensive to load in future context, and when smaller derived files would answer likely future questions.

`parsed/` is a cache of queryable subsets, not a human summary.

Prefer terse machine-readable formats:

- Use `.json` for structured subsets, normalized records, permission maps, account lists, configuration summaries, API responses, and scanner subsets.
- Use `.csv` or `.tsv` for flat tables.
- Use `.txt` for concise grep-like extracts, command snippets, unique identifiers, or short relevant log excerpts.
- Use `.xml` when retaining XML structure is more useful than converting.
- Avoid markdown for parsed artifacts unless the source itself is markdown or the parsed artifact is inherently prose.

Name parsed files with the originating raw basename plus a slice name:

```text
parsed/<raw-basename>.<slice-name>.<ext>
```

Examples:

- `parsed/nessus-export-prod-web-tier.high-and-critical-only.csv`
- `parsed/nessus-export-prod-web-tier.unique-cves.txt`
- `parsed/curl-admin-api-users-response.admin-users.json`
- `parsed/tableau-site-permissions-export.project-permissions.json`

Good parsed artifacts extract security-relevant facts, not prose summaries. Examples:

- Users, groups, roles, privileges, and effective permissions.
- Authentication and authorization configuration.
- Exposed services, listeners, routes, hosts, and trust boundaries.
- Security headers, TLS settings, cookie flags, CORS policy, CSP, and session controls.
- Vulnerability scanner findings filtered to relevant severities or affected assets.
- Interesting log lines with surrounding context trimmed to the minimum useful amount.
- API schemas, endpoints, methods, parameter names, and authorization hints.
- Misconfiguration candidates and evidence needed to confirm or refute them.
- Unique CVEs, affected hosts, package versions, or vulnerable components.

Do not create parsed artifacts just because a file is large. Create them when they avoid repeatedly loading the raw artifact or when they separate distinct evidence units that will be queried later.

If later analysis reveals that a missing parsed artifact would be useful, create it then and update the manifest.

Use appropriate tools for extraction, such as `jq`, `python`, `awk`, `sed`, `xmlstarlet`, `xq`, `csvkit`, or purpose-built CLIs. If writing shell scripts for extraction, run `shellcheck` unless there is a strong reason not to.

Record the extraction method in the manifest. If the exact command is long, record enough detail for a future agent to understand how the parsed artifact was produced.

## Cross-Reference Current Test State

After storing evidence, cross-reference it against the current state of the test.

Inspect relevant markdown files in the engagement root and `findings/`. Consider files whose names or contents suggest planning, scope, current state, findings, notes, decisions, tasks, assumptions, or component-specific status.

Always inspect `findings/*.md` when findings exist because findings are canonical and high-signal. Inspect root `*.md` files that appear relevant. Do not exhaustively read unrelated documentation unless it is needed for the current evidence.

Use both the current chat context and repository markdown state.

Update relevant markdown files directly so a future session can continue without reconstructing context. Typical updates include:

- Add newly confirmed facts to component notes or state files.
- Move answered questions out of open-question sections.
- Add new open questions created by the evidence.
- Update task lists, plan status, and next steps.
- Record scope, assumptions, and authorization constraints when clarified.
- Update or close potential findings affected by the evidence.
- Create new potential findings when evidence opens a plausible attack path.

Do not write accomplishment narratives. State files should describe the engagement state, not what the agent did.

Before finishing ingestion, review every finding that may have been affected by the new evidence. Look for findings that reference the same assets, services, users, roles, technologies, controls, open questions, or evidence gaps. For each affected finding, decide whether the evidence:

- Answers something the finding was waiting on.
- Confirms, weakens, refutes, or changes the severity of an existing finding.
- Requires evidence links, status notes, waiting-for sections, impact, likelihood, or remediation details to be updated.
- Creates a new tentative or confirmed finding.
- Opens a new edge, such as a newly discovered service, trust boundary, identity path, exposed route, configuration surface, or follow-up question.
- Closes an existing edge by answering or disproving it.

Update findings and planning notes directly when the answer is clear. If an edge remains uncertain, record it as an open question or next step instead of burying it in the final response only.

## Findings

Use `findings/` as the canonical findings directory.

Name finding files as:

```text
findings/<severity-number>-<descriptive-name>.md
```

Severity numbers:

- `0`: informational
- `1`: low
- `2`: medium
- `3`: high
- `4`: critical

For tentative findings, pick the most likely severity and explain the uncertainty near the top of the file. Rename later if severity changes.

Use this lifecycle:

- `potential`
- `needs evidence`
- `confirmed`
- `closed/refuted`

Each finding should include status details near the top, such as:

```markdown
Status: potential
Severity: medium (tentative)
Evidence:
- raw/example.json
- parsed/example.permissions.json
Waiting for:
- Specific evidence needed to confirm or refute the issue
```

When new evidence affects a finding:

- If it confirms a tentative finding, update status and evidence links.
- If it refutes a finding, mark it `closed/refuted`; do not delete it.
- If it changes severity, update the filename and explain why in the status notes.
- If it opens a new attack path, create or update the relevant finding.
- If it answers an open question on a finding, update the status block or relevant section.

Keep confirmed claims tied to evidence paths. Keep speculation clearly labelled as potential or open.

## Read-Only and State-Changing Action Discipline

Determine the engagement mode from the markdown state files when possible. Look for scope, rules of engagement, plan notes, README files, or explicit mode statements.

Relevant markdown files should encode whether the test is:

- Completely read-only.
- Read-only except for clearly allowed local evidence handling.
- Allowed to make specific target-side changes.
- Read-write with caveats.

If the mode is unclear, treat proposed target actions as read-only by default, record an open question in the appropriate state file, and ask the operator only if a next-step recommendation depends on knowing the mode.

If the engagement is read-only:

- Do not suggest target-side modifying commands.
- Do not suggest SQL, API calls, service commands, filesystem operations, or tooling actions that change target state.
- Prefer commands that only read state and print output.
- If temporary output files are proposed, clearly flag whether the write is local/operator-side or target-side.
- Prefer writing local artifacts into project `raw/`, `parsed/`, or `tmp/` instead of writing files on a target.

If a state-changing action appears necessary, do not bury it in a normal command list. Use a prominent warning and explain:

- What would change.
- Which system would be affected.
- Why read-only alternatives are insufficient.
- The likely blast radius and reversibility.
- What explicit approval is needed before proceeding.

Never run or recommend a target-side state-changing action as an ordinary next step. Flag every state-changing action every time, regardless of confidence.

## Final Operator Response

End with a concise summary that always includes:

1. A bullet-point list of `raw/` and `parsed/` files created or reused.
2. What the ingested evidence tells us.
3. Whether the evidence fully answered the intended question, partially answered it, or lacks the information that was being sought.
4. What changes the new evidence makes to findings, including potential or confirmed new findings and updates to previous findings.
5. What open edges the evidence created or closed.
6. Proposed next steps focused on the highest priorities, which may have changed because of the new evidence.

Avoid verbose detail that is already captured in files. Do not add closing pleasantries.
