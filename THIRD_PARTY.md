# Third-party code

Everything in `third_party/` is upstream open-source code, vendored as a single header per
library and kept byte-for-byte with its original license block intact. Nothing here is
relicensed; each file is governed by the license named below, not by the repository's
`LICENSE`.

Code under `src/` — including `src/infra/` — is first-party and covered by the repository
`LICENSE` (Apache-2.0).

Build-time dependencies fetched by CMake (`FetchContent`, pinned by commit) are **not**
vendored into this tree and are not listed here; see `CMakeLists.txt` for the pinned
`tree-sitter`, per-language grammar and `doctest` revisions and their own licenses.

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
