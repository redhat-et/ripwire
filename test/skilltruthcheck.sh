#!/usr/bin/env bash
# skilltruthcheck.sh — executable truth gate for claims shipped in ripwire skills.
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
fail=0
ok(){ echo "  PASS  $1" || { fail=1; echo "  FAIL  could not write the PASS line for: $1"; }; return 0; }
no(){ echo "  FAIL  $1"; fail=1; }

[ -x "$BIN" ] || { echo "no executable ripwire binary: $BIN"; exit 2; }

SEC="$ROOT/skills/ripwire-security-scan/SKILL.md"
EFF="$ROOT/skills/ripwire-orient/map-before-you-read.md"
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
#     RE-PIN (INT1 2026-11-19, BX2 FIX 6 f3b8632f0, by design): a file whose every hit the tier held back is now NAMED on the
#     root (held_files="1" held="package.json" held_next=…), never as a row. So package.json may appear in held= only: the
#     arm strips the root's held= value before asserting no package.json row, and asserts that held= names it.
mixCode="$( "$BIN" "$MIXFIX" --grep=retryBudget --no-cache 2>/dev/null )"
mixRows="$( sed 's/ held="[^"]*"//g' <<<"$mixCode" )"
if grep -q 'loader.c' <<<"$mixCode" && ! grep -q 'package.json' <<<"$mixRows" \
   && grep -q 'held_files="1" held="package.json"' <<<"$mixCode" \
   && grep -q 'suppressed_string="1"' <<<"$mixCode" && ! grep -q 'complete="1"' <<<"$mixCode"; then
    ok "mixed corpus: a code-tier hit still hides the config row — DISCLOSED (suppressed_string=, held= names the file), no completeness claim (P4-C, board 15)"
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
# The kind count is read from the binary's own --help line, like the MCP count above, so adding a kind
# moves this arm with the binary instead of leaving a literal behind to go stale.
kindCount="$( "$BIN" --help=all 2>/dev/null | sed -n 's/.*--quality-delta .*across \([0-9][0-9]*\) kinds.*/\1/p' | head -1 )"
[ -n "$kindCount" ] || kindCount=0
[ "$kindCount" -gt 0 ] && grep -q "$kindCount kinds" "$QUAL" \
    && ok "quality skill documents the binary's $kindCount quality kinds" \
    || no "quality skill does not match the binary's quality-kind count ($kindCount)"
# EVERY "N kinds" / "N quality kinds" in the skill, not just the first match: one stale count left in a routing bullet
# gave an agent two answers on the same page.
staleKinds="$( grep -noE '\b[0-9]+ (quality )?kinds\b' "$QUAL" | grep -vE ":$kindCount (quality )?kinds$" )"
[ "$kindCount" -gt 0 ] && [ -z "$staleKinds" ] \
    && ok "every 'N kinds' count in the quality skill says $kindCount" \
    || no "quality skill has a stale kind count (binary: $kindCount): $( printf '%s' "$staleKinds" | tr '\n' ' ' )"
grep -q 'all 21 MCP verbs' "$ROOT/src/wrap.h" \
    && no "wrap source retains the stale 21-verb comment" \
    || ok "wrap source does not hardcode a stale MCP verb count"

# 2026-08-08 audit M3/L4/M5: --help must document ev=/ev_why= (essential complexity) and humps=/deep=/
# locals= (the nesting profile) next to amp=/ppalt=, and --lint's help line must name the cache-* pack.
# Both claims are executed against the binary, not just grepped as prose: --metrics really emits ev= on a
# known guard-return function, and --lint really fires a cache-* rule on the cachelint fixture.
helpOut="$( "$BIN" --help=all 2>/dev/null )"
{ grep -q 'ev=N essential complexity' <<<"$helpOut" && grep -q 'ev_why=' <<<"$helpOut"; } \
    && ok "--help documents ev=/ev_why= (essential complexity) next to amp=/ppalt=" \
    || no "--help does not document ev=/ev_why="
{ grep -q 'humps=' <<<"$helpOut" && grep -q 'deep=' <<<"$helpOut" && grep -q 'locals=' <<<"$helpOut"; } \
    && ok "--help documents the humps=/deep=/locals= nesting profile" \
    || no "--help does not document humps=/deep=/locals="
grep -q -- '--lint .*cache-\* data-layout' <<<"$helpOut" \
    && ok "--help's --lint line names the cache-* data-layout pack" \
    || no "--help's --lint line does not name the cache-* pack"

# --metrics prints one row per definition (P11, 2026-09-27): svector's two push_back overloads are two rows told apart by
# l=, and only the guard-return body (the const T& one) carries ev=; the other has none. Pick that row, not the first.
pushBackRow="$( "$BIN" "$ROOT" --metrics --no-cache --top-k=5000 2>/dev/null | grep -o '<s[^>]*n="push_back" sc="svector"[^>]*>' | grep 'ev_why=' | head -1 )"
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

# The find-bug skill's Honesty line used to say ripwire gives call-graph structure "not data flow" — a claim
# --slice/--slice-flow's statement-level def-use / reaching-definition slicing (shipped 2026-08-28, 17 days
# after this line was last touched) makes false. A skill contradicting the tool's own shipped flag set is
# exactly the class this file exists to catch; assert both directions so neither the false denial nor a
# silently-dropped pointer to the real verb can land unnoticed.
FINDBUG="$ROOT/skills/ripwire-find-bug/SKILL.md"
grep -qi 'not data flow' "$FINDBUG" \
    && no "find-bug skill still claims ripwire gives structure, not data flow (--slice/--slice-flow shipped)" \
    || ok "find-bug skill does not deny data-flow support"
grep -q -- '--slice' "$FINDBUG" \
    && ok "find-bug skill's Honesty line documents --slice/--slice-flow data-flow support" \
    || no "find-bug skill's Honesty line does not mention --slice/--slice-flow"
helpOut2="$( "$BIN" --help=all 2>/dev/null )"
{ grep -q -- '--slice=' <<<"$helpOut2" && grep -q -- '--slice-flow' <<<"$helpOut2"; } \
    && ok "--help still ships --slice=/--slice-flow (the flags the find-bug skill now names)" \
    || no "--help no longer ships --slice=/--slice-flow — the skill fix now names a retired flag"

# A1-2 (owner decision 2026-09-12): every `ripwire <dir> --VERB…` a skill spells carries --legend=compact
# WHERE THE BINARY ACCEPTS IT. --for is exempt by policy (its compact legend is its own and the first call of a
# session wants the full one); everything else is decided by the BINARY, not by a list kept here.
#
# WHY NOT A LIST (PR #215 review item 5). This arm used to hold SKILL_COMPACT_VERBS, sixty verb names typed out
# by hand, and it named `zoom`. skills/ripwire-orient/SKILL.md spells `ripwire <dir> --zoom --legend=compact
# --mermaid`, which the binary REFUSES ("--legend=compact applies to the XML verbs only — --mermaid has no XML
# legend to compact") — so the gate was enforcing a broken command, and would have kept enforcing it. The verb
# is not what decides; the whole command is, because --mermaid/--html/--situ/the writer flags turn an XML verb
# into a non-XML run. Two more broken lines in ripwire-quality-bar/SKILL.md fell out of the same probe, which is
# the argument for asking the binary: a hand list cannot find what nobody thought to type into it.
#
# THE PROBE. Each distinct command that carries --legend=compact is RUN against an empty temp directory. The
# refusal is a parse-time check, so an empty corpus answers it in milliseconds and a bogus SYM operand cannot
# mask it; nothing but the refusal line is read, and no other failure counts.
SKILL_TMP="$( mktemp -d )"; trap 'rm -rf "$SKILL_TMP"' EXIT
SKILL_EMPTY="$SKILL_TMP/empty"
mkdir -p "$SKILL_EMPTY"
BT='`'
sc_checked=0; sc_bad=0
# every distinct `ripwire <dir> …--legend=compact…` command span the skills spell
grep -rhoE --include='*.md' -- "ripwire <dir> --[a-z0-9-]+[^$BT]*" "$ROOT/skills" \
    | grep -F -- '--legend=compact' | sed 's/[[:space:]]*$//' | sort -u > "$SKILL_TMP/skill_compact_cmds.txt"
while IFS= read -r cmd; do
    [ -n "$cmd" ] || continue
    args="${cmd#ripwire <dir> }"
    sc_checked=$(( sc_checked + 1 ))
    # shellcheck disable=SC2086
    if "$BIN" "$SKILL_EMPTY" $args >/dev/null 2>"$SKILL_TMP/skillprobe.err"; then :; fi
    if grep -q 'applies to the XML verbs only' "$SKILL_TMP/skillprobe.err"; then
        sc_bad=$(( sc_bad + 1 ))
        [ "$sc_bad" -le 5 ] && printf '        REFUSED: %s\n' "$( printf '%s' "$cmd" | head -c 140 )"
    fi
done < "$SKILL_TMP/skill_compact_cmds.txt"
[ "$sc_checked" -gt 0 ] || no "skills compact policy: no skill command carries --legend=compact — the arm inspected nothing"
[ "$sc_bad" -eq 0 ] \
    && ok "skills compact policy: all $sc_checked distinct --legend=compact commands are ACCEPTED by this binary (asked, not listed)" \
    || no "skills compact policy: $sc_bad of $sc_checked --legend=compact commands are REFUSED by this binary (listed above) — the flag does not belong on them"
# …and the other direction: --for must NOT carry it (the one policy exemption this gate does state, because it
# is a choice and not a refusal — the binary accepts --legend=compact on --for perfectly well).
sc_for=0
while IFS= read -r line; do
    [ -n "$line" ] || continue
    sc_for=$(( sc_for + 1 ))
done <<<"$( grep -rhoE --include='*.md' -- "ripwire <dir> --for=[^$BT]*--legend=compact[^$BT]*" "$ROOT/skills" )"
[ "$sc_for" -eq 0 ] \
    && ok "skills compact policy: no --for command carries --legend=compact (its compact legend is its own)" \
    || no "skills compact policy: $sc_for --for command(s) carry --legend=compact"

# A1-2b (PR #215 review 5192692319): …AND THE OMISSION, which is the direction the two arms above cannot
# see. Both of them start from a command that ALREADY carries --legend=compact, so a command that should
# carry it and does not was invisible to every arm in this gate: skills/ripwire-fresh-eyes/SKILL.md's
# pass 1a spelled `ripwire <dir> --rank-by=churn-decay` with no flag from #218 until this arm existed, and
# five more spans across four other skills fell out of the same sweep. A policy gate that only audits the
# commands that obey it is not auditing the policy.
#
# THE PREDICATE, both halves asked of the BINARY and not of a list (the A1-2 argument, unchanged). A
# flagless span is REQUIRED to carry the flag when (a) the bare command EMITS XML on the probe corpus —
# stdout's first byte is '<' — and (b) appending --legend=compact is not refused.
# (a) IS WHAT KEEPS THE ARM SOUND, and it is not decoration: a span carrying a placeholder operand
# (`--arch=rules.txt`, `--scip=index.scip`, `--export=cc.json[:FILE]`) or a writer/non-XML flag fails
# before the legend check is ever reached, so its silence on the refusal line would otherwise read as
# "the flag belongs here". Measured on the pre-fix tree: 21 spans looked like violations without (a) and
# 6 were real.
# FLOOR, stated because silence here would read as a guarantee: (a) excludes every span whose operand
# cannot resolve against an empty corpus, so this arm is a FLOOR on the policy, never a total. The spans
# it skips are unproven in both directions — not proven exempt.
sc_classify(){                      # 0 = must carry the flag and does not; 1 = not required (skip/exempt)
    local args="$1"
    # shellcheck disable=SC2086
    "$BIN" "$SKILL_EMPTY" $args >"$SKILL_TMP/bare.out" 2>/dev/null || true
    [ "$( head -c 1 "$SKILL_TMP/bare.out" 2>/dev/null )" = '<' ] || return 1   # (a) not an XML run here
    # shellcheck disable=SC2086
    "$BIN" "$SKILL_EMPTY" $args --legend=compact >/dev/null 2>"$SKILL_TMP/omit.err" || true
    grep -q 'applies to the XML verbs only' "$SKILL_TMP/omit.err" && return 1  # (b) the binary refuses it
    return 0
}
# POSITIVE CONTROL FIRST, so a green below is never the classifier quietly failing every span. `--flags`
# is an XML verb the binary accepts the flag on, so a flagless `--flags` MUST classify as a violation.
if sc_classify "--flags"; then
    ok "skills compact policy (omission) control: the classifier marks a flagless XML verb (--flags) as a violation — it can go red"
else
    no "skills compact policy (omission) control: a flagless --flags did NOT classify as a violation — the classifier is inert and the sweep below proves nothing"
fi
sc_swept=0; sc_xml=0; sc_missing=0
grep -rhoE --include='*.md' -- "ripwire <dir> --[a-z0-9-]+[^$BT]*" "$ROOT/skills" \
    | sed 's/[[:space:]]*$//' | sort -u \
    | grep -v -F -- '--legend=compact' | grep -vE '^ripwire <dir> --for' > "$SKILL_TMP/skill_flagless.txt"
while IFS= read -r cmd; do
    [ -n "$cmd" ] || continue
    sc_swept=$(( sc_swept + 1 ))
    args="${cmd#ripwire <dir> }"
    if sc_classify "$args"; then
        sc_xml=$(( sc_xml + 1 )); sc_missing=$(( sc_missing + 1 ))
        [ "$sc_missing" -le 6 ] && printf '        MISSING --legend=compact: %s\n' "$( printf '%s' "$cmd" | head -c 140 )"
    fi
done < "$SKILL_TMP/skill_flagless.txt"
[ "$sc_swept" -gt 0 ] || no "skills compact policy (omission): no flagless skill command was found at all — the sweep inspected nothing"
[ "$sc_missing" -eq 0 ] \
    && ok "skills compact policy (omission): $sc_swept flagless span(s) swept, none both emits XML and accepts --legend=compact (floor: placeholder operands are unprovable on an empty corpus)" \
    || no "skills compact policy (omission): $sc_missing of $sc_swept flagless span(s) emit XML and accept --legend=compact but do not carry it (listed above) — the policy requires it"

[ "$fail" -eq 0 ] && echo "ALL PASS" || { echo "SOME CHECKS FAILED"; exit 1; }
