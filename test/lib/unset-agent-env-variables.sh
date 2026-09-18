# unset-agent-env-variables.sh — the ONE list of agent-home-relocating env vars every install/hook
# gate must clear before it varies HOME= per invocation. SOURCED, not run; lives under test/lib/ so
# pargates.py's gate sweep does not treat it as a gate of its own (see test/lib/gatehttp.sh's header).
#
# WHY. `src/skillsinstall.h` and `src/wrap.h` resolve each agent's config location through an env var
# that is checked AHEAD of HOME (CLAUDE_CONFIG_DIR for Claude, CODEX_HOME/AGENTS_HOME for Codex,
# HERMES_HOME for Hermes; RIPWIRE_DATA_HOME for the shared skills store in dataHome()). openclaw
# honours no such env var — it always resolves a literal ~/.agents/skills, so nothing here applies
# to it. A gate that overrides only HOME= per invocation is not sandboxed in any dev shell where one
# of these is already exported ambiently — an ordinary state once this repo's own hook/skills wiring
# is set up. Reproduced live, twice, against the operator's real ~/.claude-work/settings.json: once
# via `test/routehookcheck.sh` (missed by the CLAUDE_CONFIG_DIR fix in d038282c, which touched four
# other gates), once via `test/codexinstallhonestycheck.sh` (whose own header claimed "fully
# hermetic" without ever unsetting CLAUDE_CONFIG_DIR). Both incidents were a per-file omission of the
# same list, not a wrong list — the fix is one list, sourced everywhere, not a fifth hand-copied
# `unset` line.
#
# ORDERING IS LOAD-BEARING: source this FIRST, then set whatever homes the gate actually needs.
# Sourcing it after your own export unsets what you just set (test/hermesinstallcheck.sh regressed
# on this once — see C3 in fix-wave-2-report.md).
#
# Any agent added to `kAgentTargets` (src/wrap.h) that resolves its own home through a NEW env var
# needs that var added here in the same commit.
unset CODEX_HOME AGENTS_HOME HERMES_HOME CLAUDE_CONFIG_DIR RIPWIRE_DATA_HOME
