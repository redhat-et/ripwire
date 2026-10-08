package app

// Review B4: Tank and Barrel both define spill(), and the class's field `tank` is a Tank.
interface Spiller { fun spill() }
class Tank : Spiller { override fun spill() {} }
class Barrel : Spiller { override fun spill() {} }

// (a) a binding that hides the field, and a local seen outside its own block; (b) a type parameter named like a class
class Scope {
    private val tank: Tank = Tank()
    fun forLoop(bs: List<Barrel>) { for (tank in bs) { tank.spill() } }
    fun forDestructure(ps: List<Pair<Barrel, Barrel>>) { for ((tank, o) in ps) { tank.spill() } }
    fun lambdaParam(bs: List<Barrel>) { bs.forEach { tank -> tank.spill() } }
    fun letParam(b: Barrel?) { b?.let { tank -> tank.spill() } }
    fun typedLambda(bs: List<Barrel>) { bs.forEach { tank: Barrel -> tank.spill() } }
    fun destructure(p: Pair<Barrel, Barrel>) { val (tank, other) = p; tank.spill() }
    fun whenSubject(o: Any) { when (val tank = o) { is Barrel -> tank.spill() } }
    fun catchUse() { try { } catch (tank: Exception) { tank.spill() } }
    fun nestedBlock(b: Boolean) { if (b) { val tank = Barrel() }; tank.spill() }
    fun lambdaOutside(bs: List<Barrel>) { bs.forEach { tank: Barrel -> }; tank.spill() }
    fun fieldUse() { tank.spill() }
    fun typedLocal() { val tank: Barrel = Barrel(); tank.spill() }
}

class Box<Tank : Spiller>(val item: Tank) {
    fun classTypeParam(t: Tank) { t.spill() }
    fun typeParamField() { item.spill() }
}
