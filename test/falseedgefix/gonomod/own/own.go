package own

// A tree with no go.mod: its module path is unknown, so no import can be proven outside it.
func Pick(a, b int) int { return a + b }
