#!/usr/bin/env bash
# grepandcheck.sh — gate for G3 (2026-08-15 harvest, report-ugrep §F2): --and=/--not=/--grep-scope= —
# a flat boolean term list layered over --grep's already-collected hits.
#
# Asserts:
#   (1) semantics: --and=B keeps only lines carrying BOTH the base pattern and B; --not=C excludes lines
#       carrying C; --grep-scope=file widens "same line" to "same file, any line"
#   (2) refusals: --and=/--not=/--grep-scope= alone (no --grep), combined with --regex=, and an empty
#       --and=/--not= value, all refuse at exit 1 naming the flag
#   (3) ORACLE: the AND result equals a POST-FILTER of the un-AND-ed scan (same oracle SHAPE as
#       test/grepscancheck.sh's --no-prefilter check) — computed independently of search.h's own
#       grepApplyBooleanTerms, so the gate cannot be biased by the code it is checking
#   (4) terms=/scope=/terms_suppressed= are disclosed on the root, and the legend defines them in-band
#   (5) determinism: an AND/NOT run is byte-identical across two invocations
#   (6) [KILL CONDITION] 6 frozen (pattern,and-term) pairs, each with a known GOLD line: the gold line
#       must survive the AND filter. REFUTED if the gold is dropped on >= 2 of 6 pairs (the round's own
#       kill bar) — this arm reports PASS/FAIL per pair AND an explicit refutation verdict, never just a
#       silent aggregate.
#
# Usage:
#   bash test/grepandcheck.sh                          # uses build/ripwire
#   RIPWIRE_BIN=asan/ripwire bash test/grepandcheck.sh
# Exits non-zero on any failure (including the kill condition firing); prints PASS/FAIL and ALL PASS on success.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${RIPWIRE_BIN:-$ROOT/build/ripwire}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
echo "grepandcheck: BIN=$BIN"

# G1: extract "path|line|in" rows in document order from a grouped (<f p=…><hit l=…>) grep answer, past
# the legend comment (whose own prose could false-match a naive tag regex).
rowid(){
    python3 -c '
import re, sys
xml = sys.stdin.read().split( "-->", 1 )[ -1 ]
cur = None
for tag in re.findall( r"<[^>]+>", xml ):
    m = re.match( r"<f p=\"([^\"]*)\"", tag )
    if m:
        cur = m.group( 1 ); continue
    m = re.match( r"<hit l=\"([0-9]+)\"", tag )
    if m and cur is not None:
        print( cur + ":" + m.group( 1 ) )
'
}

# ═══════════════════════════════════════════════════════════════════════════
echo "=== (1) semantics: --and=/--not=/--grep-scope= ==="
# ═══════════════════════════════════════════════════════════════════════════
SB="$TMP/andsandbox"
mkdir -p "$SB/src"
# One line carries BOTH tokens (the gold AND hit); others carry only one (AND-noise); one carries the
# base token plus the NOT token (the NOT-exclusion case).
cat >"$SB/src/mix.cpp" <<'EOF'
void goldBoth() { ANDTOKEN_A(); ANDTOKEN_B(); }
void onlyA1()   { ANDTOKEN_A(); }
void onlyA2()   { ANDTOKEN_A(); }
void onlyB1()   { ANDTOKEN_B(); }
void hasNotTok(){ ANDTOKEN_A(); NOTTOKEN_C(); }
void plainA()   { ANDTOKEN_A(); }
EOF

run(){ "$BIN" "$SB" --no-cache --grep=ANDTOKEN_A "$@" 2>/dev/null; }

AND_OUT="$( run --and=ANDTOKEN_B )"
AND_ROWS="$( printf '%s' "$AND_OUT" | rowid | wc -l | tr -d ' ' )"
printf '%s' "$AND_OUT" | grep -q 'goldBoth' \
    && [ "$AND_ROWS" = 1 ] \
    && ok "(1a) --and= keeps ONLY the line carrying both tokens (1 row: goldBoth)" \
    || { no "(1a) --and= wrong row set (rows=$AND_ROWS)"; printf '%s' "$AND_OUT" | rowid; }

NOT_OUT="$( run --not=NOTTOKEN_C )"
NOT_ROWS="$( printf '%s' "$NOT_OUT" | rowid | wc -l | tr -d ' ' )"
printf '%s' "$NOT_OUT" | grep -q 'hasNotTok' \
    && { no "(1b) --not= failed to exclude the line carrying the forbidden token"; } \
    || [ "$NOT_ROWS" = 4 ] \
    && ok "(1b) --not= excludes exactly the 1 line carrying the forbidden token (4 of 5 ANDTOKEN_A rows survive)" \
    || no "(1b) --not= wrong row count (rows=$NOT_ROWS, expected 4)"

# --grep-scope=file: put the second required token on a DIFFERENT LINE of the SAME file — line scope must
# find NOTHING (no single line ever carries both), file scope must find every SCOPETOKEN_A hit in that
# file. b.cpp is a second file with NEITHER token, so both scopes must ignore it entirely.
SB2="$TMP/andsandbox2"
mkdir -p "$SB2/src"
cat >"$SB2/src/a.cpp" <<'EOF'
void fnOne() { SCOPETOKEN_A(); }
void fnTwo() { SCOPETOKEN_A(); }
void other() { SCOPETOKEN_B(); }
EOF
cat >"$SB2/src/b.cpp" <<'EOF'
void unrelated() { NEITHERTOKEN(); }
EOF
LINE_SCOPE="$( "$BIN" "$SB2" --no-cache --grep=SCOPETOKEN_A --and=SCOPETOKEN_B 2>/dev/null | rowid | wc -l | tr -d ' ' )"
FILE_SCOPE="$( "$BIN" "$SB2" --no-cache --grep=SCOPETOKEN_A --and=SCOPETOKEN_B --grep-scope=file 2>/dev/null | rowid | wc -l | tr -d ' ' )"
[ "$LINE_SCOPE" = 0 ] \
    && ok "(1c) scope=line (default): 0 rows — the tokens never share a LINE" \
    || no "(1c) scope=line unexpectedly matched $LINE_SCOPE row(s)"
[ "$FILE_SCOPE" = 2 ] \
    && ok "(1d) scope=file: 2 rows — SCOPETOKEN_A hits count when SCOPETOKEN_B is ANYWHERE in that file" \
    || no "(1d) scope=file matched $FILE_SCOPE row(s), expected 2"

# ═══════════════════════════════════════════════════════════════════════════
echo "=== (2) refusals ==="
# ═══════════════════════════════════════════════════════════════════════════
refuse(){                                    # $1=label $2..=args
    local label="$1"; shift
    local out ec
    out="$( "$BIN" "$SB" --no-cache "$@" 2>&1 >/dev/null )"; ec=$?
    [ "$ec" = 1 ] && ok "(2) $label refuses at exit 1: $( printf '%s' "$out" | head -1 )" \
                  || no "(2) $label exited $ec, expected 1: $out"
}
refuse "--and= alone (no --grep)"            --and=x
refuse "--not= alone (no --grep)"            --not=x
refuse "--grep-scope= alone (no --grep)"     --grep-scope=file
refuse "--and= combined with --regex="       --regex='ANDTOKEN_[AB]' --and=x
refuse "--not= combined with --regex="       --regex='ANDTOKEN_[AB]' --not=x
refuse "empty --and="                        --grep=ANDTOKEN_A --and=
refuse "empty --not="                        --grep=ANDTOKEN_A --not=
refuse "unknown --grep-scope= value"         --grep=ANDTOKEN_A --grep-scope=bogus

# ═══════════════════════════════════════════════════════════════════════════
echo "=== (3) ORACLE: AND result == post-filter of the un-AND-ed scan ==="
# ═══════════════════════════════════════════════════════════════════════════
# Independent of search.h's grepApplyBooleanTerms: run the PLAIN scan, pull each hit's own matched-line
# text out of the XML (<m> CDATA), keep only the ones ALSO containing the and-term, and compare that row
# set to the --and= answer's row set.
PLAIN_XML="$( run --limit=1000 )"
python3 - "$PLAIN_XML" >"$TMP/oracle.rows" <<'PY'
import re, sys
xml = sys.argv[1].split("-->", 1)[-1]
cur = None
for fm in re.finditer(r'<f p="([^"]*)">(.*?)</f>', xml, re.S):
    path = fm.group(1)
    for hm in re.finditer(r'<hit l="(\d+)"[^>]*>(.*?)</hit>', fm.group(2), re.S):
        line = hm.group(1)
        text = "".join(re.findall(r'<m><!\[CDATA\[(.*?)\]\]></m>', hm.group(2), re.S))
        if "ANDTOKEN_B" in text:
            print(f"{path}:{line}")
PY
sort "$TMP/oracle.rows" >"$TMP/oracle.sorted"
run --and=ANDTOKEN_B --limit=1000 | rowid | sort >"$TMP/actual.sorted"
if diff -q "$TMP/oracle.sorted" "$TMP/actual.sorted" >/dev/null; then
    ok "(3) AND result == independent post-filter of the un-AND-ed scan ($( wc -l <"$TMP/actual.sorted" | tr -d ' ' ) row(s))"
else
    no "(3) AND result != post-filter oracle"; diff "$TMP/oracle.sorted" "$TMP/actual.sorted" | head -6
fi

# ═══════════════════════════════════════════════════════════════════════════
echo "=== (4) disclosure: terms=/scope=/terms_suppressed=, legend defines them ==="
# ═══════════════════════════════════════════════════════════════════════════
HDR="$( run --and=ANDTOKEN_B | grep -o '<grep[^>]*>' )"
printf '%s' "$HDR" | grep -q 'terms="ANDTOKEN_A +ANDTOKEN_B"' \
    && ok "(4a) terms= restates base+and as \"A +B\"" \
    || no "(4a) terms= missing or malformed: $HDR"
printf '%s' "$HDR" | grep -q 'scope="line"' \
    && ok "(4b) scope=\"line\" is the disclosed default" \
    || no "(4b) scope= missing: $HDR"
printf '%s' "$HDR" | grep -qE 'terms_suppressed="[0-9]+"' \
    && ok "(4c) terms_suppressed= present" \
    || no "(4c) terms_suppressed= missing: $HDR"
run --and=ANDTOKEN_B | grep -q 'terms= (present only with and/not)' \
    && ok "(4d) legend defines terms=" \
    || no "(4d) legend never defines terms="
run --and=ANDTOKEN_B | grep -q 'scope=file requires every term ANYWHERE' \
    && ok "(4e) legend defines scope=" \
    || no "(4e) legend never defines scope="
# a PLAIN run (no and/not) must stay byte-identical to before G3 — no terms=/scope= leak on the ROOT
# element specifically (the legend's own prose defines terms=/scope= in-band and would false-match a bare
# substring search over the whole answer — checked against the <grep …> open tag only).
run | grep -o '<grep [^>]*>' | grep -q ' terms=' \
    && no "(4f) a plain --grep run leaked terms= on its root element (must be purely additive)" \
    || ok "(4f) a plain --grep run's root element carries no terms= (purely additive)"

# ═══════════════════════════════════════════════════════════════════════════
echo "=== (5) determinism ==="
# ═══════════════════════════════════════════════════════════════════════════
D1="$( run --and=ANDTOKEN_B --not=NOTTOKEN_C )"
D2="$( run --and=ANDTOKEN_B --not=NOTTOKEN_C )"
[ "$D1" = "$D2" ] \
    && ok "(5) determinism: byte-identical AND+NOT output across runs" \
    || no "(5) determinism: AND+NOT output differs run to run"
printf '%s' "$D1" | xmllint --noout - 2>/dev/null \
    && ok "(5b) AND+NOT output is well-formed XML" \
    || no "(5b) AND+NOT output is malformed XML"

# ═══════════════════════════════════════════════════════════════════════════
echo "=== (6) [KILL CONDITION] 6 frozen (pattern,and-term) pairs — gold must survive ==="
# ═══════════════════════════════════════════════════════════════════════════
# A dedicated sandbox per pair: one GOLD line carrying both tokens, several NOISE lines carrying only one
# — mirrors the round brief's own moments (a staleness check scoped to one subsystem, a cache-invalid
# check, a buffer/resize guard, …) without depending on this repo's own prose staying byte-stable.
KSB="$TMP/killsandbox"
mkdir -p "$KSB/src"
cat >"$KSB/src/k.cpp" <<'EOF'
void staleMcpGold()    { PAIR1_stale(); PAIR1_mcp(); }
void staleOnlyNoiseA() { PAIR1_stale(); }
void mcpOnlyNoiseA()   { PAIR1_mcp(); }

void cacheInvalidGold(){ PAIR2_cache(); PAIR2_invalid(); }
void cacheOnlyNoiseB() { PAIR2_cache(); }

void bufferResizeGold(){ PAIR3_buffer(); PAIR3_resize(); }
void bufferOnlyNoiseC(){ PAIR3_buffer(); }

void guardLockGold()   { PAIR4_guard(); PAIR4_lock(); }
void guardOnlyNoiseD() { PAIR4_guard(); }

void indexBoundsGold() { PAIR5_index(); PAIR5_bounds(); }
void indexOnlyNoiseE() { PAIR5_index(); }

void parseErrorGold()  { PAIR6_parse(); PAIR6_error(); }
void parseOnlyNoiseF() { PAIR6_parse(); }
EOF

killcheck(){                                 # $1=label $2=pattern $3=and-term $4=gold-substring
    local label="$1" pat="$2" and="$3" gold="$4"
    local out; out="$( "$BIN" "$KSB" --no-cache --grep="$pat" --and="$and" 2>/dev/null )"
    if printf '%s' "$out" | grep -q "$gold"; then
        ok "(6) [$label] gold '$gold' survives $pat AND $and"
        return 0
    else
        no "(6) [$label] gold '$gold' DROPPED by $pat AND $and"
        return 1
    fi
}
killfails=0
killcheck "stale+mcp"       PAIR1_stale   PAIR1_mcp    staleMcpGold     || killfails=$(( killfails + 1 ))
killcheck "cache+invalid"   PAIR2_cache   PAIR2_invalid cacheInvalidGold || killfails=$(( killfails + 1 ))
killcheck "buffer+resize"   PAIR3_buffer  PAIR3_resize  bufferResizeGold || killfails=$(( killfails + 1 ))
killcheck "guard+lock"      PAIR4_guard   PAIR4_lock    guardLockGold    || killfails=$(( killfails + 1 ))
killcheck "index+bounds"    PAIR5_index   PAIR5_bounds  indexBoundsGold  || killfails=$(( killfails + 1 ))
killcheck "parse+error"     PAIR6_parse   PAIR6_error   parseErrorGold   || killfails=$(( killfails + 1 ))

echo
if [ "$killfails" -ge 2 ]; then
    no "[KILL CONDITION FIRED] gold dropped on $killfails/6 pairs (>= 2) — G3's AND/NOT theory is REFUTED"
else
    ok "[KILL CONDITION HOLDS] gold survived $(( 6 - killfails ))/6 pairs (< 2 dropped)"
fi

# ── Summary ───────────────────────────────────────────────────────────────────────────────────────
echo
if [ "$fail" -eq 0 ]; then
    echo "ALL PASS"
    exit 0
else
    echo "SOME CHECKS FAILED"
    exit 1
fi
