### Fixed — a default `--lint` answer fits an agent's screen, and its next page is one pasteable call

Claude Code's Bash tool shows a result inline up to about 30,000 characters; past that the agent gets a file path and a 2,000-character preview. A bare `--lint` budgeted its findings at 100,000 bytes, so on 9 of 11 GA1 DEV repositories (one tree each) it printed more than 30,000 characters (largest 83,162) and the answer never reached the agent.

The default page is now sized so the whole answer — legend, root, rule tally and findings — stays under 24,000 characters (the inline limit less 20 %, `src/outputceiling.h`). The cut is the one `--lint` already disclosed: `shown= total= capped="1" has_more="1" next_offset=K`, and the root now also carries `next="--lint --offset=K"` (with any `--lint-select` / `--lint-ignore` / `--lint-rules` / `--lint-max-per-rule` / `--naming-locals` / `--with-profile` you passed). `--offset=K` alone is now byte-budgeted the same way, so every page of the chain fits too; before, it printed every finding from K on. Following `next=` until `has_more="0"` yields every finding once, in order. An explicit `--limit=N` is unchanged and is still the way to ask for a bigger page.

Measured on GA1 DEV (11 repos, one tree each): largest default `--lint` answer 83,162 → 19,589 characters; answers over 30,000: 9 → 0. Gate: `test/outputceilingcheck.sh`.
