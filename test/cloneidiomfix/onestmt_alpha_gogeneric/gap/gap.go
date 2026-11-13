package gap

func GapOf[T int | int64](x T, y T, margin T) T {
	return (x + y*2 - margin) * (x - y + margin*3) / (y + margin - x*4) + (x*y - margin) + (margin*x - y) + (y*margin - x)
}
