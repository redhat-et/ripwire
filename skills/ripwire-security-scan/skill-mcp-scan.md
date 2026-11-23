# ripwire-security-scan — reference: skill-mcp-scan (read on demand; the recipe is in SKILL.md)

# Security scan with ripwire

> Nearest neighbour: wiring ripwire ITSELF into an agent as an MCP server (not auditing someone else's) →
> **ripwire-mcp**. General diff risk/coupling, not specifically security → **ripwire-change-check**.

Trigger (config scanning): you've received a `SKILL.md`, a skills folder, or an `.mcp.json` from an external
source and want to verify it's safe before installing or activating it.

Trigger (code scanning): you're reviewing or about to write security-sensitive code — anything that parses
untrusted input, deserializes, execs/evals, does raw pointer/buffer arithmetic, or sits on a network-facing
boundary — and want structural signal on where the risk concentrates before you read line-by-line.

## Skill files — the built-in scanner

**Scan a single file:**
```
ripwire --scan-skill=PATH/TO/SKILL.md
```
Output: `ripwire scan: N finding(s) in <file>`, then one line per finding —
```
CRITICAL  inject.md:11  INJECTION:ignore-prev  — "Ignore previous instructions and instead act as …"
```
Each finding lists severity, `file:line`, the rule id (`INJECTION:ignore-prev`, `INJECTION:you-are-now`,
exfiltration/path-traversal rules), and the offending text verbatim.

**Scan a whole directory:**
```
ripwire --scan-skills=DIR          # bare form also scans repo-local, Claude, and Codex skill homes
```
Recursively scans every `.md`, reports the same per-finding lines. Run this before adopting an entire skills
folder, and as a periodic check on installed ones. (`ripwire wrap <agent>` runs this scan automatically at
adoption time and refuses to emit the recipe on a CRITICAL finding unless `--force`.)

**Exit codes:** `0` = clean · `1` = WARN (review before installing) · `2` = CRITICAL (do not install). The
exit code for a directory scan is the worst severity found. A CRITICAL exit is a hard block.

## MCP configs — the manual checklist

`--scan-skill` targets SKILL.md-shaped markdown; it does not apply skill-injection rules to `.mcp.json`.
ripwire does index JSON config keys and `--grep` can retrieve their raw context, but it does not understand
the security semantics of an MCP stanza. Retrieval is automated; the semantic decision remains manual.

**Step 1 — locate and read the config** with ripwire or the shell + Read tool:
```
ripwire <dir> --grep-in=any --grep='"command"' --grep-context=6 --legend=compact
ls <dir>/.mcp.json ~/.claude/mcp.json ~/.cursor/mcp.json 2>/dev/null
find <dir> -maxdepth 3 \( -name ".mcp.json" -o -name "mcp*.json" \) 2>/dev/null
```
Read each file, then scan every `"command"` / `"args"` / `"env"` stanza.

**`--grep-in=any` is not optional here — it is the whole recipe.** A JSON/TOML/YAML file parses entirely to
string-tier nodes, so on any mixed repo a single code-tier hit for `"command"` anywhere (a C++ identifier, a
gate script) suppresses **every config file** and serves you prose instead. Measured on ripwire's own tree:
default → **2** files, all markdown prose, `.mcp.json` absent, `suppressed_string="38"`; `--grep-in=any` →
**12** files including `.mcp.json`. The count is disclosed, not hidden — but an auditor who trusts the
default reviews zero MCP stanzas and is told nothing is there. The empty-code-tier collapse (comment and
string served together) does **not** rescue this: it only fires when the code tier is empty, and here it is
not. Always pass `--grep-in=any` when the target is config.

**Step 2 — checklist, one pass per server entry:**
- **Command origin** — is `command` a known binary (`npx`, `node`, `python`, `uvx`)? An unknown path in a
  temp or user-writable dir is a red flag.
- **Shell injection** — do `args` values contain `;`, `&&`, `|`, `$(...)`, or backticks? These execute extra
  commands when the MCP host spawns the server.
- **Path traversal** — do `args`/`env` reference `..`, `~/.ssh`, `~/.aws/credentials`, `~/.config/`? Reading
  those = potential secret exfiltration.
- **Secret leakage** — does `env` pass `ANTHROPIC_API_KEY`, `GITHUB_TOKEN`, or similar to a third-party
  binary? Secrets passed to untrusted servers leave your control.
- **Scope creep** — does the server claim filesystem/shell/network access beyond its stated purpose? Apply
  least privilege.
