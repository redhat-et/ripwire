### Fixed — a Rust or Python call Rule 3 narrowed no longer reads as proven without a written binding

Rule 3 keeps the one imported file that defines a call's name. Member calls already took that answer as a hedge; a bare or qualified
call did not, so Rust `Ok(..)`, `assert!(..)` and Python's `conv()` through a local printed as plain edges to an unrelated namesake.
Those languages write what a name is bound to, so the writing is now the proof: a Rust `use` of the name into the target's crate, a glob
of the target's module, a qualifier (read whole from the root it is written with) naming its module or type; a Python import binding
that no local or parameter of the caller or an enclosing function shadows, or a star import whose chain reaches the target's file.
Without it the edge stays, marked `via="name"`, and only Rule 3's own file and the caller's own file are offered: no directory namesakes.
Which item a binding names is not compared with Rule 3's target, so a `use` or `from b import conv` that reaches a different definition
of the name still proves it. A Python call through a local or parameter holds a value, not a definition, so it gets no edge and counts
under `declined=`, also when the file imports the same name. A Rust qualifier that provably leaves the tree, read from its written root
(`oneshot::channel()`, `String::new()`, `std::io::stdout()`), reads as outside it; a path rooted at `crate`, `super`, `self`, a crate of
the tree or a package directory of the tree does not. `test/rule3memberguardcheck.sh`.
