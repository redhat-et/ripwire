package cx

type Thing struct{ draw func() }

func gdraw() {}

var t = Thing{draw: gdraw}

func goCall(x Thing) { x.draw() }
