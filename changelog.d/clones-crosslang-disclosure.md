### Fixed — `--clones` says that a group can span languages

The candidate pass filters on symbol kind alone and carries no language term, so a clone group can
span languages — and does, in 3 of 262,737 groups measured over five polyglot corpora. The document
never said so: the row prints no language, the legend had no language clause, and `docs/COMMANDS.md`
had no caveats block, so a reader meeting a `.cc`/`.rs` group had to infer the crossing from file
extensions. Two neighbouring verbs already carry the house template for exactly this (`--biggest-first`
"so V is cross-language", `--nonlocal-state` "that absence is NOT a measured zero").

Now disclosed in three places, split by what each costs: the per-document legend carries only the
fact (a group can span languages, none is printed, read `p=`), while `--help` and COMMANDS.md carry
the interpretation — a crossing is only meaningful where a link unit, a classpath or a declared
FFI/ABI surface already binds the two sides, and absent one, two bodies that rhyme is a coincidence.
Prose only; no new attribute, and no change to clone detection.
