package batcheval

type Cmd struct{}

func (c *Cmd) Eval() int { return goEvalHelper() }

func Put(x int) int { return goPutHelper(x) }

func goEvalHelper() int { return 1 }

func goPutHelper(x int) int { return x }
