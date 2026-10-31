### Added — `--for` prints the re-export hops to a definition the task names

A question like "where is `ShellError`, used in ls.rs, defined?" got the definition and nothing between it and the use site:
the `pub use` / `export … from` statements a reader walks through were never rows. A `--for` answer now ends with a
`<reexports>` block when a task word names an in-tree definition that something re-exports: one `<def>` row, then each
re-export statement nearest the definition first (`<rx p= l= use=|from= at= as=>`), and the task-named file's own import
(`<u>`). Rust: `pub use path::Item`, `pub use path::{A, B}`, a module re-export (`pub use other::module`) and a glob
(`pub use path::*`, marked `glob="1"`: hedged), with paths resolved through `crate` / `self` / `super`, child modules and
Cargo package names, so same-named items in two modules keep their module identity (`cands="N"` when two manifests spell
one crate name). TypeScript/JavaScript: `export { a } from`, `export { a as b } from` (`as=`), `export * from`
(`glob="1"`), recorded by the TS/TSX/JS tags queries through the shared binds channel as a new `LocalBindKind::ReExport`
(parser version bump). Rows only: nothing here is a call edge. Not followed: a Rust `pub use a as b` rename (counted
`as_skipped=`; help-wanted #445), `export * as ns from`, and items defined inside an inline `mod { }`. A `pub use` inside an inline `mod { }` prints its full module path; `src/main.rs` beside a lib.rs and `src/bin/**` are binary crates, never the library's modules; a path through a name the file imports reads through that import (never a same-named workspace crate), and only an import of the same module counts — a child `mod` inherits no parent `use`, and a `use` inside a function body binds nothing outside it; `pub(crate) use` is labelled `vis="restricted"`; a walk that stops at 256 spellings says `capped="1"` beside `total=`. Under a token budget (`--token-budget=N`) the rows are not printed (they sit outside `est_tokens`): a one-line `<reexports held="budget" defs="N"/>` names how many definitions carry a chain. `RIPWIRE_NO_REEXPORT_HOPS`
turns it off. Gate: `test/reexportcheck.sh`.
