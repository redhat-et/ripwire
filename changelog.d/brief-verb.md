### Added — `--brief="TASK"`: one page to paste into a fresh code-editing subagent

`ripwire <dir> --brief="TASK"` prints a size-capped brief for a subagent that will edit code for TASK. The cap follows the repo's size class: 3.5 KB under 1K indexed files, 5 KB under 10K, 7 KB above that. `--brief-bytes=N` (512..8192) overrides it. The page has eight sections, in this order:

1. layout: top dirs with their role. Vendored and generated dirs are marked `(skip)`, including ones the index leaves out (`third_party/`, `node_modules/`, an untracked `build/`).
2. build: build and test commands quoted from the docs' fenced blocks (`AGENTS.md:31 make test …`) and from manifests (CMake, autotools, Make targets, package.json scripts, go.mod, Cargo, tox, Bazel, meson…). Each command names the file it came from. Nothing is run and nothing is guessed. A tree with no manifest says `none found`. The section also names where a new test is registered and what runs the tests.
3. entry: program entry points ranked by call/import reach from the task.
4. task: `--for`'s act ranges (up to 8) and its question sites.
5. edges: callers and callees of the task's symbols, the primary file's imports, and the files that import it (where a model file is registered or loaded).
6. where-else: co-change partners when there is history, then tests, docs and the changelog.
7. conventions: H2 headings of the contributing docs, with line numbers.
8. next: the three-moment ripwire block that `ripwire wrap claude` prints.

When the page is over budget it drops, in order: conventions, layout depth, entries past 3, edges past one symbol, where-else past 3, then question sites. Act and build never drop. The root names what went (`dropped=`), and `over="1"` says the fixed sections alone outgrew the cap. Root attributes: `size_class`, `budget`, `bytes`, `confidence`, `build_source` (`none|manifest|docs+manifest`), `history` (`0` on a shallow clone).

`--for` output is byte-identical to before. The MCP server adds a `brief` tool (`task`, optional `bytes`; single-root) that serves the same composer. The tool catalog goes from 33 to 34 tools, and `brief` is in the `no-edit` profile that `ripwire wrap claude` registers. New gate: `test/briefcheck.sh`.

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

#### The package surface, subject tests and `<ranked>`

- `<entry>` names the package surface (`__init__.py`, `index.ts`, `lib.rs`, `mod.rs`) and the file that hands off to `main`, once each.
- The tests of the unit's subject lead `<where-else>`: tests anchored on the file the task imitates (a `like X: path` task takes that path as the exemplar).
- `<ranked>` names the files `--for`'s own page ranks that no other section names: the exemplar family, their registration files, then the files of its signature and tail rows. 12 are shown; over budget the line keeps 4. Off switch: `RIPWIRE_BRIEF_RANKED=0`.
- Over budget, attributes drop before items.

#### Routed for orientation questions, with the measured limits

`--help-task` (and so the Claude Code and Codex router hooks) recommends `--brief=TASK` for a question about the repository itself: "I'm new to this repo, where do I start", "give me an overview of this codebase", "how is this project organized". The card needs a repository noun plus orientation wording, and it is asked only where the router would otherwise abstain, so no earlier route changes. `--for` stays the default for task questions. The MCP `brief` description says it is the first call when new to a repo. Off switch: `RIPWIRE_BRIEF_ROUTE=0`. New gate arms: `test/taskroutecheck.sh (OB1)-(OB5)`.

Sealed check (8 fresh repos: sqlalchemy, pip, scrapy, vite, TanStack query, tokio, hugo, Catch2; items written by a separate agent): `--brief` 59 items in 32,022 B, `--for` 51 items in 120,161 B (26.6 % of the bytes; `--brief` matched or beat `--for` on 5 of 8 repos). By class (E/S/T/B items, `--brief` vs `--for`): 11/24 vs 9/24, 22/32 vs 27/32, 10/24 vs 3/24, 16/32 vs 12/32. By language: Python 26 vs 24, TypeScript 15 vs 11, Rust 8 vs 4, Go 5 vs 6, C++ 5 vs 6. Structure is the limit: `--for` finds more (27 vs 22). The help (`--help=--brief`), `docs/COMMANDS.md` and `docs/LIMITS.md` state this.
