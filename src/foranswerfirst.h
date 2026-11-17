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

#include <cstddef>
#include <string>
#include <string_view>
#include <vector>

#include "infra/Diagnostics.h"

namespace rw::answerfirst
{

// One top-level child of the root: its exact byte span, and what it is.
struct Block
{
    std::size_t      begin   = 0;
    std::size_t      end     = 0;
    bool             comment = false;
    std::string_view name;   // empty for a comment
};

// The gate-environment opt-out. NEVER a binary knob — the same posture RIPWIRE_LEGEND_PINS=strict holds in
// legendtarget.sh. test/foranswerfirstcheck.sh needs a legacy baseline to compare against, and a permutation
// gate with no baseline is a gate that cannot fail.
[[nodiscard]] inline bool legacyOrderAsked() noexcept
{
    const char* v = std::getenv( "RIPWIRE_FOR_LEGACY_ORDER" );
    return v != nullptr && v[0] == '1' && v[1] == '\0';
}

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

// Permute one finished --for answer in place. Returns whether it was rewritten.
//
// Every byte of every block is copied unchanged; only their order moves. The ENSURES below is the contract:
// a permutation that changed the document's size would be a different change wearing this one's name.
inline bool answerFirst( std::string& doc )
{
    if( legacyOrderAsked() ) { return false; }
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
    const auto emit = [ & ]( const Block& b ) { out.append( view.substr( b.begin, b.end - b.begin ) ); };

    for( const Block& b : blocks )   // 1. resolved routed sections, in their original relative order
    {
        if( !b.comment && resolvedRouted( view.substr( b.begin, b.end - b.begin ), b.name ) ) { emit( b ); }
    }
    for( const Block& b : blocks )   // 2. every other row block, order untouched — <sigs> stays first among them
    {
        if( !b.comment && !resolvedRouted( view.substr( b.begin, b.end - b.begin ), b.name ) ) { emit( b ); }
    }
    for( const Block& b : blocks )   // 3. the legend, last, relative order kept
    {
        if( b.comment ) { emit( b ); }
    }
    out.append( view.substr( closeAt ) );

    // THE PERMUTATION CONTRACT. Not an assertion of taste: if this ever fails, the pass has dropped or
    // duplicated a block, and the band's whole safety argument — no row removed, so no gold lost — is void.
    // DISCLOSE, not VERIFY( false ): Release deletes the fallback behind a trapping check, and this IS the
    // fallback. (CLAUDE.md still calls this macro DEGRADED_PATH_ALERT; Diagnostics.h:545 records that as the
    // same alert "under a new name, byte for byte", and the code is the authority.)
    if( out.size() != doc.size() )
    {
        DISCLOSE( "foranswerfirst: the permuted answer changed size — serving the original, unpermuted" );
        return false;
    }
    doc.swap( out );
    return true;
}

}   // namespace rw::answerfirst
