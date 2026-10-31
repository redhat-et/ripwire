package x

type Hook struct{ cb func(int) int }

func goTool(n int) int { return n }

func fireGo(h Hook) int { return h.cb(1) }

var T = Hook{cb: goTool}
