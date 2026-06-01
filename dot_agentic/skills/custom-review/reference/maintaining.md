# Maintaining this skill

**Read this when editing the skill, NOT during a review.** It is the discipline for evolving
`custom-review` without re-accumulating the bloat a prior cleanup removed. The skill grew by pure
accretion — every lesson appended a pattern, a mode, or a preflight question, and nothing was ever
merged or retired. These rules are the counter-force.

## Know the two read-paths — put weight where it's cheap

- **Cheap to grow — `bug-patterns.md`.** Class-gated: a review reads only the 2–4 patterns its change
  touches. Adding pattern #N costs almost nothing per review. **This is the default home for a new
  learning.**
- **Expensive to grow — `SKILL.md`, `notes-file.md`, `output-format.md`, and the `claude-failure-modes.md`
  table.** `SKILL.md` and `notes-file.md` and `output-format.md` are read whole every review; the
  failure-mode *table* is run down on every promotion. Every line added here is paid on every review,
  forever, and dilutes the high-value rules around it.

A new learning earns a slot in an expensive file **only if it is a genuinely cross-cutting gate** —
something that changes how *every* candidate is judged. Otherwise it is a bug-pattern. When in doubt,
it is a bug-pattern.

## Merge or retire — don't only append

Adding a pattern / mode / preflight question is an invitation to fold a stale or overlapping one out.
The pattern count, the mode count, and the preflight length are **budgets, not free space**. Before
adding:

- Is this a new facet of an existing pattern? Strengthen that pattern instead of adding a new one.
- Does it overlap a sibling pattern? Cross-link them, or merge.
- If a class of bug has stopped recurring, retire its dedicated pattern back into a more general one.

A worked example already lives in another reference's pattern? Point to it; do not restate it.

## Keep it generic and standalone

Examples use **realistic names but no provenance** — no PR / run / ticket / tool references, no "caught
by X", no "n=N across …". The skill should read as standalone craft, not a changelog of where each
rule came from. If provenance matters, it lives outside the skill (e.g. the A/B comparison log), never
inside it. A reader applying this skill to an unrelated codebase must never be sent chasing a reference
that means nothing to them.

## Single source of truth

When a concept is used in more than one file, define it **once** and link to it:

- Severity **tiers** (with floors/ceilings) are defined only in `output-format.md` § *Severity rubric*.
  `SKILL.md` and `notes-file.md` list the tier tokens for fill-in but point there for meaning.
- Canonical **finding-shape examples** (producer-claim sentence, claim-vs-reality sentence,
  render-proof line) live in `output-format.md` § *Finding shape*. `SKILL.md`'s promotion rules point
  to them rather than restating the example verbatim.

If you change a definition, change it at the source; the pointers stay valid automatically.
