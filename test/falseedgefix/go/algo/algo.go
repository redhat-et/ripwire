package algo

// Collect only uses the builtins append, max, copy, len and make.
func Collect(xs []int, buf []byte) []int {
	out := make([]int, 0, len(xs))
	for _, x := range xs {
		out = append(out, x)
	}
	n := max(len(xs), 3)
	tmp := make([]byte, n)
	copy(tmp, buf)
	return out
}
