#!/usr/bin/env bash
# termdensitycheck.sh — gate for QUERY-TERM DENSITY WEIGHTING in the conceptual BM25 (src/lexical.h,
# queryDensityWeight). Registered + measured: docs/EVALS.md §4 "Query-term density weighting".
#
# THE SHAPE. A conceptual query's words are also the NAME and the MESSAGE of a diagnostic class — a
# *Warning or *Error whose whole document is one sentence, written in the reader's vocabulary, about the
# failure the real mechanism produces. Such a document is not merely SHORT; a floor on `dl` measured
# against the corpus average was swept end to end against this population and moved it by zero. What it
# is, is a document a large fraction of which IS the query. So the rule is a RATIO: the share of a
# document that is query text, capped, with a floor so evidence is reduced and never deleted.
#
# THIS TREE CARRIES NO SUCH POPULATION — no class whose entire body is a sentence restating a question —
# so a gate written against the repo would be green while inert, the failure CONTRIBUTING.md §2 names.
# The corpus below is synthetic and carries the shape directly: forty ordinary filler modules so avgdl
# and idf are corpus-shaped rather than set by the three probe documents, one implementation, one
# diagnostic class, and one control.
#
# RED, measured against the binary at this lane's base rather than assumed: the diagnostic's two symbols
# take ranks 1 and 2 and the implementation lands third, behind both.
# GREEN (this gate): the implementation outranks EVERY symbol of the diagnostic's file; the diagnostic is
# still findable by its own name (a weight, not a filter); a SHORT document whose subject term is dense
# is not demoted, which is what separates this rule from the length floor that failed; the rule is inert
# at floor=100 by construction; and pruned scoring still agrees with exhaustive scoring byte for byte,
# which is what keeps the MaxScore impact bound honest under a shrink-only factor.
#
# Usage:  RIPWIRE_BIN=build/ripwire bash test/termdensitycheck.sh   |   RIPWIRE_BIN=asan/ripwire bash …
# Exits non-zero on any failure. Does NOT edit regression.sh.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
echo "termdensitycheck: BIN=$BIN"

TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
R="$TMP/repo"; mkdir -p "$R/lib" "$R/lib/errors" "$R/lib/util"

QUERY='how does the collector mark a stale entry as reclaimable'

# ── the corpus ───────────────────────────────────────────────────────────────────────────────────────
# 1) filler: an ordinary package's worth of small modules. Without these the three probe documents ARE
#    the corpus, avgdl and idf are set by them, and every number below measures the fixture rather than
#    the rule.
i=0
while [ $i -lt 40 ]; do
  {
    echo "/** Build the $i-th descriptor for the packer pipeline. */"
    echo "function buildDescriptor$i(options, registry) {"
    echo "  const descriptor = registry.lookup(options.key$i);"
    echo "  return descriptor ? descriptor.freeze() : registry.create(options.key$i);"
    echo "}"
    echo "module.exports = buildDescriptor$i;"
  } >"$R/lib/util/descriptor$i.js"
  i=$(( i + 1 ))
done

# 2) the implementation. It explains the subject in its doc comment and then spends its body on
#    identifiers that have nothing to do with the question — which is what implementing something looks
#    like, and exactly why the query is a small fraction of this document.
{
  echo '/**'
  echo ' * Mark every stale entry the collector can reclaim. An entry is stale once its epoch is behind'
  echo ' * the collector cursor; the collector marks each stale entry reclaimable and hands the batch back.'
  echo ' * A reclaimable entry is never dropped here — marking is what this does, and the collector'
  echo ' * decides later which reclaimable entry it can afford to release.'
  echo ' */'
  echo 'function markStaleEntriesReclaimable(collector, cursor) {'
  echo '  const reclaimable = [];'
  i=0; while [ $i -lt 18 ]; do
    echo "  const candidate$i = collector.entries[$i];"
    echo "  const generation$i = candidate$i ? candidate$i.generationIndex : options.defaultGeneration;"
    echo "  const promoted$i = registry.promote(generation$i, candidate$i, options.retainPolicy);"
    echo "  if (promoted$i && promoted$i.epoch < cursor) { promoted$i.stale = true; reclaimable.push(promoted$i); }"
    i=$(( i + 1 ))
  done
  echo '  return reclaimable;'
  echo '}'
  echo 'module.exports = markStaleEntriesReclaimable;'
} >"$R/lib/CollectorSweep.js"

# 3) the diagnostic class. Every content word of the question appears in it, once, in a sentence a human
#    wrote for a human — and that sentence is very nearly the whole document.
{
  echo 'class StaleEntryReclaimWarning extends BuildWarning {'
  echo '  constructor(entry) {'
  echo '    super('
  echo '      `how does the collector mark a stale entry as reclaimable: ${entry.id} was still reachable`'
  echo '    );'
  echo '    this.name = "StaleEntryReclaimWarning";'
  echo '  }'
  echo '}'
  echo 'module.exports = StaleEntryReclaimWarning;'
} >"$R/lib/errors/StaleEntryReclaimWarning.js"

# 4) the CONTROL, and it is the load-bearing row. A three-line document is exactly what a LENGTH rule
#    demotes; this rule must not, because its subject term is dense for the honest reason. If this row
#    ever goes red the rule has become the length floor that was already rejected for this bucket.
{
  echo 'function reclaimableCount(pool) {'
  echo '  return pool.reclaimable.length + pool.reclaimable.pending + pool.reclaimable.staged;'
  echo '}'
  echo 'module.exports = reclaimableCount;'
} >"$R/lib/util/reclaimableCount.js"

# ── the probe: one ranked candidate list, parsed into "name rank score" rows ──────────────────────────
"$BIN" "$R" --for="$QUERY" --format=candidates --top-k=30 >"$TMP/main.xml" 2>"$TMP/err" \
  || { echo "binary failed"; cat "$TMP/err"; exit 2; }
tr '>' '\n' <"$TMP/main.xml" | grep -o 'r="[0-9]*" s="[0-9.]*" n="[^"]*"' \
  | sed -E 's/r="([0-9]*)" s="([0-9.]*)" n="([^"]*)"/\3 \1 \2/' >"$TMP/ranks"
rankOf(){ awk -v n="$1" '$1==n {print $2; found=1; exit} END{ if(!found) print "" }' "$TMP/ranks"; }

# presence guard FIRST — every assertion below compares ranks, and a missing row would let a comparison
# pass by vacuity.
missing=''
for s in markStaleEntriesReclaimable StaleEntryReclaimWarning constructor reclaimableCount; do
  [ -n "$( rankOf "$s" )" ] || missing="$missing $s"
done
if [ -n "$missing" ]; then
  no "presence guard — these symbols never reached the ranked list, so nothing below could be tested:$missing"
  printf '        ranked rows were:\n'; sed 's/^/          /' "$TMP/ranks"
  exit 1
fi
ok "presence guard — all four probe symbols are indexed and ranked"

# the claim is at FILE level, because that is what an agent opens: the implementation must beat EVERY
# symbol of the diagnostic's file, not just the class row. `constructor` is the message itself and is the
# harder of the two to pass, so asserting only against the class name would be the weaker gate.
impl="$( rankOf markStaleEntriesReclaimable )"
for sym in StaleEntryReclaimWarning constructor; do
  r="$( rankOf "$sym" )"
  if [ "$impl" -lt "$r" ]; then
    ok "the implementation (rank $impl) outranks the diagnostic's $sym (rank $r)"
  else
    no "the diagnostic's $sym (rank $r) still outranks the implementation (rank $impl)"
  fi
done

# a weight, not a filter: the diagnostic is still reachable by its own name.
if "$BIN" "$R" --for=StaleEntryReclaimWarning --format=candidates --top-k=5 2>/dev/null \
     | grep -q 'n="StaleEntryReclaimWarning"'; then
  ok "the diagnostic is down-weighted but still findable by name"
else
  no "the diagnostic vanished from a name query — the rule became a filter, not a weight"
fi

# the control: a three-line document whose subject term is dense is NOT what this rule demotes.
if "$BIN" "$R" --for='reclaimable count' --format=candidates --top-k=3 2>/dev/null \
     | grep -q 'n="reclaimableCount"'; then
  ok "a three-line document whose subject term is dense is not demoted — a ratio rule, not a length rule"
else
  no "a short dense document was demoted — the rule has become the length floor already rejected here"
fi

# inert at floor=100 by construction: a floor of 1.0 makes the factor identically 1.0 for every document.
RIPWIRE_TERMDENSITY_FLOOR=100 "$BIN" "$R" --for="$QUERY" --format=candidates --top-k=30 >"$TMP/off.xml" 2>/dev/null
if cmp -s "$TMP/off.xml" "$TMP/main.xml"; then
  no "floor=100 produced the SAME ranking as the shipped floor — this fixture cannot see the rule at all"
else
  ok "floor=100 is the rule off and it changes this fixture's ranking — the fixture is discriminating"
fi

# the shrink-only property the MaxScore bound rests on: pruned scoring must still agree with exhaustive.
RIPWIRE_NO_PRUNE=1 "$BIN" "$R" --for="$QUERY" --format=candidates --top-k=30 >"$TMP/exh.xml" 2>/dev/null
if cmp -s "$TMP/exh.xml" "$TMP/main.xml"; then
  ok "pruned and exhaustive scoring are byte-identical — the factor is shrink-only, so the bound holds"
else
  no "pruned and exhaustive scoring DISAGREE — a non-shrinking factor broke the MaxScore impact bound"
fi

# determinism, on the corpus that carries the population.
"$BIN" "$R" --for="$QUERY" --format=candidates --top-k=30 >"$TMP/det.xml" 2>/dev/null
if cmp -s "$TMP/det.xml" "$TMP/main.xml"; then
  ok "two runs byte-identical"
else
  no "two runs of the same query differ"
fi

[ "$fail" -eq 0 ] && echo "termdensitycheck: ALL PASS" || echo "termdensitycheck: FAILURES"
exit "$fail"
