---
name: ripwire-opt-remarks
audience: contributor
description: >
  Triage clang optimization remarks (-Rpass, -Rpass-missed, opt-record YAML) while editing ripwire's OWN
  C++: 'loop not vectorized', 'will not be inlined' — worth a diff, or is LTO/PGO the real fix?
  Contributor-only: compiling this tool, never running it.
allowed-tools: Bash, Read, Edit
---

# Triaging clang optimization remarks in this repo

> Routing: a measured slow operation, any codebase → **ripwire-perf-target**, FIRST; remarks are the second question.
> Maintenance risk / complexity → **ripwire-fresh-eyes**. The pass's full record: **`docs/OPTREMARKS.md`**.

**A remark is an observation, not a defect.** The pass behind this skill read ~1.1 M remarks over `src/`; zero justified
a source edit, two justified a BUILD change (LTO, then PGO). Here the answer to a remark is far more often a flag than a
diff.

1. **Profile first** — `cmake -S . -B build_prof -DRIPWIRE_PROFILE=ON && cmake --build build_prof -j 6`, then read the
   hottest scopes. A remark in code that costs a millisecond is dismissible on arithmetic.
2. **Collect, narrowed** — `scripts/optremarks.sh --passes 'inline|loop-vectorize|slp-vectorizer|licm|gvn|.*unswitch|loop-idiom'`
   then `python3 scripts/optremarks.py --hot --top 40`. Never in `build/`, never with a build type.
3. **Classify the remark** and look up what that class is worth here (`optremarks-reference.md`, Step 2).
4. **A fix must survive the measurement** — same workload before and after; a change that does exactly what the remark
   asked and measures flat is reverted.

## Stop rule

No profile showing the remark's code is hot → no diff. Run `test/optremarkshotcheck.sh` if you split or rename a hot
file.

## Reference file

`optremarks-reference.md` — profiling, collection, every remark class and its worth here, the measurement a fix must
survive, the anti-patterns the pass hit.
