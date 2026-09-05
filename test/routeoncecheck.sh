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
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
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

# (a1) §L10b LOW tail: route= used to carry the old free-comment splicing form verbatim — a leading
# space then "[" (`route=" [routed: ..."`), a relic from when this string was spliced mid-sentence into a
# comment. Now that route= is the SOLE copy (per (a) above), the bracket that used to demarcate it inside
# prose just makes the attribute value start with a stray " [". Trimmed; the JSON "route" key (the same
# raw string) gets the same trim for free.
grep -oE 'route="[^"]*"' "$TMP/for.xml" | grep -q '^route=" \[' \
    && no "--for route= still starts with a stray space+bracket" \
    || ok "--for route= no longer starts with a stray space+bracket"
# verify-wave2 F6: L10b trimmed the LEADING " [" and left the TRAILING "]", so every route value on every
# dialect ended in an unbalanced bracket — and this gate asserted only the leading half, so it stayed green
# on a value it should reject. Both ends are asserted now; a bracket is a PAIR or it is neither.
grep -oE 'route="[^"]*"' "$TMP/for.xml" | grep -q ']"$' \
    && no "--for route= still ends with a stray unbalanced bracket" \
    || ok "--for route= ends with the route reason, not a bracket"
grep -oE 'route="routed: ' "$TMP/for.xml" >/dev/null \
    && ok "--for route= starts directly with 'routed: ' (no leading filler)" \
    || no "--for route= does not start with 'routed: ' — the trim moved the anchor, not just the space"

# (a2) --for on the CONCEPTUAL route (2026-08-23 serving-shape sweep): the same single-copy contract on
#      the COMPACT serving shape. (a)'s query anchors, so it pins the contract only on the auto body walk;
#      the compact bundle rebuilds its header through the same builder with a DIFFERENT enrichment plan
#      (its own legend, its own root attributes), which is exactly where a second 'routed:' copy could
#      reappear unobserved. Presence guard first (CONTRIBUTING §2): the query must actually serve compact.
"$BIN" fix --for="how does resolution work" --no-cache >"$TMP/forc.xml" 2>/dev/null
grep -q 'bundle="compact"' "$TMP/forc.xml" \
    && ok "--for conceptual presence: the query serves the COMPACT shape" \
    || no "--for conceptual presence: the query no longer serves bundle=\"compact\" — re-author it, the compact arm observes the wrong shape"
n="$( grep -o 'routed:' "$TMP/forc.xml" | wc -l | tr -d ' ' )"
if [ "$n" = 1 ]; then ok "--for (compact shape) emits 'routed:' exactly once (got $n)"; else no "--for (compact shape) emits 'routed:' $n times (want exactly 1 — the route= attribute)"; fi
grep -q 'route="' "$TMP/forc.xml" \
    && ok "--for (compact shape) keeps the route= attribute" \
    || no "--for (compact shape) lost the route= attribute"

# (b) --pack-task, same contract.
"$BIN" fix --pack-task="buildGraph" --no-cache >"$TMP/pt.xml" 2>/dev/null
n="$( grep -o 'routed:' "$TMP/pt.xml" | wc -l | tr -d ' ' )"
if [ "$n" = 1 ]; then ok "--pack-task emits 'routed:' exactly once (got $n)"; else no "--pack-task emits 'routed:' $n times (want exactly 1)"; fi
grep -q 'route="' "$TMP/pt.xml" \
    && ok "--pack-task keeps the route= attribute" \
    || no "--pack-task lost the route= attribute"
grep -oE 'route="[^"]*"' "$TMP/pt.xml" | grep -q '^route=" \[' \
    && no "--pack-task route= still starts with a stray space+bracket" \
    || ok "--pack-task route= no longer starts with a stray space+bracket"
grep -oE 'route="[^"]*"' "$TMP/pt.xml" | grep -q ']"$' \
    && no "--pack-task route= still ends with a stray unbalanced bracket" \
    || ok "--pack-task route= ends with the route reason, not a bracket"

# (c) JSON dialect: exactly one "route" key.
"$BIN" fix --for="buildGraph" --json --no-cache >"$TMP/for.json" 2>/dev/null
n="$( grep -o '"route"' "$TMP/for.json" | wc -l | tr -d ' ' )"
if [ "$n" = 1 ]; then ok '--for --json carries one "route" key'; else no "--for --json carries $n \"route\" keys (want 1)"; fi
grep -o '"route":"[^"]*"' "$TMP/for.json" | grep -q '"route":" \[' \
    && no "--for --json \"route\" value still starts with a stray space+bracket" \
    || ok "--for --json \"route\" value no longer starts with a stray space+bracket (same raw string as route=)"
grep -o '"route":"[^"]*"' "$TMP/for.json" | grep -q ']"$' \
    && no "--for --json \"route\" value still ends with a stray unbalanced bracket" \
    || ok "--for --json \"route\" value ends with the route reason, not a bracket"

# (c2) THE FOURTH DIALECT (verify-wave2 F6, rule 4 — family, not instance). route= is built at THREE sites:
# verbs_for.h (CLI --for), packtask.h's consumer of the same LensRanking (--pack-task), and mcpverbs.h TWICE
# (MCP `for`, MCP `pack_task`). This gate covered the CLI three and never the MCP pair, which is why the
# leading-bracket trim landed on four surfaces and was gated on three. Both ends, both MCP verbs.
mcp_route()   # $1 = verb name; prints the route value, empty if the payload carries none
{
    printf '%s\n%s\n' \
        '{"jsonrpc":"2.0","id":1,"method":"initialize"}' \
        '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"'"$1"'","arguments":{"path":"'"$TMP/fix"'","task":"buildGraph"}}}' \
        | "$BIN" --mcp 2>/dev/null | grep -o 'route=\\"[^\\"]*\\"' | head -1
}
for v in for pack_task; do
    r="$( mcp_route "$v" )"
    if [ -z "$r" ]; then
        no "MCP $v: no route= in the payload — the probe is stale (this verb routes and must echo it)"
    else
        case "$r" in
            'route=\" \['*) no "MCP $v route= still starts with a stray space+bracket" ;;
            *)              ok "MCP $v route= does not start with a stray space+bracket" ;;
        esac
        case "$r" in
            *']\"')  no "MCP $v route= still ends with a stray unbalanced bracket" ;;
            *)       ok "MCP $v route= ends with the route reason, not a bracket" ;;
        esac
    fi
done

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
