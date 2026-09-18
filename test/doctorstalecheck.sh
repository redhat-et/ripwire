#!/usr/bin/env bash
# test/doctorstalecheck.sh — --doctor must not misreport a mise/aqua shim as STALE, must never
# execute anything to figure that out, and must distinguish "not yet installed" from "stale".
# --agent=claude is required: agent-surface checks are empty otherwise (doctorAgentRows).
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
ripwire="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${ripwire#/}" = "$ripwire" ] && ripwire="$ROOT/$ripwire"          # allow repo-relative RIPWIRE_BIN
[ -x "$ripwire" ] || { echo "SKIP: $ripwire not built" >&2; exit 0; }

fail() { echo "FAIL ($CURRENT_ARM): $1" >&2; exit 1; }

# Call directly (`sandbox`), never as `x="$( sandbox )"` — command substitution forks a subshell, and
# an export made there never reaches the parent, so "$ripwire" would see the real, not the sandboxed, env.
sandbox() {
    d="$( mktemp -d )"
    export HOME="$d" CLAUDE_CONFIG_DIR="$d/.claude"
}

# ── arm a: exactly one managed install under a simulated mise data dir -> resolved, not STALE ──
CURRENT_ARM="a-single-managed-install"
sandbox
da="$d"
export MISE_DATA_DIR="$da/mise"
mkdir -p "$MISE_DATA_DIR/shims" "$MISE_DATA_DIR/installs/ripwire/0.9.9/bin"
cp "$ripwire" "$MISE_DATA_DIR/installs/ripwire/0.9.9/bin/ripwire"
cat > "$MISE_DATA_DIR/shims/ripwire" <<'SH'
#!/bin/sh
echo "this is a shim, not the real binary — must never be executed by --doctor"
exit 99
SH
chmod +x "$MISE_DATA_DIR/shims/ripwire"
out_a="$( PATH="$MISE_DATA_DIR/shims:$PATH" "$ripwire" "$ROOT" --doctor --agent=claude 2>&1 )"
echo "$out_a" | grep -q 'n="claude-binary" ok="0"' && fail "shim was misreported as broken/STALE"
rm -rf "$da"
unset MISE_DATA_DIR

# ── arm b: ambiguous managed layout (multiple versions) -> disclosed-unknown, not STALE, not ok ─
CURRENT_ARM="b-ambiguous-managed-install"
sandbox
db="$d"
export MISE_DATA_DIR="$db/mise"
mkdir -p "$MISE_DATA_DIR/shims" "$MISE_DATA_DIR/installs/ripwire/0.9.8/bin" "$MISE_DATA_DIR/installs/ripwire/0.9.9/bin"
cp "$ripwire" "$MISE_DATA_DIR/installs/ripwire/0.9.9/bin/ripwire"
cp "$ripwire" "$MISE_DATA_DIR/shims/ripwire"   # a real binary here would make this NOT a shim; that's fine for this arm
PATH="$MISE_DATA_DIR/shims:$PATH" "$ripwire" "$ROOT" --doctor --agent=claude 2>&1 | grep -q 'managed_unverified="1"' \
    || fail "ambiguous managed layout was not reported as disclosed-unknown"
rm -rf "$db"
unset MISE_DATA_DIR

# ── arm c: not-yet-installed vs stale are distinguished ─────────────────────────────────────────
CURRENT_ARM="c-not-installed-vs-stale"
sandbox
dc="$d"
"$ripwire" "$ROOT" --doctor --agent=claude 2>&1 | grep -q 'n="claude-skills"[^>]*not_installed="1"' || fail "missing manifest was not reported as not-installed"
mkdir -p "$CLAUDE_CONFIG_DIR/skills"
printf 'version=2\nsource=0.0.1-deadbeef\n' > "$CLAUDE_CONFIG_DIR/skills/.ripwire-manifest-v2"
"$ripwire" "$ROOT" --doctor --agent=claude 2>&1 | grep -q 'n="claude-skills"[^>]*stale="1"' || fail "mismatched source= was not reported as stale"
rm -rf "$dc"

echo "OK: doctorstalecheck"
