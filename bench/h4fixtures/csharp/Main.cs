// C# call-form fixture.
namespace Ns
{
    class Widget
    {
        public Widget() {}
        public static Widget Make() { return new Widget(); }
        public void Bump() {}
    }
    static class Util { public static void Tool() {} }
    class Main
    {
        void Generic<T>(T x) {}
        void Caller()
        {
            var w = Widget.Make();    // 1. Type.static call
            w.Bump();                 // 2. method call
            Ns.Util.Tool();           // 3. 3-segment chain call
            Util.Tool();              // 4. 2-segment chain
            w?.Bump();                // 5. conditional-access call
            Generic<int>(1);          // 6. generic bare call
            w.Generic2<int>(1);       // 7. generic member call (ext below)
            new Widget();             // 8. bare new
            new Ns.Widget();          // 9. qualified new
        }
        void Generic2<T>(T x) {}
    }
}
