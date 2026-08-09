#pragma once

// workspace.h — multi-root workspaces: N crawl roots → ONE merged symbol graph.
//
// Responsibilities (all v1-decided; do not re-litigate):
//   * root set hygiene   — realpath dedupe (stderr note), NESTED roots = hard error (§2.1);
//   * root identity      — label = shortest unique whole-segment suffix of the root's REAL path
//                          (basename when unique; leftward whole-segment extension on collision) (§2);
//   * canonical order    — roots sorted by LABEL (byte order), NEVER argv order: `ripwire a b` and
//                          `ripwire b a` are byte-identical (§2.1);
//   * merge              — per-root IngestResults concatenated with fileId/NodeId offsets into one
//                          IngestResult whose ing.files carry the LABELED spelling `<label>/<rel>`;
//                          the on-disk path per file survives in ing.realPaths (§4).
//
// N=1 NEVER reaches this header (the byte-identity quarantine): main.cpp only enters the workspace
// path when 2+ distinct roots survive dedupe. Labels are applied at MERGE time only — the per-root
// cache blobs (written by each per-root ingest() with its existing keying) never see a label.

#include "model.h"
#include "arch.h"      // relForHash — the root-relative strip (same lexical discipline as the caches)
#include "lexindex.h"  // B0.2: kLexFileSigWords — merging the per-part persisted subtoken stats

#include <climits>     // PATH_MAX
#include <cstdio>
#include <cstdlib>     // realpath
#include <string>
#include <string_view>
#include <vector>
#include <algorithm>

namespace rw
{

// One workspace root, post-hygiene. `arg` is the path as the user passed it (post git-URL resolution) —
// the spelling per-root ingest() crawls with; `real` is its realpath (dedupe/nesting/cross-root probes);
// `label` is the §2 identity prefix every merged path carries.
struct WorkspaceRoot
{
    std::string arg;
    std::string real;
    std::string label;
};

namespace wsdetail
{
    // realpath with a lexical fallback (an unresolvable path was already existence-checked by main).
    inline std::string realOf( const std::string& p )
    {
        char buf[ PATH_MAX ];
        return ::realpath( p.c_str(), buf ) ? std::string( buf ) : p;
    }

    // split a string on `delim` into its whole segments (no empties — a run of delimiters or a
    // leading/trailing one never yields an empty token). Default '/' keeps every existing call site
    // (path-segment splitting) byte-unchanged; other callers (e.g. mergescout.h's CSV ref list) pass
    // their own delimiter instead of hand-rolling the same loop (the shared primitive behind BOTH).
    inline std::vector<std::string_view> segmentsOf( std::string_view p, char delim = '/' )
    {
        std::vector<std::string_view> segs;
        std::size_t i = 0;
        while( i < p.size() )
        {
            std::size_t j = p.find( delim, i );
            if( j == std::string_view::npos )
            {
                j = p.size();
            }
            if( j > i )
            {
                segs.push_back( p.substr( i, j - i ) );
            }
            i = j + 1;
        }
        return segs;
    }

    // the k-segment suffix of `segs`, joined with '/'. k is clamped to segs.size().
    inline std::string suffixLabel( const std::vector<std::string_view>& segs, std::size_t k )
    {
        if( segs.empty() )
        {
            return std::string( "root" ); // degenerate ("/" as a root) — stable fallback
        }
        if( k > segs.size() )
        {
            k = segs.size();
        }
        std::string out;
        for( std::size_t i = segs.size() - k; i < segs.size(); ++i )
        {
            if( !out.empty() )
            {
                out.push_back( '/' );
            }
            out.append( segs[i] );
        }
        return out;
    }
}   // namespace wsdetail

// Build the canonical workspace root set from the raw (post-URL-resolution) root args.
// Returns false ⇒ hard error (nested roots), message already printed to stderr.
// On success `out` holds ≥1 root in canonical (label byte-order) order, deduped.
inline bool buildWorkspaceRoots( const std::vector<std::string>& args, std::vector<WorkspaceRoot>& out )
{
    out.clear();

    // 1) realpath + dedupe (same dir twice, incl. two spellings): keep the FIRST spelling, one stderr note.
    for( const std::string& a : args )
    {
        const std::string real = wsdetail::realOf( a );
        bool dup = false;
        for( const WorkspaceRoot& r : out )
        {
            if( r.real == real ) { dup = true; break; }
        }
        if( dup )
        {
            std::fprintf( stderr, "ripwire: duplicate root '%s' ignored (same directory already listed)\n", a.c_str() );
            continue;
        }
        out.push_back( { a, real, std::string() } );
    }

    // 2) nested roots = hard error (§2.1): files would have two owners, two ids, double PageRank mass.
    for( std::size_t i = 0; i < out.size(); ++i )
    {
        for( std::size_t j = 0; j < out.size(); ++j )
        {
            if( i == j )
            {
                continue;
            }
            const std::string& outer = out[i].real;
            const std::string& inner = out[j].real;
            if( inner.size() > outer.size() && inner.compare( 0, outer.size(), outer ) == 0
                && inner[ outer.size() ] == '/' )
            {
                std::fprintf( stderr, "ripwire: nested roots are not allowed: '%s' is inside '%s' — pass disjoint roots "
                                      "(to focus on a subtree, use --for / DIR-scoped verbs instead)\n",
                              out[j].arg.c_str(), out[i].arg.c_str() );
                return false;
            }
        }
    }

    // 3) labels: shortest unique whole-segment suffix of the REAL path (basename when unique). Extend
    //    leftward by whole segments until unique — deterministic, order-independent, stable when a third
    //    root is added elsewhere. A full-path collision is impossible post-dedupe.
    {
        std::vector<std::vector<std::string_view>> segs;
        segs.reserve( out.size() );
        for( const WorkspaceRoot& r : out )
        {
            segs.push_back( wsdetail::segmentsOf( r.real ) );
        }

        for( std::size_t i = 0; i < out.size(); ++i )
        {
            std::size_t k = 1;
            for( ;; ++k )
            {
                const std::string cand = wsdetail::suffixLabel( segs[i], k );
                bool clash = false;
                for( std::size_t j = 0; j < out.size() && !clash; ++j )
                {
                    if( j != i && wsdetail::suffixLabel( segs[j], std::min( k, segs[j].size() ) ) == cand )
                    {
                        clash = true;
                    }
                }
                if( !clash || k >= segs[i].size() ) { out[i].label = cand; break; }
            }
        }
    }

    // 4) canonical order: sort by label (byte order) — argv order can never leak into output (§2.1).
    std::sort( out.begin(), out.end(),
               []( const WorkspaceRoot& a, const WorkspaceRoot& b ) noexcept { return a.label < b.label; } );
    return true;
}

// The §P8 labeled spelling `<label>/./<rel>` shared by every merged-workspace path surface (files below,
// and the §P0.5d skipped-oversize rows) — the `./` re-insertion rationale lives at the files call site.
inline std::string labeledWorkspacePath( const std::string& label, const std::string& rootArg, std::string_view crawlPath )
{
    std::string labeled = label;
    const std::string_view rel = relForHash( crawlPath, rootArg );
    if( !rel.empty() ) { labeled.append( "/./" );  labeled.append( rel ); }
    return labeled;
}

// Merge per-root IngestResults (parallel to `roots`, canonical order) into ONE IngestResult:
//   * ing.files[f]     = `<label>/<root-relative-path>` (the §2 labeled identity — what every surface emits)
//   * ing.realPaths[f] = the per-root crawl spelling (what disk I/O must use; see rw::diskPath)
//   * ing.fileRoot[f]  = index into roots (canonical order)
//   * symbol/reference/include/binding ids re-based by one offset pass (§4)
// Node ids follow the concatenation order = (label, relPath) — the same global-sort discipline as today.
inline IngestResult mergeWorkspaceIngests( const std::vector<WorkspaceRoot>& roots,
                                           std::vector<IngestResult>&        parts )
{
    IngestResult m;
    VERIFY( roots.size() == parts.size() );

    std::size_t totFiles = 0, totSyms = 0, totRefs = 0, totIncs = 0, totBinds = 0, totFfis = 0, totRouteDefs = 0, totRouteUses = 0;
    for( const IngestResult& p : parts )
    {
        totFiles += p.files.size();   totSyms  += p.symbols.size();   totRefs += p.references.size();
        totIncs  += p.includes.size(); totBinds += p.bindings.size(); totFfis += p.bindingAliases.size();
        totRouteDefs += p.routeDefs.size();   totRouteUses += p.routeUses.size();   // B6.3
    }
    m.files.reserve( totFiles );          m.realPaths.reserve( totFiles );   m.fileRoot.reserve( totFiles );
    m.symbols.reserve( totSyms );         m.references.reserve( totRefs );
    m.includes.reserve( totIncs );        m.bindings.reserve( totBinds );    m.bindingAliases.reserve( totFfis );
    m.routeDefs.reserve( totRouteDefs );  m.routeUses.reserve( totRouteUses );   // B6.3

    // B0.2: merge the per-part persisted subtoken stats FIRST (before the element moves below) — a pure
    // concatenation with a row-offset rebase, because the merged symbol order IS the part concatenation
    // order and files are appended the same way. All-or-nothing: a part without stats (lean ingest) makes
    // the merged workspace fall back to lexical.h's scan branch — same bytes, just slower.
    {
        bool allPartsHaveLexStats = !parts.empty();
        for( const IngestResult& p : parts )
        {
            allPartsHaveLexStats = allPartsHaveLexStats && p.hasLexStats
                                && p.lexTokenRowOffsets.size() == p.symbols.size() + 1
                                && p.lexDocBodyDl.size()       == p.symbols.size()
                                && p.lexFileSig.size()         == p.files.size() * kLexFileSigWords;
        }
        if( allPartsHaveLexStats )
        {
            std::size_t totPairs = 0;
            for( const IngestResult& p : parts )
            {
                totPairs += p.lexTokenHashes.size();
            }
            m.hasLexStats = true;
            m.lexTokenRowOffsets.reserve( totSyms + 1 );   m.lexTokenRowOffsets.push_back( 0 );
            m.lexDocBodyDl.reserve( totSyms );             m.lexFileSig.reserve( totFiles * kLexFileSigWords );
            m.lexTokenHashes.reserve( totPairs );          m.lexTokenTfs.reserve( totPairs );
            for( const IngestResult& p : parts )
            {
                const std::uint32_t pairOff = std::uint32_t( m.lexTokenHashes.size() );
                for( std::size_t rowIndex = 1; rowIndex < p.lexTokenRowOffsets.size(); ++rowIndex )
                {
                    m.lexTokenRowOffsets.push_back( pairOff + p.lexTokenRowOffsets[ rowIndex ] );
                }
                m.lexTokenHashes.insert( m.lexTokenHashes.end(), p.lexTokenHashes.begin(), p.lexTokenHashes.end() );
                m.lexTokenTfs.insert( m.lexTokenTfs.end(), p.lexTokenTfs.begin(), p.lexTokenTfs.end() );
                m.lexDocBodyDl.insert( m.lexDocBodyDl.end(), p.lexDocBodyDl.begin(), p.lexDocBodyDl.end() );
                m.lexFileSig.insert( m.lexFileSig.end(), p.lexFileSig.begin(), p.lexFileSig.end() );
            }
        }
    }

    for( std::size_t r = 0; r < roots.size(); ++r )
    {
        IngestResult&      p       = parts[r];
        const std::uint32_t fileOff = std::uint32_t( m.files.size() );
        const std::uint32_t symOff  = std::uint32_t( m.symbols.size() );

        // labeled + real paths (label applied HERE, never persisted — the per-root cache stays label-free).
        //
        // §P8 (2026-07-28) — the spelling is `<label>/./<rel>`, NOT `<label>/<rel>`. The audit's finding was
        // that a workspace `id=` could not be matched against a single-root `id=` of the SAME tree: single
        // root emits `<crawl-arg>/<rel>`, and the canonical crawl arg is `.`, so the single-root id is
        // `./src/x.h::S::m` while the workspace id was `lib/src/x.h::S::m` — no relation, not even a suffix.
        // Re-inserting the root-relative `./` makes the labeled path literally `<label>/` + the single-root
        // spelling, so `./src/x.h::S::m` is an exact SUFFIX of the workspace id at a '/' boundary and the
        // two runs join with no normalization step. The rejected alternative `./<label>/<rel>` only makes
        // the path cosmetically `./`-prefixed — it leaves the two ids just as unrelatable, and it breaks the
        // label-prefix strip in resolve.h's §3.1a disk-shape probe.
        //
        // Costs nothing structurally: every path index is keyed through lexicalNormalize(), which drops `.`
        // components, so fileIndex/absIndex and the §3.1 cross-root include probes see the SAME keys as
        // before; git's repo-relative paths still suffix-match at a '/' boundary; `--exclude=<label>/` still
        // prefix-matches. The one visible change is the spelling a user pastes back — and what the tool
        // PRINTS is exactly what it now accepts.
        for( const std::string& f : p.files )
        {
            m.files.push_back( labeledWorkspacePath( roots[r].label, roots[r].arg, f ) );
            m.realPaths.push_back( f );
            m.fileRoot.push_back( std::uint32_t( r ) );
        }

        // §P0.5d: size-dropped files concatenate across roots, relabeled EXACTLY like files above so a
        // --skipped row speaks the same `<label>/./<rel>` vocabulary as every other emitted path. Parts
        // arrive in canonical label order and each part is path-sorted, so the concatenation stays sorted.
        for( SkippedOversize& sk : p.skippedOversize )
        {
            sk.path = labeledWorkspacePath( roots[r].label, roots[r].arg, sk.path );
            m.skippedOversize.push_back( std::move( sk ) );
        }

        for( Symbol& s : p.symbols )
        {
            s.id     += symOff;
            s.fileId += fileOff;
            m.symbols.push_back( std::move( s ) );
        }
        for( Reference& ref : p.references )
        {
            if( ref.fromSymbol != kNoNode )
            {
                ref.fromSymbol += symOff;
            }
            ref.fileId += fileOff;
            m.references.push_back( std::move( ref ) );
        }
        for( Include& inc : p.includes )
        {
            inc.fileId += fileOff;
            m.includes.push_back( std::move( inc ) );
        }
        for( Binding& b : p.bindings )
        {
            if( b.fromSymbol != kNoNode )
            {
                b.fromSymbol += symOff;
            }
            b.fileId += fileOff;
            m.bindings.push_back( std::move( b ) );
        }
        for( BindingAlias& a : p.bindingAliases )
        {
            a.fileId += fileOff;
            m.bindingAliases.push_back( std::move( a ) );
        }
        // B6.3: route DEFs carry no NodeId (handler resolved by name+fileId post-merge, in buildGraph) —
        // only fileId is rebased. Route USEs carry a resolved fromSymbol (like Reference/Binding above) —
        // rebase both id spaces so cross-root (method,path) matching in buildGraph sees consistent ids.
        for( RouteDef& rd : p.routeDefs )
        {
            rd.fileId += fileOff;
            m.routeDefs.push_back( std::move( rd ) );
        }
        for( RouteUse& ru : p.routeUses )
        {
            if( ru.fromSymbol != kNoNode )
            {
                ru.fromSymbol += symOff;
            }
            ru.fileId += fileOff;
            m.routeUses.push_back( std::move( ru ) );
        }
        for( auto& [ fid, text ] : p.docText )
        {
            m.docText[ fid + fileOff ] = std::move( text );
        }
    }

    // root identity tables (consumed by graph.h root-scoping, resolve.h cross-root probes, serialize.h prologue).
    m.rootLabels.reserve( roots.size() );
    m.rootPaths.reserve( roots.size() );
    m.rootReals.reserve( roots.size() );
    for( const WorkspaceRoot& r : roots )
    {
        m.rootLabels.push_back( r.label );
        m.rootPaths.push_back( r.arg );
        m.rootReals.push_back( r.real );
    }

    // macro-edges round: re-run the role="macro" retag over the MERGED corpus (model.h). Each part was
    // retagged at its own ingest() exit, but a #define defined in one root and invoked from another is
    // only visible here. Idempotent — already-Macro refs are skipped by the role==Call guard.
    retagMacroCallReferences( m );

    // r9 shadow suppression: same posture as the retag above — the collision gate ("some indexed symbol
    // carries the name") can only open here for a def that lives in ANOTHER root, so the merged corpus
    // must re-judge. Idempotent (a suppressed reference is simply gone). AFTER the retag, so a site the
    // retag just relabelled role="macro" is out of the erase's role set.
    suppressShadowedReferences( m );

    return m;
}

}   // namespace rw
