// Review B4: Tank and Barrel both define spill(), and the class's field `tank` is a Tank.
protocol Spiller { func spill() }
class Tank: Spiller { func spill() {} }
class Barrel: Spiller { func spill() {} }
enum Cask { case b(Barrel) }

// (a) a binding that hides the field, and a local seen outside its own block; (b) a type parameter named like a class
class Scope {
    var tank: Tank = Tank()
    func forLoop(_ bs: [Barrel]) { for tank in bs { tank.spill() } }
    func forCaseLet(_ bs: [Barrel?]) { for case let tank? in bs { tank.spill() } }
    func forTuple(_ ps: [(Barrel, Barrel)]) { for (tank, _) in ps { tank.spill() } }
    func closureParam(_ bs: [Barrel]) { bs.forEach { tank in tank.spill() } }
    func typedClosure(_ bs: [Barrel]) { bs.forEach { (tank: Barrel) in tank.spill() } }
    func ifLet(_ b: Barrel?) { if let tank = b { tank.spill() } }
    func guardLet(_ b: Barrel?) { guard let tank = b else { return }; tank.spill() }
    func whileLet(_ it: inout IndexingIterator<[Barrel]>) { while let tank = it.next() { tank.spill() } }
    func caseLet(_ x: Cask) { switch x { case .b(let tank): tank.spill() } }
    func ifCaseLet(_ x: Cask) { if case .b(let tank) = x { tank.spill() } }
    func catchLet() { do { } catch let tank { tank.spill() } }
    func nestedBlock(_ b: Bool) { if b { let tank = Barrel(); _ = tank }; tank.spill() }
    func fieldUse() { tank.spill() }
    func typedLocal() { let tank: Barrel = Barrel(); tank.spill() }
}

class Box<Tank: Spiller> {
    var item: Tank
    init(item: Tank) { self.item = item }
    func classTypeParam(_ t: Tank) { t.spill() }
    func typeParamField() { item.spill() }
}
