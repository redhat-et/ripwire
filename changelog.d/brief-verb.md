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
