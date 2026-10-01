#pragma once
// forhow.h — the shape="how" answer to a how-it-works task (fix #10; pre-registered as arm F2 — "prereg" below).
//
// WHAT IT ANSWERS. A task that opens "how does / how do / how is / how are / how can / explain how / walk me through /
// what happens when" asks for a MECHANISM: where it starts, what it calls, which statements decide it. The --for lens
// answers every task with a ranked list of up to 40 signatures, and on these tasks the table measured why that is not an
// answer: the entry function was missing from the head or ranked below off-target rows on 6 of 9 rows, and the deciding
// statements sit inside bodies a signature list cannot show. This header replaces the ranked list, on that task shape
// only, with four sections whose bytes are identical on all four surfaces (CLI --for, CLI --pack-task, MCP for, MCP
// explore):
//   <path seeds= hops=>  up to 3 SEEDS — the entry points, picked from the question's own identifiers and words first —
//                        and the resolved call chains walked from them (9 hops at most, depth 4), as `a > b > c | b > d`;
//   <h n= p=>            one row per hop: its signature, its distinct resolved callees (task words first) with their
//                        call-site lines, and a seed's callers;
//   <b n= p=>            the first 3 hops' SELECTED body lines (first line, calls, guards, field writes, exits) under a
//                        byte cap, re-emitted in source order;
//   <names>              the rest of the --for lens window as `name p:line`, with next= to every window row.
// Every cut is counted (shown= total= capped=) and carries the one call that returns what it cut (METHODOLOGY §9 #3).
//
// WHAT IT READS. Only the --for lens's own default ranking (the score vector, its 40-row window W after the relevance
// floor) and the resolved call graph. It never changes either: the ranking, confidence=/margin_pct=, the candidates
// export and every non-triggered answer are byte-identical to the pre-change binary (prereg Gate S).
//
// WHEN IT FIRES. howTextFires (the frozen v1 §0 text rule) AND default arguments AND one root — decided by the callers:
// cli.h (Config::howArgsDefault, from argv) and mcp.h (the verb's arguments are task/path/legend only).
//
// Gates: test/forhowcheck.sh (trigger, default-argument rule, four-surface parity, legend coverage, counts, every next=
// returns what it cut, seed order, the ref posture, well-formedness and determinism).

#include "commentcoherence.h"   // isCommentStopword — BASE's fixed English stopword list (prereg S2)
#include "filter.h"             // pathTierOf / isDemoOrGeneratedPath — the Source-tier test (prereg S4)
#include "forpage.h"            // forCoveragePct / forAnswerIsThin — coverage=, as the --for lens computes it
#include "forhowbase.h"         // the trigger and the legend clauses (dependency-free: cli.h and legenddict.h read them)
#include "lexical.h"            // subtokens
#include "mention.h"            // ForNamedHeaderRow — the <hdr> rows the --for answers carry first — THE index split (prereg S2 "index-split subtokens")
#include "model.h"
#include "nextverb.h"           // nextFlag
#include "pageview.h"           // kCallHierarchyRowCap — the --callers/--callees default page a next= must exceed — the ONE next= quoting
#include "redact.h"             // redactInPlace — every emitted source line passes the secret scrub
#include "sarif.h"              // rootPrefixOf / rootRelativeUri — p= relative to the root, as every --for row
#include "serialize.h"          // escapeXml, cleanSig, appendCdataSafe, relevanceFloorCut, kForLensDefaultTopN, tokensForEmittedBytes
#include "infra/Diagnostics.h"
#include "infra/namesplit.h"     // isIdentStart / isIdentChar — the ONE ASCII identifier test
#include "infra/sortutil.h"     // radixSortByScoreDescId — the (score desc, id asc) order the lens window uses

#include <algorithm>
#include <cstddef>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <span>
#include <string>
#include <string_view>
#include <vector>

namespace rw
{

// The data notes in their compact spelling: the numbers stay, the sentence goes. Unknown shapes pass
// through VERBATIM — a note this table does not know is never shortened into something it did not say.
inline std::string compactForNote( std::string_view note )
{
    // " [relevance floor: kept 7 of 40 - the other 33 scored zero…]" → " [floor: kept 7 of 40]"
    if( note.starts_with( " [relevance floor: kept " ) )
    {
        const std::size_t cut = note.find( " - " );
        return cut == std::string_view::npos ? std::string( note ) : " [floor: kept " + std::string( note.substr( 24, cut - 24 ) ) + "]";
    }
    // " [doc mentions: 2 docs discussing 1 top-ranked symbol surfaced; doc_mentions= …]" → " [doc mentions: 2 docs, 1 symbol; doc_mentions=]"
    if( note.starts_with( " [doc mentions: " ) )
    {
        const std::size_t disc = note.find( " discussing " );
        const std::size_t top  = note.find( " top-ranked symbol" );
        if( disc != std::string_view::npos && top != std::string_view::npos && top > disc )
        {
            return " [doc mentions: " + std::string( note.substr( 16, disc - 16 ) ) + ", " + std::string( note.substr( disc + 12, top - disc - 12 ) )
                 + " symbol" + ( note.substr( top + 18 ).starts_with( "s" ) ? "s" : "" ) + "; doc_mentions=]";
        }
        return std::string( note );
    }
    // " [mention anchor: 1 file + 2 symbols named in the task, …; mention_anchored= …]" → " [mention anchor: 1 file + 2 symbols; mention_anchored=]"
    if( note.starts_with( " [mention anchor: " ) )
    {
        const std::size_t cut = note.find( " named in the task" );
        return cut == std::string_view::npos ? std::string( note ) : std::string( note.substr( 0, cut ) ) + "; mention_anchored=]";
    }
    // " [cochange boost: promoted N symbols in M files that historically …]" → " [cochange boost: promoted N symbols in M files]"
    if( note.starts_with( " [cochange boost: promoted " ) )
    {
        const std::size_t cut = note.find( " that " );
        return cut == std::string_view::npos ? std::string( note ) : std::string( note.substr( 0, cut ) ) + "]";
    }
    return std::string( note );
}

// ── the <hdr> rows, ONE renderer ──────────────────────────────────────────────────────────────────────────────────────
// R2-AF (round 2, S4): `<hdr p= of=/>` — the named file's one same-directory, same-stem decl/impl partner. It was spelled
// twice (verbs_for.h renderForHdrRowsXml and an inline copy in mcpverbs.h forTaskText, because main.cpp includes mcp.h
// before verbs_for.h); the how answer is a third reader, so the three share this one. Byte-identical to both copies.
inline std::string renderNamedHeaderRowsXml( const IngestResult& ing, const std::vector<ForNamedHeaderRow>& rows, std::string_view rootArg )
{
    if( rows.empty() )
    {
        return {};
    }
    const std::string rootPrefix = rootArg.empty() ? std::string() : rw::sarif::rootPrefixOf( rootArg );
    const auto        rel        = [ & ]( std::uint32_t f ) -> std::string
    {
        return rootArg.empty() ? std::string( ing.files[f] ) : std::string( rw::sarif::rootRelativeUri( ing.files[f], rootPrefix ) );
    };
    std::vector<char> esc;
    std::string       x;
    for( const ForNamedHeaderRow& row : rows )
    {
        // local invariant: forNamedHeaderRows only ever returns fileIds it read out of ing.files itself (mention.h)
        ASSUME( row.partnerFile < ing.files.size() && row.namedFile < ing.files.size() );
        x += "<hdr p=\"";
        x += escapeXml( rel( row.partnerFile ), esc );
        x += "\" of=\"";
        x += escapeXml( rel( row.namedFile ), esc );
        x += "\"/>";
    }
    return x;
}

namespace forhow
{

// ── the frozen constants (prereg F2; never swept) ───────────────────────────────────────────────────────────────────
inline constexpr std::size_t kHowSeedMax          = 3;      // S7
inline constexpr std::size_t kHowHopMax           = 9;      // P: seeds included
inline constexpr int         kHowDepthMax         = 4;      // P
inline constexpr std::size_t kHowSeedCalleeRows   = 8;      // P: callee rows on a seed's hop
inline constexpr std::size_t kHowDeepCalleeRows   = 4;      // P: …and on a deeper hop
inline constexpr std::size_t kHowCallSiteLines    = 3;      // P: cl= lines per row
inline constexpr std::size_t kHowCallerRows       = 2;      // P: a seed's callers
inline constexpr std::size_t kHowNextExpandNames  = 3;      // P: next= on a capped path
inline constexpr std::size_t kHowBodyHops         = 3;      // B
inline constexpr std::size_t kHowBodyBytesEach    = 1024;   // B
inline constexpr std::size_t kHowBodyBytesAll     = 2048;   // B
inline constexpr std::size_t kHowNameRows         = 8;      // N
inline constexpr std::size_t kHowCeilingBytes     = 8192;   // §0 "Ceiling": the WHOLE first answer — the CLI default --for
                                                            // document (howCompactDocument), the unit §2 prices; every
                                                            // surface trims its sections against that same document

// The how answer reads the --for lens's index, the one that captures value uses (cli.h needsValueUses), and a plain
// --callers/--callees reads the lean one, which can resolve fewer calls (measured: 10 callers where the lens index has
// 13). --metrics selects the value-use index and leaves a --callers/--callees answer byte-identical otherwise, so the
// follow-up lists exactly the rows this answer counted.
inline constexpr std::string_view kHowValueUseIndexFlag = " --metrics";

// ── the question: identifiers, terms, variants (prereg S1-S3) ────────────────────────────────────────────────────────
inline constexpr std::string_view kHowExtraStopwords[] = {
    "explain", "walk", "through", "happen", "happens", "happened", "get", "gets", "got", "make", "makes", "made", "work",
    "works", "working", "like", "example", "via", "under", "use", "used", "uses", "using", "way", "ways", "could", "would",
    "may", "might", "must", "done", "onto", "without", "whose", "every", "function", "functions", "method", "methods",
    "class", "classes", "code", "file", "files" };

inline bool isHowStopword( std::string_view w ) noexcept
{
    if( isCommentStopword( w ) )
    {
        return true;
    }
    return std::find( std::begin( kHowExtraStopwords ), std::end( kHowExtraStopwords ), w ) != std::end( kHowExtraStopwords );
}

// the question's identifier alphabet, `[A-Za-z_$][A-Za-z0-9_$]*` (prereg S1): the ONE ASCII identifier test, plus `$`
inline bool isHowIdStart( char c ) noexcept { return c == '$' || namesplit::isIdentStart( c ); }
inline bool isHowIdChar( char c ) noexcept { return c == '$' || namesplit::isIdentChar( c ); }

// One qualified name starting at `i`: runs joined by `.`, `::`, `#` or `->`. Returns the end; `segs` gets the runs.
inline std::size_t scanQualifiedName( std::string_view s, std::size_t i, std::vector<std::string_view>& segs )
{
    segs.clear();
    for( ;; )
    {
        std::size_t j = i;
        while( j < s.size() && isHowIdChar( s[j] ) )
        {
            ++j;
        }
        segs.push_back( s.substr( i, j - i ) );
        const std::string_view rest = s.substr( j );
        std::size_t            joinerBytes = 0;
        if( rest.starts_with( "::" ) || rest.starts_with( "->" ) )
        {
            joinerBytes = 2;
        }
        else if( rest.starts_with( "." ) || rest.starts_with( "#" ) )
        {
            joinerBytes = 1;
        }
        if( joinerBytes == 0 || j + joinerBytes >= s.size() || !isHowIdStart( s[ j + joinerBytes ] ) )
        {
            return j;
        }
        i = j + joinerBytes;
    }
}

// outside backticks a token is an identifier only with a `_`, a qualifier, or a lower→upper step (prereg S1)
inline bool looksLikeIdentifier( const std::vector<std::string_view>& segs ) noexcept
{
    if( segs.size() > 1 )
    {
        return true;
    }
    for( const std::string_view seg : segs )
    {
        for( std::size_t k = 0; k < seg.size(); ++k )
        {
            if( seg[k] == '_' || ( k > 0 && seg[k - 1] >= 'a' && seg[k - 1] <= 'z' && seg[k] >= 'A' && seg[k] <= 'Z' ) )
            {
                return true;
            }
        }
    }
    return false;
}

struct HowQuestion
{
    std::vector<std::vector<std::string>> identifiers;   // each one's segments, outermost first
    std::vector<std::string>              terms;         // distinct, lowercase, stopwords removed, first-appearance order
    std::vector<std::string>              variantText;   // every variant string (storage for the map's keys)
    std::vector<std::uint16_t>            variantTerm;   // parallel: the term it is a variant of
    HashMap<std::string_view, std::vector<std::uint16_t>> termsOfVariant;

    // the term indices a lowercase subtoken matches (nullptr = none)
    const std::vector<std::uint16_t>* match( std::string_view sub ) const
    {
        const auto it = termsOfVariant.find( sub );
        return it == termsOfVariant.end() ? nullptr : &it->second;
    }
};

// V(t): t; LB-3's stem rules regardless of their env switch (lexical.h, "LB-3 arm S": -s, -es, -ed, -ing, 3 bytes at
// least); and -ies/-ied → -y (prereg S3).
inline void appendHowVariants( const std::string& t, std::vector<std::string>& out )
{
    out.push_back( t );
    const std::size_t L    = t.size();
    const auto        ends = [ & ]( std::string_view suf ) { return L >= suf.size() && std::string_view( t ).substr( L - suf.size() ) == suf; };
    const auto        add  = [ & ]( std::string v ) { if( v.size() >= 3 ) { out.push_back( std::move( v ) ); } };
    const auto isConsonant = []( char c ) { return c >= 'a' && c <= 'z' && c != 'a' && c != 'e' && c != 'i' && c != 'o' && c != 'u'; };
    if( ends( "s" ) && !ends( "ss" ) && L >= 4 )
    {
        add( t.substr( 0, L - 1 ) );
        if( ends( "es" ) && L >= 5 )
        {
            add( t.substr( 0, L - 2 ) );
        }
    }
    if( ends( "ed" ) && L >= 5 )
    {
        add( t.substr( 0, L - 1 ) );
        add( t.substr( 0, L - 2 ) );
        if( L >= 6 && t[L - 3] == t[L - 4] && isConsonant( t[L - 3] ) )
        {
            add( t.substr( 0, L - 3 ) );
        }
    }
    if( ends( "ing" ) && L >= 6 )
    {
        add( t.substr( 0, L - 3 ) );
        add( t.substr( 0, L - 3 ) + "e" );
        if( L >= 7 && t[L - 4] == t[L - 5] && isConsonant( t[L - 4] ) )
        {
            add( t.substr( 0, L - 4 ) );
        }
    }
    if( ends( "ies" ) || ends( "ied" ) )
    {
        add( t.substr( 0, L - 3 ) + "y" );
    }
}

inline HowQuestion parseHowQuestion( std::string_view s )
{
    HowQuestion               q;
    std::vector<std::string>  raw;   // candidate terms in order, before the stopword and dedupe pass
    std::vector<std::string_view> segs;
    std::vector<std::string>  scratch;
    const auto addSubtokens = [ & ]( std::string_view text )
    {
        scratch.clear();
        subtokens( text, scratch );
        for( std::string& t : scratch )
        {
            raw.push_back( std::move( t ) );
        }
    };
    bool isInBackticks = false;
    for( std::size_t i = 0; i < s.size(); )
    {
        const char c = s[i];
        if( c == '`' )
        {
            isInBackticks = !isInBackticks;
            ++i;
            continue;
        }
        if( !isHowIdStart( c ) || ( i > 0 && isHowIdChar( s[i - 1] ) ) )
        {
            ++i;
            continue;
        }
        std::size_t j = scanQualifiedName( s, i, segs );
        if( j < s.size() && s[j] == '*' )
        {
            addSubtokens( s.substr( i, j - i ) );   // a wildcard: its prefix's subtokens are terms, never an identifier
            i = j + 1;
            continue;
        }
        if( isInBackticks || looksLikeIdentifier( segs ) )
        {
            std::vector<std::string> ident;
            for( const std::string_view seg : segs )
            {
                ident.emplace_back( seg );
                addSubtokens( seg );
            }
            q.identifiers.push_back( std::move( ident ) );
        }
        else
        {
            // other runs of 3 letters or more, lowercased
            const std::string_view tok = s.substr( i, j - i );
            for( std::size_t a = 0; a < tok.size(); )
            {
                std::size_t b = a;
                while( b < tok.size() && namesplit::isIdentStart( tok[b] ) && tok[b] != '_' )
                {
                    ++b;
                }
                if( b - a >= 3 )
                {
                    std::string w( tok.substr( a, b - a ) );
                    std::transform( w.begin(), w.end(), w.begin(), []( char ch ) { return ( ch >= 'A' && ch <= 'Z' ) ? char( ch - 'A' + 'a' ) : ch; } );
                    raw.push_back( std::move( w ) );
                }
                a = b == a ? a + 1 : b;
            }
        }
        i = j;
    }
    for( std::string& t : raw )
    {
        if( t.empty() || isHowStopword( t ) || std::find( q.terms.begin(), q.terms.end(), t ) != q.terms.end() )
        {
            continue;
        }
        q.terms.push_back( std::move( t ) );
    }
    if( q.terms.size() > 0xFFFFu )
    {
        q.terms.resize( 0xFFFFu );   // a 65,535-term question is an input blow-up, not a question; the index is 16-bit
    }
    for( std::size_t u = 0; u < q.terms.size(); ++u )
    {
        std::vector<std::string> vs;
        appendHowVariants( q.terms[u], vs );
        for( std::string& v : vs )
        {
            q.variantText.push_back( std::move( v ) );
            q.variantTerm.push_back( std::uint16_t( u ) );
        }
    }
    q.termsOfVariant.reserve( q.variantText.size() );
    for( std::size_t k = 0; k < q.variantText.size(); ++k )   // keys view into variantText, which no longer grows
    {
        std::vector<std::uint16_t>& slot = q.termsOfVariant[ std::string_view( q.variantText[k] ) ];
        if( std::find( slot.begin(), slot.end(), q.variantTerm[k] ) == slot.end() )
        {
            slot.push_back( q.variantTerm[k] );
        }
    }
    return q;
}

// ── the symbols (prereg S4) ───────────────────────────────────────────────────────────────────────────────────────────
inline bool isHowCallableKind( SymKind k ) noexcept { return k == SymKind::Function || k == SymKind::Method; }
inline bool isHowContainerKind( SymKind k ) noexcept { return k == SymKind::Class || k == SymKind::Struct || k == SymKind::Interface; }
inline bool hasHowBody( const Symbol& s ) noexcept { return s.endByte > s.sigEndByte; }

// p(c) = matched / count over the name's distinct subtokens; m(c) = distinct terms matched in name ∪ container ∪ path;
// x(c) = the name equals an identifier the question names.
struct HowScore
{
    std::uint16_t matched = 0;
    std::uint16_t count   = 0;
    std::uint16_t m       = 0;
    bool          x       = false;
};

// p(a) > p(b), compared exactly (cross-multiplied); a nameless symbol's p is 0
inline int compareHowP( const HowScore& a, const HowScore& b ) noexcept
{
    const std::uint32_t lhs = std::uint32_t( a.matched ) * std::uint32_t( b.count == 0 ? 1 : b.count );
    const std::uint32_t rhs = std::uint32_t( b.matched ) * std::uint32_t( a.count == 0 ? 1 : a.count );
    return lhs > rhs ? 1 : ( lhs < rhs ? -1 : 0 );
}

struct HowContext
{
    const IngestResult&       ing;
    const Graph&              g;
    const std::vector<float>& rank;
    const HowQuestion&        q;
    std::vector<std::int8_t>  fileIsSource;            // -1 unknown, 0/1
    std::vector<std::vector<std::string>> pathSubs;    // per file, lazily
    std::vector<std::int8_t>  hasPathSubs;
    std::vector<std::uint32_t> termStamp;
    std::uint32_t             stamp = 0;

    HowContext( const IngestResult& i, const Graph& gr, const std::vector<float>& r, const HowQuestion& qq )
        : ing( i ), g( gr ), rank( r ), q( qq ), fileIsSource( i.files.size(), -1 ), pathSubs( i.files.size() ),
          hasPathSubs( i.files.size(), 0 ), termStamp( qq.terms.size(), 0 )
    {
    }

    bool isSourceFile( std::uint32_t f )
    {
        if( fileIsSource[f] < 0 )
        {
            const std::string_view p = rootRelPath( ing, f );
            fileIsSource[f]          = ( pathTierOf( p ) == PathTier::Source && !isDemoOrGeneratedPath( p ) ) ? 1 : 0;
        }
        return fileIsSource[f] == 1;
    }
    bool isSourceCallable( NodeId id )
    {
        const Symbol& s = ing.symbols[id];
        return isHowCallableKind( s.kind ) && isSourceFile( s.fileId );
    }
    bool isCandidate( NodeId id )
    {
        const Symbol& s = ing.symbols[id];
        return ( isHowCallableKind( s.kind ) || isHowContainerKind( s.kind ) ) && hasHowBody( s ) && isSourceFile( s.fileId );
    }
    float lensScore( NodeId id ) const noexcept { return id < rank.size() ? rank[id] : 0.0f; }

    const std::vector<std::string>& pathSubtokens( std::uint32_t f )
    {
        if( !hasPathSubs[f] )
        {
            subtokens( rootRelPath( ing, f ), pathSubs[f] );
            hasPathSubs[f] = 1;
        }
        return pathSubs[f];
    }

    // name-only scoring (an ambiguous callee row has a name and no single definition)
    HowScore scoreName( std::string_view name, std::span<const std::string> containerSubs, std::span<const std::string> pathSubsOf )
    {
        HowScore sc;
        if( ++stamp == 0 )
        {
            std::fill( termStamp.begin(), termStamp.end(), 0u );
            stamp = 1;
        }
        std::vector<std::string> nameSubs;
        subtokens( name, nameSubs );
        std::sort( nameSubs.begin(), nameSubs.end() );
        nameSubs.erase( std::unique( nameSubs.begin(), nameSubs.end() ), nameSubs.end() );
        sc.count = std::uint16_t( std::min<std::size_t>( nameSubs.size(), 0xFFFFu ) );
        const auto hit = [ & ]( std::string_view sub ) -> bool
        {
            const std::vector<std::uint16_t>* terms = q.match( sub );
            if( terms == nullptr )
            {
                return false;
            }
            for( const std::uint16_t u : *terms )
            {
                if( termStamp[u] != stamp )
                {
                    termStamp[u] = stamp;
                    ++sc.m;
                }
            }
            return true;
        };
        for( const std::string& sub : nameSubs )
        {
            if( hit( sub ) && sc.matched < 0xFFFFu )
            {
                ++sc.matched;
            }
        }
        for( const std::string& sub : containerSubs )
        {
            hit( sub );
        }
        for( const std::string& sub : pathSubsOf )
        {
            hit( sub );
        }
        return sc;
    }

    HowScore score( NodeId id )
    {
        const Symbol&            s = ing.symbols[id];
        std::vector<std::string> containerSubs;
        subtokens( s.scope, containerSubs );
        return scoreName( s.name, containerSubs, pathSubtokens( s.fileId ) );
    }
};

// the container-or-file-stem test a qualified identifier needs (case-insensitive)
inline bool iequalsAscii( std::string_view a, std::string_view b )
{
    return a.size() == b.size() && naminglens::toLowerAscii( a ) == naminglens::toLowerAscii( b );
}

inline std::string_view lastScopeSegment( std::string_view scope ) noexcept
{
    const std::size_t a = scope.rfind( "::" );
    const std::size_t b = scope.rfind( '.' );
    std::size_t       from = 0;
    if( a != std::string_view::npos )
    {
        from = a + 2;
    }
    if( b != std::string_view::npos && b + 1 > from )
    {
        from = b + 1;
    }
    return scope.substr( from );
}

inline std::string_view fileStem( std::string_view path ) noexcept
{
    const std::string_view base = path.substr( path.find_last_of( '/' ) + 1 );   // npos + 1 == 0: the whole path
    const std::size_t      cut  = base.find_last_of( '.' );
    return ( cut == std::string_view::npos || cut == 0 ) ? base : base.substr( 0, cut );
}

// ── seeds (prereg S5-S7) ──────────────────────────────────────────────────────────────────────────────────────────────
struct HowSeedPick
{
    NodeId id        = kNoNode;
    NodeId container = kNoNode;   // the container List A replaced by its members, when the seed came from one
};

// The resolved, followable call edges of `from` (prereg P): Source callable targets, never a split arm (outProv 3).
template<class Fn>
inline void forEachFollowableCallee( HowContext& cx, NodeId from, Fn&& fn )
{
    const Graph& g = cx.g;
    for( std::uint32_t k = g.outOff[from]; k < g.outOff[from + 1]; ++k )
    {
        const NodeId t       = g.outTargets[k];
        const bool   isSplit = k < g.outProv.size() && g.outProv[k] == 3;
        if( t < cx.ing.symbols.size() && cx.isSourceCallable( t ) )
        {
            fn( t, isSplit );
        }
    }
}

struct HowKeyed
{
    NodeId   id;
    HowScore sc;
    float    L;
};

// ordered x, p, m, callable before container, L, id (prereg S5)
inline bool listABefore( const IngestResult& ing, const HowKeyed& a, const HowKeyed& b ) noexcept
{
    if( a.sc.x != b.sc.x ) { return a.sc.x; }
    if( const int c = compareHowP( a.sc, b.sc ); c != 0 ) { return c > 0; }
    if( a.sc.m != b.sc.m ) { return a.sc.m > b.sc.m; }
    const bool ac = isHowCallableKind( ing.symbols[a.id].kind ), bc = isHowCallableKind( ing.symbols[b.id].kind );
    if( ac != bc ) { return ac; }
    if( a.L != b.L ) { return a.L > b.L; }
    return a.id < b.id;
}

// a container's members: p, m, L
inline bool memberBefore( const HowKeyed& a, const HowKeyed& b ) noexcept
{
    if( const int c = compareHowP( a.sc, b.sc ); c != 0 ) { return c > 0; }
    if( a.sc.m != b.sc.m ) { return a.sc.m > b.sc.m; }
    if( a.L != b.L ) { return a.L > b.L; }
    return a.id < b.id;
}

inline std::vector<HowSeedPick> buildListA( HowContext& cx, std::vector<HowScore>& scoreOf, std::vector<char>& scored )
{
    const IngestResult& ing = cx.ing;
    const HowQuestion&  q   = cx.q;
    const std::size_t   S   = ing.symbols.size();
    const auto scoreAt = [ & ]( NodeId id ) -> HowScore&
    {
        if( !scored[id] )
        {
            scoreOf[id] = cx.score( id );
            scored[id]  = 1;
        }
        return scoreOf[id];
    };
    // x: every identifier's last segment, narrowed by its qualifier when one matches a container or file stem
    std::vector<char> isNamed( S, 0 );
    for( const std::vector<std::string>& ident : q.identifiers )
    {
        const std::string_view last = ident.back();
        const std::string_view qual = ident.size() >= 2 ? std::string_view( ident[ ident.size() - 2 ] ) : std::string_view();
        std::vector<NodeId>    all, qualified;
        for( NodeId id = 0; id < S; ++id )
        {
            const Symbol& s = ing.symbols[id];
            if( s.name != last || !cx.isCandidate( id ) )
            {
                continue;
            }
            all.push_back( id );
            if( !qual.empty() && ( iequalsAscii( lastScopeSegment( s.scope ), qual ) || iequalsAscii( fileStem( rootRelPath( ing, s.fileId ) ), qual ) ) )
            {
                qualified.push_back( id );
            }
        }
        for( const NodeId id : qualified.empty() ? all : qualified )
        {
            isNamed[id] = 1;
        }
    }
    std::vector<HowKeyed> entries;
    for( NodeId id = 0; id < S; ++id )
    {
        if( !cx.isCandidate( id ) )
        {
            continue;
        }
        HowScore& sc = scoreAt( id );
        sc.x         = isNamed[id] != 0;
        const bool isHalfNamed = sc.count > 0 && 2u * sc.matched >= sc.count;
        if( sc.x || ( sc.m >= 1 && isHalfNamed ) )
        {
            entries.push_back( { id, sc, cx.lensScore( id ) } );
        }
    }
    std::sort( entries.begin(), entries.end(), [ & ]( const HowKeyed& a, const HowKeyed& b ) { return listABefore( ing, a, b ); } );
    std::vector<HowSeedPick> out;
    for( const HowKeyed& e : entries )
    {
        const Symbol& c = ing.symbols[e.id];
        if( !isHowContainerKind( c.kind ) )
        {
            out.push_back( { e.id, kNoNode } );
            continue;
        }
        // a container is replaced in place by its member callables (prereg S5)
        std::vector<HowKeyed> members;
        for( NodeId id = 0; id < S; ++id )
        {
            const Symbol& s = ing.symbols[id];
            if( id != e.id && s.fileId == c.fileId && s.sigStartByte >= c.sigStartByte && s.endByte <= c.endByte
                && isHowCallableKind( s.kind ) && cx.isCandidate( id ) )
            {
                members.push_back( { id, scoreAt( id ), cx.lensScore( id ) } );
            }
        }
        std::sort( members.begin(), members.end(), memberBefore );
        for( const HowKeyed& mbr : members )
        {
            out.push_back( { mbr.id, e.id } );
        }
    }
    return out;
}

inline std::vector<HowSeedPick> buildListB( HowContext& cx, std::span<const NodeId> window, std::vector<HowScore>& scoreOf, std::vector<char>& scored )
{
    std::vector<HowSeedPick> withTerm, rest;
    for( const NodeId id : window )
    {
        if( !isHowCallableKind( cx.ing.symbols[id].kind ) || !cx.isCandidate( id ) )
        {
            continue;
        }
        if( !scored[id] )
        {
            scoreOf[id] = cx.score( id );
            scored[id]  = 1;
        }
        ( scoreOf[id].m >= 1 ? withTerm : rest ).push_back( { id, kNoNode } );
    }
    withTerm.insert( withTerm.end(), rest.begin(), rest.end() );
    return withTerm;
}

// pick alternately A, B, A, … skipping anything picked or called directly by a picked seed (prereg S7)
inline std::vector<HowSeedPick> pickSeeds( HowContext& cx, const std::vector<HowSeedPick>& listA, const std::vector<HowSeedPick>& listB )
{
    std::vector<HowSeedPick> seeds;
    std::vector<char>        blocked( cx.ing.symbols.size(), 0 );
    std::size_t              ia = 0, ib = 0;
    const auto nextOf = [ & ]( const std::vector<HowSeedPick>& list, std::size_t& at ) -> const HowSeedPick*
    {
        while( at < list.size() )
        {
            const HowSeedPick& c = list[ at++ ];
            if( !blocked[c.id] )
            {
                return &c;
            }
        }
        return nullptr;
    };
    bool isTurnA = true;
    while( seeds.size() < kHowSeedMax )
    {
        const HowSeedPick* pick = isTurnA ? nextOf( listA, ia ) : nextOf( listB, ib );
        if( pick == nullptr )
        {
            pick = isTurnA ? nextOf( listB, ib ) : nextOf( listA, ia );
        }
        if( pick == nullptr )
        {
            break;
        }
        seeds.push_back( *pick );
        blocked[ pick->id ] = 1;
        forEachFollowableCallee( cx, pick->id, [ & ]( NodeId t, bool isSplit ) { if( !isSplit ) { blocked[t] = 1; } } );
        isTurnA = !isTurnA;
    }
    return seeds;
}

// ── hops (prereg P) ───────────────────────────────────────────────────────────────────────────────────────────────────
struct HowCalleeRow
{
    NodeId                     id      = kNoNode;   // the definition (the smallest arm's id on an ambiguous row)
    std::string                name;
    std::uint32_t              ambArms = 0;          // >1: the call resolved to this many definitions — listed, never followed
    HowScore                   sc;
    float                      L       = 0.0f;
    std::uint32_t              firstLine = UINT32_MAX;
    std::vector<std::uint32_t> lines;                // every call-site line in the hop, ascending
};

struct HowCallerRow
{
    NodeId                     id = kNoNode;
    std::vector<std::uint32_t> lines;
};

struct HowHop
{
    NodeId                    id        = kNoNode;
    int                       parent    = -1;       // index into the hop list; -1 for a seed
    int                       depth     = 0;
    NodeId                    container = kNoNode;  // a List-A member seed's container: its callers are instantiation sites
    std::string               sig;
    std::vector<HowCalleeRow> rows;                 // every distinct callee, priority order
    std::size_t               listed    = 0;        // rows shown (the cap, before the ceiling)
    std::size_t               shownRows = 0;        // rows rendered (≤ listed; the ceiling may trim a deeper hop's)
    std::vector<HowCallerRow> callers;              // a seed only: every distinct caller, priority order
    std::size_t               calleesBySelector = 0;   // what --callees=FILE:NAME lists (every same-named def in the file)
    std::size_t               callersBySelector = 0;   // what --callers=FILE:NAME lists for the callers' target
};

// How many distinct rows `--callees=FILE:NAME` (or `--callers=`) lists for `id`'s selector: the union over every definition
// of that name in that file (the selector resolves to all of them) — the --limit= a next= needs to return them in one page.
inline std::size_t selectorRowCount( const IngestResult& ing, const Graph& g, NodeId id, bool wantCallers )
{
    const Symbol&       s = ing.symbols[id];
    std::vector<NodeId> rows;
    const auto*         ro = g.inEdges.rowOffsets();
    const auto*         ci = g.inEdges.colIndices();
    for( NodeId d = 0; d < NodeId( ing.symbols.size() ); ++d )
    {
        if( ing.symbols[d].fileId != s.fileId || ing.symbols[d].name != s.name )
        {
            continue;
        }
        if( wantCallers )
        {
            rows.insert( rows.end(), ci + ro[d], ci + ro[d + 1] );
        }
        else
        {
            rows.insert( rows.end(), g.outTargets.begin() + g.outOff[d], g.outTargets.begin() + g.outOff[d + 1] );
        }
    }
    std::sort( rows.begin(), rows.end() );
    return std::size_t( std::unique( rows.begin(), rows.end() ) - rows.begin() );
}

inline bool calleeBefore( const HowCalleeRow& a, const HowCalleeRow& b ) noexcept
{
    const bool am = a.sc.m >= 1, bm = b.sc.m >= 1;
    if( am != bm ) { return am; }
    if( a.sc.m != b.sc.m ) { return a.sc.m > b.sc.m; }
    if( const int c = compareHowP( a.sc, b.sc ); c != 0 ) { return c > 0; }
    if( a.L != b.L ) { return a.L > b.L; }
    if( a.firstLine != b.firstLine ) { return a.firstLine < b.firstLine; }
    return a.id < b.id;
}

// one pass over the reference table: the call sites FROM `from`, as (callee name, line), sorted
inline std::vector<std::pair<std::string_view, std::uint32_t>> callSitesFrom( const IngestResult& ing, NodeId from )
{
    std::vector<std::pair<std::string_view, std::uint32_t>> sites;
    for( const Reference& r : ing.references )
    {
        if( r.fromSymbol != from || r.role != RefRole::Call || r.isCompose || r.isDocLink || r.lang == Lang::Markdown )
        {
            continue;
        }
        sites.emplace_back( r.calleeName, r.line );
    }
    std::sort( sites.begin(), sites.end() );
    sites.erase( std::unique( sites.begin(), sites.end() ), sites.end() );
    return sites;
}

inline std::vector<std::uint32_t> linesNaming( const std::vector<std::pair<std::string_view, std::uint32_t>>& sites, std::string_view name )
{
    std::vector<std::uint32_t> lines;
    for( auto it = std::lower_bound( sites.begin(), sites.end(), std::make_pair( name, std::uint32_t( 0 ) ) );
         it != sites.end() && it->first == name; ++it )
    {
        lines.push_back( it->second );
    }
    return lines;
}

inline void buildHopRows( HowContext& cx, HowHop& hop )
{
    const IngestResult& ing   = cx.ing;
    const auto          sites = callSitesFrom( ing, hop.id );
    std::vector<NodeId> splitArms;
    forEachFollowableCallee( cx, hop.id, [ & ]( NodeId t, bool isSplit )
    {
        if( isSplit )
        {
            splitArms.push_back( t );
            return;
        }
        HowCalleeRow row;
        row.id    = t;
        row.name  = ing.symbols[t].name;
        row.sc    = cx.score( t );
        row.L     = cx.lensScore( t );
        row.lines = linesNaming( sites, row.name );
        row.firstLine = row.lines.empty() ? UINT32_MAX : row.lines.front();
        hop.rows.push_back( std::move( row ) );
    } );
    // an edge split over several definitions: ONE row per called name, amb= its arm count, never followed
    std::sort( splitArms.begin(), splitArms.end(), [ & ]( NodeId a, NodeId b )
               { return ing.symbols[a].name != ing.symbols[b].name ? ing.symbols[a].name < ing.symbols[b].name : a < b; } );
    for( std::size_t i = 0; i < splitArms.size(); )
    {
        std::size_t j = i;
        while( j < splitArms.size() && ing.symbols[ splitArms[j] ].name == ing.symbols[ splitArms[i] ].name )
        {
            ++j;
        }
        HowCalleeRow row;
        row.id      = splitArms[i];
        row.name    = ing.symbols[ splitArms[i] ].name;
        row.ambArms = std::uint32_t( j - i );
        row.sc      = cx.scoreName( row.name, {}, {} );
        row.lines   = linesNaming( sites, row.name );
        row.firstLine = row.lines.empty() ? UINT32_MAX : row.lines.front();
        hop.rows.push_back( std::move( row ) );
        i = j;
    }
    std::sort( hop.rows.begin(), hop.rows.end(), calleeBefore );
    hop.listed            = std::min( hop.rows.size(), hop.depth == 0 ? kHowSeedCalleeRows : kHowDeepCalleeRows );
    hop.shownRows         = hop.listed;
    hop.calleesBySelector = selectorRowCount( ing, cx.g, hop.id, /*wantCallers=*/false );
}

// a seed's callers (a List-A member's: its container's instantiation sites), tier then task words then rank then place
inline void buildCallerRows( HowContext& cx, HowHop& hop )
{
    const IngestResult& ing    = cx.ing;
    const NodeId        target = hop.container != kNoNode ? hop.container : hop.id;
    const auto*         ro     = cx.g.inEdges.rowOffsets();
    const auto*         ci     = cx.g.inEdges.colIndices();
    std::vector<HowKeyed> keyed;
    for( std::uint32_t k = ro[target]; k < ro[target + 1]; ++k )
    {
        const NodeId c = ci[k];
        if( c < ing.symbols.size() )
        {
            keyed.push_back( { c, cx.score( c ), cx.lensScore( c ) } );
        }
    }
    std::sort( keyed.begin(), keyed.end(), []( const HowKeyed& a, const HowKeyed& b ) { return a.id < b.id; } );
    keyed.erase( std::unique( keyed.begin(), keyed.end(), []( const HowKeyed& a, const HowKeyed& b ) { return a.id == b.id; } ), keyed.end() );
    std::sort( keyed.begin(), keyed.end(), [ & ]( const HowKeyed& a, const HowKeyed& b )
    {
        const bool as = cx.isSourceFile( ing.symbols[a.id].fileId ), bs = cx.isSourceFile( ing.symbols[b.id].fileId );
        if( as != bs ) { return as; }
        if( a.sc.m != b.sc.m ) { return a.sc.m > b.sc.m; }
        if( a.L != b.L ) { return a.L > b.L; }
        const std::string& pa = ing.files[ ing.symbols[a.id].fileId ];
        const std::string& pb = ing.files[ ing.symbols[b.id].fileId ];
        if( pa != pb ) { return pa < pb; }
        if( ing.symbols[a.id].line != ing.symbols[b.id].line ) { return ing.symbols[a.id].line < ing.symbols[b.id].line; }
        return a.id < b.id;
    } );
    hop.callersBySelector = selectorRowCount( ing, cx.g, target, /*wantCallers=*/true );
    const std::string_view targetName = ing.symbols[target].name;
    for( std::size_t i = 0; i < keyed.size(); ++i )
    {
        HowCallerRow row;
        row.id = keyed[i].id;
        if( i < kHowCallerRows )
        {
            row.lines = linesNaming( callSitesFrom( ing, row.id ), targetName );
        }
        hop.callers.push_back( std::move( row ) );
    }
}

struct HowPoolEntry
{
    NodeId        id;
    int           parent;
    int           depth;
    std::uint32_t line;
    HowScore      sc;
    float         L;
};

// best: m ≥ 1, m, p, L, shallower, earlier call site (the earlier-expanded parent, then the line), id
inline bool poolBefore( const HowPoolEntry& a, const HowPoolEntry& b ) noexcept
{
    const bool am = a.sc.m >= 1, bm = b.sc.m >= 1;
    if( am != bm ) { return am; }
    if( a.sc.m != b.sc.m ) { return a.sc.m > b.sc.m; }
    if( const int c = compareHowP( a.sc, b.sc ); c != 0 ) { return c > 0; }
    if( a.L != b.L ) { return a.L > b.L; }
    if( a.depth != b.depth ) { return a.depth < b.depth; }
    if( a.parent != b.parent ) { return a.parent < b.parent; }
    if( a.line != b.line ) { return a.line < b.line; }
    return a.id < b.id;
}

struct HowPath
{
    std::vector<HowHop> hops;
    std::vector<NodeId> waiting;    // eligible callees the hop cap left unexpanded, best first (capped iff non-empty)
};

inline HowPath walkHowPath( HowContext& cx, const std::vector<HowSeedPick>& seeds )
{
    HowPath           out;
    std::vector<char> isHop( cx.ing.symbols.size(), 0 );
    std::vector<HowPoolEntry> pool;
    const auto addHop = [ & ]( NodeId id, int parent, int depth, NodeId container )
    {
        HowHop hop;
        hop.id        = id;
        hop.parent    = parent;
        hop.depth     = depth;
        hop.container = container;
        buildHopRows( cx, hop );
        isHop[id] = 1;
        const int self = int( out.hops.size() );
        for( std::size_t k = 0; k < hop.listed; ++k )
        {
            const HowCalleeRow& r = hop.rows[k];
            if( r.ambArms == 0 && depth + 1 <= kHowDepthMax )
            {
                pool.push_back( { r.id, self, depth + 1, r.firstLine, r.sc, r.L } );
            }
        }
        out.hops.push_back( std::move( hop ) );
    };
    for( const HowSeedPick& s : seeds )
    {
        addHop( s.id, -1, 0, s.container );
    }
    const auto eligible = [ & ]( const HowPoolEntry& e ) { return !isHop[e.id] && ( e.sc.m >= 1 || e.L > 0.0f ); };
    while( out.hops.size() < kHowHopMax )
    {
        const HowPoolEntry* best = nullptr;
        for( const HowPoolEntry& e : pool )
        {
            if( eligible( e ) && ( best == nullptr || poolBefore( e, *best ) ) )
            {
                best = &e;
            }
        }
        if( best == nullptr )
        {
            break;
        }
        const HowPoolEntry chosen = *best;
        addHop( chosen.id, chosen.parent, chosen.depth, kNoNode );
    }
    std::vector<HowPoolEntry> left;
    for( const HowPoolEntry& e : pool )
    {
        if( eligible( e ) )
        {
            left.push_back( e );
        }
    }
    std::sort( left.begin(), left.end(), poolBefore );
    for( const HowPoolEntry& e : left )
    {
        if( std::find( out.waiting.begin(), out.waiting.end(), e.id ) == out.waiting.end() )
        {
            out.waiting.push_back( e.id );
        }
    }
    for( HowHop& hop : out.hops )
    {
        if( hop.depth == 0 )
        {
            buildCallerRows( cx, hop );
        }
    }
    return out;
}

// ── selected body lines (prereg B) ────────────────────────────────────────────────────────────────────────────────────
struct HowBodyLine
{
    std::uint32_t line     = 0;
    std::uint8_t  priority = 5;      // 1 calls to a hop or with a term, 2 guards with a term or parameter, 3 other calls,
                                     // 4 field writes, 5 the rest (first line, field-only guards, exits)
    std::string   text;              // "N: …", scrubbed for CDATA
    bool          isKept   = false;
};

struct HowBody
{
    std::size_t              hop = 0;
    std::uint32_t            linesTotal = 0;
    std::vector<HowBodyLine> selected;     // source order
};


inline bool startsWithWord( std::string_view s, std::string_view w ) noexcept
{
    return s.starts_with( w ) && ( s.size() == w.size() || !isHowIdChar( s[ w.size() ] ) );
}

// parameter names off a one-line signature: per top-level comma, the name before `:` (Python/TS/Rust), else the last
// identifier before any `=` default (C-family, Java, Go's first word excepted — a heuristic, never a claim)
inline std::vector<std::string> paramNamesOf( std::string_view sig )
{
    std::vector<std::string> names;
    const std::size_t open = sig.find( '(' );
    if( open == std::string_view::npos )
    {
        return names;
    }
    int         depth = 0;
    std::size_t start = open + 1;
    const auto  takePiece = [ & ]( std::string_view piece )
    {
        const std::size_t eq = piece.find( '=' );
        if( eq != std::string_view::npos )
        {
            piece = piece.substr( 0, eq );
        }
        std::size_t colon = std::string_view::npos;
        for( std::size_t k = 0; k < piece.size(); ++k )
        {
            if( piece[k] == ':' && ( k + 1 >= piece.size() || piece[k + 1] != ':' ) && ( k == 0 || piece[k - 1] != ':' ) )
            {
                colon = k;
                break;
            }
        }
        if( colon != std::string_view::npos )
        {
            piece = piece.substr( 0, colon );
        }
        std::string_view last;
        for( std::size_t k = 0; k < piece.size(); )
        {
            if( isHowIdStart( piece[k] ) && ( k == 0 || !isHowIdChar( piece[k - 1] ) ) )
            {
                std::size_t e = k;
                while( e < piece.size() && isHowIdChar( piece[e] ) )
                {
                    ++e;
                }
                last = piece.substr( k, e - k );
                k    = e;
                continue;
            }
            ++k;
        }
        if( !last.empty() )
        {
            names.emplace_back( last );
        }
    };
    for( std::size_t k = open + 1; k < sig.size(); ++k )
    {
        const char c = sig[k];
        if( c == '(' || c == '<' || c == '[' || c == '{' )
        {
            ++depth;
        }
        else if( ( c == ')' || c == '>' || c == ']' || c == '}' ) && depth > 0 )
        {
            --depth;
        }
        else if( c == ')' && depth == 0 )
        {
            takePiece( sig.substr( start, k - start ) );
            break;
        }
        else if( c == ',' && depth == 0 )
        {
            takePiece( sig.substr( start, k - start ) );
            start = k + 1;
        }
    }
    return names;
}

struct HowLineFacts
{
    bool isInRepoCall   = false;   // an in-repo callable or container name followed by `(`
    bool isHopCall      = false;   // …that is a hop's name
    bool isAnyCall      = false;   // any identifier followed by `(`
    bool hasTerm        = false;
    bool hasParam       = false;
    bool hasField       = false;   // this. self. -> (and Ruby's @)
    bool isFieldWrite   = false;
    bool isGuard        = false;
    bool isExit         = false;
};

struct HowLineVocab
{
    const HowQuestion&                      q;
    const HashMap<std::string_view, char>&  inRepoNames;
    const HashMap<std::string_view, char>&  hopNames;
};

inline HowLineFacts lineFacts( std::string_view t, const HowLineVocab& v, const std::vector<std::string>& params )
{
    HowLineFacts f;
    std::vector<std::string> subs;
    for( std::size_t k = 0; k < t.size(); )
    {
        if( !isHowIdStart( t[k] ) || ( k > 0 && isHowIdChar( t[k - 1] ) ) )
        {
            ++k;
            continue;
        }
        std::size_t e = k;
        while( e < t.size() && isHowIdChar( t[e] ) )
        {
            ++e;
        }
        const std::string_view word = t.substr( k, e - k );
        if( e < t.size() && t[e] == '(' )   // "followed by `(`": immediately — prose in a comment spells "name (…)"
        {
            f.isAnyCall = true;
            if( v.inRepoNames.contains( word ) )
            {
                f.isInRepoCall = true;
                f.isHopCall    = f.isHopCall || v.hopNames.contains( word );
            }
        }
        if( !f.hasTerm )
        {
            subs.clear();
            subtokens( word, subs );
            for( const std::string& s : subs )
            {
                if( v.q.match( s ) != nullptr )
                {
                    f.hasTerm = true;
                    break;
                }
            }
        }
        if( !f.hasParam && std::find( params.begin(), params.end(), word ) != params.end() )
        {
            f.hasParam = true;
        }
        k = e;
    }
    f.hasField = t.find( "this." ) != std::string_view::npos || t.find( "self." ) != std::string_view::npos
              || t.find( "->" ) != std::string_view::npos || t.find( '@' ) != std::string_view::npos;
    // an assignment: `=` (or op=) that is not `==`, `!=`, `<=`, `>=`, `=>`
    for( std::size_t k = 0; k < t.size(); ++k )
    {
        if( t[k] != '=' )
        {
            continue;
        }
        const char next = k + 1 < t.size() ? t[k + 1] : '\0';
        const char prev = k > 0 ? t[k - 1] : '\0';
        if( next == '=' || next == '>' || prev == '=' || prev == '!' || prev == '<' || prev == '>' )
        {
            continue;
        }
        const std::string_view lhs = t.substr( 0, k );
        bool isMemberLhs = lhs.find( "this." ) != std::string_view::npos || lhs.find( "self." ) != std::string_view::npos
                        || lhs.find( "->" ) != std::string_view::npos || lhs.find( '@' ) != std::string_view::npos;
        for( std::size_t d = 1; !isMemberLhs && d + 1 < lhs.size(); ++d )
        {
            isMemberLhs = lhs[d] == '.' && isHowIdChar( lhs[d - 1] ) && isHowIdStart( lhs[d + 1] );
        }
        f.isFieldWrite = isMemberLhs;
        break;
    }
    std::string_view head = t;
    while( !head.empty() && ( head.front() == '}' || head.front() == ' ' || head.front() == '\t' ) )
    {
        head.remove_prefix( 1 );
    }
    static constexpr std::string_view kGuards[] = { "if", "elif", "else if", "switch", "case", "catch", "except", "when", "match", "while" };
    for( const std::string_view gw : kGuards )
    {
        if( startsWithWord( head, gw ) )
        {
            f.isGuard = true;
            break;
        }
    }
    f.isExit = ( startsWithWord( head, "return" ) || startsWithWord( head, "throw" ) || startsWithWord( head, "raise" ) )
            && ( f.isAnyCall || f.hasField || head.find( '.' ) != std::string_view::npos );
    return f;
}

// the class a selected line falls in (0 = not selected)
inline std::uint8_t linePriority( const HowLineFacts& f, bool isFirst ) noexcept
{
    if( f.isInRepoCall && ( f.isHopCall || f.hasTerm ) ) { return 1; }
    if( f.isGuard && ( f.hasTerm || f.hasParam ) )       { return 2; }
    if( f.isInRepoCall )                                 { return 3; }
    if( f.isFieldWrite )                                 { return 4; }
    if( isFirst || ( f.isGuard && f.hasField ) || f.isExit ) { return 5; }
    return 0;
}

// fill one body's kept lines in priority order (ties in source order) under `budget` bytes of CDATA text
inline std::size_t keepBodyLines( HowBody& b, std::size_t budget )
{
    std::vector<std::size_t> order( b.selected.size() );
    for( std::size_t i = 0; i < order.size(); ++i )
    {
        order[i] = i;
    }
    std::stable_sort( order.begin(), order.end(), [ & ]( std::size_t x, std::size_t y ) { return b.selected[x].priority < b.selected[y].priority; } );
    std::size_t used = 0, keptCount = 0;
    for( const std::size_t i : order )
    {
        const std::size_t cost = b.selected[i].text.size() + ( keptCount > 0 ? 1 : 0 );
        if( used + cost <= budget )
        {
            b.selected[i].isKept = true;
            used += cost;
            ++keptCount;
        }
    }
    return used;
}

inline std::vector<HowBody> selectBodies( HowContext& cx, const HowPath& path, const HowQuestion& q, RedactCounts* redact,
                                          HashMap<std::uint32_t, std::string>& srcCache )
{
    const IngestResult& ing = cx.ing;
    HashMap<std::string_view, char> inRepoNames;
    inRepoNames.reserve( ing.symbols.size() );
    for( const Symbol& s : ing.symbols )
    {
        if( isHowCallableKind( s.kind ) || isHowContainerKind( s.kind ) )
        {
            inRepoNames.emplace( std::string_view( s.name ), 1 );
        }
    }
    HashMap<std::string_view, char> hopNames;
    hopNames.reserve( path.hops.size() );
    for( const HowHop& h : path.hops )
    {
        hopNames.emplace( std::string_view( ing.symbols[h.id].name ), 1 );
    }
    const HowLineVocab vocab{ q, inRepoNames, hopNames };
    std::vector<HowBody> bodies;
    std::size_t          leftAll = kHowBodyBytesAll;
    for( std::size_t hi = 0; hi < path.hops.size() && bodies.size() < kHowBodyHops; ++hi )
    {
        const Symbol& s = ing.symbols[ path.hops[hi].id ];
        if( !hasHowBody( s ) || s.fileId >= ing.files.size() )
        {
            continue;
        }
        if( !srcCache.contains( s.fileId ) )
        {
            std::string text;
            if( std::FILE* in = std::fopen( diskPath( ing, s.fileId ).c_str(), "rb" ) )
            {
                char        buf[ 4096 ];
                std::size_t n;
                while( ( n = std::fread( buf, 1, sizeof( buf ), in ) ) > 0 )
                {
                    text.append( buf, n );
                }
                std::fclose( in );
            }
            srcCache.emplace( s.fileId, std::move( text ) );
        }
        const std::string& src = srcCache[ s.fileId ];
        if( s.sigStartByte >= src.size() || s.endByte > src.size() || s.sigStartByte >= s.endByte )
        {
            continue;   // the file moved under the index: no body to select from (its hop row still stands)
        }
        std::size_t from = s.sigStartByte;
        while( from > 0 && src[from - 1] != '\n' )
        {
            --from;   // the def's whole first line, so numbering starts at s.line
        }
        std::string body = src.substr( from, s.endByte - from );
        redactInPlace( body, redact );
        const std::vector<std::string> params = paramNamesOf( path.hops[hi].sig );
        HowBody                        b;
        b.hop = hi;
        std::size_t lineIndex = 0;
        for( std::size_t a = 0; a < body.size(); ++lineIndex )
        {
            std::size_t e = body.find( '\n', a );
            if( e == std::string::npos )
            {
                e = body.size();
            }
            const std::string_view t = trimWs( std::string_view( body ).substr( a, e - a ) );
            const std::uint8_t     pr = t.empty() ? 0 : linePriority( lineFacts( t, vocab, params ), lineIndex == 0 );
            if( pr != 0 )
            {
                HowBodyLine l;
                l.line     = s.line + std::uint32_t( lineIndex );
                l.priority = pr;
                l.text     = std::to_string( l.line ) + ": ";
                appendCdataSafe( t, l.text );
                b.selected.push_back( std::move( l ) );
            }
            a = e + 1;
        }
        b.linesTotal = std::uint32_t( lineIndex );
        if( b.selected.empty() )
        {
            continue;
        }
        leftAll -= keepBodyLines( b, std::min( kHowBodyBytesEach, leftAll ) );
        bodies.push_back( std::move( b ) );
    }
    return bodies;
}

// the lens window W: the top kForLensDefaultTopN by (score desc, id asc), after the relevance floor — the --for
// lens's own two calls (serialize.h relevanceFloorCut; the radix order its <sigs> selects with)
inline std::vector<NodeId> howWindow( const std::vector<float>& rank )
{
    const int           topN = relevanceFloorCut( rank, kForLensDefaultTopN ).topN;
    std::vector<NodeId> ids( rank.size() );
    for( NodeId i = 0; i < NodeId( rank.size() ); ++i )
    {
        ids[i] = i;
    }
    rw::sortutil::radixSortByScoreDescId( ids, rank );
    ids.resize( std::min<std::size_t>( std::size_t( std::max( topN, 0 ) ), ids.size() ) );
    return ids;
}

// est_tokens= for a finished how document: markup at the map rate, body lines at the body rate; the attribute's own
// digits are part of what it prices (the --for fixpoint, verbs_for.h finishForLensHeaderPriced).
inline std::string howEstAttr( std::size_t docBytesWithoutAttr, std::size_t cdataBytes )
{
    const auto price = [ & ]( std::size_t attrBytes )
    {
        const std::size_t markup = docBytesWithoutAttr + attrBytes - cdataBytes;
        return tokensForEmittedBytes( markup, kBytesPerTokenDefault ) + tokensForEmittedBytes( cdataBytes, kBytesPerTokenBody );
    };
    std::size_t est  = price( 0 );
    std::string attr = " est_tokens=\"" + std::to_string( est ) + "\"";
    for( int pass = 0; pass < 4; ++pass )
    {
        const std::size_t next = price( attr.size() );
        if( next == est )
        {
            break;
        }
        est  = next;
        attr = " est_tokens=\"" + std::to_string( est ) + "\"";
    }
    return attr;
}

// The F2 clauses every dialect carries, in one order (the session dictionary holds each one verbatim).
inline std::string howLegendClauses()
{
    std::string s;
    s.reserve( 1600 );
    s += kHowShapeLegend;
    s += kHowPathLegend;
    s += kHowHopLegend;
    s += kHowBodyLegend;
    s += kHowNamesLegend;
    s += kHowEstLegend;
    return s;
}

// ── the canonical answer around the sections ──────────────────────────────────────────────────────────────────────────
// The CLI default (compact) --for answer is the unit the ceiling and §2 measure. Every surface builds THIS head from its
// own ranking — the same inputs on all four (the --for lens's ranking, its term evidence, route, notes, cap attributes and
// the root) — so the trim it decides is the same trim everywhere and the sections stay byte-identical.
struct HowHead
{
    std::string_view task;
    std::string      routeNote;
    std::string_view rootArg;
    std::string      confAttrs;          // confidence= margin_pct= [coverage=] — deriveForConfidence, as the lens
    std::string      confNote;           // its full-dialect reading (the MCP `for` legend carries it)
    bool             hasCoverage = false;
    std::string      atStamp;            // gitstamp::stampAt — "" off git
    std::uint32_t    mentionAnchored = 0;
    std::uint32_t    docMentions     = 0;
    std::string      capAttrs;           // the indexing caps that cut the ranking (mention.h CapDisclosure)
    std::string      notes;              // the data notes, compact (compactForNote): mention, cochange, doc mentions, floor
    bool             isWeak = false;     // the top raw lexical score is under the evidence bar (lexical.h)
    std::string      hdrXml;             // <hdr p= of=/> rows
};

struct HowHeadInputs
{
    std::string_view task;
    std::string_view routeNote;
    const char*      routeTag;           // "name-exact" | "subtoken+body" | "no-route"
    std::string_view rootArg;
    std::string_view atStamp;
    std::string_view mentionNote;        // any surface's spelling: compactForNote reads the numbers, not the sentence
    std::string_view boostNote;
    std::string_view docMentionNote;
    std::string_view capAttrs;
    bool             isWeak;
};

// the first unsigned number after `key` in `note` (0 when absent)
inline std::uint32_t noteNumberAfter( std::string_view note, std::string_view key ) noexcept
{
    const std::size_t at = note.find( key );
    if( at == std::string_view::npos )
    {
        return 0;
    }
    std::uint32_t n = 0;
    for( std::size_t i = at + key.size(); i < note.size() && note[i] >= '0' && note[i] <= '9'; ++i )
    {
        n = n * 10 + std::uint32_t( note[i] - '0' );
    }
    return n;
}

// A note with its cap clauses taken out (mention.h capDisclosureNote: " [cut: … not shown here]"): the MCP twins append
// them to the lift notes where the CLI keeps them apart, and the head states the caps once, from capAttrs (howCapNote).
inline std::string withoutCapClauses( std::string_view note )
{
    std::string out( note );
    for( std::size_t at = out.find( " [cut:" ); at != std::string::npos; at = out.find( " [cut:", at ) )
    {
        const std::size_t end = out.find( "not shown here]", at );
        if( end == std::string::npos )
        {
            break;
        }
        out.erase( at, end + std::string_view( "not shown here]" ).size() - at );
    }
    return out;
}

inline HowHead howHeadFor( const IngestResult& ing, const std::vector<float>& rank, const LexTermEvidence& evidence, const HowHeadInputs& in )
{
    HowHead h;
    h.task      = in.task;
    h.routeNote = in.routeNote;
    h.rootArg   = in.rootArg;
    h.atStamp   = in.atStamp;
    h.capAttrs  = in.capAttrs;
    h.isWeak    = in.isWeak;
    // confidence=/margin_pct=/coverage= — the lens's own three calls (verbs_for.h runForLens, mcpverbs.h forTaskText)
    const AdaptiveCut       cut      = adaptiveCut( rank, 5, std::size_t( kForLensDefaultTopN ), /*scanFullDistribution=*/true );
    const bool              homonym  = isAdaptiveHomonymDecline( isNameExactRouteTag( in.routeTag ), cut, 5 );
    const RelevanceFloorCut floor    = relevanceFloorCut( rank, kForLensDefaultTopN );
    ForConfidence           conf     = deriveForConfidence( cut, floor.topN, homonym );
    const int               coverage = forCoveragePct( evidence, topLensId( rank ) );
    if( forAnswerIsThin( coverage, distinctFilesOf( ing, howWindow( rank ) ) ) && coverage >= 0 )
    {
        conf.attrs   += " coverage=\"" + std::to_string( coverage ) + "\"";
        conf.note    += kForCoverageLegend;
        h.hasCoverage = true;
    }
    h.confAttrs = std::move( conf.attrs );
    h.confNote  = std::move( conf.note );
    // the counts the root states, read off the notes every surface writes from the same numbers
    if( const std::uint32_t files = noteNumberAfter( in.mentionNote, "[mention anchor: " ); in.mentionNote.find( "[mention anchor: " ) != std::string_view::npos )
    {
        h.mentionAnchored = files + noteNumberAfter( in.mentionNote.substr( in.mentionNote.find( " + " ) ), " + " );
    }
    h.docMentions = noteNumberAfter( in.docMentionNote, "[doc mentions: " );
    h.notes = compactForNote( withoutCapClauses( in.mentionNote ) ) + compactForNote( withoutCapClauses( in.boostNote ) )
            + compactForNote( withoutCapClauses( in.docMentionNote ) ) + compactForNote( floor.note );
    h.hdrXml = renderNamedHeaderRowsXml( ing, forNamedHeaderRows( ing, in.task ), in.rootArg );
    return h;
}

// The root every how answer opens with: BASE's --for root attributes (minus the body posture and budget_bytes=), then
// shape= and lens=; schema= rides the compact dialect only, as on the lens.
inline std::string howRootOpen( const HowHead& h, bool withSchema )
{
    std::string doc   = ctxRootOpen( h.task, h.routeNote, h.rootArg );
    std::string attrs = h.confAttrs + ( h.atStamp.empty() ? std::string() : " at=\"" + h.atStamp + "\"" );
    attrs += h.mentionAnchored > 0 ? " mention_anchored=\"" + std::to_string( h.mentionAnchored ) + "\"" : std::string();
    attrs += h.docMentions > 0 ? " doc_mentions=\"" + std::to_string( h.docMentions ) + "\"" : std::string();
    attrs += withSchema ? " schema=\"ripwire.for/v1\"" : "";
    attrs += h.capAttrs;
    attrs += " shape=\"how\" lens=\"" + std::string( kHowLensValue ) + "\"";
    const std::size_t close = doc.find( '>' );
    doc.insert( close == std::string::npos ? doc.size() : close, attrs );
    return doc;
}

// the cap clause, self-defining (mention.h capDisclosureNote's spelling, over all the caps at once)
inline std::string howCapNote( std::string_view capAttrs )
{
    CapDisclosure all;
    all.xml = std::string( capAttrs );
    return capDisclosureNote( all );
}

// THE canonical answer: the CLI default (compact) --for document around `sectionsXml`.
inline std::string howCompactDocument( const HowHead& h, std::string_view sectionsXml, std::size_t cdataBytes )
{
    std::string doc = howRootOpen( h, /*withSchema=*/true );
    doc += "<!-- ripwire for schema=ripwire.for/v1 shape=how: task= the query";
    doc += h.routeNote.empty() ? std::string_view() : kForRouteCodeLegend;
    doc += kForCompactConfidenceClause;
    doc += h.hasCoverage ? kForCompactCoverageClause : std::string_view();
    doc += howLegendClauses();
    doc += h.hdrXml.empty() ? std::string_view() : kForCompactHdrClause;
    doc += h.notes;
    doc += howCapNote( h.capAttrs );
    doc += " -->";
    doc += forRootRelPathsLegendShort( !h.rootArg.empty(), !h.atStamp.empty() );
    if( h.isWeak )
    {
        const std::size_t close = doc.rfind( " -->" );
        doc.insert( close == std::string::npos ? doc.size() : close, " weak=\"1\"" );
    }
    doc += h.hdrXml;
    doc += sectionsXml;
    doc += "</ctx>";
    const std::string est   = howEstAttr( doc.size(), cdataBytes );
    const std::size_t close = doc.find( '>' );
    doc.insert( close, est );
    return doc;
}

// The FULL-dialect how answer: the CLI --legend=full answer, and the MCP `for` dialect (whose lens legend opens
// `<!-- ripwire lens for "TASK"` — the shape legenddict.h's ref posture recognises). `notes` is the surface's own prose
// notes and `capNote` its cap clause ("" where the notes already carry it).
inline std::string howFullDocument( const HowHead& h, std::string_view taskNote, std::string_view notes, std::string_view capNote,
                                    std::string_view sectionsXml, std::size_t cdataBytes )
{
    std::string doc = howRootOpen( h, /*withSchema=*/false );
    doc += "<!-- ripwire lens for \"";
    doc += taskNote;
    doc += "\"";
    doc += notes;
    doc += h.confNote;
    doc += kHowTaskLegend;
    doc += h.routeNote.empty() ? std::string_view() : kForRouteCodeLegend;
    doc += howLegendClauses();
    doc += h.hdrXml.empty() ? std::string_view() : kForHdrLegend;
    doc += capNote;
    doc += " -->";
    doc += forRootRelPathsLegendShort( !h.rootArg.empty(), !h.atStamp.empty() );
    if( h.isWeak )
    {
        const std::size_t close = doc.rfind( " -->" );
        doc.insert( close == std::string::npos ? doc.size() : close, " weak=\"1\"" );
    }
    doc += h.hdrXml;
    doc += sectionsXml;
    doc += "</ctx>";
    const std::string est   = howEstAttr( doc.size(), cdataBytes );
    const std::size_t close = doc.find( '>' );
    doc.insert( close, est );
    return doc;
}

// ── the answer ────────────────────────────────────────────────────────────────────────────────────────────────────────
struct HowInputs
{
    const IngestResult&       ing;
    const Graph&              g;
    std::string_view          task;
    const std::vector<float>& rank;      // the --for lens's default ranking, final (every lift applied)
    std::string_view          rootArg;   // single-root runs: p= is relative to it
    RedactCounts*             redact;    // REQUIRED (no default): signatures and body lines are emitted source text
    const HowHead&            head;      // the canonical answer around the sections — what the ceiling measures
};

struct HowSections
{
    std::string xml;             // `<path …>` through `</names>` — identical on all four surfaces
    std::size_t cdataBytes = 0;  // the body-line bytes inside it (priced at the body rate)
    std::size_t seedCount  = 0;
    bool        isOverCeiling = false;
};


struct HowModel
{
    HowPath              path;
    std::vector<HowBody> bodies;
    std::vector<NodeId>  nameRows;      // W rows not hops, rank order
    std::size_t          namesShown = 0;
    std::size_t          past       = 0;
    std::size_t          seedCount  = 0;
    bool                 isOverCeiling = false;
    std::size_t          cutNames    = 0;   // what the ceiling took, by kind — disclosed on <path> as cut_names= …
    std::size_t          cutCallees  = 0;
    std::size_t          cutLines    = 0;
};

class HowRenderer
{
public:
    HowRenderer( const IngestResult& ing, std::string_view rootArg, std::string_view task )
        : m_ing( ing ), m_rootArg( rootArg ), m_task( task )
    {
    }

    std::string pathOf( std::uint32_t f ) const
    {
        return lensRowPath( m_ing, f, m_rootArg );   // the --for rows' own p= spelling (serialize.h)
    }
    std::string loc( NodeId id ) const
    {
        const Symbol& s = m_ing.symbols[id];
        return pathOf( s.fileId ) + ":" + std::to_string( s.line );
    }
    std::string sel( NodeId id ) const
    {
        return pathOf( m_ing.symbols[id].fileId ) + ":" + m_ing.symbols[id].name;
    }
    std::string esc( std::string_view s )
    {
        return std::string( escapeXml( s, m_esc ) );
    }
    static std::string lineList( const std::vector<std::uint32_t>& lines )
    {
        std::string out;
        for( std::size_t i = 0; i < lines.size() && i < kHowCallSiteLines; ++i )
        {
            out += i == 0 ? "" : ",";
            out += std::to_string( lines[i] );
        }
        return out;
    }

    std::string render( const HowModel& m, std::size_t* cdataBytesOut )
    {
        // the --limit= that makes a --callees=/--callers= follow-up return every row in ONE page (their default page is
        // kCallHierarchyRowCap rows, pageview.h); "" when the default page already holds them all
        const auto pageAllRows = []( std::size_t rowCount )
        { return countFieldIfAbove( std::uint32_t( rowCount ), std::uint32_t( kCallHierarchyRowCap ), " --limit=" ); };
        const HowPath& p = m.path;
        std::string    x = "<path seeds=\"" + std::to_string( m.seedCount ) + "\" hops=\"" + std::to_string( p.hops.size() ) + "\"";
        if( !p.waiting.empty() )
        {
            std::string next = "--expand=";
            for( std::size_t i = 0; i < p.waiting.size() && i < kHowNextExpandNames; ++i )
            {
                next += i == 0 ? "" : ",";
                next += sel( p.waiting[i] );
            }
            x += " capped=\"1\" next=\"" + esc( next ) + "\"";
        }
        const struct { const char* attr; std::size_t n; } kCuts[] = { { " cut_names=\"", m.cutNames }, { " cut_callees=\"", m.cutCallees },
                                                                      { " cut_lines=\"", m.cutLines } };
        for( const auto& [ attr, n ] : kCuts )
        {
            x += n > 0 ? attr + std::to_string( n ) + "\"" : std::string();
        }
        if( m.isOverCeiling )
        {
            x += " over_ceiling=\"1\"";
        }
        x += ">";
        // chains: a hop extends the running chain when its parent is the chain's last hop, else a new chain starts at
        // its branch point (`a > b > c | b > d`)
        int lastOfChain = -1;
        for( std::size_t i = 0; i < p.hops.size(); ++i )
        {
            const HowHop& h = p.hops[i];
            const std::string name = esc( m_ing.symbols[h.id].name );
            if( h.parent < 0 )
            {
                x += i == 0 ? "" : " | ";
                x += name;
            }
            else if( h.parent == lastOfChain )
            {
                x += " &gt; " + name;
            }
            else
            {
                x += " | " + esc( m_ing.symbols[ p.hops[ std::size_t( h.parent ) ].id ].name ) + " &gt; " + name;
            }
            lastOfChain = int( i );
        }
        x += "</path>";
        std::vector<char> isHopId( m_ing.symbols.size(), 0 );
        for( const HowHop& h : p.hops )
        {
            isHopId[h.id] = 1;
        }
        for( const HowHop& h : p.hops )
        {
            x += "<h n=\"" + esc( m_ing.symbols[h.id].name ) + "\" p=\"" + esc( loc( h.id ) ) + "\" shown=\"" + std::to_string( h.shownRows )
               + "\" total=\"" + std::to_string( h.rows.size() ) + "\"";
            if( h.shownRows < h.rows.size() )
            {
                x += " capped=\"1\" next=\"" + esc( "--callees=" + sel( h.id ) + std::string( kHowValueUseIndexFlag ) + pageAllRows( h.calleesBySelector ) ) + "\"";
            }
            x += ">" + esc( h.sig );
            for( std::size_t k = 0; k < h.shownRows; ++k )
            {
                const HowCalleeRow& r = h.rows[k];
                x += "<c n=\"" + esc( r.name ) + "\"";
                if( !r.lines.empty() )
                {
                    x += " cl=\"" + lineList( r.lines ) + "\"";
                }
                if( r.ambArms > 1 )
                {
                    x += " amb=\"" + std::to_string( r.ambArms ) + "\"";
                }
                else if( !isHopId[r.id] )
                {
                    x += " p=\"" + esc( loc( r.id ) ) + "\"";
                }
                x += "/>";
            }
            if( h.depth == 0 )
            {
                const std::size_t shown = std::min( h.callers.size(), kHowCallerRows );
                x += "<us shown=\"" + std::to_string( shown ) + "\" total=\"" + std::to_string( h.callers.size() ) + "\"";
                if( shown < h.callers.size() )
                {
                    const NodeId of = h.container != kNoNode ? h.container : h.id;
                    x += " capped=\"1\" next=\"" + esc( "--callers=" + sel( of ) + std::string( kHowValueUseIndexFlag ) + pageAllRows( h.callersBySelector ) ) + "\"";
                }
                x += ">";
                for( std::size_t k = 0; k < shown; ++k )
                {
                    const HowCallerRow& u = h.callers[k];
                    x += "<u n=\"" + esc( m_ing.symbols[u.id].name ) + "\" p=\"" + esc( loc( u.id ) ) + "\"";
                    if( !u.lines.empty() )
                    {
                        x += " cl=\"" + lineList( u.lines ) + "\"";
                    }
                    x += "/>";
                }
                x += "</us>";
            }
            x += "</h>";
        }
        std::size_t cdata = 0;
        for( const HowBody& b : m.bodies )
        {
            const NodeId id = p.hops[b.hop].id;
            std::size_t  shown = 0;
            std::string  text;
            for( const HowBodyLine& l : b.selected )
            {
                if( !l.isKept )
                {
                    continue;
                }
                text += shown == 0 ? "" : "\n";
                text += l.text;
                ++shown;
            }
            x += "<b n=\"" + esc( m_ing.symbols[id].name ) + "\" p=\"" + esc( loc( id ) ) + "\" lines_shown=\"" + std::to_string( shown )
               + "\" sel=\"" + std::to_string( b.selected.size() ) + "\" lines_total=\"" + std::to_string( b.linesTotal )
               + "\" next=\"" + esc( "--expand=" + sel( id ) ) + "\"><![CDATA[" + text + "]]></b>";
            cdata += text.size();
        }
        const std::size_t total = m.nameRows.size();
        x += "<names shown=\"" + std::to_string( m.namesShown ) + "\" total=\"" + std::to_string( total ) + "\"";
        if( m.namesShown < total )
        {
            x += " capped=\"1\"";
        }
        x += " past=\"" + std::to_string( m.past ) + "\" next=\"" + esc( nextFlag( "--for=", m_task ) + " --format=candidates --top-k=" + std::to_string( kForLensDefaultTopN ) ) + "\">";
        for( std::size_t i = 0; i < m.namesShown; ++i )
        {
            const NodeId id = m.nameRows[i];
            x += i == 0 ? "" : ";";
            x += esc( m_ing.symbols[id].name ) + " " + esc( loc( id ) );
        }
        x += "</names>";
        if( cdataBytesOut != nullptr )
        {
            *cdataBytesOut = cdata;
        }
        return x;
    }

private:
    const IngestResult& m_ing;
    std::string_view    m_rootArg;
    std::string_view    m_task;
    std::vector<char>   m_esc;
};

// Over the ceiling: names first, then deeper hops' callee rows (last hop's lowest row first), then body lines in
// reverse priority — never <path> or a seed's row — and then over_ceiling="1" (§0 "Ceiling"). One step per call;
// false when nothing is left to trim.
inline bool trimHowStep( HowModel& m )
{
    if( m.namesShown > 0 )
    {
        --m.namesShown;
        ++m.cutNames;
        return true;
    }
    for( std::size_t i = m.path.hops.size(); i-- > 0; )
    {
        HowHop& h = m.path.hops[i];
        if( h.depth > 0 && h.shownRows > 0 )
        {
            --h.shownRows;
            ++m.cutCallees;
            return true;
        }
    }
    for( std::size_t bi = m.bodies.size(); bi-- > 0; )
    {
        HowBody&     b     = m.bodies[bi];
        HowBodyLine* worst = nullptr;
        for( HowBodyLine& l : b.selected )
        {
            if( l.isKept && ( worst == nullptr || l.priority >= worst->priority ) )
            {
                worst = &l;
            }
        }
        if( worst != nullptr )
        {
            worst->isKept = false;
            ++m.cutLines;
            return true;
        }
    }
    return false;
}

inline HowSections howSections( const HowInputs& in )
{
    const IngestResult& ing    = in.ing;
    const HowQuestion   q      = parseHowQuestion( in.task );
    const std::vector<NodeId> window = howWindow( in.rank );
    HowContext          cx( ing, in.g, in.rank, q );
    std::vector<HowScore> scoreOf( ing.symbols.size() );
    std::vector<char>     scored( ing.symbols.size(), 0 );

    HowModel m;
    {
        const std::vector<HowSeedPick> listA = buildListA( cx, scoreOf, scored );
        const std::vector<HowSeedPick> listB = buildListB( cx, window, scoreOf, scored );
        const std::vector<HowSeedPick> seeds = pickSeeds( cx, listA, listB );
        m.seedCount = seeds.size();
        m.path      = walkHowPath( cx, seeds );
    }
    HashMap<std::uint32_t, std::string> srcCache;
    for( HowHop& h : m.path.hops )
    {
        const Symbol& s = ing.symbols[h.id];
        if( !srcCache.contains( s.fileId ) )
        {
            std::string text;
            if( std::FILE* f = std::fopen( diskPath( ing, s.fileId ).c_str(), "rb" ) )
            {
                char        buf[ 4096 ];
                std::size_t n;
                while( ( n = std::fread( buf, 1, sizeof( buf ), f ) ) > 0 )
                {
                    text.append( buf, n );
                }
                std::fclose( f );
            }
            srcCache.emplace( s.fileId, std::move( text ) );
        }
        const std::string& src = srcCache[ s.fileId ];
        if( s.sigStartByte < s.sigEndByte && s.sigEndByte <= src.size() )
        {
            h.sig = cleanSig( src.data(), s.sigStartByte, s.sigEndByte, in.redact );
        }
    }
    m.bodies = selectBodies( cx, m.path, q, in.redact, srcCache );

    std::vector<char> isHop( ing.symbols.size(), 0 );
    for( const HowHop& h : m.path.hops )
    {
        isHop[h.id] = 1;
    }
    std::vector<char> fileInWindow( ing.files.size(), 0 );
    for( const NodeId id : window )
    {
        fileInWindow[ ing.symbols[id].fileId ] = 1;
        if( !isHop[id] )
        {
            m.nameRows.push_back( id );
        }
    }
    m.namesShown = std::min( m.nameRows.size(), kHowNameRows );
    std::vector<char> filePositive( ing.files.size(), 0 );
    for( NodeId id = 0; id < NodeId( in.rank.size() ) && id < ing.symbols.size(); ++id )
    {
        if( in.rank[id] > 0.0f )
        {
            filePositive[ ing.symbols[id].fileId ] = 1;
        }
    }
    for( std::size_t f = 0; f < ing.files.size(); ++f )
    {
        m.past += ( filePositive[f] && !fileInWindow[f] ) ? 1 : 0;
    }

    HowRenderer r( ing, in.rootArg, in.task );
    HowSections out;
    out.xml = r.render( m, &out.cdataBytes );
    // THE CEILING, on the whole first answer (the CLI default document around these sections): names, then deeper hops'
    // callee rows, then body lines in reverse priority — never <path> or a seed's row — and over_ceiling="1" iff the
    // answer is still over. Every cut is counted on <path> (cut_*=) and in its element's own shown=/lines_shown=.
    // RIPWIRE_HOW_UNCAPPED=1 is the reported F2-uncapped arm: the same answer with the ceiling off, nothing else moved.
    const char* const uncapped   = std::getenv( "RIPWIRE_HOW_UNCAPPED" );
    const bool        isUncapped = uncapped != nullptr && uncapped[0] == '1' && uncapped[1] == '\0';
    const auto answerBytes = [ & ] { return howCompactDocument( in.head, out.xml, out.cdataBytes ).size(); };
    while( !isUncapped && answerBytes() > kHowCeilingBytes && trimHowStep( m ) )
    {
        out.xml = r.render( m, &out.cdataBytes );
    }
    if( !isUncapped && answerBytes() > kHowCeilingBytes )
    {
        m.isOverCeiling = true;
        out.xml = r.render( m, &out.cdataBytes );
    }
    out.seedCount     = m.seedCount;
    out.isOverCeiling = m.isOverCeiling;
    const bool isOneBlock = out.xml.starts_with( "<path " ) && out.xml.ends_with( "</names>" );
    ENSURES( isOneBlock, "the parity region is one contiguous block" );
    return out;
}

// ── the document around the sections ──────────────────────────────────────────────────────────────────────────────────

inline std::string howRootAttrs()
{
    return " shape=\"how\" lens=\"" + std::string( kHowLensValue ) + "\"";
}


// Insert `attrs` before the '>' that closes the first start tag of `doc`.
inline void spliceRootAttrs( std::string& doc, std::string_view attrs )
{
    const std::size_t close = doc.find( '>' );
    if( close != std::string::npos )
    {
        doc.insert( close, attrs );
    }
}


// The end of the element that starts at `at` (one past its close), skipping CDATA and comments; npos when unbalanced.
inline std::size_t howElementEnd( std::string_view doc, std::size_t at ) noexcept
{
    int depth = 0;
    for( std::size_t i = at; i < doc.size(); )
    {
        const std::string_view rest = doc.substr( i );
        if( rest.starts_with( "<![CDATA[" ) )
        {
            const std::size_t e = doc.find( "]]>", i );
            i = e == std::string_view::npos ? doc.size() : e + 3;
            continue;
        }
        if( rest.starts_with( "<!--" ) )
        {
            const std::size_t e = doc.find( "-->", i );
            i = e == std::string_view::npos ? doc.size() : e + 3;
            continue;
        }
        if( doc[i] != '<' )
        {
            ++i;
            continue;
        }
        const std::size_t close = doc.find( '>', i );
        if( close == std::string_view::npos )
        {
            return std::string_view::npos;
        }
        if( rest.starts_with( "</" ) )
        {
            --depth;
        }
        else if( doc[ close - 1 ] != '/' )
        {
            ++depth;
        }
        i = close + 1;
        if( depth == 0 )
        {
            return i;
        }
    }
    return std::string_view::npos;
}

// The indexing-cap pairs the root carries (` X_capped="1" X_total="N"`, mention.h CapDisclosure) defined where this answer
// can read them: the compact dialect keeps X_capped='s generic reading and drops the bundle's prose that spelled X_total=.
inline std::string howCapClause( std::string_view rootOpen )
{
    std::string names;
    for( std::size_t at = rootOpen.find( "_capped=\"" ); at != std::string_view::npos; at = rootOpen.find( "_capped=\"", at + 1 ) )
    {
        std::size_t from = at;
        while( from > 0 && rootOpen[from - 1] != ' ' )
        {
            --from;
        }
        const std::string stem( rootOpen.substr( from, at - from ) );
        if( rootOpen.find( " " + stem + "_total=\"" ) != std::string_view::npos )
        {
            names += " " + stem + "_capped= " + stem + "_total=";
        }
    }
    return names.empty() ? std::string() : " [cut:" + names + ": an indexing cap dropped content; _total= the count before the cap]";
}

// erase ` name="…"` from the first start tag of `doc`
inline void eraseRootAttr( std::string& doc, std::string_view name )
{
    const std::size_t rootEnd = doc.find( '>' );
    const std::string key     = " " + std::string( name ) + "=\"";
    const std::size_t at      = doc.find( key );
    if( at == std::string::npos || at > rootEnd )
    {
        return;
    }
    const std::size_t close = doc.find( '"', at + key.size() );
    if( close != std::string::npos )
    {
        doc.erase( at, close + 1 - at );
    }
}

// --pack-task / MCP explore (prereg §0 Scope): the how sections take the place of the bundle's ranking, bodies and callers
// (<sigs> with its <far> tier, <bodies>, <callers>); its notes and tests follow unchanged. `bundle` is the assembler's own
// FULL-dialect document (the compact layer runs after, on the CLI and on MCP alike). The root gains shape=/lens=, loses
// dropped_positive= (a count of the ranking this answer no longer carries) and is re-priced; the ledger's ranking, bodies,
// callers and far entries — and the <sigs> cut readings — are replaced by one entry naming the sections that replaced them.
inline std::string howIntoPackTask( const std::string& bundle, const HowSections& sec, std::size_t budgetTokens )
{
    const std::size_t rootEnd = bundle.find( '>' );
    if( rootEnd == std::string::npos )
    {
        DISCLOSE( Diagnostics::answerUnchanged, "how: the pack-task bundle is served as the assembler wrote it",
                  "forhow: the bundle has no root element to splice the how sections into" );
        return bundle;
    }
    std::size_t headEnd = rootEnd + 1;
    while( std::string_view( bundle ).substr( headEnd ).starts_with( "<!--" ) )
    {
        const std::size_t e = bundle.find( "-->", headEnd );
        if( e == std::string::npos )
        {
            break;
        }
        headEnd = e + 3;
    }
    // the replaced span: the contiguous run of <sigs>, <bodies>, <callers> children right after the head
    std::size_t spanEnd = headEnd;
    for( const std::string_view tag : { std::string_view( "<sigs" ), std::string_view( "<bodies" ), std::string_view( "<callers" ) } )
    {
        const std::string_view rest = std::string_view( bundle ).substr( spanEnd );
        if( rest.starts_with( tag ) && rest.size() > tag.size() && ( rest[ tag.size() ] == ' ' || rest[ tag.size() ] == '>' || rest[ tag.size() ] == '/' ) )
        {
            const std::size_t e = howElementEnd( bundle, spanEnd );
            if( e == std::string_view::npos )
            {
                break;
            }
            spanEnd = e;
        }
    }
    std::string head = bundle.substr( 0, headEnd );
    // the ledger: one entry for the replaced sections (full dialect: inside the legend comment; the compact layer keeps it)
    if( const std::size_t r = head.find( "| ranking: " ); r != std::string::npos )
    {
        if( const std::size_t n = head.find( "| notes: ", r ); n != std::string::npos )
        {
            head.replace( r, n - r, "| how: path, hops, selected body lines and names in place of ranking, bodies, callers " );
        }
    }
    if( const std::size_t far = head.find( " | far: " ); far != std::string::npos )
    {
        std::size_t e = head.find( " -->", far );
        if( const std::size_t br = head.find( " [", far ); br != std::string::npos && br < e )
        {
            e = br;
        }
        if( e != std::string::npos )
        {
            head.erase( far, e - far );
        }
    }
    for( const std::string_view gone : { kForSigsShrunkNote, kForDocsDroppedNote } )
    {
        if( const std::size_t at = head.find( gone ); at != std::string::npos )
        {
            head.erase( at, gone.size() );
        }
    }
    eraseRootAttr( head, "dropped_positive" );
    eraseRootAttr( head, "est_tokens" );
    eraseRootAttr( head, "over_ceiling" );
    spliceRootAttrs( head, howRootAttrs() );
    std::string doc = head;
    doc += kHowPackTaskLegendOpen;
    doc += howLegendClauses();   // every clause verbatim, so the ref posture can take each out once it was sent
    doc += howCapClause( head.substr( 0, head.find( '>' ) ) );
    doc += " -->";
    doc += sec.xml;
    doc.append( bundle, spanEnd, std::string::npos );
    const std::string est = howEstAttr( doc.size(), sec.cdataBytes );
    std::size_t       estValue = 0;
    for( const char c : est )
    {
        if( c >= '0' && c <= '9' )
        {
            estValue = estValue * 10 + std::size_t( c - '0' );
        }
    }
    const bool isOver = budgetTokens > 0 && estValue > budgetTokens;
    spliceRootAttrs( doc, est + ( isOver ? " over_ceiling=\"1\"" : "" ) );
    return doc;
}

} // namespace forhow

} // namespace rw
