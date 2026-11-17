### Fixed — `--safe-delete` no longer claims coverage for an empty radius

`risk="uses-exist"` with no transitive radius (a function used only as a value, `impact_reaches="0"`) printed the reading "at least part of the radius is test-covered". The full legend now states that the radius is empty and claims no test coverage, and `--help` says the same. A non-empty radius keeps its sentence unchanged. New arm (21) in `test/safedeletecheck.sh`. Thanks to CodeRabbit for the finding in its review of #676.
