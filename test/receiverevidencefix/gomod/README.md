# gomod — Go module-alias proof (receiverevidencecheck.sh section (G2))

Each directory is its own tree (its own `go.mod`), indexed alone. A module-alias call `lib.Mark()` is proven onto a
candidate only when the import path EXACTLY names the candidate's package: the nearest go.mod's module path plus the
directory below it, or the path a local `replace L => ./D` gives a file under D. Never built.

- fork2: `replace github.com/up/lib => ./third/lib` beside an in-repo `lib/` (another package): only `third/lib` is proven.
- tail: `example.com/t/pkg/lib` — `pkg/lib` is the package; `lib/` merely ends the path.
- fork: `replace github.com/up/lib => ./lib`. rep / rep2: a replaced `legacy/` with and without its own go.mod.
- nest: a nested module `other/`. pfx: `example.com/a` vs `example.com/ab`. vend: a vendored copy. dot: a dot import.
- mixed: no go.mod at the root; the nested module `m/` carries `example.com/x/lib`, and the root's `lib/` (no import
  path at all) merely ends it — the directory-tail rule never applies to a path an in-tree module carries.
