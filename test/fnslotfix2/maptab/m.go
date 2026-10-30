package maptab

type Op int

const OpPut Op = 1

type Table map[Op]func()

func putTab() {}
func opsFn()  {}

var t = Table{OpPut: putTab}

type Ops struct{ OpPut func() }

var o = Ops{OpPut: opsFn}

func callOps(o Ops) { o.OpPut() }
