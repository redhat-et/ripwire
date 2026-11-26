### Changed — the Claude Code SessionStart primer no longer repeats a block already in CLAUDE.md

With both the CLAUDE.md block from `ripwire wrap claude` and the `--hook` install in place, Claude Code received the same
3,869 B of guidance twice, re-read on every request (about 1,640 tokens; measured offline by running the hook against a
throwaway install). The primer now stays silent when a CLAUDE.md that Claude Code loads at session start (user level,
managed policy, or CLAUDE.md, .claude/CLAUDE.md or CLAUDE.local.md in the working directory and its parents) holds the
block word for word. The match is exact; line endings are ignored, and HTML comments are removed first, as Claude Code
removes them. A block that is absent, older or edited still gets the current one, unchanged from before. So does a block
behind an `@import`, which is not followed, and any session whose user, managed or project settings name `claudeMdExcludes`
or set an instruction mode (`instructionFiles`) other than the default, since `managed-only` skips the project, local and
user CLAUDE.md files. A CLAUDE.md over 4 MiB, which Claude Code skips, does not count either.
Codex's primer is unchanged. `ripwire wrap claude` now says pasting the block is the reliable path, since the hook sends
it only in sessions where the primer is on (not the control arm). `test/hookcheck.sh` (3i6) holds each case.
