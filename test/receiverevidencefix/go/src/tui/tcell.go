package tui

import (
	"github.com/gdamore/tcell/v2"
	"github.com/rivo/uniseg"
)

var _screen tcell.Screen

type FullscreenRenderer struct {
	height int
}

func (r *FullscreenRenderer) Size() int {
	return r.height
}

func (r *FullscreenRenderer) Runes() []rune {
	return nil
}

// MaxY asks the outside screen, not this renderer.
func (r *FullscreenRenderer) MaxY() int {
	_, nlines := _screen.Size()
	return nlines
}

// Lines asks the renderer itself: the method receiver is the type.
func (r *FullscreenRenderer) Lines() int {
	return r.Size()
}

// Graphemes: a value returned by an outside package.
func Graphemes(input string) int {
	gr := uniseg.NewGraphemes(input)
	return len(gr.Runes())
}
