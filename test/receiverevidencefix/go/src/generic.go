package fzf

import (
	"example.com/fzfish/src/util"
	"go.uber.org/zap"
)

// Tracker holds a field typed as a generic instantiation from another package.
type Tracker struct {
	seen util.Set[util.Chars]
}

// mark: the field's written type keeps its `util.` qualifier, so Add is util.Set's.
func (t *Tracker) mark(c util.Chars) {
	t.seen.Add(c)
}

// markParam: the same through a parameter.
func markParam(s util.Set[util.Chars], c util.Chars) {
	s.Add(c)
}

// markLocal: the same through a declared local.
func markLocal(c util.Chars) {
	var s util.Set[util.Chars]
	s.Add(c)
}

// markOutside: a generic instantiation from an OUTSIDE package names no in-tree Set.
func markOutside(s zap.Set[int]) {
	s.Add(1)
}
