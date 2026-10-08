using System;
using System.Linq;
using System.Collections.Generic;
namespace App {
    // Review B4: Tank and Barrel both define Spill(), and the class's field `tank` is a Tank.
    public interface ISpiller { void Spill(); }
    public class Tank : ISpiller { public void Spill() {} }
    public class Barrel : ISpiller { public void Spill() {} }

    // (a) a binding that hides the field, and a local seen outside its own block; (b) a type parameter named like a class
    public class Scope {
        private Tank tank = new Tank();
        public void ForEachLoop(List<Barrel> bs) { foreach (Barrel tank in bs) { tank.Spill(); } }
        public void ForEachVar(List<Barrel> bs) { foreach (var tank in bs) { tank.Spill(); } }
        public void LambdaParam(List<Barrel> bs) { bs.ForEach(tank => tank.Spill()); }
        public void PatternVar(object o) { if (o is Barrel tank) { tank.Spill(); } }
        public void OutVar(Dictionary<int, Barrel> d) { var found = d.TryGetValue(1, out var tank); if (found) tank.Spill(); }
        public void SwitchCase(object o) { switch (o) { case Barrel tank: tank.Spill(); break; } }
        public void Deconstruct((Barrel, Barrel) p) { var (tank, other) = p; tank.Spill(); }
        public void CatchUse() { try { } catch (Exception tank) { tank.Spill(); } }
        public void Linq(List<Barrel> bs) { var q = from tank in bs select tank.Spill(); }
        public void NestedBlock(bool b) { if (b) { Barrel tank = new Barrel(); } tank.Spill(); }
        public void LambdaOutside(List<Barrel> bs) { bs.ForEach((Barrel tank) => { }); tank.Spill(); }
        public void FieldUse() { tank.Spill(); }
        public void TypedLocal() { Barrel tank = new Barrel(); tank.Spill(); }
        public void MethodTypeParam<Tank>(Tank t) where Tank : ISpiller { t.Spill(); }
    }

    public class Box<Tank> where Tank : ISpiller {
        private Tank item;
        public void ClassTypeParam(Tank t) { t.Spill(); }
        public void TypeParamField() { item.Spill(); }
    }
}
