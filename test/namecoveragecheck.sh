#!/usr/bin/env bash
# namecoveragecheck.sh — gate for the NAME-COVERAGE FLOOR on the conceptual --for route.
#
# A small registration class — one that installs a hook and does nothing else — can carry most of a task's
# content words in its own NAME and still never surface: it has near-zero graph centrality and near-zero
# body text, so structurally central symbols that share FEWER of those words displace it. Typing its
# identifier finds it at rank 1 through the name-exact route; asking for it in a sentence does not.
# lexical.h applyNameCoverageFloor floors such a symbol into the head of the bundle, independently of
# centrality, and discloses that it did.
#
# RED (the binary at the lane base) — measured, not assumed: the covering class is ABSENT from the top 5
# for "where are widget ids assigned deterministically"; five term-dense functions with generic names take
# the slots. GREEN (this gate): it is in the top 5, it did NOT take rank 1 (the ladder starts below the
# ranker's own best answer — a floor must not become a boost), the lift is DISCLOSED in the header, the
# note is ABSENT when nothing covers the task, a TWO-content-word query is refused outright even though
# the same class covers both of its words (on a query that short, "half the content words" is one word —
# a coincidence, not a name that spells the task), the unrouted lens never runs it, and the name-exact
# route is untouched.
#
# Usage:  RIPWIRE_BIN=build/ripwire bash test/namecoveragecheck.sh   |   RIPWIRE_BIN=asan/ripwire bash …
# Exits non-zero on any failure. Does NOT edit regression.sh.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
echo "namecoveragecheck: BIN=$BIN"

TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
R="$TMP/repo"; mkdir -p "$R/src/ids" "$R/src/core"

QUERY='where are widget ids assigned deterministically'

# ── the corpus ───────────────────────────────────────────────────────────────────────────────────────
# 1) the registration class under test: its NAME spells widget + ids + deterministic, its body is three
#    lines, and nothing in the tree calls it. Exactly the shape that loses on centrality.
{
  echo 'class DeterministicWidgetIdsPlugin {'
  echo '  apply(compiler) {'
  echo '    compiler.hooks.compilation.tap("plugin", (c) => this.run(c));'
  echo '  }'
  echo '}'
} >"$R/src/ids/plugin.js"

# 2) the competition: term-dense, well-connected, generically named. Each repeats the query's vocabulary
#    far more often than the class above, and they call each other so centrality is on their side. Their
#    densities DIFFER on purpose — five identical bodies would score within a hair of each other, and a
#    fixture where the whole top-5 is one flat cluster tests the ladder's step size, not the rule.
i=0
while [ $i -lt 5 ]; do
  {
    echo "function computeOrdering$i(items) {"
    echo "  // widget ids are assigned here; the widget id assignment is deterministic across runs,"
    echo "  // and every widget carries the id it was assigned deterministically on the previous run."
    j=0; while [ $j -lt $(( 12 - 2 * i )) ]; do
      echo "  const widget$j = items[$j].widget; const assignedId$j = widget$j.ids.assigned;"
      j=$(( j + 1 ))
    done
    if [ $i -lt 4 ]; then echo "  return computeOrdering$(( i + 1 ))(items);"; else echo '  return items;'; fi
    echo '}'
  } >"$R/src/core/ordering$i.js"
  i=$(( i + 1 ))
done
{
  echo 'function buildEverything(items) {'
  echo '  return computeOrdering0(items);'
  echo '}'
} >"$R/src/core/entry.js"

# ── probes ───────────────────────────────────────────────────────────────────────────────────────────
CAND="$TMP/cand.xml"; LENS="$TMP/lens.xml"
"$BIN" "$R" --for="$QUERY" --format=candidates --top-k=10 >"$CAND" 2>/dev/null || { echo "binary failed"; exit 2; }
"$BIN" "$R" --for="$QUERY" >"$LENS" 2>/dev/null || { echo "binary failed"; exit 2; }
tr '>' '\n' <"$CAND" | grep -o 'r="[0-9]*" s="[0-9.]*" n="[^"]*"' \
  | sed -E 's/r="([0-9]*)" s="([0-9.]*)" n="([^"]*)"/\3 \1/' >"$TMP/ranks"
rankOf(){ awk -v n="$1" '$1==n {print $2; found=1; exit} END{ if(!found) print "" }' "$TMP/ranks"; }

# presence guard: the competition must actually be in the ranking, or "the class is in the top 5" would
# pass on an empty corpus.
compRanked="$( grep -c '^computeOrdering' "$TMP/ranks" || true )"
if [ "$compRanked" -ge 3 ]; then
  ok "presence guard — $compRanked term-dense competitors are ranked, so the contest is real"
else
  no "presence guard — only $compRanked competitors ranked; the fixture is not exercising the rule"
  sed 's/^/          /' "$TMP/ranks"; exit 1
fi

cov="$( rankOf DeterministicWidgetIdsPlugin )"
if [ -n "$cov" ] && [ "$cov" -le 5 ]; then
  ok "the covering registration class reaches the top 5 (rank $cov) despite zero callers and a 3-line body"
else
  no "the covering registration class is at rank '${cov:-none}' — the floor did not lift it into the top 5"
fi
if [ -n "$cov" ] && [ "$cov" -gt 1 ]; then
  ok "it did NOT take rank 1 — the ladder starts below the ranker's own best answer"
else
  no "it took rank 1: the floor became a boost and displaced the ranker's own top answer"
fi

if grep -q 'name coverage: 1 symbol whose own name spells' "$LENS"; then
  ok "the lift is disclosed in the header, with the count and the task's content-word total"
else
  no "the lift happened silently — no name-coverage clause in the header"
  tr '>' '\n' <"$LENS" | grep -m1 'routed:' | sed 's/^/          /'
fi

# ABSENT when nothing covers: a conceptual query on the same corpus whose words no symbol name spells.
if "$BIN" "$R" --for='how is the compilation hook tapped by a plugin instance' 2>/dev/null | grep -q 'name coverage:'; then
  no "the note appears on a query no symbol name covers — the rule is firing when it should be inert"
else
  ok "no note on a query no symbol name covers — inert, not always-on"
fi

# a TWO-content-word query is refused by the minimum-content-words rule, even though the class under test
# covers BOTH of its words — the arm that separates "a name that spells the task" from a coincidence.
if "$BIN" "$R" --for='widget deterministically' 2>/dev/null | grep -q 'name coverage:'; then
  no "a two-content-word query lifted — half of two words is one word, which is a coincidence"
else
  ok "a two-content-word query is refused, though the class covers both of its words"
fi

# the unrouted lens (--no-route) never runs the floor: nothing chose a route, so there is no route to serve.
if "$BIN" "$R" --for="$QUERY" --no-route 2>/dev/null | grep -q 'name coverage:'; then
  no "the floor ran through --no-route — it must be conceptual-route only"
else
  ok "the floor does not run on the unrouted lens"
fi

# the name-exact route is untouched: typing the identifier still lands it at rank 1, with no coverage note
# (that route resolved its own anchor and must not be second-guessed by this rule).
NE="$( "$BIN" "$R" --for=DeterministicWidgetIdsPlugin --format=candidates --top-k=3 2>/dev/null )"
if printf '%s' "$NE" | grep -q 'route="name-exact"' && printf '%s' "$NE" | grep -q 'r="1" s="[0-9.]*" n="DeterministicWidgetIdsPlugin"'; then
  ok "the name-exact route still lands the class at rank 1"
else
  no "the name-exact route changed shape"
  printf '%s' "$NE" | tr '>' '\n' | grep -m3 'cand r=' | sed 's/^/          /'
fi
if "$BIN" "$R" --for=DeterministicWidgetIdsPlugin 2>/dev/null | grep -q 'name coverage:'; then
  no "the floor ran on the name-exact route — it must not fight the anchor that route just resolved"
else
  ok "the floor is silent on the name-exact route"
fi

[ "$fail" -eq 0 ] && echo "namecoveragecheck: ALL PASS" || echo "namecoveragecheck: FAILURES"
exit "$fail"
