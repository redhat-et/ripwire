### Fixed — `--path` tries every definition a refused endpoint spelling fits

`--path=ApplicationRef.tick,refreshView` on angular answered `found="0" refused="3"`: three definitions fit the spelling and none
was chosen, while the file-qualified spelling prints an 8-hop chain. Such an endpoint now stands for each fitted definition, and the
existing reaching-pair listing prints one chain, or every pair when two or more reach; the root says `from_fit=N` / `to_fit=N`.
When no fitted pair reaches, the refusal is unchanged. MCP `path_between` and the `--for` path rung do the same.
