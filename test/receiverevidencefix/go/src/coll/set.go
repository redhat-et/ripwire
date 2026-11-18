package coll

// Set is another package's generic set with an Add of its own: a decoy for an unqualified `Set`.
type Set[T any] struct {
	items []T
}

func (s Set[T]) Add(vs ...T) {
	_ = vs
}
