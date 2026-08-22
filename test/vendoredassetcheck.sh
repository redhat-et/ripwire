#!/usr/bin/env bash
# vendoredassetcheck.sh — gate for the VENDORED/GENERATED-ASSET de-prioritization in the ranking lenses.
#
# A shipped-but-not-authored file — a vendored front-end asset, a numbered database migration — recites a
# subsystem's vocabulary in a very short document, which is exactly the shape BM25's length normalization
# rewards most. Measured on outside repositories, such files took top slots in task bundles that had
# nothing to do with them, and the file an agent would actually edit never appeared. src/filter.h now
# classifies them into the SAME de-prioritized tier (0.35) that decks and generated captures already
# carried: down-weighted, never dropped.
#
# THIS TREE CONTAINS NEITHER FAMILY — no */static/*, no numbered migration — so a gate written against the
# repo itself would be green while inert, which is the failure CONTRIBUTING.md §2 names. The corpus below
# is synthetic on purpose and carries the population directly.
#
# RED (the binary at the lane base, before the filter.h change) — measured, not assumed:
#   for "cache eviction expiry ttl sweep" the numbered migration is #1 and the vendored static/ asset #3,
#   while the real src/ implementation lands LAST behind both — each offender has a three-line body.
# GREEN (this gate): the real implementation outranks both; each demoted file is still findable by its own
#   name (de-prioritization, not exclusion); and the two NEAR MISSES that must NOT be demoted — an
#   UNnumbered migrations/__init__.py and a staticfiles/ directory whose name merely begins with "static" —
#   still outrank their demoted twins, which carry byte-identical bodies.
#
# The last arm pins WHY filter.h carries no *.min.js rule: the crawl denylists that filename outright
# (ingest.cpp isDenylistedName), so such a file never becomes a symbol and a ranking tier for it would be
# a dead table row. If that ever changes this arm goes red, and the tier becomes worth adding.
#
# Usage:  RIPWIRE_BIN=build/ripwire bash test/vendoredassetcheck.sh   |   RIPWIRE_BIN=asan/ripwire bash …
# Exits non-zero on any failure. Does NOT edit regression.sh.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
echo "vendoredassetcheck: BIN=$BIN"

TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
R="$TMP/repo"; mkdir -p "$R/src" "$R/static/js" "$R/migrations" "$R/assets" "$R/staticfiles"

QUERY='cache eviction expiry ttl sweep'

# ── the corpus ───────────────────────────────────────────────────────────────────────────────────────
# 1) the real implementation. It EXPLAINS the subsystem across a long body, which is precisely why it
#    loses a term-density contest to a three-line file that merely names the same things.
{
  echo '/**'
  echo ' * Walk the cache and drop entries whose ttl has passed. The eviction sweep is the only writer'
  echo ' * of the expiry index, so callers never take the cache lock themselves.'
  echo ' */'
  echo 'function evictExpiredEntries(cache, now) {'
  i=0; while [ $i -lt 30 ]; do
    echo "  // step $i of the sweep: the owner decides, the caller observes, and the bookkeeping stays local"
    echo "  const bucket$i = cache.buckets[$i];"
    echo "  if (bucket$i && bucket$i.deadline <= now) { cache.drop(bucket$i); }"
    i=$(( i + 1 ))
  done
  echo '  return cache.size;'
  echo '}'
} >"$R/src/evictor.js"

# 2) the two shipped-but-not-authored files. Each is tiny and each recites the query's vocabulary.
{
  echo 'function evictionTooltipWidget(el) {'
  echo '  return el.title = "cache eviction: ttl expiry sweep runs hourly";'
  echo '}'
} >"$R/static/js/shortcuts.js"
{
  echo 'class MigrationCacheTtlColumn:'
  echo '    """cache eviction ttl expiry sweep column"""'
  echo '    operations = ["cache", "eviction", "expiry", "ttl", "sweep"]'
} >"$R/migrations/0007_cache_ttl.py"

# 3) the two NEAR MISSES, each a byte-identical twin of a demoted file except for its path. An UNnumbered
#    file in migrations/ is ordinary source, and staticfiles/ is not static/ — if either is demoted, the
#    classifier is matching a prefix rather than a whole component, and these two rows say so.
{
  echo 'class MigrationRegistryCacheTtl:'
  echo '    """cache eviction ttl expiry sweep column"""'
  echo '    operations = ["cache", "eviction", "expiry", "ttl", "sweep"]'
} >"$R/migrations/__init__.py"
{
  echo 'function evictionFinderWidget(el) {'
  echo '  return el.title = "cache eviction: ttl expiry sweep runs hourly";'
  echo '}'
} >"$R/staticfiles/finders.js"

# 4) the dead-rule witness: a minified bundle the crawl removes before ranking ever sees it.
{
  echo 'function evictionMinifiedHelper(c){return c.cache_eviction_expiry_ttl_sweep;}'
} >"$R/assets/app.min.js"

# ── the probe: one ranked candidate list, parsed into "name rank score" rows ──────────────────────────
CAND="$TMP/cand.xml"
"$BIN" "$R" --for="$QUERY" --format=candidates --top-k=40 >"$CAND" 2>"$TMP/err" || { echo "binary failed"; cat "$TMP/err"; exit 2; }
tr '>' '\n' <"$CAND" | grep -o 'r="[0-9]*" s="[0-9.]*" n="[^"]*"' \
  | sed -E 's/r="([0-9]*)" s="([0-9.]*)" n="([^"]*)"/\3 \1 \2/' >"$TMP/ranks"

rankOf(){ awk -v n="$1" '$1==n {print $2; found=1; exit} END{ if(!found) print "" }' "$TMP/ranks"; }

# presence guard FIRST — every assertion below compares ranks, and a missing row would let a comparison
# pass by vacuity. All five ranked symbols must be present before anything is asserted about them.
missing=''
for s in evictExpiredEntries evictionTooltipWidget MigrationCacheTtlColumn \
         MigrationRegistryCacheTtl evictionFinderWidget; do
  [ -n "$( rankOf "$s" )" ] || missing="$missing $s"
done
if [ -n "$missing" ]; then
  no "presence guard — these symbols never reached the ranked list, so nothing below could be tested:$missing"
  printf '        ranked rows were:\n'; sed 's/^/          /' "$TMP/ranks"
  exit 1
fi
ok "presence guard — all five probe symbols are indexed and ranked"

real="$( rankOf evictExpiredEntries )"
for pair in "evictionTooltipWidget:a vendored static/ asset" \
            "MigrationCacheTtlColumn:a numbered migration"; do
  sym="${pair%%:*}"; what="${pair#*:}"
  r="$( rankOf "$sym" )"
  if [ "$real" -lt "$r" ]; then
    ok "the real implementation (rank $real) outranks $what (rank $r)"
  else
    no "$what (rank $r) still outranks the real implementation (rank $real)"
  fi
done

# de-prioritization, NOT exclusion: each demoted file is still reachable by its own name.
for sym in evictionTooltipWidget MigrationCacheTtlColumn; do
  if "$BIN" "$R" --for="$sym" --format=candidates --top-k=5 2>/dev/null | grep -q "n=\"$sym\""; then
    ok "$sym is de-prioritized but still findable by name"
  else
    no "$sym vanished from a name query — the tier is a filter, not a down-weight"
  fi
done

# the two near misses, each against its byte-identical demoted twin.
mig="$( rankOf MigrationCacheTtlColumn )"; migOk="$( rankOf MigrationRegistryCacheTtl )"
if [ "$migOk" -lt "$mig" ]; then
  ok "an UNnumbered migrations/ file (rank $migOk) outranks its numbered twin (rank $mig)"
else
  no "migrations/__init__.py (rank $migOk) was demoted alongside the numbered file (rank $mig)"
fi
sta="$( rankOf evictionTooltipWidget )"; staOk="$( rankOf evictionFinderWidget )"
if [ "$staOk" -lt "$sta" ]; then
  ok "staticfiles/ (rank $staOk) is not static/ (rank $sta) — the component match is whole, not a prefix"
else
  no "staticfiles/ (rank $staOk) was demoted like static/ (rank $sta) — prefix match, not component match"
fi

# the dead-rule witness. A *.min.js file is denylisted by NAME at crawl time, so it is not a symbol at all
# — which is why filter.h carries no minified-bundle rule. If this goes red, add one.
if [ -z "$( rankOf evictionMinifiedHelper )" ] && ! "$BIN" "$R" --for=evictionMinifiedHelper --format=candidates --top-k=5 2>/dev/null | grep -q 'n="evictionMinifiedHelper"'; then
  ok "a *.min.js file never becomes a symbol — the crawl denylist makes a ranking tier for it dead code"
else
  no "a *.min.js file IS now indexed — filter.h needs the minified-bundle rule this gate says is unnecessary"
fi

[ "$fail" -eq 0 ] && echo "vendoredassetcheck: ALL PASS" || echo "vendoredassetcheck: FAILURES"
exit "$fail"
