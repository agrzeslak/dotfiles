# Determined — search protocol

The mechanical detail behind `SKILL.md`: where state lives, its exact schema, how the
proof renders, the orchestration loop, the subagent contracts, the resume procedure,
and a fully worked example. Read this before running a search deep enough to persist.

Notation: §N refers to the same-numbered section of `SKILL.md`.

## Canonical location

State and proof live at fixed, goal-derived paths so a fresh session resolves the same
directory without being told where to look:

```
tmp/determined/<task-slug>/state.json   # canonical search state
tmp/determined/<task-slug>/proof.md     # rendered on a terminal state
```

`<task-slug>` is a deterministic slug of the goal: lowercase, non-alphanumerics → `-`,
collapse repeats, trim, cap ~50 chars (e.g. "find any authorization issue in foo" →
`find-any-authorization-issue-in-foo`). Determinism is the point — resume depends on
recomputing the same slug from the same goal. On a slug collision with an *unrelated*
goal, append a short disambiguating suffix and record the full goal in `state.json` so
the mismatch is detectable.

## `state.json` schema

```jsonc
{
  "goal": "find any authorization issue in component foo",
  "bounds": "read + analyze foo and its callers; no writes to prod; no new scope",
  "budget": { "global_remaining": null, "per_branch": null }, // cost/time budgets; a
                               //   branch hitting its cap backtracks; the global cap
                               //   nearing zero spawns an ask-user cost escape (§10).
                               //   Persisted so a resumed session respects prior spend.
  "terminal_state": "none",   // none | solved | user_redirected | impossible
  "redirect": null,            // when user_redirected: { "asked": "...", "at_cursor": "n5" }
  "cursor": "n5",              // id of the current frontier node (where DFS resumes)
  "seen": {                    // memo map: signature -> node id (dedup => graph)
    "validate()-covers-all-entrypoints": "n6"   // memoized; parents n1 and n4
  },
  "ledger": [                  // append-only leads learned while exploring
    { "id": "L1", "content": "admin/export endpoint added in v3, not in the route guard list", "source": "n5" }
  ],
  "nodes": {
    "n0": {
      "type": "problem",       // problem (OR) | approach (AND) | ask-user (see below)
      "desc": "auth bypass exists in foo",
      "signature": "auth-bypass-foo",
      "status": "active",      // see "Status semantics" below
      "result": null,          // for closed/solved: the concrete outcome
      "attempt_state": null,   // approach nodes only: untried | succeeded | inconclusive
                               //   — whether the approach's OWN attempt worked,
                               //   independent of its surfaced sub-problems; null on
                               //   problem/ask-user nodes
      "children": ["n1","n2","n3","n4","n5"],  // SINGLE SOURCE OF TRUTH for edges (n6 is surfaced under n1+n4, not a direct child of n0)
      "closure_basis": null,   // required on every closed node; null otherwise
      "closed_at_ledger_len": null, // ledger length at this node's MOST RECENT closure;
                               //   revival + global sweep apply only leads with index
                               //   >= this, so a re-close on the same basis is not
                               //   re-revived by an already-applied lead (livelock guard)
      "precondition": null,    // for an unexplored node: the assumption keeping it un-tried
      "expansion_phase": "children_open", // problem nodes only; null otherwise
      "gated_approach": null   // ask-user nodes only: the {desc, signature} of the
                               //   out-of-bounds approach this request would unblock;
                               //   instantiated as an open approach sibling on approval
    }
  }
}
```

### Edges and multi-parent propagation

`children` is the **only** edge record. A node's parents are *derived* by scanning every
node's `children` for its id. Because a memoized node (one in `seen`) can be linked by
more than one approach, it can have several parents — this is what makes the structure a
graph, not a tree.

**Back-edges / acyclicity.** If a surfaced sub-problem's signature matches a node that is
an **ancestor on the current DFS path**, the `seen` link is recorded as a *reference*:
the cursor does **not** descend into it (the ancestor is already being solved upstream);
the child instead takes the ancestor's eventual status. So although `seen` may link a
node to an ancestor, the subgraph the cursor actually traverses is acyclic — "DFS cannot
cycle" means exactly this, not that the link is forbidden.

**Propagation rule:** when a node's status changes to `solved` or `closed`, recompute
the status of **every** parent (not just the one DFS arrived from):

- an **approach (AND)** parent is `solved` only when its own `attempt_state` is
  `succeeded` *and every* child is `solved`; it is `closed` as soon as *any* required
  child is `closed` and cannot be revived (or its own attempt is blocked).
  **Promotion (required, else decomposing approaches never solve):** an approach that
  returned `surfaced` carries `attempt_state: inconclusive`. The moment its every
  surfaced child becomes `solved`, the orchestrator promotes it to `succeeded` — the
  surfaced attempt is precisely what *produced* those sub-problems, so solving all of
  them confirms the attempt. Only then does the AND-solve above fire.
- a **problem (OR)** parent is `solved` as soon as *any* of its children — which are
  approaches (§3) — is `solved`; it advances toward `closed` only when *all* children
  are `closed` (then the §4 re-expansion gate decides whether it truly closes). An
  `ask-user` child **never** counts as the solving child — its approval unblocks a
  sibling approach but is not itself a solution (see *The `ask-user` node*).

**Every closed node carries a `closure_basis` — including one closed by propagation.**
A node closed *because a child or its own attempt closed* does not inherit a basis for
free; the orchestrator **synthesizes** one and appends it to the ledger like any other:

- AND parent closed by a required child: `closure_basis = "required child <id> closed:
  <that child's basis>"`.
- OR parent closed after exhaustion: `closure_basis = "all children closed + §4
  re-expansion exhausted"`, enumerating the child bases.

This keeps the schema invariant ("required on every closed node") true for internal
nodes, so the rendered impossibility proof has a basis at every closed node, not just at
leaves.

Propagation is transitive — walk upward until no status changes. A memoized node solving
can therefore satisfy two approaches at once.

### Status semantics (single definition; reused by §3/§4/§7)

| status | meaning |
|---|---|
| `open` | created but not yet tried. Carries a `precondition` if something is gating it. |
| `active` | on the current DFS path. |
| `solved` | succeeded (approach) / has a solved child (problem). |
| `closed` | locally terminal *until undermined by a lead* (§6): out of approaches **and** a hard-wall `closure_basis` holds. |
| `reopened` | revived by a lead (§6); re-enters the frontier. Treated like `open` thereafter. |

There is **no separate `failed` status.** A **blocked attempt** is an approach node with
`status: "closed"` and the block recorded in `result`, plus a `closure_basis`. So a
blocked attempt counts toward a parent's "all children closed" trigger *and* every closed
node — attempt or problem — carries a `closure_basis` and contributes a lead to the
ledger. This is what keeps "all children closed" and ledger-learning firing for blocks.

### The `ask-user` node (bounds escape + cost escape)

`ask-user` is a third node `type`: a child created whenever the only way forward is
out of bounds (§2) or when ballooning cost/time needs a decision (§10). It is the one
construct that lets the search legitimately defer to the user instead of either crossing
a bound silently or quitting. Its `desc` states exactly what is being requested
(authorization to cross a named bound, or a budget/scope decision). Its lifecycle:

- **Pending** (`status: open`) — the request is recorded but unanswered. Like a problem
  node, an `ask-user` node sits on the frontier until resolved; the orchestrator surfaces
  its `desc` to the user.
- **Approved** → the granted authorization is merged into the root `bounds`, and the
  approach recorded in the node's **`gated_approach`** is **instantiated as a new `open`
  approach sibling** (now in-bounds and selectable) so DFS actually tries it. The
  `ask-user` node itself is marked `solved` only as "request resolved" — and `ask-user`
  nodes are **excluded from OR-solve propagation** (propagation rule above), so approval
  *never* marks the parent solved. Approval unblocks an approach; it does not achieve the
  goal. (Letting approval OR-solve the parent would declare the root solved before the
  authorized approach ever ran — a false success the carve-out prevents.)
- **Denied** → the node is `closed` with the hard-wall `closure_basis` *"authorization
  requested and denied"* (§7); it then counts toward its parent like any other closure.
- **User changed or stopped the goal** → this is not a node-level outcome but a
  whole-search one: set `terminal_state: user_redirected` and record `redirect` (below).

An `ask-user` node has `attempt_state: null` and `expansion_phase: null` — it is neither
an OR nor an AND, and has no children of its own; it carries its request payload in
`gated_approach` (the out-of-bounds approach to instantiate on approval).

### Frontier predicate (which nodes the cursor may select)

The DFS cursor selects the deepest **selectable** node, where selectable =

- `active` (already on the path), **or**
- `reopened` (revived by a lead — these MUST be selectable, else revival dead-ends),
  **or**
- `open` **with no unsatisfied `precondition`**.

An `open` node whose `precondition` is not yet satisfied is **dormant** — skipped by the
cursor — until a matching lead activates it (event-driven revival sets it `reopened` and
clears the gate, §6). This prevents trying an unexplored node before the knowledge its
`precondition` depends on exists.

### `expansion_phase` (problem nodes only)

Records which §4 re-expansion rung the node has reached, so a resumed session never
repeats or skips a rung:

```
children_open  ->  incontext_reexpanded  ->  fresheyes_reexpanded  ->  closed
```

- `children_open` — still has untried children, or has never hit local exhaustion.
- `incontext_reexpanded` — in-context re-generation has already run since the last
  exhaustion (don't repeat it; next rung is fresh-eyes).
- `fresheyes_reexpanded` — the fresh-eyes subagent has already run; the only remaining
  transition is `closed` (if still nothing new and a hard wall holds).

**A rung that adds new children resets `expansion_phase` to `children_open`** — a fresh
exhaustion generation. Otherwise the next exhaustion would resume at the *next* rung and
skip the cheap in-context re-generation on the newest closures, letting the node close
without mining its most recent learnings (contradicting §4). Only an exhaustion that
yields **no** new children advances the phase toward `closed`.

A lead that revives the node (§6) likewise resets `expansion_phase` to `children_open`,
because new knowledge can make earlier rungs productive again.

## `proof.md` rendering

The renderer selects on `terminal_state`; each state renders distinctly so a reader (or
a resuming session) can tell them apart at a glance:

- **`solved`** — the **solution path**: the AND-path of succeeding approaches from root
  to the success, each with the `result` that made it work.
- **`impossible`** — the **impossibility proof**: the closed graph, every closed node
  (leaf *and* internal) with its hard-wall `closure_basis`, and an explicit "global
  insight-sweep ran; nothing in the ledger revives any closed node" line (the
  all-knowledge certificate).
- **`user_redirected`** — an **audit record**: what was asked of the user (`redirect.asked`),
  the frontier node at the moment of redirect (`redirect.at_cursor`) and the surrounding
  open nodes, so the run is not mistaken for either active, solved, or impossible.

Never render an `impossible` proof while `terminal_state` is `none` — an in-progress
search has not earned the proof.

## Orchestration loop

The thin orchestrator owns `state.json` and the cursor; subagents do the work. One DFS
step:

1. **Select** the frontier node at `cursor` — the deepest **selectable** node in DFS
   order (selectable = `active` ∪ `reopened` ∪ `open`-with-satisfied-`precondition`; see
   *Frontier predicate* above).
2. **Initial expansion** (a problem node that has *never* been expanded — zero children,
   `expansion_phase: children_open`): dispatch a **node-expander** subagent (contract
   below) using the §4 catalog. Filter returned approaches through `bounds`; memoize via
   `seen` (link instead of duplicating a known signature). Persist. (Re-generating a node
   whose children are all *closed* is **not** this step — that is local exhaustion, step
   6, which obeys the `expansion_phase` ladder so a rung is never repeated or skipped.)
3. **Try** the next child approach: dispatch a **branch-trying** subagent. It returns
   `success`, `closed + basis`, or `surfaced sub-problems + leads`. Record the approach's
   own outcome in `attempt_state` (`succeeded` on success; `inconclusive` if it only
   surfaced sub-problems; the block sets `status: closed` for a block).
4. **Record.** Write the result onto the node; append any emitted leads to `ledger`
   (a closed node always emits its `closure_basis` as a lead), stamping each closed
   node's `closed_at_ledger_len` with the ledger length at closure. Run **event-driven
   revival** (§6): match each new lead — *only leads with index ≥ a node's
   `closed_at_ledger_len`*, so a node that re-closed on the same basis is not re-revived
   by an already-applied lead — against closed nodes' `closure_basis` and unexplored
   nodes' `precondition`; set matches to `reopened` and reset their `expansion_phase`.
   Revival **cascades upward**: reopening a node also reopens every ancestor whose
   `closure_basis` cited it (`"required child <id> closed: …"`), transitively, since
   that basis is now false. Persist.
5. **Propagate** solve/close to every parent (rule above). For each node closed by
   propagation: synthesize a `closure_basis`, **append it to the ledger first, then stamp
   `closed_at_ledger_len` = the resulting ledger length** — so a node is never revived by
   its own closure lead (internal closed nodes join revival/sweep, so they need the mark
   too; the same append-then-stamp order applies to the direct closure in step 4).
   Persist.
6. **Re-expand or backtrack.** If the current problem node just hit local exhaustion
   (all children `closed`), run **informed lazy re-expansion** *at this node, before
   moving the cursor*: run the rung named by `expansion_phase` — in-context generation
   fed by the closed children's bases, then the fresh-eyes subagent. **If the rung yields
   new children**, reset `expansion_phase` to `children_open` (progress — the ladder
   restarts) and return to step 3 at this node. **If it yields nothing**, advance one
   rung (`children_open → incontext_reexpanded → fresheyes_reexpanded`). Only after the
   **fresh-eyes** rung yields nothing — which advances the phase to `fresheyes_reexpanded`,
   leaving no rung left to run — does the node `close` (cursor backtracks to the next
   selectable node).
7. **Before the root closes:** run the **global insight-sweep** — re-apply the whole
   `ledger` to **every closed node (leaf *and* internal) and every dormant `open` node
   with an unsatisfied `precondition`**, matching each lead against both `closure_basis`
   and `precondition` (subject to each node's `closed_at_ledger_len` guard from step 4,
   so the sweep terminates). If anything revives, resume the loop. Only if nothing revives do
   you set `terminal_state = "impossible"` and render the proof. Scanning only closed
   *leaves* would let a satisfiable dormant node or an internal closed node escape the
   final check — reaching `impossible` without exhausting accumulated knowledge.

The loop also ends at `solved` (root solved) or `user_redirected` (user changed the goal
or stopped you) — set `terminal_state` and render accordingly.

## Subagent contracts

State both directions so bounds-filtering and failure-informed expansion are reproducible,
not implicit.

**Node-expander** (generate candidate approaches for a problem node):

- *Receives:* root `bounds`; the node `desc` + `signature`; the `closure_basis` and
  `result` of the node's already-closed children (so re-generation is informed by what
  failed); a relevant `ledger` excerpt.
- *Returns:* a list of candidate approaches, **each already filtered through `bounds`**
  (an out-of-bounds idea is returned only as an explicit `ask-user` child — `type:
  ask-user`, see *The `ask-user` node* — naming the authorization it needs and recording
  the idea itself in `gated_approach`). Empty list = "no new approach" (drives the next
  re-expansion rung or closure).

**Branch-trying** (attempt one approach):

- *Receives:* root `bounds`; the approach `desc` + its budget.
- *Returns:* exactly one of — `success` (+ the `result`; the orchestrator sets the
  approach's `attempt_state: succeeded`); `closed` (+ a hard-wall `closure_basis`,
  recorded with `status: closed`); or `surfaced` (+ the sub-problems it hit, each to
  become a child problem node, + any `leads` learned; `attempt_state: inconclusive` until
  those children resolve). Always returns the leads it learned, success or not.

## Resume procedure

A fresh session (after a usage limit, or a new invocation on the same goal):

1. Recompute `<task-slug>` from the goal; read `tmp/determined/<task-slug>/state.json`.
   Absent → this is a new search; start at step 1 of the loop with a root problem node.
2. If `terminal_state != "none"`, the search already ended — render/return the existing
   `proof.md` (or resume only if the user explicitly reopens it).
3. Otherwise re-establish the frontier from `cursor`. For the cursor's problem node, read
   `expansion_phase` to resume at the correct rung — e.g. `incontext_reexpanded` means
   in-context re-generation already ran, so go straight to the fresh-eyes rung. Continue
   the loop. No rung is repeated or skipped because the phase is persisted.

## Full worked example — auth issue in `foo`

Goal `find any authorization issue in component foo`; slug `find-any-authorization-issue-in-foo`.
Root `n0` (problem `auth-bypass-foo`) expands to four OR-children (§5). Two of them —
n1 (a) and n4 (d) — independently surface the **same** sub-problem "does `validate()`
cover all entry points?", so it is memoized once as **n6** and linked from both: a
single node with two parents, which is what exercises multi-parent propagation.

```
n0  problem  auth-bypass-foo                              [active]
├─ n1 approach  "(a) an entry point with no validator"          -> surfaced n6
├─ n2 approach  "(b) validator has a logic bug"                 [closed]
├─ n3 approach  "(c) validator is bypassable (order/TOCTOU)"    [closed]
├─ n4 approach  "(d) a sibling path reaches the resource"       -> surfaced n6 (memoized)
└─ n5 approach "audit for handlers registered outside the guarded router" (added by re-expansion)
        n6 problem  "does validate() cover all entry points?"  (parents: n1, n4)  [closed -> reopened -> solved]
```

Trace:

1. **n2** (validator logic bug): branch-trying subagent *attacks* `validate()`'s logic —
   every role, every input class, inverted/short-circuit/default-deny conditions — and
   disproves each bug hypothesis it can form (its own §4 re-expansion). Only then returns
   `closed`, `closure_basis: "validate() logic verified correct across all roles and
   input classes; bug hypotheses each disproved"`. Appended to the ledger.
2. **n3** (bypassable): subagent *attacks* ordering — every guarded handler checked for
   check-after-access, TOCTOU, and missing-case bypass; each invocation provably precedes
   resource access. Returns `closed`, `closure_basis: "every guarded handler calls
   validate() before touching the resource; ordering/TOCTOU bypasses disproved"`.
   Appended to the ledger. (n2 and n3 are the *tried-to-break-the-validator* branches —
   closing branch (a) on "validate() is always called" would prove nothing without them.)
3. **n1** (entry point with no validator) is an approach that *surfaces* a sub-problem:
   "does `validate()` cover all entry points?" Its signature
   `validate()-covers-all-entrypoints` is new, so it is created as **n6** and memoized in
   `seen`. n1 is an AND node: it succeeds only if n6 yields "no, some path is unguarded."
4. **n4** (sibling path) surfaces the *same* sub-problem. Its signature matches the
   memoized `validate()-covers-all-entrypoints`, so the orchestrator **links n6 as a child
   of n4** instead of creating a duplicate — n6 now has parents `[n1, n4]`.
5. **n6** is explored: a static scan of the router shows all *known* routes call
   `validate()`. Returns `closed`, `closure_basis: "all routes in the route table call
   validate()"`, `result` records the scanned table. Propagation closes **both** parents
   that required it — n1 and n4 — each with a synthesized basis ("required child n6
   closed: all routes in the route table call validate()"). Now n0's children are all
   closed → **local exhaustion**.
6. **Informed lazy re-expansion** at n0: the in-context rung, fed by the bases, asks
   "what do these failures *assume*?" — they all assume the **route table is complete**.
   It yields a new **approach n5** (an OR-child of n0): "audit for handlers registered
   outside the guarded router." Because the rung **produced a child**, `expansion_phase`
   **resets to `children_open`** (the ladder restarts: if n5 and any later children all
   close, in-context re-generation runs again on *their* learnings).
7. Trying **n5** (audit handlers outside the router) finds the admin/export handler
   registered directly on the server. This establishes a *fact* — admin/export sits
   outside the guarded router — but not yet that it bypasses *authorization* (that is
   n6's question), so n5 returns **inconclusive**, emitting lead **L1** (`source: "n5"`):
   "admin/export endpoint added in v3, not in the route guard list." (Had the audit
   itself proven the bypass, n5 would return `success` and solve n0 directly via
   `n0 → n5`; here it only surfaces the lead, so the solve routes through reviving n6.)
8. **Event-driven revival:** L1 (newer than n6's `closed_at_ledger_len`) is matched
   against closed nodes' bases. It *undermines* n6's basis ("all routes in the route
   table call validate()") — there is a handler not in the table. n6 → **reopened**,
   `expansion_phase` reset to `children_open`. **Upward cascade:** n1 and n4 were closed
   citing "required child n6 closed: …", so they reopen too.
9. Re-exploring n6 with L1 in hand confirms: the admin export path reaches the resource
   with no `validate()` call. **n6 solved** (`result: "admin/export bypasses validate()"`).
   Propagation: n6 was n1's only surfaced child, so the orchestrator **promotes n1's
   `attempt_state` inconclusive→succeeded**; with its attempt succeeded and its child
   solved, **n1 (AND) solves** (n4 likewise). Because n0 is OR, **n0 solves** the moment
   the first parent solves.
10. `terminal_state = "solved"`; `proof.md` renders the **solution path**:
    `n0 → n1 → n6` with the concrete bypass — a real authorization issue, found by
    refusing to accept n6's first closure.

Had L1 never surfaced and every branch stayed closed, step 8's revival would find
nothing; the orchestrator would run the **global insight-sweep** over the whole ledger
(against every closed node and every dormant precondition), and only then — nothing
revivable — set `terminal_state = "impossible"`. Note what that closure requires: n0's
*verified-exhausted* basis is **not** "every entry point calls `validate()`" — that
closes only branch (a). It is the conjunction of *all* branches closed on evidence: the
validator was attacked for a logic bug (n2) **and** for bypass/ordering (n3), **and**
every other route to the resource was ruled out (n4, n5). Closing one branch is never
closing the goal. The rendered proof lists *each closed node's* basis (leaf and
internal) plus the all-knowledge certificate, so "no issue found" means *the surface was
exhaustively closed — every way in tried*, not *the search gave up*.
