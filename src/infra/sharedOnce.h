#pragma once

namespace rw
{
// The value a lazily-filled slot holds (a `std::optional<T>` or a `mutable std::shared_ptr<const T>`): built by `make()` on the
// first call, reused after. For derived data that lives and dies with the object owning the slot (a per-ingest cache member, a
// per-index cache member): a replaced owner starts with an empty slot, so the value is never stale.
template< class Slot, class Make >
decltype( auto ) sharedOnce( Slot& slot, Make&& make )
{
    if( !slot )
    {
        slot = make();
    }
    return *slot;
}
}   // namespace rw
