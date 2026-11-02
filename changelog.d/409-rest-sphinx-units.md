### Added — reST and Sphinx documents become real units (#409, thanks @muayyad-alsadi)

`.rst` no longer goes through the markdown grammar. A hand-written parser reads titles in any punctuation, with the level
taken from first-seen order, and makes `.. option::`, `.. setting::`, `.. function::`, `.. class::`, `.. method::`,
`.. confval::` and their siblings into units named by their target. `.. _label:` is a unit too, and `:ref:` and `:doc:` are
link edges. A `.txt` is indexed when the nearest Sphinx `conf.py` declares it in `source_suffix`, which brings in django's
679 documents; a `.txt` anywhere else stays unindexed and stays in `unindexed=`. Past 20,000 units or 64 levels of nesting
a file keeps the units it has and reports `why="extract-partial"` in `--skipped`.
