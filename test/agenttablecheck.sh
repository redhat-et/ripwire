#!/usr/bin/env bash
# agenttablecheck.sh — every row of kAgentTargets is honoured, and every claim a row makes is true.
#
# WHY THIS GATE EXISTS. `wrap` used to carry three parallel lists: an accept-list, a usage blurb, and a
# per-agent if/else chain. Adding openclaw on 2026-09-08 meant touching all three, and missing any one
# produced a DIFFERENT silent failure — a name the usage prints but the dispatch rejects, a skills flag
# the recipe advertises but the installer does not accept. They are now one table, and this gate reads
# THAT TABLE as its own input: a row added to src/wrap.h is covered here without anyone editing this
# file. That is the point. If a row is added and this gate does not grow an assertion, the gate is wrong.
set -u

ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
# ACCUMULATOR, not fail-fast: this gate iterates every row, and a stop at the first bad row hides the
# other seven. gateexitcheck.sh arm (C) requires this shape and caught the fail-fast version.
FAILED=0
fail() { printf '  FAIL  %s\n' "$*"; FAILED=$(( FAILED + 1 )); }
[ -x "$BIN" ] || { echo "agenttablecheck: no binary at $BIN — build first"; exit 2; }

# ── parse the table out of the source ───────────────────────────────────────────
# Rows are `{ "name", "contextFile", "homeDir", "skillsRoot", "skillsFlag", hook, WrapPrimary::X, ... }`.
# Strip comments, join the block, then split on `},` — rows span two physical lines and the block
# carries // comments, so a line-oriented grep silently truncated every row at the first newline.
# `sed 1d` drops the declaration line: it ends in `{`, so joining glued it to the first row and the
# `^{ "` filter then dropped claude entirely. Arm (A)'s row-count floor caught that — it is the reason
# a mutation control earns its place even when it looks like ceremony.
sed -n '/^inline constexpr AgentTarget kAgentTargets\[\] = {/,/^};/p' "$ROOT/src/wrap.h" | sed '1d' \
    | sed 's|//.*||' | tr '\n' ' ' | sed 's/}, */},\n/g' \
    | grep -E '^[[:space:]]*\{ "' > "$TMP/rows" || true
ROWCOUNT="$( wc -l < "$TMP/rows" | tr -d ' ' )"

# (A) MUTATION CONTROL. A parser that silently matches nothing turns every arm below into a no-op that
# reports success. If the table's shape changes, this fires instead of the suite going quietly green.
[ "$ROWCOUNT" -ge 8 ] || fail "(A) parsed only $ROWCOUNT rows from src/wrap.h — the table's shape changed and every assertion below just became a no-op"

"$BIN" wrap 2>&1 | head -40 >"$TMP/usage" || true

while IFS= read -r row; do
    name="$(       printf '%s' "$row" | sed -n 's/^[[:space:]]*{ "\([^"]*\)".*/\1/p' )"
    display="$(    printf '%s' "$row" | cut -d'"' -f4 )"
    ctxfile="$(    printf '%s' "$row" | cut -d'"' -f6 )"
    homedir="$(    printf '%s' "$row" | cut -d'"' -f10 )"
    skillsroot="$( printf '%s' "$row" | cut -d'"' -f12 )"
    skillsflag="$( printf '%s' "$row" | cut -d'"' -f14 | sed 's/^ *//' )"
    hook="$(       printf '%s' "$row" | grep -oE 'true|false' | head -1 )"
    primary="$(    printf '%s' "$row" | grep -oE 'WrapPrimary::[A-Za-z]+' | sed 's/.*:://' )"
    [ -n "$name" ] || fail "(A) could not parse a name out of row: $row"

    "$BIN" wrap "$name" --force >"$TMP/out" 2>"$TMP/err"
    rc=$?

    # (B) DISPATCH. The row exists, so the binary must accept it. This is the arm that catches a row
    # added to the table while the accept-list stayed hand-written.
    if [ "$rc" -ne 0 ] || grep -q 'unknown agent' "$TMP/err"; then
        fail "(B) '$name' is a row in kAgentTargets but 'wrap $name' exited $rc — every later arm for this row would read a stale file, so they are skipped"
        continue
    fi

    # (C) DISCOVERABILITY. A supported agent nobody can find is not supported.
    # Match only the GROUP lines. A bare `grep -qw` over the whole usage text passed for claude no matter
    # what, because the text also contains `example: ripwire wrap claude` — the arm could not fail for
    # the one agent most likely to be listed. Found by review, not by my own mutation pass.
    grep -E '^  (CLI-first|MCP config|repo-map):' "$TMP/usage" | grep -qw "$name" \
        || fail "(C) '$name' is dispatchable but no group line in 'ripwire wrap' lists it"
    grep -qF "$display" "$TMP/out" || fail "(C2) '$name' recipe never names the product '$display'"

    # (D) THE CONTEXT FILE the row names must appear in the recipe — that string is the whole reason
    # the column exists, and a wrong one sends the user to edit a file their agent never reads.
    grep -qF "$ctxfile" "$TMP/out" || fail "(D) '$name' recipe never names its context file '$ctxfile'"

    # (E) PRIMARY. CLI-first means the first actionable line is the CLI, not a config stanza. Same
    # assertion codexwrapcheck makes for one agent, applied to every row that claims it.
    first="$( grep -v '^#' "$TMP/out" | sed '/^[[:space:]]*$/d' | head -1 )"
    if [ "$primary" = "Cli" ]; then
        case "$first" in
            *" . --for="*) ;;
            *) fail "(E) '$name' is WrapPrimary::Cli but its first actionable line is not the CLI invocation: $first" ;;
        esac
    fi

    # (F) THE SKILLS FLAG MUST BE REAL. The recipe printing `install.sh --openclaw` while the installer
    # rejects `--openclaw` is a two-file defect that no single-file gate can see. This arm spans both:
    # it runs the installer with the flag the recipe printed and requires it to be understood.
    if [ -n "$skillsroot" ]; then
        grep -qF "install.sh${skillsflag:+ $skillsflag}" "$TMP/out" \
            || fail "(F) '$name' has a skills root but the recipe never prints 'install.sh ${skillsflag}'"
        if [ -n "$skillsflag" ]; then
            out="$( HOME="$TMP/h-$name" AGENTS_HOME="$TMP/h-$name/.agents" CODEX_HOME="$TMP/h-$name/.codex" \
                    bash "$ROOT/skills/install.sh" "$skillsflag" 2>&1 )"; irc=$?
            # STATUS AND EFFECT, not just the absence of a rejection message. The first version only
            # grepped for "unknown option", so an installer that accepted the flag and then died on an
            # unbound variable — or exited 0 having installed nothing — passed the arm that exists to
            # catch exactly that. Review caught this; my mutation pass did not.
            if [ "$irc" -ne 0 ]; then
                fail "(F) recipe tells the user to run 'install.sh $skillsflag' for '$name', but it exits $irc: $( printf '%s' "$out" | tail -1 )"
            elif ! printf '%s' "$out" | grep -q '^installed '; then
                fail "(F) 'install.sh $skillsflag' for '$name' exits 0 but installs nothing"
            fi
        fi
    else
        if grep -q 'install\.sh' "$TMP/out"; then
            fail "(G) '$name' has NO verified skills root but the recipe still prints an install.sh line"
        fi
    fi

    # (H) THE HOOK SLOT IS A COLUMN, NOT AN INFERENCE. openclaw shares Codex's skills root, so any rule
    # deriving "has a hook" from "has a skills flag" hands openclaw a --codex --hook line for a slot it
    # does not have. Both directions asserted, so neither a missing nor a phantom hook line survives.
    if [ "$hook" = "true" ]; then
        grep -q -- '--hook' "$TMP/out" || fail "(H) '$name' has hookSlot=true but the recipe offers no --hook line"
    else
        if grep -q -- '--hook' "$TMP/out"; then
            fail "(H) '$name' has hookSlot=false but the recipe offers a --hook line anyway"
        fi
    fi
done < "$TMP/rows"

# (I) CAVEATS ARE LOAD-BEARING. A row carrying a conditional support claim must print that condition;
# silently dropping it is the tool claiming support it cannot deliver.
while IFS= read -r row; do
    name="$( printf '%s' "$row" | sed -n 's/^[[:space:]]*{ "\([^"]*\)".*/\1/p' )"
    # The LAST quoted field on the row is the caveat (empty string when there is none). Position, not a
    # spacing-sensitive regex: the first version of this line required exactly one space after the comma,
    # the table happened to use two, and the arm silently matched nothing — it reported OK with the
    # caveat printf deleted from the binary. A gate that cannot fail is not a gate.
    caveat="$( printf '%s' "$row" | awk -F'"' '{ print $(NF-1) }' )"
    [ -n "$caveat" ] || continue
    "$BIN" wrap "$name" --force 2>/dev/null >"$TMP/out"
    grep -qF "$caveat" "$TMP/out" || fail "(I) '$name' carries a caveat the recipe never prints: $caveat"
done < "$TMP/rows"

# (J) THE README IS ANOTHER PARALLEL LIST. Its `ripwire wrap <agent>` block is the first place a
# reader looks, and nothing re-derived it from the table until now: on 2026-09-08 it still called claude
# "MCP:" three weeks after the recipe led with the CLI. Both directions — no ghost agents, no missing rows.
for name in $( awk -F'"' '{ print $2 }' "$TMP/rows" ); do
    grep -qE "^ripwire wrap $name\b" "$ROOT/README.md" \
        || fail "(J) '$name' is a supported row but README's wrap block never lists it"
done
# NOT a `... | while` loop: `fail` exits, and inside a pipeline that exit lands in a subshell and the
# script sails on. This arm reported OK with a fabricated `ripwire wrap zed` line in the README until
# the loop stopped reading from a pipe.
grep -oE '^ripwire wrap [a-z]+' "$ROOT/README.md" | awk '{ print $3 }' | sort -u >"$TMP/shown"
while IFS= read -r shown; do
    [ -n "$shown" ] || continue
    grep -q "\"$shown\"" "$TMP/rows" \
        || fail "(J) README's wrap block advertises '$shown', which is not a row in kAgentTargets"
done < "$TMP/shown"

# (K) --all MUST SEE EVERY ROW. This is the arm that was missing when it mattered: `wrap openclaw`
# printed a correct recipe while `wrap --all` could not see openclaw at all, because detection lived in
# a FIFTH hand-written list beside the table. Measured as a DELTA against an empty HOME, because the
# recipe header prints the product name ("Claude Code"), not the row key — matching on the key would
# have made this arm silently unfailable for half the table.
mkdir -p "$TMP/all-none"
# HOME ALONE DOES NOT ISOLATE THIS. opencode resolves its config through xdg-basedir, so a set
# XDG_CONFIG_HOME sends detection somewhere other than the fixture and the row goes undetected for a
# reason that has nothing to do with the table. Unset on macOS, commonly SET on Linux CI — which is
# exactly how this gate passed here and failed all four Linux legs of shard 1/4 on ff502d94.
# (Same defect PR #55 fixes for the installer gates, shipped into a gate on the same day.)
BASE="$( env -u XDG_CONFIG_HOME HOME="$TMP/all-none" "$BIN" wrap --all 2>/dev/null | grep -c '^# ripwire ->' )"
while IFS= read -r row; do
    name="$(    printf '%s' "$row" | awk -F'"' '{ print $2 }' )"
    homedir="$( printf '%s' "$row" | awk -F'"' '{ print $10 }' )"
    case "$homedir" in "~/"*) ;; *) continue ;; esac
    H="$TMP/all-$name"; mkdir -p "$H/${homedir#\~/}"
    n="$( env -u XDG_CONFIG_HOME HOME="$H" "$BIN" wrap --all 2>/dev/null | grep -c '^# ripwire ->' )"
    [ "$n" -gt "$BASE" ] \
        || fail "(K) '$name': its home dir $homedir exists, yet 'wrap --all' emits $n surfaces, no more than an empty HOME ($BASE) — detection is not reading the table"
done < "$TMP/rows"

if [ "$FAILED" -ne 0 ]; then
    echo "agenttablecheck: $FAILED failure(s) above"
    exit 1
fi
echo "agenttablecheck: OK ($ROWCOUNT rows: dispatch, listing, context file, primary, skills flag round-tripped through the installer, hook slot, caveats, README wrap block, --all detection)"
