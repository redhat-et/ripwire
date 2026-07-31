#!/usr/bin/env bash
# skilltruthcheck.sh — executable truth gate for claims shipped in ctxpack skills.
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${CTXPACK_BIN:-$ROOT/build/ctxpack}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
fail=0
ok(){ echo "  PASS  $1"; }
no(){ echo "  FAIL  $1"; fail=1; }

[ -x "$BIN" ] || { echo "no executable ctxpack binary: $BIN"; exit 2; }

SEC="$ROOT/skills/ctxpack-security-scan/SKILL.md"
EFF="$ROOT/skills/ctxpack-efficient/SKILL.md"
PERF="$ROOT/skills/ctxpack-perf-target/SKILL.md"
ROUTER="$ROOT/skills/ctxpack-router/SKILL.md"
# Aim at the copy Claude Code actually SERVES (.claude/skills), not the interop mirror. These two
# trees had silently diverged — .claude/ still claimed 14 MCP verbs and 7 quality kinds while this gate
# validated the current .agents/ copy and passed — i.e. the gate was checking the copy nobody loads.
# They are now one tree: .claude/skills holds the real files and .agents/skills is a symlink to it, so
# either path reads the same bytes and this assertion can no longer go green on an unserved copy.
ARCH="$ROOT/.claude/skills/ctxpack-arch/SKILL.md"

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
{ grep -q -- '--index-out=BASE' "$EFF" && grep -q 'lean.ctxpackcache' "$EFF" && grep -q 'rich.ctxpackcache' "$EFF"; } \
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
grep -q "$mcpCount MCP verbs" "$ARCH" \
    && ok "architecture skill matches the binary's $mcpCount MCP verbs" \
    || no "architecture skill does not match the binary's $mcpCount MCP verbs"
grep -q '10 kinds:' "$ARCH" \
    && ok "architecture skill documents the current 10 quality kinds" \
    || no "architecture skill still has a stale quality-kind count"
grep -q 'all 21 MCP verbs' "$ROOT/src/wrap.h" \
    && no "wrap source retains the stale 21-verb comment" \
    || ok "wrap source does not hardcode a stale MCP verb count"

[ "$fail" -eq 0 ] && echo "ALL PASS" || { echo "SOME CHECKS FAILED"; exit 1; }
