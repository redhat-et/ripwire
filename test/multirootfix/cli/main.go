package main

// main.go — the client. The import path "example.com/svc/pkg" is a bare module path; single-root Go is
// DEFERRED (unresolved). Only the go.mod `replace example.com/svc => ../svc` below admits the cross-root
// package resolution into the sibling svc root — same evidence-only posture as the TS alias.
import "example.com/svc/pkg"

func runGoMain() int {
    return pkg.GoHandle()
}
