# Unchanged tree, zero delta: `--quality-delta` must not gate a tree identical to HEAD

> **Solved (2026-11-26), except sparse checkout.** A tree identical to HEAD is now compared with itself
> (`head_basis="identity"`), so untracked content, a shallow clone, `export-ignore`, `TMPDIR` under `fixtures/` and
> one-sided `--no-ignore`/`--ignore-tests` report `gating="0"`; any `skip-worktree` or `assume-unchanged` path refuses
> that basis and says so (`head_basis="archived-index-hidden"`). That landed in [#304](https://github.com/redhat-et/ripwire/pull/304)
> (train 12, "#228 part 1", a maintainer lane); the Django and unittest hook half landed in
> [#437](https://github.com/redhat-et/ripwire/pull/437) by @llvm-x86, closing [#228](https://github.com/redhat-et/ripwire/issues/228), after the dispatch half in
> [#237](https://github.com/redhat-et/ripwire/pull/237) by @qinghuanandejiangshi. Slice 1's invariant gate is the (U) block in
> `test/qualitycheck.sh`. This kit stays as a worked example; the remainder is slice 2's sparse-checkout row: a
> sparse checkout takes the archived comparison, which is not sparse-aware and gates on a phantom, pinned as the (U4)
> KNOWN GAP at `test/qualitycheck.sh:831`, with no open issue tracking it. Submodules have no gate arm yet (an
> unchanged tree with one reported zero when checked by hand), and the stretch below was not re-checked.

`ripwire . --quality-delta` compares the working tree with a snapshot of `git HEAD` and exits 2 when
something got worse. On a tree that is identical to HEAD, the only correct answer is `regressions="0"`
and exit 0, for every kind, every time.

Today that answer depends on things that have nothing to do with the code:

- **how you spelled the root** (`.` versus an absolute path). The maintainers are fixing this part;
  see "Scope" below;
- **where your temp directory lives**;
- **how the checkout was made**: export attributes, submodules, sparse checkout, skip-worktree;
- **which crawl flags you passed**;
- **whether untracked files sit in the tree**, which is a policy question.

You are pinning the invariant with a gate across checkout shapes, then deciding, class by class, what the
tool fixes and what it discloses. Anything the tool cannot make equal, it discloses.

Work in a git worktree, not the main checkout, and run gates in the foreground.

---

## Scope: what is fixed, what the maintainers own, and what is yours

Issue [#228](https://github.com/redhat-et/ripwire/issues/228) (@hnipps) reported two stacked problems on a
Django monolith: 58 gating dead-code rows on a clean tree.

1. **The dispatch half is fixed.** PR #237 by @qinghuanandejiangshi landed it. Python methods reachable
   through `self.`/`cls.` calls on an indexed base class no longer count as dead, on both sides of the delta
   (`pythonDispatchedMethodIds` in `src/quality.h`, gated by an arm in `test/qualitycheck.sh`). Do not redo
   it.
2. **The root-spelling cause is maintainer-owned.** `resolvePythonImport`, and any related resolver whose
   answer depends on whether the root was typed as `.` or as an absolute path, is being fixed in a separate
   maintainer pull request that says "Refs #228" (branch `lane/root-spelling-invariance`). The
   [maintainer comment on #228](https://github.com/redhat-et/ripwire/issues/228#issuecomment-5700411686)
   explains why: it moves the whole call graph, for every command. **Do not change resolution in this
   work.** Check #228's linked pull requests before you start, and rebase onto that PR once it lands.
3. **The rest is this prompt, and it is open for the community:**
   - the **invariant gate** across checkout shapes: `TMPDIR` under a `fixtures/` directory,
     `export-ignore`, submodules, sparse checkout, skip-worktree, and `--no-ignore`/`--ignore-tests`
     reaching one side only;
   - the **per-class decision** for each shape the gate exposes: make both sides see the same population,
     or disclose the difference; untracked files are a policy question for the maintainers;
   - a **stretch**, separate PR: import-aware base-class matching for #237's rule.

This prompt reproduces the remaining half, with and without #237, and names the mechanisms. It does
**not** claim they explain the reporter's private repository. Their tree also had untracked directories,
and that is one of the shapes below.

---

## Why this matters

**The exit code is the product.** People wire `--quality-delta` into pre-commit hooks and agent "before I
push" loops. When a no-op diff exits 2, users learn to ignore the gate or to ack their way past it, and
#228's reporter did the second: "acking 58 findings to make a clean tree pass is a ratchet built on a false
floor."

**It also blocks the escape hatch.** On a clean shallow clone of Django, `--quality-baseline` refuses to pin
a sidecar. It reports that the tree "already holds 23 gating finding(s) against HEAD". The workaround the
tool recommends is therefore unavailable in exactly the repositories that need it.

**This project has fixed this shape before, one class at a time.**

- `test/qualityexcludecheck.sh`: `--exclude` reached one side of the delta and not the other.
- `test/bashsourcecheck.sh` arm 6: Bash `source` resolution worked under `.` and was half inert under an
  absolute root.
- `test/qualitystalecheck.sh`'s header: the CLI and the MCP `quality_delta` verb disagreed about the same
  tree (31 phantom rows against zero).

Each fix closed one instance. Nothing pins the invariant itself, so the next instance ships green. The gate
is the durable part of this work.

---

## Background: read these before you plan

### How the two sides are built

| | working tree (bare `--quality-delta`) | HEAD floor | ref pair (`--quality-delta=A..B`) |
| --- | --- | --- | --- |
| entry | `ingest()` in `src/main.cpp`, then `resolveDeltaBasis` (`src/verbs_quality.h`) | `computeHeadSnapshot` → `materializeCommitTree` (`src/quality.h`): `git archive` into a temp dir | `loadRefPairDelta` → `loadRefTree`: both trees archived |
| root spelling | **as typed** (`.`, `./`, absolute, `../x`) | **absolute**, `<cacheDirLadder()>/ripwire-qhead-<pid>` | absolute temp dirs, both sides |
| crawl | git ignore probe (`collectGitIgnored`), unless `--no-ignore` | the temp dir is normally not under a git root, so a full walk of the archived files | same as HEAD |
| value uses | lean (`needsValueUses( cfg )` is false for the bare verb) | rich (the `ingest()` default) | rich |
| `--ignore-tests` | applied (`applyIgnoreTests`) | not applied | not applied |
| caches | per-root parse cache; `--no-cache` honoured | `qheadsnap` ingest blob plus `qsnap` Snapshot blob, keyed on (realpath root, HEAD sha, excludes, max file size, scheme); **`--no-cache` is not honoured** (the `cacheNever` parameter is `(void)`, and the CLI passes `nullptr`) | a HEAD endpoint reuses `qheadsnap` |

Then:

- `computeSnapshot` builds the per-symbol maps and the dead set on each side.
- `isDeadCandidate` is the dead-set predicate: no in-edge, plus the exemptions.
- `computeDelta` compares the two sides key by key.
- `healIdentity` runs **only** when an ack ledger exists or `--quality-ack` is passed. It re-keys the HEAD
  snapshot through git's rename record before the delta.

### Where a path above the repository decides a verdict

- **`ing.files` carries the root exactly as it was typed.** `ripwire .` stores `pkg/mod.py`;
  `ripwire /abs/repo` stores `/abs/repo/pkg/mod.py`. On the HEAD side the prefix is your cache or temp
  directory.
- **`isFixturePath`** (`src/quality.h`) walks every component of `ing.files[ fileId ]`. A component named
  `fixture`/`fixtures`, or one ending in `fix` directly under `test`/`tests`, exempts the file from the
  dead-code and duplication kinds. **`isTestScriptPath`** calls `isTestPath` (`src/filter.h`). When the
  path includes the root prefix, directories **above** the repository decide these predicates.
- **Find every other loop over path components of `ing.files`** that can reach a verdict, and classify each
  one in your plan. Leave resolvers (`src/resolve.h`) to the maintainer PR.

### The root-spelling mechanism (maintainer-owned; know it so your gate is not fooled by it)

`resolvePythonImport` probes a module path relative to the importing file, then relative to the repo root
by calling `joinNormalizeLookup` with an **empty base**. That empty base is the crawl root only when the
root was typed as `.`. Under an absolute root the second probe matches nothing, and the name ladder in
`buildGraph` decides instead. The HEAD side always runs under an absolute root, so a Python absolute import
can bind differently on the two sides of an unchanged tree. Until the maintainer PR lands, **any fixture
with a Python absolute import can produce rows from spelling alone**, which would contaminate an arm about
a different shape.

### Gates to read

- **The delta itself:** `test/qualitycheck.sh` (#237's arm is the most recent),
  `test/qualityexcludecheck.sh` (the one-sided-flag precedent), `test/qualitystalecheck.sh`,
  `test/qualitykeycheck.sh`, `test/qualityorigincheck.sh`.
- **HEAD caches:** `test/headsnapcachecheck.sh`, `test/qsnapcachecheck.sh`,
  `test/qsnapprefetchcheck.sh`, `test/qschemetripcheck.sh` (a source-text tripwire over the snapshot
  functions), `test/qextractionkeycheck.sh`.
- **The KNOWN GAP pattern:** `test/usesselectorcheck.sh` and `test/fieldnarrowcheck.sh`.

---

## Reproduce the gap

### Root spelling (maintainer-owned; reproduce it once so you recognise it)

```bash
cmake -S . -B build && cmake --build build -j
RW="$PWD/build/ripwire"
d="$( mktemp -d )/spell" && mkdir -p "$d/pkg" "$d/app" && cd "$d"
: > pkg/__init__.py
printf 'def load(x):\n    return x\n'                                        > pkg/store.py
printf 'from pkg.store import load\n\n\ndef handler():\n    return load(1)\n' > app/views.py
printf 'def load(x):\n    return x * 2\n'                                     > app/local.py
git init -q . && git add -A && git -c user.name=fx -c user.email=fx -c core.hooksPath=/dev/null commit -qm init
git status --porcelain                                    # empty
"$RW" . --quality-delta --legend=compact;      echo " exit=$?"
"$RW" "$PWD" --quality-delta --legend=compact; echo " exit=$?"
```

Measured on a dev build of `main` at `30f14a27` (before #237) and on a dev build that contains #237:

- **`.`:** `regressions="1" preexisting-worse="1" gating="1"`, one row
  `<r kind="dead-code" sym="load" p="app/local.py:1" gating="1" …/>`, exit 2.
- **`"$PWD"`:** `regressions="0"`, exit 0.

On a clean `git clone --depth 1` of Django (7,091 tracked files at `2b30f62`), `ripwire .` gave 23 gating
dead-code rows before #237 and 14 with it, while `ripwire "$PWD"` gave 0 on both. That is the part the
maintainer PR fixes.

### Is it the cache or nondeterminism? Neither, so far

- **Every run was stable.** Cold, warm and `--no-cache` runs were byte-identical on the Django clone, and
  on each of the 20 checkout shapes we ran three ways (listed below).
- **The HEAD cache is ruled out on Django.** A fresh `TMPDIR` (no cache at all) reproduced the same rows,
  and the absolute-root run that read 0 was served the **same** cached HEAD Snapshot as the `.` run.
- **An empty commit is clean.** `--quality-delta=HEAD~1..HEAD` over an empty commit, with both sides
  archived and absolute, reports 0.

Keep this in mind while testing: `--no-cache` does not reach the HEAD caches. A cold HEAD side needs a
fresh `TMPDIR` or a new HEAD sha.

### The checkout shapes that are yours

We used a nine-file Python and C++ fixture with a `git status --porcelain` that is empty unless noted. The
fixture has symbols whose verdict depends on the file set: a function whose only definition is resolved
as a unique global, and a function with exactly one caller file.

| shape | `at=` | gating rows (before / with #237) |
| --- | --- | --- |
| `TMPDIR` inside a directory named `fixtures` | clean | 5 / 4 (one per symbol that is dead in both trees) |
| a tracked file marked `export-ignore` in `.gitattributes`; it defines a same-named function | clean | 1 / 1 |
| a checked-out submodule | clean | 3 / 3 (plus 9 / 8 new-symbol rows) |
| sparse checkout that hides a tracked caller | clean | 1 / 1 |
| `git update-index --skip-worktree` over an edited caller | clean | 1 / 1 |
| `--no-ignore` with a gitignored file that defines a same-named function | clean | 1 / 1 |
| `--ignore-tests`, with a helper called only from `tests/` | clean | 1 / 1 |
| an untracked file, or an untracked nested git repo, that defines a same-named function | `+dirty` | 1 / 1 |

These shapes held at zero on both builds: `.git/info/exclude`, `.gitignore`, `core.excludesFile`, a
tracked file that matches `.gitignore`, `export-subst`, `core.autocrlf=true`, `eol=crlf` attributes,
symlinks inside and escaping the tree, a subdirectory as root, a shallow clone, and a non-ASCII path.
This repository's own checkout (mostly C++) also read zero under `.` with its committed ack ledger, which
exercises `healIdentity`'s rename re-keying.

The `TMPDIR` row is not a resolver effect: `isFixturePath` sees the `fixtures` component of the HEAD side's
temp path and exempts every HEAD file, so symbols dead on both sides gate as new. The reverse is a silent
false zero: a repository checked out under `fixtures/` (or `test/<x>fix`) and run with an absolute root.

---

## Slices, each with a red-first gate

### Slice 1: the invariant gate (the best first PR; no `src/` change)

Pin "an unchanged tree reports zero" across the shapes above. Where current behaviour is wrong, use this
repository's KNOWN GAP pattern: an arm that passes today by asserting the documented wrong answer and says
"flipping this is the acceptance test". A later fix flips the arm in place.

**Arms worth having:**

1. **Temp-dir location.** Set `TMPDIR` explicitly in every arm, so the gate's own location never decides.
   Add one arm with `TMPDIR` under a `fixtures` directory (KNOWN GAP).
2. **git-clean population shapes.** `export-ignore`, a submodule (a local `file://` source, with
   `-c protocol.file.allow=always` on that one command), sparse checkout and skip-worktree. Record today's
   rows as KNOWN GAP until slice 2 decides each class.
3. **One-sided flags.** `--no-ignore` and `--ignore-tests` (KNOWN GAP).
4. **Untracked content.** An untracked file and an untracked nested repository, each defining a same-named
   function. Pin today's answer as a KNOWN GAP whose message says the policy is undecided; do not assert
   either outcome as correct.
5. **A sensitivity control per arm.** A real edit that deletes the only call to a uniquely named function
   must produce exactly one gating row in that same shape. Without it, a delta that reports nothing passes
   the arm.
6. **Shapes that must stay green.** Every zero listed under "The checkout shapes that are yours".
7. **Determinism per arm.** Compare cold (fresh `TMPDIR`), warm, and cold again, byte for byte.
8. **Every kind, not only dead-code.** Assert on the root attributes, with no `.ripwire_quality_acks` in
   any fixture. Add one arm **with** a ledger present, because `healIdentity` only runs then.
9. **CLI and MCP agree.** For each shape both can run, the MCP `quality_delta` verb (an absolute root) and
   the CLI give the same counts.

**Keep root spelling out of these arms.** Build the shape fixtures without Python absolute imports, or run
them under an absolute root, so the maintainer-owned bug cannot add a row to an arm about something else.
Do not add root-spelling arms of your own; the maintainer PR brings them. Once it lands, running each shape
arm under both `.` and an absolute root is a welcome follow-up.

**Register the gate in every place it must be listed:**

- `test/regression.sh` (`test/manifestcheck.sh` enforces it);
- `python3 docs/gatecount_build.py`;
- a weight in `.github/pargates-shard-weights.json` (nothing enforces it; add one anyway).

An arm inside `test/qualityexcludecheck.sh` or `test/qualitycheck.sh` is also acceptable. Say in your plan
which you chose and why.

### Slice 2: the same population on both sides (decide each class, then fix or disclose)

Each class needs a maintainer decision in the plan before code.

| class | what differs | directions to weigh |
| --- | --- | --- |
| `TMPDIR` under `fixtures/` (and a repository under `fixtures/`) | `isFixturePath`/`isTestPath` read components above the repository | the predicates see root-relative paths on both sides; a component above the root never decides a verdict. Do this through a root-relative view, not by editing `src/resolve.h`. If the maintainer PR already hands these predicates root-relative paths, this row shrinks to its arm |
| `export-ignore` / `export-subst` | `git archive` applies export attributes; the working tree does not | materialize without export attributes (a temporary index and `checkout-index` is one route; `git archive` has no switch for it). Check what each route runs: eol conversion, smudge filters, hooks. A materialization must never run a hook or reach the network |
| submodules | the crawl reads checked-out submodule trees; the archive holds gitlinks only | exclude gitlink paths on the working-tree side with a disclosed count, or materialize submodules at their recorded commits |
| sparse checkout, skip-worktree | `git status` is clean, but the trees differ | follow the index (judge what a commit would contain), or disclose the paths |
| `--no-ignore`, `--ignore-tests` | applied to one side only | thread them into `computeHeadSnapshot` **and into its cache key**, as `--exclude` was, or refuse the combination |
| untracked, not ignored | the working tree includes files HEAD cannot have | **policy, owner decision.** A new, not-yet-added file is exactly what the verb exists to judge, so do not drop it. Its same-named definitions can still flip a tracked symbol's verdict. Options: an absent-at-zero count of untracked indexed files on the root; or judge tracked symbols against HEAD plus the same untracked files. Cost each option |

A fix flips its KNOWN GAP arm, shown RED on the pre-change binary. A disclosure is a legend-defined
attribute, absent at zero, with a `--json` twin, and its arm asserts the attribute.

### Stretch, and separate: import-aware base-class matching for #237's rule

The #237 review (finding F1) noted that `pythonDispatchClasses` walks `g.implementors`, whose Python
inheritance edges resolve a base-class **name** to every same-named class in the root. A `cls.X()` in one
`BaseTestCase` can therefore keep alive `X` overrides under an unrelated `BaseTestCase`: false-live, the
conservative direction, but still wrong.

Narrow it with the import evidence `resolvePythonImport` already computes. **Start this only after the
maintainer root-spelling PR lands**, because that evidence changes with the spelling until then. The same
review noted the exemption is not counted in the output (compare `register-macro-excluded=`); whether to add
a count is an owner decision. Land this as its own PR, never folded into slices 1 or 2.

---

## Acceptance criteria

1. **Slice 1:** the gate is registered and green, with KNOWN GAP arms naming this prompt. Every arm has a
   sensitivity control that was observed producing its row, and no arm's rows come from root spelling.
2. **Slice 2:** each class is decided in the plan with the maintainers, then either fixed (its arm flipped,
   RED first) or disclosed (a legend-defined attribute, absent at zero, with a `--json` twin).
   - Any change to what the HEAD side computes for an unchanged sha bumps `kQSnapCacheScheme` (in
     `src/quality.h`) to the next free number, with a RE-PIN LOG entry and an **upgrade arm**: the
     pre-change binary writes the blob, and the changed binary must not serve it.
   - A flag threaded into `computeHeadSnapshot` is in its cache key, with an arm that flips the flag between
     two runs sharing one cache.
3. **CLI and MCP agree** on every arm they can both run.
4. **Nothing masked:** no fixture carries an ack, no path or framework is special-cased, and the exit code
   is asserted, not only the counts.
5. **Suite:**
   - `python3 test/pargates.py . ./build/ripwire -j 6` is green in the foreground, including
     `test/qschemetripcheck.sh`, `test/qextractionkeycheck.sh`, `test/qualityexcludecheck.sh`,
     `test/qualitystalecheck.sh` and `test/qsnapcachecheck.sh`.
   - `./build/ripwire . --quality-delta --legend=compact` on this repository shows zero unacknowledged
     regressions.
   - The two-run determinism diff is clean.

---

## Known traps

**Do not fix resolution here.** Resolving the working-tree root to an absolute path before ingest makes
every spelling row disappear, and it also switches off Python absolute-import precision for every
`ripwire .` user, in every verb. Root spelling is the maintainer PR's job; this work must not touch
`src/resolve.h`.

**A cached HEAD Snapshot outlives your fix.** Without a scheme bump, a changed binary keeps reading the
pre-change HEAD Snapshot for an unchanged sha. Your fix then looks broken on the second run, or the old
answer looks fixed on the first. `--no-cache` will not help you tell which: use a fresh `TMPDIR`. Whether
`--no-cache` should reach the HEAD caches is a separate owner decision; ask before changing it.

**The gate's own location can decide the answer.**
- A fixture under `test/<name>fix` run with an absolute root puts every file under a `fix` component
  directly below `test`. That exempts every file from dead-code and duplication, so the zero is vacuous.
- A `TMPDIR` under a `fixtures` directory exempts the HEAD side instead, and rows appear.
- Generate fixtures under `mktemp -d` with neutral names, and set `TMPDIR` explicitly.

**Empty equals agreement** (CONTRIBUTING.md §2, shape 3). A zero from a fixture whose verdicts cannot
move proves nothing. Give every arm a symbol whose verdict flips under the divergence it tests, assert the
symbol is present, and keep the real-edit control.

**Do not mask it with acks.** `--quality-ack` is the workaround this work retires. Fixtures carry no
ledger unless an arm is about the ledger. An ack that hides a phantom row is a false floor.

**Do not special-case Django, Python tests, or `tests/`.** The four-file repository has no tests, no classes
and no framework, and the shape fixtures need none either.

**A crashed run prints nothing.** "No rows" is also true of an empty document. Assert exit 0 and the
presence of the root element before any count.

**`computeHeadSnapshot` has four callers:** the CLI delta, the MCP `quality_delta` verb, `--edit-check`
and the MCP prefetch worker. `--quality-baseline`'s absorb refusal reads the same comparison. Keep them on
one path; a per-caller patch is how the CLI and MCP drifted apart before.

**Shared products wake gates.** Editing `src/quality.h` wakes `test/qschemetripcheck.sh` and
`test/qextractionkeycheck.sh`. Editing any gate file wakes `test/gateexitcheck.sh` and
`test/manifestcheck.sh`. If Python runs inside the checkout, set `PYTHONDONTWRITEBYTECODE=1`, or
`__pycache__` moves the crawl counts under the next gate.

**Git inside fixtures.**
- Pass identity on the command line (`-c user.name=fx -c user.email=fx`); git does not need a real address.
- Add `-c core.hooksPath=/dev/null`.
- Never let a fixture command touch the network.
- On macOS `/tmp` is a symlink to `/private/tmp`, so the repo key uses the realpath. Two spellings of one
  directory share caches.

**Build discipline.** Use the plain dev build, never edit while a build runs, and run
`cmake --build build --clean-first -j` after switching branches or rebasing onto the maintainer PR.

---

## Related

- **#237** (merged, @qinghuanandejiangshi): the dispatch half of #228. This prompt builds on its rule
  and must not undo it.
- **The maintainer root-spelling PR** ("Refs #228"): owns `resolvePythonImport` and related resolvers.
  Rebase onto it when it lands; your gate's shape arms should then run under both spellings.
- **#229 and PR #236:** the same reporter's Django `--situ`/`--affected` `run=` hints. Same user shape,
  with no code overlap (`src/testmap.h`).
- **#149, correctness fuzzers:**
  - Its input-order oracle and its cache round-trip oracle are cousins of this invariant. This one asks
    that the answer not depend on how the tree is materialized.
  - It stands alone: it has a user report, reproductions and contained fixes.
  - Once it lands, its fixture shapes could seed a further #149 oracle.
- **PR #241, cache enum validation (in review):** validates enum bytes in the ingest-cache readers that the
  HEAD ingest cache also uses. `qsnap` blobs carry no enum fields. It is not implicated in any reproduction
  above; rebase onto it if slice 2 changes what the materialized tree caches.
- **Precedents:** `test/qualityexcludecheck.sh` (a flag reaching one side), `test/qualitystalecheck.sh`
  (CLI and MCP disagreeing), `test/bashsourcecheck.sh` arm 6 (root spelling).

---

## Size

**Medium.**

- **Slice 1** is a good first contribution: one gate, no `src/` change, and the shapes above to start
  from.
- **Slice 2** is one decision and one small change per class. `export-ignore` and submodules touch how
  the HEAD tree is materialized, which needs care with git's side effects; the flags follow the
  `--exclude` precedent.
- **The stretch slice** is independent, optional, and waits for the maintainer PR.

---

## What the PR description should contain

- **The shape table** (`TMPDIR` location, checkout shapes, flags, untracked content): rows and exit code
  before and after, for each shape the PR touches.
- **The red runs:** each flipped KNOWN GAP arm failing on the pre-change binary, and each sensitivity
  control producing its row.
- **Every path-component walk you found**, and what you did with each.
- **Any scheme bump:** the old and new value, the RE-PIN LOG entry, and the upgrade arm's red and green.
- **The per-class decisions from slice 2**, with the attribute and legend text of any disclosure, verbatim.
- **What the invariant does not cover:** root spelling (the maintainer PR), a ref pair across a real change
  (name-based resolution is non-local by design), non-git roots, and multi-root runs.

---

**Write the plan: the slice you take first; the gate's arms with their sensitivity controls and the lines
you expect to be RED; how you keep root spelling out of the arms; the classes you propose to fix and the
ones you propose to disclose, with the owner decisions you need (untracked files among them); any
cache-scheme bump and its upgrade arm; and how you will show that the CLI and MCP agree. Post it on #228,
then STOP for a maintainer's go-ahead.**
