#pragma once

// slicediff.h — `--slice=SYM:VAR --since=REV`: the def-use slice as it was at REV versus as it is now,
// so a regression review reads the DEPENDENCE change and not the textual diff (card A4, from COMMITGUARD
// arXiv:2608.17401). docs/EVALS.md carries the band, the output contract and the 57-row labelled set the
// feature is judged on; test/slicediffcheck.sh is the gate. Both were written before this file.
//
// THE ONE DESIGN DECISION, and everything else follows from it: **the diff's unit is the STATEMENT, and
// the two sides are aligned on ROLE, never on line number and never on text.**
//
//   • STATEMENT, not line. src/slice.h emits one <s> per LINE but already anchors its flow chaining on
//     the enclosing statement (sliceStmtAnchorLine). A def-use EDGE is a statement-to-statement fact, so
//     re-wrapping `sink( v + 1 );` across two lines moves no edge. Line keying would call that a
//     dependence change, and re-wrapping is half of what the reformat bucket of the band is made of.
//   • ROLE, not text. Rows are paired by a canonical LCS over the tuple (binding group, k, t, pp) in
//     source order. Text keying would make `f( v, w )` -> `f( v, z )` — a rename of an UNRELATED local —
//     a dependence change, which is the other half of that bucket. Line keying would make an insertion
//     ABOVE the symbol one, for every row at once.
//
// The consequence is stated in the legend rather than left to be discovered: `v = 111;` -> `v = 222;` is
// an EMPTY diff. That is correct — no def-use edge moved — and it is why the element is named for
// dependence and not for change. A reader who wants "did the text change" already has `git diff`.
//
// THE REV SIDE IS ONE FILE, not a tree. `--slice` is single-root and re-parses the definition's own file
// (src/slice.h's contract); nothing in the slice reads the call graph. So the REV side needs exactly the
// blob at that revision plus the definition's span inside it — `git show REV:path` into a private temp
// root, ingested by the SAME ingestOneFile() the pre-apply edit preview uses (src/editpreview.h), then
// the SAME sliceScanDefinition(). No `git archive`, no whole-tree re-ingest, no second parser path: a
// warm run is milliseconds, which is what makes a 57-commit gate replay affordable.
//
// ABSENCE IS DISCLOSED, NEVER SILENTLY EMPTY. status= names which of five ways the comparison went; when
// it could not be made at all the element says comparable="0" and the legend says outright that an empty
// diff under it is not evidence of no change. That is the same ruling counts="as-classified" already
// makes one level up: a number that cannot be a total must not be printed as one.

#include "slice.h"          // SliceScan / SliceOcc / sliceFoldOcc / sliceReachingDefs / sliceScanDefinition
#include "editpreview.h"    // editpreview::ingestOneFile — the ONE single-file parse path (self-contained by its own header note)
#include "gitmine.h"        // looksLikeDate — the ONE approxidate-garbage gate --hotspots --since already uses
#include "quality.h"        // gitRepoHasHistory / gitResolveCommitSha / gitOneLine / gitRenameMap / cacheDirLadder / TmpTreeGuard
#include "redact.h"         // redactInPlace — the body-emission seam every CDATA payload passes through
#include "sarif.h"          // rootPrefixOf / rootRelativeUri — the root-relative path identity

#include <algorithm>
#include <cstdint>
#include <filesystem>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

namespace rw
{
namespace slicediff
{

// src/slice.h lives in rw::slicev; the names this file builds on are pulled in explicitly rather than by
// a using-directive, so a reader can see the whole borrowed surface in one place.
using slicev::kSliceUnbound;
using slicev::occTag;
using slicev::OccT;
using slicev::SliceFam;
using slicev::SliceLineRow;
using slicev::SliceOcc;
using slicev::SliceScan;
using slicev::sliceReachingDefs;
using slicev::sliceScanDefinition;
using slicev::SliceVarRows;

// The DP alignment is O(n*m) in statement rows of ONE variable inside ONE definition. A real slice is
// tens of rows; this bound exists so a pathological generated file cannot turn a ~ms verb into a stall.
// Hitting it is DISCLOSED (diff_capped="1"), never silently truncated to a wrong answer.
inline constexpr std::size_t kMaxDiffRows = 2000;

// how far a rename chain is followed between REV and the working tree before the answer becomes
// "the path is not there" — a chain deeper than this is vanishingly rare and must not be a loop
inline constexpr std::size_t kMaxRenameHops = 8;

enum class Status : std::uint8_t
{
    Ok = 0,                // both sides sliced
    SymAbsentAtRev,        // the file was there, the definition was not — the symbol is new
    VarAbsentAtRev,        // the definition was there, the variable was not — the local is new
    FileAbsentAtRev,       // the path is not in the REV tree and no recorded rename reaches it
    AmbiguousAtRev,        // several same-named definitions of that kind in the file at REV
    UnparsedAtRev,         // the blob is there and the grammar could not locate the span in it
};

inline const char* statusTag( Status s ) noexcept
{
    // declarative table over a switch (G2), indexed by the enum value
    static constexpr const char* kNames[] = { "ok", "sym_absent_at_rev", "var_absent_at_rev",
                                              "file_absent_at_rev", "ambiguous_at_rev", "unparsed_at_rev" };
    static_assert( std::size( kNames ) == std::size_t( Status::UnparsedAtRev ) + 1 );
    const std::size_t at = std::size_t( s );
    return kNames[ at < std::size( kNames ) ? at : 0 ];
}

// A statement-grain row of ONE variable: the unit the diff is keyed on. `stmt` is the chaining anchor
// (sliceStmtAnchorLine, folded through SliceOcc::stmtLine); `line` is the first line of the row, kept for
// display only and deliberately absent from the key.
struct StmtRow
{
    std::uint32_t stmt   = 0;
    std::uint32_t line   = 0;
    std::uint32_t grp    = 0;      // binding group, in first-appearance order (a shadowed name is >1)
    OccT          t      = OccT::Read;
    bool          hasDef = false;
    bool          hasUse = false;
    bool          pp     = false;
};

struct DefUseEdge
{
    std::uint32_t d = 0;    // the reaching DEF's row ordinal
    std::uint32_t u = 0;    // the USE's row ordinal
};

struct Side
{
    std::vector<StmtRow>    rows;
    std::vector<DefUseEdge> edges;
    bool                    capped = false;
};

// what the caller splices into the <slice> element and its legend
struct Out
{
    bool        ok = true;      // false => refuse at exit 1; `err` is the whole sentence
    std::string err;
    std::string legend;         // the <!-- --> block appended after the slice legend
    std::string body;           // the <since …>…</since> child element
};

// ── the two folds ────────────────────────────────────────────────────────────────────────────────────

// STATEMENT-grain fold of one variable's occurrences. Mirrors sliceFoldOcc's aggregation rules exactly
// (first role then min'd by enum priority, def/use OR'd, pp OR'd, a new row when the binding changes) —
// only the KEY differs: the statement anchor instead of the line. Kept here rather than parameterizing
// sliceFoldOcc because the v1 row emission is a byte contract that must not acquire a mode switch.
inline std::vector<StmtRow> foldStatements( const std::vector<SliceOcc>& occ )
{
    std::vector<StmtRow>       rows;
    std::vector<std::uint32_t> groupOf;      // bindingIdx, in first-appearance order — grp is the index here
    for( const SliceOcc& o : occ )
    {
        const std::uint32_t key = o.stmtLine != 0 ? o.stmtLine : o.line;
        std::size_t         gi  = 0;
        while( gi < groupOf.size() && groupOf[ gi ] != o.bindingIdx )
        {
            ++gi;
        }
        if( gi == groupOf.size() )
        {
            groupOf.push_back( o.bindingIdx );
        }
        if( rows.empty() || rows.back().stmt != key || rows.back().grp != std::uint32_t( gi ) )
        {
            rows.push_back( StmtRow{ key, o.line, std::uint32_t( gi ), o.t, false, false, false } );
        }
        StmtRow& r = rows.back();
        r.hasDef   = r.hasDef || o.isDef;
        r.hasUse   = r.hasUse || o.isUse;
        r.pp       = r.pp || o.pp;
        if( std::uint8_t( o.t ) < std::uint8_t( r.t ) )
        {
            r.t = o.t;   // enum order IS the priority order (src/slice.h)
        }
        if( o.line < r.line )
        {
            r.line = o.line;
        }
    }
    return rows;
}

// The def-use EDGES of a statement-grain row list, per binding group, by src/slice.h's own reaching-
// definition rule (sliceReachingDefs: the last unconditional def before the use, plus every pp def after
// it). Reusing that function rather than restating the rule is the point — the diff and the --slice-flow
// walk can never disagree about what an edge is.
inline std::vector<DefUseEdge> edgesOf( const std::vector<StmtRow>& rows )
{
    std::vector<DefUseEdge> out;
    std::uint32_t           maxGrp = 0;
    for( const StmtRow& r : rows )
    {
        maxGrp = r.grp > maxGrp ? r.grp : maxGrp;
    }
    for( std::uint32_t grp = 0; rows.empty() ? false : grp <= maxGrp; ++grp )
    {
        SliceVarRows               v;
        std::vector<std::uint32_t> ordinalOf;   // index inside v.rows → row ordinal in `rows`
        for( std::uint32_t at = 0; at < rows.size(); ++at )
        {
            if( rows[ at ].grp != grp )
            {
                continue;
            }
            const StmtRow& r = rows[ at ];
            v.rows.push_back( SliceLineRow{ r.stmt, r.hasDef, r.hasUse, r.t, r.pp, kSliceUnbound } );
            ordinalOf.push_back( at );
        }
        for( std::size_t at = 0; at < v.rows.size(); ++at )
        {
            if( !v.rows[ at ].hasUse )
            {
                continue;
            }
            for( std::size_t defAt : sliceReachingDefs( v, v.rows[ at ].line ) )
            {
                out.push_back( DefUseEdge{ ordinalOf[ defAt ], ordinalOf[ at ] } );
            }
        }
    }
    std::sort( out.begin(), out.end(), []( const DefUseEdge& a, const DefUseEdge& b )
               { return a.d != b.d ? a.d < b.d : a.u < b.u; } );
    return out;
}

inline Side sideOf( const SliceScan& scan )
{
    Side s;
    s.rows = foldStatements( scan.occ );
    if( s.rows.size() > kMaxDiffRows )
    {
        s.rows.resize( kMaxDiffRows );
        s.capped = true;
    }
    s.edges = edgesOf( s.rows );
    return s;
}

// ── the alignment ────────────────────────────────────────────────────────────────────────────────────

// the ROLE key: binding group, role, def/use, pp — and nothing positional. This is the whole reformat
// immunity in one line, so it is spelled out rather than hidden behind a hash.
inline std::uint64_t roleKey( const StmtRow& r ) noexcept
{
    return ( std::uint64_t( r.grp ) << 16 ) | ( std::uint64_t( std::uint8_t( r.t ) ) << 8 )
         | ( std::uint64_t( r.hasDef ? 1 : 0 ) << 2 ) | ( std::uint64_t( r.hasUse ? 1 : 0 ) << 1 )
         | std::uint64_t( r.pp ? 1 : 0 );
}

// Canonical longest-common-subsequence pairing over the role keys. The tie rule (>= prefers the OLD
// side's step) is fixed here so the pairing is a pure function of the two sequences: an alignment that
// depended on anything else would make the emitted rows depend on it too, and determinism is a contract.
inline std::vector<std::pair<std::uint32_t, std::uint32_t>> alignRows( const std::vector<StmtRow>& was,
                                                                      const std::vector<StmtRow>& now )
{
    const std::size_t                                       n = was.size();
    const std::size_t                                       m = now.size();
    std::vector<std::pair<std::uint32_t, std::uint32_t>>    pairs;
    if( n == 0 || m == 0 )
    {
        return pairs;
    }
    std::vector<std::uint32_t> keyWas( n ), keyNow( m );
    for( std::size_t at = 0; at < n; ++at ) { keyWas[ at ] = std::uint32_t( roleKey( was[ at ] ) ); }
    for( std::size_t at = 0; at < m; ++at ) { keyNow[ at ] = std::uint32_t( roleKey( now[ at ] ) ); }

    std::vector<std::uint32_t> dp( ( n + 1 ) * ( m + 1 ), 0 );
    const auto                 cell = [ & ]( std::size_t i, std::size_t j ) -> std::uint32_t& { return dp[ i * ( m + 1 ) + j ]; };
    for( std::size_t i = 1; i <= n; ++i )
    {
        for( std::size_t j = 1; j <= m; ++j )
        {
            if( keyWas[ i - 1 ] == keyNow[ j - 1 ] )
            {
                cell( i, j ) = cell( i - 1, j - 1 ) + 1;
            }
            else
            {
                cell( i, j ) = cell( i - 1, j ) >= cell( i, j - 1 ) ? cell( i - 1, j ) : cell( i, j - 1 );
            }
        }
    }
    std::size_t i = n, j = m;
    while( i > 0 && j > 0 )
    {
        if( keyWas[ i - 1 ] == keyNow[ j - 1 ] )
        {
            pairs.push_back( { std::uint32_t( i - 1 ), std::uint32_t( j - 1 ) } );
            --i;
            --j;
        }
        else if( cell( i - 1, j ) >= cell( i, j - 1 ) )
        {
            --i;
        }
        else
        {
            --j;
        }
    }
    std::reverse( pairs.begin(), pairs.end() );
    return pairs;
}

// ── the REV side ─────────────────────────────────────────────────────────────────────────────────────

struct RevSide
{
    Status      status = Status::Ok;
    std::string sha;              // the resolved commit (full)
    std::string path;             // the root-relative path READ at REV (may differ from now: renamed_from=)
    std::string src;              // the blob, exactly as both the ingest and the scan below saw it
    SliceScan   scan;
};

// The blob at `sha:rel`, following a git-RECORDED rename chain (never a similarity guess of our own —
// quality.h's gitRenameMap pins `-c diff.renames=true` and reads what git already decided). "" when the
// path is not reachable at that revision; `pathAtRev` is set to the spelling that answered.
inline std::string blobAtRev( const std::string& root, const std::string& sha, const std::string& rel,
                              std::string& pathAtRev )
{
    const auto read = [ & ]( const std::string& p ) -> std::string
    {
        if( quality::gitOneLine( root, "cat-file -e " + shSingleQuote( sha + ":" + p ) + " 2>/dev/null && echo ok" ) != "ok" )
        {
            return {};
        }
        return quality::gitOneLine( root, "show " + shSingleQuote( sha + ":" + p ) + " 2>/dev/null" );
    };
    std::string blob = read( rel );
    if( !blob.empty() )
    {
        pathAtRev = rel;
        return blob;
    }
    const quality::RenameMap rm  = quality::gitRenameMap( root, sha + "..HEAD" );
    std::string              cur = rel;
    for( std::size_t hop = 0; hop < kMaxRenameHops; ++hop )
    {
        const auto it = rm.previousOf.find( cur );
        if( it == rm.previousOf.end() )
        {
            return {};
        }
        cur = it->second;
        // a rename that changes the EXTENSION changes the language, and with it what a definition even is;
        // refuse to follow it rather than slice two files with two grammars and call the difference a
        // dependence change
        if( std::filesystem::path( cur ).extension() != std::filesystem::path( rel ).extension() )
        {
            return {};
        }
        blob = read( cur );
        if( !blob.empty() )
        {
            pathAtRev = cur;
            return blob;
        }
    }
    return {};
}

// The slice of `sym`'s definition as it stood at `sha`. One blob, one single-file ingest, one
// sliceScanDefinition — the same three steps the working-tree side already took, in the same order.
inline RevSide sliceAtRev( const std::string& root, const std::string& sha, const std::string& rel,
                           const Symbol& sym, SliceFam fam, const ::TSLanguage* grammar,
                           std::string_view varName, std::size_t maxFileBytes, bool captureValueUses )
{
    namespace fs = std::filesystem;
    RevSide r;
    r.sha  = sha;
    r.path = rel;

    std::string pathAtRev;
    r.src = blobAtRev( root, sha, rel, pathAtRev );
    if( r.src.empty() )
    {
        r.status = Status::FileAbsentAtRev;
        return r;
    }
    r.path = pathAtRev;

    std::error_code   ec;
    const std::string tmpRoot = quality::cacheDirLadder() + "/ripwire-slicediff-" + std::to_string( ::getpid() );
    fs::remove_all( fs::path( tmpRoot ), ec );                   // a leftover from a crashed prior run
    if( !fs::create_directories( fs::path( tmpRoot ), ec ) && ec )
    {
        DEGRADED_PATH_ALERT( "slicediff: cannot create the temp parse root" );
        r.status = Status::UnparsedAtRev;
        return r;
    }
    quality::TmpTreeGuard guard{ tmpRoot };

    const IngestResult one = editpreview::ingestOneFile( tmpRoot, r.path, r.src, maxFileBytes, captureValueUses );

    // the definition at REV: same NAME and same KIND in that file. Several is not narrowed silently —
    // a slice of "some overload" is an answer about a body the caller may never have meant (§A6a, the
    // same ruling --slice itself makes on an ambiguous selector), so it is disclosed and not compared.
    const Symbol* pick  = nullptr;
    std::size_t   found = 0;
    for( const Symbol& cand : one.symbols )
    {
        if( cand.name == sym.name && cand.kind == sym.kind && cand.sigStartByte < cand.endByte )
        {
            ++found;
            pick = &cand;
        }
    }
    if( found == 0 )
    {
        r.status = Status::SymAbsentAtRev;
        return r;
    }
    if( found > 1 )
    {
        r.status = Status::AmbiguousAtRev;
        return r;
    }
    r.scan = sliceScanDefinition( r.src, *pick, fam, grammar, varName );
    if( !r.scan.parseOk )
    {
        r.status = Status::UnparsedAtRev;
        return r;
    }
    if( r.scan.occ.empty() )
    {
        r.status = Status::VarAbsentAtRev;
    }
    return r;
}

// ── the legend ───────────────────────────────────────────────────────────────────────────────────────

// Every limit the slice legend states applies to BOTH sides of the diff, and the diff adds two of its
// own. The band requires this block to restate them rather than assume the reader scrolled up: a diff
// cannot be more confident than the slice it diffs.
inline std::string legendText( bool compact )
{
    if( compact )
    {
        // the ripwire.slice/v1 tier, admitted for this block for the reason it was admitted for the slice
        // itself (audit 2026-09-02, F-11): the repeated-call loop must not pay the full paragraph every
        // time. Same rules, same vocabulary, no rule dropped — only the prose explaining each one.
        return
            "<!-- slice-since ripwire.slice/v1: DEPENDENCE diff of this variable against the tree at rev=, resolved= the "
            "commit it resolved to, p= the definition's path now, renamed_from= the spelling that answered at REV. "
            "<sd op= i= k= t= l= [pp=] [g=]> = one STATEMENT of the variable added or removed; <se op= d= u= dl= ul=/> = one "
            "def-use EDGE added or removed, by the slice's own reaching-definition rule. UNIT = the STATEMENT, KEY = the ROLE "
            "— never the line, never the text: a re-wrap, a comment edit, an insertion above the definition, a rename of an "
            "unrelated local and a value-only edit are all EMPTY. EMPTY means no def-use edge of this variable moved, never "
            "that the commit changed nothing. Every limit of the slice legend holds on BOTH sides. status=ok | "
            "sym_absent_at_rev | var_absent_at_rev | file_absent_at_rev | ambiguous_at_rev | unparsed_at_rev; comparable=0 = "
            "NO comparison was made and the emptiness is not evidence; diff_capped=1 = over 2000 statement rows on a side. "
            "Full legend: omit legend=compact. -->";
    }
    return
        "<!-- slice-since: the DEPENDENCE diff of this variable between REV and now — what a regression review "
        "wants instead of the textual diff. rev= the spec as given, resolved= the commit it resolved to, p= the definition's path NOW "
        "and renamed_from= the spelling that answered at REV when a git-RECORDED rename had to be followed to reach it. "
        "ROWS: <sd op= i= k= t= l= [pp=] [g=]>, g= the binding group of a shadowed name and omitted for group 0, "
        "= one STATEMENT of the variable that this change ADDED (op=\"+\", it exists now) or REMOVED "
        "(op=\"-\", it existed at REV); i= is its ordinal in that side's statement order, l= its line on that side, "
        "CDATA that side's text. <se op= d= u= dl= ul=/> = one DEF-USE EDGE added or removed, d=/u= the ordinals of "
        "its def and its use, dl=/ul= their lines — edges are src/slice.h's own reaching-definition rule (the last "
        "unconditional def before the use, plus any build-dependent def after it), so this diff and slice-flow can "
        "never disagree about what an edge is. THE UNIT IS THE STATEMENT, not the line: a statement spanning several "
        "lines is ONE row, keyed on the chaining anchor, so re-wrapping it moves nothing. THE KEY IS THE ROLE, not "
        "the text and not the line: the two sides are paired by a longest-common-subsequence over (binding, k, t, pp) "
        "in source order. Two consequences, both deliberate: an edit that changes a statement's VALUE but not its role "
        "(`v = 111;` to `v = 222;`) is an EMPTY diff, and so is a comment edit, a re-indent, an insertion above the "
        "definition, or a rename of an unrelated local — none of them moves a def-use edge. EMPTY therefore means "
        "\"no def-use edge of this variable moved\", NEVER \"this commit changed nothing\"; git diff is the verb for "
        "the second question. EVERY LIMIT OF THE SLICE ABOVE HOLDS ON BOTH SIDES: name-based, no alias analysis, no "
        "flow sensitivity, intra-procedural, a write hidden behind a call is a use, block scopes separated, C-family "
        "#if 0 dropped and other conditionals kept+flagged. added=/removed=/edges_added=/edges_removed= are counts of "
        "rows emitted here, governed by the root's counts=\"as-classified\" in both directions. status=\"ok\" both "
        "sides sliced | \"sym_absent_at_rev\" the file was there and the definition was not (every row reads \"+\") | "
        "\"var_absent_at_rev\" the definition was there and this local was not | \"file_absent_at_rev\" the path is "
        "not in that tree and no recorded rename reaches it | \"ambiguous_at_rev\" several same-named definitions of "
        "that kind in the file then, never silently narrowed | \"unparsed_at_rev\" the blob is there and the span did "
        "not locate. comparable=\"0\" = NO COMPARISON WAS MADE: the absence of rows under it is not evidence of no "
        "change, and must not be read as one. diff_capped=\"1\" = more than 2000 statement rows on a side, aligned to "
        "that bound and said so. -->";
}

// ── the element ──────────────────────────────────────────────────────────────────────────────────────

// the trimmed source line at `line1`, redacted and made ]]>-safe — the CDATA payload rule the v1 rows use
inline void appendRowText( std::string& out, const std::string& src, std::uint32_t line1, RedactCounts* redact )
{
    std::size_t   start = 0;
    std::uint32_t at    = 1;
    while( at < line1 )
    {
        const std::size_t nl = src.find( '\n', start );
        if( nl == std::string::npos )
        {
            start = src.size();
            break;
        }
        start = nl + 1;
        ++at;
    }
    std::size_t end = src.find( '\n', start );
    if( end == std::string::npos )
    {
        end = src.size();
    }
    std::string text( src, start, end - start );
    const std::size_t first = text.find_first_not_of( " \t\r" );
    const std::size_t last  = text.find_last_not_of( " \t\r" );
    text = ( first == std::string::npos ) ? std::string() : text.substr( first, last - first + 1 );
    redactInPlace( text, redact );
    out += "><![CDATA[";
    std::string safe;
    safe.reserve( text.size() );
    appendCdataSafe( text, safe );
    out += safe;
    out += "]]></sd>";
}

inline const char* rowKind( const StmtRow& r ) noexcept
{
    return r.hasDef && r.hasUse ? "both" : r.hasDef ? "def" : r.hasUse ? "use" : "scope";
}

// THE ENTRY POINT. `nowScan` is the working-tree scan the caller already computed (never re-derived here:
// two scans of one tree that could disagree is exactly the shape this file exists to avoid), `relPath` its
// root-relative path, `src` its bytes. Returns the two strings the emitter splices, or a refusal.
inline Out compute( const std::string& root, const std::string& sinceSpec, const std::string& relPath,
                    const Symbol& sym, SliceFam fam, const ::TSLanguage* grammar, std::string_view varName,
                    const SliceScan& nowScan, const std::string& src, RedactCounts* redact,
                    std::size_t maxFileBytes, bool captureValueUses, bool compactLegend )
{
    Out out;

    if( !quality::gitRepoHasHistory( root ) )
    {
        out.ok  = false;
        out.err = "ripwire: --slice --since=" + sinceSpec + " compares this definition against a COMMITTED tree, and '" + root
                + "' is not a git repository with a resolvable HEAD — there is nothing to compare against, and an empty "
                  "answer would be a claim this run cannot make";
        return out;
    }

    // REV|DATE, the same two spellings --since already takes elsewhere. A revision resolves directly; a
    // date resolves to the newest commit at or before it, and resolved= discloses WHICH — a comparison
    // against "some commit around then" that never says which one is not a measurement.
    std::string sha = quality::gitResolveCommitSha( root, sinceSpec );
    if( sha.empty() && looksLikeDate( sinceSpec ) )
    {
        // looksLikeDate is the SAME coarse allowlist --hotspots --since already screens with, and it is
        // load-bearing here for the same reason it is there: git's approxidate answers "now" for anything
        // it cannot parse, so `--since=zzqq9nope` would otherwise resolve to HEAD and print an all-zero
        // diff of the tree against itself — a wrong answer wearing the shape of a right one.
        const std::string byDate = quality::gitOneLine( root, "rev-list -1 --before=" + shSingleQuote( sinceSpec ) + " HEAD 2>/dev/null" );
        sha                      = quality::gitResolveCommitSha( root, byDate );
    }
    if( sha.empty() )
    {
        out.ok  = false;
        out.err = "ripwire: --since=" + sinceSpec + " resolves to no commit in '" + root
                + "' — beside --slice it names the revision to compare this variable's def-use slice against "
                  "(e.g. --since=HEAD~1, --since=<sha>, --since=\"2 weeks ago\")";
        return out;
    }

    const RevSide was = sliceAtRev( root, sha, relPath, sym, fam, grammar, varName, maxFileBytes, captureValueUses );

    const Side nowSide = sideOf( nowScan );
    const Side wasSide = was.status == Status::Ok || was.status == Status::VarAbsentAtRev ? sideOf( was.scan ) : Side{};

    // comparable="0" is the honest answer for every status where one side could not be produced at all.
    // sym_absent/var_absent ARE comparable: the definition (or the local) is new, so every row is added.
    const bool comparable = was.status == Status::Ok || was.status == Status::SymAbsentAtRev
                                                    || was.status == Status::VarAbsentAtRev;

    std::vector<char> esc;
    const auto        ex = [ & ]( std::string_view v ) -> std::string { return std::string( escapeXml( v, esc ) ); };

    std::string rows;
    std::size_t added = 0, removed = 0, edgeAdded = 0, edgeRemoved = 0;

    if( comparable )
    {
        const std::vector<std::pair<std::uint32_t, std::uint32_t>> pairs = alignRows( wasSide.rows, nowSide.rows );

        std::vector<char>          matchedWas( wasSide.rows.size(), 0 );
        std::vector<char>          matchedNow( nowSide.rows.size(), 0 );
        std::vector<std::uint32_t> mapTo( wasSide.rows.size(), 0xFFFFFFFFu );
        for( const auto& [ wasAt, nowAt ] : pairs )
        {
            matchedWas[ wasAt ] = 1;
            matchedNow[ nowAt ] = 1;
            mapTo[ wasAt ]      = nowAt;
        }

        // rows: removed first (ordinal ascending), then added (ordinal ascending) — a fixed order, so the
        // document is a pure function of the two sides
        for( std::uint32_t at = 0; at < wasSide.rows.size(); ++at )
        {
            if( matchedWas[ at ] )
            {
                continue;
            }
            const StmtRow& r = wasSide.rows[ at ];
            rows += "<sd op=\"-\" i=\"" + std::to_string( at ) + "\" k=\"" + rowKind( r ) + "\" t=\"" + occTag( r.t )
                  + "\" l=\"" + std::to_string( r.line ) + "\"";
            if( r.grp != 0 )
            {
                rows += " g=\"" + std::to_string( r.grp ) + "\"";
            }
            if( r.pp )
            {
                rows += " pp=\"1\"";
            }
            appendRowText( rows, was.src, r.line, redact );
            ++removed;
        }
        for( std::uint32_t at = 0; at < nowSide.rows.size(); ++at )
        {
            if( matchedNow[ at ] )
            {
                continue;
            }
            const StmtRow& r = nowSide.rows[ at ];
            rows += "<sd op=\"+\" i=\"" + std::to_string( at ) + "\" k=\"" + rowKind( r ) + "\" t=\"" + occTag( r.t )
                  + "\" l=\"" + std::to_string( r.line ) + "\"";
            if( r.grp != 0 )
            {
                rows += " g=\"" + std::to_string( r.grp ) + "\"";
            }
            if( r.pp )
            {
                rows += " pp=\"1\"";
            }
            appendRowText( rows, src, r.line, redact );
            ++added;
        }

        // edges: an old edge SURVIVES only when both endpoints paired and the mapped pair exists now
        const auto hasEdge = [ & ]( const std::vector<DefUseEdge>& in, std::uint32_t d, std::uint32_t u )
        {
            for( const DefUseEdge& e : in )
            {
                if( e.d == d && e.u == u ) { return true; }
            }
            return false;
        };
        std::vector<char> keptNow( nowSide.edges.size(), 0 );
        std::string       edgeRows;
        for( const DefUseEdge& e : wasSide.edges )
        {
            const std::uint32_t md = e.d < mapTo.size() ? mapTo[ e.d ] : 0xFFFFFFFFu;
            const std::uint32_t mu = e.u < mapTo.size() ? mapTo[ e.u ] : 0xFFFFFFFFu;
            bool                kept = false;
            if( md != 0xFFFFFFFFu && mu != 0xFFFFFFFFu && hasEdge( nowSide.edges, md, mu ) )
            {
                kept = true;
                for( std::size_t at = 0; at < nowSide.edges.size(); ++at )
                {
                    if( nowSide.edges[ at ].d == md && nowSide.edges[ at ].u == mu ) { keptNow[ at ] = 1; }
                }
            }
            if( !kept )
            {
                edgeRows += "<se op=\"-\" d=\"" + std::to_string( e.d ) + "\" u=\"" + std::to_string( e.u )
                          + "\" dl=\"" + std::to_string( wasSide.rows[ e.d ].line ) + "\" ul=\""
                          + std::to_string( wasSide.rows[ e.u ].line ) + "\"/>";
                ++edgeRemoved;
            }
        }
        for( std::size_t at = 0; at < nowSide.edges.size(); ++at )
        {
            if( keptNow[ at ] )
            {
                continue;
            }
            const DefUseEdge& e = nowSide.edges[ at ];
            edgeRows += "<se op=\"+\" d=\"" + std::to_string( e.d ) + "\" u=\"" + std::to_string( e.u )
                      + "\" dl=\"" + std::to_string( nowSide.rows[ e.d ].line ) + "\" ul=\""
                      + std::to_string( nowSide.rows[ e.u ].line ) + "\"/>";
            ++edgeAdded;
        }
        rows += edgeRows;
    }

    std::string el = "<since rev=\"" + ex( sinceSpec ) + "\" resolved=\"" + ex( sha.substr( 0, 9 ) ) + "\" p=\"" + ex( relPath ) + "\"";
    if( was.path != relPath && was.status != Status::FileAbsentAtRev )
    {
        el += " renamed_from=\"" + ex( was.path ) + "\"";   // the spelling that answered at REV, followed once
    }
    el += " status=\"";
    el += statusTag( was.status );
    el += "\"";
    if( !comparable )
    {
        el += " comparable=\"0\"";
    }
    else
    {
        el += " added=\"" + std::to_string( added ) + "\" removed=\"" + std::to_string( removed )
            + "\" edges_added=\"" + std::to_string( edgeAdded ) + "\" edges_removed=\"" + std::to_string( edgeRemoved ) + "\"";
        if( nowSide.capped || wasSide.capped )
        {
            el += " diff_capped=\"1\"";
        }
    }
    el += ">";
    el += rows;
    el += "</since>";

    out.legend = legendText( compactLegend );
    out.body   = el;
    return out;
}

}   // namespace slicediff
}   // namespace rw
