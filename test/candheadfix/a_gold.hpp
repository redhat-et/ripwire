#pragma once

// Sorts FIRST by path, so this file's class Frobnicator claims the route anchor: NameAnchor::fileId is
// "the first BODY-CARRYING definition of the name in NodeId order" (the anchor-body round), and
// NodeId order is crawl/path order. This is the fixture form of rocksdb's own shape: --for="Slice"
// correctly anchors to include/rocksdb/slice.h, yet its gold sits at rank 8, one past
// kPackTaskBodyCandidates = 6, behind seven higher-scoring Slice.java rows in an unrelated file/
// language (java/src/main/java/org/rocksdb/Slice.java). b_pollutants.hpp below is that fixture twin:
// seven overloads of a free function Frobnicator(), each scoring HIGHER than this class (BM25's
// length-normalization term: a symbol WITH a written scope, like this class's own constructor, counts
// as a two-token "document" against the whole-name scorer; an unscoped free function scores as one
// token and wins the length penalty — measured, not assumed: see the gate script's header comment).
//
// NAMED "Frobnicator" rather than the house "Widget"/"Gadget"/"Sprocket" convention deliberately: this
// repo's OWN test suite already reuses "Widget" as a bare (scope-less), cross-language placeholder name
// in a dozen unrelated fixtures (callformfix, h4fixtures, csharpcondfix, impactimportfix, …), and
// --quality-delta's api-surface check keys a scope-less free function's canonical id to its BARE NAME
// (§P13.4 in quality.h — the documented "a 4-param Python add shares its key with a 2-param C add"
// collision). An UNSCOPED "Widget" free function here collided with those pre-existing symbols and
// produced a phantom "contract-change" finding having nothing to do with this fix.

namespace fixture
{

/// THE GOLD: the anchor correctly resolves here, but before the candidate-head-bound fix the seven
/// higher-scoring pollutants in b_pollutants.hpp fill the whole top-6 body-candidate head before
/// restrictBodiesToRouteAnchor ever narrows to this file, so the gold is never even a candidate.
class Frobnicator
{
public:
    Frobnicator() { x_ = 1; }
    int x_ = 0;
};

/// UNIQUE-DEFINITION INVARIANCE control: nothing else in this fixture is named Gadget, so no candidate-
/// head crowding can reach it — its anchor and its served body must be byte-stable before and after.
class Gadget
{
public:
    Gadget() {}
};

}   // namespace fixture
