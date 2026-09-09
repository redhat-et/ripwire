#!/usr/bin/env bash
# scripts/install.sh — curl-pipe installer for a PREBUILT ripwire release binary.
#
#   curl -fsSL https://raw.githubusercontent.com/<owner>/ripwire/main/scripts/install.sh | bash
#
# The release contract is gate-pinned by test/releaseinstallcheck.sh: tag, binary version, asset name,
# mandatory checksum, archive root, skills, and hooks must agree before installation.
#
# This is DIFFERENT from the repo-root `install.sh`: that one builds ripwire FROM SOURCE (clones this repo,
# runs cmake). This one downloads a prebuilt binary from GitHub Releases — no compiler, no FetchContent, no
# 15-grammar clone, seconds instead of minutes. Prefer this one unless you're developing ripwire itself.
#
# Env overrides:
#   RIPWIRE_REPO             "owner/repo" on GitHub, e.g. redhat-et/ripwire (see README.md). No default on
#                             purpose: this MUST be passed explicitly (see error below) — the script
#                             refuses to guess a plausible-looking but wrong org/repo.
#   RIPWIRE_VERSION           a specific tag (e.g. "v0.2.0"); default: latest release.
#   RIPWIRE_INSTALL_PREFIX    install prefix; the binary lands in "$RIPWIRE_INSTALL_PREFIX/bin". Default:
#                             ~/.local/bin (no sudo needed). Pass /usr/local for the traditional location
#                             (may prompt for sudo to write there).
#   RIPWIRE_INSTALL_YES=1     skip the interactive confirmation (for CI / scripted installs).
set -eu

# ── repo + version ───────────────────────────────────────────────────────────────────────────────────────
repo="${RIPWIRE_REPO:-}"
if [ -z "$repo" ]; then
    echo "install.sh: RIPWIRE_REPO is not set." >&2
    echo "  This installer has no default GitHub org/repo — deliberate, so it never guesses a" >&2
    echo "  plausible-looking but wrong one. See README.md, e.g. RIPWIRE_REPO=redhat-et/ripwire." >&2
    echo "  Re-run as: RIPWIRE_REPO=<owner>/<repo> bash install.sh" >&2
    exit 2
fi
version="${RIPWIRE_VERSION:-}"

# ── OS/arch detection, mapped to release.yml's asset naming (ripwire-<version>-<os>-<arch>.tar.gz) ─────────
osName="$( uname -s )"
archName="$( uname -m )"
case "$osName" in
    Darwin) assetOs=macos ;;
    Linux)  assetOs=linux ;;
    *) echo "install.sh: unsupported OS '$osName' — no prebuilt binary; build from source instead (see repo-root install.sh)" >&2; exit 1 ;;
esac
case "$archName" in
    arm64|aarch64) assetArch=arm64 ;;
    x86_64|amd64)  assetArch=x64 ;;
    *) echo "install.sh: unsupported architecture '$archName' — no prebuilt binary; build from source instead" >&2; exit 1 ;;
esac

command -v curl >/dev/null 2>&1 || { echo "install.sh: curl is required" >&2; exit 2; }
command -v tar  >/dev/null 2>&1 || { echo "install.sh: tar is required" >&2; exit 2; }

# ── resolve the release + asset URL via the GitHub REST API ────────────────────────────────────────────
if [ -n "$version" ]; then
    apiUrl="https://api.github.com/repos/${repo}/releases/tags/${version}"
else
    apiUrl="https://api.github.com/repos/${repo}/releases/latest"
fi

releaseJson="$( curl -fsSL -H 'Accept: application/vnd.github+json' "$apiUrl" )" || {
    echo "install.sh: could not fetch release metadata from $apiUrl" >&2
    echo "  Check RIPWIRE_REPO=$repo and RIPWIRE_VERSION=${version:-<latest>} are correct." >&2
    exit 1
}

resolvedTag="$( printf '%s' "$releaseJson" | grep -m1 '"tag_name"' | sed -E 's/.*"tag_name": *"([^"]+)".*/\1/' )"
[ -n "$resolvedTag" ] || { echo "install.sh: could not parse a tag_name out of the release metadata" >&2; exit 1; }
resolvedVersion="${resolvedTag#v}"

assetName="ripwire-${resolvedVersion}-${assetOs}-${assetArch}.tar.gz"
assetUrl="$( printf '%s' "$releaseJson" | grep -o "\"browser_download_url\": *\"[^\"]*${assetName}\"" | sed -E 's/.*"(https[^"]+)"/\1/' | head -1 )"
[ -n "$assetUrl" ] || {
    echo "install.sh: release $resolvedTag has no asset named $assetName" >&2
    echo "  (built for ${assetOs}/${assetArch} — this platform may not be published for this release)" >&2
    exit 1
}

# ── install location + consent ──────────────────────────────────────────────────────────────────────────
prefix="${RIPWIRE_INSTALL_PREFIX:-$HOME/.local}"
binDir="$prefix/bin"

echo "install.sh: about to install ripwire ${resolvedTag} (${assetOs}/${assetArch})"
echo "  source: $assetUrl"
echo "  target: $binDir/ripwire"
if [ "${RIPWIRE_INSTALL_YES:-0}" != "1" ]; then
    if [ -t 0 ] || [ -r /dev/tty ]; then
        printf 'Proceed? [y/N] '
        reply=""
        if [ -r /dev/tty ]; then read -r reply < /dev/tty; else read -r reply; fi
        case "$reply" in
            y|Y|yes|YES) ;;
            *) echo "install.sh: aborted"; exit 1 ;;
        esac
    else
        echo "install.sh: no TTY to confirm on and RIPWIRE_INSTALL_YES not set — aborting." >&2
        echo "  Re-run with: RIPWIRE_INSTALL_YES=1 bash install.sh" >&2
        exit 1
    fi
fi

# ── download, verify checksum, extract, install ─────────────────────────────────────────────────────────
work="$( mktemp -d )"
trap 'rm -rf "$work"' EXIT

echo "install.sh: downloading $assetName ..."
curl -fsSL -o "$work/$assetName" "$assetUrl"

checksumUrl="${assetUrl}.sha256"
curl -fsSL -o "$work/${assetName}.sha256" "$checksumUrl" 2>/dev/null || {
    echo "install.sh: release $resolvedTag has no checksum for $assetName — refusing an unverified binary" >&2
    exit 1
}
(
    cd "$work"
    if command -v shasum >/dev/null 2>&1; then
        shasum -a 256 -c "${assetName}.sha256"
    elif command -v sha256sum >/dev/null 2>&1; then
        sha256sum -c "${assetName}.sha256"
    else
        echo "install.sh: shasum or sha256sum is required to verify the release" >&2
        exit 1
    fi
)

# Refuse absolute/traversal paths before extraction. The archive must have exactly the release asset's
# expected top-level directory; never let `find | head` select an attacker-controlled sibling.
expectedDirName="${assetName%.tar.gz}"
archiveList="$( tar -tzf "$work/$assetName" )" || { echo "install.sh: could not list $assetName" >&2; exit 1; }
while IFS= read -r entry; do
    case "$entry" in
        /*|../*|*/../*|*/..) echo "install.sh: unsafe archive path '$entry'" >&2; exit 1 ;;
        "$expectedDirName"|"$expectedDirName"/*) ;;
        *) echo "install.sh: unexpected archive entry '$entry' (expected root $expectedDirName)" >&2; exit 1 ;;
    esac
done <<EOF
$archiveList
EOF

tar -C "$work" -xzf "$work/$assetName"
extractedDir="$work/$expectedDirName"
[ -d "$extractedDir" ] || { echo "install.sh: unexpected archive layout — no $expectedDirName directory found" >&2; exit 1; }
[ -x "$extractedDir/ripwire" ] || { echo "install.sh: extracted archive has no executable ripwire binary" >&2; exit 1; }

binaryVersion="$( "$extractedDir/ripwire" --version 2>&1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 )"
[ "$binaryVersion" = "$resolvedVersion" ] || {
    echo "install.sh: release $resolvedTag contains ripwire ${binaryVersion:-<unknown>} — refusing version mismatch" >&2
    exit 1
}

mkdir -p "$binDir"

# INSTALL BY ATOMIC RENAME, NOT BY OVERWRITING IN PLACE.
#
# OBSERVED 2026-09-06, upgrading 0.3.8 -> 0.4.0 into /opt/homebrew/bin on macOS 15 (arm64), on the day
# the first release in 1,051 commits went out. `cp` onto the existing path produced a binary the kernel
# killed on sight: exit 137 (SIGKILL), no stdout, no stderr, nothing to read. Measured, in this order:
#
#   the installed file            exec -> 137, every time, stably
#   the SAME BYTES at a new path  cp to /tmp, exec -> 0, prints its version
#   rm + fresh copy, same path    exec -> 0
#
# So the bytes were never the problem; reusing the destination inode was. `cp` onto an existing path
# truncates and rewrites THAT inode. `mv` within one directory is rename(2): the destination becomes the
# new file's inode atomically, the old one is simply unlinked, and there is never a window where the
# binary is missing or half-written. This is why package managers install by rename, and it is correct
# regardless of which kernel behaviour produced the kill.
#
# WHAT IS NOT ESTABLISHED, stated because guessing here would be worse than silence: the precise kernel
# mechanism. Code-signature cache invalidation on an ad-hoc/linker-signed Mach-O is the obvious
# candidate, and a plausible second is that a running process had the file mapped -- this tool is
# normally wired into agents as a long-lived `ripwire --mcp` server, and eight were running from that
# path at the time. Both were tried in controlled repros and NEITHER reproduced, so neither is claimed
# here. The fix does not depend on the answer; only the explanation would.
#
# The temp name lives in $binDir on purpose: a temp file elsewhere makes this a cross-device copy, and
# `mv` would silently degrade back into the overwrite this exists to avoid.
installTmp="$binDir/.ripwire.install.$$"
rm -f "$installTmp"
cp "$extractedDir/ripwire" "$installTmp"
chmod +x "$installTmp"
mv -f "$installTmp" "$binDir/ripwire"

# AND PROVE IT RUNS, FATALLY. This check existed and its failure was swallowed by `|| echo "version
# check failed"` inside a message that still said "installed" — so the script detected the broken
# install above, announced success, and exited 0. A report that cannot fail is not a check. If the
# binary we just placed cannot state its own version, that is an installation failure and the exit
# status must say so, because the alternative is a user who believes they have a working tool.
installedVersion="$( "$binDir/ripwire" --version 2>&1 )" || {
    echo "install.sh: installed $binDir/ripwire but it exits $? without printing a version." >&2
    echo "  The file is in place and is not usable. Nothing was left half-installed; re-running is safe." >&2
    exit 1
}
echo "install.sh: installed $binDir/ripwire ($installedVersion)"

case ":$PATH:" in
    *":$binDir:"*) ;;
    *) echo "install.sh: $binDir is not on PATH — add it, e.g. export PATH=\"$binDir:\$PATH\"" ;;
esac

# ── stage bundled skills (curl-pipe users never get a repo checkout otherwise) ─────────────────────────
# skills/ teaches a coding agent WHEN to reach for ripwire mid-task; release.yml packages it into the
# tarball alongside the binary. $prefix/share/ripwire/skills is a fixed, shared contract with the rest of
# the toolchain (other pieces are being wired to look there) — do not relocate this path independently.
# This directory is a STAGING AREA OWNED BY THIS INSTALLER (nothing else writes here), so blowing it away
# and recopying on every run is safe and keeps a stale skill from a previous version lingering forever.
shareDir="$prefix/share/ripwire"
skillsShareDir="$shareDir/skills"
hooksShareDir="$shareDir/hooks"
if [ -d "$extractedDir/skills" ]; then
    rm -rf "$skillsShareDir"
    mkdir -p "$( dirname "$skillsShareDir" )"
    cp -R "$extractedDir/skills" "$skillsShareDir"
    chmod +x "$skillsShareDir/install.sh" 2>/dev/null || true

    echo "install.sh: staged agent skills at $skillsShareDir"

    # ── ACTIVATE, don't hand the user a menu (2026-09-06) ──────────────────────────────────────────
    # This block used to print four commands and stop: activate for Claude Code, or for Codex, then
    # optionally hooks for either. A new user finished the one-liner facing a decision rather than a
    # working setup, and the README's headline — the same line "ships the task-shaped skills that
    # teach your agent WHEN to reach for it" — was carrying its weight on the word "ships". Skills
    # that sit staged teach nothing.
    #
    # So: activate for each agent actually PRESENT on this machine, and print one receipt line each.
    # Detection is the agent's own home directory, which is the same signal `ripwire wrap --all` uses
    # and the only one available before the binary is on PATH. An agent that is not installed is
    # never given a skills directory — inventing ~/.claude on a machine with no Claude Code would be
    # this installer writing somebody else's config.
    #
    # TWO THINGS THIS DELIBERATELY DOES NOT DO. It never registers HOOKS: those carry a data-capture
    # disclosure (raw paths, patterns and commands into a local log with no retention limit) that a
    # user must read and accept, and no amount of convenience justifies arming that silently — they
    # stay behind an explicit `--hook`. And it never fails the install over an activation: the binary
    # is the product, so a symlink that cannot be written degrades to the manual line, exactly like a
    # release with no bundled skills does.
    #
    # RIPWIRE_NO_ACTIVATE=1 stages without activating, for image builds and scripted installs that
    # provision agent homes later. test/releaseinstallcheck.sh arms (E1)-(E6) pin all of it.
    activated=0
    if [ -z "${RIPWIRE_NO_ACTIVATE:-}" ]; then
        if [ -d "$HOME/.claude" ]; then
            if bash "$skillsShareDir/install.sh" >/dev/null 2>&1; then
                echo "install.sh: activated the ripwire skills for Claude Code ($HOME/.claude/skills)"
                activated=$(( activated + 1 ))
            else
                echo "install.sh: could not activate the Claude Code skills; run: bash \"$skillsShareDir/install.sh\"" >&2
            fi
        fi
        if [ -d "${CODEX_HOME:-$HOME/.codex}" ] || [ -d "${AGENTS_HOME:-$HOME/.agents}" ]; then
            if bash "$skillsShareDir/install.sh" --codex >/dev/null 2>&1; then
                echo "install.sh: activated the ripwire skills for Codex (${AGENTS_HOME:-$HOME/.agents}/skills)"
                activated=$(( activated + 1 ))
            else
                echo "install.sh: could not activate the Codex skills; run: bash \"$skillsShareDir/install.sh\" --codex" >&2
            fi
        fi
        if [ -d "${HERMES_HOME:-$HOME/.hermes}" ]; then
            if bash "$skillsShareDir/install.sh" --hermes >/dev/null 2>&1; then
                echo "install.sh: activated the ripwire skills for Hermes (${HERMES_HOME:-$HOME/.hermes}/skills)"
                activated=$(( activated + 1 ))
            else
                echo "install.sh: could not activate the Hermes skills; run: bash \"$skillsShareDir/install.sh\" --hermes" >&2
            fi
        fi
    fi
    if [ "$activated" -eq 0 ]; then
        echo "  Activate them (symlinks into the agent's skill dir, safe to re-run):"
        echo "    Claude Code: bash \"$skillsShareDir/install.sh\""
        echo "    Codex:       bash \"$skillsShareDir/install.sh\" --codex"
        echo "    Hermes:      bash \"$skillsShareDir/install.sh\" --hermes"
    fi
    if [ -d "$extractedDir/hooks" ]; then
        rm -rf "$hooksShareDir"
        cp -R "$extractedDir/hooks" "$hooksShareDir"
        chmod +x "$hooksShareDir/"*.sh 2>/dev/null || true
        echo "  Optional advisory hooks:"
        echo "    Claude Code: bash \"$skillsShareDir/install.sh\" --hook"
        echo "    Codex:       bash \"$skillsShareDir/install.sh\" --codex --hook"
    else
        echo "install.sh: this release has no bundled hooks; skills remain usable without them" >&2
    fi
else
    # Older releases (pre-skills-bundling) simply don't have this directory — never fail the install over
    # a missing extra; just tell the user honestly how to get them.
    echo "install.sh: this release predates bundled skills — clone https://github.com/redhat-et/ripwire and run skills/install.sh to get them"
fi
