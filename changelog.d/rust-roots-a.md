### Fixed — Rust file edges: `crate::`, `super::`, `self::` and `mod x;` resolve in the includer's own crate and module

The Rust import probe anchored every `crate::` path at the first `lib.rs`/`main.rs` of the tree, so in a workspace most
`use crate::…` lines either drew nothing or drew an edge into another crate. It now reads, for each file, the crate it is
compiled in: the nearest `Cargo.toml` above it and that manifest's target (`[lib] path`, `src/main.rs`, `[[bin]] path`,
`build.rs`, and Cargo's `src/bin/`, `tests/`, `examples/`, `benches/` directories). Alongside:

- `mod b;` in a file `a.rs` (not a `mod.rs` or a crate root) is `a/b.rs` or `a/b/mod.rs`; the includer's own directory is
  read only when neither exists (the `#[path = "b.rs"]` shape, whose attribute is not captured).
- `super::` in a plain file `a/x.rs` is module `a`, `super::super::` climbs twice and never above the crate root, and
  `self::` is the file's own module; a one-segment `super::x` reaches the parent module's own file.
- `use crate::a::b` where `a/b.rs` exists draws `a/b.rs` even when `a.rs` exists too: the full path as a module file is
  read first and the parent module's file only when it misses, each step unique-or-degrade on its own.
- A brace group (`use crate::{a::b, c::{self, D}}`) resolves each member, and an `as` rename resolves the path it renames.

Measured on three in-sample trees (distinct file pairs from `.rs` includers, base main 292a26dec vs this change):
mdbook 64 → 118 (+54, none removed), axum 139 → 357 (+234; 16 removed: 15 edges into the `axum-core` crate from `axum`
files and one `self::rejection` that names an inline module), nushell 1,870 → 3,520 (+1,655; 5 removed, all into
another crate). The call narrow (the import evidence Rust call resolution reads) takes the same edges except brace-group
members, which it still leaves unresolved: there it adds 40 / 97 / 941 pairs and removes the same 0 / 16 / 5. Read as a
member call's namesakes by name, a group's edges turned two declined calls into name-only edges (card RULE3-MEMBER-GUARD).

What it does NOT do: a workspace crate named by its package (`use nu_protocol::…`) still draws no file edge (card
RUST-ROOTS-B), a one-segment `crate::Item` does not reach the crate root file, and `#[path]` values other than the
module's own name are not read.
