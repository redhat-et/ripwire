// method values of the method's own receiver, stored in a local and called inside a closure
package local

type Local struct{}
type Remote struct{}

func (b *Local) opPlan(x int)  {}
func (b *Local) opApply(x int) {}
func (r *Remote) opPlan(x int) {}

func (b *Local) Operation(t int, other *Remote) {
	var f func(int)
	switch t {
	case 1:
		f = b.opPlan
	case 2:
		f = b.opApply
	case 3:
		f = other.opPlan
	}
	go func() {
		f(t)
	}()
}
