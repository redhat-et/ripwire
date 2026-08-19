#pragma once

// namingconsistency.h — `--naming-consistency`: TIER A convention normalization (DESIGN_READABILITY_METRICS
// §9.2, the private research record; §-numbers below refer to it). Of the three Tier-A categories that
// record names — abbreviation inconsistency, synonym unification, convention normalization — this verb
// implements ONLY the last, and only that one, on purpose: the other two need a dictionary or a semantic
// judgment call (which spelling is "the" word), and naming-body-mismatch (see the WITHDRAWN note atop
// naminglens.h) is the standing proof of what shipping a plausible-but-unvalidated naming metric costs
// here. Convention normalization needs neither — the target is the SAME identifier's own subtokens,
// recombined into whatever CASE STYLE this corpus already overwhelmingly chose, so "the correct replacement
// is derivable from the corpus" (§9.2's own test) holds by construction, never by judgment.
//
// ── what "the corpus's own vote" means ───────────────────────────────────────────────────────────────────
// Every ELIGIBLE symbol (naminglens::detail::eligibleSymbol — Function/Method/Var, evaluable languages,
// ASCII names, no prototypes) whose name carries a CASE SIGNAL — at least two splitIdentifier subtokens,
// produced by a separator or a case transition — is classified into exactly one of: camel, pascal, snake,
// screaming, or mixed (BOTH a separator AND a transition in one name — naming-case's own finding, reused
// here rather than reimplemented). A name with NO signal (one token, or a name split only on digit
// boundaries, e.g. "md5sum") votes for nothing and is never flagged: there is nothing in it to normalize,
// because either style would render it identically.
//
// Votes are tallied per (language, kind-bucket) GROUP — kind-bucket is "fn" (Function+Method, which share a
// convention far more often than not) or "var" (module/global scope, where a different convention, e.g.
// SCREAMING constants, is common and legitimate). A group DECIDES only when it clears both a sample floor
// (kMinGroupVotes voting names) and an agreement floor (the leading style holds kMinAgreement of the vote);
// short of either, `dominant="UNAVAILABLE"` with `why=` naming which bar it missed — a genuinely
// mixed-convention corpus is a real, honestly-reported finding, never a guessed winner.
//
// ── what gets proposed ───────────────────────────────────────────────────────────────────────────────────
// In a DECIDED group, every off-convention name (a minority style, or `mixed`) gets `propose=`: its OWN
// subtokens (case-preserved by splitIdentifier) mechanically recombined into the group's dominant style via
// recombineToStyle — a pure function of the tokens already in the name. No word is invented, re-split, or
// looked up.
//
// ── what this is NOT ─────────────────────────────────────────────────────────────────────────────────────
// `propose=` is a SUGGESTION, not a safe-to-apply rename. Applying one for real needs the §9.3 rename-safety
// contract this verb does not implement: proof via `--uses` that the complete reference set is inside the
// indexed corpus, and a refusal on anything exported, ambiguous, or reflection-bound. This verb only ever
// READS and exits 0 unconditionally — a lens, like `--readability`/`--ensemble`, never a gate. A case
// convention is a style choice for a human/agent to apply consciously, not something CI should enforce on
// this verb's say-so alone.

#include "model.h"
#include "ingest.h"
#include "graphlegend.h"   // R-E fix (2026-08-19): rw::rootRelPathsLegend — the ONE root= definition
#include "naminglens.h"
#include "pageview.h"
#include "serialize.h"   // escapeXml

#include <algorithm>
#include <cstdint>
#include <cstdio>
#include <string>
#include <string_view>
#include <vector>

namespace rw
{
namespace namingconsistency
{

inline constexpr std::size_t kMinGroupVotes = 20;     // below this, a group's vote means nothing — UNAVAILABLE
inline constexpr double      kMinAgreement  = 0.90;   // the leading style must hold this share of the vote to DECIDE
inline constexpr std::size_t kRowCap        = 40;      // same shape as --hotspots/--readability's 40

enum class ConventionStyle : std::uint8_t { Camel, Pascal, Snake, Screaming, Mixed, NoSignal };

inline const char* styleTag( ConventionStyle st ) noexcept
{
    switch( st )
    {
        case ConventionStyle::Camel:     return "camel";
        case ConventionStyle::Pascal:    return "pascal";
        case ConventionStyle::Snake:     return "snake";
        case ConventionStyle::Screaming: return "screaming";
        case ConventionStyle::Mixed:     return "mixed";
        default:                         return "none";
    }
}

// Classifies a name ALREADY known to have >=2 splitIdentifier subtokens (the caller's job). Scans the raw
// name for the two structural facts naming-case's own rule uses — a snake separator, a camel transition —
// then, when only one is present, which sub-style it is.
inline ConventionStyle classifyConventionStyle( std::string_view name ) noexcept
{
    bool sawSeparator  = false;
    bool sawTransition = false;
    for( std::size_t i = 0; i + 1 < name.size(); ++i )
    {
        if( name[i] == '_' && i > 0 && naminglens::ncAlnum( name[ i - 1 ] ) && naminglens::ncAlnum( name[ i + 1 ] ) )
        {
            sawSeparator = true;
        }
        if( naminglens::ncLower( name[i] ) && naminglens::ncUpper( name[ i + 1 ] ) )
        {
            sawTransition = true;
        }
    }
    if( sawSeparator && sawTransition )
    {
        return ConventionStyle::Mixed;
    }
    if( sawSeparator )
    {
        bool anyLower = false;
        bool anyUpper = false;
        for( const char c : name )
        {
            anyLower = anyLower || naminglens::ncLower( c );
            anyUpper = anyUpper || naminglens::ncUpper( c );
        }
        if( anyUpper && !anyLower ) { return ConventionStyle::Screaming; }
        if( anyLower && !anyUpper ) { return ConventionStyle::Snake; }
        return ConventionStyle::Mixed;   // e.g. "Foo_bar" — a capitalized leading token plus a separator,
                                          // no lower->Upper transition, but not one clean style either
    }
    if( sawTransition )
    {
        for( const char c : name )
        {
            if( naminglens::ncAlpha( c ) )
            {
                return naminglens::ncUpper( c ) ? ConventionStyle::Pascal : ConventionStyle::Camel;
            }
        }
    }
    return ConventionStyle::NoSignal;   // no separator, no transition: digit-segmented or a single case run
}

// Whether this style VOTES. Mixed never does (it is nobody's convention) and NoSignal never reaches here
// (the caller filters it before classification matters) — kept explicit rather than inferred from the enum.
inline bool votingStyle( ConventionStyle st ) noexcept
{
    return st == ConventionStyle::Camel || st == ConventionStyle::Pascal
        || st == ConventionStyle::Snake || st == ConventionStyle::Screaming;
}

namespace detail
{

inline std::string titleCaseToken( std::string_view tok )
{
    std::string out = naminglens::toLowerAscii( tok );
    if( !out.empty() && naminglens::ncLower( out[0] ) )
    {
        out[0] = char( out[0] - 'a' + 'A' );
    }
    return out;
}

inline std::string upperToken( std::string_view tok )
{
    std::string out( tok );
    for( char& c : out )
    {
        c = naminglens::ncLower( c ) ? char( c - 'a' + 'A' ) : c;
    }
    return out;
}

}   // namespace detail

// Pure function of `toks` (splitIdentifier's OWN subtokens, case preserved) and the target style — no
// dictionary, no synonym choice: this is what keeps the suggestion inside Tier A (§9.2).
inline std::string recombineToStyle( const std::vector<std::string>& toks, ConventionStyle style )
{
    std::string out;
    for( std::size_t i = 0; i < toks.size(); ++i )
    {
        switch( style )
        {
            case ConventionStyle::Snake:
                if( i > 0 ) { out.push_back( '_' ); }
                out += naminglens::toLowerAscii( toks[i] );
                break;
            case ConventionStyle::Screaming:
                if( i > 0 ) { out.push_back( '_' ); }
                out += detail::upperToken( toks[i] );
                break;
            case ConventionStyle::Pascal:
                out += detail::titleCaseToken( toks[i] );
                break;
            case ConventionStyle::Camel:
            default:
                out += ( i == 0 ) ? naminglens::toLowerAscii( toks[i] ) : detail::titleCaseToken( toks[i] );
                break;
        }
    }
    return out;
}

enum class KindBucket : std::uint8_t { Fn, Var };

inline const char* kindBucketTag( KindBucket k ) noexcept { return k == KindBucket::Fn ? "fn" : "var"; }

// Function and Method share a convention far more often than not; Var (module/global scope) is kept
// separate because a distinct convention there (e.g. SCREAMING constants) is common and legitimate.
inline KindBucket kindBucketOf( SymKind k ) noexcept
{
    return k == SymKind::Var ? KindBucket::Var : KindBucket::Fn;
}

struct StyledSymbol
{
    NodeId                    id = 0;
    Lang                      lang;
    KindBucket                kind;
    ConventionStyle           style;
    std::vector<std::string>  toks;
};

struct ConventionGroup
{
    Lang            lang;
    KindBucket      kind;
    std::uint32_t   votes[4] = { 0, 0, 0, 0 };   // indexed by ConventionStyle: Camel,Pascal,Snake,Screaming
    std::uint32_t   total    = 0;
    ConventionStyle dominant = ConventionStyle::NoSignal;   // meaningful only when decided
    bool            decided  = false;
    const char*     why      = "";                          // set when !decided
};

struct ConventionScan
{
    std::vector<StyledSymbol>    symbols;   // every styled (non-NoSignal) eligible symbol
    std::vector<ConventionGroup> groups;    // sorted by (lang, kind) once scanNamingConsistency returns
};

inline std::size_t groupIndexOf( std::vector<ConventionGroup>& groups, Lang lang, KindBucket kind )
{
    for( std::size_t i = 0; i < groups.size(); ++i )
    {
        if( groups[i].lang == lang && groups[i].kind == kind )
        {
            return i;
        }
    }
    ConventionGroup fresh;
    fresh.lang = lang;
    fresh.kind = kind;
    groups.push_back( fresh );
    return groups.size() - 1;
}

// The measurement pass: classify every voting-eligible name, tally its group, then decide each group.
// `ing.symbols` is already in deterministic (file, line, name) order, so `id` alone orders any row by it.
inline ConventionScan scanNamingConsistency( const IngestResult& ing )
{
    ConventionScan scan;
    std::vector<std::string> toks;
    for( std::size_t symbolIndex = 0; symbolIndex < ing.symbols.size(); ++symbolIndex )
    {
        const Symbol& s = ing.symbols[symbolIndex];
        if( !naminglens::detail::eligibleSymbol( s ) )
        {
            continue;
        }
        naminglens::splitIdentifier( s.name, toks );
        if( toks.size() < 2 )
        {
            continue;   // no signal — nothing to vote and nothing to flag
        }
        const ConventionStyle style = classifyConventionStyle( s.name );
        if( style == ConventionStyle::NoSignal )
        {
            continue;
        }

        StyledSymbol styled;
        styled.id    = NodeId( symbolIndex );
        styled.lang  = s.lang;
        styled.kind  = kindBucketOf( s.kind );
        styled.style = style;
        styled.toks  = toks;

        const std::size_t groupIndex = groupIndexOf( scan.groups, styled.lang, styled.kind );
        if( votingStyle( style ) )
        {
            ++scan.groups[groupIndex].votes[ std::uint8_t( style ) ];
            ++scan.groups[groupIndex].total;
        }
        scan.symbols.push_back( std::move( styled ) );
    }

    // Groups so far are in first-seen order — sort before anyone can see them, then decide each.
    std::sort( scan.groups.begin(), scan.groups.end(),
               []( const ConventionGroup& a, const ConventionGroup& b ) noexcept
               {
                   if( a.lang != b.lang ) { return a.lang < b.lang; }
                   return a.kind < b.kind;
               } );
    for( ConventionGroup& group : scan.groups )
    {
        if( group.total < kMinGroupVotes )
        {
            group.why = "insufficient-sample";
            continue;
        }
        std::size_t bestIndex = 0;
        for( std::size_t i = 1; i < 4; ++i )
        {
            if( group.votes[i] > group.votes[bestIndex] )
            {
                bestIndex = i;
            }
        }
        const double agreement = double( group.votes[bestIndex] ) / double( group.total );
        if( agreement < kMinAgreement )
        {
            group.why = "no-clear-convention";
            continue;
        }
        group.dominant = ConventionStyle( bestIndex );
        group.decided  = true;
    }
    return scan;
}

inline const ConventionGroup* groupFor( const ConventionScan& scan, Lang lang, KindBucket kind )
{
    for( const ConventionGroup& g : scan.groups )
    {
        if( g.lang == lang && g.kind == kind )
        {
            return &g;
        }
    }
    return nullptr;   // unreachable by construction: every styled symbol created its group first
}

// The legend the reader meets FIRST. Every attribute this verb emits is DEFINED here in the house `name=`
// form (test/legendcoveragecheck.sh derives that mechanically). No `--` digraph anywhere in it — illegal
// inside an XML comment, which is why flags are named bare.
inline constexpr const char* kNamingConsistencyLegend =
    "<!-- ripwire naming-consistency: TIER A convention normalization (DESIGN_READABILITY_METRICS section 9.2): "
    "the corpus's OWN case-convention choice, voted per (language, kind) group among MULTI-TOKEN eligible "
    "names (a single-token name, or one split only on digit boundaries, carries no case signal and is silently "
    "excluded from both voting and flagging). A group DECIDES only when its leading style clears both a sample "
    "floor and an agreement floor; short of either it reports style=UNAVAILABLE with why= naming which bar it "
    "missed, never a guessed winner. Every off-convention name in a DECIDED group gets propose=: its OWN "
    "subtokens mechanically recombined into the dominant style: no dictionary, no synonym judgment, so this is "
    "safe to suggest for that reason alone. propose= is a SUGGESTION, never a safe-to-blind-apply rename: an "
    "actual rename needs the uses verb to prove the complete reference set first. A mixed name (naming-case's own "
    "finding: a snake separator AND a camel transition inside ONE identifier) never wins a vote and is always "
    "flagged when its group has a decided convention. Exit 0 always: a lens, not a gate. "
    "groups=(language,kind) pairs with at least one styled name candidates=styled names scanned "
    "decided=groups that cleared both floors flagged=off-convention names in decided groups "
    "g rows: lang= kind=fn|var style=the group's dominant convention, or UNAVAILABLE agree=leading-style votes "
    "total=all voting-style votes in this group why=insufficient-sample|no-clear-convention when style is "
    "UNAVAILABLE (absent otherwise) "
    "f rows: p=path:line n=name lang= kind=fn|var style=this name's own convention (mixed for the internally "
    "inconsistent case) propose=the mechanically recombined form in the group's dominant style. "
    "Pages limit=N (offset=M); default 40 rows, shown= capped= disclose the cut. -->";

// Emit the report. Returns the process exit code — always 0: this is a lens, not a gate. `rootPrefix`/
// `rootAttr` — R-E (2026-08-17 harvest), same convention writeContextRatioReport takes (see contextratio.h).
inline int writeNamingConsistencyReport( const IngestResult& ing, int pageLimit, int pageOffset,
                                         std::string_view rootPrefix = {}, const std::string& rootAttr = std::string() )
{
    const ConventionScan scan = scanNamingConsistency( ing );

    std::vector<const StyledSymbol*> flagged;
    for( const StyledSymbol& sym : scan.symbols )
    {
        const ConventionGroup* group = groupFor( scan, sym.lang, sym.kind );
        if( group != nullptr && group->decided && sym.style != group->dominant )
        {
            flagged.push_back( &sym );
        }
    }
    std::sort( flagged.begin(), flagged.end(),
               []( const StyledSymbol* a, const StyledSymbol* b ) noexcept { return a->id < b->id; } );

    std::size_t decidedCount = 0;
    for( const ConventionGroup& g : scan.groups )
    {
        decidedCount += g.decided ? 1u : 0u;
    }

    const std::size_t total = flagged.size();
    const PageWindow  page  = pageWindow( total, effectiveRowCap( pageLimit, int( kRowCap ) ), pageOffset );
    const std::size_t shown = page.end > page.begin ? page.end - page.begin : 0;

    char disclosure[kPageDisclosureCap];
    pageDisclosure( disclosure, sizeof disclosure, shown, total, page.end, pageLimit, pageOffset, true );

    std::fputs( kNamingConsistencyLegend, stdout );
    // R-E fix (2026-08-19): the shared root-relative clause, emitted exactly when root= is (graphlegend.h).
    std::fputs( rw::rootRelPathsLegend( !rootAttr.empty() ), stdout );
    std::printf( "<naming-consistency groups=\"%zu\" candidates=\"%zu\" decided=\"%zu\" flagged=\"%zu\"%s%s>",
                 scan.groups.size(), scan.symbols.size(), decidedCount, total, disclosure, rootAttr.c_str() );

    for( const ConventionGroup& g : scan.groups )
    {
        if( g.decided )
        {
            std::printf( "<g lang=\"%s\" kind=\"%s\" style=\"%s\" agree=\"%u\" total=\"%u\"/>",
                         langTag( g.lang ), kindBucketTag( g.kind ), styleTag( g.dominant ),
                         g.votes[ std::uint8_t( g.dominant ) ], g.total );
        }
        else
        {
            std::printf( "<g lang=\"%s\" kind=\"%s\" style=\"UNAVAILABLE\" why=\"%s\" total=\"%u\"/>",
                         langTag( g.lang ), kindBucketTag( g.kind ), g.why, g.total );
        }
    }

    std::vector<char> escPath;
    std::vector<char> escName;
    std::vector<char> escProp;
    for( std::size_t rowIndex = page.begin; rowIndex < page.end; ++rowIndex )
    {
        const StyledSymbol& sym   = *flagged[rowIndex];
        const Symbol&        s    = ing.symbols[ sym.id ];
        const ConventionGroup* group = groupFor( scan, sym.lang, sym.kind );
        const std::string_view rel  = rootPrefix.empty() ? std::string_view( ing.files[s.fileId] ) : rw::sarif::rootRelativeUri( ing.files[s.fileId], rootPrefix );
        const std::string     path( escapeXml( rel, escPath ) );
        const std::string     name( escapeXml( s.name, escName ) );
        const std::string     propose( escapeXml( recombineToStyle( sym.toks, group->dominant ), escProp ) );
        std::printf( "<f p=\"%s:%u\" n=\"%s\" lang=\"%s\" kind=\"%s\" style=\"%s\" propose=\"%s\"/>",
                     path.c_str(), s.line, name.c_str(), langTag( sym.lang ), kindBucketTag( sym.kind ),
                     styleTag( sym.style ), propose.c_str() );
    }
    std::printf( "</naming-consistency>" );
    return 0;
}

}   // namespace namingconsistency
}   // namespace rw
