#pragma once
#if !defined( RIPWIRE_INGEST_TU )
#error "ingest_inert.h is a section of ingest.cpp; include it only there"
#endif

namespace rw
{
namespace
{

// A live hole consumes its enclosing inert boundary. Keep walking: that quote
// may itself be inert syntax inside another quote. A nested quote inside a live
// hole becomes inert again until its own hole is entered. Language syntax stays
// in the callback; every tags and context capture uses this same walk.
enum class InertBoundary : std::uint8_t { None, Inert, Live };

template<typename BoundaryOf>
bool inInertRegion( TSNode node, BoundaryOf boundaryOf ) noexcept
{
    std::size_t liveHoles = 0;
    for( TSNode ancestor = ts_node_parent( node ); !ts_node_is_null( ancestor ); ancestor = ts_node_parent( ancestor ) )
    {
        switch( boundaryOf( ancestor, node ) )
        {
            case InertBoundary::Inert:
                if( liveHoles == 0 ) { return true; }
                --liveHoles;
                break;
            case InertBoundary::Live: ++liveHoles; break;
            case InertBoundary::None: break;
        }
    }
    return false;
}

}   // namespace
}   // namespace rw
