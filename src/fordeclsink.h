#pragma once
// fordeclsink.h — DECL-TWIN and DECL-SINK (precision card B14, PRECISION-LAB 11-10 §4 rules 4 and 5): a ONE-LINE OWNER-QUALIFIED
// DECLARATION row of the <sigs> block — l= equals e= (a declaration with no body: a TypeScript interface member, a .d.ts line, a C++
// in-class prototype) and n= is Owner.member / Owner::member — is a signature, not the definition an agent opens. On the graded sets
// such rows sit at ranks 1-3 (LanguageService.getCompletionsAtPosition above the services.ts body) and carry picked decoys.
//
//   DECL-TWIN: such a row whose last segment is also the name of a BODIED <sigs> <d> row of the answer (l= and e= present, unequal) is
//              printed as a tail pointer <t p="FILE" sym="NAME" r="RANK"/> in its place: the body row is the answer, the pointer keeps
//              the declaration findable. At any rank: a pointer in the first 10 answer rows lets a deeper row into them (the lab's shift
//              effect), and the lab measured that cost against the alternatives (PR body): rows past 10 only moved no top-10 Wrong; a
//              reorder that swaps the body row into the declaration's slot moved the same Wrong and gained one credited item less.
//   DECL-SINK: such a row among the first kDeclSinkRank answer rows that is not a constant (its text does not open with const / var /
//              enum / let / #define / static const / export const) and has no in= (nothing reuses it) is MOVED to just after the
//              kDeclSinkRank-th of the other <d> rows (answer row 11): reordered, never removed, so every name stays printed. Rows that
//              would not get past row 10 (fewer than kDeclSinkRank other <d> rows) stay put.
// A keep guard (SIBLING-DEMOTE's, forsiblingdemote.h) holds a row in place for both rules: K1 mem= / K7 slot_by= / slot_fields=
// (kKeepRowAttrs), K6 a <note> rides in the row, K4 the task names the row (its full name, or its last segment for a bare task word).
// DECL-TWIN runs first, DECL-SINK then reads its result (a pointer is no <d> row). Each rule's legend comment rides only when it fires
// (the twin's before its first pointer, the sink's before the moved rows). Both run where SIBLING-DEMOTE runs — the no-budget XML answer
// of CLI --for and MCP `for`; a token budget leaves the answer as shaped; --json never reaches them.
// RIPWIRE_NO_DECL_TWIN=1 / RIPWIRE_NO_DECL_SINK=1 turn each off (byte identity and the gate's twins).
#include "forsiblingdemote.h" // demote_detail::scanAnswer / AnswerRow / kKeepRowAttrs / taskNameWords, filesyms_detail::tailPointerText / leafName
#include "serialize.h" // attrOf

#include <algorithm>
#include <array>
#include <cstddef>
#include <cstdlib>
#include <string>
#include <string_view>
#include <vector>

namespace rw
{
inline constexpr std::size_t kDeclSinkRank = 10; // DECL-SINK: rows among the first 10 answer rows move to just after the 10th other <d> row

inline constexpr std::string_view kDeclTwinLegend = "<!-- decl-twin: a <t> in sigs is a one-line Owner.member declaration whose bodied same-name row is "
                                                    "in this answer, a pointer (p= file, sym= name, r= rank), not the answer -->";

inline bool declTwinOn()
{
    return std::getenv( "RIPWIRE_NO_DECL_TWIN" ) == nullptr;
}
inline bool declSinkOn()
{
    return std::getenv( "RIPWIRE_NO_DECL_SINK" ) == nullptr;
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
// The row's printed signature text opens a constant (the <doc> child and leading blanks aside).
inline bool constantRow( std::string_view answer, const AnswerRow& r )
{
    std::string_view body = answer.substr( r.at, r.end - r.at );
    const std::size_t open = body.find( '>' );
    body = open == std::string_view::npos ? std::string_view() : body.substr( open + 1 );
    if( body.starts_with( "<doc>" ) )
    {
        const std::size_t docEnd = body.find( "</doc>" );
        body = docEnd == std::string_view::npos ? std::string_view() : body.substr( docEnd + 6 );
    }
    while( !body.empty() && ( body.front() == ' ' || body.front() == '\t' ) )
    {
        body.remove_prefix( 1 );
    }
    static constexpr std::array<std::string_view, 7> kConstOpen = { "const", "var", "enum", "#define", "static const", "let ", "export const" };
    return std::ranges::any_of( kConstOpen, [&]( std::string_view k ) { return body.starts_with( k ); } );
}
inline std::string rowName( const AnswerRow& r )
{
    return filesyms_detail::unescapeXmlAttr( attrOf( r.attrs, "n" ) );
}

// DECL-SINK: the answer with each sinking row moved past the kDeclSinkRank-th other <d> row; "" when none moves.
inline std::string sinkDeclRows( std::string_view task, std::string_view answer )
{
    const AnswerScan scan = demote_detail::scanAnswer( answer );
    const std::vector<std::string_view> words = demote_detail::taskNameWords( task );
    std::vector<const AnswerRow*> sink;
    const AnswerRow* after = nullptr; // the kDeclSinkRank-th <d> row that stays
    std::size_t stay = 0;
    for( const AnswerRow& r : scan.rows )
    {
        if( r.tag != 'd' )
        {
            continue;
        }
        const std::string name = rowName( r );
        if( r.pos <= kDeclSinkRank && oneLineOwnerDecl( r, name ) && attrOf( r.attrs, "in" ).empty() && !constantRow( answer, r )
            && !keptRow( r, name, words ) )
        {
            sink.push_back( &r );
        }
        else if( ++stay == kDeclSinkRank )
        {
            after = &r;
            break;
        }
    }
    if( sink.empty() || after == nullptr || !after->inSigs )
    {
        return {};
    }
    std::string out, moved;
    std::size_t from = 0;
    for( const AnswerRow* r : sink )
    {
        out.append( answer.substr( from, r->at - from ) );
        moved.append( answer.substr( r->at, r->end - r->at ) );
        from = r->end;
    }
    out.append( answer.substr( from, after->end - from ) );
    out += sink.size() == 1 ? "<!-- decl-sink: the next <d> row is a one-line Owner.member declaration"
                            : "<!-- decl-sink: the next " + std::to_string( sink.size() ) + " <d> rows are one-line Owner.member declarations";
    out += " moved down from the first 10 answer rows (r= keeps its rank; none removed) -->";
    out += moved;
    return out.append( answer.substr( after->end ) );
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

// DECL-TWIN then DECL-SINK over the answer as the earlier post-passes left it: `edited` holds those passes' bytes ("" when they left
// `answer` unchanged) and, when a rule fires, its result. Not priced (the caller re-prices the root once on the final bytes). `held`
// (a token budget) leaves the answer as shaped. CLI shapedForFileSymsAnswer and MCP insertFileSyms both call this, after SIBLING-DEMOTE.
inline void declRowsInto( std::string_view task, std::string_view answer, std::string& edited, bool held )
{
    if( held )
    {
        return;
    }
    const auto keep = [&]( std::string next )
    {
        if( !next.empty() )
        {
            edited = std::move( next );
        }
    };
    if( declTwinOn() )
    {
        keep( decl_detail::pointDeclTwins( task, edited.empty() ? answer : std::string_view( edited ) ) );
    }
    if( declSinkOn() )
    {
        keep( decl_detail::sinkDeclRows( task, edited.empty() ? answer : std::string_view( edited ) ) );
    }
}
} // namespace rw
