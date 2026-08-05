---
name: ripwire-write-tests
description: >
  Write tests for EXISTING code that has none — "this is untested, add coverage" / "what's missing a test
  here?". Different moment from judging your own diff (ripwire-change-check) or your own code's quality
  (ripwire-quality-bar): this is about FINDING what lacks a safety net and writing the test that closes the
  gap, before or without touching the code itself. Ranks candidates by `--seams` (untested cross-module call
  edges) and the `tested=1` coverage lens, gives you the symbol's outside contract via `--callers`, then verifies the
  new test actually registers with `--affected`. Backed by ripwire (deterministic, on PATH).
allowed-tools: Bash, Read
---

# Writing tests with ripwire

> Routing:
> • Vetting a diff you already wrote (does it have test cover) → **ripwire-change-check**.
> • Judging whether your OWN code got better/worse → **ripwire-quality-bar**.
> • Don't know which symbol is even the bug → **ripwire-find-bug**.
> • Not sure which skill? → **ripwire-router**.

`<dir>` = repo root. This skill answers "what should I write a test for, and what does it need to cover" —
not "is my diff safe" (that's change-check).

## Find the gap

1. **Untested integration seams** — `ripwire <dir> --seams` → `<seams>` lists cross-module call edges no
   test reaches. These are the highest-value targets: a bug here crosses a boundary silently, and one test
   per seam buys the most coverage per line written. Scope with `<dir>` = a subsystem to focus the seam list.
2. **The `tested=1` coverage lens** — `ripwire <dir> --metrics --top-k=50` (or `--for="<area>"`, which
   carries the same lens inline) → `tested="1"` means an indexed test-path symbol transitively reaches this
   production symbol. On these explicit metric surfaces the attribute is omitted when no indexed test
   reaches it; the binary never prints a fabricated zero. Cross an omitted `tested` with `in=` (fan-in): a
   widely-relied-on function with no indexed safety net is a sharper priority than an uncovered leaf.
   Shell/subprocess test coverage remains outside the call graph, so absence is a structural finding, not
   proof that no external test exists.
3. **Pick the target** — prefer a seam over a symbol lacking `tested=1` when both are candidates; a seam test
   proves two modules cooperate correctly, a unit test on one function does not.

## Write it with the right contract

4. **The contract from OUTSIDE** — `ripwire <dir> --callers=SYM` for the symbol you're testing. Callers show
   the preconditions and argument shapes callers actually rely on — write the test against that observed
   contract, not just the signature.
5. **The body, to know what branches exist** — `ripwire <dir> --expand=SYM` → full source + callee
   signatures. Cover the branches; don't just re-assert the happy path the caller already exercises.

## Verify the test actually registers

6. **Confirm it's wired in** — `ripwire <dir> --affected=<the file you just changed>` should now list your
   new test file among the tests that transitively reach the changed code. If it doesn't show up, the test
   harness isn't discovering the new file (wrong naming convention, missing registration) — fix that before
   trusting the coverage.
6b. **Read what an existing test already covers** — `ripwire <dir> --exercises=test/<harness>` lists the
   non-test symbols that test transitively calls into, ranked. Use it before writing anything to avoid
   re-covering ground a neighbouring harness already holds, and use it as the first call when an existing
   test FAILS and you only have its name. (A non-test path refuses — the verb is the test/non-test
   partition; for "what does this file call", use `--callees`.)
7. **Close the loop with the gate** — once `--affected` proves the test registers, `ripwire <dir> --test-gate`
   on the symbol's file should now go green (the symbol drops out of the untested-blast-radius list). This is
   the same TDAD-parity gate **ripwire-change-check** runs before merge — writing the test here is what makes
   it pass there.

## Output

Name the seam or symbol lacking `tested=1` chosen and why (seam > high-fan-in symbol > leaf), the contract drawn from
`--callers`, and confirmation from `--affected` that the new test registers. Re-run `--seams`/`--metrics`
afterward — the gap you targeted should be gone.
