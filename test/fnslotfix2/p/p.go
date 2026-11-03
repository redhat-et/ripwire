package p

type A struct{ F func() }
type B struct{ F func() }

func fa() {}
func fb() {}

var a = A{F: fa}
var b = B{F: fb}

func useA(x A) { x.F() }
