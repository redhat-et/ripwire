# prompts/help-wanted/ — open problems, each with a prompt to start from

These are detailed prompts a contributor, or their coding agent, can follow to take on one open
problem in ripwire. Every prompt ends the same way: **it writes a plan and stops**, so a maintainer
can agree the plan with you before any code is written. The prompts land together, in one pull
request; each open problem then has its own issue, labelled `help wanted` and titled with the slug
below. Comment on that issue to claim it.

| Slug | What it delivers | Difficulty | Prompt |
| --- | --- | --- | --- |
| `struct-layout-doctor` | A `--doctor` row that catches a binary whose translation units were compiled against different struct layouts | good first issue | [`struct-layout-doctor.md`](struct-layout-doctor.md) |
| `uses-qualified-selector` | `--uses`, `--safe-delete`, `--verify` and the MCP `uses` verb stop answering 0 for a `::` selector that `--callers` resolves | good first issue | [`uses-qualified-selector.md`](uses-qualified-selector.md) |
| `cpp-nested-std-namespaces` | Nested `std::` calls such as `std::ranges::move` and `std::chrono::duration_cast` stop binding in-repo definitions | medium | [`cpp-nested-std-namespaces.md`](cpp-nested-std-namespaces.md) |
| `ts-literal-receivers` | TS/JS built-in calls on literal receivers, such as `"x".replace()`, stop binding unrelated user functions (#59) | medium | [`ts-literal-receivers.md`](ts-literal-receivers.md) |
| `nesting-refusals-visible` | A file refused for pathological nesting shows in `--skipped` on cold and warm runs, and `--match` refuses it too | medium | [`nesting-refusals-visible.md`](nesting-refusals-visible.md) |
| `kotlin-expect-actual` | Kotlin Multiplatform calls through `expect` declarations get their call edges back (builds on #126) | medium | [`kotlin-expect-actual.md`](kotlin-expect-actual.md) |
| `kotlin-scope-functions` | Kotlin scope functions (`run`, `let`, `apply`, `also`, `with`) stop binding unrelated Java methods (builds on #126) | medium | [`kotlin-scope-functions.md`](kotlin-scope-functions.md) |
| `correctness-fuzzers` | Fuzzers that check correctness, not just crashes: graph invariants, rank mass, input order, cache round-trips, census conservation | medium | [`correctness-fuzzers.md`](correctness-fuzzers.md) |
| `graph-unit-tests` | Unit tests for the CSR graph and the PageRank kernel, with hand-checkable expected values, built and run by CI | medium | [`graph-unit-tests.md`](graph-unit-tests.md) |
| `certified-ranking-order` | A derived, measured and disclosed bound on how far down the PageRank order is provably correct | medium | [`certified-ranking-order.md`](certified-ranking-order.md) |
| `agent-integration-verification` | A live report on whether the published wiring works in Cursor, Windsurf, Gemini CLI, opencode or aider, FAILs included | medium | [`agent-integration-verification.md`](agent-integration-verification.md) |
| `simd-more-isas` | An AVX-512 or RISC-V Vector path for the string kernels, proven bit for bit against the scalar twins | medium | [`simd-more-isas.md`](simd-more-isas.md) |
| `find-the-next-superlinear` | A scale-rung report on the largest public trees, and a fixture and fix for anything that grows faster than its input | medium | [`find-the-next-superlinear.md`](find-the-next-superlinear.md) |
| `conservation-everywhere` | Every inheritance, doc-mention and HAS-A reference accounted for, and `declined_calls=` on `--safe-delete` and `--edit-check` | large | [`conservation-everywhere.md`](conservation-everywhere.md) |
| `member-macro-reparse-beyond-allcaps` | The C/C++ member-macro re-parse carried past ALL-CAPS, with `--match`, `--lint` and `--slice` reading the repaired tree (needs #135) | large | [`member-macro-reparse-beyond-allcaps.md`](member-macro-reparse-beyond-allcaps.md) |
| `scala-jvm-bridge` | Scala indexed as the third JVM language, bridged to Java and Kotlin without moving their edges (builds on #126) | large | [`scala-jvm-bridge.md`](scala-jvm-bridge.md) |
| `visual-basic-language` | A VB.NET grammar that clears the parse-rate bar, then first-class indexing | large | [`visual-basic-language.md`](visual-basic-language.md) |
| `zig-language` | Zig indexed: a pinned grammar, definitions and tests, and disclosed blind spots | large | [`zig-language.md`](zig-language.md) |
| `shader-languages` | One shader language, GLSL, HLSL or WGSL, indexed next to CUDA and Metal | large | [`shader-languages.md`](shader-languages.md) |

Where a prompt's own size section gives a range, the difficulty is the size of the change that
reaches its finish line, not of its first measurement alone. The top-level
[`../full-audit.md`](../full-audit.md) is open for help too, with its own issue: run one lens, or all six.

Build the tool before you start, as [`../README.md`](../README.md) shows: a plain build, no build type.

## Solved

These prompts led to a merged fix. Each stays here as a worked example of a kit that landed.

| Slug | What it delivered | Solved by | Prompt |
| --- | --- | --- | --- |
| `next-uses-bare-name` | The callers answer's `next=` pointer lands on a declined call site for narrowed selectors too | @antoleod, in [#182](https://github.com/redhat-et/ripwire/pull/182), closing [#158](https://github.com/redhat-et/ripwire/issues/158) | [`next-uses-bare-name.md`](next-uses-bare-name.md) |
