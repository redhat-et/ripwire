#pragma once
// forbodyptr.h — THE POINTER FORM of a `--for` answer's first page (lane NB1, owner ruling 162 "flag + live check", 2026-11-21):
// every body the page would carry is the <skip> row that names it instead, and the page ends at the row it ended at.
//
// WHY. A delivered body is carried by every later request of the session (GR1 §2.1: a median 29 post-answer requests to the hand-back),
// while the one request it can save is a ranged Read the agent makes anyway (GR1 §4: 4 of 4 sessions whose first gold edit fell inside a
// delivered body Read the file first). NA1 §6.2 simulated the shape on GA1 DEV (n=89, page 1): every rung but BODY held at 0 down, and a
// median 952 B left page 1. Whether that lowers a WHOLE SESSION's tokens is the question a live check answers, so the form ships behind
// --bodies=pointer (forbodiesform.h), the inline default untouched, until that check reports.
//
// WHAT. On the first page an answer-first --for answer serves (page 1, the early page 1, or the whole answer when it is one page),
// each <b …>…</b> element outside CDATA and comments — a fold body, a slice member, a followed delegate, a key body — becomes
//     <skip p= n= l= e= bytes= [follow_of=] next="--expand=P:LINE:NAME"/>
// the row forfold.h's skipRow already writes for a body that did not fit, with e= added: l..e are the SOURCE lines the body spans
// (its first line is the declaration's, a decorator or `export` included, servedBodyStart; e= is ER1's defEndLine, absent when the
// extent is unknown — never a guess), bytes= its source size, next= the call that serves it. Every skip row already on the page is
// rewritten the same way, so each pointer on it reads alike (its l= may move UP to the declaration's first line). A body whose symbol
// cannot be found again keeps its row's own p= n= l= with no e= (unknown, not guessed).
// WHERE THE PAGE ENDS. The rewrite runs AFTER paging (verbs_for.h runForLens), on the bytes about to be written: the pager has cut
// page 1 with the bodies in it, so page 1 ends at the row it ended at and the freed bytes are NOT refilled by later rows (NA1 §3: with
// bodies simply switched off, the tail refills them and the page shrinks 3.7 %). Later pages are not touched: each is the same window
// onto the same document as before.
// NOT HERE (each keeps its bodies): a ROUTED answer (verbs_forroute.h) — its key body is the definition of the symbol the question
// names, the call-graph verb's own rows are call sites, and RL1 fitted its carried page with the bodies in it; --expand, --pack-task,
// MCP `for`; a --token-budget answer (the fit priced the bytes); --legend=first; a non-XML format.
// DISCLOSURE. A page the rewrite changed says so on its root (body_form="pointer") and defines the form in one legend comment before
// </ctx> (kBodyPointerClause). A page with no <b> is byte-identical to the inline form and says nothing (its skip rows are left as
// they are: rewriting them alone would only add bytes).
// est_tokens= is re-priced over the bytes served (forpages.h pricePage).
// Gate: test/bodypointercheck.sh.

#include "clones.h"            // readCloneSourceFile — a file's bytes by fileId through the one disk-path seam
#include "foranswerfirst.h"    // rootBody — the root's open-tag end and its </ctx>
#include "forbodiesform.h"     // bodyPointersOn — the switch
#include "forpages.h"          // detail::pricePage — est_tokens= prices the page as served
#include "forrowlines.h"       // readOpenTag, unescaped — the one strict open-tag reader of a --for answer
#include "model.h"
#include "nextverb.h"          // nextFlag, appendNextValueXml — the one next= spelling
#include "serialize.h"         // lensRowPath (p= as every --for row prints it), defEndLine, lineBreaksOf, servedBodyStart, extractedTextOfUnit

#include <algorithm>
#include <cstddef>
#include <cstdint>
#include <optional>
#include <string>
#include <string_view>
#include <vector>

namespace rw::bodyptr
{

inline constexpr std::string_view kBodyFormAttr = " body_form=\"pointer\"";
// The form's one legend comment. No "--" inside it (an XML comment), so the next= call is described, not spelled.
// Kept short on purpose: it rides every pointer page and is no legend-dictionary entry (an entry moves dictv=, which every
// continuation page and MCP initialize carry, so the inline default would no longer be byte-identical). Measured on GA1 DEV (n=89):
// a 380 B first wording left 11 of the 60 rewritten pages LARGER than inline.
inline constexpr std::string_view kBodyPointerClause =
    "<!-- body_form=pointer: no body text on this page; each body is a skip row in its place: l..e its source lines "
    "(no e=: unknown), bytes= its size, next= serves it; the page ends where it did -->";

struct Applied
{
    std::size_t bodies     = 0;   // <b> elements turned into pointer rows
    std::size_t skips      = 0;   // skip rows already on the page, rewritten with e=
    std::size_t withoutEnd = 0;   // pointer rows with no e= (extent unknown, or the symbol not found again)
};

namespace detail
{
// One file's bytes and line breaks, read once per rewrite (a page names a handful of files).
struct Source
{
    std::uint32_t              fileId = 0;
    bool                       ok     = false;
    std::string                bytes;
    std::vector<std::uint32_t> breaks;
};
// One rewrite: the index, the root p= is printed relative to, the files read so far, and what it changed.
struct Rewrite
{
    const IngestResult& ing;
    std::string_view    rootArg;
    std::vector<Source> cache;
    Applied             applied;
};
inline const Source& sourceOf( Rewrite& job, std::uint32_t fileId )
{
    if( const auto it = std::ranges::find( job.cache, fileId, &Source::fileId ); it != job.cache.end() )
    {
        return *it;
    }
    Source& s = job.cache.emplace_back();
    s.fileId  = fileId;
    s.ok      = readCloneSourceFile( job.ing, fileId, s.bytes );
    s.breaks  = s.ok ? lineBreaksOf( s.bytes ) : std::vector<std::uint32_t>{};
    return s;
}

// The symbol a row names by p= n= l= (values unescaped; p= as lensRowPath prints it), the lowest NodeId when several match; kNoNode when
// none does.
inline NodeId rowSymbol( const Rewrite& job, std::string_view path, std::string_view name, std::uint32_t line )
{
    for( NodeId id = 0; id < job.ing.symbols.size(); ++id )
    {
        const Symbol& s = job.ing.symbols[ id ];
        if( s.line == line && s.name == name && s.fileId < job.ing.files.size() && lensRowPath( job.ing, s.fileId, job.rootArg ) == path )
        {
            return id;
        }
    }
    return kNoNode;
}

// The source lines a body of `s` spans: from the line its served text starts on (servedBodyStart: the declaration, a wrapper prefix
// included) to ER1's e= (0: unknown). A doc unit's offsets are in extracted text, not the file's lines: l= is its own, e= unknown.
struct Lines
{
    std::uint32_t first = 0, last = 0;
};
inline Lines bodyLines( Rewrite& job, const Symbol& s )
{
    if( extractedTextOfUnit( job.ing, s ) != nullptr )
    {
        return { s.line, 0 };
    }
    const Source& f = sourceOf( job, s.fileId );
    if( !f.ok || s.endByte > f.bytes.size() )
    {
        return { s.line, 0 };
    }
    const std::size_t   at    = servedBodyStart( job.ing, s, f.bytes, /*srcIsDocUnit=*/false );
    const std::uint32_t first = std::uint32_t( std::lower_bound( f.breaks.begin(), f.breaks.end(), std::uint32_t( at ) ) - f.breaks.begin() ) + 1u;
    return { first <= s.line ? first : s.line, defEndLine( s, f.breaks, f.bytes.size() ) };
}

// The attributes a pointer row is built from, as the element's open tag spells them (still escaped); absent ones are empty.
struct RowAttrs
{
    std::string_view p, n, l, follow;
    std::string_view unused;   // where every other attribute is read to (one store, no branch)
};
inline constexpr std::pair<std::string_view, std::string_view RowAttrs::*> kRowAttrSlots[] = {
    { "p", &RowAttrs::p }, { "n", &RowAttrs::n }, { "l", &RowAttrs::l }, { "follow_of", &RowAttrs::follow } };
inline RowAttrs rowAttrs( const rowlines::OpenTag& t ) noexcept
{
    RowAttrs r;
    for( const rowlines::Attr& a : t.attrs )
    {
        const auto slot = std::ranges::find( kRowAttrSlots, a.name, &std::pair<std::string_view, std::string_view RowAttrs::*>::first );
        r.*( slot != std::ranges::end( kRowAttrSlots ) ? slot->second : &RowAttrs::unused ) = a.value;
    }
    return r;
}

// The pointer row for the element whose open tag is `t` (a <b> or a <skip>); `bodyBytes` sizes a row whose symbol is not found again.
inline std::string pointerRow( Rewrite& job, const rowlines::OpenTag& t, std::size_t bodyBytes )
{
    const RowAttrs a    = rowAttrs( t );
    std::uint32_t  line = 0;
    for( const char c : a.l )
    {
        line = c >= '0' && c <= '9' ? line * 10u + std::uint32_t( c - '0' ) : line;
    }
    const std::string path = rowlines::unescaped( a.p ), name = rowlines::unescaped( a.n );
    const NodeId      id   = rowSymbol( job, path, name, line );
    Lines             span{ line, 0 };
    std::size_t       bytes = bodyBytes;
    if( id != kNoNode )
    {
        const Symbol& s = job.ing.symbols[ id ];
        span  = bodyLines( job, s );
        bytes = s.endByte - s.sigStartByte;   // the fold skip row's bytes=: the definition's source size
    }
    job.applied.withoutEnd += span.last == 0 ? 1u : 0u;
    std::string x = "<skip p=\"" + std::string( a.p ) + "\" n=\"" + std::string( a.n ) + "\" l=\"" + std::to_string( span.first ) + "\"";
    x += span.last > 0 ? " e=\"" + std::to_string( span.last ) + "\"" : std::string();
    x += " bytes=\"" + std::to_string( bytes ) + "\"";
    x += a.follow.empty() ? std::string() : " follow_of=\"" + std::string( a.follow ) + "\"";
    x += " next=\"";
    appendNextValueXml( x, nextFlag( "--expand=", path + ":" + std::to_string( line ) + ":" + name ) );   // the selector the fold's skip row spells
    x += "\"/>";
    return x;
}

// Where the CDATA section or comment starting at `i` ends (past its terminator; `end` when it is not closed), or 0: none starts there.
inline std::size_t inertEnd( std::string_view v, std::size_t i, std::size_t end ) noexcept
{
    constexpr std::string_view kCdata = "<![CDATA[", kCdataEnd = "]]>", kComment = "<!--", kCommentEnd = "-->";
    const std::string_view at    = v.substr( i );
    const std::string_view close = at.starts_with( kCdata ) ? kCdataEnd : at.starts_with( kComment ) ? kCommentEnd : std::string_view();
    if( close.empty() )
    {
        return 0;
    }
    const std::size_t e = v.find( close, i + kComment.size() );
    return e == std::string_view::npos ? end : e + close.size();
}

// The end of the element whose content starts at `from` (just past its open tag): past its "</b>", CDATA stepped over; npos when none.
inline std::size_t bodyElementEnd( std::string_view v, std::size_t from )
{
    constexpr std::string_view kClose = "</b>";
    for( std::size_t i = v.find( '<', from ); i != std::string_view::npos; i = v.find( '<', i ) )
    {
        if( const std::size_t past = inertEnd( v, i, std::string_view::npos ); past != 0 )
        {
            i = past;
            continue;
        }
        if( v.substr( i ).starts_with( kClose ) )
        {
            return i + kClose.size();
        }
        ++i;
    }
    return std::string_view::npos;
}

// The next <b>…</b> or <skip/> element in [from, end), CDATA and comments stepped over. nullopt: none is left, or a body is not closed
// before `end` (the rest of the page is then served as it is).
struct Element
{
    std::size_t       at = 0, end = 0;
    rowlines::OpenTag tag;
    bool              body = false;
};
enum class Kind
{
    Other,
    Body,   // <b …>, closed by "</b>"
    Skip,   // <skip …/>
};
inline Kind kindOf( const std::optional<rowlines::OpenTag>& t ) noexcept
{
    if( !t )
    {
        return Kind::Other;
    }
    if( t->name == "b" )
    {
        return t->selfClosing ? Kind::Other : Kind::Body;
    }
    return t->name == "skip" && t->selfClosing ? Kind::Skip : Kind::Other;
}
inline std::optional<Element> nextElement( std::string_view v, std::size_t from, std::size_t end )
{
    for( std::size_t i = v.find( '<', from ); i != std::string_view::npos && i < end; i = v.find( '<', i ) )
    {
        if( const std::size_t past = inertEnd( v, i, end ); past != 0 )
        {
            i = past;
            continue;
        }
        std::optional<rowlines::OpenTag> t    = rowlines::readOpenTag( v.substr( i, end - i ) );
        const Kind                       kind = kindOf( t );
        if( t && kind != Kind::Other )   // kindOf( nullopt ) is Other; `t &&` states it where the deref is
        {
            const bool        body  = kind == Kind::Body;
            const std::size_t close = body ? bodyElementEnd( v, i + t->size ) : i + t->size;
            return close > end ? std::nullopt : std::optional<Element>( Element{ i, close, std::move( *t ), body } );   // npos > end
        }
        i += t ? t->size : 1;
    }
    return std::nullopt;
}

// Is this root a continuation page's (page= above 1)? Those are windows onto the inline document and keep their bodies.
[[nodiscard]] inline bool continuationRoot( std::string_view rootOpen ) noexcept
{
    return rootOpen.find( " page=\"" ) != std::string_view::npos && rootOpen.find( " page=\"1\"" ) == std::string_view::npos;
}
}   // namespace detail

// Rewrite `doc` — the bytes of a finished answer-first --for answer's first page — in place to the pointer form. Returns what it changed
// (nothing: the page held no body, or it is not a first page of an answer-first answer, and it is served as it is).
inline Applied pointBodies( std::string& doc, const IngestResult& ing, std::string_view rootArg )
{
    const std::string_view                     view = doc;
    const std::optional<answerfirst::RootBody> rb   = view.starts_with( "<ctx" ) ? answerfirst::rootBody( view ) : std::nullopt;
    if( !rb || detail::continuationRoot( view.substr( 0, rb->openEnd ) ) )
    {
        return {};
    }
    detail::Rewrite job{ ing, rootArg, {}, {} };
    std::string     out;
    out.reserve( doc.size() );
    std::size_t copied = 0;
    for( std::optional<detail::Element> e = detail::nextElement( view, rb->openEnd + 1, rb->closeAt ); e; e = detail::nextElement( view, e->end, rb->closeAt ) )
    {
        out.append( view.substr( copied, e->at - copied ) );
        out += detail::pointerRow( job, e->tag, e->end - e->at );
        ++( e->body ? job.applied.bodies : job.applied.skips );
        copied = e->end;
    }
    if( job.applied.bodies == 0 )
    {
        return {};   // no body on the page: nothing to point at, so the inline page is served as it is (no e= added, no clause)
    }
    out.append( view.substr( copied, rb->closeAt - copied ) );
    out.append( kBodyPointerClause );
    out.append( view.substr( rb->closeAt ) );
    out.insert( rb->openEnd, kBodyFormAttr );   // the root's open tag is untouched above: its '>' is still at openEnd
    doc.swap( out );
    forpages::detail::pricePage( doc );
    return job.applied;
}

}   // namespace rw::bodyptr
