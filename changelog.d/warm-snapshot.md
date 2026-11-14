### Changed — a warm run on an unchanged tree loads the crawl, the model and the resolved graph instead of rebuilding them

A warm run used to skip only the parse. It then walked the tree again, asked git for its ignore answer again, decoded every cache record, rebuilt the model and resolved every reference: all of it a deterministic function of what the cache already held. A run now writes `<cache>.snap` beside the cache file once the tree has been parsed and is unchanged, and the next run on the same tree reads it.

Measured on this lane (`--cache=FILE`, flagless map, median of 9, `/usr/bin/time -l`, dev build, macOS arm64, the before column from the base commit's binary on the same blobs, the same minute):

| repo | wall before | wall after | user CPU before | user CPU after | instructions before | instructions after | peak footprint before | peak footprint after | cache file | snapshot |
|---|---|---|---|---|---|---|---|---|---|---|
| koa | 0.03 s | 0.01 s | 0.01 s | 0.00 s | 0.155 G | 0.109 G | 8.3 MiB | 8.3 MiB | 0.47 MB | 0.17 MB |
| envoy | 1.23 s | 0.17 s | 1.30 s | 0.18 s | 20.37 G | 2.42 G | 341.5 MiB | 264.9 MiB | 154.6 MB | 62.9 MB |
| vscode | 3.24 s | 0.29 s | 3.47 s | 0.35 s | 54.05 G | 4.19 G | 602.4 MiB | 469.6 MiB | 284.6 MB | 112.6 MB |

What it costs: the snapshot is 36 % to 41 % more disk beside the cache file on those three trees, and the one run that writes it is slower and larger than a run without it (envoy 1.72 s and 390.7 MiB against 1.23 s and 341.5 MiB; vscode 4.17 s and 685.3 MiB against 3.24 s and 602.4 MiB; one run each). The run after an edit writes nothing: a snapshot is only written by a run that re-parsed no file.

What it never does is answer from a snapshot it cannot vouch for. The file carries the build's source identity, a digest of every option and of the environment the crawl and the resolver read, and one checksum over every byte. The model and the graph are keyed on every crawled file's path and content hash, and the graph on every file the resolver read outside the cache (a `go.mod`, a Cargo manifest, a `tsconfig.json` above the root). The crawl is replayed only while every directory and every entry the walk looked at still has the device, inode, size, mtime and ctime it had, every input of git's ignore answer is unchanged, and none of them was younger than two seconds when it was recorded. Any mismatch is a full run, and the answer is the one that run always gave.

`test/warmsnapcheck.sh` holds it: stdout of a loading run is byte-identical to a `--no-cache` run for 24 verb invocations over every fixture tree in `test/`, and a changed file, an added or removed file, a same-size edit with its mtime put back, a new subdirectory, a changed `.gitignore`, a file added under a directory git reported ignored, a changed `go.mod`, a removed cache file, another `--exclude` set, a patched version field, a flipped byte and a truncated file each refuse it.

Not served: a multi-root run, `--scip`, `--pin-census`, `--max-memory`, `--no-cache`, a single-file root, and, for the model alone, a tree holding a pdf/docx/pptx/xlsx when `markitdown` is installed or one of them has a cached extraction (the crawl and the graph are still served). `RIPWIRE_NO_WARMSNAP=1` turns it off; `RIPWIRE_SNAPSHOT_STATS=1` prints one stderr line saying which stages a run loaded and which guard refused the rest.
