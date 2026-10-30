package types

type Cmd struct{ Run func() }

func runY() {}

var B = Cmd{Run: runY}
