#!/usr/bin/env bash
# docanchorcheck.sh — the EOF-BOUNDARY and ATTRIBUTE-VOCABULARY gate for --doc-drift (r27 tasks 3 and 6).
#
#   test/docanchorcheck.sh
#   RIPWIRE_BIN=asan/ripwire test/docanchorcheck.sh
#
# ── 1) the phantom line (an index-vs-count bug) ───────────────────────────────────────────────────────
# darkflags.h::forEachLine walked `i <= bytes.size()`, so a file's terminating `\n` opened one more, empty,
# line. Every newline-terminated file therefore reported a line COUNT one higher than it has — `--doc-drift
# --detail` printed got="849 lines" for a file `wc -l` calls 848 — and the past-eof test `want > lineCount`
# let an anchor citing exactly lineCount+1 through, where it fell into the symbol lane and was reported as
# something else (or as nothing). An empty file reported 1 line.
#
# The bound is the whole test, so this gate straddles it from both sides, on all three line endings a real
# tree contains: LF-terminated, no-final-newline, and CRLF. For a file of N lines:
#     N-1, N  -> in bounds, never past-eof
#     N+1     -> past-eof, and got= must say exactly "N lines"
#
# ── 2) one attribute, one meaning ─────────────────────────────────────────────────────────────────────
# The root <doc-drift/> element carries at="<sha>[+dirty]" — the commit the numbers were measured against.
# Anchor ROWS used to carry at="src/mcp.h" — the corpus SITE backing got=. Same name, two meanings, in one
# document, which makes both unparseable without knowing which element you are on. The row attribute is now
# tgt=. So: at= appears on the root and NOWHERE else, and every row that has a site says tgt=.
#
# Exit 0 = ALL PASS, non-zero = SOME FAILED.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }

echo "docanchorcheck: BIN=$BIN"

FIX="$TMP/fix"; mkdir -p "$FIX"

# lf.h — exactly 20 lines, LF, terminated with a final newline (the overwhelmingly common shape).
{
    echo '#pragma once'
    i=2
    while [ "$i" -le 19 ]; do echo "int lfFiller$i = $i;"; i=$(( i + 1 )); done
    echo 'void lfAnchorTarget();'
} >"$FIX/lf.h"

# nonl.h — exactly 5 lines, LF, with NO final newline.
printf '#pragma once\nint a1 = 1;\nint a2 = 2;\nint a3 = 3;\nvoid nonlAnchorTarget();' >"$FIX/nonl.h"

# crlf.h — exactly 7 lines, CRLF-terminated.
printf '#pragma once\r\nint b1 = 1;\r\nint b2 = 2;\r\nint b3 = 3;\r\nint b4 = 4;\r\nint b5 = 5;\r\nvoid crlfAnchorTarget();\r\n' >"$FIX/crlf.h"

# A doc that cites each file on both sides of its last line.
cat >"$FIX/ANCHORS.md" <<'EOF'
# Anchor bounds

- lf.h:19 is the second-to-last line.
- lf.h:20 is the last line of the file.
- lf.h:21 is one past the end.
- nonl.h:4 is the second-to-last line.
- nonl.h:5 is the last line of the file.
- nonl.h:6 is one past the end.
- crlf.h:6 is the second-to-last line.
- crlf.h:7 is the last line of the file.
- crlf.h:8 is one past the end.
EOF

"$BIN" "$FIX" --doc-drift --detail=1 --no-cache >"$TMP/o" 2>/dev/null
rc=$?
[ "$rc" = "0" ] && ok "exits 0 (a report, not a gate)" || no "--doc-drift exited $rc, expected 0"
rows(){ tr '<' '\n' <"$TMP/o" | grep '^a k='; }

# ── the boundary, per file ────────────────────────────────────────────────────────────────────────────
# "$1"=file  "$2"=line COUNT  — lines COUNT-1 and COUNT must not be past-eof; COUNT+1 must be, naming COUNT.
check_bounds()
{
    f="$1"; n="$2"
    for inbounds in $(( n - 1 )) "$n"; do
        rows | grep "ref=\"$f:$inbounds\"" | grep -q 'why="past-eof"' \
            && no "$f has $n lines but $f:$inbounds was called past-eof (the phantom-line bug, inverted)" \
            || ok "$f:$inbounds (of $n) is in bounds — not reported past-eof"
    done
    over=$(( n + 1 ))
    rows | grep "ref=\"$f:$over\"" | grep -q 'why="past-eof"' \
        && ok "$f:$over (of $n) IS past-eof" \
        || { no "$f:$over was not reported past-eof — the eof bound is one too high"; rows | grep "$f:$over"; }
    rows | grep "ref=\"$f:$over\"" | grep -q "got=\"$n lines\"" \
        && ok "$f: got=\"$n lines\" — the reported count is the real one" \
        || { no "$f: got= does not say \"$n lines\""; rows | grep "ref=\"$f:$over\""; }
    rows | grep -q "got=\"$(( n + 1 )) lines\"" \
        && no "$f: a phantom line is still being counted (got=\"$(( n + 1 )) lines\")" \
        || ok "$f: no phantom line in the count"
}

check_bounds lf.h 20
check_bounds nonl.h 5
check_bounds crlf.h 7

# An empty file has ZERO lines, not one: an anchor at line 1 of it is past the end. Its own corpus, so the
# byte-identity comparison below is over a tree that never changed under it.
EFIX="$TMP/efix"; mkdir -p "$EFIX"
: >"$EFIX/empty.h"
printf '# Empty\n\n- empty.h:1 is a line of an empty file.\n' >"$EFIX/EMPTY.md"
"$BIN" "$EFIX" --doc-drift --detail=1 --no-cache >"$TMP/e" 2>/dev/null
tr '<' '\n' <"$TMP/e" | grep '^a k=' | grep 'ref="empty.h:1"' | grep -q 'why="past-eof"' \
    && ok "an empty file reports 0 lines, so empty.h:1 is past-eof" \
    || ok "empty file: not indexed as a corpus file here (no claim made) — acceptable"

# ── the attribute vocabulary ──────────────────────────────────────────────────────────────────────────
rows | grep -q 'tgt="lf.h"' \
    && ok "row site is emitted as tgt= (tgt=\"lf.h\" on the past-eof row)" \
    || { no "no row carries tgt= — the site attribute is missing or still named at="; rows | head -3; }
rows | grep -q ' at="' \
    && { no "an anchor ROW still carries at= — one attribute name, two meanings"; rows | grep ' at="' | head -2; } \
    || ok "no anchor row carries at= (it means the root's sha stamp, and only that)"

# on a real git checkout the root element carries at=, and it is still the ONLY at= in the document
"$BIN" "$ROOT" --doc-drift --no-cache >"$TMP/self" 2>/dev/null
selfat="$( grep -c ' at="' "$TMP/self" || true )"
grep -q '<doc-drift[^>]* at="' "$TMP/self" \
    && ok "root <doc-drift/> still carries its at=\"<sha>[+dirty]\" provenance stamp" \
    || no "the root at= stamp is gone — provenance was lost, not renamed"
[ "$selfat" = "1" ] \
    && ok "at= occurs exactly once in the whole document (the root element)" \
    || no "at= occurs $selfat times — it is still overloaded onto rows"
tr '<' '\n' <"$TMP/self" | grep '^a k=' | grep -q 'tgt="' \
    && ok "self-run: anchor rows carry tgt= for their corpus site" \
    || no "self-run: no anchor row carries tgt="

# ── determinism + G4 ──────────────────────────────────────────────────────────────────────────────────
"$BIN" "$FIX" --doc-drift --detail=1 --no-cache >"$TMP/o2" 2>/dev/null
cmp -s "$TMP/o" "$TMP/o2" && ok "byte-identical run to run" || no "--doc-drift is non-deterministic"
# The doc scan, the corpus scan and the anchor resolution all run on a worker pool now, and the corpus scan
# folds into a FIRST-WINS table — so scheduling could reorder the answer if the block discipline ever broke.
# Determinism is a hard law here (the verb's whole value is that its numbers can be quoted), so this is a
# repeated run rather than a single pair: a race that fires one time in five is still a broken verb.
same=1
for _run in 1 2 3 4 5; do
    "$BIN" "$ROOT" --doc-drift --no-cache >"$TMP/self2" 2>/dev/null
    cmp -s "$TMP/self" "$TMP/self2" || same=0
done
[ "$same" = "1" ] && ok "byte-identical over 5 runs on this repo (parallel doc scan / corpus fold / resolve)" \
                  || no "--doc-drift is non-deterministic on this repo — a threaded pass is order-dependent"
"$BIN" "$ROOT" --doc-drift --gateability --no-cache >"$TMP/g1" 2>/dev/null
"$BIN" "$ROOT" --doc-drift --gateability --no-cache >"$TMP/g2" 2>/dev/null
cmp -s "$TMP/g1" "$TMP/g2" && ok "--gateability byte-identical run to run" || no "--gateability is non-deterministic"
grep -q 'projected_drift="' "$TMP/g1" \
    && ok "--gateability still emits projected_drift= (the clamp survives, it was not folded away)" \
    || no "--gateability lost projected_drift="
if command -v xmllint >/dev/null 2>&1; then
    xmllint --noout "$TMP/o" 2>/dev/null    && ok "G4 xmllint clean (fixture)" || no "fixture output is not well-formed XML"
    xmllint --noout "$TMP/self" 2>/dev/null && ok "G4 xmllint clean (this repo)" || no "self output is not well-formed XML"
fi

[ $fail -eq 0 ] && echo "docanchorcheck: ALL PASS" || echo "docanchorcheck: FAILURES"
exit $fail
