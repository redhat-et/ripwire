---
name: ripwire-find-bug
description: >
  Locate the code behind a bug when you don't yet know where it lives. Use when you have a SYMPTOM (a crash,
  an exception, wrong output, a failing test, an error string) and need to find the responsible symbol —
  whether you have no idea where it is, suspect a subsystem, or just broke it with a change of your own
  (even a deploy). Pick the path that fits what you know: pure symptom → rank candidates; a hunch → narrow
  to a subsystem; "I changed X and it broke" → --situ regression trace. Backed by ripwire's call graph +
  hotspots + co-change (deterministic, on PATH).
allowed-tools: Bash, Read
---

# Find the bug with ripwire

> Nearest neighbours:
> • You already know the symbol and just want to understand it → **ripwire-navigate**.
> • You want the blast radius / tests for a *change* (not to find a bug) → **ripwire-change-check**.
> • Repo-wide quality once-over, no specific symptom → **ripwire-fresh-eyes**.
> • "Why don't I see feature X?" and nothing looks broken — the code may be built but compiled/flagged OFF,
>   not buggy: `ripwire <dir> --flags[=SUBSTR]` (`--flip=NAME` for the blast radius of turning one ON) —
>   lives in **ripwire-fresh-eyes**, worth a look before you go hunting for a bug that isn't one.

`<dir>` = repo root. Calls are warm after the first parse — chain freely. **Pick the branch that matches
what you already know**; each converges on the same evidence trail (relevance × maintenance pain × blast
radius), so you can escalate between them.

**Evidence-sufficiency stop:** escalate only while the responsible code is still ambiguous. If `--for`
ranks one file/symbol clearly and a focused source read explains the symptom with a minimal fix, stop
retrieval and implement/validate it. Do not automatically add `--hotspots`, `--impact`, another skill, or a
whole-file read after the defect is already proven; those answer different questions and can cost more than
the original localization. Resume the ladder only when the source contradicts the candidate, several
candidates remain plausible, or the change's blast radius is itself part of the task.

## Branch A — "I have a symptom, no idea where it lives"

1. **Symptom search** — `ripwire <dir> --for="<symptom in plain words>"`
   `<sigs>` ranked by relevance — signatures + doc-comments closest to the symptom. The `in=` reuse count
   and `cx=` complexity are inline; **prefer high-`cx`, high-`in` matches** — complex, widely-called code
   fails in more ways. If the bundle says `weak="1"`, reformulate — split camelCase terms, add synonyms
   from the domain, or quote an exact path/symbol from the issue — before trusting the ranking below it.
2. **If several candidates remain, maintenance hotspots** — `ripwire <dir> --hotspots`
   `<hotspots>` ranked by `score = churn × ccx`; `top=` names the worst function per file. Bugs cluster in
   high-score files — **cross with step 1: a symbol in both lists is your prime suspect.**
3. **If the symptom is broad, blast radius of each remaining candidate** — `ripwire <dir> --impact=SYM`
   for the top 2–3 from step 1.
   `<impact of="SYM" defs="D" reaches="N">` lists everything that reaches SYM. A large `reaches` count is
   consistent with a symptom that appears in many places — that's the root, not a downstream effect.
4. **Read narrowly** — start with the top symbol/body or the smallest source range that can confirm or
   reject it. Use the hotspot intersection only when step 1 did not already isolate a defensible candidate.

## Branch B — "I suspect a subsystem — narrow it"

1. **Symptom-to-code** — `ripwire <dir> --for="<symptom>"` → note the `p=` (file paths) of the top 5. Which
   directories recur? That's your first narrowing.
2. **Hotspots in those directories** — `ripwire <dir> --hotspots` → files that are relevant to the symptom
   AND high churn+complexity are the most likely bug homes.
3. **Find the exact emit site** — `ripwire <dir> --grep="ERROR_STRING"` (literal + enclosing symbol) or
   `--regex="pattern"`. Add `--grep-context=N` (or `--grep-before=N`/`--grep-after=N`) for ripgrep-style
   lines of source around each hit — often enough to confirm the bug without a follow-up `--expand`. The
   enclosing symbol (`in=`) is ground truth — now `--callers=SYM` to trace up one level to the true root.

## Branch C — "I changed X and now something's broken" (regression)

1. **Situational awareness on the change** — `ripwire <dir> --situ=fileA.cpp,fileB.h` (or bare `--situ` to
   read from `git diff`). Emits, in one pass:
   - **blast radius** — everything that transitively reaches the changed symbols
   - **tests to run now** (`--affected` under the hood)
   - **co-change partners NOT in your diff** — files that historically move together (hidden coupling)
2. **Who calls the broken symbol** — `ripwire <dir> --callers=SYM` → each recorded caller (a floor — counts_floor=) is a candidate for an
   unexpected side-effect.
3. **Co-change history** — `ripwire <dir> --cochange=fileA.cpp` → partners ranked by `deg` (fraction of
   commits). A `surprising="1"` partner has no `#include` link — pure behavioural coupling, the non-obvious
   suspect.
4. **Read** the functions that appear in BOTH the blast radius and the co-change list first.

## Branch D — "I have a stack trace / sanitizer report / compiler error"

You have the failing artifact's TEXT (a Python traceback, an ASan/UBSan report, a node/js stack, a
clang/gcc diagnostic) — don't hand-translate its frames into queries one by one. Pipe it straight in:

1. **Map the trace onto symbols** — `ripwire <dir> --from-trace=FILE` (or `--from-trace=-` to read the
   trace from stdin, e.g. `pytest ... 2>&1 | ripwire <dir> --from-trace=-`). Table-driven frame extraction
   (python / asan / node / compiler / generic), ranked **innermost-first** over the frames that resolve to
   your indexed code. Out-of-corpus frames (stdlib, vendored deps) are listed and counted, never ranked.
2. **Read rank 1 first** — the `innermost="1"` suspect is the crash/throw site; its FULL body is emitted
   inline, the other suspects as signatures. `skipped=` tells you how many frames fell outside every root.
3. **Compose the budget** — `--from-trace=FILE --token-budget=N` fits the bundle to N tokens for a tight
   context window. Unparseable input refuses loudly (never a misleading empty map).

## Output

Report the branch you took, then: ranked candidate symbol(s) with `name`, `file:line`, and why (from
`--for`); their hotspot score if present; their blast-radius count (`--impact reaches=`); the error site's
enclosing symbol if `--grep` found it; and any `surprising="1"` co-change partner (branch C). Recommend the
top 1–2 to inspect first, with the evidence trail.

**Honesty:** ripwire gives call-graph *structure*, not data flow. For use-after-move / taint / null / type
bugs you still need the compiler — use these results to focus *where* to look, not as proof. A high-`amb`
symbol can be a dispatch hub, not the bug.

**Found it?** Pin the gotcha with `ripwire <dir> --note-add="SYM_or_path: what actually went wrong"` — the
next agent (or you, next session) gets it automatically the next time `--for`/`--expand` surfaces that symbol.
