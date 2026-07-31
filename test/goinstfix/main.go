// H4 gate fixture (Go): explicit generic instantiation was INVESTIGATED and REJECTED for
// widening (queries/go/tags.scm, see the H4 comment there) — `Generic[int](1)` parses as
// type_conversion_expression, structurally IDENTICAL to ordinary index-then-call
// (`fs[i](3)`); tree-sitter cannot tell them apart without type information. This fixture is a
// FENCE, not a fix: it proves the widening was never shipped (F captured, Generic[int] still
// dropped) and that the ambiguous shape (fs[i](3)) is never miscaptured as a call to "fs".
package main

func F() int { return 1 }

type G struct{}

func Generic[T any](x T) T { return x }

func take(fs []func(int) int, i int) int {
	return fs[i](3) // index-then-call — must NEVER be captured as a call to "fs"
}

func caller() int {
	a := F()          // control: bare call (worked before H4, still works)
	b := Generic(1)    // control: type-inferred generic call (plain call_expression, already worked)
	c := Generic[int](1) // explicit instantiation — REJECTED widening, stays dropped
	return a + b + c
}
