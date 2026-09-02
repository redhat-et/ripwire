// fieldusesfix/shapes.go — a language the member selector does NOT serve: `--uses=Box.width` must refuse
// naming Go, never answer with an empty set.
package shapes

type Box struct {
	width int
}

func (b *Box) Grow() {
	b.width = b.width + 1
}
