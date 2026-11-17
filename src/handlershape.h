#pragma once
#if !defined( RIPWIRE_INGEST_TU )
#error "handlershape.h is a SECTION of src/ingest.cpp's translation unit - include it only from ingest.cpp (see the ingest-family split note there)"
#endif

// handlershape.h — two structural shape families read off ONE parsed tree, for --quality-delta:
//
//   ERROR-MASKING, widened (kind error-masking; the empty/pass/comment-only rows stay in lintrules.h's
//   kErrorMaskRules query table):
//     log-only      a handler whose body is ONLY logging/print calls and never names the caught error —
//                   log-and-continue, the message survives and the error does not. Broad handlers only
//                   (one that catches everything, or the language's root error type): a narrow
//                   `except FileNotFoundError: print("no config, using defaults")` states its cause in its
//                   own type, and counting it would be the false positive this shape cannot afford.
//     rethrow-only  the ONLY handler of its try re-throws the error it caught, unchanged — a try/catch
//                   that does nothing. Sole handler, because `catch( Specific e ) { throw e; }` ahead of a
//                   `catch( Exception e )` sibling is the idiom that routes one type PAST the broad
//                   handler, and that is not redundant.
//     failure-default  a read, parse or spawn failure returned as an empty success (TypeScript catch / .catch,
//                   C++ value_or on a read); REPORT-ONLY in every language — see its section below.
//   PLACEHOLDER (kind placeholder):
//     stub          raise NotImplementedError, todo!()/unimplemented!(), Kotlin TODO(), throw new
//                   NotImplementedException(), and any throw/raise/panic/fatalError/assert whose string
//                   says "not implemented" / "unimplemented" / "implement me" / TODO.
//     todo          a comment LINE that starts with TODO or FIXME and names no issue (#123, ABC-123, a URL).
//
// WHY A WALK AND NOT A QUERY. Each shape is a question about ALL of a block's statements ("every statement
// is a log call") or about a name NOT occurring below a node ("the caught identifier is never read"), and
// a tree-sitter pattern can state neither. It rides the same read, parse and newline index as the query
// groups (AstWalk::HandlerShapes), so it costs a traversal, never a second parse.
//
// PRECISION BEFORE RECALL, by construction: every test below answers "not this shape" when it cannot
// decide — an unrecognised callee is not a log call, a destructured catch binding is not judged, a name
// inside a string counts as a reference. Each of those is a miss, never a finding.
// Measured precision per shape and language is in docs/EVALS.md ("error-masking widened"); the table
// kHandlerShapeGates in lintrules.h decides which shapes gate.

#include <algorithm>
#include <cctype>
#include <cstdint>
#include <cstring>
#include <iterator>
#include <string>
#include <utility>
#include <string_view>
#include <vector>

#include <tree_sitter/api.h>

#include "infra/Diagnostics.h"   // ASSUME
#include "infra/nodekind.h"      // kindIs
#include "infra/strkern.h"       // strkern::lowerFoldAscii — the ONE ASCII case fold
#include "infra/tablelookup.h"   // findByField
#include "infra/tschildren.h"
#include "infra/tsparent.h"     // ancestorWhere / ancestorOfKind / rootOf — the failure-default readers climb with them
#include "ingest.h"              // the five kShape* tags, Lang

namespace rw::hshape
{


struct ShapeSpan
{
    std::uint32_t    startByte = 0;
    std::uint32_t    endByte   = 0;
    std::string_view tag;   // one of the five kShape* tags (ingest.h) — static storage, never a view into the file
};

// ── small readers ─────────────────────────────────────────────────────────────────────────────────────

// Every reader below is NULL-SAFE, because tree-sitter's are not: ts_node_end_byte and
// ts_node_child_by_field_name dereference the node's subtree/tree, so a missing optional field (a catch
// with no parameter, a raise with no argument) handed to either crashes the walk. Text is read with
// ingest_metrics.h's nodeTextOf, which is null-safe the same way.
inline TSNode namedChild( TSNode n, std::uint32_t index ) noexcept
{
    return ( ts_node_is_null( n ) || index >= ts_node_named_child_count( n ) ) ? TSNode{} : ts_node_named_child( n, index );
}

inline std::uint32_t namedCount( TSNode n ) noexcept
{
    return ts_node_is_null( n ) ? 0u : ts_node_named_child_count( n );
}

// A null node's type is the empty string, so kindIs answers false for it rather than crashing.
inline const char* typeOf( TSNode n ) noexcept
{
    return ts_node_is_null( n ) ? "" : ts_node_type( n );
}

template< std::size_t N >
inline bool typeIs( TSNode n, const char ( &kind )[N] ) noexcept
{
    return kindIs( typeOf( n ), kind );
}

// Is n's type one of `kinds`? A null node's type is "", which no table spells.
template< std::size_t N >
inline bool typeIsOneOf( TSNode n, const char* const ( &kinds )[N] ) noexcept
{
    const char* t = typeOf( n );
    return std::any_of( std::begin( kinds ), std::end( kinds ), [ t ]( const char* k ) { return std::strcmp( t, k ) == 0; } );
}

inline bool isCommentNode( TSNode n ) noexcept
{
    return std::strstr( ts_node_type( n ), "comment" ) != nullptr;
}

inline TSNode field( TSNode n, const char* name ) noexcept
{
    if( ts_node_is_null( n ) )
    {
        return n;
    }
    return ts_node_child_by_field_name( n, name, static_cast<std::uint32_t>( std::strlen( name ) ) );
}

// The named, non-comment children of a statement container — the statements a shape judges. A comment
// is not a statement: `catch( e ) { // retry later <NL> log.warn( "x" ) }` is still log-only.
inline void statementsOf( TSNode body, std::vector<TSNode>& out )
{
    out.clear();
    if( ts_node_is_null( body ) )
    {
        return;
    }
    ChildCursor cursor( body );
    forEachNamedChild( body, cursor.cur, [ & ]( TSNode c )
    {
        if( !isCommentNode( c ) )
        {
            out.push_back( c );
        }
        return true;
    } );
}

// How deep mentionsName reads below the node it is handed — the handler walk's own pathological-depth bound
// (walkHandlerShapes' frame.depth > 512).
inline constexpr int kMentionsNameMaxDepth = 512;   // undisclosed: a deeper subtree answers "mentions it", so a log-only handler that deep is never flagged

// Does `pred( node, depth )` accept n or a named node below it (depth 0 is n)? A node with named children met at
// kMentionsNameMaxDepth levels down is not opened: the walk answers `deepAnswers` there. An explicit stack, like
// walkHandlerShapes: a recursive walk 512 levels deep overflowed a 512 KiB worker-thread stack under AddressSanitizer's
// larger frames. A null n answers false.
template< class Pred >
inline bool anyNamedNodeBelow( TSNode n, bool deepAnswers, const Pred& pred )
{
    struct Frame { TSNode node; int depth; };
    std::vector<Frame> stack;
    if( !ts_node_is_null( n ) )
    {
        stack.push_back( { n, 0 } );
    }
    while( !stack.empty() )
    {
        const Frame frame = stack.back();
        stack.pop_back();
        if( pred( frame.node, frame.depth ) )
        {
            return true;
        }
        if( ts_node_named_child_count( frame.node ) == 0 )
        {
            continue;
        }
        if( frame.depth >= kMentionsNameMaxDepth )
        {
            if( deepAnswers )
            {
                return true;
            }
            continue;
        }
        ChildCursor cursor( frame.node );
        forEachNamedChild( frame.node, cursor.cur, [ & ]( TSNode c )
        {
            stack.push_back( { c, frame.depth + 1 } );
            return true;
        } );
    }
    return false;
}

// mentionsName's walk: true when a named leaf below n spells `name`, OR when it meets a node with named children at
// kMentionsNameMaxDepth levels down — a subtree too deep to read answers "mentions it", which excludes the handler from
// log-only: a miss, never a finding.
inline bool mentionsNameBelow( TSNode n, std::string_view src, std::string_view name )
{
    return anyNamedNodeBelow( n, true, [ & ]( TSNode c, int depth )
                              { return depth > 0 && ts_node_named_child_count( c ) == 0 && nodeTextOf( c, src ) == name; } );
}

// Does any NAMED LEAF below n spell `name`? Identifiers in every grammar are leaves, so this reads an
// f-string's `{e}`, a template's `${e}`, a Kotlin `"$e"` and a plain argument alike. A leaf inside a string
// literal that happens to equal the name also answers yes — a miss, never a finding. Bounded at
// kMentionsNameMaxDepth levels; deeper than that also answers yes (mentionsNameBelow).
inline bool mentionsName( TSNode n, std::string_view src, std::string_view name )
{
    if( name.empty() )
    {
        return false;
    }
    if( namedCount( n ) == 0 )
    {
        return !ts_node_is_null( n ) && ts_node_is_named( n ) && nodeTextOf( n, src ) == name;
    }
    return mentionsNameBelow( n, src, name );
}

// The spellings that carry the CURRENT error without naming the caught identifier: Python's
// `exc_info=True` / `stack_info=` / `sys.exc_info()` / `traceback.format_exc()`, and Ruby's `$!`. A log
// call that passes one of them logs the error, so the handler is not log-only.
inline constexpr std::string_view kErrorCarriers[] = { "exc_info", "stack_info", "traceback", "format_exc", "print_exc", "$!", "$ERROR_INFO" };

inline bool mentionsError( TSNode body, std::string_view src, std::string_view name )
{
    if( mentionsName( body, src, name ) )
    {
        return true;
    }
    for( std::string_view carrier : kErrorCarriers )
    {
        if( mentionsName( body, src, carrier ) )
        {
            return true;
        }
    }
    return false;
}

// ── the handler, read per grammar ─────────────────────────────────────────────────────────────────────

struct Handler
{
    TSNode           body     = {};   // the statement container; null = no body at all
    std::string_view name;            // the caught identifier; empty = none bound
    bool             broad    = false;// catches everything, or the language's root error type
    bool             sole     = false;// the only handler its try has
    bool             filtered = false;// a C# `when` filter — the handler is conditional, never judged
};

// How many siblings of n (n included) share n's node type — "is this the only catch of its try".
inline std::uint32_t siblingsOfSameType( TSNode n )
{
    const TSNode parent = ts_node_parent( n );
    if( ts_node_is_null( parent ) )
    {
        return 1;
    }
    std::uint32_t count = 0;
    const char*   type  = ts_node_type( n );
    ChildCursor   cursor( parent );
    forEachNamedChild( parent, cursor.cur, [ & ]( TSNode c ) { count += std::strcmp( ts_node_type( c ), type ) == 0 ? 1u : 0u; return true; } );
    return count;
}

// The root error types a "broad" handler may name, across the grammars below. A qualified spelling is
// judged by its last segment (java.lang.Exception, System.Exception, ::std::exception).
inline bool isRootErrorType( std::string_view t ) noexcept
{
    const std::size_t cut = t.find_last_of( ".:" );
    if( cut != std::string_view::npos )
    {
        t = t.substr( cut + 1 );
    }
    return t == "Exception" || t == "BaseException" || t == "Throwable" || t == "RuntimeException" || t == "StandardError"
        || t == "exception";
}

inline void readPythonHandler( TSNode n, std::string_view src, Handler& h )
{
    const TSNode value = field( n, "value" );
    TSNode       type  = value;
    if( typeIs( value, "as_pattern" ) )
    {
        type                = namedChild( value, 0 );
        const TSNode target = field( value, "alias" );
        const TSNode ident  = namedChild( target, 0 );
        h.name              = typeIs( ident, "identifier" ) ? nodeTextOf( ident, src ) : std::string_view();
    }
    h.broad = ts_node_is_null( type ) || ( ( typeIs( type, "identifier" ) || typeIs( type, "attribute" ) ) && isRootErrorType( nodeTextOf( type, src ) ) );
    h.body  = firstChildOfKind( n, true, { "block" } );
    const TSNode tryNode = ts_node_parent( n );
    h.sole  = siblingsOfSameType( n ) == 1 && ( ts_node_is_null( tryNode ) || ts_node_is_null( firstChildOfKind( tryNode, true, { "except_group_clause" } ) ) );
}

inline void readJavaScriptHandler( TSNode n, std::string_view src, Handler& h )
{
    const TSNode param = field( n, "parameter" );
    h.name  = typeIs( param, "identifier" ) ? nodeTextOf( param, src ) : std::string_view();
    h.broad = ts_node_is_null( param ) || typeIs( param, "identifier" );   // a JS catch catches everything; a destructured one is not judged
    h.body  = field( n, "body" );
    h.sole  = true;                                                        // a JS try has at most one catch
}

inline void readJavaHandler( TSNode n, std::string_view src, Handler& h )
{
    const TSNode param = firstChildOfKind( n, true, { "catch_formal_parameter" } );
    if( ts_node_is_null( param ) )
    {
        return;
    }
    const TSNode name  = field( param, "name" );
    const TSNode types = firstChildOfKind( param, true, { "catch_type" } );
    h.name  = nodeTextOf( name, src );
    h.broad = namedCount( types ) == 1 && isRootErrorType( nodeTextOf( types, src ) );
    h.body  = field( n, "body" );
    h.sole  = siblingsOfSameType( n ) == 1;
}

inline void readCSharpHandler( TSNode n, std::string_view src, Handler& h )
{
    const TSNode decl = firstChildOfKind( n, true, { "catch_declaration" } );
    h.filtered        = !ts_node_is_null( firstChildOfKind( n, true, { "catch_filter_clause" } ) );
    h.name            = ts_node_is_null( decl ) ? std::string_view() : nodeTextOf( field( decl, "name" ), src );
    h.broad           = ts_node_is_null( decl ) || isRootErrorType( nodeTextOf( field( decl, "type" ), src ) );
    h.body            = field( n, "body" );
    h.sole            = siblingsOfSameType( n ) == 1;
}

inline void readKotlinHandler( TSNode n, std::string_view src, Handler& h )
{
    const TSNode ident = firstChildOfKind( n, true, { "simple_identifier" } );
    const TSNode type  = firstChildOfKind( n, true, { "user_type" } );
    h.name  = nodeTextOf( ident, src );
    h.broad = !ts_node_is_null( type ) && isRootErrorType( nodeTextOf( type, src ) );
    h.body  = firstChildOfKind( n, true, { "statements" } );
    h.sole  = siblingsOfSameType( n ) == 1;
}

inline void readRubyHandler( TSNode n, std::string_view src, Handler& h )
{
    const TSNode exceptions = field( n, "exceptions" );
    const TSNode variable   = field( n, "variable" );
    const TSNode ident      = namedChild( variable, 0 );
    h.name  = typeIs( ident, "identifier" ) ? nodeTextOf( ident, src ) : std::string_view();
    h.broad = ts_node_is_null( exceptions )
           || ( namedCount( exceptions ) == 1 && isRootErrorType( nodeTextOf( namedChild( exceptions, 0 ), src ) ) );
    h.body  = field( n, "body" );
    h.sole  = siblingsOfSameType( n ) == 1;
}

inline void readCppHandler( TSNode n, std::string_view src, Handler& h )
{
    const TSNode params = field( n, "parameters" );
    const TSNode decl   = namedChild( params, 0 );
    if( !ts_node_is_null( decl ) )
    {
        TSNode d = field( decl, "declarator" );
        while( !typeIs( d, "identifier" ) && namedCount( d ) > 0 )
        {
            d = namedChild( d, namedCount( d ) - 1 );   // & / && / * wrappers carry the name last
        }
        h.name = typeIs( d, "identifier" ) ? nodeTextOf( d, src ) : std::string_view();
    }
    h.broad = ts_node_is_null( decl );   // catch( ... ): C++ has no root error type every throw derives from
    h.body  = field( n, "body" );
    h.sole  = siblingsOfSameType( n ) == 1;
}

// One row per grammar: which node is a handler there, and who reads it. A grammar absent from the table has
// no handler shape (Go's `if err != nil` and Rust's `Err(..)` arm are their own readers below; Swift and the rest are
// not judged).
struct HandlerReader
{
    Lang        lang;
    const char* nodeType;
    void ( *read )( TSNode, std::string_view, Handler& );
};

inline constexpr HandlerReader kHandlerReaders[] = {
    { Lang::Python,     "except_clause", readPythonHandler     },
    { Lang::JavaScript, "catch_clause",  readJavaScriptHandler },
    { Lang::TypeScript, "catch_clause",  readJavaScriptHandler },
    { Lang::Java,       "catch_clause",  readJavaHandler       },
    { Lang::CSharp,     "catch_clause",  readCSharpHandler     },
    { Lang::Kotlin,     "catch_block",   readKotlinHandler     },
    { Lang::Ruby,       "rescue",        readRubyHandler       },
    { Lang::Cpp,        "catch_clause",  readCppHandler        },
};

// ── what a statement IS ───────────────────────────────────────────────────────────────────────────────

// Unwrap every layer of `kind` that holds exactly one named child: an expression_statement to its expression, a
// parenthesized expression to what it holds.
template< std::size_t N >
inline TSNode unwrapSole( TSNode n, const char ( &kind )[N] ) noexcept
{
    while( typeIs( n, kind ) && namedCount( n ) == 1 )
    {
        n = namedChild( n, 0 );
    }
    return n;
}

// Unwrap a statement to the expression it evaluates (expression_statement → its one child).
inline TSNode statementExpression( TSNode s ) noexcept
{
    return unwrapSole( s, "expression_statement" );
}

// Python/Ruby, JS/TS/Go/Kotlin/C++/Rust/Swift, Java, C#.
inline constexpr const char* kCallNodeTypes[] = { "call", "call_expression", "method_invocation", "invocation_expression" };

inline bool isCallNode( TSNode n ) noexcept
{
    return typeIsOneOf( n, kCallNodeTypes );
}

// The callee of a call, as source text: `print`, `logger.warning`, `console.error`, `System.out.println`,
// `log.Printf`. Java's and Ruby's calls keep the receiver in its own field, so it is joined back on.
inline std::string_view calleeText( TSNode call, std::string_view src, std::string_view& receiverOut ) noexcept
{
    receiverOut = {};
    if( typeIs( call, "method_invocation" ) )
    {
        receiverOut = nodeTextOf( field( call, "object" ), src );
        return nodeTextOf( field( call, "name" ), src );
    }
    if( typeIs( call, "call" ) && !ts_node_is_null( field( call, "method" ) ) )   // Ruby
    {
        receiverOut = nodeTextOf( field( call, "receiver" ), src );
        return nodeTextOf( field( call, "method" ), src );
    }
    TSNode fn = field( call, "function" );
    if( ts_node_is_null( fn ) )
    {
        fn = namedChild( call, 0 );   // Kotlin: the callee is the first child, no field
    }
    const std::string_view text = nodeTextOf( fn, src );
    const std::size_t      dot  = text.find_last_of( '.' );
    if( dot == std::string_view::npos )
    {
        return text;
    }
    receiverOut = text.substr( 0, dot );
    return text.substr( dot + 1 );
}

// An ASCII-lower-cased copy, for the case-insensitive vocabulary tests below (every needle is lower case).
// Spelled as size-then-copy: the copy-construct-then-mutate spelling is token-identical to unrelated
// string builders (oswin::powerShellPathPrependHint), which --quality-delta's duplication kind reads as a
// clone of a reused helper — the false-positive class infra/dirwalk.h's banner documents.
inline std::string lowerCopy( std::string_view s )
{
    std::string folded( s.size(), '\0' );
    std::copy( s.begin(), s.end(), folded.begin() );
    strkern::lowerFoldAscii( folded.data(), folded.size() );
    return folded;
}

// How many of the (lower-case) `needles` occur in `hay`, case-insensitively. A COUNT rather than the one-line
// any_of-over-find, because that exact shape structurally matches several unrelated substring checks in the
// tree under --quality-delta's duplication kind (the class infra/dirwalk.h's banner documents).
template< std::size_t N >
inline std::size_t countPhrases( std::string_view hay, const std::string_view ( &needles )[N] )
{
    const std::string lowered = lowerCopy( hay );
    std::size_t       found   = 0;
    for( const std::string_view w : needles )
    {
        found += ( lowered.find( w ) != std::string::npos ) ? 1u : 0u;
    }
    return found;
}

// Does a new word start at seg[i]? A lower-to-upper camelCase step (appLogger), an acronym-to-word step (the L of
// HTTPLogger: upper after upper, lower after it) or a letter-to-digit step (logger2). seg[i - 1] is alphanumeric.
inline bool isWordStepAt( std::string_view seg, std::size_t i ) noexcept
{
    const auto up = [ & ]( std::size_t k ) noexcept { return std::isupper( (unsigned char)seg[k] ) != 0; };
    if( std::isdigit( (unsigned char)seg[i] ) )
    {
        return std::isalpha( (unsigned char)seg[i - 1] ) != 0;
    }
    if( !up( i ) )
    {
        return false;
    }
    return std::islower( (unsigned char)seg[i - 1] ) || ( up( i - 1 ) && i + 1 < seg.size() && std::islower( (unsigned char)seg[i + 1] ) );
}

// The first and last WORD of an identifier segment. Words split on every non-alphanumeric byte (`@logger`, `#logger`,
// `$logger`, audit_log, log-sink) and at isWordStepAt: audit_log -> (audit, log), appLogger -> (app, Logger),
// HTTPLogger -> (HTTP, Logger), logger2 -> (logger, 2), LOG -> (LOG, LOG). Empty views when it has no word.
inline std::pair<std::string_view, std::string_view> edgeWordsOf( std::string_view seg )
{
    std::string_view first;
    std::string_view last;
    std::size_t      wordBegin = 0;
    for( std::size_t i = 0; i <= seg.size(); ++i )
    {
        const bool atSep  = i == seg.size() || !std::isalnum( (unsigned char)seg[i] );
        const bool atStep = !atSep && i > wordBegin && isWordStepAt( seg, i );
        if( ( atSep || atStep ) && i > wordBegin )
        {
            last  = seg.substr( wordBegin, i - wordBegin );
            first = first.empty() ? last : first;
        }
        wordBegin = atSep ? i + 1 : ( atStep ? i : wordBegin );
    }
    return { first, last };
}

// `logging.getLogger(__name__)` -> `logging.getLogger`: trailing balanced call argument lists come off BEFORE the last
// `.` segment is taken, since an argument may hold dots of its own (`getLogger('a.b')`). One forward pass; a paren inside
// a quoted argument (`getLogger("svc.worker)")`, `getStore("logger(")`) is text, not a delimiter, and an escape inside a
// string skips the next byte. Unbalanced or an unterminated string: left as it is.
inline std::string_view withoutTrailingCalls( std::string_view recv ) noexcept
{
    int         depth    = 0;
    char        quote    = 0;
    std::size_t openAt   = 0;
    std::size_t runStart = std::string_view::npos;   // where the run of call groups that ends recv starts
    for( std::size_t i = 0; i < recv.size(); ++i )
    {
        const char c = recv[i];
        if( quote != 0 )
        {
            i += c == '\\' ? 1 : 0;
            quote = c == quote ? 0 : quote;
            continue;
        }
        if( c == ')' && depth == 0 )
        {
            return recv;
        }
        quote    = ( c == '"' || c == '\'' || c == '`' ) ? c : 0;
        openAt   = ( c == '(' && depth == 0 ) ? i : openAt;
        depth   += c == '(' ? 1 : ( c == ')' ? -1 : 0 );
        runStart = ( c == ')' && depth == 0 ) ? std::min( runStart, openAt ) : ( depth == 0 && c != ')' ? std::string_view::npos : runStart );
    }
    return ( quote != 0 || depth != 0 || runStart == std::string_view::npos ) ? recv : recv.substr( 0, runStart );
}

// One WORD that says log: log / logger / logging; a logger package spelled as one word (structlog, logfire, logbook,
// loguru); or log / logger / logging behind a ONE- or TWO-letter prefix (vlog, mylog, clog, mylogger). A longer prefix
// is an English word that ends in "log" and logs nothing (catalog, dialog, backlog, analog, changelog), and so is blog.
inline bool isLogWord( std::string_view word )
{
    constexpr std::string_view kLogWords[]    = { "log", "logger", "logging" };
    constexpr std::string_view kLogPackages[] = { "structlog", "logfire", "logbook", "loguru" };
    const std::string          lowered        = lowerCopy( word );
    const auto in = [ & ]( const auto& table ) { return std::find( std::begin( table ), std::end( table ), lowered ) != std::end( table ); };
    if( in( kLogWords ) || in( kLogPackages ) )
    {
        return true;
    }
    for( const std::string_view suffix : kLogWords )
    {
        const std::size_t prefix = lowered.size() - std::min( lowered.size(), suffix.size() );
        if( lowered.ends_with( suffix ) && prefix >= 1 && prefix <= 2 && lowered.compare( 0, prefix, "b" ) != 0 )
        {
            return std::all_of( lowered.begin(), lowered.begin() + std::ptrdiff_t( prefix ), []( char ch ) { return std::isalpha( (unsigned char)ch ) != 0; } );
        }
    }
    return false;
}

// A logging receiver: anything whose LAST segment (after trailing calls come off) has a first or last WORD that says
// log (isLogWord) — logger, log, LOG, logging, _log, audit_log, appLogger, HTTPLogger, logger2, @logger, this.#logger,
// self.logger, Rails.logger, logging.getLogger(__name__), get_logger(), mylog — a known logger package (slog, glog, klog,
// logrus, zerolog, syslog), or one of the console/stream spellings every grammar here uses for print-to-a-reader. A
// WORD, never a substring: catalog, dialog, backlog, analog, changelog and technology contain "log" and log nothing, and
// a Python log-only row gates — precision first, so a logger spelled some other way is a miss, never a false gate.
inline bool isLogReceiver( std::string_view recv )
{
    const std::string_view bare = withoutTrailingCalls( recv );
    const std::size_t      dot  = bare.find_last_of( '.' );
    const std::string_view last = ( dot == std::string_view::npos ) ? bare : bare.substr( dot + 1 );
    constexpr std::string_view kStreamReceivers[] = { "console", "out", "err", "stderr", "stdout", "warnings", "fmt", "debug", "trace",
                                                      "slog", "glog", "klog", "logrus", "zerolog", "syslog" };
    const std::string lowered = lowerCopy( last );
    if( std::find( std::begin( kStreamReceivers ), std::end( kStreamReceivers ), lowered ) != std::end( kStreamReceivers ) )
    {
        return true;
    }
    const auto [ firstWord, lastWord ] = edgeWordsOf( last );
    return ( !firstWord.empty() && isLogWord( firstWord ) ) || ( !lastWord.empty() && isLogWord( lastWord ) );
}

// The verbs a logging call ends in. `exception` is deliberately ABSENT (Python's logger.exception writes
// the traceback — it logs the error), and so are fatal/Fatal*/panic/Panic* (they end the program, which is
// not continuing past the error).
inline constexpr std::string_view kLogVerbs[] = {
    "debug", "info", "warn", "warning", "error", "critical", "log", "trace", "verbose", "notice", "severe", "fine",
    "print", "println", "printf", "write", "writeln", "writeline", "debugf", "infof", "warnf", "warningf", "errorf",
};

inline constexpr std::string_view kBarePrintCalls[] = { "print", "println", "printf", "puts", "warn", "eprint", "eprintln", "p" };

// C's print-to-a-stream calls, logging only when the stream is stderr: `fprintf( stderr, … )`, `fputs( "…", stderr )`.
// A file handle is output, not a log, so `fprintf( fp, … )` answers no.
inline constexpr std::string_view kStreamPrintCalls[] = { "fprintf", "fputs", "vfprintf", "fputc", "putc" };

inline bool isStderrPrintCall( TSNode call, std::string_view verb, std::string_view src )
{
    verb = verb.starts_with( "std::" ) ? verb.substr( 5 ) : verb;
    if( std::find( std::begin( kStreamPrintCalls ), std::end( kStreamPrintCalls ), verb ) == std::end( kStreamPrintCalls ) )
    {
        return false;
    }
    // the STREAM argument only: fprintf/vfprintf take it first, fputs/fputc/putc second (`fprintf( fp, "%p", stderr )` writes to
    // fp); a comment is a named child too, so it is skipped, never counted as a position (CodeRabbit #636)
    const std::uint32_t streamPos = ( verb == "fprintf" || verb == "vfprintf" ) ? 0u : 1u;
    const TSNode        args      = field( call, "arguments" );
    std::uint32_t       pos       = 0;
    for( std::uint32_t i = 0; i < namedCount( args ); ++i )
    {
        const TSNode a = namedChild( args, i );
        if( typeIs( a, "comment" ) )
        {
            continue;
        }
        if( pos++ == streamPos )
        {
            return nodeTextOf( a, src ) == "stderr";
        }
    }
    return false;
}

// C++ stream logging, K6L-CXX: a `<<` chain whose LEFTMOST operand is a console stream (`std::cerr << "x" << std::endl`)
// or a logging macro call (`LOG( ERROR ) << "x"`, `VLOG( 1 ) << …`: a callee isLogReceiver reads as a logger). Any
// other leftmost operand — an `std::ostringstream`, a file stream, a shift — answers no.
inline constexpr std::string_view kConsoleStreams[] = { "std::cerr", "std::clog", "std::cout", "cerr", "clog", "cout" };

inline bool isStreamLogStatement( TSNode stmt, std::string_view src )
{
    TSNode e = statementExpression( stmt );
    if( !typeIs( e, "binary_expression" ) )
    {
        return false;
    }
    while( typeIs( e, "binary_expression" ) )
    {
        if( nodeTextOf( field( e, "operator" ), src ) != "<<" )
        {
            return false;
        }
        e = field( e, "left" );
    }
    if( typeIs( e, "call_expression" ) )
    {
        const TSNode fn = field( e, "function" );
        return typeIs( fn, "identifier" ) && isLogReceiver( nodeTextOf( fn, src ) );
    }
    const std::string_view head = nodeTextOf( e, src );
    return std::find( std::begin( kConsoleStreams ), std::end( kConsoleStreams ), head ) != std::end( kConsoleStreams );
}

// Is this statement ONE logging/print call? An unrecognised callee answers no — the shape then does not
// fire, which is a miss and never a finding.
inline bool isLogCall( TSNode stmt, std::string_view src )
{
    const TSNode call = statementExpression( stmt );
    if( !isCallNode( call ) )
    {
        return isStreamLogStatement( stmt, src );
    }
    std::string_view       recv;
    const std::string_view verb = calleeText( call, src, recv );
    if( isStderrPrintCall( call, verb, src ) )
    {
        return true;
    }
    if( recv.empty() )
    {
        for( std::string_view bare : kBarePrintCalls )
        {
            if( verb == bare )
            {
                return true;
            }
        }
        return false;
    }
    if( recv == "fmt" && ( verb == "Errorf" || verb.starts_with( "S" ) ) )
    {
        return false;   // fmt.Errorf / Sprintf BUILD a value; they print nothing
    }
    const std::string lowered = lowerCopy( verb );
    return std::find( std::begin( kLogVerbs ), std::end( kLogVerbs ), lowered ) != std::end( kLogVerbs ) && isLogReceiver( recv );
}

// A statement that re-raises the caught error unchanged: bare `raise` / `throw;`, or raise/throw of the
// caught name itself. `raise e from x` changes the chain and is not unchanged.
inline bool isRethrowOf( TSNode stmt, std::string_view src, std::string_view name ) noexcept
{
    const TSNode s = statementExpression( stmt );
    if( typeIs( s, "identifier" ) && nodeTextOf( s, src ) == "raise" )
    {
        return true;   // Ruby: a bare `raise` parses as an identifier
    }
    const bool isThrow = typeIs( s, "raise_statement" ) || typeIs( s, "throw_statement" )
                      || ( typeIs( s, "jump_expression" ) && nodeTextOf( s, src ).starts_with( "throw" ) );
    const bool isRubyRaise = typeIs( s, "call" ) && nodeTextOf( field( s, "method" ), src ) == "raise" && ts_node_is_null( field( s, "receiver" ) );
    if( !isThrow && !isRubyRaise )
    {
        return false;
    }
    if( !ts_node_is_null( field( s, "cause" ) ) )
    {
        return false;
    }
    const TSNode arg = isRubyRaise ? field( s, "arguments" ) : s;
    const std::uint32_t argCount = namedCount( arg );
    if( argCount == 0 )
    {
        return !isRubyRaise || ts_node_is_null( arg );
    }
    return argCount == 1 && !name.empty() && nodeTextOf( namedChild( arg, 0 ), src ) == name;
}

// ── the two error-masking shapes over one handler ─────────────────────────────────────────────────────

inline std::string_view handlerShape( const Handler& h, std::string_view src, std::vector<TSNode>& stmts )
{
    if( h.filtered )
    {
        return {};
    }
    statementsOf( h.body, stmts );
    if( stmts.empty() )
    {
        return {};   // an EMPTY handler is kErrorMaskRules' row, not this shape
    }
    if( h.sole && stmts.size() == 1 && isRethrowOf( stmts[0], src, h.name ) )
    {
        return kShapeRethrowOnly;
    }
    if( !h.broad )
    {
        return {};
    }
    for( const TSNode s : stmts )
    {
        if( !isLogCall( s, src ) )
        {
            return {};
        }
    }
    return mentionsError( h.body, src, h.name ) ? std::string_view() : kShapeLogOnly;
}

// Go: `if err != nil { log.Printf( "…" ) }` — no else, the error-shaped name compared against nil, and a
// body of log calls that never reads it. A Fatal/Panic log is not a log verb above, so it never qualifies.
inline bool isGoErrName( std::string_view n ) noexcept
{
    return n == "err" || n.ends_with( "Err" ) || n.ends_with( "err" ) || ( n.starts_with( "err" ) && n.size() > 3 && n[3] >= 'A' && n[3] <= 'Z' );
}

inline std::string_view goLogOnlyShape( TSNode n, std::string_view src, std::vector<TSNode>& stmts )
{
    const TSNode cond = field( n, "condition" );
    if( !typeIs( cond, "binary_expression" ) || !ts_node_is_null( field( n, "alternative" ) ) )
    {
        return {};
    }
    const TSNode left = field( cond, "left" ), right = field( cond, "right" ), op = field( cond, "operator" );
    if( !typeIs( left, "identifier" ) || !typeIs( right, "nil" ) || nodeTextOf( op, src ) != "!=" || !isGoErrName( nodeTextOf( left, src ) ) )
    {
        return {};
    }
    const TSNode body = field( n, "consequence" );
    statementsOf( body, stmts );
    if( stmts.empty() )
    {
        return {};
    }
    for( const TSNode s : stmts )
    {
        if( !isLogCall( s, src ) )
        {
            return {};
        }
    }
    return mentionsError( body, src, nodeTextOf( left, src ) ) ? std::string_view() : kShapeLogOnly;
}

// Rust, QD-K6E-RUST's log-only half: an `Err(..)` arm, or an `if let Err(..) = … {}` with no else, whose body is only
// print/log macros (eprintln!, println!, log::warn!, tracing::error!, a bare warn!/error!/…) and never names the Err
// binding. Err is a Result's whole error side, so the handler is broad by construction. A guarded arm (`Err(_) if …`) is
// conditional and not judged.
inline constexpr std::string_view kRustPrintMacros[] = { "eprintln", "eprint", "println", "print" };
inline constexpr std::string_view kRustLogLevels[]   = { "error", "warn", "info", "debug", "trace" };

inline bool isRustLogMacro( TSNode stmt, std::string_view src )
{
    const TSNode e = statementExpression( stmt );
    if( !typeIs( e, "macro_invocation" ) )
    {
        return false;
    }
    std::string_view m = nodeTextOf( field( e, "macro" ), src );
    if( std::find( std::begin( kRustPrintMacros ), std::end( kRustPrintMacros ), m ) != std::end( kRustPrintMacros ) )
    {
        return true;
    }
    for( std::string_view crate : { std::string_view( "log::" ), std::string_view( "tracing::" ) } )
    {
        m = m.starts_with( crate ) ? m.substr( crate.size() ) : m;
    }
    return std::find( std::begin( kRustLogLevels ), std::end( kRustLogLevels ), m ) != std::end( kRustLogLevels );
}

// The Err binding of a tuple-struct pattern `Err( x )`, through `ref`/`mut` wrappers; empty for `_` or `..`. False
// when the pattern is not `Err( … )` at all, or when its inner pattern is REFUTABLE — `Err( MyError::NotFound )`,
// `Err( A | B )`, `Err( e @ MyError::Busy )`, an upper-case unit variant `Err( NotFound )`: that handles one variant,
// not the whole error side, so it is not a broad handler (CR #632).
inline bool rustErrBinding( TSNode pat, std::string_view src, std::string_view& name )
{
    name = {};
    if( !typeIs( pat, "tuple_struct_pattern" ) || nodeTextOf( field( pat, "type" ), src ) != "Err" )
    {
        return false;
    }
    TSNode inner = namedChild( pat, 1 );   // child 0 is the type
    while( typeIs( inner, "ref_pattern" ) || typeIs( inner, "mut_pattern" ) )
    {
        inner = namedChild( inner, ts_node_named_child_count( inner ) - 1 );   // `ref`/`mut` wrap the binding last
    }
    if( ts_node_is_null( inner ) || typeIs( inner, "remaining_field_pattern" ) )
    {
        return true;   // `Err( _ )` (`_` is an anonymous token) or `Err( .. )`
    }
    if( !typeIs( inner, "identifier" ) )
    {
        return false;
    }
    name = nodeTextOf( inner, src );
    return name.empty() || name[0] < 'A' || name[0] > 'Z';   // an upper-case `Err( NotFound )` names a variant
}

// A Rust format string names its argument INSIDE the literal (`"{e}"`, `"{e:?}"`), where mentionsName cannot see it.
inline bool rustFormatNames( TSNode body, std::string_view src, std::string_view name )
{
    const std::string_view text = nodeTextOf( body, src );
    for( std::size_t at = text.find( name ); at != std::string_view::npos; at = text.find( name, at + 1 ) )
    {
        const char after = at + name.size() < text.size() ? text[at + name.size()] : '\0';
        if( at > 0 && text[at - 1] == '{' && ( after == '}' || after == ':' ) )
        {
            return true;
        }
    }
    return false;
}

inline std::string_view rustLogOnlyShape( TSNode n, std::string_view src, std::vector<TSNode>& stmts )
{
    const bool       isArm = typeIs( n, "match_arm" );
    std::string_view name;
    TSNode           body;
    if( isArm )
    {
        const TSNode mp = field( n, "pattern" );
        if( !ts_node_is_null( field( mp, "condition" ) ) || !rustErrBinding( namedChild( mp, 0 ), src, name ) )
        {
            return {};
        }
        body = field( n, "value" );
    }
    else
    {
        const TSNode cond = field( n, "condition" );
        if( !typeIs( cond, "let_condition" ) || !ts_node_is_null( field( n, "alternative" ) ) || !rustErrBinding( field( cond, "pattern" ), src, name ) )
        {
            return {};
        }
        body = field( n, "consequence" );
    }
    if( typeIs( body, "block" ) )
    {
        statementsOf( body, stmts );
    }
    else
    {
        stmts.assign( 1, body );   // `Err(_) => eprintln!( "x" ),`
    }
    if( stmts.empty() || !std::all_of( stmts.begin(), stmts.end(), [ & ]( TSNode s ) { return isRustLogMacro( s, src ); } ) )
    {
        return {};
    }
    const bool named = !name.empty() && name != "_" && ( mentionsError( body, src, name ) || rustFormatNames( body, src, name ) );
    return named ? std::string_view() : kShapeLogOnly;
}

// ── placeholders ──────────────────────────────────────────────────────────────────────────────────────

// Case-insensitive search for one of the stub phrases in a string literal's text. "TODO" is matched
// case-SENSITIVELY and as a whole word, because "todo" in lower case is ordinary English ("todo list").
inline constexpr std::string_view kStubPhrases[] = { "not implemented", "not yet implemented", "unimplemented", "implement me" };

inline bool saysNotImplemented( std::string_view s )
{
    if( countPhrases( s, kStubPhrases ) > 0 )
    {
        return true;
    }
    for( std::size_t at = s.find( "TODO" ); at != std::string_view::npos; at = s.find( "TODO", at + 1 ) )
    {
        const bool leftOk  = at == 0 || !( std::isalnum( static_cast<unsigned char>( s[at - 1] ) ) || s[at - 1] == '_' );
        const bool rightOk = at + 4 >= s.size() || !( std::isalnum( static_cast<unsigned char>( s[at + 4] ) ) || s[at + 4] == '_' );
        if( leftOk && rightOk )
        {
            return true;
        }
    }
    return false;
}

// Any string literal below n that says "not implemented" (or one of its spellings).
inline bool hasStubMessage( TSNode n, std::string_view src )
{
    return anyChildBelow( n, 6, true, [ & ]( TSNode c )
                          { return std::strstr( ts_node_type( c ), "string" ) != nullptr && saysNotImplemented( nodeTextOf( c, src ) ); } );
}

// Python: is this raise inside a method decorated @abstractmethod (the language's declared "subclass
// implements this")? Such a raise is a contract, not a placeholder.
inline bool insideAbstractMethod( TSNode n, std::string_view src )
{
    for( TSNode p = ts_node_parent( n ); !ts_node_is_null( p ); p = ts_node_parent( p ) )
    {
        if( typeIs( p, "function_definition" ) )
        {
            const TSNode        deco = ts_node_parent( p );
            const std::uint32_t a    = ts_node_start_byte( deco ), b = ts_node_start_byte( p );
            return typeIs( deco, "decorated_definition" ) && a < b && b <= src.size() && src.substr( a, b - a ).find( "abstract" ) != std::string_view::npos;
        }
    }
    return false;
}

// A raise/throw whose text declares a CONTRACT for subclasses ("must be implemented by subclasses",
// "override this", "abstract") is the language's abstract-method idiom, not a placeholder.
inline constexpr std::string_view kAbstractContractWords[] = { "subclass", "override", "abstract", "implemented by", "must implement", "should implement" };

inline bool declaresAbstractContract( std::string_view t )
{
    return countPhrases( t, kAbstractContractWords ) > 0;
}

// Is `n` the WHOLE body of the function (or method) around it — the only statement, a leading docstring
// and comments aside? That is what a stub is; a raise inside an `if` is a guard for an unsupported case.
inline bool isWholeFunctionBody( TSNode n )
{
    const TSNode block = ts_node_parent( n );
    const TSNode fn    = ts_node_is_null( block ) ? block : ts_node_parent( block );
    if( !( typeIs( block, "block" ) && typeIs( fn, "function_definition" ) ) && !( typeIs( block, "body_statement" ) && typeIs( fn, "method" ) ) )
    {
        return false;
    }
    std::vector<TSNode> stmts;
    statementsOf( block, stmts );
    std::size_t first = 0;
    if( stmts.size() > 1 && typeIs( statementExpression( stmts[0] ), "string" ) )
    {
        first = 1;   // the docstring
    }
    return stmts.size() == first + 1 && ts_node_eq( stmts[first], n );
}

// Is n inside a class body — Python's class_definition, or Ruby's class/module? (Python's ROOT node is
// also called `module`, so the Ruby spellings are asked only of a Ruby tree.)
inline bool insideClass( TSNode n, Lang lang )
{
    for( TSNode p = ts_node_parent( n ); !ts_node_is_null( p ); p = ts_node_parent( p ) )
    {
        if( typeIs( p, "class_definition" ) || ( lang == Lang::Ruby && ( typeIs( p, "class" ) || typeIs( p, "module" ) ) ) )
        {
            return true;
        }
    }
    return false;
}

// Python's (and Ruby's) bare NotImplementedError is overwhelmingly NOT a placeholder, measured twice on
// 25-hit samples: in library code it is a GUARD for an unsupported case (`if sharding: raise
// NotImplementedError( "... not supported" )`), and as a whole METHOD body it is the abstract-by-convention
// interface (asyncio's AbstractEventLoop is dozens of them, no decorator). So the bare form is a stub only as
// the whole body of a FREE function; anywhere else it counts only when its message itself says "not
// implemented" / TODO (hasStubMessage) — a recall floor, stated, for an undecorated placeholder method.
inline bool isNotImplementedErrorRaise( TSNode n, std::string_view src )
{
    TSNode what = namedChild( n, 0 );
    if( typeIs( what, "call" ) )
    {
        what = field( what, "function" );
    }
    return typeIs( what, "identifier" ) && nodeTextOf( what, src ) == "NotImplementedError" && isWholeFunctionBody( n ) && !insideClass( n, Lang::Python )
        && !insideAbstractMethod( n, src );
}

inline bool isStubCall( TSNode n, std::string_view src, Lang lang )
{
    std::string_view       recv;
    const std::string_view verb = calleeText( n, src, recv );
    if( lang == Lang::Kotlin && recv.empty() && verb == "TODO" )
    {
        return true;
    }
    if( lang == Lang::Ruby && recv.empty() && verb == "raise" )
    {
        return ( nodeTextOf( n, src ).find( "NotImplementedError" ) != std::string_view::npos && isWholeFunctionBody( n ) && !insideClass( n, Lang::Ruby ) ) || hasStubMessage( n, src );
    }
    const bool stopper = recv.empty() && ( verb == "panic" || verb == "fatalError" || verb == "preconditionFailure" || verb == "assert" );
    return stopper && hasStubMessage( n, src );
}

inline bool isStubNode( TSNode n, const char* type, std::string_view src, Lang lang )
{
    if( kindIs( type, "macro_invocation" ) )
    {
        const std::string_view m = nodeTextOf( field( n, "macro" ), src );
        return m == "todo" || m == "unimplemented" || ( m == "panic" && hasStubMessage( n, src ) );
    }
    if( kindIs( type, "raise_statement" ) )
    {
        return isNotImplementedErrorRaise( n, src ) || hasStubMessage( n, src );
    }
    if( kindIs( type, "throw_statement" ) || kindIs( type, "throw_expression" ) )
    {
        const std::string_view t = nodeTextOf( n, src );
        return t.find( "NotImplementedException" ) != std::string_view::npos || hasStubMessage( n, src );
    }
    if( kindIs( type, "jump_expression" ) )
    {
        return nodeTextOf( n, src ).starts_with( "throw" ) && hasStubMessage( n, src );
    }
    if( kindIs( type, "call_expression" ) || kindIs( type, "call" ) )
    {
        return isStubCall( n, src, lang );
    }
    return false;
}

// Does this comment text name an issue? `#123`, `ABC-123` (a tracker key), `gh-123`, or any URL.
inline bool namesIssue( std::string_view c ) noexcept
{
    for( std::size_t i = 0; i + 1 < c.size(); ++i )
    {
        const bool digitNext = c[i + 1] >= '0' && c[i + 1] <= '9';
        if( ( c[i] == '#' && digitNext ) || ( c[i] == ':' && c.substr( i, 3 ) == "://" ) )
        {
            return true;
        }
        if( c[i] == '-' && digitNext && i >= 2 && c[i - 1] >= 'A' && c[i - 1] <= 'Z' && c[i - 2] >= 'A' && c[i - 2] <= 'Z' )
        {
            return true;
        }
        if( c[i] == '-' && digitNext && i >= 2 && lowerCopy( c.substr( i - 2, 2 ) ) == "gh" )
        {
            return true;
        }
    }
    return false;
}

// Does some LINE of this comment START with TODO or FIXME, once the comment punctuation is stripped?
// Line-initial only: a comment that mentions "the TODO list" mid-sentence is prose about a TODO, not one.
inline bool opensWithTodo( std::string_view c ) noexcept
{
    std::size_t at = 0;
    while( at < c.size() )
    {
        std::size_t nl = c.find( '\n', at );
        if( nl == std::string_view::npos )
        {
            nl = c.size();
        }
        std::string_view line = c.substr( at, nl - at );
        while( !line.empty() && std::strchr( " \t\r/*#-!<;", line.front() ) != nullptr )
        {
            line.remove_prefix( 1 );
        }
        for( std::string_view word : { std::string_view( "TODO" ), std::string_view( "FIXME" ) } )
        {
            // Accepts the word alone, a colon, an (owner) and a following space; refuses TODO-ARM, TODOS
            // and TODO_LIST, which name something rather than leave it undone.
            if( line.starts_with( word ) && ( line.size() == word.size() || ( line[word.size()] != '\0' && std::strchr( ":( \t\r.,", line[word.size()] ) != nullptr ) ) )
            {
                return true;
            }
        }
        at = nl + 1;
    }
    return false;
}

// The row of a (language, node type) table — kErrBranchReaders, kFailureDefaultReaders — for this node, or null.
template< class Row, std::size_t N >
inline const Row* langTypeRow( const Row ( &table )[N], Lang lang, const char* type ) noexcept
{
    const Row* it = std::find_if( std::begin( table ), std::end( table ), [ & ]( const Row& r ) { return r.lang == lang && std::strcmp( r.nodeType, type ) == 0; } );
    return it == std::end( table ) ? nullptr : it;
}

// ── failure-default (an error-masking facet) ──────────────────────────────────────────────────────────
//
// A read, parse or spawn failure collapsed into a value a success can also return, in a function whose declared
// result has no room for the failure: the caller cannot tell "no advisories" from "the audit's JSON did not parse".
// Two spellings, each REPORT-ONLY in every language (lintrules.h errorMaskHitGates), so a row it adds is sev="minor":
//   TypeScript  a `catch` whose only statement returns an empty value (null, undefined, [], {}, false, 0, ''), or a
//               promise `.catch( () => <empty> )`, where the try body (the promise chain) calls JSON.parse, an fs
//               read, readFile*, exec*/spawn*, fetch, or a helper this FILE defines that calls one of them (two hops);
//               and the enclosing function DECLARES a return type that cannot carry the failure — an array or tuple,
//               boolean, an object type, Record/Map/Set, or Promise of one of those (never a union, unknown, any or a
//               named alias, which may hold null);
//   C++         `.value_or( <empty> )` (an empty string or view, {}, "", 0, false) on a file read (readWholeFile,
//               readRegularFile, readText…), directly or through a local the read initialized, in a function whose
//               result is not an optional, expected, variant or pointer.
// Refused, each a miss and never a finding: a handler with a comment or any second statement (a log call); a TS
// function with no declared return type; a C++ local read anywhere between the read and the value_or (the
// `if( !bytes ) DISCLOSE(…)` house pattern), a value_or result the next statement tests with `.empty()` (the empty
// text is the handled "unread" answer), or a comment on the value_or's line (the documented floor).
// Measured on a hand-read sample before it was built (reports/qd-ge-card-verify-1112.md): TS 4 of 9 sites a defect,
// C++ 0 of 6 with 2 borderline; Python, Go and Rust are not read here (0 of 18).

inline bool hasCommentChild( TSNode n )
{
    return !ts_node_is_null( firstChildOfKind( n, false, { "comment" } ) );
}

// ── TypeScript ──

// null, undefined, [], {}, false, 0, '' / "" — an array or object with any child (a comment included) is not empty.
inline bool isTsEmptyValue( TSNode e, std::string_view src )
{
    e = unwrapSole( e, "parenthesized_expression" );
    if( typeIs( e, "null" ) || typeIs( e, "undefined" ) || typeIs( e, "false" ) )
    {
        return true;
    }
    if( typeIs( e, "array" ) || typeIs( e, "object" ) )
    {
        return ts_node_child_count( e ) == 2;   // the two brackets alone
    }
    if( typeIs( e, "string" ) )
    {
        return namedCount( e ) == 0;
    }
    return typeIs( e, "number" ) && nodeTextOf( e, src ) == "0";
}

inline bool isTsEmptyReturn( TSNode stmt, std::string_view src )
{
    return typeIs( stmt, "return_statement" ) && namedCount( stmt ) == 1 && isTsEmptyValue( namedChild( stmt, 0 ), src );
}

inline constexpr const char* kTsFunctionTypes[] = { "function_declaration", "function_expression", "function", "arrow_function",
                                                    "method_definition", "generator_function_declaration", "generator_function" };

inline bool isTsFunction( TSNode n ) noexcept
{
    return typeIsOneOf( n, kTsFunctionTypes );
}

// The generic containers whose value is a collection a caller reads as "none", never "failed".
inline constexpr std::string_view kTsCollectionGenerics[] = { "Array", "ReadonlyArray", "Record", "Map", "Set", "ReadonlyMap", "ReadonlySet" };

// Can a value of this declared type say "it failed"? No for a collection, boolean or object type; Promise<T> is judged
// by T (once). Everything else answers "it can" — a union, unknown, any, void, and a named type, which may alias one.
inline bool tsTypeCannotCarryFailure( TSNode t, std::string_view src, bool insidePromise )
{
    while( ( typeIs( t, "parenthesized_type" ) || typeIs( t, "readonly_type" ) ) && namedCount( t ) == 1 )
    {
        t = namedChild( t, 0 );
    }
    if( typeIs( t, "array_type" ) || typeIs( t, "tuple_type" ) || typeIs( t, "object_type" ) )
    {
        return true;
    }
    if( typeIs( t, "predefined_type" ) )
    {
        return nodeTextOf( t, src ) == "boolean";
    }
    if( !typeIs( t, "generic_type" ) )
    {
        return false;
    }
    const std::string_view name = nodeTextOf( field( t, "name" ), src );
    if( name == "Promise" && !insidePromise )
    {
        const TSNode args = field( t, "type_arguments" );
        return namedCount( args ) == 1 && tsTypeCannotCarryFailure( namedChild( args, 0 ), src, true );
    }
    return std::find( std::begin( kTsCollectionGenerics ), std::end( kTsCollectionGenerics ), name ) != std::end( kTsCollectionGenerics );
}

inline bool tsReturnCannotCarryFailure( TSNode site, std::string_view src )
{
    const TSNode fn         = ancestorWhere( site, isTsFunction );
    const TSNode annotation = field( fn, "return_type" );
    return namedCount( annotation ) == 1 && tsTypeCannotCarryFailure( namedChild( annotation, 0 ), src, false );
}

inline constexpr std::string_view kTsSpawnMembers[] = { "execSync", "execFile", "execFileSync", "spawn", "spawnSync", "execa", "execaSync", "execaCommand", "fork" };

// A call to JSON.parse, an fs read, readFile*, exec*/spawn* or fetch, by its callee's spelling. A member `exec` alone is
// not one: RegExp.prototype.exec is the common reading.
inline bool isTsReadParseSpawnCallee( TSNode callee, std::string_view src )
{
    if( typeIs( callee, "identifier" ) )
    {
        const std::string_view name = nodeTextOf( callee, src );
        return name == "fetch" || name.starts_with( "exec" ) || name.starts_with( "spawn" ) || name.starts_with( "readFile" );
    }
    if( !typeIs( callee, "member_expression" ) )
    {
        return false;
    }
    const std::string_view object   = nodeTextOf( field( callee, "object" ), src );
    const std::string_view property = nodeTextOf( field( callee, "property" ), src );
    if( object == "JSON" )
    {
        return property == "parse";
    }
    const bool fsObject = object.ends_with( "fs" ) || object.ends_with( "promises" ) || object == "fsp" || object == "fse" || object == "fsPromises";
    return ( fsObject && property.starts_with( "read" ) )
        || std::find( std::begin( kTsSpawnMembers ), std::end( kTsSpawnMembers ), property ) != std::end( kTsSpawnMembers );
}

// The body of a function this file defines under `name`: `function name`, `const name = ( … ) => …`, or a method.
inline TSNode tsHelperBody( TSNode root, std::string_view name, std::string_view src )
{
    TSNode body = {};
    anyNamedNodeBelow( root, false, [ & ]( TSNode n, int )
    {
        TSNode fn = {};
        if( typeIs( n, "function_declaration" ) || typeIs( n, "method_definition" ) || typeIs( n, "generator_function_declaration" ) )
        {
            fn = nodeTextOf( field( n, "name" ), src ) == name ? n : TSNode{};
        }
        else if( typeIs( n, "variable_declarator" ) && nodeTextOf( field( n, "name" ), src ) == name )
        {
            fn = field( n, "value" );
            fn = isTsFunction( fn ) ? fn : TSNode{};
        }
        body = field( fn, "body" );
        return !ts_node_is_null( body );
    } );
    return body;
}

// Does code below n call a read, parse or spawn — directly, or through a helper this file defines (hopsLeft more
// hops)? `this.helper()` and `helper()` are looked up by name; an imported helper is a miss.
inline bool tsCallsReadParseSpawn( TSNode n, std::string_view src, int hopsLeft )
{
    TSNode root = {};
    return anyNamedNodeBelow( n, false, [ & ]( TSNode c, int )
    {
        if( !typeIs( c, "call_expression" ) )
        {
            return false;
        }
        const TSNode callee = field( c, "function" );
        if( isTsReadParseSpawnCallee( callee, src ) )
        {
            return true;
        }
        if( hopsLeft == 0 )
        {
            return false;
        }
        std::string_view helper;
        if( typeIs( callee, "identifier" ) )
        {
            helper = nodeTextOf( callee, src );
        }
        else if( typeIs( callee, "member_expression" ) && nodeTextOf( field( callee, "object" ), src ) == "this" )
        {
            helper = nodeTextOf( field( callee, "property" ), src );
        }
        if( helper.empty() )
        {
            return false;
        }
        root = ts_node_is_null( root ) ? rootOf( n ) : root;
        const TSNode body = tsHelperBody( root, helper, src );
        return !ts_node_is_null( body ) && !ts_node_eq( body, n ) && tsCallsReadParseSpawn( body, src, hopsLeft - 1 );
    } );
}

inline constexpr int kTsHelperHops = 1;   // the try body's own calls, then one helper hop: "within depth 2"

// `try { <reads> } catch { return []; }` — the catch's ONLY child is the empty return (a comment is a child too).
inline bool tsCatchFailureDefault( TSNode n, std::string_view src )
{
    const TSNode body = field( n, "body" );
    if( namedCount( body ) != 1 || !isTsEmptyReturn( namedChild( body, 0 ), src ) )
    {
        return false;
    }
    const TSNode tryNode = ts_node_parent( n );
    return typeIs( tryNode, "try_statement" ) && tsReturnCannotCarryFailure( n, src )
        && tsCallsReadParseSpawn( field( tryNode, "body" ), src, kTsHelperHops );
}

// `<chain that reads>.catch( () => [] )`, or a handler block whose only statement is the empty return.
inline bool tsPromiseCatchFailureDefault( TSNode call, std::string_view src )
{
    const TSNode callee = field( call, "function" );
    if( !typeIs( callee, "member_expression" ) || nodeTextOf( field( callee, "property" ), src ) != "catch" )
    {
        return false;
    }
    const TSNode args    = field( call, "arguments" );
    const TSNode handler = namedChild( args, 0 );
    if( namedCount( args ) != 1 || !isTsFunction( handler ) || hasCommentChild( handler ) )
    {
        return false;
    }
    const TSNode body  = field( handler, "body" );
    const bool   empty = typeIs( body, "statement_block" ) ? namedCount( body ) == 1 && isTsEmptyReturn( namedChild( body, 0 ), src )
                                                           : isTsEmptyValue( body, src );
    return empty && tsReturnCannotCarryFailure( call, src ) && tsCallsReadParseSpawn( field( callee, "object" ), src, kTsHelperHops );
}

// ── C++ ──

// The empty value a `.value_or( … )` falls back to, compared with whitespace removed.
inline constexpr std::string_view kCxxEmptyValues[] = { "std::string()", "std::string{}", "std::string_view()", "std::string_view{}", "{}", "\"\"", "0", "0u", "false" };

inline bool isCxxEmptyValue( TSNode e, std::string_view src )
{
    const std::string_view text = nodeTextOf( e, src );
    std::string            squeezed;
    squeezed.reserve( text.size() );
    for( char c : text )
    {
        if( std::isspace( static_cast<unsigned char>( c ) ) == 0 )
        {
            squeezed.push_back( c );
        }
    }
    return std::find( std::begin( kCxxEmptyValues ), std::end( kCxxEmptyValues ), squeezed ) != std::end( kCxxEmptyValues );
}

// The read helpers whose optional result says "could not read": ripwire's own and the common spellings.
inline constexpr std::string_view kCxxReadPrefixes[] = { "readWhole", "readRegularFile", "readText", "readFile", "readAll" };

inline bool isCxxReadCall( TSNode n, std::string_view src )
{
    if( !typeIs( n, "call_expression" ) )
    {
        return false;
    }
    std::string_view name = nodeTextOf( field( n, "function" ), src );
    const std::size_t cut = name.find_last_of( ":.>" );
    name = cut == std::string_view::npos ? name : name.substr( cut + 1 );
    return std::any_of( std::begin( kCxxReadPrefixes ), std::end( kCxxReadPrefixes ), [ name ]( std::string_view p ) { return name.starts_with( p ); } );
}

// `std::move( x )` → x.
inline TSNode unwrapStdMove( TSNode n, std::string_view src )
{
    const TSNode args = field( n, "arguments" );
    if( typeIs( n, "call_expression" ) && nodeTextOf( field( n, "function" ), src ) == "std::move" && namedCount( args ) == 1 )
    {
        return namedChild( args, 0 );
    }
    return n;
}

// The source line that holds byte `at`, without its newline.
inline std::string_view lineAt( std::string_view src, std::uint32_t at ) noexcept
{
    const std::size_t from  = at == 0 ? std::string_view::npos : src.rfind( '\n', at - 1 );
    const std::size_t begin = from == std::string_view::npos ? 0 : from + 1;
    const std::size_t to    = src.find( '\n', at );
    return src.substr( begin, ( to == std::string_view::npos ? src.size() : to ) - begin );
}

// A comment anywhere on the source line that holds `at` — the line that says the empty value is a floor.
inline bool lineHasComment( std::string_view src, std::uint32_t at ) noexcept
{
    const std::string_view line = lineAt( src, at );
    char quote = 0;   // the open string or character literal's quote, 0 outside one
    for( std::size_t i = 0; i + 1 < line.size(); ++i )
    {
        if( quote != 0 && line[i] == '\\' )
        {
            ++i;
        }
        else if( line[i] == '"' || line[i] == '\'' )
        {
            quote = quote == 0 ? line[i] : ( quote == line[i] ? 0 : quote );
        }
        else if( quote == 0 && line[i] == '/' && ( line[i + 1] == '/' || line[i + 1] == '*' ) )
        {
            return true;
        }
    }
    return false;
}

inline constexpr std::string_view kCxxFailureCarriers[] = { "optional", "expected", "variant", "Result" };

// Can this function's result say "it failed"? An optional/expected/variant/Result return type (a trailing one
// included) or a pointer declarator can.
inline bool cxxReturnCanCarryFailure( TSNode fn, std::string_view src )
{
    const TSNode declarator = field( fn, "declarator" );
    if( typeIs( declarator, "pointer_declarator" ) )
    {
        return true;
    }
    const auto carries = [ & ]( TSNode t )
    {
        const std::string_view text = nodeTextOf( t, src );
        return std::any_of( std::begin( kCxxFailureCarriers ), std::end( kCxxFailureCarriers ), [ text ]( std::string_view w ) { return text.find( w ) != std::string_view::npos; } );
    };
    return carries( field( fn, "type" ) ) || carries( firstChildOfKind( declarator, true, { "trailing_return_type" } ) );
}

// Was the local `name` initialized or assigned from a read, and NOT read anywhere else before byte `before` in this
// function body? Any other use — `if( !bytes )`, `failed = !bytes.has_value()` — is the failure being looked at.
inline bool cxxLocalFromUntestedRead( TSNode body, std::string_view name, std::uint32_t before, std::string_view src )
{
    std::uint32_t reads    = 0;   // initializations and assignments from a read
    std::uint32_t mentions = 0;   // every identifier spelling the name, those included
    anyNamedNodeBelow( body, false, [ & ]( TSNode n, int )
    {
        if( ts_node_start_byte( n ) >= before )
        {
            return false;
        }
        if( typeIs( n, "identifier" ) && nodeTextOf( n, src ) == name )
        {
            ++mentions;
        }
        else if( typeIs( n, "init_declarator" ) && nodeTextOf( field( n, "declarator" ), src ) == name )
        {
            reads += isCxxReadCall( field( n, "value" ), src ) ? 1u : 0u;
        }
        else if( typeIs( n, "assignment_expression" ) && nodeTextOf( field( n, "left" ), src ) == name )
        {
            reads += isCxxReadCall( field( n, "right" ), src ) ? 1u : 0u;
        }
        return false;
    } );
    return reads > 0 && mentions == reads;
}

// The statement after the one in a block that holds n (comments skipped); null when there is none.
inline TSNode nextStatementAfter( TSNode n )
{
    const TSNode stmt = ancestorWhere( n, []( TSNode p ) { return typeIs( ts_node_parent( p ), "compound_statement" ); } );
    TSNode       next = ts_node_is_null( stmt ) ? TSNode{} : ts_node_next_named_sibling( stmt );
    while( !ts_node_is_null( next ) && isCommentNode( next ) )
    {
        next = ts_node_next_named_sibling( next );
    }
    return next;
}

// Does `text` ask `<name>.empty()` (spaces allowed before the dot)?
inline bool asksEmpty( std::string_view text, std::string_view name ) noexcept
{
    for( std::size_t at = text.find( name ); at != std::string_view::npos; at = text.find( name, at + 1 ) )
    {
        std::string_view rest = text.substr( at + name.size() );
        while( !rest.empty() && ( rest.front() == ' ' || rest.front() == '\t' ) )
        {
            rest.remove_prefix( 1 );
        }
        if( rest.starts_with( ".empty()" ) || rest.starts_with( ".empty( )" ) )
        {
            return true;
        }
    }
    return false;
}

// The statement after the one that holds `call`, when that statement stores the value_or into a name: true when it
// asks `<name>.empty()` — the empty text IS the handled "unread" answer there (`if( bytes.empty() ) continue;`).
inline bool cxxEmptyTestedNext( TSNode call, std::string_view src )
{
    const TSNode     holder = ts_node_parent( call );
    std::string_view stored;
    if( typeIs( holder, "init_declarator" ) && ts_node_eq( field( holder, "value" ), call ) )
    {
        stored = nodeTextOf( field( holder, "declarator" ), src );
    }
    else if( typeIs( holder, "assignment_expression" ) && ts_node_eq( field( holder, "right" ), call ) )
    {
        stored = nodeTextOf( field( holder, "left" ), src );
    }
    return !stored.empty() && asksEmpty( nodeTextOf( nextStatementAfter( holder ), src ), stored );
}

// `read( … ).value_or( std::string() )`, or `bytes.value_or( {} )` with `bytes` an untested read — and the empty
// result not tested by the next statement.
inline bool cxxValueOrFailureDefault( TSNode call, std::string_view src )
{
    const TSNode callee = field( call, "function" );
    if( !typeIs( callee, "field_expression" ) || nodeTextOf( field( callee, "field" ), src ) != "value_or" )
    {
        return false;
    }
    const TSNode args = field( call, "arguments" );
    if( namedCount( args ) != 1 || !isCxxEmptyValue( namedChild( args, 0 ), src ) || lineHasComment( src, ts_node_start_byte( args ) ) )
    {
        return false;
    }
    const TSNode fn = ancestorOfKind( call, { "function_definition" } );   // a lambda is transparent: its value flows into the named function
    if( ts_node_is_null( fn ) || cxxReturnCanCarryFailure( fn, src ) || cxxEmptyTestedNext( call, src ) )
    {
        return false;
    }
    const TSNode receiver = unwrapStdMove( field( callee, "argument" ), src );
    if( isCxxReadCall( receiver, src ) )
    {
        return true;
    }
    return typeIs( receiver, "identifier" ) && cxxLocalFromUntestedRead( field( fn, "body" ), nodeTextOf( receiver, src ), ts_node_start_byte( call ), src );
}

// One row per (language, node type), read like kHandlerReaders.
struct FailureDefaultReader
{
    Lang        lang;
    const char* nodeType;
    bool ( *matches )( TSNode, std::string_view );
};

inline constexpr FailureDefaultReader kFailureDefaultReaders[] = {
    { Lang::TypeScript, "catch_clause",    tsCatchFailureDefault        },
    { Lang::TypeScript, "call_expression", tsPromiseCatchFailureDefault },
    { Lang::Cpp,        "call_expression", cxxValueOrFailureDefault     },
};

// kShapeFailureDefault when this node is one, else empty.
inline std::string_view failureDefaultShape( TSNode n, const char* type, std::string_view src, Lang lang )
{
    const FailureDefaultReader* row = langTypeRow( kFailureDefaultReaders, lang, type );
    return ( row != nullptr && row->matches( n, src ) ) ? kShapeFailureDefault : std::string_view();
}

// ── the walk ──────────────────────────────────────────────────────────────────────────────────────────

// One row per language, so the language finds the row and the node type confirms it.
inline const HandlerReader* handlerReaderFor( Lang lang, const char* type ) noexcept
{
    const HandlerReader* row = findByField( kHandlerReaders, &HandlerReader::lang, lang );
    return ( row != nullptr && std::strcmp( row->nodeType, type ) == 0 ) ? row : nullptr;
}

// The languages whose error branch is not a catch clause: Go's `if err != nil` and Rust's Err arm / `if let Err`. One row
// per (language, node type), read like kHandlerReaders.
struct ErrBranchReader
{
    Lang        lang;
    const char* nodeType;
    std::string_view ( *shape )( TSNode, std::string_view, std::vector<TSNode>& );
};

inline constexpr ErrBranchReader kErrBranchReaders[] = {
    { Lang::Go,   "if_statement",  goLogOnlyShape   },
    { Lang::Rust, "match_arm",     rustLogOnlyShape },
    { Lang::Rust, "if_expression", rustLogOnlyShape },
};

inline const ErrBranchReader* errBranchReaderFor( Lang lang, const char* type ) noexcept
{
    return langTypeRow( kErrBranchReaders, lang, type );
}

// A stub, and not an abstract-method contract (declaresAbstractContract) — the one test for every spelling.
inline bool isPlaceholderStub( TSNode n, const char* type, std::string_view src, Lang lang )
{
    return isStubNode( n, type, src, lang ) && !declaresAbstractContract( nodeTextOf( n, src ) );
}

// The tag this ONE node carries, if any — empty for almost every node.
inline std::string_view shapeOfNode( TSNode n, std::string_view src, Lang lang, std::vector<TSNode>& stmts )
{
    const char* type = ts_node_type( n );
    if( const HandlerReader* reader = handlerReaderFor( lang, type ) )
    {
        Handler h;
        reader->read( n, src, h );
        const std::string_view shape = handlerShape( h, src, stmts );
        return shape.empty() ? failureDefaultShape( n, type, src, lang ) : shape;
    }
    if( const std::string_view shape = failureDefaultShape( n, type, src, lang ); !shape.empty() )
    {
        return shape;
    }
    if( const ErrBranchReader* reader = errBranchReaderFor( lang, type ) )
    {
        return reader->shape( n, src, stmts );
    }
    if( isCommentNode( n ) )
    {
        const std::string_view c = nodeTextOf( n, src );
        return ( opensWithTodo( c ) && !namesIssue( c ) ) ? kShapeTodo : std::string_view();
    }
    return isPlaceholderStub( n, type, src, lang ) ? kShapeStub : std::string_view();
}

// Every hit in one file's tree, in document (DFS pre-) order. Explicit stack with the same pathological-depth
// guard the unreachable-code walk uses; a node that is a hit is still descended into (a stub inside a
// log-only handler is two facts, one per kind).
inline void walkHandlerShapes( TSNode root, std::string_view src, Lang lang, std::vector<ShapeSpan>& out )
{
    struct Frame { TSNode node; std::uint16_t depth; };
    std::vector<Frame>  stack;
    std::vector<TSNode> kids;
    std::vector<TSNode> stmts;
    ChildCursor         cursor( root );
    stack.push_back( { root, 0 } );
    while( !stack.empty() )
    {
        const Frame frame = stack.back();
        stack.pop_back();
        if( frame.depth > 512 )
        {
            continue;   // pathological-AST guard, the same bound ur_walkTree uses
        }
        if( ts_node_is_named( frame.node ) )
        {
            const std::string_view tag = shapeOfNode( frame.node, src, lang, stmts );
            if( !tag.empty() )
            {
                ASSUME( tag == kShapeLogOnly || tag == kShapeRethrowOnly || tag == kShapeFailureDefault || tag == kShapeStub || tag == kShapeTodo,
                        "shapeOfNode answers one of the five tags or none" );
                out.push_back( { ts_node_start_byte( frame.node ), ts_node_end_byte( frame.node ), tag } );
            }
        }
        collectChildren( frame.node, cursor.cur, kids );
        for( std::size_t c = kids.size(); c > 0; --c )
        {
            stack.push_back( { kids[c - 1], static_cast<std::uint16_t>( frame.depth + 1 ) } );
        }
    }
}

}   // namespace rw::hshape
