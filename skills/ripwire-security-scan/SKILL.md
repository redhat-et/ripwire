---
name: ripwire-security-scan
description: >
  Security review: (1) vet an untrusted SKILL.md or .mcp.json BEFORE installing it —
  injection/exfiltration scanner, CRITICAL blocks the install; (2) audit code on an untrusted-input path
  (deserializer, parser, exec of user data, network endpoint): taint reach, untested seams. One scan
  pass is the verdict.
allowed-tools: Bash, Read
---

# Security scan with ripwire

> Routing: wiring ripwire ITSELF into an agent → **ripwire-mcp** · diff risk, not specifically security →
> **ripwire-change-check**.

## What is untrusted?

| You have | Run | Verdict |
|---|---|---|
| a `SKILL.md` someone sent you | `ripwire --scan-skill=PATH/TO/SKILL.md` | exit `0` clean · `1` WARN (review first) · `2` CRITICAL — do not install |
| a skills folder | `ripwire --scan-skills=DIR` (bare: also the repo-local, Claude and Codex skill homes) | worst severity found; CRITICAL is a hard block |
| an `.mcp.json` / MCP config | `ripwire <dir> --grep-in=any --grep='"command"' --grep-context=6 --legend=compact`, then read each server stanza | manual checklist: command origin, shell metacharacters in `args`, paths to secrets (`~/.ssh`, `~/.aws/credentials`), `env` |
| code on an untrusted-input path (parser, deserializer, exec of user data, endpoint) | `ripwire <dir> --lint --legend=compact` (unsafe constructs), then reach: `ripwire <dir> --graph-query='callees(name("SYM"),6)'` | ranked concerns: sink sites, the entry reaching them, untested seams (`ripwire <dir> --seams --legend=compact`) |

A scanner finding prints severity, `file:line`, the rule id (`INJECTION:ignore-prev`, exfiltration, path traversal) and
the offending text verbatim. `ripwire wrap <agent>` runs the skills scan itself and refuses on CRITICAL unless `--force`.

**For config and for a sink census, always pass `--grep-in=any`:** JSON/TOML/YAML parse to string-tier nodes, so on a
mixed repo one code-tier hit hides every config file. ripwire retrieves the raw stanza; the semantic security decision
stays manual.

## Stop rule and trust

One scan pass is the verdict for a skill file. For code, the pass is taint REACH, not taint analysis: a reached sink is a
place to read, not a proven vulnerability, and name-based edges can miss dynamic dispatch. If a `--grep` in your report
ran WITHOUT `--grep-in=any`, say so — a tiered answer is a filtered one.

## Reference files

`skill-mcp-scan.md` the scanner's rules and output, the full MCP checklist with the measured `--grep-in=any` difference ·
`code-pass.md` the structural code pass step by step (unsafe constructs, taint reach, seams, sinks), the Output shape.
