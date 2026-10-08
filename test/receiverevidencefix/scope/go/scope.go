// Review B4 (language neutrality): a binding that hides a typed parameter of its name, and a type parameter named like
// a type. Tank and Barrel both define Spill.
package scope

type Spiller interface{ Spill() }
type Tank struct{}

func (Tank) Spill() {}

type Barrel struct{}

func (Barrel) Spill() {}

func RangeLoop(tank Tank, bs []Barrel) {
	for _, tank := range bs {
		tank.Spill()
	}
}
func ShortIf(tank Tank, b Barrel) {
	if tank := b; true {
		tank.Spill()
	}
}
func TypeSwitch(tank Tank, o any) {
	switch tank := o.(type) {
	case Barrel:
		tank.Spill()
	}
}
func BlockOutside(tank Tank, b Barrel) {
	{
		tank := b
		_ = tank
	}
	tank.Spill()
}
func TypeParam[Tank Spiller](t Tank) { t.Spill() }

type Box[Tank Spiller] struct{ item Tank }

func (g Box[Tank]) TypeParamField() { g.item.Spill() }
func TypedParam(t Tank)               { t.Spill() }
