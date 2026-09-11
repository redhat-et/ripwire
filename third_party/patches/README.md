# third_party/patches — local patches to vendored code

Everything under `third_party/deps/` is vendored verbatim from upstream — except where a file in
this directory says otherwise. This directory is the complete, machine-checked record of every
local modification to vendored code. If a vendored file differs from upstream and no patch here
records it, that is a bug.

## The contract

1. **Where a patch lives.** One file per logical change:
   `third_party/patches/<dep>/<NNN-short-name>.patch`, where `<dep>` is the directory name under
   `third_party/deps/` (`swift`, `tree_sitter`, …) and `NNN` orders the patches for a dep. The
   patch is a git unified diff with repo-root-relative `a/` / `b/` paths — exactly what
   `git diff third_party/deps/<dep>/…` emits after making the edit in-tree.

2. **Every hunk carries a marker.** The added lines of each patch include a comment
   `RIPWIRE_VENDOR_PATCH(<dep>/<NNN-short-name>)` naming its own patch file. The marker is what
   makes the site findable after a re-vendor conflict, and the drift gate asserts it both in the
   patch and in the patched file on disk.

3. **The tree ships patched.** The fix is applied in `third_party/deps/` and committed; the patch
   file is the record, not a build step. Nothing at build time applies patches.

4. **How a patch survives a re-vendor/bump.** `test/vendorpatchcheck.sh` reverse-apply-checks
   every patch against the tree on every suite run. A bump that clobbers a patch turns the gate
   red the moment it lands. The re-vendorer then re-applies each of the dep's patches in order —
   `git apply third_party/patches/<dep>/NNN-*.patch` — resolves any drifted hunks by hand, and
   regenerates the patch file from the fresh diff (same name) if line numbers moved. If upstream
   fixed the issue, delete the patch file in the same commit and say so in the message.

5. **No orphans.** Removing a dep removes its patch directory in the same commit; the gate fails
   on a `third_party/patches/<dep>` with no living `third_party/deps/<dep>`, and on a patch whose
   target file is gone.

6. **Sanitizer exemptions are the sibling convention.** Suppressions for vendored code that is
   *correct by design* (defined unsigned wrap, deliberate quantization) do NOT get source patches;
   they live in the generated-ignorelist `file(WRITE …)` blocks in `CMakeLists.txt`, scoped to
   exact functions. The same gate polices them: every `fun:` entry must name a function that still
   exists under `third_party/deps/` — an entry that survives a bump while its function moves is
   how a real abort (subtree.c repeat_depth, 2026-08-11) hid behind a green suite. Patch the
   source only when the vendored code is genuinely wrong for our use (the Swift scanner's
   raw-string truncation, patch 001) — and prefer the ignorelist for tree-sitter core, which is
   upstream's arithmetic and churns on every bump.

## Current patches

| Patch | What it fixes |
| --- | --- |
| `swift/001-scanner-raw-str-lookahead-truncation.patch` | `eat_raw_str_part` stored the lexer's full `int32_t` lookahead codepoint into a `uint8_t` implicitly; any multi-byte UTF-8 (emoji) inside a raw `#"…"#` string aborted the G1 `-fsanitize=integer` stack (scanner.c:820). Explicit `(uint8_t)` cast — same value, same parse output, no `kParserVer` change. The identical cast was first carried un-conventioned on `feat/swift-shape-recall` (d2c95fe); this patch is that hunk adopted under the convention. |
| `yaml/001-serialize-bounds.patch` | `serialize()` wrote 2 × `int16` (4 bytes) per indent-stack entry behind the guard `size < TREE_SITTER_SERIALIZATION_BUFFER_SIZE`, which only proves 1 byte of headroom: with the 10-byte header, `size` reaches 1022 at 253 entries, passes, and writes bytes 1022–1025 of the 1024-byte buffer (`lexer.h` `debug_buffer`). Measured on v0.7.2: 253 block indent levels parse, 254 abort `ts_assert(length <= 1024)` (SIGABRT); under `NDEBUG` the assert is compiled out and the corrupting write is silent (observed SIGSEGV downstream). Guard becomes `size + 2 * sizeof(int16_t) <=` — same truncation-on-overflow semantics upstream already accepts, no parse-output change on any file under `kMaxYamlNestDepth`, no `kParserVer` change of its own. Defense-in-depth pair: ingest's `yamlNestsTooDeep` prescan refuses such files before any parse; vendorpatchcheck arm H audits the whole defect class across every vendored scanner. Not yet filed upstream (owner's call). |
| `markdown/001-serialize-bounds.patch` | `serialize()` memcpys `open_blocks.size * sizeof(Block)` bytes after a 5-byte header with NO bounds check at all against the 1024-byte serialization buffer — the yaml/001 defect class, minus even the bare guard. Measured on v0.5.3 standalone (2026-08-12): 300 nested blockquote markers, or 300 `- ` list markers on ONE line, abort `ts_assert(length <= 1024)` (SIGABRT rc=134); under `NDEBUG` the write corrupts the heap silently. The write is clamped UP FRONT to what fits (`max_blocks`) — truncation-on-overflow, the semantics the yaml patch established; no parse-output change on any file under ingest's `mdNestsTooDeep` guard, which refuses such files before any parse (the same defense-in-depth pair). Classified `upfront` in vendorpatchcheck arm H. Not yet filed upstream (owner's call). |
| `yaml/002-cursor-wrap-explicit.patch` | `cur_col`/`cur_row` are `int16_t` and the four `++` sites in `adv`/`adv_nwl`/`skp`/`skp_nwl` promote to `int` then store back — an implicit truncating conversion the moment a line exceeds 32 767 characters or a file 32 767 lines. Found at corpus scale, not by inspection: the G1 `-fsanitize=implicit-conversion` run over the 90-repo breadth corpus aborted on real 228 279-character lines (VCR-cassette test fixtures, under the 512 KB ceiling). Explicit `(int16_t)` casts — the exact wrapped value upstream production builds already compute, verified **byte-identical map output** on all 4 424 corpus files before vs after. Same class and same remedy as `swift/001`. Not yet filed upstream (owner's call). |
| `markdown/002-counter-saturate.patch` | Every counter this scanner accumulates into is a `uint8_t` fed from `advance()`'s `size_t`; past 255 that is an implicit truncation and G1 is `-fno-sanitize-recover=all`, so it aborts (rc=134). Found 2026-09-09 on `rails/guides/source/getting_started.md`, a pipe-table row padded to 301 columns — 64 tabs also reach it, since `advance()` charges a tab at tab stop 4. **Saturates, does not cast.** Both the indentation counters and `parse_fenced_code_block`'s `level` are read by ordering tests against a *fixed* threshold (`>= 4`, `< 4`, `< list_item_indentation` max 17; `>= 3` before a fence may open), so 255 answers exactly as any larger true value would. Wrapping inverted those predicates inside a narrow window — measured `N=255` correct, `N=256/257` **wrong at exit 0**, `N=300` correct again by luck — where an indented code block became a heading and a fence never opened, leaking its body out as live markdown. `counter_saturating_add` and the semantics argument come from the parallel lane on `claude/amazing-wescoff-181432`. Four sites are deliberately left bare with bounds proofs (guards `< 4`, `< list_item_indentation`, and `advance( … ) - 1` onto a zeroed counter), to keep the re-vendor diff small. `kParserVer` 86 → 87. Live tripwire: `vendorpatchcheck` arm I, whose plain-build half asserts the phantom headings are ABSENT — verified to go red against a fully reverted binary. Not yet filed upstream (owner's call). |
| `rust/001-delimiter-count-cast.patch` | `scan_raw_string_start`'s `opening_hash_count` is a `uint8_t` and `++` promotes to `int` before storing back — implicit truncation on a raw string opened with ≥ 256 hashes (`r###…#"x"#…###`). rustc rejects that, but a file on disk can carry it, and G1 aborts at scanner.c:77. Explicit cast: the exact value upstream production builds compute, byte-identical output, no `kParserVer` contribution. Live tripwire: `vendorpatchcheck` arm I. Not yet filed upstream (owner's call). |
| `lua/001-delimiter-count-cast.patch` | `consume_and_count_char`'s `count` is a `uint8_t` and `++count` promotes to `int` before storing back — implicit truncation on a long bracket opened with ≥ 256 `=` (`[===…[ … ]===…]`). G1 aborts at scanner.c:32. Same cast remedy, byte-identical output. Live tripwire: `vendorpatchcheck` arm I. Not yet filed upstream (owner's call). |
| `csharp/001-delimiter-count-cast.patch` | `dollar_advanced` is a `uint8_t` and `++` promotes to `int` before storing back — implicit truncation on ≥ 256 leading `$` before an interpolated string. G1 aborts at scanner.c:205. Same cast remedy, byte-identical output. Live tripwire: `vendorpatchcheck` arm I. Not yet filed upstream (owner's call). |


## A limit the delimiter-count patches do NOT remove

`rust/001`, `lua/001` and `csharp/001` make an overflowing delimiter counter **defined**, which is what G1 asks for. They do not make the token *parse*. A raw
string opened with 300 hashes, a long bracket opened with 300 `=`, or a fence opened with 300
or 300 `$` before an interpolation is not representable in a `uint8_t` counter, and closing such a
token requires matching the opening count — so it is mis-parsed under upstream's wrap, under an
explicit cast, and under saturation alike. Measured: at 255, 256, 257 and 300 the symbols after the
token are recovered identically in all three cases, so there is no extraction difference to fix and
saturation would only be a different wrong answer that looks like a repair. That is why these three
keep the cast — and why markdown's fence `level`, whose `>= 3` open test *is* a fixed threshold and
*does* change the parse, does not.

Widening the vendored counters was considered and not attempted: `indentation`, `column` and
`fenced_code_block_delimiter_length` are each written as a single byte by markdown's `serialize()`,
and the equivalents in the other three scanners likewise, so the width is part of upstream's own
wire format rather than an implementation detail we can change locally. A patch that widened them
would have to rewrite `serialize`/`deserialize` in lockstep and would conflict with every upstream
bump. If this ever matters for a real corpus — no file in 3 538 measured carries such a token — the
fix belongs upstream, not here.
