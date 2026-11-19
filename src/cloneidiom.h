#pragma once

// cloneidiom.h — IDIOM-CLASS DEMOTION for clone findings.
//
// THE FALSE POSITIVE THIS EXISTS FOR. In a real ObjC++/C++ tree a four-branch float threshold ladder
// (`altitudeBandOf`) clone-grouped with a length bucketer, a height tierer, a difficulty band and a
// giant-assembly motion picker: five cross-domain functions, 44-56 normalized tokens each, sharing only
// the BUCKETING-LADDER IDIOM and not one domain identifier. The token streams really were near-identical;
// what the detector could not say is that they are near-identical because the LANGUAGE has one way to
// spell "bucket a scalar", not because anybody copied anybody. Every one of the five needed a reasoned
// ack, twice.
//
// WHAT THIS ADDS. A CLOSED set of five recognized idioms — and closed means closed; each one past the
// first three is a decision, not a patch:
//     threshold-ladder    a chain of `if( x < C ) return K` and nothing else
//     switch-name-table   a `switch` whose every arm is a label plus a literal return
//     builder-chain       a param-struct initializer chain: declare, assign every field, return
//     one-statement       the body is ONE `return <expr>;` (leading contract asserts aside) — DECISION C3
//     call-sequence       the body is a straight run of call statements and nothing else — QD-FALSE-ROWS-E0
// A clone group whose members ALL classify to the SAME idiom is annotated with that idiom's name. It is
// additionally DEMOTED — reported, but no longer gating — only when the whole conjunction holds:
//     (1) every member classifies to the same recognized idiom, AND
//     (2) no two members share a single non-keyword identifier (no domain vocabulary in common), AND
//     (3) no two members share an enclosing context (file + scope) — copy-paste next door is copy-paste, AND
//     (4) the group is below kIdiomCloneTokenFloor normalized tokens.
// Break any one and the group keeps gating. Two ladders over the same enum ARE a copy; two ladders in one
// namespace ARE a copy; a 200-token ladder is a table that wants to be data whatever it is spelled over.
//
// THE FOURTH IDIOM, one-statement (decision C3 of the great-engineer design log, 2026-11-12: "one-statement
// clone pairs with no shared vocabulary are minor"). Two one-line predicates such as
//     return a.path != b.path ? a.path < b.path : a.line < b.line;
//     return a.first != b.first ? a.first < b.first : sortutil::svLess( a.second, b.second );
// normalize to near-identical token streams because C++ has one way to spell "compare two keys", and the
// literal identifier test of condition (2) never refused them: their only common words are the parameter
// names `a` and `b`. So for THIS idiom only, condition (2) reads a NARROWER identifier set, which leaves out
//   (a) the member's own parameter names (read off its signature: the last identifier of each parameter in
//       the C family, the first in the name-first languages, kIdiomNameFirstLangMask);
//   (b) every name in a `std::`-qualified chain (`std::ranges::any_of`, `std::string_view::npos`);
//   (c) the fixed stop list kIdiomOneStatementStopWords — standard container and string vocabulary.
// Everything else stays in: member names after `.`/`->` (`scope`, `name`, `m_inClass`), even one spelled like a
// parameter, named constants
// (`kMinBytesPerToken`), in-repo callees, lambda parameters, and the arguments of a contract assert.
// Conditions (3) and (4) are unchanged and there is no new floor. One extra refusal holds for this idiom:
// a pair whose two bodies are token-identical once each member's parameters are renamed by position (a
// Type-1 copy after alpha-renaming) never demotes, whatever its vocabulary — a one-line copy that renamed
// only its parameters is still a copy. That clause is what keeps two `return s.scope.empty() ? …` copies
// gating even if they had no member name in common.
// A signature the parameter reader cannot parse yields no parameter names: more identifiers stay in, which
// is the safe side of condition (2), but the alpha-rename refusal then cannot see a parameter-only rename,
// so the reader finds the list after a generic signature's type parameters as well (idiomParamListOpen).
//
// THE FIFTH IDIOM, call-sequence (QD-FALSE-ROWS-E0, 2026-11-19). A two-line helper promoted for reuse,
//     std::sort( values.begin(), values.end(), less );  values.erase( std::unique( … ), values.end() );
// gated as a NEW duplicate of a stream writer it has nothing to do with,
//     o.u64( rowCount );  o.vec( chunkAt );  o.u64( bytes.size() );  o.put( bytes.data(), bytes.size() );
// at 51 tokens and 0.80 similarity, and again of a bench wrapper (`scratch.resize( … ); radix::sortKeySmall( … );`):
// normalized, every body that only calls things is `$I . $I ( … ) ;` repeated, so any two short ones collide. Here
// the CALLEES are the whole meaning of the body, and two such bodies that call nothing in common are not one
// body twice. The shape: every top-level statement is ONE call expression — a name, reached through `.`, `->`
// or `::`, called (and possibly called again on its result) — ending in `;`; its arguments may hold anything
// bracketed, a lambda included. No `return`, no declaration (two adjacent names), no assignment, no keyword, no
// subscript or template argument at the top level. Condition (2) reads the SAME narrowed identifier set as
// one-statement (parameters, `std::` chains and the container stop words left out), and the same alpha-rename
// refusal holds: a call run that differs from another only in its parameter names is a copy. Shared callees
// (`u64`, `erase`, an in-repo helper) and shared members stay in the set, so a real copy of a call run, which
// keeps its callees, still gates; (3) and (4) are unchanged. A run that calls a reused helper is not a clone of
// that helper, and this is the shape in which that reads as one.
//
// THE OPERAND PATH (QD-IDIOM-ELEMTYPE, 2026-11-19), --quality-delta only. A port of a 700-line shell matcher needed
// 13 reasoned acks for short loops and one-liners that matched unrelated code by SHAPE alone: an svLess binary search
// over a runtime std::vector<std::string> beside one over a constexpr span of string_view tables (the same body once
// the parameters are renamed, so the alpha refusal above kept it gating); a quote strip beside a whitespace squeeze
// (one copy-filter loop over a different character class); `trim( s ) == "true" || … == ":"` beside an extension
// test; a bounded peek beside another parser's bounded peek; a ' ; ' join of computed texts beside a comma join of a
// string vector. None of them is a recognized idiom, or the vocabulary test refused it on a shared std-adjacent
// word. What they share is that the members operate on DIFFERENT DATA, and that is checkable without a parse tree.
// A group the idiom conjunction did not demote is reported minor (why= names which difference held) when:
//     (4') it is under the same kIdiomCloneTokenFloor ceiling, AND
//     (3') no two members share an enclosing context (file + scope), AND
//     (5) every pair has a PROVED operand difference, one of
//         literals — the two bodies' literal sets (numbers, strings, characters, true/false/nullptr/None …; 0 and 1
//                    left out as the index arithmetic every loop spells) have nothing in common, are not both
//                    empty, and not BOTH bodies pass a literal straight to a call (`rfind( '/' )` beside
//                    `rfind( "::" )` is one cut with the separator as a parameter — the afterLast family dupshortcheck
//                    pins); or
//         types    — both signatures have the same number of parameters (one or more), every one spelling a
//                    concrete type (no template header, no type-parameter group, no auto/impl, no untyped
//                    parameter), and some position's type differs once the pass-by spelling (const, &, &&, mut)
//                    and qualifiers (std::, rw::) are dropped, AND
//     (6) when every member spells the SAME recognized idiom (the vocabulary test above refused it), no pair calls the
//         same helper (`includeLangOf(` — dupshortcheck's isCQuoteRootProbe | isBareTsSpecifier) and no pair shares a
//         VALUE identifier — one of the idiom's identifiers used other than as a call or a qualifier (`ns::`),
//         parameters and members left out — unless the index names it a function (a comparator passed by value:
//         svLess). A shared constant (kOrderSlack) or a shared enum (Grade::Poor …) is the same domain data with a
//         tuned number or type around it: a copy, and it keeps gating (cloneidiomcheck I and O pin both).
// What still gates: a copy that kept any literal (writeTangleLines | writeHexPairLines share ' ' and '\n'), a copy
// over the same literals (two reverse find-by-key loops, both spelling only 0 and 1 — JsonNode::get | steer_find), a
// generic helper beside a concrete caller, any pair in one scope, and anything at or over 80 tokens. What it cannot
// see: a type ALIAS reads as a different type (NodeId vs std::uint32_t), and a named constant is not a literal, so
// two bodies that differ only in which named constant they test prove nothing here. The rows still print — the
// house rule is demotion, never deletion — and the --clones verb, which reports groups rather than changes, does
// not read this verdict at all.
//
// ON (4), AND WHY IT IS A CEILING RATHER THAN A DROP. The design note that prompted this asked for a
// "higher token floor (e.g. 2x the normal one) before it can group at all". Implemented literally that
// DELETES rows — a 47-token ladder pair would simply stop being reported — and the house rule is demotion,
// never deletion: a finding that stops gating must still print, or the detector gets quieter instead of
// getting better. So the raised floor is spelled as the ceiling on DEMOTION: below it a recognized idiom
// with no shared vocabulary is idiom noise, at or above it the sheer size makes it a real duplicate again.
// The value is 2x the 40-token floor the clones verb defaults to, so it reads the same on both verbs (the
// quality-delta duplication kind runs the same detector at a lower floor of its own).
//
// WHAT THE CLASSIFIER CANNOT SEE, stated here because the emitted legends say it too:
//   * It reads the body's TOKEN shape, not a parse tree. A body assembled by macros, or one whose ladder
//     hides inside a preprocessor branch, classifies as whatever the raw tokens spell.
//   * The `switch` arm is `case`-labelled languages only; a Rust/Swift `match` expression is not modelled.
//   * `builder-chain` covers the param-STRUCT spelling (`p.field = v;` repeated). The fluent
//     `Builder().withX().withY().build()` spelling is deliberately NOT modelled — it is one statement with
//     call parens in it, which every classifier here refuses on purpose.
//   * `call-sequence` needs braces and a `;` after every statement: a Go or Python body (no `;`) and a Rust
//     macro call (`name!( … )`) are not modelled.
//   * `one-statement` needs a literal `return`: a Rust/Kotlin expression body (`{ a == b }`, `= a == b`) is
//     not modelled, and a Python body is read as the same token stream (a leading `:` refuses).
//   * Condition (2) is literal token equality, so ONE coincidental word in common (two unrelated enums that
//     both spell a `Mid` member) is enough to refuse the demotion. That direction is chosen: refusing to
//     demote costs a reasoned ack, demoting a real copy costs a missed duplicate.
//
// DETERMINISM. Every function here is a pure function of a body's bytes plus the symbol's own file/scope
// strings. No hash-map iteration, no traversal-order dependence, no wall clock. The group verdicts are
// produced in the caller's group order.

#include "arch.h"      // rw::fnv1a64 — THE whole-string FNV-1a; the identifier set is keyed with it, never a second copy of it
#include "clones.h"    // scanCodeTokens / CodeTokenKind — THE one code scanner; this is a second projection of it
#include "infra/sortutil.h"  // sortutil::sortUnique — the one sorted-unique step
#include "docparse.h"  // docparse::detail::readWholeFile — the canonical whole-file byte read (never re-rolled)
#include "model.h"

#include <algorithm>
#include <cstdint>
#include <iterator>
#include <ranges>
#include <string>
#include <string_view>
#include <vector>

namespace rw
{

// The closed set. Row order IS the enum's declaration order and the static_assert is what makes reordering
// the enum a compile error rather than a silent re-labelling of every emitted row.
enum class CloneIdiom : std::uint8_t { None = 0, ThresholdLadder = 1, SwitchNameTable = 2, BuilderChain = 3, OneStatement = 4, CallSequence = 5 };

inline constexpr std::string_view kCloneIdiomNames[] = { "", "threshold-ladder", "switch-name-table", "builder-chain", "one-statement", "call-sequence" };
static_assert( std::size( kCloneIdiomNames ) == std::size_t( CloneIdiom::CallSequence ) + 1,
               "kCloneIdiomNames must carry exactly one row per CloneIdiom, in declaration order" );

inline std::string_view cloneIdiomName( CloneIdiom k ) noexcept { return kCloneIdiomNames[ std::size_t( k ) ]; }

// The idioms whose condition (2) reads the NARROWED identifier set and carries the alpha-rename refusal (see the
// header): the short shapes whose only common words are often parameter names and standard-library vocabulary.
// A bit per idiom, the shape CONTRIBUTING.md asks of an "is this one of N constants" test (clones.h's langBit).
inline constexpr std::uint32_t kIdiomNarrowVocabularyMask = ( 1u << std::uint32_t( CloneIdiom::OneStatement ) ) | ( 1u << std::uint32_t( CloneIdiom::CallSequence ) );
inline constexpr bool idiomReadsNarrowVocabulary( CloneIdiom k ) noexcept { return ( ( kIdiomNarrowVocabularyMask >> std::uint32_t( k ) ) & 1u ) != 0; }

// The demotion CEILING — see the "ON (4)" note above. 2x the 40-token default floor of the clones verb.
constexpr std::uint32_t kIdiomCloneTokenFloor = 80;

// Shape bounds. Each is a deliberate tightness knob, not a tuning surface: every one of them makes the
// classifier say NO more often, which is the safe direction for a rule that removes a gate.
constexpr std::size_t kIdiomMaxReturnTokens   = 6;   // `return Enum::Member ;` is 3; a call or an expression is not a table return
constexpr std::size_t kIdiomMaxCondTokens     = 8;   // `( a.b < Limit::Hi )` is 7; anything longer is not a scalar threshold
constexpr std::size_t kIdiomMaxLabelTokens    = 6;   // `case Enum::Member :`
constexpr std::size_t kIdiomMinLadderBranches = 2;   // 2 is the floor the field evidence needs: two of the five ladders that prompted this (a 2-branch length bucketer, a 2-branch direction picker) have exactly two
constexpr std::size_t kIdiomMinTableCases     = 2;
constexpr std::size_t kIdiomMinBuilderFields  = 3;

// ── the token view the classifiers read ───────────────────────────────────────────────────────────────
// A VERBATIM slice plus its kind, from the same scanCodeTokens loop --clones normalizes and --readability
// keeps. This projection runs with maximal munch ON (`<=`, `->`, `::`, `&&` arrive as ONE token), which is
// what lets the grammars below be this short. That flag is a PARAMETER of the scanner precisely so this
// choice cannot reach --clones' own normalized streams: this is a separate scan over the same bytes, run
// only for symbols that already landed in a group.
struct IdiomTok
{
    std::string_view text;
    CodeTokenKind    kind = CodeTokenKind::Punctuation;
};

// The two operator vocabularies, as TABLES rather than `==` chains — the shape CONTRIBUTING.md asks for, and
// the shape that keeps "is this one of N constants" from being re-derived as yet another disjunction (the
// duplication kind names every new copy of that; clones.h says so beside langBit for the same reason).
inline constexpr std::string_view kIdiomRelOps[] = { "<", ">", "<=", ">=", "==", "!=" };
// Anything that turns a scalar threshold into a compound predicate. A ladder whose arms carry `&&` is still
// a ladder to a human, but it is no longer the shape whose collisions this rule exists to explain away.
inline constexpr std::string_view kIdiomCompoundOps[] = { "&&", "||", "?", "!", "and", "or", "not" };

// ── the three grammars ────────────────────────────────────────────────────────────────────────────────
// Each is a linear scan with one cursor. They return true and ADVANCE on a match, false on anything else;
// the classifier bodies are then a `while` over a handful of statement forms with `return None` as the
// catch-all, which is what keeps them from drifting into "accepts most code".

// `return <=kIdiomMaxReturnTokens tokens> ;` — with no call parens and no braced init in the value.
inline bool idiomEatReturn( const std::vector<IdiomTok>& t, std::size_t& i )
{
    if( i >= t.size() || t[i].text != "return" )
    {
        return false;
    }
    ++i;
    std::size_t taken = 0;
    while( i < t.size() && t[i].text != ";" && t[i].text != "}" )
    {
        if( t[i].text == "(" || t[i].text == "{" )
        {
            return false;   // a call or an aggregate init is not a table's return value
        }
        ++i;
        ++taken;
        if( taken > kIdiomMaxReturnTokens )
        {
            return false;
        }
    }
    if( i < t.size() && t[i].text == ";" )
    {
        ++i;
    }
    return taken >= 1;   // a bare `return;` carries no bucket
}

// `( <simple> <relop> <simple> )` — exactly one relational operator, no nesting, no compound predicate.
inline bool idiomEatThresholdCond( const std::vector<IdiomTok>& t, std::size_t& i )
{
    if( i >= t.size() || t[i].text != "(" )
    {
        return false;
    }
    ++i;
    std::size_t relops = 0, taken = 0;
    while( i < t.size() && t[i].text != ")" )
    {
        // The two membership tests are spelled INLINE rather than wrapped in a predicate each: a one-line
        // std::find wrapper is the single most duplicated body shape in this tree (rw::isOneOf,
        // notes' sortNotes, three more), and --quality-delta named this file as the next copy of it the
        // moment the wrapper existed. Two uses do not need a symbol.
        const std::string_view w = t[i].text;
        if( w == "(" || std::find( std::begin( kIdiomCompoundOps ), std::end( kIdiomCompoundOps ), w ) != std::end( kIdiomCompoundOps ) )
        {
            return false;
        }
        if( std::find( std::begin( kIdiomRelOps ), std::end( kIdiomRelOps ), w ) != std::end( kIdiomRelOps ) )
        {
            ++relops;
        }
        ++i;
        ++taken;
        if( taken > kIdiomMaxCondTokens )
        {
            return false;
        }
    }
    if( i >= t.size() )
    {
        return false;
    }
    ++i;   // the ')'
    return relops == 1 && taken >= 3;
}

// idiom 1 — the scalar threshold ladder. The body is if-conditions and returns and NOTHING ELSE: no local,
// no call, no loop, no assignment. That is the whole grammar, and its narrowness is the point.
inline CloneIdiom classifyThresholdLadder( const std::vector<IdiomTok>& t )
{
    std::size_t i = 0, branches = 0, returns = 0;
    while( i < t.size() )
    {
        const std::string_view w = t[i].text;
        if( w == "{" || w == "}" || w == "else" )
        {
            ++i;
            continue;
        }
        if( w == "if" )
        {
            ++i;
            if( !idiomEatThresholdCond( t, i ) )
            {
                return CloneIdiom::None;
            }
            ++branches;
            continue;
        }
        if( w == "return" )
        {
            if( !idiomEatReturn( t, i ) )
            {
                return CloneIdiom::None;
            }
            ++returns;
            continue;
        }
        return CloneIdiom::None;
    }
    // one return per branch at least: a ladder arm that does not return is a statement this grammar did not
    // model, and the count is the cheapest way to say so.
    return ( branches >= kIdiomMinLadderBranches && returns >= branches ) ? CloneIdiom::ThresholdLadder : CloneIdiom::None;
}

// `case <=kIdiomMaxLabelTokens tokens> :` / `default :`. `::` is one munched token, so the label's own
// terminator is unambiguous.
inline bool idiomEatCaseLabel( const std::vector<IdiomTok>& t, std::size_t& i )
{
    if( i >= t.size() )
    {
        return false;
    }
    if( t[i].text == "default" )
    {
        ++i;
        if( i < t.size() && t[i].text == ":" )
        {
            ++i;
        }
        return true;
    }
    if( t[i].text != "case" )
    {
        return false;
    }
    ++i;
    std::size_t taken = 0;
    while( i < t.size() && t[i].text != ":" )
    {
        if( t[i].text == "(" || t[i].text == "{" || t[i].text == ";" )
        {
            return false;
        }
        ++i;
        ++taken;
        if( taken > kIdiomMaxLabelTokens )
        {
            return false;
        }
    }
    if( i >= t.size() )
    {
        return false;
    }
    ++i;   // the ':'
    return taken >= 1;
}

// idiom 2 — the enum-to-string switch name table: one switch, >= kIdiomMinTableCases labelled arms, every
// arm a return or a break, optionally one trailing return after the switch. `case`-labelled languages only.
inline CloneIdiom classifySwitchNameTable( const std::vector<IdiomTok>& t )
{
    std::size_t i = 0;
    while( i < t.size() && t[i].text == "{" )
    {
        ++i;
    }
    if( i >= t.size() || t[i].text != "switch" )
    {
        return CloneIdiom::None;
    }
    ++i;
    if( i < t.size() && t[i].text == "(" )
    {
        ++i;
        std::size_t taken = 0;
        while( i < t.size() && t[i].text != ")" )
        {
            if( t[i].text == "(" )
            {
                return CloneIdiom::None;   // a computed selector is not a name table
            }
            ++i;
            ++taken;
            if( taken > kIdiomMaxCondTokens )
            {
                return CloneIdiom::None;
            }
        }
        if( i >= t.size() )
        {
            return CloneIdiom::None;
        }
        ++i;
    }
    if( i >= t.size() || t[i].text != "{" )
    {
        return CloneIdiom::None;
    }
    ++i;
    std::size_t depth = 1, cases = 0, returns = 0;
    while( i < t.size() && depth > 0 )
    {
        const std::string_view w = t[i].text;
        if( w == "{" )
        {
            ++depth;
            ++i;
            continue;
        }
        if( w == "}" )
        {
            --depth;
            ++i;
            continue;
        }
        if( w == "case" || w == "default" )
        {
            if( !idiomEatCaseLabel( t, i ) )
            {
                return CloneIdiom::None;
            }
            if( w == "case" )
            {
                ++cases;
            }
            continue;
        }
        if( w == "return" )
        {
            if( !idiomEatReturn( t, i ) )
            {
                return CloneIdiom::None;
            }
            ++returns;
            continue;
        }
        if( w == "break" )
        {
            ++i;
            if( i < t.size() && t[i].text == ";" )
            {
                ++i;
            }
            continue;
        }
        return CloneIdiom::None;
    }
    // the tail after the switch closes: at most a fallback return, nothing else.
    while( i < t.size() )
    {
        const std::string_view w = t[i].text;
        if( w == "{" || w == "}" )
        {
            ++i;
            continue;
        }
        if( w == "return" )
        {
            if( !idiomEatReturn( t, i ) )
            {
                return CloneIdiom::None;
            }
            ++returns;
            continue;
        }
        return CloneIdiom::None;
    }
    return ( cases >= kIdiomMinTableCases && returns >= kIdiomMinTableCases ) ? CloneIdiom::SwitchNameTable : CloneIdiom::None;
}

// One `;`-terminated statement of a builder body, classified by shape. `receiver` is the assigned-to object
// of a field assignment (empty for the other two forms), which the caller uses to require ONE receiver.
enum class IdiomStmt : std::uint8_t { Reject, FieldAssign, Declare, Return };

inline IdiomStmt idiomClassifyBuilderStmt( const std::vector<IdiomTok>& t, std::size_t a, std::size_t b, std::string_view& receiver )
{
    receiver = {};
    const std::size_t n = b - a;
    if( n == 0 )
    {
        return IdiomStmt::Reject;
    }
    for( std::size_t k = a; k < b; ++k )
    {
        if( t[k].text == "(" || t[k].text == "{" || t[k].text == "[" )
        {
            return IdiomStmt::Reject;   // a call, an aggregate init, a subscript — all outside this grammar
        }
    }
    if( t[a].text == "return" )
    {
        return n <= 1 + kIdiomMaxReturnTokens ? IdiomStmt::Return : IdiomStmt::Reject;
    }
    // `<recv> . <field> [ . <field> ]* = <value>` — exactly one assignment operator, at least one value token.
    if( n >= 5 && t[a].kind == CodeTokenKind::Identifier
        && ( t[a + 1].text == "." || t[a + 1].text == "->" ) && t[a + 2].kind == CodeTokenKind::Identifier )
    {
        std::size_t eq = 0, eqAt = 0;
        for( std::size_t k = a; k < b; ++k )
        {
            if( t[k].text == "=" )
            {
                ++eq;
                eqAt = k;
            }
        }
        if( eq == 1 && eqAt >= a + 3 && eqAt + 1 < b )
        {
            receiver = t[a].text;
            return IdiomStmt::FieldAssign;
        }
        return IdiomStmt::Reject;
    }
    // `Type name` / `const Type name` — the receiver's own declaration, with no initializer.
    if( n <= 4 )
    {
        for( std::size_t k = a; k < b; ++k )
        {
            if( t[k].kind != CodeTokenKind::Identifier && t[k].kind != CodeTokenKind::Keyword )
            {
                return IdiomStmt::Reject;
            }
        }
        return IdiomStmt::Declare;
    }
    return IdiomStmt::Reject;
}

// idiom 3 — the param-struct initializer chain: declare the struct, assign >= kIdiomMinBuilderFields of its
// fields through ONE receiver, return it. No control flow anywhere in the body.
inline CloneIdiom classifyBuilderChain( const std::vector<IdiomTok>& t )
{
    std::size_t assigns = 0, declares = 0, returns = 0;
    std::string_view recv;
    std::size_t      i = 0;
    while( i < t.size() )
    {
        if( t[i].text == "{" || t[i].text == "}" )
        {
            ++i;
            continue;
        }
        std::size_t j = i;
        while( j < t.size() && t[j].text != ";" )
        {
            ++j;
        }
        if( j >= t.size() )
        {
            return CloneIdiom::None;   // an unterminated trailing statement is not this shape
        }
        std::string_view here;
        switch( idiomClassifyBuilderStmt( t, i, j, here ) )
        {
            case IdiomStmt::FieldAssign:
                if( recv.empty() )
                {
                    recv = here;
                }
                else if( recv != here )
                {
                    return CloneIdiom::None;   // two receivers is a function body, not one struct being filled
                }
                ++assigns;
                break;
            case IdiomStmt::Declare: ++declares; break;
            case IdiomStmt::Return:  ++returns;  break;
            case IdiomStmt::Reject:  return CloneIdiom::None;
        }
        i = j + 1;
    }
    return ( assigns >= kIdiomMinBuilderFields && declares <= 1 && returns <= 1 ) ? CloneIdiom::BuilderChain : CloneIdiom::None;
}

// ── idiom 4, one-statement (decision C3; see the header) ──────────────────────────────────────────────

// The contract asserts that do not count as a statement: a one-liner that states its precondition first is
// still a one-liner. The set is closed and these four are the house spellings (CLAUDE.md, the ASSUME rule).
inline constexpr std::string_view kIdiomContractMacros[] = { "EXPECTS", "ASSUME", "DASSERT", "VALIDATE" };

// Condition (2)'s stop list for one-statement members: standard container and string vocabulary, the words
// two unrelated one-liners share because they both touch a string or a vector. Fixed and documented here,
// never tuned per finding: a word added here stops refusing demotions everywhere at once.
inline constexpr std::string_view kIdiomOneStatementStopWords[] = {
    "size", "empty", "begin", "end", "find", "rfind", "substr", "npos", "front", "back", "data",
    "first", "second", "starts_with", "ends_with", "contains" };

// Languages whose parameter spells its NAME first (`a: T`, `a T`, untyped `a`). Every other language reads
// the C-family way: the name is the last identifier before a default (`const Symbol& s`, `int n = 3`).
inline constexpr std::uint32_t kIdiomNameFirstLangMask = langBit( Lang::Python ) | langBit( Lang::TypeScript ) | langBit( Lang::JavaScript )
                                                       | langBit( Lang::Go ) | langBit( Lang::Rust ) | langBit( Lang::Swift ) | langBit( Lang::Kotlin )
                                                       | langBit( Lang::GDScript ) | langBit( Lang::Ruby ) | langBit( Lang::Lua ) | langBit( Lang::Elixir );

// The depth step of one token: +1 for an opening bracket of any kind, -1 for a closing one, 0 otherwise. One
// switch rather than two `==` disjunctions, which the duplication kind names as the next copy of the house's
// "is one of N constants" predicate.
inline int idiomBracketStep( std::string_view w ) noexcept
{
    if( w.size() != 1 )
    {
        return 0;
    }
    switch( w[0] )
    {
        case '(':
        case '[':
        case '{': return 1;
        case ')':
        case ']':
        case '}': return -1;
        default:  return 0;
    }
}

// The index of the bracket that closes the one opened at t[open], searched before `end`; `end` when it does not close
// there. Bracket kinds are not matched against each other: a body the scanner read is balanced or is not this shape.
inline std::size_t idiomCloseOf( const std::vector<IdiomTok>& t, std::size_t open, std::size_t end ) noexcept
{
    std::size_t depth = 0;
    for( std::size_t j = open; j < end; ++j )
    {
        const int step = idiomBracketStep( t[j].text );
        if( step > 0 )
        {
            ++depth;
        }
        else if( step < 0 && --depth == 0 )
        {
            return j;
        }
    }
    return end;
}

// The member-access spellings: a name after one of these is a MEMBER (oneStatementFacts) or the next link of a call
// chain (idiomEatCallStatement). A table, for the same reason as kIdiomRelOps.
inline constexpr std::string_view kIdiomAccessOps[] = { ".", "->", "::" };
inline bool idiomIsAccessOp( std::string_view w ) noexcept
{
    return std::find( std::begin( kIdiomAccessOps ), std::end( kIdiomAccessOps ), w ) != std::end( kIdiomAccessOps );
}

// `MACRO ( <balanced> ) ;?` for a kIdiomContractMacros name. Advances past it on a match.
inline bool idiomEatContract( const std::vector<IdiomTok>& t, std::size_t& i, std::size_t end )
{
    if( i + 1 >= end || t[i + 1].text != "("
        || std::find( std::begin( kIdiomContractMacros ), std::end( kIdiomContractMacros ), t[i].text ) == std::end( kIdiomContractMacros ) )
    {
        return false;
    }
    std::size_t j = idiomCloseOf( t, i + 1, end );
    if( j >= end )
    {
        return false;   // unbalanced: not a contract statement this grammar can bound
    }
    ++j;
    if( j < end && t[j].text == ";" )
    {
        ++j;
    }
    i = j;
    return true;
}

// The body is `{ [contract]* return <expr> ;? }` and nothing else. <expr> may hold anything bracketed —
// a lambda's own braces and semicolons sit at depth > 0 and are part of the one statement — but a `;` at
// depth 0 that is not the last token is a second statement, and a body that does not start with `return`
// (a declaration, an `if`, a loop) is refused outright.
inline CloneIdiom classifyOneStatement( const std::vector<IdiomTok>& t )
{
    std::size_t i = 0, end = t.size();
    if( end >= 2 && t[0].text == "{" && t[end - 1].text == "}" )
    {
        ++i;
        --end;
    }
    while( idiomEatContract( t, i, end ) )
    {
        // each call advanced `i` past one leading contract assert
    }
    if( i >= end || t[i].text != "return" )
    {
        return CloneIdiom::None;
    }
    ++i;
    std::size_t depth = 0, taken = 0;
    for( ; i < end; ++i )
    {
        const std::string_view w    = t[i].text;
        const int              step = idiomBracketStep( w );
        if( step > 0 )
        {
            ++depth;
        }
        else if( step < 0 )
        {
            if( depth == 0 )
            {
                return CloneIdiom::None;   // closes something the body never opened
            }
            --depth;
        }
        else if( depth == 0 && w == ";" )
        {
            return ( i + 1 == end && taken >= 1 ) ? CloneIdiom::OneStatement : CloneIdiom::None;
        }
        ++taken;
    }
    return ( depth == 0 && taken >= 1 ) ? CloneIdiom::OneStatement : CloneIdiom::None;   // a `;`-less language
}

// ── idiom 5, call-sequence (QD-FALSE-ROWS-E0; see the header) ─────────────────────────────────────────

// One `<call> ;` statement starting at t[i], before `end`: a name, then any run of `.`/`->`/`::` + name and of
// balanced `( … )` groups, ending in a call and a `;`. Advances past the `;` on a match. The state is whether a
// name is due and whether the last thing was a call, so `a b` (a declaration), `a = …`, `a[ i ]`, `a< T >`, a
// keyword and a bare name all fall to the catch-all refusal.
inline bool idiomEatCallStatement( const std::vector<IdiomTok>& t, std::size_t& i, std::size_t end )
{
    bool nameDue = true, endsInCall = false;
    for( std::size_t k = i; k < end; ++k )
    {
        const std::string_view w = t[k].text;
        if( nameDue )
        {
            if( t[k].kind != CodeTokenKind::Identifier )
            {
                return false;
            }
            nameDue    = false;
            endsInCall = false;
        }
        else if( w == "(" )
        {
            k          = idiomCloseOf( t, k, end );   // the arguments: anything bracketed, a lambda included
            endsInCall = k < end;
        }
        else if( w == ";" && endsInCall )
        {
            i = k + 1;
            return true;
        }
        else if( idiomIsAccessOp( w ) )
        {
            nameDue = true;
        }
        else
        {
            return false;
        }
    }
    return false;   // unbalanced, or the body ended before the statement's `;`
}

// The body is `{ <call> ; [ <call> ; ]* }` and nothing else.
inline CloneIdiom classifyCallSequence( const std::vector<IdiomTok>& t )
{
    if( t.size() < 2 || t.front().text != "{" || t.back().text != "}" )
    {
        return CloneIdiom::None;
    }
    const std::size_t end = t.size() - 1;
    std::size_t       i   = 1;
    if( i >= end )
    {
        return CloneIdiom::None;   // an empty body calls nothing
    }
    while( i < end )
    {
        if( !idiomEatCallStatement( t, i, end ) )
        {
            return CloneIdiom::None;
        }
    }
    return CloneIdiom::CallSequence;
}

// One type-parameter group opened at sig[open] — `<T extends Base, U>` (TypeScript, Rust, Java, C#, Swift,
// Kotlin) or `[T any]` (Go) — skipped: the index just past its close, or sig.size() when it never closes
// before a body or statement starts.
inline std::size_t idiomSkipTypeParams( const std::vector<IdiomTok>& sig, std::size_t open ) noexcept
{
    const bool  angled = sig[open].text == "<";
    std::size_t depth  = 0;
    for( std::size_t k = open; k < sig.size(); ++k )
    {
        const std::string_view w = sig[k].text;
        if( w == "{" || w == ";" )
        {
            break;
        }
        if( angled )
        {
            if( w == "<" )
            {
                ++depth;
            }
            else if( !w.empty() && w.find_first_not_of( '>' ) == std::string_view::npos && depth > 0 )
            {
                depth -= std::min( depth, w.size() );   // `>>` closes two
            }
        }
        else
        {
            const int step = idiomBracketStep( w );
            depth = step > 0 ? depth + 1 : ( step < 0 && depth > 0 ? depth - 1 : depth );
        }
        if( depth == 0 )
        {
            return k + 1;
        }
    }
    return sig.size();
}

// The `(` that opens the symbol's own parameter list: `name (`, or `name` then one type-parameter group then
// `(` (`first<T>( value: T )`, `First[T any]( value T )`). sig.size() when the signature spells neither.
inline std::size_t idiomParamListOpen( const std::vector<IdiomTok>& sig, std::string_view name ) noexcept
{
    for( std::size_t i = 0; !name.empty() && i + 1 < sig.size(); ++i )
    {
        if( sig[i].text != name )
        {
            continue;
        }
        std::size_t j = i + 1;
        if( sig[j].text == "<" || sig[j].text == "[" )
        {
            j = idiomSkipTypeParams( sig, j );
        }
        if( j < sig.size() && sig[j].text == "(" )
        {
            return j;
        }
    }
    return sig.size();
}

// Whether the `<` at sig[at], inside a DEFAULT argument, opens template arguments (`= pick<Lo, Hi>()`) rather than comparing
// (`= kLo < kHi`): it does when its matching `>` comes, at its own bracket depth, before any `=` (the next parameter's default
// or a comparison's `==`/`<=`), `;`, `&&`/`||`, or the bracket that closes the list. A template argument list holds none of
// those, and a comparison's `<` is never closed before the next parameter's own `=` or the list's `)` (CodeRabbit #636).
inline bool idiomDefaultAngleOpens( const std::vector<IdiomTok>& sig, std::size_t at )
{
    std::size_t depth = 0, angle = 1;
    for( std::size_t j = at + 1; j < sig.size(); ++j )
    {
        const std::string_view w    = sig[j].text;
        const int              step = idiomBracketStep( w );
        if( step != 0 )
        {
            if( step < 0 && depth == 0 )
            {
                return false;
            }
            depth = step > 0 ? depth + 1 : depth - 1;
            continue;
        }
        if( depth != 0 )
        {
            continue;
        }
        if( w == "<" )
        {
            ++angle;
        }
        else if( w == ">" || w == ">>" )
        {
            angle -= std::min<std::size_t>( angle, w.size() );
            if( angle == 0 )
            {
                return true;
            }
        }
        else if( w == "=" || w == "==" || w == "<=" || w == ">=" || w == "!=" || w == ";" || w == "&&" || w == "||" )
        {
            return false;
        }
    }
    return false;
}

// The parameters of one signature, read off its tokens: the `(` that opens the symbol's own parameter list
// (idiomParamListOpen: after its name, and after a generic signature's type parameters), split at depth-1 commas
// (template angles counted, so `std::map<K, V> m` is one parameter), the default after a depth-1 `=` ignored (a
// template comma inside it, `= pick<T, U>()`, ends no parameter: idiomDefaultAngleOpens). A signature that spells
// no parameter list yields none. That is safe for condition (2), since every name returned here LEAVES the
// identifier set, but NOT for the alpha-rename refusal, which then sees two parameter-renamed copies as different
// bodies: so the list is found through type parameters too (CodeRabbit #629, `function first<T>( value: T )`).
//
// Each parameter also carries its TYPE as the operand path reads it (QD-IDIOM-ELEMTYPE, see the header): every
// token of the parameter but its name, the default, the pass-by spelling (`const`, `volatile`, `&`, `&&`, `mut`,
// a name-first `:`) and qualifiers (`std::`, `rw::`), FNV-1a keyed; 0 when the parameter spells no type.
// `typed` is false unless EVERY parameter spells a concrete one: a template header, a type-parameter group after
// the name, or an `auto`/`impl` parameter makes the types generic, and an untyped parameter (Python's `self`)
// says nothing, so the operand path cannot claim a difference there. A C++ `template < … >` header usually sits before
// the signature range: memberShapeOf asks idiomTemplateHeaderBefore for it.
struct IdiomParams
{
    std::vector<std::string_view> names;
    std::vector<std::uint64_t>    types;
    bool                          typed = false;
};

inline constexpr std::string_view kIdiomPassBySpellings[] = { "const", "volatile", "&", "&&", "mut", ":" };
inline constexpr std::string_view kIdiomGenericTypeWords[] = { "auto", "impl", "template" };

// One parameter's type key: its tokens without the name at `nameAt`, the pass-by spellings and the qualifiers.
inline std::uint64_t idiomParamTypeKey( const std::vector<std::string_view>& part, std::size_t nameAt, bool& generic )
{
    std::string spelled;
    for( std::size_t k = 0; k < part.size(); ++k )
    {
        const std::string_view w = part[k];
        const bool qualifier = w == "::" || ( k + 1 < part.size() && part[k + 1] == "::" );
        if( k == nameAt || qualifier || std::ranges::contains( kIdiomPassBySpellings, w ) )
        {
            continue;
        }
        generic = generic || std::ranges::contains( kIdiomGenericTypeWords, w );
        spelled += w;
        spelled += '\x02';
    }
    return spelled.empty() ? 0 : fnv1a64( spelled );
}

// The bytes of a C++ template header the symbol's signature range leaves out: whether the tokens right before
// `sigStart` (within kIdiomTemplateLookback bytes) end in `template < … >`. A member of a class template is not seen —
// its parameter type may still be the class's own type parameter, and then reads as concrete (stated in the header).
constexpr std::size_t kIdiomTemplateLookback = 256;
inline bool idiomTemplateHeaderBefore( const std::string& bytes, std::size_t sigStart, bool hashComments )
{
    std::vector<IdiomTok> t;
    scanCodeTokens( bytes, sigStart > kIdiomTemplateLookback ? sigStart - kIdiomTemplateLookback : 0, sigStart, hashComments, true,
                    [ & ]( std::string_view w, CodeTokenKind kind ) { t.push_back( { w, kind } ); } );
    std::size_t angle = 0;
    for( std::size_t k = t.size(); k > 0; --k )
    {
        const std::string_view w = t[k - 1].text;
        if( k == t.size() && w != ">" && w != ">>" )
        {
            return false;
        }
        angle += w == ">" ? 1 : ( w == ">>" ? 2 : 0 );
        if( w == "<" && --angle == 0 )
        {
            return k >= 2 && t[k - 2].text == "template";
        }
    }
    return false;
}

inline IdiomParams idiomParams( const std::vector<IdiomTok>& sig, std::string_view name, bool nameFirst )
{
    IdiomParams out;
    std::size_t i = idiomParamListOpen( sig, name );
    if( i >= sig.size() )
    {
        return out;
    }
    // A template header, or a type-parameter group between the name and the list: every parameter type may be generic.
    bool generic = sig[i - 1].text != name
                || std::any_of( sig.begin(), sig.begin() + std::ptrdiff_t( i ), []( const IdiomTok& t ) { return t.text == "template"; } );
    bool untyped = false;
    i += 1;
    std::size_t                   depth = 1, angle = 0;
    bool                          inDefault = false;
    std::string_view              firstId, lastId;
    std::size_t                   firstAt = 0, lastAt = 0;
    std::vector<std::string_view> part;   // the parameter's tokens before any default, its closing `,` or `)` included
    const auto flush = [ & ]
    {
        const std::string_view pick = nameFirst ? firstId : lastId;
        if( !pick.empty() )
        {
            out.names.push_back( pick );
            if( !part.empty() && ( part.back() == "," || part.back() == ")" ) )
            {
                part.pop_back();
            }
            if( !part.empty() && part.back() == "=" )
            {
                part.pop_back();
            }
            const std::uint64_t type = idiomParamTypeKey( part, nameFirst ? firstAt : lastAt, generic );
            untyped = untyped || type == 0;
            out.types.push_back( type );
        }
        firstId = lastId = {};
        inDefault = false;
        angle = 0;
        part.clear();
    };
    for( ; i < sig.size(); ++i )
    {
        const std::string_view w    = sig[i].text;
        const int              step = idiomBracketStep( w );
        if( !inDefault )
        {
            part.push_back( w );
        }
        if( step > 0 )
        {
            ++depth;
            continue;
        }
        if( step < 0 )
        {
            if( --depth == 0 )
            {
                flush();
                break;
            }
            continue;
        }
        if( depth != 1 || inDefault )
        {
            if( depth == 1 && w == "<" && idiomDefaultAngleOpens( sig, i ) )
            {
                ++angle;
            }
            else if( depth == 1 && ( w == ">" || w == ">>" ) && angle > 0 )
            {
                angle -= std::min<std::size_t>( angle, w.size() );
            }
            else if( depth == 1 && w == "," && angle == 0 )
            {
                flush();
            }
            continue;
        }
        if( w == "<" )
        {
            ++angle;
        }
        else if( ( w == ">" || w == ">>" ) && angle > 0 )
        {
            angle -= std::min<std::size_t>( angle, w.size() );
        }
        else if( w == "," && angle == 0 )
        {
            flush();
        }
        else if( w == "=" && angle == 0 )
        {
            inDefault = true;
        }
        else if( sig[i].kind == CodeTokenKind::Identifier )
        {
            if( firstId.empty() )
            {
                firstId = w;
                firstAt = part.size() - 1;
            }
            lastId = w;
            lastAt = part.size() - 1;
        }
    }
    out.typed = !generic && !untyped;
    return out;
}

// What condition (2) and the alpha-rename refusal read for ONE one-statement or call-sequence member: the narrowed identifier
// set (see the header for its three exclusions) and a hash of the body with every parameter replaced by its
// position, so two bodies that differ only in parameter spelling hash equal.
struct OneStatementFacts
{
    std::vector<std::uint64_t> ids;     // sorted + unique FNV-1a of the narrowed identifier set
    std::uint64_t              alpha = 0;
};

inline OneStatementFacts oneStatementFacts( const std::vector<IdiomTok>& body, const std::vector<std::string_view>& params )
{
    OneStatementFacts f;
    std::vector<bool> inStdChain( body.size(), false );
    for( std::size_t k = 0; k + 1 < body.size(); ++k )
    {
        if( body[k].text != "std" || body[k + 1].text != "::" )
        {
            continue;
        }
        for( std::size_t j = k; j < body.size() && body[j].kind == CodeTokenKind::Identifier; j += 2 )
        {
            inStdChain[j] = true;
            if( j + 1 >= body.size() || body[j + 1].text != "::" )
            {
                break;
            }
        }
    }
    std::string renamed;
    for( std::size_t k = 0; k < body.size(); ++k )
    {
        const std::string_view w = body[k].text;
        // A name after `.`/`->`/`::` is a MEMBER, never the parameter it happens to be spelled like (`vf.prefix`
        // beside a parameter `prefix`): it stays in the set and is not renamed.
        const bool afterAccess = k > 0 && idiomIsAccessOp( body[k - 1].text );
        const auto param       = afterAccess ? params.end() : std::find( params.begin(), params.end(), w );
        if( body[k].kind == CodeTokenKind::Identifier && param != params.end() )
        {
            renamed += '\x01';
            renamed += std::to_string( param - params.begin() );
        }
        else
        {
            renamed += w;
        }
        renamed += '\x02';
        if( body[k].kind != CodeTokenKind::Identifier || param != params.end() || inStdChain[k]
            || std::find( std::begin( kIdiomOneStatementStopWords ), std::end( kIdiomOneStatementStopWords ), w ) != std::end( kIdiomOneStatementStopWords ) )
        {
            continue;
        }
        f.ids.push_back( fnv1a64( w ) );
    }
    sortutil::sortUnique( f.ids );
    f.alpha = fnv1a64( renamed );
    return f;
}

// The one entry point: the first grammar that accepts wins, and the five are mutually exclusive by
// construction (a ladder has no `switch` and at least two `if`s, a table's first token IS `switch`, a
// builder has no control flow and at least three field assignments, a one-statement body starts with `return`
// and holds no second statement, a call-sequence holds no `return`, `=` or keyword at the top level), so the
// order is not load-bearing.
inline CloneIdiom classifyCloneIdiom( const std::vector<IdiomTok>& t )
{
    const CloneIdiom ladder = classifyThresholdLadder( t );
    if( ladder != CloneIdiom::None )
    {
        return ladder;
    }
    const CloneIdiom table = classifySwitchNameTable( t );
    if( table != CloneIdiom::None )
    {
        return table;
    }
    const CloneIdiom builder = classifyBuilderChain( t );
    if( builder != CloneIdiom::None )
    {
        return builder;
    }
    const CloneIdiom oneStatement = classifyOneStatement( t );
    if( oneStatement != CloneIdiom::None )
    {
        return oneStatement;
    }
    return classifyCallSequence( t );
}

// ── group verdicts ────────────────────────────────────────────────────────────────────────────────────

// The operand path's verdict (QD-IDIOM-ELEMTYPE, see the header): which proved difference held for every pair of a
// group. A bit each, so a group whose pairs differ in different ways is both.
enum class CloneOperandDiff : std::uint8_t { None = 0, Literals = 1, Types = 2, LiteralsOrTypes = 3 };

inline constexpr std::string_view kCloneOperandWhy[] = { "", "different literals", "different parameter types", "different literals or parameter types" };
static_assert( std::size( kCloneOperandWhy ) == std::size_t( CloneOperandDiff::LiteralsOrTypes ) + 1,
               "kCloneOperandWhy must carry exactly one row per CloneOperandDiff, in declaration order" );

// The why= text a clone row carries when the operand path demoted it; "" otherwise.
inline std::string_view cloneOperandWhy( CloneOperandDiff d ) noexcept { return kCloneOperandWhy[ std::size_t( d ) ]; }

// What one clone group's members turned out to be.
struct CloneIdiomVerdict
{
    CloneIdiom       idiom    = CloneIdiom::None;         // the idiom EVERY member classifies to (None = no agreement, or none recognized)
    bool             demoted  = false;                    // the full conjunction held: annotated AND no longer gating
    CloneOperandDiff operands = CloneOperandDiff::None;   // quality-delta only: not demoted above, but every pair's operands differ (the --clones verb never reads it)
};

// The literals the operand path compares: numbers, strings and characters, plus the value keywords (`true`,
// `nullptr`, `None` …) — but not 0 and 1, the index arithmetic every loop spells (`i = 0`, `> 0`, `- 1`).
inline constexpr std::string_view kIdiomIndexLiterals[] = { "0", "1" };
inline constexpr std::string_view kIdiomValueKeywords[] = { "true", "false", "nullptr", "NULL", "null", "nil", "None", "True", "False" };

// Sorted + unique FNV-1a of the body tokens `keep` accepts: the one set builder the literal set and the
// whole-body identifier set (condition (2) outside the narrowed idioms) both read.
template <typename Keep>
inline std::vector<std::uint64_t> idiomTokenHashSet( const std::vector<IdiomTok>& body, Keep keep )
{
    std::vector<std::uint64_t> out;
    for( const IdiomTok& t : body )
    {
        if( keep( t ) )
        {
            out.push_back( fnv1a64( t.text ) );
        }
    }
    sortutil::sortUnique( out );
    return out;
}

// A literal the operand path compares (kIdiomIndexLiterals left out; the value keywords counted).
inline bool idiomComparedLiteral( const IdiomTok& t )
{
    const bool literal = t.kind == CodeTokenKind::Number || t.kind == CodeTokenKind::String;
    return literal ? !std::ranges::contains( kIdiomIndexLiterals, t.text ) : std::ranges::contains( kIdiomValueKeywords, t.text );
}

// Sorted + unique FNV-1a of a body's literals.
inline std::vector<std::uint64_t> idiomLiteralSet( const std::vector<IdiomTok>& body )
{
    return idiomTokenHashSet( body, idiomComparedLiteral );
}

namespace cloneidiomdetail
{

// One member's classification inputs. `ids` is filled only when the shape was recognized — the identifier
// set exists to answer condition (2), and there is nothing to answer when (1) already failed.
struct MemberShape
{
    CloneIdiom                 idiom  = CloneIdiom::None;
    std::vector<std::uint64_t> ids;      // sorted + unique FNV-1a of every non-keyword identifier in the body (one-statement, call-sequence: the narrowed set)
    std::uint64_t              alpha  = 0;   // one-statement and call-sequence only: the parameter-renamed body hash (OneStatementFacts::alpha)
    std::uint32_t              fileId = 0;
    std::string                scope;
    bool                       read   = false;   // the body was read; an unread member proves no operand difference
    std::vector<std::uint64_t> literals;         // idiomLiteralSet of the body
    std::vector<std::uint64_t> valueIds;         // the subset of `ids` used as a value somewhere (operand path (6))
    std::vector<std::uint64_t> callIds;          // the subset of `ids` called somewhere, `f(` not after `.`/`->` (operand path (6))
    bool                       literalArg = false;   // a compared literal is a direct argument of some call (operand path (5))
    std::vector<std::uint64_t> paramTypes;       // IdiomParams::types, in parameter order
    bool                       typed  = false;   // IdiomParams::typed
};

// Both sides are sorted+unique, so probing the SMALLER set into the larger settles disjointness in
// O(min·log max) — and, unlike the sorted merge this first spelled, it is not a fourth copy of the
// merge-two-sorted-vectors body the tree already carries three of.
inline bool idiomSetsDisjoint( const std::vector<std::uint64_t>& a, const std::vector<std::uint64_t>& b ) noexcept
{
    const std::vector<std::uint64_t>& few  = a.size() <= b.size() ? a : b;
    const std::vector<std::uint64_t>& many = a.size() <= b.size() ? b : a;
    return std::none_of( few.begin(), few.end(),
                         [ & ]( std::uint64_t h ) { return std::binary_search( many.begin(), many.end(), h ); } );
}

// The shape of one member whose file bytes are `bytes`. A body that cannot be read stays None and unread.
// The members of `ids` some token of `body` uses as a VALUE (not followed by `(` or `::`) and as a CALL (followed by `(`),
// leaving out parameters and members after `.`/`->` (a name after `::` IS used: `Grade::Poor`, `tables::svLess`).
// Both sorted + unique subsets of `ids`.
struct IdiomUses
{
    std::vector<std::uint64_t> values;
    std::vector<std::uint64_t> calls;
};
inline IdiomUses idiomUseIds( const std::vector<IdiomTok>& body, const std::vector<std::string_view>& params, const std::vector<std::uint64_t>& ids )
{
    IdiomUses used;
    for( std::size_t k = 0; k < body.size(); ++k )
    {
        const std::string_view next   = k + 1 < body.size() ? body[k + 1].text : std::string_view{};
        const bool             member = k > 0 && ( body[k - 1].text == "." || body[k - 1].text == "->" );
        if( body[k].kind != CodeTokenKind::Identifier || member || next == "::" || std::ranges::contains( params, body[k].text ) )
        {
            continue;
        }
        ( next == "(" ? used.calls : used.values ).push_back( fnv1a64( body[k].text ) );
    }
    for( std::vector<std::uint64_t>* v : { &used.values, &used.calls } )
    {
        sortutil::sortUnique( *v );
        std::vector<std::uint64_t> kept;
        std::ranges::set_intersection( *v, ids, std::back_inserter( kept ) );
        *v = std::move( kept );
    }
    return used;
}

// Whether some call in `body` takes a compared literal as a direct argument (`s.rfind( '/' )`, `find( "::" )`): two bodies
// that both do are one function with the literal as a parameter (namesplit::afterLast), whatever the literals.
inline bool idiomLiteralArgument( const std::vector<IdiomTok>& body )
{
    for( std::size_t k = 1; k < body.size(); ++k )
    {
        if( body[k].text != "(" || body[k - 1].kind != CodeTokenKind::Identifier )
        {
            continue;
        }
        const std::size_t shut  = idiomCloseOf( body, k, body.size() );
        std::size_t       depth = 0;
        for( std::size_t j = k + 1; j < shut && j < body.size(); ++j )
        {
            const int step = idiomBracketStep( body[j].text );
            depth = step > 0 ? depth + 1 : ( step < 0 && depth > 0 ? depth - 1 : depth );
            if( depth == 0 && idiomComparedLiteral( body[j] ) )
            {
                return true;
            }
        }
    }
    return false;
}

inline MemberShape memberShapeOf( const Symbol& s, const std::string& bytes )
{
    MemberShape out;
    out.fileId = s.fileId;
    out.scope  = s.scope;
    if( bytes.empty() || s.endByte <= s.sigEndByte || s.endByte > bytes.size() )
    {
        return out;   // degrade: an unreadable member classifies as None and proves nothing, so its group keeps gating
    }
    std::vector<IdiomTok> toks;
    scanCodeTokens( bytes, s.sigEndByte, s.endByte, usesHashLineComments( s.lang ), true,
                    [ & ]( std::string_view w, CodeTokenKind kind ) { toks.push_back( { w, kind } ); } );
    std::vector<IdiomTok> sig;
    if( s.sigStartByte < s.sigEndByte )
    {
        scanCodeTokens( bytes, s.sigStartByte, s.sigEndByte, usesHashLineComments( s.lang ), true,
                        [ & ]( std::string_view w, CodeTokenKind kind ) { sig.push_back( { w, kind } ); } );
    }
    const IdiomParams params = idiomParams( sig, s.name, langInMask( kIdiomNameFirstLangMask, s.lang ) );
    out.read       = true;
    out.literals   = idiomLiteralSet( toks );
    out.literalArg = idiomLiteralArgument( toks );
    out.paramTypes = params.types;
    out.typed      = params.typed && !idiomTemplateHeaderBefore( bytes, s.sigStartByte, usesHashLineComments( s.lang ) );
    out.idiom      = classifyCloneIdiom( toks );
    if( out.idiom == CloneIdiom::None )
    {
        return out;
    }
    if( idiomReadsNarrowVocabulary( out.idiom ) )
    {
        OneStatementFacts f = oneStatementFacts( toks, params.names );
        out.ids        = std::move( f.ids );
        IdiomUses uses = idiomUseIds( toks, params.names, out.ids );
        out.valueIds   = std::move( uses.values );
        out.callIds    = std::move( uses.calls );
        out.alpha = f.alpha;
        return out;
    }
    out.ids      = idiomTokenHashSet( toks, []( const IdiomTok& t ) { return t.kind == CodeTokenKind::Identifier; } );
    IdiomUses uses = idiomUseIds( toks, params.names, out.ids );
    out.valueIds   = std::move( uses.values );
    out.callIds    = std::move( uses.calls );
    return out;
}

// Every wanted member's shape, `want` sorted by NodeId. File-major walk, so each file's bytes are read exactly once:
// `order` is sorted by (fileId, id), a pure function of the input, so the read order is deterministic.
inline std::vector<MemberShape> readMemberShapes( const IngestResult& ing, const std::vector<NodeId>& want )
{
    std::vector<MemberShape>   shapes( want.size() );
    std::vector<std::uint32_t> order( want.size() );
    for( std::uint32_t k = 0; k < order.size(); ++k )
    {
        order[k] = k;
    }
    std::sort( order.begin(), order.end(), [ & ]( std::uint32_t x, std::uint32_t y )
    {
        const std::uint32_t fx = ing.symbols[ want[x] ].fileId, fy = ing.symbols[ want[y] ].fileId;
        return fx != fy ? fx < fy : want[x] < want[y];
    } );
    std::string   bytes;
    std::uint32_t openFile = UINT32_MAX;
    for( const std::uint32_t k : order )
    {
        const Symbol& s = ing.symbols[ want[k] ];
        if( s.fileId != openFile )
        {
            openFile = s.fileId;
            bytes    = docparse::detail::readWholeFile( diskPath( ing, s.fileId ) ).value_or( std::string() );
        }
        shapes[k] = memberShapeOf( s, bytes );
    }
    return shapes;
}

inline bool sameContext( const MemberShape& a, const MemberShape& b ) noexcept { return a.fileId == b.fileId && a.scope == b.scope; }

// The idiom conjunction for a group whose members all spell `idiom`: (4) the size ceiling, then (3) no shared context and
// (2) no shared vocabulary — pairwise, because a 3-member group in which only two members collide is still two members that collide.
inline bool idiomDemotes( const CloneGroup& gp, const std::vector<const MemberShape*>& ms, CloneIdiom idiom )
{
    bool demote = gp.tokens < kIdiomCloneTokenFloor;
    for( std::size_t a = 0; demote && a < ms.size(); ++a )
    {
        for( std::size_t b = a + 1; demote && b < ms.size(); ++b )
        {
            if( sameContext( *ms[a], *ms[b] ) )
            {
                demote = false;
            }
            else if( idiomReadsNarrowVocabulary( idiom ) && ms[a]->alpha == ms[b]->alpha )
            {
                demote = false;   // a Type-1 copy after renaming parameters — a copy whatever its vocabulary
            }
            else if( !idiomSetsDisjoint( ms[a]->ids, ms[b]->ids ) )
            {
                demote = false;
            }
        }
    }
    return demote;
}

// The difference the operand path proves for one pair, or None: no literal in common (and at least one literal), else
// the same number of parameters, all concrete, with a different type at some position.
inline CloneOperandDiff pairOperandDiff( const MemberShape& a, const MemberShape& b ) noexcept
{
    if( !a.read || !b.read )
    {
        return CloneOperandDiff::None;
    }
    if( ( !a.literals.empty() || !b.literals.empty() ) && !( a.literalArg && b.literalArg ) && idiomSetsDisjoint( a.literals, b.literals ) )
    {
        return CloneOperandDiff::Literals;
    }
    const bool comparable = a.typed && b.typed && !a.paramTypes.empty() && a.paramTypes.size() == b.paramTypes.size();
    return comparable && a.paramTypes != b.paramTypes ? CloneOperandDiff::Types : CloneOperandDiff::None;
}

// Operand path (6): whether the pair calls one helper, or shares a value identifier the index does not name a function
// (`fnNames` sorted).
inline bool sharesDomainValue( const MemberShape& a, const MemberShape& b, const std::vector<std::uint64_t>& fnNames )
{
    if( !idiomSetsDisjoint( a.callIds, b.callIds ) )
    {
        return true;
    }
    std::vector<std::uint64_t> shared;
    std::ranges::set_intersection( a.valueIds, b.valueIds, std::back_inserter( shared ) );
    return std::ranges::any_of( shared, [ & ]( std::uint64_t h ) { return !std::ranges::binary_search( fnNames, h ); } );
}

// Sorted + unique FNV-1a of every function and method name the index holds (operand path (6)'s exemption).
inline std::vector<std::uint64_t> functionNameHashes( const IngestResult& ing )
{
    auto hashes = ing.symbols
                | std::views::filter( []( const Symbol& s ) { return s.kind == SymKind::Function || s.kind == SymKind::Method; } )
                | std::views::transform( []( const Symbol& s ) { return fnv1a64( s.name ); } );
    std::vector<std::uint64_t> out( hashes.begin(), hashes.end() );
    sortutil::sortUnique( out );
    return out;
}

// The operand path over a whole group (see the header): under the ceiling, every pair in distinct contexts and with a proved
// operand difference, and (an idiom group) no shared domain value. The union of the differences that held, or None as
// soon as one pair proves none. `fnNames` is filled on first need.
inline CloneOperandDiff groupOperandDiff( const IngestResult& ing, const CloneGroup& gp, const std::vector<const MemberShape*>& ms, CloneIdiom idiom,
                                          std::vector<std::uint64_t>& fnNames )
{
    if( gp.tokens >= kIdiomCloneTokenFloor )
    {
        return CloneOperandDiff::None;
    }
    if( idiom != CloneIdiom::None && fnNames.empty() )
    {
        fnNames = functionNameHashes( ing );
    }
    std::uint8_t held = 0;
    for( std::size_t a = 0; a < ms.size(); ++a )
    {
        for( std::size_t b = a + 1; b < ms.size(); ++b )
        {
            const bool             refused = sameContext( *ms[a], *ms[b] ) || ( idiom != CloneIdiom::None && sharesDomainValue( *ms[a], *ms[b], fnNames ) );
            const CloneOperandDiff d       = refused ? CloneOperandDiff::None : pairOperandDiff( *ms[a], *ms[b] );
            if( d == CloneOperandDiff::None )
            {
                return CloneOperandDiff::None;
            }
            held |= std::uint8_t( d );
        }
    }
    return CloneOperandDiff( held );
}

// The shapes of one group's members, or empty when a member is not among `want`.
inline std::vector<const MemberShape*> groupShapes( const CloneGroup& gp, const std::vector<NodeId>& want, const std::vector<MemberShape>& shapes )
{
    std::vector<const MemberShape*> ms;
    ms.reserve( gp.members.size() );
    for( NodeId m : gp.members )
    {
        const auto it = std::lower_bound( want.begin(), want.end(), m );
        if( it == want.end() || *it != m )
        {
            return {};
        }
        ms.push_back( &shapes[ std::size_t( it - want.begin() ) ] );
    }
    return ms;
}

}   // namespace cloneidiomdetail

// Classify every group in `groups`, in the caller's order. Only the symbols that are already group MEMBERS
// are read — a group is 1-2% of the detector's keys, so this is a small pass beside the detector itself, and
// it never touches findClones/findClonesType3, whose emitted group SETS are therefore unchanged by
// construction. Files are opened once each, in file-id order.
inline std::vector<CloneIdiomVerdict> classifyCloneGroupIdioms( const IngestResult& ing, const std::vector<CloneGroup>& groups )
{
    using cloneidiomdetail::MemberShape;

    std::vector<CloneIdiomVerdict> out( groups.size() );

    std::vector<NodeId> want;
    for( const CloneGroup& gp : groups )
    {
        for( NodeId m : gp.members )
        {
            if( m < ing.symbols.size() )
            {
                want.push_back( m );
            }
        }
    }
    sortutil::sortUnique( want );
    if( want.empty() )
    {
        return out;
    }
    const std::vector<MemberShape> shapes = cloneidiomdetail::readMemberShapes( ing, want );
    std::vector<std::uint64_t>     fnNames;   // operand path (6), filled on first need

    for( std::size_t g = 0; g < groups.size(); ++g )
    {
        const CloneGroup& gp = groups[g];
        const std::vector<const MemberShape*> ms = gp.members.size() < 2 ? std::vector<const MemberShape*>() : cloneidiomdetail::groupShapes( gp, want, shapes );
        if( ms.empty() )
        {
            continue;
        }
        // (1) every member the SAME recognized idiom.
        const CloneIdiom idiom = ms[0]->idiom;
        const bool agree = idiom != CloneIdiom::None && std::all_of( ms.begin(), ms.end(), [ & ]( const MemberShape* m ) { return m->idiom == idiom; } );
        out[g].idiom    = agree ? idiom : CloneIdiom::None;
        out[g].demoted  = agree && cloneidiomdetail::idiomDemotes( gp, ms, idiom );
        out[g].operands = out[g].demoted ? CloneOperandDiff::None : cloneidiomdetail::groupOperandDiff( ing, gp, ms, out[g].idiom, fnNames );
    }
    return out;
}

}   // namespace rw
