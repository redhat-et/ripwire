package cmd

import "example.com/fzfish/src/internal/log"

// Run: a real import of the in-repo log package, so log.Errorf is that package's function.
func Run() error {
	return log.Errorf("run")
}
