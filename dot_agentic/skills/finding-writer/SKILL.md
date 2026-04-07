---
name: finding-writer
description: produce a structured research dossier that gives the human author of a security finding everything they need to write the final draft without further prompting or scrolling. use when turning raw issue notes, exploit evidence, code or configuration excerpts, and remediation ideas into a per-claim, self-contained, fully-sourced reference document covering correct state, current state, attack paths, and recommendations, with realistic severity, owasp or cis category mapping, an ascii attack-path diagram, a glossary of relevant terms, and a final internal-consistency pass. used for web application, api, and infrastructure security findings.
---

# Finding writer

## Purpose

This skill produces a **research dossier** that gives a human author everything they need to write a security finding *without further prompting and without scrolling around the document*. It is not a polished, ship-ready finding. The author handles voice, tone, and presentation when they write the final version.

The dossier is optimized for two things:

1. **Zero internal scrolling.** Every claim is self-contained. The reader never has to look elsewhere in the document to understand any single point.
2. **Defensible sourcing.** Every claim has at least one source attached, inline, at the point the claim is made.

Duplication is intentional and acceptable. Internal contradictions are not.

## Required output sections

Produce these sections in this exact order:

1. `# <Concise Finding Name> - [<severity>]`
2. `## Category`
3. `## Summary`
4. `## Glossary`
5. `## Correct State`
6. `## Current State`
7. `## Attack Paths`
8. `## Recommendations`
9. `## Gaps and Questions`
10. `## Consistency Notes`

Severity must be exactly one of: `0-Informational`, `1-Low`, `2-Medium`, `3-High`, `4-Critical`.

## The claim model

Most sections are written as a collection of **claims**. A claim is a self-contained card consisting of:

- **A terse statement** of one fact, definition, requirement, observation, analysis, or recommendation.
- **At least one source**, inline, immediately under the statement. Sources may be official documentation links, code references with exact `path:line-line` ranges, command output, configuration excerpts, HTTP transcripts, log extracts, or — for genuinely uncontroversial points — `common knowledge` with a one-line justification.
- **Optional nested context** explaining concepts the reader may not know, mechanics, examples, mitigating factors, or implications. Nested context lives *inside the claim*, not in a referenced section.

### Claim format

Use this shape, in markdown bullets:

````markdown
- **<terse statement of the claim>**
  - <plain-language explanation of any term in the statement that the reader may not know, in nested bullets>
  - <additional mechanics, context, or implications, if helpful>
  - Source: [<title of authoritative doc>](https://example.com) — <one line on what this source supports>
  - Source: `src/path/to/file.ext:42-58` — <one line on what this code shows>
    ```<lang>
    <inlined excerpt of the relevant code>
    ```
  - Source: command transcript
    ```
    $ <command>
    <output>
    ```
  - Mitigating factor: <if any, stated inline so the reader does not have to look elsewhere>
````

### Claim types and source standards

The required type of source depends on what the claim asserts. Use this table to decide what evidence each claim needs:

| Claim type | Where it usually appears | Required source |
|---|---|---|
| **Definitional** — explains what something is | Glossary, inline explanations | Official spec or vendor doc, or `common knowledge` with a one-line justification |
| **Normative** — states how something *should* behave | Correct State | Official vendor, standards-body, or framework documentation, linked inline |
| **Observational** — states what the tested system *actually does* | Current State | Exact `file:line` reference plus inlined excerpt, command output, configuration excerpt, HTTP transcript, screenshot placeholder, or log extract |
| **Analytical** — explains *why* an observation is wrong or exploitable | Current State, Attack Paths | The combination of normative and observational facts the analysis rests on, restated inline (not cross-referenced) |
| **Prescriptive** — states what to do to fix it | Recommendations | Official vendor or hardening guide for the recommended approach, linked inline |

If the strongest available source for a normative or prescriptive claim is a blog post, forum answer, or third-party tutorial, prefer to find a primary source or downgrade the claim's confidence wording. Do not present weak sources as authoritative.

## Self-contained claims

This is the most important rule and the one that distinguishes this skill from a normal finding template.

### No internal cross-references

- **Never** reference another claim, section, or appendix by ID, number, or "see above/below."
- The Glossary is the one structural exception: it exists for orientation, but no claim ever points the reader at it.
- Forward hints of the form "this is demonstrated in the next claim" are tolerable when used sparingly, because they do not force a scroll. Backward dependencies of the form "as discussed in claim 3" are not.
- Do not number claims. Numbering invites cross-references.

### Aggressive inlining

- If a claim depends on a code excerpt, paste the relevant lines *inside the claim* under the `Source:` line, even when another claim already uses the same file.
- If a claim depends on knowing what a protocol header, term, or mechanism means, explain it *inside the claim* in nested bullets, even if the Glossary covers the same term.
- If two claims need overlapping context, both claims get their own copy of that context, tailored to what each one specifically needs.
- The author will deduplicate when writing the final draft. The skill must not.

## The skim layer

The claim headlines carry the narrative. Every claim's bolded statement must be a complete declarative sentence that, when read in sequence with the other claim headlines in its section, forms a coherent story the reader can follow *without opening any of the nested context*.

This is the single rule that prevents the document from reading as a wall of disconnected cards. It has real consequences for how claims are phrased:

- **Every claim has two reading modes by design.** Skim mode: read only the bolded headline and understand the conclusion. Verify mode: read the nested context to see the proof and the surrounding mechanics. Both modes must work independently.
- **Headlines are full sentences, not labels.** Write `The auth middleware verifies the JWT signature but never reads the role claim from the payload` — not `JWT role claim check`. Labels force the reader to open the card to learn anything, which defeats the skim layer.
- **Headlines within a section must be orderable into a narrative.** When drafting a section, arrange the claims so that reading only their headlines top-to-bottom produces a coherent story. If two adjacent headlines could be swapped without changing the story, the story is too thin and either the claims themselves or their phrasing need work.
- **If a claim's headline cannot stand alone without the nested context, rewrite the headline, not the context.** Moving explanatory material up into the headline is fine. Making the headline dependent on the context beneath it is not.
- **Skim-mode coverage matters.** A reader who only reads the bolded lines across Correct State, Current State, Attack Paths, and Recommendations should come away with the finding's full story: what should be true, what is true, how that is exploitable, and what to do about it. If any of those four narrative beats goes missing at the headline level, the skim layer is incomplete.

The final consistency pass verifies that the skim layer actually holds.

## Section requirements

### Title line
- Concise finding name that accurately reflects the issue described in the body.
- Severity in the exact bracketed format: `[<value>]`.
- Finalize the title last, after the body is drafted, so it can reflect what the body actually shows.

### Category
- State whether the finding is web application or infrastructure related.
- Provide one best-fit category from the approved lists below.
- Add a second category only when one would be materially misleading on its own. Do not pad with every plausible mapping.

### Summary
- A single paragraph of plain prose, typically three to five sentences, giving the reader a 30-second orientation before they read the body.
- State, in order: what the issue is, what is wrong with the tested system, what the realistic impact is, and what direction the remediation takes.
- Do not enumerate every piece of evidence, list every recommendation, or try to substitute for the body. This is the elevator pitch, not a table of contents.
- Draft the Summary *after* the body sections are written, so it reflects what the body actually shows.
- The Summary is duplicative with content below; that is intentional. The final consistency pass verifies it does not contradict any claim.

### Glossary
- A short list of terms used elsewhere in this finding that a technical reader may not know.
- Each entry is its own claim card — terse definition, at least one source, optional nested context.
- Derive the Glossary *after* drafting the rest of the document, from terms that recur or that the author benefits from having defined in one place.
- Inline explanations inside other claims must remain consistent with Glossary entries, but they may be shorter or framed for the specific context the claim needs.
- The Glossary is not a dependency target. No claim ever tells the reader to "see the Glossary."

### Correct State
- Normative claims describing how the affected component or class of systems is supposed to behave.
- Each claim cites an official source inline.
- Where multiple correct implementations exist, focus on the one most relevant to this finding and briefly note the alternatives within the same claim or as separate claims.

### Current State
- Observational and analytical claims describing what the tested system actually does and why that is wrong.
- Every observational claim must include real evidence inline: file path with exact line range plus an inlined excerpt, command transcript, HTTP transcript, configuration excerpt, log extract, or — when evidence should exist but is not yet available — a clearly labeled placeholder showing what the author needs to capture during retest.
- Order claims so a reader moving top to bottom encounters concepts before claims that depend on them. If a later claim still needs a concept introduced earlier, restate the concept inline at the later claim too.
- Mitigating factors are stated inline at the claim they mitigate, not in a separate section.
- When the issue is currently a best-practice gap rather than directly exploitable, state that explicitly in the relevant claim.
- When a future change, additional access, or a chained weakness would make the issue more serious, label that clearly as potential rather than established.

### Attack Paths
- This section is not pure claims. It describes who can exploit the issue, under what preconditions, and through what sequence of actions.
- State the attacker profile (network position, authentication level, prior access) in plain language at the top of the section.
- Walk the exploitation sequence step by step. Each step that introduces a concept the reader may not know explains it inline.
- Include an ASCII diagram unless the issue is genuinely trivial. Choose the style that best fits — linear flow, sequence diagram, tree, or trust-boundary diagram.
- If multiple meaningfully different attack paths exist, walk each one independently. Do not cross-reference between them.
- If chaining with other findings is realistic, describe the chain inline, restating whatever facts the reader needs.

### Recommendations
- Prescriptive claims, each self-contained.
- Each recommendation states *what to do*, *why it works*, and *what wrong behavior it eliminates*, all inside the recommendation itself. The reader should not need to flip back to Current State to understand which problem a recommendation solves.
- Each recommendation cites an official remediation source inline whenever one exists.
- When multiple viable remediations exist, present them as separate claims and state the trade-offs inside each one. Use a table when the comparison is clearer in tabular form.

### Gaps and Questions
- Things the skill could not determine that the author must resolve before finalizing the finding.
- Examples: missing version information, untested adjacent endpoints, unverified mitigations, ambiguous evidence, conflicting documentation, conflicts between equally-strong sources.
- Each gap is a one-line statement of what is missing and why it matters, optionally with a suggestion for how the author can resolve it.
- This section is allowed to be empty, but if it is empty, say so explicitly.

### Consistency Notes
- The visible output of the final consistency pass (described below).
- If conflicts were found and resolved, list each conflict, the resolution, and the reason.
- If no conflicts were found, say so explicitly. Silence is ambiguous and the author has no way to tell whether the pass actually ran.

## Workflow

1. **Clarify** missing facts before drafting. Do not start writing if the minimum required facts to support a defensible finding are absent — ask the user instead.
2. **Identify** the issue type, affected technology, plausible attacker, preconditions, realistic impact, and available evidence.
3. **Classify** the finding as web application or infrastructure related and pick the best-fit category from the approved lists.
4. **Choose a severity** from the allowed values.
5. **Draft the claim sections** in this order: Correct State, Current State, Attack Paths, Recommendations. While drafting:
   - Write each claim's headline as a complete declarative sentence that stands on its own.
   - Order claims within each section so concepts are introduced before they are used, and so the bolded headlines read in sequence form a coherent narrative.
   - Inline every concept explanation each claim needs.
   - Inline every evidence excerpt.
   - Cite sources inline at the point of every claim.
   - Note any gaps as you go, so you can collect them later.
   - Do not write any internal cross-references and do not number claims.
6. **Derive the Glossary** from terms that recur across the drafted claims or that benefit from a single canonical definition.
7. **Draft the Summary** as a single orientation paragraph reflecting what the body now shows.
8. **Collect Gaps and Questions** the author still needs to resolve.
9. **Run the consistency pass** (see below) and write the Consistency Notes section based on its results.
10. **Finalize the title** so it accurately reflects the body.

## Consistency pass

Run this as the *last* step, after every other section is drafted. Its purpose is to find and resolve internal contradictions. **Do not collapse, merge, or remove duplicated content** — duplication is intentional. Only resolve actual conflicts.

Walk this checklist explicitly:

- **Summary–body consistency.** Does anything in the Summary contradict a claim in the body? If yes, fix the side with the weaker source. The Summary is duplicative on purpose, but it must not disagree with the claims it is summarizing.
- **Skim-layer coherence.** Read only the bolded claim headlines in each section, top to bottom. Do they form a coherent narrative on their own? If a section reads as a disjointed list at the headline level, rewrite the headlines (not the bodies) until it does not. Also check coverage: do the headlines across Correct State, Current State, Attack Paths, and Recommendations, read alone, convey what should be true, what is true, how it is exploitable, and what to do about it?
- **Definitional consistency.** Do all inline explanations of each concept agree with each other and with the Glossary entry, if any?
- **Technical claim consistency.** Do all references to versions, defaults, protocol behavior, and vendor-specific details agree across claims?
- **Severity and impact consistency.** Do Current State, Attack Paths, and Recommendations agree on how serious this finding is and what it allows an attacker to do?
- **Recommendation consistency.** Are any two recommendations mutually exclusive without an explicit "choose one" framing?
- **Evidence interpretation consistency.** When two claims cite the same evidence, do they characterize what it shows the same way?
- **Mitigation consistency.** Do mitigating factors stated in Current State match the preconditions assumed by Attack Paths?

When a conflict is found, the version with the stronger source wins; correct the others to match. If the sources are equally strong, do not guess — record the conflict in **Gaps and Questions** and ask the author to decide.

The Consistency Notes section is the visible trace of this pass. List every resolution and its justification, or state explicitly that no conflicts were found.

## Approved category mappings

### Web application categories
Prefer the single most specific category from these lists:

- A01:2025 - Broken Access Control
- A02:2025 - Security Misconfiguration
- A03:2025 - Software Supply Chain Failures
- A04:2025 - Cryptographic Failures
- A05:2025 - Injection
- A06:2025 - Insecure Design
- A07:2025 - Authentication Failures
- A08:2025 - Software and Data Integrity Failures
- A09:2025 - Security Logging and Alerting Failures
- A10:2025 - Mishandling of Exceptional Conditions
- API1:2023 - Broken Object Level Authorization
- API2:2023 - Broken Authentication
- API3:2023 - Broken Object Property Level Authorization
- API4:2023 - Unrestricted Resource Consumption
- API5:2023 - Broken Function Level Authorization
- API6:2023 - Unrestricted Access to Sensitive Business Flows
- API7:2023 - Server Side Request Forgery
- API8:2023 - Security Misconfiguration
- API9:2023 - Improper Inventory Management
- API10:2023 - Unsafe Consumption of APIs

When a finding is clearly API-specific, prefer the best-fitting API category over a broader OWASP web category.

### Infrastructure categories
Prefer the single most relevant CIS Control. Add a second control only when it adds real explanatory value.

- CIS Control 1: Inventory and Control of Hardware Assets
- CIS Control 2: Inventory and Control of Software Assets
- CIS Control 3: Data Protection
- CIS Control 4: Secure Configuration of Enterprise Assets and Software
- CIS Control 5: Account Management
- CIS Control 6: Access Control Management
- CIS Control 7: Continuous Vulnerability Management
- CIS Control 8: Audit Log Management
- CIS Control 9: Email Web Browser and Protections
- CIS Control 10: Malware Defences
- CIS Control 11: Data Recovery
- CIS Control 12: Network Infrastructure Management
- CIS Control 13: Network Monitoring and Defence
- CIS Control 14: Security Awareness and Skills Training
- CIS Control 15: Service Provider Management
- CIS Control 16: Application Software Security
- CIS Control 17: Incident Response Management
- CIS Control 18: Penetration Testing

## Evidence guidance

Use whichever proof format best fits the issue:

- Code excerpts with exact `file:line-line` references — preferred for source code findings
- HTTP request and response pairs
- CLI commands and output
- Configuration snippets
- Architecture, sequence, or trust-boundary ASCII diagrams
- Log extracts
- Tables when they organize comparisons or evidence summaries more clearly than prose
- Placeholder proof blocks when evidence should exist but is not yet available

When citing code, use the narrowest defensible reference. Prefer exact file path with exact line range whenever possible. If exact line numbers are not available, say so clearly and use the smallest defensible reference, such as a function name, class name, route name, or commit hash.

Placeholder evidence must be obviously labeled, for example:

```text
[Placeholder evidence — to be captured during retest]
$ openssl s_client -connect example.internal:443 -tls1
CONNECTED(00000003)
Protocol  : TLSv1
Cipher    : ECDHE-RSA-AES256-SHA
Verify return code: 0 (ok)
```

## Acronym handling

Expand standard acronyms on first use *within each claim that introduces them*, then use the acronym for the rest of that claim. Because claims are self-contained, the same acronym may be expanded multiple times across the document — that is correct, not a bug. Examples of the expected form:

- `SSRF (Server-Side Request Forgery)`
- `TLS (Transport Layer Security)`
- `IAM (Identity and Access Management)`
- `JWT (JSON Web Token)`

## Quality bar

Before finalizing, verify that the dossier:

- follows the required section order
- uses one of the allowed severity values and a category from the approved lists
- includes a Summary that orients the reader in three to five sentences without contradicting any claim in the body
- has claim headlines that are complete declarative sentences and read as a coherent narrative when skimmed alone in section order
- contains no internal cross-references between claims and no claim numbering
- has at least one inline source on every claim
- inlines code excerpts, transcripts, and concept explanations rather than referring out to other parts of the document
- distinguishes established facts from conditional or future risk
- includes an ASCII diagram in Attack Paths unless the issue is genuinely trivial
- includes Gaps and Questions for anything the author still needs to resolve, or explicitly states that none exist
- includes Consistency Notes recording the result of the final consistency pass
- contains no contradictions across claims, even where content is duplicated
- expands standard acronyms on first use within each claim that introduces them
- makes only claims that the available evidence supports, and labels potential or future risks clearly as such
