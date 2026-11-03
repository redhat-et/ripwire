#!/usr/bin/env bash
# gendocsmergecheck.sh — two open changes that each add a gate and a cap, and regenerate the docs as
# CONTRIBUTING says, merge with NO textual conflict in either order, and the merge result passes every
# generator check. GEN-DOCS-MERGE, 2026-11-02: before it, every landing rewrote the totals in README.md,
# docs/LIMITS.md and docs/TUNING.md (and docs/EVALS.md + the deck for a gate), so GitHub marked every other
# open PR CONFLICTING and each one needed a main merge plus a full CI run. The totals are now the dated
# snapshot docs/counts.tsv (docs/counts_snapshot.py); a feature change rewrites only per-item lines.
#
# Every arm runs in a throwaway git repository built from this tree (src/, docs/, bench/capsweep, scripts/,
# README.md, the deck, test/regression.sh, test/lib and an empty stub per top-level test/*.sh), so the real
# generators run exactly as on a branch, and `git merge-tree --write-tree` plays GitHub's mergeability check.
#   (P1) A then B and B then A: merge-tree exits 0 (clean), both ways, with both gates and both caps present.
#   (P2) on the merged tree: gatecount_build, limits_build and capsweep emit --check pass, and the gate
#        registry (test/lib/gateregistry.py) proves list == files.
#   (P3) the snapshot is honest about lagging: counts_snapshot.py check exits 1 on the merged tree and names
#        gates.scripts N→N+2 (negative twin); after `refresh` it exits 0 and every gatecount site states N+2.
#   (N1) a hand-edited total on the merged tree (one gatecount site) turns gatecount_build --check red.
#   (N2) a lost per-file LIMITS.md row (a botched merge) turns limits_build --check red.
#   (N3) docs/counts.tsv without its gates.scripts line: the generator exits non-zero, never publishes live.
#   (N4) docs/counts.tsv written by a generator that crashes: counts_snapshot.py refresh exits non-zero and
#        leaves the snapshot unchanged.
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

command -v git >/dev/null || { echo "gendocsmergecheck: git not found"; exit 2; }
for f in docs/gatecount_build.py docs/limits_build.py bench/capsweep/capsweep.py test/lib/gateregistry.py; do
    [ -f "$ROOT/$f" ] || { echo "gendocsmergecheck: $f is missing"; exit 2; }
done
TMP="$( mktemp -d -t gendocsmergecheck.XXXXXX )" || exit 2
trap 'rm -rf "$TMP"' EXIT
R="$TMP/repo"
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 GIT_AUTHOR_NAME=gdm GIT_AUTHOR_EMAIL=gdm@example.invalid \
       GIT_COMMITTER_NAME=gdm GIT_COMMITTER_EMAIL=gdm@example.invalid GIT_TERMINAL_PROMPT=0
mkdir -p "$R/test" || exit 2
( cd "$ROOT" && tar cf - src docs bench/capsweep scripts present/deck5_ripwire_build.js README.md test/regression.sh test/lib ) \
    | ( cd "$R" && tar xf - ) || { echo "gendocsmergecheck: could not copy the tree"; exit 2; }
for f in "$ROOT"/test/*.sh; do [ -f "$f" ] && [ ! -e "$R/test/${f##*/}" ] && : > "$R/test/${f##*/}"; done
g(){ git -C "$R" "$@"; }
g init -q -b base . >/dev/null 2>&1 || g init -q . || exit 2
g checkout -q -B base 2>/dev/null
g add -A && g commit -q -m base || { echo "gendocsmergecheck: fixture commit failed"; exit 2; }

regen(){   # what CONTRIBUTING tells a contributor to run after adding a gate or a cap
    ( cd "$1" && python3 docs/gatecount_build.py && python3 docs/limits_build.py && python3 bench/capsweep/capsweep.py emit ) >/dev/null
}
addGateAndCap(){   # $1 branch, $2 gate name, $3 src file, $4 cap name
    g checkout -q -B "$1" base || return 1
    : > "$R/test/$2.sh"
    python3 - "$R/test/regression.sh" "$2" <<'PY' || return 1
import re, sys
p, n = sys.argv[ 1 ], sys.argv[ 2 ]; t = open( p ).read()
m = re.search( r'^for _g in \\\n(.*?)^    ; do\n', t, re.S | re.M )
if m is None:
    sys.exit( 'no one-name-per-line absorb list' )
body = sorted( set( m.group( 1 ).split( '\n' )[ :-1 ] + [ '    %s \\' % n ] ) )
open( p, 'w' ).write( t[ :m.start( 1 ) ] + '\n'.join( body ) + '\n' + t[ m.end( 1 ): ] )
PY
    printf 'inline constexpr std::size_t %s = 7;  // gendocsmergecheck fixture cap\n' "$4" >> "$R/$3" || return 1
    regen "$R" || return 1
    g add -A && g commit -q -m "$1 adds $2 and $4"
}
( cd "$R" && python3 docs/gatecount_build.py --check >/dev/null 2>&1 ) || { echo "gendocsmergecheck: the fixture's gatecount --check did not pass at base"; exit 2; }
baseGates="$( grep -oE '[*][*][0-9]+ gate scripts[*][*]' "$R/README.md" | head -1 | grep -oE '[0-9]+' )"
[ -n "$baseGates" ] || { echo "gendocsmergecheck: no '**N gate scripts**' in the fixture's README.md"; exit 2; }
addGateAndCap lane-a bgdmonecheck   src/abicheck.h kGdmAlphaCap || { echo "gendocsmergecheck: could not build branch lane-a"; exit 2; }
addGateAndCap lane-b xgdmtwocheck   src/wrap.h     kGdmOmegaCap || { echo "gendocsmergecheck: could not build branch lane-b"; exit 2; }

# ── (P1) clean both ways ─────────────────────────────────────────────────────────────────────────────
for order in "lane-a lane-b" "lane-b lane-a"; do
    set -- $order
    out="$( g merge-tree --write-tree --name-only "$1" "$2" 2>&1 )"; rc=$?
    if [ "$rc" = 0 ]; then
        ok "(P1) merge-tree $1 into $2: clean (tree ${out%%$'\n'*})"
    else
        no "(P1) merge-tree $1 x $2 CONFLICTS (exit $rc) on: $( printf '%s\n' "$out" | sed -n '2,/^$/p' | grep . | tr '\n' ' ' )"
    fi
done
tree="$( g merge-tree --write-tree lane-a lane-b 2>/dev/null | head -1 )"
M="$TMP/merged"; mkdir -p "$M"
if [ -n "$tree" ] && g archive "$tree" | tar -x -C "$M" 2>/dev/null; then
    listed=0; for n in bgdmonecheck xgdmtwocheck; do grep -qx "    $n \\\\" "$M/test/regression.sh" && listed=$(( listed + 1 )); done
    caps=0; grep -q kGdmAlphaCap "$M/docs/LIMITS.md" && caps=$(( caps + 1 )); grep -q kGdmOmegaCap "$M/docs/LIMITS.md" && caps=$(( caps + 1 ))
    [ "$listed" = 2 ] && [ "$caps" = 2 ] && ok "(P1) the merged tree lists both gates and both caps' LIMITS.md rows" \
        || no "(P1) the merged tree lists $listed of 2 gates and $caps of 2 cap rows"
else
    no "(P1) could not materialise the merged tree"; echo "FAILURES ABOVE"; exit 1
fi

# ── (P2) every generator check passes on the merge result ────────────────────────────────────────────
for c in "docs/gatecount_build.py --check" "docs/limits_build.py --check" "bench/capsweep/capsweep.py emit --check"; do
    if out="$( cd "$M" && python3 $c 2>&1 )"; then ok "(P2) $c on the merged tree: ${out#*: }"; else no "(P2) $c on the merged tree FAILED: $out"; fi
done
lst="$TMP/listing"
for f in "$M"/test/*.sh; do [ -f "$f" ] && [ "${f##*/}" != regression.sh ] && { f="${f##*/}"; printf '%s\n' "${f%.sh}"; }; done | LC_ALL=C sort > "$lst"
if out="$( python3 "$M/test/lib/gateregistry.py" "$M/test/regression.sh" "$lst" 2>&1 )"; then ok "(P2) gate registry on the merged tree: list == files"
else no "(P2) gate registry on the merged tree FAILED: $( printf '%s' "$out" | head -3 )"; fi

# ── (P3) the snapshot says it lags, and refresh makes it exact ──────────────────────────────────────
cp -R "$M" "$TMP/fresh"
out="$( cd "$TMP/fresh" && python3 docs/counts_snapshot.py check 2>&1 )"; rc=$?
want="gates.scripts $baseGates→$(( baseGates + 2 ))"
if [ "$rc" = 1 ] && printf '%s' "$out" | grep -qF "$want"; then ok "(P3) counts_snapshot.py check on the merged tree: exit 1, names $want"
else no "(P3) counts_snapshot.py check on the merged tree: exit $rc, expected 1 naming '$want'; got: $( printf '%s' "$out" | head -2 )"; fi
out="$( cd "$TMP/fresh" && COUNTS_TAKEN=2026-11-03 python3 docs/counts_snapshot.py refresh 2>&1 && python3 docs/counts_snapshot.py check 2>&1 )"; rc=$?
sites="$( grep -c "$(( baseGates + 2 )) gate scripts\|names $(( baseGates + 2 ))\|\"$(( baseGates + 2 ))\"" "$TMP/fresh/README.md" "$TMP/fresh/docs/EVALS.md" "$TMP/fresh/present/deck5_ripwire_build.js" | awk -F: '{ s += $2 } END { print s + 0 }' )"
if [ "$rc" = 0 ] && [ "$sites" -ge 8 ] && ( cd "$TMP/fresh" && python3 docs/gatecount_build.py --check >/dev/null 2>&1 ); then
    ok "(P3 twin) after refresh: check exits 0 and $sites site lines state $(( baseGates + 2 ))"
else
    no "(P3 twin) after refresh: exit $rc, $sites site lines state $(( baseGates + 2 )) (want >= 8): $( printf '%s' "$out" | tail -2 )"
fi

# ── (N1) a hand-edited total ─────────────────────────────────────────────────────────────────────────
cp -R "$M" "$TMP/n1"
python3 - "$TMP/n1/README.md" "$baseGates" <<'PY'
import sys; p, n = sys.argv[ 1 ], sys.argv[ 2 ]; t = open( p ).read()
open( p, 'w' ).write( t.replace( '**%s gate scripts**' % n, '**%d gate scripts**' % ( int( n ) + 2 ), 1 ) )
PY
if ! cmp -s "$M/README.md" "$TMP/n1/README.md" && ! ( cd "$TMP/n1" && python3 docs/gatecount_build.py --check >/dev/null 2>&1 ); then
    ok "(N1) a gatecount site hand-edited to the live number (not the snapshot) is red"
else no "(N1) a hand-edited gatecount site was not caught (or the injection did not take)"; fi

# ── (N2) a lost per-file row ─────────────────────────────────────────────────────────────────────────
cp -R "$M" "$TMP/n2"
grep -v kGdmOmegaCap "$M/docs/LIMITS.md" > "$TMP/n2/docs/LIMITS.md"
if ! cmp -s "$M/docs/LIMITS.md" "$TMP/n2/docs/LIMITS.md" && ! ( cd "$TMP/n2" && python3 docs/limits_build.py --check >/dev/null 2>&1 ); then
    ok "(N2) a LIMITS.md that lost one side's cap row is red"
else no "(N2) a LIMITS.md missing a cap row was not caught (or the injection did not take)"; fi

# ── (N3) a snapshot missing a key is an error, never the live number ────────────────────────────────
cp -R "$M" "$TMP/n3"
grep -v '^gates\.scripts' "$M/docs/counts.tsv" > "$TMP/n3/docs/counts.tsv"
out="$( cd "$TMP/n3" && python3 docs/gatecount_build.py 2>&1 )"; rc=$?
if [ "$rc" != 0 ] && printf '%s' "$out" | grep -q 'has no gates.scripts' && cmp -s "$M/README.md" "$TMP/n3/README.md"; then
    ok "(N3) docs/counts.tsv without gates.scripts: the generator refuses (exit $rc) and writes nothing"
else no "(N3) a snapshot missing gates.scripts: exit $rc, output: $( printf '%s' "$out" | head -1 )"; fi

# ── (N4) a crashing generator: refresh fails and leaves the snapshot alone ──────────────────────────
cp -R "$M" "$TMP/n4"
printf 'import sys\nsys.exit( "crash stub" )\n' > "$TMP/n4/docs/limits_build.py"
( cd "$TMP/n4" && python3 docs/counts_snapshot.py refresh >/dev/null 2>&1 ); rc=$?
if [ "$rc" != 0 ] && cmp -s "$M/docs/counts.tsv" "$TMP/n4/docs/counts.tsv"; then
    ok "(N4) refresh with a crashing generator exits $rc and leaves docs/counts.tsv unchanged"
else no "(N4) refresh with a crashing generator: exit $rc, snapshot $( cmp -s "$M/docs/counts.tsv" "$TMP/n4/docs/counts.tsv" && echo unchanged || echo CHANGED )"; fi

[ $fail -eq 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit $fail
