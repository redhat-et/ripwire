#pragma once

// scipoverlay.h — the DATA STRUCT of the SCIP precision overlay (Wave 4 #15), split out from the
// parser (scip.h) so graph.h can consume the overlay WITHOUT pulling in the protobuf reader or its
// gitmine.h dependency. scip.h builds one of these from a decoded index; buildGraph reads it.
//
// Everything is keyed in ctxpack's OWN id space (NodeId + callee name), so buildGraph consults the
// overlay with no SCIP knowledge of its own. Both vectors are SORTED (see scip.h buildScipOverlay), so
// membership tests are deterministic and the resulting edge order is unchanged run-to-run.

#include "model.h"

#include <cstddef>
#include <cstdint>
#include <string>
#include <string_view>
#include <vector>

namespace ctx
{

// one call-site the index RESOLVED: the (fromSymbol, calleeName) key + the pinned target `to`. buildGraph
// drops the name-based guess for exactly these call-sites and substitutes this precise edge. calleeName is
// the ctxpack def NAME (matches Reference::calleeName), so the seam is a plain (id, name) lookup.
struct ScipCover { NodeId from; std::string calleeName; NodeId to; };

// one PINNED directed call edge fromSymbol → toSymbol — the derived, sorted-unique (from,to) set used at
// flatten time to stamp prov="scip" onto the matching out-edge.
struct ScipEdge { NodeId from; NodeId to; };

struct ScipOverlay
{
    std::vector<ScipCover> coveredFrom;         // sorted by (from, calleeName, to), unique per (from,calleeName,to)
    std::vector<ScipEdge>  preciseEdges;        // sorted by (from, to), unique — for the provenance stamp
    std::size_t            documentsSeen = 0;   // honesty summary / gate
    std::size_t            edgesPinned   = 0;   // == preciseEdges.size()

    // ---- staleness gauges (S5): a match RATIO surfaced as a stderr note when --scip is active. -----
    // A SCIP index built from an OLDER commit silently mis-attributes: moved DEFS exact-line-drop (safe
    // subset), but stale REF lines used to be attached to whatever current symbol spanned that stale line
    // (silent partial-staleness). These two counts turn that into an honest one-line signal —
    // `edgesPinned / refOccurrences` low, or `defsUnmatched` high ⇒ the index is likely from an older
    // commit. They are DIAGNOSTIC ONLY (never enter the graph / output), so the map stays byte-identical.
    std::size_t            refOccurrences = 0;   // SCIP REFERENCE occurrences seen in mappable documents
    std::size_t            defsUnmatched  = 0;   // SCIP DEFINITION occurrences that mapped to NO current line

    // the precise target(s) the SCIP index pinned for a (from, calleeName) call-site → the [begin,end)
    // index range into coveredFrom (empty range ⇒ not covered, keep the name-based guess). A call-site
    // may map to >1 target only if the index itself is ambiguous there (SCIP usually pins exactly one).
    std::pair<std::size_t, std::size_t> targetsOf( NodeId from, std::string_view calleeName ) const noexcept
    {
        // lower_bound on (from, calleeName).
        std::size_t lo = 0, hi = coveredFrom.size();
        while( lo < hi )
        {
            const std::size_t mid = lo + ( hi - lo ) / 2;
            const ScipCover&  c   = coveredFrom[ mid ];
            const bool less = c.from < from || ( c.from == from && std::string_view( c.calleeName ) < calleeName );
            if( less ) lo = mid + 1; else hi = mid;
        }
        std::size_t endIdx = lo;
        while( endIdx < coveredFrom.size() && coveredFrom[ endIdx ].from == from && coveredFrom[ endIdx ].calleeName == calleeName )
            ++endIdx;
        return { lo, endIdx };
    }

    // is (from, to) a precise edge? Binary search over the (from,to)-sorted derived set — the prov stamp.
    bool isPrecise( NodeId from, NodeId to ) const noexcept
    {
        std::size_t lo = 0, hi = preciseEdges.size();
        while( lo < hi )
        {
            const std::size_t mid = lo + ( hi - lo ) / 2;
            const ScipEdge&   e   = preciseEdges[ mid ];
            if( e.from < from || ( e.from == from && e.to < to ) ) lo = mid + 1;
            else                                                    hi = mid;
        }
        return lo < preciseEdges.size() && preciseEdges[ lo ].from == from && preciseEdges[ lo ].to == to;
    }

    bool empty() const noexcept { return coveredFrom.empty(); }
};

}   // namespace ctx
