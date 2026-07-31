package main

import "fmt"

type G struct{}

func (g G) M() int { return 1 }
func F() int       { return 2 }
func Generic[T any](x T) T { return x }

func caller() {
	a := F()          // 1. bare call
	g := G{}
	a += g.M()        // 2. method via selector
	fmt.Println(a)    // 3. pkg.Fn selector (external)
	Generic[int](1)   // 4. generic instantiation call
	defer F()         // 5. deferred call
	go F()            // 6. goroutine call
	f := F
	f()               // 7. call through func value
	(F)()             // 8. parenthesized callee
}
