# Add a shader language: GLSL, HLSL or WGSL

You are adding one **shader language** to ripwire's index. The candidates are GLSL, HLSL and WGSL;
the STEP 0 measurement below decides which one goes first. Follow `prompts/add-a-language.md` for the
mechanics. This file supplies what is specific to shaders: the grammar survey, the corpora, and the
design decisions.

Work in a git worktree. Run gates in the foreground.

---

## Why this matters

ripwire already reads two GPU languages, and each one got there through a measured decision:

- **CUDA** (`.cu`/`.cuh`) uses the vendored `tree-sitter-cuda` grammar, a generated superset of
  tree-sitter-cpp.
  - `kernel<<<grid, block>>>( … )` launch sites are real call edges, so `--callers` of a kernel names
    its host-side launchers.
  - `test/cudacheck.sh` records the probe behind that choice: under the plain C++ grammar every
    definition survived, but no launch produced a call reference.
- **Metal** (`.metal`) rides the C++ grammar under `Lang::Cpp`. The comment above the `.metal` row in
  `src/ingest_crawl.h` records the measurement on a 45-shader application tree:
  - 0.81% of bytes landed in ERROR under the C++ grammar, against 12.3% under the C grammar;
  - every entry point survived error recovery.

What ripwire cannot read yet is the rest of real-time graphics:

- **GLSL**, the OpenGL and Vulkan shading language. Its reference front end is
  [KhronosGroup/glslang](https://github.com/KhronosGroup/glslang).
- **HLSL**, the DirectX language, compiled by
  [microsoft/DirectXShaderCompiler](https://github.com/microsoft/DirectXShaderCompiler). HLSL is also
  the second language by bytes in [Unity-Technologies/Graphics](https://github.com/Unity-Technologies/Graphics).
- **WGSL**, WebGPU's language (a [Candidate Recommendation Draft](https://www.w3.org/TR/WGSL/) at the
  World Wide Web Consortium).
  [gfx-rs/wgpu](https://github.com/gfx-rs/wgpu) carries WGSL, GLSL, HLSL and Metal shaders side by
  side.

To ripwire today, a renderer is host code that calls into nothing. That is exactly where CPU/GPU
contracts break silently: a binding index, a uniform block layout, an entry-point name.

One shader language completes the GPU story next to CUDA and Metal. It gives agents working on game
engines, graphics and WebGPU both halves of their code in one graph.

---

## STEP 0 — the grammar survey and the parse rate

Checked against each repository on 2026-09-11. Re-check before you vendor.

| language | grammar | license | pin (tag → commit) | last commit | ABI | external scanner | built on |
| --- | --- | --- | --- | --- | --- | --- | --- |
| GLSL | [tree-sitter-grammars/tree-sitter-glsl](https://github.com/tree-sitter-grammars/tree-sitter-glsl) | MIT | `v0.2.0` → `e47b8b62b59d0e3529f1c31b03e025d6bd475044` | 2025-03-16 | 14 | none | `grammar(C, …)`, tree-sitter-c |
| HLSL | [tree-sitter-grammars/tree-sitter-hlsl](https://github.com/tree-sitter-grammars/tree-sitter-hlsl) | MIT | `v0.2.0` → `bab9111922d53d43668fabb61869bec51bbcb915` | 2025-03-23 | 14 | `scanner.c`, uses the serialization buffer | `grammar(CPP, …)`, tree-sitter-cpp |
| WGSL | [szebniok/tree-sitter-wgsl](https://github.com/szebniok/tree-sitter-wgsl) | MIT | no tags; HEAD `40259f3c77ea856841a4e0c4c807705f3e4a2b65` | 2023-01-09 | 13 | `scanner.c` | — |
| WGSL + Bevy preprocessor | [tree-sitter-grammars/tree-sitter-wgsl-bevy](https://github.com/tree-sitter-grammars/tree-sitter-wgsl-bevy) | MIT | `v0.1.4` → `d9306a798ede627001a8e5752f775858c8edd7e4` | 2025-09-18 | 14 | `scanner.c`, stateless (`serialize` returns 0) | extends szebniok/tree-sitter-wgsl |

- **ABI.** Every one sits inside the vendored core's window: tree-sitter v0.26.9 accepts 13 through
  15 (`third_party/deps/tree_sitter/lib/include/tree_sitter/api.h`). ABI 13 is the edge of that
  window.
- **Maintenance.** Plain WGSL's grammar has had no commit since January 2023.

**The order to measure is GLSL, then HLSL, then WGSL.** Ship the first one that clears the bar.

- **GLSL and HLSL are generated supersets of grammars ripwire already extracts.** The CUDA precedent
  shows such a grammar can reuse its parent's `tags.scm` wherever the node names line up. That is the
  cheapest path to definitions and calls.
- **GLSL has no external scanner.** HLSL's scanner must be classified by `test/vendorpatchcheck.sh`
  arm H.
- **The WGSL grammars are further from home.** The maintained one parses a Bevy-specific
  preprocessor. On non-Bevy WGSL, such as wgpu's, measure whether it behaves as a superset in
  practice.

**Corpora.** Pin a commit for each.

- **GLSL:** glslang's test tree and wgpu.
- **HLSL:** DirectXShaderCompiler's test tree and Unity's Graphics repository.
- **WGSL:** wgpu, plus a project that uses naga_oil's `#import`.
- **Engine shaders, not just compiler tests.** A compiler's suite is adversarial on purpose and will
  under-report the parse rate.
- **Measure only; write fixtures fresh.** Check each corpus's license before you quote a line of it.

**Which files are shaders.**

- **GLSL** has no single extension. glslang's standalone driver reads the stage from the file name
  (`StandAlone/StandAlone.cpp` in that repository). It accepts `.vert`, `.frag`, `.comp`, `.mesh`,
  the ray-tracing stages such as `.rgen`, and a unified `name.vert.glsl` form.
- **HLSL** uses `.hlsl`, and commonly `.hlsli` for included files.
- **WGSL** uses `.wgsl`.

Every extension you add to `kLangTable` is a claim. Check the corpora for non-shader files with the
same extension before you claim it.

**The measurement.** Follow add-a-language.md STEP 0, and record two numbers per file:

- whether the root has an error;
- the share of bytes inside ERROR subtrees, the Metal measurement's second number.

Report both per corpus.

GLSL and HLSL are **preprocessed**. Engines build shader variants out of `#define`, `#ifdef` and
macro-generated declarations, and tree-sitter parses the text as written. Report the macro-heavy
files separately, because that is where the parse rate will fall.

---

## Design notes

**A new `Lang`, or ride a C-family one?**

- **Why CUDA and Metal ride.** Both use `Lang::Cpp` for a stated reason: host and device share one
  call namespace through dual-compile headers. A separate `Lang` would drop out of every C-family
  behaviour (the `.metal` comment in `src/ingest_crawl.h`).
- **Why the new languages may not.** Most GLSL and WGSL share no call namespace with host code: a host
  reaches a shader through an API and a name string. HLSL headers are sometimes shared with C++.

Argue the choice in the plan, with a measurement: what a riding language would inherit that is wrong
for it, and what a new `Lang` would lose.

**Entry points and stages.**

- **WGSL:** `@vertex`, `@fragment` or `@compute` on a function (the specification's shader-stage
  attributes).
- **GLSL:** `void main()` in each stage file, where the file name gives the stage. Many files define
  `main`, so a call graph that merges them is wrong. Plant that decoy first.
- **HLSL:** the build usually names the entry point. Inputs and outputs carry semantics such as
  `SV_Position` and `SV_Target`
  ([Microsoft Learn, semantics](https://learn.microsoft.com/en-us/windows/win32/direct3dhlsl/dx-graphics-hlsl-semantics)).

Mark entry points where the syntax marks them. Disclose the ones only the build knows.

**Bindings and uniforms as symbols.** These declarations are the CPU↔GPU contract, and indexing them
is most of the value:

- **GLSL:** `layout(set = 0, binding = 1) uniform Block { … } name;`, and bare
  `uniform sampler2D tex;`.
- **HLSL:** `cbuffer Name : register(b0) { … }` and `Texture2D tex : register(t0);`. In
  [register](https://learn.microsoft.com/en-us/windows/win32/direct3dhlsl/dx-graphics-hlsl-variable-register),
  `b` is a constant buffer, `t` a texture, `s` a sampler and `u` an unordered access view.
- **WGSL:** `@group(0) @binding(1) var<uniform> name: T;`.

Before you invent a symbol kind, check which kinds `docs/ARCHITECTURE.md` and `--help` already
define, and prefer one of those.

**Include and import edges** (add-a-language STEP 5, a separate round).

- **GLSL.** Core GLSL has no `#include`. glslang recognizes the `GL_GOOGLE_include_directive` and
  `GL_ARB_shading_language_include` extensions (`glslang/MachineIndependent/Versions.cpp` in that
  repository).
- **HLSL.** `#include "file.hlsli"` is ordinary preprocessor text.
- **WGSL.** The core language has **no** import or include. Its module-level directives are `enable`,
  `requires` and `diagnostic`.
  - `#import` comes from [naga_oil](https://github.com/bevyengine/naga_oil), Bevy's preprocessor. A
    module declares `#define_import_path my_module`, and a shader writes `#import my_module`.
  - tree-sitter-wgsl-bevy has `preproc_import` and `define_import_path` nodes.
  - That edge resolves through a declared module name, not a path. Resolve it through the corpus's
    own index. If two files declare the same import path, the answer is neither.

**Built-ins are not user functions.** `texture`, `normalize`, `dot`, `mix` and `saturate` must never
bind to a user definition with the same name. Count built-in calls as external.

#134 is the precedent. A `std::`-qualified C++ call bound at full confidence to the repository's lone
definition of that name, and one method gained 2,107 false callers on a real corpus.

**Preprocessor-dead code.** ripwire already computes preprocessor-dead ranges for C and C++ in
`src/preprocdead.h`. Decide whether GLSL and HLSL files go through that path. If they do,
`test/preprocdeadscalecheck.sh` covers the include-guard flood that once made it quadratic.

---

## Constraints

**The non-negotiables from `CLAUDE.md`:**

- The gate comes before the code.
- Determinism is a contract: two runs are byte-identical, and a warm run equals a cold one.
- A zero means "none found".
- Every truncation is disclosed.
- Never `VERIFY( false )` on a degrade path.
- Never use `std::map` or `std::unordered_map`.

**Grammars are vendored and pinned by full SHA.**

- Fix grammar bugs upstream.
- The only local edits are crash or memory-safety fixes, carried as
  `third_party/patches/<dep>/NNN-name.patch` under `test/vendorpatchcheck.sh`'s convention. The yaml,
  markdown and swift grammars already carry such patches.
- The vendored tree lives under `third_party/deps/<name>/`, because `ripwire_use_vendored_source` in
  CMakeLists.txt never fetches.

**Every walk over an unbounded child list** uses the cursor from `src/infra/tschildren.h`, or states
at the loop why a comment cannot reach that list. Uniform blocks, cbuffers, argument lists and struct
bodies are all unbounded.

---

## Known traps

- **A superset grammar is not its parent grammar.**
  - Its copy of the C or C++ rules comes from the parent version it was generated against, not from
    ripwire's vendored tree-sitter-c or tree-sitter-cpp.
  - Check every capture you reuse against the new grammar's `node-types.json`.
  - CUDA works only because its launch expression is **aliased** to `call_expression`.
- **One hostile file can abort a vendored scanner.**
  - #126's review found Kotlin's scanner calling `abort()` once its delimiter stack filled.
  - The yaml and markdown scanners once wrote past their serialization buffer on deep nesting.
  - Run the ASan build over generated files: thousands of nested blocks, nested `#if`, a
    16,000-comment flood inside one uniform block, and one very long line.
- **Name collisions.** A `main` in every stage file, and built-ins sharing a user function's name.
  Both need decoys.
- **Case-insensitive includes.** Windows-authored HLSL often spells an `#include` with different case
  from the file on disk. Plant a case-collision decoy and assert the right file wins, or neither does.
- **Generated shaders.** Engines and cross-compilers such as SPIR-V Cross and naga emit GLSL, HLSL and
  WGSL from one source, so a corpus can be mostly generated text. Say what share of yours was
  generated.
- **What add-a-language.md does not mention yet.** Two gates enforce these today:
  - `THIRD_PARTY.md` needs a row for the new `third_party/deps/` directory (`test/dependencypincheck.sh`
    arm (A'), added in #131).
  - Every vendored scanner that uses the serialization buffer must be classified
    (`test/vendorpatchcheck.sh` arm H).
- **Parser versions collide across PRs.** `kParserVer` and `kIngestParserVerMirror` move together,
  and in-flight language PRs claim versions too. Take the next free value on the tree you merge onto.

---

## Acceptance criteria

1. **The STEP 0 table**: language × grammar × corpus × parse rate × ERROR-byte share, with the pick
   and the reason for it.
2. **A vendored grammar.** It lives under `third_party/deps/`, is pinned by full SHA with its tag as a
   comment, and has a `THIRD_PARTY.md` row. Configure succeeds with the network off.
3. **Definitions with spans.** Functions, structs, uniform blocks or cbuffers, and bindings. Entry
   points are marked where the syntax marks them, and disclosed where it does not.
4. **A red-first gate.** `test/<lang>check.sh`, with fixtures in `test/<lang>fix/`. It is registered
   in `test/regression.sh`, and shown red on a binary without the change. The fixtures include:
   - a two-`main` decoy;
   - a built-in named like a user function;
   - a case-collision include;
   - a macro-heavy file, with its disclosed behaviour;
   - a binding with explicit coordinates.
5. **The standard arms from add-a-language STEP 7**: spans, decoy, determinism, warm == cold,
   `xmllint`, and a relative vs absolute root.
6. **Scaling**: a comment-flood isolation pair for every new unbounded walk.
7. **Memory safety**: ASan and LSan clean over the corpus and the hostile fixtures. If the grammar
   has a scanner, it is classified under arm H.
8. **Disclosure**: the README Languages section's count and a paragraph for the new language, plus
   the blind spots stated in the gate header.
9. **STEP 8's suite**, green in the foreground.

---

## What the PR description should contain

- **STEP 0**: the survey and parse-rate table, with corpus commits.
- **The grammar chosen**, the ones rejected and why, and the `Lang` decision with the measurement
  behind it.
- **Blind spots**, and where each one is disclosed:
  - preprocessor variants;
  - generated shaders;
  - entry points named only by the build;
  - naga_oil conditional imports, if in scope.
- **The gate**: red output, then green output, and the ASan result.
- **Deferred work**: include and import edges, the other shader languages, and cross-language binding
  checks.

---

**Write the plan — the STEP 0 measurements, the grammar you expect to pick and the result that would
change that, the `Lang` decision, the symbol kinds, and the fixtures — then STOP for my go-ahead.**
