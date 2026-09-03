#pragma once

// pincensus.h — the S6-C SILENT-PIN CENSUS: an eval-only, flag-gated record of WHICH mechanism decided
// each resolved call site, and WHICH target it decided on, by canonical identity.
//
// ── why a new instrument, and not a new grouping of the old one ──────────────────────────────────────
// The map serializes a call edge as `<c n="NAME"/>` — a callee NAME, no target identity. Every existing
// oracle harness (bench/scip_amb_precision.py) therefore joins ripwire's edges to SCIP's BY NAME, and a
// site the S6-C locality tie-break pinned to the WRONG same-name definition is indistinguishable from one
// it pinned correctly: both render as one `<c n="X"/>`, SCIP's replacement carries the same name, and the
// bucket scores 1.0 by construction. That is not a grouping bug the harness could fix; the identity the
// join needs is simply not in the output. So the census emits it — once, off to the side, under a flag.
//
// ── what is recorded ────────────────────────────────────────────────────────────────────────────────
// One `C` row per DECIDED call site (a reference that reached edge emission with ≥1 non-self target):
// the caller's canonical id, the callee name, the MECHANISM that decided it, the tier width entering the
// locality tie-break, the number of surviving targets, a provenance flag string, and every surviving
// target's canonical id. Under `--scip` an `O` row is also emitted per SCIP-covered call site, carrying
// the index's own pinned target(s) in the SAME canonical-id space — so the census file holds both sides
// of the join and no protobuf reader is needed downstream.
//
// Sites that never reach emission (a name with no in-repo def, a tier-3 non-unique drop, a self-only
// tier) produce NO row: they made no commitment, so there is nothing to audit. That is a floor on the
// row count, not a total, and the trailer says so.
//
// ── shape (G2) ──────────────────────────────────────────────────────────────────────────────────────
// SoA over parallel vectors keyed by row index, 32-bit handles throughout, callee names in one flat pool
// addressed by offset, targets in one flat CSR-style array addressed by a per-row start (the row's end is
// the next row's start, the last row's is the array size). No per-row allocation, no node/edge objects,
// no generic graph container. `Symbol` is untouched, so no build tree changes size.
//
// Populated ONLY when buildGraph is asked for it; empty otherwise, and the writer is the only consumer.
// The flagless map is byte-identical either way — the census is a side file, never a change to stdout.

#include "model.h"
#include "resolve.h"        // canonicalIdForEmit — the census id must be the map's id= spelling
#include "scipoverlay.h"    // kScipNonDefExternal / kScipNonDefInIndex — the O-row sentinel kinds

#include <cstdint>
#include <cstdio>
#include <string>
#include <string_view>
#include <vector>

namespace rw
{

// The mechanism that DECIDED a call site — the headline label. Ordered by specificity of the evidence
// behind it: an explicit qualifier is the strongest, a locality prior the weakest thing that still
// produces a confident edge, and `Split` means nothing decided (the honest 1/k spray that `amb=` counts).
enum class PinMech : std::uint8_t
{
    Unique       = 0,   // the tier held one candidate before any narrowing fired — never ambiguous
    Qualified    = 1,   // an explicit `A::b` qualifier resolved it (canonical)
    ReceiverRule = 2,   // P2-D Rule 1/2/2b/3 — this/self, a typed var, a field's type, or an include narrow
    Cone         = 3,   // B2.1 CHA-lite: the receiver's inheritance cone excluded the rest
    Arity        = 4,   // B2.2: every other candidate was a provably-wrong overload
    Locality     = 5,   // S6-C: the canonical-id segment prefix decided it — THE POPULATION UNDER AUDIT
    Split        = 6,   // >1 non-self survivor: the 1/k split `amb=` counts (nothing decided)
    Scip         = 7,   // a SCIP index pinned it (only under --scip)
    Binding      = 8    // A4-R5 cross-language FFI alias
};

inline const char* pinMechName( std::uint8_t m ) noexcept
{
    switch( PinMech( m ) )
    {
        case PinMech::Unique:       return "unique";
        case PinMech::Qualified:    return "qualified";
        case PinMech::ReceiverRule: return "receiver-rule";
        case PinMech::Cone:         return "cone";
        case PinMech::Arity:        return "arity";
        case PinMech::Locality:     return "locality";
        case PinMech::Split:        return "split";
        case PinMech::Scip:         return "scip";
        case PinMech::Binding:      return "binding";
    }
    return "?";
}

// Per-row provenance bits — every narrowing stage that FIRED on this site, not just the deciding one. A
// site S6-C narrowed 3→2 is labelled `split` (it is still ambiguous and still counted in `amb=`), and
// without these bits the fact that locality touched it at all would be invisible. Cheap, and it keeps the
// headline label from having to be two things at once.
enum PinFlagBit : std::uint8_t
{
    kPinFlagQualified = 1u << 0,   // 'q'
    kPinFlagNarrowed  = 1u << 1,   // 'r'
    kPinFlagCone      = 1u << 2,   // 'c'
    kPinFlagArity     = 1u << 3,   // 'a'
    kPinFlagLocality  = 1u << 4    // 'l' — the S6-C block compacted the tier on this site
};

struct PinCensus
{
    // ---- `C` rows: one per decided call site, parallel vectors -------------------------------------
    std::vector<NodeId>        fromSym;     // caller symbol id
    std::vector<std::uint32_t> nameOff;     // offset into namePool of this row's callee name (NUL-terminated)
    std::vector<std::uint32_t> tgtStart;    // start index into tgtIds; row i's end is tgtStart[i+1] or tgtIds.size()
    std::vector<std::uint8_t>  mech;        // PinMech
    std::vector<std::uint8_t>  flags;       // PinFlagBit mask
    std::vector<std::uint16_t> preTier;     // tier width entering S6-C (saturating at 65535)
    std::vector<std::uint16_t> postReal;    // non-self survivors emitted (saturating at 65535)
    std::vector<NodeId>        tgtIds;      // flat surviving-target ids, ascending within a row
    std::vector<std::uint32_t> line;        // 1-based call-site line (Reference::line) — v2: the line-level join key
    std::string                namePool;    // flat NUL-separated callee names

    // ---- `O` rows: SCIP's covered call sites, same id space (only under --scip) --------------------
    std::vector<NodeId>        oraFrom;
    std::vector<std::uint32_t> oraNameOff;  // into namePool (shared — the names are the same strings)
    std::vector<std::uint32_t> oraStart;    // into oraTo
    std::vector<NodeId>        oraTo;
    std::vector<std::uint8_t>  oraSentinel; // 0 = in-repo target(s) in oraTo; kScipNonDefExternal / kScipNonDefInIndex =
                                            //   SCIP resolved the site to something that is not a ripwire definition
                                            //   (no oraTo entries; the writer prints `@external` / `@nondef`)

    bool armed = false;                     // false ⇒ nothing was recorded and nothing will be written

    std::uint32_t internName( std::string_view n )
    {
        const std::uint32_t off = std::uint32_t( namePool.size() );
        namePool.append( n );
        namePool.push_back( '\0' );
        return off;
    }

    const char* nameAt( std::uint32_t off ) const noexcept { return namePool.c_str() + off; }

    void addRow( NodeId from, std::string_view callee, PinMech m, std::uint8_t fl,
                 std::size_t pre, std::size_t post, std::uint32_t siteLine )
    {
        fromSym.push_back( from );
        line.push_back( siteLine );
        nameOff.push_back( internName( callee ) );
        tgtStart.push_back( std::uint32_t( tgtIds.size() ) );
        mech.push_back( std::uint8_t( m ) );
        flags.push_back( fl );
        preTier.push_back( std::uint16_t( pre > 65535 ? 65535 : pre ) );
        postReal.push_back( std::uint16_t( post > 65535 ? 65535 : post ) );
    }

    void addOracleRow( NodeId from, std::string_view callee, std::uint8_t sentinel = 0 )
    {
        oraFrom.push_back( from );
        oraNameOff.push_back( internName( callee ) );
        oraStart.push_back( std::uint32_t( oraTo.size() ) );
        oraSentinel.push_back( sentinel );
    }

    std::size_t rows() const noexcept { return fromSym.size(); }
    std::size_t oraRows() const noexcept { return oraFrom.size(); }
    // CSR end of row i: the next row's start, or the flat array's size for the last row. Stated ONCE for
    // both target arrays — two copies of this two-line rule is exactly how the two drift apart.
    static std::uint32_t csrEnd( const std::vector<std::uint32_t>& start, std::size_t flatSize, std::size_t i ) noexcept
    {
        return ( i + 1 < start.size() ) ? start[ i + 1 ] : std::uint32_t( flatSize );
    }
    std::uint32_t rowEnd( std::size_t i ) const noexcept    { return csrEnd( tgtStart, tgtIds.size(), i ); }
    std::uint32_t oraRowEnd( std::size_t i ) const noexcept { return csrEnd( oraStart, oraTo.size(), i ); }
};

// The mechanism/flags decision, as ONE pure function of the stage outcomes rather than twenty lines
// inside buildGraph's resolve loop — so the precedence rule is stated in a single readable place and
// can be reasoned about (and, when a phase-3 fix moves it, changed) without reading the resolver.
//
// Precedence is "the LAST stage that narrowed", with one deliberate override: a site still holding >1
// non-self target is `split` whatever touched it, because that is precisely the site `amb=` counts, and
// labelling it by the stage that half-narrowed it would repeat the conflation this instrument exists to
// end. Everything that fired survives in the flag bits regardless.
struct PinDecision { PinMech mech; std::uint8_t flags; };

inline PinDecision classifyPin( bool scipPinned, bool bindingPinned, std::size_t nonSelfTargets,
                                bool qualified, bool narrowed, bool cone, bool arity, bool locality ) noexcept
{
    std::uint8_t fl = 0;
    if( qualified ) { fl |= kPinFlagQualified; }
    if( narrowed )  { fl |= kPinFlagNarrowed; }
    if( cone )      { fl |= kPinFlagCone; }
    if( arity )     { fl |= kPinFlagArity; }
    if( locality )  { fl |= kPinFlagLocality; }

    PinMech m = PinMech::Unique;
    if( scipPinned )              { m = PinMech::Scip; }
    else if( bindingPinned )      { m = PinMech::Binding; }
    else if( nonSelfTargets > 1 ) { m = PinMech::Split; }
    else if( locality )           { m = PinMech::Locality; }
    else if( arity )              { m = PinMech::Arity; }
    else if( cone )               { m = PinMech::Cone; }
    else if( narrowed )           { m = PinMech::ReceiverRule; }
    else if( qualified )          { m = PinMech::Qualified; }
    return { m, fl };
}

// Render a row's flag mask as the stable letter string the census documents. Fixed order, so the file
// is byte-stable run to run.
inline std::string pinFlagString( std::uint8_t fl )
{
    std::string out;
    if( fl & kPinFlagQualified ) { out.push_back( 'q' ); }
    if( fl & kPinFlagNarrowed )  { out.push_back( 'r' ); }
    if( fl & kPinFlagCone )      { out.push_back( 'c' ); }
    if( fl & kPinFlagArity )     { out.push_back( 'a' ); }
    if( fl & kPinFlagLocality )  { out.push_back( 'l' ); }
    if( out.empty() )            { out.push_back( '-' ); }
    return out;
}

// THE CENSUS IDENTITY — `path::scope::name#NODEID`, and why it is NOT simply the map's `id=`.
//
// `canonicalIdForEmit` degrades an UNSCOPED symbol (a free function, a module-level def) to its BARE NAME
// — `handler`, not `alpha.cpp::handler`. That degrade is right for the map, where `id=` is a display
// handle, and catastrophic here: two free functions named `handler` in sibling files would both print
// `handler`, and a census whose join key is a bare name has silently reproduced the exact name-keyed
// blindness it was built to escape. (Found by test/pincensuscheck.sh arm (G) against test/scipfix, whose
// `handler` defs are free functions — the fixture that made the degrade visible before any corpus did.)
//
// So the census spells an unscoped symbol `path::name` and appends `#NODEID` to every identity. The
// numeric handle is the exact key: NodeIds are assigned from the SORTED crawl during ingest, before any
// resolution, so the same binary on the same corpus assigns the same handle whether or not `--scip` is
// given — which is what lets a plain census (the decisions) join to a `--scip` census (the oracle) at
// definition granularity, including between two same-named overloads in ONE file that share a canonical
// string. Arm (I) of the gate is that cross-run stability, asserted rather than assumed. The canonical
// prefix is kept because a human, a `grep`, and SCIP's own document paths all read it.
//
// `root` is the run's single root argument (empty on a multi-root run), so the path segment is spelled
// exactly as the map's `p=`/`id=`. Returns false if the file cannot be opened.
inline bool writePinCensus( const char* path, const PinCensus& pc, const IngestResult& ing, std::string_view root )
{
    std::FILE* f = std::fopen( path, "wb" );
    if( f == nullptr )
    {
        return false;
    }
    // Resolved once per symbol and reused — a row-by-row rebuild would re-make the same strings thousands
    // of times over a real corpus, and every row of a census names two of them.
    std::vector<std::string> canon( ing.symbols.size() );
    for( std::size_t i = 0; i < ing.symbols.size(); ++i )
    {
        const Symbol& s = ing.symbols[ i ];
        const std::string rel( relForHash( ing.files[ s.fileId ], root ) );
        canon[ i ].reserve( rel.size() + s.scope.size() + s.name.size() + 16 );
        canon[ i ].append( rel ).append( "::" );
        if( !s.scope.empty() )
        {
            canon[ i ].append( s.scope ).append( "::" );
        }
        canon[ i ].append( s.name ).append( "#" ).append( std::to_string( i ) );
    }
    const auto idOf = [ & ]( NodeId n ) -> const char*
    {
        return ( n < canon.size() ) ? canon[ n ].c_str() : "?";
    };

    std::fprintf( f, "# ripwire pin-census v2\tC=kind\\tmech\\tpre\\tpost\\tflags\\tcaller_id\\tcallee\\ttargets(|-sep)\\tline\n" );
    std::fprintf( f, "# line is the 1-based call-site line in the caller's file (v2, appended LAST so v1 readers are unchanged):\n" );
    std::fprintf( f, "#   the key a SCIP occurrence joins on, so a coverage loss can be classified per site instead of guessed.\n" );
    std::fprintf( f, "# O rows (only under --scip) are the SCIP oracle: O\\tcaller_id\\tcallee\\ttargets(|-sep)\n" );
    std::fprintf( f, "#   a target of @external (a builtin / another package) or @nondef (an in-index parameter, local or\n" );
    std::fprintf( f, "#   attribute ripwire extracts no symbol for) means SCIP resolved the site to something that is NOT a\n" );
    std::fprintf( f, "#   ripwire definition — the index spoke, and disagrees with every in-repo target the C row names.\n" );
    std::fprintf( f, "# S rows (v2) are the DEFINITION universe, one per symbol: S\\tid\\tkind\\tline — the def side of the\n" );
    std::fprintf( f, "#   SCIP join (buildScipOverlay maps a SCIP definition to a symbol by exact file+line), listed in full.\n" );
    std::fprintf( f, "# ids are path::scope::name#NODEID (path::name#NODEID when unscoped) — NEVER a bare name: the\n" );
    std::fprintf( f, "#   handle is the join key and is stable across runs of one binary on one corpus, --scip or not.\n" );
    std::fprintf( f, "# mech: unique|qualified|receiver-rule|cone|arity|locality|split|scip|binding — the stage that DECIDED the site\n" );
    std::fprintf( f, "# flags: q=qualified r=receiver-rule c=cha-cone a=arity l=locality-tiebreak-fired (every stage that fired)\n" );
    std::fprintf( f, "# rows are a FLOOR on call sites, not a total: a site that produced no edge (name undefined in-repo,\n" );
    std::fprintf( f, "#   tier-3 non-unique drop, self-only tier) made no commitment and is deliberately absent.\n" );

    std::size_t mechCount[ 9 ] = { 0, 0, 0, 0, 0, 0, 0, 0, 0 };
    for( std::size_t i = 0; i < pc.rows(); ++i )
    {
        const std::uint8_t m = pc.mech[ i ];
        if( m < 9 )
        {
            ++mechCount[ m ];
        }
        std::fprintf( f, "C\t%s\t%u\t%u\t%s\t%s\t%s\t", pinMechName( m ), unsigned( pc.preTier[ i ] ), unsigned( pc.postReal[ i ] ),
                      pinFlagString( pc.flags[ i ] ).c_str(), idOf( pc.fromSym[ i ] ), pc.nameAt( pc.nameOff[ i ] ) );
        const std::uint32_t end = pc.rowEnd( i );
        for( std::uint32_t t = pc.tgtStart[ i ]; t < end; ++t )
        {
            std::fprintf( f, "%s%s", ( t > pc.tgtStart[ i ] ) ? "|" : "", idOf( pc.tgtIds[ t ] ) );
        }
        std::fprintf( f, "\t%u\n", unsigned( pc.line[ i ] ) );
    }
    for( std::size_t i = 0; i < pc.oraRows(); ++i )
    {
        std::fprintf( f, "O\t%s\t%s\t", idOf( pc.oraFrom[ i ] ), pc.nameAt( pc.oraNameOff[ i ] ) );
        const std::uint8_t sentinel = ( i < pc.oraSentinel.size() ) ? pc.oraSentinel[ i ] : std::uint8_t( 0 );
        if( sentinel != 0 )
        {
            std::fputs( sentinel == kScipNonDefExternal ? "@external" : "@nondef", f );
        }
        const std::uint32_t end = pc.oraRowEnd( i );
        for( std::uint32_t t = pc.oraStart[ i ]; t < end; ++t )
        {
            std::fprintf( f, "%s%s", ( t > pc.oraStart[ i ] ) ? "|" : "", idOf( pc.oraTo[ t ] ) );
        }
        std::fputc( '\n', f );
    }
    for( std::size_t i = 0; i < ing.symbols.size(); ++i )
    {
        std::fprintf( f, "S\t%s\t%s\t%u\n", canon[ i ].c_str(), symTag( ing.symbols[ i ].kind ), unsigned( ing.symbols[ i ].line ) );
    }
    std::fprintf( f, "# summary rows=%zu oracle_rows=%zu symbols=%zu", pc.rows(), pc.oraRows(), ing.symbols.size() );
    for( std::uint8_t m = 0; m < 9; ++m )
    {
        std::fprintf( f, " %s=%zu", pinMechName( m ), mechCount[ m ] );
    }
    std::fputc( '\n', f );
    std::fclose( f );
    return true;
}

}   // namespace rw
