### Fixed — from a fresh cache, the second call is served from the warm snapshot

On a fresh cache, the first call has to parse every file, and the call after it should then be served from the warm snapshot. On llvm-project it was not. Calls 1, 2 and 3 all rebuilt the model and the call graph, and only call 4 was served. That is two extra 24–32 s calls before the first fast one. vscode and envoy waited one extra call.

There were two causes:

- **The first call did not store the model or the call graph.** A run that re-parses files is usually the run after an edit, and the next edit would make what it stored useless, so such a run stores neither. The first call on a fresh cache re-parses every file only because there is no cache yet, and that rule caught it too. A run that started with no parse cache now stores the model and the call graph as well as the crawl. A run after an edit still does not.
- **On llvm-project, the second call also counted as a re-parse.** Five test sources contain a NUL byte, and the first run skipped them before taking their content hash. The second run then found them changed, re-read them, and rewrote the whole 840 MB parse cache. The hash is now taken first, so the second run re-reads nothing and writes nothing.

`RIPWIRE_SNAPSHOT_STATS=1` now ends with `unsaved_why=ok|racy|reparsed`. It says why something this run built was not stored for the next run:

- `racy`: a file was too new to trust its timestamp;
- `reparsed`: the run re-parsed files after an edit.

Output is byte-identical to `--no-cache` on every call. Gates: `test/warmsnapcheck.sh` arm N, and `test/savecachecheck.sh` arm (w6).

Measured on an Apple M-series machine, Release builds of this change and of its base, one fresh cache per sequence, n=1, on a busy machine (load average 20-54), so the times are indicative only. Wall seconds for calls 1, 2, 3 and 4:

| tree | command | before | after |
| --- | --- | --- | --- |
| llvm-project | `--whereis=SelectionDAG` | 59.97, 63.28, 55.11, 6.75 | 43.34, 3.16, 3.30, 3.48 |
| llvm-project | map | 74.43, 29.87, 26.50, 1.34 | 39.71, 1.28, 1.14, 1.25 |
| envoy | `--for` | 9.39, 3.31, 0.72, 0.72 | 9.22, 1.33, 0.78, 0.91 |
| envoy | map | 6.41, 4.25, 0.26, 0.23 | 6.95, 0.23, 0.28, 0.27 |

Every call printed the same bytes before and after.
