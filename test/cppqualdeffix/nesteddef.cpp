// cppqualdeffix/nesteddef.cpp — the DEFINITION half of the qualified-name recursion (C1, memgraph F1).
//
// test/cppqualfix/ proves that qualified CALLS extract at any `::` depth. This fixture proves the same for
// out-of-line DEFINITIONS, which were silently dropped past ONE qualifier segment: tree-sitter-cpp nests
// qualified_identifier RIGHT-recursively, so for `A::B::c` the `name:` child is itself a
// qualified_identifier and the 2-segment tags pattern (`name: (identifier)`) never bound. No `--skipped`
// row, no floor, no `unresolved=` — the def simply did not exist, and every caller of it read as a leaf.
//
// WHY A THIRD CORPUS DIRECTORY. test/cppqualfix/ pins a hand-read `files=1 symbols=23 edges=11` header
// literal; a second .cpp in it would invalidate that literal for reasons unrelated to what it proves.
//
// Each definition body calls its OWN uniquely named sink, so `--callers=<sink>` is a single-literal
// assertion that both (a) the definition was indexed and (b) it carries its body's call edges. Names are
// unique across the file EXCEPT for the deliberate `deep3` decoy pair described below.
//
//   shape                                     definition                     sink
//   1 qualifier (control, indexed pre-fix)    OuterB::oneSeg                 sinkOneSeg
//   2 qualifiers, class-in-class              OuterB::InnerB::deep2          sinkTwo
//   2 qualifiers, namespace + class           nsC::ClsC::nsQualMeth          sinkNsCls
//   3 qualifiers, namespace + 2 classes       nsD::OuterD::InnerD::deep3     sinkThree
//   2 qualifiers, TEMPLATED outer scope       OuterT<T>::InnerT::tdeep       sinkTmplDef
//   2 qualifiers, OPERATOR name               VecV::InnerV::operator==       sinkOpDef
//
// THE DECOY. `nsD::OuterD` also declares a `deep3()` of its own. If the definition below took the
// OUTERMOST scope (what qualifierOf() reads off the captured node's parent without the descent) it would
// key as `OuterD::deep3` and merge into that decoy — a plausible, wrong graph with sinkThree attributed to
// the wrong method. The immediate scope is the only spelling that keeps the two rows distinct.

void sinkOneSeg() {}
void sinkTwo() {}
void sinkNsCls() {}
void sinkThree() {}
void sinkTmplDef() {}
void sinkOpDef() {}
void sinkDecoy() {}

// ---- declarations (the header half) --------------------------------------------------------------

struct OuterB
{
    void oneSeg();
    struct InnerB
    {
        void deep2();
    };
};

namespace nsC
{
struct ClsC
{
    void nsQualMeth();
};
}

namespace nsD
{
struct OuterD
{
    void deep3();               // DECOY — same final name, one scope shallower
    struct InnerD
    {
        void deep3();
    };
};
}

template<class T>
struct OuterT
{
    struct InnerT
    {
        void tdeep();
    };
};

struct VecV
{
    struct InnerV
    {
        bool operator==( const InnerV& other ) const;
    };
};

// ---- out-of-line definitions ---------------------------------------------------------------------

void OuterB::oneSeg()
{
    sinkOneSeg();
}

void OuterB::InnerB::deep2()
{
    sinkTwo();
}

void nsC::ClsC::nsQualMeth()
{
    sinkNsCls();
}

void nsD::OuterD::deep3()
{
    sinkDecoy();
}

void nsD::OuterD::InnerD::deep3()
{
    sinkThree();
}

template<class T>
void OuterT<T>::InnerT::tdeep()
{
    sinkTmplDef();
}

bool VecV::InnerV::operator==( const InnerV& other ) const
{
    sinkOpDef();
    return &other == this;
}
