#pragma once
#if !defined( RIPWIRE_INGEST_TU )
#error "ingest_inert.h is a section of ingest.cpp; include it only there"
#endif

namespace rw
{
namespace
{

// The nearest boundary wins: a live hole re-enters an inert quote, and a nested
// quote inside that hole becomes inert again. Language syntax stays in the
// boundary callback; this walk is shared by every tags and context capture.
enum class InertBoundary : std::uint8_t { None, Inert, Live };

template<typename BoundaryOf>
bool inInertRegion( TSNode node, BoundaryOf boundaryOf ) noexcept
{
    for( TSNode ancestor = ts_node_parent( node ); !ts_node_is_null( ancestor ); ancestor = ts_node_parent( ancestor ) )
    {
        switch( boundaryOf( ancestor, node ) )
        {
            case InertBoundary::Inert: return true;
            case InertBoundary::Live:  return false;
            case InertBoundary::None:  break;
        }
    }
    return false;
}

}   // namespace
}   // namespace rw
