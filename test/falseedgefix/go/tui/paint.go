package tui

import c "github.com/example/cells"

// Paint reaches the outside package through an import alias.
func Paint() {
	_ = c.NewScreen()
}
