#pragma once

// testonlycallers.h — FOR-TONLY (card A2 carrier): the ONE home of "every indexed caller of this function is test code",
// read by --dead-code's test-only rows (verbs_quality.h) and by the --for lens's tonly="1" row attribute (CLI XML, --json and
// the MCP `for` twin). Both surfaces share the edge test (everyCallerIsTest), the entry-point vetting (dropTestOnlyEntryPoints)
// and the library-text name vetting (dropTestOnlySpelledInLibrary); --for adds the dispatch guards (an override, a std-protocol
// method) and the task gate that --dead-code, a list verb, has no use for. A second copy is what would drift.
//
// The rule is on CALLERS only. A caller is test code by filter.h isTestSymbol (the shared test-path rule plus the in-file
// test scopes); a by-name (hedged) edge from a library symbol is still a library caller, so it keeps the flag off; an edge a
// test reaches by name alone can only add a test caller. A function with NO caller is not test-only (that is "no callers",
// already spelled by an absent in=). A test symbol itself is never flagged.

#include "filter.h"
#include "graph.h"
#include "epmanifest.h"       // collectManifestsAbove — the manifest entry points an in-tree caller never spells
#include "docparse.h"         // lowerExtOf / isProseExtension — which skipped files could have held a caller
#include "model.h"
#include "quality.h"          // pythonGlobImportTails / pythonModuleTail — the glob-import half of the name vetting
#include "valuerefindex.h"    // ValueRefIndex::narrowFor / isValueReferenced — a name a library holds as a VALUE is a use
#include "infra/sortutil.h"   // svLess

#include <algorithm>
#include <cctype>
#include <cstdint>
#include <iterator>
#include <optional>
#include <string>
#include <string_view>
#include <vector>


namespace rw
{

// S4 (fix round 2): code SHIPPED under a test-named directory. isTestPath calls every file under a `test/` or `tests/` segment test code, and
// a package can ship a `test/` directory that library code runs (django.test: the test runner, the test client, the signal helpers; a
// `pkg/test/client.py`). A function only such a file calls is not "called only by tests": deleting it breaks the shipped runner. A file
// is SHIPPED TEST SUPPORT when (a) it is test by DIRECTORY alone (its own name is not test_*, *_test.*, *.spec.*, *.test.*, conftest*),
// (b) the test directory is nested below the root (`django/test/`, not a root `tests/` or a maven `src/test/`), and (c) a non-test file
// imports it, directly or through other such files (the include adjacency, so an `import`/`#include`/`require` edge); in a language
// whose imports that adjacency does not resolve it is shipped unless proven otherwise (conservative: no tonly). Lazy: the adjacency is
// built on the first nested-test-directory caller only.
inline bool testSupportNestedDirOnly( std::string_view rel ) noexcept
{
    if( !isTestPath( rel ) )
    {
        return false;
    }
    const std::size_t      sl = rel.rfind( '/' );
    const std::string_view fn = sl == std::string_view::npos ? rel : rel.substr( sl + 1 );
    if( sl == std::string_view::npos || isTestPath( fn ) || fn.starts_with( "conftest" ) )
    {
        return false;   // a root file, or test-NAMED: a test file
    }
    if( rel.starts_with( "src/test/" ) || rel.find( "/src/test/" ) != std::string_view::npos )
    {
        return false;   // the maven/gradle layout: src/test/ is the test tree
    }
    std::size_t pos = 0;
    for( std::size_t slash = rel.find( '/' ); slash != std::string_view::npos; pos = slash + 1, slash = rel.find( '/', pos ) )
    {
        const std::string_view seg = rel.substr( pos, slash - pos );
        if( seg == "test" || seg == "tests" || seg == "__tests__" )
        {
            return pos > 0;   // the FIRST test segment decides: a root-level one is the test tree, a nested one may be shipped
        }
    }
    return false;
}

class ShippedTestSupport
{
public:
    explicit ShippedTestSupport( const IngestResult& ing ) noexcept : ing_( ing ) {}

    bool contains( std::uint32_t fileId )
    {
        if( fileId >= ing_.files.size() || !testSupportNestedDirOnly( rootRelPath( ing_, fileId ) ) )
        {
            return false;
        }
        if( !built_ )
        {
            build();
        }
        return shipped_[ fileId ] != 0;
    }

private:
    // Python, JS/TS and C/C++: the languages whose import/include edges the adjacency resolves to files
    static bool importResolved( std::string_view ext ) noexcept
    {
        return ext == ".py" || ext == ".pyi" || ext == ".js" || ext == ".jsx" || ext == ".mjs" || ext == ".cjs" || ext == ".ts" || ext == ".tsx" || ext == ".mts"
            || ext == ".cts" || ext == ".c" || ext == ".h" || ext == ".cc" || ext == ".cpp" || ext == ".cxx" || ext == ".hpp" || ext == ".hh" || ext == ".hxx";
    }

    void build()
    {
        built_ = true;
        const std::uint32_t F = static_cast<std::uint32_t>( ing_.files.size() );
        shipped_.assign( F, 0 );
        std::vector<char> support( F, 0 );
        for( std::uint32_t f = 0; f < F; ++f )
        {
            const std::string_view rel = rootRelPath( ing_, f );
            if( testSupportNestedDirOnly( rel ) )
            {
                support[ f ] = 1;
                shipped_[ f ] = importResolved( docparse::lowerExtOf( rel ) ) ? 0 : 1;   // an unresolved language: shipped until proven otherwise
            }
        }
        const std::vector<std::vector<std::uint32_t>> adj = buildPreciseIncludeAdj( ing_, /*dedup=*/true );
        std::vector<std::uint32_t> work;
        for( std::uint32_t f = 0; f < F && f < adj.size(); ++f )
        {
            if( !isTestPath( rootRelPath( ing_, f ) ) )
            {
                work.push_back( f );   // every non-test file is a root of the reach
            }
        }
        while( !work.empty() )
        {
            const std::uint32_t f = work.back();
            work.pop_back();
            for( const std::uint32_t to : adj[ f ] )
            {
                if( to < F && support[ to ] != 0 && shipped_[ to ] == 0 )
                {
                    shipped_[ to ] = 1;
                    work.push_back( to );
                }
            }
        }
    }

    const IngestResult&  ing_;
    bool                 built_ = false;
    std::vector<char>    shipped_;
};

// A caller that is test code AS EVIDENCE. isTestSymbol also counts an in-file test scope (a Python module-level `def test_*`), and a
// LIBRARY function may carry that name (a `test_connection` health probe): when it sits outside a test path and a non-test symbol
// calls it, it is library code and its callee has a library caller. A test-scoped def nothing library calls stays a test.
inline bool callerIsTestEvidence( const IngestResult& ing, const Graph& g, NodeId caller, ShippedTestSupport& shipped )
{
    if( !isTestSymbol( ing, caller ) )
    {
        return false;
    }
    const Symbol& s = ing.symbols[ caller ];
    if( shipped.contains( s.fileId ) )
    {
        return false;   // S4: the caller is library code that lives under a test-named directory
    }
    if( s.testScope == 0 || s.fileId >= ing.files.size() || isTestPath( rootRelPath( ing, s.fileId ) ) )
    {
        return true;
    }
    const auto* ro = g.inEdges.rowOffsets();
    const auto* ci = g.inEdges.colIndices();
    return std::all_of( ci + ro[ caller ], ci + ro[ caller + 1 ], [ & ]( NodeId up ) { return isTestSymbol( ing, up ); } );
}

// D1 TESTONLY-DEAD: every in-edge of `id` comes from test code. all_of over an empty row is TRUE, so a caller that wants
// "test-only" (not "no callers") must also check the row is non-empty; computeTestOnlyCallers below does.
inline bool everyCallerIsTest( const IngestResult& ing, const Graph& g, NodeId id, ShippedTestSupport& shipped )
{
    const auto* ro = g.inEdges.rowOffsets();
    const auto* ci = g.inEdges.colIndices();
    return std::all_of( ci + ro[ id ], ci + ro[ id + 1 ], [ & ]( NodeId caller ) { return callerIsTestEvidence( ing, g, caller, shipped ); } );
}

// Was the whole tree indexed? A "every caller is a test" claim rests on having seen every caller: a memory-guard stop
// (partial crawl or parse) or a dropped oversize file in a language that carries calls can hide a library caller. Data and
// prose files (json/toml/yaml/markdown) carry no call, so an oversize lockfile does not switch the claim off.
inline bool testOnlyIndexWhole( const IngestResult& ing ) noexcept
{
    if( ing.memoryStop.isSet() )
    {
        return false;
    }
    return std::none_of( ing.skippedOversize.begin(), ing.skippedOversize.end(), []( const SkippedOversize& f )
    {
        const std::string ext = docparse::lowerExtOf( f.path );
        return !docparse::isProseExtension( ext ) && ext != ".json" && ext != ".toml" && ext != ".yaml" && ext != ".yml";
    } );
}

// Declined-call evidence (graph.h Graph::declinedSite*): a call the resolver refused to bind (an interface value, an untyped
// receiver, a name gate) gets no edge but names the definitions it could have meant. A declined call made by LIBRARY code that
// names a function is a library caller the edge pass cannot see, so that function is not "called only by tests" — the same
// evidence --callers prints as declined_calls= and <dc> rows. A decline made by a test symbol adds only a test caller.
// `unknown` is set when a library decline kept no candidate list (the uint32 offset degrade): then no function can be vetted.
inline std::vector<char> namedByLibraryDeclinedCall( const IngestResult& ing, const Graph& g, bool& unknown )
{
    std::vector<char> named( ing.symbols.size(), 0 );
    unknown = false;
    if( g.declinedSiteCaller.empty() )
    {
        return named;
    }
    std::vector<char> listFromLibrary( g.declinedListCallCount.size(), 0 );
    for( std::size_t site = 0; site < g.declinedSiteCaller.size(); ++site )
    {
        if( isTestSymbol( ing, g.declinedSiteCaller[ site ] ) )
        {
            continue;
        }
        if( const std::uint32_t list = g.declinedSiteList[ site ]; list == kNoDeclinedList )
        {
            unknown = true;
        }
        else if( list < listFromLibrary.size() )
        {
            listFromLibrary[ list ] = 1;
        }
    }
    for( std::size_t list = 0; list < listFromLibrary.size(); ++list )
    {
        for( std::uint32_t slot = g.declinedListOff[ list ]; listFromLibrary[ list ] && slot < g.declinedListOff[ list + 1 ]; ++slot )
        {
            if( const NodeId cand = g.declinedListCand[ slot ]; cand < named.size() )
            {
                named[ cand ] = 1;
            }
        }
    }
    return named;
}

// The names of methods an INTERFACE (SymKind::Interface: a Go/Java/C#/TypeScript interface) declares. A call through the interface
// value binds to that declaration, never to an implementing method, so an implementation only tests call directly still has
// library callers the graph cannot name (nfpm's RPM.Package, run by the CLI through the Packager interface). Every method
// carrying such a name is dispatch-reachable and keeps the flag off. Sorted by svLess for binary search.
inline std::vector<std::string_view> interfaceMethodNames( const IngestResult& ing )
{
    std::vector<std::string_view> ifaces;
    for( const Symbol& s : ing.symbols )
    {
        if( s.kind == SymKind::Interface )
        {
            ifaces.push_back( s.name );
        }
    }
    std::ranges::sort( ifaces, sortutil::svLess );
    std::vector<std::string_view> methods;
    for( const Symbol& s : ing.symbols )
    {
        if( s.kind == SymKind::Method && !s.scope.empty() && std::ranges::binary_search( ifaces, scopeLastSegment( s.scope ), sortutil::svLess ) )
        {
            methods.push_back( s.name );
        }
    }
    std::ranges::sort( methods, sortutil::svLess );
    methods.erase( std::ranges::unique( methods ).begin(), methods.end() );
    return methods;
}

// ── name vetting (moved verbatim from verbs_quality.h; --dead-code and --for call the same function) ──────────────────────────

// D1: is the occurrence of a name at `at` inside a comment-only line? Only --for asks (SpellVetting::skipCommentLines): a doc comment
// that names the function is documentation, not a use, and Go's doc-comment convention (`// rsaSign signs …`) would otherwise vet
// off every documented function. `hashIsComment`: `#` opens a comment in Python/Ruby but a directive (`#if name`) in C.
inline bool onCommentOnlyLine( std::string_view text, std::size_t at, bool hashIsComment ) noexcept
{
    const std::size_t lineStart = text.rfind( '\n', at == 0 ? 0 : at - 1 );
    std::size_t       i         = lineStart == std::string_view::npos ? 0 : lineStart + 1;
    while( i < at && ( text[ i ] == ' ' || text[ i ] == '\t' ) )
    {
        ++i;
    }
    const std::string_view rest = text.substr( i, 2 );
    if( rest == "//" || ( hashIsComment && !rest.empty() && rest[ 0 ] == '#' ) )
    {
        return true;
    }
    if( rest == "/*" )
    {   // `/* note */ f( x );` is a line of code with a comment in front: a comment-only line has nothing after the closing `*/`
        const std::size_t       eol    = std::min( text.find( '\n', i ), text.size() );
        const std::string_view  line   = text.substr( i, eol - i );
        const std::size_t       closed = line.find( "*/", 2 );
        if( closed == std::string_view::npos )
        {
            return true;
        }
        const std::size_t code = line.find_first_not_of( " \t\r", closed + 2 );
        return code == std::string_view::npos || line.substr( code, 2 ) == "//";
    }
    // A `*`-led line is a block-comment continuation only INSIDE an open `/* … */` and only in a language that has one: in Python/Ruby it
    // is a starred assignment or call (`*head, tail = options.f( x )`), and in C a dereference (`*p = f()`) or a continued product.
    if( hashIsComment || rest.empty() || rest[ 0 ] != '*' || ( rest.size() > 1 && rest[ 1 ] != ' ' && rest[ 1 ] != '\t' && rest[ 1 ] != '/' && rest[ 1 ] != '\n' && rest[ 1 ] != '\r' ) )
    {
        return false;
    }
    const std::string_view before = text.substr( 0, i );
    const std::size_t      open   = before.rfind( "/*" );
    const std::size_t      close  = before.rfind( "*/" );
    return open != std::string_view::npos && ( close == std::string_view::npos || close < open );
}

// D1: `name` spelled whole-word in `text` (file `fileId`) anywhere but inside the signature span of one of `rows` it names.
inline bool spelledOutsideOwnSignature( const IngestResult& ing, std::string_view text, std::uint32_t fileId, std::string_view name,
                                        const std::vector<NodeId>& rows, bool skipCommentLines = false, bool hashIsComment = false ) noexcept
{
    const auto isIdent = []( char c ) noexcept { return std::isalnum( static_cast<unsigned char>( c ) ) || c == '_'; };
    const auto ownSignature = [ & ]( std::size_t at )
    {
        return std::ranges::any_of( rows, [ & ]( NodeId id )
        {
            const Symbol& def = ing.symbols[ id ];
            return def.fileId == fileId && def.name == name && at >= def.sigStartByte && at < def.sigEndByte;
        } );
    };
    for( std::size_t at = text.find( name ); at != std::string_view::npos; at = text.find( name, at + 1 ) )
    {
        const std::size_t end      = at + name.size();
        const bool        bounded  = ( at == 0 || !isIdent( text[ at - 1 ] ) ) && ( end == text.size() || !isIdent( text[ end ] ) );
        if( bounded && !ownSignature( at ) && !( skipCommentLines && onCommentOnlyLine( text, at, hashIsComment ) ) )
        {
            return true;
        }
    }
    return false;
}

// D1: the text a library file contributes to the name vetting, or nullopt when it contributes none: a test file, a prose file
// (markdown, .txt: a mention there is documentation, not a use) or an unreadable one. A notebook is CODE in a JSON container,
// so its code and markdown cells are read as text (docparse::extractIpynb) — a def only a notebook calls is in use.
// CR 4396503875: an EXCLUDED file (libraryFileExcluded: a test or a prose file) and an UNREADABLE one both return nullopt here,
// and the vetting tells them apart through libraryFileExcluded — a failed read is not an exclusion.
inline bool libraryFileExcluded( const IngestResult& ing, std::uint32_t fileId )
{
    const std::string_view rel = rootRelPath( ing, fileId );
    const std::string      ext = docparse::lowerExtOf( rel );
    return isTestPath( rel ) || ( ext != ".ipynb" && docparse::isProseExtension( ext ) );
}
inline std::optional<std::string> libraryFileText( const IngestResult& ing, std::uint32_t fileId )
{
    if( libraryFileExcluded( ing, fileId ) )
    {
        return std::nullopt;
    }
    const std::string          ext   = docparse::lowerExtOf( rootRelPath( ing, fileId ) );
    std::optional<std::string> bytes = docparse::detail::readWholeFile( diskPath( ing, fileId ) );
    if( bytes && ext == ".ipynb" )
    {
        return docparse::extractIpynb( *bytes );
    }
    return bytes;
}

// D1 name vetting: drop every row whose name a NON-test, non-prose indexed file spells whole-word outside the def's own
// signature, and every row whose module a library file glob-imports (`from ._impl import *` re-exports the module's public
// names through the package). Text, not references: an aliased import (`from m import dump as binary_dump`), a module-level
// call (`options.f()`), a getattr string and a bound `self.m` / `this.m` value carry no edge to the def, and a comment or string
// mention costs only a missed row, never a used function on the list. Each file is read once, uncached (the scan may cover the
// whole tree). A library file that cannot be read vets nothing: `unread` lists them and `testOnly` is emptied (the third state:
// no claim). The survivors keep their order; --dead-code re-sorts them into its own row order.
inline void dropTestOnlySpelledInLibrary( const IngestResult& ing, std::vector<NodeId>& testOnly, std::vector<std::uint32_t>& unread,
                                          bool skipCommentLines = false )
{
    std::vector<std::string_view> names;
    names.reserve( testOnly.size() );
    for( NodeId id : testOnly ) { names.push_back( ing.symbols[ id ].name ); }
    std::ranges::sort( names, sortutil::svLess );
    names.erase( std::ranges::unique( names ).begin(), names.end() );
    std::vector<std::string_view> spelled;
    std::vector<std::string>      globbed;   // module tails a library file glob-imports (owned: the file text is gone after its turn)
    for( std::uint32_t fileId = 0; fileId < ing.files.size(); ++fileId )
    {
        if( libraryFileExcluded( ing, fileId ) )
        {
            continue;
        }
        const std::optional<std::string> text = libraryFileText( ing, fileId );
        if( !text )
        {   // CR 4396503875: a file whose uses are unknown vets nothing, so no test-only claim is made on its behalf
            unread.push_back( fileId );
            continue;
        }
        const std::string ext         = docparse::lowerExtOf( rootRelPath( ing, fileId ) );
        const bool        hashComment = ext == ".py" || ext == ".pyi" || ext == ".rb";
        for( std::string_view name : names )
        {
            if( spelledOutsideOwnSignature( ing, *text, fileId, name, testOnly, skipCommentLines, hashComment ) )
            {
                spelled.push_back( name );
            }
        }
        for( std::string_view tail : quality::pythonGlobImportTails( *text ) )
        {
            globbed.emplace_back( tail );
        }
    }
    if( !unread.empty() )
    {
        testOnly.clear();
        return;
    }
    std::ranges::sort( spelled, sortutil::svLess );
    std::ranges::sort( globbed, sortutil::svLess );
    std::erase_if( testOnly, [ & ]( NodeId id )
    {
        const Symbol& def = ing.symbols[ id ];
        return std::ranges::binary_search( spelled, std::string_view( def.name ), sortutil::svLess )
            || std::ranges::binary_search( globbed, quality::pythonModuleTail( rootRelPath( ing, def.fileId ) ), sortutil::svLess );
    } );
}

// ── --for dispatch guards: a method something OTHER than a traced call reaches ────────────────────────────────────────────────

// The names of the types that have any base: a class that extends or implements something, a struct with an `impl Trait for`, in
// the tree or outside it (the base need not be indexed). A method of such a type may be an override or a trait implementation, and
// the call that reaches it goes through the base (`self.get_handler()` in the base class, `const Base&`, `fmt::Display`), which
// the graph binds to the BASE's method, not to this one. Sorted by svLess for binary search.
inline std::vector<std::string_view> typesWithBases( const IngestResult& ing )
{
    std::vector<std::string_view> types;
    for( const Reference& r : ing.references )
    {
        if( !r.isInherit )
        {
            continue;
        }
        // Rust stashes the derived type NAME in `qualifier`; every other language's inherit ref sits inside the derived class header
        std::string_view name = !r.qualifier.empty() ? std::string_view( r.qualifier )
                              : r.fromSymbol < ing.symbols.size() ? std::string_view( ing.symbols[ r.fromSymbol ].name ) : std::string_view();
        name = scopeLastSegment( name );
        if( !name.empty() )
        {
            types.push_back( name );
        }
    }
    std::ranges::sort( types, sortutil::svLess );
    types.erase( std::ranges::unique( types ).begin(), types.end() );
    return types;
}

// Go's standard-library protocols: a method of one of these names is called by fmt, errors, sort, encoding/*, net/http, io and
// database/sql through an interface the tree does not declare (`fmt.Println( code )` runs RelayCode.String).
inline bool goStdProtocolMethod( std::string_view name ) noexcept
{
    static constexpr std::string_view kExact[] = {
        // fmt, errors, sort, database/sql, net/http
        "String", "Error", "Format", "GoString", "ServeHTTP", "Len", "Less", "Swap", "Unwrap", "Is", "As", "Scan", "Value", "Timeout", "Temporary",
        "Header", "WriteHeader", "Flush", "Hijack", "Push", "Pop", "RoundTrip", "Cookies", "SetCookies",
        // io, bufio, io/fs: Reader/Writer/Closer/Seeker and their At/Byte/Rune/String/From/To forms
        "Read", "Write", "Close", "Seek", "ReadAt", "WriteAt", "ReadFrom", "WriteTo", "ReadByte", "WriteByte", "UnreadByte", "ReadRune", "WriteRune",
        "UnreadRune", "WriteString", "Open", "Stat", "ReadDir", "ReadFile", "Sys", "Info", "IsDir", "Name", "Size", "Mode", "ModTime", "Type",
        // flag.Value / flag.Getter, encoding/gob, encoding.Text*/Binary*, hash.Hash, sync.Locker, context.Context, net, log/slog, go/ast
        "Set", "Get", "GobEncode", "GobDecode", "AppendText", "AppendBinary", "Sum", "Reset", "BlockSize", "Lock", "Unlock", "Deadline", "Done", "Err",
        "Accept", "Addr", "LocalAddr", "RemoteAddr", "Network", "SetDeadline", "SetReadDeadline", "SetWriteDeadline", "Enabled", "Handle", "WithAttrs",
        "WithGroup", "LogValue", "Visit" };
    return std::ranges::find( kExact, name ) != std::end( kExact ) || name.starts_with( "Marshal" ) || name.starts_with( "Unmarshal" );
}

// The innermost type (class, struct, interface …) that holds a symbol, by source span, for a method whose stored scope is empty: TS/JS
// methods, and Java/C#/Kotlin/Swift members, carry no scope, so the base guard must find the class from where the method sits.
class EnclosingTypes
{
public:
    explicit EnclosingTypes( const IngestResult& ing )
        : ing_( ing ), byFile_( symbolsByFileInIdOrder( ing, []( const Symbol& t ) { return t.kind != SymKind::Other && namespaceCompatible( RefRole::Type, t.kind ); } ) )
    {
    }

    std::string_view of( const Symbol& s ) const
    {
        const Symbol* best = nullptr;
        if( s.fileId < byFile_.size() )
        {
            for( const NodeId id : byFile_[ s.fileId ] )
            {
                const Symbol& t = ing_.symbols[ id ];
                if( t.id != s.id && t.sigStartByte <= s.sigStartByte && s.endByte <= t.endByte && ( best == nullptr || t.sigStartByte >= best->sigStartByte ) )
                {
                    best = &t;
                }
            }
        }
        return best == nullptr ? std::string_view() : std::string_view( best->name );
    }

private:
    const IngestResult&  ing_;
    SymbolsByFile        byFile_;
};

// May a call reach this METHOD (a Method, or a Function with an owner scope: Python/Ruby members) without an edge to it? Off for: a method of a type that has any base (override / trait impl), a
// Python dunder (the interpreter calls it), a Go method named for a std protocol. A plain function is never asked.
inline bool methodDispatchedElsewhere( const IngestResult& ing, const Symbol& s, const std::vector<std::string_view>& basedTypes, const EnclosingTypes& enclosing )
{
    // Python and Ruby members are SymKind::Function with an owner scope (ingest_metrics.h: @definition.function never marks them Method)
    if( s.kind != SymKind::Method && !( s.kind == SymKind::Function && !s.scope.empty() ) )
    {
        return false;
    }
    if( s.name.size() > 4 && s.name.starts_with( "__" ) && s.name.ends_with( "__" ) )
    {
        return true;
    }
    if( docparse::lowerExtOf( rootRelPath( ing, s.fileId ) ) == ".go" && goStdProtocolMethod( s.name ) )   // by extension: the language-identity ratchet counts Lang:: comparisons
    {
        return true;
    }
    // the owner type: the stored scope, else (TS/JS/Java/C#/Kotlin/Swift members store none) the class whose body holds the method
    const std::string_view owner = !s.scope.empty() ? scopeLastSegment( s.scope ) : enclosing.of( s );
    return !owner.empty() && std::ranges::binary_search( basedTypes, owner, sortutil::svLess );
}

// A def a decorator, annotation or attribute sits on: `@GrpcMethod(...)` / `@app.route(...)` / `@Override` / `#[get("/")]` / C# `[HttpGet]`.
// A framework registers such a def and calls it (a NestJS gRPC handler, a Flask route, a Spring override); the call is no source line, so
// "every indexed caller is a test" cannot be said of it. Read from the text just before the def's signature (modifier words may sit between).
inline bool precededByDecorator( std::string_view text, std::size_t sigStart ) noexcept
{
    const auto isIdent  = []( char c ) noexcept { return std::isalnum( static_cast<unsigned char>( c ) ) || c == '_' || c == '$' || c == '.'; };
    const auto skipBack = [ & ]( std::size_t i ) noexcept
    {
        while( i > 0 && std::isspace( static_cast<unsigned char>( text[ i - 1 ] ) ) ) { --i; }
        return i;
    };
    const auto matchOpen = [ & ]( std::size_t close, char open, char shut ) noexcept   // index of the bracket opening the one closed at `close`, else npos
    {
        int depth = 0;
        for( std::size_t j = close + 1; j-- > 0; )
        {
            depth += text[ j ] == shut ? 1 : text[ j ] == open ? -1 : 0;
            if( depth == 0 ) { return j; }
        }
        return std::string_view::npos;
    };
    static constexpr std::string_view kModifiers[] = { "public", "private", "protected", "static", "async", "readonly", "override", "abstract", "export",
                                                       "default", "final", "virtual", "unsafe", "pub" };
    std::size_t i = std::min( sigStart, text.size() );
    for( int hop = 0; hop < 6; ++hop )
    {
        i = skipBack( i );
        if( i == 0 ) { return false; }
        const char c = text[ i - 1 ];
        if( c == ')' || c == ']' )
        {
            const std::size_t open = matchOpen( i - 1, c == ')' ? '(' : '[', c );
            if( open == std::string_view::npos ) { return false; }
            std::size_t b = skipBack( open );
            if( c == ']' )
            {   // `#[get("/")]` (Rust), `[HttpGet]` on a line of its own (C#); `x[ i ]` is an index
                return open > 0 && ( text[ open - 1 ] == '#' || ( b < open && text.substr( b, open - b ).find( '\n' ) != std::string_view::npos ) );
            }
            std::size_t a = b;
            while( a > 0 && isIdent( text[ a - 1 ] ) ) { --a; }
            return a < b && a > 0 && text[ a - 1 ] == '@';
        }
        if( !isIdent( c ) ) { return false; }
        std::size_t a = i;
        while( a > 0 && isIdent( text[ a - 1 ] ) ) { --a; }
        if( a > 0 && text[ a - 1 ] == '@' ) { return true; }   // a bare decorator / annotation: `@Override`, `@staticmethod`
        if( std::ranges::find( kModifiers, text.substr( a, i - a ) ) == std::end( kModifiers ) ) { return false; }
        i = a;
    }
    return false;
}

// FOR-TONLY fix round 2: drop every row whose def carries a decorator / annotation / attribute (precededByDecorator). --dead-code keeps its
// own Python rule (pythonDecoratedDef, decorated-excluded=); --for asks it of every language. An unreadable file drops its rows.
inline void dropDecoratedDefs( const IngestResult& ing, std::vector<NodeId>& testOnly )
{
    std::erase_if( testOnly, [ & ]( NodeId id )
    {
        const Symbol&                    def  = ing.symbols[ id ];
        const std::optional<std::string> text = docparse::detail::readWholeFile( diskPath( ing, def.fileId ) );
        return !text || precededByDecorator( *text, def.sigStartByte );
    } );
}

// ── --for task gate G3: the attribute rides a row only where the question can use it ──────────────────────────────────────────

inline bool tonlyUseWord( std::string_view w ) noexcept
{
    static constexpr std::string_view kExact[]  = { "use", "used", "uses", "usage", "unused", "dead", "call", "calls", "called", "caller", "callers",
                                                    "test", "tests", "tested", "testing", "coverage", "covered", "obsolete" };
    static constexpr std::string_view kPrefix[] = { "reach", "remov", "delet", "deprecat", "refactor", "renam" };
    return std::ranges::find( kExact, w ) != std::end( kExact )
        || std::ranges::any_of( kPrefix, [ & ]( std::string_view p ) { return w.starts_with( p ); } );
}

// Does the path token `t` name `lp` at SEGMENT boundaries: `t` sits in `lp` with a `/` (or an end) on both sides, so `internal/sign` names
// internal/sign/rsa.go and `hono` names nothing under src/hono-base.ts. A token that merely starts or ends inside a longer segment names no file.
inline bool namesWholeSegments( std::string_view lp, std::string_view t ) noexcept
{
    for( std::size_t at = lp.find( t ); at != std::string_view::npos; at = lp.find( t, at + 1 ) )
    {
        const std::size_t end = at + t.size();
        if( ( at == 0 || lp[ at - 1 ] == '/' ) && ( end == lp.size() || lp[ end ] == '/' ) )
        {
            return true;
        }
    }
    return false;
}

// What the task says: a use-shaped word (is X used / safe to remove / who calls / tested), the row's bare name as a token, or a
// path-shaped token (a `/` or a short extension) that names the row's file or directory. A row on a question with none of the
// three is context the question did not ask for (measured: 70 of 70 fires on explanatory questions but the 12 that were GAIN).
class TonlyTaskGate
{
public:
    explicit TonlyTaskGate( std::string_view task )
    {
        const auto isWord = []( char c ) noexcept { return std::isalnum( static_cast<unsigned char>( c ) ) || c == '_'; };
        const auto isPath = [ & ]( char c ) noexcept { return isWord( c ) || c == '.' || c == '/' || c == '-'; };
        lower_ = queryshape::detail::lowerAscii( task );
        std::string_view prev;
        for( std::size_t i = 0; i < lower_.size(); )
        {
            if( !isWord( lower_[ i ] ) ) { ++i; continue; }
            std::size_t j = i;
            while( j < lower_.size() && isWord( lower_[ j ] ) ) { ++j; }
            const std::string_view w( lower_.data() + i, j - i );
            useWord_ = useWord_ || tonlyUseWord( w ) || ( prev == "safe" && w == "to" );
            idents_.push_back( w );
            prev = w;
            i = j;
        }
        std::ranges::sort( idents_, sortutil::svLess );
        for( std::size_t i = 0; i < lower_.size(); )
        {
            if( !isPath( lower_[ i ] ) ) { ++i; continue; }
            std::size_t j = i;
            while( j < lower_.size() && isPath( lower_[ j ] ) ) { ++j; }
            const std::string_view tok( lower_.data() + i, j - i );
            i = j;
            const std::size_t dot = tok.rfind( '.' );
            const bool        ext = dot != std::string_view::npos && tok.size() - dot - 1 >= 1 && tok.size() - dot - 1 <= 4 && dot + 1 < tok.size();
            if( tok.size() > 2 && ( tok.find( '/' ) != std::string_view::npos || ext ) )
            {
                const std::size_t a = tok.find_first_not_of( "./" );
                const std::size_t b = tok.find_last_not_of( "./" );
                if( a != std::string_view::npos )
                {
                    paths_.push_back( tok.substr( a, b - a + 1 ) );
                }
            }
        }
    }

    bool keeps( const IngestResult& ing, const Symbol& s ) const
    {
        if( useWord_ )
        {
            return true;
        }
        const std::string name = queryshape::detail::lowerAscii( s.name );
        // the bare name as a token, or (a name of 6+ characters, so `get` / `run` cannot match inside any word) spelled inside a longer
        // task word: `onRequestHookRunner` names hookRunner
        if( std::ranges::binary_search( idents_, std::string_view( name ), sortutil::svLess ) || ( name.size() >= 6 && lower_.find( name ) != std::string::npos ) )
        {
            return true;
        }
        if( !s.scope.empty() && ( lower_.find( queryshape::detail::lowerAscii( s.scope ) + "." + name ) != std::string::npos || lower_.find( queryshape::detail::lowerAscii( s.scope ) + "::" + name ) != std::string::npos ) )
        {
            return true;
        }
        const std::string_view path = rootRelPath( ing, s.fileId );
        const std::string_view base = path.substr( path.rfind( '/' ) == std::string_view::npos ? 0 : path.rfind( '/' ) + 1 );
        const std::string      lp   = queryshape::detail::lowerAscii( path );
        return std::ranges::any_of( paths_, [ & ]( const std::string_view& t )
        {
            const std::string_view tb = t.substr( t.rfind( '/' ) == std::string_view::npos ? 0 : t.rfind( '/' ) + 1 );
            return namesWholeSegments( lp, t ) || queryshape::detail::lowerAscii( base ) == tb;
        } );
    }

private:
    std::string                   lower_;
    std::vector<std::string_view> idents_;
    std::vector<std::string_view> paths_;
    bool                          useWord_ = false;
};

// ── the predicate ─────────────────────────────────────────────────────────────────────────────────────────────────────────────

// D1 fix round 1 (F2): drop every row a package manifest names as an entry point. setup.cfg and pyproject.toml entry-point
// tables (`console_scripts`, plugin groups) call their target by `module:attr`, an invocation no source file spells; the
// crawl does not index setup.cfg, so the name vetting never sees it. epmanifest.h already reads both formats (EP-MANIFEST); this
// asks it for the manifests above the candidates' files and keeps off any def whose name is a target's attribute (last dotted
// segment). The wide side on purpose: a same-named def in another module is dropped too, never listed.
inline void dropTestOnlyEntryPoints( const IngestResult& ing, std::vector<NodeId>& testOnly )
{
    using namespace rw;
    std::vector<std::string>        seenDirs;
    std::vector<epdetail::Manifest> manifests;
    for( NodeId id : testOnly )
    {
        epdetail::collectManifestsAbove( ing, ing.symbols[ id ].fileId, seenDirs, manifests );
    }
    const auto isEntryAttr = [ & ]( std::string_view name )
    {
        return std::ranges::any_of( manifests, [ & ]( const epdetail::Manifest& m )
        {
            return std::ranges::any_of( m.entries, [ & ]( const EpEntry& e )
            {
                const std::size_t colon = e.target.find( ':' );
                if( colon == std::string::npos ) { return false; }
                const std::string_view attr = std::string_view( e.target ).substr( colon + 1 );
                return attr.substr( attr.rfind( '.' ) == std::string_view::npos ? 0 : attr.rfind( '.' ) + 1 ) == name;
            } );
        } );
    };
    std::erase_if( testOnly, [ & ]( NodeId id ) { return isEntryAttr( ing.symbols[ id ].name ); } );
}

// The edge half of FOR-TONLY: of `wanted`, the ids that pass every check but the library-text vetting (see computeTestOnlyCallers).
inline std::vector<NodeId> testOnlyEdgeCandidates( const IngestResult& ing, const Graph& g, const std::vector<char>& declined,
                                                   const std::vector<NodeId>& wanted )
{
    ShippedTestSupport  shipped( ing );
    const auto*         ro = g.inEdges.rowOffsets();
    const auto          ifaceMethods = interfaceMethodNames( ing );
    const auto          basedTypes   = typesWithBases( ing );
    const EnclosingTypes enclosing( ing );
    std::vector<NodeId> cands;
    for( const NodeId id : wanted )
    {
        const Symbol& s        = ing.symbols[ id ];
        const bool    callable = s.kind == SymKind::Function || s.kind == SymKind::Method;
        const bool    declares = s.kind == SymKind::Method && std::ranges::binary_search( ifaceMethods, std::string_view( s.name ), sortutil::svLess );
        if( callable && ro[ id + 1 ] != ro[ id ] && !isTestSymbol( ing, id ) && declined[ id ] == 0 && !declares
            && !methodDispatchedElsewhere( ing, s, basedTypes, enclosing ) && everyCallerIsTest( ing, g, id, shipped ) )
        {
            cands.push_back( id );
        }
    }
    return cands;
}

// The ranked head a --for answer can print a <d> row for: `surface` in rank order, rank > 0, at most `limit` rows. The tonly verdict
// is computed for these ids alone — the library-text vetting reads the tree, so it is paid for the rows that can carry the flag.
template<class Rank>
inline std::vector<NodeId> tonlyHeadIds( const std::vector<NodeId>& surface, const Rank& rank, std::size_t limit )
{
    std::vector<NodeId> out;
    std::copy_if( surface.begin(), surface.begin() + static_cast<std::ptrdiff_t>( std::min( surface.size(), limit ) ), std::back_inserter( out ),
                  [ & ]( NodeId id ) { return rank[ id ] > 0; } );
    return out;
}

// FOR-TONLY: per symbol, 1 iff it is a function or method ON THE RANKED HEAD (`head`) that the question can use (TonlyTaskGate), has
// at least one indexed caller, every caller is a test, is not a method something else dispatches to (typesWithBases, std protocols),
// no library call the resolver declined names it, no package manifest names it as an entry point, no library code holds it as a
// value (ValueRefIndex) or spells its name (dropTestOnlySpelledInLibrary: a module-attribute call, a getattr string, a bound
// method), it is not a method an interface declares, and the index is whole. Empty vector (no flag anywhere) when the index is cut,
// a library file is unreadable or nothing qualifies. Cheap checks first; the tree read runs over the few survivors.
inline std::vector<std::uint8_t> computeTestOnlyCallers( const IngestResult& ing, const Graph& g, std::string_view task,
                                                         const std::vector<NodeId>& head )
{
    std::vector<std::uint8_t> flags;
    bool                      declinedUnknown = false;
    if( head.empty() || !testOnlyIndexWhole( ing ) || g.inEdges.rowOffsets() == nullptr )
    {
        return flags;
    }
    const TonlyTaskGate gate( task );
    std::vector<NodeId> wanted;
    for( const NodeId id : head )
    {
        if( id < ing.symbols.size() && gate.keeps( ing, ing.symbols[ id ] ) )
        {
            wanted.push_back( id );
        }
    }
    if( wanted.empty() )
    {
        return flags;
    }
    const std::vector<char> declined = namedByLibraryDeclinedCall( ing, g, declinedUnknown );
    std::vector<NodeId>     cands    = declinedUnknown ? std::vector<NodeId>{} : testOnlyEdgeCandidates( ing, g, declined, wanted );
    if( !cands.empty() )
    {
        dropTestOnlyEntryPoints( ing, cands );   // a package manifest's console_scripts / plugin target is an in-tree call no source spells
        dropDecoratedDefs( ing, cands );         // a decorated / annotated def is registered with a framework that calls it
    }
    if( cands.empty() )
    {
        return flags;
    }
    std::vector<NodeId> unvalued;
    {
        std::vector<std::string_view> names;
        names.reserve( cands.size() );
        for( const NodeId id : cands )
        {
            names.push_back( ing.symbols[ id ].name );
        }
        std::ranges::sort( names, sortutil::svLess );
        names.erase( std::ranges::unique( names ).begin(), names.end() );
        const ValueRefIndex vri = ValueRefIndex::narrowFor( ing, names );
        std::ranges::copy_if( cands, std::back_inserter( unvalued ), [ & ]( NodeId id ) { return !vri.isValueReferenced( id ); } );
    }
    std::vector<std::uint32_t> unread;
    dropTestOnlySpelledInLibrary( ing, unvalued, unread, /*skipCommentLines=*/true );   // an unreadable library file empties the list
    if( unvalued.empty() )
    {
        return flags;
    }
    flags.assign( ing.symbols.size(), 0u );
    for( const NodeId id : unvalued )
    {
        flags[ id ] = 1u;
    }
    return flags;
}

}   // namespace rw
