// GO-METHOD-EXPR: a method expression `(*T).m` stored in a local and handed on (cockroach replica_send.go's
// `fn := (*Replica).executeReadOnlyBatch`), beside a same-named method of another type and a method value of a
// dereferenced parameter, which names no type
package local

type Replica struct{ n int }
type Mirror struct{ n int }

func (r *Replica) executeReadOnlyBatch(x int) int { return r.n + x }
func (m *Mirror) executeReadOnlyBatch(x int) int  { return m.n + x }

func runBatch(fn func(*Replica, int) int, r *Replica) int { return fn(r, 1) }

func dispatch(r *Replica) int {
	fn := (*Replica).executeReadOnlyBatch
	return runBatch(fn, r)
}

func viaParam(p *Mirror) int {
	g := (*p).executeReadOnlyBatch
	return g(1)
}
