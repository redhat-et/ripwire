#pragma once

// Seven overloads of a free function named Widget — the fixture form of rocksdb's seven Slice-named
// rows in java/src/main/java/org/rocksdb/Slice.java. Each is UNSCOPED (a free function at FILE scope,
// deliberately NOT inside fixture:: or any other namespace — a namespace wrapper turns out to ALSO
// give a symbol a written scope for this scorer's length-normalization purposes, which would erase
// the very score gap this fixture exists to reproduce), so the whole-name BM25 scorer's length-
// normalization term treats each as a one-token "document" and scores it HIGHER than a_gold.hpp's
// class Widget and its constructor, both of which carry a written scope ("Widget", from the class
// that owns them) and therefore count as two-token documents. Seven is deliberate: one more than
// kPackTaskBodyCandidates = 6, so before the candidate-head-bound fix these seven rows fill the WHOLE
// pre-restriction top-6 and the gold in a_gold.hpp is never even a candidate.

inline void Widget() { }
inline void Widget( int ) { }
inline void Widget( int, int ) { }
inline void Widget( int, int, int ) { }
inline void Widget( long ) { }
inline void Widget( long, long ) { }
inline void Widget( double ) { }
