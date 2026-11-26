### Added — `--brief="TASK"`: one page to paste into a fresh code-editing subagent

`ripwire <dir> --brief="TASK"` prints a size-capped brief for a subagent that will edit code for TASK. The cap follows the repo's size class: 2.5 KB under 1K indexed files, 4 KB under 10K, 6 KB above that. `--brief-bytes=N` (512..8192) overrides it. The page has eight sections, in this order:

1. layout: top dirs with their role. Vendored and generated dirs are marked `(skip)`, including ones the index leaves out (`third_party/`, `node_modules/`, an untracked `build/`).
2. build: build and test commands quoted from the docs' fenced blocks (`AGENTS.md:31 make test …`) and from manifests (CMake, autotools, Make targets, package.json scripts, go.mod, Cargo, tox, Bazel, meson…). Each command names the file it came from. Nothing is run and nothing is guessed. A tree with no manifest says `none found`. The section also names where a new test is registered and what runs the tests.
3. entry: program entry points ranked by call/import reach from the task.
4. task: `--for`'s act ranges (up to 8) and its question sites.
5. edges: callers and callees of the task's symbols, the primary file's imports, and the files that import it (where a model file is registered or loaded).
6. where-else: co-change partners when there is history, then tests, docs and the changelog.
7. conventions: H2 headings of the contributing docs, with line numbers.
8. next: the three-moment ripwire block that `ripwire wrap claude` prints.

When the page is over budget it drops, in order: conventions, layout depth, entries past 3, edges past one symbol, where-else past 3, then question sites. Act and build never drop. The root names what went (`dropped=`), and `over="1"` says the fixed sections alone outgrew the cap. Root attributes: `size_class`, `budget`, `bytes`, `confidence`, `build_source` (`none|manifest|docs+manifest`), `history` (`0` on a shallow clone).

`--brief` is opt-in. `--for` output is byte-identical to before. The MCP server adds a `brief` tool (`task`, optional `bytes`; single-root) that serves the same composer. The tool catalog goes from 33 to 34 tools, and `brief` is in the `no-edit` profile that `ripwire wrap claude` registers. New gate: `test/briefcheck.sh`.

#### The unit's build file and co-change roles

The brief now learns a unit's registration, test home, build file and docs from the repo itself instead of from file-name patterns. The unit is the thing the task imitates (its `like X` exemplar), or else the first named or act file.

- **Build file.** `<build>` names the unit's own build file (`unit build: src/Functions/CMakeLists.txt`). This is the nearest manifest above the unit and above its tests: BUILD.bazel, CMakeLists.txt, Cargo.toml, Makefile(.am), package.json, meson.build, pom.xml, build.gradle and similar. It carries the line that names the unit's file when one does. The root's manifests stay on their own lines.
- **Co-change.** With git history, `<edges>` and `<where-else>` list the files that changed together with the unit's siblings (same dir, same extension; the next dir up when the dir has little history). Each file is sorted into a role:
  - test files and test corpus dirs;
  - build files;
  - docs and changelog;
  - registration: a source file outside the siblings that several of them change with, listed first under `<r>registration:`.

  A partner must change with at least 2 siblings, in at least 2 commits, and at least twice as often as an average commit does, so a lockfile or a root manifest that every commit touches is never a role.

  Commits wider than the repo's 90th-percentile commit (clamped to 12..50 files) are dropped: these are formatter passes and mass moves. The history is the 18-month walk `--for` already reads and caches: a warm call walks nothing and adds two small git calls.

`history="1"` now means that walk holds at least 10 commits after the wide ones are dropped. A clone deepened past the window counts, even though it is still marked shallow. A 1-commit clone stays at `history="0"`.

Off switches: `RIPWIRE_BRIEF_COCHANGE=0` drops the history roles and `RIPWIRE_BRIEF_UNITBUILD=0` drops the build-file line. Each leaves the rest of the brief as it was. New gate arm: `test/briefcheck.sh (H)`.

#### Opt-in, with the measured limits

`--brief` is an opt-in verb; `--for` stays the default route. Held-out check (8 repos; axum, django, fmt, gin, nest, pydantic, textual, trpc): `--brief` 64 items in 25,483 B, `--for` 58 items in 121,072 B. By class (E/S/T/B items, `--brief` vs `--for`): 9/24 vs 13/24, 24/32 vs 23/32, 12/24 vs 6/24, 19/32 vs 16/32. By language: Python 23 vs 16, TypeScript 17 vs 10, Go 10 vs 11, C++ 9 vs 12, Rust 5 vs 9. Entry points are the limit: `--for` finds more (13 vs 9). Only 1 of 8 repos met every per-class bar. The help (`--help=--brief`), `docs/COMMANDS.md` and `docs/LIMITS.md` state this.
