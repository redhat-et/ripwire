### Added — route registrations are captured by the tags queries, not a framework-word gate (#448)

A Hono or Koa server registered no routes at all: the registrar walk only armed in a file whose text
contained `express`/`fastify` (Python: `flask`/`fastapi`). One comment naming a framework was enough
to turn detection on — and a wordless server got nothing.

The shapes now live where every other shape lives: `@route.def` captures in the JS/TS/TSX and Python
`tags.scm` (`obj.VERB('/path', …, handler)` and `@app.VERB('/path')` above a def). The C++ arm keeps
the checks a query cannot make — the verb table, the leading `/`, and a function-valued last argument,
so a `Map.get('/x', fallback)` lookup registers nothing. The file-level gates are gone with the walk's
server arms; the client shapes (`fetch`, `axios.<verb>`, `requests.<verb>`) stay in the walk.

On the hono and starlette corpora the change is byte-inert (494 argv, 0 diff): hono's `src/` registers
no routes of its own — every text-shape hit there sits in a doc comment the parser never enters — and
starlette's core routes are class-based, not decorator-based.
