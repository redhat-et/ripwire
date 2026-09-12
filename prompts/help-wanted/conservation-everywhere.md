# Conservation everywhere: no blast-radius answer under-counts in silence

You are extending a **conservation law** through ripwire's graph builder. Under it, every reference the
builder takes up ends in exactly one named outcome, and every outcome is counted. An answer an agent
decides with then carries the count it would otherwise leave out.

PR #136 established the law for **call** references. This round carries it to the three reference
loops and three answer surfaces it has not reached yet. Compare two answers:

- "`--safe-delete` found no callers."
- "`--safe-delete` found no callers, but one call site could have meant this method and the resolver
  declined to guess."

Only the second is an answer an agent can act on.

Work in a git worktree, not the main checkout, and run gates in the foreground.

---

## STEP 0: the prerequisite (PR #136, merged)

This prompt builds on PR #136, "fix(resolver): a declined call no longer reads as 'no caller exists'",
which merged into `main` as d752d953 on 2026-09-11. Branch from `origin/main`, and confirm the code is
there before you plan:

```bash
git fetch origin
git grep -n declinedCallsNaming origin/main -- src/graph.h     # a hit means #136 is on main
```

No hit: stop and report back. Everything below assumes #136's `CallDisposition`, its `# dispositions`
census line and its `declined_calls=` helpers exist. Name your base sha in the plan.

Paths marked *(#136)* below arrived with that PR.

---

## Why this matters

Before an edit, the questions this tool answers most often are:

- "Who calls this?"
- "What breaks if I change it?"
- "Can I delete it?"

An agent reads `count="0"` or `risk="none-found"` and acts on it. CLAUDE.md's non-negotiable #3 says a
zero means *none found*, never *none exists*. A count that silently leaves out a whole class of
references breaks that promise, even when every edge it does report is right.

The evidence that the class is real, and large:

- **The declines #136 disclosed.** Tier 3 of the name-based resolver refuses to guess among same-named
  definitions in different directories. Before #136 that refusal was silent. PR #136's body measures it
  on the merged tree with `--no-cache`:
  - memgraph: 65,516 of 295,086 call references (22.2%);
  - ripwire itself: 6,263 of 135,449 (4.6%).
- **The conservation line caught a regression at merge time.** #134's `std::`-qualified guard merged
  beside #136, and its refusals left the resolve loop through a bare `continue`.
  - The `--pin-census` balance came out with `unaccounted` at 1,495 on ripwire and 4,966 on memgraph.
  - The merge was fixed before it shipped; those refusals now count as `external`.
  - No reviewer caught that `continue`; the arithmetic did. That is the mechanism this round extends.

Who benefits: every agent and reviewer who runs `--callers`, `--impact`, `--lego`, `--mentions`,
`--edit-check` or `--safe-delete` before touching code. That covers every language, because none of the
silent spots below is language-specific.

---

## Background: read these before you plan

### What #136 built (the pattern to extend)

- **`src/pincensus.h`** *(#136)*
  - `enum class CallDisposition`, whose buckets are `Bound`, `Self`, `External`, `Unresolved`,
    `Undefined`, `OtherRoot`, `QualifiedExternal`, `Declined`, `FileScope` and `Unaccounted`.
  - The name table `kCallDispositionNames`.
  - `isResolvableCallReference( const Reference& )`: the ONE predicate that defines the population, used
    by both the resolve loop and the census writer.
  - `writePinCensus` prints `# dispositions calls=N bound=… unaccounted=K`. `calls=` is **re-derived from
    `ing.references`**, never summed from the buckets.
- **`src/graph.h`, inside `buildGraph`**, the block profiled as `"buildGraph/3: resolve loop (per
  reference)"` *(#136)*
  - `DispositionTally` counts each iteration's disposition in its destructor, so every `continue` is
    counted.
  - An exit that names nothing is counted `Unaccounted`, and that raises `DEGRADED_PATH_ALERT` on plain
    builds.
  - `vetoExternal` returns `CallDisposition::External`.
  - A tier-3 decline increments `g.declinedOut[caller]` and appends its candidates to the CSR
    `g.declinedCandOff` / `g.declinedCand`.
- **`src/graph.h`: `declinedCallsNaming( g, targets )` and `declinedCallsMadeBy( g, sources )`**
  *(#136)*. Both count per CALL, never per call × candidate.
- **`src/graphlegend.h`** *(#136)*: `kDeclinedCallsLegend`, `declinedCallsLegend( bool )`,
  `declinedCallsAttrXml` and `declinedCallsKeyJson`. The attribute is absent at zero, and its legend
  clause is emitted exactly when the attribute is.
- **The answer surfaces:**
  - `src/callhierarchy.h`: `CallHierarchyRows::declinedCalls` *(#136)*.
  - `src/verbs_navigate.h`: `runCallHierarchy`, and `runImpact` with `emitImpactXml`, `emitImpactJson`
    and `emitImpactColumnar`.
  - `src/mcpverbs.h`: the MCP twins `find_symbol`, `find_referencing_symbols` and `impact`.
- **The gates:**
  - `test/declinecheck.sh` *(#136)*. Arm (F) is the conservation arm, arm (G) proves its predicates can
    fail, and the fixture `test/declinefix/` covers 17 languages.
  - `test/resolverhonestycheck.sh` F5 requires the decline to be disclosed.

### Silent spot (a): the three non-call loops

Each loop in `buildGraph` walks `ing.references`, filters to its own relation, and resolves the name
through `byName`. None of them counts what it drops. Read each loop and list every exit yourself; the
lists below are a starting point, not a substitute.

1. **Inheritance** (`"buildGraph/5: inheritance edges"`)
   - It records `r.isInherit` as `g.implementors[base] += derived`.
   - Consumers: `--lego` (`src/verbs_for.h`, `packLego`), the MCP `lego` verb, and the Lego view in
     `--for`.
   - Dropped per reference: a Rust `impl` whose derived type name finds no class-like symbol; a base name
     with no in-repo definition.
   - Dropped per candidate: not class-like, in another root, language-incompatible, or the derived class
     itself.
   - When a base name has several class-like candidates, the derived class is recorded under **every**
     one of them.
2. **Doc mentions** (`"buildGraph/6: doc mentions"`)
   - It records `r.isDocLink` as `g.mentions[def] += docNode`.
   - Consumers: `--mentions` (`src/verbs_navigate.h`), the MCP `mentions` verb, and the doc-mention
     surfacing in `--for` (`src/mention.h`).
   - Dropped: a mention with no enclosing doc node, a name with no definition, a declaration-only
     candidate, the mentioning node itself, a candidate in another root.
3. **HAS-A** (`"buildGraph/7: HAS-A compose edges"`)
   - It records `r.isCompose` into `g.composeEdges`.
   - Consumers: `packCompose` (`src/serialize.h`) in `--for` and `--around`.
   - Dropped: no owner symbol, a type name with no definition, a candidate that is not a class or struct,
     self, another root, language-incompatible.
   - It then keeps the first surviving candidate and `break`s. With K same-language candidates the lowest
     id wins, and nothing in the output says a choice was made.

### Silent spot (b): buckets the census counts and no answer carries

The census balances three buckets that never appear on `--callers`, `--callees` or `--impact`:

- `FileScope`: a call outside every symbol, so there is no caller node.
- `OtherRoot`: a multi-root call whose every compatible definition is in another root, with no include or
  import reaching it.
- `Self`: recursion.

`--uses` does list a file-scope call site. That is why the census is right while the answer is still
short.

### Silent spot (c): two verbs #136 did not reach

- **`--safe-delete`**: `runSafeDelete` in `src/verbs_navigate.h`, with `emitSafeDeleteLegend` beside it.
  - `callers=` is the in-edge walk.
  - `impact_reaches=` is `transitiveCallers`.
  - `risk=` names what was found.
- **`--edit-check`**: `runEditCheck` in `src/verbs_quality.h`, which calls `editCheckBundleText` in
  `src/editcheck.h`. The MCP `edit_check` verb shares that function (`src/mcpverbs.h`).

### Gates you will read or extend

- Resolver and census: `test/declinecheck.sh` *(#136)*, `test/pincensuscheck.sh`,
  `test/resolverhonestycheck.sh`, `test/floormarkcheck.sh`, `test/multirootcheck.sh`.
- The non-call relations: `test/legocheck.sh`, `test/composelangcheck.sh`, `test/mentioncheck.sh`,
  `test/mentionsverbcheck.sh`, `test/docmentioncheck.sh`.
- The two verbs: `test/safedeletecheck.sh`, `test/editcheckcheck.sh`, `test/editcheckanswercheck.sh`,
  `test/mcpeditcheck.sh`.
- Legend and MCP: `test/legendcoveragecheck.sh`, `test/mcpattrparitycheck.sh`,
  `test/mcpmanifestcheck.sh`.

And the method, in `docs/METHODOLOGY.md`:

- §1: gate before code.
- §3: sibling completeness (gate the family, not the instance).
- §9: terminality versus ceilings (honesty lives in attributes).

---

## Reproduce: every shape below was run on `main`, and re-checked on a build of d752d953 after #136 merged

Build first with `cmake -S . -B build && cmake --build build -j`. Each corpus is a scratch directory of
your own; nothing here is committed.

**(a) An implementor `--lego` cannot see, and cannot say it cannot see.** Use two roots:

```
rootA/api/Shape.java     package api;  public interface Shape { double area(); }
rootB/impl/Circle.java   package impl; import api.Shape;
                         public class Circle implements Shape { public double area() { return 1.0; } }
```

`./build/ripwire rootA rootB --no-cache --lego=Shape` prints a `<lego>` with no `<impl>` row, beside
`graph_ambiguous="0" graph_unresolved="0"`. Put both files under ONE root and `Circle` appears. The
cross-root rule may be right; the silence is not.

**(a) An implementor claimed twice.** In one root, `a/Shape.java` and `b/Shape.java` each declare
`interface Shape`, and `c/Circle.java` implements `Shape`. `--lego=a/Shape.java:Shape` and
`--lego=b/Shape.java:Shape` BOTH list `Circle`, and nothing marks the guess.

**(a) A HAS-A pick.** `p1/pool.h` and `p2/pool.h` each declare `struct Pool`, and `own/owner.cpp`
declares `struct Owner { Pool m_pool; };`. `--around=Owner` prints `<field name="m_pool" type="Pool"
owner="Owner" rel="creates"/>`: one binding, chosen by id, undisclosed.

**(b) A caller the answer leaves out.**

- `util.py` defines `helper`, and `main.py` is `from util import helper` followed by a module-level
  `helper()`. `--callers=helper` answers `count="0"`, while `--uses=helper` lists `role="call"
  p="main.py:2"`.
- A recursive `fact` answers `--callers=fact` with `count="0"`.

**(c) "none-found" about a method something may call.** The fixture is three directories:

- `alpha/alpha.py`: `class Alpha` with `def run(self)`;
- `beta/beta.py`: `class Beta` with `def run(self)`;
- `caller/caller.py`: `def drive(worker): return worker.run()`.

The answers:

- `--safe-delete=alpha/alpha.py:run` gives `callers="0" uses="0" risk="none-found"`.
- `--edit-check=alpha/alpha.py:run` gives `callers="0" incompatible="0"`.

The map header reads `edges=0 ambiguous=0 unresolved=0 declined=1`. This is the shape
`test/declinecheck.sh` arm (A) *(#136)* pins as `declined_calls="1"` on `--callers`, yet these two verbs
still say nothing.

Then the census *(#136)*:

```bash
./build/ripwire . --no-cache --pin-census=census.tsv >/dev/null
grep '^# dispositions' census.tsv
```

It prints one balance line, for calls only.

---

## Design space and constraints

### The shape of the work

Plan three parts that land independently, in this order of risk.

**(c) first:** `declined_calls=` on `--safe-delete`, on `--edit-check`, and on the MCP `edit_check` twin.
- Use the SAME helper call over the SAME set as `--callers` and `--impact`.
- Decide what `risk="none-found"` should say when `declined_calls` is non-zero. It no longer means "zero
  callers AND zero uses" in any sense a reader would accept.
- Decide whether `--edit-check`'s `incompatible=` needs a companion: a declined site's compatibility is
  unknown, not compatible.

**(a) second:** a disposition enum and a census line per relation.
- Give each relation its own population predicate beside `isResolvableCallReference`.
- The census writer re-derives each population from `ing.references`.
- Then give each relation the answer surface it needs:
  - at least `--lego`, for the implementors it cannot see;
  - a decision for `--mentions` and for `<compose>`.

**(b) last, and plan it before any code:** decide, per answer, whether each of `file_scope`,
`other_root` and `self` belongs there, and write the reason into the plan.
- `--callers` leaving out recursion may be the right call.
- `--safe-delete` reporting `callers="0"` for a function called at module scope may not be.
- This is METHODOLOGY §9's question: what does the reader need to be TERMINAL on this answer?

### Constraints (CLAUDE.md and CONTRIBUTING.md; none of these is optional)

- **Write the gate before the code.**
  - Extend `test/declinecheck.sh` and the verb gates above.
  - Run each new arm against the pre-change binary and record it RED.
  - A new gate FILE is allowed, but it needs a `test/regression.sh` entry in the same commit
    (`test/manifestcheck.sh` checks) and it moves the published gate count. Prefer extending.
- **No edge moves.** This is disclosure, not resolution.
  - `edges=`, `ambiguous=`, `unresolved=` and `external=` stay identical on every corpus you measure.
  - The only map byte diff is the new attributes and their legend lines.
  - Changing the cross-root rule, the inheritance spray or the HAS-A pick is a different change that
    needs its own measurement. Flag it; do not do it here.
- **Determinism.** Every new count is independent of thread timing and iteration order. Check with
  `./build/ripwire <dir> >a; ./build/ripwire <dir> >b; diff -q a b`.
- **Honesty in output.** A zero means *none found*.
  - Every new attribute is **absent at zero**.
  - Its legend clause is written exactly when the attribute is. Pass the emitter's own condition, as
    `declinedCallsLegend( bool )` does. `test/legendcoveragecheck.sh` fails any attribute the leading
    legend does not define.
  - Units stay stated: a count of call SITES is never a count of site × candidate.
  - Every dialect carries it: XML, `--json`, `--format=columnar`, and the MCP twin
    (`test/mcpattrparitycheck.sh`).
- **`DEGRADED_PATH_ALERT`, never `VERIFY( false )`**, on an `Unaccounted` bucket. Release deletes
  whatever follows a false VERIFY.
- **No `std::map` or `std::unordered_map`.** Use `HashMap<>` (and reserve it) or `gtl::btree_map`; see
  "Containers" in CONTRIBUTING.md.
- **Style** (CONTRIBUTING.md §3):
  - Allman braces on every control body, and spaces inside parens.
  - Output goes through `rw::emitTo`.
  - Declarative tables, not switch chains.
- **Build discipline.**
  - Use the plain dev build. Never `-DCMAKE_BUILD_TYPE=Release`: `NDEBUG` compiles the alert out, and
    the conservation arm then passes blind.
  - Never edit while a build runs.
  - After rebasing onto `main`, run `cmake --build build --clean-first -j`.
- **Versions.** This should be resolution-only, so neither `kParserVer` nor `kCacheVersion` moves.
  - Prove it: a cache written by the base binary and read warm by yours must equal `--no-cache`.
  - If you find you must change extraction, bump `kParserVer` in `src/ingest_cache.h`, mirror
    `kIngestParserVerMirror` in `src/quality.h` in the same commit, and re-pin `test/qschemetrip.hash`
    with `UPDATE_GOLDEN=1 test/qschemetripcheck.sh`.

---

## Acceptance criteria

1. **Census.** `--pin-census` prints one balance line per relation: calls, inheritance, doc mentions and
   HAS-A.
   - Each line re-derives its population from `ing.references` and shows `unaccounted=0`.
   - It holds on `test/declinefix`, on this repository, and on one external corpus of your choice (name
     it).
   - Name the buckets in the plan.
2. **Mutation.** Delete one named disposition from each new loop. Its gate arm must go red, with
   `unaccounted` ≥ 1 and a `DEGRADED_PATH_ALERT` on stderr on the plain build. The arm reads the build
   flavour from `--version`, so a Release leg is not red and the plain build is not blind;
   `test/estchargecheck.sh` shows how to read it.
3. **`--lego`.**
   - On the two-root reproduction, the `<lego>` root says that a base clause naming this type was not
     bound, and why. The attribute is absent when nothing was dropped.
   - The same-named-interface reproduction is either disclosed, or explicitly deferred in the PR with its
     measurement.
4. **`--safe-delete` and `--edit-check`.**
   - The declined-method reproduction carries `declined_calls="1"` on both verbs, on the MCP `edit_check`
     twin, and in `--json`.
   - `risk=` no longer reads "none-found" beside a non-zero `declined_calls`, unless the PR argues why it
     should.
5. **Census-only buckets.** For each of `file_scope`, `other_root` and `self`: either it is on the answers
   the plan chose, with a legend clause, or it is explicitly left out with its reason in the PR.
6. **Nothing else moved.**
   - The default map is byte-identical except the new attribute and legend bytes, on this repo and on
     your external corpus.
   - Warm-from-old-cache equals `--no-cache`.
   - Two runs are identical, and `xmllint --noout` is clean.
   - ASan is clean over `test/declinefix`.
7. **Suite.**
   - `python3 test/pargates.py . ./build/ripwire -j 6` is green, run in the foreground.
   - `./build/ripwire . --quality-delta --legend=compact` shows zero unacknowledged regressions.

---

## Known traps (each cost somebody time on #136 or its neighbours)

**A sum of the buckets always balances.** If `calls=` is computed by adding up the buckets, the
conservation line is a tautology and catches nothing. Count the population independently, from
`ing.references`, through the same predicate the loop uses. #136's census does exactly this; copy the
discipline, not just the print.

**Per reference, not per candidate.** The inner `for` over candidates has its own `continue`s. Those
filter candidates; they do not end the reference.
- A reference with three candidates, two filtered and one bound, is `bound`.
- Put the tally on the outer iteration.
- Give "every candidate was filtered" its own named bucket or buckets.

**The population filter sits outside the tally.** `DispositionTally` is constructed after
`isResolvableCallReference` has rejected the non-calls. A tally constructed before that filter would
count every inheritance reference as an `Unaccounted` call.

**The alert is compiled out in Release.** `DEGRADED_PATH_ALERT` prints only when `NDEBUG` is undefined. A
gate that greps stderr for it must read the build flavour from `--version`. Otherwise it is red on CI's
Release leg, and silently blind if you ever configure Release locally.

**`other_root` exists only with two or more roots.** A single-root fixture can never reach it, so an arm
asserting it "balances" there passes vacuously. Run `ripwire dirA dirB` inside the fixture, as
`test/declinecheck.sh` arm (F) does.

**The MCP tools/list ceiling has almost no room.** #136 fitted its description text to 42,177 B against
`test/mcpmanifestcheck.sh`'s 42,200 B ceiling. A new MCP description sentence will not fit.
- The attribute key rides the existing verbs' JSON.
- Any wording goes in the legend, not the tool description.
- Never trim another verb's routing text to make room.

**A clean rebase is not a correct merge.** #134 and #136 merged with no textual conflict and still left
1,495 calls uncounted. After every rebase, rebuild with `--clean-first` and run the conservation arms
before anything else.

**Captures quote the output you are changing.** `docs/COMMANDS.md` and
`docs/captures/COMMANDS_showcase_*.md` are recorded runs, and #136 had to regenerate both. If an answer
you changed is quoted there, regenerate them in the same PR; their gates will tell you which.

**New fixed buffers are enumerated.** A new `char buf[N]` formatting site becomes a row in
`test/fixedbufsweep.sh` and moves its pinned count. `python3 docs/limits_build.py --check` must stay
clean.

**A dirty `docs/EVALS.md` in the worktree turns two MCP gates red.** If you touched it, commit it before
running `test/mcpattrparitycheck.sh`.

---

## What the PR description should contain

- **Base:** the `main` sha you branched from (after #136).
- **The enumeration:** every exit of each loop you changed, and the bucket it now lands in. The reviewer
  checks the list against the code, so make it checkable.
- **Red first:** each new arm's FAIL/PASS count on the pre-change binary, plus the mutation results (which
  disposition you deleted, and which arms went red).
- **Census numbers:** the balance lines for this repo and for your external corpus, `--no-cache`, with
  the corpus named. From a corpus under a source-available licence, publish counts, never code.
- **Byte evidence:** on both corpora the default map's diff is only the new attributes and legend lines;
  `edges=`, `ambiguous=`, `unresolved=` and `external=` are unchanged.
- **Decisions:**
  - for (b), which buckets reach which answers, and why;
  - for the inheritance spray and the HAS-A pick, disclosed or deferred, with the number that decided it.
- **Risks:** which answers will now carry the new attributes often, and whether any MCP text was fitted.

---

**Write the plan: the base branch, the per-loop enumeration, the buckets, the answer decisions, and the
red-first arms. Then STOP for my go-ahead.**
