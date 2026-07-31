// H4 W3 Rust qualified-call fixture — file 3 of 3.
//
// The FILE form of a Rust file module (`src/plainmod.rs`), as opposed to src/gadget/mod.rs's DIRECTORY form.
// Both are named by the LAYOUT, not by any AST node, so `plainfn` carries scope="" exactly like a plain
// top-level function does — which is precisely why the guard cannot simply keep every scope-less candidate
// (V3 M-2). `crate::plainmod::plainfn()` must resolve, and it does so through the file-module rule in
// graph.h::rustFileModuleOf, which maps this path to the module name "plainmod".
pub fn plainfn() {}
