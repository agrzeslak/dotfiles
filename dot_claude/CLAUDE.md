## General best practices

- Run shell scripts through shellcheck.
- Use `tmp/` (project-local) for intermediate files and comparison artifacts, not `/tmp`. This keeps
  outputs discoverable and project-scoped, and avoids requesting permissions for `/tmp`.

### SESSION.md

While working, if you come across any bugs, missing features, or other oddities about the
implementation, structure, or workflow, **add a concise description of them to SESSION.md** to defer
solving such incidental tasks until later. You do not need to fix them all straight away unless they
block your progress; writing them down is often sufficient. **Do not write your accomplishments into
this file.**

## Rust guidelines

- When adding dependencies to Rust projects, use `cargo add`.
- In code that uses `eyre` or `anyhow` `Result`s, consistently use `.context()` prior to every
  error-propagation with `?`. Context messages in `.context` should be simple present tense, such as
  to complete the sentence "while attempting to ...".
- Prefer `expect()` over `unwrap()`. The `expect` message should be very concise, and should explain
  why that expect call cannot fail.
- When designing `pub` or crate-wide Rust APIs, consult the checklist in
  <https://rust-lang.github.io/api-guidelines/checklist.html>.
- For ad-hoc debugging, create a temporary Rust example in `examples/` and run it with
  `cargo run --example <name>`. Remove the example after use.

### Useful Rust frameworks for testing

- **`quickcheck`**: Property-based testing for when you have an obviously-correct comparison you can
  test against.
- **`insta`**: Snapshot testing for regression prevention. Use `cargo insta test` as a stand-in for
  `cargo test` to run the snapshot tests.

### Writing compile_fail Tests

Use `compile_fail` doctests to verify when certain code should _not_ compile, such as for type-state
patterns or trait-based enforcement. Each `compile_fail` test should target a specific error
condition since the doctest only has a binary output of whether it fails to compile, not the many
reasons _why_. Make sure you clearly explain exactly WHY the code should fail to compile.

If there is no obvious item to add the doctest to, create a new private item with
`#[allow(dead_code)]` that you add the compile-fail tests to. Document that that's its purpose.

Before committing, create a temporary example file for each compile-fail test and check the output
of `cargo run --example <name>` to ensure it fails for the correct reason. Remove the temporary
example after.

## Git workflow

Use the `commit-writer` skill, if available, to draft commit messages. It reads the current diff and
produces a message following the conventions below.

Make sure you use git mv to move any files that are already checked into git.

When writing commit messages, ensure that you explain any non-obvious trade-offs we've made in the
design or implementation.

Wrap any prose (but not code) in the commit message to match git commit conventions, including the
title. Also, follow semantic commit conventions for the commit title.

When you refer to types or very short code snippets, place them in backticks. When you have a full
line of code or more than one line of code, put them in indented code blocks.

## Documentation preferences

### Documentation examples

- Use realistic names for types and variables.

## Code style preferences

Document when you have intentionally omitted code that the reader might otherwise expect to be
present.

Add TODO comments for features or nuances that were deemed not important to add, support, or
implement right away.

### Literate Programming

Apply literate programming principles to make code self-documenting and maintainable across all
languages:

#### Core Principles

1. **Explain the Why, Not Just the What**: Focus on business logic, design decisions, and reasoning
   rather than describing what the code obviously does.

2. **Top-Down Narrative Flow**: Structure code to read like a story with clear sections that build
   logically:

   ```rust
   // ==============================================================================
   // Plugin Configuration Extraction
   // ==============================================================================

   // First, we extract plugin metadata from Cargo.toml to determine
   // what files we need to build and where to put them.
   ```

3. **Inline Context**: Place explanatory comments immediately before relevant code blocks,
   explaining the purpose and any important considerations:

   ```python
   # Convert timestamps to UTC for consistent comparison across time zones.
   # This prevents edge cases where local time changes affect rebuild detection.
   utc_timestamp = datetime.utcfromtimestamp(file_stat.st_mtime)
   ```

4. **Avoid Over-Abstraction**: Prefer clear, well-documented inline code over excessive function
   decomposition when logic is sequential and context-dependent. Functions should serve genuine
   reusability, not just file organization.

5. **Self-Contained When Practical**: Reduce dependencies on external shared utilities when the
   logic is straightforward enough to inline with good documentation.

#### Implementation Benefits

- **Maintainability**: Future developers can quickly understand both implementation and design
  rationale
- **Debugging**: When code fails, documentation helps identify which logical step failed and why
- **Knowledge Transfer**: Code serves as documentation of the problem domain, not just the solution
- **Reduced Cognitive Load**: Readers don't need to mentally reconstruct the author's reasoning

#### When to Apply

Use literate programming for:

- Complex algorithms with multiple phases or decision points
- Code implementing business logic rather than simple plumbing
- Code where the "why" is not immediately obvious from the "what"
- Integration points between systems where context matters

Avoid over-documenting:

- Simple utility functions where intent is clear from the signature
- Trivial getters/setters or obvious wrapper code
- Code that's primarily syntactic sugar over well-known patterns

## Claude Code sandbox insights

### Pipe workaround (trailing `;`)

The sandbox has a [known issue][cc-16305] where data is silently dropped in shell pipes between
commands. Appending a trailing `;` to the command fixes this:

```sh
# Broken (downstream receives no input):
diff <(jq -S . a.json) <(jq -S . b.json)

# Fixed — append `;`:
diff <(jq -S . a.json) <(jq -S . b.json);
echo "abc" | grep "abc";
```

This affects pipes (`|`), process substitution (`<(...)`), and any command that connects stdout of
one process to stdin of another.

[cc-16305]: https://github.com/anthropics/claude-code/issues/16305

### `!` (negation) workaround

The sandbox has a [separate bug][cc-24136] where the bash `!` keyword (pipeline negation operator)
is treated as a literal command name. The command after `!` **never executes**. This affects `if !`,
`while !`, and bare `!`. The trailing-`;` workaround does **not** fix this.

```sh
# Broken:
if ! some_command; then handle_failure; fi

# Workaround — capture $?:
some_command; rc=$?
if [ "$rc" -ne 0 ]; then handle_failure; fi

# Broken:
while ! some_command; do sleep 1; done

# Workaround — use `until`:
until some_command; do sleep 1; done
```

[cc-24136]: https://github.com/anthropics/claude-code/issues/24136

### Unsandboxable commands

The following commands can never be run successfully inside the sandbox, and thus must always be run
with `dangerouslyDisableSandbox: true`. Because they cannot be run inside the sandbox, avoid running
them in bash invocations with other commands (e.g., using `|`, `&&` or `||`). Instead, capture their
output to a file, and then operate on that file in subsequent commands, which can then be sandboxed.

Known unsandboxable commands are:

- `gh`
- `perf record` (but _not_ `perf script`)

### Sandbox discipline

Never use `dangerouslyDisableSandbox` preemptively. Always attempt commands in the default sandbox
first. Only bypass the sandbox after observing an actual permission error, and document which error
triggered the bypass. The standing exceptions are the commands known to be unsandboxable.

### Prefer temp files over pipes for sub-agent CLI testing

When testing a CLI with ad-hoc input, write the input to a temp file in `tmp/` using the Write tool
(not `cat`/`echo` with heredoc + `>`), then pass it by path rather than piping. This avoids
interactive permission prompts in sub-agents.

# Common failure modes when helping

## The XY Problem

The XY problem occurs when someone asks about their attempted solution (Y) instead of their actual
underlying problem (X).

### The Pattern

1. User wants to accomplish goal X
2. User thinks Y is the best approach to solve X
3. User asks specifically about Y, not X
4. Helper becomes confused by the odd/narrow request
5. Time is wasted on suboptimal solutions

### Warning Signs to Watch For

- Focus on a specific technical method without explaining why
- Resistance to providing broader context when asked
- Rejecting alternative approaches outright
- Questions that seem oddly narrow or convoluted
- "How do I get the last 3 characters of a filename?" (when they want file extension)

### How to Avoid It (As Helper)

- **Ask probing questions**: "What are you trying to accomplish overall?"
- **Request context**: "Can you explain the bigger picture?"
- **Challenge assumptions**: "Why do you think this approach will work?"
- **Offer alternatives**: "Have you considered...?"

### Red Flags in User Requests

- Very specific technical questions without motivation
- Unusual or roundabout approaches to common problems
- Dismissal of "why do you want to do that?" questions
- Focus on implementation details before problem definition

### Key Principle

Always try to understand the fundamental problem (X) before helping with the proposed solution (Y).
The user's approach may not be optimal or may indicate they're solving the wrong problem entirely.

## Code Review Process

### Review workflow

For non-trivial behavioral changes, follow this order:

1. Identify the feature or contract being changed.
2. State the key behavioral claims the change makes — what will the user now believe?
3. Enumerate the top 3 ways those claims could still be false.
4. Trace the data flow end-to-end for each claim: producer → storage → transport → rendering.
5. Search for all dependents and sibling code paths that should have changed but didn't.
6. Only then review the fine details of implementation and tests.
7. Split findings into: blocking correctness bugs, medium-risk semantic gaps, optional polish.

### Core review questions

- What user-visible behavior is supposed to change?
- What values are now the source of truth?
- What other code already depended on the old behavior or old data shape?
- If a new branch/early-return was added, which old inputs now hit it by accident?
- If a new helper/endpoint/category was added, which existing producers/consumers are now
  incomplete?
- If code uses async cancellation (sequence counters, AbortController, request IDs), does every
  invalidating event — not just replacement requests — advance or cancel the token?
- After adding or modifying persistent state for a workflow (path search, filters, selection), what
  are the top 3 follow-up actions on the same page? For each: does the current state still make
  sense, and does any in-flight async work need to be invalidated?

### Prioritization

1. Does this make the UI say something false to the user?
2. Does this cause a real workflow to break?
3. Does this create a silent mismatch between layers?
4. Does this only affect cleanliness, consistency, or future-proofing?

Items 1-3 are review gold. Item 4 is optional unless no real bugs exist.

### Anti-patterns

- Letting local validation substitute for completeness review. "The code that was added appears
  correct" is not the same question as "what else should have changed but didn't?"
- Writing findings about API consumer behavior without verifying the API's actual contract. Read
  existing tests, docs, and producer code together — tests alone may encode a regression.
- Ranking low-risk style observations at the same level as user-facing semantic bugs.
- Treating "are there tests?" as sufficient. Instead ask: do the tests encode the right behavior,
  and does the test fixture accidentally make the bug impossible?
- Verifying a refactor preserves success-path behavior without diffing error-path and loading-state
  behavior between old and new code. Component extractions commonly drop error conditionals that
  were inline in the original.
- Verifying a component extraction preserves rendering behavior without diffing query enablement
  conditions. When data-fetching logic moves into a reusable component, mount-time side effects
  (queries, subscriptions) may fire that were previously suppressed by page-level state. For every
  extracted data-fetching component, check: when does it query on mount, what suppresses querying,
  and whether those suppressors existed in the caller before extraction.

### Default searches for non-trivial behavioral changes

1. All consumers of any new exported hook/helper/type.
2. All producers/emitters of any semantic family the change classifies (edge types, right names,
   statuses, entity types).
3. All alternate code paths and modes for the same feature.
