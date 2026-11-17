#pragma once
// hoprecord.h — THE hop record (HOP-CONTEXT-1, IDEAS_LIST card 20; reports/hop-context-s0.md "Recommended design").
//
// A call edge an answer prints (a --path hop row, a --connect <e> row) used to say only which two definitions it joins.
// What an agent opens next is the CALL: where the caller makes it, with which arguments, and what the callee takes and
// returns. This file is the one place that knows those facts for an edge, and every edge-printing verb reads them here:
//
//   HopWant      — an edge the answer will print, and whether it prints in full (site + call + sig) or site only;
//   hopFacts()   — the ONE provider: one pass over ing.references for EVERY wanted edge of the answer (never one scan per hop),
//                  then one read per distinct file (FileTextCache), then per-edge slicing that reads no file and scans nothing;
//   hopAttrsXml()— the ONE renderer, with the shed level: ` site="f:l" [sites="N"] [call="…"] [sig="…"]`;
//   hopRootAttrsXml() / hopLegend() / the compact readings (compactlegend.h) — the disclosures, present-only.
//
// Site selection is option A (lane 1): the calls inside the caller whose callee NAME is the edge's callee (the --uses /
// sites_at= filter, editcheck.h callSiteCounts + CallSiteCalleeTest), a call whose argument count the callee accepts first,
// then a call whose written qualifier is the callee's owner, then file/line order. It is a name match, not proof that this call is the one the edge binds; the legend says so,
// and sites="N" counts the others. Per-edge stored sites (option B, Graph::outSite) are a follow-on.
//
// Honesty (CR lens 4): a call= or sig= is never guessed and never printed empty. A file that cannot be read, or whose length
// changed since indexing (FileTextCache::stale: a length compare, no content hash is stored), withholds it (hop_unread=), and a
// length change withholds site= too; a site whose text does not spell the callee (a macro-expanded or generated call)
// withholds call= (hop_notext=); an edge with no call naming the callee in its caller (an inherit/impl/link edge, an alias,
// a constructor reached by another name) prints no site= (hop_nosite=). Under a budget the renderer sheds sig=, then
// call=, then site= — all before the budget touches anything the answer printed without them (a join sig=, a leg: the hop
// attributes take their own allowance, never the answer's; owner rule: a budget that cuts answers is a bad budget).

#include "infra/emit.h"     // emitTo — the stats line
#include "editcheck.h"     // callSiteCounts / CallSiteCalleeTest — the --uses call-site filter and callee-name test
#include "elixir_resolve.h"   // elixirBaseName — an Elixir callee spells name/N in the index, name in the source
#include "filetext.h"      // FileTextCache — one read per file per answer
#include "graph.h"
#include "memberowner.h"   // MemberOwners — a TS/JS method's owner (no stored scope) for the owner-qualified pick
#include "model.h"
#include "redact.h"        // redactSecrets — call text is emitted source text (a credential seam, like cleanSig)
#include "sarif.h"         // rootRelativeUri — site= in the row's own path dialect
#include "serialize.h"     // cleanSig / escapeXml / truncateUtf8WithEllipsis

#include <algorithm>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <optional>
#include <span>
#include <string>
#include <string_view>
#include <tuple>
#include <utility>
#include <vector>

namespace rw
{

inline constexpr std::size_t   kHopCallMaxBytes  = 120;   // call= cap (U+2026 marks a cut)
inline constexpr std::size_t   kHopCallMaxLines  = 3;     // a call whose arguments continue joins up to this many lines
inline constexpr std::size_t   kHopSigMaxBytes   = 160;   // sig= cap on a hop (cleanSig's own 240 cap applies first)
inline constexpr std::size_t   kHopWindowBytes   = 512;   // source bytes read before the callee name (twice that after): a minified line costs a window
inline constexpr std::uint32_t kHopNoRef         = UINT32_MAX;

// The kill switch (like RIPWIRE_NO_HOP_BODY): set, no hop attribute and no hop disclosure prints, byte for byte the
// answer before this lane (test/hopcontextcheck.sh arm 1 reads it).
inline bool hopContextOn()
{
    return std::getenv( "RIPWIRE_NO_HOP_CONTEXT" ) == nullptr;
}

// What the renderer prints, most first; each level drops what the one before kept. Proof detail sheds before sig=, but
// this lane adds no proof word (via=/prov= are the proof and are never shed), so the first shed is sig=.
enum class HopShed : std::uint8_t
{
    Full,       // site= sites= call= sig=
    NoSig,      // site= sites= call=
    SiteOnly,   // site= sites=
    Off,        // nothing: shed before a budget touches anything the answer printed without the hop record (a join sig, a leg)
};

struct HopWant
{
    NodeId        from;
    NodeId        to;
    bool          full;                // false: the answer prints site= only for it (a later --path pair), so no text is read for it
    std::uint32_t pinRef = kHopNoRef;  // != kHopNoRef: the hop IS this call (a --path declined last hop's record): site= is it, no pick
};

enum class HopGap : std::uint8_t
{
    None,
    Unread,   // the file could not be read, or its length changed since indexing
    NoText,   // the site's text does not spell the callee (macro-expanded, generated)
    Redacted, // the callee's name sits in or against a redacted span: no call text can print without a cut through it
};

// How site= was picked among the caller's calls of the callee's name (the tiebreak: a call whose argument count the callee
// accepts, then a call whose written qualifier is the callee's owner; the review's S1). Present-only on the row.
enum class HopSiteBy : std::uint8_t
{
    Decided,   // one such line, or the tiebreak picked one
    Tie,       // site_by="first": several lines fit equally and the caller also calls a namesake; site= is the first (no guess)
    NoFit,     // site_by="nofit": no such line's argument count fits the callee; site= is the first name match
};

struct HopRecord
{
    NodeId        from    = kNoNode;
    NodeId        to      = kNoNode;
    bool          full    = false;
    std::uint32_t ref     = kHopNoRef;   // the chosen call reference (ing.references index); kHopNoRef = no site
    std::uint32_t nSites  = 0;           // distinct lines in `from` that call the callee's name
    std::string   call;                  // trimmed call text, unescaped; "" = not printed (see callGap)
    std::string   sig;                   // callee signature, unescaped; "" = not printed (see sigGap)
    HopGap        callGap = HopGap::None;
    HopGap        sigGap  = HopGap::None;
    HopSiteBy     siteBy  = HopSiteBy::Decided;
    bool          siteStale = false;     // the site's file was read and its length differs from the indexed one: site= withheld (hop_unread=)
    RedactCounts  callRx{}, sigRx{};     // the redactions inside call / sig, tallied into the run's count by whoever prints them
};

// What the root disclosures and the legend read: present-only flags and counts over a set of hops — every hop of the answer
// (hopFacts), or only the hops a --connect pass printed after a budget dropped legs (CodeRabbit #535: counts over hops the
// answer no longer prints are not counts of the answer).
struct HopTally
{
    bool        on = false;   // false: the kill switch, or nothing wanted — renders nothing
    bool        anySite = false, anySites = false, anyCall = false, anySig = false, anyTie = false, anyNoFit = false;
    std::size_t nosite = 0, unread = 0, notext = 0, redacted = 0;

    void add( const HopRecord& rec ) noexcept
    {
        if( rec.ref == kHopNoRef )
        {
            ++nosite;
        }
        else if( !rec.siteStale )
        {
            anySite  = true;
            anySites = anySites || rec.nSites > 1;
            anyTie   = anyTie || rec.siteBy == HopSiteBy::Tie;
            anyNoFit = anyNoFit || rec.siteBy == HopSiteBy::NoFit;
        }
        unread += rec.siteStale || rec.callGap == HopGap::Unread || rec.sigGap == HopGap::Unread ? 1 : 0;
        notext += rec.callGap == HopGap::NoText ? 1 : 0;
        redacted += rec.callGap == HopGap::Redacted ? 1 : 0;
        anyCall = anyCall || !rec.call.empty();
        anySig  = anySig || !rec.sig.empty();
    }
};

inline void addRedactions( RedactCounts* tally, const RedactCounts& rx ) noexcept
{
    if( tally != nullptr )
    {
        for( std::size_t k = 0; k < tally->byKind.size(); ++k )
        {
            tally->byKind[k] += rx.byKind[k];
        }
    }
}

struct HopFacts : HopTally
{
    std::vector<HopRecord> recs;         // sorted by (from, to)
    std::size_t            referenceScans = 0, filesRead = 0;   // arm 8: one scan per answer

    const HopRecord* find( NodeId from, NodeId to ) const noexcept
    {
        const auto it = std::lower_bound( recs.begin(), recs.end(), std::pair{ from, to },
                                          []( const HopRecord& r, const std::pair<NodeId, NodeId>& k ) { return r.from != k.first ? r.from < k.first : r.to < k.second; } );
        return it != recs.end() && it->from == from && it->to == to ? &*it : nullptr;
    }
};

namespace hopdetail
{

inline bool identByte( char c ) noexcept
{
    const unsigned char u = static_cast<unsigned char>( c );
    return u >= 0x80 || ( u >= '0' && u <= '9' ) || ( u >= 'a' && u <= 'z' ) || ( u >= 'A' && u <= 'Z' ) || c == '_' || c == '$';
}

// The last segment of a qualified spelling (`A` for "ns::A", `m` for "pkg.T#m"): the text after the final ::, . or #.
inline std::string_view lastSegment( std::string_view n ) noexcept
{
    for( const std::string_view sep : { std::string_view( "::" ), std::string_view( "." ), std::string_view( "#" ) } )
    {
        if( const std::size_t at = n.rfind( sep ); at != std::string_view::npos && at + sep.size() < n.size() )
        {
            n = n.substr( at + sep.size() );
        }
    }
    return n;
}

// The source spelling of a callee's name: the leaf segment (an index name may carry an owner), Elixir's /N dropped.
inline std::string_view leafName( const Symbol& s ) noexcept
{
    return lastSegment( editCheckContractId( s.name, s ) );   // Elixir's /N dropped (the one Lang:: compare, editcheck.h)
}

// The first whole-word occurrence of `name` in text[from, to), npos when none.
inline std::size_t findWord( std::string_view text, std::size_t from, std::size_t to, std::string_view name ) noexcept
{
    const std::string_view hay  = text.substr( 0, std::min( to, text.size() ) );   // a match must end by `to`
    const auto             edge = [ & ]( std::size_t before, std::size_t after ) { return ( before == 0 || !identByte( text[ before - 1 ] ) ) && ( after >= text.size() || !identByte( text[ after ] ) ); };
    std::size_t            at   = name.empty() ? std::string_view::npos : hay.find( name, from );
    while( at != std::string_view::npos && !edge( at, at + name.size() ) )
    {
        at = hay.find( name, at + 1 );
    }
    return at;
}

// A byte a credential shape can hold (redact.h kRedactRules: [A-Za-z0-9_\-+/=.]). A cut between two of them can split a
// token, and the half without its prefix no rule recognises, so every cut below lands on a run boundary instead.
inline bool tokenByte( char c ) noexcept
{
    const unsigned char u = static_cast<unsigned char>( c );
    return ( u >= '0' && u <= '9' ) || ( u >= 'a' && u <= 'z' ) || ( u >= 'A' && u <= 'Z' ) || c == '_' || c == '-' || c == '+' || c == '/' || c == '='
           || c == '.';
}

// Move cut `c` in `t` off a run of token bytes: forward to the run's end (a leading cut), backward to its start (a trailing
// cut), never past `limit` (the callee name's start or end: the name prints whatever run it sits in). Token bytes are ASCII,
// so the result is a codepoint boundary whenever `c` was. O(c - limit), never O(text): it is applied to a whole file's
// cached text too.
inline std::size_t unsplitRun( std::string_view t, std::size_t c, bool forward, std::size_t limit ) noexcept
{
    while( ( forward ? c < limit : c > limit ) && c > 0 && c < t.size() && tokenByte( t[ c - 1 ] ) && tokenByte( t[c] ) )
    {
        c = forward ? c + 1 : c - 1;
    }
    return c;
}

// unsplitRun on redacted text (a call window, at most a few KB): first out of a redaction span (the kept prefix, U+2026,
// [REDACTED:kind]) the cut would split, then off a token run; the caller clamps the result to the name.
inline std::size_t unsplitCut( std::string_view t, std::size_t c, bool forward, std::size_t limit ) noexcept
{
    static constexpr std::string_view kMark = "\xE2\x80\xA6[REDACTED:";
    for( std::size_t at = t.find( kMark ); at != std::string_view::npos && at < c; at = t.find( kMark, at + 1 ) )
    {
        std::size_t s = at;
        while( s > 0 && tokenByte( t[ s - 1 ] ) )
        {
            --s;
        }
        const std::size_t close = t.find( ']', at );
        const std::size_t e     = close == std::string_view::npos ? t.size() : close + 1;
        if( s < c && c < e )
        {
            c = forward ? e : s;
            break;
        }
    }
    return unsplitRun( t, c, forward, limit );
}

// The call text of one site: from its line's first non-blank byte (or, when the site sits on the caller's own one-line
// definition, from the end of the caller's signature: the agent has that row already), joined across up to
// kHopCallMaxLines lines while the call's parentheses are open, whitespace runs collapsed, REDACTED, and only then cut
// at kHopCallMaxBytes (a callee name past the cut moves the window so the name stays in view). Every cut — the bounded
// window on a long line, the move to the name, the cap — lands off a token run and off a redaction span, so a credential
// a cut would split prints whole-redacted or not at all (CR lens 4; the review's M1). Gap set when no honest text exists.
struct CallText
{
    std::string text;
    HopGap      gap = HopGap::None;
};
inline CallText callText( FileTextCache& files, const Reference& r, std::string_view name, const Symbol& caller, RedactCounts* redact )
{
    CallText out;
    const std::string* src = files.text( r.fileId );
    if( src == nullptr || files.stale( r.fileId ) )
    {
        out.gap = HopGap::Unread;
        return out;
    }
    const std::span<const std::uint32_t> lines = files.lineStarts( r.fileId );
    if( r.line == 0 || r.line > lines.size() || r.startByte >= src->size() )
    {
        out.gap = HopGap::Unread;   // the stored line or offset is outside the file read: it changed since indexing
        return out;
    }
    const std::size_t lineAt  = lines[ r.line - 1 ];
    const auto        lineEnd = [ & ]( std::size_t ln ) -> std::size_t   // 1-based line ln, end before its '\n'
    {
        const std::size_t e = ln < lines.size() ? lines[ ln ] - 1 : src->size();
        return e > 0 && e <= src->size() && ( *src )[ e - 1 ] == '\r' ? e - 1 : e;
    };
    if( r.startByte < lineAt || r.startByte > lineEnd( r.line ) )
    {
        out.gap = HopGap::Unread;   // the offset no longer sits on the stored line
        return out;
    }
    // the window: the site's line, then continuation lines while the call's parentheses stay open
    std::size_t endAt   = lineEnd( r.line );
    std::size_t lastLn  = r.line;
    std::size_t namePos = findWord( *src, r.startByte, endAt, name );
    const auto  depthOf = [ & ]( std::size_t a, std::size_t b )
    {
        long d = 0;
        for( std::size_t i = a; i < b; ++i )
        {
            d += ( *src )[i] == '(' ? 1 : ( *src )[i] == ')' ? -1 : 0;
        }
        return d;
    };
    while( lastLn < r.line + kHopCallMaxLines - 1 && lastLn < lines.size()
           && ( namePos == std::string_view::npos || depthOf( namePos, endAt ) > 0 ) )
    {
        ++lastLn;
        endAt = lineEnd( lastLn );
        if( namePos == std::string_view::npos )
        {
            namePos = findWord( *src, r.startByte, endAt, name );
        }
    }
    if( namePos == std::string_view::npos )
    {
        out.gap = HopGap::NoText;   // nothing in the window spells the callee: a macro-expanded or generated call
        return out;
    }
    std::size_t begin = lineAt;
    // a one-line caller (`int top( int n ) { return mid( n ); }`): its signature is the row above, so the text starts at
    // the statement after it (past an opening `{`, `:` or `=>`), never echoing the caller's own head
    if( caller.fileId == r.fileId && caller.line == r.line && caller.sigEndByte > lineAt && caller.sigEndByte <= namePos )
    {
        begin = caller.sigEndByte;
        for( bool more = true; more && begin < namePos; )
        {
            const std::string_view at = std::string_view( *src ).substr( begin, namePos - begin );
            const std::size_t      n  = at.starts_with( "=>" ) ? 2 : at[0] == ' ' || at[0] == '\t' || at[0] == '{' || at[0] == ':' ? 1 : 0;
            begin += n;
            more = n > 0;
        }
    }
    while( begin < r.startByte && ( ( *src )[ begin ] == ' ' || ( *src )[ begin ] == '\t' ) )
    {
        ++begin;
    }
    // a minified or generated line: read a bounded window around the name, never the whole line (the cuts are marked);
    // both window edges move off a token run, so the redaction below sees every token it prints whole
    bool leadCut = false;
    if( namePos - begin > kHopWindowBytes )
    {
        begin = unsplitRun( *src, namePos - kHopWindowBytes, /*forward=*/true, namePos );
        begin = std::min( begin, namePos );
        while( begin < namePos && ( static_cast<unsigned char>( ( *src )[ begin ] ) & 0xC0 ) == 0x80 )
        {
            ++begin;
        }
        leadCut = true;
    }
    if( endAt > namePos + 2 * kHopWindowBytes )
    {
        endAt = std::max( unsplitRun( *src, namePos + 2 * kHopWindowBytes, /*forward=*/false, namePos + name.size() ), namePos + name.size() );
        while( endAt > namePos + name.size() && ( static_cast<unsigned char>( ( *src )[ endAt ] ) & 0xC0 ) == 0x80 )
        {
            --endAt;
        }
    }
    // collapse whitespace (tabs, CR, LF, runs) to one space; remember where the name lands in the collapsed text
    std::string flat;
    flat.reserve( endAt - begin );
    std::size_t flatName = 0;
    bool        inSpace  = false;
    for( std::size_t i = begin; i < endAt; ++i )
    {
        if( i == namePos )
        {
            flatName = flat.size();
        }
        const char c = ( *src )[i];
        if( c == ' ' || c == '\t' || c == '\n' || c == '\r' )
        {
            if( !flat.empty() && !inSpace )
            {
                flat.push_back( ' ' );
                inSpace = true;
            }
            continue;
        }
        flat.push_back( c );
        inSpace = false;
    }
    while( !flat.empty() && flat.back() == ' ' )
    {
        flat.pop_back();
    }
    if( depthOf( namePos, endAt ) > 0 )
    {
        flat += " \xE2\x80\xA6";   // the arguments run past kHopCallMaxLines: the cut is marked, never silent
    }
    // REDACT the widest text first, then cut it. The name's place in the redacted text: the text before it and the text from
    // it redact to the whole's halves exactly when no redaction crosses the name; otherwise the name sits in or against a
    // redacted span (or a credential keyword gates a token across it) and no honest call text exists — withheld, counted.
    if( redact != nullptr )
    {
        // The keyword-gated rule (a long run on a line that assigns token=/secret=/…) reads the run's whole source line. The
        // window drops part of the line (a long line's far bytes, a one-line caller's head), so a keyword there still gates
        // the window: the redaction reads it with a gate prefix, stripped after (the prefix itself is never redacted).
        static constexpr std::string_view kGate = "token= ";
        const std::size_t                 lastEnd = lineEnd( lastLn );
        const bool gateOutside = ( begin > lineAt && redactdetail::lineNamesCredential( std::string_view( *src ).substr( lineAt, begin - lineAt ) ) )
                                 || ( endAt < lastEnd && redactdetail::lineNamesCredential( std::string_view( *src ).substr( endAt, lastEnd - endAt ) ) );
        const auto redactGated = [ & ]( std::string_view in, std::string& res, RedactCounts& counts )
        {
            if( !gateOutside )
            {
                return redactSecrets( in, res, counts );
            }
            const bool any = redactSecrets( std::string( kGate ) + std::string( in ), res, counts );
            ASSUME( std::string_view( res ).starts_with( kGate ), "the gate prefix is too short for any rule and ends in a space" );
            res.erase( 0, kGate.size() );
            return any;
        };
        std::string whole;
        if( redactGated( flat, whole, *redact ) )
        {
            RedactCounts scratch;   // the split check's tally is not the answer's (the whole was counted once, above)
            std::string  pre, post;
            (void)redactGated( std::string_view( flat ).substr( 0, flatName ), pre, scratch );
            (void)redactGated( std::string_view( flat ).substr( flatName ), post, scratch );
            if( pre.size() + post.size() != whole.size() || whole.compare( 0, pre.size(), pre ) != 0 || whole.compare( pre.size(), post.size(), post ) != 0
                || !std::string_view( post ).starts_with( name ) )
            {
                out.gap = HopGap::Redacted;
                return out;
            }
            flatName = pre.size();
            flat     = std::move( whole );
        }
    }
    // the name past the cap: start ~40 bytes before it, off any token run or redaction span, marked with a leading U+2026
    std::string lead = leadCut ? "\xE2\x80\xA6" : "";
    if( lead.size() + flatName + name.size() > kHopCallMaxBytes - 10 && flatName > 40 )
    {
        std::size_t from = std::min( unsplitCut( flat, flatName - 40, /*forward=*/true, flatName ), flatName );
        while( from < flatName && ( static_cast<unsigned char>( flat[ from ] ) & 0xC0 ) == 0x80 )
        {
            ++from;
        }
        flat.erase( 0, from );
        flatName -= from;
        lead = "\xE2\x80\xA6";
    }
    flat.insert( 0, lead );
    flatName += lead.size();
    // the cap: back to a codepoint boundary, then off any token run or redaction span — never before the name's end
    if( flat.size() > kHopCallMaxBytes )
    {
        std::size_t cut = kHopCallMaxBytes;
        while( cut > 0 && ( static_cast<unsigned char>( flat[ cut ] ) & 0xC0 ) == 0x80 )
        {
            --cut;
        }
        cut = std::max( unsplitCut( flat, cut, /*forward=*/false, flatName + name.size() ), std::min( flatName + name.size(), flat.size() ) );
        flat.resize( cut );
        while( !flat.empty() && flat.back() == ' ' )
        {
            flat.pop_back();
        }
        flat += "\xE2\x80\xA6";
    }
    out.text = std::move( flat );
    return out;
}

// The callee's declaration signature (cleanSig, cut at kHopSigMaxBytes). Unread when the file cannot be read, changed, or
// the stored span no longer holds the callee's name.
inline CallText calleeSig( FileTextCache& files, const Symbol& s, RedactCounts* redact )
{
    CallText out;
    if( s.sigStartByte >= s.sigEndByte )
    {
        return out;   // the index recorded no signature for it: nothing to print, nothing withheld
    }
    const std::string* src = files.text( s.fileId );
    if( src == nullptr || files.stale( s.fileId ) || s.sigEndByte > src->size()
        || findWord( *src, s.sigStartByte, s.sigEndByte, leafName( s ) ) == std::string_view::npos )
    {
        out.gap = HopGap::Unread;
        return out;
    }
    out.text = cleanSig( src->data(), s.sigStartByte, s.sigEndByte, redact );
    truncateUtf8WithEllipsis( out.text, kHopSigMaxBytes );
    return out;
}

// The callee's owner as a call would qualify it (`A` for scope "ns::A"; a TS/JS method's enclosing class, which the index
// stores as no scope: memberowner.h containment, built at the first such callee), "" when it has none.
inline std::string_view ownerLeaf( const IngestResult& ing, const Symbol& s, std::optional<MemberOwners>& owners )
{
    if( !s.scope.empty() )
    {
        return lastSegment( s.scope );
    }
    if( !memberOwnerPossible( s ) )
    {
        return {};
    }
    return lastSegment( ( owners ? *owners : owners.emplace( ing ) ).ownerOf( s ) );
}

}   // namespace hopdetail

// THE provider. `wanted` may repeat an edge (a full want wins over a site-only one). Work, stated per loop (owner 11-04):
//   (1) per wanted edge: sort + unique, mark the caller bit — no scan;
//   (2) ONE pass over ing.references: per call reference in a marked caller, the wanted edges of that caller (an
//       equal_range of the sorted keys, usually 1-2) test the callee name; a hit keeps the best site and counts lines;
//   (3) per distinct file of a chosen site or callee: one read (FileTextCache);
//   (4) per edge: slice the cached text — no file read, no reference scan, no name lookup.
//   `deferRedactTally`: the call/sig redactions are kept per record (HopRecord::callRx/sigRx) and NOT added to `redact` here; the
//   renderer that prints them adds them (hopEdgeXml), so a --connect budget pass that is discarded, or an attribute it sheds,
//   is never counted (CodeRabbit #535). A --path answer prints every text it computes, so it tallies here.
inline HopFacts hopFacts( const IngestResult& ing, const Graph& g, std::vector<HopWant> wanted, RedactCounts* redact, FileTextCache* shared = nullptr,
                          bool deferRedactTally = false )
{
    std::optional<FileTextCache> own;   // a verb that reads no other file for the answer lends no reader: one is made here
    FileTextCache&               files = shared != nullptr ? *shared : own.emplace( ing );
    HopFacts out;
    if( !hopContextOn() || wanted.empty() )
    {
        return out;
    }
    out.on = true;
    std::sort( wanted.begin(), wanted.end(), []( const HopWant& a, const HopWant& b )
               { return a.from != b.from ? a.from < b.from : a.to != b.to ? a.to < b.to : a.full != b.full ? a.full > b.full : a.pinRef < b.pinRef; } );
    wanted.erase( std::unique( wanted.begin(), wanted.end(), []( const HopWant& a, const HopWant& b ) { return a.from == b.from && a.to == b.to; } ), wanted.end() );
    out.recs.resize( wanted.size() );
    std::vector<char> callerSel( ing.symbols.size(), 0 );
    for( std::size_t k = 0; k < wanted.size(); ++k )   // (1)
    {
        EXPECTS( wanted[k].from < ing.symbols.size() && wanted[k].to < ing.symbols.size(), "a hop joins two indexed symbols" );
        out.recs[k].from = wanted[k].from;
        out.recs[k].to   = wanted[k].to;
        out.recs[k].full = wanted[k].full;
        callerSel[ wanted[k].from ] = 1;
    }
    // one callee test per wanted edge, built before the pass (an Elixir callee builds its resolver once, here)
    std::vector<CallSiteCalleeTest> tests;
    tests.reserve( wanted.size() );
    for( const HopWant& w : wanted )
    {
        tests.emplace_back( ing, ing.symbols[ w.to ], std::span<const NodeId>( &w.to, 1 ) );
    }
    // The arity half of the tiebreak: can the edge's callee accept this call's argument count? The --edit-check rule
    // (editCheckArityAccepts): an uncounted call, a variadic/defaulted callee or an implicit receiver always fits. A C-family
    // callee whose declaration may carry defaults is read (editCheckMinArity) only for a call passing FEWER arguments than
    // it takes, once per edge, lazily: most edges never pay it.
    EditCheckSpliced                     noSplice{};
    std::optional<EditCheckSources>      declSources;
    std::vector<std::int32_t>            minArity( wanted.size(), -1 );   // -1 = not read yet
    std::vector<NodeId>                  untiedScratch;
    const auto                           fits = [ & ]( std::size_t k, const Reference& r ) -> bool
    {
        const Symbol& callee = ing.symbols[ wanted[k].to ];
        if( !r.argCountKnown || callee.arityExact == 0 || editCheckImplicitReceiver( callee ) || r.argCount == callee.params )
        {
            return true;
        }
        if( r.argCount > callee.params || !langCompatible( callee.lang, Lang::C ) )
        {
            return false;
        }
        if( minArity[k] < 0 )
        {
            minArity[k] = editCheckMinArity( ing, declSources ? *declSources : declSources.emplace( ing, noSplice ), wanted[k].to, untiedScratch );
        }
        return std::uint32_t( minArity[k] ) <= r.argCount;
    };
    // the owner a qualified call spells, once per edge (never per reference)
    std::optional<MemberOwners>   memberOwners;
    std::vector<std::string_view> owners( wanted.size() );
    for( std::size_t k = 0; k < wanted.size(); ++k )
    {
        owners[k] = hopdetail::ownerLeaf( ing, ing.symbols[ wanted[k].to ], memberOwners );
    }
    // a candidate's rank: an arity misfit last, then a call qualified by the callee's owner first; ties go to file/line order
    struct Cand
    {
        std::uint32_t file, line, byte, ref;
        std::uint8_t  rank;   // bit 1: the arity misfits, bit 0: no owner qualifier
    };
    std::vector<std::vector<Cand>> cands( wanted.size() );
    ++out.referenceScans;   // (2)
    for( std::uint32_t refIndex = 0; refIndex < ing.references.size(); ++refIndex )
    {
        const Reference& r = ing.references[ refIndex ];
        if( r.fromSymbol >= callerSel.size() || !callerSel[ r.fromSymbol ] )
        {
            continue;   // the cheap caller-bit test first: it rejects nearly every reference of a large index
        }
        // a macro invocation is a hop the graph prints too (viamacro -> WRAP): its site is the invocation, same filter otherwise
        if( !callSiteCounts( r, refIndex, g.keptForwards, /*macroToo=*/true ) )
        {
            continue;
        }
        const auto lo = std::lower_bound( wanted.begin(), wanted.end(), r.fromSymbol, []( const HopWant& w, NodeId f ) { return w.from < f; } );
        for( auto it = lo; it != wanted.end() && it->from == r.fromSymbol; ++it )
        {
            const std::size_t k = std::size_t( it - wanted.begin() );
            if( !tests[k].reaches( r ) )
            {
                continue;
            }
            const std::string_view owner      = owners[k];
            const bool             ownerMatch = !owner.empty() && ( r.qualifier == owner || r.recvVar == owner || r.memberRoot == owner );
            cands[k].push_back( { r.fileId, r.line, r.startByte, refIndex, std::uint8_t( ( fits( k, r ) ? 0 : 2 ) | ( ownerMatch ? 0 : 1 ) ) } );
        }
    }
    for( std::size_t k = 0; k < wanted.size(); ++k )   // (3) the pick, then the files the text slices read, each once
    {
        std::vector<Cand>& c = cands[k];
        std::sort( c.begin(), c.end(), []( const Cand& a, const Cand& b ) { return std::tie( a.rank, a.file, a.line, a.byte, a.ref ) < std::tie( b.rank, b.file, b.line, b.byte, b.ref ); } );
        if( !c.empty() )
        {
            out.recs[k].ref = c.front().ref;
            // the lines tied with the pick (its rank, another line): two calls on one line are one site (sites_at='s rule)
            std::size_t tiedLines = 1;
            for( std::size_t i = 1; i < c.size() && c[i].rank == c.front().rank; ++i )
            {
                tiedLines += c[i].file != c[ i - 1 ].file || c[i].line != c[ i - 1 ].line ? 1 : 0;
            }
            // a tie misleads only when the caller has another edge to a callee of the same name (A::get beside B::get): with
            // one such callee every tied line calls it, as far as the graph knows, so the first is as good as any
            bool namesake = false;
            if( tiedLines > 1 && wanted[k].from + 1 < g.outOff.size() )
            {
                const std::string_view leaf = hopdetail::leafName( ing.symbols[ wanted[k].to ] );
                for( std::uint32_t e = g.outOff[ wanted[k].from ]; e < g.outOff[ wanted[k].from + 1 ] && !namesake; ++e )
                {
                    namesake = g.outTargets[e] != wanted[k].to && hopdetail::leafName( ing.symbols[ g.outTargets[e] ] ) == leaf;
                }
            }
            out.recs[k].siteBy = ( c.front().rank & 2 ) != 0 ? HopSiteBy::NoFit : namesake ? HopSiteBy::Tie : HopSiteBy::Decided;
        }
        if( wanted[k].pinRef != kHopNoRef && wanted[k].pinRef < ing.references.size() )
        {
            out.recs[k].ref    = wanted[k].pinRef;   // the declined call that supplied the row's cands= (CodeRabbit #612): never another line's
            out.recs[k].siteBy = HopSiteBy::Decided;
        }
        std::sort( c.begin(), c.end(), []( const Cand& a, const Cand& b ) { return std::tie( a.file, a.line ) < std::tie( b.file, b.line ); } );
        out.recs[k].nSites = std::max<std::uint32_t>( std::uint32_t( std::unique( c.begin(), c.end(), []( const Cand& a, const Cand& b ) { return a.file == b.file && a.line == b.line; } ) - c.begin() ),
                                                      out.recs[k].ref != kHopNoRef ? 1u : 0u );   // a pinned call the name scan missed (Ruby `new`) is one site
        if( out.recs[k].ref != kHopNoRef )   // a site-only hop reads its site's file too: a stale line is withheld, never printed
        {
            (void)files.text( ing.references[ out.recs[k].ref ].fileId );
        }
        if( out.recs[k].full )
        {
            (void)files.text( ing.symbols[ wanted[k].to ].fileId );
        }
    }
    out.filesRead = files.filesRead();
    for( HopRecord& rec : out.recs )   // (4)
    {
        // the stored line of a file whose length changed no longer names the call (CodeRabbit #535): no site=, counted unread
        rec.siteStale = rec.ref != kHopNoRef && files.stale( ing.references[ rec.ref ].fileId );
        if( rec.full )
        {
            const Symbol& callee = ing.symbols[ rec.to ];
            // sig= prints for every full edge, a site or not (the review's S3): the agent's read of the callee does not depend on the call
            const hopdetail::CallText st = hopdetail::calleeSig( files, callee, redact != nullptr ? &rec.sigRx : nullptr );
            rec.sig    = st.text;
            rec.sigGap = st.gap;
            if( rec.ref != kHopNoRef )
            {
                const hopdetail::CallText ct = hopdetail::callText( files, ing.references[ rec.ref ], hopdetail::leafName( callee ), ing.symbols[ rec.from ],
                                                                    redact != nullptr ? &rec.callRx : nullptr );
                rec.call    = ct.text;
                rec.callGap = ct.gap;
            }
            if( !deferRedactTally )   // a text withheld (hop_redacted=, hop_notext=) prints no redaction to count
            {
                addRedactions( redact, rec.call.empty() ? RedactCounts{} : rec.callRx );
                addRedactions( redact, rec.sig.empty() ? RedactCounts{} : rec.sigRx );
            }
        }
        out.add( rec );
    }
    if( std::getenv( "RIPWIRE_HOP_STATS" ) != nullptr )
    {
        emitTo( stderr, "ripwire: hop facts: edges={} reference_scans={} files_read={}\n", out.recs.size(), out.referenceScans, out.filesRead );
    }
    return out;
}

// THE renderer: one hop's attributes at a shed level. `withSig` false when the answer already prints the callee's
// signature on another row (a --connect join <s sig=>, an earlier <e> to the same callee).
inline std::string hopAttrsXml( const IngestResult& ing, const HopRecord& rec, HopShed shed, bool withSig, bool singleRoot, std::string_view rootPrefix )
{
    if( shed == HopShed::Off )
    {
        return {};
    }
    std::vector<char> esc;
    std::string       out;
    if( rec.ref != kHopNoRef && !rec.siteStale )   // no site (hop_nosite=, or a stale line: hop_unread=): the row still carries sig= in full
    {
        const Reference&       r  = ing.references[ rec.ref ];
        const std::string_view rp = singleRoot ? sarif::rootRelativeUri( ing.files[ r.fileId ], rootPrefix ) : std::string_view( ing.files[ r.fileId ] );
        out = " site=\"" + std::string( escapeXml( rp, esc ) ) + ":" + std::to_string( r.line ) + "\"";
        if( rec.nSites > 1 )
        {
            out += " sites=\"" + std::to_string( rec.nSites ) + "\"";
        }
        if( rec.siteBy != HopSiteBy::Decided )
        {
            out += rec.siteBy == HopSiteBy::Tie ? " site_by=\"first\"" : " site_by=\"nofit\"";
        }
    }
    if( shed < HopShed::SiteOnly && !rec.call.empty() )
    {
        out += " call=\"" + std::string( escapeXml( rec.call, esc ) ) + "\"";
    }
    if( shed < HopShed::NoSig && withSig && !rec.sig.empty() )
    {
        out += " sig=\"" + std::string( escapeXml( rec.sig, esc ) ) + "\"";
    }
    return out;
}

// --connect: the callee sigs a group already shows (its join rows' sig=, when sigs print), sorted for hopEdgeXml's lookup.
inline std::vector<NodeId> hopSigShown( std::span<const NodeId> joins, bool withSigs )
{
    std::vector<NodeId> shown;
    if( withSigs )
    {
        shown.assign( joins.begin(), joins.end() );
        std::sort( shown.begin(), shown.end() );   // a leg-dropped union need not list its joins in id order
    }
    return shown;
}

// --connect: rows that would read alike (homeassistant-08: f="get" t="async_handle" twice) print the definitions they join.
// One sort of the rows by printed names, one scan per run of alike rows. Bit 1 = fp= (the froms differ), bit 2 = tp=.
template <class Edge>
std::vector<std::uint8_t> hopAlikeRows( const IngestResult& ing, std::span<const Edge> edges )
{
    std::vector<std::uint8_t> need( edges.size(), 0 );
    std::vector<std::size_t>  byName( edges.size() );
    for( std::size_t k = 0; k < edges.size(); ++k )
    {
        byName[k] = k;
    }
    const auto names = [ & ]( std::size_t k ) { return std::pair<std::string_view, std::string_view>( ing.symbols[ edges[k].from ].name, ing.symbols[ edges[k].to ].name ); };
    std::sort( byName.begin(), byName.end(), [ & ]( std::size_t a, std::size_t b ) { return names( a ) != names( b ) ? names( a ) < names( b ) : a < b; } );
    for( std::size_t lo = 0, hi = 0; lo < byName.size(); lo = hi )
    {
        hi = lo + 1;
        bool fromsDiffer = false, tosDiffer = false;
        for( ; hi < byName.size() && names( byName[hi] ) == names( byName[lo] ); ++hi )
        {
            fromsDiffer = fromsDiffer || edges[ byName[hi] ].from != edges[ byName[lo] ].from;
            tosDiffer   = tosDiffer || edges[ byName[hi] ].to != edges[ byName[lo] ].to;
        }
        for( std::size_t k = lo; k < hi && hi - lo > 1; ++k )
        {
            need[ byName[k] ] = std::uint8_t( ( fromsDiffer ? 1 : 0 ) | ( tosDiffer ? 2 : 0 ) );
        }
    }
    return need;
}

// --connect: one <e> row's hop attributes — fp=/tp= when it reads alike, then site=/call=/sig= at the shed level, the callee's
// sig= once per group (`sigShown` grows as rows print it). `endpointRows` is set when fp=/tp= printed (its legend clause rides).
// `redact` (hopFacts ran with deferRedactTally): the redactions inside the call=/sig= this row prints are added to it here, and
// `shown` (when given) tallies the row's hop for the root disclosures of what this pass printed.
inline std::string hopEdgeXml( const IngestResult& ing, const HopFacts& hops, NodeId from, NodeId to, std::uint8_t alike, HopShed shed,
                               std::vector<NodeId>& sigShown, bool singleRoot, std::string_view rootPrefix, bool& endpointRows,
                               RedactCounts* redact = nullptr, HopTally* shown = nullptr, std::vector<char>* shownMark = nullptr )
{
    std::string out;
    if( !hops.on )
    {
        return out;
    }
    std::vector<char> esc;
    const auto        defAt = [ & ]( const char* key, NodeId n )
    {
        const Symbol&          s  = ing.symbols[n];
        const std::string_view rp = singleRoot ? sarif::rootRelativeUri( ing.files[ s.fileId ], rootPrefix ) : std::string_view( ing.files[ s.fileId ] );
        out.append( key ).append( std::string( escapeXml( rp, esc ) ) ).append( ":" ).append( std::to_string( s.line ) ).append( "\"" );
    };
    if( ( alike & 1 ) != 0 ) { defAt( " fp=\"", from ); }
    if( ( alike & 2 ) != 0 ) { defAt( " tp=\"", to ); }
    endpointRows = endpointRows || alike != 0;
    if( const HopRecord* rec = hops.find( from, to ) )
    {
        const auto at      = std::lower_bound( sigShown.begin(), sigShown.end(), to );
        const bool withSig = at == sigShown.end() || *at != to;
        out += hopAttrsXml( ing, *rec, shed, withSig, singleRoot, rootPrefix );
        if( shed < HopShed::SiteOnly && !rec->call.empty() )
        {
            addRedactions( redact, rec->callRx );
        }
        if( withSig && shed == HopShed::Full && !rec->sig.empty() )
        {
            sigShown.insert( at, to );
            addRedactions( redact, rec->sigRx );
        }
        if( shown != nullptr && shownMark != nullptr )   // an edge printed in two groups is one hop, as in hopFacts' own tally
        {
            char& seen = ( *shownMark )[ std::size_t( rec - hops.recs.data() ) ];
            if( seen == 0 )
            {
                seen = 1;
                shown->add( *rec );
            }
        }
    }
    return out;
}

// --connect --max-tokens: advance the hop shed one step (sig=, then call=, then site=); false when nothing is left to shed.
// The hop attributes take their own allowance and never displace what the answer printed before them (COMMON no-displacement).
inline bool hopShedNext( const HopFacts& hops, HopShed& shed ) noexcept
{
    if( hops.on && shed < HopShed::SiteOnly && ( hops.anyCall || hops.anySig ) )
    {
        shed = shed == HopShed::Full ? HopShed::NoSig : HopShed::SiteOnly;
        return true;
    }
    if( hops.on && shed != HopShed::Off && hops.anySite )
    {
        shed = HopShed::Off;
        return true;
    }
    return false;
}

// The root's disclosures, present-only: hops with no site, texts withheld, and the shed level a budget reached.
inline std::string hopRootAttrsXml( const HopTally& f, HopShed shed = HopShed::Full )
{
    if( !f.on )
    {
        return {};
    }
    if( shed == HopShed::Off )   // over the hops printed: a pass that printed none shed nothing from the answer
    {
        return f.anySite || f.anyCall || f.anySig ? " hop_shed=\"sig,call,site\"" : std::string();
    }
    std::string out;
    if( f.nosite > 0 ) { out += " hop_nosite=\"" + std::to_string( f.nosite ) + "\""; }
    if( f.unread > 0 ) { out += " hop_unread=\"" + std::to_string( f.unread ) + "\""; }
    if( f.notext > 0 ) { out += " hop_notext=\"" + std::to_string( f.notext ) + "\""; }
    if( f.redacted > 0 ) { out += " hop_redacted=\"" + std::to_string( f.redacted ) + "\""; }
    if( shed != HopShed::Full && ( f.anyCall || f.anySig ) )
    {
        out += shed == HopShed::NoSig ? " hop_shed=\"sig\"" : " hop_shed=\"sig,call\"";
    }
    return out;
}

// The full dialect's clause (present-only, no "--": it rides inside the verb's own comment). `row` names the element.
inline std::string hopLegend( const HopTally& f, std::string_view row, HopShed shed = HopShed::Full, bool endpointRows = false )
{
    if( !f.on )
    {
        return {};
    }
    std::string out;
    const std::string r( row );
    if( shed == HopShed::Off )   // the fp=/tp= rows still print (they are not shed): their clause stays (CodeRabbit #535)
    {
        return ( f.anySite || f.anyCall || f.anySig ? std::string( "hop_shed=: hop attributes max_tokens shed first (sig, call, site). " ) : std::string() )
               + ( endpointRows ? r + " fp=/tp=: the from/to definition, printed when two rows of a group would read alike. " : std::string() );
    }
    if( f.anySite )
    {
        out += r + " site=file:line: a call (or macro invocation) in the hop's caller whose callee name is this hop's callee (one whose argument count the callee accepts first, then one whose written owner is the callee's, then file order); "
               "matched by name, not proof that this call is the one the edge binds. ";
    }
    if( f.anySites )
    {
        out += r + " sites=N: the caller calls that name on N lines; site= is one of them. ";
    }
    if( f.anyTie )
    {
        out += r + " site_by=first: the caller also calls another callee of that name and several lines fit equally (written owner, argument count); site= is the first, not a guess. ";
    }
    if( f.anyNoFit )
    {
        out += r + " site_by=nofit: no such line passes an argument count the callee accepts; site= is the first name match. ";
    }
    if( f.anyCall && shed < HopShed::SiteOnly )
    {
        out += r + " call=: that call's text from its line start (past the caller's own head on a one-line caller), whitespace collapsed, joined up to 3 lines while its parentheses are open, at most 120 bytes (U+2026 marks either cut). ";
    }
    if( f.anySig && shed < HopShed::NoSig )
    {
        out += r + " sig=: the callee's declaration signature, cut at 160 bytes. ";
    }
    if( endpointRows )
    {
        out += r + " fp=/tp=: the from/to definition, printed when two rows of a group would read alike. ";
    }
    if( f.nosite > 0 )
    {
        out += "hop_nosite=N: N hops whose caller has no call naming the callee (an inherit, impl or link edge, an alias, a constructor), so no site=. ";
    }
    if( f.unread > 0 )
    {
        out += "hop_unread=N: call= or sig= withheld on N hops: the file could not be read or its length changed since indexing (then site= too). ";
    }
    if( f.notext > 0 )
    {
        out += "hop_notext=N: call= withheld on N hops whose site text does not spell the callee (a macro-expanded or generated call). ";
    }
    if( f.redacted > 0 )
    {
        out += "hop_redacted=N: call= withheld on N hops whose callee name sits in or against a redacted credential. ";
    }
    if( shed != HopShed::Full && ( f.anyCall || f.anySig ) )
    {
        out += "hop_shed=: hop attributes max_tokens shed first (sig, call, site). ";
    }
    return out;
}

}   // namespace rw
