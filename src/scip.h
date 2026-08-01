#pragma once

// scip.h — the SCIP precision overlay (Wave 4 #15 / long-planned in SPEC): consume a Sourcegraph
// SCIP index (`--scip=index.scip`) as an OPTIONAL, zero-dependency precision layer over the name-based
// call graph. Where the index covers a reference site, its resolution REPLACES ripwire's name-based
// guess and the resulting edge is tagged `prov="scip"` so the honesty gauges (amb= / ambiguous=) report
// exactly how much of the graph is precise vs guessed.
//
// Zero dependencies: we hand-roll the MINIMAL protobuf WIRE reader we need — varint decode, length-
// delimited fields, and field-skipping — walking only the ~4 message paths that matter:
//   Index    { documents = 2 }                                            (repeated Document)
//   Document { relative_path = 1, occurrences = 2, symbols = 3 }
//   Occurrence { range = 1 (repeated int32, packed), symbol = 2, symbol_roles = 3 }
//   SymbolInformation { symbol = 1, display_name = 6 }                     (display only; optional)
// Field numbers VERIFIED against https://raw.githubusercontent.com/sourcegraph/scip/main/scip.proto
// (fetched during implementation): Index.documents=2, Document.relative_path=1/occurrences=2/symbols=3,
// Occurrence.range=1/symbol=2/symbol_roles=3, SymbolInformation.symbol=1/display_name=6,
// SymbolRole.Definition = 0x1 (bit 0). A SCIP `range` is [startLine, startChar, endChar] (3 ints, same
// line) or [startLine, startChar, endLine, endChar] (4 ints); all 0-based. ripwire `Symbol::line` is
// 1-based, so we map scipStartLine + 1 ↔ symbol.line.
//
// Degrade, never throw (house style): a missing / unreadable / corrupt / truncated / mismatched-tree
// index emits ONE DEGRADED_PATH_ALERT and returns an EMPTY overlay — the pipeline proceeds name-based,
// byte-identical to a run with no --scip. The wire reader is bounds-checked on every read so a hostile
// or truncated blob can never over-read (the fuzz gate flips/truncates bytes and asserts no crash).

#include "model.h"
#include "scipoverlay.h"        // ScipEdge / ScipCover / ScipOverlay — the data struct (also used by graph.h)
#include "gitmine.h"            // resolveFileSuffix — map a SCIP relative_path to a ripwire fileId
#include "infra/Diagnostics.h"   // DEGRADED_PATH_ALERT

#include <algorithm>
#include <cstdint>
#include <cstdio>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

namespace rw
{

// ---- minimal protobuf wire reader ------------------------------------------------------------------
// A bounds-checked cursor over a byte span. Every accessor returns false on under-read (never over-reads
// past `end`), so a truncated / corrupt blob degrades cleanly rather than reading out of bounds. Wire
// types we handle: 0 = varint, 2 = length-delimited; 1 (i64) and 5 (i32) are skipped by fixed width.
namespace scipwire
{
    struct Reader
    {
        const std::uint8_t* p   = nullptr;
        const std::uint8_t* end = nullptr;

        bool atEnd()  const noexcept { return p >= end; }
        bool ok()     const noexcept { return p <= end; }

        // LEB128 varint (≤ 10 bytes). Returns false on truncation / overlong encoding.
        bool varint( std::uint64_t& out ) noexcept
        {
            std::uint64_t v = 0;
            for( int shift = 0; shift < 64; shift += 7 )
            {
                if( p >= end ) return false;                    // truncated
                const std::uint8_t b = *p++;
                v |= std::uint64_t( b & 0x7F ) << shift;
                if( ( b & 0x80 ) == 0 ) { out = v; return true; }
            }
            return false;                                       // overlong (> 10 bytes) → corrupt
        }

        // a tag = (fieldNumber << 3) | wireType.
        bool tag( std::uint32_t& fieldNumber, std::uint32_t& wireType ) noexcept
        {
            std::uint64_t t = 0;
            if( !varint( t ) ) return false;
            fieldNumber = std::uint32_t( t >> 3 );
            wireType    = std::uint32_t( t & 0x7 );
            return true;
        }

        // a length-delimited field → a sub-span [q, q+len). Bounds-checked against `end`.
        bool lenDelim( const std::uint8_t*& q, std::size_t& len ) noexcept
        {
            std::uint64_t n = 0;
            if( !varint( n ) ) return false;
            if( n > std::uint64_t( end - p ) ) return false;    // length runs past the buffer → corrupt
            q   = p;
            len = std::size_t( n );
            p  += n;
            return true;
        }

        // skip a field of the given wire type (for the fields we don't care about). Returns false on
        // truncation / an unknown wire type (3/4 = deprecated groups — treat as corrupt, degrade).
        bool skip( std::uint32_t wireType ) noexcept
        {
            switch( wireType )
            {
                case 0: { std::uint64_t v; return varint( v ); }                       // varint
                case 1: { if( end - p < 8 ) return false; p += 8; return true; }       // i64
                case 5: { if( end - p < 4 ) return false; p += 4; return true; }       // i32
                case 2: { const std::uint8_t* q; std::size_t n; return lenDelim( q, n ); }   // length-delimited
                default: return false;                                                 // 3/4 groups → corrupt
            }
        }
    };
}   // namespace scipwire

// ---- SCIP structural decode (proto → plain records, no ripwire mapping yet) -------------------------
// One occurrence as the wire yields it: 0-based start line + the SCIP symbol string + the role bitfield.
struct ScipOccurrence
{
    std::int64_t startLine = -1;    // range[0]; -1 if the range was absent / malformed
    std::string  symbol;            // the SCIP symbol string (e.g. "scip-clang … `A::f`().")
    std::uint32_t roles = 0;        // symbol_roles bitfield; bit 0 (0x1) = Definition
};

struct ScipDocument
{
    std::string                 relativePath;
    std::vector<ScipOccurrence> occurrences;
};

// parse a packed-or-unpacked `repeated int32 range` field → its first element (the start line). SCIP
// emits `range` packed (wire type 2) but we also accept the unpacked form defensively. We only need
// range[0] (the definition/reference start line) for the (file,line) mapping.
inline std::int64_t scipDecodeRangeStart( const std::uint8_t* q, std::size_t len ) noexcept
{
    scipwire::Reader r{ q, q + len };
    std::uint64_t    first = 0;
    if( !r.varint( first ) ) return -1;
    return std::int64_t( first );
}

// decode one Occurrence sub-message.
inline bool scipDecodeOccurrence( const std::uint8_t* q, std::size_t len, ScipOccurrence& occ ) noexcept
{
    scipwire::Reader r{ q, q + len };
    while( !r.atEnd() )
    {
        std::uint32_t field = 0, wire = 0;
        if( !r.tag( field, wire ) ) return false;
        if( field == 1 && wire == 2 )                                   // range (packed int32)
        {
            const std::uint8_t* rp; std::size_t rn;
            if( !r.lenDelim( rp, rn ) ) return false;
            occ.startLine = scipDecodeRangeStart( rp, rn );
        }
        else if( field == 1 && wire == 0 )                              // range (unpacked): first int = start line
        {
            std::uint64_t v; if( !r.varint( v ) ) return false;
            if( occ.startLine < 0 ) occ.startLine = std::int64_t( v );
        }
        else if( field == 2 && wire == 2 )                              // symbol (string)
        {
            const std::uint8_t* sp; std::size_t sn;
            if( !r.lenDelim( sp, sn ) ) return false;
            occ.symbol.assign( reinterpret_cast<const char*>( sp ), sn );
        }
        else if( field == 3 && wire == 0 )                              // symbol_roles (int32)
        {
            std::uint64_t v; if( !r.varint( v ) ) return false;
            occ.roles = std::uint32_t( v );
        }
        else if( !r.skip( wire ) ) return false;                        // any other field → skip
    }
    return true;
}

// decode one Document sub-message → relativePath + occurrences.
inline bool scipDecodeDocument( const std::uint8_t* q, std::size_t len, ScipDocument& doc ) noexcept
{
    scipwire::Reader r{ q, q + len };
    while( !r.atEnd() )
    {
        std::uint32_t field = 0, wire = 0;
        if( !r.tag( field, wire ) ) return false;
        if( field == 1 && wire == 2 )                                   // relative_path (string)
        {
            const std::uint8_t* sp; std::size_t sn;
            if( !r.lenDelim( sp, sn ) ) return false;
            doc.relativePath.assign( reinterpret_cast<const char*>( sp ), sn );
        }
        else if( field == 2 && wire == 2 )                              // occurrences (repeated Occurrence)
        {
            const std::uint8_t* op; std::size_t on;
            if( !r.lenDelim( op, on ) ) return false;
            ScipOccurrence occ;
            if( !scipDecodeOccurrence( op, on, occ ) ) return false;
            doc.occurrences.push_back( std::move( occ ) );
        }
        else if( !r.skip( wire ) ) return false;                        // relative_path_bytes / symbols / text / … → skip
    }
    return true;
}

// decode the top-level Index → its Documents. Returns false on any corruption (caller degrades).
inline bool scipDecodeIndex( const std::uint8_t* data, std::size_t size, std::vector<ScipDocument>& docs ) noexcept
{
    scipwire::Reader r{ data, data + size };
    while( !r.atEnd() )
    {
        std::uint32_t field = 0, wire = 0;
        if( !r.tag( field, wire ) ) return false;
        if( field == 2 && wire == 2 )                                   // documents (repeated Document)
        {
            const std::uint8_t* dp; std::size_t dn;
            if( !r.lenDelim( dp, dn ) ) return false;
            ScipDocument doc;
            if( !scipDecodeDocument( dp, dn, doc ) ) return false;
            docs.push_back( std::move( doc ) );
        }
        else if( !r.skip( wire ) ) return false;                        // metadata / external_symbols → skip
    }
    return true;
}

// ---- load the whole file (bounded) -----------------------------------------------------------------
// Read a .scip file into a byte buffer. Empty on any I/O failure (caller degrades). Bounded at 256 MiB
// — a SCIP index larger than that on a repo ripwire can parse is almost certainly the wrong file.
inline std::vector<std::uint8_t> scipReadFile( const char* path )
{
    std::vector<std::uint8_t> bytes;
    std::FILE* f = std::fopen( path, "rb" );
    if( !f ) return bytes;
    if( std::fseek( f, 0, SEEK_END ) != 0 ) { std::fclose( f ); return bytes; }
    const long sz = std::ftell( f );
    if( sz <= 0 || sz > ( 256L << 20 ) ) { std::fclose( f ); return bytes; }
    std::rewind( f );
    bytes.resize( std::size_t( sz ) );
    const std::size_t got = std::fread( bytes.data(), 1, bytes.size(), f );
    std::fclose( f );
    if( got != bytes.size() ) bytes.clear();
    return bytes;
}

// ---- map decoded SCIP → ripwire node ids (the overlay) ---------------------------------------------
// Strategy (design decision 2):
//   (a) DEFINITION occurrences (role bit 0x1) build a map scipSymbolString → ripwire NodeId: match the
//       document's relative_path to a ripwire fileId (suffix match) and scipStartLine+1 to the symbol
//       DEFINED at that (fileId, line). A def whose file/line does not exist in ripwire's model (the
//       index covers code ripwire didn't parse) is simply skipped — the overlay stays a subset.
//   (b) REFERENCE occurrences (NOT definitions) whose scipSymbolString maps (via the def map above) to a
//       known def produce a precise edge fromSymbol → thatDef. The enclosing `fromSymbol` is taken from
//       ripwire's OWN parse: the reference ripwire captured at the SAME (fileId, line), whose fromSymbol
//       is the exact byte-span-attributed enclosing definition. S5 STALENESS GATE: if ripwire parsed NO
//       reference at (fileId, refLine1), the SCIP ref line does not correspond to a currently-parsed
//       call site — the index is stale at this line — so the occurrence is DROPPED rather than attached
//       to whatever current symbol happens to span the stale line. This degrades toward FEWER-but-CORRECT
//       precise edges (never a wrong one): the prov="scip" edges that remain are trustworthy. The old
//       "greatest def line ≤ occ line" line-scan silently mis-attributed under staleness; keying on
//       ripwire's own (file,line)→fromSymbol both fixes that and is strictly more precise than a line-scan.
// Everything is derived from sorted inputs and the result is sorted+deduped, so the overlay — and thus
// the graph — is byte-deterministic. `calleeName` in coveredFrom is the ripwire def symbol's NAME, so it
// matches Reference::calleeName at the buildGraph seam.
// internalOccurrences / matchedOccurrencesPreDedup (A4-F21): the S5 staleness ratio's denominator and
// numerator, computed HERE (not via ScipOverlay's own refOccurrences/edgesPinned fields, which are the
// wrong pair for a ratio — see loadScipOverlay's comment) and handed back to the sole caller by reference.
//   internalOccurrences        — ref occurrences whose SYMBOL resolved into scipDef (i.e. the index thinks
//                                 it points at a def in THIS tree). Excludes external refs (the majority in
//                                 real code — std::/library symbols the index also records but that ripwire
//                                 never could or should match) from the denominator: those aren't a
//                                 freshness signal at all, just always-absent noise that deflated the old
//                                 ratio (denominator = ALL occurrences including externals; a fresh index
//                                 already "fails" most externals by construction, so old pct << true pct).
//   matchedOccurrencesPreDedup — of those internal occurrences, how many matched a live (non-stale)
//                                 ripwire ref line PRE-dedup (every occurrence counted once, not collapsed
//                                 to unique (from,to) edges the way ov.edgesPinned is). Using the deduped
//                                 edge count as the numerator against a per-occurrence denominator was the
//                                 other half of the systematic deflation: N call-sites of the same callee
//                                 from the same enclosing symbol count as 1 edge but N occurrences.
inline ScipOverlay buildScipOverlay( const IngestResult& ing, const std::vector<ScipDocument>& docs,
                                      std::size_t& internalOccurrences, std::size_t& matchedOccurrencesPreDedup )
{
    ScipOverlay ov;
    ov.documentsSeen = docs.size();
    internalOccurrences        = 0;
    matchedOccurrencesPreDedup = 0;

    // per-file sorted (defLine → NodeId) index, for both the definition mapping and the enclosing-symbol
    // lookup. Built once, reused. defLines[fileId] = ascending (line, id) pairs of symbols defined there.
    struct LineDef { std::uint32_t line; NodeId id; };
    std::vector<std::vector<LineDef>> defLines( ing.files.size() );
    for( const Symbol& s : ing.symbols )
        if( s.fileId < defLines.size() ) defLines[ s.fileId ].push_back( { s.line, s.id } );
    for( std::vector<LineDef>& v : defLines )
        std::sort( v.begin(), v.end(), []( const LineDef& a, const LineDef& b ) noexcept
                   { return a.line != b.line ? a.line < b.line : a.id < b.id; } );

    // (a) scipSymbolString → the ripwire def NodeId at (relative_path, startLine+1). A relative_path that
    // maps to no ripwire file, or a def line with no ripwire symbol, is skipped (subset semantics).
    HashMap<std::string, NodeId> scipDef;
    for( const ScipDocument& doc : docs )
    {
        const std::uint32_t fid = resolveFileSuffix( ing, doc.relativePath );
        if( fid == UINT32_MAX ) continue;                                // covers a tree ripwire didn't map
        for( const ScipOccurrence& occ : doc.occurrences )
        {
            if( !( occ.roles & 0x1u ) || occ.startLine < 0 || occ.symbol.empty() ) continue;   // definitions only
            const std::uint32_t defLine1 = std::uint32_t( occ.startLine ) + 1;                  // 0-based → 1-based
            bool matched = false;
            for( const LineDef& ld : defLines[ fid ] )
                if( ld.line == defLine1 ) { scipDef.emplace( occ.symbol, ld.id ); matched = true; break; }   // first def wins (id order)
            // a def occurrence whose exact line has no current symbol = the def MOVED (or the file changed):
            // a staleness signal. Count it (diagnostic only) so loadScipOverlay can surface the match ratio.
            if( !matched ) ++ov.defsUnmatched;
        }
    }

    // ripwire's OWN reference sites, keyed (fileId, line) → enclosing fromSymbol. This is the ground truth
    // the S5 gate matches SCIP ref occurrences against: a ripwire Reference's fromSymbol was attributed by
    // BYTE-SPAN containment at ingest (authoritative), so it is both immune to the old line-scan's
    // mis-attribution AND the freshness oracle — a SCIP ref line with no ripwire reference is a STALE line.
    // A line belongs to exactly one function body, so all refs on one (file,line) share one fromSymbol;
    // if two ever disagree (nested lambda edge case), keep the smallest NodeId for determinism.
    HashMap<std::uint64_t, NodeId> refEnclosing;
    refEnclosing.reserve( ing.references.size() );
    for( const Reference& rf : ing.references )
    {
        if( rf.fromSymbol == kNoNode ) continue;                                                 // file-scope ref: no enclosing symbol
        const std::uint64_t key = ( std::uint64_t( rf.fileId ) << 32 ) | std::uint64_t( rf.line );
        const auto it = refEnclosing.find( key );
        if( it == refEnclosing.end() ) refEnclosing.emplace( key, rf.fromSymbol );
        else if( rf.fromSymbol < it->second ) it->second = rf.fromSymbol;                        // deterministic tie-break
    }

    // (b) reference occurrences → precise edges. Enclosing symbol comes from ripwire's own parse at the
    // SAME (fileId, line); a SCIP ref line with no ripwire reference is STALE and DROPPED (S5 gate).
    for( const ScipDocument& doc : docs )
    {
        const std::uint32_t fid = resolveFileSuffix( ing, doc.relativePath );
        if( fid == UINT32_MAX ) continue;
        for( const ScipOccurrence& occ : doc.occurrences )
        {
            if( ( occ.roles & 0x1u ) || occ.startLine < 0 || occ.symbol.empty() ) continue;     // references only
            ++ov.refOccurrences;                                                                 // ALL ref occurrences seen (incl. external std::/library — diagnostic total, not the ratio denominator)
            const auto dit = scipDef.find( occ.symbol );
            if( dit == scipDef.end() ) continue;                                                 // target not a known def (external) — excluded from the S5 denominator, not a staleness signal
            const NodeId to = dit->second;
            ++internalOccurrences;                                                                // S5 denominator: occurrences the index claims point INTO this tree

            // S5 STALENESS GATE: enclosing symbol = ripwire's own reference at (fid, refLine1). If there is
            // no ripwire reference at that exact line, the SCIP ref line is stale → DROP (do not attach it to
            // whatever current symbol spans the stale line — that is the silent mis-attribution this fixes).
            const std::uint32_t refLine1 = std::uint32_t( occ.startLine ) + 1;
            const std::uint64_t key      = ( std::uint64_t( fid ) << 32 ) | std::uint64_t( refLine1 );
            const auto encIt = refEnclosing.find( key );
            if( encIt == refEnclosing.end() ) continue;                                          // stale ref line → drop, never mis-attribute
            const NodeId from = encIt->second;
            if( from == kNoNode || from == to ) continue;                                        // no enclosing / self-loop
            ++matchedOccurrencesPreDedup;                                                         // S5 numerator: matched PRE-dedup (one count per occurrence, not per unique edge)

            ov.coveredFrom.push_back( { from, ing.symbols[ to ].name, to } );                    // callee NAME + pinned target
        }
    }

    // sort + dedup coveredFrom by (from, calleeName, to) — deterministic and O(log n) to look up.
    std::sort( ov.coveredFrom.begin(), ov.coveredFrom.end(), []( const ScipCover& a, const ScipCover& b ) noexcept
               { if( a.from != b.from ) return a.from < b.from;
                 if( a.calleeName != b.calleeName ) return a.calleeName < b.calleeName;
                 return a.to < b.to; } );
    ov.coveredFrom.erase( std::unique( ov.coveredFrom.begin(), ov.coveredFrom.end(),
                          []( const ScipCover& a, const ScipCover& b ) noexcept
                          { return a.from == b.from && a.calleeName == b.calleeName && a.to == b.to; } ),
                          ov.coveredFrom.end() );

    // derive the (from,to)-sorted unique preciseEdges set (the provenance stamp source).
    ov.preciseEdges.reserve( ov.coveredFrom.size() );
    for( const ScipCover& c : ov.coveredFrom ) ov.preciseEdges.push_back( { c.from, c.to } );
    std::sort( ov.preciseEdges.begin(), ov.preciseEdges.end(), []( const ScipEdge& a, const ScipEdge& b ) noexcept
               { return a.from != b.from ? a.from < b.from : a.to < b.to; } );
    ov.preciseEdges.erase( std::unique( ov.preciseEdges.begin(), ov.preciseEdges.end(),
                           []( const ScipEdge& a, const ScipEdge& b ) noexcept { return a.from == b.from && a.to == b.to; } ),
                           ov.preciseEdges.end() );
    ov.edgesPinned = ov.preciseEdges.size();
    return ov;
}

// ---- top-level entry: path → overlay (degrade to empty on any failure) -----------------------------
// The ONE seam main.cpp calls. Missing / unreadable / corrupt / truncated / mismatched-tree index →
// exactly one DEGRADED_PATH_ALERT + an empty overlay (the pipeline proceeds name-based, byte-identical
// to a no---scip run). Never throws.
inline ScipOverlay loadScipOverlay( std::string_view path, const IngestResult& ing )
{
    const std::string             p( path );
    const std::vector<std::uint8_t> bytes = scipReadFile( p.c_str() );
    if( bytes.empty() )
    {
        DEGRADED_PATH_ALERT( "--scip: index missing or unreadable — proceeding name-based" );
        std::fprintf( stderr, "ripwire --scip: cannot read index '%s' — proceeding name-based\n", p.c_str() );
        return {};
    }

    std::vector<ScipDocument> docs;
    if( !scipDecodeIndex( bytes.data(), bytes.size(), docs ) )
    {
        DEGRADED_PATH_ALERT( "--scip: corrupt/truncated index — proceeding name-based" );
        std::fprintf( stderr, "ripwire --scip: corrupt or truncated index '%s' — proceeding name-based\n", p.c_str() );
        return {};
    }

    std::size_t internalOccurrences = 0, matchedOccurrencesPreDedup = 0;
    ScipOverlay ov = buildScipOverlay( ing, docs, internalOccurrences, matchedOccurrencesPreDedup );

    // Distinguish WRONG-TREE (the index maps to a totally different repo — no occurrence in any mappable
    // document) from SAME-TREE-BUT-STALE (occurrences WERE seen, but few/none matched current lines).
    // refOccurrences / defsUnmatched are 0 in the wrong-tree case (resolveFileSuffix matched nothing, or
    // the mapped docs had no occurrences); non-zero once we actually looked at occurrences in mapped files.
    const bool sawOccurrences = ov.refOccurrences > 0 || ov.defsUnmatched > 0 || ov.edgesPinned > 0;

    if( ov.empty() && !sawOccurrences )
    {
        // decoded fine, but nothing mapped AND no occurrence was even examined: the index describes a
        // DIFFERENT tree than the one ripwire parsed (wrong index / wrong root). Say so, proceed name-based.
        DEGRADED_PATH_ALERT( "--scip: index covers no parsed file/line — proceeding name-based" );
        std::fprintf( stderr, "ripwire --scip: index '%s' matched no parsed (file,line) — proceeding name-based\n", p.c_str() );
    }
    else if( sawOccurrences )
    {
        // S5 STALENESS SIGNAL: a one-line match RATIO whenever the index shares this tree. A low ratio or a
        // high defsUnmatched means the index is likely from an OLDER commit — stale ref lines that did not
        // match a current call site were DROPPED (not mis-attributed), so the prov="scip" edges that DID
        // land are trustworthy (fewer-but-correct, never a wrong one). Fires even when the overlay ends
        // EMPTY (def matched, every ref stale) — that is exactly when the operator most needs to know. It is
        // stderr-only + a deterministic function of (index, tree) at fixed precision, so the map on stdout
        // stays byte-identical and the det-gate holds.
        //
        // A4-F21 fix: the ratio used to be edgesPinned/refOccurrences — a denominator counting ALL ref
        // occurrences (mostly external std::/library symbols the index also records but ripwire can never
        // match — not a freshness signal) against a numerator DEDUPED to unique (from,to) edges (N call-
        // sites of the same callee from one enclosing symbol → 1 edge). Both effects only ever push the pct
        // DOWN, so a perfectly fresh index still read low. Now: denominator = internalOccurrences (ref
        // occurrences whose symbol resolved into scipDef — occurrences the index itself claims point INTO
        // this tree); numerator = matchedOccurrencesPreDedup (matched PRE-dedup, one count per occurrence,
        // the same unit as the denominator). External occurrences are reported separately, not folded into
        // either side of the ratio.
        const std::size_t externalOccurrences = ov.refOccurrences - internalOccurrences;
        const std::size_t denom = internalOccurrences ? internalOccurrences : 1;   // avoid /0; internalOccurrences==0 ⇒ 0%
        const int         pct   = internalOccurrences ? int( ( matchedOccurrencesPreDedup * 100 + denom / 2 ) / denom ) : 0;
        // append the older-commit hint ONLY when a staleness signal is present: refs were dropped (matched <
        // internal occurrences seen) or defs did not map. At a clean 100%/0-unmatched the hint would be misleading.
        const bool        stale = matchedOccurrencesPreDedup < internalOccurrences || ov.defsUnmatched > 0;
        std::fprintf( stderr,
            "ripwire: SCIP matched %d%% of occurrences (%zu/%zu), %zu defs unmatched, %zu external (unmatchable) occurrences skipped%s\n",
            pct, matchedOccurrencesPreDedup, internalOccurrences, ov.defsUnmatched, externalOccurrences,
            stale ? " — index may be from an older commit" : "" );
    }
    return ov;
}

}   // namespace rw
