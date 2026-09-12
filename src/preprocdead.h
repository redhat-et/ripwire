#pragma once

// preprocdead.h — the ONE rule for "this C-family source region is DECIDED DEAD by the preprocessor",
// and the byte ranges it yields.
//
// WHY IT IS A HEADER AND NOT A SECOND COPY. The rule already existed, correct and documented, inside
// --slice (src/slice.h, "preprocessor-conditional regions"), where it stops a def under `#if 0` from
// replacing the live chain. Issue #62 (2026-09-08, @mariadb-KyleHutchinson) showed the CALL GRAPH needed
// the identical judgement and did not have it: a `return putObject(data, len, destKey);` sitting inside an
// `#if 0` block in mariadb-columnstore-engine was served by --uses and --callers as a live role="call"
// site, indistinguishable from the six real ones. Two consumers, one question — so the question is answered
// once, here, and slice.h calls it. A second spelling of "what does `#if 0` mean" is the §B4 echo-site
// drift this tree already has scar tissue for, and it would be worse here than usual: the two answers would
// disagree about which lines of a file exist.
//
// THE RULE, unchanged from the one --slice shipped and gated:
//   * DECIDED — and ONLY — when the condition is the bare literal `0` or `1`. `#if 0`'s body is dead (its
//     `#else` live); `#if 1`'s body is live (its `#else` dead). `#if (0)` is an expression, not a literal,
//     and is deliberately not decided: this is a lexical rule, not a preprocessor.
//   * UNDECIDED — everything else. `#ifdef X`, `#ifndef X`, `#if defined(X)`, `#if EXPR`, `#elif`. Whether
//     X is defined belongs to the BUILD (-DNDEBUG, -DHAVE_FOO), and "this file never #defines X" is exactly
//     the shape of a build-defined macro, so it is NOT evidence of dead code. Undecided regions stay LIVE
//     and are counted normally — over-counting a build variant is a floor; dropping it would be a false
//     zero, which is the defect class this whole change exists to remove, not to relocate.
//
// WHAT THIS BUYS THE COUNTS. counts_floor="1" promises true >= reported. A call site that cannot compile
// makes reported > true, so `#if 0` was breaking the floor CONTRACT, not merely adding noise — which is why
// the fix drops the edge rather than flagging it. Dropping restores the promise; a flag on a still-counted
// row would not. Gate: test/blindspotcheck.sh arm (D) (both halves: the dead row absent, the live one still
// served, so an empty answer cannot pass).

#include <cstdint>
#include <cstring>
#include <string_view>
#include <vector>

#include <tree_sitter/api.h>

#include "infra/fieldid.h"   // rw::fieldChild / NodeField — the field id resolved once per grammar, not per node
#include "infra/tschildren.h"   // P1-0: ChildCursor/collectChildren — the O(C) child collection this walk needs

namespace rw
{

// One decided-dead byte range, half-open [start, end).
struct PreprocDeadRange
{
    std::uint32_t start = 0;
    std::uint32_t end   = 0;
};

// What the literal condition of ONE preproc_if / preproc_elif node decides. Undecided is the default and
// the safe answer: every non-literal condition lands here.
enum class PreprocLiteral : std::uint8_t
{
    Undecided = 0,   // `#ifdef X`, `#if defined(X)`, `#if EXPR`, `#if (0)` — the build decides, not the file
    BodyDead  = 1,   // `#if 0`  — the body is dead, the `#else` arm is live
    BodyLive  = 2    // `#if 1`  — the body is live, the `#else` arm is dead
};

// The null guard is ingest_jsimports.h's jsNodeIs contract, adopted here so that spelling can forward to
// this one instead of being its third copy. It is strictly more defensive than the two callers that did
// not have it (slice.h's sliceKindIs, and this file's own walk, which never passes a null node).
inline bool preprocNodeKindIs( TSNode n, const char* kind ) noexcept
{
    return !ts_node_is_null( n ) && std::strcmp( ts_node_type( n ), kind ) == 0;
}

// THE RULE ITSELF — the only place the literal is read. slice.h's branch-state fold calls this, so the
// slicer and the call graph cannot come to different conclusions about the same `#if`.
inline PreprocLiteral preprocLiteralBranch( TSNode n, std::string_view src ) noexcept
{
    if( !preprocNodeKindIs( n, "preproc_if" ) && !preprocNodeKindIs( n, "preproc_elif" ) )
    {
        return PreprocLiteral::Undecided;
    }
    const TSNode cond = fieldChild( n, NodeField::Condition );
    if( ts_node_is_null( cond ) || !preprocNodeKindIs( cond, "number_literal" ) )
    {
        return PreprocLiteral::Undecided;
    }
    const std::uint32_t a = ts_node_start_byte( cond ), b = ts_node_end_byte( cond );
    if( b <= a || b > src.size() )
    {
        return PreprocLiteral::Undecided;
    }
    const std::string_view text = src.substr( a, b - a );
    if( text == "0" ) { return PreprocLiteral::BodyDead; }
    if( text == "1" ) { return PreprocLiteral::BodyLive; }
    return PreprocLiteral::Undecided;
}

// Collect every decided-dead byte range in one parsed C-family file.
//
// The dead BODY of `#if 0` runs from the end of the condition to the start of the `alternative` chain (or
// to the end of the node when there is none) — so the `#if 0` line itself and the `#else`/`#endif` markers
// are outside it, and a nested conditional inside a dead region simply lands inside a range that already
// covers it. The dead ALTERNATIVE of `#if 1` runs from the start of that chain to the end of the node.
//
// Ranges may overlap and are NOT merged: the only consumer asks "does this byte fall in any of them", and
// merging would be work done for no reader. Deterministic — one fixed DFS order, no map iteration.
//
// THE WALK IS CURSOR-BASED, NOT INDEXED (audit P1-0, 2026-09-10). It used to read its children with
// `ts_node_child( n, i )`, which restarts tree-sitter's child iterator from the first child on every call
// and so costs O(C²) in a node's child count — the exact rule stated on src/infra/tschildren.h, broken
// here because the helper that enforces it used to be reachable only from inside ingest.cpp. The `#if`
// text gate below is what hid it: no `#if` anywhere in a file means no walk at all, so Go/Python/JS
// corpora never pay it — but every C/C++ header on earth opens that gate with its INCLUDE GUARD, which
// then makes the guard's own preproc_ifdef node one node whose child list is the whole file. MEASURED,
// cold llvm-project, one interleaved pair on the same box: 202.14 s CPU / 26.60 s wall -> 170.46 s /
// 18.99 s, map byte-identical; this function's inclusive share of busy leaf samples 56.67% -> 2.07%, and
// `ts_node_child_iterator_next` 62.99% -> 13.44% (the residue is the OTHER indexed walks, itemised in
// test/preprocdeadscalecheck.sh's FOLLOW-UP block). The 31.7 s realised is well short of the 107 s the
// 56.67% share implies, because that share was read from a 12 s window of a 26 s run and a leaf share is
// not a whole-run share — the A/B is the number to believe. Same child set, same left-to-right order,
// same emitted ranges — only the cost changed. Gate:
// test/preprocdeadscalecheck.sh, whose arm (C) is the isolating control (the identical comment flood with
// and without an include guard) and whose (D1)/(D2) arms hold the byte-identity against the indexed form.
//
// Children are pushed in index order and popped from the back, so a node's children are VISITED in
// reverse; that is the order the indexed form had and it is preserved deliberately. Nothing downstream
// reads the range vector in order (inPreprocDead is a membership test), but "the ranges are the same
// SET" is a weaker claim than "the output is byte-identical", and only the second one is gateable.
inline std::vector<PreprocDeadRange> collectPreprocDeadRanges( TSNode root, std::string_view src )
{
    std::vector<PreprocDeadRange> out;
    // Cheap gate first: no `#if` text at all ⇒ no conditional nodes, and the overwhelming majority of files
    // in any corpus take this branch without a walk. `memmem` is not portable, so string_view::find.
    if( src.find( "#if" ) == std::string_view::npos )
    {
        return out;
    }

    std::vector<TSNode> stack;
    ChildCursor         cursor( root );   // reused across nodes — ts_tree_cursor_reset re-points it at each one
    stack.push_back( root );
    while( !stack.empty() )
    {
        const TSNode n = stack.back();
        stack.pop_back();

        const PreprocLiteral lit = preprocLiteralBranch( n, src );
        if( lit != PreprocLiteral::Undecided )
        {
            const TSNode      cond = fieldChild( n, NodeField::Condition );
            const TSNode      alt  = fieldChild( n, NodeField::Alternative );
            const std::uint32_t nEnd = ts_node_end_byte( n );
            if( lit == PreprocLiteral::BodyDead )
            {
                const std::uint32_t s = ts_node_is_null( cond ) ? ts_node_start_byte( n ) : ts_node_end_byte( cond );
                const std::uint32_t e = ts_node_is_null( alt ) ? nEnd : ts_node_start_byte( alt );
                if( e > s ) { out.push_back( PreprocDeadRange { s, e } ); }
            }
            else if( !ts_node_is_null( alt ) )
            {
                const std::uint32_t s = ts_node_start_byte( alt );
                if( nEnd > s ) { out.push_back( PreprocDeadRange { s, nEnd } ); }
            }
        }

        appendChildren( n, cursor.cur, stack );   // O(C), not O(C²) — index order in, reverse order out
    }
    return out;
}

// Does this byte sit inside a decided-dead region? Linear over a vector that is EMPTY for almost every
// file and single-digit for the rest — the empty case is one compare, which is why no index is built.
inline bool inPreprocDead( const std::vector<PreprocDeadRange>& dead, std::uint32_t byte ) noexcept
{
    for( const PreprocDeadRange& r : dead )
    {
        if( byte >= r.start && byte < r.end )
        {
            return true;
        }
    }
    return false;
}

}   // namespace rw
