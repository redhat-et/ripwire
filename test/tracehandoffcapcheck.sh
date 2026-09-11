#!/usr/bin/env bash
# tracehandoffcapcheck.sh — the two SILENT caps in the verbs an agent reaches for when it is already in
# trouble: `--from-trace` (a stack trace in hand) and `--handoff` (a packet a successor will act on).
#
# docs/METHODOLOGY.md §9 #4 ("honesty lives in attributes"): a cut that changes the ANSWER and says
# nothing reads to the caller as "that is all there is". Two such cuts were measured on 2026-09-10:
#
#   (A) src/tracelocus.h kNameCandidateCap (8) bounds the NAME LADDER — the ordered, progressively-less-
#       qualified spellings of one frame's function name that traceResolveByName probes. The header called
#       it "a bound, never a silent cap on results", on the reasoning that exhausting it merely degrades
#       the frame to line-enclosure with resolved_by="line" stamped. That reasoning is wrong, because the
#       ladder is built from SUFFIXES: the shortest, most likely-to-resolve spelling — the bare method
#       name — is the LAST rung, so it is exactly what a truncation removes. A Java/Kotlin frame in a
#       package eight segments deep therefore never gets its own name probed. Measured on this gate's own
#       fixture against the pre-fix binary: the deep-package spelling of a frame binds rank 1 to
#       `warmUpTheCache` (resolved_by="line" — the WRONG symbol, served with its full body), while the
#       identical frame spelled with a shallow package binds to `handleTheRequestNow` (resolved_by="name",
#       with line_encloses="warmUpTheCache" disclosing the very disagreement the deep answer hid). Same
#       file, same line, same corpus; only the ladder length differs. Now the affected rows carry
#       name_ladder_capped="1" name_ladder_total="N" — present ONLY when the ladder was BOTH truncated and
#       exhausted, so a frame that bound on rung 3 (the overwhelming majority) still costs zero bytes.
#
#   (B) src/handoff.h kHandoffSymbolsPerFile (6) cuts the <s n=.../> rows inside each <verified><f> — the
#       DISK-TRUTH half of a continuation packet, the section whose whole contract is "this is what the
#       change set is". It was silent, and it fires on the typical case, not a tail: a two-file diff of
#       ordinary source files listed 12 symbols out of 44 (73% withheld) beside no marker at all. Now the
#       <f> that was cut carries syms_capped="1" syms_total="N"; an <f> under the cap carries neither.
#
# Every arm asserts THREE things, the discipline test/capdisclosurecheck.sh set:
#   1. CROSSING — the fixture really crosses the cap, proven WITHOUT reading the new attribute (arm A by
#      the deep-vs-shallow answer contrast, arm B against the flagless map's own count for that file).
#      A fixture sized AT the cap tests nothing.
#   2. DISCLOSURE — the crossed answer carries the marker, with the true pre-cut total beside it.
#   3. SILENCE — the same verb on an UNCROSSED fixture carries neither attribute.
#
# MUTATION CONTROL: assertion 2 of each arm is exactly what a revert of its fix removes, and assertion 1
# proves the fixture still reaches the reverted code. Run this gate against a binary built from the parent
# commit and A2/B2 must FAIL while A1/B1 still PASS — that is the red run this gate was written from.
# (A3/B3 pass on the parent too, by construction: silence is what the parent had. They exist to stop the
# fix from becoming a tax on every answer, which is a regression the red run cannot show.)
#
# Usage:
#   test/tracehandoffcapcheck.sh
#   RIPWIRE_BIN=base/ripwire bash test/tracehandoffcapcheck.sh     # the RED run
#
# Exits non-zero on any failure; prints PASS/FAIL per check and ALL PASS on success.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "tracehandoffcapcheck: python3 required"; exit 2; }
command -v git     >/dev/null 2>&1 || { echo "tracehandoffcapcheck: git required"; exit 2; }

echo "tracehandoffcapcheck: BIN=$BIN"
run(){ "$BIN" "$@" 2>/dev/null; }

# ===================================================================================================
# (A) the frame name ladder — --from-trace / kNameCandidateCap
# ===================================================================================================
echo "-- (A) name ladder cap (kNameCandidateCap, src/tracelocus.h)"

JFIX="$TMP/jfix"
PKG="$JFIX/src/main/java/com/example/service/internal/deep/nest/pkg"
mkdir -p "$PKG" "$JFIX/traces"
cat > "$PKG/RequestHandler.java" <<'EOF'
package com.example.service.internal.deep.nest.pkg;

public class RequestHandler
{
    public void warmUpTheCache()
    {
        int a = 1;
        int b = a + 1;
        System.out.println( b );
    }

    public void handleTheRequestNow()
    {
        int x = 0;
        x = x + 1;
        System.out.println( x );
    }
}
EOF

# BOTH traces name handleTheRequestNow and BOTH carry the same STALE line (7 — inside warmUpTheCache),
# which is the case the name resolver exists for: a trace from a binary that predates the checkout. The
# only difference is how deep the package spelling is, i.e. how long the ladder has to be.
#   deep    com.example.service.internal.deep.nest.pkg.RequestHandler.handleTheRequestNow -> 9 rungs > 8
#   shallow pkg.RequestHandler.handleTheRequestNow                                        -> 3 rungs
cat > "$JFIX/traces/deep.txt" <<'EOF'
Exception in thread "main" java.lang.NullPointerException
	at com.example.service.internal.deep.nest.pkg.RequestHandler.handleTheRequestNow(RequestHandler.java:7)
EOF
cat > "$JFIX/traces/shallow.txt" <<'EOF'
Exception in thread "main" java.lang.NullPointerException
	at pkg.RequestHandler.handleTheRequestNow(RequestHandler.java:7)
EOF

run "$JFIX" --from-trace="$JFIX/traces/deep.txt"    > "$TMP/a_deep.xml"
run "$JFIX" --from-trace="$JFIX/traces/shallow.txt" > "$TMP/a_shallow.xml"

python3 - "$TMP/a_deep.xml" "$TMP/a_shallow.xml" <<'PY' > "$TMP/a.res" 2>&1
import re, sys
deep    = open(sys.argv[1], encoding="utf-8", errors="replace").read()
shallow = open(sys.argv[2], encoding="utf-8", errors="replace").read()

def rank1(doc):
    m = re.search(r'<frame rank="1"[^>]*>', doc)
    return m.group(0) if m else ""

d1, s1 = rank1(deep), rank1(shallow)
if not d1 or not s1:
    print("PROBE_BROKEN deep=%r shallow=%r" % (d1[:120], s1[:120])); raise SystemExit

def attr(row, name):
    m = re.search(r'\b%s="([^"]*)"' % name, row)
    return m.group(1) if m else None

# 1. CROSSING — the cut CHANGED THE ANSWER, shown without reading the new attribute: the same frame,
#    same stale line, binds to a different symbol by a different route purely because the ladder ran out.
crossed = ( attr(d1, "n") == "warmUpTheCache"     and attr(d1, "resolved_by") == "line"
        and attr(s1, "n") == "handleTheRequestNow" and attr(s1, "resolved_by") == "name" )
print("A1 %s crossing: deep rank1=%s/%s  shallow rank1=%s/%s"
      % ("OK" if crossed else "NO", attr(d1,"n"), attr(d1,"resolved_by"), attr(s1,"n"), attr(s1,"resolved_by")))

# 2. DISCLOSURE — the row whose ladder ran out says so, and names the pre-cut rung count.
cap, tot = attr(d1, "name_ladder_capped"), attr(d1, "name_ladder_total")
print("A2 %s disclosure: name_ladder_capped=%s name_ladder_total=%s (want 1 / 9)"
      % ("OK" if cap == "1" and tot == "9" else "NO", cap or "<absent>", tot or "<absent>"))

# 2b. the legend states the fourth cause of resolved_by="line", and only when a ladder actually ran out.
print("A2b %s legend: deep=%s shallow=%s"
      % ("OK" if ("name_ladder_capped" in deep.split("<trace")[0]
                  and "name_ladder_capped" not in shallow.split("<trace")[0]) else "NO",
         "name_ladder_capped" in deep.split("<trace")[0],
         "name_ladder_capped" in shallow.split("<trace")[0]))

# 3. SILENCE — the short ladder pays nothing, anywhere in the bundle.
print("A3 %s silence: shallow bundle mentions name_ladder=%s"
      % ("OK" if "name_ladder" not in shallow else "NO", "name_ladder" in shallow))
PY
while read -r tag verdict rest; do
    [ "$verdict" = OK ] && ok "$tag $rest" || no "$tag $rest"
done < <( grep -E '^A[0-9]b? ' "$TMP/a.res" )
grep -q PROBE_BROKEN "$TMP/a.res" && no "(A) --from-trace probe broken: $( cat "$TMP/a.res" )"

# ===================================================================================================
# (B) the verified symbols-per-file rows — --handoff / kHandoffSymbolsPerFile
# ===================================================================================================
echo "-- (B) verified symbols-per-file cap (kHandoffSymbolsPerFile, src/handoff.h)"

HFIX="$TMP/hfix"
mkdir -p "$HFIX"
# wide.c is written PAST the cap by computation, not by eye; narrow.c stays comfortably under it.
python3 - "$HFIX" <<'PY'
import os, sys
d = sys.argv[1]
CAP = 6
wide = "".join("int wideFn%02d( int a )\n{\n    return a + %d;\n}\n" % (i, i) for i in range(12))
assert wide.count("int wideFn") > CAP
narrow = "".join("int narrowFn%02d( int a )\n{\n    return a - %d;\n}\n" % (i, i) for i in range(3))
assert narrow.count("int narrowFn") < CAP
open(os.path.join(d, "wide.c"), "w").write(wide)
open(os.path.join(d, "narrow.c"), "w").write(narrow)
PY
(
    cd "$HFIX" || exit 1
    git init -q .
    git config user.email tracehandoffcapcheck@example.invalid
    git config user.name  tracehandoffcapcheck
    git add -A
    git -c commit.gpgsign=false commit -qm "fixture base"
) >/dev/null 2>&1 || { no "(B) could not build the git fixture"; }
# a real, ordinary edit to BOTH files — this is the diff the packet reports on
printf 'int wideFnEdited( int a )\n{\n    return a;\n}\n'   >> "$HFIX/wide.c"
printf 'int narrowFnEdited( int a )\n{\n    return a;\n}\n' >> "$HFIX/narrow.c"

run "$HFIX" --handoff > "$TMP/b_handoff.xml"
run "$HFIX"           > "$TMP/b_map.xml"

python3 - "$TMP/b_handoff.xml" "$TMP/b_map.xml" <<'PY' > "$TMP/b.res" 2>&1
import re, sys
packet = open(sys.argv[1], encoding="utf-8", errors="replace").read()
mapdoc = open(sys.argv[2], encoding="utf-8", errors="replace").read()
CAP = 6

def files_of(doc):
    out = {}
    for m in re.finditer(r'<f p="([^"]+)"([^>]*)>(.*?)</f>', doc, re.S):
        out[m.group(1)] = (m.group(2), len(re.findall(r'<s\b', m.group(3))))
    return out

# the packet's <verified> half only — <heuristic> has no <f> rows, but scope it anyway so the parse
# cannot drift onto a future element that reuses the tag.
ver = re.search(r'<verified.*?</verified>', packet, re.S)
if not ver:
    print("PROBE_BROKEN no <verified> in packet: %r" % packet[-400:]); raise SystemExit
pk  = files_of(ver.group(0))
mp  = files_of(mapdoc)
if "wide.c" not in pk or "narrow.c" not in pk or "wide.c" not in mp:
    print("PROBE_BROKEN packet=%s map=%s" % (sorted(pk), sorted(mp))); raise SystemExit

w_attrs, w_shown = pk["wide.c"]
n_attrs, n_shown = pk["narrow.c"]
_, w_real = mp["wide.c"]

# 1. CROSSING — the file really has more symbols than the packet lists, per the tool's OWN map.
print("B1 %s crossing: packet lists %d of the map's %d symbols in wide.c (cap %d)"
      % ("OK" if w_shown == CAP and w_real > CAP else "NO", w_shown, w_real, CAP))

# 2. DISCLOSURE — the cut <f> says it was cut, and names the true total.
cap = re.search(r'\bsyms_capped="([^"]*)"', w_attrs)
tot = re.search(r'\bsyms_total="([^"]*)"',  w_attrs)
good = cap and cap.group(1) == "1" and tot and int(tot.group(1)) == w_real
print("B2 %s disclosure: syms_capped=%s syms_total=%s (want 1 / %d)"
      % ("OK" if good else "NO", cap.group(1) if cap else "<absent>", tot.group(1) if tot else "<absent>", w_real))

# 3. SILENCE — the uncut <f> pays nothing.
print("B3 %s silence: narrow.c shows %d symbols, attrs=%r"
      % ("OK" if ("syms_capped" not in n_attrs and "syms_total" not in n_attrs and n_shown < CAP) else "NO",
         n_shown, n_attrs.strip()))
PY
while read -r tag verdict rest; do
    [ "$verdict" = OK ] && ok "$tag $rest" || no "$tag $rest"
done < <( grep -E '^B[0-9] ' "$TMP/b.res" )
grep -q PROBE_BROKEN "$TMP/b.res" && no "(B) --handoff probe broken: $( cat "$TMP/b.res" )"

# ===================================================================================================
echo
[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; }
echo "FAILURES — see above"; exit 1
