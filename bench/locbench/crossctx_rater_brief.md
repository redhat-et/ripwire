# Rater brief — locality of a defect fix

You are rating ONE packet: a reported issue, the patch that fixed it, and the pre-fix text of the code
definitions that patch touched. Answer the four questions below and return ONE JSON object in the schema
at the end. You will not be shown any other packet, any other rater's answer, or any aggregate.

## What a site is

A **site** is `(file, definition)` in the repository at the pre-fix commit, where *definition* is the
outermost function-level definition enclosing a line: a module-level `def`, or a `Class.method`. A nested
`def` belongs to the function that contains it. Lines inside a `class` body but outside any method are the
site `(file, Class)`. Lines outside every definition are `(file, <module>)`. A file in a language other
than Python is one site `(file, <file>)`. Spell a site as `path:definition` — `pkg/mod.py:Widget.size`,
`pkg/mod.py:helper`, `pkg/mod.py:<module>`.

## The unit you are rating

One issue plus the accepted fix. The **primary site** is the site whose pre-fix code was wrong.

## The question: LOCAL or CROSS-CONTEXT

Apply this **quote test**:

> To justify the fix to a colleague, what would you have to quote? If the primary site's pre-fix text,
> the language's semantics and the issue's symptom are enough, the defect is **LOCAL**. If you would have
> to quote text from a **second site** — a callee's or caller's contract, a table, enum, constant or format
> defined elsewhere, a sibling that must agree, a schema or configuration, a registration, a test whose
> assertion did not exercise the claim — the defect is **CROSS**, and you name that second site.

The second site must be a site **in the repository at the pre-fix commit**, spelled `path:definition`, and
it must be a different site from the primary one. A contract that lives only outside the repository (a
third-party library's behaviour, an HTTP API, a language-version change) does not make a defect CROSS: answer
`LOCAL` and set `external_contract` to true.

Answer **UNDECIDED** if you cannot decide within the budget below. Answer **NOT-A-DEFECT** if the change is a
feature, a documentation-only change, or a refactor with no wrong behaviour named in the issue.

## Reading the repository

You may read the repository at the pre-fix commit, read-only, with exactly these three commands, and nothing
else: `ls-tree` (list a directory), `show <path>` (read a file), `grep <pattern>` (search the tree). Every
read is logged. Budget: **at most 25 reads** and **at most 1,500 output tokens** for this packet; if you
exceed either, your answer is recorded as UNDECIDED. You have no network access. Do not try to identify the
project's issue tracker, the fix commit or its pull request; rate what is in front of you.

## The four questions

1. **Primary site.** Which site in the packet's list holds the pre-fix code that was wrong? One site, spelled
   `path:definition`; or null with verdict `NOT-A-DEFECT`.
2. **Quote test.** To justify the fix, would you have to quote only the primary site's pre-fix text (plus the
   language and the issue's symptom), or text from a second site as well? → `LOCAL` / `CROSS`.
3. **If CROSS:** name the second site (`path:definition`, existing at the pre-fix commit, different from the
   primary site) and pick one relation: `caller-callee-contract` · `table-roster-registration` ·
   `constant-format-schema-elsewhere` · `sibling-or-clone-must-agree` · `mirror-parity-copy` ·
   `test-not-exercising-claim` · `other`.
4. **Confidence:** `sure` or `unsure`.

## Output — one JSON object, nothing else

```json
{
  "packet_index": 0,
  "primary_site": "path:definition or null",
  "verdict": "LOCAL | CROSS | UNDECIDED | NOT-A-DEFECT",
  "second_site": "path:definition when CROSS, else null",
  "relation": "one of the seven relations when CROSS, else null",
  "external_contract": false,
  "confidence": "sure | unsure",
  "tool_calls": 0,
  "output_tokens": 0,
  "note": ""
}
```
