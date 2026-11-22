### Fixed — `--grep` names the files whose every hit its tier held back, and holds nothing back in a file whose parse degraded

`--grep`'s default tier serves code and holds comment and string hits back, counted in `suppressed_comment=` / `suppressed_string=`.

- **In a file whose indexed parse holds ERROR nodes** (its row carries `parse_degraded="1"`) that tier came from the same grammar that failed there: fzf's `shell/completion.zsh`, parsed with the bash grammar, had its definition and both calls of `__fzf_list_hosts` held back as "string", and the answer named no held-back file. A hit in such a file is now unclassified: it is served, counted in `tier_unclassified=`, and never suppressed. A string or comment hit in a clean file is held back exactly as before. The `tier_unclassified=` reading says so in both legends.
- **A file whose every hit was held back had no row**, so the answer never named it: the count said hits were held back, not where. The root now adds `held_files=` (how many such files), `held=` (the first five paths, in the answer's file order) and `held_next=` (the same search with `--grep-in=any`, which serves every tier); the MCP `grep` twin carries `held_files` / `held` / `held_next`. Present only when some file was wholly held back; every other answer is byte-identical.

Gate: `test/grepdegradedcheck.sh`.
