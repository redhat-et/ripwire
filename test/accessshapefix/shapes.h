// accessshapefix/shapes.h — fixtures for test/accessshapecheck.sh (src/accessshape.h's Phase A).
//
// LinkedNode is the SELF-REF chase-target case: `next` is declared ONCE, its declared type IS the
// enclosing struct plus a pointer marker, and walks.cpp's four discriminating-trap functions advance
// through it. It must come back `<f n="next" chase="1" ... shape_conf="self-ref">`.
//
// StepperA/StepperB exist ONLY to make the field name `step` AMBIGUOUS (owned by 2 modeled aggregates —
// exactly fieldaffinityfix's own LeftBox/RightBox `slot` pattern). walks.cpp chase-advances through
// StepperA::step, which WOULD earn a chase disclosure if `step` were unique — but because StepperB also
// declares a field named `step`, fieldaffinity.h's own FieldOwners ambiguity ("refuse rather than guess",
// the same convention `amb_skipped=` already enforces for member-access attribution) must refuse it here
// too: `as_stem_ambiguous="1"` in the header, and NO `<f n="step">` row anywhere may carry a chase
// attribute. StepperB is otherwise untouched (no row of its own; its only purpose is to poison the name).
#pragma once

#include <cstdint>

struct LinkedNode
{
    std::uint64_t payload;
    LinkedNode*   next;
};

struct StepperA
{
    std::uint64_t val;
    StepperA*     step;
};

struct StepperB
{
    std::uint64_t val2;
    StepperB*     step;   // same field NAME as StepperA::step — the deliberate ambiguity
};

// Ledger is the NON-POINTER SOLE-OWNER trap: it is the ONLY modeled aggregate declaring a field named
// `link`, but its `link` is a plain int — a raw-pointer chase advance (`p = p->link`) provably cannot
// target it, so walks.cpp's ledgerWalk (which chases `link` on a FORWARD-DECLARED type) must be refused
// (`as_stem_nonptr="1"`), never attributed here. Before accessshape::chaseTypeCanPoint existed this was a
// live silent-misattribution bug: Ledger::link came back `chase="1" loops="1"` from a loop that never
// touches Ledger at all.
struct Ledger
{
    int link;    // int, not a pointer — cannot be a chase target
    int total;
};
