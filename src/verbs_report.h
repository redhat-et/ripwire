#pragma once
#if !defined( RIPWIRE_MAIN_TU )
#error "verbs_report.h is a SECTION of src/main.cpp's translation unit - include it only from main.cpp (see the verb-family split note there)"
#endif

// verbs_report.h — the report family, moved VERBATIM from main.cpp in the 2026-08-29 split:
// computeDirModules, the community-presentation cluster (kAccessorNames/isAccessorName, AnchorKey,
// CommunityPresentation, the rank-mass helpers, communityVerbSuffix, communityPresentation,
// IsolateStats/isolateStats), runArchViews (--arch/--deps/--metrics/--seams and friends), the clones/
// hotspot/co-change emitters + runMaintenanceViews, the --skipped health report (runSkipped and its
// row writers), runLayout, runFieldAffinity, the communities/zoom/structure block
// (emitCommunitiesReport, emitCommunityDrill, runZoom, orderFilesByBestSymbolRank, runStructureText).
// Same contract as every verbs_*.h: reopens main.cpp's unnamed namespace — one TU, one unnamed
// namespace, internal linkage unchanged, zero new API surface — under the RIPWIRE_MAIN_TU guard.

namespace
{

// module = a symbol's immediate parent DIRECTORY (the real subsystem: canyon/, steer/, …). Fills
// symDir[symbolId] = module id and dirName[id] = directory path. Shared by --seams and --mermaid —
// one-level Louvain is too fine to be a "module"; the directory is the meaningful boundary.
// R-E (2026-08-17 harvest): rootPrefix empty ⇒ dirName[] keeps the ing.files[] directory spelling unchanged
// (multi-root, or no single root to strip) — relativizing at the point the directory string is FIRST
// derived, same reasoning as communityPresentation() above, so both --seams and --mermaid inherit the fix.
void computeDirModules( const rw::IngestResult& ing, std::vector<std::uint32_t>& symDir, std::vector<std::string>& dirName,
                        std::string_view rootPrefix = {} )
{
    rw::HashMap<std::string, std::uint32_t> dirId;
    const auto idOf = [ & ]( std::string_view d ) -> std::uint32_t
    {
        const auto it = dirId.find( std::string( d ) );
        if( it != dirId.end() )
        {
            return it->second;
        }
        const std::uint32_t id = std::uint32_t( dirName.size() );
        dirId.emplace( std::string( d ), id );  dirName.emplace_back( d );
        return id;
    };
    symDir.assign( ing.symbols.size(), 0 );
    for( std::size_t i = 0; i < ing.symbols.size(); ++i )
    {
        std::string_view  rawP = ing.files[ ing.symbols[i].fileId ];
        std::string_view  p    = rootPrefix.empty() ? rawP : rw::sarif::rootRelativeUri( rawP, rootPrefix );
        const std::size_t sl = p.rfind( '/' );
        symDir[i] = idOf( sl == std::string_view::npos ? std::string_view( "." ) : p.substr( 0, sl ) );
    }
}

// §P6.2: a community label anchored to a trivial accessor ("push_back@svector.h", "empty@notes.h" — the
// real-repo instances that motivated this) tells a reader nothing about a multi-member module. These names
// are called from everywhere by construction (every container user calls push_back/empty/size), so they
// tend to WIN the highest-PageRank/highest-fan-in race despite carrying no semantic content. Table mirrored
// by hand in test/communitylabelcheck.sh (the gate has no way to import a constexpr table from the binary).
constexpr std::array<std::string_view, 31> kAccessorNames = {
    "empty", "size", "begin", "end", "cbegin", "cend", "push_back", "pop_back", "emplace_back",
    "data", "get", "set", "front", "back", "clear", "reserve", "resize", "at", "count", "length",
    "c_str", "insert", "erase", "find", "top", "push", "pop", "key", "value", "first", "second",
};

bool isAccessorName( std::string_view name ) noexcept
{
    for( std::string_view accessor : kAccessorNames )
    {
        if( name == accessor )
        {
            return true;
        }
    }
    // getX / setX getter-setter convention (name[3] uppercase, e.g. "getIndex", "setFlag").
    if( name.size() > 3 && ( name.rfind( "get", 0 ) == 0 || name.rfind( "set", 0 ) == 0 ) )
    {
        return name[3] >= 'A' && name[3] <= 'Z';
    }
    return false;
}

// A community-label anchor's sort key: ASCENDING on (isAccessor, invFanIn, invRank, nodeId), so plain
// operator< on this struct directly implements "prefer non-accessor, then highest fan-in, then highest
// PageRank, then lowest nodeId" without a hand-written comparison chain — that shape already exists as
// notes.h's noteLess() total order, and quality-delta's clone detector (correctly) flags a second one.
// invFanIn/invRank carry the DESCENDING fields inverted so the whole key stays a single ascending tuple.
struct AnchorKey
{
    bool          isAccessor;
    std::uint32_t invFanIn;
    float         invRank;
    rw::NodeId   nodeId;

    bool operator<( const AnchorKey& other ) const noexcept
    {
        return std::tie( isAccessor, invFanIn, invRank, nodeId ) < std::tie( other.isAccessor, other.invFanIn, other.invRank, other.nodeId );
    }
};

// A Louvain community id is an implementation detail, and a dominant directory alone is not unique when
// one directory contains multiple cohesive call clusters. Give every community a deterministic semantic
// label anchored to its highest-fan-in NON-ACCESSOR symbol (falling back to the highest-ranked symbol only
// when every member is an accessor) and exact source location. sigStartByte is a source anchor, not an
// opaque community-id suffix; it disambiguates overloads or generated definitions on the same line.
struct CommunityPresentation
{
    std::vector<std::string> directory;
    std::vector<std::string> label;
};

// community id → its member symbol ids. N=2 is FREE (rw::svector<NodeId,1> and <NodeId,2> are both 16 B,
// against a std::vector's 24) and covers 92.9%/95.5% of communities across the two census corpora: a
// Louvain partition of a call graph is mostly singletons — 88.1%/92.7% of communities hold exactly ONE
// symbol — so nearly every list here was a one-element heap block. 5 990 of them on this tree, 31 369 on
// the validation corpus, rebuilt by each of the four verbs below.
using CommunityMembers = std::vector<rw::SmallVec<rw::NodeId, 2>>;

// V6 (graphrag-transfer): the ordering key for --communities/--zoom module rows. The pre-fix ordering was
// raw member count alone, which lets a large PERIPHERAL leaf cluster (many members, each individually
// low-ranked) outrank a small LOAD-BEARING hub cluster (few members, each highly ranked) — confirmed live
// on ripwire's own tree, where the 572-member `min@infra/fastmath.h` cluster (mostly unrelated call-site
// name collisions) sorts first by size alone. Mass sums the already-computed PageRank vector over a
// community's members instead of merely counting them; member count remains the deterministic SECONDARY
// tie-break (mirroring the pre-fix primary), then community id — see every call site below.
float communityRankMass( const rw::SmallVec<rw::NodeId, 2>& communityMembers, const std::vector<float>& rank ) noexcept
{
    return std::accumulate( communityMembers.begin(), communityMembers.end(), 0.0f,
                            [ & ]( float acc, rw::NodeId nodeId ) { return acc + rank[nodeId]; } );
}

// V6: the shared (rank-mass desc, size desc, id asc) tie-break every module-ordering sort below uses —
// --communities' flat `order`/`ord` and --zoom's per-level `topOrder`/`kids` are all the same three-key
// comparator over a different (mass, members) slice, so it is one function rather than four inline copies.
bool massSizeIdLess( std::uint32_t a, std::uint32_t b, const std::vector<float>& mass, const CommunityMembers& members ) noexcept
{
    if( mass[a] != mass[b] )                     { return mass[a] > mass[b]; }
    if( members[a].size() != members[b].size() ) { return members[a].size() > members[b].size(); }
    return a < b;
}

// V6: --zoom's per-LEVEL counterpart to communityRankMass — one mass vector per level of the multi-level
// hierarchy, precomputed once so every sort at every level (top-level order + every level's child order)
// is an O(1) lookup rather than re-summing a group's members on each comparator call.
std::vector<std::vector<float>> perLevelRankMass( const std::vector<CommunityMembers>& members, const std::vector<float>& rank )
{
    std::vector<std::vector<float>> mass( members.size() );
    for( std::size_t l = 0; l < members.size(); ++l )
    {
        mass[l].resize( members[l].size() );
        for( std::size_t gid = 0; gid < members[l].size(); ++gid )
        {
            mass[l][gid] = communityRankMass( members[l][gid], rank );
        }
    }
    return mass;
}

// V6 (grepai-transfer): a deterministic verb-histogram SUFFIX for a community's label. grepai's RPG
// hierarchy (rpg/extractor_local.go's LocalExtractor + rpg/hierarchy.go's EnrichLabels) tags every symbol
// with its first-word verb (a fixed dictionary lookup) and aggregates the per-cluster frequency into the
// label; ripwire's community label was a single lead-symbol anchor only, so two clusters that happen to
// share an anchor NAME (two different `process` clusters, say) were indistinguishable. This reuses two
// primitives that already exist — naminglens::splitIdentifier for the tokenizer, verbtable::kKnownVerbs
// for the dictionary check (via std::binary_search — see that header for why there is no wrapper
// function here) — and is purely additive: the anchor (§P6.2) stays the primary disambiguator.
//
// Determinism: communityMembers arrives in ascending NodeId order (both call sites below build it with a
// single ascending push loop), so "first-seen" IS a stable, reproducible tie-break; stable_sort by count
// alone over an already-deterministic input cannot introduce nondeterminism, and ties never depend on
// container iteration order because the sort operates on `verbOrder`, a plain vector, not the map.
std::string communityVerbSuffix( const rw::IngestResult& ing, const rw::SmallVec<rw::NodeId, 2>& communityMembers )
{
    std::vector<std::string>                verbOrder;   // first-seen order == the eventual tie-break
    rw::HashMap<std::string, std::uint32_t>  verbCount;
    std::vector<std::string>                 splitScratch;

    for( rw::NodeId nodeId : communityMembers )
    {
        rw::naminglens::splitIdentifier( ing.symbols[nodeId].name, splitScratch );
        if( splitScratch.empty() )
        {
            continue;
        }
        const std::string first = rw::naminglens::toLowerAscii( splitScratch.front() );
        if( !std::binary_search( rw::verbtable::kKnownVerbs.begin(), rw::verbtable::kKnownVerbs.end(), std::string_view( first ), rw::sortutil::svLess ) )
        {
            continue;
        }
        const auto [ it, inserted ] = verbCount.try_emplace( first, 0u );
        if( inserted )
        {
            verbOrder.push_back( first );
        }
        ++it->second;
    }
    std::stable_sort( verbOrder.begin(), verbOrder.end(),
                      [ & ]( const std::string& a, const std::string& b ) { return verbCount[a] > verbCount[b]; } );

    const std::size_t topVerbs = std::min<std::size_t>( 3, verbOrder.size() );
    if( topVerbs == 0 )
    {
        return {};
    }
    std::string suffix = " [";
    for( std::size_t i = 0; i < topVerbs; ++i )
    {
        if( i ) { suffix += ","; }
        suffix += verbOrder[i];
    }
    suffix += "]";
    return suffix;
}

// R-E (2026-08-17 harvest): rootPrefix empty ⇒ dir=/label= keep the ing.files[] directory spelling unchanged
// (multi-root, or no single root to strip) — the SAME convention every other lens's pathRel uses, applied
// here at the point the directory string is first derived so every downstream reader of dir=/label= (both
// emitters below, and the zoom view) inherits the fix instead of needing its own patch.
CommunityPresentation communityPresentation( const rw::IngestResult& ing, const rw::Graph& g,
                                             const CommunityMembers& members,
                                             const std::vector<float>& rank,
                                             std::string_view rootPrefix = {} )
{
    CommunityPresentation out;
    out.directory.resize( members.size() );
    out.label.resize( members.size() );
    const auto* inRowOffset = g.inEdges.rowOffsets();   // in-edge CSR row offsets: fanIn(i) = inRowOffset[i+1]-inRowOffset[i]
    const auto  fanIn       = [ & ]( rw::NodeId nodeId ) { return inRowOffset[ nodeId + 1 ] - inRowOffset[ nodeId ]; };

    for( std::size_t communityIndex = 0; communityIndex < members.size(); ++communityIndex )
    {
        const rw::SmallVec<rw::NodeId, 2>& communityMembers = members[ communityIndex ];
        if( communityMembers.empty() )
        {
            continue;
        }

        rw::HashMap<std::string, std::uint32_t> directoryCount;
        const auto keyOf = [ & ]( rw::NodeId nodeId ) -> AnchorKey
            { return { isAccessorName( ing.symbols[nodeId].name ), ~fanIn( nodeId ), -rank[nodeId], nodeId }; };
        rw::NodeId lead    = communityMembers.front();
        AnchorKey   leadKey = keyOf( lead );
        for( rw::NodeId nodeId : communityMembers )
        {
            std::string_view  rawPath = ing.files[ ing.symbols[nodeId].fileId ];
            std::string_view  path    = rootPrefix.empty() ? rawPath : rw::sarif::rootRelativeUri( rawPath, rootPrefix );
            const std::size_t slash = path.rfind( '/' );
            ++directoryCount[ std::string( slash == std::string_view::npos ? path : path.substr( 0, slash ) ) ];

            const AnchorKey key = keyOf( nodeId );
            if( key < leadKey ) { lead = nodeId; leadKey = key; }
        }

        std::uint32_t dominantCount = 0;
        for( const auto& [ directory, count ] : directoryCount )
        {
            if( count > dominantCount || ( count == dominantCount && directory < out.directory[ communityIndex ] ) )
            {
                dominantCount                   = count;
                out.directory[ communityIndex ] = directory;
        }
        }

        const rw::Symbol& symbol = ing.symbols[ lead ];
        // R-E (2026-08-17 harvest) fix: this MUST read the same relativized spelling out.directory[] above
        // was just built from (rawPath/path further up in this loop), never the raw ing.files[] value — the
        // prefix-strip below matches directoryPrefix (relative) against anchorPath at position 0, and an
        // absolute anchorPath against a relative prefix never matches at 0, so the strip silently no-oped
        // and the full absolute path rode into the label instead of just failing loudly.
        std::string_view   anchorPath = rootPrefix.empty() ? ing.files[ symbol.fileId ] : rw::sarif::rootRelativeUri( ing.files[ symbol.fileId ], rootPrefix );
        const std::string  directoryPrefix = out.directory[ communityIndex ] + "/";
        if( anchorPath.rfind( directoryPrefix, 0 ) == 0 )
        {
            anchorPath.remove_prefix( directoryPrefix.size() );
        }
        out.label[ communityIndex ] = out.directory[ communityIndex ] + "::" + symbol.name + "@"
                                    + std::string( anchorPath ) + ":" + std::to_string( symbol.line ) + ":"
                                    + std::to_string( symbol.sigStartByte )
                                    + communityVerbSuffix( ing, communityMembers );
    }
    return out;
}


struct IsolateStats
{
    std::uint32_t total               = 0;
    std::uint32_t declaration         = 0;
    std::uint32_t header              = 0;
    std::uint32_t source              = 0;
    std::uint32_t document            = 0;
    std::uint32_t connectedSingletons = 0;
};

IsolateStats isolateStats( const rw::IngestResult& ing, const rw::Graph& graph,
                           const CommunityMembers& members ) noexcept
{
    IsolateStats stats;
    const auto*  inRowOffset = graph.inEdges.rowOffsets();

    for( const rw::SmallVec<rw::NodeId, 2>& communityMembers : members )
    {
        if( communityMembers.size() != 1 )
        {
            continue;
        }
        const rw::NodeId nodeId = communityMembers.front();
        const bool isConnected = graph.outOff[nodeId] != graph.outOff[nodeId + 1]
                              || inRowOffset[nodeId] != inRowOffset[nodeId + 1];
        if( isConnected )
        {
            ++stats.connectedSingletons;
        }
    }

    for( const rw::Symbol& symbol : ing.symbols )
    {
        const rw::NodeId nodeId = symbol.id;
        if( graph.outOff[nodeId] != graph.outOff[nodeId + 1] || inRowOffset[nodeId] != inRowOffset[nodeId + 1] )
        {
            continue;
        }
        ++stats.total;

        // Mutually-exclusive provenance, ordered from semantic node kind to definition placement.
        if( symbol.kind == rw::SymKind::Section )
        {
            ++stats.document;
        }
        else if( symbol.sigEndByte >= symbol.endByte )
        {
            ++stats.declaration;
        }
        else if( isHeaderPath( ing.files[symbol.fileId] ) )
        {
            ++stats.header;
        }
        else
        {
            ++stats.source;
        }
    }
    return stats;
}

std::optional<int> runArchViews( const MainDispatch& d )
{
    using namespace rw;
    const Config&                     cfg          = d.cfg;
    const IngestResult&               ing          = d.ing;
    // R-E (2026-08-17 harvest): same single-root condition every other verb's root= uses (sarif.h).
    const bool             avSingleRoot = ing.realPaths.empty() && cfg.roots.size() == 1;
    const std::string_view avRootArg    = avSingleRoot ? cfg.roots[0] : std::string_view();

    // --deps: the file→file physical dependency view (#include / import counts + targets), heaviest
    // first — the "why pull in 100 headers for something simple" detector.
    if( cfg.deps )
    {
        const auto      adj    = resolveIncludeAdj( ing );   // the file→file dependency graph (forward = includes)
        const auto      cycles = sccCycles( adj );           // Lakos cardinal sin: cyclic physical deps
        const DepHealth h      = dependencyHealth( adj );    // per-file transitive cone (unrestricted BFS)
        // §P9.4: <health>'s ccd/acd/nccd are the RESTRICTED (dependency-capable-only) numbers — recomputed
        // from h.transitive (a post-pass, not a second BFS; see graph.h::restrictDependencyHealth).
        const RestrictedDepHealth rh = restrictDependencyHealth( ing, h.transitive );
        std::vector<std::uint32_t> afferent( ing.files.size(), 0 );   // Ca: # files that include each file (blast radius)
        for( const auto& outs : adj )
        {
            for( std::uint32_t g : outs )
            {
                if( g < afferent.size() )
                {
                    ++afferent[g];
                }
            }
        }
        packDeps( stdout, ing, cfg.packTopN > 0 ? cfg.packTopN : 40, cycles, h.transitive, afferent, adj, rh.ccd, rh.acd, rh.nccd, cfg.pageLimit, cfg.pageOffset, avRootArg );
        return 0;
    }

    // --arch=FILE: architectural fitness function. Enforce the user's declared layering rules against the
    // #include graph; print every crossing edge; exit 2 if any (a CI gate). The rules are the user's — ripwire
    // imposes no architecture, only the one declared.
    //
    // S5-B --baseline support: a `.ripwire_arch_baseline` sidecar (one FNV-1a-64 hex hash per line) identifies
    // accepted violations (the current debt). Hash key = src_file + NUL + dst_file + NUL + FROM->TO label.
    // --baseline (first run): write the sidecar with all current violations, exit 0.
    // No flag + sidecar present: suppress baselined violations; exit 2 ONLY for new (un-baselined) ones.
    // --baseline-update: merge current violations into the sidecar (accept new debt deliberately), exit 0.
    if( !cfg.archRules.empty() )
    {
        const ArchRules ar = parseArchRules( std::string( cfg.archRules ) );
        if( !ar.loaded )
        {
            // D9: a malformed non-comment line already got a specific `path:lineNo: reason` message from
            // parseArchRules itself (mirrors --lint-rules) — printing the generic "cannot read" on top would
            // misdescribe a syntax error (file exists, parses to nothing) as a missing/unreadable file.
            if( !ar.parseError )
            {
                std::fprintf( stderr, "ripwire: --arch cannot read rules file: %.*s\n", int( cfg.archRules.size() ), cfg.archRules.data() );
            }
            return 1;
        }
        const auto adj = resolveIncludeAdj( ing );

        // ── EVERY rule is matched against the ROOT-RELATIVE path, never the emitted one ────────────────────
        // ing.files spells each file `<ingest-root>/<relative>` verbatim, so matching a user regex or a layer
        // substring against it makes the rule mean different things in different checkouts. Measured on the
        // shipped fixture: `deny path src/(\w+)/.* -> src/(?!\1/).*` gives 4 violations from a checkout with
        // no `src` in its path and 7 from one named `wt-cf2src`, because the leftmost `src/` regex_search
        // finds is the one inside the CHECKOUT NAME — so \1 captures the wrong segment and the
        // sibling-isolation lookahead spares nothing. The layer half fails the same way and worse: the same
        // `deny test -> render` fixture reports violations="1" run from inside the fixture dir and
        // violations="0" run from the repo root, because `/test/` then appears in the absolute path of the
        // RENDER file too and first-match-wins puts both files in one layer. A CI gate that reports zero
        // because of where the tree was cloned is the failure this closes; test/archcheck.sh's header used to
        // document cd-ing into the fixture as the workaround.
        //
        // relForHash is the SAME normalization the baseline hash has used since it was made portable across
        // root spellings — which is what left the verb half-normalized: a violation's IDENTITY was already
        // root-spelling-independent while the RULE that produced it was not. Anchoring instead (`^src/`) was
        // rejected: it makes the rule author responsible for the depth of a directory they cannot know, and
        // every rule in the docs and fixtures is already written repo-relative, so relative matching is what
        // the grammar has always meant. Documenting it was rejected for the same reason a CI gate exists.
        // Purely lexical (no realpath), so a symlinked or `..`-bearing root stays deterministic; a path that
        // is not under the root degrades to itself, leading-`./`-normalized — the same degrade the baseline
        // hash takes, and the only shape a multi-root invocation could reach here.
        std::vector<std::string_view> relFiles( ing.files.size() );
        for( std::size_t f = 0; f < ing.files.size(); ++f )
        {
            relFiles[f] = relForHash( ing.files[f], cfg.rootPath );
        }

        std::vector<int> lof( ing.files.size() );
        for( std::size_t f = 0; f < ing.files.size(); ++f )
        {
            lof[f] = archLayerOf( ar, relFiles[f] );
        }

        // Collect all violations (sorted for determinism). Each violation carries its own from/to layer
        // labels so layer-name rules and ABS-4 regex PATH-rules share one emit/baseline path. A path-rule
        // violation reports fromLayer="path" toLayer="<from-regex>-><to-regex>" (the matched rule).
        struct Viol
        {
            std::uint32_t from, to;
            std::uint64_t hash;          // stable FNV-1a hash of src+dst+label
            std::string   fromLayer;     // layer name of `from` (or "path" for a regex path-rule)
            std::string   toLayer;       // layer name of `to`   (or the path-rule label)
        };
        std::vector<Viol> viols;
        for( std::size_t f = 0; f < adj.size(); ++f )
        {
            for( std::uint32_t g : adj[f] )
            {
                if( g >= lof.size() )
                {
                    continue;
                }

                // layer-name rules (unchanged): both files layered, distinct layers, edge violates.
                const int la = lof[f], lb = lof[g];
                if( la >= 0 && lb >= 0 && lb != la && archViolates( ar, la, lb ) )
                {
                    const std::string label = ar.layerNames[ la ] + "->" + ar.layerNames[ lb ];
                    // S2: hash root-RELATIVE file paths so a committed baseline is portable across root
                    // spellings (`ripwire .` vs `ripwire /abs/repo`). Display still shows ing.files[…] verbatim.
                    // The same relFiles[] the rule was MATCHED against — one normalization, one meaning.
                    const std::uint64_t h   = archViolHash( relFiles[f], relFiles[g], label );
                    viols.push_back( { std::uint32_t( f ), g, h, ar.layerNames[ la ], ar.layerNames[ lb ] } );
                }

                // ABS-4 regex path-rules: sibling-isolation etc. Independent of layers (an edge can be a
                // path-rule violation even when both files are unlayered). A self-edge can't happen (g!=f
                // by resolveIncludeAdj), so no same-module guard needed beyond the rule's own regex.
                std::size_t ruleIdx = 0;
                if( !ar.pathRules.empty() && pathRuleForbids( ar, relFiles[f], relFiles[g], ruleIdx ) )
                {
                    const PathRule&     pr    = ar.pathRules[ ruleIdx ];
                    const std::string   label = std::string( "path:" ) + pr.from + "->" + pr.to;
                    const std::uint64_t h     = archViolHash( relFiles[f], relFiles[g], label );
                    viols.push_back( { std::uint32_t( f ), g, h, std::string( "path" ), pr.from + "->" + pr.to } );
                }
            }
        }
        std::sort( viols.begin(), viols.end(), [ & ]( const Viol& a, const Viol& b ) { // (src path, dst path, fromLayer) — fromLayer breaks a layer-vs-path tie on the same edge
            if( ing.files[a.from] != ing.files[b.from] )
            {
                return ing.files[a.from] < ing.files[b.from];
            }
            if( ing.files[a.to] != ing.files[b.to] )
            {
                return ing.files[a.to] < ing.files[b.to];
            }
            return a.fromLayer < b.fromLayer;
        } );

        const std::string sidecarPath = archBaselinePath( std::string( cfg.archRules ) );

        // ABS-4: per-MODULE Martin metrics (Ca/Ce/I/A/D + zone) + reachability/orphan, computed ONCE from
        // the same file→file graph. Directory-level approximation from name-based edges (see arch.h) — an
        // additive, descriptive block appended inside <arch>; it never changes the exit code (the regex/
        // layer violations above own that). Emitted in every --arch path (baseline / update / normal).
        const std::vector<ModuleMetric> mods = computeModuleMetrics( ing, adj );

        // Q5b: DSM propagation cost — density of the transitive closure of the file→file dep graph
        // (MacCormack). A single SYSTEM-level number on <metrics> (fixed 3dp → byte-identical). Reported,
        // never a gate. Computed + documented in arch.h::dsmPropagationCostCapable. §P9.4: N is restricted
        // to the SAME dependency-capable mask --deps <health> uses, so the two verbs' denominator agrees.
        const auto   depCapable = dependencyCapableMask( ing );
        const double propCost   = rw::dsmPropagationCostCapable( ing, adj, depCapable );

        // ── shared emitters (one definition → the three return paths can't drift) ──────────────────────
        std::vector<char> ae;   // escapeXml scratch (cleared per call); captured by the lambdas below
        const auto emitViol = [ & ]( const Viol& v, bool showBaselined )
        {
            // escapeXml reuses a single buffer (clears on each call), so capture to strings.
            const std::string ef  = std::string( rw::escapeXml( ing.files[ v.from ], ae ) );
            const std::string efl = std::string( rw::escapeXml( v.fromLayer, ae ) );
            const std::string et  = std::string( rw::escapeXml( ing.files[ v.to ], ae ) );
            const std::string etl = std::string( rw::escapeXml( v.toLayer, ae ) );
            std::printf( "<v from=\"%s\" fromLayer=\"%s\" to=\"%s\" toLayer=\"%s\"%s/>",
                         ef.c_str(), efl.c_str(), et.c_str(), etl.c_str(), showBaselined ? " baselined=\"1\"" : "" );
        };
        const auto emitMetrics = [ & ]()
        {
            // zone summary: pure counts over `mods` (already deterministic: sorted by path, computed once
            // above) — a one-line at-a-glance rollup next to the per-module detail. Zone itself is FOLKLORE
            // (Martin main-sequence heuristic, no independent outcome-based validation — see the EVIDENCE
            // NOTE above computeModuleMetrics in arch.h); the summary
            // carries the same "heuristic, not proof" caveat as the rest of the note= text below.
            // §P6.5: zone="n/a" (arch.h: totalTypes==0, cannot carry an abstractness score) is counted
            // separately, never folded into zone_pain/zone_useless — typed_modules is the honest
            // denominator for those two counts (modules= stays the raw total, facts unchanged on <m> rows).
            // §A10.8: zone_ok was computed (arch.h's default zone, "ok" — outside both the pain and
            // useless corners) but never emitted, so the header's own bucket sum fell 13 short of modules=
            // on the real repo with no attribute admitting the gap. zone_pain + zone_useless + zone_ok +
            // zone_na now partitions modules= exactly — every module lands in exactly one bucket.
            std::uint32_t zonePain = 0, zoneUseless = 0, zoneNa = 0, zoneOk = 0;
            for( const ModuleMetric& mm : mods )
            {
                if( mm.zone == std::string_view( "pain" ) )
                {
                    ++zonePain;
                }
                else if( mm.zone == std::string_view( "useless" ) )
                {
                    ++zoneUseless;
                }
                else if( mm.zone == std::string_view( "n/a" ) )
                {
                    ++zoneNa;
                }
                else if( mm.zone == std::string_view( "ok" ) )
                {
                    ++zoneOk;
                }
            }
            std::printf( "<metrics modules=\"%zu\" typed_modules=\"%zu\" zone_pain=\"%u\" zone_useless=\"%u\" zone_ok=\"%u\" zone_na=\"%u\" propagation_cost=\"%.3f\" note=\"Martin Ca/Ce/I/A/D + zone (main-sequence heuristic, no independent outcome-based validation — folklore, not proof) + reachability — directory-level estimate from name-based deps; zone_na = types=0 modules excluded from zone_pain/zone_useless (no meaningful abstractness score); zone_ok = typed modules in neither corner (the main-sequence middle); zone_pain+zone_useless+zone_ok+zone_na = modules, the full partition; propagation_cost = density of the file-dep transitive closure (MacCormack, validated coupling form) — fraction of files reachable from an average file\">",
                         mods.size(), mods.size() - zoneNa, zonePain, zoneUseless, zoneOk, zoneNa, propCost );
            for( const ModuleMetric& mm : mods )
            {
                const std::string ep = std::string( rw::escapeXml( mm.path, ae ) );
                std::printf( "<m path=\"%s\" ca=\"%u\" ce=\"%u\" types=\"%u\" abstract=\"%u\" I=\"%.2f\" A=\"%.2f\" D=\"%.2f\" zone=\"%s\" reachable=\"%d\"%s%s/>",
                             ep.c_str(), mm.ca, mm.ce, mm.totalTypes, mm.abstractTypes,
                             mm.instability, mm.abstractness, mm.distance, mm.zone, mm.reachable ? 1 : 0,
                             mm.isolated ? " isolated=\"1\"" : "", mm.isLeaf ? " leaf=\"1\"" : "" );
            }
            std::printf( "</metrics>" );
        };

        // The match domain, said ONCE and appended to all three emit paths (normal / baseline /
        // baseline-update). It is a property of the VERB, not of the mode it ran in, and three hand-written
        // copies of one sentence is how two of them end up saying different things.
        static constexpr const char* kArchMatchDomain =
            " Rules — layer substrings and regex path-rules alike — are matched against each file's"
            " ROOT-RELATIVE path (src/core/x.cpp), never the absolute or ./-prefixed spelling shown in from=/to=,"
            " so a rule means the same thing whatever directory the tree was checked out into.";

        // --baseline: write the sidecar with ALL current violations (accept as baseline); exit 0.
        if( cfg.baseline )
        {
            std::unordered_set<std::uint64_t> hashes;
            for( const Viol& v : viols )
            {
                hashes.insert( v.hash );
            }
            if( !archWriteBaseline( sidecarPath, hashes ) )
            {
                std::fprintf( stderr, "ripwire: --baseline cannot write sidecar: %s\n", sidecarPath.c_str() );
                return 1;
            }
            std::fprintf( stderr, "ripwire arch: baseline written (%zu violation(s) accepted) → %s\n",
                          viols.size(), sidecarPath.c_str() );
            // Still emit the arch XML for reference (shows what was baselined), then exit 0.
            std::printf( "<!-- ripwire arch: baseline mode — all %zu violation(s) accepted as baseline. exit=0.%s -->", viols.size(), kArchMatchDomain );
            std::printf( "<arch layers=\"%zu\" rules=\"%zu\" pathRules=\"%zu\" violations=\"%zu\" baselined=\"%zu\" new_violations=\"0\">",
                         ar.layerNames.size(), ar.rules.size(), ar.pathRules.size(), viols.size(), viols.size() );
            for( const Viol& v : viols )
            {
                emitViol( v, true );
            }
            emitMetrics();
            std::printf( "</arch>" );
            return 0;
        }

        // --baseline-update: merge current violations into an existing (or new) sidecar; exit 0.
        if( cfg.baselineUpdate )
        {
            std::unordered_set<std::uint64_t> hashes = archReadBaseline( sidecarPath );
            for( const Viol& v : viols )
            {
                hashes.insert( v.hash );
            }
            if( !archWriteBaseline( sidecarPath, hashes ) )
            {
                std::fprintf( stderr, "ripwire: --baseline-update cannot write sidecar: %s\n", sidecarPath.c_str() );
                return 1;
            }
            std::fprintf( stderr, "ripwire arch: baseline updated (%zu hash(es) total) → %s\n",
                          hashes.size(), sidecarPath.c_str() );
            std::printf( "<!-- ripwire arch: baseline-update mode — %zu violation(s) merged into baseline. exit=0.%s -->", viols.size(), kArchMatchDomain );
            std::printf( "<arch layers=\"%zu\" rules=\"%zu\" pathRules=\"%zu\" violations=\"%zu\" baselined=\"%zu\" new_violations=\"0\">",
                         ar.layerNames.size(), ar.rules.size(), ar.pathRules.size(), viols.size(), hashes.size() );
            for( const Viol& v : viols )
            {
                emitViol( v, true );
            }
            emitMetrics();
            std::printf( "</arch>" );
            return 0;
        }

        // Normal run: load baseline (if present) and split violations into baselined vs new.
        const std::unordered_set<std::uint64_t> baseline    = archReadBaseline( sidecarPath );
        const bool                              hasBaseline  = !baseline.empty() || [ &sidecarPath ]()
        {
            // detect sidecar presence even if it contains only comments (0 hashes)
            std::ifstream probe( sidecarPath );
            return probe.good();
        }();

        std::vector<const Viol*> newViols, basedViols;
        for( const Viol& v : viols )
        {
            if( hasBaseline && baseline.count( v.hash ) )
            {
                basedViols.push_back( &v );
            }
            else
            {
                newViols.push_back( &v );
            }
        }

        // Informational stderr line when baseline is active.
        if( hasBaseline )
        {
            std::fprintf( stderr, "ripwire arch: %zu violation(s) total — %zu suppressed (baseline) — %zu new\n",
                          viols.size(), basedViols.size(), newViols.size() );
        }

        std::printf( "<!-- ripwire arch: layering fitness function — edges that violate your declared rules (layer rules and regex path-rules). exit=2 if any NEW (un-baselined) violation. <metrics> = descriptive Martin Ca/Ce/I/A/D + reachability, never gates.%s -->", kArchMatchDomain );
        std::printf( "<arch layers=\"%zu\" rules=\"%zu\" pathRules=\"%zu\" violations=\"%zu\" baselined=\"%zu\" new_violations=\"%zu\">",
                     ar.layerNames.size(), ar.rules.size(), ar.pathRules.size(), viols.size(), basedViols.size(), newViols.size() );
        for( const Viol& v : viols )
        {
            emitViol( v, hasBaseline && baseline.count( v.hash ) );
        }
        emitMetrics();
        std::printf( "</arch>" );
        return newViols.empty() ? 0 : 2;
    }
    return std::nullopt;
}

// --clones: function/method bodies with identical NORMALIZED token streams (identifiers + literals
// normalized → catches renamed copies). "Reuse, don't reimplement"; "fix one → fix its twins".
// Each group carries type="1|2" (exact/renamed — identical normalized stream) or type="3" (gapped
// near-miss — highly similar stream, an inserted/changed statement; carries similarity=). Type-1/2
// groups are emitted first (biggest-first, unchanged shape); Type-3 pairs follow (findClonesType3).
//
// Its own function (the named-verb-handler shape) rather than a
// fourth arm inside runMaintenanceViews: §P8 gave the row stream a real windowing step, and folding that
// into an already-340-line dispatch body is how a dispatch chain turns back into a god function.

// §A8.1: the root's total= (groups+type3-group-count, the true row total) on the UN-paged path only —
// when paging is active, pageDisclosure's own paging half already carries total=, and a second attribute
// of that name would break XML well-formedness.
std::string cloneUnpagedTotalAttr( bool clonePaging, std::size_t cloneTotal )
{
    if( clonePaging )
    {
        return {};
    }
    char buf[ 32 ];
    std::snprintf( buf, sizeof( buf ), " total=\"%zu\"", cloneTotal );
    return buf;
}

// The idiom-class annotation for one row (cloneidiom.h), and the two root counters over every group. Both
// live out here for the same reason cloneUnpagedTotalAttr does: emitClonesReport is already the longest
// body in this family, and its own --quality-delta row is what says so.
std::string cloneIdiomAttrs( const rw::CloneIdiomVerdict& vd )
{
    if( vd.idiom == rw::CloneIdiom::None )
    {
        return {};
    }
    std::string out = " idiom=\"" + std::string( rw::cloneIdiomName( vd.idiom ) ) + "\"";
    if( vd.demoted )
    {
        out += " demoted=\"1\"";
    }
    return out;
}

struct CloneIdiomTally { std::size_t classified = 0; std::size_t demoted = 0; };

CloneIdiomTally tallyCloneIdioms( const std::vector<rw::CloneIdiomVerdict>& exact, const std::vector<rw::CloneIdiomVerdict>& gapped )
{
    CloneIdiomTally t;
    for( const std::vector<rw::CloneIdiomVerdict>* v : { &exact, &gapped } )
    {
        for( const rw::CloneIdiomVerdict& d : *v )
        {
            t.classified += d.idiom != rw::CloneIdiom::None ? 1u : 0u;
            t.demoted    += d.demoted ? 1u : 0u;
        }
    }
    return t;
}

int emitClonesReport( const rw::Config& cfg, const rw::IngestResult& ing )
{
    using namespace rw;
    // R-E (2026-08-17 harvest): same single-root condition every other verb's root= uses (sarif.h).
    const bool         clnSingleRoot = ing.realPaths.empty() && cfg.roots.size() == 1;
    const std::string  clnRootPrefix = clnSingleRoot ? rw::sarif::rootPrefixOf( cfg.roots[0] ) : std::string();
    std::vector<char>  clnRootEsc;
    const std::string  clnRootAttr   = clnSingleRoot ? ( " root=\"" + std::string( escapeXml( cfg.roots[0], clnRootEsc ) ) + "\"" ) : std::string();

    const std::vector<CloneGroup> cg  = findClones( ing, 40 );
    const std::vector<CloneGroup> cg3 = findClonesType3( ing, 40 );   // gapped near-misses (excludes exact = Type-1/2)
    const int                     cap = cfg.packTopN > 0 ? cfg.packTopN : 40;

    // IDIOM CLASS (cloneidiom.h): a read-only pass over the members of the groups already found. It only
    // ANNOTATES, and it is indexed in lockstep with cg / cg3.
    const std::vector<CloneIdiomVerdict> vx  = classifyCloneGroupIdioms( ing, cg );
    const std::vector<CloneIdiomVerdict> vx3 = classifyCloneGroupIdioms( ing, cg3 );

    // §P8: the root said groups="36" type3="108" while 76 <group> rows followed — NEITHER attribute was the
    // row count, because each list is capped independently. The emission order (all Type-1/2 rows, then all
    // Type-3 rows) is one flat, deterministic row stream, so address it with ONE flat index — [0,cg.size())
    // selects a Type-1/2 group, [cg.size(),…) a Type-3 one — and let both the historic per-list cap and
    // --limit/--offset window the same list:
    //   default (no --limit) — the two per-list caps, i.e. the pre-§P8 rows, byte for byte;
    //   --limit/--offset     — a window over the WHOLE stream, so page N+1 continues page N across the
    //                          Type-1/2 → Type-3 seam instead of restarting inside the second list.
    const bool                 clonePaging = cfg.pageLimit > 0 || cfg.pageOffset > 0;
    const std::size_t          keep12      = clonePaging ? cg.size()  : std::min<std::size_t>( std::size_t( cap > 0 ? cap : 0 ), cg.size()  );
    const std::size_t          keep3       = clonePaging ? cg3.size() : std::min<std::size_t>( std::size_t( cap > 0 ? cap : 0 ), cg3.size() );
    std::vector<std::size_t>   rows;
    rows.reserve( keep12 + keep3 );
    for( std::size_t i = 0; i < keep12; ++i )
    {
        rows.push_back( i );
    }
    for( std::size_t i = 0; i < keep3; ++i )
    {
        rows.push_back( cg.size() + i );
    }

    // The denominator is honest either way: every group that EXISTS, not just the kept ones.
    const std::size_t cloneTotal = cg.size() + cg3.size();
    const PageWindow  clonePage  = clonePaging ? pageWindow( rows.size(), cfg.pageLimit, cfg.pageOffset )
                                               : PageWindow{ 0, rows.size() };
    char              cpab[ kPageDisclosureCap ];

    // §P10.5: --clones and --quality-delta share the detector (kMinCloneTokens) but not the POLICY —
    // quality.h exempts fixture paths and shell test-runners from its duplication kind (documented
    // false-positive classes: sibling gate scripts repeat setup boilerplate BY CONVENTION). --clones is a
    // fact verb, so those groups stay VISIBLE — but each one now says the sibling verb would ignore it,
    // via the SAME predicates (quality::isFixturePath / isTestScriptPath — one policy, two verbs, no copy).
    const auto groupExemptKind = [ & ]( const CloneGroup& gp ) -> const char*
    {
        bool allExempt = true, allScript = true;
        for( NodeId id : gp.members )
        {
            const std::string& p        = ing.files[ ing.symbols[id].fileId ];
            const bool         isScript = quality::isTestScriptPath( p );
            if( !isScript && !quality::isFixturePath( p ) )
            {
                allExempt = false;
            }
            if( !isScript )
            {
                allScript = false;
            }
        }
        return allExempt ? ( allScript ? "shell-runner" : "fixture" ) : nullptr;
    };
    std::size_t exemptGroupCount = 0;
    for( const CloneGroup& gp : cg )
    {
        if( groupExemptKind( gp ) )
        {
            ++exemptGroupCount;
        }
    }
    for( const CloneGroup& gp : cg3 )
    {
        if( groupExemptKind( gp ) )
        {
            ++exemptGroupCount;
        }
    }
    const CloneIdiomTally idiomTally = tallyCloneIdioms( vx, vx3 );   // over ALL groups, like exempt_groups=

    // §A8.1: total= (new) is ALWAYS the true row total (groups+type3-group-count), unpaged included — see
    // cloneUnpagedTotalAttr() above for why it is skipped when paging is active (pageDisclosure already
    // owns total= there; two attributes of the same name would break XML well-formedness).
    // P0-6: the pair graph, resolved into components, and the corpus priced in LOC. Computed over the FULL
    // detector output (cg + cg3), never the displayed window — a summary that shrank with --limit would be
    // a paging artefact, not a measurement.
    const CloneGrouping grouping = groupClones( ing, cg, cg3 );

    std::printf( "<!-- ripwire clones: function bodies with similar normalized token streams (identifiers/literals normalized, so renamed copies match). type=2 exact/renamed (Type-1/2); type=3 gapped near-miss (an inserted/changed statement, similarity in [0.80,1.0)). Reuse don't reimplement; a fix to one likely belongs in all. groups= and type3= are the two GROUP-TYPE totals (each capped independently, so neither is the row count); total= is the true row total (groups + type3-group-count) and is ALWAYS present, paged or not; shown= is the number of group rows that follow this run. capped=\"1\" means rows were dropped. exempt= on a group ⇒ every member is on a path the quality-delta verb's duplication kind deliberately ignores (fixture dirs / shell test-runners repeat boilerplate by convention) — a fact here, never a gate there; exempt_groups= counts them over ALL groups. idiom= on a group names the RECOGNIZED SHAPE every one of its members classifies to, from a CLOSED set of three: threshold-ladder (a chain of if-compare-return and nothing else), switch-name-table (a switch whose every arm is a label plus a literal return), builder-chain (a param-struct initializer chain). demoted=\"1\" additionally means the quality-delta verb's duplication kind reports this group as minor rather than gating on it, which happens only when the WHOLE conjunction holds: every member the same recognized idiom, no two members sharing a single non-keyword identifier, no two members sharing an enclosing context (file plus scope), and the group under 80 normalized tokens. Five cross-domain bucketing ladders that share only the idiom are noise; two ladders over the same enum, or two in one namespace, are a copy. The idiom name is printed precisely so a human can overrule the demotion by reading the members: a demoted row is annotated, never removed. idiom_groups= and demoted_groups= count each of those over ALL groups. FLOOR on the classifier, since a silence here would read as coverage: the shape is read off the body's TOKEN stream and not a parse tree, so a macro-assembled body classifies as whatever its raw tokens spell; the table arm models case-labelled switches only; and builder-chain models the field-assignment spelling, not the fluent chained-call one. gid= on a row is its CLONE COMPONENT: the Type-3 pass reports PAIRS, so three functions that are all near-copies of each other arrive as three rows of two; rows sharing a gid are one cluster, and clone_groups= counts the clusters (union-find over the pair graph, over ALL detected rows, not just the shown ones). dup_pct=duplicated-LOC/total-LOC as a percentage, where duplicated-LOC sums, per cluster, every member's loc EXCEPT the largest member's (one instance is the code you keep, the rest is the redundancy — so a 3-clone cluster counts its lines TWICE) and total-LOC is every function/method body the detector considered; dup_loc= and total_loc= are those two operands. counts_floor=\"1\": the Type-3 pair list is capped upstream, so a dropped pair is a cluster left unmerged — clone_groups/dup_loc/dup_pct are floors, never totals. raise the default cap with limit=N (offset=M pages; a cut listing carries total=/has_more=/next_offset= so a paging loop can continue from it). -->%s", rw::rootRelPathsLegend( clnSingleRoot ) );
    std::printf( "<clones groups=\"%zu\" type3=\"%zu\"%s exempt_groups=\"%zu\" idiom_groups=\"%zu\" demoted_groups=\"%zu\" clone_groups=\"%u\" dup_loc=\"%llu\" total_loc=\"%llu\" dup_pct=\"%.1f\" counts_floor=\"1\"%s%s>",
                 cg.size(), cg3.size(),
                 // M2: pageDisclosure's paging half (which spells total= itself) now also rides on a CUT bare run,
                 // so the verb's own total= yields to it whenever that half is active — never two total= on one root.
                 cloneUnpagedTotalAttr( clonePaging || computePageDisclosure( clonePage.end - clonePage.begin, cloneTotal, clonePage.end,
                                                                             cfg.pageLimit, cfg.pageOffset, true ).paging,
                                        cloneTotal ).c_str(), exemptGroupCount,
                 idiomTally.classified, idiomTally.demoted,
                 grouping.componentCount,
                 static_cast<unsigned long long>( grouping.duplicatedLoc ), static_cast<unsigned long long>( grouping.totalLoc ),
                 cloneDuplicationPercent( grouping ),
                 pageDisclosure( cpab, sizeof( cpab ), clonePage.end - clonePage.begin, cloneTotal, clonePage.end,
                                 cfg.pageLimit, cfg.pageOffset, true ),
                 clnRootAttr.c_str() );
    std::vector<char> esc;
    const auto        ex = [ & ]( std::string_view s ) -> std::string { return std::string( escapeXml( s, esc ) ); };
    for( std::size_t rowIndex = clonePage.begin; rowIndex < clonePage.end; ++rowIndex )
    {
        const std::size_t flat    = rows[ rowIndex ];
        const bool        isType3 = flat >= cg.size();
        const CloneGroup& gp      = isType3 ? cg3[ flat - cg.size() ] : cg[ flat ];
        const char* exemptKind = groupExemptKind( gp );
        char        exemptAttr[ 40 ] = "";
        if( exemptKind )
        {
            std::snprintf( exemptAttr, sizeof( exemptAttr ), " exempt=\"%s\"", exemptKind );
        }
        const unsigned gid = flat < grouping.gidOfGroup.size() ? grouping.gidOfGroup[ flat ] : 0u;
        const std::string idiomAttr = cloneIdiomAttrs( isType3 ? vx3[ flat - cg.size() ] : vx[ flat ] );
        if( isType3 )
        {
            std::printf( "<group type=\"3\" gid=\"%u\" tokens=\"%u\" n=\"%zu\" similarity=\"%.2f\"%s%s>", gid, gp.tokens, gp.members.size(), gp.similarity, exemptAttr, idiomAttr.c_str() );
        }
        else
        {
            std::printf( "<group type=\"%u\" gid=\"%u\" tokens=\"%u\" n=\"%zu\"%s%s>", gp.type, gid, gp.tokens, gp.members.size(), exemptAttr, idiomAttr.c_str() );
        }
        for( NodeId id : gp.members )
        {
            const Symbol&           s  = ing.symbols[id];
            const std::string_view  rp = clnSingleRoot ? rw::sarif::rootRelativeUri( ing.files[ s.fileId ], clnRootPrefix ) : std::string_view( ing.files[ s.fileId ] );
            std::printf( "<f n=\"%s\" p=\"%s:%u\"/>", ex( s.name ).c_str(), ex( rp ).c_str(), s.line );
        }
        std::printf( "</group>" );
    }
    std::printf( "</clones>" );
    return 0;
}


// §P11.3: the worst-function lookup for one --hotspots row, isolated so the row-emission loop inside the
// already-oversized runMaintenanceViews dispatcher gains a function CALL, not another decision point.
struct HotspotWorstFn { const char* name; std::uint32_t line; };
inline HotspotWorstFn hotspotWorstFnOf( const rw::IngestResult& ing, rw::NodeId worstSym )
{
    if( worstSym == rw::kNoNode )
    {
        return { "", 0 };
    }
    const rw::Symbol& s = ing.symbols[ worstSym ];
    return { s.name.c_str(), s.line };
}

// §A9.3 — the two --cochange legends, hoisted out of runMaintenanceViews. They state the SAME predicate
// (dependency-capable = both sides could carry a static dependency at all: source languages yes; sh, md,
// json, ruby and binary/unknown files no — §P9.4's, shared with <health dep_files=>), so they belong beside
// each other where a reader can see they agree, not 60 lines apart inside a 180-branch dispatcher.
// §B7.6 (CA4): both forms emit together= and deg= on every row and NEITHER legend defined together=; the
// only deg= gloss lived in the per-file legend and its denominator is WRONG for the pair form — per-file
// deg is n/commits(the probed file), pair deg is n/min(commits(a), commits(b)), so the same attribute name
// carries two different fractions and the repo-wide reader was handed the other form's definition or none.
// Each legend now defines the pair it actually prints, in the words of its own denominator. §B11.5: window=
// is new on this verb — its two churn siblings have always stamped the window they mined and this one, whose
// numbers are ENTIRELY mined from that window, published nothing, so the 18-month default was readable only
// by reading the source.
inline constexpr const char* kCochangeRepoLegend =
    "<!-- ripwire cochange: file pairs that change together in git but share no transitive static dependency (surprising=1) = hidden coupling. "
    "together= is the number of commits in window= that touched BOTH files (3 or more, or the pair is not reported); "
    "deg= is that count over the commit count of the LESS-CHANGED of the two files, so 1.00 means the quieter file never changed without the other. "
    "conf_ab= is that same fraction over a='s OWN commit count and conf_ba= over b='s, which is the asymmetric form: "
    "conf_ab=1.00 means a never changed without b. deg= is by construction the larger of the two, and driver= names which side it came from "
    "(\"a\" or \"b\") — the file whose changes most reliably imply the other's, and therefore the one to look at first. "
    "driver= is OMITTED when the two directions are equal, because a tie is not a finding. "
    "recur= is how many of sub_windows= the pair actually co-changed in: the mined window is cut into that many equal-COMMIT-COUNT slices "
    "(not equal time — a calendar slice can hold 400 commits or 4), so recur=1 at any together= is one burst of activity and not a persistent "
    "coupling, which is the distinction a single window cannot make. sub_windows= is the denominator and is never omitted; it is smaller than "
    "the nominal 3 only when the window holds fewer commits than that. min_recur= appears when cochange-recur=K (the flag) filtered the rows, so a short "
    "list is explained rather than silent. "
    "window= is the mining window: the default 18 months, or the since=REV|DATE value when one resolved. "
    "surprising= is only defined where BOTH sides could carry a static dependency at all (the same "
    "dependency-capable predicate deps <health dep_files=> uses: source languages yes; sh, md, json, "
    "ruby and binary/unknown files no). A pair with a dep-incapable side keeps its row and carries "
    "dep_capable=0 instead, because for it \"shares no static dependency\" is vacuously true. raise the default cap with limit=N (offset=M pages; a cut listing carries total=/has_more=/next_offset= so a paging loop can continue from it) -->";

inline constexpr const char* kCochangeFileLegend =
    "<!-- ripwire cochange: when you edit this file, git history says you also edit these (surprising=1 => no transitive #include either way). "
    "together= is the number of commits in window= that touched BOTH this file and the partner (3 or more, or the partner is not reported); "
    "deg= is that count over commits=, THIS file's own commit count — a different denominator from the repo-wide pair form, which divides by the less-changed side. "
    "deg= is therefore already DIRECTIONAL here (this file => partner: of your commits, the fraction that also touched the partner); conf_rev= is the other direction, "
    "that same count over the PARTNER's own commit count. deg=1.00 means you never touch this file alone; conf_rev=1.00 means the partner never moves without you. "
    "recur= is how many of sub_windows= equal-COMMIT-COUNT slices of window= the pair actually co-changed in, so recur=1 is one burst rather than a standing coupling; "
    "sub_windows= is that denominator and min_recur= appears when cochange-recur=K (the flag) filtered the list. "
    "window= is the mining window: the default 18 months, or the since=REV|DATE value when one resolved. "
    "surprising= is only defined where BOTH sides could carry a static dependency at all (the dependency-capable "
    "predicate deps <health dep_files=> uses); a pair with a dep-incapable side carries dep_capable=0 instead. raise the default cap with limit=N (offset=M pages; a cut listing carries total=/has_more=/next_offset= so a paging loop can continue from it) -->";

// §CLIO — --cochange-groups' own legend. Mo/Cai/Kazman's Modularity Violation Group is the minimal set of
// GROUPS covering all violating pairs (f_core, f_j), not a pair list: "X co-changes with {A,B,C}, none of
// which it depends on" is one row that names the file to fix, where three pair rows leave the actionable
// part implicit. The minimal cover is set cover and set cover is NP-hard, so what ships is the greedy
// approximation — and the legend says so rather than letting groups= read as a proven minimum. Honesty
// rule #3: a number that cannot be a minimum must not be spelled like one.
inline constexpr const char* kCochangeGroupLegend =
    "<!-- ripwire cochange groups: the surprising=1 violating pairs, collapsed around the file each group names. "
    "core= is the file to look at; each <f p=> under it is a partner it co-changes with and has no transitive static dependency on, "
    "so one group replaces its partners= pair rows. together=/recur=/conf_core= are that pair's own numbers: together= is the shared commit count, "
    "recur= how many of sub_windows= equal-commit-count slices of window= it recurs in, and conf_core= is conf(core => partner) — of the CORE's commits, "
    "the fraction that also touched this partner. groups= is a GREEDY cover, not a proven minimal one (minimum set cover is NP-hard): it is an upper "
    "bound on the smallest number of groups, and repeatedly picking the file covering the most still-uncovered pairs is what produced it. "
    "pairs_covered= is the total membership count and equals the number of surprising=1 pairs, because every violating pair lands in exactly one group. "
    "min_recur= appears when cochange-recur=K (the flag) filtered the pairs BEFORE they were grouped. "
    "Pairs that are not surprising=1, and pairs with a dep-incapable side (dep_capable=0), are not violations and are absent here — "
    "drop the cochange-groups flag for the full pair list. raise the default cap with limit=N (offset=M pages; a cut listing carries total=/has_more=/next_offset= so a paging loop can continue from it) -->";

// §CLIO — min_recur= is emitted by all three --cochange exits and was built three times. One builder, so a
// later edit cannot teach one exit a spelling the others do not use (§P9.1's lesson, one attribute over).
// Returns `buf` so it drops straight into a printf argument list; empty string when the filter is off.
inline const char* coMinRecurAttr( char* buf, std::size_t cap, int minRecur )
{
    buf[ 0 ] = '\0';
    if( minRecur > 0 )
    {
        std::snprintf( buf, cap, " min_recur=\"%d\"", minRecur );
    }
    return buf;
}

// §CLIO — one repo-wide co-change pair, and the document that renders them. `PR` used to be a struct local
// to the --cochange branch; it moved out with the loop for the same reason the legends and the group form did.
struct CoPairRow { std::uint32_t a, b, n; double deg, confAb, confBa; std::uint32_t recur; bool surprising; bool depCapable; };

inline void emitCochangePairs( const rw::IngestResult& ing, const rw::Config& cfg, const std::vector<CoPairRow>& prs,
                               const std::string& windowLabel, std::uint32_t subWindows, const char* minRecAttr,
                               int cap, const std::string& root )
{
    std::vector<char> esc;
    const auto        ex = [ & ]( std::string_view s ) -> std::string { return std::string( rw::escapeXml( s, esc ) ); };
    // R-E (2026-08-17 harvest): same single-root condition every other verb's root= uses (sarif.h).
    const bool         coSingleRoot = ing.realPaths.empty() && cfg.roots.size() == 1;
    const std::string  coRootPrefix = coSingleRoot ? rw::sarif::rootPrefixOf( cfg.roots[0] ) : std::string();
    const std::string  coRootAttr   = coSingleRoot ? ( " root=\"" + ex( cfg.roots[0] ) + "\"" ) : std::string();

    // §P8: this is the verb the audit caught red-handed — pairs="363" with 30 rows, and --limit=3 still
    // emitted all 30, so a paging loop re-read page 0 forever. The window is honest now, and shown= /
    // capped= reconcile pairs= against the rows that follow even with no --limit at all.
    const rw::PageWindow prpw = rw::pageWindow( prs.size(), rw::effectiveRowCap( cfg.pageLimit, cap ), cfg.pageOffset );
    char                 prab[ 192 ];
    std::printf( "%s%s%s", kCochangeRepoLegend, rw::kAtStampLegend, rw::rootRelPathsLegend( coSingleRoot ) );   // sweep: ditto
    std::printf( "<cochange pairs=\"%zu\" window=\"%s\" sub_windows=\"%u\"%s%s%s%s>", prs.size(), windowLabel.c_str(), subWindows, minRecAttr,
                 rw::pageDisclosure( prab, sizeof( prab ), prpw.end - prpw.begin, prs.size(), prpw.end,
                                     cfg.pageLimit, cfg.pageOffset, true ),
                 // R-E fix (2026-08-19): root= sits BEFORE at=, never after. at= stays the LAST attribute on
                 // every git-mined report root — the r26-stamp placement rule --owners' own emitter comment
                 // states and ownerscheck.sh's "at= is still the last attribute" arm is the record of. root=
                 // is a path-interpretation attribute and belongs with the identifying ones, which is also the
                 // slot --grep already puts it in. The first R-E landing appended it and displaced the stamp.
                 coRootAttr.c_str(),
                 rw::gitstamp::atAttr( root ).c_str() );   // §P8: same anchor as the per-file path above
    for( std::size_t pairIndex = prpw.begin; pairIndex < prpw.end; ++pairIndex )
    {
        const CoPairRow& pr = prs[ pairIndex ];
        // §CLIO driver=: the antecedent of the stronger rule. A TIE emits nothing — breaking it by fiat
        // would hand the reader a claim the history does not make.
        const char* driverAttr = ( pr.confAb > pr.confBa ) ? " driver=\"a\""
                               : ( pr.confBa > pr.confAb ) ? " driver=\"b\""
                                                           : "";
        const std::string_view ra = coSingleRoot ? rw::sarif::rootRelativeUri( ing.files[ pr.a ], coRootPrefix ) : std::string_view( ing.files[ pr.a ] );
        const std::string_view rb = coSingleRoot ? rw::sarif::rootRelativeUri( ing.files[ pr.b ], coRootPrefix ) : std::string_view( ing.files[ pr.b ] );
        std::printf( "<pair a=\"%s\" b=\"%s\" together=\"%u\" deg=\"%.2f\" conf_ab=\"%.2f\" conf_ba=\"%.2f\"%s recur=\"%u\"%s/>",
                     ex( ra ).c_str(), ex( rb ).c_str(),
                     pr.n, pr.deg, pr.confAb, pr.confBa, driverAttr, pr.recur,
                     rw::coPairAttr( pr.depCapable, pr.surprising ) );
    }
    std::printf( "</cochange>" );
}

// §CLIO — the --cochange-groups document, hoisted out of runMaintenanceViews for the reason the legends
// above were: a 180-branch dispatcher is not where a rendering loop belongs, and the group form's own
// disclosure rules (cover="greedy", pairs_covered= reconciling with the membership rows, conf_core= fixed
// to the core's direction) are easier to check when they sit together. Pure output: the cover is already
// computed by gitmine.h's cochangeViolationGroups, and `viol` is the vector its members index into.
inline void emitCochangeGroups( const rw::IngestResult& ing, const rw::Config& cfg,
                                const std::vector<rw::CoViolation>& viol, const std::vector<rw::CoGroup>& groups,
                                const std::string& windowLabel, std::uint32_t subWindows, const char* minRecAttr,
                                int cap, const std::string& root )
{
    std::vector<char> esc;
    const auto        ex = [ & ]( std::string_view s ) -> std::string { return std::string( rw::escapeXml( s, esc ) ); };
    // R-E (2026-08-17 harvest): same single-root condition every other verb's root= uses (sarif.h).
    const bool         cgSingleRoot = ing.realPaths.empty() && cfg.roots.size() == 1;
    const std::string  cgRootPrefix = cgSingleRoot ? rw::sarif::rootPrefixOf( cfg.roots[0] ) : std::string();
    const std::string  cgRootAttr   = cgSingleRoot ? ( " root=\"" + ex( cfg.roots[0] ) + "\"" ) : std::string();

    const rw::PageWindow gpw = rw::pageWindow( groups.size(), rw::effectiveRowCap( cfg.pageLimit, cap ), cfg.pageOffset );
    char                 gab[ 192 ];
    std::size_t          coveredTotal = 0;
    for( const rw::CoGroup& g : groups )
    {
        coveredTotal += g.members.size();
    }
    std::printf( "%s%s%s", kCochangeGroupLegend, rw::kAtStampLegend, rw::rootRelPathsLegend( cgSingleRoot ) );
    std::printf( "<cochange groups=\"%zu\" pairs_covered=\"%zu\" cover=\"greedy\" window=\"%s\" sub_windows=\"%u\"%s%s%s%s>",
                 groups.size(), coveredTotal, windowLabel.c_str(), subWindows, minRecAttr,
                 rw::pageDisclosure( gab, sizeof( gab ), gpw.end - gpw.begin, groups.size(), gpw.end,
                                     cfg.pageLimit, cfg.pageOffset, true ),
                 cgRootAttr.c_str(),                        // R-E fix: root= before at= — at= stays LAST (r26)
                 rw::gitstamp::atAttr( root ).c_str() );
    for( std::size_t gi = gpw.begin; gi < gpw.end; ++gi )
    {
        const rw::CoGroup&     g  = groups[ gi ];
        const std::string_view rc = cgSingleRoot ? rw::sarif::rootRelativeUri( ing.files[ g.core ], cgRootPrefix ) : std::string_view( ing.files[ g.core ] );
        std::printf( "<group core=\"%s\" partners=\"%zu\">", ex( rc ).c_str(), g.members.size() );
        for( std::size_t vi : g.members )
        {
            const rw::CoViolation& v       = viol[ vi ];
            const std::uint32_t    partner = ( v.a == g.core ) ? v.b : v.a;
            // conf_core= is always conf(core => partner): the group's subject IS the core, so the direction is
            // fixed by the row rather than left for the reader to infer from an a/b ordering this form never prints.
            const double            confCore = ( v.a == g.core ) ? v.confA : v.confB;
            const std::string_view  rp       = cgSingleRoot ? rw::sarif::rootRelativeUri( ing.files[ partner ], cgRootPrefix ) : std::string_view( ing.files[ partner ] );
            std::printf( "<f p=\"%s\" together=\"%u\" recur=\"%u\" conf_core=\"%.2f\"/>",
                         ex( rp ).c_str(), v.together, v.recur, confCore );
        }
        std::printf( "</group>" );
    }
    std::printf( "</cochange>" );
}

std::optional<int> runMaintenanceViews( const MainDispatch& d )
{
    using namespace rw;
    const Config&                     cfg          = d.cfg;
    const IngestResult&               ing          = d.ing;
    const std::string&                root         = d.root;
    const bool                        multiRoot    = d.multiRoot;
    const std::vector<WorkspaceRoot>& ws           = d.ws;
    // R-E (2026-08-17 harvest): same single-root condition every other verb's root= uses (sarif.h) — shared
    // across every lens dispatched from this one function (hotspots/cochange/context-ratio/comment-coherence/
    // nonlocal-state/naming-consistency/dead-code all read cfg/ing without their own copy).
    const bool         mvSingleRoot = ing.realPaths.empty() && cfg.roots.size() == 1;
    const std::string  mvRootPrefix = mvSingleRoot ? rw::sarif::rootPrefixOf( cfg.roots[0] ) : std::string();
    std::vector<char>  mvRootEsc;
    const std::string  mvRootAttr   = mvSingleRoot ? ( " root=\"" + std::string( escapeXml( cfg.roots[0], mvRootEsc ) ) + "\"" ) : std::string();

    // --ensemble: the FAMILY JOIN (src/ensemble.h owns the join AND its emission, the way --readability owns
    // its lens). It calls four existing measurements and reports which of the four EVIDENCE FAMILIES fire on
    // each function, ranked by the count of distinct families — never by a weighted composite, which is the
    // Maintainability-Index failure mode this verb exists to avoid.
    //
    // GIT IS OPTIONAL HERE, and that is the honesty contract: --hotspots exits 1 without git because its whole
    // output IS the churn product, but three of the ensemble's four families need no history at all. So a
    // failed mining pass hands the join a nullptr and the historical family is reported UNAVAILABLE on the
    // root and on every row — never as "did not fire", which would let a missing measurement read as a clean
    // bill of health. --since is deliberately not plumbed in: the window is part of the disclosed threshold
    // set, and one fixed 12-month window (the same one --hotspots defaults to) keeps hrank= comparable.
    if( cfg.ensemble )
    {
        std::vector<std::uint32_t> churn( ing.files.size(), 0 );
        const rw::SinceScope       noScope;
        const bool                 churnOk = mineChurnPerFile( ing, root, multiRoot, ws, std::string_view(), noScope, rw::ensemble::kEnsembleChurnSince, churn );
        return rw::ensemble::writeEnsembleReport( ing, churnOk ? &churn : nullptr, root, cfg.pageLimit, cfg.pageOffset,
                                                  mvSingleRoot, mvRootPrefix, mvRootAttr );
    }

    // --context-ratio: the LOCAL-REASONING lens (src/contextratio.h owns the measurement AND its emission, the
    // way --readability and --ensemble own theirs). It reads the symbol table and the REFERENCE table — the
    // same substrate --uses reports — and needs neither the resolved call graph nor git, so it sits with the
    // other pure lenses: exit 0 always, no verdict, no threshold. The reference table only carries value
    // read/write sites when ingest ran RICH, which is why cfg.contextRatio joins needsValueUses below.
    if( cfg.contextRatio )
    {
        return rw::contextratio::writeContextRatioReport( ing, cfg.pageLimit, cfg.pageOffset, mvRootPrefix, mvRootAttr );
    }

    // --hotspots: the maintenance-pain map = per-file (Σ cognitive complexity) × (recent git churn).
    // Complexity alone is a weak prioritizer (most complex code is never touched); churn is the
    // orthogonal axis that says "and it keeps changing" — together they locate where bugs/pain live.
    if( cfg.hotspots )
    {
        // --since=REV|DATE: scope the churn window to "what got risky AFTER this point" (the regression
        // lens) instead of the fixed 12-month default. resolveSinceScope degrades an unresolvable value
        // to inactive (nullptr-equivalent), so gitChurnCounts falls back to its unscoped "12 months ago".
        const rw::SinceScope sinceScope = rw::resolveSinceScope( root, cfg.since );

        // §P0.5c: an unresolvable --since used to degrade to ALL history while stdout still printed
        // window="12mo" — a false NON-zero. The churn numbers are real; the window they are labelled with is
        // not, and the only honest signal was a DEGRADED_PATH_ALERT on stderr, invisible to every MCP client.
        // --hotspots is a measurement verb and its window is part of the measurement, so refuse instead.
        if( !cfg.since.empty() && !sinceScope.active )
        {
            std::fprintf( stderr, "ripwire: --hotspots --since='%.*s' is neither a git revision nor a recognizable date — refusing rather than "
                                  "reporting an all-history scan under a window label you did not ask for "
                                  "(e.g. ripwire <dir> --hotspots --since=\"2 weeks ago\", or --since=HEAD~20)\n",
                          int( cfg.since.size() ), cfg.since.data() );
            return 1;
        }

        std::vector<std::uint32_t> churn( ing.files.size(), 0 );
        const bool churnOk = mineChurnPerFile( ing, root, multiRoot, ws, cfg.since, sinceScope, "12 months ago", churn );
        if( !churnOk )
        {
            // Empty churn has TWO causes: (1) genuine git-unavailable / not-a-repo / no-history-at-all →
            // the error + exit 1 below; (2) git fine and history exists but an ACTIVE --since window
            // matched zero commits → a legitimate empty result, not an error. A windowless HEAD probe
            // tells them apart: history present + active scope ⇒ clean empty (ranked="0", commits="0",
            // exit 0), NOT the "git unavailable" error.
            if( sinceScope.active && gitRepoHasHistory( root ) )
            {
                std::vector<char>  sinceEsc;
                const std::string  windowLabel = std::string( escapeXml( std::string_view( cfg.since ), sinceEsc ) );
                std::printf( "<!-- ripwire hotspots: the since-window matched no commits — empty result, not an error (git history exists) -->" );
                // the same partition the main path emits, so a reader parsing one shape parses both:
                // an empty window means every file is unranked for want of churn.
                std::printf( "<hotspots window=\"%s\" files=\"%zu\" ranked=\"0\" unranked_no_churn=\"%zu\" unranked_no_complexity=\"0\" commits=\"0\" shown=\"0\" capped=\"0\"%s></hotspots>",
                             windowLabel.c_str(), ing.files.size(), ing.files.size(), gitstamp::atAttr( root ).c_str() );
                return 0;
            }
            std::fprintf( stderr, "ripwire --hotspots: git unavailable / no history (need a git repo)\n" );
            return 1;
        }

        // per-file Σ cognitive complexity + the single worst function (for "go look HERE")
        std::vector<std::uint64_t> ccxSum( ing.files.size(), 0 );
        std::vector<std::uint32_t> worstCcx( ing.files.size(), 0 );
        std::vector<NodeId>        worstSym( ing.files.size(), kNoNode );
        for( const Symbol& s : ing.symbols )
        {
            if( s.kind != SymKind::Function && s.kind != SymKind::Method )
            {
                continue;
            }
            ccxSum[ s.fileId ] += s.ccx;
            if( s.ccx > worstCcx[ s.fileId ] ) { worstCcx[ s.fileId ] = s.ccx;  worstSym[ s.fileId ] = s.id; }
        }

        // ── ranked= NEEDS A DENOMINATOR, and the two ways a file misses the ranking are not the same ──────
        // A hotspot needs both factors nonzero, so a file with no churn and a file with no functions are
        // dropped by the same `if` and were then indistinguishable inside one unexplained total: ranked="209"
        // over a corpus of 832 files, with 623 absences the reader could neither see nor account for. Worse,
        // one of those absences is not a fact about the file at all — churn is joined to the index by PATH, so
        // a file the join could not bind scores zero exactly like a genuinely quiet one, and there is no
        // signal anywhere that tells the two apart. Counted here, so the total at least reconciles:
        //   ranked + unranked_no_churn + unranked_no_complexity = files, exactly, on every run.
        // unranked_no_churn is deliberately the WIDER bucket (churn==0 whatever the complexity) because that
        // is the honest cut: it is "no commit in the window was attributed to this path", which covers the
        // quiet file AND the unbound one. Separating those two needs the join to report its own misses, which
        // it does not; the legend says so rather than implying the count is purely about quietness.
        std::vector<std::uint32_t> order;
        std::size_t                unrankedNoChurn = 0, unrankedNoComplexity = 0;
        for( std::uint32_t f = 0; f < ing.files.size(); ++f )
        {
            if( !churn[f] )      { ++unrankedNoChurn;      continue; }
            if( !ccxSum[f] )     { ++unrankedNoComplexity; continue; }
            order.push_back( f );
        }
        VERIFY( order.size() + unrankedNoChurn + unrankedNoComplexity == ing.files.size() );
        const auto score = [ & ]( std::uint32_t f ) { return std::uint64_t( churn[f] ) * ccxSum[f]; };
        std::sort( order.begin(), order.end(), [ & ]( std::uint32_t a, std::uint32_t b )
                   { return score( a ) != score( b ) ? score( a ) > score( b ) : ing.files[a] < ing.files[b]; } );

        const int topN = cfg.packTopN > 0 ? cfg.packTopN : 40;
        // window= reports the effective window: "12mo" (default) unless --since resolved to an active scope,
        // in which case it names the scoping value so the agent can trust what it's looking at. §P9 N7: the
        // header COMMENT used to hardcode "(window=12mo)" even for a valid --since, so the two halves of the
        // same screen disagreed. One label, computed once, used in both.
        std::vector<char> sinceEsc;
        const std::string windowLabel = ( !cfg.since.empty() && sinceScope.active )
                                       ? std::string( escapeXml( std::string_view( cfg.since ), sinceEsc ) )
                                       : rw::defaultWindowLabel( root, "12mo" );   // F1: the default window is HEAD-anchored and says so
        std::string windowLabelInComment = windowLabel;   // "--" is illegal inside an XML comment (G4)
        for( std::size_t i = 1; i < windowLabelInComment.size(); ++i )
        {
            if( windowLabelInComment[i - 1] == '-' && windowLabelInComment[i] == '-' )
            {
                windowLabelInComment[i] = ' ';
            }
        }
        std::printf( "<!-- ripwire hotspots: maintenance-pain = complexity × recent churn (window=%s). "
                     "churn=commits touching the file; ccx=Σ cognitive complexity; score=churn×ccx; top=worst function. "
                     "files= is the DENOMINATOR ranked= is drawn from, and a hotspot needs both factors nonzero, so "
                     "ranked= + unranked_no_churn= + unranked_no_complexity= = files= exactly. "
                     "unranked_no_complexity= is a file with commits but no function or method to score (a pure "
                     "declaration header, markdown, config). unranked_no_churn= is a file no in-window commit was "
                     "attributed to — and it CONFLATES two cases this verb cannot tell apart: a genuinely quiet file, "
                     "and one whose path the git-to-index join never bound (a rename, an exclusion, or a spelling the "
                     "join could not match), which scores zero for a reason that is not about the file. Treat it as an "
                     "upper bound on quietness, not a measure of it. "
                     "raise the default cap with limit=N (offset=M pages; a cut listing carries total=/has_more=/next_offset= so a paging loop can continue from it) -->%s%s",
                     windowLabelInComment.c_str(), rw::kAtStampLegend, rw::rootRelPathsLegend( mvSingleRoot ) );   // sweep: at= was undefined on this screen
        if( multiRoot )
        { // §5 comparability caveat: churn scales (commit-count conventions) differ per repo
            std::printf( "<!-- multi-root workspace: churn is mined PER root — hotspot scores are comparable within a root, not across roots -->" );
        }
        // T2: --limit/--offset paginate the sorted `order`. When no --limit, the historic topN cap (40 or
        // --pack-top-n) still bounds the response; --limit overrides it. ranked= is the TRUE total either way.
        // §P8: ranked="185" over 40 emitted rows was a SILENT cap — shown=/capped= now reconcile the two on
        // every run, paginated or not (the one deliberate break in this verb's pre-§P8 byte shape).
        const int         effLimit = effectiveRowCap( cfg.pageLimit, topN );
        const PageWindow  pw       = pageWindow( order.size(), effLimit, cfg.pageOffset );
        char              pab[ 192 ];
        // r26-stamp Task A: anchor churn×complexity scores to the commit (+dirty state) they were mined
        // against — multi-root anchors to the PRIMARY root (d.root); the merged ranking has no per-root
        // sub-scoping to hang a second stamp on, unlike --pr-context's per-root sections.
        std::printf( "<hotspots window=\"%s\" files=\"%zu\" ranked=\"%zu\" unranked_no_churn=\"%zu\" unranked_no_complexity=\"%zu\"%s%s%s>",
                     windowLabel.c_str(), ing.files.size(), order.size(), unrankedNoChurn, unrankedNoComplexity,
                     pageDisclosure( pab, sizeof( pab ), pw.end - pw.begin, order.size(), pw.end,
                                     cfg.pageLimit, cfg.pageOffset, true ),
                     mvRootAttr.c_str(),                    // R-E fix: root= before at= — at= stays LAST (r26)
                     gitstamp::atAttr( root ).c_str() );
        std::vector<char> esc;
        const auto        ex = [ & ]( std::string_view s ) -> std::string { return std::string( escapeXml( s, esc ) ); };
        for( std::size_t i = pw.begin; i < pw.end; ++i )
        {
            const std::uint32_t   f  = order[i];
            // §P11.3: top="main:322" used to read as a file:line pair (every other name:N in the tool means
            // line) but the trailing number was actually the worst function's cognitive complexity — an
            // agent trying to --expand it landed on a bogus line. Split into top= (bare name), top_ccx=
            // (the complexity score, same digits that used to trail the colon) and top_l= (the function's
            // real 1-based source line) so the --expand hop is buildable straight from this row.
            const HotspotWorstFn    worst = hotspotWorstFnOf( ing, worstSym[f] );
            const std::string_view  rp    = mvSingleRoot ? rw::sarif::rootRelativeUri( ing.files[f], mvRootPrefix ) : std::string_view( ing.files[f] );
            std::printf( "<f p=\"%s\" churn=\"%u\" ccx=\"%llu\" score=\"%llu\" top=\"%s\" top_ccx=\"%u\" top_l=\"%u\"/>",
                         ex( rp ).c_str(), churn[f], (unsigned long long)ccxSum[f],
                         (unsigned long long)score( f ), ex( worst.name ).c_str(), worstCcx[f], worst.line );
        }
        std::printf( "</hotspots>" );
        return 0;
    }

    if( cfg.clones )
    {
        return emitClonesReport( cfg, ing ); // body + §P8 paging: emitClonesReport() above
    }

    // --cochange[=FILE]: files that change together in git history but may share NO static dependency —
    // the hidden coupling a call graph can't see (the lockstep partner you'd forget to update). With a
    // FILE: its partners ("when you edit FILE, you historically also edit these"). Without: top surprising
    // pairs repo-wide (high co-change + no #include either way).
    if( cfg.cochange )
    {
        const int         cap = cfg.packTopN > 0 ? cfg.packTopN : rw::kCochangePartnerCap;   // M13: one cap, both surfaces
        std::vector<char> esc;
        const auto        ex = [ & ]( std::string_view s ) -> std::string { return std::string( escapeXml( s, esc ) ); };

        // --since=REV|DATE: scope co-change mining to recent coupling instead of the fixed 18-month
        // default. An unresolvable value degrades to inactive → both branches below fall back unchanged.
        const rw::SinceScope sinceScope   = rw::resolveSinceScope( root, cfg.since );
        const rw::SinceScope* sinceScopeP = cfg.since.empty() ? nullptr : &sinceScope;

        // §B11.5: the effective window label, computed ONCE for all three exits below (per-file, empty,
        // repo-wide) — --hotspots' own rule verbatim: name the --since value when it resolved, else the
        // verb's default. Escaped because it is a user-supplied string reaching an attribute value.
        std::vector<char> coSinceEsc;
        const std::string coWindowLabel = ( !cfg.since.empty() && sinceScope.active )
                                         ? std::string( escapeXml( std::string_view( cfg.since ), coSinceEsc ) )
                                         : rw::defaultWindowLabel( root, "18mo" );   // F1: the default window is HEAD-anchored and says so

        if( !cfg.cochangeFile.empty() )                                    // partners of one file → shared core (gitmine.h)
        {
            const std::uint32_t fid = resolveFileSuffix( ing, cfg.cochangeFile );
            if( fid == UINT32_MAX )
            {
                // F11: the CLI arm was the thin one — "file not found: src/grap.h" and nothing else, while
                // the MCP `cochange` twin already named the nearest indexed path and said a suffix is enough.
                // One suggester (didyoumean.h::nearestIndexedFileClause) now serves both.
                std::fprintf( stderr, "ripwire --cochange: file not found: %.*s — it takes ONE indexed file path, e.g. "
                                      "--cochange=src/graph.h%s\n",
                              int( cfg.cochangeFile.size() ), cfg.cochangeFile.data(),
                              rw::nearestIndexedFileClause( ing, cfg.cochangeFile ).c_str() );
                return 1;
            }
            // multi-root §5: the probed file belongs to exactly ONE root — mine that repo only (co-change is
            // per-repo by construction; partners in another root are undefined and never synthesized).
            const std::uint32_t fidRoot  = multiRoot ? ing.fileRoot[ fid ] : UINT32_MAX;
            const std::string&  fidRepo  = multiRoot ? ws[ fidRoot ].arg : root;
            const rw::SinceScope fidScope = multiRoot ? rw::resolveSinceScope( fidRepo, cfg.since ) : sinceScope;
            std::uint32_t                commits    = 0;
            std::uint32_t                subWindows = 0;
            std::vector<CoPartner>       ps         = cochangePartners( fidRepo, ing, cfg.cochangeFile, commits,
                                                                        cfg.since.empty() ? nullptr : &fidScope, fidRoot, &subWindows );
            // §CLIO: --cochange-recur=K drops the partners whose co-change does not RECUR across the mined
            // window's sub-windows. Applied BEFORE partners= is counted, so partners= keeps meaning "the rows
            // this run is reporting" and reconciles with shown=/capped= exactly as it always has; the reason
            // the number shrank is published as min_recur= on the element rather than left to be inferred.
            if( cfg.cochangeRecur > 0 )
            {
                const std::uint32_t minRecur = std::uint32_t( cfg.cochangeRecur );
                ps.erase( std::remove_if( ps.begin(), ps.end(), [ & ]( const CoPartner& p ) { return p.recur < minRecur; } ), ps.end() );
            }
            // §P8: partners= is the true total; shown=/capped= say how many of them actually follow, and
            // --limit/--offset window the (already deterministically sorted) partner list.
            const PageWindow  ppw = pageWindow( ps.size(), effectiveRowCap( cfg.pageLimit, cap ), cfg.pageOffset );
            char              pab[ 192 ];
            char              pminrec[ 40 ];
            coMinRecurAttr( pminrec, sizeof( pminrec ), cfg.cochangeRecur );
            std::printf( "%s%s%s", kCochangeFileLegend, rw::kAtStampLegend, rw::rootRelPathsLegend( mvSingleRoot ) );   // sweep: at= was undefined on this screen
            // §P8 vocabulary: at="<sha>[+dirty]" — cochange is a PURE git-history product (every number in
            // it is mined from `git log`), and it was one of the last two verbs of that kind emitting numbers
            // with no anchor to the HEAD that produced them. Same gitstamp::atAttr every other repo-reading
            // verb already calls, placed LAST on the element to match --hotspots' existing attribute order.
            std::printf( "<cochange of=\"%s\" commits=\"%u\" window=\"%s\" sub_windows=\"%u\"%s partners=\"%zu\"%s%s%s>",
                         ex( mvSingleRoot ? rw::sarif::rootRelativeUri( ing.files[fid], mvRootPrefix ) : std::string_view( ing.files[fid] ) ).c_str(),
                         commits, coWindowLabel.c_str(), subWindows, pminrec, ps.size(),
                         pageDisclosure( pab, sizeof( pab ), ppw.end - ppw.begin, ps.size(), ppw.end,
                                         cfg.pageLimit, cfg.pageOffset, true ),
                         mvRootAttr.c_str(),                // R-E fix: root= before at= — at= stays LAST (r26)
                         gitstamp::atAttr( root ).c_str() );
            for( std::size_t partnerIndex = ppw.begin; partnerIndex < ppw.end; ++partnerIndex )
            {
                const std::string_view rp = mvSingleRoot ? rw::sarif::rootRelativeUri( ing.files[ ps[ partnerIndex ].fileId ], mvRootPrefix )
                                                          : std::string_view( ing.files[ ps[ partnerIndex ].fileId ] );
                std::printf( "<f p=\"%s\" together=\"%u\" deg=\"%.2f\" conf_rev=\"%.2f\" recur=\"%u\"%s/>",
                             ex( rp ).c_str(), ps[ partnerIndex ].together,
                             ps[ partnerIndex ].deg, ps[ partnerIndex ].degRev, ps[ partnerIndex ].recur,
                             coPairAttr( ps[ partnerIndex ] ) );
            }
            std::printf( "</cochange>" );
            return 0;
        }

        // repo-wide: ALL co-change pairs (needs the full pair map, unlike the single-file core above).
        // Multi-root §5: mined per root (each against its own files); the merged set list is safe because
        // commits are disjoint across repos — a pair can only ever form WITHIN one root's sets.
        std::vector<std::vector<std::uint32_t>> sets;
        if( multiRoot )
        {
            for( std::uint32_t r = 0; r < ws.size(); ++r )
            {
                const rw::SinceScope rs = rw::resolveSinceScope( ws[r].arg, cfg.since );
                std::vector<std::vector<std::uint32_t>> part = gitCommitFileSets( ws[r].arg, ing, "18 months ago", 30,
                                                                                  cfg.since.empty() ? nullptr : &rs, r );
                for( std::vector<std::uint32_t>& cs : part )
                {
                    sets.push_back( std::move( cs ) );
                }
            }
        }
        else
        {
            sets = gitCommitFileSets( root, ing, "18 months ago", 30, sinceScopeP );
        }
        if( sets.empty() )
        {
            // Same two-cause split as --hotspots: an ACTIVE --since window that matched zero commits is a
            // legitimate empty result (git history exists), not the git-unavailable error. The windowless
            // HEAD probe distinguishes them → clean empty (pairs="0", commits="0", exit 0) vs error+exit 1.
            if( sinceScope.active && gitRepoHasHistory( root ) )
            {
                std::printf( "<!-- ripwire cochange: the since-window matched no commits — empty result, not an error (git history exists) -->" );
                // The at= stamp belongs on the EMPTY result too — "no pairs at this HEAD" is itself a claim
                // about a specific HEAD, and --hotspots' own zero-row path already stamps for that reason.
                // sub_windows="0" is the literal truth on this path: no commit was mined, so no partition was
                // made. Emitting the nominal 3 here would name a denominator that never existed.
                std::printf( "<cochange pairs=\"0\" commits=\"0\" window=\"%s\" sub_windows=\"0\" shown=\"0\" capped=\"0\"%s></cochange>", coWindowLabel.c_str(), gitstamp::atAttr( root ).c_str() );
                return 0;
            }
            std::fprintf( stderr, "ripwire --cochange: git unavailable / no history (need a git repo)\n" );
            return 1;
        }
        // §CLIO: one cell per pair carrying BOTH the support count and the sub-window bitmask, rather than a
        // second parallel map — the inner loop below is O(files-per-commit^2) under the 30-file bulk cap, so
        // one hash probe per pair per commit instead of two is the difference that stays inside the warm
        // latency budget on a big history.
        struct CoCell { std::uint32_t n = 0; std::uint32_t subWindowMask = 0; };
        const std::uint32_t                    subWindows = coEffectiveSubWindows( sets.size() );
        std::vector<std::uint32_t>             freq( ing.files.size(), 0 );
        HashMap<std::uint64_t, CoCell>         pair;                       // (lo<<32|hi) → co-change count + recurrence mask
        for( std::size_t commitIndex = 0; commitIndex < sets.size(); ++commitIndex )
        {
            const std::vector<std::uint32_t>& cs  = sets[ commitIndex ];
            const std::uint32_t               bit = std::uint32_t( 1u ) << coSubWindowOf( commitIndex, sets.size(), subWindows );
            for( std::uint32_t f : cs )
            {
                ++freq[f];
            }
            for( std::size_t i = 0; i < cs.size(); ++i )
            {
                for( std::size_t j = i + 1; j < cs.size(); ++j )
                { // cs is sorted+unique → cs[i] < cs[j]
                    CoCell& cell = pair[ ( std::uint64_t( cs[i] ) << 32 ) | cs[j] ];
                    ++cell.n;
                    cell.subWindowMask |= bit;
                }
            }
        }
        // P9.1: the repo-wide pair scan must use the SAME predicate as the per-file path (gitmine.h's
        // StaticIncludeCoupling) — a bare 1-hop check here previously mis-flagged transitively-coupled
        // pairs (ingest.cpp↔model.h, main.cpp↔notes.h) as "surprising" hidden coupling.
        const StaticIncludeCoupling coupling( ing );
        const auto staticDep = [ & ]( std::uint32_t a, std::uint32_t b ) -> bool { return coupling.isStaticallyCoupled( a, b ); };
        constexpr std::uint32_t kSupport = 3;                              // need ≥3 shared commits (kill coincidence)

        // repo-wide: the surprising couplings (high co-change, no static dep) — hidden architectural debt
        std::vector<CoPairRow>      prs;   // CoPairRow + its emitter are hoisted above — see emitCochangePairs
        const std::uint32_t         minRecur = cfg.cochangeRecur > 0 ? std::uint32_t( cfg.cochangeRecur ) : 0u;
        for( const auto& [k, cell] : pair )
        {
            if( cell.n < kSupport )
            {
                continue;
            }
            const std::uint32_t recur = coRecurrenceOf( cell.subWindowMask );
            if( recur < minRecur )
            {
                continue;   // §CLIO: filtered here so pairs= counts what is reported, and min_recur= on the element says why
            }
            const std::uint32_t a = std::uint32_t( k >> 32 ), b = std::uint32_t( k );
            const std::uint32_t mn = std::min( freq[a], freq[b] );
            // §CLIO directional confidence: conf(a=>b) over a's OWN commit count, conf(b=>a) over b's. deg=
            // divides by the SMALLER count, so it is by construction max(confAb, confBa) — the same magnitude
            // it has always been, now with the direction it came from recoverable.
            const bool isDepCapable = coPairDependencyCapable( ing, a, b );   // §A9.3, the same predicate the per-file path uses
            prs.push_back( { a, b, cell.n, mn ? double( cell.n ) / mn : 0.0,
                             coConfidence( cell.n, freq[a] ), coConfidence( cell.n, freq[b] ), recur,
                             isDepCapable && !staticDep( a, b ), isDepCapable } );
        }
        std::sort( prs.begin(), prs.end(), [ & ]( const CoPairRow& x, const CoPairRow& y ) { // surprising-and-strong first
            if( x.surprising != y.surprising )
            {
                return x.surprising;
            }
            if( x.deg != y.deg )
            {
                return x.deg > y.deg;
            }
            return x.n > y.n;
        } );
        char coMinRec[ 40 ];
        coMinRecurAttr( coMinRec, sizeof( coMinRec ), cfg.cochangeRecur );   // shared with the per-file exit above

        // --cochange-groups: the Modularity Violation GROUP form. The cover itself is gitmine.h's
        // cochangeViolationGroups (domain logic, and the place its determinism argument belongs); this
        // branch selects the violating pairs, hands them over, and renders the result.
        if( cfg.cochangeGroups )
        {
            std::vector<CoViolation> viol;
            for( const CoPairRow& p : prs )
            {
                if( p.surprising )
                {
                    viol.push_back( { p.a, p.b, p.n, p.recur, p.confAb, p.confBa } );
                }
            }
            const std::vector<CoGroup> groups = cochangeViolationGroups( viol, ing.files.size() );
            emitCochangeGroups( ing, cfg, viol, groups, coWindowLabel, subWindows, coMinRec, cap, root );
            return 0;
        }

        emitCochangePairs( ing, cfg, prs, coWindowLabel, subWindows, coMinRec, cap, root );
        return 0;
    }

    // --owners[=SYM]: S5-C bus-factor analysis — recency-weighted author ownership per file.
    // Each commit is weighted by exp(-λ·age) with a 6-month half-life so recent work counts more.
    // Output: per-file top author + weighted share + unique-author count + bus-factor flag (bf=1 when
    // top author holds >80% of weighted commits).  With =SYM: restrict to the file that defines SYM.
    // Deterministic: files sorted by path, authors within a file by (score desc, email asc).
    if( cfg.owners )
    {
        // Resolve an optional symbol name to its file id (--owners=SYM mode)
        std::uint32_t onlyFileId    = UINT32_MAX;
        std::size_t   symDefCount   = 0;              // §B11.3-class: how many definitions the fold below discarded
        std::string   owSeedSym;                      // @-seed rebind: the rebound definition's name, disclosed as sym=
        if( !cfg.ownersSym.empty() )
        {
            // §B11.1 — this arm resolved with the BARE-NAME resolver and refused in the pre-§B4.2 dialect, so
            // a `file:name` spelling — the grammar its nine SYM-taking siblings accept, and what an agent
            // pastes out of a p="file:line" row — was rejected outright with four words about a symbol that
            // plainly exists. Both halves join the family: resolveAllByNameQualified (bare names resolve
            // byte-identically; splitQualifiedSpec leaves a spec with no ':' alone) and the shared
            // selectorNotFoundMessage, which says whether the PATH half or the NAME half is the fault.
            const std::vector<NodeId> defs = resolveAllByNameQualified( ing, cfg.ownersSym );
            if( defs.empty() )
            {
                std::fprintf( stderr, "%s\n", selectorNotFoundMessage( ing, "ripwire: --owners symbol not found: ",
                                                                       cfg.ownersSym, "--owners=" ).c_str() );
                return 1;
            }
            // §B11.3's SHAPE, found by that item's sweep and closed here: this is a fold that reports a scalar.
            // `defs[0]` is ONE of N definitions of the name — the lowest node id — and the report then covers
            // that definition's file alone under files="1", which reads as "this symbol lives in one file"
            // while --callers/--uses/--impact/--mentions on the same name all disclose defs="3". The pick is a
            // reasonable default (it matches --around/--lego's resolveFocus), but it was invisible.
            onlyFileId  = ing.symbols[ defs[0] ].fileId;
            symDefCount = defs.size();
            if( cfg.ownersSym.front() == '@' )
            {
                // @-seed rebind (2026-08-30): the resolver's @-tier returned the seed's ONE enclosing
                // definition, so defs[0] IS the seed's own def and file — sym= names the rebind while
                // of= keeps echoing the seed as typed.
                owSeedSym = ing.symbols[ defs[0] ].name;
            }
        }

        // multi-root §5: ownership mined per root against its own files; the concatenation stays fileId-sorted
        // because canonical merge order makes every root-r fileId smaller than every root-(r+1) fileId.
        std::vector<FileOwnership> ownerships;
        if( multiRoot )
        {
            for( std::uint32_t r = 0; r < ws.size(); ++r )
            {
                if( onlyFileId != UINT32_MAX && ing.fileRoot[onlyFileId] != r )
                {
                    continue; // --owners=SYM: its one root
                }
                std::vector<FileOwnership> part = gitFileAuthors( ws[r].arg, ing, onlyFileId, 182.5, r );
                for( FileOwnership& ow : part )
                {
                    ownerships.push_back( std::move( ow ) );
                }
            }
        }
        else
        {
            ownerships = gitFileAuthors( root, ing, onlyFileId );
        }
        if( ownerships.empty() )
        {
            std::fprintf( stderr, "ripwire --owners: git unavailable / no history (need a git repo with commits)\n" );
            return 1;
        }

        // Output: terse XML consistent with the rest of the report verbs. §P6.4: authors=1 files (determin-
        // istically bf=1 share=1.00 — see countUniformOwnership() above) fold into ONE <uniform files="M"/>
        // row instead of M identical <f/> rows; --detail=N restores the full listing (ownershipRowsToPrint()).
        // <owners files="N"><uniform .../><f p="<path>" authors="N" bf="0|1" top="<email>" share="0.NN"/></owners>
        const int                      cap           = cfg.packTopN > 0 ? cfg.packTopN : int( ownerships.size() );
        const bool                     detail        = cfg.detail > 0;
        const std::size_t              uniformCount  = countUniformOwnership( ownerships, cap );
        const std::vector<std::size_t> printRows     = ownershipRowsToPrint( ownerships, cap, detail );

        // XML comments forbid a literal "--" (G4): the flag is spelled "detail=1" below, not "--detail=1".
        std::printf( "<!-- ripwire owners: recency-weighted author ownership (half-life=6mo). "
                     "bf=1 = one person holds >80%% of weighted commits (bus-factor risk); "
                     "authors=1 files fold into <uniform/> below; pass detail=1 for the full per-file listing. "
                     "files= means two different things by DEPTH here and is deliberately not renamed: on the ROOT it is how "
                     "many files were ANALYSED; on the <uniform/> fold it is how many of them collapsed into that one row. "
                     "With a SYM, of= echoes it and defs= is how many DEFINITIONS that name has: this report covers the file "
                     "holding the FIRST of them (lowest node id, the same pick around and lego make), so defs= above 1 means "
                     "the other definitions' files were NOT analysed. Qualify with file:name to choose one. An @FILE:LINE "
                     "seed rebinds to the innermost definition enclosing that line (sym= names it) and covers exactly that "
                     "definition's file -->%s%s",
                     rw::kAtStampLegend, rw::rootRelPathsLegend( mvSingleRoot ) );   // sweep: ditto
        // §P8: --limit/--offset used to be accepted and ignored here (757 rows whatever you asked for). They
        // window `printRows`, which is already deterministic (files sorted by path). files= keeps meaning the
        // number of files ANALYSED — a different quantity from the <f/> row count, which is why the paging
        // half carries its own total= (the row denominator) rather than reusing files=. The <uniform/> fold
        // is a summary of the whole run, not a row, so it is emitted on every page.
        const PageWindow  owpw = pageWindow( printRows.size(), effectiveRowCap( cfg.pageLimit, int( printRows.size() ) ), cfg.pageOffset );
        char              owab[ 192 ];
        // §P8 vocabulary: at="<sha>[+dirty]" — like --cochange above, ownership is mined entirely from git
        // history (recency-weighted commit shares), so every share= here is a claim about ONE HEAD. It was
        // the second and last unanchored pure-git verb.
        // the SYM-mode fold disclosure sits between the paging block and at=, so at= stays last (the r26-stamp
        // placement rule) and no existing `files="N"`-adjacency assertion moves on the all-files form.
        std::vector<char> owSymEsc;
        // the @-seed rebind disclosure sits between of= and defs= — the same slot the MCP owners twin
        // uses (§P8: one element name, one attribute order, both surfaces).
        const std::string owSeedAttr = owSeedSym.empty() ? std::string{}
                                                         : " sym=\"" + std::string( escapeXml( owSeedSym, owSymEsc ) ) + "\"";
        const std::string owSymAttr  = cfg.ownersSym.empty()
                                     ? std::string{}
                                     : " of=\"" + std::string( escapeXml( cfg.ownersSym, owSymEsc ) ) + "\"" + owSeedAttr
                                     + " defs=\"" + std::to_string( symDefCount ) + "\"";
        std::printf( "<owners files=\"%zu\"%s%s%s%s>", ownerships.size(),
                     pageDisclosure( owab, sizeof( owab ), owpw.end - owpw.begin, printRows.size(), owpw.end,
                                     cfg.pageLimit, cfg.pageOffset, false ),
                     owSymAttr.c_str(),
                     mvRootAttr.c_str(),                    // R-E fix: root= before at= — at= stays LAST (r26)
                     gitstamp::atAttr( root ).c_str() );
        if( !detail && uniformCount > 0 )
        {
            std::printf( "<uniform authors=\"1\" bf=\"1\" share=\"1.00\" files=\"%zu\"/>", uniformCount );
        }
        std::vector<char> owEsc;
        for( std::size_t rowIndex = owpw.begin; rowIndex < owpw.end; ++rowIndex )
        {
            const std::size_t    i   = printRows[ rowIndex ];
            const FileOwnership& ow  = ownerships[i];
            const AuthorScore&   top = ow.authors[0];
            // path and email are externally-controlled strings — escape both to keep output valid XML.
            const std::string_view rp = mvSingleRoot ? rw::sarif::rootRelativeUri( ing.files[ ow.fileId ], mvRootPrefix ) : std::string_view( ing.files[ ow.fileId ] );
            const auto ep = rw::escapeXml( rp, owEsc );
            std::printf( "<f p=\"%.*s\" authors=\"%u\" bf=\"%d\"",
                         int( ep.size() ), ep.data(), ow.uniqueAuthors, int( ow.busFactor ) );
            const auto em = rw::escapeXml( top.email, owEsc );
            std::printf( " top=\"%.*s\" share=\"%.2f\"/>", int( em.size() ), em.data(), top.share );
        }
        std::printf( "</owners>" );
        return 0;
    }
    return std::nullopt;
}

// §L1 — the skipped verb's legend, hoisted to file scope. A 20-line string literal inside the emitter is
// 20 lines of runSkipped's measured LOC for zero branching, and this text is the reader's ONLY definition
// of every attribute below it, so it earns its own name. NB: a literal `--flag` spelling is illegal inside
// an XML comment (no `--` in a comment), so it names flags in prose and leans on the attribute names.
constexpr const char* kSkippedLegend =
    "<ctx><!-- ripwire skipped report: WHY the index does not contain a file, and which files it DOES contain but cannot"
                 " vouch for. Two row kinds. <f p= why= bytes= .../> = a file the crawl passed over, one row per drop, why= being"
                 " oversize (exceeded a size ceiling; limit= names which — the max-file-size flag's value in max_file_size=, or the fixed"
                 " .json/.yaml config ceilings that flag does not raise, json_ceiling=), excluded (matched an exclude substring; ext= is"
                 " its extension), or unsupported-ext (ext= has no grammar and no doc handler in this build — the class that hides a whole"
                 " LANGUAGE). <h p= why= .../> = a file that IS indexed and stays indexed, flagged for the reader: why=degraded-parse means"
                 " the parse contains ERROR/MISSING nodes (err= counts them, err_ratio= is the share of the file's bytes covered by top-most"
                 " ERROR spans) and is a PARSER-STATE fact, never a syntax verdict — a valid file in a dialect this grammar predates reads"
                 " degraded too; why=minified-suspect means whitespace frequency ws_freq= is under 0.070 across the leading 4096 bytes"
                 " (files under 256 bytes are never flagged — too little text to judge). Nothing here is dropped by these two flags."
                 " <lang n= files= symbols=/> = corpus composition BY LANGUAGE: one row per language this build extracted at"
                 " least one symbol OR one file for, sorted files DESC then name ASC, absent languages simply not rowed. files= is a"
                 " FLOOR (derived from symbol-bearing files only — a file with zero extracted symbols is not attributed to any"
                 " language); symbols= is exact, every run. unindexed= (below) is its mirror: languages this build could not read at"
                 " all; this is what it DID read, broken down."
                 " HEADER: indexed= is files= on the map; the ACCOUNTING INVARIANT is indexed= + oversize= + excluded= = the candidate"
                 " population the crawl ENUMERATED, at every ceiling and exclude setting. unsupported_ext= counts source/text-looking files"
                 " outside that population (binary/asset extensions are deliberately not counted — an unindexed .png is a picture, not a"
                 " language this build failed to read); its per-extension breakdown is the <e x= files=/> rows, which the map header rolls"
                 " up as unindexed= — a TOP-6 list, and the map's unindexed_exts= beside it names how many DISTINCT such"
                 " extensions exist, present exactly when that list was cut and absent when it is complete."
                 " excluded_dirs= counts SUBTREES an exclude pruned: the walk stopped at the directory, so how many files"
                 " are under them is UNKNOWN, not zero, and they are in no count here. pruned_dirs= counts the subtrees this build ALWAYS"
                 " prunes by policy — the committed noise/vendor/build denylist and any directory holding a CMakeCache.txt — with the same"
                 " consequence: the walk stopped there, their contents are UNKNOWN rather than zero, and they are in no count here. The two"
                 " are separate because the answer to \"why is my tree missing\" differs: one is a rule you passed, the other is a rule this"
                 " build carries. degraded_parse= / minified_suspect= count the h rows."
                 " ignored= is ignored_files= on the map: files git's OWN ignore rules cover"
                 " (.gitignore / .git/info/exclude / core.excludesFile), tested LAST — after the extension, the exclude and the built-in"
                 " denylist — so it only ever counts a file that would OTHERWISE have been indexed, and the accounting invariant above"
                 " reads indexed= + oversize= + excluded= + ignored=. ignored_dirs= counts SUBTREES those rules pruned, with the same"
                 " consequence excluded_dirs= carries: the walk stopped at the directory, contents UNKNOWN rather than zero. Both classes"
                 " are rowed (why=\"ignored\" for the files, why=\"ignored-dir\" for the subtrees, bytes=\"0\" on a subtree because a"
                 " directory has no size this verb can honestly report). ignore_mode= names WHICH rule set applied: git (consulted and"
                 " applied), off (the no-ignore flag), unavailable (no git work tree at this root, or no git binary — the full walk), root-ignored"
                 " (the root is ITSELF inside an ignored subtree, so honouring the rules would empty the map — the full walk). Only"
                 " ignore_mode=\"git\" can put a non-zero number beside the two counters; every other mode means nothing was consulted, which"
                 " is not the same claim as nothing being ignored."
                 " unmeasured= counts indexed files this run never parsed (a doc-format file extracted by the doc pass, a binary sniff or"
                 " nesting guard refusal, a read failure) — they are absent from the health counts, not clean. rows_capped=\"1\" means a row"
                 " list hit its 500-row ceiling, so the rows are a SAMPLE of the count beside them; every count stays exact. A zero means"
                 " none found. -->";

// §L1 — one indexed file the health pass flagged. `fileIndex` indexes IngestResult::files.
struct SkipHealthFinding
{
    std::size_t fileIndex = 0;
    bool        degraded  = false;   // the parse holds ERROR/MISSING nodes
    bool        minified  = false;   // whitespace frequency under the threshold
};

// §L1 — the health pass's whole answer: the flagged files, plus the three counts the root discloses.
struct SkipHealthReport
{
    std::vector<SkipHealthFinding> findings;
    std::size_t                    degraded   = 0;
    std::size_t                    minified   = 0;
    std::size_t                    unmeasured = 0;   // indexed but never parsed — NOT the same as clean
};

// §L1 — classify every indexed file's recorded health against the two disclosure thresholds.
//
// The thresholds live HERE and not in ingest deliberately: the ingest carries facts (error-node counts,
// whitespace counts), this carries the presentation choice about where to draw a line, and keeping the two
// apart is what lets the legend state the threshold beside the raw numbers a reader would use to
// second-guess it. Cheap — four u32s per file, no I/O.
//
// fileBytes == 0 is the ingest's NOT-MEASURED sentinel (an indexed file always has a size): the file was
// never parsed — a doc-format file the doc post-pass extracted, a binary-sniff or nesting-guard refusal, a
// read failure. Those are counted as unmeasured and are absent from the other two counts, because "we did
// not look" is not "we looked and it was clean".
SkipHealthReport classifySkipHealth( const rw::IngestResult& ing )
{
    using namespace rw;
    SkipHealthReport out;
    for( std::size_t f = 0; f < ing.files.size(); ++f )
    {
        const FileHealth h = f < ing.fileHealth.size() ? ing.fileHealth[ f ] : FileHealth{};
        if( h.fileBytes == 0 )
        {
            ++out.unmeasured;
            continue;
        }
        const std::size_t   sample   = h.fileBytes < kHealthWsSampleBytes ? h.fileBytes : kHealthWsSampleBytes;
        const std::uint32_t wsPerMil = sample == 0 ? 1000u : std::uint32_t( ( std::uint64_t( h.wsBytes ) * 1000ull ) / sample );
        const bool          degraded = rw::fileParseDegraded( ing, f );   // the ONE predicate (model.h) — grep + refusals route through it too
        const bool          minified = h.fileBytes >= kMinifiedMinBytes && wsPerMil < kMinifiedWsPerMille;
        out.degraded += degraded ? 1u : 0u;
        out.minified += minified ? 1u : 0u;
        if( degraded || minified )
        {
            out.findings.push_back( { f, degraded, minified } );
        }
    }
    return out;
}

// §L1 — the <f why="oversize"> rows (§P0.5d's original population), each carrying the ceiling that dropped
// it so `bytes > limit` is self-evident per row.
// R-E (2026-08-17 harvest): rootPrefix empty ⇒ p= keeps sk.path unchanged (multi-root, or no single root to
// strip) — sk.path/sf.path/hr's ing.files[] lookup below are already-materialized copies of the crawl's own
// spelling (see emitGrepReport's note), so this relativizes them at PRINT time, same convention every other
// lens's pathRel uses.
void writeOversizeRows( rw::XmlWriter& w, std::vector<char>& esc, const std::vector<rw::SkippedOversize>& rows,
                        std::string_view rootPrefix = {} )
{
    for( const rw::SkippedOversize& sk : rows )
    {
        char row[ 96 ];
        const std::string_view rp = rootPrefix.empty() ? std::string_view( sk.path ) : rw::sarif::rootRelativeUri( sk.path, rootPrefix );
        w.write( "<f p=\"" );  w.write( rw::escapeXml( rp, esc ) );
        std::snprintf( row, sizeof( row ), "\" why=\"oversize\" bytes=\"%llu\" limit=\"%llu\"/>",
                       ( unsigned long long ) sk.sizeBytes, ( unsigned long long ) sk.limitBytes );
        w.write( row );
    }
}

// §L1 — the <f> rows for the two non-size drop classes. `why` is a caller-supplied literal from a CLOSED
// vocabulary (excluded / unsupported-ext), never data — see test/fixedbufsweep.sh's row for this buffer.
// §N6-C — the ignore mode as one stable token. A LABEL, not a boolean: "unavailable" and "root-ignored"
// both mean the full walk ran, and a reader debugging a corpus needs to tell them apart.
const char* ignoreModeLabel( rw::IgnoreMode m ) noexcept
{
    switch( m )
    {
        case rw::IgnoreMode::Git:         return "git";
        case rw::IgnoreMode::Off:         return "off";
        case rw::IgnoreMode::RootIgnored: return "root-ignored";
        case rw::IgnoreMode::Unavailable: break;
    }
    return "unavailable";
}

void writeDropRows( rw::XmlWriter& w, std::vector<char>& esc, const std::vector<rw::SkippedFile>& rows, const char* why,
                    std::string_view rootPrefix = {} )
{
    for( const rw::SkippedFile& sf : rows )
    {
        char row[ 96 ];
        const std::string_view rp = rootPrefix.empty() ? std::string_view( sf.path ) : rw::sarif::rootRelativeUri( sf.path, rootPrefix );
        w.write( "<f p=\"" );  w.write( rw::escapeXml( rp, esc ) );
        std::snprintf( row, sizeof( row ), "\" why=\"%s\" bytes=\"%llu\" ext=\"", why, ( unsigned long long ) sf.sizeBytes );
        w.write( row );
        w.write( rw::escapeXml( sf.ext, esc ) );
        w.write( "\"/>" );
    }
}

// §L1 — the <e> rows: the FULL unindexed-extension histogram. Uncapped here on purpose; the map header's
// unindexed= is the capped roll-up, and this verb is the surface a reader comes to for the whole list.
void writeUnindexedExtRows( rw::XmlWriter& w, std::vector<char>& esc, const std::vector<rw::UnindexedExt>& rows )
{
    for( const rw::UnindexedExt& ue : rows )
    {
        char row[ 64 ];
        w.write( "<e x=\"" );  w.write( rw::escapeXml( ue.ext, esc ) );
        std::snprintf( row, sizeof( row ), "\" files=\"%llu\"/>", ( unsigned long long ) ue.files );
        w.write( row );
    }
}

// §L1 — the <h> rows: files that ARE indexed and STAY indexed, flagged for the reader. Both raw numbers and
// both ratios are emitted on every row, whichever class fired, so a reader can second-guess either
// threshold without re-running anything. err_ratio is over the FILE's bytes; ws_freq is over the leading
// sample, which is its own denominator — hence two ratios and not one.
void writeHealthRows( rw::XmlWriter& w, std::vector<char>& esc, const rw::IngestResult& ing,
                      const std::vector<SkipHealthFinding>& findings, std::string_view rootPrefix = {} )
{
    for( const SkipHealthFinding& hr : findings )
    {
        const rw::FileHealth h       = ing.fileHealth[ hr.fileIndex ];
        const std::size_t    sample  = h.fileBytes < rw::kHealthWsSampleBytes ? h.fileBytes : rw::kHealthWsSampleBytes;
        const double         errFrac = double( h.errBytes ) / double( h.fileBytes );
        const double         wsFrac  = sample == 0 ? 1.0 : double( h.wsBytes ) / double( sample );
        char row[ 192 ];
        const std::string_view rp = rootPrefix.empty() ? std::string_view( ing.files[ hr.fileIndex ] ) : rw::sarif::rootRelativeUri( ing.files[ hr.fileIndex ], rootPrefix );
        w.write( "<h p=\"" );  w.write( rw::escapeXml( rp, esc ) );
        std::snprintf( row, sizeof( row ), "\" why=\"%s%s%s\" err=\"%u\" err_ratio=\"%.3f\" ws_freq=\"%.3f\" bytes=\"%u\"/>",
                       hr.degraded ? "degraded-parse" : "",
                       ( hr.degraded && hr.minified ) ? "," : "",
                       hr.minified ? "minified-suspect" : "",
                       h.errNodes, errFrac, wsFrac, h.fileBytes );
        w.write( row );
    }
}

// W3-S item 3 (2026-08-19) — corpus composition BY LANGUAGE. §L1 answers "what did the crawl DROP" in
// full (unindexed=, the <e>/<f>/<h> rows above); nothing answers "what IS this corpus, by language" —
// unindexed= names languages the build could not read at all, but a reader still cannot tell a
// 90%-Python repo from a 90%-C++ one from anything the tool prints. One count per rw::Lang, sorted
// deterministically (never hash-map iteration order — the same discipline unindexedExts' own
// lessUnindexedExt follows).
//
// files= is derived from SYMBOLS, not a second file-extension table: every symbol already carries the
// exact Lang ingest assigned it (Symbol::lang, ingest.cpp's real per-file grammar decision — the single
// source of truth), so re-deriving language from a hand-mirrored extension list (the way lintrules.h's
// langOfPath admittedly does, "kept in sync by hand", for its OWN narrower dependency-analysis purpose)
// would risk a SECOND, drifting classification for the same fact. Trade-off, stated once rather than
// buried in a caveat comment: a file that produced zero symbols (empty, or a language whose grammar
// found nothing extractable) is not attributed to any language row here. This under-counts files= by
// exactly that population — never inflates it, and never silently double-counts — so files= is a FLOOR
// on any given language's true file count, same convention as skipped_oversize=/unindexed= use
// elsewhere in this file (never a fabricated total). symbols= has no such gap: it is the exact,
// already-computed Symbol::lang tally, a total on every run.
struct LangCount { rw::Lang lang; std::uint64_t files = 0, symbols = 0; };

// files DESC, name ASC tiebreak — the SAME mixed-direction swapped-std::tie shape lessUnindexedExt
// (model.h) uses, so a reader who has already learned that ordering reads this one for free.
bool lessLangCount( const LangCount& a, const LangCount& b ) noexcept
{
    const std::string_view an = rw::langTag( a.lang ), bn = rw::langTag( b.lang );
    return std::tie( b.files, an ) < std::tie( a.files, bn );
}

std::vector<LangCount> computeLangCounts( const rw::IngestResult& ing )
{
    using namespace rw;
    // fileLangOf[f] = the Lang every symbol in file f agrees on (ingest parses one file under one
    // grammar, Metal/CUDA's C++/CUDA-as-a-language routing included, so there is nothing to disambiguate
    // — the last write among a file's own symbols is the same value every earlier one already wrote).
    std::vector<Lang> fileLangOf( ing.files.size(), Lang::Unknown );
    std::array<std::uint64_t, std::size_t( Lang::Lua ) + 1> symbolTally {};   // sized on the LAST enum member
    for( const Symbol& s : ing.symbols )
    {
        if( s.fileId < fileLangOf.size() )
        {
            fileLangOf[ s.fileId ] = s.lang;
        }
        if( std::size_t( s.lang ) < symbolTally.size() )
        {
            ++symbolTally[ std::size_t( s.lang ) ];
        }
    }
    std::array<std::uint64_t, std::size_t( Lang::Lua ) + 1> fileTally {};     // sized on the LAST enum member
    for( Lang l : fileLangOf )
    {
        if( l != Lang::Unknown && std::size_t( l ) < fileTally.size() )
        {
            ++fileTally[ std::size_t( l ) ];
        }
    }
    std::vector<LangCount> out;
    for( std::size_t i = 0; i < fileTally.size(); ++i )
    {
        if( fileTally[i] == 0 && symbolTally[i] == 0 )
        {
            continue;   // absent = this language contributed nothing, never a printed zero row
        }
        out.push_back( { Lang( i ), fileTally[i], symbolTally[i] } );
    }
    std::sort( out.begin(), out.end(), lessLangCount );
    return out;
}

void writeLangRows( rw::XmlWriter& w, std::vector<char>& esc, const std::vector<LangCount>& rows )
{
    for( const LangCount& lc : rows )
    {
        char row[ 64 ];
        w.write( "<lang n=\"" );  w.write( rw::escapeXml( rw::langTag( lc.lang ), esc ) );
        std::snprintf( row, sizeof( row ), "\" files=\"%llu\" symbols=\"%llu\"/>",
                       ( unsigned long long ) lc.files, ( unsigned long long ) lc.symbols );
        w.write( row );
    }
}

// §P0.5d / §L1 — --skipped: WHY the index does not contain a file, and which files it DOES contain but
// cannot vouch for. The disclosure doctrine ("every truncation is disclosed") applied to the corpus itself.
//
// §P0.5d built this verb around ONE drop reason: the header said HOW MANY files a size ceiling dropped and
// this verb named WHICH. §L1 closes what that left open — the verb answered `oversize="0"` on a tree it had
// passed over wholesale, which reads as "index complete" and is the honesty contract's own failure mode (a
// zero meaning "none exists" rather than "none found"). Two additions, both measured against real corpora:
//
//   * the DROP taxonomy grows why=excluded and why=unsupported-ext beside why=oversize. The second is the
//     load-bearing one: it is how a whole LANGUAGE disappears. On facebook/infer (11 923 files, ~60% OCaml,
//     which this build has no grammar for) the map's top-ranked symbols were meaningless test fixtures and
//     nothing anywhere said the primary language had contributed nothing.
//   * a SECOND row kind, <h>, for files that ARE indexed and stay indexed but whose extraction cannot be
//     vouched for: degraded-parse (ERROR/MISSING nodes in the tree) and minified-suspect (whitespace
//     frequency under the threshold). Run over 252 deliberately-invalid Python files this verb used to
//     report a clean bill of health while every symbol it had drawn from them was garbage. NOTHING is
//     dropped by either flag — this lane only ever adds disclosure.
//
// The binary-sniff and read-failure parse skips are still deliberately NOT drop rows: those files keep their
// fileId and stay inside files=. They now surface as unmeasured= instead — present in the corpus, absent
// from the health counts, which is the honest position for a file that was never parsed.
// Read-only; exit 0 always: a report, not a gate.
std::optional<int> runSkipped( const MainDispatch& d )
{
    using namespace rw;
    const Config&       cfg = d.cfg;
    const IngestResult& ing = d.ing;
    if( !cfg.skippedList )
    {
        return std::nullopt;
    }
    // R-E (2026-08-17 harvest): same single-root condition every other verb's root= uses (sarif.h).
    const bool         skSingleRoot = ing.realPaths.empty() && cfg.roots.size() == 1;
    const std::string  skRootPrefix = skSingleRoot ? rw::sarif::rootPrefixOf( cfg.roots[0] ) : std::string();
    std::vector<char>  skRootEsc;
    const std::string  skRootAttr   = skSingleRoot ? ( " root=\"" + std::string( escapeXml( cfg.roots[0], skRootEsc ) ) + "\"" ) : std::string();

    {
        XmlWriter         w( stdout );
        std::vector<char> esc;

        const SkipHealthReport health = classifySkipHealth( ing );

        w.write( kSkippedLegend );
        char hdr[ 768 ];   // fourteen counters, each up to 20 digits, + ignore_mode= — sized well clear of a truncated count
        // mirror ingest()'s own zero-ceiling clamp so the header states the EFFECTIVE bound, never a raw 0
        const std::size_t effectiveMax = cfg.maxFileBytes == 0 ? kDefaultMaxFileBytes : cfg.maxFileBytes;
        const CrawlSkips& cs           = ing.crawlSkips;
        const bool        rowsCapped   = cs.excluded.size() < cs.excludedFiles || cs.unsupported.size() < cs.unsupportedFiles
                                      || cs.ignored.size() < cs.ignoredFiles || cs.ignoredDirRows.size() < cs.ignoredDirs;   // §N6-C
        std::snprintf( hdr, sizeof( hdr ),
                       "<skipped indexed=\"%zu\" oversize=\"%zu\" excluded=\"%llu\" unsupported_ext=\"%llu\" excluded_dirs=\"%llu\""
                       " pruned_dirs=\"%llu\" ignored=\"%llu\" ignored_dirs=\"%llu\" ignore_mode=\"%s\""
                       " degraded_parse=\"%zu\" minified_suspect=\"%zu\" unmeasured=\"%zu\" max_file_size=\"%zu\" json_ceiling=\"%zu\""
                       " yaml_ceiling=\"%zu\"%s",
                       ing.files.size(), ing.skippedOversize.size(),
                       ( unsigned long long ) cs.excludedFiles, ( unsigned long long ) cs.unsupportedFiles,
                       ( unsigned long long ) cs.excludedDirs, ( unsigned long long ) cs.prunedDirs,
                       ( unsigned long long ) cs.ignoredFiles, ( unsigned long long ) cs.ignoredDirs, ignoreModeLabel( cs.ignoreMode ),
                       health.degraded, health.minified, health.unmeasured,
                       effectiveMax, kMaxJsonConfigBytes, kMaxYamlConfigBytes,
                       rowsCapped ? " rows_capped=\"1\"" : "" );
        w.write( hdr );
        // R-E: root= is unbounded (a deep absolute path), so it is NOT folded into the fixed `hdr` buffer
        // above (the V1-1 truncation class main.cpp's own history warns about) — written separately as the
        // std::string it already is, then the tag is closed.
        w.write( skRootAttr );
        w.write( ">" );

        writeOversizeRows( w, esc, ing.skippedOversize, skRootPrefix );
        writeDropRows( w, esc, cs.excluded,    "excluded", skRootPrefix );
        writeDropRows( w, esc, cs.unsupported, "unsupported-ext", skRootPrefix );
        writeDropRows( w, esc, cs.ignored,        "ignored",     skRootPrefix );   // §N6-C: the files git's rules covered
        writeDropRows( w, esc, cs.ignoredDirRows, "ignored-dir", skRootPrefix );   // §N6-C: the subtrees they pruned
        writeUnindexedExtRows( w, esc, cs.unindexedExts );
        writeHealthRows( w, esc, ing, health.findings, skRootPrefix );
        writeLangRows( w, esc, computeLangCounts( ing ) );   // W3-S item 3: corpus composition by language
        w.write( "</skipped></ctx>" );
    }
    std::fputc( '\n', stdout );
    return 0;
}

// The CPU/GPU CONTRACT verb: --layout=STRUCT. layout.h owns the whole
// computation (the lexical field walk, the offset arithmetic, the static_assert sweep, the mirror diff);
// this handler resolves the flag, refuses loudly on a bare/unknown name, and maps the verdict to an exit
// code. Deliberately MULTI-ROOT capable — "does the service's copy of this struct still match the client's"
// is exactly a merged-graph question, and the mirror check is the reason the field note asked for it.
std::optional<int> runLayout( const MainDispatch& d )
{
    using namespace rw;
    const Config& cfg = d.cfg;

    if( !cfg.layoutFlag )
    {
        return std::nullopt;
    }

    if( cfg.layoutStruct.empty() )
    {
        std::fprintf( stderr, "ripwire: --layout needs a struct/class name (e.g. --layout=AudioUniforms, or --layout=file.h:Name)\n" );
        return 1;
    }

    const layout::LayoutResult result = layout::computeLayout( d.ing, cfg.layoutStruct );
    if( !result.found )
    {
        // Three very different refusals. A name that IS indexed but carries no C-family aggregate body is a
        // Python/Java/Go/Rust/Swift class or a forward declaration — saying "no such struct" there would be
        // flatly wrong and send the reader hunting for a spelling mistake that does not exist. An `enum`/
        // `enum class`/`enum struct` (§P6.11) is its own case, named explicitly: it used to fall through to
        // findDefBody's generic aggregate scan (a scoped enum's head contains the word "class"/"struct" too)
        // and silently degrade to a confident modeled="1" zero-field struct instead of refusing.
        if( result.enumCandidates > 0 )
        {
            std::fprintf( stderr, "ripwire: --layout: '%.*s' is an enum, --layout models structs (a scoped/unscoped enum's underlying type is not a byte layout)\n",
                          int( cfg.layoutStruct.size() ), cfg.layoutStruct.data() );
        }
        else if( result.bodilessCandidates > 0 )
        {
            std::fprintf( stderr, "ripwire: --layout: '%.*s' is indexed but has no C-family aggregate body — this verb models C/C++/ObjC byte layout only\n",
                          int( cfg.layoutStruct.size() ), cfg.layoutStruct.data() );
        }
        else
        {
            // F13: the struct set is loaded and 494 names wide — offer the near-miss from it, exactly as
            // every SYMBOL selector one keystroke away does, instead of only "try --grep=<what you typed>".
            std::fprintf( stderr, "ripwire: --layout: no indexed struct/class named '%.*s'%s (try --grep=%.*s to find its spelling)\n",
                          int( cfg.layoutStruct.size() ), cfg.layoutStruct.data(),
                          rw::nearestAggregateName( d.ing, cfg.layoutStruct ).c_str(),
                          int( cfg.layoutStruct.size() ), cfg.layoutStruct.data() );
        }
        return 1;
    }
    // R-E (2026-08-17 harvest): same single-root condition every other verb's root= uses (sarif.h).
    const std::string_view layoutRootArg = ( d.ing.realPaths.empty() && cfg.roots.size() == 1 ) ? cfg.roots[0] : std::string_view();
    layout::writeLayout( stdout, result, layoutRootArg );
    return layout::layoutContractBroken( result ) ? 2 : 0;   // exit 2 = mirror drift or a contradicted tripwire
}

// --field-affinity[=STRUCT]: the CACHE-LOCALITY lens. src/fieldaffinity.h owns the whole computation (the
// aggregate modelling pass, the member-access enumeration, the affinity graph, Chilimbi's separation weight
// and the two findings); this handler resolves the flag, refuses a filter that names nothing modelable, and
// emits. Exit 0 ALWAYS on a successful run — this is a report and its findings are ADVICE, so wiring it to a
// non-zero exit would make a non-monotonic axis (see the header's Go-fieldalignment caution) into a gate.
// Single-root by construction: the offset model reads on-disk paths, which a merged workspace relabels.
std::optional<int> runFieldAffinity( const MainDispatch& d )
{
    using namespace rw;
    const Config& cfg = d.cfg;

    if( !cfg.fieldAffinity )
    {
        return std::nullopt;
    }
    if( d.multiRoot )
    {
        std::fprintf( stderr, "ripwire: --field-affinity is single-root only (the offset model reads on-disk paths, "
                              "which a merged workspace relabels) — run it once per root\n" );
        return 1;
    }

    const fieldaffinity::AffResult res =
        fieldaffinity::computeFieldAffinity( d.ing, d.fanIn, cfg.fieldAffinityStruct );

    // R-E (2026-08-17 harvest): same single-root condition every other verb's root= uses (sarif.h) — always
    // true here (the multi-root refusal above already returned), but ing.realPaths.empty() is still the
    // canonical guard so this cannot silently diverge if that invariant ever changes.
    const bool         faSingleRoot = d.ing.realPaths.empty() && cfg.roots.size() == 1;
    const std::string  faRootPrefix = faSingleRoot ? rw::sarif::rootPrefixOf( cfg.roots[0] ) : std::string();
    std::vector<char>  faRootEsc;
    const std::string  faRootAttr   = faSingleRoot ? ( " root=\"" + std::string( escapeXml( cfg.roots[0], faRootEsc ) ) + "\"" ) : std::string();

    // A filter that matched no modelable aggregate is a REFUSAL, not an empty report: an empty
    // <fieldaffinity/> reads as "this struct has no co-access", which is a different and much stronger
    // claim than "this name never resolved to a C-family aggregate body this verb can model".
    if( !cfg.fieldAffinityStruct.empty() && res.rows.empty() && res.structsTotal == 0 )
    {
        std::fprintf( stderr, "ripwire: --field-affinity: no indexed C-family struct/class named '%.*s'%s with any attributed "
                              "field access (this verb models C/C++/ObjC only; try --layout=%.*s for its declared layout)\n",
                      int( cfg.fieldAffinityStruct.size() ), cfg.fieldAffinityStruct.data(),
                      rw::nearestAggregateName( d.ing, cfg.fieldAffinityStruct ).c_str(),
                      int( cfg.fieldAffinityStruct.size() ), cfg.fieldAffinityStruct.data() );
        return 1;
    }

    fieldaffinity::writeFieldAffinity( stdout, res, faRootPrefix, faRootAttr );
    return 0;
}

// §A8.6: "how many communities count as a real module" — size>=2, i.e. NOT an isolated singleton. Shared by
// emitCommunitiesReport (below) and emitCommunityDrill's `modules=`, so the two verbs' modules= counts use
// the identical predicate and cannot drift into two different numbers under one attribute name.
std::uint32_t nonIsolatedModuleCount( const CommunityMembers& members )
{
    std::uint32_t modules = 0;
    for( const rw::SmallVec<rw::NodeId, 2>& mem : members )
    {
        if( mem.size() >= 2 )
        {
            ++modules;
        }
    }
    return modules;
}

// --communities: cluster the call graph into cohesive modules (Louvain) + cross-module bridge edges.
// Its own function (the named-verb-handler shape): §P8 added a
// real windowing step to the module row list, and the emitter was already the whole of runCommunities.
int emitCommunitiesReport( const rw::Config& cfg, const rw::IngestResult& ing, const rw::Graph& g )
{
    using namespace rw;
    // R-E (2026-08-17 harvest): same single-root condition every other verb's root= uses (sarif.h).
    const bool         cmSingleRoot = ing.realPaths.empty() && cfg.roots.size() == 1;
    const std::string  cmRootPrefix = cmSingleRoot ? rw::sarif::rootPrefixOf( cfg.roots[0] ) : std::string();
    std::vector<char>  cmRootEsc;
    const std::string  cmRootAttr   = cmSingleRoot ? ( " root=\"" + std::string( escapeXml( cfg.roots[0], cmRootEsc ) ) + "\"" ) : std::string();

    const rw::Communities   cm   = rw::communities( g );
    const auto [ rank, prIters, prConverged ] = rankGraph( g );
    const rw::RankDisclosure prD{ prIters, prConverged, true };   // W2-F: this document is PageRank-ordered
    const std::uint32_t      K    = cm.count;
    const std::uint32_t      N    = std::uint32_t( ing.symbols.size() );

    CommunityMembers members( K );
    for( NodeId i = 0; i < N; ++i )
    {
        members[cm.comm[i]].push_back( i );
    }
    const CommunityPresentation presentation = communityPresentation( ing, g, members, rank, cmRootPrefix );

    HashMap<std::uint64_t, std::uint32_t> bridge;   // (min,max) community pair → inter-module edge count
    for( NodeId u = 0; u < N; ++u )
    {
        for( std::uint32_t k = g.outOff[u]; k < g.outOff[u + 1]; ++k )
        {
            const std::uint32_t cu = cm.comm[u], cv = cm.comm[ g.outTargets[k] ];
            if( cu == cv )
            {
                continue;
            }
            const std::uint32_t a = std::min( cu, cv ), b = std::max( cu, cv );
            ++bridge[ ( std::uint64_t( a ) << 32 ) | b ];
        }
    }

    // V6: rank mass (sum of PageRank over a community's members) is the primary ordering key — see
    // communityRankMass's comment for why raw size alone under-ranks small load-bearing hubs.
    std::vector<float> mass( K );
    for( std::uint32_t c = 0; c < K; ++c )
    {
        mass[c] = communityRankMass( members[c], rank );
    }
    std::vector<std::uint32_t> order( K );
    for( std::uint32_t c = 0; c < K; ++c )
    {
        order[c] = c;
    }
    std::sort( order.begin(), order.end(), [ & ]( std::uint32_t a, std::uint32_t b ) { return massSizeIdLess( a, b, mass, members ); } );

    const std::uint32_t modules  = nonIsolatedModuleCount( members );
    const IsolateStats  isolates = isolateStats( ing, g, members );

    // §P8: --limit/--offset were accepted and ignored — the listing always emitted the same 30 largest
    // modules. The row list is `order` filtered to real modules (size>=2), already deterministic
    // (V6: rank-mass desc, then size desc, then community id), so materialize it once and window it.
    // --limit raises or lowers the historic 30 cap; the bridge listing keeps its own 12 cap (it is a
    // second, independent report, not a continuation of the module rows), which is why shown_bridges=
    // keeps its own count.
    std::vector<std::uint32_t> moduleOrder;
    moduleOrder.reserve( modules );
    for( std::uint32_t c : order )
    {
        if( members[c].size() >= 2 )
        {
            moduleOrder.push_back( c );
        }
    }
    const PageWindow  cmpw = pageWindow( moduleOrder.size(), effectiveRowCap( cfg.pageLimit, 30 ), cfg.pageOffset );
    char              cmab[ 192 ];

    // §P8 vocabulary — src/pageview.h, THE TRUNCATION VOCABULARY, rules 1+3+6. TWO independent listings, so
    // the noun-prefixed shown_<noun>= form stays (a bare shown= cannot serve both) and each gains the
    // <noun>_capped="0|1" bit it lacked: shown_modules="30" beside modules="207" left the subtraction to
    // the caller. Only the module listing is --limit-windowed, so only it takes the paging half.
    //
    // §P8/N4: and ONLY the paging half — pagingDisclosure, not pageDisclosure. The full helper also emitted
    // a bare shown=/capped= for that same module listing, so a paged <communities> carried shown_modules="3"
    // AND shown="3" (always equal, by construction — both are cmpw's width). Two names for one fact is the
    // vocabulary drift §P8 exists to remove, and here it was worse than drift: a parser that summed the two
    // listings would double-count the modules. The noun-prefixed pair is the one rule 1 requires when
    // several listings coexist, so it is the one that survives.
    const std::uint32_t shownModules     = std::uint32_t( cmpw.end - cmpw.begin );
    const std::size_t   shownBridges     = std::min<std::size_t>( bridge.size(), 12 );
    const unsigned      isModulesCapped  = unsigned( shownModules < moduleOrder.size() );
    const unsigned      isBridgesCapped  = unsigned( shownBridges < bridge.size() );
    // §B8.1 (CA4): each <community> row printed size= beside a member listing silently cut at 5, with no
    // shown=/capped= companion — pageview.h rules 2+3, on the one listing in this report that lacked them
    // (the root's two listings have carried shown_<noun>=/<noun>_capped= since §P8). The drill verb on the
    // SAME module id emits shown=/capped= for the identical listing, so the two views of one module
    // disagreed about whether a cut had happened. Per rule 2, size= IS this element's total, so the pair is
    // the bare shown=/capped= form the drill verb uses, not a noun-prefixed one.
    std::printf( "<!-- ripwire communities: cohesive call-graph modules (Louvain); bridge=cross-module edges; isolated=call-graph-edgeless symbols; "
                 "drill= names the verb that takes an id= from a row below. On each module row size= is its TRUE member count while "
                 "shown=/capped= describe the member list printed here: this listing is fixed at the 5 top-ranked members and is NOT "
                 "widened by limit=/offset= (those page the MODULE rows). capped=1 means members were dropped; drill= names the verb "
                 "that pages the full member list of one module. raise the default cap with limit=N (offset=M pages; a cut listing carries total=/has_more=/next_offset= so a paging loop can continue from it). "
                 "%s%s-->%s", rw::kGraphCountFloorBriefLegend, rw::renderDisclosure( prD, rw::DiscloseAs::LegendClause ).c_str(), rw::rootRelPathsLegend( cmSingleRoot ) );
    // §P11.6 drill=: the id= values below were the only identifiers this tool emitted that no verb took
    // back. The follow-up verb is named ON THE ROOT ELEMENT rather than in the doc comment, because an XML
    // comment may not contain a double hyphen (G4) and its entity escapes are NOT expanded — a caller would
    // read a literal "&#45;&#45;". As an attribute value the flag is exact, parseable and pasteable.
    std::printf( "<communities drill=\"--community=ID\" modules=\"%u\" shown_modules=\"%u\" modules_capped=\"%u\" bridges=\"%zu\" shown_bridges=\"%zu\" bridges_capped=\"%u\" isolated=\"%u\" isolated_decl=\"%u\" isolated_header=\"%u\" isolated_source=\"%u\" isolated_doc=\"%u\" connected_singletons=\"%u\" symbols=\"%u\"%s%s%s>",
                 modules, shownModules, isModulesCapped,
                 bridge.size(), shownBridges, isBridgesCapped, isolates.total, isolates.declaration,
                 isolates.header, isolates.source, isolates.document, isolates.connectedSingletons, N,
                 ( pagingDisclosure( cmab, sizeof( cmab ), moduleOrder.size(), cmpw.end, cfg.pageLimit, cfg.pageOffset )
                   + rw::renderDisclosure( prD, rw::DiscloseAs::XmlAttrs ) ).c_str(),
                 cmRootAttr.c_str(),
                 rw::graphCountFloorAttrXml( g ).c_str() );   // H5/M15: gauge + marker; modules=/bridges=/isolated= partition the name-based CSR
    std::vector<char> esc;
    const auto        ex = [ & ]( std::string_view s ) -> std::string { return std::string( escapeXml( s, esc ) ); };
    for( std::size_t moduleIndex = cmpw.begin; moduleIndex < cmpw.end; ++moduleIndex )
    {
        const std::uint32_t      c   = moduleOrder[ moduleIndex ];
        rw::SmallVec<NodeId, 2>& mem = members[c];
        std::sort( mem.begin(), mem.end(), [ & ]( NodeId a, NodeId b ) { return rank[a] != rank[b] ? rank[a] > rank[b] : a < b; } );
        const std::size_t topN = std::min<std::size_t>( 5, mem.size() );
        std::printf( "<community id=\"%u\" size=\"%zu\" dir=\"%s\" label=\"%s\" shown=\"%zu\" capped=\"%u\">", c, std::size_t( mem.size() ),
                     ex( presentation.directory[c] ).c_str(), ex( presentation.label[c] ).c_str(),
                     topN, unsigned( topN < mem.size() ) );   // §B8.1: rules 2+3 — size= is the total, this pair is the cut
        for( std::size_t i = 0; i < topN; ++i )
        {
            const Symbol&           s  = ing.symbols[ mem[i] ];
            const std::string_view  rp = cmSingleRoot ? rw::sarif::rootRelativeUri( ing.files[ s.fileId ], cmRootPrefix ) : std::string_view( ing.files[ s.fileId ] );
            std::printf( "<member t=\"%s\" n=\"%s\" p=\"%s:%u\"/>", symTag( s.kind ), ex( s.name ).c_str(), ex( rp ).c_str(), s.line );
        }
        std::printf( "</community>" );
    }
    std::vector<std::pair<std::uint64_t, std::uint32_t>> br( bridge.begin(), bridge.end() );
    std::sort( br.begin(), br.end(), []( const auto& a, const auto& b ) { return a.second != b.second ? a.second > b.second : a.first < b.first; } );
    const std::size_t topB = shownBridges;
    for( std::size_t i = 0; i < topB; ++i )
    {
        const std::uint32_t a = std::uint32_t( br[i].first >> 32 );
        const std::uint32_t b = std::uint32_t( br[i].first & 0xffffffffu );
        std::printf( "<bridge a=\"%u\" b=\"%u\" from_label=\"%s\" to_label=\"%s\" edges=\"%u\"/>", a, b,
                     ex( presentation.label[a] ).c_str(), ex( presentation.label[b] ).c_str(), br[i].second );
    }
    std::printf( "</communities>" );
    return 0;
}

std::optional<int> runCommunities( const MainDispatch& d )
{
    if( d.cfg.communities )
    {
        return emitCommunitiesReport( d.cfg, d.ing, d.g ); // body: emitCommunitiesReport() above
    }
    return std::nullopt;
}

// --community=ID (§P11.6): drill into ONE module. --communities and --zoom PRINT module ids and no verb
// ACCEPTED one — a 274-member module showed five members and the chain ended there. Those ids were the
// only identifiers the tool emitted that nothing took back, which is §P8's selector-chain gap at module
// granularity, on the two verbs whose entire output is module ids.
//
// The id space is the FULL Louvain partition (0..count-1), not the size>=2 subset --communities LISTS: an
// id is a fact about the partition, and refusing a legal-but-unlisted singleton would mean the drill-down
// disagreed with the clustering it drills into. A singleton simply reports size="1".
int emitCommunityDrill( const rw::Config& cfg, const rw::IngestResult& ing, const rw::Graph& g )
{
    using namespace rw;
    // R-E (2026-08-17 harvest): same single-root condition every other verb's root= uses (sarif.h).
    const bool         cdSingleRoot = ing.realPaths.empty() && cfg.roots.size() == 1;
    const std::string  cdRootPrefix = cdSingleRoot ? rw::sarif::rootPrefixOf( cfg.roots[0] ) : std::string();
    std::vector<char>  cdRootEsc;
    const std::string  cdRootAttr   = cdSingleRoot ? ( " root=\"" + std::string( escapeXml( cfg.roots[0], cdRootEsc ) ) + "\"" ) : std::string();

    const Communities   cm = communities( g );
    const std::uint32_t K  = cm.count;
    const std::uint32_t N  = std::uint32_t( ing.symbols.size() );

    // The id is a number or it is a typo — a non-numeric value must never be read as module 0. §P0: an id
    // outside the partition is a mistake, not an empty module, so the refusal names the legal range AND
    // the nearest legal id (the caller is holding a number and needs to know which numbers exist).
    std::uint64_t parsed  = 0;
    bool          numeric = !cfg.communityId.empty();
    for( char ch : cfg.communityId )
    {
        if( ch < '0' || ch > '9' ) { numeric = false; break; }
        parsed = std::min<std::uint64_t>( parsed * 10 + std::uint64_t( ch - '0' ), 0xffffffffull );
    }
    if( !numeric || parsed >= K )
    {
        if( K == 0 )
        { std::fprintf( stderr, "ripwire: --community: this corpus has no call-graph modules to drill into\n" );  return 1; }
        std::fprintf( stderr, "ripwire: --community: '%.*s' is not a module id — valid ids are 0..%u (the id= values --communities "
                              "and --zoom print); nearest valid id: %u\n",
                      int( cfg.communityId.size() ), cfg.communityId.data(), K - 1,
                      numeric ? K - 1 : 0u );
        return 1;
    }
    const std::uint32_t want = std::uint32_t( parsed );

    CommunityMembers members( K );
    for( NodeId i = 0; i < N; ++i )
    {
        members[cm.comm[i]].push_back( i );
    }

    // §A8.6: this root used to print the FULL partition size (K, isolated singletons included) under the
    // SAME attribute name (`modules=`) the parent uses for the non-isolated count — 9x apart on this repo.
    // `partition=` (below) now carries the full label space; `modules=` uses nonIsolatedModuleCount(), the
    // PARENT's exact predicate, so the two agree.
    const std::uint32_t modulesNonIsolated = nonIsolatedModuleCount( members );

    // dir=/label= come from the SAME communityPresentation the parent uses, so the two rows for one id
    // cannot drift into two derivations of "what is this module called".
    const auto [ rank, prIters, prConverged ] = rankGraph( g );
    const rw::RankDisclosure prD{ prIters, prConverged, true };   // W2-F: this document is PageRank-ordered
    const CommunityPresentation presentation = communityPresentation( ing, g, members, rank, cdRootPrefix );

    rw::SmallVec<NodeId, 2>& mem = members[ want ];
    std::sort( mem.begin(), mem.end(), [ & ]( NodeId a, NodeId b ) { return rank[a] != rank[b] ? rank[a] > rank[b] : a < b; } );

    // bridges: this module's cross-module edges only, counted per PEER module (both directions summed —
    // the parent's <bridge> is undirected too, so "how coupled are these two" means the same thing here).
    HashMap<std::uint32_t, std::uint32_t> peerEdges;
    for( NodeId u = 0; u < N; ++u )
    {
        for( std::uint32_t k = g.outOff[u]; k < g.outOff[u + 1]; ++k )
        {
            const std::uint32_t cu = cm.comm[u], cv = cm.comm[ g.outTargets[k] ];
            if( cu == cv )
            {
                continue;
            }
            if( cu == want )
            {
                ++peerEdges[cv];
            }
            else if( cv == want )
            {
                ++peerEdges[cu];
            }
        }
    }
    std::vector<std::pair<std::uint32_t, std::uint32_t>> peers( peerEdges.begin(), peerEdges.end() );
    std::sort( peers.begin(), peers.end(), []( const auto& a, const auto& b )
               { return a.second != b.second ? a.second > b.second : a.first < b.first; } );

    // §P8 / src/pageview.h: the MEMBER listing is the primary windowed one (rule 6) — this is the verb that
    // exists because five preview rows were not enough, so its cap must be raisable. The bridge listing is
    // independent and discloses through its own noun-prefixed pair.
    const PageWindow  mpw          = pageWindow( mem.size(), effectiveRowCap( cfg.pageLimit, 40 ), cfg.pageOffset );
    const std::size_t shownMembers = mpw.end - mpw.begin;
    const std::size_t shownBridges = std::min<std::size_t>( peers.size(), 12 );
    char              mpab[ kPageDisclosureCap ];
    std::vector<char> esc;
    const auto        ex = [ & ]( std::string_view s ) -> std::string { return std::string( escapeXml( s, esc ) ); };

    std::printf( "<!-- ripwire community: ONE module from the communities/zoom partition — its ranked members and its bridge edges to "
                 "other modules. size= is the module's TRUE member count; shown=/capped= are this page. partition= is the FULL label "
                 "space (every id 0..partition-1, incl. isolated singletons) — the range the id= argument ranges over; modules= counts "
                 "the NON-isolated communities (size>=2), the SAME predicate the communities-listing verb's modules= uses, so parent "
                 "and child agree. %s%s-->%s", rw::kGraphCountFloorBriefLegend, rw::renderDisclosure( prD, rw::DiscloseAs::LegendClause ).c_str(), rw::rootRelPathsLegend( cdSingleRoot ) );
    std::printf( "<community id=\"%u\" size=\"%zu\" dir=\"%s\" label=\"%s\" bridges=\"%zu\" shown_bridges=\"%zu\" bridges_capped=\"%u\" partition=\"%u\" modules=\"%u\"%s%s%s>",
                 want, std::size_t( mem.size() ), ex( presentation.directory[ want ] ).c_str(), ex( presentation.label[ want ] ).c_str(),
                 peers.size(), shownBridges, unsigned( shownBridges < peers.size() ), K, modulesNonIsolated,
                 ( pageDisclosure( mpab, sizeof( mpab ), shownMembers, mem.size(), mpw.end, cfg.pageLimit, cfg.pageOffset, true )
                   + rw::renderDisclosure( prD, rw::DiscloseAs::XmlAttrs ) ).c_str(),
                 cdRootAttr.c_str(),
                 rw::graphCountFloorAttrXml( g ).c_str() );   // H5/M15: gauge + marker; size=/bridges= are a partition of the name-based CSR
    for( std::size_t i = mpw.begin; i < mpw.end; ++i )
    {
        const Symbol&           s  = ing.symbols[ mem[i] ];
        const std::string_view  rp = cdSingleRoot ? rw::sarif::rootRelativeUri( ing.files[ s.fileId ], cdRootPrefix ) : std::string_view( ing.files[ s.fileId ] );
        std::printf( "<member t=\"%s\" n=\"%s\" p=\"%s:%u\"/>", symTag( s.kind ), ex( s.name ).c_str(), ex( rp ).c_str(), s.line );
    }
    for( std::size_t i = 0; i < shownBridges; ++i )
    {
        std::printf( "<bridge to=\"%u\" to_label=\"%s\" edges=\"%u\"/>", peers[i].first, ex( presentation.label[ peers[i].first ] ).c_str(), peers[i].second );
    }
    std::printf( "</community>" );
    return 0;
}

std::optional<int> runCommunityDrill( const MainDispatch& d )
{
    if( !d.cfg.communityFlag )
    {
        return std::nullopt;
    }
    if( d.cfg.communityId.empty() )
    {
        std::fprintf( stderr, "ripwire: --community needs a module ID — take one from the id= values --communities "
                              "or --zoom print, e.g. --community=12\n" );
        return 1;
    }
    return emitCommunityDrill( d.cfg, d.ing, d.g );
}

std::optional<int> runZoom( const MainDispatch& d )
{
    using namespace rw;
    const Config&                     cfg          = d.cfg;
    const IngestResult&               ing          = d.ing;
    const Graph&                      g            = d.g;

    // --zoom[=depth]: the NESTED module hierarchy (multi-level Louvain) — contract each community into a
    // super-node and re-run Louvain, repeatedly, until the top has ≤10 modules (or `=depth` levels). Output is
    // an INDENTED tree (top module → child modules → … → the finest community's top-ranked symbols); each node
    // is labelled by its dominant directory + symbol count. Cross-module BRIDGES at the top level are always
    // shown, ranked by traffic. `--zoom --mermaid` emits the same hierarchy as a nested-subgraph diagram.
    // Deterministic: multiLevelCommunities is byte-stable (id-order local-moving at every level); the renderer
    // visits children/symbols in a fixed (V6: rank-mass desc, size desc, id asc / rank desc, id asc) order.
    if( cfg.zoom )
    {
        const std::uint32_t N = std::uint32_t( ing.symbols.size() );
        // depth: --zoom=D caps at D levels (≥1). default (0) = auto: contract until ≤10 top modules.
        const std::uint32_t maxLevels = cfg.zoomDepth > 0 ? std::uint32_t( cfg.zoomDepth ) : 8u;
        const std::uint32_t maxTop    = cfg.zoomDepth > 0 ? 1u : 10u;   // explicit depth ⇒ contract as far as the cap allows
        const rw::ZoomHierarchy h    = rw::multiLevelCommunities( g, maxTop, maxLevels );
        const auto [ rank, prIters, prConverged ] = rankGraph( g );
        const rw::RankDisclosure prD{ prIters, prConverged, true };   // W2-F: this document is PageRank-ordered

        const std::size_t        L    = h.levels.size();                // ≥1 always (level 0 present)

        // per-level, per-group: member symbol ids (for size, dominant dir, and leaf top-symbols). members[l][gid].
        std::vector<CommunityMembers> members( L );
        for( std::size_t l = 0; l < L; ++l )
        {
            members[l].assign( h.counts[l], {} );
            for( NodeId i = 0; i < N; ++i )
            {
                members[l][h.levels[l][i]].push_back( i );
            }
        }

        // V6: per-level rank mass — see communityRankMass's comment (--communities uses the identical key)
        // and perLevelRankMass's comment (why this is precomputed once rather than per comparator call).
        const std::vector<std::vector<float>> mass = perLevelRankMass( members, rank );

        // children[l][gid] = the level-(l-1) groups whose parent is gid (l≥1). Inverts h.parentOf[l-1].
        std::vector<std::vector<std::vector<std::uint32_t>>> children( L );
        for( std::size_t l = 1; l < L; ++l )
        {
            children[l].assign( h.counts[l], {} );
            const std::vector<std::uint32_t>& par = h.parentOf[l - 1];   // level (l-1) group → level l group
            for( std::uint32_t cg = 0; cg < h.counts[l - 1]; ++cg )
            {
                children[l][par[cg]].push_back( cg );
            }
        }

        // dominant directory of a level-l group (most-frequent parent dir of its member files; ties → lexicographically first).
        const auto domDirOf = [ & ]( std::size_t l, std::uint32_t gid ) -> std::string
        {
            rw::HashMap<std::string, std::uint32_t> dirCount;
            for( NodeId n : members[l][gid] )
            {
                std::string_view  p  = ing.files[ ing.symbols[n].fileId ];
                const std::size_t sl = p.rfind( '/' );
                ++dirCount[ std::string( sl == std::string_view::npos ? p : p.substr( 0, sl ) ) ];
            }
            std::string d;  std::uint32_t best = 0;
            for( const auto& [dir, cnt] : dirCount )
            {
                if( cnt > best || ( cnt == best && dir < d ) )
                {
                    best = cnt;
                    d = dir;
                }
            }
            return d;
        };

        // top-level modules (groups with ≥2 symbols), highest rank-mass first, size- then id-tiebroken — the
        // same "a lone symbol is not a module" rule as --communities, and (V6) the same ordering key.
        const std::size_t        topL = L - 1;
        std::vector<std::uint32_t> topOrder;
        for( std::uint32_t gid = 0; gid < h.counts[topL]; ++gid )
        {
            if( members[topL][gid].size() >= 2 )
            {
                topOrder.push_back( gid );
            }
        }
        std::sort( topOrder.begin(), topOrder.end(),
                  [ & ]( std::uint32_t a, std::uint32_t b ) { return massSizeIdLess( a, b, mass[topL], members[topL] ); } );

        // top-level cross-module bridges (between the FINEST communities, summed onto top-module pairs), ranked.
        // We count finest-community→finest-community call edges, then lift each endpoint to its top-level module.
        const std::vector<std::uint32_t>& topOf = h.levels[topL];        // symbol → top module
        rw::HashMap<std::uint64_t, std::uint32_t> bridge;               // (min,max) top-module pair → edge count
        for( NodeId u = 0; u < N; ++u )
        {
            for( std::uint32_t k = g.outOff[u]; k < g.outOff[u + 1]; ++k )
            {
                const std::uint32_t tu = topOf[u], tv = topOf[ g.outTargets[k] ];
                if( tu == tv )
                {
                    continue;
                }
                const std::uint32_t a = std::min( tu, tv ), b = std::max( tu, tv );
                ++bridge[ ( std::uint64_t( a ) << 32 ) | b ];
            }
        }

        if( cfg.mermaid )
        {
            // nested-subgraph diagram: one subgraph per top module; its child modules (next-finer level) are
            // nodes inside; bridge edges connect top modules. Deterministic node ids = "L<level>_<gid>".
            // W2-F: mermaid has no attribute grammar — the note is emitted ONLY on the truncating exit, as a
            // mermaid COMMENT so the diagram still renders with the warning attached.
            std::printf( "%s", rw::renderDisclosure( prD, rw::DiscloseAs::MermaidNote ).c_str() );
            std::printf( "%%%% ripwire --zoom --mermaid: nested module hierarchy (multi-level Louvain). subgraph = top module, inner node = sub-module (dir, symbol count); edge = cross-module call count. Render at mermaid.live.\n" );
            std::printf( "flowchart TB\n" );
            std::vector<char> esc;
            const auto ex = [ & ]( std::string_view s ) -> std::string { std::string r( s ); for( char& ch : r ) { if( ch == '"' ) { ch = '\''; } } return r; };
            const std::size_t maxTopShown = std::min<std::size_t>( 10, topOrder.size() );
            for( std::size_t ti = 0; ti < maxTopShown; ++ti )
            {
                const std::uint32_t t = topOrder[ti];
                std::printf( "  subgraph sgL%zu_%u [\"%s<br/>%zu\"]\n", topL, t, ex( domDirOf( topL, t ) ).c_str(), std::size_t( members[topL][t].size() ) );
                if( topL >= 1 )
                {
                    std::vector<std::uint32_t> kids = children[topL][t];
                    std::sort( kids.begin(), kids.end(),
                              [ & ]( std::uint32_t a, std::uint32_t b ) { return massSizeIdLess( a, b, mass[topL - 1], members[topL - 1] ); } );
                    const std::size_t maxKids = std::min<std::size_t>( 8, kids.size() );
                    for( std::size_t ki = 0; ki < maxKids; ++ki )
                    {
                        std::printf( "    nL%zu_%u[\"%s<br/>%zu\"]\n", topL - 1, kids[ki], ex( domDirOf( topL - 1, kids[ki] ) ).c_str(), std::size_t( members[topL - 1][ kids[ki] ].size() ) );
                    }
                }
                else   // single-level (no coarsening happened): show the module's top symbols as inner nodes
                {
                    rw::SmallVec<NodeId, 2> mem = members[topL][t];
                    std::sort( mem.begin(), mem.end(), [ & ]( NodeId a, NodeId b ) { return rank[a] != rank[b] ? rank[a] > rank[b] : a < b; } );
                    const std::size_t maxS = std::min<std::size_t>( 5, mem.size() );
                    for( std::size_t si = 0; si < maxS; ++si )
                    {
                        std::printf( "    sL%zu_%u_%zu[\"%s\"]\n", topL, t, si, ex( ing.symbols[ mem[si] ].name ).c_str() );
                    }
                }
                std::printf( "  end\n" );
            }
            std::vector<char> shownTop( h.counts[topL], 0 );
            for( std::size_t ti = 0; ti < maxTopShown; ++ti )
            {
                shownTop[topOrder[ti]] = 1;
            }
            std::vector<std::pair<std::uint64_t, std::uint32_t>> br( bridge.begin(), bridge.end() );
            std::sort( br.begin(), br.end(), []( const auto& a, const auto& b ) { return a.second != b.second ? a.second > b.second : a.first < b.first; } );
            for( const auto& [ key, w ] : br )
            {
                const std::uint32_t a = std::uint32_t( key >> 32 ), b = std::uint32_t( key & 0xffffffffu );
                if( !shownTop[a] || !shownTop[b] )
                {
                    continue;
                }
                std::printf( "  sgL%zu_%u -->|%u| sgL%zu_%u\n", topL, a, w, topL, b );
            }
            return 0;
        }

        // INDENTED text tree. recurse top → finer levels; at level 0 (finest community) list the top symbols.
        std::vector<char> esc;
        const auto        ex = [ & ]( std::string_view s ) -> std::string { return std::string( escapeXml( s, esc ) ); };
        // §B12.1 + §B8.1 (CA4). Two arithmetic silences on one screen, and neither is closeable from this
        // document: (1) symbols= counts the WHOLE corpus while the hierarchy holds only symbols that landed
        // in a top-level module of 2 or more — the difference (call-graph singletons) is the number the
        // sibling verb publishes as isolated= and this one published nowhere, so a reader summing the size=
        // values came up short with no clause to explain it; (2) each level-0 module printed size= beside a
        // member list silently cut at 5, with no shown=/capped= (pageview.h rules 2+3). isolated= here is
        // derived from THIS verb's own hierarchy (symbols minus the members of every top-level module,
        // shown or not), so the identity below is exact by construction rather than by agreeing with
        // another verb's independently-computed number.
        std::size_t inHierarchy = 0;
        for( std::uint32_t gid : topOrder )
        {
            inHierarchy += members[topL][gid].size();
        }
        const std::uint32_t isolatedCount = N - std::uint32_t( inHierarchy );
        std::printf( "<!-- ripwire zoom: NESTED module hierarchy (multi-level Louvain); indent = one level deeper; module = dominant-dir(symbol-count); leaf lists top-ranked symbols; bridge = cross-top-module call traffic. "
                     "symbols= is the whole corpus; isolated= is the symbols in NO top-level module (a group of one — the same rule that makes top_modules= count only groups of 2 or more), and they reconcile exactly: "
                     "symbols= equals isolated= plus the sum of the TOP-LEVEL size= values, every one of them, including any this page did not print. "
                     "On a level-0 module size= is its true member count and shown=/capped= describe the member list printed here, which is fixed at the 5 top-ranked members and is not widened by limit=/offset= (those page the TOP-LEVEL modules); "
                     "the community drill verb pages one module's full member list by its level-0 id. A module above level 0 lists every child module, so it carries no shown=/capped= pair. "
                     // P4 (L7): the two default ceilings, defined where the reader meets them
                     "levels_shown= is how many of the levels= this document prints from the top (default 2; the zoom-levels flag sets it, 0 = all): a module AT the cut "
                     "carries children= (its child modules, none printed) instead of nesting. The top-level module rows are a WINDOW (shown=/capped=/total=/next_offset=, "
                     "default 40 largest; limit=/offset= page it) and next= pastes the next page. %s%s-->",
                     rw::kGraphCountFloorBriefLegend, rw::renderDisclosure( prD, rw::DiscloseAs::LegendClause ).c_str() );
        // §P15/§P16: top_modules= is a real, deterministically-ordered row list (size desc, id asc — the same
        // rule --communities' module listing uses) that used to print EVERY top module unconditionally, so a
        // repo with hundreds of top modules had no way to page it. --limit/--offset now window it like --uses
        // (no historic display cap, discloseCap=false ⇒ the un-paginated tag is byte-identical). --mermaid is
        // a fixed-shape diagram, not a row list (its own hard-coded top-10/top-8/top-5 caps are unaffected —
        // honorsPaging() excludes the --zoom --mermaid combination for the same reason plain --mermaid refuses).
        // P4 (L7): the default window over the top modules (kZoomTopModuleCap; --limit raises it) and the printed
        // depth (levels_shown=, default 2; --zoom-levels=N sets it, 0 = every level). Both cuts are disclosed on the
        // root and next= pastes the next page; a module AT the depth cut carries children= instead of nesting.
        const PageWindow  zoomPw = pageWindow( topOrder.size(), effectiveRowCap( cfg.pageLimit, kZoomTopModuleCap ), cfg.pageOffset );
        const std::size_t levelsShown = cfg.zoomLevelsSet ? ( cfg.zoomLevels > 0 ? std::min<std::size_t>( L, std::size_t( cfg.zoomLevels ) ) : L )
                                                          : std::min<std::size_t>( L, 2 );
        const std::size_t cutLevel    = topL + 1 - levelsShown;   // the deepest level printed; its rows carry children= when l > 0
        const bool        zoomCut     = zoomPw.end - zoomPw.begin < topOrder.size();
        const std::string zoomNext    = zoomCut ? rw::nextAttrXml( "--zoom --offset=" + std::to_string( zoomPw.end ) ) : std::string();
        char              zoomAb[ kPageDisclosureCap ];
        std::printf( "<zoom levels=\"%zu\" levels_shown=\"%zu\" top_modules=\"%zu\" symbols=\"%u\" isolated=\"%u\"%s%s%s>", L, levelsShown, topOrder.size(), N, isolatedCount,
                     ( pageDisclosure( zoomAb, sizeof( zoomAb ), zoomPw.end - zoomPw.begin, topOrder.size(), zoomPw.end,
                                       cfg.pageLimit, cfg.pageOffset, zoomCut )
                       + rw::renderDisclosure( prD, rw::DiscloseAs::XmlAttrs ) ).c_str(),
                     rw::graphCountFloorAttrXml( g ).c_str(),   // H5/M15: gauge + marker; isolated=/top_modules= partition the name-based CSR
                     zoomNext.c_str() );

        // a stack-free recursion via an explicit lambda (std::function — not hot). Emits <module> elements
        // nested by level; the finest level emits <member> leaves.
        std::function<void( std::size_t, std::uint32_t )> emit = [ & ]( std::size_t l, std::uint32_t gid )
        {
            // §B8.1: the shown=/capped= pair belongs ONLY to the level-0 rows — they are the ones whose
            // listing is cut. A level>0 row emits every child module, so per rule 3 ("if a verb emits no
            // shown=, it emits no capped= either") it stays a bare size= row, and the legend says which is
            // which rather than leaving a reader to infer it from an absent attribute.
            const std::size_t leafShown = ( l == 0 ) ? std::min<std::size_t>( 5, members[0][gid].size() ) : 0;
            const bool        atCut     = l > 0 && l == cutLevel;   // P4: printed, but its children are not
            std::printf( "<module level=\"%zu\" id=\"%u\" size=\"%zu\" dir=\"%s\"", l, gid, std::size_t( members[l][gid].size() ), ex( domDirOf( l, gid ) ).c_str() );
            if( l == 0 )
            {
                std::printf( " shown=\"%zu\" capped=\"%u\"", leafShown, unsigned( leafShown < members[0][gid].size() ) );
            }
            if( atCut )
            {
                std::printf( " children=\"%zu\"", std::size_t( children[l][gid].size() ) );
            }
            std::printf( ">" );
            if( atCut )
            {
                // the depth ceiling: nothing below this row is printed (levels_shown= on the root says so)
            }
            else if( l == 0 )   // finest community → list its top-ranked symbols
            {
                rw::SmallVec<NodeId, 2> mem = members[0][gid];
                std::sort( mem.begin(), mem.end(), [ & ]( NodeId a, NodeId b ) { return rank[a] != rank[b] ? rank[a] > rank[b] : a < b; } );
                const std::size_t topN = leafShown;
                for( std::size_t i = 0; i < topN; ++i )
                {
                    const Symbol& s = ing.symbols[ mem[i] ];
                    std::printf( "<member t=\"%s\" n=\"%s\" p=\"%s:%u\"/>", symTag( s.kind ), ex( s.name ).c_str(), ex( ing.files[ s.fileId ] ).c_str(), s.line );
                }
            }
            else           // recurse into child modules (next-finer level), highest rank-mass first (V6)
            {
                std::vector<std::uint32_t> kids = children[l][gid];
                std::sort( kids.begin(), kids.end(),
                          [ & ]( std::uint32_t a, std::uint32_t b ) { return massSizeIdLess( a, b, mass[l - 1], members[l - 1] ); } );
                for( std::uint32_t cg : kids )
                {
                    emit( l - 1, cg );
                }
            }
            std::printf( "</module>" );
        };
        for( std::size_t ti = zoomPw.begin; ti < zoomPw.end; ++ti )
        {
            emit( topL, topOrder[ti] );
        }

        std::vector<std::pair<std::uint64_t, std::uint32_t>> br( bridge.begin(), bridge.end() );
        std::sort( br.begin(), br.end(), []( const auto& a, const auto& b ) { return a.second != b.second ? a.second > b.second : a.first < b.first; } );
        const std::size_t topB = std::min<std::size_t>( 12, br.size() );
        for( std::size_t i = 0; i < topB; ++i )
        {
            std::printf( "<bridge a=\"%u\" b=\"%u\" edges=\"%u\"/>", std::uint32_t( br[i].first >> 32 ), std::uint32_t( br[i].first & 0xffffffffu ), br[i].second );
        }
        std::printf( "</zoom>" );
        return 0;
    }
    return std::nullopt;
}

// §P11.8 — --tree is the session-start ORIENTATION map, and it emitted files in path order: the one order an
// orientation map must not use. On ripwire's own tree a cold agent's first 40 lines were audit-document
// section titles (long process-doc names, `AGENTS.md` among them — every one of them sorts above `src/`) and the
// code it had landed to read was pages down.
//
// Order files by their BEST symbol's rank instead — the same PageRank the per-file symbol list is already
// ordered by, so the file order and the row order finally agree on what "top" means. Path breaks ties, so the
// result is still a total, deterministic order (a sort has no tolerance band; the det-gate is what proves it,
// exactly as for the per-file symbol sort). One O(N) max-reduce, not a per-file sort: the symbol lists are
// still sorted only for the files the current page actually emits.
inline void orderFilesByBestSymbolRank( std::vector<std::uint32_t>& ford, const rw::IngestResult& ing,
                                        const std::vector<float>& rank )
{
    std::vector<float> bestRankByFile( ing.files.size(), -1.0f );
    for( rw::NodeId i = 0; i < ing.symbols.size(); ++i )
    {
        const std::uint32_t sf = ing.symbols[i].fileId;
        if( rank[i] > bestRankByFile[sf] )
        {
            bestRankByFile[sf] = rank[i];
        }
    }
    rw::orderIdsByKeyDescPathAsc( ford, bestRankByFile, ing.files );
}

std::optional<int> runStructureText( const MainDispatch& d )
{
    using namespace rw;
    const Config&                     cfg          = d.cfg;
    const IngestResult&               ing          = d.ing;
    const Graph&                      g            = d.g;
    const std::string&                root         = d.root;
    // R-E (2026-08-17 harvest): same single-root condition every other verb's root= uses (sarif.h).
    const bool         stSingleRoot = ing.realPaths.empty() && cfg.roots.size() == 1;
    const std::string  stRootPrefix = stSingleRoot ? rw::sarif::rootPrefixOf( cfg.roots[0] ) : std::string();
    std::vector<char>  stRootEsc;
    const std::string  stRootAttr   = stSingleRoot ? ( " root=\"" + std::string( escapeXml( cfg.roots[0], stRootEsc ) ) + "\"" ) : std::string();

    // --seams: cross-module call seams (community bridges) that NO test transitively reaches — the untested
    // inter-module connections. The graph-leveraged slice of testing: an integration test guards a seam
    // between two modules. A FACT (these edges are never exercised from a test), never a mandate to test them.
    if( cfg.seams )
    {
        const auto [ rank, prIters, prConverged ] = rankGraph( g );
        const rw::RankDisclosure prD{ prIters, prConverged, true };   // W2-F: this document is PageRank-ordered
        const std::uint32_t      N    = std::uint32_t( ing.symbols.size() );

        // module = immediate parent DIRECTORY (the real subsystem) — NOT a Louvain community (one-level
        // Louvain is too fine; bridges land within one dir). A seam = a call edge crossing a dir boundary.
        std::vector<std::uint32_t> symDir;
        std::vector<std::string>   dirName;
        computeDirModules( ing, symDir, dirName, stRootPrefix );

        // testReach = everything transitively called from test files → a seam u→v is exercised if testReach[u]
        std::vector<NodeId> testSeeds;
        for( NodeId i = 0; i < N; ++i )
        {
            if( rw::isTestPath( ing.files[ing.symbols[i].fileId] ) )
            {
                testSeeds.push_back( i );
            }
        }
        const std::vector<char> testReach = rw::forwardReach( g, testSeeds );
        std::vector<char> isTestFile( ing.files.size(), 0 );
        for( NodeId s : testSeeds )
        {
            isTestFile[ing.symbols[s].fileId] = 1;
        }
        std::uint32_t testFileCount = 0;
        for( char c : isTestFile )
        {
            testFileCount += c;
        }

        // untested cross-directory edges, grouped by DIRECTED dir pair (caller-module → callee-module)
        struct SeamEdge { NodeId u, v; };
        HashMap<std::uint64_t, std::vector<SeamEdge>> grp;
        std::uint32_t bridges = 0, untested = 0;
        for( NodeId u = 0; u < N; ++u )
        {
            for( std::uint32_t k = g.outOff[u]; k < g.outOff[u + 1]; ++k )
            {
                const NodeId        v  = g.outTargets[k];
                const std::uint32_t du = symDir[u], dv = symDir[ v ];
                if( du == dv )
                {
                    continue; // same directory — not a seam
                }
                ++bridges;
                if( u < testReach.size() && testReach[u] )
                {
                    continue; // a test reaches the caller → exercised
                }
                ++untested;
                grp[ ( std::uint64_t( du ) << 32 ) | dv ].push_back( { u, v } );
            }
        }

        std::vector<std::pair<std::uint64_t, std::vector<SeamEdge>*>> pairs;
        for( auto& kv : grp )
        {
            pairs.push_back( { kv.first, &kv.second } );
        }
        std::sort( pairs.begin(), pairs.end(), [ & ]( const auto& a, const auto& b )
                   { return a.second->size() != b.second->size() ? a.second->size() > b.second->size() : a.first < b.first; } );

        std::vector<char> esc;
        const auto        ex = [ & ]( std::string_view s ) -> std::string { return std::string( escapeXml( s, esc ) ); };
        // §B12.5 — the UNIT clause is the same sentence on all three verbs that spell `untested=` (see
        // situ.h's kTestGateLegend and flipimpact.h's writeFlipHeader). Each legend was locally honest,
        // which is precisely why a reader comparing two of the numbers is misled.
        std::printf( "<!-- ripwire seams: cross-directory call edges NO test reaches (untested integration seams; a fact, not a mandate). module = parent dir; seam = caller-dir -> callee-dir, spelled from= and to=. Each seam pages its own edge rows with shown=/capped=; an edge names caller= at site p= calling callee= at site cp=. UNIT: untested= here counts cross-directory call EDGES. The test gate verb spells untested= over impacted SYMBOLS and the flip verb over the defs a gate lights, so the three numbers count three different things and must never be compared or summed across verbs. raise the default cap with limit=N (offset=M pages; a cut listing carries total=/has_more=/next_offset= so a paging loop can continue from it). %s%s-->%s",
                     rw::kGraphCountFloorBriefLegend, rw::renderDisclosure( prD, rw::DiscloseAs::LegendClause ).c_str(), rw::rootRelPathsLegend( stSingleRoot ) );
        // P2.1: two nested caps, neither previously marked — at most 20 seam PAIRS, and at most 5 example
        // EDGES inside each. Each <seam> gains shown= alongside its true untested= count.
        //
        // §P8 vocabulary (see src/pageview.h, THE TRUNCATION VOCABULARY): this root used to spell BOTH
        // conventions at once — the noun-prefixed shown_seam_pairs= AND the bare capped= — so one element
        // answered "how many rows" in --communities' dialect and "were rows dropped" in --grep's. Reconciled
        // to the bare pair (rule 1): the root has exactly ONE listing (the seam pairs), and the noun-prefixed
        // form exists only to disambiguate SEVERAL listings in one element. modules=/bridges=/untested=/
        // test_files= are corpus counts, not listings, so they need no shown= companion. The <seam> children
        // already carried the target untested=/shown=/capped= and are unchanged.
        //
        // §P15/§P16: the seam-PAIR listing is deterministically sorted (size desc, dir-pair asc) — a real
        // row model, so --limit/--offset now WINDOW it instead of the fixed 20-pair display cap; --limit
        // raises or lowers that historic default exactly like --impact's 40. pageDisclosure replaces the
        // hand-rolled shown=/capped= pair with the identical bytes plus the paging half when active.
        const PageWindow  seamsPw     = pageWindow( pairs.size(), effectiveRowCap( cfg.pageLimit, 20 ), cfg.pageOffset );
        const std::size_t shownPairs  = seamsPw.end - seamsPw.begin;
        char              seamsAb[ kPageDisclosureCap ];
        std::printf( "<seams modules=\"%zu\" bridges=\"%u\" untested=\"%u\" test_files=\"%u\" seam_pairs=\"%zu\"%s%s%s>",
                     dirName.size(), bridges, untested, testFileCount, pairs.size(),
                     ( pageDisclosure( seamsAb, sizeof( seamsAb ), shownPairs, pairs.size(), seamsPw.end,
                                       cfg.pageLimit, cfg.pageOffset, true )
                       + rw::renderDisclosure( prD, rw::DiscloseAs::XmlAttrs ) ).c_str(),
                     stRootAttr.c_str(),
                     rw::graphCountFloorAttrXml( g ).c_str() );   // H5/M15: gauge + marker; bridges=/untested=/seam_pairs= are edges of the name-based CSR
        for( std::size_t pi = seamsPw.begin; pi < seamsPw.end; ++pi )
        {
            const std::uint32_t    cu    = std::uint32_t( pairs[pi].first >> 32 ), cv = std::uint32_t( pairs[pi].first & 0xffffffffu );
            std::vector<SeamEdge>& edges = *pairs[pi].second;
            std::sort( edges.begin(), edges.end(), [ & ]( const SeamEdge& a, const SeamEdge& b )
                       { return rank[a.u] != rank[b.u] ? rank[a.u] > rank[b.u] : a.u < b.u; } );
            const std::size_t topE = std::min<std::size_t>( 5, edges.size() );
            std::printf( "<seam from=\"%s\" to=\"%s\" untested=\"%zu\" shown=\"%zu\" capped=\"%d\">",
                         ex( dirName[cu] ).c_str(), ex( dirName[cv] ).c_str(), edges.size(), topE, topE < edges.size() ? 1 : 0 );
            for( std::size_t i = 0; i < topE; ++i )
            {
                const Symbol&           su  = ing.symbols[ edges[i].u ];
                const Symbol&           sv  = ing.symbols[ edges[i].v ];
                const std::string_view  rpu = stSingleRoot ? rw::sarif::rootRelativeUri( ing.files[su.fileId], stRootPrefix ) : std::string_view( ing.files[su.fileId] );
                const std::string_view  rpv = stSingleRoot ? rw::sarif::rootRelativeUri( ing.files[sv.fileId], stRootPrefix ) : std::string_view( ing.files[sv.fileId] );
                std::printf( "<edge caller=\"%s\" p=\"%s:%u\" callee=\"%s\" cp=\"%s:%u\"/>",
                             ex( su.name ).c_str(), ex( rpu ).c_str(), su.line,
                             ex( sv.name ).c_str(), ex( rpv ).c_str(), sv.line );
            }
            std::printf( "</seam>" );
        }
        std::printf( "</seams>" );
        return 0;
    }

    // --mermaid: the module (directory) dependency graph as a Mermaid diagram — a HUMAN-viewable architecture
    // map. Node = directory (subsystem) sized by symbol count; edge = inter-module call count. Renders at
    // mermaid.live or in any Markdown that supports mermaid (GitHub/Obsidian/VS Code). Deterministic, no LLM.
    if( cfg.mermaid )
    {
        const std::uint32_t N = std::uint32_t( ing.symbols.size() );
        std::vector<std::uint32_t> symDir;
        std::vector<std::string>   dirName;
        computeDirModules( ing, symDir, dirName, stRootPrefix );
        const std::uint32_t M = std::uint32_t( dirName.size() );

        std::vector<std::uint32_t> sz( M, 0 );
        for( NodeId i = 0; i < N; ++i )
        {
            ++sz[symDir[i]];
        }
        HashMap<std::uint64_t, std::uint32_t> w;                       // (du<<32|dv) → cross-module call count
        for( NodeId u = 0; u < N; ++u )
        {
            for( std::uint32_t k = g.outOff[u]; k < g.outOff[u + 1]; ++k )
            {
                const std::uint32_t du = symDir[u], dv = symDir[ g.outTargets[k] ];
                if( du != dv )
                {
                    ++w[( std::uint64_t( du ) << 32 ) | dv];
                }
            }
        }

        std::vector<std::uint32_t> order( M );                         // top modules by symbol count
        for( std::uint32_t c = 0; c < M; ++c )
        {
            order[c] = c;
        }
        std::sort( order.begin(), order.end(), [ & ]( std::uint32_t a, std::uint32_t b )
                   { return sz[a] != sz[b] ? sz[a] > sz[b] : dirName[a] < dirName[b]; } );
        const std::size_t  nShown = std::min<std::size_t>( 30, M );
        std::vector<char>  shown( M, 0 );
        for( std::size_t i = 0; i < nShown; ++i )
        {
            shown[order[i]] = 1;
        }

        const std::string base = root + "/";                          // clean labels: strip the corpus root prefix
        const auto        label = [ & ]( std::uint32_t c ) -> std::string
        {
            std::string s = dirName[c];
            if( s == root )
            {
                s = "(root)";
            }
            else if( s.rfind( base, 0 ) == 0 )
            {
                s = s.substr( base.size() );
            }
            for( char& ch : s )
            {
                if( ch == '"' )
                {
                    ch = '\''; // mermaid label safety
                }
            }
            return s;
        };

        constexpr std::uint32_t minW = 3;                              // hide trivial edges for readability
        std::printf( "%%%% ripwire --mermaid: module (directory) dependency graph — node = dir (symbol count), edge = inter-module calls (>= %u). Render at mermaid.live.\n", minW );
        std::printf( "flowchart LR\n" );
        // group shown nodes by TOP-LEVEL directory component → mermaid subgraphs (visual subsystem clusters)
        HashMap<std::string, std::vector<std::uint32_t>> groups;
        std::vector<std::string>                         groupOrder;
        for( std::size_t i = 0; i < nShown; ++i )
        {
            const std::uint32_t c   = order[i];
            const std::string   lab = label( c );
            const std::size_t   sl  = lab.find( '/' );
            const auto [ it, ins ]  = groups.try_emplace( sl == std::string::npos ? lab : lab.substr( 0, sl ) );
            if( ins )
            {
                groupOrder.push_back( it->first );
            }
            it->second.push_back( c );
        }
        std::size_t gi = 0;
        for( const std::string& gname : groupOrder )
        {
            const std::vector<std::uint32_t>& gnodes = groups[ gname ];
            const bool wrap = gnodes.size() > 1;                       // wrap multi-node subsystems; lone dirs stay bare
            if( wrap )
            {
                std::printf( "  subgraph sg%zu [\"%s\"]\n", gi, gname.c_str() );
            }
            for( std::uint32_t c : gnodes )
            {
                std::printf( "%sn%u[\"%s<br/>%u\"]\n", wrap ? "    " : "  ", c, label( c ).c_str(), sz[c] );
            }
            if( wrap )
            {
                std::printf( "  end\n" );
            }
            ++gi;
        }
        std::vector<std::pair<std::uint64_t, std::uint32_t>> edges( w.begin(), w.end() );
        std::sort( edges.begin(), edges.end(), []( const auto& a, const auto& b ) { return a.first < b.first; } );
        for( const auto& [ key, weight ] : edges )
        {
            const std::uint32_t du = std::uint32_t( key >> 32 ), dv = std::uint32_t( key & 0xffffffffu );
            if( weight < minW || !shown[du] || !shown[dv] )
            {
                continue;
            }
            std::printf( "  n%u -->|%u| n%u\n", du, weight, dv );
        }
        return 0;
    }

    // --report: an at-a-glance architecture summary (markdown) — modules + god-files + cycles + top symbols
    // + cross-module bridges. Synthesizes the deterministic analyses; no git, no LLM. (graphify's GRAPH_REPORT)
    if( cfg.report )
    {
        const std::uint32_t      N    = std::uint32_t( ing.symbols.size() );
        const std::uint32_t      F    = std::uint32_t( ing.files.size() );
        const rw::Communities   cm   = rw::communities( g );
        const auto [ rank, prIters, prConverged ] = rankGraph( g );
        const rw::RankDisclosure prD{ prIters, prConverged, true };   // W2-F: this document is PageRank-ordered

        CommunityMembers members( cm.count );
        for( NodeId i = 0; i < N; ++i )
        {
            members[cm.comm[i]].push_back( i );
        }
        const CommunityPresentation presentation = communityPresentation( ing, g, members, rank, stRootPrefix );
        for( auto& m : members )
        {
            std::sort( m.begin(), m.end(), [ & ]( NodeId a, NodeId b )
                       { return rank[a] != rank[b] ? rank[a] > rank[b] : a < b; } );
        }

        std::uint32_t modules = 0;
        for( std::uint32_t c = 0; c < cm.count; ++c )
        {
            if( members[c].size() >= 2 )
            {
                ++modules;
            }
        }
        const IsolateStats isolates = isolateStats( ing, g, members );

        const auto                 adj = resolveIncludeAdj( ing );
        std::vector<std::uint32_t> afferent( F, 0 );
        for( std::size_t a = 0; a < adj.size(); ++a )
        {
            for( std::uint32_t b : adj[a] )
            {
                if( b < F )
                {
                    ++afferent[b];
                }
            }
        }
        const auto cycles = sccCycles( adj );

        // §P7 embedding contract: this markdown never contains a run of 4-or-more backticks, so a consumer's
        // 5-backtick fence always safely embeds it whole (test/mdembedcheck.sh pins this). Every element below
        // is SYNTHESIZED (counts, sorted names, fixed section labels) — no verbatim file content is embedded,
        // which is what makes this an enforceable guarantee rather than an incidental one (contrast --recall).
        std::printf( "<!-- ripwire markdown: no run of 4-or-more backticks in this output — safe to embed inside a wider fence -->\n\n" );
        // W2-F: markdown has no attribute grammar — the note is emitted ONLY on the truncating exit.
        std::printf( "%s", rw::renderDisclosure( prD, rw::DiscloseAs::MarkdownNote ).c_str() );
        std::printf( "# ripwire architecture report\n\n%u files · %u symbols · %u edges · %u modules (%u call-graph isolated)\n\n",
                     F, N, std::uint32_t( g.outTargets.size() ), modules, isolates.total );
        // R-E (2026-08-17 harvest): paths below are root-relative on a single-root run (same convention every
        // other verb's root= attribute states); this line is the markdown twin — the ONLY place the absolute
        // root is spelled, so it stays recoverable from the document per the honesty rule every other verb follows.
        if( stSingleRoot )
        {
            std::printf( "Root: `%.*s`\n\n", int( cfg.roots[0].size() ), cfg.roots[0].data() );
        }
        std::printf( "Call-graph isolate provenance: %u declaration, %u header, %u source, %u document; %u connected Louvain singletons\n\n",
                     isolates.declaration, isolates.header, isolates.source, isolates.document, isolates.connectedSingletons );

        std::vector<std::uint32_t> ord( cm.count );
        for( std::uint32_t c = 0; c < cm.count; ++c )
        {
            ord[c] = c;
        }
        std::sort( ord.begin(), ord.end(), [ & ]( std::uint32_t a, std::uint32_t b ) { return members[a].size() != members[b].size() ? members[a].size() > members[b].size() : a < b; } );
        const std::uint32_t reportModules = std::min<std::uint32_t>( modules, 12 );
        std::printf( "## Modules (call-graph clusters; showing %u of %u)\n", reportModules, modules );
        std::uint32_t shown = 0;
        // §P6.2: no separate "(lead: ...)" annotation — the label above IS the semantic anchor now (highest
        // fan-in non-accessor member), so a second "top PageRank member" field would just reintroduce the
        // accessor name (push_back/empty/...) this fix exists to keep out of the reader's first screen.
        for( std::uint32_t c : ord )
        {
            if( members[c].size() < 2 )
            {
                continue;
            }
            if( shown++ >= 12 )
            {
                break;
            }
            std::printf( "- **%s** — %zu symbols\n", presentation.label[c].c_str(), std::size_t( members[c].size() ) );
        }

        std::vector<std::uint32_t> ford( F );
        for( std::uint32_t f = 0; f < F; ++f )
        {
            ford[f] = f;
        }
        std::sort( ford.begin(), ford.end(), [ & ]( std::uint32_t a, std::uint32_t b ) { return afferent[a] != afferent[b] ? afferent[a] > afferent[b] : a < b; } );
        const std::size_t godFileCount = std::count_if( afferent.begin(), afferent.end(), []( std::uint32_t count ) { return count > 0; } );
        const std::size_t reportGodFiles = std::min<std::size_t>( godFileCount, 10 );
        std::printf( "\n## God files (most depended-on; showing %zu of %zu)\n", reportGodFiles, godFileCount );
        bool anyGod = false;
        for( std::uint32_t i = 0; i < F && i < 10; ++i )
        {
            if( afferent[ford[i]] == 0 )
            {
                break;
            }
            anyGod = true;
            const std::string_view rp = stSingleRoot ? rw::sarif::rootRelativeUri( ing.files[ford[i]], stRootPrefix ) : std::string_view( ing.files[ford[i]] );
            std::printf( "- `%.*s` — %u dependents\n", int( rp.size() ), rp.data(), afferent[ford[i]] );
        }
        if( !anyGod )
        {
            std::printf( "- (no include/import edges captured)\n" );
        }

        const std::size_t reportCycles = std::min<std::size_t>( cycles.size(), 6 );
        std::printf( "\n## Dependency cycles (showing %zu of %zu)\n", reportCycles, cycles.size() );
        if( cycles.empty() )
        {
            std::printf( "- none (acyclic)\n" );
        }
        else
        {
            for( std::size_t i = 0; i < cycles.size() && i < 6; ++i )
            {
                std::printf( "- " );
                for( std::size_t j = 0; j < cycles[i].size(); ++j )
                {
                    const std::string_view rp = stSingleRoot ? rw::sarif::rootRelativeUri( ing.files[cycles[i][j]], stRootPrefix ) : std::string_view( ing.files[cycles[i][j]] );
                    std::printf( "%s`%.*s`", j ? " ↔ " : "", int( rp.size() ), rp.data() );
                }
                std::printf( "\n" );
            }
        }

        std::vector<NodeId> ts( N );
        for( NodeId i = 0; i < N; ++i )
        {
            ts[i] = i;
        }
        std::sort( ts.begin(), ts.end(), [ & ]( NodeId a, NodeId b ) { return rank[a] != rank[b] ? rank[a] > rank[b] : a < b; } );
        const std::uint32_t reportTopSymbols = std::min<std::uint32_t>( N, 10 );
        std::printf( "\n## Top symbols (PageRank; showing %u of %u)\n", reportTopSymbols, N );
        for( std::uint32_t i = 0; i < N && i < 10; ++i )
        {
            const Symbol&           s  = ing.symbols[ ts[i] ];
            const std::string_view  rp = stSingleRoot ? rw::sarif::rootRelativeUri( ing.files[ s.fileId ], stRootPrefix ) : std::string_view( ing.files[ s.fileId ] );
            std::printf( "- `%s` (%.*s:%u)\n", s.name.c_str(), int( rp.size() ), rp.data(), s.line );
        }

        HashMap<std::uint64_t, std::uint32_t> bridge;
        for( NodeId u = 0; u < N; ++u )
        {
            for( std::uint32_t k = g.outOff[u]; k < g.outOff[u + 1]; ++k )
            {
                const std::uint32_t cu = cm.comm[u], cv = cm.comm[g.outTargets[k]];
                if( cu == cv )
                {
                    continue;
                }
                const std::uint32_t a = std::min( cu, cv ), b = std::max( cu, cv );
                ++bridge[( std::uint64_t( a ) << 32 ) | b];
            }
        }
        std::vector<std::pair<std::uint64_t, std::uint32_t>> br( bridge.begin(), bridge.end() );
        std::sort( br.begin(), br.end(), []( const auto& a, const auto& b ) { return a.second != b.second ? a.second > b.second : a.first < b.first; } );
        const std::size_t reportBridges = std::min<std::size_t>( br.size(), 8 );
        std::printf( "\n## Cross-module bridges (showing %zu of %zu)\n", reportBridges, br.size() );
        if( br.empty() )
        {
            std::printf( "- (none)\n" );
        }
        else
        {
            for( std::size_t i = 0; i < br.size() && i < 8; ++i )
            {
                const std::uint32_t a = std::uint32_t( br[i].first >> 32 ), b = std::uint32_t( br[i].first & 0xffffffffu );
                std::printf( "- %s ↔ %s (%u edges)\n", presentation.label[a].c_str(), presentation.label[b].c_str(), br[i].second );
            }
        }
        return 0;
    }

    // --tree: a file-by-file orientation map — each file with its top symbols by rank. The agentmap
    // "frontmatter for source files" idea: a cheap session-start overview. Deterministic (files by best
    // symbol rank, path breaking ties; symbols within a file by rank, id breaking ties).
    if( cfg.tree )
    {
        const auto [ rank, prIters, prConverged ] = rankGraph( g );
        const rw::RankDisclosure prD{ prIters, prConverged, true };   // W2-F: this document is PageRank-ordered
        const std::uint32_t      F    = std::uint32_t( ing.files.size() );
        SymbolsByFile              byFile = symbolsByFileInIdOrder( ing, []( const Symbol& ) { return true; } );
        std::vector<std::uint32_t> ford;  ford.reserve( F );   // ONLY non-empty files (the emitted set)
        for( std::uint32_t f = 0; f < F; ++f )
        {
            if( !byFile[f].empty() )
            {
                ford.push_back( f );
            }
        }

        // §P11.8: files lead by their best symbol's rank, not asciibetically — see the function above.
        orderFilesByBestSymbolRank( ford, ing, rank );
        // §A8.5: files= (the TRUE indexed corpus, comment below) exceeded the complete row set (ford, the
        // listable non-empty subset) with the divergence documented only in this comment — a reader outside
        // the source never learned WHY the two counts disagreed. files_unlisted= closes it: the count of
        // symbol-less files files= includes but no <file> row can ever list (fine — a file with no symbols
        // has nothing to preview — but silent until now).
        const std::uint32_t filesUnlisted = F - std::uint32_t( ford.size() );
        // ── verifier FINDING E1 (2026-08-19): --tree was the single largest absolute-path emitter left in the
        //    tool — 1,212 rows on ripwire's own corpus, more than every verb rootrelcheck already covered put
        //    together — and it is the session-start orientation map the skills route to FIRST. Same shape as
        //    every other verb's root=: the single-root condition from sarif.h, the shared legend clause from
        //    graphlegend.h emitted exactly when the attribute is, and root= appended AFTER the paging and
        //    PageRank disclosures so nothing already on this element moves.
        const bool         trSingleRoot = ing.realPaths.empty() && cfg.roots.size() == 1;
        const std::string  trRootPrefix = trSingleRoot ? rw::sarif::rootPrefixOf( cfg.roots[0] ) : std::string();
        std::vector<char>  trRootEsc;
        const std::string  trRootAttr   = trSingleRoot ? ( " root=\"" + std::string( rw::escapeXml( cfg.roots[0], trRootEsc ) ) + "\"" ) : std::string();
        std::printf( "<!-- ripwire tree: each file + its top symbols by rank, files ordered by their best "
                     "symbol's rank (path breaks ties) — a session-start orientation map. files= is the indexed "
                     "corpus; rows list files WITH symbols; files_unlisted= holds the symbol-less remainder "
                     // W3FIX NIT: "files equals the listed rows plus files_unlisted on every run" reads FALSE on
                     // a paged run, where the rows below are one WINDOW of the listable set (files=825
                     // files_unlisted=21 total=804 shown=2). One sentence now carries both cases by naming the
                     // pre-paging set, and introduces total= as the number the identity is actually about.
                     "— files equals files_unlisted plus the LISTABLE file set, which is what the rows below "
                     "enumerate before any paging window is applied; under explicit paging (limit=/offset=) that "
                     "listable count is emitted as total= and shown= says how many of it these rows are. "
                     // P4 (L7): the default window, defined where the reader meets it
                     "The rows are a WINDOW even without explicit paging: the default prints the 80 files with the best-ranked symbols "
                     "(shown=/capped=/total=/has_more=/next_offset= disclose the cut) and next= pastes the next page; limit= raises it. "
                     "%s-->%s", rw::renderDisclosure( prD, rw::DiscloseAs::LegendClause ).c_str(),
                     rw::rootRelPathsLegend( trSingleRoot ) );
        // T2 + §P8 G1: --limit/--offset paginate over the (sorted) non-empty file set. files= stays the TRUE
        // total of INDEXED files (all of them, matching pre-T2) — deliberately NOT the paging total, because
        // the emitted rows are the non-empty subset `ford`, and total= must be the count a next_offset walks
        // toward. The two therefore differ on any tree with symbol-less files, which is why total= is the one
        // pageview emits and files= is left exactly as it was. discloseCap=false: --tree has no display cap,
        // so the un-paginated tag is byte-identical. See src/pageview.h, THE TRUNCATION VOCABULARY.
        // P4 (L7): kTreeRowCap is the DEFAULT window now (187,209 B / 3,773 rows on this repo before); --limit=N
        // raises it. discloseCap fires exactly when the window cut the list, so a tree that fits stays byte-identical.
        const PageWindow  pw = pageWindow( ford.size(), effectiveRowCap( cfg.pageLimit, kTreeRowCap ), cfg.pageOffset );
        const bool        treeCut  = pw.end - pw.begin < ford.size();
        const std::string treeNext = treeCut ? rw::nextAttrXml( "--tree --offset=" + std::to_string( pw.end ) ) : std::string();
        char              pab[ kPageDisclosureCap ];
        std::printf( "<tree files=\"%u\" files_unlisted=\"%u\"%s%s%s>", F, filesUnlisted,
                     ( pageDisclosure( pab, sizeof( pab ), pw.end - pw.begin, ford.size(), pw.end,
                                       cfg.pageLimit, cfg.pageOffset, treeCut )
                       + rw::renderDisclosure( prD, rw::DiscloseAs::XmlAttrs ) ).c_str(),
                     trRootAttr.c_str(), treeNext.c_str() );
        std::vector<char> trEsc;
        for( std::size_t fi = pw.begin; fi < pw.end; ++fi )
        {
            const std::uint32_t f    = ford[fi];
            FileSymbols&        syms = byFile[f];
            std::sort( syms.begin(), syms.end(), [ & ]( NodeId a, NodeId b ) { return rank[a] != rank[b] ? rank[a] > rank[b] : a < b; } );
            // path and symbol names may contain & < > " — escape them to keep XML well-formed.
            const auto ep = rw::escapeXml( trSingleRoot ? rw::sarif::rootRelativeUri( ing.files[f], trRootPrefix )
                                                        : std::string_view( ing.files[f] ), trEsc );
            std::printf( "<file p=\"%.*s\" symbols=\"%zu\">", int( ep.size() ), ep.data(), std::size_t( syms.size() ) );
            const std::size_t topN = std::min<std::size_t>( 3, syms.size() );
            for( std::size_t i = 0; i < topN; ++i )
            {
                const Symbol& s = ing.symbols[ syms[i] ];
                const auto en = rw::escapeXml( s.name, trEsc );
                std::printf( "<s t=\"%s\" n=\"%.*s\"/>", symTag( s.kind ), int( en.size() ), en.data() );
            }
            std::printf( "</file>" );
        }
        std::printf( "</tree>" );
        return 0;
    }
    return std::nullopt;
}


}   // namespace — verbs_report.h section of main.cpp
