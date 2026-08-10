---
name: ripwire-security-scan
description: >
  Security review — two different moments, one skill. (1) Vet an untrusted agent config BEFORE you install
  or activate it: a SKILL.md file (or a whole skills/ directory) → ripwire's built-in injection/exfiltration/
  path-traversal scanner, whose findings carry a severity and whose CRITICAL verdict blocks the install;
  an .mcp.json server config → ripwire retrieval plus a manual semantic checklist of its shell stanzas.
  (2) Reviewing security-sensitive CODE or an untrusted-input path (parsing, deserialization, auth,
  exec/eval, network-facing handlers) → assemble STRUCTURAL signal: unsafe-C-fn / c-style-cast lint hits,
  forward taint-reach via transitive callees, untested integration seams, sink use-sites. Use when you receive a
  skill or MCP config from an external source, as a periodic check on already-installed ones, or when you're
  about to review/write code that touches untrusted input. One scan pass over the artifact in question is
  the verdict — a clean result doesn't need a second sweep with more verbs. Backed by ripwire
  (deterministic, on PATH).
allowed-tools: Bash, Read
---

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
ripwire <dir> --grep='"command"' --grep-context=6
ls <dir>/.mcp.json ~/.claude/mcp.json ~/.cursor/mcp.json 2>/dev/null
find <dir> -maxdepth 3 \( -name ".mcp.json" -o -name "mcp*.json" \) 2>/dev/null
```
Read each file, then scan every `"command"` / `"args"` / `"env"` stanza.

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

## Security-sensitive CODE — the structural pass

**Be honest about what this is**: ripwire has no dataflow/taint engine — it does not trace whether a value
*actually* flows from an untrusted source to a dangerous sink through variable assignments and returns.
What it gives you is **structural signal**: risky-construct hits, call-graph reachability, and untested
seams — a map of where to spend your reading time, not a proof of exploitability. Cede real taint tracking
to the compiler/a real static analyzer (clang static analyzer, CodeQL, Semgrep with dataflow) when the
finding matters enough to need one; use this to decide fast where to point that tool, or when none is
available.

1. **Unsafe constructs** — `ripwire <dir> --lint`
   Output: `<lint findings="N">` with a per-rule count block, then one `<f rule=... p=file:line in=enclosing>`
   per hit. The security-relevant rules: `unsafe-c-fn` (banned/dangerous libc calls — `strcpy`/`gets`/`system`
   class), `c-style-cast` (masks a `reinterpret_cast` as an implicit conversion — hides type-safety holes),
   `weak-crypto` (MD5/SHA1/DES-class primitives). A nonzero count on any of these in a file that touches
   untrusted input is the starting read list, ranked by rule severity not just count.

2. **Taint-reach (structural, not real taint)** — `ripwire <dir> --graph-query='callees(name("SYM"),6)'`
   where SYM is the parse/deserialize/handler entry point that receives untrusted input (the number bounds
   the hop depth; `--callees=SYM` is the 1-hop version for a quick first look).
   Output: `<query expr=... count="N">` — everything transitively reachable FROM that entry point via the
   call graph, ranked by importance and capped at `--top-k` (default 200 — raise it when you need the full
   set). Read this as "the set of code a malicious input could influence if it flows unchecked," not as
   "these N functions are vulnerable" — the call graph doesn't know which arguments actually carry the
   tainted value.
   **Direction check — do NOT use `--impact` here.** `--impact=SYM` is the OPPOSITE arrow: everything that
   REACHES SYM (transitive callers), i.e. the blast radius of *changing* SYM. Reach for it when you're about
   to modify the handler and need to know who depends on it — for forward taint-reach it's a false negative
   (on an entry point like `main` it returns an empty set).

3. **Untested integration seams** — `ripwire <dir> --seams`
   Output: `<seams>` — cross-module call edges no test file reaches. A parser/deserializer/auth boundary
   that shows up as an untested seam is doubly worth attention: it's both attack-surface-adjacent and has
   no regression net if you (or an attacker-triggered path) breaks it.

4. **Find the sinks and their call sites** — `ripwire <dir> --grep=STR` (literal, e.g. `system(`, `eval`,
   `exec`, `pickle.loads`, `deserialize`) for a quick census, or `ripwire <dir> --uses=SYM` (e.g.
   `--uses=deserialize`) once you know the exact symbol name — gives the statically-resolvable call/read/write sites by role (a floor: dynamic dispatch/callbacks/macros are unmodelled — counts_floor=) and
   file:line, and flags `external="1"` when the sink is a stdlib/third-party name with no in-corpus
   definition (the common case for `system`/`eval`-class calls). Treat the site list as a floor, not
   proof of absence — and remember ripwire cannot show you the sink's own body.

**Chain**: `--grep`/`--uses` to find the sink call sites → `--graph-query='callees(name("ENTRY"),6)'` on
the untrusted-input entry point to see what's structurally downstream of it → `--lint` to flag unsafe
constructs inside that reachable set → `--seams` to flag which of those paths have no test coverage. That
ordering is the structural triage; the actual taint judgment (does the value truly reach the sink
unsanitized) still needs a human or a real dataflow tool reading the code ripwire pointed at.

## Output

**Config scan** — per file / per server entry: **CLEAN** / **WARN** / **CRITICAL**, with the specific
finding (rule + line + text for a skill; the offending stanza for an MCP entry). Do not install/activate a
CRITICAL. For WARN, quote the suspicious text and ask the user to confirm intent before proceeding.

**Code scan** — a ranked list of concerns: sink call sites (from `--grep`/`--uses`), the entry point's
forward reach (from the `callees(...)` graph-query), any unsafe-construct hits inside that reach (from
`--lint`), and any untested seam among them (from `--seams`). Label the whole thing "structural triage,
not a taint proof" — don't let the output read as a clean bill of health; it's a prioritized reading list.
