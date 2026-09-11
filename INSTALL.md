# Installing ripwire

ripwire is one self-contained binary for macOS and Linux (arm64 and x86-64). Install it, point it at a
repository, and optionally teach your coding agent when to reach for it.

## Quick install (prebuilt)

```bash
RIPWIRE_REPO=redhat-et/ripwire bash -c "$(curl -fsSL https://raw.githubusercontent.com/redhat-et/ripwire/main/scripts/install.sh)"
export PATH="$HOME/.local/bin:$PATH"   # add this to your shell's rc file if it is not already there
ripwire --version
```

The installer:

- downloads the latest [GitHub Release](https://github.com/redhat-et/ripwire/releases) for your OS and CPU
  and verifies its SHA-256;
- installs the binary to `~/.local/bin/ripwire`, with no sudo;
- stages the agent skills and hooks under `~/.local/share/ripwire/`;
- activates the skills for each agent it finds on the machine (Claude Code, Codex, and Hermes with
  [initial support](#skills)) and prints one line per agent;
- never registers hooks and never edits your shell profile.

Linux builds run on RHEL 8 and later; every release is smoke-tested on RHEL 9 before it publishes.

| Variable | Effect |
| --- | --- |
| `RIPWIRE_REPO` | Required: `redhat-et/ripwire`. |
| `RIPWIRE_VERSION` | Install a specific tag, e.g. `v0.5.0`. Default: the latest release. |
| `RIPWIRE_INSTALL_PREFIX` | Install under this prefix instead of `~/.local`; the binary goes in `<prefix>/bin`. |
| `RIPWIRE_INSTALL_YES=1` | Skip the confirmation prompt. |
| `RIPWIRE_NO_ACTIVATE=1` | Stage the skills without activating them. |

Then try it in a repository:

```bash
cd your-repo
ripwire . --for="<the change you are about to make, in words>"
```

## Build from source

You need CMake 3.24+ and a C++23 compiler (clang 16+, AppleClang 15+ or gcc 13+). Every dependency is
vendored, so the build works offline.

```bash
git clone https://github.com/redhat-et/ripwire.git
cd ripwire
cmake -S . -B build && cmake --build build -j
./build/ripwire --version
```

To put a source build on your `PATH`, run `./install.sh` from the checkout. It builds a Release binary tuned
for this machine's CPU in `build-install/` and installs it under `RIPWIRE_INSTALL_PREFIX`, or under
`brew --prefix` when Homebrew is present, or else under `~/.local`. Like the prebuilt installer, it stages
skills and hooks under `<prefix>/share/ripwire/` and activates the skills for Claude Code and Codex when it
finds them. `RIPWIRE_NO_ACTIVATE=1` stages only; `RIPWIRE_ACTIVATE_CODEX=1` also registers the Codex hooks.

## Connect your coding agent

### Skills

Skills tell an agent *when* to reach for which ripwire verb. The installers activate them for the agents they
detect. To activate them yourself, run the staged skills installer (replace `~/.local` with your prefix if
you changed it):

| Agent | Command | Links into |
| --- | --- | --- |
| Claude Code | `bash ~/.local/share/ripwire/skills/install.sh` | `${CLAUDE_CONFIG_DIR:-~/.claude}/skills` |
| Codex | `bash ~/.local/share/ripwire/skills/install.sh --codex` | `${AGENTS_HOME:-~/.agents}/skills` |
| Hermes (initial support) | `bash ~/.local/share/ripwire/skills/install.sh --hermes` | `${HERMES_HOME:-~/.hermes}/skills` |
| openclaw (initial support) | `bash ~/.local/share/ripwire/skills/install.sh --openclaw` | `~/.agents/skills` |
| Anything else | `bash ~/.local/share/ripwire/skills/install.sh <dir>` | `<dir>` |

Hermes and openclaw support is initial. CI checks what the installers write on disk, but neither has been
verified against a real Hermes or openclaw install yet. If you use one, the help-wanted issues
[#69 (Hermes)](https://github.com/redhat-et/ripwire/issues/69) and
[#68 (openclaw)](https://github.com/redhat-et/ripwire/issues/68) ask for exactly that check.

The skills are symlinks named `ripwire-*`. Re-running the installer is safe: it refreshes the links and
removes any that a newer release no longer ships. openclaw reads `~/.agents/skills` only while its state
directory is the default `~/.openclaw`. Add `--contributor` to also activate the skill for building ripwire
itself.

### Advisory hooks (optional)

`bash ~/.local/share/ripwire/skills/install.sh --hook` registers ripwire's advisory hooks for Claude Code in
its `settings.json`: a SessionStart primer that adds ripwire's when-to-use guidance, a UserPromptSubmit router
that suggests one ready-to-run command when it is confident, and a PreToolUse hook that suggests nothing and
only records, on your machine, which tool calls ripwire could have answered. Adding `--codex --hook` does the
same for Codex in `~/.codex/hooks.json`; open `/hooks` in Codex to review and trust them. The hooks never
block a tool call, they need `jq`, and they are registered only when you pass `--hook`.

### MCP server (optional)

The CLI is the cheaper interface; the MCP server is a second way in. `ripwire wrap <agent>` prints the exact
configuration for `claude`, `codex`, `cursor`, `gemini`, `windsurf`, `opencode`, `hermes` or `openclaw`, plus
a short block to paste into that agent's rules file. For Claude Code it is:

```bash
claude mcp add ripwire -- ripwire --mcp
```

## Check and upgrade

`ripwire . --doctor` checks the install: the binary, the skills and the hooks. To upgrade, run the same
install command again (pin a release with `RIPWIRE_VERSION`). It replaces the binary and the staged skills
and refreshes their links.

## Uninstall

Remove whichever parts you set up. Each step touches only what ripwire's installers, or your own setup
following this page, created.

**1. The binary and its staged files.** Use your prefix if you changed it; for a Homebrew source build that is
`$(brew --prefix)`.

```bash
rm -f ~/.local/bin/ripwire
rm -rf ~/.local/share/ripwire
```

**2. Skill links.** This deletes only symlinks named `ripwire-*`, never a real directory or another skill.

```bash
for d in "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/skills" "${AGENTS_HOME:-$HOME/.agents}/skills" \
         "$HOME/.agents/skills" "${CODEX_HOME:-$HOME/.codex}/skills" "${HERMES_HOME:-$HOME/.hermes}/skills"; do
  [ -d "$d" ] && find "$d" -maxdepth 1 -name 'ripwire-*' -type l -delete
done
```

**3. Hooks** (only if you ran `--hook`). This removes ripwire's entries from Claude Code's `settings.json` and
Codex's `hooks.json`, keeps every other hook, and saves a `.bak` copy of each file first.

```bash
strip='def ripwire: (.command // "") | split(" ")[0] | test("/hooks/ripwire-[a-z-]+\\.sh$");
  if .hooks then .hooks |= with_entries(.value |= (map(.hooks |= map(select(ripwire | not))) | map(select((.hooks | length) > 0)))) else . end'
for f in "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json" "${CODEX_HOME:-$HOME/.codex}/hooks.json"; do
  [ -f "$f" ] && cp "$f" "$f.bak" && jq "$strip" "$f.bak" > "$f.tmp" && mv "$f.tmp" "$f"
done
```

The hooks also keep local records in `~/.ripwire`, or in `$RIPWIRE_HOME` if you set it. The ripwire binary
itself never writes there. This removes only ripwire's own entries, then the directory if nothing else is in it:

```bash
h="${RIPWIRE_HOME:-$HOME/.ripwire}"
rm -rf "$h/substitution.jsonl" "$h/routing.jsonl" "$h/routing-pending" "$h/meter.conf"
rmdir "$h" 2>/dev/null || true
```

**4. The MCP server** (only if you added it).

- Claude Code: `claude mcp remove ripwire`.
- Codex: delete the `[mcp_servers.ripwire]` table from `~/.codex/config.toml`.
- Cursor, Gemini CLI, Windsurf: delete the `"ripwire"` entry under `mcpServers` in `.cursor/mcp.json` or
  `~/.cursor/mcp.json`, `~/.gemini/settings.json`, or `~/.codeium/windsurf/mcp_config.json`.
- opencode: delete `"ripwire"` under `"mcp"` in `opencode.json` or `~/.config/opencode/opencode.json`.
- Hermes, openclaw: remove the `ripwire` server you registered with their `mcp` command.

**5. Rules blocks.** If you pasted ripwire's block into `CLAUDE.md`, `AGENTS.md`, `GEMINI.md`, `.cursor/rules`,
`.windsurfrules` or `~/.openclaw/workspace/AGENTS.md`, delete that block.

**6. The cache.** ripwire keeps its index cache, and any repositories it cloned, in one private directory:
`$TMPDIR/ripwire`, else `$XDG_CACHE_HOME/ripwire`, else `/tmp/ripwire-<uid>`. Remove all three candidates:

```bash
[ -n "${TMPDIR:-}" ] && rm -rf "${TMPDIR%/}/ripwire"
[ -n "${XDG_CACHE_HOME:-}" ] && rm -rf "$XDG_CACHE_HOME/ripwire"
rm -rf "/tmp/ripwire-$(id -u)"
```

**7. Files in your repositories.** ripwire writes into a repository only when you ask it to. If you no longer
want them, delete `.ripwire_config`, `.ripwire_notes`, `.ripwire_quality_baseline`, `.ripwire_quality_acks`
and `.ripwire_arch_baseline`; check first whether they are committed.
