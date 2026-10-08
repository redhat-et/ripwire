package fzf

import (
	"fmt"
	"os/exec"
	"strings"
)

// Tool has methods named like stdlib functions and methods it never reaches.
type Tool struct {
	out []byte
}

func (t *Tool) Output() ([]byte, error) {
	return t.out, nil
}

func (t *Tool) Split(s string) []string {
	return []string{s}
}

// runGo: fmt.Errorf, exec's Cmd.Output and strings.Split are stdlib, never Tool's methods or the log package.
func runGo(args string) ([]string, error) {
	cmd := exec.Command("go", args)
	out, err := cmd.Output()
	if err != nil {
		return nil, fmt.Errorf("go: %w", err)
	}
	return strings.Split(string(out), "\n"), nil
}

// runTool: a local of the in-repo type keeps its edges.
func runTool(s string) []string {
	t := &Tool{}
	t.Output()
	return t.Split(s)
}
