### Changed — a failed internal check in a dev build now tells the agent, not only a debugger

In a dev build (no `NDEBUG`), a failed `ASSUME`, `EXPECTS`, `ENSURES` or `UNREACHABLE` used to write its notice to stderr and trap. Over MCP the client then saw a dead server, and the request in flight never got a response. On the CLI the agent saw an empty answer. Agents do not attach a debugger, so neither told them what happened or what to do next. Before the trap, the failure path now also writes:

- **MCP**, when a request is in flight: a JSON-RPC error for that request's id, with code `-32603`. The message is `ripwire internal check failed (this is a ripwire bug): <Kind> <expr> at <file>:<line> in <function> — <note>`, and `data` holds `kind, expr, file, line, function, note, version, built_from, hint`. The error uses the transport's own framing: one JSON line on stdout for stdio, or an HTTP response with `Content-Length` on the request's socket for `--listen`.
- **CLI**: one `<ripwire_internal_error kind= expr= at= fn= note= version= built_from= hint=/>` line on stdout, XML-escaped like the answers.
- **Both**: a `last-crash` record in the cache directory, holding a one-line summary plus the fields, argv, the call's flags, and the MCP tool and request id. The next CLI call prints one stderr line naming the record, then removes it. The next MCP `initialize` does the same, and also adds one sentence to the instructions the model reads.

The stderr notice stays. Its `EXPECTS` blame no longer says "look up the stack", and a new `Next:` row says what to do: the bug is ripwire's, so retry once with a different wording or verb, then fall back to grep/Read, and report the kind, location and command.

The exit status is still the trap's signal (133 or 132 under a shell), not a new exit code. A debugger and a crash reporter both rely on the process stopping at the failing instruction. A signal status is already distinct from ripwire's own exit codes 0-5, and the stdout line names the failure in words.

The failure path formats into fixed static buffers and writes with write(2), so nothing is allocated after the check fails. A check that fails inside the report goes straight to the notice and the trap. Two threads failing at once produce one report. `DASSERT`, `VALIDATE` and `--lsp` are unchanged.

Release builds are unchanged. Each new entry point is an empty inline under `NDEBUG`, so a release binary does not contain the test trigger string.

Gate `test/agenttrapcheck.sh` uses a dev-only trigger, `RIPWIRE_TEST_TRAP=assume|expects|ensures|unreachable`. It checks:
- the CLI line, the notice and the signal exit;
- the record, reported once by the next call and then cleared;
- over MCP stdio, a parseable error for a string request id with `data.kind == "Expects"`, then the note at the next `initialize`, once;
- with the trigger unset, byte-identical output;
- in a release binary, that none of this exists.

Three mutants each turned the gate red: dropping the MCP error write, answering a fixed id instead of the request's, and leaving the record in place after reporting it. With the trigger unset, 20 in-sample `--for` rows were byte-identical to the previous build in stdout, stderr and exit code.
