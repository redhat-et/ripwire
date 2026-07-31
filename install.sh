#!/usr/bin/env bash
# Build ripwire and install it onto PATH, decoupled from the gitignored build/ dir (previously PATH
# pointed at a symlink straight into build/, which breaks on any clean rebuild). Idempotent — safe to
# re-run after any source change. Run: ./install.sh
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

cmake -S . -B build -DRIPWIRE_NATIVE=ON
cmake --build build -j
cmake --install build --prefix "$prefix" --component ripwire

case ":$PATH:" in
    *":$prefix/bin:"*) ;;
    *) echo "install.sh: $prefix/bin is not on PATH — add it, e.g. export PATH=\"$prefix/bin:\$PATH\"" ;;
esac

echo "installed: $(command -v ripwire || echo "$prefix/bin/ripwire (not yet on PATH)")"
