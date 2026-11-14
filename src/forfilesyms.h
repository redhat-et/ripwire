#pragma once
// forfilesyms.h — K-WRONGSYM (cause K "right file, wrong symbol"): a --for answer that shows the right FILE often shows the wrong
// SYMBOL of it — the head row is a neighbour that ranked on body or doc text, while the function the task needs sits a few lines
// away, unnamed. <syms> names a few of those unshown symbols, one row each (Scope.name and file:line, no body), after the
// ordinary answer. (CLI src/verbs_for.h appendForFileSyms, MCP `for` src/mcpverbs.h forTaskText — one renderer.)
//
// WHICH FILES. The answer's own shown files: the distinct p= of its <d>, <b> and <t> rows in answer order, the first
// kForFileSymsFiles. THE ANSWER IS THE BYTES AS EMITTED: the CLI hands the renderer everything the run wrote before this block (every
// section and every trailing block: decl rows, graph_verb, re-exports, the short-key ladder, the literal anchor, dotted strings, --with-graph),
// the MCP surface its whole document, so a block added later cannot drift out of a hand-kept list. A candidate is an indexed definition of one of
// the files (no doc heading or data key, no module scope, no field; a function-local def counts: TypeScript's checker.ts holds its API inside
// one function) that the answer does not name: its NAME is not a token of the answer (identifier runs, with the `#`/`$`/`@`/`~` before and the
// `?`/`!` after, since a stored name keeps them; any other spelling is searched for in the text), and no shown row stands on its (file, line).
// A C/C++ header declaration and its definition elsewhere are one candidate (the definition).
// TWO RULES, each row says which picked it (by=):
//   by="name"   its name's subtokens share a word with the task (identifier split, light stem, stopwords out); most shared first.
//   by="callee" a definition NAMED like a head row (the first kForFileSymsHeadRows <d> rows, any file) calls, in the index's graph,
//               a definition NAMED like it: the shown row or a namesake, since the row's name is what the answer gave (Stage 0: NullInjector.get is shown, the
//               R3Injector.get beside it is the one that calls augmentRuntimeError). Most head names first. The hedge reuses the call
//               rows' spellings (graphlegend.h): plain only when the shown row itself calls this very definition over an evidence-bound
//               edge; prov="split" when that call is one arm of a split; via="name" otherwise (a namesake's call, a call to a namesake
//               of it, or one bound by name alone).
// Ties: fan-in (graph callers) desc, then shown-file order, then name. kForFileSymsRowsPerRule rows per rule (a runaway cap). The constants
// (6 files, 8 head rows, 3 rows per rule) are in the legends, so the open tag prints files= / head= only when fewer were read and
// name_total= / callee_total= / files_total= only when a cap cut; every printed attribute is in kForFileSymsAttrs, which both legends must
// define (static_assert). A row in a test or fixture file or scope carries test="1" (a lead, ranked like any other). A name both rules pick
// prints once, as by="name".
// A THIRD RULE, by a fact and not by rank (VR-BINDER-ROW):
//   by="bind"   a function that stores a head row's definition AS A VALUE into a slot: the callers' <vr> row of that definition
//               (valuerefindex.h, any language whose value-ref pass records into=) names its enclosing symbol (in_id=) and the slot
//               (into=): a returned object literal (`return { isDeclarationVisible }`), a dict or table entry, a field, a variable. The row
//               carries into= as the <vr> row spells it, and may come from ANY file (the bind is a fact about the head, not about a shown
//               file). An argument pass or a parameter default (`#i`/`#kw` keys) and a decorator (`into=@NAME`) are no slot bind; a
//               self-store, a name the answer already gives and a name another rule picked are skipped. kForFileSymsBindPerHead rows per
//               head row (bind_total= the distinct binders when a cap cut). Its legend clause rides only beside a printed bind row, and
//               the value index is built only when a Value reference names a head row: a head nobody binds pays one scan and no byte.
// PRESENT-ONLY: no candidate scores, no block. A token budget holds it (held="budget", next= the same --for call without the
// budget; the stub carries its own short legend), and so does a CLI run that could not buffer its bytes (held="uncaptured"). The block is outside
// est_tokens, after every byte of the ordinary answer: no auto-served body pays for it. XML only: --json, columnar, --candidates and multi-root answers carry none.
#include "filetext.h" // FileTextCache — by="init" reads a head's file for the declaration of its name
#include "filter.h" // isTestSymbol — the test/fixture mark on a row
#include "infra/Diagnostics.h" // DISCLOSE — by="init"'s window cut (InitWindowCut)
#include "infra/namesplit.h" // namesplit::isIdentChar — the one identifier-byte test
#include "infra/sortutil.h" // svLess: the byte order every string_view sort/search here uses
#include "graph.h" // Graph::outOff / outTargets / outNameOnly / outProv / inEdges, edgeKindByte, kEdgeName
#include "lexical.h" // subtokens — the one identifier splitter
#include "memberowner.h" // MemberOwners, qualifiedMemberName — the Scope.name spelling every row kind shares
#include "model.h"
#include "nextverb.h" // nextFlag / nextAttrXml
#include "quality.h" // isHeaderPath — a C/C++ declaration lives in a header
#include "serialize.h" // escapeXml
#include "valuerefindex.h" // ValueRefIndex::narrowFor / valueRefsTo, vrBindLess — by="bind" reads the callers' <vr> rows

#include <algorithm>
#include <array>
#include <bit>
#include <charconv>
#include <cstddef>
#include <cstdint>
#include <cstdlib>
#include <format>
#include <span>
#include <string>
#include <string_view>
#include <ranges>
#include <tuple>
#include <type_traits>
#include <utility>
#include <vector>

namespace rw
{
// Runaway guards and reading scope (knob census ADDENDUM 2026-11-05, lane k-wrongsym); each is said on the block or in its legend.
inline constexpr std::size_t kForFileSymsFiles = 6; // shown files whose symbols are candidates (files_total= when more were shown)
inline constexpr std::size_t kForFileSymsHeadRows = 8; // head <d> rows whose callees by="callee" reads (head= when fewer)
inline constexpr std::size_t kForFileSymsRowsPerRule = 3; // rows per rule (name_total= / callee_total= when cut)
inline constexpr std::size_t kForFileSymsBindPerHead = 2; // by="bind" rows per head <d> row (bind_total= when cut)
inline constexpr std::size_t kForFileSymsInitHeadRows = 5; // head <d> rows (plus the re-export walk's <def> rows) by="init" reads
inline constexpr std::size_t kForFileSymsInitSpan = 200; // bytes after a declaration's `=` read for its initialiser call (a runaway guard)

inline bool forFileSymsOn()
{
    return std::getenv( "RIPWIRE_NO_FILE_SYMS" ) == nullptr;
}

// RIPWIRE_NO_BIND_ROWS (any value) drops the by="bind" rule: the A/B handle.
inline bool forFileSymsBindOn()
{
    return std::getenv( "RIPWIRE_NO_BIND_ROWS" ) == nullptr;
}

// RIPWIRE_NO_INIT_ROWS (any value) drops the by="init" rule (CONST-INIT-CALLEE): the A/B handle.
inline bool forFileSymsInitOn()
{
    return std::getenv( "RIPWIRE_NO_INIT_ROWS" ) == nullptr;
}

inline constexpr std::string_view kForFileSymsLegend =
    "<!-- ripwire for syms: leads to read, not the answer. Symbols of the answer's first 6 shown files that it does not name, one <y> row each (p=file:line, n= the owner-qualified name; test=\"1\": a test or fixture symbol; no body, the expand verb serves one): "
    "by=\"name\" its name shares a task word, by=\"callee\" a definition named like one of the first 8 <d> rows calls one named like it (via=\"name\": "
    "no evidence-bound call from the shown row to this definition, only a namesake's call, a call to a namesake or one bound by name alone; prov=\"split\": one arm of a split call); "
    "three rows per rule: name_total= and callee_total= the candidates when a rule had more, files_total= the shown files when more than 6; files= head= the files or <d> rows read when fewer than 6 or 8; "
    "not in est_tokens -->";
inline constexpr std::string_view kForFileSymsLegendCompact =
    "<!-- syms: leads, not the answer: first 6 shown files' symbols it lacks, p=file:line n=Owner.name; by=name task word, by=callee a head <d> row calls it "
    "(via=name name-only, prov=split one arm); test=1 test code; name_total= callee_total= files_total= cut by the 3-row, 6-file cap; files= head= if under 6, 8 -->";
// SIZE-1: the clauses of the two legends above that define an attribute a block may not print, erased from a block without it
// (blockXml). Each is spelled exactly as its legend carries it.
inline constexpr std::string_view kForFileSymsTestClause = "test=\"1\": a test or fixture symbol; ";
inline constexpr std::string_view kForFileSymsTestClauseCompact = "test=1 test code; ";
inline constexpr std::string_view kForFileSymsReadClause = "; files= head= the files or <d> rows read when fewer than 6 or 8";
inline constexpr std::string_view kForFileSymsReadClauseCompact = "; files= head= if under 6, 8";
static_assert( kForFileSymsLegend.contains( kForFileSymsTestClause ) && kForFileSymsLegend.contains( kForFileSymsReadClause )
                   && kForFileSymsLegendCompact.contains( kForFileSymsTestClauseCompact ) && kForFileSymsLegendCompact.contains( kForFileSymsReadClauseCompact ),
               "the present-only syms clauses are spelled as their legends carry them" );
// The held stub's own legend (both dialects): the reader meets held= and next= beside the tag, not in the block legend it replaces.
inline constexpr std::string_view kForFileSymsHeldLegend =
    "<!-- ripwire for syms: held=\"budget\": a token budget is set, so the symbol rows of the shown files are not printed; next= repeats this call "
    "without the budget, which prints them; held=\"uncaptured\": the answer's own bytes could not be buffered to read, so no rows are printed; not in est_tokens -->";

// The by="bind" clause, present-only: spliced before the legend's closing ` -->` when a bind row prints (the legend stays one comment,
// the one the reader meets right before <syms>). One clause each, no "--" (the legend is an XML comment).
inline constexpr std::string_view kForFileSymsBindLegend =
    "; by=\"bind\" a function that stores one of the first 8 <d> rows as a value into a slot (a returned object, a table or dict entry, a field, "
    "a variable, any file): into= the slot as the callers' <vr> row spells it, a binding not a call, two per head row, bind_total= the binders when more";
inline constexpr std::string_view kForFileSymsBindLegendCompact =
    "; by=bind stores a head <d> row as a value into slot into= (any file, not a call), two per head row, bind_total= when more";
// The by="init" clause, present-only like by="bind".
inline constexpr std::string_view kForFileSymsInitLegend =
    "; by=\"init\" the definition a module-level declaration of a head row's name calls to make its value (`const X = f(...)`, `X = f(...)`, for one of the first 5 <d> rows "
    "or the re-export walk's def row, any file): of= that name, at= the declaration's file:line, a resolved call at file scope, one per name, its `(` "
    "within 200 bytes of the `=` (init_cut= the declarations whose initialiser ran past those 200 bytes unread)";
inline constexpr std::string_view kForFileSymsInitLegendCompact =
    "; by=init a module-level declaration of head name of= (at=file:line, `X = f(...)`) calls it to make its value, one per name, `(` within 200 bytes "
    "of `=` (init_cut= ran past them unread)";
inline constexpr std::string_view kLegendClose = " -->";

// Every attribute <syms> and its <y> rows can print (blockXml's count() names and its row hedges; p= n= are the core row keys), and the
// held stub's: each legend that rides beside them spells it `name=` (the legendcoveragecheck predicate), checked at compile time.
inline constexpr std::array<std::string_view, 9> kForFileSymsAttrs { "files", "files_total", "head", "name_total", "callee_total", "by", "via", "prov", "test" };
inline constexpr std::array<std::string_view, 2> kForFileSymsHeldAttrs { "held", "next" };
inline constexpr std::array<std::string_view, 3> kForFileSymsBindAttrs { "by", "into", "bind_total" };
inline constexpr std::array<std::string_view, 4> kForFileSymsInitAttrs { "by", "of", "at", "init_cut" };
template<std::size_t N>
consteval bool legendDefinesAll( std::string_view legend, const std::array<std::string_view, N>& attrs )
{
    const auto word = []( char c )
    { return ( c >= 'a' && c <= 'z' ) || ( c >= 'A' && c <= 'Z' ) || ( c >= '0' && c <= '9' ) || c == '_' || c == ':' || c == '.' || c == '-'; };
    for( const std::string_view a : attrs )
    {
        bool found = false;
        for( std::size_t at = legend.find( a ); at != std::string_view::npos && !found; at = legend.find( a, at + 1 ) )
        {
            const std::size_t end = at + a.size();
            found = ( at == 0 || !word( legend[at - 1] ) ) && end < legend.size() && legend[end] == '=';
        }
        if( !found )
        {
            return false;
        }
    }
    return true;
}
static_assert( kForFileSymsFiles == 6 && kForFileSymsHeadRows == 8 && kForFileSymsRowsPerRule == 3, "the legends spell these constants; <syms> prints an attribute only when it differs" );
static_assert( legendDefinesAll( kForFileSymsLegend, kForFileSymsAttrs ), "kForFileSymsLegend must spell every <syms> attribute as name=" );
static_assert( legendDefinesAll( kForFileSymsLegendCompact, kForFileSymsAttrs ), "kForFileSymsLegendCompact must spell every <syms> attribute as name=" );
static_assert( legendDefinesAll( kForFileSymsHeldLegend, kForFileSymsHeldAttrs ), "kForFileSymsHeldLegend must spell held= and next=" );
static_assert( legendDefinesAll( kForFileSymsBindLegend, kForFileSymsBindAttrs ) && legendDefinesAll( kForFileSymsBindLegendCompact, kForFileSymsBindAttrs ),
               "each bind clause must spell by=, into= and bind_total=" );
static_assert( legendDefinesAll( kForFileSymsInitLegend, kForFileSymsInitAttrs ) && legendDefinesAll( kForFileSymsInitLegendCompact, kForFileSymsInitAttrs ),
               "each init clause must spell by=, of=, at= and init_cut=" );
static_assert( kForFileSymsInitSpan == 200 && kForFileSymsInitLegend.find( "within 200 bytes" ) != std::string_view::npos
                   && kForFileSymsInitLegendCompact.find( "within 200 bytes" ) != std::string_view::npos,
               "both init legend clauses say \"within 200 bytes\": move the words with the constant" );
static_assert( kForFileSymsInitHeadRows == 5 && kForFileSymsInitLegend.find( "the first 5 <d> rows" ) != std::string_view::npos,
               "the full init legend clause says \"the first 5 <d> rows\": move the words with the constant" );
static_assert( kForFileSymsInitLegend.find( "--" ) == std::string_view::npos && kForFileSymsInitLegendCompact.find( "--" ) == std::string_view::npos
                   && kForFileSymsInitLegend.find( ';', 1 ) == std::string_view::npos && kForFileSymsInitLegendCompact.find( ';', 1 ) == std::string_view::npos,
               "one clause each, and no '--' (the legend is an XML comment)" );
static_assert( kForFileSymsBindPerHead == 2, "the bind clauses say \"two per head row\": move the words with the constant" );
static_assert( kForFileSymsBindLegend.find( "--" ) == std::string_view::npos && kForFileSymsBindLegendCompact.find( "--" ) == std::string_view::npos
                   && kForFileSymsBindLegend.find( ';', 1 ) == std::string_view::npos && kForFileSymsBindLegendCompact.find( ';', 1 ) == std::string_view::npos,
               "one clause each, and no '--' (the legend is an XML comment)" );
static_assert( kForFileSymsLegend.ends_with( kLegendClose ) && kForFileSymsLegendCompact.ends_with( kLegendClose ), "the bind clause splices before the close" );

namespace filesyms_detail
{
// The measured stopword list (reports/k-wrongsym.md Stage 0, tmp angles.py): English glue a task carries that no name means.
inline constexpr std::array<std::string_view, 60> kStop {
    "the", "and", "for", "with", "from", "that", "this", "what", "which", "where", "when", "how", "does", "are", "was",
    "were", "into", "its", "their", "then", "than", "there", "here", "who", "why", "can", "not", "but", "all", "any",
    "has", "have", "had", "will", "would", "should", "could", "get", "set", "use", "used", "uses", "using", "via",
    "per", "new", "add", "make", "made", "like", "each", "also", "only", "just", "your", "you", "our", "out", "it's", "itself"
};

// A light suffix stem (ing, ies→y, es, ed, s) so `failed` meets `fail` and `integrations` meets `integration`.
inline std::string lightStem( std::string w )
{
    static constexpr std::array<std::string_view, 5> kSuf { "ing", "ies", "es", "ed", "s" };
    for( const std::string_view suf : kSuf )
    {
        if( w.size() > suf.size() + 2 && std::string_view( w ).ends_with( suf ) )
        {
            w.resize( w.size() - suf.size() );
            if( suf == "ies" )
            {
                w += 'y';
            }
            return w;
        }
    }
    return w;
}

// The words of `text` that can match a name: identifier subtokens of 3+ bytes, stopwords out, stemmed; sorted unique.
inline std::vector<std::string> matchWords( std::string_view text )
{
    std::vector<std::string> raw;
    subtokens( text, raw );
    std::vector<std::string> out;
    for( std::string& w : raw )
    {
        if( w.size() >= 3 && !std::ranges::contains( kStop, std::string_view( w ) ) )
        {
            out.push_back( lightStem( std::move( w ) ) );
        }
    }
    std::ranges::sort( out );
    out.erase( std::unique( out.begin(), out.end() ), out.end() );
    return out;
}

inline std::size_t sharedWords( const std::vector<std::string>& a, const std::vector<std::string>& b )
{
    std::size_t n = 0;
    for( auto i = a.begin(), j = b.begin(); i != a.end() && j != b.end(); )
    {
        const int c = i->compare( *j );
        n += c == 0 ? 1 : 0;
        i += c <= 0 ? 1 : 0;
        j += c >= 0 ? 1 : 0;
    }
    return n;
}


// The spellings a name can take in the answer, sorted unique: every identifier run, plus the run with the sigil byte before it (TypeScript
// `#priv`, JS `$name`, `@x`, `~Dtor`) and the `?`/`!` byte after it (Ruby `valid?`), since the stored name keeps them.
inline constexpr std::string_view kNameSigils = "#$@~"; // the byte a stored name may start with
inline constexpr std::string_view kNameSuffixes = "?!"; // ...and end with
// The identifier run [i, j) of `text` and its sigil/suffix variants, as views into the text.
inline void pushRunVariants( std::vector<std::string_view>& out, std::string_view text, std::size_t i, std::size_t j )
{
    const std::size_t from = i > 0 && kNameSigils.contains( text[i - 1] ) ? i - 1 : i;
    const std::size_t to = j < text.size() && kNameSuffixes.contains( text[j] ) ? j + 1 : j;
    for( const std::size_t f : { i, from } )
    {
        for( const std::size_t t : { j, to } )
        {
            out.push_back( text.substr( f, t - f ) );
        }
    }
}
inline std::vector<std::string_view> answerTokens( std::string_view text )
{
    std::vector<std::string_view> out;
    for( std::size_t i = 0, j = 0; i < text.size(); i = std::max( i + 1, j ) )
    {
        if( !namesplit::isIdentChar( text[i] ) )
        {
            continue;
        }
        for( j = i; j < text.size() && namesplit::isIdentChar( text[j] ); ++j )
        {
        }
        pushRunVariants( out, text, i, j );
    }
    std::ranges::sort( out, rw::sortutil::svLess );
    out.erase( std::unique( out.begin(), out.end() ), out.end() );
    return out;
}

// A name shaped sigil? + identifier + suffix? is looked up among the tokens; any other spelling (`operator==`, `a$b`) is searched for in the text
// itself (raw, then XML-escaped, as the answer prints attributes), with identifier boundaries at its identifier ends.
inline bool isTokenName( std::string_view n ) noexcept
{
    n.remove_prefix( !n.empty() && kNameSigils.contains( n.front() ) ? 1 : 0 );
    n.remove_suffix( !n.empty() && kNameSuffixes.contains( n.back() ) ? 1 : 0 );
    return !n.empty() && std::ranges::all_of( n, namesplit::isIdentChar );
}
inline bool spelledIn( std::string_view text, std::string_view name )
{
    for( std::size_t at = text.find( name ); at != std::string_view::npos; at = text.find( name, at + 1 ) )
    {
        const std::size_t end = at + name.size();
        const bool pre = at == 0 || !( namesplit::isIdentChar( text[at - 1] ) && namesplit::isIdentChar( name.front() ) );
        const bool suf = end == text.size() || !( namesplit::isIdentChar( text[end] ) && namesplit::isIdentChar( name.back() ) );
        if( pre && suf )
        {
            return true;
        }
    }
    return false;
}
inline bool nameInAnswer( const std::vector<std::string_view>& tokens, std::string_view text, std::string_view name )
{
    if( isTokenName( name ) )
    {
        return std::ranges::binary_search( tokens, name, rw::sortutil::svLess );
    }
    std::vector<char> esc;
    return !name.empty() && ( spelledIn( text, name ) || spelledIn( text, escapeXml( name, esc ) ) );
}

// `rest` (text from a '<') opens element `name`: the name is followed by a space, '>' or '/'.
inline bool tagIs( std::string_view rest, std::string_view name ) noexcept
{
    return rest.size() > name.size() + 1 && rest.substr( 1, name.size() ) == name
        && ( rest[name.size() + 1] == ' ' || rest[name.size() + 1] == '>' || rest[name.size() + 1] == '/' );
}

// One printed row a --for post-pass rewrites as a FILE tail pointer: its bytes [at, end) and the pointer's p=, sym= and r= values.
struct TailPointerSpan
{
    std::size_t at = 0, end = 0;
    std::string_view p, sym, rank;
};
// `text` with each span (in text order) rewritten in place as <t p= sym= r=/> (r= only when the row had one), `legend` before the
// first; "" when `spans` is empty. ONE-SIDE-REACH (foronesidereach.h) and SIBLING-DEMOTE (forsiblingdemote.h) both print through it.
inline std::string tailPointerText( std::string_view text, std::span<const TailPointerSpan> spans, std::string_view legend )
{
    std::string out;
    std::size_t from = 0;
    for( const TailPointerSpan& s : spans )
    {
        out.append( text.substr( from, s.at - from ) );
        out += &s == &spans.front() ? legend : std::string_view();
        out += "<t p=\"";
        out += s.p;
        out += "\" sym=\"";
        out += s.sym;
        out += s.rank.empty() ? std::string() : "\" r=\"" + std::string( s.rank );
        out += "\"/>";
        from = s.end;
    }
    return spans.empty() ? std::string() : out.append( text.substr( from ) );
}

// The five XML entities the answer escapes, and the three control-character references escapeXml writes for a path or name holding a tab,
// newline or carriage return (serialize.h xmlControlCharRef), decoded (a name like `operator<` or a path with `&`).
inline std::string unescapeXmlAttr( std::string_view v )
{
    static constexpr std::array<std::pair<std::string_view, char>, 8> kEnt {
        { { "&lt;", '<' }, { "&gt;", '>' }, { "&amp;", '&' }, { "&quot;", '"' }, { "&apos;", '\'' }, { "&#9;", '\t' }, { "&#10;", '\n' }, { "&#13;", '\r' } }
    };
    std::string out;
    out.reserve( v.size() );
    for( std::size_t i = 0; i < v.size(); )
    {
        const auto ent = v[i] == '&' ? std::ranges::find_if( kEnt, [&]( const auto& e )
                                                             { return v.substr( i ).starts_with( e.first ); } )
                                     : kEnt.end();
        if( ent != kEnt.end() )
        {
            out += ent->second;
            i += ent->first.size();
            continue;
        }
        out += v[i++];
    }
    return out;
}

struct ShownRow
{
    char kind = 0; // 'd', 'b' or 't'
    std::string path;
    std::string name;
    std::uint32_t line = 0;
    std::size_t symAt = 0, symLen = 0; // a <t> row: its sym= value's bytes in the answer (symLen 0: none)
};

// The <d>, <b> and <t> row tags of the answer in order, outside comments and CDATA (a served body's own `<b>` is code, not a row).
inline std::vector<ShownRow> shownRows( std::string_view text )
{
    std::vector<ShownRow> rows;
    for( std::size_t i = text.find( '<' ); i != std::string_view::npos && i + 2 < text.size(); i = text.find( '<', i + 1 ) )
    {
        const std::string_view rest = text.substr( i );
        const std::string_view skipTo = rest.starts_with( "<!--" ) ? "-->" : rest.starts_with( "<![CDATA[" ) ? "]]>"
                                                                                                             : "";
        if( !skipTo.empty() )
        {
            const std::size_t end = text.find( skipTo, i );
            if( end == std::string_view::npos )
            {
                break;
            }
            i = end;
            continue;
        }
        const char k = text[i + 1];
        if( ( k != 'd' && k != 'b' && k != 't' ) || text[i + 2] != ' ' )
        {
            continue;
        }
        const std::size_t close = text.find( '>', i );
        if( close == std::string_view::npos )
        {
            break;
        }
        const std::string_view tag = text.substr( i + 2, close - i - 2 );
        ShownRow r { .kind = k, .path = unescapeXmlAttr( attrOf( tag, "p" ) ), .name = unescapeXmlAttr( attrOf( tag, "n" ) ) };
        const std::string_view l = attrOf( tag, "l" );
        std::from_chars( l.data(), l.data() + l.size(), r.line );
        if( const std::string_view sym = attrOf( tag, "sym" ); k == 't' && !sym.empty() )
        {
            r.symAt = std::size_t( sym.data() - text.data() );
            r.symLen = sym.size();
        }
        if( const std::size_t colon = r.path.rfind( ':' ); r.line == 0 && colon != std::string::npos ) // a p="file:line" row
        {
            const std::string_view tail = std::string_view( r.path ).substr( colon + 1 );
            if( !tail.empty() && std::ranges::all_of( tail, []( char c )
                                                      { return c >= '0' && c <= '9'; } ) )
            {
                std::from_chars( tail.data(), tail.data() + tail.size(), r.line );
                r.path.resize( colon );
            }
        }
        if( !r.path.empty() )
        {
            rows.push_back( std::move( r ) );
        }
        i = close;
    }
    return rows;
}

// (name, index) rows in name byte order, then index: the order FileLookup and creditCallees binary-search by name.
inline bool nameThenIndexLess( const std::pair<std::string_view, std::size_t>& a, const std::pair<std::string_view, std::size_t>& b )
{
    return a.first != b.first ? rw::sortutil::svLess( a.first, b.first ) : a.second < b.second;
}

// The file id a row's p= names: the index path itself, else the one file it is a whole-segment suffix of (or that is one of it).
// One lookup per answer: the exact paths sort once, and each distinct path is resolved once (a suffix match scans the files, memoized).
class FileLookup
{
public:
    explicit FileLookup( const IngestResult& ing ) : ing_( ing ) {}
    std::uint32_t of( std::string_view p )
    {
        const auto memoAt = std::ranges::lower_bound( memo_, p, rw::sortutil::svLess, []( const auto& row ) { return std::string_view( row.first ); } );
        if( memoAt != memo_.end() && memoAt->first == p )
        {
            return memoAt->second;
        }
        if( exact_.empty() )
        {
            exact_.reserve( ing_.files.size() );
            for( std::uint32_t f = 0; f < ing_.files.size(); ++f )
            {
                exact_.emplace_back( rootRelPath( ing_, f ), f );
            }
            std::ranges::sort( exact_, nameThenIndexLess ); // (path, id): the first file of a spelling is the lowest id, so it wins
        }
        const auto exact = std::ranges::lower_bound( exact_, p, rw::sortutil::svLess, &std::pair<std::string_view, std::size_t>::first );
        const std::uint32_t id = exact != exact_.end() && exact->first == p ? std::uint32_t( exact->second ) : suffixMatch( p );
        memo_.emplace( memoAt, std::string( p ), id );
        return id;
    }

private:
    // The one file `p` is a whole-segment suffix of (or that is a suffix of it); none or several: UINT32_MAX.
    std::uint32_t suffixMatch( std::string_view p ) const
    {
        std::uint32_t id = UINT32_MAX, hits = 0;
        for( std::uint32_t f = 0; f < ing_.files.size(); ++f )
        {
            const std::string_view q = rootRelPath( ing_, f );
            const bool suffix = ( q.size() > p.size() && q.ends_with( p ) && q[q.size() - p.size() - 1] == '/' ) || ( p.size() > q.size() && p.ends_with( q ) && p[p.size() - q.size() - 1] == '/' );
            id = suffix ? f : id;
            hits += suffix ? 1u : 0u;
        }
        return hits == 1 ? id : UINT32_MAX;
    }
    const IngestResult& ing_;
    std::vector<std::pair<std::string_view, std::size_t>> exact_; // sorted by (path, file id), byte order
    std::vector<std::pair<std::string, std::uint32_t>>    memo_;  // sorted by path, byte order
};

inline std::string_view leafName( std::string_view n )
{
    // after the last separator, else the whole spelling (a find_last_of + 1 would wrap on npos under -fsanitize=integer)
    // A `#` that starts the member (`Router.#addRoute`, a bare `#addRoute`) is TypeScript's private mark, part of the stored name; Ruby's
    // `Owner#name` separator has an identifier byte before it.
    const auto lastSep = std::ranges::find_last_if( n, []( char c ) { return c == '.' || c == ':' || c == '#'; } );
    if( lastSep.empty() )
    {
        return n;
    }
    const std::size_t at = std::size_t( lastSep.begin() - n.begin() );
    const bool privateMark = n[at] == '#' && ( at == 0 || n[at - 1] == '.' );
    return n.substr( privateMark ? at : at + 1 );
}

inline std::uint32_t fanIn( const Graph& g, NodeId id )
{
    const std::uint32_t* ro = g.inEdges.rowOffsets();
    const std::uint32_t* ci = g.inEdges.colIndices();
    if( ro == nullptr || ci == nullptr || std::size_t( id ) >= g.inEdges.rows() )
    {
        return 0;
    }
    std::uint32_t n = 0;
    for( std::uint32_t k = ro[id]; k < ro[id + 1]; ++k )
    {
        n += ci[k] != id ? 1u : 0u;
    }
    return n;
}

struct Cand
{
    NodeId id = kNoNode;
    std::size_t fileRank = 0; // position among the shown files
    std::size_t byName = 0; // task words its name shares
    std::size_t byCallee = 0; // head names whose definitions call it (popcount of headMask)
    std::uint8_t headMask = 0; // bit i: a definition named Head::names[i] calls it
    std::uint32_t fanIn = 0;
    bool anyPlain = false; // a shown head row itself calls it over an evidence-bound edge (not name-only, not split)
    bool anySplit = false;
};

// The first kForFileSymsHeadRows <d> rows: their distinct leaf names (by="callee" reads every definition so named) and the rows
// themselves as index ids (the definition in the row's file at its line by that name; kNoNode when the row maps to none).
struct Head
{
    std::vector<std::string> names; // distinct, at most kForFileSymsHeadRows (a bit each in Cand::headMask)
    std::vector<NodeId> ids;
    std::size_t rows = 0;
};
// A head row's definition: the symbol of its file at its line by its leaf name.
struct HeadWant
{
    std::uint32_t file, line;
    std::string_view leaf;
    bool found;
};
// ONE pass over the symbols finds all (at most 8) head rows' definitions.
inline std::vector<NodeId> headIds( const IngestResult& ing, std::vector<HeadWant>& wants )
{
    std::vector<NodeId> ids;
    for( const Symbol& s : ing.symbols )
    {
        for( HeadWant& w : wants )
        {
            if( !w.found && s.fileId == w.file && s.line == w.line && s.name == w.leaf )
            {
                w.found = true;
                ids.push_back( s.id );
            }
        }
    }
    return ids;
}
inline Head headOf( const IngestResult& ing, const std::vector<ShownRow>& rows, const std::vector<std::uint32_t>& rowFile )
{
    static_assert( kForFileSymsHeadRows <= 8, "Cand::headMask holds one bit per head name" );
    Head out;
    std::vector<HeadWant> wants;
    for( std::size_t i = 0; i < rows.size() && out.rows < kForFileSymsHeadRows; ++i )
    {
        if( rows[i].kind != 'd' || rows[i].name.empty() )
        {
            continue;
        }
        ++out.rows;
        const std::string_view leaf = leafName( rows[i].name );
        if( !std::ranges::contains( out.names, leaf ) )
        {
            out.names.emplace_back( leaf );
        }
        if( rowFile[i] != UINT32_MAX )
        {
            wants.push_back( HeadWant { rowFile[i], rows[i].line, leaf, false } );
        }
    }
    out.ids = headIds( ing, wants );
    return out;
}

inline constexpr std::array<SymKind, 3> kNotCandidate { SymKind::Section, SymKind::ModuleScope, SymKind::Field }; // a heading or data key, a file's scope, a field
inline bool candidateKind( const Symbol& s ) noexcept
{
    return !s.name.empty() && !std::ranges::contains( kNotCandidate, s.kind );
}
} // namespace filesyms_detail

namespace filesyms_detail
{
// The answer's first kForFileSymsFiles distinct shown paths as file ids (UINT32_MAX: a path the index does not hold), in answer
// order, each row's file id (every row maps: the shown places below read them all), and the (file, line) of every shown row.
struct ShownFiles
{
    std::vector<std::uint32_t> files;
    std::vector<std::uint32_t> rowFile;
    std::vector<std::uint64_t> shownAt; // sorted: (file << 32 | line) of each shown row the index holds
    std::size_t pathsShown = 0; // distinct shown paths, the window's total
};
inline ShownFiles shownFiles( const IngestResult& ing, const std::vector<ShownRow>& rows )
{
    ShownFiles out;
    FileLookup lookup( ing );
    std::vector<std::string_view> paths; // distinct, in answer order
    out.rowFile.assign( rows.size(), UINT32_MAX );
    for( std::size_t i = 0; i < rows.size(); ++i )
    {
        const std::string_view p = rows[i].path;
        out.rowFile[i] = lookup.of( p );
        if( out.rowFile[i] != UINT32_MAX && rows[i].line > 0 )
        {
            out.shownAt.push_back( ( std::uint64_t( out.rowFile[i] ) << 32 ) | rows[i].line );
        }
        if( std::ranges::contains( paths, p ) )
        {
            continue;
        }
        paths.push_back( p );
        if( out.files.size() < kForFileSymsFiles )
        {
            out.files.push_back( out.rowFile[i] );
        }
    }
    out.pathsShown = paths.size();
    std::ranges::sort( out.shownAt );
    return out;
}

// The candidates in id order: definitions of the shown files whose name is no word of the answer and which no shown row stands on,
// each with its task-word score.
inline std::vector<Cand> collectCands( const IngestResult& ing, const ShownFiles& sf, std::string_view answer, std::string_view task )
{
    const std::vector<std::string_view> tokens = answerTokens( answer );
    const std::vector<std::string> taskWords = matchWords( task );
    std::vector<Cand> cands;
    for( const Symbol& s : ing.symbols )
    {
        const auto at = std::ranges::find( sf.files, s.fileId );
        if( at == sf.files.end() || !candidateKind( s ) || std::ranges::binary_search( sf.shownAt, ( std::uint64_t( s.fileId ) << 32 ) | s.line ) || nameInAnswer( tokens, answer, s.name ) )
        {
            continue;
        }
        cands.push_back( Cand { .id = s.id, .fileRank = std::size_t( at - sf.files.begin() ), .byName = sharedWords( taskWords, matchWords( s.name ) ) } );
    }
    return cands;
}

// by="callee", name-resolved at both ends (Stage 0's rule): every definition NAMED like a head row (the shown row and its namesakes,
// since a row's name is what the answer gave) and every call it makes (calls only; a markdown link is no call), crediting each
// candidate NAMED like the callee. A row is plain only when the shown row itself calls that very candidate over an evidence-bound edge.
inline void creditCallees( const IngestResult& ing, const Graph& g, const Head& head, std::vector<Cand>& cands )
{
    std::vector<std::pair<std::string_view, std::size_t>> candByName; // (name, index into cands), sorted: the callee's namesakes
    candByName.reserve( cands.size() );
    for( std::size_t i = 0; i < cands.size(); ++i )
    {
        candByName.emplace_back( ing.symbols[cands[i].id].name, i );
    }
    std::ranges::sort( candByName, nameThenIndexLess );
    for( const Symbol& caller : ing.symbols )
    {
        const auto named = std::ranges::find( head.names, caller.name );
        if( named == head.names.end() || std::size_t( caller.id ) + 1 >= g.outOff.size() )
        {
            continue;
        }
        const std::uint8_t bit = std::uint8_t( 1u << std::size_t( named - head.names.begin() ) );
        const bool shown = std::ranges::contains( head.ids, caller.id );
        for( std::uint32_t e = g.outOff[caller.id]; e < g.outOff[caller.id + 1]; ++e )
        {
            const NodeId to = g.outTargets[e];
            const std::uint8_t kind = e < g.outNameOnly.size() ? edgeKindByte( g.outNameOnly[e] ) : 0;
            if( to == caller.id || to >= ing.symbols.size() || kind == kEdgeLink )
            {
                continue;
            }
            const bool split = e < g.outProv.size() && g.outProv[e] == 3u;
            const auto [lo, hi] = std::ranges::equal_range( candByName, std::string_view( ing.symbols[to].name ), rw::sortutil::svLess, &std::pair<std::string_view, std::size_t>::first );
            for( auto it = lo; it != hi; ++it )
            {
                Cand& c = cands[it->second];
                const bool self = shown && c.id == to; // the shown row's own edge to this very definition
                c.headMask = std::uint8_t( c.headMask | bit );
                c.anySplit = c.anySplit || ( self && split && kind != kEdgeName );
                c.anyPlain = c.anyPlain || ( self && kind != kEdgeName && !split );
            }
        }
    }
}

// `from` folds into `into`: one function to look at, so its head callers (bits OR-ed: one head calling both spellings is one caller) count
// for the row that stays.
inline void foldHeads( Cand& into, const Cand& from )
{
    into.headMask = std::uint8_t( into.headMask | from.headMask );
    into.byCallee = std::size_t( std::popcount( into.headMask ) );
}
// The shown row's exact-target evidence (anyPlain / anySplit: its edge reaches THAT definition) moves only when the two are one function (a
// declaration and its definition). Between two overloads or two re-opened definitions it stays with the one it was found on: the row printed
// for `into` has no evidence-bound call, so it says via="name".
inline void foldInto( Cand& into, const Cand& from )
{
    foldHeads( into, from );
    into.anyPlain = into.anyPlain || from.anyPlain;
    into.anySplit = into.anySplit || from.anySplit;
}
// What a fold of `c` into its group's leader does.
enum class Fold : std::uint8_t { Keep, Heads, Whole }; // stay a row; head callers only (overloads); everything (one function)

// Groups `cands` by `key`, ordered inside a group by `rank`, and folds each candidate into its group's first row (the leader) as
// `canFold(leader, c)` says (a Fold); a Keep stays a row.
// a < b over a std::tuple, field by field, with every std::string_view field ordered by rw::sortutil::svLess (a tuple's own operator< would
// order a string_view through operator<, which wraps under -fsanitize=integer on libstdc++; see infra/sortutil.h).
template<class T>
inline bool orderLess( const T& a, const T& b );
template<std::size_t I, class T>
inline bool tupleLessFrom( const T& a, const T& b )
{
    if constexpr( I == std::tuple_size_v<T> )
    {
        return false;
    }
    else
    {
        return orderLess( std::get<I>( a ), std::get<I>( b ) )
               || ( !orderLess( std::get<I>( b ), std::get<I>( a ) ) && tupleLessFrom<I + 1>( a, b ) );
    }
}
template<class T>
inline bool orderLess( const T& a, const T& b )
{
    if constexpr( std::is_convertible_v<const T&, std::string_view> )
    {
        return rw::sortutil::svLess( a, b );
    }
    else if constexpr( requires { std::tuple_size<T>::value; } )
    {
        return tupleLessFrom<0>( a, b );
    }
    else
    {
        return a < b;
    }
}

template<class Key, class Rank, class CanFold>
inline void foldByKey( std::vector<Cand>& cands, Key key, Rank rank, CanFold canFold )
{
    std::ranges::sort( cands, [&]( const Cand& a, const Cand& b )
                       { return orderLess( std::tuple( key( a ), rank( a ) ), std::tuple( key( b ), rank( b ) ) ); } );
    std::vector<Cand> kept;
    std::size_t leader = 0;
    for( const Cand& c : cands )
    {
        const bool inGroup = !kept.empty() && key( kept[leader] ) == key( c );
        const Fold how     = inGroup ? canFold( kept[leader], c ) : Fold::Keep;
        if( how != Fold::Keep )
        {
            if( how == Fold::Whole )
            {
                foldInto( kept[leader], c );
            }
            else
            {
                foldHeads( kept[leader], c );
            }
            continue;
        }
        leader = inGroup ? leader : kept.size();
        kept.push_back( c );
    }
    cands = std::move( kept );
}

// The symbol's (scope, name) as views.
inline std::tuple<std::string_view, std::string_view> scopeName( const IngestResult& ing, const Cand& c )
{
    const Symbol& s = ing.symbols[c.id];
    return std::tuple( std::string_view( s.scope ), std::string_view( s.name ) );
}

// A declaration: the index holds no body for it.
inline bool bodylessSymbol( const Symbol& s ) noexcept
{
    return s.sigEndByte >= s.endByte;
}

// One row per (file, scope, name): an overload set, a member's in-class declaration and its out-of-line definition, or a re-opened
// definition name one place to look. The kept row is the one with the most head callers, else the lowest id.
inline void dedupeCands( const IngestResult& ing, std::vector<Cand>& cands )
{
    for( Cand& c : cands )
    {
        c.byCallee = std::size_t( std::popcount( c.headMask ) );
    }
    const auto bodyless = [&]( const Cand& c )
    { return bodylessSymbol( ing.symbols[c.id] ); };
    foldByKey(
        cands, [&]( const Cand& c )
        { return std::tuple( ing.symbols[c.id].fileId, scopeName( ing, c ) ); }, []( const Cand& c )
        { return std::tuple( SIZE_MAX - c.byCallee, c.id ); }, [&]( const Cand& leader, const Cand& c )
        { return bodyless( leader ) || bodyless( c ) ? Fold::Whole : Fold::Heads; } ); // overloads are not one function; a declaration and its definition are
}

// A C/C++ declaration in a header (no body) and the definition of the same (scope, name) in another file are one function to look at
// when the definition provably answers that header (DeclHome): the declaration folds into the definition, which keeps the row. A
// definition with no such tie is a namesake, so both rows stay and the header keeps its lead. A name with no definition among the
// candidates keeps its declaration (the definition is not in the shown files); same-named definitions in sibling files stay apart.
inline bool bodylessHeaderDecl( const IngestResult& ing, const Symbol& s )
{
    return bodylessSymbol( s ) && quality::isHeaderPath( rootRelPath( ing, s.fileId ) ); // .h/.hpp/.hh/.hxx: C-family headers, read as C++ or C
}

// A path up to its last dot when the extension is a C-family source or header one (foo.c, foo.C, foo.cc, foo.cpp, foo.cxx, foo.m, foo.mm
// and the four header spellings); "" for any other file, so a Python or Go namesake never shares a header's stem.
inline std::string_view cFamilyStem( std::string_view path ) noexcept
{
    const std::size_t dot = path.rfind( '.' );
    const std::size_t slash = path.find_last_of( "/\\" );
    if( dot == std::string_view::npos || ( slash != std::string_view::npos && dot < slash ) )
    {
        return {};
    }
    const std::string_view ext = path.substr( dot + 1 );
    constexpr std::array<std::string_view, 11> kExts { "c", "C", "cc", "cpp", "cxx", "m", "mm", "h", "hh", "hpp", "hxx" };
    return std::ranges::contains( kExts, ext ) ? path.substr( 0, dot ) : std::string_view {};
}

// K-DECL-IDENT (CodeRabbit on #555): does a definition's file answer a header's declaration? Yes when it is the header itself, shares the
// header's path stem (src/foo.h and src/foo.cc: one directory, one name up to the last dot), or reaches the header over #include edges,
// directly or through any number of headers (an umbrella header like tmux.h). The walk reads the graph's precise adjacency first
// (Graph::importAdj: a quote include resolved at the includer's directory, the buildGraph closure) and, only when that misses, the
// adjacency with the include-root probe too (`#include "source/server/server.h"` written from the repo root, the envoy shape), built once
// per answer on that first miss. An angle include and an include no rule resolves draw no edge, so such a pair stays two rows. One object
// per answer; each (definition file, header) pair is walked once (memo), with one reused mark array.
class DeclHome
{
public:
    DeclHome( const IngestResult& ing, const Graph& g ) : ing_( ing ), g_( g ) {}

    const IngestResult& ing() const noexcept { return ing_; }
    bool decl( const Cand& c ) const { return bodylessHeaderDecl( ing_, ing_.symbols[c.id] ); }

    // The definition among `group` (one (scope, name), kept rows so far) that header declaration `c` folds into: the first one WITH A
    // BODY whose file answers c's header (a prototype in a source file is no implementation: the header keeps its lead). nullptr when
    // `c` is no header declaration or no such definition exists.
    Cand* foldTarget( std::span<Cand> group, const Cand& c )
    {
        if( !decl( c ) )
        {
            return nullptr;
        }
        const std::uint32_t declFile = ing_.symbols[c.id].fileId;
        const auto def = std::ranges::find_if( group, [&]( const Cand& k )
                                               { return !bodylessSymbol( ing_.symbols[k.id] ) && answers( ing_.symbols[k.id].fileId, declFile ); } );
        return def == group.end() ? nullptr : &*def;
    }

    bool answers( std::uint32_t defFile, std::uint32_t declFile )
    {
        if( defFile == declFile )
        {
            return true;
        }
        const std::string_view stem = cFamilyStem( rootRelPath( ing_, declFile ) );
        if( !stem.empty() && stem == cFamilyStem( rootRelPath( ing_, defFile ) ) )
        {
            return true;
        }
        const std::uint64_t key = ( std::uint64_t( defFile ) << 32 ) | declFile;
        const auto seen = std::ranges::find( memo_, key, &std::pair<std::uint64_t, bool>::first );
        if( seen != memo_.end() )
        {
            return seen->second;
        }
        bool yes = reaches( g_.importAdj, defFile, declFile );
        if( !yes )
        {
            if( !rootedBuilt_ )
            {
                rooted_ = buildPreciseIncludeAdj( ing_ ); // the --deps adjacency: quote includes also probed from the include roots
                rootedBuilt_ = true;
            }
            yes = reaches( rooted_, defFile, declFile );
        }
        memo_.emplace_back( key, yes );
        return yes;
    }

private:
    bool reaches( const rw::FileAdjacency& adj, std::uint32_t from, std::uint32_t to )
    {
        if( from >= adj.size() || to >= adj.size() )
        {
            return false;
        }
        if( mark_.size() < adj.size() )
        {
            mark_.assign( adj.size(), 0 );
            epoch_ = 0;
        }
        ++epoch_; // a fresh visit stamp per walk; at most a few walks per answer, so it never wraps
        stack_.assign( 1, from );
        mark_[from] = epoch_;
        while( !stack_.empty() )
        {
            const std::uint32_t v = stack_.back();
            stack_.pop_back();
            for( const std::uint32_t w : adj[v] )
            {
                if( w == to )
                {
                    return true;
                }
                if( w < adj.size() && mark_[w] != epoch_ )
                {
                    mark_[w] = epoch_;
                    stack_.push_back( w );
                }
            }
        }
        return false;
    }

    const IngestResult& ing_;
    const Graph& g_;
    rw::FileAdjacency rooted_;
    bool rootedBuilt_ = false;
    std::vector<std::uint32_t> mark_;
    std::uint32_t epoch_ = 0;
    std::vector<std::uint32_t> stack_;
    std::vector<std::pair<std::uint64_t, bool>> memo_; // (defFile << 32 | declFile, answers)
};

// Groups by (scope, name), definitions first (lowest id first), then declarations. A header declaration folds into the group's first
// definition its header is answered by (DeclHome::foldTarget); with none it stays a row.
inline void collapseDeclarations( DeclHome& home, std::vector<Cand>& cands )
{
    const IngestResult& ing = home.ing();
    std::ranges::sort( cands, [&]( const Cand& a, const Cand& b )
                       { return orderLess( std::tuple( scopeName( ing, a ), home.decl( a ), a.id ), std::tuple( scopeName( ing, b ), home.decl( b ), b.id ) ); } );
    std::vector<Cand> kept;
    kept.reserve( cands.size() );
    std::size_t groupStart = 0;
    for( const Cand& c : cands )
    {
        if( kept.empty() || scopeName( ing, kept[groupStart] ) != scopeName( ing, c ) )
        {
            groupStart = kept.size();
        }
        if( Cand* def = home.foldTarget( std::span<Cand>( kept ).subspan( groupStart ), c ) )
        {
            foldInto( *def, c );
            continue;
        }
        kept.push_back( c );
    }
    cands = std::move( kept );
}

// ── by="bind" (VR-BINDER-ROW) ──
// A Value reference that stores a function into a slot: it names something, has an into= and an enclosing symbol, and is neither an
// argument pass / parameter default (key `#i` / `#kw`) nor a decorator (`into=@NAME`, a fact about the definition itself).
inline bool slotBind( const Reference& r )
{
    return r.role == RefRole::Value && r.fromSymbol != kNoNode && !r.calleeName.empty() && !r.fieldName().empty()
        && !r.fieldName().starts_with( '@' ) && !r.composeRel().starts_with( '#' );
}
struct BindRow
{
    NodeId        id  = kNoNode;   // the binder (the <vr> row's in_id=)
    std::uint32_t ref = 0;         // its first bind of a head row (into=)
};
struct BindPicks
{
    std::vector<BindRow> rows;    // at most kForFileSymsBindPerHead per head row
    std::size_t          total = 0;   // distinct binders found
};

// ── by="init" (CONST-INIT-CALLEE, residual pass 11-12 card 3) ──
// A head row's NAME is often a value a module-level declaration makes with one call: angular's
// `export const Component: ComponentDecorator = makeDecorator(…)` (the decorator the task asks about is that value, and the index
// holds only its same-named interface), django's `settings = LazySettings()`. The edge already exists — the call is a file-scope
// call of the file's module scope — but nothing joins it to the name it initialises. The rule reads the head's own file for a
// declaration of the name at the start of a statement (`const|let|var X … =`, or `X … =` at column 0), takes the call that
// begins its initialiser (a file-scope call: its owner is the module scope or the module-level variable), and prints that call's
// callee when the owner's out-edges resolve it to exactly one definition, unless a shown row already stands on that callee.
struct InitRow
{
    NodeId        callee  = kNoNode;
    std::string   of;            // the head name the declaration initialises
    std::uint32_t file = 0, line = 0;   // the declaration
};
struct InitHead
{
    std::string   name;   // leaf name
    std::uint32_t file;
};
// The re-export walk's <def n= p= l=> rows (src/forreexport.h): the definition a spelled import reached, a head like any <d> row.
inline std::vector<std::pair<std::string, std::string>> reexportDefRows( std::string_view text )
{
    std::vector<std::pair<std::string, std::string>> out;   // (name, path)
    for( std::size_t at = text.find( "<reexports>" ); at != std::string_view::npos; at = text.find( "<reexports>", at + 1 ) )
    {
        const std::size_t end = text.find( "</reexports>", at );
        const std::string_view block = text.substr( at, end == std::string_view::npos ? std::string_view::npos : end - at );
        for( std::size_t d = block.find( "<def " ); d != std::string_view::npos; d = block.find( "<def ", d + 1 ) )
        {
            const std::size_t close = block.find( '>', d );
            const std::string_view tag = block.substr( d + 4, close == std::string_view::npos ? std::string_view::npos : close - d - 4 );
            std::string n = unescapeXmlAttr( attrOf( tag, "n" ) ), p = unescapeXmlAttr( attrOf( tag, "p" ) );
            if( !n.empty() && !p.empty() )
            {
                out.emplace_back( std::move( n ), std::move( p ) );
            }
        }
    }
    return out;
}
inline std::vector<InitHead> initHeads( const IngestResult& ing, const std::vector<ShownRow>& rows, const ShownFiles& sf, std::string_view answer )
{
    std::vector<InitHead> out;
    const auto add = [&]( std::string_view name, std::uint32_t file )
    {
        if( file != UINT32_MAX && !name.empty() && std::ranges::none_of( out, [&]( const InitHead& h ) { return h.name == name && h.file == file; } ) )
        {
            out.push_back( InitHead { std::string( name ), file } );
        }
    };
    std::size_t seen = 0;
    for( std::size_t i = 0; i < rows.size() && seen < kForFileSymsInitHeadRows; ++i )
    {
        if( rows[i].kind == 'd' && !rows[i].name.empty() )
        {
            ++seen;
            add( leafName( rows[i].name ), sf.rowFile[i] );
        }
    }
    FileLookup lookup( ing );
    for( const auto& [ name, path ] : reexportDefRows( answer ) )
    {
        add( leafName( name ), lookup.of( path ) );
    }
    return out;
}
inline bool identByte( char c ) noexcept
{
    return namesplit::isIdentChar( c ) || c == '$';
}
// The byte just past `X … =` when the occurrence of `name` at `at` starts a declaration: the word before it is const/let/var on
// the same line, or it sits at column 0; then an optional `: Type` annotation, then a lone `=` (not `==` / `=>`) on the same line.
// npos otherwise.
inline std::size_t declInitAt( std::string_view t, std::size_t at, std::string_view name )
{
    const std::size_t after = at + name.size();
    if( ( at > 0 && identByte( t[at - 1] ) ) || ( after < t.size() && identByte( t[after] ) ) )
    {
        return std::string_view::npos;
    }
    std::size_t b = at;
    while( b > 0 && ( t[b - 1] == ' ' || t[b - 1] == '\t' ) )
    {
        --b;
    }
    const bool column0 = at == 0 || t[at - 1] == '\n';
    bool       keyword = false;
    for( const std::string_view kw : { std::string_view( "const" ), std::string_view( "let" ), std::string_view( "var" ) } )
    {
        keyword = keyword || ( b != at && b >= kw.size() && t.substr( b - kw.size(), kw.size() ) == kw && ( b == kw.size() || !identByte( t[b - kw.size() - 1] ) ) );
    }
    if( !column0 && !keyword )
    {
        return std::string_view::npos;
    }
    for( std::size_t i = after; i < t.size() && t[i] != '\n' && t[i] != ';' && t[i] != '(' && t[i] != '{'; ++i )
    {
        if( t[i] == '=' )
        {
            const bool lone = ( i + 1 >= t.size() || ( t[i + 1] != '=' && t[i + 1] != '>' ) ) && std::string_view( "!<>=+-*/%&|^" ).find( t[i - 1] ) == std::string_view::npos;
            if( !lone )
            {
                return std::string_view::npos;
            }
            ++i;
            while( i < t.size() && std::isspace( static_cast<unsigned char>( t[i] ) ) )
            {
                ++i;
            }
            return i;
        }
    }
    return std::string_view::npos;
}
// The callee the initialiser at `p` begins with: `f(`, `a.b.f(`, `new F(`; "" when the initialiser is anything else (a literal, an
// object, an arrow, a call whose callee is itself a call).
inline std::string_view initCallName( std::string_view t, std::size_t p )
{
    const std::string_view seg = t.substr( p, kForFileSymsInitSpan );
    const std::size_t      open = seg.find( '(' );
    if( open == std::string_view::npos )
    {
        return {};
    }
    std::string_view head = seg.substr( 0, open );
    if( head.starts_with( "new " ) )
    {
        head.remove_prefix( 4 );
    }
    while( !head.empty() && ( head.back() == ' ' || head.back() == '\t' ) )
    {
        head.remove_suffix( 1 );
    }
    if( head.empty() || !std::ranges::all_of( head, []( char c ) { return identByte( c ) || c == '.'; } ) )
    {
        return {};
    }
    const std::size_t dot = head.rfind( '.' );
    return dot == std::string_view::npos ? head : head.substr( dot + 1 );
}
// FORFILESYMS-INIT-WINDOW-LEGEND (CodeRabbit on #646): may the initialiser at `p` begin with a call whose `(` lies past the
// kForFileSymsInitSpan window? The window is full, the text goes on, and every byte read could still be a callee head (`new `,
// identifier and dot bytes, blanks), so initCallName's "" there is the window's cut, not "no call".
inline bool initRunsPastWindow( std::string_view t, std::size_t p )
{
    const bool             goesOn     = p < t.size() && t.size() - p > kForFileSymsInitSpan;
    const std::string_view seg        = goesOn ? t.substr( p, kForFileSymsInitSpan ) : std::string_view();
    const bool             pastWindow = goesOn && std::ranges::all_of( seg, []( char c ) { return identByte( c ) || c == '.' || c == ' ' || c == '\t'; } );
    return pastWindow;
}
// by="init"'s disclosure sink: the head names whose declaration ran past the window (init_cut= on <syms>).
struct InitWindowCut
{
    enum class DisclosureWhy : std::uint8_t
    {
        PastWindow,   // a declaration's initialiser ran past kForFileSymsInitSpan before its `(`
    };
    std::size_t count = 0;
    void        disclose( DisclosureWhy ) noexcept { ++count; }
};
// One declaration found in a head's file: where its initialiser starts and the callee it begins with.
struct InitDecl
{
    std::size_t      head;   // index into the heads
    std::uint32_t    file;
    std::size_t      from, to;   // the initialiser call's byte window [from, to)
    std::string_view callee;
};
// The owner's one out-edge to a definition named `name` (kNoNode: none, or several). The owner is the file's module scope, or the
// module-level variable itself where the index makes the declaration the call's owner (Python: `config = LazyConfig()` is a var row
// that calls LazyConfig).
inline NodeId moduleScopeCallee( const IngestResult& ing, const Graph& g, NodeId scope, std::string_view name )
{
    NodeId found = kNoNode;
    if( scope + 1 >= g.outOff.size() )
    {
        return found;
    }
    for( std::uint32_t e = g.outOff[scope]; e < g.outOff[scope + 1]; ++e )
    {
        if( ing.symbols[ g.outTargets[e] ].name == name )
        {
            if( found != kNoNode )
            {
                return kNoNode;   // a split: no single definition to name
            }
            found = g.outTargets[e];
        }
    }
    return found;
}
// Every declaration of each head's name in its file that begins its initialiser with a call, in file order (a name commented out or
// quoted earlier in the file is one too: pickInits takes the first one a file-scope call stands in, FORFILESYMS-COMMENT-DECL).
inline std::vector<InitDecl> initDecls( const std::vector<InitHead>& heads, FileTextCache& text, InitWindowCut& cut )
{
    std::vector<InitDecl> decls;
    for( std::size_t h = 0; h < heads.size(); ++h )
    {
        const std::string* t = text.text( heads[h].file );
        if( t == nullptr || text.stale( heads[h].file ) )
        {
            continue;
        }
        const std::string_view tv( *t ), name( heads[h].name );
        bool                   cutHere = false;   // one init_cut per head name
        for( std::size_t at = tv.find( name ); at != std::string_view::npos; at = tv.find( name, at + 1 ) )
        {
            const std::size_t p = declInitAt( tv, at, name );
            if( p == std::string_view::npos )
            {
                continue;
            }
            if( const std::string_view callee = initCallName( tv, p ); !callee.empty() )
            {
                decls.push_back( InitDecl { h, heads[h].file, p, std::min( tv.size(), p + kForFileSymsInitSpan ), callee } );
            }
            else if( !cutHere && initRunsPastWindow( tv, p ) )
            {
                cutHere = true;
                DISCLOSE( cut, InitWindowCut::DisclosureWhy::PastWindow, "for syms: a by=init declaration's initialiser ran past the 200-byte window before its call; init_cut= counts it" );
            }
        }
    }
    return decls;
}
inline std::vector<InitRow> pickInits( const IngestResult& ing, const Graph& g, const ShownFiles& sf, const std::vector<InitHead>& heads, InitWindowCut& cut )
{
    std::vector<InitRow> out;
    if( !forFileSymsInitOn() || heads.empty() )
    {
        return out;
    }
    FileTextCache               text( ing );
    const std::vector<InitDecl> decls = initDecls( heads, text, cut );
    if( decls.empty() )
    {
        return out;   // COST: no declaration of a head name: no reference scan
    }
    std::vector<NodeId>        rowFor( decls.size(), kNoNode );
    std::vector<std::uint32_t> lineFor( decls.size(), 0 );   // nonzero: a file-scope call to the callee starts in the window (the evidence)
    for( const Reference& r : ing.references )
    {
        if( r.role != RefRole::Call || r.isInherit || r.isDocLink || r.isCompose || r.fromSymbol == kNoNode || r.fromSymbol >= ing.symbols.size()
            || ( ing.symbols[ r.fromSymbol ].kind != SymKind::ModuleScope && ing.symbols[ r.fromSymbol ].kind != SymKind::Var ) )
        {
            continue;
        }
        for( std::size_t k = 0; k < decls.size(); ++k )
        {
            const InitDecl& d = decls[k];
            if( rowFor[k] == kNoNode && r.fileId == d.file && r.startByte >= d.from && r.startByte < d.to && r.calleeName == d.callee )
            {
                rowFor[k]  = moduleScopeCallee( ing, g, r.fromSymbol, d.callee );
                lineFor[k] = r.line;
            }
        }
    }
    std::vector<char> headDone( heads.size(), 0 );   // the head's declaration is its first one with a file-scope call in the window
    for( std::size_t k = 0; k < decls.size(); ++k )
    {
        if( lineFor[k] == 0 || std::exchange( headDone[ decls[k].head ], 1 ) != 0 )
        {
            continue;   // a commented-out or quoted twin (no call stands in it), or a later declaration of a name already read
        }
        const bool shown = rowFor[k] != kNoNode
                        && std::ranges::binary_search( sf.shownAt, ( std::uint64_t( ing.symbols[ rowFor[k] ].fileId ) << 32 ) | ing.symbols[ rowFor[k] ].line );
        if( rowFor[k] != kNoNode && !shown && std::ranges::none_of( out, [&]( const InitRow& o ) { return o.callee == rowFor[k] && o.of == heads[ decls[k].head ].name; } ) )
        {
            out.push_back( InitRow { rowFor[k], heads[ decls[k].head ].name, decls[k].file, lineFor[k] } );
        }
    }
    return out;
}

struct Picks
{
    std::vector<const Cand*> byName, byCallee; // capped at kForFileSymsRowsPerRule each
    std::size_t nameTotal = 0, calleeTotal = 0;
    BindPicks   binds; // by="bind" (pickBinds), filled after the two ranked rules
    std::vector<InitRow> inits; // by="init" (pickInits), a fact per head name
    InitWindowCut        initCut; // by="init" declarations the window cut (init_cut=)
};
// The tie-break after a rule's own score: fan-in desc, shown-file order, name (byte order), id: a total order. Field by field, not a tuple:
// the tuple's string_view member would order through operator< (see rw::sortutil::svLess).
inline bool tailBefore( const IngestResult& ing, const Cand* a, const Cand* b )
{
    if( a->fanIn != b->fanIn )
    {
        return a->fanIn > b->fanIn;
    }
    if( a->fileRank != b->fileRank )
    {
        return a->fileRank < b->fileRank;
    }
    const std::string_view an( ing.symbols[a->id].name ), bn( ing.symbols[b->id].name );
    return an != bn ? rw::sortutil::svLess( an, bn ) : a->id < b->id;
}
// Each rule's rows: score desc, then fan-in desc, shown-file order, name, id (a total order), cut after the sort. A name both rules
// pick prints once, as by="name".
inline Picks pickRows( const IngestResult& ing, const Graph& g, std::vector<Cand>& cands )
{
    Picks out;
    for( Cand& c : cands )
    {
        c.fanIn = ( c.byName > 0 || c.byCallee > 0 ) ? fanIn( g, c.id ) : 0;
    }
    const auto tail = [&]( const Cand* a, const Cand* b ) { return tailBefore( ing, a, b ); };
    const auto cut = [&]( std::vector<const Cand*>& rule, std::size_t& total, auto&& before )
    {
        std::ranges::sort( rule, [&]( const Cand* a, const Cand* b )
                           { return before( a, b ) || ( !before( b, a ) && tail( a, b ) ); } );
        total = rule.size();
        rule.resize( std::min( rule.size(), kForFileSymsRowsPerRule ) );
    };
    for( const Cand& c : cands )
    {
        if( c.byName > 0 )
        {
            out.byName.push_back( &c );
        }
    }
    cut( out.byName, out.nameTotal, []( const Cand* a, const Cand* b )
         { return a->byName > b->byName; } );
    for( const Cand& c : cands )
    {
        if( c.byCallee > 0 && !std::ranges::contains( out.byName, &c ) )
        {
            out.byCallee.push_back( &c );
        }
    }
    cut( out.byCallee, out.calleeTotal, []( const Cand* a, const Cand* b )
         { return std::pair( a->byCallee, a->byName ) > std::pair( b->byCallee, b->byName ); } );
    return out;
}

// SIZE-1: the block closed, its legend (the prefix before <syms) without the two clauses whose attributes its rows do not carry:
// test=1 unless a row is a test symbol, files= head= unless the <syms> tag printed either one
inline std::string presentOnlySymsBlock( const std::string& block, bool compactLegend )
{
    const std::size_t      legendEnd = block.find( "<syms" );
    std::string            legend    = block.substr( 0, legendEnd );
    const std::string_view rows      = std::string_view( block ).substr( legendEnd );
    const std::string_view tag       = rows.substr( 0, rows.find( '>' ) );
    const bool             readAttrs = !attrOf( tag, "files" ).empty() || !attrOf( tag, "head" ).empty();
    eraseAbsentClause( legend, compactLegend ? kForFileSymsTestClauseCompact : kForFileSymsTestClause, rows.contains( " test=\"1\"" ) );
    eraseAbsentClause( legend, compactLegend ? kForFileSymsReadClauseCompact : kForFileSymsReadClause, readAttrs );
    return legend + std::string( rows ) + "</syms>";
}

// <syms> has priority over a head file's tail row (R-DEDUP, forpage.h tailHeadFileSyms fills it from the file's next ranks — the
// block's own candidates): the <t> rows with sym= whose path a <d> row shows, in answer order. Their names are no word of the
// answer to the block's dedupe (headTailMasked), and a name the block prints is dropped from them (tailRowsWithoutPicks).
inline std::vector<std::size_t> headTailRows( const std::vector<ShownRow>& rows )
{
    std::vector<std::size_t> out;
    for( std::size_t i = 0; i < rows.size(); ++i )
    {
        if( rows[i].symLen > 0 && std::ranges::any_of( rows, [&]( const ShownRow& d )
                                                       { return d.kind == 'd' && d.path == rows[i].path; } ) )
        {
            out.push_back( i );
        }
    }
    return out;
}
inline std::string headTailMasked( std::string_view answer, const std::vector<ShownRow>& rows, const std::vector<std::size_t>& headTail )
{
    std::string out( answer );
    for( const std::size_t i : headTail )
    {
        out.replace( rows[i].symAt, rows[i].symLen, rows[i].symLen, ' ' );
    }
    return out;
}
// The answer with every name the block prints cut from the head files' tail rows (a row left with none prints p= only); "" when none is cut.
inline std::string tailRowsWithoutPicks( const IngestResult& ing, std::string_view answer, const std::vector<ShownRow>& rows,
                                         const std::vector<std::size_t>& headTail, const Picks& picks )
{
    constexpr std::size_t kSymOpen = std::string_view( " sym=\"" ).size();
    std::string out;
    std::size_t from = 0;
    for( const std::size_t i : headTail )
    {
        const ShownRow& r = rows[i];
        std::string kept;
        bool cut = false;
        for( const auto part : std::views::split( answer.substr( r.symAt, r.symLen ), ',' ) )
        {
            const std::string_view raw( part.begin(), part.end() );
            const auto printed = [&]( const Cand* c )
            { return unescapeXmlAttr( raw ) == ing.symbols[c->id].name; };
            if( std::ranges::any_of( picks.byName, printed ) || std::ranges::any_of( picks.byCallee, printed ) )
            {
                cut = true;
                continue;
            }
            kept += kept.empty() ? "" : ",";
            kept += raw;
        }
        if( !cut )
        {
            continue;
        }
        const std::size_t at = kept.empty() ? r.symAt - kSymOpen : r.symAt; // none left: the whole ` sym="…"` goes
        out.append( answer.substr( from, at - from ) );
        out += kept;
        from = r.symAt + r.symLen + ( kept.empty() ? 1 : 0 );
    }
    return from == 0 ? std::string() : out.append( answer.substr( from ) );
}

// ── by="bind" (VR-BINDER-ROW): the picks ──
// The head rows' definition names, sorted unique (svLess): the narrow index's names and the cost pre-check's lookup.
inline std::vector<std::string_view> headDefNames( const IngestResult& ing, const Head& head )
{
    std::vector<std::string_view> names;   // at most kForFileSymsHeadRows: an ordered insert keeps it sorted unique
    for( const NodeId h : head.ids )
    {
        const std::string_view n  = ing.symbols[h].name;
        const auto             at = std::ranges::lower_bound( names, n, rw::sortutil::svLess );
        if( at == names.end() || *at != n )
        {
            names.insert( at, n );
        }
    }
    return names;
}
// COST: does any slot bind name a head row? One scan; no index and no byte when none does.
inline bool anyHeadBind( const IngestResult& ing, const std::vector<std::string_view>& names )
{
    return std::ranges::any_of( ing.references, [&]( const Reference& r )
                                { return slotBind( r ) && std::ranges::binary_search( names, std::string_view( r.calleeName ), rw::sortutil::svLess ); } );
}
// One head's slot binds, in served order (vrBindLess, then reference order: a total order).
inline std::vector<std::uint32_t> headBindsInOrder( const IngestResult& ing, const ValueRefIndex& vri, NodeId h )
{
    std::vector<std::uint32_t> refs = vri.valueRefsTo( std::span<const NodeId>( &h, 1 ) );
    std::erase_if( refs, [&]( std::uint32_t v ) { return !slotBind( ing.references[v] ); } );
    std::ranges::sort( refs, [&]( std::uint32_t a, std::uint32_t b )
                       { return vrBindLess( ing, ing.references[a], ing.references[b] ) || ( !vrBindLess( ing, ing.references[b], ing.references[a] ) && a < b ); } );
    return refs;
}
// What a binder must not be: the head itself (a self-store), a non-candidate kind, a symbol a shown row stands on, a name the answer
// already gives, or a pick of another rule (a name prints once).
struct BinderFilter
{
    const IngestResult&                  ing;
    const ShownFiles&                    sf;
    const Picks&                         picks;
    std::string_view                     answer;
    const std::vector<std::string_view>& tokens;
    bool admits( NodeId from, NodeId head ) const
    {
        if( from == head || from >= ing.symbols.size() )
        {
            return false;
        }
        const Symbol& s  = ing.symbols[from];
        const auto    is = [&]( const Cand* c ) { return c->id == from; };
        return candidateKind( s ) && !std::ranges::binary_search( sf.shownAt, ( std::uint64_t( s.fileId ) << 32 ) | s.line )
            && !nameInAnswer( tokens, answer, s.name ) && !std::ranges::any_of( picks.byName, is ) && !std::ranges::any_of( picks.byCallee, is );
    }
};
// The binders pickBinds has met, one state byte per symbol (indexed membership: a head with thousands of binders stays linear). A
// binder counts once in total and prints at most one row; one counted under an earlier head whose rows were full may still print
// under a later head's free slot.
struct BinderTally
{
    enum : std::uint8_t { kUnseen = 0, kCounted = 1, kPrinted = 2 };
    std::vector<std::uint8_t> state;
    BindPicks&                out;
    // Counts `from` (bind ref v) once; prints its row when the head has a free slot. True when a row printed.
    bool take( NodeId from, std::uint32_t v, bool slotFree )
    {
        if( state[from] == kPrinted )
        {
            return false;
        }
        if( state[from] == kUnseen )
        {
            ++out.total;
        }
        state[from] = slotFree ? kPrinted : kCounted;
        if( slotFree )
        {
            out.rows.push_back( BindRow { from, v } );
        }
        return slotFree;
    }
};
// The binders of the head rows' definitions, head by head (head.ids order), each head's binds in served order. A binder prints one row
// at most and counts once in total; kForFileSymsBindPerHead rows per head, the rest counted in total.
inline BindPicks pickBinds( const IngestResult& ing, const ShownFiles& sf, const Head& head, const Picks& picks, std::string_view answer )
{
    BindPicks out;
    if( !forFileSymsBindOn() || head.ids.empty() )
    {
        return out;
    }
    const std::vector<std::string_view> names = headDefNames( ing, head );
    if( !anyHeadBind( ing, names ) )
    {
        return out;
    }
    const ValueRefIndex                 vri    = ValueRefIndex::narrowFor( ing, names );
    const std::vector<std::string_view> tokens = answerTokens( answer );
    const BinderFilter                  filter { ing, sf, picks, answer, tokens };
    BinderTally                         tally { std::vector<std::uint8_t>( ing.symbols.size(), BinderTally::kUnseen ), out };
    for( const NodeId h : head.ids )
    {
        std::size_t perHead = 0;
        for( const std::uint32_t v : headBindsInOrder( ing, vri, h ) )
        {
            const NodeId from = ing.references[v].fromSymbol;
            if( filter.admits( from, h ) && tally.take( from, v, perHead < kForFileSymsBindPerHead ) )   // admits() range-checks from
            {
                ++perHead;
            }
        }
    }
    return out;
}
// The legend, with the by="bind" clause spliced before its close when a bind row prints.
// A present-only clause spliced before the legend's closing ` -->` (the legend stays one comment).
inline void spliceLegendClause( std::string& legend, std::string_view clause )
{
    legend.insert( legend.size() - kLegendClose.size(), clause );
}
inline std::string symsLegend( bool compactLegend, const BindPicks& binds )
{
    std::string out( compactLegend ? kForFileSymsLegendCompact : kForFileSymsLegend );
    if( !binds.rows.empty() )
    {
        spliceLegendClause( out, compactLegend ? kForFileSymsBindLegendCompact : kForFileSymsBindLegend );
    }
    return out;
}
// The legend for these picks: symsLegend, plus the by="init" clause (present-only, before the close like by="bind"'s).
inline std::string symsLegendOf( bool compactLegend, const Picks& picks )
{
    std::string out = symsLegend( compactLegend, picks.binds );
    spliceLegendClause( out, picks.inits.empty() && picks.initCut.count == 0 ? std::string_view() : compactLegend ? kForFileSymsInitLegendCompact : kForFileSymsInitLegend );
    return out;
}
// A <y> row's opening `<y p="file:line" n="Owner.name"` for symbol `s` (the attribute tail is the rule's own).
inline void appendSymRowOpen( std::string& out, const IngestResult& ing, const MemberOwners& owners, const Symbol& s, std::vector<char>& esc )
{
    out += "<y p=\"";
    out += escapeXml( rootRelPath( ing, s.fileId ), esc );
    out += std::format( ":{}\" n=\"", s.line );
    out += escapeXml( qualifiedMemberName( owners, s ), esc );
    out += '"';
}
// The by="init" rows: p=file:line n=Owner.name of the callee, by="init" of=the head name at=the declaration [test="1"].
inline void appendInitRows( std::string& out, const IngestResult& ing, const MemberOwners& owners, const std::vector<InitRow>& inits, std::vector<char>& esc )
{
    for( const InitRow& r : inits )
    {
        appendSymRowOpen( out, ing, owners, ing.symbols[r.callee], esc );
        out += " by=\"init\" of=\"";
        out += escapeXml( r.of, esc );
        out += "\" at=\"";
        out += escapeXml( rootRelPath( ing, r.file ), esc );
        out += std::format( ":{}\"", r.line );
        out += isTestSymbol( ing, r.callee ) ? " test=\"1\"/>" : "/>";
    }
}
// The by="bind" rows: p=file:line n=Owner.name by="bind" into=the slot [test="1"].
inline void appendBindRows( std::string& out, const IngestResult& ing, const MemberOwners& owners, const BindPicks& binds, std::vector<char>& esc )
{
    for( const BindRow& b : binds.rows )
    {
        appendSymRowOpen( out, ing, owners, ing.symbols[b.id], esc );
        out += " by=\"bind\" into=\"";
        out += escapeXml( ing.references[b.ref].fieldName(), esc );
        out += isTestSymbol( ing, b.id ) ? "\" test=\"1\"/>" : "\"/>";
    }
}

inline std::string blockXml( const IngestResult& ing, const ShownFiles& sf, const Head& head, const Picks& picks, bool compactLegend )
{
    const MemberOwners owners( ing );
    std::vector<char> esc;
    const BindPicks& binds = picks.binds;
    std::string      out   = symsLegendOf( compactLegend, picks );
    // Constants live in the legend (6 files read, 8 head rows, 3 rows per rule): an attribute prints only when it differs or says a cap cut.
    const auto attr = [&]( std::string_view name, std::size_t value, bool print )
    { out += print ? std::format( " {}=\"{}\"", name, value ) : std::string(); };
    out += "<syms";
    attr( "files", sf.files.size(), sf.files.size() != kForFileSymsFiles );
    attr( "files_total", sf.pathsShown, sf.pathsShown > sf.files.size() );
    attr( "head", head.rows, head.rows != kForFileSymsHeadRows );
    attr( "name_total", picks.nameTotal, picks.nameTotal > picks.byName.size() );
    attr( "callee_total", picks.calleeTotal, picks.calleeTotal > picks.byCallee.size() );
    attr( "bind_total", binds.total, binds.total > binds.rows.size() );
    attr( "init_cut", picks.initCut.count, picks.initCut.count != 0 );
    out += ">";
    const auto row = [&]( const Cand& c, bool callee )
    {
        const Symbol& s = ing.symbols[c.id];
        out += "<y p=\"";
        out += escapeXml( rootRelPath( ing, s.fileId ), esc );
        out += std::format( ":{}\" n=\"", s.line );
        out += escapeXml( qualifiedMemberName( owners, s ), esc );
        out += callee ? "\" by=\"callee\"" : "\" by=\"name\"";
        out += !callee || c.anyPlain ? "" : c.anySplit ? " prov=\"split\""
                                                       : " via=\"name\"";
        out += isTestSymbol( ing, c.id ) ? " test=\"1\"" : "";
        out += "/>";
    };
    for( const Cand* c : picks.byName )
    {
        row( *c, false );
    }
    for( const Cand* c : picks.byCallee )
    {
        row( *c, true );
    }
    appendBindRows( out, ing, owners, binds, esc );
    appendInitRows( out, ing, owners, picks.inits, esc );
    return presentOnlySymsBlock( out, compactLegend );
}
} // namespace filesyms_detail

struct FileSymsArgs
{
    std::string_view task; // the --for task
    std::string_view answer; // the answer's text exactly as emitted, before </ctx> (every block that streamed before this one)
    bool held = false; // a token budget: the tag names the call, no rows
    std::string_view heldFlags; // held: the origin call's ranking flags and --pack-top-n, pre-spelled (" --no-route --anchor --pack-top-n=12"): the replay must rank the same list
    bool compactLegend = false;
    bool uncaptured = false; // the CLI could not buffer the emitted bytes: the tag says so, no rows (`answer` is empty)
    std::string* answerOut = nullptr; // set: receives `answer` with the head files' tail-row names the block prints cut ("" when none is);
                                      // the cut is priced markup, so the caller re-prices the root on its final bytes (repriceRootAfterCut)
};
// The block for one answer: "" when no candidate scores.
inline std::string renderForFileSyms( const IngestResult& ing, const Graph& g, const FileSymsArgs& a )
{
    namespace fd = filesyms_detail;
    if( !forFileSymsOn() || a.task.empty() )
    {
        return {};
    }
    if( a.uncaptured )
    {
        return std::string( kForFileSymsHeldLegend ) + "<syms held=\"uncaptured\"/>";
    }
    if( a.answer.empty() )
    {
        return {};
    }
    const std::vector<fd::ShownRow> rows = fd::shownRows( a.answer );
    const fd::ShownFiles sf = fd::shownFiles( ing, rows );
    if( sf.files.empty() )
    {
        return {};
    }
    const fd::Head head = fd::headOf( ing, rows, sf.rowFile );
    const std::vector<std::size_t> headTail = fd::headTailRows( rows );
    const std::string masked = headTail.empty() ? std::string() : fd::headTailMasked( a.answer, rows, headTail );
    std::vector<fd::Cand> cands = fd::collectCands( ing, sf, headTail.empty() ? a.answer : std::string_view( masked ), a.task );
    fd::creditCallees( ing, g, head, cands );
    fd::dedupeCands( ing, cands );
    fd::DeclHome home( ing, g );
    fd::collapseDeclarations( home, cands );
    fd::Picks picks = fd::pickRows( ing, g, cands );
    picks.binds     = fd::pickBinds( ing, sf, head, picks, a.answer );
    picks.inits     = fd::pickInits( ing, g, sf, fd::initHeads( ing, rows, sf, a.answer ), picks.initCut );
    if( picks.byName.empty() && picks.byCallee.empty() && picks.binds.rows.empty() && picks.inits.empty() && picks.initCut.count == 0 )
    {
        return {};
    }
    if( a.held )
    {
        return std::string( kForFileSymsHeldLegend ) + "<syms held=\"budget\"" + nextAttrXml( nextFlag( "--for=", a.task ) + std::string( a.heldFlags ) ) + "/>";
    }
    if( a.answerOut != nullptr && !headTail.empty() )
    {
        *a.answerOut = fd::tailRowsWithoutPicks( ing, a.answer, rows, headTail, picks );
    }
    return fd::blockXml( ing, sf, head, picks, a.compactLegend );
}
} // namespace rw
