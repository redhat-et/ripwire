#!/usr/bin/env bash
# scripts/install.sh — curl-pipe installer for a PREBUILT ripwire release binary.
#
#   curl -fsSL https://raw.githubusercontent.com/<owner>/ripwire/main/scripts/install.sh | bash
#
# UNTESTED UNTIL THE FIRST GITHUB RELEASE EXISTS (P3/L1): this script is written
# against .github/workflows/release.yml's asset naming and the GitHub Releases API contract, but neither
# has ever actually run — there is no release to download yet. Do not point users at this script until a
# `vX.Y.Z` tag has produced release assets and the happy path below has been exercised for real.
#
# This is DIFFERENT from the repo-root `install.sh`: that one builds ripwire FROM SOURCE (clones this repo,
# runs cmake). This one downloads a prebuilt binary from GitHub Releases — no compiler, no FetchContent, no
# 15-grammar clone, seconds instead of minutes. Prefer this one unless you're developing ripwire itself.
#
# Env overrides:
#   RIPWIRE_REPO             "owner/repo" on GitHub. TODO(P6): set the real default once the fresh-history
#                             public export lands; until then this MUST be passed explicitly (see error
#                             below) — the script refuses to guess a plausible-looking but wrong org/repo.
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
    echo "  This installer has no default GitHub org/repo yet (P6, the public export, hasn't landed)." >&2
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
if curl -fsSL -o "$work/${assetName}.sha256" "$checksumUrl" 2>/dev/null; then
    (
        cd "$work"
        if command -v shasum >/dev/null 2>&1; then
            shasum -a 256 -c "${assetName}.sha256"
        elif command -v sha256sum >/dev/null 2>&1; then
            sha256sum -c "${assetName}.sha256"
        else
            echo "install.sh: no shasum/sha256sum on PATH — skipping checksum verification" >&2
        fi
    )
else
    echo "install.sh: no .sha256 checksum file published for this asset — skipping verification" >&2
fi

tar -C "$work" -xzf "$work/$assetName"
extractedDir="$( find "$work" -maxdepth 1 -type d -name 'ripwire-*' | head -1 )"
[ -n "$extractedDir" ] || { echo "install.sh: unexpected archive layout — no ripwire-* directory found" >&2; exit 1; }
[ -x "$extractedDir/ripwire" ] || { echo "install.sh: extracted archive has no executable ripwire binary" >&2; exit 1; }

mkdir -p "$binDir"
cp "$extractedDir/ripwire" "$binDir/ripwire"
chmod +x "$binDir/ripwire"

echo "install.sh: installed $binDir/ripwire ($( "$binDir/ripwire" --version 2>&1 || echo "version check failed" ))"

case ":$PATH:" in
    *":$binDir:"*) ;;
    *) echo "install.sh: $binDir is not on PATH — add it, e.g. export PATH=\"$binDir:\$PATH\"" ;;
esac
