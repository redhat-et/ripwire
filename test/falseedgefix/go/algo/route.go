package algo

import "example.com/finder/own"

// Route calls an in-module package's exported function: a true qualified edge.
func Route(a, b int) int {
	return own.Pick(a, b)
}
