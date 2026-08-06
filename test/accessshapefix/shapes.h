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
