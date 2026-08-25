#pragma once
#include "outer.hpp"

// THE SHAPE THIS GATE PINS: out-of-line, QUALIFIED nested class/struct definitions. Before the
// candhead-ugrep lane's fix neither of the two classes below minted a symbol at all — their own
// name (`class_specifier`/`struct_specifier` `name:` field) is a qualified_identifier, not the bare
// type_identifier the upstream tags patterns require, so extraction dropped them silently: no symbol,
// no --skipped row, no floor. Their MEMBERS (the constructors) already extracted fine and already
// scoped correctly to "Outer::Inner" / "SOuter::SInner" — this fixture's own invariance control below
// pins that unchanged half. Only the class/struct's OWN bare name ("Inner" / "SInner") resolved to
// nothing, because nothing had ever minted it as a symbol.

namespace fixture
{

/// THE GOLD: an out-of-line, qualified nested CLASS definition. Its own bare name ("Inner") must
/// become a symbol findable by --for, independent of the qualifier it was written with — this is the
/// extraction gap named N11/N12 (ugrep's `class BufferedInput::dos_streambuf : public std::streambuf
/// { ... }`, reflex/input.h).
class Outer::Inner : public Base
{
public:
    explicit Inner( int code )
        : code_( code )
    {
    }
    int code_ = 0;
};

/// The struct_specifier twin of the gold above.
struct SOuter::SInner : public Base
{
    explicit SInner( int code )
        : code_( code )
    {
    }
    int code_ = 0;
};

}   // namespace fixture
