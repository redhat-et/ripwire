// near misses: a field named like a Go method; a map literal; two same-named registrars storing different fields
package misc

type Hooks struct {
	Close  func()
	OnDone func()
	OnFail func()
}

type File struct{}

func (f *File) Close() {}

func closeHook() {}
func doneHook()  {}

var hooks = Hooks{Close: closeHook}

func useHooks(h Hooks, f *File) {
	h.Close()
	f.Close()
}

var table = map[string]func(){"done": doneHook}

func runTable(k string) { table[k]() }
