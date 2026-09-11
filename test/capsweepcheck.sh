#!/usr/bin/env bash
# capsweepcheck.sh — the cap-sensitivity harness and the document it generates.
#
# WHY. docs/LIMITS.md says a cap EXISTS. It cannot say what the cap DOES. bench/capsweep answers that
# by measuring — and a measuring instrument gets exactly one thing checked about it: whether it is
# measuring the subject or measuring itself. This gate exists for the second question first.
#
# THE DEFECT THIS GATE IS BUILT AROUND. The first sweep ran against the LIVE worktree, which holds the
# harness and the JSON it writes. The harness dir grew between the baseline pass and the probe passes,
# so 18-21 invocations "responded" to every cap — including caps that touch nothing those verbs read.
# Systematic, not random, right units, plausible magnitudes: it read exactly like signal, and it cost a
# night. The fix was a corpus frozen with `git archive HEAD` plus every byte of harness state kept
# outside it. Arm (B) is that fix, held down by a control that can actually fail.
#
# NO BUILD. Every arm here is source-level: the patcher runs against a SYNTHETIC tree, the corpus
# assertion against a SYNTHETIC corpus, and the document is compared against the committed json. That
# is deliberate — the sweep itself needs a patched build and thousands of invocations, so a gate that
# re-ran it would never run. What is gated is the part that can rot silently.
#
# ARMS
#   (A) THE PATCHER, on a synthetic tree: a cap declaration is rewritten into the env-read shape, and a
#       declaration that is NOT a cap is left byte-identical. Both halves matter — a patcher that
#       rewrote everything would also "pass" the first half.
#   (B) THE CORPUS-FREEZE ASSERTION can go red: a synthetic corpus containing bench/capsweep must be
#       REFUSED, and the same corpus without it must be accepted. Contrast, not a one-sided assertion.
#   (C) THE DOCUMENT: `emit --check` reproduces docs/TUNING.md byte-for-byte from the committed
#       bench/capsweep/*.tsv plus the live cap census in src/. The committed doc came out of the same
#       generator, so on its own this is a round trip and proves nothing (see the self-referential-
#       baseline trap). The control is what makes it real: mutate ONE number in a COPY of sweep.tsv,
#       re-run against that copy, and require the comparison to fail. The doc is then demonstrably a
#       function of the data rather than a file that happens to sit next to it.
#   (D) the document says "Generated — do not edit" — a generated file that does not say so gets
#       hand-edited exactly once, and the edit is lost on the next regeneration with no diff to read.
#   (E) the harness refuses to patch the repository itself (the G3/G5 line: production keeps constexpr).
#   (F) THE RECORDS ARE NOT JSON. Arm (B) keeps the harness out of the TREE it measures and says nothing
#       about the FORMAT it writes in — and ripwire INDEXES `.json` as config keys (src/ingest_crawl.h)
#       while `.tsv` is unindexed prose (src/docparse.h, kUnindexedProseExts, beside `.txt`). The first
#       round of this harness committed screen/sweep/tunable as json and they entered the repo's own
#       index: measured on this tree, `--for="incremental cache invalidation"` — the README's headline
#       example — answered confidence="low" margin_pct="0" with them present and confidence="high"
#       margin_pct="22" without, and `--for=kMaxExpandSibs` surfaced bench/capsweep/sweep.json in an
#       answer about a cap. So a json file under bench/capsweep is a failure by its extension alone,
#       held down by a control that finds one in a SYNTHETIC copy — never in the real tree.
#
# This gate binds no ripwire binary: its subjects are a python harness, a source tree and a markdown
# file. It is pinned in test/binoverridecheck.sh's exemption list for that reason.
#
# Usage:  bash test/capsweepcheck.sh
# Exit:   0 = clean · 1 = at least one arm failed · 2 = usage / missing prerequisite
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
GEN="$ROOT/bench/capsweep/capsweep.py"
DOC="$ROOT/docs/TUNING.md"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

command -v python3 >/dev/null 2>&1 || { echo "capsweepcheck: python3 is required"; exit 2; }
[ -f "$GEN" ] || { echo "capsweepcheck: no bench/capsweep/capsweep.py"; exit 2; }
[ -f "$DOC" ] || { echo "capsweepcheck: no docs/TUNING.md — run: python3 bench/capsweep/capsweep.py emit"; exit 2; }
for j in tunable.tsv sweep.tsv screen.tsv corpus.txt; do
    [ -f "$ROOT/bench/capsweep/$j" ] || {
        echo "capsweepcheck: bench/capsweep/$j is missing — the records are TSV, not json (see arm (F)):"
        echo "               ripwire indexes .json, so the harness must not publish itself in that format"
        exit 2; }
done

# A content snapshot of src/, not `git diff`: a developer with legitimate uncommitted work in src/ must
# not read as an escaped patcher. This compares the tree to ITSELF across this gate's own runtime.
srcsum(){ find "$ROOT/src" -type f -print0 | sort -z | xargs -0 cat 2>/dev/null | wc -c; }
src_before="$( srcsum )"

# ── (A) the patcher, on a synthetic tree ────────────────────────────────────────────────────────────
# Two declarations, one a cap by the harness's own rule (a k-name matching its KEY vocabulary) and one
# not. A presence guard runs first: if the fixture stopped containing what the arm greps for, the arm
# would compare nothing against nothing and pass.
mkdir -p "$TMP/synth/src"
cat > "$TMP/synth/src/synth.h" <<'EOF'
#pragma once
inline constexpr std::size_t kSynthRowCap = 7;      // a cap: bounds how many rows survive
inline constexpr double kSynthPlainConstant = 3.5;  // NOT a cap: no cap-vocabulary token in the name
EOF
grep -q 'kSynthRowCap' "$TMP/synth/src/synth.h" && grep -q 'kSynthPlainConstant' "$TMP/synth/src/synth.h" || {
    no "(A) fixture guard: the synthetic header lost its own declarations"; }
before_plain="$( grep 'kSynthPlainConstant' "$TMP/synth/src/synth.h" )"

if ! python3 "$GEN" patch --root "$TMP/synth" > "$TMP/patch.out" 2>&1; then
    no "(A) patcher exited non-zero on a synthetic tree: $( head -3 "$TMP/patch.out" | tr '\n' ' ' )"
else
    after_cap="$( grep 'kSynthRowCap' "$TMP/synth/src/synth.h" )"
    after_plain="$( grep 'kSynthPlainConstant' "$TMP/synth/src/synth.h" )"
    a_ok=0; b_ok=0
    case "$after_cap" in
        *'rwcapsweep::envOr'*'RWCAP_kSynthRowCap'*'7'*) a_ok=1 ;;
    esac
    case "$after_cap" in *constexpr*) a_ok=0 ;; esac      # it must no longer be constexpr, or nothing is tunable
    [ "$after_plain" = "$before_plain" ] && b_ok=1
    if [ "$a_ok" = 1 ] && [ "$b_ok" = 1 ]; then
        ok "(A) patcher rewrites a cap into the env-read shape and leaves a non-cap declaration untouched"
    else
        [ "$a_ok" = 1 ] || no "(A) the cap declaration was not rewritten into the env-read shape: $after_cap"
        [ "$b_ok" = 1 ] || no "(A) a NON-cap declaration was rewritten — the patcher is too greedy: $after_plain"
    fi
fi

# ── (B) the corpus-freeze assertion, both directions ────────────────────────────────────────────────
mkdir -p "$TMP/clean/src" "$TMP/dirty/src" "$TMP/dirty/bench/capsweep"
: > "$TMP/clean/src/a.h"; : > "$TMP/dirty/src/a.h"; : > "$TMP/dirty/bench/capsweep/capsweep.py"
if python3 "$GEN" check-corpus --corpus "$TMP/dirty" >/dev/null 2>&1; then
    no "(B) a corpus containing bench/capsweep was ACCEPTED — the self-measurement guard cannot fire"
elif ! python3 "$GEN" check-corpus --corpus "$TMP/clean" >/dev/null 2>&1; then
    no "(B) a clean corpus was REFUSED — the guard rejects everything, so its refusals mean nothing"
else
    ok "(B) corpus guard refuses a corpus holding the harness and accepts one without it"
fi

# ── (C) the document is a function of the committed data ────────────────────────────────────────────
if out="$( cd "$ROOT" && python3 "$GEN" emit --check 2>&1 )"; then
    ok "(C) docs/TUNING.md matches bench/capsweep/*.tsv + src/ — ${out#*: }"
else
    no "(C) docs/TUNING.md is STALE: $out — run: python3 bench/capsweep/capsweep.py emit"
fi

# the control. Without it (C) is a round trip through the artifact it is checking, which is green
# forever. Mutate one measured byte count in a COPY of the data and require the comparison to notice.
mkdir -p "$TMP/data"
cp "$ROOT/bench/capsweep/tunable.tsv" "$TMP/data/"
# probe_bytes is column 6 of sweep.tsv, and +4242 is a delta no real run produced. The `#` provenance
# line passes through untouched, so the copy stays a well-formed record file.
awk -F'\t' -v OFS='\t' '/^#/ { print; next } !d { $6 = $6 + 4242; d = 1 } { print }' \
    "$ROOT/bench/capsweep/sweep.tsv" > "$TMP/data/sweep.tsv"
if cmp -s "$ROOT/bench/capsweep/sweep.tsv" "$TMP/data/sweep.tsv"; then
    no "(C) mutation control: the mutation was a no-op, so the control below proves nothing"
elif ( cd "$ROOT" && python3 "$GEN" emit --check --data "$TMP/data" >/dev/null 2>&1 ); then
    no "(C) mutation control: a changed byte count in sweep.tsv did NOT change the document — (C) is inert"
else
    ok "(C) mutation control: a changed measurement makes --check fail, so the doc IS derived from the data"
fi

# ── (D) the generated document says it is generated ─────────────────────────────────────────────────
if grep -Fq '**Generated — do not edit.**' "$DOC"; then
    ok "(D) docs/TUNING.md declares itself generated"
else
    no "(D) docs/TUNING.md does not carry the 'Generated — do not edit' banner"
fi

# ── (E) the harness refuses to patch production source ──────────────────────────────────────────────
if python3 "$GEN" patch --root "$ROOT" >/dev/null 2>&1; then
    no "(E) the patcher accepted the REPOSITORY as its target — production must keep its constexpr (G3/G5)"
else
    ok "(E) the patcher refuses to rewrite the repository itself"
fi
if [ "$( srcsum )" = "$src_before" ]; then
    ok "(E) src/ is byte-identical to what it was when this gate started"
else
    no "(E) src/ CHANGED while this gate ran — the patcher escaped its scratch tree"
fi

# ── (F) the records are TSV, because a harness must not enter the index it measures ─────────────
# Not a style preference. ripwire indexes `.json` as config keys (src/ingest_crawl.h's extension table);
# `.tsv` is unindexed prose (src/docparse.h, kUnindexedProseExts), which is why corpus.txt beside these
# records never polluted anything. Committed as json, the same numbers changed this repo's own answers
# — the header carries the measurement.
jsonrecords(){ find "$1" -type f -name '*.json' 2>/dev/null | sort; }
stray="$( jsonrecords "$ROOT/bench/capsweep" )"
if [ -n "$stray" ]; then
    # repo-relative: a gate's own failure text lands in a public CI log, and an operator's absolute path
    # is machine layout nobody asked to publish (the same rule capsweep.py's rel() follows).
    no "(F) bench/capsweep holds json record(s), which ripwire INDEXES — the harness is inside the index it measures: $( echo "$stray" | sed "s|^$ROOT/||" | tr '\n' ' ' )"
else
    ok "(F) bench/capsweep holds no .json — the records are TSV, which src/docparse.h leaves unindexed"
fi
# The control, on a SYNTHETIC copy. A scan that can never see a json record is a green line meaning
# nothing; running it against the real tree would drop a probe file into the population other gates read.
mkdir -p "$TMP/synthjson"; : > "$TMP/synthjson/sweep.json"; : > "$TMP/synthjson/keep.tsv"
case "$( jsonrecords "$TMP/synthjson" )" in
    *sweep.json) ok "(F) control: the same scan reports a json record in a synthetic copy, so (F) can go red" ;;
    *)           no "(F) control: the scan did not see a json record in a synthetic copy — (F) is inert" ;;
esac

[ $fail -eq 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit $fail
