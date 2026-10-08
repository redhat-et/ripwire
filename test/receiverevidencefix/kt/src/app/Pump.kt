package app

// Review B3: Kotlin receivers the source TYPES resolve (a typed parameter, a typed / constructed local, a typed or
// constructed property, a `val` constructor property), against two classes that both define spill(). Near misses stay
// hedged: an untyped local from a lower-case factory, a local that hides the property, an interface-typed receiver.
interface Spiller { fun spill() }
class Tank : Spiller { override fun spill() {} }
class Barrel : Spiller { override fun spill() {} }

class Pump(val keg: Barrel) {
    private val tank: Tank = Tank()
    var spare = Tank()
    fun param(t: Tank) { t.spill() }
    fun typedLocal() { val t: Tank = makeTank(); t.spill() }
    fun ctorLocal() { val t = Tank(); t.spill() }
    fun implicitField() { tank.spill() }
    fun thisField() { this.tank.spill() }
    fun ctorProperty() { keg.spill() }
    fun constructedProperty() { spare.spill() }
    fun untyped() { val x = makeAny(); x.spill() }
    fun shadow() { val tank = makeAny(); tank.spill() }
    fun viaIface(s: Spiller) { s.spill() }
    fun makeTank(): Tank = Tank()
    fun makeAny(): Any = Tank()
}
