#!/usr/bin/env bash
# test/skillsinstallcheck.sh — the native `ripwire skills install` subcommand: store extraction,
# link-safety, prune, manifest v2, per-agent modes, --all, --hook merge + preservation.
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
ripwire="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${ripwire#/}" = "$ripwire" ] && ripwire="$ROOT/$ripwire"          # allow repo-relative RIPWIRE_BIN
[ -x "$ripwire" ] || { echo "SKIP: $ripwire not built" >&2; exit 0; }

fail() { echo "FAIL ($CURRENT_ARM): $1" >&2; exit 1; }

# GNU `stat -f` is filesystem stat, not BSD's format flag — it succeeds with junk, so a
# `stat -f ... || stat -c ...` one-liner never reaches the fallback on Linux (see cachehashcheck.sh's
# comment on this exact trap). Detect the flavour once instead, matching the rest of the suite.
if stat --version >/dev/null 2>&1; then   # GNU coreutils
    mtime_of() { stat -c '%Y' "$1" 2>/dev/null; }
else                                       # BSD / macOS
    mtime_of() { stat -f '%m' "$1" 2>/dev/null; }
fi

# Call directly (`sandbox`), never as `x="$( sandbox )"` — command substitution forks a subshell, and
# an export made there never reaches the parent, so "$ripwire" would see the real, not the sandboxed, env.
sandbox() {
    d="$( mktemp -d )"
    . "$ROOT/test/lib/unset-agent-env-variables.sh"
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
before="$( mtime_of "$store_dir" )"
sleep 1
"$ripwire" skills install >/dev/null   # second run: must not re-extract
after="$( mtime_of "$store_dir" )"
[ "$before" = "$after" ] || fail "store directory was re-extracted on a second run (should be idempotent)"
rm -rf "$d2"

# ── arm 3: link-safety — refuses to write through a pre-planted symlink at the destination ────
CURRENT_ARM="3-link-safety-destination"
sandbox
d3="$d"
mkdir -p "$CLAUDE_CONFIG_DIR/skills"
outside="$( mktemp -d )"
ln -s "$outside" "$CLAUDE_CONFIG_DIR/skills/ripwire-orient"   # plant a symlink where install would write
out3="$( "$ripwire" skills install 2>"$d3/skills_install.err" )" || true
[ -L "$CLAUDE_CONFIG_DIR/skills/ripwire-orient" ] || fail "planted symlink was replaced instead of refused"
target="$( readlink "$CLAUDE_CONFIG_DIR/skills/ripwire-orient" )"
[ "$target" = "$outside" ] || fail "planted symlink's target changed — install wrote through it"
# I1 (round-2 review): a foreign-but-live entry skipped without --force must be COUNTED, not silent —
# the summary line must say so, not just report a linked count one short of the shipped total.
printf '%s' "$out3" | grep -qE '[0-9]+ skipped \(run --force to relink foreign entries\)' \
    || fail "a bare install that skipped a foreign symlink did not report a skipped count (I1)"
rm -rf "$d3" "$outside"

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

# ── arm 11: explicit DEST_PATH positional installs into that literal path, not the default agent home ──
CURRENT_ARM="11-explicit-dest-path"
sandbox
d11="$d"
explicit_dest="$d11/an-explicit-dest"
"$ripwire" skills install "$explicit_dest" >/dev/null
[ -d "$explicit_dest" ] || fail "explicit DEST_PATH was not created"
[ "$( find "$explicit_dest" -maxdepth 1 -name 'ripwire-*' -type l | wc -l )" -gt 0 ] \
    || fail "no ripwire-* skill symlinks created under the explicit DEST_PATH"
[ -f "$explicit_dest/.ripwire-manifest-v2" ] || fail "no v2 manifest written under the explicit DEST_PATH"
[ -e "$CLAUDE_CONFIG_DIR/skills" ] && fail "explicit DEST_PATH silently installed into the default agent home instead"
rm -rf "$d11"

# ── arm 12: a second bare positional is refused loudly, not silently accepted as a second dest ────
CURRENT_ARM="12-second-positional-refused"
sandbox
d12="$d"
"$ripwire" skills install "$d12/one" "$d12/two" >"$d12/skills_install.err" 2>&1
rc=$?
[ "$rc" -ne 0 ] || fail "a second destination positional exited 0 instead of being refused"
grep -qi "only one destination path" "$d12/skills_install.err" || fail "refusal did not name the reason"
[ -e "$d12/one" ] && fail "first destination was installed to despite the refusal"
[ -e "$d12/two" ] && fail "second destination was installed to despite the refusal"
rm -rf "$d12"

# an empty positional is not a path either — must not silently fall through to the default agent home
# (installForAgent's `!explicitDest.empty()` override is the exact seam this would slip through).
sandbox
d12b="$d"
"$ripwire" skills install "" >"$d12b/skills_install.err" 2>&1
rc=$?
[ "$rc" -ne 0 ] || fail "an empty destination positional exited 0 instead of being refused"
[ -e "$CLAUDE_CONFIG_DIR/skills" ] && fail "an empty destination positional silently installed into the default agent home"
rm -rf "$d12b"

# ── arm 13: --hook with an explicit DEST_PATH is refused (path installs have no hook target) ──────
CURRENT_ARM="13-hook-with-dest-path-refused"
sandbox
d13="$d"
"$ripwire" skills install --hook "$d13/dest" >"$d13/skills_install.err" 2>&1
rc=$?
[ "$rc" -ne 0 ] || fail "--hook with an explicit DEST_PATH exited 0 instead of being refused"
grep -qi "hook" "$d13/skills_install.err" || fail "refusal did not mention --hook"
[ -e "$d13/dest" ] && fail "explicit DEST_PATH was installed to despite the --hook refusal"
rm -rf "$d13"

# ── arm 14: end-to-end — a real install followed by a real --doctor must not read stale ────────
# Closes the gap that let writeManifestV2 write the BINARY'S PATH into source= while skillsCheck
# compares it against kStoreKey (a version-hash string): every fresh install then read as stale,
# forever. doctorstalecheck.sh's arm c never caught this because it hand-writes source=<kStoreKey>
# directly rather than going through a real install. This arm goes through the real path: real
# `skills install`, then a real `--doctor --agent=claude` against the same sandboxed HOME.
CURRENT_ARM="14-fresh-install-not-stale"
sandbox
d14="$d"
"$ripwire" skills install >/dev/null
doctor_out="$( "$ripwire" "$ROOT" --doctor --agent=claude 2>&1 )"
echo "$doctor_out" | grep -q 'n="claude-skills"[^>]*stale="1"' && fail "a fresh real install was reported stale=\"1\" by a real --doctor run"
# positive assertion too — a missing/renamed row or a silently-failed install would otherwise pass
# the negative check above vacuously, the same blind spot that let the underlying bug through.
echo "$doctor_out" | grep -q 'n="claude-skills" ok="1"' \
    || fail "fresh real install did not produce an ok=\"1\" claude-skills row: $doctor_out"
rm -rf "$d14"

# ── arm 15: C1 — a DANGLING symlink (a v1-upgrade checkout link whose target is gone) is repaired
# by a BARE install, no --force needed. This is the exact redhat-et/ripwire#225 review-round-1 C1
# repro: symlink_status() on a dangling link reports type()==symlink, not not_found, so the old code's
# `exists( destStatus )` read it as "already there" and skipped it forever.
CURRENT_ARM="15-dangling-symlink-repaired"
sandbox
d15="$d"
"$ripwire" skills install >/dev/null
deadTarget="$d15/dead-checkout-does-not-exist/ripwire-orient"
rm -f "$CLAUDE_CONFIG_DIR/skills/ripwire-orient"
ln -s "$deadTarget" "$CLAUDE_CONFIG_DIR/skills/ripwire-orient"   # dangling: nothing at $deadTarget
"$ripwire" skills install >/dev/null || fail "a bare re-run with a dangling entry present exited non-zero"
newTarget="$( readlink "$CLAUDE_CONFIG_DIR/skills/ripwire-orient" )"
[ "$newTarget" != "$deadTarget" ] || fail "the dangling v1-style symlink was left pointing at the dead checkout"
[ -f "$CLAUDE_CONFIG_DIR/skills/ripwire-orient/SKILL.md" ] || fail "ripwire-orient does not resolve to a readable SKILL.md after repair"
rm -rf "$d15"

# ── arm 16: C1 — --force also repairs a FOREIGN but LIVE symlink (an old, still-existing checkout),
# which the pre-fix --force could not: it only ever relinked an entry already pointing at THIS store.
CURRENT_ARM="16-force-repairs-foreign-live-symlink"
sandbox
d16="$d"
"$ripwire" skills install >/dev/null
oldCheckout="$( mktemp -d )/ripwire-orient"; mkdir -p "$oldCheckout"
rm -f "$CLAUDE_CONFIG_DIR/skills/ripwire-orient"
ln -s "$oldCheckout" "$CLAUDE_CONFIG_DIR/skills/ripwire-orient"   # live, but not our store
"$ripwire" skills install >/dev/null   # bare: must NOT touch it (arm 3's contract)
[ "$( readlink "$CLAUDE_CONFIG_DIR/skills/ripwire-orient" )" = "$oldCheckout" ] \
    || fail "a bare re-run touched a foreign-but-live symlink without --force"
"$ripwire" skills install --force >/dev/null || fail "--force on a foreign-but-live entry exited non-zero"
[ "$( readlink "$CLAUDE_CONFIG_DIR/skills/ripwire-orient" )" != "$oldCheckout" ] \
    || fail "--force did not repair a symlink pointing at a foreign but still-live checkout"
rm -rf "$d16" "$( dirname "$oldCheckout" )"

# ── arm 17: C2 — the manifest records OUTCOME, not intent: a permission-denied destination fails
# loudly (non-zero exit, a message per failed entry) and the manifest lists only what actually linked.
CURRENT_ARM="17-manifest-outcome-not-intent"
sandbox
d17="$d"
"$ripwire" skills install >/dev/null
before_linked="$( grep -c '^skill=' "$CLAUDE_CONFIG_DIR/skills/.ripwire-manifest-v2" )"
[ "$before_linked" -gt 0 ] || fail "nothing linked on the setup run — arm measures nothing"
victim="$( grep '^skill=' "$CLAUDE_CONFIG_DIR/skills/.ripwire-manifest-v2" | head -1 | sed 's/^skill=//' )"
rm -f "$CLAUDE_CONFIG_DIR/skills/$victim"
chmod 0555 "$CLAUDE_CONFIG_DIR/skills"   # dir still traversable/listable, not writable: symlink() there fails EACCES
"$ripwire" skills install >"$d17/skills_install.err" 2>&1
rc=$?
chmod 0755 "$CLAUDE_CONFIG_DIR/skills"   # restore before any further access (incl. cleanup)
[ "$rc" -ne 0 ] || fail "a run that failed to link an entry exited 0"
[ -s "$d17/skills_install.err" ] || fail "a link-loop failure produced no message at all"
after_linked="$( grep -c '^skill=' "$CLAUDE_CONFIG_DIR/skills/.ripwire-manifest-v2" )"
after_live="$( find "$CLAUDE_CONFIG_DIR/skills" -maxdepth 1 -name 'ripwire-*' -type l | wc -l | tr -d ' ' )"
[ "$after_linked" -eq "$after_live" ] \
    || fail "manifest skill= count ($after_linked) does not equal the actually-linked entries on disk ($after_live) — manifest still records intent, not outcome"
rm -rf "$d17"

# ── arm 18: M2 — an unknown/typo'd --flag is refused by name, not silently treated as an agent ────
CURRENT_ARM="18-unknown-flag-refused"
sandbox
d18="$d"
"$ripwire" skills install --forc >"$d18/skills_install.err" 2>&1
rc=$?
[ "$rc" -ne 0 ] || fail "an unknown --flag exited 0 instead of being refused"
grep -qi "unknown flag" "$d18/skills_install.err" || fail "the refusal did not name the flag as unknown"
[ -e "$CLAUDE_CONFIG_DIR/skills" ] && fail "an unknown --flag installed anyway before refusing"
rm -rf "$d18"

echo "OK: skillsinstallcheck (arms 1-18)"
