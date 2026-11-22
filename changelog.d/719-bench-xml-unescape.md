### Fixed — bench readers decode XML-escaped paths and names before comparing them (#719, thanks @soarkit)

`bench/arb/run_arb.py`'s `query_files` and `trace_files` took `<f p=>`, `<frame p=>` and `<hop p=>` values without undoing the
emitter's escaping, so a file such as `src/a&b.py` ranked as `src/a&amp;b.py` and never matched its gold path; both now decode through
one `xml_path` helper, as `affected_tests` already did. The same capture-without-decode shape is fixed in `bench/tgrep-h2h/arms.py`,
`bench/tokenaudit/sweep.py`, `bench/bench_proof.py` and `bench/spec_trace.py`. `benchxmlpathcheck` pins it against a fake binary.
