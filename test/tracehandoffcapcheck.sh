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
#   (B) src/handoff.h's symbols-per-file caps cut the <s n=.../> rows inside each <verified><f> — the
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
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
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
    if [ "$verdict" = OK ]; then ok "$tag $rest"; else no "$tag $rest"; fi
done < <( grep -E '^A[0-9]b? ' "$TMP/a.res" )
grep -q PROBE_BROKEN "$TMP/a.res" && no "(A) --from-trace probe broken: $( cat "$TMP/a.res" )"

# ===================================================================================================
# (B) the verified symbols-per-file rows — --handoff / kHandoffSymbolsPerFile
# ===================================================================================================
echo "-- (B) verified symbols-per-file caps (kHandoffSymbolsPerCodeFile / PerDocFile, src/handoff.h)"

HFIX="$TMP/hfix"
mkdir -p "$HFIX"
# The cap is TWO caps since 2026-09-10 — 50 for a code file, 12 for a prose file — so the fixture needs
# four files, and each of the four sizes is COMPUTED from the value read out of src/handoff.h. A fixture
# with a literal count is a fixture that silently stops crossing the cap the day the cap moves, which is
# exactly what happened here: the old one wrote 12 functions against a cap of 6, and at 50 it tests
# nothing at all while still printing PASS.
python3 - "$HFIX" "$ROOT/src/handoff.h" <<'PY'
import os, re, sys
d, hdr = sys.argv[1], open(sys.argv[2], encoding="utf-8").read()
def capOf(name):
    m = re.search(r'\b%s\s*=\s*(\d+)\s*;' % name, hdr)
    if not m:
        sys.exit("tracehandoffcapcheck: %s is not declared in src/handoff.h — the fixture cannot size itself" % name)
    return int(m.group(1))
CODE, DOC = capOf("kHandoffSymbolsPerCodeFile"), capOf("kHandoffSymbolsPerDocFile")
open(os.path.join(d, "caps.txt"), "w").write("%d %d\n" % (CODE, DOC))
wide = "".join("int wideFn%03d( int a )\n{\n    return a + %d;\n}\n" % (i, i) for i in range(CODE + 10))
assert wide.count("int wideFn") > CODE
narrow = "".join("int narrowFn%03d( int a )\n{\n    return a - %d;\n}\n" % (i, i) for i in range(3))
assert narrow.count("int narrowFn") < CODE
wided = "# Wide doc\n\n" + "".join("## section %03d\n\nbody\n\n" % i for i in range(DOC + 10))
assert wided.count("## section") > DOC
narrowd = "# Narrow doc\n\n" + "".join("## section %03d\n\nbody\n\n" % i for i in range(2))
assert narrowd.count("## section") < DOC
open(os.path.join(d, "wide.c"), "w").write(wide)
open(os.path.join(d, "narrow.c"), "w").write(narrow)
open(os.path.join(d, "wide.md"), "w").write(wided)
open(os.path.join(d, "narrow.md"), "w").write(narrowd)
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
printf '\n## edited section\n\nbody\n'                       >> "$HFIX/wide.md"
printf '\n## edited section\n\nbody\n'                       >> "$HFIX/narrow.md"

run "$HFIX" --handoff > "$TMP/b_handoff.xml"
run "$HFIX"           > "$TMP/b_map.xml"

python3 - "$TMP/b_handoff.xml" "$TMP/b_map.xml" "$HFIX/caps.txt" <<'PY' > "$TMP/b.res" 2>&1
import re, sys
packet = open(sys.argv[1], encoding="utf-8", errors="replace").read()
mapdoc = open(sys.argv[2], encoding="utf-8", errors="replace").read()
CODE, DOC = (int(x) for x in open(sys.argv[3], encoding="utf-8").read().split())

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
need = ["wide.c", "narrow.c", "wide.md", "narrow.md"]
if any(f not in pk for f in need) or "wide.c" not in mp or "wide.md" not in mp:
    print("PROBE_BROKEN packet=%s map=%s" % (sorted(pk), sorted(mp))); raise SystemExit

def crossing(tag, path, cap):
    attrs, shown = pk[path]
    _, real = mp[path]
    print("%s %s crossing: packet lists %d of the map's %d symbols in %s (cap %d)"
          % (tag, "OK" if shown == cap and real > cap else "NO", shown, real, path, cap))
    return attrs, real

def disclosure(tag, path, real):
    attrs, _ = pk[path]
    cap = re.search(r'\bsyms_capped="([^"]*)"', attrs)
    tot = re.search(r'\bsyms_total="([^"]*)"',  attrs)
    good = cap and cap.group(1) == "1" and tot and int(tot.group(1)) == real
    print("%s %s disclosure on %s: syms_capped=%s syms_total=%s (want 1 / %d)"
          % (tag, "OK" if good else "NO", path, cap.group(1) if cap else "<absent>",
             tot.group(1) if tot else "<absent>", real))

def silence(tag, path, cap):
    attrs, shown = pk[path]
    good = "syms_capped" not in attrs and "syms_total" not in attrs and shown < cap
    print("%s %s silence: %s shows %d symbols, attrs=%r" % (tag, "OK" if good else "NO", path, shown, attrs.strip()))

# 1-3. THE CODE CAP, on a file written past it by computation.
_, w_real = crossing("B1", "wide.c", CODE)
disclosure("B2", "wide.c", w_real)
silence("B3", "narrow.c", CODE)

# 4-6. THE PROSE CAP, which is a DIFFERENT number. Without a doc file in the fixture the split is
# untested: a build that ignored kHandoffSymbolsPerDocFile entirely would pass B1-B3 unchanged.
_, d_real = crossing("B4", "wide.md", DOC)
disclosure("B5", "wide.md", d_real)
silence("B6", "narrow.md", DOC)

# 7. THE SPLIT ITSELF. A code file with MORE symbols than the doc cap but fewer than the code cap must
# be uncut, which is the one assertion a single-cap build cannot satisfy.
_, mid_real = mp["wide.c"], mp["wide.c"][1]
print("B7 %s split: the two caps differ (code %d, prose %d) and the prose file is cut at the SMALLER one"
      % ("OK" if CODE != DOC and pk["wide.md"][1] == DOC and pk["wide.c"][1] == CODE else "NO", CODE, DOC))
PY
while read -r tag verdict rest; do
    if [ "$verdict" = OK ]; then ok "$tag $rest"; else no "$tag $rest"; fi
done < <( grep -E '^B[0-9] ' "$TMP/b.res" )
grep -q PROBE_BROKEN "$TMP/b.res" && no "(B) --handoff probe broken: $( cat "$TMP/b.res" )"

# ===================================================================================================
echo
[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; }
echo "FAILURES — see above"; exit 1
