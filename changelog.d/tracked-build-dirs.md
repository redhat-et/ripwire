### Fixed — a `build/`, `dist/`, `out/` or `target/` directory git tracks files under is indexed

The crawl pruned those four directory names on a guess that they hold generated output. When a repository commits real source under one of them — bat's `build/` holds its Cargo build script — that source was missing from every answer, and a question about it could not be answered at all.

The crawl now asks git: such a directory is crawled when git tracks a file under it, and stays pruned otherwise. Untracked build output, ignored or not, is pruned exactly as before; `vendor/`, `third_party/`, `node_modules/` and every other name on the list stay pruned whether git tracks them or not. git is asked once per root, and only when the walk meets one of the four names that git's ignore rules did not already cover, so a repository whose `build/` is gitignored starts no extra process. A non-git root and `--no-ignore` keep the old prune.

The verbs that index a commit's tree (`--quality-delta`'s HEAD side, `--merge-scout`, the churn window, `--dmm`) index the same directories, so a change inside a tracked `build/` gates as a change rather than reading as new code, and the MCP server notices a file added there.

On the 89 GA1 DEV questions (page 1 of the default `--for`), 21 of the 89 trees index more files (45 in all) and one question goes from missed to complete; no question loses a rung. On the 99 GA3 DEV questions only axios tracks such a directory (its `dist/` bundles): one question gains a function under the original grader and none under the stricter one, and one loses a body to the bundle copies, which now take rows on five axios answers. The parse cache version moves, so the first run after upgrading reparses. Gate: `test/trackedbuilddircheck.sh`.
