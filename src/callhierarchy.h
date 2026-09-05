#pragma once
// callhierarchy.h — the ONE 1-hop call-hierarchy computation, shared by the CLI's --callers/--callees and
// by the MCP twins find_referencing_symbols / find_symbol.
//
// WHY THIS FILE EXISTS (capture-audit 2026-09-04, H14 + M13). The two surfaces answered the same question
// from two different pieces of code. The CLI resolved EVERY definition of the name
// (resolveAllByNameQualified), unioned their neighbours, sorted them tier-then-path, partitioned them into
// tested/untested and paged the result — so its root carried `defs= count= hop_tested= hop_untested=` and
// its rows carried `tested="1"`. The MCP twin walked the CSR from ONE resolved def (resolveFocus) in raw
// node order and emitted `{name,kind,file,line,handle}` and nothing else: no defs (so a caller could not
// tell that the name it asked about has three definitions and it got the union of one), no test-reach lens
// (the exact lens --test-gate is built on), and no page 2 at all.
//
// That is the clone-seam class this repo has closed a dozen times: two emitters of one computation drift on
// what they disclose, and each passes its own tests in isolation. The computation moves here; both surfaces
// call it and differ only in how they RENDER. The gate is test/mcpattrparitycheck.sh (attribute-name-set
// diff, CLI root ⊆ MCP keys and per-row likewise) plus test/mcpclidiffcheck.sh's existing lenses.
//
// Deliberately NOT here: the rendering, the refusal wording, and the display cap policy. Those are
// surface-specific by contract (the CLI has a legend, the MCP arm speaks JSON-RPC errors), and folding them
// in would trade one drift for another.

#include "filter.h"    // pathTierIndexOver / compareTierThenPath — the tier-then-path row order both surfaces serve
#include "graph.h"     // resolveAllByNameQualified, the CSR, testSymbolForwardReach / countTestedIn / isTestedByReach
#include "model.h"

#include <string>
#include <string_view>
#include <utility>
#include <vector>

namespace rw
{

// A6: the 1-hop tested/untested partition, bundled into one call so a caller pays ONE statement instead of
// separately naming testReach / tested / untested / attr. The counting loop itself lives in
// graph.h::countTestedIn, shared with --impact. (Hoisted here from verbs_navigate.h, unchanged, so the MCP
// twins can serve the same partition instead of omitting the lens.)
struct HopTestedPartition
{
    std::vector<char> testReach;
    std::size_t       tested;
    std::size_t       untested;
    std::string       xmlAttr;   // " hop_tested=\"N\" hop_untested=\"M\""
};

inline HopTestedPartition computeHopTestedPartition( const IngestResult& ing, const Graph& g, const std::vector<NodeId>& rows )
{
    std::vector<char> testReach = testSymbolForwardReach( ing, g );
    const std::size_t tested    = countTestedIn( ing, testReach, rows );
    const std::size_t untested  = rows.size() - tested;
    std::string       attr      = " hop_tested=\"" + std::to_string( tested ) + "\" hop_untested=\"" + std::to_string( untested ) + "\"";
    return { std::move( testReach ), tested, untested, std::move( attr ) };
}

// The rows one 1-hop question yields, with the two counts that qualify them.
//   matches — every DEFINITION the selector resolved to. Its size is the `defs=` disclosure: the rows below
//             are the UNION of all of their neighbours, and a reader who thought they were one symbol's
//             would be wrong by however many definitions the name has.
//   rows    — the deduped neighbour set, in the served order (tier before path before line before name).
// `bodylessDefs` is meaningful for the callee direction only (a declaration with no body has no callees),
// and is counted here rather than at each emitter so the two cannot disagree about what "bodyless" means.
struct CallHierarchyRows
{
    std::vector<NodeId> matches;
    std::vector<NodeId> rows;
    std::size_t         bodylessDefs = 0;
};

inline CallHierarchyRows callHierarchyRows( const IngestResult& ing, const Graph& g, std::string_view selector, bool wantCallers )
{
    CallHierarchyRows out;
    // X9(b): "file:name" disambiguates here (the same rule --around/--lego/--edit-check use through
    // resolveFocus) — a same-named symbol living in more than one file must be pickable on either surface.
    out.matches = resolveAllByNameQualified( ing, selector );
    if( out.matches.empty() )
    {
        return out;   // the caller owns the refusal: a CLI stderr line, or a JSON-RPC -32602
    }

    std::vector<char> seen( ing.symbols.size(), 0 );
    for( const NodeId x : out.matches )
    {
        if( wantCallers )
        {
            const auto* ro = g.inEdges.rowOffsets();
            const auto* ci = g.inEdges.colIndices();
            for( std::uint32_t k = ro[x]; k < ro[x + 1]; ++k )
            {
                if( NodeId c = ci[k]; c < seen.size() && !seen[c] ) { seen[c] = 1;  out.rows.push_back( c ); }
            }
        }
        else
        {
            for( std::uint32_t k = g.outOff[x]; k < g.outOff[x + 1]; ++k )
            {
                if( NodeId c = g.outTargets[k]; c < seen.size() && !seen[c] ) { seen[c] = 1;  out.rows.push_back( c ); }
            }
            // Bodyless definitions (a declaration whose signature end IS its end): they have no callees, so
            // an empty row set is explained rather than mysterious.
            if( const Symbol& sym = ing.symbols[x]; sym.sigEndByte == sym.endByte )
            {
                ++out.bodylessDefs;
            }
        }
    }

    // LB-G (r10 §5): TIER before path — filter.h states the key once and --uses shares it. Plain path order
    // put 171 `tests/` rows ahead of anything useful on django's `--callers=bulk_create`.
    const std::vector<std::uint8_t> tierOfFile = pathTierIndexOver( ing, out.rows, [ & ]( NodeId r ) { return ing.symbols[r].fileId; } );
    std::sort( out.rows.begin(), out.rows.end(), [ & ]( NodeId a, NodeId b )
    {
        const Symbol& sa = ing.symbols[a];
        const Symbol& sb = ing.symbols[b];
        if( const int c = compareTierThenPath( ing, tierOfFile, sa.fileId, sb.fileId ); c != 0 )
        {
            return c < 0;
        }
        return sa.line != sb.line ? sa.line < sb.line : sa.name < sb.name;
    } );
    return out;
}

}   // namespace rw
