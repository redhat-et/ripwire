#pragma once
// formembers.h — MEMBER NAMES on the owner rows of a compact-route --for answer (lane member-names, train 32).
//
// WHY. A compact --for answer (bodies="0") names a class/struct/interface as one <d> row: its declaration line, never what it
// holds. A question whose answer is a METHOD of a shown owner (mdbook's MDBook::execute_build_process, nunjucks' Context.addBlock,
// starlette's MultiPartParser.on_part_begin) then had the right owner on screen and the member nowhere: the reader had to --expand
// a 1,300-line class to find one name. mem= names the members on the owner row itself.
//
// WHAT. On a SHOWN owner row (ReceiverEvidence::classLike: class, struct, interface/trait) the row gains
//   mem="a,b,…"     up to kForMemberNameCap names of its DIRECT members, and
//   mem_more="N"    N more member names it did not list (absent when none was cut).
// A member is the parser's (fold_detail::sliceMembers = forowner.h isParsedMemberOf): a def whose index scope names the owner
// (a Rust/Go impl or receiver method, a C++ out-of-line definition, in any file) or whose span lies inside the owner's span in
// the same file (a C++ in-class declaration, a JS/TS/Python method), never one nested inside another member (a closure inside a
// method is that method's text). Only callables and fields are named; a nested type is not a member name here.
// Order: the most question words (the fold's own words, sliceWords) in the name first, then the owner's own file before others,
// then path (file id order is path order), then declaration line, then the name itself (two members declared on one line tie on
// every other key; a content key, never NodeId — CodeRabbit #676 4588520035) — forOwnerMemberNames' sort key, and BOTH legend
// clauses below name every one of those keys, so a reader derives the printed order from the legend alone (#595, soarkit: the clauses stopped at
// "then line" while the key put the owner's file first). A name rides once (an overload, or a C++ declaration and its
// out-of-line definition, are one name).
// NOT listed: a name the answer already shows as a row (one of this owner's members ranked, or the owner's own name: a C++
// constructor), and a name a comma would split. Every member name not listed for another reason is counted in mem_more=.
//
// NOT ON: an owner whose text the answer already carries — a body the fold or the body slot serves holds it (the owner itself, or
// an enclosing body), or the fold served its member slice; an AMBIGUOUS owner (another class/struct/interface of the same name
// and a compatible language is indexed: a member's sc= cannot say which one it belongs to) — no list at all, never a guess.
//
// HONESTY. Names only: a name is index-proven containment or scope, never "relevant", never a call, never synthesised. The bytes
// ride on top of the ranked rows (the rows are chosen before the names are spliced, so a name never costs a row) and est_tokens
// prices them with the rest of <sigs>.
// Posture: the fold's — the compact route, XML, the DEFAULT regime (no explicit --token-budget: a size the caller named stays the
// answer it was). The name-exact route, --signatures-only, --json, --detail, --auto-bodies, --expand, the map and the file page
// carry none. RIPWIRE_NO_MEMBER_NAMES (any value) turns it off: the A/B handle.

#include "forfold.h"   // fold_detail::sliceMembers / sliceWords / spanInside — the fold's own member and question-word readings
#include "graph.h"    // langCompatible
#include "model.h"
#include "receiverevidence.h"   // ReceiverEvidence::classLike — the one class/struct/interface kind test

#include <algorithm>
#include <array>
#include <cstddef>
#include <cstdint>
#include <cstdlib>
#include <string>
#include <string_view>
#include <tuple>
#include <utility>
#include <vector>

namespace rw
{

// How many member names an owner row lists; the rest is counted in mem_more= (gap-diag §3.1: K=8 flipped 5 rows at +284 B median).
// A signed quantity (compared with std::ssize); the full legend clause below states it from this constant.
inline constexpr std::ptrdiff_t kForMemberNameCap = 8;
static_assert( kForMemberNameCap > 0, "an owner row lists at least one member name" );

// The A/B switch: member names ride unless RIPWIRE_NO_MEMBER_NAMES is set. The caller adds the posture (compact route, XML, default).
inline bool forMemberNamesOn()
{
    return std::getenv( "RIPWIRE_NO_MEMBER_NAMES" ) == nullptr;
}

// The legend clauses, present-only beside the attribute (a row carries mem=). Terse (LEGEND-SHORTEN); no "--" (an XML comment).
inline constexpr std::string_view kForCompactMemberNamesLegend =
    "; d mem= an owner's direct member names only, by the index (question words first, then owner's file, path, line, name), mem_more= names cut";
namespace member_detail
{
// The full clause, built at compile time around kForMemberNameCap's decimal digits, so the cap it states is the cap.
inline constexpr std::string_view kMemberNamesLegendHead = "; mem= on an owner d row: up to ";
inline constexpr std::string_view kMemberNamesLegendTail =
    " names of its direct members by the index (scope or span, question words first, then owner's file, path, line, name), "
    "not a claim they answer, never a row already shown, mem_more= the member names not listed";
struct LegendText
{
    std::array<char, 256> text{};
    std::size_t           size = 0;
};
consteval LegendText memberNamesLegend()
{
    LegendText out;
    const auto put = [ & ]( char ch ) { out.text[ out.size++ ] = ch; };   // past 256 B: not a constant expression, the build fails
    for( const char ch : kMemberNamesLegendHead )
    {
        put( ch );
    }
    std::array<char, 20> digits{};
    std::size_t          nd = 0;
    for( std::ptrdiff_t v = kForMemberNameCap; v > 0; v /= 10 )
    {
        digits[ nd++ ] = char( '0' + v % 10 );
    }
    while( nd > 0 )
    {
        put( digits[ --nd ] );
    }
    for( const char ch : kMemberNamesLegendTail )
    {
        put( ch );
    }
    return out;
}
inline constexpr LegendText kMemberNamesLegendText = memberNamesLegend();
}   // namespace member_detail
inline constexpr std::string_view kForMemberNamesLegend{ member_detail::kMemberNamesLegendText.text.data(), member_detail::kMemberNamesLegendText.size };
static_assert( kForCompactMemberNamesLegend.find( ';', 1 ) == std::string_view::npos && kForMemberNamesLegend.find( ';', 1 ) == std::string_view::npos,
               "one clause each: a ';' inside would split it (the legend's clause separator)" );

// The member names of one owner row.
struct OwnerMemberNames
{
    std::vector<std::string> names;     // in mem= order, at most kForMemberNameCap
    std::ptrdiff_t           more = 0;  // distinct member names not listed (cut by the count, or unspellable)
};

namespace member_detail
{
// another class/struct/interface of the owner's name, in a compatible language, with a body: then a member's sc= cannot say
// which owner it belongs to
inline bool ownerNameAmbiguous( const IngestResult& ing, const Symbol& c )
{
    return std::ranges::any_of( ing.symbols, [ & ]( const Symbol& o )
    {
        return o.id != c.id && ReceiverEvidence::classLike( o.kind ) && o.name == c.name && o.endByte > o.sigStartByte
            && langCompatible( o.lang, c.lang );
    } );
}
// how many of the question words the name holds as subtokens
inline std::ptrdiff_t wordOverlap( std::string_view name, const std::vector<std::string>& words )
{
    return subtokenOverlap( name, words );
}
}   // namespace member_detail

// The names one SHOWN owner row lists (the header comment's rule); empty names and more=0 when it lists none. `shownIds` are the
// answer's <d> rows; `words` the question words (fold_detail::sliceWords).
inline OwnerMemberNames forOwnerMemberNames( const IngestResult& ing, NodeId owner, const std::vector<std::string>& words,
                                             const std::vector<NodeId>& shownIds )
{
    EXPECTS( owner < ing.symbols.size(), "an owner row is an indexed symbol" );
    const Symbol&  c = ing.symbols[owner];
    OwnerMemberNames out;
    if( !ReceiverEvidence::classLike( c.kind ) || member_detail::ownerNameAmbiguous( ing, c ) )
    {
        return out;
    }
    std::vector<NodeId> members = fold_detail::sliceMembers( ing, c );
    // the member kinds a name is listed for: callables (ReceiverEvidence::callableKind) and fields — a nested type, a variable or a
    // section is not a member name here
    std::erase_if( members, [ & ]( NodeId m ) { return !ReceiverEvidence::callableKind( ing.symbols[m].kind ) && ing.symbols[m].kind != SymKind::Field; } );
    // a name the answer already shows: the owner's own (a constructor) or one of its members ranked as a row
    std::vector<std::string_view> shownNames{ c.name };
    for( const NodeId m : members )
    {
        if( std::ranges::find( shownIds, m ) != shownIds.end() )
        {
            shownNames.push_back( ing.symbols[m].name );
        }
    }
    // the last key is the name, not NodeId: two members on one line tie on every other key, and equal names print once (below)
    using Key = std::tuple<std::ptrdiff_t, bool, std::uint32_t, std::uint32_t, std::string_view>;
    const auto key = [ & ]( NodeId m ) -> Key
    {
        const Symbol& s = ing.symbols[m];
        return { -member_detail::wordOverlap( s.name, words ), s.fileId != c.fileId, s.fileId, s.line, s.name };
    };
    std::ranges::sort( members, [ & ]( NodeId a, NodeId b ) { return key( a ) < key( b ); } );
    std::vector<std::string_view> seen;
    for( const NodeId m : members )
    {
        const std::string_view name = ing.symbols[m].name;
        if( name.empty() || std::ranges::find( shownNames, name ) != shownNames.end() || std::ranges::find( seen, name ) != seen.end() )
        {
            continue;   // shown already, or this name rode once (an overload, a declaration beside its definition)
        }
        seen.push_back( name );
        if( std::ssize( out.names ) < kForMemberNameCap && name.find( ',' ) == std::string_view::npos )
        {
            out.names.emplace_back( name );
            continue;
        }
        ++out.more;   // cut by the count, or a name the list's comma would split: counted, never silent
    }
    return out;
}

// The answer's bodies that already carry text (the fold's served bodies and slices, the body slot's owner), the owners they cover.
struct MemberNamesServed
{
    std::vector<NodeId> bodies;   // every body the answer serves whole (fold, slice members, the slot's owner)
    std::vector<NodeId> sliced;   // classes the fold served as a member slice
};

// THE SPLICE: walk the rendered <sigs> rows (each opens `<d l=`, one per `shownIds` entry, in that order) and append
// ` mem="…"[ mem_more="N"]` to each shown owner row's head the header comment admits. Returns the bytes added (0: no row got a
// list, `sigs` untouched). A row count that disagrees with `shownIds` splices nothing (the rows are not the ones the ids name).
inline std::size_t spliceMemberNames( std::string& sigs, const IngestResult& ing, const std::vector<NodeId>& shownIds,
                                      std::string_view task, const MemberNamesServed& served )
{
    constexpr std::string_view kOpen = "<d l=\"";
    std::vector<std::size_t> heads;
    for( std::size_t at = sigs.find( kOpen ); at != std::string::npos; at = sigs.find( kOpen, at + kOpen.size() ) )
    {
        heads.push_back( at );
    }
    if( heads.size() != shownIds.size() )
    {
        // the rows are not the ones the ids name: no row gets a list, and the answer is the one it was without member names
        DISCLOSE( Diagnostics::answerUnchanged, "no row carries mem=: the answer is the one without member names",
                  "spliceMemberNames: the <sigs> rows and the shown ids disagree" );
        return 0;
    }
    std::vector<std::string> words;
    bool                     haveWords = false;
    std::vector<std::pair<std::size_t, std::string>> inserts;   // (offset of the head's '>', attribute run)
    std::vector<char>        esc;
    for( std::size_t i = 0; i < heads.size(); ++i )
    {
        const NodeId id = shownIds[i];
        if( id >= ing.symbols.size() || !ReceiverEvidence::classLike( ing.symbols[id].kind )
            || std::ranges::find( served.sliced, id ) != served.sliced.end()
            || fold_detail::overlapsServed( ing, id, served.bodies, /*orHolds=*/false ) )
        {
            continue;   // not an owner, or the answer already carries its text (its body, an enclosing body, or its slice)
        }
        if( !haveWords )
        {
            words     = fold_detail::sliceWords( task );
            haveWords = true;
        }
        const OwnerMemberNames mn = forOwnerMemberNames( ing, id, words, shownIds );
        if( mn.names.empty() )
        {
            continue;   // nothing to name (more= alone would claim members it cannot show: a comma-split name only)
        }
        std::string run = " mem=\"";
        for( std::size_t k = 0; k < mn.names.size(); ++k )
        {
            run += k == 0 ? "" : ",";
            run += escapeXml( mn.names[k], esc );
        }
        run += "\"";
        if( mn.more > 0 )
        {
            run += " mem_more=\"" + std::to_string( mn.more ) + "\"";
        }
        const std::size_t close = sigs.find( '>', heads[i] );
        ASSUME( close != std::string::npos && ( i + 1 == heads.size() || close < heads[i + 1] ), "a <d> head closes before the next row opens" );
        inserts.emplace_back( close, std::move( run ) );
    }
    std::size_t added = 0;
    for( auto it = inserts.rbegin(); it != inserts.rend(); ++it )   // back to front: earlier offsets stay valid
    {
        sigs.insert( it->first, it->second );
        added += it->second.size();
    }
    return added;
}

}   // namespace rw
