### Added — `--quality-delta` names a classifier that leaves a value without an outcome (`defect="unhandled-arm"`)

A sixth defect-shape facet reports, as a minor row that never gates, a classifier over a closed set that gives a
value it does not name no outcome: a C/C++ `switch` with no `default:` that decides a value (every arm returns one,
or every arm assigns the same name) over an enum defined in the indexed tree and leaves one of its enumerators out
(count sentinels such as `kFooCount` and aliases are owed no arm); a shell `case` with no `*)` arm that ends its
function with `return`/`echo`/`printf` arms, or whose arms each set one name read after `esac`; a Python if/elif
chain or `match` that ends a value-returning function with no `else`, so an unmatched value returns `None` (an
`Enum` the file defines is checked for coverage). The row's `p=` is the switch's line and its new `why=` attribute
names what is left out (XML, `--json` and MCP). Because the site names the missing enumerators, appending one to an
enum gives a row on every switch it leaves incomplete, even an untouched one. A default/`*)`/`else`, full coverage,
a comment that states the omission, a void dispatcher, an `#if` in the switch or the enum, and generated code give
no row. Rust and TypeScript stay out (the compiler checks `match`; TS has no never-check reading yet). The quality
snapshot scheme moves to 38, so an older snapshot cache is rebuilt once.
