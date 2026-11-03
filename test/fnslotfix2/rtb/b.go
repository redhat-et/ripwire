package rtb

func Mount(p0 func(), p1 func()) {}

func zero() {}
func one()  {}

func init() { Mount(zero, one) }
