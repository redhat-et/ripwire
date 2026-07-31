package pkg

// handle.go — the service's Go package. cli/main.go imports it via a go.mod `replace` directive that
// points at this sibling root (DESIGN_multiRoot.md §3.2). A Go import names a PACKAGE (a directory); it
// resolves only because this dir holds exactly one .go file (unique-or-degrade). Go source uses gofmt
// brace style (Allman is invalid Go — ASI inserts a semicolon after the signature line).
func GoHandle() int {
    return 7
}
