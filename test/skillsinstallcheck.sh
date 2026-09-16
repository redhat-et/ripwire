#!/usr/bin/env bash
# test/skillsinstallcheck.sh — the native `ripwire skills install` subcommand: store extraction,
# link-safety, prune, manifest v2, per-agent modes, --all, --hook merge + preservation.
set -eu
cd "$( dirname "$0" )/.."
ripwire="${1:-./build/ripwire}"
[ -x "$ripwire" ] || { echo "SKIP: $ripwire not built" >&2; exit 0; }

fail() { echo "FAIL ($CURRENT_ARM): $1" >&2; exit 1; }

sandbox() {
    d="$( mktemp -d )"
    export HOME="$d" CLAUDE_CONFIG_DIR="$d/.claude" RIPWIRE_DATA_HOME="$d/.local/share/ripwire"
    echo "$d"
}

# ── arm 1: fresh install, claude default ──────────────────────────────────────────────────────
CURRENT_ARM="1-fresh-install"
d1="$( sandbox )"
"$ripwire" skills install >/dev/null
[ -d "$CLAUDE_CONFIG_DIR/skills" ] || fail "no skills directory created"
[ -f "$CLAUDE_CONFIG_DIR/skills/.ripwire-manifest-v2" ] || fail "no v2 manifest written"
grep -q '^version=2$' "$CLAUDE_CONFIG_DIR/skills/.ripwire-manifest-v2" || fail "manifest missing version=2"
grep -q '^source=' "$CLAUDE_CONFIG_DIR/skills/.ripwire-manifest-v2" || fail "manifest missing source="
[ "$( find "$CLAUDE_CONFIG_DIR/skills" -maxdepth 1 -name 'ripwire-*' -type l | wc -l )" -gt 0 ] \
    || fail "no ripwire-* skill symlinks created"
rm -rf "$d1"

# ── arm 2: idempotent store extraction ────────────────────────────────────────────────────────
CURRENT_ARM="2-idempotent-store"
d2="$( sandbox )"
"$ripwire" skills install >/dev/null
store_dir="$( find "$RIPWIRE_DATA_HOME/skills" -maxdepth 1 -mindepth 1 -type d | head -1 )"
[ -n "$store_dir" ] || fail "no store directory created"
before="$( stat -f '%m' "$store_dir" 2>/dev/null || stat -c '%Y' "$store_dir" )"
sleep 1
"$ripwire" skills install >/dev/null   # second run: must not re-extract
after="$( stat -f '%m' "$store_dir" 2>/dev/null || stat -c '%Y' "$store_dir" )"
[ "$before" = "$after" ] || fail "store directory was re-extracted on a second run (should be idempotent)"
rm -rf "$d2"

# ── arm 3: link-safety — refuses to write through a pre-planted symlink at the destination ────
CURRENT_ARM="3-link-safety-destination"
d3="$( sandbox )"
mkdir -p "$CLAUDE_CONFIG_DIR/skills"
outside="$( mktemp -d )"
ln -s "$outside" "$CLAUDE_CONFIG_DIR/skills/ripwire-orient"   # plant a symlink where install would write
"$ripwire" skills install >/dev/null 2>skills_install.err || true
[ -L "$CLAUDE_CONFIG_DIR/skills/ripwire-orient" ] || fail "planted symlink was replaced instead of refused"
target="$( readlink "$CLAUDE_CONFIG_DIR/skills/ripwire-orient" )"
[ "$target" = "$outside" ] || fail "planted symlink's target changed — install wrote through it"
rm -rf "$d3" "$outside" skills_install.err

echo "OK: skillsinstallcheck (arms 1-3)"
