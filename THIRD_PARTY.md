# Third-party code

Everything in `third_party/` is upstream open-source code, kept byte-for-byte with its original
license block intact. Nothing here is relicensed; each file is governed by the license named
below, not by the repository's `LICENSE`.

Code under `src/` — including `src/infra/` — is first-party and covered by the repository
`LICENSE` (Apache-2.0).

There are **no downloaded dependencies**. Everything the build compiles is in this repository:
`third_party/*.h*` are the header-only libraries, and `third_party/deps/` holds the full build
dependency set (tree-sitter core, every grammar, doctest). A clone builds with the network
unplugged — `test/dependencypincheck.sh` proves it by configuring with
`FETCHCONTENT_FULLY_DISCONNECTED=ON` and asserting nothing was cloned.

## Header-only libraries (`third_party/`)

| File(s) | Library | Author | License | Upstream |
| --- | --- | --- | --- | --- |
| `third_party/unordered_dense.h`, `third_party/stl.h` | unordered_dense | Martin Leitner-Ankerl | MIT | https://github.com/martinus/unordered_dense |
| `third_party/svector.h` | svector | Martin Leitner-Ankerl | MIT | https://github.com/martinus/svector |
| `third_party/btree.hpp`, `third_party/gtl_base.hpp`, `third_party/gtl_config.hpp`, `third_party/phmap_fwd_decl.hpp` | gtl (Greg's Template Library) | Gregory Popovitch | Apache-2.0 | https://github.com/greg7mdp/gtl |
| `third_party/pdqsort.hpp` | pdqsort | Orson Peters | zlib | https://github.com/orlp/pdqsort |

Notes:

- `stl.h` is the standard-library include preamble that `unordered_dense.h` includes when it is
  split into two headers. It carries its own MIT block and belongs to the unordered_dense
  distribution, not to this project.
- The gtl headers are a subset: only what `btree.hpp` needs to compile standalone
  (`gtl_base.hpp` → `gtl_config.hpp`, plus `phmap_fwd_decl.hpp`).
- The include closure is self-contained: every quoted `#include` in these files resolves inside
  `third_party/`.

## Vendored build dependencies (`third_party/deps/`)

Each row is a pruned copy of the upstream repository at the pinned commit: the files the build
actually compiles, plus that project's `LICENSE`. The pin is recorded in three places that must
agree — this table, the `GIT_TAG` in `CMakeLists.txt` (kept solely as provenance; nothing fetches
it), and the upstream repository itself.

Every grammar is pruned to `src/parser.c`, `src/scanner.c` where one exists, and `src/tree_sitter/`
(the generated headers those two include). Grammar sources are machine-generated parse tables, which
is why the sizes are what they are — `parser.c` is one big static table, not hand-written code.

| Directory | Library | Author | License | Pinned commit | Upstream | Size |
| --- | --- | --- | --- | --- | --- | --- |
| `deps/tree_sitter` | tree-sitter (core runtime, v0.26.9) | Max Brunsfeld | MIT | `7f534862c3ec939c3a6ee147f7600ef5c1bf900f` | https://github.com/tree-sitter/tree-sitter | 0.9 MB |
| `deps/cpp` | tree-sitter-cpp (v0.23.4) | Max Brunsfeld | MIT | `f41e1a044c8a84ea9fa8577fdd2eab92ec96de02` | https://github.com/tree-sitter/tree-sitter-cpp | 17 MB |
| `deps/c` | tree-sitter-c (v0.24.1) | Max Brunsfeld | MIT | `7fa1be1b694b6e763686793d97da01f36a0e5c12` | https://github.com/tree-sitter/tree-sitter-c | 3.7 MB |
| `deps/cuda` | tree-sitter-cuda (v0.21.1) | Stephan Seitz | MIT | `48b066f334f4cf2174e05a50218ce2ed98b6fd01` | https://github.com/tree-sitter-grammars/tree-sitter-cuda | 19 MB |
| `deps/python` | tree-sitter-python (v0.23.6) | Max Brunsfeld | MIT | `bffb65a8cfe4e46290331dfef0dbf0ef3679de11` | https://github.com/tree-sitter/tree-sitter-python | 3.3 MB |
| `deps/go` | tree-sitter-go (v0.23.4) | Max Brunsfeld | MIT | `3c3775faa968158a8b4ac190a7fda867fd5fb748` | https://github.com/tree-sitter/tree-sitter-go | 1.5 MB |
| `deps/rust` | tree-sitter-rust (v0.23.2) | Maxim Sokolov | MIT | `cad8a206f2e4194676b9699f26f6560d07130d3f` | https://github.com/tree-sitter/tree-sitter-rust | 5.9 MB |
| `deps/java` | tree-sitter-java (v0.23.5) | Ayman Nadeem | MIT | `94703d5a6bed02b98e438d7cad1136c01a60ba2c` | https://github.com/tree-sitter/tree-sitter-java | 2.5 MB |
| `deps/javascript` | tree-sitter-javascript (v0.23.1) | Max Brunsfeld | MIT | `3a837b6f3658ca3618f2022f8707e29739c91364` | https://github.com/tree-sitter/tree-sitter-javascript | 2.4 MB |
| `deps/ts_typescript` | tree-sitter-typescript (v0.23.2; supplies both the `typescript` and `tsx` grammars) | Max Brunsfeld | MIT | `f975a621f4e7f532fe322e13c4f79495e0a7b2e7` | https://github.com/tree-sitter/tree-sitter-typescript | 17 MB |
| `deps/ruby` | tree-sitter-ruby (v0.23.1) | Rob Rix | MIT | `71bd32fb7607035768799732addba884a37a6210` | https://github.com/tree-sitter/tree-sitter-ruby | 15 MB |
| `deps/bash` | tree-sitter-bash (v0.23.3) | Max Brunsfeld | MIT | `487734f87fd87118028a65a4599352fa99c9cde8` | https://github.com/tree-sitter/tree-sitter-bash | 10 MB |
| `deps/csharp` | tree-sitter-c-sharp (v0.23.5) | Max Brunsfeld, Damien Guard, Amaan Qureshi and contributors | MIT | `cac6d5fb595f5811a076336682d5d595ac1c9e85` | https://github.com/tree-sitter/tree-sitter-c-sharp | 28 MB |
| `deps/json` | tree-sitter-json (v0.24.8) | Max Brunsfeld | MIT | `ee35a6ebefcef0c5c416c0d1ccec7370cfca5a24` | https://github.com/tree-sitter/tree-sitter-json | 56 KB |
| `deps/toml` | tree-sitter-toml (v0.7.0) | Ika (ikatyang) | MIT | `64b56832c2cffe41758f28e05c756a3a98d16f41` | https://github.com/tree-sitter-grammars/tree-sitter-toml | 164 KB |
| `deps/yaml` | tree-sitter-yaml (v0.7.2) | Ika (ikatyang) | MIT | `7708026449bed86239b1cd5bce6e3c34dbca6415` | https://github.com/tree-sitter-grammars/tree-sitter-yaml | 1.3 MB |
| `deps/objc` | tree-sitter-objc (v3.0.2) | Amaan Qureshi | MIT | `18802acf31d0b5c1c1d50bdbc9eb0e1636cab9ed` | https://github.com/amaanq/tree-sitter-objc | 27 MB |
| `deps/swift` | tree-sitter-swift | Alex Pinkus | MIT | `31d17fe7e818a2048c808b5c6fdc2dc792f4f5b5` | https://github.com/alex-pinkus/tree-sitter-swift | 20 MB |
| `deps/php` | tree-sitter-php (v0.24.2; the `php/` sub-grammar only) | Josh Vera, GitHub | MIT | `5b5627faaa290d89eb3d01b9bf47c3bb9e797dea` | https://github.com/tree-sitter/tree-sitter-php | 6.9 MB |
| `deps/lua` | tree-sitter-lua (v0.5.0) | Munif Tanjim | MIT | `10fe0054734eec83049514ea2e718b2a56acd0c9` | https://github.com/tree-sitter-grammars/tree-sitter-lua | 392 KB |
| `deps/doctest` | doctest (v2.4.12) | Viktor Kirilov | MIT | `1da23a3e8119ec5cce4f9388e91b065e20bf06f5` | https://github.com/doctest/doctest | 0.7 MB |

Notes:

- `deps/tree_sitter` keeps upstream's own `CMakeLists.txt` (the build `add_subdirectory`s it),
  `lib/src`, `lib/include` and `lib/tree-sitter.pc.in`. Its `lib/src/unicode/` is a subset of ICU
  carrying its own `LICENSE` (Unicode-DFS-2016) and `ICU_SHA` provenance file, left untouched.
- `deps/swift` is pinned to a bare commit rather than a tag because upstream's default branch does
  not carry a generated `parser.c`; that commit's generated output is what is vendored here.
- `deps/ts_typescript` keeps `common/scanner.h`, which both sub-grammars' `src/scanner.c` include.
- `deps/php` keeps the repo-relative layout `common/scanner.h` + `php/src/…` for the same reason, and
  for one more: upstream hosts TWO sub-grammars (`php/`, `php_only/`) whose `src/scanner.c` each
  `#include "../../common/scanner.h"`, so flattening to `deps/php/src` would break that include.
  Only `php/` — the sub-grammar that accepts markup around `<?php … ?>` islands — is vendored and
  built; `php_only/` is pruned.
- `deps/doctest` keeps the single header plus `doctest/parts/`, `scripts/version.txt` and
  `scripts/cmake/` — everything its own `CMakeLists.txt` reads. Its `doctest/extensions/` MPI
  headers are dropped: they include an external `<mpi.h>` this build never compiles. doctest is
  built only when the repository is configured with `-DRIPWIRE_TESTS=ON`.
- Nothing in `third_party/deps/` is modified. Re-deriving any row is `git clone` + `git checkout
  <pinned commit>` + the prune described above; a diff against the upstream commit is the audit.
