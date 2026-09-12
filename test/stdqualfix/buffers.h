// test/stdqualfix — the std::-QUALIFIED call fixture (test/stdqualcheck.sh). File 1: the LONE decoys.
//
// Every class below owns the ONLY definition of its method's name in this corpus, and every one of those
// names is also a standard library function. That is the whole defect this fixture exists for: a call
// written `std::move( x )` found no def keyed `std::move`, fell to the bare-name spray, and bound the one
// in-repo `move` it found — a member of an unrelated class — at full confidence, with no amb= and no
// prov="split". A lone same-named def is the dangerous case precisely because nothing splits it.
//
// Every expected count in the gate is a LITERAL read off these files by hand; each file's header says which
// arm it feeds. Keep the bodies call-free: an incidental call here would move the header literals.

#pragma once

namespace store
{

// the ONLY `move` in the corpus — std::move sites must never bind it; `buf.move()` must.
class Buf
{
public:
    Buf&& move() { return static_cast<Buf&&>( *this ); }
    int bytes = 0;
};

// the ONLY `swap` in the corpus — std::swap sites must never bind it; `a.swap( b )` must.
class Slot
{
public:
    void swap( Slot& other ) { int held = value; value = other.value; other.value = held; }
    int value = 0;
};

// the ONLY `unreachable` — std::unreachable() (C++23, <utility>) is NOT in the Phase-5 veto table, so the
// ObjC++ arm (bridge.mm) can show what the guard cannot see there.
class Cursor
{
public:
    void unreachable() { position = -1; }
    int position = 0;
};

}   // namespace store
