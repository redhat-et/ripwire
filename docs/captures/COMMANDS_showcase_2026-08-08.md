# ripwire — every verb, run for real

- **Date:** 2026-08-08 (regenerated capture; supersedes any older `docs/captures/COMMANDS_showcase_*.md`)
- **Lives in `docs/captures/`** — a directory the crawl/retrieval lenses SKIP (`kCrawlSkipDirs`, src/ingest.h): a generated doc that quotes every verb's output out-scores the source for any query about the tool and was measured at 77% of `--recall` on this repo when it sat at the root. `test/argvdiffcheck.sh` harvests its `## `-heading command lines as differential vectors — keep that format.
- **Version:** `ripwire 0.2.1 (dev, AppleClang 21.0.0.21000101)`
- **Repo:** the ripwire repo @ `33f9f7b` — **CLEAN — `git status --porcelain` is empty**. The diff-aware verbs (`--situ`/`--test-gate`/`--quality-delta`/`--pr-context`/`--map-diff`/`--edit-check`) answer a question about the WORKING TREE, so that condition is part of their answer and every one of their captions below states which tree it recorded against. A clean tree is the honest default for a showcase, so they appear TWICE: once here on the clean tree (their empty/exit-0 shape) and once in the final section against a throwaway `git clone --local` sandbox carrying one deliberate regression, so their real gating shapes are visible without writing a byte into the read-only repo.
- **Corpus:** the ripwire repo itself (dogfood), via `./build/ripwire`
- **Sandbox diff** (the last section only): `.ripwire_quality_acks |  9 +++----
 src/sortutil.h        | 68 ++++++++++++++++++++++++++++++++++++++++++++++-----
 2 files changed, 66 insertions(+), 11 deletions(-)` — one preexisting function made deeply nested, one function's arity changed 1 -> 2, one copy-paste duplicate helper, one new 8-parameter public function.

**How to read the blocks:** ripwire's real XML output is minified — often ONE long line. For scanability, long minified lines are displayed re-wrapped with a line break at every tag seam (`><`). Header COMMENT lines (the legends) always appear in full — they are exempt from the per-line cut; any OTHER display line over 300 bytes is cut with a `… [line truncated: N more bytes]` marker, which can hit a long root element or row. `--plan-lanes` emits JSON and is re-wrapped at object seams the same way. Long outputs are cut to their first ~30 display lines with a `… [N more display lines; full output is M bytes]` marker giving the true size. Exit codes are recorded when non-zero; wall time when >1s.

**Not run (and why):** `ripwire <git-url>` (network clone), `--mcp` / `--listen` / `--mcp-token` / `--allow-remote-edits` (persistent servers — `wrap claude` below shows the wiring), `--note-add` / `--quality-baseline` / `--arch --baseline[-update]` / `--index-out` (state writers; the repo is read-only for this capture — `--quality-ack` IS shown, but only inside the throwaway sandbox clone), `--eval-mined` (needs a `minedpair.jsonl` artifact from `bench/mine_traces.py`; none present in the tree), `--refetch` (git-url only), `--force` (wrap-only modifier), `--scan-skills` bare form (would sweep `~/.claude/skills`; the explicit-DIR form is shown instead), `--help` (960 lines — read it from the binary).


---

# understand a codebase cold

## `./build/ripwire .`

*The default ranked symbol map — start here when landing cold in a repo.*

`````
<!-- ripwire v1 t=fn|method|cls|struct|iface|var|sec p=path layer=arch-layer(opt) n=name id=canonical(path::scope::name,when-scoped) k=rank c=call amb=ambiguous-calls(read-source) overloads=N-same-name-defs-merged-into-this-row(absent-if-1;shown=counts-them-individually,so-rows+sum(overloads-1)=shown) prov=scip(precise;else name-based) hdr:unresolved=call-name-defined-only-in-a-lang-incompatible-file (edges heuristic) r:est_tokens=hdr-copy(none-if-stable) -->
<!-- files=1081 symbols=8835 edges=10480 shown=200 est_tokens=9117 ambiguous=3045 unresolved=1326 precise=3 skipped_oversize=14 order=important-first -->
<r est_tokens="9117">
<f p="./src/svector.h">
<s t="method" n="size" id="./src/svector.h::svector::size" k="0.0433">
</s>
<s t="method" n="push_back" id="./src/svector.h::svector::push_back" amb="2" k="0.0121">
<c n="buf"/>
<c n="buf"/>
<c n="grow"/>
</s>
<s t="method" n="buf" id="./src/svector.h::svector::buf" overloads="2" k="0.0110">
</s>
<s t="method" n="grow" id="./src/svector.h::svector::grow" amb="1" k="0.0065">
<c n="buf"/>
<c n="buf"/>
</s>
<s t="method" n="end" id="./src/svector.h::svector::end" overloads="2" amb="1" k="0.0040">
<c n="buf"/>
<c n="buf"/>
</s>
<s t="method" n="reserve" id="./src/svector.h::svector::reserve" k="0.0025">
<c n="grow"/>
</s>
<s t="method" n="begin" id="./src/svector.h::svector::begin" overloads="2" amb="1" k="0.0021">
<c n="buf"/>
<c n="buf"/>
</s>
</f>
<f p="./src/scipoverlay.h">
… [800 more display lines; full output is 22571 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --top-k=5`

*Same map, capped to the 5 highest-ranked symbols.*

`````
<!-- ripwire v1 t=fn|method|cls|struct|iface|var|sec p=path layer=arch-layer(opt) n=name id=canonical(path::scope::name,when-scoped) k=rank c=call amb=ambiguous-calls(read-source) overloads=N-same-name-defs-merged-into-this-row(absent-if-1;shown=counts-them-individually,so-rows+sum(overloads-1)=shown) prov=scip(precise;else name-based) hdr:unresolved=call-name-defined-only-in-a-lang-incompatible-file (edges heuristic) r:est_tokens=hdr-copy(none-if-stable) -->
<!-- files=1081 symbols=8835 edges=10480 shown=5 est_tokens=429 ambiguous=3045 unresolved=1326 precise=3 skipped_oversize=14 order=important-first -->
<r est_tokens="429">
<f p="./src/svector.h">
<s t="method" n="size" id="./src/svector.h::svector::size" k="0.0433">
</s>
<s t="method" n="push_back" id="./src/svector.h::svector::push_back" amb="2" k="0.0121">
<c n="buf"/>
<c n="buf"/>
<c n="grow"/>
</s>
<s t="method" n="buf" id="./src/svector.h::svector::buf" overloads="2" k="0.0110">
</s>
</f>
<f p="./src/scipoverlay.h">
<s t="method" n="empty" id="./src/scipoverlay.h::ScipOverlay::empty" k="0.0113">
</s>
</f>
</r>
`````

## `./build/ripwire . --top-k=0 --expand=rankGraphTeleport`

*NEW since the last capture: --top-k=0 means PAYLOAD-ONLY — no ranked map rides along with the body you asked for.*

`````
<ctx><bodies shown="1" total="1" capped="0"><b t="fn" l="1738" p="./src/graph.h" n="rankGraphTeleport"><![CDATA[inline std::vector<float> rankGraphTeleport( const Graph& g, const std::vector<float>& p, float alpha = 0.85f )
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
        {
            teleportMass += value;
        }
        if( teleportMass > 0.0 )
        {
            const double inverseMass = 1.0 / teleportMass;
            for( double& value : teleport )
            {
                value *= inverseMass;
            }
        }
        pageRankDouble( g.inEdges, g.wOutDeg, teleport, rankDouble, PageRankConfig{ .alpha = double( alpha ) } );
    }
    std::vector<float> r( N, 0.f );
    std::transform( rankDouble.begin(), rankDouble.end(), r.begin(), []( double value ) { return float( value ); } );
    return r;
}]]><calls total="7"><c n="biasPrior" l="1714">inline std::vector&lt;float&gt; biasPrior( const Graph&amp; g, const std::vector&lt;float&gt;&amp; p )</c><c n="pageRankDouble" l="36">unsigned pageRankDouble( const sparseCsr&lt;float&gt;&amp; inEdges, std::span&lt;const double&gt; weightedOutDegree, s … [line truncated: 374 more bytes on this line]
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
<!-- files=1081 symbols=8835 edges=10480 shown=22 est_tokens=1269 ambiguous=3045 unresolved=1326 precise=3 skipped_oversize=14 max_tokens=1500 fit_bytes=3186 order=important-first -->
<r est_tokens="1269">
<f p="./src/svector.h">
<s t="method" n="size" id="./src/svector.h::svector::size" k="0.0433">
</s>
<s t="method" n="push_back" id="./src/svector.h::svector::push_back" amb="2" k="0.0121">
<c n="buf"/>
<c n="buf"/>
<c n="grow"/>
</s>
<s t="method" n="buf" id="./src/svector.h::svector::buf" overloads="2" k="0.0110">
</s>
<s t="method" n="grow" id="./src/svector.h::svector::grow" amb="1" k="0.0065">
<c n="buf"/>
<c n="buf"/>
</s>
<s t="method" n="end" id="./src/svector.h::svector::end" overloads="2" amb="1" k="0.0040">
<c n="buf"/>
<c n="buf"/>
</s>
<s t="method" n="reserve" id="./src/svector.h::svector::reserve" k="0.0025">
<c n="grow"/>
</s>
<s t="method" n="begin" id="./src/svector.h::svector::begin" overloads="2" amb="1" k="0.0021">
<c n="buf"/>
<c n="buf"/>
</s>
</f>
… [50 more display lines; full output is 3148 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --token-budget=100`

*GATE form: exit 3 if the map's own est_tokens exceeds the budget (over-budget failure shape).*

**exit code: 3**

`````
<r withheld_est_tokens="9117" budget="100" withheld="1"/>
`````

stderr:

`````
ripwire: --token-budget exceeded: withheld_est_tokens=9117 > budget=100
`````

## `./build/ripwire . --for="incremental cache invalidation when a file content hash changes"`

*The task lens: ranked signatures + quality metrics framed for the task.*

`````
<ctx task="incremental cache invalidation when a file content hash changes" route=" [routed: subtoken+body BM25 (--for&apos;s default) — no strong name hit, multi-word conceptual query]">
<!-- ripwire lens for "incremental cache invalidation when a file content hash changes" [doc mentions: 1 doc discussing 1 top-ranked symbol surfaced]: reusable building blocks + quality facts for what you're about to touch (cx=complexity ccx=cognitive in=reuse-count churn=recent-commits amp=change-amplification clone=1(duplicated) tested=1) — prefer composing/reusing these; watch the high-churn/high-amp/cloned ones est_tokens="2944" -->
<sigs capped="1">
<f p="./src/ingest.h">
<d l="90" n="ingest" id="./src/ingest.h::rw::ingest" cx="1" ccx="0" in="0" churn="8" amp="18">
<doc>for vendored/generated trees not caught by the built-in dir denylist (--exclude=SUBSTR). cacheFi…</doc>IngestResult ingest( const char* rootDir, const std::vector&lt;std::string&gt;&amp; excludeSubstr =</d>
</f>
<f p="./src/mcpindex.h">
<d l="134" n="collectDirMtimes" id="./src/mcpindex.h::mcpdetail::collectDirMtimes" cx="13" ccx="21" in="1" churn="11" amp="14">inline void collectDirMtimes( const std::string&amp; root, HashMap&lt;std::string, long long&gt;&amp; dirMtime…</d>
<d l="359" n="byteHash" id="./src/mcpindex.h::mcpdetail::byteHash" cx="2" ccx="1" in="4" churn="11" amp="17">inline std::uint64_t byteHash( const char* data, std::size_t n ) noexcept</d>
<d l="391" n="stableHandleId" id="./src/mcpindex.h::mcpdetail::stableHandleId" cx="2" ccx="1" in="2" churn="11" amp="15">inline std::string stableHandleId( const std::string&amp; canonId, const std::string&amp; path, const std::string&amp; name )</d>
<d l="405" n="makeHandle" id="./src/mcpindex.h::mcpdetail::makeHandle" cx="1" ccx="0" in="1" churn="11" amp="14">inline std::string makeHandle( const std::string&amp; canonId, const std::string&amp; path, const std::string&amp; name, std::uint64_t contentHash )</d>
<d l="418" n="parseHandle" id="./src/mcpindex.h::mcpdetail::parseHandle" cx="10" ccx="13" in="1" churn="11" amp="14">inline bool parseHandle( const std::string&amp; h, std::uint64_t&amp; idHash, std::uint64_t&amp; contentHash )</d>
<d l="468" n="indexContentHash" id="./src/mcpindex.h::mcpdetail::indexContentHash" cx="5" ccx="7" in="1" churn="11" amp="14">inline std::uint64_t indexContentHash( const std::vector&lt;std::string&gt;&amp; files, const std::vector&lt;long long&gt;&amp; fileMtime, const std::vector&lt;std::uint64_t&g … [line truncated: 22 more bytes on this line]
<d l="499" n="McpIndex" id="./src/mcpindex.h::McpIndex::McpIndex" cx="0" ccx="0" in="0" churn="11" amp="13">
<doc>persistent in-memory index (parse once, reuse across MCP calls) ---- The MCP server is long-live…</doc>struct McpIndex</d>
<d l="633" n="mcpStale" id="./src/mcpindex.h::rw::mcpStale" cx="9" ccx="13" in="1" churn="11" amp="14">inline bool mcpStale( const McpIndex&amp; ix, bool skipDirSweep = false )</d>
<d l="913" n="getIndex" id="./src/mcpindex.h::rw::getIndex" cx="20" ccx="37" in="25" churn="11" amp="38">
<doc>the cached index for `root`, rebuilt only when stale (otherwise returned as-is, no parse, no gra…</doc>inline const McpIndex&amp; getIndex( const std::string&amp; root )</d>
<d l="1054" n="handleFor" id="./src/mcpindex.h::rw::handleFor" cx="4" ccx="3" in="1" churn="11" amp="14">inline std::string handleFor( const McpIndex&amp; ix, NodeId id )</d>
<d l="1074" n="resolveHandleAll" id="./src/mcpindex.h::rw::resolveHandleAll" cx="5" ccx="8" in="2" churn="11" amp="15">inline NodeId resolveHandleAll( const McpIndex&amp; ix, std::uint64_t idHash, std::vector&lt; NodeId &gt;&amp; matches )</d>
</f>
<f p="./src/ingest.cpp">
<d l="87" n="LexPair" id="./src/ingest.cpp::LexPair::LexPair" cx="0" ccx="0" in="0" churn="43" amp="116">struct LexPair</d>
<d l="696" n="StatInfo" id="./src/ingest.cpp::StatInfo::StatInfo" cx="0" ccx="0" in="0" churn="43" amp="116">struct StatInfo</d>
<d l="729" n="PathShape" cx="0" ccx="0" in="0" churn="43" amp="116">enum class PathShape : std::uint8_t</d>
<d l="753" n="wallClockNs" cx="1" ccx="0" in="1" churn="43" amp="117" tested="1">inline long long wallClockNs() noexcept</d>
<d l="813" n="compiledQueryCache" cx="1" ccx="0" in="2" churn="43" amp="118" tested="1">HashMap&lt;const TSLanguage*, TSQuery*&gt;&amp; compiledQueryCache()</d>
<d l="1239" n="contentHash64" cx="2" ccx="1" in="1" churn="43" amp="117" tested="1">
<doc>T5: renamed from fnv1a64 to contentHash64 to avoid an ODR clash now that this file also includes…</doc>inline std::uint64_t contentHash64( std::string_view s ) noexcept</d>
… [24 more display lines; full output is 7361 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --for="rankGraphTeleport"`

*Name-shaped query: the router picks name-exact BM25 (header says which/why).*

`````
<ctx task="rankGraphTeleport" route=" [routed: name-exact BM25 — query names a symbol (rankGraphTeleport); anchors: rankGraphTeleport(src/graph.h)]">
<!-- ripwire lens for "rankGraphTeleport": reusable building blocks + quality facts for what you're about to touch (cx=complexity ccx=cognitive in=reuse-count churn=recent-commits amp=change-amplification clone=1(duplicated) tested=1) — prefer composing/reusing these; watch the high-churn/high-amp/cloned ones est_tokens="2669" -->
<sigs>
<f p="./src/graph.h">
<d l="1738" n="rankGraphTeleport" id="./src/graph.h::rw::rankGraphTeleport" cx="5" ccx="8" in="6" churn="10" amp="41">
<doc>PageRank with an explicit teleport / personalization vector p (Σp = 1). The prior is name-quality-biased through biasPrior() so all rank modes share one weighting seam; the transition matrix (edges</doc>inline std::vector&lt;float&gt; rankGraphTeleport( const Graph&amp; g, const std::vector&lt … [line truncated: 44 more bytes on this line]
</f>
<f p="./.codex-plugin/plugin.json">
<d l="2" n="name" cx="0" ccx="0" in="0" churn="1">&quot;name&quot;: &quot;ripwire&quot;</d>
<d l="3" n="version" cx="0" ccx="0" in="0" churn="1">&quot;version&quot;: &quot;0.1.0&quot;</d>
<d l="4" n="description" cx="0" ccx="0" in="0" churn="1">&quot;description&quot;: &quot;Deterministic codebase maps, call-graph retrieval, and change-safety workflows for coding agents.&quot;</d>
<d l="5" n="author" cx="0" ccx="0" in="0" churn="1">&quot;author&quot;:</d>
<d l="6" n="name" cx="0" ccx="0" in="0" churn="1">&quot;name&quot;: &quot;Red Hat Emerging Technologies&quot;</d>
<d l="7" n="url" cx="0" ccx="0" in="0" churn="1">&quot;url&quot;: &quot;https://github.com/redhat-et&quot;</d>
<d l="9" n="homepage" cx="0" ccx="0" in="0" churn="1">&quot;homepage&quot;: &quot;https://github.com/redhat-et/ripwire&quot;</d>
<d l="10" n="repository" cx="0" ccx="0" in="0" churn="1">&quot;repository&quot;: &quot;https://github.com/redhat-et/ripwire&quot;</d>
<d l="11" n="license" cx="0" ccx="0" in="0" churn="1">&quot;license&quot;: &quot;Apache-2.0&quot;</d>
<d l="12" n="keywords" cx="0" ccx="0" in="0" churn="1">&quot;keywords&quot;: [ &quot;codex&quot;, &quot;openai-codex&quot;, &quot;mcp&quot;, &quot;code-navigation&quot;, &quot;context-engineering&quot; ]</d>
<d l="19" n="skills" cx="0" ccx="0" in="0" churn="1">&quot;skills&quot;: &quot;./skills/&quot;</d>
<d l="20" n="mcpServers" cx="0" ccx="0" in="0" churn="1">&quot;mcpServers&quot;: &quot;./.mcp.json&quot;</d>
<d l="21" n="interface" cx="0" ccx="0" in="0" churn="1">&quot;interface&quot;:</d>
<d l="22" n="displayName" cx="0" ccx="0" in="0" churn="1">&quot;displayName&quot;: &quot;Ripwire&quot;</d>
<d l="23" n="shortDescription" cx="0" ccx="0" in="0" churn="1">&quot;shortDescription&quot;: &quot;Deterministic codebase context for coding agents&quot;</d>
<d l="24" n="longDescription" cx="0" ccx="0" in="0" churn="1">&quot;longDescription&quot;: &quot;Map repositories, retrieve task-relevant symbols, trace impact, and run change-safety checks without embeddings or a runtime service.&quot;</d>
<d l="25" n="developerName" cx="0" ccx="0" in="0" churn="1">&quot;developerName&quot;: &quot;Red Hat Emerging Technologies&quot;</d>
<d l="26" n="category" cx="0" ccx="0" in="0" churn="1">&quot;category&quot;: &quot;Developer Tools&quot;</d>
<d l="27" n="capabilities" cx="0" ccx="0" in="0" churn="1">&quot;capabilities&quot;: [&quot;Read&quot;, &quot;Write&quot;]</d>
<d l="28" n="websiteURL" cx="0" ccx="0" in="0" churn="1">&quot;websiteURL&quot;: &quot;https://github.com/redhat-et/ripwire&quot;</d>
<d l="29" n="defaultPrompt" cx="0" ccx="0" in="0" churn="1">&quot;defaultPrompt&quot;: [ &quot;Map this repository before we start editing.&quot;, &quot;Find the code and tests relevant to this task.&quot;, &quot;Review my working changes and name the tests to run.&quot; ]</d>
<d l="34" n="brandColor" cx="0" ccx="0" in="0" churn="1">&quot;brandColor&quot;: &quot;#EE0000&quot;</d>
… [26 more display lines; full output is 6672 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --for="rankGraphTeleport" --no-route`

*Same query with routing forced OFF (plain subtoken+body BM25) — contrast with the routed run.*

`````
<ctx task="rankGraphTeleport">
<!-- ripwire lens for "rankGraphTeleport" [doc mentions: 1 doc discussing 1 top-ranked symbol surfaced]: reusable building blocks + quality facts for what you're about to touch (cx=complexity ccx=cognitive in=reuse-count churn=recent-commits amp=change-amplification clone=1(duplicated) tested=1) — prefer composing/reusing these; watch the high-churn/high-amp/cloned ones est_tokens="2888" -->
<sigs capped="1">
<f p="./src/graph.h">
<d l="32" n="Graph" id="./src/graph.h::Graph::Graph" cx="0" ccx="0" in="0" churn="10" amp="35">struct Graph</d>
<d l="1714" n="biasPrior" id="./src/graph.h::rw::biasPrior" cx="5" ccx="4" in="1" churn="10" amp="36">inline std::vector&lt;float&gt; biasPrior( const Graph&amp; g, const std::vector&lt;float&gt;&amp; p )</d>
<d l="1738" n="rankGraphTeleport" id="./src/graph.h::rw::rankGraphTeleport" cx="5" ccx="8" in="6" churn="10" amp="41">
<doc>PageRank with an explicit teleport / personalization vector p (Σp = 1). The prior is name-quali…</doc>inline std::vector&lt;float&gt; rankGraphTeleport( const Graph&amp; g, const std::vector&lt;float&gt;&amp; p, float alpha = 0.85f )</d>
<d l="1768" n="rankGraph" id="./src/graph.h::rw::rankGraph" cx="2" ccx="1" in="9" churn="10" amp="44">
<doc>uniform-teleport PageRank (the default</doc>inline std::vector&lt;float&gt; rankGraph( const Graph&amp; g, float alpha = 0.85f )</d>
<d l="2104" n="anchoredLexicalRank" id="./src/graph.h::rw::anchoredLexicalRank" cx="10" ccx="10" in="4" churn="10" amp="39">
<doc>anchored rank: pick the top-kAnchorCount symbols by lexical score (score desc, id asc — determ…</doc>inline std::vector&lt;float&gt; anchoredLexicalRank( const Graph&amp; g, const std::vector&lt;float&gt;&amp; lex )</d>
<d l="2726" n="diffTeleport" id="./src/graph.h::rw::diffTeleport" cx="8" ccx="9" in="3" churn="10" amp="38">inline std::vector&lt;float&gt; diffTeleport( const IngestResult&amp; ing, const std::vector&lt;char&gt;&amp; fileChanged, float beta = 0.7f )</d>
</f>
<f p="./src/main.cpp">
<d l="1906" n="computeLensRanking" cx="43" ccx="76" in="3" churn="65" amp="132">rw::LensRanking computeLensRanking( const MainDispatch&amp; d, std::string_view task )</d>
<d l="5389" n="runGraphQuery" cx="7" ccx="12" in="1" churn="65" amp="130">std::optional&lt;int&gt; runGraphQuery( const MainDispatch&amp; d )</d>
<d l="6012" n="runImpact" cx="8" ccx="14" in="1" churn="65" amp="130">std::optional&lt;int&gt; runImpact( const MainDispatch&amp; d )</d>
<d l="6282" n="runExercises" cx="8" ccx="8" in="1" churn="65" amp="130">std::optional&lt;int&gt; runExercises( const MainDispatch&amp; d )</d>
<d l="8205" n="runStructureText" cx="84" ccx="209" in="1" churn="65" amp="130">std::optional&lt;int&gt; runStructureText( const MainDispatch&amp; d )</d>
<d l="9425" n="runAround" cx="12" ccx="21" in="1" churn="65" amp="130">std::optional&lt;int&gt; runAround( const MainDispatch&amp; d )</d>
<d l="9597" n="ChurnRanking" id="./src/main.cpp::ChurnRanking::ChurnRanking" cx="0" ccx="0" in="0" churn="65" amp="129">struct ChurnRanking</d>
<d l="9599" n="churnRankedGraph" cx="7" ccx="8" in="1" churn="65" amp="130">inline ChurnRanking churnRankedGraph( const MainDispatch&amp; d )</d>
<d l="9703" n="runDefaultMap" cx="108" ccx="177" in="1" churn="65" amp="130">int runDefaultMap( const MainDispatch&amp; d )</d>
<d l="10491" n="ReportVerbSlot" id="./src/main.cpp::ReportVerbSlot::ReportVerbSlot" cx="0" ccx="0" in="0" churn="65" amp="129">struct ReportVerbSlot</d>
</f>
<f p="./src/gitmine.h">
<d l="1397" n="churnPriorFromFreq" id="./src/gitmine.h::rw::churnPriorFromFreq" cx="8" ccx="8" in="2" churn="6" amp="18">inline std::vector&lt;float&gt; churnPriorFromFreq( const IngestResult&amp; ing, const std::vector&lt;std::uint32_t&gt;&amp; freq, bool anyHistory )</d>
<d l="1428" n="churnTeleport" id="./src/gitmine.h::rw::churnTeleport" cx="4" ccx="4" in="1" churn="6" amp="17">inline std::vector&lt;float&gt; churnTeleport( const std::string&amp; root, const IngestResult&amp; ing, const char* since = &quot;18 months ago&quot;, const SinceScope* scope = nullpt…</ … [line truncated: 2 more bytes on this line]
<d l="1453" n="churnTeleportWorkspace" id="./src/gitmine.h::rw::churnTeleportWorkspace" cx="6" ccx="9" in="1" churn="6" amp="17">inline std::vector&lt;float&gt; churnTeleportWorkspace( const std::vector&lt;std::string&gt;&amp; rootDirs, const IngestResult&amp; ing, const char* since = &quot;18 month … [line truncated: 26 more bytes on this line]
… [37 more display lines; full output is 7219 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --for="tree-sitter parse of a source file" --adaptive`

*Cut the result at the relevance cliff (Adaptive-k).*

`````
<ctx task="tree-sitter parse of a source file" route=" [routed: subtoken+body BM25 (--for&apos;s default) — no strong name hit, multi-word conceptual query]">
<!-- ripwire lens for "tree-sitter parse of a source file" [adaptive: kept 40 of 40 - no relevance cliff (broad query saturates the score); capped at the ceiling]: reusable building blocks + quality facts for what you're about to touch (cx=complexity ccx=cognitive in=reuse-count churn=recent-commits amp=change-amplification clone=1(duplicated) tested=1) — prefer composing/reusing these; watch the high-churn/high-amp/cloned ones est_tokens="3032" -->
<sigs capped="1">
<f p="./src/ingest.cpp">
<d l="55" n="tree_sitter_cpp" cx="1" ccx="0" in="1" churn="43" amp="117">const TSLanguage* tree_sitter_cpp( void )</d>
<d l="56" n="tree_sitter_python" cx="1" ccx="0" in="0" churn="43" amp="116">const TSLanguage* tree_sitter_python( void )</d>
<d l="57" n="tree_sitter_go" cx="1" ccx="0" in="0" churn="43" amp="116">const TSLanguage* tree_sitter_go( void )</d>
<d l="58" n="tree_sitter_rust" cx="1" ccx="0" in="0" churn="43" amp="116">const TSLanguage* tree_sitter_rust( void )</d>
<d l="59" n="tree_sitter_typescript" cx="1" ccx="0" in="0" churn="43" amp="116">const TSLanguage* tree_sitter_typescript( void )</d>
<d l="60" n="tree_sitter_tsx" cx="1" ccx="0" in="0" churn="43" amp="116">const TSLanguage* tree_sitter_tsx( void )</d>
<d l="61" n="tree_sitter_swift" cx="1" ccx="0" in="0" churn="43" amp="116">const TSLanguage* tree_sitter_swift( void )</d>
<d l="62" n="tree_sitter_objc" cx="1" ccx="0" in="0" churn="43" amp="116">const TSLanguage* tree_sitter_objc( void )</d>
<d l="63" n="tree_sitter_javascript" cx="1" ccx="0" in="0" churn="43" amp="116">const TSLanguage* tree_sitter_javascript( void )</d>
<d l="64" n="tree_sitter_bash" cx="1" ccx="0" in="0" churn="43" amp="116">const TSLanguage* tree_sitter_bash( void )</d>
<d l="65" n="tree_sitter_java" cx="1" ccx="0" in="0" churn="43" amp="116">const TSLanguage* tree_sitter_java( void )</d>
<d l="66" n="tree_sitter_ruby" cx="1" ccx="0" in="0" churn="43" amp="116">const TSLanguage* tree_sitter_ruby( void )</d>
<d l="67" n="tree_sitter_json" cx="1" ccx="0" in="0" churn="43" amp="116">const TSLanguage* tree_sitter_json( void )</d>
<d l="68" n="tree_sitter_c_sharp" cx="1" ccx="0" in="0" churn="43" amp="116">const TSLanguage* tree_sitter_c_sharp( void )</d>
<d l="69" n="tree_sitter_c" cx="1" ccx="0" in="1" churn="43" amp="117">const TSLanguage* tree_sitter_c( void )</d>
<d l="70" n="tree_sitter_cuda" cx="1" ccx="0" in="0" churn="43" amp="116">const TSLanguage* tree_sitter_cuda( void )</d>
<d l="399" n="jsonNestsTooDeep" cx="13" ccx="20" in="1" churn="43" amp="117" tested="1">
<doc>True when raw bracket/brace nesting exceeds kMaxJsonNestDepth — degenerate or hostile DATA, never config (found live by bench/multiswe: tree-sitter-json&apos;s error recovery is superlinear on unclosed n</doc>bool jsonNestsTooDeep( std::string_view bytes ) noexcept</d>
<d l="2203" n="cc_declHasStructuredBinding" cx="5" ccx="6" in="1" churn="43" amp="117" tested="1">inline bool cc_declHasStructuredBinding( TSNode n, int depth ) noexcept</d>
<d l="6129" n="parseTree" cx="1" ccx="0" in="1" churn="43" amp="117" tested="1">TSTree* parseTree( TSParser* parser, std::string_view src )</d>
<d l="9138" n="collectGatedLocalNames" id="./src/ingest.cpp::rw::collectGatedLocalNames" cx="7" ccx="6" in="1" churn="43" amp="117">
<doc>local-variable-indexing plan, Phase 2 (PLAN.md 2026-08-06 evening) — see ingest.h&apos;s own comment for the full contract. Definition lives HERE (outside the anonymous namespace above) purely for LINKAG</doc>std::vector&lt;LocalNameFact&gt; collectGatedLocalNames( std::string_view defBytes,  … [line truncated: 43 more bytes on this line]
</f>
<f p="./src/mcpindex.h">
<d l="499" n="McpIndex" id="./src/mcpindex.h::McpIndex::McpIndex" cx="0" ccx="0" in="0" churn="11" amp="13">
<doc>persistent in-memory index (parse once, reuse across MCP calls) ---- The MCP server is long-lived; previously every verb re-parsed the whole tree (~6.5 s each). This caches the assembled {ingest</doc>struct McpIndex</d>
… [41 more display lines; full output is 7581 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --for="why does src/lexical.h chooseForRanker pick name-exact BM25"`

*Mention anchoring (default-on): a path and a Symbol literally named in the task get lifted; the header says what anchored.*

`````
<ctx task="why does src/lexical.h chooseForRanker pick name-exact BM25" route=" [routed: subtoken+body BM25 (--for&apos;s default) — no strong name hit, multi-word conceptual query]">
<!-- ripwire lens for "why does src/lexical.h chooseForRanker pick name-exact BM25" [mention anchor: 1 file + 3 symbols named in the task lifted near the top] [doc mentions: 1 doc discussing 1 top-ranked symbol surfaced]: reusable building blocks + quality facts for what you're about to touch (cx=complexity ccx=cognitive in=reuse-count churn=recent-commits amp=change-amplification clone=1(duplicated) tested=1) — prefer composing/reusing these; watch the high-churn/high-amp/cloned ones est_tokens="2880" -->
<sigs capped="1">
<f p="./src/eval.h">
<d l="155" n="printEvalRankerNote" id="./src/eval.h::rw::printEvalRankerNote" cx="1" ccx="0" in="1" churn="6" amp="8">
<doc>P11.12: the interpretive footer for --eval&apos;s ranker table, pulled into its own function so the 9…</doc>inline void printEvalRankerNote()</d>
<d l="168" n="runEval" id="./src/eval.h::rw::runEval" cx="44" ccx="66" in="1" churn="6" amp="8">inline int runEval( const std::string&amp; root, const IngestResult&amp; ing, const Graph&amp; g, const std::vector&lt;char&gt;&amp; currentDiff )</d>
<d l="252" n="fileDir" id="./src/eval.h::rw::fileDir" cx="1" ccx="0" in="0" churn="6" amp="7">std::vector&lt;std::string&gt; fileDir( F )</d>
<d l="496" n="runEvalRetrieval" id="./src/eval.h::rw::runEvalRetrieval" cx="15" ccx="25" in="1" churn="6" amp="8">inline int runEvalRetrieval( const IngestResult&amp; ing, const Graph&amp; g )</d>
<d l="826" n="maxPoolToFiles" id="./src/eval.h::rw::maxPoolToFiles" cx="4" ccx="4" in="2" churn="6" amp="9">inline std::vector&lt;float&gt; maxPoolToFiles( const IngestResult&amp; ing, const std::vector&lt;float&gt;&amp; sym…</d>
<d l="897" n="runEvalMined" id="./src/eval.h::rw::runEvalMined" cx="25" ccx="38" in="1" churn="6" amp="8">inline int runEvalMined( const std::string&amp; root, const IngestResult&amp; ing, const Graph&amp; g, const std::string&amp; path )</d>
</f>
<f p="./src/lexical.h">
<d l="100" n="lexicalScoresTiered" id="./src/lexical.h::rw::lexicalScoresTiered" cx="95" ccx="239" in="5" churn="10" amp="30">inline std::vector&lt;float&gt; lexicalScoresTiered( const IngestResult&amp; ing, const std::vector&lt;std::u…</d>
<d l="643" n="lexicalScoresNameExactTiered" id="./src/lexical.h::rw::lexicalScoresNameExactTiered" cx="35" ccx="61" in="5" churn="10" amp="30">
<doc>not every builder and every graph. This variant scores the query — tokenized on WHITESPACE onl…</doc>inline std::vector&lt;float&gt; lexicalScoresNameExactTiered( const IngestResult&amp; ing, std::string_view query, const std::vector&lt;float&gt;* symbolScoreMul )</d>
<d l="784" n="lexicalScoresNameExact" id="./src/lexical.h::rw::lexicalScoresNameExact" cx="1" ccx="0" in="3" churn="10" amp="28">
<doc>the un-tiered name-exact contract (--route, evals): unchanged arity, byte-identical scores</doc>inline std::vector&lt;float&gt; lexicalScoresNameExact( const IngestResult&amp; ing, std::string_view query )</d>
<d l="975" n="chooseForRanker" id="./src/lexical.h::rw::chooseForRanker" cx="28" ccx="38" in="7" churn="10" amp="32">inline RouteChoice chooseForRanker( const IngestResult&amp; ing, std::string_view query )</d>
</f>
<f p="./src/packtask.h">
<d l="39" n="LensRanking" id="./src/packtask.h::LensRanking::LensRanking" cx="0" ccx="0" in="0" churn="6" amp="15">struct LensRanking</d>
</f>
<f p="./src/naminglens.h">
<d l="789" n="NameCorpusStats" id="./src/naminglens.h::NameCorpusStats::NameCorpusStats" cx="0" ccx="0" in="0" churn="9" amp="29">struct NameCorpusStats</d>
<d l="835" n="subtokenIdf" id="./src/naminglens.h::detail::subtokenIdf" cx="2" ccx="1" in="1" churn="9" amp="30">inline double subtokenIdf( const NameCorpusStats&amp; stats, std::uint64_t hash )</d>
</f>
<f p="./src/mcpverbs.h">
<d l="871" n="forTaskText" id="./src/mcpverbs.h::rw::forTaskText" cx="32" ccx="42" in="2" churn="9" amp="38">inline std::string forTaskText( const std::string&amp; root, const std::string&amp; task, int topK, RedactCounts* redact = nullptr )</d>
<d l="2240" n="packTaskText" id="./src/mcpverbs.h::rw::packTaskText" cx="20" ccx="29" in="1" churn="9" amp="37">inline std::string packTaskText( const std::string&amp; root, const std::string&amp; task, std::size_t budgetTokens, RedactCounts* redact = nullptr, std::uint32_t parti…</d>
… [29 more display lines; full output is 7200 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --for="why does src/lexical.h chooseForRanker pick name-exact BM25" --no-mention-boost`

*Same task with the anchor disabled — the contrast the flag exists for.*

`````
<ctx task="why does src/lexical.h chooseForRanker pick name-exact BM25" route=" [routed: subtoken+body BM25 (--for&apos;s default) — no strong name hit, multi-word conceptual query]">
<!-- ripwire lens for "why does src/lexical.h chooseForRanker pick name-exact BM25" [doc mentions: 1 doc discussing 1 top-ranked symbol surfaced]: reusable building blocks + quality facts for what you're about to touch (cx=complexity ccx=cognitive in=reuse-count churn=recent-commits amp=change-amplification clone=1(duplicated) tested=1) — prefer composing/reusing these; watch the high-churn/high-amp/cloned ones est_tokens="2926" -->
<sigs capped="1">
<f p="./src/eval.h">
<d l="155" n="printEvalRankerNote" id="./src/eval.h::rw::printEvalRankerNote" cx="1" ccx="0" in="1" churn="6" amp="8">
<doc>P11.12: the interpretive footer for --eval&apos;s ranker table, pulled into its own function so the 9…</doc>inline void printEvalRankerNote()</d>
<d l="168" n="runEval" id="./src/eval.h::rw::runEval" cx="44" ccx="66" in="1" churn="6" amp="8">inline int runEval( const std::string&amp; root, const IngestResult&amp; ing, const Graph&amp; g, const std::vector&lt;char&gt;&amp; currentDiff )</d>
<d l="252" n="fileDir" id="./src/eval.h::rw::fileDir" cx="1" ccx="0" in="0" churn="6" amp="7">std::vector&lt;std::string&gt; fileDir( F )</d>
<d l="496" n="runEvalRetrieval" id="./src/eval.h::rw::runEvalRetrieval" cx="15" ccx="25" in="1" churn="6" amp="8">inline int runEvalRetrieval( const IngestResult&amp; ing, const Graph&amp; g )</d>
<d l="826" n="maxPoolToFiles" id="./src/eval.h::rw::maxPoolToFiles" cx="4" ccx="4" in="2" churn="6" amp="9">inline std::vector&lt;float&gt; maxPoolToFiles( const IngestResult&amp; ing, const std::vector&lt;float&gt;&amp; sym…</d>
<d l="897" n="runEvalMined" id="./src/eval.h::rw::runEvalMined" cx="25" ccx="38" in="1" churn="6" amp="8">inline int runEvalMined( const std::string&amp; root, const IngestResult&amp; ing, const Graph&amp; g, const std::string&amp; path )</d>
</f>
<f p="./src/packtask.h">
<d l="39" n="LensRanking" id="./src/packtask.h::LensRanking::LensRanking" cx="0" ccx="0" in="0" churn="6" amp="15">
<doc>per-symbol lens rank + the routing/mention/co-change header note fragments — populated identic…</doc>struct LensRanking</d>
</f>
<f p="./src/lexical.h">
<d l="100" n="lexicalScoresTiered" id="./src/lexical.h::rw::lexicalScoresTiered" cx="95" ccx="239" in="5" churn="10" amp="30">inline std::vector&lt;float&gt; lexicalScoresTiered( const IngestResult&amp; ing, const std::vector&lt;std::u…</d>
<d l="643" n="lexicalScoresNameExactTiered" id="./src/lexical.h::rw::lexicalScoresNameExactTiered" cx="35" ccx="61" in="5" churn="10" amp="30">inline std::vector&lt;float&gt; lexicalScoresNameExactTiered( const IngestResult&amp; ing, std::string_view query, const std::vector&lt;float&gt;* symbolScor … [line truncated: 10 more bytes on this line]
<d l="784" n="lexicalScoresNameExact" id="./src/lexical.h::rw::lexicalScoresNameExact" cx="1" ccx="0" in="3" churn="10" amp="28">inline std::vector&lt;float&gt; lexicalScoresNameExact( const IngestResult&amp; ing, std::string_view query )</d>
<d l="975" n="chooseForRanker" id="./src/lexical.h::rw::chooseForRanker" cx="28" ccx="38" in="7" churn="10" amp="32">inline RouteChoice chooseForRanker( const IngestResult&amp; ing, std::string_view query )</d>
</f>
<f p="./src/naminglens.h">
<d l="789" n="NameCorpusStats" id="./src/naminglens.h::NameCorpusStats::NameCorpusStats" cx="0" ccx="0" in="0" churn="9" amp="29">struct NameCorpusStats</d>
<d l="835" n="subtokenIdf" id="./src/naminglens.h::detail::subtokenIdf" cx="2" ccx="1" in="1" churn="9" amp="30">inline double subtokenIdf( const NameCorpusStats&amp; stats, std::uint64_t hash )</d>
</f>
<f p="./src/mcpverbs.h">
<d l="871" n="forTaskText" id="./src/mcpverbs.h::rw::forTaskText" cx="32" ccx="42" in="2" churn="9" amp="38">inline std::string forTaskText( const std::string&amp; root, const std::string&amp; task, int topK, RedactCounts* redact = nullptr )</d>
<d l="2240" n="packTaskText" id="./src/mcpverbs.h::rw::packTaskText" cx="20" ccx="29" in="1" churn="9" amp="37">inline std::string packTaskText( const std::string&amp; root, const std::string&amp; task, std::size_t budgetTokens, RedactCounts* redact = nullptr, std::uint32_t parti…</d>
</f>
… [31 more display lines; full output is 7316 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --lego=Vehicle`

*Interface -> implementors view: method contract + every existing impl.*

`````
<ctx><lego><iface n="Vehicle" p="./test/legofix/vehicle.rs" methods="0" caveat="not-extracted-for-lang" implementors="2"><impl n="Car" p="./test/legofix/vehicle.rs"/><impl n="Bike" p="./test/legofix/vehicle.rs"/></iface></lego></ctx>
`````

## `./build/ripwire . --exemplar="format byte sizes for humans"`

*The repo's best-in-class instance to imitate before writing new code (picked by ROLE).*

`````
<!-- ripwire exemplar for "format byte sizes for humans" (task -> kind=fn, low-confidence: weak match, fell back to fn): the repo's best-in-class fn to imitate — chosen by ROLE, NEVER by text similarity to your task: candidates are first filtered to cognitive complexity at or under the ccx ceiling (4x the complexity bar), then ordered non-fixture path before test-fixture path, tested before untested, higher fan-in, lower complexity, fewer lines, lowest id. low_confidence=1 marks a weak task-to-kind match that fell back to fn; over_ccx_bar=1 marks a corpus where nothing was under the ceiling, so the pick is the least bad rather than a clean one; candidates= counts the ELIGIBLE instances of the kind (post-ceiling), not every instance. On the root, the three attributes that ARE that ordering's evidence: in=reuse-count (callers), ccx=cognitive complexity, tested=1 when a test reaches it (OMITTED, never 0, when none does). The body follows in a bodies section, its callee signatures in a calls child; both disclose truncation the house way: total= is how many qualified, shown= how many are printed, capped=1 when the two differ (calls omits shown= and capped= when its list is complete). Copy its shape, not its text. -->
<exemplar kind="fn" candidates="5126" n="min" p="./src/infra/platform.h:95" in="98" ccx="1" tested="1" low_confidence="1">
<bodies shown="1" total="1" capped="0">
<b t="fn" l="95" p="./src/infra/platform.h" n="min">
<![CDATA[[[nodiscard]] ALWAYS_INLINE constexpr T min( T a, T b ) noexcept { return b < a ? b : a; }]]>
</b>
</bodies>
</exemplar>
`````

## `./build/ripwire . --recall="quality delta gating exit codes"`

*Most relevant DOCS' full bodies (markdown only) — recall what is already written down.*

`````
ripwire recall — "quality delta gating exit codes" — 63 relevant of 120 document files, best-first — total=63 shown=8 capped=1 generated_demoted=1 est_tokens=103870

━━ ./skills/ripwire-quality-bar/SKILL.md  (relevance 5.048) ━━
---
name: ripwire-quality-bar
description: >
  The code-QUALITY bar for what you just wrote — not merge-safety. Needs NO setup: right before you commit /
  open a PR / tell the user it's finished, run `ripwire <dir> --quality-delta` — reports ONLY what you made
  WORSE across 10 measured kinds (complexity, verbosity, nesting, params, duplication, dead-code,
  API-surface, error-masking, short-horizon-churn, new-clone-of-reused-helper — the measured agent-code
  failure modes), exiting non-zero on new debt. Want the wider six-family "does this still look rotten" read
  alongside the delta? `--quality-panel` is THE SINGLE COMMAND for that — the headline wide-angle pass below.
  Also carries the two things a measurement alone doesn't give you: the **shape → refactor playbook** (a
  measured shape mapped to its named fix AND that fix's precondition, so you don't guard-clause a numeric
  kernel or refactor an untested hub) and the **closed fix loop** that proves the fix landed
  (`--quality-delta` → `--edit-check` → `--affected`). Fix the real regressions, re-run, converge. Reach for this at
  every "I think this is done" moment on non-trivial work. The check itself is cheap (well under a second
  warm) — run it even on a fix that looks trivial, because "trivial" is exactly the judgment this pass exists
  to catch you being wrong about; what a single-line leaf fix with no new branch/symbol/signature can skip is
  the CONVERGENCE LOOP around it (re-reading the drill-down table, acking, chasing `--dmm`) — read this file
  only if the one-shot delta actually reports something. For
  merge-safety / blast-radius / tests-to-run →
  **ripwire-change-check** instead (this skill judges the code, not whether it's safe to merge). Backed by
  ripwire (deterministic, on PATH).
allowed-tools: Bash, Read
---

# The quality-bar convergence loop

> Routing:
… [3512 more lines, 265888 bytes total]
`````

## `./build/ripwire . --tree`

*File-by-file orientation map (top symbols per file).*

`````
<!-- ripwire tree: each file + its top symbols by rank, files ordered by their best symbol's rank (path breaks ties) — a session-start orientation map. files= is the indexed corpus; rows list files WITH symbols; files_unlisted= holds the symbol-less remainder — files equals files_unlisted plus the LISTABLE file set, which is what the rows below enumerate before any paging window is applied; under explicit paging (limit=/offset=) that listable count is emitted as total= and shown= says how many of it these rows are -->
<tree files="1081" files_unlisted="32">
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
<file p="./src/infra/platform.h" symbols="5">
<s t="fn" n="max"/>
<s t="fn" n="min"/>
<s t="fn" n="isFiniteFast"/>
</file>
<file p="./src/ingest.cpp" symbols="280">
<s t="method" n="find"/>
<s t="method" n="u32"/>
<s t="fn" n="finalSegment"/>
</file>
<file p="./src/renamemine.h" symbols="22">
<s t="method" n="clear"/>
<s t="fn" n="foldHunk"/>
… [4703 more display lines; full output is 135189 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --html=<scratch>/aux/map2.html`

*Self-contained HTML force-directed call graph.*

`````
(empty)
`````

Artifact written:

`````
   51281 <scratch>/aux/map2.html
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
<!-- files=1081 symbols=8835 edges=10480 shown=5 est_tokens=401 ambiguous=3045 unresolved=1326 precise=3 skipped_oversize=14 order=stable -->
`````


---

# navigate / answer a question

## `./build/ripwire . --around=rankGraphTeleport`

*Ego graph around one symbol.*

`````
<!-- ripwire v1 t=fn|method|cls|struct|iface|var|sec p=path layer=arch-layer(opt) n=name id=canonical(path::scope::name,when-scoped) k=rank c=call amb=ambiguous-calls(read-source) overloads=N-same-name-defs-merged-into-this-row(absent-if-1;shown=counts-them-individually,so-rows+sum(overloads-1)=shown) prov=scip(precise;else name-based) hdr:unresolved=call-name-defined-only-in-a-lang-incompatible-file (edges heuristic) r:est_tokens=hdr-copy(none-if-stable) -->
<!-- files=1081 symbols=8835 edges=10480 shown=148 est_tokens=18483 ambiguous=3045 unresolved=1326 precise=3 skipped_oversize=14 order=important-first -->
<r est_tokens="18483">
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
… [2040 more display lines; full output is 45816 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --callers=rankGraphTeleport`

*Who calls SYM (1-hop in-edges).*

`````
<!-- ripwire callers/callees: the 1-hop call hierarchy read straight off the call graph. The callers form lists the symbols that CALL of=; the callees form lists the symbols of= itself calls. of= is the selector you passed, defs= how many DEFINITIONS that name resolved to (the rows UNION every def's neighbours), and count= the number of DISTINCT neighbour symbols (a floor, per counts_floor=), which the rows window with limit= and offset=. counts_floor="1" means every count on this element is a FLOOR, never a total. Call edges are extracted from source text by NAME, so a call that reaches its target through dynamic dispatch (a virtual, interface or duck-typed receiver), a callback or function pointer, a macro-generated call site, or a declaration that parses without a call expression (C++ most-vexing-parse) contributes no edge and is missing here. Read a zero as "none found", never as "none exists". COUNTING UNIT, and it differs by verb — which is why two of them report different numbers for one symbol. The callers, callees, edit-check, graph-query and pr-context counts are DISTINCT SYMBOLS: repeated calls from one caller, and calls to two overloads of one name, collapse into ONE row, their multiplicity surviving only in the call graph's edge weight. The reach counts (impact's reaches=, pr-context's dependents=) are the size of a transitive reach SET, each symbol counted once — not a count of calls or edges. The uses verb counts call SITES, one row per occurrence, so a larger count= there for the same symbol is these units agreeing, not disagreeing. The map header's edges= is a unit again different — distinct (caller,callee) PAIRS — and that document carries neither this marker nor this clause, so its numbers answer a different question. -->
<callers of="rankGraphTeleport" defs="1" count="6" counts_floor="1">
<s t="fn" n="runEval" p="./src/eval.h:168"/>
<s t="fn" n="rankGraph" p="./src/graph.h:1768"/>
<s t="fn" n="anchoredLexicalRank" p="./src/graph.h:2104"/>
<s t="fn" n="churnRankedGraph" p="./src/main.cpp:9599"/>
<s t="fn" n="runDefaultMap" p="./src/main.cpp:9703"/>
<s t="fn" n="getIndex" p="./src/mcpindex.h:913"/>
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
<s t="fn" n="biasPrior" p="./src/graph.h:1714"/>
<s t="fn" n="pageRankDouble" p="./src/pagerank.cpp:36"/>
<s t="method" n="size" p="./src/svector.h:127"/>
<s t="method" n="begin" p="./src/svector.h:129"/>
<s t="method" n="end" p="./src/svector.h:130"/>
<s t="method" n="begin" p="./src/svector.h:131"/>
<s t="method" n="end" p="./src/svector.h:132"/>
</callees>
`````

## `./build/ripwire . --uses=rankGraphTeleport`

*The resolvable use-sites (call/read/write/import/extends) with file:line; count= is a floor.*

`````
<!-- ripwire uses: the STATICALLY RESOLVABLE use-sites of SYM (role=call|read|write|import|extends; p=file:line) — a floor, see counts_floor below. Reference-name-based (same heuristic level as call edges) — verify in source if a name is overloaded. external="1" ⇒ SYM has no definition in the indexed tree under ANY spelling (stdlib/third-party) — never merely none in the file you qualified with (that spelling refuses instead). A "file:name" SYM narrows defs= AND the role="call" sites, which are kept only where the call RESOLVES to a chosen def (the callers verb's own narrowing, read the other way, so the two agree); read/write/import/extends carry no resolution and stay name-matched across every def sharing the name. narrowed_roles= names what narrowed, and defs_of_name=/call_sites_of_name= (file: qualifier only) are the un-narrowed totals. counts_floor="1" means every count on this element is a FLOOR, never a total. Call edges are extracted from source text by NAME, so a call that reaches its target through dynamic dispatch (a virtual, interface or duck-typed receiver), a callback or function pointer, a macro-generated call site, or a declaration that parses without a call expression (C++ most-vexing-parse) contributes no edge and is missing here. Read a zero as "none found", never as "none exists". COUNTING UNIT, and it differs by verb — which is why two of them report different numbers for one symbol. The callers, callees, edit-check, graph-query and pr-context counts are DISTINCT SYMBOLS: repeated calls from one caller, and calls to two overloads of one name, collapse into ONE row, their multiplicity surviving only in the call graph's edge weight. The reach counts (impact's reaches=, pr-context's dependents=) are the size of a transitive reach SET, each symbol counted once — not a count of calls or edges. The uses verb counts call SITES, one row per occurrence, so a larger count= there for the same symbol is these units agreeing, not disagreeing. The map header's edges= is a unit again different — distinct (caller,callee) PAIRS — and that document carries neither this marker nor this clause, so its numbers answer a different question. -->
<uses of="rankGraphTeleport" defs="1" external="0" count="7" counts_floor="1">
<u role="call" p="./src/eval.h:320" in_id="./src/eval.h::rw::runEval"/>
<u role="call" p="./src/graph.h:1771" in_id="./src/graph.h::rw::rankGraph"/>
<u role="call" p="./src/graph.h:2144" in_id="./src/graph.h::rw::anchoredLexicalRank"/>
<u role="call" p="./src/main.cpp:9621" in_id="churnRankedGraph"/>
<u role="call" p="./src/main.cpp:9629" in_id="churnRankedGraph"/>
<u role="call" p="./src/main.cpp:9791" in_id="runDefaultMap"/>
<u role="call" p="./src/mcpindex.h:999" in_id="./src/mcpindex.h::rw::getIndex"/>
</uses>
`````

## `./build/ripwire . --graph-query='and(callers(name("rankGraphTeleport"),2),kind(all,fn))'`

*Composable node-set query: functions within 2 caller-hops of rankGraphTeleport.*

`````
<!-- ripwire graph-query: a fixed-operator node-set query over the call graph (sources name/all; filters kind/cx/fanin/file; bounded closure callers/callees; joins and/or/not), ranked by importance + capped at the top-k limit (default 200); narrow the query or raise top-k for more. NOT Datalog. counts_floor="1" means every count on this element is a FLOOR, never a total. Call edges are extracted from source text by NAME, so a call that reaches its target through dynamic dispatch (a virtual, interface or duck-typed receiver), a callback or function pointer, a macro-generated call site, or a declaration that parses without a call expression (C++ most-vexing-parse) contributes no edge and is missing here. Read a zero as "none found", never as "none exists". COUNTING UNIT, and it differs by verb — which is why two of them report different numbers for one symbol. The callers, callees, edit-check, graph-query and pr-context counts are DISTINCT SYMBOLS: repeated calls from one caller, and calls to two overloads of one name, collapse into ONE row, their multiplicity surviving only in the call graph's edge weight. The reach counts (impact's reaches=, pr-context's dependents=) are the size of a transitive reach SET, each symbol counted once — not a count of calls or edges. The uses verb counts call SITES, one row per occurrence, so a larger count= there for the same symbol is these units agreeing, not disagreeing. The map header's edges= is a unit again different — distinct (caller,callee) PAIRS — and that document carries neither this marker nor this clause, so its numbers answer a different question. -->
<query expr="and(callers(name(&quot;rankGraphTeleport&quot;),2),kind(all,fn))" count="44" shown="44" capped="0" counts_floor="1">
<s t="fn" n="getIndex" p="./src/mcpindex.h:913"/>
<s t="fn" n="emitCommunitiesReport" p="./src/main.cpp:7669"/>
<s t="fn" n="emitCommunityDrill" p="./src/main.cpp:7811"/>
<s t="fn" n="anchoredLexicalRank" p="./src/graph.h:2104"/>
<s t="fn" n="rankGraph" p="./src/graph.h:1768"/>
<s t="fn" n="computeLensRanking" p="./src/main.cpp:1906"/>
<s t="fn" n="dispatchMcpLine" p="./src/mcp.h:333"/>
<s t="fn" n="runEvalRetrieval" p="./src/eval.h:496"/>
<s t="fn" n="runEvalMined" p="./src/eval.h:897"/>
<s t="fn" n="symbolQueryJson" p="./src/mcpverbs.h:461"/>
<s t="fn" n="anchoredFileScore" p="./src/eval.h:108"/>
<s t="fn" n="analyzeToString" p="./src/mcpverbs.h:369"/>
<s t="fn" n="grepHitsJson" p="./src/mcpverbs.h:541"/>
<s t="fn" n="cochangePartnersJson" p="./src/mcpverbs.h:600"/>
<s t="fn" n="mentionsJson" p="./src/mcpverbs.h:822"/>
<s t="fn" n="forTaskText" p="./src/mcpverbs.h:871"/>
<s t="fn" n="legoText" p="./src/mcpverbs.h:1079"/>
<s t="fn" n="ownersText" p="./src/mcpverbs.h:1118"/>
<s t="fn" n="exemplarText" p="./src/mcpverbs.h:1224"/>
<s t="fn" n="impactText" p="./src/mcpverbs.h:1302"/>
<s t="fn" n="usesText" p="./src/mcpverbs.h:1444"/>
<s t="fn" n="pathText" p="./src/mcpverbs.h:1529"/>
<s t="fn" n="fetchBody" p="./src/mcpverbs.h:2522"/>
<s t="fn" n="churnRankedGraph" p="./src/main.cpp:9599"/>
<s t="fn" n="runEditVerb" p="./src/mcpedit.h:362"/>
<s t="fn" n="runBatchSub" p="./src/mcpverbs.h:2840"/>
<s t="fn" n="flagsText" p="./src/mcpverbs.h:428"/>
<s t="fn" n="flipText" p="./src/mcpverbs.h:440"/>
… [17 more display lines; full output is 4083 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --external-surface`

*Names referenced but never defined in-corpus (stdlib/third-party surface). NOW carries names/shown/capped (total= joins them only under --limit/--offset).*

`````
<!-- ripwire external-surface: names CALLED/IMPORTED/EXTENDED but never defined in the indexed tree = the stdlib/third-party surface the code depends on (refs=use-sites, calls=of-which-calls) -->
<external-surface names="1130" shown="1130" capped="0">
<x n="grep" lang="sh" refs="4537" calls="4537"/>
<x n="printf" lang="sh" refs="3944" calls="3944"/>
<x n="echo" lang="sh" refs="3631" calls="3631"/>
<x n="exit" lang="sh" refs="1367" calls="1367"/>
<x n="head" lang="sh" refs="992" calls="992"/>
<x n="cat" lang="sh" refs="869" calls="869"/>
<x n="cd" lang="sh" refs="784" calls="784"/>
<x n="c_str" lang="cpp" refs="721" calls="721"/>
<x n="tr" lang="sh" refs="713" calls="713"/>
<x n="fprintf" lang="cpp" refs="673" calls="673"/>
<x n="string" lang="cpp" refs="546" calls="546"/>
<x n="python3" lang="sh" refs="477" calls="477"/>
<x n="sed" lang="sh" refs="476" calls="476"/>
<x n="printf" lang="cpp" refs="474" calls="474"/>
<x n="substr" lang="cpp" refs="471" calls="471"/>
<x n="mkdir" lang="sh" refs="457" calls="457"/>
<x n="command" lang="sh" refs="424" calls="424"/>
<x n="mktemp" lang="sh" refs="422" calls="422"/>
<x n="strcmp" lang="cpp" refs="397" calls="397"/>
<x n="dirname" lang="sh" refs="395" calls="395"/>
<x n="len" lang="py" refs="383" calls="383"/>
<x n="pwd" lang="sh" refs="381" calls="381"/>
<x n="uint32_t" lang="cpp" refs="358" calls="358"/>
<x n="trap" lang="sh" refs="355" calls="355"/>
<x n="print" lang="py" refs="352" calls="352"/>
<x n="diff" lang="sh" refs="340" calls="340"/>
<x n="wc" lang="sh" refs="333" calls="333"/>
<x n="xmllint" lang="sh" refs="320" calls="320"/>
… [1103 more display lines; full output is 53922 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --path=main,rankGraphTeleport`

*Shortest directed call-path SRC -> DST. CHANGED: now reports from_p/to_p/from_defs and resolves the right `main` (was reachable="0").*

`````
<path from="main" to="rankGraphTeleport" from_p="./src/main.cpp:10992" to_p="./src/graph.h:1738" from_defs="57" to_defs="1" reachable="1" hops="2">
<s t="fn" n="main" p="./src/main.cpp:10992"/>
<s t="fn" n="runDefaultMap" p="./src/main.cpp:9703"/>
<s t="fn" n="rankGraphTeleport" p="./src/graph.h:1738"/>
</path>
`````

## `./build/ripwire . --connect=rankGraphTeleport,runEval,getIndex`

*Minimal connecting subgraph over 3 symbols (finds shared-caller joins).*

`````
<!-- ripwire connect: minimal joining subgraph over N task symbols (metric-closure 2-approx Steiner; search is undirected so SHARED-CALLER joins are found, every <e f= t=/> keeps its TRUE caller->callee direction; graph-structured navigation per CodeCompass, arXiv 2602.20048). Call edges are name-based: dynamic dispatch / callbacks may hide connections -->
<connect terminals="3" nodes="3" edges="2" radius="6" groups="1" est_tokens="287">
<g terminals="3">
<t n="runEval" t="fn" p="./src/eval.h:168"/>
<t n="rankGraphTeleport" t="fn" p="./src/graph.h:1738"/>
<t n="getIndex" t="fn" p="./src/mcpindex.h:913"/>
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
<s t="fn" n="getIndex" p="./src/mcpindex.h:913"/>
<s t="fn" n="emitCommunitiesReport" p="./src/main.cpp:7669"/>
<s t="fn" n="emitCommunityDrill" p="./src/main.cpp:7811"/>
<s t="fn" n="anchoredLexicalRank" p="./src/graph.h:2104"/>
<s t="fn" n="rankGraph" p="./src/graph.h:1768"/>
<s t="fn" n="computeLensRanking" p="./src/main.cpp:1906"/>
<s t="fn" n="dispatchMcpLine" p="./src/mcp.h:333"/>
<s t="fn" n="runEvalRetrieval" p="./src/eval.h:496"/>
<s t="fn" n="runEvalMined" p="./src/eval.h:897"/>
<s t="fn" n="symbolQueryJson" p="./src/mcpverbs.h:461"/>
<s t="fn" n="anchoredFileScore" p="./src/eval.h:108"/>
<s t="fn" n="analyzeToString" p="./src/mcpverbs.h:369"/>
<s t="fn" n="grepHitsJson" p="./src/mcpverbs.h:541"/>
<s t="fn" n="cochangePartnersJson" p="./src/mcpverbs.h:600"/>
<s t="fn" n="mentionsJson" p="./src/mcpverbs.h:822"/>
<s t="fn" n="forTaskText" p="./src/mcpverbs.h:871"/>
<s t="fn" n="legoText" p="./src/mcpverbs.h:1079"/>
<s t="fn" n="ownersText" p="./src/mcpverbs.h:1118"/>
<s t="fn" n="exemplarText" p="./src/mcpverbs.h:1224"/>
<s t="fn" n="impactText" p="./src/mcpverbs.h:1302"/>
<s t="fn" n="usesText" p="./src/mcpverbs.h:1444"/>
<s t="fn" n="pathText" p="./src/mcpverbs.h:1529"/>
<s t="fn" n="fetchBody" p="./src/mcpverbs.h:2522"/>
<s t="fn" n="churnRankedGraph" p="./src/main.cpp:9599"/>
<s t="fn" n="runEditVerb" p="./src/mcpedit.h:362"/>
<s t="fn" n="runBatchSub" p="./src/mcpverbs.h:2840"/>
<s t="fn" n="flagsText" p="./src/mcpverbs.h:428"/>
<s t="fn" n="flipText" p="./src/mcpverbs.h:440"/>
… [13 more display lines; full output is 3861 bytes on 1 raw line(s)]
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
<affected changed="src/graph.h" seeded_by="file" seeds="89" tests="6" reached="495" script_gates_unmodelled="388">
<test p="./test/cloneband_harness.cpp" run="bash test/clonebandcheck.sh"/>
<test p="./test/clonelex_harness.cpp" run="bash test/clonelexcheck.sh"/>
<test p="./test/connectcore_harness.cpp" run="bash test/connectcorecheck.sh"/>
<test p="./test/includeprecise_unit.cpp" run="bash test/includeprecisecheck.sh"/>
<test p="./test/rustimport_unit.cpp" run="bash test/rustimportprecisecheck.sh"/>
<test p="./test/type3clone_harness.cpp" run="bash test/type3clonecheck.sh"/>
</affected>
`````

## `./build/ripwire . --situ`

*Mid-task situational report for the current git diff — recorded against a CLEAN tree (contrast with the sandbox run below).*

`````
ripwire situational-awareness — 0 changed file(s), 0 symbols in them
  (no indexed symbols in the changed files — nothing to analyze)
`````

## `./build/ripwire . --test-gate`

*Pre-PR gate on a CLEAN tree: no obligations, exit 0.*

`````
<!-- ripwire test-gate (TDAD-parity, arXiv 2603.17973): the tests to run for this change + the UNTESTED blast radius. A queryable call-graph+test map cut agent-caused regressions -70% (6.08%->1.82%); this gate names the obligations, the agent runs the tests then relies on green. exit 4 if tests OR untested is non-empty. TWO INDEPENDENT LISTINGS, each with its own row count: shown_tests= counts the <t> tests-to-run rows and shown_untested= counts the <u> blast-radius rows (a single shown= could only ever have described one of them). The <t> rows are the COMPLETE obligation and are never windowed, so they REPEAT VERBATIM on every page — a walker that concatenates pages must take them from one page only; offset=/limit= window the <u> rows alone. The <u> listing shows 25 rows by default: raise the default cap with limit=N (offset=M pages). script_gates_unmodelled= counts test/*.sh runners in the corpus (a path count; not every one invokes the binary) - script-to-binary edges are NOT modelled, so those gates are invisible to this walk and never counted in tests=. UNIT: untested= here counts impacted SYMBOLS. The seams verb spells untested= over cross-directory call EDGES and the flip verb over the defs a gate lights, so the three numbers count three different things and must never be compared or summed across verbs. -->
<test-gate changed="0" impacted="0" tests="0" untested="0" shown_tests="0" tests_capped="0" shown_untested="0" untested_capped="0" script_gates_unmodelled="388" at="33f9f7be2">
</test-gate>
`````

## `./build/ripwire . --grep=DEGRADED_PATH_ALERT`

*Literal trigram-indexed search. CHANGED: each hit now carries the MATCHED line in <m>, plus shown/capped/hits_capped.*

`````
<!-- ripwire grep: parallel literal/regex scan; each hit carries its matched line (m) and enclosing symbol (in=, a NAME here; the same spelling is a fan-in COUNT in for/pack-task/exemplar). ORDER: SOURCE files before test/bench files before docs, then path and line. shown=/capped= = rows printed vs found; hits_capped="1" ⇒ hits= is a FLOOR (collection budget reached). raise the default cap with limit=N (offset=M pages); on the root, limit="0" means no explicit limit was given and the verb's own default page size shaped the window — never a zero-row page -->
<grep pattern="DEGRADED_PATH_ALERT" files="71" hits="257" shown="100" capped="1" hits_capped="0">
<hit p="./src/abicheck.h:107" in="">
<m>
<![CDATA[#include "Diagnostics.h"    // VERIFY / DEGRADED_PATH_ALERT]]>
</m>
</hit>
<hit p="./src/abicheck.h:477" in="abicheck::collectAuthoredSites">
<m>
<![CDATA[            DEGRADED_PATH_ALERT( "abi: no merge-base for a ref (unrelated history?) — that ref is counted, not compared" );]]>
</m>
</hit>
<hit p="./src/accessshape.h:132" in="">
<m>
<![CDATA[#include "Diagnostics.h"  // VERIFY / DEGRADED_PATH_ALERT]]>
</m>
</hit>
<hit p="./src/arch.h:31" in="">
<m>
<![CDATA[#include "Diagnostics.h"   // DEGRADED_PATH_ALERT — graceful-degrade on a malformed path-regex (never throw at match time)]]>
</m>
</hit>
<hit p="./src/arch.h:353" in="rw::parseArchRules">
<m>
<![CDATA[        DEGRADED_PATH_ALERT( "arch: malformed rules line — rules file rejected" );]]>
</m>
</hit>
<hit p="./src/arch.h:408" in="rw::parseArchRules">
<m>
<![CDATA[                catch( const std::regex_error& ) { pr.bad = true; DEGRADED_PATH_ALERT( "arch: malformed FROM path-regex — rule skipped" ); }]]>
… [473 more display lines; full output is 19040 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --grep=DEGRADED_PATH_ALERT --grep-context=1`

*Same search with one line of source context either side.*

`````
<!-- ripwire grep: parallel literal/regex scan; each hit carries its matched line (m) and enclosing symbol (in=, a NAME here; the same spelling is a fan-in COUNT in for/pack-task/exemplar). ORDER: SOURCE files before test/bench files before docs, then path and line. shown=/capped= = rows printed vs found; hits_capped="1" ⇒ hits= is a FLOOR (collection budget reached). raise the default cap with limit=N (offset=M pages); on the root, limit="0" means no explicit limit was given and the verb's own default page size shaped the window — never a zero-row page -->
<grep pattern="DEGRADED_PATH_ALERT" files="71" hits="257" shown="100" capped="1" hits_capped="0">
<hit p="./src/abicheck.h:107" in="">
<b>
<![CDATA[#include "serialize.h"      // escapeXml]]>
</b>
<m>
<![CDATA[#include "Diagnostics.h"    // VERIFY / DEGRADED_PATH_ALERT]]>
</m>
</hit>
<hit p="./src/abicheck.h:477" in="abicheck::collectAuthoredSites">
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
<hit p="./src/accessshape.h:132" in="">
<b>
<![CDATA[#include "docdrift.h"     // hasWholeWord — the house whole-word predicate]]>
</b>
<m>
<![CDATA[#include "Diagnostics.h"  // VERIFY / DEGRADED_PATH_ALERT]]>
</m>
</hit>
<hit p="./src/arch.h:31" in="">
… [1022 more display lines; full output is 29059 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --regex='fnv1a\w+'`

*Regex search + enclosing symbol.*

`````
<!-- ripwire grep: parallel literal/regex scan; each hit carries its matched line (m) and enclosing symbol (in=, a NAME here; the same spelling is a fan-in COUNT in for/pack-task/exemplar). ORDER: SOURCE files before test/bench files before docs, then path and line. shown=/capped= = rows printed vs found; hits_capped="1" ⇒ hits= is a FLOOR (collection budget reached). raise the default cap with limit=N (offset=M pages); on the root, limit="0" means no explicit limit was given and the verb's own default page size shaped the window — never a zero-row page -->
<grep pattern="fnv1a\w+" files="25" hits="112" shown="100" capped="1" hits_capped="0">
<hit p="./src/arch.h:507" in="rw::fnv1a64">
<m>
<![CDATA[inline std::uint64_t fnv1a64( std::string_view s ) noexcept]]>
</m>
</hit>
<hit p="./src/arch.h:512" in="rw::fnv1a64">
<m>
<![CDATA[        h = hashutil::fnv1aAbsorb( h, c );]]>
</m>
</hit>
<hit p="./src/arch.h:585" in="rw::archViolHash">
<m>
<![CDATA[            h = hashutil::fnv1aAbsorb( h, c );]]>
</m>
</hit>
<hit p="./src/arch.h:588" in="rw::archViolHash">
<m>
<![CDATA[        h = hashutil::fnv1aMultiply( h ); // NUL separator byte]]>
</m>
</hit>
<hit p="./src/clones.h:566" in="rw::cloneTokenHash">
<m>
<![CDATA[        h = hashutil::fnv1aAbsorb( h, c );]]>
</m>
</hit>
<hit p="./src/clones.h:568" in="rw::cloneTokenHash">
<m>
<![CDATA[    h ^= 0x9e3779b97f4a7c15ull;  h = hashutil::fnv1aMultiply( h );   // token separator so [ab][c] != [a][bc]]]>
… [473 more display lines; full output is 16100 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --match='(if_statement)'`

*Tree-sitter structural query WITHOUT a capture — a bare node query gets a capture AUTO-ADDED (auto_captured="1") instead of silently matching nothing.*

`````
<!-- ripwire match: tree-sitter structural query; each hit = a captured node + its enclosing symbol. shown=/capped= = rows printed vs found; hits_capped="1" ⇒ hits= is a FLOOR (engine match limit reached). auto_captured="1" ⇒ the query bound no @capture and ripwire appended `@m` to its single top-level pattern. raise the default cap with limit=N (offset=M pages) -->
<match hits="5000" shown="100" capped="1" hits_capped="1" auto_captured="1">
<m p="./bench/agentloop/analyze.py:34" in="load_results">if data.get( "schema" ) != SCHEMA:         raise SystemExit( f"{path}: unexpected schema {data.get('schema')!r} (expecte</m>
<m p="./bench/agentloop/analyze.py:51" in="pair_by_task_seed">if base and ctx and base["status"] == "ok" and ctx["status"] == "ok":             paired.append( ( instance_id, base["re</m>
<m p="./bench/agentloop/analyze.py:64" in="clustered_bootstrap_lower">if not repos: return 0.0, []</m>
<m p="./bench/agentloop/analyze.py:80" in="loc_hit_delta">if base["localization_hit"] is None or ctx["localization_hit"] is None: return 0.0</m>
<m p="./bench/agentloop/analyze.py:89" in="paired_ratio">if bv: ratios.append( cv / bv - 1 )</m>
<m p="./bench/agentloop/analyze.py:90" in="paired_ratio">if not ratios: return None, None</m>
<m p="./bench/agentloop/analyze.py:100" in="analyze">if not paired:         out["note"] = "zero complete paired (baseline,ripwire_cli) runs — nothing to analyze yet"      </m>
<m p="./bench/agentloop/analyze.py:128" in="print_report">if "note" in out:         print( f"  {out['note']}" ); return</m>
<m p="./bench/agentloop/analyze.py:179" in="self_test">if out["n_pairs"] != 27: failures.append( f"expected 27 paired runs, got {out['n_pairs']}" )</m>
<m p="./bench/agentloop/analyze.py:180" in="self_test">if out["n_incomplete"] != 1: failures.append( f"expected 1 incomplete pair, got {out['n_incomplete']}" )</m>
<m p="./bench/agentloop/analyze.py:181" in="self_test">if out["n_repos"] != 3: failures.append( f"expected 3 repos, got {out['n_repos']}" )</m>
<m p="./bench/agentloop/analyze.py:182" in="self_test">if not ( out["resolved_delta_mean"] &gt; 0 ): failures.append( "expected a positive resolved-rate delta" )</m>
<m p="./bench/agentloop/analyze.py:183" in="self_test">if not ( out["resolved_delta_bootstrap_95_lower"] &gt; 0 ):         failures.append( "expected a POSITIVE bootstrap 95% low</m>
<m p="./bench/agentloop/analyze.py:185" in="self_test">if out["tokens_out_ratio_p50"] is None or abs( out["tokens_out_ratio_p50"] - 0.08 ) &gt; 1e-6:         failures.append( f"e</m>
<m p="./bench/agentloop/analyze.py:188" in="self_test">if out.get( "n_resolved_pairs" ) != 27:         failures.append( f"expected all 27 pairs resolution-scored, got {out.get</m>
<m p="./bench/agentloop/analyze.py:194" in="self_test">if out2["n_pairs"] != 27:         failures.append( f"evaluator-none: expected 27 pairs, got {out2['n_pairs']}" )</m>
<m p="./bench/agentloop/analyze.py:196" in="self_test">if out2["n_resolved_pairs"] != 0:         failures.append( f"evaluator-none: expected 0 resolution-scored pairs, got {ou</m>
<m p="./bench/agentloop/analyze.py:198" in="self_test">if out2["resolved_delta_mean"] is not None or out2["resolved_delta_bootstrap_95_lower"] is not None:         failures.ap</m>
<m p="./bench/agentloop/analyze.py:200" in="self_test">if out2["tokens_out_ratio_p50"] is None or abs( out2["tokens_out_ratio_p50"] - 0.08 ) &gt; 1e-6:         failures.append( "</m>
<m p="./bench/agentloop/analyze.py:202" in="self_test">if failures:         print( "\nSELF-TEST FAIL:" )         for f in failures: print( f"  - {f}" )         return 1</m>
<m p="./bench/agentloop/analyze.py:216" in="main">if a.self_test:         return self_test()</m>
<m p="./bench/agentloop/analyze.py:219" in="main">if not a.results:         raise SystemExit( "--results PATH is required (or pass --self-test to validate the math on a f</m>
<m p="./bench/agentloop/analyze.py:226" in="">if __name__ == "__main__":     sys.exit( main() )</m>
<m p="./bench/agentloop/run_agentloop.py:85" in="load_tasks_lock">if lock.get( "schema" ) != "ripwire-agentloop-tasks-lock-v1":         raise SystemExit( f"{path}: unexpected schema {loc</m>
<m p="./bench/agentloop/run_agentloop.py:92" in="load_tasks_lock">if actual != expected:         raise SystemExit( f"{path}: content hash mismatch (expected {expected}, computed {actual}</m>
<m p="./bench/agentloop/run_agentloop.py:117" in="limit_tasks_repo_round_robin">if not limit or limit &gt;= len( tasks ):         return list( tasks )</m>
<m p="./bench/agentloop/run_agentloop.py:129" in="limit_tasks_repo_round_robin">if row_index &lt; len( rows ):                 selected.append( rows[row_index] )                 added = True             </m>
<m p="./bench/agentloop/run_agentloop.py:132" in="limit_tasks_repo_round_robin">if len( selected ) == limit:                     break</m>
… [73 more display lines; full output is 16313 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --match='(if_statement) @i'`

*The same shape query WITH a capture — the form that actually matches.*

`````
<!-- ripwire match: tree-sitter structural query; each hit = a captured node + its enclosing symbol. shown=/capped= = rows printed vs found; hits_capped="1" ⇒ hits= is a FLOOR (engine match limit reached). auto_captured="1" ⇒ the query bound no @capture and ripwire appended `@m` to its single top-level pattern. raise the default cap with limit=N (offset=M pages) -->
<match hits="5000" shown="100" capped="1" hits_capped="1">
<m p="./bench/agentloop/analyze.py:34" in="load_results">if data.get( "schema" ) != SCHEMA:         raise SystemExit( f"{path}: unexpected schema {data.get('schema')!r} (expecte</m>
<m p="./bench/agentloop/analyze.py:51" in="pair_by_task_seed">if base and ctx and base["status"] == "ok" and ctx["status"] == "ok":             paired.append( ( instance_id, base["re</m>
<m p="./bench/agentloop/analyze.py:64" in="clustered_bootstrap_lower">if not repos: return 0.0, []</m>
<m p="./bench/agentloop/analyze.py:80" in="loc_hit_delta">if base["localization_hit"] is None or ctx["localization_hit"] is None: return 0.0</m>
<m p="./bench/agentloop/analyze.py:89" in="paired_ratio">if bv: ratios.append( cv / bv - 1 )</m>
<m p="./bench/agentloop/analyze.py:90" in="paired_ratio">if not ratios: return None, None</m>
<m p="./bench/agentloop/analyze.py:100" in="analyze">if not paired:         out["note"] = "zero complete paired (baseline,ripwire_cli) runs — nothing to analyze yet"      </m>
<m p="./bench/agentloop/analyze.py:128" in="print_report">if "note" in out:         print( f"  {out['note']}" ); return</m>
<m p="./bench/agentloop/analyze.py:179" in="self_test">if out["n_pairs"] != 27: failures.append( f"expected 27 paired runs, got {out['n_pairs']}" )</m>
<m p="./bench/agentloop/analyze.py:180" in="self_test">if out["n_incomplete"] != 1: failures.append( f"expected 1 incomplete pair, got {out['n_incomplete']}" )</m>
<m p="./bench/agentloop/analyze.py:181" in="self_test">if out["n_repos"] != 3: failures.append( f"expected 3 repos, got {out['n_repos']}" )</m>
<m p="./bench/agentloop/analyze.py:182" in="self_test">if not ( out["resolved_delta_mean"] &gt; 0 ): failures.append( "expected a positive resolved-rate delta" )</m>
<m p="./bench/agentloop/analyze.py:183" in="self_test">if not ( out["resolved_delta_bootstrap_95_lower"] &gt; 0 ):         failures.append( "expected a POSITIVE bootstrap 95% low</m>
<m p="./bench/agentloop/analyze.py:185" in="self_test">if out["tokens_out_ratio_p50"] is None or abs( out["tokens_out_ratio_p50"] - 0.08 ) &gt; 1e-6:         failures.append( f"e</m>
<m p="./bench/agentloop/analyze.py:188" in="self_test">if out.get( "n_resolved_pairs" ) != 27:         failures.append( f"expected all 27 pairs resolution-scored, got {out.get</m>
<m p="./bench/agentloop/analyze.py:194" in="self_test">if out2["n_pairs"] != 27:         failures.append( f"evaluator-none: expected 27 pairs, got {out2['n_pairs']}" )</m>
<m p="./bench/agentloop/analyze.py:196" in="self_test">if out2["n_resolved_pairs"] != 0:         failures.append( f"evaluator-none: expected 0 resolution-scored pairs, got {ou</m>
<m p="./bench/agentloop/analyze.py:198" in="self_test">if out2["resolved_delta_mean"] is not None or out2["resolved_delta_bootstrap_95_lower"] is not None:         failures.ap</m>
<m p="./bench/agentloop/analyze.py:200" in="self_test">if out2["tokens_out_ratio_p50"] is None or abs( out2["tokens_out_ratio_p50"] - 0.08 ) &gt; 1e-6:         failures.append( "</m>
<m p="./bench/agentloop/analyze.py:202" in="self_test">if failures:         print( "\nSELF-TEST FAIL:" )         for f in failures: print( f"  - {f}" )         return 1</m>
<m p="./bench/agentloop/analyze.py:216" in="main">if a.self_test:         return self_test()</m>
<m p="./bench/agentloop/analyze.py:219" in="main">if not a.results:         raise SystemExit( "--results PATH is required (or pass --self-test to validate the math on a f</m>
<m p="./bench/agentloop/analyze.py:226" in="">if __name__ == "__main__":     sys.exit( main() )</m>
<m p="./bench/agentloop/run_agentloop.py:85" in="load_tasks_lock">if lock.get( "schema" ) != "ripwire-agentloop-tasks-lock-v1":         raise SystemExit( f"{path}: unexpected schema {loc</m>
<m p="./bench/agentloop/run_agentloop.py:92" in="load_tasks_lock">if actual != expected:         raise SystemExit( f"{path}: content hash mismatch (expected {expected}, computed {actual}</m>
<m p="./bench/agentloop/run_agentloop.py:117" in="limit_tasks_repo_round_robin">if not limit or limit &gt;= len( tasks ):         return list( tasks )</m>
<m p="./bench/agentloop/run_agentloop.py:129" in="limit_tasks_repo_round_robin">if row_index &lt; len( rows ):                 selected.append( rows[row_index] )                 added = True             </m>
<m p="./bench/agentloop/run_agentloop.py:132" in="limit_tasks_repo_round_robin">if len( selected ) == limit:                     break</m>
… [73 more display lines; full output is 16295 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --query="teleport pagerank" --top-k=5`

*Raw BM25 ranking (debug lens; --for is the real verb).*

`````
<!-- routed: subtoken+body BM25 (-for's default) — no strong name hit; broad query, plain rg may also win -->
<!-- ripwire v1 t=fn|method|cls|struct|iface|var|sec p=path layer=arch-layer(opt) n=name id=canonical(path::scope::name,when-scoped) k=rank c=call amb=ambiguous-calls(read-source) overloads=N-same-name-defs-merged-into-this-row(absent-if-1;shown=counts-them-individually,so-rows+sum(overloads-1)=shown) prov=scip(precise;else name-based) hdr:unresolved=call-name-defined-only-in-a-lang-incompatible-file (edges heuristic) r:est_tokens=hdr-copy(none-if-stable) -->
<!-- files=1081 symbols=8835 edges=10480 shown=5 est_tokens=589 ambiguous=3045 unresolved=1326 precise=3 skipped_oversize=14 order=important-first -->
<r est_tokens="589">
<f p="./src/main.cpp">
<s t="fn" n="churnRankedGraph" amb="2" k="15.8212">
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
<s t="fn" n="churnPriorFromFreq" id="./src/gitmine.h::rw::churnPriorFromFreq" k="13.2020">
<c n="size"/>
</s>
</f>
<f p="./src/graph.h">
<s t="fn" n="rankGraphTeleport" id="./src/graph.h::rw::rankGraphTeleport" amb="5" k="12.2894">
<c n="biasPrior"/>
<c n="pageRankDouble"/>
<c n="size"/>
<c n="begin"/>
<c n="end"/>
<c n="begin"/>
<c n="end"/>
</s>
<s t="fn" n="rankGraph" id="./src/graph.h::rw::rankGraph" k="11.6888">
<c n="rankGraphTeleport"/>
<c n="size"/>
</s>
<s t="fn" n="diffTeleport" id="./src/graph.h::rw::diffTeleport" k="11.6326">
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
<!-- ripwire lens for "pagerank power iteration": reusable building blocks + quality facts for what you're about to touch (cx=complexity ccx=cognitive in=reuse-count churn=recent-commits amp=change-amplification clone=1(duplicated) tested=1) — prefer composing/reusing these; watch the high-churn/high-amp/cloned ones est_tokens="4448" -->
<sigs capped="1">
<f p="./scripts/optremarks.py">
<d l="40" n="HOT_FILES" cx="0" ccx="0" in="0" churn="1" amp="13">HOT_FILES = ( &quot;src/pagerank.cpp&quot;, # the power-iteration loop — G2&apos;s no-allocation scope &quot;src/infra/radixSort.h&quot;, # LSD radix entry points &quot;src/infra/radixSort…</d>
</f>
<f p="./src/pagerank.cpp">
<d l="36" n="pageRankDouble" id="./src/pagerank.cpp::rw::pageRankDouble" cx="18" ccx="33" in="1" churn="4" amp="8">unsigned pageRankDouble( const sparseCsr&lt;float&gt;&amp; inEdges, std::span&lt;const double&gt; weightedOutDegree, std::span&lt;const double&gt; teleport, std::span&lt;double&gt; rank … [line truncated: 10 more bytes on this line]
</f>
<f p="./src/graph.h">
<d l="1738" n="rankGraphTeleport" id="./src/graph.h::rw::rankGraphTeleport" cx="5" ccx="8" in="6" churn="10" amp="41">
<doc>PageRank with an explicit teleport / personalization vector p (Σp = 1). The prior is name-quali…</doc>inline std::vector&lt;float&gt; rankGraphTeleport( const Graph&amp; g, const std::vector&lt;float&gt;&amp; p, float alpha = 0.85f )</d>
<d l="1793" n="hits" id="./src/graph.h::rw::hits" cx="9" ccx="16" in="1" churn="10" amp="36">inline std::pair&lt;std::vector&lt;float&gt;, std::vector&lt;float&gt;&gt; hits( const Graph&amp; g, float tol = 1e-6f, unsigned maxIter = 100 )</d>
<d l="3292" n="louvainLocalMoving" id="./src/graph.h::rw::louvainLocalMoving" cx="18" ccx="35" in="2" churn="10" amp="37">inline Communities louvainLocalMoving( const std::vector&lt;std::vector&lt;WEdge&gt;&gt;&amp; adj )</d>
</f>
<f p="./src/infra/dynamic_map.hpp" layer="infra">
<d l="471" n="leaf_node" id="./src/infra/dynamic_map.hpp::leaf_node::leaf_node" cx="0" ccx="0" in="0" churn="3" amp="10">struct alignas(16) leaf_node</d>
<d l="1163" n="values_begin" id="./src/infra/dynamic_map.hpp::dynamic_map::values_begin" cx="2" ccx="1" in="3" churn="3" amp="13" tested="1">value_iterator values_begin()</d>
<d l="1511" n="compact" id="./src/infra/dynamic_map.hpp::dynamic_map::compact" cx="28" ccx="49" in="0" churn="3" amp="10">void compact()</d>
<d l="2199" n="leftmost_leaf" id="./src/infra/dynamic_map.hpp::dynamic_map::leftmost_leaf" cx="2" ccx="1" in="7" churn="3" amp="17" tested="1" pure="1">
<doc>iteration helpers</doc>handle_t leftmost_leaf() const</d>
</f>
<f p="./src/serialize.h">
<d l="993" n="MapAnnotations" id="./src/serialize.h::MapAnnotations::MapAnnotations" cx="0" ccx="0" in="0" churn="20" amp="47">struct MapAnnotations</d>
<d l="1063" n="rankByLegendFor" id="./src/serialize.h::rw::rankByLegendFor" cx="4" ccx="4" in="1" churn="20" amp="48">inline const char* rankByLegendFor( const char* label ) noexcept</d>
<d l="4845" n="writeJsonMapStamp" id="./src/serialize.h::rw::writeJsonMapStamp" cx="10" ccx="12" in="1" churn="20" amp="48">inline void writeJsonMapStamp( JsonWriter&amp; w, std::string&amp; esc, const MapAnnotations* ann )</d>
</f>
<f p="./src/pagerank.h">
<d l="11" n="PageRankConfig" id="./src/pagerank.h::PageRankConfig::PageRankConfig" cx="0" ccx="0" in="0" churn="3" amp="7">struct PageRankConfig</d>
</f>
… [160 more display lines; full output is 13136 bytes on 110 raw line(s)]
`````

## `./build/ripwire . --pack-signatures --top-k=10`

*Body-elided decl skeletons — recounted on this corpus. Measured as element bytes: the <d> signature+doc elements --pack-signatures emits, against the SAME symbols' full <b> bodies from --expand, with the CORPUS-ROOT PREFIX SUBTRACTED FROM BOTH SIDES. That subtraction is the whole methodology and the figure is meaningless without it: the root repeats inside every element's id= and p=, it is not what this verb elides, and counting it makes the headline a function of how deep the checkout happens to sit on disk — on one corpus, three spellings of the same root read 18.6 points apart before the subtraction and agree exactly after it. Root-neutralised on THIS repo: 48.3% fewer bytes at top-10, 62.9% at top-50, 60.8% at top-100. top-50 is the number to quote, because the sigs payload is top-50 regardless of --top-k and is therefore what THIS command emits. '~70%' is reachable at larger N but overstates the smaller shapes people actually run, and like the --format=columnar sibling below, a single small/trivial body can invert it (signature+doc bigger than the body). test/showcasecapturecheck.sh (C) re-derives all three from this repo every run, in the same quantity, and fails if the caption and the recount drift apart.*

`````
<ctx>
<!-- ripwire v1 t=fn|method|cls|struct|iface|var|sec p=path layer=arch-layer(opt) n=name id=canonical(path::scope::name,when-scoped) k=rank c=call amb=ambiguous-calls(read-source) overloads=N-same-name-defs-merged-into-this-row(absent-if-1;shown=counts-them-individually,so-rows+sum(overloads-1)=shown) prov=scip(precise;else name-based) hdr:unresolved=call-name-defined-only-in-a-lang-incompatible-file (edges heuristic) r:est_tokens=hdr-copy(none-if-stable) -->
<!-- files=1081 symbols=8835 edges=10480 shown=10 est_tokens=4436 ambiguous=3045 unresolved=1326 precise=3 skipped_oversize=14 order=important-first -->
<r est_tokens="4436">
<f p="./src/svector.h">
<s t="method" n="size" id="./src/svector.h::svector::size" k="0.0433">
</s>
<s t="method" n="push_back" id="./src/svector.h::svector::push_back" amb="2" k="0.0121">
<c n="buf"/>
<c n="buf"/>
<c n="grow"/>
</s>
<s t="method" n="buf" id="./src/svector.h::svector::buf" overloads="2" k="0.0110">
</s>
<s t="method" n="grow" id="./src/svector.h::svector::grow" amb="1" k="0.0065">
<c n="buf"/>
<c n="buf"/>
</s>
<s t="method" n="end" id="./src/svector.h::svector::end" overloads="2" amb="1" k="0.0040">
<c n="buf"/>
<c n="buf"/>
</s>
</f>
<f p="./src/scipoverlay.h">
<s t="method" n="empty" id="./src/scipoverlay.h::ScipOverlay::empty" k="0.0113">
</s>
</f>
<f p="./src/notes.h">
<s t="method" n="empty" id="./src/notes.h::NoteIndex::empty" k="0.0074">
</s>
… [124 more display lines; full output is 11093 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --outline=rankGraphTeleport --top-k=0`

*Control-flow skeleton of one symbol, payload-only via the new --top-k=0.*

`````
<ctx><outline><o t="fn" l="1738" p="./src/graph.h" n="rankGraphTeleport"><![CDATA[inline std::vector<float> rankGraphTeleport( const Graph& g, const std::vector<float>& p, float alpha = 0.85f )
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
<ctx><outline><o t="fn" l="1738" p="./src/graph.h" n="rankGraphTeleport"><![CDATA[inline std::vector<float> rankGraphTeleport( const Graph& g, const std::vector<float>& p, float alpha = 0.85f )
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
<ctx><bodies shown="1" total="1" capped="0"><b t="fn" l="1738" p="./src/graph.h" n="rankGraphTeleport"><![CDATA[inline std::vector<float> rankGraphTeleport( const Graph& g, const std::vector<float>& p, float alpha = 0.85f )
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
        {
            teleportMass += value;
        }
        if( teleportMass > 0.0 )
        {
            const double inverseMass = 1.0 / teleportMass;
            for( double& value : teleport )
            {
                value *= inverseMass;
            }
        }
        pageRankDouble( g.inEdges, g.wOutDeg, teleport, rankDouble, PageRankConfig{ .alpha = double( alpha ) } );
    }
    std::vector<float> r( N, 0.f );
    std::transform( rankDouble.begin(), rankDouble.end(), r.begin(), []( double value ) { return float( value ); } );
    return r;
}]]><calls total="7"><c n="biasPrior" l="1714">inline std::vector&lt;float&gt; biasPrior( const Graph&amp; g, const std::vector&lt;float&gt;&amp; p )</c><c n="pageRankDouble" l="36">unsigned pageRankDouble( const sparseCsr&lt;float&gt;&amp; inEdges, std::span&lt;const double&gt; weightedOutDegree, s … [line truncated: 374 more bytes on this line]
`````

## `./build/ripwire . --expand=rankGraphTeleport:1-12 --top-k=0`

*Body SLICE: lines 1..12 of the symbol's own body, with lines="lo-hi/total" marking it partial.*

`````
<ctx><bodies shown="1" total="1" capped="0"><b t="fn" l="1738" p="./src/graph.h" n="rankGraphTeleport" lines="1-12/28"><![CDATA[inline std::vector<float> rankGraphTeleport( const Graph& g, const std::vector<float>& p, float alpha = 0.85f )
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
        {]]><calls total="7"><c n="biasPrior" l="1714">inline std::vector&lt;float&gt; biasPrior( const Graph&amp; g, const std::vector&lt;float&gt;&amp; p )</c><c n="pageRankDouble" l="36">unsigned pageRankDouble( const sparseCsr&lt;float&gt;&amp; inEdges, std::span&lt;const double&gt; weightedOutD … [line truncated: 382 more bytes on this line]
`````

## `./build/ripwire . --expand=compressBody --top-k=0 --compress`

*Comments stripped + blank runs collapsed — compressBody is the function that implements --compress itself, chosen because it is comment-heavy enough to show a real reduction (the previously captioned symbol had no comments or blank runs, so before/after were byte-identical under a caption promising a difference).*

`````
<ctx><bodies shown="1" total="1" capped="0"><b t="fn" l="2078" p="./src/serialize.h" n="compressBody"><![CDATA[inline std::string compressBody( std::string_view src )
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
                while( j < N && src[j] != '(' && src[j] != '\n' )
                {
                    delim += src[j++];
                }
                if( j < N && src[j] == '(' )
                {

… [165 more lines, 4666 bytes total]
`````

## `./build/ripwire . --expand=readAckRecords --top-k=0 --no-redact`

*--no-redact: emit bodies verbatim (credential redaction is on by default).*

`````
<ctx><bodies shown="1" total="1" capped="0"><b t="fn" l="2647" p="./src/quality.h" n="readAckRecords"><![CDATA[inline gtl::btree_map<std::string, AckRecord> readAckRecords( const std::string& path )
{
    gtl::btree_map<std::string, AckRecord> out;
    std::ifstream f( path );
    if( !f )
    {
        return out;
    }
    std::string line;
    while( std::getline( f, line ) )
    {
        while( !line.empty() && ( line.back() == '\r' || line.back() == '\n' ) )
        {
            line.pop_back(); // CRLF tolerance (merged-in Windows checkout)
        }
        if( line.empty() || line[0] == '#' )
        {
            continue;
        }
        std::istringstream is( line );
        std::string tag, kind;
        std::uint64_t key = 0;
        std::uint32_t ackNow = 0;
        is >> tag >> kind >> std::hex >> key >> std::dec >> ackNow;
        if( tag != "ack" || is.fail() ) { DEGRADED_PATH_ALERT( "quality: malformed ack line skipped" ); continue; }
        kind = normalizeLegacyAckKind( kind, ackNow );               // P0.3 migration — see the note at ackKindToken
        std::string reason;
        std::getline( is, reason );
        while( !reason.empty() && reason.front() == ' ' )
        {
… [16 more lines, 2402 bytes total]
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
… [1202 more lines, 65709 bytes total]
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
<!-- metrics: in=fan-in out=fan-out cx=cyclomatic ccx=cognitive loc=lines params=count nest=MAX-depth humps=regions-reaching-the-nesting-bar deep=lines-inside-them(floor,see deep_floor) (humps/deep are the PROFILE nest= cannot give: nest= is a max, so one deep line and a body that is deep throughout report the same number; deep/loc is the fraction. Both absent exactly when nest<bar — not-deep, never a hidden 0. deep counts LINES and humps counts REGIONS, and two regions can share a line, so deep BELOW humps is legal: a one-line if/else at the bar is 2 regions on 1 line) locals=local-var-decl-count(floor,C/C++-only,see locals_floor) ppalt=preproc-alternative-branches-in-body(#else/#elif; metrics sum ALL branches, no single build compiles them all) ev=essential-cx(McCabe: 1=fully structured, 2+=jumps block extract-method; absent on a cx row means exactly 1; floor per ev_floor — noreturn calls/macro-hidden exits unseen; not counted: &&/||, Rust ? and yield/await/defer, hence Bash carries no ev) ev_why=which-jumps-raised-it tag:count cbo=coupling lcom4=cohesion amp=change-amplification tested=1 role=hub(fan-in 8+; uses spells role call|read|write|import|extends). Absent=N/A, never 0. -->
<!-- files=1081 symbols=8835 edges=10480 shown=10 est_tokens=1517 ambiguous=3045 unresolved=1326 precise=3 skipped_oversize=14 order=important-first -->
<r est_tokens="1517">
<f p="./src/svector.h">
<s t="method" n="size" id="./src/svector.h::svector::size" in="928" out="0" cx="1" ccx="0" role="hub" loc="1" params="0" nest="0" locals="0" locals_floor="1" cbo="0" amp="928" tested="1" k="0.0433">
</s>
<s t="method" n="push_back" id="./src/svector.h::svector::push_back" in="448" out="3" cx="2" ccx="1" role="hub" loc="1" params="1" nest="1" locals="1" locals_floor="1" cbo="3" amp="448" tested="1" amb="2" k="0.0121" ev="2" ev_floor="1" ev_why="guard-return:1">
<c n="buf"/>
<c n="buf"/>
<c n="grow"/>
</s>
<s t="method" n="buf" id="./src/svector.h::svector::buf" overloads="2" in="8" out="0" cx="2" ccx="1" role="hub" loc="1" params="0" nest="1" locals="0" locals_floor="1" cbo="0" amp="8" tested="1" k="0.0110">
</s>
<s t="method" n="grow" id="./src/svector.h::svector::grow" in="2" out="2" cx="3" ccx="2" loc="14" params="1" nest="1" locals="2" locals_floor="1" cbo="2" amp="2" tested="1" amb="1" k="0.0065">
<c n="buf"/>
<c n="buf"/>
</s>
<s t="method" n="end" id="./src/svector.h::svector::end" overloads="2" in="313" out="2" cx="1" ccx="0" role="hub" loc="1" params="0" nest="0" locals="0" locals_floor="1" cbo="2" amp="313" tested="1" amb="1" k="0.0040">
<c n="buf"/>
<c n="buf"/>
</s>
</f>
<f p="./src/scipoverlay.h">
<s t="method" n="empty" id="./src/scipoverlay.h::ScipOverlay::empty" in="483" out="0" cx="1" ccx="0" role="hub" loc="1" params="0" nest="0" locals="0" locals_floor="1" cbo="0" amp="483" tested="1" k="0.0113">
</s>
</f>
<f p="./src/notes.h">
<s t="method" n="empty" id="./src/notes.h::NoteIndex::empty" in="404" out="0" cx="1" ccx="0" role="hub" loc="1" params="0" nest="0" locals="0" locals_floor="1" cbo="0" amp="414" tested="1" k="0.0074">
</s>
</f>
<f p="./src/infra/platform.h" layer="infra">
<s t="fn" n="max" id="./src/infra/platform.h::fastmath::max" in="47" out="0" cx="2" ccx="1" role="hub" loc="1" params="2" nest="1" locals="0" locals_floor="1" cbo="0" amp="53" tested="1" k="0.0035">
</s>
</f>
</r>
`````

## `./build/ripwire . --deps`

*File->file dependency graph (god-files, cycles).*

`````
<!-- ripwire deps: file-to-file #include/import view, heaviest transitive cone first. files= (root) = files with at least one dependency edge (this listing's own denominator); health files= = the whole indexed corpus; health dep_files= = the dependency-CAPABLE subset of it (the ccd/acd/nccd denominator). raise the default cap with limit=N (offset=M pages). -->
<deps files="259" shown="40" capped="1">
<health files="1081" dep_files="495" ccd="2250" acd="4.5" nccd="0.57" shape="horizontal"/>
<godfiles total="162" shown="12" capped="1">
<f p="./src/model.h" afferent="66"/>
<f p="./src/serialize.h" afferent="31"/>
<f p="./src/graph.h" afferent="28"/>
<f p="./src/ingest.h" afferent="20"/>
<f p="./src/arch.h" afferent="18"/>
<f p="./src/jsonesc.h" afferent="15"/>
<f p="./src/quality.h" afferent="15"/>
<f p="./src/pageview.h" afferent="12"/>
<f p="./src/docparse.h" afferent="11"/>
<f p="./src/filter.h" afferent="11"/>
<f p="./src/gitstamp.h" afferent="11"/>
<f p="./src/hashutil.h" afferent="11"/>
</godfiles>
<stabledeps violations="12">
<v from="./src/mcp.h" to="./src/mcpverbs.h" gap="0.38"/>
<v from="./src/gitstamp.h" to="./src/quality.h" gap="0.26"/>
<v from="./test/cyclecutfix/b.h" to="./test/cyclecutfix/c.h" gap="0.25"/>
<v from="./test/cyclecutfix/c.h" to="./test/cyclecutfix/a.h" gap="0.25"/>
<v from="./src/serialize.h" to="./src/notes.h" gap="0.20"/>
<v from="./src/mcpedit.h" to="./src/mcpindex.h" gap="0.20"/>
<v from="./src/partition.h" to="./src/packtask.h" gap="0.20"/>
<v from="./src/situ.h" to="./src/prcontext.h" gap="0.13"/>
<v from="./src/mcp.h" to="./src/mcpedit.h" gap="0.10"/>
<v from="./src/graph.h" to="./src/scipoverlay.h" gap="0.09"/>
<v from="./src/mention.h" to="./src/graph.h" gap="0.09"/>
<v from="./src/mcpserver.h" to="./src/mcp.h" gap="0.07"/>
… [736 more display lines; full output is 18098 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --hotspots`

*Complexity x recent git churn (maintenance pain).*

`````
<!-- ripwire hotspots: maintenance-pain = complexity × recent churn (window=12mo). churn=commits touching the file; ccx=Σ cognitive complexity; score=churn×ccx; top=worst function. files= is the DENOMINATOR ranked= is drawn from, and a hotspot needs both factors nonzero, so ranked= + unranked_no_churn= + unranked_no_complexity= = files= exactly. unranked_no_complexity= is a file with commits but no function or method to score (a pure declaration header, markdown, config). unranked_no_churn= is a file no in-window commit was attributed to — and it CONFLATES two cases this verb cannot tell apart: a genuinely quiet file, and one whose path the git-to-index join never bound (a rename, an exclusion, or a spelling the join could not match), which scores zero for a reason that is not about the file. Treat it as an upper bound on quietness, not a measure of it. raise the default cap with limit=N (offset=M pages) -->
<!-- at= is the git commit these numbers were computed at; a trailing +dirty means the working tree differed from that commit, so the numbers describe the tree, not the commit -->
<hotspots window="12mo" files="1081" ranked="291" unranked_no_churn="0" unranked_no_complexity="790" shown="40" capped="1" at="33f9f7be2">
<f p="./src/main.cpp" churn="65" ccx="3487" score="226655" top="main" top_ccx="381" top_l="10992"/>
<f p="./src/ingest.cpp" churn="43" ccx="3201" score="137643" top="ingest" top_ccx="687" top_l="6632"/>
<f p="./src/serialize.h" churn="20" ccx="1583" score="31660" top="packSignatures" top_ccx="197" top_l="2475"/>
<f p="./src/quality.h" churn="24" ccx="707" score="16968" top="computeDelta" top_ccx="236" top_l="2747"/>
<f p="./src/cli.h" churn="45" ccx="350" score="15750" top="parseArgs" top_ccx="154" top_l="2888"/>
<f p="./src/graph.h" churn="10" ccx="1406" score="14060" top="buildGraph" top_ccx="698" top_l="462"/>
<f p="./src/mcpverbs.h" churn="9" ccx="681" score="6129" top="runBatchSub" top_ccx="98" top_l="2840"/>
<f p="./src/layout.h" churn="7" ccx="690" score="4830" top="writeLayout" top_ccx="31" top_l="2516"/>
<f p="./src/lexical.h" churn="10" ccx="391" score="3910" top="lexicalScoresTiered" top_ccx="239" top_l="100"/>
<f p="./src/mcp.h" churn="8" ccx="454" score="3632" top="dispatchMcpLine" top_ccx="422" top_l="333"/>
<f p="./src/search.h" churn="8" ccx="425" score="3400" top="grepCollect" top_ccx="49" top_l="1328"/>
<f p="./src/naminglens.h" churn="9" ccx="373" score="3357" top="checkScopeGroups" top_ccx="93" top_l="904"/>
<f p="./src/docdrift.h" churn="6" ccx="543" score="3258" top="parseIntLiteral" top_ccx="34" top_l="361"/>
<f p="./src/gitmine.h" churn="6" ccx="521" score="3126" top="applyCoChangeBoost" top_ccx="93" top_l="2230"/>
<f p="./src/resolve.h" churn="5" ccx="462" score="2310" top="buildPreciseIncludeAdj" top_ccx="56" top_l="1064"/>
<f p="./src/skilleval.h" churn="7" ccx="313" score="2191" top="runEvalSkills" top_ccx="97" top_l="649"/>
<f p="./src/mcpindex.h" churn="11" ccx="188" score="2068" top="getIndex" top_ccx="37" top_l="913"/>
<f p="./src/crossref.h" churn="5" ccx="409" score="2045" top="streamBlobs" top_ccx="38" top_l="442"/>
<f p="./src/eval.h" churn="6" ccx="302" score="1812" top="runEval" top_ccx="66" top_l="168"/>
<f p="./src/infra/profileScope.h" churn="9" ccx="194" score="1746" top="report" top_ccx="44" top_l="1151"/>
<f p="./src/clones.h" churn="7" ccx="245" score="1715" top="findClonesType3" top_ccx="118" top_l="599"/>
<f p="./src/arch.h" churn="6" ccx="262" score="1572" top="computeModuleMetrics" top_ccx="68" top_l="721"/>
<f p="./src/darkflags.h" churn="5" ccx="295" score="1475" top="computeFlags" top_ccx="40" top_l="911"/>
<f p="./src/flipimpact.h" churn="5" ccx="271" score="1355" top="scanBindingUses" top_ccx="31" top_l="569"/>
<f p="./src/mention.h" churn="6" ccx="220" score="1320" top="applyMentionBoost" top_ccx="77" top_l="294"/>
<f p="./src/lanes.h" churn="5" ccx="240" score="1200" top="warnCoincidingClaims" top_ccx="24" top_l="686"/>
<f p="./src/skillscan.h" churn="5" ccx="233" score="1165" top="scanSkillText" top_ccx="150" top_l="401"/>
… [14 more display lines; full output is 5422 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --clones`

*Token-normalized duplicate bodies.*

`````
<!-- ripwire clones: function bodies with similar normalized token streams (identifiers/literals normalized, so renamed copies match). type=2 exact/renamed (Type-1/2); type=3 gapped near-miss (an inserted/changed statement, similarity in [0.80,1.0)). Reuse don't reimplement; a fix to one likely belongs in all. groups= and type3= are the two GROUP-TYPE totals (each capped independently, so neither is the row count); total= is the true row total (groups + type3-group-count) and is ALWAYS present, paged or not; shown= is the number of group rows that follow this run. capped="1" means rows were dropped. exempt= on a group ⇒ every member is on a path the quality-delta verb's duplication kind deliberately ignores (fixture dirs / shell test-runners repeat boilerplate by convention) — a fact here, never a gate there; exempt_groups= counts them over ALL groups. raise the default cap with limit=N (offset=M pages). -->
<clones groups="53" type3="197" total="250" exempt_groups="92" shown="80" capped="1">
<group type="2" tokens="207" n="4" exempt="shell-runner">
<f n="batch_sub" p="./test/mcpclidiffcheck.sh:63"/>
<f n="batch_sub" p="./test/mcptranchecheck.sh:55"/>
<f n="batch_sub" p="./test/mcpw2fixcheck.sh:52"/>
<f n="batch_sub" p="./test/mcpw3fixcheck.sh:51"/>
</group>
<group type="2" tokens="149" n="3" exempt="shell-runner">
<f n="monotonic_check" p="./test/pyimportprecisecheck.sh:89"/>
<f n="monotonic_check" p="./test/rustimportprecisecheck.sh:124"/>
<f n="monotonic_check" p="./test/tsimportprecisecheck.sh:88"/>
</group>
<group type="2" tokens="142" n="2">
<f n="test_tier2_accept_big_quality_small_cost" p="./bench/locbench/test_compare_gate.py:130"/>
<f n="test_tier2_reject_small_quality_big_cost" p="./bench/locbench/test_compare_gate.py:143"/>
</group>
<group type="2" tokens="126" n="2">
<f n="addWholeFileFn" p="./test/cloneband_harness.cpp:64"/>
<f n="addWholeFileFn" p="./test/type3clone_harness.cpp:47"/>
</group>
<group type="2" tokens="118" n="2">
<f n="rankFiles" p="./src/eval.h:53"/>
<f n="rankCandidates" p="./src/skilleval.h:426"/>
</group>
<group type="2" tokens="114" n="2">
<f n="timer" p="./bench/representative_perfgate.sh:54"/>
<f n="run_once_ms" p="./test/mergescoutcheck.sh:268"/>
</group>
<group type="2" tokens="112" n="2">
… [306 more display lines; full output is 15187 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --cochange`

*Files that change together in git (hidden coupling).*

`````
<!-- ripwire cochange: file pairs that change together in git but share no transitive static dependency (surprising=1) = hidden coupling. together= is the number of commits in window= that touched BOTH files (3 or more, or the pair is not reported); deg= is that count over the commit count of the LESS-CHANGED of the two files, so 1.00 means the quieter file never changed without the other. conf_ab= is that same fraction over a='s OWN commit count and conf_ba= over b='s, which is the asymmetric form: conf_ab=1.00 means a never changed without b. deg= is by construction the larger of the two, and driver= names which side it came from ("a" or "b") — the file whose changes most reliably imply the other's, and therefore the one to look at first. driver= is OMITTED when the two directions are equal, because a tie is not a finding. recur= is how many of sub_windows= the pair actually co-changed in: the mined window is cut into that many equal-COMMIT-COUNT slices (not equal time — a calendar slice can hold 400 commits or 4), so recur=1 at any together= is one burst of activity and not a persistent coupling, which is the distinction a single window cannot make. sub_windows= is the denominator and is never omitted; it is smaller than the nominal 3 only when the window holds fewer commits than that. min_recur= appears when cochange-recur=K (the flag) filtered the rows, so a short list is explained rather than silent. window= is the mining window: the default 18 months, or the since=REV|DATE value when one resolved. surprising= is only defined where BOTH sides could carry a static dependency at all (the same dependency-capable predicate deps <health dep_files=> uses: source languages yes; sh, md, json, ruby and binary/unknown files no). A pair with a dep-incapable side keeps its row and carries dep_capable=0 instead, because for it "shares no static dependency" is vacuously true. raise the default cap with limit=N (offset=M pages) -->
<!-- at= is the git commit these numbers were computed at; a trailing +dirty means the working tree differed from that commit, so the numbers describe the tree, not the commit -->
<cochange pairs="171" window="18mo" sub_windows="3" shown="30" capped="1" at="33f9f7be2">
<pair a="./src/cli.h" b="./src/mcp.h" together="3" deg="1.00" conf_ab="0.07" conf_ba="1.00" driver="b" recur="1" surprising="1"/>
<pair a="./src/cli.h" b="./src/graph.h" together="4" deg="0.80" conf_ab="0.10" conf_ba="0.80" driver="b" recur="2" surprising="1"/>
<pair a="./present/deck5_ripwire_build.js" b="./src/cli.h" together="17" deg="0.74" conf_ab="0.74" conf_ba="0.41" driver="a" recur="2" surprising="1"/>
<pair a="./present/deck5_ripwire_build.js" b="./src/main.cpp" together="17" deg="0.74" conf_ab="0.74" conf_ba="0.28" driver="a" recur="2" surprising="1"/>
<pair a="./src/ingest.cpp" b="./src/serialize.h" together="10" deg="0.62" conf_ab="0.26" conf_ba="0.62" driver="b" recur="2" surprising="1"/>
<pair a="./src/cli.h" b="./src/mcpverbs.h" together="3" deg="0.60" conf_ab="0.07" conf_ba="0.60" driver="b" recur="1" surprising="1"/>
<pair a="./src/cli.h" b="./src/serialize.h" together="8" deg="0.50" conf_ab="0.20" conf_ba="0.50" driver="b" recur="3" surprising="1"/>
<pair a="./src/quality.h" b="./src/serialize.h" together="6" deg="0.38" conf_ab="0.32" conf_ba="0.38" driver="b" recur="2" surprising="1"/>
<pair a="./src/ingest.cpp" b="./src/naminglens.h" together="3" deg="0.33" conf_ab="0.08" conf_ba="0.33" driver="b" recur="2" surprising="1"/>
<pair a="./src/ingest.cpp" b="./src/main.cpp" together="10" deg="0.26" conf_ab="0.26" conf_ba="0.17" driver="a" recur="3" surprising="1"/>
<pair a="./src/cli.h" b="./test/showcase_capture.py" together="3" deg="0.25" conf_ab="0.07" conf_ba="0.25" driver="b" recur="2" surprising="1"/>
<pair a="./src/cli.h" b="./src/ingest.cpp" together="9" deg="0.24" conf_ab="0.22" conf_ba="0.24" driver="b" recur="3" surprising="1"/>
<pair a="./src/cli.h" b="./src/quality.h" together="4" deg="0.21" conf_ab="0.10" conf_ba="0.21" driver="b" recur="2" surprising="1"/>
<pair a="./present/deck5_ripwire_build.js" b="./src/model.h" together="3" deg="0.17" conf_ab="0.13" conf_ba="0.17" driver="b" recur="2" surprising="1"/>
<pair a="./src/ingest.cpp" b="./test/qschemetripcheck.sh" together="8" deg="1.00" conf_ab="0.21" conf_ba="1.00" driver="b" recur="1" dep_capable="0"/>
<pair a="./src/quality.h" b="./test/qschemetripcheck.sh" together="8" deg="1.00" conf_ab="0.42" conf_ba="1.00" driver="b" recur="1" dep_capable="0"/>
<pair a="./src/ingest.cpp" b="./src/ingest.h" together="5" deg="1.00" conf_ab="0.13" conf_ba="1.00" driver="b" recur="3"/>
<pair a="./src/main.cpp" b="./src/mcpverbs.h" together="5" deg="1.00" conf_ab="0.08" conf_ba="1.00" driver="b" recur="2"/>
<pair a="./docs/EVALS.md" b="./test/legendcoveragecheck.sh" together="4" deg="1.00" conf_ab="0.05" conf_ba="1.00" driver="b" recur="1" dep_capable="0"/>
<pair a="./docs/COMMANDS.md" b="./test/legendcoveragecheck.sh" together="4" deg="1.00" conf_ab="0.09" conf_ba="1.00" driver="b" recur="1" dep_capable="0"/>
<pair a="./test/cppqualcheck.sh" b="./test/regression.sh" together="4" deg="1.00" conf_ab="1.00" conf_ba="0.07" driver="a" recur="2" dep_capable="0"/>
<pair a="./src/main.cpp" b="./test/cppqualcheck.sh" together="4" deg="1.00" conf_ab="0.07" conf_ba="1.00" driver="b" recur="2" dep_capable="0"/>
<pair a="./skills/ripwire-fresh-eyes/SKILL.md" b="./test/legendcoveragecheck.sh" together="4" deg="1.00" conf_ab="0.20" conf_ba="1.00" driver="b" recur="1" dep_capable="0"/>
<pair a="./src/cli.h" b="./test/cppqualcheck.sh" together="4" deg="1.00" conf_ab="0.10" conf_ba="1.00" driver="b" recur="2" dep_capable="0"/>
<pair a="./README.md" b="./test/legendcoveragecheck.sh" together="4" deg="1.00" conf_ab="0.04" conf_ba="1.00" driver="b" recur="1" dep_capable="0"/>
<pair a="./src/qualitypanel.h" b="./test/qualitypanelcheck.sh" together="4" deg="1.00" conf_ab="0.80" conf_ba="1.00" driver="b" recur="2" dep_capable="0"/>
<pair a="./docs/EVALS.md" b="./test/cppqualcheck.sh" together="4" deg="1.00" conf_ab="0.05" conf_ba="1.00" driver="b" recur="2" dep_capable="0"/>
<pair a="./src/cli.h" b="./test/legendcoveragecheck.sh" together="4" deg="1.00" conf_ab="0.10" conf_ba="1.00" driver="b" recur="1" dep_capable="0"/>
<pair a="./src/main.cpp" b="./test/legendcoveragecheck.sh" together="4" deg="1.00" conf_ab="0.07" conf_ba="1.00" driver="b" recur="1" dep_capable="0"/>
<pair a="./test/legendcoveragecheck.sh" b="./test/regression.sh" together="4" deg="1.00" conf_ab="1.00" conf_ba="0.07" driver="a" recur="1" dep_capable="0"/>
</cochange>
`````

## `./build/ripwire . --hotspots --since="2 weeks ago"`

*Hotspots scoped to RECENT churn (the regression lens).*

`````
<!-- ripwire hotspots: maintenance-pain = complexity × recent churn (window=2 weeks ago). churn=commits touching the file; ccx=Σ cognitive complexity; score=churn×ccx; top=worst function. files= is the DENOMINATOR ranked= is drawn from, and a hotspot needs both factors nonzero, so ranked= + unranked_no_churn= + unranked_no_complexity= = files= exactly. unranked_no_complexity= is a file with commits but no function or method to score (a pure declaration header, markdown, config). unranked_no_churn= is a file no in-window commit was attributed to — and it CONFLATES two cases this verb cannot tell apart: a genuinely quiet file, and one whose path the git-to-index join never bound (a rename, an exclusion, or a spelling the join could not match), which scores zero for a reason that is not about the file. Treat it as an upper bound on quietness, not a measure of it. raise the default cap with limit=N (offset=M pages) -->
<!-- at= is the git commit these numbers were computed at; a trailing +dirty means the working tree differed from that commit, so the numbers describe the tree, not the commit -->
<hotspots window="2 weeks ago" files="1081" ranked="291" unranked_no_churn="0" unranked_no_complexity="790" shown="40" capped="1" at="33f9f7be2">
<f p="./src/main.cpp" churn="65" ccx="3487" score="226655" top="main" top_ccx="381" top_l="10992"/>
<f p="./src/ingest.cpp" churn="43" ccx="3201" score="137643" top="ingest" top_ccx="687" top_l="6632"/>
<f p="./src/serialize.h" churn="20" ccx="1583" score="31660" top="packSignatures" top_ccx="197" top_l="2475"/>
<f p="./src/quality.h" churn="24" ccx="707" score="16968" top="computeDelta" top_ccx="236" top_l="2747"/>
<f p="./src/cli.h" churn="45" ccx="350" score="15750" top="parseArgs" top_ccx="154" top_l="2888"/>
<f p="./src/graph.h" churn="10" ccx="1406" score="14060" top="buildGraph" top_ccx="698" top_l="462"/>
<f p="./src/mcpverbs.h" churn="9" ccx="681" score="6129" top="runBatchSub" top_ccx="98" top_l="2840"/>
<f p="./src/layout.h" churn="7" ccx="690" score="4830" top="writeLayout" top_ccx="31" top_l="2516"/>
<f p="./src/lexical.h" churn="10" ccx="391" score="3910" top="lexicalScoresTiered" top_ccx="239" top_l="100"/>
<f p="./src/mcp.h" churn="8" ccx="454" score="3632" top="dispatchMcpLine" top_ccx="422" top_l="333"/>
<f p="./src/search.h" churn="8" ccx="425" score="3400" top="grepCollect" top_ccx="49" top_l="1328"/>
<f p="./src/naminglens.h" churn="9" ccx="373" score="3357" top="checkScopeGroups" top_ccx="93" top_l="904"/>
<f p="./src/docdrift.h" churn="6" ccx="543" score="3258" top="parseIntLiteral" top_ccx="34" top_l="361"/>
<f p="./src/gitmine.h" churn="6" ccx="521" score="3126" top="applyCoChangeBoost" top_ccx="93" top_l="2230"/>
<f p="./src/resolve.h" churn="5" ccx="462" score="2310" top="buildPreciseIncludeAdj" top_ccx="56" top_l="1064"/>
<f p="./src/skilleval.h" churn="7" ccx="313" score="2191" top="runEvalSkills" top_ccx="97" top_l="649"/>
<f p="./src/mcpindex.h" churn="11" ccx="188" score="2068" top="getIndex" top_ccx="37" top_l="913"/>
<f p="./src/crossref.h" churn="5" ccx="409" score="2045" top="streamBlobs" top_ccx="38" top_l="442"/>
<f p="./src/eval.h" churn="6" ccx="302" score="1812" top="runEval" top_ccx="66" top_l="168"/>
<f p="./src/infra/profileScope.h" churn="9" ccx="194" score="1746" top="report" top_ccx="44" top_l="1151"/>
<f p="./src/clones.h" churn="7" ccx="245" score="1715" top="findClonesType3" top_ccx="118" top_l="599"/>
<f p="./src/arch.h" churn="6" ccx="262" score="1572" top="computeModuleMetrics" top_ccx="68" top_l="721"/>
<f p="./src/darkflags.h" churn="5" ccx="295" score="1475" top="computeFlags" top_ccx="40" top_l="911"/>
<f p="./src/flipimpact.h" churn="5" ccx="271" score="1355" top="scanBindingUses" top_ccx="31" top_l="569"/>
<f p="./src/mention.h" churn="6" ccx="220" score="1320" top="applyMentionBoost" top_ccx="77" top_l="294"/>
<f p="./src/lanes.h" churn="5" ccx="240" score="1200" top="warnCoincidingClaims" top_ccx="24" top_l="686"/>
<f p="./src/skillscan.h" churn="5" ccx="233" score="1165" top="scanSkillText" top_ccx="150" top_l="401"/>
… [14 more display lines; full output is 5436 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --arch=test/archfix/rules.txt`

*Enforce layering rules (exit 2 on violation) — run against the repo's own test fixture rules.*

`````
<!-- ripwire arch: layering fitness function — edges that violate your declared rules (layer rules and regex path-rules). exit=2 if any NEW (un-baselined) violation. <metrics> = descriptive Martin Ca/Ce/I/A/D + reachability, never gates. Rules — layer substrings and regex path-rules alike — are matched against each file's ROOT-RELATIVE path (src/core/x.cpp), never the absolute or ./-prefixed spelling shown in from=/to=, so a rule means the same thing whatever directory the tree was checked out into. -->
<arch layers="2" rules="1" pathRules="0" violations="0" baselined="0" new_violations="0">
<metrics modules="231" typed_modules="86" zone_pain="70" zone_useless="1" zone_ok="15" zone_na="145" propagation_cost="0.009" note="Martin Ca/Ce/I/A/D + zone (main-sequence heuristic, no independent outcome-based validation — folklore, not proof) + reachability — directory-level estimate from na … [line truncated: 408 more bytes on this line]
<m path="." ca="0" ce="0" types="0" abstract="0" I="0.00" A="0.00" D="1.00" zone="n/a" reachable="1" isolated="1"/>
<m path="./.codex-plugin" ca="0" ce="0" types="0" abstract="0" I="0.00" A="0.00" D="1.00" zone="n/a" reachable="1" isolated="1"/>
<m path="./bench" ca="0" ce="1" types="12" abstract="2" I="1.00" A="0.17" D="0.17" zone="ok" reachable="1"/>
<m path="./bench/agentloop" ca="0" ce="0" types="0" abstract="0" I="0.00" A="0.00" D="1.00" zone="n/a" reachable="1" isolated="1"/>
<m path="./bench/agentloop/results" ca="0" ce="0" types="0" abstract="0" I="0.00" A="0.00" D="1.00" zone="n/a" reachable="1" isolated="1"/>
<m path="./bench/cppbench" ca="0" ce="0" types="1" abstract="0" I="0.00" A="0.00" D="1.00" zone="pain" reachable="1" isolated="1"/>
<m path="./bench/cppbench/results" ca="0" ce="0" types="0" abstract="0" I="0.00" A="0.00" D="1.00" zone="n/a" reachable="1" isolated="1"/>
<m path="./bench/ensemblecal" ca="0" ce="0" types="0" abstract="0" I="0.00" A="0.00" D="1.00" zone="n/a" reachable="1" isolated="1"/>
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
<m path="./bench/headtohead/r2-2026-08-03" ca="0" ce="0" types="0" abstract="0" I="0.00" A="0.00" D="1.00" zone="n/a" reachable="1" isolated="1"/>
<m path="./bench/headtohead/r2-2026-08-03/results" ca="0" ce="0" types="0" abstract="0" I="0.00" A="0.00" D="1.00" zone="n/a" reachable="1" isolated="1"/>
<m path="./bench/headtohead/r3-headroom-2026-08-03" ca="0" ce="0" types="0" abstract="0" I="0.00" A="0.00" D="1.00" zone="n/a" reachable="1" isolated="1"/>
… [206 more display lines; full output is 32396 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --lint`

*Built-in AST checks (c-cast, goto, unsafe-c-fn, ...).*

`````
<!-- ripwire lint: [AST]-only checks (descriptive facts, not gates). rule=the check; sev=user-rule severity; in=enclosing symbol NAME (the same spelling is a fan-in COUNT in for/pack-task/exemplar). A rule named atom-X is an atom of confusion (Gopstein, FSE 2017): a C-family shape that misleads READERS, C/C++/ObjC/CUDA only. Each rule is scanned under its OWN match budget, so no rule is ever starved by a noisier one. A rule that spends its whole budget carries capped="1" — its count= is then a FLOOR (that rule's raw captures reached the per-rule budget; only its own matches can cap it); findings_capped="1" on the root ⇒ at least one rule is a floor. Absent = nothing was capped and every count= is a total. raise the default cap with limit=N (offset=M pages). -->
<lint findings="2839" findings_capped="1">
<rule name="c-style-cast" count="262"/>
<rule name="goto" count="2"/>
<rule name="do-while" count="2"/>
<rule name="unsafe-c-fn" count="0"/>
<rule name="weak-crypto" count="0"/>
<rule name="redundant-parens" count="0"/>
<rule name="suspicious-semicolon" count="0"/>
<rule name="typedef-over-using" count="12"/>
<rule name="magic-number" count="436" capped="1"/>
<rule name="empty-catch" count="1"/>
<rule name="self-assign" count="3"/>
<rule name="large-function" count="181"/>
<rule name="deep-nesting" count="184"/>
<rule name="inconsistent-return" count="1"/>
<rule name="unreachable-code" count="5"/>
<rule name="naming-short" count="862"/>
<rule name="naming-wordy" count="18"/>
<rule name="naming-series" count="199"/>
<rule name="naming-underscore" count="0"/>
<rule name="naming-case" count="43"/>
<rule name="naming-predicate" count="0"/>
<rule name="naming-setter" count="1"/>
<rule name="naming-confusable" count="95"/>
<rule name="naming-uninformative" count="0"/>
<rule name="atom-comma-operator" count="1"/>
<rule name="atom-embedded-crement" count="76"/>
<rule name="atom-assign-as-value" count="32"/>
<rule name="atom-nested-ternary" count="39"/>
… [2851 more display lines; full output is 326223 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --lint-rules=test/lintrulesfix/rules`

*User lint rules (YAML, ast-grep style) from a directory.*

`````
<!-- ripwire lint: [AST]-only checks (descriptive facts, not gates). rule=the check; sev=user-rule severity; in=enclosing symbol NAME (the same spelling is a fan-in COUNT in for/pack-task/exemplar). A rule named atom-X is an atom of confusion (Gopstein, FSE 2017): a C-family shape that misleads READERS, C/C++/ObjC/CUDA only. Each rule is scanned under its OWN match budget, so no rule is ever starved by a noisier one. A rule that spends its whole budget carries capped="1" — its count= is then a FLOOR (that rule's raw captures reached the per-rule budget; only its own matches can cap it); findings_capped="1" on the root ⇒ at least one rule is a floor. Absent = nothing was capped and every count= is a total. raise the default cap with limit=N (offset=M pages). -->
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
[math degraded] lint-rules: malformed rule file skipped  (lintrules.h:267, auto rw::parseLintRuleFile(const std::string &, std::string_view, std::vector<LintRule> &)::(anonymous class)::operator()(std::size_t, const char *) const — logged once per site)
ripwire: AST query did not compile for any grammar: (this_is_not_a_real_node @x @@@ ((( )
`````

## `./build/ripwire . --lint --with-profile=report.txt`

*Join MEASURED heat onto --lint findings — runs in a tiny fabricated demo corpus (one cache-pointer-chase-loop finding under a PROFILE_SCOPE site) because a real report needs a RIPWIRE_PROFILE build; the finding inside the profiled scope gains heat_* columns from the report's #PROF_TSV row.*

Input file:

`````
#PROF_TSV_BEGIN	one row per scope, aggregated across threads; counters are RAW integers
scope	file	line	calls	total_ms	l1d_mpki
walk: chase pass	x.cpp	9	12	48.500	7.250
#PROF_TSV_END
`````

`````
<!-- ripwire lint: [AST]-only checks (descriptive facts, not gates). rule=the check; sev=user-rule severity; in=enclosing symbol NAME (the same spelling is a fan-in COUNT in for/pack-task/exemplar). A rule named atom-X is an atom of confusion (Gopstein, FSE 2017): a C-family shape that misleads READERS, C/C++/ObjC/CUDA only. Each rule is scanned under its OWN match budget, so no rule is ever starved by a noisier one. A rule that spends its whole budget carries capped="1" — its count= is then a FLOOR (that rule's raw captures reached the per-rule budget; only its own matches can cap it); findings_capped="1" on the root ⇒ at least one rule is a floor. Absent = nothing was capped and every count= is a total. raise the default cap with limit=N (offset=M pages). -->
<!-- with-profile: heat_* on a finding = MEASURED inclusive totals of the joined #PROF_TSV scope — the nearest PROFILE_SCOPE site at/above the finding inside its own enclosing symbol. Columns are whatever counter tier the profiled run armed; an ABSENT heat column was not measured, never zero. heat_joined= on the root counts annotated findings; 0 is honest (no finding sits inside a profiled scope), never an error. -->
<lint findings="1" heat_joined="1">
<rule name="c-style-cast" count="0"/>
<rule name="goto" count="0"/>
<rule name="do-while" count="0"/>
<rule name="unsafe-c-fn" count="0"/>
<rule name="weak-crypto" count="0"/>
<rule name="redundant-parens" count="0"/>
<rule name="suspicious-semicolon" count="0"/>
<rule name="typedef-over-using" count="0"/>
<rule name="magic-number" count="0"/>
<rule name="empty-catch" count="0"/>
<rule name="self-assign" count="0"/>
<rule name="large-function" count="0"/>
<rule name="deep-nesting" count="0"/>
<rule name="inconsistent-return" count="0"/>
<rule name="unreachable-code" count="0"/>
<rule name="naming-short" count="0"/>
<rule name="naming-wordy" count="0"/>
<rule name="naming-series" count="0"/>
<rule name="naming-underscore" count="0"/>
<rule name="naming-case" count="0"/>
<rule name="naming-predicate" count="0"/>
<rule name="naming-setter" count="0"/>
<rule name="naming-confusable" count="0"/>
<rule name="naming-uninformative" count="0"/>
<rule name="atom-comma-operator" count="0"/>
<rule name="atom-embedded-crement" count="0"/>
<rule name="atom-assign-as-value" count="0"/>
… [14 more display lines; full output is 3039 bytes on 1 raw line(s)]
`````

The joined finding — past the display cut above, extracted so the join is visible:

`````
<f rule="cache-pointer-chase-loop" p="./src/x.cpp:11" in="walk" heat_scope="walk: chase pass" heat_calls="12" heat_total_ms="48.500" heat_l1d_mpki="7.250">p = p-&gt;next</f>
`````

## `./build/ripwire . --communities`

*Cluster the call graph into cohesive modules.*

`````
<!-- ripwire communities: cohesive call-graph modules (Louvain); bridge=cross-module edges; isolated=call-graph-edgeless symbols; drill= names the verb that takes an id= from a row below. On each module row size= is its TRUE member count while shown=/capped= describe the member list printed here: this listing is fixed at the 5 top-ranked members and is NOT widened by limit=/offset= (those page the MODULE rows). capped=1 means members were dropped; drill= names the verb that pages the full member list of one module. raise the default cap with limit=N (offset=M pages). -->
<communities drill="--community=ID" modules="808" shown_modules="30" modules_capped="1" bridges="2070" shown_bridges="12" bridges_capped="1" isolated="5160" isolated_decl="811" isolated_header="650" isolated_source="1888" isolated_doc="1811" connected_singletons="0" symbols="8835">
<community id="293" size="384" dir="./src" label="./src::escapeXml@serialize.h:118:7125" shown="5" capped="1">
<member t="method" n="push_back" p="./src/svector.h:126"/>
<member t="method" n="buf" p="./src/svector.h:37"/>
<member t="method" n="buf" p="./src/svector.h:38"/>
<member t="method" n="grow" p="./src/svector.h:39"/>
<member t="method" n="end" p="./src/svector.h:130"/>
</community>
<community id="2215" size="94" dir="./src" label="./src::jsonEscape@mcpjson.h:809:40023" shown="5" capped="1">
<member t="method" n="empty" p="./src/notes.h:396"/>
<member t="fn" n="cappedEcho" p="./src/mcprefusal.h:318"/>
<member t="fn" n="getIndex" p="./src/mcpindex.h:913"/>
<member t="fn" n="captureXml" p="./src/mcpverbs.h:331"/>
<member t="fn" n="findKeyValuePos" p="./src/mcpjson.h:183"/>
</community>
<community id="2387" size="56" dir="./src" label="./src::max@infra/platform.h:98:4855" shown="5" capped="1">
<member t="method" n="empty" p="./src/scipoverlay.h:93"/>
<member t="fn" n="max" p="./src/infra/platform.h:98"/>
<member t="fn" n="lexicalScoresTiered" p="./src/lexical.h:100"/>
<member t="fn" n="lexicalScoresNameExactTiered" p="./src/lexical.h:643"/>
<member t="fn" n="lexicalScores" p="./src/lexical.h:618"/>
</community>
<community id="2174" size="50" dir="./src" label="./src::str@ingest.cpp:1284:79690" shown="5" capped="1">
<member t="method" n="u32" p="./src/ingest.cpp:1282"/>
<member t="method" n="str" p="./src/ingest.cpp:1284"/>
<member t="method" n="u32" p="./src/ingest.cpp:1302"/>
<member t="method" n="u8" p="./src/ingest.cpp:1281"/>
<member t="method" n="view" p="./src/ingest.cpp:1304"/>
</community>
… [195 more display lines; full output is 15775 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --zoom`

*Nested module hierarchy (multi-level Louvain) + cross-module bridges.*

`````
<!-- ripwire zoom: NESTED module hierarchy (multi-level Louvain); indent = one level deeper; module = dominant-dir(symbol-count); leaf lists top-ranked symbols; bridge = cross-top-module call traffic. symbols= is the whole corpus; isolated= is the symbols in NO top-level module (a group of one — the same rule that makes top_modules= count only groups of 2 or more), and they reconcile exactly: symbols= equals isolated= plus the sum of the TOP-LEVEL size= values, every one of them, including any this page did not print. On a level-0 module size= is its true member count and shown=/capped= describe the member list printed here, which is fixed at the 5 top-ranked members and is not widened by limit=/offset= (those page the TOP-LEVEL modules); the community drill verb pages one module's full member list by its level-0 id. A module above level 0 lists every child module, so it carries no shown=/capped= pair. -->
<zoom levels="4" top_modules="251" symbols="8835" isolated="5160">
<module level="3" id="259" size="2237" dir="./src">
<module level="2" id="276" size="1946" dir="./src">
<module level="1" id="281" size="1219" dir="./src">
<module level="0" id="293" size="384" dir="./src" shown="5" capped="1">
<member t="method" n="push_back" p="./src/svector.h:126"/>
<member t="method" n="buf" p="./src/svector.h:37"/>
<member t="method" n="buf" p="./src/svector.h:38"/>
<member t="method" n="grow" p="./src/svector.h:39"/>
<member t="method" n="end" p="./src/svector.h:130"/>
</module>
<module level="0" id="2215" size="94" dir="./src" shown="5" capped="1">
<member t="method" n="empty" p="./src/notes.h:396"/>
<member t="fn" n="cappedEcho" p="./src/mcprefusal.h:318"/>
<member t="fn" n="getIndex" p="./src/mcpindex.h:913"/>
<member t="fn" n="captureXml" p="./src/mcpverbs.h:331"/>
<member t="fn" n="findKeyValuePos" p="./src/mcpjson.h:183"/>
</module>
<module level="0" id="2387" size="56" dir="./src" shown="5" capped="1">
<member t="method" n="empty" p="./src/scipoverlay.h:93"/>
<member t="fn" n="max" p="./src/infra/platform.h:98"/>
<member t="fn" n="lexicalScoresTiered" p="./src/lexical.h:100"/>
<member t="fn" n="lexicalScoresNameExactTiered" p="./src/lexical.h:643"/>
<member t="fn" n="lexicalScores" p="./src/lexical.h:618"/>
</module>
<module level="0" id="2174" size="50" dir="./src" shown="5" capped="1">
<member t="method" n="u32" p="./src/ingest.cpp:1282"/>
<member t="method" n="str" p="./src/ingest.cpp:1284"/>
<member t="method" n="u32" p="./src/ingest.cpp:1302"/>
… [5873 more display lines; full output is 291724 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --report`

*Architecture summary (modules, god-files, cycles) as markdown.*

`````
<!-- ripwire markdown: no run of 4-or-more backticks in this output — safe to embed inside a wider fence -->

# ripwire architecture report

1081 files · 8835 symbols · 10480 edges · 808 modules (5160 call-graph isolated)

Call-graph isolate provenance: 811 declaration, 650 header, 1888 source, 1811 document; 0 connected Louvain singletons

## Modules (call-graph clusters; showing 12 of 808)
- **./src::escapeXml@serialize.h:118:7125** — 384 symbols
- **./src::jsonEscape@mcpjson.h:809:40023** — 94 symbols
- **./src::max@infra/platform.h:98:4855** — 56 symbols
- **./src::str@ingest.cpp:1284:79690** — 50 symbols
- **./src/infra::report_printf@profileScope.h:783:26683** — 39 symbols
- **./src/infra::leaf_at@dynamic_map.hpp:553:28118** — 35 symbols
- **./src::communityPresentation@main.cpp:366:22472** — 31 symbols
- **./src::shSingleQuote@jsonesc.h:268:13935** — 29 symbols
- **./src::min@infra/platform.h:95:4714** — 22 symbols
- **./src::lexicalNormalize@resolve.h:78:6031** — 21 symbols
- **./src::trim@tracein.h:116:5562** — 15 symbols
- **./src::streamBlobs@crossref.h:442:23537** — 14 symbols

## God files (most depended-on; showing 10 of 162)
- `./src/model.h` — 66 dependents
- `./src/serialize.h` — 31 dependents
- `./src/graph.h` — 28 dependents
- `./src/ingest.h` — 20 dependents
- `./src/arch.h` — 18 dependents
- `./src/jsonesc.h` — 15 dependents
- `./src/quality.h` — 15 dependents
… [29 more lines, 2902 bytes total]
`````

## `./build/ripwire . --seams`

*Cross-module call seams no test reaches. NOW carries seam_pairs/shown/capped.*

`````
<!-- ripwire seams: cross-directory call edges NO test reaches (untested integration seams; a fact, not a mandate). module = parent dir; seam = caller-dir -> callee-dir, spelled from= and to=. Each seam pages its own edge rows with shown=/capped=; an edge names caller= at site p= calling callee= at site cp=. UNIT: untested= here counts cross-directory call EDGES. The test gate verb spells untested= over impacted SYMBOLS and the flip verb over the defs a gate lights, so the three numbers count three different things and must never be compared or summed across verbs. raise the default cap with limit=N (offset=M pages) -->
<seams modules="231" bridges="501" untested="338" test_files="742" seam_pairs="49" shown="20" capped="1">
<seam from="./src" to="./src/infra" untested="139" shown="5" capped="1">
<edge caller="skipInert" p="./src/layout.h:187" callee="min" cp="./src/infra/platform.h:95"/>
<edge caller="pageWindow" p="./src/pageview.h:101" callee="min" cp="./src/infra/platform.h:95"/>
<edge caller="selectorFaultClause" p="./src/selectorrefuse.h:84" callee="min" cp="./src/infra/platform.h:95"/>
<edge caller="boundedEditDistance" p="./src/didyoumean.h:34" callee="swap" cp="./src/infra/dynamic_map.hpp:1436"/>
<edge caller="boundedEditDistance" p="./src/didyoumean.h:34" callee="min" cp="./src/infra/platform.h:95"/>
</seam>
<seam from="./bench" to="./src/infra" untested="53" shown="5" capped="1">
<edge caller="aggregateMax" p="./bench/bench_ordered_map.cpp:85" callee="max" cp="./src/infra/platform.h:98"/>
<edge caller="legacySortSmall" p="./bench/bench_radix_ab.cpp:34" callee="swap" cp="./src/infra/dynamic_map.hpp:1436"/>
<edge caller="infraSortSmall" p="./bench/bench_radix_ab.cpp:73" callee="sortKeySmall" cp="./src/infra/radixSort.h:59"/>
<edge caller="medianBy" p="./bench/bench_field_ab.cpp:144" callee="key" cp="./src/infra/dynamic_map.hpp:908"/>
<edge caller="medianBy" p="./bench/bench_chase_ab.cpp:153" callee="key" cp="./src/infra/dynamic_map.hpp:908"/>
</seam>
<seam from="./bench" to="./src" untested="31" shown="5" capped="1">
<edge caller="runSorter" p="./bench/bench_sort_large.cpp:140" callee="push_back" cp="./src/svector.h:126"/>
<edge caller="runScoreSorter" p="./bench/bench_sort_large.cpp:210" callee="push_back" cp="./src/svector.h:126"/>
<edge caller="benchAlternating" p="./bench/bench_radix_ab.cpp:86" callee="push_back" cp="./src/svector.h:126"/>
<edge caller="isSorted" p="./bench/bench_sort_large.cpp:42" callee="lessByFromTo" cp="./src/sortutil.h:132"/>
<edge caller="sameSortedOutput" p="./bench/bench_sort_large.cpp:50" callee="push_back" cp="./src/svector.h:126"/>
</seam>
<seam from="./bench" to="./test/regexfix" untested="7" shown="5" capped="1">
<edge caller="run_session" p="./bench/spec_trace.py:143" callee="open" cp="./test/regexfix/beta.py:6"/>
<edge caller="mine_session_file" p="./bench/mine_traces.py:169" callee="open" cp="./test/regexfix/beta.py:6"/>
<edge caller="read_whole" p="./bench/bench_proof.py:27" callee="open" cp="./test/regexfix/beta.py:6"/>
<edge caller="main" p="./bench/calib_json.py:16" callee="open" cp="./test/regexfix/beta.py:6"/>
<edge caller="main" p="./bench/mine_traces.py:348" callee="open" cp="./test/regexfix/beta.py:6"/>
</seam>
… [95 more display lines; full output is 12470 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --mermaid`

*Module (directory) dependency graph as a Mermaid diagram.*

`````
%% ripwire --mermaid: module (directory) dependency graph — node = dir (symbol count), edge = inter-module calls (>= 3). Render at mermaid.live.
flowchart LR
  subgraph sg0 ["src"]
    n68["src<br/>2733"]
    n69["src/infra<br/>317"]
  end
  subgraph sg1 ["test"]
    n70["test<br/>1794"]
    n131["test/expandmodefix<br/>151"]
    n160["test/legofix<br/>60"]
    n174["test/namingconsistencyfix<br/>57"]
    n110["test/constfix<br/>37"]
    n91["test/callformfix/cpp<br/>36"]
    n159["test/layoutfix<br/>32"]
    n157["test/jsshapefix<br/>29"]
  end
  n43["docs<br/>283"]
  subgraph sg3 ["bench"]
    n2["bench<br/>247"]
    n35["bench/locbench/results/r5_pooling<br/>233"]
    n36["bench/locbench/results/r6_expansion<br/>185"]
    n29["bench/locbench<br/>104"]
    n26["bench/headtohead/r3-headroom-2026-08-03<br/>100"]
    n31["bench/locbench/results/r1cpp_anchorhop<br/>85"]
    n41["bench/nestcal/r1-2026-08-07<br/>84"]
    n23["bench/headtohead<br/>72"]
    n27["bench/headtohead/r4-2026-08-06<br/>70"]
    n3["bench/agentloop<br/>62"]
    n24["bench/headtohead/r2-2026-08-03<br/>48"]
    n42["bench/recalleval<br/>43"]
… [21 more lines, 1621 bytes total]
`````

## `./build/ripwire . --owners`

*Bus-factor: recency-weighted author ownership per file.*

`````
<!-- ripwire owners: recency-weighted author ownership (half-life=6mo). bf=1 = one person holds >80% of weighted commits (bus-factor risk); authors=1 files fold into <uniform/> below; pass detail=1 for the full per-file listing. files= means two different things by DEPTH here and is deliberately not renamed: on the ROOT it is how many files were ANALYSED; on the <uniform/> fold it is how many of them collapsed into that one row. With a SYM, of= echoes it and defs= is how many DEFINITIONS that name has: this report covers the file holding the FIRST of them (lowest node id, the same pick around and lego make), so defs= above 1 means the other definitions' files were NOT analysed. Qualify with file:name to choose one -->
<!-- at= is the git commit these numbers were computed at; a trailing +dirty means the working tree differed from that commit, so the numbers describe the tree, not the commit -->
<owners files="1081" at="33f9f7be2">
<uniform authors="1" bf="1" share="1.00" files="577"/>
<f p="./CHANGELOG.md" authors="2" bf="1" top="<author>" share="0.92"/>
<f p="./README.md" authors="3" bf="1" top="<author>" share="0.97"/>
<f p="./SECURITY.md" authors="2" bf="0" top="<author>" share="0.50"/>
<f p="./THIRD_PARTY.md" authors="2" bf="0" top="<author>" share="0.75"/>
<f p="./bench/ANSWERQUALITY.md" authors="2" bf="0" top="<author>" share="0.75"/>
<f p="./bench/BENCHMARK.md" authors="2" bf="0" top="<author>" share="0.67"/>
<f p="./bench/PROFILE.md" authors="3" bf="1" top="<author>" share="0.88"/>
<f p="./bench/agentloop/README.md" authors="2" bf="0" top="<author>" share="0.75"/>
<f p="./bench/agentloop/analyze.py" authors="2" bf="1" top="<author>" share="0.80"/>
<f p="./bench/agentloop/run_agentloop.py" authors="2" bf="1" top="<author>" share="0.80"/>
<f p="./bench/agentloop/select_tasks.py" authors="2" bf="0" top="<author>" share="0.67"/>
<f p="./bench/bench_convergence.cpp" authors="2" bf="0" top="<author>" share="0.75"/>
<f p="./bench/bench_fixedstr.cpp" authors="2" bf="0" top="<author>" share="0.50"/>
<f p="./bench/bench_ordered_map.cpp" authors="2" bf="0" top="<author>" share="0.50"/>
<f p="./bench/bench_proof.py" authors="2" bf="0" top="<author>" share="0.50"/>
<f p="./bench/bench_radix_ab.cpp" authors="2" bf="0" top="<author>" share="0.75"/>
<f p="./bench/bench_sort_large.cpp" authors="2" bf="0" top="<author>" share="0.67"/>
<f p="./bench/bench_svector3.cpp" authors="2" bf="0" top="<author>" share="0.67"/>
<f p="./bench/calib_json.py" authors="2" bf="0" top="<author>" share="0.67"/>
<f p="./bench/cppbench/README.md" authors="2" bf="0" top="<author>" share="0.67"/>
<f p="./bench/cppbench/results/sfml.json" authors="2" bf="0" top="<author>" share="0.67"/>
<f p="./bench/cppbench/results/sfml_scoreboard.md" authors="2" bf="0" top="<author>" share="0.51"/>
<f p="./bench/cppbench/run_cppbench.py" authors="2" bf="0" top="<author>" share="0.50"/>
<f p="./bench/h4fixtures/cpp/main.cpp" authors="2" bf="0" top="<author>" share="0.50"/>
<f p="./bench/h4fixtures/cppvex/vex.cpp" authors="2" bf="0" top="<author>" share="0.50"/>
<f p="./bench/headtohead/README.md" authors="2" bf="0" top="<author>" share="0.75"/>
… [479 more display lines; full output is 61306 bytes on 1 raw line(s)]
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
<exercises of="test/regression.sh" seed_files="1" shown_seed_files="1" seed_files_capped="0" test_symbols="3" reaches="0" harness="script" note="a shell gate invokes the compiled binary as a subprocess; script-to-binary edges are not modelled, so reaches= counts call-graph reach only and cannot see  … [line truncated: 49 more bytes on this line]
<t p="./test/regression.sh"/>
</exercises>
`````

## `./build/ripwire . --community=0`

*Drill into ONE call-graph community by id — the drill= the --communities output itself advertises.*

`````
<!-- ripwire community: ONE module from the communities/zoom partition — its ranked members and its bridge edges to other modules. size= is the module's TRUE member count; shown=/capped= are this page. partition= is the FULL label space (every id 0..partition-1, incl. isolated singletons) — the range the id= argument ranges over; modules= counts the NON-isolated communities (size>=2), the SAME predicate the communities-listing verb's modules= uses, so parent and child agree. -->
<community id="0" size="1" dir="./.codex-plugin" label="./.codex-plugin::name@plugin.json:2:4" bridges="0" shown_bridges="0" bridges_capped="0" partition="5968" modules="808" shown="1" capped="0">
<member t="sec" n="name" p="./.codex-plugin/plugin.json:2"/>
</community>
`````

## `./build/ripwire . --quality-delta`

*On a CLEAN tree: nothing got worse, exit 0. The gating shape is in the sandbox section below.*

**wall time: 2.14s**

`````
<!-- ripwire quality-delta: only what a change made WORSE against the floor named by baseline= below. FOUR floors, and they are not interchangeable: sidecar = the pinned .ripwire_quality_baseline snapshot, honored only because it was pinned at the CURRENT git HEAD; git-HEAD = no sidecar existed, so the working tree was auto-compared against the HEAD tree; git-HEAD (stale sidecar removed) = a sidecar existed, was pinned at a DIFFERENT sha, and this run DELETED it from your working tree before falling back to HEAD (re-pin with quality-baseline); git-HEAD (stale sidecar ignored) = same staleness verdict, but the file was left on disk (the read-only MCP arm, or an unlink that failed). Only the first is a floor YOU chose; the other three compare against HEAD, so anything already committed cannot appear. at= is the git commit (plus a dirty marker when the working tree differs) this list was computed at. Findings: complexity over the ccx bar, verbosity (LOC)/nesting/params regressions, new duplication, newly-dead, new public api-surface (contract drift), error-masking, short-horizon churn, new clone of a reused helper. THREE independent axes, applied in this order: (1) acked findings are suppressed entirely (acked= counts them, honestly); (2) ORIGIN — a finding on a symbol that EXISTED at the baseline is preexisting-worse (no origin= attribute), one that exists only because the code is NEW carries origin="new-symbol"; (3) MATERIALITY — a small numeric delta is sev="minor". EXIT 2 fires only on preexisting-worse AND major, i.e. gating="N" above; new-symbol rows never gate. Clone kinds classify by their member set (a group is new-symbol only if EVERY member is new); short-horizon-churn is preexisting by construction. exit 0 is NOT a verdict on the new-symbol rows — nothing that existed got worse, but the new debt is yours: read them. LIMIT: origin is canonId identity (path::scope::name), so a RENAMED or MOVED symbol reads as new — a regression carried in with a move classifies new-symbol and will not gate. Descriptive: weigh + fix the real ones, do not game the number (a wrong abstraction beats a low score). Each row carries kind= (which of the measured axes regressed) and sym= (the canonical id it regressed on) — except duplication rows, which name the whole clone group rather than one symbol: members= is the group's member list and tokens= its shared normalized-token count (the same per-group pair the clones verb reports) — plus p="path:line" (root-relative; the first-sorting member for the clone kinds; omitted, never faked, when no locator resolves), and every row the header's gating= counter counts also carries a gating attribute set to 1 — those are the rows the exit code fires on, and they are now marked positively rather than by the ABSENCE of sev/origin. (This sentence deliberately spells no attribute=value literal: the header counters are parsed by grep in several gates, and a quoted numeric example here would be matched first.) -->
<quality-delta baseline="git-HEAD" regressions="0" minor="0" acked="0" preexisting-worse="0" new-symbol="0" gating="0" at="33f9f7be2">
</quality-delta>
`````

stderr:

`````
ripwire: no ./.ripwire_quality_baseline — auto-comparing the working tree vs git HEAD (commit the baseline with --quality-baseline to pin it)
`````

## `./build/ripwire . --edit-check=rankGraphTeleport`

*Fast per-symbol post-edit contract check vs git HEAD (unchanged on a clean tree).*

`````
<!-- ripwire edit-check: SYM's contract (param count + publicness) NOW vs git HEAD — unchanged/new-symbol/contract-change — plus its 1-hop callers. A caller is flagged incompatible="1" when its argument count was reliably counted and NO definition in the folded set could accept it: every one has a FIXED arity that disagrees. A variadic, defaulted or implicit-receiver definition (a Python/Ruby method, whose params counts the self/cls the call site never writes) has no fixed arity and is never flagged. That makes the ARITY half one-sided — a call the compared definitions could accept is never flagged — but it is NOT a proof that the call site binds to THIS definition. Call edges are matched by NAME, so a receiver-qualified call to a same-named callee this tool does not index (a standard-library or third-party method) is measured against the one definition it does index; a clean, compiling tree can therefore carry a nonzero incompatible= with nothing edited at all, and on a widely-shared name it can be most of that name's callers. Read incompatible= as a fact about the tree as it stands — call sites worth OPENING, not a verdict — and status= as a fact about the edit. Warm path hits the qheadsnap/qsnap cache — never a full quality-delta style recompute. defs= is how many DEFINITIONS at this site (same file, same scope, same name — the overload set) are folded into this one contract; a selector matching more than one SITE is refused instead, so defs= only ever counts overloads. params_was and params_now are the MAX over that set on each side (the same MAX the baseline snapshot stores), and publicness is the OR. That MAX has TWO consequences, in opposite directions. It can read like a break and not be one: adding a WIDER overload beside an unchanged one raises params_now with no existing definition altered, so it reports status="contract-change" with incompatible="0" and a def row still carrying the old parameter count — no seen caller breaks. And it can read like safety and not be: REMOVING an overload whose parameter count is BELOW the MAX moves neither number, because the MAX survives on both sides, while the call site that used the removed definition no longer binds. defs_was=/defs_now= is what closes that: the count of definitions sharing this symbol's CANONICAL ID on each side. That population is the one the baseline snapshot buckets by, so the two numbers answer the same question and are equal on an unedited tree — it is deliberately NOT the root's defs=, which is the same bucket narrowed to this FILE (a contract is per definition site), so where a scope-less name also exists in another file defs= is the smaller of the two. status is therefore the join of THREE was-vs-now facts — the params MAX, publicness, and the definition COUNT — and change= names which of them carried it. change= adds broken-callers when a seen caller is also flagged, but never on its own — for the reason stated at the top: incompatible= describes the TREE and status= describes the EDIT, so a headline must not turn on it. RESIDUAL: an overload whose arity changes BELOW the MAX while the COUNT stays the same moves none of the three. The root's incompatible= is the COUNT of flagged callers (a c row's incompatible="1" is the per-caller flag). p= is the definition the selector resolved to; when defs is above 1 EVERY folded definition is listed as its own def row (p=, t=, params=), which is what tells a widened single definition apart from an added overload. At defs="1" no def row is emitted: the root's own p=/t= is that definition, and params_now is its parameter count. counts_floor="1" means every count on this element is a FLOOR, never a total. Call edges are extracted from source text by NAME, so a call that reaches its target through dynamic dispatch (a virtual, interface or duck-typed receiver), a callback or function pointer, a macro-generated call site, or a declaration that parses without a call expression (C++ most-vexing-parse) contributes no edge and is missing here. Read a zero as "none found", never as "none exists". COUNTING UNIT, and it differs by verb — which is why two of them report different numbers for one symbol. The callers, callees, edit-check, graph-query and pr-context counts are DISTINCT SYMBOLS: repeated calls from one caller, and calls to two overloads of one name, collapse into ONE row, their multiplicity surviving only in the call graph's edge weight. The reach counts (impact's reaches=, pr-context's dependents=) are the size of a transitive reach SET, each symbol counted once — not a count of calls or edges. The uses verb counts call SITES, one row per occurrence, so a larger count= there for the same symbol is these units agreeing, not disagreeing. The map header's edges= is a unit again different — distinct (caller,callee) PAIRS — and that document carries neither this marker nor this clause, so its numbers answer a different question. -->
<edit-check sym="rankGraphTeleport" t="fn" p="./src/graph.h:1738" status="unchanged" defs="1" callers="6" incompatible="0" at="33f9f7be2" counts_floor="1">
<c n="runEval" p="./src/eval.h:168"/>
<c n="rankGraph" p="./src/graph.h:1768"/>
<c n="anchoredLexicalRank" p="./src/graph.h:2104"/>
<c n="churnRankedGraph" p="./src/main.cpp:9599"/>
<c n="runDefaultMap" p="./src/main.cpp:9703"/>
<c n="getIndex" p="./src/mcpindex.h:913"/>
</edit-check>
`````

## `./build/ripwire . --pr-context`

*No-LLM review-evidence bundle for the working-tree diff (clean tree = empty).*

`````
<!-- ripwire pr-context: no-LLM review-evidence bundle per changed file — defined symbols, their callers, blast radius (transitive dependents), affected tests, co-change partners not in the diff, and owners. base=working-tree. skipped_mode_only=diffs that changed a file's MODE and nothing else (e.g. chmod) excluded from the changed set; a pure RENAME is content-identical too but is NOT excluded — it is a changed file, listed at its new path. files= means two different things by DEPTH here and is deliberately not renamed (15 consumers read the root one): on the ROOT it is the CHANGED file count; on each <impact/> child it is the distinct files dependents= reaches (changed + non-changed), so dependents="0" implies files="0" and vice versa — never an impossible-looking dependents>0/files=0. files_other= on the same <impact/> is the non-changed subset (a changed file's dependents inside OTHER changed files have no <f> row of their own — they are already shown as their own <file> section); it is NOT the <f> row count — see the row-cap sentence below. Files are ordered by BLAST RADIUS (transitive dependents descending, path breaking ties), not alphabetically. sections= on changed-symbols counts a doc file's headings, collapsed into that number instead of one callers-zero row each; count= still counts every INDEXED symbol, sections included, so count minus sections is the number of rows that follow. Every nested list below is a TOP-N subset of its element's own total, fixed per element (impact <f> at 20, per-symbol <caller> at 12, cochange <partner> at 12, tests <test> at 40, owners <author> at 5 — the L0 defaults; max-tokens only lowers these further via the trim ladder, nothing raises them past L0): each capped element carries its own shown=/capped= pair so the cut is never silent — for the untrimmed list use impact=SYM/callers=SYM (blast radius/callers), affected=FILE or situ (tests), cochange (partners), or owners (authors) instead. direction= names which SIDE this bundle reviews (worktree-since-head, head-since-fork, head-since-ref-tip); a no-ref-work row says the base ref's tip IS the merge base, i.e. it carries no divergent work of its own. deterministic. counts_floor="1" means every count on this element is a FLOOR, never a total. Call edges are extracted from source text by NAME, so a call that reaches its target through dynamic dispatch (a virtual, interface or duck-typed receiver), a callback or function pointer, a macro-generated call site, or a declaration that parses without a call expression (C++ most-vexing-parse) contributes no edge and is missing here. Read a zero as "none found", never as "none exists". COUNTING UNIT, and it differs by verb — which is why two of them report different numbers for one symbol. The callers, callees, edit-check, graph-query and pr-context counts are DISTINCT SYMBOLS: repeated calls from one caller, and calls to two overloads of one name, collapse into ONE row, their multiplicity surviving only in the call graph's edge weight. The reach counts (impact's reaches=, pr-context's dependents=) are the size of a transitive reach SET, each symbol counted once — not a count of calls or edges. The uses verb counts call SITES, one row per occurrence, so a larger count= there for the same symbol is these units agreeing, not disagreeing. The map header's edges= is a unit again different — distinct (caller,callee) PAIRS — and that document carries neither this marker nor this clause, so its numbers answer a different question. -->
<pr-context base="working-tree" direction="worktree-since-head" files="0" skipped_mode_only="0" at="33f9f7be2" counts_floor="1">
<!-- no changed files in the index (clean tree, or the diff touched only non-indexed files) -->
</pr-context>
`````

## `./build/ripwire . --pr-context=main~1`

*The BASEREF form: diffed against merge-base(BASEREF, HEAD), never the ref tip — here the previous mainline commit.*

`````
<!-- ripwire pr-context: no-LLM review-evidence bundle per changed file — defined symbols, their callers, blast radius (transitive dependents), affected tests, co-change partners not in the diff, and owners. base=main~1. skipped_mode_only=diffs that changed a file's MODE and nothing else (e.g. chmod) excluded from the changed set; a pure RENAME is content-identical too but is NOT excluded — it is a changed file, listed at its new path. files= means two different things by DEPTH here and is deliberately not renamed (15 consumers read the root one): on the ROOT it is the CHANGED file count; on each <impact/> child it is the distinct files dependents= reaches (changed + non-changed), so dependents="0" implies files="0" and vice versa — never an impossible-looking dependents>0/files=0. files_other= on the same <impact/> is the non-changed subset (a changed file's dependents inside OTHER changed files have no <f> row of their own — they are already shown as their own <file> section); it is NOT the <f> row count — see the row-cap sentence below. Files are ordered by BLAST RADIUS (transitive dependents descending, path breaking ties), not alphabetically. sections= on changed-symbols counts a doc file's headings, collapsed into that number instead of one callers-zero row each; count= still counts every INDEXED symbol, sections included, so count minus sections is the number of rows that follow. Every nested list below is a TOP-N subset of its element's own total, fixed per element (impact <f> at 20, per-symbol <caller> at 12, cochange <partner> at 12, tests <test> at 40, owners <author> at 5 — the L0 defaults; max-tokens only lowers these further via the trim ladder, nothing raises them past L0): each capped element carries its own shown=/capped= pair so the cut is never silent — for the untrimmed list use impact=SYM/callers=SYM (blast radius/callers), affected=FILE or situ (tests), cochange (partners), or owners (authors) instead. direction= names which SIDE this bundle reviews (worktree-since-head, head-since-fork, head-since-ref-tip); a no-ref-work row says the base ref's tip IS the merge base, i.e. it carries no divergent work of its own. deterministic. counts_floor="1" means every count on this element is a FLOOR, never a total. Call edges are extracted from source text by NAME, so a call that reaches its target through dynamic dispatch (a virtual, interface or duck-typed receiver), a callback or function pointer, a macro-generated call site, or a declaration that parses without a call expression (C++ most-vexing-parse) contributes no edge and is missing here. Read a zero as "none found", never as "none exists". COUNTING UNIT, and it differs by verb — which is why two of them report different numbers for one symbol. The callers, callees, edit-check, graph-query and pr-context counts are DISTINCT SYMBOLS: repeated calls from one caller, and calls to two overloads of one name, collapse into ONE row, their multiplicity surviving only in the call graph's edge weight. The reach counts (impact's reaches=, pr-context's dependents=) are the size of a transitive reach SET, each symbol counted once — not a count of calls or edges. The uses verb counts call SITES, one row per occurrence, so a larger count= there for the same symbol is these units agreeing, not disagreeing. The map header's edges= is a unit again different — distinct (caller,callee) PAIRS — and that document carries neither this marker nor this clause, so its numbers answer a different question. -->
<!-- anchoring: a base ref was given, so this diff is anchored at merge base(BASEREF, HEAD), NOT at the ref's tip — the bundle is what THIS work changed since it forked, not how the two trees differ today. base_moved= counts paths the BASE REF moved since the fork that this work never touched (excluded here, and the same row class the abi verb names head moved: the other line moved, we did not author it). anchor="ref tip two dot" instead means there was no merge base at all (unrelated history) and the two dot view is what you are reading. -->
<pr-context base="main~1" anchor="merge-base" base_sha="2d8891b0b" base_moved="0" direction="head-since-fork" files="6" skipped_mode_only="0" at="33f9f7be2" counts_floor="1">
<no-ref-work note="main~1 tip == merge-base, so that ref has no divergent work of its own; this bundle is HEAD's work since the fork. For the ref's OWN diff see merge-scout or stray-content"/>
<file p="./test/showcase_capture.py" symbols="66">
<impact dependents="32" files="7" files_other="7" shown="7" capped="0">
<f p="./bench/headtohead/r4-2026-08-06/r4_worker.py" deps="9"/>
<f p="./bench/cppbench/run_cppbench.py" deps="5"/>
<f p="./bench/headtohead/r2-2026-08-03/worker.py" deps="5"/>
<f p="./bench/multiswe/run_multiswe.py" deps="5"/>
<f p="./bench/locbench/run_locbench.py" deps="3"/>
<f p="./bench/mine_traces.py" deps="3"/>
<f p="./bench/ensemblecal/run_ensemblecal.py" deps="2"/>
</impact>
<tests count="0" shown="0" capped="0">
</tests>
<changed-symbols count="66">
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
<s t="var" n="TRACE" p="./test/showcase_capture.py:30" callers="0" shown="0" capped="0">
… [896 more display lines; full output is 48998 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --merge-scout=main~2,main~1`

*Pairwise cross-arm conflict sites + suggested landing order (any committish works as an arm).*

**wall time: 2.10s**

`````
<!-- ripwire merge-scout: read-only cross-branch overlap for 2 arm(s) — same-symbol change on two arms = conflict, same-file/different-symbol = textual risk. landing = fewest-conflicts-first greedy (ties: ref name asc). Every tree is a git-archive TEMP COPY (read-only); the real working tree/refs are never touched. ANCHORING: every arm is diffed against its OWN merge base with HEAD (the working tree arm against HEAD itself), never against live HEAD — so a file an arm never opened can never appear here just because the live line moved. head_conflicts= is the one thing that anchor hides, kept as its own row class: symbols this arm changed that the LIVE LINE also changed since the arm forked, a merge fight no pairwise ARM comparison can see because HEAD is not an arm. -->
<merge-scout arms="2" head="33f9f7be2">
<arm ref="main~2" base="7db932ce5" ok="1" changed="0" head_conflicts="0">
<no-work note="no divergent work vs merge-base — see --stray-content"/>
</arm>
<arm ref="main~1" base="2d8891b0b" ok="1" changed="0" head_conflicts="0">
<no-work note="no divergent work vs merge-base — see --stray-content"/>
</arm>
<pair a="main~2" b="main~1" conflicts="0" risks="0"/>
<landing order=""/>
</merge-scout>
`````

## `./build/ripwire . --stray-content=lane`

*Which lane-* refs still hold divergent authored work vs HEAD, with verdicts.*

`````
<!-- ripwire stray-content: per ref, the lines its own divergent work AUTHORED (vs its merge-base with HEAD) that the live line does NOT have. v="superseded" means the live line removed the same base code this ref removed (redone/del) — it re-implemented the work, the case `git cherry` cannot see; v="unmerged" means the work is genuinely absent; merged refs are omitted. Read-only: git cat-file/diff/ls-tree only, one batched cat-file for the whole sweep, every blob reduced once per sha. Line-granular, not semantic: see the ripwire help text for the limits. ANCHORING is a deliberate hybrid: the SCOPE is base anchored (only lines the ref itself authored vs its merge base are ever considered, so a file the ref never opened cannot appear because the live line moved), while the ABSENCE test is HEAD anchored on purpose (does the live line have this content TODAY is the question being asked, and it is only answerable against live HEAD). v="unknown" with ok="0" means this ref could NOT be analysed at all because it has no merge base with HEAD, which on a SHALLOW clone (the checkout default in CI) is every ref: it is not a claim that the ref is merged, and the fix is to deepen the clone. The four buckets are exhaustive, so unmerged plus superseded plus merged plus unknown always equals refs. SCOPE: refs/heads only, which is every local branch (worktree branches included). Remote tracking refs are NOT scanned: they mirror local ones in the usual checkout and would double every row. The consequence on a FRESH CLONE, where the branches live under refs/remotes/origin and only the checked out one has a local head, is that there is nothing here to be stray FROM; refs= is that fact as a number. TRUNCATION: a ref row ends with a more element (more files=N) when its own file listing was capped; shown plus that number equals the ref's files= total, always. That inner listing is a SECONDARY listing (it repeats complete and identical on every page) and is capped by detail, not by limit / offset, which page the OUTER ref listing and report their own shown= / capped=. -->
<stray-content head="33f9f7be2" head_ref="worktree-agent-a22b630900f285f04" refs="1" blobs="0" unmerged="0" superseded="0" merged="1" unknown="0">
</stray-content>
`````

## `./build/ripwire . --stray-content=worktree-agent-a1`

*A ref family that IS fully merged — the omit-merged-refs contract, with the counters still reconciling against refs=.*

`````
<!-- ripwire stray-content: per ref, the lines its own divergent work AUTHORED (vs its merge-base with HEAD) that the live line does NOT have. v="superseded" means the live line removed the same base code this ref removed (redone/del) — it re-implemented the work, the case `git cherry` cannot see; v="unmerged" means the work is genuinely absent; merged refs are omitted. Read-only: git cat-file/diff/ls-tree only, one batched cat-file for the whole sweep, every blob reduced once per sha. Line-granular, not semantic: see the ripwire help text for the limits. ANCHORING is a deliberate hybrid: the SCOPE is base anchored (only lines the ref itself authored vs its merge base are ever considered, so a file the ref never opened cannot appear because the live line moved), while the ABSENCE test is HEAD anchored on purpose (does the live line have this content TODAY is the question being asked, and it is only answerable against live HEAD). v="unknown" with ok="0" means this ref could NOT be analysed at all because it has no merge base with HEAD, which on a SHALLOW clone (the checkout default in CI) is every ref: it is not a claim that the ref is merged, and the fix is to deepen the clone. The four buckets are exhaustive, so unmerged plus superseded plus merged plus unknown always equals refs. SCOPE: refs/heads only, which is every local branch (worktree branches included). Remote tracking refs are NOT scanned: they mirror local ones in the usual checkout and would double every row. The consequence on a FRESH CLONE, where the branches live under refs/remotes/origin and only the checked out one has a local head, is that there is nothing here to be stray FROM; refs= is that fact as a number. TRUNCATION: a ref row ends with a more element (more files=N) when its own file listing was capped; shown plus that number equals the ref's files= total, always. That inner listing is a SECONDARY listing (it repeats complete and identical on every page) and is capped by detail, not by limit / offset, which page the OUTER ref listing and report their own shown= / capped=. -->
<stray-content head="33f9f7be2" head_ref="worktree-agent-a22b630900f285f04" refs="1" blobs="0" unmerged="0" superseded="0" merged="1" unknown="0">
</stray-content>
`````

## `./build/ripwire . --stray-content=r27 --plan`

*Select the genuinely-unmerged refs and feed them to merge-scout for a landing order.*

`````
<!-- ripwire landing-plan: stray-content's cheap per-blob sweep composed with merge-scout's per-arm overlap oracle — of every local branch, which still hold REAL work (v="unmerged"), which were already re-implemented on the live line (v="superseded", EXCLUDED below — landing them re-does work that is already done) or are already merged (omitted entirely, counted in merged= on the root element), and the fewest-conflicts-first order to land what remains. scouted="0" on an unmerged ref means it was NOT fed to merge-scout this run (the cost bound, not a verdict) — it is still real, unscouted work; bounded= on the root element counts them and detail lifts the bound. merge-scout is the EXPENSIVE step here (git-archive + full ingest per arm) — stray-content's own sweep is the cheap one. An undetermined row is a ref that could NOT be analysed at all (no merge base with HEAD, which on a SHALLOW clone is every ref): it is neither scouted nor excluded nor merged, because nothing was measured — treat it as unfinished business and deepen the clone, never as a clean branch. Read-only throughout: no checkout, no ref write, no working-tree mutation. The root carries BOTH head= and at= and they are the same commit: head= is the bare 9 hex chars this verb has always printed, at= is the tool wide anchor and is head= plus a "+dirty" suffix when the working tree is not clean. Prefer at= (it is the one spelling every other repo reading verb uses, and the only one that tells you whether uncommitted work was in scope); head= is kept for callers already keyed to it. -->
<landing-plan head="33f9f7be2" refs="0" unmerged="0" superseded="0" merged="0" undetermined="0" scouted="0" bounded="0" scout-ok="1" at="33f9f7be2">
</landing-plan>
`````

## `./build/ripwire . --stray-content=lane --abi`

*Cross-branch ABI-break gate: struct byte-contract drift on each ref's AUTHORED paths.*

`````
<!-- ripwire abi: the cross-branch ABI-BREAK gate — layout(STRUCT) crossed with stray-content(BRANCH). Scope is what each ref AUTHORED: the paths `diff base..tip` reports against its own merge base, never `diff HEAD..tip` (a file the branch never opened cannot be a break the branch introduced, and on a long-lived tree that one distinction took 487 drift rows to 4). For each such path the SAME field-offset model layout uses is run LEXICALLY on the ref's git blob (never indexed) and compared against HEAD's computed fields. LISTED kinds: drift = the byte contract differs (the bug this check exists for, the only kind that exits 2); unknown = the ref-side copy could not be modelled (see ref_caveat) and is NEVER reported as unchanged; absent = the ref does not define the struct at that path. COUNTED but not listed (pass detail=N to print them): rename = identical slots and field types under different field NAMES, so every byte stayed where it was (a same-type field REORDER is lexically identical to a rename and lands here too); spelling and stub mirror layout's own harmless cases; head-moved = the ref's copy equals its own merge-base copy, so the LIVE LINE is what changed. head_only= counts candidate sites on paths only the live line touched (outside the authored scope); unmodelable= counts sites skipped because HEAD's own copy carries no baseline; every excluded row is on a counter, nothing is dropped silently. Structs that match are omitted entirely; a ref with no rows at all is counted in quiet=, and a ref whose every row is an excluded kind is counted in excluded_refs= and prints under detail=N. LIMITS: HEAD's own side is the WORKING TREE's layout answer, not a re-fetched git blob at HEAD's commit; a nested field type that ALSO changed on the ref resolves via HEAD's copy, not the ref's; the ref-side locator is index-free and file-scope (one namespace deep) only, so a struct nested in a class or wrapped in an extern C block reads absent rather than compared; the authorship anchor is per PATH, so a branch changing struct S in one file while the live line changes S's mirror in another is a merge hazard only layout(S) on the merged result can see. Single-root; read-only (cat-file/diff/merge-base only). -->
<abi head="33f9f7be2" head_ref="worktree-agent-a22b630900f285f04" refs="1" candidates="666" compared="0" blobs="0" rows="0" shown="0" capped="0" dropped="0" excluded="0" head_only="168" unmodelable="0" unrelated="0" broken_refs="0" quiet="1" excluded_refs="0">
</abi>
`````

stderr:

`````
ripwire: --stray-content takes precedence when several verbs are given — IGNORED this run: --abi. The winner is fixed by ripwire's dispatch order, NOT by the order you typed them; pass one verb per run.
`````

## `./build/ripwire . --whereis=rankGraphTeleport`

*Which ref's tree defines or mentions SYM — HEAD first, then every local branch.*

**wall time: 1.88s**

`````
<!-- ripwire whereis: every LOCAL ref whose TREE contains this symbol, HEAD first, and within a ref SOURCE files before test files before docs, then definitions before references, then path and line. The doc demotion is ORDER ONLY: a doc line that quotes a signature still reads as a definition to the heuristic below and still says kind="def", it is simply printed after the code. kind= is answered by TWO different mechanisms, and head_labels= says which one answered for HEAD: with head_labels="index" a HEAD row is kind="def" iff the PARSED index puts a definition there (one row per index def site), while every NON-HEAD row — and every row when head_labels="lexical" (no index was supplied, the index knows no def of this name, or the working tree has drifted from HEAD) — is a LEXICAL shape heuristic over raw blob text that was never ingested: it reads a quoted signature in a doc as a definition and can miss an unusual declarator. refs_scanned= is the SCAN DENOMINATOR (how many refs besides HEAD were read), NOT a count of refs that matched — hits= and the rows are the matched set. on-head="0" alongside ref hits is the case this verb exists for: content that lives only on a branch. A TREE scan can only find content some ref still carries, so hits="0" on its own does not distinguish a name this repo never had from one it deleted; run with the with_history flag and the fate row says which, naming the commit that removed it. ANCHORING: none, by design. This verb runs no diff at all — it scans each ref's FULL tree, which is what lets it find content a branch merely INHERITED (exactly what a merge base anchored diff would exclude), so nothing here can fire merely because HEAD moved. at= is sha-only here (never +dirty): a tree scan reads committed blobs, so the working tree's cleanliness does not enter the answer. SELECTOR: this verb takes a BARE symbol name, not the file:name spelling that callers, uses, impact, around, lego and edit_check accept. A file:name spelling is searched as a LITERAL string, no tree contains it, and the result is a true but useless hits="0" shaped exactly like a name this repo never had. When that is what happened, a selector-note element says so and its retry= is the bare name to re-run with. Its absence beside hits="0" means the zero IS a measurement. SCOPE: refs/heads only, which is every local branch (worktree branches included). Remote tracking refs are NOT scanned: they mirror local ones in the usual checkout and would double every row. The consequence on a FRESH CLONE, where the branches live under refs/remotes/origin and only the checked out one has a local head, is that this verb sees essentially one tree; refs_scanned= is that fact as a number, so read it before reading hits=. TRUNCATION: the trailing more element (more hits=N) is the rows AFTER this page, so shown plus more equals the rows from this page's offset on. It is not a second cap, and not a second vocabulary to page by: it is the SAME fact shown= / capped= / next_offset= carry, restated from the other end (what this page did not print). Page with limit= and offset=; the more element is absent exactly when this page reached the end of the hit list. raise the default cap with limit=N (offset=M pages) -->
<whereis sym="rankGraphTeleport" on-head="1" refs_scanned="98" blobs="2123" hits="23860" head_labels="index" shown="60" capped="1" at="33f9f7be2">
<hit ref="HEAD" tip="33f9f7be2" date="2026-08-08" p="src/graph.h" l="1738" kind="def" t="inline std::vector&lt;float&gt; rankGraphTeleport( const Graph&amp; g, const std::vector&lt;float&gt;&amp; p, float alpha = 0.85f )"/>
<hit ref="HEAD" tip="33f9f7be2" date="2026-08-08" p="present/deck5_ripwire_build.js" l="415" kind="ref" t="s.addText(&quot;$ ripwire . --callers=rankGraphTeleport&quot;, { x: 8.68, y: 2.1, w: 3.8, h: 0.3, fontFace: MONO, fontSize: 10, color: MUTED, margin: 0 });"/>
<hit ref="HEAD" tip="33f9f7be2" date="2026-08-08" p="present/deck5_ripwire_build.js" l="417" kind="ref" t="{ text: &quot;&lt;callers of=\&quot;rankGraphTeleport\&quot;\n  defs=\&quot;1\&quot; count=\&quot;6\&quot; &quot;, options: { color: TEXT } },"/>
<hit ref="HEAD" tip="33f9f7be2" date="2026-08-08" p="src/crossref.h" l="1562" kind="ref" t="// code above the real definition: `--whereis=rankGraphTeleport` opened with three kind=&quot;def&quot; rows into"/>
<hit ref="HEAD" tip="33f9f7be2" date="2026-08-08" p="src/eval.h" l="320" kind="ref" t="const std::vector&lt;float&gt; r = rankGraphTeleport( g, diffTeleport( ing, seedMask ) );"/>
<hit ref="HEAD" tip="33f9f7be2" date="2026-08-08" p="src/graph.h" l="88" kind="ref" t="// renormalized to Σ=1 in rankGraphTeleport — so every teleport-based"/>
<hit ref="HEAD" tip="33f9f7be2" date="2026-08-08" p="src/graph.h" l="1694" kind="ref" t="// prior (never the edges) and renormalized in rankGraphTeleport. Every symbol whose name is missing from"/>
<hit ref="HEAD" tip="33f9f7be2" date="2026-08-08" p="src/graph.h" l="1771" kind="ref" t="return rankGraphTeleport( g, std::vector&lt;float&gt;( N, N ? 1.0f / float( N ) : 0.f ), alpha );"/>
<hit ref="HEAD" tip="33f9f7be2" date="2026-08-08" p="src/graph.h" l="2100" kind="ref" t="// cliff), run the EXISTING PPR machinery (rankGraphTeleport — the same biasPrior/det-gate seam every"/>
<hit ref="HEAD" tip="33f9f7be2" date="2026-08-08" p="src/graph.h" l="2144" kind="ref" t="const std::vector&lt;float&gt; ppr = rankGraphTeleport( g, p );"/>
<hit ref="HEAD" tip="33f9f7be2" date="2026-08-08" p="src/main.cpp" l="9621" kind="ref" t="std::vector&lt;float&gt; rank   = rankGraphTeleport( d.g, churnTeleportWorkspace( rootDirs, d.ing, &quot;18 months ago&quot;, &amp;hasChurnEvidence ) );"/>
<hit ref="HEAD" tip="33f9f7be2" date="2026-08-08" p="src/main.cpp" l="9629" kind="ref" t="std::vector&lt;float&gt; rank   = rankGraphTeleport( d.g, churnTeleport( d.root, d.ing, &quot;18 months ago&quot;, d.cfg.since.empty() ? nullptr : &amp;sinceScope, &amp;hasChurnEvidence ) );"/>
<hit ref="HEAD" tip="33f9f7be2" date="2026-08-08" p="src/main.cpp" l="9791" kind="ref" t="rank = rankGraphTeleport( g, diffTeleport( ing, changed ) );"/>
<hit ref="HEAD" tip="33f9f7be2" date="2026-08-08" p="src/mcpindex.h" l="966" kind="ref" t="// symbols, the rest uniform, then rankGraphTeleport (which also applies the name-quality biasPrior"/>
<hit ref="HEAD" tip="33f9f7be2" date="2026-08-08" p="src/mcpindex.h" l="999" kind="ref" t="ix.rank = rankGraphTeleport( ix.g, diffTeleport( ix.ing, changed ) );"/>
<hit ref="HEAD" tip="33f9f7be2" date="2026-08-08" p="src/selectorrefuse.h" l="7" kind="ref" t="// (&quot;that file defines no &apos;rankGraphTeleport&apos;&quot;), names the files that DO define the name, and hands back a"/>
<hit ref="HEAD" tip="33f9f7be2" date="2026-08-08" p="bench/nestcal/r1-2026-08-07/post-ripwire-src.tsv" l="651" kind="ref" t="graph.h::rw::rankGraphTeleport&#9;3&#9;0&#9;0&#9;5&#9;8&#9;28"/>
<hit ref="HEAD" tip="33f9f7be2" date="2026-08-08" p="bench/nestcal/r1-2026-08-07/pre-ripwire-src.tsv" l="651" kind="ref" t="graph.h::rw::rankGraphTeleport&#9;3&#9;0&#9;0&#9;5&#9;8&#9;28"/>
<hit ref="HEAD" tip="33f9f7be2" date="2026-08-08" p="bench/recalleval/labels_ranking.tsv" l="49" kind="ref" t="power iteration rank convergence damping factor&#9;src/pagerank.cpp#pageRankDouble&#9;src/graph.h#rankGraphTeleport,src/pagerank.h#pageRankDouble&#9;concept"/>
<hit ref="HEAD" tip="33f9f7be2" date="2026-08-08" p="bench/recalleval/labels_ranking.tsv" l="68" kind="ref" t="pagerank power iteration&#9;src/pagerank.cpp#pageRankDouble&#9;src/pagerank.h#pageRankDouble,src/graph.h#rankGraphTeleport&#9;adversarial"/>
<hit ref="HEAD" tip="33f9f7be2" date="2026-08-08" p="bench/recalleval/snapshot.mdpack" l="1706" kind="ref" t="shifted `readmeexamplecheck`&apos;s pinned `--callers=rankGraphTeleport` example by +9 lines"/>
<hit ref="HEAD" tip="33f9f7be2" date="2026-08-08" p="bench/recalleval/snapshot.mdpack" l="2758" kind="ref" t="$ ripwire . --callers=rankGraphTeleport"/>
<hit ref="HEAD" tip="33f9f7be2" date="2026-08-08" p="bench/recalleval/snapshot.mdpack" l="2759" kind="ref" t="&lt;callers of=&quot;rankGraphTeleport&quot; defs=&quot;1&quot; count=&quot;6&quot; counts_floor=&quot;1&quot;&gt;"/>
<hit ref="HEAD" tip="33f9f7be2" date="2026-08-08" p="bench/recalleval/snapshot.mdpack" l="7559" kind="ref" t="$ ./build/ripwire . --for=&quot;rankGraphTeleport&quot;"/>
<hit ref="HEAD" tip="33f9f7be2" date="2026-08-08" p="bench/recalleval/snapshot.mdpack" l="7560" kind="ref" t="&lt;ctx task=&quot;rankGraphTeleport&quot; route=&quot; [routed: name-exact BM25 — query names a symbol (rankGraphTeleport)]&quot;&gt;"/>
<hit ref="HEAD" tip="33f9f7be2" date="2026-08-08" p="bench/recalleval/snapshot.mdpack" l="7561" kind="ref" t="&lt;!-- ripwire lens for &quot;rankGraphTeleport&quot; [routed: name-exact BM25 — query names a symbol (rankGraphTeleport)]: reusable building blocks + quality facts for what you&apos;re a … [line truncated: 249 more bytes on this line]
<hit ref="HEAD" tip="33f9f7be2" date="2026-08-08" p="bench/recalleval/snapshot.mdpack" l="7564" kind="ref" t="&lt;d l=&quot;1277&quot; n=&quot;rankGraphTeleport&quot; id=&quot;./src/graph.h::rw::rankGraphTeleport&quot; cx=&quot;5&quot; ccx=&quot;8&quot; in=&quot;6&quot; churn=&quot;7&quot; amp=&quot … [line truncated: 16 more bytes on this line]
<hit ref="HEAD" tip="33f9f7be2" date="2026-08-08" p="bench/recalleval/snapshot.mdpack" l="7565" kind="ref" t="&lt;doc&gt;PageRank with an explicit teleport / personalization vector p (Σp = 1). The prior is name-quality-biased through biasPrior() so all rank modes share one weighting seam; the trans … [line truncated: 190 more bytes on this line]
… [34 more display lines; full output is 17094 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --whereis=computeOnePairOverlap --with-history`

*Same, plus a git-history <fate> row (never / removed-by-commit) for names no tree carries.*

**wall time: 3.31s**

`````
<!-- ripwire whereis: every LOCAL ref whose TREE contains this symbol, HEAD first, and within a ref SOURCE files before test files before docs, then definitions before references, then path and line. The doc demotion is ORDER ONLY: a doc line that quotes a signature still reads as a definition to the heuristic below and still says kind="def", it is simply printed after the code. kind= is answered by TWO different mechanisms, and head_labels= says which one answered for HEAD: with head_labels="index" a HEAD row is kind="def" iff the PARSED index puts a definition there (one row per index def site), while every NON-HEAD row — and every row when head_labels="lexical" (no index was supplied, the index knows no def of this name, or the working tree has drifted from HEAD) — is a LEXICAL shape heuristic over raw blob text that was never ingested: it reads a quoted signature in a doc as a definition and can miss an unusual declarator. refs_scanned= is the SCAN DENOMINATOR (how many refs besides HEAD were read), NOT a count of refs that matched — hits= and the rows are the matched set. on-head="0" alongside ref hits is the case this verb exists for: content that lives only on a branch. A TREE scan can only find content some ref still carries, so hits="0" on its own does not distinguish a name this repo never had from one it deleted; run with the with_history flag and the fate row says which, naming the commit that removed it. ANCHORING: none, by design. This verb runs no diff at all — it scans each ref's FULL tree, which is what lets it find content a branch merely INHERITED (exactly what a merge base anchored diff would exclude), so nothing here can fire merely because HEAD moved. at= is sha-only here (never +dirty): a tree scan reads committed blobs, so the working tree's cleanliness does not enter the answer. SELECTOR: this verb takes a BARE symbol name, not the file:name spelling that callers, uses, impact, around, lego and edit_check accept. A file:name spelling is searched as a LITERAL string, no tree contains it, and the result is a true but useless hits="0" shaped exactly like a name this repo never had. When that is what happened, a selector-note element says so and its retry= is the bare name to re-run with. Its absence beside hits="0" means the zero IS a measurement. SCOPE: refs/heads only, which is every local branch (worktree branches included). Remote tracking refs are NOT scanned: they mirror local ones in the usual checkout and would double every row. The consequence on a FRESH CLONE, where the branches live under refs/remotes/origin and only the checked out one has a local head, is that this verb sees essentially one tree; refs_scanned= is that fact as a number, so read it before reading hits=. TRUNCATION: the trailing more element (more hits=N) is the rows AFTER this page, so shown plus more equals the rows from this page's offset on. It is not a second cap, and not a second vocabulary to page by: it is the SAME fact shown= / capped= / next_offset= carry, restated from the other end (what this page did not print). Page with limit= and offset=; the more element is absent exactly when this page reached the end of the hit list. raise the default cap with limit=N (offset=M pages) -->
<whereis sym="computeOnePairOverlap" on-head="1" refs_scanned="98" blobs="2123" hits="1802" head_labels="index" shown="60" capped="1" at="33f9f7be2">
<history probed="1" head="33f9f7be2" commits="347" removed-names="15860"/>
<fate sym="computeOnePairOverlap" v="removed" commit="04dc2d235" date="2026-08-08" p="docs/captures/COMMANDS_showcase_2026-08-01.md" note="the newest commit reachable from HEAD that removed a line carrying this name — so for a name HEAD no longer has, that is when it left"/>
<hit ref="HEAD" tip="33f9f7be2" date="2026-08-08" p="src/mergescout.h" l="530" kind="def" t="inline PairOverlap computeOnePairOverlap( std::size_t a, std::size_t b, const Arm&amp; armA, const Arm&amp; armB )"/>
<hit ref="HEAD" tip="33f9f7be2" date="2026-08-08" p="src/lanes.h" l="17" kind="ref" t="// and the landing order are mergescout::computeOnePairOverlap / computeOverlaps / landingOrder, fed SYNTHETIC"/>
<hit ref="HEAD" tip="33f9f7be2" date="2026-08-08" p="src/lanes.h" l="64" kind="ref" t="//   same_file_risk[] — different keys, same file. AGGREGATED PER FILE: computeOnePairOverlap is a nested loop"/>
<hit ref="HEAD" tip="33f9f7be2" date="2026-08-08" p="src/mergescout.h" l="557" kind="ref" t="pairs.push_back( computeOnePairOverlap( a, b, arms[a], arms[b] ) );"/>
<hit ref="HEAD" tip="33f9f7be2" date="2026-08-08" p="bench/nestcal/r1-2026-08-07/post-ripwire-src.tsv" l="1588" kind="ref" t="mergescout.h::mergescout::computeOnePairOverlap&#9;3&#9;0&#9;0&#9;5&#9;7&#9;19"/>
<hit ref="HEAD" tip="33f9f7be2" date="2026-08-08" p="bench/nestcal/r1-2026-08-07/pre-ripwire-src.tsv" l="1588" kind="ref" t="mergescout.h::mergescout::computeOnePairOverlap&#9;4&#9;1&#9;1&#9;5&#9;7&#9;19"/>
<hit ref="HEAD" tip="33f9f7be2" date="2026-08-08" p="bench/recalleval/snapshot.mdpack" l="14503" kind="ref" t="## `./build/ripwire . --whereis=computeOnePairOverlap --with-history`"/>
<hit ref="HEAD" tip="33f9f7be2" date="2026-08-08" p="bench/recalleval/snapshot.mdpack" l="14511" kind="ref" t="&lt;whereis sym=&quot;computeOnePairOverlap&quot; on-head=&quot;1&quot; refs_scanned=&quot;0&quot; blobs=&quot;1047&quot; hits=&quot;19&quot; head_labels=&quot;index&quot; shown=&quot;19&qu … [line truncated: 56 more bytes on this line]
<hit ref="HEAD" tip="33f9f7be2" date="2026-08-08" p="bench/recalleval/snapshot.mdpack" l="14513" kind="ref" t="&lt;fate sym=&quot;computeOnePairOverlap&quot; v=&quot;removed&quot; commit=&quot;93dbc7972&quot; date=&quot;2026-08-01&quot; p=&quot;docs/captures/COMMANDS_showcase_2026-08-01.md&quot; not … [line truncated: 157 more bytes on this line]
<hit ref="HEAD" tip="33f9f7be2" date="2026-08-08" p="bench/recalleval/snapshot.mdpack" l="14514" kind="ref" t="&lt;hit ref=&quot;HEAD&quot; tip=&quot;bc09d0260&quot; date=&quot;2026-08-01&quot; p=&quot;src/mergescout.h&quot; l=&quot;470&quot; kind=&quot;def&quot; t=&quot;inline PairOverlap computeOn … [line truncated: 108 more bytes on this line]
<hit ref="HEAD" tip="33f9f7be2" date="2026-08-08" p="bench/recalleval/snapshot.mdpack" l="14515" kind="ref" t="&lt;hit ref=&quot;HEAD&quot; tip=&quot;bc09d0260&quot; date=&quot;2026-08-01&quot; p=&quot;src/lanes.h&quot; l=&quot;17&quot; kind=&quot;ref&quot; t=&quot;// and the landing order are merge … [line truncated: 90 more bytes on this line]
<hit ref="HEAD" tip="33f9f7be2" date="2026-08-08" p="bench/recalleval/snapshot.mdpack" l="14516" kind="ref" t="&lt;hit ref=&quot;HEAD&quot; tip=&quot;bc09d0260&quot; date=&quot;2026-08-01&quot; p=&quot;src/lanes.h&quot; l=&quot;64&quot; kind=&quot;ref&quot; t=&quot;//   same_file_risk[] — differen … [line truncated: 92 more bytes on this line]
<hit ref="HEAD" tip="33f9f7be2" date="2026-08-08" p="bench/recalleval/snapshot.mdpack" l="14517" kind="ref" t="&lt;hit ref=&quot;HEAD&quot; tip=&quot;bc09d0260&quot; date=&quot;2026-08-01&quot; p=&quot;src/mergescout.h&quot; l=&quot;487&quot; kind=&quot;ref&quot; t=&quot;pairs.push_back( computeOneP … [line truncated: 53 more bytes on this line]
<hit ref="HEAD" tip="33f9f7be2" date="2026-08-08" p="bench/recalleval/snapshot.mdpack" l="14518" kind="ref" t="&lt;hit ref=&quot;HEAD&quot; tip=&quot;bc09d0260&quot; date=&quot;2026-08-01&quot; p=&quot;test/showcase_capture.py&quot; l=&quot;190&quot; kind=&quot;ref&quot; t=&quot;add(S4, f&amp;quot;{ … [line truncated: 254 more bytes on this line]
<hit ref="HEAD" tip="33f9f7be2" date="2026-08-08" p="bench/recalleval/snapshot.mdpack" l="14519" kind="ref" t="&lt;hit ref=&quot;HEAD&quot; tip=&quot;bc09d0260&quot; date=&quot;2026-08-01&quot; p=&quot;docs/captures/COMMANDS_showcase_2026-08-01.md&quot; l=&quot;2211&quot; kind=&quot;ref&quot; t=&quo … [line truncated: 85 more bytes on this line]
<hit ref="HEAD" tip="33f9f7be2" date="2026-08-08" p="bench/recalleval/snapshot.mdpack" l="14520" kind="ref" t="&lt;hit ref=&quot;HEAD&quot; tip=&quot;bc09d0260&quot; date=&quot;2026-08-01&quot; p=&quot;docs/captures/COMMANDS_showcase_2026-08-01.md&quot; l=&quot;2217&quot; kind=&quot;ref&quot; t=&quo … [line truncated: 283 more bytes on this line]
<hit ref="HEAD" tip="33f9f7be2" date="2026-08-08" p="bench/recalleval/snapshot.mdpack" l="14521" kind="ref" t="&lt;hit ref=&quot;HEAD&quot; tip=&quot;bc09d0260&quot; date=&quot;2026-08-01&quot; p=&quot;docs/captures/COMMANDS_showcase_2026-08-01.md&quot; l=&quot;2219&quot; kind=&quot;ref&quot; t=&quo … [line truncated: 272 more bytes on this line]
<hit ref="HEAD" tip="33f9f7be2" date="2026-08-08" p="test/showcase_capture.py" l="225" kind="ref" t="add(S4, f&quot;{BIN} . --whereis=computeOnePairOverlap --with-history&quot;, &quot;Same, plus a git-history &lt;fate&gt; row (never / removed-by-commit) for names no tree carries.&quot;, timeout=600) … [line truncated: 3 more bytes on this line]
<hit ref="HEAD" tip="33f9f7be2" date="2026-08-08" p="docs/captures/COMMANDS_showcase_2026-08-08.md" l="2276" kind="ref" t="## `./build/ripwire . --whereis=computeOnePairOverlap --with-history`"/>
<hit ref="HEAD" tip="33f9f7be2" date="2026-08-08" p="docs/captures/COMMANDS_showcase_2026-08-08.md" l="2284" kind="ref" t="&lt;whereis sym=&quot;computeOnePairOverlap&quot; on-head=&quot;1&quot; refs_scanned=&quot;93&quot; blobs=&quot;2087&quot; hits=&quot;1647&quot; head_labels=&quot;index&quot; sh … [line truncated: 71 more bytes on this line]
<hit ref="HEAD" tip="33f9f7be2" date="2026-08-08" p="docs/captures/COMMANDS_showcase_2026-08-08.md" l="2286" kind="ref" t="&lt;fate sym=&quot;computeOnePairOverlap&quot; v=&quot;removed&quot; commit=&quot;977ed77f4&quot; date=&quot;2026-08-01&quot; p=&quot;docs/captures/COMMANDS_showcase_2026-08-01. … [line truncated: 169 more bytes on this line]
<hit ref="HEAD" tip="33f9f7be2" date="2026-08-08" p="docs/captures/COMMANDS_showcase_2026-08-08.md" l="2287" kind="ref" t="&lt;hit ref=&quot;HEAD&quot; tip=&quot;89aeddd0d&quot; date=&quot;2026-08-08&quot; p=&quot;src/mergescout.h&quot; l=&quot;530&quot; kind=&quot;def&quot; t=&quot;inline PairOverl … [line truncated: 120 more bytes on this line]
<hit ref="HEAD" tip="33f9f7be2" date="2026-08-08" p="docs/captures/COMMANDS_showcase_2026-08-08.md" l="2288" kind="ref" t="&lt;hit ref=&quot;HEAD&quot; tip=&quot;89aeddd0d&quot; date=&quot;2026-08-08&quot; p=&quot;src/lanes.h&quot; l=&quot;17&quot; kind=&quot;ref&quot; t=&quot;// and the landing ord … [line truncated: 102 more bytes on this line]
<hit ref="HEAD" tip="33f9f7be2" date="2026-08-08" p="docs/captures/COMMANDS_showcase_2026-08-08.md" l="2289" kind="ref" t="&lt;hit ref=&quot;HEAD&quot; tip=&quot;89aeddd0d&quot; date=&quot;2026-08-08&quot; p=&quot;src/lanes.h&quot; l=&quot;64&quot; kind=&quot;ref&quot; t=&quot;//   same_file_risk[]  … [line truncated: 104 more bytes on this line]
<hit ref="HEAD" tip="33f9f7be2" date="2026-08-08" p="docs/captures/COMMANDS_showcase_2026-08-08.md" l="2290" kind="ref" t="&lt;hit ref=&quot;HEAD&quot; tip=&quot;89aeddd0d&quot; date=&quot;2026-08-08&quot; p=&quot;src/mergescout.h&quot; l=&quot;557&quot; kind=&quot;ref&quot; t=&quot;pairs.push_back( … [line truncated: 65 more bytes on this line]
<hit ref="HEAD" tip="33f9f7be2" date="2026-08-08" p="docs/captures/COMMANDS_showcase_2026-08-08.md" l="2291" kind="ref" t="&lt;hit ref=&quot;HEAD&quot; tip=&quot;89aeddd0d&quot; date=&quot;2026-08-08&quot; p=&quot;bench/nestcal/r1-2026-08-07/post-ripwire-src.tsv&quot; l=&quot;1588&quot; kind=&quot;r … [line truncated: 133 more bytes on this line]
… [36 more display lines; full output is 26664 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --flags`

*The dark-content dashboard: gates BUILT but OFF. CHANGED: no longer invents gates from comments/heredocs, so the count only reflects real ifndef/define, CMake option(), and getenv gates.*

`````
<!-- ripwire flags: what is BUILT but DARK here. Three gate patterns in one report: ifndef/define header gates (kind="compile"), CMake option() switches (kind="cmake"), and getenv reads (kind="env", default unset). dark="1" means the default keeps the guarded code out of the build; regions/loc size what it turns off. When one name is BOTH a header gate and a CMake option the CMake default wins (that is what the build passes) and the header shows as an also row. Lexical, not preprocessed: this reports the in-repo default, never the value your build used. dark_gates on this root is the COUNT of dark gates; it was spelled dark until that collided with the child bool. files= is THIS verb's own harvest scan (source + CMakeLists files it read looking for gates) — a wider crawl than the map's indexed corpus, so it will not equal the map's files= -->
<flags gates="55" dark_gates="49" compile="11" cmake="11" env="33" files="1084">
<gate name="FIXTURE_DARK_FEATURE" kind="compile" default="0" dark="1" regions="2" loc="13" reads="2" p="test/flagsfix/wiringFlags.h" l="10">
<read p="test/flagsfix/feature.cpp" l="10"/>
<read p="test/flagsfix/sub/nested.cpp" l="5"/>
</gate>
<gate name="PROFILE_PMC_VERBOSE" kind="compile" default="0" dark="1" regions="2" loc="10" reads="2" p="src/infra/profilePmc.h" l="76">
<read p="src/infra/profilePmc.h" l="79"/>
<read p="src/infra/profilePmc.h" l="435"/>
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
<gate name="PROFILE_BARRIER" kind="compile" default="0" dark="1" regions="1" loc="3" reads="1" p="src/infra/profileScope.h" l="58">
<read p="src/infra/profileScope.h" l="127"/>
</gate>
<gate name="FIXTURE_CMAKE_DARK" kind="cmake" default="OFF" dark="1" regions="1" loc="1" reads="3" p="test/flagsfix/CMakeLists.txt" l="4">
<read p="test/flagsfix/CMakeLists.txt" l="4"/>
<read p="test/flagsfix/CMakeLists.txt" l="10"/>
<read p="test/flagsfix/override.h" l="13"/>
… [213 more display lines; full output is 13684 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --flags --flip=RIPWIRE_ASAN`

*Blast radius of turning ONE gate on: live code, symbols, transitive reach, covering tests.*

`````
<!-- ripwire flip: the blast radius of turning ONE gate ON. lights = the code that becomes live: r rows are #if regions, b rows are C++ branch sites (a gate read as a VALUE through a constexpr bool, via= names the binding). hosts = the indexed defs that code sits inside; downstream = what those defs transitively CALL (what starts executing); dependents = what transitively calls THEM. tests = test files reaching the hosts; untested = hosts no test reaches (the honest is it safe answer). An alias MASTER rolls its children in (member rows); flipping a CHILD lights only that child and names its parent. kind=cmake also steers the BUILD graph, which no C++ side analysis follows: those sites are c rows. kind=env is RUNTIME (runtime=1) so every row is conditional at its read. Lexical and single line, never preprocessed: the value lane reads C family source only and treats a file declaring its OWN constant of that name as shadowing the gate's, but a third header's same named constant (included, not redeclared) would still count. A lit site inside no indexed def counts into filescope instead of a host. UNIT: untested= here counts HOSTS (indexed defs this gate lights that no test reaches). The test gate verb spells untested= over impacted SYMBOLS and the seams verb over cross-directory call EDGES, so the three numbers count three different things and must never be compared or summed across verbs. -->
<flip gate="RIPWIRE_ASAN" kind="cmake" default="OFF" dark="1" runtime="0" p="CMakeLists.txt" l="14" family="1" regions="0" loc="0" branches="0" bindings="0" hosts="0" filescope="0" downstream="0" dependents="0" tests="0" untested="0" files="1084">
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
<c p="CMakeLists.txt" l="690"/>
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
{"v":1,"verb":"plan-lanes","at":"33f9f7be2","root":".","task":"add a --since filter to the doc-drift verb and cover it with tests","source":"partition","requested":3,"lane_count":3,"claim_key":"path+scope+name","on_conflict":"producing-lane-rebases","corpus":{"files":1081,"symbols":8835,"edges":1048 … [line truncated: 347 more bytes on this line]
"symbols":[{"p":"./src/docdrift.h","n":"computeDocDrift","scope":"docdrift","l":2162,"id":"./src/docdrift.h::docdrift::computeDocDrift"},
{"p":"./src/docdrift.h","n":"writeDocDriftPage","scope":"docdrift","l":2494,"id":"./src/docdrift.h::docdrift::writeDocDriftPage"},
{"p":"./src/docdrift.h","n":"writeGateability","scope":"docdrift","l":2370,"id":"./src/docdrift.h::docdrift::writeGateability"},
{"p":"./src/main.cpp","n":"runDocDrift","scope":"","l":7535,"id":null},
{"p":"./src/mcpverbs.h","n":"docDriftText","scope":"rw","l":451,"id":"./src/mcpverbs.h::rw::docDriftText"},
{"p":"./src/recall.h","n":"docFileMask","scope":"rw","l":102,"id":"./src/recall.h::rw::docFileMask"}]},"lanes":[{"id":"lane-0","task":"add a --since filter to the doc-drift verb and cover it with tests","claims":{"symbols":[{"p":"./src/mcp.h","n":"isMcpEditVerb","scope":"rw","key":"29a5a2524a95d6c2" … [line truncated: 157 more bytes on this line]
{"p":"./src/mcprefusal.h","n":"notFound","scope":"rw::mcprefuse","key":"2f350cb55c4c61ac","id":"./src/mcprefusal.h::rw::mcprefuse::notFound","id_addressable":true,"id_collides_with":0,"l":677,"ord":0,"overloads":1,"amb":2,"cx":4,"ccx":3,"churn":5,"tested":0},
{"p":"./src/mcpverbs.h","n":"whereisText","scope":"rw","key":"39588f57bd7b46b5","id":"./src/mcpverbs.h::rw::whereisText","id_addressable":true,"id_collides_with":0,"l":405,"ord":0,"overloads":1,"amb":0,"cx":2,"ccx":1,"churn":9,"tested":0},
{"p":"./src/mcpverbs.h","n":"EditCheckReply","scope":"EditCheckReply","key":"4bd88db964d5c07a","id":"./src/mcpverbs.h::EditCheckReply::EditCheckReply","id_addressable":true,"id_collides_with":0,"l":2374,"ord":0,"overloads":1,"amb":0,"cx":0,"ccx":0,"churn":9,"tested":0},
{"p":"./src/cli.h","n":"printUsage","scope":"rw","key":"95122ff5fa6c90b5","id":"./src/cli.h::rw::printUsage","id_addressable":true,"id_collides_with":0,"l":617,"ord":0,"overloads":1,"amb":0,"cx":1,"ccx":0,"churn":45,"tested":0},
{"p":"./src/darkflags.h","n":"isIdentShaped","scope":"darkflags","key":"98a73b9725100265","id":"./src/darkflags.h::darkflags::isIdentShaped","id_addressable":true,"id_collides_with":0,"l":153,"ord":0,"overloads":1,"amb":0,"cx":7,"ccx":7,"churn":5,"tested":0},
{"p":"./src/situ.h","n":"gitDiffChangedMask","scope":"rw","key":"a9243123d6bed37b","id":"./src/situ.h::rw::gitDiffChangedMask","id_addressable":true,"id_collides_with":0,"l":55,"ord":0,"overloads":1,"amb":0,"cx":1,"ccx":0,"churn":5,"tested":0},
{"p":"./src/mcp.h","n":"dispatchMcpLine","scope":"rw","key":"d63db6944aa504a7","id":"./src/mcp.h::rw::dispatchMcpLine","id_addressable":true,"id_collides_with":0,"l":333,"ord":0,"overloads":1,"amb":134,"cx":220,"ccx":422,"churn":8,"tested":0},
{"p":"./src/mcpverbs.h","n":"McpIntArg","scope":"McpIntArg","key":"df109df71b7b36f2","id":"./src/mcpverbs.h::McpIntArg::McpIntArg","id_addressable":true,"id_collides_with":0,"l":59,"ord":0,"overloads":1,"amb":0,"cx":0,"ccx":0,"churn":9,"tested":0},
{"p":"./src/mcpverbs.h","n":"unknownSubVerbRefusal","scope":"rw","key":"e336d39b0a6addea","id":"./src/mcpverbs.h::rw::unknownSubVerbRefusal","id_addressable":true,"id_collides_with":0,"l":2811,"ord":0,"overloads":1,"amb":5,"cx":3,"ccx":2,"churn":9,"tested":0},
{"p":"./src/mcpjson.h","n":"RawValue","scope":"RawValue","key":"ea29179c521d535c","id":"./src/mcpjson.h::RawValue::RawValue","id_addressable":true,"id_collides_with":0,"l":551,"ord":0,"overloads":1,"amb":0,"cx":0,"ccx":0,"churn":5,"tested":0},
{"p":"./src/gitoracle.h","n":"fateOf","scope":"HistoryIndex","key":"f3e7683b7a6fd595","id":"./src/gitoracle.h::HistoryIndex::fateOf","id_addressable":true,"id_collides_with":0,"l":166,"ord":0,"overloads":1,"amb":1,"cx":6,"ccx":4,"churn":5,"tested":0}],
"files":[{"p":"./src/cli.h","symbols":1,"churn":45,"ccx":0,"hotspot_rank":5},
{"p":"./src/darkflags.h","symbols":1,"churn":5,"ccx":7,"hotspot_rank":23},
{"p":"./src/gitoracle.h","symbols":1,"churn":5,"ccx":4,"hotspot_rank":51},
{"p":"./src/mcp.h","symbols":2,"churn":8,"ccx":425,"hotspot_rank":10},
{"p":"./src/mcpjson.h","symbols":1,"churn":5,"ccx":0,"hotspot_rank":31},
{"p":"./src/mcprefusal.h","symbols":1,"churn":5,"ccx":3,"hotspot_rank":34},
{"p":"./src/mcpverbs.h","symbols":4,"churn":9,"ccx":3,"hotspot_rank":7},
{"p":"./src/situ.h","symbols":1,"churn":5,"ccx":0,"hotspot_rank":40}]},"blast_radius":{"reaches":56,"files_total":12,"capped":false,"files":["./src/cli.h","./src/crossref.h","./src/darkflags.h","./src/docdrift.h","./src/flipimpact.h","./src/handoff.h","./src/main.cpp","./src/mcp.h","./src/mcpedit.h" … [line truncated: 79 more bytes on this line]
"tests_total":0,"tests_capped":false,"tests_granularity":"claimed-symbols","untested":56,"module_span":6,"notes":[]},
{"id":"lane-1","task":"add a --since filter to the doc-drift verb and cover it with tests","claims":{"symbols":[{"p":"./src/gitmine.h","n":"gitWindowBoundarySha","scope":"rw","key":"18627516699d7062","id":"./src/gitmine.h::rw::gitWindowBoundarySha","id_addressable":true,"id_collides_with":0,"l":1175 … [line truncated: 68 more bytes on this line]
{"p":"./src/cli.h","n":"pagingDisablingMode","scope":"rw","key":"1d13d5061cd1bb7d","id":"./src/cli.h::rw::pagingDisablingMode","id_addressable":true,"id_collides_with":0,"l":2230,"ord":0,"overloads":1,"amb":0,"cx":7,"ccx":6,"churn":45,"tested":0},
{"p":"./src/docdrift.h","n":"DriftResult","scope":"DriftResult","key":"422ab39546b6e0bd","id":"./src/docdrift.h::DriftResult::DriftResult","id_addressable":true,"id_collides_with":0,"l":257,"ord":0,"overloads":1,"amb":0,"cx":0,"ccx":0,"churn":6,"tested":0},
… [76 more display lines; full output is 19926 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --plan-lanes --brief=<scratch>/aux/lanes_brief.txt`

*NEW VERB, explicit form: one line per lane, lane boundaries are the ones you wrote (the defensible mode).*

Input file:

`````
add a --since filter to the doc-drift verb
add the CLI parse arm and help text for the new filter
write regression tests for the new filter
`````

`````
{"v":1,"verb":"plan-lanes","at":"33f9f7be2","root":".","task":null,"source":"brief","requested":3,"lane_count":3,"claim_key":"path+scope+name","on_conflict":"producing-lane-rebases","corpus":{"files":1081,"symbols":8835,"edges":10480,"ambiguous":3045,"unresolved":1326},"carve":null,"core":{"files":[ … [line truncated: 2 more bytes on this line]
"symbols":[]},"lanes":[{"id":"lane-0","task":"add a --since filter to the doc-drift verb","claims":{"symbols":[{"p":"./src/mcpverbs.h","n":"docDriftText","scope":"rw","key":"1fa68e8d93c05a59","id":"./src/mcpverbs.h::rw::docDriftText","id_addressable":true,"id_collides_with":0,"l":451,"ord":0,"overlo … [line truncated: 52 more bytes on this line]
{"p":"./src/recall.h","n":"docFileMask","scope":"rw","key":"3149a219f599664c","id":"./src/recall.h::rw::docFileMask","id_addressable":true,"id_collides_with":0,"l":102,"ord":0,"overloads":1,"amb":0,"cx":4,"ccx":4,"churn":6,"tested":0},
{"p":"./src/docdrift.h","n":"writeDocDriftPage","scope":"docdrift","key":"380b7de5df1cfd73","id":"./src/docdrift.h::docdrift::writeDocDriftPage","id_addressable":true,"id_collides_with":0,"l":2494,"ord":0,"overloads":1,"amb":2,"cx":9,"ccx":10,"churn":6,"tested":0},
{"p":"./src/docdrift.h","n":"computeDocDrift","scope":"docdrift","key":"3b19cc3d8996c3b2","id":"./src/docdrift.h::docdrift::computeDocDrift","id_addressable":true,"id_collides_with":0,"l":2162,"ord":0,"overloads":1,"amb":3,"cx":20,"ccx":33,"churn":6,"tested":0},
{"p":"./src/docdrift.h","n":"DriftResult","scope":"DriftResult","key":"422ab39546b6e0bd","id":"./src/docdrift.h::DriftResult::DriftResult","id_addressable":true,"id_collides_with":0,"l":257,"ord":0,"overloads":1,"amb":0,"cx":0,"ccx":0,"churn":6,"tested":0},
{"p":"./src/docdrift.h","n":"writeGateability","scope":"docdrift","key":"42c456dfb55faee4","id":"./src/docdrift.h::docdrift::writeGateability","id_addressable":true,"id_collides_with":0,"l":2370,"ord":0,"overloads":1,"amb":0,"cx":6,"ccx":6,"churn":6,"tested":0},
{"p":"./src/docdrift.h","n":"writeDocDrift","scope":"docdrift","key":"7bbf4862e91b5d48","id":"./src/docdrift.h::docdrift::writeDocDrift","id_addressable":true,"id_collides_with":0,"l":2573,"ord":0,"overloads":1,"amb":0,"cx":1,"ccx":0,"churn":6,"tested":0},
{"p":"./src/main.cpp","n":"scanReportVerbPrecedence","scope":"","key":"9ab981e987e8108e","id":null,"id_addressable":false,"id_collides_with":0,"l":10503,"ord":0,"overloads":1,"amb":24,"cx":7,"ccx":10,"churn":65,"tested":0},
{"p":"./src/docdrift.h","n":"sortDocsByLiveDrift","scope":"docdrift","key":"d5de682411b9a9a9","id":"./src/docdrift.h::docdrift::sortDocsByLiveDrift","id_addressable":true,"id_collides_with":0,"l":2150,"ord":0,"overloads":1,"amb":2,"cx":2,"ccx":2,"churn":6,"tested":0},
{"p":"./src/mcpverbs.h","n":"unknownSubVerbRefusal","scope":"rw","key":"e336d39b0a6addea","id":"./src/mcpverbs.h::rw::unknownSubVerbRefusal","id_addressable":true,"id_collides_with":0,"l":2811,"ord":0,"overloads":1,"amb":5,"cx":3,"ccx":2,"churn":9,"tested":0},
{"p":"./src/main.cpp","n":"runDocDrift","scope":"","key":"ebf80a749e6eca28","id":null,"id_addressable":false,"id_collides_with":0,"l":7535,"ord":0,"overloads":1,"amb":0,"cx":4,"ccx":3,"churn":65,"tested":0},
{"p":"./src/cli.h","n":"validateModifierGuards","scope":"rw","key":"ec2848a4801493a2","id":"./src/cli.h::rw::validateModifierGuards","id_addressable":true,"id_collides_with":0,"l":2547,"ord":0,"overloads":1,"amb":16,"cx":43,"ccx":34,"churn":45,"tested":0}],
"files":[{"p":"./src/cli.h","symbols":1,"churn":45,"ccx":34,"hotspot_rank":5},
{"p":"./src/docdrift.h","symbols":6,"churn":6,"ccx":51,"hotspot_rank":13},
{"p":"./src/main.cpp","symbols":2,"churn":65,"ccx":13,"hotspot_rank":1},
{"p":"./src/mcpverbs.h","symbols":2,"churn":9,"ccx":2,"hotspot_rank":7},
{"p":"./src/recall.h","symbols":1,"churn":6,"ccx":4,"hotspot_rank":41}]},"blast_radius":{"reaches":12,"files_total":6,"capped":false,"files":["./src/cli.h","./src/main.cpp","./src/mcp.h","./src/mcpserver.h","./src/mcpverbs.h","./src/recall.h"]},"tests_to_run":[],
"tests_total":0,"tests_capped":false,"tests_granularity":"claimed-symbols","untested":12,"module_span":9,"notes":[]},
{"id":"lane-1","task":"add the CLI parse arm and help text for the new filter","claims":{"symbols":[{"p":"./scripts/optremarks.py","n":"main","scope":"","key":"01b3b880f77d1512","id":null,"id_addressable":false,"id_collides_with":56,"l":178,"ord":0,"overloads":1,"amb":0,"cx":23,"ccx":31,"churn":1,"t … [line truncated: 10 more bytes on this line]
{"p":"./src/main.cpp","n":"runNotes","scope":"","key":"1f218712fab4409e","id":null,"id_addressable":false,"id_collides_with":0,"l":6740,"ord":0,"overloads":1,"amb":11,"cx":26,"ccx":54,"churn":65,"tested":0},
{"p":"./docs/docs_commands_build.py","n":"assert_scrubbed","scope":"","key":"3f2f96d107d3b9c2","id":null,"id_addressable":false,"id_collides_with":0,"l":479,"ord":0,"overloads":1,"amb":0,"cx":5,"ccx":8,"churn":5,"tested":0},
{"p":"./docs/docs_commands_build.py","n":"main","scope":"","key":"4015853681ded3bc","id":null,"id_addressable":false,"id_collides_with":56,"l":527,"ord":0,"overloads":1,"amb":0,"cx":19,"ccx":28,"churn":5,"tested":0},
{"p":"./docs/docs_commands_build.py","n":"scrub_prose","scope":"","key":"6846061c73b4f780","id":null,"id_addressable":false,"id_collides_with":0,"l":272,"ord":0,"overloads":1,"amb":0,"cx":1,"ccx":0,"churn":5,"tested":0},
{"p":"./src/main.cpp","n":"deadCodeFilterMatchesPath","scope":"","key":"6d33ddb6fcd29699","id":null,"id_addressable":false,"id_collides_with":0,"l":4801,"ord":0,"overloads":1,"amb":1,"cx":11,"ccx":12,"churn":65,"tested":0},
{"p":"./src/docparse.h","n":"classifyGeneratedDoc","scope":"docparse","key":"8d10cf7eab7a73cd","id":"./src/docparse.h::docparse::classifyGeneratedDoc","id_addressable":true,"id_collides_with":0,"l":675,"ord":0,"overloads":1,"amb":0,"cx":7,"ccx":6,"churn":4,"tested":0},
{"p":"./src/naminglens.h","n":"checkLocalNameShape","scope":"detail","key":"91743d16930d33a4","id":"./src/naminglens.h::detail::checkLocalNameShape","id_addressable":true,"id_collides_with":0,"l":669,"ord":0,"overloads":1,"amb":0,"cx":7,"ccx":7,"churn":9,"tested":0},
{"p":"./docs/docs_commands_build.py","n":"parse_capture","scope":"","key":"be71bf499e18d319","id":null,"id_addressable":false,"id_collides_with":0,"l":199,"ord":0,"overloads":1,"amb":0,"cx":18,"ccx":25,"churn":5,"tested":0},
{"p":"./src/ingest.cpp","n":"ev_appendCtrl","scope":"","key":"cd99c9b90295a822","id":null,"id_addressable":false,"id_collides_with":0,"l":2629,"ord":0,"overloads":1,"amb":0,"cx":12,"ccx":14,"churn":43,"tested":0},
{"p":"./src/notes.h","n":"addNote","scope":"rw::notes","key":"d9c0d39c0c407b7e","id":"./src/notes.h::rw::notes::addNote","id_addressable":true,"id_collides_with":0,"l":359,"ord":0,"overloads":1,"amb":0,"cx":9,"ccx":6,"churn":5,"tested":0},
… [50 more display lines; full output is 16271 bytes on 1 raw line(s)]
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
<layout sym="Symbol" found="1" defs="1" mirror="single" asserts="1" conflicts="0" scanned="332">
<def p="./src/model.h" l="150" agg="struct" modeled="0" fields="22">
<f n="id" ty="NodeId" as="std::uint32_t" sz="4" al="4" off="0"/>
<f n="kind" ty="SymKind" as="std::uint8_t" sz="1" al="1" off="4"/>
<f n="lang" ty="Lang" as="std::uint8_t" sz="1" al="1" off="5"/>
<f n="ppAlt" ty="std::uint16_t" sz="2" al="2" off="6"/>
<f n="fileId" ty="std::uint32_t" sz="4" al="4" off="8"/>
<f n="line" ty="std::uint32_t" sz="4" al="4" off="12"/>
<f n="sigStartByte" ty="std::uint32_t" sz="4" al="4" off="16"/>
<f n="sigEndByte" ty="std::uint32_t" sz="4" al="4" off="20"/>
<f n="endByte" ty="std::uint32_t" sz="4" al="4" off="24"/>
<f n="cx" ty="std::uint32_t" sz="4" al="4" off="28"/>
<f n="ccx" ty="std::uint32_t" sz="4" al="4" off="32"/>
<f n="loc" ty="std::uint32_t" sz="4" al="4" off="36"/>
<f n="locals" ty="std::uint32_t" sz="4" al="4" off="40"/>
<f n="humps" ty="std::uint16_t" sz="2" al="2" off="44"/>
<f n="deepLoc" ty="std::uint16_t" sz="2" al="2" off="46"/>
<f n="ev" ty="std::uint16_t" sz="2" al="2" off="48"/>
<f n="evWhy" ty="std::array&lt;std::uint8_t, kEvWhyTagCount&gt;" sized="0"/>
<f n="params" ty="std::uint16_t" sz="2" al="2"/>
<f n="maxNest" ty="std::uint8_t" sz="1" al="1"/>
<f n="arityExact" ty="std::uint8_t" sz="1" al="1"/>
<f n="name" ty="std::string" sized="0"/>
<f n="scope" ty="std::string" sized="0"/>
<caveat k="compound-type" d="evWhy: std::array&lt;std::uint8_t, kEvWhyTagCount&gt;"/>
<caveat k="unknown-type" d="evWhy: std::array&lt;std::uint8_t, kEvWhyTagCount&gt;" count="3"/>
</def>
<assert p="./src/model.h" l="295" kind="mention" t="static_assert( sizeof( Symbol ) == 64 + 2 * sizeof( std::string ), &quot;Symbol size changed — verify the new field uses the smallest type + is grouped (SoA); see model.h&quot; )"/>
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
<doc-drift docs="117" clean="105" anchors="936" checked="245" unchecked="691" drift="19" dated="10" prose="7" corpus="1103" at="33f9f7be2">
<doc p="test/docdriftfix/NOTES.md" anchors="26" checked="15" drift="6" dated="0">
<a k="file-line" l="9" c="64" why="line-moved" ref="code.h:23" sym="stableHelper" got="movedHelper" tgt="test/docdriftfix/code.h:17"/>
<a k="file-line" l="10" c="58" why="past-eof" ref="code.h:900" sym="stableHelper" got="27 lines" tgt="test/docdriftfix/code.h"/>
<a k="file-line" l="11" c="53" why="missing-file" ref="deletedFile.h:12"/>
<a k="const" l="26" c="29" why="const-value" ref="kDriftedLimit = 10" want="10" got="15" tgt="test/docdriftfix/code.h:11"/>
<a k="array" l="28" c="49" why="array-extent" ref="kDriftedTable[16]" want="16" got="18" tgt="test/docdriftfix/code.h:14"/>
<a k="array" l="29" c="61" why="array-extent" ref="[16]" want="16" got="18" tgt="test/docdriftfix/code.h:14"/>
</doc>
<doc p="docs/COMMANDS.md" anchors="47" checked="4" drift="4" dated="0">
<a k="const" l="2144" c="51" why="const-value" ref="kDriftedLimit = 10" want="10" got="15" tgt="test/docdriftfix/code.h:11"/>
<a k="array" l="2145" c="52" why="array-extent" ref="kDriftedTable[16]" want="16" got="18" tgt="test/docdriftfix/code.h:14"/>
<a k="const" l="2182" c="51" why="const-value" ref="kDriftedLimit = 10" want="10" got="15" tgt="test/docdriftfix/code.h:11"/>
<a k="array" l="2183" c="52" why="array-extent" ref="kDriftedTable[16]" want="16" got="18" tgt="test/docdriftfix/code.h:14"/>
</doc>
<doc p="test/docdriftfix/live_notes.md" anchors="2" checked="2" drift="2" dated="0">
<a k="file-line" l="10" c="36" why="past-eof" ref="code.h:906" got="27 lines" tgt="test/docdriftfix/code.h"/>
<a k="file-line" l="17" c="36" why="past-eof" ref="code.h:907" got="27 lines" tgt="test/docdriftfix/code.h"/>
</doc>
<doc p="test/gateabilityfix/UNDATED.md" anchors="4" checked="4" drift="2" dated="0">
<a k="symbol" l="3" c="17" why="undefined" ref="deletedFn1"/>
<a k="symbol" l="4" c="17" why="undefined" ref="deletedFn2"/>
</doc>
<doc p="CONTRIBUTING.md" anchors="33" checked="4" drift="1" dated="0">
<a k="symbol" l="204" c="51" why="undefined" ref="hasNext"/>
</doc>
<doc p="PLAN.md" anchors="67" checked="37" drift="1" dated="1">
<a k="file-line" l="407" c="63" why="line-moved" kind="dated-record" rec="block" ref="naminglens.h:526" sym="checkNameShape" got="(file scope)" tgt="src/naminglens.h:618"/>
<a k="file-line" l="553" c="81" why="line-moved" ref="ingest.cpp:7175" sym="astQuery" got="operator=" tgt="src/ingest.cpp:8982"/>
… [38 more display lines; full output is 11363 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --doc-drift --gateability`

*The finishable to-do list: docs whose LIVE failing anchors a date-stamp would reclassify.*

`````
<!-- ripwire doc drift: the CHECKABLE anchors in this repo's markdown, verified against the live index, reporting only the ones that no longer hold. Four kinds: file:line refs (missing-file / past-eof / line-moved, the last only when the doc names a symbol on that line), backticked symbol mentions (undefined), `= N` constants and `[N]` array extents (value/extent vs the declaration). Every lane under reports on purpose: a name is stale only when it occurs NOWHERE in the code as an identifier, and a number is compared only against a declaration shaped literal the corpus binds uniquely. checked + unchecked == anchors: nothing is dropped silently, and the unchecked rows say what was not proved. Read why="undefined" precisely: it says the name is defined NOWHERE in this repo, which is not the same as DELETED — in a plan or design doc naming work not yet built, that is expected rather than rot. Run with the with_history flag to have git history separate the two: the lane then reports why="deleted" with the commit that removed the name, and downgrades a name this repo never had to unchecked r="never in history". A failed anchor the AUTHOR DATED is split out as kind="dated-record" and counted in dated= rather than drift=: an audit finding, a ledger row or an as-of-DATE hedge records what was true then, so drift= is the LIVE rot and drift + dated is every anchor that no longer holds. rec= names the evidence (line / block / title / stamp), and a doc that never writes its own date anywhere a machine can read reports LIVE — the lane reads dating marks, it does not guess genre. Attribute vocabulary, one name one meaning: at= appears ONLY on this root element and is the commit the run was measured against (short sha, plus dirty when the tree had uncommitted changes); ref= is the anchor as the DOC writes it; got= is what the corpus actually says; and tgt= is the corpus SITE backing got= (a path, or path:line). On the <a/> rows k= and kind= are DIFFERENT things and both are kept: k= is the ANCHOR kind (file-line / symbol / const / array), kind= is the record classification (dated-record). k= cannot be renamed to kind= here for the obvious reason that kind= is already taken on the same element; note that in the ranked map the same k= spelling is a PageRank score instead. Docs are ordered by LIVE drift descending (path breaks ties), so the worst rot leads and a fully dated doc, which is drift zero by construction, sinks on the same key. Prose claims, Status lines and dates are NOT checked. FOUR COUNTERS on this element name four DIFFERENT populations, stated here because one of them openly disagrees with a number the map reports elsewhere. docs= is the DOCUMENTS scanned for anchors (markdown by extension, after any filter); it is the denominator of the doc rows below. clean= is how many of those docs came out with NO failed anchor — drift and dated both zero for that doc — so docs minus clean is exactly the number of <doc> rows below, before any paging window is applied. A doc whose anchors were all unchecked, or all prose, is clean here: clean means nothing was found rotten, not that everything was verified. prose= is the anchors dropped as prose, so it is SUBTRACTED from anchors= rather than added to it, and the verb does not claim to have checked them; only the VALUE shapes (`= N` and `[N]`) can be dropped this way, and the drop is itself a corpus lookup — the name was searched for and not found in code — not a pre-check guess. corpus= is the file population the anchors were checked AGAINST, and it is its OWN population rather than a relation to the map's files=: the indexed files this walk could re-read, PLUS a fixed set of config, shader and build-file extensions (CMakeLists.txt, .cmake, .yml/.yaml, .toml, .metal/.glsl/.hlsl and the like — an extension whitelist, never a content sniff), MINUS every file this walk could not open or that exceeded its own 4 MiB read ceiling, which is dropped silently and never counted. So corpus= is USUALLY larger than files= and that is the normal case, but it is not always: a crawl run whose max file size ceiling was raised above 4 MiB indexes files this walk still refuses, and a file the index lists but this run cannot open is counted by one and not the other. Neither number is wrong. corpus="0" means the corpus scan never ran at all, which happens only when the docs raised no anchor SHAPE whatsoever — prose ones included — so anchors="0" beside a non-zero prose= still scanned, and still reports the corpus it scanned. -->
<doc-drift docs="117" clean="105" anchors="936" checked="245" unchecked="691" drift="19" dated="10" prose="7" corpus="1103" at="33f9f7be2">
<doc p="test/docdriftfix/NOTES.md" anchors="26" checked="15" drift="6" dated="0">
<a k="file-line" l="9" c="64" why="line-moved" ref="code.h:23" sym="stableHelper" got="movedHelper" tgt="test/docdriftfix/code.h:17"/>
<a k="file-line" l="10" c="58" why="past-eof" ref="code.h:900" sym="stableHelper" got="27 lines" tgt="test/docdriftfix/code.h"/>
<a k="file-line" l="11" c="53" why="missing-file" ref="deletedFile.h:12"/>
<a k="const" l="26" c="29" why="const-value" ref="kDriftedLimit = 10" want="10" got="15" tgt="test/docdriftfix/code.h:11"/>
<a k="array" l="28" c="49" why="array-extent" ref="kDriftedTable[16]" want="16" got="18" tgt="test/docdriftfix/code.h:14"/>
<a k="array" l="29" c="61" why="array-extent" ref="[16]" want="16" got="18" tgt="test/docdriftfix/code.h:14"/>
</doc>
<doc p="docs/COMMANDS.md" anchors="47" checked="4" drift="4" dated="0">
<a k="const" l="2144" c="51" why="const-value" ref="kDriftedLimit = 10" want="10" got="15" tgt="test/docdriftfix/code.h:11"/>
<a k="array" l="2145" c="52" why="array-extent" ref="kDriftedTable[16]" want="16" got="18" tgt="test/docdriftfix/code.h:14"/>
<a k="const" l="2182" c="51" why="const-value" ref="kDriftedLimit = 10" want="10" got="15" tgt="test/docdriftfix/code.h:11"/>
<a k="array" l="2183" c="52" why="array-extent" ref="kDriftedTable[16]" want="16" got="18" tgt="test/docdriftfix/code.h:14"/>
</doc>
<doc p="test/docdriftfix/live_notes.md" anchors="2" checked="2" drift="2" dated="0">
<a k="file-line" l="10" c="36" why="past-eof" ref="code.h:906" got="27 lines" tgt="test/docdriftfix/code.h"/>
<a k="file-line" l="17" c="36" why="past-eof" ref="code.h:907" got="27 lines" tgt="test/docdriftfix/code.h"/>
</doc>
<doc p="test/gateabilityfix/UNDATED.md" anchors="4" checked="4" drift="2" dated="0">
<a k="symbol" l="3" c="17" why="undefined" ref="deletedFn1"/>
<a k="symbol" l="4" c="17" why="undefined" ref="deletedFn2"/>
</doc>
<doc p="CONTRIBUTING.md" anchors="33" checked="4" drift="1" dated="0">
<a k="symbol" l="204" c="51" why="undefined" ref="hasNext"/>
</doc>
<doc p="PLAN.md" anchors="67" checked="37" drift="1" dated="1">
<a k="file-line" l="407" c="63" why="line-moved" kind="dated-record" rec="block" ref="naminglens.h:526" sym="checkNameShape" got="(file scope)" tgt="src/naminglens.h:618"/>
<a k="file-line" l="553" c="81" why="line-moved" ref="ingest.cpp:7175" sym="astQuery" got="operator=" tgt="src/ingest.cpp:8982"/>
… [50 more display lines; full output is 12599 bytes on 1 raw line(s)]
`````

Tail of the same output — the `<gateability>` section:

`````
<gateability docs="9" projected_drift="0">
<fix p="test/docdriftfix/NOTES.md" live="6"/>
<fix p="docs/COMMANDS.md" live="4"/>
<fix p="test/docdriftfix/live_notes.md" live="2"/>
<fix p="test/gateabilityfix/UNDATED.md" live="2"/>
<fix p="CONTRIBUTING.md" live="1"/>
<fix p="PLAN.md" live="1"/>
<fix p="docs/EVALS.md" live="1"/>
<fix p="test/docdriftfix/record_line.md" live="1"/>
<fix p="test/gateabilityfix/MIXED.md" live="1"/>
</gateability>
</doc-drift>
`````

## `./build/ripwire . --doc-drift --with-history`

*Same report, with git history splitting stale mentions into deleted-by-commit vs never-existed.*

`````
<!-- ripwire doc drift: the CHECKABLE anchors in this repo's markdown, verified against the live index, reporting only the ones that no longer hold. Four kinds: file:line refs (missing-file / past-eof / line-moved, the last only when the doc names a symbol on that line), backticked symbol mentions (undefined), `= N` constants and `[N]` array extents (value/extent vs the declaration). Every lane under reports on purpose: a name is stale only when it occurs NOWHERE in the code as an identifier, and a number is compared only against a declaration shaped literal the corpus binds uniquely. checked + unchecked == anchors: nothing is dropped silently, and the unchecked rows say what was not proved. Read why="undefined" precisely: it says the name is defined NOWHERE in this repo, which is not the same as DELETED — in a plan or design doc naming work not yet built, that is expected rather than rot. Run with the with_history flag to have git history separate the two: the lane then reports why="deleted" with the commit that removed the name, and downgrades a name this repo never had to unchecked r="never in history". A failed anchor the AUTHOR DATED is split out as kind="dated-record" and counted in dated= rather than drift=: an audit finding, a ledger row or an as-of-DATE hedge records what was true then, so drift= is the LIVE rot and drift + dated is every anchor that no longer holds. rec= names the evidence (line / block / title / stamp), and a doc that never writes its own date anywhere a machine can read reports LIVE — the lane reads dating marks, it does not guess genre. Attribute vocabulary, one name one meaning: at= appears ONLY on this root element and is the commit the run was measured against (short sha, plus dirty when the tree had uncommitted changes); ref= is the anchor as the DOC writes it; got= is what the corpus actually says; and tgt= is the corpus SITE backing got= (a path, or path:line). On the <a/> rows k= and kind= are DIFFERENT things and both are kept: k= is the ANCHOR kind (file-line / symbol / const / array), kind= is the record classification (dated-record). k= cannot be renamed to kind= here for the obvious reason that kind= is already taken on the same element; note that in the ranked map the same k= spelling is a PageRank score instead. Docs are ordered by LIVE drift descending (path breaks ties), so the worst rot leads and a fully dated doc, which is drift zero by construction, sinks on the same key. Prose claims, Status lines and dates are NOT checked. FOUR COUNTERS on this element name four DIFFERENT populations, stated here because one of them openly disagrees with a number the map reports elsewhere. docs= is the DOCUMENTS scanned for anchors (markdown by extension, after any filter); it is the denominator of the doc rows below. clean= is how many of those docs came out with NO failed anchor — drift and dated both zero for that doc — so docs minus clean is exactly the number of <doc> rows below, before any paging window is applied. A doc whose anchors were all unchecked, or all prose, is clean here: clean means nothing was found rotten, not that everything was verified. prose= is the anchors dropped as prose, so it is SUBTRACTED from anchors= rather than added to it, and the verb does not claim to have checked them; only the VALUE shapes (`= N` and `[N]`) can be dropped this way, and the drop is itself a corpus lookup — the name was searched for and not found in code — not a pre-check guess. corpus= is the file population the anchors were checked AGAINST, and it is its OWN population rather than a relation to the map's files=: the indexed files this walk could re-read, PLUS a fixed set of config, shader and build-file extensions (CMakeLists.txt, .cmake, .yml/.yaml, .toml, .metal/.glsl/.hlsl and the like — an extension whitelist, never a content sniff), MINUS every file this walk could not open or that exceeded its own 4 MiB read ceiling, which is dropped silently and never counted. So corpus= is USUALLY larger than files= and that is the normal case, but it is not always: a crawl run whose max file size ceiling was raised above 4 MiB indexes files this walk still refuses, and a file the index lists but this run cannot open is counted by one and not the other. Neither number is wrong. corpus="0" means the corpus scan never ran at all, which happens only when the docs raised no anchor SHAPE whatsoever — prose ones included — so anchors="0" beside a non-zero prose= still scanned, and still reports the corpus it scanned. -->
<doc-drift docs="117" clean="109" anchors="936" checked="238" unchecked="698" drift="15" dated="7" prose="7" corpus="1103" at="33f9f7be2">
<history probed="1" head="33f9f7be2" commits="347" removed-names="15860"/>
<doc p="test/docdriftfix/NOTES.md" anchors="26" checked="15" drift="6" dated="0">
<a k="file-line" l="9" c="64" why="line-moved" ref="code.h:23" sym="stableHelper" got="movedHelper" tgt="test/docdriftfix/code.h:17"/>
<a k="file-line" l="10" c="58" why="past-eof" ref="code.h:900" sym="stableHelper" got="27 lines" tgt="test/docdriftfix/code.h"/>
<a k="file-line" l="11" c="53" why="missing-file" ref="deletedFile.h:12"/>
<a k="const" l="26" c="29" why="const-value" ref="kDriftedLimit = 10" want="10" got="15" tgt="test/docdriftfix/code.h:11"/>
<a k="array" l="28" c="49" why="array-extent" ref="kDriftedTable[16]" want="16" got="18" tgt="test/docdriftfix/code.h:14"/>
<a k="array" l="29" c="61" why="array-extent" ref="[16]" want="16" got="18" tgt="test/docdriftfix/code.h:14"/>
</doc>
<doc p="docs/COMMANDS.md" anchors="47" checked="4" drift="4" dated="0">
<a k="const" l="2144" c="51" why="const-value" ref="kDriftedLimit = 10" want="10" got="15" tgt="test/docdriftfix/code.h:11"/>
<a k="array" l="2145" c="52" why="array-extent" ref="kDriftedTable[16]" want="16" got="18" tgt="test/docdriftfix/code.h:14"/>
<a k="const" l="2182" c="51" why="const-value" ref="kDriftedLimit = 10" want="10" got="15" tgt="test/docdriftfix/code.h:11"/>
<a k="array" l="2183" c="52" why="array-extent" ref="kDriftedTable[16]" want="16" got="18" tgt="test/docdriftfix/code.h:14"/>
</doc>
<doc p="test/docdriftfix/live_notes.md" anchors="2" checked="2" drift="2" dated="0">
<a k="file-line" l="10" c="36" why="past-eof" ref="code.h:906" got="27 lines" tgt="test/docdriftfix/code.h"/>
<a k="file-line" l="17" c="36" why="past-eof" ref="code.h:907" got="27 lines" tgt="test/docdriftfix/code.h"/>
</doc>
<doc p="PLAN.md" anchors="67" checked="37" drift="1" dated="1">
<a k="file-line" l="407" c="63" why="line-moved" kind="dated-record" rec="block" ref="naminglens.h:526" sym="checkNameShape" got="(file scope)" tgt="src/naminglens.h:618"/>
<a k="file-line" l="553" c="81" why="line-moved" ref="ingest.cpp:7175" sym="astQuery" got="operator=" tgt="src/ingest.cpp:8982"/>
</doc>
<doc p="docs/EVALS.md" anchors="22" checked="4" drift="1" dated="0">
<a k="const" l="543" c="42" why="const-value" ref="kParserVer=40" want="40" got="47" tgt="src/ingest.cpp:1013"/>
</doc>
<doc p="test/docdriftfix/record_line.md" anchors="4" checked="4" drift="1" dated="3">
<a k="file-line" l="7" c="48" why="past-eof" kind="dated-record" rec="line" ref="code.h:902" got="27 lines" tgt="test/docdriftfix/code.h"/>
… [25 more display lines; full output is 10831 bytes on 1 raw line(s)]
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
<frame rank="3" n="runDefaultMap" t="fn" p="src/main.cpp:5155" resolved_by="name"/>
<frame rank="4" n="main" t="fn" p="src/main.cpp:5594" resolved_by="name"/>
</trace>
<sigs>
<f p="./src/graph.h">
<d l="1738" n="rankGraphTeleport" id="./src/graph.h::rw::rankGraphTeleport" cx="5" ccx="8" in="6">
<doc>PageRank with an explicit teleport / personalization vector p (Σp = 1). The prior is name-quality-biased through biasPrior() so all rank modes share one weighting seam; the transition matrix (edges</doc>inline std::vector&lt;float&gt; rankGraphTeleport( const Graph&amp; g, const std::vector&lt … [line truncated: 44 more bytes on this line]
<d l="1768" n="rankGraph" id="./src/graph.h::rw::rankGraph" cx="2" ccx="1" in="9">
<doc>uniform-teleport PageRank (the default</doc>inline std::vector&lt;float&gt; rankGraph( const Graph&amp; g, float alpha = 0.85f )</d>
</f>
<f p="./src/main.cpp">
<d l="9703" n="runDefaultMap" cx="108" ccx="177" in="1">int runDefaultMap( const MainDispatch&amp; d )</d>
<d l="10992" n="main" cx="215" ccx="381" in="0">int main( int argc, char** argv )</d>
</f>
</sigs>
<bodies shown="1" total="1" capped="0">
<b t="fn" l="1738" p="./src/graph.h" n="rankGraphTeleport">
<![CDATA[inline std::vector<float> rankGraphTeleport( const Graph& g, const std::vector<float>& p, float alpha = 0.85f )
{
    PROFILE_SCOPE_DESCRIBE( "rankGraph: PageRank (power iteration)" );
    const std::vector<float> pw = biasPrior( g, p );
    const std::size_t N = pw.size();
    std::vector<double> teleport( pw.begin(), pw.end() );
    std::vector<double> rankDouble( N, 0.0 );
    if( N )
… [20 more display lines; full output is 4833 bytes on 28 raw line(s)]
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
<!-- ripwire task bundle for "add a new output format flag to the CLI": one-call orientation under ONE budget — sections in FIXED order ranking > bodies > callers > notes > tests, each truncates rank-adaptively; every truncation reported here (no silent caps): on every section shown=rows kept, total=rows that qualified, capped=1 when they differ. bodies fill rank-first, so a bigger budget can keep FEWER, larger bodies — the count is not a quality measure. Row keys: n=name (chain it), id=canonical(when scoped), in=reuse-count (absent = not measured, never a false 0), l=line, p=path, t=kind, cx=cyclomatic, ccx=cognitive, rel=caller|callee; far=ranked but over 1 hop out; of_top denominator is per-section. budget=12744 bytes (6000-token target, ceiling 14160) | ranking: full | bodies: kept 1 of 6 (capped) | callers: kept 10 of 20 | notes: none | tests: none | far: 6 of 6 -->
<sigs>
<f p="./src/main.cpp">
<d l="10668" n="jsonUnsupportedVerb" cx="73" ccx="73" in="1">const char* jsonUnsupportedVerb( const rw::Config&amp; c )</d>
</f>
<f p="./src/quality.h">
<d l="2647" n="readAckRecords" id="./src/quality.h::quality::readAckRecords" cx="16" ccx="21" in="2">
<doc>anywhere — so a round-trip (read whatever is on disk → merge in new findings → write) always SELF-HEALS the file back to canonical sorted order regardless of what shape it arrived in. Grammar (a</doc>inline gtl::btree_map&lt;std::string, AckRecord&gt; readAckRecords( const std::string&amp … [line truncated: 12 more bytes on this line]
</f>
<f p="./src/prcontext.h">
<d l="278" n="isCommitSha" id="./src/prcontext.h::rw::isCommitSha" cx="8" ccx="8" in="1">
<doc>A git object name is 40 (sha-1) or 64 (sha-256) lowercase hex characters. Checked explicitly rather than assumed so &quot;the revision token can never look like an option&quot; is a property this file PROVES ra</doc>inline bool isCommitSha( std::string_view s )</d>
</f>
<f p="./src/cli.h">
<d l="1586" n="BoolFlag" id="./src/cli.h::BoolFlag::BoolFlag" cx="0" ccx="0" in="0">
<doc>offsetof, which would be UB on a non-standard-layout type. ORDER. The tables are scanned in DECLARATION ORDER, exacts before prefixes, ahead of the hand-written arms — so the chain&apos;s original preced</doc>struct BoolFlag</d>
<d l="2279" n="validateColumnarVerb" id="./src/cli.h::rw::validateColumnarVerb" cx="6" ccx="3" in="1">
<doc>A5b — --format=columnar re-serializes a FLAT SYMBOL-ROW listing (a path table + parallel arrays), and only four verbs produce one. On any other verb it was accepted and silently ignored: --hotspot</doc>inline void validateColumnarVerb( Config&amp; c ) noexcept</d>
</f>
<f p="./src/gitoracle.h">
<d l="592" n="runProbe" id="./src/gitoracle.h::gitoracle::runProbe" cx="5" ccx="4" in="1">
<doc>no-merges   a merge&apos;s diff is not shown by default anyway; saying so keeps the walk honest and cheap                 (the LIMIT: a deletion performed ONLY as a merge resolution is invisible — do</doc>inline HistoryIndex runProbe( const std::string&amp; root )</d>
</f>
<far of_top="12" shown="6" total="6" capped="0">
<s t="fn" n="editCheckVerdict" p="./src/editcheck.h:301"/>
<s t="fn" n="toUint" p="./src/tracein.h:103"/>
<s t="fn" n="parseArgs" p="./src/cli.h:2888"/>
<s t="fn" n="addRootFilesToGitPathIndex" p="./src/gitmine.h:794"/>
<s t="struct" n="McpVerbGroup" p="./src/mcp.h:44"/>
… [239 more display lines; full output is 8979 bytes on 216 raw line(s)]
`````

## `./build/ripwire . --pack-task="add a new output format flag to the CLI" --partition=3`

*Fan-out form: one shared core + 3 per-agent slices carved along call-graph communities.*

`````
<ctx-partitions partitions="3" requested="3" core_symbols="6" surface="42" modules="26" split="0" budget_per_agent_tokens="6000" core_budget_tokens="2040" partition_budget_tokens="3960" total_bytes="26393" overlap_mean="0.058" overlap_max="0.114" shared_symbols="10" union_symbols="98" core_overlap=" … [line truncated: 7 more bytes on this line]
<!-- ripwire partitioned task bundle: ONE shared common core plus N minimally overlapping per agent slices, carved along the call graph's own community structure. Each bundle wraps one ctx document, exactly what a standalone pack task call with that slice would emit, so an orchestrator hands one bundle to one agent verbatim. budget_per_agent_tokens is the budget for core PLUS one partition, not the whole document; total_bytes is the bundles' combined size. overlap_mean/overlap_max are pairwise Jaccard over the ids each partition names (ranking window, bodies, and their 1 hop neighbors), measured BEFORE budget trimming, so they are a ceiling. shared_symbols counts the ids TWO OR MORE partitions name — NOT the ids every partition names; an id two of sixteen slices both carry is already duplicated work — and union_symbols the ids ANY partition names: one GLOBAL at-least-two over at-least-one pair, not an average. That ratio and overlap_mean (an average of PAIRWISE Jaccard) therefore answer different questions. They COINCIDE at partitions=2, where there is one pair and at-least-two IS its intersection while at-least-one IS its union, so the ratio equals that pair's Jaccard by identity; from 3 partitions on the two genuinely diverge, and neither is wrong. The remaining root counters, one clause each. requested= is the partition count N asked for and partitions= the bundles actually carved; partitions is lower only where the plan could not reach N, which is either a ranked surface that fit entirely in the shared core (partitions=0, nothing left to carve) or a surface holding fewer separable modules than N even after splitting. modules= is the distinct groups found on the assignable surface BEFORE any cut (a call-graph community, or the FILE where that surface carries no call edges), and split= the community cuts forced because those modules numbered fewer than N, so modules + split is the group count the bundles were packed from and split=0 means no cut was needed. core_symbols= is the shared core's size — the body anchors a plain pack task would have expanded, held out of every partition — and surface= is core_symbols plus the assignable remainder, i.e. the whole positive-rank window this plan carved up. core_budget_tokens= and partition_budget_tokens= are budget_per_agent_tokens split between the two halves one agent receives, and they sum to it. core_overlap is the share of the core bundle's own surface a partition reaches anyway. On each bundle, est_tokens and tokens are the SAME number: tokens is the original name kept for compatibility, est_tokens is the spelling the rest of the tool uses and the one to read. Both are that bundle's own bytes= divided by 2.36 B/tok — the DENSEST calibrated language rate — which is a different (deliberately conservative) currency from the default map's est_tokens, where the divisor is that corpus's own language-weighted rate: measured over real emitted bytes either way, but a bundle's number reads slightly HIGH, which is the safe direction for a per-agent budget. On this root element the unit is carried in the NAME instead (budget_per_agent_tokens, total_bytes) rather than by a separate unit attribute, which is a deliberate exception to the est_tokens convention and not a second estimator. -->
<bundle role="core" symbols="6" bytes="4404" tokens="1866" est_tokens="1866">
<ctx task="add a new output format flag to the CLI" route=" [routed: subtoken+body BM25 (--for&apos;s default) — no strong name hit, multi-word conceptual query]">
<!-- ripwire task bundle for "add a new output format flag to the CLI": one-call orientation under ONE budget — sections in FIXED order ranking > bodies > callers > notes > tests, each truncates rank-adaptively; every truncation reported here (no silent caps): on every section shown=rows kept, total=rows that qualified, capped=1 when they differ. bodies fill rank-first, so a bigger budget can keep FEWER, larger bodies — the count is not a quality measure. Row keys: n=name (chain it), id=canonical(when scoped), in=reuse-count (absent = not measured, never a false 0), l=line, p=path, t=kind, cx=cyclomatic, ccx=cognitive, rel=caller|callee; far=ranked but over 1 hop out; of_top denominator is per-section. budget=4332 bytes (2040-token target, ceiling 4814) | ranking: capped | bodies: kept 1 of 6 (capped) | callers: omitted (budget) | notes: none | tests: none | far: none -->
<sigs capped="1">
<f p="./src/main.cpp">
<d l="10668" n="jsonUnsupportedVerb" cx="73" ccx="73" in="1">const char* jsonUnsupportedVerb( const rw::Config&amp; c )</d>
</f>
<f p="./src/quality.h">
<d l="2647" n="readAckRecords" id="./src/quality.h::quality::readAckRecords" cx="16" ccx="21" in="2">
<doc>anywhere — so a round-trip (read whatever is on disk → merge in new findings → write) always SELF-HEALS the file back to canonical sorted order regardless of what shape it arrived in. Grammar (a</doc>inline gtl::btree_map&lt;std::string, AckRecord&gt; readAckRecords( const std::string&amp … [line truncated: 12 more bytes on this line]
</f>
<f p="./src/prcontext.h">
<d l="278" n="isCommitSha" id="./src/prcontext.h::rw::isCommitSha" cx="8" ccx="8" in="1">
<doc>A git object name is 40 (sha-1) or 64 (sha-256) lowercase hex characters. Checked explicitly rather than assumed so &quot;the revision token can never look like an option&quot; is a property this file PROVES ra</doc>inline bool isCommitSha( std::string_view s )</d>
</f>
<f p="./src/cli.h">
<d l="1586" n="BoolFlag" id="./src/cli.h::BoolFlag::BoolFlag" cx="0" ccx="0" in="0">
<doc>offsetof, which would be UB on a non-standard-layout type. ORDER. The tables are scanned in DECLARATION ORDER, exacts before prefixes, ahead of the hand-written arms — so the chain&apos;s original preced</doc>struct BoolFlag</d>
<d l="2279" n="validateColumnarVerb" id="./src/cli.h::rw::validateColumnarVerb" cx="6" ccx="3" in="1">
<doc>A5b — --format=columnar re-serializes a FLAT SYMBOL-ROW listing (a path table + parallel array…</doc>inline void validateColumnarVerb( Config&amp; c ) noexcept</d>
</f>
<f p="./src/gitoracle.h">
<d l="592" n="runProbe" id="./src/gitoracle.h::gitoracle::runProbe" cx="5" ccx="4" in="1">
<doc>no-merges   a merge&apos;s diff is not shown by default anyway; saying so keeps the walk honest and c…</doc>inline HistoryIndex runProbe( const std::string&amp; root )</d>
</f>
</sigs>
<bodies shown="1" total="6" capped="1">
<b t="fn" l="10668" p="./src/main.cpp" n="jsonUnsupportedVerb">
… [243 more display lines; full output is 30429 bytes on 197 raw line(s)]
`````

## `./build/ripwire . --for="pagerank power iteration" --with-graph`

*Task lens + a compact Mermaid flowchart of the top anchors' 1-hop edges.*

`````
<ctx task="pagerank power iteration" route=" [routed: subtoken+body BM25 (--for&apos;s default) — no strong name hit, multi-word conceptual query]">
<!-- ripwire lens for "pagerank power iteration": reusable building blocks + quality facts for what you're about to touch (cx=complexity ccx=cognitive in=reuse-count churn=recent-commits amp=change-amplification clone=1(duplicated) tested=1) — prefer composing/reusing these; watch the high-churn/high-amp/cloned ones est_tokens="3072" -->
<sigs capped="1">
<f p="./scripts/optremarks.py">
<d l="40" n="HOT_FILES" cx="0" ccx="0" in="0" churn="1" amp="13">HOT_FILES = ( &quot;src/pagerank.cpp&quot;, # the power-iteration loop — G2&apos;s no-allocation scope &quot;src/infra/radixSort.h&quot;, # LSD radix entry points &quot;src/infra/radixSort…</d>
</f>
<f p="./src/pagerank.cpp">
<d l="36" n="pageRankDouble" id="./src/pagerank.cpp::rw::pageRankDouble" cx="18" ccx="33" in="1" churn="4" amp="8">unsigned pageRankDouble( const sparseCsr&lt;float&gt;&amp; inEdges, std::span&lt;const double&gt; weightedOutDegree, std::span&lt;const double&gt; teleport, std::span&lt;double&gt; rank … [line truncated: 10 more bytes on this line]
</f>
<f p="./src/graph.h">
<d l="1738" n="rankGraphTeleport" id="./src/graph.h::rw::rankGraphTeleport" cx="5" ccx="8" in="6" churn="10" amp="41">
<doc>PageRank with an explicit teleport / personalization vector p (Σp = 1). The prior is name-quali…</doc>inline std::vector&lt;float&gt; rankGraphTeleport( const Graph&amp; g, const std::vector&lt;float&gt;&amp; p, float alpha = 0.85f )</d>
<d l="1793" n="hits" id="./src/graph.h::rw::hits" cx="9" ccx="16" in="1" churn="10" amp="36">inline std::pair&lt;std::vector&lt;float&gt;, std::vector&lt;float&gt;&gt; hits( const Graph&amp; g, float tol = 1e-6f, unsigned maxIter = 100 )</d>
<d l="3292" n="louvainLocalMoving" id="./src/graph.h::rw::louvainLocalMoving" cx="18" ccx="35" in="2" churn="10" amp="37">inline Communities louvainLocalMoving( const std::vector&lt;std::vector&lt;WEdge&gt;&gt;&amp; adj )</d>
</f>
<f p="./src/infra/dynamic_map.hpp" layer="infra">
<d l="471" n="leaf_node" id="./src/infra/dynamic_map.hpp::leaf_node::leaf_node" cx="0" ccx="0" in="0" churn="3" amp="10">struct alignas(16) leaf_node</d>
<d l="1163" n="values_begin" id="./src/infra/dynamic_map.hpp::dynamic_map::values_begin" cx="2" ccx="1" in="3" churn="3" amp="13" tested="1">value_iterator values_begin()</d>
<d l="1511" n="compact" id="./src/infra/dynamic_map.hpp::dynamic_map::compact" cx="28" ccx="49" in="0" churn="3" amp="10">void compact()</d>
<d l="2199" n="leftmost_leaf" id="./src/infra/dynamic_map.hpp::dynamic_map::leftmost_leaf" cx="2" ccx="1" in="7" churn="3" amp="17" tested="1" pure="1">
<doc>iteration helpers</doc>handle_t leftmost_leaf() const</d>
</f>
<f p="./src/serialize.h">
<d l="993" n="MapAnnotations" id="./src/serialize.h::MapAnnotations::MapAnnotations" cx="0" ccx="0" in="0" churn="20" amp="47">struct MapAnnotations</d>
<d l="1063" n="rankByLegendFor" id="./src/serialize.h::rw::rankByLegendFor" cx="4" ccx="4" in="1" churn="20" amp="48">inline const char* rankByLegendFor( const char* label ) noexcept</d>
<d l="4845" n="writeJsonMapStamp" id="./src/serialize.h::rw::writeJsonMapStamp" cx="10" ccx="12" in="1" churn="20" amp="48">inline void writeJsonMapStamp( JsonWriter&amp; w, std::string&amp; esc, const MapAnnotations* ann )</d>
</f>
<f p="./src/pagerank.h">
<d l="11" n="PageRankConfig" id="./src/pagerank.h::PageRankConfig::PageRankConfig" cx="0" ccx="0" in="0" churn="3" amp="7">struct PageRankConfig</d>
</f>
… [60 more display lines; full output is 7681 bytes on 11 raw line(s)]
`````

## `./build/ripwire . --export=cc.json:<scratch>/aux/ripwire2.cc.json`

*Per-file metrics as CodeCharta cc.json.*

`````
(empty)
`````

Artifact written:

`````
  161489 <scratch>/aux/ripwire2.cc.json
{"projectName":"project","apiVersion":"1.3","attributeDescriptors":{"loc":{"title":"Lines of Code","description":"Physical line count","direction":-1},"symbols":{"title":"Symbols","description":"Definitions in the file","direction":-1},"cx":{"title":"Cyclomatic Complexity","description":"Sum of per-symbol cyclomatic complexity","direction":-1},"cognitive_cx":{"title":"Cognitive Complexity","descri
`````

## `./build/ripwire . --batch=<scratch>/aux/batch2.txt`

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
<!-- ripwire lens for "incremental cache invalidation" [doc mentions: 1 doc discussing 1 top-ranked symbol surfaced]: reusable building blocks (cx=complexity, in=reuse-count) — prefer composing/reusing these over reimplementing -->
<sigs capped="1">
<f p="./src/dmm.h">
<d l="244" n="ingestCommitTree" id="./src/dmm.h::rw::dmm::ingestCommitTree" cx="6" ccx="5" in="1">
<doc>Ingest the tree at `sha`, materialized out of `root`&apos;s object store. The HEAD side reuses the SA…</doc>inline bool ingestCommitTree( const std::string&amp; root, const std::string&amp; sha, const std::vector&lt;std::string&gt;&amp; excludes, std::size_t maxFileBytes, IngestResult&amp;… … [line truncated: 4 more bytes on this line]
</f>
<f p="./src/ingest.h">
<d l="90" n="ingest" id="./src/ingest.h::rw::ingest" cx="1" ccx="0" in="0">
<doc>for vendored/generated trees not caught by the built-in dir denylist (--exclude=SUBSTR). cacheFi…</doc>IngestResult ingest( const char* rootDir, const std::vector&lt;std::string&gt;&amp; excludeSubstr =</d>
<d l="132" n="AstWalk" id="./src/ingest.h::rw::AstWalk" cx="0" ccx="0" in="0">enum class AstWalk : std::uint8_t</d>
</f>
<f p="./src/serialize.h">
<d l="1913" n="pureFromSig" id="./src/serialize.h::rw::pureFromSig" cx="6" ccx="5" in="3">inline bool pureFromSig( const std::string&amp; sig, Lang lang = Lang::Cpp )</d>
<d l="1931" n="docCommentBefore" id="./src/serialize.h::rw::docCommentBefore" cx="67" ccx="74" in="3">inline std::string docCommentBefore( const std::string&amp; src, std::size_t defStart )</d>
<d l="4187" n="legoImplementorsOnSurface" id="./src/serialize.h::rw::legoImplementorsOnSurface" cx="10" ccx="13" in="2">
<doc>P3 SCOPE (bundle embeddings only). packLego&apos;s ranked mode treats &quot;has implementors&quot; as &quot;is an in…</doc>inline std::vector&lt;std::vector&lt;NodeId&gt;&gt; legoImplementorsOnSurface( const IngestResult&amp; ing, const std::vector&lt;std::vector&lt;NodeId&gt;&gt;&amp; implem … [line truncated: 29 more bytes on this line]
</f>
<f p="./src/quality.h">
<d l="357" n="bodyHashesBySym" id="./src/quality.h::quality::bodyHashesBySym" cx="16" ccx="29" in="4">inline gtl::btree_map&lt;std::uint64_t, std::uint64_t&gt; bodyHashesBySym( const IngestResult&amp; ing, st…</d>
<d l="440" n="cacheDirLadder" id="./src/quality.h::quality::cacheDirLadder" cx="16" ccx="14" in="12">inline std::string cacheDirLadder()</d>
<d l="694" n="headSnapRepoHex" id="./src/quality.h::quality::headSnapRepoHex" cx="3" ccx="2" in="6">inline std::string headSnapRepoHex( const std::string&amp; root )</d>
<d l="787" n="extractionIdentityTag" id="./src/quality.h::quality::extractionIdentityTag" cx="1" ccx="0" in="1">inline std::string extractionIdentityTag()</d>
<d l="804" n="exclConfigHex" id="./src/quality.h::quality::exclConfigHex" cx="2" ccx="1" in="5">inline std::string exclConfigHex( const std::vector&lt;std::string&gt;&amp; excludes, const std::string&amp; s…</d>
<d l="819" n="headSnapExclHex" id="./src/quality.h::quality::headSnapExclHex" cx="1" ccx="0" in="3">inline std::string headSnapExclHex( const std::vector&lt;std::string&gt;&amp; excludes, std::size_t maxFil…</d>
<d l="839" n="blobShardHex" id="./src/quality.h::quality::blobShardHex" cx="1" ccx="0" in="1">inline std::string blobShardHex( std::string_view filename )</d>
<d l="846" n="resolveCacheBlobPath" id="./src/quality.h::quality::resolveCacheBlobPath" cx="4" ccx="3" in="5">inline std::string resolveCacheBlobPath( const std::string&amp; dir, const std::string&amp; filename )</d>
… [54 more display lines; full output is 15531 bytes on 1 raw line(s)]
`````


---

# self-diagnosis

## `./build/ripwire . --doctor`

*Environment self-check: binary staleness, grammars, cache dir, git, tracked-binary staleness.*

**exit code: 1**

`````
<doctor checks="6" passed="5" at="33f9f7be2">
<c n="binary-path" ok="0" self="./build/ripwire" which="/opt/homebrew/bin/ripwire" on_path="1" same_file="0" self_mtime="1786204636" self_size="39145544" which_mtime="1785771808" which_size="34366328" hint="STALE: … [line truncated: 323 more bytes on this line]
<c n="grammars" ok="1" loaded="13" expected="13"/>
<c n="cache-dir" ok="1" dir="<tmp>" blobs="4096" bytes="970064692" many="1" truncated="1"/>
<c n="git" ok="1" git="1" repo="1" history="1" head="33f9f7be2"/>
<c n="tree-sitter" ok="1" core_abi="15" cpp_grammar_abi="14" languages="13"/>
<c n="tracked-binaries" ok="1" tracked="1369" binaries="4" non_git="0" truncated="0" stale="0"/>
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
<!-- files=1081 symbols=8835 edges=10480 shown=5 est_tokens=581 ambiguous=3045 unresolved=1326 precise=3 skipped_oversize=14 order=important-first -->
<r at="33f9f7be2" rank_by="churn" window="18mo" est_tokens="581">
<f p="./src/svector.h">
<s t="method" n="size" id="./src/svector.h::svector::size" k="0.0593">
</s>
<s t="method" n="push_back" id="./src/svector.h::svector::push_back" amb="2" k="0.0160">
<c n="buf"/>
<c n="buf"/>
<c n="grow"/>
</s>
<s t="method" n="buf" id="./src/svector.h::svector::buf" overloads="2" k="0.0130">
</s>
</f>
<f p="./src/scipoverlay.h">
<s t="method" n="empty" id="./src/scipoverlay.h::ScipOverlay::empty" k="0.0199">
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
<line>168,1768,2104,9599,9703,913</line>
<kind>fn,fn,fn,fn,fn,fn</kind>
</cols>
</callers>
`````

## `./build/ripwire . --for="cache invalidation" --format=candidates --top-k=5`

*Flat top-K export for an external reranker.*

`````
<!-- ripwire candidates: flat top K export for an external reranker. r=rank(1 based) s=SCORE n=name id=canonical k=KIND-tag p=path l=line. Note k= is the kind here and the PageRank score in the ranked map; on this row the score is s=. Root: count= rows exported of total= RANKED CORPUS symbols (total is the corpus size, never a match count), capped="1" means the top-k cut dropped some; route= names the ranker (s= is comparable only within one route); anchored= counts query-mention lifts (0 = the anchor ran and moved nothing); weak="1" means the top raw lexical score is below the confidence bar, so these rows rest on thin textual evidence. -->
<candidates count="5" total="8835" capped="1" route="subtoken+body" anchored="0">
<cand r="1" s="8.81722" n="legoImplementorsOnSurface" id="./src/serialize.h::rw::legoImplementorsOnSurface" k="fn" p="./src/serialize.h" l="4187">
<sig>inline std::vector&lt;std::vector&lt;NodeId&gt;&gt; legoImplementorsOnSurface( const IngestResult&amp; ing, const std::vector&lt;std::vector&lt;NodeId&gt;&gt;&amp; implementors, const std::vector&lt;NodeId&gt;&amp; surfaceIds )</sig>
</cand>
<cand r="2" s="6.69069" n="compiledQueryCache" id="compiledQueryCache" k="fn" p="./src/ingest.cpp" l="813">
<sig>HashMap&lt;const TSLanguage*, TSQuery*&gt;&amp; compiledQueryCache()</sig>
</cand>
<cand r="3" s="6.65126" n="sweepStaleCacheBlobsOnce" id="./src/quality.h::quality::sweepStaleCacheBlobsOnce" k="fn" p="./src/quality.h" l="1094">
<sig>inline void sweepStaleCacheBlobsOnce( const std::string&amp; dir, const std::string&amp; keepPath )</sig>
</cand>
<cand r="4" s="6.6373" n="CompiledQueryCache" id="./src/ingest.cpp::CompiledQueryCache::CompiledQueryCache" k="fn" p="./src/ingest.cpp" l="794">
<sig>CompiledQueryCache( const CompiledQueryCache&amp; )</sig>
</cand>
<cand r="5" s="6.62918" n="hw_cache_config" id="./src/infra/profilePmc.h::pmc::hw_cache_config" k="fn" p="./src/infra/profilePmc.h" l="513">
<sig>inline constexpr std::uint64_t hw_cache_config( std::uint64_t cache, std::uint64_t op, std::uint64_t result ) noexcept</sig>
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
{"of":"rankGraphTeleport","defs":1,"count":6,"counts_floor":true,"callers":[{"t":"fn","n":"runEval","p":"./src/eval.h:168"},
{"t":"fn","n":"rankGraph","p":"./src/graph.h:1768"},
{"t":"fn","n":"anchoredLexicalRank","p":"./src/graph.h:2104"},
{"t":"fn","n":"churnRankedGraph","p":"./src/main.cpp:9599"},
{"t":"fn","n":"runDefaultMap","p":"./src/main.cpp:9703"},
{"t":"fn","n":"getIndex","p":"./src/mcpindex.h:913"}]}
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
<hotspots window="12mo" files="1081" ranked="291" unranked_no_churn="0" unranked_no_complexity="790" shown="3" capped="1" total="291" has_more="1" next_offset="6" offset="3" limit="3" at="33f9f7be2">
<f p="./src/quality.h" churn="24" ccx="707" score="16968" top="computeDelta" top_ccx="236" top_l="2747"/>
<f p="./src/cli.h" churn="45" ccx="350" score="15750" top="parseArgs" top_ccx="154" top_l="2888"/>
<f p="./src/graph.h" churn="10" ccx="1406" score="14060" top="buildGraph" top_ccx="698" top_l="462"/>
</hotspots>
`````

## `./build/ripwire . --ignore-tests --top-k=5`

*Drop test paths from the corpus before ranking.*

`````
<!-- ripwire v1 t=fn|method|cls|struct|iface|var|sec p=path layer=arch-layer(opt) n=name id=canonical(path::scope::name,when-scoped) k=rank c=call amb=ambiguous-calls(read-source) overloads=N-same-name-defs-merged-into-this-row(absent-if-1;shown=counts-them-individually,so-rows+sum(overloads-1)=shown) hdr:unresolved=call-name-defined-only-in-a-lang-incompatible-file (edges heuristic) r:est_tokens=hdr-copy(none-if-stable) -->
<!-- files=1081 symbols=5499 edges=9320 shown=5 est_tokens=410 ambiguous=2989 unresolved=831 skipped_oversize=14 order=important-first -->
<r est_tokens="410">
<f p="./src/svector.h">
<s t="method" n="size" id="./src/svector.h::svector::size" k="0.0587">
</s>
<s t="method" n="push_back" id="./src/svector.h::svector::push_back" amb="2" k="0.0161">
<c n="buf"/>
<c n="buf"/>
<c n="grow"/>
</s>
<s t="method" n="buf" id="./src/svector.h::svector::buf" overloads="2" k="0.0148">
</s>
</f>
<f p="./src/scipoverlay.h">
<s t="method" n="empty" id="./src/scipoverlay.h::ScipOverlay::empty" k="0.0154">
</s>
</f>
</r>
`````

## `./build/ripwire . --exclude=present --exclude=bench --top-k=5`

*Drop matching paths (repeatable) before ranking.*

`````
<!-- ripwire v1 t=fn|method|cls|struct|iface|var|sec p=path layer=arch-layer(opt) n=name id=canonical(path::scope::name,when-scoped) k=rank c=call amb=ambiguous-calls(read-source) overloads=N-same-name-defs-merged-into-this-row(absent-if-1;shown=counts-them-individually,so-rows+sum(overloads-1)=shown) prov=scip(precise;else name-based) hdr:unresolved=call-name-defined-only-in-a-lang-incompatible-file (edges heuristic) r:est_tokens=hdr-copy(none-if-stable) -->
<!-- files=934 symbols=7084 edges=9766 shown=5 est_tokens=420 ambiguous=3015 unresolved=365 precise=3 order=important-first -->
<r est_tokens="420">
<f p="./src/svector.h">
<s t="method" n="size" id="./src/svector.h::svector::size" k="0.0502">
</s>
<s t="method" n="push_back" id="./src/svector.h::svector::push_back" amb="2" k="0.0134">
<c n="buf"/>
<c n="buf"/>
<c n="grow"/>
</s>
<s t="method" n="buf" id="./src/svector.h::svector::buf" overloads="2" k="0.0125">
</s>
</f>
<f p="./src/scipoverlay.h">
<s t="method" n="empty" id="./src/scipoverlay.h::ScipOverlay::empty" k="0.0131">
</s>
</f>
</r>
`````

## `./build/ripwire . --map-diff --top-k=5`

*Full map re-ranked with teleport toward git-changed files — clean tree, so changed=0 and it degrades to the plain map.*

`````
<!-- ripwire v1 t=fn|method|cls|struct|iface|var|sec p=path layer=arch-layer(opt) n=name id=canonical(path::scope::name,when-scoped) k=rank c=call amb=ambiguous-calls(read-source) overloads=N-same-name-defs-merged-into-this-row(absent-if-1;shown=counts-them-individually,so-rows+sum(overloads-1)=shown) prov=scip(precise;else name-based) hdr:unresolved=call-name-defined-only-in-a-lang-incompatible-file (edges heuristic) r:est_tokens=hdr-copy(none-if-stable) -->
<!-- at= is the git commit these numbers were computed at; a trailing +dirty means the working tree differed from that commit, so the numbers describe the tree, not the commit -->
<!-- files=1081 symbols=8835 edges=10480 shown=5 est_tokens=511 ambiguous=3045 unresolved=1326 precise=3 changed=0 skipped_oversize=14 order=important-first -->
<r at="33f9f7be2" est_tokens="511">
<f p="./src/svector.h">
<s t="method" n="size" id="./src/svector.h::svector::size" k="0.0433">
</s>
<s t="method" n="push_back" id="./src/svector.h::svector::push_back" amb="2" k="0.0121">
<c n="buf"/>
<c n="buf"/>
<c n="grow"/>
</s>
<s t="method" n="buf" id="./src/svector.h::svector::buf" overloads="2" k="0.0110">
</s>
</f>
<f p="./src/scipoverlay.h">
<s t="method" n="empty" id="./src/scipoverlay.h::ScipOverlay::empty" k="0.0113">
</s>
</f>
</r>
`````

## `./build/ripwire . --no-cache --top-k=3`

*Force a cold parse (bypass the warm TMPDIR cache) — shows the cold-vs-warm cost.*

`````
<!-- ripwire v1 t=fn|method|cls|struct|iface|var|sec p=path layer=arch-layer(opt) n=name id=canonical(path::scope::name,when-scoped) k=rank c=call amb=ambiguous-calls(read-source) overloads=N-same-name-defs-merged-into-this-row(absent-if-1;shown=counts-them-individually,so-rows+sum(overloads-1)=shown) prov=scip(precise;else name-based) hdr:unresolved=call-name-defined-only-in-a-lang-incompatible-file (edges heuristic) r:est_tokens=hdr-copy(none-if-stable) -->
<!-- files=1081 symbols=8835 edges=10480 shown=3 est_tokens=394 ambiguous=3045 unresolved=1326 precise=3 skipped_oversize=14 order=important-first -->
<r est_tokens="394">
<f p="./src/svector.h">
<s t="method" n="size" id="./src/svector.h::svector::size" k="0.0433">
</s>
<s t="method" n="push_back" id="./src/svector.h::svector::push_back" amb="2" k="0.0121">
<c n="buf"/>
<c n="buf"/>
<c n="grow"/>
</s>
</f>
<f p="./src/scipoverlay.h">
<s t="method" n="empty" id="./src/scipoverlay.h::ScipOverlay::empty" k="0.0113">
</s>
</f>
</r>
`````

## `./build/ripwire . --cache=<scratch>/aux/warm2.ripwirecache --top-k=3`

*Explicit incremental cache at a path OUTSIDE the repo (first call writes it).*

`````
<!-- ripwire v1 t=fn|method|cls|struct|iface|var|sec p=path layer=arch-layer(opt) n=name id=canonical(path::scope::name,when-scoped) k=rank c=call amb=ambiguous-calls(read-source) overloads=N-same-name-defs-merged-into-this-row(absent-if-1;shown=counts-them-individually,so-rows+sum(overloads-1)=shown) prov=scip(precise;else name-based) hdr:unresolved=call-name-defined-only-in-a-lang-incompatible-file (edges heuristic) r:est_tokens=hdr-copy(none-if-stable) -->
<!-- files=1081 symbols=8835 edges=10480 shown=3 est_tokens=394 ambiguous=3045 unresolved=1326 precise=3 skipped_oversize=14 order=important-first -->
<r est_tokens="394">
<f p="./src/svector.h">
<s t="method" n="size" id="./src/svector.h::svector::size" k="0.0433">
</s>
<s t="method" n="push_back" id="./src/svector.h::svector::push_back" amb="2" k="0.0121">
<c n="buf"/>
<c n="buf"/>
<c n="grow"/>
</s>
</f>
<f p="./src/scipoverlay.h">
<s t="method" n="empty" id="./src/scipoverlay.h::ScipOverlay::empty" k="0.0113">
</s>
</f>
</r>
`````

Artifact written:

`````
 4791126 <scratch>/aux/warm2.ripwirecache
`````

## `./build/ripwire . --max-file-size=8K --top-k=3`

*Skip files above a size bound before parsing (note the corpus shrink in the header).*

`````
<!-- ripwire v1 t=fn|method|cls|struct|iface|var|sec p=path layer=arch-layer(opt) n=name id=canonical(path::scope::name,when-scoped) k=rank c=call amb=ambiguous-calls(read-source) overloads=N-same-name-defs-merged-into-this-row(absent-if-1;shown=counts-them-individually,so-rows+sum(overloads-1)=shown) prov=scip(precise;else name-based) hdr:unresolved=call-name-defined-only-in-a-lang-incompatible-file (edges heuristic) r:est_tokens=hdr-copy(none-if-stable) -->
<!-- files=639 symbols=2607 edges=817 shown=3 est_tokens=396 ambiguous=93 unresolved=100 precise=3 skipped_oversize=456 order=important-first -->
<r est_tokens="396">
<f p="./src/svector.h">
<s t="method" n="size" id="./src/svector.h::svector::size" k="0.0120">
</s>
</f>
<f p="./test/regexfix/beta.py" layer="test">
<s t="fn" n="open" id="./test/regexfix/beta.py::Widget::open" k="0.0041">
</s>
</f>
<f p="./src/infra/platform.h" layer="infra">
<s t="fn" n="max" id="./src/infra/platform.h::fastmath::max" k="0.0034">
</s>
</f>
</r>
`````

## `./build/ripwire . --scip=does_not_exist.scip --callers=rankGraphTeleport`

*SCIP overlay with a missing index: degrades to name-based, never fails.*

`````
<!-- ripwire callers/callees: the 1-hop call hierarchy read straight off the call graph. The callers form lists the symbols that CALL of=; the callees form lists the symbols of= itself calls. of= is the selector you passed, defs= how many DEFINITIONS that name resolved to (the rows UNION every def's neighbours), and count= the number of DISTINCT neighbour symbols (a floor, per counts_floor=), which the rows window with limit= and offset=. counts_floor="1" means every count on this element is a FLOOR, never a total. Call edges are extracted from source text by NAME, so a call that reaches its target through dynamic dispatch (a virtual, interface or duck-typed receiver), a callback or function pointer, a macro-generated call site, or a declaration that parses without a call expression (C++ most-vexing-parse) contributes no edge and is missing here. Read a zero as "none found", never as "none exists". COUNTING UNIT, and it differs by verb — which is why two of them report different numbers for one symbol. The callers, callees, edit-check, graph-query and pr-context counts are DISTINCT SYMBOLS: repeated calls from one caller, and calls to two overloads of one name, collapse into ONE row, their multiplicity surviving only in the call graph's edge weight. The reach counts (impact's reaches=, pr-context's dependents=) are the size of a transitive reach SET, each symbol counted once — not a count of calls or edges. The uses verb counts call SITES, one row per occurrence, so a larger count= there for the same symbol is these units agreeing, not disagreeing. The map header's edges= is a unit again different — distinct (caller,callee) PAIRS — and that document carries neither this marker nor this clause, so its numbers answer a different question. -->
<callers of="rankGraphTeleport" defs="1" count="6" counts_floor="1">
<s t="fn" n="runEval" p="./src/eval.h:168"/>
<s t="fn" n="rankGraph" p="./src/graph.h:1768"/>
<s t="fn" n="anchoredLexicalRank" p="./src/graph.h:2104"/>
<s t="fn" n="churnRankedGraph" p="./src/main.cpp:9599"/>
<s t="fn" n="runDefaultMap" p="./src/main.cpp:9703"/>
<s t="fn" n="getIndex" p="./src/mcpindex.h:913"/>
</callers>
`````

stderr:

`````
[math degraded] --scip: index missing or unreadable — proceeding name-based  (scip.h:523, ScipOverlay rw::loadScipOverlay(std::string_view, const IngestResult &) — logged once per site)
ripwire --scip: cannot read index 'does_not_exist.scip' — proceeding name-based
`````

## `./build/ripwire src test --top-k=5`

*Multi-root workspace: ONE merged graph over two roots, paths labeled <root>/<rel>.*

`````
<!-- ripwire v1 t=fn|method|cls|struct|iface|var|sec p=path layer=arch-layer(opt) n=name id=canonical(path::scope::name,when-scoped) k=rank c=call amb=ambiguous-calls(read-source) overloads=N-same-name-defs-merged-into-this-row(absent-if-1;shown=counts-them-individually,so-rows+sum(overloads-1)=shown) prov=scip(precise;else name-based) hdr:unresolved=call-name-defined-only-in-a-lang-incompatible-file (edges heuristic) r:est_tokens=hdr-copy(none-if-stable) -->
<!-- files=867 symbols=6345 edges=9666 shown=5 est_tokens=446 ambiguous=3007 unresolved=130 precise=3 roots=2 order=important-first -->
<r est_tokens="446">
<root label="src" p="src"/>
<root label="test" p="test"/>
<f p="src/./svector.h">
<s t="method" n="size" id="src/./svector.h::svector::size" k="0.0549">
</s>
<s t="method" n="push_back" id="src/./svector.h::svector::push_back" amb="2" k="0.0142">
<c n="buf"/>
<c n="buf"/>
<c n="grow"/>
</s>
<s t="method" n="buf" id="src/./svector.h::svector::buf" overloads="2" k="0.0135">
</s>
</f>
<f p="src/./scipoverlay.h">
<s t="method" n="empty" id="src/./scipoverlay.h::ScipOverlay::empty" k="0.0143">
</s>
</f>
</r>
`````

## `./build/ripwire . --eval`

*Self-eval: co-change recall vs BM25.*

**wall time: 2.41s**

`````
ripwire --eval  (co-change recovery, averaged over 80 historical commits)
  ranker     recall@5  recall@10  recall@20
  ripwire        2.6%       9.9%      14.6%
  BM25          12.8%      21.0%      29.1%
  BM25sub       14.1%      24.8%      31.8%
  BM25body      25.4%      38.7%      46.1%
  fused         11.4%      16.3%      20.6%
  anchored      25.4%      37.4%      46.1%
  same-dir       5.4%      12.3%      18.4%
  random         0.5%       0.9%       1.9%   <- floor (random ranking over F=1081 files)
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

**wall time: 3.77s**

`````
ripwire --eval-retrieval  (known-item, 150 doc-commented symbols; gold is in-corpus by construction)
  ranker    query-mode     MRR  recall@1  recall@5 recall@10
  subtoken  name         0.683     56.0%     83.3%     92.0%
  subtoken  doc-phrase   0.798     75.3%     83.3%     86.0%
  name-exact name         0.876     81.3%     96.7%     99.3%
  name-exact doc-phrase   0.002      0.0%      0.0%      0.7%
  anchored  name         0.682     55.3%     84.7%     88.7%
  anchored  doc-phrase   0.799     76.7%     82.7%     84.7%
  routed    name         0.876     81.3%     96.7%     99.3%
  routed    doc-phrase   0.794     75.3%     82.7%     85.3%
  note: routing chose name-exact on 150/150 NAME queries (a NAME query is always identifier-shaped);
        the confidence gate routes doc-phrase queries to name-exact ONLY when EVERY content word names a symbol
        (or an explicit camel/snake token appears), so conceptual prose falls back to subtoken+body — routed tracks
        the better ranker on BOTH modes (routed==name-exact on name, ~=subtoken+body on doc-phrase).
`````

## `./build/ripwire . --eval-stray=<scratch>/aux/stray_labels2.tsv`

*Labelled verdict-accuracy eval for --stray-content (3 hand-labelled refs).*

**exit code: 3**

Input file:

`````
# ref<TAB>verdict labels for --eval-stray
lane-notes	merged
lane-abi	merged
lane-docdrift	unmerged
`````

`````
<!-- ripwire stray-content eval: labelled verdict accuracy. Each row is one branch whose true state was established by hand; want= is the label, got= is what the classifier said. A branch absent from the report scores as merged (merged refs are omitted by design). Use this to MEASURE a threshold change instead of eyeballing it. -->
<stray-eval cases="3" correct="2" accuracy="66.7">
<case ref="lane-notes" want="merged" got="merged" hit="1" reported="0"/>
<case ref="lane-abi" want="merged" got="merged" hit="1" reported="0"/>
<case ref="lane-docdrift" want="unmerged" got="merged" hit="0" reported="0"/>
</stray-eval>
`````

## `./build/ripwire skills --eval-skills=<scratch>/aux/skills_labels2.tsv`

*Labelled skill-ROUTING eval over the repo's own skills/ directory (4 hand-labelled prompts).*

Input file:

`````
orient in an unfamiliar codebase fast	ripwire-orient	judged
who calls this function and what is the blast radius	ripwire-navigate	judged
plan parallel worktrees so the lanes do not collide	ripwire-change-check	judged
what is the weather in Paris	none	neg
`````

`````
ripwire --eval-skills  (skill routing over K=17 candidate skills [ripwire-router excluded]; 3 positive + 1 negative prompts; corpus '<scratch>/aux/skills_labels2.tsv'; split test=4 dev=0)
  arm           hit@1   hit@2     mrr   sep-auc   fire/abstain@ORACLE-th (upper bound)
  overlap       66.7%  100.0%   0.833     0.500    50.0% (th=-1.000)
  name          33.3%   66.7%   0.533     0.667    50.0% (th=0.000)
  bm25-desc    100.0%  100.0%   1.000     1.000   100.0% (th=1.993)
  bm25-full     33.3%  100.0%   0.667     1.000    50.0% (th=0.265)
  for-routed    33.3%  100.0%   0.667     1.000    50.0% (th=3.115)
  random         5.9%   11.8%   0.202     0.500   <- floor (uniform-random ranking; auc 0.5 by definition)
  provenance hit@1 (bm25-desc): router 0/0, desc 0/0, judged 3/3 (desc rows quote the descriptions - expect them easiest; judged is the honest number)
  judged-only hit@1 per arm: overlap 2/3, name 1/3, bm25-desc 3/3, bm25-full 1/3, for-routed 1/3
  router-magnet: with ripwire-router ADMITTED as a candidate it takes top-1 on 0/3 positive prompts (bm25-desc arm) - why it is excluded above
  per-skill (bm25-desc): name / permitted-rows / won / pos-fires / false-fires / neg-fires
    ripwire-before-you-build     0     0     0     0     0
    ripwire-change-check         1     1     1     0     1
    ripwire-efficient            0     0     0     0     0
    ripwire-find-bug             0     0     0     0     0
    ripwire-fresh-eyes           0     0     0     0     0
    ripwire-graph-query          0     0     0     0     0
    ripwire-handoff              0     0     0     0     0
    ripwire-layers               0     0     0     0     0
    ripwire-mcp                  0     0     0     0     0
    ripwire-navigate             1     1     1     0     0
    ripwire-opt-remarks          0     0     0     0     0
    ripwire-orient               1     1     1     0     0
    ripwire-perf-target          0     0     0     0     0
    ripwire-quality-bar          0     0     0     0     0
    ripwire-reuse-first          0     0     0     0     0
    ripwire-security-scan        0     0     0     0     0
    ripwire-write-tests          0     0     0     0     0
  misses (overlap):
… [20 more lines, 3606 bytes total]
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
#
# context wiring — a binary on PATH is invisible to an agent until its rules file says when
# to reach for it. Paste the block below into CLAUDE.md:
# --- paste into CLAUDE.md ---
## ripwire — deterministic codebase maps (on PATH as `ripwire`)
Reach for it BEFORE blind grep + whole-file reads. First call ~1s cold; after that warm, ~0.1s.
- Orient on a task: `ripwire <dir> --for="<task in words>"` — ranked, quality-annotated
  signatures. Paste symbol/file names from the issue verbatim; named mentions get anchored.
- Everything at once under one token budget: `ripwire <dir> --pack-task="<task>"`.
- Have a stack trace / build error: `ripwire <dir> --from-trace=FILE` (`-` = stdin) —
  paste the error, don't paraphrase it into a query.
- Who calls X: `--callers=SYM`. "Is it safe to change X?" needs the full blast radius:
  `--impact=SYM` (transitive) plus `--uses=SYM` (every read/write/import site).
- Just edited a symbol: `--edit-check=SYM` — contract change + newly incompatible callers.
- Before writing a new fn/class/helper: `--exemplar="<what you're writing>"` — duplicates
  are born on tasks that feel too small to tool up for.
- Before calling work done: `--quality-delta` (what you made worse), then `--test-gate`.
- Trust notes: counts marked counts_floor are floors, not totals; a zero means "none
  found", never "none exists".
# --- end paste ---
`````

## `./build/ripwire --version`

*Version + short build info.*

`````
ripwire 0.2.1 (dev, AppleClang 21.0.0.21000101)
`````


---

# the dirty-tree verbs (throwaway clone, NOT the read-only repo)

Everything below runs with `cwd` = the throwaway clone at `<scratch>/dirty` (`git clone --local` of this repo, then one deliberate regression in `src/sortutil.h`). The read-only repo is never touched. The binary is the same `build/ripwire`, addressed absolutely.

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
        (388 test/*.sh gates are NOT modelled: script-to-binary edges are not call edges, so they never appear here — a path count, not every one invokes the binary)
  [3] co-change — usually edited with these but NOT in your diff (0):
        (none, or no git history)
`````

## `./build/ripwire . --test-gate`

*The pre-PR gate with real obligations — exit 4 when tests-to-run or untested blast radius is non-empty.*

**exit code: 4**

`````
<!-- ripwire test-gate (TDAD-parity, arXiv 2603.17973): the tests to run for this change + the UNTESTED blast radius. A queryable call-graph+test map cut agent-caused regressions -70% (6.08%->1.82%); this gate names the obligations, the agent runs the tests then relies on green. exit 4 if tests OR untested is non-empty. TWO INDEPENDENT LISTINGS, each with its own row count: shown_tests= counts the <t> tests-to-run rows and shown_untested= counts the <u> blast-radius rows (a single shown= could only ever have described one of them). The <t> rows are the COMPLETE obligation and are never windowed, so they REPEAT VERBATIM on every page — a walker that concatenates pages must take them from one page only; offset=/limit= window the <u> rows alone. The <u> listing shows 25 rows by default: raise the default cap with limit=N (offset=M pages). script_gates_unmodelled= counts test/*.sh runners in the corpus (a path count; not every one invokes the binary) - script-to-binary edges are NOT modelled, so those gates are invisible to this walk and never counted in tests=. UNIT: untested= here counts impacted SYMBOLS. The seams verb spells untested= over cross-directory call EDGES and the flip verb over the defs a gate lights, so the three numbers count three different things and must never be compared or summed across verbs. -->
<test-gate changed="1" impacted="80" tests="2" untested="76" shown_tests="2" tests_capped="0" shown_untested="25" untested_capped="1" script_gates_unmodelled="388" at="33f9f7be2+dirty">
<t p="./test/adaptivecutshapefix/adaptive_cut_shape_test.cpp" run="bash test/adaptivecutshapecheck.sh"/>
<t p="./test/verify_radix.cpp"/>
<u sym="buildGraph" p="./src/graph.h" ccx="698"/>
<u sym="dispatchMcpLine" p="./src/mcp.h" ccx="422"/>
<u sym="main" p="./src/main.cpp" ccx="381"/>
<u sym="runQualityDelta" p="./src/main.cpp" ccx="197"/>
<u sym="packSignatures" p="./src/serialize.h" ccx="197"/>
<u sym="serialize" p="./src/serialize.h" ccx="185"/>
<u sym="runDefaultMap" p="./src/main.cpp" ccx="177"/>
<u sym="runForLens" p="./src/main.cpp" ccx="163"/>
<u sym="packTaskBundleText" p="./src/packtask.h" ccx="133"/>
<u sym="runBatchSub" p="./src/mcpverbs.h" ccx="98"/>
<u sym="packLego" p="./src/serialize.h" ccx="82"/>
<u sym="serializeJson" p="./src/serialize.h" ccx="82"/>
<u sym="runMcpHttp" p="./src/mcpserver.h" ccx="79"/>
<u sym="fetchBody" p="./src/mcpverbs.h" ccx="72"/>
<u sym="runEval" p="./src/eval.h" ccx="66"/>
<u sym="forTaskText" p="./src/mcpverbs.h" ccx="42"/>
<u sym="qualityDeltaJson" p="./src/mcpverbs.h" ccx="40"/>
<u sym="getIndex" p="./src/mcpindex.h" ccx="37"/>
<u sym="runTargetedViews" p="./src/main.cpp" ccx="32"/>
<u sym="packTaskText" p="./src/mcpverbs.h" ccx="29"/>
<u sym="packTaskPartitionText" p="./src/partition.h" ccx="27"/>
<u sym="packSignaturesJson" p="./src/serialize.h" ccx="26"/>
<u sym="packGraphBlock" p="./src/serialize.h" ccx="24"/>
<u sym="situationDiffJson" p="./src/mcpverbs.h" ccx="23"/>
<u sym="usesText" p="./src/mcpverbs.h" ccx="23"/>
</test-gate>
`````

## `./build/ripwire . --quality-delta`

*CHANGED: every row now carries p="file:line", the gating rows are marked gating="1", and exit 2 prints a naming line on stderr.*

**exit code: 2** — **wall time: 2.22s**

`````
<!-- ripwire quality-delta: only what a change made WORSE against the floor named by baseline= below. FOUR floors, and they are not interchangeable: sidecar = the pinned .ripwire_quality_baseline snapshot, honored only because it was pinned at the CURRENT git HEAD; git-HEAD = no sidecar existed, so the working tree was auto-compared against the HEAD tree; git-HEAD (stale sidecar removed) = a sidecar existed, was pinned at a DIFFERENT sha, and this run DELETED it from your working tree before falling back to HEAD (re-pin with quality-baseline); git-HEAD (stale sidecar ignored) = same staleness verdict, but the file was left on disk (the read-only MCP arm, or an unlink that failed). Only the first is a floor YOU chose; the other three compare against HEAD, so anything already committed cannot appear. at= is the git commit (plus a dirty marker when the working tree differs) this list was computed at. Findings: complexity over the ccx bar, verbosity (LOC)/nesting/params regressions, new duplication, newly-dead, new public api-surface (contract drift), error-masking, short-horizon churn, new clone of a reused helper. THREE independent axes, applied in this order: (1) acked findings are suppressed entirely (acked= counts them, honestly); (2) ORIGIN — a finding on a symbol that EXISTED at the baseline is preexisting-worse (no origin= attribute), one that exists only because the code is NEW carries origin="new-symbol"; (3) MATERIALITY — a small numeric delta is sev="minor". EXIT 2 fires only on preexisting-worse AND major, i.e. gating="N" above; new-symbol rows never gate. Clone kinds classify by their member set (a group is new-symbol only if EVERY member is new); short-horizon-churn is preexisting by construction. exit 0 is NOT a verdict on the new-symbol rows — nothing that existed got worse, but the new debt is yours: read them. LIMIT: origin is canonId identity (path::scope::name), so a RENAMED or MOVED symbol reads as new — a regression carried in with a move classifies new-symbol and will not gate. Descriptive: weigh + fix the real ones, do not game the number (a wrong abstraction beats a low score). Each row carries kind= (which of the measured axes regressed) and sym= (the canonical id it regressed on) — except duplication rows, which name the whole clone group rather than one symbol: members= is the group's member list and tokens= its shared normalized-token count (the same per-group pair the clones verb reports) — plus p="path:line" (root-relative; the first-sorting member for the clone kinds; omitted, never faked, when no locator resolves), and every row the header's gating= counter counts also carries a gating attribute set to 1 — those are the rows the exit code fires on, and they are now marked positively rather than by the ABSENCE of sev/origin. (This sentence deliberately spells no attribute=value literal: the header counters are parsed by grep in several gates, and a quoted numeric example here would be matched first.) -->
<quality-delta baseline="git-HEAD" regressions="10" minor="2" acked="0" preexisting-worse="7" new-symbol="3" gating="7" at="33f9f7be2+dirty">
<r kind="api-surface" sym="src/sortutil.h::rw::sortutil::nonNegativeFloatAscKeyCopy" sev="minor" surface="new-symbol" origin="new-symbol" p="src/sortutil.h:84"/>
<r kind="api-surface" sym="src/sortutil.h::rw::sortutil::nonNegativeFloatDescKey" was="1" now="2" surface="contract-change" p="src/sortutil.h:74" gating="1"/>
<r kind="api-surface" sym="src/sortutil.h::rw::sortutil::sortScoredIdsWithOptions" sev="minor" surface="new-symbol" origin="new-symbol" p="src/sortutil.h:94"/>
<r kind="complexity" sym="src/sortutil.h::rw::sortutil::lessByScoreDescId" was="1" now="67" p="src/sortutil.h:14" gating="1"/>
<r kind="duplication" members="src/sortutil.h::rw::sortutil::nonNegativeFloatAscKeyCopy | src/sortutil.h::rw::sortutil::nonNegativeFloatDescKey" tokens="59" p="src/sortutil.h:84" gating="1"/>
<r kind="nesting" sym="src/sortutil.h::rw::sortutil::lessByScoreDescId" was="1" now="6" p="src/sortutil.h:14" gating="1"/>
<r kind="new-clone-of-reused-helper" sym="src/sortutil.h::rw::sortutil::nonNegativeFloatAscKeyCopy | src/sortutil.h::rw::sortutil::nonNegativeFloatDescKey" was="0" now="4" p="src/sortutil.h:84" gating="1"/>
<r kind="params" sym="src/sortutil.h::rw::sortutil::sortScoredIdsWithOptions" was="0" now="8" origin="new-symbol" p="src/sortutil.h:94"/>
<r kind="short-horizon-churn" sym="src/sortutil.h::rw::sortutil::lessByScoreDescId" was="0" now="3" churn="self" p="src/sortutil.h:14" gating="1"/>
<r kind="short-horizon-churn" sym="src/sortutil.h::rw::sortutil::nonNegativeFloatDescKey" was="0" now="3" churn="self" p="src/sortutil.h:74" gating="1"/>
</quality-delta>
`````

stderr:

`````
ripwire: no ./.ripwire_quality_baseline — auto-comparing the working tree vs git HEAD (commit the baseline with --quality-baseline to pin it)
ripwire: --quality-delta gating: 7 preexisting-worse major finding(s); first: api-surface ./src/sortutil.h::rw::sortutil::nonNegativeFloatDescKey at src/sortutil.h:74 (was=1 now=2)
`````

## `./build/ripwire . --quality-delta --json`

*The same findings as JSON (one of the CI/scripting verbs --json supports).*

**exit code: 2**

`````
{"baseline":"git-HEAD","regressions":10,"minor":2,"acked":0,"preexisting-worse":7,"new-symbol":3,"gating":7,"at":"33f9f7be2+dirty","r":[{"kind":"api-surface","sym":"src/sortutil.h::rw::sortutil::nonNegativeFloatAscKeyCopy","p":"src/sortutil.h:84","sev":"minor","surface":"new-symbol","origin":"new-sy … [line truncated: 7 more bytes on this line]
{"kind":"api-surface","sym":"src/sortutil.h::rw::sortutil::nonNegativeFloatDescKey","was":1,"now":2,"p":"src/sortutil.h:74","gating":true,"surface":"contract-change"},
{"kind":"api-surface","sym":"src/sortutil.h::rw::sortutil::sortScoredIdsWithOptions","p":"src/sortutil.h:94","sev":"minor","surface":"new-symbol","origin":"new-symbol"},
{"kind":"complexity","sym":"src/sortutil.h::rw::sortutil::lessByScoreDescId","was":1,"now":67,"p":"src/sortutil.h:14","gating":true},
{"kind":"duplication","members":"src/sortutil.h::rw::sortutil::nonNegativeFloatAscKeyCopy | src/sortutil.h::rw::sortutil::nonNegativeFloatDescKey","tokens":59,"p":"src/sortutil.h:84","gating":true},
{"kind":"nesting","sym":"src/sortutil.h::rw::sortutil::lessByScoreDescId","was":1,"now":6,"p":"src/sortutil.h:14","gating":true},
{"kind":"new-clone-of-reused-helper","sym":"src/sortutil.h::rw::sortutil::nonNegativeFloatAscKeyCopy | src/sortutil.h::rw::sortutil::nonNegativeFloatDescKey","was":0,"now":4,"p":"src/sortutil.h:84","gating":true},
{"kind":"params","sym":"src/sortutil.h::rw::sortutil::sortScoredIdsWithOptions","was":0,"now":8,"p":"src/sortutil.h:94","origin":"new-symbol"},
{"kind":"short-horizon-churn","sym":"src/sortutil.h::rw::sortutil::lessByScoreDescId","was":0,"now":3,"p":"src/sortutil.h:14","gating":true,"churn":"self"},
{"kind":"short-horizon-churn","sym":"src/sortutil.h::rw::sortutil::nonNegativeFloatDescKey","was":0,"now":3,"p":"src/sortutil.h:74","gating":true,"churn":"self"}]}
`````

stderr:

`````
ripwire: no ./.ripwire_quality_baseline — auto-comparing the working tree vs git HEAD (commit the baseline with --quality-baseline to pin it)
ripwire: --quality-delta gating: 7 preexisting-worse major finding(s); first: api-surface ./src/sortutil.h::rw::sortutil::nonNegativeFloatDescKey at src/sortutil.h:74 (was=1 now=2)
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
<!-- ripwire quality-delta: only what a change made WORSE against the floor named by baseline= below. FOUR floors, and they are not interchangeable: sidecar = the pinned .ripwire_quality_baseline snapshot, honored only because it was pinned at the CURRENT git HEAD; git-HEAD = no sidecar existed, so the working tree was auto-compared against the HEAD tree; git-HEAD (stale sidecar removed) = a sidecar existed, was pinned at a DIFFERENT sha, and this run DELETED it from your working tree before falling back to HEAD (re-pin with quality-baseline); git-HEAD (stale sidecar ignored) = same staleness verdict, but the file was left on disk (the read-only MCP arm, or an unlink that failed). Only the first is a floor YOU chose; the other three compare against HEAD, so anything already committed cannot appear. at= is the git commit (plus a dirty marker when the working tree differs) this list was computed at. Findings: complexity over the ccx bar, verbosity (LOC)/nesting/params regressions, new duplication, newly-dead, new public api-surface (contract drift), error-masking, short-horizon churn, new clone of a reused helper. THREE independent axes, applied in this order: (1) acked findings are suppressed entirely (acked= counts them, honestly); (2) ORIGIN — a finding on a symbol that EXISTED at the baseline is preexisting-worse (no origin= attribute), one that exists only because the code is NEW carries origin="new-symbol"; (3) MATERIALITY — a small numeric delta is sev="minor". EXIT 2 fires only on preexisting-worse AND major, i.e. gating="N" above; new-symbol rows never gate. Clone kinds classify by their member set (a group is new-symbol only if EVERY member is new); short-horizon-churn is preexisting by construction. exit 0 is NOT a verdict on the new-symbol rows — nothing that existed got worse, but the new debt is yours: read them. LIMIT: origin is canonId identity (path::scope::name), so a RENAMED or MOVED symbol reads as new — a regression carried in with a move classifies new-symbol and will not gate. Descriptive: weigh + fix the real ones, do not game the number (a wrong abstraction beats a low score). Each row carries kind= (which of the measured axes regressed) and sym= (the canonical id it regressed on) — except duplication rows, which name the whole clone group rather than one symbol: members= is the group's member list and tokens= its shared normalized-token count (the same per-group pair the clones verb reports) — plus p="path:line" (root-relative; the first-sorting member for the clone kinds; omitted, never faked, when no locator resolves), and every row the header's gating= counter counts also carries a gating attribute set to 1 — those are the rows the exit code fires on, and they are now marked positively rather than by the ABSENCE of sev/origin. (This sentence deliberately spells no attribute=value literal: the header counters are parsed by grep in several gates, and a quoted numeric example here would be matched first.) -->
<quality-delta baseline="git-HEAD" regressions="7" minor="0" acked="3" preexisting-worse="6" new-symbol="1" gating="6" at="33f9f7be2+dirty">
<r kind="complexity" sym="src/sortutil.h::rw::sortutil::lessByScoreDescId" was="1" now="67" p="src/sortutil.h:14" gating="1"/>
<r kind="duplication" members="src/sortutil.h::rw::sortutil::nonNegativeFloatAscKeyCopy | src/sortutil.h::rw::sortutil::nonNegativeFloatDescKey" tokens="59" p="src/sortutil.h:84" gating="1"/>
<r kind="nesting" sym="src/sortutil.h::rw::sortutil::lessByScoreDescId" was="1" now="6" p="src/sortutil.h:14" gating="1"/>
<r kind="new-clone-of-reused-helper" sym="src/sortutil.h::rw::sortutil::nonNegativeFloatAscKeyCopy | src/sortutil.h::rw::sortutil::nonNegativeFloatDescKey" was="0" now="4" p="src/sortutil.h:84" gating="1"/>
<r kind="params" sym="src/sortutil.h::rw::sortutil::sortScoredIdsWithOptions" was="0" now="8" origin="new-symbol" p="src/sortutil.h:94"/>
<r kind="short-horizon-churn" sym="src/sortutil.h::rw::sortutil::lessByScoreDescId" was="0" now="3" churn="self" p="src/sortutil.h:14" gating="1"/>
<r kind="short-horizon-churn" sym="src/sortutil.h::rw::sortutil::nonNegativeFloatDescKey" was="0" now="3" churn="self" p="src/sortutil.h:74" gating="1"/>
</quality-delta>
`````

stderr:

`````
ripwire: no ./.ripwire_quality_baseline — auto-comparing the working tree vs git HEAD (commit the baseline with --quality-baseline to pin it)
ripwire: --quality-delta gating: 6 preexisting-worse major finding(s); first: complexity ./src/sortutil.h::rw::sortutil::lessByScoreDescId at src/sortutil.h:14 (was=1 now=67)
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
<edit-check sym="nonNegativeFloatDescKey" t="fn" p="./src/sortutil.h:74" status="contract-change" defs="1" params_was="1" params_now="2" public_was="1" public_now="1" defs_was="1" defs_now="1" change="params,broken-callers" callers="4" incompatible="4" at="33f9f7be2+dirty" counts_floor="1">
<c n="benchScores" p="./bench/bench_radix_ab.cpp:133" incompatible="1"/>
<c n="benchAdaptive" p="./bench/bench_radix_ab.cpp:157" incompatible="1"/>
<c n="radixSortNonNegativeFloatsDesc" p="./src/sortutil.h:103" incompatible="1"/>
<c n="radixSortByScoreDescId" p="./src/sortutil.h:118" incompatible="1"/>
</edit-check>
`````

## `./build/ripwire . --pr-context`

*The review-evidence bundle with an actual changed file.*

`````
<!-- ripwire pr-context: no-LLM review-evidence bundle per changed file — defined symbols, their callers, blast radius (transitive dependents), affected tests, co-change partners not in the diff, and owners. base=working-tree. skipped_mode_only=diffs that changed a file's MODE and nothing else (e.g. chmod) excluded from the changed set; a pure RENAME is content-identical too but is NOT excluded — it is a changed file, listed at its new path. files= means two different things by DEPTH here and is deliberately not renamed (15 consumers read the root one): on the ROOT it is the CHANGED file count; on each <impact/> child it is the distinct files dependents= reaches (changed + non-changed), so dependents="0" implies files="0" and vice versa — never an impossible-looking dependents>0/files=0. files_other= on the same <impact/> is the non-changed subset (a changed file's dependents inside OTHER changed files have no <f> row of their own — they are already shown as their own <file> section); it is NOT the <f> row count — see the row-cap sentence below. Files are ordered by BLAST RADIUS (transitive dependents descending, path breaking ties), not alphabetically. sections= on changed-symbols counts a doc file's headings, collapsed into that number instead of one callers-zero row each; count= still counts every INDEXED symbol, sections included, so count minus sections is the number of rows that follow. Every nested list below is a TOP-N subset of its element's own total, fixed per element (impact <f> at 20, per-symbol <caller> at 12, cochange <partner> at 12, tests <test> at 40, owners <author> at 5 — the L0 defaults; max-tokens only lowers these further via the trim ladder, nothing raises them past L0): each capped element carries its own shown=/capped= pair so the cut is never silent — for the untrimmed list use impact=SYM/callers=SYM (blast radius/callers), affected=FILE or situ (tests), cochange (partners), or owners (authors) instead. direction= names which SIDE this bundle reviews (worktree-since-head, head-since-fork, head-since-ref-tip); a no-ref-work row says the base ref's tip IS the merge base, i.e. it carries no divergent work of its own. deterministic. counts_floor="1" means every count on this element is a FLOOR, never a total. Call edges are extracted from source text by NAME, so a call that reaches its target through dynamic dispatch (a virtual, interface or duck-typed receiver), a callback or function pointer, a macro-generated call site, or a declaration that parses without a call expression (C++ most-vexing-parse) contributes no edge and is missing here. Read a zero as "none found", never as "none exists". COUNTING UNIT, and it differs by verb — which is why two of them report different numbers for one symbol. The callers, callees, edit-check, graph-query and pr-context counts are DISTINCT SYMBOLS: repeated calls from one caller, and calls to two overloads of one name, collapse into ONE row, their multiplicity surviving only in the call graph's edge weight. The reach counts (impact's reaches=, pr-context's dependents=) are the size of a transitive reach SET, each symbol counted once — not a count of calls or edges. The uses verb counts call SITES, one row per occurrence, so a larger count= there for the same symbol is these units agreeing, not disagreeing. The map header's edges= is a unit again different — distinct (caller,callee) PAIRS — and that document carries neither this marker nor this clause, so its numbers answer a different question. -->
<pr-context base="working-tree" direction="worktree-since-head" files="1" skipped_mode_only="0" at="33f9f7be2+dirty" counts_floor="1">
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
… [72 more display lines; full output is 8608 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --map-diff --top-k=5`

*The map re-ranked with a teleport toward the changed file (changed=1 here, not 0).*

`````
<!-- ripwire v1 t=fn|method|cls|struct|iface|var|sec p=path layer=arch-layer(opt) n=name id=canonical(path::scope::name,when-scoped) k=rank c=call amb=ambiguous-calls(read-source) overloads=N-same-name-defs-merged-into-this-row(absent-if-1;shown=counts-them-individually,so-rows+sum(overloads-1)=shown) prov=scip(precise;else name-based) hdr:unresolved=call-name-defined-only-in-a-lang-incompatible-file (edges heuristic) r:est_tokens=hdr-copy(none-if-stable) -->
<!-- at= is the git commit these numbers were computed at; a trailing +dirty means the working tree differed from that commit, so the numbers describe the tree, not the commit -->
<!-- files=1081 symbols=8837 edges=10482 shown=5 est_tokens=682 ambiguous=3045 unresolved=1326 precise=3 changed=1 skipped_oversize=14 order=important-first -->
<r at="33f9f7be2+dirty" est_tokens="682">
<f p="./src/svector.h">
<s t="method" n="size" id="./src/svector.h::svector::size" k="0.1185">
</s>
</f>
<f p="./src/sortutil.h">
<s t="fn" n="radixSortByScoreDescId" id="./src/sortutil.h::rw::sortutil::radixSortByScoreDescId" amb="6" k="0.0965">
<c n="lessByScoreDescId"/>
<c n="radixSortUint32ByKey"/>
<c n="nonNegativeFloatDescKey"/>
<c n="size"/>
<c n="begin"/>
<c n="end"/>
<c n="begin"/>
<c n="end"/>
</s>
<s t="fn" n="radixSortByFromTo" id="./src/sortutil.h::rw::sortutil::radixSortByFromTo" amb="2" k="0.0661">
<c n="sortKeySmall"/>
<c n="lessByFromTo"/>
<c n="size"/>
<c n="begin"/>
<c n="end"/>
<c n="begin"/>
<c n="end"/>
</s>
<s t="fn" n="nonNegativeFloatDescKey" id="./src/sortutil.h::rw::sortutil::nonNegativeFloatDescKey" k="0.0657">
</s>
<s t="fn" n="lessByScoreDescId" id="./src/sortutil.h::rw::sortutil::lessByScoreDescId" k="0.0568">
<c n="size"/>
</s>
</f>
</r>
`````

## `./build/ripwire . --clones`

*The duplicated helper the sandbox edit introduced shows up as a clone group.*

`````
<!-- ripwire clones: function bodies with similar normalized token streams (identifiers/literals normalized, so renamed copies match). type=2 exact/renamed (Type-1/2); type=3 gapped near-miss (an inserted/changed statement, similarity in [0.80,1.0)). Reuse don't reimplement; a fix to one likely belongs in all. groups= and type3= are the two GROUP-TYPE totals (each capped independently, so neither is the row count); total= is the true row total (groups + type3-group-count) and is ALWAYS present, paged or not; shown= is the number of group rows that follow this run. capped="1" means rows were dropped. exempt= on a group ⇒ every member is on a path the quality-delta verb's duplication kind deliberately ignores (fixture dirs / shell test-runners repeat boilerplate by convention) — a fact here, never a gate there; exempt_groups= counts them over ALL groups. raise the default cap with limit=N (offset=M pages). -->
<clones groups="54" type3="197" total="251" exempt_groups="92" shown="80" capped="1">
<group type="2" tokens="207" n="4" exempt="shell-runner">
<f n="batch_sub" p="./test/mcpclidiffcheck.sh:63"/>
<f n="batch_sub" p="./test/mcptranchecheck.sh:55"/>
<f n="batch_sub" p="./test/mcpw2fixcheck.sh:52"/>
<f n="batch_sub" p="./test/mcpw3fixcheck.sh:51"/>
</group>
<group type="2" tokens="149" n="3" exempt="shell-runner">
<f n="monotonic_check" p="./test/pyimportprecisecheck.sh:89"/>
<f n="monotonic_check" p="./test/rustimportprecisecheck.sh:124"/>
<f n="monotonic_check" p="./test/tsimportprecisecheck.sh:88"/>
</group>
<group type="2" tokens="142" n="2">
<f n="test_tier2_accept_big_quality_small_cost" p="./bench/locbench/test_compare_gate.py:130"/>
<f n="test_tier2_reject_small_quality_big_cost" p="./bench/locbench/test_compare_gate.py:143"/>
</group>
<group type="2" tokens="126" n="2">
<f n="addWholeFileFn" p="./test/cloneband_harness.cpp:64"/>
<f n="addWholeFileFn" p="./test/type3clone_harness.cpp:47"/>
</group>
<group type="2" tokens="118" n="2">
<f n="rankFiles" p="./src/eval.h:53"/>
<f n="rankCandidates" p="./src/skilleval.h:426"/>
</group>
<group type="2" tokens="114" n="2">
<f n="timer" p="./bench/representative_perfgate.sh:54"/>
<f n="run_once_ms" p="./test/mergescoutcheck.sh:268"/>
</group>
<group type="2" tokens="112" n="2">
… [306 more display lines; full output is 15213 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --stray-content=zz-orphan`

*CHANGED: a ref with NO merge base with HEAD now reports v="unknown" ok="0" in its own bucket — the absence of an answer, never a claim it is merged. (The sandbox carries a deliberately parentless branch built with `git commit-tree`; a shallow CI clone puts every ref here.)*

`````
<!-- ripwire stray-content: per ref, the lines its own divergent work AUTHORED (vs its merge-base with HEAD) that the live line does NOT have. v="superseded" means the live line removed the same base code this ref removed (redone/del) — it re-implemented the work, the case `git cherry` cannot see; v="unmerged" means the work is genuinely absent; merged refs are omitted. Read-only: git cat-file/diff/ls-tree only, one batched cat-file for the whole sweep, every blob reduced once per sha. Line-granular, not semantic: see the ripwire help text for the limits. ANCHORING is a deliberate hybrid: the SCOPE is base anchored (only lines the ref itself authored vs its merge base are ever considered, so a file the ref never opened cannot appear because the live line moved), while the ABSENCE test is HEAD anchored on purpose (does the live line have this content TODAY is the question being asked, and it is only answerable against live HEAD). v="unknown" with ok="0" means this ref could NOT be analysed at all because it has no merge base with HEAD, which on a SHALLOW clone (the checkout default in CI) is every ref: it is not a claim that the ref is merged, and the fix is to deepen the clone. The four buckets are exhaustive, so unmerged plus superseded plus merged plus unknown always equals refs. SCOPE: refs/heads only, which is every local branch (worktree branches included). Remote tracking refs are NOT scanned: they mirror local ones in the usual checkout and would double every row. The consequence on a FRESH CLONE, where the branches live under refs/remotes/origin and only the checked out one has a local head, is that there is nothing here to be stray FROM; refs= is that fact as a number. TRUNCATION: a ref row ends with a more element (more files=N) when its own file listing was capped; shown plus that number equals the ref's files= total, always. That inner listing is a SECONDARY listing (it repeats complete and identical on every page) and is capped by detail, not by limit / offset, which page the OUTER ref listing and report their own shown= / capped=. -->
<stray-content head="33f9f7be2" head_ref="worktree-agent-a22b630900f285f04" refs="1" blobs="0" unmerged="0" superseded="0" merged="0" unknown="1">
<ref name="zz-orphan-lane" tip="7c9563586" date="2026-08-08" base="" ok="0" v="unknown" stray="0" files="0" superseded="0">
</ref>
</stray-content>
`````

stderr:

`````
[math degraded] crossref: no merge-base for ref (shallow clone or unrelated history?) — verdict is unknown, not merged  (crossref.h:1002, RefPlumbing rw::crossref::probeRefBase(const std::string &, const RefInfo &, const std::string &) — logged once per site)
`````

## `./build/ripwire . --stray-content=zz-orphan --plan`

*CHANGED: --plan surfaces those same refs as an <undetermined> row rather than silently dropping them.*

`````
<!-- ripwire landing-plan: stray-content's cheap per-blob sweep composed with merge-scout's per-arm overlap oracle — of every local branch, which still hold REAL work (v="unmerged"), which were already re-implemented on the live line (v="superseded", EXCLUDED below — landing them re-does work that is already done) or are already merged (omitted entirely, counted in merged= on the root element), and the fewest-conflicts-first order to land what remains. scouted="0" on an unmerged ref means it was NOT fed to merge-scout this run (the cost bound, not a verdict) — it is still real, unscouted work; bounded= on the root element counts them and detail lifts the bound. merge-scout is the EXPENSIVE step here (git-archive + full ingest per arm) — stray-content's own sweep is the cheap one. An undetermined row is a ref that could NOT be analysed at all (no merge base with HEAD, which on a SHALLOW clone is every ref): it is neither scouted nor excluded nor merged, because nothing was measured — treat it as unfinished business and deepen the clone, never as a clean branch. Read-only throughout: no checkout, no ref write, no working-tree mutation. The root carries BOTH head= and at= and they are the same commit: head= is the bare 9 hex chars this verb has always printed, at= is the tool wide anchor and is head= plus a "+dirty" suffix when the working tree is not clean. Prefer at= (it is the one spelling every other repo reading verb uses, and the only one that tells you whether uncommitted work was in scope); head= is kept for callers already keyed to it. -->
<landing-plan head="33f9f7be2" refs="1" unmerged="0" superseded="0" merged="0" undetermined="1" scouted="0" bounded="0" scout-ok="1" at="33f9f7be2+dirty">
<undetermined name="zz-orphan-lane" v="unknown" reason="no merge base with HEAD (shallow clone or unrelated history) — this ref could not be analysed, it is NOT known to be merged; deepen the clone and re-run"/>
</landing-plan>
`````

stderr:

`````
[math degraded] crossref: no merge-base for ref (shallow clone or unrelated history?) — verdict is unknown, not merged  (crossref.h:1002, RefPlumbing rw::crossref::probeRefBase(const std::string &, const RefInfo &, const std::string &) — logged once per site)
`````
