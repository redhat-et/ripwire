---
name: ripwire-before-you-build
description: >
  About to start a whole FEATURE — multi-symbol work that needs a plan, an interface, or a size estimate
  before you write it — do the homework from the codebase's actual structure instead of assumptions. Use
  when starting a feature and you need any of: is this approach even viable (spike)? what's the ordered
  implementation plan? what should the boundary/API look like (interface)? how big is this change
  (scope/effort)? Each takes ~30s and often surfaces an existing implementation to reuse. For a SINGLE
  function/class/helper you're about to write → ripwire-reuse-first. NOT for reviewing an already-written
  diff — that's ripwire-change-check. NOT for restructuring EXISTING code — that's ripwire-fresh-eyes; this
  skill is for NEW work. Run only the homework the task actually lacks — a small feature with an obvious
  home needs none of this: skip the skill and build. Backed by ripwire (deterministic, on PATH).
  Ask first: do building blocks already exist, which exemplar, what integration adds.
allowed-tools: Bash, Read
---

# Before you build — with ripwire

> Routing:
> • Writing ONE symbol (fn/class/helper) and want to reuse rather than reinvent → **ripwire-reuse-first**.
> • You've already written the change and want the pre-submit check → **ripwire-change-check**.
> • You want to judge whether the code you wrote got better/worse → **ripwire-quality-bar**.
> • Restructuring EXISTING code (not new work) → **ripwire-fresh-eyes**.
> • Not sure which skill? → **ripwire-router**.

`<dir>` = repo root. `FEATURE`/`APPROACH` = your task in 2–4 plain words; `SYM` = a representative symbol.
Run only the sections your question needs — they share the same building blocks.

## Common first move — recall + reusable blocks

Almost every section starts here; do it once. **One-call shortcut:** `ripwire <dir> --pack-task="FEATURE"`
assembles the recall + `--for` ranking + top bodies + caller signatures + notes + `tests_to_run` into ONE
bundle under one token budget — reach for it first instead of firing the calls below one at a time; drop to
the individual calls only when you need a specific section's full output.

- **Recall prior decisions** — `ripwire <dir> --recall="FEATURE"` → full bodies of the most relevant
  markdown docs (planning/design notes, READMEs) ranked by relevance. **If a doc already covers this, read
  it fully — the decision may be made.** Look for explicit "rejected" / "future work" language.
- **Reusable building blocks — the one-call write-mode bundle** — `ripwire <dir> --for="FEATURE"` → `<sigs>`
  ranked by task-relevance, each carrying the **quality lens** in the same call: `cx`/`ccx` (complexity),
  `in`/`amp` (reuse count / change-amplification), `churn` (recent-commits), `clone="1"` (duplicated),
  `tested="1"`, plus the inline `<doc>` block. That's read-context-and-quality-signal in ONE call — you learn
  what to reuse AND what's fragile (high-churn, high-amp, cloned, or untested) before you write a line, not
  after. High-`in` symbols are already widely composed — prefer extending them over reimplementing; treat a
  high-`churn`/high-`amp` one as something to touch carefully and test around.
- **The shape to imitate for each new symbol** — `ripwire <dir> --exemplar=fn|method|class|struct|iface|var`
  or `--exemplar="<the sub-task in words>"` (top match's kind inferred) → the repo's single best-in-class
  instance of that shape — cognitive complexity must clear an eligibility ceiling first (a blob can never
  win no matter how reused/tested), then among eligible candidates it's ranked `tested=1` first, highest
  fan-in second, lowest cognitive-cx as the final tie-break — full body under
  `<bodies>`. Run it per new symbol the feature adds so each one **copies a proven shape** (structure, error
  handling, naming) instead of being invented from memory. (Deep-dive on exemplar-by-ROLE → **ripwire-reuse-first**.)
- **Implementing against an interface?** — `ripwire <dir> --lego=I` (or `--lego=file:I` to disambiguate a
  same-named type) → the interface's method contract (the exact signatures you must satisfy) **plus every
  existing implementor**, own-language only. Read one existing impl as the template so your new one matches
  the house pattern (method order, error handling, registration) instead of guessing the shape from the
  interface alone. The single highest-value call when the thing you're building has to satisfy an `I`.

## Feasibility spike — "is this approach even viable?"

After the recall + `--for` above:
1. If highly-relevant symbols already exist with `in > 0`, the approach is **partially implemented** — build
   on it. If `--recall` shows it was decided against, stop.
2. **Integration seams** — `ripwire <dir> --seams` → `<seams>` (untested cross-module edges). If your
   approach must connect two modules with no test-covered seam between them, that's an integration cost.
3. **Coupling cost** — `ripwire <dir> --deps` (skim `<godfiles>` + `shape=`). Adding a dependency on a
   god-file adds coupling cost for every future change — flag it.
   → **Verdict:** "build on existing" / "greenfield but seams exist" / "needs new seam, flag risk".

## Plan — "give me the ordered implementation steps"

1. Recall + `--for` (above) — check whether any existing symbol already solves part of the problem. Low `in=`
   = an underused candidate to extend or replace; high `in=` = load-bearing, extend cautiously.
2. **Integration seams** — `ripwire <dir> --seams`. Each seam is a wiring point; your plan should name which
   seam(s) the new code wires through, and add a test at each new seam it creates.
3. **Impact of anything you'll modify** — `ripwire <dir> --impact=SYM`. Large `reaches=` → plan a staged
   rollout or a compatibility shim.
   → **Plan:** ordered steps (recall → design → wire seams → write tests → implement), each naming the
   specific file+symbol to touch, the blast radius of any modification, and its test gate (from
   `--affected`). Flag any step that creates a new seam without a test.

## Interface — "what should the boundary / API look like?"

1. **Neighborhood of the subsystem** — `ripwire <dir> --around=SYM --metrics [--around-depth=2]` → the ego
   graph with ranks + call edges. `--metrics` is what adds the `in=` fan-in annotation (bare `--around`
   emits none); **high-`in=` symbols are already acting as the de-facto API surface.**
2. **The seam it lives on** — `ripwire <dir> --seams`. If your subsystem straddles a `<seam from="X"
   to="Y">`, that's where the interface belongs.
3. **Who currently crosses the boundary** — `ripwire <dir> --callers=SYM` for the top 2–3 in the ego graph.
   Callers from *outside* the subsystem's directory are the external clients the interface must serve.
4. **What to hide** — `ripwire <dir> --deps`, skim `instab=`. High-instability internal files (leaves) stay
   behind the interface; stable (low-instability) files may be safe to expose.
   → **Proposal:** the 3–5 high-fan-in, called-from-outside symbols that form the natural API surface, the
   seam they live on, and the internal symbols to hide. Write it in terms of callers' needs, not internals.

## Sizing rubric — "how big is this change?"

1. **Blast radius** — `ripwire <dir> --impact=SYM` → `reaches="N"` is the blast-radius **symbol** count
   (count distinct `p=` files for the file count); `defs="D">1` means overloads, each a separate blast root.
2. **Affected tests** — `ripwire <dir> --affected=fileA.cpp,fileB.h` (the files defining SYM, from
   `--impact`). `tests="0"` = no test cover — flag it.
3. **Caller-stack depth** — `ripwire <dir> --callers=SYM`, then spot-check `--callers=<top-caller>` one level
   up. A 2-hop caller graph is a tactical change; 5+ hops is architectural.
4. **Hidden coupling** — `ripwire <dir> --cochange=fileA.cpp`; `surprising="1"` partners must be verified
   manually even if not in the blast radius.
   → **Classify:** local (≤5 blast, tests exist) / moderate (5–20) / wide (>20 or no tests).

## Honesty

ripwire maps *structure*, not data flow; seams/impact are name-based (dynamic dispatch/callbacks/macros can
be missing). Compose from what exists; note what's genuinely missing rather than reinventing it.
