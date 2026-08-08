#pragma once

// cachelint.h — the CACHE-FRIENDLINESS lint pack, folded into the existing `--lint` machinery.
//
// Static, syntactic facts about memory-locality: the shapes practitioners agree hurt (Chilimbi PLDI
// 1999 and Drepper cover the layout half — that half already ships as `--field-affinity`; Agner Fog's
// optimization manual §9.6-9.10, Drepper's "What Every Programmer Should Know About Memory" §6, and
// the Game Programming Patterns "Data Locality" chapter cover the ACCESS-PATTERN half implemented
// here). Eight rules, each a single AST shape a tree-sitter pattern can decide:
//
//   cache-node-container    — a node-based std container type (map/list/set/…): one heap node per
//                             element, a dependent pointer chase per traversal step
//   cache-vector-of-raw-ptr — vector<T*>: contiguous handles, scattered payloads
//   cache-vector-of-indirect— vector<unique_ptr/shared_ptr/vector<…>>: an indirection per element;
//                             vector<vector<T>> is the "matrix as vector of vectors" anti-pattern
//   cache-heap-alloc-in-loop— new/malloc/calloc/realloc/strdup inside a loop body: per-iteration
//                             allocation scatters the loop's output across the heap
//   cache-pointer-chase-loop— `p = p->next` inside a loop: a serial dependent-load chain the
//                             prefetcher cannot predict (complements accessshape.h, which classifies
//                             C-style for-UPDATE clauses for --field-affinity; this fires on the
//                             assignment wherever it sits in a loop)
//   cache-gather-subscript  — a[b[i]] inside a loop: gather/scatter — random access by construction
//   cache-shared-ptr-by-value — a by-value shared_ptr parameter: atomic refcount traffic per call
//   cache-manual-prefetch   — an EXISTING _mm_prefetch/__builtin_prefetch call, flagged for
//                             re-measurement (2007-era wins are often a wash on current hardware) —
//                             found with high confidence, judged with none, and never suggested
//
// LENS, NOT VERDICT. Every row is a fact, not a defect claim: an intrusive list, a CSR gather, or a
// deliberate per-iteration arena refill is still the right code in the right hands — the reader
// judges. DELIBERATELY OUT OF SCOPE (each needs semantics no single AST shape gives soundly):
// loop-interchange/stride order (needs induction-variable-to-subscript-position binding), missing
// vector::reserve (needs "no reserve between declaration and loop" scope reasoning), loop-invariant
// branch hoisting (compilers unswitch provable invariants at -O3 — flagging them is noise), false
// sharing (the layout half's inverse; belongs beside --field-affinity's arithmetic), and anything
// "hot" — heat is a runtime property; pair these rows with --hotspots/churn, don't guess.
// Under-reporting is the house failure mode of choice.
//
// C-FAMILY ONLY, ENFORCED. `new_expression` in a JavaScript loop is idiomatic GC allocation, and
// several node kinds here are spelled identically across grammars — findings are filtered to files
// ingest routes through a C/C++/ObjC/CUDA grammar, exactly like the atoms pack.

#include "Diagnostics.h"
#include "atoms.h"        // isCFamilyPath — the same file-language fence the atoms pack enforces
#include "ingest.h"       // AstQuerySpec / AstMatch / astQuery — the SAME engine --lint and --match run
#include "lintrules.h"    // lintdetail::Span + containment predicates; kLintMaxPerRule

#include <algorithm>
#include <array>
#include <cstddef>
#include <cstdint>
#include <string>
#include <string_view>
#include <vector>

namespace rw::cachelint
{

// The pack's rule names, in the order the `--lint` tally prints them. main.cpp appends this run to
// its own allRuleNames, so declaration order here IS emission order — deterministic by construction.
inline constexpr std::array<std::string_view, 8> kCacheRuleNames = { {
    "cache-node-container",
    "cache-vector-of-raw-ptr",
    "cache-vector-of-indirect",
    "cache-heap-alloc-in-loop",
    "cache-pointer-chase-loop",
    "cache-gather-subscript",
    "cache-shared-ptr-by-value",
    "cache-manual-prefetch",
} };

// Three rules only count INSIDE a loop, and tree-sitter queries cannot express "an ancestor is a
// loop" — so loop regions come back as their own capture stream and the containment is span algebra
// here, exactly the atoms pack's exclusion mechanism inverted (keep-if-inside instead of
// drop-if-inside). The loop stream is load-bearing the harmless way around: a truncated stream can
// only UNDER-report (a hit inside an unrecorded loop is dropped), never invent a finding — but a
// floor is still disclosed if it saturates, because "none found" must never read as "none exists".
// The budget is far above kLintMaxPerRule for the same reason the atoms pack's is.
inline constexpr std::size_t kCacheQueryBudget = 100000;

// Internal tag for the loop-region stream — never emitted; stripped before findings leave the pack.
inline constexpr std::string_view kLoopRegionTag = "cache-loop-region";

struct CacheRun
{
    std::vector<AstMatch>    findings;        // tag = one of kCacheRuleNames
    std::vector<std::string> saturatedTags;   // rules whose count= is a FLOOR (budget spent)
};

namespace cachedetail
{

using lintdetail::Span;
using rw::atoms::spanOf;   // the AstMatch→Span bridge — one copy, owned by the atoms pack

// The pack's specs. Every pattern captures the WHOLE interesting node as its widest capture;
// auxiliary predicate captures (@f/@t/@l/@r/@i) are collapsed away below by containment, so one
// source site emits one row. Two specs sharing a tag share one budget (astQuery's own contract).
inline std::vector<AstQuerySpec> cacheSpecs()
{
    std::vector<AstQuerySpec> specs;
    const auto add = [ &specs ]( const char* query, std::string_view tag )
    { specs.push_back( { query, std::string( tag ) } ); };

    // Loop regions — the containment universe for the three in-loop rules.
    add( "[ (for_statement) (while_statement) (do_statement) (for_range_loop) ] @c", kLoopRegionTag );

    add( "(template_type name: (type_identifier) @c (#match? @c "
         "\"^(map|multimap|list|forward_list|set|multiset|unordered_map|unordered_set|unordered_multimap|unordered_multiset)$\"))",
         "cache-node-container" );

    add( "((template_type name: (type_identifier) @v (#eq? @v \"vector\") "
         "arguments: (template_argument_list (type_descriptor (abstract_pointer_declarator)))) @c)",
         "cache-vector-of-raw-ptr" );

    // vector<unique_ptr<T>> / vector<shared_ptr<T>> / vector<vector<T>> — inner spelling with and
    // without a namespace qualifier (post `using namespace std;`).
    add( "((template_type name: (type_identifier) @v (#eq? @v \"vector\") arguments: (template_argument_list "
         "(type_descriptor type: (qualified_identifier name: (template_type name: (type_identifier) @i "
         "(#match? @i \"^(unique_ptr|shared_ptr|vector)$\")))))) @c)",
         "cache-vector-of-indirect" );
    add( "((template_type name: (type_identifier) @v (#eq? @v \"vector\") arguments: (template_argument_list "
         "(type_descriptor type: (template_type name: (type_identifier) @i "
         "(#match? @i \"^(unique_ptr|shared_ptr|vector)$\"))))) @c)",
         "cache-vector-of-indirect" );

    add( "(new_expression) @c", "cache-heap-alloc-in-loop" );
    add( "((call_expression function: (identifier) @f (#match? @f \"^(malloc|calloc|realloc|strdup)$\")) @c)",
         "cache-heap-alloc-in-loop" );
    add( "((call_expression function: (qualified_identifier name: (identifier) @f "
         "(#match? @f \"^(malloc|calloc|realloc|strdup)$\"))) @c)",
         "cache-heap-alloc-in-loop" );

    add( "((assignment_expression left: (identifier) @l right: (field_expression argument: (identifier) @r) "
         "(#eq? @l @r)) @c)",
         "cache-pointer-chase-loop" );

    add( "(subscript_expression indices: (subscript_argument_list (subscript_expression))) @c",
         "cache-gather-subscript" );

    add( "((parameter_declaration type: (qualified_identifier name: (template_type name: (type_identifier) @t "
         "(#eq? @t \"shared_ptr\"))) declarator: (identifier)) @c)",
         "cache-shared-ptr-by-value" );
    add( "((parameter_declaration type: (template_type name: (type_identifier) @t (#eq? @t \"shared_ptr\")) "
         "declarator: (identifier)) @c)",
         "cache-shared-ptr-by-value" );

    add( "((call_expression function: (identifier) @f (#match? @f \"^(_mm_prefetch|__builtin_prefetch)$\")) @c)",
         "cache-manual-prefetch" );

    return specs;
}

// Which rules only count inside a loop region.
inline bool needsLoopContext( std::string_view tag ) noexcept
{
    return tag == "cache-heap-alloc-in-loop" || tag == "cache-pointer-chase-loop" || tag == "cache-gather-subscript";
}

// Loop-region spans, bucketed per file (indexed by fileId — no hash-container iteration order),
// each bucket sorted by startByte with a prefix-max of endByte so containment is one binary search
// per candidate instead of a linear scan (a saturated stream squared is the regex-bomb shape this
// subsystem already refuses elsewhere).
struct LoopIndex
{
    std::vector<std::vector<Span>>          loopsByFile;
    std::vector<std::vector<std::uint32_t>> prefixMaxEnd;
    std::size_t                             loopRows = 0;

    LoopIndex( const IngestResult& ing, const std::vector<AstMatch>& ms )
        : loopsByFile( ing.files.size() ), prefixMaxEnd( ing.files.size() )
    {
        for( const AstMatch& m : ms )
        {
            if( m.tag == kLoopRegionTag )
            {
                ++loopRows;
                if( m.fileId < loopsByFile.size() )
                {
                    loopsByFile[m.fileId].push_back( spanOf( m ) );
                }
            }
        }
        for( std::size_t fileIndex = 0; fileIndex < loopsByFile.size(); ++fileIndex )
        {
            std::vector<Span>& loops = loopsByFile[fileIndex];
            std::sort( loops.begin(), loops.end(), []( const Span& a, const Span& b )
                       { return a.startByte != b.startByte ? a.startByte < b.startByte : a.endByte > b.endByte; } );
            std::vector<std::uint32_t>& prefix = prefixMaxEnd[fileIndex];
            prefix.resize( loops.size() );
            std::uint32_t maxEnd = 0;
            for( std::size_t loopIndex = 0; loopIndex < loops.size(); ++loopIndex )
            {
                maxEnd = std::max( maxEnd, loops[loopIndex].endByte );
                prefix[loopIndex] = maxEnd;
            }
        }
    }

    // Rightmost loop whose startByte <= m.startByte; the prefix max tells whether ANY of those
    // reaches past m.endByte — and the loop achieving that max then contains m outright, so the
    // test is exact for arbitrary span sets, no nesting assumption needed.
    bool contains( const AstMatch& m ) const noexcept
    {
        if( m.fileId >= loopsByFile.size() )
        {
            return false;
        }
        const std::vector<Span>& loops = loopsByFile[m.fileId];
        std::size_t lo = 0, hi = loops.size();
        while( lo < hi )
        {
            const std::size_t mid = lo + ( hi - lo ) / 2;
            if( loops[mid].startByte <= m.startByte ) { lo = mid + 1; }
            else                                      { hi = mid; }
        }
        return lo > 0 && prefixMaxEnd[m.fileId][lo - 1] >= m.endByte;
    }
};

// Collapse auxiliary captures: a row STRICTLY contained by a wider row of the same tag in the same
// file is the inner predicate capture (@f/@t/@l/@r/@i, or a nested repeat) of the site the wider
// row already reports — one source site, one row. Exact-duplicate spans survive to
// dedupeLintFindings, which collapses on the visible row identity like every other built-in.
// Sweep per (tag, file) bucket in (startByte asc, endByte desc) order with a running max-end taken
// BEFORE each exact-span group: covered iff that max reaches the group's end.
inline std::vector<AstMatch> collapseAuxCaptures( std::vector<AstMatch> eligible )
{
    std::vector<std::size_t> order( eligible.size() );
    for( std::size_t i = 0; i < order.size(); ++i ) { order[i] = i; }
    std::sort( order.begin(), order.end(), [ &eligible ]( std::size_t a, std::size_t b )
    {
        const AstMatch& x = eligible[a];
        const AstMatch& y = eligible[b];
        if( x.tag != y.tag )             { return x.tag < y.tag; }
        if( x.fileId != y.fileId )       { return x.fileId < y.fileId; }
        if( x.startByte != y.startByte ) { return x.startByte < y.startByte; }
        return x.endByte > y.endByte;
    } );
    std::vector<char> covered( eligible.size(), 0 );
    for( std::size_t i = 0; i < order.size(); )
    {
        const AstMatch& bucketHead = eligible[order[i]];
        std::uint32_t maxEndBeforeGroup = 0;
        std::size_t   j                 = i;
        while( j < order.size() )
        {
            const AstMatch& row = eligible[order[j]];
            if( row.tag != bucketHead.tag || row.fileId != bucketHead.fileId )
            {
                break;
            }
            // The group of exact-span duplicates starting at j — judged against rows BEFORE the group.
            std::size_t groupEnd = j;
            while( groupEnd < order.size() )
            {
                const AstMatch& g = eligible[order[groupEnd]];
                if( g.tag != row.tag || g.fileId != row.fileId || g.startByte != row.startByte || g.endByte != row.endByte )
                {
                    break;
                }
                ++groupEnd;
            }
            if( maxEndBeforeGroup >= row.endByte )
            {
                for( std::size_t k = j; k < groupEnd; ++k ) { covered[order[k]] = 1; }
            }
            maxEndBeforeGroup = std::max( maxEndBeforeGroup, row.endByte );
            j = groupEnd;
        }
        i = j;
    }
    std::vector<AstMatch> kept;
    kept.reserve( eligible.size() );
    for( std::size_t i = 0; i < eligible.size(); ++i )
    {
        if( !covered[i] )
        {
            kept.push_back( std::move( eligible[i] ) );
        }
    }
    return kept;
}

}   // namespace cachedetail

// The pack's QUERY table, re-exported at pack level so `--lint` can hand it to the one grouped astQuery
// walk (astQueryGrouped, src/ingest.h) that also serves the built-in checks and the atoms pack, instead
// of this pack paying for a second read+parse of the whole corpus.
using cachedetail::cacheSpecs;

// `ms` is this pack's own captures, produced by the ONE grouped astQuery walk that also serves the
// built-in [AST] checks and the atoms pack (astQueryGrouped, src/ingest.h). The pack does not run its own
// pass: `--lint` is its only caller, and a second full read+parse of the corpus to ask this pack's
// questions of trees the same run already built was most of what made the verb slow.
inline CacheRun cacheFriendliness( const IngestResult& ing, std::size_t maxPerRule, std::vector<AstMatch> ms )
{
    using namespace cachedetail;

    CacheRun              run;

    // The language fence first: every downstream count is computed on C-family rows only.
    ms.erase( std::remove_if( ms.begin(), ms.end(), [ &ing ]( const AstMatch& m )
                              { return !rw::atoms::isCFamilyPath( ing.files[m.fileId] ); } ),
              ms.end() );

    // Loop containment universe, then the fence: the loop stream is stripped and the three in-loop
    // rules keep only rows a loop region contains.
    const LoopIndex loops( ing, ms );
    const bool loopStreamSaturated = loops.loopRows >= kCacheQueryBudget;
    std::vector<AstMatch> eligible;
    eligible.reserve( ms.size() );
    for( AstMatch& m : ms )
    {
        if( m.tag == kLoopRegionTag )
        {
            continue;
        }
        if( needsLoopContext( m.tag ) && !loops.contains( m ) )
        {
            continue;
        }
        eligible.push_back( std::move( m ) );
    }

    std::vector<AstMatch> kept = collapseAuxCaptures( std::move( eligible ) );

    // Per-rule truncation on the SAME scale every other built-in rule spends, so `capped="1"` reads
    // identically across the whole <lint> tally. astQuery's order is deterministic and the filters
    // above preserve it, so "the first maxPerRule" is a stable window.
    std::vector<std::size_t> emittedPerRule( kCacheRuleNames.size(), 0 );
    for( AstMatch& m : kept )
    {
        for( std::size_t ruleIndex = 0; ruleIndex < kCacheRuleNames.size(); ++ruleIndex )
        {
            if( m.tag != kCacheRuleNames[ruleIndex] )
            {
                continue;
            }
            if( emittedPerRule[ruleIndex] < maxPerRule )
            {
                ++emittedPerRule[ruleIndex];
                run.findings.push_back( std::move( m ) );
            }
            break;
        }
    }
    for( std::size_t ruleIndex = 0; ruleIndex < kCacheRuleNames.size(); ++ruleIndex )
    {
        const bool ruleSaturated = emittedPerRule[ruleIndex] >= maxPerRule;
        const bool loopBlind     = loopStreamSaturated && cachedetail::needsLoopContext( kCacheRuleNames[ruleIndex] );
        if( ruleSaturated || loopBlind )
        {
            run.saturatedTags.emplace_back( kCacheRuleNames[ruleIndex] );
        }
    }
    return run;
}

}   // namespace rw::cachelint
