package app

import "example.com/cm/lib"

// Run calls into its own module: a true edge.
func Run(n int) int { return lib.Shape(n) }
