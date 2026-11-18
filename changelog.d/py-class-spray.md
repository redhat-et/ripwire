### Fixed — a bare Python call binds the definition its own scope chain binds, not every namesake

A bare call `Model(...)` whose name the call's own scope, an enclosing function, or the module binds by
`def`/`class` statements alone now resolves to those definitions only, as Python's name lookup (LEGB) does.
Before, such a call took the name-only ladder and was split across every same-named definition in its
directory: on pydantic one `Model(b=1)` in a test reached all 965 `class Model` definitions of `tests/`
(517,311 edges from 643 callers). Measured with the pin census, cold, `--no-cache`: pydantic call edges
892,662 → 64,166 (the map's `edges=` 582,130 → 48,178), textual 34,013 → 28,252, django 107,887 → 100,627;
every call site keeps its disposition, and a changed site only loses targets, except where the local
definition had been dropped (pydantic's `test_args`: `foo(1, 2)` now binds the test's own `foo`). Peak
memory falls with the edges (pydantic 153–171 MB → 122–128 MB).

Two or more `def`/`class` statements of the name in that scope (an `if`/`else` pair, a redefinition) are a
split across those only. The rule makes no decision, and the call keeps the earlier answer, when another
binding shares the scope (an assignment, a parameter, an import, a `for`/`with`/`except` target), when a
`global`/`nonlocal` names it, when a lambda parameter or comprehension target of the name holds the call,
when the innermost scope is a class body that binds it, and at module scope under a star import, a
`globals()`/`setattr` write or a conditional def of a builtin's name. A default argument, annotation,
decorator or base clause runs in the enclosing scope. Python only; `--for` answers on Python trees can change.
Gate: `test/pyaliascallcheck.sh` section 5.
