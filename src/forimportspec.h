#pragma once
// forimportspec.h — IMPORT-SPELLING (lane import-spelling): a task that spells an import, `NAME from <spec>` / `from a.b import NAME` /
// a dotted `a.b.NAME`, gets the chain FROM the spelling: the spec resolved to its entry file, then each statement that hands NAME on,
// followed to the definition. forreexport.h prints it inside <reexports>, ahead of the definition-side chains.
//
// WHY. "Where is `inject` imported from @angular/core defined?" The definition-side walk (forreexport.h) starts at every definition
// named NAME and walks outward, so it (1) needs the task's NAME (the parse took the cue word `imported` as the name), (2) picks the
// package by the spec's LAST segment as a directory (`@nestjs/common/internal` -> an `internal/` directory nothing has), and (3)
// stops silently where a specifier names both a file and a directory (`export * from './di'` beside `di.ts` and `di/`). An agent then
// walks the barrels by hand.
//
// WHAT.
//   * The spec: the token after `from` that is spelled as a module, and NAME the word before it once the cue words (`imported`,
//     `type`, `decorator`, …) are skipped; Python: `from a.b import NAME`, `NAME imported from a.b`, or a dotted `a.b.NAME` whose
//     prefix is an in-tree module.
//   * TS/JS: the package is the in-tree package.json whose `name` is the spec's package (`@s/n` or `n`); its `exports` entry for the
//     subpath (else `module`/`main`, else `index`) is the entry, a build-output target (`./dist/x/index.js`) mapped back to its
//     source (`src/x/index.ts`, then `x/index.ts`). Two package.json files that declare the name: disclosed (cands=N), nothing
//     guessed. No in-tree package of that name: the spec is external and no in-tree hop row prints for it.
//   * Python: the module `a.b` is `a/b.py` or `a/b/__init__.py` (one in-tree file; several: disclosed).
//   * From the entry, breadth-first: a definition of NAME in the file ends the walk; else `export { X as NAME } from`, `export * from`
//     (glob, hedged) or Python `from .m import X as NAME` / `lazy from .m import NAME` / `from .m import *` (glob) hand it on.
//     A relative specifier is resolved the way tsc reads it, the FILE before the directory index (`./di` -> `di.ts` before
//     `di/index.ts`).
// NOT ON. RIPWIRE_NO_IMPORT_SPEC (any value); a spec that is not module-shaped; a walk that reaches no definition (the spec row then
// says found="0" and the definition-side chains of the package's directory print as before).

#include "depdialect.h"          // dependencyDialect
#include "docparse.h"            // detail::readWholeFile
#include "infra/namesplit.h"     // isIdentChar
#include "model.h"
#include "resolve.h"             // JsonNode, parseJsonObject, exportsEntry, splitPackageSpecifier, joinNormalizeLookup, includerDir,
                                 // lexicalNormalize, jsRuntimeSourceExtOf
#include "serialize.h"           // escapeXml

#include <algorithm>
#include <array>
#include <cstddef>
#include <cstdint>
#include <cstdlib>
#include <optional>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

namespace rw
{

inline constexpr std::size_t kImportSpecDepth  = 12;    // statements one walk follows from the entry
inline constexpr std::size_t kImportSpecStates = 256;   // (file, name) states one walk visits; past it the walk says capped="1"

inline bool forImportSpecOn()
{
    return std::getenv( "RIPWIRE_NO_IMPORT_SPEC" ) == nullptr;
}

inline constexpr std::string_view kImportSpecLegend =
    "<!-- spec: the task spells an import. m= the specifier, n= the name; p= l= the package.json that declares the package (l= its "
    "exports key, else its name) or, for Python, the module file; entry= the file the specifier resolves to; cands=N N package.json "
    "files (or module files) answer it: nothing is guessed; external=1 no in-tree package declares it (no in-tree row is printed for "
    "it); found=0 the walk from entry reached no definition (the definition-side chains below are leads); capped=1 the walk stopped "
    "early. The def row after it is the definition the walk reached; its rx rows are the statements from entry to it, in import order "
    "(from= the module each one names, as= the name it renames, glob=1 a star / wildcard hop, hedged; val= a VALUE hop: the name is a value built from an import, `export const "
    "verify = Jwt.verify` or a member of an exported object literal `{ verify }`, not a re-export statement) -->";

namespace importspec_detail
{

// The words a task writes between NAME and `from` (`inject imported from`, `the Component decorator from`).
inline bool specCueWord( std::string_view w )
{
    static constexpr std::array<std::string_view, 22> kCue{ "imported", "exported", "re-exported", "reexported", "type", "types",
                                                            "decorator", "function", "class", "interface", "const", "constant",
                                                            "enum", "is", "was", "being", "as", "{", "}", "the", "a", "an" };
    return std::ranges::find( kCue, w ) != kCue.end();
}

inline bool identWord( std::string_view w )
{
    return !w.empty() && !( w.front() >= '0' && w.front() <= '9' )
        && std::ranges::all_of( w, []( char ch ) { return namesplit::isIdentChar( ch ) || ch == '$'; } );
}

// A dotted Python module path (`django.utils.deprecation`, `concurrent.futures`): identifier segments joined by `.`, at least two.
inline std::vector<std::string_view> dottedSegments( std::string_view m )
{
    std::vector<std::string_view> segs;
    for( std::size_t at = 0; at <= m.size(); )
    {
        const std::size_t end = std::min( m.find( '.', at ), m.size() );
        if( !identWord( m.substr( at, end - at ) ) )
        {
            return {};
        }
        segs.push_back( m.substr( at, end - at ) );
        at = end + 1;
    }
    return segs;
}

}   // namespace importspec_detail

// The import the task spells: NAME and the specifier as written; python = the specifier is a dotted Python module.
struct ImportSpecTask
{
    std::string name;
    std::string spec;
    bool        python = false;
};

// `NAME [cue…] from M` (M spelled as a module: `@s/p/sub`, `pkg/sub`, `./x`; or, after `imported`, a dotted Python module),
// `from a.b import NAME` (Python), or a dotted `a.b.NAME` token (Python; the caller resolves the prefix). The first one wins.
inline std::optional<ImportSpecTask> importSpecOf( const std::vector<std::string_view>& tokens )
{
    using namespace importspec_detail;
    const auto webModule = []( std::string_view m ) { return !m.empty() && ( m.front() == '@' || m.front() == '.' || m.contains( '/' ) ); };
    for( std::size_t i = 1; i + 1 < tokens.size(); ++i )
    {
        if( tokens[ i ] != "from" )
        {
            continue;
        }
        const std::string_view m = tokens[ i + 1 ];
        // `from a.b import NAME` (Python)
        if( i + 3 < tokens.size() && tokens[ i + 2 ] == "import" && !dottedSegments( m ).empty() && identWord( tokens[ i + 3 ] ) )
        {
            return ImportSpecTask{ std::string( tokens[ i + 3 ] ), std::string( m ), true };
        }
        std::size_t k = i;
        bool        imported = false;
        while( k > 0 && specCueWord( tokens[ k - 1 ] ) )
        {
            imported = imported || tokens[ k - 1 ] == "imported";
            --k;
        }
        if( k == 0 || !identWord( tokens[ k - 1 ] ) )
        {
            continue;
        }
        if( webModule( m ) && !m.contains( ' ' ) )
        {
            return ImportSpecTask{ std::string( tokens[ k - 1 ] ), std::string( m ), false };
        }
        if( imported && dottedSegments( m ).size() >= 2 )
        {
            return ImportSpecTask{ std::string( tokens[ k - 1 ] ), std::string( m ), true };
        }
    }
    if( tokens.size() >= 2 && tokens[ 0 ] == "from" && tokens.size() >= 4 && tokens[ 2 ] == "import" && identWord( tokens[ 3 ] )
        && !dottedSegments( tokens[ 1 ] ).empty() )
    {
        return ImportSpecTask{ std::string( tokens[ 3 ] ), std::string( tokens[ 1 ] ), true };
    }
    for( const std::string_view tok : tokens )   // a dotted `a.b.NAME`: the module is every segment but the last
    {
        const std::vector<std::string_view> segs = dottedSegments( tok );
        if( segs.size() >= 3 || ( segs.size() == 2 && !( segs.back().front() >= 'a' && segs.back().front() <= 'z' ) ) )
        {
            return ImportSpecTask{ std::string( segs.back() ), std::string( tok.substr( 0, tok.size() - segs.back().size() - 1 ) ), true };
        }
    }
    return std::nullopt;
}

namespace importspec_detail
{

using tsimport::JsonNode;   // resolve.h: the package.json reader the import resolver uses
using tsimport::exportsEntry;
using tsimport::parseJsonObject;
using tsimport::splitPackageSpecifier;

inline std::uint32_t lineAt( const std::string& text, std::size_t byte )
{
    return std::uint32_t( std::count( text.begin(), text.begin() + std::ptrdiff_t( std::min( byte, text.size() ) ), '\n' ) ) + 1;
}

// tsc's order for a relative, extensionless specifier: the FILE (`.ts`, `.tsx`, `.d.ts`) before the directory index. kNoFile when
// none answers or the specifier is not relative and extensionless (a runtime extension keeps the resolver's own answer).
inline std::uint32_t tsOrderFile( std::string_view importerRel, std::string_view module, const HashMap<std::string, std::uint32_t>& files )
{
    if( ( !module.starts_with( "./" ) && !module.starts_with( "../" ) && module != "." && module != ".." ) || jsRuntimeSourceExtOf( module ) != nullptr )
    {
        return kNoFile;
    }
    for( const std::string_view tail : { ".ts", ".tsx", ".d.ts", "/index.ts", "/index.tsx", "/index.d.ts", ".js", "/index.js" } )
    {
        if( const std::uint32_t f = joinNormalizeLookup( includerDir( importerRel ), module, files, nullptr, kNoFile, tail ); f != kNoFile )
        {
            return f;
        }
    }
    return kNoFile;
}

// A package.json target spelled as the build output (`./dist/middleware/jwt/index.js`, `./internal.js`) mapped to the source file
// that builds it, inside package directory `dir` ("" = the root): the target itself, then without its output directory
// (`dist`, `build`, `lib`, `out` and a following `types`/`esm`/`cjs`/`es`), under `src/` then bare; each in tsc's source order.
inline std::uint32_t sourceOfTarget( std::string_view dir, std::string_view target, const HashMap<std::string, std::uint32_t>& files )
{
    std::string t( target.starts_with( "./" ) ? target.substr( 2 ) : target );
    for( const std::string_view ext : { ".d.ts", ".js", ".mjs", ".cjs", ".jsx", ".ts", ".tsx" } )
    {
        if( t.ends_with( ext ) )
        {
            t.resize( t.size() - ext.size() );
            break;
        }
    }
    std::vector<std::string> bases{ t };
    std::string_view         rest( t );
    static constexpr std::array<std::string_view, 4> kOut{ "dist/", "build/", "lib/", "out/" };
    static constexpr std::array<std::string_view, 5> kSub{ "types/", "esm/", "cjs/", "es/", "mjs/" };
    if( const auto o = std::ranges::find_if( kOut, [ & ]( std::string_view p ) { return rest.starts_with( p ); } ); o != kOut.end() )
    {
        rest.remove_prefix( o->size() );
        for( auto s = std::ranges::find_if( kSub, [ & ]( std::string_view p ) { return rest.starts_with( p ); } ); s != kSub.end();
             s      = std::ranges::find_if( kSub, [ & ]( std::string_view p ) { return rest.starts_with( p ); } ) )
        {
            rest.remove_prefix( s->size() );
        }
        bases.push_back( "src/" + std::string( rest ) );
        bases.push_back( std::string( rest ) );
    }
    const std::string prefix = dir.empty() ? std::string() : std::string( dir ) + "/";
    for( const std::string& b : bases )
    {
        for( const std::string_view tail : { ".ts", ".tsx", ".mts", "/index.ts", "/index.tsx", ".d.ts", ".js", ".mjs", "/index.js", "" } )
        {
            if( const auto hit = files.find( lexicalNormalize( prefix + b + std::string( tail ) ) ); hit != files.end() )
            {
                return hit->second;
            }
        }
    }
    return kNoFile;
}

// The first string target of an exports entry under the conditions a consumer imports with (import, default, require, node, then
// types); a nested condition object is entered (depth-bounded).
inline std::string exportsTargetOf( const JsonNode& e, int depth = 0 )
{
    if( e.kind == JsonNode::Kind::Str )
    {
        return e.str;
    }
    if( e.kind == JsonNode::Kind::Arr && !e.vals.empty() && depth < 4 )
    {
        return exportsTargetOf( e.vals.front(), depth + 1 );
    }
    if( e.kind != JsonNode::Kind::Obj || depth >= 4 )
    {
        return {};
    }
    for( const std::string_view c : { "import", "default", "require", "node", "types" } )
    {
        if( const JsonNode* v = e.get( c ) )
        {
            if( std::string t = exportsTargetOf( *v, depth + 1 ); !t.empty() )
            {
                return t;
            }
        }
    }
    return {};
}

// The 1-based line of the first `"key"` in `text` (0 when absent).
inline std::uint32_t lineOfKey( const std::string& text, std::string_view key )
{
    const std::size_t at = text.find( "\"" + std::string( key ) + "\"" );
    return at == std::string::npos ? 0 : lineAt( text, at );
}

}   // namespace importspec_detail

namespace importspec_detail
{

// A test, fixture, mock or vendored copy (`…/tests/test-workspace/mock_packages/@angular/core/package.json`, `Lib/test/…`) is not
// the package or module a task spells: dropped whenever a copy outside such directories answers.
inline bool testCopyPath( std::string_view rel )
{
    const std::string p = "/" + std::string( rel );
    return std::ranges::any_of( std::array<std::string_view, 7>{ "/test/", "/tests/", "/fixtures/", "/mock_packages/", "/site-packages/",
                                                                  "/node_modules/", "/__fixtures__/" },
                                [ & ]( std::string_view d ) { return p.contains( d ); } );
}

}   // namespace importspec_detail

// Where an import specifier lands: the package.json (or Python module file) that answers it and the entry file.
struct SpecEntry
{
    enum class Kind : std::uint8_t { External, Ambiguous, Unresolved, Resolved };
    Kind          kind     = Kind::External;
    std::uint32_t manifest = kNoFile;   // the package.json (Python: the module file)
    std::uint32_t line     = 0;         // its exports key's line (else its name's)
    std::uint32_t entry    = kNoFile;
    std::size_t   cands    = 0;
    std::string   pkgDir;               // the package directory ("" = the root), for the definition-side fallback
};

// TS/JS: the in-tree package.json whose `name` is the spec's package, and the entry its subpath selects.
inline SpecEntry resolveWebSpec( const IngestResult& ing, const HashMap<std::string, std::uint32_t>& files, std::string_view spec )
{
    using namespace importspec_detail;
    using tsimport::JsonNode;
    SpecEntry  out;
    const auto [ pkg, sub ] = splitPackageSpecifier( spec );
    if( pkg.empty() || spec.starts_with( '.' ) )
    {
        return out;
    }
    std::vector<std::pair<std::uint32_t, JsonNode>> hits;
    std::vector<std::string>                        texts;
    for( std::uint32_t f = 0; f < ing.files.size(); ++f )
    {
        const std::string_view rel = rootRelPath( ing, f );
        if( rel != "package.json" && !rel.ends_with( "/package.json" ) )
        {
            continue;
        }
        std::string text = docparse::detail::readWholeFile( diskPath( ing, f ) ).value_or( std::string() );
        if( !text.contains( "\"" + std::string( pkg ) + "\"" ) )
        {
            continue;
        }
        JsonNode pj;
        const JsonNode* name = parseJsonObject( text, pj ) ? pj.get( "name" ) : nullptr;
        if( name != nullptr && name->kind == JsonNode::Kind::Str && name->str == pkg )
        {
            hits.emplace_back( f, std::move( pj ) );
            texts.push_back( std::move( text ) );
        }
    }
    if( std::ranges::any_of( hits, [ & ]( const auto& h ) { return !testCopyPath( rootRelPath( ing, h.first ) ); } ) )
    {
        for( std::size_t cursor = hits.size(); cursor > 0; --cursor )   // counts down to 1 (no unsigned wrap under -fsanitize=integer)
        {
            if( testCopyPath( rootRelPath( ing, hits[ cursor - 1 ].first ) ) )
            {
                hits.erase( hits.begin() + std::ptrdiff_t( cursor - 1 ) );
                texts.erase( texts.begin() + std::ptrdiff_t( cursor - 1 ) );
            }
        }
    }
    out.cands = hits.size();
    if( hits.size() != 1 )
    {
        out.kind = hits.empty() ? SpecEntry::Kind::External : SpecEntry::Kind::Ambiguous;
        return out;
    }
    const auto& [ f, pj ] = hits.front();
    const std::string_view rel = rootRelPath( ing, f );
    out.manifest = f;
    out.pkgDir   = std::string( rel.substr( 0, rel.size() - std::string_view( "package.json" ).size() ) );
    if( !out.pkgDir.empty() )
    {
        out.pkgDir.pop_back();   // the trailing '/'
    }
    out.kind = SpecEntry::Kind::Unresolved;
    out.line = lineOfKey( texts.front(), "name" );
    if( const JsonNode* ex = pj.get( "exports" ); ex != nullptr && ex->kind != JsonNode::Kind::Other )
    {
        std::string capture;
        if( const JsonNode* e = exportsEntry( *ex, sub, capture ) )
        {
            std::string t = exportsTargetOf( *e );
            for( std::size_t star = t.find( '*' ); !capture.empty() && star != std::string::npos; star = t.find( '*', star + capture.size() ) )
            {
                t.replace( star, 1, capture );
            }
            out.entry = t.empty() ? kNoFile : sourceOfTarget( out.pkgDir, t, files );
            if( const std::uint32_t l = lineOfKey( texts.front(), sub ); l != 0 && ex->kind == JsonNode::Kind::Obj && ex->get( sub ) != nullptr )
            {
                out.line = l;
            }
        }
    }
    if( out.entry == kNoFile && sub != "." )
    {
        out.entry = sourceOfTarget( out.pkgDir, sub, files );
    }
    for( const std::string_view field : { "module", "main", "types" } )
    {
        const JsonNode* v = out.entry == kNoFile && sub == "." ? pj.get( field ) : nullptr;
        if( v != nullptr && v->kind == JsonNode::Kind::Str && !v->str.empty() )
        {
            out.entry = sourceOfTarget( out.pkgDir, v->str, files );
        }
    }
    if( out.entry == kNoFile && sub == "." )
    {
        out.entry = sourceOfTarget( out.pkgDir, "index", files );
    }
    out.kind = out.entry == kNoFile ? SpecEntry::Kind::Unresolved : SpecEntry::Kind::Resolved;
    return out;
}

// Python: the in-tree file of dotted module `m` (`a/b.py` or `a/b/__init__.py`, under any directory); several = ambiguous.
inline SpecEntry resolvePythonSpec( const IngestResult& ing, std::string_view m )
{
    SpecEntry   out;
    std::string path( m );
    std::ranges::replace( path, '.', '/' );
    const std::string asFile = path + ".py", asPkg = path + "/__init__.py";
    std::vector<std::uint32_t> hits;
    for( std::uint32_t f = 0; f < ing.files.size(); ++f )
    {
        const std::string_view rel = rootRelPath( ing, f );
        for( const std::string& want : { asFile, asPkg } )
        {
            if( rel == want || ( rel.ends_with( want ) && rel[ rel.size() - want.size() - 1 ] == '/' ) )
            {
                hits.push_back( f );
            }
        }
    }
    const auto testish = [ & ]( std::uint32_t f ) { return importspec_detail::testCopyPath( rootRelPath( ing, f ) ); };
    if( std::ranges::any_of( hits, [ & ]( std::uint32_t f ) { return !testish( f ); } ) )
    {
        std::erase_if( hits, testish );
    }
    out.cands = hits.size();
    if( hits.size() != 1 )
    {
        out.kind = hits.empty() ? SpecEntry::Kind::External : SpecEntry::Kind::Ambiguous;
        return out;
    }
    out.kind     = SpecEntry::Kind::Resolved;
    out.manifest = hits.front();
    out.entry    = hits.front();
    return out;
}

// One statement the walk followed: its file and byte, the module it names, the name it takes there, and how.
struct SpecHop
{
    std::uint32_t file  = kNoFile;
    std::uint32_t byte  = 0;
    std::string   from;
    std::string   taken;      // the name the statement takes from `from` (== the name it binds unless renamed)
    std::string   bound;      // the name it binds in `file`
    bool          glob  = false;
    std::string   val;        // VALUE-HOP: the value expression that hands the name on (`Jwt.verify`, `{ verify }`); empty for a statement
};

// The walk's result: the definition reached and the statements from the entry to it, in import order.
struct SpecWalk
{
    const Symbol*        def = nullptr;
    std::vector<SpecHop> hops;
    std::size_t          defs   = 0;       // definitions reached at the same depth (>1: hedged)
    bool                 capped = false;
};

namespace importspec_detail
{

// Python: the `from M import …` statements of `text` (also PEP 810 `lazy from M import …`), each name with its alias, and
// `from M import *`. Line-based; a parenthesized list may span lines. A statement inside a block (indented) is read too.
struct PyFrom
{
    std::size_t byte = 0;
    std::string module;
    std::vector<std::pair<std::string, std::string>> names;   // (taken, bound); ("*","*") for a star
};

inline std::vector<PyFrom> pythonFroms( const std::string& text )
{
    std::vector<PyFrom> out;
    for( std::size_t at = 0; at < text.size(); )
    {
        const std::size_t eol  = std::min( text.find( '\n', at ), text.size() );
        std::string_view  line = std::string_view( text ).substr( at, eol - at );
        const std::size_t lineStart = at;
        at = eol + 1;
        const std::size_t ind = line.find_first_not_of( " \t" );
        if( ind == std::string_view::npos )
        {
            continue;
        }
        line.remove_prefix( ind );
        if( line.starts_with( "lazy from " ) )
        {
            line.remove_prefix( 5 );
        }
        if( !line.starts_with( "from " ) )
        {
            continue;
        }
        const std::size_t imp = line.find( " import " );
        if( imp == std::string_view::npos )
        {
            continue;
        }
        PyFrom pf{ .byte = lineStart + ind, .module = std::string( line.substr( 5, imp - 5 ) ) };
        std::erase( pf.module, ' ' );
        std::string list( line.substr( imp + 8 ) );
        if( list.contains( '(' ) )
        {
            while( !list.contains( ')' ) && at < text.size() )   // a parenthesized list runs to its `)`
            {
                const std::size_t e2 = std::min( text.find( '\n', at ), text.size() );
                list.append( " " ).append( text, at, e2 - at );
                at = e2 + 1;
            }
        }
        if( const std::size_t hash = list.find( '#' ); hash != std::string::npos && !list.contains( '(' ) )
        {
            list.resize( hash );
        }
        for( char& ch : list )
        {
            ch = ( ch == '(' || ch == ')' || ch == '\\' || ch == '\t' || ch == '\r' ) ? ' ' : ch;
        }
        for( std::size_t p = 0; p <= list.size(); )
        {
            const std::size_t comma = std::min( list.find( ',', p ), list.size() );
            std::string_view  item  = std::string_view( list ).substr( p, comma - p );
            p                       = comma + 1;
            if( const std::size_t hash = item.find( '#' ); hash != std::string_view::npos )
            {
                item = item.substr( 0, hash );
            }
            const std::size_t b = item.find_first_not_of( ' ' );
            if( b == std::string_view::npos )
            {
                continue;
            }
            item = item.substr( b, item.find_last_not_of( ' ' ) - b + 1 );
            const std::size_t as = item.find( " as " );
            std::string taken( item.substr( 0, as ) ), bound( as == std::string_view::npos ? item : item.substr( as + 4 ) );
            std::erase( taken, ' ' );
            std::erase( bound, ' ' );
            if( taken == "*" || identWord( taken ) )
            {
                pf.names.emplace_back( std::move( taken ), std::move( bound ) );
            }
        }
        if( !pf.names.empty() && !pf.module.empty() )
        {
            out.push_back( std::move( pf ) );
        }
    }
    return out;
}

// The file a Python `from M import` names, from file `f`: a relative M (`.thread`, `..x`) against f's package, an absolute one
// through resolvePythonSpec. kNoFile when none or several answer.
inline std::uint32_t pythonModuleFile( const IngestResult& ing, const HashMap<std::string, std::uint32_t>& files, std::uint32_t f, std::string_view m )
{
    if( !m.starts_with( '.' ) )
    {
        const SpecEntry e = resolvePythonSpec( ing, m );
        return e.kind == SpecEntry::Kind::Resolved ? e.entry : kNoFile;
    }
    std::string dir( includerDir( rootRelPath( ing, f ) ) );
    std::size_t dots = 0;
    while( dots < m.size() && m[ dots ] == '.' )
    {
        ++dots;
    }
    for( std::size_t up = 1; up < dots; ++up )
    {
        const std::size_t slash = dir.rfind( '/' );
        dir                     = slash == std::string::npos ? std::string() : dir.substr( 0, slash );
    }
    std::string rest( m.substr( dots ) );
    std::ranges::replace( rest, '.', '/' );
    const std::string base = dir.empty() ? rest : rest.empty() ? dir : dir + "/" + rest;
    for( const std::string& cand : { base + ".py", ( base.empty() ? std::string() : base + "/" ) + "__init__.py" } )
    {
        if( const auto hit = files.find( cand ); hit != files.end() )
        {
            return hit->second;
        }
    }
    return kNoFile;
}

// VALUE-HOP: a top-level `export const NAME = Q.M` (also let/var) in `text`: (Q, M, the statement's byte); nullopt when absent.
struct MemberAlias
{
    std::string   q, m;
    std::size_t   byte = 0;
};

inline std::optional<MemberAlias> memberAliasOf( const std::string& text, std::string_view name )
{
    for( const std::string_view kw : { "export const ", "export let ", "export var " } )
    {
        const std::string head = std::string( kw ) + std::string( name ) + " = ";
        for( std::size_t at = text.find( head ); at != std::string::npos; at = text.find( head, at + 1 ) )
        {
            if( at != 0 && text[ at - 1 ] != '\n' )
            {
                continue;
            }
            const std::size_t eol  = std::min( text.find( '\n', at ), text.size() );
            std::string_view  expr = std::string_view( text ).substr( at + head.size(), eol - at - head.size() );
            while( !expr.empty() && ( expr.back() == ';' || expr.back() == ' ' || expr.back() == '\r' ) )
            {
                expr.remove_suffix( 1 );
            }
            const std::size_t dot = expr.find( '.' );
            if( dot != std::string_view::npos && identWord( expr.substr( 0, dot ) ) && identWord( expr.substr( dot + 1 ) ) )
            {
                return MemberAlias{ std::string( expr.substr( 0, dot ) ), std::string( expr.substr( dot + 1 ) ), at };
            }
        }
    }
    return std::nullopt;
}

// VALUE-HOP: the local name an object literal binds member `m` to, inside [from, to) of `text` (`{ sign, verify }` -> verify;
// `{ verify: verifyImpl }` -> verifyImpl); empty when the span holds no top-level object member m.
inline std::string objectMemberLocal( const std::string& text, std::size_t from, std::size_t to, std::string_view m )
{
    const std::size_t open = text.find( '{', from );
    if( open == std::string::npos || open >= to )
    {
        return {};
    }
    int         depth = 0;
    std::size_t item  = open + 1;
    for( std::size_t i = open; i < std::min( to, text.size() ); ++i )
    {
        const char ch = text[ i ];
        depth += ( ch == '{' || ch == '(' || ch == '[' ) ? 1 : ( ch == '}' || ch == ')' || ch == ']' ) ? -1 : 0;
        if( ( depth == 1 && ch == ',' ) || depth == 0 )
        {
            std::string_view e = std::string_view( text ).substr( item, i - item );
            const std::size_t b = e.find_first_not_of( " \t\r\n" );
            e = b == std::string_view::npos ? std::string_view() : e.substr( b, e.find_last_not_of( " \t\r\n" ) - b + 1 );
            const std::size_t colon = e.find( ':' );
            const std::string_view key = colon == std::string_view::npos ? e : e.substr( 0, e.find_last_not_of( " \t", colon - 1 ) + 1 );
            if( key == m )
            {
                std::string_view v = colon == std::string_view::npos ? e : e.substr( colon + 1 );
                v = v.substr( std::min( v.find_first_not_of( " \t" ), v.size() ) );
                return identWord( v ) ? std::string( v ) : std::string();
            }
            item = i + 1;
            if( depth == 0 )
            {
                break;
            }
        }
    }
    return {};
}

}   // namespace importspec_detail

// Breadth-first from (entry, name): a top-level definition of the name in the file ends the walk; otherwise each statement that
// binds the name hands the walk on to the file it names (TS/JS ReExport records, `webTarget` resolving their module; Python
// `from … import` lines). The shortest path wins; other definitions at the same depth are counted (defs=).
template <class WebTarget>
inline SpecWalk walkImportSpec( const IngestResult& ing, const HashMap<std::string, std::uint32_t>& files, std::uint32_t entry, std::string_view name,
                                bool python, WebTarget&& webTarget )
{
    using namespace importspec_detail;
    SpecWalk out;
    HashMap<std::string, const Symbol*> defs;   // "<file>#<name>" -> the top-level definition
    for( const Symbol& s : ing.symbols )
    {
        const DepDialect d = dependencyDialect( s.lang );
        // top level: no owner scope (a Python class carries its own name as its scope)
        const bool top = s.scope.empty() || ( python && s.scope == s.name );
        if( ( python ? d == DepDialect::Python : d == DepDialect::Web ) && top && s.kind != SymKind::Method && s.kind != SymKind::Other )
        {
            defs.try_emplace( std::to_string( s.fileId ) + "#" + s.name, &s );
        }
    }
    HashMap<std::uint32_t, std::vector<const Binding*>> reexports;   // Web ReExport records by file
    HashMap<std::string, const Binding*>                imports;     // VALUE-HOP: "<file>#<local>" -> the named ES import binding it
    if( !python )
    {
        for( const Binding& b : ing.bindings )
        {
            if( b.kind == LocalBindKind::ReExport )
            {
                reexports[ b.fileId ].push_back( &b );
            }
            else if( b.kind == LocalBindKind::JsImport && !b.importedName.empty() )
            {
                imports.try_emplace( std::to_string( b.fileId ) + "#" + b.var, &b );
            }
        }
    }
    HashMap<std::uint32_t, std::optional<std::string>> texts;
    const auto textOf = [ & ]( std::uint32_t f ) -> const std::string&
    {
        auto [ it, fresh ] = texts.try_emplace( f );
        if( fresh )
        {
            it->second = docparse::detail::readWholeFile( diskPath( ing, f ) ).value_or( std::string() );
        }
        return *it->second;
    };
    struct State
    {
        std::uint32_t file;
        std::string   name;
        int           parent;
        SpecHop       hop;
        std::size_t   depth;
        std::string   member;   // VALUE-HOP: the member of `name` (an object) the walk is after; empty: name itself
    };
    std::vector<State>         states{ State{ entry, std::string( name ), -1, {}, 0, {} } };
    HashMap<std::string, char> seen;
    seen.try_emplace( std::to_string( entry ) + "#" + std::string( name ), '\0' );
    HashMap<std::uint32_t, std::vector<PyFrom>> pyCache;
    int         found      = -1;
    std::size_t foundDepth = 0;
    for( std::size_t at = 0; at < states.size(); ++at )
    {
        const State st = states[ at ];
        if( found >= 0 && st.depth > foundDepth )
        {
            break;
        }
        const auto d = defs.find( std::to_string( st.file ) + "#" + st.name );
        std::vector<SpecHop> next;
        std::string          nextMember;
        if( !python && !st.member.empty() )   // VALUE-HOP: the object's member, imported into this file
        {
            const std::string& text = textOf( st.file );
            // the object: its definition's span, else (an object-literal const is no indexed definition) its `[export] const X = {` line
            std::size_t from = d != defs.end() ? d->second->sigStartByte : std::string::npos;
            const std::size_t end = d != defs.end() ? d->second->endByte : text.size();
            for( const std::string_view kw : { "export const ", "const " } )
            {
                const std::string head = std::string( kw ) + st.name + " = ";
                for( std::size_t at = text.find( head ); from == std::string::npos && at != std::string::npos; at = text.find( head, at + 1 ) )
                {
                    from = at == 0 || text[ at - 1 ] == '\n' ? at : std::string::npos;
                }
            }
            const std::string   local = from == std::string::npos ? std::string() : objectMemberLocal( text, from, end, st.member );
            const auto          imp   = local.empty() ? imports.end() : imports.find( std::to_string( st.file ) + "#" + local );
            const std::uint32_t to    = imp == imports.end() ? kNoFile : webTarget( imp->second );
            if( to != kNoFile )
            {
                const std::size_t bol = text.rfind( '\n', std::min( from, text.size() ) );
                next.push_back( SpecHop{ to, std::uint32_t( bol == std::string::npos || bol + 1 > from ? from : bol + 1 ), imp->second->typeName, imp->second->importedName, st.member, false,
                                         "{ " + st.member + ( local == st.member ? std::string() : ": " + local ) + " }" } );
            }
        }
        if( next.empty() && d != defs.end() )
        {
            if( found < 0 )
            {
                found      = int( at );
                foundDepth = st.depth;
                out.def    = d->second;
            }
            ++out.defs;
            continue;
        }
        if( st.depth >= kImportSpecDepth )
        {
            continue;
        }
        if( python )
        {
            auto [ it, fresh ] = pyCache.try_emplace( st.file );
            if( fresh )
            {
                it->second = pythonFroms( docparse::detail::readWholeFile( diskPath( ing, st.file ) ).value_or( std::string() ) );
            }
            for( const PyFrom& pf : it->second )
            {
                for( const auto& [ taken, bound ] : pf.names )
                {
                    if( bound == st.name || taken == "*" )
                    {
                        const std::uint32_t to = pythonModuleFile( ing, files, st.file, pf.module );
                        if( to != kNoFile )
                        {
                            next.push_back( SpecHop{ to, std::uint32_t( pf.byte ), pf.module, taken == "*" ? st.name : taken, st.name, taken == "*", {} } );
                        }
                    }
                }
            }
        }
        else if( const auto rx = reexports.find( st.file ); rx != reexports.end() )
        {
            for( const Binding* b : rx->second )
            {
                const bool star = b->importedName == "*" && b->var == "*";
                if( !star && ( b->importedName == "*" || b->var != st.name ) )
                {
                    continue;   // a namespace hop (`export * as X`) or another name
                }
                const std::uint32_t to = webTarget( b );
                if( to != kNoFile )
                {
                    next.push_back( SpecHop{ to, b->startByte, b->typeName, star ? st.name : b->importedName, st.name, star, {} } );
                }
            }
        }
        if( !python && next.empty() && st.member.empty() )   // VALUE-HOP: `export const NAME = Q.M`, Q a named import of this file
        {
            const std::string& text = textOf( st.file );
            if( const std::optional<MemberAlias> a = memberAliasOf( text, st.name ) )
            {
                const auto imp = imports.find( std::to_string( st.file ) + "#" + a->q );
                const std::uint32_t to = imp == imports.end() ? kNoFile : webTarget( imp->second );
                if( to != kNoFile )
                {
                    next.push_back( SpecHop{ to, std::uint32_t( a->byte ), imp->second->typeName, imp->second->importedName, st.name, false, a->q + "." + a->m } );
                    nextMember = a->m;
                }
            }
        }
        for( SpecHop& h : next )
        {
            if( states.size() >= kImportSpecStates )
            {
                out.capped = true;
                break;
            }
            std::string key = std::to_string( h.file ) + "#" + h.taken;
            if( !seen.try_emplace( std::move( key ), '\0' ).second )
            {
                continue;
            }
            const std::uint32_t to = h.file;
            std::string         taken = h.taken;
            h.file = st.file;   // the statement sits in the state's file; the next state is the file it names
            const std::string member = h.val.empty() || h.val.starts_with( '{' ) ? std::string() : nextMember;
            states.push_back( State{ to, std::move( taken ), int( at ), std::move( h ), st.depth + 1, member } );
        }
    }
    for( int i = found; i > 0; i = states[ std::size_t( i ) ].parent )
    {
        out.hops.insert( out.hops.begin(), states[ std::size_t( i ) ].hop );
    }
    return out;
}

}   // namespace rw
