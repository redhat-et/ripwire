#!/usr/bin/env bash
# cochangesurprisecheck.sh — §P9.1 gate: --cochange's repo-wide surprising="1" flag must use the SAME
# transitive #include-closure predicate as the per-file path, not a 1-hop-only check.
#
# The repo-wide path's static-dependency predicate (src/main.cpp, --cochange pair scan) was a 1-HOP
# neighbour test, while the header comment promises "no TRANSITIVE static dependency" and the per-file
# path (src/gitmine.h cochangePartners, A4-F22) already computed the correct forward+reverse transitive
# closure. Result: a genuinely coupled pair like ingest.cpp -> ingest.h -> model.h (one hop indirect)
# shipped as `surprising="1"` — a confident FALSE POSITIVE on the tool's own architecturally-actionable
# rows (both src<->src rows in the emitted top-30 were wrong: ingest.cpp<->model.h, main.cpp<->notes.h).
#
# Fix: ONE shared predicate — src/gitmine.h::StaticIncludeCoupling, built once from resolveIncludeAdj(ing)
# and used by BOTH cochangePartners (per-file) and the repo-wide pair scan in src/main.cpp.
#
# This gate:
#   (1) NEGATIVE  — a pair with a real #include path, DIRECT or TRANSITIVE (and in either direction),
#                   must NOT carry surprising="1".
#   (1b) NEGATIVE — a CROSS-DIRECTORY bare-name `#include "x.h"` (the `-I` form the path-precise
#                   resolver structurally cannot see) must not carry surprising="1" either.
#   (2) POSITIVE  — a genuinely uncoupled DEPENDENCY-CAPABLE pair (src<->src, no #include path either
#                   way) must STILL carry surprising="1": the fix must not suppress the signal wholesale.
#   (2b) §A9.3    — a pair with a DEP-INCAPABLE side (.sh/.md/.pdf/.pptx/.json) must carry dep_capable="0"
#                   and never surprising="1"; the per-file path must say the same thing.
#   (3) DETERMINISM — two runs are byte-identical.
#
# CORPUS ANCHORING (2026-08-01, Lane O). Arms (1), (1b), (2) and (2b) USED to be pinned to named pairs
# out of THIS repo's git history (ingest.cpp<->model.h, main.cpp<->notes.h, bench_convergence.cpp<->
# svector.h) and to whatever happened to sit in the live top-30. That is not a property of the code under
# test, it is a property of one machine's `.git`: on the published fresh-history repo — i.e. on every
# clone anyone but the author will ever make, and therefore on every CI run — those commits do not exist,
# both NEGATIVE arms printed "pair not found ... (fixture drifted — cannot assert)" and the gate exited 1.
# A gate that can only pass on the author's laptop is not a gate.
#
# So the four semantic arms are re-anchored onto a DETERMINISTIC IN-GATE FIXTURE REPO built from scratch
# by mkCochangeFixture() below: a throwaway git tree with a scripted co-change history that contains, by
# construction, one pair of every kind the predicate has to separate. It needs no history but its own, so
# it asserts identically on a fresh clone, a shallow CI checkout and the author's machine — and it closes
# the ledgered "the positive control is picked from live output, so it can silently stop being a control"
# gate-health item, because the fixture's positive pair is uncoupled BY CONSTRUCTION.
#
# The LIVE repo is still swept afterwards (§A9.3's uncapped no-leak sweep is exactly the kind of check
# that wants a big real corpus), but every live arm is now PRESENCE-GUARDED: where the row it needs does
# not exist in this corpus it SKIPs with the missing precondition named, and where the row DOES exist it
# hard-asserts exactly as before. No live arm can red merely because a clone has different history.
#
# §A9.3 AMENDMENT (2026-07-28) — arm (2)'s control INVERTED, on purpose. It used to require that a
# src<->test/*.sh pair still carry surprising="1", on the reasoning "a shell script can never be
# #included by C++, so the flag must survive". That reasoning is exactly the §A9 finding: surprising=
# claims "these change together yet NO static dependency explains it", and for a pair that could not
# carry a static dependency AT ALL the claim is vacuously true, not evidence of hidden coupling. ~22 of
# the first 30 repo-wide rows were such pairs (a .pdf<->.pptx build-artifact pair read as hidden
# architectural debt). So the shell-script pair is now the NEGATIVE control for dep_capable="0", and the
# "signal survives" duty moved to a real src<->src surprising row, which is what the flag is FOR.
#
#   RIPWIRE_BIN=build/ripwire      bash test/cochangesurprisecheck.sh
#   RIPWIRE_BIN=build_base/ripwire bash test/cochangesurprisecheck.sh   # must FAIL (pre-fix binary)

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
command -v git >/dev/null || { echo "cochangesurprisecheck: git not on PATH"; exit 2; }
echo "cochangesurprisecheck: BIN=$BIN  ROOT=$ROOT"

skip(){ printf '  SKIP  %s\n' "$*"; }

"$BIN" "$ROOT" --cochange >"$TMP/out" 2>"$TMP/err"
rc=$?
[ "$rc" -eq 0 ] && ok "--cochange exits 0" || { no "--cochange exits $rc"; cat "$TMP/err"; }
[ -s "$TMP/out" ] || { echo "cochangesurprisecheck: empty output, cannot proceed"; exit 2; }

# --pack-top-n raises the cap so the rows checked below aren't hidden by the default 30-row truncation
# (surprising=0 pairs sort AFTER surprising=1 ones, so a fixed cap alone could make a false positive
# silently "pass" by dropping out of the top-N instead of by being correctly unflagged).
"$BIN" "$ROOT" --cochange --pack-top-n=1000 >"$TMP/full" 2>/dev/null

# ══ 0. THE FIXTURE REPO — every semantic arm's corpus, built here, owned here ═════════════════════════
#
# One throwaway git repo whose co-change history is scripted so that ONE co-change wave touches every
# file: every pair therefore has identical together=/deg= support, and the ONLY thing that can vary
# between two pairs is the #include predicate itself. That is what makes each arm below a clean
# single-variable test rather than a correlation over whatever the corpus happened to contain.
#
#   src/apply.cpp  --#include "mid.h"-->  src/mid.h  --#include "leaf.h"-->  src/leaf.h
#       → apply.cpp/mid.h  = DIRECT include            (arm 1a)
#       → apply.cpp/leaf.h = TRANSITIVE, 2 hops        (arm 1b — the §P9.1 defect: a 1-hop-only
#                                                       predicate flags exactly this pair)
#       → leaf.h/mid.h     = REVERSE (leaf is includED) (arm 1c — the closure is undirected)
#   bench/probe.cpp --#include "leaf.h"--> (bare name, other directory, resolvable only through -Isrc)
#       → probe.cpp/leaf.h = the §P9.1 RESIDUE class   (arm 1d)
#   src/alpha.cpp / src/beta.cpp and src/alpha.cpp / src/beta.h — both sides dependency-capable, NO
#   include path in either direction
#       → the POSITIVE controls                         (arms 2a/2b). 2b is deliberately the SAME .cpp/.h
#         shape as the negatives above and differs from them in exactly one bit — whether the include
#         line exists — so a single edited line in this fixture flips it, which is what makes it a
#         mutation-testable control rather than an assertion nobody has ever seen fail.
#   tools/deploy.sh — cannot participate in a C++ include graph at all
#       → dep_capable="0", never surprising="1"         (arms 3a/3b)
FIX="$TMP/cofix"
mkCochangeFixture(){
    mkdir -p "$FIX/src" "$FIX/bench" "$FIX/tools" || return 1
    printf '#pragma once\nint leafValue();\n'                                      > "$FIX/src/leaf.h"
    printf '#pragma once\n#include "leaf.h"\nint midValue();\n'                    > "$FIX/src/mid.h"
    printf '#include "mid.h"\nint apply(){ return midValue() + leafValue(); }\n'   > "$FIX/src/apply.cpp"
    printf '#pragma once\nint alphaValue();\n'                                     > "$FIX/src/alpha.h"
    printf '#include "alpha.h"\nint alphaValue(){ return 1; }\n'                   > "$FIX/src/alpha.cpp"
    printf '#pragma once\nint betaValue();\n'                                      > "$FIX/src/beta.h"
    printf '#include "beta.h"\nint betaValue(){ return 2; }\n'                     > "$FIX/src/beta.cpp"
    printf '#include "leaf.h"\nint probe(){ return leafValue(); }\n'               > "$FIX/bench/probe.cpp"
    printf '#!/bin/sh\necho deploy\n'                                              > "$FIX/tools/deploy.sh"
    (
        cd "$FIX" || exit 1
        git init -q . || exit 1
        git config user.email cochange@example.invalid
        git config user.name  cochange-fixture
        git config commit.gpgsign false
        git add -A && git commit -qm "fixture base" || exit 1
        # Four co-change waves. The support floor is 3 commits-together, so four is one clear of it and
        # every pair in the tree crosses it in the same wave — see the single-variable note above.
        for i in 1 2 3 4; do
            printf 'int pad%d(){ return %d; }\n' "$i" "$i" >> src/apply.cpp
            printf '// pad %d\n' "$i"                      >> src/mid.h
            printf '// pad %d\n' "$i"                      >> src/leaf.h
            printf '// pad %d\n' "$i"                      >> src/alpha.cpp
            printf '// pad %d\n' "$i"                      >> src/beta.cpp
            printf '// pad %d\n' "$i"                      >> src/beta.h
            printf '// pad %d\n' "$i"                      >> bench/probe.cpp
            printf '# pad %d\n'  "$i"                      >> tools/deploy.sh
            git add -A && git commit -qm "co-change wave $i" || exit 1
        done
    ) >/dev/null 2>&1
}
mkCochangeFixture || { echo "cochangesurprisecheck: could not build the fixture repo (git unusable?)"; exit 2; }

"$BIN" "$FIX" --cochange --pack-top-n=1000 --no-cache >"$TMP/fix" 2>"$TMP/fix.err"
rc_fix=$?
[ "$rc_fix" -eq 0 ] && ok "fixture: --cochange exits 0 on the scripted repo" || { no "fixture: --cochange exits $rc_fix"; head -3 "$TMP/fix.err"; }

# pull out one <pair .../> element mentioning BOTH path fragments, regardless of a=/b= order. Fragments
# are matched against the fixture's own repo-relative paths, which are unique inside it.
fixPairRow(){
    grep -oE '<pair [^>]*/>' "$TMP/fix" | grep -F "$1" | grep -F "$2" | head -n1
}

# ── 1. NEGATIVE — a pair joined by an #include path (direct, transitive, or reverse) is NOT surprising.
#      Absence here is a hard FAILURE, not a skip: this gate built the history itself, so a missing pair
#      means the support floor or the pair scan moved, which is exactly what the gate is for.
fixNotSurprising(){
    local n1="$1" n2="$2" why="$3"
    local row; row="$( fixPairRow "$n1" "$n2" )"
    if [ -z "$row" ]; then
        no "fixture $n1 <-> $n2: pair ABSENT from the fixture's own uncapped output — the pair scan or the support floor regressed ($why)"
    elif echo "$row" | grep -q 'surprising="1"'; then
        no "fixture $n1 <-> $n2: FALSE POSITIVE — surprising=\"1\" despite $why: $row"
    else
        ok "fixture $n1 <-> $n2: present, no surprising=\"1\" ($why correctly recognised)"
    fi
}
fixNotSurprising "src/apply.cpp" "src/mid.h"    "a DIRECT #include"
fixNotSurprising "src/apply.cpp" "src/leaf.h"   "a TRANSITIVE 2-hop #include path (apply.cpp -> mid.h -> leaf.h) — the §P9.1 defect a 1-hop predicate flags"
fixNotSurprising "src/leaf.h"    "src/mid.h"    "a REVERSE #include (mid.h includes leaf.h) — the closure is undirected"
fixNotSurprising "bench/probe.cpp" "src/leaf.h" "a CROSS-DIRECTORY bare-name \`#include \"leaf.h\"\` (the -I form the path-precise resolver cannot see) — the §P9.1 residue"
fixNotSurprising "src/beta.cpp"  "src/beta.h"   "a DIRECT #include (the mutation-control twin of the src/alpha.cpp <-> src/beta.h positive arm below)"

# ── 2. POSITIVE controls — the signal must still FIRE where it means something. Both pairs co-change in
#      the SAME waves as every negative pair above and differ from them in exactly one respect: no
#      #include path joins them, in either direction. Uncoupled BY CONSTRUCTION, so unlike the old
#      live-output pick these controls cannot quietly stop being controls.
fixSurprising(){
    local n1="$1" n2="$2" why="$3"
    local row; row="$( fixPairRow "$n1" "$n2" )"
    if [ -z "$row" ]; then
        no "fixture positive control $n1 <-> $n2: ABSENT from the fixture's own uncapped output"
    elif echo "$row" | grep -q 'surprising="1"'; then
        ok "fixture positive control fires: $n1 <-> $n2 ($why) carries surprising=\"1\""
    else
        no "fixture positive control $n1 <-> $n2 is NOT surprising=\"1\" — the signal has been suppressed wholesale ($why): $row"
    fi
}
fixSurprising "src/alpha.cpp" "src/beta.cpp" "two dependency-capable translation units, no include path either way"
fixSurprising "src/alpha.cpp" "src/beta.h"   "the same .cpp/.h shape as the negatives, minus the include line"

# ── 3a. §A9.3 on the fixture — the .sh side cannot participate in a C++ include graph, so its rows must
#       carry dep_capable="0" and must never claim surprising="1" (vacuously-true is not evidence).
shRow="$( fixPairRow "tools/deploy.sh" "src/alpha.cpp" )"
if [ -z "$shRow" ]; then
    no "fixture §A9.3: tools/deploy.sh <-> src/alpha.cpp ABSENT from the fixture's own output"
elif echo "$shRow" | grep -q 'surprising="1"'; then
    no "fixture §A9.3: a dependency-INCAPABLE pair claims surprising=\"1\": $shRow"
elif echo "$shRow" | grep -q 'dep_capable="0"'; then
    ok "fixture §A9.3: the .sh-sided pair keeps its row and carries the dep_capable=\"0\" tell"
else
    no "fixture §A9.3: the .sh-sided pair is silent — neither surprising= nor dep_capable=\"0\": $shRow"
fi

# ── 3b. §A9.3 — the PER-FILE path must speak the same vocabulary as the repo-wide one (§P9.1's rule, one
#       flag over). Same fixture, same .sh partner, read through --cochange=<file>.
"$BIN" "$FIX" --cochange=src/alpha.cpp --pack-top-n=1000 --no-cache >"$TMP/fixpf" 2>/dev/null
fixPfRow="$( grep -oE '<f [^>]*/>' "$TMP/fixpf" | grep -F 'deploy.sh' | head -n1 )"
if [ -z "$fixPfRow" ]; then
    no "fixture §A9.3 per-file: --cochange=src/alpha.cpp lists no deploy.sh partner — the per-file scan regressed"
elif echo "$fixPfRow" | grep -q 'surprising="1"'; then
    no "fixture §A9.3 per-file: the .sh partner claims surprising=\"1\" — the two paths disagree again: $fixPfRow"
elif echo "$fixPfRow" | grep -q 'dep_capable="0"'; then
    ok "fixture §A9.3 per-file: the .sh partner carries dep_capable=\"0\", same vocabulary as the repo-wide path"
else
    no "fixture §A9.3 per-file: the .sh partner is silent (no surprising=, no dep_capable=): $fixPfRow"
fi

# ── 3c. fixture determinism — the scripted history is fixed, so two runs must be byte-identical.
"$BIN" "$FIX" --cochange --no-cache >"$TMP/fd1" 2>/dev/null
"$BIN" "$FIX" --cochange --no-cache >"$TMP/fd2" 2>/dev/null
diff -q "$TMP/fd1" "$TMP/fd2" >/dev/null && ok "fixture: deterministic (byte-identical run-to-run)" || no "fixture: non-deterministic --cochange output"

# ══ LIVE-CORPUS SWEEP — presence-guarded ═════════════════════════════════════════════════════════════
# §A9.3's no-leak sweep genuinely wants a big real corpus, so it keeps running against this checkout.
# What it must NOT do is red because a clone's history differs: an arm whose row is absent SKIPs with the
# missing precondition named, and hard-asserts wherever the row exists.

# The live positive control. Its DUTY moved to the fixture arm above; here it is a corroboration on real
# history, so absence is a named SKIP rather than a failure.
livePos="$( grep -oE '<pair [^>]*/>' "$TMP/out" | grep 'surprising="1"' \
           | grep -E 'a="[^"]*/src/[^"]*\.(h|cpp)"' | grep -E 'b="[^"]*/src/[^"]*\.(h|cpp)"' | head -n1 )"
if [ -z "$livePos" ]; then
    skip "live positive control — no src<->src pair clears the co-change support floor in THIS corpus's history (fresh-history export); the duty is discharged by the fixture positive-control arm above"
else
    ok "live corroboration: the signal fires on a real dependency-capable pair too: $livePos"
fi

# ── 2b. §A9.3 — every row with a DEP-INCAPABLE side must carry dep_capable="0" and must NOT carry
#      surprising="1". Swept over the UNCAPPED run: one leaked row is the whole defect (a .pdf<->.pptx
#      pair rendered as hidden coupling), so a sampled check would not be a gate.
badRows="$( grep -oE '<pair [^>]*/>' "$TMP/full" | grep 'surprising="1"' \
            | grep -E '(a|b)="[^"]*\.(sh|md|pdf|pptx|json|rb|txt)"' | head -n3 )"
if [ -n "$badRows" ]; then
    no "§A9.3: a dependency-INCAPABLE pair still claims surprising=\"1\" (vacuously true, reads as hidden coupling):"
    printf '        %s\n' "$badRows"
else
    ok "§A9.3: no .sh/.md/.pdf/.pptx/.json-sided pair carries surprising=\"1\" (uncapped sweep)"
fi

depRow="$( grep -oE '<pair [^>]*/>' "$TMP/full" | grep -E '(a|b)="[^"]*\.sh"' | head -n1 )"
if [ -z "$depRow" ]; then
    skip "live dep_capable=\"0\" tell — no .sh-sided pair clears the co-change support floor in THIS corpus's history (fresh-history export); the duty is discharged by the fixture §A9.3 arm above"
elif echo "$depRow" | grep -q 'dep_capable="0"'; then
    ok "§A9.3: a .sh-sided pair keeps its row and carries the dep_capable=\"0\" tell: $depRow"
else
    no "§A9.3: a .sh-sided pair carries neither surprising= nor dep_capable=\"0\" — the row is silent about why: $depRow"
fi

# ── 2c. §A9.3 — the per-file path must speak the SAME vocabulary as the repo-wide one (§P9.1's rule,
#      one flag over). Live corroboration of the fixture per-file arm; presence-guarded, because whether
#      src/quality.h co-changes with any .sh at all is a property of THIS clone's history.
"$BIN" "$ROOT" --cochange=src/quality.h --pack-top-n=1000 >"$TMP/perfile" 2>/dev/null
perFileRow="$( grep -oE '<f [^>]*/>' "$TMP/perfile" | grep -E 'p="[^"]*\.sh"' | head -n1 )"
if [ -z "$perFileRow" ]; then
    skip "live per-file vocabulary — src/quality.h has no .sh partner above the co-change support floor in THIS corpus's history (fresh-history export); the duty is discharged by the fixture per-file arm above"
elif echo "$perFileRow" | grep -q 'surprising="1"'; then
    no "§A9.3 per-file: a .sh partner still claims surprising=\"1\" — the two paths disagree again: $perFileRow"
elif echo "$perFileRow" | grep -q 'dep_capable="0"'; then
    ok "§A9.3 per-file: a .sh partner carries dep_capable=\"0\", same vocabulary as the repo-wide path: $perFileRow"
else
    no "§A9.3 per-file: a .sh partner is silent (no surprising=, no dep_capable=): $perFileRow"
fi

# ── 3. determinism
"$BIN" "$ROOT" --cochange >"$TMP/d1" 2>/dev/null
"$BIN" "$ROOT" --cochange >"$TMP/d2" 2>/dev/null
diff -q "$TMP/d1" "$TMP/d2" >/dev/null && ok "deterministic (byte-identical run-to-run)" || no "non-deterministic --cochange output"

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit $fail
