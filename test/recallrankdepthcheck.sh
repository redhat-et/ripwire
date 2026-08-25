#!/usr/bin/env bash
# recallrankdepthcheck.sh — the RANKING half of the root-relative contract: `--recall`'s RELEVANCE
# SCORES must not depend on WHERE the corpus happens to be checked out.
#
#   test/recallrankdepthcheck.sh
#   RIPWIRE_BIN=asan/ripwire test/recallrankdepthcheck.sh
#
# WHY THIS EXISTS. `test/rootrelemitcheck.sh` fixed the EMITTED half — every p=/id= is now relative to the
# corpus root, so a document a consumer receives is independent of checkout depth. That lane closed with one
# DISCLOSED residual, named in its own report (§6 "The one disclosed residual — ranking, not emission"):
#
#     --recall's relevance SCORES still move with checkout depth. The mechanism is not an un-relativized
#     emitted path; it is that the lexical scorer TOKENIZES ing.files[] — the STORED spelling, which that
#     lane deliberately left absolute — so a deeper checkout feeds the scorer more path tokens and shifts
#     tf-idf. Curing it means changing what the RANKER indexes, which is a ranking change owing an eval.
#
# This gate is that residual's gate. `lexical.h` pass 1.5 scans each symbol's file path through the BM25
# state machine at weight `pathFieldDefaultW`, and the RECALL lens is the one caller that passes 1 (docs are
# ranked partly BY their filename — "readme", "report", "paired table"). Scanning the stored ABSOLUTE path
# means every directory above the corpus root is indexed as corpus vocabulary:
#
#   * every symbol gains the SAME root tokens, inflating each doc's BM25 length `dl` and the corpus `avgdl`
#     by different proportions — length normalization shifts, so every score moves; and
#   * if any directory above the root happens to spell a query word ("…/ripwire/docs/recall/…"), that word
#     now matches EVERY document equally, collapsing its idf and promoting whatever else the doc shares.
#
# The second is the one that reorders answers, and it is why ARM 2 exists: a checkout path made of NEUTRAL
# segments under-tests the defect. Measured on the frozen recall corpus (113 docs, 42 labelled queries),
# pre-fix: a 90-char NEUTRAL depth delta moved 5 of 42 queries' rank order and all 42 queries' scores; a
# 68-char delta whose segments were corpus vocabulary moved 11 of 42 rank orders and changed TOP-K
# MEMBERSHIP on 5 — a different set of documents returned for the same query on the same commit.
#
# THE ORACLE IS NOT INVENTED. A RELATIVE root ("ripwire ." from inside the corpus) is already invariant:
# ing.files hold "./docs/x.md", whose only path tokens are corpus-internal. So the correct ranking already
# exists and is already shipped — absolute-root runs simply disagree with it. That makes ARM 3 the ranking
# twin of rootrelemitcheck's ARM 3 ("an absolute root is a SPELLING, not a content change") and it is the
# arm that states the target as an equality rather than as a tolerance.
#
# What it proves:
#   ARM 0  LIVENESS — the corpus actually retrieves. Without this every later arm compares empty to empty
#          and reports ALL PASS on a dead binary (the exact false-green test/binoverridecheck.sh exists to
#          catch, and which rootrelemitcheck.sh shipped and had to fix).
#   ARM 1  NEUTRAL DEPTH INVARIANCE — same corpus, two absolute roots ~90 chars apart, segments chosen to
#          share no vocabulary with the corpus: byte-identical --recall output.
#   ARM 2  ADVERSARIAL DEPTH INVARIANCE — same corpus, a deep root whose every segment IS corpus
#          vocabulary: byte-identical --recall output. This is the tf-idf-pollution arm.
#   ARM 3  SPELLING EQUIVALENCE — `ripwire /abs/corpus --recall=Q` ≡ (cd /abs/corpus && `ripwire . --recall=Q`).
#   ARM 4  THE PATH FIELD STILL WORKS — the kill tripwire. Invariance is trivially achievable by scoring no
#          path tokens at all, which would silently delete a measured retrieval feature
#          (bench/recalleval, +0.03 lenient MRR; gate test/recallevalcheck.sh). A document whose BODY never
#          contains the query word but whose PATH does must still be retrieved. If ARM 4 goes red while
#          1-3 go green, the "fix" disabled the feature instead of relativizing it.
#
# A pre-fix binary fails ARMs 1, 2 and 3 and passes ARMs 0 and 4.
#
# Exit 0 = ALL PASS, non-zero = SOME FAILED.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }

# ── the corpus ──────────────────────────────────────────────────────────────────────────────────────────
# Hand-built rather than borrowed from test/fixture, for one reason ARM 4 depends on: the PATHS must carry
# words the BODIES do not. `notes/zephyr/tuning.md` never contains "zephyr", so a query for it can only be
# answered through the path field. Lowercase single words throughout — the subtoken state machine splits
# camelCase and snake_case, and a split token would make the arms test the tokenizer instead of the root.
mk(){ mkdir -p "$( dirname "$1" )"; printf '%s\n' "$2" > "$1"; }

build_corpus(){
  local d="$1"
  mk "$d/docs/architecture/pipeline.md" '# Stages

The crawl walks the tree, extracts definitions, resolves references
into a call graph and streams a deterministic map to stdout.'
  mk "$d/notes/zephyr/tuning.md"        '# Tuning

Raising the weight of a field changes how strongly a match in that
field contributes to the final relevance number.'
  mk "$d/guides/quality/bar.md"         '# The bar

Report only what a change made worse. Ten measured kinds, each with a
named threshold and a drill-down row.'
  mk "$d/memory/design/notes.md"        '# Notes

A gotcha worth keeping is committed beside the code so the next
session surfaces it without being told.'
  mk "$d/reference/commands.md"         '# Reference

Every verb with its recorded output, regenerated from the binary so a
disagreement is a bug in the document.'
  mk "$d/README.md"                     '# Readme

The short hook, then the details behind a fold.'
}

# Two absolute roots at deliberately different depths. NEUTRAL segments: nine letters that appear nowhere in
# the corpus or the queries, so ARM 1 isolates the pure length-normalization shift.
SHORT="$TMP/a"
DEEP="$TMP/qqqqqqqqq/qqqqqqqqq/qqqqqqqqq/qqqqqqqqq/qqqqqqqqq/qqqqqqqqq/qqqqqqqqq/qqqqqqqqq/qqqqqqqqq/q"
# ADVERSARIAL segments: every one is a word the corpus or the queries actually use. Same corpus, and a
# SHALLOWER delta than DEEP — so any arm this breaks that DEEP does not is about vocabulary, not length.
POLL="$TMP/zephyr/tuning/quality/design/memory/pipeline/reference/commands/readme"
mkdir -p "$SHORT" "$DEEP" "$POLL"
build_corpus "$SHORT"; build_corpus "$DEEP"; build_corpus "$POLL"
printf '  note  short root=%d chars, deep root=%d chars (delta %d), polluted root=%d chars (delta %d)\n' \
  "${#SHORT}" "${#DEEP}" "$(( ${#DEEP} - ${#SHORT} ))" "${#POLL}" "$(( ${#POLL} - ${#SHORT} ))"

# ── the query set ───────────────────────────────────────────────────────────────────────────────────────
# Five queries: one pure path-field probe (Q1, ARM 4's subject) and four ordinary conceptual asks that each
# match several documents, so a shifted score has somewhere to show up as a shifted ORDER.
QUERIES=(
  "zephyr"
  "tuning the weight of a field changes relevance"
  "crawl the tree and resolve references into a call graph"
  "report only what a change made worse"
  "every verb with its recorded output"
)

recall_at(){ "$BIN" "$1" --recall="$2" 2>/dev/null; }

# ── ARM 0 — liveness ────────────────────────────────────────────────────────────────────────────────────
live="$( recall_at "$SHORT" "crawl the tree and resolve references into a call graph" )"
if printf '%s' "$live" | grep -q '━━ '; then
  ok "ARM 0 liveness: the corpus retrieves (at least one recalled document)"
else
  no "ARM 0 liveness: --recall returned NO documents — every later arm would compare empty to empty"
  printf '        refusing to report on arms 1-4 against a binary that retrieves nothing\n'
  echo "SOME FAILED"; exit 1
fi

# ── ARM 1 / ARM 2 — depth invariance, neutral and adversarial ───────────────────────────────────────────
# The whole stdout is compared, not just the separator lines: --recall emits no root anchor of its own
# (checked below), so a correct binary has literally nothing that may differ between the two roots.
if recall_at "$DEEP" "zephyr" | grep -q "$DEEP"; then
  no "precondition: --recall echoes the absolute root in its own output — this gate's byte-compare is invalid"
else
  ok "precondition: --recall emits no absolute root of its own, so a full-output byte-compare is meaningful"
fi

for q in "${QUERIES[@]}"; do
  a="$( recall_at "$SHORT" "$q" )"
  b="$( recall_at "$DEEP"  "$q" )"
  if [ "$a" = "$b" ]; then
    ok "ARM 1 neutral depth: identical ranking for \"$q\""
  else
    no "ARM 1 neutral depth: ranking CHANGED with checkout depth for \"$q\""
    diff <( printf '%s\n' "$a" | grep '━━ ' ) <( printf '%s\n' "$b" | grep '━━ ' ) | head -6 | sed 's/^/        /'
  fi
done

for q in "${QUERIES[@]}"; do
  a="$( recall_at "$SHORT" "$q" )"
  c="$( recall_at "$POLL"  "$q" )"
  if [ "$a" = "$c" ]; then
    ok "ARM 2 adversarial depth: identical ranking for \"$q\""
  else
    no "ARM 2 adversarial depth: corpus-vocabulary directories above the root changed the ranking for \"$q\""
    diff <( printf '%s\n' "$a" | grep '━━ ' ) <( printf '%s\n' "$c" | grep '━━ ' ) | head -6 | sed 's/^/        /'
  fi
done

# ── ARM 3 — spelling equivalence ────────────────────────────────────────────────────────────────────────
# The relative-root run is the ORACLE: its path tokens are already corpus-internal, so it is the ranking an
# absolute-root run must reproduce. Equality here is the definition of the cure.
for q in "${QUERIES[@]}"; do
  a="$( recall_at "$SHORT" "$q" )"
  r="$( cd "$SHORT" && "$BIN" . --recall="$q" 2>/dev/null )"
  if [ "$a" = "$r" ]; then
    ok "ARM 3 spelling: absolute root ≡ relative root for \"$q\""
  else
    no "ARM 3 spelling: an absolute root ranks differently than the same corpus addressed as \".\" — \"$q\""
    diff <( printf '%s\n' "$a" | grep '━━ ' ) <( printf '%s\n' "$r" | grep '━━ ' ) | head -6 | sed 's/^/        /'
  fi
done

# ── ARM 4 — the path field still works (kill tripwire) ──────────────────────────────────────────────────
# "zephyr" appears in exactly one place in this corpus: the DIRECTORY NAME of notes/zephyr/tuning.md. No
# body contains it. Retrieving that document therefore proves the path field is still scored — and it must
# hold at BOTH depths and under the relative spelling, or the feature survives only by accident of location.
for label in SHORT DEEP POLL; do
  case "$label" in
    SHORT) r="$( recall_at "$SHORT" zephyr )";;
    DEEP)  r="$( recall_at "$DEEP"  zephyr )";;
    POLL)  r="$( recall_at "$POLL"  zephyr )";;
  esac
  if printf '%s' "$r" | grep -q '━━ notes/zephyr/tuning.md'; then
    ok "ARM 4 path field: a path-only match is still retrieved at root $label"
  else
    no "ARM 4 path field: notes/zephyr/tuning.md NOT retrieved for \"zephyr\" at root $label — the path field is dead"
    printf '%s' "$r" | grep '━━ ' | head -4 | sed 's/^/        /'
  fi
done

r="$( cd "$SHORT" && "$BIN" . --recall=zephyr 2>/dev/null )"
if printf '%s' "$r" | grep -q '━━ notes/zephyr/tuning.md'; then
  ok "ARM 4 path field: a path-only match is still retrieved under the relative spelling"
else
  no "ARM 4 path field: notes/zephyr/tuning.md NOT retrieved for \"zephyr\" under \".\" — the path field is dead"
fi

if [ "$fail" -eq 0 ]; then echo "ALL PASS"; else echo "SOME FAILED"; fi
exit "$fail"
