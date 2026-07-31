#pragma once

// docdriftfix/code.h — the corpus NOTES.md makes its claims about. LINE NUMBERS HERE ARE LOAD-BEARING:
// NOTES.md anchors at specific lines and test/docdriftcheck.sh asserts on the verdicts, so inserting or
// deleting a line above stableHelper() changes what the gate measures. Edit the doc and the gate together.

namespace ddfix
{

inline constexpr int kHoldingLimit = 7;
inline constexpr int kDriftedLimit = 15;

inline constexpr int kHoldingTable[ 4 ]  = { 1, 2, 3, 4 };
inline constexpr int kDriftedTable[ 18 ] = { 0 };

// stableHelper's own doc comment — NOTES.md anchors INSIDE the body just below, which must read as holding.
inline int stableHelper( int value )
{
    return value + kHoldingLimit;
}

inline int movedHelper( int value )
{
    return value * 2;
}

}   // namespace ddfix
