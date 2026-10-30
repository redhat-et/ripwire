#pragma once

// grepcarrier.h — what a grep hit's CARRIER holds and who reads it (L4, train 28).
//
// WHY. A literal often sits in a variable or constant rather than a function: `DRIVER = get_environ( "TEXTUAL_DRIVER" )`,
// or a C initialiser `cmd_split_window_entry = { .name = "split-window", … .exec = cmd_split_window_exec }`. The grep
// <enc> row then names that variable with callers="0" — a call count on a thing nobody calls — and the answer stops one
// hop short of what the reader wanted: the place the value is READ (app.py's `constants.DRIVER`) or the FUNCTION the
// initialiser stores (`.exec = cmd_split_window_exec`). Both facts are already in the index; this header reads them.
//
// THE RULE (labels from the index, never from text):
//   * a carrier is an enclosing definition of kind Var (a variable, constant or initialiser) — the parser's kind;
//   * reads= / reads_at= are the uses verb's role="read" sites for the carrier's NAME (matched by name, the uses verb's own
//     unit), counted only where that verb can see reads at all: an ingest that captured value uses and a language whose
//     reads reach the use-site table (countfloor.h valueUsesArmedFor), never a C-family header, whose readers are `.c`
//     files the uses verb never reads (the countFloorNext rule), and only on a page whose TOP hit sits in such a carrier
//     (grepCarriersWantReads — the CLI pays a second ingest for them). Anywhere else the attributes are ABSENT: unknown, never 0;
//   * vals= are the function values the carrier itself stores: value references (valuerefindex.h) made inside the
//     carrier's definition whose name resolves to an indexed function, in source order, as slot=fn@line: the slot key as
//     the value index normalised it, and the line of the ONE definition the name resolves to (@path:line when that
//     definition is in another file) — the hop the reader wants next. A name resolving to several definitions keeps no
//     @: which one the slot holds is not something the index decided.
// The CLI (verbs_grep.h) and the MCP grep twin (mcpverbs.h grepEnclosingJson) both call grepCarriers, so the two
// surfaces cannot disagree about a row.

#include "countfloor.h"      // valueUsesArmedFor — where reads reach the use-site table
#include "filter.h"          // pathTierIndexOver, compareTierThenPath — the uses verb's base row order
#include "model.h"
#include "nextverb.h"        // nextFlag — the root next= spelling
#include "sarif.h"           // rootRelativeUri — the root-relative spelling every grep path takes
#include "search.h"          // GrepEncRow — the rows this decorates
#include "valuerefindex.h"   // ValueRefIndex — madeIn / targetsOf, the stored function values
#include "infra/sortutil.h"  // sortutil::svLess — the byte order every string_view search here uses
#include "infra/Diagnostics.h"

#include <algorithm>
#include <cstddef>
#include <cstdint>
#include <span>
#include <string>
#include <string_view>
#include <vector>

namespace rw
{

inline constexpr std::size_t kGrepCarrierShown = 3;   // reads_at= sites and vals= entries printed per row (reads=/vals_total= count all)

struct GrepCarrierSite
{
    std::string   path;       // the READS ingest's own file spelling (the CLI's may be a second, rich ingest of the same root)
    std::uint32_t line = 0;
};

struct GrepCarrierVal
{
    std::string   slot;       // the normalised key without its leading '.', "" for a plain assignment
    std::string   fn;         // the function name as written
    std::string   path;       // the definition's file when it is not the carrier's own, else ""
    std::uint32_t line = 0;   // the definition's line; 0 = the name resolves to several definitions (no @)
};

struct GrepCarrier
{
    bool                         isCarrier  = false;   // every definition on the row is a Var
    bool                         readsKnown = false;   // reads= is a count the uses verb could make (see the rule above)
    std::uint32_t                reads      = 0;       // role="read" sites spelled like the carrier's name
    std::vector<GrepCarrierSite> at;                   // the first kGrepCarrierShown of them, in tier, path, line order (not the order the uses verb prints)
    std::vector<GrepCarrierVal>  vals;                 // the first kGrepCarrierShown stored function values
    std::uint32_t                valsTotal  = 0;       // every stored function value on the row
    std::string                  defPath;              // A3: the row's ONE carrier definition's file ("" when the row groups several)
    std::uint32_t                defLine    = 0;       // ... and its line; p= anchors a vals= @line that names no path
};

// Does the uses verb see reads of a definition of `s`'s language at that path? (countfloor.h countFloorNext's rule.)
inline bool grepCarrierReadsVisible( const IngestResult& ing, const Symbol& s ) noexcept
{
    const std::string_view path = s.fileId < ing.files.size() ? std::string_view( ing.files[ s.fileId ] ) : std::string_view();
    return valueUsesArmedFor( s.lang ) && !path.ends_with( ".h" );
}

inline bool isGrepCarrierRow( const IngestResult& ing, const GrepEncRow& row ) noexcept
{
    return !row.ids.empty() && std::ranges::all_of( row.ids, [ & ]( NodeId id ) { return id < ing.symbols.size() && ing.symbols[id].kind == SymKind::Var; } );
}

// The row holding the TOP hit's enclosing definition — the row the root next= is decided on — or rows.size() when the
// top hit has no enclosing definition or no row holds it.
inline std::size_t grepTopHitRow( std::span<const GrepHit> hits, std::span<const GrepEncRow> rows ) noexcept
{
    if( hits.empty() || hits[0].enclosingId == kNoNode )
    {
        return rows.size();
    }
    const auto row = std::ranges::find_if( rows, [ & ]( const GrepEncRow& r ) { return std::ranges::find( r.ids, hits[0].enclosingId ) != r.ids.end(); } );
    return std::size_t( row - rows.begin() );
}

// Does this page count reads at all? Only when the TOP hit's row is a carrier the uses verb reads for (a language whose
// reads reach the use-site table, not a header): that row decides the root next=, so it is the one whose reads are worth
// a rich ingest (the CLI's second ingest is paid here and only here). Once counted, every readable carrier row on the
// page gets reads=; on a page that does not count, a lower carrier keeps its floor_next= (the uses verb on its name) as
// the clue. The CLI and the MCP twin both ask this, so the two surfaces count reads on the same pages.
inline bool grepCarriersWantReads( const IngestResult& ing, std::span<const GrepHit> hits, std::span<const GrepEncRow> rows ) noexcept
{
    const std::size_t top = grepTopHitRow( hits, rows );
    return top < rows.size() && isGrepCarrierRow( ing, rows[top] ) && grepCarrierReadsVisible( ing, ing.symbols[ rows[top].ids.front() ] );
}

namespace grepcarrier
{

// The value-reference sites that replace a read row in the uses verb (valuerefindex.h UsesValueFilter): a Value
// reference spelled like `names[k]` that resolves to a function. Built only when such a reference exists, so the
// common case (a variable name no function shares) never builds the reads ingest's value index.
inline std::vector<std::uint64_t> valueSitesOf( const IngestResult& rd, std::span<const std::string_view> names )
{
    std::vector<std::uint32_t> candidates;
    for( std::uint32_t i = 0; i < rd.references.size(); ++i )
    {
        const Reference& r = rd.references[i];
        if( r.role == RefRole::Value && !r.fieldName.starts_with( '@' ) && std::ranges::binary_search( names, std::string_view( r.calleeName ), sortutil::svLess ) )
        {
            candidates.push_back( i );
        }
    }
    std::vector<std::uint64_t> sites;
    if( candidates.empty() )
    {
        return sites;
    }
    const ValueRefIndex vri( rd );
    for( const std::uint32_t i : candidates )
    {
        if( !vri.targetsOf( i ).empty() )
        {
            sites.push_back( ( std::uint64_t( rd.references[i].fileId ) << 32 ) | rd.references[i].startByte );
        }
    }
    std::ranges::sort( sites );
    return sites;
}

}   // namespace grepcarrier

namespace grepcarrier
{

// One stored function value as vals= prints it: the slot key without its leading '.', the name as written, and the one
// definition it resolves to (none when it resolves to several). `targets` is vri.targetsOf of that reference.
inline GrepCarrierVal storedVal( const IngestResult& ing, const Reference& ref, std::span<const NodeId> targets )
{
    const std::string_view rel = ref.composeRel;
    GrepCarrierVal         val{ std::string( rel.starts_with( '.' ) ? rel.substr( 1 ) : rel ), ref.calleeName, {}, 0 };
    if( targets.size() == 1 && targets[0] < ing.symbols.size() )
    {
        const Symbol& def = ing.symbols[ targets[0] ];
        val.line = def.line;
        if( def.fileId != ref.fileId && def.fileId < ing.files.size() )
        {
            val.path = ing.files[ def.fileId ];
        }
    }
    return val;
}

// vals=: the stored function values of every carrier on the page, attributed to the row whose definition made them —
// ONE madeIn pass for the page (source order: madeIn is ascending reference order, file then byte within one ingest).
inline void fillVals( const IngestResult& ing, const ValueRefIndex& vri, std::span<const GrepEncRow> rows, std::span<const NodeId> carrierIds,
                      std::span<GrepCarrier> out )
{
    for( const std::uint32_t v : vri.madeIn( carrierIds, RefRole::Value ) )
    {
        const Reference&          ref     = ing.references[v];
        const std::vector<NodeId> targets = vri.targetsOf( v );
        if( ref.fieldName.starts_with( '@' ) || targets.empty() )
        {
            continue;   // a decorator row is a fact about a definition; an unresolved name is not a function value
        }
        const auto row = std::ranges::find_if( rows, [ & ]( const GrepEncRow& rw ) { return std::ranges::find( rw.ids, ref.fromSymbol ) != rw.ids.end(); } );
        if( row == rows.end() || !out[ std::size_t( row - rows.begin() ) ].isCarrier )
        {
            continue;   // madeIn was asked for carrier ids only; a row that is no carrier holds none of them
        }
        GrepCarrier& c = out[ std::size_t( row - rows.begin() ) ];   // a definition sits on one row (grepEnclosingRows groups by chain)
        if( ++c.valsTotal <= kGrepCarrierShown )
        {
            c.vals.push_back( storedVal( ing, ref, targets ) );
        }
    }
}

struct ReadHit
{
    std::uint32_t name;     // index into the sorted, unique name list
    std::uint32_t fileId;   // into the reads ingest
    std::uint32_t line;
};

// The uses verb's role="read" rows (collectUseSites' filters) for every name in `names` (sorted, unique), in ONE pass
// over the reads ingest, sorted by name, then tier, path, line (source before tests) — the order
// the uses verb starts from before it ranks; its printed order is rankUseSites', which reads_at= does not follow.
inline std::vector<ReadHit> readSitesOf( const IngestResult& rd, std::span<const std::string_view> names )
{
    const std::vector<std::uint64_t> valueSites = valueSitesOf( rd, names );
    std::vector<ReadHit>             hits;
    for( const Reference& r : rd.references )
    {
        if( r.role != RefRole::Read || r.isCompose || r.isDocLink )
        {
            continue;
        }
        const auto it = std::ranges::lower_bound( names, std::string_view( r.calleeName ), sortutil::svLess );
        if( it == names.end() || *it != r.calleeName || std::ranges::binary_search( valueSites, ( std::uint64_t( r.fileId ) << 32 ) | r.startByte ) )
        {
            continue;   // another name, or a site the uses verb serves as role="value", not a read
        }
        hits.push_back( { std::uint32_t( it - names.begin() ), r.fileId, r.line } );
    }
    const std::vector<std::uint8_t> tierOfFile = pathTierIndexOver( rd, hits, []( const ReadHit& h ) { return h.fileId; } );
    std::ranges::sort( hits, [ & ]( const ReadHit& a, const ReadHit& b )
    {
        if( a.name != b.name )
        {
            return a.name < b.name;
        }
        const int c = compareTierThenPath( rd, tierOfFile, a.fileId, b.fileId );
        return c != 0 ? c < 0 : a.line < b.line;
    } );
    return hits;
}

// reads=/reads_at= for every readsKnown row, from one readSitesOf pass over the reads ingest.
inline void fillReads( const IngestResult& ing, const IngestResult& rd, std::span<const GrepEncRow> rows, std::span<GrepCarrier> out )
{
    std::vector<std::string_view> names;
    for( std::size_t r = 0; r < rows.size(); ++r )
    {
        if( out[r].readsKnown )
        {
            names.push_back( ing.symbols[ rows[r].ids.front() ].name );
        }
    }
    std::ranges::sort( names, sortutil::svLess );   // byte order: the default string_view < aborts the Linux G1 leg (portablebuildcheck #6)
    names.erase( std::unique( names.begin(), names.end() ), names.end() );
    const std::vector<ReadHit> hits = readSitesOf( rd, names );
    for( std::size_t r = 0; r < rows.size(); ++r )
    {
        if( !out[r].readsKnown )
        {
            continue;
        }
        const std::string_view name = ing.symbols[ rows[r].ids.front() ].name;
        const std::uint32_t    k    = std::uint32_t( std::ranges::lower_bound( names, name, sortutil::svLess ) - names.begin() );
        ASSUME( k < names.size() && names[k] == name, "every readsKnown row queued its name" );
        const auto [ first, last ] = std::ranges::equal_range( hits, k, {}, &ReadHit::name );   // hits are sorted by name first
        out[r].reads = std::uint32_t( last - first );
        for( auto h = first; h != last && out[r].at.size() < kGrepCarrierShown; ++h )
        {
            out[r].at.push_back( { rd.files[ h->fileId ], h->line } );
        }
    }
}

}   // namespace grepcarrier

// One carrier verdict per row. `ing` is the ingest the rows came from; `vri` its value index (vals=); `reads` the
// ingest whose role="read" references count (nullptr = none captured: reads= stays unknown on every row). Each pass
// walks its table ONCE for the whole page, never per row.
inline std::vector<GrepCarrier> grepCarriers( const IngestResult& ing, const ValueRefIndex& vri, std::span<const GrepEncRow> rows,
                                              const IngestResult* reads )
{
    std::vector<GrepCarrier> out( rows.size() );
    std::vector<NodeId>      carrierIds;   // every carrier definition on the page, for ONE madeIn pass
    bool                     anyReads = false;
    for( std::size_t r = 0; r < rows.size(); ++r )
    {
        if( !isGrepCarrierRow( ing, rows[r] ) )
        {
            continue;
        }
        out[r].isCarrier  = true;
        if( rows[r].ids.size() == 1 && ing.symbols[ rows[r].ids.front() ].fileId < ing.files.size() )
        {
            const Symbol& def = ing.symbols[ rows[r].ids.front() ];   // exact or none: a row grouping several defs has no one place
            out[r].defPath    = ing.files[ def.fileId ];
            out[r].defLine    = def.line;
        }
        out[r].readsKnown = reads != nullptr && grepCarrierReadsVisible( ing, ing.symbols[ rows[r].ids.front() ] );
        anyReads          = anyReads || out[r].readsKnown;
        carrierIds.insert( carrierIds.end(), rows[r].ids.begin(), rows[r].ids.end() );
    }
    if( !carrierIds.empty() )
    {
        grepcarrier::fillVals( ing, vri, rows, carrierIds, out );
    }
    if( anyReads )
    {
        EXPECTS( reads != nullptr, "a row is readsKnown only when a reads ingest was handed in" );
        grepcarrier::fillReads( ing, *reads, rows, out );
    }
    ENSURES( out.size() == rows.size() );
    return out;
}

// The root next= on an uncut answer whose TOP hit sits in a carrier with reads= — the uses verb on that carrier's name
// (the spelling floor_next= uses, countfloor.h countFloorNext), because where the value is read is the hop the at verb
// on the hit's own line cannot give. "" otherwise: the at verb on the top hit stays the follow-up. The CLI grep root
// and the MCP grep twin both call it; each caller keeps its cut-answer rule (the next page) ahead of this one.
inline std::string grepCarrierNext( const IngestResult& ing, std::span<const GrepHit> hits, std::span<const GrepEncRow> rows,
                                    std::span<const GrepCarrier> carriers )
{
    const std::size_t top = grepTopHitRow( hits, rows );
    if( top >= rows.size() || top >= carriers.size() || !carriers[top].readsKnown || carriers[top].reads == 0 )
    {
        return {};
    }
    return nextFlag( "--uses=", ing.symbols[ hits[0].enclosingId ].name );
}

// The two list attributes as plain text items (the emitters escape them for their own dialect): reads_at= as
// path:line, vals= as slot=fn@line / slot=fn@path:line / slot=fn, and at (p=) the carrier's own path:line beside vals= — paths
// root-relative exactly when the hit rows' are.
struct GrepCarrierText
{
    std::string              at;        // A3: p= — the carrier's own definition as path:line, only on a row that prints vals= ("" otherwise)
    std::vector<std::string> readsAt;
    std::vector<std::string> vals;
};

// A3: p= — the carrier's own definition as path:line, only beside vals= (the file a path-less vals= @line is in, storedVal's rule)
// and only on a row of one definition; "" otherwise.
inline std::string grepCarrierAt( const GrepCarrier& c, bool singleRoot, std::string_view rootPrefix )
{
    if( c.vals.empty() || c.defPath.empty() || c.defLine == 0 )
    {
        return {};
    }
    return std::string( singleRoot ? sarif::rootRelativeUri( c.defPath, rootPrefix ) : std::string_view( c.defPath ) ) + ":" + std::to_string( c.defLine );
}

inline GrepCarrierText grepCarrierText( const GrepCarrier& c, bool singleRoot, std::string_view rootPrefix )
{
    const auto rel = [ & ]( const std::string& p ) { return std::string( singleRoot ? sarif::rootRelativeUri( p, rootPrefix ) : std::string_view( p ) ); };
    GrepCarrierText t;
    if( c.readsKnown && c.reads > 0 )
    {
        for( const GrepCarrierSite& site : c.at )
        {
            t.readsAt.push_back( rel( site.path ) + ":" + std::to_string( site.line ) );
        }
    }
    for( const GrepCarrierVal& v : c.vals )
    {
        std::string item = v.slot.empty() ? v.fn : v.slot + "=" + v.fn;
        if( v.line != 0 )
        {
            item += "@" + ( v.path.empty() ? std::string() : rel( v.path ) + ":" ) + std::to_string( v.line );
        }
        t.vals.push_back( std::move( item ) );
    }
    t.at = grepCarrierAt( c, singleRoot, rootPrefix );
    return t;
}

}   // namespace rw
