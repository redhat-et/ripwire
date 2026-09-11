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
    const TSNode cond = ts_node_child_by_field_name( n, "condition", 9 );
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
// merging would be work done for no reader. Deterministic — pre-order, no map iteration, no allocation
// beyond the output vector.
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
    stack.push_back( root );
    while( !stack.empty() )
    {
        const TSNode n = stack.back();
        stack.pop_back();

        const PreprocLiteral lit = preprocLiteralBranch( n, src );
        if( lit != PreprocLiteral::Undecided )
        {
            const TSNode      cond = ts_node_child_by_field_name( n, "condition", 9 );
            const TSNode      alt  = ts_node_child_by_field_name( n, "alternative", 11 );
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

        const std::uint32_t kids = ts_node_child_count( n );
        for( std::uint32_t i = 0; i < kids; ++i )
        {
            stack.push_back( ts_node_child( n, i ) );
        }
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
