#pragma once

// degradedscan.h — THE ONE degraded-parse text scan behind every "that name resolved to nothing" refusal.
//
// WHY THIS FILE EXISTS (degradedhintcheck, 2026-08-30). The health pass records which indexed files'
// parses hold ERROR/MISSING nodes, and --skipped discloses them — but a refusal never routed the reader
// there, so a symbol sitting in a shredded file (the looksObjC misroute: src/ingest_model.h, err=190)
// answered a bare "symbol not found" and sent an agent hunting for a rename that never happened. The fix
// is a scan of the BYTES of the parse-degraded files for the missing name as a WHOLE WORD — precise by
// construction: an ordinary typo occurs in no file, so it never fires on misspellings (this repo carries
// 65 deliberately-degraded fixtures; a blanket "there are degraded files" note would ride on every
// refusal).
//
// The scan landed inside the CLI's selectorrefuse.h first; the MCP arms refuse in their own vocabulary
// (mcprefusal.h) and needed the SAME facts under different wording — and a byte-scan that exists twice is
// two budgets, two boundary predicates and two behaviours. So the scan lives here, returning FACTS, and
// each surface words them: selectorrefuse.h's degradedParseClause (CLI, parenthetical, --skipped retry)
// and mcprefusal.h's degradedParseNote (MCP, sentence, grep-verb retry). Same split as didyoumean.h, the
// other enrichment both refusal surfaces already share.
//
// Cold path only (the command is already failing), and bounded: at most kDegradedScanFiles files and
// kDegradedScanBytes total are read; readWhole itself refuses oversized files. A budget hit or unreadable
// file just means no hit — an ABSENT note claims nothing, same as the near-miss suggester. First matching
// file only: --skipped is the itemization, this is the routing.

#include "model.h"
#include "darkflags.h"      // readWhole / wholeWordAt — the shared lexical helpers (no second copy)

#include <cstddef>
#include <cstdio>
#include <string>
#include <string_view>

namespace rw
{

inline constexpr std::size_t kDegradedScanFiles = 32;
inline constexpr std::size_t kDegradedScanBytes = 8u << 20;

// The facts a wording surface needs, and nothing pre-worded: WHICH indexed file textually holds the name,
// and how much of that file's parse is error bytes. errRatio is formatted ONCE ("%.3f") so the two
// surfaces can never print different digits for the same file.
struct DegradedTextHit
{
    bool        found     = false;
    std::size_t fileIndex = 0;         // into ing.files, valid only when found
    char        errRatio[ 16 ] = {};   // "%.3f"; <= 1.000 by construction (errBytes <= fileBytes)
};

inline DegradedTextHit degradedTextHit( const IngestResult& ing, std::string_view name )
{
    if( name.empty() || name.size() > 256 )
    {
        return {};
    }
    std::size_t scannedFiles = 0, scannedBytes = 0;
    std::string bytes;
    for( std::size_t fileIndex = 0; fileIndex < ing.files.size() && fileIndex < ing.fileHealth.size(); ++fileIndex )
    {
        if( !fileParseDegraded( ing, fileIndex ) )
        {
            continue;                                    // clean, or the ingest never parsed it — not this scan's claim
        }
        const FileHealth& h = ing.fileHealth[ fileIndex ];
        if( ++scannedFiles > kDegradedScanFiles || ( scannedBytes += h.fileBytes ) > kDegradedScanBytes )
        {
            return {};                                   // budget — absent claims nothing
        }
        if( !darkflags::readWhole( diskPath( ing, std::uint32_t( fileIndex ) ), bytes ) )
        {
            continue;
        }
        const std::string_view hay( bytes );
        for( std::size_t at = hay.find( name ); at != std::string_view::npos; at = hay.find( name, at + 1 ) )
        {
            if( darkflags::wholeWordAt( hay, at, name.size() ) )
            {
                DegradedTextHit hit;
                hit.found     = true;
                hit.fileIndex = fileIndex;
                std::snprintf( hit.errRatio, sizeof( hit.errRatio ), "%.3f", double( h.errBytes ) / double( h.fileBytes ) );
                return hit;
            }
        }
    }
    return {};
}

}   // namespace rw
