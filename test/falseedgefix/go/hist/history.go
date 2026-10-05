package hist

// History keeps entered lines; its method is spelled like the builtin append.
type History struct{ lines []string }

func (h *History) append(line string) error {
	h.lines = append(h.lines, line)
	return nil
}

// Remember is a true caller of the method through a receiver.
func Remember(h *History, s string) {
	_ = h.append(s)
}
