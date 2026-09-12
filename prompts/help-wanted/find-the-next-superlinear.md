# The scale rung: find the next thing that grows faster than its input

You are hunting for **super-linear cost** in ripwire: a phase whose time grows faster than the tree it
reads. That defect class is invisible on the corpora most people test with. On the trees that matter
it decides whether the tool is usable.

The job has four parts:

1. Run the tool on the largest public repositories you can hold.
2. Find what bends.
3. Reduce it to a generated fixture that grows one dimension.
4. Prove the fix with a ratio arm that fails before and passes after, never with a stopwatch
   threshold.

Work in a git worktree, and run gates in the foreground. Keep the corpora **outside** the checkout: a
tree inside the checkout joins every gate's view of the repository.

---

## Why this matters

The code the world runs on lives in very large trees: the Linux kernel, Chromium, LLVM. An agent
working there needs its map in seconds. The defects that make a map slow at that size cannot be seen
on anything smaller.

Two public examples:

- **The O(C²) child walk (PR #127, then #130).**
  - A loop that indexed a node's children with `ts_node_child( n, i )` looks linear. It is not: the
    vendored tree-sitter restarts its child iterator from the first child on every call.
  - It bites only when a child list is **flat**. Comments are tree-sitter *extras*, spliced into the
    parent's own child array, and C/C++ include guards produce the same flat width.
  - A grammar repeat of 16,000 declarations is stored as a balanced tree, and stays linear.
  - On llvm-project (182,555 files), converting those walks to a cursor took the cold parse from
    194.14 to 155.60 s CPU (−19.9%), with identical output.
  - No standard corpus could see it; llvm was the only instrument.
  - #130 converted 22 more walks, and proved each one at 13×–126× its control before the fix.
- **The inheritance cone (PR #83).**
  - On llvm-project, warm `--grep` took 159.7 s and `--callers=main` took 152.9 s.
  - `--help-task`, which does the same crawl, cache and model work but builds no graph, took 3.8 s.
  - Inside `buildGraph`, 143 of 154 s went to one O(n²) dedup, recomputed for every
    still-ambiguous receiver-typed call.
  - With a memo, warm `--grep` took 9.2 s.

The project rule that came out of this is **one llvm-sized run per performance round.** This kit
climbs past llvm, to the trees where the next such defect is waiting.

---

## Background with file pointers

- **`src/infra/tschildren.h`** holds the child-walk rule: use a cursor, or write at the loop the
  one-line reason a comment cannot reach that list. Its header records why "the grammar bounds this
  list" was wrong.
- **`test/childwalkscalecheck.sh`** is this kit's method in executable form. Read its header and its
  `verdict`, `arm` and `pair` functions.
  - `test/padscalecheck.sh` covers comment floods through ingest.
  - `test/preprocdeadscalecheck.sh` covers the include-guard flood.
- **`src/quality.h`.** `kMaxCacheDirBytes` is the 2 GB cache-directory budget, and the eviction note
  above it explains what went wrong.
  - One llvm root needs 1.76 GB of cache for its own two families.
  - Before #127, the oldest-first sweep could evict the working root's sibling family.
  - A repeated `--for` then read 274 s CPU instead of 26 s.
  - Since #127, an eviction is disclosed on stderr.
- **`-DRIPWIRE_PROFILE=ON`** (CMakeLists.txt, `src/infra/profileScope.h`) builds a self-profiling
  binary. It prints its per-scope report on **stderr** at exit, so stdout stays byte-comparable.
- **`bench/perfgate.sh`** runs in ledger mode. It records medians into `bench/PROFILE.md` and never
  fails on a budget.
- **`--doctor`** states the environment, the cache state, and what the tool believes about the tree.
- **`--skipped`** lists what the crawl did not index.
- **`docs/LIMITS.md`** is the cap register. A cap that binds only at scale changes *what* you are
  timing.
- **Leads the last round recorded and did not work.** Verify them before believing them:
  - `ts_node_prev_sibling` restarts from the parent's first child (#130).
  - The parent-chain family is the larger remaining cold-parse cost (#130). `ts_node_parent`
    re-descends from the root, and it is reached from `bindsVisitNode`, `qualifierOf` and
    `enclosingScopeOf`.
  - The floors of warm map, `--for` and `--grep` are the serial resolve loop and file opens (#127).

---

## The measurement protocol

Every number in your report follows these rules, or is labelled as not following them.

1. **Pin the corpora.**
   - Record the commit, `git ls-files | wc -l`, the size on disk, and whether the clone is shallow.
     History-mining phases (churn, co-change) cost differently on a shallow clone, so keep that the
     same across arms.
   - The suggested ladder, in order:
     1. ripwire itself;
     2. [golang/go](https://github.com/golang/go), the middle rung;
     3. [llvm/llvm-project](https://github.com/llvm/llvm-project), the established rung;
     4. [torvalds/linux](https://github.com/torvalds/linux);
     5. [chromium/chromium](https://github.com/chromium/chromium), the official GitHub mirror. Its
        `third_party/` alone is a polyglot tree worth a rung.
     6. one polyglot monorepo you care about, for example
        [pytorch/pytorch](https://github.com/pytorch/pytorch).
   - Stop where disk or patience runs out. Every rung you complete is data.
2. **Never mix cold and warm.**
   - *Cold* is `--no-cache`. *Warm* is a run against a cache that a priming run just wrote.
   - Before and after every warm series, run `--doctor`, `du -sh` the cache directory it names, and
     read stderr for eviction lines.
   - A warm number measured across an eviction is a cold number in disguise.
3. **CPU, not wall.**
   - Use `/usr/bin/time -p`, and report user+sys as CPU.
   - Report wall separately; it moves with I/O and with other load.
   - CPU sums threads, so say which phases run in parallel.
   - CPU is robust to load, not immune to it: frequency scaling, SMT and cache contention still move
     it. Record `uptime` for every series.
4. **Interleave.**
   - Run A B A B, or ABAB then BABA, with the same argv, cwd and environment.
   - Take n ≥ 5 pairs on the mid rungs. On the largest rungs n = 1 is acceptable only when the table
     says n = 1, as #127's does.
   - Report the median and the min.
5. **Add a placebo arm.**
   - Arm C is a byte-identical copy of the base binary. C−A is the noise floor under the same load.
   - #132 used one: a +45 ms median delta sat inside a placebo whose own swings reached 537 ms.
   - If B−A is inside C−A, the verdict is "nothing measurable".
6. **Check output identity.** `cmp` every arm's stdout. A faster run with different output is a
   different program: report it as a change, not a speed-up.
7. **Start from a quiet process table.** `pgrep ripwire` must be empty before each run. Before #129, a
   gate the harness had stopped could leave its children running beside the next measurement.
8. **Measure per phase.**
   - A total hides the phase you are looking for. Use the profiling build or a sampler.
   - Then find a **control invocation** that does everything except the suspect phase. That is how
     `--help-task` isolated graph construction in #83, before a line of code was read.

---

## How to find it

1. **Profile the big rung.**
   - Linux: `perf record -g`, then `perf report`. [FlameGraph](https://github.com/brendangregg/FlameGraph)
     renders the same data.
   - macOS: `sample <pid> <seconds>`, or Instruments' Time Profiler.
   - Attribute leaf samples to the nearest caller outside tree-sitter. That is how childwalkscalecheck's
     header ranked `bindsVisitNode` second, behind `captureTagsFacts`.
2. **Read per-unit cost across the ladder.** Divide each phase's CPU by the unit it should scale
   with: files for the crawl, bytes for scans, symbols for extraction, call references for
   resolution. A per-unit cost that rises with the rung is the signal. A flat per-unit cost is linear,
   however large the total.
3. **Grow one dimension.** Write a generator that produces a fixture where one quantity grows and
   everything else holds still. Candidates include:
   - children of one node;
   - files in one directory;
   - definitions sharing one name;
   - overloads;
   - classes in one inheritance chain;
   - nesting depth;
   - the length of one line;
   - arguments in one call;
   - `#include` fan-in.

   Use at least two widths, for example 1,000 and 16,000. Make each child cheap ("wide node, cheap
   children") so the arm measures the indexing, not the payload.
4. **Build an isolation pair.** At the same width, compare a fixture that **enters** the suspect path
   with one that does not: the same flood inside the list and beside it, or the verb and the plain
   map. The pair names one walk instead of saying "the verb got slower". A fixed start-up cost cannot
   defeat it, the way it can defeat a 1k-vs-16k ratio.
5. **Prove the flood reaches the path.** A flat measurement proves only that the fixture missed.
   #130's examples:
   - A flood in a Python class body read flat. The same flood inside the superclass parentheses read
     54×.
   - Comments that lead a Ruby body belong to the parent node, not to the body.
   - An unqualified C++ `using` is never captured, so it never enters the walk.

---

## Rule out the instrument before you believe the subject

The 2026-09-10 audit that produced #127 was fooled twice, and the gate that checks the string kernels
once:

- **A cache that evicted itself faked super-linearity.** Two `--for` rows on llvm read super-linear,
  one of them 14×. The 2 GB sweep was deleting the root's own sibling cache family between runs. `du`
  the cache and read stderr.
- **A population of zero.** A cap sweep measured retrieval caps on inputs where the verb emitted
  nothing, and published a split over rows that answer nothing. #127 re-derived it as 64 of 151
  answering rows, not 59/195. Before a ratio means anything, show the path under test **ran** on that
  input: rows emitted, samples inside the function, a counter.
- **A probe that could not see.** A capability probe compiled to scalar code said "ok" on every host
  (`test/strkerncheck.sh`). Every instrument gets a control that can go red.
- **A control that is quadratic too.** A C# control flooded a class body, but the walk under test
  runs on every ancestor of a definition, so the control paid the same cost (#130).
- **Translated or emulated execution** (Rosetta, QEMU) is not a timing environment.

---

## Design space and constraints

- **The fix is output-identical.** Arm (C) of `childwalkscalecheck.sh` compares every fixture × verb
  against `RIPWIRE_REF_BIN`, the pre-change build. If the output has to change, that is a separate,
  disclosed PR.
- **Never fix scaling by cutting the answer.**
  - No new cap, no sampling, and no dropped rows to flatten a curve.
  - Caps are blow-up guards toward one complete answer. A cap that binds is disclosed in the header,
    and a cap can make the answer wrong.
  - Never tune a default down to flatter a number.
- **No perf-budget gate.** No gate may fail on a timing threshold. The gate is a **ratio arm**, built
  the way `childwalkscalecheck.sh` builds one:
  - user CPU, walk vs control;
  - a ratio ceiling;
  - a divisor floored so a near-zero control cannot manufacture a large ratio;
  - an absolute short-circuit below which scaling is moot;
  - a **mutation arm** proving the verdict calls the measured pre-change pair quadratic, and a
    linear pair linear.
- **Determinism is a contract.** Nothing in the fix may make output depend on thread timing, and
  reductions keep their canonical order (`docs/ARCHITECTURE.md` §3).
- **G2.** Use plain vectors, sorted arrays and 32-bit handles. Never `std::map` or
  `std::unordered_map`; the container rule is in `CONTRIBUTING.md` §3. A memo's key must carry every
  input its answer depends on.
- **Generated fixtures, never committed.** A committed megabyte of comments would join every other
  gate's view of `test/`.
- **One llvm-sized run per round**, plus any new rung you add, reported per phase.

---

## Acceptance criteria

1. **A ladder table.** For each corpus and verb: cold and warm CPU (median, min, n), wall, per-unit
   cost, a digest of the output, the commit SHAs, and the load.
2. **Attribution.** A profile that names the function, with sample counts, on the rung where the cost
   bends.
3. **A red-first fixture.**
   - A generated fixture that grows one dimension.
   - An **isolation pair that is red on the pre-change binary**; paste the red row. It is green after
     the fix.
   - Extend an existing scaling gate where the path fits. Otherwise add a `test/*check.sh`, listed in
     `test/regression.sh` in the same commit.
4. **A mutation arm** showing the verdict can fail.
5. **Byte-identity** with the pre-change binary: on the generated fixtures, on committed fixtures, and
   on at least one real rung.
6. **Before/after on the rung** where the defect showed, in #127's table shape. Include the verbs
   that did not move.
7. **G1.** The ASan build (`-DRIPWIRE_ASAN=ON`) runs the widest fixture clean.
8. **A clean ladder is a result.** If nothing bends, publish the ladder anyway: which verbs, which
   rungs, which per-unit costs. "Checked, linear, do not re-fund" saves the next person a week.

---

## Known traps

- **Declarations do not flood the way comments do.** A flood of 16,000 **declarations** is linear; a
  flood of 16,000 **comments** is not. Build the shape that reaches the list.
- **Fixed-index probes are fine.** `ts_node_child( n, 0 )` is not the defect; only unbounded indexed
  loops are.
- **Leading extras attach to the parent.** Place the flood after the first real child.
- **A cache twice the expected size.** Two cache-key builders once hashed the same root two ways and
  minted two cache families per root (fixed in #127). If you see this, look.
- **Orphaned children.** A timed-out harness's children outlive it unless it kills the process group
  (#129). Check the process table.
- **A green summary over zero items.** A harness that ran nothing can still print one. Count what ran.
- **Clone depth.** Shallow and full clones cost differently in the history phases.
- **A build across a branch switch.** A build started before a switch produces a binary no commit
  describes. See CLAUDE.md, and rebuild clean.

---

## Reporting format

Paste this into the PR description or the issue and fill every field. Write "not measured" where you
did not measure.

```
## Scale rung report — <date> — ripwire <commit>
Host: <CPU model, cores, RAM, OS>   load during runs: <min–max>   build: plain | profile
Corpora:
| corpus | commit | files | size | clone | notes |
Ladder (CPU = user+sys, interleaved, median / min / n):
| corpus | verb | cold CPU | warm CPU | wall | per-unit cost | stdout sha256 |
Instrument checks: cache du before/after · eviction lines on stderr · placebo C−A · pgrep empty
Profile (rung where it bends): <function — samples — % of busy — attributed caller>
Suspect: <function, file> grows with <dimension>
Fixture: <shape>, widths <a>/<b>; isolation control: <shape>
Red (pre-change): <gate row>          Green (after): <gate row>
Byte-identity: <N> fixture × verb pairs, <M> real-corpus verbs
Checked and linear (do not re-fund): <verb × rung list>
```

---

**Write the plan — the corpora you can hold and their commits, the host, the ladder you will run, the
first three suspects and the control invocation that would isolate each — then STOP for my go-ahead.**
