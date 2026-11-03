// near miss: a same-named struct type in another package, whose field holds a function
package cobra

type Command struct {
	RunE func() error
}

func runRoot() error { return nil }

var Root = Command{RunE: runRoot}

func execute(c Command) error { return c.RunE() }
