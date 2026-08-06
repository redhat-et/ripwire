#pragma once

// atoms.h — the ATOMS OF CONFUSION lint pack, folded into the existing `--lint` machinery.
//
// Gopstein, Iannacone, Yan, DeLong, Zhuang, Yeh, Cappos — "Understanding Misunderstandings in
// Source Code", ESEC/FSE 2017 — isolated 15 C/C++ micro-patterns that measurably raise the rate at
// which a HUMAN mispredicts what a snippet does, each one small enough to be a single AST shape.
// The MSR 2018 follow-up found roughly one atom per 23 LOC in the wild and a correlation with
// bug-fix commits. Reference detector: github.com/dgopstein/atom-finder (Apache-2.0). This pack
// implements the seven that a tree-sitter pattern can decide from SHAPE alone:
//
//   atom-comma-operator     — the comma operator inside an expression (never a for-header comma)
//   atom-embedded-crement   — ++/-- evaluated inside a larger expression (never a whole statement)
//   atom-assign-as-value    — an assignment whose VALUE is consumed (a condition, an argument, ...)
//   atom-nested-ternary     — a conditional expression inside a conditional expression
//   atom-implicit-predicate — arithmetic (or a non-0/1 integer literal) used where a truth value is
//   atom-octal-literal      — a leading-zero integer literal: 0755 is 493, not 755
//   atom-reversed-subscript — `1[arr]`, legal C and almost never intended
//
// DELIBERATELY OUT OF SCOPE. The macro atoms (Preprocessor-in-Statement, Macro-Operator-Precedence)
// and the operator-precedence atoms need the preprocessor and a precedence model respectively, and
// both misfire on ordinary code; a lint rule that cries wolf is worse than a missing rule. Also out:
// `do { } while( expr )` conditions and the C++14 digit-separator spelling `0'777` — under-reporting
// is the house failure mode of choice (a zero means "none FOUND", never "none exists").
//
// LENS, NOT VERDICT. Every row is a fact about the source, not a defect claim: an atom in a hot loop
// written by someone who knew exactly what they were doing is still an atom, and the reader judges.
//
// C-FAMILY ONLY, ENFORCED. `update_expression`, `assignment_expression`, `subscript_expression` and
// `conditional_expression` are spelled identically in the JavaScript, Java, C# and Python grammars,
// so astQuery's "compile against every grammar it is valid for" would fire these patterns on files
// whose IDIOMS are completely different (`for( const x of xs )`, Python's `a if c else b`). Findings
// are therefore filtered to the extensions ingest routes through a C/C++/ObjC/CUDA grammar.

#include "Diagnostics.h"
#include "ingest.h"       // AstQuerySpec / AstMatch / astQuery — the SAME engine --lint and --match run
#include "lintrules.h"    // langOfPath — the house file-language predicate; kLintMaxPerRule
#include "model.h"

#include <algorithm>
#include <array>
#include <cstddef>
#include <cstdint>
#include <string>
#include <string_view>
#include <vector>

namespace rw::atoms
{

// The pack's rule names, in the order the `--lint` tally prints them. main.cpp appends this run to
// its own allRuleNames, so declaration order here IS emission order — deterministic by construction.
inline constexpr std::array<std::string_view, 7> kAtomRuleNames = { {
    "atom-comma-operator",
    "atom-embedded-crement",
    "atom-assign-as-value",
    "atom-nested-ternary",
    "atom-implicit-predicate",
    "atom-octal-literal",
    "atom-reversed-subscript",
} };

// Three of the seven are decided by SUBTRACTION — "every update_expression EXCEPT the ones that are a
// whole statement or sit in a for-header" — and tree-sitter queries cannot express negation, so the
// excluded sets come back as their own captures and are removed here by span algebra. That makes the
// exclusion sets load-bearing: a constraint capture stream truncated by the engine budget would turn
// into FALSE POSITIVES, which is the one failure mode this pack must not have. So the astQuery budget
// spent here is deliberately far above kLintMaxPerRule (ripwire's own src/ holds ~4.7k
// assignment_expressions against the 5000 default — no headroom at all), and a constraint that DOES
// saturate suppresses the rules that depend on it rather than emitting rows it can no longer trust.
// The surviving candidates are then truncated to the SAME per-rule budget every other built-in rule
// spends, so `capped="1"` means one thing across the whole `<lint>` tally.
//
// That separate budget is why the pack costs its own astQuery pass rather than riding the built-in
// checks' call: one shared maxMatches cannot be both 5000 (what every existing rule's `capped="1"`
// means) and large enough for the exclusion streams. MEASURED price on ripwire's own src/, warm:
// `--lint` 0.92s -> 1.07s wall. Paid only by `--lint`, never by the default map.
inline constexpr std::size_t kAtomsQueryBudget = 100000;

struct AtomsRun
{
    std::vector<AstMatch>    findings;        // tag = one of kAtomRuleNames; sorted (file, startByte, tag)
    std::vector<std::string> saturatedTags;   // rules whose count= is a FLOOR (budget spent, or exclusions untrusted)
};

namespace atomdetail
{

// Spans are lintrules.h's Span and lintrules.h's predicate — the SAME half-open [startByte, endByte)
// algebra the user-rule combinators run on, so there is one containment rule in the lint subsystem
// rather than two that can drift apart. (`group` and `line` go unused here; they cost nothing.)
using lintdetail::Span;

// How a recorded exclusion span has to relate to a candidate before it removes it.
//   Exact     — the SAME node: `i++;` IS the statement that makes the crement not an atom.
//   Cover     — the candidate sits anywhere INSIDE the recorded region, e.g. a whole for-header.
//   WiderThan — Cover, but a span identical to the candidate does NOT count: used to keep only the
//               outermost member of a nest, where the candidate set IS the recorded set.
enum class SpanRelation { Exact, Cover, WiderThan };

inline Span spanOf( const AstMatch& m ) noexcept
{
    return Span{ m.fileId, m.startByte, m.endByte, m.line, 0 };
}

// Per-file span buckets, indexed by fileId so a lookup never iterates a hash container (an iteration
// order that reached the output would be exactly the determinism bug the house rule forbids).
struct SpanIndex
{
    std::vector<std::vector<Span>> byFile;

    explicit SpanIndex( std::size_t fileCount ) : byFile( fileCount ) {}

    void add( const Span& s )
    {
        if( s.fileId < byFile.size() )
        {
            byFile[s.fileId].push_back( s );
        }
    }
    bool excludes( const Span& probe, SpanRelation relation ) const
    {
        if( probe.fileId >= byFile.size() )
        {
            return false;
        }
        for( const Span& recorded : byFile[probe.fileId] )
        {
            const bool identical = recorded.startByte == probe.startByte && recorded.endByte == probe.endByte;
            const bool covers    = lintdetail::coversOrEquals( recorded, probe );
            bool       hit       = covers;                      // SpanRelation::Cover
            if( relation == SpanRelation::Exact )
            {
                hit = identical;
            }
            else if( relation == SpanRelation::WiderThan )
            {
                hit = covers && !identical;
            }
            if( hit )
            {
                return true;
            }
        }
        return false;
    }
};

// The extensions ingest routes through a C/C++/ObjC/CUDA grammar. langOfPath covers C, C++ and ObjC;
// the three shader/CUDA extensions ride a C-family grammar in ingest.cpp's kLangTable but predate
// langOfPath's table, so they are named here rather than widening a predicate that other verbs
// (packDeps' dep_files= denominator, --health) read for a different question.
inline bool isCFamilyPath( std::string_view path ) noexcept
{
    const Lang lang = langOfPath( path );
    if( lang == Lang::C || lang == Lang::Cpp || lang == Lang::ObjC )
    {
        return true;
    }
    const std::size_t dot = path.rfind( '.' );
    if( dot == std::string_view::npos )
    {
        return false;
    }
    const std::string_view ext = path.substr( dot );
    return ext == ".cu" || ext == ".cuh" || ext == ".metal";
}

// Which symbol OWNS a byte offset — the INNERMOST definition whose [sigStartByte, endByte) contains
// it. Identical to the rule --lint's own `in=` attribute and its magic-number filter already use.
struct OwnerIndex
{
    std::vector<std::vector<NodeId>> byFile;   // symbol ids per file, ordered by sigStartByte

    explicit OwnerIndex( const IngestResult& ing ) : byFile( ing.files.size() )
    {
        for( std::size_t id = 0; id < ing.symbols.size(); ++id )
        {
            const std::uint32_t fileId = ing.symbols[id].fileId;
            if( fileId < byFile.size() )
            {
                byFile[fileId].push_back( static_cast<NodeId>( id ) );
            }
        }
        for( std::vector<NodeId>& ids : byFile )
        {
            std::sort( ids.begin(), ids.end(), [ & ]( NodeId a, NodeId b )
                       { return ing.symbols[a].sigStartByte < ing.symbols[b].sigStartByte; } );
        }
    }

    const Symbol* ownerOf( const IngestResult& ing, std::uint32_t fileId, std::uint32_t offset ) const
    {
        if( fileId >= byFile.size() )
        {
            return nullptr;
        }
        const Symbol* best = nullptr;
        for( const NodeId id : byFile[fileId] )
        {
            const Symbol& s = ing.symbols[id];
            if( s.sigStartByte > offset )
            {
                break;
            }
            if( offset < s.endByte && ( best == nullptr || s.sigStartByte > best->sigStartByte ) )
            {
                best = &s;
            }
        }
        return best;
    }
};

// Every atom in this pack except the octal literal is a claim about an expression being EVALUATED, so
// it belongs inside a function or method body. Requiring that is not just tidiness: tree-sitter's C++
// grammar resolves the declaration-vs-expression ambiguity WRONGLY for a pointer-to-member declarator
// carrying a default member initializer — `bool Config::* isSetFlag = nullptr;` in a struct body comes
// back as an assignment_expression, and every such field in this repo's own flag tables was reported
// as an assignment-used-as-a-value. An octal literal cannot be manufactured that way and is confusing
// wherever it is written, so it alone is exempt.
inline bool needsExecutableContext( std::string_view rule ) noexcept
{
    return rule != kAtomRuleNames[5];
}

inline bool isExecutableContext( const IngestResult& ing, const OwnerIndex& owners, const AstMatch& m )
{
    const Symbol* owner = owners.ownerOf( ing, m.fileId, m.startByte );
    return owner != nullptr && ( owner->kind == SymKind::Function || owner->kind == SymKind::Method );
}

// Is this literal's text an OCTAL integer literal? The query already narrowed to `^0[0-7]+`; this
// decides the tail, where the shapes that merely start that way live: `0755` yes, `0711L` yes (a
// suffix is still an octal literal), `0x1F` / `0.5` / `0e7` / `0L` / `0` / `099` all no. Anything
// after the octal digits that is not a length/sign suffix means the token is NOT an integer literal
// in base 8, and an unrecognised tail is a "do not fire" — never a guess.
inline bool isOctalLiteralText( std::string_view text ) noexcept
{
    if( text.size() < 2 || text[0] != '0' )
    {
        return false;
    }
    std::size_t index = 1;
    while( index < text.size() && text[index] >= '0' && text[index] <= '7' )
    {
        ++index;
    }
    if( index == 1 )
    {
        return false;   // `0x…` / `0.…` / `0L` / `0'…` — nothing base-8 followed the zero
    }
    for( std::size_t tail = index; tail < text.size(); ++tail )
    {
        const char c = text[tail];
        if( c != 'u' && c != 'U' && c != 'l' && c != 'L' )
        {
            return false;   // `099`, `0755.5`, `07e2` — not an octal integer literal
        }
    }
    return true;
}

// Tags for the EXCLUSION captures. The leading '!' can never collide with a rule name (built-in or
// user), and every one of these is erased before the run is returned — they are working state, not
// findings.
inline constexpr std::string_view kTagForHeader   = "!for-header";
inline constexpr std::string_view kTagStmtCrement = "!stmt-crement";
inline constexpr std::string_view kTagStmtAssign  = "!stmt-assign";
inline constexpr std::string_view kTagInnerComma  = "!inner-comma";

// The arithmetic operators that make a condition an implicit predicate. Bitwise `&` / `|` / `^` and
// the shifts are deliberately absent: `if( flags & kMask )` is the idiomatic C flag test, and firing
// on it would bury the real atoms under it. Comparisons and `&&` / `||` already yield a truth value.
inline constexpr std::string_view kArithOps = "[\"+\" \"-\" \"*\" \"/\" \"%\"]";

// One query per shape. Several specs share a tag on purpose (astQuery treats a tag as one rule with
// one budget): the C/ObjC grammars wrap an if/while condition in `parenthesized_expression` while
// the C++ grammar wraps it in `condition_clause`, so a position-anchored atom needs both node paths
// and neither can fire twice on the same node.
inline std::vector<AstQuerySpec> atomsSpecs()
{
    const std::string arith( kArithOps );
    const std::string predicateValue = "[ (binary_expression operator: " + arith + " ) (number_literal) ]";
    const std::string arithOnly      = "(binary_expression operator: " + arith + " )";

    std::vector<AstQuerySpec> specs;
    specs.reserve( 20 );

    // ── candidates ────────────────────────────────────────────────────────────────────────────────
    specs.push_back( { "(comma_expression) @c", std::string( kAtomRuleNames[0] ) } );
    specs.push_back( { "(update_expression) @c", std::string( kAtomRuleNames[1] ) } );
    specs.push_back( { "(assignment_expression) @c", std::string( kAtomRuleNames[2] ) } );

    // A ternary is only an atom once it CONTAINS another ternary; report the outer one, which is where
    // a reader's parse actually goes wrong. The second pattern is the parenthesised spelling, which is
    // a grandchild and so invisible to the first.
    specs.push_back( { "(conditional_expression (conditional_expression)) @c", std::string( kAtomRuleNames[3] ) } );
    specs.push_back( { "(conditional_expression (parenthesized_expression (conditional_expression))) @c", std::string( kAtomRuleNames[3] ) } );

    const std::string implicit( kAtomRuleNames[4] );
    specs.push_back( { "(if_statement condition: (parenthesized_expression " + predicateValue + " @c))", implicit } );          // C / ObjC
    specs.push_back( { "(if_statement condition: (condition_clause value: " + predicateValue + " @c))", implicit } );          // C++
    // A literal loop condition is the universal `while( 1 )` idiom, not an atom — loops take the
    // arithmetic shape only.
    specs.push_back( { "(while_statement condition: (parenthesized_expression " + arithOnly + " @c))", implicit } );
    specs.push_back( { "(while_statement condition: (condition_clause value: " + arithOnly + " @c))", implicit } );
    specs.push_back( { "(conditional_expression condition: " + predicateValue + " @c)", implicit } );

    // The regex narrows the capture stream to leading-zero shapes before it ever reaches memory;
    // isOctalLiteralText decides the tail.
    specs.push_back( { "((number_literal) @c (#match? @c \"^0[0-7]+\"))", std::string( kAtomRuleNames[5] ) } );
    specs.push_back( { "(subscript_expression argument: (number_literal)) @c", std::string( kAtomRuleNames[6] ) } );

    // ── exclusions ────────────────────────────────────────────────────────────────────────────────
    const std::string forHeader( kTagForHeader );
    specs.push_back( { "(for_statement initializer: (_) @x)", forHeader } );
    specs.push_back( { "(for_statement condition: (_) @x)", forHeader } );
    specs.push_back( { "(for_statement update: (_) @x)", forHeader } );
    specs.push_back( { "(expression_statement (update_expression) @x)", std::string( kTagStmtCrement ) } );
    specs.push_back( { "(expression_statement (assignment_expression) @x)", std::string( kTagStmtAssign ) } );
    specs.push_back( { "(comma_expression (comma_expression) @x)", std::string( kTagInnerComma ) } );
    return specs;
}

// The exclusion sets, bucketed per file, plus which of them the engine budget left INCOMPLETE. An
// incomplete exclusion set can only produce false positives, so the rules that read it are dropped
// wholesale — under-reporting is recoverable, a wrong finding is not.
struct Exclusions
{
    SpanIndex forHeader;
    SpanIndex stmtCrement;
    SpanIndex stmtAssign;
    SpanIndex innerComma;
    bool      forHeaderPartial   = false;
    bool      stmtCrementPartial = false;
    bool      stmtAssignPartial  = false;
    bool      innerCommaPartial  = false;

    explicit Exclusions( std::size_t fileCount )
        : forHeader( fileCount ), stmtCrement( fileCount ), stmtAssign( fileCount ), innerComma( fileCount )
    {
    }

    // Is this rule's evidence untrustworthy this run? Only the three subtraction-decided rules can be.
    bool suppresses( std::string_view rule ) const noexcept
    {
        if( rule == kAtomRuleNames[0] ) { return innerCommaPartial  || forHeaderPartial; }
        if( rule == kAtomRuleNames[1] ) { return stmtCrementPartial || forHeaderPartial; }
        if( rule == kAtomRuleNames[2] ) { return stmtAssignPartial  || forHeaderPartial; }
        return false;
    }
};

inline Exclusions collectExclusions( const IngestResult& ing, const std::vector<AstMatch>& ms, std::size_t budget )
{
    Exclusions ex( ing.files.size() );
    std::size_t forHeaderRaw = 0, stmtCrementRaw = 0, stmtAssignRaw = 0, innerCommaRaw = 0;
    for( const AstMatch& m : ms )
    {
        const Span span = spanOf( m );
        if( m.tag == kTagForHeader )        { ex.forHeader.add( span );   ++forHeaderRaw; }
        else if( m.tag == kTagStmtCrement ) { ex.stmtCrement.add( span ); ++stmtCrementRaw; }
        else if( m.tag == kTagStmtAssign )  { ex.stmtAssign.add( span );  ++stmtAssignRaw; }
        else if( m.tag == kTagInnerComma )  { ex.innerComma.add( span );  ++innerCommaRaw; }
    }
    ex.forHeaderPartial   = forHeaderRaw   >= budget;
    ex.stmtCrementPartial = stmtCrementRaw >= budget;
    ex.stmtAssignPartial  = stmtAssignRaw  >= budget;
    ex.innerCommaPartial  = innerCommaRaw  >= budget;
    if( ex.forHeaderPartial || ex.stmtCrementPartial || ex.stmtAssignPartial || ex.innerCommaPartial )
    {
        DEGRADED_PATH_ALERT( "atoms: an exclusion capture stream spent its whole budget; the rules reading it are suppressed this run" );
    }
    return ex;
}

// Drop every candidate its own rule excludes, preserving astQuery's order (which is already total).
inline std::vector<AstMatch> applyExclusions( const IngestResult& ing, std::vector<AstMatch>& ms, const Exclusions& ex )
{
    const OwnerIndex      owners( ing );
    std::vector<AstMatch> kept;
    kept.reserve( ms.size() );
    for( AstMatch& m : ms )
    {
        if( m.tag.empty() || m.tag[0] == '!' )
        {
            continue;   // an exclusion capture is working state, never a finding
        }
        if( ex.suppresses( m.tag ) )
        {
            continue;
        }
        if( !isCFamilyPath( ing.files[m.fileId] ) )
        {
            continue;   // the same node type names exist in grammars whose idioms are different
        }
        if( needsExecutableContext( m.tag ) && !isExecutableContext( ing, owners, m ) )
        {
            continue;   // not inside a function body ⇒ not an expression this reader evaluates
        }
        const Span span = spanOf( m );
        if( m.tag == kAtomRuleNames[0] )
        {   // report the OUTERMOST comma of a chain; a for-header comma is idiom, not confusion
            if( ex.innerComma.excludes( span, SpanRelation::Exact ) || ex.forHeader.excludes( span, SpanRelation::Cover ) )
            {
                continue;
            }
        }
        else if( m.tag == kAtomRuleNames[1] )
        {   // a whole statement `i++;` evaluates nothing else — the atom is the EMBEDDED use
            if( ex.stmtCrement.excludes( span, SpanRelation::Exact ) || ex.forHeader.excludes( span, SpanRelation::Cover ) )
            {
                continue;
            }
        }
        else if( m.tag == kAtomRuleNames[2] )
        {   // `x = y;` is a statement; the atom is an assignment whose VALUE is consumed
            if( ex.stmtAssign.excludes( span, SpanRelation::Exact ) || ex.forHeader.excludes( span, SpanRelation::Cover ) )
            {
                continue;
            }
        }
        else if( m.tag == kAtomRuleNames[4] && ( m.text == "0" || m.text == "1" ) )
        {   // `if( 0 )` disables a block and `while( 1 )` loops forever — universal idioms every C
            // reader parses correctly, so firing on them would bury the arithmetic predicates that
            // actually mislead. The loop patterns already refuse literals outright; this covers
            // if/ternary, where a literal that is NOT 0 or 1 is still worth a row.
            continue;
        }
        else if( m.tag == kAtomRuleNames[5] && !isOctalLiteralText( m.text ) )
        {
            continue;
        }
        kept.push_back( std::move( m ) );
    }
    return kept;
}

// One nest, one row. The two nested-ternary patterns can capture the SAME node (an outer ternary with
// one bare and one parenthesised inner ternary satisfies both), and `a ? b : c ? d : e ? f : g` makes
// both the outer and the middle ternary a match for what a reader sees as one confusing chain. Keep
// the first occurrence of each span, and only the widest span of any nest.
inline std::vector<AstMatch> collapseNestedTernaries( const IngestResult& ing, std::vector<AstMatch>& kept )
{
    SpanIndex everyNest( ing.files.size() );
    for( const AstMatch& m : kept )
    {
        if( m.tag == kAtomRuleNames[3] )
        {
            everyNest.add( spanOf( m ) );
        }
    }

    SpanIndex             alreadyEmitted( ing.files.size() );
    std::vector<AstMatch> out;
    out.reserve( kept.size() );
    for( AstMatch& m : kept )
    {
        if( m.tag != kAtomRuleNames[3] )
        {
            out.push_back( std::move( m ) );
            continue;
        }
        const Span mine = spanOf( m );
        if( alreadyEmitted.excludes( mine, SpanRelation::Exact )        // the same node, via the other pattern
         || everyNest.excludes( mine, SpanRelation::WiderThan ) )       // an enclosing ternary already reports this nest
        {
            continue;
        }
        alreadyEmitted.add( mine );
        out.push_back( std::move( m ) );
    }
    return out;
}

}   // namespace atomdetail

// The pack's LANGUAGE precondition, re-exported at pack level so a caller can ask the COVERAGE question
// — "could this pack evaluate anything in this corpus at all?" — by calling the SAME predicate the pack
// gates on, never a second copy of the extension list. src/ensemble.h's availability precondition reads
// it: a corpus with no path this returns true for is one the atom rules were never run on, and that
// silence is not a fact about the code. Deliberately NOT layout::isCFamilyPath, which answers a
// different question (byte layout) over a different extension set.
using atomdetail::isCFamilyPath;

// Run the pack. One astQuery pass over the already-crawled files; everything after it is span algebra
// and text tests over the captures. Deterministic: astQuery returns (file path, startByte, endByte,
// tag) order and every filter below is order-preserving, so no hash iteration, thread arrival order,
// or wall clock can reach a row.
inline AtomsRun atomsOfConfusion( const IngestResult& ing, std::size_t maxPerRule )
{
    using namespace atomdetail;

    AtomsRun              run;
    std::vector<AstMatch> ms   = astQuery( ing, atomsSpecs(), kAtomsQueryBudget );
    const Exclusions      ex   = collectExclusions( ing, ms, kAtomsQueryBudget );
    std::vector<AstMatch> kept = applyExclusions( ing, ms, ex );
    std::vector<AstMatch> rows = collapseNestedTernaries( ing, kept );

    // Per-rule truncation on the SAME scale every other built-in rule spends, so `capped="1"` reads
    // identically across the whole <lint> tally. `rows` is already in a total order, so "the first
    // maxPerRule" is a stable window rather than an arbitrary one. A rule the engine budget or an
    // incomplete exclusion set left untrustworthy is declared a floor too — its count is then 0, and
    // 0 is an honest floor here: "none this run can stand behind", never "none exist".
    std::vector<std::size_t> emittedPerRule( kAtomRuleNames.size(), 0 );
    for( AstMatch& m : rows )
    {
        for( std::size_t ruleIndex = 0; ruleIndex < kAtomRuleNames.size(); ++ruleIndex )
        {
            if( m.tag != kAtomRuleNames[ruleIndex] )
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
    for( std::size_t ruleIndex = 0; ruleIndex < kAtomRuleNames.size(); ++ruleIndex )
    {
        if( emittedPerRule[ruleIndex] >= maxPerRule || ex.suppresses( kAtomRuleNames[ruleIndex] ) )
        {
            run.saturatedTags.emplace_back( kAtomRuleNames[ruleIndex] );
        }
    }
    return run;
}

}   // namespace rw::atoms
