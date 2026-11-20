### Fixed — a multi-root workspace lists its files in path order

A workspace sorted its roots by the bare label, so roots `a` and `a-b` merged as `a/…` then `a-b/…`, while one root over their parent lists `a-b/…` first (`-` sorts below `/`). The roots now sort by `<label>/`, so the merged files, and every file or node id tie-break that reads them, follow the path order a single root gives. Argv order still never matters. Only workspaces with such a label pair change. New arm `G-label-order` in `test/multirootcheck.sh`.
