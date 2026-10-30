package misc2

type Hooks2 struct{ OnFail func() }

func Reg(fn func()) { _ = Hooks2{OnFail: fn} }

func ambiguous() {}

func init() { Reg(ambiguous) }

func fire(h Hooks2) { h.OnFail() }
