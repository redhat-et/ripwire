package fzf

import u "example.com/fzfish/src/util"

// FileItem embeds Chars: its promoted Get is Chars.Get.
type FileItem struct {
	u.Chars
	path string
}

// firstRune: a promoted method through an embedded field.
func firstRune(fi *FileItem) rune {
	return fi.Get(0)
}

// aliased: a local typed through an aliased import.
func aliased() int {
	var c u.Chars
	return c.Length()
}
