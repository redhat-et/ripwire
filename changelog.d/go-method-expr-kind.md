### Fixed — Go method expressions are references, and a selector call never binds a type

`fn := (*Replica).executeReadOnlyBatch` made no reference at all: `--callers=Replica.executeReadOnlyBatch` showed no production caller. A method expression `(*T).m` in a value position is now a value row of T's method m (the same join as a receiver's method value). And `unmarkedPriorVal.Type()` (a method of an outside type) printed the in-tree `type Type` as a `via="name"` row: a name-only Go selector call now drops type candidates, as it already dropped free functions, so a call nothing else answers counts `external=`. A conversion through a package alias (`types.Name( s )`) keeps its edge. Measured on terraform: 406 fewer edges, 3,713 more `external=` (`t.Fatal` beside three in-tree `Fatal` interfaces, `.Type()` on cty values).

What it does not change: a plain `T.m` method expression (its operand is spelled like a package or a variable) and `( *p ).m` on a local stay unread.
