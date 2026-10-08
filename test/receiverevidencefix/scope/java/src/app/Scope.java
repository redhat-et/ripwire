package app;

import java.util.List;

// Review B4: Tank and Barrel both define spill(), and the class's field `tank` is a Tank.
interface Spiller { void spill(); }
class Tank implements Spiller { public void spill() {} }
class Barrel implements Spiller, AutoCloseable { public void spill() {} public void close() {} }
record P(Barrel b) {}

// (a) a binding that hides the field — a loop, lambda, catch or resource variable, a pattern variable — and a local seen
// outside its own block; (b) a generic's type parameter named like a class. Kept: the field, a typed local.
class Scope {
    private Tank tank = new Tank();
    void forEachLoop(List<Barrel> bs) { for (Barrel tank : bs) { tank.spill(); } }
    void lambdaParam(List<Barrel> bs) { bs.forEach(tank -> tank.spill()); }
    void typedLambda(List<Barrel> bs) { bs.forEach((Barrel tank) -> tank.spill()); }
    void catchUse() { try { } catch (RuntimeException tank) { tank.spill(); } }
    void tryRes() throws Exception { try (Barrel tank = new Barrel()) { tank.spill(); tank.close(); } }
    void patternVar(Object o) { if (o instanceof Barrel tank) { tank.spill(); } }
    void negatedPattern(Object o) { if (!(o instanceof Barrel tank)) return; tank.spill(); }
    void switchPattern(Object o) { switch (o) { case Barrel tank -> tank.spill(); default -> {} } }
    void recordPattern(Object o) { if (o instanceof P(Barrel tank)) { tank.spill(); } }
    void nestedBlock(boolean b) { if (b) { Barrel tank = new Barrel(); } tank.spill(); }
    void lambdaOutside(List<Barrel> bs) { bs.forEach((Barrel tank) -> { }); tank.spill(); }
    void fieldUse() { tank.spill(); }
    void typedLocal() { Barrel tank = new Barrel(); tank.spill(); }
    <Tank extends Spiller> void methodTypeParam(Tank t) { t.spill(); }
}

class Box<Tank extends Spiller> {
    Tank item;
    void classTypeParam(Tank t) { t.spill(); }
    void typeParamField() { item.spill(); }
}
