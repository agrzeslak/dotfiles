---
name: codex-review
description: Cross-check the most recent Claude `/review` by spawning a codex agent that runs `codex review` against the same target, then synthesise a single combined review out of the best parts of both. Use when the operator has just run `/review` (in this conversation) and wants a second opinion merged in. Also accepts trailing text that is forwarded to codex as a custom review prompt.
---

# Codex Review

## Purpose

`/codex-review` runs a second, independent code review using the `codex` CLI against the **same target Claude just reviewed**, then merges Claude's review and codex's review into a single combined review. The user only sees the merged output — never codex's raw output.

This skill is **manually invoked after** a Claude `/review`. It is not auto-triggered.

## Hard preconditions

Refuse with a clear, short message if any of these fail:

1. **A prior `/review` exists in the current conversation.** This skill cross-checks Claude's review — if Claude has not just reviewed something in this conversation, there is nothing to cross-check. Tell the operator to run `/review` first.
2. **`codex` is on `PATH`.** Run `command -v codex`. If missing, tell the operator to install codex.
3. **Working directory is inside a git repository.** `codex review` operates on a working tree.

## Step 1 — Recall what was reviewed

Look back through the current conversation for the most recent `/review` invocation and Claude's resulting review. Extract:

- **Target type:** one of `pr`, `branch`, `commit`, `uncommitted`.
- **Target identifier:** PR number, base branch, or commit SHA, as applicable.
- **Base branch:** for `pr` and `branch` targets.

Heuristics:

- A PR number or PR URL in the user's `/review` invocation → `pr`.
- An explicit base branch (e.g. `against main`) with no PR → `branch`.
- A specific commit SHA → `commit`.
- Words like "uncommitted", "staged", "working tree" → `uncommitted`.
- If unclear, default to `branch` against the repo's default branch (`gh repo view --json defaultBranchRef -q .defaultBranchRef.name`, falling back to `main`).

If you genuinely cannot determine the target from the conversation, ask the operator one short multiple-choice question rather than guessing.

## Step 2 — PR-target preflight

If target type is `pr`:

1. `gh pr view <num> --json headRefName,baseRefName` to get the PR's head and base ref names.
2. `git rev-parse --abbrev-ref HEAD` to get the current branch.
3. If the current branch does **not** match `headRefName`, abort with a clear message:

   > Codex reviews the current working tree. The PR's head branch is `<headRefName>` but you're on `<currentBranch>`. Run `gh pr checkout <num>` and re-invoke `/codex-review`.

   Do not auto-checkout — that risks clobbering uncommitted work.

For non-`pr` targets, skip this step.

## Step 3 — Build the codex invocation

Map target → flags:

| Target type | Flags |
|---|---|
| `pr` | `--base <baseRefName>` |
| `branch` | `--base <baseBranch>` |
| `uncommitted` | `--uncommitted` |
| `commit` | `--commit <sha>` |

**Construct a human-readable target phrase** to splice into the prompt:

| Target type | Target phrase |
|---|---|
| `pr` | `PR #<num>` |
| `branch` | `the changes on branch <currentBranch> vs base <baseBranch>` |
| `commit` | `commit <sha>` |
| `uncommitted` | `the uncommitted changes in the working tree` |

**Always pass the following prompt** as the trailing positional after a `--` separator. The `--` prevents text starting with `-` from being parsed as a codex flag. Substitute `<target phrase>` with the value from the table above:

```
You may encounter `bwrap: loopback: Failed RTM_NEWADDR: Operation not permitted`.

Do not treat that as a review result. Per the active tool policy, if an important command fails due to sandboxing, rerun that command with `sandbox_permissions: "require_escalated"` and include a short justification. `gh` may be unsandboxable, so attempt it normally only if required by policy, then request escalation after the sandbox failure.

Review <target phrase> in code-review mode:
1. Identify the behavioral contract changed by the PR.
2. Inspect the diff and relevant surrounding code.
3. Search for dependents and sibling paths.
4. Run focused verification where practical.
5. Return findings first, ordered by severity, with file/line references.
6. If no issues are found, say so and list any residual test gaps.

Follow the repo's AGENTS.md instructions, especially ADR conformance and review workflow.
```

**Operator trailing text.** If the operator passed trailing text to `/codex-review`:

- Drop the text if it is exactly `-` (codex would treat that as stdin and hang).
- Otherwise append it to the prompt above as an `Additional focus:` line on a new line at the end, e.g. if the operator wrote `/codex-review focus on the auth changes`, the final line of the prompt becomes:

  ```
  Additional focus: focus on the auth changes
  ```

Pass the whole assembled prompt as a single positional argument. Example shape:

```
codex review --base main -- "<assembled prompt>"
```

## Step 4 — Run codex review

Single `Bash` call:

- Working directory: same as the current working directory (so codex sees the same tree Claude reviewed).
- Timeout: 600000 ms (10 minutes). Codex reviews of large diffs can take several minutes.
- Capture stdout and stderr. **Do not stream** codex's output to the user. Do not echo it after the run.
- If codex exits non-zero, surface the stderr to the operator and stop. Do not attempt to merge.
- If codex exits zero with empty stdout, tell the operator codex returned no findings and emit only Claude's original review (no merge to do).

## Step 5 — Synthesize the combined review

You now have two reviews:

- **Claude's review** — already in the current conversation context, from the recent `/review`.
- **Codex's review** — the captured stdout from Step 4.

Produce **one** combined review with these synthesis rules:

1. **Findings both reviewers flagged** — keep, dedupe to a single entry. Use the clearer wording.
2. **Findings only one reviewer flagged** — re-examine the actual code. Keep the finding only if you now believe it is real after looking. Drop hallucinations or noise.
3. **Disagreements** — if the two reviewers take opposite positions on the same code (e.g. Claude said "fine", codex flagged it as a bug, or vice versa), re-examine the code with both views in mind and pick the position you now believe correct. Include only the chosen position in the combined review. Do **not** mark findings as "disputed".
4. **Voice** — one unified voice. No "Claude said X / codex said Y" attribution. The combined review reads like a single reviewer's output.
5. **Structure** — match the structure of Claude's original review (the operator already has a mental model of that shape from `/review`).

## Step 6 — Output

Print only the combined review. Nothing else — no preamble like "Here is the combined review", no codex raw output, no diff against the original Claude review, no file artifacts on disk.

If you re-read the actual code as part of synthesis (Step 5 rules 2 and 3), do that with `Read` — do not narrate the re-reading to the operator.

## Failure modes — quick reference

| Failure | Action |
|---|---|
| No prior `/review` in conversation | Refuse; tell operator to run `/review` first |
| `codex` not on `PATH` | Refuse; tell operator to install codex |
| Not inside a git repo | Refuse; explain `codex review` needs a working tree |
| PR head branch ≠ current branch | Abort with `gh pr checkout <num>` instruction |
| Cannot determine target from conversation | Ask one short multiple-choice question |
| Codex exits non-zero | Show stderr; do not merge |
| Codex stdout empty | Emit Claude's original review unchanged; tell operator codex had no findings |
| Codex times out (10 min) | Tell operator; do not merge |
