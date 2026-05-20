# Bug patterns

Seventeen concrete heuristics that surface the kinds of bugs a shallow review misses. **Class-triggered lookup**: at workflow step 5, identify which class of change is in scope (table below) and read only the patterns for that class. Reading all seventeen on every review is wasted runtime — most diffs touch 2–4 classes.

Use these to **prime attention**, not as a checklist to mechanically tick. The pattern is wrong-shaped if you've ticked it without naming the specific surface or site to which it applies.

## Class-triggered lookup table

| Change class | Patterns to prime on |
|---|---|
| New or changed semantic surface (type, enum, field, schema, status, route) | 1, 2, 9, 12, 15 |
| New producer / writer / dispatch arm meant to affect current behavior | 1, 2, 12, 17 |
| Changed user workflow / command / action path | 3, 5, 8 |
| Refactor or extraction | 5, 6 |
| New early return / new branch / new guard | 4 |
| Async / cancellation / sequencing | 7 |
| UI state / persistent state / cache | 8, 9 |
| Permission or auth change | 10 |
| Migration or schema | 11 |
| Wire format / serialization / persisted config | 12, 14 |
| Touched tests | 13 |
| Documentation, comments, runtime-model docs, adjacent docstrings | 16 |
| Defensive flags, accumulators, scratch state, new dispatch arms with potentially no producer | 17 |

Patterns 16 (doc-vs-impl-lies) and 17 (dead-state) also deserve a deliberate sweep at workflow step 2 — re-read adjacent comments and check for defensive structures whose read sites are unreachable.

---

## 1. Search every consumer of every changed shape

When a type, enum, JSON shape, field name, status, or contract changes, the producer and the primary consumer usually get updated. Filters, exports, analytics, audit logs, tests, and admin views frequently don't.

> Example: backend starts returning `archived_at` instead of `is_archived`. The main page updates. CSV export still filters on `is_archived` and silently exports archived rows.

**Search target:** every occurrence of the old name AND every consumer of the new shape.

---

## 2. Search every producer, not just every consumer

When code adds handling for a new semantic category (status, edge type, event, permission), the question is *who can produce it?* Many bugs are incomplete producer updates.

> Example: UI adds support for a new edge type in a graph. Only one importer emits it. The live API and the background sync still emit the old type, so the new view only works in seeded tests.

**Search target:** for any new branch handling a new category, find every code path that could put data into that category.

---

## 3. Inspect sibling paths

When one workflow changes, look for alternate versions of the same workflow: create/edit, mobile/desktop, admin/user, bulk/single, modal/full-page, retry/initial submit.

> Example: validation added to "Create project" but not "Edit project," so existing records can be edited into invalid states.

**Search target:** for every changed workflow, the parallel implementation of the same workflow elsewhere in the codebase.

---

## 4. Enumerate old inputs that hit a new branch

New early returns are dangerous. Ask: *which old valid inputs now satisfy this condition by accident?*

> Example: code returns early when `items.length === 0` to show an empty state, but `items` is temporarily empty during loading. The page now flashes "No results" and suppresses the spinner.

**Search target:** every newly-introduced branch, early return, or guard — and the old inputs that would now hit it.

---

## 5. Diff error / loading / empty paths separately from happy paths

A refactor can preserve success rendering and drop error handling. Compare non-happy paths between old and new code explicitly.

> Example: extracted React component keeps the table but loses the parent's `isError` branch. A failed fetch now renders an empty table, making the UI lie.

**Search target:** for every component or handler refactored, the error/loading/empty rendering in both versions.

---

## 6. Check query enablement and mount-time side effects after extraction

When data-fetching moves into a child component, the child often mounts and fetches earlier than the parent did. The `enabled` condition that suppressed querying may now be absent.

> Example: parent previously rendered the details query only after the user selected an ID. The new child mounts immediately with `id === undefined`, causing a 400 loop or a broad fallback request.

**Search target:** when data-fetching is extracted into a reusable component, the `enabled` / `skip` / conditional-render guard that existed in the original.

---

## 7. Track async invalidation, not just replacement

If code uses sequence IDs, request IDs, AbortControllers, debounce, or query keys, ask which events should invalidate in-flight work. Replacement requests are easy. Other invalidating events are easy to miss.

> Example: a search request starts. The user clears the filter. The UI resets results. The earlier request resolves and repopulates stale results because clearing did not advance the request token.

**Search target:** every event that resets state or changes identity (clear, navigate, blur, filter change, identity switch) — does it cancel or invalidate in-flight work?

---

## 8. Follow persistent state through the next three actions

For UI state changes, ask: *after this state is set, what does the user likely do next?* Navigate, refresh, change filter, submit, retry, select another item.

> Example: a path search stores the selected result ID. After the user switches repositories, the old selected ID remains and the details pane shows a file from the previous repo.

**Search target:** any new persistent state — and whether the next user action keeps it correct, invalidates it, or makes it stale.

---

## 9. Cache keys must include every input that affects results

If fetched data depends on filters, permissions, locale, organization, feature flags, or sort order, the cache key must include them — or the cache will return wrong data.

> Example: query key includes `projectId` but not `includeArchived`. Toggling the archived view shows cached active-only results.

**Search target:** for every new query / cache key, every input that influences the response.

---

## 10. Treat permission changes as two-sided

Check both false positives and false negatives: who is newly allowed, and who is newly blocked? Compare UI gating with server enforcement separately.

> Example: frontend hides delete for non-owners, but the backend now checks only membership because the helper was reused from "edit." Direct API calls can delete.

**Search target:** every permission-touching change — the UI gate, the server check, and the difference between them.

---

## 11. Check migrations against existing data, not ideal data

Schema changes assume clean rows. Real data has nulls, duplicates, old enum values, and partial deployments.

> Example: migration adds a non-null foreign key populated from "the latest event." Accounts with no events fail migration, though tests only used accounts with events.

**Search target:** every migration — and the rows in production that don't match the migration's assumptions.

---

## 12. Verify serialization boundaries

Bugs appear where Rust/TypeScript/Python/internal names cross JSON, database, CLI, or environment boundaries. Renaming an internal symbol can silently change the serialized form.

> Example: internal enum variant is renamed. The serialized value changes unintentionally. Existing saved configs no longer load.

**Search target:** every cross-boundary serialization — JSON wire format, database column values, CLI flags, env vars, persisted configs — and whether the new code preserves the on-the-wire form.

---

## 13. Read tests for fixture blindness

Ask what the fixture makes **impossible to fail**. Tests often pass because data is too simple.

> Example: a sorting test uses names `A`, `B`, `C`. Both server sort and client insertion order pass. Real mixed-case names expose wrong ordering.

**Search target:** every fixture — what real-world variation does it not cover (case, locale, concurrency, scale, old data, identity overlap)?

---

## 14. Check backward compatibility and rollout order

If producer and consumer deploy separately, ask whether old-producer / new-consumer AND new-producer / old-consumer both work.

> Example: API stops emitting a field after frontend update. Mobile clients still require it.

**Search target:** every wire-format or contract change — and both directions of partial deployment.

---

## 15. Look for semantic mismatch hidden behind matching types

Types can compile while meaning changes. Strings, IDs, and durations are common offenders.

> Example: helper takes `workspaceId`; caller passes `organizationId`. Both are strings. Tests use the same fake ID for both. Production permissions break.

**Search target:** every API surface where two structurally identical types carry different meanings — IDs of different entities, durations in different units, paths in different namespaces, timestamps in different timezones.

---

## 16. Doc-vs-impl-lies

A comment, docstring, doc-bullet, runtime-model table, ADR, or in-source `//` comment claims behavior that the code beside it does not implement. The claim was true at one point; the code was changed; the comment was not. Or the claim was wishful from the start.

This pattern is custom-review's strongest demonstrated niche (n=4 across R5/R6/R8/R10) — but only when scanned for deliberately. Otherwise it surfaces emergently in some runs and gets dropped as trigger-shyness in others.

> Example (R6): `runtime-model.md` status tables still read `NotImplemented` for arms that were just wired in this PR. The doc lies. Fix is the doc, not the code — but the lie is a finding.
>
> Example (R10 F4): `permissions_filter` doc claims `clear-on-AgentDisconnected`; the code never clears it. The comment is sticky; the doc is wrong.
>
> Example (R8): variant doc says `.scope`, impl replaces whole `intercept_defaults`. Silent today, becomes a live bug when documented future consumer lands.

**Search target:** for every touched code path with adjacent doc-comment / docstring / `//` comment, re-read the comment and ask whether it still describes what the code does. For every touched module/feature, check whether `runtime-model.md`, ADRs, READMEs, or in-tree spec files contain status tables, capability lists, or behavior bullets referring to the touched concept. **The promotion gate is "is the claim currently false?" — not "is the bug reachable from this comment?"** (See the claim-vs-reality finding-shape in `SKILL.md` § *Finding-promotion rules* and the v2 sweep guidance in step 2.)

---

## 17. Dead / defensive state

A field, flag, accumulator, defensive-guard variable, or scratch state exists but has no observable read on the actual control flow. It looks load-bearing — set and cleared in multiple sites — but never affects behavior. Or the read site is reached only in code paths the program never enters (dead dispatch arm, unused early-return branch, test-only path).

This is the **"looks load-bearing but isn't"** class, novel to R10 F3.

> Example (R10 F3): `suppress_agents_perm_undo_record` flag has no observable effect — the recording-prevention happens at the dispatch-path bypass, not at the flag. Four set/clear pairs and a guarded read site all turn out to be no-ops. Removed entirely on adjudication.

**Search target:** for every defensive flag, accumulator, or scratch-state field added or modified in the diff, name every read site by file:line. For each read site, trace from a real entry point and confirm the read is reachable. If the read site is unreachable, the entire defensive structure is dead. Symmetric scan: for every new dispatch arm, status code, or enum variant, confirm a real producer can emit it (the inverse — read-but-not-written — is the deletion-orphan / dead-dispatch class).

This complements the v2 producer-claim shape: producer-without-actual-source-of-truth-at-read is the architectural blind spot (`claude-failure-modes.md` #12); consumer-without-producer is the dead/defensive-state class.

---

(See the class-triggered lookup table at the top of this file for which patterns to read per change class.)
