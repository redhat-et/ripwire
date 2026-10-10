package src

type Panel struct {
	Base
}

func (p *Panel) Typed() string {
	base := &Widget{}
	return base.Render()
}

func (p *Panel) Untyped() string {
	base := makeAny()
	return base.Render()
}

func (p *Panel) Super() string {
	super := makeAny()
	return super.Render()
}

func (p *Panel) Promoted() string {
	return p.Render()
}
