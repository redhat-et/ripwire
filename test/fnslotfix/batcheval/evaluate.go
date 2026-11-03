package batcheval

func evaluateCommand(m int) error {
	cmd, ok := LookupCommand(m)
	if !ok {
		return nil
	}
	return cmd.EvalRW(1, "x")
}
