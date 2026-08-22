#!/usr/bin/env bash
# skilltruthcheck.sh — executable truth gate for claims shipped in ripwire skills.
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
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

# ── the MIXED fixture (wave-3 verifier P2-5) ──────────────────────────────────────────────────────────
# The arm above runs against test/jsonfix, a JSON MONOCULTURE. Under span tiers a monoculture is exactly
# the corpus in which the claim cannot fail: with no code tier anywhere, the ladder falls through and the
# JSON row is served no matter what the policy is. The gate whose job is to pin "JSON config keys are
# retrievable" was therefore structurally incapable of observing the regression it exists to catch, which
# is why the config-language consequence shipped unnoticed. test/jsonmixfix is the same claim on a corpus
# that CAN say no: one package.json plus one C file, and two tokens that exercise the two sub-cases.
MIXFIX="$ROOT/test/jsonmixfix"
# Liveness: if the fixture ever stops carrying both files, every arm below would pass by finding nothing.
{ [ -f "$MIXFIX/package.json" ] && [ -f "$MIXFIX/loader.c" ]; } \
    && ok "mixed fixture present (a JSON config AND a code file — the monoculture blind spot is closed)" \
    || no "test/jsonmixfix is missing a member — the arms below cannot observe the config-language class"

# (a) EMPTY CODE TIER: `dependencies` is a JSON key (string) and a C COMMENT mention, and nothing else.
#     The collapsed ladder must serve BOTH. Before the wave-3 ladder fix, comment outranked string and
#     package.json vanished from its own retrieval claim — this arm is red on that binary.
mixDep="$( "$BIN" "$MIXFIX" --grep=dependencies --no-cache 2>/dev/null )"
if grep -q 'package.json' <<<"$mixDep" && grep -q 'loader.c' <<<"$mixDep"; then
    ok "mixed corpus: a JSON key survives a code file's COMMENT mention of the same token (collapsed tier)"
else
    no "mixed corpus: --grep=dependencies lost one of the two files — the comment>string inversion is back"
    printf '%s\n' "$mixDep" | grep -o '<grep [^>]*>'
fi

# (b) NON-EMPTY CODE TIER: `retryBudget` is a JSON key AND a C function name. The code tier wins, so the
#     config row IS held back. That is the OPEN half of the finding (P4-C, wave-4 board item 15: in a data
#     language the string tier IS the content). This arm does not pretend otherwise — it pins the current
#     answer AND the honesty around it, so the class is observable instead of silent: the row must be
#     disclosed via suppressed_string=, and the answer must NOT claim complete=.
#     WHEN BOARD ITEM 15 LANDS this arm goes red on purpose: flip it to the (a) shape in that commit.
mixCode="$( "$BIN" "$MIXFIX" --grep=retryBudget --no-cache 2>/dev/null )"
if grep -q 'loader.c' <<<"$mixCode" && ! grep -q 'package.json' <<<"$mixCode" \
   && grep -q 'suppressed_string="1"' <<<"$mixCode" && ! grep -q 'complete="1"' <<<"$mixCode"; then
    ok "mixed corpus: a code-tier hit still hides the config row — DISCLOSED (suppressed_string=), no completeness claim (P4-C, board 15)"
else
    no "mixed corpus: the config-suppression case changed shape — if this is board item 15 landing, re-pin this arm deliberately"
    printf '%s\n' "$mixCode" | grep -o '<grep [^>]*>'
fi

# (c) …and the hatch the security skill now tells auditors to use actually recovers it.
mixAny="$( "$BIN" "$MIXFIX" --grep=retryBudget --grep-in=any --no-cache 2>/dev/null )"
{ grep -q 'package.json' <<<"$mixAny" && grep -q 'loader.c' <<<"$mixAny"; } \
    && ok "mixed corpus: --grep-in=any recovers the config row the default holds back" \
    || no "mixed corpus: --grep-in=any did NOT recover the config row — the documented escape hatch is broken"

# The security skill must actually TELL the auditor that, since its own MCP-config recipe depends on it.
grep -q -- '--grep-in=any' "$SEC" \
    && ok "security skill routes its config recipe through --grep-in=any" \
    || no "security skill's MCP-config recipe does not use --grep-in=any — as written it reviews zero config stanzas"
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
