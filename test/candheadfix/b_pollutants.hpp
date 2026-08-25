#pragma once

// Seven overloads of a free function named Frobnicator — the fixture form of rocksdb's seven
// Slice-named rows in java/src/main/java/org/rocksdb/Slice.java. Each is UNSCOPED (a free function at
// FILE scope, deliberately NOT inside fixture:: or any other namespace — a namespace wrapper turns out
// to ALSO give a symbol a written scope for this scorer's length-normalization purposes, which would
// erase the very score gap this fixture exists to reproduce), so the whole-name BM25 scorer's length-
// normalization term treats each as a one-token "document" and scores it HIGHER than a_gold.hpp's class
// Frobnicator and its constructor, both of which carry a written scope ("Frobnicator", from the class
// that owns them) and therefore count as two-token documents. Seven is deliberate: one more than
// kPackTaskBodyCandidates = 6, so before the candidate-head-bound fix these seven rows fill the WHOLE
// pre-restriction top-6 and the gold in a_gold.hpp is never even a candidate.
//
// See a_gold.hpp's header comment for why this fixture uses "Frobnicator" rather than the house
// "Widget" placeholder: an UNSCOPED "Widget" here collided with this repo's own pre-existing, unrelated
// "Widget" fixtures on --quality-delta's bare-name api-surface key.

inline void Frobnicator() { }
inline void Frobnicator( int ) { }
inline void Frobnicator( int, int ) { }
inline void Frobnicator( int, int, int ) { }
inline void Frobnicator( long ) { }
inline void Frobnicator( long, long ) { }
inline void Frobnicator( double ) { }
