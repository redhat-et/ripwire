#pragma once

// textid.h — an in-repo class TEMPLATE whose layout does not depend on its argument (the InternedTextOf<Domain> shape:
// a 4 B id behind a typed handle), plus a same-named `string` stub. The stub is the trap: an unrelated `class string {}`
// in the index used to size every std::string member at 1 B (LAYOUT-SIZED, 2026-11-11).

#include <cstdint>

namespace layoutfix
{

template <class Domain> class TextIdOf
{
public:
    TextIdOf() noexcept = default;
    explicit TextIdOf( std::uint32_t id ) : id_( id ) {}
    template <class Other> bool sameAs( const Other& o ) const { return id_ == o.id(); }
    std::uint32_t id() const noexcept { return id_; }

private:
    std::uint32_t id_ = 0;
};

namespace stub
{
class string
{
};
}   // namespace stub

}   // namespace layoutfix
