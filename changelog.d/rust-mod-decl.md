### Fixed — `--deps` and `--report` stop reading Rust module declarations as dependency cycles

A parent's `mod x;` and the child's `use crate::…` or `use super::…` drew edges both ways, so every parent and child read as a
cycle and a crate read as one tangle: with true edges injected, nushell's largest cycle held 228 files. A `mod x;` pair, with
the child at the module-file rule's own location (beside a `mod.rs` or a crate root, or under `<dir>/<stem>/`), is now
containment: it leaves `--deps`' cycles, `ccd`/`acd`/`nccd`/`shape` and a row's `transitive=`, and `--report`'s cycle list,
and stays in `afferent=`, `instab=`, `godfiles` and `stabledeps`. `<health containment_edges=N>` and the `--report` heading
count the pairs left out. On the same injected graph nushell's largest cycle is 19 files (1,850 pairs left out); on this
build's own edges its three cycles were all such pairs and are gone. A crate root is `lib.rs`, `main.rs`, or a file no `mod`
declares (a `[lib] path`, a `[[bin]]`, an integration test). Not covered yet: `#[path]` modules, a `mod` inside an inline
`mod { }`, and `--arch`'s `propagation_cost`, which still walks these pairs.
