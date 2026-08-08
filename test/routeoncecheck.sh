#!/usr/bin/env bash
# routeoncecheck.sh — G4: the route disclosure is emitted ONCE per bundle, not twice.
#
#   test/routeoncecheck.sh                        # uses build/ripwire on test/routefix
#   RIPWIRE_BIN=asan/ripwire test/routeoncecheck.sh
#
# WHY (density audit 2026-08-08, lane D finding L1). A routed --for / --pack-task bundle used to carry the
# IDENTICAL "routed: ..." text twice — once verbatim in the root's route= attribute (the machine surface) and
# once scrubbed inside the legend comment — ~230-260 duplicated bytes on EVERY routed call, saying the same
# thing to the same reader. The attribute is the copy that stays: it is verbatim (the comment copy was
# xmlCommentText-scrubbed, i.e. lossy), it is machine-addressable, and the ceiling ladder already treats it
# as "the only copy whose drop costs unique information" (serialize.h climbCeilingLadder rung (c)) — a claim
# that was false while the comment held a second copy. This gate pins the fix:
#   (a) --for on a routed (identifier) query: "routed:" appears EXACTLY once, and it is the route= attribute.
#   (b) --pack-task, same query: same single-copy contract.
#   (c) the JSON dialect of --for: exactly one "route" key (it was never duplicated — pinned so it stays).
#   (d) --query keeps its leading "<!-- routed: ... -->" comment: the default map has NO route= attribute,
#       so the comment there is the ONLY copy, not a duplicate — this gate must never "fix" it away.
#   (e) determinism: two routed --for runs are byte-identical.
# The fixture is copied to a tmp dir OUTSIDE any git repo and scanned via a RELATIVE path, so output carries
# no churn attrs and no absolute paths. Exits non-zero on any failure.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${RIPWIRE_BIN:-$ROOT/build/ripwire}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"          # allow a repo-relative RIPWIRE_BIN
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN (build first)"; exit 1; }

mkdir -p "$TMP/fix"
cp "$ROOT"/test/routefix/*.cpp "$TMP/fix/"
cd "$TMP"

# (a) --for, routed: the disclosure text appears exactly once, and the attribute carries it.
"$BIN" fix --for="buildGraph" --no-cache >"$TMP/for.xml" 2>/dev/null
n="$( grep -o 'routed:' "$TMP/for.xml" | wc -l | tr -d ' ' )"
if [ "$n" = 1 ]; then ok "--for emits 'routed:' exactly once (got $n)"; else no "--for emits 'routed:' $n times (want exactly 1 — the route= attribute)"; fi
grep -q 'route="' "$TMP/for.xml" \
    && ok "--for keeps the route= attribute (the machine-readable copy)" \
    || no "--for lost the route= attribute — the surviving copy must be the ATTRIBUTE, not the comment"

# (b) --pack-task, same contract.
"$BIN" fix --pack-task="buildGraph" --no-cache >"$TMP/pt.xml" 2>/dev/null
n="$( grep -o 'routed:' "$TMP/pt.xml" | wc -l | tr -d ' ' )"
if [ "$n" = 1 ]; then ok "--pack-task emits 'routed:' exactly once (got $n)"; else no "--pack-task emits 'routed:' $n times (want exactly 1)"; fi
grep -q 'route="' "$TMP/pt.xml" \
    && ok "--pack-task keeps the route= attribute" \
    || no "--pack-task lost the route= attribute"

# (c) JSON dialect: exactly one "route" key.
"$BIN" fix --for="buildGraph" --json --no-cache >"$TMP/for.json" 2>/dev/null
n="$( grep -o '"route"' "$TMP/for.json" | wc -l | tr -d ' ' )"
if [ "$n" = 1 ]; then ok '--for --json carries one "route" key'; else no "--for --json carries $n \"route\" keys (want 1)"; fi

# (d) --query's leading routed comment is the ONLY copy there (no route= attribute on the default map) — keep it.
"$BIN" fix --query="buildGraph" --no-cache >"$TMP/q.xml" 2>/dev/null
grep -q '<!-- routed:' "$TMP/q.xml" \
    && ok "--query keeps its leading routed comment (sole copy on the default map)" \
    || no "--query lost its routed comment — that one is NOT a duplicate (the map has no route= attribute)"
grep -q 'route="' "$TMP/q.xml" \
    && no "--query grew a route= attribute (the map header is serialize's, not the lens's)" \
    || ok "--query map carries no route= attribute (comment stays the sole copy)"

# (e) determinism of the routed --for.
"$BIN" fix --for="buildGraph" --no-cache >"$TMP/for2.xml" 2>/dev/null
diff -q "$TMP/for.xml" "$TMP/for2.xml" >/dev/null \
    && ok "routed --for deterministic (byte-identical twice)" \
    || no "routed --for output differs across two runs"

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit $fail
