#!/usr/bin/env bash
# cochangecliocheck.sh — the gate for the three CLIO/MVG refinements of --cochange's surprising="1".
#
# WHY THIS GATE EXISTS. ripwire's `--cochange surprising="1"` predicate — "file pairs that change
# together in git but share no transitive static dependency" — is an independent implementation of
# published work (Wong, Cai, Kim & Dalton, *Detecting Software Modularity Violations*, ICSE 2011, the
# Clio tool; extended by Mo, Cai, Kazman & Xiao, IEEE TSE 2019). docs/LINEAGE.md §2 now cites both.
# Reading the papers against the shipped predicate surfaced three things ripwire did NOT have, each of
# which this gate pins:
#
#   (a) RECURRENCE. Clio does not report a discrepancy the first time it appears — it mines frequent
#       patterns over the LAST FIVE RELEASES and reports only the RECURRING ones. ripwire mined a
#       single 18-month window, in which a one-off refactor sprint that touched two files four times
#       in one week is INDISTINGUISHABLE from a structural defect that has bled for eighteen months.
#       Both scored together=4. The window is now split into equal-commit-count sub-windows and each
#       row carries recur= — how many of them actually contain a joint commit.
#
#   (b) GROUPING (Mo's MVG). A Modularity Violation Group is defined as the minimal set of GROUPS
#       covering all violating pairs (f_core, f_j), not a list of pairs. "core.cpp co-changes with
#       {g1,g2,g3}, none of which it depends on" is ONE actionable row naming the file to fix; three
#       pair rows are the same fact spread over three lines with the actionable part left implicit.
#
#   (c) DIRECTIONAL CONFIDENCE. Clio's confidence is asymmetric — conf = frq(x1 U x2)/frq(x1) — so
#       "A always drags B" is distinguishable from "B always drags A". ripwire's deg= is confidence
#       over the QUIETER file, which is the MAXIMUM of the two directions with no record of which
#       direction it came from. A reader met deg="1.00" on a pair and could not tell which of the two
#       files was the one that never moves alone.
#
# THE FIXTURE, and why it is scripted rather than picked out of live output. Every semantic arm below
# runs against mkClioFixture()'s throwaway git repo, whose history is written by this gate so that
# each arm is a SINGLE-VARIABLE test. The live repo is swept afterwards for INVARIANTS only (arms 6),
# because a published fresh-history clone has different commits than the author's machine and an arm
# anchored on named live pairs can only pass in one place — the lesson cochangesurprisecheck.sh
# already learned and records at length.
#
# The fixture is 24 mining commits over 10 files. NO file includes any other, so every pair is
# dependency-capable and surprising by construction, and the only thing that varies between pairs is
# the timing and shape of their co-change.
#
# THE BASE COMMIT IS DELIBERATELY OVERSIZED. It creates the ten real files plus 25 inert fillers — 35
# paths, past the 30-file bulk-commit cap every co-change walk here applies (Code Maat's lesson,
# docs/LINEAGE.md §3a) — so the miner DROPS it. Without that, the base commit would be a joint commit
# for all 45 pairs at once and would silently add one sub-window to every pair's recurrence, which is
# exactly what it would do to a real repository's initial import. It therefore doubles as a live
# assertion that the cap still works: if the cap ever stops firing, the burst pair below picks up a
# second sub-window and arm (1c) goes red.
#
#   commits (oldest=1 .. newest=24); sub-windows are equal COMMIT-COUNT thirds, so with 24 mined
#   commits the boundaries fall at 8/8/8: oldest = c1..c8, middle = c9..c16, newest = c17..c24.
#   No pair below is scheduled ON a boundary commit, so the arms survive an off-by-one in either
#   direction of the chunker.
#
#     steady1+steady2   4, 12, 20   -> together=3, one joint commit in EACH third   => recur=3
#     burst1+burst2    17, 18, 19   -> together=3, all three inside the NEWEST third => recur=1
#     core+g1           5, 13, 21   -> together=3, recur=3
#     core+g2           6, 14, 22   -> together=3, recur=3
#     core+g3           7, 15, 23   -> together=3, recur=3
#     hub+follow        3, 11, 24   -> together=3, recur=3
#     hub ALONE         1, 2, 8, 9, 10, 16
#
#   burst vs steady is the whole point of arm (a): identical together=, identical deg=, and the ONLY
#   difference is whether the co-change recurs. A one-line edit to the commit numbers flips it, which
#   is what makes it a mutation-testable control rather than an assertion nobody has watched fail.
#
#   core is the MVG control: it has three surprising partners and g1/g2/g3 have exactly one each
#   (their commit triples are disjoint, so g1/g2/g3 never co-change with each OTHER). The greedy
#   cover therefore has exactly one possible first pick, and the group is unambiguous.
#
#   hub/follow is the asymmetry control: follow appears in 3 commits and hub in 9, so
#   conf(follow=>hub) = 3/3 = 1.00 while conf(hub=>follow) = 3/9 = 0.33. steady1/steady2 both appear
#   in exactly 3 and are the TIE control — a driver= claim there would be a claim the data does not
#   support, so the attribute must be absent rather than guessed.
#
#   RIPWIRE_BIN=build/ripwire      bash test/cochangecliocheck.sh
#   RIPWIRE_BIN=build_base/ripwire bash test/cochangecliocheck.sh   # must FAIL (pre-refinement binary)

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){   printf '  PASS  %s\n' "$*"; }
no(){   printf '  FAIL  %s\n' "$*"; fail=1; }
skip(){ printf '  SKIP  %s\n' "$*"; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
command -v git >/dev/null || { echo "cochangecliocheck: git not on PATH"; exit 2; }
echo "cochangecliocheck: BIN=$BIN  ROOT=$ROOT"

# ══ 0. THE FIXTURE REPO ═══════════════════════════════════════════════════════════════════════════
FIX="$TMP/cliofix"
mkClioFixture(){
    mkdir -p "$FIX/src" || return 1
    for f in steady1 steady2 burst1 burst2 core g1 g2 g3 hub follow; do
        printf 'int %s_value(){ return 0; }\n' "$f" > "$FIX/src/$f.cpp"
    done
    # 25 inert fillers push the base commit to 35 paths, past the 30-file bulk cap — see the header.
    for i in $( seq 1 25 ); do
        printf 'int filler%s_value(){ return %s; }\n' "$i" "$i" > "$FIX/src/filler$i.cpp"
    done
    (
        cd "$FIX" || exit 1
        git init -q . || exit 1
        git config user.email clio@example.invalid
        git config user.name  clio-fixture
        git config commit.gpgsign false
        git add -A && git commit -qm "fixture base" || exit 1

        # touch() appends a distinct line to each named file and makes ONE commit of exactly them.
        touchCommit(){
            local n="$1"; shift
            for f in "$@"; do
                printf '// commit %s\n' "$n" >> "src/$f.cpp"
            done
            git add -A && git commit -qm "c$n: $*" || exit 1
        }
        for n in $( seq 1 24 ); do
            case "$n" in
                4|12|20)       touchCommit "$n" steady1 steady2 ;;
                17|18|19)      touchCommit "$n" burst1  burst2  ;;
                5|13|21)       touchCommit "$n" core    g1      ;;
                6|14|22)       touchCommit "$n" core    g2      ;;
                7|15|23)       touchCommit "$n" core    g3      ;;
                3|11|24)       touchCommit "$n" hub     follow  ;;
                *)             touchCommit "$n" hub             ;;
            esac
        done
    ) >/dev/null 2>&1
}
mkClioFixture || { echo "cochangecliocheck: could not build the fixture repo (git unusable?)"; exit 2; }

run(){ "$BIN" "$FIX" --cochange --pack-top-n=1000 --no-cache "$@" 2>"$TMP/err"; }

run > "$TMP/fix"
rc=$?
[ "$rc" -eq 0 ] && ok "fixture: --cochange exits 0" || { no "fixture: --cochange exits $rc"; head -3 "$TMP/err"; }
[ -s "$TMP/fix" ] || { echo "cochangecliocheck: empty fixture output, cannot proceed"; exit 2; }

# pull one <pair .../> element naming BOTH fragments, in either a=/b= order.
pairRow(){ grep -oE '<pair [^>]*/>' "$1" | grep -F "src/$2.cpp" | grep -F "src/$3.cpp" | head -n1; }
attrOf(){  printf '%s' "$1" | grep -oE " $2=\"[^\"]*\"" | head -n1 | sed -E 's/.*="([^"]*)"/\1/'; }

# ══ 1. RECURRENCE — the header discloses the sub-window count, every row carries recur= ════════════
#
# Honesty rule #3: a number mined over a partitioned window is only readable if the partition is
# published. sub_windows= is that disclosure, and it is what makes recur= interpretable at all —
# recur="1" means nothing until the reader knows whether the denominator was 3 or 30.
subw="$( grep -oE '<cochange [^>]*>' "$TMP/fix" | head -n1 | grep -oE 'sub_windows="[0-9]+"' | sed -E 's/.*"([0-9]+)"/\1/' )"
if [ -z "$subw" ]; then
    no "(1a) the <cochange> header does NOT disclose sub_windows= — recur= would be a number with an unpublished denominator"
elif [ "$subw" = "3" ]; then
    ok "(1a) header discloses sub_windows=\"3\" over the fixture's 24 commits"
else
    no "(1a) header discloses sub_windows=\"$subw\", expected 3 on a 24-commit fixture"
fi

rows_total="$(  grep -oE '<pair [^>]*/>' "$TMP/fix" | wc -l | tr -d ' ' )"
rows_recur="$(  grep -oE '<pair [^>]*/>' "$TMP/fix" | grep -c 'recur="' || true )"
if [ "$rows_total" -gt 0 ] && [ "$rows_total" = "$rows_recur" ]; then
    ok "(1b) all $rows_total pair rows carry recur="
else
    no "(1b) only $rows_recur of $rows_total pair rows carry recur= — the attribute is not on every row"
fi

# The single-variable arm. burst and steady have IDENTICAL together= and deg=; only recurrence differs.
burst="$(  pairRow "$TMP/fix" burst1  burst2  )"
steady="$( pairRow "$TMP/fix" steady1 steady2 )"
if [ -z "$burst" ] || [ -z "$steady" ]; then
    no "(1c) the burst/steady control pairs are ABSENT from the fixture's own uncapped output — the support floor or the pair scan regressed"
else
    bt="$( attrOf "$burst" together )";  st="$( attrOf "$steady" together )"
    br="$( attrOf "$burst" recur )";     sr="$( attrOf "$steady" recur )"
    if [ "$bt" != "$st" ]; then
        no "(1c) control is broken: burst together=$bt but steady together=$st — they must be identical for recurrence to be the only variable"
    elif [ "$br" = "1" ] && [ "$sr" = "3" ]; then
        ok "(1c) same together=$bt, different recurrence: burst recur=\"1\" (one sprint) vs steady recur=\"3\" (all three sub-windows)"
    else
        no "(1c) burst recur=\"$br\" (expected 1) / steady recur=\"$sr\" (expected 3) at identical together=$bt — recurrence is not separating them"
    fi
fi

# ── 1d. the FILTER. --cochange-recur=K must drop exactly the pairs below K and nothing else.
run --cochange-recur=2 > "$TMP/fix.r2"
if [ -n "$( pairRow "$TMP/fix.r2" burst1 burst2 )" ]; then
    no "(1d) --cochange-recur=2 still emits the recur=1 burst pair — the filter does not filter"
elif [ -z "$( pairRow "$TMP/fix.r2" steady1 steady2 )" ]; then
    no "(1d) --cochange-recur=2 dropped the recur=3 steady pair as well — the filter is over-broad"
else
    ok "(1d) --cochange-recur=2 drops the one-sprint pair and keeps the recurring one"
fi
if grep -qE '<cochange [^>]*min_recur="2"' "$TMP/fix.r2"; then
    ok "(1e) the filtered header discloses min_recur=\"2\" — a reduced pair count is explained, not silent"
else
    no "(1e) --cochange-recur=2 emits FEWER pairs with nothing in the header saying so — an undisclosed filter reads as 'there are no more'"
fi

# ── 1f. the INVARIANT: 1 <= recur <= sub_windows on every row. A recur above the denominator, or a
#        zero, is an arithmetic bug that no per-pair assertion above would catch.
badrecur=0; seenrecur=0
for r in $( grep -oE '<pair [^>]*/>' "$TMP/fix" | grep -oE 'recur="[0-9]+"' | sed -E 's/.*"([0-9]+)"/\1/' ); do
    seenrecur=$(( seenrecur + 1 ))
    { [ "$r" -ge 1 ] && [ "$r" -le "${subw:-0}" ]; } || badrecur=$(( badrecur + 1 ))
done
if [ "$seenrecur" -eq 0 ]; then
    no "(1f) no fixture row carried a recur= at all — the range invariant would otherwise pass vacuously"
elif [ "$badrecur" -eq 0 ]; then
    ok "(1f) all $seenrecur fixture rows satisfy 1 <= recur <= sub_windows ($subw)"
else
    no "(1f) $badrecur of $seenrecur fixture row(s) carry a recur= outside [1, $subw]"
fi

# ══ 2. DIRECTIONAL CONFIDENCE — both directions, and which file is the driver ══════════════════════
#
# conf_ab is Clio's conf for the rule a=>b: of the commits that touched a, the fraction that also
# touched b. driver= names the antecedent of the STRONGER rule — the file that most reliably drags
# the other — and deg= must equal the larger of the two, which is the relationship that turns three
# numbers into one readable claim instead of three unrelated ones.
hf="$( pairRow "$TMP/fix" follow hub )"
if [ -z "$hf" ]; then
    no "(2a) the hub/follow asymmetry control is ABSENT from the fixture output"
else
    cab="$( attrOf "$hf" conf_ab )"; cba="$( attrOf "$hf" conf_ba )"; drv="$( attrOf "$hf" driver )"; dg="$( attrOf "$hf" deg )"
    if [ -z "$cab" ] || [ -z "$cba" ]; then
        no "(2a) hub/follow row carries no conf_ab=/conf_ba= — only the symmetric deg=\"$dg\", which cannot say which file never moves alone: $hf"
    elif [ "$cab" = "1.00" ] && [ "$cba" = "0.33" ]; then
        ok "(2a) hub/follow is asymmetric and says so: conf_ab=\"1.00\" (follow never changes without hub) vs conf_ba=\"0.33\""
    else
        no "(2a) hub/follow conf_ab=\"$cab\" conf_ba=\"$cba\", expected 1.00 / 0.33 (follow in 3 commits, hub in 9, 3 shared): $hf"
    fi
    # a= sorts before b= by path, so a=src/follow.cpp and the driver is the a side.
    if [ "$drv" = "a" ]; then
        ok "(2b) driver=\"a\" names src/follow.cpp — the file whose changes imply the other's"
    else
        no "(2b) driver=\"$drv\" on the hub/follow row, expected \"a\" (src/follow.cpp sorts first and holds the 1.00 direction): $hf"
    fi
    if [ "$dg" = "$cab" ]; then
        ok "(2c) deg=\"$dg\" equals the larger direction — the existing attribute is now attributable to a file"
    else
        no "(2c) deg=\"$dg\" is not the larger of conf_ab=\"$cab\"/conf_ba=\"$cba\" — the three numbers do not reconcile"
    fi
fi

# ── 2d. the MIRROR case. core has 9 commits and g1 has 3, so the strong direction is g1=>core: the
#        driver must be the B side here. Without this arm a hard-coded driver="a" would pass (2b).
cg="$( pairRow "$TMP/fix" core g1 )"
if [ -z "$cg" ]; then
    no "(2d) the core/g1 mirror control is ABSENT from the fixture output"
else
    drv2="$( attrOf "$cg" driver )"
    if [ "$drv2" = "b" ]; then
        ok "(2d) mirror case: core/g1 carries driver=\"b\" (src/g1.cpp is the antecedent) — driver is computed, not hard-coded"
    else
        no "(2d) core/g1 carries driver=\"$drv2\", expected \"b\": core appears in 9 commits and g1 in 3, so g1=>core is the stronger rule: $cg"
    fi
fi

# ── 2e. the TIE case. steady1 and steady2 each appear in exactly 3 commits and share all 3, so both
#        directions are 1.00 and NEITHER file is the driver. Honesty rule: emit nothing rather than
#        break the tie with an arbitrary rule the reader would take for a finding.
if [ -n "$steady" ]; then
    if printf '%s' "$steady" | grep -q 'driver='; then
        no "(2e) the symmetric steady pair claims a driver= — a tie is being broken by fiat and read as a finding: $steady"
    else
        ok "(2e) the symmetric steady pair carries NO driver= — a tie is reported as a tie"
    fi
fi

# ══ 3. MVG GROUPS — one row naming the file to fix, not N pair rows ════════════════════════════════
"$BIN" "$FIX" --cochange --cochange-groups --pack-top-n=1000 --no-cache > "$TMP/fix.g" 2>"$TMP/gerr"
rcg=$?
[ "$rcg" -eq 0 ] && ok "(3a) --cochange-groups exits 0" || { no "(3a) --cochange-groups exits $rcg"; head -3 "$TMP/gerr"; }

ngroups="$( grep -oE '<group [^>]*>' "$TMP/fix.g" | wc -l | tr -d ' ' )"
# Six surprising pairs; core covers three of them, the other three are disjoint edges.
if [ "$ngroups" = "4" ]; then
    ok "(3b) six surprising pairs collapse to 4 groups (core's three, plus three disjoint edges)"
else
    no "(3b) --cochange-groups emitted $ngroups group(s), expected 4 over the fixture's six surprising pairs"
fi

coreGroup="$( tr '<' '\n' < "$TMP/fix.g" | grep -n 'group core="[^"]*src/core\.cpp"' | head -n1 )"
if [ -z "$coreGroup" ]; then
    no "(3c) no <group core=\"...src/core.cpp\"> — the file with three violating partners is not named as a core"
else
    # the group's own members: everything between this <group ...> and its </group>
    python3 - "$TMP/fix.g" > "$TMP/coremembers" <<'PY'
import re,sys
d=open(sys.argv[1]).read()
m=re.search(r'<group core="[^"]*src/core\.cpp"[^>]*>(.*?)</group>',d,re.S)
if m:
    print(m.group(0).split('>',1)[0]+'>')
    for f in re.findall(r'<f p="([^"]*)"',m.group(1)): print(f)
PY
    # RE-PINNED 2026-08-19 (R-E CORRECTION): p= is root-relative, so the members read "src/g1.cpp" and
    # the old 's#.*/src/##' (which needs a slash BEFORE src/) stripped nothing. Anchored to the start.
    members="$( tail -n +2 "$TMP/coremembers" | sed -E 's#^(.*/)?src/##' | sort | tr '\n' ' ' )"
    if [ "$members" = "g1.cpp g2.cpp g3.cpp " ]; then
        ok "(3c) the core group names exactly {g1,g2,g3} — one actionable row instead of three pair rows"
    else
        no "(3c) the core group's members are [$members], expected [g1.cpp g2.cpp g3.cpp ]"
    fi
    hdr="$( head -n1 "$TMP/coremembers" )"
    pc="$( printf '%s' "$hdr" | grep -oE 'partners="[0-9]+"' | sed -E 's/.*"([0-9]+)"/\1/' )"
    [ "$pc" = "3" ] && ok "(3d) the core group discloses partners=\"3\"" \
                    || no "(3d) the core group discloses partners=\"$pc\", expected 3"
fi

# ── 3e. COVERAGE, both ways. Every surprising pair must appear in exactly one group: a pair covered
#        twice inflates the report, a pair covered zero times loses a finding silently. The header's
#        own pairs_covered= must reconcile with the emitted membership rows, or the disclosure is
#        decorative.
nsurprising="$( grep -oE '<pair [^>]*/>' "$TMP/fix" | grep -c 'surprising="1"' || true )"
nmembers="$( grep -oE '<f p="[^"]*"' "$TMP/fix.g" | wc -l | tr -d ' ' )"
covered="$( grep -oE '<cochange [^>]*>' "$TMP/fix.g" | head -n1 | grep -oE 'pairs_covered="[0-9]+"' | sed -E 's/.*"([0-9]+)"/\1/' )"
if [ "$nsurprising" = "$nmembers" ] && [ "$covered" = "$nsurprising" ]; then
    ok "(3e) $nsurprising surprising pairs, $nmembers group memberships, header pairs_covered=\"$covered\" — an exact cover, and the header says the same number"
else
    no "(3e) cover does not reconcile: $nsurprising surprising pairs vs $nmembers group memberships vs header pairs_covered=\"$covered\""
fi

# ── 3f. groups must COMPOSE with the recurrence filter, or the two refinements are separate tools
#        that happen to share a verb.
"$BIN" "$FIX" --cochange --cochange-groups --cochange-recur=2 --pack-top-n=1000 --no-cache > "$TMP/fix.gr" 2>/dev/null
if ! grep -q '<group ' "$TMP/fix.gr"; then
    no "(3f) --cochange-groups --cochange-recur=2 emitted NO groups at all — the composition arm would otherwise pass vacuously"
elif grep -q 'src/burst1\.cpp' "$TMP/fix.gr" || grep -q 'src/burst2\.cpp' "$TMP/fix.gr"; then
    no "(3f) --cochange-groups --cochange-recur=2 still contains the recur=1 burst pair — the two refinements do not compose"
else
    ok "(3f) --cochange-groups honours --cochange-recur (the one-sprint pair is gone from the grouped form too)"
fi

# ══ 4. THE PER-FILE FORM must speak the same vocabulary ════════════════════════════════════════════
#
# §P9.1's lesson, one attribute over: when the same concept is emitted by two paths, the paths drift.
# The per-file form's deg= is ALREADY directional (this file => partner), so the reverse direction is
# what it is missing; recur= it lacks outright.
"$BIN" "$FIX" --cochange=src/follow.cpp --pack-top-n=1000 --no-cache > "$TMP/fix.pf" 2>/dev/null
pfrow="$( grep -oE '<f p="[^"]*" [^>]*/>' "$TMP/fix.pf" | grep -F 'src/hub.cpp' | head -n1 )"
if [ -z "$pfrow" ]; then
    no "(4a) --cochange=src/follow.cpp does not list src/hub.cpp as a partner"
else
    pfr="$( attrOf "$pfrow" recur )"; pfrev="$( attrOf "$pfrow" conf_rev )"; pfdeg="$( attrOf "$pfrow" deg )"
    [ "$pfr" = "3" ] && ok "(4a) the per-file row carries recur=\"3\", the same number the pair form reports" \
                     || no "(4a) the per-file row carries recur=\"$pfr\", expected 3 — the two paths disagree: $pfrow"
    if [ "$pfdeg" = "1.00" ] && [ "$pfrev" = "0.33" ]; then
        ok "(4b) the per-file row emits both directions: deg=\"1.00\" (follow=>hub) and conf_rev=\"0.33\" (hub=>follow)"
    else
        no "(4b) per-file deg=\"$pfdeg\" conf_rev=\"$pfrev\", expected 1.00 / 0.33: $pfrow"
    fi
fi
if grep -qE '<cochange [^>]*sub_windows="3"' "$TMP/fix.pf"; then
    ok "(4c) the per-file header discloses sub_windows= too"
else
    no "(4c) the per-file header omits sub_windows= — its recur= has an unpublished denominator"
fi

# ══ 5. G4 + determinism ════════════════════════════════════════════════════════════════════════════
if command -v xmllint >/dev/null; then
    for f in fix fix.r2 fix.g fix.gr fix.pf; do
        xmllint --noout "$TMP/$f" 2>/dev/null && ok "(5a) xmllint clean: $f" || no "(5a) xmllint REJECTED $f"
    done
else
    skip "(5a) xmllint not on PATH"
fi
"$BIN" "$FIX" --cochange --cochange-groups --pack-top-n=1000 --no-cache > "$TMP/det1" 2>/dev/null
"$BIN" "$FIX" --cochange --cochange-groups --pack-top-n=1000 --no-cache > "$TMP/det2" 2>/dev/null
cmp -s "$TMP/det1" "$TMP/det2" && ok "(5b) two grouped runs are byte-identical" \
                               || no "(5b) --cochange-groups is NOT deterministic across two runs"

# ══ 6. THE LIVE REPO — invariants only, never a named pair ═════════════════════════════════════════
"$BIN" "$ROOT" --cochange --pack-top-n=100000 > "$TMP/live" 2>/dev/null
if ! grep -q '<pair ' "$TMP/live"; then
    skip "(6) live repo has no co-change pairs above the support floor (shallow clone?) — invariants not exercised"
else
    lsub="$( grep -oE '<cochange [^>]*>' "$TMP/live" | head -n1 | grep -oE 'sub_windows="[0-9]+"' | sed -E 's/.*"([0-9]+)"/\1/' )"
    badlive=0
    for r in $( grep -oE '<pair [^>]*/>' "$TMP/live" | grep -oE 'recur="[0-9]+"' | sed -E 's/.*"([0-9]+)"/\1/' ); do
        { [ "$r" -ge 1 ] && [ "$r" -le "${lsub:-0}" ]; } || badlive=$(( badlive + 1 ))
    done
    [ -n "$lsub" ] && [ "$badlive" -eq 0 ] \
        && ok "(6a) live repo: every recur= lies in [1, sub_windows=$lsub]" \
        || no "(6a) live repo: sub_windows=\"$lsub\" and $badlive row(s) carry an out-of-range recur="
    # deg must be the max of the two directions on EVERY live row — the reconciliation arm (2c) run
    # over a real corpus rather than one hand-built pair.
    python3 - "$TMP/live" > "$TMP/degcheck" <<'PY'
import re,sys
bad=0; n=0
for row in re.findall(r'<pair [^>]*/>', open(sys.argv[1]).read()):
    g=lambda a:(lambda m: float(m.group(1)) if m else None)(re.search(a+r'="([0-9.]+)"',row))
    deg,ab,ba=g('deg'),g('conf_ab'),g('conf_ba')
    if None in (deg,ab,ba): continue
    n+=1
    if abs(deg-max(ab,ba))>0.011: bad+=1
print(n,bad)
PY
    read -r ln lbad < "$TMP/degcheck"
    if [ "${ln:-0}" -eq 0 ]; then
        no "(6b) no live row carried deg=/conf_ab=/conf_ba= together — the reconciliation cannot be checked"
    elif [ "$lbad" -eq 0 ]; then
        ok "(6b) live repo: deg == max(conf_ab, conf_ba) on all $ln rows (0.01 rounding band)"
    else
        no "(6b) live repo: $lbad of $ln rows have deg != max(conf_ab, conf_ba)"
    fi
fi

if [ "$fail" -eq 0 ]; then
    echo "cochangecliocheck: ALL PASS"
else
    echo "cochangecliocheck: FAILURES ABOVE"
fi
exit "$fail"
