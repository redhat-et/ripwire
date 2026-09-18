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
# Simulate a stale, manifest-TRACKED entry (mirrors arm 4's construction) that is itself a symlink
# pointing OUTSIDE the destination — pruneStale must recognize it as previously-tracked-but-no-
# longer-current (it must be IN the previous manifest's skill= list for pruneStale to ever consider
# it at all) and remove the destination ENTRY via unlink, without ever following the link into
# $outside to delete through it.
ln -s "$outside" "$CLAUDE_CONFIG_DIR/skills/ripwire-renamed-away"
echo "skill=ripwire-renamed-away" >> "$CLAUDE_CONFIG_DIR/skills/.ripwire-manifest-v2"
"$ripwire" skills install >/dev/null
[ -f "$outside/canary" ] || fail "prune followed the symlink and deleted through it into $outside"
[ -e "$CLAUDE_CONFIG_DIR/skills/ripwire-renamed-away" ] && fail "the link-unsafe stale entry was not pruned"
rm -rf "$d5" "$outside"

# ── arm 6: per-agent modes reach the right destination ──────────────────────────────────────────
CURRENT_ARM="6-per-agent-modes"
sandbox
d6="$d"
"$ripwire" skills install --codex >/dev/null
[ -d "$HOME/.agents/skills" ] || fail "--codex did not install to \$AGENTS_HOME/skills"
sandbox
d6b="$d"
"$ripwire" skills install --hermes >/dev/null
[ -d "$HOME/.hermes/skills" ] || fail "--hermes did not install to \$HERMES_HOME/skills"
rm -rf "$d6" "$d6b"

# ── arm 7: --all detects and activates every present agent ─────────────────────────────────────
CURRENT_ARM="7-all-detection"
sandbox
d7="$d"
mkdir -p "$HOME/.claude" "$HOME/.agents"   # make claude + codex "present" per whatever getAgentConfigs checks
out="$( "$ripwire" skills install --all )"
echo "$out" | grep -qi claude || fail "--all summary did not mention claude"
[ -d "$CLAUDE_CONFIG_DIR/skills" ] || fail "--all did not activate claude"
[ -d "$HOME/.agents/skills" ] || fail "--all did not activate codex"
rm -rf "$d7"

# ── arm 8: --contributor gates the contributor-only skill ──────────────────────────────────────
CURRENT_ARM="8-contributor-gating"
sandbox
d8="$d"
"$ripwire" skills install >/dev/null
[ -e "$CLAUDE_CONFIG_DIR/skills/ripwire-opt-remarks" ] && fail "contributor skill installed without --contributor"
"$ripwire" skills install --contributor >/dev/null
[ -e "$CLAUDE_CONFIG_DIR/skills/ripwire-opt-remarks" ] || fail "contributor skill missing after --contributor"
rm -rf "$d8"

# ── arm 9: --hook merges into settings.json, preserving pre-existing unrelated entries ─────────
CURRENT_ARM="9-hook-merge-preservation"
sandbox
d9="$d"
mkdir -p "$CLAUDE_CONFIG_DIR"
cat > "$CLAUDE_CONFIG_DIR/settings.json" <<'JSON'
{"hooks":{"PreToolUse":[{"matcher":"SomeOtherTool","hooks":[{"type":"command","command":"/somewhere/unrelated.sh"}]}]}}
JSON
"$ripwire" skills install --hook >/dev/null
grep -q "unrelated.sh" "$CLAUDE_CONFIG_DIR/settings.json" || fail "pre-existing unrelated hook entry was dropped by the merge"
grep -q "ripwire-nudge.sh" "$CLAUDE_CONFIG_DIR/settings.json" || fail "ripwire's own hook was not added"
python3 -c "import json; json.load(open('$CLAUDE_CONFIG_DIR/settings.json'))" || fail "settings.json is not valid JSON after merge"
rm -rf "$d9"

# ── arm 10: extracted hook scripts are executable (0755), extracted skill files are not ────────
CURRENT_ARM="10-hook-mode-executable"
sandbox
d10="$d"
"$ripwire" skills install >/dev/null
hook_store="$( find "$RIPWIRE_DATA_HOME/hooks" -name '*.sh' | head -1 )"
[ -n "$hook_store" ] || fail "no extracted hook script found under \$RIPWIRE_DATA_HOME/hooks"
[ -x "$hook_store" ] || fail "extracted hook script $hook_store is not executable"
skill_store="$( find "$RIPWIRE_DATA_HOME/skills" -name 'SKILL.md' | head -1 )"
[ -n "$skill_store" ] || fail "no extracted SKILL.md found under \$RIPWIRE_DATA_HOME/skills"
[ -x "$skill_store" ] && fail "extracted skill file $skill_store is unexpectedly executable"
rm -rf "$d10"

# ── arm 11: a bare positional path is loudly refused, never silently installed to the default home ──
CURRENT_ARM="11-positional-path-refused"
sandbox
d11="$d"
bogus_dest="$d11/somewhere-explicit"
"$ripwire" skills install "$bogus_dest" >skills_install.out 2>skills_install.err
rc=$?
[ "$rc" -ne 0 ] || fail "positional destination path was accepted (exit 0) instead of refused"
grep -q "$bogus_dest" skills_install.err || fail "refusal did not name the rejected path in stderr"
[ -e "$CLAUDE_CONFIG_DIR/skills" ] && fail "refused run still created the default agent home ($CLAUDE_CONFIG_DIR/skills)"
[ -e "$bogus_dest" ] && fail "refused run still created the (unsupported) explicit destination"
rm -rf "$d11" skills_install.out skills_install.err

echo "OK: skillsinstallcheck (arms 1-11)"
