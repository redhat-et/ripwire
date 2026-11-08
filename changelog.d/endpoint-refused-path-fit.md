- `--path` (and MCP `path_between`, and the `--for` path rung) no longer stops at an endpoint whose spelling several definitions fit
  with none chosen (`--path=ApplicationRef.tick,refreshView` on angular answered `found="0" refused="3"`). Each fitted definition is
  tried through the existing reaching-pair listing: one reaching pair prints its chain, two or more print every pair, and the root
  says so with `from_fit=N` / `to_fit=N`. When no fitted pair reaches, the refusal is unchanged (gate `test/endpointfitcheck.sh`).
