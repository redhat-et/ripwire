# Help wanted: make `--uses` answer a `::` selector instead of a silent zero

**Good first issue · size M · no prerequisite · one comparison, three CLI verbs and one MCP twin downstream**

You are fixing **one comparison**. Every symbol-taking verb accepts the two `::` spellings the tool
prints about itself: the canonical id `path::scope::name` (the `id=` on every map row) and
`Scope::name` (the `sym=` that `--edit-check` prints). `--callers`, `--callees`, `--impact` and
`--expand` resolve them. `--uses` resolves them too, reports `defs="1"`, and then answers
`count="0"` with no rows, on a symbol that has a call site. Nothing in the answer says the zero is a
spelling artifact.

This is not a tour. Every path, line and output below was checked against `main` at `f22081b0`
(2026-09-11), by running a build whose `src/` is identical to that commit on the fixtures named. Line
numbers move; every pointer also names its symbol, so `git grep -n <symbol>` finds it again after they do.

Work in a git worktree, not the main checkout. Run every gate in the foreground.

---

## Why it matters

- `--help` promises the spelling works: under `--callers`, `Scope::name picks one scope's definition —
  the sym= spelling edit-check prints resolves everywhere` (`src/cli.h` line 1025).
- `--callers` hands the reader this exact dead end. `--callers=cpp/pair/one.cpp::One::ctwin` answers
  `count="1"` with `next="--uses=cpp/pair/one.cpp::One::ctwin"`, and that pointer, pasted, is `count="0"`.
- `count="0"` beside `defs="1" external="0"` reads as "defined here, and nothing uses it". That is the
  misreading `CLAUDE.md` non-negotiable 3 exists to prevent: a zero means "none found", never "none exists".
- `--safe-delete`, the verb whose whole question is "can this go", reads the same scan and prints
  `uses="0"` beside `callers="1"`. `--verify="uses(Solo::conly)"` answers `not-established` where the bare
  name is `confirmed`.
- On this repository: `--callers=NoteIndex::empty` counts 816 callers; `--uses=NoteIndex::empty` counts 0.

**The sibling kit.** `prompts/help-wanted/next-uses-bare-name.md` (opened alongside this one; if it is not on
`main` yet, read it on its PR) changes the callers answer's `next=` on a **declined** call. It names this
**bound** `::` case as "a separate, older gap" and leaves it alone. This issue is that gap. The two changes
touch different code, can land in either order, and must not be combined into one PR.

---

## STEP 0 — check the ground has not moved

```bash
git fetch origin
git grep -n 'u.fileQualified = sym.find( "::" )' origin/main -- src/verbs_navigate.h   # a hit: the gap is still there
bash test/usesselectorcheck.sh | grep -c 'PASS  .*KNOWN GAP (help wanted'               # 12 on a build of f22081b0
```

No hit, or the count moved: someone has touched this. Run STEP 1 before anything else, and if `--uses` on a
`::` selector no longer answers the silent zero, **stop and say so.**

---

## STEP 1 — build and reproduce

```bash
cmake -S . -B build && cmake --build build -j       # the plain dev build — never add a build type
cd test/declinefix                                  # every selector below is relative to this root, `.`
../../build/ripwire . --no-cache --callers=cpp/pair/one.cpp::One::ctwin
../../build/ripwire . --no-cache --uses=cpp/pair/one.cpp::One::ctwin
../../build/ripwire . --no-cache --uses=cpp/pair/one.cpp:ctwin
../../build/ripwire . --no-cache --uses=ctwin
```

**Never configure with `-DCMAKE_BUILD_TYPE=Release`.** Release defines `NDEBUG`, which compiles
`DEGRADED_PATH_ALERT` out, and a gate that asserts a degrade path then passes blind (`CLAUDE.md`, "Build").

`ctwin` is defined twice in one directory, `cpp/pair/one.cpp:3` (`struct One`) and `cpp/pair/two.cpp:3`
(`struct Two`), and called once, as `t.ctwin()` on a template parameter at `cpp/pair/user.cpp:3`. The
resolver binds that call to both (a same-directory split), so both definitions have a caller. The root tags
as they print (the fixture-wide `graph_*`, `root=` and `counts_floor=` attributes elided as `…`):

```
--callers=cpp/pair/one.cpp::One::ctwin  <callers of="cpp/pair/one.cpp::One::ctwin" defs="1" count="1" … next="--uses=cpp/pair/one.cpp::One::ctwin">
                                          <s t="fn" n="cppSplit" p="cpp/pair/user.cpp:1"/>
--uses=cpp/pair/one.cpp::One::ctwin     <uses of="cpp/pair/one.cpp::One::ctwin" defs="1" external="0" count="0" …>
                                          (no rows)
--uses=cpp/pair/one.cpp:ctwin           <uses of="cpp/pair/one.cpp:ctwin" defs="1" external="0" count="1" defs_of_name="2" narrowed_roles="call" call_sites_of_name="1" …>
                                          <u role="call" p="cpp/pair/user.cpp:3" in_id="cppSplit"/>
--uses=ctwin                            <uses of="ctwin" defs="2" external="0" count="1" …>
                                          <u role="call" p="cpp/pair/user.cpp:3" in_id="cppSplit"/>
```

One definition, three spellings. The `file:name` and bare spellings land on the call site; the canonical id
does not.

**Which spellings fail.** `--callees`, `--impact` (`reaches=` equals the callers count on every row) and
`--expand` resolve every selector in this table; only `--uses` loses it.

| selector | fixture | shape | `--callers` | `--uses` today | bare-name `--uses` |
| --- | --- | --- | --- | --- | --- |
| `ctwin` | `test/declinefix` | bare name | `count="1"` | `count="1"`, `cpp/pair/user.cpp:3` | (itself) |
| `cpp/pair/one.cpp:ctwin` | same | file:name | `count="1"` | `count="1"`, same row | — |
| `@cpp/pair/one.cpp:3` | same | line seed | `count="1"` | `count="1"`, same row | — |
| `cpp/pair/one.cpp::One::ctwin` | same | canonical id | `count="1"` | **`count="0"`**, no rows | `count="1"` |
| `One::ctwin` | same | `Class::method` | `count="1"` | **`count="0"`** | `count="1"` |
| `Solo::conly` | same | `Class::method`, a unique global | `count="1"` | **`count="0"`** | `count="1"` |
| `cpp/solo/solo.cpp::Solo::conly` | same | canonical id | `count="1"` | **`count="0"`** | `count="1"` |
| `ns::pick` | same | `namespace::function`, `defs="2"` | `count="1"` | **`count="0"`** | `count="1"` |
| `cpp/ns_impl/pick_int.cpp::ns::pick` | same | canonical id in a namespace | `count="1"` | **`count="0"`** | `count="1"` |
| `Widget::step` | same | out-of-line member, `defs="4"` | `count="1"` | **`count="0"`** | `count="1"` |
| `One::pytwin` | same | Python `Class::method` | `count="1"` | **`count="0"`** | `count="1"` |
| `py/pair/one.py::One::pytwin` | same | Python canonical id | `count="1"` | **`count="0"`** | `count="1"` |
| `util::tool` | `test/rustqualfix` | Rust `mod::fn` | `count="1"` | **`count="0"`** | `count="1"` |
| `src/lib.rs::util::tool` | same | Rust canonical id | `count="1"` | **`count="0"`** | `count="1"` |
| `Widget::new` | same | Rust `Type::assoc` | `count="2"` | **`count="0"`** | `count="4"` (three defs named `new`) |
| `Gadget::new` | same | Rust `Type::assoc` | `count="1"` | **`count="0"`** | `count="4"` |

**The same zero on every surface that reads the scan:**

| surface | bare spelling | `::` spelling |
| --- | --- | --- |
| `--uses … --format=columnar` | `cpp/pair/one.cpp:ctwin`: `count="1"`, `<cols n="1" …>` | `cpp/pair/one.cpp::One::ctwin`: `count="0"`, `<cols n="0" …>` |
| `--safe-delete=` | `conly`: `callers="1" … uses="1"` | `Solo::conly`, and its canonical id: `callers="1" … uses="0"` |
| `--verify="uses(…)"` | `conly`: `verdict="confirmed" count="1"` | `Solo::conly`: `verdict="not-established" count="0" limit="reference-floor"` |
| `--verify="unused(…)"` | `conly`: `verdict="refuted"` | `Solo::conly`: `verdict="not-established"` |
| MCP `uses` (`"symbol"`) | `ctwin`: `count="1"` | `One::ctwin`, `cpp/pair/one.cpp::One::ctwin`, `ns::pick`, `Solo::conly`: `count="0"` |
| this repository | `--uses=src/notes.h:empty`: `count="2193"` | `--uses=NoteIndex::empty` and `--uses=src/notes.h::NoteIndex::empty`: `count="0"` |

Two notes. MCP `uses` **refuses** a `file:name` spelling by design (`qualified file:name selectors are
CLI-only on this verb`), so on MCP the `::` spellings are the only qualified ones it answers, and it answers
them wrong. `--uses` does not support `--json` for any spelling, so there is no JSON dialect to fix.

**Not this issue.** These fail on every verb alike, so `--uses` is not the odd one out. Do not widen into them;
list any you confirm as follow-ups.

| selector | what happens |
| --- | --- |
| `crate::util::tool`, `util::deep::deepfn`, `crate::gadget::gadget_free`, `crate::Widget::new` (`test/rustqualfix`) | all five verbs exit 1, "symbol not found" |
| `App::Admin::User`, `App::Services::Job` (`test/rubyconstfix`) | all five exit 1. `Admin::User` and `App::Helper` resolve everywhere, but they are classes with no call edge, and even the bare `--uses=User` is `count="0"` there, so that fixture cannot show this gap for Ruby |
| `One::jtwin`, `java/pair/One.java::One::jtwin` (`test/declinefix`) | all five exit 1 on this fixture |
| `One.ctwin`, `One.pytwin` (dotted) | the four graph verbs exit 1; `--uses` takes the member-FIELD route and refuses, naming `./java/pair/One.java` for the C++ and Python owner too |

---

## STEP 2 — read the code

Line numbers are at `f22081b0`.

**Why `--callers` does not care about the spelling** — `src/callhierarchy.h`, `callHierarchyRows` (line 74):
line 79 resolves `out.matches = resolveAllByNameQualified( ing, selector )`, and every row after that is read
off the graph's edges on those node ids. The spelling is gone once the ids exist.

**The shared resolver** — `src/graph.h`:

- `resolveAllByNameQualified` (line 4080). Lines 4096–4108: a spec carrying `::` tries
  `resolveAllByCanonicalId` (line 3944) and then `resolveAllByScopeQualified` (line 3631; the `::`-boundary
  suffix rule is `scopeSuffixMatches`, line 3493) before the `file:name` split (`splitQualifiedSpec`, line
  3474). The scope tier landed in `ac02257b` (2026-08-30, "the tool's own spellings resolve").
- Line 3643: the scope tier matches `s.name == name`, and a canonical id ends in the name, so a non-empty
  result from either tier shares ONE name. Confirm that yourself before relying on it.
- Lines 3957–3959: "no indexed symbol NAME contains `::` in any grammar we parse". That sentence is why the
  next comparison can never match.

**Where `--uses` resolves the selector and then drops it** — `src/verbs_navigate.h`:

- `runUses` (line 491). Line 518: `defs = resolveAllByNameQualified( ing, sym )`, the same resolver, so
  `defs=` is right. Line 519: `sel = resolveUsesSelector( ing, sym, defs.size() )`.
- `resolveUsesSelector` (lines 328–368). The `@FILE:LINE` arm (lines 331–354) **rebinds** to the seed
  definition's name and sets `fileQualified = true`: that is the precedent for this fix. Line 355 sets
  `fileQualified` only for a `:` with no `::`; line 363 otherwise keeps `siteMatchName = sym`, the whole
  spelling. The comment above (lines 321–326) says a canonical id "was never a use-site match key and stays
  byte-identical". It was written before the scope tier existed, and it is the sentence this issue retires.
- `collectUseSites` (lines 416–469). **Line 425, `if( r.calleeName != sel.siteMatchName )`, is the root
  cause:** `r.calleeName` is a bare name, the match key is `One::ctwin`, every reference is skipped.
- Line 444: the call-role narrowing a `file:name` selector gets. `usesChosenCallers` (line 380) marks every
  symbol with a resolved edge into a chosen definition, and a call site survives only inside a marked symbol.
- Lines 546–549 refuse a `file:name` selector that resolved nothing; lines 556–561 refuse any selector with
  no definitions and no sites. The second is why a wrong scope (`Nope::ctwin`) refuses today. Keep that.
- Lines 566–568 emit `defs_of_name=`, `narrowed_roles="call"` and `call_sites_of_name=` only when
  `fileQualified`. Lines 582–590 are the legend body: `A "file:name" SYM narrows defs= AND the role="call"
  sites … (file: qualifier only)`.

**The same scan in two more verbs** — `runSafeDelete` (line 718) at lines 779–784, and `runVerify` (line 1322),
the `uses()`/`unused()` arm at lines 1444–1451. Both call `resolveUsesSelector`, `usesChosenCallers` and
`collectUseSites`. A fix inside `resolveUsesSelector` reaches all three verbs; the gate proves whether it did.
The comment at lines 779–781 ("Always a bare-name selector …") is already stale.

**The MCP twin has its own copy** — `src/mcpverbs.h`:

- `usesSelectorRefusal` (line 2371). Lines 2386–2390 pass any spelling containing `:` to
  `qualifiedSelectorRefusal` (line 2331), which returns "" when `resolveAllByName( ing, symbol )` resolves
  the whole spelling (line 2357). `resolveAllByName` (`src/graph.h` line 3960) has the same two `::` tiers,
  so a `::` spelling passes and a `file:name` spelling refuses.
- `usesText` (line 2441). Line 2447 rebinds an `@` seed to its name (`atSeedNameOr`, line 2435); line 2449
  resolves `defs` by the whole spelling; **line 2462, `if( r.calleeName != sym )`, is the same comparison**,
  with no narrowing machinery at all. Lines 2517–2521 are its legend body.
- It is reached from `src/mcp.h` lines 1608–1616 (`tools/call`) and from the batch arm, `src/mcpverbs.h`
  lines 4646–4657, both through `usesSelectorRefusal` and then `usesText`.

**The documentation that describes the contract** — `src/cli.h` lines 1027–1031 (the `--uses` help);
`docs/COMMANDS.md` is **generated** from `--help` by `docs/docs_commands_build.py` and gated by
`test/docscommandscheck.sh`.

---

## STEP 3 — the gate is already written; you flip it

`test/usesselectorcheck.sh`. It is an existing gate, so `test/regression.sh` and the published gate count do
not move. On a build of `f22081b0` it prints 57 PASS, 12 of them `KNOWN GAP`.

- **Arm (d), lines 132–143.** The canonical id `src/notes.h::NoteIndex::empty` on this repository. It used to
  call its `count="0"` "documented, unchanged behaviour". It is now labelled a KNOWN GAP.
- **Section (f), lines 157–332**, on `test/declinefix` and `test/rustqualfix`. The header comment lists every
  literal site it reads.
  - lines 192–217: a table of seven `::` selectors (the `ctwin` canonical id, `One::ctwin`, `Solo::conly`,
    `ns::pick`, `One::pytwin`, `util::tool`, `Widget::new`). Each row has a premise (`--callers` counts N), a
    control (the bare `--uses` lists the site) and a KNOWN GAP (the `::` `--uses` is the silent zero);
  - lines 219–233: the callers answer's own `next=`, run verbatim (KNOWN GAP);
  - lines 235–239: the `file:name` spelling of the same definition already lands (control);
  - lines 241–250: `--safe-delete` `uses=` (KNOWN GAP and control);
  - lines 252–261: `--verify="uses(…)"` (KNOWN GAP and control);
  - lines 263–283: MCP `uses` over JSON-RPC (KNOWN GAP and control);
  - lines 285–306: **precision controls**. `Alpha::find`'s only same-named call is an external `find( 3 )`,
    and `Widget::new`'s bare name also covers `Vec::<u32>::new()` at `src/lib.rs:91`, which binds nothing.
    Neither may ever be a row;
  - lines 308–317: **negative controls**, `Widget::run` and `Gadget::spin`, which nothing calls: `count="0"`
    before and after;
  - lines 319–322: a wrong scope still refuses; lines 324–332: determinism and `xmllint`.

Every KNOWN GAP arm has a `FIXED:` comment beside it. **Flipping** means rewriting that arm's condition to its
FIXED line, and turning its message from "KNOWN GAP" into a plain assertion. Never delete an arm. Premise and
control arms stay exactly as they are: a fix that turns one red is wrong.

Two extra assertions belong in the flipped arms, because they are what make the fix *right* and not merely
non-zero:

1. **Same definition, same rows.** A `::` selector and a `file:name` selector that resolve to the same
   definitions list identical rows: `--uses=cpp/pair/one.cpp::One::ctwin` against `--uses=cpp/pair/one.cpp:ctwin`,
   and arm (d)'s canonical id against `--uses=src/notes.h:empty` (`--callers` counts 816 for both spellings).
2. **The two verbs agree.** Every `role="call"` row the `::` answer lists sits inside a symbol its own
   `--callers` answer lists (`test/declinecheck.sh`'s `call_sites` helper, line 103, already reads that relation).

**Red first.** Build `main` in a second worktree and keep that binary. Every arm you flip must FAIL against it
and PASS against yours:

```bash
git worktree add ../rw-base origin/main
cmake -S ../rw-base -B ../rw-base/build && cmake --build ../rw-base/build -j
bash test/usesselectorcheck.sh ../rw-base/build/ripwire     # the flipped arms FAIL; every control still PASSes
```

The precision controls are there to catch the obvious wrong fix: strip the scope, then name-match the bare
half. You can watch them catch it without writing C++. Put a wrapper outside the checkout, so it never enters
the crawl:

```bash
mkdir -p ../rw-naive && cat > ../rw-naive/ripwire <<EOF
#!/usr/bin/env bash
args=(); for a in "\$@"; do case "\$a" in --uses=*::*) args+=( "--uses=\${a##*::}" ) ;; *) args+=( "\$a" ) ;; esac; done
exec "$PWD/../rw-base/build/ripwire" "\${args[@]}"
EOF
chmod +x ../rw-naive/ripwire && bash test/usesselectorcheck.sh ../rw-naive/ripwire
```

On `f22081b0` that wrapper turns 12 arms red: arm (d) and the eight `--uses`/`next=` KNOWN GAP arms read
MOVED, both precision controls go red, and so does the wrong-scope control. A correct fix flips the first nine
and leaves the last three green.

---

## STEP 4 — the fix: its shape, and the edges it must stay inside

**The shape.** In `resolveUsesSelector`, a `::` spelling whose `defs` came back non-empty is treated the way
the `@FILE:LINE` arm already treats a seed. Match sites by the resolved definitions' **name**, and narrow the
call role through `usesChosenCallers` exactly as a `file:name` selector does. The design is yours to write in
the plan; these are its edges.

- **Narrow, never strip.** Read, write, import and extends roles carry no resolution and stay name-matched, as
  they do for `file:name`. The call role narrows. The precision controls fail on a strip-and-match fix.
- **The function needs the definitions.** `resolveUsesSelector` takes `defsCount` today. It has three call
  sites (lines 519, 782, 1449), and all three already hold `defs`.
- **A wrong scope still refuses, with today's bytes.** `Nope::ctwin` resolves nothing. Set any narrowing flag
  only after you know `defs` is non-empty, or the refusal moves from lines 556–561 into
  `refuseUsesFileQualifier`. Section (f)'s control pins the `--uses` refusal, and
  `test/selectorscopecheck.sh` arm (h) pins the scope tier's own refusal on `--callees`. A flag named for what it means ("this answer is narrowed") is clearer than overloading
  `fileQualified`; name it in the plan.
- **Member fields are a different path.** `memberUsesArm` (line 524) serves an `Owner::field` spelling of a
  FIELD and reads `defs` and `sym`, never `sel`. `test/fieldusescheck.sh`, which runs `--uses=Tally::limit` at
  line 149, must stay green.
- **Disclose what narrowed.** A narrowed `::` answer carries the same `narrowed_roles=`, `defs_of_name=` and
  `call_sites_of_name=` a `file:name` answer does, so a narrowed zero shows how many same-named call sites it
  set aside. Arguing for different attributes is allowed; it is a vocabulary change and costs a legend clause.
- **The MCP twin: choose in the plan, and never leave the silent zero.** Option (a) serves the narrowed answer
  through the CLI's own derivation. `usesText` holds `ix.g`, but it needs the narrowing, the attributes and a
  legend body, and `test/mcpattrparitycheck.sh` and `test/mcpclidiffcheck.sh` compare the twins attribute by
  attribute. Option (b) refuses a resolving `::` spelling the way `file:name` is refused today, pointing at
  the bare name and the CLI form. That is one condition in `usesSelectorRefusal`, and the MCP legend already
  says qualified spellings refuse. Two emitters of one computation drifting apart is the defect class this
  repo gates hardest, so if you pick (a), share the code rather than copy it.
- **Keep the pointers true.** After the fix, `--callers`' `next="--uses=SELECTOR"` lands on bound `::` calls
  with no change to `src/nextverb.h`. Do not touch the pointer: the sibling kit owns it.
- **Stale comments move with the contract:** `src/verbs_navigate.h` lines 321–326 and 779–781, and the arm (d)
  comment in the gate.
- **House rules** (`CLAUDE.md`, `CONTRIBUTING.md` section 3): write the gate before the code; Allman braces and
  braces on every body; spaces inside parentheses; output through `rw::emitTo`; never `std::map` or
  `std::unordered_map`; a degrade path uses `DEGRADED_PATH_ALERT`, never `VERIFY( false )`.

---

## The honesty rules this fix lives under

- **A zero means "none found", never "none exists"** (`CLAUDE.md`, non-negotiable 3). After the fix, a `::`
  answer's `count="0"` must mean the narrowing found no call that resolves to that definition, and the
  answer must say it narrowed. Today's zero means neither.
- **Legends and counts agree.** Every attribute an answer emits is defined in its legend. No legend sentence
  describes a behaviour the answer does not have. The `--uses` legend and help say narrowing is "file:
  qualifier only"; after the fix that is false, so rewrite it to name the spellings that narrow.
  `test/legendcoveragecheck.sh` holds the first half; you hold the second.
- **The legend has a byte budget.** `test/graphlegendbudgetcheck.sh` measures the `--uses` legend at 3954 B
  against 3979 B (line 99): 25 B of headroom. Write the shortest honest sentence. If a new honesty fact truly
  does not fit, that file's RE-PINNED comments show the one accepted way to move the number, and the PR says why.
  No double hyphen anywhere in the legend: it lands inside an XML comment.
- **Counts stay floors.** `counts_floor="1"` still holds; narrowing never turns a floor into a total.
- **The CLI and MCP twins say the same thing**, or the MCP twin refuses with a retry. Never a third answer.
- **Determinism is a contract.** Same input, byte-identical output. The rows keep `collectUseSites`' existing
  sort, tier then path then line then role then enclosing id. Section (f) runs a `::` selector twice and `cmp`s.

---

## STEP 5 — acceptance: what "done" means

Done means all of this, on a build of your final commit, every command in the foreground with
`PYTHONDONTWRITEBYTECODE=1` exported:

- every KNOWN GAP arm in `test/usesselectorcheck.sh`, arm (d) and section (f), is flipped to its FIXED line
  plus the two assertions from STEP 3, and FAILS against `../rw-base`;
- every premise, control, precision and negative arm in that file is unchanged and green;
- the `--uses` legend, the MCP legend body you touched, the `--help` text and the stale comments say what the
  code now does, and `docs/COMMANDS.md` is regenerated from the new `--help`;
- the suite is green.

```bash
cmake -S . -B build && cmake --build build -j
bash test/usesselectorcheck.sh
bash test/selectorscopecheck.sh
bash test/fieldusescheck.sh
bash test/atcheck.sh
bash test/usescheck.sh
bash test/safedeletecheck.sh
bash test/verifycheck.sh
bash test/declinecheck.sh
bash test/graphlegendbudgetcheck.sh
bash test/legendcoveragecheck.sh
bash test/mcpattrparitycheck.sh
bash test/mcpclidiffcheck.sh
bash test/mcpmanifestcheck.sh
bash test/nextverbcheck.sh
bash test/printffmtparitycheck.sh
bash test/docscommandscheck.sh
python3 test/pargates.py . ./build/ripwire -j 6        # the full suite
./build/ripwire . --quality-delta --legend=compact     # only what the change made worse — zero regressions
./build/ripwire . --test-gate                          # then the tests to run and the untested blast radius
```

- At `f22081b0` no recorded output uses a `::` selector with `--uses`, `--safe-delete` or `--verify`:
  `docs/captures/`, `docs/COMMANDS.md`'s samples and `test/printf_parity.manifest` all use bare names. A change
  confined to `::` spellings should move none of their rows. The `--help` text is different. If
  `printffmtparitycheck` goes red, read which labels are red first, and re-pin with
  `UPDATE_GOLDEN=1 bash test/printffmtparitycheck.sh` only when you can explain every one.
- Regenerate the reference on a clean committed tree, then commit the regeneration on its own:
  `python3 docs/docs_commands_build.py`.

---

## TRAPS — each one has cost somebody a day here

**The MCP legend spells the row shape.** The MCP `uses` legend contains `<u role=call|macro|…` unquoted, so a
test that greps `<u ` for rows matches the legend. Rows always quote the attribute (`<u role="call" p="…"`),
and section (f)'s helpers match that.

**Narrowing is per enclosing symbol, not per call site.** `usesChosenCallers` keeps every call site inside a
symbol that has an edge to a chosen definition. On `test/rustqualfix`, `--uses=src/gadget/mod.rs:new`
(`Gadget::new`) already lists `src/gadget/mod.rs:47`, a `crate::Widget::new()` call, because the same
function also calls `Gadget::new()` on line 48. Your fixed `--uses=Widget::new` inherits that granularity and
will list line 48 too. It is the `file:name` rule's existing behaviour, not this issue: name it as a follow-up
and do not widen the change.

**The MCP tool list is 23 B from its ceiling.** `test/mcpmanifestcheck.sh` caps `tools/list` at 42,200 B, and a
build of `f22081b0` measures 42,177 B. Neither option in STEP 4 needs a tool description change, so do not
touch the descriptions in `src/mcp.h`. That gate moves its ceiling for a declared argument, never for prose.

**The sibling kit's fixture is yours too.** Both kits read `test/declinefix`. If
`prompts/help-wanted/next-uses-bare-name.md` has landed when you rebase, run `test/declinecheck.sh` as well.
Its declined `::` spellings (`Alpha::crender`, `cpp/alpha/alpha.cpp::Alpha::crender`) will start carrying the
`file:name` disclosure your change adds. Read any red row before touching either change.

**`__pycache__` moves the crawl.** Python gates that import from the checkout write `__pycache__/` into it.
The name is gitignored, so `git status` stays clean, but the crawl counts the directory and a live-tree answer
can differ between two runs. Export `PYTHONDONTWRITEBYTECODE=1` for anything you run by hand.

**A clean rebase can still be wrong.** git merges text; the invariants here are about populations. If `main`
moves under you, everything generated, pinned or recorded (`test/printf_parity.manifest`, the captures,
`docs/COMMANDS.md`, the published gate count) is re-derived after the rebase by rebuilding and rerunning its
generator, never by picking a side of a conflict.

**A build that saw the tree move.** Never edit while a build runs, and never background a build you then edit
around. After a rebase or a branch switch, rebuild with `cmake --build build --clean-first -j`
(`CLAUDE.md`, "Build").

---

## STEP 6 — what the PR description contains

- **Before and after** for the STEP 1 commands, root tags and rows, and an "after" column for both STEP 1 tables.
- **What changed:** `--uses` in XML and columnar, `--safe-delete`, `--verify`, the MCP twin (which option, and
  why), the `--uses` legend and help, and the regenerated `docs/COMMANDS.md`. **What deliberately did not:**
  the pointer (`next=`), every "Not this issue" row, and the per-enclosing-symbol granularity.
- **Red-first evidence:** the flipped arms' FAIL rows against `../rw-base`, the `../rw-naive` result, and the
  PASS count after.
- **Byte-identity evidence** where nothing may move: `cmp` of pre- and post-fix output for `--uses=ctwin`,
  `--uses=cpp/pair/one.cpp:ctwin`, `--uses=src/notes.h:empty`, and the stderr of `--uses=Nope::ctwin`.
- **The legend's bytes** before and after, from `test/graphlegendbudgetcheck.sh` arm (a).
- **Every STEP 5 gate with its result**, and the `--quality-delta` and `--test-gate` summaries.
- **Follow-ups found and not fixed:** at least the per-site narrowing granularity, and any "Not this issue"
  row you confirmed.
- Links to this prompt and to the sibling kit.

---

**Write the plan — the condition and where it lives, what you do with the three call sites, the MCP option and
its cost, the legend sentence with its byte count, which arms you flip and their red run, and the gates you will
run — then STOP for my go-ahead.**
