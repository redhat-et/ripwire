#!/usr/bin/env bash
# meterdisclosurecheck.sh — D2: the install-time banner for `skills/install.sh --hook` must actually
# disclose what the substitution meter persists, not just that it counts.
#
# The meter (docs/SUBSTITUTION_METER.md) appends rows whose `detail` field holds a RAW file path
# (Read), a RAW grep pattern (Grep/Glob), or the first 200 B of a RAW command (Bash) — plus `repo` as
# an absolute path and the raw, unhashed session id — to ~/.ripwire/substitution.jsonl, with no TTL on
# the file. That is documented correctly in docs/SUBSTITUTION_METER.md, and RIPWIRE_METER=0 does work.
# The gap is the ONE line a user actually reads at install time
# (skills/install.sh, the "counting:" banner line under --hook), which on 1dc7b01 reads:
#
#   counting: appends one JSONL row per observed call to ~/.ripwire/substitution.jsonl (RIPWIRE_METER=0 opts out).
#
# That reads like anonymous counts/metadata. It does not say the row carries the raw path/pattern/
# command you just ran, does not say it stays local, and does not say there is no retention limit.
#
# This is a DISCLOSURE-ONLY gate: it asserts the banner's wording, never the meter's actual capture
# behavior (which is out of scope for this fix — see the lane's hard constraint against touching
# hooks/ripwire-nudge.sh or changing what the meter captures).
#
# Usage:  test/meterdisclosurecheck.sh   |   RIPWIRE_BIN=build/ripwire test/meterdisclosurecheck.sh
# Hermetic: runs `install.sh --hook` (to capture the REAL stdout banner, not just grep the source)
# against a fresh mktemp -d HOME/AGENTS_HOME with a pre-seeded valid, empty settings.json — never the
# operator's real ~/.claude. Exits non-zero on any failure.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
: "$BIN"   # unused (this gate inspects install.sh's own source/output text, no ripwire binary needed)
INSTALL="$ROOT/skills/install.sh"
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -f "$INSTALL" ] || { echo "no $INSTALL"; exit 2; }

# ── run the REAL banner a user sees: `install.sh --hook` against a fresh, empty (valid) settings.json
# in a hermetic sandbox, captured before the (successful) jq merge. This exercises the actual stdout
# text, not just source grep, so a refactor that moves the wording around still gets checked correctly.
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
SANDBOX_HOME="$TMP/home"; mkdir -p "$SANDBOX_HOME/.claude"
echo '{}' >"$SANDBOX_HOME/.claude/settings.json"
BANNER_OUT="$( HOME="$SANDBOX_HOME" AGENTS_HOME="$TMP/agents" bash "$INSTALL" --hook 2>&1 )"
# the disclosure block runs from the "counting:" line up to (not including) "remove:"
COUNTING_LINE="$( printf '%s\n' "$BANNER_OUT" | sed -n '/counting:/,/remove:/p' | sed '$d' )"
echo "-- counting/disclosure block from a real \`install.sh --hook\` run --"
echo "$COUNTING_LINE"

[ -n "$COUNTING_LINE" ] && ok "found the substitution.jsonl disclosure line in skills/install.sh" \
    || { no "no line in skills/install.sh mentions substitution.jsonl at all"; COUNTING_LINE=""; }

printf '%s' "$COUNTING_LINE" | grep -qi 'path' \
    && ok "banner names raw file PATH capture" \
    || no "banner does not name raw file path capture (Read rows carry the literal path opened)"
printf '%s' "$COUNTING_LINE" | grep -qi 'pattern' \
    && ok "banner names raw grep/glob PATTERN capture" \
    || no "banner does not name raw grep/glob pattern capture"
printf '%s' "$COUNTING_LINE" | grep -qi 'command' \
    && ok "banner names raw Bash COMMAND capture" \
    || no "banner does not name raw command capture"
printf '%s' "$COUNTING_LINE" | grep -qiE 'local|never (leaves|transmitted|sent)' \
    && ok "banner states the data stays local / is never transmitted" \
    || no "banner does not state the data stays local-only"
printf '%s' "$COUNTING_LINE" | grep -qiE 'no (automatic )?retention|unbounded|does not expire|no ttl' \
    && ok "banner states there is no automatic retention limit" \
    || no "banner does not disclose the absence of a retention limit"

# ── sanity check, not a hard requirement of this lane: the doc this banner points readers to should
# still carry the same raw-path-capture disclosure it always has, so the banner's short summary and
# the doc's long-form explanation do not diverge.
DOC="$ROOT/docs/SUBSTITUTION_METER.md"
# R3 (V1, wave-1 verifier 2026-09-05): the two blocks below were `if [ -f "$DOC" ]` with NO else and
# nothing asserting the doc exists, so moving or renaming docs/SUBSTITUTION_METER.md deleted NINE of this
# gate's fifteen arms — including the eight that are the ONLY gate on the EDIT band's column definitions,
# every one of them a doc-text grep — and the run still printed ALL PASS at rc=0. A disclosure contract
# whose gate disarms itself when the disclosure disappears is not a gate. hookcheck's shape is the one to
# copy: a missing bench/substitution_report.py makes it RED, it does not make it quiet. The doc is a
# required artifact of this contract, so its absence is the loudest failure available, never a skip.
DOC_PRESENT=1
if [ ! -f "$DOC" ]; then
    DOC_PRESENT=0
    no "docs/SUBSTITUTION_METER.md is MISSING at $DOC — the raw-path-capture disclosure and the EDIT band's eight column definitions (policy-read / sweep / redundant-check / unattrib / agent+surface / v2->v3 boundary / v3 example row) are UNGATED; this gate is their only gate"
fi
if [ "$DOC_PRESENT" = 1 ]; then
    # the doc's own sentence wraps across two source lines; match on the substrings that survive that
    grep -q 'Full local paths are' "$DOC" && grep -q 'this log never leaves the machine' "$DOC" \
        && ok "docs/SUBSTITUTION_METER.md still documents raw-path capture (unchanged claim, D2 doesn't touch capture)" \
        || no "docs/SUBSTITUTION_METER.md's raw-path-capture disclosure went missing"
fi

# ── the EDIT band (terminality round A, 2026-09-05, lane T2). docs/EVALS.md registers a second §5 table
# whose three columns are named and DEFINED, none silently folded into another, printed per agent and
# per surface. The definitions live in docs/SUBSTITUTION_METER.md, and this gate pins that they do —
# a percentage whose columns are not defined where the reader looks is a number somebody quotes wrong.
if [ "$DOC_PRESENT" = 1 ]; then
    EB="$( sed -n '/^## Terminality/,$p' "$DOC" )"
    printf '%s' "$EB" | grep -q 'policy-read' && printf '%s' "$EB" | grep -qiE 'never counted|reported, never' \
        && ok "doc defines (a) policy-read as the harness Read of the edit's TARGET FILE — reported, never counted against the verb" \
        || no "docs/SUBSTITUTION_METER.md does not define the policy-read column (or does not say it is never counted)"
    printf '%s' "$EB" | grep -q 'native-edit' && printf '%s' "$EB" | grep -qiE 'sweep' \
        && ok "doc defines (b) sweep as a Read/grep of another file or a native-edit of the same target" \
        || no "docs/SUBSTITUTION_METER.md does not define the sweep column of the EDIT band"
    printf '%s' "$EB" | grep -q 'redundant-check' && printf '%s' "$EB" | grep -q 'no-post-check' \
        && ok "doc defines (c) redundant-check as an edit-check on the same symbol after an edit whose receipt carried the folded post-check" \
        || no "docs/SUBSTITUTION_METER.md does not define the redundant-check column (and its --no-post-check exception)"
    printf '%s' "$EB" | grep -q 'unattrib' \
        && ok "doc discloses the unattrib count (no recorded target: (a) and (b) cannot be told apart, excluded from terminal%)" \
        || no "docs/SUBSTITUTION_METER.md does not disclose how an edit row with no recorded target is counted"
    printf '%s' "$EB" | grep -q '`agent`' && printf '%s' "$EB" | grep -q '`surface`' \
        && printf '%s' "$EB" | grep -qE 'cli.*mcp|mcp.*cli' \
        && ok "doc says the EDIT table is printed per agent and per surface (cli / mcp)" \
        || no "docs/SUBSTITUTION_METER.md does not define the agent/surface split of the EDIT band"
    grep -q 'v2 → v3\|v2 -> v3' "$DOC" && grep -qE 'native-edit' "$DOC" && grep -qiE 'not comparable' "$DOC" \
        && ok "doc discloses the v2 -> v3 boundary: MCP and native-edit rows become visible, counts across it are not comparable" \
        || no "docs/SUBSTITUTION_METER.md does not disclose the v2 -> v3 schema boundary"
    grep -q '"agent"' "$DOC" && grep -q '"target"' "$DOC" && grep -q '"surface"' "$DOC" \
        && ok "doc carries a v3 example row with agent, surface and target (the shape agentloop rows must emit)" \
        || no "docs/SUBSTITUTION_METER.md has no v3 example row naming agent/surface/target"
fi

[ "$fail" -eq 0 ] && echo "ALL PASS" || { echo "SOME CHECKS FAILED"; exit 1; }
