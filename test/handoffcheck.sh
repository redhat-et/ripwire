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
# M4(b) (capture-audit 2026-09-04): a runner script whose basename STEM matches the test file, so
# testmap.h's runAttr has real evidence to derive `run="bash test/test_engine.sh"` from. Without it the
# run= arm below is vacuous — "absent means not derivable" would be the honest answer for every emitter.
cat > "$WORK/test/test_engine.sh" <<'EOF'
#!/usr/bin/env bash
exec ./test_engine
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
# M11 (2026-09-04): the byte comparison was a proxy for "heuristic rows were withheld", and the budgeted root
# now carries est_tokens=/budget_tokens=/over_ceiling= (~60 B) — on a fixture with ONE small heuristic row the
# budgeted packet can be a few bytes LARGER than the unbounded one while having withheld everything it may.
# Assert the property itself: the budgeted packet withheld rows (withheld="1", withheld_rows>=1) and prints
# fewer <heuristic n=> rows than the unbounded run.
N_NOBUDGET="$( grep -oE '<heuristic n="[0-9]+"' "$TMP/nobudget.xml" | tr -dc '0-9' )"
N_BUDGET="$(   grep -oE '<heuristic n="[0-9]+"' "$TMP/budget.xml"   | tr -dc '0-9' )"
W_BUDGET="$(   grep -oE '<handoff [^>]*>' "$TMP/budget.xml" | grep -oE ' withheld="[01]"' | tr -dc '0-9' )"
WR_BUDGET="$(  grep -oE '<handoff [^>]*>' "$TMP/budget.xml" | grep -oE ' withheld_rows="[0-9]+"' | tr -dc '0-9' )"
if [ "$rc_budget" -eq 0 ] && [ "${N_BUDGET:-0}" -lt "${N_NOBUDGET:-0}" ] && [ "$W_BUDGET" = "1" ] && [ "${WR_BUDGET:-0}" -ge 1 ]; then
    ok "--token-budget=400 withheld heuristic rows: <heuristic n=$N_BUDGET> vs unbounded n=$N_NOBUDGET, withheld=\"1\" withheld_rows=\"$WR_BUDGET\" ($SZ_BUDGET B vs $SZ_NOBUDGET B)"
else
    no "--token-budget=400 did not withhold rows (rc=$rc_budget, heuristic n=$N_BUDGET vs unbounded $N_NOBUDGET, withheld=$W_BUDGET withheld_rows=$WR_BUDGET; $SZ_BUDGET B vs $SZ_NOBUDGET B): $( cat "$TMP/budget.err" )"
fi
DISCLOSED="$( cat "$TMP/budget.xml" "$TMP/budget.err" 2>/dev/null )"
{ printf '%s' "$DISCLOSED" | grep -qi 'budget' && printf '%s' "$DISCLOSED" | grep -qiE 'trunc|withheld|omit'; } \
    && ok "the header discloses the budget and a truncation note" \
    || no "no budget/truncation disclosure found in --token-budget=400 output"

# ═══════════════════════════════════════════════════════════════════════════════════════════════════════
# M4 (capture-audit 2026-09-04, lens 2 M5 / lens 4 / lens 0) — THE THREE GAPS IN THE PACKET
#
# (a) NOTES DROPPED WITH withheld="0". In the capture's sandbox a non-dangling note sat on a symbol in
#     handoff's OWN <verified> set and no <note> row appeared, while the header said nothing had been
#     withheld. Root cause: the match tested `n.target.rfind( ing.files[f], 0 ) == 0` — a note target is
#     stored ROOT-RELATIVE (notes.h::normalizeNoteTarget) and ing.files[] is CRAWL-ROOT-PREFIXED, so the
#     prefix test could only ever match by accident. The rule this gate asserts:
#         notes( non-dangling, target ∈ changed ∪ blast ) ⊆ handoff.<note> rows ∪ what the header accounts for
#     — i.e. a matching note is either IN the packet or COUNTED as dropped. Never silently absent.
# (b) NO run= ON <t> ROWS. --situ / --test-gate / --pr-context all print run="bash test/…" for the SAME
#     test file (testmap.h::runAttr is the ONE spelling); handoff, whose whole audience is an agent about
#     to resume, made the recipient re-derive it.
# (c) branch="HEAD" ON A DETACHED HEAD. That is git's answer, not a branch; the packet's "disk truth" half
#     read as if a branch named HEAD existed. detached="1" says what the state actually is (the sha is
#     already on at=).
#
# RED-FIRST: every arm below fails on the pre-fix binary.
# ═══════════════════════════════════════════════════════════════════════════════════════════════════════
echo
echo "── M4(a) — a note on a changed/blast target is a row, or it is accounted for ────────────────────"
NOTEREPO="$TMP/noterepo"
cp -R "$WORK" "$NOTEREPO"
# a note on a symbol in the CHANGED file, and one on a symbol in the BLAST radius (scheduler.cpp calls
# engineRun, so it is a dependent, not a changed, file) — both non-dangling by construction.
# engineRun is DECLARED in three files, so the bare name is ambiguous and H1 refuses it (notecanoncheck) —
# the file-qualified spelling is what picks the definition, and both notes are then canonicalised to the id
# the note index actually keys on.
"$BIN" "$NOTEREPO" --no-cache --note-add="src/engine.cpp:engineRun: the +2 is deliberate, do not revert" >/dev/null 2>&1
"$BIN" "$NOTEREPO" --no-cache --note-add="schedRun: this caller assumes engineRun is pure" >/dev/null 2>&1
NOTES_XML="$( "$BIN" "$NOTEREPO" --no-cache --notes 2>/dev/null )"
DANGLING_BEFORE="$( printf '%s' "$NOTES_XML" | grep -c 'dangling="1"' )"
TARGETS_BEFORE="$( printf '%s' "$NOTES_XML" | grep -o '<target ' | wc -l | tr -d ' ' )"
{ [ "$DANGLING_BEFORE" = "0" ] && [ "$TARGETS_BEFORE" = "2" ]; } \
    && ok "M4(a): both fixture notes were written and are non-dangling (the arm is not measuring dead notes)" \
    || no "M4(a): expected 2 non-dangling fixture notes, got targets=$TARGETS_BEFORE dangling=$DANGLING_BEFORE — the arms below would be vacuous"
"$BIN" "$NOTEREPO" --no-cache --handoff >"$TMP/note.xml" 2>/dev/null
NOTE_ROWS="$( grep -o '<note ' "$TMP/note.xml" | wc -l | tr -d ' ' )"
[ "$NOTE_ROWS" -ge 1 ] \
    && ok "M4(a): the packet carries the note on the CHANGED file's symbol ($NOTE_ROWS <note> row(s))" \
    || no "M4(a): a non-dangling note on handoff's own verified symbol produced NO <note> row"
grep -q 'do not revert' "$TMP/note.xml" \
    && ok "M4(a): it is the right note (the changed symbol's text is in the packet)" \
    || no "M4(a): the changed symbol's note text is absent from the packet"
grep -q 'assumes engineRun is pure' "$TMP/note.xml" \
    && ok "M4(a): the BLAST-radius symbol's note is in the packet too (changed ∪ blast, not changed alone)" \
    || no "M4(a): a note on a blast-radius symbol was dropped"
# the ACCOUNTING half: <heuristic> discloses how many candidate rows there were and whether a cap fired,
# so a dropped note is never invisible.
HROOT="$( grep -oE '<heuristic [^>]*>' "$TMP/note.xml" | head -1 )"
{ printf '%s' "$HROOT" | grep -q 'candidates="' && printf '%s' "$HROOT" | grep -q 'capped="'; } \
    && ok "M4(a): <heuristic> accounts for its own row population ($HROOT)" \
    || no "M4(a): <heuristic> carries no candidates=/capped= accounting: [$HROOT]"
grep -q 'candidates=' "$TMP/note.xml" && grep -q 'capped=' "$TMP/note.xml" \
    && ok "M4(a): the legend defines them (legendcoveragecheck's rule)" \
    || no "M4(a): candidates=/capped= are emitted with no legend definition"

echo
echo "── M4(b) — <t> rows carry run=, the same spelling situ/test-gate/pr-context print ──────────────"
run --handoff >"$TMP/hb.xml" 2>/dev/null
TROW="$( grep -oE '<t p="[^>]*/>' "$TMP/hb.xml" | head -1 )"
[ -n "$TROW" ] && ok "M4(b): the packet has a <t> row to check ($TROW)" \
               || no "M4(b): no <t> row in the packet — the arm would be vacuous"
# the sibling that already prints it, on the SAME fixture and the SAME file: if --test-gate can derive a
# runner here, handoff has no excuse not to.
run --test-gate >"$TMP/tg.xml" 2>/dev/null
SIB_RUN="$( grep -oE '<t [^>]*run="[^"]*"' "$TMP/tg.xml" | head -1 | sed -E 's/.*run="([^"]*)".*/\1/' )"
if [ -n "$SIB_RUN" ]; then
    ok "M4(b): the sibling --test-gate derives a runner on this fixture (run=\"$SIB_RUN\")"
    printf '%s' "$TROW" | grep -q 'run="' \
        && ok "M4(b): --handoff's <t> row carries run= too" \
        || no "M4(b): --handoff's <t> row carries no run= while --test-gate prints run=\"$SIB_RUN\" for it"
else
    ok "M4(b): no runner derivable on this fixture — nothing to compare (absent means not derivable)"
fi

echo
echo "── M4(c) — a DETACHED head says so, instead of naming a branch called HEAD ─────────────────────"
DET="$TMP/detached"
cp -R "$CLEAN" "$DET"
( cd "$DET" && git checkout -q --detach HEAD )
"$BIN" "$DET" --no-cache --handoff >"$TMP/det.xml" 2>/dev/null
DROOT="$( grep -oE '<handoff [^>]*>' "$TMP/det.xml" | head -1 )"
printf '%s' "$DROOT" | grep -q 'detached="1"' \
    && ok "M4(c): a detached head is disclosed as detached=\"1\"" \
    || no "M4(c): a detached head reports branch=\"HEAD\" with no detached= marker: [$DROOT]"
printf '%s' "$DROOT" | grep -qE 'at="[0-9a-f]{7}' \
    && ok "M4(c): and the sha is on the root (at=), so the state is fully named" \
    || no "M4(c): no sha on the detached-head packet: [$DROOT]"
# the control: an ATTACHED head must NOT carry the marker (absent means none).
grep -oE '<handoff [^>]*>' "$TMP/clean.xml" | head -1 | grep -q 'detached=' \
    && no "M4(c): an attached head carries detached= — absent means none" \
    || ok "M4(c): an attached head carries no detached= (absent means none)"
if command -v xmllint >/dev/null 2>&1; then
    xmllint --noout "$TMP/note.xml" 2>/dev/null && xmllint --noout "$TMP/det.xml" 2>/dev/null \
        && ok "M4: the note-carrying and detached packets are both well-formed XML" \
        || no "M4: a packet is not well-formed XML"
fi

[ "$fail" = 0 ] && echo 'ALL PASS' || echo 'FAILURES ABOVE'
exit "$fail"
