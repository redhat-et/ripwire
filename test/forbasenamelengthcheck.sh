#!/usr/bin/env bash
# forbasenamelengthcheck.sh — the basename field lifts every symbol of a named file by the same amount, whatever its length
# (θ10, #728; src/lexical.h basenameFieldTf / addBasenameFieldTf).
#
# WHY. The basename field (pass 1.6, kForBasenameFieldW) adds a file name's tokens to the tf of every symbol in that file. BM25
# divides tf by the symbol's OWN length norm, so the same flat tf lifted a 5-line helper several times more than the long
# function the question is about: on in-sample rows a query word naming the file sank textual's `Widget` class behind its own
# short methods (textual-02, textual-12) and vscode's TextSearchManager.search (ld-vscode-04). Pass 2.5 scales the file's tf by
# the symbol's length norm, never below the flat tf.
#
# Arms ([P] red on the flat field — main 6c018f611, or RIPWIRE_BASENAME_FLAT=1; [G] hold on both):
#   L1 [P] long target: render_all (a long function whose NAME carries the question's words) in widget.py ranks r=1 for a
#          question that also names the file, above every one of widget.py's 40 short helpers (each says `children` once)
#   L2 [G] control: RIPWIRE_BASENAME_FLAT=1 — >= 1 short helper of widget.py outranks render_all (premise: counted, FAIL on 0)
#   L3 [G] control: RIPWIRE_BASENAME_W=0 — render_all is r=1 with no field at all (the sink is the field's, not ambient rank)
#   L4 [G] short symbols keep the flat lift: every helper's s= is identical in the default and the FLAT answer (count >= 1)
#   L5 [G] the lift still reaches a file-only question: a helper of widget.py scores > 0 for a question whose only matching
#          word is the file's name (the field is on, only rescaled)
#   F1 [G] RIPWIRE_BASENAME_FLAT=0 is the scaled default, not the flat field (only 1 selects flat)
#   X1 [G] determinism: two default runs exit 0 and are byte-identical
#
# Usage:  bash test/forbasenamelengthcheck.sh [BIN]   — BIN is $1, else RIPWIRE_BIN, else build/ripwire.
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
. "$ROOT/test/lib/clean-env.sh"
unset RIPWIRE_BASENAME_W RIPWIRE_BASENAME_FLAT RIPWIRE_PATHTOK_W RIPWIRE_QSTEM
export RIPWIRE_NO_ROWLINES=1
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
TMP="$( mktemp -d "${TMPDIR:-/tmp}/forbasenamelen.XXXXXX" )"
trap 'rm -rf "$TMP"' EXIT
FAIL=0
ok(){ printf '  PASS  %s\n' "$*" || { FAIL=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; FAIL=1; }
echo "forbasenamelengthcheck: BIN=$BIN"

# ── fixture: one long target (300 body lines) among 40 short siblings in widget.py that each say `children` once, plus 300
#    short symbols in layout.py so the corpus mean length is a short symbol's. Measured on the flat field: all 40 helpers
#    outrank render_all (r=41); length-scaled and field-off: r=1. ──
R="$TMP/corpus"
mkdir -p "$R/pkg" "$R/home"
python3 - "$R" <<'PY'
import sys
r = sys.argv[1]
w = ["def render_all(children, canvas):", '    """Render every child onto the canvas."""', "    total = 0"]
for k in range(300):
    w.append(f"    total += canvas.draw_box(children, {k}, offset={k * 3}, depth={k % 7})")
w.append("    return total")
for k in range(40):
    w += ["", f"def helper_{k:02d}(x):", f"    return x.children + {k}"]
open(f"{r}/pkg/widget.py", "w").write("\n".join(w) + "\n")
o = []
for k in range(300):
    o += [f"def layout_step_{k:03d}(box):", f"    return box.width * {k} + box.height", ""]
open(f"{r}/pkg/layout.py", "w").write("\n".join(o) + "\n")
PY

Q_LONG="How does the widget render all of its children?"
Q_FILE="What lives in the widget module?"
cli(){ ( cd "$R" && HOME="$R/home" TMPDIR="$R/home/" "$@" </dev/null 2>/dev/null ); }
# rank of render_all, and the count of widget.py helpers ranked above it; or "none"
rankinfo(){ python3 -c '
import re, sys
rows = [dict(re.findall(r"(\w+)=\"([^\"]*)\"", m.group(0))) for m in re.finditer(r"<cand [^>]*>", open(sys.argv[1]).read())]
t = [int(r["r"]) for r in rows if r.get("n") == "render_all"]
if not t: print("none 0 %d" % len(rows)); sys.exit()
above = sum(1 for r in rows if r.get("n", "").startswith("helper_") and int(r["r"]) < t[0])
print("%d %d %d" % (t[0], above, len(rows)))' "$1"; }
# "name score" of every widget.py helper row
helpers(){ python3 -c '
import re, sys
for m in re.finditer(r"<cand [^>]*>", open(sys.argv[1]).read()):
    a = dict(re.findall(r"(\w+)=\"([^\"]*)\"", m.group(0)))
    if a.get("n", "").startswith("helper_"): print(a["n"], a["s"])' "$1" | sort; }

cli "$BIN" "$R" --no-cache --for="$Q_LONG" --format=candidates > "$TMP/long_on.xml"
cli env RIPWIRE_BASENAME_FLAT=1 "$BIN" "$R" --no-cache --for="$Q_LONG" --format=candidates > "$TMP/long_flat.xml"
cli env RIPWIRE_BASENAME_W=0 "$BIN" "$R" --no-cache --for="$Q_LONG" --format=candidates > "$TMP/long_off.xml"
cli "$BIN" "$R" --no-cache --for="$Q_FILE" --format=candidates > "$TMP/file_on.xml"
cli env RIPWIRE_BASENAME_FLAT=1 "$BIN" "$R" --no-cache --for="$Q_FILE" --format=candidates > "$TMP/file_flat.xml"
for f in long_on long_flat long_off file_on file_flat; do
    grep -q '<cand ' "$TMP/$f.xml" || no "premise: $f.xml has no <cand> rows (the arms below would be vacuous)"
done

echo "=== L: a long symbol of a named file keeps its rank ==="
read -r r_on above_on n_on <<<"$( rankinfo "$TMP/long_on.xml" )"
read -r r_flat above_flat n_flat <<<"$( rankinfo "$TMP/long_flat.xml" )"
read -r r_off above_off n_off <<<"$( rankinfo "$TMP/long_off.xml" )"
if [ "$r_on" = 1 ]; then ok "L1 default: render_all r=1 ($n_on rows)"; else no "L1 default: render_all r=$r_on, $above_on short helpers above it"; fi
if [ "$above_flat" -ge 1 ] 2>/dev/null; then ok "L2 control (FLAT): $above_flat short helpers outrank render_all (r=$r_flat) on the flat field"
else no "L2 control (FLAT): 0 helpers above render_all (r=$r_flat) — the fixture no longer shows the sink, L1 proves nothing"; fi
if [ "$r_off" = 1 ]; then ok "L3 control (W=0): render_all r=1 with the field off"; else no "L3 control (W=0): render_all r=$r_off (ambient rank, not the field)"; fi

echo "=== L4/L5: short symbols keep the flat lift; the field is still on ==="
helpers "$TMP/file_on.xml" > "$TMP/h_on.txt"; helpers "$TMP/file_flat.xml" > "$TMP/h_flat.txt"
nh="$( wc -l < "$TMP/h_on.txt" | tr -d ' ' )"
if [ "$nh" -ge 1 ] && cmp -s "$TMP/h_on.txt" "$TMP/h_flat.txt"; then ok "L4 $nh short helpers: s= identical default vs FLAT"
else no "L4 helper scores differ default vs FLAT (or none listed: $nh)"; diff "$TMP/h_flat.txt" "$TMP/h_on.txt" | head -5; fi
pos="$( awk '$2 > 0' "$TMP/h_on.txt" | wc -l | tr -d ' ' )"
if [ "$pos" -ge 1 ]; then ok "L5 a file-only question: $pos widget.py helpers score > 0 on the basename word"; else no "L5 no widget.py helper scores > 0 (the field is off)"; fi

echo "=== F: only FLAT=1 selects the flat field ==="
cli env RIPWIRE_BASENAME_FLAT=0 "$BIN" "$R" --no-cache --for="$Q_LONG" --format=candidates > "$TMP/long_flat0.xml"
if grep -q '<cand ' "$TMP/long_flat0.xml" && cmp -s "$TMP/long_on.xml" "$TMP/long_flat0.xml"; then ok "F1 FLAT=0 answers byte-identical to the default (scaled)"
else no "F1 FLAT=0 differs from the default (or no <cand> rows): presence alone switched the field"; fi

echo "=== X: determinism ==="
cli "$BIN" "$R" --no-cache --for="$Q_LONG" > "$TMP/x1.xml"; rc1=$?
cli "$BIN" "$R" --no-cache --for="$Q_LONG" > "$TMP/x2.xml"; rc2=$?
if [ "$rc1" -eq 0 ] && [ "$rc2" -eq 0 ] && [ -s "$TMP/x1.xml" ] && cmp -s "$TMP/x1.xml" "$TMP/x2.xml"; then ok "X1 two default --for runs succeed and are byte-identical"
else no "X1 rc=$rc1/$rc2, nondeterministic or empty --for answer"; fi

if [ "$FAIL" -ne 0 ]; then echo "forbasenamelengthcheck: FAIL"; exit 1; fi
echo "forbasenamelengthcheck: PASS"
