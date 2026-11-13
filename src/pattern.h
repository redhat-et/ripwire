#pragma once

// pattern.h — R2 "pattern surface": `--pattern='foo($X, ...)'`, structural search written in CODE.
//
// --match already exposes tree-sitter queries, and that surface is exact and unforgiving: you must know
// each grammar's node-kind vocabulary before you can ask it anything ("is it call_expression, call,
// method_invocation or invocation_expression this week?"). --pattern takes the code shape you actually
// want and compiles it, PER GRAMMAR, into a matcher — the ast-grep idea, done deterministically, with no
// new dependency and with ripwire's disclosure contract attached.
//
// ── the pipeline, in five steps ──────────────────────────────────────────────────────────────────────
//   1. NORMALIZE. `$NAME` metavariables and `...` / `$$$` ellipses are rewritten to grammar-legal
//      identifiers before tree-sitter ever sees the string (the "expando char", ast-grep
//      crates/language/src/lib.rs:93-148). `$` is not a legal identifier character in C, C++, ObjC,
//      Python, Go, Rust, Swift or C#, so a pattern carrying one does not parse at all in eight of the
//      eleven grammars served here. The marker is picked from a fixed LADDER per grammar rather than a
//      hand-kept per-grammar table: a table has to be right about every vendored grammar's lexer, and a
//      ladder only has to try. See kMarkerLadder.
//   2. WRAP. The normalized text is dropped into a family template — bare first, then progressively more
//      context — because most fragments are not independently parseable (`a + b` is not a translation
//      unit). See kTemplates.
//   3. LOCATE. The pattern's own byte range inside the wrapped source is known exactly, so the pattern
//      NODE is the smallest node containing that range, and it must span it EXACTLY. A fragment that
//      does not correspond to one node is not a pattern.
//   4. GUARD. **A clean parse is not sufficient** — this is the E1 spike's binding finding (2026-08-14):
//      Ruby's bare `new` and bash's bare `try` both parse clean into the wrong node kind. A pattern that
//      collapses to a single childless token, or whose root is itself a metavariable or an ellipsis
//      (ast-grep gh#2697, `PatternError::RootMultiMetaVar` — a pattern matches ONE node, a multi-capture
//      matches a LIST, so it cannot be a root), is refused and never scanned.
//   5. SNAPSHOT. The surviving tree is copied into a flat POD array and the TSTree is freed. Nothing in
//      the match path touches tree-sitter's pattern tree, so the program is trivially shareable across
//      the file-walk's worker threads without ts_tree_copy.
//
// ── matching semantics, stated so they can be disagreed with ─────────────────────────────────────────
//   * Kind-exact, text-exact at leaves. `a + b` does not match `a - b`: the operator is a real child.
//   * COMMENTS ARE TRANSPARENT on both sides, and nothing else is. `foo(1 /* n */, 2)` matches
//     `foo($A, $B)`. This is ast-grep's `Smart` default narrowed to the one class of trivia that files
//     bug reports (recon §3); the six-level strictness ladder is deliberately NOT built.
//   * Metavariable unification is STRUCTURAL, not textual: same node → equal; either side a named leaf →
//     compare text; otherwise kind plus recursive children (ast-grep `does_node_match_exactly`, the fix
//     for their over-strict gh#1087). Never whole-subtree string equality — that fails on incidental
//     whitespace.
//   * `$_` matches one node and binds nothing.
//   * The ellipsis is a SINGLE FIRST-MATCH-WINS PROBE, not a backtracking search: on reaching `...` the
//     matcher peeks the next literal pattern child and consumes candidate children until the first one
//     that matches it, against a CLONED environment so a failed probe leaks no binding (ast-grep
//     PR #2670). O(n) per ellipsis, no combinatorial blow-up — and it is capped at kEllipsisBound
//     children besides. Both facts are disclosed on the emitted element; neither is inferable from the
//     result, so neither may be left unsaid.
//
// ── what this deliberately does NOT do ───────────────────────────────────────────────────────────────
//   * Ruby and bash are NOT served. They are exactly the two grammars E1 caught parsing bare tokens into
//     plausible-looking wrong kinds, and a shallow eleventh and twelfth language would be a coverage
//     claim this lane cannot back. The data tiers (JSON/TOML/YAML) and markdown have no code shapes at
//     all. Both sets are NAMED in the output's unsupported= attribute — a user of those languages learns
//     the limit from the tool, never from a zero.
//   * No rule algebra (all/any/not, inside/has), no strictness knob, no user-supplied context/selector.

#include "model.h"
#include "infra/Diagnostics.h"
#include "infra/namesplit.h"   // isIdentChar / isIdentStart — the ONE ASCII identifier-character pair
#include "infra/tablelookup.h" // findByField — the one declarative-table row lookup
#include "infra/tschildren.h"  // ChildCursor/forEachChild/collectChildren — the O(C) child walk (P1-0)

#include <tree_sitter/api.h>

#include <algorithm>
#include <cstdint>
#include <cstring>
#include <string>
#include <string_view>
#include <vector>

namespace rw
{
namespace pattern
{

// ── budgets, named rather than implied ───────────────────────────────────────────────────────────────
inline constexpr std::size_t   kMaxPatternBytes = 4096;   // a pattern is a code SHAPE, not a file
inline constexpr std::size_t   kMaxMetavars     = 32;     // bindings live in a fixed-size env on the stack
inline constexpr std::uint32_t kEllipsisBound   = 256;    // sibling nodes ONE ellipsis may absorb; disclosed
inline constexpr std::size_t   kMaxHits         = 5000;   // same per-verb budget --match spends
inline constexpr std::uint8_t  kAnonMeta        = 0xFF;   // `$_` — matches one node, binds nothing

// The marker ladder (step 1). Tried in order, per grammar; the first that both parses and passes the
// guard wins, and a marker that already occurs literally in the user's pattern is skipped so a real
// identifier can never be misread as a metavariable. "$" first because it is legal in JS/TS/Java and
// leaves those patterns byte-identical to what the user typed; "µ" is ast-grep's C# choice (a letter, so
// a legal identifier start in every Unicode-aware lexer); "RW_" is the ASCII last resort for the
// grammars whose identifier rule is still `[a-zA-Z_]\w*` (tree-sitter-c and friends).
inline constexpr std::string_view kMarkerLadder[] = { "$", "\xc2\xb5", "RW_" };

// Reserved metavariable names: the normalizer spells the ellipsis and the anonymous capture as
// MARKER+NAME, so a user metavariable of the same name would be indistinguishable from one. Refused with
// a message rather than silently shadowed.
inline constexpr std::string_view kEllipsisName = "ELLIPSIS";
inline constexpr std::string_view kAnonName     = "ANON";

// ── why a pattern did not resolve, per grammar ───────────────────────────────────────────────────────
// Split because the two cases mean different things to the caller: BareToken is a fact about the PATTERN
// (refuse the whole verb — no grammar will do better), NoParse is a fact about ONE grammar (the others
// may still be fine, and the zero it might produce is what unresolved_in= exists to explain).
enum class Fault : std::uint8_t
{
    None = 0,
    NoParse,      // no template × marker combination parsed cleanly into an exactly-spanning node
    BareToken,    // parsed, but collapsed to a childless token / a bare metavariable / a bare ellipsis
};

enum class PatRole : std::uint8_t { Literal = 0, Metavar, Ellipsis };

// One node of the compiled pattern. AoS, not SoA, and deliberately: a pattern is a few dozen nodes that
// fit in one cache line's worth of pages and are walked in tree order, so the SoA split G2 mandates for
// the CSR arrays would buy nothing and cost the reader a level of indirection. The static_assert is
// still here for the same reason it is on the hot structures — a silent layout change should fail loudly.
struct PatNode
{
    std::uint32_t childStart = 0;   // into PatternProgram::childIndex
    std::uint32_t childCount = 0;
    std::uint32_t textStart  = 0;   // into PatternProgram::textPool — Literal leaves only
    std::uint32_t textLen    = 0;
    std::uint16_t kindId     = 0;   // TSSymbol, this grammar's own numbering
    PatRole       role       = PatRole::Literal;
    std::uint8_t  metaIndex  = 0;   // Metavar only; kAnonMeta ⇒ `$_`, binds nothing
};
static_assert( sizeof( PatNode ) == 20, "PatNode layout changed — check the field order before widening" );

// The compiled pattern for ONE grammar. Immutable after compile(); shared read-only by every worker.
struct PatternProgram
{
    const TSLanguage*          grammar = nullptr;
    std::string                grammarName;   // kLangTable querySub — the TEMPLATE key (shared across dialects)
    std::string                label;         // the DISCLOSURE name, unique per grammar OBJECT — what grammars=/shapes= print
    std::string                rootKind;      // the node kind the pattern became, for shapes=
    std::vector<PatNode>       nodes;         // nodes[0] is the root
    std::vector<std::uint32_t> childIndex;    // flattened child lists
    std::string                textPool;      // Literal-leaf texts, concatenated
    Fault                      fault = Fault::None;

    bool ok() const noexcept { return fault == Fault::None && !nodes.empty(); }
    std::string_view textOf( const PatNode& n ) const noexcept { return std::string_view( textPool ).substr( n.textStart, n.textLen ); }
};

// Everything one --pattern invocation compiled, plus the facts the emitter has to disclose about it.
struct PatternProgramSet
{
    std::vector<PatternProgram> programs;        // resolved ones only — one per grammar OBJECT
    std::vector<std::string>    unresolved;      // served grammar LABELS that did not resolve (per OBJECT — see GrammarRow::label)
    bool                        usesEllipsis = false;
    std::uint8_t                metavarCount = 0;

    const PatternProgram* forGrammar( const TSLanguage* g ) const noexcept
    {
        const auto it = std::find_if( programs.begin(), programs.end(), [ g ]( const PatternProgram& p ) noexcept { return p.grammar == g; } );
        return it == programs.end() ? nullptr : &*it;
    }
};

// ── step 1: normalization ────────────────────────────────────────────────────────────────────────────

// Metavariable names are ASCII identifiers, which is exactly what infra/namesplit.h already decides for
// mention.h — one predicate, two callers, no second opinion about what an identifier byte is.
using rw::namesplit::isIdentChar;
using rw::namesplit::isIdentStart;

// What the normalizer produced, or why it could not.
struct Normalized
{
    std::string              src;         // the rewritten pattern text
    std::vector<std::string> metaNames;   // binding order == metaIndex
    bool                     usesEllipsis = false;
    bool                     rootIsMarker = false;   // the WHOLE pattern is one metavariable / ellipsis
    bool                     ok           = true;
    std::string              err;
};

// Rewrite `$NAME` / `$_` / `$$$` / `$$$NAME` / `...` into MARKER-prefixed identifiers. String and
// character literals are copied through untouched, so `log("...")` keeps its literal ellipsis.
// Deterministic and allocation-light; called once per (grammar × marker × ellipsisSuffix) candidate.
//
// ellipsisSpelling is the second dimension of the ladder (empty ⇒ the default MARKER+ELLIPSIS), and it
// exists for one shape: an ellipsis in a STATEMENT position. `if ($C) { ... }` normalizes to
// `if (RW_C) { RW_ELLIPSIS }`, and in every semicolon language that is a bare expression statement
// missing its `;` — so the whole pattern failed to resolve in C, C++, ObjC, Java and C# while working
// fine in JS/Go/Rust/Swift. `RW_ELLIPSIS;` parses as a statement and is still ONE node (the
// expression_statement) whose text the snapshot recognises. C# needs a third spelling on top of that,
// and it is the real CS0201 shape, measured here rather than assumed: tree-sitter-c-sharp will not
// accept a BARE identifier as an expression statement at all (only an invocation, assignment,
// increment, `new` or `await` is a statement-expression), so `RW_ELLIPSIS;` is still a parse error there
// while `_ = RW_ELLIPSIS;` — a discard assignment — is not. The spellings are tried in order and the
// first that resolves wins, so an ellipsis in an argument list, where any of this would be a syntax
// error, is unaffected by all of it.
inline Normalized normalizePattern( std::string_view raw, std::string_view marker, std::string_view ellipsisSpelling = {} )
{
    Normalized out;
    out.src.reserve( raw.size() + 16 );

    const std::string ellipsisTok = ellipsisSpelling.empty() ? ( std::string( marker ) + std::string( kEllipsisName ) )
                                                             : std::string( ellipsisSpelling );
    const std::string anonTok     = std::string( marker ) + std::string( kAnonName );

    // metaIndex for a name, appending on first sight.
    const auto indexOfName = [ & ]( std::string_view name ) -> int
    {
        for( std::size_t i = 0; i < out.metaNames.size(); ++i )
        {
            if( out.metaNames[i] == name )
            {
                return int( i );
            }
        }
        if( out.metaNames.size() >= kMaxMetavars )
        {
            return -1;
        }
        out.metaNames.emplace_back( name );
        return int( out.metaNames.size() - 1 );
    };

    std::size_t markerCount = 0;     // how many markers the whole pattern is made of
    std::size_t otherBytes  = 0;     // non-whitespace bytes that are NOT part of a marker
    char        quote       = '\0';
    for( std::size_t i = 0; i < raw.size(); ++i )
    {
        const char c = raw[i];
        if( quote != '\0' )
        {
            out.src.push_back( c );
            ++otherBytes;
            if( c == '\\' && i + 1 < raw.size() )
            {
                out.src.push_back( raw[++i] );
            }
            else if( c == quote )
            {
                quote = '\0';
            }
            continue;
        }
        if( c == '"' || c == '\'' || c == '`' )
        {
            quote = c;
            out.src.push_back( c );
            ++otherBytes;
            continue;
        }
        // `...` — the ellipsis, spelled the way a person writes it
        if( c == '.' && i + 2 < raw.size() && raw[i + 1] == '.' && raw[i + 2] == '.' )
        {
            out.src += ellipsisTok;
            out.usesEllipsis = true;
            ++markerCount;
            i += 2;
            continue;
        }
        if( c == '$' )
        {
            std::size_t dollars = 0;
            while( i + dollars < raw.size() && raw[i + dollars] == '$' )
            {
                ++dollars;
            }
            std::size_t nameEnd = i + dollars;
            while( nameEnd < raw.size() && isIdentChar( raw[nameEnd] ) )
            {
                ++nameEnd;
            }
            const std::string_view name = raw.substr( i + dollars, nameEnd - ( i + dollars ) );
            if( dollars >= 3 )
            {   // `$$$` / `$$$NAME` — ast-grep's spelling of the same ellipsis; the NAME is accepted and dropped
                out.src += ellipsisTok;
                out.usesEllipsis = true;
                ++markerCount;
                i = nameEnd - 1;
                continue;
            }
            if( name.empty() || !isIdentStart( name[0] ) )
            {
                out.src.push_back( c );      // a lone `$` that starts no metavariable is just a byte
                ++otherBytes;
                continue;
            }
            if( name == kEllipsisName || name == kAnonName )
            {
                out.ok  = false;
                out.err = "'$" + std::string( name ) + "' is a reserved metavariable name (it is how ripwire spells the ellipsis and the anonymous capture internally) — rename it";
                return out;
            }
            if( name == "_" )
            {
                out.src += anonTok;
                ++markerCount;
                i = nameEnd - 1;
                continue;
            }
            const int metaIndex = indexOfName( name );
            if( metaIndex < 0 )
            {
                out.ok  = false;
                out.err = "more than " + std::to_string( kMaxMetavars ) + " distinct metavariables in one pattern";
                return out;
            }
            out.src += marker;
            out.src += name;
            ++markerCount;
            i = nameEnd - 1;
            continue;
        }
        out.src.push_back( c );
        if( c != ' ' && c != '\t' && c != '\n' && c != '\r' )
        {
            ++otherBytes;
        }
    }
    if( quote != '\0' )
    {
        out.ok  = false;
        out.err = "unterminated string literal in the pattern";
        return out;
    }
    // The whole pattern is ONE marker and nothing else: `$X`, `...`, `$$$ARGS`. ast-grep gh#2697 —
    // a pattern matches one node and a multi-capture matches a list, so neither can be the root. Caught
    // syntactically, before any grammar gets a chance to make it look reasonable.
    out.rootIsMarker = ( markerCount == 1 && otherBytes == 0 );
    return out;
}

// Does `marker` occur in the raw pattern OUTSIDE the metavariable/ellipsis syntax? If it does, using it
// would make a real identifier indistinguishable from a rewritten metavariable, so the candidate is
// skipped rather than risked. ("$" is special-cased: every metavariable starts with one, so only a `$`
// that does NOT begin a metavariable counts.)
inline bool markerCollides( std::string_view raw, std::string_view marker )
{
    if( marker == "$" )
    {
        for( std::size_t i = 0; i < raw.size(); ++i )
        {
            if( raw[i] != '$' )
            {
                continue;
            }
            std::size_t j = i;
            while( j < raw.size() && raw[j] == '$' )
            {
                ++j;
            }
            if( j - i >= 3 )
            {
                i = j - 1;   // `$$$` — a legal ellipsis, not a collision
                continue;
            }
            if( j >= raw.size() || !isIdentStart( raw[j] ) )
            {
                return true;   // a bare `$` the rewrite would leave behind, next to ones it replaced
            }
            i = j - 1;
        }
        return false;
    }
    return raw.find( marker ) != std::string_view::npos;
}

// ── step 2: the wrap templates ───────────────────────────────────────────────────────────────────────
// `@@` is the slot. Ordered bare-first, then by increasing context, and the FIRST that parses cleanly AND
// passes the guard wins — so a fragment that stands on its own is never needlessly wrapped, and one that
// does not is given exactly as much scaffolding as it needs. The C# rows carry the extra
// `var rwwrapv = @@;` arm: a bare expression is not a legal C# statement (the CS0201 shape), so an
// expression pattern that is not an invocation or an assignment reaches its node only through an
// initializer. Every wrapper identifier is `rwwrap`-prefixed so it cannot collide with pattern text.
struct TemplateSet
{
    std::string_view              grammarName;
    std::vector<std::string_view> templates;
};

inline const std::vector<TemplateSet>& templateTable()
{
    static const std::vector<TemplateSet> table = {
        { "c",          { "@@", "void rwwrapfn(void){ @@; }", "void rwwrapfn(void){ @@ }", "struct rwwrapst { @@ };" } },
        { "cpp",        { "@@", "void rwwrapfn(){ @@; }",     "void rwwrapfn(){ @@ }",     "struct rwwrapst { @@ };" } },
        { "objc",       { "@@", "void rwwrapfn(void){ @@; }", "void rwwrapfn(void){ @@ }", "@interface RwWrapCls : NSObject\n@@\n@end\n" } },
        { "java",       { "@@", "class RwWrapCls { void rwwrapfn(){ @@; } }", "class RwWrapCls { void rwwrapfn(){ @@ } }", "class RwWrapCls { @@ }" } },
        { "csharp",     { "@@", "class RwWrapCls { void RwWrapFn(){ @@; } }", "class RwWrapCls { void RwWrapFn(){ @@ } }",
                          "class RwWrapCls { void RwWrapFn(){ var rwwrapv = @@; } }", "class RwWrapCls { @@ }" } },
        { "javascript", { "@@", "function rwwrapfn(){ @@; }", "function rwwrapfn(){ @@ }", "class RwWrapCls { @@ }" } },
        { "typescript", { "@@", "function rwwrapfn(){ @@; }", "function rwwrapfn(){ @@ }", "class RwWrapCls { @@ }" } },
        // #285: .tsx moved to its own querySub ("tsx", not "typescript" — see kLangTable's .tsx row and
        // queries/typescript/tags.scm's header for why) so this table needs its own entry too, or
        // templatesFor("tsx") returns nullptr and supportedPatternGrammars() silently drops .tsx from
        // --pattern's served set entirely (measured: test/patterncheck.sh arm 4e's `<Foo bar={$V} />`
        // against a .tsx fixture went from hits>0 to hits=0 the moment the querySub split landed). Same
        // wrapper shapes as "typescript"/"javascript" — JSX is an expression, so it wraps the same.
        { "tsx",        { "@@", "function rwwrapfn(){ @@; }", "function rwwrapfn(){ @@ }", "class RwWrapCls { @@ }" } },
        { "python",     { "@@", "def rwwrapfn():\n    @@\n", "class RwWrapCls:\n    @@\n" } },
        { "go",         { "@@", "package rwwrappkg\n\nfunc rwwrapfn() {\n@@\n}\n", "package rwwrappkg\n\n@@\n",
                          "package rwwrappkg\n\nfunc rwwrapfn() {\nrwwrapv := @@\n}\n" } },
        { "rust",       { "@@", "fn rwwrapfn() { @@; }", "fn rwwrapfn() { @@ }", "fn rwwrapfn() { let rwwrapv = @@; }" } },
        { "swift",      { "@@", "func rwwrapfn() { @@ }", "class RwWrapCls { @@ }" } },
    };
    return table;
}

// The families --pattern deliberately does not serve, NAMED so the limit is a disclosure and not a
// silent zero. ruby/bash are the E1 node-kind traps; the rest have no code shapes to match.
inline constexpr std::string_view kUnsupportedGrammars = "ruby,bash,json,toml,yaml,markdown";

inline const TemplateSet* templatesFor( std::string_view grammarName )
{
    const std::vector<TemplateSet>& table = templateTable();
    const auto it = std::find_if( table.begin(), table.end(), [ grammarName ]( const TemplateSet& ts ) { return ts.grammarName == grammarName; } );
    return it == table.end() ? nullptr : &*it;
}

// ── steps 3-5: locate, guard, snapshot ───────────────────────────────────────────────────────────────

// Is this node kind one tree-sitter uses for a comment? Comments are transparent on BOTH sides of a
// match, so they are dropped at snapshot time and skipped at scan time. Same substring rule (and the
// same reason) as ingest.cpp's spanTierOfNodeType: a dozen grammars spell it a dozen ways and a
// hand-kept table goes stale on the next vendored grammar.
inline bool isCommentKind( const char* type ) noexcept
{
    return type != nullptr && std::strstr( type, "comment" ) != nullptr;
}

// The smallest node CONTAINING [begin,end). Iterative descent rather than
// ts_node_descendant_for_byte_range so the walk cannot be surprised by a grammar that reports an
// extra/zero-width child, and so the loop is obviously bounded by tree depth.
inline TSNode smallestContaining( TSNode root, std::uint32_t begin, std::uint32_t end )
{
    TSNode      n = root;
    ChildCursor cursor( root );   // ONE cursor for the whole descent: each level finishes before the next starts
    for( ;; )
    {
        bool descended = false;
        forEachChild( n, cursor.cur, [ & ]( TSNode child )
        {
            if( ts_node_start_byte( child ) <= begin && ts_node_end_byte( child ) >= end && ts_node_end_byte( child ) > ts_node_start_byte( child ) )
            {
                n         = child;
                descended = true;
                return false;   // stop: this level is decided
            }
            return true;
        } );
        if( !descended )
        {
            return n;
        }
    }
}

// Copy one tree-sitter subtree into the flat program. Returns the new node's index.
// The role of a node is decided by its TEXT: the normalizer wrote every metavariable and ellipsis as a
// MARKER-prefixed identifier, so a leaf (or a wrapper whose whole span is one) that spells one IS one —
// and the descent stops there, which is what makes `if ($C) { ... }` work at statement level as well as
// `foo($A, ...)` at argument level without two separate rules.
inline std::uint32_t snapshotNode( PatternProgram& prog, TSNode n, std::string_view src, std::string_view marker,
                                   const std::vector<std::string>& metaNames, std::string_view ellipsisTok, std::string_view anonTok )
{
    const std::uint32_t    index = std::uint32_t( prog.nodes.size() );
    prog.nodes.emplace_back();
    const std::uint32_t    a    = ts_node_start_byte( n ), b = ts_node_end_byte( n );
    const std::string_view text = ( b > a && b <= src.size() ) ? src.substr( a, b - a ) : std::string_view();

    {
        PatNode& self = prog.nodes[index];
        self.kindId   = ts_node_symbol( n );
        if( text == ellipsisTok )
        {
            self.role = PatRole::Ellipsis;
            return index;
        }
        if( text == anonTok )
        {
            self.role      = PatRole::Metavar;
            self.metaIndex = kAnonMeta;
            return index;
        }
        if( text.size() > marker.size() && text.compare( 0, marker.size(), marker ) == 0 )
        {
            const std::string_view name = text.substr( marker.size() );
            for( std::size_t i = 0; i < metaNames.size(); ++i )
            {
                if( metaNames[i] == name )
                {
                    self.role      = PatRole::Metavar;
                    self.metaIndex = std::uint8_t( i );
                    return index;
                }
            }
        }
    }

    // Literal: keep every child, named and anonymous alike (the `+` in `a + b` is load-bearing), minus
    // comments. A childless literal carries its own text and must match it exactly.
    std::vector<TSNode> kids;
    kids.reserve( ts_node_child_count( n ) );
    ChildCursor cursor( n );   // this frame's own — the loop below recurses into snapshotNode
    forEachChild( n, cursor.cur, [ & ]( TSNode child )
    {
        if( isCommentKind( ts_node_type( child ) ) )
        {
            return true;
        }
        if( ts_node_end_byte( child ) <= ts_node_start_byte( child ) )
        {
            return true;   // zero-width (a MISSING recovery node) — never a shape constraint
        }
        kids.push_back( child );
        return true;
    } );
    if( kids.empty() )
    {
        PatNode& self  = prog.nodes[index];
        self.textStart = std::uint32_t( prog.textPool.size() );
        self.textLen   = std::uint32_t( text.size() );
        prog.textPool.append( text );
        return index;
    }

    // Reserve the child slots before recursing: snapshotNode appends to childIndex too, so the slice
    // must be claimed up front or a grandchild's entries would land in the middle of ours.
    const std::uint32_t childStart = std::uint32_t( prog.childIndex.size() );
    prog.childIndex.resize( childStart + kids.size(), 0u );
    for( std::size_t k = 0; k < kids.size(); ++k )
    {
        prog.childIndex[ childStart + k ] = snapshotNode( prog, kids[k], src, marker, metaNames, ellipsisTok, anonTok );
    }
    PatNode& self   = prog.nodes[index];
    self.childStart = childStart;
    self.childCount = std::uint32_t( kids.size() );
    return index;
}

// Compile the pattern for ONE grammar. Walks the marker ladder × the template list and takes the first
// combination that parses clean, spans the pattern exactly, and passes the guard. `fault` says which of
// the two refusal classes applies when nothing does.
inline PatternProgram compileFor( const TSLanguage* grammar, std::string_view grammarName, std::string_view label, std::string_view raw )
{
    PatternProgram prog;
    prog.grammar     = grammar;
    prog.grammarName = std::string( grammarName );
    prog.label       = std::string( label );
    prog.fault       = Fault::NoParse;

    const TemplateSet* ts = templatesFor( grammarName );
    if( ts == nullptr )
    {
        return prog;   // not a served family — the caller already knows, this is belt and braces
    }

    for( const std::string_view marker : kMarkerLadder )
    {
        if( markerCollides( raw, marker ) )
        {
            continue;
        }
        // The ellipsis-spelling dimension: bare identifier first, then the statement form. Only the first
        // is tried when the pattern carries no ellipsis at all, so a pattern without one costs exactly
        // what it did before this dimension existed.
        const Normalized probe = normalizePattern( raw, marker );
        if( !probe.ok )
        {
            continue;
        }
        if( probe.rootIsMarker )
        {
            prog.fault = Fault::BareToken;
            return prog;
        }
        const std::string      bare         = std::string( marker ) + std::string( kEllipsisName );
        const std::string      spellings[]  = { bare, bare + ";", "_ = " + bare + ";" };
        const std::size_t      spellCount   = probe.usesEllipsis ? 3u : 1u;
        for( std::size_t spellIndex = 0; spellIndex < spellCount; ++spellIndex )
        {
        const Normalized  norm        = normalizePattern( raw, marker, spellings[spellIndex] );
        const std::string ellipsisTok = spellings[spellIndex];
        const std::string anonTok     = std::string( marker ) + std::string( kAnonName );

        for( const std::string_view tmpl : ts->templates )
        {
            const std::size_t slot = tmpl.find( "@@" );
            ASSUME( slot != std::string_view::npos );   // every row in templateTable() carries the slot
            std::string src( tmpl.substr( 0, slot ) );
            const std::uint32_t begin = std::uint32_t( src.size() );
            src += norm.src;
            const std::uint32_t end = std::uint32_t( src.size() );
            src += std::string( tmpl.substr( slot + 2 ) );

            TSParser* parser = ts_parser_new();
            ASSUME( parser != nullptr, "ts_parser_new: the default tree-sitter allocator aborts on failure (alloc.c)" );
            if( !ts_parser_set_language( parser, grammar ) )
            {
                ts_parser_delete( parser );
                continue;
            }
            TSTree* tree = ts_parser_parse_string( parser, nullptr, src.data(), std::uint32_t( src.size() ) );
            ts_parser_delete( parser );
            if( tree == nullptr )
            {
                continue;
            }
            const TSNode root = ts_tree_root_node( tree );
            // ts_node_has_error is true for ERROR *and* MISSING recovery nodes, which is exactly the
            // "did this really parse" question — a MISSING semicolon is the grammar guessing, not agreeing.
            if( ts_node_has_error( root ) )
            {
                ts_tree_delete( tree );
                continue;
            }
            const TSNode node = smallestContaining( root, begin, end );
            if( ts_node_start_byte( node ) != begin || ts_node_end_byte( node ) != end )
            {
                ts_tree_delete( tree );
                continue;   // the fragment is not ONE node in this grammar
            }

            // THE GUARD (step 4). A clean parse is not sufficient: a childless token is a text search
            // wearing a structure search's clothes, and a root metavariable/ellipsis cannot be a root.
            PatternProgram candidate;
            candidate.grammar     = grammar;
            candidate.grammarName = std::string( grammarName );
            candidate.label       = std::string( label );
            candidate.nodes.reserve( 64 );
            snapshotNode( candidate, node, src, marker, norm.metaNames, ellipsisTok, anonTok );
            const PatNode& rootNode = candidate.nodes[0];
            if( rootNode.role != PatRole::Literal || rootNode.childCount == 0 )
            {
                ts_tree_delete( tree );
                prog.fault = Fault::BareToken;
                break;   // every richer template would wrap the SAME bare token — stop asking
            }
            candidate.rootKind = ts_node_type( node ) != nullptr ? ts_node_type( node ) : "";
            candidate.fault    = Fault::None;
            ts_tree_delete( tree );
            return candidate;
        }
        if( prog.fault == Fault::BareToken )
        {
            return prog;
        }
        }
    }
    return prog;
}

// ── compiling across every served grammar, and the ONE refusal decision ──────────────────────────────

// One row of the served-grammar table; built from kLangTable by ingest.cpp so this header never has to
// know how the crawler maps extensions to grammars.
struct GrammarRow
{
    const TSLanguage* grammar = nullptr;
    std::string_view  name;      // kLangTable querySub — the TEMPLATE key: "cpp", "python", …
    // V-3 (adversarial verification 2026-08-20). querySub is NOT always unique per grammar OBJECT: `.cu`/
    // `.cuh` ride tree_sitter_cuda under querySub "cpp" (`.tsx` was the other example, under "typescript",
    // until #285 gave it its own querySub "tsx" — see kLangTable's .tsx row). The template key MUST stay
    // shared where it genuinely can (the cpp tags.scm is what compiles against the cuda grammar), but
    // the DISCLOSURE name must not be, or `grammars="cpp"` claims the C++ grammar resolved when only the
    // CUDA one did — while eligible_files=, which is keyed on the grammar OBJECT, correctly counts the
    // .cpp file as unscanned. Two attributes on one element, contradicting each other, on a run where
    // files went unscanned with no honest signal. label is unique per object, so every disclosed set is
    // keyed the same way the scan itself is. Built in ingest.cpp::supportedPatternGrammars.
    //
    // OWNED, unlike `name`: a dialect label is SYNTHESISED ("cpp/cu"), so there is no constexpr storage for
    // a view to point at, and a per-run vector of a dozen short strings is not a cost worth a lifetime bug.
    std::string       label;
};

struct CompileOutcome
{
    PatternProgramSet set;
    bool              ok = false;
    std::string       err;   // the refusal message when !ok — never empty in that case
};

// Compile `raw` for every served grammar. Refuses ONCE, for the whole verb, when no grammar could turn
// the string into a code shape — a zero from an unasked question is the §P0.1 defect, and this is the
// same rule applied one level further out.
inline CompileOutcome compileAll( std::string_view raw, const std::vector<GrammarRow>& rows )
{
    CompileOutcome out;
    if( raw.empty() )
    {
        out.err = "the pattern is empty";
        return out;
    }
    if( raw.size() > kMaxPatternBytes )
    {
        out.err = "the pattern is " + std::to_string( raw.size() ) + " bytes; the limit is " + std::to_string( kMaxPatternBytes )
                  + " (a pattern is a code SHAPE, not a file)";
        return out;
    }
    // The syntax-only pass: everything normalizePattern can refuse is a property of the pattern TEXT,
    // not of any grammar, so it is settled once and reported in the user's own spelling.
    const Normalized syntax = normalizePattern( raw, "$" );
    if( !syntax.ok )
    {
        out.err = syntax.err;
        return out;
    }
    if( syntax.rootIsMarker )
    {
        out.err = "the whole pattern is a single metavariable or ellipsis, which cannot be a pattern root — "
                  "a pattern matches ONE node and an ellipsis matches a LIST. Put it inside a shape: foo($X) rather than $X";
        return out;
    }
    out.set.usesEllipsis = syntax.usesEllipsis;
    out.set.metavarCount = std::uint8_t( syntax.metaNames.size() );

    bool anyBareToken = false;
    for( const GrammarRow& row : rows )
    {
        PatternProgram prog = compileFor( row.grammar, row.name, row.label, raw );
        if( prog.ok() )
        {
            out.set.programs.push_back( std::move( prog ) );
            continue;
        }
        anyBareToken = anyBareToken || ( prog.fault == Fault::BareToken );
        if( std::find( out.set.unresolved.begin(), out.set.unresolved.end(), prog.label ) == out.set.unresolved.end() )
        {
            out.set.unresolved.push_back( prog.label );
        }
    }
    if( out.set.programs.empty() )
    {
        out.err = anyBareToken
                      ? std::string( "this pattern collapses to a single bare token, which is a TEXT search, not a structural one — "
                                     "a clean parse is not enough (a bare word parses fine in most grammars and means nothing structural). "
                                     "Give it a shape (foo($X), $A + $B, if ($C) { ... }) or use the grep flag for literal text" )
                      : std::string( "this pattern did not resolve to a code shape in any served grammar — refusing rather than reporting a "
                                     "zero it did not measure" );
        return out;
    }
    // Belt and braces: a grammar that resolved must not also be listed as unresolved. Keyed on `label`,
    // which is unique per grammar OBJECT — the erase-by-NAME this replaced is exactly V-3's bug, because
    // `typescript/tsx` and `cpp/cuda` share a NAME and only one of the two objects may have failed, so the
    // failing object vanished from the disclosure while its files went unscanned.
    for( const PatternProgram& p : out.set.programs )
    {
        out.set.unresolved.erase( std::remove( out.set.unresolved.begin(), out.set.unresolved.end(), p.label ), out.set.unresolved.end() );
    }
    out.ok = true;
    return out;
}

// Append `value` unless it is already there. Three of the disclosure lists below are "walk the programs,
// keep one entry per grammar NAME, in table order", and three hand-written copies of that loop is both a
// clone and three chances to get the order wrong. Order-preserving on purpose: table order is what makes
// grammars=/shapes= deterministic without a sort.
inline bool appendUnique( std::vector<std::string>& into, std::string value )
{
    if( std::find( into.begin(), into.end(), value ) != into.end() )
    {
        return false;
    }
    into.push_back( std::move( value ) );
    return true;
}

// Every served grammar NAME, deduplicated, in table order — what a refusal quotes back as "served".
inline std::vector<std::string> servedNames( const std::vector<GrammarRow>& rows )
{
    std::vector<std::string> names;
    for( const GrammarRow& r : rows )
    {
        appendUnique( names, std::string( r.label ) );
    }
    return names;
}

// The grammar NAMES the pattern resolved for, deduplicated, in table order — grammars= on the element.
inline std::vector<std::string> resolvedNames( const PatternProgramSet& set )
{
    std::vector<std::string> names;
    for( const PatternProgram& p : set.programs )
    {
        appendUnique( names, p.label );
    }
    return names;
}

// "name:node_kind" per resolved grammar — shapes= on the element. This is the disclosure that makes the
// per-grammar compile auditable: the reader can see that `foo($A,$B)` became a call_expression in cpp and
// a call in python, rather than having to trust that it became anything sensible at all.
inline std::vector<std::string> resolvedShapes( const PatternProgramSet& set )
{
    std::vector<std::string> shapes, seen;
    for( const PatternProgram& p : set.programs )
    {
        if( appendUnique( seen, p.label ) )
        {
            shapes.push_back( p.label + ":" + p.rootKind );
        }
    }
    return shapes;
}

// ── the matcher ──────────────────────────────────────────────────────────────────────────────────────

// Metavariable bindings for one in-flight match attempt. Fixed size, trivially copyable — the ellipsis
// probe CLONES it so a failed probe can never leak a binding into the surviving environment (ast-grep
// PR #2670, a bug they shipped and had to fix).
struct MatchEnv
{
    TSNode bound[ kMaxMetavars ];
    bool   isBound[ kMaxMetavars ] = {};
};

inline std::string_view nodeText( TSNode n, std::string_view src ) noexcept
{
    const std::uint32_t a = ts_node_start_byte( n ), b = ts_node_end_byte( n );
    if( b <= a || b > src.size() )
    {
        return std::string_view();
    }
    return src.substr( a, b - a );
}

// stripQuotePair lives in infra/namesplit.h (a tree-sitter-free leaf) so lintrules.h, which graph.h
// includes, can share it without pulling <tree_sitter/api.h> into every graph.h consumer (the gate
// harnesses build graph.h with no tree-sitter include path). Spelled pattern::stripQuotePair here, as
// before, so every call site is unchanged.
using namesplit::stripQuotePair;

// Structural equality for metavariable unification (ast-grep does_node_match_exactly). NOT whole-subtree
// text equality: `a + b` and `a  +  b` must unify (only whitespace differs) while `a + b` and `a - b`
// must not, and re-serializing text cannot tell those two cases apart.
inline bool nodesMatchExactly( TSNode a, TSNode b, std::string_view src, unsigned depth = 0 )
{
    if( ts_node_eq( a, b ) )
    {
        return true;
    }
    if( depth > 64 )
    {
        return false;   // bounded like every other recursion here; a pattern this deep is not a pattern
    }
    const std::uint32_t an = ts_node_named_child_count( a ), bn = ts_node_named_child_count( b );
    if( an == 0 || bn == 0 )
    {
        return nodeText( a, src ) == nodeText( b, src );
    }
    if( ts_node_symbol( a ) != ts_node_symbol( b ) || an != bn )
    {
        return false;
    }
    // O(children) on both sides: a bound metavariable and its candidate both come from the FILE, so each
    // list is as wide as the comments in it (a comment is a NAMED extra) — `$X == $X` over two 16 000-comment
    // argument lists measured 126x the plain map (test/childwalkscalecheck.sh, arm B36). a's list is
    // materialised so b's can be walked in lockstep; each frame owns its cursors because the body recurses.
    std::vector<TSNode> aKids;
    aKids.reserve( an );
    {
        ChildCursor aCursor( a );
        forEachNamedChild( a, aCursor.cur, [ & ]( TSNode c ) { aKids.push_back( c ); return true; } );
    }
    bool          same  = true;
    std::uint32_t index = 0;
    ChildCursor   bCursor( b );
    forEachNamedChild( b, bCursor.cur, [ & ]( TSNode bc )
    {
        same = index < aKids.size() && nodesMatchExactly( aKids[ index ], bc, src, depth + 1 );
        ++index;
        return same;
    } );
    return same;
}

// THE CALL-SHAPE TABLE (PATTERN-MEMBER-ZERO, audit-verify 2026-11-11). A bare `f($X)` compiles to a call whose callee
// is an identifier, so it never matches a MEMBER call `obj.f(x)`, whose callee is a member node: textual
// `post_message($X)` answered hits="0" while `$O.post_message($X)` found 173, and nothing said so. Per grammar, the
// node kind a bare call compiles to, the callee kind of the member spelling, and the field of that callee holding the
// member's name. A grammar missing here gets no member count: Java's `obj.f(x)` is the SAME method_invocation node with
// an extra object child, Swift's is a navigation suffix and ObjC's a message expression — each needs matcher work of
// its own, not a row.
struct MemberCallShape
{
    std::string_view grammarName;   // kLangTable querySub, as PatternProgram::grammarName
    std::string_view callKind;      // what a bare `f($X)` became (shapes=)
    std::string_view memberKind;    // the callee node of `$O.f($X)`
    std::string_view nameField;     // the field of memberKind that holds `f`
};

inline constexpr MemberCallShape kMemberCallShapes[] = {
    { "c",          "call_expression",       "field_expression",         "field" },
    { "cpp",        "call_expression",       "field_expression",         "field" },
    { "go",         "call_expression",       "selector_expression",      "field" },
    { "rust",       "call_expression",       "field_expression",         "field" },
    { "javascript", "call_expression",       "member_expression",        "property" },
    { "typescript", "call_expression",       "member_expression",        "property" },
    { "tsx",        "call_expression",       "member_expression",        "property" },
    { "python",     "call",                  "attribute",                "attribute" },
    { "csharp",     "invocation_expression", "member_access_expression", "name" },
};

// V-2 (adversarial verification 2026-08-20). The ellipsis probe ABANDONS a candidate node when the run of
// siblings it would have to absorb exceeds kEllipsisBound — and before this struct existed, that abandon
// was indistinguishable from "this node does not match". A 400-argument `foo(0,…,399, zzz)` that LITERALLY
// matches `foo(...)` produced no row while hits= presented itself as a total (hits_capped="0", capped="0").
// ellipsis_bound= disclosed the limit STATICALLY; nothing said "it bit here", so hits= was a floor that did
// not say so — non-negotiable 3.
//
// One counter, threaded by reference (never copied the way MatchEnv is on a probe), incremented at both
// abandon sites and at neither non-cap failure. It counts ABANDONS, not distinct nodes: one node reached
// under two enclosing probes counts twice, so the number is a FLOOR on nodes left unevaluated and the
// emitted attribute says so. Summation is the only reduction, so the parallel file walk stays deterministic.
struct MatchStats
{
    std::uint64_t ellipsisCappedCount = 0;
    // QUALIFIED-CALLEE NEAR MISSES (lane honesty-cuts-066). The matcher is kind- and text-exact, so a bare callee in the
    // pattern (`escapeXml($X, ...)`) never matches a SCOPE-QUALIFIED spelling of the same name (`rw::escapeXml( s, esc )`):
    // the callee is a qualified_identifier there, not an identifier. On this repository that left 47 such calls out of
    // hits="213" while --uses counted 265, and nothing said so. findMatches now re-asks every candidate the exact match
    // refused with ONE relaxation — a pattern leaf may match the final name segment of a qualified/scoped name — and
    // counts the nodes only that relaxation matches. They are NOT hits (the pattern did not say `rw::`); the count is
    // disclosed as unmatched_qualified= so a reader knows the exact answer left them out and how to spell them in.
    std::uint64_t qualifiedUnmatchedCount = 0;
    bool          relaxQualified          = false;   // set by findMatches for the second ask only
    bool          relaxedLeafHit          = false;   // the second ask used the relaxation at least once
    // MEMBER-CALL NEAR MISSES (PATTERN-MEMBER-ZERO): the third ask, for a node neither the exact match nor the qualified
    // relaxation took. The CALLEE leaf of a call pattern may match the member name of `memberShape`'s callee kind. Never
    // hits; disclosed as unmatched_member= with the `$O.f($X)` spelling as next=. Null shape: the grammar has no row.
    const MemberCallShape* memberShape          = nullptr;
    std::uint64_t          memberUnmatchedCount = 0;
    std::uint64_t          memberCappedCount    = 0;       // third-ask probes the ellipsis bound abandoned: the count is a floor
    std::uint64_t          memberArrowCount     = 0;       // counted calls whose member callee is spelled `->` (C, C++)
    std::uint64_t          memberOptChainCount  = 0;       // counted calls whose member callee is spelled `?.` (JS, TS)
    bool                   relaxMember          = false;   // set for the third ask only
};

bool matchAt( const PatternProgram& prog, std::uint32_t patIndex, TSNode cand, std::string_view src, MatchEnv& env, MatchStats& stats, unsigned depth );

// The child-sequence walk, with the first-match-wins ellipsis probe. Split out of matchAt so neither
// function grows a second concern: matchAt decides what ONE node is, this decides how a LIST lines up.
inline bool matchChildren( const PatternProgram& prog, const PatNode& pat, TSNode cand, std::string_view src, MatchEnv& env, MatchStats& stats, unsigned depth )
{
    // O(children), not O(children²): `cand` is a node of the CORPUS, so its width — and, since comments
    // are extras spliced into the child array, its comment count — comes from the file being searched.
    // A 16 000-comment function body measured 174× the plain map of the same file before this became a
    // cursor (test/childwalkscalecheck.sh, arm B7).
    std::vector<TSNode> kids;
    kids.reserve( ts_node_child_count( cand ) );
    ChildCursor cursor( cand );   // this frame's own — matchAt below recurses back into matchChildren
    forEachChild( cand, cursor.cur, [ &kids ]( TSNode child )
    {
        if( !isCommentKind( ts_node_type( child ) ) )
        {
            kids.push_back( child );   // comments are transparent on the candidate side too
        }
        return true;
    } );

    std::size_t ci = 0;                       // next unconsumed candidate child
    std::size_t pi = 0;                       // next unmatched pattern child
    while( pi < pat.childCount )
    {
        const std::uint32_t patChild = prog.childIndex[ pat.childStart + pi ];
        if( prog.nodes[ patChild ].role != PatRole::Ellipsis )
        {
            if( ci >= kids.size() || !matchAt( prog, patChild, kids[ci], src, env, stats, depth + 1 ) )
            {
                return false;
            }
            ++ci;
            ++pi;
            continue;
        }
        // an ellipsis: collapse any run of them, then find what has to come AFTER
        while( pi < pat.childCount && prog.nodes[ prog.childIndex[ pat.childStart + pi ] ].role == PatRole::Ellipsis )
        {
            ++pi;
        }
        if( pi >= pat.childCount )
        {
            if( kids.size() - ci > kEllipsisBound )
            {
                ++stats.ellipsisCappedCount;   // ABANDON site 1: a trailing ellipsis over too long a sibling run
                return false;                  // the cap — now disclosed per-run, not merely per-constant
            }
            ci = kids.size();
            break;
        }
        const std::uint32_t goal  = prog.childIndex[ pat.childStart + pi ];
        const std::size_t   limit = std::min<std::size_t>( kids.size(), ci + kEllipsisBound + 1 );
        bool                found = false;
        for( std::size_t k = ci; k < limit; ++k )
        {
            MatchEnv probe = env;   // a failed probe must leak nothing
            if( matchAt( prog, goal, kids[k], src, probe, stats, depth + 1 ) )
            {
                env   = probe;
                ci    = k + 1;
                ++pi;
                found = true;
                break;
            }
        }
        if( !found )
        {
            if( limit < kids.size() )
            {
                ++stats.ellipsisCappedCount;   // ABANDON site 2: the forward scan was CUT SHORT by the bound, so
                                               // this "no match" is a fact about the cap, not about the code
            }
            return false;   // a scan that reached kids.size() is a complete answer and is NOT counted
        }
    }
    return ci == kids.size();
}

// The final name segment of a scope-qualified name node (`a::b::c` -> `c`), or a null node when `n` is not one. By node
// TYPE, so one rule serves every grammar that spells it: C/C++/CUDA qualified_identifier, Rust scoped_identifier, C#/PHP
// qualified_name. The `name` field when the grammar has one, else the last named child; a nested qualified name descends.
inline TSNode qualifiedTail( TSNode n ) noexcept
{
    for( unsigned depth = 0; depth < 16 && !ts_node_is_null( n ); ++depth )
    {
        const std::string_view type = ts_node_type( n );
        if( type != "qualified_identifier" && type != "scoped_identifier" && type != "qualified_name" )
        {
            return depth == 0 ? TSNode{} : n;
        }
        TSNode next = ts_node_child_by_field_name( n, "name", 4 );
        if( ts_node_is_null( next ) )
        {
            const std::uint32_t kids = ts_node_named_child_count( n );
            next = kids == 0 ? TSNode{} : ts_node_named_child( n, kids - 1 );
        }
        n = next;
    }
    return TSNode{};
}

// The second ask's one relaxation (MatchStats::qualifiedUnmatchedCount): a pattern LEAF of another kind than `cand`
// still matches when `cand` is a qualified name whose final segment is that leaf, kind and text. Records that it did.
inline bool relaxedQualifiedLeaf( const PatternProgram& prog, const PatNode& pat, TSNode cand, std::string_view src, MatchStats& stats )
{
    if( !stats.relaxQualified || pat.childCount != 0 )
    {
        return false;
    }
    const TSNode tail = qualifiedTail( cand );
    if( ts_node_is_null( tail ) || ts_node_symbol( tail ) != pat.kindId || nodeText( tail, src ) != prog.textOf( pat ) )
    {
        return false;
    }
    stats.relaxedLeafHit = true;
    return true;
}

// The third ask's one relaxation: the call pattern's CALLEE leaf (depth 1, the only childless child of a call root)
// matches a member callee — `memberShape->memberKind` — whose name field spells the same text. Records that it did.
inline bool relaxedMemberLeaf( const PatternProgram& prog, const PatNode& pat, TSNode cand, std::string_view src, MatchStats& stats, unsigned depth )
{
    if( !stats.relaxMember || stats.memberShape == nullptr || depth != 1 || pat.childCount != 0 )
    {
        return false;
    }
    if( std::string_view( ts_node_type( cand ) ) != stats.memberShape->memberKind )
    {
        return false;
    }
    const std::string_view field = stats.memberShape->nameField;
    const TSNode           name  = ts_node_child_by_field_name( cand, field.data(), std::uint32_t( field.size() ) );
    if( ts_node_is_null( name ) || nodeText( name, src ) != prog.textOf( pat ) )
    {
        return false;
    }
    stats.relaxedLeafHit = true;
    return true;
}

// Does the candidate node satisfy pattern node `patIndex`?
inline bool matchAt( const PatternProgram& prog, std::uint32_t patIndex, TSNode cand, std::string_view src, MatchEnv& env, MatchStats& stats, unsigned depth )
{
    if( depth > 128 )
    {
        return false;   // bounded: a pattern cannot out-nest this, and a hostile tree must not recurse us to death
    }
    const PatNode& pat = prog.nodes[ patIndex ];
    if( pat.role == PatRole::Ellipsis )
    {
        return false;   // an ellipsis only ever matches inside a child LIST — matchChildren owns it
    }
    if( pat.role == PatRole::Metavar )
    {
        if( pat.metaIndex == kAnonMeta )
        {
            return true;
        }
        if( env.isBound[ pat.metaIndex ] )
        {
            return nodesMatchExactly( env.bound[ pat.metaIndex ], cand, src );
        }
        env.bound[ pat.metaIndex ]   = cand;
        env.isBound[ pat.metaIndex ] = true;
        return true;
    }
    if( ts_node_symbol( cand ) != pat.kindId )
    {
        return relaxedQualifiedLeaf( prog, pat, cand, src, stats ) || relaxedMemberLeaf( prog, pat, cand, src, stats, depth );   // false outside the second/third ask
    }
    if( pat.childCount == 0 )
    {
        return nodeText( cand, src ) == prog.textOf( pat );
    }
    return matchChildren( prog, pat, cand, src, env, stats, depth );
}

// The second ask for a node the exact match refused: would a qualified spelling of a pattern leaf have matched it?
// Counted, never a hit. Its ellipsis abandons are not the exact answer's, so they are rolled back, not double counted.
// Returns whether it counted the node, so the member ask below never counts the same node twice.
inline bool countQualifiedNearMiss( const PatternProgram& prog, TSNode n, std::string_view src, MatchStats& stats )
{
    const std::uint64_t ellipsisBefore = stats.ellipsisCappedCount;
    MatchEnv            relaxedEnv;
    stats.relaxQualified = true;
    stats.relaxedLeafHit = false;
    const bool relaxedMatch = matchAt( prog, 0, n, src, relaxedEnv, stats, 0 );
    const bool counted      = relaxedMatch && stats.relaxedLeafHit;
    stats.qualifiedUnmatchedCount += counted ? 1u : 0u;
    stats.relaxQualified      = false;
    stats.ellipsisCappedCount = ellipsisBefore;
    return counted;
}

// Which operator spells this member callee: `.`, the arrow (`ptr->f`, an anonymous child) or JS/TS optional chaining
// (`obj?.f`, a named `optional_chain` child)? A pattern spelled `$O.f` matches neither of the last two, so the emitter
// needs both counts to offer a next= that does (PATTERN-OPTCHAIN-NEXT, CodeRabbit #633).
// A cursor walk (PATTERN-ARROW-CURSOR, CodeRabbit #633): a comment can sit between `obj` and `->f`, so the callee's
// child list is as wide as the file makes it, and an indexed ts_node_child loop is quadratic (src/infra/tschildren.h).
enum class MemberOperator : std::uint8_t
{
    Dot,
    Arrow,
    OptionalChain,
};
inline MemberOperator memberCalleeOperator( TSNode callee )
{
    MemberOperator op = MemberOperator::Dot;
    ChildCursor    cursor( callee );
    forEachChild( callee, cursor.cur, [ & ]( TSNode c )
    {
        const std::string_view type( ts_node_type( c ) );
        if( !ts_node_is_named( c ) && type == "->" )
        {
            op = MemberOperator::Arrow;
        }
        else if( ts_node_is_named( c ) && type == "optional_chain" )
        {
            op = MemberOperator::OptionalChain;
        }
        return op == MemberOperator::Dot;
    } );
    return op;
}

// The third ask (PATTERN-MEMBER-ZERO), same contract as the second: counted, never a hit. Its ellipsis abandons are
// rolled back out of ellipsis_capped= (the exact answer's fact) and kept in memberCappedCount, so a member call the
// bound skipped labels unmatched_member= a floor instead of vanishing (CR #624). Asked only when the node's callee IS
// the grammar's member kind, so an ordinary refused call costs one type compare.
inline void countMemberNearMiss( const PatternProgram& prog, TSNode n, std::string_view src, MatchStats& stats )
{
    if( stats.memberShape == nullptr || ts_node_named_child_count( n ) == 0
        || std::string_view( ts_node_type( ts_node_named_child( n, 0 ) ) ) != stats.memberShape->memberKind )
    {
        return;
    }
    const std::uint64_t ellipsisBefore = stats.ellipsisCappedCount;
    MatchEnv            relaxedEnv;
    stats.relaxMember    = true;
    stats.relaxedLeafHit = false;
    const bool relaxedMatch = matchAt( prog, 0, n, src, relaxedEnv, stats, 0 );
    const bool counted      = relaxedMatch && stats.relaxedLeafHit;
    stats.memberUnmatchedCount += counted ? 1u : 0u;
    const MemberOperator op = counted ? memberCalleeOperator( ts_node_named_child( n, 0 ) ) : MemberOperator::Dot;
    stats.memberArrowCount += op == MemberOperator::Arrow ? 1u : 0u;
    stats.memberOptChainCount += op == MemberOperator::OptionalChain ? 1u : 0u;
    stats.memberCappedCount += stats.ellipsisCappedCount - ellipsisBefore;
    stats.relaxMember         = false;
    stats.ellipsisCappedCount = ellipsisBefore;
}

// Every node in one file's tree that the pattern matches, reported as [startByte,endByte) pairs in
// ascending start order. Explicit stack, never recursion: a generated file nests thousands of nodes deep
// (the YAML grammar's 254-level indent bug is the standing reminder) and a search pass may not be the
// thing that overflows the stack. A matched node is still descended into, so `foo(foo(a))` reports both.
inline void findMatches( const PatternProgram& prog, TSNode root, std::string_view src,
                         std::vector<std::pair<std::uint32_t, std::uint32_t>>& out, std::size_t budget, MatchStats& stats )
{
    if( !prog.ok() )
    {
        return;
    }
    const std::uint16_t rootKindId = prog.nodes[0].kindId;
    // the program's member-call row: kMemberCallShapes holds ONE row per grammar, and it applies only to a CALL pattern
    const MemberCallShape* shape   = findByField( kMemberCallShapes, &MemberCallShape::grammarName, std::string_view( prog.grammarName ) );
    stats.memberShape              = ( shape != nullptr && shape->callKind == prog.rootKind ) ? shape : nullptr;
    std::vector<TSNode> stack;
    std::vector<TSNode> kids;     // reused across nodes — a warm walk allocates nothing per node
    ChildCursor         cursor( root );
    stack.push_back( root );
    while( !stack.empty() && out.size() < budget )
    {
        const TSNode n = stack.back();
        stack.pop_back();
        if( ts_node_symbol( n ) == rootKindId )
        {
            MatchEnv env;
            if( matchAt( prog, 0, n, src, env, stats, 0 ) )
            {
                out.emplace_back( ts_node_start_byte( n ), ts_node_end_byte( n ) );
            }
            else if( !countQualifiedNearMiss( prog, n, src, stats ) )
            {
                countMemberNearMiss( prog, n, src, stats );
            }
        }
        // Collected once, then pushed in REVERSE so the stack pops left to right — the same visit order
        // the indexed loop had, at O(children) instead of O(children²) (src/infra/tschildren.h).
        collectChildren( n, cursor.cur, kids );
        for( std::size_t c = kids.size(); c > 0; --c )
        {
            stack.push_back( kids[ c - 1 ] );
        }
    }
    std::sort( out.begin(), out.end() );
}

}   // namespace pattern
}   // namespace rw
