#pragma once
#if !defined( RIPWIRE_INGEST_TU )
#error "ingest_importcap.h is a SECTION of src/ingest.cpp's translation unit - include it only from ingest.cpp (see the ingest-family split note there)"
#endif

// ingest_importcap.h — the C++ half of the shared import-capture vocabulary (issue #358).
//
// THE SHAPE OF THE ROUND. What every per-language import extractor did was the same three steps: find the
// directive's node, pick the one child that carries the written specifier, normalise that child's text.
// Step one is now the tags query's job — `@import.path` in queries/<lang>/tags.scm names the specifier
// node, one capture name for every language, and an UNANCHORED pattern so a directive nested in a guard
// is found without the C++ walk descending to meet it. Steps two and three are what is left here, and
// they are ONE function per DepDialect instead of one per language: the dialect is the unit at which
// "what does a written specifier mean" actually varies (a C-family `<x.h>` carries a quote-vs-angle bit,
// a TS `'./x'` carries quote delimiters, a Ruby `require_relative` carries a file-relative rule), and
// dependencyDialect already groups languages by exactly that. Dependency RESOLUTION stays in
// src/resolve.h and is untouched by this round.
//
// WHAT IS STILL IN C++, AND WHY IT CANNOT LEAVE. Tags-pass predicates never run here (stated in
// queries/python/tags.scm, pinned by test/matchgrammarcheck.sh, and the reason `using namespace ns;` is
// gated in ingest.cpp rather than excluded by a query). So every gate that needs to READ TEXT stays in
// C++: which preprocessor directive a captured `preproc_call` argument belongs to, whether a callee is
// the bare name `require`, whether an argument is a single string literal. Those are normaliser arms, not
// extractors — one per dialect, not one per language.
//
// THE VOCABULARY IS A FAMILY, AND ONLY ITS FIRST MEMBER IS SPENT. `@import.path` is the only capture name
// in use, because C-family imports have no other part: `#include` names a path and nothing else — no
// alias to record, no list of imported names. The other two names the issue sketches are reserved BY NAME
// so the next language lands on them rather than inventing a spelling: `@import.alias` is the local name an
// import renames a target to (`import a.b as c`, `use Foo\Bar as Baz`, `using X = Foo.Bar`), and
// `@import.names` is a group of targets ONE directive names (`use Foo\{A, B}`, `alias MyApp.{Bar, Baz}`),
// which is why both of those are emitted by the C++ side today through a per-directive helper rather than
// by one capture — a capture names one node, and a group is many. No enum value reserves them: an unused
// arm that no query can reach is a lie about what the vocabulary supports.
//
// SECOND MEMBER: DepDialect::Web (TypeScript, TSX, JavaScript, the .astro frontmatter that rides TypeScript).
// Its three spellings are three patterns on the SAME capture name — `import … from 'x'`, a re-export
// `export … from 'x'`, and the CommonJS / dynamic call `require('x')` / `import('x')` — and one normaliser.
// Neither `@import.alias` nor `@import.names` is used for it, for the same reason C-family has none: the
// Include record a TS/JS import produces names a MODULE and nothing else. The bound names (`import { a as b }`)
// are a different record — captureJsImportFacts' RawBinds, in src/ingest_jsimports.h — which this slice does
// not touch, so there is no current JS/TS semantics for those two names to carry yet.
//
// ORDERING. ts_query_cursor_next_match yields matches by the match's start byte, so a capture arrives in
// SOURCE order and the emitted Includes do too — the same order captureIncludes' walk produced, because
// emitCapturedImport runs straight from the capture dispatch with nothing staging it in between. The
// import-role use-site refs move into the tags pass's own window, where orderReferences re-sorts them by
// (startByte, name, role, isInherit) — a total key, so the move cannot reorder a published row.
//
// WHAT THE WALK USED TO OWN, AND DOES NOT TRAVEL WITH THE MOVE. Three things captureIncludes computed from
// its own frame are re-derived here rather than dropped: the import-container nesting bound
// (importContainerReach + the same DISCLOSE, below), the lazy bit a TS/JS require needs from `insideFn`
// (the same ancestor loop, one more bit), and Ruby's innermost-open index for the constant-receiver dedupe.
// The first two are recovered because each is one parent hop per import; the third is why Ruby cannot move
// until the emission can re-derive it from ancestry too — the tags pass never sees a walk frame.

#include "depdialect.h"   // DepDialect + dependencyDialect — the unit one normaliser is written per

namespace rw
{

namespace
{

// What importContainerReach reads off one directive's ancestry.
struct ImportReach
{
    std::uint16_t depth     = 0;       // containers above the directive, stopped at kMaxImportContainerDepth + 1
    bool          reachable = true;    // every node between the file root and the directive is an import container
    bool          insideFn  = false;   // some such container is a function body (kJsFunctionContainers): TS/JS lazy bit
};

// The import-container REACH of a captured directive, its DEPTH and its function-body bit — the walk's own
// rules, re-derived from the captured node because the walk no longer runs for this language.
//
// REACH. captureIncludes seeded the frame stack with root's DIRECT children and then entered only
// `isImportContainer` nodes, so a directive was reachable exactly when every node between the file root
// and it was an import container. A flat tags query has no such notion: `(preproc_include path: (_)
// @import.path)` is unanchored and matches at any depth. Without this test the round would WIDEN the
// C-family graph by 10 edges on the maintainer's probe tree — `extern "C" { #include "n.h" }` (the
// standard C-header idiom), `namespace ns { #include "d.inc" }`, an `#include` inside a function body
// (the X-macro `.def` pattern), and an include under an ERROR node in a header whose guard arm failed
// to parse: main 17, this 27. All four are real dependencies and capturing them is arguably a FIX, which
// is exactly why it cannot ride along in this PR — #358's rule is that each slice is byte-identical.
// So reach is restored here and the widening is left as its own follow-up.
//
// The file root is deliberately NOT tested: its children are what the walk always started from, so
// `isImportContainer(root)` being false must not reject a file-scope include. The loop stops when
// `p`'s own parent is null, which is the root.
ImportReach importContainerReach( TSNode directive, Lang lang ) noexcept
{
    const bool directiveIsNode = !ts_node_is_null( directive );   // hoisted: a promise holds no call (selfcheckcheck C)
    EXPECTS( directiveIsNode, "the directive is a node of the parsed tree: importDirectiveOf never returns null for a captured specifier" );
    ImportReach reach;
    for( TSNode p = ts_node_parent( directive ); !ts_node_is_null( p ); p = ts_node_parent( p ) )
    {
        if( ts_node_is_null( ts_node_parent( p ) ) )
        {
            break;                                   // p is the file root: reached unconditionally
        }
        if( !isImportContainer( lang, ts_node_type( p ) ) )
        {
            reach.reachable = false;                 // the walk would not have entered this node
            break;
        }
        // The walk's `childInsideFn = frame.insideFn || isFunctionLike( lang, t )` is sticky downward, so the
        // directive is inside a function exactly when ANY container above it is a function-body kind.
        reach.insideFn = reach.insideFn || isFunctionLike( lang, ts_node_type( p ) );
        if( ++reach.depth > kMaxImportContainerDepth )
        {
            break;                                   // STOPS AT THE BOUND: past it the answer cannot change, and
        }                                            // a hostile file must not buy an unbounded parent walk
    }
    ENSURES( reach.depth <= kMaxImportContainerDepth + 1, "the ancestor loop stops one past the bound, so a hostile file buys a bounded parent walk" );
    return reach;
}

// One captured `@import.path`, normalised. `text` empty is the "not an import after all" signal and the
// caller emits nothing: that is how a dropped directive reads (a floor), which is the honest direction
// for this graph — a wrong edge is worse than a missing one.
struct ImportSpec
{
    std::string text;
    bool        isAngle = false;   // CFamily: <x.h> is external (unresolvable without a build system), "x.h" is not
    bool        lazyInClosure = false;   // Web: this is a require()/import() CALL, so it is Include::isLazy iff it sits in a function body
};

// ── DepDialect::CFamily ───────────────────────────────────────────────────────────────────────────────
// `<dir/x.h>` / `"dir/x.h"` → `dir/x.h`, with the quote-vs-angle bit read from the delimiter BEFORE it
// is stripped. A spelling with no recognised opening delimiter — a macro include, `#include HEADER` —
// comes back verbatim in quote-form, which is pre-existing behaviour preserved byte-for-byte.
//
// THE ONE GATE, and it is a gate on TEXT because a predicate cannot run. Under the C and C++ grammars
// `#import` has no rule of its own, so it parses as a generic preproc_call whose `directive:` field holds
// the spelling — and so do `#pragma once`, `#error "…"`, `#warning`, and every unknown directive, all of
// which the query above captures and NONE of which is a physical dependency. Under the ObjC grammar
// `#import` IS a preproc_include and needs no gate, which is why this branch tests the node kind rather
// than the text alone. Every non-`#import` spelling is dropped: a floor, never a fabricated edge.
//
// DISCLOSED FLOOR, unchanged by this round and named here rather than left to be rediscovered:
// `#include_next "x.h"` also parses as a preproc_call, so it fails this same gate and is NOT captured —
// before and after, on main exactly as here. It is a real dependency and the fix is its own arm (a
// `#include_next` spelling admitted alongside `#import`); it is out of scope for a pure refactor.
ImportSpec normaliseCFamilyImport( TSNode directive, std::string_view raw, std::string_view src )
{
    ImportSpec out;
    if( kindIs( ts_node_type( directive ), "preproc_call" )
        && nodeFieldText( directive, NodeField::Directive, src ) != "#import" )
    {
        return out;
    }
    out.text = includePathOf( raw, out.isAngle );
    return out;
}

// ── DepDialect::Web ──────────────────────────────────────────────────────────────────────────────────
// TypeScript, TSX, JavaScript and the .astro frontmatter. Two directive shapes reach this normaliser, told
// apart by the DIRECTIVE node (the captured string's statement, or its call):
//   import_statement / export_statement — `import … from 'x'`, `import 'x'`, `import type …`, and the re-exports
//       `export * from`, `export * as n from`, `export { a as b } from`, `export type { T } from`. The grammar
//       gives all of them the same `source:` string, which is the whole capture; every other export_statement
//       has no `source:` and is not matched by the query at all.
//   call_expression — the CommonJS `require('x')` and the dynamic `import('x')`. A query cannot say "the
//       callee's TEXT is require" (tags-pass predicates never run), so the three guards that keep an ordinary
//       call out of the dependency graph stay C++: jsModuleLoadTarget (src/ingest_relations.h), UNCHANGED by
//       this round and shared with captureJsImportFacts, reads the callee text, the argument count and the
//       string. The query only says where a candidate call is; the guards say whether it is a module load.
//       Whether the hit is LAZY (written inside a function body) is the ancestry's answer, not the text's: this
//       arm only says the directive is a call (`lazyInClosure`), and emitCapturedImport ANDs it with the walk up.
// `import x = require('y')` (TS) is `import_require_clause` with its own `source:` and matches no pattern —
// the extractor never read it either, so it is still not an edge: a disclosed floor, unchanged by the round.
ImportSpec normaliseWebImport( TSNode directive, std::string_view raw, std::string_view src )
{
    ImportSpec out;
    if( kindIs( ts_node_type( directive ), "call_expression" ) )
    {
        out.text          = jsModuleLoadTarget( directive, src );
        out.lazyInClosure = !out.text.empty();   // kParserVer 72: a hit found inside a function body is LAZY (the caller knows where it sits)
        return out;
    }
    out.text = std::string( pattern::stripQuotePair( raw ) );   // the captured node is a `string`: strip the one quote pair
    return out;
}

// ── the dispatch: ONE normaliser per DepDialect ──────────────────────────────────────────────────────
// CFamily and Web are the dialects that have moved over so far; every other arm returns an empty ImportSpec,
// which is what makes the capture INERT rather than wrong on a language whose tags.scm has not adopted
// `@import.path` yet. Each `case` is deleted as its language moves, and the compiler then names every
// other dialect still to do — the same "one language at a time" landing the issue asks for.
ImportSpec normaliseImportSpecifier( DepDialect dialect, TSNode directive, std::string_view raw, std::string_view src )
{
    switch( dialect )
    {
        case DepDialect::CFamily: return normaliseCFamilyImport( directive, raw, src );
        case DepDialect::Web:     return normaliseWebImport( directive, raw, src );
        default:                  return {};   // no other language captures @import.path yet
    }
}

// True for a dialect whose directives come from `@import.path` and NOT from captureIncludes' walk. The one
// place the walk is switched off (captureSideFacts) asks this, so a dialect cannot be moved in the normaliser
// above and still be walked a second time, or walked-off without a normaliser.
inline constexpr std::array<DepDialect, 2> kCapturedImportDialects = { DepDialect::CFamily, DepDialect::Web };

inline bool importsFromCapture( DepDialect dialect ) noexcept
{
    return std::find( kCapturedImportDialects.begin(), kCapturedImportDialects.end(), dialect ) != kCapturedImportDialects.end();
}

// The DIRECTIVE a captured specifier belongs to — the node both records are SITED at. For a C include or a
// JS import/re-export it is the specifier's parent; for a call it is the call, one hop further, because the
// specifier sits in the call's `arguments`.
TSNode importDirectiveOf( TSNode pathNode ) noexcept
{
    const TSNode parent = ts_node_parent( pathNode );
    const bool hasParent = !ts_node_is_null( parent );
    ASSUME( hasParent, "a captured specifier is a string or path token, never the file root" );
    const TSNode directive = kindIs( ts_node_type( parent ), "arguments" ) ? ts_node_parent( parent ) : parent;
    const bool hasDirective = !ts_node_is_null( directive );
    ENSURES( hasDirective, "an `arguments` list always belongs to a call" );
    return directive;
}

// One captured `@import.path` → the Include record plus its ABS-3 import-role use-site ref, which is
// exactly the pair captureIncludes' `emitDirective` lambda minted for a C-family directive.
//
// IT TAKES THE CAPTURED NODE, not a (node, text) pair, because the whole shape of this file is "one node
// in, everything else derived here": the specifier's text is its own source span, and the DIRECTIVE it
// belongs to is its parent — the `#include` / `#import` statement itself. Handing the caller a `directive`
// and a `raw` string instead would push that rule out to every call site and make this function correct
// only while its callers obey an unwritten contract.
//
// The directive is also the node both records are SITED at, so an include nested inside an `#if` reports
// its own line and byte, not the guard's (captureIncludes' own rule, kept because resolve.h's Ruby
// containment reads the byte and --deps reports the line). The use-site ref's name is the importable final
// segment — `dir/x.h` → `x`, `<vector>` → `vector` — and a target with no identifier head (a relative
// `../x`) names nothing and emits no ref, since there is nothing for the resolver to key on.
//
// THE NESTING BOUND AND THE REACH, both kept deliberately. A flat tags query has no depth limit and no
// container allowlist of its own, so nothing about THIS path forces either — but the contract the walk
// carried is a real one: past kMaxImportContainerDepth a file's deeper imports are NOT captured, the file
// still indexes, and the fact is announced (test/preproccondcheck.sh's 600-deep arm pins all three), and
// an import under a non-container ancestor was NEVER captured at all. Re-deriving both from ancestry
// keeps the round a pure refactor; the widening an unanchored query would otherwise buy is real, and
// belongs in its own PR.
//
// SEVEN PARAMETERS, and that is the house shape rather than an accident. --quality-delta's `params` check
// bars 5, and this is over it; the siblings it sits between take 5 (captureBases, captureFields,
// capturePythonImportBinds) and 9 (captureIncludes — the very function this round moved C-family OUT of),
// with the two per-file drivers at 10. Four of the seven are the sink set (includes, refs, shortfall) plus
// the file id every capture records carry. Collapsing them into a context struct would take this one call
// under the bar while leaving every sibling over it, i.e. a local abstraction that makes the family harder
// to read, not easier. The count is the convention; the bar is generic.
void emitCapturedImport( TSNode pathNode, std::uint32_t fileId, Lang lang, std::string_view src,
                         std::vector<Include>& includes, std::vector<RawRef>& refs, ExtractShortfall& shortfall )
{
    const TSNode      directive = importDirectiveOf( pathNode );
    const ImportReach reach     = importContainerReach( directive, lang );
    if( reach.depth > kMaxImportContainerDepth )
    {
        DISCLOSE( shortfall, ExtractShortfall::DisclosureWhy::ImportNestingTooDeep,
                  "ingest: import-container nesting past the depth bound — deeper imports not captured" );
        return;   // the same degrade the walk performed: not captured, file still indexed
    }
    if( !reach.reachable )
    {
        return;   // a non-container ancestor the walk would never have entered — see importContainerReach
    }
    const ImportSpec spec = normaliseImportSpecifier( dependencyDialect( lang ), directive, nodeTextOf( pathNode, src ), src );
    if( spec.text.empty() )
    {
        return;
    }
    if( std::string name = importName( spec.text ); !name.empty() )
    {
        RawRef r;
        r.fileId    = fileId;
        r.startByte = ts_node_start_byte( directive );   // the DIRECTIVE, never its enclosing #if
        r.line      = ts_node_start_point( directive ).row + 1;
        r.role      = RefRole::Import;
        r.name      = std::move( name );
        refs.push_back( std::move( r ) );
    }
    includes.push_back( { fileId, spec.isAngle, spec.lazyInClosure && reach.insideFn, false, ts_node_start_byte( directive ), false, spec.text } );
}

}   // namespace

}   // namespace rw
