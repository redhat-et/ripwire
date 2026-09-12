#pragma once
#include "infra/emit.h" // rw::emitTo / emitRaw / formatTo — THE emitter and its siblings


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
// Sites that never reach emission (a name with no in-repo def, a tier-3 decline, a self-only tier) produce
// NO row: they made no commitment, so there is nothing to audit. That is a floor on the row count, not a
// total, and the trailer says so — the `# dispositions` line beside it is the total (CallDisposition below).
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

#include <array>
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
    Binding      = 8,   // A4-R5 cross-language FFI alias
    External     = 9,   // Phase 5: the external-name VETO refused the site — no target, no edge (a bare name or
                        // receiver bound OUTSIDE the indexed tree: a builtin/stdlib name with no in-repo evidence,
                        // an external import binding, or a `super()` whose MRO left the tree). The row exists so
                        // the veto's OWN precision can be measured against SCIP's `@external`.
    Import       = 10   // an ES named-import binding pinned it: `import { f } from './m.js'` names the module and
                        // the export, so the target is READ, not chosen. Deliberately NOT folded into `Binding`:
                        // that label is scored as the A4-R5 cross-language FFI population, and quietly doubling
                        // its membership with a same-language, module-scoped mechanism would change what every
                        // existing reading of `binding=` means — the silent-redefinition failure this instrument
                        // exists to end. It is not `ReceiverRule` either: no receiver, no type, no include graph.
};
constexpr std::uint8_t kPinMechCount = 11;   // one past Import — the census trailer's per-mechanism counter width

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
        case PinMech::External:     return "external";
        case PinMech::Import:       return "import";
    }
    return "?";
}

// ── the CALL DISPOSITIONS — the census's conservation line ────────────────────────────────────────────
// The `C` rows are a FLOOR: a site that commits to nothing writes no row. The dispositions are the TOTAL.
// Every reference buildGraph's resolve loop takes up as a call (isResolvableCallReference below) ends in
// EXACTLY ONE bucket, counted when its loop iteration ends — so a `continue` that names no bucket lands in
// Unaccounted instead of vanishing. The census writer re-derives the population from ing.references and
// prints both; test/declinecheck.sh arm (F) asserts they balance. Three buckets are also header gauges
// (external=, unresolved=, declined=); the others have no header surface on purpose, each for the reason
// its comment gives.
enum class CallDisposition : std::uint8_t
{
    Bound             = 0,   // at least one non-self edge committed — exactly the sites with a non-external C row
    Self              = 1,   // every surviving target was the caller itself (recursion), or a SCIP-covered site whose
                             // targets were all self/out-of-range: the only symbol that could lose a caller is the caller
    External          = 2,   // a vetoExternal refusal — the Phase-5 veto, an ES import bound outside the tree, super() past the MRO, the C++ std:: guard — header external=
    Unresolved        = 3,   // an in-repo name the tool refused to answer (every def lang-filtered, an L3 known-indirect
                             // call, a shadowed/refused/renamed ES import) — header unresolved=
    Undefined         = 4,   // no in-repo definition of the name at all — a stdlib or third-party call, no gauge by design
    OtherRoot         = 5,   // multi-root only: every compatible definition lives in ANOTHER root and no include/import
                             // reaches it — external to this root, which is what that root's solo run would say
    QualifiedExternal = 6,   // a Rust `Scope::name()` call no in-repo member of `Scope` can answer (the H4 W3 guard)
    Declined          = 7,   // tier 3: two or more same-language candidates, none in the caller's file or directory, none
                             // pinned by a qualifier or a receiver rule — header declined=, answers' declined_calls=
    FileScope         = 8,   // a call outside every symbol (module / file scope): there is no caller node to hang an edge on
    Unaccounted       = 9    // an exit that named no bucket. Always a resolver bug: buildGraph raises a degrade alert
};
inline constexpr std::size_t kCallDispositionCount = 10;   // one past Unaccounted — size every per-disposition array with this

using CallDispositionCounts = std::array<std::size_t, kCallDispositionCount>;

// The census spelling of each bucket, indexed by its value: a declarative table (CONTRIBUTING §3), sized by the
// count so a new bucket without a name does not compile, and pinned at both ends so a reorder cannot misname one.
inline constexpr std::array<const char*, kCallDispositionCount> kCallDispositionNames = {
    "bound", "self", "external", "unresolved", "undefined", "other_root", "qualified_external", "declined", "file_scope", "unaccounted"
};
static_assert( std::string_view( kCallDispositionNames[ std::size_t( CallDisposition::Bound ) ] ) == "bound" );
static_assert( std::string_view( kCallDispositionNames[ std::size_t( CallDisposition::Declined ) ] ) == "declined" );
static_assert( std::string_view( kCallDispositionNames[ std::size_t( CallDisposition::Unaccounted ) ] ) == "unaccounted" );

// The POPULATION the dispositions partition: a reference the call graph could carry. Inheritance, doc-mention
// and HAS-A references are other relations with their own passes; read/write/import/type use-sites live only in
// the use-site index (ABS-3). One predicate, read by the resolve loop's filter AND by the census writer's
// re-derivation, so the two cannot disagree about what a call is — only about what happened to one.
inline bool isResolvableCallReference( const Reference& r ) noexcept
{
    return !r.isInherit && !r.isDocLink && !r.isCompose && ( r.role == RefRole::Call || r.role == RefRole::Macro );
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
    kPinFlagLocality  = 1u << 4,   // 'l' — the S6-C block compacted the tier on this site
    kPinFlagImport    = 1u << 5    // 'm' — an ES named-import binding named the target module + export
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

    // ---- the conservation line's buckets (buildGraph copies Graph::callDispositions in when armed) --------
    CallDispositionCounts      dispositions{};

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

// The Phase-4 marker predicate (docs/EVALS.md "Phase 4"): the S6-C compaction left exactly ONE non-self
// survivor and nothing stronger decided the site — a prior's guess is about to ship as a confident edge.
// buildGraph counts it into Graph::locPinOut (serialized as lpin="K" / locality_pinned=N) and classifyPin
// labels the census row `locality` through this SAME function, so the shipped marker and the census name one
// population by construction rather than by two copies of a four-term condition.
inline bool isLocalityPin( bool scipPinned, bool bindingPinned, std::size_t nonSelfTargets, bool locality ) noexcept
{
    return !scipPinned && !bindingPinned && nonSelfTargets == 1 && locality;
}

inline PinDecision classifyPin( bool scipPinned, bool bindingPinned, bool importPinned, std::size_t nonSelfTargets,
                                bool qualified, bool narrowed, bool cone, bool arity, bool locality ) noexcept
{
    std::uint8_t fl = 0;
    if( qualified )   { fl |= kPinFlagQualified; }
    if( narrowed )    { fl |= kPinFlagNarrowed; }
    if( cone )        { fl |= kPinFlagCone; }
    if( arity )       { fl |= kPinFlagArity; }
    if( locality )    { fl |= kPinFlagLocality; }
    if( importPinned ){ fl |= kPinFlagImport; }

    PinMech m = PinMech::Unique;
    if( scipPinned )              { m = PinMech::Scip; }
    else if( bindingPinned )      { m = PinMech::Binding; }
    // An import pin reads ONE target out of a module's export table, so it can never be a split; it sits
    // beside Binding because both are binding-table resolutions, above Split for the same reason Binding is.
    else if( importPinned )       { m = PinMech::Import; }
    else if( nonSelfTargets > 1 ) { m = PinMech::Split; }
    else if( isLocalityPin( scipPinned, bindingPinned, nonSelfTargets, locality ) ) { m = PinMech::Locality; }
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
    if( fl & kPinFlagImport )    { out.push_back( 'm' ); }
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
// The per-symbol census identity, resolved ONCE per symbol and reused — a row-by-row rebuild would re-make
// the same strings thousands of times over a real corpus, and every row of a census names two of them.
inline std::vector<std::string> pinCensusIdentities( const IngestResult& ing, std::string_view root )
{
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
    return canon;
}

inline const char* pinCensusIdOf( const std::vector<std::string>& canon, NodeId n ) noexcept
{
    return ( n < canon.size() ) ? canon[ n ].c_str() : "?";
}

// `C` rows — one per decided call site; returns the per-mechanism tally the summary line prints.
inline void writePinCensusDecisionRows( std::FILE* f, const PinCensus& pc, const std::vector<std::string>& canon, std::size_t ( &mechCount )[ kPinMechCount ] )
{
    for( std::size_t i = 0; i < pc.rows(); ++i )
    {
        const std::uint8_t m = pc.mech[ i ];
        if( m < kPinMechCount )
        {
            // The bound was a literal 9, which silently excluded `external` — the trailer printed
            // `external=0` while the rows above it said otherwise, i.e. the summary disagreed with its own
            // file. Derived from the roster now, so a mechanism added below cannot be dropped again.
            ++mechCount[ m ];
        }
        rw::emitTo( f, "C\t{}\t{}\t{}\t{}\t{}\t{}\t", pinMechName( m ), unsigned( pc.preTier[ i ] ), unsigned( pc.postReal[ i ] ),
                      pinFlagString( pc.flags[ i ] ).c_str(), pinCensusIdOf( canon, pc.fromSym[ i ] ), pc.nameAt( pc.nameOff[ i ] ) );
        const std::uint32_t end = pc.rowEnd( i );
        for( std::uint32_t t = pc.tgtStart[ i ]; t < end; ++t )
        {
            rw::emitTo( f, "{}{}", ( t > pc.tgtStart[ i ] ) ? "|" : "", pinCensusIdOf( canon, pc.tgtIds[ t ] ) );
        }
        rw::emitTo( f, "\t{}\n", unsigned( pc.line[ i ] ) );
    }
}

// `O` rows — the SCIP oracle; a sentinel row prints `@external` / `@nondef` and carries no target ids.
inline void writePinCensusOracleRows( std::FILE* f, const PinCensus& pc, const std::vector<std::string>& canon )
{
    for( std::size_t i = 0; i < pc.oraRows(); ++i )
    {
        rw::emitTo( f, "O\t{}\t{}\t", pinCensusIdOf( canon, pc.oraFrom[ i ] ), pc.nameAt( pc.oraNameOff[ i ] ) );
        const std::uint8_t sentinel = ( i < pc.oraSentinel.size() ) ? pc.oraSentinel[ i ] : std::uint8_t( 0 );
        if( sentinel != 0 )
        {
            std::fputs( sentinel == kScipNonDefExternal ? "@external" : "@nondef", f );
        }
        const std::uint32_t end = pc.oraRowEnd( i );
        for( std::uint32_t t = pc.oraStart[ i ]; t < end; ++t )
        {
            rw::emitTo( f, "{}{}", ( t > pc.oraStart[ i ] ) ? "|" : "", pinCensusIdOf( canon, pc.oraTo[ t ] ) );
        }
        std::fputc( '\n', f );
    }
}

// `S` rows — the definition universe, one per symbol (v2).
inline void writePinCensusSymbolRows( std::FILE* f, const IngestResult& ing, const std::vector<std::string>& canon )
{
    for( std::size_t i = 0; i < ing.symbols.size(); ++i )
    {
        rw::emitTo( f, "S\t{}\t{}\t{}\n", canon[ i ].c_str(), symTag( ing.symbols[ i ].kind ), unsigned( ing.symbols[ i ].line ) );
    }
}

// `root` is the run's single root argument (empty on a multi-root run), so the path segment is spelled
// exactly as the map's `p=`/`id=`. Returns false if the file cannot be opened.
inline bool writePinCensus( const char* path, const PinCensus& pc, const IngestResult& ing, std::string_view root )
{
    std::FILE* f = std::fopen( path, "wb" );
    if( f == nullptr )
    {
        return false;
    }
    const std::vector<std::string> canon = pinCensusIdentities( ing, root );

    rw::emitRaw( f, "# ripwire pin-census v2\tC=kind\\tmech\\tpre\\tpost\\tflags\\tcaller_id\\tcallee\\ttargets(|-sep)\\tline\n" );
    rw::emitRaw( f, "# line is the 1-based call-site line in the caller's file (v2, appended LAST so v1 readers are unchanged):\n" );
    rw::emitRaw( f, "#   the key a SCIP occurrence joins on, so a coverage loss can be classified per site instead of guessed.\n" );
    rw::emitRaw( f, "# O rows (only under --scip) are the SCIP oracle: O\\tcaller_id\\tcallee\\ttargets(|-sep)\n" );
    rw::emitRaw( f, "#   a target of @external (a builtin / another package) or @nondef (an in-index parameter, local or\n" );
    rw::emitRaw( f, "#   attribute ripwire extracts no symbol for) means SCIP resolved the site to something that is NOT a\n" );
    rw::emitRaw( f, "#   ripwire definition — the index spoke, and disagrees with every in-repo target the C row names.\n" );
    rw::emitRaw( f, "# S rows (v2) are the DEFINITION universe, one per symbol: S\\tid\\tkind\\tline — the def side of the\n" );
    rw::emitRaw( f, "#   SCIP join (buildScipOverlay maps a SCIP definition to a symbol by exact file+line), listed in full.\n" );
    rw::emitRaw( f, "# ids are path::scope::name#NODEID (path::name#NODEID when unscoped) — NEVER a bare name: the\n" );
    rw::emitRaw( f, "#   handle is the join key and is stable across runs of one binary on one corpus, --scip or not.\n" );
    rw::emitRaw( f, "# mech: unique|qualified|receiver-rule|cone|arity|locality|split|scip|binding|external|import — the stage that DECIDED the site\n" );
    rw::emitRaw( f, "#   external (Phase 5): the external-name VETO refused the site — an EMPTY target list, no edge; the row is\n" );
    rw::emitRaw( f, "#   scored right iff SCIP's answer is @external (the name was bound outside the indexed tree).\n" );
    rw::emitRaw( f, "# flags: q=qualified r=receiver-rule c=cha-cone a=arity l=locality-tiebreak-fired m=es-import-binding (every stage that fired)\n" );
    rw::emitRaw( f, "# rows are a FLOOR on call sites, not a total: a site that produced no edge (name undefined in-repo,\n" );
    rw::emitRaw( f, "#   tier-3 decline, self-only tier) made no commitment and is deliberately absent.\n" );
    rw::emitRaw( f, "# the TOTAL is the `# dispositions` line above the summary: calls= is re-derived from the references, and\n" );
    rw::emitRaw( f, "#   every call lands in exactly one of bound|self|external|unresolved|undefined|other_root|qualified_external|\n" );
    rw::emitRaw( f, "#   declined|file_scope|unaccounted, which must sum to it; bound == the non-external C rows, unaccounted == 0.\n" );

    std::size_t mechCount[ kPinMechCount ] = {};
    writePinCensusDecisionRows( f, pc, canon, mechCount );
    writePinCensusOracleRows( f, pc, canon );
    writePinCensusSymbolRows( f, ing, canon );
    // calls= is counted HERE, off the references, never summed from the buckets it is checked against: a sum of
    // the buckets would balance by construction and catch nothing.
    std::size_t callCount = 0;
    for( const Reference& r : ing.references )
    {
        if( isResolvableCallReference( r ) )
        {
            ++callCount;
        }
    }
    rw::emitTo( f, "# dispositions calls={}", callCount );
    for( std::size_t d = 0; d < kCallDispositionCount; ++d )
    {
        rw::emitTo( f, " {}={}", kCallDispositionNames[ d ], pc.dispositions[ d ] );
    }
    std::fputc( '\n', f );
    rw::emitTo( f, "# summary rows={} oracle_rows={} symbols={}", pc.rows(), pc.oraRows(), ing.symbols.size() );
    for( std::uint8_t m = 0; m < kPinMechCount; ++m )
    {
        rw::emitTo( f, " {}={}", pinMechName( m ), mechCount[ m ] );
    }
    std::fputc( '\n', f );
    std::fclose( f );
    return true;
}

}   // namespace rw
