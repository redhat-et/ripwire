package fzf

import "example.com/fzfish/src/util"

// buildResult reads an item's text through its typed field.
func buildResult(item *Item, b int) int {
	numChars := item.text.Length()
	last := item.text.Get(b - 1)
	return numChars + int(last)
}

// merged: a local whose type is spelled at its declaration.
func merged(n int) int {
	m := &Merger{count: n}
	return m.Length()
}

// fromValue: a local declared with an in-repo type from another package.
func fromValue(c util.Chars) rune {
	return c.Get(0)
}
