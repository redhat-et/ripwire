### Fixed — Python file edges: stdlib-named siblings, src layouts, and directories the crawl denylist removes (#478)

Reported by @jflowers, who built an `ast` ground truth of pip's whole import graph and named the causes.

Inside a package, an absolute `import logging` no longer binds a sibling `logging.py`, in the file graph or the call graph; Python 3 has no implicit relative import. A plain script directory keeps its sibling, because it is `sys.path[0]` when the script runs. An absolute import now also resolves under a `src` directory beside the importer or any ancestor, and under the source root of the importer's own package chain (`lib/mypkg/a.py` importing `mypkg.b`). Two roots that name one module degrade to no edge, as before. A file outside those shapes importing a package under a root that is not `src` stays unresolved. Over `ast` truth, exact directories Ca/Ce: textual 86/3 to 98/98, flake8 62/25 to 100/100, pydantic 97/97 to 100/100 with 52 false edges gone.

`--skipped` now rows every directory counted in `pruned_dirs=`: `why="pruned-package"` when a build-output name (`build`, `dist`, `out`, `target`, `captures`) holds its own `__init__.py`, else `why="pruned-dir"`. `--arch` and `--deps` carry `<pruned_packages>` naming the real packages, present only when one was pruned, up to 8 with `count=` and `next="--skipped"` for the rest.
