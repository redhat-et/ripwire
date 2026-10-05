package lib

// Shape lives in this tree under a module path that only go.mod's local replace maps here.
func Shape(n int) int { return n * 3 }
