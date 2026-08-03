#!/usr/bin/env bash
# handoffcheck.sh — gate for `--handoff`, a deterministic, zero-LLM "continuation packet" for handing an
# interrupted coding session to the next AI agent. Frozen spec (do not redesign it here — this gate only
# measures it):
#
#   `ripwire <dir> --handoff` emits ONE minified XML document (G4: no inter-tag whitespace, xmllint-clean)
#   with two hard-labeled sections:
#     <verified>  — disk truth only: git branch/sha/dirty marker, changed files (vs HEAD) with their changed
#                   symbols, transitive blast radius count, tests-to-run rows (the same analysis --situ
#                   section 2 already uses).
#     <heuristic> — clearly labeled NON-verified suggestions: co-change partner files NOT in the diff
#                   ("usually edited together"), committed .ripwire_notes rows matching changed symbols, and
#                   top plan/design docs ranked by --recall using branch name + last commit subject as the
#                   query (disk-derived, deterministic — no network, no model).
#   An empty diff is NOT an error: the packet still carries branch/sha + notes + recall docs, exit 0.
#   `--handoff` composes with `--token-budget=N`: it respects the budget and discloses truncation in the
#   header, the same vocabulary --for/--recall/--pack-task already use (budget=/withheld/truncated).
#
# THIS GATE IS WRITTEN BEFORE THE VERB EXISTS (TDD, red-first). It is expected to FAIL against the current
# binary — `--handoff` is not a recognized flag yet. It must go GREEN only once the verb is implemented to
# this spec; do not weaken any assertion below to make it pass early.
#
# Usage:  bash test/handoffcheck.sh   |   RIPWIRE_BIN=asan/ripwire bash test/handoffcheck.sh
#         bash test/handoffcheck.sh <path-to-binary>   (positional override, same convention as
#         notescheck.sh / situdiffcheck.sh)

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"          # make BIN absolute BEFORE we cd away
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
command -v git >/dev/null 2>&1 || { echo "git required"; exit 2; }

TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
echo "handoffcheck: BIN=$BIN"

# ── slice out the <verified>...</verified> region of a (minified, single-line) XML document, so a
#    filename check against it cannot be satisfied by a match that actually lives in <heuristic> instead.
verified_slice(){ sed -n 's/.*\(<verified.*\)<heuristic.*/\1/p' "$1"; }

# ═══════════════════════════════════════════════════════════════════════════════════════════════════════
# fixture 1 — a real git repo (git init, commit, then an edit) so --handoff has real disk truth to report.
# engine.cpp defines engineRun; scheduler.cpp calls it, so an edit to engine.cpp has a non-empty blast
# radius and a docs/ plan file gives the heuristic --recall lens something to rank.
# ═══════════════════════════════════════════════════════════════════════════════════════════════════════
WORK="$TMP/repo"
mkdir -p "$WORK/src" "$WORK/test" "$WORK/docs"
cat > "$WORK/src/engine.cpp" <<'EOF'
int engineRun( int x ) { return x + 1; }
EOF
cat > "$WORK/src/scheduler.cpp" <<'EOF'
int engineRun( int x );
int schedRun( int x ) { return engineRun( x ) + 1; }
EOF
cat > "$WORK/test/test_engine.cpp" <<'EOF'
int engineRun( int x );
int testEngine() { return engineRun( 1 ); }
EOF
cat > "$WORK/docs/engine_rework_notes.md" <<'EOF'
# PLAN: engine rework
Notes on reworking the engine/scheduler pipeline for the handoff.
EOF
( cd "$WORK" && git init -q \
    && git config user.email t@t && git config user.name t \
    && git add -A && git commit -qm "init: engine + scheduler + test + plan" >/dev/null 2>&1 \
    && git checkout -q -b work-engine-rework )
# the edit: unstaged, so the diff-vs-HEAD path (not just the index) must pick it up.
printf 'int engineRun( int x ) { return x + 2; }\n' > "$WORK/src/engine.cpp"

run(){ "$BIN" "$WORK" --no-cache "$@"; }

# ── (i) exit-0, both section markers present, verified section names the edited file ─────────────────────
run --handoff >"$TMP/h1.xml" 2>"$TMP/h1.err"; rc1=$?
[ "$rc1" -eq 0 ] && ok "--handoff exits 0 on a git fixture with an unstaged edit" \
    || { no "--handoff exit=$rc1 (expected 0): $( cat "$TMP/h1.err" )"; }
grep -q '<verified' "$TMP/h1.xml" && ok "output contains a <verified> section marker" \
    || no "no <verified> section marker in output"
grep -q '<heuristic' "$TMP/h1.xml" && ok "output contains a <heuristic> section marker" \
    || no "no <heuristic> section marker in output"
VSLICE="$( verified_slice "$TMP/h1.xml" )"
{ [ -n "$VSLICE" ] && printf '%s' "$VSLICE" | grep -q 'engine\.cpp'; } \
    && ok "the <verified> section names the edited file (engine.cpp)" \
    || no "the <verified> section does not name engine.cpp (slice: ${VSLICE:0:200})"

# ── (ii) determinism: two runs byte-identical (guarded — an rc!=0 pair is a FAIL, not a vacuous PASS;
#    two empty/error outputs would otherwise "match" for the wrong reason, per regression.sh's own
#    non-vacuity discipline). ───────────────────────────────────────────────────────────────────────────
run --handoff >"$TMP/h2.xml" 2>"$TMP/h2.err"; rc2=$?
if [ "$rc1" -eq 0 ] && [ "$rc2" -eq 0 ] && [ -s "$TMP/h1.xml" ] && cmp -s "$TMP/h1.xml" "$TMP/h2.xml"; then
    ok "determinism (two byte-identical, non-empty, exit-0 runs)"
else
    no "determinism failed (rc1=$rc1 rc2=$rc2, or empty, or diverging bytes)"
fi

# ── (iii) xmllint --noout clean (skip gracefully if xmllint is absent, like mentioncheck.sh does) ─────────
if command -v xmllint >/dev/null 2>&1; then
    if [ -s "$TMP/h1.xml" ] && xmllint --noout "$TMP/h1.xml" 2>"$TMP/xmllint.err"; then
        ok "--handoff output is xmllint-clean (G4)"
    else
        no "--handoff output is not well-formed XML: $( cat "$TMP/xmllint.err" 2>/dev/null )"
    fi
else
    ok "xmllint not present — skipped (G4 covered elsewhere)"
fi

# ── (iv) additive (G5): the flagless map of the SAME fixture is byte-identical whether or not --handoff
#    was ever invoked against it — --handoff must be purely additive, no side effect on the core map. ────
run >"$TMP/map_before.xml" 2>/dev/null
run --handoff >/dev/null 2>&1   # exercise the verb (whatever it does today) between the two map snapshots
run --handoff >/dev/null 2>&1
run >"$TMP/map_after.xml" 2>/dev/null
if [ -s "$TMP/map_before.xml" ] && cmp -s "$TMP/map_before.xml" "$TMP/map_after.xml"; then
    ok "flagless map is byte-identical whether or not --handoff was ever run (G5 additive)"
else
    no "flagless map changed after --handoff was invoked (--handoff has a side effect)"
fi

# ═══════════════════════════════════════════════════════════════════════════════════════════════════════
# fixture 2 — a second, CLEAN repo (committed, no edits after) for the empty-diff contract.
# ═══════════════════════════════════════════════════════════════════════════════════════════════════════
CLEAN="$TMP/clean_repo"
mkdir -p "$CLEAN/src" "$CLEAN/docs"
cat > "$CLEAN/src/main.c" <<'EOF'
int main(void) { return 0; }
EOF
cat > "$CLEAN/docs/design_notes.md" <<'EOF'
# DESIGN: notes
Nothing pending.
EOF
( cd "$CLEAN" && git init -q \
    && git config user.email t@t && git config user.name t \
    && git add -A && git commit -qm "clean init" >/dev/null 2>&1 )
HEAD_SHA="$( cd "$CLEAN" && git rev-parse HEAD )"
HEAD_BRANCH="$( cd "$CLEAN" && git rev-parse --abbrev-ref HEAD )"

# ── (v) empty-diff fixture: exit 0, packet still carries branch/sha and a heuristic section ────────────
"$BIN" "$CLEAN" --no-cache --handoff >"$TMP/clean.xml" 2>"$TMP/clean.err"; rc_clean=$?
[ "$rc_clean" -eq 0 ] && ok "--handoff exits 0 on a clean (empty-diff) tree" \
    || no "--handoff on a clean tree exit=$rc_clean (expected 0, empty diff is NOT an error): $( cat "$TMP/clean.err" )"
{ grep -qF "$HEAD_SHA" "$TMP/clean.xml" 2>/dev/null || grep -qF "${HEAD_SHA:0:7}" "$TMP/clean.xml" 2>/dev/null; } \
    && ok "clean-tree packet carries the HEAD sha" \
    || no "clean-tree packet is missing the HEAD sha ($HEAD_SHA / short ${HEAD_SHA:0:7})"
grep -qF "$HEAD_BRANCH" "$TMP/clean.xml" 2>/dev/null \
    && ok "clean-tree packet carries the branch name ($HEAD_BRANCH)" \
    || no "clean-tree packet is missing the branch name ($HEAD_BRANCH)"
grep -q '<heuristic' "$TMP/clean.xml" \
    && ok "clean-tree packet still contains a <heuristic> section" \
    || no "clean-tree packet is missing the <heuristic> section"

# ── (vi) --token-budget=400 composes: smaller output than unbounded, header discloses budget/truncation ──
run --handoff --no-cache >"$TMP/nobudget.xml" 2>/dev/null
run --handoff --token-budget=400 --no-cache >"$TMP/budget.xml" 2>"$TMP/budget.err"; rc_budget=$?
SZ_NOBUDGET="$( wc -c <"$TMP/nobudget.xml" | tr -d ' ' )"
SZ_BUDGET="$( wc -c <"$TMP/budget.xml" | tr -d ' ' )"
if [ "$rc_budget" -eq 0 ] && [ "$SZ_BUDGET" -lt "$SZ_NOBUDGET" ]; then
    ok "--token-budget=400 output ($SZ_BUDGET B) is smaller than unbounded ($SZ_NOBUDGET B)"
else
    no "--token-budget=400 did not shrink the packet (budget=$SZ_BUDGET B rc=$rc_budget, unbounded=$SZ_NOBUDGET B): $( cat "$TMP/budget.err" )"
fi
DISCLOSED="$( cat "$TMP/budget.xml" "$TMP/budget.err" 2>/dev/null )"
{ printf '%s' "$DISCLOSED" | grep -qi 'budget' && printf '%s' "$DISCLOSED" | grep -qiE 'trunc|withheld|omit'; } \
    && ok "the header discloses the budget and a truncation note" \
    || no "no budget/truncation disclosure found in --token-budget=400 output"

[ "$fail" = 0 ] && echo 'ALL PASS' || echo 'FAILURES ABOVE'
exit "$fail"
