### Added — `--impact` sums up the importers a cut listing hides

A cut importer listing showed the 40 most-imported importers and nothing about the rest. Beside `importers_capped="1"` the
root now carries `importers_tests=` (how many importers are test, bench or fixture files) and `importers_dirs=` (the three
directories, by their first two path segments, that hold the most, as `dir:count`), both counted over every importer. On
cpython, `Lib/os.py` has 512 importers: `importers_tests="353" importers_dirs="Lib/test:346,Lib:58,Lib/idlelib:24"`. XML,
columnar, JSON and the MCP tool carry it.
