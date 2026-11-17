package shapes

func next(a int) int  { return a }
func limit(b int) int { return b }
func feed(c int) chan int { return make(chan int, c) }
func use(v int)       {}

func loop(ch chan int) {
	for i := next(1); i < limit(2); i++ {
		use(i)
	}
	select {
	case v := <-feed(3):
		use(v)
	case ch <- next(4):
	}
}
