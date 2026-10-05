package term

// Scale holds a local variable spelled like the builtin max.
func Scale(xs []float64) float64 {
	var max float64
	for _, x := range xs {
		if x > max {
			max = x
		}
	}
	return max
}
