# ripwire-quality-bar — reference: playbook (read on demand; the recipe is in SKILL.md)

## The shape → refactor playbook

The table above maps a *regression kind* to a direction. This maps a **measured shape** to the **named
refactor** and — the part agents skip — that refactor's **precondition**. Same doctrine as everything else
here: these are facts plus options, never verdicts. The tool measures the shape; which option is right is
still your call, and "leave it alone" is always on the menu.

| Measured shape | The named fix | Its precondition — check this FIRST |
|---|---|---|
| **Many shallow humps** — `humps` high, `deep/humps` small, `deep/loc` low | **Extract each hump.** The bumpy-road fix: every region that rises to the bar and falls back is one missing abstraction with its own name. Cheap, mechanical, one hump at a time. | Nothing structural blocks it — but each extraction is a new symbol, so re-run the loop below: extraction that lands as `origin="new-symbol"` `api-surface` debt should be file-local, not public. |
| **One deep tangle** — `humps=1` (or few) with high `deep/loc` | **Guard-clause inversion**, then **state extraction**: invert the conditions that hold the depth, return early, and lift the sustained region's working set into a named struct or its own function. Expensive and genuinely risky — a rewrite, not a move. | `locals=` tells you what you're really moving; a big `locals` means the region's working set, not just its braces, has to travel. Check `--callers=SYM`/`--impact=SYM` before starting, and never do it in the same diff as a behavior change. |
| **Deciding whether an extract-method is mechanical or a rewrite** — check `ev=` before picking a fix off this table | `ev=` absent (or `ev="1"`) on a `cx=` row means every region is single-entry/single-exit: **extract-method applies mechanically**, anywhere. `ev>=2` means a jump gave some region a second exit — the same extraction is now the "one deep tangle" row above, not a cheap lift. | `ev_why=tag:count` (guard-return, loop-escape, goto, ...) names which jumps raised it — a guard-return-heavy row is visibly not a knot. A FLOOR (`ev_floor="1"`): noreturn calls and macro-hidden exits can only push the true value higher. |
| **Small AND dense** — small `loc`, but `deep` is a large fraction of it (roughly half or more), typically in one hump | **Read it before you prescribe anything.** Numeric kernels, tree walks, and state machines are *legitimately* dense: the depth is the algorithm. Often the right fix is a comment or a named constant, not a split. | This row is where a metric-driven agent does the most damage. `--expand=SYM` first. If the density is the algorithm, ack it (`--ack-only=`) and move on. |
| **High fan-in AND untested** — big `in=`/`amp=`, `tested="0"`, or a `--quality-panel` row carrying `join="deep+untested"` | **Test first, refactor second.** The safety net is the fix's precondition, not its follow-up. → **ripwire-write-tests** (`--seams`, the `tested=` lens, `--callers=SYM` for the outside contract). | Confirm the annotation is real: `join=` is suppressed entirely at `tested_scope="0"`, so on an uncrawled-test corpus its *absence* proves nothing. |
| **Duplication** — a `--quality-delta` `duplication` / `new-clone-of-reused-helper` row, or a `--clones` group | **Consolidate through the repo's own exemplar** — `ripwire <dir> --exemplar="<what this code does>" --legend=compact` names the best-in-class instance to converge on (chosen by ROLE, not text similarity), so the survivor matches house patterns instead of being whichever copy you happened to open. | **Rule of Three** — extract on the third occurrence, not the second; a wrong abstraction is worse than two honest copies. Check `type=` on the clone group: `type="3"` members are gapped near-misses and may differ on purpose. |
| **Churn-flagged, structurally quiet** — `historical` fires with thin other evidence | **Probably nothing here.** `churn=`/`hrank=` are FILE facts inherited by every symbol in the file. | Confirm at the symbol before acting: `git log -p <file>` or `--hotspots --since=` to see whether *this* function is what keeps moving. |

**None of these has a corpus-derivable "correct" answer** — see the paragraph above the table. The playbook
names a move and the condition that makes the move safe; it does not compute a target shape, and any of these
rows can honestly end in "measured, understood, left alone."

## The closed fix loop — fix it, then PROVE the fix landed

Fixing without verifying is how a refactor trades one regression for two. Four steps, in this order; each
answers a question the previous one cannot:

```bash
# 1. make the fix (playbook above)
ripwire <dir> --quality-delta --legend=compact        # 2. did the TARGETED kind improve, and did nothing else regress?
ripwire <dir> --edit-check=SYM --legend=compact       # 3. is the CONTRACT intact?
ripwire <dir> --affected=F1,F2 --legend=compact       # 4. which tests PROVE it? (then run them)
```

2. **`--quality-delta`** — the only step with a meaningful exit code, and it is doing *two* jobs here, not
   one: the row you were chasing should be gone, **and** nothing new should have appeared. A "split the
   function" fix that drops `complexity` while adding `api-surface` + `duplication` is a lateral move.
   Read `gating=`, but also read the `origin="new-symbol"` rows — extraction *always* creates new symbols, and
   those rows do not gate (see **What exits 2** above), so exit 0 is not the same as "the fix was free."
3. **`--edit-check=SYM`** — `unchanged` / `new-symbol` / `contract-change` for the symbol you just edited:
   param count and publicness NOW vs `git HEAD`, plus its 1-hop callers with any call site provably
   incompatible with the new arity flagged. A refactor is *supposed* to be `unchanged` here; a
   `contract-change` you did not intend is the finding. Cheap enough (~ms warm) that skipping it is never the
   economical choice. It refuses (exit 1) if `SYM` matches several definition sites — a contract is per
   definition, so pass the `file:name` spelling it lists.
4. **`--affected=F1,F2`** (or `--affected=SYM`) — the test files that transitively reach what you changed.
   Metrics improving is not evidence the code still works; this names what to run, and then you run it.
   Mid-task, `--situ` is the same answer over the whole `git diff` plus co-change partners; at PR time
   `--test-gate` is the gating form (exit 4 when tests-to-run or the untested blast radius is non-empty).

**Done means:** the targeted kind is gone from `--quality-delta`, nothing else regressed, `--edit-check`
reports the contract you intended, and the `--affected` tests pass. Anything short of all four and the fix is
still a hypothesis.
