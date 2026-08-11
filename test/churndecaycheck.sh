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
#
# Determinism note: symbol ORDER is compared, never k= floats (CONTRIBUTING §3 — a sort has no tolerance
# band, a float does; this gate uses the sort).
#
# Usage:  RIPWIRE_BIN=build/ripwire bash test/churndecaycheck.sh   |   RIPWIRE_BIN=asan/ripwire bash …

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${RIPWIRE_BIN:-$ROOT/build/ripwire}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
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
    printf '%s' "$A" | xmllint --noout - 2>"$WORK/xl" && ok "arm 1c: output is well-formed XML" || { no "arm 1c: xmllint rejected the output"; sed 's/^/    /' "$WORK/xl" | head -3; }
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

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit $fail
