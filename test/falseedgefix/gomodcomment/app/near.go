package app

import lib "example.com/cmx/lib"

// Near calls a package OUTSIDE the module whose path only starts with the module path (cmx, not cm/): no edge to
// the in-tree Shape.
func Near(n int) int { return lib.Shape(n) }
