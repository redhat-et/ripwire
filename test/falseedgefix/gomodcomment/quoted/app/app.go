package app

import "example.com/qm/lib"

// Use calls into its own (quoted) module: a true edge.
func Use(n int) int { return lib.Mark(n) }
