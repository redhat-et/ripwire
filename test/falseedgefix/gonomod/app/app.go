package app

import "github.com/acme/tool/own"

// Run calls the in-tree package through its full import path: a true edge.
func Run() int { return own.Pick(1, 2) }
