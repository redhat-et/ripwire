// C# CALL-FORM MATRIX fixture — one line per call SPELLING the grammar distinguishes.
// Every callee has a UNIQUE name so `--uses=<name>` is a per-spelling assertion; expected counts
// are literals read off this file.
namespace Ns
{
    class Widget
    {
        public Widget Inner;
        public int Member() { return 1; }
        public int CondOne() { return 2; }
        public int CondChain() { return 3; }
        public int CondMixed() { return 4; }
        public int CondGeneric<T>(T v) { return 5; }
        public int MemberGeneric<T>(T v) { return 6; }
    }

    class Gadget
    {
        public int Ping() { return 7; }
    }

    static class Util
    {
        public static int TwoSeg() { return 8; }
    }

    static class Deep
    {
        public static class Mid
        {
            public static int ThreeSeg() { return 9; }
        }
    }

    class Caller
    {
        static int Bare() { return 10; }

        static int GenericFree<T>(T v) { return 11; }

        int Run()
        {
            int a = Bare();                     // 1. bare call
            var w = new Widget();               // 8. new, unqualified ctor
            a += w.Member();                    // 2. member call
            a += Util.TwoSeg();                 // 3. 2-segment member-access chain
            a += Deep.Mid.ThreeSeg();           // 4. 3-segment member-access chain
            a += w?.CondOne() ?? 0;             // 5. conditional access, single link
            a += w?.Inner?.CondChain() ?? 0;    // 6. conditional access, chained ?.
            a += w?.Inner.CondMixed() ?? 0;     // 7. mixed ?. then .
            a += w?.CondGeneric<int>(1) ?? 0;   // 9. conditional access on a GENERIC method
            a += GenericFree<int>(1);           // 10. generic call, bare
            a += w.MemberGeneric<int>(1);       // 11. generic call, member
            var g = new Ns.Gadget();            // 12. qualified new (qualified_name nests LEFT)
            a += g.Ping();
            return a;
        }
    }
}
