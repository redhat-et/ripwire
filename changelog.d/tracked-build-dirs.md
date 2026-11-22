### Fixed — a `build/` directory whose files git tracks is indexed

The crawl skips `build/` on the guess that it holds build output. When a repository commits real source there (bat's `build/` holds its Cargo build script), that source was missing from every answer, so a question about it could not be answered at all.

Now the crawl asks git. A `build/` that git tracks files under is indexed, and only its tracked files are: an untracked file inside it is left out and counted (`untracked_build=` on the map header, why=`untracked-build` rows in `--skipped`). A `build/` git does not track stays skipped, as before. git is asked once per root, and only when the walk reaches a `build/` that the repository's ignore rules do not already cover, so a repository that gitignores its `build/` starts no extra process. A root that is not a git repository keeps the old behaviour. Under `--no-ignore`, a tracked `build/` is indexed with every file in it, the flag's usual meaning, and the warm cache watches git's index there too, so a `git add` is never answered from a stale crawl.

Only `build/` changed. `dist/`, `out/` and `target/` stay skipped even when tracked. Repositories commit bundles under `dist/`: on axios that meant readable rollup output, which none of ripwire's minified, bundle or vendored checks flags, and the copies pushed real source off the first page of answers. `vendor/`, `third_party/` and `node_modules/` stay skipped as well.

The commands that index a commit's tree (`--quality-delta`'s HEAD side, `--merge-scout`, the churn window, `--dmm`) index the same directories, so an edit inside a tracked `build/` is reported as a change to existing code rather than as new code. The MCP server also notices a file added there.

On the 89 GA1 DEV questions, one question goes from missed to complete and none loses ground. On the 99 GA3 DEV questions no answer changes. The parse cache and warm snapshot versions move, so the first run after upgrading reparses. Gate: `test/trackedbuilddircheck.sh`.
