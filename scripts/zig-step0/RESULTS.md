# Zig STEP 0 — grammar pin measurement

Issue [#166](https://github.com/redhat-et/ripwire/issues/166). This is the
parse-rate measurement only. The grammar is not vendored, and nothing is extracted.

## Method

Both documented pins of [tree-sitter-grammars/tree-sitter-zig](https://github.com/tree-sitter-grammars/tree-sitter-zig)
were linked against the vendored tree-sitter core (`TREE_SITTER_LANGUAGE_VERSION` 15,
minimum compatible 13) and run on the same files.

| pin | commit | ABI | what changed since v1.1.2 |
| --- | --- | --- | --- |
| `v1.1.2` | `b670c8df85a1568f498aa5c8cae42f51a90473c0` | 14 | tagged pin, 2024-12-22 |
| `6479aa13` | `6479aa13f32f701c383083d8b28360ebd682fb7d` | 15 | documented `master` pin, 2025-09-10 |

`grammar.js` between those commits moves a call's argument list into an `arguments`
rule, `seq('(', optionalCommaSep($.expression), ')')`, which is the same sequence the
old `call_expression` inlined. Both grammars still contain `usingnamespace`, `async`,
and `await`. `parser.c` was regenerated. Neither pin has an external scanner.
`6479aa13` is not current `master`; it is the commit the issue names.

For each file the harness records the two numbers from `prompts/help-wanted/zig-language.md`,
counted the way `measureFileHealth` in `src/ingest_crawl.h` counts them:

- clean means `ts_node_has_error(root)` is false;
- the ERROR-byte share is the sum of the top-most ERROR spans. Nested recovery
  nodes are not added again. A MISSING node makes the file not clean and adds no bytes.

A file that does not finish within 10 seconds is a timeout. Timeouts are not clean
and are left out of the byte ratio. Files over 64 MiB would be `too_big` and were
not seen. `.zon` files are not part of this measurement.

## Corpora

The standard library is `lib/std.zig` plus `lib/std/` at a release tag. A sparse
checkout of `lib/std` also keeps files that sit directly in `lib/`
(`c.zig`, `compiler_rt.zig`, `fuzzer.zig`, `ubsan_rt.zig`) and the root `build.zig`.
Those extra files are in the totals. The same commit is on Codeberg and on the
GitHub mirror. Ghostty
is every tracked `.zig` file at a release whose `build.zig.zon` names the Zig
version. Ghostty 1.3.1 asks for 0.15.2; the 0.15 standard library measured here is
0.15.1, the release named in the grammar pin's corpus bump. 0.15.2 is a bugfix
on that language.

| corpus | Zig | commit | files |
| --- | --- | --- | --- |
| zig-std-0.14.1 | 0.14.1 | `d03a147ea0a590ca711b3db07106effc559b0fc6` | 570 |
| zig-std-0.15.1 | 0.15.1 | `3db960767d12b6214bcf43f1966a037c7a586a12` | 545 |
| ghostty-1.2.3 | 0.14.1 | `6d2dd585a5d87fa745d48188dd096ca6e63014d0` | 540 |
| ghostty-1.3.1 | 0.15.2 | `332b2aefc6e72d363aa93ab6ecfc86eeeeb5ed28` | 638 |

Dialect keywords present anywhere in a corpus (a file is counted once per word).
This is the corpus, not the parser: it says whether the 0.14-era keywords are still
in the tree.

| corpus | usingnamespace | async | await | suspend | resume | nosuspend | anyframe |
| --- | --- | --- | --- | --- | --- | --- | --- |
| zig-std-0.14.1 | 9 | 16 | 9 | 14 | 10 | 12 | 15 |
| zig-std-0.15.1 | 0 | 14 | 0 | 14 | 11 | 12 | 15 |
| ghostty-1.2.3 | 0 | 6 | 0 | 0 | 0 | 3 | 0 |
| ghostty-1.3.1 | 0 | 9 | 0 | 0 | 1 | 3 | 0 |

## Results

Clean % is clean files / files that finished. ERROR % is top-most ERROR bytes / bytes
in files that finished. `zero-width` is a finished file with an error flag and
no ERROR bytes: a MISSING token, or a node whose error cost is neither.

| corpus | pin | files | clean | clean % | ERROR bytes | file bytes | ERROR % | zero-width | timeout |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| zig-std-0.14.1 | `v1.1.2` | 570 | 543/570 | 95.26% | 0 | 14635297 | 0.000% | 27 | 0 |
| zig-std-0.14.1 | `6479aa13` | 570 | 543/570 | 95.26% | 0 | 14635297 | 0.000% | 27 | 0 |
| zig-std-0.15.1 | `v1.1.2` | 545 | 492/545 | 90.28% | 18187 | 15161816 | 0.120% | 25 | 0 |
| zig-std-0.15.1 | `6479aa13` | 545 | 492/545 | 90.28% | 18187 | 15161816 | 0.120% | 25 | 0 |
| ghostty-1.2.3 | `v1.1.2` | 540 | 523/540 | 96.85% | 30 | 6491318 | 0.000% | 16 | 0 |
| ghostty-1.2.3 | `6479aa13` | 540 | 523/540 | 96.85% | 30 | 6491318 | 0.000% | 16 | 0 |
| ghostty-1.3.1 | `v1.1.2` | 638 | 617/638 | 96.71% | 30 | 8391390 | 0.000% | 20 | 0 |
| ghostty-1.3.1 | `6479aa13` | 638 | 617/638 | 96.71% | 30 | 8391390 | 0.000% | 20 | 0 |

Pooled across the four corpora:

| pin | clean | clean % | ERROR bytes | file bytes | ERROR % | timeout |
| --- | --- | --- | --- | --- | --- | --- |
| `v1.1.2` | 2175/2293 | 94.85% | 18247 | 44679821 | 0.041% | 0 |
| `6479aa13` | 2175/2293 | 94.85% | 18247 | 44679821 | 0.041% | 0 |

## Where the pins differ

`zig-std-0.14.1`: 0 file(s) differ in status or ERROR bytes.
`zig-std-0.15.1`: 0 file(s) differ in status or ERROR bytes.
`ghostty-1.2.3`: 0 file(s) differ in status or ERROR bytes.
`ghostty-1.3.1`: 0 file(s) differ in status or ERROR bytes.

No file changed status or ERROR-byte count between the pins.

## Representative failures

The pins agreed on every file, so each corpus is shown once.
A pattern is the start of the first top-most ERROR span. A file with an error
flag and no ERROR bytes is `MISSING <token>` or `cost <type>` (a zero-width node
whose error cost is neither an ERROR nor a MISSING node). Identifiers and numbers
are folded. The byte table is only files that contain ERROR bytes.

### zig-std-0.14.1

| files | pattern | example |
| --- | --- | --- |
| 25 | `cost identifier` | `lib/std/Target/lanai.zig:7` `pub const Feature = enum {};` |
| 2 | `MISSING ..` | `lib/std/zon/parse.zig:1219` `try std.testing.expect(!comptime canParseType(struct { error{foo} }));` |

Zero-width `cost identifier` rows: 25. Lines containing an empty container: `struct {}` × 13, `enum {}` × 3, `opaque {}` × 9.

No ERROR bytes in this corpus.

### zig-std-0.15.1

Dialect keywords inside the first top-most ERROR span:

| keyword | files |
| --- | --- |
| `async` | 1 |

| files | pattern | example |
| --- | --- | --- |
| 23 | `cost identifier` | `lib/std/Build/Watch/FsEvents.zig:399` `const dispatch_semaphore_t = *opaque {};` |
| 10 | `: [ID] ID (-> ID), : [ID] ID (@ID(ID)), : .{` | `lib/std/os/linux/aarch64.zig:19` |
| 2 | `.{ .ID = true }` | `lib/std/Thread.zig:1192` |
| 2 | `: : [ID] ID (ID), : .{` | `lib/std/mem.zig:4499` |
| 2 | `\\ ID \\ ID+ NID \\ ID N, N \\ N: : [ID] ID (-> ID), : [ID] "{ID}` | `lib/std/os/linux/powerpc.zig:19` |
| 2 | `MISSING ..` | `lib/std/zon/Serializer.zig:890` `try std.testing.expect(!comptime canSerializeType(struct { error{foo} }));` |
| 1 | `,` | `lib/std/builtin.zig:197` |
| 1 | `::: .{` | `lib/std/debug.zig:795` |

Zero-width `cost identifier` rows: 23. Lines containing an empty container: `struct {}` × 9, `enum {}` × 4, `opaque {}` × 10.

| ERROR bytes | file bytes | file | line | span |
| --- | --- | --- | --- | --- |
| 2053 | 13489 | `lib/std/os/linux/x86_64.zig` | 20 | `"syscall" : [ret] "={rax}" (-> usize), : [number] "{rax}" (@intFromEnum(number)), : .` |
| 1811 | 10635 | `lib/std/os/linux/mips64.zig` | 22 | `: [ret] "={$2}" (-> usize), : [number] "{$2}" (@intFromEnum(number)), : .{` |
| 1808 | 11254 | `lib/std/os/linux/mips.zig` | 22 | `: [ret] "={$2}" (-> usize), : [number] "{$2}" (@intFromEnum(number)), : .{` |
| 1675 | 7941 | `lib/std/os/linux/loongarch64.zig` | 17 | `\\ syscall 0 : [ret] "={$r4}" (-> usize), : [number] "{$r11}" (@intFromEnum(number)), : .` |
| 1556 | 8845 | `lib/std/os/linux/powerpc.zig` | 19 | `\\ sc \\ bns+ 1f \\ neg 3, 3 \\ 1: : [ret] "={r3}" (-> usize), : [number] "{r0}` |
| 1556 | 8837 | `lib/std/os/linux/powerpc64.zig` | 19 | `\\ sc \\ bns+ 1f \\ neg 3, 3 \\ 1: : [ret] "={r3}" (-> usize), : [number] "{r0}` |
| 1132 | 12292 | `lib/std/valgrind.zig` | 17 | `: [_] "={r3}" (-> usize), : [_] "{r4}" (args), [_] "{r3}" (default), : .{` |
| 1065 | 10847 | `lib/std/os/linux/sparc64.zig` | 32 | `: [ret] "={o0}" (-> usize), : [number] "{g1}" (@intFromEnum(SYS.pipe)), [arg] "r" (fd), : .{` |

### ghostty-1.2.3

| files | pattern | example |
| --- | --- | --- |
| 16 | `cost identifier` | `src/App.zig:578` `pub const Wasm = if (!builtin.target.isWasm()) struct {} else struct {` |
| 1 | `: { ID` | `src/Surface.zig:815` |

Zero-width `cost identifier` rows: 16. Lines containing an empty container: `struct {}` × 15, `opaque {}` × 1.

| ERROR bytes | file bytes | file | line | span |
| --- | --- | --- | --- | --- |
| 30 | 212021 | `src/Surface.zig` | 815 | `: { self` |

### ghostty-1.3.1

| files | pattern | example |
| --- | --- | --- |
| 20 | `cost identifier` | `src/App.zig:588` `pub const Wasm = if (!builtin.target.isWasm()) struct {} else struct {` |
| 1 | `: { ID` | `src/Surface.zig:935` |

Zero-width `cost identifier` rows: 20. Lines containing an empty container: `struct {}` × 19, `opaque {}` × 1.

| ERROR bytes | file bytes | file | line | span |
| --- | --- | --- | --- | --- |
| 30 | 243367 | `src/Surface.zig` | 935 | `: { self` |

## Directories

ERROR-byte share by the first path component, using `v1.1.2`. The other pin
matches these totals. `pkg/` is Ghostty's in-tree Zig packages, not a second
dialect hidden under `src/`.

### zig-std-0.14.1

| directory | files | clean % | ERROR % |
| --- | --- | --- | --- |
| `build.zig` | 1 | 100.00% | 0.000% |
| `lib` | 569 | 95.25% | 0.000% |

### zig-std-0.15.1

| directory | files | clean % | ERROR % |
| --- | --- | --- | --- |
| `build.zig` | 1 | 100.00% | 0.000% |
| `lib` | 544 | 90.26% | 0.120% |

### ghostty-1.2.3

| directory | files | clean % | ERROR % |
| --- | --- | --- | --- |
| `build.zig` | 1 | 100.00% | 0.000% |
| `pkg` | 162 | 100.00% | 0.000% |
| `src` | 377 | 95.49% | 0.000% |

### ghostty-1.3.1

| directory | files | clean % | ERROR % |
| --- | --- | --- | --- |
| `build.zig` | 1 | 100.00% | 0.000% |
| `example` | 10 | 100.00% | 0.000% |
| `pkg` | 161 | 100.00% | 0.000% |
| `src` | 461 | 95.44% | 0.000% |
| `test` | 5 | 100.00% | 0.000% |

## Recommendation

The issue's rule is to pin the grammar that parses more of the same corpus: more
files with no error flag, then fewer top-most ERROR bytes. A tie stays on the
tagged commit, which is the house convention (`CMakeLists.txt` comments a tag
after the SHA; the Swift pin is the exception, and it says why).

The pins tie on every file, not only on the pooled totals. `6479aa13` does not
parse more. Pin **`v1.1.2`** (`b670c8df85a1568f498aa5c8cae42f51a90473c0`, ABI 14).

`prompts/add-a-language.md` calls 95% of a real corpus worth vendoring, and treats
a grammar that silently drops about half of a language as worse than no grammar.
The two numbers answer that separately. Clean-file rate is the strict one. ERROR
bytes are how much of a file the recovery actually lost.

- `zig-std-0.14.1`: 543/570 clean (95.26%); no ERROR bytes; 27 files flagged with zero ERROR bytes.
- `zig-std-0.15.1`: 492/545 clean (90.28%); ERROR bytes 18187 (0.120%) in 28 files; 25 files flagged with zero ERROR bytes.
- `ghostty-1.2.3`: 523/540 clean (96.85%); ERROR bytes 30 (0.000%) in 1 file; 16 files flagged with zero ERROR bytes.
- `ghostty-1.3.1`: 617/638 clean (96.71%); ERROR bytes 30 (0.000%) in 1 file; 20 files flagged with zero ERROR bytes.

`zig-std-0.15.1` is the cell under 95% clean. It is not a half-parsed library:
its ERROR bytes are 0.120% of that corpus,
and the other three corpora together hold 60 ERROR bytes. The shapes are
in the failure section. Vendoring can use the tagged pin. This step does not vendor
it and does not extract symbols; the issue asked for the table first.

## Not in this step

`@import` resolution, `.zon`, and Zig-to-C edges stay deferred, as agreed on the issue.
Nothing here binds `fs.openFile()` to a call. Extraction, vendoring, and `test/zigcheck.sh`
wait until this table is accepted.

Re-run with `scripts/zig-step0/run.sh`. The corpora and both grammar checkouts are
fetched into the cache directory the script prints; they are not part of the tree.
