package hist

// cache's methods are spelled like the builtins delete, len and close.
type cache struct{ m map[string]int }

func (c *cache) delete(k string) { _ = k }
func (c *cache) len() int        { return 0 }
func (c *cache) close()          {}
