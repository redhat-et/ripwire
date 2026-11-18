---
name: ripwire-write-tests
description: >
  Write tests for EXISTING code that has none — 'this is untested, add coverage', 'add a safety
  net first'; also verify a new test reaches its intended code. Finds what no test reaches: --seams
  ranks untested cross-module edges, --callers gives the outside contract. Diff test selection →
  change-check. For one target one --seams or --callers pass suffices.
allowed-tools: Bash, Read
---

# Writing tests with ripwire

> Routing: vetting a diff you already wrote (does it have test cover) → **ripwire-change-check** · judging whether
> your OWN code got better/worse → **ripwire-quality-bar** · don't know which symbol is even the bug →
> **ripwire-find-bug** · unsure → **ripwire-router**.

`<dir>` = repo root (or a subsystem, to focus the list). This skill answers "what should I write a test for, and
what does it need to cover" — not "is my diff safe".

## The recipe

1. **Find the gap** — `ripwire <dir> --seams --legend=compact` lists cross-module call edges no test reaches: the
   highest-value targets (one test per seam buys the most coverage per line). Prefer a seam over a lone symbol; a
   widely relied-on symbol with no `tested="1"` beats an uncovered leaf (`--metrics` shows the lens, `in=` the fan-in).
2. **The contract from OUTSIDE** — `ripwire <dir> --callers=SYM --legend=compact`: the preconditions and argument
   shapes callers actually rely on. Then `ripwire <dir> --expand=SYM --legend=compact` to see which branches exist —
   cover them, not only the happy path.
3. **Verify it registers** — `ripwire <dir> --affected=<the file you just changed> --legend=compact` must now list
   your new test file. If it doesn't, the harness is not discovering it (naming, registration) — fix that first.
   To see what an existing test already covers (or the first call when a test fails and you only have its name):
   `ripwire <dir> --exercises=test/<harness> --legend=compact`.
4. **Close the loop** — `ripwire <dir> --test-gate --legend=compact` on the symbol's file goes green once the symbol
   leaves the untested blast radius.

## Stop rule and trust

For one target, one `--seams` or `--callers` pass suffices — then write the test. `tested` is omitted, never a
fabricated zero, when no indexed test reaches a symbol; shell/subprocess tests sit outside the call graph, so an
absence is a structural finding, not proof that no test exists.

## Reference file

`write-tests-reference.md` — each step in full, the `tested=1` lens, `--exercises`, and the Output shape.
