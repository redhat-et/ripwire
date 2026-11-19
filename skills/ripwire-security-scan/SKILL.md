---
name: ripwire-security-scan
description: >
  Security review: (1) vet an untrusted SKILL.md or .mcp.json BEFORE installing it — the
  injection/exfiltration scanner; CRITICAL blocks the install; (2) audit code on an untrusted-input
  path (a deserializer, parser, exec of user data, network endpoint): taint reach, untested seams. One
  scan pass is the verdict.
allowed-tools: Bash, Read
---

# Security scan with ripwire

> Routing: wiring ripwire ITSELF into an agent as an MCP server (not auditing someone else's) → **ripwire-mcp** ·
> general diff risk, not specifically security → **ripwire-change-check** · unsure → **ripwire-router**.

## The decision: what is untrusted?

| You have | Run | Verdict |
|---|---|---|
| a `SKILL.md` someone sent you | `ripwire --scan-skill=PATH/TO/SKILL.md` | exit `0` clean · `1` WARN (review before installing) · `2` CRITICAL — do not install |
| a whole skills folder | `ripwire --scan-skills=DIR` (bare form also scans the repo-local, Claude and Codex skill homes) | worst severity found; CRITICAL is a hard block |
| an `.mcp.json` / MCP config | `ripwire <dir> --grep-in=any --grep='"command"' --grep-context=6 --legend=compact`, then read each server stanza | the manual checklist: command origin, shell metacharacters in `args`, paths to secrets (`~/.ssh`, `~/.aws/credentials`), `env` |
| code on an untrusted-input path (parser, deserializer, exec of user data, network endpoint) | `ripwire <dir> --lint --legend=compact` (unsafe constructs), then the entry's reach: `ripwire <dir> --graph-query='callees(name("SYM"),6)' --legend=compact` | a ranked list of concerns: sink sites, the entry that reaches them, untested seams (`ripwire <dir> --seams --legend=compact`) |

Each scanner finding prints severity, `file:line`, the rule id (`INJECTION:ignore-prev`, exfiltration, path
traversal) and the offending text verbatim. `ripwire wrap <agent>` runs the skills scan itself before it prints a
recipe and refuses on a CRITICAL unless `--force`.

**For config and for a sink census, always pass `--grep-in=any`.** A JSON/TOML/YAML file parses entirely to
string-tier nodes, so on a mixed repo one code-tier hit suppresses every config file and serves prose instead.
ripwire indexes JSON config keys and retrieves their raw context, but it does not understand the security
semantics of an MCP stanza: retrieval is automated, the semantic decision remains manual.

## Stop rule and trust

One scan pass is the verdict for a skill file. For code, the structural pass is taint REACH, not real taint
analysis: a reached sink is a place to read, not a proven vulnerability, and name-based edges can miss dynamic
dispatch. If any `--grep` in your report ran WITHOUT `--grep-in=any`, say so — a tiered answer is a filtered one.

## Reference files

`skill-mcp-scan.md` — the scanner's rules and output, the full MCP checklist with the measured `--grep-in=any`
difference · `code-pass.md` — the structural code pass step by step (unsafe constructs, taint reach, seams, sinks,
the chain) and the Output shape.
