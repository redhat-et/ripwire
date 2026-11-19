#pragma once
// legendseen.h — `--legend-seen=FILE`: an answer leaves out the legend definitions its caller says it already HOLDS
// (lane LS1, 2026-11-18; pre-registered in results/LS1_LEGENDSEEN_1118/PREREG.md).
//
// WHY. A CLI agent makes several calls a session and receives mostly the same definitions each time: an answer-first
// `--for` page 1 is ~12 KB of rows plus a ~4 KB trailing legend. The MCP server stops the resend with a session
// (`--mcp-legend=session`); a CLI run has no session, and making one the DEFAULT would make output depend on earlier
// runs (owner ruling: determinism). `--legend-have=` asserts whole TIERS, which must be taught before they pay (lane
// P4: +2.6 % at 5 calls, −0.7 % at 10). This is the per-DEFINITION handshake P4 named instead: nothing to teach,
// nothing to refuse.
//
// WHAT FILE HOLDS. One 16-hex ENTRY HASH per line: FNV-1a 64 of that entry's line in `ripwire --legend-dict` plus its
// newline — the dictionary's own versionOfLines over one line. Blank lines and lines starting `#` are skipped; order
// and repeats do not matter. The hash is CONTENT-addressed, which is the whole robustness argument:
//   * a file written by another build is never wrong — a definition whose text changed hashes differently, matches
//     nothing, and rides the answer inline. So there is no "foreign dictv" to refuse: the check is per entry, finer
//     than a per-file version, and an upgrade mid-session costs only the definitions that actually changed;
//   * a hash this binary does not know is simply not held. Only a line that is no hash at all (or an unreadable,
//     missing or oversized file) distrusts the WHOLE file: the answer is served whole and stderr says so. FILE can
//     never turn a good call into a failure.
//
// WHO WRITES FILE: THE CALLER, FROM WHAT IT RECEIVED. `ripwire --legend-dict=seen` reads text on stdin and prints the
// hashes of the entries that text carries in its XML comments (seenHashesText). The binary never appends to FILE
// itself: a `| head`, a grep or a display limit means the reader did NOT receive the whole answer, and only the
// consumer knows what it received. The answer is therefore a pure function of argv and FILE's bytes.
//
// WHAT THE ANSWER LOSES. Exactly the entry texts FILE holds, from the answer's comments — before the root, between its
// rows, and the block-local legends a --for section carries with it — never inside CDATA, where ripwire's own source
// carries legend-shaped string literals. An entry is matched verbatim at a clause boundary, LONGEST FIRST, and a match claims
// its span, so a shorter entry nested in a longer clause is never cut out of it. Each reduced comment says so in
// place (" [legend-seen: N held]", or that alone when nothing else is left). Rows, CDATA and every root attribute but est_tokens= are byte-identical; est_tokens= is repriced to the
// bytes delivered (the page's own pricer on a --for page, the dict posture's proportional reprice elsewhere). One
// comment marks the omission where it happened, with its count and the dictionary that holds every definition:
//     <!-- legend-seen: N definitions you hold were left out; the legend-dict flag prints every one (dictv=…) -->
// The marker is prose, not a new attribute (a new attribute costs a reading in every verb dialect that can carry it),
// and names the flag without its dashes: "--" is ill-formed inside an XML comment (G4).
// An answer the reduction would not shorten is served unchanged.
//
// Gate: test/legendseencheck.sh. The hook that keeps FILE for a Claude Code session: hooks/ripwire-legend-seen.sh.

#include "compactlegend.h"   // findCompactRoot, repriceEstTokensIn
#include "forpages.h"        // forpages::pricePage — est_tokens= on a --for page prices every byte of it
#include "infra/Diagnostics.h"
#include "infra/sortutil.h"   // svLess — the portable string_view order (portablebuildcheck #6b)
#include "legenddict.h"

#include <algorithm>
#include <cstddef>
#include <cstdint>
#include <string>
#include <string_view>
#include <vector>

namespace rw::legendseen
{

// A file over this is not a holding anyone wrote one call at a time (the whole dictionary is ~1,230 lines, 21 KB).
inline constexpr std::size_t kMaxFileBytes = 4u << 20;
// An entry shorter than this is too short to be matched as a clause without matching ordinary prose.
inline constexpr std::size_t kMinEntryBytes = 12;

// ── hashes ───────────────────────────────────────────────────────────────────────────────────────────────────────

// An entry's hash is the dictionary's own version function over its one line: versionOfLines( line + '\n' ), the
// 16 lowercase hex a caller can recompute from `ripwire --legend-dict` alone.
inline std::string entryHashOf( std::size_t id )
{
    return legenddict::versionOfLines( legenddict::entryLine( id ) + '\n' );
}

// Per entry id: its hash, and the match order (longest body first, then id). Built once per process.
struct EntryIndex
{
    std::vector<std::string>   hash;    // by id: 16 lowercase hex
    std::vector<std::size_t>   order;   // ids of matchable entries, longest body first
};

inline const EntryIndex& entryIndex()
{
    static const EntryIndex idx = []
    {
        EntryIndex x;
        x.hash.resize( legenddict::kEntryCount );
        for( std::size_t id = 0; id < legenddict::kEntryCount; ++id )
        {
            x.hash[ id ] = entryHashOf( id );
            if( legenddict::entryBody( id ).size() >= kMinEntryBytes ) { x.order.push_back( id ); }
        }
        std::sort( x.order.begin(), x.order.end(), []( std::size_t a, std::size_t b )
                   {
                       const std::size_t la = legenddict::entryBody( a ).size(), lb = legenddict::entryBody( b ).size();
                       return la != lb ? la > lb : a < b;
                   } );
        return x;
    }();
    return idx;
}

// ── matching one comment ─────────────────────────────────────────────────────────────────────────────────────────

namespace detail
{

inline bool isSep( char c ) noexcept { return c == ';' || c == '.' || c == ':' || c == ']' || c == '-'; }

// Does a clause begin at p? The entry opens with its own separator, or follows "<!-- ", ". ", "; ", ": ", "] " or "[".
inline bool leftBoundary( std::string_view t, std::size_t p, std::string_view body ) noexcept
{
    const char c = body.front();
    if( c == ' ' || c == ';' || c == '[' || c == '.' || c == ',' ) { return true; }
    if( p >= 1 && t[ p - 1 ] == '[' ) { return true; }
    return p >= 2 && t[ p - 1 ] == ' ' && isSep( t[ p - 2 ] );
}

// Does the clause end at e? The entry closes with its own separator, or is followed by the comment's close, ". ",
// "; ", "]" or " [".
inline bool rightBoundary( std::string_view t, std::size_t e, std::string_view body ) noexcept
{
    const char c = body.back();
    if( c == '.' || c == ';' || c == ']' || c == ' ' ) { return true; }
    if( e >= t.size() ) { return false; }
    const std::string_view rest = t.substr( e );
    if( rest.starts_with( " -->" ) || rest.starts_with( "-->" ) || rest.starts_with( " [" ) || t[ e ] == ']' ) { return true; }
    return ( t[ e ] == '.' || t[ e ] == ';' ) && ( e + 1 == t.size() || t[ e + 1 ] == ' ' );
}

}   // namespace detail

struct Match
{
    std::size_t begin = 0;
    std::size_t end   = 0;
    std::size_t id    = 0;
};

// Every entry in one comment ("<!-- … -->"), longest first, each claiming its span. Sorted by position.
inline std::vector<Match> entriesIn( std::string_view comment )
{
    std::vector<Match> out;
    if( comment.size() < 9 ) { return out; }
    // From just after "<!--": an entry spelled with its own leading space (" h value_refs=N: …") owns the space the
    // comment opens with, and is the whole comment when it is the only thing in it.
    const std::size_t lo = 4, hi = comment.size() - 3;
    const std::string_view inner = comment.substr( 0, hi );
    for( const std::size_t id : entryIndex().order )
    {
        const std::string_view body = legenddict::entryBody( id );
        if( body.size() > hi - lo ) { continue; }
        for( std::size_t at = inner.find( body, lo ); at != std::string_view::npos; at = inner.find( body, at + 1 ) )
        {
            const std::size_t end = at + body.size();
            const bool claimed = std::any_of( out.begin(), out.end(), [ & ]( const Match& m ) { return at < m.end && m.begin < end; } );
            if( !claimed && detail::leftBoundary( comment, at, body ) && detail::rightBoundary( comment, end, body ) )
            {
                out.push_back( { at, end, id } );
            }
        }
    }
    std::sort( out.begin(), out.end(), []( const Match& a, const Match& b ) { return a.begin < b.begin; } );
    return out;
}

// ── what a reader received: --legend-dict=seen ───────────────────────────────────────────────────────────────────

// Every COMPLETE comment of `text`, CDATA stepped over. An unterminated comment or CDATA (an answer cut by `| head`)
// ends the scan: what follows it was not received as a comment.
inline std::vector<std::string_view> receivedComments( std::string_view text )
{
    std::vector<std::string_view> out;
    for( std::size_t i = 0; i < text.size(); )
    {
        const std::size_t c = text.find( "<!--", i );
        const std::size_t d = text.find( "<![CDATA[", i );
        if( c == std::string_view::npos && d == std::string_view::npos ) { break; }
        if( d < c )
        {
            const std::size_t close = text.find( "]]>", d + 9 );
            if( close == std::string_view::npos ) { break; }
            i = close + 3;
            continue;
        }
        const std::size_t close = text.find( "-->", c + 4 );
        if( close == std::string_view::npos ) { break; }
        out.push_back( text.substr( c, close + 3 - c ) );
        i = close + 3;
    }
    return out;
}

// The hashes of the entries `received` carries, sorted, one per line — what a caller appends to FILE.
inline std::string seenHashesText( std::string_view received )
{
    std::vector<std::string_view> hs;
    for( const std::string_view comment : receivedComments( received ) )
    {
        for( const Match& m : entriesIn( comment ) ) { hs.push_back( entryIndex().hash[ m.id ] ); }
    }
    std::sort( hs.begin(), hs.end(), rw::sortutil::svLess );
    hs.erase( std::unique( hs.begin(), hs.end() ), hs.end() );
    std::string out;
    for( const std::string_view h : hs )
    {
        out.append( h );
        out += '\n';
    }
    return out;
}

// ── FILE ─────────────────────────────────────────────────────────────────────────────────────────────────────────

struct Holding
{
    std::vector<std::uint8_t> held;          // by entry id
    std::size_t               hashes = 0;    // distinct hashes FILE named
    std::size_t               known  = 0;    // entries of THIS dictionary they name
    std::size_t               badLine = 0;   // 1-based line that is no hash; 0 = none
};

// Parse FILE's bytes. A line that is not blank, not `#…` and not 16 lowercase hex makes the file untrusted (badLine).
inline Holding parseHolding( std::string_view bytes )
{
    Holding h;
    h.held.assign( legenddict::kEntryCount, 0 );
    std::vector<std::string_view> named;
    std::size_t lineNo = 0;
    for( std::size_t at = 0; at < bytes.size() && h.badLine == 0; )
    {
        const std::size_t nl = std::min( bytes.find( '\n', at ), bytes.size() );
        std::string_view line = bytes.substr( at, nl - at );
        at = nl + 1;
        ++lineNo;
        if( line.ends_with( '\r' ) ) { line.remove_suffix( 1 ); }
        if( line.empty() || line.front() == '#' ) { continue; }
        const bool hex = line.size() == 16 && std::all_of( line.begin(), line.end(), []( char c ) { return ( c >= '0' && c <= '9' ) || ( c >= 'a' && c <= 'f' ); } );
        if( !hex ) { h.badLine = lineNo; break; }
        named.push_back( line );
    }
    if( h.badLine != 0 ) { return h; }
    std::sort( named.begin(), named.end(), rw::sortutil::svLess );
    named.erase( std::unique( named.begin(), named.end() ), named.end() );
    h.hashes = named.size();
    const EntryIndex& idx = entryIndex();
    for( std::size_t id = 0; id < legenddict::kEntryCount; ++id )
    {
        if( std::binary_search( named.begin(), named.end(), std::string_view( idx.hash[ id ] ), rw::sortutil::svLess ) ) { h.held[ id ] = 1; ++h.known; }
    }
    return h;
}

// ── the reduction ────────────────────────────────────────────────────────────────────────────────────────────────

namespace detail
{

// Remove the held matches from one comment, right to left, tidying the separators each removal leaves.
inline std::string reduceComment( std::string_view comment, const std::vector<Match>& matches, const Holding& h, std::size_t& omitted )
{
    std::string t( comment );
    for( auto it = matches.rbegin(); it != matches.rend(); ++it )
    {
        if( h.held[ it->id ] == 0 ) { continue; }
        const std::string_view body = legenddict::entryBody( it->id );
        std::size_t p = it->begin;
        t.erase( p, it->end - it->begin );
        ++omitted;
        if( body.back() != '.' && p < t.size() && t[ p ] == '.' && ( p + 1 == t.size() || t[ p + 1 ] == ' ' ) ) { t.erase( p, 1 ); }   // "BODY." clauses
        if( p >= 2 && ( t.compare( p - 2, 2, "; " ) == 0 || t.compare( p - 2, 2, ": " ) == 0 ) && t.compare( p, 2, "; " ) == 0 ) { t.erase( p, 2 ); }
        if( p >= 1 && t[ p - 1 ] == ' ' && p < t.size() && t[ p ] == ' ' ) { t.erase( p, 1 ); }
    }
    return t;
}

// A reduced comment REFERS to what it left out, where it left it: " [legend-seen: N held]" before its close, or, when
// nothing else is left, the reference alone. A reader of any one block — a later page included — sees in place that
// definitions were omitted, and the answer's one marker says which dictionary holds them.
inline bool hollow( std::string_view comment ) noexcept;
inline std::string referInPlace( std::string_view reduced, std::size_t n )
{
    const std::string ref = "legend-seen: " + std::to_string( n ) + " held";
    if( hollow( reduced ) )
    {
        return "<!-- " + ref + " -->";
    }
    std::string out( reduced.substr( 0, reduced.size() - 3 ) );
    while( !out.empty() && out.back() == ' ' ) { out.pop_back(); }
    return out + " [" + ref + "] -->";
}

// Only separators and space left between the markers: nothing to say.
inline bool hollow( std::string_view comment ) noexcept
{
    if( comment.size() < 7 ) { return true; }
    const std::string_view inner = comment.substr( 4, comment.size() - 7 );
    return std::all_of( inner.begin(), inner.end(), []( char c ) { return c == ' ' || c == '.' || c == ';' || c == ':' || c == ','; } );
}

// Every comment span of an answer outside CDATA: before the root, between its rows, and INSIDE a block — a block-local
// legend (`<!-- ripwire for X …` on a --for section) travels with its block and is reduced where it stands. Only entry
// text is ever removed, so a data comment (`+more`, the map header) loses nothing. `ok` false = an unterminated comment
// or CDATA, a shape this pass does not cut (the answer is then served unchanged).
struct Spans
{
    bool                                             ok = false;
    std::vector<std::pair<std::size_t, std::size_t>> comments;
    CompactRootInfo                                  root;
};

inline Spans answerComments( std::string_view doc )
{
    Spans s;
    s.root = findCompactRoot( doc );
    if( s.root.tag.empty() || s.root.openEnd > doc.size() ) { return s; }
    for( std::size_t i = 0; i < doc.size(); )
    {
        const std::size_t c = doc.find( "<!--", i );
        const std::size_t d = doc.find( "<![CDATA[", i );
        if( c == std::string_view::npos && d == std::string_view::npos ) { break; }
        const bool        cdata = d < c;
        const std::size_t close = cdata ? doc.find( "]]>", d + 9 ) : doc.find( "-->", c + 4 );
        if( close == std::string_view::npos ) { return s; }
        if( !cdata ) { s.comments.emplace_back( c, close + 3 ); }
        i = close + 3;
    }
    s.ok = true;
    return s;
}

}   // namespace detail

enum class Outcome : std::uint8_t
{
    Reduced,         // definitions were left out
    Unchanged,       // nothing FILE holds is in this answer, or leaving it out would not shorten it
    NotApplicable,   // not an XML answer whose comments this pass understands: served unchanged
};

struct Result
{
    Outcome     outcome = Outcome::NotApplicable;
    std::size_t omitted = 0;
};

inline std::string marker( std::size_t omitted )
{
    return "<!-- legend-seen: " + std::to_string( omitted ) + " definitions you hold were left out; the legend-dict flag prints every one (dictv="
         + legenddict::dictionaryVersion() + ") -->";
}

// Leave out of `doc` every definition `h` holds — see the header. `doc` is the answer as the default posture serves it.
inline Result applySeenPosture( std::string& doc, const Holding& h )
{
    Result r;
    const std::string_view view = doc;
    const detail::Spans    spans = detail::answerComments( view );
    if( !spans.ok )
    {
        return r;
    }
    std::string out;
    out.reserve( doc.size() );
    std::size_t copied = 0, markAt = std::string::npos;
    for( const auto& [ b, e ] : spans.comments )
    {
        const std::string_view comment = view.substr( b, e - b );
        const std::size_t      before  = r.omitted;
        const std::string      reduced = detail::reduceComment( comment, entriesIn( comment ), h, r.omitted );
        if( r.omitted != before && reduced.find( "--", 4 ) != reduced.size() - 3 )
        {
            // Two removals that left "-" against "-" would make the comment ill-formed XML (G4): this one stays whole.
            DISCLOSE( Diagnostics::answerUnchanged, "the comment is served whole: only its cost stays",
                      "legendseen: a reduced comment would hold \"--\" — kept unreduced" );
            r.omitted = before;
        }
        if( r.omitted == before )
        {
            continue;
        }
        out.append( view.substr( copied, b - copied ) );
        if( markAt == std::string::npos ) { markAt = out.size(); }
        out += detail::referInPlace( reduced, r.omitted - before );
        copied = e;
    }
    r.outcome = Outcome::Unchanged;
    if( r.omitted == 0 )
    {
        return r;
    }
    out.append( view.substr( copied ) );
    out.insert( markAt, marker( r.omitted ) );
    // est_tokens= PRICES WHAT WAS DELIVERED. A --for page prices itself (every byte, the emitter's two rates); any other
    // answer is repriced from its own value as the dict posture does, on the root and on a map header before it.
    const CompactRootInfo root = findCompactRoot( out );
    if( root.tag.empty() )
    {
        return r;   // cannot happen: no comment edit touches the root
    }
    if( root.tag == "ctx" && view.substr( spans.root.openBegin, spans.root.openEnd - spans.root.openBegin ).find( " page=\"" ) != std::string_view::npos )
    {
        forpages::detail::pricePage( out );
    }
    else
    {
        repriceEstTokensIn( out, root.openBegin, root.openEnd, doc.size(), out.size() );
        repriceEstTokensIn( out, 0, root.openBegin, doc.size(), out.size() );
    }
    if( out.size() >= doc.size() )
    {
        r.outcome = Outcome::Unchanged;   // the marker costs more than the definitions it replaced
        r.omitted = 0;
        return r;
    }
    doc.swap( out );
    r.outcome = Outcome::Reduced;
    return r;
}

}   // namespace rw::legendseen
