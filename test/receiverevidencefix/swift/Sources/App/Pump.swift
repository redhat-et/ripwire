// Review B3: Swift receivers the source TYPES resolve (a typed parameter, a typed / constructed local, a typed or
// constructed property read bare or through `self`), against two classes that both define spill(). Near misses stay
// hedged: an untyped local from a lower-case factory, a local that hides the property, a protocol-typed receiver.
protocol Spiller { func spill() }
class Tank: Spiller { func spill() {} }
class Barrel: Spiller { func spill() {} }

class Pump {
    var tank: Tank = Tank()
    let keg = Barrel()
    func param(t: Tank) { t.spill() }
    func typedLocal() { let t: Tank = makeTank(); t.spill() }
    func ctorLocal() { let t = Tank(); t.spill() }
    func implicitField() { tank.spill() }
    func selfField() { self.tank.spill() }
    func constructedProperty() { keg.spill() }
    func untyped() { let x = makeAny(); x.spill() }
    func shadow() { let tank = makeAny(); tank.spill() }
    func viaIface(s: Spiller) { s.spill() }
    func makeTank() -> Tank { return Tank() }
    func makeAny() -> Any { return Tank() }
}
