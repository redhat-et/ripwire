package main
type MyStruct struct{ v int }
func take(fs []func(int) int, i int) {
	_ = int(i)         // plain conversion
	_ = MyStruct{v: i} // literal
	_ = fs[i](3)       // index-then-call
}
