package util

// copy is a package-level function in ANOTHER package: a bare copy() elsewhere cannot reach it.
func copy(dst, src []byte) int {
	n := 0
	for i := range src {
		dst[i] = src[i]
		n++
	}
	return n
}

// Dup is a true bare caller of the same-package copy above.
func Dup(b []byte) []byte {
	out := make([]byte, len(b))
	copy(out, b)
	return out
}
