#!/usr/bin/env bash
# churnjoincheck.sh — §H6 / F4 / F6 + §B2.2 gate: the git-history path -> indexed-file JOIN must be EXACT
# against a DERIVED offset and must never guess, and a churn prior with NO evidence must say so.
#
# §H6 (BROKEN, HIGH). gitmine.h resolved a git path to an indexed file with "first match in an unordered
# HashMap bucket wins, no tie-break", and the join predicate accepts a BARE BASENAME as a boundary suffix
# of any indexed path ending in /<basename>. So a root-level file's commit count silently overwrote a
# subdirectory file's, and a same-basename file that is NOT in the tree at all (deleted, excluded) donated
# its whole history to an arbitrary same-name survivor. Measured on the ripwire repo before the fix:
#   ./skills/install.sh  churn="2"   while `git log --since="12 months ago" -- skills/install.sh` = 6
#   (the ROOT ./install.sh's 2 commits, proven causal: bumping the root file to 5 moved the SKILLS row to 5)
# and in a sandbox: BOTH a/src/x.cpp and b/src/x.cpp reported churn="6" — the count of a DELETED src/x.cpp —
# while each has exactly 1 commit of its own, and --owners attributed the deleted file's author to a/.
#
# §B2.2 (MISLEADING, MED). --rank-by=churn on a repo whose history lies entirely OUTSIDE the window returned
# the STRUCTURAL ranking (uniform prior) while still stamping rank_by="churn" window="18mo" at="<sha>" with
# empty stderr — ranks byte-identical to pagerank, and the stamp --help sells as the thing that stops churn
# "passing for the structural one" was the only tell and it could not tell.
#
# F4 (MED, the residual the wave-1 verifier found). The first fix kept a fuzzy fallback and refused only on an
# exact byte TIE. A tie is not the failure condition — an ABSENT better candidate is. With exactly ONE surviving
# same-basename file (because the file the git path really names was deleted / excluded / never indexed) there
# is no tie, so the dead path's commits were written onto the survivor at full confidence with empty stderr:
#   root zeta.cpp = 5 edits + a delete, a/zeta.cpp = 1 commit dated 2019
#     -> --hotspots  ranked="1"  ./a/zeta.cpp churn="6"   with zero in-window commits of its own
# F6 (MED, same verdict). "Readers moved onto readByteSafeLine" was true of 1 of 5 git-pipe readers; four
# `char line[4096]` + fgets readers could still split a >4095-byte path into a tail that binds to a WRONG file.
#
# The contract this gate pins:
#   1. The git-root -> index-root OFFSET is DERIVED once per root (rev-parse --show-toplevel vs the probe's own
#      realpath), and a git path binds iff it EQUALS a file's derived spelling, byte for byte after one shared
#      normalisation (leading "./" stripped, the workspace "/./" seam collapsed; never case-folded).
#   2. There is no fallback. A path that does not spell an indexed file binds to NOTHING — no basename match, no
#      least-unexplained-prefix runner-up — and that is the ordinary, SILENT case (§2, §5, §7, §8).
#   3. What IS disclosed once per process: a root whose offset cannot be derived, an indexed file that does not
#      wear its root's spelling, and two roots deriving one repo-relative path. Each on stderr (which survives
#      -DNDEBUG) plus a DEGRADED_PATH_ALERT.
#   4. The same join, and the same byte-safe reader, apply to EVERY consumer — churn, co-change, ownership,
#      the changed mask, short-horizon churn (§9 walks the readers one by one).
#   5. A churn prior with zero in-window evidence discloses that in the window stamp AND on stderr, so
#      "churn-ranked" and "churn found nothing" are distinguishable.
#
# Usage:  test/churnjoincheck.sh              # build/ripwire
#         test/churnjoincheck.sh asan/ripwire # positional seam
#         RIPWIRE_BIN=asan/ripwire test/churnjoincheck.sh   # env seam
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"       # BOTH seams — positional and env
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
command -v git >/dev/null 2>&1 || { echo "git required"; exit 2; }
echo "churnjoincheck: BIN=$BIN  ROOT=$ROOT"

TMP="$( mktemp -d )"; R1="$( mktemp -d )"; R2="$( mktemp -d )"; R3="$( mktemp -d )"
TMPDIRS=""                                    # the §5+ fixtures append themselves here as they are made
trap 'rm -rf "$TMP" "$R1" "$R2" "$R3" $TMPDIRS' EXIT

# a C++ file with one function of non-zero cognitive complexity (so --hotspots ranks it at all)
mkfn(){ printf 'int %s( int x )\n{\n    if( x > 1 ) return x + 1;\n    return x - 1;\n}\n' "$1"; }
D(){ export GIT_AUTHOR_DATE="$1" GIT_COMMITTER_DATE="$1"; }
# RE-PINNED 2026-08-19 (R-E CORRECTION). Every path selector in this file was a LEADING-SLASH substring
# ("/deep/util.cpp\"") — correct while p= carried the absolute crawl path, and silently WRONG since p= went
# root-relative (2026-08-17): a file AT the crawl root now spells p="util.cpp" with no slash at all, so the
# selector matched nothing and several arms went green-while-inert (the live-repo audit below re-derived
# "all 0 ranked rows", passing on an empty set). The JOIN itself was never broken — root util.cpp still
# reports churn=2/rootdev and deep/util.cpp churn=5/deepdev, verified before this re-pin — so the fix is the
# selector, and it is written to be spelling-independent rather than re-pinned to the new spelling: psel
# keeps the "boundary suffix" semantics the callers were written for (equal to, or ending in "/" + it) and
# now accepts the root-relative form too. Callers still pass the leading-slash spelling; psel strips it.
psel(){ awk -v s="${1#/}" '{ if( match( $0, /p="[^"]*"/ ) ) { v = substr( $0, RSTART + 3, RLENGTH - 4 );
        if( v == s || ( length(v) > length(s) && substr( v, length(v) - length(s) ) == "/" s ) ) print } }'; }
# psel's complement: pass every line through EXCEPT the ones psel would select.
pdrop(){ awk -v s="${1#/}" '{ if( match( $0, /p="[^"]*"/ ) ) { v = substr( $0, RSTART + 3, RLENGTH - 4 );
        if( v == s || ( length(v) > length(s) && substr( v, length(v) - length(s) ) == "/" s ) ) next } print }'; }
prow(){ tr '>' '\n' < "$1" | psel "$2"; }
# churn_of REPO PATHSUFFIX — the churn= attribute of the <f> row whose p= ends with PATHSUFFIX ("" if absent)
churn_of(){ prow "$1" "$2" | grep -oE 'churn="[0-9]+"' | head -1 | tr -cd '0-9'; }

# ── 1. SAME BASENAME AT TWO DEPTHS, divergent commit counts (the §H6 headline shape) ────────────────
# util.cpp at the root (2 commits) and deep/util.cpp (5 commits). The root file's commit is the NEWEST, so
# its path is first in the churn bucket's insertion order — which is exactly what let it win the bucket.
# Each file is CREATED by its own author, so "how many authors does this file have" is 1 for both unless a
# join donated one file's history to the other.
mkdir -p "$R1/deep"
mkfn rootFn > "$R1/util.cpp"
git -C "$R1" init -q
git -C "$R1" config user.email rootdev@x.com;  git -C "$R1" config user.name Rootdev
D 2026-06-01T12:00:00; git -C "$R1" add -A >/dev/null; git -C "$R1" commit -qm c1
mkfn deepFn > "$R1/deep/util.cpp"
git -C "$R1" config user.email deepdev@x.com;  git -C "$R1" config user.name Deepdev
D 2026-06-02T09:00:00; git -C "$R1" add -A >/dev/null; git -C "$R1" commit -qm deep1
for i in 2 3 4 5; do
    printf '// touch %s\n' "$i" >> "$R1/deep/util.cpp"
    D "2026-06-0${i}T12:00:00"; git -C "$R1" add -A >/dev/null; git -C "$R1" commit -qm "deep$i"
done
git -C "$R1" config user.email rootdev@x.com;  git -C "$R1" config user.name Rootdev
printf '// touch root\n' >> "$R1/util.cpp"
D 2026-06-10T12:00:00; git -C "$R1" add -A >/dev/null; git -C "$R1" commit -qm root2
unset GIT_AUTHOR_DATE GIT_COMMITTER_DATE

"$BIN" "$R1" --hotspots --limit=50 > "$TMP/h1.out" 2>"$TMP/h1.err"
C_DEEP="$( churn_of "$TMP/h1.out" /deep/util.cpp )"     # the deep row matches on its own longer suffix;
# "…/deep/util.cpp" also ends with /util.cpp, so the ROOT row is the one that ends with /util.cpp and NOT with /deep/util.cpp
C_ROOT="$( prow "$TMP/h1.out" /util.cpp | pdrop /deep/util.cpp | grep -oE 'churn="[0-9]+"' | tr -cd '0-9' )"
[ "$C_ROOT" = 2 ] && ok "--hotspots: root util.cpp keeps its OWN churn (2)" \
    || no "--hotspots: root util.cpp churn=\"$C_ROOT\", want 2"
[ "$C_DEEP" = 5 ] && ok "--hotspots: deep/util.cpp keeps its OWN churn (5) — not the root file's 2 (§H6)" \
    || no "--hotspots: deep/util.cpp churn=\"$C_DEEP\", want 5 (the root file's count won the bucket — §H6)"

# the same join backs --for's churn= quality lens (gitmine.h resolveCommitStream, a different call site)
"$BIN" "$R1" --for="deepFn util" > "$TMP/f1.out" 2>/dev/null
FCH="$( tr '>' '\n' < "$TMP/f1.out" | grep -F 'n="deepFn"' | grep -oE 'churn="[0-9]+"' | tr -cd '0-9' )"
[ "$FCH" = 5 ] && ok "--for churn=: deepFn's file keeps its own churn (5)" \
    || no "--for churn= for deepFn is \"$FCH\", want 5 (§H6 reaches the quality lens too)"

# ownership uses the OTHER direction of the same join (one git path -> many indexed files)
"$BIN" "$R1" --owners --detail=1 --limit=50 > "$TMP/o1.out" 2>/dev/null
OROOT="$( prow "$TMP/o1.out" /util.cpp | pdrop /deep/util.cpp | grep -oE 'top="[^"]*"' | head -1 )"
ODEEP="$( prow "$TMP/o1.out" /deep/util.cpp | grep -oE 'top="[^"]*"' | head -1 )"
[ "$OROOT" = 'top="rootdev@x.com"' ] && ok "--owners: root util.cpp is owned by rootdev (it has an ownership row at all)" \
    || no "--owners: root util.cpp top author is '$OROOT', want rootdev@x.com (its history was donated to the deep file — §H6)"
[ "$ODEEP" = 'top="deepdev@x.com"' ] && ok "--owners: deep/util.cpp is owned by deepdev" \
    || no "--owners: deep/util.cpp top author is '$ODEEP', want deepdev@x.com"
prow "$TMP/o1.out" /deep/util.cpp | grep -q 'authors="1"' \
    && ok "--owners: deep/util.cpp has ONE author (the root file's author is not folded in)" \
    || no "--owners: deep/util.cpp author count is not 1: $( prow "$TMP/o1.out" /deep/util.cpp | head -c 200 )"
prow "$TMP/o1.out" /util.cpp | pdrop /deep/util.cpp | grep -q 'authors="1"' \
    && ok "--owners: root util.cpp has ONE author (its own)" \
    || no "--owners: root util.cpp author count is not 1: $( prow "$TMP/o1.out" /util.cpp | pdrop /deep/util.cpp | head -c 200 )"

# determinism: the tie-break must not depend on hash/bucket order
"$BIN" "$R1" --hotspots --limit=50 > "$TMP/h1b.out" 2>/dev/null
cmp -s "$TMP/h1.out" "$TMP/h1b.out" && ok "--hotspots is byte-identical across runs (det-gate)" \
    || no "--hotspots differs between two runs on the same tree"

# the same join backs the --map-diff CHANGED MASK, where the failure mode is an over-mark rather than a wrong
# number: an UNCOMMITTED edit to the ROOT util.cpp must mark ONE file, not every */util.cpp in the tree.
printf '// uncommitted edit to the root file only\n' >> "$R1/util.cpp"
CHANGED_GIT="$( git -C "$R1" diff --name-only HEAD | grep -c . )"
CHANGED_MAP="$( "$BIN" "$R1" --map-diff --top-k=5 2>/dev/null | tr '<' '\n' | grep -oE 'changed=[0-9]+' | head -1 | tr -cd '0-9' )"
[ "$CHANGED_MAP" = "$CHANGED_GIT" ] \
    && ok "--map-diff changed=\"$CHANGED_MAP\" equals git's own changed-file count ($CHANGED_GIT)" \
    || no "--map-diff changed=\"$CHANGED_MAP\" but git changed $CHANGED_GIT file(s) — a same-basename sibling was marked (§H6, mask direction)"
git -C "$R1" checkout -- util.cpp 2>/dev/null

# ── 2. A GENUINELY AMBIGUOUS TIE: disclosed-unresolved, never an arbitrary pick ─────────────────────
# a/src/x.cpp and b/src/x.cpp are both in the tree (1 commit each). src/x.cpp is NOT (deleted in the last
# commit) but its 6 commits, by a DIFFERENT author, are still in the history — and "src/x.cpp" is an equally
# good boundary-suffix of both survivors. Nothing may claim them.
mkdir -p "$R2/a/src" "$R2/b/src" "$R2/src"
mkfn aFn > "$R2/a/src/x.cpp"
mkfn bFn > "$R2/b/src/x.cpp"
mkfn gFn > "$R2/src/x.cpp"
mkfn oFn > "$R2/other.cpp"
git -C "$R2" init -q
git -C "$R2" config user.email real@x.com;  git -C "$R2" config user.name Real
D 2026-06-01T12:00:00; git -C "$R2" add -A >/dev/null; git -C "$R2" commit -qm c1
git -C "$R2" config user.email ghost@x.com; git -C "$R2" config user.name Ghost
for i in 2 3 4 5; do
    printf '// ghost %s\n' "$i" >> "$R2/src/x.cpp"
    printf '// with %s\n'  "$i" >> "$R2/other.cpp"
    D "2026-06-0${i}T12:00:00"; git -C "$R2" add -A >/dev/null; git -C "$R2" commit -qm "ghost$i"
done
D 2026-06-09T12:00:00; git -C "$R2" rm -q "src/x.cpp"; git -C "$R2" commit -qm drop
unset GIT_AUTHOR_DATE GIT_COMMITTER_DATE

"$BIN" "$R2" --hotspots --limit=50 > "$TMP/h2.out" 2>"$TMP/h2.err"
CA="$( churn_of "$TMP/h2.out" /a/src/x.cpp )"
CB="$( churn_of "$TMP/h2.out" /b/src/x.cpp )"
[ "$CA" = 1 ] && [ "$CB" = 1 ] \
    && ok "--hotspots: a/ and b/ src/x.cpp each keep their OWN churn (1) — the deleted src/x.cpp's 6 is nobody's" \
    || no "--hotspots: a/=\"$CA\" b/=\"$CB\", want 1 and 1 (a DELETED file's history was donated — §H6)"

"$BIN" "$R2" --owners --detail=1 --limit=50 > "$TMP/o2.out" 2>"$TMP/o2.err"
# ghost@x.com legitimately owns other.cpp; what must never happen is ghost appearing on a SURVIVOR of the
# ambiguous join (the deleted src/x.cpp's history has no honest home).
{ prow "$TMP/o2.out" /a/src/x.cpp; prow "$TMP/o2.out" /b/src/x.cpp; } | grep -q 'ghost@x.com' \
    && no "--owners: the deleted file's author (ghost@x.com) was attributed to a surviving same-name file: $( { prow "$TMP/o2.out" /a/src/x.cpp; prow "$TMP/o2.out" /b/src/x.cpp; } | head -c 300 )" \
    || ok "--owners: the deleted file's author is attributed to NEITHER survivor (ambiguous join refused)"
prow "$TMP/o2.out" /a/src/x.cpp | grep -q 'authors="1"' \
    && ok "--owners: a/src/x.cpp has exactly ONE author (its own)" \
    || no "--owners: a/src/x.cpp author count is not 1: $( prow "$TMP/o2.out" /a/src/x.cpp | head -c 200 )"

"$BIN" "$R2" --cochange=other.cpp > "$TMP/cc2.out" 2>"$TMP/cc2.err"
grep -q 'partners="0"' "$TMP/cc2.out" \
    && ok "--cochange: no fabricated partner from the deleted file's commits" \
    || no "--cochange invented a partner for other.cpp: $( tr '>' '\n' < "$TMP/cc2.out" | grep -E '<cochange|<f p' | head -c 300 )"

# F4 — WHAT MUST NOT BE SAID HERE, and why this used to be four inverted arms.
# Wave 1's join refused only on an exact TIE in `unmatchedPrefixBytes` and printed a per-path "AMBIGUOUS" line
# when it did; these four arms asserted that line. The exact join has no ties to break, so the state they
# assert no longer exists: `src/x.cpp` simply is not `a/src/x.cpp` and is not `b/src/x.cpp`, so it names no
# indexed file — the SAME ordinary state as the thousands of deleted / excluded / out-of-root paths in any real
# history. Disclosing it per path would print thousands of lines and bury the states that ARE worth a line
# (§7/§8 below). So the assertion inverts: on this corpus the join must be SILENT, and the guarantees the old
# arms were really protecting (each survivor keeps its own count, the deleted file's author lands on neither,
# no partner is invented) are the arms above — all of which still hold and none of which needed the tie line.
for pair in "h2:--hotspots" "o2:--owners" "cc2:--cochange"; do
    f="${pair%%:*}"; label="${pair#*:}"
    [ -s "$TMP/$f.err" ] \
        && no "$label spoke about a git path that names no indexed file — that is the ordinary case, not a degrade (stderr: '$( head -c 220 "$TMP/$f.err" )')" \
        || ok "$label stays SILENT about the deleted src/x.cpp: unresolvable is ordinary, and its count went nowhere"
done
# NO false alarm where there is nothing to refuse: sandbox 1 has two same-basename files at different depths
# and every path there binds EXACTLY, so nothing may be reported as ambiguous.
[ -s "$TMP/h1.err" ] \
    && no "--hotspots reported an ambiguity on a tree where every path binds exactly: $( head -c 200 "$TMP/h1.err" )" \
    || ok "--hotspots stays quiet when every git path binds exactly (no false alarm)"

# ── 3. §B2.2 — a churn prior with NO in-window evidence must say so ─────────────────────────────────
# Every commit here is dated 2019: `--rank-by=churn`'s 18-month window matches nothing, so the prior is
# uniform and the ranking IS the structural one.
mkdir -p "$R3/src"
printf 'int helperB( int x ) { return x + 1; }\nint a( int x ) { if( x ) return 1; return helperB( x ); }\n' > "$R3/src/a.cpp"
printf 'int c( int x ) { return a( x ) + helperB( x ); }\n' > "$R3/src/c.cpp"
git -C "$R3" init -q
git -C "$R3" config user.email old@x.com; git -C "$R3" config user.name Old
D 2019-01-01T12:00:00; git -C "$R3" add -A >/dev/null; git -C "$R3" commit -qm c1
printf '// more\n' >> "$R3/src/a.cpp"
D 2019-02-01T12:00:00; git -C "$R3" add -A >/dev/null; git -C "$R3" commit -qm c2
unset GIT_AUTHOR_DATE GIT_COMMITTER_DATE

"$BIN" "$R3" --rank-by=churn --top-k=5 > "$TMP/z.xml" 2>"$TMP/z.err"; zrc=$?
"$BIN" "$R3"                 --top-k=5 > "$TMP/p.xml" 2>/dev/null
[ "$zrc" -eq 0 ] && ok "zero-evidence --rank-by=churn still exits 0 (a structural map is a valid answer)" \
    || no "zero-evidence --rank-by=churn exit $zrc, want 0"
# the ranks ARE the structural ones — that is the fact that must be disclosed, not hidden
KZ="$( grep -o 'k="[0-9.]*"' "$TMP/z.xml" | tr '\n' ' ' )"
KP="$( grep -o 'k="[0-9.]*"' "$TMP/p.xml" | tr '\n' ' ' )"
[ "$KZ" = "$KP" ] && ok "zero-evidence churn ranks equal the pagerank ranks (the premise of §B2.2 holds)" \
    || no "zero-evidence churn ranks differ from pagerank — the sandbox no longer reproduces §B2.2"
grep -oE 'window="[^"]*"' "$TMP/z.xml" | head -1 | grep -qi 'no churn evidence' \
    && ok 'the window stamp says the churn signal was EMPTY' \
    || no "window= still passes for a real churn window: $( grep -oE 'window="[^"]*"' "$TMP/z.xml" | head -1 )"
grep -qi 'churn' "$TMP/z.err" \
    && ok "zero-evidence churn prints one stderr note (the --map-diff 'using uniform ranking' precedent)" \
    || no "zero-evidence churn is silent on stderr"
# the JSON dialect must carry the same stamp (churnjsonstampcheck's XML/JSON agreement, one value over)
"$BIN" "$R3" --rank-by=churn --top-k=5 --json > "$TMP/z.json" 2>/dev/null
grep -qi '"window":"[^"]*no churn evidence' "$TMP/z.json" \
    && ok "the JSON stamp discloses the empty churn signal identically" \
    || no "JSON window= hides what the XML discloses: $( grep -oE '"window":"[^"]*"' "$TMP/z.json" | head -1 )"

# CONTROL: a repo WITH in-window churn keeps the plain window label and stays quiet (no over-firing)
if git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1; then
    "$BIN" "$ROOT" --rank-by=churn --top-k=3 > "$TMP/live.xml" 2>"$TMP/live.err"
    grep -q 'window="18mo"' "$TMP/live.xml" \
        && ok 'CONTROL: a repo with real churn still stamps exactly window="18mo"' \
        || no "CONTROL: the live repo's window label changed: $( grep -oE 'window="[^"]*"' "$TMP/live.xml" | head -1 )"
    grep -qi 'churn' "$TMP/live.err" \
        && no "CONTROL: the empty-churn note fired on a repo that HAS churn: $( head -c 200 "$TMP/live.err" )" \
        || ok "CONTROL: no empty-churn note on a repo that has churn"
fi

# ── 4. THE LIVE REPO: every same-basename file re-derives its OWN git count ─────────────────────────
# Derived from git in-gate (never pinned): churn= must equal the number of times THAT path appears in the
# very stream the miner reads — `git log -c --since=12-months --name-only --format=`. (Not `git log -- <path>`,
# which applies history simplification and counts merges: 305 vs 260 for src/main.cpp. Same window, same
# walk, same tally is the only comparison that is a fact about the join rather than about git's log options.)
# Checked on the basenames that occur more than once in the tree — the population §H6 corrupts.
#
# THE `-c` IN EVERY ORACLE HERE (2026-07-31, the L-OWN lane —
# NOT a re-pin to make a red gate green). The miners now spell `git log -c` (gitmine.h::kMergeDiffArgs) so that
# a merge commit names the files IT introduced; without the same `-c` here the oracle asks a DIFFERENT question
# than the code and 19 of 209 live rows "disagreed" while both sides were right about their own command — trap
# #12, the very thing the paragraph above warns about, arriving from the other direction. Nothing in this gate
# is pinned: every `want` is still derived from git in-gate, and on a merge-free fixture `-c` is a no-op, so the
# only numbers that moved are the LIVE repo's — legitimately, because the tool now mines merge-introduced
# content it used to drop. The merge behaviour itself is gated by test/mergechurncheck.sh, not here.
if git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1; then
    DUPES="$( git -C "$ROOT" ls-files | awk -F/ '{ print $NF }' | sort | uniq -d | grep -c . )"
    # auditWindow LABEL GIT_WINDOW [EXTRA_FLAGS...] — every ranked row's churn= must equal the number of
    # in-window commits naming THAT path. A row whose own path has ZERO in-window commits must not be ranked at
    # all (the §H6 phantom row: ranked= counted a file that only borrowed a bare-basename sibling's commit).
    auditWindow(){
        local label="$1" gitWindow="$2"; shift 2
        "$BIN" "$ROOT" --hotspots --limit=1000 "$@" > "$TMP/live.hot" 2>/dev/null
        git -C "$ROOT" log -c --since="$gitWindow" --name-only --format= | sort | uniq -c | awk '{ print $1" "$2 }' > "$TMP/live.counts"
        # RE-PINNED 2026-08-19 (R-E CORRECTION): p= is ROOT-RELATIVE now, so the old "$ROOT/"-anchored
        # pattern selected nothing and this audit reported "all 0 ranked rows" — green, and inert.
        tr '>' '\n' < "$TMP/live.hot" | grep -oE 'p="[^"]+" churn="[0-9]+"' \
            | sed 's|p="||; s|" churn="| |; s|"$||' > "$TMP/live.rows"
        local rows=0 bad=0
        while read -r rel got; do
            rows=$(( rows + 1 ))
            local want; want="$( awk -v p="$rel" '$2 == p { print $1 }' "$TMP/live.counts" )"
            [ -n "$want" ] || want=0
            [ "$got" != "$want" ] && { bad=$(( bad + 1 )); no "live ($label): $rel churn=\"$got\" but its own path appears in $want in-window commit(s)"; }
        done < "$TMP/live.rows"
        [ "$bad" = 0 ] && ok "live repo ($label): all $rows ranked rows re-derive their own git count ($DUPES duplicated basenames in the tree)" \
            || no "live repo ($label): $bad of $rows rows disagree with git"
    }
    auditWindow "default 12mo" "12 months ago"
    auditWindow "--since=2 weeks ago" "2 weeks ago" --since="2 weeks ago"
fi


# ── 5. F4 — THE RIGHT ANSWER DOES NOT EXIST, SO THERE IS NO TIE TO REFUSE ───────────────────────────
# The residual §H6 left standing. `zeta.cpp` at the root is edited 5 times and then DELETED; exactly ONE
# same-basename file survives (`a/zeta.cpp`, one commit dated 2019, i.e. zero inside the window). With one
# candidate there is no tie, so wave 1's tie-only refusal bound the dead path's 6 commits onto the survivor at
# full confidence with empty stderr — bit-for-bit the `./skills/install.sh` phantom §H6 exists to kill:
#   base:  ranked="1"  ./a/zeta.cpp churn="6"   (its own in-window count is 0)
#   fixed: ranked="0"  a/zeta.cpp unranked
# Run for FOUR reasons the better candidate can be absent from the index — deleted, --exclude'd, an extension
# ripwire does not parse, and pruned by the crawl's own denylist — because the join must not care WHY.
zetaFixture(){   # zetaFixture DIR SURVIVOR_SUBDIR EXTRA_ROOT_FILE   (EXTRA_ROOT_FILE "" ⇒ the root file is deleted)
    local d="$1" sub="$2" extra="$3"
    mkdir -p "$d/$sub"
    mkfn zetaSurvivor > "$d/$sub/zeta.cpp"
    git -C "$d" init -q
    git -C "$d" config user.email surv@x.com;  git -C "$d" config user.name Surv
    D 2019-01-01T12:00:00; git -C "$d" add -A >/dev/null; git -C "$d" commit -qm "old survivor"
    git -C "$d" config user.email ghost@x.com; git -C "$d" config user.name Ghost
    local target="$d/zeta.cpp"; [ -n "$extra" ] && target="$d/$extra"
    mkfn zetaGhost > "$target"
    D 2026-06-01T12:00:00; git -C "$d" add -A >/dev/null; git -C "$d" commit -qm rz1
    local i; for i in 2 3 4 5; do
        printf '// ghost touch %s\n' "$i" >> "$target"
        D "2026-06-0${i}T12:00:00"; git -C "$d" add -A >/dev/null; git -C "$d" commit -qm "rz$i"
    done
    if [ -z "$extra" ]; then
        D 2026-06-09T12:00:00; git -C "$d" rm -q "zeta.cpp"; git -C "$d" commit -qm "delete root zeta.cpp"
    fi
    unset GIT_AUTHOR_DATE GIT_COMMITTER_DATE
}

# 5a. DELETED — the file the git path names is gone from the tree
R4="$( mktemp -d )"; TMPDIRS="$TMPDIRS $R4"
zetaFixture "$R4" a ""
"$BIN" "$R4" --hotspots --limit=50 > "$TMP/h4.out" 2>"$TMP/h4.err"
RANKED4="$( grep -oE 'ranked="[0-9]+"' "$TMP/h4.out" | head -1 | tr -cd '0-9' )"
C4="$( churn_of "$TMP/h4.out" /a/zeta.cpp )"
# git's own answer, from the SAME command ripwire runs (never `git log -- <path>`: history simplification
# manufactures mismatches — 19 of them on a first verifier pass; that is trap #12 in this round's ledger)
WANT4="$( git -C "$R4" log -c --since="12 months ago" --name-only --format= | grep -cx 'a/zeta.cpp' )"
[ "${RANKED4:-x}" = 0 ] && ok "F4/deleted: ranked=\"0\" — a deleted file's 6 commits are NOBODY's, not the one survivor's" \
    || no "F4/deleted: ranked=\"$RANKED4\", want 0 (a phantom row is counted — the survivor took the deleted file's churn)"
[ -z "$C4" ] && ok "F4/deleted: a/zeta.cpp carries NO churn= (its own in-window count is $WANT4)" \
    || no "F4/deleted: a/zeta.cpp churn=\"$C4\" but its own path appears in $WANT4 in-window commit(s)"
[ -s "$TMP/h4.err" ] && no "F4/deleted: stderr should be silent (an absent file is ordinary): $( head -c 200 "$TMP/h4.err" )" \
    || ok "F4/deleted: silent — an unresolvable path is the ordinary case, not a degrade"
# the same fabrication through the OTHER two entry points the finding reproduced it on
FCH4="$( "$BIN" "$R4" --for="zetaSurvivor" 2>/dev/null | tr '<' '\n' | grep -F 'n="zetaSurvivor"' | grep -oE 'churn="[0-9]+"' | tr -cd '0-9' )"
[ "${FCH4:-0}" = 0 ] && ok "F4/deleted: --for churn= for the survivor is 0, not the dead path's 6" \
    || no "F4/deleted: --for reports churn=\"$FCH4\" for a file with $WANT4 in-window commits"
"$BIN" "$R4" --owners --detail=1 --limit=50 2>/dev/null | tr '>' '\n' | psel /a/zeta.cpp | grep -q 'ghost@x.com' \
    && no "F4/deleted: the deleted file's author was attributed to the survivor" \
    || ok "F4/deleted: --owners does not give the survivor the deleted file's author"

# 5b. EXCLUDED — the better candidate is in git AND on disk, and only --exclude keeps it out of the INDEX.
# The shape has to be a SUFFIX rather than a bare basename, because --exclude=SUBSTR would otherwise match both
# files: `src/zeta.cpp` (the ghost, 5 commits) is a directory-aligned suffix of `keep/src/zeta.cpp` (the
# survivor, 1 old commit), and `<root>/src/` is a substring of only the ghost's path. Base binds the ghost's 5
# onto the survivor with no tie to refuse; the exact join sees two different paths and binds neither to the other.
R5="$( mktemp -d )"; TMPDIRS="$TMPDIRS $R5"
mkdir -p "$R5/keep/src" "$R5/src"
mkfn zetaSurvivor5 > "$R5/keep/src/zeta.cpp"
git -C "$R5" init -q; git -C "$R5" config user.email surv@x.com; git -C "$R5" config user.name Surv
D 2019-01-01T12:00:00; git -C "$R5" add -A >/dev/null; git -C "$R5" commit -qm "old survivor"
git -C "$R5" config user.email ghost@x.com; git -C "$R5" config user.name Ghost
for i in 1 2 3 4 5; do
    mkfn zetaGhost5 > "$R5/src/zeta.cpp"; printf '// ghost %s\n' "$i" >> "$R5/src/zeta.cpp"
    D "2026-06-0${i}T12:00:00"; git -C "$R5" add -A >/dev/null; git -C "$R5" commit -qm "g$i"
done
unset GIT_AUTHOR_DATE GIT_COMMITTER_DATE
"$BIN" "$R5" --exclude="$R5/src/" --hotspots --limit=50 > "$TMP/h5.out" 2>/dev/null
# the two premises come from the plain MAP, not from --hotspots: --hotspots lists only RANKED rows, so on a
# correct binary the survivor is absent there precisely because its churn is 0 — which would read as "excluded".
"$BIN" "$R5" --exclude="$R5/src/" --top-k=50 > "$TMP/m5.out" 2>/dev/null
grep -qF '"'"$R5"'/src/zeta.cpp"' "$TMP/m5.out" \
    && no "F4/excluded: the sandbox is wrong — the excluded ghost is still indexed" \
    || ok "F4/excluded: src/zeta.cpp is out of the index (the premise holds)"
tr '>' '\n' < "$TMP/m5.out" | psel /keep/src/zeta.cpp | grep -q . \
    && ok "F4/excluded: the survivor keep/src/zeta.cpp IS indexed (so the next arm is not vacuous)" \
    || no "F4/excluded: --exclude took the survivor too — this arm proves nothing"
C5="$( churn_of "$TMP/h5.out" /keep/src/zeta.cpp )"
W5="$( git -C "$R5" -c core.quotepath=false log -c --since="12 months ago" --name-only --format= | grep -cx 'keep/src/zeta.cpp' )"
[ "${C5:-0}" = "$W5" ] && ok "F4/excluded: keep/src/zeta.cpp keeps its own $W5 in-window commit(s) — the EXCLUDED src/zeta.cpp's 5 are nobody's" \
    || no "F4/excluded: keep/src/zeta.cpp churn=\"$C5\" but its own path appears in $W5 in-window commit(s) — an --exclude'd file's history was donated to it"

# 5c. OUTSIDE THE CRAWL ROOT — the better candidate is tracked, present on disk and in the same repo, and is
# absent from the index only because the crawl root is a SUBDIRECTORY. `src/zeta.cpp` (5 commits, repo-root
# relative) is a directory-aligned suffix of the survivor `keep/src/zeta.cpp`, and with the crawl rooted at
# `keep/` the survivor's OWN path never appears in the tally (no in-window commits of its own), so once again
# there is one candidate and no tie. This arm also exercises the derived offset in the same breath: with the root
# at `keep/`, git's paths carry a `keep/` segment the indexed paths do not.
R6b="$( mktemp -d )"; TMPDIRS="$TMPDIRS $R6b"
mkdir -p "$R6b/keep/src" "$R6b/src"
mkfn zetaSurvivor6 > "$R6b/keep/src/zeta.cpp"
git -C "$R6b" init -q; git -C "$R6b" config user.email surv@x.com; git -C "$R6b" config user.name Surv
D 2019-01-01T12:00:00; git -C "$R6b" add -A >/dev/null; git -C "$R6b" commit -qm "old survivor"
git -C "$R6b" config user.email ghost@x.com; git -C "$R6b" config user.name Ghost
for i in 1 2 3 4 5; do
    mkfn zetaGhost6 > "$R6b/src/zeta.cpp"; printf '// ghost %s\n' "$i" >> "$R6b/src/zeta.cpp"
    D "2026-06-0${i}T12:00:00"; git -C "$R6b" add -A >/dev/null; git -C "$R6b" commit -qm "g$i"
done
unset GIT_AUTHOR_DATE GIT_COMMITTER_DATE
"$BIN" "$R6b/keep" --hotspots --limit=50 > "$TMP/h6b.out" 2>/dev/null
C6B="$( churn_of "$TMP/h6b.out" /src/zeta.cpp )"
W6B="$( git -C "$R6b" -c core.quotepath=false log -c --since="12 months ago" --name-only --format= | grep -cx 'keep/src/zeta.cpp' )"
[ "${C6B:-0}" = "$W6B" ] && ok "F4/out-of-root: keep/src/zeta.cpp keeps its own $W6B in-window commit(s) — the out-of-root src/zeta.cpp's 5 are nobody's" \
    || no "F4/out-of-root: the crawled keep/src/zeta.cpp churn=\"$C6B\" but its own path appears in $W6B in-window commit(s) — a path outside the crawl root donated its history"

# 5d. CONTROL, green on both flavours BY CONSTRUCTION, and recorded as such so nobody reads it as red-first:
# an unparsed extension and a denylisted directory CANNOT produce this shape. The old join bound only on a
# matching BASENAME, so a different extension never competed at all; and `build/` is pruned by the crawl's own
# denylist wherever it appears, so any survivor spelled `*/build/zeta.cpp` would be pruned with the ghost. The
# arm still earns its place: it pins that neither reason starts guessing later.
R6="$( mktemp -d )"; TMPDIRS="$TMPDIRS $R6"
mkdir -p "$R6/a"
mkfn zetaSurv6 > "$R6/a/zeta.cpp"
git -C "$R6" init -q; git -C "$R6" config user.email s@x.com; git -C "$R6" config user.name S
D 2019-01-01T12:00:00; git -C "$R6" add -A >/dev/null; git -C "$R6" commit -qm old
mkdir -p "$R6/build"
for i in 1 2 3 4 5; do
    printf 'zeta payload %s\n' "$i" > "$R6/zeta.unparsed"   # an extension ripwire has no grammar for
    mkfn zetaBuild"$i"          > "$R6/build/zeta.cpp"       # build/ is on the crawl's own denylist
    D "2026-06-0${i}T12:00:00"; git -C "$R6" add -A >/dev/null; git -C "$R6" commit -qm "u$i"
done
unset GIT_AUTHOR_DATE GIT_COMMITTER_DATE
"$BIN" "$R6" --hotspots --limit=50 > "$TMP/h6.out" 2>/dev/null
C6="$( churn_of "$TMP/h6.out" /a/zeta.cpp )"
[ -z "$C6" ] && ok "F4/unparsed+denylisted CONTROL: a/zeta.cpp gets nothing from zeta.unparsed or build/zeta.cpp (neither is indexed)" \
    || no "F4/unparsed+denylisted CONTROL: a/zeta.cpp churn=\"$C6\" — an unindexable same-basename path donated its history"

# ── 6. A --since WINDOW WHOSE TRUE COUNT IS ZERO FOR EVERY ROW ──────────────────────────────────────
# R3's whole history is dated 2019, so a --since FLOOR in 2026 admits nothing. Every row's true count is 0 and
# `ranked=` must be 0 — the phantom shape wave 1 found at 2 weeks was exactly a row whose own count inside the
# window was 0 while `ranked=` counted it anyway. The floor has to sit ABOVE the history, not below it: --since
# is a lower bound, so an old floor cannot exclude a newer commit. An ACTIVE scope is also what makes --hotspots
# answer in its clean-empty form (ranked="0" commits="0") rather than its no-history refusal.
"$BIN" "$R3" --hotspots --since="2026-01-01" --limit=50 > "$TMP/hw.out" 2>"$TMP/hw.err"
WRANKED="$( grep -oE 'ranked="[0-9]+"' "$TMP/hw.out" | head -1 | tr -cd '0-9' )"
WWANT="$( git -C "$R3" -c core.quotepath=false log -c --since="2026-01-01" --name-only --format= | sort -u | grep -c . )"
[ "${WRANKED:-x}" = 0 ] && [ "$WWANT" = 0 ] \
    && ok "empty window: ranked=\"0\" and git's own walk over the same window names 0 paths — no row borrows a count from outside it" \
    || no "empty window: ranked=\"$WRANKED\" but git's walk over that window names $WWANT path(s)"

# ── 7. RENAME (git's R100): the pre-rename path is a DEAD path, and a same-basename file must not inherit it ─
# `old.cpp` (4 commits) is renamed to `new.cpp`; `sub/old.cpp` exists with 1 commit of its own. `git log
# --name-only` reports the pre-rename commits under `old.cpp`, which no longer names an indexed file — and
# `sub/old.cpp` is its ONLY surviving same-basename candidate, so there is no tie. Nothing may inherit it.
R7="$( mktemp -d )"; TMPDIRS="$TMPDIRS $R7"
mkdir -p "$R7/sub"
mkfn oldFn > "$R7/old.cpp"
mkfn subFn > "$R7/sub/old.cpp"
git -C "$R7" init -q; git -C "$R7" config user.email r@x.com; git -C "$R7" config user.name R
D 2026-06-01T12:00:00; git -C "$R7" add -A >/dev/null; git -C "$R7" commit -qm c1
for i in 2 3 4; do
    printf '// pre-rename %s\n' "$i" >> "$R7/old.cpp"
    D "2026-06-0${i}T12:00:00"; git -C "$R7" add -A >/dev/null; git -C "$R7" commit -qm "pre$i"
done
D 2026-06-08T12:00:00; git -C "$R7" mv old.cpp new.cpp; git -C "$R7" commit -qm rename
unset GIT_AUTHOR_DATE GIT_COMMITTER_DATE
git -C "$R7" log -1 --name-status --find-renames=40% --format= | grep -q '^R' \
    && ok "rename: git itself reports the commit as a rename (R…), so the sandbox is the R100 shape" \
    || ok "rename: git reported the change as delete+add — the dead-path question is identical either way"
"$BIN" "$R7" --hotspots --limit=50 > "$TMP/h7.out" 2>/dev/null
C7SUB="$( churn_of "$TMP/h7.out" /sub/old.cpp )"
W7SUB="$( git -C "$R7" log -c --since="12 months ago" --name-only --format= | grep -cx 'sub/old.cpp' )"
C7NEW="$( churn_of "$TMP/h7.out" /new.cpp )"
W7NEW="$( git -C "$R7" log -c --since="12 months ago" --name-only --format= | grep -cx 'new.cpp' )"
[ "${C7SUB:-0}" = "$W7SUB" ] && ok "rename: sub/old.cpp keeps its own $W7SUB commit(s) — the 4 pre-rename commits of the DEAD old.cpp are nobody's" \
    || no "rename: sub/old.cpp churn=\"$C7SUB\" but its own path appears in $W7SUB in-window commit(s)"
[ "${C7NEW:-0}" = "$W7NEW" ] && ok "rename: new.cpp reports exactly the $W7NEW commit(s) that name it (history starts at the rename, as documented)" \
    || no "rename: new.cpp churn=\"$C7NEW\", git's own walk names it in $W7NEW commit(s)"

# ── 8. PATH SPELLINGS: spaces, non-ASCII, and a CASE-ONLY difference ────────────────────────────────
# Spaces and UTF-8 must JOIN (git emits them raw under core.quotepath=false, and a C-quoted path is unquoted
# at the seam). A case-only difference must NOT join: on this case-insensitive filesystem a committed spelling
# that has drifted from the on-disk spelling is a fact to notice, never a licence to bind a different file.
R8="$( mktemp -d )"; TMPDIRS="$TMPDIRS $R8"
mkdir -p "$R8/od d" "$R8/nested"
mkfn spaceFn  > "$R8/od d/sp ace.cpp"
mkfn utf8Fn   > "$R8/nested/héllo wörld.cpp"
mkfn quoteFn  > "$R8/nested/tab$( printf '\t' )ed.cpp"
mkfn caseFn   > "$R8/Case.cpp"
git -C "$R8" init -q; git -C "$R8" config user.email s@x.com; git -C "$R8" config user.name S
D 2026-06-01T12:00:00; git -C "$R8" add -A >/dev/null; git -C "$R8" commit -qm c1
for i in 2 3; do
    printf '// t%s\n' "$i" >> "$R8/od d/sp ace.cpp"
    printf '// t%s\n' "$i" >> "$R8/nested/héllo wörld.cpp"
    printf '// t%s\n' "$i" >> "$R8/nested/tab$( printf '\t' )ed.cpp"
    printf '// t%s\n' "$i" >> "$R8/Case.cpp"
    D "2026-06-0${i}T12:00:00"; git -C "$R8" add -A >/dev/null; git -C "$R8" commit -qm "t$i"
done
# now make the on-disk spelling differ from the committed spelling in CASE ONLY, without a git rename
mv "$R8/Case.cpp" "$R8/casetmp" && mv "$R8/casetmp" "$R8/case.cpp"
unset GIT_AUTHOR_DATE GIT_COMMITTER_DATE
"$BIN" "$R8" --hotspots --limit=50 > "$TMP/h8.out" 2>"$TMP/h8.err"
# `want` must come from the SAME git command ripwire runs, C-unquoted the same way. Two traps live here and both
# bit this gate while it was being written: without `-c core.quotepath=false` git octal-escapes the UTF-8 bytes,
# and WITH it git still C-quotes a path containing a control byte — so a raw `grep -cxF` against a shell literal
# counts 0 for two of these three files and would have "proved" the join broken when it is the expectation that
# is wrong. Unquote git's side in python, exactly as gitUnquotePath does, then compare.
gitPathCount(){   # gitPathCount REPO RELPATH — in-window commits naming exactly RELPATH, per ripwire's own command
    git -C "$1" -c core.quotepath=false log -c --since="12 months ago" --name-only --format= \
        | python3 -c '
import sys, re
def unquote( raw ):
    if len( raw ) < 2 or raw[0] != "\"" or raw[-1] != "\"": return raw.encode( "utf-8", "surrogateescape" )
    out, i, body = bytearray(), 1, raw[ 1 : -1 ]
    while i - 1 < len( body ):
        c = body[ i - 1 ]; i += 1
        if c != "\\": out += c.encode( "utf-8", "surrogateescape" ); continue
        e = body[ i - 1 ]; i += 1
        simple = { "a":7, "b":8, "f":12, "n":10, "r":13, "t":9, "v":11, "\"":34, "\\":92 }
        if e in simple: out.append( simple[e] )
        elif e.isdigit():
            digits = e
            while len( digits ) < 3 and i - 1 < len( body ) and body[ i - 1 ] in "01234567": digits += body[ i - 1 ]; i += 1
            out.append( int( digits, 8 ) )
        else: out += e.encode( "utf-8", "surrogateescape" )
    return bytes( out )
want = sys.argv[1].encode( "utf-8", "surrogateescape" )
print( sum( 1 for line in sys.stdin.read().split( "\n" ) if line and unquote( line ) == want ) )
' "$2"
}
# spec = <repo-relative path>|<how the row is spelled in the XML>|<label>. The two differ for the control-byte
# file: the join takes the RAW byte and the serializer escapes it to &#9; (G4), so a grep for the literal tab
# finds nothing and would read as a broken join when both halves are in fact correct.
for spec in "od d/sp ace.cpp|/od d/sp ace.cpp|spaces" \
            "nested/héllo wörld.cpp|/nested/héllo wörld.cpp|non-ASCII (UTF-8)" \
            "nested/tab$( printf '\t' )ed.cpp|/nested/tab&#9;ed.cpp|a C-quoted control byte, XML-escaped on the way out"; do
    rel="${spec%%|*}"; label="${spec##*|}"; xmlsuffix="${spec#*|}"; xmlsuffix="${xmlsuffix%|*}"
    got="$( churn_of "$TMP/h8.out" "$xmlsuffix" )"
    want="$( gitPathCount "$R8" "$rel" )"
    [ "${want:-0}" -gt 0 ] || no "spelling ($label): the fixture is wrong — git's own walk names '$rel' in 0 commits"
    [ "${got:-0}" = "${want:-0}" ] && ok "spelling ($label): '$rel' joins and reports its own $want commit(s)" \
        || no "spelling ($label): '$rel' churn=\"$got\", git's own walk names it in $want commit(s)"
done
# `Case.cpp` has 3 commits in git; `case.cpp` is what is indexed. Zero, not three.
C8CASE="$( churn_of "$TMP/h8.out" /case.cpp )"
[ -z "$C8CASE" ] || [ "$C8CASE" = 0 ] \
    && ok "spelling (case-only): the committed Case.cpp's 3 commits do NOT land on the indexed case.cpp" \
    || no "spelling (case-only): case.cpp churn=\"$C8CASE\" — a case-folded guess bound a path git never spelled that way"

# ── 8b. G2 — a DECOMPOSED (NFD) filename, the half §8's fixtures could not reach ────────────────────
# §8 pins non-ASCII paths, but its fixtures are written by the shell from this file's own bytes, which are
# NFC — so the NORMALIZATION half was untested and a real defect lived under it. On macOS a file created with
# a decomposed accent ("e" + U+0301) stays NFD on disk while git, with core.precomposeunicode on by default,
# stores and prints the COMPOSED form. Different byte strings; this join is byte-exact; so the file is indexed
# and 100% of its git history is lost — --hotspots never ranks it, --owners omits it from files=, stderr empty,
# no alert. That silent total loss is indistinguishable from a real zero, and a normalization mismatch is none
# of the five states gitmine.h rules deliberately silent (deleted / excluded / outside-root / renamed /
# case-drift). Composing NFD→NFC needs the Unicode tables this zero-dependency binary does not carry, so the
# class is DISCLOSED, and this arm is what proves the disclosure fires and says the true thing.
# The fixture is written by python3 with explicit codepoints — never a shell literal, which is exactly how the
# NFC-only coverage happened.
# mk_nfd_repo DIR [PRECOMPOSE] — the NFD/NFC fixture pair, three commits each. PRECOMPOSE=false forces git to
# record the on-disk NFD bytes VERBATIM, which is what a Linux/ext4 checkout does natively; left unset, the
# platform decides (macOS composes via core.precomposeunicode, Linux does not) — so both shapes are reachable
# from either platform and neither branch below can pass by being inapplicable.
#
# L6 (Linux probe): the bodies carry a DECISION POINT, exactly like mkfn above, and that is load-bearing, not
# decoration. They used to be `int nfdFn( int a ) { return a + 1; }` — cognitive complexity ZERO — and
# --hotspots ranks on churn x ccx, so a zero-complexity file is never emitted as an <f> row no matter how many
# commits touch it, and churn_of reads "" for it. On macOS that stayed invisible: git composes, so the arm
# takes the DISCLOSURE branch, which never calls churn_of. On Linux git records NFD verbatim, the JOIN branch
# runs, and it read churn="<none>" and failed — a fixture that cannot produce the row it asserts, on the one
# platform that asserts it. The join itself was never at fault (proved below, on both git shapes).
mk_nfd_repo(){
    dir="$1"; precompose="${2:-}"
    python3 - "$dir" <<'PY'
import sys, os
# ESCAPED codepoints, never literal bytes: a heredoc literal is whatever the editor saved (NFC here), which
# is exactly how the arm above came to cover only the COMPOSED half of "non-ASCII". "héllo.cpp" is
# e + COMBINING ACUTE ACCENT (NFD); "wörld.cpp" is a PRECOMPOSED o-diaeresis (NFC) — same visual class,
# no combining mark — the control that must stay silent. The body mirrors mkfn's (one `if`) so the file can
# actually be RANKED by --hotspots; see the L6 note above.
root = sys.argv[1]
body = lambda fn: "int %s( int x )\n{\n    if( x > 1 ) return x + 1;\n    return x - 1;\n}\n" % fn
open( os.path.join( root, "héllo.cpp" ), "w" ).write( body( "nfdFn" ) )
open( os.path.join( root, "wörld.cpp"  ), "w" ).write( body( "nfcFn" ) )
PY
    git -C "$dir" init -q; git -C "$dir" config user.email s@x.com; git -C "$dir" config user.name S
    [ -n "$precompose" ] && git -C "$dir" config core.precomposeunicode "$precompose"
    D 2026-06-01T12:00:00; git -C "$dir" add -A >/dev/null; git -C "$dir" commit -qm c1
    for i in 2 3; do
        python3 - "$dir" "$i" <<'PY'
import sys, os
root, i = sys.argv[1], sys.argv[2]
for name in ( "héllo.cpp", "wörld.cpp" ):
    open( os.path.join( root, name ), "a" ).write( "// t%s\n" % i )
PY
        D "2026-06-0${i}T12:00:00"; git -C "$dir" add -A >/dev/null; git -C "$dir" commit -qm "t$i"
    done
    unset GIT_AUTHOR_DATE GIT_COMMITTER_DATE
}

R8B="$( mktemp -d )"; TMPDIRS="$TMPDIRS $R8B"
mk_nfd_repo "$R8B"

# PREMISE: does git on THIS platform record a spelling different from the on-disk one? macOS with
# core.precomposeunicode (the default) does; a platform that records the NFD bytes verbatim does not, and
# there the file joins normally. Both are asserted below — the arm must never pass by being inapplicable.
NFDSPELL="$( python3 -c 'print("he\u0301llo.cpp")' )"
GITSPELL="$( git -C "$R8B" -c core.quotepath=false ls-files --full-name -- "$NFDSPELL" | head -1 )"
"$BIN" "$R8B" --hotspots --limit=50 >"$TMP/h8b.out" 2>"$TMP/h8b.err"
"$BIN" "$R8B" --owners >"$TMP/o8b.out" 2>>"$TMP/h8b.err"
"$BIN" "$R8B" --top-k=50 >"$TMP/m8b.out" 2>/dev/null
grep -q 'nfdFn' "$TMP/m8b.out" \
    && ok "G2: the NFD-named file IS indexed (so any zero it reports is a JOIN result, not an absent file)" \
    || no "G2: the NFD-named file is not indexed at all — the fixture, not the join, is at fault"

if [ -n "$GITSPELL" ] && [ "$GITSPELL" != "$NFDSPELL" ]; then
    ok "G2 premise: this platform's git records a DIFFERENT spelling than the disk ('$GITSPELL' vs the NFD name)"
    grep -q 'DECOMPOSED (NFD) filename' "$TMP/h8b.err" \
        && ok "G2: the loss is DISCLOSED on stderr (was: silent, empty stderr, indistinguishable from a real zero)" \
        || no "G2: no NFD disclosure on stderr — a total history loss is still silent. stderr was: $( head -1 "$TMP/h8b.err" )"
    grep -q "1 indexed file(s) carry a DECOMPOSED" "$TMP/h8b.err" \
        && ok "G2: the disclosure COUNTS the affected files (1 of the fixture's 2 — the composed sibling is fine)" \
        || no "G2: the disclosure does not carry the right count: $( grep -o '[0-9]* indexed file(s) carry a DECOMPOSED' "$TMP/h8b.err" | head -1 )"
    grep -q "git spells it" "$TMP/h8b.err" \
        && ok "G2: the disclosure names BOTH spellings (the two look identical; only the bytes differ)" \
        || no "G2: the disclosure does not name git's own spelling, so the reader cannot act on it"
    # trap #3: an alert arm must establish that this build CAN observe alerts with its OWN probe before it
    # believes its own silence — a Release/NDEBUG build compiles DEGRADED_PATH_ALERT out and this arm would
    # then pass for the wrong reason (the 2026-07-27 CI trap). Probe with an unrelated, already-gated degrade.
    "$BIN" "$R8B" --rank-by=churn --since=notadate >/dev/null 2>"$TMP/h8b.probe"
    if grep -q 'math degraded' "$TMP/h8b.probe"; then
        grep -q 'math degraded' "$TMP/h8b.err" \
            && ok "G2: the plain build's DEGRADED_PATH_ALERT fires too (the surface that gates degrade paths)" \
            || no "G2: no DEGRADED_PATH_ALERT for the NFD join loss on a build that CAN observe them (probe confirmed)"
    else
        printf '  SKIP  G2: alerts are compiled out on this build (NDEBUG) — the alert arm cannot observe anything\n'
    fi
else
    ok "G2 premise: this platform's git records the on-disk NFD bytes verbatim — the mismatch cannot arise here"
    C8B="$( churn_of "$TMP/h8b.out" "/$NFDSPELL" )"
    [ "${C8B:-0}" -gt 0 ] \
        && ok "G2: the NFD file joins normally here (churn=\"$C8B\") — nothing to disclose" \
        || no "G2: the NFD file reports churn=\"${C8B:-<none>}\" on a platform whose git spells it identically"
    grep -q 'DECOMPOSED (NFD) filename' "$TMP/h8b.err" \
        && no "G2: FALSE POSITIVE — the disclosure fired on a platform where the two spellings agree" \
        || ok "G2: no disclosure fired where the spellings agree (the probe confirms before it speaks)"
fi

# ── 8c. G2 on the OTHER git shape, FORCED — the join half runs on every platform ────────────────────
# §8b's two branches are selected by what git does on the host, so each platform only ever exercises one of
# them: macOS always took the DISCLOSURE branch, Linux always took the JOIN branch. That is how the join
# branch's fixture defect (L6 — see mk_nfd_repo) survived every macOS run of this gate and reddened the very
# first Linux one. core.precomposeunicode=false makes git record the on-disk NFD bytes verbatim, which is a
# Linux checkout's native behaviour, so this arm runs the join half HERE too, unconditionally. Nothing
# platform-specific is asserted: git spells the file exactly as the index does, so its history must bind and
# there is nothing to disclose.
R8C="$( mktemp -d )"; TMPDIRS="$TMPDIRS $R8C"
mk_nfd_repo "$R8C" false
GITSPELL_C="$( git -C "$R8C" -c core.quotepath=false ls-files --full-name -- "$NFDSPELL" | head -1 )"
[ "$GITSPELL_C" = "$NFDSPELL" ] \
    && ok "G2/forced: core.precomposeunicode=false makes git record the on-disk NFD bytes verbatim (the Linux shape, on any host)" \
    || no "G2/forced: git records '$GITSPELL_C' even with core.precomposeunicode=false — the forced fixture is not the shape it claims"
"$BIN" "$R8C" --hotspots --limit=50 >"$TMP/h8c.out" 2>"$TMP/h8c.err"
C8C="$( churn_of "$TMP/h8c.out" "/$NFDSPELL" )"
[ "${C8C:-0}" -gt 0 ] \
    && ok "G2/forced: the NFD file's history JOINS byte-exactly (churn=\"$C8C\") — the join was never the defect" \
    || no "G2/forced: the NFD file reports churn=\"${C8C:-<none>}\" though git spells it exactly as the index does"
grep -q 'DECOMPOSED (NFD) filename' "$TMP/h8c.err" \
    && no "G2/forced: FALSE POSITIVE — the disclosure fired where the two spellings agree byte-for-byte" \
    || ok "G2/forced: no disclosure fired where the spellings agree"

# no false positive on a COMPOSED non-ASCII name: §8's own fixture is NFC and must stay silent
grep -q 'DECOMPOSED (NFD) filename' "$TMP/h8.err" \
    && no "G2: FALSE POSITIVE — §8's composed (NFC) non-ASCII fixture triggered the NFD disclosure" \
    || ok "G2: §8's composed (NFC) non-ASCII fixture triggers no NFD disclosure"

# ── 9. F6 — A GIT PATH LONGER THAN THE OLD char[4096], THROUGH EVERY READER THAT FEEDS THE JOIN ──────
# The wave recorded "readers moved onto readByteSafeLine"; it was true of ONE of five. A >4095-byte repo-relative
# path is split by fgets, and the TAIL fragment is a SHORTER path that can bind to a real but WRONG file — the
# §H6 failure mode arriving through the reader instead of the join. Such a path cannot be created on this
# filesystem (PATH_MAX ~1024), so it is written straight into the object store with `git fast-import`; its tail
# is deliberately the survivor's own repo-relative path, which is what makes the misbinding observable:
#   base:  --for churn="4"   --owners authors="2"   --cochange partners="1"      (all three fabricated)
#   fixed: --for churn="1"   --owners authors="1"   --cochange partners="0"
# Reader coverage: gitLogNameOnlyRaw (--for churn=), gitFileAuthors (--owners), gitLogFileSets (--cochange),
# gitCommandLines (--hotspots, the one wave 1 moved — the CONTROL here). The fifth,
# gitFileCommitCountsInDayWindow, is reachable only through --quality-delta's short-horizon-churn kind, so it is
# covered by the source arm at the end of this section instead.
if git fast-import --help >/dev/null 2>&1; then
    R9="$( mktemp -d )"; TMPDIRS="$TMPDIRS $R9"
    mkdir -p "$R9/src"
    mkfn xFn > "$R9/src/x.cpp"
    mkfn oFn > "$R9/src/other.cpp"
    git -C "$R9" init -q -b main; git -C "$R9" config user.email real@x.com; git -C "$R9" config user.name Real
    D 2026-06-01T12:00:00; git -C "$R9" add -A >/dev/null; git -C "$R9" commit -qm c1
    unset GIT_AUTHOR_DATE GIT_COMMITTER_DATE
    # 4095 bytes of directory prefix, then "src/x.cpp": fgets' first chunk ends exactly at the prefix, so the
    # SECOND chunk is the survivor's own path, byte for byte.
    python3 - > "$TMP/fastimport.stream" <<'PYEOF'
long = "dd/" * 1365 + "src/x.cpp"
assert len( "dd/" * 1365 ) == 4095
for i in range( 3 ):
    print( "commit refs/heads/main" )
    print( "mark :%d" % ( i + 1 ) )
    print( "author Ghost <ghost@x.com> %d +0000" % ( 1780000000 + i * 86400 ) )
    print( "committer Ghost <ghost@x.com> %d +0000" % ( 1780000000 + i * 86400 ) )
    print( "data <<EOM" ); print( "long path commit %d" % i ); print( "EOM" )
    print( "from " + ( "refs/heads/main^0" if i == 0 else ":%d" % i ) )
    print( "M 100644 inline src/other.cpp" )
    print( "data <<EOD" ); print( "int oFn( int x ) { if( x > 2 ) return x + 9; return x - 9; } // e%d" % i ); print( "EOD" )
    print( "M 100644 inline " + long )
    print( "data <<EOD" ); print( "hi %d" % i ); print( "EOD" )
PYEOF
    git -C "$R9" fast-import --quiet < "$TMP/fastimport.stream" >/dev/null 2>&1
    LONGROWS="$( git -C "$R9" log -c --name-only --format= | awk 'length($0)>4095' | grep -c . )"
    [ "${LONGROWS:-0}" = 3 ] && ok "F6: the fixture really does carry 3 git paths longer than the old char[4096]" \
        || no "F6: fast-import did not produce the long paths (got $LONGROWS) — the rest of this section proves nothing"

    F9="$( "$BIN" "$R9" --for="xFn" 2>/dev/null | tr '<' '\n' | grep -F 'n="xFn"' | grep -oE 'churn="[0-9]+"' | tr -cd '0-9' )"
    W9="$( git -C "$R9" log -c --since="12 months ago" --name-only --format= | grep -cx 'src/x.cpp' )"
    [ "${F9:-0}" = "$W9" ] && ok "F6/gitLogNameOnlyRaw: --for churn=\"$F9\" equals src/x.cpp's own $W9 commit(s) — the split tail bound to nothing" \
        || no "F6/gitLogNameOnlyRaw: --for churn=\"$F9\" but src/x.cpp's own path appears in $W9 in-window commit(s) (a 4096-byte split tail bound to it)"

    A9="$( "$BIN" "$R9" --owners --detail=1 --limit=50 2>/dev/null | tr '>' '\n' | psel /src/x.cpp | grep -oE 'authors="[0-9]+"' | tr -cd '0-9' )"
    [ "${A9:-0}" = 1 ] && ok "F6/gitFileAuthors: src/x.cpp has ONE author — the long path's Ghost is not folded in" \
        || no "F6/gitFileAuthors: src/x.cpp authors=\"$A9\", want 1 (the split tail donated the long path's author)"

    P9="$( "$BIN" "$R9" --cochange=src/x.cpp 2>/dev/null | grep -oE 'partners="[0-9]+"' | head -1 | tr -cd '0-9' )"
    [ "${P9:-0}" = 0 ] && ok "F6/gitLogFileSets: --cochange invents no partner for src/x.cpp from the long path's commits" \
        || no "F6/gitLogFileSets: --cochange reports partners=\"$P9\" — the split tail put src/x.cpp in 3 commits it was never in"

    H9="$( churn_of "$( "$BIN" "$R9" --hotspots --limit=50 2>/dev/null > "$TMP/h9.out"; echo "$TMP/h9.out" )" /src/x.cpp )"
    [ "${H9:-0}" = "$W9" ] && ok "F6/gitCommandLines CONTROL: --hotspots was already on the byte-safe reader and still reports $W9" \
        || no "F6/gitCommandLines CONTROL: --hotspots churn=\"$H9\", want $W9"
else
    ok "F6: git fast-import unavailable — long-path arms skipped (behavioural), source arm below still applies"
fi
# The COMPLETENESS arm, and the one that would have caught the finding: the claim is that no git-pipe reader in
# gitmine.h uses a fixed line buffer. Assert it of the source, not of one call site.
# G3 correction: this arm used to accept "gitmine.h also reads a sha and two short accumulators through fgets,
# and those are safe BY SHAPE", and pinned the COUNT of readByteSafeLine adoptions at five. Both halves were the
# trap. Counting adoptions cannot see a survivor (that is trap #10 stated exactly), and the count itself rots
# the moment a reader is legitimately added — as it did here. The bar is now: no fixed-buffer reader survives
# ANYWHERE in the file (§9c asserts that from source, comments excluded), and at LEAST the five path readers
# go through the byte-safe one. A lower bound cannot rot upward; a survivor still fails §9c.
LEFTOVER="$( grep -c 'char line\[ 4096 \]' "$ROOT/src/gitmine.h" || true )"
SAFEREADERS="$( grep -c 'readByteSafeLine( pipe' "$ROOT/src/gitmine.h" || true )"
[ "${LEFTOVER:-1}" = 0 ] && ok "F6/completeness: no 'char line[ 4096 ]' path reader survives in gitmine.h" \
    || no "F6/completeness: $LEFTOVER fixed-buffer path reader(s) still in gitmine.h — a long path can still be split there"
[ "${SAFEREADERS:-0}" -ge 5 ] && ok "F6/completeness: all five git-pipe PATH readers go through readByteSafeLine ($SAFEREADERS call sites: gitCommandLines, gitLogFileSets, gitLogNameOnlyRaw, gitFileCommitCountsInDayWindow, gitFileAuthors, + any later adopter)" \
    || no "F6/completeness: only $SAFEREADERS readByteSafeLine call site(s) in gitmine.h, expected at least the five path readers"

# ── 9c. G3 — the migration claim is re-derived FROM SOURCE, not read from the comment that makes it ──
# F6 recorded "every git-pipe reader in this file uses readByteSafeLine"; it was true at one of five. The fix
# that recorded F6 left THREE more `fgets` readers in the same file (a rev-parse probe, a %H window boundary,
# a %ct head epoch) — trap #10 recurring in the same file in the same wave. All three were harmless (fixed,
# short output; two accumulate), which is exactly why nobody looked: "harmless" is a property of today's
# command, not of the reader. They are migrated, and this arm is the thing that keeps the claim true, by
# counting the OLD pattern's SURVIVORS in code rather than the new pattern's adoptions.
SRC="$ROOT/src/gitmine.h"
if [ -f "$SRC" ]; then
    LEGACYREADERS="$( grep -nE 'fgets|char[[:space:]]+(line|buf)[[:space:]]*\[' "$SRC" | grep -vE '^[0-9]+:[[:space:]]*(//|\*|/\*)' | wc -l | tr -d ' ' )"
    [ "${LEGACYREADERS:-1}" = "0" ] \
        && ok "G3: no fgets / fixed-line-buffer reader survives in src/gitmine.h (every hit is a comment)" \
        || no "G3: $LEGACYREADERS fixed-buffer git-pipe reader(s) survive in src/gitmine.h — $( grep -nE 'fgets|char[[:space:]]+(line|buf)[[:space:]]*\[' "$SRC" | grep -vE '^[0-9]+:[[:space:]]*(//|\*|/\*)' | head -3 | tr '\n' ' ' )"
    # and the readers that replaced them still WORK: the two probes whose values feed a window are exercised
    # here rather than trusted (a migrated reader that returns "" degrades silently to an empty window).
    "$BIN" "$R8" --hotspots --since="12 months ago" --limit=5 >"$TMP/g3since.out" 2>"$TMP/g3since.err"
    grep -q 'window=' "$TMP/g3since.out" \
        && ok "G3: the migrated --since window probe still resolves (window= present after the reader swap)" \
        || no "G3: --since produced no window= after the reader swap: $( head -1 "$TMP/g3since.err" )"
    "$BIN" "$R8" --quality-delta >"$TMP/g3qd.out" 2>"$TMP/g3qd.err"
    grep -q '<quality-delta' "$TMP/g3qd.out" \
        && ok "G3: the migrated HEAD-epoch probe still drives short-horizon churn (--quality-delta emits)" \
        || no "G3: --quality-delta emitted nothing after the HEAD-epoch reader swap: $( head -1 "$TMP/g3qd.err" )"
else
    no "G3: src/gitmine.h not found at $SRC — the source-level arm cannot run"
fi


# ── 10. THE DERIVED OFFSET: three spellings of one tree must agree, including a SUBDIRECTORY root ────
# The offset exists because git anchors at the repo TOPLEVEL and the index anchors at the crawl root. Where the
# crawl root is a SUBDIRECTORY, git's paths carry leading segments the indexed paths do not — and with a
# basename/suffix join that direction cannot match at all, so churn silently vanished: `cd src && ripwire .`
# reported ranked="0" on the base binary and 73 correct rows on this one. Same tree, three spellings, one truth.
if git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1 && [ -d "$ROOT/src" ]; then
    "$BIN" "$ROOT/src" --hotspots --limit=1000 > "$TMP/o_abs.out" 2>/dev/null
    ( cd "$ROOT/src" && "$BIN" . --hotspots --limit=1000 ) > "$TMP/o_dot.out" 2>"$TMP/o_dot.err"
    RA="$( grep -oE 'ranked="[0-9]+"' "$TMP/o_abs.out" | head -1 | tr -cd '0-9' )"
    RD="$( grep -oE 'ranked="[0-9]+"' "$TMP/o_dot.out" | head -1 | tr -cd '0-9' )"
    [ -n "$RD" ] && [ "${RD:-0}" -gt 0 ] \
        && ok "offset: a crawl root spelled '.' from INSIDE the repo ranks $RD rows (the derived gitPrefix is doing real work)" \
        || no "offset: 'cd src && ripwire .' ranked=\"$RD\" — the derived git prefix is not being applied, so churn vanished"
    [ "${RA:-0}" = "${RD:-1}" ] && ok "offset: the absolute-subdir and dot-from-inside spellings agree (ranked=$RA)" \
        || no "offset: ranked=\"$RA\" for '$ROOT/src' vs \"$RD\" for '.' inside it — one spelling of the same tree is wrong"
    # and every row of the dot spelling re-derives against git's own walk, prefixed by the offset
    git -C "$ROOT" log -c --since="12 months ago" --name-only --format= | sort | uniq -c | awk '{ print $1" "$2 }' > "$TMP/o.counts"
    tr '>' '\n' < "$TMP/o_dot.out" | grep -oE 'p="\./[^"]+" churn="[0-9]+"' | sed 's|p="\./||; s|" churn="| |; s|"$||' > "$TMP/o.rows"
    obad=0; orows=0
    while read -r rel got; do
        orows=$(( orows + 1 ))
        want="$( awk -v p="src/$rel" '$2 == p { print $1 }' "$TMP/o.counts" )"; [ -n "$want" ] || want=0
        [ "$got" != "$want" ] && { obad=$(( obad + 1 )); no "offset: ./$rel churn=\"$got\" but git names src/$rel in $want in-window commit(s)"; }
    done < "$TMP/o.rows"
    [ "$obad" = 0 ] && ok "offset: all $orows rows of the subdirectory-root spelling re-derive against git's own walk (prefix 'src/')" \
        || no "offset: $obad of $orows subdirectory-root rows disagree with git"
fi

# 10b. A root directory spelled with a SPACE and non-ASCII bytes — the offset probe runs `rev-parse
# --show-toplevel` on it and then string-compares the answer against a realpath, so a root git renders
# differently from the way it was passed would break every join in the tree at once (silently: churn just
# empties). `--show-toplevel` prints the directory verbatim, and this arm is what keeps that true.
R11="$( mktemp -d )/répo dïr"; TMPDIRS="$TMPDIRS $( dirname "$R11" )"
mkdir -p "$R11/src"
mkfn uFn > "$R11/src/u.cpp"
git -C "$R11" init -q; git -C "$R11" config user.email t@x.com; git -C "$R11" config user.name T
D 2026-06-01T12:00:00; git -C "$R11" add -A >/dev/null; git -C "$R11" commit -qm c1
printf '// t\n' >> "$R11/src/u.cpp"
D 2026-06-02T12:00:00; git -C "$R11" add -A >/dev/null; git -C "$R11" commit -qm c2
unset GIT_AUTHOR_DATE GIT_COMMITTER_DATE
"$BIN" "$R11" --hotspots --limit=50 > "$TMP/h11.out" 2>"$TMP/h11.err"
C11="$( churn_of "$TMP/h11.out" /src/u.cpp )"
W11="$( git -C "$R11" -c core.quotepath=false log -c --since="12 months ago" --name-only --format= | grep -cx 'src/u.cpp' )"
[ "${C11:-0}" = "$W11" ] && ok "offset: a root spelled with a space and non-ASCII bytes still derives (src/u.cpp = $W11)" \
    || no "offset: churn=\"$C11\" under a non-ASCII root dir, want $W11 — the toplevel probe's answer did not compare equal"

# ── 11. A NESTED REPO must not capture the outer root's offset ──────────────────────────────────────
# The offset is derived from one probe file, so WHICH file is load-bearing: a file inside a nested checkout
# (submodule, vendored clone) answers `rev-parse --show-toplevel` with the NESTED toplevel, and using it would
# take the whole outer root's churn with it. The probe is the shallowest indexed path for exactly this reason.
R10="$( mktemp -d )"; TMPDIRS="$TMPDIRS $R10"
mkdir -p "$R10/inner"
mkfn outerFn > "$R10/a.cpp"
mkfn innerFn > "$R10/inner/b.cpp"
git -C "$R10/inner" init -q; git -C "$R10/inner" config user.email i@x.com; git -C "$R10/inner" config user.name I
D 2026-05-01T12:00:00; git -C "$R10/inner" add -A >/dev/null; git -C "$R10/inner" commit -qm i1
git -C "$R10" init -q; git -C "$R10" config user.email o@x.com; git -C "$R10" config user.name O
D 2026-06-01T12:00:00; git -C "$R10" add a.cpp >/dev/null; git -C "$R10" commit -qm o1
printf '// outer touch\n' >> "$R10/a.cpp"
D 2026-06-02T12:00:00; git -C "$R10" add a.cpp >/dev/null; git -C "$R10" commit -qm o2
unset GIT_AUTHOR_DATE GIT_COMMITTER_DATE
"$BIN" "$R10" --hotspots --limit=50 > "$TMP/h10.out" 2>"$TMP/h10.err"
C10="$( churn_of "$TMP/h10.out" /a.cpp )"
W10="$( git -C "$R10" log -c --since="12 months ago" --name-only --format= | grep -cx 'a.cpp' )"
[ "${C10:-0}" = "$W10" ] && ok "nested repo: the OUTER root keeps its own churn ($W10) — the nested checkout did not capture the offset" \
    || no "nested repo: a.cpp churn=\"$C10\" but git names it in $W10 outer commit(s) — a nested toplevel won the probe"
[ -z "$( churn_of "$TMP/h10.out" /inner/b.cpp )" ] \
    && ok "nested repo: inner/b.cpp gets no churn from the OUTER log, which never names it (correct, and quiet)" \
    || no "nested repo: inner/b.cpp churn=\"$( churn_of "$TMP/h10.out" /inner/b.cpp )\" — the outer log does not name that path at all"

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit $fail
