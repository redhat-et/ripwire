#pragma once

// ownersview.h — §P6.4: the --owners uniform-collapse shared by the CLI (main.cpp) and MCP (mcpverbs.h)
// `owners` verb, so both serializers fold authors=1 files into one <uniform/> row identically. A separate
// header (not folded into gitmine.h, which owns the raw git-mining core) so this presentation-layer logic
// stays a one-file diff away from either caller.

#include "gitmine.h" // FileOwnership

#include <cstddef>
#include <vector>

namespace rw
{

// authors==1 deterministically implies bf=1 AND share=1.00 — a sole author's weighted-commit share
// divided by itself is exactly 1.0 (no float slop from the recency decay) — so this predicate exactly
// identifies the modal "758 identical rows" shape a real repo's --owners output hit (75KB, zero
// information per row beyond "one person"). Kept out of the callers' own bodies so this loop doesn't add
// to their complexity — same reasoning as serialize.h's collapseOverloadRows (§P6.3).
inline std::size_t countUniformOwnership( const std::vector<FileOwnership>& ownerships, int cap )
{
    std::size_t n = 0;
    for( int i = 0; i < cap && i < int( ownerships.size() ); ++i )
    {
        if( !ownerships[i].authors.empty() && ownerships[i].uniqueAuthors == 1 )
        {
            ++n;
        }
    }
    return n;
}

// The ownership rows to print INDIVIDUALLY: every file under `detail`, otherwise every file EXCEPT the
// ones countUniformOwnership() above already counted (those fold into a single <uniform/> row instead).
// Pre-filtered here so a caller's print loop stays a plain, branch-free iteration.
inline std::vector<std::size_t> ownershipRowsToPrint( const std::vector<FileOwnership>& ownerships, int cap, bool detail )
{
    std::vector<std::size_t> rows;
    for( int i = 0; i < cap && i < int( ownerships.size() ); ++i )
    {
        if( !ownerships[i].authors.empty() && ( detail || ownerships[i].uniqueAuthors != 1 ) )
        {
            rows.push_back( std::size_t( i ) );
        }
    }
    return rows;
}

} // namespace rw
