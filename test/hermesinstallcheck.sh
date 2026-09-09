#!/usr/bin/env bash
# hermesinstallcheck.sh — the Hermes installer target gate for skills/install.sh --hermes.
# Pins that --hermes wires ripwire skills into the Hermes agent home exactly like the Claude
# (~/.claude) / Codex (~/.agents) paths, and that each target is hermetic: installing for one
# agent never touches another agent's home.
# The scripts/install.sh release-installer half (its Hermes activation block) is pinned by
# test/releaseinstallcheck.sh arm E7, not here.
# All against TEMP homes + the repo tree, so it is CI-runnable and never touches the real ~/.hermes,
# ~/.claude or ~/.agents.  HERMES_HOME is ALWAYS exported (not just a shell var) so the child
# bash processes inherit the temporary home and can never fall back to the real $HOME/.hermes.
# Usage:  test/hermesinstallcheck.sh   |   RIPWIRE_BIN=build/ripwire test/hermesinstallcheck.sh
# (RIPWIRE_BIN feeds arm 6 only — arms 1-5 are about skills/install.sh and bind no binary.)
# Exits non-zero on any failure. Does NOT edit regression.sh.
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
SK="$ROOT/skills"
fail=0
ok(){ echo "  PASS  $1"; }
no(){ echo "  FAIL  $1"; fail=1; }

[ -f "$SK/install.sh" ] || { echo "no skills/install.sh"; exit 2; }

TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
export HERMES_HOME="$TMP/hermes-home"; rm -rf "$HERMES_HOME"; mkdir -p "$HERMES_HOME"

# helper: skill NAMES shipped in the repo — the flat Agent-Skills-standard set plus the Hermes-native
# set under skills/hermes/ (both deploy via --hermes; a flat dir of the same name wins and the native
# one is skipped, mirroring install.sh). $1 selects the set: user (activated by default) or contributor.
skill_names() {
    for d in "$SK"/ripwire-*/ "$SK"/hermes/*/; do
        [ -d "$d" ] || continue
        name="$( basename "$d" )"
        [ -f "$d/SKILL.md" ] || continue
        case "$d" in
            "$SK"/hermes/*) [ -d "$SK/$name" ] && continue ;;
        esac
        if [ "${1:-user}" = "contributor" ]; then
            grep -q '^audience: contributor' "$d/SKILL.md" 2>/dev/null || continue
        else
            grep -q '^audience: contributor' "$d/SKILL.md" 2>/dev/null && continue
        fi
        echo "$name"
    done | sort -u
}

shipped=$( skill_names user | wc -l | tr -d ' ' )
contributorSkills=$( skill_names contributor | wc -l | tr -d ' ' )

# ---- 1) --hermes installs every user-facing shipped skill under ${HERMES_HOME}/skills ----
bash "$SK/install.sh" --hermes >/dev/null 2>&1
H_FOUND=$( find -L "$HERMES_HOME/skills" -mindepth 2 -maxdepth 2 -name SKILL.md 2>/dev/null | wc -l | tr -d ' ' )
{ [ "$H_FOUND" -eq "$shipped" ]; } \
    && ok "--hermes exposes all $shipped user-facing shipped skills under HERMES_HOME/skills (found=$H_FOUND)" \
    || no "--hermes exposed $H_FOUND of $shipped skills under HERMES_HOME/skills"

# ---- 1b) the manifest names EXACTLY the linked user-facing set (no contributor-only, nothing omitted) ----
MANIFEST="$HERMES_HOME/skills/.ripwire-manifest-v1"
manifest_set=$( grep '^skill=' "$MANIFEST" 2>/dev/null | sed 's/^skill=//' | sort )
wanted_set=$( skill_names user )
if [ "$manifest_set" != "$wanted_set" ]; then
    no "--hermes manifest set differs from the shipped user-facing set
        (manifest has $(printf '%s\n' "$manifest_set" | wc -l | tr -d ' ') entries, wanted $(printf '%s\n' "$wanted_set" | wc -l | tr -d ' '))"
else
    ok "--hermes manifest declares exactly the linked user-facing set ($(printf '%s\n' "$manifest_set" | wc -l | tr -d ' ') skills)"
fi

# ---- 2) --hermes is hermetic: never touches ~/.claude or the cross-agent ~/.agents ----
FALLBACK_HOME="$TMP/fallback-home"; rm -rf "$FALLBACK_HOME"; mkdir -p "$FALLBACK_HOME"
HOME="$FALLBACK_HOME" bash "$SK/install.sh" --hermes >/dev/null 2>&1   # HERMES_HOME already exported
{ [ ! -e "$FALLBACK_HOME/.claude/skills" ]; } \
    && ok "--hermes does not create a Claude skill home" \
    || no "--hermes also created a Claude skill home"
{ [ ! -e "$FALLBACK_HOME/.agents/skills" ]; } \
    && ok "--hermes does not create the cross-agent ~/.agents skill home" \
    || no "--hermes also created the cross-agent ~/.agents skill home"

# ---- 3) the reverse: default (Claude) and --codex installs never touch a Hermes home ----
CLAUDE_HOME="$TMP/claude-home"; rm -rf "$CLAUDE_HOME"; mkdir -p "$CLAUDE_HOME/.claude"
HOME="$CLAUDE_HOME" bash "$SK/install.sh" >/dev/null 2>&1   # HERMES_HOME still points at TMP
H_AFTER_CLAUDE=$( find -L "$HERMES_HOME/skills" -mindepth 2 -maxdepth 2 -name SKILL.md 2>/dev/null | wc -l | tr -d ' ' )
{ [ "$H_AFTER_CLAUDE" -eq "$shipped" ]; } \
    && ok "a default (Claude) install leaves the Hermes skill home intact" \
    || no "a default (Claude) install overwrote/pruned the Hermes skill home (found=$H_AFTER_CLAUDE)"

# ---- 4) --hermes re-run is idempotent (0 pruned), proving "safe to re-run" ----
RE_RUN=$( bash "$SK/install.sh" --hermes 2>&1 | grep -c "pruned stale" || true )
{ [ "${RE_RUN:-0}" -eq 0 ]; } \
    && ok "--hermes re-run prunes nothing (idempotent)" \
    || no "--hermes re-run pruned $RE_RUN skills (drift: shipped set changed between runs)"

# ---- 5) --hermes --hook is refused with EXIT STATUS 2 (the hook port has not landed yet) ----
bash "$SK/install.sh" --hermes --hook >/dev/null 2>&1
HOOK_STATUS=$?
{ [ "$HOOK_STATUS" -eq 2 ]; } \
    && ok "--hermes --hook fails with exit status 2 (hook not ported to the Hermes target yet)" \
    || no "--hermes --hook exited $HOOK_STATUS, expected 2 — or it succeeded, which is wrong"

# ---- 6) the binary's own Hermes recipe resolves to the home the installer just populated ----
# `ripwire wrap hermes` prints a paste-able recipe carrying two strings that live in src/wrap.h's
# kAgentTargets row: the install FLAG, and the skills DIRECTORY that flag deploys to. The behaviour
# those strings describe lives in skills/install.sh, which knows nothing about wrap.h. Nothing else
# holds the pair together: PR #51 first landed them across six hand-edited branches, and the
# kAgentTargets consolidation folded those into one row, so a future row edit is exactly the drift
# this arm exists to catch. Binding BIN here is also what makes this gate answerable to
# test/binoverridecheck.sh — arms 1-5 are about skills/install.sh alone, and a gate that never
# invokes the binary it is handed stays GREEN against a binary that is entirely broken.
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"          # allow a repo-relative RIPWIRE_BIN
[ -x "$BIN" ] || BIN="$( command -v ripwire 2>/dev/null || true )"
if [ -z "$BIN" ] || [ ! -x "$BIN" ]; then
    echo "  SKIP  wrap-recipe arm (no ripwire binary found via RIPWIRE_BIN / build/ripwire / PATH)"
else
    WRAP="$TMP/wrap-hermes.txt"
    if ! "$BIN" wrap hermes >"$WRAP" 2>"$TMP/wrap-hermes.err"; then
        no "ripwire wrap hermes exited non-zero — the binary cannot print its own Hermes recipe"
    else
        RECIPE=$( grep -m1 -E '^bash skills/install\.sh ' "$WRAP" || true )
        FLAG=$( printf '%s\n' "$RECIPE" | awk '{ print $3 }' )
        ADV=$( printf '%s\n' "$RECIPE" | sed -n 's/.*# deploy to \(.*\) (drift-gated).*/\1/p' )

        { [ "$FLAG" = "--hermes" ]; } \
            && ok "wrap hermes recommends the installer flag this gate exercises ($FLAG)" \
            || no "wrap hermes recommends installer flag '${FLAG:-<none>}'; this gate installs with --hermes"

        # The advertised path is deliberately UNexpanded in the recipe (it is meant to be pasted into
        # a shell), so the gate resolves it the way a reader's shell would. HERMES_HOME is exported
        # above and never empty here, so the ${...:-~/.hermes} default branch is not the one under
        # test; the charset guard keeps a command substitution out of the resolving shell.
        if [ -z "$ADV" ]; then
            no "wrap hermes prints no '# deploy to <dir> (drift-gated)' path for the --hermes flag"
        elif ! printf '%s' "$ADV" | grep -qE '^[A-Za-z0-9_~/${}:.-]+$'; then
            no "wrap hermes advertises a deploy path with unexpected shell metacharacters: $ADV"
        else
            RESOLVED=$( HERMES_HOME="$HERMES_HOME" bash -c "printf '%s\n' \"$ADV\"" )
            { [ "$RESOLVED" = "$HERMES_HOME/skills" ]; } \
                && ok "wrap hermes advertises the skills home --hermes actually populated ($ADV)" \
                || no "wrap hermes advertises '$ADV' -> '$RESOLVED', but --hermes deployed to $HERMES_HOME/skills"
        fi

        # the binary half of arm 5's honesty claim: the recipe must not tell anyone to run a flag
        # combination the installer refuses.
        { ! grep -q -- '--hermes --hook' "$WRAP"; } \
            && ok "wrap hermes prints no --hook install line (arm 5 pins the installer's matching refusal)" \
            || no "wrap hermes prints a '--hermes --hook' install line, but the installer refuses it with exit 2"
    fi
fi

[ "$fail" -eq 0 ] && echo "hermesinstallcheck: ALL PASS" || { echo "hermesinstallcheck: FAILURES"; exit 1; }
