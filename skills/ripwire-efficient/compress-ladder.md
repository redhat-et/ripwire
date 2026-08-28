# The detail ladder (and --compress) with ripwire

Reference for `ripwire-efficient` — load this when you've already found the right file(s) via the map and
need to decide HOW MUCH of a symbol to pull into context, or want to shrink body output further.

`<dir>` = repo root. Every rung is additive to the ranked map; climb only as far as the question demands.

## The ladder — climb one rung at a time

| Rung | Command | You get | Cost |
|---|---|---|---|
| 0. map | `ripwire <dir>` | ranked signatures + call edges | cheapest |
| 1. skeletons | `--pack-signatures` | body-elided decl skeletons + doc-comments (~68% fewer element BYTES at the top-50 sigs payload, vs the same symbols' full bodies; see `docs/EVALS.md`) | cheap |
| 2. control flow | `--outline=A,B` | branch/loop skeletons of named symbols | medium |
| 3. full body | `--expand=A,B` | full source of named symbols + inline callee signatures | dear |
| 4. whole files | `--pack-top-n=N [--pack-budget-bytes=B]` | the top-N symbols' source under a byte budget (last one truncated at a newline) | dearest |

Most questions die at rung 0–1. Reach rung 3 for the ONE symbol you're editing; rung 4 only for a
handoff/briefing artifact, never for browsing.

## --compress — the modifier, and its exact scope

`--compress` strips `//` and `/* */` comments and collapses blank runs **in SERVED BODIES**: the
body output of `--expand`/`--outline`, `--for`'s auto/anchor bundle and `--detail=N` top-N bodies,
`--pack-task`, `--from-trace`, and `--exemplar` — disclosed per bundle as `compress="1"` on the
`<bodies>` element. It is a no-op on the map, on `--pack-signatures` (already body-elided), and on
`--for`'s compact (conceptual) route, which serves no bodies to strip. Typical saving:
**20–35%** of the body tokens.

```
ripwire <dir> --expand=SYM1,SYM2 --compress     # bodies, comments stripped
ripwire <dir> --outline=SYM1 --compress         # skeleton, comments stripped
```

It is **string-literal-safe** — a `//` or `/* */` *inside a string* is kept verbatim:
```
const char* url = "http://example.com // not a comment";   // ← survives --compress
```
So compressed output still compiles/reads correctly — you lose human commentary, not code.

`--max-tokens=N` still applies to the overall output if you need a hard cap on top.

## When NOT to compress

If the *reason* you're reading the body is its comments/documentation (a doc-quality review, or
intent that lives only in the comments), skip `--compress` — it removes exactly what you came
for. Default to compress for "I need the logic"; plain for "I need the rationale."

## Redaction — emitted bodies are NOT verbatim by default

Any body/doc text ripwire emits (`--expand`, `--outline`, `--pack-signatures`, `--pack-top-n`, `--recall`,
MCP `fetch_body`/`memory_recall`) has high-confidence credentials (API keys, tokens, connection strings)
redacted by default before you ever see them — safe to paste into a handoff or a shared doc as-is. Pass
`--no-redact` to opt out and get bodies verbatim (e.g. you're deliberately auditing a secret-handling path
and need the real value) — never the default, and never silent: you have to ask for it by name.
