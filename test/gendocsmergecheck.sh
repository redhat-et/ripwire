#!/usr/bin/env bash
# gendocsmergecheck.sh — two open changes that each add a gate and a cap, and regenerate the docs as
# CONTRIBUTING says, merge with no textual conflict on any TOTAL in either order, and the merge result passes
# every generator check. Scope of "no conflict": the two changes here touch different source files and gate
# names far apart in the sorted list. Two caps in the SAME file, or two gate names adjacent in the list, still
# conflict on their per-item lines (docs/LIMITS.md rows, the absorb list) — git cannot merge two insertions
# at one spot; scripts/merge_main.sh settles those (it rebuilds LIMITS.md and set-merges the list), GitHub's
# mergeability check does not. GEN-DOCS-MERGE, 2026-11-02: before it, every landing rewrote the totals in README.md,
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
#   (N5) a generator that passes the live preflight and fails in WRITE mode: refresh exits non-zero and every
#        file it writes (the snapshot, README, EVALS, deck, LIMITS, TUNING) is back to its bytes before it.
#   (N6) a hand-edited snapshot whose totals do not add up (silent + disclosing != caps): every generator refuses.
#   (N7) an impossible COUNTS_TAKEN date (2026-11-31): refresh refuses and the snapshot is unchanged.
#   (N8) a snapshot key no generator publishes: `show` lists it and counts it; `check` exits 1.
#   (N9) a marked gate-count site without its "counts snapshot YYYY-MM-DD" date: gatecount_build refuses.
#   (D)  the drift bound (the staleness rule, docs/counts_snapshot.py MAX_DRIFT): `check --max-drift` exits 0 on
#        THIS tree; on the fixture it exits 0 at the merged tree's drift of 2 gates, 1 once gates drift by 11
#        or caps by 21, and non-zero when a generator crashes. (Dr) release.yml runs the exact `check`.
#   (S)  no tracked *.sh (or extensionless sh/bash script) has an unbraced `$name` directly followed by a
#        non-ASCII byte outside a comment line: macOS bash 3.2 reads the byte as part of the name and `set -u`
#        kills the gate ("baseGates→: unbound variable", this gate's own CI red on macOS). Twins: a fixture
#        with one such line is caught (exactly that line), its braced and commented forms are not, and a
#        failing scan (unreadable file) is a FAIL, never a clean result.
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
# the fixture starts from an exact snapshot (both changes cut right after a refresh, same date), so its arms do
# not depend on how far this tree's own snapshot lags; arm (D) checks this tree's lag separately
taken="$( awk -F'\t' '$1 == "taken" { print $2 }' "$R/docs/counts.tsv" )"
( cd "$R" && COUNTS_TAKEN="$taken" python3 docs/counts_snapshot.py refresh >/dev/null ) || { echo "gendocsmergecheck: refresh failed on the fixture"; exit 2; }
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
want="gates.scripts ${baseGates}→$(( baseGates + 2 ))"
if [ "$rc" = 1 ] && printf '%s' "$out" | grep -qF "$want"; then ok "(P3) counts_snapshot.py check on the merged tree: exit 1, names $want"
else no "(P3) counts_snapshot.py check on the merged tree: exit $rc, expected 1 naming '$want'; got: $( printf '%s' "$out" | head -2 )"; fi
out="$( cd "$TMP/fresh" && COUNTS_TAKEN=2000-01-02 python3 docs/counts_snapshot.py refresh 2>&1 && python3 docs/counts_snapshot.py check 2>&1 )"; rc=$?
sites="$( grep -c "$(( baseGates + 2 )) gate scripts\|names $(( baseGates + 2 ))\|\"$(( baseGates + 2 ))\"" "$TMP/fresh/README.md" "$TMP/fresh/docs/EVALS.md" "$TMP/fresh/present/deck5_ripwire_build.js" | awk -F: '{ s += $2 } END { print s + 0 }' )"
if [ "$rc" = 0 ] && [ "$sites" -ge 8 ] && ( cd "$TMP/fresh" && python3 docs/gatecount_build.py --check >/dev/null 2>&1 ); then
    ok "(P3 twin) after refresh: check exits 0 and $sites site lines state $(( baseGates + 2 ))"
else
    no "(P3 twin) after refresh: exit $rc, $sites site lines state $(( baseGates + 2 )) (want >= 8): $( printf '%s' "$out" | tail -2 )"
fi

# a date no real snapshot has, so the arm cannot pass on the fixture's own `taken`
dated="$( cat "$TMP/fresh/README.md" "$TMP/fresh/docs/EVALS.md" "$TMP/fresh/present/deck5_ripwire_build.js" | grep -E '<!-- gatecount -->|// gatecount' | grep -c 'counts snapshot 2000-01-02' )"
if [ "$dated" -ge 8 ] && grep -q 'counts snapshot 2000-01-02 the tool had [0-9]* compile-time caps' "$TMP/fresh/README.md"; then
    ok "(P3 date) after refresh: $dated marked site lines and README's cap sentence carry the new date 2000-01-02"
else no "(P3 date) after refresh: $dated marked site lines carry the new date (want >= 8), cap sentence $( grep -c 'counts snapshot 2000-01-02 the tool' "$TMP/fresh/README.md" )"; fi

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

# ── (N5) write-mode failure after the live preflight: refresh restores every file it writes ─────────
cp -R "$M" "$TMP/n5"
cp "$M/docs/limits_build.py" "$TMP/n5/docs/limits_build_real.py"
cat > "$TMP/n5/docs/limits_build.py" <<'PY'
import os, subprocess, sys
here = os.path.dirname( os.path.abspath( __file__ ) )
if '--live-counts' in sys.argv[ 1: ]:
    sys.exit( subprocess.run( [ sys.executable, '-B', os.path.join( here, 'limits_build_real.py' ) ] + sys.argv[ 1: ] ).returncode )
sys.exit( 'write-mode stub failure' )
PY
out="$( cd "$TMP/n5" && COUNTS_TAKEN=2000-01-01 python3 docs/counts_snapshot.py refresh 2>&1 )"; rc=$?
same=0; for f in docs/counts.tsv README.md docs/EVALS.md present/deck5_ripwire_build.js docs/LIMITS.md docs/TUNING.md; do cmp -s "$M/$f" "$TMP/n5/$f" && same=$(( same + 1 )); done
if [ "$rc" != 0 ] && printf '%s' "$out" | grep -q 'failed after the refresh' && [ "$same" = 6 ]; then
    ok "(N5) a write-mode failure: refresh exits $rc and all 6 written files are restored (gatecount_build had already rewritten its 3)"
else no "(N5) write-mode failure: exit $rc, $same of 6 files restored: $( printf '%s' "$out" | tail -1 )"; fi

# ── (N6) a snapshot whose totals do not add up is refused by every generator ──────────────────────────
cp -R "$M" "$TMP/n6"
awk -F'\t' 'BEGIN { OFS = "\t" } $1 == "limits.silent" { $2 = $2 + 1 } { print }' "$M/docs/counts.tsv" > "$TMP/n6/docs/counts.tsv"
refused=0; for c in "docs/gatecount_build.py --check" "docs/limits_build.py --check" "bench/capsweep/capsweep.py emit --check"; do
    out="$( cd "$TMP/n6" && python3 $c 2>&1 )" || { printf '%s' "$out" | grep -q 'does not add up' && refused=$(( refused + 1 )); }
done
if ! cmp -s "$M/docs/counts.tsv" "$TMP/n6/docs/counts.tsv" && [ "$refused" = 3 ]; then
    ok "(N6) a hand-edited snapshot (limits.silent + 1, sums broken) is refused by all 3 generators"
else no "(N6) a snapshot that does not add up was refused by $refused of 3 generators"; fi

# ── (N7) an impossible date is refused ───────────────────────────────────────────────────────────────
cp -R "$M" "$TMP/n7"
out="$( cd "$TMP/n7" && COUNTS_TAKEN=2026-11-31 python3 docs/counts_snapshot.py refresh 2>&1 )"; rc=$?
if [ "$rc" != 0 ] && printf '%s' "$out" | grep -q 'not a real' && cmp -s "$M/docs/counts.tsv" "$TMP/n7/docs/counts.tsv"; then
    ok "(N7) COUNTS_TAKEN=2026-11-31: refresh refuses (exit $rc), snapshot unchanged"
else no "(N7) impossible date: exit $rc: $( printf '%s' "$out" | tail -1 )"; fi
out="$( cd "$TMP/n7" && COUNTS_TAKEN=2026-11-30 python3 docs/counts_snapshot.py refresh 2>&1 )"; rc=$?
if [ "$rc" = 0 ] && grep -qx 'taken	2026-11-30' "$TMP/n7/docs/counts.tsv"; then ok "(N7 twin) COUNTS_TAKEN=2026-11-30: refresh exits 0 and records it"
else no "(N7 twin) a real date: exit $rc: $( printf '%s' "$out" | tail -1 )"; fi

# ── (N8) an obsolete snapshot key: show lists it, check refuses ─────────────────────────────────────
cp -R "$M" "$TMP/n8"
printf 'limits.retired\t5\n' >> "$TMP/n8/docs/counts.tsv"
sout="$( cd "$TMP/n8" && python3 docs/counts_snapshot.py show 2>&1 )"; src=$?
( cd "$TMP/n8" && python3 docs/counts_snapshot.py check >/dev/null 2>&1 ); crc=$?
if [ "$src" = 0 ] && printf '%s' "$sout" | grep -q '^limits.retired .*no longer published' && printf '%s' "$sout" | grep -q '1 snapshot key(s) no longer published' && [ "$crc" = 1 ]; then
    ok "(N8) an obsolete key: show lists it and counts it (exit 0), check exits 1"
else no "(N8) obsolete key: show exit $src, check exit $crc: $( printf '%s' "$sout" | tail -1 )"; fi

# ── (N9) a marked site without its snapshot date ─────────────────────────────────────────────────────
cp -R "$M" "$TMP/n9"
python3 - "$TMP/n9/README.md" <<'PY'
import re, sys; p = sys.argv[ 1 ]; t = open( p ).read()
open( p, 'w' ).write( re.sub( r' \(counts snapshot [0-9-]+\)(?=, five contracts)', '', t, count = 1 ) )
PY
out="$( cd "$TMP/n9" && python3 docs/gatecount_build.py --check 2>&1 )"; rc=$?
if ! cmp -s "$M/README.md" "$TMP/n9/README.md" && [ "$rc" != 0 ] && printf '%s' "$out" | grep -q 'without its date'; then
    ok "(N9) a marked site that lost its snapshot date is refused (exit $rc)"
else no "(N9) undated site: exit $rc (injection $( cmp -s "$M/README.md" "$TMP/n9/README.md" && echo 'did NOT take' || echo took )): $( printf '%s' "$out" | head -1 )"; fi

# ── (D) the drift bound ─────────────────────────────────────────────────────────────────────────────
out="$( cd "$ROOT" && python3 docs/counts_snapshot.py check --max-drift 2>&1 )"; rc=$?
if [ "$rc" = 0 ]; then ok "(D) this tree: ${out#counts_snapshot: }"
else no "(D) this tree's counts snapshot lags past the bound (exit $rc) — run: python3 docs/counts_snapshot.py refresh in this PR: $out"; fi
out="$( cd "$M" && python3 docs/counts_snapshot.py check --max-drift 2>&1 )"; rc=$?
if [ "$rc" = 0 ]; then ok "(D twin) the merged fixture (2 gates and 2 caps behind) is within the bound"
else no "(D twin) the merged fixture, 2 behind, exit $rc: $out"; fi
setSnap(){   # $1 tree, $2 key, $3 delta; keeps SUMS true (caps moves silent and constants with it)
    python3 - "$1/docs/counts.tsv" "$2" "$3" <<'PY'
import sys
p, k, d = sys.argv[ 1 ], sys.argv[ 2 ], int( sys.argv[ 3 ] )
ks = [ k ] + ( [ 'limits.silent', 'limits.constants' ] if k == 'limits.caps' else [] )
out = []
for l in open( p ).read().split( '\n' ):
    f = l.split( '\t' )
    if len( f ) == 2 and f[ 0 ] in ks:
        l = '%s\t%d' % ( f[ 0 ], int( f[ 1 ] ) + d )
    out.append( l )
open( p, 'w' ).write( '\n'.join( out ) )
PY
}
for spec in "gates.scripts -9 1" "limits.caps -19 1" "gates.scripts -8 0"; do
    set -- $spec
    rm -rf "$TMP/d"; cp -R "$M" "$TMP/d"; setSnap "$TMP/d" "$1" "$2"
    out="$( cd "$TMP/d" && python3 docs/counts_snapshot.py check --max-drift 2>&1 )"; rc=$?
    if [ "$rc" = "$3" ]; then ok "(D) $1 snapshot moved by $2 on the merged fixture: check --max-drift exits $rc as expected"
    else no "(D) $1 moved by $2: exit $rc, expected $3: $out"; fi
done
( cd "$TMP/n4" && python3 docs/counts_snapshot.py check --max-drift >/dev/null 2>&1 ); rc=$?
if [ "$rc" != 0 ]; then ok "(D crash) a crashing generator: check --max-drift exits $rc, never a pass"
else no "(D crash) check --max-drift passed with a crashing generator"; fi
if [ -f "$ROOT/.github/workflows/release.yml" ] && grep -qE '^[[:space:]]*python3 docs/counts_snapshot\.py check[[:space:]]*(\|\||$)' "$ROOT/.github/workflows/release.yml"; then
    ok "(Dr) .github/workflows/release.yml runs the exact counts_snapshot.py check before publishing"
else no "(Dr) .github/workflows/release.yml does not run 'python3 docs/counts_snapshot.py check' (the release refusal of a stale snapshot)"; fi

# ── (S) unbraced `$name` + non-ASCII byte: bash 3.2 (macOS) reads the byte into the name ─────────────────
# scanShell FILE...: prints FILE:LINE:text for each hit outside a comment line; exit 0 hits, 1 none, 2 error.
scanShell(){
    local hits rc
    hits="$( LC_ALL=C grep -nHE '\$[A-Za-z_][A-Za-z0-9_]*[^ -~[:space:]]' "$@" )"; rc=$?
    [ "$rc" -gt 1 ] && return 2
    hits="$( printf '%s\n' "$hits" | LC_ALL=C grep -vE '^[^:]*:[0-9]+:[[:space:]]*#' | LC_ALL=C grep -v '^$' )"
    [ -n "$hits" ] || return 1
    printf '%s\n' "$hits"; return 0
}
sfx="$TMP/s"; mkdir -p "$sfx"
arr="$( printf '\342\206\222' )"   # the arrow, built from octal so this file never holds the pattern it bans
printf '%s\n' 'set -u' 'n=1' "a=\"x \$n${arr}y\"" "b=\"x \${n}${arr}y\"" "# c=\"x \$n${arr}y\" in a comment" > "$sfx/bad.sh"
out="$( scanShell "$sfx/bad.sh" )"; rc=$?
if [ "$rc" = 0 ] && [ "$( printf '%s\n' "$out" | wc -l | tr -d ' ' )" = 1 ] && printf '%s' "$out" | grep -q ':3:a='; then
    ok "(S twin) the fixture's one unbraced \$n-then-arrow line is caught; its braced and commented forms are not"
else no "(S twin) fixture scan: exit $rc, expected 0 with exactly line 3: $out"; fi
scanShell "$sfx/no-such-file.sh" >/dev/null 2>&1; rc=$?
if [ "$rc" = 2 ]; then ok "(S twin) a scan that cannot read its file exits 2, never a clean result"
else no "(S twin) a scan of a missing file exited $rc, expected 2"; fi
shl="$TMP/shfiles"
if ( cd "$ROOT" && git ls-files '*.sh' && git grep -lE '^#!/(usr/)?bin/(env )?(ba)?sh' -- . ':!*.sh' ':!*.md' ) > "$shl" 2>"$TMP/shl.err"; then
    nsh="$( LC_ALL=C sort -u "$shl" | grep -c . )"
    if [ "$nsh" -lt 100 ]; then no "(S) only $nsh tracked shell files listed (want >= 100): the listing is broken"
    else
        LC_ALL=C sort -u "$shl" > "$TMP/shl.sorted"
        # read the list into the positional parameters through a loop (bash 3.2: no mapfile)
        set --; while IFS= read -r f; do set -- "$@" "$f"; done < "$TMP/shl.sorted"
        out="$( cd "$ROOT" && scanShell "$@" )"; rc=$?; set --
        if [ "$rc" = 1 ]; then ok "(S) $nsh tracked shell scripts: no unbraced \$name directly followed by a non-ASCII byte"
        elif [ "$rc" = 0 ]; then no "(S) unbraced \$name before a non-ASCII byte (bash 3.2 reads it into the name; write \${name}): $( printf '%s' "$out" | head -5 )"
        else no "(S) the shell scan failed (exit $rc) over $nsh files"; fi
    fi
else no "(S) could not list the tracked shell scripts: $( head -2 "$TMP/shl.err" )"; fi

[ $fail -eq 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit $fail
