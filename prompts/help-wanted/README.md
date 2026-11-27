# prompts/help-wanted/ — open problems, each with a prompt to start from

These are detailed prompts a contributor, or their coding agent, can follow to take on one open
problem in ripwire. Paste one into your agent at the root of a ripwire checkout. Every prompt ends the
same way: **it writes a plan and stops**, so a maintainer can agree the plan with you before any code is
written. Each open problem has its own `help wanted` issue, linked below; comment there to claim it, and
read the thread first, since a claim or a draft PR may already be on it.

| Slug | What it delivers | Difficulty | Issue | Prompt |
| --- | --- | --- | --- | --- |
| `ready-to-claim-slice` | Any one of the fully specified slice issues (Kotlin, C#, PHP and TS import renames, Dart imports, `kLangFacts` columns, `mem=` fields, …): claimed, red first, byte-identical on every other language | good first issue for the S slices | one per slice, listed in the kit | [`ready-to-claim-slice.md`](ready-to-claim-slice.md) |
| `kotlin-expect-actual` | Kotlin Multiplatform calls through `expect` declarations get their call edges back | medium | [#154](https://github.com/redhat-et/ripwire/issues/154) | [`kotlin-expect-actual.md`](kotlin-expect-actual.md) |
| `correctness-fuzzers` | Fuzzers that check correctness, not just crashes: graph invariants, rank mass, input order, cache round-trips, census conservation | medium | [#149](https://github.com/redhat-et/ripwire/issues/149) | [`correctness-fuzzers.md`](correctness-fuzzers.md) |
| `graph-unit-tests` | Unit tests for the CSR graph and the PageRank kernel, with hand-checkable expected values, built and run by CI. Claimed by @Ankit-cs; [#531](https://github.com/redhat-et/ripwire/pull/531) is in review, so offer help there | medium | [#153](https://github.com/redhat-et/ripwire/issues/153) | [`graph-unit-tests.md`](graph-unit-tests.md) |
| `certified-ranking-order` | A derived, measured and disclosed bound on how far down the PageRank order is provably correct | medium | [#147](https://github.com/redhat-et/ripwire/issues/147) | [`certified-ranking-order.md`](certified-ranking-order.md) |
| `agent-integration-verification` | A live report on whether the published wiring works in Cursor, Windsurf, Gemini CLI, opencode or aider, FAILs included | good first issue if you already use one of the five; medium if a recipe fix follows | [#146](https://github.com/redhat-et/ripwire/issues/146) | [`agent-integration-verification.md`](agent-integration-verification.md) |
| `find-the-next-superlinear` | A scale-rung report on the largest public trees, peak memory included, and a fixture and fix for anything that grows faster than its input | medium | [#151](https://github.com/redhat-et/ripwire/issues/151) | [`find-the-next-superlinear.md`](find-the-next-superlinear.md) |
| `zig-language` | Zig indexed: a pinned grammar, definitions and tests, and disclosed blind spots. The grammar measurement is done (draft [#495](https://github.com/redhat-et/ripwire/pull/495), @csy20); extraction is next | medium | [#166](https://github.com/redhat-et/ripwire/issues/166) | [`zig-language.md`](zig-language.md) |
| `simd-more-isas` | An AVX-512 or RISC-V Vector path for the string kernels, proven bit for bit against the scalar twins | large | [#161](https://github.com/redhat-et/ripwire/issues/161) | [`simd-more-isas.md`](simd-more-isas.md) |
| `shader-languages` | One shader language, GLSL, HLSL or WGSL, indexed next to CUDA and Metal | medium to large | [#160](https://github.com/redhat-et/ripwire/issues/160) | [`shader-languages.md`](shader-languages.md) |
| `conservation-everywhere` | Every inheritance, doc-mention and HAS-A reference accounted for, and `declined_calls=` on `--safe-delete` and `--edit-check`. The `declined_calls=` part is done; inheritance, doc mentions and HAS-A remain | large | [#148](https://github.com/redhat-et/ripwire/issues/148) | [`conservation-everywhere.md`](conservation-everywhere.md) |
| `install-discovery-mise-aqua` | Skills embedded in the binary and a `ripwire skills install` subcommand, so `wrap` and `--doctor` work for mise, aqua and every other install channel. Ask on the issue first: the direction is being re-decided | large | [#225](https://github.com/redhat-et/ripwire/issues/225) | [`install-discovery-mise-aqua.md`](install-discovery-mise-aqua.md) |
| `member-macro-reparse-beyond-allcaps` | The C/C++ member-macro re-parse carried past ALL-CAPS, with `--match`, `--lint` and `--slice` reading the repaired tree | large | [#156](https://github.com/redhat-et/ripwire/issues/156) | [`member-macro-reparse-beyond-allcaps.md`](member-macro-reparse-beyond-allcaps.md) |
| `scala-jvm-bridge` | Scala indexed as the third JVM language, bridged to Java and Kotlin without moving their edges | large | [#159](https://github.com/redhat-et/ripwire/issues/159) | [`scala-jvm-bridge.md`](scala-jvm-bridge.md) |
| `visual-basic-language` | A VB.NET grammar that clears the parse-rate bar, then first-class indexing | large | [#165](https://github.com/redhat-et/ripwire/issues/165) | [`visual-basic-language.md`](visual-basic-language.md) |

"Difficulty" is the size of the change that reaches the kit's finish line, not of its first measurement
alone. The top-level [`../full-audit.md`](../full-audit.md) is open for help too, on [#152](https://github.com/redhat-et/ripwire/issues/152): run one lens,
or all six. @jay23606 is assigned there; coordinate on the thread.

Build the tool before you start, as [`../README.md`](../README.md) shows: a plain build, no build type.

## Solved

These kits led to merged fixes. Each stays here as a worked example of a kit that landed, with a
**Solved** note at its top that names the gate proving it and any part still open.

| Slug | What it delivered | Solved by | Prompt |
| --- | --- | --- | --- |
| `next-uses-bare-name` | The callers answer's `next=` pointer lands on a declined call site for narrowed selectors too | @antoleod, in [#182](https://github.com/redhat-et/ripwire/pull/182), closing [#158](https://github.com/redhat-et/ripwire/issues/158) | [`next-uses-bare-name.md`](next-uses-bare-name.md) |
| `struct-layout-doctor` | A `--doctor` `layout` row that catches a binary whose translation units were compiled against different struct layouts | @lennix1337, in [#224](https://github.com/redhat-et/ripwire/pull/224), closing [#162](https://github.com/redhat-et/ripwire/issues/162) | [`struct-layout-doctor.md`](struct-layout-doctor.md) |
| `uses-qualified-selector` | `--uses` and its siblings stop answering 0 for a `::` selector that `--callers` resolves | @aniruddhaadak80, in [#231](https://github.com/redhat-et/ripwire/pull/231), closing [#164](https://github.com/redhat-et/ripwire/issues/164); the dot-qualified follow-up in [#657](https://github.com/redhat-et/ripwire/pull/657) | [`uses-qualified-selector.md`](uses-qualified-selector.md) |
| `ts-literal-receivers` | TS/JS built-in calls on literal receivers, such as `"x".replace()`, stop binding unrelated user functions | @csy20, in [#244](https://github.com/redhat-et/ripwire/pull/244), closing [#163](https://github.com/redhat-et/ripwire/issues/163) and [#59](https://github.com/redhat-et/ripwire/issues/59); the `--uses` twin by @lennix1337 in [#411](https://github.com/redhat-et/ripwire/pull/411) | [`ts-literal-receivers.md`](ts-literal-receivers.md) |
| `kotlin-scope-functions` | Kotlin scope functions (`run`, `let`, `apply`, `also`, `with`) stop binding unrelated Java methods | @llvm-x86, in [#438](https://github.com/redhat-et/ripwire/pull/438), closing [#155](https://github.com/redhat-et/ripwire/issues/155) | [`kotlin-scope-functions.md`](kotlin-scope-functions.md) |
| `quality-delta-unchanged-tree-zero` | `--quality-delta` reports zero on a tree identical to HEAD. Still open: a sparse checkout, pinned as a known gap in `test/qualitycheck.sh` | @llvm-x86, in [#437](https://github.com/redhat-et/ripwire/pull/437), closing [#228](https://github.com/redhat-et/ripwire/issues/228); @qinghuanandejiangshi in [#237](https://github.com/redhat-et/ripwire/pull/237); maintainers in [#304](https://github.com/redhat-et/ripwire/pull/304) | [`quality-delta-unchanged-tree-zero.md`](quality-delta-unchanged-tree-zero.md) |
| `cpp-nested-std-namespaces` | Nested `std::` calls such as `std::ranges::move` stop binding in-repo definitions. Still open: the optional ObjC++ step, pinned in `test/stdqualcheck.sh` | maintainers, in [#331](https://github.com/redhat-et/ripwire/pull/331), closing [#150](https://github.com/redhat-et/ripwire/issues/150) | [`cpp-nested-std-namespaces.md`](cpp-nested-std-namespaces.md) |
| `nesting-refusals-visible` | A file refused for pathological nesting shows in `--skipped` on cold and warm runs, and `--match` refuses it too | maintainers, in [#331](https://github.com/redhat-et/ripwire/pull/331), closing [#157](https://github.com/redhat-et/ripwire/issues/157) | [`nesting-refusals-visible.md`](nesting-refusals-visible.md) |
| `deps-ts-aliases-workspaces` | `--deps`, `--arch` and `--report` disclose unresolved TS/JS imports, then draw edges for tsconfig `paths` aliases and workspace packages | maintainers, in [#336](https://github.com/redhat-et/ripwire/pull/336) and [#340](https://github.com/redhat-et/ripwire/pull/340), closing [#220](https://github.com/redhat-et/ripwire/issues/220) reported by @srinchow | [`deps-ts-aliases-workspaces.md`](deps-ts-aliases-workspaces.md) |
