package tui

import (
	"strings"

	"github.com/example/cells"
)

// NewScreen is spelled like the external package's constructor.
func NewScreen() *Renderer { return &Renderer{} }

type Renderer struct{ rows int }

// Split is spelled like strings.Split.
func Split(s string) []string { return []string{s} }

// Open calls the EXTERNAL package's constructor and the standard library's Split: neither is in-repo.
func Open(spec string) int {
	scr := cells.NewScreen()
	parts := strings.Split(spec, ",")
	_ = scr
	return len(parts)
}
