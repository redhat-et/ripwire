#!/usr/bin/env bash
# Runs inside the SWE-bench container at agent startup (the ARISE bundle's install.sh slot).
#
# ripwire is a single self-contained C++ binary, not a pip package, so this installer does NOT
# build or download anything: it verifies that a binary for THIS container's platform is present
# and pins it into RIPWIRE_BIN for the bin/ shims. Two accepted sources, in order:
#   1. RIPWIRE_BIN already set by the harness (the registered posture — the harness pins the binary);
#   2. a `ripwire` binary staged next to this script (e.g. a Linux build copied in by the runner).
# Anything else is a loud, immediate failure — the shims must never fall back to a PATH guess.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ -n "${RIPWIRE_BIN:-}" && -x "${RIPWIRE_BIN}" ]]; then
    echo "[ripwire/install.sh] Using pinned RIPWIRE_BIN=${RIPWIRE_BIN}"
elif [[ -x "${SCRIPT_DIR}/ripwire" ]]; then
    export RIPWIRE_BIN="${SCRIPT_DIR}/ripwire"
    echo "[ripwire/install.sh] Using staged binary ${RIPWIRE_BIN}"
else
    echo "[ripwire/install.sh] ERROR: no ripwire binary — set RIPWIRE_BIN or stage one next to install.sh." >&2
    echo "[ripwire/install.sh] The binary must be built for THIS container's platform (linux)." >&2
    exit 1
fi

"${RIPWIRE_BIN}" --help >/dev/null || { echo "[ripwire/install.sh] ERROR: ${RIPWIRE_BIN} does not run here (wrong platform?)." >&2; exit 1; }
echo "[ripwire/install.sh] OK."
