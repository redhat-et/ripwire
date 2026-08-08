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
cmake --install build-install --prefix "$prefix" --component ripwire

case ":$PATH:" in
    *":$prefix/bin:"*) ;;
    *) echo "install.sh: $prefix/bin is not on PATH — add it, e.g. export PATH=\"$prefix/bin:\$PATH\"" ;;
esac

echo "installed: $(command -v ripwire || echo "$prefix/bin/ripwire (not yet on PATH)")"
