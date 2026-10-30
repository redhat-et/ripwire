package twofield

type H struct {
	A func()
	B func()
}

func Hold(fn func()) {
	_ = H{A: fn}
	_ = H{B: fn}
}

func amb() {}

func init() { Hold(amb) }

func fireA(h H) { h.A() }
func fireB(h H) { h.B() }
