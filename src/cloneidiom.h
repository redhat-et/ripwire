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
// WHAT THIS ADDS. A CLOSED set of four recognized idioms — and closed means closed; each one past the
// first three is a decision, not a patch:
//     threshold-ladder    a chain of `if( x < C ) return K` and nothing else
//     switch-name-table   a `switch` whose every arm is a label plus a literal return
//     builder-chain       a param-struct initializer chain: declare, assign every field, return
//     one-statement       the body is ONE `return <expr>;` (leading contract asserts aside) — DECISION C3
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
// Everything else stays in: member names after `.`/`->` (`scope`, `name`, `m_inClass`), named constants
// (`kMinBytesPerToken`), in-repo callees, lambda parameters, and the arguments of a contract assert.
// Conditions (3) and (4) are unchanged and there is no new floor. One extra refusal holds for this idiom:
// a pair whose two bodies are token-identical once each member's parameters are renamed by position (a
// Type-1 copy after alpha-renaming) never demotes, whatever its vocabulary — a one-line copy that renamed
// only its parameters is still a copy. That clause is what keeps two `return s.scope.empty() ? …` copies
// gating even if they had no member name in common.
// Every exclusion fails SAFE: a signature the parameter reader cannot parse yields no parameter names, so
// more identifiers stay in and fewer groups demote.
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
#include "docparse.h"  // docparse::detail::readWholeFile — the canonical whole-file byte read (never re-rolled)
#include "model.h"

#include <algorithm>
#include <cstdint>
#include <string>
#include <string_view>
#include <vector>

namespace rw
{

// The closed set. Row order IS the enum's declaration order and the static_assert is what makes reordering
// the enum a compile error rather than a silent re-labelling of every emitted row.
enum class CloneIdiom : std::uint8_t { None = 0, ThresholdLadder = 1, SwitchNameTable = 2, BuilderChain = 3, OneStatement = 4 };

inline constexpr std::string_view kCloneIdiomNames[] = { "", "threshold-ladder", "switch-name-table", "builder-chain", "one-statement" };
static_assert( std::size( kCloneIdiomNames ) == std::size_t( CloneIdiom::OneStatement ) + 1,
               "kCloneIdiomNames must carry exactly one row per CloneIdiom, in declaration order" );

inline std::string_view cloneIdiomName( CloneIdiom k ) noexcept { return kCloneIdiomNames[ std::size_t( k ) ]; }

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
        // std::find wrapper is the single most duplicated body shape in this tree (naminglens' ncAnyOf,
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

inline bool idiomIsOpenBracket( std::string_view w ) noexcept { return w == "(" || w == "[" || w == "{"; }
inline bool idiomIsCloseBracket( std::string_view w ) noexcept { return w == ")" || w == "]" || w == "}"; }

// `MACRO ( <balanced> ) ;?` for a kIdiomContractMacros name. Advances past it on a match.
inline bool idiomEatContract( const std::vector<IdiomTok>& t, std::size_t& i, std::size_t end )
{
    if( i + 1 >= end || t[i + 1].text != "("
        || std::find( std::begin( kIdiomContractMacros ), std::end( kIdiomContractMacros ), t[i].text ) == std::end( kIdiomContractMacros ) )
    {
        return false;
    }
    std::size_t j = i + 1, depth = 0;
    for( ; j < end; ++j )
    {
        if( idiomIsOpenBracket( t[j].text ) )
        {
            ++depth;
        }
        else if( idiomIsCloseBracket( t[j].text ) && --depth == 0 )
        {
            break;
        }
    }
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
    }
    if( i >= end || t[i].text != "return" )
    {
        return CloneIdiom::None;
    }
    ++i;
    std::size_t depth = 0, taken = 0;
    for( ; i < end; ++i )
    {
        const std::string_view w = t[i].text;
        if( idiomIsOpenBracket( w ) )
        {
            ++depth;
        }
        else if( idiomIsCloseBracket( w ) )
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

// The parameter NAMES of one signature's parameter list, read off its tokens: the `(` that follows the
// symbol's own name, split at depth-1 commas (template angles counted, so `std::map<K, V> m` is one
// parameter), the default after a depth-1 `=` ignored. A signature that never spells `name (` yields none —
// the safe direction, since every name returned here LEAVES the identifier set.
inline std::vector<std::string_view> idiomParamNames( const std::vector<IdiomTok>& sig, std::string_view name, bool nameFirst )
{
    std::vector<std::string_view> out;
    std::size_t i = 0;
    while( i + 1 < sig.size() && !( sig[i].text == name && sig[i + 1].text == "(" ) )
    {
        ++i;
    }
    if( name.empty() || i + 1 >= sig.size() )
    {
        return out;
    }
    i += 2;
    std::size_t      depth = 1, angle = 0;
    bool             inDefault = false;
    std::string_view firstId, lastId;
    const auto flush = [ & ]
    {
        const std::string_view pick = nameFirst ? firstId : lastId;
        if( !pick.empty() )
        {
            out.push_back( pick );
        }
        firstId = lastId = {};
        inDefault = false;
        angle = 0;
    };
    for( ; i < sig.size(); ++i )
    {
        const std::string_view w = sig[i].text;
        if( idiomIsOpenBracket( w ) )
        {
            ++depth;
            continue;
        }
        if( idiomIsCloseBracket( w ) )
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
            if( depth == 1 && w == "," && angle == 0 )
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
            }
            lastId = w;
        }
    }
    return out;
}

// What condition (2) and the alpha-rename refusal read for ONE one-statement member: the narrowed identifier
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
        const std::string_view w     = body[k].text;
        const auto             param = std::find( params.begin(), params.end(), w );
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
    std::sort( f.ids.begin(), f.ids.end() );
    f.ids.erase( std::unique( f.ids.begin(), f.ids.end() ), f.ids.end() );
    f.alpha = fnv1a64( renamed );
    return f;
}

// The one entry point: the first grammar that accepts wins, and the four are mutually exclusive by
// construction (a ladder has no `switch` and at least two `if`s, a table's first token IS `switch`, a
// builder has no control flow and at least three statements, a one-statement body starts with `return`
// and holds no second statement), so the order is not load-bearing.
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
    return classifyOneStatement( t );
}

// ── group verdicts ────────────────────────────────────────────────────────────────────────────────────

// What one clone group's members turned out to be.
struct CloneIdiomVerdict
{
    CloneIdiom idiom   = CloneIdiom::None;   // the idiom EVERY member classifies to (None = no agreement, or none recognized)
    bool       demoted = false;              // the full conjunction held: annotated AND no longer gating
};

namespace cloneidiomdetail
{

// One member's classification inputs. `ids` is filled only when the shape was recognized — the identifier
// set exists to answer condition (2), and there is nothing to answer when (1) already failed.
struct MemberShape
{
    CloneIdiom                 idiom  = CloneIdiom::None;
    std::vector<std::uint64_t> ids;      // sorted + unique FNV-1a of every non-keyword identifier in the body (one-statement: the narrowed set)
    std::uint64_t              alpha  = 0;   // one-statement only: the parameter-renamed body hash (OneStatementFacts::alpha)
    std::uint32_t              fileId = 0;
    std::string                scope;
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
    std::sort( want.begin(), want.end() );
    want.erase( std::unique( want.begin(), want.end() ), want.end() );
    if( want.empty() )
    {
        return out;
    }

    // File-major walk over the members, so each file's bytes are read exactly once. `order` is sorted by
    // (fileId, id) — a pure function of the input, so the read order is deterministic.
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

    std::string           bytes;
    std::uint32_t         openFile = UINT32_MAX;
    bool                  readOk   = false;
    std::vector<std::uint64_t> ids;
    for( const std::uint32_t k : order )
    {
        const Symbol& s = ing.symbols[ want[k] ];
        shapes[k].fileId = s.fileId;
        shapes[k].scope  = s.scope;
        if( s.fileId != openFile )
        {
            openFile = s.fileId;
            bytes    = docparse::detail::readWholeFile( diskPath( ing, s.fileId ) ).value_or( std::string() );
            readOk   = !bytes.empty();
        }
        if( !readOk || s.endByte <= s.sigEndByte || s.endByte > bytes.size() )
        {
            continue;   // degrade: an unreadable member simply classifies as None, so its group keeps gating
        }
        std::vector<IdiomTok> toks;
        scanCodeTokens( bytes, s.sigEndByte, s.endByte, usesHashLineComments( s.lang ), true,
                        [ & ]( std::string_view w, CodeTokenKind kind ) { toks.push_back( { w, kind } ); } );
        shapes[k].idiom = classifyCloneIdiom( toks );
        if( shapes[k].idiom == CloneIdiom::None )
        {
            continue;
        }
        if( shapes[k].idiom == CloneIdiom::OneStatement )
        {
            std::vector<IdiomTok> sig;
            if( s.sigStartByte < s.sigEndByte )
            {
                scanCodeTokens( bytes, s.sigStartByte, s.sigEndByte, usesHashLineComments( s.lang ), true,
                                [ & ]( std::string_view w, CodeTokenKind kind ) { sig.push_back( { w, kind } ); } );
            }
            OneStatementFacts f = oneStatementFacts( toks, idiomParamNames( sig, s.name, langInMask( kIdiomNameFirstLangMask, s.lang ) ) );
            shapes[k].ids   = std::move( f.ids );
            shapes[k].alpha = f.alpha;
            continue;
        }
        ids.clear();
        for( const IdiomTok& t : toks )
        {
            if( t.kind == CodeTokenKind::Identifier )
            {
                ids.push_back( fnv1a64( t.text ) );
            }
        }
        std::sort( ids.begin(), ids.end() );
        ids.erase( std::unique( ids.begin(), ids.end() ), ids.end() );
        shapes[k].ids = ids;
    }

    for( std::size_t g = 0; g < groups.size(); ++g )
    {
        const CloneGroup& gp = groups[g];
        if( gp.members.size() < 2 )
        {
            continue;
        }
        std::vector<const MemberShape*> ms;
        ms.reserve( gp.members.size() );
        for( NodeId m : gp.members )
        {
            const auto it = std::lower_bound( want.begin(), want.end(), m );
            if( it == want.end() || *it != m )
            {
                ms.clear();
                break;
            }
            ms.push_back( &shapes[ std::size_t( it - want.begin() ) ] );
        }
        if( ms.empty() )
        {
            continue;
        }
        // (1) every member the SAME recognized idiom.
        const CloneIdiom idiom = ms[0]->idiom;
        if( idiom == CloneIdiom::None )
        {
            continue;
        }
        bool agree = true;
        for( const MemberShape* m : ms )
        {
            agree = agree && m->idiom == idiom;
        }
        if( !agree )
        {
            continue;
        }
        out[g].idiom = idiom;

        // (4) size ceiling, then (2) no shared vocabulary and (3) no shared context — pairwise, because a
        // 3-member group in which only two members collide is still two members that collide.
        bool demote = gp.tokens < kIdiomCloneTokenFloor;
        for( std::size_t a = 0; demote && a < ms.size(); ++a )
        {
            for( std::size_t b = a + 1; demote && b < ms.size(); ++b )
            {
                if( ms[a]->fileId == ms[b]->fileId && ms[a]->scope == ms[b]->scope )
                {
                    demote = false;
                }
                else if( idiom == CloneIdiom::OneStatement && ms[a]->alpha == ms[b]->alpha )
                {
                    demote = false;   // a Type-1 copy after renaming parameters — a copy whatever its vocabulary
                }
                else if( !cloneidiomdetail::idiomSetsDisjoint( ms[a]->ids, ms[b]->ids ) )
                {
                    demote = false;
                }
            }
        }
        out[g].demoted = demote;
    }
    return out;
}

}   // namespace rw
