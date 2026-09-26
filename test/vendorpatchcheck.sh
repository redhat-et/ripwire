#!/usr/bin/env bash
# vendorpatchcheck.sh — the vendored-patch convention + sanitizer-exemption drift gate.
#
# Nothing under third_party/deps/ is ours, but two kinds of local artifact ride on top of it and
# BOTH have already drifted silently in this repo's history:
#
#   1. Source patches to vendored files (first tenant: the Swift external scanner stored the
#      lexer's full int32 lookahead codepoint into a uint8 — implicit truncation, a hard G1 abort
#      on any emoji inside a raw #"…"# string; scanner.c:820). A grammar re-vendor/bump silently
#      clobbers such a fix: the build stays green and the abort comes back weeks later on a corpus.
#      Convention: every local edit to a vendored file lives as third_party/patches/<dep>/
#      <NNN-name>.patch (git unified diff from the repo root), each hunk carrying a
#      RIPWIRE_VENDOR_PATCH(<dep>/<NNN-name>) marker comment in its added lines, and this gate
#      re-verifies each patch against the tree on every run.
#   2. Sanitizer-ignorelist exemptions for vendored code (CMakeLists.txt file(WRITE …) blocks).
#      These name exact functions, and an entry can quietly rot into naming the WRONG function:
#      tree-sitter's `[implicit-unsigned-integer-truncation]` section exempted
#      ts_parser__balance_subtree while the live truncation sat in ts_subtree_summarize_children
#      (subtree.c:469, uint16 repeat_depth) — unguarded, aborting on ~66K-deep repeat chains
#      (large generated headers). So this gate checks the FAMILY: every fun: entry must name a
#      function that exists in the vendored tree, and the known abort site must be covered.
#
# Arms:
#   A  presence — third_party/patches/ exists with a README and at least one *.patch (the guard
#      that keeps arms B/C from passing green-while-inert over an empty set).
#   B  patch-applied — every patch reverse-apply-checks clean against the tree (a re-vendor that
#      dropped a patch turns this red), and its RIPWIRE_VENDOR_PATCH marker is present both in
#      the patch's added lines and in the patched file on disk.
#   C  no orphans — every path a patch touches exists, and every third_party/patches/<dep> has a
#      living third_party/deps/<dep> (dep removed → its patches must go too).
#   D  ignorelist validity — every `fun:` entry in CMakeLists.txt's generated sanitizer
#      ignorelists names a function defined somewhere under third_party/deps/.
#   E  ignorelist coverage pin — the tree-sitter `[implicit-unsigned-integer-truncation]` section
#      names ts_subtree_summarize_children (the repeat_depth truncation site), not merely its
#      historical neighbor.
#   F  swift fixture parses — $BIN on test/vendorpatchfix (emoji inside raw #"…"# strings) exits 0
#      with well-formed output. Under the asan flavour this arm IS the live sanitizer tripwire
#      for the scanner patch.
#   G  deep-repeat parses — a generated 70 001-element C initializer (repeat_depth > 65 535)
#      parses clean. Under the asan flavour this arm is the live tripwire for arm E's exemption.
#   H  serialize() write-width family audit — every vendored scanner referencing
#      TREE_SITTER_SERIALIZATION_BUFFER_SIZE is classified (upfront/static/loop1/loopwide) and its
#      class's proof obligation checked; an unclassified scanner fails loudly. This is the yaml
#      OOB write's whole DEFECT CLASS (a per-iteration guard narrower than the widest write in its
#      loop), caught statically for the next grammar too. The live runtime tripwire for the yaml
#      patch itself is yamllangcheck's deep-indent arm.
#   I  narrow-counter family — test/vendorwrapfix, one fixture file per grammar so a reverted patch
#      turns exactly one file red. TWO independent halves, because the two damage windows differ.
#      The exit code is the sanitizer tripwire (asan only) and fires at every width >= 256. The
#      SEMANTIC assertions are what hold on the plain build, where a revert is an exit-0 wrong
#      answer rather than a crash: four ATX lines that must NOT be minted as headings — buried under
#      256 spaces, under 64 tabs (advance() charges a tab at tab stop 4), and inside a 256-tilde
#      fence; the list-continuation line drives the soft-line-ending site for the ABORT arm only,
#      because it mints no phantom either way. Widths are pinned at
#      EXACTLY 256 and gated as ==, because the wrong parse only fires while the wrapped value lands
#      under the threshold tested (N mod 256 in 0..3) — at a round 300 the parse is accidentally
#      correct and every plain-build assertion here would go inert while asan stayed green.
#   J  kotlin/001 + kotlin/002. kotlin/001: tree-sitter-kotlin's stack_push abort()ed the process when
#      nested interpolated strings overran the delimiter stack's TREE_SITTER_SERIALIZATION_BUFFER_SIZE
#      budget (512 open strings) — a DELIBERATE abort(), not UB, so no sanitizer catches it and no
#      corpus/fuzz sweep found it. Three halves: a STATIC shape audit (no abort() left on the string-stack
#      path — stack_push / stack_pop / scan_string_start — and both string-start shapes return the push's
#      verdict); the default map over 700 nested string-opens, generated fresh like arm G, must exit 0
#      well-formed; and a RUNTIME half over a 600-deep file. Before #157, ingest's kotlinStringsNestTooDeep
#      prescan refused such a file before any parse for the default map, but --match's structural-query
#      pass had no nesting guard and handed the scanner the file directly — the RUNTIME half used to be a
#      --match run for exactly that reason. #157 closed that gap (every ripwire verb now applies the same
#      refusal, via IngestResult::nestRefusedFile), so no CLI verb can reach this scanner path anymore; the
#      runtime half is now a standalone harness that links the vendored kotlin grammar straight to a
#      tree-sitter core build and calls it directly, bypassing ripwire entirely (kotlincheck §12 is the
#      runtime arm for the prescan itself, on the CLI side). kotlin/002: the plain-build exit-0
#      mis-tokenization from an escaped `$` right before a triple-quoted string's closing delimiter
#      (test/vendorpatchfix/tripledollar.kt, committed like arm F's fixture) — checked via
#      degraded_parse=0 and that the symbol declared right after the tricky string still extracts.
#      kotlin/003: arm I's narrow-counter class at uint16_t — a run of 65,536 `$` inside a string truncates
#      `additional_dollars`. A static check that the saturation guard is in the counting loop, and a
#      generated 65,537-`$` run (closed by a quote, so the scan stays linear) that is the ASan tripwire.
#   K  the yaml scanner under an UNSIGNED char — `char` is unsigned on aarch64 Linux (the linux-arm64
#      release asset), where tree-sitter-yaml's SCN_FAIL (-1), returned through `static char`
#      functions, becomes 255: a malformed %-escape in a tag parses differently, and G1's
#      implicit-conversion check aborts on every `key: value` line. Neither CI leg has an unsigned
#      char, so this arm does not use $BIN: it compiles the vendored grammar itself, -fsigned-char and
#      -funsigned-char, and requires identical trees, plus a clean -funsigned-char sanitizer run.
#   L  tree_sitter/001 — ts_query__parse_pattern returned TSQueryErrorField without deleting the capture
#      quantifiers it had just parsed for that field's sub-pattern. A structural query is compiled against
#      every linked grammar (--match's grammar disclosure probes them all), so one naming a field some
#      grammar lacks, over a capturing sub-pattern, leaked 16 bytes per such grammar. LeakSanitizer turns
#      that into an abort at exit: the Linux ASan leg died with SIGABRT running crashsweepcheck's S2 query
#      `right: (unary_expression argument: (call_expression … @c))`. A leak detector is the only way to see
#      it, so the arm uses what the host has. On a sanitizer binary with LeakSanitizer (Linux), the run's
#      exit code decides. On macOS it runs the plain binary under `leaks --atExit`, which reported
#      "1 leak for 16 total leaked bytes" on the unpatched build and 0 on the patched one, with a
#      field-free control query that must report 0 on both. Anywhere else it SKIPs by name.
#   M  `1UL <<` shift-width family audit (static, $BIN-independent) — first tenant: swift/002.
#      `1UL` is `unsigned long`, 32 bits on LLP64 (Windows); shifting it by an enumerator whose
#      ordinal is >= 32 (swift's OP_SYMBOL_SUPPRESSOR table, FAKE_TRY_BANG = 32) is undefined
#      behaviour there, even though it is well-defined on every LP64 host this repo is built and
#      tested on — so the bug is invisible locally and on Linux/macOS CI alike. This scans every
#      vendored `.c`/`.h` file for a bare `1UL << IDENT` (or `1UL << N`), in every spelling of a
#      `long` literal (`1UL`/`1ul`/`1LU`/`1lu`/… unsigned, `1L`/`1l` signed; not `1ULL`/`1LL`, 64 bits
#      everywhere), resolves IDENT's ordinal from the nearest enclosing `enum { … }` in the same file
#      (explicit `= N` members reset the count), and fails on any unsigned shift >= 32 or signed shift
#      >= 31 (a signed 32-bit `1L << 31` overflows into the sign bit, undefined in C); a shift whose
#      operand cannot be resolved statically fails loudly too (H's "unclassified fails loudly"
#      convention), rather than passing while unproven. A re-vendor that reintroduces this shape in
#      any grammar — not just swift — turns this arm red the moment it lands, before it ever reaches
#      a Windows build.
#
# Usage:
#   test/vendorpatchcheck.sh
#   RIPWIRE_BIN=asan/ripwire test/vendorpatchcheck.sh
#
# Exits non-zero on any failure; prints PASS/FAIL per check and ALL PASS on success.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
PATCH_DIR="$ROOT/third_party/patches"
DEPS_DIR="$ROOT/third_party/deps"
FIX="$ROOT/test/vendorpatchfix"
WRAPFIX="$ROOT/test/vendorwrapfix"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0

ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }
skip(){ printf '  SKIP  %s\n' "$*"; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
command -v git >/dev/null 2>&1 || { echo "git required for patch reverse-apply checks"; exit 2; }
command -v xmllint >/dev/null 2>&1 || { echo "xmllint required for well-formedness assertions"; exit 2; }

# ── A: presence — the convention must actually be populated ─────────────────────────────────────
patchCount=0
if [ -d "$PATCH_DIR" ] && [ -f "$PATCH_DIR/README.md" ]; then
    patchCount="$( find "$PATCH_DIR" -type f -name '*.patch' | wc -l | tr -d ' ' )"
fi
if [ "$patchCount" -ge 1 ]; then
    ok "A: third_party/patches/ exists with README.md and $patchCount patch(es)"
else
    no "A: third_party/patches/ missing, README-less, or empty — the vendored-patch convention is not established"
fi

# ── B: every patch is still carried by the tree, marker included ────────────────────────────────
while IFS= read -r patchPath; do
    patchRel="${patchPath#"$ROOT/"}"
    stem="$( basename "$patchPath" .patch )"
    dep="$( basename "$( dirname "$patchPath" )" )"
    if git -C "$ROOT" apply --reverse --check "$patchPath" >/dev/null 2>&1; then
        ok "B: $patchRel reverse-apply-checks clean (tree carries the patch)"
    else
        no "B: $patchRel does NOT reverse-apply — a re-vendor/bump dropped the patch; re-apply it with: git apply $patchRel"
    fi
    marker="RIPWIRE_VENDOR_PATCH($dep/$stem)"
    if grep -E "^\+" "$patchPath" | grep -F -q "$marker"; then
        ok "B: $patchRel added lines carry marker $marker"
    else
        no "B: $patchRel has no $marker in its added lines — unfindable after a re-vendor conflict"
    fi
    markerHits=0
    while IFS= read -r touchedRel; do
        if [ -f "$ROOT/$touchedRel" ] && grep -F -q "$marker" "$ROOT/$touchedRel"; then
            markerHits=$(( markerHits + 1 ))
        fi
    done < <( grep -E '^\+\+\+ b/' "$patchPath" | sed 's|^+++ b/||' )
    if [ "$markerHits" -ge 1 ]; then
        ok "B: marker $marker present in the patched file(s) on disk"
    else
        no "B: marker $marker absent from every file $patchRel touches — the patch is not in the tree"
    fi
done < <( find "$PATCH_DIR" -type f -name '*.patch' 2>/dev/null | LC_ALL=C sort )

# ── C: no orphans in either direction ───────────────────────────────────────────────────────────
while IFS= read -r patchPath; do
    patchRel="${patchPath#"$ROOT/"}"
    while IFS= read -r touchedRel; do
        if [ -f "$ROOT/$touchedRel" ]; then
            ok "C: $patchRel target $touchedRel exists"
        else
            no "C: $patchRel targets $touchedRel which is gone — orphaned patch (dep removed or file renamed)"
        fi
    done < <( grep -E '^\+\+\+ b/' "$patchPath" | sed 's|^+++ b/||' )
done < <( find "$PATCH_DIR" -type f -name '*.patch' 2>/dev/null | LC_ALL=C sort )
while IFS= read -r depPatchDir; do
    dep="$( basename "$depPatchDir" )"
    if [ -d "$DEPS_DIR/$dep" ]; then
        ok "C: third_party/patches/$dep has a living third_party/deps/$dep"
    else
        no "C: third_party/patches/$dep is orphaned — no third_party/deps/$dep in the tree"
    fi
done < <( find "$PATCH_DIR" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | LC_ALL=C sort )

# ── D: every fun: ignorelist entry names a function that exists under third_party/deps/ ─────────
# The ignorelists are generated by file(WRITE …) in CMakeLists.txt; the fun: names inside those
# string literals are the source of truth. Presence guard first: finding ZERO entries means the
# extraction regex rotted, not that the tree is clean.
grep -oE 'fun:[A-Za-z0-9_]+' "$ROOT/CMakeLists.txt" | sed 's/^fun://' | LC_ALL=C sort -u > "$TMP/funs"
if [ -s "$TMP/funs" ]; then
    ok "D: presence — $( wc -l < "$TMP/funs" | tr -d ' ' ) fun: ignorelist entries extracted from CMakeLists.txt"
else
    no "D: presence — extracted ZERO fun: entries from CMakeLists.txt (extraction rot, or the ignorelists moved)"
fi
while IFS= read -r fn; do
    if grep -rE "(^|[^A-Za-z0-9_])${fn}[[:space:]]*\(" "$DEPS_DIR" --include='*.c' --include='*.h' -l | head -1 | grep -q .; then
        ok "D: ignorelist fun:$fn is defined under third_party/deps/"
    else
        no "D: ignorelist fun:$fn matches NOTHING under third_party/deps/ — stale exemption (function renamed or dep bumped)"
    fi
done < "$TMP/funs"

# ── E: the tree-sitter truncation exemption covers the real site ────────────────────────────────
# Scope the assertion to the tree_sitter ignorelist's file(WRITE …) block so a same-spelled entry
# in another dep's list can never satisfy it.
tsBlock="$( awk '/file\(WRITE "\$\{_ripwire_tree_sitter_ignorelist\}"/ { f = 1 } f { print; if( /\)$/ ) { exit } }' "$ROOT/CMakeLists.txt" )"
if printf '%s' "$tsBlock" | grep -q 'implicit-unsigned-integer-truncation'; then
    ok "E: presence — located the tree_sitter [implicit-unsigned-integer-truncation] ignorelist block"
else
    no "E: presence — cannot locate the tree_sitter [implicit-unsigned-integer-truncation] block in CMakeLists.txt"
fi
if printf '%s' "$tsBlock" | grep -q 'fun:ts_subtree_summarize_children'; then
    ok "E: tree_sitter ignorelist exempts ts_subtree_summarize_children (the uint16 repeat_depth site)"
else
    no "E: tree_sitter ignorelist does NOT exempt ts_subtree_summarize_children — repeat_depth > 65535 aborts the G1 stack"
fi
if grep -q 'void ts_subtree_summarize_children' "$DEPS_DIR/tree_sitter/lib/src/subtree.c"; then
    ok "E: ts_subtree_summarize_children still defined in vendored subtree.c"
else
    no "E: ts_subtree_summarize_children no longer defined in vendored subtree.c — re-audit the exemption"
fi

# ── F: the swift emoji-in-raw-string fixture parses (asan flavour: the live tripwire) ───────────
if [ -f "$FIX/emojiraw.swift" ] && LC_ALL=C grep -q $'\xf0\x9f' "$FIX/emojiraw.swift"; then
    ok "F: presence — fixture exists and carries 4-byte UTF-8 inside it"
else
    no "F: presence — test/vendorpatchfix/emojiraw.swift missing or emoji-less (arm would pass while inert)"
fi
if "$BIN" "$FIX" --no-cache > "$TMP/swift.xml" 2> "$TMP/swift.err"; then
    if xmllint --noout "$TMP/swift.xml" 2>/dev/null && grep -q 'rawStringWithEmoji' "$TMP/swift.xml"; then
        ok "F: swift raw-string fixture parses clean, well-formed, symbol extracted"
    else
        no "F: swift fixture ran but output is malformed or rawStringWithEmoji was not extracted"
    fi
else
    no "F: ripwire ABORTED on emoji inside a raw #\"…\"# string (rc=$?) — the vendored scanner patch is not in effect"
    head -3 "$TMP/swift.err" | sed 's/^/        /'
fi

# ── G: a >65535-deep repeat chain parses (asan flavour: the live tripwire for arm E) ────────────
mkdir -p "$TMP/deeprepeat"
python3 - "$TMP/deeprepeat/bigtable.h" <<'PYEOF'
import sys
with open( sys.argv[1], 'w' ) as f:
    f.write( 'static const int kBigTable[] = {' + ','.join( '1' for _ in range( 70001 ) ) + '};\n' )
PYEOF
if [ "$( wc -c < "$TMP/deeprepeat/bigtable.h" )" -gt 100000 ]; then
    ok "G: presence — generated deep-repeat header ($( wc -c < "$TMP/deeprepeat/bigtable.h" | tr -d ' ' ) bytes)"
else
    no "G: presence — deep-repeat header generation failed"
fi
if "$BIN" "$TMP/deeprepeat" --no-cache > "$TMP/deep.xml" 2> "$TMP/deep.err"; then
    if xmllint --noout "$TMP/deep.xml" 2>/dev/null; then
        ok "G: 70001-element initializer (repeat_depth > 65535) parses clean and well-formed"
    else
        no "G: deep-repeat parse ran but produced malformed output"
    fi
else
    no "G: ripwire ABORTED on a >65535-deep repeat chain (rc=$?) — the summarize_children exemption is not in effect"
    head -3 "$TMP/deep.err" | sed 's/^/        /'
fi

# ── H: serialize() write-width family audit — the yaml OOB's whole CLASS, next grammar included ──
# tree-sitter-yaml's serialize() wrote 4 bytes per iteration behind a loop guard that only proved 1
# byte of headroom (patch yaml/001-serialize-bounds; SIGABRT at ~254 block indent levels, silent
# corruption under NDEBUG). That defect SHAPE — a per-iteration guard narrower than the widest write
# in its loop body — is auditable statically for EVERY vendored scanner, including one not vendored
# yet: each scanner.c that references TREE_SITTER_SERIALIZATION_BUFFER_SIZE must be CLASSIFIED below
# (enumerated-not-globbed, the dependencypincheck posture: an unclassified scanner fails loudly and
# the classification IS the review), and each class carries a checkable proof obligation:
#   upfront  — whole-write bounds check before any write (bash, csharp, ruby)
#   static   — compile-time static_assert against the buffer size (cpp, cuda)
#   loop1    — per-iteration guard `size < BUFFER` writing exactly 1 byte/iteration (python):
#              the bare guard proves exactly enough, so it must stay paired with 1-byte writes
#   loopwide — per-iteration guard writing >1 byte/iteration (yaml): the bare `size < BUFFER` form
#              is the defect; the guard MUST carry explicit headroom for the full iteration
serializeClassOf(){
    case "$1" in
        bash|csharp|ruby) echo upfront ;;
        markdown)         echo upfront ;;  # patch 001-serialize-bounds: whole-write clamp BEFORE the
                                           # memcpy (upstream had NO guard at all — the yaml class,
                                           # minus even the bare per-iteration check)
        kotlin)           echo upfront ;;  # `n = stack->size; if (n > BUFFER_SIZE) n = BUFFER_SIZE;`
                                           # THEN one memcpy(buffer, contents, n) — upstream's own
                                           # whole-write clamp, so the WRITE needs no patch. The stack
                                           # that feeds it was NOT harmless: upstream's stack_push
                                           # bounded it with `abort()`, which killed the whole process
                                           # on 512 nested string templates in one .kt file (rc=134,
                                           # no output). That is kotlin/001, and arm J, not this arm,
                                           # is what keeps it from coming back.
        cpp|cuda)         echo static ;;
        python)           echo loop1 ;;
        # gdscript: AUDITED against python's, which its scanner is derived from — the two serialize()
        # bodies are structurally identical. Prefix: a delimiter_count clamped to UINT8_MAX then an
        # UNGUARDED memcpy of that many bytes, so the pre-loop write is at most 1 + 255 = 256 against a
        # 1024-byte buffer (python's is 257: it writes inside_f_string first). Bounded by the clamp, not
        # by a buffer check — the same accepted shape as python's. Indent loop: bare
        # `size < BUFFER_SIZE` guard paired with a 1-byte `buffer[size++]` write, which is exactly what
        # loop1 asserts must stay paired.
        gdscript)         echo loop1 ;;
        yaml)             echo loopwide ;;
        *)                echo unknown ;;
    esac
}
serCount=0
while IFS= read -r scannerPath; do
    dep="$( basename "$( dirname "$( dirname "$scannerPath" )" )" )"
    serCount=$(( serCount + 1 ))
    cls="$( serializeClassOf "$dep" )"
    case "$cls" in
        upfront)
            if grep -E 'TREE_SITTER_SERIALIZATION_BUFFER_SIZE' "$scannerPath" | grep -vE '^\s*(for|while)\s*\(' | grep -q .; then
                ok "H: $dep scanner classified upfront — whole-write bounds check present"
            else
                no "H: $dep scanner classified upfront but every BUFFER_SIZE reference sits in a loop header — reclassify"
            fi ;;
        static)
            if grep -q 'static_assert.*TREE_SITTER_SERIALIZATION_BUFFER_SIZE' "$scannerPath"; then
                ok "H: $dep scanner classified static — static_assert against the buffer size present"
            else
                no "H: $dep scanner classified static but has no static_assert against BUFFER_SIZE — reclassify"
            fi ;;
        loop1)
            if grep -q 'size < TREE_SITTER_SERIALIZATION_BUFFER_SIZE' "$scannerPath" && grep -q 'buffer\[size++\]' "$scannerPath"; then
                ok "H: $dep scanner classified loop1 — bare guard paired with 1-byte writes (proves exactly enough)"
            else
                no "H: $dep scanner classified loop1 but the guard/write pairing changed — re-audit the write width"
            fi ;;
        loopwide)
            if grep -q 'size + 2 \* sizeof(int16_t) <= TREE_SITTER_SERIALIZATION_BUFFER_SIZE' "$scannerPath"; then
                ok "H: $dep scanner classified loopwide — guard carries explicit headroom for the 4-byte iteration"
            else
                no "H: $dep scanner classified loopwide but the headroom guard is GONE — a bump resurrected the OOB write (re-apply third_party/patches/yaml/001-serialize-bounds.patch)"
            fi
            if grep -E 'TREE_SITTER_SERIALIZATION_BUFFER_SIZE' "$scannerPath" | grep -E '(for|while)[[:space:]]*\(' | grep -vE '\+.*<=' | grep -q .; then
                no "H: $dep scanner still has a bare per-iteration BUFFER_SIZE guard — the defect form is back"
            else
                ok "H: $dep scanner has no bare per-iteration BUFFER_SIZE guard left"
            fi ;;
        unknown)
            no "H: $dep scanner references TREE_SITTER_SERIALIZATION_BUFFER_SIZE but is UNCLASSIFIED — audit its serialize() write width and add it to serializeClassOf" ;;
    esac
done < <( grep -l 'TREE_SITTER_SERIALIZATION_BUFFER_SIZE' "$DEPS_DIR"/*/src/scanner.c 2>/dev/null | LC_ALL=C sort )
if [ "$serCount" -ge 5 ]; then
    ok "H: presence — $serCount vendored scanners reference the serialization buffer (sweep is not inert)"
else
    no "H: presence — only $serCount scanner(s) matched; the family sweep found too little to audit (extraction rot?)"
fi

# ── I: the narrow-counter family parses (asan flavour: the live tripwire for the four ───────────
#      markdown/002-counter-saturate + rust|lua|csharp/001-delimiter-count-cast) ────────────────
# markdown/002 + rust/001 + lua/001 + csharp/001 all fix ONE defect shape: a uint8_t counter in a
# vendored external scanner incremented past 255, which under G1's -fno-sanitize-recover=all is a
# hard abort, not a warning. Found 2026-09-09 on rails/guides/source/getting_started.md (a
# pipe-table row padded to 301 columns); the family sweep that followed found three more grammars
# carrying it. One fixture file per grammar, so a single reverted patch turns exactly one file red
# rather than hiding behind a neighbour. Presence first: a fixture whose wide run got reflowed by
# an editor would let this arm pass while inert, which is the failure mode arms F and G guard the
# same way.
# BSD grep caps interval repetition at 255 ("maximum repetition exceeds 255"), so `{256,}` is a
# hard error on the macOS leg while working fine under GNU grep — measure the runs in awk instead.
# WIDTHS ARE PINNED AT EXACTLY 256, NOT ">= 256", and that is the whole point of this block. The
# sanitizer aborts at every value >= 256, but the WRONG PARSE only fires while the wrapped value
# lands under the threshold the parser tests — N mod 256 in 0..3. Measured on the pre-fix binary:
#   indent/fence N=255 correct · N=256,257 WRONG at exit 0 · N=300 correct again, by luck
# So a fixture widened to a round 300 still reddens the asan arm and silently stops asserting
# anything on the plain build, where it would survive a FULL REVERT of the fix. A `>=` guard would
# not notice that edit; `==` does.
wrapPresence=0
wrapExact(){    # label  file  awk-expression-yielding-the-measured-width  expected
    got="$( awk "$3" "$WRAPFIX/$2" 2>/dev/null )"
    if [ -f "$WRAPFIX/$2" ] && [ "${got:-0}" = "$4" ]; then
        ok "I: presence — $2 $1 is EXACTLY $4 (the wrong-parse window, not merely over the abort threshold)"
        wrapPresence=$(( wrapPresence + 1 ))
    else
        no "I: presence — $2 $1 measured ${got:-none}, expected exactly $4 — widen it and the plain-build assertions below go inert while the asan arm stays green"
    fi
}
wrapExact "buried-heading indent"  widecounters.md '/buriedByTwoFiftySixColumns/ { match( $0, /^ */ ); print RLENGTH; exit }'   256
wrapExact "tab-buried indent"      widecounters.md '/buriedBySixtyFourTabs/ { n = gsub( /\t/, "" ); print n; exit }'            64
wrapExact "list-continuation"      widecounters.md '/buriedInListContinuation/ { match( $0, /^ */ ); print RLENGTH; exit }'     256
wrapExact "tilde fence"            widecounters.md '/^~+$/ { print length( $0 ); exit }'                                        256
wrapExact "rust raw-string hashes" widehash.rs     '{ while( match( $0, /#+/ ) ) { if( RLENGTH > mx ) { mx = RLENGTH } $0 = substr( $0, RSTART + RLENGTH ) } } END { print mx + 0 }' 256
wrapExact "lua long-bracket eqs"   widebracket.lua '{ while( match( $0, /=+/ ) ) { if( RLENGTH > mx ) { mx = RLENGTH } $0 = substr( $0, RSTART + RLENGTH ) } } END { print mx + 0 }' 256
wrapExact "csharp dollar run"      widedollar.cs   '{ while( match( $0, /[$]+/ ) ) { if( RLENGTH > mx ) { mx = RLENGTH } $0 = substr( $0, RSTART + RLENGTH ) } } END { print mx + 0 }' 256
if [ "$wrapPresence" -eq 7 ]; then
    ok "I: presence — all 7 widths pinned at exactly 256 across 4 grammars"
else
    no "I: presence — only $wrapPresence of 7 widths pinned at exactly 256"
fi
if "$BIN" "$WRAPFIX" --no-cache > "$TMP/wrap.xml" 2> "$TMP/wrap.err"; then
    if ! xmllint --noout "$TMP/wrap.xml" 2>/dev/null; then
        no "I: narrow-counter fixture ran but produced malformed output"
    else
        wrapMissing=""
        for sym in narrowCounterWrapMarkdown narrow_counter_wrap_rust narrowCounterWrapLua NarrowCounterWrapCsharp; do
            grep -q "\"$sym\"" "$TMP/wrap.xml" || wrapMissing="$wrapMissing $sym"
        done
        if [ -z "$wrapMissing" ]; then
            ok "I: markdown/rust/lua/csharp wide-counter fixtures parse clean, well-formed, all 4 symbols extracted"
        else
            no "I: fixture parsed but these symbols were NOT extracted —$wrapMissing (the parse degraded, not just survived)"
        fi
        # THE SEMANTIC HALF, live under BOTH flavours and the only half that survives on the plain
        # build. Reverting the saturation there is an exit-0 WRONG ANSWER, not a crash, so an
        # exit-code-only arm goes green straight through a full revert. Each name below is text the
        # scanner must NOT mint a heading for: three buried under 256 columns (spaces, 64 tabs, and a
        # and one inside a 256-tilde fence, which upstream never opened because `level` wrapped to 0
        # and `level >= 3` then failed, leaking the fence body out as live markdown. VERIFIED
        # NON-VACUOUS: on a fully reverted binary this list is exactly what comes back red.
        # The fixture's list-continuation line is deliberately NOT in this list. It drives the
        # soft-line-ending lookahead site (scanner.c:1501), which the leading-indent case never
        # reaches, but it mints no phantom heading either way — measured absent on the reverted
        # binary too — so asserting its absence would be a vacuous assertion dressed as coverage.
        # It earns its place on the ABORT arm above and is claimed for nothing more.
        wrapPhantom=""
        for sym in buriedByTwoFiftySixColumns buriedBySixtyFourTabs buriedInsideFence; do
            grep -q "\"$sym\"" "$TMP/wrap.xml" && wrapPhantom="$wrapPhantom $sym"
        done
        if [ -z "$wrapPhantom" ]; then
            ok "I: no phantom heading — all 3 phantom-capable ATX lines are correctly ABSENT from the map (the counters saturate)"
        else
            no "I: PHANTOM HEADINGS extracted —$wrapPhantom. A uint8_t counter wrapped 256 to 0, so an indented code block parsed as a heading and/or a fence never opened (markdown/002-counter-saturate is not in effect). This is an exit-0 wrong answer: the asan arm above cannot see it."
        fi
    fi
else
    no "I: ripwire ABORTED on the narrow-counter fixture (rc=$?) — markdown/002-counter-saturate or a rust|lua|csharp/001-delimiter-count-cast patch is not in effect"
    head -3 "$TMP/wrap.err" | sed 's/^/        /'
fi

# ── J: kotlin/001 (stack-push-no-abort) + kotlin/002 (triple-dollar-escape) live tripwires ────────
# kotlin/001, STATIC: Arm B proves the patch file is still carried. This arm proves the SHAPE it exists for is gone, so a
# re-vendor that brings an abort() back onto the string-stack path fails here even if someone
# regenerates the patch file to match the new tree. Presence first: the extraction keys on the
# PATCHED signature (`static inline bool stack_push`), so upstream's `void` form — or a rename on a
# bump — fails the presence check instead of passing an arm that extracted nothing.
KT_SCANNER="$DEPS_DIR/kotlin/src/scanner.c"
ktStackPath="$( awk '/^static inline bool stack_push\(/,/^}/ { print } /^static inline void stack_pop\(/,/^}/ { print } /^static bool scan_string_start\(/,/^}/ { print }' "$KT_SCANNER" 2>/dev/null )"
if printf '%s\n' "$ktStackPath" | grep -q 'array_push(stack' \
   && printf '%s\n' "$ktStackPath" | grep -q 'stack->size -= 2' \
   && printf '%s\n' "$ktStackPath" | grep -q 'lexer->lookahead'; then
    ok "J: presence — the bool stack_push, stack_pop and scan_string_start bodies extracted from the kotlin scanner"
    if printf '%s\n' "$ktStackPath" | grep -q 'abort()'; then
        no "J: the kotlin scanner's string-stack path calls abort() again — re-apply third_party/patches/kotlin/001-stack-push-no-abort.patch"
    else
        ok "J: no abort() on the kotlin scanner's string-stack path (stack_push / stack_pop / scan_string_start)"
    fi
    ktPropagate="$( printf '%s\n' "$ktStackPath" | grep -c 'return stack_push(' )"
    if [ "$ktPropagate" -eq 2 ]; then
        ok "J: both string-start shapes (single- and triple-quoted) return the push's verdict — a refused push is no string start"
    else
        no "J: expected 2 'return stack_push(' sites in scan_string_start, found $ktPropagate — a refused push would be reported as a string the stack never recorded"
    fi
else
    no "J: presence — no bool stack_push / stack_pop / scan_string_start bodies in $KT_SCANNER (upstream's abort() form, or renamed on a bump) — the arm would otherwise pass while inert"
fi

# kotlin/001: the delimiter stack's abort() is a DELIBERATE process termination, not UB — no sanitizer
# flags it, so it is invisible to every fuzz/ASan sweep that found every other patch in this file
# (found instead by an automated PR review, 2026-09-10). A file whose interpolated strings nest deep
# enough (>=512 unterminated string-opens, TREE_SITTER_SERIALIZATION_BUFFER_SIZE / 2 bytes-per-entry)
# used to SIGABRT the whole process; it must now degrade to ERROR nodes like any other malformed input.
# Since the ingest nesting guard landed (kotlincheck §12) the default map refuses this file before any parse, so
# this run proves the WHOLE pipeline survives it; the --match run below is the half that reaches the scanner.
mkdir -p "$TMP/deepinterp"
python3 - "$TMP/deepinterp/deep.kt" <<'PYEOF'
import sys
with open( sys.argv[1], 'w' ) as f:
    f.write( 'package deepinterp\n\nval x = "' + '${"' * 700 + '\n' )
PYEOF
if [ "$( wc -c < "$TMP/deepinterp/deep.kt" )" -gt 2000 ]; then
    ok "J: presence — generated deep-interpolation Kotlin file (700 nested string-opens)"
else
    no "J: presence — deep-interpolation file generation failed"
fi
"$BIN" "$TMP/deepinterp" --no-cache > "$TMP/deepinterp.xml" 2> "$TMP/deepinterp.err"; deepRc=$?
if [ "$deepRc" -eq 0 ]; then
    if xmllint --noout "$TMP/deepinterp.xml" 2>/dev/null; then
        ok "J: the default map over 700 nested string-opens exits 0 and is well-formed (ingest's prescan refuses the file first; the raw-scanner harness below is what reaches the scanner)"
    else
        no "J: deep-interpolation parse ran but produced malformed output"
    fi
else
    no "J: the default map exited $deepRc over 700 nested string-opens (134 = an abort) — neither the ingest prescan nor kotlin/001-stack-push-no-abort held"
    head -3 "$TMP/deepinterp.err" | sed 's/^/        /'
fi

# The RUNTIME half. #157 closed the loophole this arm used to exercise: --match's structural-query pass used to
# parse every file of a grammar the query compiled against with NO nesting guard, handing the scanner a 600-deep
# file directly — that was the bug #157 fixed (ripwire's own CLI now refuses this file at every entry point, ingest
# AND --match/--pattern alike, via IngestResult::nestRefusedFile — see ingest_astquery.h). So $BIN can no longer
# reach this scanner path at all, by any verb, and this arm's own job — proving kotlin/001 (the scanner refuses the
# push instead of aborting) independently of ripwire's prescan — needs a caller that has no prescan to bypass:
# a standalone harness linking the vendored kotlin grammar (parser.c + scanner.c) straight to a tree-sitter core
# build, calling tree_sitter_kotlin() and ts_parser_parse_string() with nothing else in front. Same $CC detection
# as arm K's harness below (this arm runs first, so it cannot reuse arm K's $kcc). rc=134 (SIGABRT) is the bug;
# rc=0 is the patch holding. The harness is built with plain -O1 and no sanitizer flags, in every flavour: it
# proves the refusal by exit status only, so since #157 took $BIN off this scanner path the asan flavour no
# longer runs this scanner under a sanitizer (CodeRabbit on #331).
KTDEEP="$TMP/ktdeep"; mkdir -p "$KTDEEP"
{
    printf 'package deep\n\nfun deepFn(): Int = 1\n\nval deep = '
    for _ in $( seq 1 599 ); do printf '"a${'; done
    printf '"leaf"'
    for _ in $( seq 1 599 ); do printf '}"'; done
    printf '\n'
} > "$KTDEEP/Deep.kt"
ktOpeners="$( grep -o '"a\${' "$KTDEEP/Deep.kt" | wc -l | tr -d ' ' )"
if [ "$ktOpeners" != 599 ]; then
    no "J: presence — the generated Deep.kt has $ktOpeners string openers, not 599 (600 open strings) — the runtime arm would assert on the wrong input"
else
    JDIR="$TMP/ktharness"; mkdir -p "$JDIR"
    KTSRC="$DEPS_DIR/kotlin/src"
    JCORE="$DEPS_DIR/tree_sitter/lib"
    jcc=""
    for jcand in "${CC:-}" clang cc gcc; do
        if [ -n "$jcand" ] && command -v "$jcand" >/dev/null 2>&1; then
            jcc="$jcand"
            break
        fi
    done
    cat > "$JDIR/probe.c" <<'CEOF'
#include <stdio.h>
#include <stdlib.h>
#include "tree_sitter/api.h"

const TSLanguage *tree_sitter_kotlin(void);

int main(int argc, char **argv) {
    static char buf[1 << 20];
    FILE *f = argc == 2 ? fopen(argv[1], "rb") : NULL;
    if (!f) {
        return 2;
    }
    size_t n = fread(buf, 1, sizeof buf, f);
    fclose(f);
    if (n == sizeof buf) {
        return 4;
    }
    TSParser *parser = ts_parser_new();
    if (!ts_parser_set_language(parser, tree_sitter_kotlin())) {
        return 3;
    }
    TSTree *tree = ts_parser_parse_string(parser, NULL, buf, (uint32_t)n);
    char *sexp = ts_node_string(ts_tree_root_node(tree));
    printf("%s\n", sexp);
    free(sexp);
    ts_tree_delete(tree);
    ts_parser_delete(parser);
    return 0;
}
CEOF
    if [ -z "$jcc" ]; then
        skip "J: no C compiler found (checked \$CC, clang, cc, gcc) — the raw-scanner runtime harness cannot be built"
    else
        jbuilt=1
        "$jcc" -O1 -c "$JCORE/src/lib.c"   -I "$JCORE/include" -I "$JCORE/src" -o "$JDIR/core.o"    2> "$JDIR/build.log" || jbuilt=0
        "$jcc" -O1 -c "$KTSRC/parser.c"    -I "$JCORE/include" -I "$KTSRC"     -o "$JDIR/parser.o"  2>>"$JDIR/build.log" || jbuilt=0
        "$jcc" -O1 -c "$KTSRC/scanner.c"   -I "$JCORE/include" -I "$KTSRC"     -o "$JDIR/scanner.o" 2>>"$JDIR/build.log" || jbuilt=0
        "$jcc" -O1 -c "$JDIR/probe.c"      -I "$JCORE/include"                -o "$JDIR/probe.o"    2>>"$JDIR/build.log" || jbuilt=0
        if [ "$jbuilt" = 1 ]; then
            "$jcc" "$JDIR/probe.o" "$JDIR/core.o" "$JDIR/parser.o" "$JDIR/scanner.o" -o "$JDIR/probe" 2>>"$JDIR/build.log" || jbuilt=0
        fi
        if [ "$jbuilt" != 1 ]; then
            no "J: $jcc could not build the raw kotlin-scanner harness — $( grep -m1 -iE 'error|undefined' "$JDIR/build.log" )"
        else
            ok "J: presence — the vendored kotlin grammar (parser.c + scanner.c) built standalone against one tree-sitter core with $jcc, no ripwire CLI involved"
            ( "$JDIR/probe" "$KTDEEP/Deep.kt" > "$JDIR/probe.out" 2>"$JDIR/probe.err" ); jrc=$?
            if [ "$jrc" -eq 0 ] && [ -s "$JDIR/probe.out" ]; then
                ok "J: the raw scanner parses the 600-deep Deep.kt directly and exits 0 — the scanner refused the push instead of aborting"
            else
                no "J: the raw scanner over a 600-deep string template exited $jrc (134 = the scanner's abort(); kotlin/001-stack-push-no-abort.patch would be reverted or ineffective): $( head -2 "$JDIR/probe.err" )"
            fi
        fi
    fi
fi

# kotlin/002: an escaped `$` immediately before a triple-quoted string's closing delimiter used to
# consume only the FIRST of three closing quotes as STRING_END, corrupting the tokens after it. The
# committed fixture (test/vendorpatchfix/tripledollar.kt, shared with arm F's directory) pins this on
# the plain build too (an exit-0 mis-tokenization, not a crash arm F/G/I's exit-code check would ever
# see): the file must parse with NO degraded-parse signal, and the function declared right after the
# tricky string literal must still extract as its own symbol — proof the scanner resynced correctly.
TDOLLAR_XML="$( "$BIN" "$FIX" --no-cache 2>/dev/null )"
TDOLLAR_SK="$( "$BIN" "$FIX" --skipped --no-cache 2>/dev/null )"
if echo "$TDOLLAR_XML" | grep -q 'n="afterTripleDollarEscape"'; then
    ok "J: kotlin/002 fixture — afterTripleDollarEscape extracts cleanly right after the tricky string"
else
    no "J: kotlin/002 fixture — afterTripleDollarEscape missing/not extracted (the scanner did not resync — kotlin/002-triple-dollar-escape is not in effect)"
fi
if echo "$TDOLLAR_SK" | grep -q 'degraded_parse="0"'; then
    ok "J: kotlin/002 fixture — degraded_parse=\"0\" (no ERROR/MISSING nodes from the escaped-dollar edge case)"
else
    no "J: kotlin/002 fixture — degraded_parse is non-zero: $( echo "$TDOLLAR_SK" | grep -o 'degraded_parse="[^"]*"' )"
fi

# kotlin/003: the uint16_t dollar-run counter saturates. STATIC half: the guard sits inside the loop that counts the run.
# RUNTIME half: a generated run of 65,537 `$` reaches both truncation sites (`1 + additional_dollars` at 65,536, and `++`
# one step later), so the ASan flavour aborts without the patch. The run is closed by a quote on purpose: a run followed
# by `{` or an identifier is re-read once per excess `$` (upstream's design, quadratic in the run), which is where the
# plain-build wrong parse at 65,536 lives, and seconds per file is too slow for this arm. So on the plain build this half
# proves only that the file and the symbol after it survive; the ASan leg is the tripwire.
ktDollarLoop="$( awk '/uint16_t additional_dollars = 0;/,/uint16_t total_dollars/' "$KT_SCANNER" 2>/dev/null )"
if printf '%s\n' "$ktDollarLoop" | grep -q "while (lexer->lookahead == '\\$')"; then
    ok "J: presence — the kotlin scanner's dollar-run counting loop extracted"
    if printf '%s\n' "$ktDollarLoop" | grep -F -q 'if (additional_dollars < 256) additional_dollars = (uint16_t)(additional_dollars + 1);' \
       && ! printf '%s\n' "$ktDollarLoop" | grep -F -q 'additional_dollars++'; then
        ok "J: kotlin/003 — the dollar-run counter saturates at 256 (no bare additional_dollars++ left)"
    else
        no "J: kotlin/003 — the dollar-run counter is not saturated — re-apply third_party/patches/kotlin/003-dollar-run-saturate.patch"
    fi
else
    no "J: presence — no dollar-run counting loop found in $KT_SCANNER (renamed on a bump?) — the kotlin/003 arm would pass while inert"
fi
KTDOLLAR="$TMP/ktdollar"; mkdir -p "$KTDOLLAR"
python3 - "$KTDOLLAR/Dollars.kt" <<'PYEOF'
import sys
with open( sys.argv[1], 'w' ) as f:
    f.write( 'package dollars\n\nval run = "' + '$' * 65537 + '"\n\nfun afterDollarRun(n: Int): Int = n + 1\n' )
PYEOF
ktDollarRun="$( awk '{ while( match( $0, /[$]+/ ) ) { if( RLENGTH > mx ) { mx = RLENGTH } $0 = substr( $0, RSTART + RLENGTH ) } } END { print mx + 0 }' "$KTDOLLAR/Dollars.kt" )"
if [ "$ktDollarRun" = 65537 ]; then
    "$BIN" "$KTDOLLAR" --no-cache > "$TMP/ktdollar.xml" 2> "$TMP/ktdollar.err"; ktDollarRc=$?
    if [ "$ktDollarRc" -eq 0 ] && grep -q '"afterDollarRun"' "$TMP/ktdollar.xml"; then
        ok "J: kotlin/003 — a 65,537-dollar run exits 0 and afterDollarRun still extracts"
    else
        no "J: kotlin/003 — a 65,537-dollar run exited $ktDollarRc (134 = the uint16_t truncation abort on asan) or lost afterDollarRun: $( grep -m1 'runtime error' "$TMP/ktdollar.err" | cut -c1-160 )"
    fi
else
    no "J: presence — the generated dollar run is $ktDollarRun long, not 65537 — the kotlin/003 runtime arm would assert on the wrong input"
fi

# ── K: the yaml scanner's SCN_FAIL (-1) under an UNSIGNED char — signedness forced, any host ─────────────────
# tree-sitter-yaml v0.7.2 returns its scan status (SCN_SUCC 1, SCN_STOP 0, SCN_FAIL -1) through four functions
# declared `static char`: scn_uri_esc, the two that hand its result back unchanged (scn_ns_uri_char and
# scn_ns_tag_char), and scn_pln_cnt. `char` is signed on x86-64 and Apple arm64 and UNSIGNED on aarch64 Linux,
# which is where the linux-arm64 release asset is built. There -1 comes back as 255, with two symptoms:
#   parse  the three `case SCN_FAIL:` labels (scn_dir_tag_pfx, and scn_tag's verbatim and shorthand loops) never
#          match 255, so a malformed %-escape in a tag or a %TAG prefix is swallowed into the token instead of
#          ending it. `a: !<tag:x%zz> b` is ERROR under a signed char and a clean tagged scalar under an
#          unsigned one: the same bytes give a different tree depending on the CPU the binary was built for.
#   abort  scn_pln_cnt's `return SCN_FAIL;` is reached by an ordinary `key: value` line, and G1's
#          implicit-conversion check stops the run there (int -1 to char 255). Its caller only tests
#          `!= SCN_SUCC`, so that tree does not change; only a sanitizer sees this one.
# Neither CI leg has an unsigned char, so no run of $BIN can show either symptom. This arm does not use $BIN. It
# compiles the vendored grammar itself with the signedness FORCED and parses fixtures with the result:
#   trees      parser.c + scanner.c built -fsigned-char and again -funsigned-char, each linked against one build
#              of the vendored tree-sitter core, must print byte-identical output for every fixture: the
#              S-expression, then every node with its byte range, so a token that ends one byte later differs.
#              Each fixture's ERROR-or-clean verdict is pinned as well, so a "fix" that made BOTH signednesses
#              accept a malformed escape still goes red.
#   sanitizer  the -funsigned-char scanner built with -fsanitize=undefined,implicit-conversion
#              -fno-sanitize-recover=all must parse every fixture and every test/yamlfix file with exit 0 and an
#              empty stderr. A synthetic -1 returned through an unsigned char must abort under the same flags
#              first, so this half cannot pass by instrumenting nothing. GCC has no implicit-conversion check:
#              where the compiler cannot build with those flags, this half SKIPs and says why.
# Fixtures, one per site the audit found (named by function, never by line): the reported repro under a mapping
# key; a bad and a half escape in a verbatim tag (scn_uri_esc's two returns, scn_tag's verbatim case label); a
# bad escape in a shorthand tag and in a %TAG prefix (the other two case labels); the same -1 reaching the three
# sign-blind `!= SCN_SUCC` / `== SCN_SUCC` tests, where the tree cannot differ but the sanitizer still aborts;
# `key: value` (scn_pln_cnt); and a CONTROL that reaches no failure path at all. The control parsed identically
# and ran clean under the sanitizer BEFORE the fix, so an identical pair is evidence, not a harness that prints
# the same nothing twice. The remedy is third_party/patches/yaml/003-scan-status-enum.patch; before it, this arm
# is red on every host.
# The compiler is $CC when set, else the first of clang, cc, gcc (clang first: only Clang has the sanitizer
# half). With no C compiler at all the whole arm SKIPs and says so.
KDIR="$TMP/uchar"; mkdir -p "$KDIR/fix"
KYAML="$DEPS_DIR/yaml/src"
KCORE="$DEPS_DIR/tree_sitter/lib"
kcc=""
for kcand in "${CC:-}" clang cc gcc; do
    if [ -n "$kcand" ] && command -v "$kcand" >/dev/null 2>&1; then
        kcc="$kcand"
        break
    fi
done
: > "$KDIR/fixtures.tsv"
kfix(){   # file  printf-format-of-its-bytes  pinned-verdict(error|clean)  what-it-reaches
    printf "$2" > "$KDIR/fix/$1"
    printf '%s\t%s\t%s\n' "$1" "$3" "$4" >> "$KDIR/fixtures.tsv"
}
kfix repro_verbatim_tag.yaml      'a: !<tag:x%%zz> b\n'                 error 'the reported repro, a bad %-escape in a verbatim tag under a mapping key'
kfix verbatim_bad_escape.yaml     '!<tag:x%%zz> b\n'                    error "scn_uri_esc's first SCN_FAIL, into scn_tag's verbatim case label"
kfix verbatim_half_escape.yaml    '!<tag:x%%4z> b\n'                    error "scn_uri_esc's second SCN_FAIL (one hex digit, then none), same case label"
kfix shorthand_bad_escape.yaml    '!foo%%zz b\n'                        error "scn_ns_tag_char handing SCN_FAIL to scn_tag's shorthand case label"
kfix tag_prefix_bad_escape.yaml   '%%TAG !e! tag:x%%zz\n--- !e!b c\n'   error "scn_ns_uri_char handing SCN_FAIL to scn_dir_tag_pfx's case label"
kfix verbatim_first_escape.yaml   '!<%%zz> b\n'                         error "SCN_FAIL at scn_tag's first verbatim character, a sign-blind != SCN_SUCC test"
kfix shorthand_first_escape.yaml  '!e!%%zz b\n'                         error "SCN_FAIL at scn_tag's first shorthand character, a sign-blind != SCN_SUCC test"
kfix tag_prefix_first_escape.yaml '%%TAG !e! %%zz\n--- !e!b c\n'        error "SCN_FAIL at scn_dir_tag_pfx's first character, a sign-blind == SCN_SUCC test"
kfix plain_key_colon.yaml         'key: value\n'                        clean "scn_pln_cnt's SCN_FAIL at a colon with no plain-safe character after it, a sign-blind != SCN_SUCC test"
kfix control.yaml                 '"seq":\n  - [alpha, beta]\n  - !<tag:yaml.org,2002:str> gamma\n  - !!str delta\n  - !<tag:x%%41> epsilon\n' \
                                                                        clean 'CONTROL: flow scalars, a verbatim tag, a secondary-handle tag and a valid %41 escape, no failure path'
cat > "$KDIR/parse.c" <<'CEOF'
#include <stdio.h>
#include <stdlib.h>
#include "tree_sitter/api.h"

const TSLanguage *tree_sitter_yaml(void);

static void dump(TSNode node, unsigned depth) {
    printf("%*s%s%s [%u,%u]%s\n", (int)(depth * 2), "", ts_node_is_named(node) ? "" : "'", ts_node_type(node),
           ts_node_start_byte(node), ts_node_end_byte(node), ts_node_is_missing(node) ? " MISSING" : "");
    for (uint32_t i = 0; i < ts_node_child_count(node); i++) {
        dump(ts_node_child(node, i), depth + 1);
    }
}

int main(int argc, char **argv) {
    static char buf[1 << 20];
    FILE *f = argc == 2 ? fopen(argv[1], "rb") : NULL;
    if (!f) {
        return 2;
    }
    size_t n = fread(buf, 1, sizeof buf, f);
    fclose(f);
    if (n == sizeof buf) {
        return 4;
    }
    TSParser *parser = ts_parser_new();
    if (!ts_parser_set_language(parser, tree_sitter_yaml())) {
        return 3;
    }
    TSTree *tree = ts_parser_parse_string(parser, NULL, buf, (uint32_t)n);
    char *sexp = ts_node_string(ts_tree_root_node(tree));
    printf("%s\n", sexp);
    free(sexp);
    dump(ts_tree_root_node(tree), 0);
    ts_tree_delete(tree);
    ts_parser_delete(parser);
    return 0;
}
CEOF
cat > "$KDIR/narrow.c" <<'CEOF'
static char narrow(int value) {
    return value;
}

int main(int argc, char **argv) {
    (void)argv;
    return narrow(argc - 2) == 0;
}
CEOF
kdisp(){ printf '%s/%s' "$( basename "$( dirname "$1" )" )" "$( basename "$1" )"; }
if [ -z "$kcc" ]; then
    skip "K: no C compiler (tried \$CC, clang, cc, gcc) — the forced-signedness yaml build cannot run, so arm K asserted nothing on this host"
else
    kbuilt=1
    "$kcc" -O1 -c "$KCORE/src/lib.c" -I "$KCORE/include" -I "$KCORE/src" -o "$KDIR/core.o" 2> "$KDIR/build.log" || kbuilt=0
    "$kcc" -O1 -c "$KDIR/parse.c" -I "$KCORE/include" -o "$KDIR/parse.o" 2>> "$KDIR/build.log" || kbuilt=0
    for ksign in signed unsigned; do
        "$kcc" -O1 "-f$ksign-char" -c "$KYAML/parser.c" -I "$KYAML" -o "$KDIR/parser_$ksign.o" 2>> "$KDIR/build.log" || kbuilt=0
        "$kcc" -O1 "-f$ksign-char" -c "$KYAML/scanner.c" -I "$KYAML" -o "$KDIR/scanner_$ksign.o" 2>> "$KDIR/build.log" || kbuilt=0
        "$kcc" "$KDIR/parse.o" "$KDIR/core.o" "$KDIR/parser_$ksign.o" "$KDIR/scanner_$ksign.o" -o "$KDIR/parse_$ksign" 2>> "$KDIR/build.log" || kbuilt=0
    done
    if [ "$kbuilt" = 0 ]; then
        no "K: $kcc could not build the forced-signedness yaml harness — $( grep -m1 -iE 'error|undefined' "$KDIR/build.log" )"
    else
        ok "K: presence — the vendored yaml grammar built twice with $kcc (-fsigned-char, -funsigned-char) against one tree-sitter core, $( wc -l < "$KDIR/fixtures.tsv" | tr -d ' ' ) fixtures"
        while IFS=$'\t' read -r kname kwant kwhat; do
            "$KDIR/parse_signed" "$KDIR/fix/$kname" > "$KDIR/$kname.signed" 2>/dev/null; krs=$?
            "$KDIR/parse_unsigned" "$KDIR/fix/$kname" > "$KDIR/$kname.unsigned" 2>/dev/null; kru=$?
            ksexp="$( head -1 "$KDIR/$kname.signed" )"
            case "$ksexp" in
                '')                kgot=empty ;;
                *ERROR*|*MISSING*) kgot=error ;;
                *)                 kgot=clean ;;
            esac
            if [ "$krs" != 0 ] || [ "$kru" != 0 ]; then
                no "K: $kname — the harness itself failed (signed rc=$krs, unsigned rc=$kru), so nothing was compared"
            elif ! cmp -s "$KDIR/$kname.signed" "$KDIR/$kname.unsigned"; then
                no "K: $kname parses DIFFERENTLY once char is unsigned ($kwhat). signed: $ksexp | unsigned: $( head -1 "$KDIR/$kname.unsigned" )"
            elif [ "$kgot" != "$kwant" ]; then
                no "K: $kname parses the same under both signednesses, but $kgot where $kwant is pinned ($kwhat): $ksexp"
            else
                ok "K: $kname — identical tree under signed and unsigned char, $kwant as pinned ($kwhat)"
            fi
        done < "$KDIR/fixtures.tsv"

        if ! "$kcc" -O0 -funsigned-char -fsanitize=undefined,implicit-conversion -fno-sanitize-recover=all "$KDIR/narrow.c" -o "$KDIR/narrow" 2> "$KDIR/narrow.log"; then
            skip "K: sanitizer half — $kcc cannot build with -fsanitize=undefined,implicit-conversion ($( head -1 "$KDIR/narrow.log" )). GCC has no implicit-conversion check; CC=clang runs this half. The trees half above still ran."
        else
            ( UBSAN_OPTIONS=print_stacktrace=0 "$KDIR/narrow" > /dev/null 2> "$KDIR/narrow.err" ) 2>/dev/null; krc=$?
            if [ "$krc" = 0 ] || ! grep -q 'implicit conversion' "$KDIR/narrow.err"; then
                no "K: sanitizer self-test — a -1 returned through an unsigned char did NOT abort (rc=$krc) under -fsanitize=implicit-conversion -fno-sanitize-recover=all, so the population below would prove nothing"
            elif ! { "$kcc" -O1 -g -funsigned-char -fsanitize=undefined,implicit-conversion -fno-sanitize-recover=all -c "$KYAML/scanner.c" -I "$KYAML" -o "$KDIR/scanner_ubsan.o" 2> "$KDIR/ubsan.log" \
                     && "$kcc" -fsanitize=undefined,implicit-conversion "$KDIR/parse.o" "$KDIR/core.o" "$KDIR/parser_unsigned.o" "$KDIR/scanner_ubsan.o" -o "$KDIR/parse_ubsan" 2>> "$KDIR/ubsan.log"; }; then
                no "K: sanitizer self-test passed, but the -funsigned-char sanitizer build of the yaml scanner failed — $( grep -m1 -iE 'error|undefined' "$KDIR/ubsan.log" )"
            else
                ok "K: sanitizer self-test — a -1 returned through an unsigned char aborts under -fsanitize=implicit-conversion -fno-sanitize-recover=all (rc=$krc)"
                kpop=0; kyamlfix=0; kaborted=0
                while IFS= read -r kfile; do
                    kpop=$(( kpop + 1 ))
                    case "$kfile" in "$ROOT/test/yamlfix/"*) kyamlfix=$(( kyamlfix + 1 )) ;; esac
                    ( UBSAN_OPTIONS=print_stacktrace=0 "$KDIR/parse_ubsan" "$kfile" > /dev/null 2> "$KDIR/ubsan.err" ) 2>/dev/null; krc=$?
                    if [ "$krc" != 0 ] || [ -s "$KDIR/ubsan.err" ]; then
                        kaborted=$(( kaborted + 1 ))
                        no "K: sanitizer — $( kdisp "$kfile" ) aborts once char is unsigned (rc=$krc): $( grep -m1 -oE 'scanner\.c:[0-9]+:[0-9]+: runtime error: [^(]*' "$KDIR/ubsan.err" )"
                    fi
                done < <( cut -f1 "$KDIR/fixtures.tsv" | sed "s|^|$KDIR/fix/|"; find "$ROOT/test/yamlfix" -type f \( -name '*.yml' -o -name '*.yaml' \) | LC_ALL=C sort )
                if [ "$kyamlfix" -lt 3 ]; then
                    no "K: sanitizer — presence: only $kyamlfix test/yamlfix file(s) found, expected >= 3 (the population shrank)"
                elif [ "$kaborted" = 0 ]; then
                    ok "K: sanitizer — all $kpop inputs ($kyamlfix of them test/yamlfix) parse clean with the -funsigned-char scanner under -fsanitize=implicit-conversion -fno-sanitize-recover=all"
                fi
            fi
        fi
    fi
fi

# ── L: tree_sitter/001 — a field the grammar lacks, over a capture, leaks nothing ─────────────────────
LDIR="$TMP/fieldleak"; mkdir -p "$LDIR"
printf 'int f( int x ) { return x; }\n' > "$LDIR/a.c"
LQUERY='(binary_expression operator: ["&&" "||"] right: (unary_expression argument: (call_expression function: (_) @c)) (#match? @c "^(fclose|close)$"))'
LCONTROL='(binary_expression operator: ["&&" "||"] right: (call_expression function: (_) @c) (#match? @c "^(fclose|close)$"))'
leaksOf(){ grep -oE '[0-9]+ leaks? for [0-9]+ total leaked bytes' "$1" | head -1 | grep -oE '^[0-9]+'; }
if LC_ALL=C grep -q -a '__lsan_' "$BIN" 2>/dev/null && [ "$( uname -s )" = "Linux" ]; then
    ASAN_OPTIONS="${ASAN_OPTIONS:+$ASAN_OPTIONS:}detect_leaks=1:log_path=stderr" LSAN_OPTIONS="suppressions=$ROOT/lsan_suppressions.txt" \
        "$BIN" "$LDIR" --match="$LQUERY" >"$TMP/fieldleak.out" 2>"$TMP/fieldleak.err"; lrc=$?
    if [ "$lrc" -eq 0 ] && ! grep -q 'LeakSanitizer' "$TMP/fieldleak.err"; then
        ok "L: tree_sitter/001 — a query naming a field some grammar lacks exits 0 under LeakSanitizer"
    else
        no "L: tree_sitter/001 — exit $lrc under LeakSanitizer: $( grep -m1 -A3 'LeakSanitizer' "$TMP/fieldleak.err" | tr '\n' ' ' | cut -c1-240 )"
    fi
elif command -v leaks >/dev/null 2>&1 && [ "$( uname -s )" = "Darwin" ] && ! LC_ALL=C grep -q -a '__asan_init' "$BIN" 2>/dev/null; then
    leaks --atExit -- "$BIN" "$LDIR" --match="$LCONTROL" >"$TMP/fieldleak_control.txt" 2>&1
    leaks --atExit -- "$BIN" "$LDIR" --match="$LQUERY"   >"$TMP/fieldleak.txt" 2>&1
    lcontrol="$( leaksOf "$TMP/fieldleak_control.txt" )"; lcount="$( leaksOf "$TMP/fieldleak.txt" )"
    if [ -z "$lcontrol" ] || [ -z "$lcount" ]; then
        skip "L: tree_sitter/001 — leaks(1) printed no leak count here (control '${lcontrol:-none}', query '${lcount:-none}'), so nothing was measured"
    elif [ "$lcontrol" -ne 0 ]; then
        no "L: tree_sitter/001 — the field-free CONTROL query already leaks $lcontrol object(s); the arm cannot attribute a leak to the field path"
    elif [ "$lcount" -eq 0 ]; then
        ok "L: tree_sitter/001 — leaks(1): 0 leaks for a query naming a field some grammar lacks (control 0)"
    else
        no "L: tree_sitter/001 — leaks(1): $lcount leak(s) for a query naming a field some grammar lacks (control 0): the field-error return skipped its quantifier delete"
    fi
else
    skip "L: tree_sitter/001 — no leak detector for this binary here (LeakSanitizer needs a Linux sanitizer build; leaks(1) needs macOS and a plain build)"
fi

# ── M: 1UL << shift-width family audit (static, no $BIN involved) ─────────────────────────────────
# The audit is written once and run twice: first on a synthetic tree whose verdicts are known (M0, the arm's own
# red-first control), then on third_party/deps/. A clean result means every *.c/*.h was READ and every `1UL <<`
# operand was either proven < 32 or reported: the whole operand is parsed across lines, a numeric operand gets the
# same >= 32 test as an enumerator, an operand that continues past its first token (`31 + 1`, `(n)`, `a[i]`) is
# UNRESOLVED rather than read as its first token, and after an enumerator whose initializer is not a literal the
# implicit members that follow stay unresolved until a literal initializer resets the count.
cat > "$TMP/shiftwidth.py" <<'PYEOF'
import re, sys, pathlib

deps_dir = pathlib.Path(sys.argv[1])
files = sorted(deps_dir.rglob("*.c")) + sorted(deps_dir.rglob("*.h"))
if not files:
    sys.exit(f"no *.c or *.h under {deps_dir}: the audit would read nothing")

# every spelling of a `long` 1: unsigned (u and l in either order and case) or signed; `1ULL`/`1LL` fail the \b
shift_re = re.compile(r'\b1(?P<suffix>[uU][lL]|[lL][uU]?)\b\s*<<')
ident_re = re.compile(r'[A-Za-z_]\w*')
num_re = re.compile(r'(0[xX][0-9A-Fa-f]+|[0-9]+)[uUlL]*(?![\w.])')
enum_block_re = re.compile(r'\benum\b[^{;]*\{([^}]*)\}', re.S)

def strip_comments(text):
    # Blanks out // and /* */ comments while preserving every newline, so line numbers in the
    # stripped text still match the original file, and no identifier or digit inside a comment
    # (including this audit's own explanatory comments in a patched vendored file) can be mistaken
    # for a real shift expression. Not string-literal aware — acceptable here: these are C scanner
    # sources, and a `//`/`/*` inside a string literal on a `1UL <<` line is not a shape this
    # vendored code uses.
    out = []
    i, n = 0, len(text)
    line_comment = block_comment = False
    while i < n:
        c = text[i]
        if line_comment:
            out.append('\n' if c == '\n' else ' ')
            line_comment = c != '\n'
            i += 1
        elif block_comment:
            if text[i:i + 2] == '*/':
                out.append('  '); i += 2; block_comment = False
            else:
                out.append('\n' if c == '\n' else ' '); i += 1
        elif text[i:i + 2] == '//':
            out.append('  '); i += 2; line_comment = True
        elif text[i:i + 2] == '/*':
            out.append('  '); i += 2; block_comment = True
        else:
            out.append(c); i += 1
    return ''.join(out)

def c_int(tok):
    # a C integer literal (hex, octal, decimal; any u/l suffix): its value, or None when it is not one
    m = re.fullmatch(r'(0[xX][0-9A-Fa-f]+|0[0-7]*|[1-9][0-9]*)[uUlL]*', tok.strip())
    if not m:
        return None
    d = m.group(1)
    return int(d, 16) if d[:2] in ('0x', '0X') else int(d, 8) if d.startswith('0') else int(d)

def operand(text, i):
    # The shift operand starting at text[i]: (token, None) when it is ONE identifier or number that ends the
    # operand, else (None, why). `<<` binds looser than + - * / % and tighter than everything after it, so the
    # token ends the operand exactly when the next code character is none of those (nor a call, index, member
    # access or a further shift).
    n = len(text)
    while i < n and text[i].isspace():
        i += 1
    m = num_re.match(text, i) or ident_re.match(text, i)
    if not m:
        return None, "the operand is not a single identifier or number (%r)" % text[i:i + 12].split('\n')[0]
    j = m.end()
    while j < n and text[j].isspace():
        j += 1
    nxt = text[j:j + 2]
    if j < n and (text[j] in '+-*/%([.' or nxt in ('<<', '>>') or text[j].isalnum() or text[j] == '_'):
        return None, "the operand continues past %s (%r)" % (m.group(0), text[i:j + 8].replace('\n', ' '))
    return m.group(0), None

for f in files:
    rel = f.relative_to(deps_dir.parent).as_posix()
    try:
        text = strip_comments(f.read_bytes().decode("utf-8", errors="replace"))
    except OSError as e:
        sys.exit(f"cannot read {rel}: {e}: a file the audit could not read is not a clean file")
    # Ordinal map for every identifier declared in any enum { … } block in this file. A later
    # block overwrites an earlier one on a name collision, same as C's last-definition-wins scope.
    ordmap = {}
    for m in enum_block_re.finditer(text):
        ordv = 0   # None once an initializer could not be read: the implicit members after it are unknown too
        for part in m.group(1).split(','):
            part = part.strip()
            if not part:
                continue
            if '=' in part:
                name, val = (p.strip() for p in part.split('=', 1))
                ordv = c_int(val)
            else:
                name = part
            if not re.match(r'^[A-Za-z_]\w*$', name):
                continue
            ordmap[name] = ordv
            ordv = None if ordv is None else ordv + 1
    for sm in shift_re.finditer(text):
        lineno = text.count('\n', 0, sm.start()) + 1
        lit = '1' + sm.group('suffix')
        # 32-bit long on LLP64: an unsigned 1 may shift by up to 31; a signed 1 by up to 30 (31 reaches the sign bit)
        limit = 32 if 'u' in lit.lower() else 31
        tok, why = operand(text, sm.end())
        if tok is None:
            print(f"UNRESOLVED\t{rel}\t{lineno}\t-\t{why}\t{lit}\t{limit}")
            continue
        val = c_int(tok) if tok[0].isdigit() else ordmap.get(tok)
        if val is None:
            print(f"UNRESOLVED\t{rel}\t{lineno}\t{tok}\tcould not resolve {tok}'s ordinal statically (unknown, or after a non-literal enumerator initializer)\t{lit}\t{limit}")
        elif val >= limit:
            print(f"BAD\t{rel}\t{lineno}\t{tok}\t{val}\t{lit}\t{limit}")
        else:
            print(f"OK\t{rel}\t{lineno}\t{tok}\t{val}\t{lit}\t{limit}")
PYEOF
# M0 — the audit's own control. Each shape below is one the previous per-line, first-token audit passed (1UL << 32,
# an operand continued by `+ 1` or onto the next line, a parenthesised operand, an implicit enumerator after a
# non-literal initializer); each must now be BAD or UNRESOLVED, while the plainly safe shifts stay OK. g() is the
# other `long` spellings: unsigned ones (`1ul`, `1LU`, `1lu`, `1Ul`) are held to < 32 and the signed `1L`/`1l` to < 31,
# while `1ULL`/`1LL` (64 bits on every model) are not shift sites at all.
M0="$TMP/shiftwidth-m0/deps"; mkdir -p "$M0/x"
cat > "$M0/x/s.c" <<'CEOF'
enum Tok { A = 0, B = 1 << 5, C, D = 3, E };
unsigned long f( int n ) {
    return 1UL << 32 | 1UL << 31 + 1 | 1UL <<
        40 | 1UL << ( 2 ) | 1UL << C | 1UL << E | 1UL << 0x1f | 1UL << 5, 0;
}
long g( void ) {
    return 1ul << 33 | 1LU << 34 | 1L << 31 | 1l << 30 | 1lu << 31 | 1Ul << 3 | 1ULL << 40 | 1LL << 40;
}
CEOF
m0got="$( python3 "$TMP/shiftwidth.py" "$M0" 2>&1 | cut -f1,3,4 | tr '\t\n' ': ' )"
m0want='BAD:3:32 UNRESOLVED:3:- BAD:3:40 UNRESOLVED:4:- UNRESOLVED:4:C OK:4:E OK:4:0x1f OK:4:5 BAD:7:33 BAD:7:34 BAD:7:31 OK:7:30 OK:7:31 OK:7:3 '
if [ "$m0got" = "$m0want" ]; then
    ok "M0: the shift-width audit rejects the 5 shapes a first-token, per-line audit passed (numeric 32, \`31 + 1\`, 40 on the next line, \`( 2 )\`, an enumerator after a non-literal initializer) and passes 3 safe shifts; in the other long spellings it rejects \`1ul << 33\`, \`1LU << 34\` and signed \`1L << 31\`, passes \`1l << 30\`, \`1lu << 31\` and \`1Ul << 3\`, and skips \`1ULL\`/\`1LL\`"
else
    no "M0: the shift-width audit's own control: got [$m0got], want [$m0want]"
fi
m0empty="$TMP/shiftwidth-m0/empty"; mkdir -p "$m0empty"
if python3 "$TMP/shiftwidth.py" "$m0empty" >/dev/null 2>&1; then
    no "M0: the audit passed a tree with no *.c/*.h (it read nothing)"
else
    ok "M0: the audit refuses a tree with no *.c/*.h rather than report zero sites"
fi
python3 "$TMP/shiftwidth.py" "$DEPS_DIR" > "$TMP/shiftwidth.out" 2>"$TMP/shiftwidth.err"; mrc=$?
if [ "$mrc" != 0 ] || [ -s "$TMP/shiftwidth.err" ]; then
    no "M: the shift-width audit did not complete (rc=$mrc): $( head -3 "$TMP/shiftwidth.err" | tr '\n' ' ' )"
else
    mBad=0; mUnresolved=0
    while IFS=$'\t' read -r kind rel lineno tok val lit limit; do
        case "$kind" in
            BAD)
                mBad=$(( mBad + 1 ))
                no "M: $rel:$lineno — \`$lit << $tok\` shifts by $val (>= $limit): undefined behaviour on LLP64 (long is 32 bits there); use a 64-bit literal (1ULL / 1LL)"
                ;;
            UNRESOLVED)
                mUnresolved=$(( mUnresolved + 1 ))
                no "M: $rel:$lineno — \`$lit << …\`: $val; cannot prove this shift is in range"
                ;;
        esac
    done < "$TMP/shiftwidth.out"
    if [ "$mBad" = 0 ] && [ "$mUnresolved" = 0 ]; then
        ok "M: no \`long\` 1 shifted past its 32-bit width (unsigned >= 32, signed >= 31) or by an operand the audit cannot establish under third_party/deps/ ($( wc -l < "$TMP/shiftwidth.out" | tr -d ' ' ) bare-long-1 shift site(s) checked)"
    fi
fi

# ── verdict ─────────────────────────────────────────────────────────────────────────────────────
if [ "$fail" = 0 ]; then
    echo "ALL PASS"
else
    echo "vendorpatchcheck: FAILURES above"
    exit 1
fi
