# Bug patterns

Fifteen concrete heuristics that surface the kinds of bugs a shallow review misses. Read selected sections at the phases noted in `SKILL.md`. Each pattern names what to look for, why it fails, and a concrete example.

Use these to **prime attention**, not as a checklist to mechanically tick. The pattern is wrong-shaped if you've ticked it without naming the specific surface or site to which it applies.

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

## Section pointers by phase

The SKILL.md routes specific sections to specific phases:

| Phase | Sections to read | Why |
|---|---|---|
| Model (surface enumeration) | 1, 2, 9, 12, 15 | Primes attention to which kinds of changes count as semantic surfaces. |
| Search (sibling-path inspection) | 3, 5, 6, 10 | Sibling and parity heuristics. |
| Falsification | 4, 7, 8, 11, 13, 14, 15 | Edge-enumeration heuristics. |
| Search (completeness audit subagent) | All sections | The audit subagent re-derives surfaces from scratch. |
