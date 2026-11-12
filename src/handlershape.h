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
#include "ingest.h"              // the four kShape* tags, Lang

namespace rw::hshape
{


struct ShapeSpan
{
    std::uint32_t    startByte = 0;
    std::uint32_t    endByte   = 0;
    std::string_view tag;   // one of the four kShape* tags (ingest.h) — static storage, never a view into the file
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

// mentionsName's walk: true when a named leaf below n spells `name`, OR when it meets a node with named children at
// kMentionsNameMaxDepth levels down — a subtree too deep to read answers "mentions it", which excludes the handler from
// log-only: a miss, never a finding. An explicit stack, like walkHandlerShapes: a recursive walk 512 levels deep
// overflowed a 512 KiB worker-thread stack under AddressSanitizer's larger frames.
inline bool mentionsNameBelow( TSNode n, std::string_view src, std::string_view name )
{
    struct Frame { TSNode node; int depth; };
    std::vector<Frame> stack( 1, Frame{ n, 0 } );
    while( !stack.empty() )
    {
        const Frame frame = stack.back();
        stack.pop_back();
        if( ts_node_named_child_count( frame.node ) == 0 )
        {
            if( frame.depth > 0 && nodeTextOf( frame.node, src ) == name )
            {
                return true;
            }
            continue;
        }
        if( frame.depth >= kMentionsNameMaxDepth )
        {
            return true;
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

// Unwrap a statement to the expression it evaluates (expression_statement → its one child).
inline TSNode statementExpression( TSNode s ) noexcept
{
    if( typeIs( s, "expression_statement" ) && namedCount( s ) == 1 )
    {
        return namedChild( s, 0 );
    }
    return s;
}

// Python/Ruby, JS/TS/Go/Kotlin/C++/Rust/Swift, Java, C#.
inline constexpr const char* kCallNodeTypes[] = { "call", "call_expression", "method_invocation", "invocation_expression" };

inline bool isCallNode( TSNode n ) noexcept
{
    const char* t = typeOf( n );
    return std::any_of( std::begin( kCallNodeTypes ), std::end( kCallNodeTypes ), [ t ]( const char* k ) { return std::strcmp( t, k ) == 0; } );
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
    const TSNode args = field( call, "arguments" );
    for( std::uint32_t i = 0; i < namedCount( args ); ++i )
    {
        if( nodeTextOf( namedChild( args, i ), src ) == "stderr" )
        {
            return true;
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

// The Err binding of a tuple-struct pattern `Err( x )`, through `ref`/`mut` wrappers; empty for `_`, `..` or a nested
// pattern. False when the pattern is not `Err( … )` at all.
inline bool rustErrBinding( TSNode pat, std::string_view src, std::string_view& name )
{
    name = {};
    if( !typeIs( pat, "tuple_struct_pattern" ) || nodeTextOf( field( pat, "type" ), src ) != "Err" )
    {
        return false;
    }
    const TSNode inner = namedChild( pat, 1 );   // child 0 is the type
    if( typeIs( inner, "identifier" ) )
    {
        name = nodeTextOf( inner, src );
    }
    return true;
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

// ── the walk ──────────────────────────────────────────────────────────────────────────────────────────

// One row per language, so the language finds the row and the node type confirms it.
inline const HandlerReader* handlerReaderFor( Lang lang, const char* type ) noexcept
{
    const HandlerReader* row = findByField( kHandlerReaders, &HandlerReader::lang, lang );
    return ( row != nullptr && std::strcmp( row->nodeType, type ) == 0 ) ? row : nullptr;
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
        return handlerShape( h, src, stmts );
    }
    if( lang == Lang::Go && kindIs( type, "if_statement" ) )
    {
        return goLogOnlyShape( n, src, stmts );
    }
    if( lang == Lang::Rust && ( kindIs( type, "match_arm" ) || kindIs( type, "if_expression" ) ) )
    {
        return rustLogOnlyShape( n, src, stmts );
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
                ASSUME( tag == kShapeLogOnly || tag == kShapeRethrowOnly || tag == kShapeStub || tag == kShapeTodo, "shapeOfNode answers one of the four tags or none" );
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
