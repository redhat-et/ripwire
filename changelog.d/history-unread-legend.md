### Fixed — a cut git history walk no longer breaks the `--for` file page, and its `history_unread="1"` is defined where it rides

When the git history walk behind `churn=` and `amp=` is cut by its budget (20 s or 200 K commits) or fails, the answer
carries `history_unread="1"` on its root and a comment that explains it. Three things were wrong with that path, and all
three showed only when the walk was actually cut, which on this repository happens only on a slow runner (a CI flake on
#688):

- `--for … --limit=N` (the file page) printed an ill-formed document: its own `coverage=`, `shown=`, `total=` and `next=`
  attributes and its legend landed inside the explaining comment, so no reader or XML parser saw them. The page now keeps
  its attributes on its `<files>` root and puts the comment after the tag.
- The comment opened as `<!--history_unread=1: …`. It now opens `<!-- history_unread=1: …`, the spelling every other
  definition comment uses, so the legend checks read it as the attribute's definition.
- On the ranked map (`--metrics`, `--grep --metrics`), the comment now leads the legend in front of the `<r>` root, rather
  than following the root tag where the full-legend first screen does not look.

A run whose walk is read in full is byte-identical. The MCP `for` tool runs no history walk (it already declares
`churn` and `amp` absent with `lens=`), so it still carries no `history_unread`. `RIPWIRE_GIT_WALK_COMMITS=1` forces the
cut in `test/legendcoveragecheck.sh` (arm HU) and `test/mcpattrparitycheck.sh`, so both check this path on every run.
