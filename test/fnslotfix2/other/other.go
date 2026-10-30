package other

var list []func()

func Enlist(fn func()) { list = append(list, fn) }

func otherFn() {}

func init() { Enlist(otherFn) }
