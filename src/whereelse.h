#pragma once
// whereelse.h — WHERE-ELSE: the one helper family for "where else does a change land" (lane WHERE-ELSE-SHARED, 11-27, LESSON-APPLY 1).
//
// WHY. Three answers name the non-code files a change also touches: --for's <listed> (listedin.h: the manifest lines listing a shown
// file), --for's <where> (the act files' tests, changelog and build file) and --brief's <where-else> (the unit's tests, build file and
// changelog). Each grew its own manifest table, its own ancestor walk, its own changelog names and its own test ranking, and they
// disagreed: a substring "names the file" in one (`log.c` inside `catalog.c`), whole-segment names in another; a root-only changelog
// in one, the nearest one in the other. This header is the one place; listedin.h reads through it today, and the two other callers
// switch to it when they land (DESIGN: tmp/orch-1127/where-else/DESIGN.md in the orchestration notes; CONTRIBUTING family 10c).
//
// LAYERS, top to bottom:
//   1. ECOSYSTEM — the one table of build / package manifests (kManifestKinds): per name its comment syntax and its roles (read by
//      LISTED-IN, a unit's build file, a package root, lists sources by FILE path); included build fragments by extension
//      (kFragmentKinds); changelog names (changelogName). A new build system is one row here, not a new reader.
//   2. DIRECTORIES — walkDirsUp (the one upward walk), isVendoredDir, readDirManifests / manifestsAbove (the manifests at and above a
//      file, nearest first).
//   3. NAMES — boundedFind / tokensFor: does a manifest line name this file (whole path segments, relative to the manifest's own
//      directory, never a same-named file elsewhere); nearestNaming (the nearest manifest that names a file, and the line).
//   4. CHANGELOG — changelogIn (one directory: a fragment directory before a file, since a repo with changelog.d/ adds fragments and
//      generates the file), changelogNear (the nearest directory holding one, from a file up to the root).
//   5. TESTS — subjectTestHits / rankSubjectTests: the test files that call into a subject file and its siblings, ranked by whether
//      they reach the exemplar symbol, then by how much of the test is ABOUT the subject (its share of the test's cross-file calls).
#include "darkflags.h"    // forEachLine — the one line splitter over raw file text (CR stripped)
#include "ingest.h"       // kDefaultMaxFileBytes — the crawl size ceiling a manifest read also honours
#include "docparse.h"     // readRegularFile — a fixed-name file in the tree, refused when it is not a regular file
#include "graph.h"        // Graph — the resolved out-edge CSR the test layer counts
#include "taskroute.h"    // taskroute::wordByte — the word byte (alnum or _)
#include "model.h"        // IngestResult, rootRelPath, diskPath
#include "infra/namesplit.h" // namesplit::afterLast — the ONE base-name cut
#include "infra/sortutil.h" // sortutil::svLess — string_view ordering is never operator< (portablebuildcheck #6)

#include <algorithm>
#include <array>
#include <cctype>
#include <cstddef>
#include <cstdint>
#include <filesystem>
#include <optional>
#include <span>
#include <string>
#include <string_view>
#include <system_error>
#include <utility>
#include <vector>

namespace rw::whereelse
{

// ── 1. ecosystem ──────────────────────────────────────────────────────────────────────────────────────────────────────────────────

// How a manifest comments: make (`#`, a trailing backslash continues the comment), CMake (`#`, `#[[ ]]`, `#[=[ ]=]`), the other hash
// formats (meson, Bazel, TOML, Python: `#` outside "…" and '…'), C-style (`//`, `/* */` outside "…": JSON with comments, Gradle, go.mod)
// and XML (`<!-- -->`).
enum class CommentStyle : unsigned char { Make, CMake, Hash, JsonC, Xml };

// A manifest's roles, OR-ed.
enum ManifestRole : std::uint8_t
{
    kRoleListedIn = 1,   // LISTED-IN reads it for the lines that list a shown file (listedin.h)
    kRoleUnit     = 2,   // a unit's build file: the file a new sibling unit is listed in or built by (--brief, --for <where>)
    kRolePackage  = 4,   // a package root: a file under it belongs to that package, not to an outer one
    kRoleByFile   = 8,   // it lists sources by FILE path: a directory there is a command's argument or a dep label, not a listing
};

struct ManifestKind
{
    std::string_view name;   // exact (case-sensitive) file name, or the extension of a fragment (kFragmentKinds)
    CommentStyle     style;
    std::uint8_t     roles;
    std::uint8_t     unitRank;   // the nearest-unit fallback's order inside one directory (lower first): the build a project is
                                 // configured by before a convenience wrapper (CMakeLists.txt before a Makefile that calls cmake)
};

// Table order is the read order inside one directory (LISTED-IN prints manifests in it, so it never depends on directory order).
inline constexpr ManifestKind kManifestKinds[] = {
    { "Makefile.am", CommentStyle::Make, kRoleListedIn | kRoleUnit | kRoleByFile, 6 },
    { "Makefile", CommentStyle::Make, kRoleListedIn | kRoleUnit | kRoleByFile, 7 },
    { "GNUmakefile", CommentStyle::Make, kRoleListedIn | kRoleUnit | kRoleByFile, 7 },
    { "CMakeLists.txt", CommentStyle::CMake, kRoleListedIn | kRoleUnit | kRoleByFile, 3 },
    { "meson.build", CommentStyle::Hash, kRoleListedIn | kRoleUnit | kRoleByFile, 5 },
    { "BUILD", CommentStyle::Hash, kRoleListedIn | kRoleUnit | kRoleByFile, 1 },
    { "BUILD.bazel", CommentStyle::Hash, kRoleListedIn | kRoleUnit | kRoleByFile, 0 },
    { "package.json", CommentStyle::JsonC, kRoleListedIn | kRoleUnit | kRolePackage, 8 },
    { "jsr.json", CommentStyle::JsonC, kRoleListedIn | kRoleUnit | kRolePackage, 9 },
    { "deno.json", CommentStyle::JsonC, kRoleListedIn | kRoleUnit | kRolePackage, 9 },
    { "Cargo.toml", CommentStyle::Hash, kRoleListedIn | kRoleUnit | kRolePackage, 4 },
    { "BUILD.gn", CommentStyle::Hash, kRoleUnit | kRoleByFile, 2 },
    { "pom.xml", CommentStyle::Xml, kRoleUnit | kRolePackage, 10 },
    { "build.gradle", CommentStyle::JsonC, kRoleUnit | kRolePackage, 10 },
    { "build.gradle.kts", CommentStyle::JsonC, kRoleUnit | kRolePackage, 10 },
    { "pyproject.toml", CommentStyle::Hash, kRoleUnit | kRolePackage, 11 },
    { "setup.py", CommentStyle::Hash, kRoleUnit | kRolePackage, 12 },
    { "project.json", CommentStyle::JsonC, kRoleUnit, 13 },
    { "go.mod", CommentStyle::JsonC, kRoleUnit | kRolePackage, 14 },
};

// Included build fragments, by extension (name order inside a directory, at most kFragmentsPerDir of them read).
inline constexpr ManifestKind kFragmentKinds[] = {
    { "bzl", CommentStyle::Hash, kRoleListedIn | kRoleUnit, 15 },
    { "cmake", CommentStyle::CMake, kRoleUnit | kRoleByFile, 15 },
    { "mk", CommentStyle::Make, kRoleUnit | kRoleByFile, 15 },
    { "gni", CommentStyle::Hash, kRoleUnit | kRoleByFile, 15 },
};

inline constexpr std::size_t    kFragmentsPerDir = 8;                      // fragment files read per directory (a runaway guard, disclosed)
inline constexpr std::uintmax_t kManifestBytes   = kDefaultMaxFileBytes;   // a manifest above the crawl ceiling is not read (a floor)

// The kind of the file `name` (a base name), or nullptr: a fixed name first, else a fragment by its extension.
inline const ManifestKind* manifestKindOf( std::string_view name ) noexcept
{
    for( const ManifestKind& k : kManifestKinds )
    {
        if( k.name == name )
        {
            return &k;
        }
    }
    const std::size_t dot = name.rfind( '.' );
    for( const ManifestKind& k : kFragmentKinds )
    {
        if( dot != std::string_view::npos && name.substr( dot + 1 ) == k.name )
        {
            return &k;
        }
    }
    return nullptr;
}

// A build manifest or fragment by its path (any role): the co-change sorter's "build" slot.
inline bool isManifestPath( std::string_view rel ) noexcept
{
    return manifestKindOf( namesplit::afterLast( rel, "/" ) ) != nullptr;
}

// `text` with every comment byte blanked (line breaks kept, so line numbers and offsets are unchanged). A string ("…", and '…' where
// the format has it) protects a `#` or `//` inside it and ends with its line; make has no quotes (a `#` always starts a comment).
inline std::string blankComments( std::string_view text, CommentStyle style )
{
    std::string       code( text );
    const std::size_t n = text.size();
    const auto        blank = [ & ]( std::size_t from, std::size_t to )
    {
        for( std::size_t k = from; k < to; ++k )
        {
            if( code[k] != '\n' && code[k] != '\r' )
            {
                code[k] = ' ';
            }
        }
    };
    const auto lineEnd = [ & ]( std::size_t from ) { return std::min( text.find( '\n', from ), n ); };
    const auto continues = [ & ]( std::size_t end )   // the line ending at `end` ends in a backslash (before an optional CR)
    {
        while( end > 0 && text[end - 1] == '\r' )
        {
            --end;
        }
        return end > 0 && text[end - 1] == '\\';
    };
    if( style == CommentStyle::Xml )   // `<!-- … -->`, which may span lines; XML has no line comment and quotes do not protect it
    {
        for( std::size_t at = text.find( "<!--" ); at != std::string_view::npos; at = text.find( "<!--", at ) )
        {
            const std::size_t close = text.find( "-->", at + 4 );
            const std::size_t stop  = close == std::string_view::npos ? n : close + 3;
            blank( at, stop );
            at = stop;
        }
        return code;
    }
    char quote = 0;
    for( std::size_t i = 0; i < n; ++i )
    {
        const char c = text[i];
        if( c == '\n' )
        {
            quote = 0;
        }
        else if( quote != 0 )
        {
            i += c == '\\' && i + 1 < n && text[i + 1] != '\n' ? 1 : 0;
            quote = c == quote ? 0 : quote;
        }
        else if( style == CommentStyle::Make && c == '\\' )
        {
            i += i + 1 < n && text[i + 1] != '\n' ? 1 : 0;   // `\#` is not a comment
        }
        else if( style != CommentStyle::Make && ( c == '"' || ( c == '\'' && style == CommentStyle::Hash ) ) )
        {
            quote = c;
        }
        else if( c == '#' && style != CommentStyle::JsonC )
        {
            std::size_t stop = lineEnd( i );
            if( style == CommentStyle::CMake && i + 1 < n && text[i + 1] == '[' )   // `#[[ … ]]` / `#[==[ … ]==]`, which may span lines
            {
                std::size_t eq = i + 2;
                while( eq < n && text[eq] == '=' )
                {
                    ++eq;
                }
                if( eq < n && text[eq] == '[' )
                {
                    const std::string close = "]" + std::string( eq - i - 2, '=' ) + "]";
                    const std::size_t at    = text.find( close, eq + 1 );
                    stop                    = at == std::string_view::npos ? n : at + close.size();
                }
            }
            blank( i, stop );
            // a make comment ending in a backslash continues onto the next line
            while( style == CommentStyle::Make && stop < n && continues( stop ) )
            {
                const std::size_t next = lineEnd( stop + 1 );
                blank( stop + 1, next );
                stop = next;
            }
            i = stop > 0 ? stop - 1 : 0;
        }
        else if( c == '/' && style == CommentStyle::JsonC && i + 1 < n && ( text[i + 1] == '/' || text[i + 1] == '*' ) )
        {
            const std::size_t stop = text[i + 1] == '/' ? lineEnd( i ) : ( text.find( "*/", i + 2 ) == std::string_view::npos ? n : text.find( "*/", i + 2 ) + 2 );
            blank( i, stop );
            i = stop - 1;
        }
    }
    return code;
}

inline bool saysGenerated( std::string_view text ) noexcept
{
    const std::string_view head = text.substr( 0, std::min<std::size_t>( text.size(), 400 ) );
    return head.find( "generated by" ) != std::string_view::npos || head.find( "Generated by" ) != std::string_view::npos
        || head.find( "DO NOT EDIT" ) != std::string_view::npos;
}

// A changelog's name: CHANGELOG, CHANGES, NEWS, HISTORY, RELEASE?NOTES (any case) for a file, the lead word whole (`newsletter.md` is
// not NEWS) and then nothing or a '.', '_' or '-' tail that is prose (no extension, or .md .rst .txt .adoc .markdown); changelog,
// changelog.d, changes, .changes, .changeset for a directory (towncrier, changie, changesets fragments).
inline bool changelogName( std::string_view name, bool dir ) noexcept
{
    std::string low( name );
    std::ranges::transform( low, low.begin(), []( unsigned char ch ) { return char( std::tolower( ch ) ); } );
    if( dir )
    {
        return low == "changelog" || low == "changelog.d" || low == "changes" || low == ".changes" || low == ".changeset";
    }
    for( const std::string_view lead : { "changelog", "changes", "news", "history", "release-notes", "release_notes", "releasenotes" } )
    {
        if( !low.starts_with( lead ) )
        {
            continue;
        }
        const std::string_view rest = std::string_view( low ).substr( lead.size() );
        const std::size_t      dot  = rest.rfind( '.' );
        const std::string_view ext  = dot == std::string_view::npos ? std::string_view() : rest.substr( dot + 1 );
        const bool             prose = dot == std::string_view::npos || ext == "md" || ext == "rst" || ext == "txt" || ext == "adoc" || ext == "markdown";
        if( rest.empty() || ( ( rest[0] == '.' || rest[0] == '_' || rest[0] == '-' ) && prose ) )
        {
            return true;   // a prose file: `changelog_parser.go` and `changelog.d` (a D source) are code
        }
    }
    return false;
}

// A path that IS a changelog or sits in a changelog fragment directory: its base name is a changelog file, or one of its directory
// segments is a changelog directory. By name, never by substring (`src/changelog_parser.go`, `docs/newsletter.md` are not).
inline bool isChangelogPath( std::string_view rel ) noexcept
{
    std::size_t at = 0;
    while( true )
    {
        const std::size_t      slash = rel.find( '/', at );
        const std::string_view seg   = rel.substr( at, slash == std::string_view::npos ? std::string_view::npos : slash - at );
        if( slash == std::string_view::npos )
        {
            return !seg.empty() && changelogName( seg, false );
        }
        if( changelogName( seg, true ) )
        {
            return true;
        }
        at = slash + 1;
    }
}

// ── 2. directories ────────────────────────────────────────────────────────────────────────────────────────────────────────────────

// Every directory from the one holding the file `rel` names up to the root, nearest first, each with its on-disk twin (`disk` = the
// file's own directory on disk): `visit( dir, disk )` returns false to stop.
template<class Visit>
inline void walkDirsUp( std::string_view rel, std::filesystem::path disk, Visit&& visit )
{
    const std::size_t cut = rel.rfind( '/' );
    std::string_view  dir = rel.substr( 0, cut == std::string_view::npos ? 0 : cut );
    while( visit( dir, std::as_const( disk ) ) && !dir.empty() )
    {
        const std::size_t up = dir.rfind( '/' );
        dir  = up == std::string_view::npos ? std::string_view() : dir.substr( 0, up );
        disk = disk.parent_path();
    }
}

inline bool isVendoredDir( std::string_view dir ) noexcept
{
    for( const std::string_view seg : { std::string_view( "vendor" ), std::string_view( "third_party" ), std::string_view( "node_modules" ),
                                        std::string_view( "bower_components" ) } )
    {
        if( dir == seg || dir.starts_with( std::string( seg ) + "/" ) || dir.find( "/" + std::string( seg ) + "/" ) != std::string_view::npos
            || dir.ends_with( "/" + std::string( seg ) ) )
        {
            return true;
        }
    }
    return false;
}

struct Manifest
{
    std::string rel;    // root-relative path
    std::string dir;    // its root-relative directory ("" = the root)
    std::string text;
    std::string code;   // `text` with every comment byte blanked to a space (line breaks kept): the view names are matched in
    bool        gen = false;
    bool        dirTokens = true;   // false for a kRoleByFile kind (make / CMake / meson / Bazel BUILD): they list sources by FILE
                                    // path; a directory there is a command's argument or a dep label
};

// The manifests of one directory whose kind has `role`: the fixed names in kManifestKinds order, then the fragments in name order
// (at most kFragmentsPerDir; `filesCapped` set when more were there). ONE directory listing, exact (case-sensitive) names of REGULAR
// files only: on a case-insensitive file system `BUILD` would otherwise open the `build/` directory (readRegularFile refuses it, but
// warns on stderr), and `Makefile` a `makefile`. A Makefile beside a Makefile.am is automake's output: the source is the one read.
inline void readDirManifests( std::string_view dir, const std::filesystem::path& disk, std::vector<Manifest>& out, bool& filesCapped,
                              std::uint8_t role = kRoleListedIn )
{
    std::vector<std::string> fixedNames;
    std::vector<std::string> fragments;
    std::error_code          ec;
    for( std::filesystem::directory_iterator it( disk, ec ), end; !ec && it != end; it.increment( ec ) )
    {
        std::error_code   sec;
        const std::string name = it->path().filename().string();
        if( !std::filesystem::is_regular_file( it->symlink_status( sec ) ) || sec )
        {
            continue;   // a directory, FIFO, device or symlink is not a manifest
        }
        if( it->file_size( sec ) > kManifestBytes || sec )
        {
            continue;   // above the crawl size ceiling (or unsized): a generated multi-MB list is not read whole on every call
        }
        const ManifestKind* kind = manifestKindOf( name );
        if( kind == nullptr || ( kind->roles & role ) == 0 )
        {
            continue;
        }
        ( std::ranges::any_of( kManifestKinds, [ & ]( const ManifestKind& k ) { return k.name == name; } ) ? fixedNames : fragments ).push_back( name );
    }
    const auto add = [ & ]( const std::string& name )
    {
        const std::optional<std::string> text = docparse::detail::readRegularFile( name, ( disk / name ).string() );
        if( text && !text->empty() )
        {
            const ManifestKind& kind = *manifestKindOf( name );
            Manifest m{ dir.empty() ? name : std::string( dir ) + "/" + name, std::string( dir ), *text, blankComments( *text, kind.style ),
                        saysGenerated( *text ), ( kind.roles & kRoleByFile ) == 0 };
            out.push_back( std::move( m ) );
        }
    };
    const bool haveAm = std::ranges::find( fixedNames, std::string( "Makefile.am" ) ) != fixedNames.end();
    for( const ManifestKind& k : kManifestKinds )   // table order, so the output never depends on directory order
    {
        const bool present = std::ranges::find( fixedNames, std::string( k.name ) ) != fixedNames.end();
        if( present && !( k.name == "Makefile" && haveAm ) )
        {
            add( std::string( k.name ) );
        }
    }
    std::ranges::sort( fragments );
    filesCapped = filesCapped || fragments.size() > kFragmentsPerDir;   // the files past the cap are never read: disclosed by the caller
    for( std::size_t i = 0; i < fragments.size() && i < kFragmentsPerDir; ++i )
    {
        add( fragments[i] );
    }
}

// The manifests (of `role`) of every file's directory and ancestors, nearest first, each directory once (vendored directories never read).
inline std::vector<Manifest> manifestsAbove( const IngestResult& ing, const std::vector<std::uint32_t>& files, bool& filesCapped,
                                             std::uint8_t role = kRoleListedIn )
{
    std::vector<std::string> seenDirs;
    std::vector<Manifest>    manifests;
    for( const std::uint32_t f : files )
    {
        walkDirsUp( rootRelPath( ing, f ), std::filesystem::path( diskPath( ing, f ) ).parent_path(),
                    [ & ]( std::string_view dir, const std::filesystem::path& disk )
                    {
                        if( std::ranges::find( seenDirs, dir ) == seenDirs.end() )
                        {
                            seenDirs.emplace_back( dir );
                            if( !isVendoredDir( dir ) )
                            {
                                readDirManifests( dir, disk, manifests, filesCapped, role );
                            }
                        }
                        return true;
                    } );
    }
    return manifests;
}

// Does a package root (kRolePackage, LISTED-IN's read set) of its own sit in a directory of `rel` strictly below the directory `mdir`?
// Then `rel` belongs to that NESTED package: an outer package's directory tails (build outputs, export keys) do not name it.
inline bool inNestedPackage( const IngestResult& ing, std::uint32_t fileId, std::string_view rel, std::string_view mdir )
{
    bool nested = false;
    walkDirsUp( rel, std::filesystem::path( diskPath( ing, fileId ) ).parent_path(),
                [ & ]( std::string_view dir, const std::filesystem::path& disk )
                {
                    if( dir.size() <= mdir.size() )
                    {
                        return false;
                    }
                    for( const ManifestKind& k : kManifestKinds )
                    {
                        std::error_code ec;
                        if( ( k.roles & kRolePackage ) != 0 && ( k.roles & kRoleListedIn ) != 0 && std::filesystem::is_regular_file( disk / k.name, ec ) && !ec )
                        {
                            nested = true;
                        }
                    }
                    return !nested;
                } );
    return nested;
}

// ── 3. names ──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────

inline bool isNameChar( char c ) noexcept
{
    return taskroute::wordByte( c ) || c == '-';   // a path segment's name bytes: a word byte or '-' (cmd-new-session)
}

// `tok` occurs in `line` bounded on both sides: the byte before is not a name character, '.' or '!' (an exclusion), the byte after is not a
// name character ("abi.h" never matches "abi.hpp"). A FILE-path token also refuses a '/' before it unless that '/' ends `./`, `)/`, `}/`
// or `//` or opens the line (`$(srcdir)/x.c`, `${dir}/x.c`, `//x.c`): `legacy/x.c` and `../x.c` name ANOTHER file of the same name,
// not the one the token resolves to from the manifest's own directory. A DIRECTORY token (`stem` non-empty) names that directory itself, not a deeper one:
// when a '/' follows, the next segment must be the shown file's stem (`middleware/logger/index.js` for index.ts, the build output of
// that file) — `pkg/sql/appstatspb:proto` is another package, not pkg/sql (fire table cockroach-07).
inline bool slashBeforePathOk( std::string_view line, std::size_t slash ) noexcept
{
    if( slash == 0 )
    {
        return true;
    }
    const char before = line[slash - 1];
    if( before == ')' || before == '}' || before == '/' )
    {
        return true;
    }
    return before == '.' && ( slash == 1 || ( !isNameChar( line[slash - 2] ) && line[slash - 2] != '.' ) );   // `./`, not `../` or `a./`
}

// A Bazel label `//pkg:x.cc` (`@repo//pkg:x.cc`, `pkg:x.cc`) names a file of package `pkg`: a ':' right after a name byte, or after a
// '/' that is not the `//` opening a root label (`//:x.cc`), is another package's label, not this manifest's own file.
inline bool colonNamesOtherPackage( std::string_view line, std::size_t colon ) noexcept
{
    if( colon == 0 )
    {
        return false;
    }
    const char before = line[colon - 1];
    if( isNameChar( before ) )
    {
        return true;
    }
    if( before != '/' )
    {
        return false;
    }
    // `//:x.cc` is the root package's own label unless the `//` follows a repository name (`@repo//:x.cc`) or a path (`a//:x`)
    const bool rootLabel = colon >= 2 && line[colon - 2] == '/' && ( colon == 2 || ( !isNameChar( line[colon - 3] ) && line[colon - 3] != '/' ) );
    return !rootLabel;
}

// The token at `at` sits inside a negated path: the bytes back to the start of its path word (name bytes, '/' and '.') are preceded by
// '!' — `"!./src/x"`, `"!dist/x"` in package.json `files` EXCLUDE what they name.
inline bool negatedPath( std::string_view line, std::size_t at ) noexcept
{
    while( at > 0 && ( isNameChar( line[at - 1] ) || line[at - 1] == '/' || line[at - 1] == '.' ) )
    {
        --at;
    }
    return at > 0 && line[at - 1] == '!';
}

// A ROOT anchor right before the token at `at`: `$(top_srcdir)/` / `${CMAKE_SOURCE_DIR}/` (and their abs_ / build-dir / PROJECT_ twins),
// the `//` opening a Bazel root path or the `//:` of a root label. From a SUBDIRECTORY manifest such a spelling names the ROOT file, never
// the manifest's own sub/x.c (`$(srcdir)/`, `${CMAKE_CURRENT_SOURCE_DIR}/` and `./` stay the manifest's own directory).
inline bool rootAnchoredAt( std::string_view line, std::size_t at ) noexcept
{
    // line[s], line[s+1] == "//" opening a root path: at the line start or after a byte that is neither a name byte nor '/'
    const auto rootSlashes = [ & ]( std::size_t s ) { return s == 0 || ( !isNameChar( line[s - 1] ) && line[s - 1] != '/' ); };
    if( at >= 3 && line[at - 1] == ':' )
    {
        return line[at - 2] == '/' && line[at - 3] == '/' && rootSlashes( at - 3 );
    }
    if( at < 2 || line[at - 1] != '/' )
    {
        return false;
    }
    const char before = line[at - 2];
    if( before == '/' )
    {
        return rootSlashes( at - 2 );
    }
    if( before != ')' && before != '}' )
    {
        return false;
    }
    const std::size_t open = line.rfind( before == ')' ? '(' : '{', at - 2 );
    if( open == std::string_view::npos || open == 0 || line[open - 1] != '$' )
    {
        return false;
    }
    static constexpr std::array<std::string_view, 8> kRootVars{ "top_srcdir",       "abs_top_srcdir",     "top_builddir",     "abs_top_builddir",
                                                                "CMAKE_SOURCE_DIR", "PROJECT_SOURCE_DIR", "CMAKE_BINARY_DIR", "PROJECT_BINARY_DIR" };
    return std::ranges::find( kRootVars, line.substr( open + 1, at - 2 - open - 1 ) ) != kRootVars.end();
}

inline bool boundedFind( std::string_view line, std::string_view tok, std::string_view stem = {}, bool pathToken = false,
                         bool refuseRootAnchor = false ) noexcept
{
    if( tok.empty() )
    {
        return false;
    }
    for( std::size_t at = line.find( tok ); at != std::string_view::npos; at = line.find( tok, at + 1 ) )
    {
        const char        prev   = at == 0 ? ' ' : line[at - 1];
        const bool        leftOk = at == 0 || ( pathToken && prev == '/' ? slashBeforePathOk( line, at - 1 )
                                                : prev == ':'                ? !colonNamesOtherPackage( line, at - 1 )
                                                                             : !isNameChar( prev ) && prev != '.' && prev != '!' );
        const std::size_t end    = at + tok.size();
        if( negatedPath( line, at ) || ( refuseRootAnchor && rootAnchoredAt( line, at ) ) )
        {
            continue;
        }
        bool              rightOk = end == line.size() || !isNameChar( line[end] );
        if( rightOk && !stem.empty() && end < line.size() && line[end] == '/' )
        {
            const std::string_view next = line.substr( end + 1 );
            rightOk = next.starts_with( stem ) && ( next.size() == stem.size() || !isNameChar( next[stem.size()] ) );
        }
        if( leftOk && rightOk )
        {
            return true;
        }
    }
    return false;
}

inline std::size_t segmentCount( std::string_view p ) noexcept
{
    return p.empty() ? 0u : std::size_t( std::ranges::count( p, '/' ) ) + 1u;
}

// The path tokens that name `fileRel` from a manifest in `mdir`, most specific first, each tagged path (the file) or dir.
struct Token
{
    std::string text;
    bool        isDir      = false;
    bool        belowSubdir = false;   // the file's path below a SUBDIRECTORY manifest: a root-anchored spelling of it is the root file
};

inline std::vector<Token> tokensFor( std::string_view fileRel, std::string_view mdir, bool dirTokens )
{
    std::vector<Token> t;
    const std::string_view below = mdir.empty() ? fileRel
                                 : ( fileRel.starts_with( mdir ) && fileRel.size() > mdir.size() && fileRel[mdir.size()] == '/' )
                                       ? fileRel.substr( mdir.size() + 1 ) : std::string_view();
    if( !below.empty() )
    {
        t.push_back( { std::string( below ), false, !mdir.empty() } );
        if( !mdir.empty() )
        {
            t.push_back( { std::string( fileRel ), false } );   // a root-relative spelling of a file INSIDE the manifest's directory
        }
    }
    // A file OUTSIDE the manifest's directory gets no token: a bare `x.c` in sub/Makefile.am is sub/x.c, never the root x.c or another
    // same-named file (the full path would match the root file's spelling as if it were relative to the manifest).
    const std::size_t slash = fileRel.rfind( '/' );
    // A manifest in the file's own directory names it by its file name only: a directory tail there is the package's own label
    // (a Bazel BUILD's `//pkg:dep` deps), not a listing of the file.
    const bool sameDir = slash == std::string_view::npos ? mdir.empty() : fileRel.substr( 0, slash ) == mdir;
    // ... and a manifest names a DIRECTORY only inside its own: package a's package.json does not list package b's src/middleware/cors
    // (a file outside the manifest's directory is matched by its full path, never by a directory tail).
    const bool inside = mdir.empty() || !below.empty();
    if( slash != std::string_view::npos && !sameDir && dirTokens && inside )
    {
        std::string_view dir = fileRel.substr( 0, slash );
        // directory tails of two or more segments, longest first
        while( segmentCount( dir ) >= 2 )
        {
            t.push_back( { std::string( dir ), true } );
            dir = dir.substr( dir.find( '/' ) + 1 );
        }
    }
    return t;
}

// The 1-based line of `man`'s comment-blanked code that first names `fileRel` by a file-path token (tokensFor, no directory tails), or
// by its stem when the stem has at least `minStem` bytes (a CMake test list names `test_foo`, not `test_foo.cpp`; 0 = never by stem).
// 0 when no line does. A commented-out line never names.
inline std::uint32_t lineNaming( const Manifest& man, std::string_view fileRel, std::size_t minStem )
{
    const std::vector<Token> toks = tokensFor( fileRel, man.dir, false );
    const std::string_view   base = namesplit::afterLast( fileRel, "/" );
    const std::string_view   stem = base.substr( 0, std::min( base.rfind( '.' ), base.size() ) );
    std::uint32_t            found = 0;
    darkflags::forEachLine( man.code, [ & ]( std::string_view l, std::uint32_t n )
                            {
                                const bool named = std::ranges::any_of( toks, [ & ]( const Token& t ) { return boundedFind( l, t.text ); } )
                                                || ( minStem > 0 && stem.size() >= minStem && boundedFind( l, stem ) );
                                found = found == 0 && named ? n : found;
                            } );
    return found;
}

// A manifest at a path, with the line that names the file (0 = it does not name it; the nearest-unit fallback).
struct ManifestRef
{
    std::string   rel;
    std::uint32_t line = 0;
};

inline constexpr std::size_t kMinStemNaming = 5;   // a stem shorter than this ("util", "io") names too many things to count

// The nearest manifest (of `role`) at or above `fileId`'s directory that NAMES the file (lineNaming), nearest first, table order inside a
// directory. Package manifests (no kRoleByFile) have no source list and never name it here. Empty rel when none does.
inline ManifestRef nearestNaming( const IngestResult& ing, std::uint32_t fileId, std::uint8_t role = kRoleUnit )
{
    bool                   capped = false;
    const std::string_view rel    = rootRelPath( ing, fileId );
    for( const Manifest& m : manifestsAbove( ing, std::vector<std::uint32_t>{ fileId }, capped, role ) )
    {
        if( m.dirTokens || m.rel == rel )
        {
            continue;
        }
        if( const std::uint32_t line = lineNaming( m, rel, kMinStemNaming ); line > 0 )
        {
            return { m.rel, line };
        }
    }
    return {};
}

// The nearest unit build file at or above `fileId`'s directory whether or not it names the file (the unit a new sibling is built by:
// tests/CMakeLists.txt for a new test, crates/x/Cargo.toml for a new module), lowest unitRank inside the nearest directory holding one.
// `skipRoot`: the root's manifests are quoted elsewhere on the answer. Empty rel when none.
inline ManifestRef nearestUnit( const IngestResult& ing, std::uint32_t fileId, bool skipRoot )
{
    ManifestRef out;
    walkDirsUp( rootRelPath( ing, fileId ), std::filesystem::path( diskPath( ing, fileId ) ).parent_path(),
                [ & ]( std::string_view dir, const std::filesystem::path& disk )
                {
                    if( ( skipRoot && dir.empty() ) || isVendoredDir( dir ) )
                    {
                        return false;
                    }
                    std::vector<Manifest> here;
                    bool                  capped = false;
                    readDirManifests( dir, disk, here, capped, kRoleUnit );
                    const auto rank = [ & ]( const Manifest& m ) { return manifestKindOf( namesplit::afterLast( m.rel, "/" ) )->unitRank; };
                    const auto best = std::ranges::min_element( here, {}, rank );
                    if( best != here.end() )
                    {
                        out = { best->rel, lineNaming( *best, rootRelPath( ing, fileId ), kMinStemNaming ) };
                    }
                    return best == here.end();
                } );
    return out;
}

// ── 4. changelog ──────────────────────────────────────────────────────────────────────────────────────────────────────────────────

// The changelog entry of one directory, "" for none: a fragment directory first (a printed trailing '/'), else a changelog file, name
// order inside each. A repo with changelog.d/ (or changelog/unreleased/) adds a fragment there and generates CHANGELOG.md from them.
inline std::string changelogIn( const std::filesystem::path& disk )
{
    std::vector<std::string> files, dirs;
    std::error_code          ec;
    for( std::filesystem::directory_iterator it( disk, ec ), end; !ec && it != end; it.increment( ec ) )
    {
        std::error_code   sec;
        const std::string name = it->path().filename().string();
        const auto        st   = it->symlink_status( sec );
        if( sec )
        {
            continue;
        }
        if( std::filesystem::is_regular_file( st ) && changelogName( name, false ) )
        {
            files.push_back( name );
        }
        else if( std::filesystem::is_directory( st ) && changelogName( name, true ) )
        {
            std::error_code ue;
            const bool unreleased = std::filesystem::is_directory( disk / name / "unreleased", ue ) && !ue;   // changelog/unreleased/
            dirs.push_back( name + ( unreleased ? "/unreleased/" : "/" ) );
        }
    }
    std::ranges::sort( files );
    std::ranges::sort( dirs );
    return !dirs.empty() ? dirs.front() : !files.empty() ? files.front() : std::string();
}

// The nearest changelog, root-relative: the first directory from `rel`'s own up to the root that holds one (changelogIn). A package of a
// monorepo keeps its own (packages/zod/CHANGELOG.md before the root's). "" for none.
inline std::string changelogNear( std::string_view rel, const std::filesystem::path& diskDir )
{
    std::string found;
    walkDirsUp( rel, diskDir,
                [ & ]( std::string_view dir, const std::filesystem::path& disk )
                {
                    const std::string entry = changelogIn( disk );
                    found = entry.empty() || dir.empty() ? entry : std::string( dir ) + "/" + entry;
                    return entry.empty();
                } );
    return found;
}

// ── 5. tests ──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────

// One test file's cross-file call edges: into the subject file, into the subject's siblings, into any other file, and whether one
// lands on an exemplar symbol (the act symbols, or the exemplar the task names).
struct TestHits
{
    std::uint32_t file = 0;
    int           subject = 0, siblings = 0, all = 0;
    bool          exemplar = false;
};

// Per test file (`isTest( fileId )`, never a sibling): its resolved cross-file call edges, counted against `subject` (a file id) and
// `sibling[fileId]` (the subject's own file counts as a sibling: a test of the unit's kind). `exemplar( nodeId )`: the target is an
// exemplar symbol. Rows in file order; a test file with no cross-file edge is absent.
template<class IsTest, class IsExemplar>
inline std::vector<TestHits> subjectTestHits( const IngestResult& ing, const Graph& g, std::uint32_t subject, const std::vector<std::uint8_t>& sibling,
                                              IsTest&& isTest, IsExemplar&& exemplar )
{
    const std::size_t          n = ing.symbols.size();
    std::vector<std::int32_t>  slot( ing.files.size(), -1 );
    std::vector<TestHits>      out;
    if( g.outOff.size() < n + 1 )
    {
        return out;
    }
    for( std::uint32_t s = 0; s < n; ++s )
    {
        const std::uint32_t from = ing.symbols[s].fileId;
        if( from >= ing.files.size() || ( from < sibling.size() && sibling[from] ) || !isTest( from ) )
        {
            continue;
        }
        for( std::uint32_t e = g.outOff[s]; e < g.outOff[s + 1]; ++e )
        {
            const NodeId t = g.outTargets[e];
            if( t >= n || ing.symbols[t].fileId >= ing.files.size() || ing.symbols[t].fileId == from )
            {
                continue;
            }
            if( slot[from] < 0 )
            {
                slot[from] = std::int32_t( out.size() );
                out.push_back( TestHits{ from } );
            }
            TestHits&           h  = out[std::size_t( slot[from] )];
            const std::uint32_t to = ing.symbols[t].fileId;
            ++h.all;
            h.siblings += to < sibling.size() && sibling[to] ? 1 : 0;
            h.subject += to == subject ? 1 : 0;
            h.exemplar = h.exemplar || ( to == subject && exemplar( t ) );
        }
    }
    std::ranges::sort( out, {}, &TestHits::file );
    return out;
}

// The tests worth naming, best first: those reaching a sibling (the subject is one), inside `inScope( fileId )`; an exemplar caller first, then the share of
// the test's cross-file calls that land on the subject (a test ABOUT the subject — test_switch.py — before one that calls every
// widget once), then the subject count, then path.
template<class InScope>
inline std::vector<TestHits> rankSubjectTests( const IngestResult& ing, std::vector<TestHits> hits, InScope&& inScope )
{
    std::erase_if( hits, [ & ]( const TestHits& h ) { return h.siblings == 0 || !inScope( h.file ); } );
    std::ranges::sort( hits, [ & ]( const TestHits& a, const TestHits& b )
    {
        if( a.exemplar != b.exemplar )
        {
            return a.exemplar;
        }
        const long sa = long( a.subject ) * b.all, sb = long( b.subject ) * a.all;
        if( sa != sb )
        {
            return sa > sb;
        }
        return a.subject != b.subject ? a.subject > b.subject : sortutil::svLess( rootRelPath( ing, a.file ), rootRelPath( ing, b.file ) );
    } );
    return hits;
}

}   // namespace rw::whereelse
