package util

// Chars holds an item's text.
type Chars struct {
	runes []rune
}

func (c *Chars) Get(i int) rune {
	return c.runes[i]
}

func (c *Chars) Length() int {
	return len(c.runes)
}

func (c *Chars) Runes() []rune {
	return c.runes
}
