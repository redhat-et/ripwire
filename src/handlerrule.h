#pragma once
// handlerrule.h — ON-NAME-HANDLERS-V2: a posted message CLASS names its handler methods (the Python layer of the name-key hop
// family, backhops.h NameKeyHops).
//
// THE GAP. A message framework dispatches by a name the message's class carries: textual's `Message.__init_subclass__` writes
// `cls.handler_name = f"on_{name}"` (name = camel_to_snake of the owner and class names), and the pump looks the handler up
// with `cls.__dict__.get( method_name )` where method_name is a PARAMETER. Nothing at the lookup is provable (every on_* def
// fits it), so lane string-keyed declined it. The class is known at the POST SITE: `self.post_message( Button.Pressed( self ) )`
// names Button.Pressed, whose handler name is on_button_pressed.
//
// THE CONTRACT. HandlerRules reads the RULE from the repo's own source, never from a framework list:
//   rule       a Python `__init_subclass__` of class B with ONE write `cls.A = f"P{v}"` at the top level of the function (not under
//              an if/else/for/while/try/match: a conditional write is not the rule for every class), literal identifier prefix P,
//              one hole v, where EVERY assignment of the local v calls a converter whose body is the `[a-z][A-Z]` regex plus
//              `.lower()` (camel_to_snake: an underscore between a lower and an upper letter, then all lower), on
//              `cls.__qualname__` cut to its last two parts (`[-2:]`: owner class + class) or on `cls.__name__` alone; a
//              `{namespace}_` branch makes a `namespace="x"` class keyword the owner part. Any other shape: no rule, no hop (a
//              floor). A class body that writes A is overwritten by the rule (it runs after the body), so the rule decides.
//   nearest    a class's rule is the one of its NEAREST rule base (the most derived: a base whose own ancestry holds the others),
//              none when two unrelated bases both carry one; a class below an intermediate class whose `__init_subclass__` also
//              writes cls.A is never named (the intermediate decides at run time, which this does not read). A base written by
//              name that several classes carry binds only through the deriving file's own import (the same-file class, or the
//              file the import resolves to): a same-named class of another module is no base.
//   readers    per rule, the functions outside test paths that read A; their classes hold that rule's POSTERS (every method name
//              they define).
//   post site  a call to a poster whose FIRST argument is a construction `X( … )`, `self.X( … )`, `Owner.X( … )` or
//              `module.X( … )` of a subclass of B (written bases, valuerefindex.h ClassFamilies). A variable argument,
//              a factory (`X.from_event( … )`) or an unresolved class: no hop.
//   targets    the methods (a definition inside a class) named by the rule's name for that class: a hedge — which of them
//              runs depends on the receiving object's class, which the index does not decide.
// The hop is never a call edge: consumers print it via="name-key" with its width (cands=), never in reaches=/hops=.

#include "darkflags.h"          // readWhole — the rule and the post site are read from the file text
#include "filter.h"             // isTestPath — a test's reader does not make posters
#include "model.h"
#include "resolve.h"            // trimWs
#include "infra/namesplit.h"   // isIdentChar
#include "infra/sortutil.h"    // svLess — the explicit byte order for string searches (portablebuildcheck #6)
#include "valuerefindex.h"      // ClassFamilies — owner class and written-base family

#include <algorithm>
#include <cctype>
#include <cstddef>
#include <cstdint>
#include <optional>
#include <ranges>
#include <span>
#include <string>
#include <string_view>
#include <vector>

namespace rw
{

struct HandlerReader
{
    NodeId        fn   = kNoNode;   // the function reading the attribute
    std::uint32_t line = 0;         // the line of its first read
};

struct HandlerRule
{
    NodeId        base   = kNoNode;   // the class whose __init_subclass__ writes the attribute
    NodeId        writer = kNoNode;   // that __init_subclass__
    std::uint32_t fileId = 0;         // where the rule's write is (p=)
    std::uint32_t line   = 0;
    std::string   attr;               // the class attribute written (handler_name)
    std::string   prefix;             // the template's literal prefix (on_)
    bool          qualified = false;  // __qualname__[-2:]: owner class + class; else the class name alone
    bool          nsKeyword = false;  // a namespace= class keyword replaces the owner part
    std::vector<HandlerReader>    readers;   // the functions outside tests that read attr (symbol order)
    std::vector<std::string_view> posters;   // the method names of the readers' classes (svLess order): the calls that post
};

// One line of a function body: its text, indentation and 1-based file line.
struct BodyLine
{
    std::string_view text;
    std::uint32_t    indent = 0;
    std::uint32_t    no     = 0;
};

struct HandlerPostSite
{
    std::uint32_t            ref = 0;     // the poster call reference
    std::vector<std::string> names;       // the handler names its message class(es) carry, sorted, unique
    std::vector<NodeId>      classes;     // the message class definitions the construction may mean
};

// camel_to_snake as the `[a-z][A-Z]` rule states it: an underscore between each non-overlapping lower-upper pair, then lower.
inline std::string snakeOfCamel( std::string_view s )
{
    std::string out;
    out.reserve( s.size() + 4 );
    for( std::size_t i = 0; i < s.size(); ++i )
    {
        const unsigned char c = static_cast<unsigned char>( s[i] );
        out.push_back( char( std::tolower( c ) ) );
        if( std::islower( c ) && i + 1 < s.size() && std::isupper( static_cast<unsigned char>( s[ i + 1 ] ) ) )
        {
            out.push_back( '_' );
            out.push_back( char( std::tolower( static_cast<unsigned char>( s[ i + 1 ] ) ) ) );
            ++i;
        }
    }
    return out;
}

// Two reference-ordered site lists merged in reference order (NameKeyHops: template lookups beside post sites).
inline std::vector<std::uint32_t> mergedSiteLists( std::vector<std::uint32_t> sites, const std::vector<std::uint32_t>& more )
{
    const std::size_t mid = sites.size();
    sites.insert( sites.end(), more.begin(), more.end() );
    std::ranges::inplace_merge( sites, sites.begin() + std::ptrdiff_t( mid ) );
    return sites;
}

class HandlerRules
{
public:
    // The rule is a Python construct: the Python value-ref family is the one language it reads.
    static bool isPython( Lang l ) noexcept { return valueRefFamily( l ) == ValueRefFamily::Py; }

    HandlerRules( const IngestResult& ing, const ValueRefIndex& values ) : m_ing( ing ), m_values( values ), m_classes( ing ) {}

    // Built on first use; a tree with no Python __init_subclass__ write pays one reference scan.
    bool any() const
    {
        build();
        return !m_sites.empty();
    }
    const std::vector<HandlerPostSite>& sites() const { build(); return m_sites; }
    const ClassFamilies&                classes() const noexcept { return m_classes; }
    // The post site at reference `ref`, or null.
    const HandlerPostSite* siteAt( std::uint32_t ref ) const
    {
        build();
        const auto it = m_siteOfRef.find( ref );
        return it == m_siteOfRef.end() ? nullptr : &m_sites[ it->second ];
    }
    // The post sites whose message names handler `d` (a method), in reference order.
    std::vector<std::uint32_t> sitesNaming( NodeId d ) const
    {
        std::vector<std::uint32_t> out;
        if( !any() || d >= m_inClass.size() || m_inClass[d] == 0 )   // a Python function definition inside a class
        {
            return out;
        }
        for( const HandlerPostSite& s : m_sites )
        {
            if( m_ing.references[ s.ref ].fromSymbol != d && std::ranges::binary_search( s.names, std::string_view( m_ing.symbols[d].name ), sortutil::svLess ) )
            {
                out.push_back( s.ref );
            }
        }
        return out;
    }
    // The post sites made in `u`, in reference order.
    std::vector<std::uint32_t> sitesIn( NodeId u ) const
    {
        std::vector<std::uint32_t> out;
        if( any() )
        {
            for( const HandlerPostSite& s : m_sites )
            {
                if( m_ing.references[ s.ref ].fromSymbol == u )
                {
                    out.push_back( s.ref );
                }
            }
        }
        return out;
    }
    // The methods named by post site `ref`'s handler names, in symbol order.
    std::vector<NodeId> targets( std::uint32_t ref ) const
    {
        std::vector<NodeId> out;
        if( const HandlerPostSite* s = siteAt( ref ) )
        {
            for( const std::string& n : s->names )
            {
                const auto it = m_methodsByName.find( std::string_view( n ) );
                if( it != m_methodsByName.end() )
                {
                    out.insert( out.end(), it->second.begin(), it->second.end() );
                }
            }
            std::ranges::sort( out );
            out.erase( std::ranges::unique( out ).begin(), out.end() );
        }
        return out;
    }
    // The rule class `c` obeys: the nearest rule base among its ancestors (the most derived one; a base is an ancestor only
    // through a link `linkOk` keeps). Null when no rule covers it, when two unrelated bases both carry one, or when an
    // intermediate class between `c` and that base also writes the attribute in its own `__init_subclass__` (it decides at
    // run time, which this does not read). The ONE rule pick of the name, the post sites and the path block.
    const HandlerRule* ruleOf( NodeId c ) const
    {
        build();
        if( m_rules.empty() || c >= m_ing.symbols.size() )
        {
            return nullptr;
        }
        const auto memo = m_ruleOf.find( c );
        if( memo != m_ruleOf.end() )
        {
            return memo->second < 0 ? nullptr : &m_rules[ std::size_t( memo->second ) ];
        }
        const HandlerRule* rule = pickRule( c );
        m_ruleOf[c]             = rule == nullptr ? -1 : int( rule - m_rules.data() );
        return rule;
    }
    // The rule's name for message class `c` (empty when no rule covers it).
    std::string handlerNameOf( NodeId c ) const
    {
        const HandlerRule* rule = ruleOf( c );
        return rule == nullptr ? std::string() : nameUnder( *rule, c );
    }
    // The file text (empty when unreadable).
    const std::string& text( std::uint32_t fileId ) const
    {
        static const std::string kEmpty;
        if( fileId >= m_ing.files.size() )
        {
            return kEmpty;
        }
        if( m_text.size() != m_ing.files.size() )
        {
            m_text.resize( m_ing.files.size() );
            m_textRead.assign( m_ing.files.size(), 0 );
        }
        if( m_textRead[ fileId ] == 0 )
        {
            m_textRead[ fileId ] = 1;
            m_text[ fileId ]     = darkflags::readWhole( diskPath( m_ing, fileId ) ).value_or( std::string() );
        }
        return m_text[ fileId ];
    }

private:
    std::string_view span( const Symbol& s ) const
    {
        const std::string& t = text( s.fileId );
        return s.sigStartByte < s.endByte && s.endByte <= t.size() ? std::string_view( t ).substr( s.sigStartByte, s.endByte - s.sigStartByte ) : std::string_view();
    }
    struct Template
    {
        std::string prefix;   // the literal identifier prefix (on_)
        std::string hole;     // the one local the f-string holds ({name})
    };
    // `cls.A = f"P{v}"` (either quote) → prefix P and hole v; nullopt for any other line.
    static std::optional<Template> templateOf( std::string_view line, std::string_view attr )
    {
        line = trimWs( line );
        const std::string head = "cls." + std::string( attr );
        if( !line.starts_with( head ) )
        {
            return std::nullopt;
        }
        line = trimWs( line.substr( head.size() ) );
        if( !line.starts_with( '=' ) || line.starts_with( "==" ) )
        {
            return std::nullopt;
        }
        line = trimWs( line.substr( 1 ) );
        if( line.size() < 6 || line[0] != 'f' || ( line[1] != '"' && line[1] != '\'' ) || line.back() != line[1] )
        {
            return std::nullopt;
        }
        const std::string_view body = line.substr( 2, line.size() - 3 );
        const std::size_t      open = body.find( '{' );
        if( open == 0 || open == std::string_view::npos || body.back() != '}' || body.find( '{', open + 1 ) != std::string_view::npos || open + 2 >= body.size()
            || !std::ranges::all_of( body.substr( 0, open ), namesplit::isIdentChar ) || !std::ranges::all_of( body.substr( open + 1, body.size() - open - 2 ), namesplit::isIdentChar )
            || std::isdigit( static_cast<unsigned char>( body[ open + 1 ] ) ) )
        {
            return std::nullopt;
        }
        return Template{ std::string( body.substr( 0, open ) ), std::string( body.substr( open + 1, body.size() - open - 2 ) ) };
    }
    // Is `name` a Python function that is a camel_to_snake converter: its body holds the `[a-z][A-Z]` rule and `.lower()`? Memoised.
    bool isSnakeConverter( std::string_view name ) const
    {
        const auto memo = m_converter.find( std::string( name ) );
        if( memo != m_converter.end() )
        {
            return memo->second != 0;
        }
        const bool hit = std::ranges::any_of( m_ing.symbols, [ & ]( const Symbol& f )
        {
            if( f.name != name || !isPython( f.lang ) || f.kind != SymKind::Function )
            {
                return false;
            }
            const std::string_view body = span( f );
            return body.find( "[a-z][A-Z]" ) != std::string_view::npos && body.find( ".lower()" ) != std::string_view::npos;
        } );
        m_converter[ std::string( name ) ] = hit ? 1 : 0;
        return hit;
    }
    // Does statement text `stmt` call a converter (`conv(` with `conv` not the tail of a longer name)?
    bool callsConverter( std::string_view stmt ) const
    {
        for( std::size_t at = stmt.find( '(' ); at != std::string_view::npos; at = stmt.find( '(', at + 1 ) )
        {
            std::size_t b = at;
            while( b > 0 && namesplit::isIdentChar( stmt[ b - 1 ] ) )
            {
                --b;
            }
            if( b < at && isSnakeConverter( stmt.substr( b, at - b ) ) )
            {
                return true;
            }
        }
        return false;
    }
    // Is EVERY assignment of local `v` in the function a call of a converter (and is there one)? The statement runs on while a
    // bracket is open, so a call split over lines is read whole. `cls.log_key = camel_to_snake( … )` beside `v = x.lower()` is not.
    bool holeIsConverted( std::span<const BodyLine> lines, std::string_view v ) const
    {
        bool any = false;
        for( std::size_t i = 0; i < lines.size(); ++i )
        {
            std::string_view t = trimWs( lines[i].text );
            if( !t.starts_with( v ) || t.size() == v.size() || namesplit::isIdentChar( t[ v.size() ] ) )
            {
                continue;
            }
            t = trimWs( t.substr( v.size() ) );
            if( !t.starts_with( '=' ) || t.starts_with( "==" ) )
            {
                continue;
            }
            std::string stmt( trimWs( t.substr( 1 ) ) );
            int         depth = int( std::ranges::count_if( stmt, []( char c ) { return c == '(' || c == '[' || c == '{'; } ) ) - int( std::ranges::count_if( stmt, []( char c ) { return c == ')' || c == ']' || c == '}'; } ) );
            for( std::size_t k = i + 1; depth > 0 && k < lines.size(); ++k )
            {
                stmt += ' ';
                stmt += std::string( trimWs( lines[k].text ) );
                depth += int( std::ranges::count_if( lines[k].text, []( char c ) { return c == '(' || c == '[' || c == '{'; } ) ) - int( std::ranges::count_if( lines[k].text, []( char c ) { return c == ')' || c == ']' || c == '}'; } ) );
            }
            if( !callsConverter( stmt ) )
            {
                return false;
            }
            any = true;
        }
        return any;
    }
    // Is line `idx` a statement of the function's own top level — under no if/elif/else/for/while/try/except/finally/match/case?
    // Walks the enclosing blocks upward (the nearest earlier line of smaller indent is the parent) to the `def` or the `)` that
    // ends a split signature.
    static bool atTopLevel( std::span<const BodyLine> lines, std::size_t idx )
    {
        static constexpr std::string_view kBlocks[] = { "if", "elif", "else", "for", "while", "try", "except", "finally", "match", "case" };
        std::uint32_t                     cur       = lines[idx].indent;
        for( std::size_t k = idx; k-- > 0; )
        {
            const std::string_view t = trimWs( lines[k].text );
            if( t.empty() || t.front() == '#' || lines[k].indent >= cur )
            {
                continue;
            }
            if( k == 0 || t.front() == ')' || t.starts_with( "def " ) || t.starts_with( "async def " ) )
            {
                return true;
            }
            const bool block = std::ranges::any_of( kBlocks, [ & ]( std::string_view w ) { return t.starts_with( w ) && ( t.size() == w.size() || !namesplit::isIdentChar( t[ w.size() ] ) ); } );
            if( block )
            {
                return false;
            }
            cur = lines[k].indent;
        }
        return true;
    }
    // The class attribute `cls.NAME = …` (an assignment, not `==`) line `t` writes, else empty.
    static std::string_view attrWritten( std::string_view t )
    {
        t = trimWs( t );
        if( !t.starts_with( "cls." ) )
        {
            return {};
        }
        std::size_t e = 4;
        while( e < t.size() && namesplit::isIdentChar( t[e] ) )
        {
            ++e;
        }
        const std::string_view rest = trimWs( t.substr( e ) );
        return e > 4 && rest.starts_with( '=' ) && !rest.starts_with( "==" ) ? t.substr( 4, e - 4 ) : std::string_view();
    }
    // One `cls.A = f"P{v}"` line (index `idx` of __init_subclass__ `writer`'s lines) as a rule, or nullopt: the only write of A in
    // the function, at its top level, with a hole that every assignment of it builds by a converter call.
    std::optional<HandlerRule> ruleAt( NodeId writer, std::span<const BodyLine> lines, std::size_t idx ) const
    {
        const std::string_view attr = attrWritten( lines[idx].text );
        if( attr.empty() )
        {
            return std::nullopt;
        }
        HandlerRule rule;
        rule.attr                          = std::string( attr );
        const std::optional<Template> tpl  = templateOf( lines[idx].text, attr );
        rule.writer                        = writer;
        rule.base                          = m_classes.ownerOf( writer );
        const auto sameAttr                = [ & ]( const BodyLine& l ) { return attrWritten( l.text ) == attr; };
        if( !tpl || rule.base == kNoNode || std::ranges::count_if( lines, sameAttr ) != 1 || !atTopLevel( lines, idx ) || !holeIsConverted( lines, tpl->hole ) )
        {
            return std::nullopt;
        }
        const std::string_view body = span( m_ing.symbols[ writer ] );
        rule.qualified = body.find( "__qualname__" ) != std::string_view::npos;
        if( rule.qualified ? body.find( "[-2:]" ) == std::string_view::npos : body.find( "cls.__name__" ) == std::string_view::npos )
        {
            return std::nullopt;   // a qualname cut other than the last two parts, or no class name at all: not a rule we read
        }
        rule.nsKeyword = body.find( "{namespace}_" ) != std::string_view::npos;
        rule.fileId    = m_ing.symbols[ writer ].fileId;
        rule.line      = lines[idx].no;
        rule.prefix    = tpl->prefix;
        return rule;
    }
    // `namespace="x"` in class c's header, else empty.
    std::string namespaceKeyword( NodeId c ) const
    {
        const Symbol&          s    = m_ing.symbols[c];
        const std::string_view all  = span( s );
        const std::string_view head = all.substr( 0, std::min( all.find( ':' ), all.size() ) );
        const std::size_t      at   = head.find( "namespace" );
        if( at == std::string_view::npos )
        {
            return {};
        }
        std::string_view v = trimWs( head.substr( at + 9 ) );
        if( !v.starts_with( '=' ) )
        {
            return {};
        }
        v = trimWs( v.substr( 1 ) );
        if( v.size() < 2 || ( v[0] != '"' && v[0] != '\'' ) )
        {
            return {};
        }
        const std::size_t close = v.find( v[0], 1 );
        return close == std::string_view::npos ? std::string() : std::string( v.substr( 1, close - 1 ) );
    }
    std::string nameUnder( const HandlerRule& r, NodeId c ) const
    {
        const std::string ns = r.nsKeyword ? namespaceKeyword( c ) : std::string();
        if( !ns.empty() )
        {
            return r.prefix + ns + "_" + snakeOfCamel( m_ing.symbols[c].name );
        }
        const NodeId owner = r.qualified ? m_classes.ownerOf( c ) : kNoNode;
        return r.prefix + ( owner != kNoNode ? snakeOfCamel( m_ing.symbols[ owner ].name ) + "_" : std::string() ) + snakeOfCamel( m_ing.symbols[c].name );
    }
    // The construction a post site's first argument spells: `a.b.X(` after `callee(` → {a, b, X}; empty when it is not one.
    std::vector<std::string_view> constructionAt( const Reference& r ) const
    {
        const std::string_view t( text( r.fileId ) );
        std::size_t at = r.startByte < t.size() ? t.find( r.calleeName, r.startByte ) : std::string_view::npos;
        if( at == std::string_view::npos || at > r.startByte + 256 )
        {
            return {};
        }
        std::size_t i    = at + r.calleeName.size();
        const auto  skip = [ & ] { while( i < t.size() && std::isspace( static_cast<unsigned char>( t[i] ) ) ) { ++i; } };
        skip();
        if( i >= t.size() || t[i] != '(' )
        {
            return {};
        }
        ++i;
        skip();
        std::vector<std::string_view> segs;
        for( ;; )
        {
            const std::size_t b = i;
            while( i < t.size() && namesplit::isIdentChar( t[i] ) )
            {
                ++i;
            }
            if( i == b || std::isdigit( static_cast<unsigned char>( t[b] ) ) )
            {
                return {};
            }
            segs.push_back( t.substr( b, i - b ) );
            if( i < t.size() && t[i] == '.' )
            {
                ++i;
                continue;
            }
            break;
        }
        skip();
        return i < t.size() && t[i] == '(' ? segs : std::vector<std::string_view>();
    }
    // The message classes construction `segs` in reference r may mean: same name; the owner the qualifier spells.
    std::vector<NodeId> classesFor( const Reference& r, std::span<const std::string_view> segs ) const
    {
        std::vector<NodeId> out;
        const auto it = m_messagesByName.find( segs.back() );
        if( it == m_messagesByName.end() )
        {
            return out;
        }
        const NodeId           caller = r.fromSymbol < m_ing.symbols.size() ? m_classes.ownerOf( r.fromSymbol ) : kNoNode;
        const std::string_view q      = segs.size() >= 2 ? segs[ segs.size() - 2 ] : std::string_view();
        const bool             viaSelf = segs.size() == 2 && ( q == "self" || q == "cls" );
        const bool             viaOwner = !viaSelf && !q.empty() && std::isupper( static_cast<unsigned char>( q.front() ) );
        std::ranges::copy_if( it->second, std::back_inserter( out ), [ & ]( NodeId c )
        {
            const NodeId owner = m_classes.ownerOf( c );
            if( viaSelf )
            {
                return owner != kNoNode && caller != kNoNode && m_classes.sameFamily( caller, owner );
            }
            if( viaOwner )
            {
                return owner != kNoNode && m_ing.symbols[ owner ].name == q;
            }
            return owner == kNoNode;   // a bare or module-qualified name: a top-level class
        } );
        return out;
    }
    // Every Python __init_subclass__'s lines, read from the file (the index keeps no attribute writes on a lean verb): the rules,
    // and every class that writes some `cls.A` there (m_writers: the intermediate overrides ruleOf declines on).
    void collectRules() const
    {
        for( const Symbol& w : m_ing.symbols )
        {
            if( !isPython( w.lang ) || w.name != "__init_subclass__" || ( w.kind != SymKind::Function && w.kind != SymKind::Method ) )
            {
                continue;
            }
            const std::string_view body = span( w );
            std::vector<BodyLine>  lines;
            std::uint32_t          lineNo = w.line;
            for( std::size_t at = 0; at < body.size(); at = std::min( body.find( '\n', at ), body.size() ) + 1, ++lineNo )
            {
                const std::string_view l = body.substr( at, std::min( body.find( '\n', at ), body.size() ) - at );
                lines.push_back( BodyLine{ l, std::uint32_t( std::min( l.find_first_not_of( " \t" ), l.size() ) ), lineNo } );
            }
            const NodeId owner = m_classes.ownerOf( w.id );
            for( std::size_t i = 0; i < lines.size(); ++i )
            {
                if( const std::string_view attr = attrWritten( lines[i].text ); !attr.empty() && owner != kNoNode )
                {
                    m_writers.push_back( AttrWriter{ owner, std::string( attr ) } );
                }
                if( std::optional<HandlerRule> rule = ruleAt( w.id, lines, i ) )
                {
                    m_rules.push_back( std::move( *rule ) );
                }
            }
        }
    }
    void collectMessagesAndMethods() const
    {
        m_inClass.assign( m_ing.symbols.size(), 0 );
        m_fnsOfFile.assign( m_ing.files.size(), {} );
        for( const Symbol& s : m_ing.symbols )
        {
            if( !isPython( s.lang ) )
            {
                continue;
            }
            if( s.kind == SymKind::Function || s.kind == SymKind::Method )
            {
                m_fnsOfFile[ s.fileId ].push_back( s.id );
                if( m_classes.ownerOf( s.id ) != kNoNode )
                {
                    m_inClass[ s.id ] = 1;
                    m_methodsByName[ std::string_view( s.name ) ].push_back( s.id );
                }
            }
            else if( s.kind == SymKind::Class && !handlerNameOf( s.id ).empty() )
            {
                m_messagesByName[ std::string_view( s.name ) ].push_back( s.id );
            }
        }
    }
    // The innermost Python function definition of `fileId` holding byte `at`, else kNoNode (definition order: an inner function
    // follows the one it is nested in, so the last that holds `at` is the innermost).
    NodeId functionAt( std::uint32_t fileId, std::uint32_t at ) const
    {
        const auto holds = [ & ]( NodeId f ) { return m_ing.symbols[f].sigStartByte <= at && at < m_ing.symbols[f].endByte; };
        const auto hit   = std::ranges::find_if( m_fnsOfFile[ fileId ] | std::views::reverse, holds );
        return hit == ( m_fnsOfFile[ fileId ] | std::views::reverse ).end() ? kNoNode : *hit;
    }
    // Readers of rule `rule`'s attribute (`.A` not assigned) in Python files outside test paths, read from the text, and every
    // method name their classes define (its posters). Per rule: another rule's readers do not post this rule's messages.
    void collectReaders( HandlerRule& rule ) const
    {
        const std::string needle = "." + rule.attr;
        std::vector<NodeId> readerClasses;
        for( std::uint32_t f = 0; f < m_ing.files.size(); ++f )
        {
            if( m_fnsOfFile[f].empty() || isTestPath( m_ing.files[f] ) )
            {
                continue;
            }
            const std::string_view t( text( f ) );
            for( std::size_t at = t.find( needle ); at != std::string_view::npos; at = t.find( needle, at + 1 ) )
            {
                const std::size_t end  = at + needle.size();
                std::size_t       next = end;
                while( next < t.size() && t[ next ] == ' ' )
                {
                    ++next;
                }
                const bool store = next < t.size() && t[ next ] == '=' && ( next + 1 >= t.size() || t[ next + 1 ] != '=' );
                if( ( end < t.size() && namesplit::isIdentChar( t[ end ] ) ) || store )
                {
                    continue;
                }
                const NodeId fn = functionAt( f, std::uint32_t( at ) );
                if( fn == kNoNode || fn == rule.writer || std::ranges::contains( rule.readers, fn, &HandlerReader::fn ) )
                {
                    continue;
                }
                rule.readers.push_back( HandlerReader{ fn, std::uint32_t( 1 + std::ranges::count( t.substr( 0, at ), '\n' ) ) } );
                if( const NodeId owner = m_classes.ownerOf( fn ); owner != kNoNode )
                {
                    readerClasses.push_back( owner );
                }
            }
        }
        std::ranges::sort( rule.readers, {}, &HandlerReader::fn );
        std::ranges::sort( readerClasses );
        for( const auto& [ name, defs ] : m_methodsByName )
        {
            if( std::ranges::any_of( defs, [ & ]( NodeId d ) { return std::ranges::binary_search( readerClasses, m_classes.ownerOf( d ) ); } ) )
            {
                rule.posters.push_back( name );
            }
        }
        std::ranges::sort( rule.posters, sortutil::svLess );
    }
    // Is `c`'s base link `d` -> `b` one Python resolves to `b`? A base written by name binds (ClassFamilies) to the same-file
    // class, else to EVERY class of that name: where several Python classes carry the name, only the file `d`'s own import of it
    // resolves to is the base (a same-named class of another module is not). Exact or no link.
    bool linkOk( NodeId d, NodeId b ) const
    {
        const Symbol& sd = m_ing.symbols[d];
        const Symbol& sb = m_ing.symbols[b];
        if( !isPython( sb.lang ) )
        {
            return false;
        }
        const auto n = m_pyClassCount.find( std::string_view( sb.name ) );
        if( sb.fileId == sd.fileId || n == m_pyClassCount.end() || n->second <= 1 )
        {
            return true;
        }
        return std::ranges::contains( m_values.importedFilesBinding( sd.fileId, sb.name ), sb.fileId );
    }
    // The ancestors of class `c` through the links linkOk keeps, sorted (a copy: the memo may rehash).
    std::vector<NodeId> ancestors( NodeId c ) const
    {
        if( const auto it = m_ancestors.find( c ); it != m_ancestors.end() )
        {
            return it->second;
        }
        std::vector<NodeId> out;
        std::vector<NodeId> todo { c };
        while( !todo.empty() && out.size() < 4096 )
        {
            const NodeId d = todo.back();
            todo.pop_back();
            m_classes.eachBase( d, [ & ]( NodeId b )
            {
                if( b != c && linkOk( d, b ) && !std::ranges::contains( out, b ) )
                {
                    out.push_back( b );
                    todo.push_back( b );
                }
            } );
        }
        std::ranges::sort( out );
        m_ancestors[c] = out;
        return out;
    }
    // ruleOf without the memo.
    const HandlerRule* pickRule( NodeId c ) const
    {
        if( !isPython( m_ing.symbols[c].lang ) || m_ing.symbols[c].kind != SymKind::Class )
        {
            return nullptr;
        }
        const std::vector<NodeId>       anc = ancestors( c );
        std::vector<const HandlerRule*> cand;
        for( const HandlerRule& r : m_rules )
        {
            if( std::ranges::binary_search( anc, r.base ) )
            {
                cand.push_back( &r );
            }
        }
        // the nearest: the candidate whose own ancestry holds every other candidate's base (two rules of one base, or two
        // unrelated bases, have none: which one runs is not decided here)
        const HandlerRule* best = nullptr;
        for( const HandlerRule* r : cand )
        {
            const std::vector<NodeId> rAnc = ancestors( r->base );
            if( std::ranges::all_of( cand, [ & ]( const HandlerRule* q ) { return q == r || ( q->base != r->base && std::ranges::binary_search( rAnc, q->base ) ); } ) )
            {
                best = r;
                break;
            }
        }
        const bool overridden = best != nullptr && std::ranges::any_of( m_writers, [ & ]( const AttrWriter& w )
        {
            return w.attr == best->attr && w.owner != best->base && std::ranges::binary_search( anc, w.owner ) && std::ranges::contains( ancestors( w.owner ), best->base );
        } );
        return overridden ? nullptr : best;
    }
    void build() const
    {
        if( m_built )
        {
            return;
        }
        m_built = true;
        collectRules();
        if( m_rules.empty() )
        {
            return;
        }
        for( const Symbol& s : m_ing.symbols )
        {
            if( isPython( s.lang ) && s.kind == SymKind::Class )
            {
                ++m_pyClassCount[ std::string_view( s.name ) ];
            }
        }
        collectMessagesAndMethods();
        HashMap<std::string_view, char> posters;
        for( HandlerRule& rule : m_rules )
        {
            collectReaders( rule );
            for( const std::string_view name : rule.posters )
            {
                posters[ name ] = 1;
            }
        }
        for( std::uint32_t i = 0; i < m_ing.references.size(); ++i )
        {
            const Reference& r = m_ing.references[i];
            if( r.role != RefRole::Call || !isPython( r.lang ) || r.fromSymbol >= m_ing.symbols.size() || !posters.contains( std::string_view( r.calleeName ) ) )
            {
                continue;
            }
            const std::vector<std::string_view> segs = constructionAt( r );
            HandlerPostSite site { i, {}, {} };
            for( const NodeId c : segs.empty() ? std::vector<NodeId>() : classesFor( r, segs ) )
            {
                // a class posts through a method only its OWN rule's readers define (another rule's poster is not this rule's)
                if( const HandlerRule* rule = ruleOf( c ); rule != nullptr && std::ranges::binary_search( rule->posters, std::string_view( r.calleeName ), sortutil::svLess ) )
                {
                    site.classes.push_back( c );
                    site.names.push_back( nameUnder( *rule, c ) );
                }
            }
            std::ranges::sort( site.names, sortutil::svLess );
            site.names.erase( std::ranges::unique( site.names ).begin(), site.names.end() );
            if( !site.names.empty() )
            {
                m_siteOfRef[ i ] = std::uint32_t( m_sites.size() );
                m_sites.push_back( std::move( site ) );
            }
        }
    }

    struct AttrWriter
    {
        NodeId      owner = kNoNode;   // the class whose __init_subclass__ writes
        std::string attr;              // cls.attr
    };

    const IngestResult&                                   m_ing;
    const ValueRefIndex&                                  m_values;
    ClassFamilies                                         m_classes;
    mutable bool                                          m_built = false;
    mutable std::vector<HandlerRule>                      m_rules;
    mutable std::vector<HandlerPostSite>                  m_sites;      // reference order
    mutable HashMap<std::uint32_t, std::uint32_t>         m_siteOfRef;  // post-site reference -> its m_sites index
    mutable std::vector<char>                             m_inClass;    // per symbol: a Python function definition inside a class
    mutable std::vector<AttrWriter>                       m_writers;
    mutable HashMap<std::string_view, std::uint32_t>      m_pyClassCount;   // Python class definitions per name
    mutable HashMap<NodeId, std::vector<NodeId>>          m_ancestors;
    mutable HashMap<NodeId, int>                          m_ruleOf;         // class -> index into m_rules, -1 none
    mutable HashMap<std::string, char>                    m_converter;      // function name -> is a camel_to_snake converter
    mutable std::vector<std::vector<NodeId>>              m_fnsOfFile;   // per file: its Python function definitions
    mutable HashMap<std::string_view, std::vector<NodeId>> m_messagesByName;
    mutable HashMap<std::string_view, std::vector<NodeId>> m_methodsByName;
    mutable std::vector<std::string>                      m_text;
    mutable std::vector<char>                             m_textRead;
};

}   // namespace rw
