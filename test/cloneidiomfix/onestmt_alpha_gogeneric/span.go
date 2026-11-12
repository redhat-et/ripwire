package span

func WidthBetween[T int | int64](lo T, hi T, pad T) T {
	return (lo + hi*2 - pad) * (lo - hi + pad*3) / (hi + pad - lo*4) + (lo*hi - pad) + (pad*lo - hi) + (hi*pad - lo)
}
