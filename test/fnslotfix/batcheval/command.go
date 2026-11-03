// fn-valued slot fixture (test/fnslotcheck.sh): a command table filled through a registrar's parameter.
package batcheval

type Command struct {
	DeclareKeys func(int) int
	EvalRW      func(int, string) error
}

var cmds = map[int]Command{}

func register(m int, c Command) { cmds[m] = c }

func RegisterReadWriteCommand(m int, declare func(int) int, impl func(int, string) error) {
	register(m, Command{
		DeclareKeys: declare,
		EvalRW:      impl,
	})
}

func LookupCommand(m int) (Command, bool) { c, ok := cmds[m]; return c, ok }
