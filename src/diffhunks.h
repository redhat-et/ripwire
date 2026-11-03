#pragma once
#include <string_view>       // %.*s (precision, pointer) collapses to one view

// diffhunks.h — THE zero-context diff-hunk primitive: what `git diff --unified=0 vs HEAD` says moved, as
// (oldStart, oldCount, newStart, newCount) ranges, and the two access shapes over it —
//   gitDiffHunksVsHead / diffHunksMemoized   ONE spawn per PATH, lazily (quality.h's churn lens)
//   gitDiffHunksAllVsHead                    ONE spawn for the WHOLE working tree (situ.h's symbol-granular
//                                            change set — the change set is known up front there, so the
//                                            per-path lazy shape would be a subprocess per changed file)
// Both parse hunk headers through the SAME parseHunkHeaderLine, so the four sscanf forms live once.
//
// Extracted from quality.h (2026-09-27) when --situ grew the symbol-granular change set: situ.h could not
// include quality.h (a late, heavy header), and a second hunk parser beside the churn lens's is exactly the
// clone the house rules exist to prevent. quality.h now includes THIS header; its churnEditWindowCommitCount
// consumes these types unchanged.
//
// THE CONTRACT, both shapes: degrade-only. No git, no HEAD, spawn failure, an unparseable header → an empty
// result, which every caller reads as "no evidence" and falls back to its conservative superset — never as
// "nothing changed". A hunk is (oldStart, oldCount, newStart, newCount), 1-based, git's own spelling: a count
// of 1 is omitted in the header, oldCount==0 is a pure insertion, newCount==0 a pure deletion.

#include "model.h"           // HashMap
#include "gitcmd.h"          // rw::gitCmd — every git child starts with the hardened prefix (githarden.h)
#include "infra/jsonesc.h"   // rw::shSingleQuote — the ONE shell-quote (gitmine.h names it canonical here)
#include "infra/os.h"        // rw::os::popen / pclose — the OS seam
#include "infra/Diagnostics.h"   // DISCLOSE — the degrade path's one record

#include <cstdint>
#include <cstdio>
#include <cstring>
#include <string>
#include <vector>

namespace rw
{

// One zero-context unified-diff hunk, in the two coordinate systems the consumers need: the OLD-side range
// (what `git blame` is asked about) and the NEW-side range (what a working-tree symbol's line span is
// compared against). SoA is pointless for four u32s read together — this is one cache line either way.
struct DiffHunk
{
    std::uint32_t oldStart = 0;
    std::uint32_t oldCount = 0;
    std::uint32_t newStart = 0;
    std::uint32_t newCount = 0;
};
static_assert( sizeof( DiffHunk ) == 16, "DiffHunk is a 4×u32 POD" );

// The ONE hunk-header parser: "@@ -oldStart[,oldCount] +newStart[,newCount] @@", git omitting a count of 1.
// Returns false (out untouched) on any line that is not a well-formed header — the caller skips it, which is
// the per-hunk degrade both access shapes share. Negative components are refused rather than wrapped; git
// never emits them, and a hostile path cannot reach these fields anyway (the values only ever index line
// ranges), but a wrapped u32 would silently become a huge range.
inline bool parseHunkHeaderLine( const char* buf, DiffHunk& out )
{
    if( buf[0] != '@' || buf[1] != '@' )
    {
        return false;   // only hunk-header lines matter here
    }
    int oldStart = 0, oldCount = 1, newStart = 0, newCount = 1;
    if( std::sscanf( buf, "@@ -%d,%d +%d,%d @@", &oldStart, &oldCount, &newStart, &newCount ) == 4 ) {}
    else if( std::sscanf( buf, "@@ -%d,%d +%d @@", &oldStart, &oldCount, &newStart ) == 3 ) { newCount = 1; }
    else if( std::sscanf( buf, "@@ -%d +%d,%d @@", &oldStart, &newStart, &newCount ) == 3 ) { oldCount = 1; }
    else if( std::sscanf( buf, "@@ -%d +%d @@", &oldStart, &newStart ) == 2 ) { oldCount = 1; newCount = 1; }
    else
    {
        return false;   // malformed/unexpected header — skip (degrade per-hunk)
    }
    if( oldStart < 0 || oldCount < 0 || newStart < 0 || newCount < 0 )
    {
        return false;   // git never emits these; refuse rather than wrap
    }
    out = DiffHunk{ std::uint32_t( oldStart ), std::uint32_t( oldCount ),
                    std::uint32_t( newStart ), std::uint32_t( newCount ) };
    return true;
}

// The ONE git invocation shape both access forms share. `pathspec` is the already-quoted " -- <path>" tail,
// or empty for the whole tree. FLAG ORDER IS LOAD-BEARING for one substring: test/qchurnmemocheck.sh's shim
// log greps the per-path form "--no-ext-diff --no-textconv --ignore-submodules=dirty --unified=0 --no-color HEAD -- <path>"
// (contiguous) — do not insert a flag inside it. --src-prefix/--dst-prefix pin the a/ b/ spelling regardless of a configured
// diff.noprefix (the whole-tree parser reads "+++ b/<path>"). --no-ext-diff disarms a diff.external driver
// (NOT `-c diff.external=` — an EMPTY value is an external diff whose command is "", and git dies trying to
// exec it; see quality.h's churn-lens note, where that mistake was first measured: 8 gating rows silently
// went AMBIENT). -c diff.algorithm=myers pins hunk BOUNDARIES against a configured histogram/patience
// algorithm, same reason as the churn lens.
inline std::string gitDiffHunksCmd( const std::string& root, const std::string& quotedPathspec )
{
    return gitCmd( " -c core.quotepath=false -c diff.algorithm=myers -C " ) + shSingleQuote( root )
         + " diff --no-ext-diff --no-textconv --ignore-submodules=dirty --unified=0 --no-color"
         + ( quotedPathspec.empty() ? " --src-prefix=a/ --dst-prefix=b/" : "" )   // whole-tree only: the per-path form is pinned byte-for-byte by qchurnmemocheck
         + " HEAD" + quotedPathspec + " 2>/dev/null";
}

// The run-scoped hunk memo (P3, r27 — moved with its primitive). `git diff --unified=0 HEAD -- <path>` is a
// pure function of (HEAD, working tree), both FIXED for the life of one call, yet the churn blame pass once
// spawned it per SYMBOL: a subprocess-shim log showed EIGHT byte-identical spawns for a single dirty file.
// Caller owns the storage (house rule — views/handles at seams, no hidden process-global state that a second
// root or a second MCP request would silently share).
// hwh-fix4 (N1): the read carries whether git answered. A failed diff (git refused, an absent HEAD blob on a partial clone) is not
// "no hunks": the churn lens reports that row's self/ambient split as unknown instead of reading the silence as ambient.
struct DiffHunkRead
{
    std::vector<DiffHunk> hunks;
    bool                  ok = true;   // false: the spawn failed or git exited non-zero; `hunks` is then empty
};
using DiffHunkMemo = HashMap<std::string, DiffHunkRead>;

// Parse `relPath`'s zero-context hunk headers vs HEAD. Degrade-only: no git / no HEAD / path absent at HEAD →
// an EMPTY vector, which the caller reads as "no evidence" → its conservative fallback (quality.h's churn
// lens: AMBIENT, never inflates severity; situ.h: file-granular, never narrows on missing evidence).
inline std::vector<DiffHunk> gitDiffHunksVsHead( const std::string& root, const std::string& relPath, bool* okOut = nullptr )
{
    if( okOut )
    {
        *okOut = false;
    }
    std::vector<DiffHunk> hunks;
    const std::string cmd = gitDiffHunksCmd( root, " -- " + shSingleQuote( relPath ) );
    std::FILE* pipe = os::popen( cmd.c_str(), "r" );
    if( !pipe ) { DISCLOSE( "diffhunks: hunk diff could not be spawned" ); return hunks; }

    char buf[ 4096 ];
    while( std::fgets( buf, sizeof( buf ), pipe ) )
    {
        DiffHunk h;
        if( parseHunkHeaderLine( buf, h ) )
        {
            hunks.push_back( h );
        }
    }
    const int rc = os::pclose( pipe );
    if( okOut )
    {
        *okOut = rc == 0;
    }
    if( rc != 0 )
    {
        hunks.clear();   // a non-zero git exit is not an empty diff (CR lens 5): no partial hunk list survives it
    }
    return hunks;
}

// Memoized accessor: one `git diff` spawn per PATH per run, not per symbol. A path with no hunks memoizes the
// empty vector too, so a repeatedly-queried clean path costs one spawn, not N.
inline const DiffHunkRead& diffHunksMemoized( DiffHunkMemo& memo, const std::string& root, const std::string& relPath )
{
    const auto it = memo.find( relPath );
    if( it != memo.end() )
    {
        return it->second;
    }
    DiffHunkRead read;
    read.hunks = gitDiffHunksVsHead( root, relPath, &read.ok );
    return memo.emplace( relPath, std::move( read ) ).first->second;
}

// The WHOLE-TREE shape: ONE spawn, every dirty path's hunks, keyed by the diff's own repo-root-relative
// NEW-side spelling (gitmine.h's forEachBoundGitPath is the ONE join from that spelling to ingested
// fileIds — the same join the numstat mask builder uses, so hunks and the changed-file mask can never
// disagree about which file a path names). `ok` is false ONLY when the spawn itself failed; ok=true with an
// empty map is a MEASUREMENT (nothing content-changed vs HEAD — every consumer then keeps its file-granular
// superset, which is exactly the pre-hunk behavior).
//
// DEGRADE DIRECTIONS, all conservative — the parser never invents a hunk and never moves one to another
// file, so every failure mode lands on "this file has no evidence" and its consumer falls back:
//   * "+++ /dev/null" (a deleted file): its hunks are dropped — the file has no working-tree symbols to
//     locate them in anyway, and the mask builder's own numstat pass is what decides deletion handling.
//   * a path line longer than the read buffer: the key is cut mid-path, binds to nothing, and the real file
//     degrades to no-evidence → file-granular. (git pathspecs beyond PATH_MAX are refused by git first.)
//   * a binary file / mode-only change / pure rename: git emits no hunks for it, so it simply has no entry.
struct HunkDiffAll
{
    HashMap<std::string, std::vector<DiffHunk>> byPath;
    bool ok = false;
};

inline HunkDiffAll gitDiffHunksAllVsHead( const std::string& root )
{
    HunkDiffAll out;
    const std::string cmd = gitDiffHunksCmd( root, {} );
    std::FILE* pipe = os::popen( cmd.c_str(), "r" );
    // No DISCLOSE( msg ) here on purpose: `ok=false` IS the sink — it is what the caller reads, and situ.h's
    // change_set: line surfaces it as evidence=0 (a sink-less trace ships nothing under NDEBUG and spends
    // the sink-less ratchet, test/selfcheckcheck.sh arm R).
    if( !pipe ) { return out; }
    out.ok = true;

    // fgets reads the stream in fixed chunks; a line longer than the buffer arrives in pieces. For hunk
    // headers (short, bounded) that cannot happen below 4096; for +++ path lines it degrades as documented
    // above. `lineCut` tracks a split line so its continuation chunks are not re-read as new lines — a body
    // line longer than the buffer must not have its tail mistaken for a header either.
    // NOTE: no pointer into byPath is held across iterations — ankerl::unordered_dense stores values in one
    // contiguous vector, so the NEXT file's insert could reallocate and dangle it. The section key is a
    // string; each hunk pays one hash lookup, which beside a git spawn is noise.
    //
    // HEADER POSITION ONLY (the "+++ " trap): an ADDED line whose content starts "++ " is "+++ …" in the diff,
    // and a DELETED line starting "-- " is "--- …". Read as a file header, the first reset the current path and
    // silently dropped every later hunk of the file — a narrower answer from a parser bug. A hunk header
    // announces its body exactly (oldCount '-' lines plus newCount '+' lines; "\ No newline" markers are not
    // counted), so `bodyLeft` consumes the body before any line is allowed to be a file header again.
    char          buf[ 8192 ];
    std::string   curPath;              // the diff's NEW-side spelling of the current file section; empty = drop (deletion / preamble)
    bool          lineCut = false;      // the previous chunk ended mid-line (no '\n')
    std::uint64_t bodyLeft = 0;         // '-' / '+' body lines the last hunk header announced and this stream has not yet delivered
    while( std::fgets( buf, sizeof( buf ), pipe ) )
    {
        const std::size_t len = std::strlen( buf );
        const bool        eol  = len > 0 && buf[len - 1] == '\n';
        if( lineCut )
        {
            lineCut = !eol;   // swallow the continuation; a cut path key stays cut (documented degrade)
            continue;
        }
        lineCut = !eol;
        if( bodyLeft > 0 )
        {
            if( buf[0] == '-' || buf[0] == '+' ) { --bodyLeft; continue; }
            if( buf[0] == '\\' ) { continue; }   // "\ No newline at end of file" belongs to the body and is not counted
            bodyLeft = 0;   // not a body line at all (the counts lied): resynchronise on the header rules below
        }
        if( buf[0] == '+' && buf[1] == '+' && buf[2] == '+' && buf[3] == ' ' )
        {
            // "+++ b/<path>" (prefixes pinned by --dst-prefix=b/ above), or "+++ /dev/null" for a deletion.
            // A trailing '\t' starts git's optional timestamp/quoting tail — cut there. Trailing '\r' (a
            // CRLF-diff artifact on the path line) is cut too.
            curPath.clear();
            if( len <= 6 || std::strncmp( buf + 4, "/dev/null", 9 ) == 0 )
            {
                continue;   // a bare "+++ " line (or /dev/null) names no NEW-side path — drop the section
            }
            curPath.assign( buf + 6 );   // skip "+++ b/"
            while( !curPath.empty() && ( curPath.back() == '\n' || curPath.back() == '\r' || curPath.back() == '\t' || curPath.back() == ' ' ) )
            {
                curPath.pop_back();
            }
            continue;
        }
        DiffHunk h;
        if( !curPath.empty() && parseHunkHeaderLine( buf, h ) )
        {
            out.byPath[ curPath ].push_back( h );
            bodyLeft = std::uint64_t( h.oldCount ) + h.newCount;
        }
    }
    if( os::pclose( pipe ) != 0 )
    {
        // git failed (no repo, no HEAD, a killed child): whatever was parsed is a truncated or empty stream, so it
        // is "no evidence", never a measurement of "nothing changed" — `ok=false` is what the change_set: line reads
        // as evidence=0. `git diff` without --exit-code exits 0 on a diff, so non-zero is always a failure.
        out.byPath.clear();
        out.ok = false;
        return out;
    }
    // A file section that collected no hunks (a mode line, a pure rename's similarity block) leaves an empty
    // vector behind — indistinguishable from "no entry" to every consumer, but erase it so byPath.size()
    // counts files WITH hunk evidence, which is what situ.h's disclosure could otherwise overstate.
    for( auto it = out.byPath.begin(); it != out.byPath.end(); )
    {
        it = it->second.empty() ? out.byPath.erase( it ) : std::next( it );
    }
    return out;
}

}   // namespace rw
