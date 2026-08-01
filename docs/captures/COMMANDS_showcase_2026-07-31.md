# ripwire — every verb, run for real

- **Date:** 2026-07-31 (regenerated capture; supersedes any older `docs/captures/COMMANDS_showcase_*.md`)
- **Lives in `docs/captures/`** — a directory the crawl/retrieval lenses SKIP (`kCrawlSkipDirs`, src/ingest.h): a generated doc that quotes every verb's output out-scores the source for any query about the tool and was 77% of `--recall` on this repo when it sat at the root (PLAN_outputAudit_2026-07-28.md §P2). `test/argvdiffcheck.sh` harvests its `## `-heading command lines as differential vectors — keep that format.
- **Version:** `ripwire 0.1.0 (dev, AppleClang 21.0.0.21000101)`
- **Repo:** the ripwire repo @ `1dc07e2` — **dirty: ['M src/cli.h', ' M test/docscommandscheck.sh', ' M test/showcase_capture.py', '?? docs/captures/']**. That is the one structural difference from the previous capture, which ran against a deliberately dirty tree. A clean tree is the honest default for a showcase, so the diff-aware verbs (`--situ`/`--test-gate`/`--quality-delta`/`--pr-context`/`--map-diff`) appear TWICE: once here on the clean tree (their empty/exit-0 shape) and once in the final section against a throwaway `git clone --local` sandbox carrying one deliberate regression, so their real gating shapes are visible without writing a byte into the read-only repo.
- **Corpus:** the ripwire repo itself (dogfood), via `./build/ripwire`
- **Sandbox diff** (the last section only): `src/sortutil.h | 67 +++++++++++++++++++++++++++++++++++++++++++++++++++++++---
 1 file changed, 64 insertions(+), 3 deletions(-)` — one preexisting function made deeply nested, one function's arity changed 1 -> 2, one copy-paste duplicate helper, one new 8-parameter public function.

**How to read the blocks:** ripwire's real XML output is minified — often ONE long line. For scanability, long minified lines are displayed re-wrapped with a line break at every tag seam (`><`). Header COMMENT lines (the legends) always appear in full — they are exempt from the per-line cut; any OTHER display line over 300 bytes is cut with a `… [line truncated: N more bytes]` marker, which can hit a long root element or row. `--plan-lanes` emits JSON and is re-wrapped at object seams the same way. Long outputs are cut to their first ~30 display lines with a `… [N more display lines; full output is M bytes]` marker giving the true size. Exit codes are recorded when non-zero; wall time when >1s.

**Not run (and why):** `ripwire <git-url>` (network clone), `--mcp` / `--listen` / `--mcp-token` / `--allow-remote-edits` (persistent servers — `wrap claude` below shows the wiring), `--note-add` / `--quality-baseline` / `--arch --baseline[-update]` / `--index-out` (state writers; the repo is read-only for this capture — `--quality-ack` IS shown, but only inside the throwaway sandbox clone), `--eval-mined` (needs a `minedpair.jsonl` artifact from `bench/mine_traces.py`; none present in the tree), `--refetch` (git-url only), `--force` (wrap-only modifier), `--scan-skills` bare form (would sweep `~/.claude/skills`; the explicit-DIR form is shown instead), `--help` (754 lines — read it from the binary).


---

# understand a codebase cold

## `./build/ripwire .`

*The default ranked symbol map — start here when landing cold in a repo.*

`````
<!-- ripwire v1 t=fn|method|cls|struct|iface|var|sec p=path layer=arch-layer(opt) n=name id=canonical(path::scope::name,when-scoped) k=rank c=call amb=ambiguous-calls(read-source) overloads=N-same-name-defs-merged-into-this-row(absent-if-1;shown=counts-them-individually,so-rows+sum(overloads-1)=shown) prov=scip(precise;else name-based) hdr:unresolved=call-name-defined-only-in-a-lang-incompatible-file (edges heuristic) r:est_tokens=hdr-copy(none-if-stable) -->
<!-- files=836 symbols=6432 edges=8733 shown=200 est_tokens=9677 ambiguous=2631 unresolved=652 precise=3 skipped_oversize=3 order=important-first -->
<r est_tokens="9677">
<f p="./src/svector.h">
<s t="method" n="size" id="./src/svector.h::svector::size" k="0.0503">
</s>
<s t="method" n="push_back" id="./src/svector.h::svector::push_back" amb="2" k="0.0133">
<c n="buf"/>
<c n="buf"/>
<c n="grow"/>
</s>
<s t="method" n="buf" id="./src/svector.h::svector::buf" overloads="2" k="0.0123">
</s>
<s t="method" n="grow" id="./src/svector.h::svector::grow" amb="1" k="0.0073">
<c n="buf"/>
<c n="buf"/>
</s>
<s t="method" n="end" id="./src/svector.h::svector::end" overloads="2" amb="1" k="0.0044">
<c n="buf"/>
<c n="buf"/>
</s>
<s t="method" n="reserve" id="./src/svector.h::svector::reserve" k="0.0030">
<c n="grow"/>
</s>
<s t="method" n="begin" id="./src/svector.h::svector::begin" overloads="2" amb="1" k="0.0023">
<c n="buf"/>
<c n="buf"/>
</s>
</f>
<f p="./src/scipoverlay.h">
… [860 more display lines; full output is 23974 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --top-k=5`

*Same map, capped to the 5 highest-ranked symbols.*

`````
<!-- ripwire v1 t=fn|method|cls|struct|iface|var|sec p=path layer=arch-layer(opt) n=name id=canonical(path::scope::name,when-scoped) k=rank c=call amb=ambiguous-calls(read-source) overloads=N-same-name-defs-merged-into-this-row(absent-if-1;shown=counts-them-individually,so-rows+sum(overloads-1)=shown) prov=scip(precise;else name-based) hdr:unresolved=call-name-defined-only-in-a-lang-incompatible-file (edges heuristic) r:est_tokens=hdr-copy(none-if-stable) -->
<!-- files=836 symbols=6432 edges=8733 shown=5 est_tokens=428 ambiguous=2631 unresolved=652 precise=3 skipped_oversize=3 order=important-first -->
<r est_tokens="428">
<f p="./src/svector.h">
<s t="method" n="size" id="./src/svector.h::svector::size" k="0.0503">
</s>
<s t="method" n="push_back" id="./src/svector.h::svector::push_back" amb="2" k="0.0133">
<c n="buf"/>
<c n="buf"/>
<c n="grow"/>
</s>
<s t="method" n="buf" id="./src/svector.h::svector::buf" overloads="2" k="0.0123">
</s>
</f>
<f p="./src/scipoverlay.h">
<s t="method" n="empty" id="./src/scipoverlay.h::ScipOverlay::empty" k="0.0126">
</s>
</f>
</r>
`````

## `./build/ripwire . --top-k=0 --expand=rankGraphTeleport`

*NEW since the last capture: --top-k=0 means PAYLOAD-ONLY — no ranked map rides along with the body you asked for.*

`````
<ctx><bodies shown="1" total="1" capped="0"><b t="fn" l="1278" p="./src/graph.h" n="rankGraphTeleport"><![CDATA[inline std::vector<float> rankGraphTeleport( const Graph& g, const std::vector<float>& p, float alpha = 0.85f )
{
    PROFILE_SCOPE_DESCRIBE( "rankGraph: PageRank (power iteration)" );
    const std::vector<float> pw = biasPrior( g, p );
    const std::size_t N = pw.size();
    std::vector<double> teleport( pw.begin(), pw.end() );
    std::vector<double> rankDouble( N, 0.0 );
    if( N )
    {
        double teleportMass = 0.0;
        for( const double value : teleport )
            teleportMass += value;
        if( teleportMass > 0.0 )
        {
            const double inverseMass = 1.0 / teleportMass;
            for( double& value : teleport )
                value *= inverseMass;
        }
        pageRankDouble( g.inEdges, g.wOutDeg, teleport, rankDouble, PageRankConfig{ .alpha = double( alpha ) } );
    }
    std::vector<float> r( N, 0.f );
    std::transform( rankDouble.begin(), rankDouble.end(), r.begin(), []( double value ) { return float( value ); } );
    return r;
}]]><calls total="7"><c n="biasPrior" l="1263">inline std::vector&lt;float&gt; biasPrior( const Graph&amp; g, const std::vector&lt;float&gt;&amp; p )</c><c n="pageRankDouble" l="34">unsigned pageRankDouble( const sparseCsr&lt;float&gt;&amp; inEdges, std::span&lt;const double&gt; weightedOutDegree, s … [line truncated: 369 more bytes on this line]
`````

## `./build/ripwire . --top-k=0`

*--top-k=0 with NO payload verb asked for — what an empty request emits.*

**exit code: 1**

`````
(empty)
`````

stderr:

`````
ripwire: --top-k=0 means "no ranked map, payload only" — pass a payload verb (--expand=SYM / --outline=SYM / --pack-signatures / --pack-top-n=N), or use --top-k=1 for the smallest map
`````

## `./build/ripwire . --max-tokens=1500`

*SHAPE the map to fit ~1500 tokens (binary-search top-K).*

`````
<!-- ripwire v1 t=fn|method|cls|struct|iface|var|sec p=path layer=arch-layer(opt) n=name id=canonical(path::scope::name,when-scoped) k=rank c=call amb=ambiguous-calls(read-source) overloads=N-same-name-defs-merged-into-this-row(absent-if-1;shown=counts-them-individually,so-rows+sum(overloads-1)=shown) prov=scip(precise;else name-based) hdr:unresolved=call-name-defined-only-in-a-lang-incompatible-file (edges heuristic) r:est_tokens=hdr-copy(none-if-stable) -->
<!-- max_tokens=asked fit_bytes=honoured: fit_bytes = max_tokens x 2.36 (densest-language B/tok) x 0.90 headroom, a CONSERVATIVE cap, so est_tokens (this corpus's own rate) lands ~10-20% BELOW max_tokens by design; the token-budget gate compares against est_tokens, not fit_bytes; over_ceiling=floor-alone-exceeded-fit_bytes(absent=cap-held) -->
<!-- files=836 symbols=6432 edges=8733 shown=21 est_tokens=1255 ambiguous=2631 unresolved=652 precise=3 skipped_oversize=3 max_tokens=1500 fit_bytes=3186 order=important-first -->
<r est_tokens="1255">
<f p="./src/svector.h">
<s t="method" n="size" id="./src/svector.h::svector::size" k="0.0503">
</s>
<s t="method" n="push_back" id="./src/svector.h::svector::push_back" amb="2" k="0.0133">
<c n="buf"/>
<c n="buf"/>
<c n="grow"/>
</s>
<s t="method" n="buf" id="./src/svector.h::svector::buf" overloads="2" k="0.0123">
</s>
<s t="method" n="grow" id="./src/svector.h::svector::grow" amb="1" k="0.0073">
<c n="buf"/>
<c n="buf"/>
</s>
<s t="method" n="end" id="./src/svector.h::svector::end" overloads="2" amb="1" k="0.0044">
<c n="buf"/>
<c n="buf"/>
</s>
<s t="method" n="reserve" id="./src/svector.h::svector::reserve" k="0.0030">
<c n="grow"/>
</s>
<s t="method" n="begin" id="./src/svector.h::svector::begin" overloads="2" amb="1" k="0.0023">
<c n="buf"/>
<c n="buf"/>
</s>
</f>
… [49 more display lines; full output is 3115 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --token-budget=100`

*GATE form: exit 3 if the map's own est_tokens exceeds the budget (over-budget failure shape).*

**exit code: 3**

`````
<r withheld_est_tokens="9677" budget="100" withheld="1"/>
`````

stderr:

`````
ripwire: --token-budget exceeded: withheld_est_tokens=9677 > budget=100
`````

## `./build/ripwire . --for="incremental cache invalidation when a file content hash changes"`

*The task lens: ranked signatures + quality metrics framed for the task.*

`````
<ctx task="incremental cache invalidation when a file content hash changes" route=" [routed: subtoken+body BM25 (--for&apos;s default) — no strong name hit, multi-word conceptual query]">
<!-- ripwire lens for "incremental cache invalidation when a file content hash changes" [routed: subtoken+body BM25 (-for's default) — no strong name hit, multi-word conceptual query] [doc mentions: 1 doc discussing 1 top-ranked symbol surfaced]: reusable building blocks + quality facts for what you're about to touch (cx=complexity ccx=cognitive in=reuse-count churn=recent-commits amp=change-amplification clone=1(duplicated) tested=1) — prefer composing/reusing these; watch the high-churn/high-amp/cloned ones est_tokens="2908" -->
<sigs capped="1">
<f p="./src/ingest.h">
<d l="85" n="ingest" id="./src/ingest.h::rw::ingest" cx="1" ccx="0" in="0" churn="2" tested="1">
<doc>for vendored/generated trees not caught by the built-in dir denylist (--exclude=SUBSTR). cacheFi…</doc>IngestResult ingest( const char* rootDir, const std::vector&lt;std::string&gt;&amp; excludeSubstr =</d>
</f>
<f p="./src/mcpindex.h">
<d l="80" n="collectDirMtimes" id="./src/mcpindex.h::mcpdetail::collectDirMtimes" cx="13" ccx="21" in="1" churn="3" amp="1">inline void collectDirMtimes( const std::string&amp; root, HashMap&lt;std::string, long long&gt;&amp; dirMtime…</d>
<d l="253" n="byteHash" id="./src/mcpindex.h::mcpdetail::byteHash" cx="2" ccx="1" in="4" churn="3" amp="4">inline std::uint64_t byteHash( const char* data, std::size_t n ) noexcept</d>
<d l="285" n="stableHandleId" id="./src/mcpindex.h::mcpdetail::stableHandleId" cx="2" ccx="1" in="2" churn="3" amp="2">inline std::string stableHandleId( const std::string&amp; canonId, const std::string&amp; path, const std::string&amp; name )</d>
<d l="296" n="makeHandle" id="./src/mcpindex.h::mcpdetail::makeHandle" cx="1" ccx="0" in="1" churn="3" amp="1">inline std::string makeHandle( const std::string&amp; canonId, const std::string&amp; path, const std::string&amp; name, std::uint64_t contentHash )</d>
<d l="309" n="parseHandle" id="./src/mcpindex.h::mcpdetail::parseHandle" cx="10" ccx="13" in="1" churn="3" amp="1">inline bool parseHandle( const std::string&amp; h, std::uint64_t&amp; idHash, std::uint64_t&amp; contentHash )</d>
<d l="341" n="indexContentHash" id="./src/mcpindex.h::mcpdetail::indexContentHash" cx="5" ccx="7" in="1" churn="3" amp="1">inline std::uint64_t indexContentHash( const std::vector&lt;std::string&gt;&amp; files, const std::vector&lt;long long&gt;&amp; fileMtime, const std::vector&lt;std::uint64_t&gt; … [line truncated: 20 more bytes on this line]
<d l="372" n="McpIndex" id="./src/mcpindex.h::McpIndex::McpIndex" cx="0" ccx="0" in="0" churn="3">
<doc>persistent in-memory index (parse once, reuse across MCP calls) ---- The MCP server is long-live…</doc>struct McpIndex</d>
<d l="516" n="mcpStale" id="./src/mcpindex.h::rw::mcpStale" cx="9" ccx="13" in="1" churn="3" amp="1">inline bool mcpStale( const McpIndex&amp; ix, bool skipDirSweep = false )</d>
<d l="734" n="getIndex" id="./src/mcpindex.h::rw::getIndex" cx="20" ccx="38" in="25" churn="3" amp="25">
<doc>the cached index for `root`, rebuilt only when stale (otherwise returned as-is, no parse, no gra…</doc>inline const McpIndex&amp; getIndex( const std::string&amp; root )</d>
<d l="852" n="handleFor" id="./src/mcpindex.h::rw::handleFor" cx="4" ccx="3" in="1" churn="3" amp="1">inline std::string handleFor( const McpIndex&amp; ix, NodeId id )</d>
<d l="869" n="resolveHandleAll" id="./src/mcpindex.h::rw::resolveHandleAll" cx="5" ccx="8" in="2" churn="3" amp="2">inline NodeId resolveHandleAll( const McpIndex&amp; ix, std::uint64_t idHash, std::vector&lt; NodeId &gt;&amp; matches )</d>
</f>
<f p="./src/ingest.cpp">
<d l="526" n="StatInfo" id="./src/ingest.cpp::StatInfo::StatInfo" cx="0" ccx="0" in="0" churn="3">struct StatInfo</d>
<d l="544" n="wallClockNs" cx="1" ccx="0" in="1" churn="3" amp="1">inline long long wallClockNs() noexcept</d>
<d l="562" n="compiledQueryCache" cx="1" ccx="0" in="2" churn="3" amp="2">HashMap&lt;const TSLanguage*, TSQuery*&gt;&amp; compiledQueryCache()</d>
<d l="847" n="contentHash64" cx="2" ccx="1" in="1" churn="3" amp="1">
<doc>T5: renamed from fnv1a64 to contentHash64 to avoid an ODR clash now that this file also includes…</doc>inline std::uint64_t contentHash64( std::string_view s ) noexcept</d>
<d l="859" n="blobChecksum" cx="5" ccx="5" in="2" churn="3" amp="2">inline std::uint64_t blobChecksum( std::string_view s ) noexcept</d>
<d l="878" n="FileFacts" id="./src/ingest.cpp::FileFacts::FileFacts" cx="0" ccx="0" in="0" churn="3">struct FileFacts</d>
… [28 more display lines; full output is 7269 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --for="rankGraphTeleport"`

*Name-shaped query: the router picks name-exact BM25 (header says which/why).*

`````
<ctx task="rankGraphTeleport" route=" [routed: name-exact BM25 — query names a symbol (rankGraphTeleport)]">
<!-- ripwire lens for "rankGraphTeleport" [routed: name-exact BM25 — query names a symbol (rankGraphTeleport)]: reusable building blocks + quality facts for what you're about to touch (cx=complexity ccx=cognitive in=reuse-count churn=recent-commits amp=change-amplification clone=1(duplicated) tested=1) — prefer composing/reusing these; watch the high-churn/high-amp/cloned ones est_tokens="2236" -->
<sigs>
<f p="./src/graph.h">
<d l="1278" n="rankGraphTeleport" id="./src/graph.h::rw::rankGraphTeleport" cx="5" ccx="8" in="6" churn="3" amp="6">
<doc>PageRank with an explicit teleport / personalization vector p (Σp = 1). The prior is name-quality-biased (W4-#1) here so all rank modes share one weighting seam; the transition matrix (edges) is unto</doc>inline std::vector&lt;float&gt; rankGraphTeleport( const Graph&amp; g, const std::vector& … [line truncated: 46 more bytes on this line]
</f>
<f p="./AGENTS.md">
<d l="1" n="AGENTS" cx="0" ccx="0" in="0" churn="1" amp="2"># ripwire — agent instructions This repository follows the `AGENTS.md` convention. The full agent guide is **`CLAUDE.md`**</d>
<d l="1" n="ripwire — agent instructions" cx="0" ccx="0" in="0" churn="1" amp="2"># ripwire — agent instructions</d>
<d l="9" n="Setup" cx="0" ccx="0" in="0" churn="1" amp="2">## Setup</d>
<d l="18" n="Test" cx="0" ccx="0" in="0" churn="1" amp="2">## Test</d>
<d l="36" n="Rules that will fail your change if you break them" cx="0" ccx="0" in="0" churn="1" amp="2">## Rules that will fail your change if you break them</d>
<d l="50" n="Documentation" cx="0" ccx="0" in="0" churn="1" amp="2">## Documentation</d>
</f>
<f p="./CHANGELOG.md">
<d l="1" n="CHANGELOG" cx="0" ccx="0" in="0" churn="1"># Changelog All notable changes to ripwire are documented in this file. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). **No release has been cut yet.** Everything below is unreleased and pre-1.0: the flag surfa</d>
<d l="1" n="Changelog" cx="0" ccx="0" in="0" churn="1"># Changelog</d>
<d l="15" n="[Unreleased]" cx="0" ccx="0" in="0" churn="1">## [Unreleased]</d>
<d l="17" n="Added — retrieval and ranking" cx="0" ccx="0" in="0" churn="1">### Added — retrieval and ranking</d>
<d l="51" n="Added — navigation and the call graph" cx="0" ccx="0" in="0" churn="1">### Added — navigation and the call graph</d>
<d l="68" n="Added — change safety and review" cx="0" ccx="0" in="0" churn="1">### Added — change safety and review</d>
<d l="96" n="Added — cross-branch archaeology" cx="0" ccx="0" in="0" churn="1">### Added — cross-branch archaeology</d>
<d l="119" n="Added — dark code and feature flags" cx="0" ccx="0" in="0" churn="1">### Added — dark code and feature flags</d>
<d l="146" n="Added — documentation drift" cx="0" ccx="0" in="0" churn="1">### Added — documentation drift</d>
<d l="165" n="Added — the git-history oracle" cx="0" ccx="0" in="0" churn="1">### Added — the git-history oracle</d>
<d l="199" n="Added — languages" cx="0" ccx="0" in="0" churn="1">### Added — languages</d>
<d l="220" n="Added — output shaping, honesty and paging" cx="0" ccx="0" in="0" churn="1">### Added — output shaping, honesty and paging</d>
<d l="263" n="Added — architecture, quality and structure" cx="0" ccx="0" in="0" churn="1">### Added — architecture, quality and structure</d>
<d l="285" n="Added — MCP server and agent wiring" cx="0" ccx="0" in="0" churn="1">### Added — MCP server and agent wiring</d>
… [26 more display lines; full output is 5591 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --for="rankGraphTeleport" --no-route`

*Same query with routing forced OFF (plain subtoken+body BM25) — contrast with the routed run.*

`````
<ctx task="rankGraphTeleport">
<!-- ripwire lens for "rankGraphTeleport" [doc mentions: 1 doc discussing 1 top-ranked symbol surfaced]: reusable building blocks + quality facts for what you're about to touch (cx=complexity ccx=cognitive in=reuse-count churn=recent-commits amp=change-amplification clone=1(duplicated) tested=1) — prefer composing/reusing these; watch the high-churn/high-amp/cloned ones est_tokens="2976" -->
<sigs capped="1">
<f p="./src/graph.h">
<d l="32" n="Graph" id="./src/graph.h::Graph::Graph" cx="0" ccx="0" in="0" churn="3">struct Graph</d>
<d l="1263" n="biasPrior" id="./src/graph.h::rw::biasPrior" cx="5" ccx="4" in="1" churn="3" amp="1">inline std::vector&lt;float&gt; biasPrior( const Graph&amp; g, const std::vector&lt;float&gt;&amp; p )</d>
<d l="1278" n="rankGraphTeleport" id="./src/graph.h::rw::rankGraphTeleport" cx="5" ccx="8" in="6" churn="3" amp="6">
<doc>PageRank with an explicit teleport / personalization vector p (Σp = 1). The prior is name-quali…</doc>inline std::vector&lt;float&gt; rankGraphTeleport( const Graph&amp; g, const std::vector&lt;float&gt;&amp; p, float alpha = 0.85f )</d>
<d l="1304" n="rankGraph" id="./src/graph.h::rw::rankGraph" cx="2" ccx="1" in="9" churn="3" amp="9">
<doc>uniform-teleport PageRank (the default</doc>inline std::vector&lt;float&gt; rankGraph( const Graph&amp; g, float alpha = 0.85f )</d>
<d l="1553" n="anchoredLexicalRank" id="./src/graph.h::rw::anchoredLexicalRank" cx="10" ccx="10" in="4" churn="3" amp="4">
<doc>anchored rank: pick the top-kAnchorCount symbols by lexical score (score desc, id asc — determ…</doc>inline std::vector&lt;float&gt; anchoredLexicalRank( const Graph&amp; g, const std::vector&lt;float&gt;&amp; lex )</d>
<d l="2012" n="diffTeleport" id="./src/graph.h::rw::diffTeleport" cx="8" ccx="9" in="3" churn="3" amp="3">inline std::vector&lt;float&gt; diffTeleport( const IngestResult&amp; ing, const std::vector&lt;char&gt;&amp; fileChanged, float beta = 0.7f )</d>
</f>
<f p="./src/main.cpp">
<d l="1242" n="computeLensRanking" cx="37" ccx="67" in="3" churn="4" amp="7">rw::LensRanking computeLensRanking( const MainDispatch&amp; d, std::string_view task )</d>
<d l="3887" n="runGraphQuery" cx="7" ccx="12" in="1" churn="4" amp="5">std::optional&lt;int&gt; runGraphQuery( const MainDispatch&amp; d )</d>
<d l="4430" n="runImpact" cx="8" ccx="14" in="1" churn="4" amp="5">std::optional&lt;int&gt; runImpact( const MainDispatch&amp; d )</d>
<d l="4678" n="runExercises" cx="8" ccx="8" in="1" churn="4" amp="5">std::optional&lt;int&gt; runExercises( const MainDispatch&amp; d )</d>
<d l="6239" n="runStructureText" cx="84" ccx="213" in="1" churn="4" amp="5">std::optional&lt;int&gt; runStructureText( const MainDispatch&amp; d )</d>
<d l="7094" n="runAround" cx="12" ccx="21" in="1" churn="4" amp="5">std::optional&lt;int&gt; runAround( const MainDispatch&amp; d )</d>
<d l="7244" n="ChurnRanking" id="./src/main.cpp::ChurnRanking::ChurnRanking" cx="0" ccx="0" in="0" churn="4" amp="4">struct ChurnRanking</d>
<d l="7246" n="churnRankedGraph" cx="7" ccx="8" in="1" churn="4" amp="5">inline ChurnRanking churnRankedGraph( const MainDispatch&amp; d )</d>
<d l="7276" n="runDefaultMap" cx="100" ccx="170" in="1" churn="4" amp="5">int runDefaultMap( const MainDispatch&amp; d )</d>
</f>
<f p="./src/gitmine.h">
<d l="1182" n="churnPriorFromFreq" id="./src/gitmine.h::rw::churnPriorFromFreq" cx="8" ccx="8" in="2" churn="3" amp="2">inline std::vector&lt;float&gt; churnPriorFromFreq( const IngestResult&amp; ing, const std::vector&lt;std::uint32_t&gt;&amp; freq, bool anyHistory )</d>
<d l="1202" n="churnTeleport" id="./src/gitmine.h::rw::churnTeleport" cx="4" ccx="4" in="1" churn="3" amp="1">inline std::vector&lt;float&gt; churnTeleport( const std::string&amp; root, const IngestResult&amp; ing, const char* since = &quot;18 months ago&quot;, const SinceScope* scope = nullpt…</d … [line truncated: 1 more bytes on this line]
<d l="1218" n="churnTeleportWorkspace" id="./src/gitmine.h::rw::churnTeleportWorkspace" cx="6" ccx="9" in="1" churn="3" amp="1">inline std::vector&lt;float&gt; churnTeleportWorkspace( const std::vector&lt;std::string&gt;&amp; rootDirs, const IngestResult&amp; ing, const char* since = &quot;18 months … [line truncated: 25 more bytes on this line]
</f>
… [40 more display lines; full output is 7440 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --for="tree-sitter parse of a source file" --adaptive`

*Cut the result at the relevance cliff (Adaptive-k).*

`````
<ctx task="tree-sitter parse of a source file" route=" [routed: subtoken+body BM25 (--for&apos;s default) — no strong name hit, multi-word conceptual query]">
<!-- ripwire lens for "tree-sitter parse of a source file" [routed: subtoken+body BM25 (-for's default) — no strong name hit, multi-word conceptual query] [adaptive: kept 5 of 40 - sharp cliff at rank 1 (23% drop), clamped up to the floor of 5]: reusable building blocks + quality facts for what you're about to touch (cx=complexity ccx=cognitive in=reuse-count churn=recent-commits amp=change-amplification clone=1(duplicated) tested=1) — prefer composing/reusing these; watch the high-churn/high-amp/cloned ones est_tokens="854" -->
<sigs>
<f p="./src/ingest.cpp">
<d l="66" n="tree_sitter_c" cx="1" ccx="0" in="0" churn="3">const TSLanguage* tree_sitter_c( void )</d>
<d l="285" n="jsonNestsTooDeep" cx="13" ccx="20" in="1" churn="3" amp="1">
<doc>True when raw bracket/brace nesting exceeds kMaxJsonNestDepth — degenerate or hostile DATA, never config (AUDIT5, found live by bench/multiswe: tree-sitter-json&apos;s error recovery is superlinear on un</doc>bool jsonNestsTooDeep( std::string_view bytes ) noexcept</d>
<d l="3486" n="parseTree" cx="1" ccx="0" in="1" churn="3" amp="1">TSTree* parseTree( TSParser* parser, std::string_view src )</d>
</f>
<f p="./src/mcpindex.h">
<d l="372" n="McpIndex" id="./src/mcpindex.h::McpIndex::McpIndex" cx="0" ccx="0" in="0" churn="3">
<doc>persistent in-memory index (parse once, reuse across MCP calls) ---- The MCP server is long-lived; previously every verb re-parsed the whole tree (~6.5 s each). This caches the assembled {ingest</doc>struct McpIndex</d>
</f>
<f p="./src/lintrules.h">
<d l="40" n="LintRule" id="./src/lintrules.h::LintRule::LintRule" cx="0" ccx="0" in="0" churn="3">
<doc>the parsed shape</doc>struct LintRule</d>
</f>
</sigs>
<compose>
<field name="lang" type="Lang" owner="LintRule" rel="creates"/>
<field name="g" type="Graph" owner="McpIndex" rel="creates"/>
<field name="watcher" type="FsWatcher" owner="McpIndex" rel="creates"/>
<field name="ing" type="IngestResult" owner="McpIndex" rel="creates"/>
</compose>
</ctx>
`````

## `./build/ripwire . --for="why does src/lexical.h chooseForRanker pick name-exact BM25"`

*Mention anchoring (default-on): a path and a Symbol literally named in the task get lifted; the header says what anchored.*

`````
<ctx task="why does src/lexical.h chooseForRanker pick name-exact BM25" route=" [routed: subtoken+body BM25 (--for&apos;s default) — no strong name hit, multi-word conceptual query]">
<!-- ripwire lens for "why does src/lexical.h chooseForRanker pick name-exact BM25" [routed: subtoken+body BM25 (-for's default) — no strong name hit, multi-word conceptual query] [mention anchor: 1 file + 3 symbols named in the task lifted near the top] [doc mentions: 1 doc discussing 1 top-ranked symbol surfaced]: reusable building blocks + quality facts for what you're about to touch (cx=complexity ccx=cognitive in=reuse-count churn=recent-commits amp=change-amplification clone=1(duplicated) tested=1) — prefer composing/reusing these; watch the high-churn/high-amp/cloned ones est_tokens="2934" -->
<sigs capped="1">
<f p="./src/eval.h">
<d l="120" n="printEvalRankerNote" id="./src/eval.h::rw::printEvalRankerNote" cx="1" ccx="0" in="1" churn="3" amp="1">
<doc>P11.12: the interpretive footer for --eval&apos;s ranker table, pulled into its own function so the 9…</doc>inline void printEvalRankerNote()</d>
<d l="133" n="runEval" id="./src/eval.h::rw::runEval" cx="44" ccx="66" in="1" churn="3" amp="1">inline int runEval( const std::string&amp; root, const IngestResult&amp; ing, const Graph&amp; g, const std::vector&lt;char&gt;&amp; currentDiff )</d>
<d l="177" n="fileDir" id="./src/eval.h::rw::fileDir" cx="1" ccx="0" in="0" churn="3">std::vector&lt;std::string&gt; fileDir( F )</d>
<d l="330" n="runEvalRetrieval" id="./src/eval.h::rw::runEvalRetrieval" cx="15" ccx="25" in="1" churn="3" amp="1">inline int runEvalRetrieval( const IngestResult&amp; ing, const Graph&amp; g )</d>
<d l="584" n="maxPoolToFiles" id="./src/eval.h::rw::maxPoolToFiles" cx="4" ccx="4" in="2" churn="3" amp="2">inline std::vector&lt;float&gt; maxPoolToFiles( const IngestResult&amp; ing, const std::vector&lt;float&gt;&amp; sym…</d>
<d l="626" n="runEvalMined" id="./src/eval.h::rw::runEvalMined" cx="25" ccx="38" in="1" churn="3" amp="1">inline int runEvalMined( const std::string&amp; root, const IngestResult&amp; ing, const Graph&amp; g, const std::string&amp; path )</d>
</f>
<f p="./src/lexical.h">
<d l="95" n="lexicalScoresTiered" id="./src/lexical.h::rw::lexicalScoresTiered" cx="91" ccx="256" in="5" churn="3" amp="5">inline std::vector&lt;float&gt; lexicalScoresTiered( const IngestResult&amp; ing, const std::vector&lt;std::u…</d>
<d l="457" n="lexicalScores" id="./src/lexical.h::rw::lexicalScores" cx="1" ccx="0" in="6" churn="3" amp="6">inline std::vector&lt;float&gt; lexicalScores( const IngestResult&amp; ing, const std::vector&lt;std::uint32_…</d>
<d l="481" n="lexicalScoresNameExactTiered" id="./src/lexical.h::rw::lexicalScoresNameExactTiered" cx="35" ccx="61" in="5" churn="3" amp="5">
<doc>not every builder and every graph. This variant scores the query — tokenized on WHITESPACE onl…</doc>inline std::vector&lt;float&gt; lexicalScoresNameExactTiered( const IngestResult&amp; ing, std::string_view query, const std::vector&lt;float&gt;* symbolScoreMul )</d>
<d l="581" n="lexicalScoresNameExact" id="./src/lexical.h::rw::lexicalScoresNameExact" cx="1" ccx="0" in="3" churn="3" amp="3">
<doc>the un-tiered name-exact contract (--route, evals): unchanged arity, byte-identical scores</doc>inline std::vector&lt;float&gt; lexicalScoresNameExact( const IngestResult&amp; ing, std::string_view query )</d>
<d l="637" n="chooseForRanker" id="./src/lexical.h::rw::chooseForRanker" cx="29" ccx="39" in="7" churn="3" amp="7">inline RouteChoice chooseForRanker( const IngestResult&amp; ing, std::string_view query )</d>
</f>
<f p="./src/packtask.h">
<d l="39" n="LensRanking" id="./src/packtask.h::LensRanking::LensRanking" cx="0" ccx="0" in="0" churn="3">struct LensRanking</d>
</f>
<f p="./src/main.cpp">
<d l="466" n="ExpandToken" id="./src/main.cpp::ExpandToken::ExpandToken" cx="0" ccx="0" in="0" churn="4" amp="4">struct ExpandToken</d>
<d l="1242" n="computeLensRanking" cx="37" ccx="67" in="3" churn="4" amp="7">rw::LensRanking computeLensRanking( const MainDispatch&amp; d, std::string_view task )</d>
<d l="2129" n="runTargetedViews" cx="16" ccx="32" in="1" churn="4" amp="5">std::optional&lt;int&gt; runTargetedViews( const MainDispatch&amp; d )</d>
<d l="3725" n="runEvalViews" cx="5" ccx="4" in="1" churn="4" amp="5">std::optional&lt;int&gt; runEvalViews( const MainDispatch&amp; d )</d>
<d l="4294" n="runPath" cx="14" ccx="25" in="1" churn="4" amp="5">std::optional&lt;int&gt; runPath( const MainDispatch&amp; d )</d>
… [27 more display lines; full output is 7335 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --for="why does src/lexical.h chooseForRanker pick name-exact BM25" --no-mention-boost`

*Same task with the anchor disabled — the contrast the flag exists for.*

`````
<ctx task="why does src/lexical.h chooseForRanker pick name-exact BM25" route=" [routed: subtoken+body BM25 (--for&apos;s default) — no strong name hit, multi-word conceptual query]">
<!-- ripwire lens for "why does src/lexical.h chooseForRanker pick name-exact BM25" [routed: subtoken+body BM25 (-for's default) — no strong name hit, multi-word conceptual query] [doc mentions: 1 doc discussing 1 top-ranked symbol surfaced]: reusable building blocks + quality facts for what you're about to touch (cx=complexity ccx=cognitive in=reuse-count churn=recent-commits amp=change-amplification clone=1(duplicated) tested=1) — prefer composing/reusing these; watch the high-churn/high-amp/cloned ones est_tokens="2980" -->
<sigs capped="1">
<f p="./src/eval.h">
<d l="120" n="printEvalRankerNote" id="./src/eval.h::rw::printEvalRankerNote" cx="1" ccx="0" in="1" churn="3" amp="1">
<doc>P11.12: the interpretive footer for --eval&apos;s ranker table, pulled into its own function so the 9…</doc>inline void printEvalRankerNote()</d>
<d l="133" n="runEval" id="./src/eval.h::rw::runEval" cx="44" ccx="66" in="1" churn="3" amp="1">inline int runEval( const std::string&amp; root, const IngestResult&amp; ing, const Graph&amp; g, const std::vector&lt;char&gt;&amp; currentDiff )</d>
<d l="177" n="fileDir" id="./src/eval.h::rw::fileDir" cx="1" ccx="0" in="0" churn="3">std::vector&lt;std::string&gt; fileDir( F )</d>
<d l="330" n="runEvalRetrieval" id="./src/eval.h::rw::runEvalRetrieval" cx="15" ccx="25" in="1" churn="3" amp="1">inline int runEvalRetrieval( const IngestResult&amp; ing, const Graph&amp; g )</d>
<d l="584" n="maxPoolToFiles" id="./src/eval.h::rw::maxPoolToFiles" cx="4" ccx="4" in="2" churn="3" amp="2">inline std::vector&lt;float&gt; maxPoolToFiles( const IngestResult&amp; ing, const std::vector&lt;float&gt;&amp; sym…</d>
<d l="626" n="runEvalMined" id="./src/eval.h::rw::runEvalMined" cx="25" ccx="38" in="1" churn="3" amp="1">inline int runEvalMined( const std::string&amp; root, const IngestResult&amp; ing, const Graph&amp; g, const std::string&amp; path )</d>
</f>
<f p="./src/lexical.h">
<d l="95" n="lexicalScoresTiered" id="./src/lexical.h::rw::lexicalScoresTiered" cx="91" ccx="256" in="5" churn="3" amp="5">inline std::vector&lt;float&gt; lexicalScoresTiered( const IngestResult&amp; ing, const std::vector&lt;std::u…</d>
<d l="457" n="lexicalScores" id="./src/lexical.h::rw::lexicalScores" cx="1" ccx="0" in="6" churn="3" amp="6">inline std::vector&lt;float&gt; lexicalScores( const IngestResult&amp; ing, const std::vector&lt;std::uint32_…</d>
<d l="481" n="lexicalScoresNameExactTiered" id="./src/lexical.h::rw::lexicalScoresNameExactTiered" cx="35" ccx="61" in="5" churn="3" amp="5">inline std::vector&lt;float&gt; lexicalScoresNameExactTiered( const IngestResult&amp; ing, std::string_view query, const std::vector&lt;float&gt;* symbolScoreM … [line truncated: 8 more bytes on this line]
<d l="581" n="lexicalScoresNameExact" id="./src/lexical.h::rw::lexicalScoresNameExact" cx="1" ccx="0" in="3" churn="3" amp="3">inline std::vector&lt;float&gt; lexicalScoresNameExact( const IngestResult&amp; ing, std::string_view query )</d>
<d l="637" n="chooseForRanker" id="./src/lexical.h::rw::chooseForRanker" cx="29" ccx="39" in="7" churn="3" amp="7">inline RouteChoice chooseForRanker( const IngestResult&amp; ing, std::string_view query )</d>
</f>
<f p="./src/packtask.h">
<d l="39" n="LensRanking" id="./src/packtask.h::LensRanking::LensRanking" cx="0" ccx="0" in="0" churn="3">
<doc>per-symbol lens rank + the routing/mention/co-change header note fragments — populated identic…</doc>struct LensRanking</d>
</f>
<f p="./src/main.cpp">
<d l="466" n="ExpandToken" id="./src/main.cpp::ExpandToken::ExpandToken" cx="0" ccx="0" in="0" churn="4" amp="4">struct ExpandToken</d>
<d l="1242" n="computeLensRanking" cx="37" ccx="67" in="3" churn="4" amp="7">rw::LensRanking computeLensRanking( const MainDispatch&amp; d, std::string_view task )</d>
<d l="2129" n="runTargetedViews" cx="16" ccx="32" in="1" churn="4" amp="5">std::optional&lt;int&gt; runTargetedViews( const MainDispatch&amp; d )</d>
<d l="3725" n="runEvalViews" cx="5" ccx="4" in="1" churn="4" amp="5">std::optional&lt;int&gt; runEvalViews( const MainDispatch&amp; d )</d>
<d l="4294" n="runPath" cx="14" ccx="25" in="1" churn="4" amp="5">std::optional&lt;int&gt; runPath( const MainDispatch&amp; d )</d>
<d l="7276" n="runDefaultMap" cx="100" ccx="170" in="1" churn="4" amp="5">int runDefaultMap( const MainDispatch&amp; d )</d>
… [29 more display lines; full output is 7450 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --lego=Vehicle`

*Interface -> implementors view: method contract + every existing impl.*

`````
<ctx><lego><iface n="Vehicle" p="./test/legofix/vehicle.rs" methods="0" caveat="not-extracted-for-lang" implementors="2"><impl n="Car" p="./test/legofix/vehicle.rs"/><impl n="Bike" p="./test/legofix/vehicle.rs"/></iface></lego></ctx>
`````

## `./build/ripwire . --exemplar="format byte sizes for humans"`

*The repo's best-in-class instance to imitate before writing new code (picked by ROLE).*

`````
<!-- ripwire exemplar for "format byte sizes for humans" (task -> kind=fn, low-confidence: weak match, fell back to fn): the repo's best-in-class fn to imitate — chosen by ROLE, NEVER by text similarity to your task: candidates are first filtered to cognitive complexity at or under the ccx ceiling (4x the complexity bar), then ordered non-fixture path before test-fixture path, tested before untested, higher fan-in, lower complexity, fewer lines, lowest id. low_confidence=1 marks a weak task-to-kind match that fell back to fn; over_ccx_bar=1 marks a corpus where nothing was under the ceiling, so the pick is the least bad rather than a clean one; candidates= counts the ELIGIBLE instances of the kind (post-ceiling), not every instance. On the root, the three attributes that ARE that ordering's evidence: in=reuse-count (callers), ccx=cognitive complexity, tested=1 when a test reaches it (OMITTED, never 0, when none does). Copy its shape, not its text. -->
<exemplar kind="fn" candidates="4128" n="min" p="./src/infra/fastmath.h:218" in="84" ccx="1" tested="1" low_confidence="1">
<bodies shown="1" total="1" capped="0">
<b t="fn" l="218" p="./src/infra/fastmath.h" n="min">
<![CDATA[[[nodiscard]] ALWAYS_INLINE CONST_FUNC constexpr T min( T a, T b ) noexcept { return b < a ? b : a; }]]>
</b>
</bodies>
</exemplar>
`````

## `./build/ripwire . --recall="quality delta gating exit codes"`

*Most relevant DOCS' full bodies (markdown only) — recall what is already written down.*

`````
ripwire recall — "quality delta gating exit codes" — 34 relevant of 78 document files, best-first — total=34 shown=8 capped=1 generated_demoted=1 est_tokens=52797

━━ ./skills/ripwire-quality-bar/SKILL.md  (relevance 6.211) ━━
---
name: ripwire-quality-bar
description: >
  The code-QUALITY bar for what you just wrote — not merge-safety. Needs NO setup: right before you commit /
  open a PR / tell the user it's finished, run `ripwire <dir> --quality-delta` — reports ONLY what you made
  WORSE across 10 measured kinds (complexity, verbosity, nesting, params, duplication, dead-code,
  API-surface, error-masking, short-horizon-churn, new-clone-of-reused-helper — the measured agent-code
  failure modes), exiting non-zero on new debt. Fix the real regressions, re-run, converge. Reach for this at
  every "I think this is done" moment on non-trivial work. For merge-safety / blast-radius / tests-to-run →
  **ripwire-change-check** instead (this skill judges the code, not whether it's safe to merge). Backed by
  ripwire (deterministic, on PATH).
allowed-tools: Bash, Read
---

# The quality-bar convergence loop

> Routing:
> • PR-submission readiness — tests to run, blast radius, "safe to merge?" → **ripwire-change-check** — run
>   `--quality-delta` FIRST, then its `--test-gate`: clean code that runs the wrong tests still regresses.
> • Reusing before you write the code in the first place → **ripwire-reuse-first**.
> • Not sure which skill? → **ripwire-router**.

Don't eyeball quality — **measure the delta your change introduced**, with a deterministic oracle, in a
bounded loop. A file that was already complex is not your regression.

## The loop
1. **Zero-setup path:** just make your change, then run `ripwire <dir> --quality-delta` before you call it
… [1870 more lines, 135141 bytes total]
`````

## `./build/ripwire . --tree`

*File-by-file orientation map (top symbols per file).*

`````
<!-- ripwire tree: each file + its top symbols by rank, files ordered by their best symbol's rank (path breaks ties) — a session-start orientation map. files= is the indexed corpus; rows list files WITH symbols; files_unlisted= holds the symbol-less remainder — files equals files_unlisted plus the LISTABLE file set, which is what the rows below enumerate before any paging window is applied; under explicit paging (limit=/offset=) that listable count is emitted as total= and shown= says how many of it these rows are -->
<tree files="836" files_unlisted="15">
<file p="./src/svector.h" symbols="17">
<s t="method" n="size"/>
<s t="method" n="push_back"/>
<s t="method" n="buf"/>
</file>
<file p="./src/scipoverlay.h" symbols="6">
<s t="method" n="empty"/>
<s t="method" n="targetsOf"/>
<s t="method" n="isPrecise"/>
</file>
<file p="./src/notes.h" symbols="23">
<s t="method" n="empty"/>
<s t="method" n="find"/>
<s t="fn" n="sortNotes"/>
</file>
<file p="./src/infra/fastmath.h" symbols="120">
<s t="fn" n="max"/>
<s t="fn" n="min"/>
<s t="fn" n="cpuRelax"/>
</file>
<file p="./src/ingest.cpp" symbols="204">
<s t="method" n="find"/>
<s t="fn" n="finalSegment"/>
<s t="method" n="u32"/>
</file>
<file p="./src/hashutil.h" symbols="2">
<s t="fn" n="fnv1aMultiply"/>
<s t="fn" n="multiplyModulo64"/>
… [3642 more display lines; full output is 100674 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --html=/var/folders/_7/1b0h5mxs3vl2jgb9jk3qzw7r0000gn/T/ripwire_showcase_fxbqqxez/aux/map2.html`

*Self-contained HTML force-directed call graph.*

`````
(empty)
`````

Artifact written:

`````
-rw-r--r--@ 1 qgames  staff  52090 Jul 31 20:15 /var/folders/_7/1b0h5mxs3vl2jgb9jk3qzw7r0000gn/T/ripwire_showcase_fxbqqxez/aux/map2.html
`````

## `./build/ripwire . --order=stable --top-k=5`

*Stable (path/id) emit order — provider KV-cache hits across re-runs.*

`````
<!-- ripwire v1 t=fn|method|cls|struct|iface|var|sec p=path layer=arch-layer(opt) n=name id=canonical(path::scope::name,when-scoped) k=rank c=call amb=ambiguous-calls(read-source) overloads=N-same-name-defs-merged-into-this-row(absent-if-1;shown=counts-them-individually,so-rows+sum(overloads-1)=shown) prov=scip(precise;else name-based) hdr:unresolved=call-name-defined-only-in-a-lang-incompatible-file (edges heuristic) r:est_tokens=hdr-copy(none-if-stable) -->
<r>
<f p="./src/scipoverlay.h">
<s t="method" n="empty" id="./src/scipoverlay.h::ScipOverlay::empty">
</s>
</f>
<f p="./src/svector.h">
<s t="method" n="buf" id="./src/svector.h::svector::buf" overloads="2">
</s>
<s t="method" n="push_back" id="./src/svector.h::svector::push_back" amb="2">
<c n="buf"/>
<c n="buf"/>
<c n="grow"/>
</s>
<s t="method" n="size" id="./src/svector.h::svector::size">
</s>
</f>
</r>
<!-- files=836 symbols=6432 edges=8733 shown=5 est_tokens=400 ambiguous=2631 unresolved=652 precise=3 skipped_oversize=3 order=stable -->
`````


---

# navigate / answer a question

## `./build/ripwire . --around=rankGraphTeleport`

*Ego graph around one symbol.*

`````
<!-- ripwire v1 t=fn|method|cls|struct|iface|var|sec p=path layer=arch-layer(opt) n=name id=canonical(path::scope::name,when-scoped) k=rank c=call amb=ambiguous-calls(read-source) overloads=N-same-name-defs-merged-into-this-row(absent-if-1;shown=counts-them-individually,so-rows+sum(overloads-1)=shown) prov=scip(precise;else name-based) hdr:unresolved=call-name-defined-only-in-a-lang-incompatible-file (edges heuristic) r:est_tokens=hdr-copy(none-if-stable) -->
<!-- files=836 symbols=6432 edges=8733 shown=147 est_tokens=17785 ambiguous=2631 unresolved=652 precise=3 skipped_oversize=3 order=important-first -->
<r est_tokens="17785">
<f p="./src/graph.h">
<s t="fn" n="rankGraphTeleport" id="./src/graph.h::rw::rankGraphTeleport" amb="5" k="1.0000">
<c n="biasPrior"/>
<c n="pageRankDouble"/>
<c n="size"/>
<c n="begin"/>
<c n="end"/>
<c n="begin"/>
<c n="end"/>
</s>
<s t="fn" n="biasPrior" id="./src/graph.h::rw::biasPrior" k="0.5000">
<c n="size"/>
</s>
<s t="fn" n="rankGraph" id="./src/graph.h::rw::rankGraph" k="0.5000">
<c n="rankGraphTeleport"/>
<c n="size"/>
</s>
<s t="fn" n="anchoredLexicalRank" id="./src/graph.h::rw::anchoredLexicalRank" amb="3" k="0.5000">
<c n="rankGraphTeleport"/>
<c n="blendMaxNorm"/>
<c n="min"/>
<c n="empty"/>
<c n="size"/>
<c n="begin"/>
<c n="end"/>
<c n="begin"/>
<c n="end"/>
… [1968 more display lines; full output is 44088 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --callers=rankGraphTeleport`

*Who calls SYM (1-hop in-edges).*

`````
<!-- ripwire callers/callees: the 1-hop call hierarchy read straight off the call graph. The callers form lists the symbols that CALL of=; the callees form lists the symbols of= itself calls. of= is the selector you passed, defs= how many DEFINITIONS that name resolved to (the rows UNION every def's neighbours), and count= the number of DISTINCT neighbour symbols (a floor, per counts_floor=), which the rows window with limit= and offset=. counts_floor="1" means every count on this element is a FLOOR, never a total. Call edges are extracted from source text by NAME, so a call that reaches its target through dynamic dispatch (a virtual, interface or duck-typed receiver), a callback or function pointer, a macro-generated call site, or a declaration that parses without a call expression (C++ most-vexing-parse) contributes no edge and is missing here. Read a zero as "none found", never as "none exists". COUNTING UNIT, and it differs by verb — which is why two of them report different numbers for one symbol. The callers, callees, edit-check, graph-query and pr-context counts are DISTINCT SYMBOLS: repeated calls from one caller, and calls to two overloads of one name, collapse into ONE row, their multiplicity surviving only in the call graph's edge weight. The reach counts (impact's reaches=, pr-context's dependents=) are the size of a transitive reach SET, each symbol counted once — not a count of calls or edges. The uses verb counts call SITES, one row per occurrence, so a larger count= there for the same symbol is these units agreeing, not disagreeing. The map header's edges= is a unit again different — distinct (caller,callee) PAIRS — and that document carries neither this marker nor this clause, so its numbers answer a different question. -->
<callers of="rankGraphTeleport" defs="1" count="6" counts_floor="1">
<s t="fn" n="runEval" p="./src/eval.h:133"/>
<s t="fn" n="rankGraph" p="./src/graph.h:1304"/>
<s t="fn" n="anchoredLexicalRank" p="./src/graph.h:1553"/>
<s t="fn" n="churnRankedGraph" p="./src/main.cpp:7246"/>
<s t="fn" n="runDefaultMap" p="./src/main.cpp:7276"/>
<s t="fn" n="getIndex" p="./src/mcpindex.h:734"/>
</callers>
`````

## `./build/ripwire . --callers=DoesNotExist`

*Unknown-symbol failure shape.*

**exit code: 1**

`````
(empty)
`````

stderr:

`````
ripwire: --callers symbol not found: DoesNotExist
`````

## `./build/ripwire . --callees=rankGraphTeleport`

*What SYM calls (1-hop out-edges).*

`````
<!-- ripwire callers/callees: the 1-hop call hierarchy read straight off the call graph. The callers form lists the symbols that CALL of=; the callees form lists the symbols of= itself calls. of= is the selector you passed, defs= how many DEFINITIONS that name resolved to (the rows UNION every def's neighbours), and count= the number of DISTINCT neighbour symbols (a floor, per counts_floor=), which the rows window with limit= and offset=. counts_floor="1" means every count on this element is a FLOOR, never a total. Call edges are extracted from source text by NAME, so a call that reaches its target through dynamic dispatch (a virtual, interface or duck-typed receiver), a callback or function pointer, a macro-generated call site, or a declaration that parses without a call expression (C++ most-vexing-parse) contributes no edge and is missing here. Read a zero as "none found", never as "none exists". COUNTING UNIT, and it differs by verb — which is why two of them report different numbers for one symbol. The callers, callees, edit-check, graph-query and pr-context counts are DISTINCT SYMBOLS: repeated calls from one caller, and calls to two overloads of one name, collapse into ONE row, their multiplicity surviving only in the call graph's edge weight. The reach counts (impact's reaches=, pr-context's dependents=) are the size of a transitive reach SET, each symbol counted once — not a count of calls or edges. The uses verb counts call SITES, one row per occurrence, so a larger count= there for the same symbol is these units agreeing, not disagreeing. The map header's edges= is a unit again different — distinct (caller,callee) PAIRS — and that document carries neither this marker nor this clause, so its numbers answer a different question. -->
<callees of="rankGraphTeleport" defs="1" count="7" counts_floor="1">
<s t="fn" n="biasPrior" p="./src/graph.h:1263"/>
<s t="fn" n="pageRankDouble" p="./src/pagerank.cpp:34"/>
<s t="method" n="size" p="./src/svector.h:77"/>
<s t="method" n="begin" p="./src/svector.h:79"/>
<s t="method" n="end" p="./src/svector.h:80"/>
<s t="method" n="begin" p="./src/svector.h:81"/>
<s t="method" n="end" p="./src/svector.h:82"/>
</callees>
`````

## `./build/ripwire . --uses=rankGraphTeleport`

*The resolvable use-sites (call/read/write/import/extends) with file:line; count= is a floor.*

`````
<!-- ripwire uses: the STATICALLY RESOLVABLE use-sites of SYM (role=call|read|write|import|extends; p=file:line) — a floor, see counts_floor below. Reference-name-based (same heuristic level as call edges) — verify in source if a name is overloaded. external="1" ⇒ SYM has no definition in the indexed tree under ANY spelling (stdlib/third-party) — never merely none in the file you qualified with (that spelling refuses instead). A "file:name" SYM narrows defs= AND the role="call" sites, which are kept only where the call RESOLVES to a chosen def (the callers verb's own narrowing, read the other way, so the two agree); read/write/import/extends carry no resolution and stay name-matched across every def sharing the name. narrowed_roles= names what narrowed, and defs_of_name=/call_sites_of_name= (file: qualifier only) are the un-narrowed totals. counts_floor="1" means every count on this element is a FLOOR, never a total. Call edges are extracted from source text by NAME, so a call that reaches its target through dynamic dispatch (a virtual, interface or duck-typed receiver), a callback or function pointer, a macro-generated call site, or a declaration that parses without a call expression (C++ most-vexing-parse) contributes no edge and is missing here. Read a zero as "none found", never as "none exists". COUNTING UNIT, and it differs by verb — which is why two of them report different numbers for one symbol. The callers, callees, edit-check, graph-query and pr-context counts are DISTINCT SYMBOLS: repeated calls from one caller, and calls to two overloads of one name, collapse into ONE row, their multiplicity surviving only in the call graph's edge weight. The reach counts (impact's reaches=, pr-context's dependents=) are the size of a transitive reach SET, each symbol counted once — not a count of calls or edges. The uses verb counts call SITES, one row per occurrence, so a larger count= there for the same symbol is these units agreeing, not disagreeing. The map header's edges= is a unit again different — distinct (caller,callee) PAIRS — and that document carries neither this marker nor this clause, so its numbers answer a different question. -->
<uses of="rankGraphTeleport" defs="1" external="0" count="7" counts_floor="1">
<u role="call" p="./src/eval.h:211" in_id="./src/eval.h::rw::runEval"/>
<u role="call" p="./src/graph.h:1307" in_id="./src/graph.h::rw::rankGraph"/>
<u role="call" p="./src/graph.h:1575" in_id="./src/graph.h::rw::anchoredLexicalRank"/>
<u role="call" p="./src/main.cpp:7262" in_id="churnRankedGraph"/>
<u role="call" p="./src/main.cpp:7270" in_id="churnRankedGraph"/>
<u role="call" p="./src/main.cpp:7348" in_id="runDefaultMap"/>
<u role="call" p="./src/mcpindex.h:807" in_id="./src/mcpindex.h::rw::getIndex"/>
</uses>
`````

## `./build/ripwire . --graph-query='and(callers(name("rankGraphTeleport"),2),kind(all,fn))'`

*Composable node-set query: functions within 2 caller-hops of rankGraphTeleport.*

`````
<!-- ripwire graph-query: a fixed-operator node-set query over the call graph (sources name/all; filters kind/cx/fanin/file; bounded closure callers/callees; joins and/or/not), ranked by importance + capped at the top-k limit (default 200); narrow the query or raise top-k for more. NOT Datalog. counts_floor="1" means every count on this element is a FLOOR, never a total. Call edges are extracted from source text by NAME, so a call that reaches its target through dynamic dispatch (a virtual, interface or duck-typed receiver), a callback or function pointer, a macro-generated call site, or a declaration that parses without a call expression (C++ most-vexing-parse) contributes no edge and is missing here. Read a zero as "none found", never as "none exists". COUNTING UNIT, and it differs by verb — which is why two of them report different numbers for one symbol. The callers, callees, edit-check, graph-query and pr-context counts are DISTINCT SYMBOLS: repeated calls from one caller, and calls to two overloads of one name, collapse into ONE row, their multiplicity surviving only in the call graph's edge weight. The reach counts (impact's reaches=, pr-context's dependents=) are the size of a transitive reach SET, each symbol counted once — not a count of calls or edges. The uses verb counts call SITES, one row per occurrence, so a larger count= there for the same symbol is these units agreeing, not disagreeing. The map header's edges= is a unit again different — distinct (caller,callee) PAIRS — and that document carries neither this marker nor this clause, so its numbers answer a different question. -->
<query expr="and(callers(name(&quot;rankGraphTeleport&quot;),2),kind(all,fn))" count="44" shown="44" capped="0" counts_floor="1">
<s t="fn" n="getIndex" p="./src/mcpindex.h:734"/>
<s t="fn" n="emitCommunitiesReport" p="./src/main.cpp:5794"/>
<s t="fn" n="emitCommunityDrill" p="./src/main.cpp:5916"/>
<s t="fn" n="anchoredLexicalRank" p="./src/graph.h:1553"/>
<s t="fn" n="rankGraph" p="./src/graph.h:1304"/>
<s t="fn" n="computeLensRanking" p="./src/main.cpp:1242"/>
<s t="fn" n="dispatchMcpLine" p="./src/mcp.h:304"/>
<s t="fn" n="runEvalRetrieval" p="./src/eval.h:330"/>
<s t="fn" n="runEvalMined" p="./src/eval.h:626"/>
<s t="fn" n="symbolQueryJson" p="./src/mcpverbs.h:394"/>
<s t="fn" n="anchoredFileScore" p="./src/eval.h:93"/>
<s t="fn" n="analyzeToString" p="./src/mcpverbs.h:308"/>
<s t="fn" n="grepHitsJson" p="./src/mcpverbs.h:456"/>
<s t="fn" n="cochangePartnersJson" p="./src/mcpverbs.h:505"/>
<s t="fn" n="mentionsJson" p="./src/mcpverbs.h:673"/>
<s t="fn" n="forTaskText" p="./src/mcpverbs.h:707"/>
<s t="fn" n="legoText" p="./src/mcpverbs.h:888"/>
<s t="fn" n="ownersText" p="./src/mcpverbs.h:921"/>
<s t="fn" n="exemplarText" p="./src/mcpverbs.h:1016"/>
<s t="fn" n="impactText" p="./src/mcpverbs.h:1085"/>
<s t="fn" n="usesText" p="./src/mcpverbs.h:1198"/>
<s t="fn" n="pathText" p="./src/mcpverbs.h:1266"/>
<s t="fn" n="fetchBody" p="./src/mcpverbs.h:2096"/>
<s t="fn" n="churnRankedGraph" p="./src/main.cpp:7246"/>
<s t="fn" n="runEditVerb" p="./src/mcpedit.h:300"/>
<s t="fn" n="runBatchSub" p="./src/mcpverbs.h:2381"/>
<s t="fn" n="flagsText" p="./src/mcpverbs.h:361"/>
<s t="fn" n="flipText" p="./src/mcpverbs.h:373"/>
… [17 more display lines; full output is 4079 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --external-surface`

*Names referenced but never defined in-corpus (stdlib/third-party surface). NOW carries names/shown/capped (total= joins them only under --limit/--offset).*

`````
<!-- ripwire external-surface: names CALLED/IMPORTED/EXTENDED but never defined in the indexed tree = the stdlib/third-party surface the code depends on (refs=use-sites, calls=of-which-calls) -->
<external-surface names="940" shown="940" capped="0">
<x n="grep" lang="sh" refs="3973" calls="3973"/>
<x n="printf" lang="sh" refs="3507" calls="3507"/>
<x n="echo" lang="sh" refs="3245" calls="3245"/>
<x n="exit" lang="sh" refs="1111" calls="1111"/>
<x n="git" lang="sh" refs="917" calls="917"/>
<x n="head" lang="sh" refs="851" calls="851"/>
<x n="cat" lang="sh" refs="762" calls="762"/>
<x n="cd" lang="sh" refs="692" calls="692"/>
<x n="c_str" lang="cpp" refs="625" calls="625"/>
<x n="tr" lang="sh" refs="611" calls="611"/>
<x n="fprintf" lang="cpp" refs="610" calls="610"/>
<x n="string" lang="cpp" refs="471" calls="471"/>
<x n="python3" lang="sh" refs="427" calls="427"/>
<x n="substr" lang="cpp" refs="419" calls="419"/>
<x n="printf" lang="cpp" refs="398" calls="398"/>
<x n="mkdir" lang="sh" refs="372" calls="372"/>
<x n="sed" lang="sh" refs="368" calls="368"/>
<x n="mktemp" lang="sh" refs="366" calls="366"/>
<x n="command" lang="sh" refs="359" calls="359"/>
<x n="set" lang="sh" refs="334" calls="334"/>
<x n="dirname" lang="sh" refs="331" calls="331"/>
<x n="pwd" lang="sh" refs="318" calls="318"/>
<x n="diff" lang="sh" refs="316" calls="316"/>
<x n="trap" lang="sh" refs="303" calls="303"/>
<x n="uint32_t" lang="cpp" refs="290" calls="290"/>
<x n="wc" lang="sh" refs="289" calls="289"/>
<x n="xmllint" lang="sh" refs="288" calls="288"/>
<x n="strcmp" lang="cpp" refs="279" calls="279"/>
… [913 more display lines; full output is 44666 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --path=main,rankGraphTeleport`

*Shortest directed call-path SRC -> DST. CHANGED: now reports from_p/to_p/from_defs and resolves the right `main` (was reachable="0").*

`````
<path from="main" to="rankGraphTeleport" from_p="./src/main.cpp:8007" to_p="./src/graph.h:1278" from_defs="43" to_defs="1" reachable="1" hops="2">
<s t="fn" n="main" p="./src/main.cpp:8007"/>
<s t="fn" n="runDefaultMap" p="./src/main.cpp:7276"/>
<s t="fn" n="rankGraphTeleport" p="./src/graph.h:1278"/>
</path>
`````

## `./build/ripwire . --connect=rankGraphTeleport,runEval,getIndex`

*Minimal connecting subgraph over 3 symbols (finds shared-caller joins).*

`````
<!-- ripwire connect: minimal joining subgraph over N task symbols (metric-closure 2-approx Steiner; search is undirected so SHARED-CALLER joins are found, every <e f= t=/> keeps its TRUE caller->callee direction; graph-structured navigation per CodeCompass, arXiv 2602.20048). Call edges are name-based: dynamic dispatch / callbacks may hide connections -->
<connect terminals="3" nodes="3" edges="2" radius="6" groups="1" est_tokens="287">
<g terminals="3">
<t n="runEval" t="fn" p="./src/eval.h:133"/>
<t n="rankGraphTeleport" t="fn" p="./src/graph.h:1278"/>
<t n="getIndex" t="fn" p="./src/mcpindex.h:734"/>
<e f="runEval" t="rankGraphTeleport"/>
<e f="getIndex" t="rankGraphTeleport"/>
</g>
</connect>
`````

## `./build/ripwire . --impact=rankGraphTeleport`

*Transitive blast radius — everything that reaches SYM. NOW carries shown/capped.*

`````
<!-- ripwire impact: transitive blast radius — symbols that reach SYM via calls (review before changing SYM). raise the default cap with limit=N (offset=M pages); on the root, limit="0" means no explicit limit was given and the verb's own default page size shaped the window — never a zero-row page. counts_floor="1" means every count on this element is a FLOOR, never a total. Call edges are extracted from source text by NAME, so a call that reaches its target through dynamic dispatch (a virtual, interface or duck-typed receiver), a callback or function pointer, a macro-generated call site, or a declaration that parses without a call expression (C++ most-vexing-parse) contributes no edge and is missing here. Read a zero as "none found", never as "none exists". COUNTING UNIT, and it differs by verb — which is why two of them report different numbers for one symbol. The callers, callees, edit-check, graph-query and pr-context counts are DISTINCT SYMBOLS: repeated calls from one caller, and calls to two overloads of one name, collapse into ONE row, their multiplicity surviving only in the call graph's edge weight. The reach counts (impact's reaches=, pr-context's dependents=) are the size of a transitive reach SET, each symbol counted once — not a count of calls or edges. The uses verb counts call SITES, one row per occurrence, so a larger count= there for the same symbol is these units agreeing, not disagreeing. The map header's edges= is a unit again different — distinct (caller,callee) PAIRS — and that document carries neither this marker nor this clause, so its numbers answer a different question. -->
<impact of="rankGraphTeleport" defs="1" reaches="50" shown="40" capped="1" counts_floor="1">
<s t="fn" n="getIndex" p="./src/mcpindex.h:734"/>
<s t="fn" n="emitCommunitiesReport" p="./src/main.cpp:5794"/>
<s t="fn" n="emitCommunityDrill" p="./src/main.cpp:5916"/>
<s t="fn" n="anchoredLexicalRank" p="./src/graph.h:1553"/>
<s t="fn" n="rankGraph" p="./src/graph.h:1304"/>
<s t="fn" n="computeLensRanking" p="./src/main.cpp:1242"/>
<s t="fn" n="dispatchMcpLine" p="./src/mcp.h:304"/>
<s t="fn" n="runEvalRetrieval" p="./src/eval.h:330"/>
<s t="fn" n="runEvalMined" p="./src/eval.h:626"/>
<s t="fn" n="symbolQueryJson" p="./src/mcpverbs.h:394"/>
<s t="fn" n="anchoredFileScore" p="./src/eval.h:93"/>
<s t="fn" n="analyzeToString" p="./src/mcpverbs.h:308"/>
<s t="fn" n="grepHitsJson" p="./src/mcpverbs.h:456"/>
<s t="fn" n="cochangePartnersJson" p="./src/mcpverbs.h:505"/>
<s t="fn" n="mentionsJson" p="./src/mcpverbs.h:673"/>
<s t="fn" n="forTaskText" p="./src/mcpverbs.h:707"/>
<s t="fn" n="legoText" p="./src/mcpverbs.h:888"/>
<s t="fn" n="ownersText" p="./src/mcpverbs.h:921"/>
<s t="fn" n="exemplarText" p="./src/mcpverbs.h:1016"/>
<s t="fn" n="impactText" p="./src/mcpverbs.h:1085"/>
<s t="fn" n="usesText" p="./src/mcpverbs.h:1198"/>
<s t="fn" n="pathText" p="./src/mcpverbs.h:1266"/>
<s t="fn" n="fetchBody" p="./src/mcpverbs.h:2096"/>
<s t="fn" n="churnRankedGraph" p="./src/main.cpp:7246"/>
<s t="fn" n="runEditVerb" p="./src/mcpedit.h:300"/>
<s t="fn" n="runBatchSub" p="./src/mcpverbs.h:2381"/>
<s t="fn" n="flagsText" p="./src/mcpverbs.h:361"/>
<s t="fn" n="flipText" p="./src/mcpverbs.h:373"/>
… [13 more display lines; full output is 3856 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --mentions=rankGraphTeleport`

*Markdown docs that name SYM in a backtick (doc<->code edges).*

`````
<!-- ripwire mentions: markdown FILES that name this symbol in a `backtick` (doc<->code; NOT a call edge). docs= is the row count (distinct files); sections= counts the underlying markdown-section mentions before file-collapse (docs <= sections). Each row's mentions= is its own section-mention count. No line locator: the doc edge is stored at file granularity — a fabricated always-1 l= was removed; absent beats fake -->
<mentions of="rankGraphTeleport" defs="1" docs="0" sections="0">
</mentions>
`````

## `./build/ripwire . --affected=src/graph.h`

*Test files that transitively reach the changed file.*

`````
<!-- ripwire affected: test files that transitively reach the changed files/symbols (run these); seeded_by= says which reading the argument took. script_gates_unmodelled= counts test/*.sh runners in the corpus (a path count; not every one invokes the binary) — script-to-binary edges are NOT modelled, so those gates are invisible to this walk and never counted in tests=/reached= -->
<affected changed="src/graph.h" seeded_by="file" seeds="88" tests="6" reached="422" script_gates_unmodelled="331">
<test p="./test/cloneband_harness.cpp" run="bash test/clonebandcheck.sh"/>
<test p="./test/clonelex_harness.cpp" run="bash test/clonelexcheck.sh"/>
<test p="./test/connectcore_harness.cpp" run="bash test/connectcorecheck.sh"/>
<test p="./test/includeprecise_unit.cpp" run="bash test/includeprecisecheck.sh"/>
<test p="./test/rustimport_unit.cpp" run="bash test/rustimportprecisecheck.sh"/>
<test p="./test/type3clone_harness.cpp" run="bash test/type3clonecheck.sh"/>
</affected>
`````

## `./build/ripwire . --situ`

*Mid-task situational report for the current git diff — on a CLEAN tree (contrast with the sandbox run below).*

`````
ripwire situational-awareness — 3 changed file(s), 96 symbols in them
  [1] blast radius: 18 symbols across 5 files transitively depend on these changes
        ./bench/cppbench/run_cppbench.py  (5 dependent symbols)
        ./bench/multiswe/run_multiswe.py  (5 dependent symbols)
        ./bench/locbench/run_locbench.py  (3 dependent symbols)
        ./bench/mine_traces.py  (3 dependent symbols)
        ./src/main.cpp  (2 dependent symbols)
  [2] tests to run (0): (none transitively reach these files)
        (331 test/*.sh gates are NOT modelled: script-to-binary edges are not call edges, so they never appear here — a path count, not every one invokes the binary)
  [3] co-change — usually edited with these but NOT in your diff (0):
        (none, or no git history)
`````

## `./build/ripwire . --test-gate`

*Pre-PR gate on a CLEAN tree: no obligations, exit 0.*

**exit code: 4**

`````
<!-- ripwire test-gate (TDAD-parity, arXiv 2603.17973): the tests to run for this change + the UNTESTED blast radius. A queryable call-graph+test map cut agent-caused regressions -70% (6.08%->1.82%); this gate names the obligations, the agent runs the tests then relies on green. exit 4 if tests OR untested is non-empty. TWO INDEPENDENT LISTINGS, each with its own row count: shown_tests= counts the <t> tests-to-run rows and shown_untested= counts the <u> blast-radius rows (a single shown= could only ever have described one of them). The <t> rows are the COMPLETE obligation and are never windowed, so they REPEAT VERBATIM on every page — a walker that concatenates pages must take them from one page only; offset=/limit= window the <u> rows alone. The <u> listing shows 25 rows by default: raise the default cap with limit=N (offset=M pages). script_gates_unmodelled= counts test/*.sh runners in the corpus (a path count; not every one invokes the binary) - script-to-binary edges are NOT modelled, so those gates are invisible to this walk and never counted in tests=. UNIT: untested= here counts impacted SYMBOLS. The seams verb spells untested= over cross-directory call EDGES and the flip verb over the defs a gate lights, so the three numbers count three different things and must never be compared or summed across verbs. -->
<test-gate changed="3" impacted="18" tests="0" untested="18" shown_tests="0" tests_capped="0" shown_untested="18" untested_capped="0" script_gates_unmodelled="331" at="1dc07e27a+dirty">
<u sym="main" p="./src/main.cpp" ccx="376"/>
<u sym="main" p="./bench/locbench/run_locbench.py" ccx="113"/>
<u sym="main" p="./bench/multiswe/run_multiswe.py" ccx="65"/>
<u sym="main" p="./bench/cppbench/run_cppbench.py" ccx="57"/>
<u sym="mine_session_file" p="./bench/mine_traces.py" ccx="44"/>
<u sym="runPath" p="./src/main.cpp" ccx="25"/>
<u sym="parse_ranked" p="./bench/locbench/run_locbench.py" ccx="19"/>
<u sym="main" p="./bench/mine_traces.py" ccx="17"/>
<u sym="mine_instances" p="./bench/cppbench/run_cppbench.py" ccx="15"/>
<u sym="gold_from_fix_patch" p="./bench/multiswe/run_multiswe.py" ccx="14"/>
<u sym="record_edit" p="./bench/mine_traces.py" ccx="12"/>
<u sym="classify_row" p="./bench/multiswe/run_multiswe.py" ccx="12"/>
<u sym="classify_commit" p="./bench/cppbench/run_cppbench.py" ccx="10"/>
<u sym="load_or_mine_lock" p="./bench/multiswe/run_multiswe.py" ccx="10"/>
<u sym="mine_lang" p="./bench/multiswe/run_multiswe.py" ccx="10"/>
<u sym="derive_gold_funcs" p="./bench/cppbench/run_cppbench.py" ccx="9"/>
<u sym="load_or_mine_lock" p="./bench/cppbench/run_cppbench.py" ccx="7"/>
<u sym="ranked_files_from_candidates" p="./bench/locbench/run_locbench.py" ccx="3"/>
</test-gate>
`````

## `./build/ripwire . --grep=DEGRADED_PATH_ALERT`

*Literal trigram-indexed search. CHANGED: each hit now carries the MATCHED line in <m>, plus shown/capped/hits_capped.*

`````
<!-- ripwire grep: parallel literal/regex scan; each hit carries its matched line (m) and enclosing symbol (in=, a NAME here; the same spelling is a fan-in COUNT in for/pack-task/exemplar). ORDER: SOURCE files before test/bench files before docs, then path and line. shown=/capped= = rows printed vs found; hits_capped="1" ⇒ hits= is a FLOOR (collection budget reached). raise the default cap with limit=N (offset=M pages); on the root, limit="0" means no explicit limit was given and the verb's own default page size shaped the window — never a zero-row page -->
<grep pattern="DEGRADED_PATH_ALERT" files="59" hits="221" shown="100" capped="1" hits_capped="0">
<hit p="./src/abicheck.h:107" in="">
<m>
<![CDATA[#include "Diagnostics.h"    // VERIFY / DEGRADED_PATH_ALERT]]>
</m>
</hit>
<hit p="./src/abicheck.h:421" in="abicheck::collectAuthoredSites">
<m>
<![CDATA[            DEGRADED_PATH_ALERT( "abi: no merge-base for a ref (unrelated history?) — that ref is counted, not compared" );]]>
</m>
</hit>
<hit p="./src/arch.h:31" in="">
<m>
<![CDATA[#include "Diagnostics.h"   // DEGRADED_PATH_ALERT — graceful-degrade on a malformed path-regex (never throw at match time)]]>
</m>
</hit>
<hit p="./src/arch.h:286" in="rw::parseArchRules">
<m>
<![CDATA[        DEGRADED_PATH_ALERT( "arch: malformed rules line — rules file rejected" );]]>
</m>
</hit>
<hit p="./src/arch.h:332" in="rw::parseArchRules">
<m>
<![CDATA[                catch( const std::regex_error& ) { pr.bad = true; DEGRADED_PATH_ALERT( "arch: malformed FROM path-regex — rule skipped" ); }]]>
</m>
</hit>
<hit p="./src/clones.h:10" in="">
<m>
<![CDATA[#include "Diagnostics.h"   // DEGRADED_PATH_ALERT — graceful-degrade on the Type-3 pair-cap guard (never throw)]]>
… [473 more display lines; full output is 19167 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --grep=DEGRADED_PATH_ALERT --grep-context=1`

*Same search with one line of source context either side.*

`````
<!-- ripwire grep: parallel literal/regex scan; each hit carries its matched line (m) and enclosing symbol (in=, a NAME here; the same spelling is a fan-in COUNT in for/pack-task/exemplar). ORDER: SOURCE files before test/bench files before docs, then path and line. shown=/capped= = rows printed vs found; hits_capped="1" ⇒ hits= is a FLOOR (collection budget reached). raise the default cap with limit=N (offset=M pages); on the root, limit="0" means no explicit limit was given and the verb's own default page size shaped the window — never a zero-row page -->
<grep pattern="DEGRADED_PATH_ALERT" files="59" hits="221" shown="100" capped="1" hits_capped="0">
<hit p="./src/abicheck.h:107" in="">
<b>
<![CDATA[#include "serialize.h"      // escapeXml]]>
</b>
<m>
<![CDATA[#include "Diagnostics.h"    // VERIFY / DEGRADED_PATH_ALERT]]>
</m>
</hit>
<hit p="./src/abicheck.h:421" in="abicheck::collectAuthoredSites">
<b>
<![CDATA[        {]]>
</b>
<m>
<![CDATA[            DEGRADED_PATH_ALERT( "abi: no merge-base for a ref (unrelated history?) — that ref is counted, not compared" );]]>
</m>
<a>
<![CDATA[            ++result.unrelated;]]>
</a>
</hit>
<hit p="./src/arch.h:31" in="">
<b>
<![CDATA[#include "model.h"]]>
</b>
<m>
<![CDATA[#include "Diagnostics.h"   // DEGRADED_PATH_ALERT — graceful-degrade on a malformed path-regex (never throw at match time)]]>
</m>
<a>
<![CDATA[#include "hashutil.h"      // sanitizer-clean modulo-2^64 FNV multiplication]]>
… [1031 more display lines; full output is 30523 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --regex='fnv1a\w+'`

*Regex search + enclosing symbol.*

`````
<!-- ripwire grep: parallel literal/regex scan; each hit carries its matched line (m) and enclosing symbol (in=, a NAME here; the same spelling is a fan-in COUNT in for/pack-task/exemplar). ORDER: SOURCE files before test/bench files before docs, then path and line. shown=/capped= = rows printed vs found; hits_capped="1" ⇒ hits= is a FLOOR (collection budget reached). raise the default cap with limit=N (offset=M pages); on the root, limit="0" means no explicit limit was given and the verb's own default page size shaped the window — never a zero-row page -->
<grep pattern="fnv1a\w+" files="24" hits="112" shown="100" capped="1" hits_capped="0">
<hit p="./src/arch.h:406" in="rw::fnv1a64">
<m>
<![CDATA[inline std::uint64_t fnv1a64( std::string_view s ) noexcept]]>
</m>
</hit>
<hit p="./src/arch.h:409" in="rw::fnv1a64">
<m>
<![CDATA[    for( unsigned char c : s ) { h ^= c; h = hashutil::fnv1aMultiply( h ); }]]>
</m>
</hit>
<hit p="./src/arch.h:464" in="rw::archViolHash">
<m>
<![CDATA[        for( unsigned char c : sv ) { h ^= c; h = hashutil::fnv1aMultiply( h ); }]]>
</m>
</hit>
<hit p="./src/arch.h:465" in="rw::archViolHash">
<m>
<![CDATA[        h ^= 0u; h = hashutil::fnv1aMultiply( h );   // NUL separator byte]]>
</m>
</hit>
<hit p="./src/clones.h:374" in="rw::cloneTokenHash">
<m>
<![CDATA[    for( unsigned char c : t ) { h ^= c; h = hashutil::fnv1aMultiply( h ); }]]>
</m>
</hit>
<hit p="./src/clones.h:375" in="rw::cloneTokenHash">
<m>
<![CDATA[    h ^= 0x9e3779b97f4a7c15ull;  h = hashutil::fnv1aMultiply( h );   // token separator so [ab][c] != [a][bc]]]>
… [473 more display lines; full output is 16577 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --match='(if_statement)'`

*Tree-sitter structural query WITHOUT a capture — a bare node query gets a capture AUTO-ADDED (auto_captured="1") instead of silently matching nothing.*

`````
<!-- ripwire match: tree-sitter structural query; each hit = a captured node + its enclosing symbol. shown=/capped= = rows printed vs found; hits_capped="1" ⇒ hits= is a FLOOR (engine match limit reached). auto_captured="1" ⇒ the query bound no @capture and ripwire appended `@m` to its single top-level pattern. raise the default cap with limit=N (offset=M pages) -->
<match hits="5000" shown="100" capped="1" hits_capped="1" auto_captured="1">
<m p="./bench/agentloop/analyze.py:34" in="load_results">if data.get( "schema" ) != SCHEMA:         raise SystemExit( f"{path}: unexpected schema {data.get('schema')!r} (expecte</m>
<m p="./bench/agentloop/analyze.py:50" in="pair_by_task_seed">if base and ctx and base["status"] == "ok" and ctx["status"] == "ok" \            and base["resolved"] is not None and c</m>
<m p="./bench/agentloop/analyze.py:64" in="clustered_bootstrap_lower">if not repos: return 0.0, []</m>
<m p="./bench/agentloop/analyze.py:80" in="loc_hit_delta">if base["localization_hit"] is None or ctx["localization_hit"] is None: return 0.0</m>
<m p="./bench/agentloop/analyze.py:89" in="paired_ratio">if bv: ratios.append( cv / bv - 1 )</m>
<m p="./bench/agentloop/analyze.py:90" in="paired_ratio">if not ratios: return None, None</m>
<m p="./bench/agentloop/analyze.py:100" in="analyze">if not paired:         out["note"] = "zero complete paired (baseline,ripwire_mcp) runs — nothing to analyze yet"      </m>
<m p="./bench/agentloop/analyze.py:124" in="print_report">if "note" in out:         print( f"  {out['note']}" ); return</m>
<m p="./bench/agentloop/analyze.py:173" in="self_test">if out["n_pairs"] != 27: failures.append( f"expected 27 paired runs, got {out['n_pairs']}" )</m>
<m p="./bench/agentloop/analyze.py:174" in="self_test">if out["n_incomplete"] != 1: failures.append( f"expected 1 incomplete pair, got {out['n_incomplete']}" )</m>
<m p="./bench/agentloop/analyze.py:175" in="self_test">if out["n_repos"] != 3: failures.append( f"expected 3 repos, got {out['n_repos']}" )</m>
<m p="./bench/agentloop/analyze.py:176" in="self_test">if not ( out["resolved_delta_mean"] &gt; 0 ): failures.append( "expected a positive resolved-rate delta" )</m>
<m p="./bench/agentloop/analyze.py:177" in="self_test">if not ( out["resolved_delta_bootstrap_95_lower"] &gt; 0 ):         failures.append( "expected a POSITIVE bootstrap 95% low</m>
<m p="./bench/agentloop/analyze.py:179" in="self_test">if out["tokens_out_ratio_p50"] is None or abs( out["tokens_out_ratio_p50"] - 0.08 ) &gt; 1e-6:         failures.append( f"e</m>
<m p="./bench/agentloop/analyze.py:182" in="self_test">if failures:         print( "\nSELF-TEST FAIL:" )         for f in failures: print( f"  - {f}" )         return 1</m>
<m p="./bench/agentloop/analyze.py:196" in="main">if a.self_test:         return self_test()</m>
<m p="./bench/agentloop/analyze.py:199" in="main">if not a.results:         raise SystemExit( "--results PATH is required (or pass --self-test to validate the math on a f</m>
<m p="./bench/agentloop/analyze.py:206" in="">if __name__ == "__main__":     sys.exit( main() )</m>
<m p="./bench/agentloop/run_agentloop.py:88" in="load_tasks_lock">if lock.get( "schema" ) != "ripwire-agentloop-tasks-lock-v1":         raise SystemExit( f"{path}: unexpected schema {loc</m>
<m p="./bench/agentloop/run_agentloop.py:95" in="load_tasks_lock">if actual != expected:         raise SystemExit( f"{path}: content hash mismatch (expected {expected}, computed {actual}</m>
<m p="./bench/agentloop/run_agentloop.py:132" in="checkout_repo">if not fetched_marker.exists():         if not ( dst / ".git" ).exists():             dst.mkdir( parents=True, exist_ok=</m>
<m p="./bench/agentloop/run_agentloop.py:133" in="checkout_repo">if not ( dst / ".git" ).exists():             dst.mkdir( parents=True, exist_ok=True )             sh( [ "git", "init", </m>
<m p="./bench/agentloop/run_agentloop.py:138" in="checkout_repo">if f.returncode != 0:             sh( [ "git", "fetch", "-q", "origin" ], cwd=dst )   # fallback: unshallow fetch of the</m>
<m p="./bench/agentloop/run_agentloop.py:142" in="checkout_repo">if co.returncode != 0:         co = sh( [ "git", "checkout", "-q", "-f", "FETCH_HEAD" ], cwd=dst )</m>
<m p="./bench/agentloop/run_agentloop.py:145" in="checkout_repo">if co.returncode != 0:         return None</m>
<m p="./bench/agentloop/run_agentloop.py:236" in="run_swebench_harness">if proc.returncode != 0:         print( f"# swebench harness run failed for {task['instance_id']}: {(proc.stderr or '')[</m>
<m p="./bench/agentloop/run_agentloop.py:242" in="run_swebench_harness">if not report_path.exists():         candidates = list( pathlib.Path( "." ).glob( f"*{run_id}*.json" ) )         report_</m>
<m p="./bench/agentloop/run_agentloop.py:245" in="run_swebench_harness">if not report_path or not report_path.exists():         print( f"# swebench harness produced no report for {task['instan</m>
… [73 more display lines; full output is 14757 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --match='(if_statement) @i'`

*The same shape query WITH a capture — the form that actually matches.*

`````
<!-- ripwire match: tree-sitter structural query; each hit = a captured node + its enclosing symbol. shown=/capped= = rows printed vs found; hits_capped="1" ⇒ hits= is a FLOOR (engine match limit reached). auto_captured="1" ⇒ the query bound no @capture and ripwire appended `@m` to its single top-level pattern. raise the default cap with limit=N (offset=M pages) -->
<match hits="5000" shown="100" capped="1" hits_capped="1">
<m p="./bench/agentloop/analyze.py:34" in="load_results">if data.get( "schema" ) != SCHEMA:         raise SystemExit( f"{path}: unexpected schema {data.get('schema')!r} (expecte</m>
<m p="./bench/agentloop/analyze.py:50" in="pair_by_task_seed">if base and ctx and base["status"] == "ok" and ctx["status"] == "ok" \            and base["resolved"] is not None and c</m>
<m p="./bench/agentloop/analyze.py:64" in="clustered_bootstrap_lower">if not repos: return 0.0, []</m>
<m p="./bench/agentloop/analyze.py:80" in="loc_hit_delta">if base["localization_hit"] is None or ctx["localization_hit"] is None: return 0.0</m>
<m p="./bench/agentloop/analyze.py:89" in="paired_ratio">if bv: ratios.append( cv / bv - 1 )</m>
<m p="./bench/agentloop/analyze.py:90" in="paired_ratio">if not ratios: return None, None</m>
<m p="./bench/agentloop/analyze.py:100" in="analyze">if not paired:         out["note"] = "zero complete paired (baseline,ripwire_mcp) runs — nothing to analyze yet"      </m>
<m p="./bench/agentloop/analyze.py:124" in="print_report">if "note" in out:         print( f"  {out['note']}" ); return</m>
<m p="./bench/agentloop/analyze.py:173" in="self_test">if out["n_pairs"] != 27: failures.append( f"expected 27 paired runs, got {out['n_pairs']}" )</m>
<m p="./bench/agentloop/analyze.py:174" in="self_test">if out["n_incomplete"] != 1: failures.append( f"expected 1 incomplete pair, got {out['n_incomplete']}" )</m>
<m p="./bench/agentloop/analyze.py:175" in="self_test">if out["n_repos"] != 3: failures.append( f"expected 3 repos, got {out['n_repos']}" )</m>
<m p="./bench/agentloop/analyze.py:176" in="self_test">if not ( out["resolved_delta_mean"] &gt; 0 ): failures.append( "expected a positive resolved-rate delta" )</m>
<m p="./bench/agentloop/analyze.py:177" in="self_test">if not ( out["resolved_delta_bootstrap_95_lower"] &gt; 0 ):         failures.append( "expected a POSITIVE bootstrap 95% low</m>
<m p="./bench/agentloop/analyze.py:179" in="self_test">if out["tokens_out_ratio_p50"] is None or abs( out["tokens_out_ratio_p50"] - 0.08 ) &gt; 1e-6:         failures.append( f"e</m>
<m p="./bench/agentloop/analyze.py:182" in="self_test">if failures:         print( "\nSELF-TEST FAIL:" )         for f in failures: print( f"  - {f}" )         return 1</m>
<m p="./bench/agentloop/analyze.py:196" in="main">if a.self_test:         return self_test()</m>
<m p="./bench/agentloop/analyze.py:199" in="main">if not a.results:         raise SystemExit( "--results PATH is required (or pass --self-test to validate the math on a f</m>
<m p="./bench/agentloop/analyze.py:206" in="">if __name__ == "__main__":     sys.exit( main() )</m>
<m p="./bench/agentloop/run_agentloop.py:88" in="load_tasks_lock">if lock.get( "schema" ) != "ripwire-agentloop-tasks-lock-v1":         raise SystemExit( f"{path}: unexpected schema {loc</m>
<m p="./bench/agentloop/run_agentloop.py:95" in="load_tasks_lock">if actual != expected:         raise SystemExit( f"{path}: content hash mismatch (expected {expected}, computed {actual}</m>
<m p="./bench/agentloop/run_agentloop.py:132" in="checkout_repo">if not fetched_marker.exists():         if not ( dst / ".git" ).exists():             dst.mkdir( parents=True, exist_ok=</m>
<m p="./bench/agentloop/run_agentloop.py:133" in="checkout_repo">if not ( dst / ".git" ).exists():             dst.mkdir( parents=True, exist_ok=True )             sh( [ "git", "init", </m>
<m p="./bench/agentloop/run_agentloop.py:138" in="checkout_repo">if f.returncode != 0:             sh( [ "git", "fetch", "-q", "origin" ], cwd=dst )   # fallback: unshallow fetch of the</m>
<m p="./bench/agentloop/run_agentloop.py:142" in="checkout_repo">if co.returncode != 0:         co = sh( [ "git", "checkout", "-q", "-f", "FETCH_HEAD" ], cwd=dst )</m>
<m p="./bench/agentloop/run_agentloop.py:145" in="checkout_repo">if co.returncode != 0:         return None</m>
<m p="./bench/agentloop/run_agentloop.py:236" in="run_swebench_harness">if proc.returncode != 0:         print( f"# swebench harness run failed for {task['instance_id']}: {(proc.stderr or '')[</m>
<m p="./bench/agentloop/run_agentloop.py:242" in="run_swebench_harness">if not report_path.exists():         candidates = list( pathlib.Path( "." ).glob( f"*{run_id}*.json" ) )         report_</m>
<m p="./bench/agentloop/run_agentloop.py:245" in="run_swebench_harness">if not report_path or not report_path.exists():         print( f"# swebench harness produced no report for {task['instan</m>
… [73 more display lines; full output is 14739 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --query="teleport pagerank" --top-k=5`

*Raw BM25 ranking (debug lens; --for is the real verb).*

`````
<!-- routed: subtoken+body BM25 (-for's default) — no strong name hit; broad query, plain rg may also win -->
<!-- ripwire v1 t=fn|method|cls|struct|iface|var|sec p=path layer=arch-layer(opt) n=name id=canonical(path::scope::name,when-scoped) k=rank c=call amb=ambiguous-calls(read-source) overloads=N-same-name-defs-merged-into-this-row(absent-if-1;shown=counts-them-individually,so-rows+sum(overloads-1)=shown) prov=scip(precise;else name-based) hdr:unresolved=call-name-defined-only-in-a-lang-incompatible-file (edges heuristic) r:est_tokens=hdr-copy(none-if-stable) -->
<!-- files=836 symbols=6432 edges=8733 shown=5 est_tokens=587 ambiguous=2631 unresolved=652 precise=3 skipped_oversize=3 order=important-first -->
<r est_tokens="587">
<f p="./src/main.cpp">
<s t="fn" n="churnRankedGraph" amb="2" k="14.8167">
<c n="resolveSinceScope"/>
<c n="churnTeleport"/>
<c n="churnTeleportWorkspace"/>
<c n="churnWindowStamp"/>
<c n="rankGraphTeleport"/>
<c n="empty"/>
<c n="empty"/>
<c n="push_back"/>
</s>
</f>
<f p="./src/gitmine.h">
<s t="fn" n="churnPriorFromFreq" id="./src/gitmine.h::rw::churnPriorFromFreq" k="12.1279">
<c n="size"/>
</s>
</f>
<f p="./src/graph.h">
<s t="fn" n="rankGraphTeleport" id="./src/graph.h::rw::rankGraphTeleport" amb="5" k="11.7235">
<c n="biasPrior"/>
<c n="pageRankDouble"/>
<c n="size"/>
<c n="begin"/>
<c n="end"/>
<c n="begin"/>
<c n="end"/>
</s>
<s t="fn" n="rankGraph" id="./src/graph.h::rw::rankGraph" k="11.1576">
<c n="rankGraphTeleport"/>
<c n="size"/>
</s>
<s t="fn" n="diffTeleport" id="./src/graph.h::rw::diffTeleport" k="11.0576">
<c n="size"/>
</s>
</f>
</r>
`````


---

# zoom the detail ladder

## `./build/ripwire . --for="pagerank power iteration" --detail=2`

*Importance-weighted detail: FULL bodies for top-2, signatures for the rest.*

`````
<ctx task="pagerank power iteration" route=" [routed: subtoken+body BM25 (--for&apos;s default) — no strong name hit, multi-word conceptual query]">
<!-- ripwire lens for "pagerank power iteration" [routed: subtoken+body BM25 (-for's default) — no strong name hit, multi-word conceptual query]: reusable building blocks + quality facts for what you're about to touch (cx=complexity ccx=cognitive in=reuse-count churn=recent-commits amp=change-amplification clone=1(duplicated) tested=1) — prefer composing/reusing these; watch the high-churn/high-amp/cloned ones est_tokens="4304" -->
<sigs capped="1">
<f p="./src/pagerank.cpp">
<d l="34" n="pageRankDouble" id="./src/pagerank.cpp::rw::pageRankDouble" cx="18" ccx="33" in="1" churn="2" amp="1" tested="1">unsigned pageRankDouble( const sparseCsr&lt;float&gt;&amp; inEdges, std::span&lt;const double&gt; weightedOutDegree, std::span&lt;const double&gt; teleport, std::span&lt;doub … [line truncated: 21 more bytes on this line]
</f>
<f p="./src/infra/dynamic_map.hpp" layer="infra">
<d l="290" n="leaf_node" id="./src/infra/dynamic_map.hpp::leaf_node::leaf_node" cx="0" ccx="0" in="0" churn="1">struct alignas(16) leaf_node</d>
<d l="310" n="dynamic_map" id="./src/infra/dynamic_map.hpp::dynamic_map::dynamic_map" cx="0" ccx="0" in="0" churn="1">class dynamic_map</d>
<d l="979" n="values_begin" id="./src/infra/dynamic_map.hpp::dynamic_map::values_begin" cx="2" ccx="1" in="3" churn="1" amp="3">value_iterator values_begin()</d>
<d l="1327" n="compact" id="./src/infra/dynamic_map.hpp::dynamic_map::compact" cx="28" ccx="49" in="0" churn="1">void compact()</d>
<d l="2015" n="leftmost_leaf" id="./src/infra/dynamic_map.hpp::dynamic_map::leftmost_leaf" cx="2" ccx="1" in="7" churn="1" amp="7" pure="1">
<doc>iteration helpers</doc>handle_t leftmost_leaf() const</d>
</f>
<f p="./src/graph.h">
<d l="1278" n="rankGraphTeleport" id="./src/graph.h::rw::rankGraphTeleport" cx="5" ccx="8" in="6" churn="3" amp="6">
<doc>PageRank with an explicit teleport / personalization vector p (Σp = 1). The prior is name-quali…</doc>inline std::vector&lt;float&gt; rankGraphTeleport( const Graph&amp; g, const std::vector&lt;float&gt;&amp; p, float alpha = 0.85f )</d>
<d l="1327" n="hits" id="./src/graph.h::rw::hits" cx="9" ccx="16" in="1" churn="3" amp="1">inline std::pair&lt;std::vector&lt;float&gt;, std::vector&lt;float&gt;&gt; hits( const Graph&amp; g, float tol = 1e-6f, unsigned maxIter = 100 )</d>
<d l="1742" n="computeQMetrics" id="./src/graph.h::rw::computeQMetrics" cx="52" ccx="124" in="2" churn="3" amp="2">inline QMetrics computeQMetrics( const IngestResult&amp; ing, const Graph&amp; g )</d>
<d l="2414" n="louvainLocalMoving" id="./src/graph.h::rw::louvainLocalMoving" cx="18" ccx="35" in="2" churn="3" amp="2">inline Communities louvainLocalMoving( const std::vector&lt;std::vector&lt;WEdge&gt;&gt;&amp; adj )</d>
</f>
<f p="./src/serialize.h">
<d l="918" n="MapAnnotations" id="./src/serialize.h::MapAnnotations::MapAnnotations" cx="0" ccx="0" in="0" churn="3">struct MapAnnotations</d>
<d l="988" n="rankByLegendFor" id="./src/serialize.h::rw::rankByLegendFor" cx="4" ccx="4" in="1" churn="3" amp="1">
<doc>The label → clause lookup. Returns nullptr for an unstamped map (the default pagerank path) so…</doc>inline const char* rankByLegendFor( const char* label ) noexcept</d>
<d l="3768" n="writeJsonMapStamp" id="./src/serialize.h::rw::writeJsonMapStamp" cx="10" ccx="12" in="1" churn="3" amp="1">inline void writeJsonMapStamp( JsonWriter&amp; w, std::string&amp; esc, const MapAnnotations* ann )</d>
<d l="3900" n="serializeJson" id="./src/serialize.h::rw::serializeJson" cx="49" ccx="82" in="1" churn="3" amp="1">inline void serializeJson( std::FILE* out, const IngestResult&amp; ing, const std::vector&lt;float&gt;&amp; ra…</d>
</f>
<f p="./src/pagerank.h">
<d l="11" n="PageRankConfig" id="./src/pagerank.h::PageRankConfig::PageRankConfig" cx="0" ccx="0" in="0" churn="2">struct PageRankConfig</d>
… [136 more display lines; full output is 12559 bytes on 92 raw line(s)]
`````

## `./build/ripwire . --pack-signatures --top-k=10`

*Body-elided decl skeletons — recounted on this corpus. Measured as element bytes: the <d> signature+doc elements --pack-signatures emits, against the SAME symbols' full <b> bodies from --expand, with the CORPUS-ROOT PREFIX SUBTRACTED FROM BOTH SIDES. That subtraction is the whole methodology and the figure is meaningless without it: the root repeats inside every element's id= and p=, it is not what this verb elides, and counting it makes the headline a function of how deep the checkout happens to sit on disk — on one corpus, three spellings of the same root read 18.6 points apart before the subtraction and agree exactly after it. Root-neutralised on THIS repo: 59.1% fewer bytes at top-10, 68.4% at top-50, 66.5% at top-100. top-50 is the number to quote, because the sigs payload is top-50 regardless of --top-k and is therefore what THIS command emits. '~70%' is reachable at larger N but overstates the smaller shapes people actually run, and like the --format=columnar sibling below, a single small/trivial body can invert it (signature+doc bigger than the body). test/showcasecapturecheck.sh (C) re-derives all three from this repo every run, in the same quantity, and fails if the caption and the recount drift apart.*

`````
<ctx>
<!-- ripwire v1 t=fn|method|cls|struct|iface|var|sec p=path layer=arch-layer(opt) n=name id=canonical(path::scope::name,when-scoped) k=rank c=call amb=ambiguous-calls(read-source) overloads=N-same-name-defs-merged-into-this-row(absent-if-1;shown=counts-them-individually,so-rows+sum(overloads-1)=shown) prov=scip(precise;else name-based) hdr:unresolved=call-name-defined-only-in-a-lang-incompatible-file (edges heuristic) r:est_tokens=hdr-copy(none-if-stable) -->
<!-- files=836 symbols=6432 edges=8733 shown=10 est_tokens=4701 ambiguous=2631 unresolved=652 precise=3 skipped_oversize=3 order=important-first -->
<r est_tokens="4701">
<f p="./src/svector.h">
<s t="method" n="size" id="./src/svector.h::svector::size" k="0.0503">
</s>
<s t="method" n="push_back" id="./src/svector.h::svector::push_back" amb="2" k="0.0133">
<c n="buf"/>
<c n="buf"/>
<c n="grow"/>
</s>
<s t="method" n="buf" id="./src/svector.h::svector::buf" overloads="2" k="0.0123">
</s>
<s t="method" n="grow" id="./src/svector.h::svector::grow" amb="1" k="0.0073">
<c n="buf"/>
<c n="buf"/>
</s>
<s t="method" n="end" id="./src/svector.h::svector::end" overloads="2" amb="1" k="0.0044">
<c n="buf"/>
<c n="buf"/>
</s>
</f>
<f p="./src/scipoverlay.h">
<s t="method" n="empty" id="./src/scipoverlay.h::ScipOverlay::empty" k="0.0126">
</s>
</f>
<f p="./src/notes.h">
<s t="method" n="empty" id="./src/notes.h::NoteIndex::empty" k="0.0076">
</s>
… [120 more display lines; full output is 11755 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --outline=rankGraphTeleport --top-k=0`

*Control-flow skeleton of one symbol, payload-only via the new --top-k=0.*

`````
<ctx><outline><o t="fn" l="1278" p="./src/graph.h" n="rankGraphTeleport"><![CDATA[inline std::vector<float> rankGraphTeleport( const Graph& g, const std::vector<float>& p, float alpha = 0.85f )
{
    PROFILE_SCOPE_DESCRIBE( "rankGraph: PageRank (power iteration)" );
    const std::vector<float> pw = biasPrior( g, p );
    const std::size_t N = pw.size();
    std::vector<double> teleport( pw.begin(), pw.end() );
    std::vector<double> rankDouble( N, 0.0 );
    if( N )
    {
  ...
    }
    std::vector<float> r( N, 0.f );
    std::transform( rankDouble.begin(), rankDouble.end(), r.begin(), []( double value ) { return float( value ); } );
    return r;
}
]]></o></outline></ctx>
`````

## `./build/ripwire . --outline=rankGraphTeleport:1-10 --top-k=0`

*CHANGED: a line range on --outline is now STRIPPED with a stderr note (it used to refuse).*

`````
<ctx><outline><o t="fn" l="1278" p="./src/graph.h" n="rankGraphTeleport"><![CDATA[inline std::vector<float> rankGraphTeleport( const Graph& g, const std::vector<float>& p, float alpha = 0.85f )
{
    PROFILE_SCOPE_DESCRIBE( "rankGraph: PageRank (power iteration)" );
    const std::vector<float> pw = biasPrior( g, p );
    const std::size_t N = pw.size();
    std::vector<double> teleport( pw.begin(), pw.end() );
    std::vector<double> rankDouble( N, 0.0 );
    if( N )
    {
  ...
    }
    std::vector<float> r( N, 0.f );
    std::transform( rankDouble.begin(), rankDouble.end(), r.begin(), []( double value ) { return float( value ); } );
    return r;
}
]]></o></outline></ctx>
`````

stderr:

`````
ripwire: --outline=rankGraphTeleport:1-10: --outline has no line-range form — outlining the whole symbol (use --expand=rankGraphTeleport:1-10 for a body slice)
`````

## `./build/ripwire . --expand=rankGraphTeleport --top-k=0`

*Full body + inline callee signatures.*

`````
<ctx><bodies shown="1" total="1" capped="0"><b t="fn" l="1278" p="./src/graph.h" n="rankGraphTeleport"><![CDATA[inline std::vector<float> rankGraphTeleport( const Graph& g, const std::vector<float>& p, float alpha = 0.85f )
{
    PROFILE_SCOPE_DESCRIBE( "rankGraph: PageRank (power iteration)" );
    const std::vector<float> pw = biasPrior( g, p );
    const std::size_t N = pw.size();
    std::vector<double> teleport( pw.begin(), pw.end() );
    std::vector<double> rankDouble( N, 0.0 );
    if( N )
    {
        double teleportMass = 0.0;
        for( const double value : teleport )
            teleportMass += value;
        if( teleportMass > 0.0 )
        {
            const double inverseMass = 1.0 / teleportMass;
            for( double& value : teleport )
                value *= inverseMass;
        }
        pageRankDouble( g.inEdges, g.wOutDeg, teleport, rankDouble, PageRankConfig{ .alpha = double( alpha ) } );
    }
    std::vector<float> r( N, 0.f );
    std::transform( rankDouble.begin(), rankDouble.end(), r.begin(), []( double value ) { return float( value ); } );
    return r;
}]]><calls total="7"><c n="biasPrior" l="1263">inline std::vector&lt;float&gt; biasPrior( const Graph&amp; g, const std::vector&lt;float&gt;&amp; p )</c><c n="pageRankDouble" l="34">unsigned pageRankDouble( const sparseCsr&lt;float&gt;&amp; inEdges, std::span&lt;const double&gt; weightedOutDegree, s … [line truncated: 369 more bytes on this line]
`````

## `./build/ripwire . --expand=rankGraphTeleport:1-12 --top-k=0`

*Body SLICE: lines 1..12 of the symbol's own body, with lines="lo-hi/total" marking it partial.*

`````
<ctx><bodies shown="1" total="1" capped="0"><b t="fn" l="1278" p="./src/graph.h" n="rankGraphTeleport" lines="1-12/24"><![CDATA[inline std::vector<float> rankGraphTeleport( const Graph& g, const std::vector<float>& p, float alpha = 0.85f )
{
    PROFILE_SCOPE_DESCRIBE( "rankGraph: PageRank (power iteration)" );
    const std::vector<float> pw = biasPrior( g, p );
    const std::size_t N = pw.size();
    std::vector<double> teleport( pw.begin(), pw.end() );
    std::vector<double> rankDouble( N, 0.0 );
    if( N )
    {
        double teleportMass = 0.0;
        for( const double value : teleport )
            teleportMass += value;]]><calls total="7"><c n="biasPrior" l="1263">inline std::vector&lt;float&gt; biasPrior( const Graph&amp; g, const std::vector&lt;float&gt;&amp; p )</c><c n="pageRankDouble" l="34">unsigned pageRankDouble( const sparseCsr&lt;float&gt;&amp; inEdges, std::span&lt;cons … [line truncated: 402 more bytes on this line]
`````

## `./build/ripwire . --expand=compressBody --top-k=0 --compress`

*Comments stripped + blank runs collapsed — compressBody is the function that implements --compress itself, chosen because it is comment-heavy enough to show a real reduction (the previously captioned symbol had no comments or blank runs, so before/after were byte-identical under a caption promising a difference).*

`````
<ctx><bodies shown="1" total="1" capped="0"><b t="fn" l="1707" p="./src/serialize.h" n="compressBody"><![CDATA[inline std::string compressBody( std::string_view src )
{


    std::string out;
    out.reserve( src.size() );

    const std::size_t N = src.size();
    std::size_t       i = 0;

    while( i < N )
    {
        const char c = src[i];


        if( c == '"' )
        {

            if( i >= 1 && src[i - 1] == 'R' && ( i < 2 || src[i - 2] != '\\' ) )
            {

                std::size_t j = i + 1;
                std::string delim;
                while( j < N && src[j] != '(' && src[j] != '\n' ) delim += src[j++];
                if( j < N && src[j] == '(' )
                {

                    const std::string terminator = ")" + delim + "\"";
                    out += src.substr( i, j - i + 1 );   
                    i = j + 1;
… [128 more lines, 4119 bytes total]
`````

## `./build/ripwire . --expand=readAckRecords --top-k=0 --no-redact`

*--no-redact: emit bodies verbatim (credential redaction is on by default).*

`````
<ctx><bodies shown="1" total="1" capped="0"><b t="fn" l="2124" p="./src/quality.h" n="readAckRecords"><![CDATA[inline gtl::btree_map<std::string, AckRecord> readAckRecords( const std::string& path )
{
    gtl::btree_map<std::string, AckRecord> out;
    std::ifstream f( path );
    if( !f ) return out;
    std::string line;
    while( std::getline( f, line ) )
    {
        while( !line.empty() && ( line.back() == '\r' || line.back() == '\n' ) ) line.pop_back();   // CRLF tolerance (merged-in Windows checkout)
        if( line.empty() || line[0] == '#' ) continue;
        std::istringstream is( line );
        std::string tag, kind;
        std::uint64_t key = 0;
        std::uint32_t ackNow = 0;
        is >> tag >> kind >> std::hex >> key >> std::dec >> ackNow;
        if( tag != "ack" || is.fail() ) { DEGRADED_PATH_ALERT( "quality: malformed ack line skipped" ); continue; }
        kind = normalizeLegacyAckKind( kind, ackNow );               // P0.3 migration — see the note at ackKindToken
        std::string reason;
        std::getline( is, reason );
        while( !reason.empty() && reason.front() == ' ' ) reason.erase( reason.begin() );
        while( !reason.empty() && reason.back() == '\r' ) reason.pop_back();   // CRLF tolerance on the trailing field too

        const std::string mapKey = ackMapKey( kind, key );
        const auto        it     = out.find( mapKey );
        if( it == out.end() || ackNow > it->second.ackNow )              // D2: max(ackNow) wins, not last-line
            out[ mapKey ] = AckRecord{ kind, key, ackNow, reason };
    }
    return out;
}]]><calls total="9"><c n="find" l="1738">std::uint32_t find( std::uint32_t x )</c><c n="ackMapKey" l="2048">inline std::string ackMapKey( const std::string&amp; kind, std::uint64_t key )</c><c n="normalizeLegacyAckKind" l="2098">inline std::string normalizeLegacyAckKind( const std::string&amp; kind … [line truncated: 343 more bytes on this line]
`````

## `./build/ripwire . --pack-top-n=3 --top-k=0`

*Pack the top-3 ranked symbols' full bodies (deprecated verb; see stderr).*

`````
<ctx><src p="./src/svector.h"><![CDATA[#pragma once

// svector.h — rw::svector: a small-vector with N INLINE slots that spills to the heap only past N.
//
// WHY THIS EXISTS ALONGSIDE the vendored martinus/svector (third_party/svector.h, ankerl::svector):
// it's purpose-built for the ONE shape ripwire leans on hardest — a `Map<K, svector<V,N>>` of many tiny
// id-lists (byName / shard maps): WRITE-ONCE during the parse/merge, then READ-HOT during resolve.
//
//   • build win (shared with martinus): the N small lists that would each malloc become inline — one fewer
//     heap allocation per collection, no pointer-chase to the payload.
//   • read win (the differentiator): size() is `return sz_` — BRANCH-FREE. martinus packs its size into the
//     SVO buffer to reach 16 B, so its size() branches on is_direct(); on a 4M-read hot loop that branch
//     costs ~6 ms. We keep an explicit sz_ field instead: sizeof(svector<uint32,2>) = 24 B (same as
//     std::vector), 8 B more than martinus — we spend those 8 bytes to make the hot read branch-free.
//
// Measured 3-way (std::vector vs martinus vs this) in bench/bench_svector3.cpp: for the read-hot map value,
// this wins ~25% over martinus and ~45% over std::vector. Prefer martinus when compactness matters, for
// general standalone use, or when the value is iterated (begin()/end() branch in BOTH) more than size()'d.
//
// Hand-rolled RAII (raw new[]/delete[], per house style), move + copy. Tuned for trivially-copyable V
// (ids); fine for any movable V.

#include <cstdint>
#include <utility>

namespace rw
{

template <class T, std::uint32_t N>
class svector
… [1006 more lines, 65683 bytes total]
`````

stderr:

`````
ripwire: --pack-top-n is deprecated — use --pack-task/--detail instead (unchanged behavior for now)
`````


---

# assess quality / structure

## `./build/ripwire . --metrics --top-k=10`

*Fan-in/out + complexity annotations on the map.*

`````
<!-- ripwire v1 t=fn|method|cls|struct|iface|var|sec p=path layer=arch-layer(opt) n=name id=canonical(path::scope::name,when-scoped) k=rank c=call amb=ambiguous-calls(read-source) overloads=N-same-name-defs-merged-into-this-row(absent-if-1;shown=counts-them-individually,so-rows+sum(overloads-1)=shown) prov=scip(precise;else name-based) hdr:unresolved=call-name-defined-only-in-a-lang-incompatible-file (edges heuristic) r:est_tokens=hdr-copy(none-if-stable) -->
<!-- metrics: in=fan-in out=fan-out cx=cyclomatic ccx=cognitive loc=lines params=count nest=depth cbo=coupling lcom4=cohesion amp=change-amplification tested=1 role=hub(fan-in 8+; uses spells role call|read|write|import|extends). Absent=N/A, never 0. -->
<!-- files=836 symbols=6432 edges=8733 shown=10 est_tokens=1020 ambiguous=2631 unresolved=652 precise=3 skipped_oversize=3 order=important-first -->
<r est_tokens="1020">
<f p="./src/svector.h">
<s t="method" n="size" id="./src/svector.h::svector::size" in="796" out="0" cx="1" ccx="0" role="hub" loc="1" params="0" nest="0" cbo="0" amp="796" tested="1" k="0.0503">
</s>
<s t="method" n="push_back" id="./src/svector.h::svector::push_back" in="367" out="3" cx="2" ccx="1" role="hub" loc="1" params="1" nest="1" cbo="3" amp="367" tested="1" amb="2" k="0.0133">
<c n="buf"/>
<c n="buf"/>
<c n="grow"/>
</s>
<s t="method" n="buf" id="./src/svector.h::svector::buf" overloads="2" in="8" out="0" cx="2" ccx="1" role="hub" loc="1" params="0" nest="1" cbo="0" amp="8" tested="1" k="0.0123">
</s>
<s t="method" n="grow" id="./src/svector.h::svector::grow" in="2" out="2" cx="3" ccx="2" loc="7" params="1" nest="1" cbo="2" amp="2" amb="1" k="0.0073">
<c n="buf"/>
<c n="buf"/>
</s>
<s t="method" n="end" id="./src/svector.h::svector::end" overloads="2" in="266" out="2" cx="1" ccx="0" role="hub" loc="1" params="0" nest="0" cbo="2" amp="266" tested="1" amb="1" k="0.0044">
<c n="buf"/>
<c n="buf"/>
</s>
</f>
<f p="./src/scipoverlay.h">
<s t="method" n="empty" id="./src/scipoverlay.h::ScipOverlay::empty" in="410" out="0" cx="1" ccx="0" role="hub" loc="1" params="0" nest="0" cbo="0" amp="410" tested="1" k="0.0126">
</s>
</f>
<f p="./src/notes.h">
<s t="method" n="empty" id="./src/notes.h::NoteIndex::empty" in="336" out="0" cx="1" ccx="0" role="hub" loc="1" params="0" nest="0" cbo="0" amp="336" tested="1" k="0.0076">
</s>
</f>
<f p="./src/infra/fastmath.h" layer="infra">
<s t="fn" n="max" id="./src/infra/fastmath.h::fastmath::max" in="39" out="0" cx="2" ccx="1" role="hub" loc="1" params="2" nest="1" cbo="0" amp="39" tested="1" k="0.0052">
</s>
</f>
</r>
`````

## `./build/ripwire . --deps`

*File->file dependency graph (god-files, cycles).*

`````
<!-- ripwire deps: file-to-file #include/import view, heaviest transitive cone first. files= (root) = files with at least one dependency edge (this listing's own denominator); health files= = the whole indexed corpus; health dep_files= = the dependency-CAPABLE subset of it (the ccd/acd/nccd denominator). raise the default cap with limit=N (offset=M pages). -->
<deps files="202" shown="40" capped="1">
<health files="836" dep_files="398" ccd="1712" acd="4.3" nccd="0.56" shape="horizontal"/>
<godfiles total="124" shown="12" capped="1">
<f p="./src/model.h" afferent="50"/>
<f p="./src/graph.h" afferent="23"/>
<f p="./src/serialize.h" afferent="20"/>
<f p="./src/arch.h" afferent="18"/>
<f p="./src/jsonesc.h" afferent="13"/>
<f p="./src/ingest.h" afferent="12"/>
<f p="./src/quality.h" afferent="12"/>
<f p="./src/filter.h" afferent="11"/>
<f p="./src/hashutil.h" afferent="10"/>
<f p="./src/gitmine.h" afferent="9"/>
<f p="./src/docparse.h" afferent="8"/>
<f p="./src/gitstamp.h" afferent="8"/>
</godfiles>
<stabledeps violations="14">
<v from="./src/mcp.h" to="./src/mcpverbs.h" gap="0.38"/>
<v from="./src/gitstamp.h" to="./src/quality.h" gap="0.29"/>
<v from="./test/cyclecutfix/b.h" to="./test/cyclecutfix/c.h" gap="0.25"/>
<v from="./test/cyclecutfix/c.h" to="./test/cyclecutfix/a.h" gap="0.25"/>
<v from="./src/mcpedit.h" to="./src/mcpindex.h" gap="0.20"/>
<v from="./src/partition.h" to="./src/packtask.h" gap="0.20"/>
<v from="./src/serialize.h" to="./src/notes.h" gap="0.19"/>
<v from="./src/mcp.h" to="./src/mcpedit.h" gap="0.10"/>
<v from="./src/mcpserver.h" to="./src/mcp.h" gap="0.07"/>
<v from="./src/situ.h" to="./src/prcontext.h" gap="0.07"/>
<v from="./src/lexical.h" to="./src/lexindex.h" gap="0.07"/>
<v from="./src/ownersview.h" to="./src/gitmine.h" gap="0.07"/>
… [700 more display lines; full output is 17300 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --hotspots`

*Complexity x recent git churn (maintenance pain).*

`````
<!-- ripwire hotspots: maintenance-pain = complexity × recent churn (window=12mo). churn=commits touching the file; ccx=Σ cognitive complexity; score=churn×ccx; top=worst function. files= is the DENOMINATOR ranked= is drawn from, and a hotspot needs both factors nonzero, so ranked= + unranked_no_churn= + unranked_no_complexity= = files= exactly. unranked_no_complexity= is a file with commits but no function or method to score (a pure declaration header, markdown, config). unranked_no_churn= is a file no in-window commit was attributed to — and it CONFLATES two cases this verb cannot tell apart: a genuinely quiet file, and one whose path the git-to-index join never bound (a rename, an exclusion, or a spelling the join could not match), which scores zero for a reason that is not about the file. Treat it as an upper bound on quietness, not a measure of it. raise the default cap with limit=N (offset=M pages) -->
<!-- at= is the git commit these numbers were computed at; a trailing +dirty means the working tree differed from that commit, so the numbers describe the tree, not the commit -->
<hotspots window="12mo" files="836" ranked="221" unranked_no_churn="0" unranked_no_complexity="615" shown="40" capped="1" at="1dc07e27a+dirty">
<f p="./src/main.cpp" churn="4" ccx="3311" score="13244" top="main" top_ccx="376" top_l="8007"/>
<f p="./src/ingest.cpp" churn="3" ccx="2713" score="8139" top="ingest" top_ccx="702" top_l="3856"/>
<f p="./src/serialize.h" churn="3" ccx="1517" score="4551" top="packSignatures" top_ccx="197" top_l="2035"/>
<f p="./src/graph.h" churn="3" ccx="1424" score="4272" top="buildGraph" top_ccx="712" top_l="379"/>
<f p="./src/quality.h" churn="3" ccx="700" score="2100" top="computeDelta" top_ccx="236" top_l="2204"/>
<f p="./src/layout.h" churn="3" ccx="694" score="2082" top="writeLayout" top_ccx="31" top_l="1870"/>
<f p="./src/mcpverbs.h" churn="3" ccx="685" score="2055" top="runBatchSub" top_ccx="98" top_l="2381"/>
<f p="./src/docdrift.h" churn="3" ccx="545" score="1635" top="parseIntLiteral" top_ccx="37" top_l="345"/>
<f p="./src/gitmine.h" churn="3" ccx="497" score="1491" top="applyCoChangeBoost" top_ccx="93" top_l="1706"/>
<f p="./src/mcp.h" churn="3" ccx="460" score="1380" top="dispatchMcpLine" top_ccx="428" top_l="304"/>
<f p="./src/resolve.h" churn="3" ccx="460" score="1380" top="resolveTsImport" top_ccx="56" top_l="331"/>
<f p="./src/crossref.h" churn="3" ccx="412" score="1236" top="streamBlobs" top_ccx="39" top_l="362"/>
<f p="./src/lexical.h" churn="3" ccx="398" score="1194" top="lexicalScoresTiered" top_ccx="256" top_l="95"/>
<f p="./src/search.h" churn="3" ccx="367" score="1101" top="grepCollect" top_ccx="52" top_l="815"/>
<f p="./src/cli.h" churn="3" ccx="344" score="1032" top="parseArgs" top_ccx="156" top_l="2423"/>
<f p="./src/skilleval.h" churn="3" ccx="319" score="957" top="runEvalSkills" top_ccx="108" top_l="484"/>
<f p="./src/eval.h" churn="3" ccx="302" score="906" top="runEval" top_ccx="66" top_l="133"/>
<f p="./src/darkflags.h" churn="3" ccx="295" score="885" top="computeFlags" top_ccx="40" top_l="709"/>
<f p="./src/lintrules.h" churn="3" ccx="280" score="840" top="parseLintRuleFile" top_ccx="102" top_l="212"/>
<f p="./src/flipimpact.h" churn="3" ccx="276" score="828" top="scanBindingUses" top_ccx="31" top_l="446"/>
<f p="./src/arch.h" churn="3" ccx="263" score="789" top="computeModuleMetrics" top_ccx="68" top_l="584"/>
<f p="./src/lanes.h" churn="3" ccx="240" score="720" top="warnCoincidingClaims" top_ccx="24" top_l="585"/>
<f p="./src/skillscan.h" churn="3" ccx="235" score="705" top="scanSkillText" top_ccx="150" top_l="365"/>
<f p="./src/mcpjson.h" churn="3" ccx="212" score="636" top="findRawId" top_ccx="43" top_l="552"/>
<f p="./src/prcontext.h" churn="3" ccx="205" score="615" top="writePrContext" top_ccx="138" top_l="606"/>
<f p="./src/clones.h" churn="2" ccx="303" score="606" top="findClonesType3" top_ccx="119" top_l="401"/>
<f p="./src/mcpserver.h" churn="3" ccx="200" score="600" top="runMcpHttp" top_ccx="86" top_l="332"/>
… [14 more display lines; full output is 5364 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --clones`

*Token-normalized duplicate bodies.*

`````
<!-- ripwire clones: function bodies with similar normalized token streams (identifiers/literals normalized, so renamed copies match). type=2 exact/renamed (Type-1/2); type=3 gapped near-miss (an inserted/changed statement, similarity in [0.80,1.0)). Reuse don't reimplement; a fix to one likely belongs in all. groups= and type3= are the two GROUP-TYPE totals (each capped independently, so neither is the row count); total= is the true row total (groups + type3-group-count) and is ALWAYS present, paged or not; shown= is the number of group rows that follow this run. capped="1" means rows were dropped. exempt= on a group ⇒ every member is on a path the quality-delta verb's duplication kind deliberately ignores (fixture dirs / shell test-runners repeat boilerplate by convention) — a fact here, never a gate there; exempt_groups= counts them over ALL groups. raise the default cap with limit=N (offset=M pages). -->
<clones groups="39" type3="154" total="193" exempt_groups="80" shown="79" capped="1">
<group type="2" tokens="273" n="3" exempt="shell-runner">
<f n="monotonic_check" p="./test/pyimportprecisecheck.sh:88"/>
<f n="monotonic_check" p="./test/rustimportprecisecheck.sh:114"/>
<f n="monotonic_check" p="./test/tsimportprecisecheck.sh:87"/>
</group>
<group type="2" tokens="207" n="4" exempt="shell-runner">
<f n="batch_sub" p="./test/mcpclidiffcheck.sh:63"/>
<f n="batch_sub" p="./test/mcptranchecheck.sh:55"/>
<f n="batch_sub" p="./test/mcpw2fixcheck.sh:52"/>
<f n="batch_sub" p="./test/mcpw3fixcheck.sh:51"/>
</group>
<group type="2" tokens="142" n="2">
<f n="test_tier2_accept_big_quality_small_cost" p="./bench/locbench/test_compare_gate.py:130"/>
<f n="test_tier2_reject_small_quality_big_cost" p="./bench/locbench/test_compare_gate.py:143"/>
</group>
<group type="2" tokens="126" n="2">
<f n="addWholeFileFn" p="./test/cloneband_harness.cpp:61"/>
<f n="addWholeFileFn" p="./test/type3clone_harness.cpp:44"/>
</group>
<group type="2" tokens="116" n="2">
<f n="rankFiles" p="./src/eval.h:44"/>
<f n="rankCandidates" p="./src/skilleval.h:347"/>
</group>
<group type="2" tokens="114" n="2">
<f n="timer" p="./bench/representative_perfgate.sh:39"/>
<f n="run_once_ms" p="./test/mergescoutcheck.sh:268"/>
</group>
<group type="2" tokens="109" n="2">
… [302 more display lines; full output is 14576 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --cochange`

*Files that change together in git (hidden coupling).*

`````
<!-- ripwire cochange: file pairs that change together in git but share no transitive static dependency (surprising=1) = hidden coupling. together= is the number of commits in window= that touched BOTH files (3 or more, or the pair is not reported); deg= is that count over the commit count of the LESS-CHANGED of the two files, so 1.00 means the quieter file never changed without the other. window= is the mining window: the default 18 months, or the since=REV|DATE value when one resolved. surprising= is only defined where BOTH sides could carry a static dependency at all (the same dependency-capable predicate deps <health dep_files=> uses: source languages yes; sh, md, json, ruby and binary/unknown files no). A pair with a dep-incapable side keeps its row and carries dep_capable=0 instead, because for it "shares no static dependency" is vacuously true. raise the default cap with limit=N (offset=M pages) -->
<!-- at= is the git commit these numbers were computed at; a trailing +dirty means the working tree differed from that commit, so the numbers describe the tree, not the commit -->
<cochange pairs="0" window="18mo" shown="0" capped="0" at="1dc07e27a+dirty">
</cochange>
`````

## `./build/ripwire . --hotspots --since="2 weeks ago"`

*Hotspots scoped to RECENT churn (the regression lens).*

`````
<!-- ripwire hotspots: maintenance-pain = complexity × recent churn (window=2 weeks ago). churn=commits touching the file; ccx=Σ cognitive complexity; score=churn×ccx; top=worst function. files= is the DENOMINATOR ranked= is drawn from, and a hotspot needs both factors nonzero, so ranked= + unranked_no_churn= + unranked_no_complexity= = files= exactly. unranked_no_complexity= is a file with commits but no function or method to score (a pure declaration header, markdown, config). unranked_no_churn= is a file no in-window commit was attributed to — and it CONFLATES two cases this verb cannot tell apart: a genuinely quiet file, and one whose path the git-to-index join never bound (a rename, an exclusion, or a spelling the join could not match), which scores zero for a reason that is not about the file. Treat it as an upper bound on quietness, not a measure of it. raise the default cap with limit=N (offset=M pages) -->
<!-- at= is the git commit these numbers were computed at; a trailing +dirty means the working tree differed from that commit, so the numbers describe the tree, not the commit -->
<hotspots window="2 weeks ago" files="836" ranked="221" unranked_no_churn="0" unranked_no_complexity="615" shown="40" capped="1" at="1dc07e27a+dirty">
<f p="./src/main.cpp" churn="4" ccx="3311" score="13244" top="main" top_ccx="376" top_l="8007"/>
<f p="./src/ingest.cpp" churn="3" ccx="2713" score="8139" top="ingest" top_ccx="702" top_l="3856"/>
<f p="./src/serialize.h" churn="3" ccx="1517" score="4551" top="packSignatures" top_ccx="197" top_l="2035"/>
<f p="./src/graph.h" churn="3" ccx="1424" score="4272" top="buildGraph" top_ccx="712" top_l="379"/>
<f p="./src/quality.h" churn="3" ccx="700" score="2100" top="computeDelta" top_ccx="236" top_l="2204"/>
<f p="./src/layout.h" churn="3" ccx="694" score="2082" top="writeLayout" top_ccx="31" top_l="1870"/>
<f p="./src/mcpverbs.h" churn="3" ccx="685" score="2055" top="runBatchSub" top_ccx="98" top_l="2381"/>
<f p="./src/docdrift.h" churn="3" ccx="545" score="1635" top="parseIntLiteral" top_ccx="37" top_l="345"/>
<f p="./src/gitmine.h" churn="3" ccx="497" score="1491" top="applyCoChangeBoost" top_ccx="93" top_l="1706"/>
<f p="./src/mcp.h" churn="3" ccx="460" score="1380" top="dispatchMcpLine" top_ccx="428" top_l="304"/>
<f p="./src/resolve.h" churn="3" ccx="460" score="1380" top="resolveTsImport" top_ccx="56" top_l="331"/>
<f p="./src/crossref.h" churn="3" ccx="412" score="1236" top="streamBlobs" top_ccx="39" top_l="362"/>
<f p="./src/lexical.h" churn="3" ccx="398" score="1194" top="lexicalScoresTiered" top_ccx="256" top_l="95"/>
<f p="./src/search.h" churn="3" ccx="367" score="1101" top="grepCollect" top_ccx="52" top_l="815"/>
<f p="./src/cli.h" churn="3" ccx="344" score="1032" top="parseArgs" top_ccx="156" top_l="2423"/>
<f p="./src/skilleval.h" churn="3" ccx="319" score="957" top="runEvalSkills" top_ccx="108" top_l="484"/>
<f p="./src/eval.h" churn="3" ccx="302" score="906" top="runEval" top_ccx="66" top_l="133"/>
<f p="./src/darkflags.h" churn="3" ccx="295" score="885" top="computeFlags" top_ccx="40" top_l="709"/>
<f p="./src/lintrules.h" churn="3" ccx="280" score="840" top="parseLintRuleFile" top_ccx="102" top_l="212"/>
<f p="./src/flipimpact.h" churn="3" ccx="276" score="828" top="scanBindingUses" top_ccx="31" top_l="446"/>
<f p="./src/arch.h" churn="3" ccx="263" score="789" top="computeModuleMetrics" top_ccx="68" top_l="584"/>
<f p="./src/lanes.h" churn="3" ccx="240" score="720" top="warnCoincidingClaims" top_ccx="24" top_l="585"/>
<f p="./src/skillscan.h" churn="3" ccx="235" score="705" top="scanSkillText" top_ccx="150" top_l="365"/>
<f p="./src/mcpjson.h" churn="3" ccx="212" score="636" top="findRawId" top_ccx="43" top_l="552"/>
<f p="./src/prcontext.h" churn="3" ccx="205" score="615" top="writePrContext" top_ccx="138" top_l="606"/>
<f p="./src/clones.h" churn="2" ccx="303" score="606" top="findClonesType3" top_ccx="119" top_l="401"/>
<f p="./src/mcpserver.h" churn="3" ccx="200" score="600" top="runMcpHttp" top_ccx="86" top_l="332"/>
… [14 more display lines; full output is 5378 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --arch=test/archfix/rules.txt`

*Enforce layering rules (exit 2 on violation) — run against the repo's own test fixture rules.*

`````
<!-- ripwire arch: layering fitness function — edges that violate your declared rules (layer rules and regex path-rules). exit=2 if any NEW (un-baselined) violation. <metrics> = descriptive Martin Ca/Ce/I/A/D + reachability, never gates. Rules — layer substrings and regex path-rules alike — are matched against each file's ROOT-RELATIVE path (src/core/x.cpp), never the absolute or ./-prefixed spelling shown in from=/to=, so a rule means the same thing whatever directory the tree was checked out into. -->
<arch layers="2" rules="1" pathRules="0" violations="0" baselined="0" new_violations="0">
<metrics modules="198" typed_modules="76" zone_pain="60" zone_useless="1" zone_ok="15" zone_na="122" propagation_cost="0.011" note="Martin Ca/Ce/I/A/D + zone (main-sequence heuristic, no independent outcome-based validation — folklore, not proof) + reachability — directory-level estimate from na … [line truncated: 408 more bytes on this line]
<m path="." ca="0" ce="0" types="0" abstract="0" I="0.00" A="0.00" D="1.00" zone="n/a" reachable="1" isolated="1"/>
<m path="./bench" ca="0" ce="1" types="5" abstract="2" I="1.00" A="0.40" D="0.40" zone="ok" reachable="1"/>
<m path="./bench/agentloop" ca="0" ce="0" types="0" abstract="0" I="0.00" A="0.00" D="1.00" zone="n/a" reachable="1" isolated="1"/>
<m path="./bench/cppbench" ca="0" ce="0" types="1" abstract="0" I="0.00" A="0.00" D="1.00" zone="pain" reachable="1" isolated="1"/>
<m path="./bench/cppbench/results" ca="0" ce="0" types="0" abstract="0" I="0.00" A="0.00" D="1.00" zone="n/a" reachable="1" isolated="1"/>
<m path="./bench/h4fixtures/bash" ca="0" ce="0" types="0" abstract="0" I="0.00" A="0.00" D="1.00" zone="n/a" reachable="1" isolated="1"/>
<m path="./bench/h4fixtures/c" ca="0" ce="0" types="1" abstract="0" I="0.00" A="0.00" D="1.00" zone="pain" reachable="1" isolated="1"/>
<m path="./bench/h4fixtures/cpp" ca="0" ce="0" types="2" abstract="1" I="0.00" A="0.50" D="0.50" zone="ok" reachable="1" isolated="1"/>
<m path="./bench/h4fixtures/cppvex" ca="0" ce="0" types="0" abstract="0" I="0.00" A="0.00" D="1.00" zone="n/a" reachable="1" isolated="1"/>
<m path="./bench/h4fixtures/csharp" ca="0" ce="0" types="3" abstract="0" I="0.00" A="0.00" D="1.00" zone="pain" reachable="1" isolated="1"/>
<m path="./bench/h4fixtures/go" ca="0" ce="0" types="1" abstract="0" I="0.00" A="0.00" D="1.00" zone="pain" reachable="1" isolated="1"/>
<m path="./bench/h4fixtures/go2" ca="0" ce="0" types="1" abstract="0" I="0.00" A="0.00" D="1.00" zone="pain" reachable="1" isolated="1"/>
<m path="./bench/h4fixtures/java" ca="0" ce="0" types="4" abstract="0" I="0.00" A="0.00" D="1.00" zone="pain" reachable="1" isolated="1"/>
<m path="./bench/h4fixtures/js" ca="0" ce="0" types="2" abstract="0" I="0.00" A="0.00" D="1.00" zone="pain" reachable="1" isolated="1"/>
<m path="./bench/h4fixtures/objc" ca="0" ce="0" types="1" abstract="0" I="0.00" A="0.00" D="1.00" zone="pain" reachable="1" isolated="1"/>
<m path="./bench/h4fixtures/python" ca="0" ce="0" types="3" abstract="0" I="0.00" A="0.00" D="1.00" zone="pain" reachable="1" isolated="1"/>
<m path="./bench/h4fixtures/ruby" ca="0" ce="0" types="1" abstract="0" I="0.00" A="0.00" D="1.00" zone="pain" reachable="1" isolated="1"/>
<m path="./bench/h4fixtures/rust" ca="0" ce="0" types="1" abstract="0" I="0.00" A="0.00" D="1.00" zone="pain" reachable="1" isolated="1"/>
<m path="./bench/h4fixtures/swift" ca="0" ce="0" types="3" abstract="0" I="0.00" A="0.00" D="1.00" zone="pain" reachable="1" isolated="1"/>
<m path="./bench/h4fixtures/ts" ca="0" ce="0" types="2" abstract="0" I="0.00" A="0.00" D="1.00" zone="pain" reachable="1" isolated="1"/>
<m path="./bench/headtohead" ca="0" ce="0" types="0" abstract="0" I="0.00" A="0.00" D="1.00" zone="n/a" reachable="1" isolated="1"/>
<m path="./bench/locbench" ca="0" ce="0" types="0" abstract="0" I="0.00" A="0.00" D="1.00" zone="n/a" reachable="1" isolated="1"/>
<m path="./bench/locbench/results/r1_anchorhop" ca="0" ce="0" types="0" abstract="0" I="0.00" A="0.00" D="1.00" zone="n/a" reachable="1" isolated="1"/>
<m path="./bench/locbench/results/r1cpp_anchorhop" ca="0" ce="0" types="0" abstract="0" I="0.00" A="0.00" D="1.00" zone="n/a" reachable="1" isolated="1"/>
<m path="./bench/multiswe" ca="0" ce="0" types="0" abstract="0" I="0.00" A="0.00" D="1.00" zone="n/a" reachable="1" isolated="1"/>
<m path="./bench/multiswe/results" ca="0" ce="0" types="0" abstract="0" I="0.00" A="0.00" D="1.00" zone="n/a" reachable="1" isolated="1"/>
<m path="./bench/recalleval" ca="0" ce="0" types="2" abstract="0" I="0.00" A="0.00" D="1.00" zone="pain" reachable="1" isolated="1"/>
… [173 more display lines; full output is 27846 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --lint`

*Built-in AST checks (c-cast, goto, unsafe-c-fn, ...).*

`````
<!-- ripwire lint: [AST]-only checks (descriptive facts, not gates). rule=the check; sev=user-rule severity; in=enclosing symbol NAME (the same spelling is a fan-in COUNT in for/pack-task/exemplar). Each rule is scanned under its OWN match budget, so no rule is ever starved by a noisier one. A rule that spends its whole budget carries capped="1" — its count= is then a FLOOR (that rule's raw captures reached the per-rule budget; only its own matches can cap it); findings_capped="1" on the root ⇒ at least one rule is a floor. Absent = nothing was capped and every count= is a total. raise the default cap with limit=N (offset=M pages). -->
<lint findings="1122" findings_capped="1">
<rule name="c-style-cast" count="242"/>
<rule name="goto" count="2"/>
<rule name="do-while" count="1"/>
<rule name="unsafe-c-fn" count="0"/>
<rule name="weak-crypto" count="0"/>
<rule name="redundant-parens" count="0"/>
<rule name="suspicious-semicolon" count="0"/>
<rule name="typedef-over-using" count="12"/>
<rule name="magic-number" count="615" capped="1"/>
<rule name="empty-catch" count="1"/>
<rule name="self-assign" count="4" capped="1"/>
<rule name="large-function" count="110"/>
<rule name="deep-nesting" count="81"/>
<rule name="inconsistent-return" count="49"/>
<rule name="unreachable-code" count="5"/>
<f rule="magic-number" p="./bench/bench_convergence.cpp:47" in="shardOf">33</f>
<f rule="magic-number" p="./bench/bench_convergence.cpp:60" in="main">1'000'000</f>
<f rule="magic-number" p="./bench/bench_convergence.cpp:60" in="main">200'000</f>
<f rule="magic-number" p="./bench/bench_convergence.cpp:60" in="main">4'000'000</f>
<f rule="magic-number" p="./bench/bench_convergence.cpp:65" in="main">24</f>
<f rule="c-style-cast" p="./bench/bench_convergence.cpp:65" in="main">(unsigned long long)( rng() % 99999983ULL )</f>
<f rule="magic-number" p="./bench/bench_convergence.cpp:65" in="main">99999983ULL</f>
<f rule="magic-number" p="./bench/bench_convergence.cpp:86" in="main">65536</f>
<f rule="magic-number" p="./bench/bench_convergence.cpp:104" in="main">65536</f>
<f rule="c-style-cast" p="./bench/bench_convergence.cpp:125" in="main">(unsigned long long)resolvedA</f>
<f rule="c-style-cast" p="./bench/bench_convergence.cpp:125" in="main">(unsigned long long)resolvedB</f>
<f rule="c-style-cast" p="./bench/bench_convergence.cpp:125" in="main">(unsigned long long)resolvedC</f>
<f rule="magic-number" p="./bench/bench_fixedstr.cpp:16" in="main">31</f>
… [1110 more display lines; full output is 97391 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --lint-rules=test/lintrulesfix/rules`

*User lint rules (YAML, ast-grep style) from a directory.*

`````
<!-- ripwire lint: [AST]-only checks (descriptive facts, not gates). rule=the check; sev=user-rule severity; in=enclosing symbol NAME (the same spelling is a fan-in COUNT in for/pack-task/exemplar). Each rule is scanned under its OWN match budget, so no rule is ever starved by a noisier one. A rule that spends its whole budget carries capped="1" — its count= is then a FLOOR (that rule's raw captures reached the per-rule budget; only its own matches can cap it); findings_capped="1" on the root ⇒ at least one rule is a floor. Absent = nothing was capped and every count= is a total. raise the default cap with limit=N (offset=M pages). -->
<lint findings="5">
<rule name="broken-query" sev="error" count="0"/>
<rule name="no-printf" sev="warn" count="5"/>
<f rule="no-printf" sev="warn" p="./test/coplintfix/position.cpp:41" in="demo">use LOG() instead of printf</f>
<f rule="no-printf" sev="warn" p="./test/coplintfix/safe.cpp:15" in="safe_demo">use LOG() instead of printf</f>
<f rule="no-printf" sev="warn" p="./test/coplintfix/safe.cpp:27" in="safe_demo">use LOG() instead of printf</f>
<f rule="no-printf" sev="warn" p="./test/lintrulesfix/sample.cpp:8" in="greet">use LOG() instead of printf</f>
<f rule="no-printf" sev="warn" p="./test/usesfix/store.cpp:24" in="run">use LOG() instead of printf</f>
</lint>
`````

stderr:

`````
ripwire: lint-rules: test/lintrulesfix/rules/malformed.yaml:5: expected 'key: value' — file skipped
[math degraded] lint-rules: malformed rule file skipped  (lintrules.h:227, auto rw::parseLintRuleFile(const std::string &, std::string_view, std::vector<LintRule> &)::(anonymous class)::operator()(std::size_t, const char *) const — logged once per site)
ripwire: AST query did not compile for any grammar: (this_is_not_a_real_node @x @@@ ((( )
`````

## `./build/ripwire . --communities`

*Cluster the call graph into cohesive modules.*

`````
<!-- ripwire communities: cohesive call-graph modules (Louvain); bridge=cross-module edges; isolated=call-graph-edgeless symbols; drill= names the verb that takes an id= from a row below. On each module row size= is its TRUE member count while shown=/capped= describe the member list printed here: this listing is fixed at the 5 top-ranked members and is NOT widened by limit=/offset= (those page the MODULE rows). capped=1 means members were dropped; drill= names the verb that pages the full member list of one module. raise the default cap with limit=N (offset=M pages). -->
<communities drill="--community=ID" modules="619" shown_modules="30" modules_capped="1" bridges="1180" shown_bridges="12" bridges_capped="1" isolated="3379" isolated_decl="675" isolated_header="561" isolated_source="1380" isolated_doc="763" connected_singletons="0" symbols="6432">
<community id="182" size="323" dir="./src" label="./src::relForHash@arch.h:434:23902" shown="5" capped="1">
<member t="method" n="push_back" p="./src/svector.h:76"/>
<member t="method" n="buf" p="./src/svector.h:37"/>
<member t="method" n="buf" p="./src/svector.h:38"/>
<member t="method" n="grow" p="./src/svector.h:39"/>
<member t="method" n="end" p="./src/svector.h:80"/>
</community>
<community id="961" size="264" dir="./src" label="./src::canonicalId@resolve.h:926:55337" shown="5" capped="1">
<member t="method" n="empty" p="./src/scipoverlay.h:81"/>
<member t="method" n="empty" p="./src/notes.h:337"/>
<member t="fn" n="utf8SeqLen" p="./src/jsonesc.h:51"/>
<member t="fn" n="cappedEcho" p="./src/mcprefusal.h:290"/>
<member t="fn" n="canonicalId" p="./src/resolve.h:926"/>
</community>
<community id="952" size="53" dir="./src" label="./src::str@ingest.cpp:887:55947" shown="5" capped="1">
<member t="method" n="u32" p="./src/ingest.cpp:885"/>
<member t="method" n="str" p="./src/ingest.cpp:887"/>
<member t="method" n="u32" p="./src/ingest.cpp:899"/>
<member t="method" n="u8" p="./src/ingest.cpp:884"/>
<member t="method" n="view" p="./src/ingest.cpp:901"/>
</community>
<community id="956" size="46" dir="./src" label="./src::lexicalNormalize@resolve.h:78:6054" shown="5" capped="1">
<member t="method" n="size" p="./src/svector.h:77"/>
<member t="fn" n="lexicalNormalize" p="./src/resolve.h:78"/>
<member t="fn" n="buildPreciseIncludeAdj" p="./src/resolve.h:771"/>
<member t="fn" n="includerDir" p="./src/resolve.h:167"/>
<member t="fn" n="hex4" p="./src/mcpjson.h:26"/>
</community>
… [195 more display lines; full output is 15509 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --zoom`

*Nested module hierarchy (multi-level Louvain) + cross-module bridges.*

`````
<!-- ripwire zoom: NESTED module hierarchy (multi-level Louvain); indent = one level deeper; module = dominant-dir(symbol-count); leaf lists top-ranked symbols; bridge = cross-top-module call traffic. symbols= is the whole corpus; isolated= is the symbols in NO top-level module (a group of one — the same rule that makes top_modules= count only groups of 2 or more), and they reconcile exactly: symbols= equals isolated= plus the sum of the TOP-LEVEL size= values, every one of them, including any this page did not print. On a level-0 module size= is its true member count and shown=/capped= describe the member list printed here, which is fixed at the 5 top-ranked members and is not widened by limit=/offset= (those page the TOP-LEVEL modules); the community drill verb pages one module's full member list by its level-0 id. A module above level 0 lists every child module, so it carries no shown=/capped= pair. -->
<zoom levels="4" top_modules="228" symbols="6432" isolated="3379">
<module level="3" id="135" size="1867" dir="./src">
<module level="2" id="160" size="1573" dir="./src">
<module level="1" id="165" size="1130" dir="./src">
<module level="0" id="182" size="323" dir="./src" shown="5" capped="1">
<member t="method" n="push_back" p="./src/svector.h:76"/>
<member t="method" n="buf" p="./src/svector.h:37"/>
<member t="method" n="buf" p="./src/svector.h:38"/>
<member t="method" n="grow" p="./src/svector.h:39"/>
<member t="method" n="end" p="./src/svector.h:80"/>
</module>
<module level="0" id="961" size="264" dir="./src" shown="5" capped="1">
<member t="method" n="empty" p="./src/scipoverlay.h:81"/>
<member t="method" n="empty" p="./src/notes.h:337"/>
<member t="fn" n="utf8SeqLen" p="./src/jsonesc.h:51"/>
<member t="fn" n="cappedEcho" p="./src/mcprefusal.h:290"/>
<member t="fn" n="canonicalId" p="./src/resolve.h:926"/>
</module>
<module level="0" id="952" size="53" dir="./src" shown="5" capped="1">
<member t="method" n="u32" p="./src/ingest.cpp:885"/>
<member t="method" n="str" p="./src/ingest.cpp:887"/>
<member t="method" n="u32" p="./src/ingest.cpp:899"/>
<member t="method" n="u8" p="./src/ingest.cpp:884"/>
<member t="method" n="view" p="./src/ingest.cpp:901"/>
</module>
<module level="0" id="956" size="46" dir="./src" shown="5" capped="1">
<member t="method" n="size" p="./src/svector.h:77"/>
<member t="fn" n="lexicalNormalize" p="./src/resolve.h:78"/>
<member t="fn" n="buildPreciseIncludeAdj" p="./src/resolve.h:771"/>
… [4725 more display lines; full output is 231550 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --report`

*Architecture summary (modules, god-files, cycles) as markdown.*

`````
<!-- ripwire markdown: no run of 4-or-more backticks in this output — safe to embed inside a wider fence -->

# ripwire architecture report

836 files · 6432 symbols · 8733 edges · 619 modules (3379 call-graph isolated)

Call-graph isolate provenance: 675 declaration, 561 header, 1380 source, 763 document; 0 connected Louvain singletons

## Modules (call-graph clusters; showing 12 of 619)
- **./src::relForHash@arch.h:434:23902** — 323 symbols
- **./src::canonicalId@resolve.h:926:55337** — 264 symbols
- **./src::str@ingest.cpp:887:55947** — 53 symbols
- **./src::lexicalNormalize@resolve.h:78:6054** — 46 symbols
- **./src::escapeXml@serialize.h:112:7123** — 33 symbols
- **./src/infra::leaf_at@dynamic_map.hpp:372:18374** — 33 symbols
- **./src::min@infra/fastmath.h:218:11498** — 27 symbols
- **./src::cleanSig@serialize.h:1569:110263** — 16 symbols
- **./src/infra::events_shown@profileScope.h:657:22463** — 15 symbols
- **./src::write@serialize.h:302:19899** — 14 symbols
- **./src::peek@search.h:430:22425** — 14 symbols
- **./test/callformfix/csharp::CondChain@Main.cs:11:383** — 14 symbols

## God files (most depended-on; showing 10 of 124)
- `./src/model.h` — 50 dependents
- `./src/graph.h` — 23 dependents
- `./src/serialize.h` — 20 dependents
- `./src/arch.h` — 18 dependents
- `./src/jsonesc.h` — 13 dependents
- `./src/ingest.h` — 12 dependents
- `./src/quality.h` — 12 dependents
… [29 more lines, 2903 bytes total]
`````

## `./build/ripwire . --seams`

*Cross-module call seams no test reaches. NOW carries seam_pairs/shown/capped.*

`````
<!-- ripwire seams: cross-directory call edges NO test reaches (untested integration seams; a fact, not a mandate). module = parent dir; seam = caller-dir -> callee-dir, spelled from= and to=. Each seam pages its own edge rows with shown=/capped=; an edge names caller= at site p= calling callee= at site cp=. UNIT: untested= here counts cross-directory call EDGES. The test gate verb spells untested= over impacted SYMBOLS and the flip verb over the defs a gate lights, so the three numbers count three different things and must never be compared or summed across verbs. raise the default cap with limit=N (offset=M pages) -->
<seams modules="198" bridges="412" untested="270" test_files="630" seam_pairs="22" shown="20" capped="1">
<seam from="./src" to="./src/infra" untested="174" shown="5" capped="1">
<edge caller="ensureFileLoaded" p="./src/layout.h:987" callee="clear" cp="./src/infra/dynamic_map.hpp:1265"/>
<edge caller="skipInert" p="./src/layout.h:178" callee="min" cp="./src/infra/fastmath.h:218"/>
<edge caller="getIndex" p="./src/mcpindex.h:734" callee="clear" cp="./src/infra/dynamic_map.hpp:1265"/>
<edge caller="readByteSafeLine" p="./src/stdinline.h:44" callee="clear" cp="./src/infra/dynamic_map.hpp:1265"/>
<edge caller="selectorFaultClause" p="./src/selectorrefuse.h:81" callee="min" cp="./src/infra/fastmath.h:218"/>
</seam>
<seam from="./bench" to="./src" untested="22" shown="5" capped="1">
<edge caller="runSorter" p="./bench/bench_sort_large.cpp:140" callee="push_back" cp="./src/svector.h:76"/>
<edge caller="runScoreSorter" p="./bench/bench_sort_large.cpp:210" callee="push_back" cp="./src/svector.h:76"/>
<edge caller="benchAlternating" p="./bench/bench_radix_ab.cpp:86" callee="push_back" cp="./src/svector.h:76"/>
<edge caller="isSorted" p="./bench/bench_sort_large.cpp:42" callee="lessByFromTo" cp="./src/sortutil.h:113"/>
<edge caller="sameSortedOutput" p="./bench/bench_sort_large.cpp:50" callee="push_back" cp="./src/svector.h:76"/>
</seam>
<seam from="./bench" to="./src/infra" untested="20" shown="5" capped="1">
<edge caller="aggregateMax" p="./bench/bench_ordered_map.cpp:85" callee="max" cp="./src/infra/fastmath.h:221"/>
<edge caller="legacySortSmall" p="./bench/bench_radix_ab.cpp:34" callee="swap" cp="./src/infra/dynamic_map.hpp:1252"/>
<edge caller="infraSortSmall" p="./bench/bench_radix_ab.cpp:73" callee="sortKeySmall" cp="./src/infra/radixSort.h:52"/>
<edge caller="sameSortedOutput" p="./bench/bench_sort_large.cpp:50" callee="clear" cp="./src/infra/dynamic_map.hpp:1265"/>
<edge caller="perSymbolDynamicSeen" p="./bench/bench_ordered_map.cpp:156" callee="end" cp="./src/infra/dynamic_map.hpp:938"/>
</seam>
<seam from="./bench" to="./test/regexfix" untested="7" shown="5" capped="1">
<edge caller="run_session" p="./bench/spec_trace.py:143" callee="open" cp="./test/regexfix/beta.py:6"/>
<edge caller="mine_session_file" p="./bench/mine_traces.py:169" callee="open" cp="./test/regexfix/beta.py:6"/>
<edge caller="read_whole" p="./bench/bench_proof.py:27" callee="open" cp="./test/regexfix/beta.py:6"/>
<edge caller="main" p="./bench/calib_json.py:16" callee="open" cp="./test/regexfix/beta.py:6"/>
<edge caller="main" p="./bench/mine_traces.py:348" callee="open" cp="./test/regexfix/beta.py:6"/>
</seam>
… [74 more display lines; full output is 9619 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --mermaid`

*Module (directory) dependency graph as a Mermaid diagram.*

`````
%% ripwire --mermaid: module (directory) dependency graph — node = dir (symbol count), edge = inter-module calls (>= 3). Render at mermaid.live.
flowchart LR
  subgraph sg0 ["src"]
    n48["src<br/>2265"]
    n49["src/infra<br/>407"]
  end
  subgraph sg1 ["test"]
    n50["test<br/>1494"]
    n132["test/legofix<br/>60"]
    n69["test/callformfix/cpp<br/>36"]
    n131["test/layoutfix<br/>32"]
    n176["test/rustqualfix/src<br/>27"]
    n91["test/cppqualfix<br/>23"]
    n75["test/callformfix/java<br/>22"]
    n90["test/cppqualdecoyfix<br/>22"]
    n160["test/redactfix<br/>22"]
    n178["test/skillfix<br/>22"]
    n80["test/callformfix/rust/src<br/>20"]
    n157["test/qualnewfix<br/>20"]
    n177["test/scipfix<br/>20"]
    n103["test/docdriftfix<br/>19"]
    n73["test/callformfix/csharp<br/>18"]
    n89["test/cppopfix<br/>18"]
    n82["test/callformfix/typescript<br/>17"]
  end
  subgraph sg2 ["bench"]
    n1["bench<br/>205"]
    n21["bench/locbench<br/>104"]
    n23["bench/locbench/results/r1cpp_anchorhop<br/>85"]
    n20["bench/headtohead<br/>72"]
… [17 more lines, 1457 bytes total]
`````

## `./build/ripwire . --owners`

*Bus-factor: recency-weighted author ownership per file.*

`````
<!-- ripwire owners: recency-weighted author ownership (half-life=6mo). bf=1 = one person holds >80% of weighted commits (bus-factor risk); authors=1 files fold into <uniform/> below; pass detail=1 for the full per-file listing. files= means two different things by DEPTH here and is deliberately not renamed: on the ROOT it is how many files were ANALYSED; on the <uniform/> fold it is how many of them collapsed into that one row. With a SYM, of= echoes it and defs= is how many DEFINITIONS that name has: this report covers the file holding the FIRST of them (lowest node id, the same pick around and lego make), so defs= above 1 means the other definitions' files were NOT analysed. Qualify with file:name to choose one -->
<!-- at= is the git commit these numbers were computed at; a trailing +dirty means the working tree differed from that commit, so the numbers describe the tree, not the commit -->
<owners files="836" at="1dc07e27a+dirty">
<uniform authors="1" bf="1" share="1.00" files="364"/>
<f p="./SECURITY.md" authors="2" bf="0" top="quaterniongames@gmail.com" share="0.50"/>
<f p="./THIRD_PARTY.md" authors="2" bf="0" top="quaterniongames@gmail.com" share="0.67"/>
<f p="./bench/ANSWERQUALITY.md" authors="2" bf="0" top="quaterniongames@gmail.com" share="0.50"/>
<f p="./bench/BENCHMARK.md" authors="2" bf="0" top="quaterniongames@gmail.com" share="0.50"/>
<f p="./bench/PROFILE.md" authors="2" bf="0" top="quaterniongames@gmail.com" share="0.50"/>
<f p="./bench/agentloop/README.md" authors="2" bf="0" top="quaterniongames@gmail.com" share="0.50"/>
<f p="./bench/agentloop/analyze.py" authors="2" bf="0" top="quaterniongames@gmail.com" share="0.50"/>
<f p="./bench/agentloop/run_agentloop.py" authors="2" bf="0" top="quaterniongames@gmail.com" share="0.50"/>
<f p="./bench/agentloop/select_tasks.py" authors="2" bf="0" top="quaterniongames@gmail.com" share="0.50"/>
<f p="./bench/bench_convergence.cpp" authors="2" bf="0" top="quaterniongames@gmail.com" share="0.67"/>
<f p="./bench/bench_fixedstr.cpp" authors="2" bf="0" top="quaterniongames@gmail.com" share="0.50"/>
<f p="./bench/bench_ordered_map.cpp" authors="2" bf="0" top="quaterniongames@gmail.com" share="0.50"/>
<f p="./bench/bench_proof.py" authors="2" bf="0" top="quaterniongames@gmail.com" share="0.50"/>
<f p="./bench/bench_radix_ab.cpp" authors="2" bf="0" top="quaterniongames@gmail.com" share="0.67"/>
<f p="./bench/bench_sort_large.cpp" authors="2" bf="0" top="quaterniongames@gmail.com" share="0.67"/>
<f p="./bench/bench_svector3.cpp" authors="2" bf="0" top="quaterniongames@gmail.com" share="0.50"/>
<f p="./bench/cppbench/README.md" authors="2" bf="0" top="quaterniongames@gmail.com" share="0.50"/>
<f p="./bench/cppbench/run_cppbench.py" authors="2" bf="0" top="quaterniongames@gmail.com" share="0.50"/>
<f p="./bench/h4fixtures/cpp/main.cpp" authors="2" bf="0" top="quaterniongames@gmail.com" share="0.50"/>
<f p="./bench/h4fixtures/cppvex/vex.cpp" authors="2" bf="0" top="quaterniongames@gmail.com" share="0.50"/>
<f p="./bench/headtohead/README.md" authors="2" bf="0" top="quaterniongames@gmail.com" share="0.50"/>
<f p="./bench/headtohead/REPORT.md" authors="2" bf="0" top="quaterniongames@gmail.com" share="0.50"/>
<f p="./bench/headtohead/headtohead_results.json" authors="2" bf="0" top="quaterniongames@gmail.com" share="0.50"/>
<f p="./bench/headtohead/loss_buckets.json" authors="2" bf="0" top="quaterniongames@gmail.com" share="0.50"/>
<f p="./bench/locbench/README.md" authors="2" bf="0" top="quaterniongames@gmail.com" share="0.50"/>
<f p="./bench/locbench/anchorhop_calib.json" authors="2" bf="0" top="quaterniongames@gmail.com" share="0.50"/>
… [447 more display lines; full output is 46518 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --dead-code=src`

*High-confidence internal functions with no caller. NOTE the filter is a path-COMPONENT match: 'src' matches any .../src/... segment; use ./src to pin the root directory.*

`````
<!-- ripwire dead-code: high-confidence source functions with internal linkage and no caller in the indexed tree. A bare-name filter matches by path COMPONENT: filter="src" keeps any path with a src segment at any depth (test/x/src/y.cpp included); anchor with ./ (filter="./src") to pin the root-level directory only. Graph evidence is local to the indexed tree; verify before deleting -->
<dead-code count="1" confidence="high" evidence="internal-linkage+zero-callers" filter="src">
<d n="unused_helper" t="fn" p="./test/archmetricsfix/src/orphan/util.cpp" l="1"/>
</dead-code>
`````

## `./build/ripwire . --exercises=test/regression.sh`

*Which symbols a TEST FILE exercises — the reverse direction of --affected.*

`````
<!-- ripwire exercises: the NON-TEST symbols this test transitively calls into — what it covers (the inverse of the affected verb). <t> = the seed test files the pattern matched; <s> = the covered symbols, PageRank desc. harness=script|mixed says the seed set contains shell gates, whose subprocess coverage this walk cannot see -->
<exercises of="test/regression.sh" seed_files="1" shown_seed_files="1" seed_files_capped="0" test_symbols="2" reaches="0" harness="script" note="a shell gate invokes the compiled binary as a subprocess; script-to-binary edges are not modelled, so reaches= counts call-graph reach only and cannot see  … [line truncated: 49 more bytes on this line]
<t p="./test/regression.sh"/>
</exercises>
`````

## `./build/ripwire . --community=0`

*Drill into ONE call-graph community by id — the drill= the --communities output itself advertises.*

`````
<!-- ripwire community: ONE module from the communities/zoom partition — its ranked members and its bridge edges to other modules. size= is the module's TRUE member count; shown=/capped= are this page. partition= is the FULL label space (every id 0..partition-1, incl. isolated singletons) — the range the id= argument ranges over; modules= counts the NON-isolated communities (size>=2), the SAME predicate the communities-listing verb's modules= uses, so parent and child agree. -->
<community id="0" size="1" dir="." label=".::AGENTS@AGENTS.md:1:0" bridges="0" shown_bridges="0" bridges_capped="0" partition="3998" modules="619" shown="1" capped="0">
<member t="sec" n="AGENTS" p="./AGENTS.md:1"/>
</community>
`````

## `./build/ripwire . --quality-delta`

*On a CLEAN tree: nothing got worse, exit 0. The gating shape is in the sandbox section below.*

**exit code: 2**

`````
<!-- ripwire quality-delta: only what a change made WORSE against the floor named by baseline= below. FOUR floors, and they are not interchangeable: sidecar = the pinned .ripwire_quality_baseline snapshot, honored only because it was pinned at the CURRENT git HEAD; git-HEAD = no sidecar existed, so the working tree was auto-compared against the HEAD tree; git-HEAD (stale sidecar removed) = a sidecar existed, was pinned at a DIFFERENT sha, and this run DELETED it from your working tree before falling back to HEAD (re-pin with quality-baseline); git-HEAD (stale sidecar ignored) = same staleness verdict, but the file was left on disk (the read-only MCP arm, or an unlink that failed). Only the first is a floor YOU chose; the other three compare against HEAD, so anything already committed cannot appear. at= is the git commit (plus a dirty marker when the working tree differs) this list was computed at. Findings: complexity over the ccx bar, verbosity (LOC)/nesting/params regressions, new duplication, newly-dead, new public api-surface (contract drift), error-masking, short-horizon churn, new clone of a reused helper. THREE independent axes, applied in this order: (1) acked findings are suppressed entirely (acked= counts them, honestly); (2) ORIGIN — a finding on a symbol that EXISTED at the baseline is preexisting-worse (no origin= attribute), one that exists only because the code is NEW carries origin="new-symbol"; (3) MATERIALITY — a small numeric delta is sev="minor". EXIT 2 fires only on preexisting-worse AND major, i.e. gating="N" above; new-symbol rows never gate. Clone kinds classify by their member set (a group is new-symbol only if EVERY member is new); short-horizon-churn is preexisting by construction. exit 0 is NOT a verdict on the new-symbol rows — nothing that existed got worse, but the new debt is yours: read them. LIMIT: origin is canonId identity (path::scope::name), so a RENAMED or MOVED symbol reads as new — a regression carried in with a move classifies new-symbol and will not gate. Descriptive: weigh + fix the real ones, do not game the number (a wrong abstraction beats a low score). Each row carries kind= (which of the measured axes regressed) and sym= (the canonical id it regressed on), plus p="path:line" (root-relative; the first-sorting member for the clone kinds; omitted, never faked, when no locator resolves), and every row the header's gating= counter counts also carries a gating attribute set to 1 — those are the rows the exit code fires on, and they are now marked positively rather than by the ABSENCE of sev/origin. (This sentence deliberately spells no attribute=value literal: the header counters are parsed by grep in several gates, and a quoted numeric example here would be matched first.) -->
<quality-delta baseline="git-HEAD" regressions="2" minor="0" acked="0" preexisting-worse="2" new-symbol="0" gating="2" at="1dc07e27a+dirty">
<r kind="short-horizon-churn" sym="src/cli.h::Config::Config" was="0" now="3" churn="self" p="src/cli.h:24" gating="1"/>
<r kind="short-horizon-churn" sym="src/cli.h::rw::printUsage" was="0" now="3" churn="self" p="src/cli.h:504" gating="1"/>
</quality-delta>
`````

stderr:

`````
ripwire: no ./.ripwire_quality_baseline — auto-comparing the working tree vs git HEAD (commit the baseline with --quality-baseline to pin it)
ripwire: --quality-delta gating: 2 preexisting-worse major finding(s); first: short-horizon-churn ./src/cli.h::Config::Config at src/cli.h:24 (was=0 now=3)
`````

## `./build/ripwire . --edit-check=rankGraphTeleport`

*Fast per-symbol post-edit contract check vs git HEAD (unchanged on a clean tree).*

`````
<!-- ripwire edit-check: SYM's contract (param count + publicness) NOW vs git HEAD — unchanged/new-symbol/contract-change — plus its 1-hop callers. A caller is flagged incompatible="1" when its argument count was reliably counted and NO definition in the folded set could accept it: every one has a FIXED arity that disagrees. A variadic, defaulted or implicit-receiver definition (a Python/Ruby method, whose params counts the self/cls the call site never writes) has no fixed arity and is never flagged. That makes the ARITY half one-sided — a call the compared definitions could accept is never flagged — but it is NOT a proof that the call site binds to THIS definition. Call edges are matched by NAME, so a receiver-qualified call to a same-named callee this tool does not index (a standard-library or third-party method) is measured against the one definition it does index; a clean, compiling tree can therefore carry a nonzero incompatible= with nothing edited at all, and on a widely-shared name it can be most of that name's callers. Read incompatible= as a fact about the tree as it stands — call sites worth OPENING, not a verdict — and status= as a fact about the edit. Warm path hits the qheadsnap/qsnap cache — never a full quality-delta style recompute. defs= is how many DEFINITIONS at this site (same file, same scope, same name — the overload set) are folded into this one contract; a selector matching more than one SITE is refused instead, so defs= only ever counts overloads. params_was and params_now are the MAX over that set on each side (the same MAX the baseline snapshot stores), and publicness is the OR. That MAX has TWO consequences, in opposite directions. It can read like a break and not be one: adding a WIDER overload beside an unchanged one raises params_now with no existing definition altered, so it reports status="contract-change" with incompatible="0" and a def row still carrying the old parameter count — no seen caller breaks. And it can read like safety and not be: REMOVING an overload whose parameter count is BELOW the MAX moves neither number, because the MAX survives on both sides, while the call site that used the removed definition no longer binds. defs_was=/defs_now= is what closes that: the count of definitions sharing this symbol's CANONICAL ID on each side. That population is the one the baseline snapshot buckets by, so the two numbers answer the same question and are equal on an unedited tree — it is deliberately NOT the root's defs=, which is the same bucket narrowed to this FILE (a contract is per definition site), so where a scope-less name also exists in another file defs= is the smaller of the two. status is therefore the join of THREE was-vs-now facts — the params MAX, publicness, and the definition COUNT — and change= names which of them carried it. change= adds broken-callers when a seen caller is also flagged, but never on its own — for the reason stated at the top: incompatible= describes the TREE and status= describes the EDIT, so a headline must not turn on it. RESIDUAL: an overload whose arity changes BELOW the MAX while the COUNT stays the same moves none of the three. The root's incompatible= is the COUNT of flagged callers (a c row's incompatible="1" is the per-caller flag). p= is the definition the selector resolved to; when defs is above 1 EVERY folded definition is listed as its own def row (p=, t=, params=), which is what tells a widened single definition apart from an added overload. At defs="1" no def row is emitted: the root's own p=/t= is that definition, and params_now is its parameter count. counts_floor="1" means every count on this element is a FLOOR, never a total. Call edges are extracted from source text by NAME, so a call that reaches its target through dynamic dispatch (a virtual, interface or duck-typed receiver), a callback or function pointer, a macro-generated call site, or a declaration that parses without a call expression (C++ most-vexing-parse) contributes no edge and is missing here. Read a zero as "none found", never as "none exists". COUNTING UNIT, and it differs by verb — which is why two of them report different numbers for one symbol. The callers, callees, edit-check, graph-query and pr-context counts are DISTINCT SYMBOLS: repeated calls from one caller, and calls to two overloads of one name, collapse into ONE row, their multiplicity surviving only in the call graph's edge weight. The reach counts (impact's reaches=, pr-context's dependents=) are the size of a transitive reach SET, each symbol counted once — not a count of calls or edges. The uses verb counts call SITES, one row per occurrence, so a larger count= there for the same symbol is these units agreeing, not disagreeing. The map header's edges= is a unit again different — distinct (caller,callee) PAIRS — and that document carries neither this marker nor this clause, so its numbers answer a different question. -->
<edit-check sym="rankGraphTeleport" t="fn" p="./src/graph.h:1278" status="unchanged" defs="1" callers="6" incompatible="0" at="1dc07e27a+dirty" counts_floor="1">
<c n="runEval" p="./src/eval.h:133"/>
<c n="rankGraph" p="./src/graph.h:1304"/>
<c n="anchoredLexicalRank" p="./src/graph.h:1553"/>
<c n="churnRankedGraph" p="./src/main.cpp:7246"/>
<c n="runDefaultMap" p="./src/main.cpp:7276"/>
<c n="getIndex" p="./src/mcpindex.h:734"/>
</edit-check>
`````

## `./build/ripwire . --pr-context`

*No-LLM review-evidence bundle for the working-tree diff (clean tree = empty).*

`````
<!-- ripwire pr-context: no-LLM review-evidence bundle per changed file — defined symbols, their callers, blast radius (transitive dependents), affected tests, co-change partners not in the diff, and owners. base=working-tree. skipped_mode_only=diffs that changed a file's MODE and nothing else (e.g. chmod) excluded from the changed set; a pure RENAME is content-identical too but is NOT excluded — it is a changed file, listed at its new path. files= means two different things by DEPTH here and is deliberately not renamed (15 consumers read the root one): on the ROOT it is the CHANGED file count; on each <impact/> child it is the distinct files dependents= reaches (changed + non-changed), so dependents="0" implies files="0" and vice versa — never an impossible-looking dependents>0/files=0. files_other= on the same <impact/> is the non-changed subset (a changed file's dependents inside OTHER changed files have no <f> row of their own — they are already shown as their own <file> section); it is NOT the <f> row count — see the row-cap sentence below. Files are ordered by BLAST RADIUS (transitive dependents descending, path breaking ties), not alphabetically. sections= on changed-symbols counts a doc file's headings, collapsed into that number instead of one callers-zero row each; count= still counts every INDEXED symbol, sections included, so count minus sections is the number of rows that follow. Every nested list below is a TOP-N subset of its element's own total, fixed per element (impact <f> at 20, per-symbol <caller> at 12, cochange <partner> at 12, tests <test> at 40, owners <author> at 5 — the L0 defaults; max-tokens only lowers these further via the trim ladder, nothing raises them past L0): each capped element carries its own shown=/capped= pair so the cut is never silent — for the untrimmed list use impact=SYM/callers=SYM (blast radius/callers), affected=FILE or situ (tests), cochange (partners), or owners (authors) instead. direction= names which SIDE this bundle reviews (worktree-since-head, head-since-fork, head-since-ref-tip); a no-ref-work row says the base ref's tip IS the merge base, i.e. it carries no divergent work of its own. deterministic. counts_floor="1" means every count on this element is a FLOOR, never a total. Call edges are extracted from source text by NAME, so a call that reaches its target through dynamic dispatch (a virtual, interface or duck-typed receiver), a callback or function pointer, a macro-generated call site, or a declaration that parses without a call expression (C++ most-vexing-parse) contributes no edge and is missing here. Read a zero as "none found", never as "none exists". COUNTING UNIT, and it differs by verb — which is why two of them report different numbers for one symbol. The callers, callees, edit-check, graph-query and pr-context counts are DISTINCT SYMBOLS: repeated calls from one caller, and calls to two overloads of one name, collapse into ONE row, their multiplicity surviving only in the call graph's edge weight. The reach counts (impact's reaches=, pr-context's dependents=) are the size of a transitive reach SET, each symbol counted once — not a count of calls or edges. The uses verb counts call SITES, one row per occurrence, so a larger count= there for the same symbol is these units agreeing, not disagreeing. The map header's edges= is a unit again different — distinct (caller,callee) PAIRS — and that document carries neither this marker nor this clause, so its numbers answer a different question. -->
<pr-context base="working-tree" direction="worktree-since-head" files="3" skipped_mode_only="0" at="1dc07e27a+dirty" counts_floor="1">
<file p="./test/showcase_capture.py" symbols="57">
<impact dependents="16" files="4" files_other="4" shown="4" capped="0">
<f p="./bench/cppbench/run_cppbench.py" deps="5"/>
<f p="./bench/multiswe/run_multiswe.py" deps="5"/>
<f p="./bench/locbench/run_locbench.py" deps="3"/>
<f p="./bench/mine_traces.py" deps="3"/>
</impact>
<tests count="0" shown="0" capped="0">
</tests>
<changed-symbols count="57">
<s t="var" n="REPO" p="./test/showcase_capture.py:8" callers="0" shown="0" capped="0">
</s>
<s t="var" n="SCRATCH" p="./test/showcase_capture.py:9" callers="0" shown="0" capped="0">
</s>
<s t="var" n="BIN" p="./test/showcase_capture.py:10" callers="0" shown="0" capped="0">
</s>
<s t="var" n="ABIN" p="./test/showcase_capture.py:11" callers="0" shown="0" capped="0">
</s>
<s t="var" n="DIRTY" p="./test/showcase_capture.py:12" callers="0" shown="0" capped="0">
</s>
<s t="var" n="AUX" p="./test/showcase_capture.py:13" callers="0" shown="0" capped="0">
</s>
<s t="var" n="TRACE" p="./test/showcase_capture.py:19" callers="0" shown="0" capped="0">
</s>
<s t="var" n="trace_path" p="./test/showcase_capture.py:29" callers="0" shown="0" capped="0">
</s>
<s t="var" n="_batchWord1" p="./test/showcase_capture.py:38" callers="0" shown="0" capped="0">
</s>
… [255 more display lines; full output is 16629 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --pr-context=r29-planlanes`

*The BASEREF form: diffed against merge-base(r29-planlanes, HEAD), never the ref tip.*

**exit code: 1**

`````
(empty)
`````

stderr:

`````
[math degraded] pr-context: the base ref does not resolve to a commit — refusing rather than handing the raw token to git  (prcontext.h:283, DiffAnchor rw::resolveDiffAnchor(const std::string &, std::string_view) — logged once per site)
ripwire: --pr-context: unknown base ref 'r29-planlanes'
`````

## `./build/ripwire . --merge-scout=r28-parseargs,r29-planlanes`

*Pairwise cross-branch conflict sites + suggested landing order.*

**exit code: 1**

`````
(empty)
`````

stderr:

`````
ripwire: --merge-scout: unknown ref 'r28-parseargs'
`````

## `./build/ripwire . --stray-content=r25`

*Which r25-* refs still hold divergent authored work vs HEAD, with verdicts.*

`````
<!-- ripwire stray-content: per ref, the lines its own divergent work AUTHORED (vs its merge-base with HEAD) that the live line does NOT have. v="superseded" means the live line removed the same base code this ref removed (redone/del) — it re-implemented the work, the case `git cherry` cannot see; v="unmerged" means the work is genuinely absent; merged refs are omitted. Read-only: git cat-file/diff/ls-tree only, one batched cat-file for the whole sweep, every blob reduced once per sha. Line-granular, not semantic: see the ripwire help text for the limits. ANCHORING is a deliberate hybrid: the SCOPE is base anchored (only lines the ref itself authored vs its merge base are ever considered, so a file the ref never opened cannot appear because the live line moved), while the ABSENCE test is HEAD anchored on purpose (does the live line have this content TODAY is the question being asked, and it is only answerable against live HEAD). v="unknown" with ok="0" means this ref could NOT be analysed at all because it has no merge base with HEAD, which on a SHALLOW clone (the checkout default in CI) is every ref: it is not a claim that the ref is merged, and the fix is to deepen the clone. The four buckets are exhaustive, so unmerged plus superseded plus merged plus unknown always equals refs. SCOPE: refs/heads only, which is every local branch (worktree branches included). Remote tracking refs are NOT scanned: they mirror local ones in the usual checkout and would double every row. The consequence on a FRESH CLONE, where the branches live under refs/remotes/origin and only the checked out one has a local head, is that there is nothing here to be stray FROM; refs= is that fact as a number. TRUNCATION: a ref row ends with a more element (more files=N) when its own file listing was capped; shown plus that number equals the ref's files= total, always. That inner listing is a SECONDARY listing (it repeats complete and identical on every page) and is capped by detail, not by limit / offset, which page the OUTER ref listing and report their own shown= / capped=. -->
<stray-content head="1dc07e27a" head_ref="main" refs="0" blobs="0" unmerged="0" superseded="0" merged="0" unknown="0">
</stray-content>
`````

## `./build/ripwire . --stray-content=worktree-agent-a1`

*A ref family that IS fully merged — the omit-merged-refs contract, with the counters still reconciling against refs=.*

`````
<!-- ripwire stray-content: per ref, the lines its own divergent work AUTHORED (vs its merge-base with HEAD) that the live line does NOT have. v="superseded" means the live line removed the same base code this ref removed (redone/del) — it re-implemented the work, the case `git cherry` cannot see; v="unmerged" means the work is genuinely absent; merged refs are omitted. Read-only: git cat-file/diff/ls-tree only, one batched cat-file for the whole sweep, every blob reduced once per sha. Line-granular, not semantic: see the ripwire help text for the limits. ANCHORING is a deliberate hybrid: the SCOPE is base anchored (only lines the ref itself authored vs its merge base are ever considered, so a file the ref never opened cannot appear because the live line moved), while the ABSENCE test is HEAD anchored on purpose (does the live line have this content TODAY is the question being asked, and it is only answerable against live HEAD). v="unknown" with ok="0" means this ref could NOT be analysed at all because it has no merge base with HEAD, which on a SHALLOW clone (the checkout default in CI) is every ref: it is not a claim that the ref is merged, and the fix is to deepen the clone. The four buckets are exhaustive, so unmerged plus superseded plus merged plus unknown always equals refs. SCOPE: refs/heads only, which is every local branch (worktree branches included). Remote tracking refs are NOT scanned: they mirror local ones in the usual checkout and would double every row. The consequence on a FRESH CLONE, where the branches live under refs/remotes/origin and only the checked out one has a local head, is that there is nothing here to be stray FROM; refs= is that fact as a number. TRUNCATION: a ref row ends with a more element (more files=N) when its own file listing was capped; shown plus that number equals the ref's files= total, always. That inner listing is a SECONDARY listing (it repeats complete and identical on every page) and is capped by detail, not by limit / offset, which page the OUTER ref listing and report their own shown= / capped=. -->
<stray-content head="1dc07e27a" head_ref="main" refs="0" blobs="0" unmerged="0" superseded="0" merged="0" unknown="0">
</stray-content>
`````

## `./build/ripwire . --stray-content=r27 --plan`

*Select the genuinely-unmerged refs and feed them to merge-scout for a landing order.*

`````
<!-- ripwire landing-plan: stray-content's cheap per-blob sweep composed with merge-scout's per-arm overlap oracle — of every local branch, which still hold REAL work (v="unmerged"), which were already re-implemented on the live line (v="superseded", EXCLUDED below — landing them re-does work that is already done) or are already merged (omitted entirely, counted in merged= on the root element), and the fewest-conflicts-first order to land what remains. scouted="0" on an unmerged ref means it was NOT fed to merge-scout this run (the cost bound, not a verdict) — it is still real, unscouted work; bounded= on the root element counts them and detail lifts the bound. merge-scout is the EXPENSIVE step here (git-archive + full ingest per arm) — stray-content's own sweep is the cheap one. An undetermined row is a ref that could NOT be analysed at all (no merge base with HEAD, which on a SHALLOW clone is every ref): it is neither scouted nor excluded nor merged, because nothing was measured — treat it as unfinished business and deepen the clone, never as a clean branch. Read-only throughout: no checkout, no ref write, no working-tree mutation. The root carries BOTH head= and at= and they are the same commit: head= is the bare 9 hex chars this verb has always printed, at= is the tool wide anchor and is head= plus a "+dirty" suffix when the working tree is not clean. Prefer at= (it is the one spelling every other repo reading verb uses, and the only one that tells you whether uncommitted work was in scope); head= is kept for callers already keyed to it. -->
<landing-plan head="1dc07e27a" refs="0" unmerged="0" superseded="0" merged="0" undetermined="0" scouted="0" bounded="0" scout-ok="1" at="1dc07e27a+dirty">
</landing-plan>
`````

## `./build/ripwire . --stray-content=r25 --abi`

*Cross-branch ABI-break gate: struct byte-contract drift on each ref's AUTHORED paths.*

`````
<!-- ripwire abi: the cross-branch ABI-BREAK gate — layout(STRUCT) crossed with stray-content(BRANCH). Scope is what each ref AUTHORED: the paths `diff base..tip` reports against its own merge base, never `diff HEAD..tip` (a file the branch never opened cannot be a break the branch introduced, and on a long-lived tree that one distinction took 487 drift rows to 4). For each such path the SAME field-offset model layout uses is run LEXICALLY on the ref's git blob (never indexed) and compared against HEAD's computed fields. LISTED kinds: drift = the byte contract differs (the bug this check exists for, the only kind that exits 2); unknown = the ref-side copy could not be modelled (see ref_caveat) and is NEVER reported as unchanged; absent = the ref does not define the struct at that path. COUNTED but not listed (pass detail=N to print them): rename = identical slots and field types under different field NAMES, so every byte stayed where it was (a same-type field REORDER is lexically identical to a rename and lands here too); spelling and stub mirror layout's own harmless cases; head-moved = the ref's copy equals its own merge-base copy, so the LIVE LINE is what changed. head_only= counts candidate sites on paths only the live line touched (outside the authored scope); unmodelable= counts sites skipped because HEAD's own copy carries no baseline; every excluded row is on a counter, nothing is dropped silently. Structs that match are omitted entirely; a ref with no rows at all is counted in quiet=, and a ref whose every row is an excluded kind is counted in excluded_refs= and prints under detail=N. LIMITS: HEAD's own side is the WORKING TREE's layout answer, not a re-fetched git blob at HEAD's commit; a nested field type that ALSO changed on the ref resolves via HEAD's copy, not the ref's; the ref-side locator is index-free and file-scope (one namespace deep) only, so a struct nested in a class or wrapped in an extern C block reads absent rather than compared; the authorship anchor is per PATH, so a branch changing struct S in one file while the live line changes S's mirror in another is a merge hazard only layout(S) on the merged result can see. Single-root; read-only (cat-file/diff/merge-base only). -->
<abi head="1dc07e27a" head_ref="main" refs="0" candidates="553" compared="0" blobs="0" rows="0" shown="0" capped="0" dropped="0" excluded="0" head_only="0" unmodelable="0" unrelated="0" broken_refs="0" quiet="0" excluded_refs="0">
</abi>
`````

stderr:

`````
ripwire: --stray-content takes precedence when several verbs are given — IGNORED this run: --abi. The winner is fixed by ripwire's dispatch order, NOT by the order you typed them; pass one verb per run.
`````

## `./build/ripwire . --whereis=rankGraphTeleport`

*Which ref's tree defines or mentions SYM — HEAD first, then every local branch.*

`````
<!-- ripwire whereis: every LOCAL ref whose TREE contains this symbol, HEAD first, and within a ref SOURCE files before test files before docs, then definitions before references, then path and line. The doc demotion is ORDER ONLY: a doc line that quotes a signature still reads as a definition to the heuristic below and still says kind="def", it is simply printed after the code. kind= is answered by TWO different mechanisms, and head_labels= says which one answered for HEAD: with head_labels="index" a HEAD row is kind="def" iff the PARSED index puts a definition there (one row per index def site), while every NON-HEAD row — and every row when head_labels="lexical" (no index was supplied, the index knows no def of this name, or the working tree has drifted from HEAD) — is a LEXICAL shape heuristic over raw blob text that was never ingested: it reads a quoted signature in a doc as a definition and can miss an unusual declarator. refs_scanned= is the SCAN DENOMINATOR (how many refs besides HEAD were read), NOT a count of refs that matched — hits= and the rows are the matched set. on-head="0" alongside ref hits is the case this verb exists for: content that lives only on a branch. A TREE scan can only find content some ref still carries, so hits="0" on its own does not distinguish a name this repo never had from one it deleted; run with the with_history flag and the fate row says which, naming the commit that removed it. ANCHORING: none, by design. This verb runs no diff at all — it scans each ref's FULL tree, which is what lets it find content a branch merely INHERITED (exactly what a merge base anchored diff would exclude), so nothing here can fire merely because HEAD moved. at= is sha-only here (never +dirty): a tree scan reads committed blobs, so the working tree's cleanliness does not enter the answer. SELECTOR: this verb takes a BARE symbol name, not the file:name spelling that callers, uses, impact, around, lego and edit_check accept. A file:name spelling is searched as a LITERAL string, no tree contains it, and the result is a true but useless hits="0" shaped exactly like a name this repo never had. When that is what happened, a selector-note element says so and its retry= is the bare name to re-run with. Its absence beside hits="0" means the zero IS a measurement. SCOPE: refs/heads only, which is every local branch (worktree branches included). Remote tracking refs are NOT scanned: they mirror local ones in the usual checkout and would double every row. The consequence on a FRESH CLONE, where the branches live under refs/remotes/origin and only the checked out one has a local head, is that this verb sees essentially one tree; refs_scanned= is that fact as a number, so read it before reading hits=. TRUNCATION: the trailing more element (more hits=N) is the rows AFTER this page, so shown plus more equals the rows from this page's offset on. It is not a second cap, and not a second vocabulary to page by: it is the SAME fact shown= / capped= / next_offset= carry, restated from the other end (what this page did not print). Page with limit= and offset=; the more element is absent exactly when this page reached the end of the hit list. raise the default cap with limit=N (offset=M pages) -->
<whereis sym="rankGraphTeleport" on-head="1" refs_scanned="1" blobs="1564" hits="238" head_labels="index" shown="60" capped="1" at="1dc07e27a">
<hit ref="HEAD" tip="1dc07e27a" date="2026-07-31" p="src/graph.h" l="1278" kind="def" t="inline std::vector&lt;float&gt; rankGraphTeleport( const Graph&amp; g, const std::vector&lt;float&gt;&amp; p, float alpha = 0.85f )"/>
<hit ref="HEAD" tip="1dc07e27a" date="2026-07-31" p="src/crossref.h" l="1280" kind="ref" t="// code above the real definition: `--whereis=rankGraphTeleport` opened with three kind=&quot;def&quot; rows into"/>
<hit ref="HEAD" tip="1dc07e27a" date="2026-07-31" p="src/eval.h" l="211" kind="ref" t="const std::vector&lt;float&gt; r = rankGraphTeleport( g, diffTeleport( ing, seedMask ) );"/>
<hit ref="HEAD" tip="1dc07e27a" date="2026-07-31" p="src/graph.h" l="88" kind="ref" t="// renormalized to Σ=1 in rankGraphTeleport — so every teleport-based"/>
<hit ref="HEAD" tip="1dc07e27a" date="2026-07-31" p="src/graph.h" l="1243" kind="ref" t="// prior (never the edges) and renormalized in rankGraphTeleport. Every symbol whose name is missing from"/>
<hit ref="HEAD" tip="1dc07e27a" date="2026-07-31" p="src/graph.h" l="1307" kind="ref" t="return rankGraphTeleport( g, std::vector&lt;float&gt;( N, N ? 1.0f / float( N ) : 0.f ), alpha );"/>
<hit ref="HEAD" tip="1dc07e27a" date="2026-07-31" p="src/graph.h" l="1549" kind="ref" t="// cliff), run the EXISTING PPR machinery (rankGraphTeleport — the same biasPrior/det-gate seam every"/>
<hit ref="HEAD" tip="1dc07e27a" date="2026-07-31" p="src/graph.h" l="1575" kind="ref" t="const std::vector&lt;float&gt; ppr = rankGraphTeleport( g, p );"/>
<hit ref="HEAD" tip="1dc07e27a" date="2026-07-31" p="src/main.cpp" l="7262" kind="ref" t="std::vector&lt;float&gt; rank   = rankGraphTeleport( d.g, churnTeleportWorkspace( rootDirs, d.ing, &quot;18 months ago&quot;, &amp;hasChurnEvidence ) );"/>
<hit ref="HEAD" tip="1dc07e27a" date="2026-07-31" p="src/main.cpp" l="7270" kind="ref" t="std::vector&lt;float&gt; rank   = rankGraphTeleport( d.g, churnTeleport( d.root, d.ing, &quot;18 months ago&quot;, d.cfg.since.empty() ? nullptr : &amp;sinceScope, &amp;hasChurnEvidence ) );"/>
<hit ref="HEAD" tip="1dc07e27a" date="2026-07-31" p="src/main.cpp" l="7348" kind="ref" t="rank = rankGraphTeleport( g, diffTeleport( ing, changed ) );"/>
<hit ref="HEAD" tip="1dc07e27a" date="2026-07-31" p="src/mcpindex.h" l="785" kind="ref" t="// symbols, the rest uniform, then rankGraphTeleport (which also applies the W4-#1 name-quality biasPrior"/>
<hit ref="HEAD" tip="1dc07e27a" date="2026-07-31" p="src/mcpindex.h" l="807" kind="ref" t="ix.rank = rankGraphTeleport( ix.g, diffTeleport( ix.ing, changed ) );"/>
<hit ref="HEAD" tip="1dc07e27a" date="2026-07-31" p="src/selectorrefuse.h" l="7" kind="ref" t="// (&quot;that file defines no &apos;rankGraphTeleport&apos;&quot;), names the files that DO define the name, and hands back a"/>
<hit ref="HEAD" tip="1dc07e27a" date="2026-07-31" p="bench/recalleval/labels_ranking.tsv" l="49" kind="ref" t="power iteration rank convergence damping factor&#9;src/pagerank.cpp#pageRankDouble&#9;src/graph.h#rankGraphTeleport,src/pagerank.h#pageRankDouble&#9;concept"/>
<hit ref="HEAD" tip="1dc07e27a" date="2026-07-31" p="bench/recalleval/labels_ranking.tsv" l="68" kind="ref" t="pagerank power iteration&#9;src/pagerank.cpp#pageRankDouble&#9;src/pagerank.h#pageRankDouble,src/graph.h#rankGraphTeleport&#9;adversarial"/>
<hit ref="HEAD" tip="1dc07e27a" date="2026-07-31" p="test/crossrefcheck.sh" l="176" kind="ref" t="# source path put doc-QUOTED code on the first screen: on this repo `--whereis=rankGraphTeleport` opened"/>
<hit ref="HEAD" tip="1dc07e27a" date="2026-07-31" p="test/crossrefcheck.sh" l="230" kind="ref" t="&quot;$BIN&quot; &quot;$ROOT&quot; --whereis=rankGraphTeleport &gt;&quot;$TMP/wreal&quot; 2&gt;/dev/null"/>
<hit ref="HEAD" tip="1dc07e27a" date="2026-07-31" p="test/crossrefcheck.sh" l="234" kind="ref" t="&quot;def src/graph.h&quot;) ok &quot;whereis: rankGraphTeleport&apos;s first def row is src/graph.h (was a docs/captures CDATA row)&quot; ;;"/>
<hit ref="HEAD" tip="1dc07e27a" date="2026-07-31" p="test/crossrefcheck.sh" l="235" kind="ref" t="&quot;&quot;)                ok &quot;whereis: rankGraphTeleport not found in this checkout — real-repo arm skipped&quot; ;;"/>
<hit ref="HEAD" tip="1dc07e27a" date="2026-07-31" p="test/crossrefcheck.sh" l="236" kind="ref" t="*)                 no &quot;whereis: rankGraphTeleport&apos;s first def row is &apos;$firstRealDef&apos;, want src/graph.h&quot; ;;"/>
<hit ref="HEAD" tip="1dc07e27a" date="2026-07-31" p="test/selectorchaincheck.sh" l="11" kind="ref" t="#       `--expand=src/graph.h:rankGraphTeleport` was parsed as a LINE RANGE, warned &quot;malformed range&quot;, and"/>
<hit ref="HEAD" tip="1dc07e27a" date="2026-07-31" p="test/selectorchaincheck.sh" l="62" kind="ref" t="A_Q=&quot;$( run --top-k=0 --expand=src/graph.h:rankGraphTeleport 2&gt;/dev/null )&quot;"/>
<hit ref="HEAD" tip="1dc07e27a" date="2026-07-31" p="test/selectorchaincheck.sh" l="63" kind="ref" t="A_B=&quot;$( run --top-k=0 --expand=rankGraphTeleport            2&gt;/dev/null )&quot;"/>
<hit ref="HEAD" tip="1dc07e27a" date="2026-07-31" p="test/selectorchaincheck.sh" l="65" kind="ref" t="*&apos;n=&quot;rankGraphTeleport&quot;&apos;*&apos;PROFILE_SCOPE_DESCRIBE&apos;*) ok &quot;(a) --expand=src/graph.h:rankGraphTeleport returns that symbol&apos;s BODY&quot; ;;"/>
<hit ref="HEAD" tip="1dc07e27a" date="2026-07-31" p="test/selectorchaincheck.sh" l="66" kind="ref" t="*) no &quot;(a) --expand=src/graph.h:rankGraphTeleport did not return the body (got ${#A_Q} bytes)&quot; ;;"/>
<hit ref="HEAD" tip="1dc07e27a" date="2026-07-31" p="test/selectorchaincheck.sh" l="75" kind="ref" t="C=&quot;$( run --callers=rankGraphTeleport 2&gt;/dev/null )&quot;"/>
<hit ref="HEAD" tip="1dc07e27a" date="2026-07-31" p="test/selectorchaincheck.sh" l="83" kind="ref" t="&amp;&amp; ok &quot;(b) chain --callers=rankGraphTeleport → --expand=$RP:$RN → exactly that one def&quot; \"/>
… [34 more display lines; full output is 17057 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --whereis=computeOnePairOverlap --with-history`

*Same, plus a git-history <fate> row (never / removed-by-commit) for names no tree carries.*

`````
<!-- ripwire whereis: every LOCAL ref whose TREE contains this symbol, HEAD first, and within a ref SOURCE files before test files before docs, then definitions before references, then path and line. The doc demotion is ORDER ONLY: a doc line that quotes a signature still reads as a definition to the heuristic below and still says kind="def", it is simply printed after the code. kind= is answered by TWO different mechanisms, and head_labels= says which one answered for HEAD: with head_labels="index" a HEAD row is kind="def" iff the PARSED index puts a definition there (one row per index def site), while every NON-HEAD row — and every row when head_labels="lexical" (no index was supplied, the index knows no def of this name, or the working tree has drifted from HEAD) — is a LEXICAL shape heuristic over raw blob text that was never ingested: it reads a quoted signature in a doc as a definition and can miss an unusual declarator. refs_scanned= is the SCAN DENOMINATOR (how many refs besides HEAD were read), NOT a count of refs that matched — hits= and the rows are the matched set. on-head="0" alongside ref hits is the case this verb exists for: content that lives only on a branch. A TREE scan can only find content some ref still carries, so hits="0" on its own does not distinguish a name this repo never had from one it deleted; run with the with_history flag and the fate row says which, naming the commit that removed it. ANCHORING: none, by design. This verb runs no diff at all — it scans each ref's FULL tree, which is what lets it find content a branch merely INHERITED (exactly what a merge base anchored diff would exclude), so nothing here can fire merely because HEAD moved. at= is sha-only here (never +dirty): a tree scan reads committed blobs, so the working tree's cleanliness does not enter the answer. SELECTOR: this verb takes a BARE symbol name, not the file:name spelling that callers, uses, impact, around, lego and edit_check accept. A file:name spelling is searched as a LITERAL string, no tree contains it, and the result is a true but useless hits="0" shaped exactly like a name this repo never had. When that is what happened, a selector-note element says so and its retry= is the bare name to re-run with. Its absence beside hits="0" means the zero IS a measurement. SCOPE: refs/heads only, which is every local branch (worktree branches included). Remote tracking refs are NOT scanned: they mirror local ones in the usual checkout and would double every row. The consequence on a FRESH CLONE, where the branches live under refs/remotes/origin and only the checked out one has a local head, is that this verb sees essentially one tree; refs_scanned= is that fact as a number, so read it before reading hits=. TRUNCATION: the trailing more element (more hits=N) is the rows AFTER this page, so shown plus more equals the rows from this page's offset on. It is not a second cap, and not a second vocabulary to page by: it is the SAME fact shown= / capped= / next_offset= carry, restated from the other end (what this page did not print). Page with limit= and offset=; the more element is absent exactly when this page reached the end of the hit list. raise the default cap with limit=N (offset=M pages) -->
<whereis sym="computeOnePairOverlap" on-head="1" refs_scanned="1" blobs="1564" hits="10" head_labels="index" shown="10" capped="0" at="1dc07e27a">
<history probed="1" head="1dc07e27a" commits="18" removed-names="6977"/>
<fate sym="computeOnePairOverlap" v="never" note="no commit reachable from HEAD ever removed a line carrying this name — so for a name HEAD does not have, this repo never had it"/>
<hit ref="HEAD" tip="1dc07e27a" date="2026-07-31" p="src/mergescout.h" l="470" kind="def" t="inline PairOverlap computeOnePairOverlap( std::size_t a, std::size_t b, const Arm&amp; armA, const Arm&amp; armB )"/>
<hit ref="HEAD" tip="1dc07e27a" date="2026-07-31" p="src/lanes.h" l="17" kind="ref" t="// and the landing order are mergescout::computeOnePairOverlap / computeOverlaps / landingOrder, fed SYNTHETIC"/>
<hit ref="HEAD" tip="1dc07e27a" date="2026-07-31" p="src/lanes.h" l="64" kind="ref" t="//   same_file_risk[] — different keys, same file. AGGREGATED PER FILE: computeOnePairOverlap is a nested loop"/>
<hit ref="HEAD" tip="1dc07e27a" date="2026-07-31" p="src/mergescout.h" l="487" kind="ref" t="pairs.push_back( computeOnePairOverlap( a, b, arms[a], arms[b] ) );"/>
<hit ref="HEAD" tip="1dc07e27a" date="2026-07-31" p="test/showcase_capture.py" l="157" kind="ref" t="add(S4, f&quot;{BIN} . --whereis=computeOnePairOverlap --with-history&quot;, &quot;Same, plus a git-history &lt;fate&gt; row (never / removed-by-commit) for names no tree carries.&quot;, timeout=600) … [line truncated: 3 more bytes on this line]
<hit ref="docs" tip="6008ac607" date="2026-07-31" p="src/mergescout.h" l="470" kind="def" t="inline PairOverlap computeOnePairOverlap( std::size_t a, std::size_t b, const Arm&amp; armA, const Arm&amp; armB )"/>
<hit ref="docs" tip="6008ac607" date="2026-07-31" p="src/lanes.h" l="17" kind="ref" t="// and the landing order are mergescout::computeOnePairOverlap / computeOverlaps / landingOrder, fed SYNTHETIC"/>
<hit ref="docs" tip="6008ac607" date="2026-07-31" p="src/lanes.h" l="64" kind="ref" t="//   same_file_risk[] — different keys, same file. AGGREGATED PER FILE: computeOnePairOverlap is a nested loop"/>
<hit ref="docs" tip="6008ac607" date="2026-07-31" p="src/mergescout.h" l="487" kind="ref" t="pairs.push_back( computeOnePairOverlap( a, b, arms[a], arms[b] ) );"/>
<hit ref="docs" tip="6008ac607" date="2026-07-31" p="test/showcase_capture.py" l="157" kind="ref" t="add(S4, f&quot;{BIN} . --whereis=computeOnePairOverlap --with-history&quot;, &quot;Same, plus a git-history &lt;fate&gt; row (never / removed-by-commit) for names no tree carries.&quot;, timeout=600) … [line truncated: 3 more bytes on this line]
</whereis>
`````

## `./build/ripwire . --flags`

*The dark-content dashboard: gates BUILT but OFF. CHANGED: no longer invents gates from comments/heredocs, so the count only reflects real ifndef/define, CMake option(), and getenv gates.*

`````
<!-- ripwire flags: what is BUILT but DARK here. Three gate patterns in one report: ifndef/define header gates (kind="compile"), CMake option() switches (kind="cmake"), and getenv reads (kind="env", default unset). dark="1" means the default keeps the guarded code out of the build; regions/loc size what it turns off. When one name is BOTH a header gate and a CMake option the CMake default wins (that is what the build passes) and the header shows as an also row. Lexical, not preprocessed: this reports the in-repo default, never the value your build used. dark_gates on this root is the COUNT of dark gates; it was spelled dark until that collided with the child bool. files= is THIS verb's own harvest scan (source + CMakeLists files it read looking for gates) — a wider crawl than the map's indexed corpus, so it will not equal the map's files= -->
<flags gates="44" dark_gates="38" compile="11" cmake="9" env="24" files="839">
<gate name="FIXTURE_DARK_FEATURE" kind="compile" default="0" dark="1" regions="2" loc="13" reads="2" p="test/flagsfix/wiringFlags.h" l="10">
<read p="test/flagsfix/feature.cpp" l="10"/>
<read p="test/flagsfix/sub/nested.cpp" l="5"/>
</gate>
<gate name="PROFILE_PMC_VERBOSE" kind="compile" default="0" dark="1" regions="2" loc="10" reads="2" p="src/infra/profilePmc.h" l="78">
<read p="src/infra/profilePmc.h" l="81"/>
<read p="src/infra/profilePmc.h" l="416"/>
</gate>
<gate name="ALIASFIX_ALL" kind="compile" default="0" dark="1" regions="0" loc="0" reads="2" p="test/flagsaliasfix/aliases.h" l="7">
<aliases n="2" regions="2" loc="8"/>
<read p="test/flagsaliasfix/aliases.h" l="11"/>
<read p="test/flagsaliasfix/aliases.h" l="15"/>
</gate>
<gate name="ALIASFIX_TURNS" kind="compile" default="0" dark="1" regions="1" loc="4" reads="1" p="test/flagsaliasfix/aliases.h" l="15">
<alias-of name="ALIASFIX_ALL"/>
<read p="test/flagsaliasfix/use.cpp" l="10"/>
</gate>
<gate name="ALIASFIX_WALLS" kind="compile" default="0" dark="1" regions="1" loc="4" reads="1" p="test/flagsaliasfix/aliases.h" l="11">
<alias-of name="ALIASFIX_ALL"/>
<read p="test/flagsaliasfix/use.cpp" l="3"/>
</gate>
<gate name="PROFILE_BARRIER" kind="compile" default="0" dark="1" regions="1" loc="3" reads="1" p="src/infra/profileScope.h" l="53">
<read p="src/infra/profileScope.h" l="109"/>
</gate>
<gate name="FIXTURE_CMAKE_DARK" kind="cmake" default="OFF" dark="1" regions="1" loc="1" reads="3" p="test/flagsfix/CMakeLists.txt" l="4">
<read p="test/flagsfix/CMakeLists.txt" l="4"/>
<read p="test/flagsfix/CMakeLists.txt" l="10"/>
<read p="test/flagsfix/override.h" l="13"/>
… [172 more display lines; full output is 11179 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --flags --flip=RIPWIRE_ASAN`

*Blast radius of turning ONE gate on: live code, symbols, transitive reach, covering tests.*

`````
<!-- ripwire flip: the blast radius of turning ONE gate ON. lights = the code that becomes live: r rows are #if regions, b rows are C++ branch sites (a gate read as a VALUE through a constexpr bool, via= names the binding). hosts = the indexed defs that code sits inside; downstream = what those defs transitively CALL (what starts executing); dependents = what transitively calls THEM. tests = test files reaching the hosts; untested = hosts no test reaches (the honest is it safe answer). An alias MASTER rolls its children in (member rows); flipping a CHILD lights only that child and names its parent. kind=cmake also steers the BUILD graph, which no C++ side analysis follows: those sites are c rows. kind=env is RUNTIME (runtime=1) so every row is conditional at its read. Lexical and single line, never preprocessed: the value lane reads C family source only and treats a file declaring its OWN constant of that name as shadowing the gate's, but a third header's same named constant (included, not redeclared) would still count. A lit site inside no indexed def counts into filescope instead of a host. UNIT: untested= here counts HOSTS (indexed defs this gate lights that no test reaches). The test gate verb spells untested= over impacted SYMBOLS and the seams verb over cross-directory call EDGES, so the three numbers count three different things and must never be compared or summed across verbs. -->
<flip gate="RIPWIRE_ASAN" kind="cmake" default="OFF" dark="1" runtime="0" p="CMakeLists.txt" l="14" family="1" regions="0" loc="0" branches="0" bindings="0" hosts="0" filescope="0" downstream="0" dependents="0" tests="0" untested="0" files="839">
<member name="RIPWIRE_ASAN" via="self" regions="0" loc="0" branches="0"/>
<lights r="0" b="0">
</lights>
<hosts n="0">
</hosts>
<downstream n="0">
</downstream>
<tests n="0">
</tests>
<untested n="0">
</untested>
<build n="4" note="CMake read sites: a switch here can add whole translation units or link targets, which this verb does NOT follow">
<c p="CMakeLists.txt" l="14"/>
<c p="CMakeLists.txt" l="18"/>
<c p="CMakeLists.txt" l="24"/>
<c p="CMakeLists.txt" l="415"/>
</build>
</flip>
`````

## `./build/ripwire . --flags --flip=NoSuchGate`

*Unknown-gate refusal (exit 1) naming the near-misses.*

**exit code: 1**

`````
(empty)
`````

stderr:

`````
ripwire: --flip: no gate named 'NoSuchGate' in .
ripwire: run `ripwire . --flags` for the gate table
`````

## `./build/ripwire . --plan-lanes=3 --task="add a --since filter to the doc-drift verb and cover it with tests"`

*NEW VERB: pre-hoc lane plan — which of 3 parallel worktrees would COLLIDE, before a line is written. JSON on stdout.*

`````
{"v":1,"verb":"plan-lanes","at":"1dc07e27a+dirty","root":".","task":"add a --since filter to the doc-drift verb and cover it with tests","source":"partition","requested":3,"lane_count":3,"claim_key":"path+scope+name","on_conflict":"producing-lane-rebases","corpus":{"files":836,"symbols":6432,"edges" … [line truncated: 350 more bytes on this line]
"symbols":[{"p":"./src/docdrift.h","n":"computeDocDrift","scope":"docdrift","l":1736,"id":"./src/docdrift.h::docdrift::computeDocDrift"},
{"p":"./src/docdrift.h","n":"writeDocDriftPage","scope":"docdrift","l":2003,"id":"./src/docdrift.h::docdrift::writeDocDriftPage"},
{"p":"./src/docdrift.h","n":"writeGateability","scope":"docdrift","l":1886,"id":"./src/docdrift.h::docdrift::writeGateability"},
{"p":"./src/main.cpp","n":"runDocDrift","scope":"","l":5719,"id":null},
{"p":"./src/mcpverbs.h","n":"docDriftText","scope":"rw","l":384,"id":"./src/mcpverbs.h::rw::docDriftText"},
{"p":"./src/recall.h","n":"docFileMask","scope":"rw","l":93,"id":"./src/recall.h::rw::docFileMask"}]},"lanes":[{"id":"lane-0","task":"add a --since filter to the doc-drift verb and cover it with tests","claims":{"symbols":[{"p":"./src/cli.h","n":"pagingDisablingMode","scope":"rw","key":"1d13d5061cd1 … [line truncated: 169 more bytes on this line]
{"p":"./src/mcp.h","n":"isMcpEditVerb","scope":"rw","key":"29a5a2524a95d6c2","id":"./src/mcp.h::rw::isMcpEditVerb","id_addressable":true,"id_collides_with":0,"l":264,"ord":0,"overloads":1,"amb":0,"cx":3,"ccx":3,"churn":3,"tested":0},
{"p":"./src/mcprefusal.h","n":"notFound","scope":"rw::mcprefuse","key":"2f350cb55c4c61ac","id":"./src/mcprefusal.h::rw::mcprefuse::notFound","id_addressable":true,"id_collides_with":0,"l":600,"ord":0,"overloads":1,"amb":2,"cx":4,"ccx":3,"churn":3,"tested":0},
{"p":"./src/mcpverbs.h","n":"whereisText","scope":"rw","key":"39588f57bd7b46b5","id":"./src/mcpverbs.h::rw::whereisText","id_addressable":true,"id_collides_with":0,"l":344,"ord":0,"overloads":1,"amb":0,"cx":2,"ccx":1,"churn":3,"tested":0},
{"p":"./src/mcprefusal.h","n":"singleRootRefusal","scope":"rw::mcprefuse","key":"4cf11960f7360525","id":"./src/mcprefusal.h::rw::mcprefuse::singleRootRefusal","id_addressable":true,"id_collides_with":0,"l":524,"ord":0,"overloads":1,"amb":0,"cx":1,"ccx":0,"churn":3,"tested":0},
{"p":"./src/main.cpp","n":"jsonUnsupportedVerb","scope":"","key":"6e4dbe9b6d8ebac4","id":null,"id_addressable":false,"id_collides_with":0,"l":7900,"ord":0,"overloads":1,"amb":26,"cx":72,"ccx":72,"churn":4,"tested":0},
{"p":"./src/lanes.h","n":"buildWarnings","scope":"lanes","key":"6ff5b3de543f7431","id":"./src/lanes.h::lanes::buildWarnings","id_addressable":true,"id_collides_with":0,"l":615,"ord":0,"overloads":1,"amb":2,"cx":17,"ccx":19,"churn":3,"tested":0},
{"p":"./src/gitmine.h","n":"resolveSinceScope","scope":"rw","key":"9caaa3dbeaa688d0","id":"./src/gitmine.h::rw::resolveSinceScope","id_addressable":true,"id_collides_with":0,"l":116,"ord":0,"overloads":1,"amb":0,"cx":6,"ccx":6,"churn":3,"tested":0},
{"p":"./src/situ.h","n":"gitDiffChangedMask","scope":"rw","key":"a9243123d6bed37b","id":"./src/situ.h::rw::gitDiffChangedMask","id_addressable":true,"id_collides_with":0,"l":55,"ord":0,"overloads":1,"amb":0,"cx":1,"ccx":0,"churn":3,"tested":0},
{"p":"./src/cli.h","n":"validateConfig","scope":"rw","key":"c17db5239ed07cf7","id":"./src/cli.h::rw::validateConfig","id_addressable":true,"id_collides_with":0,"l":2234,"ord":0,"overloads":1,"amb":19,"cx":57,"ccx":44,"churn":3,"tested":0},
{"p":"./src/mcp.h","n":"dispatchMcpLine","scope":"rw","key":"d63db6944aa504a7","id":"./src/mcp.h::rw::dispatchMcpLine","id_addressable":true,"id_collides_with":0,"l":304,"ord":0,"overloads":1,"amb":134,"cx":220,"ccx":428,"churn":3,"tested":0},
{"p":"./src/main.cpp","n":"gitChurnCounts","scope":"","key":"dce05f27d584683a","id":null,"id_addressable":false,"id_collides_with":0,"l":196,"ord":0,"overloads":1,"amb":1,"cx":5,"ccx":4,"churn":4,"tested":0},
{"p":"./src/mcprefusal.h","n":"nearestName","scope":"rw::mcprefuse","key":"ddc57fe52dbd6718","id":"./src/mcprefusal.h::rw::mcprefuse::nearestName","id_addressable":true,"id_collides_with":0,"l":646,"ord":0,"overloads":1,"amb":1,"cx":7,"ccx":8,"churn":3,"tested":0},
{"p":"./src/mcpverbs.h","n":"packTaskText","scope":"rw","key":"e514a69013d0934c","id":"./src/mcpverbs.h::rw::packTaskText","id_addressable":true,"id_collides_with":0,"l":1856,"ord":0,"overloads":1,"amb":2,"cx":20,"ccx":29,"churn":3,"tested":0},
{"p":"./src/cli.h","n":"validateModifierGuards","scope":"rw","key":"ec2848a4801493a2","id":"./src/cli.h::rw::validateModifierGuards","id_addressable":true,"id_collides_with":0,"l":2112,"ord":0,"overloads":1,"amb":14,"cx":36,"ccx":27,"churn":3,"tested":0}],
"files":[{"p":"./src/cli.h","symbols":3,"churn":3,"ccx":77,"hotspot_rank":15},
{"p":"./src/gitmine.h","symbols":1,"churn":3,"ccx":6,"hotspot_rank":9},
{"p":"./src/lanes.h","symbols":1,"churn":3,"ccx":19,"hotspot_rank":22},
{"p":"./src/main.cpp","symbols":2,"churn":4,"ccx":76,"hotspot_rank":1},
{"p":"./src/mcp.h","symbols":2,"churn":3,"ccx":431,"hotspot_rank":10},
{"p":"./src/mcprefusal.h","symbols":3,"churn":3,"ccx":11,"hotspot_rank":31},
{"p":"./src/mcpverbs.h","symbols":2,"churn":3,"ccx":30,"hotspot_rank":7},
{"p":"./src/situ.h","symbols":1,"churn":3,"ccx":0,"hotspot_rank":36}]},"blast_radius":{"reaches":42,"files_total":9,"capped":false,"files":["./src/cli.h","./src/lanes.h","./src/main.cpp","./src/mcp.h","./src/mcpedit.h","./src/mcpindex.h","./src/mcprefusal.h","./src/mcpserver.h","./src/mcpverbs.h"]}, … [line truncated: 18 more bytes on this line]
"tests_total":0,"tests_capped":false,"tests_granularity":"claimed-symbols","untested":42,"module_span":1,"notes":[]},
… [75 more display lines; full output is 19437 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --plan-lanes --brief=/var/folders/_7/1b0h5mxs3vl2jgb9jk3qzw7r0000gn/T/ripwire_showcase_fxbqqxez/aux/lanes_brief.txt`

*NEW VERB, explicit form: one line per lane, lane boundaries are the ones you wrote (the defensible mode).*

Input file:

`````
add a --since filter to the doc-drift verb
add the CLI parse arm and help text for the new filter
write regression tests for the new filter
`````

`````
{"v":1,"verb":"plan-lanes","at":"1dc07e27a+dirty","root":".","task":null,"source":"brief","requested":3,"lane_count":3,"claim_key":"path+scope+name","on_conflict":"producing-lane-rebases","corpus":{"files":836,"symbols":6432,"edges":8733,"ambiguous":2631,"unresolved":652},"carve":null,"core":{"files … [line truncated: 5 more bytes on this line]
"symbols":[]},"lanes":[{"id":"lane-0","task":"add a --since filter to the doc-drift verb","claims":{"symbols":[{"p":"./src/mcpverbs.h","n":"docDriftText","scope":"rw","key":"1fa68e8d93c05a59","id":"./src/mcpverbs.h::rw::docDriftText","id_addressable":true,"id_collides_with":0,"l":384,"ord":0,"overlo … [line truncated: 52 more bytes on this line]
{"p":"./src/recall.h","n":"docFileMask","scope":"rw","key":"3149a219f599664c","id":"./src/recall.h::rw::docFileMask","id_addressable":true,"id_collides_with":0,"l":93,"ord":0,"overloads":1,"amb":0,"cx":4,"ccx":4,"churn":3,"tested":0},
{"p":"./src/docdrift.h","n":"writeDocDriftPage","scope":"docdrift","key":"380b7de5df1cfd73","id":"./src/docdrift.h::docdrift::writeDocDriftPage","id_addressable":true,"id_collides_with":0,"l":2003,"ord":0,"overloads":1,"amb":2,"cx":9,"ccx":10,"churn":3,"tested":0},
{"p":"./src/docdrift.h","n":"computeDocDrift","scope":"docdrift","key":"3b19cc3d8996c3b2","id":"./src/docdrift.h::docdrift::computeDocDrift","id_addressable":true,"id_collides_with":0,"l":1736,"ord":0,"overloads":1,"amb":3,"cx":20,"ccx":33,"churn":3,"tested":0},
{"p":"./src/docdrift.h","n":"DriftResult","scope":"DriftResult","key":"422ab39546b6e0bd","id":"./src/docdrift.h::DriftResult::DriftResult","id_addressable":true,"id_collides_with":0,"l":250,"ord":0,"overloads":1,"amb":0,"cx":0,"ccx":0,"churn":3,"tested":0},
{"p":"./src/docdrift.h","n":"writeGateability","scope":"docdrift","key":"42c456dfb55faee4","id":"./src/docdrift.h::docdrift::writeGateability","id_addressable":true,"id_collides_with":0,"l":1886,"ord":0,"overloads":1,"amb":0,"cx":6,"ccx":6,"churn":3,"tested":0},
{"p":"./src/docdrift.h","n":"writeDocDrift","scope":"docdrift","key":"7bbf4862e91b5d48","id":"./src/docdrift.h::docdrift::writeDocDrift","id_addressable":true,"id_collides_with":0,"l":2062,"ord":0,"overloads":1,"amb":0,"cx":1,"ccx":0,"churn":3,"tested":0},
{"p":"./src/main.cpp","n":"warnReportVerbPrecedence","scope":"","key":"8969760b6183631b","id":null,"id_addressable":false,"id_collides_with":0,"l":7852,"ord":0,"overloads":1,"amb":22,"cx":6,"ccx":8,"churn":4,"tested":0},
{"p":"./src/docdrift.h","n":"sortDocsByLiveDrift","scope":"docdrift","key":"d5de682411b9a9a9","id":"./src/docdrift.h::docdrift::sortDocsByLiveDrift","id_addressable":true,"id_collides_with":0,"l":1724,"ord":0,"overloads":1,"amb":2,"cx":2,"ccx":2,"churn":3,"tested":0},
{"p":"./src/mcpverbs.h","n":"unknownSubVerbRefusal","scope":"rw","key":"e336d39b0a6addea","id":"./src/mcpverbs.h::rw::unknownSubVerbRefusal","id_addressable":true,"id_collides_with":0,"l":2357,"ord":0,"overloads":1,"amb":5,"cx":3,"ccx":2,"churn":3,"tested":0},
{"p":"./src/main.cpp","n":"runDocDrift","scope":"","key":"ebf80a749e6eca28","id":null,"id_addressable":false,"id_collides_with":0,"l":5719,"ord":0,"overloads":1,"amb":0,"cx":4,"ccx":3,"churn":4,"tested":0},
{"p":"./src/cli.h","n":"validateModifierGuards","scope":"rw","key":"ec2848a4801493a2","id":"./src/cli.h::rw::validateModifierGuards","id_addressable":true,"id_collides_with":0,"l":2112,"ord":0,"overloads":1,"amb":14,"cx":36,"ccx":27,"churn":3,"tested":0}],
"files":[{"p":"./src/cli.h","symbols":1,"churn":3,"ccx":27,"hotspot_rank":15},
{"p":"./src/docdrift.h","symbols":6,"churn":3,"ccx":51,"hotspot_rank":8},
{"p":"./src/main.cpp","symbols":2,"churn":4,"ccx":11,"hotspot_rank":1},
{"p":"./src/mcpverbs.h","symbols":2,"churn":3,"ccx":2,"hotspot_rank":7},
{"p":"./src/recall.h","symbols":1,"churn":3,"ccx":4,"hotspot_rank":38}]},"blast_radius":{"reaches":12,"files_total":6,"capped":false,"files":["./src/cli.h","./src/main.cpp","./src/mcp.h","./src/mcpserver.h","./src/mcpverbs.h","./src/recall.h"]},"tests_to_run":[],
"tests_total":0,"tests_capped":false,"tests_granularity":"claimed-symbols","untested":12,"module_span":7,"notes":[]},
{"id":"lane-1","task":"add the CLI parse arm and help text for the new filter","claims":{"symbols":[{"p":"./src/main.cpp","n":"runNotes","scope":"","key":"1f218712fab4409e","id":null,"id_addressable":false,"id_collides_with":0,"l":5061,"ord":0,"overloads":1,"amb":11,"cx":26,"ccx":54,"churn":4,"teste … [line truncated: 6 more bytes on this line]
{"p":"./src/mcpverbs.h","n":"batchPageRefusal","scope":"rw","key":"37b8ed7e29b141da","id":"./src/mcpverbs.h::rw::batchPageRefusal","id_addressable":true,"id_collides_with":0,"l":2336,"ord":0,"overloads":1,"amb":1,"cx":4,"ccx":3,"churn":3,"tested":0},
{"p":"./docs/docs_commands_build.py","n":"assert_scrubbed","scope":"","key":"3f2f96d107d3b9c2","id":null,"id_addressable":false,"id_collides_with":0,"l":426,"ord":0,"overloads":1,"amb":0,"cx":5,"ccx":8,"churn":3,"tested":0},
{"p":"./docs/docs_commands_build.py","n":"main","scope":"","key":"4015853681ded3bc","id":null,"id_addressable":false,"id_collides_with":42,"l":474,"ord":0,"overloads":1,"amb":0,"cx":18,"ccx":25,"churn":3,"tested":0},
{"p":"./docs/docs_commands_build.py","n":"scrub_prose","scope":"","key":"6846061c73b4f780","id":null,"id_addressable":false,"id_collides_with":0,"l":229,"ord":0,"overloads":1,"amb":0,"cx":1,"ccx":0,"churn":3,"tested":0},
{"p":"./src/main.cpp","n":"deadCodeFilterMatchesPath","scope":"","key":"6d33ddb6fcd29699","id":null,"id_addressable":false,"id_collides_with":0,"l":3454,"ord":0,"overloads":1,"amb":1,"cx":11,"ccx":12,"churn":4,"tested":0},
{"p":"./src/docparse.h","n":"classifyGeneratedDoc","scope":"docparse","key":"8d10cf7eab7a73cd","id":"./src/docparse.h::docparse::classifyGeneratedDoc","id_addressable":true,"id_collides_with":0,"l":540,"ord":0,"overloads":1,"amb":0,"cx":7,"ccx":6,"churn":2,"tested":0},
{"p":"./docs/docs_commands_build.py","n":"parse_capture","scope":"","key":"be71bf499e18d319","id":null,"id_addressable":false,"id_collides_with":0,"l":156,"ord":0,"overloads":1,"amb":0,"cx":18,"ccx":25,"churn":3,"tested":0},
{"p":"./src/main.cpp","n":"deadCodeStripDotSlash","scope":"","key":"c568137ee172716f","id":null,"id_addressable":false,"id_collides_with":0,"l":3434,"ord":0,"overloads":1,"amb":0,"cx":4,"ccx":2,"churn":4,"tested":0},
{"p":"./test/showcase_capture.py","n":"BRIEF","scope":"","key":"d75d423bbee0bcc1","id":null,"id_addressable":false,"id_collides_with":0,"l":60,"ord":0,"overloads":1,"amb":0,"cx":0,"ccx":0,"churn":4,"tested":0},
{"p":"./src/notes.h","n":"addNote","scope":"rw::notes","key":"d9c0d39c0c407b7e","id":"./src/notes.h::rw::notes::addNote","id_addressable":true,"id_collides_with":0,"l":313,"ord":0,"overloads":1,"amb":0,"cx":9,"ccx":6,"churn":3,"tested":0},
… [54 more display lines; full output is 16361 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --plan-lanes=99 --task=x`

*Out-of-range refusal shape for the lane count.*

**exit code: 1**

`````
(empty)
`````

stderr:

`````
ripwire: --plan-lanes=99 is out of range — N must be 2..16 (1 is not a fan-out)
`````

## `./build/ripwire . --layout=Symbol`

*CPU/GPU contract view of one struct: computed offsets/sizes/padding + mirror check.*

`````
<!-- ripwire layout: field offsets COMPUTED from the source text under standard-layout assumptions on a 64-bit Apple/LP64 target (natural alignment, interior padding, trailing pad to the aggregate's own alignment). NOT the ABI: pragma pack, bitfields, virtuals, base classes, nested aggregates, preprocessor-conditional members and unsized field types are DETECTED and set modeled="0" with a caveat rather than numbered. Every same-name definition is compared: kind="drift" means the BYTE contract differs (the bug this verb exists for, and the only one that exits non-zero); kind="stub" is an empty placeholder aggregate and kind="spelling" is the two arms of one ifdef block naming the same bytes differently (simd::float4 vs float4) — both reported, neither a break. agree="0" on an assert row means a sizeof tripwire contradicts the computed size. Definitions and asserts come from the INDEXED files. -->
<layout sym="Symbol" found="1" defs="1" mirror="single" asserts="1" conflicts="0" scanned="275">
<def p="./src/model.h" l="106" agg="struct" modeled="0" fields="16">
<f n="id" ty="NodeId" as="std::uint32_t" sz="4" al="4" off="0"/>
<f n="kind" ty="SymKind" as="std::uint8_t" sz="1" al="1" off="4"/>
<f n="lang" ty="Lang" as="std::uint8_t" sz="1" al="1" off="5"/>
<pad bytes="2"/>
<f n="fileId" ty="std::uint32_t" sz="4" al="4" off="8"/>
<f n="line" ty="std::uint32_t" sz="4" al="4" off="12"/>
<f n="sigStartByte" ty="std::uint32_t" sz="4" al="4" off="16"/>
<f n="sigEndByte" ty="std::uint32_t" sz="4" al="4" off="20"/>
<f n="endByte" ty="std::uint32_t" sz="4" al="4" off="24"/>
<f n="cx" ty="std::uint32_t" sz="4" al="4" off="28"/>
<f n="ccx" ty="std::uint32_t" sz="4" al="4" off="32"/>
<f n="loc" ty="std::uint32_t" sz="4" al="4" off="36"/>
<f n="params" ty="std::uint16_t" sz="2" al="2" off="40"/>
<f n="maxNest" ty="std::uint8_t" sz="1" al="1" off="42"/>
<f n="arityExact" ty="std::uint8_t" sz="1" al="1" off="43"/>
<f n="name" ty="std::string" sized="0"/>
<f n="scope" ty="std::string" sized="0"/>
<caveat k="unknown-type" d="name: std::string" count="2"/>
</def>
<assert p="./src/model.h" l="136" kind="mention" t="static_assert( sizeof( Symbol ) == 48 + 2 * sizeof( std::string ), &quot;Symbol size changed — verify the new field uses the smallest type + is grouped (SoA); see model.h&quot; )"/>
</layout>
`````

## `./build/ripwire . --layout=Lang`

*The honest-degrade case: Lang is an `enum class`, not a struct.*

**exit code: 1**

`````
(empty)
`````

stderr:

`````
ripwire: --layout: 'Lang' is an enum, --layout models structs (a scoped/unscoped enum's underlying type is not a byte layout)
`````

## `./build/ripwire . --doc-drift`

*Which of this repo's doc claims are now false. CHANGED: row attribute at= renamed to tgt= (at= is now only the root sha stamp).*

`````
<!-- ripwire doc drift: the CHECKABLE anchors in this repo's markdown, verified against the live index, reporting only the ones that no longer hold. Four kinds: file:line refs (missing-file / past-eof / line-moved, the last only when the doc names a symbol on that line), backticked symbol mentions (undefined), `= N` constants and `[N]` array extents (value/extent vs the declaration). Every lane under reports on purpose: a name is stale only when it occurs NOWHERE in the code as an identifier, and a number is compared only against a declaration shaped literal the corpus binds uniquely. checked + unchecked == anchors: nothing is dropped silently, and the unchecked rows say what was not proved. Read why="undefined" precisely: it says the name is defined NOWHERE in this repo, which is not the same as DELETED — in a plan or design doc naming work not yet built, that is expected rather than rot. Run with the with_history flag to have git history separate the two: the lane then reports why="deleted" with the commit that removed the name, and downgrades a name this repo never had to unchecked r="never in history". A failed anchor the AUTHOR DATED is split out as kind="dated-record" and counted in dated= rather than drift=: an audit finding, a ledger row or an as-of-DATE hedge records what was true then, so drift= is the LIVE rot and drift + dated is every anchor that no longer holds. rec= names the evidence (line / block / title / stamp), and a doc that never writes its own date anywhere a machine can read reports LIVE — the lane reads dating marks, it does not guess genre. Attribute vocabulary, one name one meaning: at= appears ONLY on this root element and is the commit the run was measured against (short sha, plus dirty when the tree had uncommitted changes); ref= is the anchor as the DOC writes it; got= is what the corpus actually says; and tgt= is the corpus SITE backing got= (a path, or path:line). On the <a/> rows k= and kind= are DIFFERENT things and both are kept: k= is the ANCHOR kind (file-line / symbol / const / array), kind= is the record classification (dated-record). k= cannot be renamed to kind= here for the obvious reason that kind= is already taken on the same element; note that in the ranked map the same k= spelling is a PageRank score instead. Docs are ordered by LIVE drift descending (path breaks ties), so the worst rot leads and a fully dated doc, which is drift zero by construction, sinks on the same key. Prose claims, Status lines and dates are NOT checked. FOUR COUNTERS on this element name four DIFFERENT populations, stated here because one of them openly disagrees with a number the map reports elsewhere. docs= is the DOCUMENTS scanned for anchors (markdown by extension, after any filter); it is the denominator of the doc rows below. clean= is how many of those docs came out with NO failed anchor — drift and dated both zero for that doc — so docs minus clean is exactly the number of <doc> rows below, before any paging window is applied. A doc whose anchors were all unchecked, or all prose, is clean here: clean means nothing was found rotten, not that everything was verified. prose= is the anchors dropped as prose, so it is SUBTRACTED from anchors= rather than added to it, and the verb does not claim to have checked them; only the VALUE shapes (`= N` and `[N]`) can be dropped this way, and the drop is itself a corpus lookup — the name was searched for and not found in code — not a pre-check guess. corpus= is the file population the anchors were checked AGAINST, and it is its OWN population rather than a relation to the map's files=: the indexed files this walk could re-read, PLUS a fixed set of config, shader and build-file extensions (CMakeLists.txt, .cmake, .yml/.yaml, .toml, .metal/.glsl/.hlsl and the like — an extension whitelist, never a content sniff), MINUS every file this walk could not open or that exceeded its own 4 MiB read ceiling, which is dropped silently and never counted. So corpus= is USUALLY larger than files= and that is the normal case, but it is not always: a crawl run whose max file size ceiling was raised above 4 MiB indexes files this walk still refuses, and a file the index lists but this run cannot open is counted by one and not the other. Neither number is wrong. corpus="0" means the corpus scan never ran at all, which happens only when the docs raised no anchor SHAPE whatsoever — prose ones included — so anchors="0" beside a non-zero prose= still scanned, and still reports the corpus it scanned. -->
<doc-drift docs="75" clean="65" anchors="430" checked="102" unchecked="328" drift="26" dated="9" prose="5" corpus="857" at="1dc07e27a+dirty">
<doc p="docs/COMMANDS.md" anchors="38" checked="13" drift="13" dated="0">
<a k="const" l="72" c="48" why="const-value" ref="est_tokens=428" want="428" got="619" tgt="src/main.cpp:7745"/>
<a k="const" l="108" c="49" why="const-value" ref="est_tokens=1278" want="1278" got="619" tgt="src/main.cpp:7745"/>
<a k="const" l="341" c="136" why="const-value" ref="est_tokens=45391" want="45391" got="619" tgt="src/main.cpp:7745"/>
<a k="const" l="455" c="50" why="const-value" ref="est_tokens=17250" want="17250" got="619" tgt="src/main.cpp:7745"/>
<a k="const" l="840" c="48" why="const-value" ref="est_tokens=588" want="588" got="619" tgt="src/main.cpp:7745"/>
<a k="const" l="901" c="49" why="const-value" ref="est_tokens=4907" want="4907" got="619" tgt="src/main.cpp:7745"/>
<a k="const" l="1083" c="49" why="const-value" ref="est_tokens=1027" want="1027" got="619" tgt="src/main.cpp:7745"/>
<a k="const" l="2111" c="48" why="const-value" ref="est_tokens=615" want="615" got="619" tgt="src/main.cpp:7745"/>
<a k="const" l="2183" c="48" why="const-value" ref="est_tokens=420" want="420" got="619" tgt="src/main.cpp:7745"/>
<a k="const" l="2215" c="48" why="const-value" ref="est_tokens=510" want="510" got="619" tgt="src/main.cpp:7745"/>
<a k="const" l="2248" c="48" why="const-value" ref="est_tokens=393" want="393" got="619" tgt="src/main.cpp:7745"/>
<a k="const" l="2287" c="48" why="const-value" ref="est_tokens=393" want="393" got="619" tgt="src/main.cpp:7745"/>
<more drift="1"/>
</doc>
<doc p="test/docdriftfix/NOTES.md" anchors="26" checked="15" drift="6" dated="0">
<a k="file-line" l="9" c="64" why="line-moved" ref="code.h:23" sym="stableHelper" got="movedHelper" tgt="test/docdriftfix/code.h:17"/>
<a k="file-line" l="10" c="58" why="past-eof" ref="code.h:900" sym="stableHelper" got="27 lines" tgt="test/docdriftfix/code.h"/>
<a k="file-line" l="11" c="53" why="missing-file" ref="deletedFile.h:12"/>
<a k="const" l="26" c="29" why="const-value" ref="kDriftedLimit = 10" want="10" got="15" tgt="test/docdriftfix/code.h:11"/>
<a k="array" l="28" c="49" why="array-extent" ref="kDriftedTable[16]" want="16" got="18" tgt="test/docdriftfix/code.h:14"/>
<a k="array" l="29" c="61" why="array-extent" ref="[16]" want="16" got="18" tgt="test/docdriftfix/code.h:14"/>
</doc>
<doc p="test/docdriftfix/live_notes.md" anchors="2" checked="2" drift="2" dated="0">
<a k="file-line" l="10" c="36" why="past-eof" ref="code.h:906" got="27 lines" tgt="test/docdriftfix/code.h"/>
<a k="file-line" l="17" c="36" why="past-eof" ref="code.h:907" got="27 lines" tgt="test/docdriftfix/code.h"/>
</doc>
<doc p="test/gateabilityfix/UNDATED.md" anchors="4" checked="4" drift="2" dated="0">
… [40 more display lines; full output is 11724 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --doc-drift --gateability`

*The finishable to-do list: docs whose LIVE failing anchors a date-stamp would reclassify.*

`````
<!-- ripwire doc drift: the CHECKABLE anchors in this repo's markdown, verified against the live index, reporting only the ones that no longer hold. Four kinds: file:line refs (missing-file / past-eof / line-moved, the last only when the doc names a symbol on that line), backticked symbol mentions (undefined), `= N` constants and `[N]` array extents (value/extent vs the declaration). Every lane under reports on purpose: a name is stale only when it occurs NOWHERE in the code as an identifier, and a number is compared only against a declaration shaped literal the corpus binds uniquely. checked + unchecked == anchors: nothing is dropped silently, and the unchecked rows say what was not proved. Read why="undefined" precisely: it says the name is defined NOWHERE in this repo, which is not the same as DELETED — in a plan or design doc naming work not yet built, that is expected rather than rot. Run with the with_history flag to have git history separate the two: the lane then reports why="deleted" with the commit that removed the name, and downgrades a name this repo never had to unchecked r="never in history". A failed anchor the AUTHOR DATED is split out as kind="dated-record" and counted in dated= rather than drift=: an audit finding, a ledger row or an as-of-DATE hedge records what was true then, so drift= is the LIVE rot and drift + dated is every anchor that no longer holds. rec= names the evidence (line / block / title / stamp), and a doc that never writes its own date anywhere a machine can read reports LIVE — the lane reads dating marks, it does not guess genre. Attribute vocabulary, one name one meaning: at= appears ONLY on this root element and is the commit the run was measured against (short sha, plus dirty when the tree had uncommitted changes); ref= is the anchor as the DOC writes it; got= is what the corpus actually says; and tgt= is the corpus SITE backing got= (a path, or path:line). On the <a/> rows k= and kind= are DIFFERENT things and both are kept: k= is the ANCHOR kind (file-line / symbol / const / array), kind= is the record classification (dated-record). k= cannot be renamed to kind= here for the obvious reason that kind= is already taken on the same element; note that in the ranked map the same k= spelling is a PageRank score instead. Docs are ordered by LIVE drift descending (path breaks ties), so the worst rot leads and a fully dated doc, which is drift zero by construction, sinks on the same key. Prose claims, Status lines and dates are NOT checked. FOUR COUNTERS on this element name four DIFFERENT populations, stated here because one of them openly disagrees with a number the map reports elsewhere. docs= is the DOCUMENTS scanned for anchors (markdown by extension, after any filter); it is the denominator of the doc rows below. clean= is how many of those docs came out with NO failed anchor — drift and dated both zero for that doc — so docs minus clean is exactly the number of <doc> rows below, before any paging window is applied. A doc whose anchors were all unchecked, or all prose, is clean here: clean means nothing was found rotten, not that everything was verified. prose= is the anchors dropped as prose, so it is SUBTRACTED from anchors= rather than added to it, and the verb does not claim to have checked them; only the VALUE shapes (`= N` and `[N]`) can be dropped this way, and the drop is itself a corpus lookup — the name was searched for and not found in code — not a pre-check guess. corpus= is the file population the anchors were checked AGAINST, and it is its OWN population rather than a relation to the map's files=: the indexed files this walk could re-read, PLUS a fixed set of config, shader and build-file extensions (CMakeLists.txt, .cmake, .yml/.yaml, .toml, .metal/.glsl/.hlsl and the like — an extension whitelist, never a content sniff), MINUS every file this walk could not open or that exceeded its own 4 MiB read ceiling, which is dropped silently and never counted. So corpus= is USUALLY larger than files= and that is the normal case, but it is not always: a crawl run whose max file size ceiling was raised above 4 MiB indexes files this walk still refuses, and a file the index lists but this run cannot open is counted by one and not the other. Neither number is wrong. corpus="0" means the corpus scan never ran at all, which happens only when the docs raised no anchor SHAPE whatsoever — prose ones included — so anchors="0" beside a non-zero prose= still scanned, and still reports the corpus it scanned. -->
<doc-drift docs="75" clean="65" anchors="430" checked="102" unchecked="328" drift="26" dated="9" prose="5" corpus="857" at="1dc07e27a+dirty">
<doc p="docs/COMMANDS.md" anchors="38" checked="13" drift="13" dated="0">
<a k="const" l="72" c="48" why="const-value" ref="est_tokens=428" want="428" got="619" tgt="src/main.cpp:7745"/>
<a k="const" l="108" c="49" why="const-value" ref="est_tokens=1278" want="1278" got="619" tgt="src/main.cpp:7745"/>
<a k="const" l="341" c="136" why="const-value" ref="est_tokens=45391" want="45391" got="619" tgt="src/main.cpp:7745"/>
<a k="const" l="455" c="50" why="const-value" ref="est_tokens=17250" want="17250" got="619" tgt="src/main.cpp:7745"/>
<a k="const" l="840" c="48" why="const-value" ref="est_tokens=588" want="588" got="619" tgt="src/main.cpp:7745"/>
<a k="const" l="901" c="49" why="const-value" ref="est_tokens=4907" want="4907" got="619" tgt="src/main.cpp:7745"/>
<a k="const" l="1083" c="49" why="const-value" ref="est_tokens=1027" want="1027" got="619" tgt="src/main.cpp:7745"/>
<a k="const" l="2111" c="48" why="const-value" ref="est_tokens=615" want="615" got="619" tgt="src/main.cpp:7745"/>
<a k="const" l="2183" c="48" why="const-value" ref="est_tokens=420" want="420" got="619" tgt="src/main.cpp:7745"/>
<a k="const" l="2215" c="48" why="const-value" ref="est_tokens=510" want="510" got="619" tgt="src/main.cpp:7745"/>
<a k="const" l="2248" c="48" why="const-value" ref="est_tokens=393" want="393" got="619" tgt="src/main.cpp:7745"/>
<a k="const" l="2287" c="48" why="const-value" ref="est_tokens=393" want="393" got="619" tgt="src/main.cpp:7745"/>
<more drift="1"/>
</doc>
<doc p="test/docdriftfix/NOTES.md" anchors="26" checked="15" drift="6" dated="0">
<a k="file-line" l="9" c="64" why="line-moved" ref="code.h:23" sym="stableHelper" got="movedHelper" tgt="test/docdriftfix/code.h:17"/>
<a k="file-line" l="10" c="58" why="past-eof" ref="code.h:900" sym="stableHelper" got="27 lines" tgt="test/docdriftfix/code.h"/>
<a k="file-line" l="11" c="53" why="missing-file" ref="deletedFile.h:12"/>
<a k="const" l="26" c="29" why="const-value" ref="kDriftedLimit = 10" want="10" got="15" tgt="test/docdriftfix/code.h:11"/>
<a k="array" l="28" c="49" why="array-extent" ref="kDriftedTable[16]" want="16" got="18" tgt="test/docdriftfix/code.h:14"/>
<a k="array" l="29" c="61" why="array-extent" ref="[16]" want="16" got="18" tgt="test/docdriftfix/code.h:14"/>
</doc>
<doc p="test/docdriftfix/live_notes.md" anchors="2" checked="2" drift="2" dated="0">
<a k="file-line" l="10" c="36" why="past-eof" ref="code.h:906" got="27 lines" tgt="test/docdriftfix/code.h"/>
<a k="file-line" l="17" c="36" why="past-eof" ref="code.h:907" got="27 lines" tgt="test/docdriftfix/code.h"/>
</doc>
<doc p="test/gateabilityfix/UNDATED.md" anchors="4" checked="4" drift="2" dated="0">
… [50 more display lines; full output is 12911 bytes on 1 raw line(s)]
`````

Tail of the same output — the `<gateability>` section:

`````
<gateability docs="7" projected_drift="0">
<fix p="docs/COMMANDS.md" live="13"/>
<fix p="test/docdriftfix/NOTES.md" live="6"/>
<fix p="test/docdriftfix/live_notes.md" live="2"/>
<fix p="test/gateabilityfix/UNDATED.md" live="2"/>
<fix p="bench/agentloop/README.md" live="1"/>
<fix p="test/docdriftfix/record_line.md" live="1"/>
<fix p="test/gateabilityfix/MIXED.md" live="1"/>
</gateability>
</doc-drift>
`````

## `./build/ripwire . --doc-drift --with-history`

*Same report, with git history splitting stale mentions into deleted-by-commit vs never-existed.*

`````
<!-- ripwire doc drift: the CHECKABLE anchors in this repo's markdown, verified against the live index, reporting only the ones that no longer hold. Four kinds: file:line refs (missing-file / past-eof / line-moved, the last only when the doc names a symbol on that line), backticked symbol mentions (undefined), `= N` constants and `[N]` array extents (value/extent vs the declaration). Every lane under reports on purpose: a name is stale only when it occurs NOWHERE in the code as an identifier, and a number is compared only against a declaration shaped literal the corpus binds uniquely. checked + unchecked == anchors: nothing is dropped silently, and the unchecked rows say what was not proved. Read why="undefined" precisely: it says the name is defined NOWHERE in this repo, which is not the same as DELETED — in a plan or design doc naming work not yet built, that is expected rather than rot. Run with the with_history flag to have git history separate the two: the lane then reports why="deleted" with the commit that removed the name, and downgrades a name this repo never had to unchecked r="never in history". A failed anchor the AUTHOR DATED is split out as kind="dated-record" and counted in dated= rather than drift=: an audit finding, a ledger row or an as-of-DATE hedge records what was true then, so drift= is the LIVE rot and drift + dated is every anchor that no longer holds. rec= names the evidence (line / block / title / stamp), and a doc that never writes its own date anywhere a machine can read reports LIVE — the lane reads dating marks, it does not guess genre. Attribute vocabulary, one name one meaning: at= appears ONLY on this root element and is the commit the run was measured against (short sha, plus dirty when the tree had uncommitted changes); ref= is the anchor as the DOC writes it; got= is what the corpus actually says; and tgt= is the corpus SITE backing got= (a path, or path:line). On the <a/> rows k= and kind= are DIFFERENT things and both are kept: k= is the ANCHOR kind (file-line / symbol / const / array), kind= is the record classification (dated-record). k= cannot be renamed to kind= here for the obvious reason that kind= is already taken on the same element; note that in the ranked map the same k= spelling is a PageRank score instead. Docs are ordered by LIVE drift descending (path breaks ties), so the worst rot leads and a fully dated doc, which is drift zero by construction, sinks on the same key. Prose claims, Status lines and dates are NOT checked. FOUR COUNTERS on this element name four DIFFERENT populations, stated here because one of them openly disagrees with a number the map reports elsewhere. docs= is the DOCUMENTS scanned for anchors (markdown by extension, after any filter); it is the denominator of the doc rows below. clean= is how many of those docs came out with NO failed anchor — drift and dated both zero for that doc — so docs minus clean is exactly the number of <doc> rows below, before any paging window is applied. A doc whose anchors were all unchecked, or all prose, is clean here: clean means nothing was found rotten, not that everything was verified. prose= is the anchors dropped as prose, so it is SUBTRACTED from anchors= rather than added to it, and the verb does not claim to have checked them; only the VALUE shapes (`= N` and `[N]`) can be dropped this way, and the drop is itself a corpus lookup — the name was searched for and not found in code — not a pre-check guess. corpus= is the file population the anchors were checked AGAINST, and it is its OWN population rather than a relation to the map's files=: the indexed files this walk could re-read, PLUS a fixed set of config, shader and build-file extensions (CMakeLists.txt, .cmake, .yml/.yaml, .toml, .metal/.glsl/.hlsl and the like — an extension whitelist, never a content sniff), MINUS every file this walk could not open or that exceeded its own 4 MiB read ceiling, which is dropped silently and never counted. So corpus= is USUALLY larger than files= and that is the normal case, but it is not always: a crawl run whose max file size ceiling was raised above 4 MiB indexes files this walk still refuses, and a file the index lists but this run cannot open is counted by one and not the other. Neither number is wrong. corpus="0" means the corpus scan never ran at all, which happens only when the docs raised no anchor SHAPE whatsoever — prose ones included — so anchors="0" beside a non-zero prose= still scanned, and still reports the corpus it scanned. -->
<doc-drift docs="75" clean="69" anchors="430" checked="95" unchecked="335" drift="22" dated="6" prose="5" corpus="857" at="1dc07e27a+dirty">
<history probed="1" head="1dc07e27a" commits="18" removed-names="6977"/>
<doc p="docs/COMMANDS.md" anchors="38" checked="13" drift="13" dated="0">
<a k="const" l="72" c="48" why="const-value" ref="est_tokens=428" want="428" got="619" tgt="src/main.cpp:7745"/>
<a k="const" l="108" c="49" why="const-value" ref="est_tokens=1278" want="1278" got="619" tgt="src/main.cpp:7745"/>
<a k="const" l="341" c="136" why="const-value" ref="est_tokens=45391" want="45391" got="619" tgt="src/main.cpp:7745"/>
<a k="const" l="455" c="50" why="const-value" ref="est_tokens=17250" want="17250" got="619" tgt="src/main.cpp:7745"/>
<a k="const" l="840" c="48" why="const-value" ref="est_tokens=588" want="588" got="619" tgt="src/main.cpp:7745"/>
<a k="const" l="901" c="49" why="const-value" ref="est_tokens=4907" want="4907" got="619" tgt="src/main.cpp:7745"/>
<a k="const" l="1083" c="49" why="const-value" ref="est_tokens=1027" want="1027" got="619" tgt="src/main.cpp:7745"/>
<a k="const" l="2111" c="48" why="const-value" ref="est_tokens=615" want="615" got="619" tgt="src/main.cpp:7745"/>
<a k="const" l="2183" c="48" why="const-value" ref="est_tokens=420" want="420" got="619" tgt="src/main.cpp:7745"/>
<a k="const" l="2215" c="48" why="const-value" ref="est_tokens=510" want="510" got="619" tgt="src/main.cpp:7745"/>
<a k="const" l="2248" c="48" why="const-value" ref="est_tokens=393" want="393" got="619" tgt="src/main.cpp:7745"/>
<a k="const" l="2287" c="48" why="const-value" ref="est_tokens=393" want="393" got="619" tgt="src/main.cpp:7745"/>
<more drift="1"/>
</doc>
<doc p="test/docdriftfix/NOTES.md" anchors="26" checked="15" drift="6" dated="0">
<a k="file-line" l="9" c="64" why="line-moved" ref="code.h:23" sym="stableHelper" got="movedHelper" tgt="test/docdriftfix/code.h:17"/>
<a k="file-line" l="10" c="58" why="past-eof" ref="code.h:900" sym="stableHelper" got="27 lines" tgt="test/docdriftfix/code.h"/>
<a k="file-line" l="11" c="53" why="missing-file" ref="deletedFile.h:12"/>
<a k="const" l="26" c="29" why="const-value" ref="kDriftedLimit = 10" want="10" got="15" tgt="test/docdriftfix/code.h:11"/>
<a k="array" l="28" c="49" why="array-extent" ref="kDriftedTable[16]" want="16" got="18" tgt="test/docdriftfix/code.h:14"/>
<a k="array" l="29" c="61" why="array-extent" ref="[16]" want="16" got="18" tgt="test/docdriftfix/code.h:14"/>
</doc>
<doc p="test/docdriftfix/live_notes.md" anchors="2" checked="2" drift="2" dated="0">
<a k="file-line" l="10" c="36" why="past-eof" ref="code.h:906" got="27 lines" tgt="test/docdriftfix/code.h"/>
<a k="file-line" l="17" c="36" why="past-eof" ref="code.h:907" got="27 lines" tgt="test/docdriftfix/code.h"/>
</doc>
… [27 more display lines; full output is 11168 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --from-trace=-`

*Map a pasted stack trace onto indexed symbols. CHANGED: in_corpus= now reports the real count (was 0).*

Input file:

`````
AddressSanitizer:DEADLYSIGNAL
=================================================================
==41337==ERROR: AddressSanitizer: SEGV on unknown address 0x000000000018 (pc 0x000102f4a1c8 bp 0x00016d2f1a40 sp 0x00016d2f19e0 T0)
    #0 0x102f4a1c8 in rw::rankGraphTeleport(Graph const&, std::vector<float> const&, float) src/graph.h:1148
    #1 0x102f3e884 in rw::rankGraph(Graph const&, float) src/graph.h:1174
    #2 0x102e11f30 in runDefaultMap(MainDispatch const&) src/main.cpp:5155
    #3 0x102e01a44 in main src/main.cpp:5594
    #4 0x1a2b3c0dc in start+0x9dc (dyld:arm64e+0x60dc)
==41337==ABORTING
`````

`````
<ctx task="&lt;stdin&gt;">
<!-- ripwire trace-to-locus for "<stdin>": frames of a asan trace mapped onto indexed symbols, ranked INNERMOST-first. frame_lines=5 parsed=4 in_corpus=4 skipped=0 (out of every root - listed, never ranked) merged=0 unresolved=0. frame_lines = frame-shaped lines the INPUT presented (a #N marker, a leading "at ", or a Python File "..." line, plus every line that did extract); parsed = how many of them yielded a usable path:line, so frame_lines - parsed is the count that matched no format shape and enters no bucket below. in_corpus = suspects + merged + unresolved, so every file-matched frame is visible: merged= folded into an already-claimed symbol, unresolved= listed as <unresolved> (indexed file, no def by name or by line). resolved_by="name" means the frame's OWN function name bound to a unique def (line_encloses=, when present, names the different symbol today's line sits in: the tell that the trace predates this checkout); resolved_by="line" means the name was absent, unknown or ambiguous, so the def enclosing that line was used. p= on a frame is the FRAME's own locator (the trace's path:line, verbatim); definition sites live in <sigs> l=. On a <sigs> row: n=name, id=canonical(when scoped), t=kind, cx=cyclomatic complexity, ccx=cognitive complexity, in=reuse-count (absent = not measured, never a false 0). rank 1 = the innermost in-corpus frame; its FULL body follows, other suspects as signatures. budget=7500 bytes (allowance 9583 bytes = ceiling + the single-entry overshoot a whole first signature costs). -->
<trace src="&lt;stdin&gt;" format="asan" frame_lines="5" parsed="4" in_corpus="4" skipped="0" merged="0" unresolved="0" suspects="4">
<frame rank="1" n="rankGraphTeleport" t="fn" p="src/graph.h:1148" resolved_by="name" line_encloses="buildGraph" innermost="1"/>
<frame rank="2" n="rankGraph" t="fn" p="src/graph.h:1174" resolved_by="name" line_encloses="buildGraph"/>
<frame rank="3" n="runDefaultMap" t="fn" p="src/main.cpp:5155" resolved_by="name" line_encloses="runNotes"/>
<frame rank="4" n="main" t="fn" p="src/main.cpp:5594" resolved_by="name"/>
</trace>
<sigs>
<f p="./src/graph.h">
<d l="1278" n="rankGraphTeleport" id="./src/graph.h::rw::rankGraphTeleport" cx="5" ccx="8" in="6">
<doc>PageRank with an explicit teleport / personalization vector p (Σp = 1). The prior is name-quality-biased (W4-#1) here so all rank modes share one weighting seam; the transition matrix (edges) is unto</doc>inline std::vector&lt;float&gt; rankGraphTeleport( const Graph&amp; g, const std::vector& … [line truncated: 46 more bytes on this line]
<d l="1304" n="rankGraph" id="./src/graph.h::rw::rankGraph" cx="2" ccx="1" in="9">
<doc>uniform-teleport PageRank (the default</doc>inline std::vector&lt;float&gt; rankGraph( const Graph&amp; g, float alpha = 0.85f )</d>
</f>
<f p="./src/main.cpp">
<d l="7276" n="runDefaultMap" cx="100" ccx="170" in="1">int runDefaultMap( const MainDispatch&amp; d )</d>
<d l="8007" n="main" cx="204" ccx="376" in="0">int main( int argc, char** argv )</d>
</f>
</sigs>
<bodies shown="1" total="1" capped="0">
<b t="fn" l="1278" p="./src/graph.h" n="rankGraphTeleport">
<![CDATA[inline std::vector<float> rankGraphTeleport( const Graph& g, const std::vector<float>& p, float alpha = 0.85f )
{
    PROFILE_SCOPE_DESCRIBE( "rankGraph: PageRank (power iteration)" );
    const std::vector<float> pw = biasPrior( g, p );
    const std::size_t N = pw.size();
    std::vector<double> teleport( pw.begin(), pw.end() );
    std::vector<double> rankDouble( N, 0.0 );
    if( N )
… [16 more display lines; full output is 4806 bytes on 24 raw line(s)]
`````

## `./build/ripwire . --notes`

*List all field notes (write-side memory). This repo still has no .ripwire_notes.*

`````
<ctx><!-- ripwire field notes: notes=0 targets=0 dangling=0 (a target with no matching indexed symbol/file — legal: listed here, surfaced nowhere) --><notes></notes></ctx>
`````

## `./build/ripwire . --pack-task="add a new output format flag to the CLI"`

*ONE budget-shared bundle: ranking + top bodies + caller sigs + notes + tests_to_run. CHANGED: <d> rows now carry n=/id=.*

`````
<ctx task="add a new output format flag to the CLI" route=" [routed: subtoken+body BM25 (--for&apos;s default) — no strong name hit, multi-word conceptual query]">
<!-- ripwire task bundle for "add a new output format flag to the CLI" [routed: subtoken+body BM25 (-for's default) — no strong name hit, multi-word conceptual query]: one-call orientation under ONE budget — sections in FIXED order ranking > bodies > callers > notes > tests, each truncates rank-adaptively; every truncation reported here (no silent caps): on every section shown=rows kept, total=rows that qualified, capped=1 when they differ. bodies fill rank-first, so a bigger budget can keep FEWER, larger bodies — the count is not a quality measure. Row keys: n=name (chain it), id=canonical(when scoped), in=reuse-count (absent = not measured, never a false 0), l=line, p=path, t=kind, cx=cyclomatic, ccx=cognitive, rel=caller|callee; far=ranked but over 1 hop out; of_top denominator is per-section. budget=12744 bytes (6000-token target, ceiling 14160) | ranking: full | bodies: kept 5 of 6 (capped) | callers: kept 11 of 16 | notes: none | tests: none | far: 6 of 6 -->
<sigs>
<f p="./src/main.cpp">
<d l="7850" n="ReportVerbSlot" id="./src/main.cpp::ReportVerbSlot::ReportVerbSlot" cx="0" ccx="0" in="0">
<doc>B11.4 — THE REPORT-VERB PRECEDENCE TABLE, in ripwire&apos;s real DISPATCH order (main()&apos;s handler chain, then each handler&apos;s own arm order). One row per verb-selecting flag, so adding a verb is adding</doc>struct ReportVerbSlot</d>
<d l="7900" n="jsonUnsupportedVerb" cx="72" ccx="72" in="1">const char* jsonUnsupportedVerb( const rw::Config&amp; c )</d>
</f>
<f p="./src/prcontext.h">
<d l="250" n="isCommitSha" id="./src/prcontext.h::rw::isCommitSha" cx="8" ccx="8" in="1">
<doc>A git object name is 40 (sha-1) or 64 (sha-256) lowercase hex characters. Checked explicitly rather than assumed so &quot;the revision token can never look like an option&quot; is a property this file PROVES ra</doc>inline bool isCommitSha( std::string_view s )</d>
</f>
<f p="./src/quality.h">
<d l="2124" n="readAckRecords" id="./src/quality.h::quality::readAckRecords" cx="16" ccx="21" in="2">
<doc>anywhere — so a round-trip (read whatever is on disk → merge in new findings → write) always SELF-HEALS the file back to canonical sorted order regardless of what shape it arrived in. Grammar (a</doc>inline gtl::btree_map&lt;std::string, AckRecord&gt; readAckRecords( const std::string&amp … [line truncated: 12 more bytes on this line]
</f>
<f p="./src/cli.h">
<d l="1267" n="BoolFlag" id="./src/cli.h::BoolFlag::BoolFlag" cx="0" ccx="0" in="0">
<doc>offsetof, which would be UB on a non-standard-layout type. ORDER. The tables are scanned in DECLARATION ORDER, exacts before prefixes, ahead of the hand-written arms — so the chain&apos;s original preced</doc>struct BoolFlag</d>
<d l="1881" n="validateColumnarVerb" id="./src/cli.h::rw::validateColumnarVerb" cx="6" ccx="3" in="1">
<doc>A5b — --format=columnar re-serializes a FLAT SYMBOL-ROW listing (a path table + parallel arrays), and only four verbs produce one. On any other verb it was accepted and silently ignored: --hotspot</doc>inline void validateColumnarVerb( Config&amp; c ) noexcept</d>
</f>
<far of_top="12" shown="6" total="6" capped="0">
<s t="fn" n="editCheckVerdict" p="./src/editcheck.h:258"/>
<s t="struct" n="McpVerbGroup" p="./src/mcp.h:44"/>
<s t="fn" n="toUint" p="./src/tracein.h:94"/>
<s t="fn" n="addRootFilesToGitPathIndex" p="./src/gitmine.h:700"/>
<s t="fn" n="dominantFormat" p="./src/tracein.h:323"/>
<s t="fn" n="formatRecallSeparator" p="./src/recall.h:383"/>
</far>
… [51 more display lines; full output is 8759 bytes on 44 raw line(s)]
`````

## `./build/ripwire . --pack-task="add a new output format flag to the CLI" --partition=3`

*Fan-out form: one shared core + 3 per-agent slices carved along call-graph communities.*

`````
<ctx-partitions partitions="3" requested="3" core_symbols="6" surface="42" modules="25" split="0" budget_per_agent_tokens="6000" core_budget_tokens="2040" partition_budget_tokens="3960" total_bytes="26620" overlap_mean="0.036" overlap_max="0.072" shared_symbols="5" union_symbols="88" core_overlap="0 … [line truncated: 6 more bytes on this line]
<!-- ripwire partitioned task bundle: ONE shared common core plus N minimally overlapping per agent slices, carved along the call graph's own community structure. Each bundle wraps one ctx document, exactly what a standalone pack task call with that slice would emit, so an orchestrator hands one bundle to one agent verbatim. budget_per_agent_tokens is the budget for core PLUS one partition, not the whole document; total_bytes is the bundles' combined size. overlap_mean/overlap_max are pairwise Jaccard over the ids each partition names (ranking window, bodies, and their 1 hop neighbors), measured BEFORE budget trimming, so they are a ceiling. shared_symbols counts the ids TWO OR MORE partitions name — NOT the ids every partition names; an id two of sixteen slices both carry is already duplicated work — and union_symbols the ids ANY partition names: one GLOBAL at-least-two over at-least-one pair, not an average. That ratio and overlap_mean (an average of PAIRWISE Jaccard) therefore answer different questions. They COINCIDE at partitions=2, where there is one pair and at-least-two IS its intersection while at-least-one IS its union, so the ratio equals that pair's Jaccard by identity; from 3 partitions on the two genuinely diverge, and neither is wrong. The remaining root counters, one clause each. requested= is the partition count N asked for and partitions= the bundles actually carved; partitions is lower only where the plan could not reach N, which is either a ranked surface that fit entirely in the shared core (partitions=0, nothing left to carve) or a surface holding fewer separable modules than N even after splitting. modules= is the distinct groups found on the assignable surface BEFORE any cut (a call-graph community, or the FILE where that surface carries no call edges), and split= the community cuts forced because those modules numbered fewer than N, so modules + split is the group count the bundles were packed from and split=0 means no cut was needed. core_symbols= is the shared core's size — the body anchors a plain pack task would have expanded, held out of every partition — and surface= is core_symbols plus the assignable remainder, i.e. the whole positive-rank window this plan carved up. core_budget_tokens= and partition_budget_tokens= are budget_per_agent_tokens split between the two halves one agent receives, and they sum to it. core_overlap is the share of the core bundle's own surface a partition reaches anyway. On each bundle, est_tokens and tokens are the SAME number: tokens is the original name kept for compatibility, est_tokens is the spelling the rest of the tool uses and the one to read. Both are that bundle's own bytes= divided by 2.36 B/tok — the DENSEST calibrated language rate — which is a different (deliberately conservative) currency from the default map's est_tokens, where the divisor is that corpus's own language-weighted rate: measured over real emitted bytes either way, but a bundle's number reads slightly HIGH, which is the safe direction for a per-agent budget. On this root element the unit is carried in the NAME instead (budget_per_agent_tokens, total_bytes) rather than by a separate unit attribute, which is a deliberate exception to the est_tokens convention and not a second estimator. -->
<bundle role="core" symbols="6" bytes="4604" tokens="1951" est_tokens="1951">
<ctx task="add a new output format flag to the CLI" route=" [routed: subtoken+body BM25 (--for&apos;s default) — no strong name hit, multi-word conceptual query]">
<!-- ripwire task bundle for "add a new output format flag to the CLI" [routed: subtoken+body BM25 (-for's default) — no strong name hit, multi-word conceptual query]: one-call orientation under ONE budget — sections in FIXED order ranking > bodies > callers > notes > tests, each truncates rank-adaptively; every truncation reported here (no silent caps): on every section shown=rows kept, total=rows that qualified, capped=1 when they differ. bodies fill rank-first, so a bigger budget can keep FEWER, larger bodies — the count is not a quality measure. Row keys: n=name (chain it), id=canonical(when scoped), in=reuse-count (absent = not measured, never a false 0), l=line, p=path, t=kind, cx=cyclomatic, ccx=cognitive, rel=caller|callee; far=ranked but over 1 hop out; of_top denominator is per-section. budget=4332 bytes (2040-token target, ceiling 4814) | ranking: capped | bodies: kept 4 of 6 (capped) | callers: omitted (budget) | notes: none | tests: none | far: none -->
<sigs capped="1">
<f p="./src/main.cpp">
<d l="7850" n="ReportVerbSlot" id="./src/main.cpp::ReportVerbSlot::ReportVerbSlot" cx="0" ccx="0" in="0">
<doc>B11.4 — THE REPORT-VERB PRECEDENCE TABLE, in ripwire&apos;s real DISPATCH order (main()&apos;s handler chain, then each handler&apos;s own arm order). One row per verb-selecting flag, so adding a verb is adding</doc>struct ReportVerbSlot</d>
<d l="7900" n="jsonUnsupportedVerb" cx="72" ccx="72" in="1">const char* jsonUnsupportedVerb( const rw::Config&amp; c )</d>
</f>
<f p="./src/prcontext.h">
<d l="250" n="isCommitSha" id="./src/prcontext.h::rw::isCommitSha" cx="8" ccx="8" in="1">
<doc>A git object name is 40 (sha-1) or 64 (sha-256) lowercase hex characters. Checked explicitly rather than assumed so &quot;the revision token can never look like an option&quot; is a property this file PROVES ra</doc>inline bool isCommitSha( std::string_view s )</d>
</f>
<f p="./src/quality.h">
<d l="2124" n="readAckRecords" id="./src/quality.h::quality::readAckRecords" cx="16" ccx="21" in="2">
<doc>anywhere — so a round-trip (read whatever is on disk → merge in new findings → write) always SELF-HEALS the file back to canonical sorted order regardless of what shape it arrived in. Grammar (a</doc>inline gtl::btree_map&lt;std::string, AckRecord&gt; readAckRecords( const std::string&amp … [line truncated: 12 more bytes on this line]
</f>
<f p="./src/cli.h">
<d l="1267" n="BoolFlag" id="./src/cli.h::BoolFlag::BoolFlag" cx="0" ccx="0" in="0">
<doc>offsetof, which would be UB on a non-standard-layout type. ORDER. The tables are scanned in DECL…</doc>struct BoolFlag</d>
<d l="1881" n="validateColumnarVerb" id="./src/cli.h::rw::validateColumnarVerb" cx="6" ccx="3" in="1">
<doc>A5b — --format=columnar re-serializes a FLAT SYMBOL-ROW listing (a path table + parallel array…</doc>inline void validateColumnarVerb( Config&amp; c ) noexcept</d>
</f>
</sigs>
<bodies shown="4" total="6" capped="1">
<b t="cls" l="7850" p="./src/main.cpp" n="ReportVerbSlot">
<![CDATA[struct ReportVerbSlot { const char* flag; bool isActive; }]]>
</b>
… [132 more display lines; full output is 30655 bytes on 130 raw line(s)]
`````

## `./build/ripwire . --for="pagerank power iteration" --with-graph`

*Task lens + a compact Mermaid flowchart of the top anchors' 1-hop edges.*

`````
<ctx task="pagerank power iteration" route=" [routed: subtoken+body BM25 (--for&apos;s default) — no strong name hit, multi-word conceptual query]">
<!-- ripwire lens for "pagerank power iteration" [routed: subtoken+body BM25 (-for's default) — no strong name hit, multi-word conceptual query]: reusable building blocks + quality facts for what you're about to touch (cx=complexity ccx=cognitive in=reuse-count churn=recent-commits amp=change-amplification clone=1(duplicated) tested=1) — prefer composing/reusing these; watch the high-churn/high-amp/cloned ones est_tokens="3099" -->
<sigs capped="1">
<f p="./src/pagerank.cpp">
<d l="34" n="pageRankDouble" id="./src/pagerank.cpp::rw::pageRankDouble" cx="18" ccx="33" in="1" churn="2" amp="1" tested="1">unsigned pageRankDouble( const sparseCsr&lt;float&gt;&amp; inEdges, std::span&lt;const double&gt; weightedOutDegree, std::span&lt;const double&gt; teleport, std::span&lt;doub … [line truncated: 21 more bytes on this line]
</f>
<f p="./src/infra/dynamic_map.hpp" layer="infra">
<d l="290" n="leaf_node" id="./src/infra/dynamic_map.hpp::leaf_node::leaf_node" cx="0" ccx="0" in="0" churn="1">struct alignas(16) leaf_node</d>
<d l="310" n="dynamic_map" id="./src/infra/dynamic_map.hpp::dynamic_map::dynamic_map" cx="0" ccx="0" in="0" churn="1">class dynamic_map</d>
<d l="979" n="values_begin" id="./src/infra/dynamic_map.hpp::dynamic_map::values_begin" cx="2" ccx="1" in="3" churn="1" amp="3">value_iterator values_begin()</d>
<d l="1327" n="compact" id="./src/infra/dynamic_map.hpp::dynamic_map::compact" cx="28" ccx="49" in="0" churn="1">void compact()</d>
<d l="2015" n="leftmost_leaf" id="./src/infra/dynamic_map.hpp::dynamic_map::leftmost_leaf" cx="2" ccx="1" in="7" churn="1" amp="7" pure="1">
<doc>iteration helpers</doc>handle_t leftmost_leaf() const</d>
</f>
<f p="./src/graph.h">
<d l="1278" n="rankGraphTeleport" id="./src/graph.h::rw::rankGraphTeleport" cx="5" ccx="8" in="6" churn="3" amp="6">
<doc>PageRank with an explicit teleport / personalization vector p (Σp = 1). The prior is name-quali…</doc>inline std::vector&lt;float&gt; rankGraphTeleport( const Graph&amp; g, const std::vector&lt;float&gt;&amp; p, float alpha = 0.85f )</d>
<d l="1327" n="hits" id="./src/graph.h::rw::hits" cx="9" ccx="16" in="1" churn="3" amp="1">inline std::pair&lt;std::vector&lt;float&gt;, std::vector&lt;float&gt;&gt; hits( const Graph&amp; g, float tol = 1e-6f, unsigned maxIter = 100 )</d>
<d l="1742" n="computeQMetrics" id="./src/graph.h::rw::computeQMetrics" cx="52" ccx="124" in="2" churn="3" amp="2">inline QMetrics computeQMetrics( const IngestResult&amp; ing, const Graph&amp; g )</d>
<d l="2414" n="louvainLocalMoving" id="./src/graph.h::rw::louvainLocalMoving" cx="18" ccx="35" in="2" churn="3" amp="2">inline Communities louvainLocalMoving( const std::vector&lt;std::vector&lt;WEdge&gt;&gt;&amp; adj )</d>
</f>
<f p="./src/serialize.h">
<d l="918" n="MapAnnotations" id="./src/serialize.h::MapAnnotations::MapAnnotations" cx="0" ccx="0" in="0" churn="3">struct MapAnnotations</d>
<d l="988" n="rankByLegendFor" id="./src/serialize.h::rw::rankByLegendFor" cx="4" ccx="4" in="1" churn="3" amp="1">
<doc>The label → clause lookup. Returns nullptr for an unstamped map (the default pagerank path) so…</doc>inline const char* rankByLegendFor( const char* label ) noexcept</d>
<d l="3768" n="writeJsonMapStamp" id="./src/serialize.h::rw::writeJsonMapStamp" cx="10" ccx="12" in="1" churn="3" amp="1">inline void writeJsonMapStamp( JsonWriter&amp; w, std::string&amp; esc, const MapAnnotations* ann )</d>
<d l="3900" n="serializeJson" id="./src/serialize.h::rw::serializeJson" cx="49" ccx="82" in="1" churn="3" amp="1">inline void serializeJson( std::FILE* out, const IngestResult&amp; ing, const std::vector&lt;float&gt;&amp; ra…</d>
</f>
<f p="./src/pagerank.h">
<d l="11" n="PageRankConfig" id="./src/pagerank.h::PageRankConfig::PageRankConfig" cx="0" ccx="0" in="0" churn="2">struct PageRankConfig</d>
… [55 more display lines; full output is 7747 bytes on 12 raw line(s)]
`````

## `./build/ripwire . --export=cc.json:/var/folders/_7/1b0h5mxs3vl2jgb9jk3qzw7r0000gn/T/ripwire_showcase_fxbqqxez/aux/ripwire2.cc.json`

*Per-file metrics as CodeCharta cc.json.*

`````
(empty)
`````

Artifact written:

`````
-rw-r--r--@ 1 qgames  staff  126163 Jul 31 20:15 /var/folders/_7/1b0h5mxs3vl2jgb9jk3qzw7r0000gn/T/ripwire_showcase_fxbqqxez/aux/ripwire2.cc.json
{"projectName":"project","apiVersion":"1.3","attributeDescriptors":{"loc":{"title":"Lines of Code","description":"Physical line count","direction":-1},"symbols":{"title":"Symbols","description":"Definitions in the file","direction":-1},"cx":{"title":"Cyclomatic Complexity","description":"Sum of per-symbol cyclomatic complexity","direction":-1},"cognitive_cx":{"title":"Cognitive Complexity","descri
`````

## `./build/ripwire . --batch=/var/folders/_7/1b0h5mxs3vl2jgb9jk3qzw7r0000gn/T/ripwire_showcase_fxbqqxez/aux/batch2.txt`

*One-turn sweep: 4 newline-delimited verb:arg sub-queries answered in ONE deduped <batch>.*

Input file:

`````
for:incremental cache invalidation
callers:rankGraphTeleport
grep:DEGRADED_PATH_ALERT
lego:Vehicle
`````

`````
<batch n="4" requested="4" cap="16">
<!-- ripwire batch: N read sub-queries answered in one sweep. Each <q> carries i=index, verb=sub-verb, ok=1|0; the sub-answer rides verbatim in CDATA (a mix of XML and JSON payloads); <dup-of q="i"/> means this payload is byte-identical to the one already emitted at index i; ok=0 carries err= and no payload. Over-cap batches set capped="1" with n<requested. -->
<q i="0" verb="for" ok="1">
<![CDATA[<ctx task="incremental cache invalidation" route=" [routed: subtoken+body BM25 (--for&apos;s default) — no strong name hit, multi-word conceptual query]">
<!-- ripwire lens for "incremental cache invalidation" [routed: subtoken+body BM25 (-for's default) — no strong name hit, multi-word conceptual query]: reusable building blocks (cx=complexity, in=reuse-count) — prefer composing/reusing these over reimplementing -->
<sigs capped="1">
<f p="./src/ingest.h">
<d l="85" n="ingest" id="./src/ingest.h::rw::ingest" cx="1" ccx="0" in="0">
<doc>for vendored/generated trees not caught by the built-in dir denylist (--exclude=SUBSTR). cacheFi…</doc>IngestResult ingest( const char* rootDir, const std::vector&lt;std::string&gt;&amp; excludeSubstr =</d>
</f>
<f p="./src/serialize.h">
<d l="1612" n="pureFromSig" id="./src/serialize.h::rw::pureFromSig" cx="6" ccx="5" in="3">inline bool pureFromSig( const std::string&amp; sig, Lang lang = Lang::Cpp )</d>
<d l="1625" n="docCommentBefore" id="./src/serialize.h::rw::docCommentBefore" cx="67" ccx="74" in="2">inline std::string docCommentBefore( const std::string&amp; src, std::size_t defStart )</d>
<d l="3254" n="legoImplementorsOnSurface" id="./src/serialize.h::rw::legoImplementorsOnSurface" cx="10" ccx="13" in="2">
<doc>P3 SCOPE (bundle embeddings only). packLego&apos;s ranked mode treats &quot;has implementors&quot; as &quot;is an in…</doc>inline std::vector&lt;std::vector&lt;NodeId&gt;&gt; legoImplementorsOnSurface( const IngestResult&amp; ing, const std::vector&lt;std::vector&lt;NodeId&gt;&gt;&amp; implem … [line truncated: 29 more bytes on this line]
</f>
<f p="./src/quality.h">
<d l="300" n="bodyHashesBySym" id="./src/quality.h::quality::bodyHashesBySym" cx="16" ccx="29" in="4">inline gtl::btree_map&lt;std::uint64_t, std::uint64_t&gt; bodyHashesBySym( const IngestResult&amp; ing, st…</d>
<d l="357" n="cacheDirLadder" id="./src/quality.h::quality::cacheDirLadder" cx="7" ccx="7" in="10">inline std::string cacheDirLadder()</d>
<d l="554" n="headSnapRepoHex" id="./src/quality.h::quality::headSnapRepoHex" cx="3" ccx="2" in="5">inline std::string headSnapRepoHex( const std::string&amp; root )</d>
<d l="608" n="extractionIdentityTag" id="./src/quality.h::quality::extractionIdentityTag" cx="1" ccx="0" in="1">inline std::string extractionIdentityTag()</d>
<d l="625" n="exclConfigHex" id="./src/quality.h::quality::exclConfigHex" cx="2" ccx="1" in="5">inline std::string exclConfigHex( const std::vector&lt;std::string&gt;&amp; excludes, const std::string&amp; s…</d>
<d l="640" n="headSnapExclHex" id="./src/quality.h::quality::headSnapExclHex" cx="1" ccx="0" in="2">inline std::string headSnapExclHex( const std::vector&lt;std::string&gt;&amp; excludes, std::size_t maxFil…</d>
<d l="660" n="blobShardHex" id="./src/quality.h::quality::blobShardHex" cx="1" ccx="0" in="1">inline std::string blobShardHex( std::string_view filename )</d>
<d l="667" n="resolveCacheBlobPath" id="./src/quality.h::quality::resolveCacheBlobPath" cx="4" ccx="3" in="2">inline std::string resolveCacheBlobPath( const std::string&amp; dir, const std::string&amp; filename )</d>
<d l="686" n="shaKeyedCachePath" id="./src/quality.h::quality::shaKeyedCachePath" cx="1" ccx="0" in="6">inline std::string shaKeyedCachePath( const char* family, const std::string&amp; repoHex, const std::string&amp; exclHex, const std::string&amp; sha )</d>
<d l="695" n="headSnapCachePath" id="./src/quality.h::quality::headSnapCachePath" cx="1" ccx="0" in="2">inline std::string headSnapCachePath( const std::string&amp; repoHex, const std::string&amp; exclHex, const std::string&amp; headSha )</d>
<d l="724" n="evictOldCacheFamily" id="./src/quality.h::quality::evictOldCacheFamily" cx="39" ccx="70" in="4">inline void evictOldCacheFamily( const std::string&amp; dir, const std::string&amp; prefix, const std::s…</d>
<d l="865" n="sweepStaleCacheBlobsOnce" id="./src/quality.h::quality::sweepStaleCacheBlobsOnce" cx="2" ccx="1" in="1">inline void sweepStaleCacheBlobsOnce( const std::string&amp; dir, const std::string&amp; keepPath )</d>
<d l="875" n="evictOldHeadSnapCaches" id="./src/quality.h::quality::evictOldHeadSnapCaches" cx="1" ccx="0" in="2">inline void evictOldHeadSnapCaches( const std::string&amp; dir, const std::string&amp; repoHex, const std::string&amp; exclHex, const std::string&amp; keepPath, std::size_t keep = 2 )</d … [line truncated: 1 more bytes on this line]
… [50 more display lines; full output is 15409 bytes on 1 raw line(s)]
`````


---

# self-diagnosis

## `./build/ripwire . --doctor`

*Environment self-check: binary staleness, grammars, cache dir, git, tracked-binary staleness.*

`````
<doctor checks="6" passed="6" at="1dc07e27a+dirty">
<c n="binary-path" ok="1" self="./build/ripwire" which="" on_path="0"/>
<c n="grammars" ok="1" loaded="13" expected="13"/>
<c n="cache-dir" ok="1" dir="/var/folders/_7/1b0h5mxs3vl2jgb9jk3qzw7r0000gn/T" blobs="1794" bytes="26337442" many="1"/>
<c n="git" ok="1" git="1" repo="1" history="1" head="1dc07e27a"/>
<c n="tree-sitter" ok="1" core_abi="15" cpp_grammar_abi="14" languages="13"/>
<c n="tracked-binaries" ok="1" tracked="1077" binaries="2" non_git="0" truncated="0" stale="0"/>
</doctor>
`````


---

# security

## `./build/ripwire --scan-skill=skills/ripwire-orient/SKILL.md`

*Scan a single skill file for injection/exfiltration patterns before installing.*

`````
<skillscan files="1" findings="0" verdict="clean"></skillscan>
`````

stderr:

`````
ripwire scan: 0 finding(s) in skills/ripwire-orient/SKILL.md
`````

## `./build/ripwire --scan-skills=skills`

*Scan a whole skills directory (exit 2 = CRITICAL, 1 = WARN). Explicit-DIR form only.*

`````
<skillscan files="24" findings="0" verdict="clean"></skillscan>
`````

stderr:

`````
ripwire scan: 0 finding(s) total (24 skill file(s) scanned, 0 unscannable file(s) skipped, 0 denylisted subtree(s) not descended)
`````


---

# knobs / modes

## `./build/ripwire . --rank-by=churn --top-k=5`

*Rank by git change-frequency prior instead of PageRank.*

`````
<!-- ripwire v1 t=fn|method|cls|struct|iface|var|sec p=path layer=arch-layer(opt) n=name id=canonical(path::scope::name,when-scoped) k=rank c=call amb=ambiguous-calls(read-source) overloads=N-same-name-defs-merged-into-this-row(absent-if-1;shown=counts-them-individually,so-rows+sum(overloads-1)=shown) prov=scip(precise;else name-based) hdr:unresolved=call-name-defined-only-in-a-lang-incompatible-file (edges heuristic) r:est_tokens=hdr-copy(none-if-stable) -->
<!-- rank_by=churn: k= is a git CHANGE-FREQUENCY prior over window=, not call-graph importance; the same corpus ranked by pagerank orders differently -->
<!-- at= is the git commit these numbers were computed at; a trailing +dirty means the working tree differed from that commit, so the numbers describe the tree, not the commit -->
<!-- files=836 symbols=6432 edges=8733 shown=5 est_tokens=582 ambiguous=2631 unresolved=652 precise=3 skipped_oversize=3 order=important-first -->
<r at="1dc07e27a+dirty" rank_by="churn" window="18mo" est_tokens="582">
<f p="./src/svector.h">
<s t="method" n="size" id="./src/svector.h::svector::size" k="0.0479">
</s>
<s t="method" n="push_back" id="./src/svector.h::svector::push_back" amb="2" k="0.0126">
<c n="buf"/>
<c n="buf"/>
<c n="grow"/>
</s>
<s t="method" n="buf" id="./src/svector.h::svector::buf" overloads="2" k="0.0116">
</s>
</f>
<f p="./src/scipoverlay.h">
<s t="method" n="empty" id="./src/scipoverlay.h::ScipOverlay::empty" k="0.0122">
</s>
</f>
</r>
`````

## `./build/ripwire . --rank-by=bogus --top-k=5`

*CHANGED: an unknown value is now NAMED, with the supported set listed.*

**exit code: 1**

`````
(empty)
`````

stderr:

`````
ripwire: --rank-by: unknown value 'bogus' (supported: pagerank|authority|hub|rrf|churn)
`````

## `./build/ripwire . --callers=rankGraphTeleport --format=columnar`

*Columnar output: paths table + parallel arrays, ~15-60% fewer tokens on MANY-row lists — small results can be LARGER (the columnar legend is a fixed cost).*

`````
<!-- ripwire callers/callees: the 1-hop call hierarchy read straight off the call graph. The callers form lists the symbols that CALL of=; the callees form lists the symbols of= itself calls. of= is the selector you passed, defs= how many DEFINITIONS that name resolved to (the rows UNION every def's neighbours), and count= the number of DISTINCT neighbour symbols (a floor, per counts_floor=), which the rows window with limit= and offset=. counts_floor="1" means every count on this element is a FLOOR, never a total. Call edges are extracted from source text by NAME, so a call that reaches its target through dynamic dispatch (a virtual, interface or duck-typed receiver), a callback or function pointer, a macro-generated call site, or a declaration that parses without a call expression (C++ most-vexing-parse) contributes no edge and is missing here. Read a zero as "none found", never as "none exists". COUNTING UNIT, and it differs by verb — which is why two of them report different numbers for one symbol. The callers, callees, edit-check, graph-query and pr-context counts are DISTINCT SYMBOLS: repeated calls from one caller, and calls to two overloads of one name, collapse into ONE row, their multiplicity surviving only in the call graph's edge weight. The reach counts (impact's reaches=, pr-context's dependents=) are the size of a transitive reach SET, each symbol counted once — not a count of calls or edges. The uses verb counts call SITES, one row per occurrence, so a larger count= there for the same symbol is these units agreeing, not disagreeing. The map header's edges= is a unit again different — distinct (caller,callee) PAIRS — and that document carries neither this marker nor this clause, so its numbers answer a different question. -->
<!-- format=columnar: PARALLEL ARRAYS, not per-row attributes — the t=/n=/p= attributes this verb's XML row form carries are NOT emitted in this form. Zip by index: <paths> maps `I=path`; each array under <cols> holds exactly n= comma-separated values in ONE shared row order, and the path column is an index into <paths>. fields= names the columns, in array order. n="0" (an empty page) means every array is present and empty. A ',' inside a VALUE is escaped as &#44; (ordinary XML entity decoding restores it), so splitting a row array on ',' can never mis-zip. -->
<callers of="rankGraphTeleport" defs="1" count="6" counts_floor="1" format="columnar">
<paths>0=./src/eval.h 1=./src/graph.h 2=./src/main.cpp 3=./src/mcpindex.h</paths>
<cols n="6" fields="path,name,line,kind">
<path>0,1,1,2,2,3</path>
<name>runEval,rankGraph,anchoredLexicalRank,churnRankedGraph,runDefaultMap,getIndex</name>
<line>133,1304,1553,7246,7276,734</line>
<kind>fn,fn,fn,fn,fn,fn</kind>
</cols>
</callers>
`````

## `./build/ripwire . --for="cache invalidation" --format=candidates --top-k=5`

*Flat top-K export for an external reranker.*

`````
<!-- ripwire candidates: flat top K export for an external reranker. r=rank(1 based) s=SCORE n=name id=canonical k=KIND-tag p=path l=line. Note k= is the kind here and the PageRank score in the ranked map; on this row the score is s=. Root: count= rows exported of total= RANKED CORPUS symbols (total is the corpus size, never a match count), capped="1" means the top-k cut dropped some; route= names the ranker (s= is comparable only within one route); anchored= counts query-mention lifts (0 = the anchor ran and moved nothing); weak="1" means the top raw lexical score is below the confidence bar, so these rows rest on thin textual evidence. -->
<candidates count="5" total="6432" capped="1" route="subtoken+body" anchored="0">
<cand r="1" s="8.05944" n="legoImplementorsOnSurface" id="./src/serialize.h::rw::legoImplementorsOnSurface" k="fn" p="./src/serialize.h" l="3254">
<sig>inline std::vector&lt;std::vector&lt;NodeId&gt;&gt; legoImplementorsOnSurface( const IngestResult&amp; ing, const std::vector&lt;std::vector&lt;NodeId&gt;&gt;&amp; implementors, const std::vector&lt;NodeId&gt;&amp; surfaceIds )</sig>
</cand>
<cand r="2" s="6.51735" n="sweepStaleCacheBlobsOnce" id="./src/quality.h::quality::sweepStaleCacheBlobsOnce" k="fn" p="./src/quality.h" l="865">
<sig>inline void sweepStaleCacheBlobsOnce( const std::string&amp; dir, const std::string&amp; keepPath )</sig>
</cand>
<cand r="3" s="6.48678" n="msCachePath" id="./src/mergescout.h::mergescout::msCachePath" k="fn" p="./src/mergescout.h" l="147">
<sig>inline std::string msCachePath( const std::string&amp; repoHex, const std::string&amp; exclHex, const std::string&amp; sha )</sig>
</cand>
<cand r="4" s="6.48018" n="cacheDirLadder" id="./src/quality.h::quality::cacheDirLadder" k="fn" p="./src/quality.h" l="357">
<sig>inline std::string cacheDirLadder()</sig>
</cand>
<cand r="5" s="6.47908" n="qbodyCachePath" id="./src/quality.h::quality::qbodyCachePath" k="fn" p="./src/quality.h" l="977">
<sig>inline std::string qbodyCachePath( const std::string&amp; repoHex, const std::string&amp; exclHex, const std::string&amp; refSha )</sig>
</cand>
</candidates>
`````

stderr:

`````
ripwire: --top-k is not read by --for — it shapes the default map, --query, --format=candidates, --recall and --graph-query. --for emitted its full result (nothing was dropped); narrow it with the verb's own arguments instead
`````

## `./build/ripwire . --callers=rankGraphTeleport --format=bogus`

*CHANGED: unknown --format value named + supported set listed.*

**exit code: 1**

`````
(empty)
`````

stderr:

`````
ripwire: --format: unknown value 'bogus' (supported: xml|columnar|rows|candidates)
`````

## `./build/ripwire . --callers=rankGraphTeleport --json`

*Machine-parseable JSON, same content, keys mirror the XML attrs.*

`````
{"of":"rankGraphTeleport","defs":1,"count":6,"counts_floor":true,"callers":[{"t":"fn","n":"runEval","p":"./src/eval.h:133"},
{"t":"fn","n":"rankGraph","p":"./src/graph.h:1304"},
{"t":"fn","n":"anchoredLexicalRank","p":"./src/graph.h:1553"},
{"t":"fn","n":"churnRankedGraph","p":"./src/main.cpp:7246"},
{"t":"fn","n":"runDefaultMap","p":"./src/main.cpp:7276"},
{"t":"fn","n":"getIndex","p":"./src/mcpindex.h:734"}]}
`````

## `./build/ripwire . --hotspots --json`

*JSON refusal shape: an unsupported verb refuses loudly instead of silently falling back to XML.*

**exit code: 1**

`````
(empty)
`````

stderr:

`````
ripwire: --json is not yet supported for --hotspots — supported: the default map, --for, --pack-task, --callers/--callees, --impact, --quality-delta, --test-gate, --metrics (e.g. ripwire <dir> --callers=SYM --json)
`````

## `./build/ripwire . --hotspots --limit=3 --offset=3`

*Pagination: 3 items, skipping the first 3 (deterministic seams).*

`````
<!-- ripwire hotspots: maintenance-pain = complexity × recent churn (window=12mo). churn=commits touching the file; ccx=Σ cognitive complexity; score=churn×ccx; top=worst function. files= is the DENOMINATOR ranked= is drawn from, and a hotspot needs both factors nonzero, so ranked= + unranked_no_churn= + unranked_no_complexity= = files= exactly. unranked_no_complexity= is a file with commits but no function or method to score (a pure declaration header, markdown, config). unranked_no_churn= is a file no in-window commit was attributed to — and it CONFLATES two cases this verb cannot tell apart: a genuinely quiet file, and one whose path the git-to-index join never bound (a rename, an exclusion, or a spelling the join could not match), which scores zero for a reason that is not about the file. Treat it as an upper bound on quietness, not a measure of it. raise the default cap with limit=N (offset=M pages) -->
<!-- at= is the git commit these numbers were computed at; a trailing +dirty means the working tree differed from that commit, so the numbers describe the tree, not the commit -->
<hotspots window="12mo" files="836" ranked="221" unranked_no_churn="0" unranked_no_complexity="615" shown="3" capped="1" total="221" has_more="1" next_offset="6" offset="3" limit="3" at="1dc07e27a+dirty">
<f p="./src/graph.h" churn="3" ccx="1424" score="4272" top="buildGraph" top_ccx="712" top_l="379"/>
<f p="./src/quality.h" churn="3" ccx="700" score="2100" top="computeDelta" top_ccx="236" top_l="2204"/>
<f p="./src/layout.h" churn="3" ccx="694" score="2082" top="writeLayout" top_ccx="31" top_l="1870"/>
</hotspots>
`````

## `./build/ripwire . --ignore-tests --top-k=5`

*Drop test paths from the corpus before ranking.*

`````
<!-- ripwire v1 t=fn|method|cls|struct|iface|var|sec p=path layer=arch-layer(opt) n=name id=canonical(path::scope::name,when-scoped) k=rank c=call amb=ambiguous-calls(read-source) overloads=N-same-name-defs-merged-into-this-row(absent-if-1;shown=counts-them-individually,so-rows+sum(overloads-1)=shown) hdr:unresolved=call-name-defined-only-in-a-lang-incompatible-file (edges heuristic) r:est_tokens=hdr-copy(none-if-stable) -->
<!-- files=836 symbols=3830 edges=7780 shown=5 est_tokens=410 ambiguous=2587 unresolved=434 skipped_oversize=3 order=important-first -->
<r est_tokens="410">
<f p="./src/svector.h">
<s t="method" n="size" id="./src/svector.h::svector::size" k="0.0677">
</s>
<s t="method" n="push_back" id="./src/svector.h::svector::push_back" amb="2" k="0.0173">
<c n="buf"/>
<c n="buf"/>
<c n="grow"/>
</s>
<s t="method" n="buf" id="./src/svector.h::svector::buf" overloads="2" k="0.0163">
</s>
</f>
<f p="./src/scipoverlay.h">
<s t="method" n="empty" id="./src/scipoverlay.h::ScipOverlay::empty" k="0.0170">
</s>
</f>
</r>
`````

## `./build/ripwire . --exclude=present --exclude=bench --top-k=5`

*Drop matching paths (repeatable) before ranking.*

`````
<!-- ripwire v1 t=fn|method|cls|struct|iface|var|sec p=path layer=arch-layer(opt) n=name id=canonical(path::scope::name,when-scoped) k=rank c=call amb=ambiguous-calls(read-source) overloads=N-same-name-defs-merged-into-this-row(absent-if-1;shown=counts-them-individually,so-rows+sum(overloads-1)=shown) prov=scip(precise;else name-based) hdr:unresolved=call-name-defined-only-in-a-lang-incompatible-file (edges heuristic) r:est_tokens=hdr-copy(none-if-stable) -->
<!-- files=768 symbols=5651 edges=8288 shown=5 est_tokens=420 ambiguous=2619 unresolved=262 precise=3 order=important-first -->
<r est_tokens="420">
<f p="./src/svector.h">
<s t="method" n="size" id="./src/svector.h::svector::size" k="0.0552">
</s>
<s t="method" n="push_back" id="./src/svector.h::svector::push_back" amb="2" k="0.0143">
<c n="buf"/>
<c n="buf"/>
<c n="grow"/>
</s>
<s t="method" n="buf" id="./src/svector.h::svector::buf" overloads="2" k="0.0133">
</s>
</f>
<f p="./src/scipoverlay.h">
<s t="method" n="empty" id="./src/scipoverlay.h::ScipOverlay::empty" k="0.0138">
</s>
</f>
</r>
`````

## `./build/ripwire . --map-diff --top-k=5`

*Full map re-ranked with teleport toward git-changed files — clean tree, so changed=0 and it degrades to the plain map.*

`````
<!-- ripwire v1 t=fn|method|cls|struct|iface|var|sec p=path layer=arch-layer(opt) n=name id=canonical(path::scope::name,when-scoped) k=rank c=call amb=ambiguous-calls(read-source) overloads=N-same-name-defs-merged-into-this-row(absent-if-1;shown=counts-them-individually,so-rows+sum(overloads-1)=shown) prov=scip(precise;else name-based) hdr:unresolved=call-name-defined-only-in-a-lang-incompatible-file (edges heuristic) r:est_tokens=hdr-copy(none-if-stable) -->
<!-- at= is the git commit these numbers were computed at; a trailing +dirty means the working tree differed from that commit, so the numbers describe the tree, not the commit -->
<!-- files=836 symbols=6432 edges=8733 shown=5 est_tokens=544 ambiguous=2631 unresolved=652 precise=3 changed=3 skipped_oversize=3 order=important-first -->
<r at="1dc07e27a+dirty" est_tokens="544">
<f p="./src/svector.h">
<s t="method" n="size" id="./src/svector.h::svector::size" k="0.0492">
</s>
</f>
<f p="./src/scipoverlay.h">
<s t="method" n="empty" id="./src/scipoverlay.h::ScipOverlay::empty" k="0.0266">
</s>
</f>
<f p="./src/notes.h">
<s t="method" n="empty" id="./src/notes.h::NoteIndex::empty" k="0.0250">
</s>
</f>
<f p="./test/pargates.py" layer="test">
<s t="fn" n="run" k="0.0235">
</s>
</f>
<f p="./src/cli.h">
<s t="fn" n="printPlanLanesUsage" id="./src/cli.h::rw::printPlanLanesUsage" k="0.0161">
</s>
</f>
</r>
`````

## `./build/ripwire . --no-cache --top-k=3`

*Force a cold parse (bypass the warm TMPDIR cache) — shows the cold-vs-warm cost.*

`````
<!-- ripwire v1 t=fn|method|cls|struct|iface|var|sec p=path layer=arch-layer(opt) n=name id=canonical(path::scope::name,when-scoped) k=rank c=call amb=ambiguous-calls(read-source) overloads=N-same-name-defs-merged-into-this-row(absent-if-1;shown=counts-them-individually,so-rows+sum(overloads-1)=shown) prov=scip(precise;else name-based) hdr:unresolved=call-name-defined-only-in-a-lang-incompatible-file (edges heuristic) r:est_tokens=hdr-copy(none-if-stable) -->
<!-- files=836 symbols=6432 edges=8733 shown=3 est_tokens=393 ambiguous=2631 unresolved=652 precise=3 skipped_oversize=3 order=important-first -->
<r est_tokens="393">
<f p="./src/svector.h">
<s t="method" n="size" id="./src/svector.h::svector::size" k="0.0503">
</s>
<s t="method" n="push_back" id="./src/svector.h::svector::push_back" amb="2" k="0.0133">
<c n="buf"/>
<c n="buf"/>
<c n="grow"/>
</s>
</f>
<f p="./src/scipoverlay.h">
<s t="method" n="empty" id="./src/scipoverlay.h::ScipOverlay::empty" k="0.0126">
</s>
</f>
</r>
`````

## `./build/ripwire . --cache=/var/folders/_7/1b0h5mxs3vl2jgb9jk3qzw7r0000gn/T/ripwire_showcase_fxbqqxez/aux/warm2.ripwirecache --top-k=3`

*Explicit incremental cache at a path OUTSIDE the repo (first call writes it).*

`````
<!-- ripwire v1 t=fn|method|cls|struct|iface|var|sec p=path layer=arch-layer(opt) n=name id=canonical(path::scope::name,when-scoped) k=rank c=call amb=ambiguous-calls(read-source) overloads=N-same-name-defs-merged-into-this-row(absent-if-1;shown=counts-them-individually,so-rows+sum(overloads-1)=shown) prov=scip(precise;else name-based) hdr:unresolved=call-name-defined-only-in-a-lang-incompatible-file (edges heuristic) r:est_tokens=hdr-copy(none-if-stable) -->
<!-- files=836 symbols=6432 edges=8733 shown=3 est_tokens=393 ambiguous=2631 unresolved=652 precise=3 skipped_oversize=3 order=important-first -->
<r est_tokens="393">
<f p="./src/svector.h">
<s t="method" n="size" id="./src/svector.h::svector::size" k="0.0503">
</s>
<s t="method" n="push_back" id="./src/svector.h::svector::push_back" amb="2" k="0.0133">
<c n="buf"/>
<c n="buf"/>
<c n="grow"/>
</s>
</f>
<f p="./src/scipoverlay.h">
<s t="method" n="empty" id="./src/scipoverlay.h::ScipOverlay::empty" k="0.0126">
</s>
</f>
</r>
`````

Artifact written:

`````
-rw-r--r--@ 1 qgames  staff  3726049 Jul 31 20:15 /var/folders/_7/1b0h5mxs3vl2jgb9jk3qzw7r0000gn/T/ripwire_showcase_fxbqqxez/aux/warm2.ripwirecache
`````

## `./build/ripwire . --max-file-size=8K --top-k=3`

*Skip files above a size bound before parsing (note the corpus shrink in the header).*

`````
<!-- ripwire v1 t=fn|method|cls|struct|iface|var|sec p=path layer=arch-layer(opt) n=name id=canonical(path::scope::name,when-scoped) k=rank c=call amb=ambiguous-calls(read-source) overloads=N-same-name-defs-merged-into-this-row(absent-if-1;shown=counts-them-individually,so-rows+sum(overloads-1)=shown) prov=scip(precise;else name-based) hdr:unresolved=call-name-defined-only-in-a-lang-incompatible-file (edges heuristic) r:est_tokens=hdr-copy(none-if-stable) -->
<!-- files=504 symbols=1923 edges=721 shown=3 est_tokens=360 ambiguous=60 unresolved=56 precise=3 skipped_oversize=335 order=important-first -->
<r est_tokens="360">
<f p="./src/svector.h">
<s t="method" n="size" id="./src/svector.h::svector::size" k="0.0136">
</s>
<s t="method" n="buf" id="./src/svector.h::svector::buf" k="0.0039">
</s>
</f>
<f p="./test/scipfix/make_index.py" layer="test">
<s t="fn" n="varint" k="0.0044">
</s>
</f>
</r>
`````

## `./build/ripwire . --scip=does_not_exist.scip --callers=rankGraphTeleport`

*SCIP overlay with a missing index: degrades to name-based, never fails.*

`````
<!-- ripwire callers/callees: the 1-hop call hierarchy read straight off the call graph. The callers form lists the symbols that CALL of=; the callees form lists the symbols of= itself calls. of= is the selector you passed, defs= how many DEFINITIONS that name resolved to (the rows UNION every def's neighbours), and count= the number of DISTINCT neighbour symbols (a floor, per counts_floor=), which the rows window with limit= and offset=. counts_floor="1" means every count on this element is a FLOOR, never a total. Call edges are extracted from source text by NAME, so a call that reaches its target through dynamic dispatch (a virtual, interface or duck-typed receiver), a callback or function pointer, a macro-generated call site, or a declaration that parses without a call expression (C++ most-vexing-parse) contributes no edge and is missing here. Read a zero as "none found", never as "none exists". COUNTING UNIT, and it differs by verb — which is why two of them report different numbers for one symbol. The callers, callees, edit-check, graph-query and pr-context counts are DISTINCT SYMBOLS: repeated calls from one caller, and calls to two overloads of one name, collapse into ONE row, their multiplicity surviving only in the call graph's edge weight. The reach counts (impact's reaches=, pr-context's dependents=) are the size of a transitive reach SET, each symbol counted once — not a count of calls or edges. The uses verb counts call SITES, one row per occurrence, so a larger count= there for the same symbol is these units agreeing, not disagreeing. The map header's edges= is a unit again different — distinct (caller,callee) PAIRS — and that document carries neither this marker nor this clause, so its numbers answer a different question. -->
<callers of="rankGraphTeleport" defs="1" count="6" counts_floor="1">
<s t="fn" n="runEval" p="./src/eval.h:133"/>
<s t="fn" n="rankGraph" p="./src/graph.h:1304"/>
<s t="fn" n="anchoredLexicalRank" p="./src/graph.h:1553"/>
<s t="fn" n="churnRankedGraph" p="./src/main.cpp:7246"/>
<s t="fn" n="runDefaultMap" p="./src/main.cpp:7276"/>
<s t="fn" n="getIndex" p="./src/mcpindex.h:734"/>
</callers>
`````

stderr:

`````
[math degraded] --scip: index missing or unreadable — proceeding name-based  (scip.h:389, ScipOverlay rw::loadScipOverlay(std::string_view, const IngestResult &) — logged once per site)
ripwire --scip: cannot read index 'does_not_exist.scip' — proceeding name-based
`````

## `./build/ripwire src test --top-k=5`

*Multi-root workspace: ONE merged graph over two roots, paths labeled <root>/<rel>.*

`````
<!-- ripwire v1 t=fn|method|cls|struct|iface|var|sec p=path layer=arch-layer(opt) n=name id=canonical(path::scope::name,when-scoped) k=rank c=call amb=ambiguous-calls(read-source) overloads=N-same-name-defs-merged-into-this-row(absent-if-1;shown=counts-them-individually,so-rows+sum(overloads-1)=shown) prov=scip(precise;else name-based) hdr:unresolved=call-name-defined-only-in-a-lang-incompatible-file (edges heuristic) r:est_tokens=hdr-copy(none-if-stable) -->
<!-- files=729 symbols=5257 edges=8221 shown=5 est_tokens=445 ambiguous=2619 unresolved=32 precise=3 roots=2 order=important-first -->
<r est_tokens="445">
<root label="src" p="src"/>
<root label="test" p="test"/>
<f p="src/./svector.h">
<s t="method" n="size" id="src/./svector.h::svector::size" k="0.0586">
</s>
<s t="method" n="push_back" id="src/./svector.h::svector::push_back" amb="2" k="0.0146">
<c n="buf"/>
<c n="buf"/>
<c n="grow"/>
</s>
<s t="method" n="buf" id="src/./svector.h::svector::buf" overloads="2" k="0.0139">
</s>
</f>
<f p="src/./scipoverlay.h">
<s t="method" n="empty" id="src/./scipoverlay.h::ScipOverlay::empty" k="0.0146">
</s>
</f>
</r>
`````

## `./build/ripwire . --eval`

*Self-eval: co-change recall vs BM25.*

`````
ripwire --eval  (co-change recovery, averaged over 11 historical commits)
  ranker     recall@5  recall@10  recall@20
  ripwire        0.0%       0.0%       0.0%
  BM25           9.1%       9.1%       9.1%
  BM25sub        9.1%       9.1%       9.1%
  BM25body      13.6%      27.3%      40.9%
  fused          0.0%       0.0%       0.0%
  anchored      13.6%      27.3%      40.9%
  same-dir      34.8%      34.8%      34.8%
  random         0.6%       1.2%       2.4%   <- floor (random ranking over F=836 files)
  note: `ripwire` here is the DEFAULT MAP's structural-only PageRank (importance, not
        relatedness) — it is NOT what a --for/--query retrieval call ranks with. BM25 /
        BM25sub / BM25body are QUERY-TIME lexical rankers (whole-name / subtoken /
        subtoken+body); fused = RRF(ripwire, BM25sub); anchored = BM25body + anchored PPR
        expansion (--for --anchor, EXPERIMENTAL). The SHIPPED default for --for/--query is
        the subtoken+body lexical family (routed to name-exact only for an identifier-shaped
        query — lexical.h chooseForRanker), so a gap between the ripwire and BM25* rows here
        is structural-importance-vs-lexical-relatedness on a co-change task, not the shipped
        retrieval path losing to an alternative it was never running.
`````

## `./build/ripwire . --eval-retrieval`

*Known-item retrieval eval: MRR + recall@k per ranker per query mode.*

**wall time: 2.73s**

`````
ripwire --eval-retrieval  (known-item, 150 doc-commented symbols; gold is in-corpus by construction)
  ranker    query-mode     MRR  recall@1  recall@5 recall@10
  subtoken  name         0.685     55.3%     85.3%     92.7%
  subtoken  doc-phrase   0.817     78.0%     85.3%     86.7%
  name-exact name         0.894     84.0%     96.7%     99.3%
  name-exact doc-phrase   0.001      0.0%      0.0%      0.0%
  anchored  name         0.699     58.0%     84.7%     89.3%
  anchored  doc-phrase   0.813     78.7%     84.0%     85.3%
  routed    name         0.894     84.0%     96.7%     99.3%
  routed    doc-phrase   0.815     78.0%     85.3%     86.7%
  note: routing chose name-exact on 150/150 NAME queries (a NAME query is always identifier-shaped);
        the confidence gate routes doc-phrase queries to name-exact ONLY when EVERY content word names a symbol
        (or an explicit camel/snake token appears), so conceptual prose falls back to subtoken+body — routed tracks
        the better ranker on BOTH modes (routed==name-exact on name, ~=subtoken+body on doc-phrase).
`````

## `./build/ripwire . --eval-stray=/var/folders/_7/1b0h5mxs3vl2jgb9jk3qzw7r0000gn/T/ripwire_showcase_fxbqqxez/aux/stray_labels2.tsv`

*Labelled verdict-accuracy eval for --stray-content (3 hand-labelled refs).*

**exit code: 3**

Input file:

`````
# ref<TAB>verdict labels for --eval-stray
r25-notes	merged
r25-abi	merged
r25-docdrift	unmerged
`````

`````
<!-- ripwire stray-content eval: labelled verdict accuracy. Each row is one branch whose true state was established by hand; want= is the label, got= is what the classifier said. A branch absent from the report scores as merged (merged refs are omitted by design). Use this to MEASURE a threshold change instead of eyeballing it. -->
<stray-eval cases="3" correct="2" accuracy="66.7">
<case ref="r25-notes" want="merged" got="merged" hit="1" reported="0"/>
<case ref="r25-abi" want="merged" got="merged" hit="1" reported="0"/>
<case ref="r25-docdrift" want="unmerged" got="merged" hit="0" reported="0"/>
</stray-eval>
`````

## `./build/ripwire skills --eval-skills=/var/folders/_7/1b0h5mxs3vl2jgb9jk3qzw7r0000gn/T/ripwire_showcase_fxbqqxez/aux/skills_labels2.tsv`

*Labelled skill-ROUTING eval over the repo's own skills/ directory (4 hand-labelled prompts).*

Input file:

`````
orient in an unfamiliar codebase fast	ripwire-orient	judged
who calls this function and what is the blast radius	ripwire-navigate	judged
plan parallel worktrees so the lanes do not collide	ripwire-change-check	judged
what is the weather in Paris	none	neg
`````

`````
ripwire --eval-skills  (skill routing over K=16 candidate skills [ripwire-router excluded]; 3 positive + 1 negative prompts; corpus '/var/folders/_7/1b0h5mxs3vl2jgb9jk3qzw7r0000gn/T/ripwire_showcase_fxbqqxez/aux/skills_labels2.tsv'; split test=4 dev=0)
  arm           hit@1   hit@2     mrr   sep-auc   fire/abstain@ORACLE-th (upper bound)
  overlap       66.7%  100.0%   0.833     0.500    50.0% (th=-1.000)
  name          33.3%   66.7%   0.533     0.667    50.0% (th=0.000)
  bm25-desc     66.7%  100.0%   0.833     1.000    75.0% (th=2.036)
  bm25-full     33.3%  100.0%   0.667     1.000    50.0% (th=0.413)
  for-routed    33.3%  100.0%   0.667     0.667    50.0% (th=2.978)
  random         6.2%   12.5%   0.211     0.500   <- floor (uniform-random ranking; auc 0.5 by definition)
  provenance hit@1 (bm25-desc): router 0/0, desc 0/0, judged 2/3 (desc rows quote the descriptions - expect them easiest; judged is the honest number)
  judged-only hit@1 per arm: overlap 2/3, name 1/3, bm25-desc 2/3, bm25-full 1/3, for-routed 1/3
  router-magnet: with ripwire-router ADMITTED as a candidate it takes top-1 on 0/3 positive prompts (bm25-desc arm) - why it is excluded above
  per-skill (bm25-desc): name / permitted-rows / won / pos-fires / false-fires / neg-fires
    ripwire-before-you-build     0     0     0     0     0
    ripwire-change-check         1     1     1     0     0
    ripwire-efficient            0     0     0     0     0
    ripwire-find-bug             0     0     0     0     0
    ripwire-fresh-eyes           0     0     1     1     0
    ripwire-graph-query          0     0     0     0     0
    ripwire-handoff              0     0     0     0     0
    ripwire-layers               0     0     0     0     1
    ripwire-mcp                  0     0     0     0     0
    ripwire-navigate             1     1     1     0     0
    ripwire-orient               1     0     0     0     0
    ripwire-perf-target          0     0     0     0     0
    ripwire-quality-bar          0     0     0     0     0
    ripwire-reuse-first          0     0     0     0     0
    ripwire-security-scan        0     0     0     0     0
    ripwire-write-tests          0     0     0     0     0
  misses (bm25-desc):
    line 1   want=ripwire-orient got=ripwire-fresh-eyes "orient in an unfamiliar codebase fast"
  split=test (N=4: 3 positive + 1 negative):
    split=test  overlap       66.7%  100.0%   0.833     0.500
    split=test  name          33.3%   66.7%   0.533     0.667
    split=test  bm25-desc     66.7%  100.0%   0.833     1.000
    split=test  bm25-full     33.3%  100.0%   0.667     1.000
    split=test  for-routed    33.3%  100.0%   0.667     0.667
  split=dev (N=0: 0 positive + 0 negative):
    split=dev (no positive rows in this split yet)
`````

## `./build/ripwire wrap claude`

*Print the recipe to wire ripwire into Claude Code as an MCP server.*

`````
# ripwire -> Claude Code (MCP — deterministic, no LLM, no embeddings)
claude mcp add ripwire -- ripwire --mcp
# verbs the agent can then call mid-task (30 total):
#   read:             analyze, find_symbol, find_referencing_symbols, grep, cochange, memory_recall, situational_awareness, mentions, for, lego, owners, fetch_body, batch, flags, doc_drift
#   flagship reflex:  exemplar, quality_delta, quality_baseline, impact, uses, path_between, connect, explore, from_trace, edit_check, whereis, stray_content
#   edit:             replace_symbol_body, insert_before_symbol, insert_after_symbol
# (no-MCP one-shot orientation: ripwire . --for="<task>" --max-tokens=2000)
bash skills/install.sh   # deploy to ~/.claude/skills (drift-gated)
`````

## `./build/ripwire --version`

*Version + short build info.*

`````
ripwire 0.1.0 (dev, AppleClang 21.0.0.21000101)
`````


---

# the dirty-tree verbs (throwaway clone, NOT the read-only repo)

Everything below runs with `cwd` = the throwaway clone at `/var/folders/_7/1b0h5mxs3vl2jgb9jk3qzw7r0000gn/T/ripwire_showcase_fxbqqxez/dirty` (`git clone --local` of this repo, then one deliberate regression in `src/sortutil.h`). The read-only repo is never touched. The binary is the same `build/ripwire`, addressed absolutely.

## `./build/ripwire . --situ`

*Situational report for a real diff: blast radius + tests + co-change + forgotten co-change partners.*

`````
ripwire situational-awareness — 1 changed file(s), 12 symbols in them
  [1] blast radius: 80 symbols across 20 files transitively depend on these changes (showing 8 of 20 files; --pr-context's own per-file blast-radius list is also capped, at 20)
        ./src/mcpverbs.h  (26 dependent symbols)
        ./src/main.cpp  (13 dependent symbols)
        ./src/serialize.h  (8 dependent symbols)
        ./bench/bench_sort_large.cpp  (5 dependent symbols)
        ./bench/bench_radix_ab.cpp  (3 dependent symbols)
        ./src/lanes.h  (3 dependent symbols)
        ./src/partition.h  (3 dependent symbols)
        ./src/editcheck.h  (2 dependent symbols)
  [2] tests to run (2):
        ./test/verify_radix.cpp
        ./test/adaptivecutshapefix/adaptive_cut_shape_test.cpp   (run: bash test/adaptivecutshapecheck.sh)
        (331 test/*.sh gates are NOT modelled: script-to-binary edges are not call edges, so they never appear here — a path count, not every one invokes the binary)
  [3] co-change — usually edited with these but NOT in your diff (0):
        (none, or no git history)
`````

## `./build/ripwire . --test-gate`

*The pre-PR gate with real obligations — exit 4 when tests-to-run or untested blast radius is non-empty.*

**exit code: 4**

`````
<!-- ripwire test-gate (TDAD-parity, arXiv 2603.17973): the tests to run for this change + the UNTESTED blast radius. A queryable call-graph+test map cut agent-caused regressions -70% (6.08%->1.82%); this gate names the obligations, the agent runs the tests then relies on green. exit 4 if tests OR untested is non-empty. TWO INDEPENDENT LISTINGS, each with its own row count: shown_tests= counts the <t> tests-to-run rows and shown_untested= counts the <u> blast-radius rows (a single shown= could only ever have described one of them). The <t> rows are the COMPLETE obligation and are never windowed, so they REPEAT VERBATIM on every page — a walker that concatenates pages must take them from one page only; offset=/limit= window the <u> rows alone. The <u> listing shows 25 rows by default: raise the default cap with limit=N (offset=M pages). script_gates_unmodelled= counts test/*.sh runners in the corpus (a path count; not every one invokes the binary) - script-to-binary edges are NOT modelled, so those gates are invisible to this walk and never counted in tests=. UNIT: untested= here counts impacted SYMBOLS. The seams verb spells untested= over cross-directory call EDGES and the flip verb over the defs a gate lights, so the three numbers count three different things and must never be compared or summed across verbs. -->
<test-gate changed="1" impacted="80" tests="2" untested="76" shown_tests="2" tests_capped="0" shown_untested="25" untested_capped="1" script_gates_unmodelled="331" at="1dc07e27a+dirty">
<t p="./test/adaptivecutshapefix/adaptive_cut_shape_test.cpp" run="bash test/adaptivecutshapecheck.sh"/>
<t p="./test/verify_radix.cpp"/>
<u sym="buildGraph" p="./src/graph.h" ccx="712"/>
<u sym="dispatchMcpLine" p="./src/mcp.h" ccx="428"/>
<u sym="main" p="./src/main.cpp" ccx="376"/>
<u sym="runQualityDelta" p="./src/main.cpp" ccx="198"/>
<u sym="packSignatures" p="./src/serialize.h" ccx="197"/>
<u sym="runDefaultMap" p="./src/main.cpp" ccx="170"/>
<u sym="serialize" p="./src/serialize.h" ccx="165"/>
<u sym="runForLens" p="./src/main.cpp" ccx="163"/>
<u sym="packTaskBundleText" p="./src/packtask.h" ccx="133"/>
<u sym="runBatchSub" p="./src/mcpverbs.h" ccx="98"/>
<u sym="runMcpHttp" p="./src/mcpserver.h" ccx="86"/>
<u sym="packLego" p="./src/serialize.h" ccx="84"/>
<u sym="serializeJson" p="./src/serialize.h" ccx="82"/>
<u sym="fetchBody" p="./src/mcpverbs.h" ccx="77"/>
<u sym="runEval" p="./src/eval.h" ccx="66"/>
<u sym="forTaskText" p="./src/mcpverbs.h" ccx="42"/>
<u sym="qualityDeltaJson" p="./src/mcpverbs.h" ccx="41"/>
<u sym="getIndex" p="./src/mcpindex.h" ccx="38"/>
<u sym="runTargetedViews" p="./src/main.cpp" ccx="32"/>
<u sym="packTaskText" p="./src/mcpverbs.h" ccx="29"/>
<u sym="packTaskPartitionText" p="./src/partition.h" ccx="27"/>
<u sym="packSignaturesJson" p="./src/serialize.h" ccx="26"/>
<u sym="situationDiffJson" p="./src/mcpverbs.h" ccx="24"/>
<u sym="packGraphBlock" p="./src/serialize.h" ccx="24"/>
<u sym="usesText" p="./src/mcpverbs.h" ccx="23"/>
</test-gate>
`````

## `./build/ripwire . --quality-delta`

*CHANGED: every row now carries p="file:line", the gating rows are marked gating="1", and exit 2 prints a naming line on stderr.*

**exit code: 2** — **wall time: 1.77s**

`````
<!-- ripwire quality-delta: only what a change made WORSE against the floor named by baseline= below. FOUR floors, and they are not interchangeable: sidecar = the pinned .ripwire_quality_baseline snapshot, honored only because it was pinned at the CURRENT git HEAD; git-HEAD = no sidecar existed, so the working tree was auto-compared against the HEAD tree; git-HEAD (stale sidecar removed) = a sidecar existed, was pinned at a DIFFERENT sha, and this run DELETED it from your working tree before falling back to HEAD (re-pin with quality-baseline); git-HEAD (stale sidecar ignored) = same staleness verdict, but the file was left on disk (the read-only MCP arm, or an unlink that failed). Only the first is a floor YOU chose; the other three compare against HEAD, so anything already committed cannot appear. at= is the git commit (plus a dirty marker when the working tree differs) this list was computed at. Findings: complexity over the ccx bar, verbosity (LOC)/nesting/params regressions, new duplication, newly-dead, new public api-surface (contract drift), error-masking, short-horizon churn, new clone of a reused helper. THREE independent axes, applied in this order: (1) acked findings are suppressed entirely (acked= counts them, honestly); (2) ORIGIN — a finding on a symbol that EXISTED at the baseline is preexisting-worse (no origin= attribute), one that exists only because the code is NEW carries origin="new-symbol"; (3) MATERIALITY — a small numeric delta is sev="minor". EXIT 2 fires only on preexisting-worse AND major, i.e. gating="N" above; new-symbol rows never gate. Clone kinds classify by their member set (a group is new-symbol only if EVERY member is new); short-horizon-churn is preexisting by construction. exit 0 is NOT a verdict on the new-symbol rows — nothing that existed got worse, but the new debt is yours: read them. LIMIT: origin is canonId identity (path::scope::name), so a RENAMED or MOVED symbol reads as new — a regression carried in with a move classifies new-symbol and will not gate. Descriptive: weigh + fix the real ones, do not game the number (a wrong abstraction beats a low score). Each row carries kind= (which of the measured axes regressed) and sym= (the canonical id it regressed on), plus p="path:line" (root-relative; the first-sorting member for the clone kinds; omitted, never faked, when no locator resolves), and every row the header's gating= counter counts also carries a gating attribute set to 1 — those are the rows the exit code fires on, and they are now marked positively rather than by the ABSENCE of sev/origin. (This sentence deliberately spells no attribute=value literal: the header counters are parsed by grep in several gates, and a quoted numeric example here would be matched first.) -->
<quality-delta baseline="git-HEAD" regressions="10" minor="2" acked="0" preexisting-worse="7" new-symbol="3" gating="7" at="1dc07e27a+dirty">
<r kind="api-surface" sym="src/sortutil.h::rw::sortutil::nonNegativeFloatAscKeyCopy" sev="minor" surface="new-symbol" origin="new-symbol" p="src/sortutil.h:82"/>
<r kind="api-surface" sym="src/sortutil.h::rw::sortutil::nonNegativeFloatDescKey" was="1" now="2" surface="contract-change" p="src/sortutil.h:72" gating="1"/>
<r kind="api-surface" sym="src/sortutil.h::rw::sortutil::sortScoredIdsWithOptions" sev="minor" surface="new-symbol" origin="new-symbol" p="src/sortutil.h:92"/>
<r kind="complexity" sym="src/sortutil.h::rw::sortutil::lessByScoreDescId" was="1" now="73" p="src/sortutil.h:14" gating="1"/>
<r kind="duplication" members="src/sortutil.h::rw::sortutil::nonNegativeFloatAscKeyCopy | src/sortutil.h::rw::sortutil::nonNegativeFloatDescKey" tokens="59" p="src/sortutil.h:82" gating="1"/>
<r kind="nesting" sym="src/sortutil.h::rw::sortutil::lessByScoreDescId" was="1" now="9" p="src/sortutil.h:14" gating="1"/>
<r kind="new-clone-of-reused-helper" sym="src/sortutil.h::rw::sortutil::nonNegativeFloatAscKeyCopy | src/sortutil.h::rw::sortutil::nonNegativeFloatDescKey" was="0" now="4" p="src/sortutil.h:82" gating="1"/>
<r kind="params" sym="src/sortutil.h::rw::sortutil::sortScoredIdsWithOptions" was="0" now="8" origin="new-symbol" p="src/sortutil.h:92"/>
<r kind="short-horizon-churn" sym="src/sortutil.h::rw::sortutil::lessByScoreDescId" was="0" now="2" churn="self" p="src/sortutil.h:14" gating="1"/>
<r kind="short-horizon-churn" sym="src/sortutil.h::rw::sortutil::nonNegativeFloatDescKey" was="0" now="2" churn="self" p="src/sortutil.h:72" gating="1"/>
</quality-delta>
`````

stderr:

`````
ripwire: no ./.ripwire_quality_baseline — auto-comparing the working tree vs git HEAD (commit the baseline with --quality-baseline to pin it)
ripwire: --quality-delta gating: 7 preexisting-worse major finding(s); first: api-surface ./src/sortutil.h::rw::sortutil::nonNegativeFloatDescKey at src/sortutil.h:72 (was=1 now=2)
`````

## `./build/ripwire . --quality-delta --json`

*The same findings as JSON (one of the CI/scripting verbs --json supports).*

**exit code: 2**

`````
{"baseline":"git-HEAD","regressions":10,"minor":2,"acked":0,"preexisting-worse":7,"new-symbol":3,"gating":7,"at":"1dc07e27a+dirty","r":[{"kind":"api-surface","sym":"src/sortutil.h::rw::sortutil::nonNegativeFloatAscKeyCopy","p":"src/sortutil.h:82","sev":"minor","surface":"new-symbol","origin":"new-sy … [line truncated: 7 more bytes on this line]
{"kind":"api-surface","sym":"src/sortutil.h::rw::sortutil::nonNegativeFloatDescKey","was":1,"now":2,"p":"src/sortutil.h:72","gating":true,"surface":"contract-change"},
{"kind":"api-surface","sym":"src/sortutil.h::rw::sortutil::sortScoredIdsWithOptions","p":"src/sortutil.h:92","sev":"minor","surface":"new-symbol","origin":"new-symbol"},
{"kind":"complexity","sym":"src/sortutil.h::rw::sortutil::lessByScoreDescId","was":1,"now":73,"p":"src/sortutil.h:14","gating":true},
{"kind":"duplication","members":"src/sortutil.h::rw::sortutil::nonNegativeFloatAscKeyCopy | src/sortutil.h::rw::sortutil::nonNegativeFloatDescKey","tokens":59,"p":"src/sortutil.h:82","gating":true},
{"kind":"nesting","sym":"src/sortutil.h::rw::sortutil::lessByScoreDescId","was":1,"now":9,"p":"src/sortutil.h:14","gating":true},
{"kind":"new-clone-of-reused-helper","sym":"src/sortutil.h::rw::sortutil::nonNegativeFloatAscKeyCopy | src/sortutil.h::rw::sortutil::nonNegativeFloatDescKey","was":0,"now":4,"p":"src/sortutil.h:82","gating":true},
{"kind":"params","sym":"src/sortutil.h::rw::sortutil::sortScoredIdsWithOptions","was":0,"now":8,"p":"src/sortutil.h:92","origin":"new-symbol"},
{"kind":"short-horizon-churn","sym":"src/sortutil.h::rw::sortutil::lessByScoreDescId","was":0,"now":2,"p":"src/sortutil.h:14","gating":true,"churn":"self"},
{"kind":"short-horizon-churn","sym":"src/sortutil.h::rw::sortutil::nonNegativeFloatDescKey","was":0,"now":2,"p":"src/sortutil.h:72","gating":true,"churn":"self"}]}
`````

stderr:

`````
ripwire: no ./.ripwire_quality_baseline — auto-comparing the working tree vs git HEAD (commit the baseline with --quality-baseline to pin it)
ripwire: --quality-delta gating: 7 preexisting-worse major finding(s); first: api-surface ./src/sortutil.h::rw::sortutil::nonNegativeFloatDescKey at src/sortutil.h:72 (was=1 now=2)
`````

## `./build/ripwire . --quality-delta --quality-ack --ack-only=zzznope`

*NEW FLAG: --ack-only matching nothing REFUSES rather than falling back to acking everything.*

**exit code: 1**

`````
(empty)
`````

stderr:

`````
ripwire: no ./.ripwire_quality_baseline — auto-comparing the working tree vs git HEAD (commit the baseline with --quality-baseline to pin it)
ripwire: --ack-only=zzznope matched none of the 10 finding(s) — nothing written
`````

## `./build/ripwire . --quality-delta --quality-ack --ack-only=api-surface`

*NEW FLAG: ack only the api-surface findings — a per-finding ratchet instead of a rubber stamp.*

`````
(empty)
`````

stderr:

`````
ripwire: no ./.ripwire_quality_baseline — auto-comparing the working tree vs git HEAD (commit the baseline with --quality-baseline to pin it)
ripwire: acknowledged 3 of 10 finding(s) (7 left UNACKED by --ack-only, 0 already acked) → ./.ripwire_quality_acks
`````

## `./build/ripwire . --quality-delta`

*Re-run after the partial ack: acked=3, the rest still gate.*

**exit code: 2**

`````
<!-- ripwire quality-delta: only what a change made WORSE against the floor named by baseline= below. FOUR floors, and they are not interchangeable: sidecar = the pinned .ripwire_quality_baseline snapshot, honored only because it was pinned at the CURRENT git HEAD; git-HEAD = no sidecar existed, so the working tree was auto-compared against the HEAD tree; git-HEAD (stale sidecar removed) = a sidecar existed, was pinned at a DIFFERENT sha, and this run DELETED it from your working tree before falling back to HEAD (re-pin with quality-baseline); git-HEAD (stale sidecar ignored) = same staleness verdict, but the file was left on disk (the read-only MCP arm, or an unlink that failed). Only the first is a floor YOU chose; the other three compare against HEAD, so anything already committed cannot appear. at= is the git commit (plus a dirty marker when the working tree differs) this list was computed at. Findings: complexity over the ccx bar, verbosity (LOC)/nesting/params regressions, new duplication, newly-dead, new public api-surface (contract drift), error-masking, short-horizon churn, new clone of a reused helper. THREE independent axes, applied in this order: (1) acked findings are suppressed entirely (acked= counts them, honestly); (2) ORIGIN — a finding on a symbol that EXISTED at the baseline is preexisting-worse (no origin= attribute), one that exists only because the code is NEW carries origin="new-symbol"; (3) MATERIALITY — a small numeric delta is sev="minor". EXIT 2 fires only on preexisting-worse AND major, i.e. gating="N" above; new-symbol rows never gate. Clone kinds classify by their member set (a group is new-symbol only if EVERY member is new); short-horizon-churn is preexisting by construction. exit 0 is NOT a verdict on the new-symbol rows — nothing that existed got worse, but the new debt is yours: read them. LIMIT: origin is canonId identity (path::scope::name), so a RENAMED or MOVED symbol reads as new — a regression carried in with a move classifies new-symbol and will not gate. Descriptive: weigh + fix the real ones, do not game the number (a wrong abstraction beats a low score). Each row carries kind= (which of the measured axes regressed) and sym= (the canonical id it regressed on), plus p="path:line" (root-relative; the first-sorting member for the clone kinds; omitted, never faked, when no locator resolves), and every row the header's gating= counter counts also carries a gating attribute set to 1 — those are the rows the exit code fires on, and they are now marked positively rather than by the ABSENCE of sev/origin. (This sentence deliberately spells no attribute=value literal: the header counters are parsed by grep in several gates, and a quoted numeric example here would be matched first.) -->
<quality-delta baseline="git-HEAD" regressions="7" minor="0" acked="3" preexisting-worse="6" new-symbol="1" gating="6" at="1dc07e27a+dirty">
<r kind="complexity" sym="src/sortutil.h::rw::sortutil::lessByScoreDescId" was="1" now="73" p="src/sortutil.h:14" gating="1"/>
<r kind="duplication" members="src/sortutil.h::rw::sortutil::nonNegativeFloatAscKeyCopy | src/sortutil.h::rw::sortutil::nonNegativeFloatDescKey" tokens="59" p="src/sortutil.h:82" gating="1"/>
<r kind="nesting" sym="src/sortutil.h::rw::sortutil::lessByScoreDescId" was="1" now="9" p="src/sortutil.h:14" gating="1"/>
<r kind="new-clone-of-reused-helper" sym="src/sortutil.h::rw::sortutil::nonNegativeFloatAscKeyCopy | src/sortutil.h::rw::sortutil::nonNegativeFloatDescKey" was="0" now="4" p="src/sortutil.h:82" gating="1"/>
<r kind="params" sym="src/sortutil.h::rw::sortutil::sortScoredIdsWithOptions" was="0" now="8" origin="new-symbol" p="src/sortutil.h:92"/>
<r kind="short-horizon-churn" sym="src/sortutil.h::rw::sortutil::lessByScoreDescId" was="0" now="2" churn="self" p="src/sortutil.h:14" gating="1"/>
<r kind="short-horizon-churn" sym="src/sortutil.h::rw::sortutil::nonNegativeFloatDescKey" was="0" now="2" churn="self" p="src/sortutil.h:72" gating="1"/>
</quality-delta>
`````

stderr:

`````
ripwire: no ./.ripwire_quality_baseline — auto-comparing the working tree vs git HEAD (commit the baseline with --quality-baseline to pin it)
ripwire: --quality-delta gating: 6 preexisting-worse major finding(s); first: complexity ./src/sortutil.h::rw::sortutil::lessByScoreDescId at src/sortutil.h:14 (was=1 now=73)
`````

## `./build/ripwire . --ack-only=gating`

*--ack-only WITHOUT --quality-ack REFUSES loudly (exit 1, the pairing named) — it used to be silently ignored.*

**exit code: 1**

`````
(empty)
`````

stderr:

`````
ripwire: --ack-only=SUBSTR narrows --quality-ack — pass both (e.g. ripwire <dir> --quality-delta --ack-only=contract-change --quality-ack="reason")
`````

## `./build/ripwire . --edit-check=nonNegativeFloatDescKey`

*A real contract-change: was=1 now=2 params, with the call sites that are now provably incompatible.*

`````
<!-- ripwire edit-check: SYM's contract (param count + publicness) NOW vs git HEAD — unchanged/new-symbol/contract-change — plus its 1-hop callers. A caller is flagged incompatible="1" when its argument count was reliably counted and NO definition in the folded set could accept it: every one has a FIXED arity that disagrees. A variadic, defaulted or implicit-receiver definition (a Python/Ruby method, whose params counts the self/cls the call site never writes) has no fixed arity and is never flagged. That makes the ARITY half one-sided — a call the compared definitions could accept is never flagged — but it is NOT a proof that the call site binds to THIS definition. Call edges are matched by NAME, so a receiver-qualified call to a same-named callee this tool does not index (a standard-library or third-party method) is measured against the one definition it does index; a clean, compiling tree can therefore carry a nonzero incompatible= with nothing edited at all, and on a widely-shared name it can be most of that name's callers. Read incompatible= as a fact about the tree as it stands — call sites worth OPENING, not a verdict — and status= as a fact about the edit. Warm path hits the qheadsnap/qsnap cache — never a full quality-delta style recompute. defs= is how many DEFINITIONS at this site (same file, same scope, same name — the overload set) are folded into this one contract; a selector matching more than one SITE is refused instead, so defs= only ever counts overloads. params_was and params_now are the MAX over that set on each side (the same MAX the baseline snapshot stores), and publicness is the OR. That MAX has TWO consequences, in opposite directions. It can read like a break and not be one: adding a WIDER overload beside an unchanged one raises params_now with no existing definition altered, so it reports status="contract-change" with incompatible="0" and a def row still carrying the old parameter count — no seen caller breaks. And it can read like safety and not be: REMOVING an overload whose parameter count is BELOW the MAX moves neither number, because the MAX survives on both sides, while the call site that used the removed definition no longer binds. defs_was=/defs_now= is what closes that: the count of definitions sharing this symbol's CANONICAL ID on each side. That population is the one the baseline snapshot buckets by, so the two numbers answer the same question and are equal on an unedited tree — it is deliberately NOT the root's defs=, which is the same bucket narrowed to this FILE (a contract is per definition site), so where a scope-less name also exists in another file defs= is the smaller of the two. status is therefore the join of THREE was-vs-now facts — the params MAX, publicness, and the definition COUNT — and change= names which of them carried it. change= adds broken-callers when a seen caller is also flagged, but never on its own — for the reason stated at the top: incompatible= describes the TREE and status= describes the EDIT, so a headline must not turn on it. RESIDUAL: an overload whose arity changes BELOW the MAX while the COUNT stays the same moves none of the three. The root's incompatible= is the COUNT of flagged callers (a c row's incompatible="1" is the per-caller flag). p= is the definition the selector resolved to; when defs is above 1 EVERY folded definition is listed as its own def row (p=, t=, params=), which is what tells a widened single definition apart from an added overload. At defs="1" no def row is emitted: the root's own p=/t= is that definition, and params_now is its parameter count. counts_floor="1" means every count on this element is a FLOOR, never a total. Call edges are extracted from source text by NAME, so a call that reaches its target through dynamic dispatch (a virtual, interface or duck-typed receiver), a callback or function pointer, a macro-generated call site, or a declaration that parses without a call expression (C++ most-vexing-parse) contributes no edge and is missing here. Read a zero as "none found", never as "none exists". COUNTING UNIT, and it differs by verb — which is why two of them report different numbers for one symbol. The callers, callees, edit-check, graph-query and pr-context counts are DISTINCT SYMBOLS: repeated calls from one caller, and calls to two overloads of one name, collapse into ONE row, their multiplicity surviving only in the call graph's edge weight. The reach counts (impact's reaches=, pr-context's dependents=) are the size of a transitive reach SET, each symbol counted once — not a count of calls or edges. The uses verb counts call SITES, one row per occurrence, so a larger count= there for the same symbol is these units agreeing, not disagreeing. The map header's edges= is a unit again different — distinct (caller,callee) PAIRS — and that document carries neither this marker nor this clause, so its numbers answer a different question. -->
<edit-check sym="nonNegativeFloatDescKey" t="fn" p="./src/sortutil.h:72" status="contract-change" defs="1" params_was="1" params_now="2" public_was="1" public_now="1" defs_was="1" defs_now="1" change="params,broken-callers" callers="4" incompatible="4" at="1dc07e27a+dirty" counts_floor="1">
<c n="benchScores" p="./bench/bench_radix_ab.cpp:133" incompatible="1"/>
<c n="benchAdaptive" p="./bench/bench_radix_ab.cpp:157" incompatible="1"/>
<c n="radixSortNonNegativeFloatsDesc" p="./src/sortutil.h:101" incompatible="1"/>
<c n="radixSortByScoreDescId" p="./src/sortutil.h:114" incompatible="1"/>
</edit-check>
`````

## `./build/ripwire . --pr-context`

*The review-evidence bundle with an actual changed file.*

`````
<!-- ripwire pr-context: no-LLM review-evidence bundle per changed file — defined symbols, their callers, blast radius (transitive dependents), affected tests, co-change partners not in the diff, and owners. base=working-tree. skipped_mode_only=diffs that changed a file's MODE and nothing else (e.g. chmod) excluded from the changed set; a pure RENAME is content-identical too but is NOT excluded — it is a changed file, listed at its new path. files= means two different things by DEPTH here and is deliberately not renamed (15 consumers read the root one): on the ROOT it is the CHANGED file count; on each <impact/> child it is the distinct files dependents= reaches (changed + non-changed), so dependents="0" implies files="0" and vice versa — never an impossible-looking dependents>0/files=0. files_other= on the same <impact/> is the non-changed subset (a changed file's dependents inside OTHER changed files have no <f> row of their own — they are already shown as their own <file> section); it is NOT the <f> row count — see the row-cap sentence below. Files are ordered by BLAST RADIUS (transitive dependents descending, path breaking ties), not alphabetically. sections= on changed-symbols counts a doc file's headings, collapsed into that number instead of one callers-zero row each; count= still counts every INDEXED symbol, sections included, so count minus sections is the number of rows that follow. Every nested list below is a TOP-N subset of its element's own total, fixed per element (impact <f> at 20, per-symbol <caller> at 12, cochange <partner> at 12, tests <test> at 40, owners <author> at 5 — the L0 defaults; max-tokens only lowers these further via the trim ladder, nothing raises them past L0): each capped element carries its own shown=/capped= pair so the cut is never silent — for the untrimmed list use impact=SYM/callers=SYM (blast radius/callers), affected=FILE or situ (tests), cochange (partners), or owners (authors) instead. direction= names which SIDE this bundle reviews (worktree-since-head, head-since-fork, head-since-ref-tip); a no-ref-work row says the base ref's tip IS the merge base, i.e. it carries no divergent work of its own. deterministic. counts_floor="1" means every count on this element is a FLOOR, never a total. Call edges are extracted from source text by NAME, so a call that reaches its target through dynamic dispatch (a virtual, interface or duck-typed receiver), a callback or function pointer, a macro-generated call site, or a declaration that parses without a call expression (C++ most-vexing-parse) contributes no edge and is missing here. Read a zero as "none found", never as "none exists". COUNTING UNIT, and it differs by verb — which is why two of them report different numbers for one symbol. The callers, callees, edit-check, graph-query and pr-context counts are DISTINCT SYMBOLS: repeated calls from one caller, and calls to two overloads of one name, collapse into ONE row, their multiplicity surviving only in the call graph's edge weight. The reach counts (impact's reaches=, pr-context's dependents=) are the size of a transitive reach SET, each symbol counted once — not a count of calls or edges. The uses verb counts call SITES, one row per occurrence, so a larger count= there for the same symbol is these units agreeing, not disagreeing. The map header's edges= is a unit again different — distinct (caller,callee) PAIRS — and that document carries neither this marker nor this clause, so its numbers answer a different question. -->
<pr-context base="working-tree" direction="worktree-since-head" files="1" skipped_mode_only="0" at="1dc07e27a+dirty" counts_floor="1">
<file p="./src/sortutil.h" symbols="12">
<impact dependents="80" files="20" files_other="20" shown="20" capped="0">
<f p="./src/mcpverbs.h" deps="26"/>
<f p="./src/main.cpp" deps="13"/>
<f p="./src/serialize.h" deps="8"/>
<f p="./bench/bench_sort_large.cpp" deps="5"/>
<f p="./bench/bench_radix_ab.cpp" deps="3"/>
<f p="./src/lanes.h" deps="3"/>
<f p="./src/partition.h" deps="3"/>
<f p="./src/editcheck.h" deps="2"/>
<f p="./src/graph.h" deps="2"/>
<f p="./src/mcp.h" deps="2"/>
<f p="./src/mcpindex.h" deps="2"/>
<f p="./src/packtask.h" deps="2"/>
<f p="./test/verify_radix.cpp" deps="2"/>
<f p="./src/eval.h" deps="1"/>
<f p="./src/lexical.h" deps="1"/>
<f p="./src/mcpedit.h" deps="1"/>
<f p="./src/mcpserver.h" deps="1"/>
<f p="./src/quality.h" deps="1"/>
<f p="./src/tracelocus.h" deps="1"/>
<f p="./test/adaptivecutshapefix/adaptive_cut_shape_test.cpp" deps="1"/>
</impact>
<tests count="2" shown="2" capped="0">
<test p="./test/adaptivecutshapefix/adaptive_cut_shape_test.cpp" run="bash test/adaptivecutshapecheck.sh"/>
<test p="./test/verify_radix.cpp"/>
</tests>
<changed-symbols count="12">
… [72 more display lines; full output is 8584 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --map-diff --top-k=5`

*The map re-ranked with a teleport toward the changed file (changed=1 here, not 0).*

`````
<!-- ripwire v1 t=fn|method|cls|struct|iface|var|sec p=path layer=arch-layer(opt) n=name id=canonical(path::scope::name,when-scoped) k=rank c=call amb=ambiguous-calls(read-source) overloads=N-same-name-defs-merged-into-this-row(absent-if-1;shown=counts-them-individually,so-rows+sum(overloads-1)=shown) prov=scip(precise;else name-based) hdr:unresolved=call-name-defined-only-in-a-lang-incompatible-file (edges heuristic) r:est_tokens=hdr-copy(none-if-stable) -->
<!-- at= is the git commit these numbers were computed at; a trailing +dirty means the working tree differed from that commit, so the numbers describe the tree, not the commit -->
<!-- files=836 symbols=6434 edges=8735 shown=5 est_tokens=681 ambiguous=2631 unresolved=652 precise=3 changed=1 skipped_oversize=3 order=important-first -->
<r at="1dc07e27a+dirty" est_tokens="681">
<f p="./src/svector.h">
<s t="method" n="size" id="./src/svector.h::svector::size" k="0.1192">
</s>
</f>
<f p="./src/sortutil.h">
<s t="fn" n="radixSortByScoreDescId" id="./src/sortutil.h::rw::sortutil::radixSortByScoreDescId" amb="6" k="0.0955">
<c n="lessByScoreDescId"/>
<c n="radixSortUint32ByKey"/>
<c n="nonNegativeFloatDescKey"/>
<c n="size"/>
<c n="begin"/>
<c n="end"/>
<c n="begin"/>
<c n="end"/>
</s>
<s t="fn" n="radixSortByFromTo" id="./src/sortutil.h::rw::sortutil::radixSortByFromTo" amb="2" k="0.0654">
<c n="sortKeySmall"/>
<c n="lessByFromTo"/>
<c n="size"/>
<c n="begin"/>
<c n="end"/>
<c n="begin"/>
<c n="end"/>
</s>
<s t="fn" n="nonNegativeFloatDescKey" id="./src/sortutil.h::rw::sortutil::nonNegativeFloatDescKey" k="0.0651">
</s>
<s t="fn" n="lessByScoreDescId" id="./src/sortutil.h::rw::sortutil::lessByScoreDescId" k="0.0562">
<c n="size"/>
</s>
</f>
</r>
`````

## `./build/ripwire . --clones`

*The duplicated helper the sandbox edit introduced shows up as a clone group.*

`````
<!-- ripwire clones: function bodies with similar normalized token streams (identifiers/literals normalized, so renamed copies match). type=2 exact/renamed (Type-1/2); type=3 gapped near-miss (an inserted/changed statement, similarity in [0.80,1.0)). Reuse don't reimplement; a fix to one likely belongs in all. groups= and type3= are the two GROUP-TYPE totals (each capped independently, so neither is the row count); total= is the true row total (groups + type3-group-count) and is ALWAYS present, paged or not; shown= is the number of group rows that follow this run. capped="1" means rows were dropped. exempt= on a group ⇒ every member is on a path the quality-delta verb's duplication kind deliberately ignores (fixture dirs / shell test-runners repeat boilerplate by convention) — a fact here, never a gate there; exempt_groups= counts them over ALL groups. raise the default cap with limit=N (offset=M pages). -->
<clones groups="40" type3="154" total="194" exempt_groups="80" shown="80" capped="1">
<group type="2" tokens="273" n="3" exempt="shell-runner">
<f n="monotonic_check" p="./test/pyimportprecisecheck.sh:88"/>
<f n="monotonic_check" p="./test/rustimportprecisecheck.sh:114"/>
<f n="monotonic_check" p="./test/tsimportprecisecheck.sh:87"/>
</group>
<group type="2" tokens="207" n="4" exempt="shell-runner">
<f n="batch_sub" p="./test/mcpclidiffcheck.sh:63"/>
<f n="batch_sub" p="./test/mcptranchecheck.sh:55"/>
<f n="batch_sub" p="./test/mcpw2fixcheck.sh:52"/>
<f n="batch_sub" p="./test/mcpw3fixcheck.sh:51"/>
</group>
<group type="2" tokens="142" n="2">
<f n="test_tier2_accept_big_quality_small_cost" p="./bench/locbench/test_compare_gate.py:130"/>
<f n="test_tier2_reject_small_quality_big_cost" p="./bench/locbench/test_compare_gate.py:143"/>
</group>
<group type="2" tokens="126" n="2">
<f n="addWholeFileFn" p="./test/cloneband_harness.cpp:61"/>
<f n="addWholeFileFn" p="./test/type3clone_harness.cpp:44"/>
</group>
<group type="2" tokens="116" n="2">
<f n="rankFiles" p="./src/eval.h:44"/>
<f n="rankCandidates" p="./src/skilleval.h:347"/>
</group>
<group type="2" tokens="114" n="2">
<f n="timer" p="./bench/representative_perfgate.sh:39"/>
<f n="run_once_ms" p="./test/mergescoutcheck.sh:268"/>
</group>
<group type="2" tokens="109" n="2">
… [306 more display lines; full output is 14733 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --stray-content=zz-orphan`

*CHANGED: a ref with NO merge base with HEAD now reports v="unknown" ok="0" in its own bucket — the absence of an answer, never a claim it is merged. (The sandbox carries a deliberately parentless branch built with `git commit-tree`; a shallow CI clone puts every ref here.)*

`````
<!-- ripwire stray-content: per ref, the lines its own divergent work AUTHORED (vs its merge-base with HEAD) that the live line does NOT have. v="superseded" means the live line removed the same base code this ref removed (redone/del) — it re-implemented the work, the case `git cherry` cannot see; v="unmerged" means the work is genuinely absent; merged refs are omitted. Read-only: git cat-file/diff/ls-tree only, one batched cat-file for the whole sweep, every blob reduced once per sha. Line-granular, not semantic: see the ripwire help text for the limits. ANCHORING is a deliberate hybrid: the SCOPE is base anchored (only lines the ref itself authored vs its merge base are ever considered, so a file the ref never opened cannot appear because the live line moved), while the ABSENCE test is HEAD anchored on purpose (does the live line have this content TODAY is the question being asked, and it is only answerable against live HEAD). v="unknown" with ok="0" means this ref could NOT be analysed at all because it has no merge base with HEAD, which on a SHALLOW clone (the checkout default in CI) is every ref: it is not a claim that the ref is merged, and the fix is to deepen the clone. The four buckets are exhaustive, so unmerged plus superseded plus merged plus unknown always equals refs. SCOPE: refs/heads only, which is every local branch (worktree branches included). Remote tracking refs are NOT scanned: they mirror local ones in the usual checkout and would double every row. The consequence on a FRESH CLONE, where the branches live under refs/remotes/origin and only the checked out one has a local head, is that there is nothing here to be stray FROM; refs= is that fact as a number. TRUNCATION: a ref row ends with a more element (more files=N) when its own file listing was capped; shown plus that number equals the ref's files= total, always. That inner listing is a SECONDARY listing (it repeats complete and identical on every page) and is capped by detail, not by limit / offset, which page the OUTER ref listing and report their own shown= / capped=. -->
<stray-content head="1dc07e27a" head_ref="main" refs="1" blobs="0" unmerged="0" superseded="0" merged="0" unknown="1">
<ref name="zz-orphan-lane" tip="17778a6c1" date="2026-07-31" base="" ok="0" v="unknown" stray="0" files="0" superseded="0">
</ref>
</stray-content>
`````

stderr:

`````
[math degraded] crossref: no merge-base for ref (shallow clone or unrelated history?) — verdict is unknown, not merged  (crossref.h:829, RefPlumbing rw::crossref::probeRefBase(const std::string &, const RefInfo &, const std::string &) — logged once per site)
`````

## `./build/ripwire . --stray-content=zz-orphan --plan`

*CHANGED: --plan surfaces those same refs as an <undetermined> row rather than silently dropping them.*

`````
<!-- ripwire landing-plan: stray-content's cheap per-blob sweep composed with merge-scout's per-arm overlap oracle — of every local branch, which still hold REAL work (v="unmerged"), which were already re-implemented on the live line (v="superseded", EXCLUDED below — landing them re-does work that is already done) or are already merged (omitted entirely, counted in merged= on the root element), and the fewest-conflicts-first order to land what remains. scouted="0" on an unmerged ref means it was NOT fed to merge-scout this run (the cost bound, not a verdict) — it is still real, unscouted work; bounded= on the root element counts them and detail lifts the bound. merge-scout is the EXPENSIVE step here (git-archive + full ingest per arm) — stray-content's own sweep is the cheap one. An undetermined row is a ref that could NOT be analysed at all (no merge base with HEAD, which on a SHALLOW clone is every ref): it is neither scouted nor excluded nor merged, because nothing was measured — treat it as unfinished business and deepen the clone, never as a clean branch. Read-only throughout: no checkout, no ref write, no working-tree mutation. The root carries BOTH head= and at= and they are the same commit: head= is the bare 9 hex chars this verb has always printed, at= is the tool wide anchor and is head= plus a "+dirty" suffix when the working tree is not clean. Prefer at= (it is the one spelling every other repo reading verb uses, and the only one that tells you whether uncommitted work was in scope); head= is kept for callers already keyed to it. -->
<landing-plan head="1dc07e27a" refs="1" unmerged="0" superseded="0" merged="0" undetermined="1" scouted="0" bounded="0" scout-ok="1" at="1dc07e27a+dirty">
<undetermined name="zz-orphan-lane" v="unknown" reason="no merge base with HEAD (shallow clone or unrelated history) — this ref could not be analysed, it is NOT known to be merged; deepen the clone and re-run"/>
</landing-plan>
`````

stderr:

`````
[math degraded] crossref: no merge-base for ref (shallow clone or unrelated history?) — verdict is unknown, not merged  (crossref.h:829, RefPlumbing rw::crossref::probeRefBase(const std::string &, const RefInfo &, const std::string &) — logged once per site)
`````
