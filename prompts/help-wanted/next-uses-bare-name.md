# Help wanted: make the callers answer's `next=` land on a declined call site

> **Solved.** @antoleod fixed this in [#182](https://github.com/redhat-et/ripwire/pull/182), closing
> [#158](https://github.com/redhat-et/ripwire/issues/158). The prompt stays as a worked example of a kit that landed;
> the paths, lines and outputs below describe the tree before that fix.

**Good first issue · size S · scheduled after the 0.6.0 release · builds on PR #136 (merged)**

You are fixing **one pointer**. When `--callers` cannot show a call as a row because the resolver
declined to bind it, the answer says so (`declined_calls="1"`) and hands the reader a `next=`
invocation meant to show that call site. For a bare name it does. For a narrowed selector —
`file:name`, `@FILE:LINE`, a canonical id, `Scope::name` — it points at an answer that **cannot**
list the site, and the reader lands on `count="0"`.

This is not a tour. Every path, line and output below was checked against PR #136's head,
`c181d2be` (2026-09-11), by running that binary on its own fixture. That head is what merged into
`main` as d752d953. Line numbers move; every pointer also names its symbol, so
`git grep -n <symbol>` finds it again after they do.

Outputs move too. **Your baseline is the commit you branch from, not `c181d2be`**: build that base,
run the STEP 1 block on it, and record what it prints. Every "leave this byte-identical" below means
byte-identical to *that*, and the STEP 3 controls are pinned against it. Where your base disagrees
with a printed tag here, the base is right and this file is out of date — say which rows moved in the
plan.

Work in a git worktree, not the main checkout. Run every gate in the foreground.

---

## Why it matters

An answer here is supposed to end the search: a gap is acceptable when the answer names the one
call that closes it (`docs/METHODOLOGY.md` §9, principle 3). `next=` is that call —
`src/nextverb.h` defines it as the pasteable follow-up. An agent that pastes it and gets
`count="0"` has been sent to an empty answer **by the tool itself**, and that zero reads as "no call
site exists", which is the exact misreading PR #136 was written to end (`CLAUDE.md`, non-negotiable
3: a zero means "none found", never "none exists").

PR #136 made the decline visible. This issue makes its pointer land on the evidence.

---

## STEP 0 — the prerequisite: PR #136 is on your base

PR #136, `fix/tier3-drop-disclosure-2026-09-11` ("a declined call no longer reads as 'no caller
exists'"), merged into `main` as d752d953 on 2026-09-11. That PR added:

- `declined=N` on the map header (JSON `"declined"`), absent at zero — calls the resolver declined
  to guess at: two or more same-language definitions of the called name, none in the caller's file
  or directory, and no qualifier, receiver type or include to pick one, so no edge is made;
- `declined_calls="K"` on the `--callers`, `--callees` and `--impact` roots in XML, `--json` and
  `--format=columnar`, and the same key on the MCP twins `find_referencing_symbols`, `find_symbol`
  and `impact`;
- the legend sentence that defines the key, emitted exactly when the key is;
- `test/declinecheck.sh` and its fixture `test/declinefix/`: per language, one same-named method in
  each of two directories, called through an untyped receiver from a third (`alpha/`, `beta/` and
  `caller/` for Java, C++, Python and Rust; `sweep/<language>/` for the rest).

Check before anything else that your base carries it:

```bash
git fetch origin
git grep -n declinedCallsNaming origin/main -- src/graph.h     # a hit means #136 is on main
```

No hit: **stop and say so.**

---

## STEP 1 — build and reproduce

```bash
cmake -S . -B build && cmake --build build -j       # the plain dev build — never add a build type
cd test/declinefix                                  # the gate runs every selector from here, root `.`
../../build/ripwire . --no-cache --callers=jbody
../../build/ripwire . --no-cache --uses=jbody
../../build/ripwire . --no-cache --callers=java/alpha/Alpha.java:jbody
../../build/ripwire . --no-cache --uses=java/alpha/Alpha.java:jbody
```

`jbody` is defined in `java/alpha/Alpha.java` and `java/beta/Beta.java` and called once, as
`response.jbody()` on an `Object`, at `java/caller/JavaCaller.java:7`. Nothing can pin that call to
either definition, so it has no edge. The root tags as they print at `c181d2be` (the fixture-wide
`graph_*`, `hop_*`, `root=` and `counts_floor=` attributes elided as `…`):

```
--callers=jbody                        <callers of="jbody" defs="2" count="0" … declined_calls="1" … next="--uses=jbody">
--uses=jbody                           <uses of="jbody" defs="2" external="0" count="1" …>
                                         <u role="call" p="java/caller/JavaCaller.java:7" in_id="javaDeclined"/>
--callers=java/alpha/Alpha.java:jbody  <callers of="java/alpha/Alpha.java:jbody" defs="1" count="0" … declined_calls="1" … next="--uses=java/alpha/Alpha.java:jbody">
--uses=java/alpha/Alpha.java:jbody     <uses of="java/alpha/Alpha.java:jbody" defs="1" external="0" count="0" defs_of_name="2" narrowed_roles="call" call_sites_of_name="1" …>
                                         (no rows)
```

The first pair is the pointer working. The second pair is the gap: the pointer keeps the selector,
the narrowed uses answer keeps only call sites that **resolve** to the chosen definition, a declined
call resolves to none, and the site survives only as arithmetic — `call_sites_of_name="1"` minus
zero rows shown.

Run the other narrowed spellings. The gap is the same on every one, and worse on two:

| `--callers=` selector | `next=` it carries today | what that pointer's answer shows |
| --- | --- | --- |
| `@java/alpha/Alpha.java:5` (line seed) | `--uses=@java/alpha/Alpha.java:5` | `count="0"`, `call_sites_of_name="1"`, no rows |
| `cpp/alpha/alpha.cpp:crender` | `--uses=cpp/alpha/alpha.cpp:crender` | `count="0"`, `call_sites_of_name="1"`, no rows |
| `cpp/alpha/alpha.cpp::Alpha::crender` (canonical id) | `--uses=cpp/alpha/alpha.cpp::Alpha::crender` | `count="0"`, **no** `call_sites_of_name=` at all |
| `Alpha::crender` (`Scope::name`) | `--uses=Alpha::crender` | `count="0"`, **no** `call_sites_of_name=` at all |

Every row above carries `declined_calls="1"`; the declined `crender` site is
`cpp/caller/caller.cpp:3`. The two `::` spellings are worse because `--uses` matches sites against
the whole spelling there (STEP 2), and that is true even when nothing was declined:
`--callers=cpp/pair/one.cpp::One::ctwin` answers `count="1"` with
`next="--uses=cpp/pair/one.cpp::One::ctwin"`, and at `c181d2be` that answer is `count="0"`. **That
bound case is a separate, older gap and not this change's to close. Leave whatever your base prints
for it byte-identical.**

**The sibling kit.** `prompts/help-wanted/uses-qualified-selector.md` is that older gap. It has no
prerequisite and can land **before** this one, so run the bound pair on your own base before you
believe the paragraph above:

```bash
../../build/ripwire . --no-cache --callers=cpp/pair/one.cpp::One::ctwin
../../build/ripwire . --no-cache --uses=cpp/pair/one.cpp::One::ctwin
```

If that second answer is already `count="1"`, the sibling has landed: the bound gap is closed, the
STEP 6 follow-up bullet is moot, and the declined `::` spellings in the table above now carry the
`file:name` disclosure that kit adds — so re-read the two rows that say "**no** `call_sites_of_name=`
at all" against your base before you pin a gate row on them. If it is `count="0"`, the sibling has
not landed and the table stands as printed. Either way the two changes touch different code, must not
be combined into one PR, and neither is a prerequisite for the other.

Controls that must not move:

```
--callers=java/solo/Solo.java:jonly    <callers … count="1" … next="--uses=java/solo/Solo.java:jonly">       (no declined_calls)
--callees=javaDeclined                 <callees … count="0" … declined_calls="1" … next="--expand=javaDeclined">
--impact=java/alpha/Alpha.java:jbody   <impact … declined_calls="1" … next="--safe-delete=java/alpha/Alpha.java:jbody">
```

---

## STEP 2 — read the code

Line numbers are at `c181d2be`.

**Where the callers answer builds and emits `next=`** — `src/verbs_navigate.h`, `runCallHierarchy`
(line 67):

- line 152 — `chNextAttr = rw::nextAttrXml( rw::nextFlag( wantCallers ? "--uses=" : "--expand=", sym ) )`,
  where `sym` (line 84) is the selector exactly as typed. **This is the line the fix changes.**
- line 177 puts the same `chNextAttr` on the `--format=columnar` root; line 217 on the XML root.
- lines 186–204, the `--json` branch, carry `declined_calls` (line 196) but **no `next` key** —
  today, and after this fix. Adding a key is a vocabulary change of its own.
- lines 137–147 print the legend before the format branch, so XML and columnar read the same
  sentences; line 144 appends the declined clause exactly when `declined_calls` is emitted.

**Where `declined_calls` is computed:**

- `src/callhierarchy.h` line 112 — `declinedCallsNaming( g, out.matches )` for callers,
  `declinedCallsMadeBy` for callees. `out.matches` (line 79) is every definition the selector
  resolved to; this one computation serves the CLI and both MCP find verbs.
- `src/graph.h` line 6263 `declinedCallsNaming` (declines naming any target among their candidates,
  one count per call) and line 6294 `declinedCallsMadeBy`; the decline is recorded in the resolve
  loop at lines 2497–2506.
- `src/graphlegend.h` lines 441–448 — `declinedCallsAttrXml` and `declinedCallsKeyJson`, both
  absent at zero.

**The legend the fix must keep true** — `src/graphlegend.h`:

- line 401, in `callHierarchyLegendOpen` (lines 396–403), the callers form says
  `next= is the one pasteable follow-up (the uses verb on this selector: the call sites).` That
  sentence becomes **false** on exactly the answers this fix changes.
- lines 436–438 — `kDeclinedCallsLegend`, which already ends
  `the uses verb on the called name lists the sites.`, and `declinedCallsLegend( bool on )`, which
  takes the emitter's own condition rather than re-deriving it. Copy that shape.

**The `next=` contract** — `src/nextverb.h`:

- lines 2–15: every root carries exactly ONE `next=`, at most `kNextAttrMaxBytes` (line 26, 120 B);
  line 12 documents the callers pointer as `--uses=SELECTOR`. `test/nextverbcheck.sh` runs every
  `next=` that starts with `--` through the argv parser and requires exit 0 or 4.
- line 30 `kNextLegendClause`, line 35 `nextAttrXml`, line 72 `nextFieldJson`, line 95 `nextFlag`
  (single-quotes a value a shell would split). Build the new pointer through `nextFlag` too.

**Why the narrowed `--uses` cannot list the site** — `src/verbs_navigate.h`:

- lines 327–368, `resolveUsesSelector`: an `@FILE:LINE` seed rebinds to the seed's name with
  `fileQualified = true` (lines 331–354); line 355 sets `fileQualified` only for a `:` with no `::`,
  so a canonical id or `Scope::name` keeps its whole spelling as `siteMatchName`, which no
  reference name equals.
- line 380, `usesChosenCallers`, and line 444 in `collectUseSites` (lines 416–469): the `continue`
  that drops every call site whose enclosing symbol has no resolved edge to a chosen definition. A
  declined call has no edge.
- lines 566–568 — `call_sites_of_name=` is emitted for file-qualified selectors only.

**The MCP twins** — `src/mcpverbs.h`, `symbolQueryJson` (line 579):

- line 586 — `callHierarchyRows( ing, g, name, /*wantCallers=*/referencingOnly )`:
  `find_referencing_symbols` computes the callers direction; `find_symbol` computes callees there and
  callers in a second pass (lines 593–597).
- lines 659–660 — `declinedCallsKeyJson( chRows.declinedCalls )`, then
  `nextFieldJson( nextFlag( referencingOnly ? "--uses=" : "--expand=", name ) )`. The
  `find_referencing_symbols` half is the twin of `verbs_navigate.h` line 152 and must change with
  it. At `c181d2be`, `symbol: "java/alpha/Alpha.java:jbody"` returns
  `"declined_calls":1,"next":"--uses=java/alpha/Alpha.java:jbody"`.
- `src/mcp.h` lines 707 and 709 — the two tools' descriptions. Neither mentions `next`; leave both
  alone (see TRAPS).

**The surfaces that stay as they are.** Say so in the plan and in the PR; do not just skip them.

| surface | `next=` today | why it already lands, or is a different question |
| --- | --- | --- |
| `--callees`, every dialect | `--expand=SELECTOR` | `declined_calls` counts calls the selector's own body makes, and the body is where they are |
| MCP `find_symbol` | `"next":"--expand=…"` | its `declined_calls` is the callees direction (line 586), same reason |
| `--impact` XML and columnar (`verbs_navigate.h` lines 2102, 2049; its JSON, 2061–2082, has no `next`) and MCP `impact` (`mcpverbs.h` line 2283) | `--safe-delete=SYM` | a different follow-up ("can it go"), and its `declined_calls` also counts declines into radius symbols (`verbs_navigate.h` 2154–2156, `mcpverbs.h` 2236–2238), which no `--uses` on one name lists |

If one of these turns out not to land, write it down as a follow-up. Do not widen this change.

---

## STEP 3 — the gate, written RED first

The gate already exists: `test/declinecheck.sh`, section (E), lines 220–319. Read the header's arm
list (lines 33–52), then these blocks:

- lines 240–275 — the bare-name arm this issue builds on. For `jbody`, `crender`, `pyfetch` and
  `rfetch` it asserts (a) `next="--uses=NAME"`; (b) that pointer, run verbatim with `rw "$NEXT"`,
  lists the declined site's `file:line` through the `call_sites` helper (line 103); (c) the call
  sites no caller row encloses number exactly `declined_calls`. `jtwin`, `ctwin` and `pytwin` are
  the bound controls.
- lines 276–288 — **the arm you change.** On `DEF=java/alpha/Alpha.java:jbody` it asserts only that
  `next=` is `--uses=$DEF` and that `call_sites_of_name` minus the call rows shown is at least
  `declined_calls`. It accepts a pointer that lands on nothing, so long as arithmetic discloses it.
- lines 376–391 — section (G), "the predicates can fail"; lines 389–391 are the site predicate's
  failure shape.

Turn lines 276–288 into a loop over the narrowed spellings, each verified at `c181d2be` to carry
`declined_calls="1"`:

```
selector                              | bare name | declined site
java/alpha/Alpha.java:jbody           | jbody     | java/caller/JavaCaller.java:7
@java/alpha/Alpha.java:5              | jbody     | java/caller/JavaCaller.java:7
cpp/alpha/alpha.cpp:crender           | crender   | cpp/caller/caller.cpp:3
cpp/alpha/alpha.cpp::Alpha::crender   | crender   | cpp/caller/caller.cpp:3
Alpha::crender                        | crender   | cpp/caller/caller.cpp:3
```

On every row, assert:

1. the XML root's `next=`, run verbatim, **lists the declined site** — this is the property; the
   rest supports it;
2. that `next=` is `--uses=<bare name>`;
3. the `--format=columnar` root carries the same `next=`;
4. MCP `find_referencing_symbols` on the same selector returns the same `"next"` (the `mcp_text` and
   `call` helpers at lines 302–310 already speak JSON-RPC);
5. the callers legend on that answer defines the pointer it emits, not the "on this selector"
   sentence.

Controls, green before and after:

6. `--callers=java/solo/Solo.java:jonly` (file-qualified, nothing declined) keeps
   `next="--uses=java/solo/Solo.java:jonly"` and today's legend sentence;
7. the bare-name arm, lines 240–275, is unchanged and green.

Add a row to (G) proving the new "is it the bare name" predicate fails on a synthetic root that
still names the narrowed selector, and update the header's (E) and (G) lines to say what the arm now
proves. This edits an existing gate file, so `test/regression.sh` and the published gate count do
not move.

**Red first.** Build the pre-fix binary in a second worktree at the same `origin/main` commit and
point the gate at it — the header's usage line (line 6) is `test/declinecheck.sh build_base/ripwire`:

```bash
git worktree add ../rw-base origin/main
cmake -S ../rw-base -B ../rw-base/build && cmake --build ../rw-base/build -j
test/declinecheck.sh ../rw-base/build/ripwire     # the new rows FAIL; every pre-existing row still PASSes
```

Keep that FAIL list; it goes in the PR. A gate that has never failed is not evidence it can.

---

## STEP 4 — the fix: constraints, not code

The design is yours to write in the plan. These are the edges it has to stay inside.

- **ONE `next=`.** XML cannot carry two attributes of one name, `src/nextverb.h` promises exactly
  one, and a second pointer under a new name is new vocabulary: a legend definition, a key on the MCP
  twin (`test/mcpattrparitycheck.sh` diffs the CLI root's attribute names against the MCP keys), and
  bytes on every answer that carries it. If you think both pointers are needed, argue it in the plan
  with those costs. The default is one pointer.
- **The condition:** the callers direction, `declined_calls > 0`, and a selector that is not already
  the bare name. One way to get the bare name for every spelling in STEP 3 is the name of the
  resolved definitions; confirm in `resolveAllByNameQualified` (`src/graph.h` line 4080) that they
  always share one before relying on it. Everywhere else — nothing declined, or a bare selector —
  **today's pointer, byte for byte.**
- **One derivation, both surfaces.** `verbs_navigate.h` line 152 and `mcpverbs.h` line 660 call the
  same function. Two emitters of one computation drifting apart is the defect class
  `src/callhierarchy.h`'s header describes. Name the helper's home in the plan.
- **The legend defines what is emitted.** Give the callers clause a variant that fires on exactly
  the answers carrying the bare pointer, passed the emitter's own condition the way
  `declinedCallsLegend( bool )` is. It says what the reader gets: the uses verb on the called
  *name*, whose rows are every same-named definition's sites, because a declined call names no single
  definition. No double hyphen anywhere in it — it lands inside an XML comment. Answers where it does
  not fire keep today's bytes.
- **State the trade-off.** The bare pointer is wider than the selector: its rows include sites that
  bind to *other* definitions of the name. That is the price of landing on the declined site; the
  legend variant and the PR both say so. The alternative — teaching the narrowed `--uses` to keep
  declined sites whose candidates include the chosen definition — changes that verb's contract, its
  legend and its MCP twin, and is not this issue.
- **Paging.** `--uses` has a default row cap (`kUseSiteRowCap`, disclosed with `shown=`/`capped=`).
  On a name with many sites, the declined one can sit past the first page. The fixture cannot show
  that; the plan says what the reader gets in that case.
- **Keep the pointer pasteable:** built through `nextFlag`, at most 120 B, green under
  `test/nextverbcheck.sh`.
- **Comments that document the old contract move with it:** `src/nextverb.h` line 12 and the
  `test/nextverbcheck.sh` header.
- **House rules** (`CLAUDE.md`, `CONTRIBUTING.md` §3): write the gate before the code; determinism is
  a contract; Allman braces and braces on every body; spaces inside parentheses; output through
  `rw::emitTo`; never `std::map` or `std::unordered_map`; a degrade path uses
  `DEGRADED_PATH_ALERT`, never `VERIFY( false )`.

---

## STEP 5 — acceptance

On a build of your final commit, every command in the foreground:

```bash
cmake -S . -B build && cmake --build build -j
test/declinecheck.sh                                  # green here, red on ../rw-base (STEP 3)
bash test/nextverbcheck.sh
bash test/mcpattrparitycheck.sh
bash test/mcpclidiffcheck.sh
bash test/legendcoveragecheck.sh
bash test/printffmtparitycheck.sh
bash test/showcasecapturecheck.sh
bash test/docscommandscheck.sh
python3 test/pargates.py . ./build/ripwire -j 6        # the full suite
./build/ripwire . --quality-delta --legend=compact     # only what the change made worse — zero regressions
./build/ripwire . --test-gate                          # then the tests to run and the untested blast radius
```

- `mcpattrparitycheck` and `mcpclidiffcheck` compare the CLI and MCP twins attribute by attribute;
  `legendcoveragecheck` fails when a first screen carries an attribute its legend does not define.
- `printffmtparitycheck` hashes the stdout and stderr of a fixed verb corpus against
  `test/printf_parity.manifest`. Its `--callers`, `--uses` and `--impact` rows use bare names, so a
  conditional change should move none of them. If a label goes red anyway, run the gate first and
  read which labels are red; re-pin with `UPDATE_GOLDEN=1 bash test/printffmtparitycheck.sh` only
  when you can explain every one of them, then review the manifest diff so that only those rows
  moved, and name each in the commit message.
- `docs/captures/` and `docs/COMMANDS.md` hold recorded output. At `c181d2be` their `--callers` and
  `--uses` invocations are bare names (`rankGraphTeleport`), so they should not move either. If any
  recorded output does change, regenerate on a clean committed tree, rebuild the reference, run
  `showcasecapturecheck` and `docscommandscheck` again, and commit the regeneration by itself
  (`CONTRIBUTING.md` §6, item 6):

  ```bash
  PYTHONDONTWRITEBYTECODE=1 python3 test/showcase_capture.py
  python3 docs/docs_commands_build.py
  ```

---

## TRAPS — each one has cost somebody a day here

**Recorded output from a dirty tree.** A capture records the tree it ran on, and its diff-aware
captions record a dirty tree as dirty. Commit first, then regenerate, then commit the regeneration
on its own.

**`__pycache__` moves the crawl.** Python gates that import from the checkout write `__pycache__/`
into it. The name is gitignored, so `git status` stays clean, but the crawl counts the directory and
a live-tree answer can differ between two runs. The suite runners export `PYTHONDONTWRITEBYTECODE=1`;
do the same for anything you run by hand, which is why the capture command above carries it.

**The MCP tool list is 23 B from its ceiling.** `test/mcpmanifestcheck.sh` caps the whole
`tools/list` payload at 42,200 B (line 205), and a binary built from `c181d2be` measures 42,177 B.
This fix needs no description change — neither tool's description mentions `next` — so do not touch
`src/mcp.h`. That gate's own rules move the ceiling for a declared argument, never for prose.

**A clean rebase can still be wrong.** git merges text; the invariants here are about populations.
If `main` moves under you, everything **generated, pinned or recorded** — `test/printf_parity.manifest`,
the captures, `docs/COMMANDS.md`, the published gate count — is re-derived after the rebase by
rebuilding and re-running its generator, never by picking a side of a conflict. A rebase with no
conflict markers is not evidence those files are right.

**A build that saw the tree move.** Never edit while a build runs, and never background a build you
then edit around. After a rebase or branch switch, rebuild with
`cmake --build build --clean-first -j`: an incremental build across a changed header can produce a
binary no single commit can, and every symptom then points somewhere else (`CLAUDE.md`, "Build").

---

## STEP 6 — what the PR description contains

- **Before and after** for the STEP 1 invocations on `test/declinefix`, root tags only, plus one
  line per narrowed spelling in the STEP 3 table.
- **What changed** — the callers answer in XML and columnar, MCP `find_referencing_symbols`, the
  callers legend — **and what deliberately did not**: `--callees`, MCP `find_symbol`, `--impact` and
  MCP `impact`, the CLI `--json` key set, each with its one-line reason from STEP 2.
- **Red-first evidence:** the FAIL rows `test/declinecheck.sh` printed against the pre-fix binary,
  and its PASS count after.
- **Byte-identity evidence** where the pointer must not move: `cmp` of pre- and post-fix output for
  `--callers=java/solo/Solo.java:jonly` and for `--callers=jbody`, and the gate rows that pin both.
- **Every STEP 5 gate with its result**, and the `--quality-delta` and `--test-gate` summaries.
- **Every re-pinned manifest row or regenerated capture**, each with its reason, in its own commit.
- **Follow-ups found and not fixed** — at least the `::` spellings whose uses answer is `count="0"`
  when nothing was declined (STEP 1), unless `uses-qualified-selector.md` landed first and your base
  already answers them, in which case say that instead.
- A link to PR #136.

---

**Write the plan — the condition and where it is computed, the legend variant, the gate rows and
their red run, the surfaces left alone and why, the gates you will run — then STOP for my go-ahead.**
