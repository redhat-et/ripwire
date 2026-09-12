// test/stdqualfix — file 4: a SPECIALIZATION declared inside `namespace std { }`.
//
// What ripwire does with this TODAY, measured on the pre-fix binary and pinned by the gate rather than
// invented: the specialization's class is not a symbol (its name is a template_type, which no C++ class
// pattern captures), its operator() IS one (scope `hash<Mine>`), and `std::hash<Mine>{}( m )` mints no call
// reference that reaches operator() — brace-initialised temporaries are not call_expressions naming it. So
// hashMine has zero callees before the fix and zero after; the guard adds nothing and takes nothing here.
// The specialization BINDING case the guard must preserve is polyfill.h's inline-namespace def.

struct Mine
{
    int v = 0;
};

namespace std
{
template<> struct hash<Mine>
{
    unsigned long operator()( const Mine& m ) const { return static_cast<unsigned long>( m.v ); }
};
}

unsigned long hashMine( const Mine& m )
{
    return std::hash<Mine>{}( m );
}
