#!/usr/bin/env bash
# recallbufcheck.sh — CA4 §H1: the recall bundle's line formatters must never size an emitted line against a
# FIXED STACK BUFFER whose snprintf return value is then used as an append length.
#
# The bug this gate pins (measured on base 22a6a84):
#   buildRecall composed "\n━━ %s  (relevance %.3f) ━━%s" into `char sep[640]`, interpolating
#   ing.files[fileId] — an ABSOLUTE PATH, unbounded by nature — and then appended snprintf's WOULD-BE
#   return length:  sepLen = snprintf( sep, sizeof sep, … );  payload.append( sep, sepBytes );
#   A recalled doc whose absolute path crosses ~640 bytes therefore made std::string::append READ PAST the
#   stack frame:  ASan → stack-buffer-overflow READ of size 790 (a 756-byte path), exit 134, on BOTH the
#   `--recall=` CLI seam and MCP `memory_recall` (one client request kills the server). Under the plain
#   build the read succeeds and ~100-260 raw stack bytes — including live pointers — are emitted into the
#   payload, i.e. into the JSON-RPC reply an MCP client hands to a model.
#
# This is verbatim the W3FIX-H1 class already fixed one function ABOVE it in the same file
# (formatRecallHeader, commit 4a72e71), whose own comment states the rule: user-length / path-length text is
# composed on std::string, never into a fixed char buffer. The fix stopped at its callee; this gate makes the
# whole family of recall line formatters observable instead of only the one that was noticed.
#
# ARMS
#   (a) deep-path CLI recall — a recalled doc at a ~756-byte absolute path: exit 0, and the emitted separator
#       line carries the FULL path (not a 640-byte truncation, not garbage), with ZERO control bytes.
#   (b) the same over MCP `memory_recall` on a LIVE `--mcp` server: the reply line parses as JSON, carries the
#       full path in its payload, and contains NO raw byte below 0x20 (a leaked stack byte is exactly that).
#   (c) the bisect boundary: 600 / 700 / 900 / ~1000-byte paths all clean AND byte-deterministic across runs.
#       (~1000 is the macOS ceiling — PATH_MAX is 1024, so a 1500-byte path cannot be created at all here;
#       that is a platform limit on the TEST, not a bound on ing.files[] — a checkout reached through a long
#       symlinked or network mount path is not bounded by what mkdir can build in /tmp.)
#   (d) one arm per SIBLING formatter converted off the same shape — truncateRecallBody's `[truncated: …]`,
#       formatRecallCappedNote's `(capped: …)` and emitRecallBudgeted's `(withheld: …)` — each exercised with
#       a long path in the corpus and its own interpoland at width, asserting the text is intact and clean.
#       Those three are provably BOUNDED (fixed prose + integers only) and so are green on base too: their
#       arms are the byte-identity guard for the conversion, not a second red.
#
# Usage:  test/recallbufcheck.sh [BIN]   |   RIPWIRE_BIN=asan/ripwire test/recallbufcheck.sh
# Both binding seams are live and both are exercised in CI-style use. Exits non-zero on any failure.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
export LSAN_OPTIONS="suppressions=$ROOT/lsan_suppressions.txt"

fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 required for the byte/JSON assertions"; exit 2; }

echo "recallbufcheck: BIN=$BIN"

TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT

# ─── sandbox: one markdown doc per target ABSOLUTE-path length ────────────────────────────────────
# Each repo root holds exactly one deep doc, so the separator line under test is unambiguous. Prints
# "<root> <docpath>" per line; the doc path is the string that lands in ing.files[] verbatim.
python3 - "$TMP" >"$TMP/paths.txt" <<'PY'
import os, sys
tmp = sys.argv[1]
for target in ( 600, 700, 756, 900, 1000 ):
    root = os.path.join( tmp, "r%d" % target )
    d = root
    os.makedirs( d, exist_ok = True )
    comp = "d" * 60
    while len( d ) < target - 20:
        nd = os.path.join( d, comp )
        try:                os.makedirs( nd, exist_ok = True )
        except OSError:     break
        d = nd
    doc = os.path.join( d, "kafka.md" )
    with open( doc, "w" ) as f:
        f.write( "# Kafka consumer rebalancing\n\n"
                 "Partition assignment, consumer group rebalancing, offset commits and the sticky "
                 "assignor for kafka streams. " * 40 )
    print( root, doc )
PY

pathline(){ grep -E "/r$1 " "$TMP/paths.txt"; }
rootof(){ pathline "$1" | cut -d' ' -f1; }
docof(){  pathline "$1" | cut -d' ' -f2; }

# byte hygiene: a leaked stack byte shows up as a control byte (NUL and friends) in the payload. \n and \t
# are the only sub-0x20 bytes the recall bundle legitimately emits.
clean_bytes(){
    python3 - "$1" <<'PY'
import sys
b = open( sys.argv[1], "rb" ).read()
bad = [ x for x in b if x < 0x20 and x not in ( 9, 10, 13 ) ]
print( "%d %s" % ( len( bad ), sorted( set( bad ) )[:8] ) )
PY
}

recall(){ # recall <root> <outfile> [extra flags…]
    local root="$1" out="$2"; shift 2
    perl -e 'alarm 60; exec @ARGV' "$BIN" "$root" --recall="kafka consumer offset rebalancing partition" \
         --no-cache "$@" >"$out" 2>"$out.err"
}

# ─── (a) deep-path CLI recall: no overflow, no truncation, no leak ────────────────────────────────
echo
echo "=== (a) --recall with a 756-byte doc path — full path emitted, no stack bytes ==="
A_ROOT="$( rootof 756 )"; A_DOC="$( docof 756 )"
echo "  doc path length: ${#A_DOC} bytes"
recall "$A_ROOT" "$TMP/a.out"; a_exit=$?
[ "$a_exit" -eq 0 ] && ok "exit 0 (base: 134 under ASan — stack-buffer-overflow in buildRecall)" \
                    || no "exit $a_exit (expected 0); stderr: $( head -c 300 "$TMP/a.out.err" )"
grep -aqF "$A_DOC" "$TMP/a.out" \
    && ok "separator line carries the FULL ${#A_DOC}-byte path" \
    || no "FULL path absent — the separator was truncated or garbled: $( grep -aF '━━' "$TMP/a.out" | head -1 | cat -v | head -c 200 )"
A_CTRL="$( clean_bytes "$TMP/a.out" )"
[ "${A_CTRL%% *}" = "0" ] && ok "zero control bytes in the payload" \
                          || no "control bytes LEAKED into the payload: $A_CTRL"
# counted, not grepped: `grep "$( printf '\000' )"` is a SILENTLY EMPTY pattern (command substitution drops
# NUL), and an empty pattern matches every non-empty file — the arm would fire on clean output and stay
# quiet on an empty one. Count the byte instead.
A_NULS="$( python3 -c 'import sys; print(open(sys.argv[1],"rb").read().count(b"\x00"))' "$TMP/a.out" )"
[ "$A_NULS" = "0" ] && ok "no NUL byte in the payload" \
                    || no "$A_NULS NUL byte(s) present in the payload"

# ─── (b) the same over a LIVE MCP server ─────────────────────────────────────────────────────────
echo
echo "=== (b) MCP memory_recall on a live --mcp server — valid JSON, no raw control bytes ==="
INIT='{"jsonrpc":"2.0","id":1,"method":"initialize"}'
CALL='{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"memory_recall","arguments":{"path":"'"$A_ROOT"'","task":"kafka consumer offset rebalancing partition"}}}'
printf '%s\n%s\n' "$INIT" "$CALL" | perl -e 'alarm 60; exec @ARGV' "$BIN" --mcp >"$TMP/b.out" 2>"$TMP/b.err"; b_exit=$?
[ "$b_exit" -eq 0 ] && ok "server exited 0 (base: killed by ASan on the ONE request)" \
                    || no "server exit $b_exit (expected 0); stderr: $( head -c 300 "$TMP/b.err" )"
python3 - "$TMP/b.out" "$A_DOC" <<'PY' >"$TMP/b.verdict" 2>&1
import sys, json
raw = open( sys.argv[1], "rb" ).read()
docPath = sys.argv[2]
problems = []
lines = [ l for l in raw.split( b"\n" ) if l.strip() ]
if not lines:
    problems.append( "no response lines at all" )
for i, l in enumerate( lines ):
    bad = sorted( set( x for x in l if x < 0x20 ) )
    if bad:
        problems.append( "line %d carries RAW control bytes %s (a leaked stack byte is exactly this)" % ( i, bad ) )
    try:
        json.loads( l.decode( "utf-8", "replace" ) )
    except Exception as e:
        problems.append( "line %d does not parse as JSON: %s" % ( i, e ) )
if lines:
    try:
        r = json.loads( lines[-1].decode( "utf-8", "replace" ) )
        text = r["result"]["content"][0]["text"]
        if docPath not in text:
            problems.append( "reply payload does not carry the full %d-byte doc path" % len( docPath ) )
    except Exception as e:
        problems.append( "could not read result text: %s" % e )
print( "OK" if not problems else "PROBLEMS: " + " | ".join( problems ) )
PY
if [ "$( cat "$TMP/b.verdict" )" = "OK" ]; then
    ok "MCP reply parses as JSON, carries the full path, zero raw control bytes"
else
    no "MCP reply: $( cat "$TMP/b.verdict" )"
fi

# ─── (c) the bisect boundary + determinism ───────────────────────────────────────────────────────
echo
echo "=== (c) bisect boundary — 600 / 700 / 900 / ~1000-byte paths clean and deterministic ==="
for t in 600 700 900 1000; do
    r="$( rootof "$t" )"; d="$( docof "$t" )"
    recall "$r" "$TMP/c_${t}_a"; e1=$?
    recall "$r" "$TMP/c_${t}_b"; e2=$?
    if [ "$e1" -ne 0 ] || [ "$e2" -ne 0 ]; then
        no "target $t (${#d}-byte path): exit $e1/$e2 (expected 0/0)"
    else
        ok "target $t (${#d}-byte path): exit 0"
    fi
    cc="$( clean_bytes "$TMP/c_${t}_a" )"
    [ "${cc%% *}" = "0" ] && ok "target $t: zero control bytes" || no "target $t: control bytes leaked: $cc"
    grep -aqF "$d" "$TMP/c_${t}_a" && ok "target $t: full path emitted" || no "target $t: full path missing/truncated"
    cmp -s "$TMP/c_${t}_a" "$TMP/c_${t}_b" && ok "target $t: byte-deterministic" || no "target $t: NON-deterministic across two runs"
done

# ─── (d) sibling formatters, each with its own interpoland at width ──────────────────────────────
# One corpus, several deep-path docs, so --max-tokens has to truncate one body AND omit others: that fires
# truncateRecallBody and formatRecallCappedNote in the same run, with a >640-byte path in the separator.
echo
echo "=== (d) sibling formatters — truncated / capped / withheld notes intact under a long path ==="
D_ROOT="$TMP/dsib"
python3 - "$D_ROOT" <<'PY'
import os, sys
root = sys.argv[1]
for n in range( 4 ):
    d = os.path.join( root, "s%d" % n )
    os.makedirs( d, exist_ok = True )
    comp = "e" * 60
    while len( d ) < 740:
        nd = os.path.join( d, comp )
        try:                os.makedirs( nd, exist_ok = True )
        except OSError:     break
        d = nd
    with open( os.path.join( d, "kafka%d.md" % n ), "w" ) as f:
        f.write( "# Kafka consumer rebalancing %d\n\n" % n +
                 "Partition assignment, consumer group rebalancing, offset commits and the sticky "
                 "assignor for kafka streams. " * 120 )
PY

# (d1) truncateRecallBody — "[truncated: N of M bytes]" on a doc whose separator holds a 740+ byte path
recall "$D_ROOT" "$TMP/d1.out" --max-tokens=1200; d1_exit=$?
[ "$d1_exit" -eq 0 ] && ok "d1 --max-tokens: exit 0" || no "d1 --max-tokens: exit $d1_exit (expected 0)"
grep -aqE '\[truncated: [0-9]+ of [0-9]+ bytes' "$TMP/d1.out" \
    && ok "d1 truncateRecallBody: '[truncated: N of M bytes…]' intact" \
    || no "d1 truncateRecallBody: marker missing/garbled: $( grep -aoE '\[trunc.{0,60}' "$TMP/d1.out" | head -1 | cat -v )"
D1_CTRL="$( clean_bytes "$TMP/d1.out" )"
[ "${D1_CTRL%% *}" = "0" ] && ok "d1: zero control bytes" || no "d1: control bytes leaked: $D1_CTRL"

# (d1b) L4 UPDATE (recall.h's protected-range fix, same commit): this arm used to force the cut to land
# INSIDE the ``` block and assert the ", fence_closed" repair note fired. §L4.2 now protects a fenced block
# as WHOLE-OR-NOTHING — the forced cut is moved to BEFORE the fence instead of landing inside it, so
# closeOpenMarkdownFence's repair is no longer the mechanism that keeps this doc's fence balanced (it
# remains in place as a last-resort safety net for any shape the protected-range scan doesn't cover, but a
# ``` block this large, this ordinary, is never one of them). The property this arm actually exists to
# guard — a long absolute path never corrupts the sibling formatters, and a fenced doc never comes out with
# a dangling open fence — still holds and is asserted directly: the emitted payload's ``` markers are
# BALANCED (an even count: either the whole fence survived, or none of it did — never a torn half).
# Its own corpus (one deep-path doc that is almost entirely one fenced block) so it cannot perturb d1/d2's
# ranking.
F_ROOT="$TMP/dfence"
python3 - "$F_ROOT" <<'PY'
import os, sys
d = os.path.join( sys.argv[1], "f0" )
os.makedirs( d, exist_ok = True )
comp = "f" * 60
while len( d ) < 700:
    nd = os.path.join( d, comp )
    try:                os.makedirs( nd, exist_ok = True )
    except OSError:     break
    d = nd
with open( os.path.join( d, "kafka.md" ), "w" ) as fh:
    fh.write( "# Kafka consumer rebalancing\n\nPartition assignment and offset commits.\n\n```python\n" )
    fh.write( "# kafka consumer group rebalancing partition offset commit sticky assignor\n" * 200 )
    fh.write( "```\n" )
PY
recall "$F_ROOT" "$TMP/d1b.out" --max-tokens=1400; d1b_exit=$?
[ "$d1b_exit" -eq 0 ] && ok "d1b --max-tokens (fenced doc): exit 0" || no "d1b: exit $d1b_exit (expected 0)"
grep -aqE '\[truncated: [0-9]+ of [0-9]+ bytes' "$TMP/d1b.out" \
    && ok "d1b truncateRecallBody: '[truncated: N of M bytes…]' fired" \
    || no "d1b truncateRecallBody: marker missing: $( grep -aoE '\[trunc.{0,60}' "$TMP/d1b.out" | head -1 | cat -v )"
D1B_TICKS="$( grep -ao '```' "$TMP/d1b.out" | wc -l | tr -d ' ' )"
[ "$(( D1B_TICKS % 2 ))" -eq 0 ] \
    && ok "d1b fence markers balanced (even count: $D1B_TICKS) — whole-or-nothing under the protected-range cut, never torn" \
    || no "d1b fence markers UNBALANCED (odd count: $D1B_TICKS) — the forced cut tore the fenced block"
D1B_CTRL="$( clean_bytes "$TMP/d1b.out" )"
[ "${D1B_CTRL%% *}" = "0" ] && ok "d1b: zero control bytes" || no "d1b: control bytes leaked: $D1B_CTRL"

# (d2) formatRecallCappedNote — BOTH attribution clauses at once: --top-k trims the relevant set (4→2) AND
# the byte budget trims what survives (2→1), so `why` is composed at its widest. That is the arm that
# matters: 161 of this note's 254-byte worst case is `why`, so a one-clause run under-exercises it.
recall "$D_ROOT" "$TMP/d2.out" --top-k=2 --max-tokens=1200; d2_exit=$?
[ "$d2_exit" -eq 0 ] && ok "d2 --top-k + --max-tokens: exit 0" || no "d2: exit $d2_exit (expected 0)"
if grep -aqE '\(capped: [0-9]+ of [0-9]+ relevant document files omitted' "$TMP/d2.out"; then
    ok "d2 formatRecallCappedNote: '(capped: N of M … omitted — why)' intact"
else
    no "d2 formatRecallCappedNote: note missing/garbled: $( grep -aoE '\(capped.{0,80}' "$TMP/d2.out" | head -1 | cat -v )"
fi
grep -aqE 'raise --top-k \(default 8\) for [0-9]+ more; raise --max-tokens or narrow the query for [0-9]+ more \(~[0-9]+-byte budget\)\)' "$TMP/d2.out" \
    && ok "d2: BOTH attribution clauses present and intact (widest 'why')" \
    || no "d2: the two-clause 'why' was not produced — $( grep -aoE 'omitted —.{0,160}' "$TMP/d2.out" | head -1 | cat -v )"
D2_CTRL="$( clean_bytes "$TMP/d2.out" )"
[ "${D2_CTRL%% *}" = "0" ] && ok "d2: zero control bytes" || no "d2: control bytes leaked: $D2_CTRL"

# (d3) emitRecallBudgeted — the withheld note (exit 3 is the contract, not a failure)
recall "$D_ROOT" "$TMP/d3.out" --token-budget=1; d3_exit=$?
[ "$d3_exit" -eq 3 ] && ok "d3 --token-budget=1: exit 3 (gate personality)" || no "d3: exit $d3_exit (expected 3)"
grep -aqE '\(withheld: withheld_est_tokens=[0-9]+ > budget=1 — [0-9]+ bytes not emitted; re-run with --max-tokens=1 to SHAPE it to fit\)' "$TMP/d3.out" \
    && ok "d3 emitRecallBudgeted: withheld note intact, verbatim" \
    || no "d3 emitRecallBudgeted: note missing/garbled: $( grep -aoE '\(withheld.{0,140}' "$TMP/d3.out" | head -1 | cat -v )"
D3_CTRL="$( clean_bytes "$TMP/d3.out" )"
[ "${D3_CTRL%% *}" = "0" ] && ok "d3: zero control bytes" || no "d3: control bytes leaked: $D3_CTRL"

echo
[ "$fail" -eq 0 ] && { echo "recallbufcheck: ALL PASS"; exit 0; }
echo "recallbufcheck: FAILURES present"; exit 1
