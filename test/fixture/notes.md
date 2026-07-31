# Geometry Fixture

A tiny polyglot corpus for ctxpack regression tests — kept small and stable so the golden snapshot
only moves when ctxpack's output genuinely changes.

## Symbols

`distance` and `perimeter` live in the C++ files; `area_of_triangle` and `total_area` in Python.

## Why it exists

The det-gate and cache-transparency checks compare ctxpack against itself, so they work on any corpus.
The golden snapshot needs a STABLE corpus — that's this directory. Each `.md` file also gets a file-level
node (named by its stem), and `[[wikilink]]` references become file→file edges — see [[related]].
