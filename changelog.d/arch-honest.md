### Fixed — `--arch`, `--deps`, `--cochange`, `--impact` and `--export=cc.json` stop reporting coupling from edges the index never had

Go, Java, Kotlin, C#, PHP, Swift, Dart, GDScript and Clojure draw almost no file-to-file edge in this build (Go only across a
`go.mod` replace), so `--arch` printed Ca = Ce = 0 and `zone="pain"` for every typed module of those languages, a design finding made
only of missing data. A module holding a file in such a language now reads `zone="unknown" no_file_edges=LANGS`: with no edge observed
it has no `ca`/`ce`/`I`/`D`/`reachable`, with one it keeps `ca`/`ce` as floors and has no `I`/`D`/`leaf`. `<metrics>` counts it in
`zone_unknown=`. Every no-edge file, with or without an observed edge, is left out of both system denominators (`dep_files=`, `propagation_cost`), so one
real edge elsewhere cannot bring back a `shape="horizontal"` over files that could not have an edge, and `masked_files=N` says how many
were left out; with no edge left among the other files, `ccd`/`nccd`/`shape` and `propagation_cost` are absent. `--cochange-groups` puts
`no_file_edges=` and `unknown_pairs=N` on its root when pairs with such a side are in no group, so `groups="0"` no longer reads as a clean answer. `--deps` drops `afferent=`/`instab=`/`transitive=`
on those files, and `--report` no longer calls such a tree acyclic. Roots carry `no_file_edges= unmeasured_files= graph_partial="1"`,
and `--arch` says on stderr that `violations=` is a floor. The same missing data used to print elsewhere as a measured zero, and no
longer does: `--cochange` (and the MCP `cochange`, and `--pr-context`) put `no_file_edges=` where `surprising="1"` claimed hidden
coupling for a Go pair with a real import; `--impact` (and the MCP `impact`) carries `no_file_edges=` on the root, because its
`importers=` is then a floor; `--export=cc.json` omits `fan_in`/`fan_out` for such a file instead of writing 0. Which languages is the
`fileEdges` column in `src/langfacts.h`. Trees with no such file are byte-identical. Thanks to @jflowers, whose #478 led to this finding.
