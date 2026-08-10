#pragma once

// nonlocalstate.h — `--nonlocal-state`: per function, the NON-LOCAL MUTABLE STATE it can reach, with
// READS and WRITES kept apart.
//
// WHAT IT MEASURES. A "cell" is one piece of mutable data declared outside any function's local scope: a
// file-scope or namespace-scope variable, a function-local `static` (local in name only — it outlives every
// call), or a Python module global. For every function and method the lens reports the set of cells that
// function — or anything in its transitive callee closure — READS, and the set it WRITES, as two separate
// numbers, plus the specific site or callee that puts each cell in the set. Direction is not a decoration:
// Henry & Kafura's 1981 information-flow measure already separated the two, and a function that only reads
// a global is a very different comprehension problem from one that writes it.
//
// LANGUAGE COVERAGE IS C++, OBJC AND PYTHON, and the reason is a hard one — see kAnalyzedLangs below. Every
// other indexed language is named on the root as unanalyzed_langs=, never scored zero.
//
// WHY THIS AND NOT AN EXISTING METRIC — the lineage, stated so the delta is arguable rather than assumed:
//   • Fowler's GLOBAL DATA and MUTABLE DATA smells (Refactoring 2nd ed., 2018) name exactly this hazard
//     and stop there: prose, no metric, no threshold, no detector. This is the missing numeric side.
//   • Marinescu's ATFD — Access To Foreign Data (ICSM 2004 detection strategies) — is the closest
//     published NUMBER: how many OTHER classes' attributes a class touches directly or via accessors.
//     ATFD counts foreign INSTANCE data reached one hop, per class, in Java. This counts non-local
//     MUTABLE data reached TRANSITIVELY, per function, across languages, and splits read from write.
//   • The standard encapsulation metrics are declared-visibility counting and nothing more. QMOOD's DAM
//     (Bansiya & Davis, TSE 2002) is (private+protected attributes)/(total attributes); MOOD's AHF/MHF
//     (Brito e Abreu 1994) are system-level averages of the same syntax. All are blind to aliasing and to
//     escape: a class whose fields are 100% private and whose getters hand out mutable internal
//     collections scores DAM = 1.0. This lens counts what code actually touches, so a private field
//     mutated through a leaked reference is not scored as encapsulated — and, conversely, a `const`
//     declaration is not scored as state at all, whatever its visibility.
//   • The one published MEASUREMENT of externally-reachable state is Potanin, Noble & Biddle, "Checking
//     Ownership and Confinement" (Concurrency & Computation 16(7):671-687, 2004): dominator-based
//     ownership over JAVA HEAP SNAPSHOTS, with the `Fox` tool, which was never maintained. It is
//     DYNAMIC, single-language, and needs a running program. A static, source-level, cross-language
//     approximation is what is offered here — strictly weaker evidence, available before you run anything.
//   • Slice-based coupling (Meyers & Binkley, TOSEM 2007) already puts globals in its output set, so the
//     delta has to be argued precisely rather than waved at. A slice is computed per VARIABLE over a
//     dataflow/dependence graph and answers "what statements affect this value"; the globals appear
//     inside the slice as a by-product. This runs the other direction — per FUNCTION, over the CALL
//     graph, name-resolved rather than dependence-resolved — and reports the cells themselves as the
//     result with their direction, not the statements. It is much cheaper and much weaker: it has no
//     dependence graph, so it cannot say a write is dead, and it is polyglot, which no slicer is.
//
// SOUNDNESS — THE PART THAT MUST NOT BE OVERSOLD. This analysis is UNSOUND in general and the output
// says so in every count. In C++ especially, a pointer or reference can alias a global with no textual
// mention of its name; an indirect call through a virtual, an unbound/reassigned function pointer or
// callback, or an unindexed macro contributes no call edge, so the closure stops early; a macro can name a global that never appears as
// an identifier in the tree; a local variable that shadows a global name is charged to the global unless
// ingest happened to record a type binding for it. Every one of those failures makes the count TOO LOW
// or (for shadowing) too high in a way this pass cannot see. Hence: every count is a FLOOR
// (counts_floor="1"), the legend names the blind spots where the reader meets them, and a zero means
// "none found", never "none exists". An unsound number presented as exact is the failure mode this
// header exists to avoid.
//
// DETERMINISM. Cells are discovered in the astQuery pass's own (path, startByte) order; the fixpoint is a
// monotone bit union, so its result does not depend on visit order; rows and children are fully sorted
// before emission; nothing iterates a HashMap into output.

#include "model.h"
#include "graph.h"              // Graph (in/out CSR) + langCompatible — the same call graph every reach verb walks
#include "ingest.h"             // AstQuerySpec / AstMatch / astQuery — the shared re-parse pass --lint already runs
#include "flipimpact.h"         // buildSymbolLineIndex / innermostAtLine — the shared line -> innermost-def lookup
#include "docdrift.h"           // hasWholeWord — THE house whole-word predicate (so `const_cast` never satisfies `const`)
#include "pageview.h"           // pageWindow + pageDisclosure — THE TRUNCATION VOCABULARY
#include "serialize.h"          // escapeXml
#include "graphlegend.h"        // kGraphCountFloorAttrXml — the shared floor marker
#include "infra/Diagnostics.h"  // DEGRADED_PATH_ALERT — a blind spot degrades the report, never aborts it

#include <algorithm>
#include <array>
#include <bit>
#include <cstdint>
#include <cstdio>
#include <span>          // std::span — enclosingDecl reads whichever contiguous bucket the caller holds
#include <string>
#include <string_view>
#include <utility>
#include <vector>

namespace rw::nonlocal
{

// The display cap, in the same shape as --readability's 40: raisable with --limit, paged with --offset.
inline constexpr std::size_t kRowCap = 40;

// Cells per row. A function that reaches 300 globals has already told the reader what it needed to; the
// list is evidence, not an inventory. Truncation is disclosed per row (cells_shown/cells_capped).
inline constexpr std::size_t kCellsPerRowCap = 12;

// The bitset width ceiling. Two bitsets per symbol at this width is the whole memory cost of the closure
// (symbols x 2 x kMaxCells/8 bytes), so it is a real budget and not a taste. Saturation is disclosed.
inline constexpr std::size_t kMaxCells = 2048;

// The per-rule astQuery budget. Above --lint's 5000 because a declaration pattern legitimately fires on
// every file; saturation is disclosed as decls_capped="1" rather than silently truncating the corpus.
inline constexpr std::size_t kDeclMatchBudget = 40000;

// WHERE a cell's name may be matched — the linkage question, answered per declaration form rather than
// guessed. Ordered by SPECIFICITY (Function is narrowest): when one name has candidates at several
// scopes, the narrowest match wins, which is what the language's own lookup would do.
enum class CellScope : std::uint8_t { Global = 0, File = 1, Function = 2 };

// How the rule decides a declaration is MUTABLE, from the declaration text that precedes the declared
// name. Two real rules, because the covered families spell mutability two different ways.
enum class MutRule : std::uint8_t
{
    RejectImmutablePrefix,   // C++/ObjC: mutable UNLESS the prefix carries const/constexpr/consteval
    AlwaysMutable            // Python: the matched declaration form has no immutable spelling at all
};

// One declaration FORM to look for. Two tree-sitter queries per form, differing only in what they capture:
// `declQuery` binds the whole declaration (so the mutability test can read the specifiers that precede the
// name) and `nameQuery` binds the declared identifier. They are separate SPECS rather than two captures of
// one spec because astQuery tags a spec, not a capture — separate tags are what lets the join below tell a
// declaration row from a name row without guessing from span shapes.
struct CellRule
{
    std::string_view tag;                  // routing key; the emitted tags are tag+".d" and tag+".n"
    std::string_view declQuery;
    std::string_view nameQuery;
    CellScope        scope;                // the DEFAULT scope for this form
    MutRule          mut;
    bool             staticNarrowsScope;   // C family: a `static` prefix means internal linkage -> File
};

// The C-family declarator alternation, shared by the translation-unit and namespace forms: the four
// nestings a data declarator actually takes (plain / pointer / array / pointer-to-array), with and
// without an initializer. Spelled once.
#define RW_NLS_C_DECLARATORS                                                     \
    "[ (init_declarator declarator: [ (identifier) @n "                          \
    "                                 (pointer_declarator declarator: (identifier) @n) " \
    "                                 (array_declarator declarator: (identifier) @n) "   \
    "                                 (pointer_declarator declarator: (array_declarator declarator: (identifier) @n)) ]) " \
    "  (identifier) @n "                                                         \
    "  (pointer_declarator declarator: (identifier) @n) "                        \
    "  (array_declarator declarator: (identifier) @n) ]"

#define RW_NLS_C_DECLARATORS_NONAME                                              \
    "[ (init_declarator declarator: [ (identifier) "                             \
    "                                 (pointer_declarator declarator: (identifier)) " \
    "                                 (array_declarator declarator: (identifier)) "   \
    "                                 (pointer_declarator declarator: (array_declarator declarator: (identifier))) ]) " \
    "  (identifier) "                                                            \
    "  (pointer_declarator declarator: (identifier)) "                           \
    "  (array_declarator declarator: (identifier)) ]"

// THE RULE TABLE. Declarative, not a switch chain. astQuery compiles each query against every grammar it
// is VALID for and silently skips the rest, so a C-family pattern simply never fires on a .py file — which
// is what makes one flat table a cross-language analysis instead of a per-language dispatch.
inline constexpr std::array<CellRule, 4> kCellRules = { {
    // C++ / ObjC — translation-unit scope. `static` narrows to the file (internal linkage).
    { "ctu",
      "(translation_unit (declaration declarator: " RW_NLS_C_DECLARATORS_NONAME ") @d)",
      "(translation_unit (declaration declarator: " RW_NLS_C_DECLARATORS "))",
      CellScope::Global, MutRule::RejectImmutablePrefix, true },
    // C++ — namespace scope (`declaration_list` is a namespace / extern-block body).
    { "cns",
      "(declaration_list (declaration declarator: " RW_NLS_C_DECLARATORS_NONAME ") @d)",
      "(declaration_list (declaration declarator: " RW_NLS_C_DECLARATORS "))",
      CellScope::Global, MutRule::RejectImmutablePrefix, true },
    // C++ / ObjC — a function-local `static`: local in name only, it outlives every call. Scoped to the
    // enclosing function, which makes it the one cell class this pass can match with no ambiguity at all.
    { "cfnstatic",
      "(compound_statement (declaration (storage_class_specifier) declarator: " RW_NLS_C_DECLARATORS_NONAME ") @d)",
      "(compound_statement (declaration (storage_class_specifier) declarator: " RW_NLS_C_DECLARATORS "))",
      CellScope::Function, MutRule::RejectImmutablePrefix, false },
    // Python — a module-level binding. Python has no immutable binding form, so every one of them is a cell
    // (an ALL-CAPS name is a convention, not a language guarantee, and this lens does not grade conventions).
    { "py",
      "(module (expression_statement (assignment left: (identifier)) @d))",
      "(module (expression_statement (assignment left: (identifier) @n)))",
      CellScope::File, MutRule::AlwaysMutable, false },
} };

// THE COVERAGE CEILING, AND WHY IT IS WHERE IT IS. A cell is only half the measurement; the other half is
// the ACCESS, and accesses come from ingest's read/write use-site index (RefRole::Read / RefRole::Write),
// which ingest.cpp captures for C++, ObjC and Python ONLY — those are the grammars whose assignment and
// update shapes `isWriteTarget` knows, and writing a "write" it cannot actually tell from a read would be
// worse than not answering. So this lens is scoped to exactly those three: a Go or Rust file WOULD yield
// cells from a query, and every one of them would then report zero accessors — a confident, wrong zero, and
// the single failure mode CLAUDE.md's non-negotiable #3 forbids. Widening the lens therefore means widening
// `captureUses` in ingest.cpp FIRST (with its own gate and a kParserVer bump), not adding a rule here.
// Every other indexed language is named on the root as unanalyzed_langs= rather than silently scoring 0.
inline constexpr std::array<Lang, 3> kAnalyzedLangs = { Lang::Cpp, Lang::ObjC, Lang::Python };

inline bool isAnalyzedLang( Lang l ) noexcept
{
    return std::ranges::find( kAnalyzedLangs, l ) != kAnalyzedLangs.end();
}

// The indexed languages this lens does NOT analyse — the ones the root names, so their absence from the
// report reads as "not measured" and never as "measured, found nothing". A declarative table, not a switch
// chain. Markdown, JSON and TOML are deliberately absent: they hold no functions, so naming them would be
// noise rather than a disclosure. The emission order is this table's order, which makes it deterministic.
struct UnanalyzedLang { Lang lang; std::string_view name; };
inline constexpr std::array<UnanalyzedLang, 10> kUnanalyzedLangs = { {
    { Lang::C, "c" }, { Lang::Go, "go" }, { Lang::Rust, "rust" },
    { Lang::JavaScript, "javascript" }, { Lang::TypeScript, "typescript" },
    { Lang::Java, "java" }, { Lang::CSharp, "csharp" }, { Lang::Swift, "swift" },
    { Lang::Ruby, "ruby" }, { Lang::Bash, "bash" } } };

// The immutability keywords of the covered families. A declaration prefix carrying any of these is not
// mutable state. Conservative on purpose: a type argument that merely MENTIONS const (`vector<const T*> v`)
// drops a genuinely mutable cell, which is the direction a floor is allowed to be wrong in. Each spelling
// is listed separately because the match is WHOLE-WORD (docdrift::hasWholeWord — the house predicate, reused
// rather than re-rolled): "const" does not cover "constexpr", and neither of them matches `const_cast`.
inline constexpr std::array<std::string_view, 3> kImmutableWords = { "const", "constexpr", "consteval" };

inline bool prefixSaysImmutable( std::string_view prefix )
{
    return std::ranges::any_of( kImmutableWords, [ & ]( std::string_view w ) { return docdrift::hasWholeWord( prefix, w ); } );
}

// ── the model ────────────────────────────────────────────────────────────────────────────────────────

// One piece of non-local mutable state. POD-ish; the vector of these is the cell universe the bitsets index.
struct Cell
{
    std::string   name;
    std::uint32_t fileId = 0;
    std::uint32_t line   = 0;
    CellScope     scope  = CellScope::Global;
    Lang          lang   = Lang::Unknown;
    NodeId        owner  = kNoNode;   // Function scope only: the function the `static` lives in
};

// One DIRECT access: a function touching a cell at a named site. The transitive closure is bits; this is
// the evidence, kept so a reader can see why a row says what it says.
struct AccessSite
{
    NodeId        fn      = kNoNode;
    std::uint32_t cell    = 0;
    std::uint32_t fileId  = 0;
    std::uint32_t line    = 0;
    bool          isWrite = false;
};

// One emitted cell child, resolved down to exactly the evidence the reader needs.
struct RowCell
{
    std::uint32_t cell        = 0;
    bool          read        = false;   // dir=: the UNION over this function's own body and its callee closure
    bool          write       = false;
    bool          direct      = false;
    bool          directRead  = false;   // at_dir=: what the OWN-BODY sites do, which can be narrower than dir=
    bool          directWrite = false;
    std::uint32_t siteFile    = 0;       // direct only
    std::uint32_t siteLine    = 0;       // direct only
    NodeId        via         = kNoNode; // transitive only: the nearest callee that touches the cell directly
};

struct Row
{
    NodeId               fn = kNoNode;
    std::uint32_t        writeCount = 0;
    std::uint32_t        readCount  = 0;
    std::uint32_t        directWriteCount = 0;
    std::uint32_t        directReadCount  = 0;
    std::vector<RowCell> cells;
};

struct Scan
{
    std::vector<Cell> cells;
    std::vector<Row>  rows;
    std::uint32_t     unanalyzedFileCount = 0;
    std::string       unanalyzedLangs;                 // comma-joined, deterministic order
    std::uint32_t     undecidedDeclCount  = 0;         // declarations whose prefix was truncated past the decision
    bool              cellsCapped         = false;
    bool              declsCapped         = false;
};

// ── discovery ────────────────────────────────────────────────────────────────────────────────────────

// The declaration row that ENCLOSES a name row. Declaration forms do not nest at the scopes the table
// matches, so "the last declaration starting at or before the name, that also ends at or after it" is
// exact, not a heuristic. Rows arrive sorted by (path, startByte, endByte), so the bucket is sorted too.
inline const AstMatch* enclosingDecl( std::span<const AstMatch* const> bucket, const AstMatch& name ) noexcept
{
    if( bucket.empty() )
    {
        return nullptr;
    }
    std::size_t lo = 0, hi = bucket.size();   // last index with startByte <= name.startByte
    while( lo < hi )
    {
        const std::size_t mid = lo + ( hi - lo ) / 2;
        if( bucket[mid]->startByte <= name.startByte )
        {
            lo = mid + 1;
        }
        else
        {
            hi = mid;
        }
    }
    if( lo == 0 )
    {
        return nullptr;
    }
    const AstMatch* d = bucket[lo - 1];
    return ( d->endByte >= name.endByte ) ? d : nullptr;
}

// Find the cell universe: run every rule's two queries through the shared astQuery pass, join each name
// back to its declaration, apply the form's mutability test to the text that PRECEDES the name, and keep
// what survives. Deduplicated by (scope key, name) so a header included many times contributes one cell.
inline void discoverCells( const IngestResult& ing, Scan& scan )
{
    std::vector<AstQuerySpec> specs;
    specs.reserve( kCellRules.size() * 2 );
    for( const CellRule& r : kCellRules )
    {
        specs.push_back( { std::string( r.declQuery ), std::string( r.tag ) + ".d" } );
        specs.push_back( { std::string( r.nameQuery ), std::string( r.tag ) + ".n" } );
    }

    const std::vector<AstMatch> matches = astQuery( ing, specs, kDeclMatchBudget );

    // Bucket the DECLARATION rows by (rule, file) for the join. A HashMap is a lookup structure only —
    // nothing here iterates it, so its order never reaches output.
    // N=4. The element is a bare `const AstMatch*` — 8 bytes, trivially copyable, so rw::svector takes it
    // and the free-N-is-2 rule for 4-byte elements does not apply: <ptr,1> is 16 B, <ptr,2> is 24 B (what a
    // std::vector already costs), <ptr,4> is 40 B. Coverage runs 28.7/43.7/59.2/85.6% here and
    // 36.0/50.3/68.7/82.2% on the validation corpus for N=1/2/4/8, and marginal coverage per byte falls
    // 1.79 → 1.15 → 0.42 across 1→2→4→8 there, so the knee is N=4. Absolute cost is trivial either way —
    // 174/600 buckets — and what this buys is that the (rule, file) join stops making a heap block per key.
    HashMap<std::string, rw::SmallVec<const AstMatch*, 4>> declBuckets;
    std::vector<std::size_t>                          keptPerTag( kCellRules.size() * 2, 0 );
    for( const AstMatch& m : matches )
    {
        const std::size_t dot = m.tag.rfind( '.' );
        if( dot == std::string::npos || m.tag.compare( dot, 2, ".d" ) != 0 )
        {
            continue;
        }
        declBuckets[ m.tag + "#" + std::to_string( m.fileId ) ].push_back( &m );
    }
    for( const AstMatch& m : matches )
    {
        for( std::size_t ruleIndex = 0; ruleIndex < kCellRules.size(); ++ruleIndex )
        {
            if( m.tag.size() > 2 && m.tag.compare( 0, m.tag.size() - 2, kCellRules[ruleIndex].tag ) == 0 )
            {
                keptPerTag[ ruleIndex * 2 + ( m.tag.compare( m.tag.size() - 2, 2, ".d" ) == 0 ? 0 : 1 ) ]++;
                break;
            }
        }
    }
    for( std::size_t kept : keptPerTag )
    {
        if( kept >= kDeclMatchBudget )
        {
            scan.declsCapped = true;
        }
    }

    const flipimpact::SymbolLineIndex lineIndex = flipimpact::buildSymbolLineIndex( ing );
    HashMap<std::string, std::uint32_t> seen;   // dedup key -> cell index (lookup only; never iterated)

    for( const AstMatch& m : matches )
    {
        if( m.tag.size() < 3 || m.tag.compare( m.tag.size() - 2, 2, ".n" ) != 0 )
        {
            continue;
        }
        // The coverage ceiling, enforced at the one place it can be: a C-family query compiles against the
        // C grammar too, so a .c file WOULD yield cells here that no access could ever reach (see the note
        // on kAnalyzedLangs). Drop them at discovery so cells= counts only what the lens can actually answer.
        if( m.fileId >= ing.files.size() || !isAnalyzedLang( langOfPath( ing.files[m.fileId] ) ) )
        {
            continue;
        }
        const std::string_view base( m.tag.data(), m.tag.size() - 2 );
        const CellRule*        rule = nullptr;
        for( const CellRule& r : kCellRules )
        {
            if( r.tag == base )
            {
                rule = &r;
                break;
            }
        }
        if( rule == nullptr )
        {
            continue;
        }

        const auto bucketIt = declBuckets.find( std::string( base ) + ".d#" + std::to_string( m.fileId ) );
        if( bucketIt == declBuckets.end() )
        {
            continue;
        }
        const AstMatch* decl = enclosingDecl( bucketIt->second, m );
        if( decl == nullptr )
        {
            continue;
        }

        // The mutability decision reads ONLY the bytes between the declaration's start and the declared
        // name — the specifiers. astQuery caps its text at 120 bytes; a name that starts past the cap
        // leaves the decision UNDECIDABLE, and an undecidable declaration is DROPPED (a floor may
        // under-count; it may not invent a cell) and counted so the drop is visible.
        const std::size_t prefixLen = m.startByte - decl->startByte;
        if( prefixLen > decl->text.size() )
        {
            ++scan.undecidedDeclCount;
            continue;
        }
        const std::string_view prefix( decl->text.data(), prefixLen );
        if( rule->mut == MutRule::RejectImmutablePrefix && prefixSaysImmutable( prefix ) )
        {
            continue;
        }

        Cell cell;
        cell.name   = m.text;
        cell.fileId = m.fileId;
        cell.line   = m.line;
        cell.scope  = rule->scope;
        cell.lang   = m.fileId < ing.files.size() ? langOfPath( ing.files[m.fileId] ) : Lang::Unknown;
        if( rule->staticNarrowsScope && docdrift::hasWholeWord( prefix, "static" ) )
        {
            cell.scope = CellScope::File;   // internal linkage: the name is not visible outside this file
        }
        if( cell.scope == CellScope::Function )
        {
            cell.owner = flipimpact::innermostAtLine( ing, lineIndex, cell.fileId, cell.line );
            if( cell.owner == kNoNode )
            {
                continue;   // a `static` in a body tree-sitter did not attribute to a def — no scope to match in
            }
        }

        std::string key;
        key.reserve( cell.name.size() + 24 );
        key += char( '0' + static_cast<int>( cell.scope ) );
        key += '\x1f';
        if( cell.scope == CellScope::Function )
        {
            key += std::to_string( cell.owner );
        }
        else if( cell.scope == CellScope::File )
        {
            key += std::to_string( cell.fileId );
        }
        key += '\x1f';
        key += cell.name;
        if( seen.find( key ) != seen.end() )
        {
            continue;
        }
        if( scan.cells.size() >= kMaxCells )
        {
            scan.cellsCapped = true;
            break;
        }
        seen[key] = static_cast<std::uint32_t>( scan.cells.size() );
        scan.cells.push_back( std::move( cell ) );
    }
}

// ── attribution ──────────────────────────────────────────────────────────────────────────────────────

// Does this reference site fall inside the cell's scope? Function scope is exact (the `static` and the use
// share one body); File scope is exact for both forms that carry it (C++ internal linkage, a Python module
// binding); Global scope is the one that GUESSES — a C++ external-linkage name is matched repo-wide by name
// across language-compatible files, which is where a same-named global in an unrelated file would collide.
// The narrowest scope that matches wins, so the caller tries candidates in specificity order.
inline bool siteInScope( const Cell& cell, const Reference& ref )
{
    switch( cell.scope )
    {
        case CellScope::Function: return cell.owner == ref.fromSymbol;
        case CellScope::File:     return cell.fileId == ref.fileId;
        case CellScope::Global:   return langCompatible( cell.lang, ref.lang );
    }
    return false;
}

// Every DIRECT read/write of a cell by a function, in deterministic order. Two filters carry the whole
// precision story and both are named in the legend:
//   • the enclosing symbol must be a FUNCTION or METHOD — which also excludes a cell's own initializer,
//     whose enclosing symbol is the declaration itself (Python indexes a module binding as a def);
//   • a name the enclosing function locally BINDS (ingest's Rule-2 var->type records) is a shadow, not
//     the cell, and is dropped. Those records cover typed/constructed locals only, so shadowing is
//     reduced, not eliminated — the legend says exactly that.
inline std::vector<AccessSite> collectAccesses( const IngestResult& ing, const std::vector<Cell>& cells )
{
    std::vector<AccessSite> sites;
    if( cells.empty() )
    {
        return sites;
    }

    HashMap<std::string, std::vector<std::uint32_t>> byName;   // lookup only; never iterated into output
    for( std::uint32_t cellIndex = 0; cellIndex < cells.size(); ++cellIndex )
    {
        byName[ cells[cellIndex].name ].push_back( cellIndex );
    }
    HashMap<std::string, char> locallyBound;                   // "fromSymbol\x1fvar" -> 1
    for( const Binding& b : ing.bindings )
    {
        if( b.fromSymbol != kNoNode )
        {
            locallyBound[ std::to_string( b.fromSymbol ) + "\x1f" + b.var ] = 1;
        }
    }

    for( const Reference& ref : ing.references )
    {
        if( ref.role != RefRole::Read && ref.role != RefRole::Write )
        {
            continue;
        }
        if( ref.fromSymbol == kNoNode || ref.fromSymbol >= ing.symbols.size() )
        {
            continue;
        }
        const SymKind hostKind = ing.symbols[ref.fromSymbol].kind;
        if( hostKind != SymKind::Function && hostKind != SymKind::Method )
        {
            continue;
        }
        const auto it = byName.find( ref.calleeName );
        if( it == byName.end() )
        {
            continue;
        }
        if( locallyBound.find( std::to_string( ref.fromSymbol ) + "\x1f" + ref.calleeName ) != locallyBound.end() )
        {
            continue;   // the enclosing function declares this name itself — a shadow, not the cell
        }

        std::uint32_t best      = UINT32_MAX;
        int           bestScope = -1;
        for( std::uint32_t cellIndex : it->second )
        {
            if( !siteInScope( cells[cellIndex], ref ) )
            {
                continue;
            }
            const int rank = static_cast<int>( cells[cellIndex].scope );
            if( rank > bestScope || ( rank == bestScope && cellIndex < best ) )
            {
                best      = cellIndex;
                bestScope = rank;
            }
        }
        if( best == UINT32_MAX )
        {
            continue;
        }
        sites.push_back( { ref.fromSymbol, best, ref.fileId, ref.line, ref.role == RefRole::Write } );
    }

    std::sort( sites.begin(), sites.end(),
               [ & ]( const AccessSite& a, const AccessSite& b )
               {
                   if( a.fn != b.fn )         { return a.fn < b.fn; }
                   if( a.cell != b.cell )     { return a.cell < b.cell; }
                   if( a.isWrite != b.isWrite ) { return static_cast<int>( a.isWrite ) > static_cast<int>( b.isWrite ); }
                   if( a.fileId != b.fileId ) { return ing.files[a.fileId] < ing.files[b.fileId]; }
                   return a.line < b.line;
               } );
    return sites;
}

// ── the closure ──────────────────────────────────────────────────────────────────────────────────────

// A dense per-symbol bit matrix over the cell universe. Two of these (read, write) ARE the closure state.
struct BitMatrix
{
    std::size_t                words = 0;
    std::vector<std::uint64_t> bits;

    void init( std::size_t rowCount, std::size_t cellCount )
    {
        words = ( cellCount + 63 ) / 64;
        bits.assign( rowCount * words, 0ull );
    }
    bool set( std::size_t row, std::size_t cell ) noexcept
    {
        std::uint64_t&      w    = bits[ row * words + cell / 64 ];
        const std::uint64_t mask = 1ull << ( cell % 64 );
        const bool          was  = ( w & mask ) != 0;
        w |= mask;
        return !was;
    }
    bool test( std::size_t row, std::size_t cell ) const noexcept
    {
        return ( bits[ row * words + cell / 64 ] & ( 1ull << ( cell % 64 ) ) ) != 0;
    }
    // OR `from`'s row into `into`'s row; true when a bit was actually added.
    bool unionInto( std::size_t into, std::size_t from ) noexcept
    {
        bool changed = false;
        for( std::size_t w = 0; w < words; ++w )
        {
            const std::uint64_t before = bits[ into * words + w ];
            const std::uint64_t after  = before | bits[ from * words + w ];
            if( after != before )
            {
                bits[ into * words + w ] = after;
                changed                  = true;
            }
        }
        return changed;
    }
    std::uint32_t popcount( std::size_t row ) const noexcept
    {
        std::uint32_t n = 0;
        for( std::size_t w = 0; w < words; ++w )
        {
            n += static_cast<std::uint32_t>( std::popcount( bits[ row * words + w ] ) );
        }
        return n;
    }
};

// Push each symbol's set up to its CALLERS until nothing changes. Monotone bit union, so the fixpoint is
// independent of the visit order — the one property that makes a worklist safe here at all. The `pending`
// flag keeps the queue free of duplicates; the queue is a plain vector used as a stack.
inline void propagateToCallers( const Graph& g, std::size_t symbolCount, BitMatrix& readBits, BitMatrix& writeBits,
                                const std::vector<char>& hasDirect )
{
    const auto*       rowOffsets = g.inEdges.rowOffsets();
    const auto*       colIndices = g.inEdges.colIndices();
    std::vector<char> pending( symbolCount, 0 );
    std::vector<NodeId> work;
    work.reserve( symbolCount );
    for( std::size_t i = 0; i < symbolCount; ++i )
    {
        if( hasDirect[i] != 0 )
        {
            work.push_back( static_cast<NodeId>( i ) );
            pending[i] = 1;
        }
    }
    while( !work.empty() )
    {
        const NodeId target = work.back();
        work.pop_back();
        pending[target] = 0;
        for( std::uint32_t k = rowOffsets[target]; k < rowOffsets[target + 1]; ++k )
        {
            const NodeId caller = colIndices[k];
            if( caller >= symbolCount || caller == target )
            {
                continue;
            }
            bool changed = readBits.unionInto( caller, target );
            changed      = writeBits.unionInto( caller, target ) || changed;
            if( changed && pending[caller] == 0 )
            {
                pending[caller] = 1;
                work.push_back( caller );
            }
        }
    }
}

// Hop distance from `fn` to every symbol it can reach, over the call graph's out-edges. Used ONLY for the
// emitted rows (at most the page's worth), to name the NEAREST callee that explains a transitive cell.
inline std::vector<std::uint32_t> forwardHops( const Graph& g, std::size_t symbolCount, NodeId fn )
{
    std::vector<std::uint32_t> hop( symbolCount, UINT32_MAX );
    if( fn >= symbolCount )
    {
        return hop;
    }
    std::vector<NodeId> frontier{ fn }, next;
    hop[fn] = 0;
    for( std::uint32_t depth = 1; !frontier.empty(); ++depth )
    {
        next.clear();
        for( NodeId u : frontier )
        {
            if( u + 1 >= g.outOff.size() )
            {
                continue;
            }
            for( std::uint32_t k = g.outOff[u]; k < g.outOff[u + 1]; ++k )
            {
                const NodeId v = g.outTargets[k];
                if( v < symbolCount && hop[v] == UINT32_MAX )
                {
                    hop[v] = depth;
                    next.push_back( v );
                }
            }
        }
        frontier.swap( next );
    }
    return hop;
}

// ── the pass ─────────────────────────────────────────────────────────────────────────────────────────

inline Scan computeNonLocalState( const IngestResult& ing, const Graph& g )
{
    Scan scan;

    // Honesty first, before any measuring: which indexed files carry a language this lens cannot answer for.
    // Emitted in kUnanalyzedLangs' own order, so the attribute is deterministic without a sort.
    std::array<std::uint32_t, 16> filesByLang{};
    for( const std::string& path : ing.files )
    {
        if( const std::size_t index = static_cast<std::size_t>( langOfPath( path ) ); index < filesByLang.size() )
        {
            ++filesByLang[index];
        }
    }
    for( const UnanalyzedLang& u : kUnanalyzedLangs )
    {
        const std::size_t index = static_cast<std::size_t>( u.lang );
        if( index >= filesByLang.size() || filesByLang[index] == 0 )
        {
            continue;
        }
        scan.unanalyzedFileCount += filesByLang[index];
        if( !scan.unanalyzedLangs.empty() )
        {
            scan.unanalyzedLangs += ",";
        }
        scan.unanalyzedLangs += u.name;
    }

    discoverCells( ing, scan );
    if( scan.cells.empty() )
    {
        return scan;
    }

    const std::vector<AccessSite> sites       = collectAccesses( ing, scan.cells );
    const std::size_t             symbolCount = ing.symbols.size();

    BitMatrix readBits, writeBits, directRead, directWrite;
    readBits.init( symbolCount, scan.cells.size() );
    writeBits.init( symbolCount, scan.cells.size() );
    directRead.init( symbolCount, scan.cells.size() );
    directWrite.init( symbolCount, scan.cells.size() );

    std::vector<char> hasDirect( symbolCount, 0 );
    for( const AccessSite& s : sites )
    {
        if( s.fn >= symbolCount )
        {
            continue;
        }
        BitMatrix& all    = s.isWrite ? writeBits : readBits;
        BitMatrix& direct = s.isWrite ? directWrite : directRead;
        all.set( s.fn, s.cell );
        direct.set( s.fn, s.cell );
        hasDirect[s.fn] = 1;
    }

    propagateToCallers( g, symbolCount, readBits, writeBits, hasDirect );

    // Rows: every function or method that reaches at least one cell.
    for( std::size_t id = 0; id < symbolCount; ++id )
    {
        const SymKind kind = ing.symbols[id].kind;
        if( kind != SymKind::Function && kind != SymKind::Method )
        {
            continue;
        }
        Row row;
        row.fn               = static_cast<NodeId>( id );
        row.writeCount       = writeBits.popcount( id );
        row.readCount        = readBits.popcount( id );
        row.directWriteCount = directWrite.popcount( id );
        row.directReadCount  = directRead.popcount( id );
        if( row.writeCount == 0 && row.readCount == 0 )
        {
            continue;
        }
        scan.rows.push_back( std::move( row ) );
    }

    std::sort( scan.rows.begin(), scan.rows.end(),
               [ & ]( const Row& a, const Row& b )
               {
                   if( a.writeCount != b.writeCount ) { return a.writeCount > b.writeCount; }
                   if( a.readCount != b.readCount )   { return a.readCount > b.readCount; }
                   const Symbol& sa = ing.symbols[a.fn];
                   const Symbol& sb = ing.symbols[b.fn];
                   if( sa.fileId != sb.fileId )       { return ing.files[sa.fileId] < ing.files[sb.fileId]; }
                   if( sa.line != sb.line )           { return sa.line < sb.line; }
                   return a.fn < b.fn;
               } );

    // Evidence, for the rows only. `sites` is sorted by (fn, cell), so the direct site for a pair is one
    // binary search away; the transitive ones need one BFS per row, not one per cell.
    for( Row& row : scan.rows )
    {
        const std::vector<std::uint32_t> hop = forwardHops( g, symbolCount, row.fn );
        for( std::uint32_t cellIndex = 0; cellIndex < scan.cells.size(); ++cellIndex )
        {
            const bool r = readBits.test( row.fn, cellIndex );
            const bool w = writeBits.test( row.fn, cellIndex );
            if( !r && !w )
            {
                continue;
            }
            RowCell rc;
            rc.cell  = cellIndex;
            rc.read  = r;
            rc.write = w;

            const AccessSite probe{ row.fn, cellIndex, 0, 0, false };
            const auto       lower = std::lower_bound( sites.begin(), sites.end(), probe,
                                                       [ ]( const AccessSite& a, const AccessSite& b )
                                                       {
                                                           if( a.fn != b.fn ) { return a.fn < b.fn; }
                                                           return a.cell < b.cell;
                                                       } );
            if( lower != sites.end() && lower->fn == row.fn && lower->cell == cellIndex )
            {
                rc.direct      = true;
                rc.siteFile    = lower->fileId;
                rc.siteLine    = lower->line;
                rc.directRead  = directRead.test( row.fn, cellIndex );
                rc.directWrite = directWrite.test( row.fn, cellIndex );
            }
            else
            {
                std::uint32_t bestHop = UINT32_MAX;
                for( const AccessSite& s : sites )
                {
                    if( s.cell != cellIndex || s.fn >= symbolCount )
                    {
                        continue;
                    }
                    if( hop[s.fn] < bestHop || ( hop[s.fn] == bestHop && s.fn < rc.via ) )
                    {
                        bestHop = hop[s.fn];
                        rc.via  = s.fn;
                    }
                }
                if( bestHop == UINT32_MAX )
                {
                    // The bit exists but no reachable toucher explains it — a graph/closure disagreement.
                    // Drop the child rather than emit an unexplained one; the counts stay, and the row's
                    // cells_total vs its children is what makes the gap visible.
                    DEGRADED_PATH_ALERT( "nonlocal-state: a reachable cell has no reachable direct access site" );
                    continue;
                }
            }
            row.cells.push_back( rc );
        }
        std::sort( row.cells.begin(), row.cells.end(),
                   [ & ]( const RowCell& a, const RowCell& b )
                   {
                       if( a.write != b.write )   { return static_cast<int>( a.write ) > static_cast<int>( b.write ); }
                       if( a.direct != b.direct ) { return static_cast<int>( a.direct ) > static_cast<int>( b.direct ); }
                       if( scan.cells[a.cell].name != scan.cells[b.cell].name )
                       {
                           return scan.cells[a.cell].name < scan.cells[b.cell].name;
                       }
                       return a.cell < b.cell;
                   } );
    }
    return scan;
}

// ── emission ─────────────────────────────────────────────────────────────────────────────────────────

// The legend the reader meets FIRST. Every attribute this verb emits is DEFINED here in the house `name=`
// form (test/legendcoveragecheck.sh derives that mechanically). No `--` digraph anywhere in it: that is
// illegal inside an XML comment, which is why flags are named bare (see src/graphlegend.h).
inline constexpr const char* kNonLocalStateLegend =
    "<!-- ripwire nonlocal-state: per function, the NON-LOCAL MUTABLE STATE it can reach, reads and writes "
    "kept apart. A cell is one mutable datum declared outside any local scope: a file or namespace scope "
    "variable, a function-local static (local in name only), or a Python module global. A const, constexpr "
    "or consteval declaration is NOT a cell. Rows are ordered MOST WRITES FIRST, then most reads. "
    "p=path:line n=symbol name "
    "writes=distinct cells this function or its transitive callees WRITE "
    "reads=distinct cells this function or its transitive callees READ "
    "direct_writes=the writes= subset written in this function's OWN body "
    "direct_reads=the reads= subset read in this function's OWN body "
    "cells_total=distinct cells reached (a cell both read and written counts once) "
    "cells_shown=cell children printed cells_capped=1 when a row's children were truncated. "
    "Each cell child: n=cell name p=the cell's declaration path:line "
    "dir=r for read, w for write, rw for both, taken over this function's OWN BODY AND its callee closure together "
    "at=one use site in this function's own body (direct cells; there may be more) "
    "at_dir=what the OWN-BODY sites do, which can be NARROWER than dir=: at_dir=r with dir=rw means this body only "
    "reads the cell and a callee is what writes it "
    "via=the nearest callee whose own body touches the cell (transitive cells; exactly one of at= or via= is present). "
    "cells=cells found in the corpus functions=functions reaching at least one cell "
    "shown=rows printed capped=1 when rows were dropped; raise the default cap with limit=N (offset=M pages), "
    "which also prints total= has_more= next_offset= offset= limit= "
    "unanalyzed_langs=indexed languages this lens does NOT analyse, so their files contribute NO cells and NO "
    "rows; the analysis covers C++, ObjC and Python, the languages whose read and write use sites the index "
    "carries. Their absence is NOT a measurement of zero. unanalyzed_files=indexed files in those languages "
    "undecided_decls=declarations whose specifiers ran past the text window, so mutability could not be decided; dropped, never guessed "
    "cells_capped=1 on the ROOT when the cell universe hit its ceiling decls_capped=1 when a declaration query hit its match budget. "
    "counts_floor=1 because this analysis is UNSOUND BY CONSTRUCTION and every count here is a FLOOR. It cannot "
    "see: an indirect call (a virtual, an unbound or reassigned function pointer or callback, or a macro "
    "invocation whose #define is not indexed), so the callee "
    "closure stops early; a write through a pointer or reference that ALIASES a cell without naming it; a "
    "cell named only inside a macro; reflection-like or duck-typed dispatch. It can also OVER-count in one "
    "way: a local that SHADOWS a cell's name is charged to the cell unless ingest recorded a type binding "
    "for that local, which it does for typed and constructed locals only. Read a zero as none found, never "
    "as none exists, and read a row as a place to look rather than a verdict. -->";

inline int writeNonLocalStateReport( const IngestResult& ing, const Graph& g, int pageLimit, int pageOffset )
{
    const Scan        scan  = computeNonLocalState( ing, g );
    const std::size_t total = scan.rows.size();
    const PageWindow  page  = pageWindow( total, effectiveRowCap( pageLimit, int( kRowCap ) ), pageOffset );
    const std::size_t shown = page.end > page.begin ? page.end - page.begin : 0;

    char disclosure[kPageDisclosureCap];
    pageDisclosure( disclosure, sizeof disclosure, shown, total, page.end, pageLimit, pageOffset, true );

    std::fputs( kNonLocalStateLegend, stdout );
    std::printf( "<nonlocal_state cells=\"%zu\" functions=\"%zu\"%s%s", scan.cells.size(), total, disclosure,
                 rw::kGraphCountFloorAttrXml );
    if( !scan.unanalyzedLangs.empty() )
    {
        std::printf( " unanalyzed_langs=\"%s\" unanalyzed_files=\"%u\"", scan.unanalyzedLangs.c_str(), scan.unanalyzedFileCount );
    }
    if( scan.undecidedDeclCount != 0 )
    {
        std::printf( " undecided_decls=\"%u\"", scan.undecidedDeclCount );
    }
    if( scan.cellsCapped )
    {
        std::printf( " cells_capped=\"1\"" );
    }
    if( scan.declsCapped )
    {
        std::printf( " decls_capped=\"1\"" );
    }
    std::printf( ">" );

    // Separate scratch buffers per concurrently-live view: escapeXml returns a VIEW into its `out`, so
    // reusing one buffer for two live strings invalidates the first (see readability.h's note).
    std::vector<char> escA, escB, escC, escD;
    for( std::size_t rowIndex = page.begin; rowIndex < page.end; ++rowIndex )
    {
        const Row&    row  = scan.rows[rowIndex];
        const Symbol& s    = ing.symbols[row.fn];
        const std::string path( escapeXml( ing.files[s.fileId], escA ) );
        const std::string name( escapeXml( s.name, escB ) );
        const std::size_t cellsShown = std::min( row.cells.size(), kCellsPerRowCap );

        std::printf( "<fn p=\"%s:%u\" n=\"%s\" writes=\"%u\" reads=\"%u\" direct_writes=\"%u\" direct_reads=\"%u\" cells_total=\"%zu\"",
                     path.c_str(), s.line, name.c_str(),
                     row.writeCount, row.readCount, row.directWriteCount, row.directReadCount, row.cells.size() );
        if( cellsShown != row.cells.size() )
        {
            std::printf( " cells_shown=\"%zu\" cells_capped=\"1\"", cellsShown );
        }
        std::printf( ">" );

        for( std::size_t k = 0; k < cellsShown; ++k )
        {
            const RowCell& rc   = row.cells[k];
            const Cell&    cell = scan.cells[rc.cell];
            const std::string cellName( escapeXml( cell.name, escC ) );
            const std::string cellPath( escapeXml( ing.files[cell.fileId], escD ) );
            const char*       dir = rc.read && rc.write ? "rw" : ( rc.write ? "w" : "r" );
            std::printf( "<cell n=\"%s\" p=\"%s:%u\" dir=\"%s\"", cellName.c_str(), cellPath.c_str(), cell.line, dir );
            if( rc.direct )
            {
                std::vector<char>  escSite;
                const std::string  sitePath( escapeXml( ing.files[rc.siteFile], escSite ) );
                const char*        atDir = rc.directRead && rc.directWrite ? "rw" : ( rc.directWrite ? "w" : "r" );
                std::printf( " at=\"%s:%u\" at_dir=\"%s\"", sitePath.c_str(), rc.siteLine, atDir );
            }
            else
            {
                std::vector<char> escVia;
                const std::string via( escapeXml( ing.symbols[rc.via].name, escVia ) );
                std::printf( " via=\"%s\"", via.c_str() );
            }
            std::printf( "/>" );
        }
        std::printf( "</fn>" );
    }
    std::printf( "</nonlocal_state>" );
    return 0;
}

}   // namespace rw::nonlocal

#undef RW_NLS_C_DECLARATORS
#undef RW_NLS_C_DECLARATORS_NONAME
