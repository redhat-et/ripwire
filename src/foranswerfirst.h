// foranswerfirst.h — ITEM R: a finished `--for` answer serves its ANSWER first.
//
// Two moves on a buffered document, and nothing else:
//   1. every top-level legend comment goes AFTER the rows, keeping its relative order;
//   2. a RESOLVED routed section goes ahead of <sigs>.
//
// It is a PERMUTATION. The same top-level blocks, byte for byte, in a different order — so no row is
// removed, no payload byte changes, and no gold can be lost by construction. That property is the whole
// reason this exists: four pre-registered attempts to make a --for answer shorter by CUTTING failed their
// own zero-gold-loss rules (item K's fixed tail cap, K1's height of 64, item C collapsing the tail on
// routed-element PRESENCE, item C' on routed-verb RESOLUTION), and unconditional tail removal costs 92
// anchors across 63 of 275 graded cells. A permutation cannot reach that bar.
//
// MEASURED BEFORE THIS WAS WRITTEN, as offline permutations of all 216 recorded --for cells: gold items
// found at a 2 KB budget 0.4 % -> 54.8 %, at 4 KB 19.3 % -> 70.6 %, at 8 KB 69.5 % -> 84.1 %; median
// bytes-to-complete 10,279 -> 5,541; ZERO of 212 cells worse; 27 of 27 repos improved. On the 13 cells
// carrying <path reachable="1"> or <met_bridge>, bytes-to-complete falls from a median 37,125 B (92.9 % of
// the answer's depth) to 3,377 B (8.0 %). Registered as docs/EVALS.md amendment 8.
//
// WHY THE LEGEND MAY MOVE. G4 constrains the legend's COUNT — "the legend is emitted once per answer on the
// CLI" — not its position, and its next clause already describes an answer that "ends with" its legend
// material. The legend STAYS IN THE ANSWER, so the ~80 gates that assert "this attribute is defined in this
// answer" still pass: this is the ref posture's move WITHOUT the ref posture's drop, which legenddict.h
// already documents as "rows first … legend comment … moved after the rows". It therefore does not wait on
// the dictionary-backed coverage contract.
//
// RESOLVED IS DELIBERATELY NARROW. Three separate bands this round mistook element PRESENCE for resolution,
// and the cost is measurable: <lego> and <compose> ship as `shown="0" capped="1"` STUBS when nothing
// resolved, and <graph_verb> is frequently an unresolved `reachable="0"` fallback cascade. Promoting any
// <graph_verb> has a worst case of +17,479 B — one cell put a 14.8 KB block ahead of <sigs> of which the
// answering path was 1,348 B. So a section is RESOLVED only when:
//     <reexports> carries BOTH a <def> row and at least one <rx> row, or
//     <graph_verb> carries <path … reachable="1"> or <met_bridge>.
// Measured marginal effect once the comments are at the end: reexports 14 better / 0 worse; graph_verb
// 8 better / 5 worse with a worst case of +2,192 B. Every other candidate measured net-worse or a wash when
// promoted — <callers> (12/5, ~1 KB either way), selfhooks (4/4), lit, shortkey, dotted_strings,
// exemplar_family — and none of them moves.
//
// <sigs> STAYS FIRST among the generic sections. A fitted full-section order (every section sorted by
// gold-per-byte) FAILED a held-out split, worse in more cells than better in both folds. And <tail> does NOT
// move: whole-tail-last took median bytes-to-complete 10,279 -> 11,487. Those two nulls are registered so
// this file cannot be widened into them without new evidence.
//
// THE STATED COST, which belongs in the open rather than in a footnote: a truncating consumer previously
// lost ROWS and now loses DEFINITIONS, so a hedge like `cands="133"` can be read without its reading. That
// is the strongest argument against this change (registered as band R5).
#pragma once

#include <algorithm>
#include <cstddef>
#include <string>
#include <string_view>
#include <vector>

#include "infra/Diagnostics.h"
#include "infra/emit.h"

namespace rw::answerfirst
{

// The DISCLOSE SINK for this pass's two fallbacks. A one-argument DISCLOSE( msg ) is trace-only and compiles
// away under NDEBUG (Diagnostics.h RW_DISCLOSE_1), so a RELEASE user learns nothing when the permutation
// declines to run — test/selfcheckcheck.sh (R) ratchets on exactly that count, and it caught these two.
//
// Both fallbacks serve a COMPLETE answer: only the reordering is missed, which is why each message says so.
// A reader who cannot tell a degraded answer from a whole one is the failure this sink exists to prevent.
struct AnswerFirstFallback
{
    enum class DisclosureWhy : std::uint8_t
    {
        SizeChanged,      // the permutation changed the document's size — a block was dropped or duplicated
        NoWholeCapture,   // the answer could not be buffered whole, so it is served in the default order
    };
    void disclose( DisclosureWhy why ) noexcept
    {
        rw::emitTo( stderr, "ripwire: --legend=last: {}\n",
                    why == DisclosureWhy::SizeChanged
                        ? "the permuted answer changed size, so the original order is served — the answer is complete either way"
                        : "the answer did not buffer whole, so it is served in the default order — the answer is complete either way" );
    }
};

// One top-level child of the root: its exact byte span, and what it is.
struct Block
{
    std::size_t      begin   = 0;
    std::size_t      end     = 0;
    bool             comment = false;
    std::string_view name;   // empty for a comment
};

// ITEM R IS OPT-IN (--legend=last). The decision belongs to the caller, which holds the Config; this header used to
// read RIPWIRE_FOR_LEGACY_ORDER itself, which made the ordering depend on the environment rather than on argv and
// left no user-facing way to ask for it. answerFirst() is now unconditional: call it only when the posture asked.
// The name characters an XML element name is made of. A set lookup rather than a hand-rolled scan loop:
// quality-delta scored the loop form as a 79-token duplicate of src/query.h's Eval::ident, which is the
// repo's identifier scanner and has no business being reimplemented here.
inline constexpr std::string_view kNameChars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-";

[[nodiscard]] inline std::string_view elementName( std::string_view doc, std::size_t i, std::size_t j ) noexcept
{
    const std::size_t stop = doc.find_first_not_of( kNameChars, i + 1 );
    return doc.substr( i + 1, ( stop == std::string_view::npos ? j : std::min( stop, j ) ) - ( i + 1 ) );
}

// Scan the root's top-level children between [bodyBegin, bodyEnd).
//
// Hand-rolled, and it must stay that way: --for answers carry ripwire's own C++ inside CDATA, and that
// source contains BOTH comment-shaped and tag-shaped text (`<!--" + add + "-->` and `<std::string>` are real
// strings in it). 228 of 295 recorded answers carry CDATA, and an unmasked scan cost another instrument this
// round an entire 16.9 KB section. A regex here is a defect, not a shortcut.
// A bracketed span the scanner must step over whole rather than parse: a comment or a CDATA section.
// Returns the byte just past its terminator, or npos when it is unterminated inside the body.
[[nodiscard]] inline std::size_t skipBracketed( std::string_view doc, std::size_t i, std::size_t end,
                                                std::string_view open, std::string_view close ) noexcept
{
    if( doc.compare( i, open.size(), open ) != 0 )
    {
        return i;   // not this kind of span: the caller tries the next shape
    }
    const std::size_t j = doc.find( close, i );
    return ( j == std::string_view::npos || j + close.size() > end ) ? std::string_view::npos : j + close.size();
}

// Scan the root's top-level children between [bodyBegin, bodyEnd). Empty means "a shape this pass does not
// understand", and the caller then serves the answer unchanged.
//
// Hand-rolled, and it must stay that way: --for answers carry ripwire's own C++ inside CDATA, and that
// source contains BOTH comment-shaped and tag-shaped text (`<!--" + add + "-->` and `<std::string>` are real
// strings in it). 228 of 295 recorded answers carry CDATA, and an unmasked scan cost another instrument this
// round an entire 16.9 KB section. A regex here is a defect, not a shortcut.
[[nodiscard]] inline std::vector<Block> topLevelBlocks( std::string_view doc, std::size_t bodyBegin, std::size_t bodyEnd )
{
    std::vector<Block> out;
    std::size_t        i = bodyBegin, depth = 0, start = 0;
    std::string_view   name;
    while( i < bodyEnd )
    {
        const std::size_t afterComment = skipBracketed( doc, i, bodyEnd, "<!--", "-->" );
        if( afterComment == std::string_view::npos ) { return {}; }
        if( afterComment != i )
        {
            if( depth == 0 ) { out.push_back( { i, afterComment, true, {} } ); }
            i = afterComment;
            continue;
        }
        const std::size_t afterCdata = skipBracketed( doc, i, bodyEnd, "<![CDATA[", "]]>" );
        if( afterCdata == std::string_view::npos ) { return {}; }
        if( afterCdata != i ) { i = afterCdata; continue; }
        if( doc[ i ] != '<' ) { ++i; continue; }   // inter-tag text: minified output has none

        const std::size_t j = doc.find( '>', i );
        if( j == std::string_view::npos || j >= bodyEnd ) { return {}; }
        if( doc[ i + 1 ] == '/' )
        {
            if( depth == 0 ) { return {}; }
            if( --depth == 0 ) { out.push_back( { start, j + 1, false, name } ); }
            i = j + 1;
            continue;
        }
        const bool selfClosing = j > i && doc[ j - 1 ] == '/';
        if( depth == 0 )
        {
            if( selfClosing ) { out.push_back( { i, j + 1, false, elementName( doc, i, j ) } ); }
            else              { start = i; name = elementName( doc, i, j ); }
        }
        if( !selfClosing ) { ++depth; }
        i = j + 1;
    }
    return depth == 0 ? out : std::vector<Block>{};
}

// RESOLVED, by the narrow definition in the header. Read from the block's own structure — never from any
// ranking, score or gold.
[[nodiscard]] inline bool resolvedRouted( std::string_view block, std::string_view name ) noexcept
{
    if( name == "reexports" )
    {
        return block.find( "<def" ) != std::string_view::npos && block.find( "<rx" ) != std::string_view::npos;
    }
    if( name == "graph_verb" )
    {
        return block.find( "reachable=\"1\"" ) != std::string_view::npos || block.find( "<met_bridge" ) != std::string_view::npos;
    }
    return false;
}

// Would the permutation actually move anything? A comment before a row block, or a resolved routed section
// sitting behind <sigs>. Separated so answerFirst stays one job: assemble.
[[nodiscard]] inline bool permutationWouldMove( std::string_view view, const std::vector<Block>& blocks ) noexcept
{
    std::size_t sigsAt = blocks.size();
    for( std::size_t k = 0; k < blocks.size(); ++k )
    {
        if( !blocks[ k ].comment && blocks[ k ].name == "sigs" ) { sigsAt = k; break; }
    }
    for( std::size_t k = 0; k < blocks.size(); ++k )
    {
        const Block& b = blocks[ k ];
        if( b.comment ) { if( k + 1 < blocks.size() ) { return true; } continue; }
        if( k > sigsAt && resolvedRouted( view.substr( b.begin, b.end - b.begin ), b.name ) ) { return true; }
    }
    return false;
}

// The FIRST WORD of a comment: `syms` in `<!-- syms t= n= …`. This is what separates the two kinds of
// comment a --for answer carries. The DOCUMENT legend opens with the verb or the root (`<!-- ripwire for …`,
// `<!-- root …`) and documents the answer as a whole; a BLOCK-LOCAL legend NAMES ITS OWN ELEMENT. Measured on
// a --detail=5 answer: `ripwire`→<sigs> and `root`→<sigs> do not match, `syms`→<syms> does.
//
// AF1-fix (2026-11-18): a block-local legend has TWO spellings in src/, and both name their element: `<!-- syms: …` and
// `<!-- ripwire for X: …` (doc_body, dotted_strings, exemplar_family, lit, manifest_rows, decl_rows, graph_verb, met_bridge,
// path_gap, reask, syms). Reading only the first word sent every `ripwire for X:` legend to the trailing DOCUMENT legend, away
// from its block — against the convention below and AF1's registered layout ("block-local legend comments stay in the stream,
// glued to the block they declare"): fordocbodycheck (f1), forexemplarcheck and formanifestcheck (a1) read the block from its
// legend and found nothing after it. So `ripwire for X` reads as X, whatever follows X (`ripwire for doc_body held="budget":`,
// `ripwire for lit callers:` are block legends too); declaredBlock still requires the next block to BE an <X>. The document
// legend's own `ripwire for schema=…` names no element the answer opens, so it stays where it is.
[[nodiscard]] inline std::string_view commentWordAt( std::string_view doc, std::size_t from, std::size_t end ) noexcept
{
    if( from == std::string_view::npos || from >= end ) { return {}; }
    const std::size_t stop = doc.find_first_not_of( kNameChars, from );
    return doc.substr( from, ( stop == std::string_view::npos ? end : std::min( stop, end ) ) - from );
}
[[nodiscard]] inline std::string_view commentFirstWord( std::string_view doc, const Block& b ) noexcept
{
    const std::string_view first = commentWordAt( doc, doc.find_first_of( kNameChars, b.begin + 4 ), b.end );   // past the "<!--"
    constexpr std::string_view kVerbLead = "ripwire for ";
    const std::size_t          at        = first.empty() ? std::string_view::npos : static_cast<std::size_t>( first.data() - doc.data() );
    if( first != "ripwire" || doc.compare( at, kVerbLead.size(), kVerbLead ) != 0 ) { return first; }
    const std::string_view named = commentWordAt( doc, at + kVerbLead.size(), b.end );
    return named.empty() ? first : named;
}

// Which row block does this comment DECLARE, if any? The house convention is that a block's own legend sits
// in the comment IMMEDIATELY before its open tag, so the block can be switched off without moving a byte in
// front of it and a reader meets the definition where the block begins. Such a comment must therefore TRAVEL
// WITH its block rather than join the document legend at the tail.
//
// Why this matters beyond tidiness: formaxtokenscheck's judge strips one self-declaring trailing block before
// pricing, and its pattern requires comment-then-block. With the comment relocated, 1,447 B stopped being
// stripped and est_tokens looked as though it under-charged by exactly 579 tokens — a phantom accounting
// defect whose only cause was this adjacency. test/foranswerfirstcheck.sh (R8) pins it.
[[nodiscard]] inline std::size_t declaredBlock( std::string_view doc, const std::vector<Block>& blocks, std::size_t k ) noexcept
{
    if( !blocks[ k ].comment ) { return std::string_view::npos; }
    for( std::size_t j = k + 1; j < blocks.size(); ++j )
    {
        if( blocks[ j ].comment ) { continue; }   // several comments may queue in front of one block
        return commentFirstWord( doc, blocks[ k ] ) == blocks[ j ].name ? j : std::string_view::npos;
    }
    return std::string_view::npos;   // nothing follows it: the document legend, by position as well as by name
}

// ── AF2's order spec (results/AF2_FIRST12K_1118/READOUT.md §SPEC, frozen 2026-11-18 after meeting its pre-registered bar:
// within 12 KB, design 70→75 of 99, held-out 32→33 of 39, 0 flips). Three moves on top of the two above, all of them still
// a reordering of the same bytes:
//   A  — every comment that is a DIRECT CHILD of a top-level section (the <graph_verb>/<reexports>/<fold> notes) joins the
//        document legend, relative order kept. NOT <sigs>'s demote:/decl-twin:/one-side: notes, which the spec lists: they
//        label the pointer rows after them by POSITION (see blockTextHoisting). Not moved either: a section's own
//        lead comment (declaredBlock — it travels with its block, R8), the <bodies> section's per-answer body-omitted note,
//        and comments nested inside a row. A zero-row self-closing <lego/> or <compose/> stub between <sigs> and <tail> goes
//        directly after </tail>.
//   E1 — inside <graph_verb>, <met_bridge> ahead of <path_gap> (an emitter swap in verbs_for.h appendSubjectGraphVerbBlock).
//   G  — GUARDED promotion: a RES section after </tail> moves directly ahead of <tail> ONLY IF the tail has more than
//        kGuardTailRows rows, </tail> ends past the page stop, and tail row kGuardTailRows still ends within the stop with it
//        and every section already moved in place. The stop is the DEFAULT PAGE SIZE (kAnswerPageBytesDefault, which forpages.h
//        kForPageBytesDefault IS), never a separate 12,000 — so it follows the owner if the default page becomes 6 KB. The
//        unguarded variant is an owner call and is NOT built.
inline constexpr std::size_t      kAnswerPageBytesDefault = 12000;   // the default page size: forpages.h kForPageBytesDefault IS this
inline constexpr std::size_t      kGuardTailRows          = 24;
inline constexpr std::string_view kPromotable[] = { "lit", "dotted_strings", "graph_verb", "callers", "selfhooks", "manifest_rows",
                                                    "listed", "ep", "reexports", "exemplar_family" };

// One row block as it will be emitted: its own bytes minus the direct-child comments A hoists, which go to `hoisted`.
[[nodiscard]] inline std::string blockTextHoisting( std::string_view view, const Block& b, std::vector<std::string_view>& hoisted )
{
    const std::string_view text = view.substr( b.begin, b.end - b.begin );
    const std::size_t      open = view.find( '>', b.begin ) + 1;
    // NOT <sigs> (AF1 deviation from the frozen spec, measured and reported in results/AF1_ANSWERFIRST_1118/READOUT.md): its
    // demote:/decl-twin:/one-side: comments are POSITIONAL — each labels the <t> pointer rows that FOLLOW it (fordemoteallcheck
    // reads the kind of rows 9-10 as decl-twin and 11-26 as demote from exactly that order). Lifted to the legend, every <t>
    // reads as both kinds at once: a disclosure lost, which no byte saving pays for. The other sections' comments are readings.
    if( b.comment || b.name == "bodies" || b.name == "sigs" || view[ open - 2 ] == '/' ) { return std::string( text ); }
    const std::size_t        close = view.rfind( "</", b.end - 1 );
    const std::vector<Block> kids  = close > open ? topLevelBlocks( view, open, close ) : std::vector<Block>{};
    std::string out;
    std::size_t copied = b.begin;
    for( const Block& k : kids )
    {
        if( !k.comment ) { continue; }
        out.append( view.substr( copied, k.begin - copied ) );
        hoisted.push_back( view.substr( k.begin, k.end - k.begin ) );
        copied = k.end;
    }
    out.append( view.substr( copied, b.end - copied ) );
    return out;
}

// The answer-first order of the row blocks before G: resolved routed sections, then every other row block in place, a
// zero-row lego/compose stub that sits between <sigs> and <tail> moved to just after </tail>.
[[nodiscard]] inline std::vector<std::size_t> rowBlockOrder( std::string_view view, const std::vector<Block>& blocks )
{
    std::vector<std::size_t> routed, rest, stubs;
    bool sawSigs = false, sawTail = false;
    for( std::size_t j = 0; j < blocks.size(); ++j )
    {
        const Block& b = blocks[ j ];
        if( b.comment ) { continue; }
        const std::string_view text = view.substr( b.begin, b.end - b.begin );
        const bool isStub = ( b.name == "lego" || b.name == "compose" ) && text.ends_with( "/>" ) && text.find( '>' ) + 1 == text.size();
        if( resolvedRouted( text, b.name ) )                { routed.push_back( j ); }
        else if( isStub && sawSigs && !sawTail )            { stubs.push_back( j ); }
        else                                                { rest.push_back( j ); }
        if( b.name == "tail" ) { sawTail = true; rest.insert( rest.end(), stubs.begin(), stubs.end() ); stubs.clear(); }
        sawSigs = sawSigs || b.name == "sigs";
    }
    rest.insert( rest.end(), stubs.begin(), stubs.end() );   // no <tail> after them: they stay, in order, at the end
    routed.insert( routed.end(), rest.begin(), rest.end() );
    return routed;
}

// The answer as A will emit it: each block's lead comments (ownerOf), its text with the direct-child comments lifted out, its
// emitted size with those lead comments (`sized`), and the lifted comments in document order.
struct Layout
{
    std::vector<std::size_t>      ownerOf;
    std::vector<std::string>      text;
    std::vector<std::size_t>      sized;
    std::vector<std::string_view> hoisted;
};
[[nodiscard]] inline Layout layoutBlocks( std::string_view view, const std::vector<Block>& blocks )
{
    Layout l{ .ownerOf = std::vector<std::size_t>( blocks.size(), std::string_view::npos ), .text = std::vector<std::string>( blocks.size() ),
              .sized = std::vector<std::size_t>( blocks.size(), 0 ), .hoisted = {} };
    for( std::size_t k = 0; k < blocks.size(); ++k )
    {
        l.ownerOf[ k ] = declaredBlock( view, blocks, k );
        if( !blocks[ k ].comment ) { l.text[ k ] = blockTextHoisting( view, blocks[ k ], l.hoisted ); l.sized[ k ] += l.text[ k ].size(); }
    }
    for( std::size_t k = 0; k < blocks.size(); ++k )
    {
        if( l.ownerOf[ k ] != std::string_view::npos ) { l.sized[ l.ownerOf[ k ] ] += blocks[ k ].end - blocks[ k ].begin; }
    }
    return l;
}

// G, the GUARDED promotion, on the emitted sizes. The bytes ahead of the first row block are the root open tag; the stop is the
// DEFAULT page size, one constant, so every page size windows the same document. Returns the order with the promoted RES
// sections directly ahead of <tail>.
[[nodiscard]] inline std::vector<std::size_t> promoteGuarded( std::string_view view, const std::vector<Block>& blocks, std::vector<std::size_t> order,
                                                              const Layout& layout )
{
    const std::vector<std::size_t>& sized  = layout.sized;
    const std::size_t               prefix = blocks.empty() ? 0 : blocks.front().begin;
    const std::size_t               stop   = kAnswerPageBytesDefault;
    const auto tailIt = std::ranges::find_if( order, [ & ]( std::size_t j ) { return blocks[ j ].name == "tail"; } );
    if( tailIt == order.end() ) { return order; }
    const Block&             tail = blocks[ *tailIt ];
    const std::size_t        open = view.find( '>', tail.begin ) + 1;
    const std::size_t        close = view.rfind( "</", tail.end - 1 );
    std::vector<Block> rows = close > open ? topLevelBlocks( view, open, close ) : std::vector<Block>{};
    std::erase_if( rows, []( const Block& r ) { return r.comment; } );   // ROWS: a comment inside the tail is not one
    std::size_t before = prefix;
    for( auto it = order.begin(); it != tailIt; ++it ) { before += sized[ *it ]; }
    if( rows.size() <= kGuardTailRows || before + sized[ *tailIt ] <= stop ) { return order; }
    const std::size_t rowEnd = before + ( sized[ *tailIt ] - ( tail.end - tail.begin ) ) + ( rows[ kGuardTailRows - 1 ].end - tail.begin );
    std::vector<std::size_t> moved, kept;
    std::size_t used = 0;
    for( auto it = tailIt + 1; it != order.end(); ++it )
    {
        const bool res = std::ranges::find( kPromotable, blocks[ *it ].name ) != std::ranges::end( kPromotable );
        if( res && rowEnd + used + sized[ *it ] <= stop ) { moved.push_back( *it ); used += sized[ *it ]; }
        else                                              { kept.push_back( *it ); }
    }
    std::vector<std::size_t> out( order.begin(), tailIt );
    out.insert( out.end(), moved.begin(), moved.end() );
    out.push_back( *tailIt );
    out.insert( out.end(), kept.begin(), kept.end() );
    return out;
}

// Append the blocks in ANSWER-FIRST order: the row blocks (each preceded by its own block-local legend, so the convention's
// adjacency survives), then the DOCUMENT legend, then the comments A lifted out of the sections. Every byte of the answer is
// copied once; only the order moves.
inline void appendAnswerFirst( std::string_view view, const std::vector<Block>& blocks, std::string& out )
{
    const Layout l   = layoutBlocks( view, blocks );
    const auto   put = [ & ]( std::size_t k ) { out.append( view.substr( blocks[ k ].begin, blocks[ k ].end - blocks[ k ].begin ) ); };
    for( const std::size_t j : promoteGuarded( view, blocks, rowBlockOrder( view, blocks ), l ) )
    {
        for( std::size_t k = 0; k < blocks.size(); ++k )
        {
            if( l.ownerOf[ k ] == j ) { put( k ); }
        }
        out += l.text[ j ];
    }
    for( std::size_t k = 0; k < blocks.size(); ++k )   // the DOCUMENT legend, last, relative order kept
    {
        if( blocks[ k ].comment && l.ownerOf[ k ] == std::string_view::npos ) { put( k ); }
    }
    for( const std::string_view c : l.hoisted ) { out.append( c ); }
}

// Permute one finished --for answer in place. Returns whether it was rewritten.
//
// Every byte of every block is copied unchanged; only their order moves. The ENSURES below is the contract:
// a permutation that changed the document's size would be a different change wearing this one's name.
inline bool answerFirst( std::string& doc )
{
    const std::string_view view = doc;
    const std::size_t      openAt = view.find( "<ctx" );
    if( openAt == std::string_view::npos ) { return false; }
    const std::size_t openEnd = view.find( '>', openAt );
    const std::size_t closeAt = view.rfind( "</ctx>" );
    if( openEnd == std::string_view::npos || closeAt == std::string_view::npos || closeAt <= openEnd ) { return false; }

    const std::vector<Block> blocks = topLevelBlocks( view, openEnd + 1, closeAt );
    if( blocks.empty() ) { return false; }   // not a shape this pass understands: served unchanged

    if( !permutationWouldMove( view, blocks ) ) { return false; }

    std::string out;
    out.reserve( doc.size() );
    out.append( view.substr( 0, openEnd + 1 ) );

    appendAnswerFirst( view, blocks, out );
    out.append( view.substr( closeAt ) );

    // THE PERMUTATION CONTRACT. Not an assertion of taste: if this ever fails, the pass has dropped or
    // duplicated a block, and the band's whole safety argument — no row removed, so no gold lost — is void.
    // DISCLOSE rather than a trapping self-check: Release deletes the fallback behind a trap, and this IS the
    // fallback. (test/selfcheckcheck.sh (A) refuses the retired macro spellings anywhere outside its own
    // history list, so this note names the mechanism instead of the old names; Diagnostics.h:545 holds the
    // rename record, and the code is the authority over any document.)
    if( out.size() != doc.size() )
    {
        AnswerFirstFallback sink;
        DISCLOSE( sink, AnswerFirstFallback::DisclosureWhy::SizeChanged,
                  "foranswerfirst: the permuted answer changed size — serving the original, unpermuted" );
        return false;
    }
    doc.swap( out );
    return true;
}

}   // namespace rw::answerfirst
