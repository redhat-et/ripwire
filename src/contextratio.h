#pragma once

// contextratio.h — `--context-ratio`: the LOCAL-REASONING lens. One question, per symbol and per file:
// *to understand this, how much must I know that is not in front of me?*
//
// ── WHAT IS NEW HERE, AND WHAT IS NOT. Read this before touching the arithmetic. ───────────────────────
// The RATIO ITSELF IS PUBLISHED, at least twice, and this file does not pretend otherwise:
//   * Beck & Diehl, *On the Congruence of Modularity and Code Coupling*, FSE 2011, define
//     congruence(C) = cohesion/(cohesion+coupling) over the package hierarchy — for a single class that is
//     literally the distance-weighted fraction of its coupling that stays inside its own package. This
//     verb emits the complement of that quantity with the file as the boundary. Same idea, flipped.
//   * Robert Martin's instability I = Ce/(Ca+Ce) is the crude ancestor of the same fraction, and NDepend
//     has shipped it for years.
// So "the fraction of a unit's context that lives outside its own boundary" is NOT a contribution, and
// presenting it as one would read as a rename. What this verb refines is HOW the fraction is taken:
//   1. READER WEIGHTING. Every published form of the fraction counts EDGES (or distance-weighted edges).
//      This one also weights by what a reader must actually READ — the estimated tokens of the definitions
//      they would have to open — because two entities are not two equal units of comprehension when one is
//      a four-token type and the other is a two-hundred-line function. Both numbers are emitted side by
//      side (ent_ratio= is the edge form, read_ratio= is the reader-weighted one) precisely so the reader
//      can see the refinement doing work rather than take it on trust.
//   2. EVERY REFERENCE SITE, NOT JUST CALLS. The substrate is the `--uses` reference table: calls, value
//      reads, writes, imports, base-class edges and HAS-A member types. A coupling metric computed off the
//      call graph alone cannot see a class whose entire outside context is a base class and a member type.
// The one framing this file DOES claim as unoccupied is narrower and is stated as such: an a-priori,
// static, code-derived quantity of the form "understanding X requires N entities across M files". The
// adjacent work is all something else — Mylyn's degree-of-interest (Kersten & Murphy, AOSD 2005) is
// interaction-derived and retrospective and does not traverse the call graph at all; Suade (Robillard,
// TOSEM 2008) is a recommender, not a measure; Ko et al. (TSE 2006) and Piorkowski et al. (FSE 2016)
// measured HUMANS navigating, not a property of the code. That claim, and only that claim, is defensible.
//
// ── WHAT IS MEASURED ──────────────────────────────────────────────────────────────────────────────────
// A UNIT is one indexed symbol (markdown headings excluded — they are not code) or one file. For a symbol
// unit the sites are the references attributed to it; for a FILE unit they are every reference IN the
// file, which INCLUDES the file-scope ones (`#include`, top-level imports) that belong to no symbol. So a
// file row is a UNION over the file, not the sum of its symbol rows, and the legend says so.
//
// An ENTITY is an indexed definition that a reference site resolves to. Resolution is NAME-BASED and
// language-gated (graph.h's own `langCompatible`) — the same heuristic level `--uses` works at, NOT the
// call graph's narrowed resolution, because four of the five roles carry no resolution at all (a
// Reference holds a NAME). Using the resolved CSR for calls and names for everything else would put one
// row's two halves on different footings; one uniform rule is worth more than a locally better one.
//
// Three consequences, all disclosed on the first screen rather than discovered later:
//   * A name with several in-corpus definitions contributes each of them, capped at kDefsPerNameCap, and
//     amb= counts the names that were ambiguous. Without a cap a corpus-ubiquitous name (`size`, `get`)
//     would swamp the row it appears in; with one, ents= is bounded and the cap is a published number.
//   * A referenced name with NO in-corpus definition resolves to nothing and lands in ext=. Local
//     variables and parameters produce read/write sites and therefore dominate ext= on real code, so
//     ext= is NOT a count of external dependencies and is excluded from both ratios. Saying that plainly
//     is cheaper than letting a reader infer it wrongly.
//   * ents=/files= are FLOORS. A name-based static scan cannot see dynamic dispatch, reflection, or a
//     macro invocation whose #define is not indexed, so a zero means "none found", never "none exists".
//
// READER WEIGHT. tokensForEmittedBytes( the whole definition span, kBytesPerTokenBody ) — serialize.h's
// ONE body-text conversion, at the rate measured for def bodies (3.80 B/tok), never a second estimator.
// The span is [sigStartByte, endByte), byte-for-byte what `--expand` would print for that entity.
//
// DETERMINISM. Every (unit, entity) and (unit, name) fact is accumulated as a u64 key, sorted, and
// deduplicated before it is folded into a row — no hash iteration order reaches a count, let alone the
// output. The row sorts are integer-only: the two ratios are DERIVED for printing and never sorted on,
// so no float comparison decides an order. Rows come out most-outside-reading-first.

#include "model.h"
#include "graph.h"       // langCompatible — the SAME language gate the resolver uses; never a second one
#include "graphlegend.h"   // R-E fix (2026-08-19): rw::rootRelPathsLegend — the ONE root= definition
#include "serialize.h"   // escapeXml, tokensForEmittedBytes, kBytesPerTokenBody — the one body-token rate
#include "pageview.h"    // pageWindow + effectiveRowCap + pagingDisclosure — THE TRUNCATION VOCABULARY
#include "smallvec.h"          // rw::SmallVec — the small-vector the byName id-lists use in graph.h too

#include <algorithm>
#include <cstdint>
#include <cstdio>
#include <string>
#include <string_view>
#include <vector>

namespace rw
{
namespace contextratio
{

// Display caps, in the same shape as --ensemble's pair: the symbol listing is the one --limit/--offset
// windows, the file rollup discloses through its own noun-prefixed pair.
inline constexpr std::size_t kSymbolRowCap = 40;
inline constexpr std::size_t kFileRowCap   = 40;

// The per-NAME candidate cap. A name with more definitions than this contributes its first kDefsPerNameCap
// in ascending symbol id (i.e. sorted crawl order), and the row's amb= says the name was ambiguous. The
// number is published on the root as defs_per_name_cap= so it is never a hidden constant.
inline constexpr std::uint32_t kDefsPerNameCap = 8;

// ONE measured unit. Symbol rows and file rows carry the identical column set — the only thing that
// differs is what "own file" means — so they share a struct and share the fold below.
struct Row
{
    std::uint32_t unitId    = 0;   // NodeId for a symbol row; fileId for a file row
    std::uint32_t sites     = 0;   // reference sites scanned for this unit (every role)
    std::uint32_t ents      = 0;   // distinct in-corpus definitions the sites resolve to
    std::uint32_t entsOut   = 0;   // …of which are defined outside this unit's own file
    std::uint32_t files     = 0;   // distinct files holding those definitions
    std::uint32_t filesOut  = 0;   // …of which are not this unit's own file
    std::uint64_t rtok      = 0;   // estimated tokens of every entity definition (what a reader must read)
    std::uint64_t rtokOut   = 0;   // …the outside-the-file part
    std::uint32_t ext       = 0;   // distinct referenced names with NO in-corpus definition
    std::uint32_t amb       = 0;   // distinct referenced names that resolved to more than one definition
};

struct Scan
{
    std::vector<Row> symbols;
    std::vector<Row> files;
};

// The printable ratio. An exact integer quotient rendered at three decimals; 0/0 prints 0.000, which the
// legend defines as "nothing to resolve" rather than letting it read as "all local".
inline double ratioOf( std::uint64_t part, std::uint64_t whole ) noexcept
{
    return whole == 0 ? 0.0 : double( part ) / double( whole );
}

// The reader weight of ONE definition: its whole span through serialize.h's body-text rate. A declaration
// with no body (endByte <= sigEndByte) still costs its signature — a reader who must resolve it reads that.
inline std::uint32_t readerTokensOf( const Symbol& s ) noexcept
{
    const std::uint32_t defEnd = s.endByte > s.sigEndByte ? s.endByte : s.sigEndByte;
    const std::uint32_t bytes  = defEnd > s.sigStartByte ? defEnd - s.sigStartByte : 0u;
    return std::uint32_t( tokensForEmittedBytes( bytes, kBytesPerTokenBody ) );
}

// A markdown heading is a document node, not code, and has no reading context to measure.
inline bool isMeasurableKind( SymKind k ) noexcept
{
    return k != SymKind::Section;
}

namespace detail
{

// Pack a (unit, other) fact into one sortable u64. Sorting these is what makes the whole verb
// deterministic: nothing downstream ever iterates a hash container.
inline std::uint64_t packPair( std::uint32_t unit, std::uint32_t other ) noexcept
{
    return ( std::uint64_t( unit ) << 32 ) | std::uint64_t( other );
}

// The six raw fact streams ONE reference pass produces, before they are sorted, deduplicated and folded.
// Named as a struct rather than six out-parameters so the pass and the fold agree on the set by type: a
// seventh stream cannot be added to one and forgotten in the other.
struct Facts
{
    std::vector<std::uint64_t> symEnt,  fileEnt;    // (unit, entity id)
    std::vector<std::uint64_t> symExt,  fileExt;    // (unit, name id) for names with NO in-corpus definition
    std::vector<std::uint64_t> symAmb,  fileAmb;    // (unit, name id) for names that resolved to more than one
};

// The (unit, entity) fold, written ONCE for both rollups. `ownFileOf` is the only difference between them:
// a symbol unit's own file is the file it is defined in, a file unit IS its own file.
template<class OwnFileFn>
inline void foldEntityPairs( const std::vector<std::uint64_t>& pairs, const IngestResult& ing,
                             const std::vector<std::uint32_t>& tokOfSym, OwnFileFn ownFileOf,
                             std::vector<Row>& rows )
{
    std::vector<std::uint32_t> entFiles;
    std::size_t                pairIndex = 0;
    while( pairIndex < pairs.size() )
    {
        const std::uint32_t unit = std::uint32_t( pairs[pairIndex] >> 32 );
        if( unit >= rows.size() )
        {
            ++pairIndex;
            continue;
        }
        Row&                row = rows[unit];
        const std::uint32_t own = ownFileOf( unit );
        entFiles.clear();
        std::size_t scan = pairIndex;
        while( scan < pairs.size() && std::uint32_t( pairs[scan] >> 32 ) == unit )
        {
            const NodeId entity = NodeId( pairs[scan] & 0xFFFFFFFFu );
            if( entity < ing.symbols.size() )
            {
                const std::uint32_t entFile = ing.symbols[entity].fileId;
                ++row.ents;
                row.rtok += tokOfSym[entity];
                if( entFile != own )
                {
                    ++row.entsOut;
                    row.rtokOut += tokOfSym[entity];
                }
                entFiles.push_back( entFile );
            }
            ++scan;
        }
        std::sort( entFiles.begin(), entFiles.end() );
        entFiles.erase( std::unique( entFiles.begin(), entFiles.end() ), entFiles.end() );
        row.files = std::uint32_t( entFiles.size() );
        for( const std::uint32_t fileId : entFiles )
        {
            row.filesOut += fileId != own ? 1u : 0u;
        }
        pairIndex = scan;
    }
}

// The (unit, name) fold — one distinct-name counter, used for both ext= and amb=.
inline void foldNamePairs( const std::vector<std::uint64_t>& pairs, std::vector<Row>& rows, std::uint32_t Row::* field )
{
    for( const std::uint64_t key : pairs )
    {
        const std::uint32_t unit = std::uint32_t( key >> 32 );
        if( unit < rows.size() )
        {
            ++( rows[unit].*field );
        }
    }
}

using NameDefs = HashMap<std::string_view, SmallVec<NodeId, 2>>;

// name → definition ids, ascending (insertion follows symbol id order, which is already sorted crawl
// order). The map is a LOOKUP only — it is never iterated, so its order cannot reach an output byte.
inline NameDefs buildNameDefs( const IngestResult& ing )
{
    NameDefs byName;
    byName.reserve( ing.symbols.size() );
    for( const Symbol& s : ing.symbols )
    {
        if( isMeasurableKind( s.kind ) )
        {
            byName[ std::string_view( s.name ) ].push_back( s.id );
        }
    }
    return byName;
}

// ONE reference site's candidates: same name, language-compatible (graph.h's own gate, never a second one),
// capped at kDefsPerNameCap and in ascending id order. The referring symbol itself is NOT filtered here —
// that is the caller's rule, because it applies to the symbol rollup and not to the file one.
inline void resolveCandidates( const IngestResult& ing, const NameDefs& byName, const Reference& r,
                               std::vector<NodeId>& out )
{
    out.clear();
    const auto it = byName.find( std::string_view( r.calleeName ) );
    if( it == byName.end() )
    {
        return;
    }
    for( const NodeId id : it->second )
    {
        if( out.size() >= kDefsPerNameCap )
        {
            break;
        }
        // langCompatible AND namespaceCompatible — the same pair buildGraph's candidate set is gated by.
        // This is the one place the namespace gate has a MEASURABLE effect: unlike the call-edge loop, which
        // admits only Call and Macro, this pass resolves every role it is HANDED.
        //
        // The role that reaches it is RefRole::Extends, NOT RefRole::Type — corrected 2026-08-20 after
        // adversarial verification found both this comment and graph.h's naming the wrong one. There is
        // exactly one caller, collectFacts below, and it `continue`s on Type 28 lines before it calls here
        // (see the DELIBERATELY OUT OF SCOPE block), so a Type reference can never arrive. What keeps a type
        // mention from spraying across same-named functions is that `continue`, not this predicate.
        //
        // What the predicate actually does here, measured on test/nsfilterfix: the base clause of
        // `class Derived : public Handler` is an Extends reference, and without the narrow it binds to BOTH
        // `class Handler` and the free `int Handler( int )` — ents 1 -> 2, amb 0 -> 1 on Derived's row. A base
        // clause can only ever mean a class, struct or interface, so the narrow is sound, not a guess.
        // Pinned by test/nsfiltercheck.sh arm 5, which is red under full removal of the narrowing.
        if( langCompatible( ing.symbols[id].lang, r.lang ) && namespaceCompatible( r.role, ing.symbols[id].kind ) )
        {
            out.push_back( id );
        }
    }
}

// THE reference pass. Walks the reference table once, counts sites into the dense row arrays, and emits the
// raw (unit, entity) / (unit, name) facts. Nothing is sorted or deduplicated here — that is the caller's
// next step, and keeping the two apart is what lets the pass stay a straight-line loop.
inline Facts collectFacts( const IngestResult& ing, const NameDefs& byName,
                           std::vector<Row>& symRows, std::vector<Row>& fileRows )
{
    // name interning, so a "distinct NAME" fact is a u32 and the ext=/amb= folds are the same sort as the
    // entity fold. Same rule as byName: lookup only, never iterated.
    HashMap<std::string_view, std::uint32_t> nameIndex;
    nameIndex.reserve( byName.size() );

    Facts               facts;
    std::vector<NodeId> candidates;
    const std::size_t   symbolCount = ing.symbols.size();
    const std::size_t   fileCount   = ing.files.size();

    for( const Reference& r : ing.references )
    {
        if( r.isDocLink || r.lang == Lang::Markdown )
        {
            continue;   // a doc→code mention is a reader's cross-reference, not a thing the code resolves
        }
        if( r.role == RefRole::Type )
        {
            // DELIBERATELY OUT OF SCOPE, and this is a scoping decision rather than a judgement that a type
            // mention is not context. Two reasons. (1) A member declaration `Shared m_a;` already contributes
            // a site here through its HAS-A compose reference, which occupies the same bytes — admitting the
            // type mention as well would count ONE thing a reader must read TWICE. (2) The coupling/cohesion
            // thresholds this lens feeds were calibrated over the pre-Type reference stream (docs/EVALS.md
            // §9); moving their input silently, from a lane registered to change the USE-SITE index, would
            // invalidate a calibrated instrument as a side effect. Admitting type mentions here is a real
            // improvement and a real re-calibration — it needs its own registered round, not a free ride.
            continue;
        }
        const bool          hasFile = r.fileId < fileCount;
        const bool          hasSym  = r.fromSymbol != kNoNode && r.fromSymbol < symbolCount
                                      && isMeasurableKind( ing.symbols[r.fromSymbol].kind );
        if( !hasSym && !hasFile )
        {
            continue;
        }
        if( hasSym )
        {
            ++symRows[r.fromSymbol].sites;
        }
        if( hasFile )
        {
            ++fileRows[r.fileId].sites;
        }

        resolveCandidates( ing, byName, r, candidates );
        const auto [ nameIt, inserted ] = nameIndex.try_emplace( std::string_view( r.calleeName ), std::uint32_t( nameIndex.size() ) );
        (void) inserted;
        const std::uint32_t nameId = nameIt->second;

        if( candidates.empty() )
        {
            if( hasSym )  { facts.symExt.push_back( packPair( r.fromSymbol, nameId ) ); }
            if( hasFile ) { facts.fileExt.push_back( packPair( r.fileId, nameId ) ); }
            continue;
        }
        if( candidates.size() > 1 )
        {
            if( hasSym )  { facts.symAmb.push_back( packPair( r.fromSymbol, nameId ) ); }
            if( hasFile ) { facts.fileAmb.push_back( packPair( r.fileId, nameId ) ); }
        }
        for( const NodeId entity : candidates )
        {
            // a symbol does not have to leave itself to understand its own recursion; a FILE does still
            // count a definition it holds, because that is what puts it in the ratio's denominator.
            if( hasSym && entity != r.fromSymbol )
            {
                facts.symEnt.push_back( packPair( r.fromSymbol, entity ) );
            }
            if( hasFile )
            {
                facts.fileEnt.push_back( packPair( r.fileId, entity ) );
            }
        }
    }
    return facts;
}

}   // namespace detail

// THE scan. One pass over the symbol table for the name index and the reader weights, one pass over the
// reference table for the raw facts, then sort/dedup/fold and two integer-keyed sorts.
inline Scan computeContextRatio( const IngestResult& ing )
{
    const std::size_t symbolCount = ing.symbols.size();
    const std::size_t fileCount   = ing.files.size();

    // reader weight per definition, computed once (a definition reached from a hundred sites is read once).
    std::vector<std::uint32_t> tokOfSym( symbolCount, 0u );
    for( std::size_t i = 0; i < symbolCount; ++i )
    {
        tokOfSym[i] = readerTokensOf( ing.symbols[i] );
    }

    std::vector<Row> symRows( symbolCount );
    std::vector<Row> fileRows( fileCount );
    for( std::size_t i = 0; i < symbolCount; ++i )
    {
        symRows[i].unitId = std::uint32_t( i );
    }
    for( std::size_t i = 0; i < fileCount; ++i )
    {
        fileRows[i].unitId = std::uint32_t( i );
    }

    detail::Facts facts = detail::collectFacts( ing, detail::buildNameDefs( ing ), symRows, fileRows );

    // sorted and deduplicated BEFORE anything is counted — this is the whole determinism argument, and it
    // is spelled once over the fact set rather than six times (the tree writes this idiom inline everywhere;
    // naming a three-line wrapper for it is a clone, which quality-delta correctly said so).
    for( std::vector<std::uint64_t>* stream : { &facts.symEnt, &facts.fileEnt, &facts.symExt,
                                                &facts.fileExt, &facts.symAmb, &facts.fileAmb } )
    {
        std::sort( stream->begin(), stream->end() );
        stream->erase( std::unique( stream->begin(), stream->end() ), stream->end() );
    }

    detail::foldEntityPairs( facts.symEnt, ing, tokOfSym,
                             [ & ]( std::uint32_t unit ) { return ing.symbols[unit].fileId; }, symRows );
    detail::foldEntityPairs( facts.fileEnt, ing, tokOfSym,
                             []( std::uint32_t unit ) { return unit; }, fileRows );
    detail::foldNamePairs( facts.symExt,  symRows,  &Row::ext );
    detail::foldNamePairs( facts.fileExt, fileRows, &Row::ext );
    detail::foldNamePairs( facts.symAmb,  symRows,  &Row::amb );
    detail::foldNamePairs( facts.fileAmb, fileRows, &Row::amb );

    // MOST-OUTSIDE-READING-FIRST, integer keys only: the outside reading volume, then the outside entity
    // count, then the total reading volume, then the id (already assigned in file/line/name order). The
    // printed ratios are DERIVED and never sorted on — a 1-of-1 row would otherwise rank 1.000 above a
    // symbol with forty outside entities, which is the noise this ordering exists to avoid.
    const auto byOutsideFirst = []( const Row& a, const Row& b ) noexcept
    {
        if( a.rtokOut != b.rtokOut )   { return a.rtokOut > b.rtokOut; }
        if( a.entsOut != b.entsOut )   { return a.entsOut > b.entsOut; }
        if( a.rtok    != b.rtok )      { return a.rtok    > b.rtok; }
        return a.unitId < b.unitId;
    };

    Scan scan;
    scan.symbols.reserve( symbolCount );
    for( std::size_t i = 0; i < symbolCount; ++i )
    {
        if( isMeasurableKind( ing.symbols[i].kind ) )
        {
            scan.symbols.push_back( symRows[i] );
        }
    }
    std::sort( scan.symbols.begin(), scan.symbols.end(), byOutsideFirst );

    // a file row is emitted for every file that holds at least one measurable symbol — the same corpus the
    // symbol listing covers, aggregated the other way.
    std::vector<char> fileHasSymbol( fileCount, 0 );
    for( std::size_t i = 0; i < symbolCount; ++i )
    {
        if( isMeasurableKind( ing.symbols[i].kind ) && ing.symbols[i].fileId < fileCount )
        {
            fileHasSymbol[ ing.symbols[i].fileId ] = 1;
        }
    }
    scan.files.reserve( fileCount );
    for( std::size_t i = 0; i < fileCount; ++i )
    {
        if( fileHasSymbol[i] != 0 )
        {
            scan.files.push_back( fileRows[i] );
        }
    }
    // file rows break their last tie on PATH, not on file id, so the order is stable against a crawl that
    // assigns ids differently; the paths are unique, so this is a total order.
    std::sort( scan.files.begin(), scan.files.end(),
               [ & ]( const Row& a, const Row& b ) noexcept
               {
                   if( a.rtokOut != b.rtokOut ) { return a.rtokOut > b.rtokOut; }
                   if( a.entsOut != b.entsOut ) { return a.entsOut > b.entsOut; }
                   if( a.rtok    != b.rtok )    { return a.rtok    > b.rtok; }
                   return ing.files[a.unitId] < ing.files[b.unitId];
               } );
    return scan;
}

// The legend the reader meets FIRST. Every attribute this verb emits is DEFINED here in the house `name=`
// form (test/legendcoveragecheck.sh derives that mechanically), and the PRIOR-ART CREDIT is part of it
// rather than a source comment — the ratio is a published quantity and a reader meeting it for the first
// time is entitled to know that on the first screen. test/contextratiocheck.sh arm (J) pins the credit.
// No `--` digraph anywhere in it: that is illegal inside an XML comment, which is why flags are named bare.
inline constexpr const char* kContextRatioLegend =
    "<!-- ripwire context-ratio: the LOCAL-REASONING lens — for one symbol (and the same numbers rolled up per "
    "file), how much of what you must resolve to understand it lives OUTSIDE its own file. "
    "ATTRIBUTION, because the fraction itself is published: the share of a unit's coupling that stays inside "
    "its own boundary is Beck and Diehl's per-class congruence (FSE 2011) and Martin's instability "
    "Ce/(Ca+Ce) is its crude ancestor. This verb is a REFINEMENT of that measure, not a new one. Two things "
    "are refined. First, the ratio is also taken over what a reader must READ (read_ratio=, weighted by the "
    "estimated tokens of the definitions to open) and not only over edge counts (ent_ratio=) — both are "
    "printed side by side so the weighting can be seen doing work. Second, the reference set is EVERY use "
    "site (call, value read, write, import, base class, member type), not calls alone, so a type whose whole "
    "outside context is a base class and a field is measured rather than missed. "
    "s=one measured symbol: p=path:line n=symbol name t=symbol kind. f=the same columns rolled up per file, "
    "which is a UNION over every reference site in the file — including the file-scope ones like includes "
    "and imports that belong to no symbol — and therefore NOT the sum of that file's symbol rows. "
    "sites=reference sites scanned for this unit, in every role "
    "ents=distinct in-corpus definitions those sites resolve to ents_out=how many of them are defined "
    "outside this unit's own file ent_ratio=ents_out divided by ents, the edge-count form "
    "files=distinct files holding those definitions files_out=how many of them are not this unit's own file "
    "rtok=estimated tokens of every entity definition, the whole span at 3.80 bytes per token, which is what "
    "a reader must actually read rtok_out=the outside-the-file part of rtok read_ratio=rtok_out divided by "
    "rtok, the READER-WEIGHTED form and the one this verb exists for. Both ratios print 0.000 when there is "
    "nothing to resolve (ents=0), which is not the same claim as a self-contained unit — read ents= first. "
    "ext=distinct referenced names with NO in-corpus definition. Local variables and parameters produce read "
    "and write sites, so they DOMINATE ext= on real code: it is not a count of external dependencies and it "
    "is excluded from both ratios. amb=distinct referenced names that resolved to more than one definition, "
    "each of which is counted as an entity — resolution is NAME-BASED and language-gated, the same heuristic "
    "level the uses verb works at, never the call graph's narrowed resolution, because four of the five "
    "reference roles carry no resolution at all. defs_per_name_cap=the most definitions ONE name may "
    "contribute (the first that many in symbol id order); a corpus-ubiquitous name would otherwise swamp "
    "every row it appears in. body_bytes_per_token=the rate rtok= is converted at. "
    "ents= and files= are FLOORS: a name-based static scan cannot see dynamic dispatch, reflection, or a "
    "macro invocation whose #define is not indexed, so a zero means none FOUND, never none exists. "
    "units=symbols measured file_units=files measured. Rows come out most-outside-reading-first (rtok_out "
    "descending, then ents_out, then rtok, then id) — an ORDERING, never a grade, and never a threshold. "
    "shown_syms=symbol rows printed syms_capped=1 when symbol rows were dropped shown_files=file rows "
    "printed files_capped=1 when file rows were dropped; the symbol listing is the one limit=N and offset=M "
    "window, which also prints total= has_more= next_offset= offset= limit= -->";

// Emit the report. Returns the process exit code — always 0: this is a lens, not a gate. `rootPrefix` empty
// ⇒ every p= stays the ing.files[] spelling unchanged (multi-root, or no single root to strip) — R-E
// (2026-08-17 harvest): same convention serialize()'s pathRel uses; `rootAttr` is the ready-made root="…"
// clause (empty when rootPrefix is), computed once by the caller since every --* lens in runMaintenanceViews
// shares it.
inline int writeContextRatioReport( const IngestResult& ing, int pageLimit, int pageOffset,
                                    std::string_view rootPrefix = {}, const std::string& rootAttr = std::string() )
{
    const Scan        scan  = computeContextRatio( ing );
    const std::size_t total = scan.symbols.size();
    const PageWindow  page  = pageWindow( total, effectiveRowCap( pageLimit, int( kSymbolRowCap ) ), pageOffset );
    const std::size_t shown = page.end > page.begin ? page.end - page.begin : 0;
    const std::size_t fileShown = scan.files.size() < kFileRowCap ? scan.files.size() : kFileRowCap;

    char paging[kPageDisclosureCap];
    pagingDisclosure( paging, sizeof paging, total, page.end, pageLimit, pageOffset );

    std::fputs( kContextRatioLegend, stdout );
    // R-E fix (2026-08-19): the shared root-relative clause, emitted exactly when root= is (graphlegend.h).
    std::fputs( rw::rootRelPathsLegend( !rootAttr.empty() ), stdout );
    std::printf( "<contextratio units=\"%zu\" file_units=\"%zu\" defs_per_name_cap=\"%u\" body_bytes_per_token=\"%.2f\""
                 " shown_syms=\"%zu\" syms_capped=\"%s\" shown_files=\"%zu\" files_capped=\"%s\"%s%s>",
                 total, scan.files.size(), unsigned( kDefsPerNameCap ), kBytesPerTokenBody,
                 shown, shown < total ? "1" : "0",
                 fileShown, fileShown < scan.files.size() ? "1" : "0", paging, rootAttr.c_str() );

    // TWO scratch buffers, not one reused twice in the same call: escapeXml returns a VIEW into its `out`,
    // so a second call with the same buffer invalidates the first view (readability.h carries the same note).
    std::vector<char> escPath;
    std::vector<char> escName;
    const auto         pathRel = [ & ]( std::uint32_t fileId ) -> std::string_view
    {
        return rootPrefix.empty() ? std::string_view( ing.files[ fileId ] ) : rw::sarif::rootRelativeUri( ing.files[ fileId ], rootPrefix );
    };
    for( std::size_t rowIndex = page.begin; rowIndex < page.end; ++rowIndex )
    {
        const Row&        row = scan.symbols[rowIndex];
        const Symbol&     s   = ing.symbols[row.unitId];
        const std::string path( escapeXml( pathRel( s.fileId ), escPath ) );
        const std::string name( escapeXml( s.name, escName ) );
        std::printf( "<s p=\"%s:%u\" n=\"%s\" t=\"%s\" sites=\"%u\" ents=\"%u\" ents_out=\"%u\" ent_ratio=\"%.3f\""
                     " files=\"%u\" files_out=\"%u\" rtok=\"%llu\" rtok_out=\"%llu\" read_ratio=\"%.3f\" ext=\"%u\" amb=\"%u\"/>",
                     path.c_str(), s.line, name.c_str(), symTag( s.kind ),
                     row.sites, row.ents, row.entsOut, ratioOf( row.entsOut, row.ents ),
                     row.files, row.filesOut,
                     static_cast<unsigned long long>( row.rtok ), static_cast<unsigned long long>( row.rtokOut ),
                     ratioOf( row.rtokOut, row.rtok ), row.ext, row.amb );
    }
    for( std::size_t fileIndex = 0; fileIndex < fileShown; ++fileIndex )
    {
        const Row&        row = scan.files[fileIndex];
        const std::string path( escapeXml( pathRel( row.unitId ), escPath ) );
        std::printf( "<f p=\"%s\" sites=\"%u\" ents=\"%u\" ents_out=\"%u\" ent_ratio=\"%.3f\""
                     " files=\"%u\" files_out=\"%u\" rtok=\"%llu\" rtok_out=\"%llu\" read_ratio=\"%.3f\" ext=\"%u\" amb=\"%u\"/>",
                     path.c_str(), row.sites, row.ents, row.entsOut, ratioOf( row.entsOut, row.ents ),
                     row.files, row.filesOut,
                     static_cast<unsigned long long>( row.rtok ), static_cast<unsigned long long>( row.rtokOut ),
                     ratioOf( row.rtokOut, row.rtok ), row.ext, row.amb );
    }
    std::printf( "</contextratio>" );
    return 0;
}

}   // namespace contextratio
}   // namespace rw
