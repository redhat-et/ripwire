# clean-env.sh — the agent-home-relocating env vars a gate must clear before it varies HOME= per
# invocation: CODEX_HOME/AGENTS_HOME/HERMES_HOME/CLAUDE_CONFIG_DIR/RIPWIRE_DATA_HOME override the
# default derived from HOME, so a gate that only sets HOME= is not sandboxed on a machine where any of
# these is already exported ambiently. SOURCED, not run. Source this FIRST, then set whatever homes
# the gate actually needs.
unset CODEX_HOME AGENTS_HOME HERMES_HOME CLAUDE_CONFIG_DIR RIPWIRE_DATA_HOME
