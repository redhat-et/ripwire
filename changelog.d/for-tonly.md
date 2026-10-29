### Added — `--for` rows say when every caller is a test (`tonly="1"`)

A `--for` signature row carries `tonly="1"` when the function (or method) has at least one indexed caller and every one of
them is test code (a test path or an in-file test scope; the same rule `--dead-code`'s `test-only=` rows use, now one shared
predicate). It answers "is X used, or only tested" without a second call: `in=` already counts the callers, `tonly=` says none
is library code. The legend clause rides only on an answer whose ranked head holds such a row, in both dialects, the
`--json` twin (`"tonly":true`) and the MCP `for` verb.

Kept off, so the flag never claims more than the index shows: a function with no caller at all (that is an absent `in=`), a
library caller by name only, a name a library holds as a value (a dispatch table or registering decorator), a call the
resolver declined to bind that names it (an interface value or untyped receiver), a method an interface declares (the
implementation is reached through the interface), a test symbol itself, and any index that is cut (a memory-guard stop, or an
oversize code file the crawl dropped). It is one hop, not reachability: a function only another test-only function calls is not
flagged. A call the index does not attribute at all (an aliased import, run-time dispatch) is invisible, so verify before deleting.
