#pragma once
// forfilepage.h — FOR-FILE-ANCHOR (issue #466, reported by @pguerrerolinares; peer-mine-mf1 card 2): the --for FILE PAGE.
//
// A --for subject that IS a file — a bare basename (`DynamicScreen.c`, `sync_ledger.py`), a file stem (`document-remind`,
// `sync_ledger`), a path, or a directory (`internal/sign package`) — used to get a name-exact no_candidates answer (1.2 KB,
// empty) or a confident subtoken scatter over files that merely share its subtokens. The honest answer is the file itself:
// every def it holds in line order (signature, end line, how many indexed callers and from which files), and, for a script
// whose work is its top-level code, that top-level TEXT — the statements outside every def that the `<file-scope>` row owns
// but has no body for (ingest_model.h assignSymbols zeroes that row's extent on purpose; this page reads the file span
// directly instead, so the one place serves every language that mints a `<file-scope>` row).
//
// PRESENT-ONLY (owner rule L-B: every --for byte must change the next step): the page rides only when the subject is
// file-SHAPED — once its file tokens, stopwords and file nouns ("file", "package", "script" …) are set aside nothing is left
// (forSubjectIsFileShaped). A question that merely mentions a file as context ("where ShellError used in ls.rs is defined")
// gets the mention anchor (mention.h) and no page. A name that matches several files lists them and picks none.
//
// HONESTY: in=0 is "no caller in the index", never "unused" (a registration, a table, dynamic dispatch or a build the index
// did not see may still reach it — the legend says so); via=name marks a def whose every caller was bound by name alone;
// the reachability verdict is not computed here, it is the existing --graph-query closure, named on next= when the corpus
// has a `main` to start it from. Caps are runaway guards, each cut disclosed with its total.
#include "graph.h"       // Graph::inEdges / outOff / outTargets / outNameOnly — the callers a def row counts
#include "lexical.h"     // isRouteStopword, splitRouteWords — the ONE stopword list the route reads
#include "mention.h"     // extractMentions, RawMention::whole, resolveStemFile, pathSuffixMatches, dirSuffixMatches
#include "model.h"
#include "nextverb.h"    // nextFlag — next= pastes into a shell
#include "docparse.h"    // docparse::detail::readWholeFile
#include "filter.h"      // isTestPath, isDemoOrGeneratedPath — the tier label on a listed file
#include "resolve.h"     // trimWs — the one blank-trimmer
#include "redact.h"      // redactInPlace — the top-level text is file text, redacted like any served body
#include "taskroute.h"   // taskroute::isOneOf — the one "is this word in the table" predicate
#include "serialize.h"   // escapeXml, appendCdataSafe, cleanSig, truncateUtf8WithEllipsis

#include <algorithm>
#include <cstdint>
#include <cstdlib>
#include <format>
#include <optional>
#include <tuple>
#include <string>
#include <string_view>
#include <vector>

namespace rw
{

// Runaway guards (knob census ADDENDUM), never size targets: every cut is disclosed (capped="1" + the total).
inline constexpr std::size_t kForFilePageDefRows     = 40;     // def rows per file
inline constexpr std::size_t kForFilePageDirFiles    = 6;      // files of a named directory given a page each
inline constexpr std::size_t kForFilePageListFiles   = 8;      // paths listed when a name matches several files
inline constexpr std::size_t kForFilePageCallerFiles = 3;      // caller files named per def (by_total= counts all)
inline constexpr std::size_t kForFilePageTopLines    = 40;     // top-level lines served per file
inline constexpr std::size_t kForFilePageTopBytes    = 2048;   // top-level bytes served per file
inline constexpr std::size_t kForFilePageSigBytes    = 160;    // one def row's signature text
inline constexpr std::size_t kForFilePageMaxAnchors  = 2;      // file tokens of one subject given a page
inline constexpr std::size_t kForFilePageMaxBytes  = 16384;   // the whole page: no file or directory starts past it (the first always does)
inline constexpr unsigned    kForFilePageNextDepth   = 16;      // calls the next= closure walks from main (said in the legend: a cap, not a fact)

inline bool forFilePageOn()
{
    return std::getenv( "RIPWIRE_NO_FILE_PAGE" ) == nullptr;
}

// One file token of the subject and what it resolved to. kind: 'b' basename, 's' stem, 'p' path, 'd' directory.
struct FileAnchor
{
    std::string                token;
    char                       kind  = 'b';
    std::vector<std::uint32_t> files;        // at most kForFilePageListFiles (a directory: its code files, at most that many)
    std::uint32_t              total = 0;    // every file it names
    bool                       near  = false;   // a SHORTER path than the one written matched: listed, never picked
    // the path ALSO names directories of code files (a file matched in full too): one row per directory, the one written exactly first
    // (root-relative path, ITS OWN code-file count — the shown and the counted set are the same set); dirsCut when more matched than rows
    std::vector<std::pair<std::string, std::uint32_t>> dirs;
    bool                       dirsCut = false;

    // is the anchor exactly one file the subject named in full (page it, lift it)?
    bool picksOne() const noexcept { return kind != 'd' && total == 1 && files.size() == 1 && !near && dirs.empty(); }
};

namespace filepage
{

inline std::string_view trimWordPunct( std::string_view w ) noexcept
{
    const auto punct = []( char c ) { return c == '"' || c == '\'' || c == '`' || c == '(' || c == ')' || c == ',' || c == ':' || c == ';'
                                             || c == '?' || c == '!' || c == '.' || c == '/'; };
    while( !w.empty() && punct( w.front() ) ) { w.remove_prefix( 1 ); }
    while( !w.empty() && punct( w.back() ) )  { w.remove_suffix( 1 ); }
    return w;
}

inline bool isFileNoun( std::string_view lw ) noexcept
{
    static constexpr std::string_view kNouns[] = { "file", "files", "package", "pkg", "module", "dir", "directory", "folder",
                                                   "script", "source", "header", "crate" };
    return taskroute::isOneOf( lw, kNouns, std::size( kNouns ) );
}

inline bool isListableCodeFile( std::string_view path ) noexcept
{
    const std::string_view base = mention_detail::baseNameOf( path );
    const std::string_view stem = mention_detail::stripExt( base );
    return stem.size() < base.size() && mention_detail::isCodeExtension( base.substr( stem.size() + 1 ) );
}

inline void addAnchor( std::vector<FileAnchor>& out, FileAnchor a )
{
    for( const FileAnchor& have : out )
    {
        if( have.files == a.files )
        {
            return;   // two spellings of one file (`a.py` and `src/a.py`): one page
        }
    }
    out.push_back( std::move( a ) );
}

} // namespace filepage

namespace filepage
{

// files whose root-relative path `match` accepts: the first kForFilePageListFiles kept, all counted
template<class Match>
inline void collectFiles( const IngestResult& ing, FileAnchor& a, Match match )
{
    for( std::uint32_t f = 0; f < ing.files.size(); ++f )
    {
        if( match( f ) )
        {
            if( a.files.size() < kForFilePageListFiles ) { a.files.push_back( f ); }
            ++a.total;
        }
    }
}

// The code files of the directories a slash token names (dirSuffixMatches), in the order the page serves them: a directory spelled
// exactly as written first, non-test before test, a module root (mod.rs, __init__.py, index.ts, lib.rs, main.go — the file that
// says what the directory is) first within them, path order after. `files` keeps the first kForFilePageListFiles of that order,
// `total` counts every one, and `dirs` holds one row per distinct directory with its own count.
inline FileAnchor collectDirFiles( const IngestResult& ing, const std::vector<std::string>& segments, const std::string& token )
{
    using namespace mention_detail;
    FileAnchor dir;
    dir.kind  = 'd';
    dir.token = token;
    struct Hit { std::uint32_t f; bool inexact, test, notRoot; std::string_view dirOf; };
    std::vector<Hit> hits;
    for( std::uint32_t f = 0; f < ing.files.size(); ++f )
    {
        const std::string_view rel = rootRelPath( ing, f );
        if( !isListableCodeFile( rel ) || !dirSuffixMatches( rel, segments ) )
        {
            continue;
        }
        const std::string_view base = baseNameOf( rel );
        const std::string_view stem = stripExt( base );
        const bool             root = stem == "mod" || stem == "__init__" || stem == "index" || stem == "lib" || stem == "main";
        const std::string_view dirOf = rel.substr( 0, rel.size() - base.size() - 1 );
        hits.push_back( { f, dirOf != token, isTestPath( rel ), !root, dirOf } );
    }
    std::stable_sort( hits.begin(), hits.end(), []( const Hit& x, const Hit& y )
                      { return std::tie( x.inexact, x.test, x.notRoot ) < std::tie( y.inexact, y.test, y.notRoot ); } );
    dir.total = std::uint32_t( hits.size() );
    for( const Hit& h : hits )
    {
        if( dir.files.size() < kForFilePageListFiles ) { dir.files.push_back( h.f ); }
        auto row = std::ranges::find_if( dir.dirs, [ & ]( const auto& d ) { return d.first == h.dirOf; } );
        if( row != dir.dirs.end() )   { ++row->second; }
        else if( dir.dirs.size() < kForFilePageListFiles ) { dir.dirs.emplace_back( std::string( h.dirOf ), 1u ); }
        else                                               { dir.dirsCut = true; }
    }
    return dir;
}

// one extracted mention as a file anchor: a bare basename (RawMention::whole), else a path by the longest suffix any file matches,
// else a directory whose code files a slash token names; total == 0 when it names no file
inline FileAnchor anchorOfMention( const IngestResult& ing, const mention_detail::RawMention& m )
{
    using namespace mention_detail;
    FileAnchor a;
    if( !m.whole.empty() )
    {
        a.token = m.whole;
        a.total = filesWithBaseName( ing, m.whole, &a.files, kForFilePageListFiles );
        return a;
    }
    if( !m.isPath )
    {
        return a;
    }
    for( std::size_t k = 0; k < m.segments.size(); ++k )
    {
        a.token += ( k ? "/" : "" ) + m.segments[k];
    }
    a.kind = 'p';
    const auto isCode = [ & ]( std::uint32_t f ) { return isListableCodeFile( ing.files[f] ); };
    // the path as WRITTEN, whole: a file at its full length ...
    collectFiles( ing, a, [ & ]( std::uint32_t f ) { return isCode( f ) && pathSuffixMatches( rootRelPath( ing, f ), m.segments ); } );
    // ... and the directory it may name — read on the full path BEFORE any shorter suffix, so `src/helper/cookie` is never
    // answered by an unrelated src/utils/cookie.ts that merely shares its last segment's stem
    FileAnchor dir = collectDirFiles( ing, m.segments, a.token );
    if( dir.total > 0 && a.total == 0 )
    {
        return dir;
    }
    if( dir.total > 0 )   // a file AND a directory answer to the written path: both said, none picked
    {
        a.dirs    = std::move( dir.dirs );
        a.dirsCut = dir.dirsCut;
        return a;
    }
    // a SHORTER suffix is never a page: a file at a path the subject did not write is listed as near, picked by nobody
    for( std::size_t suffixLen = m.segments.size() - 1; suffixLen >= 1 && a.total == 0; --suffixLen )
    {
        const std::vector<std::string> suffix( m.segments.end() - suffixLen, m.segments.end() );
        collectFiles( ing, a, [ & ]( std::uint32_t f ) { return isCode( f ) && pathSuffixMatches( rootRelPath( ing, f ), suffix ); } );
        a.near = a.total > 0;
    }
    return a;
}

// one hyphen/snake word as a file anchor (resolveStemFile's rule): the one file it names, or — no symbol of that name — the
// several code files sharing that stem (listed, none picked); no file → empty
inline FileAnchor anchorOfStem( const IngestResult& ing, std::string_view w )
{
    using namespace mention_detail;
    FileAnchor    a;
    std::uint32_t f = 0, total = 0;
    a.token.assign( w );
    a.kind = 's';
    if( resolveStemFile( ing, w, f, &total ) )
    {
        a.files.push_back( f );
        a.total = 1;
    }
    else if( total > 1 && std::none_of( ing.symbols.begin(), ing.symbols.end(), [ & ]( const Symbol& s ) { return s.name == w; } ) )
    {
        collectFiles( ing, a, [ & ]( std::uint32_t g ) { const std::string_view base = baseNameOf( ing.files[g] ); return stripExt( base ) == w && isListableCodeFile( base ); } );
    }
    return a;
}

} // namespace filepage

// The subject's file tokens, text order, resolved against the index exactly as the mention anchor reads them (mention.h):
// a bare basename by RawMention::whole, a path by the longest suffix any file matches, a directory when a slash token names
// no file but is the directory of indexed code files, and a stem by resolveStemFile's rule (a symbol of that exact name keeps
// the token a name). A token that resolves to nothing is not an anchor.
inline std::vector<FileAnchor> resolveFileAnchors( const IngestResult& ing, std::string_view task )
{
    std::vector<FileAnchor> out;
    for( const mention_detail::RawMention& m : mention_detail::extractMentions( task ) )
    {
        if( FileAnchor a = filepage::anchorOfMention( ing, m ); a.total > 0 )
        {
            filepage::addAnchor( out, std::move( a ) );
        }
    }
    for( const std::string_view w : mention_detail::extractStemTokens( task ) )
    {
        if( FileAnchor a = filepage::anchorOfStem( ing, w ); a.total > 0 )
        {
            filepage::addAnchor( out, std::move( a ) );
        }
    }
    return out;
}

// Is the subject the file(s) and nothing else? Every word is a resolved file token, a route stopword or a file noun.
inline bool forSubjectIsFileShaped( std::string_view task, const std::vector<FileAnchor>& anchors )
{
    if( anchors.empty() )
    {
        return false;
    }
    for( const std::string_view raw : splitRouteWords( task ) )
    {
        const std::string_view w = filepage::trimWordPunct( raw );
        if( w.empty() )
        {
            continue;
        }
        const std::string lw = routeLower( w );
        if( isRouteStopword( lw ) || filepage::isFileNoun( lw ) )
        {
            continue;
        }
        const bool isAnchor = std::ranges::any_of( anchors, [ & ]( const FileAnchor& a )
                                                   { return a.token == w || ( a.kind != 'b' && a.kind != 's' && w.ends_with( a.token ) ); } );
        if( !isAnchor )
        {
            return false;
        }
    }
    return true;
}

namespace filepage
{

// 1-based line of byte `at` in `src`, by the line-start table
inline std::uint32_t lineOfByte( const std::vector<std::uint32_t>& lineStart, std::uint32_t at ) noexcept
{
    return std::uint32_t( std::partition_point( lineStart.begin(), lineStart.end(), [ at ]( std::uint32_t start ) { return start <= at; } )
                          - lineStart.begin() );
}

struct CallerFacts
{
    std::uint32_t                                     callers  = 0;     // distinct indexed callers
    bool                                              allByName = false; // every one bound by name alone (via="name")
    std::vector<std::pair<std::uint32_t, std::uint32_t>> byFile;        // (caller count, fileId), most first then fileId
};

inline CallerFacts callerFactsOf( const IngestResult& ing, const Graph& g, NodeId id )
{
    CallerFacts out;
    const std::uint32_t* ro = g.inEdges.rowOffsets();
    const std::uint32_t* ci = g.inEdges.colIndices();
    if( ro == nullptr || ci == nullptr || id >= ing.symbols.size() )
    {
        return out;
    }
    bool anyPlain = false;
    for( std::uint32_t k = ro[id]; k < ro[id + 1]; ++k )
    {
        const NodeId caller = ci[k];
        if( caller == id || caller >= ing.symbols.size() )
        {
            continue;
        }
        ++out.callers;
        const bool byName = edgeNameOnly( g, caller, id );
        anyPlain = anyPlain || !byName;
        const std::uint32_t cf = ing.symbols[caller].fileId;
        auto at = std::ranges::find_if( out.byFile, [ & ]( const auto& p ) { return p.second == cf; } );
        if( at == out.byFile.end() ) { out.byFile.emplace_back( 1u, cf ); }
        else                         { ++at->first; }
    }
    out.allByName = out.callers > 0 && !anyPlain;
    std::sort( out.byFile.begin(), out.byFile.end(), []( const auto& a, const auto& b ) { return a.first != b.first ? a.first > b.first : a.second < b.second; } );
    return out;
}

inline std::string_view tierLabelOf( std::string_view rel ) noexcept
{
    if( isTestPath( rel ) )             { return "test"; }
    if( isDemoOrGeneratedPath( rel ) )  { return "generated"; }
    // quality.h kBuiltinVendoredPrefixes' four names, at any depth (the crawler drops three of them; external/ is reached)
    for( const std::string_view seg : { std::string_view( "third_party/" ), std::string_view( "vendor/" ), std::string_view( "node_modules/" ),
                                        std::string_view( "external/" ) } )
    {
        if( rel.starts_with( seg ) || hasDirSegment( rel, seg ) ) { return "vendored"; }
    }
    return {};
}

// does the corpus have a non-test `main` a reachability closure can start from?
inline bool corpusHasMain( const IngestResult& ing )
{
    return std::ranges::any_of( ing.symbols, [ & ]( const Symbol& s )
                                { return s.name == "main" && s.kind == SymKind::Function && !isTestPath( rootRelPath( ing, s.fileId ) ); } );
}

// the ECMAScript regex for one root-relative path, anchored at a component boundary — the --graph-query file() spelling
inline std::string pathRegexOf( std::string_view rel )
{
    std::string re = "(^|/)";
    for( const char c : rel )
    {
        if( std::string_view( "\\^$.|?*+()[]{}" ).find( c ) != std::string_view::npos )
        {
            re += '\\';
        }
        re += c;
    }
    return re + "$";
}

// One file's text, read now, and its line-start table (lineCount 0 when the read failed: nothing is claimed from it).
struct FileText
{
    std::string                src;
    std::vector<std::uint32_t> lineStart{ 0 };
    std::uint32_t              lineCount = 0;
    bool                       read      = false;

    std::string_view line( std::uint32_t x ) const noexcept   // 1-based, with its newline
    {
        const std::uint32_t s0 = lineStart[x - 1], s1 = x < lineCount ? lineStart[x] : std::uint32_t( src.size() );
        return std::string_view( src ).substr( s0, s1 - s0 );
    }
    bool blank( std::uint32_t x ) const noexcept   // nothing but blanks (resolve.h trimWs) before its newline
    {
        const std::string_view l = line( x );
        return trimWs( l.ends_with( '\n' ) ? l.substr( 0, l.size() - 1 ) : l ).empty();
    }
};

inline FileText loadFileText( const IngestResult& ing, std::uint32_t f )
{
    FileText t;
    if( std::optional<std::string> read = docparse::detail::readWholeFile( diskPath( ing, f ) ) )
    {
        t.src  = std::move( *read );
        t.read = true;
    }
    for( std::uint32_t i = 0; i < t.src.size(); ++i )
    {
        if( t.src[i] == '\n' && i + 1 < t.src.size() ) { t.lineStart.push_back( i + 1 ); }
    }
    t.lineCount = t.src.empty() ? 0u : std::uint32_t( t.lineStart.size() );
    return t;
}

// the file's defs (no function-local def, no <file-scope> row) in line order; `modScope` says whether a <file-scope> row exists
inline std::vector<NodeId> fileDefsInLineOrder( const IngestResult& ing, std::uint32_t f, bool& modScope )
{
    std::vector<NodeId> defs;
    modScope = false;
    for( const Symbol& s : ing.symbols )
    {
        if( s.fileId != f )
        {
            continue;
        }
        modScope = modScope || s.kind == SymKind::ModuleScope;
        if( s.kind != SymKind::ModuleScope && s.fnLocal == 0 )
        {
            defs.push_back( s.id );
        }
    }
    std::sort( defs.begin(), defs.end(), [ & ]( NodeId a, NodeId b ) { return ing.symbols[a].line != ing.symbols[b].line ? ing.symbols[a].line < ing.symbols[b].line : a < b; } );
    return defs;
}

// which lines the defs' spans cover (index 1..lineCount)
inline std::vector<char> coveredLines( const IngestResult& ing, const std::vector<NodeId>& defs, const FileText& t )
{
    std::vector<char> covered( t.lineCount + 2, 0 );
    for( const NodeId id : defs )
    {
        const Symbol& s = ing.symbols[id];
        if( s.endByte <= s.sigStartByte || s.endByte > t.src.size() )
        {
            continue;
        }
        const std::uint32_t b = std::min( lineOfByte( t.lineStart, s.endByte - 1 ), t.lineCount );
        std::fill( covered.begin() + lineOfByte( t.lineStart, s.sigStartByte ), covered.begin() + b + 1, char( 1 ) );
    }
    return covered;
}

inline void appendCallerAttrs( std::string& out, const IngestResult& ing, const CallerFacts& cf, std::vector<char>& esc )
{
    out += std::format( " in=\"{}\"", cf.callers );
    if( !cf.byFile.empty() )
    {
        out += " by=\"";
        for( std::size_t i = 0; i < cf.byFile.size() && i < kForFilePageCallerFiles; ++i )
        {
            out += i ? "," : "";
            out += escapeXml( rootRelPath( ing, cf.byFile[i].second ), esc );
        }
        out += "\"";
        if( cf.byFile.size() > kForFilePageCallerFiles )
        {
            out += std::format( " by_total=\"{}\"", cf.byFile.size() );
        }
    }
    if( cf.allByName )
    {
        out += " via=\"name\"";
    }
}

// one def row: <s t= n= l= e= in= by= via=>signature</s>
inline void appendDefRow( std::string& out, const IngestResult& ing, const Graph& g, const Symbol& s, const FileText& t, RedactCounts* redact,
                          std::vector<char>& esc )
{
    out += std::format( "<s t=\"{}\" n=\"", symTag( s.kind ) );
    out += escapeXml( s.name, esc );
    out += std::format( "\" l=\"{}\"", s.line );
    const bool spanRead = s.endByte > s.sigStartByte && s.endByte <= t.src.size();
    if( const std::uint32_t e = spanRead ? lineOfByte( t.lineStart, s.endByte - 1 ) : 0u; e > s.line )
    {
        out += std::format( " e=\"{}\"", e );
    }
    appendCallerAttrs( out, ing, callerFactsOf( ing, g, s.id ), esc );
    out += ">";
    if( s.sigStartByte < s.sigEndByte && s.sigEndByte <= t.src.size() )
    {
        std::string sig = cleanSig( t.src.data(), s.sigStartByte, s.sigEndByte, redact );
        truncateUtf8WithEllipsis( sig, kForFilePageSigBytes );
        out += escapeXml( sig, esc );
    }
    out += "</s>";
}

// The top-level text: each run of lines outside every def (blank edges trimmed) as <top l= e=>CDATA</top>, until the line or byte
// cap; what the cap left is disclosed once (<top_cut top_lines= shown= rest=>, rest= from the first line not shown to the last).
inline void appendTopLevel( std::string& out, const FileText& t, const std::vector<char>& covered, RedactCounts* redact )
{
    std::uint32_t topTotal = 0, shownLines = 0, shownBytes = 0, restFrom = 0, restTo = 0;
    for( std::uint32_t l = 1; l <= t.lineCount; ++l ) { topTotal += covered[l] ? 0u : 1u; }
    for( std::uint32_t l = 1; l <= t.lineCount; )
    {
        if( covered[l] ) { ++l; continue; }
        std::uint32_t a = l;
        while( l <= t.lineCount && !covered[l] ) { ++l; }
        std::uint32_t b = l - 1;
        while( a <= b && t.blank( a ) ) { ++a; }
        while( b >= a && t.blank( b ) ) { --b; }
        if( a > b || restFrom != 0 )
        {
            restTo = a > b ? restTo : b;
            continue;
        }
        std::uint32_t e = a, bytes = 0;
        for( ; e <= b && shownLines < kForFilePageTopLines && shownBytes + bytes + t.line( e ).size() <= kForFilePageTopBytes; ++e )
        {
            bytes += std::uint32_t( t.line( e ).size() );
            ++shownLines;
        }
        if( e > a )
        {
            std::string text( std::string_view( t.src ).substr( t.lineStart[a - 1], bytes ) );
            while( !text.empty() && ( text.back() == '\n' || text.back() == '\r' ) ) { text.pop_back(); }
            redactInPlace( text, redact );
            out += std::format( "<top l=\"{}\" e=\"{}\"><![CDATA[", a, e - 1 );
            appendCdataSafe( text, out );
            out += "]]></top>";
            shownBytes += bytes;
        }
        if( e <= b )
        {
            restFrom = e;
            restTo   = b;
        }
    }
    if( restFrom != 0 )
    {
        out += std::format( "<top_cut top_lines=\"{}\" shown=\"{}\" rest=\"{}-{}\"/>", topTotal, shownLines, restFrom, restTo );
    }
}

inline void appendFileOpenTag( std::string& out, std::string_view rel, const FileText& t, std::size_t defCount, std::string_view mainNext,
                               std::vector<char>& esc )
{
    out += "<named-file p=\"";
    out += escapeXml( rel, esc );
    out += std::format( "\" lines=\"{}\" defs=\"{}\"", t.lineCount, defCount );
    if( defCount > kForFilePageDefRows )
    {
        out += std::format( " shown=\"{}\" capped=\"1\"", kForFilePageDefRows );
    }
    if( const std::string_view tier = tierLabelOf( rel ); !tier.empty() )
    {
        out += std::format( " tier=\"{}\"", tier );
    }
    if( !t.read )
    {
        out += " unread=\"1\"";   // the file could not be read now: lines=0 is "not read", never "empty"
    }
    if( !mainNext.empty() )
    {
        out += " next=\"";
        out += escapeXml( mainNext, esc );
        out += "\"";
    }
    out += ">";
}

// one file's page: its defs in line order, then (a script) its top-level text
inline void renderOneFile( std::string& out, const IngestResult& ing, const Graph& g, std::uint32_t f, RedactCounts* redact,
                           bool withMainNext, std::vector<char>& esc )
{
    const std::string_view    rel = rootRelPath( ing, f );
    const FileText            t   = loadFileText( ing, f );
    bool                      modScope = false;
    const std::vector<NodeId> defs = fileDefsInLineOrder( ing, f, modScope );
    const bool hasFn = std::ranges::any_of( defs, [ & ]( NodeId id ) { return ing.symbols[id].kind == SymKind::Function || ing.symbols[id].kind == SymKind::Method; } );
    // a C/C++ header holds prototypes: their callers bind to the definitions, so "main does not reach" would be said of the wrong rows
    const std::string_view ext = mention_detail::fileExtOf( rel );
    const bool isHeader = ext == "h" || ext == "hpp" || ext == "hh";
    const std::string re = pathRegexOf( rel );
    // main's closure, and — a script's work is its top-level code — the file's own <file-scope> row's: what either reaches is not listed
    const std::string mainNext = withMainNext && hasFn && !isHeader
        ? nextFlag( "--graph-query=", "not(and(file(all,\"" + re + "\"),or(kind(all,fn),kind(all,method))),callees(or(name(\"main\"),and(file(all,\"" + re
                                      + "\"),kind(all,modscope))),"
                                      + std::to_string( kForFilePageNextDepth ) + "))" )
        : std::string();
    appendFileOpenTag( out, rel, t, defs.size(), mainNext, esc );
    for( std::size_t k = 0; k < defs.size() && k < kForFilePageDefRows; ++k )
    {
        appendDefRow( out, ing, g, ing.symbols[ defs[k] ], t, redact, esc );
    }
    // the top-level text: a file with a <file-scope> row whose defs cover under half its lines (a script, not a module of defs)
    const std::vector<char> covered = coveredLines( ing, defs, t );
    const std::size_t       coveredCount = std::size_t( std::count( covered.begin(), covered.end(), char( 1 ) ) );
    if( modScope && t.lineCount > 0 && coveredCount * 2 < t.lineCount )
    {
        appendTopLevel( out, t, covered, redact );
    }
    else if( !modScope && defs.empty() && t.lineCount > 0 )   // no def and no top-level row (a minified bundle): said, never an empty page
    {
        out += std::format( "<top_cut top_lines=\"{}\" shown=\"0\" rest=\"1-{}\"/>", t.lineCount, t.lineCount );
    }
    out += "</named-file>";
}

} // namespace filepage

// The page for a file-shaped subject ("" when the subject is not one or names nothing indexed).
inline std::string renderForFilePage( const IngestResult& ing, const Graph& g, std::string_view task, RedactCounts* redact )
{
    const std::vector<FileAnchor> anchors = resolveFileAnchors( ing, task );
    if( !forSubjectIsFileShaped( task, anchors ) )
    {
        return {};
    }
    std::string       out;
    std::vector<char> esc;
    const bool        withMainNext = filepage::corpusHasMain( ing );
    // the page has ONE byte bound (kForFilePageMaxBytes): a file or directory that would carry it past the bound is not started
    // (the first always is), and the cut is said — bytes_capped=1 on the directory or on <named-cut>
    const auto fits = [ & ]( std::size_t pending, std::size_t piece ) { return pending == 0 || pending + piece <= kForFilePageMaxBytes; };
    std::size_t paged = 0;
    bool        bytesCut = false;
    for( std::size_t ai = 0; ai < anchors.size() && ai < kForFilePageMaxAnchors; ++ai )
    {
        const FileAnchor& a = anchors[ai];
        std::string       piece;
        if( a.kind == 'd' )
        {
            const std::vector<std::uint32_t>& files = a.files;   // already in serving order (collectDirFiles)
            std::string       body;
            std::size_t       shown = 0;
            bool              dirCut = false;
            const std::size_t room = std::min( files.size(), kForFilePageDirFiles );
            for( ; shown < room; ++shown )
            {
                std::string one;
                filepage::renderOneFile( one, ing, g, files[shown], redact, withMainNext, esc );
                if( !fits( out.size() + body.size(), one.size() ) ) { dirCut = true; break; }
                body += one;
            }
            if( shown == 0 && dirCut ) { bytesCut = true; break; }   // not even its first file fits: the directory is not started
            piece += "<named-dir p=\"";
            piece += escapeXml( a.token, esc );
            piece += std::format( "\" files=\"{}\"", a.total );
            if( shown < a.total )
            {
                piece += std::format( " shown=\"{}\" capped=\"1\"{}", shown, dirCut ? " bytes_capped=\"1\"" : "" );
            }
            piece += ">";
            piece += body;
            piece += "</named-dir>";
            bytesCut = bytesCut || dirCut;
        }
        else if( a.picksOne() )
        {
            filepage::renderOneFile( piece, ing, g, a.files.front(), redact, withMainNext, esc );
            if( !fits( out.size(), piece.size() ) ) { bytesCut = true; break; }
        }
        else
        {
            piece += "<named-files n=\"";
            piece += escapeXml( a.token, esc );
            piece += std::format( "\" total=\"{}\"{}{}", a.total, a.near ? " near=\"1\"" : "", a.dirsCut ? " dirs_capped=\"1\"" : "" );
            if( a.files.size() < a.total )
            {
                piece += std::format( " shown=\"{}\" capped=\"1\"", a.files.size() );
            }
            piece += ">";
            for( const std::uint32_t f : a.files )
            {
                const std::string_view rel = rootRelPath( ing, f );
                const std::size_t defs = std::size_t( std::ranges::count_if( ing.symbols, [ & ]( const Symbol& s ) { return s.fileId == f && s.kind != SymKind::ModuleScope && s.fnLocal == 0; } ) );
                piece += "<f p=\"";
                piece += escapeXml( rel, esc );
                piece += std::format( "\" defs=\"{}\"", defs );
                if( const std::string_view tier = filepage::tierLabelOf( rel ); !tier.empty() )
                {
                    piece += std::format( " tier=\"{}\"", tier );
                }
                piece += "/>";
            }
            for( const auto& [dirPath, dirFiles] : a.dirs )   // the written path is ALSO a directory: a row per directory (the one written first)
            {
                piece += "<f p=\"";
                piece += escapeXml( dirPath, esc );
                piece += std::format( "/\" dir=\"1\" files=\"{}\"/>", dirFiles );
            }
            piece += "</named-files>";
            if( !fits( out.size(), piece.size() ) ) { bytesCut = true; break; }   // the one byte bound holds for a listing after a full directory too
        }
        out += piece;
        ++paged;
    }
    if( anchors.size() > paged )   // a subject naming more files than this pages: the cut is said, never silent
    {
        out += std::format( "<named-cut total=\"{}\" shown=\"{}\"{}/>", anchors.size(), paged, bytesCut ? " bytes_capped=\"1\"" : "" );
    }
    return out;
}

// The note the lift leaves on the mention note (one text for the CLI and both MCP twins). It says what the lift did to the auto-served
// bodies: they follow the named file's rank now, a def ranked lower gets none, and the way to read one. No "--" (an XML comment).
inline std::string fileSubjectNote( std::uint32_t moved )
{
    return std::format( " [file subject: {} defs of the named file ranked first; the bodies served follow that rank, a def ranked lower gets none "
                        "(its body: the expand flag, by name)]", moved );
}

// FILE SUBJECT LIFT: when the subject IS a file (forSubjectIsFileShaped) the named file's defs are the answer, so its top
// kMentionMaxSymbolsPerFile defs (by current score, then line) are ranked ABOVE everything else — the B8 mention anchor keeps a
// named file just below #1 because there the file is context in a longer question, here it is the whole question. A name that
// matches several files lifts nothing (never a silent pick); a directory lifts each of its first kForFilePageDirFiles code files
// (non-test first). Returns how many symbols moved; the caller discloses it.
inline std::uint32_t applyFileSubjectLift( const IngestResult& ing, std::string_view task, std::vector<float>& lensRank )
{
    if( lensRank.size() != ing.symbols.size() )
    {
        return 0;
    }
    const std::vector<FileAnchor> anchors = resolveFileAnchors( ing, task );
    if( !forSubjectIsFileShaped( task, anchors ) )
    {
        return 0;
    }
    std::vector<std::uint32_t> files;
    for( std::size_t ai = 0; ai < anchors.size() && ai < kForFilePageMaxAnchors; ++ai )
    {
        const FileAnchor& a = anchors[ai];
        if( a.kind == 'd' )
        {
            files.insert( files.end(), a.files.begin(), a.files.begin() + std::min( a.files.size(), kForFilePageDirFiles ) );   // serving order
        }
        else if( a.picksOne() )
        {
            files.push_back( a.files.front() );
        }
    }
    float top = 0.0f;
    for( const float v : lensRank ) { top = std::max( top, v ); }
    if( !( top > 0.0f ) ) { top = 1.0f; }
    std::uint32_t moved = 0;
    for( std::size_t fi = 0; fi < files.size(); ++fi )
    {
        std::vector<NodeId> mine;
        for( const Symbol& s : ing.symbols )
        {
            if( s.fileId == files[fi] && s.fnLocal == 0 )
            {
                mine.push_back( s.id );
            }
        }
        std::sort( mine.begin(), mine.end(), [ & ]( NodeId a, NodeId b )
                   { return lensRank[a] != lensRank[b] ? lensRank[a] > lensRank[b] : ing.symbols[a].line != ing.symbols[b].line ? ing.symbols[a].line < ing.symbols[b].line : a < b; } );
        for( std::size_t k = 0; k < mine.size() && k < kMentionMaxSymbolsPerFile; ++k )
        {
            // file fi, slot k: strictly above the old top, file order then slot order
            const float slot = top * ( 1.0f + 0.01f * float( ( files.size() - fi ) * kMentionMaxSymbolsPerFile - k ) );
            if( lensRank[ mine[k] ] < slot )
            {
                lensRank[ mine[k] ] = slot;
                ++moved;
            }
        }
    }
    return moved;
}

// The page's legend clauses, present-only beside it: the full and the compact dialect. No "--" inside (they ride in an XML comment).
inline constexpr std::string_view kForFilePageLegend =
    "; named-file p= lines= defs=: the file the task names (a basename, a file stem, a path, or a file of a named-dir), its defs in "
    "line order; s t= n= l= e=: a def and its first/last line, in= its indexed callers (in=0: no caller in the index, NOT unused: a "
    "registration, a table, dynamic dispatch or code the index did not see may reach it), by= their files (by_total= all), via=name "
    "every caller bound by name alone; next= the graph query listing the file's defs that neither main nor the file's own top-level code "
    "reaches within 16 calls (a walk cap, and not proof: a registration or dynamic dispatch may still reach them); top l= e=: the file's "
    "top-level text outside every def, top_cut top_lines= shown= rest=: of the top-level lines, those not shown (in the file; no verb serves them); "
    "named-files n= total=: the name matches several files, f p= defs= each, none picked; near=1 only a SHORTER path than the one written "
    "matched (listed, never picked); f p= dir=1 files=: the written path is also a directory (one row each, the one written first) of that many code files, dirs_capped=1 more directories matched than rows; named-dir p= files=: that "
    "directory's code files; tier=test|generated|vendored; unread=1 the file could not be read; named-cut total= shown=: the subject names more "
    "files than were paged; bytes_capped=1 the page stopped at its 16 KB bound, at a file boundary; shown= capped=1 the list was cut";
inline constexpr std::string_view kForCompactFilePageLegend =
    "; named-file p= lines= defs=: the named file, defs in line order; s t= n= l= e= in= callers (0: none indexed, NOT unused) by= "
    "their files, by_total= all, via=name; next= graph query of defs neither main nor the file's top-level code reaches within 16 calls "
    "(a walk cap); top l= e=: top-level text, top_cut top_lines= shown= rest=: lines not shown; named-files n= total=: several files, "
    "f p= defs=, none picked; near=1 only a shorter path matched; f dir=1 files=: also a directory, dirs_capped=1 more than rows; named-dir p= files=; "
    "tier=test|generated|vendored; unread=1; named-cut total= shown=: more files named than paged; bytes_capped=1 page stopped at 16 KB; shown= capped=1 cut";

} // namespace rw
