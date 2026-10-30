### Added — `--for` names where a base class reaches a served Python override through `self`

A served Python method whose name has two or more definitions in its inheritance cone now carries a `<selfhooks>` element: the override
relation (`overrides=` / `op=` when the inheritance edges prove which base definition wins, `candidates=` when two unrelated bases define it, or `hook="1"` when only subclasses define it) and the `self.x()` / `cls.x()` sites in its base classes,
with a `hasattr` / `getattr` guard said `guarded="1"` and a reference without a call said `form="ref"`. `--for="what calls
SessionMiddleware.process_request"` now names `MiddlewareMixin.__call__` and `__acall__`, which `--callers` cannot bind. The list is
hedged (a call through `self` reaches this override only for instances of its class) and adds no edge, no count and nothing to `--impact`.
Every site is read from the parse (a docstring, a string, a rebound `self`, a nested def, a lambda or a static method is no site and is counted in `skipped=`); `next=` runs a verb that lists the rest; under `--token-budget` only `<selfhooks held="budget">` is printed. Other answers are byte-identical. `RIPWIRE_NO_SELF_HOOK` turns it off.
