// C# call-FORM fixture for the H4 round (test/csharpcondcheck.sh).
//
// Exercises every call spelling C# offers, split across three methods so the gate can attribute
// each spelling to a caller by NAME rather than guessing which edge came from which line:
//
//   Caller()          — the classic forms that worked before the H4 fix, plus the two duplicate-ref
//                       pairs that expose (from,to) edge collapse in graph.h.
//   CondOnly()        — ONLY conditional-access ("?.") calls; every reference here was invisible
//                       before the fix, so this method's edge count is the red-first arm.
//   CondThenMember()  — `?.` followed by a PLAIN member access; captured by the pre-existing
//                       member_access pattern, i.e. identical pre- and post-fix.
//
// Deliberately kept single-target: no name in this file has two definitions, so ambiguous=0 and
// unresolved=0 and every reference has exactly one resolution target. Fields (b, B) are not
// captured as definitions by design (queries/csharp/tags.scm header).

namespace Ns
{
    class Inner
    {
        public void C() {}
    }

    class Widget
    {
        public Inner b;
        public Inner B;
        public void Bump() {}
        public void BumpGen<T>( T x ) {}
    }

    static class Util
    {
        public static void Tool() {}
    }

    class Driver
    {
        void Bare() {}
        void Gen<T>( T x ) {}

        void Caller( Widget w )
        {
            Bare();                //  1  bare call
            w.Bump();              //  2  member call
            Util.Tool();           //  3  2-segment member chain
            Ns.Util.Tool();        //  4  3-segment member chain   -> SAME target as 3
            w.BumpGen<int>( 1 );   //  5  generic member call
            Gen<int>( 1 );         //  6  generic bare call
            new Widget();          //  7  bare new
            new Ns.Widget();       //  8  qualified new            -> SAME target as 7
        }

        void CondOnly( Widget w, Widget a )
        {
            w?.Bump();             //  9  conditional-access member call
            a?.b?.C();             // 10  conditional-access chain, both links guarded
            w?.BumpGen<int>( 1 );  // 11  conditional-access generic member call
        }

        void CondThenMember( Widget a )
        {
            a?.B.C();              // 12  guarded link then PLAIN link — the invoked name is a
                                   //     member_access_expression, never a member_binding_expression
        }
    }
}
