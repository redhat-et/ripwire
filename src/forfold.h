#pragma once
// forfold.h — THE BODY-TAIL FOLD of a compact-route --for answer (lane body-fold, train 31): the whole bodies of its top ranked
// rows, appended after the unchanged answer under a fixed byte budget.
//
// WHY. A conceptual --for question routes to the compact bundle: ranked signatures, one-hop edges, the file tail, no bodies
// (bodies="0" reason="compact-route"). Its own continuation is "--expand the row you want". Measured over the round-5 rows, the
// one follow-up that ever lifted a row without names-only credit was reading one to three of the top ranked bodies; the existing
// knobs that serve bodies (--auto-bodies, --detail=N) REPLACE ranked rows and lost 2-5 complete answers. The fold APPENDS
// instead: every byte before it is the answer without it (RIPWIRE_NO_BODY_FOLD=1), the fold is a fixed stair-step on top of
// the answer's budget_bytes target, never a share of it.
//
// WHAT. The first kForBodyFoldRows ranked <d> rows (rank order) that are not already bodied (the body slot's owner) and have a
// body to slice (never a module scope). Each body is whole or not served: in rank order, a body whose rendered element fits
// what is left of kForBodyFoldBudgetBytes is served; one that does not is listed as <skip p= n= l= bytes= next="--expand=…">,
// the call that serves it, and the walk goes on to the next row (a later, smaller body can still fit). A body here is the
// --expand body element (<b t= l= p= n=> with its CDATA) WITHOUT the --expand file context (sibs=, inc=), WITHOUT the row's field
// note (it rides on the <d> row already: one note, once) and WITHOUT callee <calls> rows: the one-hop edges are the answer's <hops>, and the next-hop false adds a reader drew from callee rows of
// expanded bodies were the measured risk (dn-compound F2). The bodies are by rank, not a claim they are the answer.
// THE MEMBER SLICE (owner-approved variant V1, the STEP-0 pick): a CLASS/struct/interface row whose whole body does not fit what is
// left is not just skipped — its constructor (constructor, __init__, ctor, initialize, init, new, or the class's own name) and every
// member whose name, or body text past its signature (never the receiver or parameter names), holds a question word (the query's
// subtokens less the stopword lists) are served, each whole or not at all, in source order, inside <slice p= n= l= members= of=>, and the class itself is still the <skip> that names the whole body.
// A member is the parser's (isParsedMemberOf: its scope names the class, or the class's span holds it), never one nested in another
// member (that text is already inside the outer member). Each text rides once: a ranked row inside a body the fold already serves
// is counted as served, and a ranked body holding served ranked bodies replaces them. Measured on the 53 round-5 --for rows: +1 Rule-C row over the plain fold
// (koa-02: the Application slice), 0 lost, +0.8 KB median.
// Funding: the DEFAULT regime only — an explicit --token-budget is a size the caller named, and the fold does not ride there
// (that answer is byte-identical to before); --json, --signatures-only, --detail=N, --auto-bodies and the name-exact route
// (which already serves the anchor's body) carry none either.
// RIPWIRE_NO_BODY_FOLD (any value) turns the fold off — the A/B handle, the RIPWIRE_NO_BODY_SLOT precedent.

#include "commentcoherence.h"   // isCommentStopword — the member slice's question words
#include "hopbody.h"    // WRAPPER-FOLLOW: thinDelegate, renderBodyElement — a thin wrapper's callee body
#include "memberowner.h"   // followOfName: the wrapper named as its row names it (Owner.name)
#include "forowner.h"   // isParsedMemberOf — a class's members BY THE PARSER (the body slot's member reading)
#include "lexical.h"    // subtokens, isRouteStopword, lexicalScanText — a sliced class's member text, read as the index read it
#include "model.h"
#include "nextverb.h"   // nextFlag
#include "receiverevidence.h"   // ReceiverEvidence::classLike — the one class/struct/interface kind test
#include "infra/sortutil.h"
#include "serialize.h"  // packBodies, chargeSection, redactTakeBack, tokensForEmittedBytes

#include <algorithm>
#include <cstddef>
#include <cstdint>
#include <cstdlib>
#include <iterator>
#include <optional>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

namespace rw
{

// The fold's byte budget: the served body elements' bytes (markup and CDATA), never the envelope or the skip rows. A fixed step
// on top of the answer (owner, 2026-10-17: 4 KB). A content cap with a disclosed, recoverable cut: every body it leaves out is a
// <skip> row naming the call that serves it.
inline constexpr std::size_t kForBodyFoldBudgetBytes = 4000;
// How many ranked rows the fold considers (served or skipped): the top three (dn-compound C1, measured at 1 / 3 rows).
inline constexpr std::size_t kForBodyFoldRows = 3;

// The A/B switch: the fold rides unless RIPWIRE_NO_BODY_FOLD is set. The caller adds the posture (compact route, XML, default regime).
inline bool forBodyFoldOn()
{
    return std::getenv( "RIPWIRE_NO_BODY_FOLD" ) == nullptr;
}

// The candidates: the first kForBodyFoldRows rows of the ranked head (rank order; the first `headRows` entries of the surface
// with a positive score, the rows <sigs> prints) that are not `bodied` (the body slot's owner, already served whole) and have a
// span to slice (a module scope is bodyless by construction).
inline std::vector<NodeId> forBodyFoldCandidates( const IngestResult& ing, const std::vector<NodeId>& lensSurfaceIds, const std::vector<float>& lensRank,
                                                  std::size_t headRows, NodeId bodied )
{
    std::vector<NodeId> out;
    for( std::size_t i = 0; i < lensSurfaceIds.size() && i < headRows && out.size() < kForBodyFoldRows; ++i )
    {
        const NodeId id = lensSurfaceIds[i];
        if( id >= ing.symbols.size() || id >= lensRank.size() || lensRank[id] <= 0.0f || id == bodied )
        {
            continue;
        }
        const Symbol& s = ing.symbols[id];
        if( s.kind == SymKind::ModuleScope || s.endByte <= s.sigStartByte )
        {
            continue;
        }
        out.push_back( id );
    }
    return out;
}

// The fold's legend clauses, present-only beside the element: the full dialect's, and the compact dialect's (the default posture, so it
// is the one most answers carry: the same readings, terse). Both start "; fold kind=bodies:" and end at the sigs_next= reading. No "--":
// they ride inside an XML comment.
inline constexpr std::string_view kForBodyFoldLegend =
    "; fold kind=bodies: whole bodies of the top ranked rows not already bodied, by rank, not a claim they are the answer "
    "(b t= n= p= l=, no sibs= or calls); served= of total=, each whole within budget_bytes=, on top of the unchanged answer; "
    "slice/skip p= n= l= name the row; slice members= of=: a class too big for the rest, its constructor and question-word "
    "members; skip bytes= its source size, next= serves it; a skipped body makes sigs next= the first skip, sigs_next= the "
    "signatures-only re-call";
// FIX1 B2: the compact clause defines the <b> it carries (b t= n= p= l=) itself — the compact route's hops clause does not, and
// the slot's clause rides only beside the slot — and the p= n= l= of its slice and skip rows; terse (compact 286 B, full 496 B).
inline constexpr std::string_view kForCompactBodyFoldLegend =
    "; fold kind=bodies: b t= n= p= l= top ranked rows' whole bodies, not the answer; served= of total= in budget_bytes=; "
    "slice/skip p= n= l=; slice members= of=: a big class's ctor, question-word members; skip bytes= next=; "
    "a skip makes sigs next= it, sigs_next= the signatures-only re-call";
// WRAPPER-FOLLOW: present-only beside a <b follow_of=> (BodyFoldRender::follows > 0), after the fold clause. No "--".
inline constexpr std::string_view kForFoldFollowLegend =
    "; b follow_of=W: the body of the one call W makes, W a thin wrapper served just before it (a function whose text holds one call "
    "site, a proven call, at most 3 statement lines), followed at most 2 levels and 3 bodies; outside budget_bytes=, whole up to 4000 "
    "bytes; follow_cut n= next=: n wrappers past the 3 whose callee was not followed, next= the first one's expand";
inline constexpr std::string_view kForCompactFoldFollowLegend =
    "; b follow_of=W: body of the one call thin wrapper W (one call site, <=3 lines) makes, <=2 levels, <=3 bodies, past budget_bytes=, "
    "whole to 4000 B; follow_cut n= next=: wrappers not followed past 3";
static_assert( kHopBodyCapBytes == 4000 && kWrapperFollowDepth == 2 && kThinBodyLines == 3 && kWrapperFollowMax == 3,
               "the follow clauses spell the bounds: re-word them with the knobs" );
static_assert( kForCompactBodyFoldLegend.find( "b t= n= p= l=" ) != std::string_view::npos
                   && kForBodyFoldLegend.find( "b t= n= p= l=" ) != std::string_view::npos,
               "both fold clauses define the <b> element the fold carries (FIX1 B2)" );

struct BodyFoldInputs
{
    const IngestResult&     ing;
    std::string_view        task;         // the question: the member slice's words
    NodeId                  bodied;       // the body slot's owner (kNoNode: none) — already served, never repeated
    const std::vector<float>& lensRank;   // orders nothing here (no <calls>); threaded so a body renders as every --for body
    std::string_view        rootArg;
    RedactCounts*           redact;       // no NoteIndex: a ranked row's note rides on its <d> row once, never again in the fold
    bool                    compress;     // --compress (the CLI only)
    const Graph*            g = nullptr;  // WRAPPER-FOLLOW (hopbody.h thinDelegate): nullptr = no body is followed
};

struct BodyFoldRender
{
    std::string xml;                 // <fold …>…</fold>; empty when nothing rides (no candidate, or a render buffer failed)
    std::size_t bodyTokens  = 0;     // the served body elements, at the body rate
    std::size_t markupBytes = 0;     // the envelope and the skip rows, priced with the rest of the markup
    std::size_t served      = 0;
    std::size_t total       = 0;
    std::size_t slices = 0;   // classes served as a member slice (each also has its skip row)
    std::size_t follows = 0;  // WRAPPER-FOLLOW: delegate bodies served after the thin wrapper that calls them (<b follow_of=>)
    std::string firstSkipNext;       // the first skip's next= value, XML-escaped; empty when every candidate was served
    std::vector<NodeId> bodies;      // member-names: every body this answer carries whole (the slot's owner, the fold's, slice members)
    std::vector<NodeId> sliced;      // member-names: the classes served as a member slice
};

namespace fold_detail
{
// the member slice's question words: the query's subtokens (the BM25 split), less the general-English and route stopwords, deduped
inline std::vector<std::string> sliceWords( std::string_view task )
{
    std::vector<std::string> toks;
    subtokens( task, toks );
    std::vector<std::string> out;
    for( std::string& t : toks )
    {
        if( !isCommentStopword( t ) && !isRouteStopword( t ) && std::find( out.begin(), out.end(), t ) == out.end() )
        {
            out.push_back( std::move( t ) );
        }
    }
    return out;
}
// a constructor by name: the languages' spellings (Python __init__, JS/TS constructor, Ruby initialize, Swift/ObjC init, Rust new,
// a C# ctor) as DATA rows, or the class's own name (C++, Java, C#)
inline constexpr std::string_view kFoldCtorNames[] = { "__init__", "constructor", "ctor", "init", "initialize", "new" };
static_assert( std::ranges::is_sorted( kFoldCtorNames, rw::sortutil::svLess ), "kFoldCtorNames is binary-searched: keep it sorted" );
inline bool isConstructorName( std::string_view member, std::string_view cls ) noexcept
{
    return member == cls || std::ranges::binary_search( kFoldCtorNames, member, rw::sortutil::svLess );
}
// does `text` (a member's name, or its body) carry one of `words` as a subtoken
inline bool holdsWord( std::string_view text, const std::vector<std::string>& words )
{
    std::vector<std::string> toks;
    subtokens( text, toks );
    return std::ranges::any_of( toks, [ & ]( const std::string& t ) { return std::ranges::find( words, t ) != words.end(); } );
}
// One body through packBodies (the --expand body shape, no callee rows: the empty CSR has no out-edge for any id), unwrapped from
// its <bodies> envelope: the legend comments packBodies writes ahead of the envelope (an extent-suspect body's reading) stay in
// front of the <b>. nullopt when the buffer failed or the span rendered nothing.
inline std::optional<std::string> renderOneBody( const BodyFoldInputs& in, NodeId id )
{
    return renderBodyElement( in.ing, id, /*capBytes=*/0, in.compress, in.redact, in.rootArg, &in.lensRank );
}

inline std::string skipRow( const BodyFoldInputs& in, NodeId id, std::string& escapedNext )
{
    const Symbol&     s          = in.ing.symbols[id];
    const std::string rootPrefix = in.rootArg.empty() ? std::string() : rw::sarif::rootPrefixOf( in.rootArg );
    const std::string path       = in.rootArg.empty() ? std::string( in.ing.files[s.fileId] )
                                                      : std::string( rw::sarif::rootRelativeUri( in.ing.files[s.fileId], rootPrefix ) );
    std::vector<char> esc;
    escapedNext = std::string( escapeXml( nextFlag( "--expand=", path + ":" + std::to_string( s.line ) + ":" + s.name ), esc ) );
    std::string x = "<skip p=\"";
    x += escapeXml( path, esc );
    x += "\" n=\"";
    x += escapeXml( s.name, esc );
    x += "\" l=\"" + std::to_string( s.line ) + "\" bytes=\"" + std::to_string( s.endByte - s.sigStartByte ) + "\" next=\"";
    x += escapedNext;
    x += "\"/>";
    return x;
}

// spanInside / overlapsServed (each text once, FIX1 N2) live in hopbody.h, the one containment reading the fold, its follows and the
// path hop bodies share.

// a class's direct members by the parser (isParsedMemberOf), in source order; one nested in another member is inside that
// member's text, so it is not a member of its own
inline std::vector<NodeId> sliceMembers( const IngestResult& ing, const Symbol& c )
{
    std::vector<NodeId> members;
    for( NodeId m = 0; m < ing.symbols.size(); ++m )
    {
        const Symbol& ms = ing.symbols[m];
        if( ms.kind != SymKind::ModuleScope && ms.endByte > ms.sigStartByte && isParsedMemberOf( ms, c ) )
        {
            members.push_back( m );
        }
    }
    std::erase_if( members, [ & ]( NodeId a ) { return std::ranges::any_of( members, [ & ]( NodeId b ) { return spanInside( ing, a, b ); } ); } );
    std::ranges::sort( members, [ & ]( NodeId a, NodeId b )
    {
        const Symbol& x = ing.symbols[a];
        const Symbol& y = ing.symbols[b];
        return x.fileId != y.fileId ? x.fileId < y.fileId : ( x.sigStartByte != y.sigStartByte ? x.sigStartByte < y.sigStartByte : a < b );
    } );
    return members;
}

// the slice's picks: the constructor first, then every member whose name, or whose body PAST ITS SIGNATURE, holds a question word.
// Past the signature (FIX1 N3): a Go method's receiver (s *Scheduler) and a member's parameter names are written on its declaration
// line, so a question naming the class no longer matches every method (a parameter list wrapped onto later lines still reads as
// body: no per-language signature grammar here). The text is the one the index scanned (lexicalScanText), one read
// per file (a C++ out-of-line member lives in another file than its class).
inline std::vector<NodeId> slicePicks( const IngestResult& ing, const std::vector<NodeId>& members, std::string_view cls,
                                       const std::vector<std::string>& words )
{
    std::vector<std::pair<std::uint32_t, std::string>> files;
    const auto bodyOf = [ & ]( const Symbol& ms ) -> std::string_view
    {
        auto it = std::ranges::find_if( files, [ & ]( const auto& f ) { return f.first == ms.fileId; } );
        if( it == files.end() )
        {
            std::string scratch;
            const std::string* text = lexicalScanText( ing, ms.fileId, scratch );
            files.emplace_back( ms.fileId, text == &scratch ? std::move( scratch ) : *text );
            it = files.end() - 1;
        }
        const std::string& src = it->second;
        if( ms.endByte > src.size() || ms.sigStartByte >= ms.endByte )
        {
            return {};
        }
        // the body starts at the parser's body start or the end of the declaration's first line, whichever is first: a Python
        // block starts at its first statement, so a leading comment line would otherwise read as signature
        const std::size_t eol  = src.find( '\n', ms.sigStartByte );
        const std::size_t from = std::min<std::size_t>( { std::max( ms.sigStartByte, ms.sigEndByte ), eol, ms.endByte } );
        return std::string_view( src ).substr( from, ms.endByte - from );
    };
    std::vector<NodeId> chosen;
    std::ranges::copy_if( members, std::back_inserter( chosen ), [ & ]( NodeId m ) { return isConstructorName( ing.symbols[m].name, cls ); } );
    std::ranges::copy_if( members, std::back_inserter( chosen ), [ & ]( NodeId m )
    {
        const Symbol& ms = ing.symbols[m];
        return !isConstructorName( ms.name, cls ) && ( holdsWord( ms.name, words ) || holdsWord( bodyOf( ms ), words ) );
    } );
    return chosen;
}

// THE MEMBER SLICE of one class row that did not fit: its picks (slicePicks), each whole within `room` bytes (a member that does not
// fit what is left is passed over, the walk goes on), emitted in source order. Empty xml when no member fits (the class's skip row
// alone then stands for it).
struct SliceRender
{
    std::string xml;
    std::size_t bodyBytes = 0;   // the served member elements' bytes (charged to the fold budget)
};
inline SliceRender renderSlice( const BodyFoldInputs& in, NodeId clsId, const std::vector<std::string>& words, std::size_t room,
                                std::vector<NodeId>& served )   // in: the bodies the fold (and the slot) already carry; out: + this slice's
{
    SliceRender               out;
    const Symbol&             c       = in.ing.symbols[clsId];
    const std::vector<NodeId> members = sliceMembers( in.ing, c );
    std::vector<std::pair<std::size_t, std::string>> kept;   // (source-order index, element)
    for( const NodeId m : slicePicks( in.ing, members, c.name, words ) )
    {
        const Symbol& ms = in.ing.symbols[m];
        if( overlapsServed( in.ing, m, served, /*orHolds=*/true ) )
        {
            continue;   // its text, or a body inside it, is already in this answer (a ranked row, the slot's owner): never twice
        }
        if( out.bodyBytes + ( ms.endByte - ms.sigStartByte ) > room )
        {
            continue;   // the span alone is over what is left: never rendered
        }
        const std::optional<RedactCounts> before = in.redact != nullptr ? std::optional<RedactCounts>( *in.redact ) : std::nullopt;
        const std::optional<std::string>  piece  = renderOneBody( in, m );
        if( piece && out.bodyBytes + piece->size() <= room )
        {
            out.bodyBytes += piece->size();
            kept.emplace_back( std::size_t( std::ranges::find( members, m ) - members.begin() ), *piece );
            served.push_back( m );
            continue;
        }
        rw::redactTakeBack( in.redact, before, in.redact != nullptr ? std::optional<RedactCounts>( *in.redact ) : std::nullopt );
    }
    if( kept.empty() )
    {
        return out;
    }
    std::ranges::sort( kept, {}, &std::pair<std::size_t, std::string>::first );
    std::vector<char> esc;
    const std::string rootPrefix = in.rootArg.empty() ? std::string() : rw::sarif::rootPrefixOf( in.rootArg );
    const std::string path       = in.rootArg.empty() ? std::string( in.ing.files[c.fileId] )
                                                      : std::string( rw::sarif::rootRelativeUri( in.ing.files[c.fileId], rootPrefix ) );
    out.xml = "<slice p=\"";
    out.xml += escapeXml( path, esc );
    out.xml += "\" n=\"";
    out.xml += escapeXml( c.name, esc );
    out.xml += "\" l=\"" + std::to_string( c.line ) + "\" members=\"" + std::to_string( kept.size() ) + "\" of=\"" + std::to_string( members.size() ) + "\">";
    for( const auto& [ idx, x ] : kept )
    {
        out.xml += x;
    }
    out.xml += "</slice>";
    return out;
}

// One served piece of the fold, in walk order: a ranked row's body (id = the row) or a member slice (id = kNoNode, never replaced).
struct FoldPiece
{
    NodeId      id = kNoNode;
    std::string xml;
    std::size_t bodyBytes = 0;
};
// FIX1 N2: a ranked body that holds bodies the fold already served (a class after its own method) replaces them — its text carries
// theirs. The bytes it would charge net of theirs, or nullopt when it holds a slice member (a slice is never cut apart). The slot's
// owner is its own element outside the fold, before it: an outer body beside it is served as before.
inline std::optional<std::size_t> refundOfInner( const IngestResult& ing, NodeId outer, const std::vector<FoldPiece>& pieces,
                                                 const std::vector<NodeId>& served, NodeId slotOwner )
{
    std::size_t refund = 0;
    for( const NodeId b : served )
    {
        if( b == slotOwner || !spanInside( ing, b, outer ) )
        {
            continue;
        }
        const auto it = std::ranges::find( pieces, b, &FoldPiece::id );
        if( it == pieces.end() )
        {
            return std::nullopt;   // a slice member: it stays, so the outer body would repeat it
        }
        refund += it->bodyBytes;
    }
    return refund;
}
// WRAPPER-FOLLOW: from a body the answer serves, the delegate bodies a chain of thin wrappers leads to (hopbody.h thinDelegate), at
// most kWrapperFollowDepth levels, each <b follow_of="WRAPPER"> whole up to kHopBodyCapBytes (else cut and disclosed by packBodies'
// truncation). A delegate whose text the answer already carries stops the chain (its own follows ride where it is served).
struct FollowRender
{
    std::string xml;
    std::size_t bytes = 0, count = 0;
};
// The answer-wide follow guard (kWrapperFollowMax): bodies followed so far, and the wrappers past it whose callee was not followed.
struct FollowBudget
{
    std::size_t followed = 0, cut = 0;
    std::string firstCutNext;   // the first unfollowed callee's --expand (unescaped)
};
// follow_of= names the wrapper as its row would (Owner.name when the index defines its owner, review F7): a super-override follow
// (ChildRunner.launch -> BaseRunner.launch) no longer reads follow_of="launch" on a <b n="launch">.
inline std::string followOfName( const IngestResult& ing, NodeId w )
{
    const Symbol& s = ing.symbols[w];
    return memberOwnerPossible( s ) ? qualifiedMemberName( MemberOwners( ing ).ownerOf( s ), s ) : s.name;
}
inline FollowRender renderFollows( const BodyFoldInputs& in, NodeId from, std::vector<NodeId>& served, FollowBudget& budget )
{
    FollowRender out;
    if( in.g == nullptr || !hopBodiesOn() )
    {
        return out;
    }
    std::vector<char> esc;
    NodeId            cur = from;
    for( std::size_t depth = 0; depth < kWrapperFollowDepth; ++depth )
    {
        const NodeId t = thinDelegate( in.ing, *in.g, cur );
        if( t == kNoNode || overlapsServed( in.ing, t, served, /*orHolds=*/true ) )
        {
            break;
        }
        if( budget.followed == kWrapperFollowMax )
        {
            if( budget.cut++ == 0 )
            {
                budget.firstCutNext = expandSelectorOf( in.ing, t, in.rootArg );
            }
            break;   // the spew guard: counted and named on <follow_cut>, never silent
        }
        std::optional<std::string> b = renderBodyElement( in.ing, t, kHopBodyCapBytes, in.compress, in.redact, in.rootArg, &in.lensRank );
        if( !b )
        {
            break;
        }
        insertOpenTagAttrs( *b, "<b t=\"", " follow_of=\"" + std::string( escapeXml( followOfName( in.ing, cur ), esc ) ) + "\"" );
        out.bytes += b->size();
        ++out.count;
        ++budget.followed;
        out.xml += *b;
        served.push_back( t );
        cur = t;
    }
    return out;
}
}   // namespace fold_detail

// THE FOLD'S RENDER: the walk the header comment states. A body that does not fit is never rendered into the answer, and the
// redaction count its render added is taken back (it is not served). Each text is served once (FIX1 N2): a candidate inside a body
// already served counts as served; one that holds served ranked bodies replaces them.
inline BodyFoldRender renderForBodyFold( const BodyFoldInputs& in, const std::vector<NodeId>& candidates )
{
    BodyFoldRender out;
    out.total = candidates.size();
    if( candidates.empty() )
    {
        return out;
    }
    std::vector<fold_detail::FoldPiece> pieces;
    std::string skips;
    std::size_t used = 0;
    std::optional<std::vector<std::string>> words;   // the member slice's question words, split on the first slice
    std::vector<NodeId> served;                       // every body this answer carries: the slot's owner, then the fold's
    if( in.bodied != kNoNode )
    {
        served.push_back( in.bodied );
    }
    for( const NodeId id : candidates )
    {
        EXPECTS( id < in.ing.symbols.size(), "a fold candidate is an indexed symbol (forBodyFoldCandidates)" );
        if( fold_detail::overlapsServed( in.ing, id, served, /*orHolds=*/false ) )
        {
            ++out.served;   // a ranked row whose text an earlier body or slice already serves whole: counted, never repeated
            continue;
        }
        const Symbol&     s       = in.ing.symbols[id];
        const std::size_t span    = s.endByte - s.sigStartByte;
        const std::optional<std::size_t> refund = fold_detail::refundOfInner( in.ing, id, pieces, served, in.bodied );
        std::string       next;
        // the source span is a lower bound of the element (markup only adds bytes), so a span over what is left skips unrendered
        if( refund && used - *refund + span <= kForBodyFoldBudgetBytes )
        {
            const std::optional<RedactCounts> before = in.redact != nullptr ? std::optional<RedactCounts>( *in.redact ) : std::nullopt;
            const std::optional<std::string>  piece  = fold_detail::renderOneBody( in, id );
            if( piece && used - *refund + piece->size() <= kForBodyFoldBudgetBytes )
            {
                std::erase_if( pieces, [ & ]( const fold_detail::FoldPiece& p ) { return p.id != kNoNode && fold_detail::spanInside( in.ing, p.id, id ); } );
                pieces.push_back( { id, *piece, piece->size() } );
                used = used - *refund + piece->size();
                ++out.served;
                served.push_back( id );
                continue;
            }
            rw::redactTakeBack( in.redact, before, in.redact != nullptr ? std::optional<RedactCounts>( *in.redact ) : std::nullopt );
        }
        if( ReceiverEvidence::classLike( s.kind ) )   // a class, struct or interface row: the member slice
        {
            if( !words )
            {
                words = fold_detail::sliceWords( in.task );
            }
            fold_detail::SliceRender slice = fold_detail::renderSlice( in, id, *words, kForBodyFoldBudgetBytes - used, served );
            used += slice.bodyBytes;
            out.slices += slice.bodyBytes > 0 ? 1u : 0u;
            if( slice.bodyBytes > 0 )
            {
                out.sliced.push_back( id );
            }
            if( !slice.xml.empty() )
            {
                pieces.push_back( { kNoNode, std::move( slice.xml ), slice.bodyBytes } );
            }
        }
        skips += fold_detail::skipRow( in, id, next );
        if( out.firstSkipNext.empty() )
        {
            out.firstSkipNext = next;
        }
    }
    std::string               bodies;
    std::size_t               followBytes = 0;
    fold_detail::FollowBudget followBudget;
    const auto  follow = [ & ]( NodeId from )
    {
        fold_detail::FollowRender f = fold_detail::renderFollows( in, from, served, followBudget );
        bodies += f.xml;
        followBytes += f.bytes;
        out.follows += f.count;
    };
    if( in.bodied != kNoNode )
    {
        follow( in.bodied );   // the slot owner's body is its own element before the fold: its delegate leads the fold
    }
    for( const fold_detail::FoldPiece& p : pieces )
    {
        bodies += p.xml;
        if( p.id != kNoNode )
        {
            follow( p.id );   // right after the wrapper it explains
        }
    }
    if( followBudget.cut > 0 )
    {
        bodies += "<follow_cut n=\"" + std::to_string( followBudget.cut ) + "\"" + nextAttrXml( followBudget.firstCutNext ) + "/>";
    }
    const std::string open = "<fold kind=\"bodies\" budget_bytes=\"" + std::to_string( kForBodyFoldBudgetBytes ) + "\" served=\""
                           + std::to_string( out.served ) + "\" total=\"" + std::to_string( out.total ) + "\">";
    constexpr std::string_view kClose = "</fold>";
    out.xml         = open + bodies + skips + std::string( kClose );
    out.bodyTokens  = tokensForEmittedBytes( used + followBytes, kBytesPerTokenBody );
    out.markupBytes = out.xml.size() - used - followBytes;
    out.bodies      = std::move( served );
    ENSURES( used <= kForBodyFoldBudgetBytes, "the served bodies fit the fold's budget" );
    return out;
}

// C3 NEXT ORDER (dn-compound): on an answer that carries the fold, the <sigs> continuation an agent meets first is the call that
// ever lifted a row — the first skipped body's --expand — and the signatures-only re-call of the same rows (0 items lifted in 20
// executions) moves to sigs_next=, its reading renamed with it. Only the <sigs> open tag is touched; nothing when it has no next=
// and no body was skipped; an answer whose fold skipped nothing keeps its <sigs> tag as it was.
inline constexpr std::string_view kForFoldSigsNextNote = " [sigs sigs_next=: one call serving all total= rows uncut]";
inline void spliceFoldSigsNext( std::string& sigs, std::string& sigsNote, std::string_view firstSkipNext )
{
    if( firstSkipNext.empty() )
    {
        return;   // every candidate was served: no body to lead with, the <sigs> continuation stays the re-call it was
    }
    std::size_t open = sigs.find( "<sigs" );
    while( open != std::string::npos && open + 5 < sigs.size() && sigs[open + 5] != ' ' && sigs[open + 5] != '>' )
    {
        open = sigs.find( "<sigs", open + 5 );   // the open tag itself, never a longer element name
    }
    std::size_t close = open == std::string::npos ? std::string::npos : sigs.find( '>', open );
    if( close == std::string::npos )
    {
        return;
    }
    constexpr std::string_view kNext = " next=\"";
    if( const std::size_t at = sigs.find( kNext, open ); at != std::string::npos && at < close )
    {
        sigs.replace( at, kNext.size(), " sigs_next=\"" );
        close += 5;   // "sigs_"
        if( const std::size_t n = sigsNote.find( kForSigsNextNote ); n != std::string::npos )
        {
            sigsNote.replace( n, kForSigsNextNote.size(), kForFoldSigsNextNote );
        }
    }
    sigs.insert( close, " next=\"" + std::string( firstSkipNext ) + "\"" );
}

}   // namespace rw
