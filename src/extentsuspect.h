#pragma once
// extentsuspect.h — THE EXTENT/SCOPE HONESTY DETECTOR (0.6.0). Gates: test/extentcheck.sh (the surfaces, on real
// parses) and test/extentsuspect_unit.cpp (each rule, on synthetic extents).
//
// WHAT IT ANSWERS. A definition row states three things the parser INFERRED: its extent (where the definition
// starts, where its body starts, where it ends), its scope (`C::`), and — through the capture pattern that matched —
// its kind. When tree-sitter RECOVERS from input it cannot parse, all three can be wrong while each still looks
// well-formed. Measured on a large C++ corpus (reproduced with fresh identifiers in test/extentfix): a run of
// structs whose last member is a macro invocation with no semicolon let one struct's body swallow 5,000 lines;
// 331 of one file's 343 definition ids were filed under that struct, free functions came out as `method`, and one
// 14-line function reported cx=749 ccx=920 because a swallowed struct had become its RETURN TYPE. No row said so.
//
// DISCLOSURE, NEVER DELETION. Nothing here drops a row or rewrites a fact. It classifies each definition against
// four containment rules and records which failed (Symbol::extentSuspect); the surfaces print the reasons as
// extent_suspect="…" and --hotspots keeps a flagged definition's complexity out of its ranking. A zero means "every
// rule held", never "the extent is right" — the rules can only catch contradictions the facts themselves expose.
//
// THE RULES (bit order = the printed order):
//   name  (R1) a definition's own name lies outside its own signature span [start, bodyStart) — the span was
//              adopted from another node. Sections are exempt: a heading or config key is an identity key, and
//              markdown's whole-file node names EOF on purpose (ingest_docs.h).
//   head  (R3) C family only: a definition lies in a BODIED definition's signature span, wholly BEFORE that
//              definition's own name — its return-type position. Valid C++ defines nothing there (C allows
//              `struct S {…} f() {…}`, flagged as the same shape); a derailed parse produces exactly this when a
//              swallowing struct becomes a later function's return type. The name bound is measured, not
//              assumed: valid C++ does put definitions in a signature AFTER the name (a local struct inside a
//              lambda in a constructor's member-initializer list), and the unbounded rule flagged them. The whole
//              top-level extent tree holding a violation is marked, because the containers' extents are the
//              corrupted ones and every scope inside them was derived through them.
//   scope (R2) C++ only: a bodied definition filed under C:: while its nearest enclosing class is a DIFFERENT
//              class, and C is a class defined in the same file. tree-sitter-cpp refuses a qualified member
//              definition inside another class's body, and ripwire derives in-class scope from the same tree the
//              extents come from, so no input the vendored grammar accepts reaches this today; it guards the join
//              between the two, and test/extentsuspect_unit.cpp pins it.
//   error (R4) the parse recovered this definition's container or kind — RawDef::recovered, set at extraction
//              (ingest_names.h parseRecoveredBits): a class whose own body holds an error inside an ERROR node, or
//              a scopeless C++ method inside one — plus every definition inside such a class. A clean class inside
//              a recovered file is not marked: its body parsed, so its members carry the scope the source gave.
//
// COST. One linear pass per file over the spans ingest_model.h's DefSpanIndex already sorted (startByte ascending,
// endByte descending): a stack of open ancestors, amortized O(n). R2's same-file class lookup sorts the file's
// C++ class names (n log n over class definitions only). The extraction bit behind `error` is computed only in a
// file whose root reports an error. Pure and deterministic: the output depends on the input order alone.

#include "model.h"
#include "infra/Diagnostics.h"
#include "infra/sortutil.h"   // svLess — R2's class-name table sorts and searches in byte order, never through operator<

#include <algorithm>
#include <array>
#include <cstddef>
#include <cstdint>
#include <span>
#include <string_view>
#include <vector>

namespace rw::extent
{

// ── the reason bits (Symbol::extentSuspect), in printed order ─────────────────────────────────────────────────
inline constexpr std::uint8_t kSuspectName  = 1u << 0;
inline constexpr std::uint8_t kSuspectHead  = 1u << 1;
inline constexpr std::uint8_t kSuspectScope = 1u << 2;
inline constexpr std::uint8_t kSuspectError = 1u << 3;

// ── the extraction bits (RawDef::recovered) ───────────────────────────────────────────────────────────────────
inline constexpr std::uint8_t kRecoveredContainer = 1u << 0;   // a class whose body holds an error, inside an ERROR node
inline constexpr std::uint8_t kRecoveredOrphan    = 1u << 1;   // a scopeless C++ method inside an ERROR node

// Every subset of the four reasons, spelled once: index = the bit set. Comma-joined in bit order, so a reader can
// match one reason with a substring test and two runs can never disagree on the spelling.
inline constexpr std::array<std::string_view, 16> kExtentSuspectReasonTable =
{
    "",            "name",             "head",             "name,head",
    "scope",       "name,scope",       "head,scope",       "name,head,scope",
    "error",       "name,error",       "head,error",       "name,head,error",
    "scope,error", "name,scope,error", "head,scope,error", "name,head,scope,error",
};

inline std::string_view extentSuspectReasons( std::uint8_t bits ) noexcept
{
    return kExtentSuspectReasonTable[ bits & 0x0Fu ];
}

// ── the two membership tables the rules key on (declarative, one lookup shape) ──────────────────────────────
inline constexpr std::array<SymKind, 3> kExtentClassKinds = { SymKind::Class, SymKind::Struct, SymKind::Interface };
inline constexpr std::array<Lang, 3>    kHeadRuleLangs    = { Lang::C, Lang::Cpp, Lang::ObjC };   // R3's C family

template<class T, std::size_t N>
constexpr bool inSet( const std::array<T, N>& set, T value ) noexcept
{
    return std::find( set.begin(), set.end(), value ) != set.end();
}

// One definition's extent facts, as the classifier reads them. The views borrow the caller's Symbol strings.
struct ExtentDef
{
    std::uint32_t    startByte  = 0;
    std::uint32_t    sigEndByte = 0;   // the body's start, or endByte for a bodyless definition
    std::uint32_t    endByte    = 0;
    std::uint32_t    nameByte   = 0;
    SymKind          kind       = SymKind::Other;
    Lang             lang       = Lang::Unknown;
    std::uint8_t     recovered  = 0;
    std::string_view name;
    std::string_view scope;
};

inline constexpr std::uint32_t kNoIndex = 0xFFFFFFFFu;

// Per-file working storage, reused across files so the pass allocates once per ingest rather than once per file.
struct ExtentScratch
{
    std::vector<std::uint32_t>    openStack;        // indices of the definitions still open, outermost first
    std::vector<std::uint32_t>    nearestClass;     // per def: the nearest ENCLOSING class-kind def, or kNoIndex
    std::vector<std::uint32_t>    componentRoot;    // per def: its outermost enclosing def (itself when top-level)
    std::vector<std::uint8_t>     componentHasHead; // per def used as a root: 1 ⇒ a head violation inside it
    std::vector<std::uint8_t>     underRecovered;   // per def: 1 ⇒ it, or a def enclosing it, is a recovered class
    std::vector<std::string_view> cppClassNames;    // the file's C++ class-kind names, sorted, for R2
};

inline bool hasBody( const ExtentDef& d ) noexcept
{
    return d.sigEndByte > d.startByte && d.sigEndByte < d.endByte;
}

// `outer` holds `inner` and the two are not the same extent (identical extents are a duplicate capture).
inline bool strictlyContains( const ExtentDef& outer, const ExtentDef& inner ) noexcept
{
    return outer.startByte <= inner.startByte && inner.endByte <= outer.endByte
        && ( outer.startByte != inner.startByte || outer.endByte != inner.endByte );
}

// R1: the name lies inside [startByte, signature end). A degenerate (empty) extent makes no claim to test.
inline bool nameOutsideHead( const ExtentDef& d ) noexcept
{
    if( d.kind == SymKind::Section || d.endByte <= d.startByte )
    {
        return false;
    }
    const std::uint32_t headEnd = d.sigEndByte > d.startByte ? d.sigEndByte : d.endByte;
    return d.nameByte < d.startByte || d.nameByte >= headEnd;
}

// R3: `d` lies in its bodied parent's return-type position — inside the signature, wholly before the parent's name.
inline bool inParentReturnType( const ExtentDef& d, const ExtentDef* parent ) noexcept
{
    return parent != nullptr && inSet( kHeadRuleLangs, d.lang ) && inSet( kHeadRuleLangs, parent->lang ) && hasBody( *parent )
        && d.startByte < parent->sigEndByte && d.endByte <= parent->nameByte;
}

// R2 (C++): filed under C:: while the nearest enclosing class is another class, C being a class of this file.
inline bool scopeContradictsContainer( const ExtentDef& d, const ExtentDef* nearestClass, std::span<const std::string_view> cppClassNames ) noexcept
{
    const bool isSelfScopedClass = inSet( kExtentClassKinds, d.kind ) && d.scope == d.name;
    if( d.lang != Lang::Cpp || d.scope.empty() || isSelfScopedClass || !hasBody( d ) || nearestClass == nullptr )
    {
        return false;
    }
    return nearestClass->name != d.scope && std::binary_search( cppClassNames.begin(), cppClassNames.end(), d.scope, rw::sortutil::svLess );
}

// R4: inside (or itself) a recovered class, or a recovered scopeless member.
inline bool recoveredSuspect( const ExtentDef& d, bool isUnderRecovered ) noexcept
{
    return isUnderRecovered || ( d.recovered & kRecoveredOrphan ) != 0;
}

// Per-file reset: the scratch vectors sized to the file, and the sorted C++ class names R2 looks up.
inline void resetExtentScratch( std::span<const ExtentDef> defs, ExtentScratch& scratch )
{
    const std::size_t defCount = defs.size();
    scratch.openStack.clear();
    scratch.nearestClass.assign( defCount, kNoIndex );
    scratch.componentRoot.assign( defCount, kNoIndex );
    scratch.componentHasHead.assign( defCount, 0 );
    scratch.underRecovered.assign( defCount, 0 );
    scratch.cppClassNames.clear();
    for( const ExtentDef& d : defs )
    {
        if( d.lang == Lang::Cpp && inSet( kExtentClassKinds, d.kind ) )
        {
            scratch.cppClassNames.push_back( d.name );
        }
    }
    // svLess, never the default comparator: libstdc++'s string_view compare subtracts the two lengths in size_type, and
    // G1's integer sanitizer aborts on the wrap the moment two class names prefix one another (Linux leg only; libc++
    // never subtracts). Same total order as operator<, so the lookup above answers exactly as before.
    std::sort( scratch.cppClassNames.begin(), scratch.cppClassNames.end(), rw::sortutil::svLess );
}

// Close every open def that does not strictly hold `d` (it ended before d, crosses it, or duplicates it) and
// return d's parent — the innermost open def left — or kNoIndex at top level.
inline std::uint32_t popToParent( std::span<const ExtentDef> defs, const ExtentDef& d, std::vector<std::uint32_t>& openStack ) noexcept
{
    while( !openStack.empty() && !strictlyContains( defs[ openStack.back() ], d ) )
    {
        openStack.pop_back();
    }
    return openStack.empty() ? kNoIndex : openStack.back();
}

// Record d's ancestry facts from its parent's: component root, nearest enclosing class, recovered-class cover.
inline void linkToParent( std::span<const ExtentDef> defs, std::uint32_t defIndex, std::uint32_t parentIndex, ExtentScratch& scratch ) noexcept
{
    const bool hasParent        = parentIndex != kNoIndex;
    const bool isRecoveredClass = inSet( kExtentClassKinds, defs[ defIndex ].kind ) && ( defs[ defIndex ].recovered & kRecoveredContainer ) != 0;
    if( !hasParent )
    {
        scratch.componentRoot[ defIndex ]  = defIndex;
        scratch.underRecovered[ defIndex ] = isRecoveredClass ? 1 : 0;
        return;
    }
    scratch.componentRoot[ defIndex ]  = scratch.componentRoot[ parentIndex ];
    scratch.nearestClass[ defIndex ]   = inSet( kExtentClassKinds, defs[ parentIndex ].kind ) ? parentIndex : scratch.nearestClass[ parentIndex ];
    scratch.underRecovered[ defIndex ] = ( isRecoveredClass || scratch.underRecovered[ parentIndex ] != 0 ) ? 1 : 0;
}

// Classify ONE file's definitions. `defs` must be in DefSpanIndex order (startByte ascending, endByte descending);
// bits[i] receives defs[i]'s reason set. Deterministic in the input order alone.
inline void classifyFileExtents( std::span<const ExtentDef> defs, std::span<std::uint8_t> bits, ExtentScratch& scratch )
{
    VERIFY( bits.size() == defs.size() );
    std::fill( bits.begin(), bits.end(), std::uint8_t( 0 ) );
    resetExtentScratch( defs, scratch );

    // one pass: each def against its parent (the innermost open def that strictly holds it)
    for( std::uint32_t defIndex = 0; defIndex < defs.size(); ++defIndex )
    {
        const ExtentDef&    d           = defs[ defIndex ];
        const std::uint32_t parentIndex = popToParent( defs, d, scratch.openStack );
        linkToParent( defs, defIndex, parentIndex, scratch );

        const std::uint32_t classIndex = scratch.nearestClass[ defIndex ];
        const ExtentDef*    classDef   = classIndex == kNoIndex ? nullptr : &defs[ classIndex ];
        bits[ defIndex ] |= nameOutsideHead( d ) ? kSuspectName : 0;
        bits[ defIndex ] |= scopeContradictsContainer( d, classDef, scratch.cppClassNames ) ? kSuspectScope : 0;
        bits[ defIndex ] |= recoveredSuspect( d, scratch.underRecovered[ defIndex ] != 0 ) ? kSuspectError : 0;
        if( inParentReturnType( d, parentIndex == kNoIndex ? nullptr : &defs[ parentIndex ] ) )
        {
            bits[ defIndex ]    |= kSuspectHead;
            bits[ parentIndex ] |= kSuspectHead;
            scratch.componentHasHead[ scratch.componentRoot[ defIndex ] ] = 1;
        }
        scratch.openStack.push_back( defIndex );
    }

    // R3's reach: the whole top-level extent tree that holds a head violation
    for( std::uint32_t defIndex = 0; defIndex < defs.size(); ++defIndex )
    {
        bits[ defIndex ] |= scratch.componentHasHead[ scratch.componentRoot[ defIndex ] ] != 0 ? kSuspectHead : 0;
    }
}

}   // namespace rw::extent
