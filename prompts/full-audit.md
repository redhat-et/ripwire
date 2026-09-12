# Full audit of ripwire

Audit this repository across six lenses. Run the lenses **in parallel** — they are independent, and
each one finds different things. Every finding carries evidence a stranger can re-run.

You can also point the audit at **your own large repository**. Build ripwire, run it on your tree, and
report what it gets wrong. Your tree is an instrument this project does not have. Either way, a
finding is a reproducer — argv, corpus and commit, output — not an impression.

Build first. Most lenses need a binary, and Lens 1 needs the sanitizer build too:

```bash
cmake -S . -B build && cmake --build build -j        # no build type: Release blinds the degrade gates
cmake -S . -B asan -DRIPWIRE_ASAN=ON && cmake --build asan -j
```

## Before any lens: measure the instrument

The previous full audit (2026-09-10, PR #127 and follow-ups #128–#136) was fooled three times. Each
time the subject was fine and the instrument was not:

- **A cache that evicted itself faked super-linearity.** Two `--for` rows on llvm-project read
  super-linear, one of them 14×. The cause was the 2 GB oldest-first sweep (`kMaxCacheDirBytes`,
  `src/quality.h`): it was deleting the working root's own sibling cache family. The same `--for`
  read 274 s CPU instead of 26 s.
- **A cap sweep measured caps on a population of zero.** The recorded harness crashed, discarded exit
  codes, stayed green while inert, and counted rows that emit nothing. Counted over rows that answer,
  the split was 64 of 151, not the published 59/195.
- **A capability probe was optimized into scalar code.** One AVX2 instruction compiled with `-mavx2`
  was folded by clang into a scalar add, and printed "ok" on every host. `test/strkerncheck.sh` now
  disassembles its probe first.

So before any lens reports a number:

- **Give its instrument a control that can go red** in the same session: a planted leak, a mutation,
  a known-bad pair. A harness that matched zero items has not passed.
- **Show the path under test ran on that input**: rows emitted, samples in the function, a counter.
- **For any A/B, add a placebo arm**: a byte-identical copy of the base binary. Its distance from the
  base is the noise floor (#132).
- **Check the process table is empty before timing.** A stopped harness once left its children
  running beside the next gate (#129).

## Lens 1 — bugs, hostile inputs, and silent omissions

Wrong output, crashes, silent truncation, a flag that does not do what `--help` says. Start where the
tool itself says the risk is: `./build/ripwire . --hotspots`, `--lint`, `--clones`, and `--report`.
Then read the code those point at. A bug is only a finding once you have a **reproducer argv** that
shows it.

**Hostile inputs.** One file is enough, and the vendored parsers are where it happens:

- **The yaml and markdown scanners** wrote past their serialization buffers on deep nesting: an abort
  at a few hundred levels, silent corruption under `NDEBUG`. The fixes are `third_party/patches/` and
  the prescans `kMaxYamlNestDepth` / `kMaxMdBlockDepth` in `src/ingest.h`.
- **tree-sitter's 16-bit repeat depth** aborted the sanitizer build on ~66K-deep repeat chains,
  because the sanitizer exemption named the wrong function (`test/vendorpatchcheck.sh` arms E and G).
- **The Kotlin scanner**, per the review of PR #126, called `abort()` when its delimiter stack filled.

Generate adversarial files per language and run them through `asan/ripwire` with the committed
`lsan_suppressions.txt`:

- deep nesting;
- a 16,000-comment flood in one list;
- one very long line;
- invalid UTF-8;
- merge-conflict markers;
- one enormous initializer.

A crash is HIGH. Silent corruption is the other half, and the sanitizer sees only the part of it that
is a memory-safety violation — the out-of-bounds write, the use-after-free. A wrong count, a dropped
row, a mis-sorted list stays in bounds and exits 0 under the sanitizer exactly as it does in the plain
build. Catch those with an independent oracle on the same input — the conservation identity below, a
second verb that has to agree, a byte-identical re-run — and run it in the plain build too.

**Every omission counted.** Wherever a loop can drop an item — a resolver, a filter, a cap, a paging
cut — ask two questions: does every iteration end in exactly one named outcome, and do the outcomes sum
back to the input?

PR #136 did this for call resolution:

- Every resolve iteration ends in one of `bound`, `self`, `external`, `unresolved`, `undefined`,
  `qualified_external`, `declined`, `file_scope` or `other_root`.
- Anything left over lands in `unaccounted`, which raises `DEGRADED_PATH_ALERT` on plain builds.
- The census re-derives `calls=` from the references instead of summing its own buckets.

That balance exposed two silent losses:

- **A silent decline.** `--callers=X` answered `count=0` as if nothing called `X`, for 22% of one real
  corpus's call references.
- **Uncounted skips.** On the merged tree, #134's `std::` guard skipped 1,495 calls on ripwire itself
  without counting them.

A count the output presents as a total, with no conservation line behind it, is a candidate finding.

## Lens 2 — performance (measure, never assume)

No claim in this lens without a timing. Distinguish the two states explicitly, because they differ by
orders of magnitude and conflating them is how a false speed claim gets published:

- **cold** — `--no-cache`, or after deleting the cache the tool reports.
- **warm** — a second run against a live cache. `--doctor` says whether it still is live.

`bench/perfgate.sh` and `bench/representative_perfgate.sh` are the harnesses. Both run in LEDGER mode
(owner directive: perf budgets are not the model — "best tool first, then make it fast"). They print
medians and append a dated entry to `bench/PROFILE.md` instead of failing on a budget. Whether a
number is worth flagging is your judgment call, not a red exit code.

**The scale rung: one llvm-sized run per audit.** Small corpora cannot see super-linear cost.

- Indexed `ts_node_child( n, i )` walks restart tree-sitter's child iterator on every call. That is
  O(children²), but only on flat child lists (comment extras, include guards).
- On llvm-project (182,555 files) those walks cost a fifth of the cold parse: 194.14 → 155.60 s CPU in
  #127. They were invisible on every standard corpus.
- Report per phase, and find a control invocation that does everything except the suspect phase.

**Protocol.**

- CPU = user+sys, with wall reported separately.
- Interleaved arms, same argv, n pairs, median and min.
- Outputs `cmp`-identical.
- Load recorded.
- The placebo arm above.

**A performance fix is proven by a red-first isolation arm, never by a timing budget:**

- a generated fixture that grows one dimension;
- the suspect path entered vs not entered, at the same width;
- user CPU, with a ratio ceiling over a floored divisor;
- a mutation arm showing the verdict calls the measured pre-change pair quadratic.

`test/childwalkscalecheck.sh` is the template. A flat reading proves only that the fixture missed the
path (#130). No gate here fails on a timing threshold.

## Lens 3 — skill and verb matching

Does the **right verb fire at the right moment**? Take ten real questions an agent asks mid-task
("who calls this", "is this safe to change", "which tests cover it", "where does this flow go"). For
each, check which verb an agent would actually reach for, given only `--help` and `skills/`.

Separate two failure shapes:

- **routing** — a verb that exists but is never reached;
- **gap** — a moment with no verb at all.

`--eval-skills=FILE` scores deterministic skill routing against a labeled TSV. Use it rather than
judging the routing by eye.

Build an adversarial prose set before you trust a router. `--help-task` answered "how does <an indexed
word> …" with `--expand=<that word>`, and on such a set 13 of 25 of its recommendations were harmful
until #127 (precision 0.797 → 1.000).

## Lens 4 — tool-use efficiency

**Tokens per answered question.** For each question in lens 3, compare the tokens the ripwire path
costs against the naive path (grep plus whole-file reads) for the *same* correct answer. Count real
bytes from real runs.

`docs/EVALS.md` §5 already publishes this for some verbs, including the counterexamples where a verb
costs *more* than it saves. Extend that table; do not contradict it without an instrument.

## Lens 5 — ecosystem scan

Search for research papers and GitHub repositories doing something this tool should learn from:
repo-map construction, code retrieval and ranking, call-graph resolution, agent context budgeting.

Rank by **momentum, not total stars**: commits and releases in the last few months, issues actually
being closed, a maintainer who is still there. A 30k-star repo last touched two years ago is not a
signal.

For each candidate, answer three things:

- what it does that ripwire does not;
- whether the idea transfers to a zero-dependency deterministic C++ tool;
- the cheapest experiment that would confirm or kill it.

An idea with no cheap experiment goes in a "not now, and here is why" list, not into the plan. Credit
in `docs/LINEAGE.md` goes only to a source whose technique ends up in shipped code.

## Lens 6 — honesty of the output

Read what the tool **says about itself** against what it did:

- **Counts.** Does every header count equal the rows listed?
- **Cuts.** Does every cut, cap and floor say so — `counts_floor="1"`, a `_capped` attribute, a
  disclosed truncation?
- **Zeros.** For each zero, find the path that produces it. A zero must mean *none found*, never
  *none exists*.
- **Refusals.** Does every refusal name the flag, the problem, and an example of the accepted form?

Pair each check with the gate that should have caught it. A disclosure that under-reports is worse
than one that is absent.

## The plan

One comprehensive plan, findings ordered by severity:

- **HIGH** — output a user would act on is wrong, the tool crashes on an input, or a published claim
  is not true.
- **MEDIUM** — missing capability, a measured performance regression, a verb that never fires, a
  silent omission.
- **LOW** — polish, wording, discoverability.

Each finding carries four things:

- the evidence: argv, timing, transcript line, or link;
- the control run that shows the instrument could see it;
- the decided fix shape, named down to the file;
- **the gate**: the check in `test/` that fails today and passes after.

A finding with no gate is not ready to be worked. Either write the gate into the plan, or move the
finding to an open-questions list.

## Honesty rules

- **A zero is a measurement; absent is not zero.** Counts that cannot be totals are floors and say
  so. Do not close a finding by hiding the floor.
- **Every dropped item is counted somewhere.** A conservation line that balances beats a plausible
  count.
- **Refusals name the flag, the problem, and an example** of the accepted form.
- **Never publish a number without an instrument that pins it**, and a control that shows the
  instrument can see what it claims. Every performance and efficiency number names the command that
  reproduces it.
- **Negative results get written down.** An idea that measured flat is worth more recorded than
  deleted; `docs/EVALS.md` §7 and §8 are where they live.

## Process

Run the plan as an **orchestrator**, matching task to model: cheap models for enumeration, fixture
authoring and mechanical sweeps; your strongest for resolver, ranking and concurrency work.

- **Producer agents work in git worktrees**, one lane each, one source file per lane where possible.
- **Producers run their own gates in the foreground**; the full suite is the orchestrator's job.
- **Red first.** A new gate must be shown failing against the pre-fix binary before it is trusted.
- **A targeted gate list is not the suite.** #132's list of 65 local gates missed `qschemetripcheck`,
  which CI caught. Run the full suite before the first push.
- **Cross-ISA and emulated test slices carry the host arm's sanitizer flags.** A shift that lost the
  top bit of a 32-bit mask reached CI because the x86 mirror first ran without them (#127).
- **Clean merge, wrong population.** Git merges text, not meaning.
  - Two lanes that each add a gate merge cleanly into a count that is one short.
  - A guard on one branch can drop items a census on another would have counted (#136).
  - After every merge wave, **regenerate** on the merged tree instead of hand-merging:
    - the gate count (`docs/gatecount_build.py`);
    - `docs/LIMITS.md` (`docs/limits_build.py`);
    - `docs/COMMANDS.md` and its captures (`docs/docs_commands_build.py`);
    - `test/printf_parity.manifest`;
    - `test/qschemetrip.hash`;
    - the quality ack ledger, healed through the binary.
  - Then re-run the conservation and live-tree gates on the merged binary.
- **An adversarial verifier runs after every merge wave**, briefed to find the wave broken rather than
  to approve it. Its findings are claims, not verdicts; a measurement that refutes it wins.
- **No unacknowledged `--quality-delta` regressions** before a lane reports done.
- **Finish green.** `python3 test/pargates.py . ./build/ripwire -j 6` passes in the foreground; commit
  per verified item.

**Filing findings.** Open one issue per finding, with:

- a title that names the defect;
- the reproducer argv, and the corpus and its commit;
- expected vs actual output;
- the control that shows the instrument could see it;
- the severity, with its reason.

Findings from your own repository are just as welcome. If its code is private, reduce the finding to
a generated fixture first.

**Write the plan, then STOP for my go-ahead.**
