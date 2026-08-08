#!/usr/bin/env bash
# skilltruthcheck.sh — executable truth gate for claims shipped in ripwire skills.
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${RIPWIRE_BIN:-$ROOT/build/ripwire}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
fail=0
ok(){ echo "  PASS  $1"; }
no(){ echo "  FAIL  $1"; fail=1; }

[ -x "$BIN" ] || { echo "no executable ripwire binary: $BIN"; exit 2; }

SEC="$ROOT/skills/ripwire-security-scan/SKILL.md"
EFF="$ROOT/skills/ripwire-efficient/SKILL.md"
PERF="$ROOT/skills/ripwire-perf-target/SKILL.md"
ROUTER="$ROOT/skills/ripwire-router/SKILL.md"
# The catalog-count assertions used to aim at an architecture skill that lived only in the author's
# personal agent config and never shipped with the repo. A gate must assert against a file a clone
# actually has, so they now aim at the two SHIPPED skills that make the same claims: the MCP skill
# names the verb count and the quality skill names the kind count. Same claim, same teeth, on files
# every reader can see.
MCPSKILL="$ROOT/skills/ripwire-mcp/SKILL.md"
QUAL="$ROOT/skills/ripwire-quality-bar/SKILL.md"

# JSON is indexed and literal retrieval works; semantic MCP-config auditing remains a manual review.
jsonOut="$( "$BIN" "$ROOT/test/jsonfix" --grep=dependencies --no-cache 2>/dev/null )"
{ grep -q 'package.json' <<<"$jsonOut" && grep -q 'dependencies' <<<"$jsonOut"; } \
    && ok "JSON config keys are retrievable with --grep" \
    || no "--grep failed to retrieve the JSON fixture"
if grep -qiE "doesn.t index JSON|--grep.? can.t find" "$SEC"; then
    no "security skill still claims JSON is not indexed/retrievable"
else
    ok "security skill does not deny JSON retrieval"
fi
{ grep -qi 'semantic' "$SEC" && grep -qi 'manual' "$SEC"; } \
    && ok "security skill keeps semantic MCP-config review manual" \
    || no "security skill does not state the manual semantic-review boundary"

# Portable artifact guidance must describe the complete two-artifact generation and consumption workflow.
{ grep -q -- '--index-out=BASE' "$EFF" && grep -q 'lean.ripwirecache' "$EFF" && grep -q 'rich.ripwirecache' "$EFF"; } \
    && ok "efficient skill documents --index-out lean/rich artifacts" \
    || no "efficient skill omits the complete --index-out lean/rich workflow"

# Static graph/maintenance metrics are hypotheses, never runtime profiles.
stalePerf='call frequency proxy|first profiling targets|where should I optimize before profiling|hotspot × hot-path ranking'
if grep -qiE "$stalePerf" "$PERF" "$ROUTER"; then
    no "performance routing still presents structural metrics as runtime evidence"
else
    ok "performance routing does not label structural metrics as runtime heat"
fi
{ grep -qiE 'benchmark|profil' "$PERF" && grep -qiE 'structural.*not.*runtime|not.*runtime.*structural' "$PERF"; } \
    && ok "performance skill starts from measurement and states the structural boundary" \
    || no "performance skill lacks measure-first / structural-not-runtime guidance"

# Counts in the architecture skill must match the binary-owned catalogs.
mcpCount="$( "$BIN" wrap codex --force 2>/dev/null | sed -n 's/.*(\([0-9][0-9]*\) total).*/\1/p' | head -1 )"
[ -n "$mcpCount" ] || mcpCount=0
grep -q "$mcpCount MCP verbs" "$MCPSKILL" \
    && ok "MCP skill matches the binary's $mcpCount MCP verbs" \
    || no "MCP skill does not match the binary's $mcpCount MCP verbs"
grep -q '10 kinds' "$QUAL" \
    && ok "quality skill documents the current 10 quality kinds" \
    || no "quality skill still has a stale quality-kind count"
grep -q 'all 21 MCP verbs' "$ROOT/src/wrap.h" \
    && no "wrap source retains the stale 21-verb comment" \
    || ok "wrap source does not hardcode a stale MCP verb count"

# 2026-08-08 audit M3/L4/M5: --help must document ev=/ev_why= (essential complexity) and humps=/deep=/
# locals= (the nesting profile) next to amp=/ppalt=, and --lint's help line must name the cache-* pack.
# Both claims are executed against the binary, not just grepped as prose: --metrics really emits ev= on a
# known guard-return function, and --lint really fires a cache-* rule on the cachelint fixture.
helpOut="$( "$BIN" --help 2>/dev/null )"
{ grep -q 'ev=N essential complexity' <<<"$helpOut" && grep -q 'ev_why=' <<<"$helpOut"; } \
    && ok "--help documents ev=/ev_why= (essential complexity) next to amp=/ppalt=" \
    || no "--help does not document ev=/ev_why="
{ grep -q 'humps=' <<<"$helpOut" && grep -q 'deep=' <<<"$helpOut" && grep -q 'locals=' <<<"$helpOut"; } \
    && ok "--help documents the humps=/deep=/locals= nesting profile" \
    || no "--help does not document humps=/deep=/locals="
grep -q -- '--lint .*cache-\* data-layout' <<<"$helpOut" \
    && ok "--help's --lint line names the cache-* data-layout pack" \
    || no "--help's --lint line does not name the cache-* pack"

pushBackRow="$( "$BIN" "$ROOT" --metrics --no-cache --top-k=5000 2>/dev/null | grep -o '<s[^>]*n="push_back"[^>]*svector\.h::svector::push_back[^>]*>' | head -1 )"
{ [ -n "$pushBackRow" ] && grep -q 'ev="2"' <<<"$pushBackRow" && grep -q 'ev_why="guard-return:1"' <<<"$pushBackRow"; } \
    && ok "--metrics actually emits ev=/ev_why= on a known guard-return function (svector::push_back)" \
    || no "--metrics did not emit the expected ev=/ev_why= on svector::push_back"

cacheLintOut="$( "$BIN" "$ROOT/test/cachefix" --lint --no-cache 2>/dev/null )"
grep -q 'rule="cache-gather-subscript"' <<<"$cacheLintOut" \
    && ok "--lint actually fires a cache-* rule (cache-gather-subscript) on the cachelint fixture" \
    || no "--lint did not fire any cache-* rule on test/cachefix"

# The three skills touched for M3/M5/L6 must carry the claims they now make, on the shipped files.
FRESH="$ROOT/skills/ripwire-fresh-eyes/SKILL.md"
PERF2="$ROOT/skills/ripwire-perf-target/SKILL.md"
QUAL2="$ROOT/skills/ripwire-quality-bar/SKILL.md"
grep -q '`ev=`' "$QUAL2" \
    && ok "quality-bar's shape -> refactor playbook names ev=" \
    || no "quality-bar's playbook does not name ev="
grep -q '`ev=`' "$FRESH" \
    && ok "fresh-eyes' profile-reading paragraph names ev=" \
    || no "fresh-eyes does not name ev="
grep -qiF 'cache-\* pack' "$PERF2" \
    && ok "perf-target names the cache-* pack next to --field-affinity" \
    || no "perf-target does not name the cache-* pack"
{ grep -qi 'ppalt' "$FRESH" && grep -qi 'ppalt' "$PERF2"; } \
    && ok "fresh-eyes and perf-target both carry a ppalt= discount caveat" \
    || no "fresh-eyes and/or perf-target is missing the ppalt= discount caveat"

[ "$fail" -eq 0 ] && echo "ALL PASS" || { echo "SOME CHECKS FAILED"; exit 1; }
