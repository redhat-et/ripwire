// forrowlines.h — ROWLINES + RANKSEQ (lane FMT2, owner ruling 136, 2026-11-21): the rows of a finished answer-first `--for` answer's
// <sigs> and <tail> are served as TEXT LINES inside one CDATA per section, and a sigs row whose rank is the previous row's + 1 does
// not spell it.
//
// WHY. Lane FMT1 measured it on Claude's own token count (results FMT1_FORMAT_TOKENS_1121 §7, n=15 page-1 answers): the per-row
// markup (`<d l="` `" n="` `"/>` …) is paid on every row and carries no fact. Rows as lines: a median 743 tokens = 9.6 % of the
// answer; sequential ranks elided: a median 113 = 1.5 %; both 15 of 15 positive. G4 admits it (ruling 136): the answer stays
// well-formed XML and a newline appears only inside CDATA.
//
// THE FORM (the reference is FMT1's scripts/fmt1_codec.py: RANKSEQ, then ROWLINES with the space separator; this file is that
// codec's encode() byte for byte, its legend placement aside).
//   RANKSEQ   in the top-level <sigs>: when every <d>/<t> row carries a plain r=, a row whose r= is the previous row's + 1 (the
//             first row's: 1) AND is its last attribute drops it, and the section says so: <sigs … rseq="1">.
//   ROWLINES  in the top-level <sigs> and <tail>, when every child is an element: the children become lines joined by '\n' in ONE
//             CDATA.   <t p=P sym=SYMS k=v…/>            is   P SYMS<tab>k=v…          (values unescaped)
//                      <d l=L e=E n=N [sc=…] p=P k=v…>SIG</d>   is   P:L-E N k=v… | SIG      (a value with whitespace is "quoted")
//             A row the line grammar cannot give back EXACTLY (a <doc> child, another attribute order, a path with a space, an
//             &apos;) stays VERBATIM as its XML on its own line, which starts with '<'. Every line is proved by parsing it back
//             before it is used (parseLine below), so the inverse is total by construction, not by argument.
// One legend clause each (kRankSeqClause, kRowLinesClause), written last in the document legend, only when the form is used — or,
// on a page 1 whose root says the section goes on (continued=) or starts later (deferred=). A continuation page carries neither: it
// re-sends no legend (forpages.h), and page 1 defined its lines as it defines every other attribute of theirs.
// THREE DEVIATIONS FROM THE REFERENCE CODEC, all in the legend and none in a row: the clauses sit inside the root, last before
// </ctx> (the codec appended them after the last byte, outside the root); a continuation page has none and page 1 may carry one
// for a later page; and the line clause ends with what est_tokens= prices.
//
// LOSSLESS. Undoing the two clauses, the CDATA and rseq= rebuilds the element-form answer byte for byte: test/rowlinescheck.sh (L1)
// does it against the RIPWIRE_NO_ROWLINES=1 twin of the same binary, with a dropped-byte negative control. est_tokens= is NOT
// re-priced: it stays the element form's price, an UPPER bound on the bytes served (never an under-read), so a budget the element
// form fitted is still fitted and the rebuild needs no pricing model.
//
// WHERE IT RUNS. Last, on the bytes about to be written by the answer-first CLI path (verbs_for.h runForLens / fittedAnswerFirst):
// after the permutation, SIGX, the key body, the early stop, the budget fit and PAGING — so every stage before it reads rows as
// elements exactly as it did, a page holds the same rows it held, and each page is encoded on its own (a continuation page's first
// sigs row keeps its r=). Not on --legend=first's straight-through write, --json, or the MCP twin. RIPWIRE_NO_ROWLINES (any value)
// turns both off — the A/B handle, the RIPWIRE_NO_SIGX precedent — and --rows=lines|elements decides over it (rowLinesOn below).
#pragma once

#include <algorithm>
#include <charconv>
#include <cstddef>
#include <cstdlib>
#include <optional>
#include <string>
#include <string_view>
#include <vector>

#include "foranswerfirst.h"   // topLevelBlocks / rootBody — the one CDATA-safe scanner of a --for answer's blocks
#include "forrowsform.h"      // rowLinesOn — the switch: --rows= over RIPWIRE_NO_ROWLINES (cli.h reads the same header)

namespace rw::rowlines
{

inline constexpr std::string_view kRankSeqClause = "<!-- sigs rseq=1: a row with no r= has the previous row's r= plus 1 -->";
inline constexpr std::string_view kRowLinesClause =
    "<!-- sigs/tail rows are lines: 'P SYMS' is <t p=P sym=SYMS/> (a space between), then tab-separated k=v are its other attributes; "
    "'P:L-E N k=v.. | SIG' is <d p=P l=L e=E n=N k=v..>SIG</d>; values are unescaped; a line starting with &lt; is the row verbatim; "
    "est_tokens= may price the element form: an upper bound -->";

// ── the row reader: one open tag, strictly ` name="value"` attributes (values are escaped by the emitter, so they hold no raw '"').
struct Attr
{
    std::string_view name, value;   // value as it stands between the quotes: still escaped
};
struct OpenTag
{
    std::string_view  name;
    std::vector<Attr> attrs;
    bool              selfClosing = false;
    std::size_t       size        = 0;   // bytes of the tag, through its '>'
};

[[nodiscard]] constexpr bool isNameStart( char c ) noexcept { return ( c >= 'A' && c <= 'Z' ) || ( c >= 'a' && c <= 'z' ) || c == '_'; }
[[nodiscard]] constexpr bool isNameChar( char c ) noexcept { return isNameStart( c ) || ( c >= '0' && c <= '9' ) || c == '.' || c == ':' || c == '-'; }
[[nodiscard]] constexpr bool isSpaceByte( char c ) noexcept { return c == ' ' || ( c >= '\t' && c <= '\r' ); }   // the six ASCII whitespace bytes

// The end of the XML name starting at `at` (== at when none starts there).
[[nodiscard]] constexpr std::size_t nameEnd( std::string_view s, std::size_t at ) noexcept
{
    if( at >= s.size() || !isNameStart( s[ at ] ) ) { return at; }
    std::size_t i = at + 1;
    while( i < s.size() && isNameChar( s[ i ] ) ) { ++i; }
    return i;
}

// The open tag `row` begins with; nullopt on any shape that is not `<name( name="value")*>` or `…/>`.
[[nodiscard]] inline std::optional<OpenTag> readOpenTag( std::string_view row )
{
    if( !row.starts_with( '<' ) ) { return std::nullopt; }
    OpenTag     tag;
    std::size_t i = nameEnd( row, 1 );
    if( i == 1 ) { return std::nullopt; }
    tag.name = row.substr( 1, i - 1 );
    while( i < row.size() && row[ i ] == ' ' )
    {
        const std::size_t ne = nameEnd( row, i + 1 );
        const std::size_t q  = ne > i + 1 && row.compare( ne, 2, "=\"" ) == 0 ? row.find( '"', ne + 2 ) : std::string_view::npos;
        if( q == std::string_view::npos ) { return std::nullopt; }
        tag.attrs.push_back( { row.substr( i + 1, ne - i - 1 ), row.substr( ne + 2, q - ne - 2 ) } );
        i = q + 1;
    }
    tag.selfClosing = row.compare( i, 2, "/>" ) == 0;
    if( !tag.selfClosing && ( i >= row.size() || row[ i ] != '>' ) ) { return std::nullopt; }
    tag.size = i + ( tag.selfClosing ? 2 : 1 );
    return tag;
}

inline void appendOpenTag( std::string& out, std::string_view name, const std::vector<Attr>& attrs, bool selfClosing )
{
    out.append( "<" ).append( name );
    for( const Attr& a : attrs ) { out.append( " " ).append( a.name ).append( "=\"" ).append( a.value ).append( "\"" ); }
    out.append( selfClosing ? "/>" : ">" );
}

// ── escapes, as the reference codec defines them (NOT escapeXml's set: an &apos; or a control-character reference does not come back
// from escaped(), so a row holding one fails its parse-back proof and stays verbatim — the codec's own behaviour).
struct Entity
{
    char             raw;
    std::string_view spelled;
};
inline constexpr Entity kEntities[] = { { '&', "&amp;" }, { '<', "&lt;" }, { '>', "&gt;" }, { '"', "&quot;" }, { '\'', "&apos;" } };
inline constexpr std::size_t kTextEntityCount = 3;   // element text escapes & < > only
inline constexpr std::size_t kAttrEntityCount = 4;   // an attribute value also escapes the quote that would close it

[[nodiscard]] inline std::string unescaped( std::string_view v )
{
    std::string out;
    out.reserve( v.size() );
    for( std::size_t i = 0; i < v.size(); )
    {
        const auto e = v[ i ] == '&' ? std::ranges::find_if( kEntities, [ & ]( const Entity& k ) { return v.substr( i ).starts_with( k.spelled ); } ) : std::ranges::end( kEntities );
        out += e == std::ranges::end( kEntities ) ? v[ i ] : e->raw;
        i   += e == std::ranges::end( kEntities ) ? 1 : e->spelled.size();
    }
    return out;
}
// `v` with the first `entityCount` entities of kEntities spelled out.
[[nodiscard]] inline std::string escaped( std::string_view v, std::size_t entityCount )
{
    std::string out;
    out.reserve( v.size() + 16 );
    for( const char c : v )
    {
        const auto e = std::ranges::find( kEntities, kEntities + entityCount, c, &Entity::raw );
        if( e == kEntities + entityCount ) { out += c; } else { out.append( e->spelled ); }
    }
    return out;
}
[[nodiscard]] inline std::string escapedText( std::string_view v ) { return escaped( v, kTextEntityCount ); }
[[nodiscard]] inline std::string escapedAttr( std::string_view v ) { return escaped( v, kAttrEntityCount ); }

// ── RANKSEQ. The plain rank an r= value spells ([1-9][0-9]*), or 0.
[[nodiscard]] inline std::size_t plainRank( std::string_view v ) noexcept
{
    std::size_t rank = 0;
    const auto [ end, ec ] = std::from_chars( v.data(), v.data() + v.size(), rank );
    const bool plain = !v.empty() && v.front() >= '1' && v.front() <= '9' && ec == std::errc() && end == v.data() + v.size();
    return plain ? rank : 0;
}

// One child of a section, as the text it is served as: its bytes (r= dropped where RANKSEQ applies) and, for a <d>/<t> row, its tag.
struct Row
{
    std::string            xml;
    std::optional<OpenTag> tag;   // views into the DOCUMENT (the attribute list RANKSEQ left), not into `xml`
    std::string_view       rest;  // the document bytes after the open tag: a <d>'s text and close
};

// Drop the sequential ranks of `rows` in place. Returns whether any was dropped; nothing is touched unless EVERY <d>/<t> row carries
// a plain r= (the codec's all-or-nothing rule, so the inverse never meets a row whose rank it cannot tell).
inline bool elideSequentialRanks( std::vector<Row>& rows )
{
    const auto ranked = []( const Row& r ) { return r.tag && ( r.tag->name == "d" || r.tag->name == "t" ); };
    const auto rankOf = []( const Row& r )
    {
        const auto it = std::ranges::find( r.tag->attrs, std::string_view( "r" ), &Attr::name );
        return it == r.tag->attrs.end() ? std::size_t( 0 ) : plainRank( it->value );
    };
    if( std::ranges::none_of( rows, ranked ) || std::ranges::any_of( rows, [ & ]( const Row& r ) { return ranked( r ) && rankOf( r ) == 0; } ) ) { return false; }
    std::size_t previous = 0;
    bool        dropped  = false;
    for( Row& r : rows )
    {
        if( !ranked( r ) ) { continue; }
        const std::size_t rank = rankOf( r );
        if( rank == previous + 1 && r.tag->attrs.back().name == "r" )
        {
            r.tag->attrs.pop_back();
            r.xml.clear();
            appendOpenTag( r.xml, r.tag->name, r.tag->attrs, r.tag->selfClosing );
            r.xml.append( r.rest );
            dropped = true;
        }
        previous = rank;
    }
    return dropped;
}

// ── ROWLINES, the two line shapes. nullopt: the row has no line (it stays verbatim).
[[nodiscard]] inline std::optional<std::string> pointerLine( const std::vector<Attr>& attrs )
{
    if( attrs.empty() || attrs[ 0 ].name != "p" ) { return std::nullopt; }
    std::string       line = unescaped( attrs[ 0 ].value );
    const std::size_t rest = attrs.size() > 1 && attrs[ 1 ].name == "sym" ? 2 : 1;
    if( rest == 2 ) { line.append( " " ).append( unescaped( attrs[ 1 ].value ) ); }
    for( std::size_t i = rest; i < attrs.size(); ++i ) { line.append( "\t" ).append( attrs[ i ].name ).append( "=" ).append( unescaped( attrs[ i ].value ) ); }
    return line;
}
// A value a definition line may carry bare: empty, or no whitespace and no leading quote.
[[nodiscard]] inline bool bareValue( std::string_view v ) noexcept
{
    return v.empty() || ( v.front() != '"' && std::ranges::none_of( v, isSpaceByte ) );
}
[[nodiscard]] inline std::optional<std::string> definitionLine( const OpenTag& tag, std::string_view text )
{
    const auto named = [ & ]( std::string_view name ) { return std::ranges::find( tag.attrs, name, &Attr::name ); };
    const auto none  = tag.attrs.end(), p = named( "p" ), l = named( "l" ), e = named( "e" ), n = named( "n" );
    if( p == none || l == none || n == none ) { return std::nullopt; }
    std::string line = unescaped( p->value );
    line.append( ":" ).append( l->value );
    if( e != none ) { line.append( "-" ).append( e->value ); }
    line.append( " " ).append( unescaped( n->value ) );
    for( const Attr& a : tag.attrs )
    {
        if( a.name == "p" || a.name == "l" || a.name == "e" || a.name == "n" ) { continue; }
        const std::string v = unescaped( a.value );
        line.append( " " ).append( a.name ).append( "=" );
        if( bareValue( v ) ) { line.append( v ); } else { line.append( "\"" ).append( v ).append( "\"" ); }
    }
    if( !tag.selfClosing ) { line.append( " | " ).append( unescaped( text ) ); }
    return line;
}

// ── the parse-back: the row a line stands for. It is what a reader of the legend clause does, and the proof each line is held to.
[[nodiscard]] inline std::string parsePointerLine( std::string_view line )
{
    const std::size_t headEnd = std::min( line.find( '\t' ), line.size() );
    const std::size_t space   = line.substr( 0, headEnd ).find( ' ' );
    std::string       row     = "<t p=\"" + escapedAttr( line.substr( 0, std::min( space, headEnd ) ) ) + "\"";
    if( space != std::string_view::npos ) { row += " sym=\"" + escapedAttr( line.substr( space + 1, headEnd - space - 1 ) ) + "\""; }
    for( std::size_t at = headEnd; at < line.size(); )
    {
        const std::size_t      next  = std::min( line.find( '\t', at + 1 ), line.size() );
        const std::string_view field = line.substr( at + 1, next - at - 1 );
        const std::size_t      eq    = std::min( field.find( '=' ), field.size() );
        row.append( " " ).append( field.substr( 0, eq ) ).append( "=\"" ).append( escapedAttr( field.substr( std::min( eq + 1, field.size() ) ) ) ).append( "\"" );
        at = next;
    }
    return row + "/>";
}

// The head of a definition line, `P:L[-E] N`: P the shortest prefix that leaves a line span and a name behind it.
struct LineHead
{
    std::string_view path, first, last, name;   // last: empty when the line spells no -E
    std::size_t      end = 0;
};
[[nodiscard]] inline std::optional<LineHead> definitionHead( std::string_view line ) noexcept
{
    const auto digitsEnd = [ & ]( std::size_t i ) { while( i < line.size() && line[ i ] >= '0' && line[ i ] <= '9' ) { ++i; } return i; };
    for( std::size_t colon = line.find( ':', 1 ); colon != std::string_view::npos; colon = line.find( ':', colon + 1 ) )
    {
        const std::size_t firstEnd = digitsEnd( colon + 1 );
        if( firstEnd == colon + 1 ) { continue; }
        std::size_t at = firstEnd;
        LineHead    head{ line.substr( 0, colon ), line.substr( colon + 1, firstEnd - colon - 1 ), {}, {}, 0 };
        if( at < line.size() && line[ at ] == '-' && digitsEnd( at + 1 ) > at + 1 )
        {
            head.last = line.substr( at + 1, digitsEnd( at + 1 ) - at - 1 );
            at        = digitsEnd( at + 1 );
        }
        if( at >= line.size() || line[ at ] != ' ' ) { continue; }
        head.end = at + 1;
        while( head.end < line.size() && !isSpaceByte( line[ head.end ] ) ) { ++head.end; }
        if( head.end == at + 1 ) { continue; }
        head.name = line.substr( at + 1, head.end - at - 1 );
        return head;
    }
    return std::nullopt;
}

// One ` k=v` of a definition line at `at`: v bare (to the next whitespace, which must be a space or the end), empty, or "quoted".
struct LineAttr
{
    std::string_view name, value;
    std::size_t      end = 0;
};
[[nodiscard]] inline std::optional<LineAttr> definitionAttr( std::string_view line, std::size_t at ) noexcept
{
    const std::size_t ne = at < line.size() && line[ at ] == ' ' ? nameEnd( line, at + 1 ) : at + 1;
    if( ne <= at + 1 || ne >= line.size() || line[ ne ] != '=' ) { return std::nullopt; }
    const std::size_t v      = ne + 1;
    const auto        closes = [ & ]( std::size_t i ) { return i == line.size() || line[ i ] == ' '; };
    if( v < line.size() && line[ v ] == '"' )
    {
        const std::size_t q = line.find( '"', v + 1 );
        return q != std::string_view::npos && closes( q + 1 ) ? std::optional<LineAttr>( LineAttr{ line.substr( at + 1, ne - at - 1 ), line.substr( v + 1, q - v - 1 ), q + 1 } )
                                                              : std::nullopt;
    }
    std::size_t end = v;
    while( end < line.size() && !isSpaceByte( line[ end ] ) ) { ++end; }
    return closes( end ) ? std::optional<LineAttr>( LineAttr{ line.substr( at + 1, ne - at - 1 ), line.substr( v, end - v ), end } ) : std::nullopt;
}

// The <d> row a definition line stands for, in the emitter's attribute order (l e n [sc] p, then the rest); nullopt: not one.
[[nodiscard]] inline std::optional<std::string> parseDefinitionLine( std::string_view line )
{
    const std::optional<LineHead> head = definitionHead( line );
    if( !head ) { return std::nullopt; }
    std::vector<LineAttr> rest;
    std::size_t           at = head->end;
    for( std::optional<LineAttr> a = definitionAttr( line, at ); a; a = definitionAttr( line, at ) )
    {
        rest.push_back( *a );
        at = a->end;
    }
    const std::string_view sig = line.substr( at );
    if( !sig.empty() && !sig.starts_with( " | " ) ) { return std::nullopt; }
    const auto put = []( std::string& row, std::string_view name, std::string_view value ) { row.append( " " ).append( name ).append( "=\"" ).append( value ).append( "\"" ); };
    std::string row = "<d";
    put( row, "l", head->first );
    if( !head->last.empty() ) { put( row, "e", head->last ); }
    put( row, "n", escapedAttr( head->name ) );
    const std::size_t scoped = !rest.empty() && rest.front().name == "sc" ? 1 : 0;
    if( scoped == 1 ) { put( row, "sc", escapedAttr( rest.front().value ) ); }
    put( row, "p", escapedAttr( head->path ) );
    for( std::size_t i = scoped; i < rest.size(); ++i ) { put( row, rest[ i ].name, escapedAttr( rest[ i ].value ) ); }
    return sig.empty() ? row + "/>" : row + ">" + escapedText( sig.substr( 3 ) ) + "</d>";
}

// A line read back: verbatim XML, else a definition, else a pointer — the order the legend clause gives a reader.
[[nodiscard]] inline std::string parseLine( std::string_view line )
{
    if( line.starts_with( '<' ) ) { return std::string( line ); }
    std::optional<std::string> d = parseDefinitionLine( line );
    return d ? std::move( *d ) : parsePointerLine( line );
}

// The line one row is served as: its line form when that parses back to the row exactly, else the row itself.
[[nodiscard]] inline std::string lineOf( const Row& row )
{
    std::optional<std::string> line;
    if( row.tag && row.tag->name == "t" && row.tag->selfClosing )
    {
        line = pointerLine( row.tag->attrs );
    }
    else if( row.tag && row.tag->name == "d" && ( row.tag->selfClosing || ( row.rest.ends_with( "</d>" ) && row.rest.find( '<' ) == row.rest.size() - 4 ) ) )
    {
        line = definitionLine( *row.tag, row.tag->selfClosing ? std::string_view() : row.rest.substr( 0, row.rest.size() - 4 ) );
    }
    const bool usable = line && !line->starts_with( '<' ) && line->find( '\n' ) == std::string::npos && parseLine( *line ) == row.xml;
    return usable ? std::move( *line ) : row.xml;
}

// ── one section. Its children as rows; nullopt when the section is self-closing, empty or not read (a child tag of another shape, or
// text between the children, which minified output never has).
struct Section
{
    std::string_view open;       // the open tag, without its '>'
    std::vector<Row> rows;
    bool             elementsOnly = true;   // no comment child: the shape ROWLINES rewrites
    std::string_view close;      // "</name>"
};
[[nodiscard]] inline std::optional<Section> readSection( std::string_view doc, const answerfirst::Block& b )
{
    const std::size_t open  = doc.find( '>', b.begin ) + 1;
    const std::size_t close = doc.rfind( "</", b.end - 1 );
    if( doc[ open - 2 ] == '/' || close == std::string_view::npos || close < open ) { return std::nullopt; }
    Section     sec{ doc.substr( b.begin, open - 1 - b.begin ), {}, true, doc.substr( close, b.end - close ) };
    std::size_t at = open;
    for( const answerfirst::Block& k : answerfirst::topLevelBlocks( doc, open, close ) )
    {
        const std::string_view xml = doc.substr( k.begin, k.end - k.begin );
        Row                    row{ std::string( xml ), k.comment ? std::nullopt : readOpenTag( xml ), {} };
        if( ( !k.comment && !row.tag ) || k.begin != at ) { return std::nullopt; }
        if( row.tag ) { row.rest = xml.substr( row.tag->size ); }
        sec.elementsOnly = sec.elementsOnly && !k.comment;
        at               = k.end;
        sec.rows.push_back( std::move( row ) );
    }
    return sec.rows.empty() || at != close ? std::nullopt : std::optional<Section>( std::move( sec ) );
}

// What one pass did to a document: which of the two forms it wrote.
struct Applied
{
    bool rankSeq = false, rowLines = false;
};

// One top-level <sigs>/<tail> block re-emitted into `out` (verbatim when neither form applies to it).
inline void encodeSection( std::string_view doc, const answerfirst::Block& b, std::string& out, Applied& applied )
{
    std::optional<Section> sec = readSection( doc, b );
    const bool rankSeq = sec && b.name == "sigs" && sec->open.find( " rseq=\"" ) == std::string_view::npos && elideSequentialRanks( sec->rows );
    std::string body;
    for( std::size_t i = 0; sec && sec->elementsOnly && i < sec->rows.size(); ++i )
    {
        body.append( i > 0 ? "\n" : "" ).append( lineOf( sec->rows[ i ] ) );
    }
    // a verbatim row holding a newline would split into two lines, and "]]>" would end the CDATA: such a section keeps its elements
    const bool rowLines = sec && sec->elementsOnly && body.find( "]]>" ) == std::string::npos
                       && std::ranges::count( body, '\n' ) == std::ranges::ssize( sec->rows ) - 1;
    if( !rankSeq && !rowLines )
    {
        out.append( doc.substr( b.begin, b.end - b.begin ) );
        return;
    }
    out.append( sec->open ).append( rankSeq ? " rseq=\"1\">" : ">" );
    if( rowLines )
    {
        out.append( "<![CDATA[" ).append( body ).append( "]]>" );
    }
    else
    {
        for( const Row& r : sec->rows ) { out.append( r.xml ); }
    }
    out.append( sec->close );
    applied.rankSeq  = applied.rankSeq || rankSeq;
    applied.rowLines = applied.rowLines || rowLines;
}

// Page 1 of several names, on its root, the section that goes on past it (continued=) and the ones that start later (deferred=).
// The continuation pages carry no legend — page 1's defines them — so page 1 defines the line form for a section it names there.
[[nodiscard]] inline bool laterPageHolds( std::string_view rootOpen, std::string_view section ) noexcept
{
    if( rootOpen.find( " page=\"1\"" ) == std::string_view::npos ) { return false; }
    for( const std::string_view key : { " continued=\"", " deferred=\"" } )
    {
        const std::size_t at = rootOpen.find( key );
        if( at == std::string_view::npos ) { continue; }
        const std::string_view value = rootOpen.substr( at + key.size(), rootOpen.find( '"', at + key.size() ) - at - key.size() );
        for( std::size_t w = value.find( section ); w != std::string_view::npos; w = value.find( section, w + 1 ) )
        {
            const bool starts = w == 0 || value[ w - 1 ] == ' ';
            const bool ends   = w + section.size() == value.size() || value[ w + section.size() ] == ' ';
            if( starts && ends ) { return true; }
        }
    }
    return false;
}

// THE CLAUSES an answer writes, given the forms it used. A continuation page (page= above 1) re-sends no legend — forpages.h: page
// 1's defines its attributes — so it gets neither; page 1 writes the clause of a form it used, or of a section it names as going on
// or starting later.
[[nodiscard]] inline Applied clausesFor( std::string_view rootOpen, const Applied& applied ) noexcept
{
    if( rootOpen.find( " page=\"" ) != std::string_view::npos && rootOpen.find( " page=\"1\"" ) == std::string_view::npos ) { return {}; }
    const bool sigsLater = laterPageHolds( rootOpen, "sigs" );
    return { applied.rankSeq || sigsLater, applied.rowLines || sigsLater || laterPageHolds( rootOpen, "tail" ) };
}

// Rewrite `doc` (the bytes of a finished answer-first --for answer or of one page of it) in place. Returns whether it changed.
// `rows`: --rows= as typed (Config::rowsSpec; empty = not typed), read by rowLinesOn.
inline bool encodeRows( std::string& doc, std::string_view rows = {} )
{
    const std::string_view                     view = doc;
    // an answer-first document OPENS with its root; anything else (a legend-first answer, JSON, a refusal) is served as it is
    const std::optional<answerfirst::RootBody> rb   = rowLinesOn( rows ) && view.starts_with( "<ctx" ) ? answerfirst::rootBody( view ) : std::nullopt;
    if( !rb ) { return false; }
    Applied     applied;
    std::string out;
    out.reserve( doc.size() + kRankSeqClause.size() + kRowLinesClause.size() );
    std::size_t copied = 0;
    for( const answerfirst::Block& b : answerfirst::topLevelBlocks( view, rb->openEnd + 1, rb->closeAt ) )
    {
        if( b.comment || ( b.name != "sigs" && b.name != "tail" ) ) { continue; }
        out.append( view.substr( copied, b.begin - copied ) );
        encodeSection( view, b, out, applied );
        copied = b.end;
    }
    const Applied clauses = clausesFor( view.substr( 0, rb->openEnd ), applied );
    if( !applied.rankSeq && !applied.rowLines && !clauses.rankSeq && !clauses.rowLines ) { return false; }
    out.append( view.substr( copied, rb->closeAt - copied ) );
    out.append( clauses.rankSeq ? kRankSeqClause : std::string_view() ).append( clauses.rowLines ? kRowLinesClause : std::string_view() );
    out.append( view.substr( rb->closeAt ) );
    doc.swap( out );
    return true;
}

}   // namespace rw::rowlines
