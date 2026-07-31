#!/usr/bin/env bash
# routeedgecheck.sh — the B6.3 HTTP-route / cross-service edge-kind gate.
#
#   test/routeedgecheck.sh                       # uses build/ripwire on test/routeedgefix
#   RIPWIRE_BIN=asan/ripwire test/routeedgecheck.sh
#
# Fixture test/routeedgefix/:
#   server/app.py      FastAPI: GET /users/{user_id} (get_user), POST /users (create_user),
#                       GET /orders/{order_id} (get_order); a deliberately AMBIGUOUS pair sharing one
#                       shape — GET /items/{item_id} (get_item_by_id) and GET /items/{name}
#                       (get_item_by_name); GET /unused (unused_handler, no caller anywhere).
#   server/express.js  Express: app.get('/widgets/:widgetId', getWidget).
#   client/client.ts   fetch/axios calls: loadUser -> /users/42 (template match), registerUser ->
#                       POST /users (exact match), loadOrder -> /orders/7 (template match),
#                       loadWidget -> /widgets/7 (cross-file JS server match), loadItem -> /items/42
#                       (the deliberately AMBIGUOUS case — must NOT match), loadNothing -> a path with
#                       no DEF (must stay unresolved), loadDynamic -> a template-literal path (a KNOWN
#                       non-detection — dynamic path strings are never guessed).
#
# Asserts, in BOTH invocation forms (single-root over test/routeedgefix, and multi-root over
# server+client as two separate roots — the cross-root evidence case DESIGN_multiRoot.md §3 requires):
#   (a) route DEF facts exist (the handler signatures appear in --for's <sigs>)
#   (b) route USE facts + the synthesized <route> edge, including a TEMPLATE-path match
#   (c) the deliberately ambiguous case produces NO edge (never a guess)
#   (d) an unresolved USE (no matching DEF) produces NO edge
#   (e) determinism x3 (byte-identical) + xmllint-clean output
#   (f) a route-free corpus (ripwire's OWN src/) is BYTE-IDENTICAL to a route-free baseline run — the
#       additive-only / G5 contract (no route detector ever perturbs a corpus with none).
# Exits non-zero on any failure.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${RIPWIRE_BIN:-$ROOT/build/ripwire}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"          # allow a repo-relative RIPWIRE_BIN
FIXTURE="$ROOT/test/routeedgefix"
SERVER="$FIXTURE/server"
CLIENT="$FIXTURE/client"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
echo "routeedgecheck: BIN=$BIN  FIXTURE=$FIXTURE"

forDump(){ "$BIN" "$@" --for="test" --no-cache 2>/dev/null; }

# ---------------------------------------------------------------------------------------------------
# form 1: SINGLE ROOT (server + client under one crawl root)
# ---------------------------------------------------------------------------------------------------
echo "-- single-root form --"
SINGLE="$( forDump "$FIXTURE" )"

# (e) determinism x3 + xmllint
"$BIN" "$FIXTURE" --for="test" --no-cache >"$TMP/s1" 2>/dev/null
"$BIN" "$FIXTURE" --for="test" --no-cache >"$TMP/s2" 2>/dev/null
"$BIN" "$FIXTURE" --for="test" --no-cache >"$TMP/s3" 2>/dev/null
diff -q "$TMP/s1" "$TMP/s2" >/dev/null && diff -q "$TMP/s2" "$TMP/s3" >/dev/null \
  && ok "single-root: determinism x3 (byte-identical)" || no "single-root: non-deterministic output"
printf '%s' "$SINGLE" | xmllint --noout - 2>/dev/null && ok "single-root: xmllint-clean" || no "single-root: xmllint failed"

# (a) route DEF facts: the handler signatures are visible
printf '%s' "$SINGLE" | grep -q 'def get_user(user_id: int):' \
  && ok "single-root: route DEF fact (get_user signature present)" || no "single-root: get_user signature missing"
printf '%s' "$SINGLE" | grep -q 'function getWidget(req, res)' \
  && ok "single-root: JS server route DEF fact (getWidget signature present)" || no "single-root: getWidget signature missing"

# (b) route USE facts + synthesized edges, including a TEMPLATE-path match
printf '%s' "$SINGLE" | grep -q '<route method="GET" path="/users/{user_id}" from="loadUser" to="get_user"/>' \
  && ok "single-root: template-path match GET /users/{user_id} loadUser->get_user" \
  || no "single-root: missing template-path edge loadUser->get_user"
printf '%s' "$SINGLE" | grep -q '<route method="POST" path="/users" from="registerUser" to="create_user"/>' \
  && ok "single-root: exact-literal match POST /users registerUser->create_user" \
  || no "single-root: missing exact-literal edge registerUser->create_user"
printf '%s' "$SINGLE" | grep -q '<route method="GET" path="/orders/{order_id}" from="loadOrder" to="get_order"/>' \
  && ok "single-root: template-path match GET /orders/{order_id} loadOrder->get_order" \
  || no "single-root: missing template-path edge loadOrder->get_order"
printf '%s' "$SINGLE" | grep -q '<route method="GET" path="/widgets/:widgetId" from="loadWidget" to="getWidget"/>' \
  && ok "single-root: JS-server/JS-client cross-file match GET /widgets/:widgetId loadWidget->getWidget" \
  || no "single-root: missing cross-file JS edge loadWidget->getWidget"

# (c) the deliberately AMBIGUOUS case (loadItem -> /items/42, matches BOTH item DEFs) — NO edge
printf '%s' "$SINGLE" | grep -q 'to="get_item_by_id"' \
  && no "single-root: ambiguous case wrongly resolved to get_item_by_id" \
  || ok "single-root: ambiguous case (loadItem) produced NO edge to get_item_by_id"
printf '%s' "$SINGLE" | grep -q 'to="get_item_by_name"' \
  && no "single-root: ambiguous case wrongly resolved to get_item_by_name" \
  || ok "single-root: ambiguous case (loadItem) produced NO edge to get_item_by_name"

# (d) unresolved USE (loadNothing -> a path with no DEF) — NO edge, never a guess
printf '%s' "$SINGLE" | grep -q 'does-not-exist' \
  && no "single-root: unresolved USE wrongly appears in a route edge" \
  || ok "single-root: unresolved USE (loadNothing) produced NO edge"

# unused DEF (no caller) and the dynamic template-literal USE (a KNOWN non-detection) both correctly
# produce no edge — same "from"/"to" absence check, folded into the count below.
EDGECOUNT="$( printf '%s' "$SINGLE" | grep -o '<route ' | wc -l | tr -d ' ' )"
[ "$EDGECOUNT" = "4" ] && ok "single-root: exactly 4 synthesized edges (no more, no fewer)" \
  || no "single-root: expected 4 route edges, got $EDGECOUNT"

# ---------------------------------------------------------------------------------------------------
# form 2: MULTI-ROOT (server and client as two SEPARATE roots — the cross-root evidence case)
# ---------------------------------------------------------------------------------------------------
echo "-- multi-root form --"
MULTI="$( forDump "$SERVER" "$CLIENT" )"

"$BIN" "$SERVER" "$CLIENT" --for="test" --no-cache >"$TMP/m1" 2>/dev/null
"$BIN" "$SERVER" "$CLIENT" --for="test" --no-cache >"$TMP/m2" 2>/dev/null
"$BIN" "$SERVER" "$CLIENT" --for="test" --no-cache >"$TMP/m3" 2>/dev/null
diff -q "$TMP/m1" "$TMP/m2" >/dev/null && diff -q "$TMP/m2" "$TMP/m3" >/dev/null \
  && ok "multi-root: determinism x3 (byte-identical)" || no "multi-root: non-deterministic output"
printf '%s' "$MULTI" | xmllint --noout - 2>/dev/null && ok "multi-root: xmllint-clean" || no "multi-root: xmllint failed"

printf '%s' "$MULTI" | grep -q '<route method="GET" path="/users/{user_id}" from="loadUser" to="get_user"/>' \
  && ok "multi-root: cross-root template-path match GET /users/{user_id} loadUser->get_user" \
  || no "multi-root: missing cross-root edge loadUser->get_user"
printf '%s' "$MULTI" | grep -q '<route method="POST" path="/users" from="registerUser" to="create_user"/>' \
  && ok "multi-root: cross-root exact-literal match POST /users registerUser->create_user" \
  || no "multi-root: missing cross-root edge registerUser->create_user"
printf '%s' "$MULTI" | grep -q '<route method="GET" path="/orders/{order_id}" from="loadOrder" to="get_order"/>' \
  && ok "multi-root: cross-root template-path match GET /orders/{order_id} loadOrder->get_order" \
  || no "multi-root: missing cross-root edge loadOrder->get_order"
printf '%s' "$MULTI" | grep -q '<route method="GET" path="/widgets/:widgetId" from="loadWidget" to="getWidget"/>' \
  && ok "multi-root: cross-root match GET /widgets/:widgetId loadWidget->getWidget" \
  || no "multi-root: missing cross-root edge loadWidget->getWidget"

printf '%s' "$MULTI" | grep -q 'to="get_item_by_id"' \
  && no "multi-root: ambiguous case wrongly resolved to get_item_by_id" \
  || ok "multi-root: ambiguous case (loadItem) produced NO edge to get_item_by_id"
printf '%s' "$MULTI" | grep -q 'to="get_item_by_name"' \
  && no "multi-root: ambiguous case wrongly resolved to get_item_by_name" \
  || ok "multi-root: ambiguous case (loadItem) produced NO edge to get_item_by_name"
printf '%s' "$MULTI" | grep -q 'does-not-exist' \
  && no "multi-root: unresolved USE wrongly appears in a route edge" \
  || ok "multi-root: unresolved USE (loadNothing) produced NO edge"

MEDGECOUNT="$( printf '%s' "$MULTI" | grep -o '<route ' | wc -l | tr -d ' ' )"
[ "$MEDGECOUNT" = "4" ] && ok "multi-root: exactly 4 synthesized edges (no more, no fewer)" \
  || no "multi-root: expected 4 route edges, got $MEDGECOUNT"

# ---------------------------------------------------------------------------------------------------
# (f) additive-only / G5: a route-free corpus is BYTE-IDENTICAL whether or not the B6.3 detectors ran.
#     ripwire's own src/ (pure C++/headers) has zero routes — its default map is not the --for/--around
#     path this feature touches, so this checks the cheapest reliable proxy: two back-to-back --no-cache
#     runs agree, AND neither run's default map contains a <routes> tag (the block is additive-only,
#     gated on g.routeEdges non-empty — G5 never fires on a route-free tree).
# ---------------------------------------------------------------------------------------------------
echo "-- additive-only (route-free corpus) --"
"$BIN" "$ROOT/src" --no-cache >"$TMP/src1" 2>/dev/null
"$BIN" "$ROOT/src" --no-cache >"$TMP/src2" 2>/dev/null
diff -q "$TMP/src1" "$TMP/src2" >/dev/null && ok "additive-only: ripwire's own src/ default map is deterministic" \
  || no "additive-only: src/ default map is non-deterministic"
grep -q '<routes>' "$TMP/src1" && no "additive-only: <routes> leaked into a route-free corpus's default map" \
  || ok "additive-only: no <routes> tag on a route-free corpus"

echo
[ "$fail" = "0" ] && { echo "routeedgecheck: ALL PASS"; exit 0; } || { echo "routeedgecheck: FAILURES"; exit 1; }
