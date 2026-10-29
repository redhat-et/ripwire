### Added — `--for` rows say when every caller is a test (`tonly="1"`)

A `--for` signature row carries `tonly="1"` when the function (or method) has at least one indexed caller and every one of
them is test code (a test path or an in-file test scope; `--dead-code`'s `test-only=` rows and this flag share the edge test, the entry-point
vetting and the library-text name vetting, in one header). It answers "is X used, or only tested" without a second call: `in=` already counts the callers, `tonly=` says none
is library code. The legend clause rides only on an answer whose ranked head holds such a row, in both dialects, the
`--json` twin (`"tonly":true`) and the MCP `for` verb.

Kept off, so the flag never claims more than the index shows: a function with no caller at all (that is an absent `in=`), a
library caller by name only, a name a library holds as a value (a dispatch table or registering decorator), a call the
resolver declined to bind that names it (an interface value or untyped receiver), a method an interface declares (the
implementation is reached through the interface), a test symbol itself, and any index that is cut (a memory-guard stop, or an
oversize code file the crawl dropped). It is one hop, not reachability: a function only another test-only function calls is not
flagged. A call the index does not attribute at all (an aliased import, run-time dispatch) is invisible, so verify before deleting.

Fix round: the flag also stays off a function whose name any library code file spells outside its own signature (a module-
attribute call `options.f()`, a `getattr` string, a bound `self.m` / `this.m` value; comment-only lines excluded), a method of a
type that has any base (an override or trait implementation reached through the base: Python `self.get_handler()`, C++
virtual, Rust `impl Display`), a Python dunder, a Go method named for a std protocol (`String`, `Error`, ...), and a caller
that is a library function merely named `test_*`. It rides a row only when the question can use it (a use word such as
used/callers/tested/remove, the row's name, or its file or directory) and, like `e=`, not under an explicit token ceiling
tighter than the default.

Fix round 2: a function only called from code a package ships under a nested `test/` directory (django's test runner and client)
is not flagged when library code imports that code; a Python starred line (`*head, tail = options.f(x)`) and a code line that
starts with a block comment count as uses; the Go protocol list covers the standard-library interfaces (`WriteTo`, `Set`, `Push`,
`Pop`, `Seek`, `Flush`, ...); a method of a TS/JS/Java/C# class that has any base (`implements OnInit`, `extends Component`) and
a decorated or annotated def (a NestJS `@GrpcMethod`, a Flask `@app.route`, a Rust `#[get]`) are never flagged; and a path in the
question names a row's file or directory only at whole path segments (`hono/...` no longer matches `src/hono-base.ts`).
