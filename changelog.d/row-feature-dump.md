### Added — `RIPWIRE_ROW_FEATURES=<path>`: a dev-only dump of what the `--for` ranker held for each printed row

A measurement switch, not a feature: when it is set, `--for` (CLI) and the MCP `for` verb append one tab-separated line per
printed answer row, in output order, to the named file. Each line carries the row's printed tag, `n=` and `p=`, its enclosing
element, and the ranker's view of it: the final score and what each lift stage added (base lexical score and tier multiplier,
mention, path cut, co-change, doc-mention), its place in score order, fan-in and `tested`, call-graph hops from the head row and
from the route's anchor definitions, the edge kind to the head, same file / same directory, whether the head round-robin moved
it up and its score-order rank, and the test / generated / vendored path classes. The column list is in `src/rowfeatures.h`.
The answers are byte-identical with and without the switch (`test/rowfeaturescheck.sh`); the CLI answer is captured and
written unchanged before the rows are read from it. It exists so precision rules for the top rows can be fitted offline on
the ranking's own internals rather than only on the printed attributes.
