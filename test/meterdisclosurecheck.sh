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
if [ -f "$DOC" ]; then
    # the doc's own sentence wraps across two source lines; match on the substrings that survive that
    grep -q 'Full local paths are' "$DOC" && grep -q 'this log never leaves the machine' "$DOC" \
        && ok "docs/SUBSTITUTION_METER.md still documents raw-path capture (unchanged claim, D2 doesn't touch capture)" \
        || no "docs/SUBSTITUTION_METER.md's raw-path-capture disclosure went missing"
fi

[ "$fail" -eq 0 ] && echo "ALL PASS" || { echo "SOME CHECKS FAILED"; exit 1; }
