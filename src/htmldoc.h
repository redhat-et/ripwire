#pragma once
// htmldoc.h — DOCS-UNITS (D5): an HTML page as a SECTION TREE over its body, not as one flat string.
//
// What --recall used to get from a rendered docs page was the whole page flattened: every tag a space, every
// sidebar, header, search box, table of contents and footer included. A MkDocs page is ~97 % chrome by bytes
// (reports/docs-lab.md), so the first 2 KB served was navigation and the answer sat 100 KB further down. The
// lab that picked this design (tmp/docs-lab, arm A0u: Complete 25 -> 51 of 79 dev rows, 2 -> 13 of 28 held)
// measured chrome removal alone as a small win and section units on top of it as the large one; this file is
// the extraction half, recall.h the scoring half.
//
// THREE RULES, each general (no generator, site or path is named anywhere below):
//   1. BODY REGION. The text comes from the page's content region: every <main> element (or role="main"), else
//      every <article>, else every element whose class or id carries a content word (content, main), else the
//      whole <body>. A region that yields no text at all (a page its scripts fill in) falls back to the body.
//   2. CHROME. Inside the region, these never reach the text: script, style, template, noscript, svg, nav,
//      aside, footer, form, button, select, an element with the `hidden` attribute or a chrome ARIA role (navigation,
//      search, banner, contentinfo, complementary), and an element whose class
//      or id carries a chrome word (sidebar, nav, navbar, navigation, toc, menu, breadcrumb, footer, search,
//      skip, headerlink, …: kChromeWords) — except <html>, <body> and the region element itself, whose classes
//      are page state (`sidebar-visible`). Without a region, <header> is chrome too (it holds the site's own
//      title and links); inside a region a <header> is kept, since an article's header holds its h1.
//   3. UNITS. h1-h6 open a unit; so does a <section id="…">, named by the heading that opens it or else by its
//      id (pdoc members). On a page that HAS section ids, h3-h6 stay inside their member: they are docstring
//      headings ("Arguments", "Example"), not structure, and splitting on them cut a member from its signature.
//
// THE TEXT IS LINE-PRESERVING: line k of the extracted text holds what raw line k of the file shows, and a raw
// line holding only markup or chrome is an empty line. That is what lets a unit carry `lines=` that name the
// FILE's own lines (an agent can open page.html at them, and a grader can check the span), with no line map
// stored anywhere: the extracted text's line numbers ARE the file's. Whitespace inside a line collapses to one
// space; <pre> keeps its spacing. Inline tags (a, code, span, em, …) join their text without a space, so
// `<code><span>re</span><span>.</span><span>compile</span></code>` reads `re.compile`, the literal an agent
// greps for; every other tag separates words.
//
// Determinism: a pure function of the bytes, one forward pass after a one-pass region probe; no allocation per
// character, no regex. Gate: test/docsunitscheck.sh (chrome, region, section ids, line mapping).

#include "infra/jsonesc.h"       // jsonesc::appendUtf8 — the one code-point encoder
#include "infra/tablelookup.h"   // rw::findByField — the one small-constexpr-table scan

#include <algorithm>
#include <array>
#include <cctype>
#include <cstdint>
#include <string>
#include <string_view>
#include <vector>

namespace rw
{
namespace docparse
{

struct HtmlHeading
{
    std::uint32_t startByte = 0;   // where the unit starts in HtmlDoc::text (the opening tag's position)
    std::uint32_t sigEnd    = 0;   // end of the heading construct (its closing tag); == startByte for a bare section id
    std::uint32_t endByte   = 0;   // SUBTREE end: the next unit of the same or a shallower level, else the text's end
    std::uint32_t line      = 0;   // 1-based raw line of the opening tag (== the text's line, by construction)
    std::uint32_t level     = 0;   // 1..6 for h1-h6; nesting depth for a section id
    bool          isSectionId = false;
    std::string   name;            // heading text, whitespace-collapsed; a bare section's id
    std::string   id;              // the id attribute (heading's, or the section's), "" when none
};

struct HtmlDoc
{
    std::string              text;       // line-preserving body text (see the header comment)
    std::vector<HtmlHeading> headings;   // unit boundaries, in byte order
    bool                     hasRegion = false;   // a content region was found and used (rule 1)
    std::uint32_t            titleBegin = 0;      // the page <title>'s text in `text`: [titleBegin, titleEnd), on its own raw
    std::uint32_t            titleEnd   = 0;      // line(s); blanked again when the page has units (see extractHtmlDoc)
};

namespace htmldetail
{

// Does s, at offset p, begin with `lowerLit` (already lower case), ignoring the case of s?
inline bool startsWithLower( std::string_view s, std::size_t p, std::string_view lowerLit ) noexcept
{
    return p <= s.size() && s.size() - p >= lowerLit.size()
        && std::equal( lowerLit.begin(), lowerLit.end(), s.begin() + std::ptrdiff_t( p ),
                       []( char lit, char c ) { return lit == char( std::tolower( static_cast<unsigned char>( c ) ) ); } );
}

// One tag, read in place. `name` is lower-cased into a fixed buffer: every name this file compares against is
// short, and a longer one (a custom element) only ever needs to be "not one of ours".
struct Tag
{
    std::array<char, 16> nameBuf{};
    std::size_t          nameLen     = 0;
    bool                 isEnd       = false;
    bool                 isSelfClose = false;
    std::size_t          attrsBegin  = 0;   // first byte after the name
    std::size_t          end         = 0;   // one past the closing '>' (or the input's end)

    std::string_view name() const noexcept { return { nameBuf.data(), nameLen }; }
};

// Read the tag that starts at html[i] == '<' (an element tag, not a comment or declaration). Quoted attribute
// values may hold '>', so the scan honours quotes.
inline Tag readTag( std::string_view html, std::size_t i ) noexcept
{
    Tag t;
    std::size_t p = i + 1;
    if( p < html.size() && html[ p ] == '/' )
    {
        t.isEnd = true;
        ++p;
    }
    while( p < html.size() )
    {
        const char c = html[ p ];
        const bool isNameByte = ( c >= 'a' && c <= 'z' ) || ( c >= 'A' && c <= 'Z' ) || ( c >= '0' && c <= '9' ) || c == '-' || c == ':';
        if( !isNameByte )
        {
            break;
        }
        if( t.nameLen < t.nameBuf.size() )
        {
            t.nameBuf[ t.nameLen ] = char( std::tolower( static_cast<unsigned char>( c ) ) );
        }
        ++t.nameLen;
        ++p;
    }
    if( t.nameLen > t.nameBuf.size() )
    {
        t.nameLen = 0;   // too long to be any element this file knows: an anonymous tag
    }
    t.attrsBegin = p;
    char quote   = 0;
    for( ; p < html.size(); ++p )
    {
        const char c = html[ p ];
        if( quote )
        {
            if( c == quote )
            {
                quote = 0;
            }
            continue;
        }
        if( c == '"' || c == '\'' )
        {
            quote = c;
            continue;
        }
        if( c == '>' )
        {
            t.isSelfClose = p > t.attrsBegin && html[ p - 1 ] == '/';
            t.end         = p + 1;
            return t;
        }
    }
    t.end = html.size();
    return t;
}

// The value of attribute `attr` (lower-case) inside [from, to), or {} when absent. `isPresent` reports a bare
// attribute (`hidden`), which has no value.
inline std::string_view attrValue( std::string_view html, std::size_t from, std::size_t to, std::string_view attr, bool* isPresent = nullptr ) noexcept
{
    std::size_t p = from;
    while( p < to )
    {
        while( p < to && ( html[ p ] == ' ' || html[ p ] == '\t' || html[ p ] == '\n' || html[ p ] == '\r' || html[ p ] == '/' ) )
        {
            ++p;
        }
        const std::size_t nameStart = p;
        while( p < to && html[ p ] != '=' && html[ p ] != ' ' && html[ p ] != '\t' && html[ p ] != '\n' && html[ p ] != '\r' && html[ p ] != '>'
               && html[ p ] != '/' )
        {
            ++p;
        }
        const std::size_t nameLen = p - nameStart;
        if( nameLen == 0 )
        {
            ++p;   // a stray byte (a lone '=' or '>'): step over it so the scan always advances
            continue;
        }
        const bool isMatch = nameLen == attr.size() && startsWithLower( html, nameStart, attr );
        while( p < to && ( html[ p ] == ' ' || html[ p ] == '\t' ) )
        {
            ++p;
        }
        if( p >= to || html[ p ] != '=' )
        {
            if( isMatch && isPresent )
            {
                *isPresent = true;
            }
            continue;   // a bare attribute
        }
        ++p;
        while( p < to && ( html[ p ] == ' ' || html[ p ] == '\t' ) )
        {
            ++p;
        }
        std::size_t valStart = p;
        std::size_t valEnd   = p;
        if( p < to && ( html[ p ] == '"' || html[ p ] == '\'' ) )
        {
            const char q = html[ p ];
            valStart     = p + 1;
            valEnd       = valStart;
            while( valEnd < to && html[ valEnd ] != q )
            {
                ++valEnd;
            }
            p = valEnd < to ? valEnd + 1 : to;
        }
        else
        {
            while( valEnd < to && html[ valEnd ] != ' ' && html[ valEnd ] != '\t' && html[ valEnd ] != '\n' && html[ valEnd ] != '>' )
            {
                ++valEnd;
            }
            p = valEnd;
        }
        if( isMatch )
        {
            if( isPresent )
            {
                *isPresent = true;
            }
            return html.substr( valStart, valEnd - valStart );
        }
    }
    return {};
}

// Does a class/id value carry one of `words`? A value is split on whitespace, '-' and '_', so `md-sidebar`,
// `sidebar-scrollbox` and `nav_wrapper` all carry their word, and `navigation-tabs` carries `navigation`, while
// `canvas` carries no `nav`: only whole words count. Case-insensitive.
template<std::size_t N>
inline bool carriesWord( std::string_view value, const std::array<std::string_view, N>& words ) noexcept
{
    std::size_t p = 0;
    while( p < value.size() )
    {
        while( p < value.size() && ( value[ p ] == ' ' || value[ p ] == '\t' || value[ p ] == '\n' || value[ p ] == '-' || value[ p ] == '_' ) )
        {
            ++p;
        }
        const std::size_t start = p;
        while( p < value.size() && value[ p ] != ' ' && value[ p ] != '\t' && value[ p ] != '\n' && value[ p ] != '-' && value[ p ] != '_' )
        {
            ++p;
        }
        const std::string_view word = value.substr( start, p - start );
        for( const std::string_view w : words )
        {
            if( word.size() == w.size() && startsWithLower( word, 0, w ) )
            {
                return true;
            }
        }
    }
    return false;
}

inline constexpr std::array<std::string_view, 17> kChromeWords = { "breadcrumb", "breadcrumbs", "contents", "footer", "headerlink", "menu", "nav",
                                                                    "navbar",     "navigation",  "pagetoc",  "search", "searchbar",  "sidebar", "skip",
                                                                    "toc",        "topbar",      "toolbar" };
// ARIA landmark roles that are chrome by declaration (role="search" on a div is a search box whatever its class says).
inline constexpr std::array<std::string_view, 5>  kChromeRoles  = { "banner", "complementary", "contentinfo", "navigation", "search" };
inline constexpr std::array<std::string_view, 3>  kContentWords = { "content", "main", "maincontent" };

// How a tag name behaves in the extractor: CHROME elements' content is never page prose, whatever region they sit
// in; INLINE tags do not separate words (their text joins the text around them); VOID tags have no end tag.
enum class TagClass : std::uint8_t
{
    Other,
    Chrome,
    Inline,
    Void,
};
struct TagClassRow
{
    std::string_view name;
    TagClass         cls;
};
inline constexpr TagClassRow kTagClasses[] = {
    { "aside", TagClass::Chrome }, { "button", TagClass::Chrome }, { "footer", TagClass::Chrome }, { "form", TagClass::Chrome },
    { "head", TagClass::Chrome },  { "nav", TagClass::Chrome },    { "noscript", TagClass::Chrome }, { "script", TagClass::Chrome },
    { "select", TagClass::Chrome }, { "style", TagClass::Chrome }, { "svg", TagClass::Chrome },   { "template", TagClass::Chrome },
    { "textarea", TagClass::Chrome },
    { "a", TagClass::Inline },     { "abbr", TagClass::Inline },   { "b", TagClass::Inline },      { "cite", TagClass::Inline },
    { "code", TagClass::Inline },  { "data", TagClass::Inline },   { "dfn", TagClass::Inline },    { "em", TagClass::Inline },
    { "i", TagClass::Inline },     { "kbd", TagClass::Inline },    { "mark", TagClass::Inline },   { "q", TagClass::Inline },
    { "s", TagClass::Inline },     { "samp", TagClass::Inline },   { "small", TagClass::Inline },  { "span", TagClass::Inline },
    { "strong", TagClass::Inline }, { "sub", TagClass::Inline },   { "sup", TagClass::Inline },    { "time", TagClass::Inline },
    { "u", TagClass::Inline },     { "var", TagClass::Inline },
    { "area", TagClass::Void },    { "base", TagClass::Void },     { "br", TagClass::Void },       { "col", TagClass::Void },
    { "embed", TagClass::Void },   { "hr", TagClass::Void },       { "img", TagClass::Void },      { "input", TagClass::Void },
    { "link", TagClass::Void },    { "meta", TagClass::Void },     { "param", TagClass::Void },    { "source", TagClass::Void },
    { "track", TagClass::Void },   { "wbr", TagClass::Void },      { "keygen", TagClass::Void },
};

inline TagClass tagClassOf( std::string_view n ) noexcept
{
    const std::size_t k = findIndexByField( kTagClasses, &TagClassRow::name, n );
    return k < std::size( kTagClasses ) ? kTagClasses[ k ].cls : TagClass::Other;
}

inline int headingLevelOf( std::string_view n ) noexcept
{
    return ( n.size() == 2 && n[ 0 ] == 'h' && n[ 1 ] >= '1' && n[ 1 ] <= '6' ) ? n[ 1 ] - '0' : 0;
}

enum class Region : std::uint8_t { Body, Main, Article, ContentClass };

// Rule 1's probe: which region kind this page has, best first. One pass over the tags, comments skipped.
inline Region probeRegion( std::string_view html ) noexcept
{
    bool hasArticle = false, hasContentClass = false;
    for( std::size_t i = html.find( '<' ); i != std::string_view::npos && i < html.size(); i = html.find( '<', i + 1 ) )
    {
        if( html.substr( i, 4 ) == "<!--" )
        {
            const std::size_t close = html.find( "-->", i + 4 );
            if( close == std::string_view::npos )
            {
                break;
            }
            i = close;
            continue;
        }
        const Tag t = readTag( html, i );
        if( t.isEnd || t.nameLen == 0 )
        {
            continue;
        }
        if( t.name() == "main" || attrValue( html, t.attrsBegin, t.end, "role" ) == "main" )
        {
            return Region::Main;
        }
        hasArticle = hasArticle || t.name() == "article";
        if( !hasContentClass && t.name() == "div" )
        {
            hasContentClass = carriesWord( attrValue( html, t.attrsBegin, t.end, "class" ), kContentWords )
                           || carriesWord( attrValue( html, t.attrsBegin, t.end, "id" ), kContentWords );
        }
        if( t.name() == "script" || t.name() == "style" )
        {
            const std::size_t close = html.find( t.name() == "script" ? "</script" : "</style", t.end );   // raw text: no tags inside
            i = close == std::string_view::npos ? html.size() : close;
        }
    }
    return hasArticle ? Region::Article : hasContentClass ? Region::ContentClass : Region::Body;
}

struct OpenElement
{
    std::array<char, 16> nameBuf{};
    std::size_t          nameLen     = 0;
    bool                 isSkip      = false;
    bool                 isRegion    = false;
    bool                 isPre       = false;
    int                  headingSlot = -1;   // index into headings while a heading is open
    bool                 isSection   = false;

    std::string_view name() const noexcept { return { nameBuf.data(), nameLen }; }
};

// A numeric reference's code point as UTF-8; NUL, surrogates and out-of-range values become one space.
inline void appendCodePoint( std::string& out, std::uint32_t cp )
{
    if( cp == 0 || cp > 0x10FFFF || ( cp >= 0xD800 && cp <= 0xDFFF ) )
    {
        out.push_back( ' ' );
        return;
    }
    jsonesc::appendUtf8( out, cp );
}

// Decode the entity at html[i] == '&' into `out`; returns the index after it, or i + 1 with '&' copied when it is
// not an entity. Numeric entities decode to UTF-8; the five XML names and &nbsp; decode; any other name becomes
// one space (it is punctuation or a symbol, never a token an agent searches for).
inline std::size_t decodeEntity( std::string_view html, std::size_t i, std::string& out )
{
    const std::size_t semi = html.find( ';', i );
    if( semi == std::string_view::npos || semi - i > 10 || semi == i + 1 )
    {
        out.push_back( '&' );
        return i + 1;
    }
    const std::string_view ent = html.substr( i + 1, semi - i - 1 );
    if( ent[ 0 ] == '#' )
    {
        std::uint32_t cp    = 0;
        const bool    isHex = ent.size() > 1 && ( ent[ 1 ] == 'x' || ent[ 1 ] == 'X' );
        for( std::size_t k = isHex ? 2 : 1; k < ent.size(); ++k )
        {
            const char c = ent[ k ];
            int        d = -1;
            if( c >= '0' && c <= '9' ) { d = c - '0'; }
            else if( isHex && c >= 'a' && c <= 'f' ) { d = c - 'a' + 10; }
            else if( isHex && c >= 'A' && c <= 'F' ) { d = c - 'A' + 10; }
            if( d < 0 || cp > 0x10FFFF )
            {
                out.push_back( '&' );
                return i + 1;
            }
            cp = cp * ( isHex ? 16u : 10u ) + std::uint32_t( d );
        }
        appendCodePoint( out, cp );
        return semi + 1;
    }
    for( const char c : ent )
    {
        if( !( ( c >= 'a' && c <= 'z' ) || ( c >= 'A' && c <= 'Z' ) || ( c >= '0' && c <= '9' ) ) )
        {
            out.push_back( '&' );
            return i + 1;
        }
    }
    if( ent == "amp" ) { out.push_back( '&' ); }
    else if( ent == "lt" ) { out.push_back( '<' ); }
    else if( ent == "gt" ) { out.push_back( '>' ); }
    else if( ent == "quot" ) { out.push_back( '"' ); }
    else if( ent == "apos" ) { out.push_back( '\'' ); }
    else { out.push_back( ' ' ); }
    return semi + 1;
}

// The extraction pass for one region choice. Split from extractHtmlDoc so the empty-region fallback is a second
// call with Region::Body rather than a flag threaded through the loop.
class Extractor
{
public:
    Extractor( std::string_view html, Region region ) : html_( html ), region_( region ) { out_.reserve( html.size() / 3 ); }

    HtmlDoc run()
    {
        for( std::size_t i = 0; i < html_.size(); )
        {
            const char c = html_[ i ];
            if( c == '<' )
            {
                i = onAngle( i );
            }
            else if( c == '&' )
            {
                i = isEmitting() ? decodeEntity( html_, i, out_ ) : i + 1;
                markText();
            }
            else
            {
                onChar( c );
                ++i;
            }
        }
        finishOpenHeadings();
        HtmlDoc doc;
        doc.text      = std::move( out_ );
        doc.headings  = std::move( heads_ );
        doc.hasRegion = region_ != Region::Body;
        doc.titleBegin = titleBegin_;
        doc.titleEnd   = titleEnd_;
        return doc;
    }

private:
    bool isEmitting() const noexcept { return skipDepth_ == 0 && ( region_ == Region::Body || regionDepth_ > 0 ); }

    void newline()
    {
        while( !out_.empty() && out_.back() == ' ' )
        {
            out_.pop_back();
        }
        out_.push_back( '\n' );
        ++line_;
    }

    void space()
    {
        if( !out_.empty() && out_.back() != ' ' && out_.back() != '\n' )
        {
            out_.push_back( ' ' );
        }
    }

    void markText() noexcept
    {
        if( isEmitting() )
        {
            sawTextSinceSection_ = true;
        }
    }

    void onChar( char c )
    {
        if( c == '\n' )
        {
            newline();   // EVERY raw newline, emitting or not: the line mapping is the whole point
            return;
        }
        if( !isEmitting() || c == '\r' )
        {
            return;
        }
        if( preDepth_ == 0 && ( c == ' ' || c == '\t' || c == '\f' || c == '\v' ) )
        {
            space();
            return;
        }
        out_.push_back( c );
        sawTextSinceSection_ = true;
    }

    // Copy the newlines of html_[from, to) — the bytes of a tag, comment or skipped raw-text element.
    void newlinesIn( std::size_t from, std::size_t to )
    {
        const auto first = html_.begin() + std::ptrdiff_t( from );
        for( auto lineCount = std::count( first, first + std::ptrdiff_t( to - from ), '\n' ); lineCount > 0; --lineCount )
        {
            newline();
        }
    }

    std::size_t skipTo( std::size_t from, std::string_view closeLower )
    {
        std::size_t k = from;
        while( k < html_.size() && !startsWithLower( html_, k, closeLower ) )
        {
            ++k;
        }
        if( !( !isPastHead_ && titleEnd_ == 0 && closeLower == "</title" ) )
        {
            newlinesIn( from, k );   // the page title's own newlines are emitted by emitPageTitle
        }
        return k;
    }

    // The page <title>, one collapsed line of text where it sits, so a heading-less page's text still opens with its
    // name (HTML-CUT repeats that first line above a window it serves). Newlines inside it are kept: line k stays line k.
    void emitPageTitle( std::size_t from, std::size_t to )
    {
        space();
        titleBegin_ = std::uint32_t( out_.size() );
        for( std::size_t k = from; k < to; )
        {
            const char c = html_[ k ];
            if( c == '&' )
            {
                k = decodeEntity( html_, k, out_ );
                continue;
            }
            if( c == '\n' )
            {
                newline();
            }
            else if( c == ' ' || c == '\t' || c == '\r' )
            {
                space();
            }
            else
            {
                out_.push_back( c );
            }
            ++k;
        }
        titleEnd_ = std::uint32_t( out_.size() );
        if( titleEnd_ == titleBegin_ )
        {
            titleBegin_ = titleEnd_ = 0;   // an empty title is none
        }
        space();
    }

    std::size_t onAngle( std::size_t i )
    {
        if( html_.substr( i, 4 ) == "<!--" )
        {
            const std::size_t close = html_.find( "-->", i + 4 );
            const std::size_t end   = close == std::string_view::npos ? html_.size() : close + 3;
            newlinesIn( i, end );
            return end;
        }
        if( i + 1 < html_.size() && ( html_[ i + 1 ] == '!' || html_[ i + 1 ] == '?' ) )
        {
            const std::size_t close = html_.find( '>', i );
            const std::size_t end   = close == std::string_view::npos ? html_.size() : close + 1;
            newlinesIn( i, end );
            return end;
        }
        const bool isTagStart = i + 1 < html_.size()
                             && ( ( html_[ i + 1 ] >= 'a' && html_[ i + 1 ] <= 'z' ) || ( html_[ i + 1 ] >= 'A' && html_[ i + 1 ] <= 'Z' ) || html_[ i + 1 ] == '/' );
        if( !isTagStart )
        {
            onChar( '<' );   // a literal '<' in text ("a < b")
            return i + 1;
        }
        const Tag t = readTag( html_, i );
        newlinesIn( i, t.end );
        if( t.isEnd )
        {
            onEndTag( t );
        }
        else
        {
            onStartTag( t );
            isPastHead_ = isPastHead_ || t.name() == "body";
            if( !t.isSelfClose && ( t.name() == "script" || t.name() == "style" || t.name() == "textarea" || t.name() == "title" ) )
            {
                // raw text: no markup inside, and none of it is page prose here (a page <title> sits in <head>)
                std::string closeTag = "</";
                closeTag += t.name();
                const std::size_t k = skipTo( t.end, closeTag );
                if( t.name() == "title" && !isPastHead_ && titleEnd_ == 0 )
                {
                    emitPageTitle( t.end, k );
                }
                return k;
            }
        }
        return t.end;
    }

    void onStartTag( const Tag& t )
    {
        const std::string_view n = t.name();
        if( n.empty() || tagClassOf( n ) == TagClass::Void || t.isSelfClose )
        {
            if( isEmitting() && tagClassOf( n ) != TagClass::Inline && !( preDepth_ > 0 ) )
            {
                space();
            }
            return;
        }
        const std::string_view cls  = attrValue( html_, t.attrsBegin, t.end, "class" );
        const std::string_view id   = attrValue( html_, t.attrsBegin, t.end, "id" );
        bool                   isHidden = false;
        attrValue( html_, t.attrsBegin, t.end, "hidden", &isHidden );

        OpenElement e;
        e.nameLen = std::min( n.size(), e.nameBuf.size() );
        std::copy_n( n.begin(), e.nameLen, e.nameBuf.begin() );
        e.isRegion = isRegionStart( t, n, cls, id );
        // the document's own frame (html, body) and a region element carry PAGE-STATE classes (`sidebar-visible`,
        // `nav-open`), never chrome of their own: a class word only marks an element inside them
        const bool isFrame = n == "html" || n == "body" || e.isRegion;
        e.isSkip   = tagClassOf( n ) == TagClass::Chrome
                  || ( !isFrame && ( isHidden || carriesWord( cls, kChromeWords ) || carriesWord( id, kChromeWords )
                                     || carriesWord( attrValue( html_, t.attrsBegin, t.end, "role" ), kChromeRoles ) ) )
                  || ( n == "header" && region_ == Region::Body );
        e.isPre    = n == "pre";

        if( e.isRegion )
        {
            ++regionDepth_;
        }
        if( e.isSkip )
        {
            ++skipDepth_;
        }
        if( isEmitting() )
        {
            if( tagClassOf( n ) != TagClass::Inline && preDepth_ == 0 )
            {
                space();
            }
            openUnit( e, n, id );
        }
        if( e.isPre )
        {
            ++preDepth_;
        }
        if( e.isSection )
        {
            ++sectionDepth_;
        }
        stack_.push_back( e );
    }

    bool isRegionStart( const Tag& t, std::string_view n, std::string_view cls, std::string_view id ) const noexcept
    {
        switch( region_ )
        {
            case Region::Main:         return n == "main" || attrValue( html_, t.attrsBegin, t.end, "role" ) == "main";
            case Region::Article:      return n == "article";
            case Region::ContentClass: return n == "div" && ( carriesWord( cls, kContentWords ) || carriesWord( id, kContentWords ) );
            case Region::Body:         return false;
        }
        return false;
    }

    void openUnit( OpenElement& e, std::string_view n, std::string_view id )
    {
        if( const int level = headingLevelOf( n ); level > 0 )
        {
            // A heading that OPENS a section id (nothing printed since the section began) names that section
            // instead of starting a unit of its own.
            if( openSection_ >= 0 && !sawTextSinceSection_ && heads_[ std::size_t( openSection_ ) ].name == heads_[ std::size_t( openSection_ ) ].id )
            {
                e.headingSlot = openSection_;
                heads_[ std::size_t( openSection_ ) ].name.clear();
                titleStart_ = out_.size();
                return;
            }
            HtmlHeading h;
            h.startByte = std::uint32_t( out_.size() );
            h.line      = line_;
            h.level     = std::uint32_t( level );
            h.id        = std::string( id );
            heads_.push_back( std::move( h ) );
            e.headingSlot = int( heads_.size() - 1 );
            titleStart_   = out_.size();
            return;
        }
        if( n == "section" && !id.empty() )
        {
            HtmlHeading h;
            h.startByte   = std::uint32_t( out_.size() );
            h.sigEnd      = h.startByte;
            h.line        = line_;
            h.level       = std::uint32_t( std::min( sectionDepth_ + 1, 6 ) );
            h.isSectionId = true;
            h.id          = std::string( id );
            h.name        = h.id;
            heads_.push_back( std::move( h ) );
            e.isSection          = true;
            openSection_         = int( heads_.size() - 1 );
            sawTextSinceSection_ = false;
        }
    }

    void onEndTag( const Tag& t )
    {
        const std::string_view n = t.name();
        for( std::size_t k = stack_.size(); k > 0; --k )
        {
            if( stack_[ k - 1 ].name() != n )
            {
                continue;
            }
            while( stack_.size() >= k )   // close everything the author left open inside it, innermost first
            {
                closeElement( stack_.back() );
                stack_.pop_back();
            }
            break;
        }
        if( isEmitting() && tagClassOf( n ) != TagClass::Inline && preDepth_ == 0 )
        {
            space();
        }
    }

    void closeElement( const OpenElement& e )
    {
        if( e.headingSlot >= 0 )
        {
            closeHeading( heads_[ std::size_t( e.headingSlot ) ] );
        }
        if( e.isPre && preDepth_ > 0 )
        {
            --preDepth_;
        }
        if( e.isSection && sectionDepth_ > 0 )
        {
            --sectionDepth_;
            openSection_ = -1;   // a heading after a closed section names nothing but itself
        }
        if( e.isSkip && skipDepth_ > 0 )
        {
            --skipDepth_;
        }
        if( e.isRegion && regionDepth_ > 0 )
        {
            --regionDepth_;
        }
    }

    // The heading's name is the text printed between its tags, whitespace-collapsed and capped.
    void closeHeading( HtmlHeading& h )
    {
        constexpr std::size_t kMaxNameBytes = 160;
        h.sigEnd = std::uint32_t( out_.size() );
        std::string name;
        for( std::size_t k = std::min( titleStart_, out_.size() ); k < out_.size(); ++k )
        {
            const char c = out_[ k ];
            if( c == ' ' || c == '\n' || c == '\t' )
            {
                if( !name.empty() && name.back() != ' ' )
                {
                    name.push_back( ' ' );
                }
                continue;
            }
            name.push_back( c );
        }
        while( !name.empty() && name.back() == ' ' )
        {
            name.pop_back();
        }
        if( name.size() > kMaxNameBytes )
        {
            std::size_t cut = kMaxNameBytes;
            while( cut > 0 && ( static_cast<unsigned char>( name[ cut ] ) & 0xC0 ) == 0x80 )
            {
                --cut;   // never split a UTF-8 sequence
            }
            name.resize( cut );
        }
        if( name.empty() )
        {
            name = h.id;   // an icon-only heading: its anchor is the only name it has
        }
        h.name = std::move( name );
    }

    void finishOpenHeadings()
    {
        for( auto open = stack_.rbegin(); open != stack_.rend(); ++open )   // innermost first, as the end tags would
        {
            closeElement( *open );
        }
        stack_.clear();
    }

    std::string_view         html_;
    Region                   region_;
    std::string              out_;
    std::vector<HtmlHeading> heads_;
    std::vector<OpenElement> stack_;
    std::uint32_t            line_                = 1;
    int                      skipDepth_           = 0;
    int                      regionDepth_         = 0;
    int                      preDepth_            = 0;
    int                      sectionDepth_        = 0;
    int                      openSection_         = -1;
    bool                     sawTextSinceSection_ = true;
    std::size_t              titleStart_          = 0;
    std::uint32_t            titleBegin_          = 0;
    std::uint32_t            titleEnd_            = 0;
    bool                     isPastHead_          = false;   // a <body> tag was read: a later <title> (an svg's) is no page title
};

// Rule 3's second half, and the subtree spans: on a page with section ids, drop the h3-h6 boundaries that are not
// a section's own title; then give each unit the end of its subtree (the next unit at the same or a shallower
// level), which is the span ingest's Section symbols carry for markdown too.
inline void finishUnits( HtmlDoc& doc )
{
    const bool hasSectionIds = std::any_of( doc.headings.begin(), doc.headings.end(), []( const HtmlHeading& h ) noexcept { return h.isSectionId; } );
    if( hasSectionIds )
    {
        std::erase_if( doc.headings, []( const HtmlHeading& h ) noexcept { return !h.isSectionId && h.level >= 3; } );
    }
    for( std::size_t p = 0; p < doc.headings.size(); ++p )
    {
        HtmlHeading& h = doc.headings[ p ];
        h.endByte      = std::uint32_t( doc.text.size() );
        for( std::size_t q = p + 1; q < doc.headings.size(); ++q )
        {
            if( doc.headings[ q ].level <= h.level )
            {
                h.endByte = doc.headings[ q ].startByte;
                break;
            }
        }
        h.sigEnd = std::min( std::max( h.sigEnd, h.startByte ), h.endByte );
    }
}

}   // namespace htmldetail

// An HTML page as line-preserving body text plus its unit boundaries (rules 1-3 in the header comment).
inline HtmlDoc extractHtmlDoc( std::string_view html )
{
    const htmldetail::Region region = htmldetail::probeRegion( html );
    HtmlDoc                  doc    = htmldetail::Extractor( html, region ).run();
    const auto isBlank       = []( char c ) noexcept { return c == ' ' || c == '\n'; };
    const bool isEmptyRegion = region != htmldetail::Region::Body && std::all_of( doc.text.begin(), doc.text.begin() + doc.titleBegin, isBlank )
                            && std::all_of( doc.text.begin() + doc.titleEnd, doc.text.end(), isBlank );
    if( isEmptyRegion )
    {
        doc = htmldetail::Extractor( html, htmldetail::Region::Body ).run();   // a script-filled region: the body is all there is
    }
    htmldetail::finishUnits( doc );
    if( !doc.headings.empty() )
    {
        // A page with units names itself by its headings; its title would only ride, as a short preamble, into the first
        // unit and stretch its lines=. Blanked in place, so every offset and line stays where it was.
        std::replace_if( doc.text.begin() + doc.titleBegin, doc.text.begin() + doc.titleEnd, []( char c ) noexcept { return c != '\n'; }, ' ' );
    }
    return doc;
}

}   // namespace docparse
}   // namespace rw
