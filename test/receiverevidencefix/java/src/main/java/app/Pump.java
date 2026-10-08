package app;

// Review B3: Java receivers the source TYPES resolve (a typed parameter, a typed / constructed / `var` local, a typed field
// read bare or through `this`), against two classes that both define spill(). Near misses stay hedged: an untyped local,
// a local that hides the field, an interface-typed receiver with two implementors.
interface Spiller { void spill(); }
class Tank implements Spiller { public void spill() {} }
class Barrel implements Spiller { public void spill() {} }

public class Pump {
    private Tank tank = new Tank();
    void param(Tank t) { t.spill(); }
    void typedLocal() { Tank t = makeTank(); t.spill(); }
    void ctorLocal() { Tank t = new Tank(); t.spill(); }
    void varLocal() { var t = new Tank(); t.spill(); }
    void implicitField() { tank.spill(); }
    void thisField() { this.tank.spill(); }
    void untyped() { var x = makeAny(); x.spill(); }
    void shadow() { var tank = makeAny(); tank.spill(); }
    void viaIface(Spiller s) { s.spill(); }
    Tank makeTank() { return null; }
    Object makeAny() { return null; }
}
