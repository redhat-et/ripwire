#!/usr/bin/env bash
# staleackcheck.sh — L2 gate for STALE-ACK disclosure on --quality-delta.
#
# WHY. `.ripwire_quality_acks` has acquisition (--quality-ack) and a worsen-past-acked-magnitude ratchet
# (quality::applyAckRatchet) but no retirement surface: an ack whose target symbol was deleted, or whose
# finding kind no longer fires on a symbol that survived, sits in the ledger forever, invisibly. A past
# round hand-retired 109 dead rows out of this repo's own 188-line ledger — a whole session of manual
# audit for a question the tool should answer in one pass. The in-repo precedent for exactly this shape
# is --notes: a note whose target no longer resolves is flagged dangling="1" against the LIVE symbol/file
# set. This gate pins the mirror of that pattern for acks: quality::computeStaleAcks (src/quality.h),
# surfaced on --quality-delta's report root as stale="N" plus a per-row <sa kind= key= why=/> detail —
# report, never gate: exit code must be unchanged whether or not any ack is stale.
#
# FIXTURE MECHANICS. computeStaleAcks reads ONLY the CURRENT working-tree snapshot — never the git
# baseline computeDelta compares against — so once a finding is acked, staleness is decided purely by
# rewriting the file on disk (no further git commits needed): delete the symbol entirely for target-gone,
# or shrink its body back under the bar (same canonId, same file/scope/name) for finding-gone.
#
# Checks:
#   (1) a clean, freshly-acked tree reports stale="0" and emits no <sa> rows.
#   (2) TARGET-GONE — the acked symbol is deleted outright: stale="1", why="target-gone", exit code
#       unchanged from (1).
#   (3) FINDING-GONE — the acked symbol survives (same canonId) but its complexity is refactored back
#       under the bar: stale="1", why="finding-gone", exit code unchanged from (1).
#   (4) a second, independent clean fixture also reports stale="0" (not a one-off on the first tree).
#
# Own temp repo, own private cache dir. Needs git.
# Usage:  test/staleackcheck.sh   |   test/staleackcheck.sh asan/ripwire   |   RIPWIRE_BIN=asan/ripwire test/staleackcheck.sh
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
. "$ROOT/test/lib/clean-env.sh"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
fail=0
ok(){ echo "  PASS  $1" || { fail=1; echo "  FAIL  could not write the PASS line for: $1"; }; return 0; }
no(){ echo "  FAIL  $1"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
command -v git >/dev/null 2>&1 || { echo "git required"; exit 2; }

REPO="$( mktemp -d )"; REPO2="$( mktemp -d )"; TMP="$( mktemp -d )"
trap 'rm -rf "$REPO" "$REPO2" "$TMP"' EXIT
XDG="$TMP/xdg"; mkdir -p "$XDG"
run(){ env -u TMPDIR XDG_CACHE_HOME="$XDG" "$BIN" "$REPO" "$@"; }
run2(){ env -u TMPDIR XDG_CACHE_HOME="$XDG" "$BIN" "$REPO2" "$@"; }
ACKS="$REPO/.ripwire_quality_acks"

echo "staleackcheck: BIN=$BIN"

# `knotty` breaches kCcxBar (15) reliably — the same fixture shape test/qackorigincheck.sh uses to pin a
# real complexity finding, reused here so this gate does not have to re-derive a bar-breaching shape.
# Committed WITHOUT knotty first, so appending it makes an UNCOMMITTED (ackable) new-symbol finding —
# exactly test/qackorigincheck.sh's own setup.
mkdir -p "$REPO/src"
cat > "$REPO/src/lib.cpp" <<'EOF'
int stable( int a ) { return a + 1; }
EOF
git -C "$REPO" init -q; git -C "$REPO" config user.email x@y; git -C "$REPO" config user.name x
git -C "$REPO" add -A; git -C "$REPO" commit -qm init >/dev/null

cat > "$REPO/src/lib.cpp" <<'EOF'
int stable( int a ) { return a + 1; }
int knotty( int a, int b, int c ) {
    int r = 0;
    for( int i = 0; i < a; ++i ) {
        if( i % 2 == 0 ) { if( i > b ) { r += i; } else { r -= 1; } }
        else { for( int j = 0; j < b; ++j ) { if( j > c ) { r += j; } else { r--; } } }
        while( r > c && r > b ) { r = r - 1; if( r % 3 == 0 ) { r += 2; } }
    }
    return r;
}
EOF

# ── setup: ack the complexity finding on knotty() ──────────────────────────────────────────────────────
run --quality-delta --quality-ack="fixture: accepted complexity" >/dev/null 2>&1
grep -q '^ack complexity ' "$ACKS" 2>/dev/null \
    && ok "setup: complexity finding on knotty() acked" \
    || { no "setup: no complexity ack recorded — fixture vacuous, later checks are meaningless"; cat "$ACKS" 2>/dev/null; }

# ── (1) clean re-run: the acked symbol is untouched and still breaches its bar → stale="0", no <sa> rows ─
run --quality-delta >"$TMP/clean" 2>/dev/null; rcClean=$?
if grep -q 'stale="0"' "$TMP/clean" && ! grep -q '<sa ' "$TMP/clean"; then
    ok "(1) a clean, freshly-acked tree reports stale=\"0\" with no <sa> rows"
else
    no "(1) unexpected stale reporting on a clean tree"
    grep -o '<quality-delta[^>]*>\|<sa[^>]*/>' "$TMP/clean"
fi

# ── (2) TARGET-GONE: delete knotty() outright — the acked canonId no longer exists at all. knotty() is
#     uncalled, so it was ALSO a dead-code candidate at ack time (--quality-ack sweeps every CURRENT
#     finding, not just complexity) — deleting it therefore goes stale on BOTH acked kinds sharing its
#     canonId, so this checks stale=\"N\" is non-zero rather than pinning the exact count.
cat > "$REPO/src/lib.cpp" <<'EOF'
int stable( int a ) { return a + 1; }
EOF
# lane lean-trio (idea #11): a regression-free answer collapses its stale rows to counts by default; the row arms below
# read them through the recovery flag, and arm (2c) asserts the collapse itself on the same tree.
run --quality-delta --show-stale >"$TMP/targetgone" 2>/dev/null; rcTG=$?
run --quality-delta >"$TMP/targetgone_c" 2>/dev/null; rcTGc=$?
if grep -q 'stale="[1-9]' "$TMP/targetgone" && grep -q '<sa kind="complexity"[^>]*why="target-gone"' "$TMP/targetgone"; then
    ok "(2) a deleted acked symbol is reported stale>0 including why=\"target-gone\" for its complexity ack"
else
    no "(2) target-gone case not reported correctly"
    grep -o '<quality-delta[^>]*>\|<sa[^>]*/>' "$TMP/targetgone"
fi
if [ "$rcTG" -eq "$rcClean" ]; then
    ok "(2) stale-ack disclosure does not change the exit code ($rcTG, same as the no-stale run)"
else
    no "(2) exit code changed from the no-stale run ($rcClean -> $rcTG) — disclosure must never gate"
fi

# ── (2c) the COLLAPSE (lane lean-trio, idea #11): with no regression the default answer prints no <sa> row, keeps stale=
#     (the same count), splits it by kind in stale_by_kind=, names the recovery call in stale_next=, and exits the same.
#     RED on main 0852bc0f: the default answer carries the <sa> rows and no stale_by_kind=.
tgStale="$( grep -o 'stale="[0-9]*"' "$TMP/targetgone" | head -1 )"
if [ -n "$tgStale" ] && grep -q "$tgStale" "$TMP/targetgone_c" && ! grep -q '<sa ' "$TMP/targetgone_c" \
   && grep -q 'stale_by_kind="[^"]*complexity:[1-9]' "$TMP/targetgone_c" && grep -q 'stale_next="--quality-delta --show-stale"' "$TMP/targetgone_c" \
   && [ "$rcTGc" -eq "$rcTG" ]; then
    ok "(2c) no regression: the stale rows collapse to $tgStale + stale_by_kind=, stale_next= names the recovery flag, same exit"
else
    no "(2c) the regression-free collapse is wrong (rc $rcTGc vs $rcTG)"
    grep -o '<quality-delta[^>]*>\|<sa[^>]*/>' "$TMP/targetgone_c"
fi
sed 's/<quality-delta.*//' "$TMP/targetgone_c" | grep -q 'stale_by_kind=' \
    && ok "(2c) stale_by_kind= and stale_next= are defined in the collapsed answer's own legend" \
    || no "(2c) stale_by_kind= emitted with no legend definition"
# ── (2m) the MCP twin folds too (lane lean2b, card #9 MCP-FOLD; owner bar LOSSLESS). The fold rides only when it PAYS (foldPays:
#     at least a quarter of the bytes; JSON rows are cheaper than the CLI's legend-carrying XML, so the two surfaces can decide
#     differently on a two-row ledger). So the arm predicts the default answer EXACTLY from the show_stale=true one: the "sa"
#     array replaced by "stale_by_kind" (the CLI's own string) + "stale_next":"show_stale=true" when that is under 75 % of the
#     bytes, else the show_stale=true document byte for byte. Either way stale = the CLI's count and show_stale=true lists the
#     CLI --show-stale rows by key. Run on this two-row tree (no fold: it saves < 25 %) and again after twelve more acks go
#     stale (fold). RED on ffbec708: show_stale is refused as an unknown argument, and the 14-row default carries "sa".
if command -v python3 >/dev/null 2>&1; then
    mcpqd(){ printf '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"quality_delta","arguments":{"path":"%s"%s}}}\n' "$REPO" "$1" \
             | env -u TMPDIR XDG_CACHE_HOME="$XDG" "$BIN" --mcp 2>/dev/null \
             | python3 -c 'import sys,json
for line in sys.stdin:
    try: d=json.loads(line)
    except Exception: continue
    c=(d.get("result") or {}).get("content")
    if c: sys.stdout.write(c[0].get("text","")); break
    if d.get("error"): sys.stdout.write("__ERROR__"+json.dumps(d["error"])); break'; }
    mcpfold(){   # LABEL EXPECT(fold|full) CLI_COLLAPSED CLI_SHOWSTALE
        mcpqd '' >"$TMP/mcp_qd_def"; mcpqd ',"show_stale":true' >"$TMP/mcp_qd_full"
        if python3 - "$TMP/mcp_qd_def" "$TMP/mcp_qd_full" "$3" "$4" "$2" <<'PY'
import json, re, sys
dT, fT = ( open( p, encoding = "utf-8" ).read() for p in sys.argv[ 1:3 ] )
cliC, cliF = ( open( p ).read() for p in sys.argv[ 3:5 ] )
want = sys.argv[ 5 ]
f = json.loads( fT )
stale = int( re.search( r'<quality-delta\b[^>]*\bstale="(\d+)"', cliC ).group( 1 ) )
kinds = re.search( r'<quality-delta\b[^>]*\bstale_by_kind="([^"]*)"', cliC ).group( 1 )
cliKeys = sorted( re.findall( r'<sa kind="[^"]*" key="([0-9a-f]+)"', cliF ) )
cut = fT.rfind( '"sa":[' )
folded = fT[ :cut ] + '"stale_by_kind":"' + kinds + '","stale_next":"show_stale=true"}'
pays = len( folded.encode() ) * 100 < len( fT.encode() ) * 75
ok = True
for cond, msg in (
        ( f.get( "stale" ) == stale > 0 and f.get( "regressions" ) == 0, "show_stale=true: stale == the CLI's (%r vs %r), no regression" % ( f.get( "stale" ), stale ) ),
        ( sorted( a[ "key" ] for a in f.get( "sa", [] ) ) == cliKeys,   "show_stale=true lists the CLI --show-stale rows by key (%d)" % len( cliKeys ) ),
        ( "stale_by_kind" not in f and "stale_next" not in f,           "show_stale=true carries no fold key" ),
        ( pays == ( want == "fold" ),                                   "the fixture's fold decision is the expected one (%s, pays=%s)" % ( want, pays ) ),
        ( dT == ( folded if pays else fT ),                             "the default answer is exactly the predicted %s document" % ( "folded" if pays else "full" ) ) ):
    if not cond: print( "    " + msg ); ok = False
sys.exit( 0 if ok else 1 )
PY
        then ok "$1"; else no "$1"; fi
    }
    mcpfold "(2m) MCP quality_delta, 2 stale rows: the fold does not pay, the default is the show_stale=true document byte for byte" full "$TMP/targetgone_c" "$TMP/targetgone"
    # twelve more acked symbols, then deleted: 14 stale rows — the fold pays
    { cat "$REPO/src/lib.cpp"; for i in 1 2 3 4 5 6 7 8 9 10 11 12; do echo "int gone$i( int a ) { return a * $i; }"; done; } >"$TMP/lib_more.cpp"
    cp "$ACKS" "$TMP/acks_saved"   # restored below: the arms after this one read the two-row ledger
    cp "$TMP/lib_more.cpp" "$REPO/src/lib.cpp"
    run --quality-delta --quality-ack="fixture: twelve uncalled helpers" >/dev/null 2>&1
    printf 'int stable( int a ) { return a + 1; }\n' >"$REPO/src/lib.cpp"
    run --quality-delta --show-stale >"$TMP/tg14" 2>/dev/null; run --quality-delta >"$TMP/tg14_c" 2>/dev/null
    mcpfold "(2m) MCP quality_delta, more stale rows: the default folds to stale_by_kind + stale_next=show_stale=true, counts kept" fold "$TMP/tg14_c" "$TMP/tg14"
    cp "$TMP/acks_saved" "$ACKS"
else
    printf '  SKIP  (2m) MCP fold (no python3)\n'
fi
run --show-stale >/dev/null 2>&1 && no "(2c) --show-stale alone was accepted" || ok "(2c) --show-stale alone is refused (it modifies --quality-delta)"

# ── (3) FINDING-GONE: knotty() survives (same canonId) but is simplified back under the complexity bar ──
cat > "$REPO/src/lib.cpp" <<'EOF'
int stable( int a ) { return a + 1; }
int knotty( int a, int b, int c ) { return a + b + c; }
EOF
run --quality-delta --show-stale >"$TMP/findinggone" 2>/dev/null; rcFG=$?
if grep -q 'stale="[1-9]' "$TMP/findinggone" && grep -q '<sa kind="complexity"[^>]*why="finding-gone"' "$TMP/findinggone"; then
    ok "(3) a simplified (still-existing) symbol is reported stale>0 including why=\"finding-gone\" for its complexity ack"
else
    no "(3) finding-gone case not reported correctly"
    grep -o '<quality-delta[^>]*>\|<sa[^>]*/>' "$TMP/findinggone"
fi
if [ "$rcFG" -eq "$rcClean" ]; then
    ok "(3) stale-ack disclosure does not change the exit code ($rcFG, same as the no-stale run)"
else
    no "(3) exit code changed from the no-stale run ($rcClean -> $rcFG) — disclosure must never gate"
fi

# ── (2d) fix round 1 (owner ruling 5, rv-lean-trio item 5): a fold ships only when it PAYS (a quarter of the bytes, in both
#     postures). ONE stale row on a dirty, regression-free tree costs less than the collapse's own attributes and legend
#     sentence, so the default answer IS the full document — byte-identical to --show-stale, the <sa> row printed — in
#     both postures. RED on 33873861: the default collapsed the one row (fx: 1512 B collapsed vs 1481 B full).
run --quality-delta >"$TMP/fg_default" 2>/dev/null; rcFGd=$?
run --quality-delta --legend=full >"$TMP/fg_full" 2>/dev/null
run --quality-delta --show-stale --legend=full >"$TMP/fg_full_show" 2>/dev/null
fgStale="$( grep -o 'stale="[0-9]*"' "$TMP/findinggone" | head -1 )"
if [ "$fgStale" = 'stale="1"' ] && grep -q 'at="[0-9a-f]*+dirty' "$TMP/findinggone"; then
    if cmp -s "$TMP/fg_default" "$TMP/findinggone" && cmp -s "$TMP/fg_full" "$TMP/fg_full_show" && grep -q '<sa ' "$TMP/fg_default" \
       && [ "$rcFGd" -eq "$rcFG" ]; then
        ok "(2d) one stale row on a dirty tree: the collapse does not pay, the default is the full document (both postures)"
    else
        no "(2d) the one-row collapse shipped although it does not pay"
        grep -o '<quality-delta[^>]*>' "$TMP/fg_default" "$TMP/fg_full"
    fi
else
    no "(2d) premise: the finding-gone tree should be dirty with exactly one stale ack (got $fgStale)"
fi

# ── (5) M21(a): a <sa> row NAMES the ack that went stale, wherever the tree can still name it ──────────
# capture-audit 2026-09-04 (lens 0 M0-2). `<sa kind="complexity" key="4b309450f25c2b44" why="finding-gone"/>`
# is a 16-hex hash of an identity the reader does not have: to act on it — retire the ack, or look at why
# the finding stopped firing — the agent had to open .ripwire_quality_acks and then reverse a hash it
# cannot reverse. On this repo's own ledger that was 10 rows and 10 dead ends.
#
# THE RULE, and it is exactly derivable rather than best-effort: why="finding-gone" means the oracle found
# the key IN the current snapshot (that is how it told finding-gone from target-gone), so the symbol EXISTS
# and must be named. why="target-gone" means it is not there, so there is nothing to name and the why=
# already says so. The two CLONE kinds key on a member-SET hash that no live symbol carries, so they are
# never nameable — a floor, stated in the legend rather than papered over with a guess. Asserted in all
# three directions below, on the documents arms (2) and (3) already produced.
FG_ROWS="$( grep -o '<sa [^>]*why="finding-gone"[^>]*/>' "$TMP/findinggone" | grep -vE 'kind="(duplication|new-clone-of-reused-helper)' )"
if [ -z "$FG_ROWS" ]; then
    no "(5) no non-clone finding-gone row in the fixture — the arm cannot bite"
else
    FG_BAD="$( printf '%s\n' "$FG_ROWS" | grep -v ' sym="' )"
    [ -z "$FG_BAD" ] \
        && ok "(5) every non-clone why=\"finding-gone\" row names its symbol ($( printf '%s\n' "$FG_ROWS" | grep -c . ) rows)" \
        || { no "(5) a finding-gone <sa> row carries only a key hash — the reader cannot tell WHICH ack is stale"; printf '%s\n' "$FG_BAD"; }
    # and the name must be the RIGHT one, not just present: the fixture's stale complexity ack is knotty().
    printf '%s\n' "$FG_ROWS" | grep -q 'kind="complexity"[^>]*sym="[^"]*knotty"' \
        && ok "(5) the stale complexity ack is named as knotty(), the symbol it was written for" \
        || { no "(5) the finding-gone complexity row names the wrong symbol"; printf '%s\n' "$FG_ROWS"; }
    # …and it carries the LOCATOR every other row family in this document carries, so it is one paste from
    # --expand (the gating <r> rows' own p="path:line" shape).
    printf '%s\n' "$FG_ROWS" | grep -q 'kind="complexity"[^>]*p="[^"]*src/lib\.cpp:[0-9]*"' \
        && ok "(5) the named row carries p=\"path:line\", the locator the gating rows use" \
        || { no "(5) the named row carries no p= locator"; printf '%s\n' "$FG_ROWS"; }
fi
# the counterpart: target-gone is unnameable BY CONSTRUCTION, so it must not fabricate a name.
grep -o '<sa [^>]*why="target-gone"[^>]*/>' "$TMP/targetgone" | grep -q ' sym="' \
    && { no "(5) a target-gone row names a symbol the current tree does not have"; grep -o '<sa [^>]*/>' "$TMP/targetgone"; } \
    || ok "(5) target-gone rows name nothing — the tree cannot name what it no longer holds"
# and the rule itself is stated where the attribute is emitted (legendcoveragecheck's rule, pinned here too).
# the rule itself is stated where the attribute is emitted (legendcoveragecheck's rule, pinned here too).
# The legend is everything BEFORE the root start tag — a greedy <!--…--> regex over a one-line document
# would capture only the last comment.
if grep -q '<sa [^>]*sym="' "$TMP/findinggone"; then
    sed 's/<quality-delta.*//' "$TMP/findinggone" | grep -q 'sym=' \
        && ok "(5) the sa sym= rule is defined in the document's own legend" \
        || no "(5) sa sym= is emitted with no legend definition"
else
    no "(5) no sa row carried sym= — the legend arm cannot bite"
fi

# ── (4) a second, independent clean fixture also reports stale="0" — not a one-off on the first tree ────
mkdir -p "$REPO2/src"
cat > "$REPO2/src/other.cpp" <<'EOF'
int stable2( int a ) { return a + 1; }
EOF
git -C "$REPO2" init -q; git -C "$REPO2" config user.email x@y; git -C "$REPO2" config user.name x
git -C "$REPO2" add -A; git -C "$REPO2" commit -qm init >/dev/null
cat > "$REPO2/src/other.cpp" <<'EOF'
int stable2( int a ) { return a + 1; }
int knotty2( int a, int b, int c ) {
    int r = 0;
    for( int i = 0; i < a; ++i ) {
        if( i % 2 == 0 ) { if( i > b ) { r += i; } else { r -= 1; } }
        else { for( int j = 0; j < b; ++j ) { if( j > c ) { r += j; } else { r--; } } }
        while( r > c && r > b ) { r = r - 1; if( r % 3 == 0 ) { r += 2; } }
    }
    return r;
}
EOF
run2 --quality-delta --quality-ack="fixture 2: accepted complexity" >/dev/null 2>&1
run2 --quality-delta >"$TMP/clean2" 2>/dev/null
if grep -q 'stale="0"' "$TMP/clean2" && ! grep -q '<sa ' "$TMP/clean2"; then
    ok "(4) a second, independent clean fixture also reports stale=\"0\""
else
    no "(4) unexpected stale reporting on the second clean fixture"
    grep -o '<quality-delta[^>]*>\|<sa[^>]*/>' "$TMP/clean2"
fi

[ "$fail" -eq 0 ] && echo "staleackcheck: ALL PASS" || { echo "staleackcheck: SOME CHECKS FAILED"; exit 1; }
