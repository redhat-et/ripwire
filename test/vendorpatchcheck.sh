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
#
# Usage:
#   test/vendorpatchcheck.sh
#   RIPWIRE_BIN=asan/ripwire test/vendorpatchcheck.sh
#
# Exits non-zero on any failure; prints PASS/FAIL per check and ALL PASS on success.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${RIPWIRE_BIN:-$ROOT/build/ripwire}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
PATCH_DIR="$ROOT/third_party/patches"
DEPS_DIR="$ROOT/third_party/deps"
FIX="$ROOT/test/vendorpatchfix"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0

ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

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
        cpp|cuda)         echo static ;;
        python)           echo loop1 ;;
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

# ── verdict ─────────────────────────────────────────────────────────────────────────────────────
if [ "$fail" = 0 ]; then
    echo "ALL PASS"
else
    echo "vendorpatchcheck: FAILURES above"
    exit 1
fi
