### Fixed — `--affected` answers for the files it can use when a list also names one it cannot

`--affected=F1,F2,…` refused the whole call (exit 1, nothing on stdout) as soon as one item matched no indexed path and no indexed symbol. The usual way to build that list is `git diff --name-only | paste -sd, -`, and a diff routinely names a file the index does not hold — a deleted file, a `ChangeLog`, a generated, vendored or excluded file — so an agent that changed three source files and a changelog got no tests to run at all.

The call now answers for every item that resolves and names each one it could not use, on the answer itself:

```xml
<affected … tests="2" reached="2" unused="2" …>…<unused item="ChangeLog" reason="not_indexed"/><unused item="src/old.cpp" reason="not_found"/></affected>
```

- `reason="not_indexed"`: a file by that path exists under the root, but the index does not hold it (non-source, excluded, ignored, vendored or oversize; `--skipped` says which), so there is nothing in the graph to reach from it.
- `reason="not_found"`: no indexed path, no indexed symbol and no file match it — a deleted or renamed file, or a typo. The two cannot be told apart without history, so `near=` names the closest indexed path when there is one and the reader decides.

`tests=`, `reached=` and `seeds=` answer for the usable items only, and the test rows are byte-identical to the answer for those items alone. Exit status is 0 when at least one item resolved. A list with **no** usable item is still a refusal (exit 1), never a `tests="0"` answer, and a list of more than one item now says that none of them resolved; a one-item refusal is unchanged. A list with nothing unusable is byte-identical to before. The MCP `affected` verb carries the same disclosure (one renderer). `--situ=` and `--test-gate=` share the old refusal shape and are unchanged in this fix. Gate: `test/affectedpathcheck.sh`.
