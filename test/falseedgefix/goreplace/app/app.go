package app

import "example.com/legacy/lib"

// UseLegacy calls through an import a LOCAL go.mod replace puts in this tree: a true edge.
func UseLegacy(n int) int { return lib.Shape(n) }
