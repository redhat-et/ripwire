#!/usr/bin/env bash
# Build ctxpack and install it onto PATH, decoupled from the gitignored build/ dir (previously PATH
# pointed at a symlink straight into build/, which breaks on any clean rebuild). Idempotent — safe to
# re-run after any source change. Run: ./install.sh
#
# The install prefix is detected, not hardcoded: /opt/homebrew is wrong on Intel macOS (brew
# lives at /usr/local there) and on any machine with no Homebrew at all (most Linux). Detect instead:
#   1) CTXPACK_INSTALL_PREFIX env override, for anyone who wants a specific location
#   2) `brew --prefix` if brew is on PATH (covers both Apple Silicon /opt/homebrew and Intel /usr/local)
#   3) ~/.local as the no-brew fallback (no sudo needed, commonly already on PATH)
set -eu
dir="$( cd "$( dirname "$0" )" && pwd )"
cd "$dir"

if [ -n "${CTXPACK_INSTALL_PREFIX:-}" ]; then
    prefix="$CTXPACK_INSTALL_PREFIX"
elif command -v brew >/dev/null 2>&1; then
    prefix="$( brew --prefix )"
else
    prefix="$HOME/.local"
    echo "install.sh: no brew on PATH — installing under $prefix (set CTXPACK_INSTALL_PREFIX to override)"
fi

cmake -S . -B build -DCTXPACK_NATIVE=ON
cmake --build build -j
cmake --install build --prefix "$prefix" --component ctxpack

case ":$PATH:" in
    *":$prefix/bin:"*) ;;
    *) echo "install.sh: $prefix/bin is not on PATH — add it, e.g. export PATH=\"$prefix/bin:\$PATH\"" ;;
esac

echo "installed: $(command -v ctxpack || echo "$prefix/bin/ctxpack (not yet on PATH)")"
