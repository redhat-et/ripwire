package algo

func apply(f func(int) int, n int) int { return f(n) }
func inc(n int) int { return n + 1 }
func UseFnVal() int { return apply(inc, 1) }
