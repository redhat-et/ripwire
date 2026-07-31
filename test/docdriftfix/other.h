#pragma once

// docdriftfix/other.h — a SECOND file, so NOTES.md can name a symbol that lives here while anchoring a line
// number in code.h. That is the "named-elsewhere" case: the doc is pointing at a call site, not a
// definition, and the verb must decline to call it line-moved rather than blaming the wrong symbol.

namespace ddfix
{

inline int otherEntry( int seed )
{
    return seed - 1;
}

}   // namespace ddfix
