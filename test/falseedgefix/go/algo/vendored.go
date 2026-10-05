package algo

import "example.com/vendored/lib"

// UseVendored calls through an import a LOCAL go.mod replace puts in this tree: a true edge.
func UseVendored(n int) int { return lib.Shape(n) }
