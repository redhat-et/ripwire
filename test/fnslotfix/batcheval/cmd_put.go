package batcheval

func init() { RegisterReadWriteCommand(1, declareKeysPut, Put) }

func declareKeysPut(x int) int { return x }

func Put(a int, b string) error { return nil }

func Direct(a int, b string) error { return nil }

var direct = Command{EvalRW: Direct}

func Assigned(a int, b string) error { return nil }

func assign(c *Command) { c.EvalRW = Assigned }
