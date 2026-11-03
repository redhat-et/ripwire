#!/usr/bin/env bash
# mergemaincheck.sh — scripts/merge_main.sh settles only what has a mechanical answer, and never reports
# "merged" over a conflict it did not settle.
#
# Every arm runs the REAL script end to end in a throwaway git repository built from this tree (src/, docs/,
# the generators, scripts/, regression.sh, and an empty stub for every top-level test/*.sh), so the generators
# and the registry run exactly as they do on a branch. Each negative arm has a positive twin, and every arm
# reads the script's exit status and the resulting HEAD, never only its text.
#   (M1) a hand-written number on a gatecount-marked line (docs/EVALS.md's "~210 ... 200+") is NOT settled by
#        "only the numbers differ": the merge stops on docs/EVALS.md. Twin: the same two gate additions with no
#        hand edit, but different counts on the two sides, merge with exit 0 and the count regenerated.
#   (M2) `git add` of a file that still holds conflict markers clears git's unmerged state; --continue must
#        refuse (exit 1, nothing committed). Twin: the file resolved for real commits with exit 0.
#   (M3) the one-time reshape: a branch still on the old one-line `for _g in …; do` list merging the new
#        one-name-per-line list (both directions) settles with exit 0 and both sides' new gates listed.
#        Neighbour: an old side that also changed a loop line inside the same hunk stays a conflict.
#   (S1) a gate file deleted on one side and kept by hand from a delete/modify conflict is unregistered:
#        --continue must refuse. Twin: accepting the delete commits with exit 0.
#   (N2) a binary-pinned conflict (docs/COMMANDS.md) takes main's side, commits, exits 3, and the REGEN list
#        is in the merge commit message.
#   (X)  a crashing scripts/merge_resolve.py (on a merge with count conflicts) is exit 2 ("error"), never 1 ("conflicts left") or 0.
#   (M4) a side that only re-ran the generator on a marked line yields to a side that reworded it (count regenerated).
#        Neighbour: a rewording that also adds a non-owned number stays a conflict.
#   (M5) a rewording that keeps a non-owned number's digits but changes its qualifier ("200+" -> "200", "~210" ->
#        "210") is a changed figure: it stays a conflict (exit 1), never a silent rewording.
#   (R2) --regen-after-build re-pins only parity labels the marked merge's two parents pinned differently: a
#        label both parents agreed on that moves is refused (exit 1, nothing committed, the label named). Twin:
#        only the conflicted label moves -> exit 0, and the commit message names it. (Stub parity gate + stub BIN.)
#   (R3) a merge with marks, then a merge without: --regen-after-build still settles the earlier marks (exit 0,
#        re-pinned), never "nothing to re-record".
#   (R1) CAPTURE-DICTV-DRIFT: a merge that brings main's newer capture marks it REGEN AFTER BUILD (exit 3, no
#        conflict needed); --regen-after-build BIN re-records the dictv=/entries= pair from BIN and commits (exit 0).
#        Crash twin: a binary whose --legend-dict fails gives exit 1 and commits nothing. Needs BIN ($1); SKIP without.
# The fixture runs the generators WITHOUT docs/counts.tsv (live totals), the shape every branch cut before the
# counts snapshot has; test/gendocsmergecheck.sh covers merges of branches that have the snapshot.
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
case "$BIN" in /*) ;; *) BIN="$ROOT/$BIN" ;; esac
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

command -v git >/dev/null || { echo "mergemaincheck: git not found"; exit 2; }
for f in scripts/merge_main.sh scripts/merge_resolve.py docs/gatecount_build.py docs/limits_build.py bench/capsweep/capsweep.py test/lib/gateregistry.py; do
    [ -f "$ROOT/$f" ] || { echo "mergemaincheck: $f is missing"; exit 2; }
done
TMP="$( mktemp -d -t mergemaincheck.XXXXXX )" || exit 2
trap 'rm -rf "$TMP"' EXIT
R="$TMP/repo"
# an isolated git: no user config, hooks or signing can change what the arms see
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 GIT_AUTHOR_NAME=mmc GIT_AUTHOR_EMAIL=mmc@example.invalid \
       GIT_COMMITTER_NAME=mmc GIT_COMMITTER_EMAIL=mmc@example.invalid GIT_TERMINAL_PROMPT=0
mkdir -p "$R/test" || exit 2
( cd "$ROOT" && tar cf - src docs bench/capsweep scripts present/deck5_ripwire_build.js README.md test/regression.sh test/lib ) \
    | ( cd "$R" && tar xf - ) || { echo "mergemaincheck: could not copy the tree"; exit 2; }
for f in "$ROOT"/test/*.sh; do [ -f "$f" ] && [ ! -e "$R/test/${f##*/}" ] && : > "$R/test/${f##*/}"; done
rm -f "$R/docs/counts.tsv"      # live totals: see the header
( cd "$R" && python3 docs/gatecount_build.py && python3 docs/limits_build.py && python3 bench/capsweep/capsweep.py emit ) >/dev/null \
    || { echo "mergemaincheck: the generators failed on the fixture"; exit 2; }
g(){ git -C "$R" "$@"; }
g init -q -b base . >/dev/null 2>&1 || g init -q . || exit 2
g checkout -q -B base 2>/dev/null
g add -A && g commit -q -m base || { echo "mergemaincheck: fixture commit failed"; exit 2; }

addGate(){   # $1 name: stub file + its list line at the sorted place, then the count regenerated
    : > "$R/test/$1.sh"
    python3 - "$R/test/regression.sh" "$1" <<'PY' || return 1
import re, sys
p, n = sys.argv[ 1 ], sys.argv[ 2 ]; t = open( p ).read()
m = re.search( r'^for _g in \\\n(.*?)^    ; do\n', t, re.S | re.M )
if m:
    body = sorted( set( m.group( 1 ).split( '\n' )[ :-1 ] + [ '    %s \\' % n ] ) )
    t = t[ :m.start( 1 ) ] + '\n'.join( body ) + '\n' + t[ m.end( 1 ): ]
else:
    m = re.search( r'^for _g in ([^\n]*); do$', t, re.M )
    t = t[ :m.end( 1 ) ] + ' ' + n + t[ m.end( 1 ): ]
open( p, 'w' ).write( t )
PY
    ( cd "$R" && python3 docs/gatecount_build.py >/dev/null )
}
commitAll(){ g add -A && g commit -q -m "$1"; }
fresh(){   # $1 new branch from $2
    g merge --abort >/dev/null 2>&1; g reset -q --hard >/dev/null 2>&1; g clean -fdq >/dev/null 2>&1
    g checkout -q -B "$1" "$2" || { no "fixture: could not branch $1 from $2"; return 1; }
}
mm(){ ( cd "$R" && bash scripts/merge_main.sh "$@" ) > "$TMP/out" 2>&1; }
count(){ sed -n 's/.*loop in `test\/regression\.sh` names \([0-9][0-9]*\)[ .].*/\1/p' "$R/docs/EVALS.md" | head -1; }
listed(){ grep -qx "    $1 \\\\" "$R/test/regression.sh"; }
baseCount="$( count )"
[ -n "$baseCount" ] || { echo "mergemaincheck: could not read the fixture's gate count"; exit 2; }

# ── (M1) hand-written number on a marked line ─────────────────────────────────────────────────────────
fresh m1-main base && addGate zzmaincheck && commitAll "main adds a gate"
# the lane adds TWO gates, so its count lines differ from main's (base+2 vs base+1): a real conflict on them
fresh m1-twin base && addGate aaalanecheck && addGate aabbcheck && commitAll "lane adds two gates"
mm m1-main; rc=$?
if [ "$rc" = 0 ] && grep -q '^RESOLVED docs/EVALS.md c=' "$TMP/out" && [ "$( count )" = "$(( baseCount + 3 ))" ] && listed zzmaincheck && listed aabbcheck; then
    ok "(M1 twin) a count-only conflict on the marked lines is settled, exit 0, count regenerated to $(( baseCount + 3 ))"
else no "(M1 twin) count-only merge: rc=$rc count=$( count ) (want 0, docs/EVALS.md settled as (c), $(( baseCount + 3 ))): $( tail -3 "$TMP/out" | tr '\n' ' ' )"; fi
fresh m1-lane base && addGate aaalanecheck
before="$( cat "$R/docs/EVALS.md" )"
sed -i.bak -e '/loop in `test\/regression\.sh` names/s/~\([0-9][0-9]*\)/~9\1/' "$R/docs/EVALS.md" && rm -f "$R/docs/EVALS.md.bak"
if [ "$before" = "$( cat "$R/docs/EVALS.md" )" ]; then
    no "(M1) mutation did not take: no '~N' on the marked EVALS line to hand-edit"
else
    commitAll "lane adds a gate and hand-edits a number on a marked line"; head0="$( g rev-parse HEAD )"
    mm m1-main; rc=$?
    if [ "$rc" = 1 ] && grep -q '^UNTOUCHED docs/EVALS.md\|^PARTIAL docs/EVALS.md' "$TMP/out" && [ "$( g rev-parse HEAD )" = "$head0" ]; then
        ok "(M1) a hand-written number on a marked line stays a conflict (exit 1, docs/EVALS.md left for a person)"
    else no "(M1) hand-edited number: rc=$rc (want 1, docs/EVALS.md left): $( grep -E 'EVALS|merged' "$TMP/out" | tr '\n' ' ' )"; fi
fi

# ── (M2) staged conflict markers ──────────────────────────────────────────────────────────────────────
fresh m2-base base && printf 'line one\nline two\n' > "$R/conflict.txt" && commitAll "a plain file"
fresh m2-main m2-base && printf 'line one\nmain side\n' > "$R/conflict.txt" && commitAll "main edits"
fresh m2-lane m2-base && printf 'line one\nlane side\n' > "$R/conflict.txt" && commitAll "lane edits"
head0="$( g rev-parse HEAD )"
mm m2-main; rc=$?
if [ "$rc" != 1 ] || ! grep -q '^<<<<<<< ' "$R/conflict.txt"; then no "(M2) setup: a real conflict did not stop the merge (rc=$rc)"
else
    g add conflict.txt; mm --continue; rc=$?
    if [ "$rc" = 1 ] && [ "$( g rev-parse HEAD )" = "$head0" ] && grep -q 'conflict markers are still staged' "$TMP/out"; then
        ok "(M2) --continue refuses staged conflict markers (exit 1, nothing committed)"
    else no "(M2) staged markers: rc=$rc head moved=$( [ "$( g rev-parse HEAD )" = "$head0" ] && echo no || echo yes ): $( tail -2 "$TMP/out" | tr '\n' ' ' )"; fi
    printf 'line one\nlane side\nmain side\n' > "$R/conflict.txt"; g add conflict.txt; mm --continue; rc=$?
    if [ "$rc" = 0 ] && [ "$( g rev-parse HEAD^2 2>/dev/null )" = "$( g rev-parse m2-main )" ]; then
        ok "(M2 twin) the same conflict resolved for real commits the merge (exit 0)"
    else no "(M2 twin) resolved conflict: rc=$rc: $( tail -2 "$TMP/out" | tr '\n' ' ' )"; fi
fi

# ── (M3) the one-time reshape, both directions ────────────────────────────────────────────────────────
oldShape(){ python3 - "$R/test/regression.sh" <<'PY'
import re, sys
p = sys.argv[ 1 ]; t = open( p ).read()
m = re.search( r'^for _g in \\\n(.*?)^    ; do\n', t, re.S | re.M )
names = [ w for w in m.group( 1 ).split() if w != chr( 92 ) ]
open( p, 'w' ).write( t[ :m.start() ] + 'for _g in ' + ' '.join( names ) + '; do\n' + t[ m.end(): ] )
PY
}
fresh m3-old base && oldShape && ( cd "$R" && python3 docs/gatecount_build.py >/dev/null ) && commitAll "old one-line list"
fresh m3-new base && addGate zzmaincheck && commitAll "new list, main adds a gate"
fresh m3-oldlane m3-old && addGate aaalanecheck && commitAll "old-shape lane adds a gate"
# m3-new descends from base, not m3-old: graft so m3-old is the merge base of both sides
fresh m3-newmain m3-old && g checkout -q m3-new -- . && commitAll "reshape to the new list, main adds a gate"
for dir in lane-merges-main main-merges-lane; do
    if [ "$dir" = lane-merges-main ]; then fresh m3-a m3-oldlane; other=m3-newmain; else fresh m3-b m3-newmain; other=m3-oldlane; fi
    mm "$other"; rc=$?
    if [ "$rc" = 0 ] && grep -q 'RESOLVED test/regression.sh.*r=1' "$TMP/out" && listed zzmaincheck && listed aaalanecheck \
       && [ "$( count )" = "$(( baseCount + 2 ))" ] && ! grep -q '^for _g in [^\\]' "$R/test/regression.sh"; then
        ok "(M3 $dir) old one-line list vs new list settles: exit 0, both gates listed in the new shape, count $(( baseCount + 2 ))"
    else no "(M3 $dir) reshape: rc=$rc count=$( count ): $( grep -E 'regression|merged|STOPPED' "$TMP/out" | tr '\n' ' ' )"; fi
done
# neighbour: the old side also edits a loop line that falls inside the same hunk -> a person decides
fresh m3-oldlane2 m3-old && addGate aaalanecheck && sed -i.bak 's/^_absorb_listed=0; _absorb_ran=0$/_absorb_listed=0; _absorb_ran=0 # lane edit/' "$R/test/regression.sh" && rm -f "$R/test/regression.sh.bak"
if ! grep -q '_absorb_ran=0 # lane edit' "$R/test/regression.sh"; then no "(M3 neighbour) mutation did not take: no '_absorb_listed=0; _absorb_ran=0' line next to the list"
else
    commitAll "old-shape lane adds a gate and edits a loop line"; head0="$( g rev-parse HEAD )"
    mm m3-newmain; rc=$?
    if [ "$rc" = 1 ] && grep -q '^UNTOUCHED test/regression.sh\|^PARTIAL test/regression.sh' "$TMP/out" && [ "$( g rev-parse HEAD )" = "$head0" ]; then
        ok "(M3 neighbour) an old side that also changed a loop line in the hunk stays a conflict (exit 1)"
    else no "(M3 neighbour) rc=$rc (want 1, regression.sh left): $( grep -E 'regression|merged' "$TMP/out" | tr '\n' ' ' )"; fi
fi

# ── (S1) a gate file kept from a delete/modify conflict ───────────────────────────────────────────────
fresh s1-base base && addGate zzretirecheck && printf '#!/usr/bin/env bash\nexit 0\n' > "$R/test/zzretirecheck.sh" && commitAll "a gate to retire"
fresh s1-del s1-base && g rm -q test/zzretirecheck.sh && python3 - "$R/test/regression.sh" <<'PY' && ( cd "$R" && python3 docs/gatecount_build.py >/dev/null ) && commitAll "retire it"
import sys
p = sys.argv[ 1 ]; t = open( p ).read(); open( p, 'w' ).write( t.replace( '    zzretirecheck \\\n', '' ) )
PY
fresh s1-mod s1-base && printf '# edited\n' >> "$R/test/zzretirecheck.sh" && addGate zzretirebcheck && commitAll "edit it, add a neighbour"
head0="$( g rev-parse HEAD )"
mm s1-del; rc=$?
if [ "$rc" != 1 ]; then no "(S1) setup: the delete/modify conflict did not stop the merge (rc=$rc)"
else
    g add test/zzretirecheck.sh; mm --continue; rc=$?
    if [ "$rc" = 1 ] && [ "$( g rev-parse HEAD )" = "$head0" ] && grep -q 'zzretirecheck.sh exists' "$TMP/out"; then
        ok "(S1) a kept, unregistered gate file is refused by --continue (exit 1, registry membership)"
    else no "(S1) kept file: rc=$rc: $( tail -3 "$TMP/out" | tr '\n' ' ' )"; fi
    g rm -q test/zzretirecheck.sh; mm --continue; rc=$?
    if [ "$rc" = 0 ] && listed zzretirebcheck && ! listed zzretirecheck; then
        ok "(S1 twin) accepting the delete commits (exit 0, the neighbour listed, the retired gate gone)"
    else no "(S1 twin) rc=$rc: $( tail -3 "$TMP/out" | tr '\n' ' ' )"; fi
fi

# ── (X) a crashing resolver is an error, not "conflicts left" ─────────────────────────────────────────
fresh x-lane base && addGate aaalanecheck && addGate aabbcheck && printf 'import sys\nsys.exit(139)\n' > "$R/scripts/merge_resolve.py" && commitAll "crashing resolver"
head0="$( g rev-parse HEAD )"
mm m1-main; rc=$?
if [ "$rc" = 2 ] && [ "$( g rev-parse HEAD )" = "$head0" ] && [ -n "$( g diff --name-only --diff-filter=U )" ]; then
    ok "(X) a crashing scripts/merge_resolve.py gives exit 2, commits nothing, and leaves the conflicts in place"
else no "(X) crashing resolver: rc=$rc (want 2): $( tail -2 "$TMP/out" | tr '\n' ' ' )"; fi

# ── (M4) one side only re-ran the generator, the other reworded the marked line (2026-11-02) ─────────
# The counts-snapshot rewording met every open branch that had regenerated a count on the same line. The
# side whose change is only a generator-owned number yields to the prose side; the count is then recomputed.
deckLine(){ grep -n 'stat(s, "[0-9]*", "gate scripts' "$R/present/deck5_ripwire_build.js" | head -1; }
fresh m4-main base && sed -i.bak -E 's/(stat\(s, "[0-9]+", "gate scripts )/\1(reworded) /' "$R/present/deck5_ripwire_build.js" && rm -f "$R/present/deck5_ripwire_build.js.bak"
if ! deckLine | grep -q '(reworded)'; then no "(M4) mutation did not take: no deck stat() gate-count line to reword"
else
    commitAll "main rewords the deck's gate-count line"
    fresh m4-lane base && addGate aaalanecheck && commitAll "lane adds a gate (its generator rewrote the count)"
    mm m4-main; rc=$?
    if [ "$rc" = 0 ] && deckLine | grep -q "\"$(( baseCount + 1 ))\", \"gate scripts (reworded) " && grep -q '^RESOLVED present/deck5_ripwire_build.js c=' "$TMP/out"; then
        ok "(M4) a count-only side against a reworded side settles to the rewording with the count regenerated ($(( baseCount + 1 )))"
    else no "(M4) count-only vs reworded: rc=$rc deck='$( deckLine | cut -c1-90 )': $( grep -E 'deck|merged|STOPPED' "$TMP/out" | tr '\n' ' ' )"; fi
    # neighbour: the rewording side also changed a non-owned number on the line -> a person decides
    fresh m4-main2 base && sed -i.bak -E 's/(stat\(s, "[0-9]+", "gate scripts )/\1(reworded 2) /' "$R/present/deck5_ripwire_build.js" && rm -f "$R/present/deck5_ripwire_build.js.bak" && commitAll "main rewords with a number"
    fresh m4-lane2 base && addGate aaalanecheck && commitAll "lane adds a gate"; head0="$( g rev-parse HEAD )"
    mm m4-main2; rc=$?
    if [ "$rc" = 1 ] && grep -q '^UNTOUCHED present/deck5_ripwire_build.js\|^PARTIAL present/deck5_ripwire_build.js' "$TMP/out" && [ "$( g rev-parse HEAD )" = "$head0" ]; then
        ok "(M4 neighbour) a rewording that also adds a non-owned number stays a conflict (exit 1)"
    else no "(M4 neighbour) rc=$rc (want 1, deck left): $( grep -E 'deck|merged' "$TMP/out" | tr '\n' ' ' )"; fi
fi

# ── (M5) a qualifier change on a non-owned number is a changed figure, not a rewording ─────────────────
for shape in 's/says 200[+]), while the loop/says 200), while the loop/' 's/^  ~210;/  210;/'; do
    fresh m5-main base && sed -i.bak -E "$shape" "$R/docs/EVALS.md" && rm -f "$R/docs/EVALS.md.bak"
    if g diff --quiet -- docs/EVALS.md; then no "(M5) mutation '$shape' did not take on the fixture's docs/EVALS.md"; continue; fi
    commitAll "main rewords a qualifier"
    fresh m5-lane base && addGate aaalanecheck && commitAll "lane adds a gate"; head0="$( g rev-parse HEAD )"
    mm m5-main; rc=$?
    if [ "$rc" = 1 ] && [ "$( g rev-parse HEAD )" = "$head0" ] && grep -q 'docs/EVALS.md' "$TMP/out"; then
        ok "(M5) a qualifier-only edit ($shape) against a count-only side stays a conflict on docs/EVALS.md (exit 1)"
    else no "(M5) qualifier edit '$shape': rc=$rc (want 1, nothing committed): $( grep -E 'EVALS|merged' "$TMP/out" | tr '\n' ' ' )"; fi
done

# ── (R2)/(R3) --regen-after-build: scoped parity re-pin, and marks pending across merges ─────────────
# A stub parity gate stands in for the merged binary: UPDATE_GOLDEN=1 writes $TRUE_MANIFEST, plain mode compares.
writeManifest(){ printf 'alpha 0 %s e\nbeta 0 %s e\ngamma 0 ccc e\n' "$1" "$2" > "$3"; }
printf '#!/bin/sh\necho "stub-bin 0 (built_from=stub)"\n' > "$TMP/stubbin"; chmod +x "$TMP/stubbin"
fresh r2-base base && writeManifest aaa bbb "$R/test/printf_parity.manifest" \
    && printf '#!/usr/bin/env bash\nif [ "${UPDATE_GOLDEN:-0}" = 1 ]; then cp "$TRUE_MANIFEST" test/printf_parity.manifest; exit 0; fi\ncmp -s "$TRUE_MANIFEST" test/printf_parity.manifest\n' > "$R/test/printffmtparitycheck.sh" \
    && commitAll "parity fixture"
fresh r2-main r2-base && writeManifest a-main bbb "$R/test/printf_parity.manifest" && commitAll "main re-pins alpha"
fresh r2-lane r2-base && writeManifest a-lane bbb "$R/test/printf_parity.manifest" && commitAll "lane re-pins alpha"
mm r2-main; rc=$?
if [ "$rc" != 3 ] || ! g log -1 --format=%B | grep -qx '    test/printf_parity.manifest'; then
    no "(R2) setup: the alpha conflict did not mark test/printf_parity.manifest (rc=$rc): $( tail -2 "$TMP/out" | tr '\n' ' ' )"
else
    head0="$( g rev-parse HEAD )"
    export TRUE_MANIFEST="$TMP/true.manifest"
    writeManifest a-true b-true "$TRUE_MANIFEST"          # beta moved too, and both parents pinned beta alike
    mm --regen-after-build "$TMP/stubbin"; rc=$?
    if [ "$rc" = 1 ] && [ "$( g rev-parse HEAD )" = "$head0" ] && grep -qx '    beta' "$TMP/out" && ! grep -qx '    alpha' "$TMP/out"; then
        ok "(R2) a re-pin that moves a label both parents agreed on (beta) is refused: exit 1, nothing committed, beta named"
    else no "(R2) unscoped re-pin: rc=$rc (want 1, beta named, nothing committed): $( tail -3 "$TMP/out" | tr '\n' ' ' )"; fi
    g checkout -q -- .
    writeManifest a-true bbb "$TRUE_MANIFEST"
    mm --regen-after-build "$TMP/stubbin"; rc=$?
    if [ "$rc" = 0 ] && [ "$( g rev-parse HEAD^ )" = "$head0" ] && g log -1 --format=%B | grep -qx 'parity labels re-pinned: alpha'; then
        ok "(R2 twin) only the conflicted label moves: exit 0, committed, the message names 'alpha'"
    else no "(R2 twin) scoped re-pin: rc=$rc (want 0, one commit naming alpha): $( tail -2 "$TMP/out" | tr '\n' ' ' ) | $( g log -1 --format=%B | tail -2 | tr '\n' ' ' )"; fi
    # (R3) marks, then a merge without marks, then regen
    fresh r3-lane r2-base && writeManifest a-lane bbb "$R/test/printf_parity.manifest" && commitAll "lane re-pins alpha"
    mm r2-main; rc1=$?
    g checkout -q -B r3-main2 r2-main && printf 'more main\n' > "$R/main2.txt" && commitAll "main moves on" && g checkout -q r3-lane
    mm r3-main2; rc2=$?
    head1="$( g rev-parse HEAD )"
    mm --regen-after-build "$TMP/stubbin"; rc=$?
    if [ "$rc1" = 3 ] && [ "$rc2" = 0 ] && [ "$rc" = 0 ] && [ "$( g rev-parse HEAD^ )" = "$head1" ] && cmp -s "$TRUE_MANIFEST" "$R/test/printf_parity.manifest"; then
        ok "(R3) marks from an earlier merge survive a later unmarked merge: --regen-after-build re-pins them (exit 0)"
    else no "(R3) pending marks: merge rc=$rc1/$rc2 (want 3/0), regen rc=$rc (want 0, committed): $( tail -2 "$TMP/out" | tr '\n' ' ' )"; fi
    unset TRUE_MANIFEST
fi

# ── (R1) CAPTURE-DICTV-DRIFT: main's newer capture is marked, and --regen-after-build re-records it ──
# Needs a real binary (the merged build): BIN, the gate's argument. A missing binary SKIPs these arms only.
capOf(){ ls "$R"/docs/captures/COMMANDS_showcase_*.md 2>/dev/null | LC_ALL=C sort | tail -1; }
pairOf(){ sed -n '/^## .*--legend-dict/,/^## /p' "$1" | grep -oE 'dictv=[0-9a-f]+ entries=[0-9]+' | head -1; }
if [ ! -x "$BIN" ]; then
    echo "  SKIP  (R1) no binary at $BIN — the --regen-after-build arms need the merged build"
elif ! livePair="$( "$BIN" . --legend-dict 2>/dev/null | grep -oE 'dictv=[0-9a-f]+ entries=[0-9]+' | head -1 )" || [ -z "$livePair" ]; then
    no "(R1) '$BIN . --legend-dict' printed no dictv=/entries= pair (or failed)"
else
    cap="$( capOf )"; fake='dictv=0123456789abcdef entries=1'
    fresh r1-main base && python3 - "$cap" "$( pairOf "$cap" )" "$fake" <<'PY' && commitAll "main's capture records another binary's dictionary"
import sys; p, old, new = sys.argv[ 1: ]; t = open( p ).read(); open( p, 'w' ).write( t.replace( old, new, 1 ) )
PY
    fresh r1-lane base && printf 'lane\n' > "$R/lane.txt" && commitAll "lane work"
    mm r1-main; rc=$?
    if [ "$rc" = 3 ] && g log -1 --format=%B | grep -qx "    ${cap#$R/}"; then
        ok "(R1) a merge that brings main's capture (no conflict) exits 3 and marks ${cap##*/} REGEN AFTER BUILD"
    else no "(R1) capture from main: rc=$rc (want 3, capture named in the merge message): $( tail -3 "$TMP/out" | tr '\n' ' ' )"; fi
    head0="$( g rev-parse HEAD )"
    printf '#!/bin/sh\nexit 1\n' > "$TMP/crashbin"; chmod +x "$TMP/crashbin"
    mm --regen-after-build "$TMP/crashbin"; rc=$?
    if [ "$rc" = 1 ] && [ "$( g rev-parse HEAD )" = "$head0" ] && [ "$( pairOf "$cap" )" = "$fake" ]; then
        ok "(R1 crash) a binary whose --legend-dict fails: exit 1, nothing committed, the capture untouched"
    else no "(R1 crash) failing binary: rc=$rc (want 1, nothing committed): $( tail -2 "$TMP/out" | tr '\n' ' ' )"; fi
    g checkout -q -- . 2>/dev/null
    mm --regen-after-build "$BIN"; rc=$?
    if [ "$rc" = 0 ] && [ "$( g rev-parse HEAD^ )" = "$head0" ] && [ "$( pairOf "$cap" )" = "$livePair" ] && ! g grep -qF "$fake" -- docs; then
        ok "(R1 twin) --regen-after-build re-records $fake -> $livePair from the merged build and commits it (exit 0)"
    else no "(R1 twin) regen: rc=$rc capture='$( pairOf "$cap" )' (want $livePair, one new commit): $( tail -3 "$TMP/out" | tr '\n' ' ' )"; fi
fi

# ── (N2) exit 3: a binary-pinned file took main's side; the REGEN list is in the merge commit message ──
fresh n2-main base && printf 'main pin\n' >> "$R/docs/COMMANDS.md" && commitAll "main re-pins"
fresh n2-lane base && printf 'lane pin\n' >> "$R/docs/COMMANDS.md" && commitAll "lane re-pins"
head0="$( g rev-parse HEAD )"
mm n2-main; rc=$?
if [ "$rc" = 3 ] && [ "$( g rev-parse HEAD^2 2>/dev/null )" = "$( g rev-parse n2-main )" ] && g log -1 --format=%B | grep -q '^    docs/COMMANDS.md$' \
   && cmp -s "$R/docs/COMMANDS.md" <( g show n2-main:docs/COMMANDS.md ); then
    ok "(N2) a binary-pinned conflict takes main's side, commits, exits 3, and names the file in the merge commit message"
else no "(N2) pinned conflict: rc=$rc (want 3, committed, docs/COMMANDS.md in the message): $( tail -3 "$TMP/out" | tr '\n' ' ' )"; fi

[ $fail -eq 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit $fail
