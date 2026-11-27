// forpagelegend.h — LD1 (lane LD1, 2026-11-21; lane LG2's lever d1, results/LG2_FIRST_LEGEND_1121/READOUT.md §4.1): a clause of
// the DOCUMENT legend that only a LATER page's rows use travels with that page instead of riding page 1.
//
// THE RULE (forpages.h "WHERE THE LEGEND SITS"). A reader of page N holds page N and page 1: page 1 because every continuation page
// names it (<about legend="ref" have="page1"/>), and nothing between, because a page may be asked directly (--page-bytes=P:N). So
// every attribute and element page N carries is defined on page N or on page 1. Page 1 used to define, in advance, the vocabulary
// only later pages use — the hops clause for a <hops> on page 4, the fold clause for a <fold> on page 5: LG2 measured a median 551 B
// of a 4,554 B first legend that way on GA1 DEV (n=89, 84 of 89 page 1s). Such a clause now leaves page 1 and rides, verbatim, on
// every later page whose rows carry it; a later page carries no clause page 1 still holds. Nothing is reworded and nothing is lost:
// the clause text is the dictionary entry's, so --legend-seen and --legend-dict=seen read it on the later page as on page 1.
//
// WHICH CLAUSES. Only the ones in kTravels, each with its TRIGGERS — the element (<h) or attribute (via=) whose presence on a page
// means the page needs the clause. A clause is moved only when page 1's rows (its root included) carry none of its triggers and a
// later page's rows carry one; any trigger in page 1's rows keeps it there, so a trigger that also matches a served body or an
// unrelated element only keeps bytes, never drops a reading. A VALUE trigger ("&lt;file-scope&gt;", its escaped spelling) is a
// name no element or attribute stands for: the module-scope owner rides a <d n=>, an <h n=> or a tail row's sym= list alike.
// Short attributes (l= p= n=, on every row kind) are never triggers:
// such a clause is needed by its ELEMENT. A clause not in the table, or whose lead no longer starts a dictionary entry (it was
// reworded), stays on page 1 — a missed saving, never a wrong reading. Gate: test/pagelegendcheck.sh (test/pagelegend.py holds an
// independent copy of the triggers; LD0-LD8, with mutation controls).
#pragma once

#include <algorithm>
#include <array>
#include <cstddef>
#include <string>
#include <string_view>
#include <vector>

#include "infra/namesplit.h"   // isIdentChar — the ONE ASCII identifier-character test
#include "legenddict.h"   // kForDocBase / kEntryCount / entryBody — the clause text is the dictionary entry's

namespace rw::forpages::scope
{

struct Travels
{
    std::string_view                lead;       // the clause's opening bytes, as its dictionary entry spells them
    std::array<std::string_view, 4> triggers;   // "<name": that element on the page; "name=": that attribute; "&lt;…": that value
};

// Order is irrelevant (a moved clause keeps its page-1 order on the later page). Leads verbatim from the constants they name.
inline constexpr Travels kTravels[] = {
    { "; h l= p= n=, c n= l= p=", { "<hops", "<h", "<c", "noedge=" } },              // verbs_for.h kForCompactLegendHops
    { "; h calls capped=1 next=", { "<h", "<calls" } },                              // kForCompactHopsCallsNextClause
    { "; h qword=", { "qword=", "qword_cut=" } },                                    // kForCompactLegendOwner
    { "; fold kind=bodies:", { "<fold", "<slice", "<skip" } },                       // forfold.h kForCompactBodyFoldLegend (its first piece)
    { "slice members= of=:", { "<fold", "<slice", "<skip", "members=" } },           // kForCompactBodyFoldMembersClause
    { "skip bytes= next=;", { "<fold", "<slice", "<skip", "sigs_next=" } },          // the fold legend's last piece: it also defines sigs_next=
    { "; b follow_of=W:", { "follow_of=", "<follow_cut" } },                         // kForCompactFoldFollowLegend
    { "; d mem= ", { "mem=", "mem_more=" } },                                        // formembers.h kForCompactMemberNamesLegend
    { "; c via=name:", { "via=" } },                                                 // graphlegend.h kForCompactViaNameClause
    { "; c prov=split:", { "prov=" } },                                              // kForCompactSplitClause
    { " h value_refs=N:", { "value_refs=" } },                                       // kForHopValueRefsClause
    { "; d same_as=N:", { "same_as=" } },                                            // serialize.h kForCompactSameAsLegend
    { "; t tsym=", { "tsym=" } },                                                    // fortailterms.h kForCompactFileTailTermsLegend
    { "; d layer=:", { "layer=" } },                                                 // kForCompactLegendLayer
    { "; iface implementors=N:", { "<iface", "implementors=" } },                    // kForCompactLegendLego
    { "; field name= type= owner= rel=:", { "<field", "<compose" } },                // kForCompactLegendCompose
    { "; lego/compose collapse to a counted stub", { "<lego", "<compose" } },        // serialize.h kForSectionStubLegend
    { "; d ctor_l= ctor_calls=", { "ctor_l=", "ctor_calls=", "ctor_calls_more=" } },  // forctorhop.h kForCompactCtorHopLegend
    { "; d slot_by= functions that MAY call", { "slot_by=", "slot_fields=", "slot_by_more=", "slot_fields_more=" } },   // forslots.h
    { "; d slot_by= ~C,", { "slot_by=", "slot_fields=" } },                          // kForCompactSlotNameLegend
    { "; d slots= ", { "slots=", "slots_more=" } },                                  // kForCompactInitSlotsLegend
    { "; t=modscope n=<file-scope>:", { "&lt;file-scope&gt;" } },                   // graphlegend.h kForCompactModScopeClause
};
inline constexpr std::size_t kTravelCount = std::size( kTravels );

// The full clause text of each row: the first CLI document-legend entry whose text starts with its lead, or empty (inert).
inline const std::array<std::string_view, kTravelCount>& travelBodies()
{
    static const std::array<std::string_view, kTravelCount> bodies = []
    {
        std::array<std::string_view, kTravelCount> b{};
        for( std::size_t i = 0; i < kTravelCount; ++i )
        {
            for( std::size_t id = legenddict::kForDocBase; id < legenddict::kEntryCount && b[ i ].empty(); ++id )
            {
                if( legenddict::entryBody( id ).starts_with( kTravels[ i ].lead ) ) { b[ i ] = legenddict::entryBody( id ); }
            }
        }
        return b;
    }();
    return bodies;
}

// A page's rows as the trigger and carrier tests read them: every comment and CDATA section blanked to spaces, so a served body
// that quotes markup, or a block-local legend, carries no element and no attribute (test/pagelegend.py masks the same way).
[[nodiscard]] inline std::string rowsOnly( std::string_view page )
{
    std::string out( page );
    for( std::size_t i = 0; i < out.size(); )
    {
        const std::size_t c = out.find( "<!--", i ), d = out.find( "<![CDATA[", i );
        const std::size_t at = std::min( c, d );
        if( at == std::string::npos ) { break; }
        const std::size_t close = at == d ? out.find( "]]>", at + 9 ) : out.find( "-->", at + 4 );
        const std::size_t end   = close == std::string::npos ? out.size() : close + 3;
        std::fill( out.begin() + static_cast<std::ptrdiff_t>( at ), out.begin() + static_cast<std::ptrdiff_t>( end ), ' ' );
        i = end;
    }
    return out;
}

// Does `rows` (rowsOnly bytes, the root's open tag included on page 1) carry one of row `i`'s triggers? An element trigger is its
// open tag ("<h " "<h>" "<h/"), an attribute trigger its spelling after a space (` via="`), a value trigger its bytes anywhere.
[[nodiscard]] inline bool needs( std::size_t i, std::string_view rows ) noexcept
{
    for( const std::string_view t : kTravels[ i ].triggers )
    {
        if( t.empty() ) { continue; }
        for( std::size_t at = rows.find( t ); at != std::string_view::npos; at = rows.find( t, at + 1 ) )
        {
            const std::size_t e = at + t.size();
            const bool        hit = t.front() == '&' || ( t.front() == '<' ? e < rows.size() && ( rows[ e ] == ' ' || rows[ e ] == '>' || rows[ e ] == '/' )
                                                                       : at > 0 && rows[ at - 1 ] == ' ' && e < rows.size() && rows[ e ] == '"' );
            if( hit ) { return true; }
        }
    }
    return false;
}

// Where `body` stands in `legend` as a whole clause: opened by its own separator or after "; ", and closed by its own separator or
// by "; ", " " or the comment's close. npos when it is not there as a clause.
[[nodiscard]] inline std::size_t clauseAt( std::string_view legend, std::string_view body ) noexcept
{
    for( std::size_t at = legend.find( body ); at != std::string_view::npos; at = legend.find( body, at + 1 ) )
    {
        const std::size_t e     = at + body.size();
        const bool        left  = body.front() == ';' || body.front() == ' ' || ( at >= 2 && legend.compare( at - 2, 2, "; " ) == 0 );
        const bool        right = body.back() == ' ' || body.back() == ';' || body.back() == '.' || e == legend.size() || legend[ e ] == ';' || legend[ e ] == ' ';
        if( left && right ) { return at; }
    }
    return std::string_view::npos;
}

// Is `c` a character of an attribute name (the `a=` spelling's left edge)?
[[nodiscard]] inline bool nameChar( char c ) noexcept { return namesplit::isIdentChar( c ) || c == '-'; }

// Does `text` spell `name=` with no name character before it — the house convention for defining an attribute?
[[nodiscard]] inline bool spells( std::string_view text, std::string_view name ) noexcept
{
    for( std::size_t at = text.find( name ); at != std::string_view::npos; at = text.find( name, at + 1 ) )
    {
        const std::size_t e = at + name.size();
        if( e < text.size() && text[ e ] == '=' && ( at == 0 || !nameChar( text[ at - 1 ] ) ) ) { return true; }
    }
    return false;
}

// Every attribute name `body` spells as `name=`.
[[nodiscard]] inline std::vector<std::string_view> spelledNames( std::string_view body )
{
    std::vector<std::string_view> out;
    for( std::size_t eq = body.find( '=' ); eq != std::string_view::npos; eq = body.find( '=', eq + 1 ) )
    {
        std::size_t b = eq;
        while( b > 0 && nameChar( body[ b - 1 ] ) ) { --b; }
        if( b < eq && std::find( out.begin(), out.end(), body.substr( b, eq - b ) ) == out.end() ) { out.push_back( body.substr( b, eq - b ) ); }
    }
    return out;
}

[[nodiscard]] inline std::string firstPageLegend( std::string_view legend, const std::vector<std::size_t>& gone );   // below

// THE CLAUSES PAGE 1 SHEDS: rows of kTravels whose clause stands in `legend`, that page 1's rows (`pages[0]`) do not need and a
// later page's do — in the order they stand in `legend`.
// THE LAST-DEFINER BACKSTOP. Every attribute name is read element-blind by this repo's coverage gates (legendcoveragecheck.sh
// "ELEMENT-BLINDNESS"): `n=` spelled by the hops clause (for <h>) is the only `n=` a <d n=> on an element-form page 1 meets. So a
// clause is shed only if every name it spells stays spelled, for every page that carries the name without receiving the clause,
// by what page 1's document legend keeps. The row-line clause (forrowlines.h, written onto page 1 after paging) spells <d>'s n= too,
// but it is NOT counted: rowlinescheck (L1) pins the row-line answer decoded as the element form byte for byte, so both forms shed
// the same clauses. Tried largest clause first, so a kept clause is the smaller one; each check counts every clause shed before it.
[[nodiscard]] inline std::vector<std::size_t> shed( std::string_view legend, const std::vector<std::string_view>& pages )
{
    std::vector<std::pair<std::size_t, std::size_t>> at;   // (position in legend, row)
    for( std::size_t i = 0; i < kTravelCount && pages.size() > 1; ++i )
    {
        const std::string_view body = travelBodies()[ i ];
        if( body.empty() ) { continue; }
        const std::size_t p = clauseAt( legend, body );
        if( p != std::string_view::npos && !needs( i, pages[ 0 ] )
            && std::any_of( pages.begin() + 1, pages.end(), [ & ]( std::string_view r ) { return needs( i, r ); } ) )
        {
            at.emplace_back( p, i );
        }
    }
    std::vector<std::size_t> bySize;
    for( const auto& [ p, i ] : at ) { bySize.push_back( i ); }
    std::stable_sort( bySize.begin(), bySize.end(), []( std::size_t a, std::size_t b ) { return travelBodies()[ a ].size() > travelBodies()[ b ].size(); } );
    std::vector<std::size_t> gone;
    for( const std::size_t c : bySize )
    {
        gone.push_back( c );
        const std::string kept = firstPageLegend( legend, gone );
        bool orphans = false;
        const std::string_view body = travelBodies()[ c ];
        for( const std::string_view name : spelledNames( body ) )
        {
            const std::string carried = " " + std::string( name ) + "=\"";
            for( std::size_t k = 0; k < pages.size() && !orphans; ++k )
            {
                orphans = pages[ k ].find( carried ) != std::string_view::npos && ( k == 0 || !needs( c, pages[ k ] ) ) && !spells( kept, name );
            }
            if( orphans ) { break; }
        }
        if( orphans ) { gone.pop_back(); }
    }
    std::vector<std::size_t> out;
    for( const auto& [ p, i ] : at )
    {
        if( std::find( gone.begin(), gone.end(), i ) != gone.end() ) { out.push_back( i ); }
    }
    return out;
}

// Page 1's document legend without the shed clauses, each erased where it stands in `legend`, right to left, and the junction
// tidied: "; " doubled by the erasure is made single, and a separator the erased clause carried for the text after it ("…l=; skip
// bytes=…", the fold legend's pieces) is put back. A comment left with nothing between its markers (a clause that was a whole
// comment, graphlegend.h's value_refs one) goes with it.
[[nodiscard]] inline std::string firstPageLegend( std::string_view legend, const std::vector<std::size_t>& gone )
{
    std::vector<std::pair<std::size_t, std::size_t>> spans;   // (position, length) in `legend`
    for( const std::size_t i : gone )
    {
        const std::string_view body = travelBodies()[ i ];
        if( const std::size_t p = clauseAt( legend, body ); p != std::string_view::npos ) { spans.emplace_back( p, body.size() ); }
    }
    std::sort( spans.begin(), spans.end(), []( const auto& a, const auto& b ) { return a.first > b.first; } );
    std::string out( legend );
    for( const auto& [ p, n ] : spans )
    {
        out.erase( p, n );
        if( p >= 2 && out.compare( p - 2, 2, "; " ) == 0 && out.compare( p, 2, "; " ) == 0 ) { out.erase( p, 2 ); }
        else if( p > 0 && p < out.size() && std::string_view( " [;:" ).find( out[ p - 1 ] ) == std::string_view::npos
                 && std::string_view( "; .]-" ).find( out[ p ] ) == std::string_view::npos )
        {
            out.insert( p, "; " );
        }
    }
    for( std::size_t open = out.find( "<!--" ); open != std::string::npos; )
    {
        const std::size_t close = out.find( "-->", open + 4 );
        if( close == std::string::npos ) { break; }
        const std::string_view inner = std::string_view( out ).substr( open + 4, close - open - 4 );
        if( std::all_of( inner.begin(), inner.end(), []( char c ) { return c == ' ' || c == ';' || c == '.' || c == ':' || c == ','; } ) )
        {
            out.erase( open, close + 3 - open );
            open = out.find( "<!--", open );
            continue;
        }
        open = out.find( "<!--", close + 3 );
    }
    return out;
}

// The comment a later page carries: the shed clauses its own rows need, verbatim and in page-1 order, or empty.
[[nodiscard]] inline std::string laterPageComment( const std::vector<std::size_t>& gone, std::string_view page )
{
    const std::string rows = rowsOnly( page );
    std::string       out;
    for( const std::size_t i : gone )
    {
        if( !needs( i, rows ) ) { continue; }
        const std::string_view body = travelBodies()[ i ];
        if( out.empty() ) { out = "<!-- defined for this page, the rest on page 1"; }
        if( !( body.front() == ';' || body.front() == ' ' || out.ends_with( "; " ) ) ) { out += "; "; }
        out.append( body );
    }
    return out.empty() ? out : out + " -->";
}

}   // namespace rw::forpages::scope
