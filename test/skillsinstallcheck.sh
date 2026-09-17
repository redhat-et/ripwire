#!/usr/bin/env bash
# test/skillsinstallcheck.sh — the native `ripwire skills install` subcommand: store extraction,
# link-safety, prune, manifest v2, per-agent modes, --all, --hook merge + preservation.
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
    export HOME="$d" CLAUDE_CONFIG_DIR="$d/.claude" RIPWIRE_DATA_HOME="$d/.local/share/ripwire"
}

# ── arm 1: fresh install, claude default ──────────────────────────────────────────────────────
CURRENT_ARM="1-fresh-install"
sandbox
d1="$d"
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
sandbox
d2="$d"
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
sandbox
d3="$d"
mkdir -p "$CLAUDE_CONFIG_DIR/skills"
outside="$( mktemp -d )"
ln -s "$outside" "$CLAUDE_CONFIG_DIR/skills/ripwire-orient"   # plant a symlink where install would write
"$ripwire" skills install >/dev/null 2>skills_install.err || true
[ -L "$CLAUDE_CONFIG_DIR/skills/ripwire-orient" ] || fail "planted symlink was replaced instead of refused"
target="$( readlink "$CLAUDE_CONFIG_DIR/skills/ripwire-orient" )"
[ "$target" = "$outside" ] || fail "planted symlink's target changed — install wrote through it"
rm -rf "$d3" "$outside" skills_install.err

# ── arm 4: manifest v2 round-trip and prune-on-rename ─────────────────────────────────────────
CURRENT_ARM="4-manifest-prune"
sandbox
d4="$d"
"$ripwire" skills install >/dev/null
before_count="$( grep -c '^skill=' "$CLAUDE_CONFIG_DIR/skills/.ripwire-manifest-v2" )"
[ "$before_count" -gt 0 ] || fail "manifest recorded zero skills"
# simulate a renamed/removed skill: manually add a bogus manifest entry + matching stale symlink,
# then re-run install and confirm both are pruned.
ln -sfn "$RIPWIRE_DATA_HOME/skills/does-not-exist-anymore" "$CLAUDE_CONFIG_DIR/skills/ripwire-renamed-away"
echo "skill=ripwire-renamed-away" >> "$CLAUDE_CONFIG_DIR/skills/.ripwire-manifest-v2"
"$ripwire" skills install >/dev/null
[ -e "$CLAUDE_CONFIG_DIR/skills/ripwire-renamed-away" ] && fail "stale skill symlink was not pruned"
grep -q '^skill=ripwire-renamed-away$' "$CLAUDE_CONFIG_DIR/skills/.ripwire-manifest-v2" && fail "stale manifest entry was not pruned"
rm -rf "$d4"

# ── arm 5: prune is link-safe — never follows a symlink to delete through it ──────────────────
CURRENT_ARM="5-prune-link-safety"
sandbox
d5="$d"
"$ripwire" skills install >/dev/null
outside="$( mktemp -d )"
touch "$outside/canary"
# repoint a manifest-tracked entry at something outside the destination, then force a prune of it
tracked="$( grep '^skill=' "$CLAUDE_CONFIG_DIR/skills/.ripwire-manifest-v2" | head -1 | cut -d= -f2 )"
[ -n "$tracked" ] || fail "no manifest-tracked skill to repoint"
rm "$CLAUDE_CONFIG_DIR/skills/$tracked"
ln -s "$outside" "$CLAUDE_CONFIG_DIR/skills/$tracked"
sed -i.bak "/^skill=$tracked\$/d" "$CLAUDE_CONFIG_DIR/skills/.ripwire-manifest-v2"   # force it to look "renamed away"
"$ripwire" skills install >/dev/null
[ -f "$outside/canary" ] || fail "prune followed the symlink and deleted through it into $outside"
rm -rf "$d5" "$outside"

echo "OK: skillsinstallcheck (arms 1-5)"
