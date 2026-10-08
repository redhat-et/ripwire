package app

import "example.com/legacy/lib"

func Use(n int) int { return lib.Mark(n) }
