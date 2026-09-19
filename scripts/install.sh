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
#   RIPWIRE_VERSION           a specific tag (e.g. "v0.2.0"); default: latest release. On an Intel Mac, v0.6.1 is
#                             the last release with a binary (see "Intel macOS" below).
#   RIPWIRE_INSTALL_PREFIX    install prefix; the binary lands in "$RIPWIRE_INSTALL_PREFIX/bin". Default:
#                             ~/.local/bin (no sudo needed). Pass /usr/local for the traditional location
#                             (may prompt for sudo to write there).
#   RIPWIRE_INSTALL_YES=1     skip the interactive confirmation (for CI / scripted installs).
#   RIPWIRE_SKIP_CPU_CHECK=1  skip the x86-64-v3 CPU pre-check ("CPU floor" below). The downloaded binary is
#                             still run before it is installed, so a CPU that truly lacks v3 is still refused.
#   RIPWIRE_CPUINFO           read the Linux CPU flags from this file instead of /proc/cpuinfo (test seam).
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

sourceBuildHint()
{
    echo "  Build from source instead, tuned for this CPU (https://github.com/${repo}/blob/main/INSTALL.md#build-from-source):" >&2
    echo "    git clone https://github.com/${repo}.git && cd ${repo##*/} && ./install.sh" >&2
    echo "  ./install.sh configures -DRIPWIRE_NATIVE=ON (-march=native); a plain cmake build keeps the x86-64-v3 floor." >&2
}

# ── Intel macOS: the last prebuilt binary is 0.6.1 ─────────────────────────────────────────────────────────
# release.yml built macos-x64 on an arm64 runner (cross-compiled, PGO-trained and smoke-run under Rosetta 2) and
# dropped that leg after 0.6.1. The arch map above is OS-agnostic, so without this stop an Intel Mac asks a later
# release for a macos-x64 asset and hears only "has no asset named ...". The stop keys on the version, never on
# the asset list, and each glob matches a whole version, so 0.10.0 is never read as older than 0.6.1. 0.6.1 and
# everything before it keep their macos-x64 asset, so pinning RIPWIRE_VERSION=v0.6.1 still installs. A Rosetta
# shell on Apple silicon also reports x86_64; it is sent to a native arm64 shell, where the arm64 binary installs.
# test/releaseinstallcheck.sh arms (H1)-(H7) pin all of it.
intelMacLast=0.6.1
if [ "$assetOs" = macos ] && [ "$assetArch" = x64 ]; then
    case "$resolvedVersion" in
        0.[0-5].*|0.6.[01]) ;;
        *)
            echo "install.sh: ripwire ${resolvedTag} has no Intel macOS build: prebuilt Intel macOS (x86-64) binaries end with ${intelMacLast}." >&2
            if [ "$( sysctl -n sysctl.proc_translated 2>/dev/null || true )" = 1 ]; then
                echo "  This shell runs under Rosetta on an Apple silicon Mac. Run the installer from a native arm64 shell" >&2
                echo "  to install the arm64 binary." >&2
            else
                echo "  Install ${intelMacLast}, the last one, by pinning it:" >&2
                printf '    RIPWIRE_REPO=%s RIPWIRE_VERSION=v%s bash -c "$(curl -fsSL https://raw.githubusercontent.com/%s/main/scripts/install.sh)"\n' \
                    "$repo" "$intelMacLast" "$repo" >&2
                sourceBuildHint
            fi
            echo "  Nothing was downloaded." >&2
            exit 1
            ;;
    esac
fi

assetName="ripwire-${resolvedVersion}-${assetOs}-${assetArch}.tar.gz"
assetUrl="$( printf '%s' "$releaseJson" | grep -o "\"browser_download_url\": *\"[^\"]*${assetName}\"" | sed -E 's/.*"(https[^"]+)"/\1/' | head -1 )"
[ -n "$assetUrl" ] || {
    echo "install.sh: release $resolvedTag has no asset named $assetName" >&2
    echo "  (built for ${assetOs}/${assetArch} — this platform may not be published for this release)" >&2
    exit 1
}

# ── CPU floor: from 0.6.0 the prebuilt x86-64 binary requires x86-64-v3 ────────────────────────────────────
# cmake/PortableFlags.cmake builds every non-native x86-64 binary with -march=x86-64-v3: AVX, AVX2, BMI1, BMI2,
# F16C, FMA, LZCNT, MOVBE — the RHEL 10 floor, roughly Intel Haswell (2013) / AMD Excavator (2015) onward. On an
# older CPU that binary dies with SIGILL the first time it runs, and this installer used to report that as
# "refusing version mismatch" with an empty version. So the flags are read BEFORE the download, and a CPU below
# the floor stops here naming what it lacks. On Linux that means EVERY processor's flags, not the first record's:
# the scheduler can run the binary on any online processor, so a feature counts only if all of them carry it.
# Four rules keep the check from refusing a machine the binary runs on:
#   * no guessing: unreadable flags (no /proc/cpuinfo, a sysctl key missing) give no verdict, and the
#     verification run after the download names a SIGILL for what it is;
#   * a Rosetta-translated shell is not judged: its feature bits describe the translator, not the machine;
#   * releases up to 0.5.x were built without the floor, so pinning one with RIPWIRE_VERSION is not judged;
#   * RIPWIRE_SKIP_CPU_CHECK=1 overrides a verdict the user knows is wrong (a VM hiding a flag its host has).
# test/releaseinstallcheck.sh arms (G1)-(G15) pin all of it; sourceBuildHint is defined above the Intel macOS stop.
cpuFloor=0
case "$resolvedVersion" in
    0.[0-5].*) ;;
    *) if [ "$assetArch" = x64 ]; then cpuFloor=1; fi ;;
esac
cpuTranslated=0
if [ "$cpuFloor" = 1 ] && [ "$osName" = Darwin ] && [ "$( sysctl -n sysctl.proc_translated 2>/dev/null || true )" = 1 ]; then
    cpuTranslated=1
fi
if [ "$cpuFloor" = 1 ] && [ "$cpuTranslated" = 0 ] && [ "${RIPWIRE_SKIP_CPU_CHECK:-0}" != 1 ]; then
    # cpuFlags holds ONE RECORD PER LINE, each padded with spaces so " name " only ever matches a whole flag.
    cpuFlags=""
    if [ "$osName" = Linux ]; then
        # Names as the kernel prints them (arch/x86/include/asm/cpufeatures.h): LZCNT is "abm". "lzcnt" is taken
        # as well, so a synthetic cpuinfo that spells the instruction's own name is never refused over it. The kernel
        # prints a "flags" line per online processor and each stays its own record ("vmx flags" is not one); the
        # alias is added inside each record, so two records that spell LZCNT differently still agree.
        cpuSource="${RIPWIRE_CPUINFO:-/proc/cpuinfo}"
        cpuNeed="avx:AVX avx2:AVX2 bmi1:BMI1 bmi2:BMI2 f16c:F16C fma:FMA movbe:MOVBE abm:LZCNT"
        cpuFlags="$( grep '^flags[[:space:]]*:' "$cpuSource" 2>/dev/null | sed 's/^[^:]*:/ /; s/$/ /; s/ lzcnt / lzcnt abm /' || true )"
    else
        # Names as XNU prints them (osfmk/i386/cpuid.c): AVX is "AVX1.0", AVX2/BMI1/BMI2 are leaf-7 bits and LZCNT
        # an extended one. A key that is missing or empty leaves no verdict, never a list of "missing" features.
        # The three keys describe one CPU model, so they join into a single record.
        cpuSource="sysctl machdep.cpu"
        cpuNeed="AVX1.0:AVX AVX2:AVX2 BMI1:BMI1 BMI2:BMI2 F16C:F16C FMA:FMA MOVBE:MOVBE LZCNT:LZCNT"
        for cpuKey in machdep.cpu.features machdep.cpu.leaf7_features machdep.cpu.extfeatures; do
            cpuValue="$( sysctl -n "$cpuKey" 2>/dev/null || true )"
            if [ -z "$cpuValue" ]; then cpuFlags=""; break; fi
            cpuFlags="$cpuFlags $cpuValue "
        done
    fi
    # A feature is missing when ANY record lacks it: grep -v counts the records without the name. -c reads to the
    # end (-q would exit at the first hit and SIGPIPE the printf on a many-core cpuinfo); a grep that fails prints
    # no count, and no count names nothing missing.
    cpuLacks=""
    if [ -n "$cpuFlags" ]; then
        for cpuPair in $cpuNeed; do
            cpuWithout="$( printf '%s\n' "$cpuFlags" | grep -vcF " ${cpuPair%%:*} " )" || true
            [ "${cpuWithout:-0}" = 0 ] || cpuLacks="$cpuLacks ${cpuPair#*:}"
        done
    fi
    if [ -n "$cpuLacks" ]; then
        echo "install.sh: this CPU is below x86-64-v3, which the prebuilt x86-64 ripwire ${resolvedTag} requires." >&2
        echo "  missing on at least one CPU:${cpuLacks} (read from ${cpuSource})" >&2
        echo "  x86-64-v3 is AVX, AVX2, BMI1, BMI2, F16C, FMA, LZCNT and MOVBE: roughly Intel Haswell (2013) or AMD Excavator (2015) and newer." >&2
        echo "  That binary would die with SIGILL (illegal instruction) here, so nothing was downloaded." >&2
        sourceBuildHint
        echo "  If this verdict is wrong for this machine (a VM that hides a flag its host has), RIPWIRE_SKIP_CPU_CHECK=1 skips it;" >&2
        echo "  the binary is still test-run before it is installed." >&2
        exit 1
    fi
fi

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

# RUN IT BEFORE INSTALLING IT, AND READ HOW IT EXITED. This was `ripwire --version 2>&1 | grep | head -1`, and a
# pipeline's status is its last command's: a binary that could not run at all — SIGILL below the x86-64 floor,
# a loader refusing an older glibc — left an empty version and the report "refusing version mismatch". A
# mismatch now means one thing only: a binary that RAN and named another version (releaseinstallcheck (G1)-(G4)).
verifyRc=0
verifyOut="$( "$extractedDir/ripwire" --version 2>&1 )" || verifyRc=$?
if [ "$verifyRc" -ne 0 ]; then
    if [ "$verifyRc" -eq 132 ]; then
        verifyHow="was killed by SIGILL (illegal instruction)"
    elif [ "$verifyRc" -gt 128 ]; then
        verifyHow="was killed by signal $(( verifyRc - 128 ))"
    else
        verifyHow="exited $verifyRc"
    fi
    echo "install.sh: the ripwire binary in release $resolvedTag $verifyHow when run as \`ripwire --version\`; nothing was installed." >&2
    [ -z "$verifyOut" ] || printf '%s\n' "$verifyOut" | head -5 | sed 's/^/  | /' >&2
    if [ "$verifyRc" -eq 132 ] && [ "$cpuFloor" = 1 ]; then
        if [ "$cpuTranslated" = 1 ]; then
            echo "  This shell runs under Rosetta, and the x86-64 binary requires x86-64-v3 instructions (AVX2, BMI2, FMA, ...)." >&2
            echo "  Run the installer from a native arm64 shell to install the arm64 binary instead." >&2
        else
            echo "  This binary requires an x86-64-v3 CPU (AVX2, BMI2, FMA, ...); this CPU may be older." >&2
            sourceBuildHint
        fi
    fi
    exit 1
fi
binaryVersion="$( printf '%s\n' "$verifyOut" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 )"
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

# ── activate skills/hooks (#225: embedded in the binary, no more $prefix/share/ripwire staging) ────
# `ripwire skills install --all` does its own per-agent detection; never fails the install over an
# activation failure (degrades to a printed hint), and never registers hooks without `--hook` — those
# carry a data-capture disclosure a user must read and accept.
# RIPWIRE_NO_ACTIVATE=1 installs without activating; test/releaseinstallcheck.sh arms (E1)-(E6) pin it.
if [ -z "${RIPWIRE_NO_ACTIVATE:-}" ]; then
    ACTIVATE_OUT="$( "$binDir/ripwire" skills install --all )"; ACTIVATE_RC=$?
    printf '%s\n' "$ACTIVATE_OUT"
    if [ "$ACTIVATE_RC" -ne 0 ]; then
        echo "install.sh: could not activate ripwire skills for one or more agents; run: \"$binDir/ripwire\" skills install --all" >&2
    fi
    # M9 (round-2 review): the hint is only useful if something was actually activated to hook —
    # printing it after "0 agent(s) configured" would advertise a --hook flag with nothing to attach to.
    CONFIGURED="$( printf '%s' "$ACTIVATE_OUT" | sed -n 's/.*: \([0-9][0-9]*\) agent(s) configured.*/\1/p' )"
    if [ -n "$CONFIGURED" ] && [ "$CONFIGURED" -gt 0 ]; then
        echo "  Optional advisory hooks: \"$binDir/ripwire\" skills install --all --hook"
    else
        echo "  Nothing was activated — no detected agent to hook into."
    fi
else
    echo "install.sh: RIPWIRE_NO_ACTIVATE set — skills not activated. Run \"$binDir/ripwire\" skills install --all when ready."
fi
