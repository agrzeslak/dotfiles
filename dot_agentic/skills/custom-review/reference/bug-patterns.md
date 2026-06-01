# Bug patterns

Twenty-one concrete heuristics that surface the kinds of bugs a shallow review misses. **Class-triggered lookup**: at workflow step 5, identify which class of change is in scope (table below) and read only the patterns for that class. Reading all twenty-one on every review is wasted runtime — most diffs touch 2–4 classes.

Use these to **prime attention**, not as a checklist to mechanically tick. The pattern is wrong-shaped if you've ticked it without naming the specific surface or site to which it applies.

## Class-triggered lookup table

| Change class | Patterns to prime on |
|---|---|
| New or changed semantic surface (type, enum, field, schema, status, route) | 1, 2, 9, 12, 15 |
| New producer / writer / dispatch arm meant to affect current behavior | 1, 2, 12, 17, 20 |
| Changed user workflow / command / action path | 3, 5, 8, 19 |
| Refactor or extraction | 3, 5, 6, 20 |
| New code path mirroring an established sibling (divert/forward, send variant, transport mode, new match arm beside existing ones) | 3, 20 |
| New early return / new branch / new guard | 4, 18 |
| Async / cancellation / sequencing | 7, 21 |
| Finalize / persist / flush that reads state written by join/timeout/cancellation-bounded tasks | 20, 21 |
| UI state / persistent state / cache | 8, 9 |
| Permission or auth change | 10, 18 |
| Migration or schema | 11 |
| Wire format / serialization / persisted config | 12, 14, 18 |
| Touched tests | 13 |
| Documentation, comments, runtime-model docs, adjacent docstrings | 16 |
| Defensive flags, accumulators, scratch state, new dispatch arms with potentially no producer | 17 |
| Boolean predicate / validator / `is_*` / `has_*` / `should_*` helper gating a destructive or wire-visible side effect | 18 |
| New operator-facing entry (keybinding, prompt-command, menu item, MCP tool, CLI subcommand, dispatch arm, context-menu action) | 17, 19 |
| UI→command→output edit chain (inline editor, form commit, request crafter) | 19, 20 |

Patterns 16 (doc-vs-impl-lies) and 17 (dead-state) also deserve a deliberate sweep at workflow step 2 — re-read adjacent comments and check for defensive structures whose read sites are unreachable.

Patterns 3 (sibling-path parity), 20 (returned-value discarded), and 21 (cross-async-task teardown) are the **cross-component / sibling-parity / async-lifetime** classes: the bugs that survive a review which validates each component in isolation. Prime on them whenever a change spans more than one component, mirrors a sibling, or finalizes data produced by a separate task.

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

**Sibling behavior-parity diff (not just validation).** When a NEW code path has an established sibling implementing the same operation (a divert path beside the normal forward path, a new send-mode beside the existing one, a new transport branch beside the cleartext one), do not stop at "does the new path validate its inputs?" — **diff the two paths for behavior the sibling HAS that the new path LACKS.** The new path typically compiles, unit-tests green, and silently does *less* than its sibling: it omits a response-attach, picks a wrong per-transport default, maps an error to the wrong terminal state, or fails to persist a returned value the sibling persists. The tell is asymmetry between two paths that the operator believes are equivalent.

> Example: a request-divert success arm discards the returned `ResponseCapture` before persistence, so the diverted flow records no status/body — diverging from the sibling normal-send path's `build_result_flow`, which *does* attach the response. (This pairs with pattern 20.)
>
> Example: a `resolve_dial_authority` helper defaults a portless authority to `:443` for ALL transports, which is wrong (`:80`) for the cleartext transports — a per-transport sibling gap the TLS path doesn't have.

**Search target:** for every changed workflow, the parallel implementation of the same workflow elsewhere in the codebase. For every NEW path that mirrors an existing sibling, enumerate what the sibling does after the shared step (attach response, set terminal state, persist a returned value, pick a per-input default) and confirm the new path does each of those too. For error/failure branches specifically, pattern 5's sibling-branch comparison is the focused form of this check.

---

## 4. Enumerate old inputs that hit a new branch

New early returns are dangerous. Ask: *which old valid inputs now satisfy this condition by accident?*

> Example: code returns early when `items.length === 0` to show an empty state, but `items` is temporarily empty during loading. The page now flashes "No results" and suppresses the spinner.

**Search target:** every newly-introduced branch, early return, or guard — and the old inputs that would now hit it.

---

## 5. Diff error / loading / empty paths separately from happy paths

A refactor can preserve success rendering and drop error handling. Compare non-happy paths between old and new code explicitly.

> Example: extracted React component keeps the table but loses the parent's `isError` branch. A failed fetch now renders an empty table, making the UI lie.

**Sibling-branch comparison — and finding-vs-OQ.** When the change adds or alters one error/failure branch, find the *sibling* branch(es) handling the same failure class and compare them. A divergence between two arms of the same `match`/`if` that handle related failures is the tell: one sets `persist_error`, the other doesn't; one maps to `Aborted`, the other to `Completed`; one advances a cursor, the other doesn't. Run this comparison *before* deciding whether a divergence is a finding or merely an Open Question — if the sibling proves the intended contract, the divergence is a finding, not an OQ; if the sibling shows the divergence is deliberate, demote to OQ. This is the error-branch-focused form of pattern 3's sibling behavior-parity diff.

**Search target:** for every component or handler refactored, the error/loading/empty rendering in both versions; for every new error/failure branch, the sibling branch handling the same failure class.

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

**Cross-surface authority parity.** When a NEW endpoint / tool / query returns the SAME sensitive payload an EXISTING one already gates, it must require **at least** the existing surface's permission group(s) — never a narrower new group. A single-group classification can't express a conjunction the spec requires (e.g. `FindingRead + FlowRead`). Diff the new surface's payload against siblings that return the same data; if a sibling is gated higher, the new surface's gate is a privilege-escalation finding.

> Example: a new `finding.get_flow` tool returns the full `FlowDetail` (bodies) identical to the `Read`-gated `flow.get_detail`, but is classified `FindingRead` — a profile granting `FindingRead` while denying `Read` could read arbitrary flow content. This class slips past per-surface reviews and surfaces only on a cross-cutting pass.

**Search target:** every permission-touching change — the UI gate, the server check, and the difference between them; every new payload-returning surface — the existing surfaces returning the same payload, and whether the new gate is at least as strict.

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

This pattern is one of the review's strongest niches — but only when scanned for deliberately. Otherwise it surfaces emergently and gets dropped as trigger-shyness.

> Example: `runtime-model.md` status tables still read `NotImplemented` for arms that were just wired in this change. The doc lies. Fix is the doc, not the code — but the lie is a finding.
>
> Example: a `permissions_filter` doc claims `clear-on-AgentDisconnected`; the code never clears it. The comment is sticky; the doc is wrong.
>
> Example: a variant's doc says it replaces `.scope`, but the impl replaces the whole `intercept_defaults`. Silent today; becomes a live bug when a documented future consumer lands.
>
> Example: an *implementation-plan doc landed in the same diff* claims "Note and description mutations carry the new value only" — contradicting the shipped value-less `NoteSet`/`NoteCleared` enum. The lie is in plan prose, not a code comment, and it ships in the same diff.

**Plan / spec docs landed in the same PR are first-class claim-vs-reality targets — not just code comments and ADRs.** Design specs, implementation-plan docs, roadmap entries, and PR-body prose that ship in the diff make claims about the code shipping alongside them. Read them as claims and falsify each against the enum/struct/function they describe. This is high-signal on doc-heavy and contracts-only PRs where the code is mechanical but the prose drifts.

**"New vs reused" member cross-check.** When a doc, comment, or plan lists members as *"new" / "added" / "<feature>-specific"* versus *"reused" / "existing" / "shared"*, cross-check each listed member against its actual definition. A member grouped as new that is in fact a reused/shared variant (or vice-versa) is a false claim. (Example: a `FindingListQuery.search` doc lists `Status` among "finding-specific additions", but `SearchField::Status` is the reused HTTP-status variant — exactly the per-member verification this bullet forces.)

**Search target:** for every touched code path with adjacent doc-comment / docstring / `//` comment, re-read the comment and ask whether it still describes what the code does. For every touched module/feature, check whether `runtime-model.md`, ADRs, READMEs, in-tree spec files, OR plan/spec/roadmap docs landed in the diff contain status tables, capability lists, member groupings ("new vs reused"), or behavior bullets referring to the touched concept. **The promotion gate is "is the claim currently false?" — not "is the bug reachable from this comment?"** (See the claim-vs-reality finding-shape in `SKILL.md` § *Finding-promotion rules* and the claim-vs-reality sweep guidance in step 2.)

**Symmetric guard — don't let a *true* comment hide a *false* behavior.** This gate scores the comment, not the behavior. A literally-accurate comment does NOT clear a candidate when the accurately-described behavior is itself the defect — route those back through the behavioral correctness gates rather than dropping them as `claim-currently-true`. See `SKILL.md` § *Claim-vs-reality findings* (the claim-true-but-behavior-wrong carve-out) and `claude-failure-modes.md` #17.

---

## 17. Dead / defensive state

A field, flag, accumulator, defensive-guard variable, or scratch state exists but has no observable read on the actual control flow. It looks load-bearing — set and cleared in multiple sites — but never affects behavior. Or the read site is reached only in code paths the program never enters (dead dispatch arm, unused early-return branch, test-only path).

This is the **"looks load-bearing but isn't"** class.

> Example: a `suppress_agents_perm_undo_record` flag has no observable effect — the recording-prevention happens at the dispatch-path bypass, not at the flag. Four set/clear pairs and a guarded read site all turn out to be no-ops; the flag should be removed entirely.

**Search target:** for every defensive flag, accumulator, or scratch-state field added or modified in the diff, name every read site by file:line. For each read site, trace from a real entry point and confirm the read is reachable. If the read site is unreachable, the entire defensive structure is dead. Symmetric scan: for every new dispatch arm, status code, or enum variant, confirm a real producer can emit it (the inverse — read-but-not-written — is the deletion-orphan / dead-dispatch class).

This complements the producer-claim shape: producer-without-actual-source-of-truth-at-read is the architectural blind spot (`claude-failure-modes.md` #12); consumer-without-producer is the dead/defensive-state class.

---

## 18. Negative-space truth-table for boolean predicates

Boolean predicates that gate side-effects (`is_*`, `has_*`, `should_*`, validation helpers, framing/parsing predicates, dispatch guards) hide bugs in their permissive branch. Most coverage tests exercise signal-present rows (header present, field valid, state matches); the permissive default row — every checked attribute is absent, or the parser failed, or the fall-through returns the permissive value — is where destructive operations slip through.

**Two-step mental check:**

1. **Caller-local.** At each caller of the predicate, identify which return value is *permissive* — i.e. unlocks the destructive / irreversible / wire-visible operation. (Sometimes `true` is permissive; sometimes `false` is. The patch-applier in `framing_carries_body` returned `false` to mean "no body to worry about," which permitted a body-shape patch.)

2. **Function-local.** In the predicate, enumerate every path that returns the permissive value. Cover at minimum:
   - No relevant attribute present at all.
   - Attribute present but malformed (parse error → default).
   - Multiple values where only one was anticipated (`Content-Length: 0, 100`).
   - Default / fall-through return at end of function.
   - Early-return on edge cases (HEAD method, status forbids body).

   For each path, ask: is the destructive operation gated by the caller still safe?

**Triggers on:** `fn(...) -> bool` that controls whether a destructive side-effect runs — patch application, write commit, broadcast emit, permission grant, wire format change.

> Example: a `framing_carries_body` predicate returns `false` when no `Content-Length > 0` AND no `Transfer-Encoding: chunked`. HTTP/1.0 close-delimited responses (no CL, no TE) hit this path. The caller, `StatusForbidsBody`, then *accepts* a patch from `200 OK + close-delimited body` to `204 No Content` — wire-desync on the client socket. Coverage tests asserted CL=0/CL>0/TE=chunked; no test covered the "no framing headers at all" branch.

**Search target:** for every changed predicate, write a one-line truth-table next to it in `notes.md` covering the absent / malformed / parse-error / default / fall-through cases; mark which row produces the permissive return.

---

## 19. Feature shipped but unreachable

For every new operator-facing entry the PR adds — keybinding, prompt-command, menu item, CLI subcommand, MCP tool, dispatch arm, context-menu action — trace from the operator-facing entry through the dispatcher to the producing engine command / handler. The bug class is *"entry binds but the producer rejects, no-ops, hardcodes the wrong target, or the precondition the producer needs is never realized."* Unit tests of the dispatcher and unit tests of the producer can both pass while the wired path is broken end-to-end.

**Three-step trace:**

1. **Find the operator-facing binding.** Inspect the integration site for each new entry — the keymap.rs row, the dispatch arm in `App::apply`, the MCP tool registration in `build_tool_router`, the CLI `clap` subcommand definition, the menu / context-menu construction. Confirm the entry exists at the integration table, not just in the helper module the entry refers to.
2. **Walk dispatch: binding → command emitter → engine receiver → producing handler.** At each hop, confirm the next layer **accepts the exact value the prior layer emits.** A binding that emits a command the engine rejects, or that targets a pane / context / listener / agent / ID that no longer exists, or whose precondition (selected != None, mode == Foo, pane has Proxy) is never realized, is broken even though both ends compile and both ends' unit tests pass.
3. **Assert the OUTPUT artifact carries the operator's actual edit.** Reaching the producer is necessary but not sufficient: for an edit chain (inline editor, form commit, request crafter), drive the full keystroke → commit → dispatched-artifact path and confirm the *output* reflects what the operator entered — the field NAME as well as its value, the toggled mode as well as the staged bytes, the re-derived authority as well as the path. Validating each handler in isolation misses a commit step that silently keeps a stale or empty component.

**Triggers on:** any new entry in the operator-facing integration table — new keybinding, new prompt-command, new menu item, new MCP tool, new CLI subcommand, new dispatch arm, new context-menu action. Also fires when an existing entry is re-routed (re-targeted to a different handler), and on any UI→command→output edit chain (step 3).

> Example: a new `d` keybinding for rule removal emits `ProxyScopeRemove` against `scope_selected`, but the new `refresh_scope_rules` never auto-selects on empty→non-empty, so `scope_selected` stays `None`. The keybinding binds; the command emits; the engine accepts — but nothing happens because the producer's precondition (selected != None) is never realized.
>
> Example: a new `t` keybinding for per-listener intercept toggle dispatches `ProxyListenerSetIntercept(listener_id)` with a hardcoded `listener_id = 0` from a stale spec, so the binding works only for listener 0 and silently misfires for any other listener.
>
> Example (step 3): a request editor's inline-edit commit writes only the field *value* and preserves the empty *name*, so `to_request()` never carries a keyboard-added `content-length` / duplicate-`:path` / arbitrary header — the feature's entire point is unreachable through the UI. Each handler and the operator-only gate are individually sound; only composing keystroke → commit → `to_request()` and inspecting the output reveals the dropped name.

**Search target:** for every new operator-facing entry added by the PR, find the entry's integration site AND every layer the dispatch crosses. Confirm each layer's behaviour on the value the prior layer actually emits — not the value the spec / comment / test fixture claims it emits. Confirm preconditions the producing handler needs are realized by initialization / refresh code that runs before the operator can reach the entry. For edit chains, additionally assert the final dispatched artifact carries every component of the operator's edit.

This pattern pairs with the prompt-command/keybinding dispatch carve-out in `SKILL.md` § *Visibility-dependent findings*: findings of this class satisfy `Render proof:` by citing the dispatch chain, not by tracing through to a TUI redraw.

---

## 20. Returned value discarded before persistence / propagation

This is the **inverse of the producer-realization lens** (`SKILL.md` step 5). Producer-realization asks *"does the produced value reach its consumer?"* This asks the mirror question: *"does a caller DISCARD a value that a sibling caller or a contract says must be persisted / propagated / forwarded?"* The producer-realization template tracks values flowing *toward* a read site; it has no native lens for a returned value that is simply dropped on the floor.

The defect shape: a function returns a value (a capture, a result, a status, a handle, a count) that an established sibling call site or a documented contract persists or forwards — but a NEW caller drops it. The drop is usually quiet: `let _ = f()`, an unused binding, a success arm that ignores `Ok(x)` and returns early, a `match` arm that handles the value's *existence* but never attaches it to the record.

> Example: a request-divert success arm receives a `ResponseCapture` from the send core and discards it before persistence, so the diverted flow records no status/body — while the sibling normal-send path's `build_result_flow` attaches the same capture. (Also a pattern-3 sibling-parity miss.)
>
> Example: a bridge's `upstream_conn_task` 5s join-timeout result is discarded with `let _ = timeout(...)`, so the discarded value never marks the capture incomplete (see pattern 21 for the teardown angle).

**Search target:** for every function in the diff whose return value a sibling caller or a contract persists/propagates, find the NEW callers and confirm none of them drop it. Flag `let _ = …`, unused `Ok(_)` / `Some(_)` bindings, and success arms that hold the returned value but never persist or forward it where a sibling does. When the producer-realization row finalizes cleanly (value reaches its consumer), still ask the inverse: is there a *returned* value here that some caller throws away?

---

## 21. Cross-async-task teardown completeness

When a finalize / persist / flush step reads a completeness signal — a `truncated` flag, a `complete` marker, a final byte count, an `Aborted` vs `Completed` terminal state — that is written by tasks which are themselves bounded by `join` timeouts, drain timeouts, cancellation, or `select!` arms, then **every teardown path must reach that signal**, not just one of them. A reviewer who confirms the signal is set on the *normal* completion path, or on *one* of several bounds, misses the bound that tears down silently.

The defect shape: two or more concurrent tasks can each end the capture (a per-task join timeout AND a drain timeout; a cancellation AND a normal return; a `select!` loser); the finalize logic only consults one of them, so data clipped by the other is persisted as if complete.

> Example: a capture finalize reads only the drain timeout to decide `s2c_truncated`; the per-task `upstream_conn_task` join timeout is discarded (`let _ = timeout(...)`), so a server→client blob clipped by the *join* timeout persists with `s2c_truncated == false` — a silent truncation reported as complete.

**Search target:** for every finalize/persist that reads a completeness/truncation/terminal-state signal, enumerate **every** teardown path of the tasks that produce the captured data — normal completion, each timeout (join, drain, idle), cancellation, error return, the losing arm of every `select!` — and confirm each path reaches the signal. This pairs with pattern 20 (the discarded `timeout` result is often the dropped value) and pattern 7 (async invalidation is about cancelling in-flight work; this is about *recording* that work ended incomplete).

---

(See the class-triggered lookup table at the top of this file for which patterns to read per change class.)
