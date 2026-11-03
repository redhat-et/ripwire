package mapraw

type Op int

const OpGet Op = 1

func getMap() {}

var t = map[Op]func(){OpGet: getMap}

type Ops struct{ OpGet func() }

func callGet(o Ops) { o.OpGet() }
