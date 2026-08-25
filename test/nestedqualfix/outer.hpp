#pragma once

// The Pimpl-style idiom this fixture exists to pin: a nested type is FORWARD-DECLARED inside its
// enclosing class here, and DEFINED out-of-line, qualified, elsewhere (defs.hpp). rocksdb's own tree
// does this ~29 times (BlockBasedTable::IndexReaderCommon, AutoHyperClockTable::ChainRewriteLock,
// VersionBuilder::Rep, CompressionContextCache::Rep, …) — this fixture is a minimal, controlled twin.

namespace fixture
{

/// Common base the nested implementation types derive from.
class Base
{
public:
    virtual ~Base() {}
};

/// Enclosing CLASS whose nested implementation type is defined out of line, in defs.hpp.
class Outer
{
public:
    /// Forward declaration only; the real definition is out-of-line in defs.hpp.
    class Inner;

    Outer();
};

/// Enclosing STRUCT, same shape — the struct_specifier twin of Outer/Inner above.
struct SOuter
{
    struct SInner;

    SOuter();
};

/// A DECOY: a DIFFERENT enclosing type that also forward-declares a nested type named "Inner", so a
/// query for "Inner" that resolves to the wrong scope — or that merges Decoy::Inner and Outer::Inner
/// into one symbol — is a provable wrong answer. Decoy::Inner is deliberately NEVER defined out of
/// line: only Outer::Inner gets a real body, anywhere in this fixture.
class Decoy
{
public:
    class Inner;
};

}   // namespace fixture
