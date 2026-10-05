package algo

// Drain only uses the builtins delete, len, close, panic and new.
func Drain(m map[string]int, ch chan int) int {
	for k := range m {
		delete(m, k)
	}
	close(ch)
	p := new(int)
	if len(m) > 0 {
		panic("left")
	}
	return *p
}
