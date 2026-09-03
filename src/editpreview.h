#pragma once

// editpreview.h — the PRE-APPLY half of --edit-check (card A1; gortex's preview_edit / agent-lsp's
// simulate_edit). `--edit-check=SYM --edit-payload=FILE --dry-run` answers exactly what --edit-check
// answers post-hoc — the contract delta vs git HEAD, and the callers a payload would make
// incompatible="1" — about bytes that have NOT been written.
//
// THE DESIGN RULE, and it is the whole reason this file is small: the preview does not re-derive the
// answer. It re-derives the TREE and hands it to the SAME editCheckBundleText() the post-hoc verb calls.
// Two things follow. (1) The payload is spliced by mcpedit::applyEdit over the SAME [sigStartByte,
// endByte) span, with the SAME CRLF harmonisation the write path applies, so "what the preview measured"
// and "what an apply would write" are one function. (2) Every fact downstream — the HEAD baseline, the
// root spelling, the at= commit anchor, the note children, the legend — is the real tree's, because the
// merged IngestResult keeps the real ing.files identities throughout. No temporary root reaches output.
//
// THE MERGE. An edit touches ONE file. ingest assigns symbol ids in (fileId, line, name, startByte)
// order, so a file's definitions are a CONTIGUOUS id range and its references/bindings/routes are a
// contiguous run of the same order — replacing a file's parse is therefore a RANGE SPLICE with one linear
// id shift, not a renumbering search. previewMerge() does exactly that and buildGraph() runs over the
// result, so the call graph the answer is read off is the graph the applied tree would have had — the
// arity filter included, which is why the CALLER SET itself is allowed to move.
//
// Included by main.cpp AFTER mcp.h (mcpedit) and quality.h; self-contained via its own includes so the
// order elsewhere never matters to it.

#include "editcheck.h"      // editCheckBundleText / editCheckGroups / editCheckAmbiguousMessage
#include "mcpedit.h"        // Op / applyEdit / detectDominantEol / normalizeToCrlf / kBinaryPayloadRefusal
#include "ingest.h"         // ingest() — the ONE parser path; looksBinary
#include "graph.h"          // buildGraph / resolveAllByNameQualified
#include "quality.h"        // cacheDirLadder / TmpTreeGuard
#include "sarif.h"          // rootPrefixOf / rootRelativeUri — the root-relative identity of the edited file

#include <array>
#include <cstdio>
#include <filesystem>
#include <string>
#include <utility>
#include <vector>

namespace rw
{
namespace editpreview
{

// the answer, or the refusal that replaces it. `xml` is non-empty exactly when ok; `message` exactly when
// not. POD-ish by intent: the caller prints one or the other and nothing else.
struct Outcome
{
    bool        ok = false;
    std::string message;
    std::string xml;
};

inline Outcome refuse( std::string message )
{
    Outcome oc;
    oc.message = std::move( message );
    return oc;
}

// ── the payload reader, owned HERE and called from the CLI write path too ─────────────────────────────
// The preview and --replace-symbol-body must refuse the same four payloads in the same words, or an agent
// learns one vocabulary and meets another the moment it stops previewing. FILE, or "-" for stdin; an empty
// payload never means delete; oversize is measured against the same --max-file-size the crawl uses; a
// NUL-bearing payload is refused by rw::looksBinary itself (not a second NUL rule) so the claim
// kBinaryPayloadRefusal makes is exactly the condition that would drop the file from the index.
inline bool readPayload( std::string_view spec, std::size_t maxFileBytes, std::string& out, std::string& err )
{
    out.clear();
    if( spec == "-" )
    {
        std::array<char, 8192> buf{};
        for( ;; )
        {
            const std::size_t n = std::fread( buf.data(), 1, buf.size(), stdin );
            out.append( buf.data(), n );
            if( n < buf.size() )
            {
                if( std::ferror( stdin ) )
                {
                    err = "could not read --edit-payload=- from stdin";
                    return false;
                }
                break;
            }
        }
    }
    else
    {
        bool readOk = false;
        out = rw::mcpdetail::readFileBytes( std::string( spec ), readOk );
        if( !readOk )
        {
            err = "could not read edit payload '" + std::string( spec ) + "'";
            return false;
        }
    }
    if( out.empty() )
    {
        err = "--edit-payload is empty; empty never means delete";
        return false;
    }
    if( out.size() > maxFileBytes )
    {
        err = "edit payload is " + std::to_string( out.size() ) + " bytes, over the --max-file-size ceiling of "
            + std::to_string( maxFileBytes ) + " bytes";
        return false;
    }
    if( rw::looksBinary( out ) )
    {
        err = "--edit-payload " + std::string( rw::mcpedit::kBinaryPayloadRefusal );
        return false;
    }
    return true;
}

// ── the range splice ──────────────────────────────────────────────────────────────────────────────────

// [lo, hi) — the ids of `fileId`'s definitions. Contiguous by construction (assignSymbols sorts by fileId
// first); the loop asserts nothing about that and simply finds the first and last, so a future ordering
// change degrades to a wrong-but-bounded range rather than reading past the end.
inline std::pair<std::size_t, std::size_t> symbolRangeOfFile( const IngestResult& ing, std::uint32_t fileId ) noexcept
{
    std::size_t lo = ing.symbols.size(), hi = 0;
    for( std::size_t i = 0; i < ing.symbols.size(); ++i )
    {
        if( ing.symbols[i].fileId == fileId )
        {
            if( i < lo ) { lo = i; }
            hi = i + 1;
        }
    }
    if( lo > hi ) { lo = hi; }
    return { lo, hi };
}

// The working tree with ONE file's parse replaced by `one`'s (a single-file ingest of the spliced bytes).
// Everything outside that file is carried over verbatim with its ids shifted by the size delta; everything
// inside it is dropped and replaced. The file TABLE never changes, so ing.files identities — and therefore
// every path, every root-relative spelling and every baseline key derived from them — stay the real tree's.
inline IngestResult previewMerge( const IngestResult& ing, std::uint32_t fileId, const IngestResult& one )
{
    IngestResult out;
    out.files           = ing.files;
    out.realPaths       = ing.realPaths;
    out.fileRoot        = ing.fileRoot;
    out.rootLabels      = ing.rootLabels;
    out.rootPaths       = ing.rootPaths;
    out.rootReals       = ing.rootReals;
    out.skippedOversize = ing.skippedOversize;
    out.crawlSkips      = ing.crawlSkips;
    out.fileHealth      = ing.fileHealth;
    out.docText         = ing.docText;
    if( fileId < out.fileHealth.size() && !one.fileHealth.empty() )
    {
        out.fileHealth[ fileId ] = one.fileHealth[0];
    }
    out.docText.erase( fileId );
    if( const auto dit = one.docText.find( 0u ); dit != one.docText.end() )
    {
        out.docText.emplace( fileId, dit->second );
    }

    const auto [ lo, hi ]      = symbolRangeOfFile( ing, fileId );
    const std::size_t newCount = one.symbols.size();

    // old id -> merged id, for a symbol OUTSIDE the replaced range. Inside it, the old symbol is gone and
    // so is everything that pointed at it — those records were dropped with the file, never re-pointed.
    const auto shift = [ lo = lo, hi = hi, newCount ]( NodeId old ) noexcept -> NodeId
    {
        if( old == kNoNode || old < lo ) { return old; }
        if( old >= hi )                  { return NodeId( old - hi + lo + newCount ); }
        return kNoNode;
    };

    out.symbols.reserve( ing.symbols.size() - ( hi - lo ) + newCount );
    for( std::size_t i = 0; i < lo; ++i )
    {
        out.symbols.push_back( ing.symbols[i] );
    }
    for( const Symbol& s : one.symbols )
    {
        Symbol c  = s;
        c.fileId  = fileId;
        c.id      = NodeId( out.symbols.size() );
        out.symbols.push_back( std::move( c ) );
    }
    for( std::size_t i = hi; i < ing.symbols.size(); ++i )
    {
        Symbol c = ing.symbols[i];
        c.id     = NodeId( out.symbols.size() );
        out.symbols.push_back( std::move( c ) );
    }

    // The field SIDE TABLE keeps its own index space (a FieldId, never a NodeId), so it is spliced by the
    // same (fileId, …) ordering and its ids are simply re-indexed.
    for( const Symbol& f : ing.fields )
    {
        if( f.fileId < fileId ) { out.fields.push_back( f ); }
    }
    for( const Symbol& f : one.fields )
    {
        Symbol c = f;  c.fileId = fileId;  out.fields.push_back( std::move( c ) );
    }
    for( const Symbol& f : ing.fields )
    {
        if( f.fileId > fileId ) { out.fields.push_back( f ); }
    }
    for( std::uint32_t fieldIndex = 0; fieldIndex < out.fields.size(); ++fieldIndex )
    {
        out.fields[ fieldIndex ].id = fieldIndex;
    }

    // Every other per-file table is emitted by ingest in (fileId, …) order, so splicing at the fileId seam
    // reproduces the order a real re-ingest of the edited tree would have produced — which matters because
    // buildGraph walks these in order and a different order is a different (still deterministic) graph.
    const auto spliceRefs = [ & ]( auto& dst, const auto& before, const auto& inside, auto remap )
    {
        for( const auto& r : before ) { if( r.fileId < fileId ) { auto c = r; remap( c, false ); dst.push_back( std::move( c ) ); } }
        for( const auto& r : inside ) { auto c = r; remap( c, true ); dst.push_back( std::move( c ) ); }
        for( const auto& r : before ) { if( r.fileId > fileId ) { auto c = r; remap( c, false ); dst.push_back( std::move( c ) ); } }
    };

    spliceRefs( out.references, ing.references, one.references, [ & ]( Reference& r, bool isNew )
    { r.fileId = isNew ? fileId : r.fileId; r.fromSymbol = isNew ? ( r.fromSymbol == kNoNode ? kNoNode : NodeId( lo + r.fromSymbol ) ) : shift( r.fromSymbol ); } );

    spliceRefs( out.bindings, ing.bindings, one.bindings, [ & ]( Binding& b, bool isNew )
    { b.fileId = isNew ? fileId : b.fileId; b.fromSymbol = isNew ? ( b.fromSymbol == kNoNode ? kNoNode : NodeId( lo + b.fromSymbol ) ) : shift( b.fromSymbol ); } );

    spliceRefs( out.routeUses, ing.routeUses, one.routeUses, [ & ]( RouteUse& u, bool isNew )
    { u.fileId = isNew ? fileId : u.fileId; u.fromSymbol = isNew ? ( u.fromSymbol == kNoNode ? kNoNode : NodeId( lo + u.fromSymbol ) ) : shift( u.fromSymbol ); } );

    spliceRefs( out.includes,       ing.includes,       one.includes,       [ & ]( Include& r, bool isNew )      { if( isNew ) { r.fileId = fileId; } } );
    spliceRefs( out.bindingAliases, ing.bindingAliases, one.bindingAliases, [ & ]( BindingAlias& r, bool isNew ) { if( isNew ) { r.fileId = fileId; } } );
    spliceRefs( out.routeDefs,      ing.routeDefs,      one.routeDefs,      [ & ]( RouteDef& r, bool isNew )     { if( isNew ) { r.fileId = fileId; } } );

    // The persisted subtoken statistics are sized 1:1 with symbols and serve RANKING alone — nothing the
    // contract comparison reads. Left empty and DECLARED empty (hasLexStats stays false) rather than
    // carried over at the wrong length, which is the shape that would corrupt a later reader silently.
    out.reparsedFiles = 0;
    return out;
}

// ── the preview itself ────────────────────────────────────────────────────────────────────────────────

// A single-file ingest of `bytes` written under `rel` inside a private temp root, so the parse sees the
// file's real EXTENSION and its real relative directory (both are inputs to language selection). Returns
// an empty result (files empty) on any I/O failure — a degrade, never a throw.
inline IngestResult ingestOneFile( const std::string& tmpDir, const std::string& rel, const std::string& bytes,
                                   std::size_t maxFileBytes, bool captureValueUses )
{
    namespace fs = std::filesystem;
    std::error_code   ec;
    const fs::path    target = fs::path( tmpDir ) / fs::path( rel );
    fs::create_directories( target.parent_path(), ec );
    std::FILE* fp = std::fopen( target.string().c_str(), "wb" );
    if( fp == nullptr )
    {
        DEGRADED_PATH_ALERT( "edit-preview: cannot write the spliced file into the temp root" );
        return {};
    }
    const std::size_t written = bytes.empty() ? 0 : std::fwrite( bytes.data(), 1, bytes.size(), fp );
    const bool        wrote   = ( written == bytes.size() );
    std::fclose( fp );
    if( !wrote )
    {
        DEGRADED_PATH_ALERT( "edit-preview: short write of the spliced file" );
        return {};
    }
    // No excludes: the ONE file here is the one the caller already resolved through the main index, so a
    // --exclude that would drop it can only produce a false "the payload defines nothing".
    return ingest( tmpDir.c_str(), {}, {}, maxFileBytes, captureValueUses );
}

// THE entry point. `focus` is the definition the CLI's own resolver picked on the CURRENT tree (so the
// span is the one an apply would splice); `selector` is the caller's spec verbatim, RE-RESOLVED on the
// merged tree through the same resolver + the same §A6a ambiguity refusal, which is what makes the
// preview's choice of definition identical to the post-apply verb's by construction.
inline Outcome run( const IngestResult& ing, const Graph& g, const std::string& root, std::size_t maxFileBytes,
                    const std::vector<std::string>& excludes, bool captureValueUses, std::string_view selector,
                    NodeId focus, const std::string& payload, const notes::NoteIndex* ni )
{
    namespace fs = std::filesystem;

    if( !ing.realPaths.empty() )
    {
        return refuse( "the pre-apply preview is single-root only; pass one <dir> (the CLI edit verbs are too)" );
    }
    const Symbol&      fsym = ing.symbols[ focus ];
    const std::string& path = ing.files[ fsym.fileId ];
    if( fsym.kind == SymKind::Section )
    {   // the edit engine's own kind guard: a Section's span does not delimit an editable definition, and
        // for html/csv/ipynb it is EXTRACTED-text coordinates — previewing a splice through one would
        // describe an edit that corrupts the file.
        return refuse( "'" + std::string( selector ) + "' is a document heading/section (" + path
                     + "), not an editable code definition — there is no definition span to preview a payload against" );
    }

    bool              readOk = false;
    const std::string src    = mcpdetail::readFileBytes( diskPath( ing, fsym.fileId ), readOk );
    if( !readOk )
    {
        return refuse( "cannot read '" + path + "' to preview the edit" );
    }
    const std::size_t a = fsym.sigStartByte, b = fsym.endByte;
    if( !( a < b && b <= src.size() ) )
    {
        return refuse( "the definition span for '" + std::string( selector ) + "' does not fit '" + path
                     + "' as it is on disk now (a=" + std::to_string( a ) + " b=" + std::to_string( b )
                     + " size=" + std::to_string( src.size() ) + ") — the index is stale; re-run to refresh it" );
    }
    if( std::string_view( src ).substr( a, b - a ).find( fsym.name ) == std::string_view::npos )
    {
        return refuse( "the recorded span for '" + std::string( selector ) + "' no longer contains the name '" + fsym.name
                     + "' in '" + path + "' — the file changed since the index was built; re-run to refresh it" );
    }

    // F-07, mirrored from the write path: harmonise the payload to the TARGET's own dominant line ending
    // before splicing, so the preview measures the bytes an apply would actually write.
    const mcpedit::EolStyle fileEol       = mcpedit::detectDominantEol( src );
    const bool              eolNormalized = ( fileEol == mcpedit::EolStyle::Crlf ) && ( payload.find( '\n' ) != std::string::npos );
    const std::string       editText      = eolNormalized ? mcpedit::normalizeToCrlf( payload ) : payload;

    std::size_t       newStart = 0, newEnd = 0;
    const std::string newBytes = mcpedit::applyEdit( mcpedit::Op::ReplaceBody, src, a, b, editText, newStart, newEnd );

    const std::string relPath = std::string( rw::sarif::rootRelativeUri( path, rw::sarif::rootPrefixOf( root ) ) );
    std::error_code   ec;
    const std::string tmpRoot = quality::cacheDirLadder() + "/ripwire-editpreview-" + std::to_string( ::getpid() );
    fs::remove_all( fs::path( tmpRoot ), ec );                    // a leftover from a crashed prior run
    if( !fs::create_directories( fs::path( tmpRoot ), ec ) && ec )
    {
        DEGRADED_PATH_ALERT( "edit-preview: cannot create the temp parse root" );
        return refuse( "cannot create a private temp directory to parse the payload in" );
    }
    quality::TmpTreeGuard guard{ tmpRoot };

    // The BEFORE parse is taken here rather than read off ing.fileHealth, so the ERROR-node comparison is
    // apples-to-apples even when the working-tree parse came from the content cache (where fileBytes==0
    // means NOT MEASURED and would silently become a zero baseline that refuses every payload).
    const IngestResult baseOne = ingestOneFile( tmpRoot + "/base", relPath, src,      maxFileBytes, captureValueUses );
    const IngestResult headOne = ingestOneFile( tmpRoot + "/head", relPath, newBytes, maxFileBytes, captureValueUses );
    if( headOne.files.empty() )
    {
        return refuse( "the payload could not be parsed: the spliced file did not survive the crawl" );
    }
    const std::uint32_t errBefore = baseOne.fileHealth.empty() ? 0u : baseOne.fileHealth[0].errNodes;
    const std::uint32_t errAfter  = headOne.fileHealth.empty() ? 0u : headOne.fileHealth[0].errNodes;
    if( errAfter > errBefore )
    {   // a DELTA, not an absolute: a file that already parses degraded (a macro-heavy header) must not make
        // every payload refuse — that refusal would be right about the file and wrong about the payload.
        return refuse( "the payload does not parse: splicing it into '" + path + "' raises the file's parse errors from "
                     + std::to_string( errBefore ) + " to " + std::to_string( errAfter )
                     + " — nothing was written, and no contract can be read off a broken parse" );
    }

    const IngestResult merged = previewMerge( ing, fsym.fileId, headOne );
    const Graph        mg     = buildGraph( merged );

    const std::vector<NodeId> matches = resolveAllByNameQualified( merged, selector );
    bool                      inSplice = false;
    for( NodeId m : matches )
    {
        const Symbol& ms = merged.symbols[m];
        if( ms.fileId == fsym.fileId && ms.sigStartByte < newEnd && ms.endByte > newStart )
        {
            inSplice = true;
        }
    }
    if( matches.empty() || !inSplice )
    {
        return refuse( "the payload does not define '" + std::string( selector ) + "': after splicing it over that "
                       "definition's span nothing of that name is defined in the replaced region of '" + path + "'" );
    }
    const std::vector<EditCheckGroup> groups = editCheckGroups( merged, mg, matches );
    if( groups.size() > 1 )
    {
        return refuse( editCheckAmbiguousMessage( selector, groups, "--edit-check=", matches.size() ) );
    }

    Outcome oc;
    oc.ok  = true;
    oc.xml = editCheckBundleText( merged, mg, root, maxFileBytes, excludes, groups[0].lowestNode, ni, true );
    return oc;
}

}   // namespace editpreview
}   // namespace rw
