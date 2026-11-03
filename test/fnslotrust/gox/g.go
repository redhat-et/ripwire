package gox

type Box struct {
	eval func(string) int
}

func goTarget(s string) int { return len(s) }

func makeBox() Box { return Box{eval: goTarget} }

func (b Box) fire() int { return b.eval("x") }
