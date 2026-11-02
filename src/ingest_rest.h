#pragma once
#if !defined( RIPWIRE_INGEST_TU )
#error "ingest_rest.h is a SECTION of src/ingest.cpp's translation unit - include it only from ingest.cpp (see the ingest-family split note there)"
#endif

// ingest_rest.h — the reStructuredText section tier, the sibling of ingest_docs.h's extractMarkdown. A hand-written
// line scan, no grammar: the markdown block grammar read a `.. option::` as a paragraph, and a title in a 700-line options
// page as whichever setext underline it happened to accept. Gate: test/restdocscheck.sh. Credit: @muayyad-alsadi (#409).
//
// WHAT A UNIT IS. Every unit is a Section def on Lang::Markdown, so recall's tiling, --expand and the link index read it
// exactly as they read a markdown heading:
//   (1) the file node, built by the same helper extractMarkdown uses;
//   (2) a TITLE, over- or underlined in any punctuation. Its level is the first-seen order of its style, as docutils
//       has it; there is no fixed meaning to `=` or `-`. It runs to the next title of the same or a higher level;
//   (3) an OBJECT DIRECTIVE on the allowlist below, named by its target (`.. option:: --width=<n>` is `--width`). It runs
//       to the next unit at the same or a shallower indent, or the next title, so units tile: recall's own-prose span ends
//       at the next unit whichever it is, and prose after a body would otherwise belong to no unit;
//   (4) a LABEL, `.. _name:`, named `_name` (lowered, as Sphinx looks it up). `_` keeps a label from being read as a title
//       of the same words when a `:ref:` binds it in graph.h.
//   A label or a directive with no body names what follows it: `.. setting:: X` above a title Y covers that title's whole
//   section, so asking for X serves the prose. Above a title X it IS that title, one unit. With prose after it, it runs
//   like (3).
// WHAT IS NOT STRUCTURE. Anything in a literal block (`::`, or a directive on kLiteralDirectives), a comment, or a
//   substitution definition. A title is read at column 0 only: reST has no indented title.
// THE UNDERLINE RULE is docutils': shorter than its title and under 4 characters is ordinary text; shorter and 4 or more
//   is still a title. A multi-line paragraph's last line is not a title, which a blank-line test decides.
// BOUNDS. One pass over the lines with an explicit stack, so a span costs O(1) however deep the file nests and a hostile
//   file cannot recurse. Past kMaxRestDepth or kMaxRestUnits a file keeps the units it has, and says so through
//   ExtractShortfall: --skipped why="extract-partial", and its facts stay out of the cache.
// LINKS. `:doc:` is a path, written relative as a markdown link is; `/abs` is relative to the Sphinx root, which this file
//   cannot see, so it carries kRestDocRootMark and graph.h finds the nearest ancestor holding that path. `:ref:` carries
//   kRestLabelMark. A `:ref:` that binds no label drops: its ref name holds a `:`, which no symbol is called, so a dangling
//   label can never land on a function of that name.

namespace rw
{

namespace
{

namespace resttier
{

inline constexpr std::uint32_t kMaxRestDepth = 64;
inline constexpr std::size_t   kMaxRestUnits = 20000;
inline constexpr std::size_t   kMaxRestName  = 256;    // a longer "target" is a sentence, not a name
inline constexpr std::size_t   kMaxRoleBytes = 400;    // a role's closing backtick must be this near, on one paragraph
inline constexpr std::uint32_t kNoUnit       = 0xFFFFFFFFu;

// Sphinx object descriptions, by their directive name without a domain. An allowlist: any other directive is not a unit,
// and its body is still scanned, so a `.. note::` holding an option keeps the option.
inline constexpr std::string_view kUnitDirectives[] = {
    "attribute", "class", "classmethod", "cmdoption", "confval", "data", "decorator", "django-admin", "django-admin-option",
    "envvar", "exception", "fieldlookup", "function", "macro", "member", "method", "option", "setting", "staticmethod",
    "templatefilter", "templatetag", "type", "var" };

static_assert( std::is_sorted( std::begin( kUnitDirectives ), std::end( kUnitDirectives ), rw::sortutil::svLess ), "kUnitDirectives must stay byte-sorted" );

// A directive whose body is not reST.
inline constexpr std::string_view kLiteralDirectives[] = {
    "code", "code-block", "csv-table", "doctest", "graphviz", "literalinclude", "math", "parsed-literal", "productionlist",
    "raw", "sourcecode", "testcleanup", "testcode", "testoutput", "testsetup" };

static_assert( std::is_sorted( std::begin( kLiteralDirectives ), std::end( kLiteralDirectives ), rw::sortutil::svLess ), "kLiteralDirectives must stay byte-sorted" );

// A directive that says nothing about what follows it, so a label above it still names the next unit.
inline constexpr std::string_view kPassThroughDirectives[] = { "currentmodule", "default-role", "highlight", "index", "module", "program" };

static_assert( std::is_sorted( std::begin( kPassThroughDirectives ), std::end( kPassThroughDirectives ), rw::sortutil::svLess ), "kPassThroughDirectives must stay byte-sorted" );

inline bool inTable( std::span<const std::string_view> table, std::string_view name ) noexcept
{
    return std::binary_search( table.begin(), table.end(), name, rw::sortutil::svLess );
}

struct RestLine
{
    std::uint32_t start = 0;
    std::uint32_t end   = 0;   // excludes the newline and a CR before it
    std::uint32_t next  = 0;   // the next line's start
};

inline std::vector<RestLine> splitRestLines( std::string_view src )
{
    std::vector<RestLine> lines;
    for( std::size_t i = 0; i < src.size(); )
    {
        const std::size_t nl   = src.find( '\n', i );
        const std::size_t stop = nl == std::string_view::npos ? src.size() : nl;
        std::size_t       end  = stop;
        if( end > i && src[ end - 1 ] == '\r' )
        {
            --end;
        }
        const std::size_t next = nl == std::string_view::npos ? src.size() : nl + 1;
        lines.push_back( { std::uint32_t( i ), std::uint32_t( end ), std::uint32_t( next ) } );
        i = next;
    }
    return lines;
}

inline bool isBlankText( std::string_view s ) noexcept
{
    return s.find_first_not_of( " \t" ) == std::string_view::npos;
}

inline std::uint32_t indentOf( std::string_view s ) noexcept
{
    std::uint32_t width = 0;
    for( const char c : s )
    {
        if( c == ' ' ) { ++width; }
        else if( c == '\t' ) { width = ( width / 8 + 1 ) * 8; }
        else { break; }
    }
    return width;
}

inline std::string_view trimText( std::string_view s ) noexcept
{
    const std::size_t a = s.find_first_not_of( " \t" );
    if( a == std::string_view::npos )
    {
        return {};
    }
    return s.substr( a, s.find_last_not_of( " \t" ) - a + 1 );
}

inline bool isAdornmentChar( char c ) noexcept
{
    return ( c >= '!' && c <= '/' ) || ( c >= ':' && c <= '@' ) || ( c >= '[' && c <= '`' ) || ( c >= '{' && c <= '~' );
}

// A whole line of one punctuation character, with trailing blanks allowed.
inline bool isAdornmentLine( std::string_view s ) noexcept
{
    const std::string_view t = s.substr( 0, s.find_last_not_of( " \t" ) + 1 );
    return !t.empty() && isAdornmentChar( t[ 0 ] ) && t.find_first_not_of( t[ 0 ] ) == std::string_view::npos;
}

inline std::size_t adornmentLength( std::string_view s ) noexcept
{
    return s.find_last_not_of( " \t" ) + 1;
}

// Width in code points, not bytes: an accented title must not read as longer than its underline.
inline std::size_t textWidth( std::string_view s ) noexcept
{
    std::size_t n = 0;
    for( const char c : s )
    {
        n += ( static_cast<unsigned char>( c ) & 0xC0u ) != 0x80u ? 1u : 0u;
    }
    return n;
}

// A line another block type claims first: a bullet, or a field. An underline below one does not make a title.
inline bool startsOtherBlock( std::string_view s ) noexcept
{
    if( s.size() >= 2 && ( s[ 0 ] == '-' || s[ 0 ] == '*' || s[ 0 ] == '+' ) && s[ 1 ] == ' ' )
    {
        return true;
    }
    if( s.starts_with( ".." ) )
    {
        return true;
    }
    // `:field: value` is a field; `:mod:`os` --- Files` is a title that opens on a role.
    const std::size_t colon = s.size() > 2 && s[ 0 ] == ':' ? s.find( ':', 1 ) : std::string_view::npos;
    return colon != std::string_view::npos && ( colon + 1 == s.size() || s[ colon + 1 ] == ' ' );
}

inline bool underlineFits( std::string_view title, std::string_view underline ) noexcept
{
    const std::size_t len = adornmentLength( underline );
    return len >= 4 || len >= textWidth( trimText( title ) );
}

// Title text with its inline markup taken off: ``NAME`` and :role:`NAME` both read NAME. Any other byte stays.
inline std::string cleanTitleText( std::string_view raw )
{
    std::string out;
    const std::string_view t = trimText( raw );
    out.reserve( t.size() );
    for( std::size_t i = 0; i < t.size(); ++i )
    {
        if( t[ i ] == '`' )
        {
            continue;
        }
        if( t[ i ] == ':' && ( i == 0 || t[ i - 1 ] == ' ' ) )
        {
            const std::size_t close = t.find( ":`", i + 1 );
            if( close != std::string_view::npos && t.substr( i + 1, close - i - 1 ).find( ' ' ) == std::string_view::npos )
            {
                i = close + 1;   // on the '`'; the loop steps past it, and past Sphinx's `!` or `~` display marks
                if( i + 1 < t.size() && ( t[ i + 1 ] == '!' || t[ i + 1 ] == '~' ) )
                {
                    ++i;
                }
                continue;
            }
        }
        out.push_back( t[ i ] );
    }
    return out;
}

// `-h, --help` names --help: a long spelling is the one a reader asks for. `--width=<n>` and `--width <n>` name --width.
inline std::string_view optionTarget( std::string_view args ) noexcept
{
    std::string_view first;
    for( std::size_t i = 0; i < args.size(); )
    {
        const std::size_t stop  = std::min( args.find_first_of( " ,", i ), args.size() );
        std::string_view  token = args.substr( i, stop - i );
        i = stop + 1;
        if( token.empty() || !( token.front() == '-' || token.front() == '/' ) )
        {
            continue;
        }
        token = token.substr( 0, std::min( token.find_first_of( "=[<" ), token.size() ) );
        if( first.empty() )
        {
            first = token;
        }
        if( token.starts_with( "--" ) )
        {
            return token;
        }
    }
    return first.empty() ? args.substr( 0, std::min( args.find_first_of( " ,=[<" ), args.size() ) ) : first;
}

// `foo.bar(x)` names foo.bar; `int f(int a)` names f; `x = 1` and `x: int` name x; `class Foo` names Foo.
inline std::string_view signatureTarget( std::string_view args ) noexcept
{
    std::string_view head = trimText( args.substr( 0, std::min( args.find_first_of( "(=" ), args.size() ) ) );
    if( const std::size_t colon = head.find( ": " ); colon != std::string_view::npos )
    {
        head = trimText( head.substr( 0, colon ) );
    }
    const std::size_t space = head.find_last_of( " \t" );
    std::string_view  name  = space == std::string_view::npos ? head : head.substr( space + 1 );
    while( !name.empty() && ( name.front() == '*' || name.front() == '&' ) )
    {
        name.remove_prefix( 1 );
    }
    return name;
}

inline std::string_view directiveTarget( std::string_view directive, std::string_view args ) noexcept
{
    if( directive == "option" || directive == "cmdoption" || directive == "django-admin-option" )
    {
        return optionTarget( args );
    }
    if( directive == "setting" || directive == "confval" || directive == "envvar" || directive == "django-admin"
        || directive == "templatetag" || directive == "templatefilter" || directive == "fieldlookup" )
    {
        return args.substr( 0, std::min( args.find_first_of( " \t" ), args.size() ) );
    }
    return signatureTarget( args );
}

// One explicit-markup line, split. kind Other is a comment, a footnote or a substitution.
enum class ExplicitKind : std::uint8_t { Comment, Label, Directive, Other };

struct ExplicitLine
{
    ExplicitKind     kind = ExplicitKind::Comment;
    std::string_view name;   // the label, or the directive with its domain taken off
    std::string_view args;
};

inline ExplicitLine parseExplicit( std::string_view text ) noexcept
{
    std::string_view body = text.substr( 2 );   // past ".."
    if( !body.empty() && body.front() != ' ' && body.front() != '\t' )
    {
        return {};   // `..word` is a paragraph to docutils; the caller only reaches here on ".. " or a bare ".."
    }
    body = trimText( body );
    if( body.empty() )
    {
        return {};
    }
    if( body.front() == '_' )
    {
        if( body.size() > 2 && body.back() == ':' )
        {
            std::string_view label = body.substr( 1, body.size() - 2 );
            if( label.size() > 2 && label.front() == '`' && label.back() == '`' )
            {
                label = label.substr( 1, label.size() - 2 );
            }
            if( !label.empty() )
            {
                return { ExplicitKind::Label, label, {} };
            }
        }
        return { ExplicitKind::Other, {}, {} };   // `.. _name: https://…` points elsewhere and names nothing here
    }
    if( body.front() == '|' || body.front() == '[' )
    {
        return { ExplicitKind::Other, {}, {} };
    }
    const std::size_t marker = body.find( "::" );
    if( marker == std::string_view::npos || marker == 0 || body.substr( 0, marker ).find_first_of( " \t" ) != std::string_view::npos )
    {
        return {};
    }
    std::string_view directive = body.substr( 0, marker );
    if( const std::size_t domain = directive.find( ':' ); domain != std::string_view::npos )
    {
        directive = directive.substr( domain + 1 );
    }
    return { ExplicitKind::Directive, directive, trimText( body.substr( marker + 2 ) ) };
}

struct RestUnit
{
    std::uint32_t startByte = 0;
    std::uint32_t sigEnd    = 0;
    std::uint32_t nameByte  = 0;
    std::uint32_t endByte   = 0;
    std::uint32_t line      = 0;
    std::uint32_t parent    = kNoUnit;
    std::uint32_t cover     = kNoUnit;   // the later unit this one names: it ends where that one ends
    std::string   name;
};

struct RestOpen
{
    std::uint32_t unit      = 0;
    std::uint32_t level     = 0;      // title level, meaningful when !directive
    std::uint32_t indent    = 0;      // directive indent, meaningful when directive
    bool          directive = false;
};

// The unit stack and the units a label or a body-less directive left waiting for what follows.
class RestUnitBuilder
{
public:
    RestUnitBuilder( std::uint32_t srcSize, ExtractShortfall& shortfall ) noexcept : srcSize_( srcSize ), shortfall_( shortfall ) {}

    void addTitle( RestUnit unit, std::uint32_t level )
    {
        // `.. setting:: X` straight above a title X: one thing with one name. The title keeps it and takes the line.
        while( !waiting_.empty() && waiting_.back().name == unit.name )
        {
            unit.startByte = waiting_.back().startByte;
            waiting_.pop_back();
        }
        closeTitlesTo( level, firstWaitingStart( unit.startByte ) );
        if( !admit() )
        {
            return;
        }
        open_.push_back( { adopt( std::move( unit ) ), level, 0, false } );
    }

    void addDirective( RestUnit unit, std::uint32_t indent )
    {
        closeDirectivesTo( indent, firstWaitingStart( unit.startByte ) );
        if( !admit() )
        {
            return;
        }
        open_.push_back( { adopt( std::move( unit ) ), 0, indent, true } );
    }

    // A label or a body-less directive: it waits, since what comes next decides what it covers.
    void addWaiting( RestUnit unit, std::uint32_t indent )
    {
        if( units_.size() + waiting_.size() >= kMaxRestUnits )
        {
            noteCapped();
            return;
        }
        waitingIndent_ = waiting_.empty() ? indent : waitingIndent_;
        waiting_.push_back( std::move( unit ) );
    }

    // Prose came next: the last waiter becomes an ordinary directive unit, and any before it name that one.
    void flushWaiting()
    {
        if( waiting_.empty() )
        {
            return;
        }
        RestUnit last = std::move( waiting_.back() );
        waiting_.pop_back();
        addDirective( std::move( last ), waitingIndent_ );
    }

    [[nodiscard]] std::vector<RestUnit> finish()
    {
        flushWaiting();
        for( const RestOpen& o : open_ )
        {
            units_[ o.unit ].endByte = srcSize_;
        }
        open_.clear();
        for( std::size_t i = units_.size(); i > 0; --i )   // a cover always sits later, so this order settles a chain
        {
            RestUnit& u = units_[ i - 1 ];
            if( u.cover != kNoUnit )
            {
                u.endByte = units_[ u.cover ].endByte;
            }
        }
        return std::move( units_ );
    }

private:
    [[nodiscard]] std::uint32_t firstWaitingStart( std::uint32_t otherwise ) const noexcept
    {
        return waiting_.empty() ? otherwise : waiting_.front().startByte;
    }

    void closeTitlesTo( std::uint32_t level, std::uint32_t at ) noexcept
    {
        while( !open_.empty() && ( open_.back().directive || open_.back().level >= level ) )
        {
            units_[ open_.back().unit ].endByte = at;
            open_.pop_back();
        }
    }

    void closeDirectivesTo( std::uint32_t indent, std::uint32_t at ) noexcept
    {
        while( !open_.empty() && open_.back().directive && open_.back().indent >= indent )
        {
            units_[ open_.back().unit ].endByte = at;
            open_.pop_back();
        }
    }

    [[nodiscard]] bool admit()
    {
        if( open_.size() < kMaxRestDepth && units_.size() + waiting_.size() < kMaxRestUnits )
        {
            return true;
        }
        noteCapped();
        waiting_.clear();
        return false;
    }

    void noteCapped() noexcept
    {
        DISCLOSE( shortfall_, ExtractShortfall::DisclosureWhy::RestUnitsCapped,
                  "ingest: a reST file passed the unit or nesting bound; later units stay in the whole-file node (--skipped why=extract-partial)" );
    }

    // Waiters take the new unit's parent and end where it ends. They precede it, so they keep byte order.
    std::uint32_t adopt( RestUnit unit )
    {
        const std::uint32_t parent = open_.empty() ? kNoUnit : open_.back().unit;
        const std::uint32_t self   = std::uint32_t( units_.size() + waiting_.size() );
        for( RestUnit& w : waiting_ )
        {
            w.parent = parent;
            w.cover  = self;
            units_.push_back( std::move( w ) );
        }
        waiting_.clear();
        unit.parent = parent;
        units_.push_back( std::move( unit ) );
        return self;
    }

    std::vector<RestUnit> units_;
    std::vector<RestOpen> open_;
    std::vector<RestUnit> waiting_;
    std::uint32_t         waitingIndent_ = 0;
    std::uint32_t         srcSize_;
    ExtractShortfall&     shortfall_;
};

// The level of a title style, first-seen: at most 2 × the punctuation characters, so a small linear table.
class TitleStyles
{
public:
    std::uint32_t levelOf( char c, bool overlined )
    {
        const std::uint16_t key = std::uint16_t( ( std::uint16_t( static_cast<unsigned char>( c ) ) << 1 ) | ( overlined ? 1u : 0u ) );
        const auto          hit = std::find( seen_.begin(), seen_.end(), key );
        if( hit != seen_.end() )
        {
            return std::uint32_t( hit - seen_.begin() ) + 1u;
        }
        seen_.push_back( key );
        return std::uint32_t( seen_.size() );
    }

private:
    std::vector<std::uint16_t> seen_;
};

// One role's text: `label`, or `text <label>` whose target is the angle-bracketed part.
inline std::string_view roleTarget( std::string_view inner ) noexcept
{
    inner = trimText( inner );
    if( inner.size() > 2 && inner.back() == '>' )
    {
        const std::size_t open = inner.rfind( '<' );
        if( open != std::string_view::npos )
        {
            return trimText( inner.substr( open + 1, inner.size() - open - 2 ) );
        }
    }
    return inner;
}

inline void emitRestLabelRef( std::uint32_t fileId, std::uint32_t at, std::string_view target, std::vector<RawRef>& refs )
{
    std::string label;
    label.reserve( target.size() );
    bool pendingSpace = false;
    for( const char c : target )
    {
        const bool space = c == ' ' || c == '\t' || c == '\n' || c == '\r';
        pendingSpace = pendingSpace || space;
        if( space )
        {
            continue;
        }
        if( pendingSpace && !label.empty() )
        {
            label.push_back( ' ' );
        }
        pendingSpace = false;
        label.push_back( c >= 'A' && c <= 'Z' ? char( c - 'A' + 'a' ) : c );
    }
    if( label.empty() )
    {
        return;
    }
    RawRef r;
    r.fileId = fileId; r.startByte = at; r.lang = Lang::Markdown; r.isInherit = false;
    r.name = ":ref:" + label;
    r.memberPath.assign( kRestLabelMark );
    r.memberPath.append( label );
    refs.push_back( std::move( r ) );
}

inline void emitRestDocRef( std::uint32_t fileId, std::uint32_t at, std::string_view target, std::string_view ownExt, std::vector<RawRef>& refs )
{
    if( target.empty() || target.find_first_of( " \t\r\n" ) != std::string_view::npos )
    {
        return;
    }
    const std::size_t slash = target.find_last_of( '/' );
    const std::string_view stem = slash == std::string_view::npos ? target : target.substr( slash + 1 );
    if( stem.empty() )
    {
        return;
    }
    RawRef r;
    r.fileId = fileId; r.startByte = at; r.lang = Lang::Markdown; r.isInherit = false;
    r.name.assign( stem );
    if( target.front() == '/' )
    {
        r.memberPath.assign( kRestDocRootMark );
        target.remove_prefix( 1 );
    }
    r.memberPath.append( target );
    r.memberPath.append( ownExt );
    refs.push_back( std::move( r ) );
}

// One line's roles and mentions. A :ref: or :doc: may wrap to the next lines of its paragraph, so its closing backtick
// is looked for in src; a mention is one line, as in markdown. Returns where the scan of later lines must resume, so a
// wrapped role's tail is not read again as text.
inline std::uint32_t scanRestInline( std::string_view src, const RestLine& line, std::uint32_t resumeAt, std::uint32_t fileId, std::string_view ownExt,
                                     std::vector<RawRef>& refs )
{
    std::uint32_t pos = std::max( line.start, resumeAt );
    while( pos < line.end )
    {
        const std::string_view text = src.substr( pos, line.end - pos );
        const std::size_t      role = text.find( ":`" );
        if( role == std::string_view::npos || role < 4 || ( text.substr( role - 4, 4 ) != ":ref" && text.substr( role - 4, 4 ) != ":doc" ) )
        {
            const std::size_t stop = role == std::string_view::npos ? text.size() : role + 2;
            if( role == std::string_view::npos )
            {
                scanBacktickMentions( text, pos, fileId, refs );
                return line.next;
            }
            // Another role. Its backticks are a mention to the shared scan, so hand it the text through the closing one.
            const std::size_t close = text.find( '`', stop );
            const std::size_t end   = close == std::string_view::npos ? text.size() : close + 1;
            scanBacktickMentions( text.substr( 0, end ), pos, fileId, refs );
            pos += std::uint32_t( end );
            continue;
        }
        scanBacktickMentions( text.substr( 0, role - 4 ), pos, fileId, refs );
        const std::size_t innerStart = pos + role + 2;
        const std::size_t limit      = std::min( src.size(), innerStart + kMaxRoleBytes );
        const std::size_t close      = src.substr( 0, limit ).find( '`', innerStart );
        const std::size_t para       = src.substr( 0, limit ).find( "\n\n", innerStart );
        if( close == std::string_view::npos || ( para != std::string_view::npos && para < close ) )
        {
            pos += std::uint32_t( role + 2 );   // never closed in its paragraph: not a role
            continue;
        }
        const std::string_view target = roleTarget( src.substr( innerStart, close - innerStart ) );
        if( text[ role - 1 ] == 'f' )
        {
            emitRestLabelRef( fileId, pos + std::uint32_t( role ) - 4u, target, refs );
        }
        else
        {
            emitRestDocRef( fileId, pos + std::uint32_t( role ) - 4u, target, ownExt, refs );
        }
        pos = std::uint32_t( close + 1 );
    }
    return pos;
}

inline std::string lowerText( std::string_view s )
{
    std::string out( s );
    for( char& c : out )
    {
        c = c >= 'A' && c <= 'Z' ? char( c - 'A' + 'a' ) : c;
    }
    return out;
}

inline bool nextLineHasBody( const std::vector<RestLine>& lines, std::size_t i, std::string_view src, std::uint32_t indent ) noexcept
{
    for( std::size_t k = i + 1; k < lines.size(); ++k )
    {
        const std::string_view t = src.substr( lines[ k ].start, lines[ k ].end - lines[ k ].start );
        if( !isBlankText( t ) )
        {
            return indentOf( t ) > indent;
        }
    }
    return false;
}

// Whether the line at i opens a title, and how. Lines are read only at column 0, except an overlined title's own text.
struct TitleHit
{
    bool        hit       = false;
    bool        overlined = false;
    std::size_t textLine  = 0;
    std::size_t lastLine  = 0;
    char        style     = 0;
};

inline TitleHit titleAt( const std::vector<RestLine>& lines, std::size_t i, std::string_view src, bool afterBlank ) noexcept
{
    const auto textOf = [ & ]( std::size_t k ) { return src.substr( lines[ k ].start, lines[ k ].end - lines[ k ].start ); };
    const std::string_view here = textOf( i );
    if( !afterBlank || here.empty() || here[ 0 ] == ' ' || here[ 0 ] == '\t' )
    {
        return {};
    }
    if( isAdornmentLine( here ) )
    {
        if( i + 2 >= lines.size() )
        {
            return {};
        }
        const std::string_view text  = textOf( i + 1 );
        const std::string_view under = textOf( i + 2 );
        const bool ok = !isBlankText( text ) && isAdornmentLine( under ) && under[ 0 ] == here[ 0 ]
            && adornmentLength( under ) == adornmentLength( here ) && !isAdornmentLine( trimText( text ) ) && underlineFits( text, under );
        return ok ? TitleHit{ true, true, i + 1, i + 2, here[ 0 ] } : TitleHit{};
    }
    if( i + 1 >= lines.size() || startsOtherBlock( here ) )
    {
        return {};
    }
    const std::string_view under = textOf( i + 1 );
    if( under.empty() || under[ 0 ] == ' ' || under[ 0 ] == '\t' || !isAdornmentLine( under ) || !underlineFits( here, under ) )
    {
        return {};
    }
    return { true, false, i, i + 1, under[ 0 ] };
}

// A directive line's unit, when it makes one.
inline void addDirectiveUnit( RestUnitBuilder& build, const ExplicitLine& ex, std::string_view src, const RestLine& line, std::size_t lineIndex, std::uint32_t indent,
                              bool hasBody )
{
    const std::string_view target = directiveTarget( ex.name, ex.args );
    if( target.empty() || target.size() > kMaxRestName )
    {
        return;
    }
    RestUnit unit;
    unit.startByte = line.start;
    unit.sigEnd    = line.next;
    unit.nameByte  = std::uint32_t( target.data() - src.data() );
    unit.line      = std::uint32_t( lineIndex ) + 1u;
    unit.name.assign( target );
    if( hasBody )
    {
        build.addDirective( std::move( unit ), indent );
    }
    else
    {
        build.addWaiting( std::move( unit ), indent );
    }
}

} // namespace resttier

void extractRest( std::uint32_t fileId, std::string_view src, std::string_view stem, std::string_view ownExt,
                  std::vector<RawDef>& defs, std::vector<RawRef>& refs, ExtractShortfall& shortfall )
{
    using namespace resttier;

    pushDocFileNode( fileId, src, stem, defs );

    const std::vector<RestLine> lines = splitRestLines( src );
    RestUnitBuilder             build( std::uint32_t( src.size() ), shortfall );
    TitleStyles                 styles;

    constexpr std::uint32_t kNotActive = 0xFFFFFFFFu;
    std::uint32_t opaqueIndent  = kNotActive;   // inside a literal block or comment: skip while deeper than this
    std::uint32_t literalIndent = kNotActive;   // the paragraph above ended in `::`: a deeper block is literal
    std::uint32_t resumeAt      = 0;            // past a role that wrapped onto earlier-scanned lines
    bool          afterBlank    = true;

    for( std::size_t i = 0; i < lines.size(); ++i )
    {
        const RestLine&        line = lines[ i ];
        const std::string_view text = src.substr( line.start, line.end - line.start );
        if( isBlankText( text ) )
        {
            afterBlank = true;
            continue;
        }
        const std::uint32_t indent = indentOf( text );
        if( opaqueIndent != kNotActive )
        {
            if( indent > opaqueIndent )
            {
                continue;
            }
            opaqueIndent = kNotActive;
        }
        if( literalIndent != kNotActive )
        {
            const std::uint32_t para = literalIndent;
            literalIndent = kNotActive;
            if( indent > para )
            {
                opaqueIndent = para;
                continue;
            }
        }

        const std::string_view body = text.substr( text.find_first_not_of( " \t" ) );
        if( body == ".." || body.starts_with( ".. " ) || body.starts_with( "..\t" ) )
        {
            const ExplicitLine ex      = parseExplicit( body );
            const bool         hasBody = nextLineHasBody( lines, i, src, indent );
            afterBlank = !hasBody;   // a title may sit straight below a label
            if( ex.kind == ExplicitKind::Comment || ex.kind == ExplicitKind::Other )
            {
                opaqueIndent = indent;
                continue;
            }
            if( ex.kind == ExplicitKind::Label )
            {
                RestUnit unit;
                unit.startByte = line.start;
                unit.sigEnd    = line.next;
                unit.nameByte  = std::uint32_t( ex.name.data() - src.data() );
                unit.line      = std::uint32_t( i ) + 1u;
                unit.name      = "_" + lowerText( ex.name );
                build.addWaiting( std::move( unit ), indent );
                continue;
            }
            if( inTable( kUnitDirectives, ex.name ) )
            {
                addDirectiveUnit( build, ex, src, line, i, indent, hasBody );
                continue;
            }
            if( inTable( kPassThroughDirectives, ex.name ) )
            {
                opaqueIndent = indent;
                continue;
            }
            build.flushWaiting();
            if( inTable( kLiteralDirectives, ex.name ) )
            {
                opaqueIndent = indent;
                continue;
            }
            resumeAt = scanRestInline( src, line, resumeAt, fileId, ownExt, refs );
            continue;
        }

        const TitleHit title = titleAt( lines, i, src, afterBlank );
        if( title.hit )
        {
            const RestLine&        textLine = lines[ title.textLine ];
            const std::string_view raw      = src.substr( textLine.start, textLine.end - textLine.start );
            std::string            name     = cleanTitleText( raw );
            afterBlank = true;   // a title may sit straight on the next one
            if( !name.empty() )
            {
                RestUnit unit;
                unit.startByte = line.start;
                unit.sigEnd    = lines[ title.lastLine ].next;
                unit.nameByte  = std::uint32_t( trimText( raw ).data() - src.data() );
                unit.line      = std::uint32_t( title.textLine ) + 1u;
                unit.name      = std::move( name );
                build.addTitle( std::move( unit ), styles.levelOf( title.style, title.overlined ) );
            }
            resumeAt = scanRestInline( src, textLine, resumeAt, fileId, ownExt, refs );
            i        = title.lastLine;
            continue;
        }

        if( isAdornmentLine( text ) )   // a transition, or a table rule
        {
            afterBlank = false;
            continue;
        }
        build.flushWaiting();
        afterBlank = false;
        resumeAt   = scanRestInline( src, line, resumeAt, fileId, ownExt, refs );
        if( text.ends_with( "::" ) )
        {
            literalIndent = indent;
        }
    }

    const std::vector<RestUnit> units = build.finish();
    defs.reserve( defs.size() + units.size() );
    for( const RestUnit& u : units )
    {
        RawDef d;
        d.fileId    = fileId;
        d.line      = u.line;
        d.startByte = u.startByte;
        d.endByte   = u.endByte;
        d.nameByte  = u.nameByte;
        d.bodyByte  = u.sigEnd;
        d.kind      = SymKind::Section;
        d.lang      = Lang::Markdown;
        if( u.parent != kNoUnit )
        {
            d.scope = units[ u.parent ].name;
        }
        d.name = u.name;
        defs.push_back( std::move( d ) );
    }
}

}   // namespace — ingest_rest.h section of ingest.cpp

}   // namespace rw
