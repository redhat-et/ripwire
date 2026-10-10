package src

type Base struct{}

func (b *Base) Render() string { return "base" }

type Widget struct{}

func (w *Widget) Render() string { return "widget" }

func NewWidget() *Widget { return &Widget{} }

func makeAny() interface{ Render() string } { return nil }
