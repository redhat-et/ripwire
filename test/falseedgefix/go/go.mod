module example.com/finder

go 1.22

require (
	example.com/sub v0.0.0
	example.com/vendored v0.0.0
)

replace example.com/sub => ./sub

replace example.com/vendored => ./vendored
