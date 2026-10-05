package own

// hook is a package-level function VARIABLE: a bare call in this package reaches it.
var hook = func(s string) string { return s }

// Fire calls the variable bare: a true edge.
func Fire(s string) string {
	return hook(s)
}
