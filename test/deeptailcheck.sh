#!/usr/bin/env bash
# deeptailcheck.sh — the DEEP-TAIL serving contract (rank-order preservation + the file-grain tail).
#
# WHY THIS GATE EXISTS. Two measured losses on budgeted consumers of the ranked bundles (registered in
# docs/EVALS.md, "Deep-tail serving"):
#   d1  the served JSON/XML groups symbols by FILE and sorts by LINE inside the group, so a consumer that
#       truncates at a budget reads document order, not ranker order — the true per-symbol rank was
#       unrecoverable from the default bundle. Every lens-ranked signature row now carries its 1-based
#       global rank (XML ` r="N"`, JSON `"r":N`), rank-consistent with the flat --format=candidates export.
#   d2  the lens serves ranked symbol HEADS concentrated in few files, while file-grain consumers need
#       recall 20+ deep — the bundle now ends its signature-shaped sections with a FILE-GRAIN TAIL: the
#       remaining candidate files (positive lens score, not already in the head) as paths only, in the
#       best-symbol projection of the same ranking, disclosed as total=/shown=/capped= and labelled
#       weaker-than-head evidence in the legend.
#
# RED-FIRST: every d1/d2 assertion below FAILS against the prebuilt d8e257d baseline (which emits neither
# surface); each fuses presence with content bytes so a bare-exit arm cannot pass green-while-inert.
#
# Usage:  test/deeptailcheck.sh              # uses build/ripwire
#         RIPWIRE_BIN=asan/ripwire test/deeptailcheck.sh
# Exits non-zero on any failure. Does NOT edit regression.sh.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
command -v xmllint >/dev/null 2>&1 || { echo "xmllint required"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 required"; exit 2; }
echo "deeptailcheck: BIN=$BIN"

# ── fixture: 12 one-symbol files, every one matching the query, so the head/tail split is exact ─────────
# --pack-top-n=4 keeps a 4-symbol head (4 files); the remaining 8 files are the expected tail, in id
# (= path) order because every score ties — deterministic by the (score desc, id asc) contract.
# 12 files x 5 defs = 60 symbols, every one matching the query: --pack-top-n=4 keeps a one-file head
# (11 tail files); the DEFAULT head (40) keeps files w01..w08, leaving exactly w09..w12 as the tail.
CORPUS="$TMP/corpus"
mkdir -p "$CORPUS"
for i in 01 02 03 04 05 06 07 08 09 10 11 12; do
    { for j in a b c d e; do
        printf 'def widget_frobnicate_%s_%s():\n    """widget frobnicate helper %s %s"""\n    return 1\n' "$i" "$j" "$i" "$j"
    done; } > "$CORPUS/w$i.py"
done
Q="widget frobnicate helper"

XML="$( "$BIN" "$CORPUS" --no-cache --for="$Q" --pack-top-n=4 2>/dev/null )"
printf '%s' "$XML" > "$TMP/for.xml"

# ── 1) d2: the file-grain tail — present, complete, disjoint from the head ─────────────────────────────
TAILTAG="$( printf '%s' "$XML" | grep -o '<tail [^>]*>' | head -1 )"
case "$TAILTAG" in
    *'total="11"'*'shown="11"'*'capped="0"'*) ok "tail element carries the exact split: $TAILTAG" ;;
    '') no "no <tail> element in the --for bundle (d2 missing)" ;;
    *)  no "tail element has wrong counts: $TAILTAG (expected total=11 shown=11 capped=0)" ;;
esac
TROWS="$( printf '%s' "$XML" | grep -o '<t p="[^"]*"/>' | wc -l | tr -d ' ' )"
if [ "$TROWS" = "11" ]; then ok "tail serves 11 <t p= rows"; else no "tail rows: $TROWS (expected 11)"; fi
# disjoint: no tail path may also be a head row's p= (P7: the head is flat <d … p=> rows, no <f> wrapper)
DUP="$( printf '%s' "$XML" | python3 -c '
import re, sys
s = sys.stdin.read()
head  = set( re.findall( r"<d [^>]*?\bp=\"([^\"]*)\"", s ) )
tails = re.findall( r"<t p=\"([^\"]*)\"/>", s )
print( sum( 1 for t in tails if t in head ) )
' )"
if [ "$DUP" = "0" ]; then ok "tail files are disjoint from the head's files"; else no "$DUP tail file(s) duplicate a head file"; fi

# ── 2) d1: r= on every ranked row, exactly the ranks 1..K ──────────────────────────────────────────────
RSEQ="$( printf '%s' "$XML" | grep -o '<d l="[^>]*>' | grep -o ' r="[0-9]*"' | grep -o '[0-9]*' | sort -n | tr '\n' ' ' )"
if [ "$RSEQ" = "1 2 3 4 " ]; then ok "every <d> row carries r=, ranks exactly 1..4"; else no "XML r= sequence wrong: '$RSEQ' (expected '1 2 3 4 ')"; fi

# ── 3) d1 cross-surface: r=1 names the same symbol the flat candidates export ranks first ──────────────
TOPD="$( printf '%s' "$XML" | grep -o '<d l="[^>]*r="1"[^>]*>' | head -1 | grep -o 'n="[^"]*"' | head -1 )"
TOPC="$( "$BIN" "$CORPUS" --no-cache --for="$Q" --format=candidates --top-k=1 2>/dev/null | grep -o '<cand r="1" [^>]*>' | grep -o 'n="[^"]*"' | head -1 )"
if [ -n "$TOPD" ] && [ "$TOPD" = "$TOPC" ]; then ok "r=1 row and <cand r=1> name the same symbol ($TOPD)"
else no "rank surfaces disagree: bundle r=1 is '$TOPD', candidates r=1 is '$TOPC'"; fi

# ── 4) the JSON dialect: per-row "r" + the always-present tail object, matching the XML tail ───────────
# The JSON arm runs at the DEFAULT head (--pack-top-n has no --json dialect): 40 symbols = files w01..w08,
# so the expected tail is exactly w09..w12 — compared file-for-file against the default XML run's tail.
"$BIN" "$CORPUS" --no-cache --for="$Q" --json 2>/dev/null > "$TMP/for.json"
"$BIN" "$CORPUS" --no-cache --for="$Q" 2>/dev/null > "$TMP/for_default.xml"
JV="$( python3 - "$TMP/for.json" "$TMP/for_default.xml" <<'EOF'
import json, re, sys
d = json.load( open( sys.argv[1] ) )
xml = open( sys.argv[2] ).read()
rs = sorted( s.get( "r", 0 ) for s in d.get( "sigs", [] ) )   # P7: flat sigs array
tail = d.get( "tail" )
xtails = re.findall( r"<t p=\"([^\"]*)\"/>", xml )
checks = [
    bool( rs ) and rs == list( range( 1, len( rs ) + 1 ) ),
    tail is not None and tail.get( "total" ) == 4 and tail.get( "shown" ) == 4,
    tail is not None and tail.get( "files" ) == xtails,
]
print( " ".join( "Y" if c else "N" for c in checks ) )
EOF
)"
case "$JV" in
    "Y Y Y") ok "JSON: r keys are contiguous 1..K; tail total/shown=4/4; files match the XML tail exactly" ;;
    *)       no "JSON dialect wrong (r-seq / tail-counts / xml-parity = $JV)" ;;
esac

# ── 5) pack-task: both dialects carry the rank fact ────────────────────────────────────────────────────
PT="$( "$BIN" "$CORPUS" --no-cache --pack-task="$Q" 2>/dev/null )"
if printf '%s' "$PT" | grep -q '<d l="[^>]*r="1"'; then ok "pack-task XML ranking rows carry r="; else no "pack-task XML rows carry no r="; fi
PTJ="$( "$BIN" "$CORPUS" --no-cache --pack-task="$Q" --json 2>/dev/null | python3 -c '
import json, sys
d = json.load( sys.stdin )
rs = [ s.get( "r", 0 ) for s in d.get( "ranking", [] ) ]   # P7: flat ranking array
print( "Y" if rs and all( r > 0 for r in rs ) else "N" )
' )"
if [ "$PTJ" = "Y" ]; then ok "pack-task JSON ranking rows carry r"; else no "pack-task JSON ranking rows carry no r"; fi

# ── 6) hard ceiling: the tail funds LAST and its disclosure survives a spent budget ────────────────────
TB="$( "$BIN" "$CORPUS" --no-cache --for="$Q" --pack-top-n=4 --token-budget=220 2>/dev/null )"
TBTAG="$( printf '%s' "$TB" | grep -o '<tail [^>]*>' | head -1 )"
case "$TBTAG" in
    *'total="11"'*) ok "tight --token-budget keeps the tail disclosure: $TBTAG" ;;
    '') no "tight --token-budget dropped the <tail> element entirely (disclosure lost)" ;;
    *)  no "tight-budget tail lost its denominator: $TBTAG" ;;
esac
TBSHOWN="$( printf '%s' "$TBTAG" | grep -o 'shown="[0-9]*"' | grep -o '[0-9]*' )"
TBCAP="$(   printf '%s' "$TBTAG" | grep -o 'capped="[0-9]"' | grep -o '[0-9]' )"
if [ -n "$TBSHOWN" ] && [ "$TBSHOWN" -lt 11 ] && [ "$TBCAP" = "1" ]; then
    ok "tight budget trimmed tail rows (shown=$TBSHOWN) and disclosed capped=1"
else
    no "tight budget did not trim/disclose honestly (shown=$TBSHOWN capped=$TBCAP)"
fi
if printf '%s' "$TB" | xmllint --noout - 2>/dev/null; then ok "tight-budget bundle stays well-formed"; else no "tight-budget bundle fails xmllint"; fi

# ── 7) zero-tail honesty: a head that covers every file still emits the element (0 = none remain) ──────
MINI="$TMP/mini"
mkdir -p "$MINI"
for i in 1 2 3; do
    printf 'def widget_frobnicate_%s():\n    """widget frobnicate helper %s"""\n    return 1\n' "$i" "$i" > "$MINI/m$i.py"
done
Z="$( "$BIN" "$MINI" --no-cache --for="$Q" 2>/dev/null | grep -o '<tail [^>]*>' | head -1 )"
case "$Z" in
    *'total="0"'*'shown="0"'*'capped="0"'*) ok "all-files-in-head bundle still emits <tail total=0 shown=0> (none remain, said out loud)" ;;
    *) no "zero-tail bundle wrong/missing: '$Z'" ;;
esac

# ── 9) H2H-Graft lane 2 (2026-09-07): a row the byte ladder TRIMS lands in the tail, never nowhere ─────
# The tail used to exclude every file of the 40-candidate SURFACE, so a sigs row cut by the budget (rank 5..40)
# appeared in neither section. On rocksdb three single-file answers at candidate rank 5/10/5 were served nowhere.
# Contract: tail total = files with a positive score MINUS the files of the sigs rows actually shown; the trimmed
# rows' files come first, in rank order; the JSON twin agrees file-for-file at the same budget.
T9="$( "$BIN" "$CORPUS" --no-cache --for="$Q" --token-budget=900 2>/dev/null )"
T9_SIGS="$( printf '%s' "$T9" | grep -o '<sigs [^>]*>' | head -1 )"
T9_SHOWN_FILES="$( printf '%s' "$T9" | grep -o '<d [^>]*p="[^"]*"' | grep -o 'p="[^"]*"' | sed 's/p="//;s/"//' | sort -u )"
T9_NSHOWN="$( printf '%s\n' "$T9_SHOWN_FILES" | grep -c . )"
T9_TAG="$( printf '%s' "$T9" | grep -o '<tail [^>]*>' | head -1 )"
T9_TOTAL="$( printf '%s' "$T9_TAG" | grep -oE 'total="[0-9]+"' | grep -oE '[0-9]+' )"
case "$T9_SIGS" in *'capped="1"'*) ok "(9) fixture guard: the 900-token budget trims sigs rows ($T9_SIGS; $T9_NSHOWN file(s) shown)" ;;
                   *) no "(9) fixture guard: expected the ladder to trim at --token-budget=900, got '$T9_SIGS'" ;; esac
[ "$T9_TOTAL" = "$(( 12 - T9_NSHOWN ))" ] \
    && ok "(9a) tail total=$T9_TOTAL = 12 files minus the $T9_NSHOWN shown (trimmed surface rows are IN the tail)" \
    || no "(9a) tail total=$T9_TOTAL but $T9_NSHOWN file(s) are shown — $(( 12 - T9_NSHOWN - ${T9_TOTAL:-0} )) ranked file(s) served nowhere ($T9_TAG)"
T9_EXPECT_FIRST="$( for i in 01 02 03 04 05 06 07 08 09 10 11 12; do printf '%s\n' "w$i.py"; done | grep -vxF -f <( printf '%s\n' "$T9_SHOWN_FILES" ) | head -1 )"
T9_FIRST="$( printf '%s' "$T9" | grep -o '<t p="[^"]*"' | head -1 | sed 's/<t p="//;s/"//' )"
if [ -n "$T9_FIRST" ]; then
    [ "$T9_FIRST" = "$T9_EXPECT_FIRST" ] && ok "(9b) first tail row is the best trimmed file ($T9_FIRST)" \
                                          || no "(9b) first tail row '$T9_FIRST', expected the best trimmed file '$T9_EXPECT_FIRST'"
else
    printf '  SKIP  (9b) the 900-token budget left the tail no rows (total disclosed above)\n'
fi
# The JSON twin runs its OWN ladder (its rows cost different bytes), so it may trim one row more or less at the
# same budget; the contract is per dialect — its tail total = 12 minus the files ITS sigs rows show.
T9J="$( "$BIN" "$CORPUS" --no-cache --for="$Q" --token-budget=900 --json 2>/dev/null )"
T9J_TOTAL="$( printf '%s' "$T9J" | grep -o '"tail":{"total":[0-9]*' | grep -oE '[0-9]+$' )"
T9J_NSHOWN="$( printf '%s' "$T9J" | grep -o '"p":"w[0-9]*\.py"' | sort -u | grep -c . )"   # sigs rows carry "p":; the tail carries "files":[]
[ -n "$T9J_TOTAL" ] && [ "$T9J_TOTAL" = "$(( 12 - T9J_NSHOWN ))" ] \
    && ok "(9c) JSON twin: tail total=$T9J_TOTAL = 12 minus its own $T9J_NSHOWN shown file(s)" \
    || no "(9c) JSON twin: tail total='$T9J_TOTAL' but its sigs show $T9J_NSHOWN file(s)"

# ── 8) the legend defines both new surfaces where the reader meets them ────────────────────────────────
HDR="$( printf '%s' "$XML" | sed 's/-->.*//' )"
if printf '%s' "$HDR" | grep -q 'tail: file-grain tail'; then ok "legend defines the tail (file-grain, weaker evidence)"; else no "legend does not define the tail"; fi
if printf '%s' "$HDR" | grep -q 'r= on a ranked row'; then ok "legend defines r= (true ranker order)"; else no "legend does not define r="; fi

# ── 9) determinism + well-formedness ───────────────────────────────────────────────────────────────────
"$BIN" "$CORPUS" --no-cache --for="$Q" --pack-top-n=4 2>/dev/null > "$TMP/d1.xml"
"$BIN" "$CORPUS" --no-cache --for="$Q" --pack-top-n=4 2>/dev/null > "$TMP/d2.xml"
"$BIN" "$CORPUS" --no-cache --for="$Q" --pack-top-n=4 2>/dev/null > "$TMP/d3.xml"
if cmp -s "$TMP/d1.xml" "$TMP/d2.xml" && cmp -s "$TMP/d2.xml" "$TMP/d3.xml"; then
    ok "deterministic: three runs byte-identical"
else
    no "runs differ byte-wise (determinism broken)"
fi
if xmllint --noout "$TMP/d1.xml" 2>/dev/null; then ok "bundle is well-formed XML"; else no "bundle fails xmllint"; fi

# ── 10) MCP parity: the `for` verb serves the same two surfaces ────────────────────────────────────────
MCP_INNER="$( printf '%s\n' \
    '{"jsonrpc":"2.0","id":1,"method":"initialize"}' \
    '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"for","arguments":{"path":"'"$CORPUS"'","task":"'"$Q"'"}}}' \
    | "$BIN" --mcp 2>/dev/null | tail -1 | python3 -c '
import json, sys
r = json.load( sys.stdin )
print( "" if "error" in r else r["result"]["content"][0]["text"] )
' )"
if printf '%s' "$MCP_INNER" | grep -q '<tail total='; then ok "MCP for verb serves the file-grain tail"; else no "MCP for verb has no <tail>"; fi
if printf '%s' "$MCP_INNER" | grep -q '<d l="[^>]*r="1"'; then ok "MCP for verb rows carry r="; else no "MCP for verb rows carry no r="; fi

echo
if [ "$fail" = "0" ]; then echo "deeptailcheck: ALL PASS"; else echo "deeptailcheck: FAILURES ABOVE"; fi
exit "$fail"
