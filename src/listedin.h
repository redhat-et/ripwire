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
#include "whereelse.h"    // the where-else family: manifest table + reader, ancestor walk, bounded path names, vendored dirs
#include "lintrules.h"    // lintdetail::indentOf — the leading-blank count of a raw line
#include "model.h"        // IngestResult, rootRelPath, diskPath
#include "redact.h"       // redactInPlace — a printed <ln> is a manifest line (a script or config value can hold a token)
#include "serialize.h"    // escapeXml, truncateUtf8WithEllipsis

#include <algorithm>
#include <cctype>
#include <cstddef>
#include <cstdint>
#include <cstdlib>
#include <format>
#include <span>
#include <string>
#include <string_view>
#include <vector>

namespace rw
{

// Runaway guards, not size targets (knob census ADDENDUM): every manifest, line or name past them is dropped WITH a disclosure
// (manifests_capped="1" manifests_total= on the first element, capped="1" lines_total= on the element, also_total=, files_capped="1" on the
// first element for the two caps on what is READ: *.bzl files past whereelse::kFragmentsPerDir, shown files past kListedShownFiles; when the cut leaves
// no manifest that lists a shown file there is no element to carry it, and no clause either: an absent <listed> claims nothing).
inline constexpr std::size_t kListedManifests   = 4;     // manifests per answer
inline constexpr std::size_t kListedLines       = 8;     // printed lines per manifest (stanza openers included)
inline constexpr std::size_t kListedAlsoNames   = 4;     // also= names per manifest
inline constexpr std::size_t kListedShownFiles  = 16;    // distinct shown files whose ancestors are read
inline constexpr std::size_t kListedLineBytes   = 240;   // one printed line (UTF-8-safe cut + ellipsis)

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

// The manifest reader and the path-name matcher are the where-else family's (whereelse.h), shared with --for's <where> and --brief.
using whereelse::boundedFind;
using whereelse::inNestedPackage;
using whereelse::isVendoredDir;
using whereelse::Manifest;
using whereelse::manifestsAbove;
using whereelse::Token;
using whereelse::tokensFor;

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

struct ManifestLine
{
    std::uint32_t    line = 0;
    std::string_view text;           // byte-exact, what is printed
    std::string_view code;           // the same bytes with comments blanked, what is matched
    std::uint32_t    stanza = 0;     // index of the line that opens this line's top-level stanza
};

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
                          std::string_view manifestsCap, std::vector<char>& esc, RedactCounts* redact )
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
        redactInPlace( text, redact );   // REDACT-TOUCH: BEFORE the cut, so a token crossing kListedLineBytes reaches the redactor whole
        truncateUtf8WithEllipsis( text, kListedLineBytes );
        x += std::format( "<ln l=\"{}\">{}</ln>", h.lines[ print[pi] ].line, escapeXml( text, esc ) );
    }
    x += "</listed>";
}

}   // namespace listeddetail

// The <listed> elements for the shown rows (rank order). Empty unless the task is a creation task and a manifest names a shown file.
// `redact`: the run's redaction tally, every printed <ln> passes it (nullptr: --no-redact).
inline ListedRender renderForListedIn( const IngestResult& ing, std::span<const NodeId> shown, std::string_view task, RedactCounts* redact )
{
    using namespace listeddetail;
    ListedRender out;
    if( ing.crawlRoot.empty() || shown.empty() || !isCreationTask( task ) )
    {
        return out;
    }
    std::vector<std::uint32_t> files;   // distinct shown files, rank order
    bool                       filesCapped = false;   // a shown file or a *.bzl file was left unread (kListedShownFiles, whereelse::kFragmentsPerDir)
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
        appendListed( out.xml, ing, files, manifests[ hits[hi].m ], hits[hi], cap, esc, redact );
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
