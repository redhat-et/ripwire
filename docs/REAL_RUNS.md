# Four real runs

*Moved out of `README.md` for 0.7.0. Nothing was rewritten in the move.*

---

<details>
<summary><b>Four real invocations</b> against this repository, printed as the binary actually prints them — including why <code>--callers</code>' count is a floor and what <code>amb=</code> admits</summary>

**Four real invocations against this repository**, each printed as the binary actually prints it:
`--callers` (and why its count is a floor), the default ranked map (and what `amb=` admits),
`--test-gate` (exit 4 while obligations remain), and `--from-trace` (feed it the error itself, not a
paraphrase of one).
</details>

<details>
<summary>How these excerpts were edited — minified output wrapped for reading, and exactly which numbers are elided</summary>

Output is minified — one line, no whitespace between tags — so the excerpts below are wrapped for
reading, and each one's leading legend comment is elided. Nothing else is edited, except that
corpus-size numbers (file/symbol/edge counts, the ranked-map header's token/ambiguity tallies,
PageRank `k=` values, and the test-gate example's
`script_gates_unmodelled=` — a count of the script runners under `test/`, recursively) drift as this repository
grows: **the ranked map** elides those specifically, and says so again at the point of use, and **the
test gate** additionally trims its `<u>` rows down to 2 of the 25 the real run prints, behind a
trailing `…`.

</details>

<details>
<summary><code>--callers</code> — a call graph built on the spot, and why <code>count="7"</code> ships labelled a floor</summary>

**Ten seconds, no index server, no embeddings, no API key** — a parse and a call graph, built on the
spot. The rows below are a real capture: the callers and their files are gate-held current
(`test/readmeexamplecheck.sh`), the `:line` suffixes were true when captured and drift as the files
grow — nothing can keep a line number true in a document, so it is not claimed here. `p=` is where each caller is
defined; `sites_at=` lists its call sites as pasteable `file:line` tokens, so the lines to edit come with the first answer.

```
$ ripwire . --callers=rankGraphTeleport
<callers of="rankGraphTeleport" defs="1" count="7" root="." hop_tested="0" hop_untested="7" counts_floor="1">
<s t="fn" n="getIndex" p="src/mcpindex.h:1165" sites_at="src/mcpindex.h:1268"/>
<s t="fn" n="rankGraph" p="src/graph.h:7965" sites_at="src/graph.h:7968"/>
<s t="fn" n="anchoredLexicalRank" p="src/graph.h:8611" sites_at="src/graph.h:8662"/>
<s t="fn" n="runEval" p="src/eval.h:171" sites_at="src/eval.h:325"/>
<s t="fn" n="churnDecayRanking" p="src/main.cpp:1383" sites_at="src/main.cpp:1397"/>
<s t="fn" n="churnRankedGraph" p="src/main.cpp:1422" sites_at="src/main.cpp:1436 src/main.cpp:1437 src/main.cpp:1451"/>
<s t="fn" n="runDefaultMap" p="src/main.cpp:1632" sites_at="src/main.cpp:1752"/>
</callers>
```

`counts_floor="1"` is the point. Call edges are extracted from source text by name, so dynamic
dispatch contributes no edge (a call through a function pointer or callback is an edge only when
ONE function is bound to that variable in scope and the variable never escapes — its address taken
or reference-bound — and a macro-generated call site — tagged
`role="macro"` — only when its function-like `#define` is indexed): `count="7"` is a **floor**,
and the element says so before you read a single row.

</details>

<details>
<summary>The default ranked map — <code>--top-k=3</code>, and what <code>amb="2"</code> admits about a resolver guess</summary>

**The ranked map** — the default run, capped to three symbols so it fits here:

```
$ ripwire . --top-k=3
<!-- files=… symbols=… edges=… shown=3 est_tokens=… ambiguous=… unresolved=…
     precise=… skipped_oversize=… order=important-first -->
<r est_tokens="435">
<f p="./src/infra/svector.h" layer="infra">
<s t="method" n="size" sc="svector" k="…"></s>
<s t="method" n="push_back" sc="svector" amb="2" k="…">
<c n="buf" l="…,…"/><c n="grow" l="…"/></s>
</f>
<f p="./src/scipoverlay.h">
<s t="method" n="empty" sc="ScipOverlay" k="…"></s>
</f>
</r>
```

`files=`/`symbols=`/`edges=` and the `k=` rank values are elided: this repository is the corpus here,
so they move every time README.md itself gains or loses a line, which is not what the example
demonstrates. The rest of the header measures the whole corpus, not the excerpt — the `ambiguous=` tally is
the call-graph completeness gauge, and `amb="2"` on a row says two of that symbol's calls hit a name
with several definitions and the resolver guessed. Read the source when which-target matters.

</details>

<details>
<summary><code>--test-gate</code> — exit 4 while obligations remain, and why <code>script_gates_unmodelled="332"</code> stays nonzero on a clean clone</summary>

**The test gate** — `--test-gate` names the obligations and exits 4 while any remain. Captured with an
uncommitted change in the tree: `changed="1"` and the rows below appear only because something was
actually pending. A clean clone exits 0 with every changed/impacted/test count at zero. The structural
counts describe the tree, not git status, so they stay nonzero even then: `script_gates_unmodelled=`
(script-to-binary test runners the call graph cannot see), `script_gates_registered=`,
`script_gates_mapped=` and `script_gates_unresolved_dynamic=` (the suite's registered shell gates, and how
many of them map to their dependencies), and the resolver gauges `graph_ambiguous=`, `graph_unresolved=`
and `graph_unindexed=`. The capture below predates the `script_gates_*` registry counts and those gauges:

```
$ ripwire . --test-gate          # exit code: 4
<test-gate changed="1" impacted="80" tests="2" untested="76" shown_tests="2" tests_capped="0"
           shown_untested="25" untested_capped="1" script_gates_unmodelled="332" at="9cf0b16f3+dirty">
<t p="./test/adaptivecutshapefix/adaptive_cut_shape_test.cpp" run="bash test/adaptivecutshapecheck.sh"/>
<t p="./test/verify_radix.cpp" run_unknown="1"/>
<u sym="buildGraph" p="./src/graph.h" ccx="712"/>
<u sym="dispatchMcpLine" p="./src/mcp.h" ccx="428"/>
…
</test-gate>
```

A `run=` attribute appears only when a runner is derivable from real evidence — a test-dir script
whose stem matches the harness, or whose text names it; for TypeScript/JavaScript, a file already
recognized as test code (`test/`/`tests/`/`__tests__/`, or a `_test./.test./_spec./.spec.` name, or a `.e2e-spec./.perf-spec.` name — the
`__tests__/` directory convention is shared with every language, the rest are TS/JS's own) whose name
ALSO matches vitest/jest's own test-name shape (`.test.`/`.spec.`, or living under `__tests__/` at
all, jest's own two default conventions — never a `.d.ts` declaration file) — whose nearest
`package.json` names `vitest`, `jest`, or node's own test runner. Its own `package.json` is
AUTHORITATIVE for the whole subtree below it: a non-empty, non-placeholder `scripts.test` entry
decides the runner (or decides none — a same-named dependency never overrides it, whether that
dependency sits in the same manifest or a parent one), and only a manifest with NEITHER a real
`scripts.test` NOR a `vitest`/`jest` dependency is skipped in favour of one further up. A TS/JS file
with no manifest evidence of its own still falls back to the SAME test-dir shell/Python driver search
every other language uses — a named driver beats an
unguessed default. A row with none says so — `run_unknown="1"`, never a guessed suite command — and a
`<t>` row carries one or the other, never neither. A
`<g hops="2" n="3" p="a,b,c" run_unknown="1"/>` row is **two or more contiguous runner-less rows whose
attributes are byte-identical**, served as one: `n=` is how many, `p=` is their paths verbatim in list
order, and the disclosure is paid once per group rather than once per row. Rows that HAVE a runner group
the same way when each one's command is exactly `<head> <its own path>` with the same head:
`<g hops="1" n="3" p="a,b,c" run_each="pytest {p}"/>`, where a path's command is `run_each=` with `{p}`
replaced by that path. It is a template rather than a bare verb because of how it fails unexpanded:
`python3 {p}` errors, a bare `pytest` runs the whole suite. Everything else stays its own
row — a row whose command is not that shape (a runner that is another file, a `(cd pkg && …)` subshell, a
quoted or `--` path, a multi-root path) keeps its full `run=`, as does a row whose attributes or verb differ
from its neighbour's, and a path containing a
comma, which is never grouped at all, so `p=` splits on `,` into exactly `n=` paths. A `shown=`/`total=`
over these rows counts test FILES: a `<g>` row is `n=` of them.

`script_gates_unmodelled="332"` is the same discipline: script-to-binary is not a call edge, so those
gates are invisible to this walk, and the number says so rather than letting `tests="2"` read as
complete. The `<u>` rows are the untested blast radius: impacted symbols that no test in the corpus
reaches — never a file's own `<file-scope>` module scope (a top-level statement or anonymous-callback
body), since nothing in any language can name it and no test could ever be written for it; it still
counts toward `impacted=` when it is a real caller in the blast radius, just never as an obligation.
Those excluded owners are counted, not dropped without a trace: `untested_modscope="N"` (always
present, alongside `untested=`) says how many, so a change whose only reader is an untestable
entrypoint discloses why `untested=` reads zero instead of looking like there was nothing to find.
The capture above predates that attribute (and a few other root attributes added since), so its root
lacks it; today's root carries `untested_modscope="N"` immediately after `untested=`.

A TS/JS file with NO manifest evidence of its own (no `package.json` anywhere in the crawl boundary, or
the nearest one decides nothing) still gets one more chance before falling to the shell/Python driver
search above: its own bytes are read for a `node:test` import or require — `import test from "node:test"`,
`import { test, describe } from "node:test"`, `require("node:test")`, single or double quoted (#60). This
is a real parse, not a substring scan: a `"node:test"` mention inside a comment or an unrelated string
literal is not evidence. An explicit `package.json` `scripts.test` (or `vitest`/`jest` dependency) still
wins over this — including an authoritative-but-unrecognized script, which is a decided "no" — so the
import fallback only ever fires on what was previously `run_unknown="1"`.

For a `.ts`/`.mts`/`.cts` file — whether the runner was named by `scripts.test: "node --test"` or inferred
from the import above — a `run=` command is spelled only where the checks below find nothing that makes Node
refuse to start it. They are read off the repository's own bytes, so they cannot see the Node that will run
it, and a refusal is `run_unknown="1"`, never a guess:

- **`.tsx` and `.jsx` never get a command.** Node's type stripping does not cover `.tsx` at all
  (`ERR_UNKNOWN_FILE_EXTENSION`), and plain `node` cannot load a `.jsx` file at all, on any Node version —
  both stay `run_unknown="1"` unconditionally.
- **Every relative import/require must resolve exactly as written, in the test file and in every local
  TypeScript module it reaches.** Node's module resolver, under type stripping, never probes an extension
  and never maps a `.js` specifier onto a `.ts` source — the exact shapes tsc-, tsx- and bundler-run TS code
  uses to import its own siblings. So a command is spelled only when every relative (`./`/`../`) static
  `import`/`export … from` specifier or `require(...)` argument names a file that exists on disk at that
  exact path. The walk follows each specifier that lands on a `.ts`/`.mts`/`.cts` file, reads at most 64
  modules, and a walk cut at that bound stays `run_unknown="1"` too.
- **No module on that walk may use syntax type stripping cannot erase.** Node strips types and rewrites
  nothing, so an `enum`, a `namespace` with runtime code (or holding only `declare` statements), the legacy
  `module M {}` keyword, a constructor parameter property, an import alias (`import A = B.C`,
  `import x = require(…)`), `export =`, an angle-bracket assertion `<T>x` or a decorator stops it with
  `ERR_UNSUPPORTED_TYPESCRIPT_SYNTAX` (or a parse error) before any test runs; any of them outside a
  `declare` stays `run_unknown="1"`. A type-only namespace and a `declare enum` are erased and do not count.
- **The command is additionally Node-version-aware, from `engines.node`.** `--experimental-strip-types`
  itself exists from Node 22.6 only (an older Node refuses to start at all with it); stripping is ON BY
  DEFAULT — the flag becomes a harmless no-op — from Node 22.18 and separately from Node 23.6 (two floors,
  not one continuous range: 23.6 turned it on first, the 22.x line got it later by backport, and a bare
  23.0–23.5 does not have it). This tool cannot see which
  Node will run the emitted command, so it reads `engines.node` from the nearest manifest: the bare
  `node --test <file>` when that range proves every satisfying Node has stripping on by default; the
  flagged `node --experimental-strip-types --test <file>` when it proves >= 22.6 but not provably
  default-on, or when there is no manifest at all (a stated assumption of a Node that strips types with the
  flag, not a guess at an unseen runtime); and `run_unknown="1"` when the range admits ANY Node below 22.6
  (a plain `>=18`/`^20`, or a compound range like `>=24 || ^20`, where every `||` alternative must pass on
  its own) or cannot be read with confidence at all. Each alternative is read for its upper bound too,
  because the default-on versions have a gap: `^22.18.0` gets the bare form, but `>=22.18` also admits
  23.0–23.5 and keeps the flag.

Every node:test file, `.js` or TypeScript, must also load as the module kind its own syntax needs. A file
with a static ES `import`/`export` runs as an ES module only as `.mjs`/`.mts`, under `"type": "module"` in
its nearest `package.json`, or on a Node with default module-syntax detection (22.7 and later, 20.19 on the
20.x line). Without one of those the command stays `run_unknown="1"`: an explicit `"type": "commonjs"` (or a
`.cjs`/`.cts` file) turns detection off, and with no `"type"` the `engines.node` range must prove detection —
`>=22.7` does, `>=20.19` does not, since it admits 21.x. With no `engines.node` at all, a TypeScript file keeps
the stated assumption above and a `.js` file stays `run_unknown="1"`, since its command otherwise rests on
no assumption at all. A CommonJS file (`require`, no ES `import`/`export`) runs either way.

`.js`/`.mjs`/`.cjs` never need the flag. Their one version question is the runner itself: the `--test` flag
exists from Node 18.1 and, by backport, 16.17 — never on 17.x, and 18.0 has the `node:test` module but not
the flag. So `engines.node` must not admit a Node below 18 without it: `^16.17.0`, `>=18` and `>=18.1` get the bare
form, while `>=16`, `>=16.17` and `16.17 - 18` (they reach 17.x) stay `run_unknown="1"`, and so does a range confined
to 18.0.x such as `18.0.x`. A hyphen range `A - B` is bounded by B. `>=18` is accepted although it admits 18.0:
that is one release from April 2022, the command fails loudly there, and refusing the most common spelling would make
the answer useless on most projects. No `engines.node` at all keeps the bare form.

A TS/JS `run_unknown="1"` can still mean the manifest genuinely names nothing recognized (and the test file
itself names no `node:test` import either), one of the refusals above, or a real runner this tool does not
yet derive: node's own test runner invoked through `tsx` (when neither the manifest nor the test file's own
bytes name `node:test` directly) and `bun`'s test runner. These stay an honest unknown rather than a guess;
`pnpm`/`yarn`-prefixed test scripts derive correctly today (spelled `npx …`, which finds a local binary
first).

</details>

<details>
<summary><code>--from-trace</code> — hand it the stack trace, sanitizer report or compiler error itself, not a paraphrase</summary>

**From an error, not a paraphrase of one** — `--from-trace` takes a stack trace, sanitizer report or
compiler error on stdin or from a file, maps its frames onto indexed symbols innermost-first, and
returns the innermost in-corpus body with them:

```bash
./build/ripwire . --from-trace=asan_report.txt
cmake --build build 2>&1 | ./build/ripwire . --from-trace=-
```

</details>

