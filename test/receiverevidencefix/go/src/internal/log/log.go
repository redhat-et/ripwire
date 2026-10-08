package log

import "fmt"

// Errorf is the in-repo log package's function.
func Errorf(format string, a ...any) error {
	return fmt.Errorf(format, a...)
}
