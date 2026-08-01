#!/usr/bin/env bash
# mapdiffcheck.sh — gate for --map-diff, which had ZERO coverage. --map-diff is NOT a filter: it is a
# PageRank TELEPORT reweighting (§3 / src/graph.h:1071 "β of the mass on symbols in changed files,
# (1−β) on the rest"). The map still shows every symbol; symbols in git-changed files get a rank BOOST.
# The high-value, hand-verifiable contract is therefore a RANK FLIP, which this gate constructs from a
# synthetic git repo whose natural PageRank order is known:
#
#   a.cpp:  a1()            (leaf, no in-corpus callers)
#   b.cpp:  b1() <- b2(), b1() <- b3()   (b1 has in-degree 2 → b1 out-ranks a1 under PLAIN pagerank)
#
# Commit both, THEN edit a.cpp only. Expected:
#   plain  --no-cache      : b1.k  >  a1.k   (b1 wins by structural importance)
#   --map-diff             : a1.k  >  b1.k   (a.cpp is the changed file → teleport boosts a1 past b1)
# i.e. the ordering of a1 vs b1 must INVERT between the two runs. That inversion cannot happen unless the
# diff teleport is actually reweighting toward changed files — a mode that silently fell through to plain
# pagerank would leave b1 on top in both runs.
#
# Also gated: --map-diff on a clean tree (no diff) still emits a valid map; determinism.
#
# Usage:  RIPWIRE_BIN=build/ripwire bash test/mapdiffcheck.sh   |   RIPWIRE_BIN=asan/ripwire bash …
# Exits non-zero on any failure. Does NOT edit regression.sh. Needs git.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${RIPWIRE_BIN:-$ROOT/build/ripwire}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
command -v git >/dev/null 2>&1 || { echo "git required for --map-diff gate"; exit 2; }
echo "mapdiffcheck: BIN=$BIN"

TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
R="$TMP/repo"; mkdir -p "$R/src"
git -C "$R" init -q
git -C "$R" config user.email a@x.com
git -C "$R" config user.name  A

printf 'int a1() { return 1; }\n'                                        > "$R/src/a.cpp"
printf 'int b1() { return 1; }\nint b2() { return b1(); }\nint b3() { return b1(); }\n' > "$R/src/b.cpp"
git -C "$R" add -A
GIT_AUTHOR_DATE="2026-06-01T00:00:00" GIT_COMMITTER_DATE="2026-06-01T00:00:00" \
    git -C "$R" commit -q -m init

k(){ printf '%s' "$1" | grep -oE 'n="'"$2"'" k="[0-9.]+"' | head -1 | grep -oE 'k="[0-9.]+"' | sed 's/k="//;s/"//'; }
gt(){ awk -v x="$1" -v y="$2" 'BEGIN{ exit !(x+0 > y+0) }'; }

# ── 0) baseline sanity: under PLAIN pagerank, b1 (in-degree 2) out-ranks a1 (leaf) ────────────────────
PLAIN0="$( "$BIN" "$R" --no-cache 2>/dev/null )"
a1p="$( k "$PLAIN0" a1 )"; b1p="$( k "$PLAIN0" b1 )"
{ [ -n "$a1p" ] && [ -n "$b1p" ] && gt "$b1p" "$a1p"; } \
    && ok "baseline: plain pagerank ranks b1 ($b1p) > a1 ($a1p) — structural importance" \
    || no "baseline broken: expected b1 > a1 under plain pagerank (a1=$a1p b1=$b1p)"

# ── 1) edit a.cpp only, then --map-diff must FLIP the order: a1 > b1 ──────────────────────────────────
printf 'int a1() { return 2; }\n' > "$R/src/a.cpp"    # working-tree edit, a.cpp is now the changed file
DIFF="$( "$BIN" "$R" --map-diff --no-cache 2>/dev/null )"
a1d="$( k "$DIFF" a1 )"; b1d="$( k "$DIFF" b1 )"
{ [ -n "$a1d" ] && [ -n "$b1d" ] && gt "$a1d" "$b1d"; } \
    && ok "--map-diff FLIPS the order: a1 ($a1d) > b1 ($b1d) — teleport boosts the changed file (a.cpp)" \
    || no "--map-diff did NOT boost the changed file: expected a1 > b1, got a1=$a1d b1=$b1d (mode may have fallen through to plain pagerank)"

# ── 1b) D6: the header's changed="N" names the teleport-seed file count — here exactly 1
#       (a.cpp), so agents can tell a real diff from a degrade/clean-tree run without shelling to git. ──
changed1="$( printf '%s' "$DIFF" | grep -oE 'changed=[0-9]+' | head -1 | grep -oE '[0-9]+' )"
[ "$changed1" = 1 ] \
    && ok "--map-diff header reports changed=1 (a.cpp is the one seed file)" \
    || no "--map-diff header changed= wrong or missing (got '$changed1', expected 1)"

# ── 1c) the default map (no --map-diff) never carries changed= — zero token cost for every other caller ──
PLAIN_NOCHANGED="$( "$BIN" "$R" --no-cache 2>/dev/null )"
printf '%s' "$PLAIN_NOCHANGED" | grep -q 'changed=' \
    && no "default map unexpectedly carries changed= (should be absent — nullptr means omitted)" \
    || ok "default map has no changed= attribute (nullptr → zero token cost, byte-identical to before D6)"

# ── 2) the flip is real (both symbols present, and the inequality genuinely reversed) ────────────────
{ gt "$b1p" "$a1p" && gt "$a1d" "$b1d"; } \
    && ok "rank inequality INVERTED between plain (b1>a1) and --map-diff (a1>b1) — diff teleport is active" \
    || no "no inversion — plain(b1>a1)=$( gt "$b1p" "$a1p" && echo y || echo n) diff(a1>b1)=$( gt "$a1d" "$b1d" && echo y || echo n)"

# ── 3) --map-diff on a CLEAN tree (no working-tree diff) still emits a full valid map, all symbols ────
git -C "$R" checkout -q -- src/a.cpp   # revert the working-tree edit → no diff vs HEAD
CLEAN="$( "$BIN" "$R" --map-diff --no-cache 2>/dev/null )"
csyms="$( printf '%s' "$CLEAN" | grep -oE 'symbols=[0-9]+' | head -1 | grep -oE '[0-9]+' )"
{ [ "$csyms" = 4 ] && printf '%s' "$CLEAN" | grep -q 'n="a1"' && printf '%s' "$CLEAN" | grep -q 'n="b1"'; } \
    && ok "--map-diff on a clean tree: full map (4 symbols, a1+b1 present) — degrades to normal ranking" \
    || no "--map-diff clean-tree map wrong (symbols=$csyms)"

# ── 3b) D6: a clean tree reports changed=0 — the honest "nothing to seed" signal, not an absent attribute ──
cchanged="$( printf '%s' "$CLEAN" | grep -oE 'changed=[0-9]+' | head -1 | grep -oE '[0-9]+' )"
[ "$cchanged" = 0 ] \
    && ok "--map-diff on a clean tree reports changed=0" \
    || no "--map-diff clean-tree changed= wrong or missing (got '$cchanged', expected 0)"

# ── 4) determinism ───────────────────────────────────────────────────────────────────────────────────
printf 'int a1() { return 2; }\n' > "$R/src/a.cpp"
D1="$( "$BIN" "$R" --map-diff --no-cache 2>/dev/null )"
D2="$( "$BIN" "$R" --map-diff --no-cache 2>/dev/null )"
[ "$D1" = "$D2" ] && ok "--map-diff deterministic (byte-identical run-to-run)" || no "--map-diff non-deterministic"

# ── 5) xml well-formed ───────────────────────────────────────────────────────────────────────────────
if command -v xmllint >/dev/null 2>&1; then
    printf '%s' "$D1" | xmllint --noout - 2>/dev/null && ok "--map-diff xml well-formed" || no "--map-diff xml malformed"
else
    printf '  SKIP  xml well-formed (no xmllint)\n'
fi

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit $fail
