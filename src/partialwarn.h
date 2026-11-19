// partialwarn.h — RT1: "this routed answer may be partial", lane W1's FROZEN rule F1 (results/W1_PARTIALWARN_1118/frozen_f1.py,
// sha256 5498bf51…909e5f, with signals.py b28fa629…7e9fbd), transcribed. Nothing here was tuned by this lane.
//
// WHAT F1 READS. Only answers this binary prints and the indexed text — never a gold:
//   the routed verb's answer (its p= rows, its <def> rows), the --defs answer for the same spelling, the --grep=LAST answer
//   (its <hit in=> enclosers and their <enc callers_floor="1"> rows), and a whole-word scan of LAST over the CORPUS: indexed
//   files with a code extension, not vendored, not a test path (frozen mirrors of signals.py, which this file keeps verbatim
//   even where src/filter.h has since grown — isTestPath now knows __tests__/, the frozen mirror does not).
// THE RULE, by verb:
//   callers: warn iff the target's own <enc> row on --grep=LAST carries callers_floor="1"                       why=target-floor
//   uses:    warn iff text-gap >= 1, OR a C-family #define line names LAST, OR two non-declaration definitions share a stem
//            after one build-tag suffix (or outright)                    why=text-gap:N:FILE, macro:FILE:LINE, twin-defs:N
//   impact:  warn iff an encloser of a whole-word non-test grep hit is floored, OR text-gap >= 1
//                                                                         why=value-hop:N:NAME, text-gap:N:FILE
//   text-gap = corpus files with a whole-word LAST hit, minus every p= file of the answer and of --defs' non-test rows.
// An ABSENT warning means no evidence of a miss was found, never that the answer is complete (W1 READOUT; every routed answer
// says complete="not-proven").
//
// TRANSCRIPTION NOTES (each a reading of non-ASCII text or of an order; none changes the warn bit on W1's 21 cells):
//   * rg -w's Unicode word boundary is read as: a non-ASCII byte is a word character (W1 post-filters with [A-Za-z0-9_$]).
//   * frozen_f1 names the FIRST macro hit in rg's output order; here the first in (path, line) order — only why= text differs.
//   * the corpus is the INDEX (ripwire's crawl), not `git ls-files`: an over-size file the crawl skipped is not scanned.
#pragma once

#include <algorithm>
#include <cstddef>
#include <string>
#include <string_view>
#include <tuple>
#include <utility>
#include <vector>

#include "forroute.h"          // lastSegment — the one "after the last :: . #" cut
#include "infra/namesplit.h"   // isIdentChar, afterLast, containsWordBoundedBy — the shared byte, cut and walk

namespace rw::partialwarn
{

// One whole-word occurrence line of LAST in a corpus file.
struct CorpusHit
{
    std::string file;          // root-relative, as p= spells it
    int         line  = 0;     // 1-based
    bool        macro = false; // a C-family `#define` line
};

struct Warn
{
    bool        warn = false;
    std::string why;   // comma list, fixed reason order; "" when no evidence
};

namespace detail
{
[[nodiscard]] inline bool isAsciiWord( char c ) noexcept { return rw::namesplit::isIdentChar( c ); }
// W1's identifier class [A-Za-z0-9_$]
[[nodiscard]] inline bool isIdentChar( char c ) noexcept { return isAsciiWord( c ) || c == '$'; }

// The frozen corpus mirrors (signals.py VENDOR / EXT / CFAM / is_test_path / TWIN).
inline constexpr std::string_view kVendor[] = { "third_party/", "vendor/", "node_modules/", "external/" };
inline constexpr std::string_view kCodeExt[] = { "c", "h", "cc", "cpp", "cxx", "hh", "hpp", "hxx", "m", "mm", "py", "pyi", "ts", "tsx", "mts", "cts", "js",
                                                 "jsx", "mjs", "cjs", "java", "rb", "rake", "sh", "bash", "go", "rs", "swift", "cs", "cu", "cuh", "metal" };
inline constexpr std::string_view kCFamilyExt[] = { "c", "h", "cc", "cpp", "cxx", "hh", "hpp", "hxx", "m", "mm", "cu", "cuh", "metal" };
inline constexpr std::string_view kTwinSuffix[] = { "_unix", "_windows", "_linux", "_darwin", "_posix", "_win32", "_win", "_bsd", "_freebsd", "_openbsd", "_netbsd",
                                                    "_solaris", "_aix", "_js", "_wasm", "_other", "_generic", "_amd64", "_arm64", "_386", "_arm" };

// p.rsplit(".", 1)[-1] (the whole path when it has no '.') and the basename.
[[nodiscard]] inline std::string_view extOf( std::string_view p ) noexcept { return rw::namesplit::afterLast( p, "." ); }
[[nodiscard]] inline std::string_view baseOf( std::string_view p ) noexcept { return rw::namesplit::afterLast( p, "/" ); }
template <std::size_t N>
[[nodiscard]] inline bool listed( const std::string_view ( &list )[ N ], std::string_view s ) noexcept
{
    return std::ranges::find( list, s ) != std::end( list );
}

// signals.py is_test_path, verbatim.
[[nodiscard]] inline bool isFrozenTestPath( std::string_view p ) noexcept
{
    for( const std::string_view seg : { std::string_view( "test/" ), std::string_view( "tests/" ) } )
    {
        for( std::size_t i = p.find( seg ); i != std::string_view::npos; i = p.find( seg, i + 1 ) )
        {
            if( i == 0 || p[ i - 1 ] == '/' )
            {
                return true;
            }
        }
    }
    const std::string_view fn = baseOf( p );
    return fn.starts_with( "test_" ) || fn.find( "_test." ) != std::string_view::npos || fn.find( ".test." ) != std::string_view::npos
        || fn.find( "_spec." ) != std::string_view::npos || fn.find( ".spec." ) != std::string_view::npos;
}

// <!--.*?--> replaced by one space (re.S); an unterminated comment is left as it stands.
[[nodiscard]] inline std::string stripComments( std::string_view doc )
{
    std::string out;
    out.reserve( doc.size() );
    std::size_t i = 0;
    for( ;; )
    {
        const std::size_t open = doc.find( "<!--", i );
        const std::size_t close = open == std::string_view::npos ? std::string_view::npos : doc.find( "-->", open + 4 );
        if( close == std::string_view::npos )
        {
            out.append( doc.substr( i ) );
            return out;
        }
        out.append( doc.substr( i, open - i ) );
        out += ' ';
        i = close + 3;
    }
}

// dict(re.findall(r'(\w+)="([^"]*)"', span)): the LAST value of a repeated name wins.
[[nodiscard]] inline std::string_view attrOf( std::string_view span, std::string_view name ) noexcept
{
    std::string_view found;
    bool             has = false;
    for( std::size_t i = 0; i < span.size(); )
    {
        if( !isAsciiWord( span[ i ] ) )
        {
            ++i;
            continue;
        }
        std::size_t j = i;
        while( j < span.size() && isAsciiWord( span[ j ] ) )
        {
            ++j;
        }
        if( span.substr( j, 2 ) == "=\"" )
        {
            const std::size_t close = span.find( '"', j + 2 );
            if( close != std::string_view::npos )
            {
                if( span.substr( i, j - i ) == name )
                {
                    found = span.substr( j + 2, close - j - 2 );
                    has   = true;
                }
                i = close + 1;
                continue;
            }
        }
        i = j;
    }
    return has ? found : std::string_view{};
}
// re.finditer(r"<TAG ([^>]*)/?>"): each tag's attribute span (a trailing '/' kept, as [^>]* keeps it).
[[nodiscard]] inline std::vector<std::string_view> tagSpans( std::string_view body, std::string_view openWithSpace )
{
    std::vector<std::string_view> out;
    for( std::size_t at = body.find( openWithSpace ); at != std::string_view::npos; )
    {
        const std::size_t from = at + openWithSpace.size();
        const std::size_t gt   = body.find( '>', from );
        if( gt == std::string_view::npos )
        {
            break;
        }
        out.push_back( body.substr( from, gt - from ) );
        at = body.find( openWithSpace, gt + 1 );
    }
    return out;
}

// signals.py files_in: every \bp="…" value, cut at its first ':'.
[[nodiscard]] inline std::vector<std::string> filesIn( std::string_view body )
{
    std::vector<std::string> out;
    for( std::size_t at = body.find( "p=\"" ); at != std::string_view::npos; )
    {
        const bool        bounded = at == 0 || !isAsciiWord( body[ at - 1 ] );
        const std::size_t close   = body.find( '"', at + 3 );
        if( close == std::string_view::npos )
        {
            break;
        }
        if( bounded && close > at + 3 )
        {
            const std::string_view v = body.substr( at + 3, close - at - 3 );
            out.emplace_back( v.substr( 0, v.find( ':' ) ) );
            at = body.find( "p=\"", close + 1 );
        }
        else
        {
            at = body.find( "p=\"", at + 1 );
        }
    }
    return out;
}

// W1's wre: LAST with no [A-Za-z0-9_$] on either side.
[[nodiscard]] inline bool hasIdentWord( std::string_view text, std::string_view word )
{
    return !word.empty() && rw::namesplit::containsWordBoundedBy( text, word, isIdentChar );
}
// rg -w -F LAST post-filtered by wre: an occurrence with no [A-Za-z0-9_$] and no non-ASCII byte on either side.
[[nodiscard]] inline bool hasCorpusWord( std::string_view text, std::string_view word )
{
    return !word.empty() && rw::namesplit::containsWordBoundedBy( text, word, []( char c ) { return isIdentChar( c ) || static_cast<unsigned char>( c ) >= 0x80u; } );
}
// re.match(r"^\s*#\s*define\b", line)
[[nodiscard]] inline bool isDefineLine( std::string_view line ) noexcept
{
    const auto skipSpace = [ & ]( std::size_t i )
    {
        while( i < line.size() && ( line[ i ] == ' ' || line[ i ] == '\t' || line[ i ] == '\r' || line[ i ] == '\f' || line[ i ] == '\v' ) )
        {
            ++i;
        }
        return i;
    };
    std::size_t i = skipSpace( 0 );
    if( i >= line.size() || line[ i ] != '#' )
    {
        return false;
    }
    i = skipSpace( i + 1 );
    if( line.substr( i, 6 ) != "define" )
    {
        return false;
    }
    return i + 6 >= line.size() || !( isAsciiWord( line[ i + 6 ] ) || static_cast<unsigned char>( line[ i + 6 ] ) >= 0x80u );
}

// signals.py twin: two stems equal after one build-tag suffix is cut (or equal outright).
[[nodiscard]] inline bool hasTwin( const std::vector<std::string>& paths )
{
    std::vector<std::string> stems;
    stems.reserve( paths.size() );
    for( const std::string& p : paths )
    {
        std::string_view b   = baseOf( p );
        const std::size_t dot = b.rfind( '.' );
        b = dot == std::string_view::npos ? b : b.substr( 0, dot );
        for( const std::string_view t : kTwinSuffix )
        {
            if( b.ends_with( t ) )
            {
                b.remove_suffix( t.size() );
                break;
            }
        }
        stems.emplace_back( b );
    }
    std::ranges::sort( stems );
    return std::ranges::adjacent_find( stems ) != stems.end();
}

// One <hit l="N" in="ENC" …><![CDATA[TEXT]]>TAIL</hit> of a grep <f> body at `h`, as frozen_f1.py's regex reads it.
struct GrepHit
{
    std::string_view enc, text, tail;
    std::size_t      end = std::string_view::npos;   // just past </hit>; npos: no hit parses at `h`
};
// `"N" in="` after `at` (N one or more digits): the offset just past it, or npos.
[[nodiscard]] inline std::size_t afterLineAndIn( std::string_view s, std::size_t at ) noexcept
{
    constexpr std::string_view kIn = "\" in=\"";
    std::size_t i = at;
    while( i < s.size() && s[ i ] >= '0' && s[ i ] <= '9' )
    {
        ++i;
    }
    return i > at && s.substr( i, kIn.size() ) == kIn ? i + kIn.size() : std::string_view::npos;
}
[[nodiscard]] inline GrepHit parseHit( std::string_view body, std::size_t h ) noexcept
{
    constexpr std::string_view kHit = "<hit l=\"", kCd = "<![CDATA[";
    GrepHit           g;
    const std::size_t encAt  = afterLineAndIn( body, h + kHit.size() );
    const std::size_t inEnd  = encAt == std::string_view::npos ? encAt : body.find( '"', encAt );
    const std::size_t tagEnd = inEnd == std::string_view::npos ? inEnd : body.find( '>', inEnd );
    const bool        cdata  = tagEnd != std::string_view::npos && body.substr( tagEnd + 1, kCd.size() ) == kCd;
    const std::size_t cdEnd  = cdata ? body.find( "]]>", tagEnd + 1 + kCd.size() ) : std::string_view::npos;
    const std::size_t hitEnd = cdEnd == std::string_view::npos ? cdEnd : body.find( "</hit>", cdEnd + 3 );
    if( hitEnd == std::string_view::npos )
    {
        return g;
    }
    g.enc  = body.substr( encAt, inEnd - encAt );
    g.text = body.substr( tagEnd + 1 + kCd.size(), cdEnd - tagEnd - 1 - kCd.size() );
    g.tail = body.substr( cdEnd + 3, hitEnd - cdEnd - 3 );
    g.end  = hitEnd + 6;
    return g;
}
// The in= of every <at l="N" in="…" carrier in a hit's tail.
inline void carrierEnclosers( std::string_view tail, std::vector<std::string>& out )
{
    bool lead = true;   // the field before the first <at l=" opener is no carrier
    (void)rw::namesplit::anyField( tail, "<at l=\"", false, [ & ]( std::string_view field )
    {
        const std::size_t encAt = lead ? std::string_view::npos : afterLineAndIn( field, 0 );
        const std::size_t e     = encAt == std::string_view::npos ? encAt : field.find( '"', encAt );
        if( e != std::string_view::npos )
        {
            out.emplace_back( field.substr( encAt, e - encAt ) );
        }
        lead = false;
        return false;
    } );
}
// The whole-word enclosers of one non-test <f> body: frozen_f1.py's word_in, one file at a time.
inline void fileWordEnclosers( std::string_view body, std::string_view last, std::vector<std::string>& out )
{
    constexpr std::string_view kHit = "<hit l=\"";
    for( std::size_t h = body.find( kHit ); h != std::string_view::npos; )
    {
        const GrepHit g = parseHit( body, h );
        if( g.end == std::string_view::npos )
        {
            h = body.find( kHit, h + 1 );
            continue;
        }
        if( hasIdentWord( g.text, last ) )
        {
            out.emplace_back( g.enc );
            carrierEnclosers( g.tail, out );
        }
        h = body.find( kHit, g.end );
    }
}
// The grep answer's whole-word enclosers over every non-test <f p="…">…</f> block.
[[nodiscard]] inline std::vector<std::string> wordEnclosers( std::string_view g, std::string_view last )
{
    std::vector<std::string> out;
    constexpr std::string_view kF = "<f p=\"";
    for( std::size_t at = g.find( kF ); at != std::string_view::npos; )
    {
        const std::size_t pEnd = g.find( '"', at + kF.size() );
        const std::size_t gt   = pEnd == std::string_view::npos ? pEnd : g.find( '>', pEnd );
        const std::size_t fEnd = gt == std::string_view::npos ? gt : g.find( "</f>", gt );
        if( pEnd == at + kF.size() || fEnd == std::string_view::npos )
        {
            at = g.find( kF, at + 1 );
            continue;
        }
        if( !isFrozenTestPath( g.substr( at + kF.size(), pEnd - at - kF.size() ) ) )
        {
            fileWordEnclosers( g.substr( gt + 1, fEnd - gt - 1 ), last, out );
        }
        at = g.find( kF, fEnd + 4 );
    }
    return out;
}
} // namespace detail

// The frozen corpus filter: a root-relative path F1 scans.
[[nodiscard]] inline bool isCorpusPath( std::string_view rel ) noexcept
{
    for( const std::string_view v : detail::kVendor )
    {
        if( rel.starts_with( v ) )
        {
            return false;
        }
    }
    return !detail::isFrozenTestPath( rel ) && detail::listed( detail::kCodeExt, detail::extOf( rel ) )
        && detail::baseOf( rel ).find( '.' ) != std::string_view::npos;
}

// Every whole-word line of `last` in one corpus file's text, appended to `out` in line order.
inline void scanText( std::string_view rel, std::string_view text, std::string_view last, std::vector<CorpusHit>& out )
{
    if( last.empty() || text.find( last ) == std::string_view::npos )
    {
        return;
    }
    const bool cFamily = detail::listed( detail::kCFamilyExt, detail::extOf( rel ) );
    int        line    = 1;
    for( std::size_t from = 0; from <= text.size(); ++line )
    {
        const std::size_t nl = text.find( '\n', from );
        const std::string_view l = text.substr( from, nl == std::string_view::npos ? std::string_view::npos : nl - from );
        if( detail::hasCorpusWord( l, last ) )
        {
            out.push_back( { std::string( rel ), line, cFamily && detail::isDefineLine( l ) } );
        }
        if( nl == std::string_view::npos )
        {
            break;
        }
        from = nl + 1;
    }
}

// LAST as F1 reads it: the last segment of the routed answer's root of=.
[[nodiscard]] inline std::string answerTarget( std::string_view answer )
{
    const std::string body = detail::stripComments( answer );
    for( const std::string_view root : { std::string_view( "<callers" ), std::string_view( "<uses" ), std::string_view( "<impact" ) } )
    {
        const std::size_t at = body.find( root );
        if( at == std::string::npos )
        {
            continue;
        }
        const std::size_t after = at + root.size();
        if( after < body.size() && detail::isAsciiWord( body[ after ] ) )
        {
            continue;
        }
        const std::size_t gt = body.find( '>', after );
        return std::string( rw::forroute::lastSegment( detail::attrOf( std::string_view( body ).substr( after, gt - after ), "of" ) ) );
    }
    return {};
}

// What F1 reads: the routed answer of `verb` ("callers" | "uses" | "impact"), the --defs and --grep=LAST answers, LAST and the
// corpus hits of LAST (partialwarn.h scanText, in (path, line) order).
struct F1Inputs
{
    std::string_view              verb, answer, defs, grep, last;
    const std::vector<CorpusHit>& hits;
};

namespace detail
{
// The answer's files (every p= of the routed answer and of --defs' non-test rows), sorted, and --defs' non-declaration files.
struct AnswerFiles
{
    std::vector<std::string> files, nonDeclDefs;
};
[[nodiscard]] inline AnswerFiles answerFiles( std::string_view answer, std::string_view defs )
{
    AnswerFiles af{ .files = filesIn( stripComments( answer ) ) };
    const std::string dbody = stripComments( defs );
    for( const std::string_view d : tagSpans( dbody, "<d " ) )
    {
        const std::string_view p = attrOf( d, "p" );
        if( attrOf( d, "class" ) == "test" || ( p.empty() && d.find( "p=\"\"" ) == std::string_view::npos ) )
        {
            continue;   // a test row, or no p= at all
        }
        af.files.emplace_back( p.substr( 0, p.find( ':' ) ) );
        if( attrOf( d, "decl_only" ) != "1" )
        {
            af.nonDeclDefs.emplace_back( p.substr( 0, p.find( ':' ) ) );
        }
    }
    std::ranges::sort( af.files );
    return af;
}
// text-gap: the distinct hit files the answer does not name, sorted.
[[nodiscard]] inline std::vector<std::string> textGap( const std::vector<CorpusHit>& hits, const std::vector<std::string>& sortedAnswerFiles )
{
    std::vector<std::string> gap;
    for( const CorpusHit& h : hits )
    {
        if( !std::ranges::binary_search( sortedAnswerFiles, h.file ) )
        {
            gap.push_back( h.file );
        }
    }
    std::ranges::sort( gap );
    gap.erase( std::unique( gap.begin(), gap.end() ), gap.end() );
    return gap;
}
// The floored enclosers on --grep=LAST: value hops (floored whole-word enclosers, in <enc> order) and the target's own floor.
struct Floors
{
    std::vector<std::string> hops;
    bool                     targetFloor = false;
};
[[nodiscard]] inline Floors grepFloors( std::string_view grep, std::string_view last )
{
    Floors                         fl;
    const std::string              g      = stripComments( grep );
    const std::vector<std::string> wordIn = wordEnclosers( g, last );
    for( const std::string_view e : tagSpans( g, "<enc " ) )
    {
        if( attrOf( e, "callers_floor" ) != "1" )
        {
            continue;
        }
        const std::string_view n = attrOf( e, "n" );
        if( std::ranges::find( wordIn, n ) != wordIn.end() )
        {
            fl.hops.emplace_back( n );
        }
        fl.targetFloor = fl.targetFloor || rw::forroute::lastSegment( n ) == last;
    }
    return fl;
}
[[nodiscard]] inline std::string countedReason( std::string_view kind, std::size_t n, std::string_view first )
{
    return std::string( kind ) + ":" + std::to_string( n ) + ":" + std::string( first );
}
} // namespace detail

// F1. See the header for the rule.
[[nodiscard]] inline Warn frozenF1( const F1Inputs& in )
{
    const detail::AnswerFiles      af  = detail::answerFiles( in.answer, in.defs );
    const std::vector<std::string> gap = detail::textGap( in.hits, af.files );
    std::vector<std::string>       why;
    if( in.verb == "callers" && detail::grepFloors( in.grep, in.last ).targetFloor )
    {
        why.emplace_back( "target-floor" );
    }
    else if( in.verb == "uses" )
    {
        const auto macro = std::ranges::find_if( in.hits, []( const CorpusHit& h ) { return h.macro; } );
        if( !gap.empty() )
        {
            why.push_back( detail::countedReason( "text-gap", gap.size(), gap.front() ) );
        }
        if( macro != in.hits.end() )
        {
            why.push_back( "macro:" + macro->file + ":" + std::to_string( macro->line ) );
        }
        if( af.nonDeclDefs.size() >= 2 && detail::hasTwin( af.nonDeclDefs ) )
        {
            why.push_back( "twin-defs:" + std::to_string( af.nonDeclDefs.size() ) );
        }
    }
    else if( in.verb == "impact" )
    {
        const detail::Floors fl = detail::grepFloors( in.grep, in.last );
        if( !fl.hops.empty() )
        {
            why.push_back( detail::countedReason( "value-hop", fl.hops.size(), fl.hops.front() ) );
        }
        if( !gap.empty() )
        {
            why.push_back( detail::countedReason( "text-gap", gap.size(), gap.front() ) );
        }
    }
    Warn w{ .warn = !why.empty() };
    for( const std::string& r : why )
    {
        w.why += ( w.why.empty() ? "" : "," ) + r;
    }
    return w;
}

// ── RT2 (results/RT2_ROUTE_1118, frozen in its PREREG.md): W2 — the evidence a ROUTED answer acts on ─────────────────────────
// F1 above is unchanged and still runs. W2 adds three clauses (BS1 fix 1) and FOLDS the text gap instead of warning on it:
//   fold      = text-only files: F1's text-gap files (its corpus scan) united with the files of --grep=LAST --grep-in=any — the
//               index's own files AND its <unindexed> section — whose hit line names LAST as a whole word; minus test paths (F1's
//               frozen isTestPath), vendored prefixes, prose documents (md markdown rst txt adoc rdoc) and every file the answer
//               names (p=, bind=) or --defs names. Each prints as <tx p="FILE:LINE"/> (first whole-word line), sorted by path.
//   residual  = reasons a fold cannot answer, in this order: F1's non-text-gap reasons (target-floor, macro:F:L, twin-defs:N,
//               value-hop:N:NAME); macro-row:NAME (a --callers row is a function-like macro, so its own callers are callers the
//               answer does not list); target-floor (a --uses answer to a who-calls / where-used question whose target's
//               callers are a floor: it is called through a slot the graph cannot follow); text-gap-capped:N (more than
//               kFoldCap fold files); grep-capped (the exhaustive grep was itself cut, so the fold is a floor).
// A routed answer with a residual reason says warn="1" why=<residual> and carries the first --for page; a fold alone does not.
inline constexpr std::size_t kFoldCap = 16;

struct FoldRow
{
    std::string file;
    int         line = 0;
};
struct RouteEvidence
{
    std::string          residual;   // the residual reasons, comma-joined in their fixed order ("" = none: no warning)
    std::vector<FoldRow> fold;       // every text-only file, sorted by path; the caller prints the first kFoldCap
};

namespace detail
{
inline constexpr std::string_view kProseExt[] = { "md", "markdown", "rst", "txt", "adoc", "rdoc" };

// Every value of `attr="…"` (attr with no word byte before it), cut at its first ':'.
inline void attrFiles( std::string_view body, std::string_view attrEq, std::vector<std::string>& out )
{
    for( std::size_t at = body.find( attrEq ); at != std::string_view::npos; at = body.find( attrEq, at + 1 ) )
    {
        const std::size_t close = body.find( '"', at + attrEq.size() );
        if( close == std::string_view::npos )
        {
            return;
        }
        if( ( at == 0 || !isAsciiWord( body[ at - 1 ] ) ) && close > at + attrEq.size() )
        {
            const std::string_view v = body.substr( at + attrEq.size(), close - at - attrEq.size() );
            out.emplace_back( v.substr( 0, v.find( ':' ) ) );
        }
    }
}
[[nodiscard]] inline bool foldable( std::string_view rel ) noexcept
{
    for( const std::string_view v : kVendor )
    {
        if( rel.starts_with( v ) )
        {
            return false;
        }
    }
    const std::string_view base = baseOf( rel );
    std::string ext( base.find( '.' ) == std::string_view::npos ? std::string_view{} : extOf( base ) );
    std::ranges::transform( ext, ext.begin(), []( char c ) { return c >= 'A' && c <= 'Z' ? char( c - 'A' + 'a' ) : c; } );
    return !isFrozenTestPath( rel ) && !listed( kProseExt, std::string_view( ext ) );
}
// The line number of the first <hit l="N"> in `fileBody` whose CDATA names `last` as a whole word; 0 when none does.
[[nodiscard]] inline int firstWordHitLine( std::string_view fileBody, std::string_view last )
{
    constexpr std::string_view kHit = "<hit l=\"", kCd = "<![CDATA[", kCdEnd = "]]>";
    for( std::size_t h = fileBody.find( kHit ); h != std::string_view::npos; h = fileBody.find( kHit, h + 1 ) )
    {
        const std::size_t cd = fileBody.find( kCd, h );
        const std::size_t ce = cd == std::string_view::npos ? std::string_view::npos : fileBody.find( kCdEnd, cd );
        if( ce == std::string_view::npos )
        {
            return 0;
        }
        if( hasIdentWord( fileBody.substr( cd + kCd.size(), ce - cd - kCd.size() ), last ) )
        {
            int line = 0;
            for( std::size_t k = h + kHit.size(); k < fileBody.size() && rw::forroute::detail::isAsciiDigit( fileBody[ k ] ); ++k )
            {
                line = line * 10 + ( fileBody[ k ] - '0' );
            }
            return line;
        }
    }
    return 0;
}
// --grep-in=any's files whose hit line names `last` as a whole word: (file, first such line), in the answer's order.
inline void grepAnyWordFiles( std::string_view g, std::string_view last, std::vector<FoldRow>& out )
{
    constexpr std::string_view kF = "<f p=\"";
    for( std::size_t at = g.find( kF ); at != std::string_view::npos; )
    {
        const std::size_t pEnd = g.find( '"', at + kF.size() );
        const std::size_t fEnd = pEnd == std::string_view::npos ? std::string_view::npos : g.find( "</f>", pEnd );
        if( fEnd == std::string_view::npos )
        {
            return;
        }
        if( const int line = firstWordHitLine( g.substr( pEnd, fEnd - pEnd ), last ); line > 0 )
        {
            out.push_back( { std::string( g.substr( at + kF.size(), pEnd - at - kF.size() ) ), line } );
        }
        at = g.find( kF, fEnd + 4 );
    }
}
[[nodiscard]] inline bool grepCapped( std::string_view g )
{
    const std::size_t at = g.find( "<grep " );
    const std::size_t gt = at == std::string_view::npos ? std::string_view::npos : g.find( '>', at );
    if( gt == std::string_view::npos )
    {
        return false;
    }
    const std::string_view open = g.substr( at, gt - at );
    return attrOf( open, "capped" ) == "1" || attrOf( open, "hits_capped" ) == "1";
}
// The first --callers row that is a function-like macro: its n=, or "".
[[nodiscard]] inline std::string_view macroCallerRow( std::string_view body )
{
    for( const std::string_view s : tagSpans( body, "<s " ) )
    {
        if( attrOf( s, "t" ) == "macro" )
        {
            return attrOf( s, "n" );
        }
    }
    return {};
}
} // namespace detail

namespace detail
{
inline void addReason( std::string& why, std::string_view r )
{
    why += why.empty() ? "" : ",";
    why += r;
}
// F1's reasons a fold cannot answer: every comma-separated reason but text-gap:…, in F1's order.
inline void nonGapReasons( std::string_view why, std::string& out )
{
    while( !why.empty() )
    {
        const std::size_t      comma = why.find( ',' );
        const std::string_view r     = why.substr( 0, comma );
        if( !r.starts_with( "text-gap:" ) )
        {
            addReason( out, r );
        }
        why = comma == std::string_view::npos ? std::string_view{} : why.substr( comma + 1 );
    }
}
// The fold: F1's corpus hits and --grep-in=any's whole-word files, one row per file (its first line), foldable and unnamed.
[[nodiscard]] inline std::vector<FoldRow> foldRows( const F1Inputs& in, std::string_view answerBody, std::string_view grepAny )
{
    AnswerFiles af = answerFiles( in.answer, in.defs );
    attrFiles( answerBody, "bind=\"", af.files );
    std::ranges::sort( af.files );
    std::vector<FoldRow> cand;
    for( const CorpusHit& h : in.hits )
    {
        cand.push_back( { h.file, h.line } );
    }
    grepAnyWordFiles( grepAny, in.last, cand );
    std::ranges::sort( cand, []( const FoldRow& a, const FoldRow& b ) { return std::tie( a.file, a.line ) < std::tie( b.file, b.line ); } );
    std::vector<FoldRow> fold;
    std::string_view     prev;
    for( const FoldRow& r : cand )
    {
        if( r.file != prev && foldable( r.file ) && !std::ranges::binary_search( af.files, r.file ) )
        {
            fold.push_back( r );
        }
        prev = r.file;
    }
    return fold;
}
} // namespace detail

// W2. `whoCallsAsk`: the question asks who calls / where it is used (rule R2's who-calls and where-used kinds).
[[nodiscard]] inline RouteEvidence rt2Evidence( const F1Inputs& in, std::string_view grepAny, bool whoCallsAsk )
{
    RouteEvidence ev;
    detail::nonGapReasons( frozenF1( in ).why, ev.residual );
    const std::string answer = detail::stripComments( in.answer );
    const std::string any    = detail::stripComments( grepAny );
    ev.fold = detail::foldRows( in, answer, any );
    if( const std::string_view m = in.verb == "callers" ? detail::macroCallerRow( answer ) : std::string_view{}; !m.empty() )
    {
        detail::addReason( ev.residual, "macro-row:" + std::string( m ) );
    }
    if( in.verb == "uses" && whoCallsAsk && detail::grepFloors( in.grep, in.last ).targetFloor )
    {
        detail::addReason( ev.residual, "target-floor" );
    }
    if( ev.fold.size() > kFoldCap )
    {
        detail::addReason( ev.residual, "text-gap-capped:" + std::to_string( ev.fold.size() ) );
    }
    if( detail::grepCapped( any ) )
    {
        detail::addReason( ev.residual, "grep-capped" );
    }
    return ev;
}
// ── RT2-C (results/RT2_ROUTE_1118/PREREG_CALLEES.md): the what-it-calls route's evidence ─────────────────────────────────────
// BODY GAP: the names X's own body CALLS (an identifier followed by `(`, or by `!` and a bracket: a Rust macro), keywords
// aside, that have an in-repo definition (the caller's test) and that the --callees answer names nowhere — no <s> row (its
// last segment), no <dc>, no <stdm>, no <vr to=>, no <in> closure, and not X itself. A call the graph did not bind (inside a
// macro_rules invocation, through a local the resolver cannot type) shows here as a name the answer omits: residual reason
// `body-gap:N:FIRST`, which warns and carries the first --for page. It reads text, not the graph: a local variable that shares
// a definition's name can be a false alarm (a page of bytes), never a silent miss of a name the body spells.
namespace detail
{
inline constexpr std::string_view kCallKeywords[] = { "if", "for", "while", "switch", "return", "sizeof", "catch", "match", "elif", "and", "or",
                                                      "not", "in", "case", "do", "else", "new", "typeof", "await", "yield", "assert", "defined",
                                                      "alignof", "decltype", "static_assert", "loop", "where", "unless", "until", "lambda" };
} // namespace detail

namespace detail
{
// The end of the identifier at `i` when it is CALL-SHAPED — followed by `(`, or by `!` and a bracket (a Rust macro) — else 0.
[[nodiscard]] inline std::size_t callShapedEnd( std::string_view body, std::size_t i, std::size_t j )
{
    std::size_t k = j;
    const bool bang = k < body.size() && body[ k ] == '!';
    k += bang ? 1 : 0;
    while( k < body.size() && ( body[ k ] == ' ' || body[ k ] == '\t' ) )
    {
        ++k;
    }
    const bool open = k < body.size() && ( body[ k ] == '(' || ( bang && ( body[ k ] == '[' || body[ k ] == '{' ) ) );
    return open && j > i ? j : 0;
}
} // namespace detail

// The distinct call-shaped names in `body`, in first-seen order.
[[nodiscard]] inline std::vector<std::string> bodyCallNames( std::string_view body )
{
    std::vector<std::string> out;
    for( std::size_t i = 0; i < body.size(); )
    {
        const bool starts = detail::isIdentChar( body[ i ] ) && !( i > 0 && detail::isIdentChar( body[ i - 1 ] ) ) && !rw::forroute::detail::isAsciiDigit( body[ i ] );
        if( !starts )
        {
            ++i;
            continue;
        }
        std::size_t j = i;
        while( j < body.size() && detail::isIdentChar( body[ j ] ) )
        {
            ++j;
        }
        const std::string_view name = body.substr( i, j - i );
        if( detail::callShapedEnd( body, i, j ) != 0 && !detail::listed( detail::kCallKeywords, name ) && std::ranges::find( out, name ) == out.end() )
        {
            out.emplace_back( name );
        }
        i = j;
    }
    return out;
}

// Every name a --callees answer accounts for: <s n=> (last segment), <dc n=>, <stdm n="a,b">, <vr to=>, <in n=>; sorted.
[[nodiscard]] inline std::vector<std::string> calleeAnswerNames( std::string_view answer )
{
    const std::string        body = detail::stripComments( answer );
    std::vector<std::string> out;
    for( const std::string_view tag : { std::string_view( "<s " ), std::string_view( "<dc " ), std::string_view( "<in " ) } )
    {
        for( const std::string_view span : detail::tagSpans( body, tag ) )
        {
            out.emplace_back( rw::forroute::lastSegment( detail::attrOf( span, "n" ) ) );
        }
    }
    for( const std::string_view span : detail::tagSpans( body, "<vr " ) )
    {
        out.emplace_back( rw::forroute::lastSegment( detail::attrOf( span, "to" ) ) );
    }
    for( const std::string_view span : detail::tagSpans( body, "<stdm " ) )
    {
        for( std::string_view list = detail::attrOf( span, "n" ); !list.empty(); )
        {
            const std::size_t comma = list.find( ',' );
            out.emplace_back( list.substr( 0, comma ) );
            list = comma == std::string_view::npos ? std::string_view{} : list.substr( comma + 1 );
        }
    }
    std::ranges::sort( out );
    return out;
}

// The body-gap reason, "" when every defined call-shaped name is accounted for. `defined` answers "does the repo define it".
template <class Defined>
[[nodiscard]] inline std::string bodyGapReason( const std::vector<std::string>& calls, std::string_view answer, std::string_view self, Defined defined )
{
    const std::vector<std::string> named = calleeAnswerNames( answer );
    std::vector<std::string>       gap;
    for( const std::string& c : calls )
    {
        if( c != self && !std::ranges::binary_search( named, c ) && defined( c ) )
        {
            gap.push_back( c );
        }
    }
    return gap.empty() ? std::string() : detail::countedReason( "body-gap", gap.size(), gap.front() );
}

} // namespace rw::partialwarn
