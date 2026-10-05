module example.com/rp

go 1.22

// Not buildable Go on purpose: legacy/ has no go.mod, so this replace is the ONLY place the tree names
// example.com/legacy. It pins that the module census reads a local replace (the go/ root is valid Go, where the
// replaced directory's own go.mod names the same path).
replace example.com/legacy => ./legacy
