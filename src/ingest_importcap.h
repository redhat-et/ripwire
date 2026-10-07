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
// Python also consumes @import.names (one named clause per match) and @import.alias (its optional
// local rename). These build the existing Import bindings, never additional dependency targets.
// Other dialects still use their existing extractors until their own slice moves over.
// Python retains the bounded captureIncludes walk for exact nesting disclosure, even with no import.
//
// ORDERING. ts_query_cursor_next_match yields matches by the match's start byte, so a capture arrives in
// SOURCE order and the emitted Includes do too — the same order captureIncludes' walk produced, because
// emitCapturedImport runs straight from the capture dispatch with nothing staging it in between. The
// import-role use-site refs move into the tags pass's own window, where orderReferences re-sorts them by
// (startByte, name, role, isInherit) — a total key, so the move cannot reorder a published row.
//
// WHAT THE WALK STILL OWNS, AND DOES NOT TRAVEL WITH THE MOVE. Three things captureIncludes computed from
// its own frame are re-derived here rather than dropped: the import-container nesting bound
// (importContainerDepth + the same DISCLOSE, below), the lazy bit a TS/JS require needs from `insideFn`,
// and Ruby's innermost-open index for the constant-receiver dedupe. The first is recovered now because it
// is one parent hop per import; the other two are why a language still on the walk cannot move until the
// emission can re-derive them from ancestry too — the tags pass never sees a walk frame.

#include "depdialect.h"   // DepDialect + dependencyDialect — the unit one normaliser is written per

namespace rw
{

namespace
{

// The import-container REACH of a captured directive, and its DEPTH — the walk's own two rules,
// re-derived from the captured node because the walk no longer runs for this language.
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
std::uint16_t importContainerReach( TSNode directive, Lang lang, bool& reachable ) noexcept
{
    std::uint16_t depth     = 0;
    reachable = true;
    for( TSNode p = ts_node_parent( directive ); !ts_node_is_null( p ); p = ts_node_parent( p ) )
    {
        if( ts_node_is_null( ts_node_parent( p ) ) )
        {
            break;                                   // p is the file root: reached unconditionally
        }
        if( !isImportContainer( lang, ts_node_type( p ) ) )
        {
            reachable = false;                       // the walk would not have entered this node
            break;
        }
        if( ++depth > kMaxImportContainerDepth )
        {
            break;                                   // STOPS AT THE BOUND: past it the answer cannot change, and
        }                                            // a hostile file must not buy an unbounded parent walk
    }
    return depth;
}

// One captured `@import.path`, normalised. `text` empty is the "not an import after all" signal and the
// caller emits nothing: that is how a dropped directive reads (a floor), which is the honest direction
// for this graph — a wrong edge is worse than a missing one.
struct ImportSpec
{
    std::string text;
    bool        isAngle = false;   // CFamily: <x.h> is external (unresolvable without a build system), "x.h" is not
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

// ── the dispatch: ONE normaliser per DepDialect ──────────────────────────────────────────────────────
// Python keeps its written span verbatim, including the first plain import's `as alias` spelling.
// Cleaning that clause or emitting one target per clause would change --deps and is a separate change.
// Other dialects remain inert until their queries adopt this vocabulary.
ImportSpec normaliseImportSpecifier( DepDialect dialect, TSNode directive, std::string_view raw, std::string_view src )
{
    switch( dialect )
    {
        case DepDialect::CFamily: return normaliseCFamilyImport( directive, raw, src );
        case DepDialect::Python:  return { std::string( raw ) };
        default:                  return {};   // dialects that have not moved over
    }
}

// One @import.names clause and its optional @import.alias → the existing Python Import binding.
// The query selects the clause; normalization keeps the plain-import module marker and from-import
// member distinction (#287). Both records stay at the STATEMENT byte, with the same empty spans.
// A multi-clause import still has only its FIRST Include, but every clause binds a name. Reach and
// depth must apply to bindings too, or a cut/ERROR-wrapped import would still narrow a call.
void emitCapturedPythonImportBind( TSNode namesNode, TSNode aliasNode, std::uint32_t fileId, std::string_view src, std::vector<RawBind>& binds )
{
    const bool   hasAlias = !ts_node_is_null( aliasNode );
    const TSNode clause   = hasAlias ? ts_node_parent( namesNode ) : namesNode;
    const TSNode stmt     = ts_node_parent( clause );
    const bool   isFrom   = kindIs( ts_node_type( stmt ), "import_from_statement" );
    bool         reachable = false;
    if( importContainerReach( stmt, Lang::Python, reachable ) > kMaxImportContainerDepth || !reachable )
    {
        return;
    }
    // The old walk called its binding helper only after extracting a nonempty first target.
    const TSNode first = fieldChild( stmt, isFrom ? NodeField::ModuleName : NodeField::Name );
    if( nodeTextOf( first, src ).empty() )
    {
        return;
    }
    std::string_view bound = nodeTextOf( hasAlias ? aliasNode : namesNode, src );
    if( !isFrom && !hasAlias )
    {
        bound = bound.substr( 0, bound.find( '.' ) );   // `import a.b` binds `a`, not `a.b`
    }
    std::string target = importSpecifierText( isFrom ? first : namesNode, src );
    if( bound.empty() || target.empty() )
    {
        return;
    }
    RawBind b;
    b.fileId       = fileId;
    b.startByte    = ts_node_start_byte( stmt );
    b.lang         = Lang::Python;
    b.kind         = LocalBindKind::Import;
    b.var.assign( bound );
    b.typeName     = std::move( target );
    b.importedName = isFrom ? std::string{} : "module";
    binds.push_back( std::move( b ) );
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
void emitCapturedImport( TSNode pathNode, std::uint32_t fileId, Lang lang, std::string_view src,
                         std::vector<Include>& includes, std::vector<RawRef>& refs, ExtractShortfall& shortfall )
{
    const TSNode directive = ts_node_parent( pathNode );
    if( lang == Lang::Python && kindIs( ts_node_type( directive ), "import_statement" )
        && !ts_node_eq( pathNode, fieldChild( directive, NodeField::Name ) ) )
    {
        return;   // the old walk emitted only the first name, even for `import a, b`
    }
    bool           reachable = false;
    if( importContainerReach( directive, lang, reachable ) > kMaxImportContainerDepth )
    {
        if( lang != Lang::Python )   // Python's retained walk owns the exact disclosure, including empty containers
        {
            DISCLOSE( shortfall, ExtractShortfall::DisclosureWhy::ImportNestingTooDeep,
                      "ingest: import-container nesting past the depth bound — deeper imports not captured" );
        }
        return;   // the same degrade the walk performed: not captured, file still indexed
    }
    if( !reachable )
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
    includes.push_back( { fileId, spec.isAngle, false, false, ts_node_start_byte( directive ), false, spec.text } );
}

}   // namespace

}   // namespace rw
