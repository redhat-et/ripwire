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
