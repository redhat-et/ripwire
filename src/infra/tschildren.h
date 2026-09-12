#pragma once
// tschildren.h — O(children) child collection for UNBOUNDED-WIDTH tree-sitter walks.
//
// WHY THIS EXISTS. `ts_node_child( n, i )` restarts tree-sitter's child iterator from the FIRST child on
// every call (vendored `ts_node__child`, third_party/deps/tree_sitter/lib/src/node.c:139 — it builds a
// fresh `ts_node_iterate_children` each time and calls `ts_node__relevant_child_count` on each skipped
// invisible child), so an indexed loop over a node's C children costs O(C²). Width is
// attacker-controlled: ONE 980 KB file of 14 000 line comments hands the root 14 000 children and turned
// ingest into ~2 s of user CPU, quadratic in line count (gate: test/padscalecheck.sh). Every
// unbounded-width walk therefore collects the child list ONCE per node with a TSTreeCursor — the same
// child set (named + anonymous + extras) in the same left-to-right order, O(C) total. The cursor and the
// out vector are caller-owned and reused across nodes, so a warm walk allocates nothing per node.
//
// "BOUNDED SHAPE" IS NOT A PROPERTY OF THE GRAMMAR RULE — IT IS A PROPERTY OF THE LIST, AND ALMOST NO LIST
// HAS IT. Earlier revisions of this note named base clauses, argument lists and a declaration's declarators
// as the safe indexed cases, "their widths come from the grammar, not from the input file". That was wrong,
// and every one of those three was measured quadratic on 2026-09-10 (lane W3): a `base_class_clause` with
// 16 000 comments in it is 13x the same file with the flood outside the clause, an `argument_list` 56x, a
// `declaration` 77x, a lambda capture list 26x (test/childwalkscalecheck.sh, arms B7 and B10..B12). A
// comment can sit between ANY two children of ANY node, and tree-sitter splices an extra into the child
// array it is parsing — so the width of a list is set by the FILE wherever a comment may legally appear in
// it, which is everywhere. The indexed form is right only where the node's child list cannot grow at all:
// a FIXED-INDEX probe (`ts_node_child( n, 0 )`), or a scan of a node whose children a comment cannot reach.
// If you cannot name that reason in one line, use the cursor.
//
// Lane W4 (2026-09-10) then audited the ~25 loops the class-3 table had left across ingest_relations.h,
// ingest_names.h, ingest_elixir.h, ingest_sidecap.h and pattern.h: twenty-two of them measured 13x..126x
// their control under the flood and are cursors now (test/childwalkscalecheck.sh, arms B13..B36 — every
// one proven red on the pre-change binary first); the three that stay indexed each carry the one-line
// reason at the loop — the markdown grammar has no extras at all (mdWalk), and a string's children come
// from the external scanner, which owns every byte between the delimiters (stringLiteralText, the Elixir
// test-title scan). Two lessons from that round: a FLAT measurement proves the fixture missed the list,
// never that the loop is safe (leading comments belong to the PARENT, not the child that has not started;
// an uncaptured form never enters the walk); and a control can be quadratic in its own right when the walk
// under test runs on every ancestor of a def.
//
// WHY IT IS ITS OWN HEADER AND NOT A SECTION OF ingest.cpp. It was one, inside ingest_metrics.h's unnamed
// namespace, and that made it unreachable from the two headers that ALSO walk whole subtrees and are
// compiled outside that translation unit — src/preprocdead.h (shared with src/slice.h). The result was
// audit P1-0 (2026-09-10): `collectPreprocDeadRanges` kept the indexed form, and on a cold llvm-project
// run `ts_node_child_iterator_next` was 62.99% of busy leaves with that ONE walk's inclusive subtree at
// 56.67% of busy CPU. Converting it took that cold run from 202.14 s CPU to 170.46 s (wall 26.60 ->
// 18.99 s) with a byte-identical map. A rule that only some translation units can obey is a rule that
// gets broken, so the rule and the helper now live where every walk can reach them. Gates:
// test/padscalecheck.sh (the comment flood) and test/preprocdeadscalecheck.sh (the include-guard flood,
// which the `#if`-text gate in preprocdead.h hides from the first).
//
// WHICH WIDE NODES ACTUALLY COST O(C²) — MEASURED, 2026-09-10 (lane W2, test/childwalkscalecheck.sh). A
// FLAT child list does; a grammar REPEAT does not. tree-sitter stores a repetition as a balanced tree of
// invisible `_repeat` nodes, and `ts_node__child` skips a whole invisible subtree in O(1) by reading its
// stored `visible_child_count` (`ts_node__relevant_child_count`, node.c) — so indexing the 128 000th
// declaration of a file scope is ~O(log C), and a declaration flood measured dead linear on the
// pre-change binary (8k/64k/128k children = 0.04 / 0.33 / 0.63 s). What is NOT balanced is anything the
// parser splices into the child array itself: EXTRAS (comments, above all) and preprocessor-conditional
// bodies. A root of 16 000 COMMENTS measured 117× its own control on the same binary. The practical rule
// is therefore not "wide node" but "wide node whose width can come from EXTRAS", which — since a comment
// can appear between any two children of anything — is every walk whose node comes from the FILE. It is
// also why a scaling gate must flood with comments: a declaration flood of identical width goes green
// over a live defect.

#include <cstring>
#include <initializer_list>
#include <vector>

#include <tree_sitter/api.h>

namespace rw
{

struct ChildCursor   // RAII — several walkers return mid-loop, so deletion must not depend on fallthrough
{
    TSTreeCursor cur;
    explicit ChildCursor( TSNode n ) noexcept : cur( ts_tree_cursor_new( n ) ) {}
    ChildCursor( const ChildCursor& ) = delete;
    ChildCursor& operator=( const ChildCursor& ) = delete;
    ~ChildCursor() { ts_tree_cursor_delete( &cur ); }
};

// VISIT n's children, left to right, without materialising them — the one spelling of the cursor idiom
// every other function here is written on. `fn( TSNode ) -> bool` returns false to STOP, which is the
// `break` a filtering or searching walk needs and the `continue` case falls out of returning true.
//
// It takes the node AND the cursor because the two lifetimes differ: a walk that only filters can hand
// the same cursor to every node it visits, while a walk that RECURSES from inside `fn` cannot — the
// recursive call resets the cursor out from under the loop — and must own one per frame (`ChildCursor
// cursor( n ); forEachChild( n, cursor.cur, … )`). Making the cursor implicit would have hidden exactly
// that distinction, which is the bug this whole header exists to prevent.
template< class Fn >
inline void forEachChild( TSNode n, TSTreeCursor& cur, const Fn& fn )   // A4-F25: NOT noexcept — `fn` may allocate
{
    ts_tree_cursor_reset( &cur, n );
    if( ts_tree_cursor_goto_first_child( &cur ) )
    {
        do
        {
            if( !fn( ts_tree_cursor_current_node( &cur ) ) )
            {
                return;
            }
        }
        while( ts_tree_cursor_goto_next_sibling( &cur ) );
    }
}

// VISIT n's NAMED children, left to right — the cursor form of a `ts_node_named_child( n, i )` loop.
// That call is the SAME `ts_node__child` body with include_anonymous=false and the same restart from the
// first child, so an indexed named-child loop is O(C²) exactly like an all-children one; and a COMMENT is
// a NAMED extra, so the flood shape above reaches this class too. Measured on the pre-change binary,
// 2026-09-10: --slice's rung-3 flow walk over a 16 000-comment definition body was 87× the plain map of
// the same file (test/childwalkscalecheck.sh arm B8).
//
// WHY FILTERING forEachChild BY ts_node_is_named REPRODUCES ts_node_named_child EXACTLY. The cursor yields
// precisely the VISIBLE children — a visible subtree, or an invisible one carrying a visible alias — which
// is `ts_node__is_relevant( child, true )`; it never yields a hidden node, it descends through it. For
// those nodes `ts_node_is_named` (alias ? alias.named : subtree.named, node.c:505) and
// `ts_node__is_relevant( child, false )` (alias ? alias.named : visible && named, node.c:109) agree term
// for term, because `visible` is already true. And a named-but-INVISIBLE node — a hidden `_rule` — is
// skipped identically by both: the cursor descends through it, and ts_node__child counts through its
// stored named child count. Same set, same order.
template< class Fn >
inline void forEachNamedChild( TSNode n, TSTreeCursor& cur, const Fn& fn )   // A4-F25: NOT noexcept — `fn` may allocate
{
    forEachChild( n, cur, [ &fn ]( TSNode child ) { return ts_node_is_named( child ) ? fn( child ) : true; } );
}

// TRUE when `pred` holds for any node in n's child subtree — depth-first, left to right, stopping at the
// first hit, bounded at `maxDepth` levels below n (`maxDepth < 0` = unbounded). Two walks ask exactly this
// question in exactly this shape — slicev::SliceRdWalker::hasStructureBelow ("is there a block or control
// construct below?") and cc_declHasStructuredBinding ("is there a structured_binding_declarator within 4
// levels?") — and a second hand-written copy of the cursor-plus-recursion loop is the clone this header
// exists to prevent. `namedOnly` picks which child set: the named one (`ts_node_named_child`'s) or all.
template< class Pred >
inline bool anyChildBelow( TSNode n, int maxDepth, bool namedOnly, const Pred& pred )
{
    if( maxDepth == 0 )
    {
        return false;
    }
    ChildCursor cursor( n );   // this frame's own: the body recurses
    bool        found = false;
    forEachChild( n, cursor.cur, [ & ]( TSNode c )
    {
        if( ( namedOnly && !ts_node_is_named( c ) ) || ( !pred( c ) && !anyChildBelow( c, maxDepth - 1, namedOnly, pred ) ) )
        {
            return true;
        }
        found = true;
        return false;
    } );
    return found;
}

// FIRST child of n whose node type is one of `kinds` (named children only when `namedOnly`), or a null node
// when none is — the cursor form of the `for( i ) { if( strcmp( ts_node_type( ts_node_child( n, i ) ), K ) == 0 )
// return child; }` probe that lane W4 found spelled at six sites (a C# using directive's specifier, an Elixir
// call's `arguments` and `do_block`, an ObjC method's body, a linkage_specification's string, the C++
// using-declaration keyword). One spelling, so a converted probe cannot drift back into an indexed one.
inline TSNode firstChildOfKind( TSNode n, bool namedOnly, std::initializer_list<const char*> kinds )   // A4-F25: NOT noexcept — the cursor allocates
{
    TSNode      found = {};
    ChildCursor cursor( n );
    forEachChild( n, cursor.cur, [ & ]( TSNode child )
    {
        if( namedOnly && !ts_node_is_named( child ) )
        {
            return true;
        }
        const char* type = ts_node_type( child );
        for( const char* kind : kinds )
        {
            if( std::strcmp( type, kind ) == 0 )
            {
                found = child;
                return false;
            }
        }
        return true;
    } );
    return found;
}

// APPEND n's children, left to right, to whatever `out` already holds. This is the form a DFS-STACK walk
// needs: there the collected list IS the work list, so clearing it would throw the frontier away. Routing
// such a walk through collectChildren instead costs it a scratch vector plus a copy of every node; the two
// forms measured indistinguishably on this box (both inside a ±3% noise band that a same-binary control
// reproduced with the opposite sign), so this exists for the shape, not for a measured win.
inline void appendChildren( TSNode n, TSTreeCursor& cur, std::vector<TSNode>& out )   // A4-F25: NOT noexcept — `out` allocates
{
    forEachChild( n, cur, [ &out ]( TSNode child ) { out.push_back( child ); return true; } );
}

// REPLACE `out` with n's children — the form a walker uses when it wants one node's child list as a
// standalone array to scan or index. Delegates, so there is exactly one spelling of the cursor idiom.
inline void collectChildren( TSNode n, TSTreeCursor& cur, std::vector<TSNode>& out )   // A4-F25: NOT noexcept — `out` allocates
{
    out.clear();
    appendChildren( n, cur, out );
}

}   // namespace rw
