# Maintaining this skill

**Read this when editing the skill, NOT during a review.** It is the discipline for evolving
`custom-review` without re-accumulating debt. The skill once grew by pure accretion — every lesson
appended a bug-pattern, a failure-mode, and a preflight question, and nothing was ever merged or
retired. It has since been restructured around **five root review primitives** (see
`review-primitives.md`): *Trace, don't skim* / *Diff the siblings* / *Probe the negative space* /
*Follow the async lifetime* / *Distrust the narrative*. These rules keep it that way.

## The governing rule: a new learning is an instance under a root

When a review round surfaces a new lesson, do **not** reach for a new top-level pattern, mode, or
preflight question. Instead:

1. **Find its root.** Which of the five primitives is this lesson an instance of? (Almost everything
   is — guard-parity is *Diff the siblings*; a discarded return value is *Trace*; a boot/attach
   false-zero is *Probe the negative space*.)
2. **Add it as an instance** under that root in `review-primitives.md`: a short titled bullet with one
   realistic example and a search target. Extend the root's **Failure signature** if the lesson names
   a new way to skip that root.
3. **Touch nothing else.** The preflight stays at the five roots + evidence discipline; it does not
   grow per learning. The class-triggered lookup gains a row only for a genuinely new change-class.

A **new root** is a once-in-a-long-while event: justified only when a lesson is a detection *lens*
none of the five cover (not merely a new example of an existing one). Adding a sixth root is a
deliberate restructuring decision, not a default.

## Put weight where it's cheap

- **Cheap to grow — `review-primitives.md`.** Class-gated: a review reads only the 2–3 roots its
  change touches. Adding an instance under a root costs almost nothing per review. This is the home
  for nearly every new learning.
- **Expensive to grow — `SKILL.md`, `notes-file.md`, `output-format.md`.** These are read whole on
  every review. A learning earns a line here only if it changes the *workflow*, the *notes contract*,
  or the *output discipline* for every review — not because it's a new thing to look for. When in
  doubt, it belongs under a root in `review-primitives.md`.

## Merge or retire — don't only append

Instances and roots are **budgets, not free space**. Before adding:

- Is this a new facet of an existing instance? Strengthen that instance instead of adding one.
- Does it overlap a sibling instance? Cross-link by name, or merge.
- If a class of bug has stopped recurring, fold its instance back into the root's general statement.

If a worked example already lives elsewhere, point to it by name; do not restate it.

## Keep it generic and standalone

Examples use **realistic names but no provenance** — no PR / run / ticket / tool references, no "caught
by X", no "n=N across …". The skill reads as standalone craft, not a changelog of where each rule came
from. Provenance, if it matters, lives outside the skill (e.g. the A/B comparison log). A reader
applying this skill to an unrelated codebase must never be sent chasing a reference that means nothing
to them.

## Single source of truth

When a concept is used in more than one file, define it **once** and link to it by name (not by a
fragile number):

- The **detection spine** is the five roots in `review-primitives.md`. `SKILL.md` (steps 2/6/9 and the
  preflight) and `notes-file.md` (candidate `<class>` tokens) point to the roots; they do not restate
  the instances.
- Severity **tiers** (with floors/ceilings) are defined only in `output-format.md` § *Severity rubric*.
  `SKILL.md` and `notes-file.md` list the tier tokens for fill-in but point there for meaning.
- Canonical **finding-shape examples** (producer-claim sentence, claim-vs-reality sentence,
  render-proof line) live in `output-format.md` § *Finding shape*; `SKILL.md`'s promotion rules point
  to them. The finding shapes are the *output* discipline and align to roots (producer-claim & render
  proof → *Trace*; claim-vs-reality → *Distrust the narrative*) but are kept separate from detection.

If you change a definition, change it at the source; the by-name pointers stay valid automatically.
