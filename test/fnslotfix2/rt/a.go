package rt

type Route struct{ H func() }

type Router struct{ r Route }

func (rt *Router) Mount(name string, fn func()) { rt.r = Route{H: fn} }

func serve(x Route) { x.H() }
