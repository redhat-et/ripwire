### Fixed — a map of llvm-project no longer grows without bound: the name-keyed class and alias walks enter each name once

Any verb on llvm-project (a flagless map too) grew resident memory at about 5 GB/s; one process reached 149.7 GB before the operating system killed it. The cause was `derivesFromName` in `buildClassIdentity`: a depth-12 breadth-first walk over the NAME-keyed base-class table with no visited set. Where one class name is defined in many files, each with its own bases (llvm's test suites define `A` 4,769 times), every level appended every base of every frontier name, so the frontier grew as the product of the fan-outs. With that bounded, graph.h's element-of-alias and arrow-opacity walks over the name-keyed alias table showed the same shape at about 60 MB/s.

All three walks now keep a visited set: each name enters once, at its shortest distance, so "reached within N steps" is unchanged and output is byte-identical. The class walk is also memoised per outer class name. Measured: the default map and one `--for` are byte-identical on koa, tmux, cpython, envoy and nushell, and llvm-project's cold map peaks at about 3.0 GB. 0.6.9 and every earlier release carry the defect.

`test/namewalkcheck.sh` builds a class fan-out (6 names x 12 layers) and an alias fan-out (16 names x 7 levels) that an unvisited walk cannot finish. The binary must finish both under a 1 GiB RSS watchdog, with exact `RIPWIRE_STATS` work counts; given the unfixed parent binary, the gate shows the parent killed past the ceiling.

Also: the Windows clang-cl legs prefer Visual Studio's bundled clang-cl over a standalone LLVM, because the runner image's MSVC 14.52 STL requires Clang 22 or newer.
