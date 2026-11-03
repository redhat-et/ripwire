#pragma once
// listedin.h — LISTED-IN: the build / package / registry manifest lines that list a SHOWN file, on a --for answer whose task is a
// creation task (lane manifest-noncode; CONTRIBUTING family 10, slice 10c, beside epmanifest.h's Python entry points).
//
// WHY. "Add a new tmux command / a new hono middleware / a new Envoy extension" is answered by the code pattern AND by the
// non-code files every new instance must also be listed in: automake's `dist_tmux_SOURCES` list, package.json "exports" +
// "typesVersions" and jsr.json "exports", Bazel's extensions_build_config.bzl. No code edge reaches them (Makefile.am and .bzl
// are not crawled; package.json keys are indexed as data rows that never rank for the task), so the answer stopped at
// the source files. Measured before this code (reports/manifest-noncode.md Stage 0): mf1-tmux-01, mf1-hono-03 and ld-envoy-07
// printed no manifest line although the shown exemplar files ARE listed in one.
//
// WHAT. <listed p= of= by= also=[ also_total=][ lines_total= capped="1"]><ln l=>LINE</ln>…</listed>, after the file tail and
// beside <ep>: one element per manifest (at the root or an ancestor directory of a shown file) whose lines name TWO or more shown
// files — a list of the exemplar's siblings; a manifest naming one shown file (package.json "main") is not one (fire table koa/fastify). of= the FIRST shown file (rank order) the manifest names, and every line naming it, byte-exact (XML-escaped), each
// preceded once by its nearest less-indented line above (the stanza it sits in: the `dist_tmux_SOURCES = \` assignment, the
// `"./timing": {` key, the `EXTENSIONS = {` dict). by="path" the line names of='s path (relative to the manifest's directory, or
// root-relative); by="dir" it names of='s directory by a tail of two or more path segments (package.json lists a build output
// under that directory, a .bzl a Bazel label) — the file's directory, not the file. Make, CMake, meson and Bazel BUILD files are
// matched by file path only: a directory there is a command argument (fzf's `go test ./src/algo`) or a dep label, not a listing
// (fire table fzf-02, cockroach-07); a .bzl registry (Envoy's extensions_build_config.bzl) keeps directory labels. also= the other shown files the same manifest
// names (by either rule), at most kListedAlsoNames, also_total= all of them. A path token matches whole segments only (bounded by a
// non-name character on both sides), so `middleware/log` never matches `middleware/logger`. gen="1": the manifest says it was
// generated (an automake Makefile.in, a configure-written Makefile) — the file to edit is its source.
//
// GATE (present-only): the task has a creation word (new, add, adding, register, registration, plugin, plugins, extension,
// extensions) as a whole word (not inside an identifier: `Plan::AddTarget`, `new_local`, `createX` do not fire); the DEFAULT regime and the XML dialect only, as the caller hop and
// <ep>. RIPWIRE_NO_LISTED_IN (any value) turns it off — the A/B handle.
// SIBLINGS: a sibling counts only when one of its lines sits in the SAME top-level stanza as one of of='s (blanked comments and
// exclusion lists never name a file; a name resolves from the manifest's own directory, so `legacy/x.c` is not x.c and package a's
// package.json does not list package b's directory).
// FLOORS: a manifest above the crawl size ceiling (kDefaultMaxFileBytes) is not read; CODEOWNERS (ownership, not a build listing: it fired on a codec question, fire table cpython-08), a manifest that lists a file by a glob or a variable (`$(wildcard src/*.c)`, `glob(["*.cc"])`), a list keyed by a
// registered NAME string (a man page's command list, a docs index — mf1-lit's literal anchors), a manifest outside the shown
// files' ancestor directories, a multi-root run. Files under vendor/, third_party/, node_modules/, bower_components/ are vendored: neither a shown file
// there nor a manifest there is read.

#include "darkflags.h"    // forEachLine — the one line splitter over raw file text (CR stripped)
#include "ingest.h"       // kDefaultMaxFileBytes — the crawl size ceiling a manifest read also honours
#include "docparse.h"     // readRegularFile — a fixed-name file in the tree, refused when it is not a regular file
#include "lintrules.h"    // lintdetail::indentOf — the leading-blank count of a raw line
#include "taskroute.h"    // taskroute::wordByte — the word byte (alnum or _)
#include "model.h"        // IngestResult, rootRelPath, diskPath
#include "serialize.h"    // escapeXml, truncateUtf8WithEllipsis

#include <algorithm>
#include <array>
#include <cctype>
#include <cstddef>
#include <cstdint>
#include <cstdlib>
#include <filesystem>
#include <format>
#include <optional>
#include <span>
#include <string>
#include <string_view>
#include <system_error>
#include <vector>

namespace rw
{

// Runaway guards, not size targets (knob census ADDENDUM): every manifest, line or name past them is dropped WITH a disclosure
// (manifests_capped="1" manifests_total= on the first element, capped="1" lines_total= on the element, also_total=, files_capped="1" on the
// first element for the two caps on what is READ: *.bzl files past kListedBzlPerDir, shown files past kListedShownFiles; when the cut leaves
// no manifest that lists a shown file there is no element to carry it, and no clause either: an absent <listed> claims nothing).
inline constexpr std::size_t kListedManifests   = 4;     // manifests per answer
inline constexpr std::size_t kListedLines       = 8;     // printed lines per manifest (stanza openers included)
inline constexpr std::size_t kListedAlsoNames   = 4;     // also= names per manifest
inline constexpr std::size_t kListedShownFiles  = 16;    // distinct shown files whose ancestors are read
inline constexpr std::size_t kListedLineBytes   = 240;   // one printed line (UTF-8-safe cut + ellipsis)
inline constexpr std::size_t kListedBzlPerDir   = 8;     // *.bzl files read per directory
inline constexpr std::uintmax_t kListedManifestBytes = kDefaultMaxFileBytes;   // a manifest above the crawl ceiling is not read (a floor)

inline bool forListedInOn()
{
    return std::getenv( "RIPWIRE_NO_LISTED_IN" ) == nullptr;
}

struct ListedRender
{
    std::string xml;   // the <listed> elements; empty when no manifest lists a shown file (or the task is not a creation task)
};

namespace listeddetail
{

// A creation word as a whole word of the task, case-folded; words split on every character that is not alphanumeric or '_', so a
// creation word inside an identifier (`Plan::AddTarget`, `Workspace::new_local`, `createSingletons`) is not one: that task names a
// symbol, it does not ask to add one. "hono/<new-middleware>" → new.
inline bool isCreationTask( std::string_view task )
{
    // Not "create": "how does Koa create the per-request ctx" asks how code runs, not what to add (fire table koa-13).
    static constexpr std::string_view kWords[] = { "new", "add", "adding", "register", "registration", "plugin", "plugins", "extension",
                                                    "extensions" };
    std::string word;
    const auto  flush = [ & ]()
    {
        const bool hit = std::ranges::find( kWords, std::string_view( word ) ) != std::end( kWords );
        word.clear();
        return hit;
    };
    char prev = ' ';   // the previous ORIGINAL character (word holds the folded ones, so "NEW" is not a camel boundary)
    for( const char ch : task )
    {
        const unsigned char c = static_cast<unsigned char>( ch );
        const bool          camel = std::isupper( c ) && !word.empty() && std::islower( static_cast<unsigned char>( prev ) );
        prev = ch;
        if( !std::isalnum( c ) && ch != '_' )
        {
            if( flush() )
            {
                return true;
            }
            continue;
        }
        if( camel )
        {
            word += '\x01';   // a lower→upper camel boundary inside one word: the word is an identifier, never a creation word
        }
        word += char( std::tolower( c ) );
    }
    return flush();
}

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

// How a manifest comments: make (`#`, a trailing backslash continues the comment), CMake (`#`, `#[[ ]]`, `#[=[ ]=]`), the other hash
// formats (meson, Bazel, TOML: `#` outside "…" and '…'), and JSON with comments (`//`, `/* */` outside "…").
enum class CommentStyle : unsigned char { Make, CMake, Hash, JsonC };

struct Manifest
{
    std::string rel;    // root-relative path
    std::string dir;    // its root-relative directory ("" = the root)
    std::string text;
    std::string code;   // `text` with every comment byte blanked to a space (line breaks kept): the view names are matched in
    bool        gen = false;
    bool        dirTokens = true;   // false for make / CMake / meson / Bazel BUILD: they list sources by FILE path; a directory there is a
                                    // command's argument or a dep label
};

struct ManifestLine
{
    std::uint32_t    line = 0;
    std::string_view text;           // byte-exact, what is printed
    std::string_view code;           // the same bytes with comments blanked, what is matched
    std::uint32_t    stanza = 0;     // index of the line that opens this line's top-level stanza
};

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

// The fixed-name manifests of one directory (and its *.bzl files, name order, at most kListedBzlPerDir).
inline void readDirManifests( std::string_view dir, const std::filesystem::path& disk, std::vector<Manifest>& out, bool& filesCapped )
{
    static constexpr std::string_view kNames[] = { "Makefile.am", "Makefile", "GNUmakefile", "CMakeLists.txt", "meson.build", "BUILD",
                                                   "BUILD.bazel", "package.json", "jsr.json", "deno.json", "Cargo.toml" };
    // ONE directory listing, exact (case-sensitive) names of REGULAR files only: on a case-insensitive file system `BUILD` would
    // otherwise open the `build/` directory (readRegularFile refuses it, but warns on stderr), and `Makefile` a `makefile`.
    std::vector<std::string> fixedNames;
    std::vector<std::string> bzl;
    std::error_code          ec;
    for( std::filesystem::directory_iterator it( disk, ec ), end; !ec && it != end; it.increment( ec ) )
    {
        std::error_code   sec;
        const std::string name = it->path().filename().string();
        if( !std::filesystem::is_regular_file( it->symlink_status( sec ) ) || sec )
        {
            continue;   // a directory, FIFO, device or symlink is not a manifest
        }
        if( it->file_size( sec ) > kListedManifestBytes || sec )
        {
            continue;   // above the crawl size ceiling (or unsized): a generated multi-MB list is not read whole on every --for
        }
        if( std::ranges::find( kNames, std::string_view( name ) ) != std::end( kNames ) )
        {
            fixedNames.push_back( name );
        }
        else if( name.ends_with( ".bzl" ) )
        {
            bzl.push_back( name );
        }
    }
    const auto add = [ & ]( const std::string& name )
    {
        const std::optional<std::string> text = docparse::detail::readRegularFile( name, ( disk / name ).string() );
        if( text && !text->empty() )
        {
            const bool byFile = name.starts_with( "Makefile" ) || name == "GNUmakefile" || name == "CMakeLists.txt" || name == "meson.build"
                             || name.starts_with( "BUILD" );   // a Bazel BUILD names other packages only as deps (fire table cockroach-07)
            const CommentStyle style = name.starts_with( "Makefile" ) || name == "GNUmakefile" ? CommentStyle::Make
                                     : name == "CMakeLists.txt"                                ? CommentStyle::CMake
                                     : name.ends_with( ".json" )                               ? CommentStyle::JsonC : CommentStyle::Hash;
            Manifest   m{ dir.empty() ? name : std::string( dir ) + "/" + name, std::string( dir ), *text, blankComments( *text, style ),
                          saysGenerated( *text ), !byFile };
            out.push_back( std::move( m ) );
        }
    };
    const bool haveAm = std::ranges::find( fixedNames, std::string( "Makefile.am" ) ) != fixedNames.end();
    for( const std::string_view name : kNames )   // table order, so the output never depends on directory order
    {
        const bool present = std::ranges::find( fixedNames, std::string( name ) ) != fixedNames.end();
        if( present && !( name == "Makefile" && haveAm ) )   // automake writes Makefile from Makefile.am: the source is the one to show
        {
            add( std::string( name ) );
        }
    }
    std::ranges::sort( bzl );
    filesCapped = filesCapped || bzl.size() > kListedBzlPerDir;   // the files past the cap are never read: files_capped on the answer
    for( std::size_t i = 0; i < bzl.size() && i < kListedBzlPerDir; ++i )
    {
        add( bzl[i] );
    }
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

// The lines of a manifest (text + comment-blanked code, same offsets), each with its top-level stanza: the nearest line above, or
// itself, that sits at indent 0 with every bracket closed and no backslash continuation pending (`dist_tmux_SOURCES = \`, an
// `add_library(`, a Bazel rule, the `{` of a package.json). Two names are siblings only inside one stanza.
inline std::vector<ManifestLine> splitLines( const Manifest& man )
{
    std::vector<ManifestLine> lines;
    const std::string_view    text = man.text;
    darkflags::forEachLine( text, [ & ]( std::string_view l, std::uint32_t n )
                            { lines.push_back( { n, l, std::string_view( man.code ).substr( std::size_t( l.data() - text.data() ), l.size() ), 0 } ); } );
    std::uint32_t stanza = 0;
    int           depth  = 0;
    bool          cont   = false;
    for( std::size_t li = 0; li < lines.size(); ++li )
    {
        const std::string_view c = lines[li].code;
        const std::size_t      ind = lintdetail::indentOf( c );
        if( ind >= c.size() )
        {
            cont = false;   // a blank (or comment-only) line ends a make continuation
        }
        else
        {
            stanza = ind == 0 && depth == 0 && !cont ? std::uint32_t( li ) : stanza;
            for( const char ch : c )
            {
                depth += ( ch == '(' || ch == '[' || ch == '{' ) ? 1 : ( ( ch == ')' || ch == ']' || ch == '}' ) && depth > 0 ) ? -1 : 0;
            }
            const std::string_view t = lintdetail::trim( c );   // trim also drops \r \v \f, which indentOf keeps: a line of only those is empty here
            cont = !t.empty() && t.back() == '\\';
        }
        lines[li].stanza = stanza;
    }
    return lines;
}

}   // namespace listeddetail

namespace listeddetail
{

// The manifests of every shown file's directory and ancestors, nearest first, each directory once (vendored directories never read).
inline std::vector<Manifest> manifestsAbove( const IngestResult& ing, const std::vector<std::uint32_t>& files, bool& filesCapped )
{
    std::vector<std::string> seenDirs;
    std::vector<Manifest>    manifests;
    for( const std::uint32_t f : files )
    {
        const std::string_view rel  = rootRelPath( ing, f );
        std::filesystem::path  disk = std::filesystem::path( diskPath( ing, f ) ).parent_path();
        const std::size_t      cut  = rel.rfind( '/' );
        std::string_view       dir  = rel.substr( 0, cut == std::string_view::npos ? 0 : cut );
        while( true )
        {
            if( std::ranges::find( seenDirs, dir ) == seenDirs.end() )
            {
                seenDirs.emplace_back( dir );
                if( !isVendoredDir( dir ) )
                {
                    readDirManifests( dir, disk, manifests, filesCapped );
                }
            }
            if( dir.empty() )
            {
                break;
            }
            const std::size_t up = dir.rfind( '/' );
            dir  = up == std::string_view::npos ? std::string_view() : dir.substr( 0, up );
            disk = disk.parent_path();
        }
    }
    return manifests;
}

struct Hit
{
    std::size_t               m = 0;
    std::size_t               firstFile = 0;   // index into files
    bool                      byDir = false;
    std::vector<std::size_t>  lineIx;          // matched lines of the first file (indices into lines)
    std::vector<std::string>  also;            // other shown files named
    std::vector<ManifestLine> lines;
};

// Does this (comment-blanked) line say it REMOVES names: Bazel `exclude =`, CMake `list(REMOVE_ITEM`? Case-folded, whole word.
inline bool saysExclusion( std::string_view code )
{
    std::string lower( code );
    std::ranges::transform( lower, lower.begin(), []( unsigned char ch ) { return char( std::tolower( ch ) ); } );
    return boundedFind( lower, "exclude" ) || boundedFind( lower, "remove_item" );
}

// The line (or a less-indented line it sits under, up to the stanza's opener) is an exclusion list: its names are NOT listed.
inline bool underExclusion( const std::vector<ManifestLine>& lines, std::size_t li )
{
    if( saysExclusion( lines[li].code ) )
    {
        return true;
    }
    std::size_t ind = lintdetail::indentOf( lines[li].code );
    for( std::size_t up = li; ind > 0 && up-- > 0; )
    {
        const std::size_t upInd = lintdetail::indentOf( lines[up].code );
        if( upInd < lines[up].code.size() && upInd < ind )
        {
            if( saysExclusion( lines[up].code ) )
            {
                return true;
            }
            ind = upInd;
        }
    }
    return false;
}

// The lines of `lines` naming `rel` (from a manifest in `mdir`; comments and exclusion lists never name), and whether every one names only its directory.
inline std::vector<std::size_t> linesNaming( const std::vector<ManifestLine>& lines, std::string_view rel, std::string_view mdir, bool dirTokens,
                                             bool& dirOnly )
{
    const std::vector<Token> toks = tokensFor( rel, mdir, dirTokens );
    const std::string_view   base = rel.substr( rel.rfind( '/' ) == std::string_view::npos ? 0 : rel.rfind( '/' ) + 1 );
    const std::string_view   stem = base.substr( 0, std::min( base.find( '.' ), base.size() ) );   // index.ts → index
    std::vector<std::size_t> mine;
    dirOnly = true;
    for( std::size_t li = 0; li < lines.size(); ++li )
    {
        // the first token the line names, in specificity order (path before directory tails)
        const auto k = std::ranges::find_if( toks, [ & ]( const Token& t )
                                             { return boundedFind( lines[li].code, t.text, t.isDir ? stem : std::string_view(), !t.isDir, t.belowSubdir ); } );
        if( k != toks.end() && !underExclusion( lines, li ) )
        {
            mine.push_back( li );
            dirOnly = dirOnly && k->isDir;
        }
    }
    return mine;
}

// Does a package-family manifest (package.json, jsr.json, deno.json, Cargo.toml) of its own sit in a directory of `rel` strictly below the
// manifest's directory `mdir`? Then `rel` belongs to that NESTED package: the outer package's directory tails (build outputs, export
// keys) do not name it.
inline bool inNestedPackage( const IngestResult& ing, std::uint32_t fileId, std::string_view rel, std::string_view mdir )
{
    std::filesystem::path disk = std::filesystem::path( diskPath( ing, fileId ) ).parent_path();
    std::string_view      dir  = rel.substr( 0, rel.rfind( '/' ) == std::string_view::npos ? 0 : rel.rfind( '/' ) );
    while( dir.size() > mdir.size() )
    {
        for( const char* name : { "package.json", "jsr.json", "deno.json", "Cargo.toml" } )
        {
            std::error_code ec;
            if( std::filesystem::is_regular_file( disk / name, ec ) && !ec )
            {
                return true;
            }
        }
        const std::size_t cut = dir.rfind( '/' );
        dir  = cut == std::string_view::npos ? std::string_view() : dir.substr( 0, cut );
        disk = disk.parent_path();
    }
    return false;
}

// One manifest's hit: the first shown file it names (and those lines), and the other shown files that are its SIBLINGS: named in the
// same top-level stanza as one of its lines (a registry lists the exemplar's siblings together; `add_executable(ninja src/ninja.cc)` and
// a different `add_library(libninja …)` are not a list). found=false: no shown file is named.
inline bool manifestHit( const IngestResult& ing, const std::vector<std::uint32_t>& files, const Manifest& man, Hit& h )
{
    h.lines = splitLines( man );
    std::vector<std::uint32_t> stanzas;   // the stanzas of the first named file's lines
    bool                       found = false;
    for( std::size_t fi = 0; fi < files.size(); ++fi )
    {
        const std::string_view rel = rootRelPath( ing, files[fi] );
        bool                   dirOnly = true;
        std::vector<std::size_t> mine;   // never the manifest itself
        if( rel != man.rel )
        {
            mine = linesNaming( h.lines, rel, man.dir, man.dirTokens && !inNestedPackage( ing, files[fi], rel, man.dir ), dirOnly );
        }
        if( mine.empty() )
        {
            continue;
        }
        if( found )
        {
            const bool sibling = std::ranges::any_of( mine, [ & ]( std::size_t li ) { return std::ranges::find( stanzas, h.lines[li].stanza ) != stanzas.end(); } );
            if( sibling )
            {
                h.also.emplace_back( rel );
            }
            continue;
        }
        found       = true;
        h.firstFile = fi;
        h.byDir     = dirOnly;
        for( const std::size_t li : mine )
        {
            stanzas.push_back( h.lines[li].stanza );
        }
        h.lineIx = std::move( mine );
    }
    return found;
}

// The printed line indices: each matched line, preceded once by its stanza opener (the nearest less-indented, non-blank line above;
// none when that line is a lone bracket).
inline std::vector<std::size_t> printedLines( const Hit& h )
{
    std::vector<std::size_t> print;
    const auto addOnce = [ & ]( std::size_t li )
    {
        if( std::ranges::find( print, li ) == print.end() )
        {
            print.push_back( li );
        }
    };
    for( const std::size_t li : h.lineIx )
    {
        const std::size_t ind = lintdetail::indentOf( h.lines[li].text );
        for( std::size_t up = li; ind > 0 && up-- > 0; )
        {
            const std::string_view t     = h.lines[up].code;   // a comment is never a stanza's opener
            const std::size_t      upInd = lintdetail::indentOf( t );
            if( upInd < t.size() && upInd < ind )
            {
                if( lintdetail::trim( t ).size() > 1 )   // a bare `{` / `[` opens the whole file: it names no stanza
                {
                    addOnce( up );
                }
                break;
            }
        }
        addOnce( li );
    }
    std::ranges::sort( print );
    return print;
}

inline void appendListed( std::string& x, const IngestResult& ing, const std::vector<std::uint32_t>& files, const Manifest& man, const Hit& h,
                          std::string_view manifestsCap, std::vector<char>& esc )
{
    const std::vector<std::size_t> print = printedLines( h );
    x += std::format( "<listed p=\"{}\"", escapeXml( man.rel, esc ) );
    x += std::format( " of=\"{}\" by=\"{}\"", escapeXml( rootRelPath( ing, files[h.firstFile] ), esc ), h.byDir ? "dir" : "path" );
    x += man.gen ? " gen=\"1\"" : "";
    if( !h.also.empty() )
    {
        std::string also;
        for( std::size_t a = 0; a < h.also.size() && a < kListedAlsoNames; ++a )
        {
            also += ( a ? "," : "" ) + h.also[a];
        }
        x += std::format( " also=\"{}\"", escapeXml( also, esc ) );
        x += h.also.size() > kListedAlsoNames ? std::format( " also_total=\"{}\"", h.also.size() ) : std::string();
    }
    x += print.size() > kListedLines ? std::format( " capped=\"1\" lines_total=\"{}\"", print.size() ) : std::string();
    x += manifestsCap;
    x += ">";
    for( std::size_t pi = 0; pi < print.size() && pi < kListedLines; ++pi )
    {
        std::string text( h.lines[ print[pi] ].text );
        truncateUtf8WithEllipsis( text, kListedLineBytes );
        x += std::format( "<ln l=\"{}\">{}</ln>", h.lines[ print[pi] ].line, escapeXml( text, esc ) );
    }
    x += "</listed>";
}

}   // namespace listeddetail

// The <listed> elements for the shown rows (rank order). Empty unless the task is a creation task and a manifest names a shown file.
inline ListedRender renderForListedIn( const IngestResult& ing, std::span<const NodeId> shown, std::string_view task )
{
    using namespace listeddetail;
    ListedRender out;
    if( ing.crawlRoot.empty() || shown.empty() || !isCreationTask( task ) )
    {
        return out;
    }
    std::vector<std::uint32_t> files;   // distinct shown files, rank order
    bool                       filesCapped = false;   // a shown file or a *.bzl file was left unread (kListedShownFiles, kListedBzlPerDir)
    for( const NodeId id : shown )
    {
        if( id < ing.symbols.size() && std::ranges::find( files, ing.symbols[id].fileId ) == files.end()
            && !isVendoredDir( rootRelPath( ing, ing.symbols[id].fileId ) ) )   // a vendored copy's own manifest is its upstream's, not the repo's
        {
            if( files.size() < kListedShownFiles )
            {
                files.push_back( ing.symbols[id].fileId );
            }
            else
            {
                filesCapped = true;
            }
        }
    }
    const std::vector<Manifest> manifests = manifestsAbove( ing, files, filesCapped );
    std::vector<Hit>            hits;
    for( std::size_t mi = 0; mi < manifests.size(); ++mi )
    {
        Hit h;
        h.m = mi;
        if( manifestHit( ing, files, manifests[mi], h ) && !h.also.empty() )   // a registry: it lists the exemplar AND a shown sibling
        {
            hits.push_back( std::move( h ) );
        }
    }
    // A manifest naming more shown files first (a registry of the exemplar's siblings), then nearest-first discovery order.
    std::ranges::stable_sort( hits, []( const Hit& a, const Hit& b ) { return a.also.size() > b.also.size(); } );
    std::vector<char> esc;
    for( std::size_t hi = 0; hi < hits.size() && hi < kListedManifests; ++hi )
    {
        std::string cap = ( hi == 0 && hits.size() > kListedManifests )
                                  ? std::format( " manifests_capped=\"1\" manifests_total=\"{}\"", hits.size() ) : std::string();
        cap += hi == 0 && filesCapped ? " files_capped=\"1\"" : "";
        appendListed( out.xml, ing, files, manifests[ hits[hi].m ], hits[hi], cap, esc );
    }
    return out;
}

// The element's legend clauses, present-only beside it: the full and the compact dialect. No "--": they ride inside an XML comment.
inline constexpr std::string_view kForListedInLegend =
    "; listed p= of= by=: a build, package or registry manifest (Makefile.am, CMakeLists.txt, meson.build, BUILD, *.bzl, package.json, "
    "jsr.json, deno.json, Cargo.toml) at the root or above a shown file that lists of=, the first shown file it names, "
    "and at least one more shown file, on a creation task; ln l=: each line naming of= byte-exact, after the less-indented line it sits under; by=path the line names "
    "the file, by=dir only its directory (2+ path segments); also=: other shown files the manifest names, also_total= all; gen=1 the "
    "manifest says it is generated; capped=1 lines_total=, manifests_capped=1 manifests_total=: cut, the total; files_capped=1 shown files or *.bzl files past a cap were not read; "
    "not exhaustive: code tables, docs, globs, variable listings and manifests above no shown file are not searched (a floor)";
inline constexpr std::string_view kForCompactListedInLegend =
    "; listed p= of= by=path|dir: a manifest above a shown file listing of= and another shown file (a creation task); ln l=: its lines byte-exact with the "
    "line they sit under; also=/also_total= other shown files it lists; gen=1 generated; not exhaustive (code tables, docs, globs, other manifests are not searched); capped=1 lines_total=/manifests_capped=1/files_capped=1 if cut";

}   // namespace rw
