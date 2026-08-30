#!/usr/bin/env bash
# cloneidiomcheck.sh — IDIOM-CLASS DEMOTION for clone findings (src/cloneidiom.h).
#
# WHY THIS GATE EXISTS. A four-branch float threshold ladder (`altitudeBandOf`) clone-grouped with four
# unrelated functions in a real ObjC++/C++ tree — a length bucketer, a height tierer, a difficulty band, a
# giant-assembly motion picker. Five cross-domain functions, 44-56 normalized tokens each, sharing only the
# BUCKETING-LADDER IDIOM and not one domain identifier. Every one of them needed a reasoned ack, twice. The
# detector was not wrong about the token streams; it was wrong about what the streams MEAN.
#
# WHAT LANDED. A closed three-member set of recognized idioms — scalar threshold ladder, enum-to-string
# switch name table, param-struct initializer chain — classified from the body's own token shape. A group
# whose every member classifies to the SAME idiom, whose members share NO non-keyword identifier, and whose
# members live in pairwise-distinct enclosing contexts is DEMOTED: it still prints (with the idiom named, so
# a human can overrule the demotion by reading), it just stops gating.
#
# WHAT THIS GATE PINS — the conjunction, in both directions, and the detection it must not change:
#   (A) the ladder pair (the field shape, reproduced in test/cloneidiomfix) demotes, and names its idiom
#   (B) a ladder pair that SHARES domain identifiers classifies but does NOT demote — a real copy-paste
#   (C) a ladder pair in ONE file and ONE namespace classifies but does NOT demote — copy-paste next door
#   (D) the switch name-table pair demotes
#   (E) the param-struct initializer-chain pair demotes
#   (F) a genuinely duplicated body that is NOT a recognized idiom carries no idiom at all and keeps gating
#       — this is the non-vacuity arm: without it every arm above would pass on a classifier that says yes
#       to everything
#   (G) TRUE-POSITIVE PRESERVATION — every fixture still produces exactly the one group with exactly the two
#       members it produced before the classifier existed. Demotion is an annotation, never a deletion, and
#       this arm is what proves it on the row stream itself
#   (H) the quality-delta half: a demoted group is reported minor and is NOT counted by the gating counter,
#       while the non-idiom duplicate beside it still gates (exit 2 still fires for a real regression)
#   (I) the shared-identifier ladder still GATES through quality-delta
#   (J) determinism — two runs byte-identical
#   (K) MUTATION CONTROL — a deliberately-wrong expectation must fail, so (A)-(J) cannot pass vacuously
#   (L) the two root counters are present and count over ALL groups
#   (M) the emitted legend DEFINES both new attributes (the legend-coverage ratchet's own predicate)
#   (N) the fixture corpus is TRACKED by git — a gate whose corpus only exists locally is not a gate
#
# Usage:  bash test/cloneidiomcheck.sh            |   RIPWIRE_BIN=asan/ripwire bash test/cloneidiomcheck.sh
# Exits non-zero on any failure; prints PASS/FAIL per check and ALL PASS on success.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
FIX="$ROOT/test/cloneidiomfix"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
[ -d "$FIX" ] || { echo "no test/cloneidiomfix dir — fixture missing"; exit 2; }
command -v git >/dev/null 2>&1 || { echo "git required"; exit 2; }

# The fixture is COPIED out of test/ before every run. Under its committed home the quality-delta verb's
# duplication kind exempts it as a fixture path, which would make every arm below vacuously green.
CORPUS="$TMP/corpus"; mkdir -p "$CORPUS"
cp -R "$FIX/." "$CORPUS/"

echo "cloneidiomcheck: BIN=$BIN"

# One <group ...> row per line, for grep-per-row assertions.
rows(){ "$BIN" "$CORPUS/$1" --clones --no-cache 2>/dev/null | sed 's|<group |\n<group |g' | grep '^<group'; }

# ── (A)-(F) the conjunction, one fixture per condition ────────────────────────────────────────────────
# expect_row <dir> <memberA> <memberB> <idiom-or-NONE> <demoted:yes|no>
expect_row()
{
    local dir="$1" a="$2" b="$3" idiom="$4" dem="$5" r
    r="$( rows "$dir" )"
    case "$r" in
        *"n=\"$a\""*) ;;
        *) no "$dir: row does not name $a"; return;;
    esac
    case "$r" in
        *"n=\"$b\""*) ;;
        *) no "$dir: row does not name $b"; return;;
    esac
    if [ "$idiom" = NONE ]; then
        case "$r" in
            *' idiom="'*) no "$dir: an unrecognized body was classified as an idiom"; return;;
        esac
    else
        case "$r" in
            *" idiom=\"$idiom\""*) ;;
            *) no "$dir: row is not marked idiom=$idiom"; return;;
        esac
    fi
    case "$r" in
        *' demoted="1"'*) [ "$dem" = yes ] || { no "$dir: row demoted but must keep gating"; return; };;
        *)               [ "$dem" = no  ] || { no "$dir: row not demoted"; return; };;
    esac
    ok "$dir: idiom=$idiom demoted=$dem on ${a}/${b}"
}

expect_row ladder_demote    altitudeBandOf      tankStateFor        threshold-ladder  yes   # (A)
expect_row ladder_sharedids gradeOfScore        gradeOfScore        threshold-ladder  no    # (B)
expect_row ladder_samefile  widthClassOf        depthClassOf        threshold-ladder  no    # (C)
expect_row switchtable      hueName             phaseName           switch-name-table yes   # (D)
expect_row paramstruct      defaultCameraParams defaultMixerParams  builder-chain     yes   # (E)
expect_row nonidiom         accumulateWeights   rollupSamples       NONE              no    # (F)

# ── (G) true-positive preservation: the row stream itself is untouched ────────────────────────────────
# Demotion is an ANNOTATION. Every fixture must still yield exactly ONE group of exactly TWO members —
# the shape each yielded before any of this existed. A classifier that suppressed a row would pass every
# attribute arm above and fail here.
for d in ladder_demote ladder_sharedids ladder_samefile switchtable paramstruct nonidiom; do
    n="$( rows "$d" | wc -l | tr -d ' ' )"
    m="$( rows "$d" | grep -c 'n="2"' )"
    if [ "$n" = 1 ] && [ "$m" = 1 ]; then
        ok "$d: still exactly one 2-member group (detection unchanged)"
    else
        no "$d: expected 1 group of 2, got $n group rows ($m two-member)"
    fi
done

# ── (N) the fixture is TRACKED ────────────────────────────────────────────────────────────────────────
# Found the hard way in this gate's own first commit: `.gitignore` carries `build*/`, so a fixture
# subdirectory named `builder/` was silently never added and every arm above still passed — against files
# that exist only in this checkout. A gate whose corpus is untracked is a gate that is green here and
# absent in CI, so it checks its own corpus.
if git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1; then
    untracked="$( git -C "$ROOT" ls-files --others --exclude-standard --ignored -- test/cloneidiomfix )$( git -C "$ROOT" ls-files --others --exclude-standard -- test/cloneidiomfix )"
    if [ -z "$untracked" ]; then
        ok "every test/cloneidiomfix file is tracked"
    else
        no "test/cloneidiomfix holds files git does not track: $( printf '%s' "$untracked" | tr '\n' ' ' )"
    fi
fi

# ── (L) the two root counters, over ALL groups ────────────────────────────────────────────────────────
root(){ "$BIN" "$CORPUS/$1" --clones --no-cache 2>/dev/null | tr '<' '\n' | grep '^clones '; }
check_counter()
{
    local dir="$1" attr="$2" want="$3" got
    got="$( root "$dir" | sed -n "s/.* $attr=\"\([0-9]*\)\".*/\1/p" )"
    [ "$got" = "$want" ] && ok "$dir: $attr=$want" || no "$dir: $attr=$got, expected $want"
}
check_counter ladder_demote idiom_groups   1
check_counter ladder_demote demoted_groups 1
check_counter nonidiom      idiom_groups   0
check_counter nonidiom      demoted_groups 0

# ── (M) the legend defines both new attributes ────────────────────────────────────────────────────────
# The DEFINITIONAL predicate legendcoveragecheck uses for a closure: the attribute name followed by `=`.
# The legend is everything ahead of the root element, which is where a reader meets it.
LEG="$( "$BIN" "$CORPUS/ladder_demote" --clones --no-cache 2>/dev/null | sed 's/<clones .*//' )"
for a in idiom demoted idiom_groups demoted_groups; do
    case "$LEG" in
        *"$a="*) ok "legend defines $a=";;
        *)       no "legend never defines $a=";;
    esac
done

# ── (H)/(I) the quality-delta half ────────────────────────────────────────────────────────────────────
# A group is only judged preexisting-worse when at least one member EXISTED at the baseline, so each repo
# commits one member and leaves the twin in the working tree. Without that the row is origin="new-symbol",
# which never gates on either side of this change and would make the arm vacuous.
# mkrepo <name> "<committed files>" "<working-tree files>" — every path relative to the fixture corpus.
# The COMMIT must contain only the baseline halves: commit a twin as well and the group exists at the
# baseline, which is no longer a NEW duplication and produces no row at all (this gate's first draft did
# exactly that and read as a missing feature).
mkrepo()
{
    local R="$TMP/$1" f
    mkdir -p "$R/src"
    ( cd "$R" && git init -q . && git config user.email t@t && git config user.name t \
      && git config commit.gpgsign false ) || return 1
    for f in $2; do cp "$CORPUS/$f" "$R/src/"; done
    ( cd "$R" && git add -A && git commit -qm base ) || return 1
    for f in $3; do cp "$CORPUS/$f" "$R/src/"; done
    return 0
}

qd(){ "$BIN" "$TMP/$1" --quality-delta --no-cache 2>/dev/null; }

mkrepo qd_demote "ladder_demote/altitude.h nonidiom/acc.h" "ladder_demote/tank.h nonidiom/roll.h" \
    || { echo "git fixture setup failed"; exit 2; }
QD="$( qd qd_demote )"

# the demoted ladder: minor, idiom named, NOT gating
LROW="$( printf '%s' "$QD" | tr '<' '\n' | grep 'kind="duplication"' | grep 'altitudeBandOf' )"
case "$LROW" in
    *'idiom="threshold-ladder"'*) ok "quality-delta: the ladder row names its idiom";;
    *)                            no "quality-delta: the ladder row has no idiom (row: ${LROW:-<none>})";;
esac
case "$LROW" in
    *'sev="minor"'*) ok "quality-delta: the ladder row is minor";;
    *)               no "quality-delta: the ladder row is not minor";;
esac
case "$LROW" in
    *'gating="1"'*) no "quality-delta: the demoted ladder row still gates";;
    *)              ok "quality-delta: the demoted ladder row does not gate";;
esac

# the non-idiom duplicate beside it: still a gating regression
NROW="$( printf '%s' "$QD" | tr '<' '\n' | grep 'kind="duplication"' | grep 'accumulateWeights' )"
case "$NROW" in
    *'gating="1"'*) ok "quality-delta: the non-idiom duplicate still gates";;
    *)              no "quality-delta: the non-idiom duplicate stopped gating (row: ${NROW:-<none>})";;
esac
case "$NROW" in
    *'idiom='*) no "quality-delta: the non-idiom duplicate was classified";;
    *)          ok "quality-delta: the non-idiom duplicate carries no idiom";;
esac

# (I) shared identifiers → classified, still gating
mkrepo qd_shared "ladder_sharedids/grade.h ladder_sharedids/alphaGrade.h" "ladder_sharedids/betaGrade.h" \
    || { echo "git fixture setup failed"; exit 2; }
SROW="$( qd qd_shared | tr '<' '\n' | grep 'kind="duplication"' | grep 'gradeOfScore' )"
case "$SROW" in
    *'idiom="threshold-ladder"'*) ok "quality-delta: the shared-identifier ladder is classified";;
    *)                            no "quality-delta: the shared-identifier ladder lost its idiom (row: ${SROW:-<none>})";;
esac
case "$SROW" in
    *'gating="1"'*) ok "quality-delta: the shared-identifier ladder still gates";;
    *)              no "quality-delta: the shared-identifier ladder stopped gating";;
esac

# ── (J) determinism ───────────────────────────────────────────────────────────────────────────────────
"$BIN" "$CORPUS" --clones --no-cache >"$TMP/a" 2>/dev/null
"$BIN" "$CORPUS" --clones --no-cache >"$TMP/b" 2>/dev/null
cmp -s "$TMP/a" "$TMP/b" && ok "two --clones runs byte-identical" || no "--clones is not deterministic"

# ── (K) mutation control ──────────────────────────────────────────────────────────────────────────────
# Every arm above is a grep for a string. If the emitter stopped emitting entirely, the NONE/no arms would
# still pass — absence looks like success to half of them. Prove the predicates can still fail: assert a
# claim we KNOW is false (the non-idiom pair classified as a ladder) and require the same machinery to
# report a miss rather than a hit.
MUT="$( rows nonidiom )"
case "$MUT" in
    *'idiom="threshold-ladder"'*) no "mutation control: a non-ladder body matched the ladder classifier";;
    *)                            ok "mutation control: the ladder claim is refutable on this corpus";;
esac
# ...and the positive half: the same string MUST be findable where it belongs, or the arms above are
# passing on an emitter that never runs.
case "$( rows ladder_demote )" in
    *'idiom="threshold-ladder"'*) ok "mutation control: the ladder claim is provable where it holds";;
    *)                            no "mutation control: no ladder row anywhere — the arms above are vacuous";;
esac

echo
[ "$fail" = 0 ] && { echo "ALL PASS"; exit 0; }
echo "FAILURES"; exit 1
