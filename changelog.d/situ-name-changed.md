### Changed — `--situ` names what you changed before what depends on it

The default `--situ` (the git-diff form) now opens with a `changed:` block: one row per edited function,
`path:first-last name`, followed by up to 3 direct-caller files outside the diff after `←` (`+K (--callers=NAME)`
when there are more). A file whose edit could not be located in a function (module-level edit, deletion) is one
`(whole file: N symbols)` row. Past 8 rows the block ends `+N more: --situ --limit=M`. A `last commit:` line
names HEAD's sha, subject and files, because an edit that is already committed is outside a diff vs HEAD;
`--pr-context=HEAD~1` covers both. A parentless HEAD (a root commit, a shallow clone's boundary) prints no such
line. An explicit `--situ=FILES` list prints neither block, since it already names its files.
Before this, the report gave only a count (`2 changed file(s)`, `changed_symbols=2`). On the VERB-AUDIT-2 cells
the changed files were named on 0 of 4 repos (jq, vscode, zed, cockroach), so the agent's next calls were
`git diff --stat` and a grep. The MCP `situ` tool is unchanged: it already lists `changed_files`.
