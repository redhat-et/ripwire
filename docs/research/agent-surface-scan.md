# Scanning the agent surface — the files an agent loads or runs, not only skills

**Status: DESIGN, 2026-09-28. No number in this note was produced by running anything.** It follows the SkillSpector
work (the lineage row and the port plan for `--scan-skills`, and #353's net-exfil false positives) and asks one question:
which other files deserve the same checks, and how do we add them without adding noise? Read `docs/METHODOLOGY.md` §9 first.
Nothing here changes a default until a measurement below licenses it.

---

## 1. The boundary

**Scan the files an AI agent automatically loads into its context or runs without asking. Do not scan code in general.**

A skill is one such file, but it is not the only one. An instruction file loaded into every session, a settings hook that
runs a shell command, and an MCP config that picks which server the agent talks to all carry the same risks as a skill:
prompt injection, exfiltration, concealed text, and commands that run without a prompt. The same code-based checks
therefore apply almost unchanged.

General source-code security (injection sinks, unsafe deserialization in application code, and so on) is **out of scope**.
Semgrep, CodeQL and their peers do it well, and ripwire would be a weaker copy.

Within the boundary, the split is the one the SkillSpector plan set: **ripwire runs only deterministic code checks; the
agent's LLM reads the findings and makes the judgment.** A finding therefore carries judge-ready evidence as terse,
legend-defined attributes: the rule and category, the matched line, for a flow the source → sink lines and the resolved
destination (or `dest="unresolved"`), and why it fired.

## 2. What is on the agent surface

| # | File class | Examples | Why it matters | Checks that carry over |
|---|---|---|---|---|
| 1 | Agent instruction files | `CLAUDE.md`, `AGENTS.md`, `GEMINI.md`, `.cursorrules`, `.cursor/rules/*.mdc`, `.github/copilot-instructions.md`, `.windsurfrules`, aider's `CONVENTIONS.md` | Loaded into every agent session in the repository. A pull request that adds one line is a lasting prompt injection on everyone who works there. | All skill checks: injection phrases, exfiltration instructions, concealed and letter-spaced text, HTML-comment payloads |
| 2 | Settings that run commands without asking | `.claude/settings*.json` hooks and permission allow-lists; `.mcp.json`, `.cursor/mcp.json`; `.vscode/tasks.json` tasks that run on folder open; `devcontainer.json` `postCreateCommand` | Commands run, or traffic is rerouted, with no prompt. SkillSpector's newest analyzer fix flags exactly "settings keys that run commands or reroute traffic". | Command execution, network sinks and reroutes, MCP tool poisoning and rug-pull, least privilege |
| 3 | Invisible text in any file an agent reads | bidi control characters and zero-width characters ("Trojan Source", CVE-2021-42574); hidden HTML comments in docs | The agent reads text a human reviewer cannot see. | Concealed-text normalization (SkillSpector's whitespace-padding and letter-spacing checks) |
| 4 | Install-time execution | `package.json` lifecycle scripts (`postinstall`, …); `setup.py` and build hooks; registry redirection in `.npmrc` / `pip.conf`; `go.mod` `replace` to a URL | Installing a dependency runs code. | SkillSpector's supply-chain checks, including dependency-source redirection |
| 5 | CI workflows | `pull_request_target` combined with checking out the PR head; secrets reaching a network call; unpinned third-party actions; `curl … \| bash` | High impact, and a secret leak is permanent. | Taint from secret to network, pinning |

`src/wrap.h` already holds a table of each supported agent's instruction file. Class 1 reuses that table rather than
keeping a second list.

## 3. What ripwire adds that a skill scanner does not: diff-aware gating

SkillSpector scans a skill before you install it. ripwire runs inside the agent's work loop and already gates diffs with
`--quality-delta`. So the agent-surface checks can be **diff-aware**: a change that touches a file on the agent surface is
scanned, and a *new* critical finding in a changed file is a regression. That is "never make things worse" applied to
security. It also covers the case no install-time scanner sees: an agent being steered into editing its own `CLAUDE.md`,
hooks or MCP config, which is how a prompt injection persists.

Only new findings in changed files gate. Pre-existing findings are reported, never gating, which is the same rule
`--quality-delta` applies to every other kind.

## 4. Recommendations

1. **Do classes 1 and 3 first.** They reuse the `--scan-skills` rules almost unchanged, need little new code (class 1 is a
   file-class list that `src/wrap.h` already has), and are the least likely to be noisy. Class 3 is precise by nature: a
   bidi control in a Markdown instruction file has almost no innocent reading.
2. **Then class 2**, reusing the MCP and settings analyzers ported from SkillSpector anyway. Do it after the SkillSpector
   gap table exists, so no check is written twice.
3. **Hold classes 4 and 5** until after the SkillSpector gap table and a survey of the dedicated tools (for CI workflows,
   zizmor and actionlint). If an existing tool already does it well, the right outcome may be a lineage row and a
   routing hint, not new code.
4. **Name it for what it is.** A separate verb, for example `--scan-agent-surface`, rather than stretching `--scan-skills`
   over files that are not skills. The diff-aware form is one more `--quality-delta` kind, gated on changed files only.
5. **Precision before severity, everywhere.** Every check starts as WARN. It becomes CRITICAL only after measured
   precision ≥ 0.8 on ≥ 20 real samples *of that file class* (a rule that is precise on skills is not assumed precise on
   `package.json`). A noisy CRITICAL teaches people to ignore the scanner, and a CRITICAL can block `ripwire wrap`.
6. **Keep the honesty rules.** Coverage gaps are findings, not silences (SkillSpector reached the same principle: incomplete
   coverage is reported and fails closed). A zero means "none found". A file class the scanner did not read is named.
7. **Keep the implementation rules.** Linear-time matching only (`src/regexguard.h`), deterministic output, legend entries
   for every new attribute, a red-first gate per file class, and Apache-2.0 attribution on anything ported from SkillSpector.

## 5. Measurement, fixed before running anything

- **Precision per rule × file class:** sample ≥ 20 findings per rule and class from public repositories that contain the
  files in §2. Each is labelled real / not real by two raters, using the same protocol as the lint precision work. A rule
  below 0.8 stays WARN or is dropped.
- **A negative corpus:** ripwire's own tree and three unrelated real repositories. Every finding there is expected to be
  not real unless shown otherwise. A class that produces more than a handful of findings on clean repositories is not
  ready.
- **Diff-aware gate:** on a replay of real commits that touched agent-surface files, the gate must flag the planted
  positives and stay silent on the ordinary edits.

**What would prove this wrong:** class 1 or 3 fails the precision bar on real repositories (then the skill rules do not
carry over as assumed, and each class needs its own rules); or the diff-aware gate fires on ordinary edits to instruction
files (then it gates too early and should be report-only).

## 6. Out of scope

- General application-code security (§1).
- Any LLM call. The agent that reads the output is the judge.
- Network lookups at scan time (for example live vulnerability databases). Output must not depend on the network.
