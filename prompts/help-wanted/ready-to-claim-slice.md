# Take a ready-to-claim issue — one slice, red first, every other answer byte-identical

You are taking one **ready-to-claim** issue on `redhat-et/ripwire`: an issue labelled `help wanted` whose
body already names the problem in user terms, the files to touch, a red-first fixture and an acceptance
list. Most of them are one row and letter of the feature-family map in `CONTRIBUTING.md` (§3, "Adding a
language: common stays common"), such as "2b, Kotlin" or "6d". This kit is the workflow around such an
issue: claim it, reproduce it red, make the smallest change that turns it green, and prove that nothing
else moved.

The issue is the specification. This kit does not repeat it, and where the two disagree the issue wins.
If the issue is wrong about the code on today's `main`, say so on the issue before you code around it.

Work in a git worktree, not the main checkout, and run every gate in the foreground.

---

## Which issues this covers

Open, unclaimed issues of this shape on 2026-11-26. Check each one's comments before you start; a comment
saying "I'd like to take this" is a claim.

| Issue | Slice | Language | Size the issue states |
| --- | --- | --- | --- |
| [#487](https://github.com/redhat-et/ripwire/issues/487) | 2b: `import a.f as g` reaches the call resolver | Kotlin | S |
| [#488](https://github.com/redhat-et/ripwire/issues/488) | 2b: `using R = Lib.Real;` reaches the call resolver | C# | S |
| [#552](https://github.com/redhat-et/ripwire/issues/552) | 2b: `use A\B as C;` reaches the call resolver | PHP | S |
| [#550](https://github.com/redhat-et/ripwire/issues/550) | 1: `import y = require("./y")` draws the file edge | TypeScript | S |
| [#551](https://github.com/redhat-et/ripwire/issues/551) | 1a: Dart `import` draws file edges | Dart | S–M |
| [#490](https://github.com/redhat-et/ripwire/issues/490) | 6d: the remaining per-`Lang` predicates become `kLangFacts` columns | all | S per PR, two PRs |
| [#489](https://github.com/redhat-et/ripwire/issues/489) | 4d: Rust `impl Trait for Type` read through `tags.scm` | Rust | M |
| [#546](https://github.com/redhat-et/ripwire/issues/546) | 12a: `emit("x")` joins `on("x", fn)` as a hedged hop | TS/JS | S–M |
| [#547](https://github.com/redhat-et/ripwire/issues/547) | 12a: a send on a struct-field channel joins its receiver | Go | M |
| [#543](https://github.com/redhat-et/ripwire/issues/543) | `--layout` sizes standard-library members | C++ | M |
| [#544](https://github.com/redhat-et/ripwire/issues/544) | `--lint --with-profile` reads `sample` / `perf script` trees | any | M |
| [#672](https://github.com/redhat-et/ripwire/issues/672) | `conf=` on `prov="split"` arms | all | not stated |
| [#726](https://github.com/redhat-et/ripwire/issues/726) | `mem=` names a class's direct fields | all | not stated |

Refresh the list before you pick: `gh issue list -R redhat-et/ripwire --label "help wanted" --state open`.
An issue with an assignee, or a claim in its comments, is taken. Offer help on its thread instead.

---

## Step 1 — claim it

Comment on the issue: which slice you are taking, the one-paragraph plan, and what you expect to be red on
`main`. Wait for a maintainer to agree before you write code. That takes minutes to a day, and it is the
cheapest review the change will ever get. One slice per pull request.

---

## Step 2 — orient with ripwire before you open files

Build plain, with no build type (`cmake -S . -B build && cmake --build build -j`), then:

```bash
./build/ripwire . --pack-task="<the issue's title, verbatim>"     # ranked symbols, top bodies, callers, tests to run
./build/ripwire . --recall="<the slice, e.g. 2b import renames>"   # the plans and CONTRIBUTING rows that say why
./build/ripwire . --expand=<each function the issue names>          # its body and its callees' signatures
```

Paste the file and function names from the issue into `--pack-task` as they are written; the ranker lifts
literal mentions. Before you write any new helper or gate, run `./build/ripwire . --exemplar="<what you are
writing>"` and imitate what it returns, and `--grep=<concept>` to catch the twin that already exists. A
`tags.scm` change starts from the node shape: `./build/ripwire <fixture> --match='(<node> ...)'` on the
issue's fixture shows what the grammar really calls it. Verify the name rather than guessing it.

---

## Step 3 — red first

1. Put the issue's fixture under `test/<name>fix/`, or add an arm to the gate the issue names.
2. Run the issue's reproduction against a build of `main` and keep the output: it must show the wrong
   answer the issue describes. If it already shows the right answer, stop and say so on the issue.
3. Write the gate arm that asserts the right answer, and watch it fail on `main`. A new
   `test/<name>check.sh` is listed in `test/regression.sh` in the same commit, or `test/manifestcheck.sh`
   fails.
4. Add the near misses the issue lists as arms that must **not** move: the forms that already work, the
   unrelated same-named symbol, and the out-of-tree name that must stay unresolved rather than guessed.
   An arm that passes on unfixed code proves nothing (`CONTRIBUTING.md` §2, "an arm that cannot fail").

---

## Step 4 — the change

Make it in shared code, driven by data. A `tags.scm` capture in the shared vocabulary or a table row beats a
new `Lang::X` comparison in a shared file, and a reviewer looks for that comparison first. When extraction
output moves, bump `kParserVer` and its mirror to any number above `main`'s; a maintainer sets the final
number at merge. Delete the per-language function the slice replaces. Do not leave it beside the shared
path.

---

## Done means

All of `CONTRIBUTING.md`'s "Definition of done for a common-code slice", and concretely:

- [ ] The new arm is red on `main` and green on your branch, and both runs are in the PR description.
- [ ] `bash test/langidentitycheck.sh origin/main HEAD --langs=<touched,plus one you did not touch>
      --repo=<LANG>:<a real repository>` prints SAME for every untouched language, and every DIFF is
      waived by one `--intended` row naming the arm that pins it.
- [ ] The family's gates pass, run as `bash test/<gate>.sh "$PWD/build/ripwire"`. `CONTRIBUTING.md`
      names them per family: imports `importcapcheck`, `depsprecisecheck`, `resolvecheck`,
      `nestedimportcheck`; qualified calls `stdqualcheck`, `rustqualcheck`, `resolverhonestycheck`; and so on.
- [ ] `./build/ripwire . --quality-delta=origin/main..HEAD --legend=compact` gates 0 on the committed
      branch, then `./build/ripwire . --test-gate` names the tests you ran.
- [ ] A wrong answer the slice does not fix is pinned as a known-gap arm that names the slice that will flip
      it (`test/fieldnarrowcheck.sh` shows the form), not left silent.
- [ ] One `changelog.d/<PR>-<slug>.md` fragment (`changelog.d/README.md` gives the format).

CI runs the full suite on the pull request. Locally, run the gates above plus the selection sweep in
`CONTRIBUTING.md` §1, "Selecting which gates to run".

---

## Known traps

1. **A Release build blinds the degrade gates.** `-DCMAKE_BUILD_TYPE=Release` defines `NDEBUG`. Build plain.
2. **Never edit the tree while a build runs**, and rebuild `--clean-first` after a branch switch. A
   mixed-layout binary produces real sanitizer reports of fake bugs (`CLAUDE.md`, "Build").
3. **A language that shares a dialect.** Kotlin shares `DepDialect::Java`, and TypeScript shares the Web
   arm with JavaScript. An arm for one must fire only for what that language's query captures.
4. **The cache hides your change.** Run reproductions with `--no-cache`, or a fresh `--cache=DIR` for each
   binary.
5. **A count of zero is not proof of absence.** ripwire's own output says so (`counts_floor="1"`). When a
   reproduction prints `count="0"`, check that the fixture actually reached the code path, for example with
   `--skipped`.

---

## What the PR description should contain

- `Closes #N`, and the slice's row and letter.
- The red run on `main` and the green run on the branch, as command plus output.
- The `langidentitycheck` lines, with each DIFF and the `--intended` row that waives it.
- The deleted duplicate, or why there was none.
- What the change still does not handle, and the known-gap arm that pins it.

Contributors are credited by handle in the changelog entry and in the release notes.

---

**Write the plan — the issue you claimed, the red reproduction you expect, the files you will touch, the
gate arms and near misses, and the byte-identity run — then STOP for my go-ahead.**
