#pragma once
// fordemoteall.h — DEMOTE-ALL-DIALECTS (card B26): SIBLING-DEMOTE (forsiblingdemote.h) and DECL-TWIN (fordecltwin.h) in every dialect
// of the --for answer, so one question gets one answer shape:
//   - the no-budget XML answer (CLI --for and MCP `for`): the post-pass after <syms> renders, as before (demoteAndPointRowsInto);
//   - a SOFT TARGET (CLI --token-budget, MCP budget_tokens): the rules run on the rendered <sigs> block BEFORE the rows are settled,
//     read with the rows and hop callees rendered around it, and the bytes they free buy rows past the cut (refillRowsForDemote): the
//     rows stay a rank prefix, and an answer never ships fewer rows than its undemoted twin at the same target;
//   - --json: the same rules over the "sigs" array (one row object per <d> row), and a demoted row becomes the pointer object
//     {"pointer":"demote"|"decl-twin","p":FILE,"sym":NAME,"r":RANK} in its place (the XML <t p= sym= r=/>), budget or not.
// The rules read only what each dialect's answer carries (they are rules over the answer's own rows): --json and a budgeted answer
// print no mem= / same_as= / slot_by= (the default regime's XML splices) and a budgeted or MCP answer no <h> hop rows, so the
// guards those feed (K1, K5, K7, K2) hold nothing there. RIPWIRE_NO_SIBLING_DEMOTE=1 / RIPWIRE_NO_DECL_TWIN=1 turn each rule off in
// every dialect.
#include "fordecltwin.h" // demoteAndPointRowsInto, siblingDemoteOn, declTwinOn, filesyms_detail::unescapeXmlAttr
#include "memberowner.h" // MemberOwners / qualifiedMemberName: the row's n= as the XML dialect spells it
#include "infra/jsonesc.h" // jsonesc::appendUtf8
#include "serialize.h" // attrOf, jsonStr

#include <span>

#include <algorithm>
#include <cstddef>
#include <cstdint>
#include <string>
#include <string_view>
#include <vector>

namespace rw
{
inline bool demoteRulesOn()
{
    return siblingDemoteOn() || declTwinOn();
}

// The rules over `block` (the <sigs> block of an answer still being assembled), read with `before` and `after` (the rows and hop rows
// rendered around it, in answer order); "" when no row moves. Both rules move <sigs> rows only, so the bytes around the block come
// back unchanged and the block is the edited text between them.
inline std::string demoteAndPointBlock( const IngestResult& ing, const Graph& g, std::string_view task, std::string_view before, std::string_view block,
                                        std::string_view after )
{
    if( !demoteRulesOn() )
    {
        return {};
    }
    std::string context;
    context.reserve( before.size() + block.size() + after.size() );
    context.append( before ).append( block ).append( after );
    std::string edited;
    demoteAndPointRowsInto( ing, g, task, context, edited, /*held=*/false, DemoteRegime::Budgeted ); // a soft target's <sigs>: K8 holds
    if( edited.empty() )
    {
        return {};
    }
    ASSUME( edited.size() >= before.size() + after.size() && edited.starts_with( before ) && edited.ends_with( after ),
            "demoteAndPointBlock: the rules rewrite <sigs> rows only" );
    return edited.substr( before.size(), edited.size() - before.size() - after.size() );
}

// A soft target's rows past the cut get the bytes the rules free: `pointed` is the rules' result on the rendered block (`block()`), and
// while rows were cut (`rowsCut()`) and the rules shrink the block, the rows are rendered again at `baseRowDrop` plus the bytes the
// rules free on the latest render (`renderAt( budget )`: false when that render failed, the block then stays as it was). The freed
// bytes are those of the whole latest render, so the rows that ship after the rules cost about `baseRowDrop`; a render that serves
// no more rows than the one before stops the walk. Returns the rules' result on the block as it finally is ("" when none moves).
inline constexpr int kDemoteRefillPasses = 3;
template<class Block, class RowsCut, class RowsShown, class RenderAt, class Point>
inline std::string refillRowsForDemote( std::size_t baseRowDrop, const Block& block, const RowsCut& rowsCut, const RowsShown& rowsShown,
                                        const RenderAt& renderAt, const Point& point )
{
    std::string pointed = point();
    for( int pass = 0; pass < kDemoteRefillPasses && !pointed.empty() && rowsCut() && pointed.size() < block().size(); ++pass )
    {
        const std::size_t shownBefore = rowsShown();
        if( !renderAt( baseRowDrop + ( block().size() - pointed.size() ) ) )
        {
            break;
        }
        pointed = point();
        if( rowsShown() <= shownBefore )
        {
            break;
        }
    }
    return pointed;
}

namespace demote_json_detail
{
// The [at, end) byte spans of the objects of a JSON array of objects (`arr` from its `[` to its `]`), by brace depth outside strings.
struct ObjectSpan
{
    std::size_t at = 0, end = 0;
};
inline std::vector<ObjectSpan> arrayObjects( std::string_view arr )
{
    std::vector<ObjectSpan> out;
    int depth = 0;
    bool inString = false;
    std::size_t at = 0;
    for( std::size_t i = 0; i < arr.size(); ++i )
    {
        const char c = arr[i];
        if( inString )
        {
            i += c == '\\' ? 1 : 0;
            inString = c != '"';
            continue;
        }
        inString = c == '"';
        if( c == '{' && depth++ == 0 )
        {
            at = i;
        }
        else if( c == '}' && depth > 0 && --depth == 0 )
        {
            out.push_back( { .at = at, .end = i + 1 } );
        }
    }
    return out;
}
// The raw value text of the object's TOP-LEVEL key `key` (a string with its quotes, still JSON-escaped; a number as written); "" when
// the object has no such key. Keys of nested objects and arrays are skipped.
inline std::string_view topValue( std::string_view obj, std::string_view key )
{
    int depth = 0;
    for( std::size_t i = 0; i < obj.size(); ++i )
    {
        const char c = obj[i];
        if( c == '"' )
        {
            std::size_t close = i + 1;
            while( close < obj.size() && obj[close] != '"' )
            {
                close += obj[close] == '\\' ? 2 : 1;
            }
            if( close >= obj.size() )
            {
                return {};
            }
            const bool isKey = depth == 1 && close + 1 < obj.size() && obj[close + 1] == ':';
            if( isKey && obj.substr( i + 1, close - i - 1 ) == key )
            {
                const std::size_t v = close + 2;
                if( v < obj.size() && obj[v] == '"' )
                {
                    std::size_t vend = v + 1;
                    while( vend < obj.size() && obj[vend] != '"' )
                    {
                        vend += obj[vend] == '\\' ? 2 : 1;
                    }
                    return vend < obj.size() ? obj.substr( v, vend - v + 1 ) : std::string_view();
                }
                std::size_t vend = v;
                while( vend < obj.size() && obj[vend] != ',' && obj[vend] != '}' && obj[vend] != ']' )
                {
                    ++vend;
                }
                return obj.substr( v, vend - v );
            }
            i = close;
            continue;
        }
        depth += c == '{' || c == '[' ? 1 : c == '}' || c == ']' ? -1 : 0;
    }
    return {};
}
inline std::uint32_t hex4( std::string_view s )
{
    std::uint32_t v = 0;
    for( const char c : s )
    {
        v = v * 16 + std::uint32_t( c >= '0' && c <= '9' ? c - '0' : c >= 'a' && c <= 'f' ? c - 'a' + 10 : c >= 'A' && c <= 'F' ? c - 'A' + 10 : 0 );
    }
    return v;
}
// A JSON string value (with its quotes) decoded: the answer's own escapes (\" \\ \/ \b \f \n \r \t \uXXXX, a surrogate pair joined).
inline std::string unquote( std::string_view q )
{
    const std::string_view s = q.size() >= 2 && q.front() == '"' && q.back() == '"' ? q.substr( 1, q.size() - 2 ) : q;
    std::string out;
    out.reserve( s.size() );
    for( std::size_t i = 0; i < s.size(); ++i )
    {
        if( s[i] != '\\' || i + 1 >= s.size() )
        {
            out += s[i];
            continue;
        }
        const char e = s[++i];
        if( e == 'u' && i + 4 < s.size() )
        {
            std::uint32_t cp = hex4( s.substr( i + 1, 4 ) );
            i += 4;
            if( cp >= 0xD800 && cp < 0xDC00 && i + 6 < s.size() && s[i + 1] == '\\' && s[i + 2] == 'u' )
            {
                const std::uint32_t lo = hex4( s.substr( i + 3, 4 ) );
                cp = lo >= 0xDC00 && lo < 0xE000 ? 0x10000 + ( ( cp - 0xD800 ) << 10 ) + ( lo - 0xDC00 ) : cp;
                i += lo >= 0xDC00 && lo < 0xE000 ? 6 : 0;
            }
            jsonesc::appendUtf8( out, cp );
            continue;
        }
        out += e == 'n' ? '\n' : e == 't' ? '\t' : e == 'r' ? '\r' : e == 'b' ? '\b' : e == 'f' ? '\f' : e;
    }
    return out;
}
inline std::string xmlAttr( std::string_view v )
{
    std::string out;
    for( const char c : v )
    {
        out += c == '&' ? "&amp;" : c == '<' ? "&lt;" : c == '>' ? "&gt;" : c == '"' ? "&quot;" : std::string( 1, c );
    }
    return out;
}
// One row object as the <d> row the XML dialect prints for it: n= (`name`, owner-qualified as the XML row spells it; the JSON "n" is
// the bare name beside "sc") p= l= e= r= sc= (the attributes the rules read), the signature as its text (K8), and a <note> child when
// it carries notes (its own or its file's: the XML row carries both as <note> children).
inline std::string xmlRowOf( std::string_view obj, std::string_view name )
{
    std::string row = "<d n=\"" + xmlAttr( name ) + "\"";
    for( const std::string_view key : { "p", "l", "e", "r", "sc" } )
    {
        const std::string_view v = topValue( obj, key );
        if( !v.empty() )
        {
            row.append( " " ).append( key ).append( "=\"" ).append( xmlAttr( v.front() == '"' ? unquote( v ) : std::string( v ) ) ).append( "\"" );
        }
    }
    const bool noted = !topValue( obj, "notes" ).empty() || !topValue( obj, "file_notes" ).empty();
    const std::string_view sig = topValue( obj, "sig" ); // (K8) the printed signature, the row text a task term may hit
    row.append( ">" ).append( sig.empty() || sig.front() != '"' ? std::string() : xmlAttr( unquote( sig ) ) );
    return row + ( noted ? "<note k=\"json\"/></d>" : "</d>" ); // (K6) scanAnswer reads a note as "<note " (an attribute run)
}
// The ranks (r= text) of the <t> pointers inside the answer's <sigs>.
inline std::vector<std::string> pointerRanks( std::string_view answer )
{
    std::vector<std::string> ranks;
    for( std::string_view rest = answer; rest.contains( "<t " ); )
    {
        rest.remove_prefix( rest.find( "<t " ) + 2 ); // keep the space before the first attribute
        ranks.emplace_back( attrOf( rest.substr( 0, rest.find( '>' ) ), "r" ) );
    }
    return ranks;
}
} // namespace demote_json_detail

// --json: the "sigs" array (`sigsJson`, from its `[` to its `]`) with each row the rules pick (read over the rows as the XML dialect
// prints them) rewritten as {"pointer":RULE,"p":FILE,"sym":NAME,"r":RANK} (sym= the owner-qualified name, as the XML pointer's);
// "" when no row moves. `rowIds` are the rows' symbols in array order (packSignaturesJson's shown ids): an array they do not match
// row for row, or a row with no "r" to tell it by, is left as shaped.
inline std::string demoteJsonRows( const IngestResult& ing, const Graph& g, std::string_view task, std::string_view sigsJson, std::span<const NodeId> rowIds,
                                   DemoteRegime regime )
{
    using namespace demote_json_detail;
    if( !demoteRulesOn() )
    {
        return {};
    }
    const std::vector<ObjectSpan> objects = arrayObjects( sigsJson );
    if( objects.size() != rowIds.size() )
    {
        return {};
    }
    const MemberOwners owners( ing );
    std::vector<std::string> names;
    std::string xml = "<sigs>";
    for( std::size_t k = 0; k < objects.size(); ++k )
    {
        const std::string_view obj = sigsJson.substr( objects[k].at, objects[k].end - objects[k].at );
        if( topValue( obj, "r" ).empty() || std::size_t( rowIds[k] ) >= ing.symbols.size() )
        {
            return {};
        }
        names.push_back( qualifiedMemberName( owners, ing.symbols[rowIds[k]] ) );
        xml += xmlRowOf( obj, names.back() );
    }
    xml += "</sigs>";
    // the two rules one after the other, as demoteAndPointRowsInto runs them, so each row's pointer names the rule that moved it
    std::string demoted = siblingDemoteOn() ? demote_detail::demoteSiblingRows( ing, g, task, xml, regime ) : std::string();
    const std::vector<std::string> byDemote = pointerRanks( demoted );
    std::string twinned = declTwinOn() ? decl_detail::pointDeclTwins( task, demoted.empty() ? std::string_view( xml ) : std::string_view( demoted ) ) : std::string();
    const std::vector<std::string> all = pointerRanks( twinned.empty() ? demoted : twinned );
    if( all.empty() )
    {
        return {};
    }
    std::string out;
    std::size_t from = 0;
    for( std::size_t k = 0; k < objects.size(); ++k )
    {
        const ObjectSpan&      o   = objects[k];
        const std::string_view obj = sigsJson.substr( o.at, o.end - o.at );
        const std::string_view r = topValue( obj, "r" );
        const auto has = [&]( const std::vector<std::string>& ranks ) { return std::ranges::contains( ranks, std::string_view( r ) ); };
        if( !has( all ) )
        {
            continue;
        }
        out.append( sigsJson.substr( from, o.at - from ) );
        out.append( "{\"pointer\":\"" ).append( has( byDemote ) ? "demote" : "decl-twin" ).append( "\",\"p\":" ).append( topValue( obj, "p" ) );
        out.append( ",\"sym\":\"" ).append( jsonStr( names[k] ) ).append( "\",\"r\":" ).append( r ).append( "}" );
        from = o.end;
    }
    return out.append( sigsJson.substr( from ) );
}
} // namespace rw
