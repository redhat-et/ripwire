### Fixed — `--deps` and `--report` stop reading Rust module declarations as dependency cycles

A parent's `mod x;` and the child's `use crate::…` or `use super::…` drew edges both ways, so every parent and child read as a
cycle and a crate read as one tangle: with true edges injected, nushell's largest cycle held 228 files. The parent-to-child
edge of a `mod x;` pair, with the child at the module-file rule's own location (beside a `mod.rs` or a crate root, or under
`<dir>/<stem>/`), is now containment when the declaration is its only reason: it leaves `--deps`' cycles,
`ccd`/`acd`/`nccd`/`shape` and a row's `transitive=`, and `--report`'s cycle list, and stays in `afferent=`, `instab=`,
`godfiles` and `stabledeps`. A parent that also uses its child (`pub use child::Thing;`, `use self::child::…`, a call
`child::f()`) depends on it, so that edge stays and a cycle through it is still reported. `<health containment_edges=N>` and
the `--report` heading count the pairs left out, and `--report` says "acyclic without the containment pairs" rather than a bare
"acyclic". On this build's own edges nushell leaves out 725 pairs and keeps three cycles of 3, 2 and 2 files, each a parent
that re-exports a child which uses the parent's items; zed leaves out 289 and has none. A crate root is `lib.rs`, `main.rs`, or a
file no `mod` declares (a `[lib] path`, a `[[bin]]`, an integration test). Not covered yet: `#[path]` modules and a `mod` inside
an inline `mod { }` (both read as the parent's own `mod x;`), and `--arch`'s `propagation_cost`, which still walks these pairs.
