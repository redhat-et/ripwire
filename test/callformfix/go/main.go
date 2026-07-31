// GO CALL-FORM MATRIX fixture — one line per call SPELLING the grammar distinguishes.
// Expected counts are literals read off this file; ABSENT rows are asserted at 0.
package main

type Recv struct{ n int }

func (r Recv) selectorFn() int { return r.n }

func bareFn() int { return 1 }

func deferFn() int { return 2 }

func goStmtFn() int { return 3 }

func parenFn() int { return 4 }

func inferredGeneric[T any](v T) T { return v }

func explicitGeneric[T any](v T) T { return v }

func indexedFn(x int) int { return x }

func caller() int {
	a := bareFn()                 // 1. bare call
	r := Recv{}
	a += r.selectorFn()           // 2. selector call
	a += inferredGeneric(1)       // 3. inferred generic — plain identifier call, captured
	a += explicitGeneric[int](1)  // 4. ABSENT: explicit instantiation parses as
	                              //    type_conversion_expression, NOT call_expression
	defer deferFn()               // 5. defer statement
	go goStmtFn()                 // 6. go statement
	a += (parenFn)()              // 7. parenthesized function expression
	return a
}

func callerIndexed() int {
	// 8. ABSENT AND MUST STAY ABSENT: index-then-call shares the type_conversion_expression node
	// kind with spelling 4, so a widening that captured spelling 4 by node kind alone would mint a
	// bogus call reference named `fs` here. `fs` is a slice of func values, not a callee.
	fs := []func(int) int{indexedFn}
	return fs[0](3)
}
