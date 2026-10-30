package misc

func Reg(fn func()) { _ = Hooks{OnDone: fn} }
