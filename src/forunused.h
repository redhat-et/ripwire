#pragma once
// forunused.h — UNUSED-IN-FILE (practice-60 group E, widens IDEAS A2 TESTONLY-DEAD): the --for table for "which public X in <file> are unused".
//
// --dead-code answers a different question on purpose: internal linkage plus zero callers, so `--dead-code=util/network.py` says
// count=0 about a file of public functions. It keeps that meaning. This table takes a --for subject with an unused cue that names a file
// or a directory, and prints each public def of the file with the evidence for and against a use.
//
// THE ROW SAYS WHAT WAS PROVEN, because this answer tells an agent code is safe to delete, and a wrong row is expensive. The verdict words:
//   used       a non-test caller in another file bound by more than the name, or an in-file chain from one (or from the file's top level).
//              Proves one such caller. Not that the caller itself is live.
//   unknown    something may reach it that this tool cannot follow; why= names each reason. NOT a claim either way.
//   file-only  only same-file references, none chained from a used or unknown def. Proves no reference from another file.
//   test-only  every reference found is in a test. Proves no non-test reference in this tree, nothing about a consumer outside it (why=api).
//   unused     the name appears in no text file under the root (indexed or not, vendored or generated included) outside its own definition, its
//              declarations and comments, and no row of the table below applies. Proves that about this tree only: a consumer outside it is
//              not seen (why=api names the surfaces that have them). A file the scan could not read makes every such row `unknown why=unseen`.
// The evidence runs in that order and a stronger word never hides a hedge: `used` wins, then any why= makes `unknown`.
//
// WHY THE TEXT SCAN. The graph is a floor: a member call on an unproved receiver, a table, a string lookup are no edge. So no row says
// unused from zero callers alone. One pass over every indexed file reads each name as a word: a non-test word that no resolved edge
// explains makes the row `unknown`, with its site. This is what makes the class of false row small and language-independent.
//
// THE HONESTY TABLE, per language (kept here, in the legend and in docs/COMMANDS.md; test/forunusedcheck.sh pins each row):
//   why=         reads as unknown when                                                Python  TS/JS  Go  Rust  C/C++
//   name         a non-test code word names it and no edge is resolved                  x       x    x    x     x     (member call, callback, value)
//   by-name      its only non-test callers were bound by name alone or split            x       x    x    x     x
//   declined     the resolver declined a call whose candidates hold it                  x       x    x    x     x
//   value        a table, field or argument holds it (the value index)                  x       x    x    x     x     (registries)
//   string       a string literal is exactly its name                                   x       x    x    x     x     (__all__, getattr, MethodByName)
//   built-name   a string or macro builds names it could be: "on_{x}", `on_${x}`, a##b  x       x    x    x     x
//   import       a non-test import or re-export names it, and nothing else does         x       x    x    x     x
//   barrel       its file is star re-exported: `export *`, `from m import *`, `pub use m::*`  x  x         x
//   dispatch     a method a base, trait or interface may call                           class(bases) extends/implements  every method  (not pub)  virtual/override/base
//   framework    the language or a framework calls it with no call in the tree          decorator, dunder, runner hook, pytest_*  decorator  init, Test*, //export  #[attr], extern "C", main  __attribute__, extern "C", main, ctor
//   api          a surface consumers outside this tree may use                          -       -    exported outside internal/, not package main  pub in a lib crate  a header under include/
//   members      its members are reached without naming it: a member row has evidence   x       x    x    x     x     (and every unscoped C/C++ enum)
//   manifest     a build or package file beside it names it                             pyproject, setup.cfg  package.json  -  Cargo.toml  CMakeLists, Makefile, BUILD
//   unseen       a text file under the root could not be read, or the walk hit its cap   x       x    x    x     x     (the block says unseen=N)
// Beyond the table: a Python class whose base defines `__init_subclass__` or a metaclass reads dispatch; a file under a route directory
// (pages/, app/, routes/, views.py ...) reads framework; a literal joined by `+` or `%` beside a lookup is a built-name stem; a dynamic
// import of a directory (`import(`./routes/${n}`)`, `import_module("pkg.plugins." + n)`) reads built-name on every def of the directory.
//
// PRESENT-ONLY: no cue or no file, no block, and the answer is byte-identical. The block takes its own allowance, like the file page: it draws
// nothing from the bytes that fund bodies. Caps are runaway guards, each cut disclosed.
#include "filter.h" // isTestPath, isTestSymbol
#include "forfilepage.h" // resolveFileAnchors, FileAnchor, filepage::fileDefsInLineOrder, trimWordPunct
#include "infra/namesplit.h" // isIdentChar
#include "graph.h" // Graph, edgeNameOnly, declinedCallsNaming, graphCountFloorAttrXml
#include "langfacts.h" // langFacts(l).hashComment
#include "lexical.h" // splitRouteWords, routeLower
#include "lintrules.h" // langOfPath
#include "model.h"
#include "quality.h" // pythonDecoratedDef, pythonRunnerRoot, languageInvokedSymbol, symbolHasStaticLinkage
#include "serialize.h" // escapeXml
#include "taskroute.h" // taskroute::isOneOf
#include "valuerefindex.h" // ValueRefIndex::isValueReferenced

#include <algorithm>
#include <array>
#include <cstdint>
#include <cstdlib>
#include <filesystem>
#include <format>
#include <optional>
#include <span>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

namespace rw
{

// Runaway guards (knob census ADDENDUM), never size targets: every cut is disclosed.
inline constexpr std::size_t kForUnusedRowsPerFile = 150; // printed rows of one file (shown= capped=1 and the counts stay whole)
inline constexpr std::size_t kForUnusedDirFiles = 6; // files of a named directory given a table
inline constexpr std::size_t kForUnusedMaxBytes = 32768; // the whole block: no further file starts past it
inline constexpr std::size_t kForUnusedSitesShown = 2; // at= sites on one row
inline constexpr std::size_t kForUnusedExtraFileBytes = std::size_t( 32 ) << 20; // one unindexed text file; a larger one is unseen
inline constexpr std::size_t kForUnusedExtraBytes = std::size_t( 768 ) << 20; // all unindexed text read in one answer; past it the rest is unseen
inline constexpr std::size_t kForUnusedExtraFiles = 400000; // unindexed files visited in one answer
inline constexpr std::size_t kForUnusedMinPrefix = 3; // a built-name prefix shorter than this names too much to read as evidence

inline bool forUnusedOn()
{
    return std::getenv( "RIPWIRE_NO_UNUSED_TABLE" ) == nullptr;
}

namespace unusedfile
{

// Hedge bits, in the order why= prints them.
enum Why : std::uint16_t
{
    kWhyName = 1,
    kWhyByName = 2,
    kWhyDeclined = 4,
    kWhyValue = 8,
    kWhyString = 16,
    kWhyBuilt = 32,
    kWhyImport = 64,
    kWhyBarrel = 128,
    kWhyDispatch = 256,
    kWhyFramework = 512,
    kWhyApi = 1024,
    kWhyManifest = 2048,
    kWhyInFile = 4096,
    kWhyMembers = 8192,
    kWhyUnseen = 16384
};
inline constexpr std::array<std::pair<std::uint16_t, std::string_view>, 15> kWhyWords = { { { kWhyName, "name" }, { kWhyByName, "by-name" }, { kWhyDeclined, "declined" }, { kWhyValue, "value" }, { kWhyString, "string" }, { kWhyBuilt, "built-name" }, { kWhyImport, "import" }, { kWhyBarrel, "barrel" }, { kWhyDispatch, "dispatch" }, { kWhyFramework, "framework" }, { kWhyApi, "api" }, { kWhyManifest, "manifest" }, { kWhyInFile, "in-file" }, { kWhyMembers, "members" }, { kWhyUnseen, "unseen" } } };

// isTestPath plus the support trees a test run alone loads. A caller here reads as a test: row at= names the path, so a reader can see it.
inline bool isTestLikePath( std::string_view p ) noexcept
{
    if( isTestPath( p ) || p.ends_with( "conftest.py" ) )
    {
        return true;
    }
    static constexpr std::array<std::string_view, 9> kDirs = { "harness/", "testRunner/", "testing/", "testutil/", "testutils/", "test-utils/", "test_utils/", "testdata/", "e2e/" };
    return std::ranges::any_of( kDirs, [&]( std::string_view d )
                                {
        for( std::size_t at = p.find( d ); at != std::string_view::npos; at = p.find( d, at + 1 ) )
        {
            if( at == 0 || p[at - 1] == '/' )
            {
                return true;
            }
        }
        return false; } );
}

// ---- the trigger: an ALLOWLIST of phrasings, read from the stored argv's own words ----

inline bool isTableNoun( std::string_view w ) noexcept
{
    static constexpr std::string_view kNouns[] = { "function", "functions", "func", "funcs", "fn", "fns", "method", "methods", "export", "exports", "exported", "public", "class",
                                                   "classes", "def", "defs", "definition", "definitions", "symbol", "symbols", "helper", "helpers", "api", "apis", "code", "name", "names",
                                                   "type", "types", "constant", "constants", "const", "consts", "utility", "utilities", "util", "utils", "member", "members", "routine",
                                                   "routines", "procedure", "procedures", "item", "items", "thing", "things", "entry", "entries", "struct", "structs", "macro", "macros", "enum", "enums", "interface", "interfaces", "trait", "traits", "global", "globals", "hook", "hooks", "component", "components" };
    return taskroute::isOneOf( w, kNouns, std::size( kNouns ) );
}

// May an unused/dead word's object be the table's rows? The next word is a row noun, a linking word, a file token or the end of the subject:
// `unused imports`, `dead store`, `unused parameter` are other questions and do not fire.
inline bool cueObjectFits( std::span<const std::string> words, std::size_t next ) noexcept
{
    if( next >= words.size() )
    {
        return true;
    }
    const std::string_view w = words[next];
    static constexpr std::string_view kLinks[] = { "in", "from", "of", "inside", "within", "here", "at", "or", "and" };
    return isTableNoun( w ) || taskroute::isOneOf( w, kLinks, std::size( kLinks ) ) || w.find_first_of( "./" ) != std::string_view::npos;
}

inline constexpr auto wordIn = []( std::string_view w, std::initializer_list<std::string_view> set ) noexcept
{ return taskroute::isOneOf( w, set.begin(), set.size() ); };

// The words that may sit between `not`/`never` and the verb: `never get called`, `not being used`, `aren't even called`.
inline bool isGapWord( std::string_view w ) noexcept
{
    return wordIn( w, { "being", "get", "gets", "getting", "ever", "even", "actually", "currently", "be", "been", "really", "yet", "directly", "anywhere" } );
}

inline bool isUseVerb( std::string_view w ) noexcept
{
    return wordIn( w, { "called", "used", "referenced", "invoked", "imported", "exercised" } );
}

inline bool isCallVerb( std::string_view w ) noexcept
{
    return wordIn( w, { "calls", "uses", "references", "imports", "invokes", "call", "use", "reference" } );
}

inline bool isCallerNoun( std::string_view w ) noexcept
{
    return wordIn( w, { "caller", "callers", "users", "usages", "references", "callsites", "call-sites", "call-site", "callsite" } );
}

inline bool subjectAsksUnused( std::string_view task )
{
    std::vector<std::string> words;
    for( const std::string_view raw : splitRouteWords( task ) )
    {
        if( const std::string_view w = filepage::trimWordPunct( raw ); !w.empty() )
        {
            words.push_back( routeLower( w ) );
        }
    }
    const auto at = [&]( std::size_t k ) -> std::string_view
    { return k < words.size() ? std::string_view( words[k] ) : std::string_view {}; };
    // `no one`, `nobody`, `nothing`, `noone` at k: the index after them, or 0
    const auto nobodyEnd = [&]( std::size_t k ) -> std::size_t
    {
        if( wordIn( at( k ), { "nobody", "nothing", "noone" } ) )
        {
            return k + 1;
        }
        return at( k ) == "no" && at( k + 1 ) == "one" ? k + 2 : 0;
    };
    for( std::size_t k = 0; k < words.size(); ++k )
    {
        const std::string_view w = words[k];
        if( wordIn( w, { "unused", "uncalled", "unreferenced", "unexercised-by-code", "orphaned", "orphan", "unreachable", "stale" } ) && cueObjectFits( words, k + 1 ) )
        {
            return true;
        }
        if( w == "dead" )
        {
            // `dead code elimination` / `dead store` are other subjects; `dead code in f`, `dead functions`, `are any dead` fire
            const bool analysis = at( k + 1 ) == "code" && wordIn( at( k + 2 ), { "elimination", "removal", "detection", "analysis", "pass", "analyzer", "stripping" } );
            if( !analysis && cueObjectFits( words, k + 1 ) )
            {
                return true;
            }
        }
        if( wordIn( w, { "never", "not", "isn't", "aren't", "isnt", "arent" } ) )
        {
            std::size_t j = k + 1;
            for( int gap = 0; gap < 2 && isGapWord( at( j ) ); ++gap )
            {
                ++j;
            }
            if( isUseVerb( at( j ) ) )
            {
                return true;
            }
        }
        if( const std::size_t after = nobodyEnd( k ); after != 0 && isCallVerb( at( after ) ) )
        {
            return true;
        }
        if( wordIn( w, { "no", "without", "zero" } ) )
        {
            std::size_t j = k + 1;
            if( wordIn( at( j ), { "a", "an", "any", "the" } ) )
            {
                ++j;
            }
            const bool callSites = at( j ) == "call" && wordIn( at( j + 1 ), { "site", "sites" } );
            if( isCallerNoun( at( j ) ) || callSites || ( wordIn( at( j ), { "non-test", "production", "library", "external", "outside" } ) && isCallerNoun( at( j + 1 ) ) ) )
            {
                return true;
            }
        }
        if( w == "by" && wordIn( at( k - 1 ), { "used", "called", "referenced", "imported", "invoked" } ) && nobodyEnd( k + 1 ) != 0 )
        {
            return true; // `used by nothing`, `called by no one`
        }
        if( w == "test-only" )
        {
            return true;
        }
        if( w == "only" && isUseVerb( at( k + 1 ) ) && wordIn( at( k + 2 ), { "by", "from", "in" } ) && wordIn( at( k + 3 ), { "test", "tests" } ) )
        {
            return true;
        }
        if( w == "only" && wordIn( at( k + 1 ), { "test", "tests" } ) && isCallVerb( at( k + 2 ) ) )
        {
            return true; // `only tests use`
        }
        // delete intent: the question is whether code can go
        if( wordIn( w, { "safe", "safely" } ) && wordIn( at( k + 1 ), { "delete", "remove", "drop", "deleted", "removed", "dropped" } ) )
        {
            return true;
        }
        if( w == "can" && at( k + 1 ) == "be" && wordIn( at( k + 2 ), { "removed", "deleted", "dropped" } ) )
        {
            return true;
        }
        if( wordIn( w, { "removable", "deletable" } ) )
        {
            return true;
        }
        // `does anything call the functions in f`
        if( w == "anything" && isCallVerb( at( k + 1 ) ) && ( isTableNoun( at( k + 2 ) ) || ( at( k + 2 ) == "the" && isTableNoun( at( k + 3 ) ) ) ) )
        {
            return true;
        }
    }
    return false;
}

// ---- which defs are public, per language (an allowlist: an unserved language gets no verdict at all) ----

inline constexpr std::array<Lang, 7> kServedLangs = { Lang::Python, Lang::TypeScript, Lang::JavaScript, Lang::Go, Lang::Rust, Lang::C, Lang::Cpp };
inline constexpr std::array<Lang, 2> kCFamilyLangs = { Lang::C, Lang::Cpp };
inline constexpr std::array<Lang, 2> kJsFamilyLangs = { Lang::TypeScript, Lang::JavaScript };
inline constexpr std::array<Lang, 3> kScopedMemberLangs = { Lang::Python, Lang::TypeScript, Lang::JavaScript }; // a scoped function is a member here


inline std::string_view scopeTail( const Symbol& s ) noexcept
{
    const std::string_view scope = s.scope;
    const std::size_t sep = scope.rfind( "::" );
    return sep == std::string_view::npos ? scope : scope.substr( sep + 2 );
}

// A class attribute is a field, not a row: `r`, `x`, `red` read as words everywhere and no one asks whether they are unused here.
inline bool rowKind( const Symbol& s ) noexcept
{
    const SymKind k = s.kind;
    return k == SymKind::Function || k == SymKind::Method || k == SymKind::Class || k == SymKind::Struct || k == SymKind::Interface || k == SymKind::NamedType || k == SymKind::Alias || k == SymKind::FuncType || ( k == SymKind::Var && s.scope.empty() ) || k == SymKind::Macro;
}

// a member of a class or type: Python keeps a method as a scoped function
inline bool isMemberDef( const Symbol& s ) noexcept
{
    const bool scopedFunctionIsMember = std::ranges::contains( kScopedMemberLangs, s.lang );
    return s.kind == SymKind::Method || ( scopedFunctionIsMember && s.kind == SymKind::Function && !s.scope.empty() );
}

// the text before byte `at` on its own line and the lines just above: what an attribute, a decorator or `//export` sits on
inline std::string_view lineBefore( std::string_view src, std::size_t lineStartByte ) noexcept
{
    if( lineStartByte < 2 || lineStartByte > src.size() )
    {
        return {};
    }
    const std::size_t prevEnd = lineStartByte - 1;
    const std::size_t nl = src.rfind( '\n', prevEnd - 1 );
    const std::size_t prevStart = nl == std::string_view::npos ? 0 : nl + 1;
    return trimWs( src.substr( prevStart, prevEnd - prevStart ) );
}

inline std::size_t lineStartOf( std::string_view src, std::size_t at ) noexcept
{
    if( at == 0 || at > src.size() )
    {
        return 0;
    }
    const std::size_t nl = src.rfind( '\n', at - 1 );
    return nl == std::string_view::npos ? 0 : nl + 1;
}

// C and C++ mint a type symbol at `enum E x;` and `struct S *p;`: that line uses the type. A definition opens a body or typedefs one.
inline bool cTypeMentionNotDefinition( const Symbol& s, std::string_view src ) noexcept
{
    if( !std::ranges::contains( kCFamilyLangs, s.lang ) || ( s.kind != SymKind::Class && !isStructOrNamedType( s.kind ) ) || s.kind == SymKind::Alias )
    {
        return false;
    }
    const std::size_t ls = lineStartOf( src, s.sigStartByte );
    const std::size_t e1 = src.find( '\n', ls );
    if( e1 == std::string_view::npos )
    {
        return src.substr( ls ).find( '{' ) == std::string_view::npos;
    }
    const std::size_t e2 = src.find( '\n', e1 + 1 );
    const std::string_view twoLines = src.substr( ls, e2 == std::string_view::npos ? std::string_view::npos : e2 - ls );
    return twoLines.find( '{' ) == std::string_view::npos && src.substr( ls, e1 - ls ).find( "typedef" ) == std::string_view::npos;
}

inline bool jsIsExported( const IngestResult& ing, const Symbol& s, std::string_view src, std::span<const std::string_view> exportedNames ) noexcept
{
    (void)ing;
    if( std::ranges::binary_search( exportedNames, std::string_view( s.name ), sortutil::svLess ) )
    {
        return true;
    }
    const std::size_t ls = lineStartOf( src, s.sigStartByte );
    return src.substr( ls ).starts_with( "export " );
}

inline bool sigOpensPub( const Symbol& s, std::string_view src ) noexcept
{
    const std::size_t ls = lineStartOf( src, s.sigStartByte );
    return s.sigStartByte <= src.size() && trimWs( src.substr( ls, s.sigStartByte - ls + 4 ) ).starts_with( "pub" );
}

// Is the def a public row of its language? `owner` is the class symbol of a method, when the file holds one.
inline bool isPublicDef( const IngestResult& ing, const Symbol& s, std::string_view src, std::span<const std::string_view> jsExports, const Symbol* owner ) noexcept
{
    if( !rowKind( s ) || ( s.kind != SymKind::Class && !isStructOrNamedType( s.kind ) && s.kind != SymKind::Interface && quality::languageInvokedSymbol( s ) ) )
    {
        return false;
    }
    switch( s.lang )
    {
        case Lang::Python:
            return !s.name.starts_with( '_' ) && !scopeTail( s ).starts_with( '_' );
        case Lang::Go:
            return !s.name.empty() && s.name.front() >= 'A' && s.name.front() <= 'Z';
        case Lang::Rust:
            return sigOpensPub( s, src );
        case Lang::TypeScript:
        case Lang::JavaScript:
            if( isMemberDef( s ) )
            {
                const std::size_t ls = lineStartOf( src, s.sigStartByte );
                const std::string_view head = trimWs( src.substr( ls, s.sigStartByte > ls ? s.sigStartByte - ls + 8 : 8 ) );
                return owner != nullptr && jsIsExported( ing, *owner, src, jsExports ) && !s.name.starts_with( '#' ) && !head.starts_with( "private" ) && !head.starts_with( "protected" );
            }
            return jsIsExported( ing, s, src, jsExports );
        case Lang::C:
        case Lang::Cpp:
            return !quality::symbolHasStaticLinkage( s, src );
        default:
            return false;
    }
}

// ---- the hedges a def carries before any scan: the language's own ways of reaching it ----

inline bool sigHolds( const Symbol& s, std::string_view src, std::string_view word ) noexcept
{
    const std::size_t end = std::min<std::size_t>( s.sigEndByte, src.size() );
    return s.sigStartByte < end && src.substr( s.sigStartByte, end - s.sigStartByte ).find( word ) != std::string_view::npos;
}

// A Python decorator registers its function unless it is one of these, which only reshape it. An allowlist: an unlisted decorator hedges.
inline bool pythonDecoratorsMayRegister( std::string_view src, std::size_t lineStart ) noexcept
{
    static constexpr std::array<std::string_view, 16> kShapers = { "dataclass", "dataclasses.dataclass", "attr.s", "attrs.define", "attrs.frozen", "staticmethod", "classmethod", "property", "cached_property",
                                                                   "functools.cached_property", "functools.wraps", "functools.lru_cache", "functools.cache", "lru_cache", "overload", "typing.overload" };
    for( std::size_t ls = lineStart; ls > 0; )
    {
        const std::string_view line = lineBefore( src, ls );
        if( !line.starts_with( '@' ) )
        {
            return false;
        }
        const std::size_t cut = line.find_first_of( "( \t" );
        const std::string_view name = line.substr( 1, cut == std::string_view::npos ? std::string_view::npos : cut - 1 );
        if( std::ranges::find( kShapers, name ) == kShapers.end() )
        {
            return true;
        }
        const std::size_t nl = src.rfind( '\n', ls - 2 );
        ls = nl == std::string_view::npos ? 0 : nl + 1;
    }
    return false;
}

// A framework that routes by FILE PATH calls the defs of a file nothing in the tree names: Next, Nuxt, SvelteKit, Remix and Astro (pages/, app/, routes/,
// page.tsx, +server.ts), Django and Flask conventions (views.py, urls.py, admin.py, management/commands/). These are framework conventions, not rows of any
// corpus. A path component that matches reads framework on every public def of the file.
inline bool frameworkRoutedPath( std::string_view rel, Lang lang ) noexcept
{
    static constexpr std::array<std::string_view, 12> kJsDirs = { "pages", "app", "routes", "route", "api", "layouts", "middleware", "handlers", "controllers", "plugins", "endpoints", "server" };
    static constexpr std::array<std::string_view, 12> kJsStems = { "page", "layout", "route", "loading", "error", "template", "middleware", "+page", "+layout", "+server", "root", "entry.server" };
    static constexpr std::array<std::string_view, 9> kPyDirs = { "commands", "templatetags", "migrations", "routes", "api", "handlers", "plugins", "blueprints", "views" };
    static constexpr std::array<std::string_view, 12> kPyStems = { "views", "urls", "admin", "apps", "signals", "consumers", "routing", "tasks", "serializers", "forms", "models", "wsgi" };
    const bool js = std::ranges::contains( kJsFamilyLangs, lang );
    if( !js && lang != Lang::Python )
    {
        return false;
    }
    const std::size_t slash = rel.rfind( '/' );
    std::string_view dirs = slash == std::string_view::npos ? std::string_view {} : rel.substr( 0, slash );
    while( !dirs.empty() )
    {
        const std::size_t cut = dirs.rfind( '/' );
        const std::string_view part = cut == std::string_view::npos ? dirs : dirs.substr( cut + 1 );
        if( js ? std::ranges::contains( kJsDirs, part ) : std::ranges::contains( kPyDirs, part ) )
        {
            return true;
        }
        dirs = cut == std::string_view::npos ? std::string_view {} : dirs.substr( 0, cut );
    }
    const std::string_view stem = mention_detail::stripExt( mention_detail::baseNameOf( rel ) );
    return js ? std::ranges::contains( kJsStems, stem ) : std::ranges::contains( kPyStems, stem );
}

inline std::uint16_t languageHedges( const Symbol& s, std::string_view rel, std::string_view src, const Symbol* owner, bool rustLibCrate )
{
    std::uint16_t why = 0;
    const std::size_t ls = lineStartOf( src, s.sigStartByte );
    const std::string_view above = lineBefore( src, ls );
    const bool isMethod = isMemberDef( s );
    if( s.name == "main" || frameworkRoutedPath( rel, s.lang ) )
    {
        why |= kWhyFramework;
    }
    switch( s.lang )
    {
        case Lang::Python:
            if( ( quality::pythonDecoratedDef( s, src ) && pythonDecoratorsMayRegister( src, ls ) ) || quality::pythonRunnerRoot( rel, s, src ) || s.name.starts_with( "pytest_" ) )
            {
                why |= kWhyFramework;
            }
            if( isMethod && owner != nullptr && sigHolds( *owner, src, "(" ) && !sigHolds( *owner, src, "(object)" ) )
            {
                why |= kWhyDispatch;
            }
            break;
        case Lang::TypeScript:
        case Lang::JavaScript:
            if( above.starts_with( "@" ) )
            {
                why |= kWhyFramework;
            }
            if( isMethod && owner != nullptr && ( sigHolds( *owner, src, " extends " ) || sigHolds( *owner, src, " implements " ) ) )
            {
                why |= kWhyDispatch;
            }
            break;
        case Lang::Go:
            if( s.name == "init" || s.name.starts_with( "Test" ) || s.name.starts_with( "Benchmark" ) || s.name.starts_with( "Fuzz" ) || s.name.starts_with( "Example" ) || above.starts_with( "//export " ) || above.starts_with( "//go:linkname " ) )
            {
                why |= kWhyFramework;
            }
            if( isMethod )
            {
                why |= kWhyDispatch; // Go interfaces are implicit: any method may satisfy one, inside or outside the tree
            }
            if( rel.find( "internal/" ) == std::string_view::npos && !src.starts_with( "package main" ) && src.find( "\npackage main" ) == std::string_view::npos )
            {
                why |= kWhyApi;
            }
            break;
        case Lang::Rust:
            if( above.starts_with( "#[" ) || sigHolds( s, src, "extern \"" ) )
            {
                why |= kWhyFramework;
            }
            if( rustLibCrate )
            {
                why |= kWhyApi;
            }
            break;
        case Lang::C:
        case Lang::Cpp:
            if( sigHolds( s, src, "__attribute__" ) || sigHolds( s, src, "extern \"C\"" ) || above.starts_with( "extern \"C\"" ) )
            {
                why |= kWhyFramework;
            }
            // an out-of-class definition's class is in another file: its bases and `virtual` are not read here, so it hedges
            if( isMethod && ( owner == nullptr || sigHolds( s, src, "virtual" ) || sigHolds( s, src, "override" ) || sigHolds( *owner, src, ":" ) ) )
            {
                why |= kWhyDispatch;
            }
            // the enumerators of an unscoped enum are used without ever naming it, so its own name proves nothing
            if( s.kind != SymKind::Function && s.kind != SymKind::Method && src.substr( lineStartOf( src, s.sigStartByte ) ).starts_with( "enum " ) && !sigHolds( s, src, "enum class" ) && !sigHolds( s, src, "enum struct" ) )
            {
                why |= kWhyMembers;
            }
            if( rel.starts_with( "include/" ) || rel.find( "/include/" ) != std::string_view::npos )
            {
                why |= kWhyApi;
            }
            break;
        default:
            break;
    }
    return why;
}

// ---- one name's evidence, grouped over the same-named defs of the file (an overload set is one row) ----

struct Site
{
    std::uint32_t fileId = 0;
    std::uint32_t line = 0;
};

struct Row
{
    std::string_view name;
    std::vector<NodeId> defs;
    std::vector<std::uint64_t> ownLines; // (fileId << 32) | line of each def: a word there is the def itself, sorted
    bool listed = false; // has a def in the named file (its pair's other defs read as evidence only)
    std::uint16_t why = 0;
    bool isPublic = false;
    std::string_view ownerName; // the class of a member def, when this file holds it
    bool member = false; // a def of it is a member: any object's attribute lookup may reach it
    bool derived = false; // a Python class with a base: an `__init_subclass__` or metaclass hook in the tree may register it
    bool top = false; // the file's own top-level code calls it
    bool viaFile = false; // `used` came down an in-file chain
    std::uint32_t outPlain = 0; // non-test callers in another file, bound by more than the name
    std::uint32_t inFile = 0; // non-test callers in this file
    std::uint32_t tests = 0; // test callers and test-file words
    std::uint32_t text = 0; // non-test code words outside this file, past the def lines
    std::uint32_t strings = 0;
    std::uint32_t imports = 0;
    std::uint32_t sameText = 0; // words in this file past the def lines
    std::uint32_t decls = 0;
    std::vector<Site> at;
    std::vector<Site> testAt;
    NodeId byInFile = kNoNode;
};

inline void noteSite( std::vector<Site>& sites, std::uint32_t fileId, std::uint32_t line )
{
    if( sites.size() < kForUnusedSitesShown )
    {
        sites.push_back( { fileId, line } );
    }
}

// A class reached only through its members never has its name read: a member with any evidence keeps the class row from `unused`.
inline void hedgeOwnersOfMembers( std::span<Row> rows )
{
    for( const Row& r : rows )
    {
        const bool evidence = r.outPlain > 0 || r.inFile > 0 || r.text > 0 || r.tests > 0 || r.sameText > 0 || ( r.why & ( kWhyByName | kWhyDeclined | kWhyString | kWhyValue ) ) != 0;
        if( !evidence || r.ownerName.empty() )
        {
            continue;
        }
        const auto owner = std::ranges::lower_bound( rows, r.ownerName, sortutil::svLess, &Row::name );
        if( owner != rows.end() && owner->name == r.ownerName && owner->name != r.name )
        {
            owner->why |= kWhyMembers;
        }
    }
}

// a word on a line that only DECLARES it (C/C++: a prototype or a forward declaration) is the definition's other half, not a use
inline bool isPrototypeLine( std::string_view line, std::size_t col, std::size_t nameLen ) noexcept
{
    const std::string_view t = trimWs( line );
    if( t.empty() || t.starts_with( "return" ) || t.find( '=' ) != std::string_view::npos )
    {
        return false;
    }
    if( col + nameLen >= line.size() || line[col + nameLen] != '(' || col == 0 )
    {
        return false;
    }
    const char before = line[col - 1];
    if( before != ' ' && before != '\t' && before != '*' && before != '&' )
    {
        return false;
    }
    if( trimWs( line.substr( 0, col ) ).empty() )
    {
        return false; // no type ahead of the name: a call
    }
    const char last = t.back();
    return last == ';' || last == ',' || last == '(';
}

inline constexpr auto opensWithAny = []( std::string_view t, std::span<const std::string_view> heads ) noexcept
{ return std::ranges::contains( heads, true, [t]( std::string_view head )
                                { return t.starts_with( head ); } ); };

// `hashComments` comes from the language facts (langFacts(l).hashComment): `#` is a comment in Python, shell, Ruby and the like, and is NOT one in Rust
// attributes, C/C++ directives or JS/TS private fields. A language no table row knows reads `#` as code.
// `/* note */ call()` is code after the comment: only a line that ends with its comment is skipped whole.
inline bool isCommentLine( std::string_view line, bool hashComments ) noexcept
{
    static constexpr std::array<std::string_view, 4> kHeads = { "//", "/*", "* ", "*/" };
    const std::string_view t = trimWs( line );
    if( t.starts_with( "/*" ) || t.starts_with( "*/" ) )
    {
        const std::size_t close = t.starts_with( "*/" ) ? 0 : t.find( "*/", 2 );
        if( close != std::string_view::npos )
        {
            const std::string_view rest = trimWs( t.substr( close + 2 ) );
            return rest.empty() || rest.starts_with( "//" );
        }
    }
    return opensWithAny( t, kHeads ) || t == "*" || ( hashComments && t.starts_with( '#' ) );
}

inline constexpr std::array<std::string_view, 7> kImportHeads = { "import ", "from ", "export {", "export type {", "use ", "pub use ", "pub(crate) use " };
inline bool isImportLine( std::string_view line ) noexcept { return opensWithAny( trimWs( line ), kImportHeads ); }

inline bool isDocPath( std::string_view p ) noexcept
{
    const auto ends = [&]( std::string_view e )
    { return p.ends_with( e ); };
    return ends( ".md" ) || ends( ".mdx" ) || ends( ".rst" ) || ends( ".txt" ) || ends( ".adoc" ) || p.find( "CHANGELOG" ) != std::string_view::npos;
}

inline bool isIdent( char c ) noexcept { return namesplit::isIdentChar( c ) || c == '$'; }

inline std::string_view stemOf( std::string_view rel ) noexcept
{
    const std::string_view base = mention_detail::baseNameOf( rel );
    return mention_detail::stripExt( base );
}

// How a lookup near a built name reaches things: an OBJECT lookup (`getattr(obj, ...)`, `obj[...]`, MethodByName) reaches the members of that object, a MODULE
// lookup (`globals()`, `import_module`, `dlsym`) reaches the free defs of a module. A stem built beside an object lookup in another file reads on members only,
// unless that file names the target's module (then the object may be the module).
enum class Lookup : std::uint8_t
{
    None,
    Object,
    Module
};

// The module name a file is imported by: its stem, or its directory's when the stem is `index`, `__init__` or `mod`.
inline std::string moduleStem( std::string_view rel )
{
    std::string_view stem = stemOf( rel );
    if( stem == "index" || stem == "__init__" || stem == "mod" )
    {
        const std::size_t sl = rel.rfind( '/' );
        stem = sl == std::string_view::npos ? stem : mention_detail::baseNameOf( rel.substr( 0, sl ) );
    }
    return std::string( stem );
}

inline std::string withoutExt( std::string_view rel )
{
    const std::size_t sl = rel.rfind( '/' );
    const std::size_t dot = rel.rfind( '.' );
    return std::string( dot != std::string_view::npos && ( sl == std::string_view::npos || dot > sl ) ? rel.substr( 0, dot ) : rel );
}

// Does `src` hold `word` as a whole identifier?
inline bool holdsWord( std::string_view src, std::string_view word ) noexcept
{
    for( std::size_t p = src.find( word ); p != std::string_view::npos; p = src.find( word, p + 1 ) )
    {
        if( ( p == 0 || !isIdent( src[p - 1] ) ) && ( p + word.size() >= src.size() || !isIdent( src[p + word.size()] ) ) )
        {
            return true;
        }
    }
    return false;
}

// The one pass: every word of every scanned file, looked up in the table's sorted names. A two-byte prefilter keeps the lookup off most words.
class NameScan
{
public:
    NameScan( std::span<Row> rows, std::span<const std::uint32_t> targetFiles, std::vector<std::string> targetModules, std::vector<std::string> targetStems )
        : rows_( rows ), targets_( targetFiles ), first2_( 1u << 16, 0 ), modules_( std::move( targetModules ) ), stems_( std::move( targetStems ) )
    {
        for( const Row& r : rows_ )
        {
            if( r.name.size() >= 2 )
            {
                first2_[key2( r.name[0], r.name[1] )] = 1;
            }
            else if( r.name.size() == 1 )
            {
                single_[static_cast<unsigned char>( r.name[0] )] = 1;
            }
            names_.push_back( r.name );
        }
    }

    // rows_ is sorted by name, so names_ is too
    void scanFile( std::uint32_t fileId, std::string_view path, std::string_view src, bool manifest )
    {
        const bool isTest = !manifest && isTestLikePath( path );
        const bool isDoc = !manifest && isDocPath( path );
        const bool isTarget = !manifest && std::ranges::contains( targets_, fileId );
        if( isDoc )
        {
            return; // a doc naming a function is no use of it
        }
        const bool cFamily = path.ends_with( ".c" ) || path.ends_with( ".h" ) || path.ends_with( ".cc" ) || path.ends_with( ".cpp" ) || path.ends_with( ".hpp" ) || path.ends_with( ".cxx" ) || path.ends_with( ".hh" );
        const bool hashComments = langFacts( langOfPath( path ) ).hashComment; // an unknown language reads `#` as code
        std::size_t lineStart = 0;
        std::uint32_t lineNo = 1;
        bool commentLine = false;
        bool lineRead = false;
        const auto lineText = [&]() -> std::string_view
        {
            const std::size_t e = src.find( '\n', lineStart );
            return src.substr( lineStart, e == std::string_view::npos ? std::string_view::npos : e - lineStart );
        };
        for( std::size_t i = 0; i < src.size(); )
        {
            const char c = src[i];
            if( c == '\n' )
            {
                ++i;
                lineStart = i;
                ++lineNo;
                lineRead = false;
                continue;
            }
            if( !isIdent( c ) )
            {
                if( ( c == '"' || c == '\'' || c == '`' ) && !isTest )
                {
                    i = quoted( i, src, fileId, lineNo );
                    continue;
                }
                if( c == '#' && !hashComments && i + 1 < src.size() && src[i + 1] == '#' && !isTest )
                {
                    pasted( i, src );
                }
                ++i;
                continue;
            }
            std::size_t e = i + 1;
            while( e < src.size() && isIdent( src[e] ) )
            {
                ++e;
            }
            const std::string_view word = src.substr( i, e - i );
            if( word.size() >= 6 && !isTest && !manifest )
            {
                noteHook( word, e, src );
            }
            if( word.size() == 1 ? single_[static_cast<unsigned char>( word[0] )] != 0 : first2_[key2( word[0], word[1] )] != 0 )
            {
                if( Row* r = find( word ); r != nullptr )
                {
                    if( !lineRead )
                    {
                        commentLine = isCommentLine( lineText(), hashComments );
                        lineRead = true;
                    }
                    const std::uint64_t here = ( std::uint64_t( fileId ) << 32 ) | lineNo;
                    if( !commentLine && !( !manifest && std::ranges::binary_search( r->ownLines, here ) ) )
                    {
                        hit( *r, fileId, lineNo, lineText(), i - lineStart, isTest, isTarget, cFamily, manifest );
                    }
                    else if( commentLine && manifest )
                    {
                        hit( *r, fileId, lineNo, lineText(), i - lineStart, isTest, isTarget, cFamily, manifest );
                    }
                }
            }
            i = e;
        }
    }

    // After every file is read: what the whole tree said about all the rows at once.
    void finish() noexcept
    {
        for( Row& r : rows_ )
        {
            if( dynamicDir_ )
            {
                r.why |= kWhyBuilt; // a directory import with a computed name: any module of it, any def of the module
            }
            if( registryHook_ && r.derived )
            {
                r.why |= kWhyDispatch; // `__init_subclass__` or a metaclass may register a subclass at its definition
            }
        }
    }

private:
    static std::size_t key2( char a, char b ) noexcept { return ( std::size_t( static_cast<unsigned char>( a ) ) << 8 ) | static_cast<unsigned char>( b ); }

    Row* find( std::string_view w ) noexcept
    {
        const auto it = std::ranges::lower_bound( names_, w, sortutil::svLess );
        return it != names_.end() && *it == w ? &rows_[std::size_t( it - names_.begin() )] : nullptr;
    }

    // Does another file name the target's module (an import, an alias)? Then an object it looks names up on may be that module.
    bool namesTargetModule( std::uint32_t fileId, std::string_view src )
    {
        if( mentionFile_ != fileId )
        {
            mentionFile_ = fileId;
            mentionVal_ = std::ranges::any_of( stems_, [&]( const std::string& st )
                                               { return !st.empty() && holdsWord( src, st ); } );
        }
        return mentionVal_;
    }

    // a stem builds a NAME only near a lookup that takes one: `f"is_{x}"` alone is a log line
    static Lookup nearDynamicLookup( std::string_view src, std::size_t at ) noexcept
    {
        std::size_t b = at;
        for( int up = 0; up < 3 && b > 0; ++up )
        {
            const std::size_t nl = src.rfind( '\n', b - 1 );
            b = nl == std::string_view::npos ? 0 : nl;
        }
        std::size_t e = at;
        for( int down = 0; down < 4 && e != std::string_view::npos; ++down )
        {
            e = src.find( '\n', e + 1 );
        }
        const std::string_view near = src.substr( b, e == std::string_view::npos ? std::string_view::npos : e - b );
        static constexpr std::array<std::string_view, 9> kModuleLookups = { "globals()", "locals()", "vars(", "import_module(", "__import__(", "sys.modules", "dlsym(", "GetProcAddress(", "eval(" };
        static constexpr std::array<std::string_view, 6> kObjectLookups = { "getattr(", "hasattr(", "__getattribute__", "MethodByName(", "FieldByName(", ".send(" };
        const auto holds = [&]( std::string_view w )
        { return near.find( w ) != std::string_view::npos; };
        if( std::ranges::any_of( kModuleLookups, holds ) )
        {
            return Lookup::Module;
        }
        if( ( at > 0 && src[at - 1] == '[' ) || near.find( "Reflect.get(" ) != std::string_view::npos || std::ranges::any_of( kObjectLookups, holds ) )
        {
            return Lookup::Object;
        }
        return Lookup::None;
    }

    // A stem built beside an object lookup in another file reaches that object's members; beside a module lookup, or in a file that names the target's module,
    // it reaches a free def too. No length rule: the lookup decides, not the stem.
    void markPrefix( std::string_view prefix, Lookup how, std::uint32_t fileId, std::string_view src )
    {
        if( prefix.size() < kForUnusedMinPrefix )
        {
            return;
        }
        const bool membersOnly = how == Lookup::Object && !std::ranges::contains( targets_, fileId ) && !namesTargetModule( fileId, src );
        markPrefixRows( prefix, membersOnly );
    }

    void markPrefixRows( std::string_view prefix, bool membersOnly = false ) noexcept
    {
        if( prefix.size() < kForUnusedMinPrefix )
        {
            return;
        }
        for( auto it = std::ranges::lower_bound( names_, prefix, sortutil::svLess ); it != names_.end() && it->starts_with( prefix ); ++it )
        {
            Row& r = rows_[std::size_t( it - names_.begin() )];
            if( !membersOnly || r.member )
            {
                r.why |= kWhyBuilt;
            }
        }
    }

    void markSuffixRows( std::string_view tail ) noexcept
    {
        if( tail.size() < 2 * kForUnusedMinPrefix )
        {
            return;
        }
        for( std::size_t k = 0; k < names_.size(); ++k )
        {
            if( names_[k].ends_with( tail ) )
            {
                rows_[k].why |= kWhyBuilt;
            }
        }
    }

    // `"render" + kind`, `.concat(` : the literal is joined to something computed
    static bool joinedAfter( std::string_view src, std::size_t pos ) noexcept
    {
        while( pos < src.size() && ( src[pos] == ' ' || src[pos] == '\t' ) )
        {
            ++pos;
        }
        return pos < src.size() && ( ( src[pos] == '+' && ( pos + 1 >= src.size() || src[pos + 1] != '+' ) ) || src.substr( pos ).starts_with( ".concat(" ) );
    }

    static bool joinedBefore( std::string_view src, std::size_t pos ) noexcept
    {
        while( pos > 0 && ( src[pos - 1] == ' ' || src[pos - 1] == '\t' ) )
        {
            --pos;
        }
        return pos > 0 && src[pos - 1] == '+' && ( pos < 2 || src[pos - 2] != '+' );
    }

    // a literal that is a name (string), or that opens with a stem a built name could extend (built-name). Returns where the scan resumes:
    // past the identifier run; a quote that opens no such run moves one byte, so the words of the string's text still read as words.
    std::size_t quoted( std::size_t at, std::string_view src, std::uint32_t fileId, std::uint32_t lineNo ) noexcept
    {
        const char q = src[at];
        std::size_t e = at + 1;
        while( e < src.size() && isIdent( src[e] ) )
        {
            ++e;
        }
        const std::string_view lit = src.substr( at + 1, e - at - 1 );
        if( lit.empty() || e >= src.size() )
        {
            return at + 1;
        }
        const char close = src[e];
        if( close == q )
        {
            if( Row* r = find( lit ); r != nullptr )
            {
                r->why |= kWhyString;
                ++r->strings;
                noteSite( r->at, fileId, lineNo );
            }
            else
            {
                const bool after = joinedAfter( src, e + 1 );
                const bool before = joinedBefore( src, at );
                if( lit.back() == '_' || after || before )
                {
                    if( const Lookup how = nearDynamicLookup( src, at ); how != Lookup::None )
                    {
                        if( lit.back() == '_' || after )
                        {
                            markPrefix( lit, how, fileId, src );
                        }
                        if( before )
                        {
                            markSuffixRows( lit );
                        }
                    }
                }
            }
            return e + 1;
        }
        if( close == '{' || close == '%' || ( close == '$' && q == '`' ) )
        {
            if( const Lookup how = nearDynamicLookup( src, at ); how != Lookup::None )
            {
                markPrefix( lit, how, fileId, src );
            }
        }
        return at + 1;
    }

    // `import(`./routes/${n}`)`, `import_module("pkg.plugins." + n)`: a computed module name under a literal directory. Every def of a target under that directory
    // may be reached by the member lookup that follows, so the table reads built-name. A fully computed name (no literal head) names no directory and is not read.
    void dynamicImport( std::size_t open, std::string_view src ) noexcept
    {
        std::size_t k = open + 1;
        while( k < src.size() && ( src[k] == ' ' || src[k] == '\t' ) )
        {
            ++k;
        }
        for( int pre = 0; pre < 3 && k < src.size() && ( src[k] == 'f' || src[k] == 'r' || src[k] == 'b' ); ++pre )
        {
            ++k;
        }
        if( k >= src.size() || ( src[k] != '"' && src[k] != '\'' && src[k] != '`' ) )
        {
            return;
        }
        const char q = src[k++];
        std::string lit;
        bool computed = false;
        for( ; k < src.size() && src[k] != q && src[k] != '\n'; ++k )
        {
            if( src[k] == '{' || src[k] == '%' || ( src[k] == '$' && k + 1 < src.size() && src[k + 1] == '{' ) )
            {
                computed = true;
                break;
            }
            lit += src[k];
        }
        if( !computed && ( k >= src.size() || src[k] != q || !joinedAfter( src, k + 1 ) ) )
        {
            return; // a whole literal: the import graph already follows it
        }
        if( lit.find( '/' ) == std::string::npos )
        {
            std::ranges::replace( lit, '.', '/' );
        }
        while( lit.starts_with( "./" ) || lit.starts_with( "../" ) )
        {
            lit.erase( 0, lit.find( '/' ) + 1 );
        }
        if( lit.empty() )
        {
            return;
        }
        for( const std::string& m : modules_ )
        {
            const std::size_t p = m.find( lit );
            if( p != std::string::npos && ( p == 0 || m[p - 1] == '/' ) )
            {
                dynamicDir_ = true;
            }
        }
    }

    // words that say something about the whole tree: dynamic imports, class-registration hooks
    void noteHook( std::string_view word, std::size_t end, std::string_view src ) noexcept
    {
        if( word == "__init_subclass__" || word == "__subclasses__" || word == "metaclass" )
        {
            registryHook_ = true;
        }
        else if( end < src.size() && src[end] == '(' && ( word == "import" || word == "import_module" || word == "__import__" || word == "require" ) )
        {
            dynamicImport( end, src );
        }
    }

    void pasted( std::size_t at, std::string_view src ) noexcept
    {
        std::size_t b = at;
        while( b > 0 && isIdent( src[b - 1] ) )
        {
            --b;
        }
        markPrefixRows( src.substr( b, at - b ) );
        std::size_t e = at + 2;
        while( e < src.size() && isIdent( src[e] ) )
        {
            ++e;
        }
        markSuffixRows( src.substr( at + 2, e - at - 2 ) );
    }

    void hit( Row& r, std::uint32_t fileId, std::uint32_t lineNo, std::string_view line, std::size_t col, bool isTest, bool isTarget, bool cFamily, bool manifest ) noexcept
    {
        if( manifest )
        {
            r.why |= kWhyManifest;
            return;
        }
        if( cFamily && isPrototypeLine( line, col, r.name.size() ) )
        {
            ++r.decls;
            return;
        }
        if( isTest )
        {
            ++r.tests;
            noteSite( r.testAt, fileId, lineNo );
            return;
        }
        if( isTarget )
        {
            ++r.sameText;
            return;
        }
        if( isImportLine( line ) )
        {
            ++r.imports;
        }
        else
        {
            ++r.text;
        }
        noteSite( r.at, fileId, lineNo );
    }

    std::span<Row> rows_;
    std::span<const std::uint32_t> targets_;
    std::vector<std::uint8_t> first2_;
    std::array<std::uint8_t, 256> single_ {};
    std::vector<std::string_view> names_;
    std::vector<std::string> modules_; // the target files' paths without extension: what a computed import's literal head is matched against
    std::vector<std::string> stems_; // the names the target files are imported by
    std::uint32_t mentionFile_ = ~std::uint32_t( 0 );
    bool mentionVal_ = false;
    bool dynamicDir_ = false;
    bool registryHook_ = false;
};

// `export * from "./x"`, `from x import *`, `pub use x::*`: the stem right beside the star, in any non-test file
// `export * from`, `export * as ns from`, `export type * from`
inline bool isExportStar( std::string_view t ) noexcept
{
    return t.starts_with( "export *" ) || t.starts_with( "export type *" );
}

inline bool lineStarExportsStem( std::string_view line, std::string_view stem, Lang lang ) noexcept
{
    const std::string_view t = trimWs( line );
    const auto holdsStem = [&]( std::string_view hay )
    {
        for( std::size_t p = hay.find( stem ); p != std::string_view::npos; p = hay.find( stem, p + 1 ) )
        {
            const bool leftOk = p == 0 || !isIdent( hay[p - 1] );
            const bool rightOk = p + stem.size() >= hay.size() || !isIdent( hay[p + stem.size()] );
            if( leftOk && rightOk )
            {
                return true;
            }
        }
        return false;
    };
    if( isExportStar( t ) )
    {
        return std::ranges::contains( kJsFamilyLangs, lang ) && holdsStem( t );
    }
    if( t.starts_with( "from " ) && t.ends_with( "import *" ) )
    {
        return std::to_underlying( lang ) == std::to_underlying( Lang::Python ) && holdsStem( t );
    }
    if( ( t.starts_with( "pub use " ) || t.starts_with( "pub(crate) use " ) ) && t.find( "::*" ) != std::string_view::npos )
    {
        return std::to_underlying( lang ) == std::to_underlying( Lang::Rust ) && holdsStem( t );
    }
    return false;
}

inline bool fileIsStarExported( std::string_view rel, Lang lang, std::uint32_t self, std::span<const std::string> texts, std::span<const std::uint32_t> ids )
{
    std::string_view stem = stemOf( rel );
    if( stem == "index" || stem == "__init__" || stem == "mod" )
    {
        const std::string_view dir = rel.substr( 0, rel.rfind( '/' ) == std::string_view::npos ? 0 : rel.rfind( '/' ) );
        stem = mention_detail::baseNameOf( dir );
    }
    for( std::size_t k = 0; k < texts.size(); ++k )
    {
        if( ids[k] != self && lineStarExportsStem( texts[k], stem, lang ) )
        {
            return true;
        }
    }
    return false;
}

// the star-export lines of a file, kept while the one pass reads it
inline void collectStarLines( std::string_view src, std::uint32_t fileId, std::vector<std::string>& texts, std::vector<std::uint32_t>& ids )
{
    for( std::size_t p = src.find( '*' ); p != std::string_view::npos; p = src.find( '*', p + 1 ) )
    {
        const std::size_t ls = lineStartOf( src, p );
        const std::size_t le = src.find( '\n', p );
        const std::string_view line = src.substr( ls, le == std::string_view::npos ? std::string_view::npos : le - ls );
        const std::string_view t = trimWs( line );
        if( isExportStar( t ) || ( t.starts_with( "from " ) && t.ends_with( "import *" ) ) || ( ( t.starts_with( "pub use " ) || t.starts_with( "pub(crate) use " ) ) && t.find( "::*" ) != std::string_view::npos ) )
        {
            texts.emplace_back( t );
            ids.push_back( fileId );
        }
        if( le == std::string_view::npos )
        {
            break;
        }
        p = le;
    }
}

// the build and package files on the way from the file up to the root: a name in one is a `[project.scripts]`, a `bin`, a linker list
inline std::vector<std::string> manifestsAbove( std::string_view diskAbs, std::string_view rel )
{
    static constexpr std::array<std::string_view, 10> kManifests = { "pyproject.toml", "setup.cfg", "setup.py", "package.json", "Cargo.toml", "CMakeLists.txt", "Makefile", "Makefile.am", "BUILD", "BUILD.bazel" };
    std::vector<std::string> out;
    if( !diskAbs.ends_with( rel ) )
    {
        return out;
    }
    const std::string root( diskAbs.substr( 0, diskAbs.size() - rel.size() ) );
    std::string_view dir = rel;
    while( true )
    {
        const std::size_t sl = dir.rfind( '/' );
        dir = sl == std::string_view::npos ? std::string_view {} : dir.substr( 0, sl );
        for( const std::string_view m : kManifests )
        {
            out.push_back( root + ( dir.empty() ? std::string() : std::string( dir ) + "/" ) + std::string( m ) );
        }
        if( dir.empty() )
        {
            break;
        }
    }
    return out;
}

// a `pub` def in a crate with a src/lib.rs: consumers outside the tree may use it
inline bool inRustLibCrate( std::string_view diskAbs ) noexcept
{
    namespace fs = std::filesystem;
    std::string dir( diskAbs );
    std::error_code ec;
    for( std::size_t sl = dir.rfind( '/' ); sl != std::string::npos && sl > 0; sl = dir.rfind( '/' ) )
    {
        dir.resize( sl );
        if( fs::is_regular_file( dir + "/Cargo.toml", ec ) )
        {
            return fs::is_regular_file( dir + "/src/lib.rs", ec );
        }
    }
    return false;
}

// The one read of this lane's scan: every indexed file, every unindexed text file and every manifest comes through here.
inline std::optional<std::string> readText( const std::string& path )
{
    return docparse::detail::readWholeFile( path );
}

// A package.json that publishes something: a main, module, exports, types or bin, and not `"private": true`. Its exported defs have consumers outside the tree.
inline bool packageJsonPublishes( std::string_view json ) noexcept
{
    if( const std::size_t p = json.find( "\"private\"" ); p != std::string_view::npos )
    {
        std::size_t k = p + 9;
        while( k < json.size() && ( json[k] == ' ' || json[k] == ':' || json[k] == '\t' || json[k] == '\n' || json[k] == '\r' ) )
        {
            ++k;
        }
        if( json.substr( k ).starts_with( "true" ) )
        {
            return false;
        }
    }
    static constexpr std::array<std::string_view, 6> kKeys = { "\"main\"", "\"module\"", "\"exports\"", "\"types\"", "\"typings\"", "\"bin\"" };
    return std::ranges::any_of( kKeys, [&]( std::string_view key )
                                { return json.find( key ) != std::string_view::npos; } );
}

// A pyproject.toml that builds a distribution: a [project] or [tool.poetry] table, or a [build-system].
inline bool pyprojectBuilds( std::string_view toml ) noexcept
{
    return toml.find( "[project]" ) != std::string_view::npos || toml.find( "[tool.poetry]" ) != std::string_view::npos || toml.find( "[build-system]" ) != std::string_view::npos;
}

// A Python module path with a private component (`_impl/`, `_compat.py`) is not a public surface; `__init__` and `__main__` are.
inline bool pythonModulePrivate( std::string_view rel ) noexcept
{
    for( std::size_t p = 0; p < rel.size(); )
    {
        const std::size_t sl = rel.find( '/', p );
        const std::string_view part = rel.substr( p, sl == std::string_view::npos ? std::string_view::npos : sl - p );
        if( part.starts_with( '_' ) && !part.starts_with( "__init__" ) && !part.starts_with( "__main__" ) )
        {
            return true;
        }
        if( sl == std::string_view::npos )
        {
            break;
        }
        p = sl + 1;
    }
    return false;
}

// The text files under the root that the index did not take (a .vue, a Procfile, vendor/, dist/, a file over the size limit), read once each. A caller can sit in
// any of them, so the scan reads them all. `unseen` counts what it could not read or was too large to read: those make every claim of absence `unknown`.
struct ExtraFiles
{
    std::vector<std::string> paths; // root-relative, by extra id: an id of ing.files.size() + k is paths[k]
    std::size_t unseen = 0;
};

template <class Visit>
inline void walkUnindexed( const IngestResult& ing, ExtraFiles& st, Visit&& visit )
{
    namespace fs = std::filesystem;
    if( ing.crawlRoot.empty() )
    {
        ++st.unseen; // a merged multi-root index: no one root to walk
        return;
    }
    std::vector<std::string_view> indexed;
    indexed.reserve( ing.files.size() );
    for( std::uint32_t k = 0; k < ing.files.size(); ++k )
    {
        indexed.push_back( rootRelPath( ing, k ) );
    }
    std::ranges::sort( indexed, sortutil::svLess );
    std::error_code ec;
    fs::recursive_directory_iterator it( ing.crawlRoot, fs::directory_options::skip_permission_denied, ec );
    if( ec )
    {
        ++st.unseen;
        return;
    }
    std::size_t visited = 0;
    std::size_t bytes = 0;
    for( const fs::recursive_directory_iterator end; it != end; it.increment( ec ) )
    {
        if( ec )
        {
            ec.clear();
            ++st.unseen;
            continue;
        }
        const fs::file_status ls = it->symlink_status( ec );
        if( ec )
        {
            ec.clear();
            ++st.unseen;
            continue;
        }
        if( fs::is_directory( ls ) )
        {
            if( it->path().filename() == ".git" )
            {
                it.disable_recursion_pending();
            }
            continue;
        }
        if( !fs::is_regular_file( ls ) ) // a symlink, FIFO, socket or device is never opened
        {
            continue;
        }
        if( ++visited > kForUnusedExtraFiles )
        {
            ++st.unseen;
            break;
        }
        const std::string rel = it->path().lexically_relative( ing.crawlRoot ).generic_string();
        if( std::ranges::binary_search( indexed, std::string_view( rel ), sortutil::svLess ) )
        {
            continue;
        }
        const std::uintmax_t size = it->file_size( ec );
        if( ec )
        {
            ec.clear();
            ++st.unseen;
            continue;
        }
        if( size == 0 )
        {
            continue;
        }
        if( size > kForUnusedExtraFileBytes || bytes + size > kForUnusedExtraBytes )
        {
            ++st.unseen;
            continue;
        }
        const std::optional<std::string> data = readText( it->path().string() );
        if( !data )
        {
            ++st.unseen;
            continue;
        }
        bytes += data->size();
        if( std::string_view( *data ).substr( 0, 4096 ).find( '\0' ) != std::string_view::npos )
        {
            continue; // binary: it holds no caller a text scan could read
        }
        visit( rel, *data );
    }
}

inline std::string_view verdictOf( const Row& r ) noexcept
{
    if( r.outPlain > 0 || r.top || r.viaFile )
    {
        return "used";
    }
    if( r.why != 0 )
    {
        return "unknown";
    }
    if( r.inFile > 0 || r.sameText > 0 )
    {
        return "file-only";
    }
    return r.tests > 0 ? "test-only" : "unused";
}

inline int verdictRank( std::string_view v ) noexcept
{
    return v == "unused" ? 0 : v == "test-only" ? 1
                           : v == "file-only"   ? 2
                           : v == "unknown"     ? 3
                                                : 4;
}

// A C/C++ header and its source are one surface: `quoteString.h` declares what `quoteString.cpp` defines, so the table reads both.
inline std::vector<std::uint32_t> pairedFiles( const IngestResult& ing, std::uint32_t f )
{
    std::vector<std::uint32_t> out { f };
    const std::string_view rel = rootRelPath( ing, f );
    static constexpr std::array<std::string_view, 7> kExts = { ".h", ".hpp", ".hh", ".c", ".cc", ".cpp", ".cxx" };
    const auto isC = []( std::string_view p )
    { return std::ranges::any_of( kExts, [&]( std::string_view e )
                                  { return p.ends_with( e ); } ); };
    if( !isC( rel ) )
    {
        return out;
    }
    const std::string_view stem = stemOf( rel );
    for( std::uint32_t k = 0; k < ing.files.size(); ++k )
    {
        const std::string_view other = rootRelPath( ing, k );
        if( k != f && isC( other ) && stemOf( other ) == stem )
        {
            out.push_back( k );
        }
    }
    if( out.size() != 2 ) // the same stem three times over is no pair
    {
        out.resize( 1 );
    }
    return out;
}

// One file's rows, the evidence read off the graph, then the scan, then the in-file chain.
struct FileTable
{
    std::uint32_t file = 0;
    std::vector<Row> rows; // by name
    std::vector<std::uint32_t> pair; // the named file, and its C/C++ other half when it has one
    std::size_t privateDefs = 0;
    bool unread = false;
    bool servedLanguage = true;
};

// the caller's edge to `id` is one of several to same-named defs: the resolver did not pick, so it proves neither
inline bool callSplitOverNamesakes( const IngestResult& ing, const Graph& g, NodeId caller, NodeId id ) noexcept
{
    if( std::size_t( caller ) + 1 >= g.outOff.size() )
    {
        return false;
    }
    const std::string_view name = ing.symbols[id].name;
    for( std::uint32_t k = g.outOff[caller]; k < g.outOff[caller + 1]; ++k )
    {
        const NodeId other = g.outTargets[k];
        if( other != id && other < ing.symbols.size() && ing.symbols[other].name == name )
        {
            return true;
        }
    }
    return false;
}

inline FileTable buildFileTable( const IngestResult& ing, const Graph& g, const ValueRefIndex& vri, std::uint32_t f )
{
    FileTable table;
    table.file = f;
    const filepage::FileText text = filepage::loadFileText( ing, f );
    table.unread = text.src.empty();
    table.pair = pairedFiles( ing, f );
    bool modScope = false;
    std::vector<NodeId> defs = filepage::fileDefsInLineOrder( ing, f, modScope );
    for( std::size_t k = 1; k < table.pair.size(); ++k )
    {
        const std::vector<NodeId> more = filepage::fileDefsInLineOrder( ing, table.pair[k], modScope );
        defs.insert( defs.end(), more.begin(), more.end() );
    }

    std::vector<std::string_view> jsExports;
    for( const Binding& b : ing.bindings )
    {
        if( b.kind == LocalBindKind::JsExport && b.fileId == f )
        {
            jsExports.push_back( b.var );
            if( !b.importedName.empty() )
            {
                jsExports.push_back( b.importedName );
            }
        }
    }
    std::ranges::sort( jsExports, sortutil::svLess );

    const std::string_view rel = rootRelPath( ing, f );
    const std::string disk = diskPath( ing, f );
    const bool rustLib = !defs.empty() && std::to_underlying( ing.symbols[defs.front()].lang ) == std::to_underlying( Lang::Rust ) && inRustLibCrate( disk );
    table.servedLanguage = defs.empty() || std::ranges::contains( kServedLangs, ing.symbols[defs.front()].lang );

    const auto ownerOf = [&]( const Symbol& s ) -> const Symbol*
    {
        if( !isMemberDef( s ) )
        {
            return nullptr;
        }
        const std::string_view tail = scopeTail( s );
        for( const NodeId d : defs )
        {
            const Symbol& o = ing.symbols[d];
            if( o.kind != SymKind::Class && !isStructOrNamedType( o.kind ) && o.kind != SymKind::Interface )
            {
                continue;
            }
            // a C++ or Python member names its class in scope; TS and JS leave scope empty, and the class's span holds the member
            const bool holds = tail.empty() && o.fileId == s.fileId && o.sigStartByte < s.sigStartByte && s.sigStartByte < o.endByte;
            if( o.name == tail || holds )
            {
                return &o;
            }
        }
        return nullptr;
    };

    // the rows, by name: an overload set or two same-named members is one row
    for( const NodeId id : defs )
    {
        const Symbol& s = ing.symbols[id];
        if( !rowKind( s ) )
        {
            continue;
        }
        const filepage::FileText pairText = s.fileId == f ? filepage::FileText {} : filepage::loadFileText( ing, s.fileId );
        const std::string_view defSrc = s.fileId == f ? std::string_view( text.src ) : std::string_view( pairText.src );
        if( cTypeMentionNotDefinition( s, defSrc ) )
        {
            continue; // the word stays a use: the scan reads this line as one
        }
        auto it = std::ranges::lower_bound( table.rows, std::string_view( s.name ), sortutil::svLess, &Row::name );
        if( it == table.rows.end() || it->name != s.name )
        {
            Row fresh;
            fresh.name = s.name;
            it = table.rows.insert( it, std::move( fresh ) );
        }
        const Symbol* owner = ownerOf( s );
        it->ownerName = owner != nullptr ? std::string_view( owner->name ) : it->ownerName;
        it->defs.push_back( id );
        it->member = it->member || isMemberDef( s );
        it->ownLines.push_back( ( std::uint64_t( s.fileId ) << 32 ) | s.line );
        if( s.fileId == f )
        {
            it->listed = true;
            it->isPublic = it->isPublic || isPublicDef( ing, s, text.src, jsExports, owner );
            it->derived = it->derived || ( s.lang == Lang::Python && s.kind == SymKind::Class && sigHolds( s, text.src, "(" ) && !sigHolds( s, text.src, "(object)" ) );
            it->why = std::uint16_t( it->why | languageHedges( s, rel, text.src, owner, rustLib ) );
        }
        else
        {
            // the pair's other half: read for the hedges through its own bytes
            it->why = std::uint16_t( it->why | languageHedges( s, rootRelPath( ing, s.fileId ), defSrc, owner, rustLib ) );
        }
        if( vri.isValueReferenced( id ) )
        {
            it->why |= kWhyValue;
        }
    }
    for( Row& r : table.rows )
    {
        std::ranges::sort( r.ownLines );
    }

    // the graph's evidence
    const std::uint32_t* ro = g.inEdges.rowOffsets();
    const std::uint32_t* ci = g.inEdges.colIndices();
    for( Row& r : table.rows )
    {
        for( const NodeId id : r.defs )
        {
            if( ro == nullptr || ci == nullptr || id >= ing.symbols.size() )
            {
                continue;
            }
            for( std::uint32_t k = ro[id]; k < ro[id + 1]; ++k )
            {
                const NodeId caller = ci[k];
                if( caller == id || caller >= ing.symbols.size() )
                {
                    continue;
                }
                const Symbol& c = ing.symbols[caller];
                if( isTestSymbol( ing, caller ) || isTestLikePath( rootRelPath( ing, c.fileId ) ) )
                {
                    ++r.tests;
                    continue;
                }
                if( std::ranges::contains( table.pair, c.fileId ) )
                {
                    if( c.kind == SymKind::ModuleScope || c.name == "main" )
                    {
                        r.top = true; // top-level code or the entry point runs: this is what `used` chains from
                    }
                    ++r.inFile;
                    r.byInFile = r.byInFile == kNoNode ? caller : r.byInFile;
                    continue;
                }
                if( edgeNameOnly( g, caller, id ) || callSplitOverNamesakes( ing, g, caller, id ) )
                {
                    r.why |= kWhyByName;
                }
                else
                {
                    ++r.outPlain;
                }
            }
            const NodeId one[] = { id };
            if( declinedCallsNaming( g, one ) > 0 )
            {
                r.why |= kWhyDeclined;
            }
        }
    }
    return table;
}

// The in-file chain, once the scan has set each row's hedges: a def called by a used def is used; by an unknown one, unknown.
inline void chainWithinFile( const IngestResult& ing, const Graph& g, FileTable& t )
{
    const std::uint32_t* ro = g.inEdges.rowOffsets();
    const std::uint32_t* ci = g.inEdges.colIndices();
    if( ro == nullptr || ci == nullptr )
    {
        return;
    }
    struct Edge
    {
        std::uint32_t caller, callee;
    };
    std::vector<Edge> edges;
    for( std::uint32_t r = 0; r < t.rows.size(); ++r )
    {
        for( const NodeId id : t.rows[r].defs )
        {
            for( std::uint32_t k = ro[id]; k < ro[id + 1]; ++k )
            {
                const NodeId caller = ci[k];
                if( caller >= ing.symbols.size() || caller == id || !std::ranges::contains( t.pair, ing.symbols[caller].fileId ) )
                {
                    continue;
                }
                const auto it = std::ranges::lower_bound( t.rows, std::string_view( ing.symbols[caller].name ), sortutil::svLess, &Row::name );
                if( it != t.rows.end() && it->name == ing.symbols[caller].name && std::ranges::contains( it->defs, caller ) )
                {
                    edges.push_back( { std::uint32_t( it - t.rows.begin() ), r } );
                }
            }
        }
    }
    bool moved = true;
    for( std::size_t pass = 0; moved && pass <= t.rows.size(); ++pass )
    {
        moved = false;
        for( const Edge& e : edges )
        {
            const Row& from = t.rows[e.caller];
            Row& to = t.rows[e.callee];
            const bool fromUsed = from.outPlain > 0 || from.top || from.viaFile;
            if( fromUsed && !( to.outPlain > 0 || to.top || to.viaFile ) )
            {
                to.viaFile = true;
                moved = true;
            }
            else if( !fromUsed && from.why != 0 && to.why == 0 && !( to.outPlain > 0 || to.top || to.viaFile ) )
            {
                to.why = kWhyInFile;
                moved = true;
            }
        }
    }
}

inline void appendWhy( std::string& out, std::uint16_t why )
{
    bool first = true;
    for( const auto& [bit, word] : kWhyWords )
    {
        if( ( why & bit ) != 0 )
        {
            out += first ? " why=\"" : ",";
            out += word;
            first = false;
        }
    }
    if( !first )
    {
        out += '"';
    }
}

// a site's path: an indexed file's, or an unindexed one (id past the index) read off the extra list
inline std::string_view sitePath( const IngestResult& ing, const ExtraFiles& extra, std::uint32_t fileId ) noexcept
{
    return fileId < ing.files.size() ? rootRelPath( ing, fileId ) : std::string_view( extra.paths[fileId - ing.files.size()] );
}

inline void appendSites( std::string& out, const IngestResult& ing, const ExtraFiles& extra, std::span<const Site> sites, std::vector<char>& esc )
{
    bool first = true;
    for( const Site& s : sites )
    {
        out += first ? " at=\"" : ",";
        out += escapeXml( sitePath( ing, extra, s.fileId ), esc );
        out += std::format( ":{}", s.line );
        first = false;
    }
    if( !first )
    {
        out += '"';
    }
}

inline void appendRow( std::string& out, const IngestResult& ing, const ExtraFiles& extra, const Row& r, std::string_view verdict, std::vector<char>& esc )
{
    const Symbol& s = ing.symbols[r.defs.front()];
    out += "<u n=\"";
    out += escapeXml( r.name, esc );
    out += "\" t=\"";
    out += symTag( s.kind );
    out += std::format( "\" l=\"{}\" v=\"{}\"", s.line, verdict );
    if( r.defs.size() > 1 )
    {
        out += std::format( " defs=\"{}\"", r.defs.size() );
    }
    if( r.outPlain > 0 ) { out += std::format( " out=\"{}\"", r.outPlain ); }
    if( r.inFile > 0 ) { out += std::format( " in=\"{}\"", r.inFile ); }
    if( verdict == "used" )
    {
        out += "/>"; // a used row needs no more: why= would hedge what out= or in= already proves
        return;
    }
    appendWhy( out, r.why );
    if( r.tests > 0 ) { out += std::format( " tests=\"{}\"", r.tests ); }
    if( r.text > 0 ) { out += std::format( " text=\"{}\"", r.text ); }
    if( r.strings > 0 ) { out += std::format( " str=\"{}\"", r.strings ); }
    if( r.imports > 0 ) { out += std::format( " imp=\"{}\"", r.imports ); }
    if( r.sameText > 0 && r.inFile == 0 ) { out += std::format( " same=\"{}\"", r.sameText ); }
    if( r.byInFile != kNoNode && verdict != "used" )
    {
        out += " by=\"";
        out += escapeXml( ing.symbols[r.byInFile].name, esc );
        out += '"';
    }
    if( verdict != "used" )
    {
        appendSites( out, ing, extra, verdict == "test-only" ? std::span<const Site>( r.testAt ) : std::span<const Site>( r.at ), esc );
    }
    out += "/>";
}

inline std::string renderFileTable( const IngestResult& ing, const Graph& g, const FileTable& t, const ExtraFiles& extra, std::vector<char>& esc )
{
    std::array<std::size_t, 5> tally {};
    std::vector<std::pair<int, const Row*>> shownRows;
    std::size_t privateRows = 0;
    for( const Row& r : t.rows )
    {
        if( !r.listed )
        {
            continue;
        }
        if( !r.isPublic )
        {
            ++privateRows;
            continue;
        }
        const int rank = verdictRank( verdictOf( r ) );
        ++tally[std::size_t( rank )];
        shownRows.emplace_back( rank, &r );
    }
    std::ranges::stable_sort( shownRows, [&]( const auto& a, const auto& b )
                              { return a.first != b.first ? a.first < b.first : ing.symbols[a.second->defs.front()].line < ing.symbols[b.second->defs.front()].line; } );
    std::string out = "<unused_in_file p=\"";
    out += escapeXml( rootRelPath( ing, t.file ), esc );
    out += std::format( "\" public=\"{}\" private=\"{}\" unused=\"{}\" test_only=\"{}\" file_only=\"{}\" unknown=\"{}\" used=\"{}\"", shownRows.size(), privateRows, tally[0], tally[1], tally[2], tally[3], tally[4] );
    if( t.unread ) { out += " unread=\"1\""; }
    if( extra.unseen > 0 ) { out += std::format( " unseen=\"{}\"", extra.unseen ); }
    if( !t.servedLanguage ) { out += " lang_unserved=\"1\""; }
    if( shownRows.size() > kForUnusedRowsPerFile ) { out += std::format( " shown=\"{}\" capped=\"1\"", kForUnusedRowsPerFile ); }
    out += graphCountFloorAttrXml( g );
    out += '>';
    for( std::size_t k = 0; k < shownRows.size() && k < kForUnusedRowsPerFile; ++k )
    {
        appendRow( out, ing, extra, *shownRows[k].second, verdictOf( *shownRows[k].second ), esc );
    }
    out += "</unused_in_file>";
    return out;
}

} // namespace unusedfile

// The block: "" unless the subject carries a cue and names a file or a directory.
inline std::string renderForUnusedTable( const IngestResult& ing, const Graph& g, std::string_view task )
{
    using namespace unusedfile;
    if( !subjectAsksUnused( task ) )
    {
        return {};
    }
    const std::vector<FileAnchor> anchors = resolveFileAnchors( ing, task );
    std::vector<std::uint32_t> files;
    std::string nameList;
    std::vector<char> esc;
    std::size_t dirTotal = 0;
    for( const FileAnchor& a : anchors )
    {
        if( a.picksOne() || a.kind == 'd' )
        {
            for( const std::uint32_t f : a.files )
            {
                if( !std::ranges::contains( files, f ) && ( files.size() < kForUnusedDirFiles ) )
                {
                    files.push_back( f );
                }
            }
            dirTotal = std::max<std::size_t>( dirTotal, a.total );
        }
        else
        {
            nameList += std::format( "<unused_names s=\"{}\" total=\"{}\">", std::string( escapeXml( a.token, esc ) ), a.total );
            for( const std::uint32_t f : a.files )
            {
                nameList += "<f p=\"";
                nameList += escapeXml( rootRelPath( ing, f ), esc );
                nameList += "\"/>";
            }
            nameList += "</unused_names>";
        }
    }
    if( files.empty() )
    {
        return nameList;
    }

    const ValueRefIndex vri( ing );
    std::vector<FileTable> tables;
    tables.reserve( files.size() );
    for( const std::uint32_t f : files )
    {
        tables.push_back( buildFileTable( ing, g, vri, f ) );
    }

    // The one pass over the tree: each file read once, whatever the number of tables.
    std::vector<std::string> starTexts;
    std::vector<std::uint32_t> starIds;
    ExtraFiles extra;
    std::vector<NameScan> scans;
    scans.reserve( tables.size() );
    for( FileTable& table : tables )
    {
        std::vector<std::string> modules;
        std::vector<std::string> stems;
        for( const std::uint32_t pf : table.pair )
        {
            modules.push_back( withoutExt( rootRelPath( ing, pf ) ) );
            stems.push_back( moduleStem( rootRelPath( ing, pf ) ) );
        }
        scans.emplace_back( table.rows, table.pair, std::move( modules ), std::move( stems ) );
    }
    const auto scanAll = [&]( std::uint32_t id, std::string_view rel, std::string_view bytes )
    {
        for( NameScan& scan : scans )
        {
            scan.scanFile( id, rel, bytes, false );
        }
        if( !isTestLikePath( rel ) )
        {
            collectStarLines( bytes, id, starTexts, starIds );
        }
    };
    for( std::uint32_t k = 0; k < ing.files.size(); ++k )
    {
        const std::optional<std::string> bytes = readText( diskPath( ing, k ) );
        if( !bytes )
        {
            ++extra.unseen; // an indexed file that cannot be read may hold a caller
            continue;
        }
        scanAll( k, rootRelPath( ing, k ), *bytes );
    }
    walkUnindexed( ing, extra, [&]( const std::string& rel, const std::string& bytes )
                   {
        extra.paths.push_back( rel );
        scanAll( std::uint32_t( ing.files.size() + extra.paths.size() - 1 ), rel, bytes ); } );
    for( std::size_t t = 0; t < tables.size(); ++t )
    {
        FileTable& table = tables[t];
        bool pyPackaged = false;
        bool jsPublished = false;
        bool sawPackageJson = false;
        for( const std::string& m : manifestsAbove( diskPath( ing, table.file ), rootRelPath( ing, table.file ) ) )
        {
            if( const std::optional<std::string> bytes = readText( m ); bytes )
            {
                scans[t].scanFile( table.file, m, *bytes, true );
                if( m.ends_with( "/pyproject.toml" ) )
                {
                    pyPackaged = pyPackaged || pyprojectBuilds( *bytes );
                }
                else if( m.ends_with( "/setup.py" ) || m.ends_with( "/setup.cfg" ) )
                {
                    pyPackaged = true;
                }
                else if( m.ends_with( "/package.json" ) && !sawPackageJson )
                {
                    sawPackageJson = true; // the nearest one decides
                    jsPublished = packageJsonPublishes( *bytes );
                }
            }
        }
        scans[t].finish();
        const Lang fileLang = table.rows.empty() ? Lang::Unknown : ing.symbols[table.rows.front().defs.front()].lang;
        const bool barrel = fileIsStarExported( rootRelPath( ing, table.file ), fileLang, table.file, starTexts, starIds );
        const bool library = ( fileLang == Lang::Python && pyPackaged && !pythonModulePrivate( rootRelPath( ing, table.file ) ) ) || ( std::ranges::contains( kJsFamilyLangs, fileLang ) && jsPublished );
        for( Row& r : table.rows )
        {
            if( barrel )
            {
                r.why |= kWhyBarrel;
            }
            if( library )
            {
                r.why |= kWhyApi; // a distribution's public surface has consumers this tree does not hold
            }
            if( extra.unseen > 0 && r.outPlain == 0 && !r.top )
            {
                r.why |= kWhyUnseen;
            }
            if( r.text > 0 )
            {
                r.why |= kWhyName;
            }
            if( r.imports > 0 && r.text == 0 )
            {
                r.why |= kWhyImport;
            }
        }
        hedgeOwnersOfMembers( table.rows );
        chainWithinFile( ing, g, table );
    }

    std::string out = nameList;
    for( const FileTable& table : tables )
    {
        if( out.size() > kForUnusedMaxBytes )
        {
            out += "<unused_cut bytes_capped=\"1\"/>";
            break;
        }
        out += renderFileTable( ing, g, table, extra, esc );
    }
    if( dirTotal > files.size() )
    {
        out += std::format( "<unused_cut total=\"{}\" shown=\"{}\"/>", dirTotal, files.size() );
    }
    return out;
}

inline constexpr std::string_view kForUnusedLegend =
    "; unused_in_file p= public= private=: the task asks what is unused in a named file; its public defs, private ones counted and not listed. u n= t= l=: a def, defs= an overload set. "
    "v=used: a non-test caller in another file bound by more than the name, or an in-file chain from one or from top-level code (proves one caller, not that it is live); "
    "v=unknown: something may reach it that no index follows, why= says what, no claim either way; v=file-only: only same-file references; v=test-only: every reference found is in a test (a consumer outside this tree is not seen, see why=api); "
    "v=unused: the name appears in no text file under the root outside its definition, declarations and comments, and no why= applies: proves that of this tree only. "
    "why=name a non-test word no edge explains (a member call, a callback), by-name its callers bound by name alone or split over same-named defs, declined a declined call may mean it, value a table or argument holds it, "
    "string a string literal is its name (__all__, getattr), built-name a string or macro builds names it could be, import only an import or re-export names it, barrel its file is star re-exported, "
    "dispatch a base, trait or interface may call it, framework the language or a framework calls it (decorator, attribute, entry point), api consumers outside this tree may use it, "
    "members a type whose members are reached without its name (a member has evidence, or an unscoped enum), manifest a build or package file names it, in-file an unknown def in this file calls it, unseen a text file could not be read (unseen=N on the block). "
    "out= non-test callers elsewhere, in= in this file, by= one of them, tests= test callers and words, text= str= imp= same= non-test code, string, import and same-file words, at= sites to read. "
    "lang_unserved=1 no verdicts for this language; unread=1; unseen=N files that could not be read; shown= capped=1 rows cut; unused_cut: files or bytes cut; unused_names: several files match, none picked";
inline constexpr std::string_view kForCompactUnusedLegend =
    "; unused_in_file p= public= private=: public defs of the named file. u n= t= l= defs= v=used|unknown|file-only|test-only|unused: used a non-test caller elsewhere, or a chain from one; unknown why= says what may reach it; "
    "file-only same-file refs only; test-only tests only; unused no mention in any text file under the root. why=name|by-name|declined|value|string|built-name|import|barrel|dispatch|framework|api|members|manifest|in-file|unseen. "
    "out= in= by= tests= text= str= imp= same= at= the evidence; lang_unserved=1 unread=1 unseen= shown= capped=1 unused_cut unused_names";

} // namespace rw
