#!/usr/bin/env bash
# planlintcheck.sh — the gate for `--plan-lint=FILE` (P3.2, src/planlint.h): the house PLAN format's
# STRUCTURE check — task cards vs the status ledger, every card's terminal status glyph, a stale
# hourglass line, an undischarged "owed" mention. See src/planlint.h's own header for the full grammar
# and its stated limits; this gate proves the acceptance shape verbatim: on a mid-wave plan, a task card
# left with no terminal status line is reported — the exact catch a wave-closer used to make by eye.
#
# MODEL CORRECTION (post-review against the field-evidence source repo's own flagship plan, not just this
# repo's own PLAN_*.md corpus): the FIRST version of this lint read "status" as a glyph on the CARD's own
# body. Validated against the real 14-task authorship wave the whole feature was built for, that model
# gated 23/23 rows on a plan that was actually fully closed — every one of its cards ends its own body in
# prose ("**Effort M.**"), because the real house convention writes status into the §Status LEDGER, not
# onto the card. arm (9) below reproduces that shape directly: a card closed only in the ledger (T2), a
# card closed on its own body as before (T1, unbroken), and the genuine T5-unlaunched catch — a card the
# ledger never mentions at all — which is the acceptance case this verb exists for. It also reproduces a
# second real-corpus finding: a card described in its OWN body as splitting into lettered sub-tasks
# ("T7a", "T7b") is tracked under THOSE ids in the ledger, never the bare parent id — folded by digit,
# one-directional (src/planlint.h's ledgerMentionMatchesCard), so this does not silently mask a genuine
# orphan under a document shaped some other way.
#
# FIXTURE SPLIT, deliberately: test/planlintfix/wave.md and wave_ledger.md are COMMITTED,
# git-history-INDEPENDENT fixtures — every assertion on them (missing status, ledger-orphan, owed
# discharge, ledger-satisfied status, sub-id folding) is a pure function of the file's own bytes, so they
# stay correct forever regardless of how many more commits this repo's own history accumulates after this
# lane lands. The ONE check that genuinely needs a controlled commit history — an hourglass line's
# staleness — is instead built in a throwaway git repo THIS SCRIPT constructs (same shape as
# test/editchecknotecheck.sh's own temp repo), because asserting "more than 20 commits behind HEAD"
# against this repo's own ever-growing history would silently flip from PASS to FAIL as ordinary commits
# land after this one — measurement noise wearing a gate's clothes.
#
# Usage:  test/planlintcheck.sh
#         RIPWIRE_BIN=asan/ripwire test/planlintcheck.sh
# Exit:   0 = ALL PASS, non-zero = FAILURES

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
FIX="$ROOT/test/planlintfix/wave.md"
FIX2="$ROOT/test/planlintfix/wave_ledger.md"
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
command -v git >/dev/null 2>&1 || { echo "git required"; exit 2; }
[ -f "$FIX" ] || { echo "missing fixture $FIX"; exit 2; }
[ -f "$FIX2" ] || { echo "missing fixture $FIX2"; exit 2; }

echo "planlintcheck: BIN=$BIN  FIX=$FIX"

# ── (1) the acceptance shape, verbatim: the static, committed fixture ─────────────────────────────────
OUT="$( cd "$ROOT" && "$BIN" . --plan-lint=test/planlintfix/wave.md --no-cache )"
RC=$?

[ "$RC" = "2" ] && ok "(1) exit 2 — dialect=\"1\" and gating rows present" || no "(1) exit $RC, expected 2"

printf '%s' "$OUT" | grep -q 'dialect="1"' && ok "(1) dialect=\"1\" (the H3 task-card + §Status-ledger shape was recognized)" \
                                            || no "(1) dialect=\"1\" missing"
printf '%s' "$OUT" | grep -q 'cards="3"' && ok "(1) cards=\"3\" (T1, T2, T5)" || no "(1) cards=\"3\" missing"
printf '%s' "$OUT" | grep -q 'ledger="1"' && ok "(1) ledger=\"1\" (the §Status heading was found)" || no "(1) ledger=\"1\" missing"

# THE HEADLINE CATCH — a task card with no terminal status line, the exact failure a wave-closer used to
# find only by reading the whole plan by eye.
printf '%s' "$OUT" | grep -qE '<card id="T5"[^/]*status="missing"[^/]*gating="1"' \
    && ok "(1) T5 (the never-launched task) reports status=\"missing\" gating=\"1\" — THE ACCEPTANCE CASE" \
    || { no "(1) T5's missing-status row is absent or malformed"; printf '%s\n' "$OUT" | tail -c 1200; echo; }

printf '%s' "$OUT" | grep -qE '<card id="T1"[^/]*status="check"' \
    && ok "(1) T1 (terminal ✅) reports status=\"check\", not flagged" || no "(1) T1's status=\"check\" row missing"
printf '%s' "$OUT" | grep -qE '<card id="T1"[^/]*gating="1"' \
    && no "(1) T1 was marked gating=\"1\" despite a clean ✅ terminal line" \
    || ok "(1) T1 carries no gating=\"1\" — a finished card is silent"

printf '%s' "$OUT" | grep -qE '<card id="T2"[^/]*status="cross"' \
    && ok "(1) T2 (terminal ❌) reports status=\"cross\", not flagged" || no "(1) T2's status=\"cross\" row missing"
printf '%s' "$OUT" | grep -qE '<card id="T2"[^/]*gating="1"' \
    && no "(1) T2 was marked gating=\"1\" despite a clean ❌ terminal line" \
    || ok "(1) T2 carries no gating=\"1\" — an abandoned-but-recorded card is silent"

# the ledger cross-check: T9 is named in the ledger's own body with no matching "### T9" card
printf '%s' "$OUT" | grep -qE '<ledger-orphan id="T9"[^/]*gating="1"' \
    && ok "(1) ledger-orphan id=\"T9\" — the ledger names a task with no matching card" \
    || { no "(1) the T9 ledger-orphan row is missing"; printf '%s\n' "$OUT" | tail -c 1200; echo; }
printf '%s' "$OUT" | grep -q 'ledger-orphan id="T2"' \
    && no "(1) T2 was reported as a ledger-orphan, but a \"### T2\" card genuinely exists" \
    || ok "(1) T2's ledger mentions do NOT spuriously orphan (a real card silences them)"

# owed discharge: the T2 mention has a LATER ✅ in the same document (discharged, not gating); the T9
# mention is the LAST line of the file with nothing after it (undischarged, gating).
printf '%s' "$OUT" | grep -qE '<owed line="[0-9]+"><!\[CDATA\[- 2026-08-01 — T2 owed a re-check\]\]></owed>' \
    && ok "(1) the T2 owed mention carries NO gating=\"1\" — a later ✅ in the same doc discharges it" \
    || { no "(1) the discharged T2 owed row is missing or wrongly marked gating"; printf '%s\n' "$OUT" | tail -c 1200; echo; }
printf '%s' "$OUT" | grep -qE '<owed line="[0-9]+" gating="1"><!\[CDATA\[- 2026-08-03 — T9 owed a kickoff review' \
    && ok "(1) the T9 owed mention carries gating=\"1\" — nothing later in the doc discharges it" \
    || { no "(1) the undischarged T9 owed row is missing or wrongly marked clean"; printf '%s\n' "$OUT" | tail -c 1200; echo; }

printf '%s' "$OUT" | grep -q 'gating="3"' \
    && ok "(1) header gating=\"3\" — T5 missing + the T9 ledger-orphan + the T9 owed mention, nothing else" \
    || no "(1) header gating= is not 3 (or missing): $( printf '%s' "$OUT" | grep -oE 'gating="[0-9]+"' | head -1 )"

# ── (2) determinism x3 on the static fixture ────────────────────────────────────────────────────────
D2="$( cd "$ROOT" && "$BIN" . --plan-lint=test/planlintfix/wave.md --no-cache )"
D3="$( cd "$ROOT" && "$BIN" . --plan-lint=test/planlintfix/wave.md --no-cache )"
{ [ "$OUT" = "$D2" ] && [ "$D2" = "$D3" ]; } && ok "(2) --plan-lint is deterministic (byte-identical x3)" \
                                              || no "(2) --plan-lint is non-deterministic across repeated runs"

# ── (3) well-formed, minified XML (G4) ──────────────────────────────────────────────────────────────
if command -v xmllint >/dev/null 2>&1; then
    printf '%s' "$OUT" | xmllint --noout - 2>/dev/null && ok "(3) xmllint-clean" || no "(3) not well-formed XML"
else
    printf '  SKIP  (3) xmllint (not installed)\n'
fi
[ "$( printf '%s' "$OUT" | grep -c '' )" -le 1 ] && ok "(3) output is minified (no stray newlines)" \
                                                  || no "(3) output contains newlines outside the legend comment"

# ── (4) dialect="0": a plan that never adopted the convention is not a failing lint ────────────────
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
cat > "$TMP/plain.md" <<'EOF'
# Just a design note

Some prose. No task cards, no status ledger — most of this repo's own plans look exactly like this.
EOF
PLAIN_OUT="$( "$BIN" "$TMP" --plan-lint="$TMP/plain.md" --no-cache )"; PLAIN_RC=$?
[ "$PLAIN_RC" = "0" ] && ok "(4) a file showing neither signal exits 0 — opt-in, not a failing lint" \
                       || no "(4) exit $PLAIN_RC on a no-dialect file, expected 0"
printf '%s' "$PLAIN_OUT" | grep -q 'dialect="0" cards="0" ledger="0"' \
    && ok "(4) dialect=\"0\" cards=\"0\" ledger=\"0\" — honestly reports nothing to check" \
    || no "(4) the no-dialect header shape is wrong: $( printf '%s' "$PLAIN_OUT" | grep -oE '<plan-lint[^>]*>' )"
printf '%s' "$PLAIN_OUT" | grep -q 'gating="0"' && ok "(4) gating=\"0\" on the no-dialect file" \
                                                 || no "(4) gating= is non-zero on a no-dialect file"

# ── (5) refusal: FILE cannot be opened is exit 1, a usage error, nothing on stdout ──────────────────
MISSING_OUT="$( "$BIN" "$ROOT" --plan-lint="$TMP/does-not-exist.md" --no-cache 2>"$TMP/stderr" )"; MISSING_RC=$?
[ "$MISSING_RC" = "1" ] && ok "(5) an unreadable FILE exits 1" || no "(5) exit $MISSING_RC, expected 1"
[ -z "$MISSING_OUT" ] && ok "(5) nothing printed to stdout on refusal" || no "(5) stdout was non-empty on refusal"
grep -q -- '--plan-lint' "$TMP/stderr" && ok "(5) stderr names the flag" || no "(5) stderr does not mention --plan-lint"

# ── (5b) F-09: a DIRECTORY is refused, not silently linted as an empty clean plan ─────────────────────
# darkflags::readWhole opens with fopen(path,"rb"); on this platform that open (and the immediate
# zero-byte fread loop) both succeed on a directory, so before the stat() guard this used to print
# dialect="0" at exit 0 — a directory reading as "clean plan" is a usage error, not a finding.
mkdir -p "$TMP/adir"
DIR_OUT="$( "$BIN" "$ROOT" --plan-lint="$TMP/adir" --no-cache 2>"$TMP/direrr" )"; DIR_RC=$?
[ "$DIR_RC" = "1" ] && ok "(5b) a directory argument exits 1" || no "(5b) exit $DIR_RC, expected 1"
[ -z "$DIR_OUT" ] && ok "(5b) nothing printed to stdout on a directory refusal" || no "(5b) stdout was non-empty: $DIR_OUT"
grep -q 'is a directory' "$TMP/direrr" && ok "(5b) stderr names the specific reason (a directory, not a file)" \
                                        || no "(5b) stderr does not name the directory reason: $( cat "$TMP/direrr" )"

# ── (6) --json is not yet supported for this verb, and refuses LOUDLY rather than silently ignoring it
JSON_OUT="$( "$BIN" "$ROOT" --plan-lint=test/planlintfix/wave.md --json --no-cache 2>"$TMP/jsonerr" )"; JSON_RC=$?
[ "$JSON_RC" = "1" ] && ok "(6) --plan-lint --json refuses (exit 1)" || no "(6) --plan-lint --json exited $JSON_RC, expected 1"
[ -z "$JSON_OUT" ] && ok "(6) nothing printed to stdout under the --json refusal" || no "(6) stdout was non-empty under --json"
grep -q -- '--plan-lint' "$TMP/jsonerr" && ok "(6) the --json refusal names --plan-lint" || no "(6) the --json refusal does not name --plan-lint"

# ── (7) non-git directory: staleness is never claimed, never guessed ───────────────────────────────
mkdir -p "$TMP/nongit"
cat > "$TMP/nongit/wave.md" <<'EOF'
### T1
In progress, but this directory is not a git repo at all.
⏳ pending
EOF
NONGIT_OUT="$( "$BIN" "$TMP/nongit" --plan-lint="$TMP/nongit/wave.md" --no-cache )"
printf '%s' "$NONGIT_OUT" | grep -q 'git="0"' && ok "(7) git=\"0\" — the file's own directory is not a git repo" \
                                                || no "(7) git=\"0\" missing on a non-git directory"
printf '%s' "$NONGIT_OUT" | grep -qE '<card id="T1"[^/]*since=' \
    && no "(7) a since= attribute was printed with no git repo to blame against" \
    || ok "(7) no since= attribute on an hourglass card outside any git repo — degrade-only, never guessed"
printf '%s' "$NONGIT_OUT" | grep -q 'stale="1"' \
    && no "(7) stale=\"1\" was claimed with no git history available"  \
    || ok "(7) no stale=\"1\" claimed without git evidence"

# ── (8) staleness end-to-end: a throwaway git repo with a controlled commit history ─────────────────
# T3's hourglass line is edited (a genuine content change, not a no-op re-commit) at the LAST commit —
# 0 commits behind HEAD, so it must NOT be stale. T4's hourglass line is written ONCE, at the first
# commit, and never touched again; 22 filler commits plus the final edit commit land after it — 23
# commits behind HEAD, comfortably past the kStaleCommits=20 default — so it MUST be stale.
WORK="$( mktemp -d )"
cat > "$WORK/wave2.md" <<'EOF'
### T3
Fresh in-progress task.
⏳ pending

### T4
Stale in-progress task.
⏳ in progress
EOF
echo 0 > "$WORK/filler.txt"
( cd "$WORK" && git init -q && git config user.email t@t && git config user.name t \
  && git add -A && git commit -qm "commit 1: initial wave" >/dev/null 2>&1 )

i=1
while [ "$i" -le 22 ]; do
    echo "$i" > "$WORK/filler.txt"
    ( cd "$WORK" && git add -A && git commit -qm "filler $i" >/dev/null 2>&1 )
    i=$(( i + 1 ))
done

# the genuine content edit — T3's line CHANGES text, so blame re-attributes it to this, the LAST, commit
sed -i.bak 's/⏳ pending/⏳ in progress/' "$WORK/wave2.md" && rm -f "$WORK/wave2.md.bak"
( cd "$WORK" && git add -A && git commit -qm "T3 update" >/dev/null 2>&1 )

STALE_OUT="$( "$BIN" "$WORK" --plan-lint="$WORK/wave2.md" --no-cache )"; STALE_RC=$?
printf '%s' "$STALE_OUT" | grep -q 'git="1"' && ok "(8) git=\"1\" — the throwaway repo was found" \
                                              || { no "(8) git=\"1\" missing — blame could not run at all"; printf '%s\n' "$STALE_OUT"; }

printf '%s' "$STALE_OUT" | grep -qE '<card id="T3"[^/]*since="0"' \
    && ok "(8) T3 since=\"0\" — its hourglass line was edited at HEAD itself" \
    || { no "(8) T3's since= is not 0"; printf '%s' "$STALE_OUT" | grep -oE '<card id="T3"[^/]*/>'; }
printf '%s' "$STALE_OUT" | grep -qE '<card id="T3"[^/]*stale="1"' \
    && no "(8) T3 was marked stale despite being edited at HEAD" \
    || ok "(8) T3 carries no stale=\"1\" — fresh, under the threshold"

printf '%s' "$STALE_OUT" | grep -qE '<card id="T4"[^/]*since="23"' \
    && ok "(8) T4 since=\"23\" — 22 fillers plus the final edit commit, never itself touched again" \
    || { no "(8) T4's since= is not 23"; printf '%s' "$STALE_OUT" | grep -oE '<card id="T4"[^/]*/>'; }
printf '%s' "$STALE_OUT" | grep -qE '<card id="T4"[^/]*stale="1"[^/]*gating="1"' \
    && ok "(8) T4 stale=\"1\" gating=\"1\" — 23 commits behind HEAD, past the stale_commits=20 default" \
    || { no "(8) T4 was not reported stale+gating"; printf '%s' "$STALE_OUT" | grep -oE '<card id="T4"[^/]*/>'; }

[ "$STALE_RC" = "2" ] && ok "(8) exit 2 — the stale hourglass card gates the run" || no "(8) exit $STALE_RC, expected 2"

rm -rf "$WORK"

# ── (9) the real house dialect: status lives in the LEDGER, not the card ───────────────────────────────
# test/planlintfix/wave_ledger.md reproduces the shape this lint was corrected against: T1 closes out on
# its own card body (unbroken by the model correction); T2 closes out ONLY in the ledger (the primary
# real-dialect path); T5 is named by NEITHER — the genuine unlaunched-card catch, mid-wave, this verb
# exists for; T7's own body names lettered sub-tasks T7a/T7b, and the ledger tracks THOSE ids, never
# bare "T7" — proving the digit-fold does not require an exact spelling match to read as launched.
LEDGER_OUT="$( cd "$ROOT" && "$BIN" . --plan-lint=test/planlintfix/wave_ledger.md --no-cache )"; LEDGER_RC=$?

printf '%s' "$LEDGER_OUT" | grep -q 'cards="4"' && ok "(9) cards=\"4\" (T1, T2, T5, T7)" || no "(9) cards=\"4\" missing"

printf '%s' "$LEDGER_OUT" | grep -qE '<card id="T1"[^/]*status="check"[^/]*/>' \
    && ok "(9) T1 still resolves from its OWN body (✅) — the original path is unbroken" \
    || { no "(9) T1's card-derived status broke"; printf '%s\n' "$LEDGER_OUT" | tail -c 800; echo; }
printf '%s' "$LEDGER_OUT" | grep -qE '<card id="T1"[^/]*src="ledger"' \
    && no "(9) T1 was marked src=\"ledger\" despite resolving from its own card body" \
    || ok "(9) T1 carries no src=\"ledger\" — card-derived status is not mislabeled"

printf '%s' "$LEDGER_OUT" | grep -qE '<card id="T2"[^/]*status="check"[^/]*src="ledger"' \
    && ok "(9) T2 resolves to status=\"check\" src=\"ledger\" — closed ONLY in the §Status ledger" \
    || { no "(9) T2's ledger-derived status is missing or malformed"; printf '%s\n' "$LEDGER_OUT" | tail -c 800; echo; }
printf '%s' "$LEDGER_OUT" | grep -qE '<card id="T2"[^/]*gating="1"' \
    && no "(9) T2 was marked gating=\"1\" despite a ledger-recorded ✅" \
    || ok "(9) T2 carries no gating=\"1\" — a card whose status is recorded in the ledger is not a finding"

printf '%s' "$LEDGER_OUT" | grep -qE '<card id="T5"[^/]*status="missing"[^/]*why="unlaunched"[^/]*gating="1"' \
    && ok "(9) T5 reports status=\"missing\" why=\"unlaunched\" gating=\"1\" — THE MID-WAVE ACCEPTANCE CASE" \
    || { no "(9) T5's unlaunched row is missing or malformed"; printf '%s\n' "$LEDGER_OUT" | tail -c 800; echo; }

printf '%s' "$LEDGER_OUT" | grep -qE '<card id="T7"[^/]*status="check"[^/]*src="ledger"' \
    && ok "(9) T7 resolves via its lettered sub-tasks (T7a/T7b in the ledger, never bare \"T7\")" \
    || { no "(9) T7's sub-id-folded status is missing or malformed"; printf '%s\n' "$LEDGER_OUT" | tail -c 800; echo; }
printf '%s' "$LEDGER_OUT" | grep -q 'ledger-orphan id="T7a"' \
    && no "(9) T7a was reported as a ledger-orphan — it is T7's own named sub-task, not an orphan" \
    || ok "(9) T7a does NOT spuriously orphan — folded into card T7 by digit"
printf '%s' "$LEDGER_OUT" | grep -q 'ledger-orphan id="T7b"' \
    && no "(9) T7b was reported as a ledger-orphan — it is T7's own named sub-task, not an orphan" \
    || ok "(9) T7b does NOT spuriously orphan — folded into card T7 by digit"

printf '%s' "$LEDGER_OUT" | grep -q 'plan-lint file="test/planlintfix/wave_ledger.md"[^>]*gating="1"' \
    && ok "(9) header gating=\"1\" — T5 alone; T1/T2/T7 all resolve clean" \
    || no "(9) header gating= is not 1: $( printf '%s' "$LEDGER_OUT" | grep -oE 'gating="[0-9]+"' | head -1 )"

[ "$LEDGER_RC" = "2" ] && ok "(9) exit 2 — the one unlaunched card gates the run" || no "(9) exit $LEDGER_RC, expected 2"

[ "$fail" = 0 ] && echo "planlintcheck: ALL PASS" || echo "planlintcheck: FAILURES ABOVE"
exit "$fail"
