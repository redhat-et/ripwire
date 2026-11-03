#pragma once
// forselfhook.h — THE SELF HOOK of a --for answer (lane self-hook): a served Python override names WHERE its base classes reach it
// through `self` or `cls`.
//
// WHY. "What calls SessionMiddleware.process_request?" serves that method's body and no caller: the only call is
// `self.process_request(request)` in MiddlewareMixin.__call__, under `hasattr`, and the mixin defines no such method, so the resolver
// has nothing to bind it to. "Which get_handler runs for runserver?" serves both get_handler bodies and neither names
// Command.inner_run, which calls self.get_handler: the edge is proven to the BASE's definition, so `--callers` lists it there, and the
// subtoken route has no caller hop at all. The site is in the index both times; the answer never says it.
//
// WHAT. <selfhooks total= shown= capped=> after the dispatch hop and before the bodies, one <selfhook> per served override:
// n= p= the served method; overrides= op= the base definition the method resolution order picks when the inheritance edges PROVE which
// one that is, else candidates= the base definitions it chooses among (abstract=), or hook=1 when no base defines it; defs= the
// definitions in the inheritance cone, test= of them on test paths (counted, never named); sites= shown= capped= next= skipped=; one
// <s n= p=file:line [test=1] [recv=cls] [form=ref|getattr] [guarded=1]> per site, non-test first, nearest base first.
// Hedged by construction: nothing enters a reaches= set, a count or --impact, and no edge is added. The list says where the base can
// reach the method; only instances of this class get there.
//
// ALLOWLIST. Every site is decided by the PARSE, never by a text scan: a call or read through `self` counts only in a method whose first
// parameter is `self`, directly in the class body, not a static or class method, where the name `self` is never bound again; `cls` only
// in a classmethod whose first parameter it is, never rebound; a getattr/hasattr is a Call reference of the index whose argument nodes
// are the receiver name and a plain string literal. Any other shape prints no site and is counted in skipped= (a floor, never named).
//
// BASES. The proven implementors edges, plus the edge buildGraph never draws: a base clause spelled with a RENAMED import
// (`from m import Command as RunserverCommand`; class Command(RunserverCommand)), where no class has the written name so the map holds
// nothing. That one is read here, for this element only, under the resolver's own rule for a renamed import (buildPythonRenamedImports,
// the module-scope rebind table, the star-import and dynamic-namespace marks, the endpoint's one binding: the tables pythonRenamedImportPin
// reads) and a full module path; it enters no graph table (--lego keeps its answer).
//
// WHEN. A served Python method (an auto <bodies> body, a fold/slot body, or a member the task names of a class served whole) of a non-test class, whose name has two or more definitions
// in the inheritance cone of its class, with at least one site in a base class. The default regime and the XML dialect (the dispatch
// hop's posture); under a token budget only a held marker. Bases are walked over PROVEN implementors edges only, so a namesake class (two
// `Command`s in two modules) never crosses; a by-name base leaves the walk short and the element silent, a floor rather than a guess.
// RIPWIRE_NO_SELF_HOOK (any value) turns it off — the A/B handle.

#include "crossref.h"        // crossref::wholeWordAt
#include "filter.h"          // isTestSymbol
#include "graph.h"           // readTextIfPresent, the renamed-import tables, pythonClassScopeChain
#include "infra/fieldid.h"   // fieldChild
#include "infra/sortutil.h"    // sortutil::svLess: the explicit byte order for a string_view key (portablebuildcheck #6)
#include "infra/tschildren.h"
#include "memberowner.h"
#include "model.h"
#include "nextverb.h"
#include "receiverevidence.h"   // ReceiverEvidence::callableKind / classLike
#include "sarif.h"           // rootRelativeUri
#include "serialize.h"       // escapeXml, diskPath

#include <algorithm>
#include <cctype>
#include <cstddef>
#include <cstdint>
#include <cstdlib>
#include <limits>
#include <memory>
#include <optional>
#include <span>
#include <string>
#include <string_view>
#include <tuple>
#include <utility>
#include <vector>

extern "C"
{
    const TSLanguage* tree_sitter_python( void );
}

namespace rw
{

// Runaway guards, not size targets: every row left out is counted (total=, sites=, capped="1") and next= lists the sites.
inline constexpr std::size_t kForSelfHookSiteRows      = 3;   // base-class sites per served method
inline constexpr std::size_t kForSelfHookMethodRows    = 4;   // served methods per answer
inline constexpr std::size_t kForSelfHookCandidateRows = 4;   // base definitions named when the order picks none provably

inline bool forSelfHookOn()
{
    return std::getenv( "RIPWIRE_NO_SELF_HOOK" ) == nullptr;
}

inline constexpr std::string_view kForSelfHookLegend =
    "; selfhooks total= shown= capped=: served methods whose base classes reach them through self or cls (a method with one definition in its cone, or with no base-class site, is neither listed nor counted), "
    "held=budget a token budget is set so the list was not rendered and total= is how many it holds, selfhook n= p= the served method, "
    "overrides= op= the base definition the method resolution order picks, named only when every other base definition sits above it in the inheritance edges, "
    "candidates= the base definitions the order chooses among when that is not provable here, abstract=1 the overrides definition raises NotImplementedError or is marked abstract, "
    "hook=1 no base class in this tree defines it, defs= definitions in the inheritance cone, test= of them on test paths, not named, "
    "sites= shown= capped=1 next= runs the verb that lists the rest, skipped= base-class uses through a receiver the parse does not prove is the instance (rebound, a closure, a lambda, a static method), counted and never listed, "
    "unread= base-class files that could not be read again, so their uses or an abstract mark are missing (a floor), "
    "s n= p=file:line a site in a base class (test=1 that base is on a test path, recv=cls through cls, form=ref a read with no call syntax, a property read still runs it, "
    "form=getattr by string, guarded=1 a hasattr or getattr on that name for that receiver comes earlier in that function: text order only, it does not say the call is conditional). "
    "A call through self reaches this override only for instances of this class and other subclasses may run their own: which one runs is unproven, never an edge";
inline constexpr std::string_view kForCompactSelfHookLegend =
    "; selfhooks total= shown= capped=: served methods reached through self or cls from a base class (one definition in the cone, or no base site: not listed), held=budget not rendered under a token budget, "
    "selfhook n= p=, overrides= op= the base def the order picks when provable, candidates= the base defs it chooses among, abstract=1, hook=1 no base defines it, "
    "defs= in the cone, test= not named, sites= shown= capped=1 next= runs the verb listing the rest, skipped= uses through a receiver not proven the instance, counted, unread= base files that could not be read again, uses there missing (a floor), "
    "s n= p=file:line the base site (test=1 base on a test path, recv=cls, form=ref read not called, form=getattr by string, guarded=1 a hasattr or getattr on the name earlier in the function: text order only). "
    "Reaches this override only for its own instances, other subclasses may run theirs: never an edge";
static_assert( kForSelfHookLegend.find( ';', 1 ) == std::string_view::npos && kForCompactSelfHookLegend.find( ';', 1 ) == std::string_view::npos
                   && kForSelfHookLegend.find( "--" ) == std::string_view::npos && kForCompactSelfHookLegend.find( "--" ) == std::string_view::npos,
               "one clause each, and no \"--\": it rides inside an XML comment" );

namespace selfhook_detail
{
// The mechanism's family rows (CONTRIBUTING "Family rows"): the languages whose methods call their overrides through a receiver spelled
// in the source, and how that spelling reads. A language without a row carries no element.
struct FamilyRow
{
    Lang             lang;
    std::string_view memberImportMark;   // a Binding's importedName prefix for a member import; the member follows it
    std::string_view selfRecv;    // the instance receiver, recorded as RecvKind::ThisObj
    std::string_view classRecv;   // the class receiver, a plain name: it counts only as the first parameter of a class method
    std::string_view probe;       // true when the object has the attribute, the name in a string
    std::string_view fetch;       // the attribute by string
    std::string_view abstractRaise;
    std::string_view abstractMark;
    std::string_view staticMark;   // the decorators that take no instance receiver
    std::string_view classMark;
};
inline constexpr FamilyRow kFamilyRows[] = {
    { Lang::Python, kPythonFromMemberMark, "self", "cls", "hasattr", "getattr", "NotImplementedError", "abstractmethod", "staticmethod", "classmethod" },
};
inline const FamilyRow* familyRow( Lang l ) noexcept
{
    switch( l )   // a switch, not a language-equality predicate: the language-identity ratchet counts those in shared files
    {
        case Lang::Python: return &kFamilyRows[0];
        default:           return nullptr;
    }
}

// ── the parse ────────────────────────────────────────────────────────────────────────────────────────────────

// One file's bytes and their parse. A file that cannot be read or parsed is unusable: every question about it answers "no", which claims nothing.
class ParsedFile
{
public:
    explicit ParsedFile( std::string bytes ) : m_bytes( std::move( bytes ) )
    {
        if( m_bytes.size() > std::numeric_limits<std::uint32_t>::max() )
        {
            return;
        }
        // The parser cannot come back null (tree-sitter's allocator aborts rather than return null, and no ripwire code calls ts_set_allocator),
        // and the Python grammar is statically linked at a supported ABI.
        TSParser* parser = ts_parser_new();
        ASSUME( parser != nullptr, "ts_parser_new: the default tree-sitter allocator aborts on failure" );
        const bool isLanguageSet = ts_parser_set_language( parser, tree_sitter_python() );
        ASSUME( isLanguageSet, "the Python grammar is linked into this binary at a supported ABI" );
        m_tree = ts_parser_parse_string( parser, nullptr, m_bytes.data(), std::uint32_t( m_bytes.size() ) );
        ts_parser_delete( parser );
    }
    ~ParsedFile()
    {
        if( m_tree != nullptr )
        {
            ts_tree_delete( m_tree );
        }
    }
    ParsedFile( const ParsedFile& )            = delete;
    ParsedFile& operator=( const ParsedFile& ) = delete;

    bool usable() const noexcept { return m_tree != nullptr; }
    TSNode root() const { return ts_tree_root_node( m_tree ); }
    std::string_view text( TSNode n ) const
    {
        if( ts_node_is_null( n ) || ts_node_end_byte( n ) > m_bytes.size() )
        {
            return {};
        }
        return std::string_view( m_bytes ).substr( ts_node_start_byte( n ), ts_node_end_byte( n ) - ts_node_start_byte( n ) );
    }

private:
    std::string m_bytes;
    TSTree*     m_tree = nullptr;
};

inline bool isType( TSNode n, std::string_view type ) noexcept
{
    if( ts_node_is_null( n ) )
    {
        return false;
    }
    return std::string_view( ts_node_type( n ) ) == type;
}

// The function_definition a method symbol's span holds, a null node when the span holds anything else (a changed file, a syntax error).
inline TSNode functionOf( const ParsedFile& f, const Symbol& s )
{
    if( !f.usable() )
    {
        return TSNode{};
    }
    TSNode n = ts_node_descendant_for_byte_range( f.root(), s.sigStartByte, s.endByte );
    while( !ts_node_is_null( n ) && !isType( n, "function_definition" ) && !isType( n, "decorated_definition" ) )
    {
        n = ts_node_parent( n );
    }
    if( isType( n, "decorated_definition" ) )
    {
        n = fieldChild( n, NodeField::Definition );
    }
    if( !isType( n, "function_definition" ) || ts_node_start_byte( n ) < s.sigStartByte || ts_node_end_byte( n ) > s.endByte
        || f.text( fieldChild( n, NodeField::Name ) ) != s.name || ts_node_has_error( n ) )
    {
        return TSNode{};
    }
    return n;
}

// Is one of `fn`'s decorators `@name` (or, with `qualified`, `@pkg.name`)?
inline bool decoratedWith( const ParsedFile& f, TSNode fn, std::string_view name, bool qualified )
{
    const TSNode parent = ts_node_parent( fn );
    if( !isType( parent, "decorated_definition" ) )
    {
        return false;
    }
    for( std::uint32_t i = 0; i < ts_node_named_child_count( parent ); ++i )
    {
        const TSNode d = ts_node_named_child( parent, i );
        if( !isType( d, "decorator" ) )
        {
            continue;
        }
        std::string_view t = f.text( d );
        t.remove_prefix( std::min<std::size_t>( 1, t.size() ) );   // the @
        t.remove_prefix( std::min( t.find_first_not_of( " \t" ), t.size() ) );
        t.remove_suffix( t.size() - std::min( t.find_last_not_of( " \t\r\n" ) + 1, t.size() ) );
        if( t == name || ( qualified && t.size() > name.size() && t.ends_with( name ) && t[ t.size() - name.size() - 1 ] == '.' ) )
        {
            return true;
        }
    }
    return false;
}

// Is `recv` the first parameter of `fn`?
inline bool firstParamIs( const ParsedFile& f, TSNode fn, std::string_view recv )
{
    const TSNode params = fieldChild( fn, NodeField::Parameters );
    if( ts_node_is_null( params ) || ts_node_named_child_count( params ) == 0 )
    {
        return false;
    }
    TSNode first = ts_node_named_child( params, 0 );
    if( isType( first, "typed_parameter" ) && ts_node_named_child_count( first ) > 0 )
    {
        first = ts_node_named_child( first, 0 );
    }
    return isType( first, "identifier" ) && f.text( first ) == recv;
}

// Is `id` (an identifier spelled like the receiver) a READ of it? A binder slot, a parameter or an import alias is not. The shapes that read
// are listed; anything else is not read here (the method is then not trusted: a floor).
inline bool readsName( TSNode id )
{
    const auto container = []( std::string_view t )
    {
        return t == "tuple" || t == "list" || t == "set" || t == "expression_list" || t == "parenthesized_expression" || t == "pattern_list"
               || t == "tuple_pattern" || t == "list_pattern" || t == "list_splat" || t == "list_splat_pattern" || t == "parenthesized_pattern";
    };
    TSNode child  = id;
    TSNode parent = ts_node_parent( child );
    while( !ts_node_is_null( parent ) && container( ts_node_type( parent ) ) )
    {
        child  = parent;
        parent = ts_node_parent( child );
    }
    if( ts_node_is_null( parent ) )
    {
        return false;
    }
    const std::string_view t = ts_node_type( parent );
    if( t == "attribute" || t == "keyword_argument" )
    {
        return true;   // `self.x`: the object; `x.self` and `f(self=1)` name no variable
    }
    if( t == "assignment" || t == "augmented_assignment" || t == "for_statement" || t == "for_in_clause" )
    {
        return !ts_node_eq( fieldChild( parent, NodeField::Left ), child );
    }
    if( t == "named_expression" )
    {
        return !ts_node_eq( fieldChild( parent, NodeField::Name ), child );
    }
    static constexpr std::string_view kReads[] = { "argument_list", "call", "subscript", "slice", "comparison_operator", "boolean_operator", "not_operator",
                                                    "unary_operator", "binary_operator", "conditional_expression", "await", "yield", "return_statement",
                                                    "expression_statement", "assert_statement", "raise_statement", "pair", "if_statement", "elif_clause",
                                                    "while_statement", "interpolation", "format_expression", "dictionary", "dictionary_splat" };
    return std::ranges::find( kReads, t ) != std::end( kReads );
}

// Is the attribute whose NAME identifier starts at byte `at` a binding target (`self.x, y = ..`, `for self.x in ..`, `with c as self.x`, `del self.x`),
// not a read? The index records only a plain assignment's left side as a write; these four are read here from the parse. A write is no site.
inline bool bindsAttribute( const ParsedFile& f, std::uint32_t at )
{
    if( !f.usable() )
    {
        return false;
    }
    TSNode child = ts_node_descendant_for_byte_range( f.root(), at, at + 1 );
    if( !isType( child, "identifier" ) || ts_node_start_byte( child ) != at )
    {
        return false;
    }
    child = ts_node_parent( child );
    if( !isType( child, "attribute" ) )
    {
        return false;
    }
    static constexpr std::string_view kContainers[] = { "tuple", "list", "expression_list", "parenthesized_expression", "pattern_list", "tuple_pattern",
                                                         "list_pattern", "list_splat", "list_splat_pattern", "parenthesized_pattern" };
    TSNode parent = ts_node_parent( child );
    while( !ts_node_is_null( parent ) && std::ranges::find( kContainers, std::string_view( ts_node_type( parent ) ) ) != std::end( kContainers ) )
    {
        child  = parent;
        parent = ts_node_parent( child );
    }
    if( ts_node_is_null( parent ) )
    {
        return false;
    }
    const std::string_view t = ts_node_type( parent );
    if( t == "delete_statement" || t == "as_pattern_target" )
    {
        return true;
    }
    return ( t == "assignment" || t == "for_statement" || t == "for_in_clause" ) && ts_node_eq( fieldChild( parent, NodeField::Left ), child );
}

// Does a `nonlocal <recv>` sit anywhere under `scope`? A nested def that declares it rebinds the enclosing method's name.
inline bool declaresNonlocal( const ParsedFile& f, TSNode scope, std::string_view recv )
{
    std::vector<TSNode> todo{ scope };
    while( !todo.empty() )
    {
        const TSNode n = todo.back();
        todo.pop_back();
        if( isType( n, "nonlocal_statement" ) )
        {
            for( std::uint32_t i = 0; i < ts_node_named_child_count( n ); ++i )
            {
                if( f.text( ts_node_named_child( n, i ) ) == recv )
                {
                    return true;
                }
            }
            continue;
        }
        for( std::uint32_t i = 0; i < ts_node_child_count( n ); ++i )
        {
            todo.push_back( ts_node_child( n, i ) );
        }
    }
    return false;
}

// Is `fn` re-bound in its class body as `fn = staticmethod(fn)` / `fn = classmethod(fn)`: a method that takes no instance receiver by assignment?
inline bool wrappedAfterDef( const ParsedFile& f, TSNode fn, const FamilyRow& row )
{
    TSNode self = fn;
    if( isType( ts_node_parent( self ), "decorated_definition" ) )
    {
        self = ts_node_parent( self );
    }
    const TSNode block = ts_node_parent( self );
    if( !isType( block, "block" ) )
    {
        return false;
    }
    const std::string_view name = f.text( fieldChild( fn, NodeField::Name ) );
    for( std::uint32_t i = 0; i < ts_node_named_child_count( block ); ++i )
    {
        TSNode st = ts_node_named_child( block, i );
        if( isType( st, "expression_statement" ) && ts_node_named_child_count( st ) == 1 )
        {
            st = ts_node_named_child( st, 0 );
        }
        if( !isType( st, "assignment" ) )
        {
            continue;
        }
        const TSNode left  = fieldChild( st, NodeField::Left );
        const TSNode right = fieldChild( st, NodeField::Right );
        if( isType( left, "identifier" ) && f.text( left ) == name && isType( right, "call" ) )
        {
            const std::string_view callee = f.text( fieldChild( right, NodeField::Function ) );
            if( callee.ends_with( row.staticMark ) || callee.ends_with( row.classMark ) )
            {
                return true;
            }
        }
    }
    return false;
}

// Is `recv` bound nowhere in `fn`'s own scope but as its first parameter? Every identifier spelled like it must be a read; a nested def or
// class keeps its own scope (its uses are its own symbol's) but must not be named like it; a lambda's parameters are this scope's names.
inline bool neverRebound( const ParsedFile& f, TSNode fn, std::string_view recv )
{
    std::vector<TSNode> todo{ fieldChild( fn, NodeField::Body ) };
    while( !todo.empty() )
    {
        const TSNode n = todo.back();
        todo.pop_back();
        if( ts_node_is_null( n ) )
        {
            continue;
        }
        if( isType( n, "function_definition" ) || isType( n, "class_definition" ) )
        {
            if( f.text( fieldChild( n, NodeField::Name ) ) == recv || declaresNonlocal( f, n, recv ) )
            {
                return false;
            }
            continue;
        }
        if( isType( n, "identifier" ) && f.text( n ) == recv && !readsName( n ) )
        {
            return false;
        }
        for( std::uint32_t i = 0; i < ts_node_child_count( n ); ++i )
        {
            todo.push_back( ts_node_child( n, i ) );
        }
    }
    return true;
}

// The method's receiver is the instance (`self`) or the class (`cls`): the first parameter, of the kind of method that passes it, never rebound.
inline bool receiverProven( const ParsedFile& f, TSNode fn, const FamilyRow& row, bool viaCls )
{
    if( ts_node_is_null( fn ) )
    {
        return false;
    }
    if( wrappedAfterDef( f, fn, row ) )
    {
        return false;   // `f = staticmethod(f)`: what the receiver is, is no longer the def's to say
    }
    const bool isStatic = decoratedWith( f, fn, row.staticMark, false );
    const bool isClass  = decoratedWith( f, fn, row.classMark, false );
    const std::string_view recv = viaCls ? row.classRecv : row.selfRecv;
    if( viaCls ? !isClass : ( isStatic || isClass ) )
    {
        return false;
    }
    return firstParamIs( f, fn, recv ) && neverRebound( f, fn, recv );
}

// `<fn>( <recv>, "<name>"` as the call that starts at byte `at`: a plain identifier callee, the receiver name, a string literal with no prefix,
// escape or interpolation.
inline bool stringAttrCall( const ParsedFile& f, std::uint32_t at, std::string_view fn, std::string_view recv, std::string_view name )
{
    if( !f.usable() )
    {
        return false;
    }
    TSNode n = ts_node_descendant_for_byte_range( f.root(), at, at + 1 );
    for( int up = 0; up < 3 && !ts_node_is_null( n ) && !isType( n, "call" ); ++up )
    {
        n = ts_node_parent( n );
    }
    if( !isType( n, "call" ) || ts_node_start_byte( n ) != at )
    {
        return false;
    }
    const TSNode callee = fieldChild( n, NodeField::Function );
    const TSNode args   = fieldChild( n, NodeField::Arguments );
    if( !isType( callee, "identifier" ) || f.text( callee ) != fn || !isType( args, "argument_list" ) || ts_node_named_child_count( args ) < 2 )
    {
        return false;
    }
    const TSNode first  = ts_node_named_child( args, 0 );
    const TSNode second = ts_node_named_child( args, 1 );
    if( !isType( first, "identifier" ) || f.text( first ) != recv || !isType( second, "string" ) || ts_node_child_count( second ) != 3 )
    {
        return false;
    }
    const std::string_view open = f.text( ts_node_child( second, 0 ) );
    return ( open == "\"" || open == "'" ) && isType( ts_node_child( second, 1 ), "string_content" ) && f.text( ts_node_child( second, 1 ) ) == name;
}

// Does `fn` raise NotImplementedError in its own scope, or carry an abstract decorator?
inline bool isAbstractDef( const ParsedFile& f, TSNode fn, const FamilyRow& row )
{
    if( ts_node_is_null( fn ) )
    {
        return false;
    }
    if( decoratedWith( f, fn, row.abstractMark, true ) )
    {
        return true;
    }
    std::vector<TSNode> todo{ fieldChild( fn, NodeField::Body ) };
    while( !todo.empty() )
    {
        const TSNode n = todo.back();
        todo.pop_back();
        if( ts_node_is_null( n ) || isType( n, "function_definition" ) || isType( n, "class_definition" ) )
        {
            continue;
        }
        if( isType( n, "raise_statement" ) && ts_node_named_child_count( n ) > 0 )
        {
            TSNode what = ts_node_named_child( n, 0 );
            if( isType( what, "call" ) )
            {
                what = fieldChild( what, NodeField::Function );
            }
            if( isType( what, "identifier" ) && f.text( what ) == row.abstractRaise )
            {
                return true;
            }
        }
        for( std::uint32_t i = 0; i < ts_node_child_count( n ); ++i )
        {
            todo.push_back( ts_node_child( n, i ) );
        }
    }
    return false;
}

// The parses of the files the sites sit in, a few kept: the sites of one method sit in few files.
class SourceReader
{
public:
    explicit SourceReader( const IngestResult& ing ) : m_ing( ing ) {}
    // The parse of file `file`, nullptr when it cannot be read. The pointer lives until the next call.
    const ParsedFile* parsed( std::uint32_t file )
    {
        for( const Entry& e : m_kept )
        {
            if( e.file == file )
            {
                return e.parse.get();
            }
        }
        if( m_kept.size() >= kKeep )
        {
            m_kept.erase( m_kept.begin() );
        }
        bool                       unreadable = false;
        std::optional<std::string> bytes      = readTextIfPresent( diskPath( m_ing, file ), unreadable );
        std::unique_ptr<ParsedFile> parse = bytes.has_value() ? std::make_unique<ParsedFile>( std::move( *bytes ) ) : nullptr;
        if( parse != nullptr && !parse->usable() )
        {
            parse.reset();   // no tree: as unread as a missing file, and counted the same (unread=)
        }
        m_kept.push_back( Entry{ file, std::move( parse ) } );
        return m_kept.back().parse.get();
    }

private:
    static constexpr std::size_t kKeep = 16;
    struct Entry
    {
        std::uint32_t               file;
        std::unique_ptr<ParsedFile> parse;
    };
    const IngestResult& m_ing;
    std::vector<Entry>  m_kept;
};

// The classes of the family's languages by file, for the class whose span holds a member.
class ClassIndex
{
public:
    explicit ClassIndex( const IngestResult& ing ) : m_ing( ing )
    {
        for( NodeId id = 0; id < ing.symbols.size(); ++id )
        {
            const Symbol& s = ing.symbols[id];
            if( ReceiverEvidence::classLike( s.kind ) && s.endByte > s.sigStartByte && familyRow( s.lang ) != nullptr )
            {
                m_classes.push_back( id );
            }
        }
        std::ranges::sort( m_classes, [ & ]( NodeId a, NodeId b ) { return keyOf( a ) < keyOf( b ); } );
    }
    // The innermost class whose span holds `m`, kNoNode when none does.
    NodeId ownerOf( const Symbol& m ) const
    {
        const auto lower = std::ranges::lower_bound( m_classes, m.fileId, {}, [ & ]( NodeId c ) { return m_ing.symbols[c].fileId; } );
        NodeId     best  = kNoNode;
        for( auto it = lower; it != m_classes.end() && m_ing.symbols[ *it ].fileId == m.fileId && m_ing.symbols[ *it ].sigStartByte <= m.sigStartByte; ++it )
        {
            if( m_ing.symbols[ *it ].id != m.id && m.endByte <= m_ing.symbols[ *it ].endByte )
            {
                best = *it;   // ascending start: a later class that still holds the member is nested inside the earlier one
            }
        }
        return best;
    }

private:
    std::pair<std::uint32_t, std::uint32_t> keyOf( NodeId c ) const { return { m_ing.symbols[c].fileId, m_ing.symbols[c].sigStartByte }; }
    const IngestResult& m_ing;
    std::vector<NodeId> m_classes;
};

// A base class and its distance from the served method's class: 1 for a direct base.
struct Ancestor
{
    NodeId        id    = kNoNode;
    std::uint32_t depth = 0;
};
inline bool provenEdge( const Graph& g, NodeId base, std::size_t childIx ) noexcept
{
    return base < g.implementorBound.size() && childIx < g.implementorBound[ base ].size() && g.implementorBound[ base ][ childIx ] == static_cast<std::uint8_t>( BaseBound::Proven );
}

// `a.b.c` from `dir/x.py` (a leading dot climbs from the file's directory) to the ONE indexed file it names, kNoFile for none or several.
// An absolute module names its whole path from the indexed root (or under one `src/`): a suffix match would bind `logging` to a
// vendored `compat/logging.py`, and the standard library's module is not in the tree.
inline std::uint32_t moduleFileOf( const IngestResult& ing, std::string_view module, std::uint32_t fromFile )
{
    std::string stem;
    bool        relative = false;
    if( module.starts_with( '.' ) )
    {
        relative = true;
        stem     = rootRelPath( ing, fromFile );
        for( ; module.starts_with( '.' ); module.remove_prefix( 1 ) )
        {
            const std::size_t slash = stem.rfind( '/' );
            stem.resize( slash == std::string::npos ? 0 : slash );
        }
        if( !stem.empty() )
        {
            stem += '/';
        }
    }
    for( const char c : module )
    {
        stem += c == '.' ? '/' : c;
    }
    std::uint32_t found = kNoFile;
    for( std::uint32_t f = 0; f < ing.files.size(); ++f )
    {
        const std::string_view path = rootRelPath( ing, f );
        for( const std::string_view tail : { std::string_view( ".py" ), std::string_view( "/__init__.py" ) } )
        {
            const std::size_t whole = stem.size() + tail.size();
            const bool        hit   = path.size() == whole ? path.starts_with( stem ) && path.ends_with( tail )
                                                           : !relative && path.size() == whole + 4 && path.starts_with( "src/" ) && path.substr( 4 ).starts_with( stem )
                                                                 && path.ends_with( tail );
            if( !hit )
            {
                continue;
            }
            if( found != kNoFile && found != f )
            {
                return kNoFile;
            }
            found = f;
        }
    }
    return found;
}
// The (derived, base) edges a renamed import states (see BASES above). The resolver's rule for the written name decides whether it means the
// import: every import of it in the file is that one module-scope rename, nothing at module scope binds it again (an assignment, a class or
// def, a for/with/except target, a global), no star import or dynamic namespace write may bind it, and the derived class sits at module scope
// (a base clause evaluates where the class is written). The import names ONE module file by its full path that the graph's own table agrees on,
// whose module scope binds the member only by its one module-level class. Anything else leaves the edge out: a floor.
inline void addRenamedImportBases( const IngestResult& ing, std::vector<std::pair<NodeId, NodeId>>& edges )
{
    struct Renamed
    {
        std::uint32_t    file;
        std::string_view var;
        std::string_view member;
        std::string_view module;
    };
    std::vector<Renamed> renamed;
    for( const Binding& b : ing.bindings )
    {
        if( b.kind != LocalBindKind::Import || b.fromSymbol != kNoNode || b.importedName == "module" )
        {
            continue;
        }
        const std::string_view imported = b.importedName;
        for( const FamilyRow& row : kFamilyRows )
        {
            if( imported.starts_with( row.memberImportMark ) && imported.substr( row.memberImportMark.size() ) != b.var )
            {
                renamed.push_back( Renamed{ b.fileId, b.var, imported.substr( row.memberImportMark.size() ), b.typeName } );
            }
        }
    }
    if( renamed.empty() )
    {
        return;
    }
    const auto key = []( const Renamed& r ) { return std::pair( r.file, r.var ); };
    const auto keyLess = []( const auto& a, const auto& b ) { return a.first != b.first ? a.first < b.first : sortutil::svLess( a.second, b.second ); };
    std::ranges::sort( renamed, [ & ]( const Renamed& a, const Renamed& b ) { return keyLess( key( a ), key( b ) ); } );
    struct Clause
    {
        const Reference* ref;
        const Renamed*   entry;
    };
    std::vector<Clause> clauses;
    for( const Reference& r : ing.references )
    {
        if( !r.isInherit || !r.memberRoot.empty() || r.fromSymbol >= ing.symbols.size() || familyRow( r.lang ) == nullptr )
        {
            continue;
        }
        const std::pair written( r.fileId, std::string_view( r.calleeName ) );
        const auto      hit = std::ranges::equal_range( renamed, written, keyLess, key );
        if( hit.size() == 1 )
        {
            clauses.push_back( Clause{ &r, &hit.front() } );
        }
    }
    if( clauses.empty() )
    {
        return;
    }
    const PythonRenamedImports imports = buildPythonRenamedImports( ing );
    const ExternalVetoTables   veto    = buildExternalVetoTables( ing );
    // the module-level classes by (name, file), to find the one a member names
    std::vector<std::tuple<std::string_view, std::uint32_t, NodeId>> classes;
    for( NodeId c = 0; c < ing.symbols.size(); ++c )
    {
        const Symbol& s = ing.symbols[c];
        if( familyRow( s.lang ) != nullptr && ReceiverEvidence::classLike( s.kind ) )
        {
            classes.emplace_back( s.name, s.fileId, c );
        }
    }
    const auto classKeyLess = []( const auto& a, const auto& b ) { return a.first != b.first ? sortutil::svLess( a.first, b.first ) : a.second < b.second; };
    const auto classLess = []( const auto& a, const auto& b )
    {
        return std::get<0>( a ) != std::get<0>( b ) ? sortutil::svLess( std::get<0>( a ), std::get<0>( b ) ) : std::pair( std::get<1>( a ), std::get<2>( a ) ) < std::pair( std::get<1>( b ), std::get<2>( b ) );
    };
    std::ranges::sort( classes, classLess );
    std::string       buf;
    const auto        rebound = [ & ]( std::uint32_t file, std::string_view name ) { return veto.pythonModuleRebind.contains( fileNameKey( buf, file, name ) ); };
    for( const Clause& c : clauses )
    {
        const Reference& r  = *c.ref;
        const auto       it = imports.renamed.find( fileNameKey( buf, r.fileId, r.calleeName ) );
        if( it == imports.renamed.end() || it->second != c.entry->member || rebound( r.fileId, r.calleeName ) || rebound( r.fileId, kPythonDynamicWrite )
            || ( r.fileId < veto.pythonScopes.starTargets.size() && !veto.pythonScopes.starTargets[ r.fileId ].empty() )
            || !pythonClassScopeChain( ing, r.fromSymbol ).empty() )
        {
            continue;
        }
        const std::uint32_t file = moduleFileOf( ing, c.entry->module, r.fileId );
        const auto          mf   = veto.memberImportFile.find( fileNameKey( buf, r.fileId, r.calleeName ) );
        if( file == kNoFile || mf == veto.memberImportFile.end() || mf->second != file || rebound( file, kPythonDynamicWrite ) || !pythonEndpointBindsOnlyByClass( veto, file, c.entry->member ) )
        {
            continue;
        }
        const auto named = std::ranges::equal_range( classes, std::pair( c.entry->member, file ), classKeyLess,
                                                     []( const auto& t ) { return std::pair( std::get<0>( t ), std::get<1>( t ) ); } );
        if( named.size() == 1 && pythonClassScopeChain( ing, std::get<2>( named.front() ) ).empty() )
        {
            edges.emplace_back( r.fromSymbol, std::get<2>( named.front() ) );
        }
    }
}

// Every (child, base) edge the index proves, ascending: buildGraph binds a base NAME to every same-named class, so a by-name edge is exactly
// the namesake crossing this element must not make.
inline std::vector<std::pair<NodeId, NodeId>> provenParents( const IngestResult& ing, const Graph& g )
{
    std::vector<std::pair<NodeId, NodeId>> out;
    for( NodeId base = 0; base < g.implementors.size(); ++base )
    {
        for( std::size_t i = 0; i < g.implementors[ base ].size(); ++i )
        {
            if( provenEdge( g, base, i ) )
            {
                out.emplace_back( g.implementors[ base ][ i ], base );
            }
        }
    }
    addRenamedImportBases( ing, out );
    std::ranges::sort( out );
    return out;
}
// The classes (ascending) with a base edge the index does not prove: a by-name base binds every same-named class, so it may be a namesake.
// The method resolution order can run such a base ahead of a proven one, so the walk up from such a class is short and stays silent.
inline std::vector<NodeId> classesWithUnprovenBase( const Graph& g )
{
    std::vector<NodeId> out;
    for( NodeId base = 0; base < g.implementors.size(); ++base )
    {
        for( std::size_t i = 0; i < g.implementors[ base ].size(); ++i )
        {
            if( !provenEdge( g, base, i ) )
            {
                out.push_back( g.implementors[ base ][ i ] );
            }
        }
    }
    std::ranges::sort( out );
    out.erase( std::ranges::unique( out ).begin(), out.end() );
    return out;
}
// Breadth-first up the proven edges from `cls`, each base once at its shallowest depth; `cls` itself is never listed.
inline std::vector<Ancestor> ancestorsOf( std::span<const std::pair<NodeId, NodeId>> parents, NodeId cls )
{
    std::vector<Ancestor> out;
    const auto            seen = [ & ]( NodeId id ) { return id == cls || std::ranges::any_of( out, [ id ]( const Ancestor& a ) { return a.id == id; } ); };
    const auto            expand = [ & ]( NodeId child, std::uint32_t depth )
    {
        const auto range = std::ranges::equal_range( parents, child, {}, []( const std::pair<NodeId, NodeId>& e ) { return e.first; } );
        for( const auto& edge : range )
        {
            if( !seen( edge.second ) )
            {
                out.push_back( Ancestor{ edge.second, depth } );
            }
        }
    };
    expand( cls, 1 );
    for( std::size_t i = 0; i < out.size(); ++i )   // out grows inside the loop: index, never iterate by reference
    {
        expand( out[i].id, out[i].depth + 1 );
    }
    return out;
}
// The classes at or below any of `roots`, over proven edges: the inheritance cone. One byte per symbol, so a membership test is one load.
inline std::vector<char> coneOf( std::span<const std::pair<NodeId, NodeId>> parents, std::size_t symbolCount, std::span<const NodeId> roots )
{
    std::vector<char> in( symbolCount, char( 0 ) );
    for( const NodeId r : roots )
    {
        in[r] = 1;
    }
    // edges sorted by child, so a downward walk is a fixpoint over them: a pass that marks nothing ends it
    for( bool grew = true; grew; )
    {
        grew = false;
        for( const auto& [ child, base ] : parents )
        {
            if( in[base] != 0 && in[child] == 0 )
            {
                in[child] = 1;
                grew      = true;
            }
        }
    }
    return in;
}

enum class SiteForm : std::uint8_t { Call, Ref, Getattr };
struct Site
{
    NodeId        caller  = kNoNode;
    std::uint32_t line    = 0;
    std::uint32_t depth   = 0;
    SiteForm      form    = SiteForm::Call;
    bool          viaCls  = false;
    bool          guarded = false;
    bool          test    = false;
};
// What a search for one method's sites found: the sites, and how many uses by spelling the parse did not prove (counted, never named).
struct SiteSet
{
    std::vector<Site> list;
    std::size_t       skipped = 0;
    // The files a use or a definition sat in that could not be read again (missing, unreadable, changed since the index): their uses are
    // in neither list nor skipped=, so the row says how many files it lost (a floor).
    std::vector<std::uint32_t> unread;   // may repeat a file: the row counts the distinct ones
    void noteUnread( std::uint32_t file ) { unread.push_back( file ); }
};

inline void orderSites( std::vector<Site>& sites, const IngestResult& ing )
{
    const auto key = [ & ]( const Site& s ) { return std::tuple( s.test, s.depth, ing.symbols[ s.caller ].fileId, s.line, s.form ); };
    std::ranges::sort( sites, [ & ]( const Site& a, const Site& b ) { return key( a ) < key( b ); } );
    const auto dup = std::ranges::unique( sites, [ & ]( const Site& a, const Site& b ) { return a.caller == b.caller && a.line == b.line && a.form == b.form; } );
    sites.erase( dup.begin(), dup.end() );
}
class Finder
{
public:
    Finder( const IngestResult& ing, const ClassIndex& classes, SourceReader& source ) : m_ing( ing ), m_classes( classes ), m_source( source ), m_verdict( ing.symbols.size(), 0 )
    {
        for( const Reference& r : ing.references )
        {
            if( isProbe( r ) )
            {
                m_probes.push_back( &r );
            }
        }
        std::ranges::stable_sort( m_probes, []( const Reference* a, const Reference* b ) { return std::pair( a->fromSymbol, a->startByte ) < std::pair( b->fromSymbol, b->startByte ); } );
    }

    SiteSet sitesOf( std::span<const Ancestor> bases, const FamilyRow& row, std::string_view name )
    {
        SiteSet out;
        for( const Reference& r : m_ing.references )
        {
            addRef( out, r, bases, row, name );
        }
        for( const Reference* p : m_probes )
        {
            addFetch( out, *p, bases, row, name );
        }
        orderSites( out.list, m_ing );
        return out;
    }
    // The base of `bases` that holds `member`, nullptr when it is another class's.
    const Ancestor* holderOf( std::span<const Ancestor> bases, const Symbol& member ) const
    {
        const NodeId owner = m_classes.ownerOf( member );
        const auto   match = [ owner ]( const Ancestor& a ) { return a.id == owner; };
        return std::ranges::any_of( bases, match ) ? &*std::ranges::find_if( bases, match ) : nullptr;
    }

private:
    // A bare call of the probe or the fetch: the Call references the index holds for them, whose arguments the parse reads.
    static bool isProbe( const Reference& r )
    {
        const FamilyRow* row = familyRow( r.lang );
        return row != nullptr && r.role == RefRole::Call && r.recv == RecvKind::None && !r.memberCall && r.qualifier.empty() && r.memberRoot.empty() && r.fromSymbol != kNoNode
               && ( r.calleeName == row->probe || r.calleeName == row->fetch );
    }
    // The caller is a method directly in its class whose receiver the parse proves (decided once per method).
    bool receiverOf( NodeId id, const FamilyRow& row, bool viaCls )
    {
        const Symbol& caller = m_ing.symbols[id];
        if( caller.fnLocal || !ReceiverEvidence::callableKind( caller.kind ) )
        {
            return false;
        }
        std::uint8_t& v = m_verdict[id];
        if( ( v & kDecided ) == 0 )
        {
            v = kDecided;
            if( const ParsedFile* file = m_source.parsed( caller.fileId ); file != nullptr )
            {
                const TSNode fn = functionOf( *file, caller );
                v |= receiverProven( *file, fn, row, false ) ? kSelfOk : 0;
                v |= receiverProven( *file, fn, row, true ) ? kClsOk : 0;
            }
        }
        return ( v & ( viaCls ? kClsOk : kSelfOk ) ) != 0;
    }
    // A probe or fetch of `name` on `recv` earlier in the same function (text order, not control flow).
    bool guardedBefore( NodeId caller, std::string_view recv, std::string_view name, std::uint32_t before )
    {
        const auto range = std::ranges::equal_range( m_probes, caller, {}, []( const Reference* p ) { return p->fromSymbol; } );
        for( const Reference* p : range )
        {
            const ParsedFile* file = p->startByte < before ? m_source.parsed( p->fileId ) : nullptr;
            if( file != nullptr && stringAttrCall( *file, p->startByte, p->calleeName, recv, name ) )
            {
                return true;
            }
        }
        return false;
    }
    void addRef( SiteSet& out, const Reference& r, std::span<const Ancestor> bases, const FamilyRow& row, std::string_view name )
    {
        if( r.fromSymbol == kNoNode || r.fromSymbol >= m_ing.symbols.size() || r.calleeName != name || r.lang != row.lang || r.isInherit
            || ( r.role != RefRole::Call && r.role != RefRole::Read ) )
        {
            return;
        }
        const bool throughSelf = r.recv == RecvKind::ThisObj;
        if( !throughSelf && !( r.recv == RecvKind::NamedVar && r.recvVar == row.classRecv ) )
        {
            return;
        }
        const Symbol&   caller = m_ing.symbols[ r.fromSymbol ];
        const Ancestor* holder = holderOf( bases, caller );
        if( holder == nullptr )
        {
            return;
        }
        if( r.role == RefRole::Read )
        {
            const ParsedFile* file = m_source.parsed( r.fileId );
            if( file != nullptr && bindsAttribute( *file, r.startByte ) )
            {
                return;   // a write through the receiver, not a use of the method
            }
        }
        if( !receiverOf( r.fromSymbol, row, !throughSelf ) )
        {
            if( m_source.parsed( caller.fileId ) == nullptr )
            {
                out.noteUnread( caller.fileId );   // no parse to decide on: not a receiver verdict
            }
            else
            {
                ++out.skipped;   // spelled like a site, not proven to be one
            }
            return;
        }
        out.list.push_back( Site{ r.fromSymbol, r.line, holder->depth, r.role == RefRole::Call ? SiteForm::Call : SiteForm::Ref, !throughSelf,
                                  guardedBefore( r.fromSymbol, throughSelf ? row.selfRecv : row.classRecv, name, r.startByte ), isTestSymbol( m_ing, r.fromSymbol ) } );
    }
    // A fetch by string is a Call reference of `getattr` whose arguments are the receiver and the name as a literal.
    void addFetch( SiteSet& out, const Reference& p, std::span<const Ancestor> bases, const FamilyRow& row, std::string_view name )
    {
        if( p.calleeName != row.fetch || p.fromSymbol >= m_ing.symbols.size() )
        {
            return;
        }
        const Ancestor* holder = holderOf( bases, m_ing.symbols[ p.fromSymbol ] );   // before any parse: only a base class's own functions are read
        if( holder == nullptr )
        {
            return;
        }
        const ParsedFile* file = m_source.parsed( p.fileId );
        if( file == nullptr )
        {
            out.noteUnread( p.fileId );   // a getattr in a base class that cannot be read: it may be a use of the name
            return;
        }
        if( !stringAttrCall( *file, p.startByte, row.fetch, row.selfRecv, name ) )
        {
            return;
        }
        if( !receiverOf( p.fromSymbol, row, false ) )
        {
            ++out.skipped;
            return;
        }
        out.list.push_back( Site{ p.fromSymbol, p.line, holder->depth, SiteForm::Getattr, false, true, isTestSymbol( m_ing, p.fromSymbol ) } );
    }

    static constexpr std::uint8_t kDecided = 1;
    static constexpr std::uint8_t kSelfOk  = 2;
    static constexpr std::uint8_t kClsOk   = 4;
    const IngestResult&           m_ing;
    const ClassIndex&             m_classes;
    SourceReader&                 m_source;
    std::vector<std::uint8_t>     m_verdict;   // per symbol: the bits above
    std::vector<const Reference*> m_probes;    // the probe/fetch calls, by caller then position
};

// A whole class in the served list carries its methods' text: the ones the task spells count as served, the rest are the class's bulk.
inline std::vector<NodeId> withTaskNamedMembers( const IngestResult& ing, const ClassIndex& classes, std::span<const NodeId> served, std::string_view task )
{
    std::vector<NodeId> out( served.begin(), served.end() );
    const auto          inTask = [ task ]( std::string_view name )
    {
        for( std::size_t at = task.find( name ); at != std::string_view::npos; at = task.find( name, at + 1 ) )
        {
            if( crossref::wholeWordAt( task, at, name.size() ) )
            {
                return true;
            }
        }
        return false;
    };
    const auto isServedClass = [ & ]( NodeId id ) { return id < ing.symbols.size() && ReceiverEvidence::classLike( ing.symbols[id].kind ) && familyRow( ing.symbols[id].lang ) != nullptr; };
    if( std::ranges::none_of( served, isServedClass ) )
    {
        return out;
    }
    for( NodeId id = 0; id < ing.symbols.size(); ++id )
    {
        const Symbol& s = ing.symbols[id];
        if( ReceiverEvidence::callableKind( s.kind ) && !s.fnLocal && familyRow( s.lang ) != nullptr && inTask( s.name ) )
        {
            const NodeId owner = classes.ownerOf( s );
            if( owner != kNoNode && std::ranges::find( served, owner ) != served.end() )
            {
                out.push_back( id );
            }
        }
    }
    return out;
}

}   // namespace selfhook_detail

struct SelfHookInputs
{
    const IngestResult& ing;
    const Graph&        g;
    std::string_view    rootArg;
    std::string_view    task;
};

namespace selfhook_detail
{
// The definitions of a method's name in its inheritance cone: never a namesake's. The base definitions (one per defining base class: the
// last one written in a class is the one it ends with, @overload and @property setters included) name the MRO's pick only when the inheritance
// edges prove it: a definition whose class derives from every other defining base. Otherwise they are the candidates.
struct ConeDefs
{
    std::size_t         defs     = 0;
    std::size_t         testDefs = 0;
    bool                hasBase  = false;
    NodeId              winner   = kNoNode;
    std::vector<NodeId> candidates;
};
inline ConeDefs coneDefsOf( const IngestResult& ing, const ClassIndex& classes, std::span<const std::pair<NodeId, NodeId>> parents, const Symbol& m, NodeId cls, std::span<const Ancestor> bases )
{
    std::vector<NodeId> roots{ cls };
    for( const Ancestor& a : bases )
    {
        roots.push_back( a.id );
    }
    const std::vector<char> cone = coneOf( parents, ing.symbols.size(), roots );
    struct BaseDef
    {
        NodeId        def;
        NodeId        owner;
        std::uint32_t depth;
    };
    std::vector<BaseDef> found;
    ConeDefs             out;
    for( NodeId d = 0; d < ing.symbols.size(); ++d )
    {
        const Symbol& def = ing.symbols[d];
        if( def.name != m.name || def.lang != m.lang || def.fnLocal || !ReceiverEvidence::callableKind( def.kind ) )
        {
            continue;
        }
        const NodeId owner = classes.ownerOf( def );
        if( owner == kNoNode || cone[ owner ] == 0 )
        {
            continue;
        }
        ++out.defs;
        out.testDefs += isTestSymbol( ing, d ) ? 1u : 0u;
        const auto base = std::ranges::find( bases, owner, &Ancestor::id );
        if( base == bases.end() )
        {
            continue;
        }
        const auto same = std::ranges::find( found, owner, &BaseDef::owner );
        if( same == found.end() )
        {
            found.push_back( BaseDef{ d, owner, base->depth } );
        }
        else if( def.sigStartByte > ing.symbols[ same->def ].sigStartByte )
        {
            same->def = d;
        }
    }
    out.hasBase = !found.empty();
    std::ranges::sort( found, [ & ]( const BaseDef& a, const BaseDef& b )
                       { return std::tuple( a.depth, ing.symbols[ a.def ].fileId, ing.symbols[ a.def ].sigStartByte ) < std::tuple( b.depth, ing.symbols[ b.def ].fileId, ing.symbols[ b.def ].sigStartByte ); } );
    for( const BaseDef& x : found )
    {
        const std::vector<Ancestor> above = ancestorsOf( parents, x.owner );
        const auto                  below = [ & ]( const BaseDef& y ) { return y.owner == x.owner || std::ranges::any_of( above, [ & ]( const Ancestor& a ) { return a.id == y.owner; } ); };
        if( std::ranges::all_of( found, below ) )
        {
            out.winner = x.def;
            return out;
        }
    }
    for( const BaseDef& x : found )
    {
        out.candidates.push_back( x.def );
    }
    return out;
}

// The one place this element escapes text: a free function, because `--callers=escapeXml` lists a METHOD caller as Class::name in the xml
// form and bare in the columnar one (columnarcheck's round trip reads that list on this very tree).
inline std::string_view xmlText( std::string_view text, std::vector<char>& buffer )
{
    return escapeXml( text, buffer );
}

// One answer's rendering state: the row writers read it, and it lives as long as the element.
struct RowWriter
{
    const IngestResult& ing;
    const MemberOwners& owners;
    std::string_view    rootArg;
    SourceReader&       source;
    std::vector<char>   esc;

    std::string placeOf( std::uint32_t fileId, std::uint32_t line )
    {
        const std::string_view rel = rootArg.empty() ? std::string_view( ing.files[ fileId ] ) : sarif::rootRelativeUri( ing.files[ fileId ], rootArg );
        return std::string( xmlText( rel, esc ) ) + ':' + std::to_string( line );
    }
    // Appends the override relation; returns the file of the overrides definition when it could not be read (abstract= is then unknown), else kNoFile.
    std::uint32_t relation( std::string& x, const ConeDefs& d, const FamilyRow& row )
    {
        if( !d.hasBase )
        {
            x += " hook=\"1\"";
            return kNoFile;
        }
        if( d.winner == kNoNode )
        {
            x += " candidates=\"";
            std::string names;
            for( const NodeId c : std::span( d.candidates ).first( std::min( d.candidates.size(), kForSelfHookCandidateRows ) ) )
            {
                names += names.empty() ? "" : ",";
                names += qualifiedMemberName( owners, ing.symbols[c] );
            }
            x += xmlText( names, esc );
            x += '"';
            return kNoFile;
        }
        const Symbol& base = ing.symbols[ d.winner ];
        x += " overrides=\"";
        x += xmlText( qualifiedMemberName( owners, base ), esc );
        x += "\" op=\"" + placeOf( base.fileId, base.line ) + '"';
        const ParsedFile* file = source.parsed( base.fileId );
        if( file == nullptr )
        {
            return base.fileId;
        }
        if( isAbstractDef( *file, functionOf( *file, base ), row ) )
        {
            x += " abstract=\"1\"";
        }
        return kNoFile;
    }
    void siteRow( std::string& x, const Site& site )
    {
        const Symbol& caller = ing.symbols[ site.caller ];
        x += "<s n=\"";
        x += xmlText( qualifiedMemberName( owners, caller ), esc );
        x += "\" p=\"" + placeOf( caller.fileId, site.line ) + '"';
        if( site.test )
        {
            x += " test=\"1\"";
        }
        if( site.viaCls )
        {
            x += " recv=\"cls\"";
        }
        if( site.form != SiteForm::Call )
        {
            x += site.form == SiteForm::Ref ? " form=\"ref\"" : " form=\"getattr\"";
        }
        if( site.guarded )
        {
            x += " guarded=\"1\"";
        }
        x += "/>";
    }
    void method( std::string& x, const Symbol& m, const ConeDefs& d, const FamilyRow& row, const SiteSet& found )
    {
        const std::vector<Site>& sites    = found.list;
        const std::size_t        siteRows = std::min( sites.size(), kForSelfHookSiteRows );
        const std::string        qual( qualifiedMemberName( owners, m ) );
        x += "<selfhook n=\"";
        x += xmlText( qual, esc );
        x += "\" p=\"" + placeOf( m.fileId, m.line ) + '"';
        std::vector<std::uint32_t> unread = found.unread;
        if( const std::uint32_t lost = relation( x, d, row ); lost != kNoFile )
        {
            unread.push_back( lost );
        }
        std::ranges::sort( unread );
        unread.erase( std::ranges::unique( unread ).begin(), unread.end() );
        x += " defs=\"" + std::to_string( d.defs ) + '"';
        if( d.testDefs > 0 )
        {
            x += " test=\"" + std::to_string( d.testDefs ) + '"';
        }
        x += " sites=\"" + std::to_string( sites.size() ) + "\" shown=\"" + std::to_string( siteRows ) + "\" capped=\"" + ( siteRows < sites.size() ? "1" : "0" ) + '"';
        if( siteRows < sites.size() )
        {
            // a verb that returns the rest: an override's edge is proven to the base's definition, so the sites sit under THAT name
            x += nextAttrXml( d.winner != kNoNode ? nextFlag( "--callers=", qualifiedMemberName( owners, ing.symbols[ d.winner ] ) ) : nextFlag( "--uses=", m.name ) );
        }
        if( found.skipped > 0 )
        {
            x += " skipped=\"" + std::to_string( found.skipped ) + '"';
        }
        if( !unread.empty() )
        {
            x += " unread=\"" + std::to_string( unread.size() ) + '"';
        }
        x += '>';
        for( const Site& site : std::span( sites ).first( siteRows ) )
        {
            siteRow( x, site );
        }
        x += "</selfhook>";
    }
};
}   // namespace selfhook_detail

// The element for `served`, "" when no served method qualifies (see WHEN above). A method served twice counts once. `held`: a token budget is
// set, so only the marker `<selfhooks held="budget" total=N/>` (the count, no rows) is returned, "" when the count is 0.
inline std::string renderForSelfHooks( const SelfHookInputs& in, std::span<const NodeId> served, bool held = false )
{
    using namespace selfhook_detail;
    const IngestResult& ing = in.ing;
    if( std::ranges::none_of( served, [ & ]( NodeId id ) { return id < ing.symbols.size() && familyRow( ing.symbols[id].lang ) != nullptr; } ) )
    {
        return {};
    }
    const ClassIndex   classes( ing );
    const auto         parents = provenParents( ing, in.g );
    const auto         partial = classesWithUnprovenBase( in.g );
    const MemberOwners owners( ing );
    SourceReader       source( ing );
    Finder             finder( ing, classes, source );
    RowWriter          writer{ ing, owners, in.rootArg, source, {} };

    std::vector<NodeId> seen;
    std::string         rows;
    std::size_t         total = 0;
    std::size_t         shown = 0;
    for( const NodeId id : withTaskNamedMembers( ing, classes, served, in.task ) )
    {
        if( id >= ing.symbols.size() || std::ranges::find( seen, id ) != seen.end() )
        {
            continue;
        }
        seen.push_back( id );
        const Symbol&    m   = ing.symbols[id];
        const FamilyRow* row = familyRow( m.lang );
        if( row == nullptr || !ReceiverEvidence::callableKind( m.kind ) || m.fnLocal || isTestSymbol( ing, id ) )
        {
            continue;
        }
        const NodeId                cls   = classes.ownerOf( m );
        const std::vector<Ancestor> bases = cls == kNoNode ? std::vector<Ancestor>{} : ancestorsOf( parents, cls );
        if( bases.empty() )
        {
            continue;
        }
        // an unproven (by-name) base of cls or of an ancestor may define the name ahead of a proven one: the walk is short, stay silent
        const auto unproven = [ & ]( NodeId c ) { return std::ranges::binary_search( partial, c ); };
        if( unproven( cls ) || std::ranges::any_of( bases, [ & ]( const Ancestor& a ) { return unproven( a.id ); } ) )
        {
            continue;
        }
        const SiteSet sites = finder.sitesOf( bases, *row, m.name );
        if( sites.list.empty() )
        {
            continue;
        }
        const ConeDefs defs = coneDefsOf( ing, classes, parents, m, cls, bases );
        if( defs.defs < 2 )
        {
            continue;   // no override relation: the caller hop's question, not this one
        }
        ++total;
        if( !held && shown < kForSelfHookMethodRows )
        {
            ++shown;
            writer.method( rows, m, defs, *row, sites );
        }
    }
    if( held )
    {
        return total == 0 ? std::string() : "<selfhooks held=\"budget\" total=\"" + std::to_string( total ) + "\"/>";
    }
    if( rows.empty() )
    {
        return {};
    }
    return "<selfhooks total=\"" + std::to_string( total ) + "\" shown=\"" + std::to_string( shown ) + "\" capped=\"" + ( shown < total ? "1" : "0" ) + "\">" + rows + "</selfhooks>";
}

}   // namespace rw
