#!/usr/bin/env bash
# churndecaycheck.sh — gate for --rank-by=churn-decay (P0-4: TIME-DECAYED churn).
#
# WHY THIS GATE EXISTS. `--rank-by=churn` counts every commit in its window EQUALLY: a file rewritten
# fifteen times two years ago outranks one rewritten twice last week, which is the opposite of the prior
# an agent wants ("where is the action NOW"). `--rank-by=churn-decay` weights each commit by
# 0.5^(age_days / half_life) with a 90-day half-life, so recency is priced instead of thresholded.
#
# The load-bearing property is NOT the ranking — it is the ANCHOR. "age" is measured from HEAD's own
# committer timestamp, never from the system clock, because ripwire's determinism contract says the same
# tree at the same HEAD must serialize the same bytes on every machine on every day. A wall-clock anchor
# would make this the one verb whose output silently changes overnight, and no diff-based gate can see
# that drift after the fact. So the anchor gets its own MUTATION arm here (arm 5) rather than a comment.
#
# Arms:
#   1  --rank-by=churn-decay is accepted: exit 0, non-empty, well-formed, deterministic across two runs.
#   2  the map STAMPS what it did: rank_by="churn-decay", window= carries the half-life, and the legend
#      spells the decay formula + the HEAD anchor (G4/honesty: a prior you cannot read is not disclosed).
#   3  SEMANTIC: on a fixture where the OLD file has MORE commits and the NEW file has FEWER but recent
#      ones, plain churn ranks the old file's symbol first and churn-decay ranks the new file's first.
#      An implementation that ignored the decay would tie with plain churn and fail this arm.
#   4  --since composes (the cli.h guard that refuses --since without a churn-consuming verb must know
#      about the new value) — no refusal on stderr, exit 0.
#   5  WALL-CLOCK INDEPENDENCE (the mutation that pins the anchor): two repos with IDENTICAL relative
#      commit spacing but absolute dates five years apart must produce the IDENTICAL symbol ORDER. Under
#      a wall-clock anchor the 5-years-ago repo's commits all decay to ~0 and the order collapses to the
#      Laplace-smoothed tie; under the HEAD anchor the two are indistinguishable, which is the contract.
#   6  the file-level <recent> block comes FIRST (H2H-Graft F3).
#   7  merge_bombs_skipped= on <recent>: a commit touching more than 100 files is skipped by the miner, and
#      the block SAYS how many it skipped (always, "0" included) — a >100-file fixture commit reads "1"; a window
#      whose ONLY commit was skipped still prints the block, with zero rows and the count (7h).
#
# Determinism note: symbol ORDER is compared, never k= floats (CONTRIBUTING §3 — a sort has no tolerance
# band, a float does; this gate uses the sort).
#
# Usage:  RIPWIRE_BIN=build/ripwire bash test/churndecaycheck.sh   |   RIPWIRE_BIN=asan/ripwire bash …

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
command -v git >/dev/null 2>&1 || { echo "churndecaycheck: git is required"; exit 2; }

WORK="$( mktemp -d )"; trap 'rm -rf "$WORK"' EXIT
echo "churndecaycheck: BIN=$BIN"

# ── the fixture: a two-file repo whose churn history and whose RECENCY disagree ──────────────────────
# old.py  — 6 commits, all ~400 days before HEAD  ⇒ wins on RAW commit count
# new.py  — 2 commits, at HEAD's own day          ⇒ wins on DECAYED weight (0.5^(400/90) ≈ 0.046 each)
# No call edges between the two files, so the PageRank teleport prior IS the ranking (no structure to
# fight it) — the arm measures the prior, which is the thing this feature changes.
mkrepo()   # $1 = dir, $2 = base epoch (the OLD commits' timestamp; HEAD lands at base + 400 days)
{
    local dir="$1" base="$2" i stamp
    mkdir -p "$dir"
    git -C "$dir" init -q 2>/dev/null
    git -C "$dir" config user.email rw@example.invalid
    git -C "$dir" config user.name  ripwire-gate
    printf 'def old_one():\n    return 1\n' > "$dir/old.py"
    printf 'def new_one():\n    return 2\n' > "$dir/new.py"
    # six OLD commits touching old.py only
    for i in 1 2 3 4 5 6; do
        stamp="$(( base + i * 3600 ))"
        printf 'def old_one():\n    return %d\n' "$i" > "$dir/old.py"
        GIT_AUTHOR_DATE="$stamp +0000" GIT_COMMITTER_DATE="$stamp +0000" \
            git -C "$dir" add -A >/dev/null 2>&1
        GIT_AUTHOR_DATE="$stamp +0000" GIT_COMMITTER_DATE="$stamp +0000" \
            git -C "$dir" commit -q -m "old $i" >/dev/null 2>&1
    done
    # two RECENT commits touching new.py only; the last one is HEAD, so age(old) ≈ 400 days
    for i in 1 2; do
        stamp="$(( base + 400 * 86400 + i * 3600 ))"
        printf 'def new_one():\n    return %d\n' "$i" > "$dir/new.py"
        GIT_AUTHOR_DATE="$stamp +0000" GIT_COMMITTER_DATE="$stamp +0000" \
            git -C "$dir" add -A >/dev/null 2>&1
        GIT_AUTHOR_DATE="$stamp +0000" GIT_COMMITTER_DATE="$stamp +0000" \
            git -C "$dir" commit -q -m "new $i" >/dev/null 2>&1
    done
}

# RECENT repo: HEAD ~30 days before today, so the OLD commits (400 days before HEAD) still land inside
# plain churn's wall-clock 18-month window — that is what makes arm 3's churn-vs-churn-decay contrast a
# contrast and not a comparison against a degraded uniform prior.
NOW="$( date +%s )"
RECENT_BASE="$(( NOW - 430 * 86400 ))"
OLD_BASE="$(( NOW - (430 + 5 * 365) * 86400 ))"
mkrepo "$WORK/recent" "$RECENT_BASE"
mkrepo "$WORK/shifted" "$OLD_BASE"

# PRESENCE GUARD (CONTRIBUTING §2, "green while inert"): the arms below are meaningless if the fixture
# has no history or ripwire indexed no symbols from it. Assert both before asserting anything about them.
[ "$( git -C "$WORK/recent" rev-list --count HEAD 2>/dev/null )" = 8 ] \
    && ok "fixture guard: recent repo has 8 commits" \
    || no "fixture guard: recent repo does not have 8 commits (got $( git -C "$WORK/recent" rev-list --count HEAD 2>/dev/null ))"

names(){ printf '%s' "$1" | grep -oE '<s [^>]*n="[^"]*"' | grep -oE 'n="[^"]*"' | sed 's/n="//;s/"//' | tr '\n' ' '; }

# ── arm 1: accepted, non-empty, deterministic ────────────────────────────────────────────────────────
A="$( "$BIN" "$WORK/recent" --rank-by=churn-decay --no-cache 2>"$WORK/e1" )"; ec=$?
B="$( "$BIN" "$WORK/recent" --rank-by=churn-decay --no-cache 2>/dev/null )"
if [ "$ec" = 0 ] && [ -n "$A" ] && printf '%s' "$A" | grep -q '<s '; then
    ok "arm 1a: --rank-by=churn-decay accepted, non-empty (exit 0)"
else
    no "arm 1a: --rank-by=churn-decay rejected or empty (exit=$ec)"; sed 's/^/    /' "$WORK/e1" | head -3
fi
# NON-VACUITY: two empty outputs are byte-identical to each other, so 0 B must FAIL this arm rather than
# pass it (the same trap regression.sh's determinism row guards against).
if [ -z "$A" ]; then
    no "arm 1b: EMPTY output — 0 B is vacuously identical, not deterministic"
elif [ "$A" = "$B" ]; then
    ok "arm 1b: two runs byte-identical (determinism, $( printf '%s' "$A" | wc -c | tr -d ' ' ) B)"
else
    no "arm 1b: two runs DIFFER — churn-decay is not deterministic"
fi
if command -v xmllint >/dev/null 2>&1; then
    if printf '%s' "$A" | xmllint --noout - 2>"$WORK/xl"; then ok "arm 1c: output is well-formed XML"; else { no "arm 1c: xmllint rejected the output"; sed 's/^/    /' "$WORK/xl" | head -3; }; fi
else
    no "arm 1c: xmllint missing — cannot verify well-formedness (install libxml2-utils)"
fi

# ── arm 2: the map discloses the decay it applied ────────────────────────────────────────────────────
printf '%s' "$A" | grep -q 'rank_by="churn-decay"' \
    && ok "arm 2a: header stamps rank_by=\"churn-decay\"" \
    || no "arm 2a: header does not stamp rank_by=\"churn-decay\""
printf '%s' "$A" | grep -oE 'window="[^"]*"' | grep -q 'half-life=90d' \
    && ok "arm 2b: window= discloses the 90-day half-life" \
    || no "arm 2b: window= does not disclose the half-life (got: $( printf '%s' "$A" | grep -oE 'window="[^"]*"' | head -1 ))"
printf '%s' "$A" | grep -q '0.5\^(age' \
    && ok "arm 2c: legend spells the decay formula" \
    || no "arm 2c: legend does not spell the decay formula"
printf '%s' "$A" | grep -qi 'HEAD commit timestamp' \
    && ok "arm 2d: legend names the HEAD-commit-timestamp anchor" \
    || no "arm 2d: legend does not name the HEAD-commit-timestamp anchor"

# ── arm 3: SEMANTIC — decay flips the order raw churn produces ───────────────────────────────────────
C="$( "$BIN" "$WORK/recent" --rank-by=churn --no-cache 2>/dev/null )"
churn_first="$( names "$C" | awk '{print $1}' )"
decay_first="$( names "$A" | awk '{print $1}' )"
[ "$churn_first" = "old_one" ] \
    && ok "arm 3a: plain --rank-by=churn leads with old_one (6 commits beats 2)" \
    || no "arm 3a: plain churn should lead with old_one, got '$churn_first' — fixture or churn mining is off"
[ "$decay_first" = "new_one" ] \
    && ok "arm 3b: --rank-by=churn-decay leads with new_one (recent beats frequent)" \
    || no "arm 3b: churn-decay should lead with new_one, got '$decay_first' — decay is not being applied"

# ── arm 4: --since composes with the new value (no modifier refusal) ─────────────────────────────────
"$BIN" "$WORK/recent" --rank-by=churn-decay --since=HEAD~2 --no-cache >/dev/null 2>"$WORK/e4"; ec=$?
if [ "$ec" = 0 ] && ! grep -q 'scopes' "$WORK/e4"; then
    ok "arm 4: --since composes with --rank-by=churn-decay (no modifier refusal)"
else
    no "arm 4: --since was refused alongside --rank-by=churn-decay (exit=$ec)"; sed 's/^/    /' "$WORK/e4" | head -3
fi

# ── arm 5: MUTATION — the anchor is HEAD's timestamp, not the wall clock ─────────────────────────────
# Identical relative spacing, absolute dates five years apart. Same order ⇒ the wall clock was never read.
S="$( "$BIN" "$WORK/shifted" --rank-by=churn-decay --no-cache 2>/dev/null )"
ord_recent="$( names "$A" )"
ord_shifted="$( names "$S" )"
if [ -n "$ord_recent" ] && [ "$ord_recent" = "$ord_shifted" ]; then
    ok "arm 5: a 5-years-shifted copy ranks identically ($ord_recent) — the anchor is HEAD's commit timestamp, not the wall clock"
else
    no "arm 5: shifted copy ranks DIFFERENTLY (recent: '$ord_recent' vs shifted: '$ord_shifted') — the decay is reading the system clock"
fi

# ── arm 6: H2H-Graft F3 — the file-level answer comes FIRST ──────────────────────────────────────────
# "What changed recently in <dir>?" is a question about FILES; the verb answered it with a 200-symbol map
# (35 KB on rocksdb) and no file-level row at all. <recent> lists the n= files with the largest decayed weight
# — new.py (2 commits at HEAD's day, weight ≈ 2.0) before old.py (6 commits 400 days back, ≈ 0.28) — with
# age_d= on HEAD's clock and the weight the ranker used, and it precedes every <f> group.
R6="$( perl -e 'alarm 20; exec @ARGV' "$BIN" "$WORK/recent" --rank-by=churn-decay --no-cache 2>/dev/null )"
printf '%s' "$R6" | grep -q '<recent n="2" of="2" ' \
 \
        && ok "arm 6a: <recent n=\"2\" of=\"2\" …> is emitted" \
        || no "arm 6a: no <recent n=\"2\" of=\"2\" …> element"
r6_first="$( printf '%s' "$R6" | grep -oE '<rc p="[^"]*"' | head -1 )"
[ "$r6_first" = '<rc p="new.py"' ] && ok "arm 6b: the file with the newest decayed weight leads (new.py)" \
                                    || no "arm 6b: first <rc> is '$r6_first', expected new.py"
printf '%s' "$R6" | grep -qE '<rc p="new.py" age_d="0" w="[0-9.]+"/>' && printf '%s' "$R6" | grep -qE '<rc p="old.py" age_d="(399|400)" w="[0-9.]+"/>' \
    && ok "arm 6c: age_d= is days since the file's newest commit at HEAD's clock (new 0, old ~400)" \
    || no "arm 6c: age_d= wrong: $( printf '%s' "$R6" | grep -oE '<rc [^>]*>' | tr '\n' ' ' )"
r6_recent_pos="$( printf '%s' "$R6" | grep -bo '<recent ' | head -1 | cut -d: -f1 )"
r6_f_pos="$( printf '%s' "$R6" | grep -bo '<f p=' | head -1 | cut -d: -f1 )"
[ -n "$r6_recent_pos" ] && [ -n "$r6_f_pos" ] && [ "$r6_recent_pos" -lt "$r6_f_pos" ] \
    && ok "arm 6d: <recent> precedes the first <f> group (the answer before the map)" \
    || no "arm 6d: <recent> at byte '$r6_recent_pos' is not before the first <f> at '$r6_f_pos'"
printf '%s' "$R6" | grep -q 'recent: the file-level answer' && ok "arm 6e: the legend defines recent/rc/age_d/w" \
                                                            || no "arm 6e: legend does not define the recent element"
# negative: plain churn and pagerank carry NO <recent> (byte-free elsewhere)
R6p="$( perl -e 'alarm 20; exec @ARGV' "$BIN" "$WORK/recent" --rank-by=churn --no-cache 2>/dev/null )"
printf '%s' "$R6p" | grep -q '<recent ' && no "arm 6f: --rank-by=churn must not emit <recent> (churn-decay only)" \
                                        || ok "arm 6f: plain churn carries no <recent>"

# ── arm 7: merge_bombs_skipped= — the cut the miner makes is DISCLOSED on the block it shapes ────────────
# The decayed walk skips any commit touching more than 100 files (the merge-bomb rule) and, until this arm,
# counted NOTHING about it: a <recent> block could omit the very commit a question was about (a held-out gold
# commit with 71 src files was invisible) and nothing in the output said a commit had been dropped. The
# fixture: three ordinary commits on small.py, then ONE commit adding 101 files under bulk/. The block must
# say merge_bombs_skipped="1", the bulk-only files must be ABSENT from its rows (that is what "skipped" means),
# the plain fixture must say "0" (absence is never ambiguous), and both legends must define the attribute.
# RED against the pre-change binary: no merge_bombs_skipped= anywhere.
BOMB="$WORK/bomb"; mkdir -p "$BOMB/bulk"
git -C "$BOMB" init -q 2>/dev/null
git -C "$BOMB" config user.email rw@example.invalid
git -C "$BOMB" config user.name  ripwire-gate
for i in 1 2 3; do
    stamp="$(( RECENT_BASE + i * 86400 ))"
    printf 'def small_one():\n    return %d\n' "$i" > "$BOMB/small.py"
    GIT_AUTHOR_DATE="$stamp +0000" GIT_COMMITTER_DATE="$stamp +0000" git -C "$BOMB" add -A >/dev/null 2>&1
    GIT_AUTHOR_DATE="$stamp +0000" GIT_COMMITTER_DATE="$stamp +0000" git -C "$BOMB" commit -q -m "small $i" >/dev/null 2>&1
done
i=0
while [ "$i" -le 100 ]; do
    printf 'def bulk_%03d():\n    return %d\n' "$i" "$i" > "$BOMB/bulk/b$( printf '%03d' "$i" ).py"
    i=$(( i + 1 ))
done
stamp="$(( RECENT_BASE + 4 * 86400 ))"
GIT_AUTHOR_DATE="$stamp +0000" GIT_COMMITTER_DATE="$stamp +0000" git -C "$BOMB" add -A >/dev/null 2>&1
GIT_AUTHOR_DATE="$stamp +0000" GIT_COMMITTER_DATE="$stamp +0000" git -C "$BOMB" commit -q -m "bulk sweep: 101 files" >/dev/null 2>&1
# presence guards: the bomb commit really touches 101 files, and it is HEAD
bombfiles="$( git -C "$BOMB" show --name-only --format= HEAD 2>/dev/null | grep -c . )"
[ "$bombfiles" = 101 ] && ok "arm 7 guard: the bomb commit touches 101 files (> the 100-file rule)" \
                       || no "arm 7 guard: the bomb commit touches $bombfiles files, not 101 — the arm below would be vacuous"
R7="$( perl -e 'alarm 30; exec @ARGV' "$BIN" "$BOMB" --rank-by=churn-decay --no-cache 2>/dev/null )"
r7_recent="$( printf '%s' "$R7" | grep -oE '<recent [^>]*>' | head -1 )"
[ -n "$r7_recent" ] && ok "arm 7 guard: the bomb fixture emits a <recent> block ($r7_recent)" \
                    || no "arm 7 guard: no <recent> block on the bomb fixture — nothing below can be asserted"
printf '%s' "$r7_recent" | grep -q 'merge_bombs_skipped="1"' \
    && ok "arm 7a: <recent> discloses merge_bombs_skipped=\"1\" — the 101-file commit was skipped and SAYS so" \
    || no "arm 7a: <recent> does not carry merge_bombs_skipped=\"1\" (got: $r7_recent)"
printf '%s' "$R7" | grep -q '<rc p="bulk/b000.py"' \
    && no "arm 7b: bulk/b000.py is a <rc> row — the merge-bomb rule did not skip the commit, so the counter measures nothing" \
    || ok "arm 7b: the bulk-only files are absent from the rows (the skipped commit contributed nothing)"
printf '%s' "$r7_recent" | grep -q 'of="1"' \
    && ok "arm 7c: of=\"1\" — only small.py was touched by a COUNTED commit" \
    || no "arm 7c: of= is not 1 (got: $r7_recent)"
printf '%s' "$R6" | grep -oE '<recent [^>]*>' | head -1 | grep -q 'merge_bombs_skipped="0"' \
    && ok "arm 7d: a window with no merge bomb says merge_bombs_skipped=\"0\" (always emitted; absence is never ambiguous)" \
    || no "arm 7d: the plain fixture's <recent> lacks merge_bombs_skipped=\"0\" (got: $( printf '%s' "$R6" | grep -oE '<recent [^>]*>' | head -1 ))"
printf '%s' "$R7" | grep -q 'merge_bombs_skipped= ' && printf '%s' "$R7" | grep -q '100 files' \
    && ok "arm 7e: the full legend defines merge_bombs_skipped= and states the 100-file threshold" \
    || no "arm 7e: the full legend does not define merge_bombs_skipped= with its threshold"
R7c="$( perl -e 'alarm 30; exec @ARGV' "$BIN" "$BOMB" --rank-by=churn-decay --no-cache --legend=compact 2>/dev/null )"
printf '%s' "$R7c" | grep -q 'merge_bombs_skipped=N' && printf '%s' "$R7c" | grep -q '100 files' \
    && ok "arm 7f: the compact legend defines merge_bombs_skipped=N with the 100-file threshold" \
    || no "arm 7f: the compact legend does not define merge_bombs_skipped= (legend: $( printf '%s' "$R7c" | grep -oE '<!-- ripwire map[^>]*-->' | head -c 300 ))"
if command -v xmllint >/dev/null 2>&1; then
    printf '%s' "$R7" | xmllint --noout - 2>/dev/null \
        && ok "arm 7g: the bomb fixture's output is well-formed XML" \
        || no "arm 7g: xmllint rejected the bomb fixture's output"
fi
# 7h: a window whose EVERY commit is a merge bomb (a shallow clone of a large tree is exactly this shape — llvm-project at
# depth 1 is one 183,835-file commit) must still print the block, with zero rows and the count: an ABSENT block reads as
# "no history mined", which is a different fact, and the disclosure arm 7a exists for would vanish on the one run that
# needs it most. Byte-free elsewhere is kept: a corpus with no git at all still prints no block (the goldens).
ONLYBOMB="$WORK/onlybomb"; mkdir -p "$ONLYBOMB/bulk"
git -C "$ONLYBOMB" init -q 2>/dev/null
git -C "$ONLYBOMB" config user.email rw@example.invalid
git -C "$ONLYBOMB" config user.name  ripwire-gate
i=0
while [ "$i" -le 100 ]; do
    printf 'def bulk_%03d():\n    return %d\n' "$i" "$i" > "$ONLYBOMB/bulk/b$( printf '%03d' "$i" ).py"
    i=$(( i + 1 ))
done
stamp="$(( RECENT_BASE + 5 * 86400 ))"
GIT_AUTHOR_DATE="$stamp +0000" GIT_COMMITTER_DATE="$stamp +0000" git -C "$ONLYBOMB" add -A >/dev/null 2>&1
GIT_AUTHOR_DATE="$stamp +0000" GIT_COMMITTER_DATE="$stamp +0000" git -C "$ONLYBOMB" commit -q -m "one bulk commit" >/dev/null 2>&1
[ "$( git -C "$ONLYBOMB" rev-list --count HEAD 2>/dev/null )" = 1 ] && ok "arm 7h guard: the only-bomb fixture has exactly one commit" \
                                                                    || no "arm 7h guard: the only-bomb fixture does not have exactly one commit"
R7h="$( perl -e 'alarm 30; exec @ARGV' "$BIN" "$ONLYBOMB" --rank-by=churn-decay --no-cache 2>/dev/null )"
printf '%s' "$R7h" | grep -q '<recent n="0" of="0" merge_bombs_skipped="1"></recent>' \
    && ok "arm 7h: a window whose only commit was skipped still prints <recent n=\"0\" of=\"0\" merge_bombs_skipped=\"1\"> — zero rows, and the reason" \
    || no "arm 7h: the only-bomb window prints no <recent> block (got: '$( printf '%s' "$R7h" | grep -oE '<recent [^>]*>' | head -1 )') — the disclosure vanished with the rows"

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit $fail
