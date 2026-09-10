#!/usr/bin/env bash
# Build ripwire and install it onto PATH, decoupled from the gitignored build/ dir (previously PATH
# pointed at a symlink straight into build/, which breaks on any clean rebuild). Idempotent — safe to
# re-run after any source change. Run: ./install.sh
#
# Builds in its OWN tree (build-install/), as Release: an installed binary is one you USE, so it gets
# the fast flavour (Release implies LTO — see CMakeLists). build/ stays the plain dev flavour every
# gate and bench number is measured against; configuring THAT tree as Release or -march=native would
# silently move all of them at once (the same argument CMakeLists uses to refuse PGO in build/).
#
# The install prefix is detected, not hardcoded: /opt/homebrew is wrong on Intel macOS (brew
# lives at /usr/local there) and on any machine with no Homebrew at all (most Linux). Detect instead:
#   1) RIPWIRE_INSTALL_PREFIX env override, for anyone who wants a specific location
#   2) `brew --prefix` if brew is on PATH (covers both Apple Silicon /opt/homebrew and Intel /usr/local)
#   3) ~/.local as the no-brew fallback (no sudo needed, commonly already on PATH)
# RIPWIRE_ACTIVATE_CODEX=1 additionally activates the just-installed skills + advisory hooks. It is
# explicit because it writes agent configuration outside the install prefix; staging is always atomic.
set -eu
dir="$( cd "$( dirname "$0" )" && pwd )"
cd "$dir"

if [ -n "${RIPWIRE_INSTALL_PREFIX:-}" ]; then
    prefix="$RIPWIRE_INSTALL_PREFIX"
elif command -v brew >/dev/null 2>&1; then
    prefix="$( brew --prefix )"
else
    prefix="$HOME/.local"
    echo "install.sh: no brew on PATH — installing under $prefix (set RIPWIRE_INSTALL_PREFIX to override)"
fi

cmake -S . -B build-install -DCMAKE_BUILD_TYPE=Release -DRIPWIRE_NATIVE=ON
cmake --build build-install -j
# The staged skills dir is OWNED by this installer: `cmake --install` is additive, so a skill directory this
# source no longer ships (renamed or folded — ripwire-efficient, 2026-09-07) would survive an upgrade and be
# re-linked as live by skills/install.sh. Blow it away first; the release installer (scripts/install.sh) does the same.
rm -rf "$prefix/share/ripwire/skills"
cmake --install build-install --prefix "$prefix" --component ripwire

# 2026-09-06 (stranger audit): activate the skills for the agents present on this machine, the same way the
# release installer (scripts/install.sh) does — the two documented routes used to leave different setups,
# and this one left the skills staged with no word about it. RIPWIRE_NO_ACTIVATE=1 stages only; hooks stay
# behind an explicit flag (they carry a data-capture disclosure). RIPWIRE_ACTIVATE_CODEX=1 keeps its old
# meaning: Codex skills plus its advisory hooks.
skillsInstaller="$prefix/share/ripwire/skills/install.sh"
if [ -z "${RIPWIRE_NO_ACTIVATE:-}" ] && [ -f "$skillsInstaller" ]; then
    if [ -d "${CLAUDE_CONFIG_DIR:-$HOME/.claude}" ]; then
        if bash "$skillsInstaller" >/dev/null 2>&1; then
            echo "install.sh: activated the ripwire skills for Claude Code (${CLAUDE_CONFIG_DIR:-$HOME/.claude}/skills)"
        else
            echo "install.sh: could not activate the Claude Code skills; run: bash \"$skillsInstaller\"" >&2
        fi
    fi
    if [ "${RIPWIRE_ACTIVATE_CODEX:-0}" = "1" ]; then
        bash "$skillsInstaller" --codex --hook
    elif [ -d "${CODEX_HOME:-$HOME/.codex}" ] || [ -d "${AGENTS_HOME:-$HOME/.agents}" ]; then
        if bash "$skillsInstaller" --codex >/dev/null 2>&1; then
            echo "install.sh: activated the ripwire skills for Codex (${AGENTS_HOME:-$HOME/.agents}/skills)"
        else
            echo "install.sh: could not activate the Codex skills; run: bash \"$skillsInstaller\" --codex" >&2
        fi
    fi
fi

case ":$PATH:" in
    *":$prefix/bin:"*) ;;
    *) echo "install.sh: $prefix/bin is not on PATH — add it, e.g. export PATH=\"$prefix/bin:\$PATH\"" ;;
esac

# 2026-09-06 (stranger audit): this line used to echo `command -v ripwire` — on a machine with an older
# ripwire elsewhere on PATH it announced THAT one as "installed". Name what was written; then say what
# `ripwire` at the prompt currently resolves to, if that is a different file.
echo "installed: $prefix/bin/ripwire"
resolved="$( command -v ripwire 2>/dev/null || true )"
if [ -n "$resolved" ] && [ "$resolved" != "$prefix/bin/ripwire" ]; then
    echo "install.sh: NOTE: \`ripwire\` on PATH currently resolves to $resolved, not the one just installed — that one runs until PATH puts $prefix/bin first"
fi
echo "agent assets: $prefix/share/ripwire/{skills,hooks}"
