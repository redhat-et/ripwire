#pragma once
// fordecltwin.h — DECL-TWIN (precision card B14, PRECISION-LAB 11-10 §4 rule 4): a ONE-LINE OWNER-QUALIFIED DECLARATION row of the
// <sigs> block — l= equals e= (a declaration with no body: a TypeScript interface member, a .d.ts line, a C++ in-class prototype) and
// n= is Owner.member / Owner::member — is a signature, not the definition an agent opens. On the graded sets such rows sit at ranks
// 1-3 (LanguageService.getCompletionsAtPosition above the services.ts body) and carry picked decoys.
//
// Such a row whose last segment is also the name of a BODIED <sigs> <d> row of the answer (l= and e= present, unequal) is printed as a
// tail pointer <t p="FILE" sym="NAME" r="RANK"/> in its place: the body row is the answer, the pointer keeps the declaration findable.
// At any rank: a pointer in the first 10 answer rows lets a deeper row into them (the lab's shift effect), and the lab measured that
// cost against the alternatives (PR body): rows past 10 only moved no top-10 Wrong; a reorder that swaps the body row into the
// declaration's slot moved the same Wrong and gained one credited item less. (The lab's rule 5, DECL-SINK — move such rows past answer
// row 10 — was built and measured beside it and dropped: on the post-SIBLING-DEMOTE answers it raised top-10 Wrong.)
// A keep guard (SIBLING-DEMOTE's, forsiblingdemote.h) holds a row in place: K1 mem= / K7 slot_by= / slot_fields= (kKeepRowAttrs), K6 a
// <note> rides in the row, K4 the task names the row (its full name, or its last segment for a bare task word). The legend comment
// rides before the first pointer, only when the rule fires. It runs where SIBLING-DEMOTE runs — the no-budget XML answer of CLI --for
// and MCP `for`; a token budget leaves the answer as shaped; --json never reaches it. RIPWIRE_NO_DECL_TWIN=1 turns it off (byte
// identity and the gate's twin).
#include "forsiblingdemote.h" // demote_detail::scanAnswer / AnswerRow / kKeepRowAttrs / taskNameWords, filesyms_detail::tailPointerText / leafName
#include "serialize.h" // attrOf

#include <algorithm>
#include <cstddef>
#include <cstdlib>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

namespace rw
{
inline constexpr std::string_view kDeclTwinLegend = "<!-- decl-twin: a <t> in sigs is a one-line Owner.member declaration whose bodied same-name row is "
                                                    "in this answer, a pointer (p= file, sym= name, r= rank), not the answer -->";

inline bool declTwinOn()
{
    return std::getenv( "RIPWIRE_NO_DECL_TWIN" ) == nullptr;
}

namespace decl_detail
{
using demote_detail::AnswerRow;
using demote_detail::AnswerScan;

// `s` with `::` and `#` spelled `.`: Owner::name, Owner#name and Owner.name compare equal.
inline std::string dotted( std::string_view s )
{
    std::string out;
    for( std::size_t i = 0; i < s.size(); ++i )
    {
        const bool scope = s[i] == ':' && i + 1 < s.size() && s[i + 1] == ':';
        out += scope || s[i] == '#' ? '.' : s[i];
        i += scope ? 1 : 0;
    }
    return out;
}
// K4 (task-named): a qualified task word names the row when the row's name is it or ends with it (`ts.LanguageService.x` for
// `LanguageService.x`); a bare task word names the row's last segment. `Completions.getCompletionsAtPosition` does not name
// LanguageService.getCompletionsAtPosition.
inline bool taskNamesRow( const std::vector<std::string_view>& words, std::string_view name )
{
    const std::string_view leaf = filesyms_detail::leafName( name );
    const std::string full = dotted( name );
    return std::ranges::any_of( words, [&]( std::string_view w )
                                {
                                    if( filesyms_detail::leafName( w ).size() == w.size() )
                                    {
                                        return w == leaf;
                                    }
                                    const std::string q = dotted( w );
                                    return full == q || full.ends_with( "." + q );
                                } );
}

inline bool ownerQualified( std::string_view name )
{
    const std::size_t sep = std::min( name.find( '.' ), name.find( "::" ) );
    return sep != std::string_view::npos && sep != 0;
}
// A one-line owner-qualified declaration <d> row of <sigs>: l= present and equal to e=, n= Owner.member / Owner::member.
inline bool oneLineOwnerDecl( const AnswerRow& r, std::string_view name )
{
    const std::string_view l = attrOf( r.attrs, "l" );
    return r.tag == 'd' && r.inSigs && !l.empty() && l == attrOf( r.attrs, "e" ) && ownerQualified( name );
}
// A row a keep guard holds in place: K1/K7 (mem=, slot_by=, slot_fields=), K6 (a <note>), K4 (the task names it).
inline bool keptRow( const AnswerRow& r, std::string_view name, const std::vector<std::string_view>& words )
{
    const auto carries = [&]( std::string_view attr ) { return r.attrs.contains( attr ); };
    return r.noted || std::ranges::any_of( demote_detail::kKeepRowAttrs, carries ) || taskNamesRow( words, name );
}
inline std::string rowName( const AnswerRow& r )
{
    return filesyms_detail::unescapeXmlAttr( attrOf( r.attrs, "n" ) );
}

// DECL-TWIN: the answer with each twinned declaration row rewritten as a pointer; "" when none is.
inline std::string pointDeclTwins( std::string_view task, std::string_view answer )
{
    const AnswerScan scan = demote_detail::scanAnswer( answer );
    const std::vector<std::string_view> words = demote_detail::taskNameWords( task );
    std::vector<std::string> bodied; // last segments of the bodied <sigs> <d> rows (a <shortkey> rung's <d n= l=/> names, it is no body)
    for( const AnswerRow& r : scan.rows )
    {
        const std::string_view l = attrOf( r.attrs, "l" ), e = attrOf( r.attrs, "e" );
        if( r.tag == 'd' && r.inSigs && !l.empty() && !e.empty() && l != e )
        {
            bodied.emplace_back( filesyms_detail::leafName( rowName( r ) ) );
        }
    }
    std::ranges::sort( bodied );
    std::vector<filesyms_detail::TailPointerSpan> spans;
    for( const AnswerRow& r : scan.rows )
    {
        const std::string name = rowName( r );
        if( oneLineOwnerDecl( r, name ) && !keptRow( r, name, words )
            && std::ranges::binary_search( bodied, filesyms_detail::leafName( name ) ) )
        {
            spans.push_back( { .at = r.at, .end = r.end, .p = attrOf( r.attrs, "p" ), .sym = attrOf( r.attrs, "n" ), .rank = attrOf( r.attrs, "r" ) } );
        }
    }
    return filesyms_detail::tailPointerText( answer, spans, kDeclTwinLegend );
}
} // namespace decl_detail

// DECL-TWIN over the answer as the earlier post-passes left it: `edited` holds those passes' bytes ("" when they left `answer`
// unchanged) and, when the rule fires, its result. Not priced (the caller re-prices the root once on the final bytes). `held` (a token
// budget) leaves the answer as shaped. CLI shapedForFileSymsAnswer and MCP insertFileSyms both call this, after SIBLING-DEMOTE.
inline void declTwinInto( std::string_view task, std::string_view answer, std::string& edited, bool held )
{
    if( held || !declTwinOn() )
    {
        return;
    }
    std::string next = decl_detail::pointDeclTwins( task, edited.empty() ? answer : std::string_view( edited ) );
    if( !next.empty() )
    {
        edited = std::move( next );
    }
}
} // namespace rw
