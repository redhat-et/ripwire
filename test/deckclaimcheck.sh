#!/usr/bin/env bash
# deckclaimcheck.sh — numeric claims ABOUT the deck are derived from the deck, not remembered.
#
# Arm (A), the original: the flag count the generated showcase source states matches `--help`.
# Arm (B), added 2026-08-10: the SLIDE COUNT stated in prose matches the generator's own
#          `p.addSlide()` calls. Same shape as (A), different fact, and it had the same hole (A) was
#          written to close — "18 slides" was asserted in TWO prose files (README.md's documentation
#          table and present/README.md's opening line) with nothing deriving it from the generator, so
#          a deck that grew or shrank falsified both silently. It grew from 18 to 23 in the refresh
#          that added this arm; without (B) both sentences would still read "18".
#
# Both arms are DERIVE-then-COMPARE, never a pinned constant: the instrument is the artifact itself
# (the binary's --help, the generator's addSlide calls), so the gate cannot drift out of date on its
# own — only a real disagreement fails it.
set -u

ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${RIPWIRE_BIN:-$ROOT/build/ripwire}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
GEN="$ROOT/present/deck5_ripwire_build.js"

[ -x "$BIN" ] || { echo "deckclaimcheck: no binary at $BIN — build first"; exit 2; }
[ -f "$GEN" ] || { echo "deckclaimcheck: missing $GEN"; exit 2; }

# ── (A) flag count ──────────────────────────────────────────────────────────────────────────────
derived="$( "$BIN" --help 2>&1 | grep -oE '\-\-[a-z][a-z0-9-]+' | sort -u | wc -l | tr -d ' ' )"
bad="$( grep -oE '[0-9]+ long flags' "$GEN" | grep -v "^${derived} long flags$" || true )"
[ -z "$bad" ] || { echo "deckclaimcheck: stale claim(s), binary has $derived flags: $bad"; exit 1; }
grep -q "${derived} long flags" "$GEN" || { echo "deckclaimcheck: generator does not state derived count $derived"; exit 1; }

# ── (B) slide count ─────────────────────────────────────────────────────────────────────────────
# The generator calls p.addSlide() exactly once per slide; that call IS the definition of "a slide",
# so counting it is a derivation and not a second place to keep the number. A count of 0 means the
# grep stopped matching the generator's idiom (a refactor to a helper, say) — that is a REFUSAL, not
# a pass, because a gate that silently compares against 0 is the inert shape this suite keeps hitting.
#
# Count the CALL, not the line it usually sits on. The first draft of this arm anchored on
# `^\s*const s = p.addSlide()` — the idiom all 18 slides happened to use — and a mutation test caught
# it cold: appending `{ const s = p.addSlide(); bg(s); }` grew the deck to 19 while the gate still
# reported 18 and PASSED. An arm that only recognizes the formatting it was written against is the
# same inert shape in miniature. `grep -o` counts every occurrence, including several on one line.
slides="$( grep -oF 'p.addSlide()' "$GEN" | wc -l | tr -d ' ' )"
[ "$slides" -ge 5 ] || {
    printf 'deckclaimcheck: derived slide count %s from %s — implausible; has the generator idiom changed?\n' \
        "$slides" "${GEN#$ROOT/}"
    printf '        (B) counts occurrences of the literal: p.addSlide()\n'
    exit 2; }

# Prose that states a slide count, and must agree with it. Both files ship publicly; both stated 18
# while the generator built 18, and both would have kept stating it at 23. Every drifted site is
# reported, not just the first — the same courtesy deckcheck.sh pays with its file:line list, and the
# reason this arm accumulates instead of exiting on the first mismatch.
slideClaimFail=0
for f in "$ROOT/README.md" "$ROOT/present/README.md"; do
    [ -f "$f" ] || continue
    while IFS=: read -r lineNo claim; do
        [ -z "$claim" ] && continue
        stated="${claim%% slides*}"
        [ "$stated" = "$slides" ] && continue
        printf 'deckclaimcheck: %s:%s states "%s" — the generator builds %s\n' \
            "${f#$ROOT/}" "$lineNo" "$claim" "$slides"
        slideClaimFail=1
    done <<< "$( grep -noE '[0-9]+ slides' "$f" || true )"
done

# A claim that vanished is as much a drift as a claim that is wrong: the documentation table's slide
# count is how a reader sizes the deck before clicking it. Require at least one prose site to state it.
grep -qE "$slides slides" "$ROOT/README.md" || {
    printf 'deckclaimcheck: README.md no longer states the deck size (%s slides) — the documentation-table row lost its count\n' "$slides"
    slideClaimFail=1; }

# TERMINAL REGION — deliberately the last read of slideClaimFail, and deliberately self-contained.
# test/gateexitcheck.sh arm (B) slices from an accumulator's final read to EOF and RUNS that slice in
# isolation with the accumulator forced to 1 and to 0; the slice must exit non-zero then zero. An
# earlier draft put the README-states-it grep AFTER this test, which made the slice reference $ROOT
# and $slides — unset in the harness — so the clean run exited 1 and the gate was classified
# UNSYNTHESIZABLE: unprovable, not wrong, which is its own kind of unchecked.
[ "$slideClaimFail" -eq 0 ] || exit 1
printf 'deckclaimcheck: ALL PASS — %s long flags, %s slides, derived from the artifacts themselves\n' "$derived" "$slides"
