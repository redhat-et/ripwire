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
// alias to record, no list of imported names — and because Go's alias/dot/blank spellings ride inside the
// declaration clause its Include has always carried (see DepDialect::Go below), not in a field of their own.
// The other two names the issue sketches are reserved BY NAME so the next language lands on them rather
// than inventing a spelling: `@import.alias` is the local name an import renames a target to (`import a.b as c`, `use Foo\Bar as Baz`, `using X = Foo.Bar`), and
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
// `isImportContainer(root)` being false must not reject a file-scope include. The ancestors read are the
// nodes STRICTLY BETWEEN the root and the directive.
//
// ONE DESCENT FROM THE ROOT, not an upward walk. tree-sitter nodes hold no parent pointer, so every
// ts_node_parent is itself a descent from the root and walking k ancestors up costs k of them (the precedent
// and its measurement: ingest_names.h::enclosingFunctionScope — 600 nested blocks, 19.7 s upward against
// 9.4 s down). The first version of this function walked up, bounded to kMaxImportContainerDepth hops, and
// that bound capped the HOPS, not the cost: a TS/JS file of 2 000 nested `foo( "x", foo( "x", … ) )` calls
// (a hyperscript tree; every one matches the call pattern) took 152 s against 0.5 s for the walk it replaced.
// Descending once is O(depth) per directive, and what the upward loop answered is read off the same descent:
// `run` is how many container ancestors sit directly above the directive (the loop's reach before it met a
// non-container or the bound), `total` is how many ancestors there are. Reachable means the run is all of them.
// A run PAST the bound is reported by `depth` (clamped one past it), which the caller tests BEFORE `reachable`: the
// upward loop stopped at the bound without ever seeing a non-container above it, so a too-deep import is announced
// whether or not the walk would have entered it — the one LOUDER disclosure difference test/importcapcheck.sh pins.
ImportReach importContainerReach( TSNode directive, Lang lang ) noexcept
{
    const bool directiveIsNode = !ts_node_is_null( directive );   // hoisted: a promise holds no call (selfcheckcheck C)
    EXPECTS( directiveIsNode, "the directive is a node of the parsed tree: importDirectiveOf never returns null for a captured specifier" );
    std::uint32_t total = 0;
    std::uint32_t run   = 0;        // container ancestors directly above the directive (reset by a non-container)
    bool          fnInRun = false;  // some container in `run` is a function body
    TSNode        n     = ts_node_child_with_descendant( ts_tree_root_node( directive.tree ), directive );
    for( ; !ts_node_is_null( n ) && !ts_node_eq( n, directive ); n = ts_node_child_with_descendant( n, directive ) )
    {
        const char* t = ts_node_type( n );
        ++total;
        if( isImportContainer( lang, t ) )
        {
            ++run;
            // The walk's `childInsideFn = frame.insideFn || isFunctionLike( lang, t )` is sticky downward, so the
            // directive is inside a function exactly when ANY container above it is a function-body kind.
            fnInRun = fnInRun || isFunctionLike( lang, t );
        }
        else
        {
            run     = 0;
            fnInRun = false;
        }
    }
    ImportReach reach;
    if( ts_node_is_null( n ) )
    {
        reach.reachable = false;    // the descent lost the directive: read as "the walk would not have entered", a floor
        return reach;
    }
    reach.depth     = static_cast<std::uint16_t>( std::min<std::uint32_t>( run, kMaxImportContainerDepth + 1u ) );
    reach.reachable = ( run == total );
    reach.insideFn  = fnInRun;
    ENSURES( reach.depth <= kMaxImportContainerDepth + 1, "the depth is clamped one past the bound" );
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

// ── DepDialect::Go ───────────────────────────────────────────────────────────────────────────────────
// A Go import is ONE `import_declaration` — `import "fmt"`, `import f "fmt"` (aliased), `import . "x"` (dot),
// `import _ "x"` (blank), cgo's `import "C"`, or a parenthesised group of any of those — and the Include
// target it has always carried is the declaration's own CLAUSE (importClauseTarget, shared with the one
// language that still reads it from the walk), not a per-spec specifier. So the captured node is the
// declaration itself (queries/go/tags.scm: `(import_declaration) @import.path`) and the normaliser is the
// clause reader, nothing more. A GROUPED import therefore stays ONE record whose text is the whole group cut
// at 96 bytes, exactly as before: resolve.h's resolveGoImport documents that ("grouped imports collapse to
// one node upstream and are left unresolved"), and splitting a group into one record per spec would add
// edges — a behaviour change, so its own slice. The alias / dot / blank spellings are the same: they ride
// INSIDE the clause text (`f "fmt"`), which is why `@import.alias` and `@import.names` are NOT used here —
// today's Go semantics have no separate alias or names field on an Include. (The alias a Go import binds is
// a different record altogether, the ModuleAlias RawBind captureGoImportFacts writes; it is not a dependency
// edge and is left where it is.)
ImportSpec normaliseGoImport( TSNode declaration, std::string_view src )
{
    ImportSpec out;
    out.text = importClauseTarget( declaration, src );
    return out;
}

// ── the dispatch: ONE normaliser per DepDialect ──────────────────────────────────────────────────────
// CFamily, Web and Go are the dialects that have moved over so far; every other arm returns an empty ImportSpec,
// which is what makes the capture INERT rather than wrong on a language whose tags.scm has not adopted
// `@import.path` yet. Each `case` is deleted as its language moves, and the compiler then names every
// other dialect still to do — the same "one language at a time" landing the issue asks for.
ImportSpec normaliseImportSpecifier( DepDialect dialect, TSNode directive, std::string_view raw, std::string_view src )
{
    switch( dialect )
    {
        case DepDialect::CFamily: return normaliseCFamilyImport( directive, raw, src );
        case DepDialect::Web:     return normaliseWebImport( directive, raw, src );
        case DepDialect::Go:      return normaliseGoImport( directive, src );
        default:                  return {};   // no other language captures @import.path yet
    }
}

// True for a dialect whose directives come from `@import.path` and NOT from captureIncludes' walk. The one
// place the walk is switched off (captureSideFacts) asks this, so a dialect cannot be moved in the normaliser
// above and still be walked a second time, or walked-off without a normaliser.
inline bool importsFromCapture( DepDialect dialect ) noexcept
{
    switch( dialect )   // one case per dialect normaliseImportSpecifier has an arm for
    {
        case DepDialect::CFamily:
        case DepDialect::Web:
        case DepDialect::Go:
            return true;
        default:
            return false;
    }
}

// The DIRECTIVE a captured specifier belongs to — the node both records are SITED at. For a C include or a
// JS import/re-export it is the specifier's parent; for a call it is the call, one hop further, because the
// specifier sits in the call's `arguments`.
TSNode importDirectiveOf( DepDialect dialect, TSNode pathNode ) noexcept
{
    if( dialect == DepDialect::Go )
    {
        return pathNode;   // the Go capture IS the whole import_declaration
    }
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
    const TSNode     directive = importDirectiveOf( dependencyDialect( lang ), pathNode );
    // TEXT FIRST, ancestry second. The Web call pattern matches every bare `f( "s" … )`, so most captures here are
    // not imports at all, and the reach read below is a descent from the root — paying it to learn that `t( "key" )`
    // is not a dependency is the cost that made a 2 000-deep hyperscript tree 300x slower. Dropping a non-import
    // BEFORE the bound test also means a `#pragma once` / `foo( "x" )` under a too-deep nest no longer announces
    // "an import was cut" when none was (the walk announced on any too-deep container, import or not).
    const ImportSpec spec = normaliseImportSpecifier( dependencyDialect( lang ), directive, nodeTextOf( pathNode, src ), src );
    if( spec.text.empty() )
    {
        return;
    }
    const ImportReach reach = importContainerReach( directive, lang );
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
