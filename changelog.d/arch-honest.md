### Fixed — `--arch` and `--deps` stop reporting coupling from edges the index never had

Go, Java, Kotlin, C#, PHP, Swift, Dart, GDScript and Clojure draw no file-to-file edge in this build, so `--arch` printed
Ca = Ce = 0 and `zone="pain"` for every typed module of those languages, a design finding made only of missing data. A module
with no edge observed and a file in such a language now reads `zone="unknown" no_file_edges=LANGS` with no `ca`/`ce`/`I`/`D`/`reachable`;
`<metrics>` counts it in `zone_unknown=`, and `propagation_cost` is absent when the whole index holds no edge. `--deps` drops
`afferent=`/`instab=`/`transitive=` on those files and `ccd`/`acd`/`nccd`/`shape` when the index holds no edge; `--report` no longer
calls such a tree acyclic. Roots carry `no_file_edges= unmeasured_files= graph_partial="1"`, and `--arch` says on stderr that `violations=`
is a floor. Which languages is the new `fileEdges` column in `src/langfacts.h`. Trees with no such file are byte-identical. Thanks to
@jflowers, whose #478 led to this finding.
