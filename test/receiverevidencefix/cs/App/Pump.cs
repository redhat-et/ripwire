// Review B3: C# receivers the source TYPES resolve (a typed parameter, a typed / constructed / `var` local, a typed field
// read bare or through `this`, a typed property), against two classes that both define Spill(). Near misses stay hedged:
// an untyped local, a local that hides the field, an interface-typed receiver with two implementors.
namespace App
{
    interface ISpiller { void Spill(); }
    class Tank : ISpiller { public void Spill() {} }
    class Barrel : ISpiller { public void Spill() {} }

    public class Pump
    {
        private Tank tank = new Tank();
        public Barrel Keg { get; } = new Barrel();
        void Param(Tank t) { t.Spill(); }
        void TypedLocal() { Tank t = MakeTank(); t.Spill(); }
        void CtorLocal() { var t = new Tank(); t.Spill(); }
        void ImplicitField() { tank.Spill(); }
        void ThisField() { this.tank.Spill(); }
        void ViaProperty() { Keg.Spill(); }
        void Untyped() { var x = MakeAny(); x.Spill(); }
        void Shadow() { var tank = MakeAny(); tank.Spill(); }
        void ViaIface(ISpiller s) { s.Spill(); }
        Tank MakeTank() { return null; }
        dynamic MakeAny() { return null; }
    }
}
