---
name: cleanup
description: Post-PR housekeeping. Use after a PR's work is complete — merge the open PR, delete its branch/worktree, sweep stale merged branches and worktrees, remove leftover implementation files, and drain SESSION.md into issues / the active plan / a stub. Trigger whenever the user says "cleanup", "clean up after this PR", "post-merge cleanup", is finishing/wrapping up a feature branch, or asks to tidy branches, worktrees, leftover files, or SESSION.md after merging — even without the word "cleanup".
---

# Cleanup

Post-PR housekeeping. Runs the five steps below in order, then reports.

## Autonomy model

The cost of acting is asymmetric: deleting in-use work is expensive, deleting clear cruft is free. So:

- **Act automatically on clear-cut cases** — the just-merged PR's branch, branches/worktrees provably merged or tied to a closed PR, files unmistakably scoped to the last PR's implementation.
- **Prompt on ambiguous cases** — stale-looking but possibly-live branches, files whose forward usefulness is unclear. One short prompt listing them; don't interrogate per-item.
- **Never touch in-use work** — anything still referenced, current branch, the default branch, the worktree you're in.

`gh` is unsandboxable here: run it with `dangerouslyDisableSandbox: true`, never chained with other commands. Capture its output to a file, then process that file in a sandboxed call.

## Step 0 — Orient

Confirm a git repo. Identify the default branch, the current branch, and the PR associated with the current branch (`gh pr view --json number,state,title,body,headRefName`). If no PR exists for the branch, say so and skip to step 3 — there is nothing to merge.

## Step 1 — Merge the PR

If the PR is open and mergeable, merge it. Pick the method from what the repo allows (`gh repo view --json mergeCommitAllowed,squashMergeAllowed,rebaseMergeAllowed`): **prefer squash**; fall back to whatever the repo permits. If only one method is allowed, use it without asking.

With squash the squash commit message is the only message that survives. Compose it from the PR title and body — a semantic title and a body explaining non-obvious trade-offs — rather than letting GitHub concatenate every branch commit subject. Pass it explicitly (`gh pr merge --squash --subject ... --body ...`).

If the PR is not mergeable (conflicts, failing required checks, review pending), stop and report why — do not force it.

## Step 2 — Delete the merged PR's branch

Once merged, delete that branch locally and on the remote. This is the clearest-cut case; no prompt. Skip if it is the default branch. If you are currently on it, switch to the default branch first.

## Step 3 — Sweep stale branches & worktrees

Auto-delete (no prompt) branches that are either:

- fully merged into the default branch (`git branch --merged <default>`), or
- attached to a GitHub PR that is closed or merged.

Apply the same logic to worktrees: remove worktrees whose branch is merged / closed-PR and that haven't been used since. Never remove the worktree you are running in.

Prompt (one consolidated list, never auto-delete) for the genuinely ambiguous: local branches whose upstream is gone but not provably merged, or branches with no recent activity that aren't provably merged — they may hold un-pushed work.

Never delete the default branch, the current branch, or any branch with unmerged unique commits unless the user confirms.

## Step 4 — Remove leftover implementation files

Find files left over from the last PR's implementation that serve no forward purpose: scratch comparison artifacts, `tmp/` intermediates, ad-hoc `examples/` debugging programs, one-off scripts, dead notes.

Do not delete blindly. For each candidate, check forward usefulness before acting: grep the repo for references, check imports, build/test/CI config, and whether it is part of the shipped surface. Use `git mv`/`git rm` for tracked files.

- Unmistakably scoped to the last PR and unreferenced → delete automatically.
- Unclear forward value → list and prompt.
- Still referenced or in use → leave it.

## Step 5 — Drain SESSION.md

`SESSION.md` is gitignored and project-local. In a worktree the real one is in the **main** worktree: resolve via `git rev-parse --path-format=absolute --git-common-dir`, then `../SESSION.md`. Edit that file, not a worktree copy.

For each item, do the right thing, then remove it from the file:

1. **Immediately relevant to upcoming work** → integrate it into the active plan. Use both this conversation's context and the repo's planning/roadmap files (look for them — a plan/roadmap doc almost always exists; if genuinely none, ask where upcoming work is tracked) to place the item where it belongs.
2. **Real but not immediately relevant** → open a GitHub issue capturing it with enough context to action later; reference the issue number in your final report.
3. **Irrelevant / obsolete / already resolved** → just remove it.

End with `SESSION.md` reduced to a minimal stub (a header and nothing else) so the next session starts clean.

## Final report

Summarise concisely: PR merged (method), branches/worktrees deleted, branches awaiting the user's call, files deleted vs. left, and SESSION.md disposition (issues opened with numbers, items folded into the plan, items dropped). Surface anything you deliberately did not touch and why.
