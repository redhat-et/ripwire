### Fixed — a Rust or Python call Rule 3 narrowed no longer reads as proven without a written binding

Rule 3 keeps the one imported file that defines a call's name. Member calls already took that answer as a hedge; a bare or qualified
call did not, so Rust `Ok(..)`, `assert!(..)` and Python's `conv()` through a local printed as plain edges to an unrelated namesake.
Those languages write what a name is bound to, so the writing is now the proof: a Rust `use` of the name, a glob of the target's module,
a qualifier naming its module or type; a Python import binding or a star import of an indexed module. Without it the edge stays, marked
`via="name"`, and only Rule 3's own file and the caller's own file are offered: no directory namesakes. A Python call through a local or
parameter holds a value, not a definition, so it gets no edge and counts under `declined=`. A Rust qualifier that provably leaves the
tree (`oneshot::channel()`, `String::new()`) reads as outside it, unless its root names a package directory of the tree.
`test/rule3memberguardcheck.sh`.
