#!/usr/bin/env bash
# fieldaffinitycheck.sh — gate for --field-affinity, the CACHE-LOCALITY lens.
#
# Fixture test/fieldaffinityfix/ has HAND-COMPUTED layouts (every offset is written out in hot.h, so this
# gate asserts numbers a human derived, not numbers the binary produced):
#   Particle   80 B — x/y/z at 0/4/8, tagA..tagF at 16..56 (line 0 exactly full), vx/vy/vz at 64/68/72.
#                     integrateParticle and dampParticle each co-access x,y,z,vx,vy,vz, so dist(x,vx) is
#                     EXACTLY 64 -> Chilimbi wt = (64-64)/64 = 0.00 and split-line must fire with fns=2.
#                     dist(z,vx) = 56 -> wt = 0.12 > 0, so that pair must NOT fire: the threshold is a
#                     wt==0 fact ("no field order can share a line"), not a preference.
#   Straddler  80 B — payload (double[2], 16 B) at offset 56 CROSSES the 64 B boundary -> straddle fires.
#                     headA/trailer are 72 B apart at wt 0.00 but only ONE function co-accesses them, so
#                     the min_fns=2 threshold must keep that pair OUT of the findings.
#   Compact    16 B — three co-accessed floats already inside one line: the NEGATIVE case. Nothing may
#                     fire. "Fire only where you can say which way is bad" — there is no bad direction
#                     here, and the tempting advice (pack tighter / sort by size) is the non-monotonic
#                     move this lens refuses to emit at all.
#   LeftBox/RightBox — both declare a field named `slot`, so the two `->slot` sites must be REFUSED and
#                     counted in amb_skipped=2. An under-count is the contract; a mis-attribution is not.
#
# The gate also pins the two HONESTY surfaces the design is built on: the header must carry
# counts_floor / model="lp64-approx" / weighting="fanin-floor" / block, the legend must CITE Chilimbi
# PLDI 1999 and Hundt CGO 2006 rather than claim the affinity graph or the separation weight as new, and
# <validate> must report an uninstrumented struct as such instead of emitting nothing.
#
# Usage:  bash test/fieldaffinitycheck.sh [BIN]  |  RIPWIRE_BIN=build/ripwire bash test/fieldaffinitycheck.sh
# Exits non-zero on any failure; prints PASS/FAIL per check, ALL PASS on success.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
FIX="$ROOT/test/fieldaffinityfix"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
[ -d "$FIX" ] || { echo "no test/fieldaffinityfix dir — fixture missing"; exit 2; }
cd "$ROOT"

echo "fieldaffinitycheck: BIN=$BIN  CORPUS=test/fieldaffinityfix"

"$BIN" "$FIX" --field-affinity --no-cache >"$TMP/out.xml" 2>"$TMP/err.txt"; rc=$?
[ "$rc" = 0 ] || { echo "  FAIL  --field-affinity exited $rc"; cat "$TMP/err.txt"; exit 1; }
OUT="$( cat "$TMP/out.xml" )"

# the <s> element for one struct name, sliced out so a later struct's attributes cannot satisfy an
# assertion about an earlier one (the whole document is one line — G4 minified XML).
sect(){ printf '%s' "$OUT" | tr '<' '\n' | awk -v want="$1" '
    /^s n="/ { inside = ( $0 ~ ("^s n=\"" want "\"") ) }
    inside   { print }
'; }
has(){ printf '%s' "$1" | grep -q -- "$2"; }

# ── 1) hand-computed geometry survives the model ─────────────────────────────────────────────────────
P="$( sect Particle )"
if has "$P" 'n="x" acc="3" fns="2" sz="4" off="0" ln="0"' \
   && has "$P" 'n="vx" acc="3" fns="2" sz="4" off="64" ln="1"' \
   && has "$P" 'size="80" align="8" lines="2"'
then ok 'Particle geometry matches the hand-computed layout (x@0 line0, vx@64 line1, size 80 align 8, 2 lines)'
else no 'Particle geometry wrong'; printf '%s\n' "$P" | head -20
fi

# ── 2) Chilimbi's separation weight, at three distances (the CITED formula, reproduced) ───────────────
if has "$P" 'a="x" b="vx" fns="2" w="2" dist="64" wt="0.00"' \
   && has "$P" 'a="x" b="y" fns="2" w="2" dist="4" wt="0.94"' \
   && has "$P" 'a="x" b="z" fns="2" w="2" dist="8" wt="0.88"'
then ok 'wt = (64 - dist)/64 reproduced at dist 64 -> 0.00, dist 8 -> 0.88, dist 4 -> 0.94 (Chilimbi PLDI 1999)'
else no 'separation weight arithmetic wrong'; printf '%s\n' "$P" | grep '^pair' | head
fi

# ── 3) split-line fires on exactly the wt==0 pairs, and NOT on the wt>0 ones ──────────────────────────
if has "$P" 'k="split-line" f="x" g="vx" dist="64" wt="0.00" fns="2"' \
   && has "$P" 'k="split-line" f="y" g="vy" dist="64" wt="0.00" fns="2"' \
   && has "$P" 'k="split-line" f="z" g="vz" dist="64" wt="0.00" fns="2"'
then ok 'split-line fires on the three 64-byte-apart co-accessed pairs'
else no 'split-line did not fire on x/vx, y/vy, z/vz'; printf '%s\n' "$P" | grep '^finding'
fi
if printf '%s' "$P" | grep '^finding' | grep -q 'f="z" g="vx"'
then no 'split-line fired on z/vx (dist 56, wt 0.12) — the threshold is wt==0, not "far-ish"'
else ok 'split-line does NOT fire on z/vx (dist 56, wt 0.12 > 0) — a fact, not a preference'
fi

# ── 4) straddle fires on the line-crossing field, with its hand-computed offset/size ──────────────────
S="$( sect Straddler )"
if has "$S" 'k="straddle" f="payload" off="56" sz="16" crosses="1"'
then ok 'straddle fires on payload (16 B at offset 56 crosses the 64 B boundary)'
else no 'straddle finding missing/wrong'; printf '%s\n' "$S" | grep '^finding'
fi

# ── 5) the min_fns threshold keeps a single-witness wt=0 pair OUT of the findings ─────────────────────
if has "$S" 'a="headA" b="trailer" fns="1" w="1" dist="72" wt="0.00"' \
   && ! ( printf '%s' "$S" | grep '^finding' | grep -q 'f="headA" g="trailer"' )
then ok 'headA/trailer is at wt 0.00 but has ONE co-accessing function — reported as a pair, not as a finding'
else no 'min_fns threshold not honoured for headA/trailer'; printf '%s\n' "$S" | grep -E '^pair|^finding'
fi

# ── 6) THE NEGATIVE CASE: three co-accessed fields already inside one line -> nothing fires ───────────
C="$( sect Compact )"
if has "$C" 'findings="0"' && ! ( printf '%s' "$C" | grep -q '^finding' )
then ok 'Compact fires NOTHING (co-accessed fields already share a line — no defensible direction)'
else no 'Compact produced a finding — the lens fired where it cannot say which way is bad'; printf '%s\n' "$C"
fi

# ── 7) ambiguity is REFUSED and COUNTED, never guessed ────────────────────────────────────────────────
if has "$OUT" 'amb_skipped="2"'
then ok 'the two `->slot` sites (declared by LeftBox AND RightBox) are refused and tallied in amb_skipped=2'
else no "amb_skipped wrong: $( printf '%s' "$OUT" | grep -o 'amb_skipped="[0-9]*"' )"
fi
if ( sect LeftBox | grep -q 'n="slot"' ) || ( sect RightBox | grep -q 'n="slot"' )
then no 'an ambiguous field was attributed to an aggregate anyway — a mis-attribution, not an under-count'
else ok 'neither LeftBox nor RightBox claims the ambiguous `slot` field'
fi

# ── 8) the header carries every honesty attribute the design promises ─────────────────────────────────
missing=""
for a in 'block="64"' 'model="lp64-approx"' 'counts_floor="1"' 'weighting="fanin-floor"' 'min_fns="2"' 'capped="'; do
    has "$OUT" "$a" || missing="$missing $a"
done
[ -z "$missing" ] && ok 'header discloses block/model/counts_floor/weighting/min_fns/capped' \
                  || no "header missing:$missing"

# ── 9) the legend CITES the prior art instead of claiming it ──────────────────────────────────────────
if has "$OUT" 'Chilimbi' && has "$OUT" 'PLDI 1999' && has "$OUT" 'Hundt' && has "$OUT" 'CGO 2006' \
   && has "$OUT" 'ADVICE ONLY'
then ok 'legend cites Chilimbi (PLDI 1999) and Hundt (CGO 2006) and states ADVICE ONLY'
else no 'legend does not cite the prior art / does not state the advice-only posture'
fi

# ── 10) exactly two finding kinds exist — no packing or reordering advice is emitted, ever ────────────
kinds="$( printf '%s' "$OUT" | tr '<' '\n' | grep '^finding ' | sed -E 's/.*k="([^"]*)".*/\1/' | sort -u | tr '\n' ' ' )"
case "$kinds" in
    "split-line straddle "|"split-line "|"straddle "|"")
        ok "only the two defensible finding kinds are emitted (saw: ${kinds:-none})" ;;
    *)  no "an unexpected finding kind appeared: $kinds (pack/reorder advice is non-monotonic and must not ship)" ;;
esac

# ── 11) the PMC bridge reports an uninstrumented struct AS SUCH, never as silence ─────────────────────
if has "$P" 'status="uninstrumented"' && has "$P" 'RIPWIRE_PROFILE=ON'
then ok 'validate reports the fixture as uninstrumented and names the way to instrument it'
else no 'validate did not disclose the uninstrumented state'; printf '%s\n' "$P" | grep '^validate'
fi

# ── 12) determinism + well-formedness (the two standing contracts) ────────────────────────────────────
"$BIN" "$FIX" --field-affinity --no-cache >"$TMP/a.xml" 2>/dev/null
"$BIN" "$FIX" --field-affinity --no-cache >"$TMP/b.xml" 2>/dev/null
cmp -s "$TMP/a.xml" "$TMP/b.xml" && ok 'two runs are byte-identical (determinism)' || no 'output is not deterministic'
if command -v xmllint >/dev/null 2>&1; then
    xmllint --noout "$TMP/out.xml" 2>"$TMP/xml.err" && ok 'output is well-formed XML' \
        || { no 'xmllint rejected the output'; cat "$TMP/xml.err"; }
else
    echo "  SKIP  xmllint not installed — well-formedness unchecked"
fi

# ── 13) the =STRUCT form narrows the REPORT but not the AMBIGUITY UNIVERSE ────────────────────────────
"$BIN" "$FIX" --field-affinity=Particle --no-cache >"$TMP/one.xml" 2>/dev/null
ONE="$( cat "$TMP/one.xml" )"
if has "$ONE" 'sym="Particle"' && has "$ONE" 'shown="1"' && has "$ONE" 'amb_skipped="2"' \
   && ! ( printf '%s' "$ONE" | tr '<' '\n' | grep -q '^s n="Straddler"' )
then ok '--field-affinity=Particle narrows to one struct and KEEPS the corpus-wide amb_skipped=2'
else no '--field-affinity=STRUCT narrowing wrong'; printf '%s' "$ONE" | tr '<' '\n' | grep '^fieldaffinity\|^s n='
fi

# ── 14) a filter that names nothing modelable REFUSES loudly (an empty report would read as a claim) ──
"$BIN" "$FIX" --field-affinity=NoSuchAggregate --no-cache >"$TMP/none.xml" 2>"$TMP/none.err"; rc=$?
if [ "$rc" = 1 ] && grep -q 'no indexed C-family struct/class named' "$TMP/none.err"
then ok 'an unknown struct refuses (exit 1) instead of emitting an empty report that reads as "no co-access"'
else no "unknown-struct refusal wrong (exit $rc): $( cat "$TMP/none.err" )"
fi

# ── 15) purely additive: a flagless run is untouched by any of this ───────────────────────────────────
"$BIN" "$FIX" --no-cache >"$TMP/plain.xml" 2>/dev/null
# Match the ELEMENT, not the word: every fixture path contains "fieldaffinityfix", so a bare word match
# fails on its own corpus — which is how this assertion first went red.
grep -q '<fieldaffinity' "$TMP/plain.xml" && no 'the flagless map leaked field-affinity output' \
                                          || ok 'the flagless map is untouched (G5: every flag is purely additive)'

# ── 16) the validation harness compiles — a hook nobody can build is not a hook ───────────────────────
BENCH="$ROOT/bench/bench_field_ab.cpp"
if [ ! -f "$BENCH" ]; then
    no 'bench/bench_field_ab.cpp is missing — the PMC validation half has no harness'
elif command -v c++ >/dev/null 2>&1; then
    if c++ -fsyntax-only -std=c++23 "$BENCH" -I"$ROOT/src" -I"$ROOT/src/infra" -I"$ROOT/third_party" 2>"$TMP/bench.err"
    then ok 'bench/bench_field_ab.cpp compiles against src/infra/profilePmc.h (the counter backend it validates with)'
    else no 'bench/bench_field_ab.cpp does not compile'; head -20 "$TMP/bench.err"
    fi
else
    echo "  SKIP  no c++ on PATH — validation harness compile unchecked"
fi

# ── 17) it runs on ripwire's own source, and the static->PMC bridge finds a real scope there ──────────
"$BIN" "$ROOT/src" --field-affinity >"$TMP/self.xml" 2>/dev/null; rc=$?
if [ "$rc" = 0 ] && grep -q '<fieldaffinity' "$TMP/self.xml"; then
    ok "runs on ripwire's own source (exit 0)"
    if grep -q 'status="instrumented"' "$TMP/self.xml"; then
        ok 'the static hypothesis names at least one real PROFILE_SCOPE to validate against (the offset->field->function->scope path closes)'
    else
        # NOT a failure: a tree with no PROFILE_SCOPE in any co-accessing function is a legitimate state.
        echo "  SKIP  no co-accessing function sits inside a PROFILE_SCOPE in this tree"
    fi
else
    no "--field-affinity on src/ failed (exit $rc)"
fi

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES"
exit "$fail"
