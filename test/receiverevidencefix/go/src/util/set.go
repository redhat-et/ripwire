package util

// Set is a generic set; its Add is the one a `util.Set[T]` value reaches.
type Set[T any] map[string]T

func (s Set[T]) Add(v T) {
	_ = v
}
