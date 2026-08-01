#!/usr/bin/env bash
# mdembedcheck.sh — §P7 gate: ripwire's markdown-emitting verbs (--report, --recall) must produce
# EMBEDDABLE markdown — no run of four-or-more backticks anywhere in the output, so a consumer that wraps
# the whole payload in a five-backtick fence (the standard trick for embedding markdown-that-itself-contains
# fenced code) can always do so safely, no matter how many THREE-backtick fences the payload carries.
#
# WHY THIS GATE EXISTS (read this before "fixing" it green by widening the assertion): --report and
# --recall emit raw markdown containing three-backtick code fences and "##" headings — neither verb escapes
# or re-fences anything it emits. This ONCE silently broke a generated document (test/showcase_capture.py's
# output) until its own wrapper fences were widened from three to five backticks by hand; no gate would have
# caught that regression before it shipped. This assertion is that gate, going forward.
#
# THIS GATE MAY LEGITIMATELY BE GREEN THE FIRST TIME YOU RUN IT (and stay green for a long time) — pinning
# an invariant that currently holds is the point "assertions, not
# bytes" — an INVARIANT, not a stored golden). Today, --report's payload is entirely SYNTHESIZED (counts,
# sorted names, fixed section labels) so it structurally cannot contain a 4-backtick run, and no doc file
# currently indexed by --recall happens to contain one either (docs/captures/ — which DOES, from
# test/showcase_capture.py's own 5-backtick wrapper — is excluded from ingest by design; src/ingest.h:56-60).
# --recall's guarantee is NOT enforced by construction the way --report's is: --recall embeds a doc's FULL
# body verbatim (src/recall.h: "fwrite, not %s: an embedded NUL must not truncate the doc"), so this gate is
# the ONLY thing standing between a future doc that happens to contain a 4-backtick run (someone writing
# ABOUT nested fences, ironically) and a silently-broken consumer. If this gate ever goes red, that is a
# real doc-content regression to fix (widen the doc's own fence, or the consumer's) — not a signal to raise
# the threshold in this script.
#
# Usage:  RIPWIRE_BIN=build/ripwire bash test/mdembedcheck.sh   |   RIPWIRE_BIN=asan/ripwire bash …
# Exits non-zero on any failure. Does NOT edit regression.sh.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${RIPWIRE_BIN:-$ROOT/build/ripwire}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
echo "mdembedcheck: BIN=$BIN  CORPUS=$ROOT"

# a run of 4-or-more consecutive backticks, ANYWHERE in the payload (not anchored to line start — a run
# mid-line is just as fatal to a 5-backtick wrapper fence as one at column 0).
has_bad_run(){ printf '%s' "$1" | grep -Eq '`{4,}'; }
first_bad_run(){ printf '%s' "$1" | grep -Eo '`{4,}' | head -1; }

# ── 1) --report on this repo (the real, non-synthetic corpus, not a tiny fixture) ─────────────────────────
REP="$( "$BIN" "$ROOT" --no-cache --report 2>/dev/null )"
[ -n "$REP" ] || { echo "no --report output — cannot test"; exit 2; }
has_bad_run "$REP" \
    && no "--report contains a 4+-backtick run ('$( first_bad_run "$REP" )') — breaks a 5-backtick embedding fence" \
    || ok "--report contains no run of 4+ backticks (safe to embed in a 5-backtick fence)"

# ── 2) --recall on this repo, several queries (recall embeds doc bodies VERBATIM — the corpus decides) ────
for Q in "pagerank ranking" "cmake build commands" "quality delta regression" "markdown fence backtick embed"; do
    REC="$( "$BIN" "$ROOT" --no-cache --recall="$Q" 2>/dev/null )"
    if has_bad_run "$REC"; then
        no "--recall=\"$Q\" contains a 4+-backtick run ('$( first_bad_run "$REC" )') — breaks a 5-backtick embedding fence"
    else
        ok "--recall=\"$Q\" contains no run of 4+ backticks (safe to embed in a 5-backtick fence)"
    fi
done

# ── 2b) BUDGETED --recall: the truncation cut must never leave a code fence OPEN (§B2) ───────────────────
# --max-tokens slices the last doc's body mid-stream. When that cut lands INSIDE a ```fenced block, the
# emitted payload used to end with an OPENED fence that is never closed — the truncation marker and the
# closing "(capped: …)" note then sit inside a phantom code block, and a consumer that embeds this payload
# inherits corrupted fence state for everything it appends afterwards. The invariant: in EVERY budgeted
# output, the number of lines whose first non-space characters are three-or-more backticks is EVEN.
# (Even-ness is the toggle-parity of the fence state machine: an odd count means one fence never closed.)
fence_line_count(){ printf '%s\n' "$1" | grep -cE '^[[:space:]]*```' ; }

# the repro query: this corpus's CLAUDE.md "## Quick commands" ```bash block is exactly what a mid-budget
# cut lands inside. Kept literal so the gate stays a regression test for the reported repro, not a fuzz.
BQ="quick commands cmake build"
for MT in 2000 8000 15000 30000; do
    REC="$( "$BIN" "$ROOT" --no-cache "--recall=$BQ" "--max-tokens=$MT" 2>/dev/null )"
    if [ -z "$REC" ]; then
        no "--recall=\"$BQ\" --max-tokens=$MT produced no output"
        continue
    fi
    FC="$( fence_line_count "$REC" )"
    if [ "$(( FC % 2 ))" -eq 0 ]; then
        ok "--recall --max-tokens=$MT: fences balanced ($FC fence lines, even)"
    else
        no "--recall --max-tokens=$MT: UNBALANCED fences ($FC fence lines, odd) — a truncation cut left a \`\`\` block open"
    fi
    has_bad_run "$REC" \
        && no "--recall --max-tokens=$MT contains a 4+-backtick run ('$( first_bad_run "$REC" )')" \
        || ok "--recall --max-tokens=$MT contains no run of 4+ backticks"
done

# determinism: the fence-closing decision must not vary run to run (it is pure text state, no clock/map order)
D1="$( "$BIN" "$ROOT" --no-cache "--recall=$BQ" --max-tokens=15000 2>/dev/null )"
D2="$( "$BIN" "$ROOT" --no-cache "--recall=$BQ" --max-tokens=15000 2>/dev/null )"
[ "$D1" = "$D2" ] \
    && ok "budgeted --recall is deterministic across two runs" \
    || no "budgeted --recall differs between runs (non-deterministic truncation)"

# sanity: the fence counter itself is live — an odd synthetic payload MUST be reported odd
[ "$( fence_line_count "$( printf 'x\n```bash\ncmake\n' )" )" -eq 1 ] \
    && ok "mutation self-test: fence counter reports an unclosed fence as odd" \
    || no "mutation self-test: fence counter did NOT see a lone opening fence (unsound gate)"

# ── 3) sanity: the assertion itself is live (a synthetic 4-backtick run MUST be caught) ────────────────────
if has_bad_run "three fences: \`\`\`\`" ; then
    ok "mutation self-test: a synthetic 4-backtick run is correctly detected"
else
    no "mutation self-test broke — a 4-backtick run did NOT trip the assertion (unsound gate)"
fi
if has_bad_run "plain \`\`\` three-backtick fence, no more"; then
    no "mutation self-test: a plain 3-backtick fence was WRONGLY flagged (assertion too strict)"
else
    ok "mutation self-test: a plain 3-backtick fence is correctly NOT flagged"
fi

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit $fail
