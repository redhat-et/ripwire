# ripwire-router — reference: primer (read on demand; the recipe is in SKILL.md)

## The two-reflex primer — the moments the habit forgets

The always-loaded ripwire primer trains the READ verbs (`--for`/`--recall`/`--callers`/`--expand`/
`--hotspots`) but not the two WRITE-time reflexes, which is exactly where the most value leaks:

- **Before you write a fn/class — even a "quick" one:** `ripwire <dir> --exemplar="<the sub-task in words>" --legend=compact`
  → the repo's best-in-class instance of that shape to imitate (by ROLE, not text similarity), plus
  `--for="<task>"` to reuse before reinventing. Duplicates are born on tasks that felt too small to tool up
  for. (→ **ripwire-reuse-first**.)
- **Before you call it DONE:** `ripwire <dir> --quality-delta --legend=compact` → ONLY what your change made worse across 12
  kinds (complexity, verbosity, nesting, params, duplication, dead-code, api-surface, error-masking,
  short-horizon-churn, new-clone-of-reused-helper, placeholder, defect-shape); exit 2 = code that already existed got worse.
  In a git repo it **auto-compares vs `git HEAD`** (no start-of-task ritual — just run it before you push).
  **A finding is only half the job** — the fix is not done until it is proven: `--quality-delta` (targeted
  kind gone, nothing else regressed) → `--edit-check=SYM` (contract intact) → `--affected` (the tests that
  prove it). That chain, and the shape → refactor playbook that picks the fix in the first place, are in
  **ripwire-quality-bar**.
  For a mid-task convergence loop, run `ripwire <dir> --quality-baseline` at the start to pin an explicit
  floor (it takes precedence over HEAD), then re-run `--quality-delta` after each edit. (→ **ripwire-quality-bar**.)
  Want the wider "does this still look rotten" picture alongside the delta, not just what you changed? —
  `ripwire <dir> --quality-panel[=strict|default|lenient] --legend=compact`, the six-family panel (→ **ripwire-fresh-eyes**).
  **It is a lens, not a gate** — always exits 0; `--quality-delta` above is the only pass here that gates.

`ripwire --help` lists every flag on one line; `--help=--FLAG` prints one flag in full and `--help=all` the whole catalog. Every skill re-verifies its commands against the shipped binary.

**Installing these skills:** `bash skills/install.sh` symlinks every `ripwire-*` skill into the Claude
skill home (its codex mode targets `${AGENTS_HOME:-~/.agents}/skills`; `--codex-legacy` retains
`${CODEX_HOME:-~/.codex}/skills`) and prunes dangling links from removed skills. Add `--hook` explicitly
for the advisory nudge (`--codex --hook` for Codex).
