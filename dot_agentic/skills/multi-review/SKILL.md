---
name: multi-review
description: Run three independent reviewers in parallel (codex `/review`, claude `/custom-review`, claude `/custom-review2`) against the same target, save verbatim outputs to `tmp/multi-review/`, synthesize a merged best-of review, optionally apply the fixes, then write an A/B evaluation comparing the three reviewers on accuracy, signal-to-noise, and depth. The evaluation is the point — it powers iterative improvement of the review skills. Codex runs as a plain `/review` with only the target; non-target trailing text after `/multi-review` is forwarded verbatim to the two claude reviewers as additional focus.
---

# Multi Review

## Purpose

`/multi-review` runs three independent code reviews of the same target in parallel and synthesizes a merged best-of review. After applying the fixes, the skill writes an evaluation of the three reviewers so the user can A/B-test review skills and improve them over time.

Key difference from `/codex-review`: this skill is **invoked fresh** (not after a prior `/review`). The target must be determined from `/multi-review` arguments, not from earlier conversation context.

## Hard preconditions

Refuse with a clear, short message if any fail:

1. **Working directory is inside a git repository.** All three reviewers operate on a working tree.
2. **`codex` is on `PATH`.** Run `command -v codex`. If missing, tell the operator to install codex.
3. **The `custom-review` and `custom-review2` skills are available.** If either is missing from the available-skills list, refuse.
4. **`gh` is on `PATH` and authenticated** — *only* if the target is `pr`. Run `command -v gh` and `gh auth status`. If either fails, refuse with the missing piece.

## Step 1 — Parse args and determine target

Split `/multi-review`'s trailing text into:

- **Target hints** — phrases that explicitly identify what to review (see table below).
- **Focus text** — everything that doesn't match a target hint; forwarded verbatim to the two claude reviewers (custom-review and custom-review2) as additional focus. Codex is not given focus text — it runs as a plain `/review` with only the target flags.

Target heuristics (parse from args; default to uncommitted):

| Args contain | Target type | Notes |
|---|---|---|
| `PR #N`, `#N`, or a GitHub PR URL | `pr` | Extract `N`. |
| `against X` or `vs X` | `branch` | Current branch reviewed against base `X`. |
| A 7+ hex SHA | `commit` | Use as commit ref. |
| `uncommitted` or `working tree` | `uncommitted` | |
| Nothing target-like | `uncommitted` | Default. |

**Removed shorthands** (do not silently accept them):

- `branch X` — ambiguous between "review branch X" and "review current against X". Reject with a clear correction: "Did you mean `against X`?"
- `staged` — would silently include unstaged changes too. Reject with a correction: "use `uncommitted` (covers staged + unstaged + untracked) or commit your staged changes first."

If args are ambiguous (e.g., both a PR and a base named), ask one short multiple-choice question.

### PR preflight (target = `pr` only)

1. `gh pr view <N> --json headRefName,baseRefName,headRefOid` to fetch refs and OID.
2. `git rev-parse --abbrev-ref HEAD` → current branch. If it doesn't match `headRefName`, abort: "PR head branch is `<headRefName>` but you're on `<currentBranch>`. Run `gh pr checkout <N>` and re-invoke."
3. `git rev-parse HEAD` → current local OID. Compare to `headRefOid`:
   - **Equal** → proceed.
   - **Local ahead** (PR head is an ancestor of HEAD): abort with `git push` guidance — codex would review your local commits but `custom-review` resolves the GitHub PR head, so the three reviewers would see different code.
   - **Local behind** (HEAD is an ancestor of PR head): abort with `git fetch origin pull/<N>/head && git reset --hard FETCH_HEAD` guidance (or `gh pr checkout <N>`).
   - **Diverged**: abort with a "force-push or rebase to align" message; do not auto-resolve.
4. Reject dirty worktree for `pr` targets: if `git status --porcelain` is non-empty, abort with "commit, stash, or discard before /multi-review on a PR" (the reviewers operate on different snapshots, so worktree drift breaks comparability).

### Empty-diff preflight

Before spawning anything, verify the target has a non-empty diff:

| Target | Check |
|---|---|
| `pr` | `git diff <baseRefName>...<headRefName> --stat` non-empty (after the PR fetch in custom-review's lookup). For the preflight, `gh pr diff <N> --name-only` is enough. |
| `branch` | `git diff <X>...HEAD --name-only` non-empty. |
| `commit` | `git show --stat <sha>` shows file changes. |
| `uncommitted` | `git status --porcelain` non-empty. |

If empty, refuse: "Target `<phrase>` has no changes to review."

### Target strings (used downstream)

Build two distinct strings — do not collapse them:

- **Display phrase** (printed to the operator):
  - `pr` → `PR #<N>`
  - `branch` → `branch <currentBranch> against <X>`
  - `commit` → `commit <sha>`
  - `uncommitted` → `the uncommitted changes in the working tree`
- **Canonical reviewer arg** (passed verbatim to subagents invoking custom-review/custom-review2; their resolution tables parse this):
  - `pr` → `<N>`
  - `branch` → `against <X>`
  - `commit` → `<sha>`
  - `uncommitted` → `uncommitted`

Also record `<base branch>` (PR's `baseRefName` or the `X` from `against X`) for codex's `--base` flag.

## Step 2 — Derive slug and check for collision

Derive a slug from the target:

| Target | Slug |
|---|---|
| `pr` | `pr<N>` (e.g., `pr100`) |
| `branch` | `branch-<sanitized-name>-<hash>` where `<hash>` is the first 6 chars of `sha1sum` of the raw branch name. Sanitization: lowercase, non-alphanumeric → `-`. The hash disambiguates `feature/a` from `feature-a`. |
| `commit` | `commit-<short-sha>` (first 7 chars) |
| `uncommitted` | `uncommitted-<hash>` where `<hash>` is the first 6 chars of `sha1sum` of `git status --porcelain` + `git diff` output — disambiguates back-to-back runs on different working states |

Output paths (project-local `tmp/`):

- `tmp/multi-review/codex-<slug>.md`
- `tmp/multi-review/custom-review-<slug>.md`
- `tmp/multi-review/custom-review2-<slug>.md`
- `tmp/multi-review/merged-<slug>.md`
- `tmp/multi-review/evaluation-<slug>.md`

Plus per-reviewer status sidecars (see Step 3):

- `tmp/multi-review/codex-<slug>.status.json`
- `tmp/multi-review/custom-review-<slug>.status.json`
- `tmp/multi-review/custom-review2-<slug>.status.json`

**Collision check.** Before running anything, check if any of the seven files already exist. If yes: warn the operator listing which files exist, and ask via `AskUserQuestion` whether to overwrite. Exit on "no".

Then `mkdir -p tmp/multi-review/`.

## Step 3 — Spawn three reviewers in parallel

All three start in a **single message** with three tool calls so they run concurrently.

### Reviewer A — codex (background Bash)

Run a plain `codex review` with only the target flags — **no custom prompt, no AGENTS.md preamble, no focus text**. Codex sees the same invocation it would see from a bare `/review` against this target. Flags by target:

| Target | Flags |
|---|---|
| `pr` | `--base <baseRefName>` |
| `branch` | `--base <baseBranch>` |
| `commit` | `--commit <sha>` |
| `uncommitted` | `--uncommitted` |

Run codex with a single background Bash call (run_in_background: true, timeout 600000 ms):

```sh
flags=(<each flag and its value as a separate array element, e.g. "--base" "main">);
codex review "${flags[@]}" > tmp/multi-review/codex-<slug>.md 2> tmp/multi-review/codex-<slug>.stderr;
rc=$?;
printf '{"reviewer":"codex","exit":%d,"timed_out":false,"output":"tmp/multi-review/codex-<slug>.md"}\n' "$rc" > tmp/multi-review/codex-<slug>.status.json;
```

The trailing `;` per CLAUDE.md guards against the sandbox pipe-drop bug. Keep stderr separate so the output file stays parseable as a review.

**Empty-output guard.** After codex finishes, before treating its output as a review, the parent must check: if `exit != 0` or `stat -c %s tmp/multi-review/codex-<slug>.md` reports `0`, mark the status sidecar as `"ok": false` with a reason that includes the exit code and a pointer to the `.stderr` file. The codex CLI prints argument errors to stderr and exits without writing anything to stdout, so a silent zero-byte review file is the failure shape to defend against.

### Reviewer B — claude `/custom-review` (Agent tool, foreground)

Spawn a general-purpose Agent. Crucial constraint: `custom-review` **will not** write outside its own `tmp/custom-review-<timestamp>/review.md` (see custom-review/SKILL.md:16,20). Instructing the subagent to write elsewhere will either fail or violate the skill. So the parent collects the review path from the subagent and copies it after.

Sample prompt (fill in concrete values):

> You are running a code review as part of a multi-reviewer comparison. Do not infer the target from this prompt's framing — the target is given below.
>
> **Target (canonical arg for the custom-review skill):** `<canonical reviewer arg>`
> **Display phrase (for human reference only):** \<display phrase\>
> **Additional focus from operator:** \<focus text, or "(none)"\>
>
> Invoke the `custom-review` skill via the Skill tool, passing the canonical arg above as its target. If the operator provided additional focus text, forward it verbatim as part of the skill's invocation.
>
> Let the skill write to its standard `tmp/custom-review-<timestamp>/` directory — **do not** redirect or override that path. When the skill finishes, your reply to me must be exactly two lines:
>
> ```
> REVIEW_PATH=<absolute path to the review.md the skill wrote>
> FINDINGS=<integer count of distinct findings in that review>
> ```
>
> If the skill refuses or fails, reply with a single line: `FAILED: <one-sentence reason>`. Do not paraphrase or echo the review body in your reply.

### Reviewer C — claude `/custom-review2` (Agent tool, foreground)

Same as Reviewer B but invoking the `custom-review2` skill (not `custom-review`).

**Naming gotcha — read carefully.** The `custom-review2` skill writes its review into a directory named `tmp/custom-review-<timestamp>/` (note: same `custom-review-` prefix as the v1 skill — the `2` does *not* appear in its own output path). The two subagents therefore return `REVIEW_PATH=` values that look interchangeable. **Do not** identify which review is which by inspecting their source paths. Identify them solely by which subagent (B or C) returned the reply, and copy each to its correct destination:

- Reviewer B's reply → `tmp/multi-review/custom-review-<slug>.md`
- Reviewer C's reply → `tmp/multi-review/custom-review2-<slug>.md`  ← the `2` MUST be in this filename.

If you overwrite Reviewer C's output into `custom-review-<slug>.md`, downstream Step 4 (synthesis) and Step 8 (evaluation) will silently treat the v2 review as the v1 review, and the evaluation will compare the wrong skills.

### Why one Bash + two Agents in one message

All three are independent; issuing them in a single message starts them in parallel. Codex runs in background because its 10-min timeout is longer than the Agents typically take; the two Agents are foreground (their results return when complete). After this message, monitor for the background codex completion before proceeding.

## Step 3.5 — Collect outputs into the canonical paths

After all three reviewers finish, normalize their outputs so Step 4 can read predictable paths.

Process Reviewers B and C **separately**, by which subagent returned the reply — never by inspecting `REVIEW_PATH`, which uses the same `tmp/custom-review-<timestamp>/` prefix for both skills (see "Naming gotcha" under Reviewer C).

**Reviewer B (`custom-review`):**

1. Parse Reviewer B's reply for `REVIEW_PATH=<...>`. If parsing fails or the file does not exist, treat as failure.
2. On success: `Read` the source file, then `Write` its full contents to `tmp/multi-review/custom-review-<slug>.md` (no `2`). Use `Read` + `Write` rather than a shell `cp` so the file goes through normal write paths.
3. Write `tmp/multi-review/custom-review-<slug>.status.json`:
   ```json
   {"reviewer":"custom-review","ok":true,"source":"<REVIEW_PATH from B>","findings":<N>,"output":"tmp/multi-review/custom-review-<slug>.md"}
   ```
4. On failure: write a placeholder `tmp/multi-review/custom-review-<slug>.md` containing exactly `FAILED: <reason>` and a status sidecar with `"ok":false,"reason":"<reason>"`.

**Reviewer C (`custom-review2`):**

1. Parse Reviewer C's reply for `REVIEW_PATH=<...>`. If parsing fails or the file does not exist, treat as failure.
2. On success: `Read` the source file, then `Write` its full contents to `tmp/multi-review/custom-review2-<slug>.md` (the `2` MUST appear in this destination filename). Use `Read` + `Write` rather than a shell `cp`.
3. Write `tmp/multi-review/custom-review2-<slug>.status.json` (note the `2`):
   ```json
   {"reviewer":"custom-review2","ok":true,"source":"<REVIEW_PATH from C>","findings":<N>,"output":"tmp/multi-review/custom-review2-<slug>.md"}
   ```
4. On failure: write a placeholder `tmp/multi-review/custom-review2-<slug>.md` containing exactly `FAILED: <reason>` and a status sidecar `tmp/multi-review/custom-review2-<slug>.status.json` with `"ok":false,"reason":"<reason>"`.

**Post-write sanity check.** Before proceeding to Step 4, confirm that all of `tmp/multi-review/custom-review-<slug>.md`, `tmp/multi-review/custom-review2-<slug>.md`, and (if codex ran) `tmp/multi-review/codex-<slug>.md` exist as distinct files. If `custom-review2-<slug>.md` is missing, you forgot the `2` in a destination path above — find and rename before continuing.

For codex (Reviewer A): the status sidecar was already written by the bash command. If `exit != 0` or the output file is empty (`stat -c %s ... -eq 0`), update its status to `"ok":false` and leave the output file as-is (codex's own error messages are useful evidence).

**Abort condition.** If all three reviewers report failure, print the three reasons and stop before merging. Otherwise proceed — partial runs still produce a useful merged review and evaluation.

## Step 4 — Synthesize merged review

`Read` each of the three `tmp/multi-review/*-<slug>.md` outputs (skip any whose status sidecar is `"ok":false`). Produce **one** merged review and write it to `tmp/multi-review/merged-<slug>.md`.

Synthesis rules (same as `codex-review` Step 5):

1. **Findings flagged by 2+ reviewers** — keep, dedupe to one entry. Use the clearest wording. Note multi-reviewer agreement as `(consensus)` next to the heading — useful evidence for the evaluation step, not noise.
2. **Findings flagged by only one reviewer** — re-read the actual code with `Read`. Keep only if you now believe it's real. Drop hallucinations and noise.
3. **Disagreements** — pick the position you now believe correct after re-reading. Do not mark as "disputed".
4. **Voice** — single unified reviewer voice. No "codex said X / custom-review said Y" attribution in the body.
5. **Structure** — group by severity (blocking → medium → optional). File:line references on every finding.

Also write `tmp/multi-review/provenance-<slug>.md` capturing, per finding (kept or dropped):

- Which reviewer(s) raised it.
- Kept / dropped / merged decision and one-line reason.

The evaluation step uses this directly; never lose it to in-memory state.

## Step 5 — Print merged review and ask to fix

Print the full contents of `merged-<slug>.md` inline in the chat.

Then call `AskUserQuestion` with a yes/no:

- **Question:** "Apply these fixes now?"
- **Options:** "Yes — apply all merged findings" / "No — skip fixes (evaluation still written)"

Regardless of the answer, an evaluation will be written in Step 8. The fix experience supplies grounded judgments; without it, evaluation fields that depend on fix evidence are explicitly marked `not assessed (fixes declined)` rather than guessed.

If "no": skip Steps 6 and 7, jump to Step 8 with the `fixes_applied=false` flag.

## Step 6 — Apply fixes (one pass, no per-finding checkpoint)

(Only runs if the operator answered "yes" in Step 5.)

Apply every blocking and medium finding from the merged review in one pass. Optional/polish findings: apply if cheap, skip if invasive.

While fixing, keep brief notes for the evaluation step:

- Which findings were real, partial, or false alarms once you got into the code.
- Which findings required reading code the reviewer didn't cite (under-statement).
- Which findings exaggerated severity or impact (over-statement).
- Which findings were uniquely deep (would have been missed by the other two).

Do not prompt the user between findings.

## Step 7 — Best-effort verification

(Only runs if Step 6 ran.)

If there is an obvious one-command quick check in the repo, run it and capture the result:

- Rust: `cargo check` (and `cargo test` if fast)
- Node/TS: `npm test`, `pnpm test`, or `yarn test`; or `npx tsc --noEmit`
- Python: `pytest -q` if a `pytest.ini`/`pyproject.toml` indicates it
- Go: `go build ./...`

If the project has no obvious quick check, or the check would take more than ~2 minutes, skip it. Note the result (or that it was skipped) in the evaluation.

Do **not** block the evaluation on a green check — the evaluation is about reviewer quality, not the final state of the code.

## Step 8 — Write evaluation

Write to `tmp/multi-review/evaluation-<slug>.md`. Always written — even when fixes were declined. Fix-grounded fields without evidence are explicitly marked `not assessed (fixes declined)`; do not guess.

Required sections:

### 1. Run metadata

- Target (display phrase), slug, date.
- Args / focus text forwarded.
- `fixes_applied`: true / false.
- Per-reviewer status (ok / failed-with-reason, findings count).
- Verification step outcome (command run, result, or "skipped: <reason>", or "n/a (fixes declined)").

### 2. Per-reviewer scorecard

One subsection per reviewer (codex, custom-review, custom-review2). For each, report:

- **Findings raised:** count, with severity breakdown.
- **Real findings:** how many turned out to be real after fixing. Cite 1–3 by short title. *(If `fixes_applied=false`: `not assessed (fixes declined)` — but still report the merge-stage decisions from `provenance-<slug>.md`: kept after re-read vs. dropped as hallucination.)*
- **False positives:** count, with one concrete example. *(If `fixes_applied=false`: use merge-stage drops only.)*
- **Under-statement:** findings whose severity or scope was understated. *(`not assessed` if fixes declined.)*
- **Over-statement:** findings whose severity, scope, or certainty was overstated. *(`not assessed` if fixes declined.)*
- **Signal-to-noise:** real / total (or kept-after-merge / total if fixes declined). One sentence on the dominant noise type.
- **Unique depth:** findings only this reviewer raised that survived merge / fix. At least one cited example if any.

### 3. Comparison table

Single markdown table. Rows: total findings, kept-after-merge, real-after-fix (or `—` if declined), false positives, blocking real / claimed, unique-real (or unique-kept), S/N ratio, depth rank (1–3). One column per reviewer.

### 4. Narrative (2–4 paragraphs)

Which review was most useful and why, in concrete terms grounded in either the fix experience or the merge-stage evidence. Which was least useful and why. Patterns visible across runs that hint at skill improvements (e.g., "`custom-review2` consistently over-states React render-path claims" or "`codex` misses cross-file consumer searches"). Avoid generic praise; cite findings.

### 5. Skill-improvement hypotheses

A short bullet list of concrete edits to `custom-review`, `custom-review2`, or the codex prompt that would have improved this run. Each bullet names the skill, the change, and the finding(s) that motivated it. This is the deliverable that makes the A/B testing actionable.

After writing the evaluation, print only a short summary to the operator:

- Path to the evaluation file.
- One-line "ranked best → worst" verdict.
- The top 1–2 skill-improvement hypotheses, verbatim from section 5.

Do not re-print the evaluation in full — the operator can read the file.

## Failure modes — quick reference

| Failure | Action |
|---|---|
| Not inside a git repo | Refuse |
| `codex` not on `PATH` | Refuse |
| `custom-review` or `custom-review2` skill missing | Refuse |
| `gh` missing or unauthenticated (PR target only) | Refuse with the specific missing piece |
| Args use rejected shorthand (`branch X`, `staged`) | Refuse with the corrected form |
| Args ambiguous (multiple target hints) | One short multiple-choice question |
| PR head branch ≠ current branch | Abort with `gh pr checkout <num>` instruction |
| PR head OID ≠ local HEAD OID | Abort with the appropriate fetch / push / rebase guidance for ahead / behind / diverged |
| PR target with dirty worktree | Abort; tell operator to commit, stash, or discard first |
| Target has no diff | Refuse |
| Output files already exist for this slug | `AskUserQuestion` overwrite y/n; exit on no |
| One reviewer fails / empty / times out | Write `FAILED:` placeholder + status sidecar; continue with the others |
| All three reviewers fail | Print the three reasons and exit before merging |
| Operator declines to fix | Skip Steps 6–7; still write evaluation with fix-grounded fields marked `not assessed` |
