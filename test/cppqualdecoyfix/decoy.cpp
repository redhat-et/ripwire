// cppqualdecoyfix/decoy.cpp — the DISCRIMINATING half of the §H4 C++ qualified-call gate.
//
// test/cppqualfix/qual.cpp proves each spelling EXTRACTS and resolves. It cannot prove the re-split picked
// the RIGHT def, because every name in it has exactly one definition: a garbage qualifier still lands on the
// only candidate by bare-name fallback, so a broken re-split would pass silently. Every name here therefore
// has a DECOY — a same-final-name definition in a DIFFERENT scope that a broken re-split provably binds.
// This fixture lives in its own directory so the counts pinned on qual.cpp stay untouched.
//
// Two independent traps, both found by the adversarial verifier (V2) against the first W2b implementation:
//
//   M-3  TEMPLATE-ARGUMENT STRIP. `a::b::Box<int>::get()` re-splits to qualifier `Box<int>` unless the scope
//        half is passed through stripTemplateArgs first. `Box<int>::get` is not a canonical key, so the
//        lookup misses and the call falls to the bare-name spray — which, with `Other::get` also in scope,
//        splits AMBIGUOUSLY across both defs instead of resolving. The gate asserts each call lands on its
//        OWN def by line, and that the corpus carries NO ambiguity at all.
//
//   M-2  THE `>`-FAMILY OPERATOR NAMES. Scanning `inner::operator>` right-to-left for the last top-level
//        `::`, the trailing `>` opens a template-argument group that never closes, so the scan finds no
//        separator, the re-split is skipped, and the qualifier falls back to the OUTERMOST scope (`outer`)
//        — which is exactly where the decoy lives. `operator>`, `operator>>` and `operator>=` all carry a
//        `>` and are all poisoned by that scan; the fix detects an operator-name tail BEFORE any angle
//        scanning. `operator<<` (the `<`-family) never broke and is kept here as a control, as is
//        `operatorId` — a plain identifier that merely STARTS with "operator" and must NOT take the
//        operator path.
//
//        NOT FIXTURED, deliberately: `operator->`. It shares the mechanism exactly (its name contains a
//        `>`, so the same scan poisons it and the same operator-tail detection cures it), but it cannot
//        legally be a free function, and an explicit qualified call to a member operator has no
//        call_expression shape for any query to match. Its coverage is the shared code path, not a site.

// ---- M-3: the template-argument-strip decoy ---------------------------------------------------------

namespace a
{
namespace b
{

template<typename T>
struct Box
{
    static int get() { return 5; }
};

struct Other
{
    static int get() { return 6; }
};

}
}

int callerStrip()
{
    return a::b::Box<int>::get() + a::b::Other::get();
}

// ---- M-2: the `>`-family operator decoys ------------------------------------------------------------

namespace outer
{

struct S { int v = 0; };

// DECOYS — the outer scope a poisoned re-split falls back to.
bool operator>(  const S& a, const S& b ) { return a.v >  b.v; }
bool operator>>( const S& a, const S& b ) { return a.v >  b.v; }
bool operator>=( const S& a, const S& b ) { return a.v >= b.v; }
bool operator<<( const S& a, const S& b ) { return a.v <  b.v; }
int  operatorId( const S& a )             { return a.v; }
int  gt(         const S& a )             { return a.v; }

namespace inner
{

// TARGETS — the 3-segment spellings below must bind THESE.
bool operator>(  const S& a, const S& b ) { return a.v >  b.v; }
bool operator>>( const S& a, const S& b ) { return a.v >  b.v; }
bool operator>=( const S& a, const S& b ) { return a.v >= b.v; }
bool operator<<( const S& a, const S& b ) { return a.v <  b.v; }
int  operatorId( const S& a )             { return a.v; }
int  gt(         const S& a )             { return a.v; }

}
}

int callerOperators( const outer::S& x, const outer::S& y )
{
    int total = 0;

    total += outer::inner::operator>(  x, y ) ? 1 : 0;
    total += outer::inner::operator>>( x, y ) ? 1 : 0;
    total += outer::inner::operator>=( x, y ) ? 1 : 0;
    total += outer::inner::operator<<( x, y ) ? 1 : 0;   // control: the `<`-family never broke
    total += outer::inner::operatorId( x );              // control: NOT an operator name
    total += outer::inner::gt( x );                      // control: a plain name with an outer decoy

    return total;
}
