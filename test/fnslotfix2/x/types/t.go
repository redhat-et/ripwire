package types

type Cmd struct{ Run func() }

func runX() {}

var A = Cmd{Run: runX}

func execX(c Cmd) { c.Run() }
