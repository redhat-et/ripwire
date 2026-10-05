package own

// min is this package's own function: a bare min() in this package reaches it (it shadows the builtin).
func min(a, b int) int {
	if a < b {
		return a
	}
	return b
}

func score(a int) int { return a * 2 }

// Pick calls the shadowing min and a plain package function, both bare: both edges are true.
func Pick(a, b int) int {
	return score(min(a, b))
}
