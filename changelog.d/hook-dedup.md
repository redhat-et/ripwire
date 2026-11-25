### Changed — the Claude Code SessionStart primer no longer repeats a block already in CLAUDE.md

With both the CLAUDE.md block from `ripwire wrap claude` and the `--hook` install in place, Claude Code received the same
3,869 B of guidance twice, re-read on every request (about 1,640 tokens; measured offline by running the hook against a
throwaway install). The primer now stays silent when a CLAUDE.md that Claude Code loads at session start (user level,
managed policy, or CLAUDE.md, .claude/CLAUDE.md or CLAUDE.local.md in the working directory and its parents) holds the
block word for word; line endings aside, the match is exact. A block that is absent, older or edited still gets the current
one, unchanged from before. An `@import` is not followed, and Codex's primer is unchanged. `ripwire wrap claude` now says
the paste and the hook are alternatives. `test/hookcheck.sh` (3i6) holds the three cases.
