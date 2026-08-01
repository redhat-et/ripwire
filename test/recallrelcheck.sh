#!/usr/bin/env bash
# recallrelcheck.sh — RELEVANCE gate for --recall=TASK. Existing coverage (regression 3c / doc-ingest)
# only asserts --recall is deterministic + non-empty + extracts text — NOT that it retrieves the RIGHT
# doc. --recall is the "recall what I already know before reading code" verb; if it surfaced the wrong
# memory/design doc, an agent would prime on irrelevant context. This gate builds three mutually-unrelated
# design docs and asserts the retrieval picks the on-topic one FIRST and scores it highest.
#
# Corpus (three disjoint topics, no shared vocabulary):
#   kafka.md   — kafka consumer group rebalancing / partition assignment / offset commits
#   render.md  — font glyph rasterization / antialiasing / bezier tessellation
#   cache.md   — LRU eviction / doubly-linked list + hashmap / TTL expiry
#
# Hand-reasoned expectations (BM25-family retrieval over distinct term sets):
#   query "kafka consumer offset rebalancing partition" → kafka.md is the SINGLE relevant doc, ranked #1
#   query "glyph antialiasing bezier rasterization"     → render.md ranked #1  (the ranking actually MOVES
#                                                          with the query — not a fixed order)
#   query "unicorn zebra quasar nonexistentterm"        → 0 relevant docs (no doc matches → honest empty)
#
# The #1-doc assertion parses the FIRST "━━ <path> (relevance X) ━━" header line — best-first ordering is
# part of the emitted contract ("best-first" appears in the summary line).
#
# Usage:  RIPWIRE_BIN=build/ripwire bash test/recallrelcheck.sh   |   RIPWIRE_BIN=asan/ripwire bash …
# Exits non-zero on any failure. Does NOT edit regression.sh.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${RIPWIRE_BIN:-$ROOT/build/ripwire}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
echo "recallrelcheck: BIN=$BIN"

TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
R="$TMP/repo"; mkdir -p "$R"
cat >"$R/kafka.md" <<'EOF'
# Kafka consumer rebalancing
Partition assignment, consumer group rebalancing, offset commits and the sticky assignor for kafka streams.
EOF
cat >"$R/render.md" <<'EOF'
# Font rendering pipeline
Glyph rasterization, subpixel antialiasing, hinting and bezier curve tessellation for the text render layer.
EOF
cat >"$R/cache.md" <<'EOF'
# LRU cache eviction
Doubly-linked list plus hashmap, eviction on capacity, TTL expiry for the in-memory cache.
EOF
# a CODE file, deliberately unrelated to every query below — §A8.2 needs the corpus to hold something
# --recall never ranks (docsOnly), so ing.files.size() (4: 3 docs + this one) DIVERGES from
# docFileMask()'s population (3, docs only) — the exact gap the pre-fix denominator bug hid.
cat >"$R/unrelated_code.py" <<'EOF'
def totally_unrelated_helper(x):
    return x + 1
EOF

run(){ perl -e 'alarm 15; exec @ARGV' "$BIN" "$R" --recall="$1" --no-cache 2>/dev/null; }
# basename of the FIRST result-block header ("━━ <path> (relevance X) ━━")
top_doc(){ printf '%s' "$1" | grep -F '━━' | head -1 | grep -oE '/[^ ]*\.md' | sed 's#.*/##'; }
relevant_n(){ printf '%s' "$1" | grep -oE '[0-9]+ relevant of' | grep -oE '^[0-9]+'; }

# ── 1) kafka query → kafka.md ranked #1 ──────────────────────────────────────────────────────────────
K="$( run "kafka consumer offset rebalancing partition" )"
[ "$( top_doc "$K" )" = "kafka.md" ] \
    && ok "--recall(kafka query): kafka.md ranked #1 (best-first)" \
    || no "--recall(kafka query): top doc is '$( top_doc "$K" )', expected kafka.md"

# ── 2) render query → render.md ranked #1 (ranking MOVES with the query, not a fixed order) ───────────
G="$( run "glyph antialiasing bezier rasterization" )"
[ "$( top_doc "$G" )" = "render.md" ] \
    && ok "--recall(render query): render.md ranked #1 — retrieval is query-sensitive, not fixed order" \
    || no "--recall(render query): top doc is '$( top_doc "$G" )', expected render.md"

# ── 3) the two queries pick DIFFERENT top docs — proves relevance, not a constant winner ─────────────
[ "$( top_doc "$K" )" != "$( top_doc "$G" )" ] \
    && ok "--recall: kafka-query and render-query return different #1 docs (kafka.md vs render.md)" \
    || no "--recall returned the same #1 doc for both queries — relevance not discriminating"

# ── 4) irrelevant query → 0 relevant docs (honest empty, not a forced match) ─────────────────────────
Z="$( run "unicorn zebra quasar zzznonexistentterm" )"
run "unicorn zebra quasar zzznonexistentterm" >/dev/null 2>&1; ZEC=$?
ZN="$( relevant_n "$Z" )"
{ [ "$ZEC" = 0 ] && { [ "$ZN" = 0 ] || [ -z "$( top_doc "$Z" )" ]; }; } \
    && ok "--recall(nonsense query): 0 relevant docs, exit 0 (honest empty, no forced match)" \
    || no "--recall(nonsense query): relevant=$ZN top='$( top_doc "$Z" )' exit=$ZEC (expected 0 relevant)"

# ── 5) determinism ───────────────────────────────────────────────────────────────────────────────────
[ "$( run "kafka consumer offset rebalancing partition" )" = "$( run "kafka consumer offset rebalancing partition" )" ] \
    && ok "--recall deterministic (byte-identical run-to-run)" || no "--recall non-deterministic"

# ── 6) §A8.2 + §B9.2: the "K relevant of N document files" denominator is docFileMask()'s population (the
# DOCUMENT files the verb actually ranks), not ing.files.size() (the whole file corpus, code included).
#
# §B9.2 PIN UPDATE: §A8.2 reconciled the two NUMBERS on this fixture but not the
# PREDICATES behind them — docFileMask is "≥1 Markdown-LANG symbol" (so it includes docparse'd notebooks /
# HTML / CSV) while --doc-drift's docs= is isMarkdownPath, an EXTENSION test. On the live repo they had
# already drifted 4 apart, and both were narrated as "docs". The fix was naming, not arithmetic: recall now
# says "document files" and states in --help that it is a SUPERSET of --doc-drift's docs=. So this arm
# tracks the new noun, and pins BOTH halves of the ruling — the two counts still agree on a
# markdown-only tree (where the predicates coincide), and the two verbs no longer share a word.
docs_of(){ printf '%s' "$1" | grep -oE '[0-9]+ document files,' | grep -oE '^[0-9]+'; }
RECALL_N="$( docs_of "$K" )"
DD="$( "$BIN" "$R" --doc-drift --no-cache 2>/dev/null )"
DRIFT_N="$( printf '%s' "$DD" | grep -oE '<doc-drift docs="[0-9]+"' | grep -oE '"[0-9]+"' | tr -d '"' )"
{ [ -n "$RECALL_N" ] && [ -n "$DRIFT_N" ] && [ "$RECALL_N" = "$DRIFT_N" ] && [ "$RECALL_N" = 3 ]; } \
    && ok "§A8.2: --recall's denominator ($RECALL_N document files) == --doc-drift's docs= ($DRIFT_N) on a markdown-only tree" \
    || no "§A8.2: denominator mismatch — --recall says $RECALL_N document files, --doc-drift says docs=$DRIFT_N (expected both 3)"
printf '%s' "$K" | grep -qE '[0-9]+ relevant of [0-9]+ document files' \
    && ok "§B9.2: --recall names its OWN population (\"document files\"), not --doc-drift's word (\"docs\")" \
    || no "§B9.2: --recall still reports its denominator as \"docs\" — the two predicates share a noun again"
HELP_DEN="$( "$BIN" --help 2>&1 | tr '\n' ' ' )"
printf '%s' "$HELP_DEN" | grep -q 'SUPERSET of --doc-drift' \
    && ok "§B9.2: --help states the superset relationship between the two populations" \
    || no "§B9.2: --help does not state how recall's denominator relates to --doc-drift's docs="

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit $fail
