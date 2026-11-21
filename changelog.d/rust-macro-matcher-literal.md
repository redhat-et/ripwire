### Fixed — a Rust macro's matcher words are no longer read as calls at its invocation

The re-read of a Rust macro invocation's arguments (RUST-MACRO-ARGS) parsed `wrap!( matcher_fn( 3 ), drop )` as a tuple and
reported `matcher_fn` as a call, so `--callers=matcher_fn` listed the invoking function, although the word is a literal token
of `wrap`'s `macro_rules!` matcher (`( matcher_fn ( $x:expr ), $f:ident ) => …`) and nothing calls it. When the invoked macro is
a `macro_rules!` the same file defines, a bare call whose name one of its matchers spells as a literal word before a `( … )`
group is no longer kept; the expression the matcher binds (`$x:expr`) is still read. A macro defined in another file is not
consulted: the re-read is a per-file pass. Parser tag 338 (rich 339) invalidates the old extraction cache; kCacheVersion is
unchanged. `rustmacrocallcheck` arm [N] matcher_fn goes green and a new arm [K1] pins the kept `$x:expr` call.
