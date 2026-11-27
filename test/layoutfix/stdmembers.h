#pragma once

// stdmembers.h — std:: members, an in-repo alias of an in-repo template, a single base class and 1-byte bitfields: the
// shapes of ripwire's own Reference / Binding / Symbol (LAYOUT-SIZED, 2026-11-11 memory audit). test/layoutcheck.sh
// COMPILES this header and compares every size and offset --layout prints against sizeof/offsetof, so no number here
// is pinned: std::string is 24 B in libc++ and 32 B in libstdc++, and the gate holds on both.

#include "textalias.h"

#include <array>
#include <cstdint>
#include <functional>
#include <memory>
#include <optional>
#include <span>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

namespace layoutfix
{

inline constexpr std::size_t kTriple = 3;

struct StdMembersCase
{
    char                               lead = 0;
    std::string                        s;
    std::string_view                   v;
    std::vector<int>                   vec;
    std::unique_ptr<int>               up;
    std::shared_ptr<int>               sp;
    std::optional<int>                 oi;
    std::optional<double>              od;
    std::array<std::uint16_t, kTriple> arr {};
    std::span<const int>               view;
    std::pair<char, double>            pr;
    const std::vector<int*>*           pv = nullptr;
    char                               tail = 0;
};

// RefColdFields' shape: one owning pointer behind member functions, a member template and a private section.
class ColdBase
{
public:
    ColdBase() noexcept = default;
    template <class T> void set( T&& v ) { cold_ = std::make_unique<int>( int( v ) ); }
    bool has() const noexcept { return cold_ != nullptr; }

private:
    std::unique_ptr<int> cold_;
};

// Reference's shape: a base subobject at offset 0, then scalars, an alias-of-template handle, and a std::string.
struct DerivedRowCase : ColdBase
{
    std::uint32_t id   = 0;
    TextId        name;
    bool          flag = false;
    std::string   text;
};

// Symbol's flag bytes: bitfields of 1-byte types, which every ABI packs the same way (fill a byte, then the next).
struct ByteBitsCase
{
    std::uint16_t n = 0;
    std::uint8_t  a : 1 = 0;
    std::uint8_t  b : 3 = 0;
    std::uint8_t  c : 4 = 0;
    std::uint8_t  d : 4 = 0;
    bool          e : 1 = false;
    std::uint32_t x = 0;
};

// What must stay UNSIZED, by member: a std:: type outside the table, and std::vector<bool> (40 B in libstdc++, 24 B in
// libc++ — a specialisation, not the vector row).
struct UnlistedStdCase
{
    int                   first = 0;
    std::function<void()> cb;
    std::vector<bool>     bits;
    int                   after = 0;
};

// A base with tail padding: Itanium may place a derived member inside it (when the base is not POD), MSVC never does.
struct TailPadBase
{
    std::uint32_t a = 0;
    char          b = 0;
};

struct TailPadDerivedCase : TailPadBase
{
    char c = 0;
};

}   // namespace layoutfix
