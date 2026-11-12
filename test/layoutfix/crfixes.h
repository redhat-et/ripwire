#pragma once

// crfixes.h — the six #618 CodeRabbit shapes (B44, 2026-11-12). test/layoutcheck.sh arm 18 compiles this header and compares
// what --layout prints against sizeof/offsetof for the modelled cases, and expects a refusal for the rest.

#include <array>
#include <cstddef>
#include <cstdint>

namespace layoutfix
{

// a ternary default initializer is not a bitfield width: c is a whole byte, d opens the next one
struct TernaryInitCase
{
    std::uint8_t a : 3;
    std::uint8_t b : 2;
    std::uint8_t c = true ? 2 : 1;
    std::uint8_t d : 4;
};

// an aggregate whose only content is an empty base is empty: the empty-base optimisation puts a at 0
struct CrEmptyBase
{
};
struct CrEmptyMid : CrEmptyBase
{
};
struct EmptyChainCase : CrEmptyMid
{
    int a;
};

// the first member has the empty base's own type: e cannot share the base's address (it sits at 1), so the model refuses
struct EboClashCase : CrEmptyBase
{
    CrEmptyBase e;
    int         x;
};

// a template parameter shadows a same-named file constant: the extent, the std::array bound and the width are the template
// argument's, never 16 / 2
inline constexpr std::size_t N = 16;
inline constexpr int         W = 2;
template <std::size_t N>
struct CrTplBuf
{
    char data[N];
};
template <std::size_t N>
struct CrTplArr
{
    std::array<char, N> data;
};
template <int W>
struct CrTplBits
{
    std::uint8_t v : W;
};
struct TplExtentCase
{
    CrTplBuf<64> big;
    int          tail;
};
struct TplArrayCase
{
    CrTplArr<64> big;
    int          tail;
};
struct TplWidthCase
{
    CrTplBits<3> b;
    int          tail;
};

// a comment line above a #define between two members: the directive is still not glued onto the next field
struct CommentDefineCase
{
    int a;
    // flags
#define CDC_FLAG 0x1
    unsigned int sync_dirty;
};

}   // namespace layoutfix
