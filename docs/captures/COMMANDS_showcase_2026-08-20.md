# ripwire — every verb, run for real

- **Date:** 2026-08-20 (regenerated capture; supersedes any older `docs/captures/COMMANDS_showcase_*.md`)
- **Lives in `docs/captures/`** — a directory the crawl/retrieval lenses SKIP (`kCrawlSkipDirs`, src/ingest.h): a generated doc that quotes every verb's output out-scores the source for any query about the tool and was measured at 77% of `--recall` on this repo when it sat at the root. `test/argvdiffcheck.sh` harvests its `## `-heading command lines as differential vectors — keep that format.
- **Version:** `ripwire 0.3.8 (dev, AppleClang 21.0.0.21000101)`
- **Repo:** the ripwire repo @ `700e51d` — **CLEAN — `git status --porcelain` is empty**. The diff-aware verbs (`--situ`/`--test-gate`/`--quality-delta`/`--pr-context`/`--map-diff`/`--edit-check`) answer a question about the WORKING TREE, so that condition is part of their answer and every one of their captions below states which tree it recorded against. A clean tree is the honest default for a showcase, so they appear TWICE: once here on the clean tree (their empty/exit-0 shape) and once in the final section against a throwaway `git clone --local` sandbox carrying one deliberate regression, so their real gating shapes are visible without writing a byte into the read-only repo.
- **Corpus:** the ripwire repo itself (dogfood), via `./build/ripwire`
- **Sandbox diff** (the last section only): `.ripwire_quality_acks |  3 +++
 src/infra/sortutil.h  | 68 ++++++++++++++++++++++++++++++++++++++++++++++-----
 2 files changed, 65 insertions(+), 6 deletions(-)` — one preexisting function made deeply nested, one function's arity changed 1 -> 2, one copy-paste duplicate helper, one new 8-parameter public function.

**How to read the blocks:** ripwire's real XML output is minified — often ONE long line. For scanability, long minified lines are displayed re-wrapped with a line break at every tag seam (`><`). Header COMMENT lines (the legends) always appear in full — they are exempt from the per-line cut; any OTHER display line over 300 bytes is cut with a `… [line truncated: N more bytes]` marker, which can hit a long root element or row. `--plan-lanes` emits JSON and is re-wrapped at object seams the same way. Long outputs are cut to their first ~30 display lines with a `… [N more display lines; full output is M bytes]` marker giving the true size. Exit codes are recorded when non-zero; wall time when >1s.

**Not run (and why):** `ripwire <git-url>` (network clone), `--mcp` / `--listen` / `--mcp-token` / `--allow-remote-edits` (persistent servers — `wrap claude` below shows the wiring), `--note-add` / `--quality-baseline` / `--arch --baseline[-update]` / `--index-out` (state writers; the repo is read-only for this capture — `--quality-ack` IS shown, but only inside the throwaway sandbox clone), `--eval-mined` (needs a `minedpair.jsonl` artifact from `bench/mine_traces.py`; none present in the tree), `--refetch` (git-url only), `--force` (wrap-only modifier), `--scan-skills` bare form (would sweep `~/.claude/skills`; the explicit-DIR form is shown instead), `--help` (1118 lines — read it from the binary).


---

# understand a codebase cold

## `./build/ripwire .`

*The default ranked symbol map — start here when landing cold in a repo.*

`````
<!-- ripwire v1 t=fn|method|cls|struct|iface|var|sec|macro(#define;degraded:body-is-replacement-text,edges-cross-expansion) p=path layer=arch-layer(opt) n=name id=canonical(path::scope::name,when-scoped) k=rank c=call amb=ambiguous-calls(read-source) overloads=N-same-name-defs-merged-into-this-row(absent-if-1;shown=counts-them-individually,so-rows+sum(overloads-1)=shown) prov=scip(precise;else name-based) hdr:unresolved=call-name-defined-only-in-a-lang-incompatible-file (edges heuristic) r:est_tokens=hdr-copy(none-if-stable) -->
<!-- r:root=crawl-root-every-p=-is-relative-to(single-root-only;absent=>p=is-the-raw-ingest-path) -->
<!-- pr_iters=pagerank-power-iterations(stop:L1-residual-below-tol,else-ceiling) pr_converged=0-only-when-ceiling-hit-first(absent=converged;no-such-attr=not-pagerank-ordered) -->
<!-- files=1304 symbols=11348 edges=13926 shown=200 est_tokens=9284 ambiguous=5517 unresolved=3202 precise=3 skipped_oversize=15 unindexed="jsonl:25,txt:22,scm:16,tsv:16,lock:6,xml:4" unindexed_exts=17 order=important-first -->
<r root="." est_tokens="9284" pr_iters="32">
<f p="src/infra/svector.h" layer="infra">
<s t="method" n="size" id="./src/infra/svector.h::svector::size" k="0.0165">
</s>
<s t="method" n="buf" id="./src/infra/svector.h::svector::buf" overloads="2" k="0.0084">
</s>
<s t="method" n="push_back" id="./src/infra/svector.h::svector::push_back" overloads="2" amb="2" k="0.0071">
<c n="buf"/>
<c n="buf"/>
<c n="grow"/>
</s>
<s t="method" n="grow" id="./src/infra/svector.h::svector::grow" amb="1" k="0.0049">
<c n="isSpilled"/>
<c n="buf"/>
<c n="buf"/>
<c n="moveRange"/>
<c n="maxSize"/>
</s>
<s t="method" n="empty" id="./src/infra/svector.h::svector::empty" k="0.0029">
</s>
<s t="method" n="reserve" id="./src/infra/svector.h::svector::reserve" k="0.0025">
<c n="grow"/>
</s>
<s t="method" n="end" id="./src/infra/svector.h::svector::end" overloads="2" amb="1" k="0.0023">
<c n="buf"/>
<c n="buf"/>
… [806 more display lines; full output is 23001 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --top-k=5`

*Same map, capped to the 5 highest-ranked symbols.*

`````
<!-- ripwire v1 t=fn|method|cls|struct|iface|var|sec|macro(#define;degraded:body-is-replacement-text,edges-cross-expansion) p=path layer=arch-layer(opt) n=name id=canonical(path::scope::name,when-scoped) k=rank c=call amb=ambiguous-calls(read-source) overloads=N-same-name-defs-merged-into-this-row(absent-if-1;shown=counts-them-individually,so-rows+sum(overloads-1)=shown) prov=scip(precise;else name-based) hdr:unresolved=call-name-defined-only-in-a-lang-incompatible-file (edges heuristic) r:est_tokens=hdr-copy(none-if-stable) -->
<!-- r:root=crawl-root-every-p=-is-relative-to(single-root-only;absent=>p=is-the-raw-ingest-path) -->
<!-- pr_iters=pagerank-power-iterations(stop:L1-residual-below-tol,else-ceiling) pr_converged=0-only-when-ceiling-hit-first(absent=converged;no-such-attr=not-pagerank-ordered) -->
<!-- files=1304 symbols=11348 edges=13926 shown=5 est_tokens=609 ambiguous=5517 unresolved=3202 precise=3 skipped_oversize=15 unindexed="jsonl:25,txt:22,scm:16,tsv:16,lock:6,xml:4" unindexed_exts=17 order=important-first -->
<r root="." est_tokens="609" pr_iters="32">
<f p="src/infra/svector.h" layer="infra">
<s t="method" n="size" id="./src/infra/svector.h::svector::size" k="0.0165">
</s>
<s t="method" n="buf" id="./src/infra/svector.h::svector::buf" overloads="2" k="0.0084">
</s>
</f>
<f p="src/notes.h">
<s t="method" n="empty" id="./src/notes.h::NoteIndex::empty" k="0.0081">
</s>
</f>
<f p="src/scipoverlay.h">
<s t="method" n="empty" id="./src/scipoverlay.h::ScipOverlay::empty" k="0.0079">
</s>
</f>
</r>
`````

## `./build/ripwire . --top-k=0 --expand=rankGraphTeleport`

*NEW since the last capture: --top-k=0 means PAYLOAD-ONLY — no ranked map rides along with the body you asked for.*

`````
<ctx root=".">
<bodies shown="1" total="1" capped="0">
<b t="fn" l="2112" p="src/graph.h" n="rankGraphTeleport" sibs="Graph,langCompatible,namespaceCompatible,kCommonNameMul,kCommonNameDefThreshold,kPrivateNameMul,kSpecificNameMul,kSpecificMinLen,kSpecificMinWords,wordCount,weight,decodeJniName,splitSegments,isTemplateSegment,pathsMatch,methodsCompatibl … [line truncated: 570 more bytes on this line]
<![CDATA[inline RankedGraph rankGraphTeleport( const Graph& g, const std::vector<float>& p, float alpha = 0.85f )
{
    PROFILE_SCOPE_DESCRIBE( "rankGraph: PageRank (power iteration)" );
    const std::vector<float> pw = biasPrior( g, p );
    const std::size_t N = pw.size();
    std::vector<double> teleport( pw.begin(), pw.end() );
    std::vector<double> rankDouble( N, 0.0 );
    PageRankRun         run{};   // an N == 0 graph never enters the kernel: { 0, converged } — see PageRankRun
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
        run = pageRankDouble( g.inEdges, g.wOutDeg, teleport, rankDouble, PageRankConfig{ .alpha = double( alpha ) } );
    }
    std::vector<float> r( N, 0.f );
    std::transform( rankDouble.begin(), rankDouble.end(), r.begin(), []( double value ) { return float( value ); } );
    return { std::move( r ), run.iterationCount, run.hasConverged };
}]]><calls total="9"><c n="biasPrior" l="2075">inline std::vector&lt;float&gt; biasPrior( const Graph&amp; g, const std::vector&lt;float&gt;&amp; p )</c><c n="PROFILE_SCOPE_DESCRIBE" l="1322">#define PROFILE_SCOPE_DESCRIBE( desc )</c><c n="PROFILE_SCOPE_DESCRIBE" l="1336">#define PROFILE_SCOPE_DESCR … [line truncated: 535 more bytes on this line]
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
<!-- ripwire v1 t=fn|method|cls|struct|iface|var|sec|macro(#define;degraded:body-is-replacement-text,edges-cross-expansion) p=path layer=arch-layer(opt) n=name id=canonical(path::scope::name,when-scoped) k=rank c=call amb=ambiguous-calls(read-source) overloads=N-same-name-defs-merged-into-this-row(absent-if-1;shown=counts-them-individually,so-rows+sum(overloads-1)=shown) prov=scip(precise;else name-based) hdr:unresolved=call-name-defined-only-in-a-lang-incompatible-file (edges heuristic) r:est_tokens=hdr-copy(none-if-stable) -->
<!-- r:root=crawl-root-every-p=-is-relative-to(single-root-only;absent=>p=is-the-raw-ingest-path) -->
<!-- max_tokens=asked fit_bytes=honoured: fit_bytes = max_tokens x 2.36 (densest-language B/tok) x 0.90 headroom, a CONSERVATIVE cap, so est_tokens (this corpus's own rate) lands ~10-20% BELOW max_tokens by design; the token-budget gate compares against est_tokens, not fit_bytes; over_ceiling=floor-alone-exceeded-fit_bytes(absent=cap-held) -->
<!-- pr_iters=pagerank-power-iterations(stop:L1-residual-below-tol,else-ceiling) pr_converged=0-only-when-ceiling-hit-first(absent=converged;no-such-attr=not-pagerank-ordered) -->
<!-- files=1304 symbols=11348 edges=13926 shown=15 est_tokens=1247 ambiguous=5517 unresolved=3202 precise=3 skipped_oversize=15 unindexed="jsonl:25,txt:22,scm:16,tsv:16,lock:6,xml:4" unindexed_exts=17 max_tokens=1500 fit_bytes=3186 order=important-first -->
<r root="." est_tokens="1247" pr_iters="32">
<f p="src/infra/svector.h" layer="infra">
<s t="method" n="size" id="./src/infra/svector.h::svector::size" k="0.0165">
</s>
<s t="method" n="buf" id="./src/infra/svector.h::svector::buf" overloads="2" k="0.0084">
</s>
<s t="method" n="push_back" id="./src/infra/svector.h::svector::push_back" overloads="2" amb="2" k="0.0071">
<c n="buf"/>
<c n="buf"/>
<c n="grow"/>
</s>
<s t="method" n="grow" id="./src/infra/svector.h::svector::grow" amb="1" k="0.0049">
<c n="isSpilled"/>
<c n="buf"/>
<c n="buf"/>
<c n="moveRange"/>
<c n="maxSize"/>
</s>
<s t="method" n="empty" id="./src/infra/svector.h::svector::empty" k="0.0029">
</s>
<s t="method" n="reserve" id="./src/infra/svector.h::svector::reserve" k="0.0025">
<c n="grow"/>
</s>
</f>
<f p="src/notes.h">
… [39 more display lines; full output is 3099 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --token-budget=100`

*GATE form: exit 3 if the map's own est_tokens exceeds the budget (over-budget failure shape).*

**exit code: 3**

`````
<r withheld_est_tokens="9284" budget="100" withheld="1"/>
`````

stderr:

`````
ripwire: --token-budget exceeded: withheld_est_tokens=9284 > budget=100
`````

## `./build/ripwire . --for="incremental cache invalidation when a file content hash changes"`

*The task lens: ranked signatures + quality metrics framed for the task.*

`````
<ctx task="incremental cache invalidation when a file content hash changes" route=" [routed: subtoken+body BM25 (--for&apos;s default) — no strong name hit, multi-word conceptual query]" root="." bundle="auto" bodies="5">
<!-- ripwire lens for "incremental cache invalidation when a file content hash changes" [doc mentions: 1 doc discussing 1 top-ranked symbol surfaced]: reusable building blocks + quality facts for what you're about to touch (cx=complexity ccx=cognitive in=reuse-count churn=recent-commits amp=change-amplification clone=1(duplicated) tested=1) — prefer composing/reusing these; watch the high-churn/high-amp/cloned ones; bundle=auto: the top-ranked FULL bodies ride inline after the signatures in a bodies section (bodies=N on this root counts them; bodies=0 reason=budget when none fit the remaining budget whole; the signatures-only flag (no-bodies mode) opts out) — read them here instead of opening the files. The bodies element discloses the house way: total=requested, shown=printed, capped=1 when they differ; each body's calls child lists its callee signatures, total= always, shown=/capped= only when that list is cut -->
<!-- root= is the crawl root; p= below is RELATIVE to it (single-root only; absent => p= is ingest's own path, unchanged). est_tokens="4645" -->
<sigs capped="1">
<f p="src/ingest.cpp">
<d l="1154" n="StatInfo" id="./src/ingest.cpp::StatInfo::StatInfo" cx="0" ccx="0" in="0" churn="93" amp="208">struct StatInfo</d>
<d l="1187" n="PathShape" cx="0" ccx="0" in="0" churn="93" amp="208">enum class PathShape : std::uint8_t</d>
<d l="1211" n="wallClockNs" cx="1" ccx="0" in="1" churn="93" amp="209" tested="1">inline long long wallClockNs() noexcept</d>
<d l="1425" n="kCacheMagic" cx="0" ccx="0" in="0" churn="93" amp="208" pure="1">
<doc>incremental cache (--cache): per-file content hash + raw facts so a re-run re-parses ONLY      c…</doc>constexpr std::uint32_t kCacheMagic = 0x4b505443</d>
<d l="1932" n="contentHash64" cx="2" ccx="1" in="1" churn="93" amp="209" tested="1">inline std::uint64_t contentHash64( std::string_view s ) noexcept</d>
<d l="1947" n="blobChecksum" cx="5" ccx="5" in="2" churn="93" amp="210" tested="1">inline std::uint64_t blobChecksum( std::string_view s ) noexcept</d>
<d l="1968" n="FileFacts" id="./src/ingest.cpp::FileFacts::FileFacts" cx="0" ccx="0" in="0" churn="93" amp="208">struct FileFacts</d>
<d l="2242" n="reAbsolutize" cx="4" ccx="3" in="1" churn="93" amp="209" tested="1">inline std::string reAbsolutize( std::string_view rel, std::string_view root )</d>
<d l="2508" n="saveCache" cx="44" ccx="89" in="1" churn="93" amp="209" tested="1">inline void saveCache( const std::string&amp; path, std::string_view rootDir, const std::vector&lt;std::string&gt;&amp; files, const std::vector&lt;std::uint64_t&gt;&amp; fileHash, const std::vector&lt;long long&gt;&am … [line truncated: 70 more bytes on this line]
<d l="9780" n="docTextViaBridgeCache" id="./src/ingest.cpp::rw::docTextViaBridgeCache" cx="10" ccx="16" in="1" churn="93" amp="209" tested="1">inline std::string docTextViaBridgeCache( const std::string&amp; path, const std::string&amp; ext, bool cacheEnabled, std::uint32_t tmpKey )</d>
<d l="9910" n="ingest" id="./src/ingest.cpp::rw::ingest" cx="244" ccx="722" in="13" churn="93" amp="221" tested="1">IngestResult ingest( const char* rootDir, const std::vector&lt;std::string&gt;&amp; excludeSubstr, std::string_view cacheFile, std::size_t maxFileBytes, bool captureValueUses, std::str … [line truncated: 27 more bytes on this line]
</f>
<f p="src/quality.h">
<d l="718" n="kHeadSnapCacheScheme" id="./src/quality.h::quality::kHeadSnapCacheScheme" cx="0" ccx="0" in="0" churn="60" amp="146" pure="1">
<doc>and every file whose content hash differs is re-parsed — so a stale or foreign blob self-heals…</doc>constexpr std::uint32_t kHeadSnapCacheScheme = 1</d>
<d l="1297" n="kQBodyCacheScheme" id="./src/quality.h::quality::kQBodyCacheScheme" cx="0" ccx="0" in="0" churn="60" amp="146" pure="1">constexpr std::uint32_t kQBodyCacheScheme = 3</d>
<d l="1740" n="computeHeadSnapshot" id="./src/quality.h::quality::computeHeadSnapshot" cx="18" ccx="20" in="4" churn="60" amp="150">inline std::pair&lt;Snapshot, bool&gt; computeHeadSnapshot( const std::string&amp; root, const std::string_view* cacheNever = nullptr, std::size_t maxFileBytes = kDefau … [line truncated: 72 more bytes on this line]
<d l="1920" n="computeWindowRefBodyHashes" id="./src/quality.h::quality::computeWindowRefBodyHashes" cx="9" ccx="8" in="1" churn="60" amp="147">inline std::pair&lt;gtl::btree_map&lt;std::uint64_t, std::uint64_t&gt;, bool&gt; computeWindowRefBodyHashes(…</d>
</f>
<f p="src/mcpindex.h">
<d l="134" n="collectDirMtimes" id="./src/mcpindex.h::mcpdetail::collectDirMtimes" cx="13" ccx="21" in="1" churn="16" amp="29">inline void collectDirMtimes( const std::string&amp; root, HashMap&lt;std::string, long long&gt;&amp; dirMtime…</d>
<d l="359" n="byteHash" id="./src/mcpindex.h::mcpdetail::byteHash" cx="2" ccx="1" in="4" churn="16" amp="32">inline std::uint64_t byteHash( const char* data, std::size_t n ) noexcept</d>
<d l="391" n="stableHandleId" id="./src/mcpindex.h::mcpdetail::stableHandleId" cx="2" ccx="1" in="2" churn="16" amp="30">inline std::string stableHandleId( const std::string&amp; canonId, const std::string&amp; path, const std::string&amp; name )</d>
<d l="405" n="makeHandle" id="./src/mcpindex.h::mcpdetail::makeHandle" cx="1" ccx="0" in="1" churn="16" amp="29">inline std::string makeHandle( const std::string&amp; canonId, const std::string&amp; path, const std::string&amp; name, std::uint64_t contentHash )</d>
… [93 more display lines; full output is 13510 bytes on 61 raw line(s)]
`````

## `./build/ripwire . --for="rankGraphTeleport"`

*Name-shaped query: the router picks name-exact BM25 (header says which/why).*

`````
<ctx task="rankGraphTeleport" route=" [routed: name-exact BM25 — query names a symbol (rankGraphTeleport); anchors: rankGraphTeleport(src/graph.h)]" root="." bundle="auto" bodies="2">
<!-- ripwire lens for "rankGraphTeleport" [doc mentions: 2 docs discussing 1 top-ranked symbol surfaced]: reusable building blocks + quality facts for what you're about to touch (cx=complexity ccx=cognitive in=reuse-count churn=recent-commits amp=change-amplification clone=1(duplicated) tested=1) — prefer composing/reusing these; watch the high-churn/high-amp/cloned ones; bundle=auto: the top-ranked FULL bodies ride inline after the signatures in a bodies section (bodies=N on this root counts them; bodies=0 reason=budget when none fit the remaining budget whole; the signatures-only flag (no-bodies mode) opts out) — read them here instead of opening the files. The bodies element discloses the house way: total=requested, shown=printed, capped=1 when they differ; each body's calls child lists its callee signatures, total= always, shown=/capped= only when that list is cut -->
<!-- root= is the crawl root; p= below is RELATIVE to it (single-root only; absent => p= is ingest's own path, unchanged). est_tokens="4549" -->
<sigs>
<f p="src/graph.h">
<d l="2112" n="rankGraphTeleport" id="./src/graph.h::rw::rankGraphTeleport" cx="5" ccx="8" in="6" churn="29" amp="112">
<doc>PageRank with an explicit teleport / personalization vector p (Σp = 1). The prior is name-quality-biased through biasPrior() so all rank modes share one weighting seam; the transition matrix (edges</doc>inline RankedGraph rankGraphTeleport( const Graph&amp; g, const std::vector&lt;float&gt;&am … [line truncated: 31 more bytes on this line]
</f>
<f p="docs/ARCHITECTURE.md">
<d l="223" n="The convergence disclosure contract" id="./docs/ARCHITECTURE.md::rank — Personalized PageRank::The convergence disclosure contract" cx="0" ccx="0" in="0" churn="7" amp="30">#### The convergence disclosure contract</d>
</f>
<f p="docs/EVALS.md">
<d l="2021" n="Wave-2 adversarial verification (2026-08-19) — six probes against `aa97c9e`" id="./docs/EVALS.md::6. Correctness and quality instruments::Wave-2 adversarial verification (2026-08-19) — six probes against `aa97c9e`" cx="0" ccx="0" in="0" churn="211" amp="389">### Wave-2 adversarial … [line truncated: 63 more bytes on this line]
</f>
<f p=".codex-plugin/plugin.json">
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
… [111 more display lines; full output is 13475 bytes on 81 raw line(s)]
`````

## `./build/ripwire . --for="rankGraphTeleport" --no-route`

*Same query with routing forced OFF (plain subtoken+body BM25) — contrast with the routed run.*

`````
<ctx task="rankGraphTeleport" root="." bundle="auto" bodies="5">
<!-- ripwire lens for "rankGraphTeleport" [doc mentions: 3 docs discussing 2 top-ranked symbols surfaced]: reusable building blocks + quality facts for what you're about to touch (cx=complexity ccx=cognitive in=reuse-count churn=recent-commits amp=change-amplification clone=1(duplicated) tested=1) — prefer composing/reusing these; watch the high-churn/high-amp/cloned ones; bundle=auto: the top-ranked FULL bodies ride inline after the signatures in a bodies section (bodies=N on this root counts them; bodies=0 reason=budget when none fit the remaining budget whole; the signatures-only flag (no-bodies mode) opts out) — read them here instead of opening the files. The bodies element discloses the house way: total=requested, shown=printed, capped=1 when they differ; each body's calls child lists its callee signatures, total= always, shown=/capped= only when that list is cut -->
<!-- root= is the crawl root; p= below is RELATIVE to it (single-root only; absent => p= is ingest's own path, unchanged). est_tokens="4821" -->
<sigs capped="1">
<f p="src/graph.h">
<d l="34" n="Graph" id="./src/graph.h::Graph::Graph" cx="0" ccx="0" in="0" churn="29" amp="106">struct Graph</d>
<d l="2075" n="biasPrior" id="./src/graph.h::rw::biasPrior" cx="5" ccx="4" in="1" churn="29" amp="107">inline std::vector&lt;float&gt; biasPrior( const Graph&amp; g, const std::vector&lt;float&gt;&amp; p )</d>
<d l="2103" n="RankedGraph" id="./src/graph.h::RankedGraph::RankedGraph" cx="0" ccx="0" in="0" churn="29" amp="106">
<doc>What a rank call hands back: the vector, and the power iteration&apos;s own account of itself. Struct…</doc>struct RankedGraph</d>
<d l="2112" n="rankGraphTeleport" id="./src/graph.h::rw::rankGraphTeleport" cx="5" ccx="8" in="6" churn="29" amp="112">
<doc>PageRank with an explicit teleport / personalization vector p (Σp = 1). The prior is name-quali…</doc>inline RankedGraph rankGraphTeleport( const Graph&amp; g, const std::vector&lt;float&gt;&amp; p, float alpha = 0.85f )</d>
<d l="2146" n="takeRank" id="./src/graph.h::rw::takeRank" cx="1" ccx="0" in="1" churn="29" amp="107">inline std::vector&lt;float&gt; takeRank( RankedGraph ranked, RankDisclosure&amp; disclosureOut )</d>
<d l="2153" n="rankGraph" id="./src/graph.h::rw::rankGraph" cx="2" ccx="1" in="9" churn="29" amp="115">
<doc>uniform-teleport PageRank (the default</doc>inline RankedGraph rankGraph( const Graph&amp; g, float alpha = 0.85f )</d>
<d l="2489" n="anchoredLexicalRank" id="./src/graph.h::rw::anchoredLexicalRank" cx="10" ccx="10" in="4" churn="29" amp="110">inline std::vector&lt;float&gt; anchoredLexicalRank( const Graph&amp; g, const std::vector&lt;float&gt;&amp; lex )</d>
<d l="3120" n="diffTeleport" id="./src/graph.h::rw::diffTeleport" cx="8" ccx="9" in="3" churn="29" amp="109">inline std::vector&lt;float&gt; diffTeleport( const IngestResult&amp; ing, const std::vector&lt;char&gt;&amp; fileCh…</d>
</f>
<f p="src/main.cpp">
<d l="6286" n="runGraphQuery" cx="11" ccx="19" in="1" churn="141" amp="242">std::optional&lt;int&gt; runGraphQuery( const MainDispatch&amp; d )</d>
<d l="12489" n="ChurnRanking" id="./src/main.cpp::ChurnRanking::ChurnRanking" cx="0" ccx="0" in="0" churn="141" amp="241">struct ChurnRanking</d>
<d l="12504" n="churnRankedGraph" cx="13" ccx="18" in="1" churn="141" amp="242">inline ChurnRanking churnRankedGraph( const MainDispatch&amp; d )</d>
<d l="13503" n="ReportVerbSlot" id="./src/main.cpp::ReportVerbSlot::ReportVerbSlot" cx="0" ccx="0" in="0" churn="141" amp="241">struct ReportVerbSlot</d>
</f>
<f p="src/gitmine.h">
<d l="1407" n="churnPriorFromFreq" id="./src/gitmine.h::rw::churnPriorFromFreq" cx="8" ccx="8" in="2" churn="11" amp="23">inline std::vector&lt;float&gt; churnPriorFromFreq( const IngestResult&amp; ing, const std::vector&lt;std::uint32_t&gt;&amp; freq, bool anyHistory )</d>
<d l="1438" n="churnTeleport" id="./src/gitmine.h::rw::churnTeleport" cx="4" ccx="4" in="1" churn="11" amp="22">inline std::vector&lt;float&gt; churnTeleport( const std::string&amp; root, const IngestResult&amp; ing, const char* since = &quot;18 months ago&quot;, const SinceScope* scope = nullptr, b … [line truncated: 40 more bytes on this line]
<d l="1463" n="churnTeleportWorkspace" id="./src/gitmine.h::rw::churnTeleportWorkspace" cx="6" ccx="9" in="1" churn="11" amp="22">inline std::vector&lt;float&gt; churnTeleportWorkspace( const std::vector&lt;std::string&gt;&amp; rootDirs, const IngestResult&amp; ing, const char* since = &quot;18 mont … [line truncated: 27 more bytes on this line]
<d l="1637" n="churnDecayTeleport" id="./src/gitmine.h::rw::churnDecayTeleport" cx="4" ccx="3" in="1" churn="11" amp="22">inline std::vector&lt;float&gt; churnDecayTeleport( const std::string&amp; root, const IngestResult&amp; ing, const SinceScope* scope = nullptr, bool* outHasChurnEvidence = n…< … [line truncated: 3 more bytes on this line]
<d l="1654" n="churnDecayTeleportWorkspace" id="./src/gitmine.h::rw::churnDecayTeleportWorkspace" cx="5" ccx="6" in="1" churn="11" amp="22">inline std::vector&lt;float&gt; churnDecayTeleportWorkspace( const std::vector&lt;std::string&gt;&amp; rootDirs, const IngestResult&amp; ing, bool* outHasChurnE … [line truncated: 23 more bytes on this line]
</f>
… [126 more display lines; full output is 14190 bytes on 88 raw line(s)]
`````

## `./build/ripwire . --for="rankGraphTeleport" --signatures-only`

*T3 opt-out: the signatures-only lens (no auto bodies, no bundle="auto" attribute) — contrast with the terminal default above.*

`````
<ctx task="rankGraphTeleport" route=" [routed: name-exact BM25 — query names a symbol (rankGraphTeleport); anchors: rankGraphTeleport(src/graph.h)]" root=".">
<!-- ripwire lens for "rankGraphTeleport" [doc mentions: 2 docs discussing 1 top-ranked symbol surfaced]: reusable building blocks + quality facts for what you're about to touch (cx=complexity ccx=cognitive in=reuse-count churn=recent-commits amp=change-amplification clone=1(duplicated) tested=1) — prefer composing/reusing these; watch the high-churn/high-amp/cloned ones -->
<!-- root= is the crawl root; p= below is RELATIVE to it (single-root only; absent => p= is ingest's own path, unchanged). est_tokens="2717" -->
<sigs>
<f p="src/graph.h">
<d l="2112" n="rankGraphTeleport" id="./src/graph.h::rw::rankGraphTeleport" cx="5" ccx="8" in="6" churn="29" amp="112">
<doc>PageRank with an explicit teleport / personalization vector p (Σp = 1). The prior is name-quality-biased through biasPrior() so all rank modes share one weighting seam; the transition matrix (edges</doc>inline RankedGraph rankGraphTeleport( const Graph&amp; g, const std::vector&lt;float&gt;&am … [line truncated: 31 more bytes on this line]
</f>
<f p="docs/ARCHITECTURE.md">
<d l="223" n="The convergence disclosure contract" id="./docs/ARCHITECTURE.md::rank — Personalized PageRank::The convergence disclosure contract" cx="0" ccx="0" in="0" churn="7" amp="30">#### The convergence disclosure contract</d>
</f>
<f p="docs/EVALS.md">
<d l="2021" n="Wave-2 adversarial verification (2026-08-19) — six probes against `aa97c9e`" id="./docs/EVALS.md::6. Correctness and quality instruments::Wave-2 adversarial verification (2026-08-19) — six probes against `aa97c9e`" cx="0" ccx="0" in="0" churn="211" amp="389">### Wave-2 adversarial … [line truncated: 63 more bytes on this line]
</f>
<f p=".codex-plugin/plugin.json">
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
… [29 more display lines; full output is 6793 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --for="tree-sitter parse of a source file" --adaptive`

*Cut the result at the relevance cliff (Adaptive-k).*

`````
<ctx task="tree-sitter parse of a source file" route=" [routed: subtoken+body BM25 (--for&apos;s default) — no strong name hit, multi-word conceptual query]" root="." bundle="auto" bodies="4">
<!-- ripwire lens for "tree-sitter parse of a source file" [adaptive: kept 40 of 40 - no relevance cliff (broad query saturates the score); capped at the ceiling]: reusable building blocks + quality facts for what you're about to touch (cx=complexity ccx=cognitive in=reuse-count churn=recent-commits amp=change-amplification clone=1(duplicated) tested=1) — prefer composing/reusing these; watch the high-churn/high-amp/cloned ones; bundle=auto: the top-ranked FULL bodies ride inline after the signatures in a bodies section (bodies=N on this root counts them; bodies=0 reason=budget when none fit the remaining budget whole; the signatures-only flag (no-bodies mode) opts out) — read them here instead of opening the files. The bodies element discloses the house way: total=requested, shown=printed, capped=1 when they differ; each body's calls child lists its callee signatures, total= always, shown=/capped= only when that list is cut -->
<!-- root= is the crawl root; p= below is RELATIVE to it (single-root only; absent => p= is ingest's own path, unchanged). est_tokens="4942" -->
<sigs capped="1">
<f p="src/ingest.h">
<d l="32" n="kDefaultMaxFileBytes" id="./src/ingest.h::rw::kDefaultMaxFileBytes" cx="0" ccx="0" in="0" churn="19" amp="48" pure="1">
<doc>The crawl&apos;s per-file byte ceiling. A text file larger than this is skipped: at this size it is o…</doc>constexpr std::size_t kDefaultMaxFileBytes = 4u * 1024u * 1024u</d>
<d l="91" n="kMaxYamlNestDepth" id="./src/ingest.h::rw::kMaxYamlNestDepth" cx="0" ccx="0" in="0" churn="19" amp="48" pure="1">constexpr std::uint32_t kMaxYamlNestDepth = 64u</d>
<d l="265" n="AstQuerySpec" id="./src/ingest.h::AstQuerySpec::AstQuerySpec" cx="0" ccx="0" in="0" churn="19" amp="48">struct AstQuerySpec</d>
<d l="299" n="AstWalk" id="./src/ingest.h::rw::AstWalk" cx="0" ccx="0" in="0" churn="19" amp="48">enum class AstWalk : std::uint8_t</d>
<d l="421" n="SpanTier" id="./src/ingest.h::rw::SpanTier" cx="0" ccx="0" in="1" churn="19" amp="49">enum class SpanTier : std::uint8_t</d>
</f>
<f p="src/ingest.cpp">
<d l="134" n="tree_sitter_cpp" cx="1" ccx="0" in="1" churn="93" amp="209">const TSLanguage* tree_sitter_cpp( void )</d>
<d l="135" n="tree_sitter_python" cx="1" ccx="0" in="0" churn="93" amp="208">const TSLanguage* tree_sitter_python( void )</d>
<d l="136" n="tree_sitter_go" cx="1" ccx="0" in="0" churn="93" amp="208">const TSLanguage* tree_sitter_go( void )</d>
<d l="137" n="tree_sitter_rust" cx="1" ccx="0" in="0" churn="93" amp="208">const TSLanguage* tree_sitter_rust( void )</d>
<d l="138" n="tree_sitter_typescript" cx="1" ccx="0" in="0" churn="93" amp="208">const TSLanguage* tree_sitter_typescript( void )</d>
<d l="139" n="tree_sitter_tsx" cx="1" ccx="0" in="0" churn="93" amp="208">const TSLanguage* tree_sitter_tsx( void )</d>
<d l="140" n="tree_sitter_swift" cx="1" ccx="0" in="0" churn="93" amp="208">const TSLanguage* tree_sitter_swift( void )</d>
<d l="141" n="tree_sitter_objc" cx="1" ccx="0" in="0" churn="93" amp="208">const TSLanguage* tree_sitter_objc( void )</d>
<d l="142" n="tree_sitter_javascript" cx="1" ccx="0" in="0" churn="93" amp="208">const TSLanguage* tree_sitter_javascript( void )</d>
<d l="143" n="tree_sitter_bash" cx="1" ccx="0" in="0" churn="93" amp="208">const TSLanguage* tree_sitter_bash( void )</d>
<d l="144" n="tree_sitter_java" cx="1" ccx="0" in="0" churn="93" amp="208">const TSLanguage* tree_sitter_java( void )</d>
<d l="145" n="tree_sitter_ruby" cx="1" ccx="0" in="0" churn="93" amp="208">const TSLanguage* tree_sitter_ruby( void )</d>
<d l="146" n="tree_sitter_json" cx="1" ccx="0" in="0" churn="93" amp="208">const TSLanguage* tree_sitter_json( void )</d>
<d l="147" n="tree_sitter_toml" cx="1" ccx="0" in="0" churn="93" amp="208">const TSLanguage* tree_sitter_toml( void )</d>
<d l="148" n="tree_sitter_yaml" cx="1" ccx="0" in="0" churn="93" amp="208">const TSLanguage* tree_sitter_yaml( void )</d>
<d l="150" n="tree_sitter_c" cx="1" ccx="0" in="1" churn="93" amp="209">const TSLanguage* tree_sitter_c( void )</d>
<d l="199" n="kLangTable" cx="0" ccx="0" in="0" churn="93" amp="208" pure="1">constexpr std::array&lt;LangEntry, 37&gt; kLangTable =</d>
… [148 more display lines; full output is 14608 bytes on 103 raw line(s)]
`````

## `./build/ripwire . --for="why does src/lexical.h chooseForRanker pick name-exact BM25"`

*Mention anchoring (default-on): a path and a Symbol literally named in the task get lifted; the header says what anchored.*

`````
<ctx task="why does src/lexical.h chooseForRanker pick name-exact BM25" route=" [routed: subtoken+body BM25 (--for&apos;s default) — no strong name hit, multi-word conceptual query]" root="." bundle="auto" bodies="1">
<!-- ripwire lens for "why does src/lexical.h chooseForRanker pick name-exact BM25" [mention anchor: 1 file + 3 symbols named in the task lifted near the top] [doc mentions: 2 docs discussing 1 top-ranked symbol surfaced]: reusable building blocks + quality facts for what you're about to touch (cx=complexity ccx=cognitive in=reuse-count churn=recent-commits amp=change-amplification clone=1(duplicated) tested=1) — prefer composing/reusing these; watch the high-churn/high-amp/cloned ones; bundle=auto: the top-ranked FULL bodies ride inline after the signatures in a bodies section (bodies=N on this root counts them; bodies=0 reason=budget when none fit the remaining budget whole; the signatures-only flag (no-bodies mode) opts out) — read them here instead of opening the files. The bodies element discloses the house way: total=requested, shown=printed, capped=1 when they differ; each body's calls child lists its callee signatures, total= always, shown=/capped= only when that list is cut -->
<!-- root= is the crawl root; p= below is RELATIVE to it (single-root only; absent => p= is ingest's own path, unchanged). est_tokens="4802" -->
<sigs capped="1">
<f p="src/eval.h">
<d l="155" n="printEvalRankerNote" id="./src/eval.h::rw::printEvalRankerNote" cx="1" ccx="0" in="1" churn="9" amp="24">
<doc>P11.12: the interpretive footer for --eval&apos;s ranker table, pulled into its own function so the 9…</doc>inline void printEvalRankerNote()</d>
<d l="168" n="runEval" id="./src/eval.h::rw::runEval" cx="44" ccx="66" in="1" churn="9" amp="24">inline int runEval( const std::string&amp; root, const IngestResult&amp; ing, const Graph&amp; g, const std::vector&lt;char&gt;&amp; currentDiff )</d>
<d l="252" n="fileDir" id="./src/eval.h::rw::fileDir" cx="1" ccx="0" in="0" churn="9" amp="23">std::vector&lt;std::string&gt; fileDir( F )</d>
<d l="498" n="runEvalRetrieval" id="./src/eval.h::rw::runEvalRetrieval" cx="15" ccx="25" in="1" churn="9" amp="24">inline int runEvalRetrieval( const IngestResult&amp; ing, const Graph&amp; g )</d>
<d l="901" n="runEvalMined" id="./src/eval.h::rw::runEvalMined" cx="25" ccx="38" in="1" churn="9" amp="24">inline int runEvalMined( const std::string&amp; root, const IngestResult&amp; ing, const Graph&amp; g, const std::string&amp; path )</d>
</f>
<f p="src/lexical.h">
<d l="86" n="kWeakLexicalScoreThreshold" id="./src/lexical.h::rw::kWeakLexicalScoreThreshold" cx="0" ccx="0" in="0" churn="19" amp="35" pure="1">
<doc>calling agent knows to reformulate rather than trust the ranking. Calibrated empirically (2026-0…</doc>inline constexpr float kWeakLexicalScoreThreshold = 1.0f</d>
<d l="905" n="lexicalScoresNameExactTiered" id="./src/lexical.h::rw::lexicalScoresNameExactTiered" cx="35" ccx="61" in="5" churn="19" amp="40">inline std::vector&lt;float&gt; lexicalScoresNameExactTiered( const IngestResult&amp; ing, std::string_view query, const std::vector&lt;float&gt;* symbolScor … [line truncated: 10 more bytes on this line]
<d l="1046" n="lexicalScoresNameExact" id="./src/lexical.h::rw::lexicalScoresNameExact" cx="1" ccx="0" in="3" churn="19" amp="38">inline std::vector&lt;float&gt; lexicalScoresNameExact( const IngestResult&amp; ing, std::string_view query )</d>
<d l="1319" n="kMaxAnchorDefs" id="./src/lexical.h::rw::kMaxAnchorDefs" cx="0" ccx="0" in="0" churn="19" amp="35" pure="1">inline constexpr std::uint32_t kMaxAnchorDefs = 3</d>
<d l="1360" n="declinedRouteReason" id="./src/lexical.h::rw::declinedRouteReason" cx="1" ccx="0" in="1" churn="19" amp="36">
<doc>Truth in the header when name-exact is declined: say WHY — the failing anchor and its measured…</doc>inline std::string declinedRouteReason( const ImplausibleAnchor&amp; imp )</d>
<d l="1384" n="chooseForRanker" id="./src/lexical.h::rw::chooseForRanker" cx="26" ccx="34" in="7" churn="19" amp="42">inline RouteChoice chooseForRanker( const IngestResult&amp; ing, std::string_view query )</d>
</f>
<f p="src/packtask.h">
<d l="41" n="LensRanking" id="./src/packtask.h::LensRanking::LensRanking" cx="0" ccx="0" in="0" churn="13" amp="32">struct LensRanking</d>
</f>
<f p="src/skilleval.h">
<d l="627" n="binomialChoose" id="./src/skilleval.h::skilleval::binomialChoose" cx="4" ccx="3" in="1" churn="9" amp="25">inline double binomialChoose( std::size_t n, std::size_t k )</d>
<d l="649" n="runEvalSkills" id="./src/skilleval.h::rw::runEvalSkills" cx="56" ccx="97" in="1" churn="9" amp="25">inline int runEvalSkills( const std::string&amp; root, const IngestResult&amp; ing, const Graph&amp; g, const std::string&amp; labelsPath )</d>
</f>
<f p="src/naminglens.h">
… [145 more display lines; full output is 14128 bytes on 110 raw line(s)]
`````

## `./build/ripwire . --for="why does src/lexical.h chooseForRanker pick name-exact BM25" --no-mention-boost`

*Same task with the anchor disabled — the contrast the flag exists for.*

`````
<ctx task="why does src/lexical.h chooseForRanker pick name-exact BM25" route=" [routed: subtoken+body BM25 (--for&apos;s default) — no strong name hit, multi-word conceptual query]" root="." bundle="auto" bodies="1">
<!-- ripwire lens for "why does src/lexical.h chooseForRanker pick name-exact BM25" [doc mentions: 2 docs discussing 1 top-ranked symbol surfaced]: reusable building blocks + quality facts for what you're about to touch (cx=complexity ccx=cognitive in=reuse-count churn=recent-commits amp=change-amplification clone=1(duplicated) tested=1) — prefer composing/reusing these; watch the high-churn/high-amp/cloned ones; bundle=auto: the top-ranked FULL bodies ride inline after the signatures in a bodies section (bodies=N on this root counts them; bodies=0 reason=budget when none fit the remaining budget whole; the signatures-only flag (no-bodies mode) opts out) — read them here instead of opening the files. The bodies element discloses the house way: total=requested, shown=printed, capped=1 when they differ; each body's calls child lists its callee signatures, total= always, shown=/capped= only when that list is cut -->
<!-- root= is the crawl root; p= below is RELATIVE to it (single-root only; absent => p= is ingest's own path, unchanged). est_tokens="4772" -->
<sigs capped="1">
<f p="src/eval.h">
<d l="155" n="printEvalRankerNote" id="./src/eval.h::rw::printEvalRankerNote" cx="1" ccx="0" in="1" churn="9" amp="24">
<doc>P11.12: the interpretive footer for --eval&apos;s ranker table, pulled into its own function so the 9…</doc>inline void printEvalRankerNote()</d>
<d l="168" n="runEval" id="./src/eval.h::rw::runEval" cx="44" ccx="66" in="1" churn="9" amp="24">inline int runEval( const std::string&amp; root, const IngestResult&amp; ing, const Graph&amp; g, const std::vector&lt;char&gt;&amp; currentDiff )</d>
<d l="252" n="fileDir" id="./src/eval.h::rw::fileDir" cx="1" ccx="0" in="0" churn="9" amp="23">std::vector&lt;std::string&gt; fileDir( F )</d>
<d l="498" n="runEvalRetrieval" id="./src/eval.h::rw::runEvalRetrieval" cx="15" ccx="25" in="1" churn="9" amp="24">inline int runEvalRetrieval( const IngestResult&amp; ing, const Graph&amp; g )</d>
<d l="901" n="runEvalMined" id="./src/eval.h::rw::runEvalMined" cx="25" ccx="38" in="1" churn="9" amp="24">inline int runEvalMined( const std::string&amp; root, const IngestResult&amp; ing, const Graph&amp; g, const std::string&amp; path )</d>
</f>
<f p="src/packtask.h">
<d l="41" n="LensRanking" id="./src/packtask.h::LensRanking::LensRanking" cx="0" ccx="0" in="0" churn="13" amp="32">
<doc>per-symbol lens rank + the routing/mention/co-change header note fragments — populated identic…</doc>struct LensRanking</d>
</f>
<f p="src/lexical.h">
<d l="86" n="kWeakLexicalScoreThreshold" id="./src/lexical.h::rw::kWeakLexicalScoreThreshold" cx="0" ccx="0" in="0" churn="19" amp="35" pure="1">
<doc>calling agent knows to reformulate rather than trust the ranking. Calibrated empirically (2026-0…</doc>inline constexpr float kWeakLexicalScoreThreshold = 1.0f</d>
<d l="905" n="lexicalScoresNameExactTiered" id="./src/lexical.h::rw::lexicalScoresNameExactTiered" cx="35" ccx="61" in="5" churn="19" amp="40">inline std::vector&lt;float&gt; lexicalScoresNameExactTiered( const IngestResult&amp; ing, std::string_view query, const std::vector&lt;float&gt;* symbolScor … [line truncated: 10 more bytes on this line]
<d l="1046" n="lexicalScoresNameExact" id="./src/lexical.h::rw::lexicalScoresNameExact" cx="1" ccx="0" in="3" churn="19" amp="38">inline std::vector&lt;float&gt; lexicalScoresNameExact( const IngestResult&amp; ing, std::string_view query )</d>
<d l="1319" n="kMaxAnchorDefs" id="./src/lexical.h::rw::kMaxAnchorDefs" cx="0" ccx="0" in="0" churn="19" amp="35" pure="1">inline constexpr std::uint32_t kMaxAnchorDefs = 3</d>
<d l="1360" n="declinedRouteReason" id="./src/lexical.h::rw::declinedRouteReason" cx="1" ccx="0" in="1" churn="19" amp="36">inline std::string declinedRouteReason( const ImplausibleAnchor&amp; imp )</d>
<d l="1384" n="chooseForRanker" id="./src/lexical.h::rw::chooseForRanker" cx="26" ccx="34" in="7" churn="19" amp="42">inline RouteChoice chooseForRanker( const IngestResult&amp; ing, std::string_view query )</d>
</f>
<f p="src/skilleval.h">
<d l="627" n="binomialChoose" id="./src/skilleval.h::skilleval::binomialChoose" cx="4" ccx="3" in="1" churn="9" amp="25">inline double binomialChoose( std::size_t n, std::size_t k )</d>
<d l="649" n="runEvalSkills" id="./src/skilleval.h::rw::runEvalSkills" cx="56" ccx="97" in="1" churn="9" amp="25">inline int runEvalSkills( const std::string&amp; root, const IngestResult&amp; ing, const Graph&amp; g, const std::string&amp; labelsPath )</d>
</f>
<f p="src/naminglens.h">
… [145 more display lines; full output is 14053 bytes on 110 raw line(s)]
`````

## `./build/ripwire . --lego=Vehicle`

*Interface -> implementors view: method contract + every existing impl.*

`````
<ctx root="."><lego><iface n="Vehicle" p="test/legofix/vehicle.rs" methods="0" caveat="not-extracted-for-lang" implementors="2"><impl n="Car" p="test/legofix/vehicle.rs"/><impl n="Bike" p="test/legofix/vehicle.rs"/></iface></lego></ctx>
`````

## `./build/ripwire . --exemplar="format byte sizes for humans"`

*The repo's best-in-class instance to imitate before writing new code (picked by ROLE).*

`````
<!-- ripwire exemplar for "format byte sizes for humans" (task -> kind=fn, low-confidence: weak match, fell back to fn): the repo's best-in-class fn to imitate — chosen by ROLE, NEVER by text similarity to your task: candidates are first filtered to cognitive complexity at or under the ccx ceiling (4x the complexity bar), then ordered non-fixture path before test-fixture path, tested before untested, higher fan-in, lower complexity, fewer lines, lowest id. low_confidence=1 marks a weak task-to-kind match that fell back to fn; over_ccx_bar=1 marks a corpus where nothing was under the ceiling, so the pick is the least bad rather than a clean one; candidates= counts the ELIGIBLE instances of the kind (post-ceiling), not every instance. On the root, the three attributes that ARE that ordering's evidence: in=reuse-count (callers), ccx=cognitive complexity, tested=1 when a test reaches it (OMITTED, never 0, when none does). The body follows in a bodies section, its callee signatures in a calls child; both disclose truncation the house way: total= is how many qualified, shown= how many are printed, capped=1 when the two differ (calls omits shown= and capped= when its list is complete). Copy its shape, not its text. -->
<exemplar kind="fn" candidates="6115" n="min" p="src/infra/fastmath.h:51" in="110" ccx="1" root="." tested="1" low_confidence="1">
<bodies shown="1" total="1" capped="0">
<b t="fn" l="51" p="src/infra/fastmath.h" n="min">
<![CDATA[[[nodiscard]] ALWAYS_INLINE constexpr T min( T a, T b ) noexcept { return b < a ? b : a; }]]>
</b>
</bodies>
</exemplar>
`````

## `./build/ripwire . --help-task="calls(runDefaultMap, rankGraphTeleport)"`

*Deterministic enhanced help: a closed claim in the task is a structured shape, so the router recommends the ONE command that answers it (--verify) with the evidence behind the pick. Advice only — nothing executes.*

`````
<task-route status="recommend" confidence="high" score="100" margin="100">
<facts git="1" dirty="0" trace="0" resolved_symbols="2"/>
<choice intent="verify-claim" skill="ripwire-navigate" reason="closed claim grammar" score="100">
<run>ripwire &apos;.&apos; --verify=&apos;calls(runDefaultMap, rankGraphTeleport)&apos;</run>
</choice>
</task-route>
`````

## `./build/ripwire . --help-task="write a cheerful release announcement"`

*The honest half of the contract: a task with no ripwire-shaped evidence ABSTAINS with zero commands rather than guessing.*

`````
<task-route status="abstain" confidence="none" score="0" margin="0"><facts git="1" dirty="0" trace="0" resolved_symbols="0"/></task-route>
`````

## `./build/ripwire . --recall="quality delta gating exit codes"`

*Most relevant DOCS' full bodies (markdown only) — recall what is already written down.*

`````
ripwire recall — "quality delta gating exit codes" — 71 relevant of 137 document files, best-first — total=71 shown=8 capped=1 generated_demoted=1 est_tokens=72115

━━ ./skills/ripwire-quality-bar/SKILL.md  (relevance 6.616) ━━  [sections: 8 of 10, section-granular; whole doc 28422 B; lines="54-137,138-223,224-252,253-273,274-305,306-315,316-326,327-332"]
## Before you converge: the wide-angle read — `--quality-panel`

`ripwire <dir> --quality-panel[=strict|default|lenient]` is THE SINGLE COMMAND for "does what I just
touched still look rotten" — one ranked report over **six** evidence families (the four `--ensemble`
joins — `structural`, `lexical`, `confusion`, `historical` — plus `colocation` and `state`; the full
per-family breakdown lives in **ripwire-fresh-eyes**). Point it at the file or symbol you just edited for
a multi-angle second opinion the single `--quality-delta` number can't give you on its own.

**Read it correctly: it is a lens, never a gate.** `--help` says so in the flag's own text and the
contract is enforced in code — `--quality-panel` exits 0 unconditionally, on every preset, on every repo.
It does not compare against a baseline and it cannot fail a commit. The gate for "did MY change make this
WORSE" is Step 3 below (`--quality-delta`) — that is the only pass in this skill (or in ripwire) with an
exit code that means something. Run `--quality-panel` for the wide-angle read, converge with
`--quality-delta`, never the other way round.

Pick the preset by what "rotten" needs to mean right now: `lenient` (all six families, 1 must agree) is a
reading order, roughly a third of any tree; `default` (all six, 2 must agree) is a review list; `strict`
(only the four families measured stable enough to stand behind repeatedly — `historical` and `colocation`
are fixed-size worst-40 cuts over a ranking whose population moves, so both re-shuffle release to release
on code that never changed) is the rung closest to something CI-shaped, but it is still a lens — nothing
here plugs into an exit code the way `--quality-delta` does.

### Read the structural row as a PROFILE — `nest=` alone is a max, and misleads solo

`nest=` reports the single deepest line in a function. One line at depth 9 and a thousand lines at depth 9
report the same number, so `nest=9` cannot tell a **tangled** body from a long **blocked-sequential** one
whose max was set by one inner loop nobody has to hold in their head. Acting on `nest=` alone is how an
… [2293 more lines, 184573 bytes total]
`````

## `./build/ripwire . --tree`

*File-by-file orientation map (top symbols per file).*

`````
<!-- ripwire tree: each file + its top symbols by rank, files ordered by their best symbol's rank (path breaks ties) — a session-start orientation map. files= is the indexed corpus; rows list files WITH symbols; files_unlisted= holds the symbol-less remainder — files equals files_unlisted plus the LISTABLE file set, which is what the rows below enumerate before any paging window is applied; under explicit paging (limit=/offset=) that listable count is emitted as total= and shown= says how many of it these rows are. pr_iters=pagerank-power-iterations(stop:L1-residual-below-tol,else-ceiling) pr_converged=0-only-when-ceiling-hit-first(absent=converged;no-such-attr=not-pagerank-ordered) -->
<!-- root= on this element is the crawl root every p= below is RELATIVE to (single-root runs only; absent => p= is the path ingest itself used, unchanged). -->
<tree files="1304" files_unlisted="67" pr_iters="32" root=".">
<file p="src/infra/svector.h" symbols="68">
<s t="method" n="size"/>
<s t="method" n="buf"/>
<s t="method" n="buf"/>
</file>
<file p="src/notes.h" symbols="25">
<s t="method" n="empty"/>
<s t="method" n="find"/>
<s t="fn" n="sortNotes"/>
</file>
<file p="src/scipoverlay.h" symbols="6">
<s t="method" n="empty"/>
<s t="method" n="targetsOf"/>
<s t="method" n="isPrecise"/>
</file>
<file p="src/ingest.cpp" symbols="407">
<s t="method" n="find"/>
<s t="fn" n="nodeTextOf"/>
<s t="fn" n="finalSegment"/>
</file>
<file p="src/graph.h" symbols="113">
<s t="method" n="find"/>
<s t="fn" n="stripLineLocator"/>
<s t="fn" n="resolveAllByName"/>
</file>
<file p="src/infra/fastmath.h" symbols="5">
<s t="fn" n="max"/>
… [5597 more display lines; full output is 158374 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --html=<scratch>/aux/map2.html`

*Self-contained HTML force-directed call graph.*

`````
(empty)
`````

Artifact written:

`````
   59617 <scratch>/aux/map2.html
`````

## `./build/ripwire . --order=stable --top-k=5`

*Stable (path/id) emit order — provider KV-cache hits across re-runs.*

`````
<!-- ripwire v1 t=fn|method|cls|struct|iface|var|sec|macro(#define;degraded:body-is-replacement-text,edges-cross-expansion) p=path layer=arch-layer(opt) n=name id=canonical(path::scope::name,when-scoped) k=rank c=call amb=ambiguous-calls(read-source) overloads=N-same-name-defs-merged-into-this-row(absent-if-1;shown=counts-them-individually,so-rows+sum(overloads-1)=shown) prov=scip(precise;else name-based) hdr:unresolved=call-name-defined-only-in-a-lang-incompatible-file (edges heuristic) r:est_tokens=hdr-copy(none-if-stable) -->
<!-- r:root=crawl-root-every-p=-is-relative-to(single-root-only;absent=>p=is-the-raw-ingest-path) -->
<!-- pr_iters=pagerank-power-iterations(stop:L1-residual-below-tol,else-ceiling) pr_converged=0-only-when-ceiling-hit-first(absent=converged;no-such-attr=not-pagerank-ordered) -->
<r root="." pr_iters="32">
<f p="src/infra/svector.h" layer="infra">
<s t="method" n="buf" id="./src/infra/svector.h::svector::buf" overloads="2">
</s>
<s t="method" n="size" id="./src/infra/svector.h::svector::size">
</s>
</f>
<f p="src/notes.h">
<s t="method" n="empty" id="./src/notes.h::NoteIndex::empty">
</s>
</f>
<f p="src/scipoverlay.h">
<s t="method" n="empty" id="./src/scipoverlay.h::ScipOverlay::empty">
</s>
</f>
</r>
<!-- files=1304 symbols=11348 edges=13926 shown=5 est_tokens=581 ambiguous=5517 unresolved=3202 precise=3 skipped_oversize=15 unindexed="jsonl:25,txt:22,scm:16,tsv:16,lock:6,xml:4" unindexed_exts=17 order=stable -->
`````


---

# navigate / answer a question

## `./build/ripwire . --around=rankGraphTeleport`

*Ego graph around one symbol.*

`````
<!-- ripwire v1 t=fn|method|cls|struct|iface|var|sec|macro(#define;degraded:body-is-replacement-text,edges-cross-expansion) p=path layer=arch-layer(opt) n=name id=canonical(path::scope::name,when-scoped) k=rank c=call amb=ambiguous-calls(read-source) overloads=N-same-name-defs-merged-into-this-row(absent-if-1;shown=counts-them-individually,so-rows+sum(overloads-1)=shown) prov=scip(precise;else name-based) hdr:unresolved=call-name-defined-only-in-a-lang-incompatible-file (edges heuristic) r:est_tokens=hdr-copy(none-if-stable) -->
<!-- r:root=crawl-root-every-p=-is-relative-to(single-root-only;absent=>p=is-the-raw-ingest-path) -->
<!-- files=1304 symbols=11348 edges=13926 shown=211 est_tokens=26051 ambiguous=5517 unresolved=3202 precise=3 skipped_oversize=15 unindexed="jsonl:25,txt:22,scm:16,tsv:16,lock:6,xml:4" unindexed_exts=17 order=important-first -->
<r root="." est_tokens="26051">
<f p="src/graph.h">
<s t="fn" n="rankGraphTeleport" id="./src/graph.h::rw::rankGraphTeleport" amb="6" k="1.0000">
<c n="biasPrior"/>
<c n="PROFILE_SCOPE_DESCRIBE"/>
<c n="PROFILE_SCOPE_DESCRIBE"/>
<c n="begin"/>
<c n="end"/>
<c n="begin"/>
<c n="end"/>
<c n="size"/>
<c n="pageRankDouble"/>
</s>
<s t="fn" n="biasPrior" id="./src/graph.h::rw::biasPrior" k="0.5000">
<c n="size"/>
</s>
<s t="fn" n="rankGraph" id="./src/graph.h::rw::rankGraph" k="0.5000">
<c n="rankGraphTeleport"/>
<c n="size"/>
</s>
<s t="fn" n="anchoredLexicalRank" id="./src/graph.h::rw::anchoredLexicalRank" amb="7" k="0.5000">
<c n="rankGraphTeleport"/>
<c n="blendMaxNorm"/>
<c n="min"/>
<c n="back"/>
<c n="back"/>
<c n="begin"/>
… [2857 more display lines; full output is 64569 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --callers=rankGraphTeleport`

*Who calls SYM (1-hop in-edges).*

`````
<!-- ripwire callers/callees: the 1-hop call hierarchy read straight off the call graph. The callers form lists the symbols that CALL of=; the callees form lists the symbols of= itself calls. of= is the selector you passed, defs= how many DEFINITIONS that name resolved to (the rows UNION every def's neighbours), and count= the number of DISTINCT neighbour symbols (a floor, per counts_floor=), which the rows window with limit= and offset=. A neighbour that is an indexed function-like #define is a macro row (t="macro", role="macro" on the XML row): the edge crosses a macro expansion, not a plain call — rows carry no role= otherwise. counts_floor="1" means every count on this element is a FLOOR, never a total. Call edges are extracted from source text by NAME, so a call that reaches its target through dynamic dispatch (a virtual, interface or duck-typed receiver), or a declaration that parses without a call expression (C++ most-vexing-parse) contributes no edge and is missing here. A call through a function pointer or callback resolves only when ONE function is bound to that variable in scope (C-family; a reassigned, table-indexed, lambda-bound or escaped pointer — its address taken or reference-bound — still contributes no edge). A binding written as a plain name rather than an address-of (fp = handler, not fp = &handler) is read as a function only when the variable is PROVEN able to hold one: a function-pointer declarator, or a function-pointer typedef declared in the SAME FILE, or a type the parse cannot pin down at all (auto, a template type). Under any other concrete written type it is a value copy and contributes no edge, so a variable whose function-pointer typedef lives in a HEADER is missed. A macro-generated call site contributes a role="macro" edge when its name uniquely names an indexed function-like #define (C-family, t="macro"); a name shared with any non-macro definition stays a plain call for the resolver, and an unindexed macro's call site contributes no edge. Read a zero as "none found", never as "none exists". COUNTING UNIT, and it differs by verb — which is why two of them report different numbers for one symbol. The callers, callees, edit-check, graph-query and pr-context counts are DISTINCT SYMBOLS: repeated calls from one caller, and calls to two overloads of one name, collapse into ONE row, their multiplicity surviving only in the call graph's edge weight. The reach counts (impact's reaches=, pr-context's dependents=) are the size of a transitive reach SET, each symbol counted once — not a count of calls or edges. The uses verb counts call SITES, one row per occurrence, so a larger count= there for the same symbol is these units agreeing, not disagreeing. The map header's edges= is a unit again different — distinct (caller,callee) PAIRS — and that document carries neither this marker nor this clause, so its numbers answer a different question. -->
<!-- root= on this element is the crawl root every p= below is RELATIVE to (single-root runs only; absent => p= is the path ingest itself used, unchanged). -->
<callers of="rankGraphTeleport" defs="1" count="6" root="." counts_floor="1">
<s t="fn" n="runEval" p="src/eval.h:168"/>
<s t="fn" n="rankGraph" p="src/graph.h:2153"/>
<s t="fn" n="anchoredLexicalRank" p="src/graph.h:2489"/>
<s t="fn" n="churnRankedGraph" p="src/main.cpp:12504"/>
<s t="fn" n="runDefaultMap" p="src/main.cpp:12619"/>
<s t="fn" n="getIndex" p="src/mcpindex.h:950"/>
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
<!-- ripwire callers/callees: the 1-hop call hierarchy read straight off the call graph. The callers form lists the symbols that CALL of=; the callees form lists the symbols of= itself calls. of= is the selector you passed, defs= how many DEFINITIONS that name resolved to (the rows UNION every def's neighbours), and count= the number of DISTINCT neighbour symbols (a floor, per counts_floor=), which the rows window with limit= and offset=. A neighbour that is an indexed function-like #define is a macro row (t="macro", role="macro" on the XML row): the edge crosses a macro expansion, not a plain call — rows carry no role= otherwise. When emitted by callees, bodyless_defs= (when present) counts how many of the defs= are declarations with no body (header-only or forward-declared); zero callees may mean no body to read callees from rather than truly no dependencies. counts_floor="1" means every count on this element is a FLOOR, never a total. Call edges are extracted from source text by NAME, so a call that reaches its target through dynamic dispatch (a virtual, interface or duck-typed receiver), or a declaration that parses without a call expression (C++ most-vexing-parse) contributes no edge and is missing here. A call through a function pointer or callback resolves only when ONE function is bound to that variable in scope (C-family; a reassigned, table-indexed, lambda-bound or escaped pointer — its address taken or reference-bound — still contributes no edge). A binding written as a plain name rather than an address-of (fp = handler, not fp = &handler) is read as a function only when the variable is PROVEN able to hold one: a function-pointer declarator, or a function-pointer typedef declared in the SAME FILE, or a type the parse cannot pin down at all (auto, a template type). Under any other concrete written type it is a value copy and contributes no edge, so a variable whose function-pointer typedef lives in a HEADER is missed. A macro-generated call site contributes a role="macro" edge when its name uniquely names an indexed function-like #define (C-family, t="macro"); a name shared with any non-macro definition stays a plain call for the resolver, and an unindexed macro's call site contributes no edge. Read a zero as "none found", never as "none exists". COUNTING UNIT, and it differs by verb — which is why two of them report different numbers for one symbol. The callers, callees, edit-check, graph-query and pr-context counts are DISTINCT SYMBOLS: repeated calls from one caller, and calls to two overloads of one name, collapse into ONE row, their multiplicity surviving only in the call graph's edge weight. The reach counts (impact's reaches=, pr-context's dependents=) are the size of a transitive reach SET, each symbol counted once — not a count of calls or edges. The uses verb counts call SITES, one row per occurrence, so a larger count= there for the same symbol is these units agreeing, not disagreeing. The map header's edges= is a unit again different — distinct (caller,callee) PAIRS — and that document carries neither this marker nor this clause, so its numbers answer a different question. -->
<!-- root= on this element is the crawl root every p= below is RELATIVE to (single-root runs only; absent => p= is the path ingest itself used, unchanged). -->
<callees of="rankGraphTeleport" defs="1" count="9" root="." counts_floor="1">
<s t="fn" n="biasPrior" p="src/graph.h:2075"/>
<s t="macro" n="PROFILE_SCOPE_DESCRIBE" p="src/infra/profileScope.h:1322" role="macro"/>
<s t="macro" n="PROFILE_SCOPE_DESCRIBE" p="src/infra/profileScope.h:1336" role="macro"/>
<s t="method" n="begin" p="src/infra/svector.h:269"/>
<s t="method" n="end" p="src/infra/svector.h:270"/>
<s t="method" n="begin" p="src/infra/svector.h:271"/>
<s t="method" n="end" p="src/infra/svector.h:272"/>
<s t="method" n="size" p="src/infra/svector.h:285"/>
<s t="fn" n="pageRankDouble" p="src/pagerank.cpp:95"/>
</callees>
`````

## `./build/ripwire . --uses=rankGraphTeleport`

*The resolvable use-sites (call/read/write/import/extends) with file:line; count= is a floor.*

`````
<!-- ripwire uses: the STATICALLY RESOLVABLE use-sites of SYM (role=call|macro|read|write|import|extends|type; p=file:line) — a floor, see counts_floor below. That role list is the whole vocabulary. role="type" is a bare TYPE mention — SYM named as a type in a signature, a declaration or a template argument — and it carries no call edge: a type dependency is real, but it is not an invocation, so it never reaches the call graph, PageRank or the ranked map. It is captured for C/C++/ObjC only, and only where the type is spelled as a plain leaf name, so a mention written through a qualified or aliased spelling still contributes no row. A base clause is role="extends" rather than role="type" (that relation is modelled separately), and a type's own DEFINITION is never a use of itself. role="macro" is the call-shaped invocation of a name that uniquely names an indexed function-like #define — never labelled role="call", because an expansion is not a plain call; a name shared with a non-macro definition stays role="call" for the resolver. Reference-name-based (same heuristic level as call edges) — verify in source if a name is overloaded. external="1" ⇒ SYM has no definition in the indexed tree under ANY spelling (stdlib/third-party) — never merely none in the file you qualified with (that spelling refuses instead). A "file:name" SYM narrows defs= AND the role="call" sites, which are kept only where the call RESOLVES to a chosen def (the callers verb's own narrowing, read the other way, so the two agree); read/write/import/extends carry no resolution and stay name-matched across every def sharing the name. narrowed_roles= names what narrowed, and defs_of_name=/call_sites_of_name= (file: qualifier only) are the un-narrowed totals. counts_floor="1" means every count on this element is a FLOOR, never a total. Call edges are extracted from source text by NAME, so a call that reaches its target through dynamic dispatch (a virtual, interface or duck-typed receiver), or a declaration that parses without a call expression (C++ most-vexing-parse) contributes no edge and is missing here. A call through a function pointer or callback resolves only when ONE function is bound to that variable in scope (C-family; a reassigned, table-indexed, lambda-bound or escaped pointer — its address taken or reference-bound — still contributes no edge). A binding written as a plain name rather than an address-of (fp = handler, not fp = &handler) is read as a function only when the variable is PROVEN able to hold one: a function-pointer declarator, or a function-pointer typedef declared in the SAME FILE, or a type the parse cannot pin down at all (auto, a template type). Under any other concrete written type it is a value copy and contributes no edge, so a variable whose function-pointer typedef lives in a HEADER is missed. A macro-generated call site contributes a role="macro" edge when its name uniquely names an indexed function-like #define (C-family, t="macro"); a name shared with any non-macro definition stays a plain call for the resolver, and an unindexed macro's call site contributes no edge. Read a zero as "none found", never as "none exists". COUNTING UNIT, and it differs by verb — which is why two of them report different numbers for one symbol. The callers, callees, edit-check, graph-query and pr-context counts are DISTINCT SYMBOLS: repeated calls from one caller, and calls to two overloads of one name, collapse into ONE row, their multiplicity surviving only in the call graph's edge weight. The reach counts (impact's reaches=, pr-context's dependents=) are the size of a transitive reach SET, each symbol counted once — not a count of calls or edges. The uses verb counts call SITES, one row per occurrence, so a larger count= there for the same symbol is these units agreeing, not disagreeing. The map header's edges= is a unit again different — distinct (caller,callee) PAIRS — and that document carries neither this marker nor this clause, so its numbers answer a different question. -->
<!-- root= on this element is the crawl root every p= below is RELATIVE to (single-root runs only; absent => p= is the path ingest itself used, unchanged). -->
<uses of="rankGraphTeleport" defs="1" external="0" count="9" root="." counts_floor="1">
<u role="call" p="src/eval.h:322" in_id="./src/eval.h::rw::runEval"/>
<u role="call" p="src/graph.h:2156" in_id="./src/graph.h::rw::rankGraph"/>
<u role="call" p="src/graph.h:2533" in_id="./src/graph.h::rw::anchoredLexicalRank"/>
<u role="call" p="src/main.cpp:12528" in_id="churnRankedGraph"/>
<u role="call" p="src/main.cpp:12529" in_id="churnRankedGraph"/>
<u role="call" p="src/main.cpp:12539" in_id="churnRankedGraph"/>
<u role="call" p="src/main.cpp:12545" in_id="churnRankedGraph"/>
<u role="call" p="src/main.cpp:12716" in_id="runDefaultMap"/>
<u role="call" p="src/mcpindex.h:1041" in_id="./src/mcpindex.h::rw::getIndex"/>
</uses>
`````

## `./build/ripwire . --graph-query='and(callers(name("rankGraphTeleport"),2),kind(all,fn))'`

*Composable node-set query: functions within 2 caller-hops of rankGraphTeleport.*

`````
<!-- ripwire graph-query: a fixed-operator node-set query over the call graph (sources name/all; filters kind/cx/fanin/file/layer; bounded closure callers/callees; joins and/or/not), ranked by importance + capped at the top-k limit (default 200); narrow the query or raise top-k for more. NOT Datalog. counts_floor="1" means every count on this element is a FLOOR, never a total. Call edges are extracted from source text by NAME, so a call that reaches its target through dynamic dispatch (a virtual, interface or duck-typed receiver), or a declaration that parses without a call expression (C++ most-vexing-parse) contributes no edge and is missing here. A call through a function pointer or callback resolves only when ONE function is bound to that variable in scope (C-family; a reassigned, table-indexed, lambda-bound or escaped pointer — its address taken or reference-bound — still contributes no edge). A binding written as a plain name rather than an address-of (fp = handler, not fp = &handler) is read as a function only when the variable is PROVEN able to hold one: a function-pointer declarator, or a function-pointer typedef declared in the SAME FILE, or a type the parse cannot pin down at all (auto, a template type). Under any other concrete written type it is a value copy and contributes no edge, so a variable whose function-pointer typedef lives in a HEADER is missed. A macro-generated call site contributes a role="macro" edge when its name uniquely names an indexed function-like #define (C-family, t="macro"); a name shared with any non-macro definition stays a plain call for the resolver, and an unindexed macro's call site contributes no edge. Read a zero as "none found", never as "none exists". COUNTING UNIT, and it differs by verb — which is why two of them report different numbers for one symbol. The callers, callees, edit-check, graph-query and pr-context counts are DISTINCT SYMBOLS: repeated calls from one caller, and calls to two overloads of one name, collapse into ONE row, their multiplicity surviving only in the call graph's edge weight. The reach counts (impact's reaches=, pr-context's dependents=) are the size of a transitive reach SET, each symbol counted once — not a count of calls or edges. The uses verb counts call SITES, one row per occurrence, so a larger count= there for the same symbol is these units agreeing, not disagreeing. The map header's edges= is a unit again different — distinct (caller,callee) PAIRS — and that document carries neither this marker nor this clause, so its numbers answer a different question. pr_iters=pagerank-power-iterations(stop:L1-residual-below-tol,else-ceiling) pr_converged=0-only-when-ceiling-hit-first(absent=converged;no-such-attr=not-pagerank-ordered) -->
<query expr="and(callers(name(&quot;rankGraphTeleport&quot;),2),kind(all,fn))" count="45" shown="45" capped="0" counts_floor="1" root="." pr_iters="32">
<s t="fn" n="getIndex" p="src/mcpindex.h:950"/>
<s t="fn" n="emitCommunitiesReport" p="src/main.cpp:9679"/>
<s t="fn" n="anchoredLexicalRank" p="src/graph.h:2489"/>
<s t="fn" n="emitCommunityDrill" p="src/main.cpp:9839"/>
<s t="fn" n="rankGraph" p="src/graph.h:2153"/>
<s t="fn" n="computeLensRanking" p="src/main.cpp:2230"/>
<s t="fn" n="fetchBody" p="src/mcpverbs.h:2997"/>
<s t="fn" n="runEvalRetrieval" p="src/eval.h:498"/>
<s t="fn" n="runEvalMined" p="src/eval.h:901"/>
<s t="fn" n="dispatchMcpLine" p="src/mcp.h:499"/>
<s t="fn" n="fetchBodyByName" p="src/mcpverbs.h:2928"/>
<s t="fn" n="symbolQueryJson" p="src/mcpverbs.h:474"/>
<s t="fn" n="anchoredFileScore" p="src/eval.h:108"/>
<s t="fn" n="analyzeToString" p="src/mcpverbs.h:371"/>
<s t="fn" n="grepHitsJson" p="src/mcpverbs.h:723"/>
<s t="fn" n="cochangePartnersJson" p="src/mcpverbs.h:847"/>
<s t="fn" n="mentionsJson" p="src/mcpverbs.h:1095"/>
<s t="fn" n="forTaskText" p="src/mcpverbs.h:1155"/>
<s t="fn" n="legoText" p="src/mcpverbs.h:1376"/>
<s t="fn" n="ownersText" p="src/mcpverbs.h:1415"/>
<s t="fn" n="exemplarText" p="src/mcpverbs.h:1529"/>
<s t="fn" n="impactText" p="src/mcpverbs.h:1616"/>
<s t="fn" n="usesText" p="src/mcpverbs.h:1769"/>
<s t="fn" n="pathText" p="src/mcpverbs.h:1863"/>
<s t="fn" n="churnRankedGraph" p="src/main.cpp:12504"/>
<s t="fn" n="runEditVerb" p="src/mcpedit.h:362"/>
<s t="fn" n="runBatchSub" p="src/mcpverbs.h:3317"/>
<s t="fn" n="flagsText" p="src/mcpverbs.h:441"/>
… [18 more display lines; full output is 5213 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --external-surface`

*Names referenced but never defined in-corpus (stdlib/third-party surface). NOW carries names/shown/capped (total= joins them only under --limit/--offset).*

`````
<!-- ripwire external-surface: names CALLED/IMPORTED/EXTENDED but never defined in the indexed tree = the stdlib/third-party surface the code depends on (refs=use-sites, calls=of-which-calls) -->
<external-surface names="1310" shown="1310" capped="0">
<x n="grep" lang="sh" refs="5608" calls="5608"/>
<x n="printf" lang="sh" refs="4847" calls="4847"/>
<x n="echo" lang="sh" refs="4287" calls="4287"/>
<x n="exit" lang="sh" refs="1652" calls="1652"/>
<x n="head" lang="sh" refs="1174" calls="1174"/>
<x n="cat" lang="sh" refs="1036" calls="1036"/>
<x n="cd" lang="sh" refs="906" calls="906"/>
<x n="c_str" lang="cpp" refs="841" calls="841"/>
<x n="tr" lang="sh" refs="824" calls="824"/>
<x n="fprintf" lang="cpp" refs="741" calls="741"/>
<x n="string" lang="cpp" refs="741" calls="741"/>
<x n="python3" lang="sh" refs="635" calls="635"/>
<x n="mkdir" lang="sh" refs="610" calls="610"/>
<x n="printf" lang="cpp" refs="580" calls="580"/>
<x n="sed" lang="sh" refs="575" calls="575"/>
<x n="substr" lang="cpp" refs="536" calls="536"/>
<x n="strcmp" lang="cpp" refs="533" calls="533"/>
<x n="print" lang="py" refs="532" calls="532"/>
<x n="command" lang="sh" refs="507" calls="507"/>
<x n="mktemp" lang="sh" refs="499" calls="499"/>
<x n="len" lang="py" refs="498" calls="498"/>
<x n="dirname" lang="sh" refs="472" calls="472"/>
<x n="pwd" lang="sh" refs="452" calls="452"/>
<x n="trap" lang="sh" refs="425" calls="425"/>
<x n="uint32_t" lang="cpp" refs="422" calls="422"/>
<x n="wc" lang="sh" refs="408" calls="408"/>
<x n="diff" lang="sh" refs="403" calls="403"/>
<x n="xmllint" lang="sh" refs="370" calls="370"/>
… [1283 more display lines; full output is 62359 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --path=main,rankGraphTeleport`

*Shortest directed call-path SRC -> DST. CHANGED: now reports from_p/to_p/from_defs and resolves the right `main` (was reachable="0").*

`````
<!-- root= on this element is the crawl root every p= below is RELATIVE to (single-root runs only; absent => p= is the path ingest itself used, unchanged). -->
<path from="main" to="rankGraphTeleport" from_p="src/main.cpp:14052" to_p="src/graph.h:2112" from_defs="70" to_defs="1" reachable="1" hops="2" root=".">
<s t="fn" n="main" p="src/main.cpp:14052"/>
<s t="fn" n="runDefaultMap" p="src/main.cpp:12619"/>
<s t="fn" n="rankGraphTeleport" p="src/graph.h:2112"/>
</path>
`````

## `./build/ripwire . --connect=rankGraphTeleport,runEval,getIndex`

*Minimal connecting subgraph over 3 symbols (finds shared-caller joins).*

`````
<!-- ripwire connect: minimal joining subgraph over N task symbols (metric-closure 2-approx Steiner; search is undirected so SHARED-CALLER joins are found, every <e f= t=/> keeps its TRUE caller->callee direction; graph-structured navigation per CodeCompass, arXiv 2602.20048). Call edges are name-based: dynamic dispatch / callbacks may hide connections -->
<!-- root= on this element is the crawl root every p= below is RELATIVE to (single-root runs only; absent => p= is the path ingest itself used, unchanged). -->
<connect terminals="3" nodes="3" edges="2" radius="6" groups="1" est_tokens="352" root=".">
<g terminals="3">
<t n="runEval" t="fn" p="src/eval.h:168"/>
<t n="rankGraphTeleport" t="fn" p="src/graph.h:2112"/>
<t n="getIndex" t="fn" p="src/mcpindex.h:950"/>
<e f="runEval" t="rankGraphTeleport"/>
<e f="getIndex" t="rankGraphTeleport"/>
</g>
</connect>
`````

## `./build/ripwire . --impact=rankGraphTeleport`

*Transitive blast radius — everything that reaches SYM. NOW carries shown/capped.*

`````
<!-- ripwire impact: transitive blast radius — symbols that reach SYM via calls (review before changing SYM). raise the default cap with limit=N (offset=M pages); on the root, limit="0" means no explicit limit was given and the verb's own default page size shaped the window — never a zero-row page. counts_floor="1" means every count on this element is a FLOOR, never a total. Call edges are extracted from source text by NAME, so a call that reaches its target through dynamic dispatch (a virtual, interface or duck-typed receiver), or a declaration that parses without a call expression (C++ most-vexing-parse) contributes no edge and is missing here. A call through a function pointer or callback resolves only when ONE function is bound to that variable in scope (C-family; a reassigned, table-indexed, lambda-bound or escaped pointer — its address taken or reference-bound — still contributes no edge). A binding written as a plain name rather than an address-of (fp = handler, not fp = &handler) is read as a function only when the variable is PROVEN able to hold one: a function-pointer declarator, or a function-pointer typedef declared in the SAME FILE, or a type the parse cannot pin down at all (auto, a template type). Under any other concrete written type it is a value copy and contributes no edge, so a variable whose function-pointer typedef lives in a HEADER is missed. A macro-generated call site contributes a role="macro" edge when its name uniquely names an indexed function-like #define (C-family, t="macro"); a name shared with any non-macro definition stays a plain call for the resolver, and an unindexed macro's call site contributes no edge. Read a zero as "none found", never as "none exists". COUNTING UNIT, and it differs by verb — which is why two of them report different numbers for one symbol. The callers, callees, edit-check, graph-query and pr-context counts are DISTINCT SYMBOLS: repeated calls from one caller, and calls to two overloads of one name, collapse into ONE row, their multiplicity surviving only in the call graph's edge weight. The reach counts (impact's reaches=, pr-context's dependents=) are the size of a transitive reach SET, each symbol counted once — not a count of calls or edges. The uses verb counts call SITES, one row per occurrence, so a larger count= there for the same symbol is these units agreeing, not disagreeing. The map header's edges= is a unit again different — distinct (caller,callee) PAIRS — and that document carries neither this marker nor this clause, so its numbers answer a different question. pr_iters=pagerank-power-iterations(stop:L1-residual-below-tol,else-ceiling) pr_converged=0-only-when-ceiling-hit-first(absent=converged;no-such-attr=not-pagerank-ordered) -->
<impact of="rankGraphTeleport" defs="1" reaches="51" root="." shown="40" capped="1" counts_floor="1" pr_iters="32">
<s t="fn" n="getIndex" p="src/mcpindex.h:950"/>
<s t="fn" n="emitCommunitiesReport" p="src/main.cpp:9679"/>
<s t="fn" n="anchoredLexicalRank" p="src/graph.h:2489"/>
<s t="fn" n="emitCommunityDrill" p="src/main.cpp:9839"/>
<s t="fn" n="rankGraph" p="src/graph.h:2153"/>
<s t="fn" n="computeLensRanking" p="src/main.cpp:2230"/>
<s t="fn" n="fetchBody" p="src/mcpverbs.h:2997"/>
<s t="fn" n="runEvalRetrieval" p="src/eval.h:498"/>
<s t="fn" n="runEvalMined" p="src/eval.h:901"/>
<s t="fn" n="dispatchMcpLine" p="src/mcp.h:499"/>
<s t="fn" n="fetchBodyByName" p="src/mcpverbs.h:2928"/>
<s t="fn" n="symbolQueryJson" p="src/mcpverbs.h:474"/>
<s t="fn" n="anchoredFileScore" p="src/eval.h:108"/>
<s t="fn" n="analyzeToString" p="src/mcpverbs.h:371"/>
<s t="fn" n="grepHitsJson" p="src/mcpverbs.h:723"/>
<s t="fn" n="cochangePartnersJson" p="src/mcpverbs.h:847"/>
<s t="fn" n="mentionsJson" p="src/mcpverbs.h:1095"/>
<s t="fn" n="forTaskText" p="src/mcpverbs.h:1155"/>
<s t="fn" n="legoText" p="src/mcpverbs.h:1376"/>
<s t="fn" n="ownersText" p="src/mcpverbs.h:1415"/>
<s t="fn" n="exemplarText" p="src/mcpverbs.h:1529"/>
<s t="fn" n="impactText" p="src/mcpverbs.h:1616"/>
<s t="fn" n="usesText" p="src/mcpverbs.h:1769"/>
<s t="fn" n="pathText" p="src/mcpverbs.h:1863"/>
<s t="fn" n="churnRankedGraph" p="src/main.cpp:12504"/>
<s t="fn" n="runEditVerb" p="src/mcpedit.h:362"/>
<s t="fn" n="runBatchSub" p="src/mcpverbs.h:3317"/>
<s t="fn" n="flagsText" p="src/mcpverbs.h:441"/>
… [13 more display lines; full output is 4942 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --mentions=rankGraphTeleport`

*Markdown docs that name SYM in a backtick (doc<->code edges).*

`````
<!-- ripwire mentions: markdown FILES that name this symbol in a `backtick` (doc<->code; NOT a call edge). docs= is the row count (distinct files); sections= counts the underlying markdown-section mentions before file-collapse (docs <= sections). Each row's mentions= is its own section-mention count. No line locator: the doc edge is stored at file granularity — a fabricated always-1 l= was removed; absent beats fake -->
<!-- root= on this element is the crawl root every p= below is RELATIVE to (single-root runs only; absent => p= is the path ingest itself used, unchanged). -->
<mentions of="rankGraphTeleport" defs="1" docs="2" sections="2" root=".">
<doc p="docs/ARCHITECTURE.md" mentions="1"/>
<doc p="docs/EVALS.md" mentions="1"/>
</mentions>
`````

## `./build/ripwire . --affected=src/graph.h`

*Test files that transitively reach the changed file.*

`````
<!-- ripwire affected: test files that transitively reach the changed files/symbols (run these); seeded_by= says which reading the argument took. script_gates_unmodelled= counts test/*.sh runners in the corpus (a path count; not every one invokes the binary) — script-to-binary edges are NOT modelled, so those gates are invisible to this walk and never counted in tests=/reached= -->
<affected changed="src/graph.h" seeded_by="file" seeds="113" tests="6" reached="553" script_gates_unmodelled="456">
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
root: .
  (no indexed symbols in the changed files — nothing to analyze)
`````

## `./build/ripwire . --test-gate`

*Pre-PR gate on a CLEAN tree: no obligations, exit 0.*

`````
<!-- ripwire test-gate (TDAD-parity, arXiv 2603.17973): the tests to run for this change + the UNTESTED blast radius. A queryable call-graph+test map cut agent-caused regressions -70% (6.08%->1.82%); this gate names the obligations, the agent runs the tests then relies on green. exit 4 if tests OR untested is non-empty. TWO INDEPENDENT LISTINGS, each with its own row count: shown_tests= counts the <t> tests-to-run rows and shown_untested= counts the <u> blast-radius rows (a single shown= could only ever have described one of them). The <t> rows are the COMPLETE obligation and are never windowed, so they REPEAT VERBATIM on every page — a walker that concatenates pages must take them from one page only; offset=/limit= window the <u> rows alone. The <u> listing shows 25 rows by default: raise the default cap with limit=N (offset=M pages). script_gates_unmodelled= counts test/*.sh runners in the corpus (a path count; not every one invokes the binary) - script-to-binary edges are NOT modelled, so those gates are invisible to this walk and never counted in tests=. UNIT: untested= here counts impacted SYMBOLS. The seams verb spells untested= over cross-directory call EDGES and the flip verb over the defs a gate lights, so the three numbers count three different things and must never be compared or summed across verbs. -->
<test-gate changed="0" impacted="0" tests="0" untested="0" shown_tests="0" tests_capped="0" shown_untested="0" untested_capped="0" script_gates_unmodelled="456" at="700e51d49">
</test-gate>
`````

## `./build/ripwire . --grep=DEGRADED_PATH_ALERT`

*Literal trigram-indexed search. CHANGED: each hit now carries the MATCHED line in <m>, plus shown/capped/hits_capped.*

`````
<!-- ripwire grep: parallel literal/regex scan; hits GROUP by file under <f p="…">, each <hit> carrying its LINE (l=), matched text (m) and enclosing symbol (in=, a NAME here; the same spelling is a fan-in COUNT in for/pack-task/exemplar; ABSENT (never an empty in= value) when no symbol encloses the hit, which is NOT the same claim as file scope). root= on the root element is the crawl root every <f p=…> is now RELATIVE to (single-root runs only; absent ⇒ p= is the path ingest itself used, unchanged). ORDER: SOURCE files before test/bench files before docs, then path and line. shown=/capped= = rows printed vs found (a count of underlying HITS, the same unit hits= uses, not of printed <hit> elements); hits_capped="1" ⇒ hits= is a FLOOR (collection budget reached). SPAN TIERS: each hit is classified by the tree-sitter span it sits in (code/comment/string) and this answer serves the CODE tier, or — when no hit is code — comment and string TOGETHER; tier= names what was served when it is not code, so a pattern living only in prose is answered, never emptied. suppressed_comment=/suppressed_string= are the classified hits held back: not in hits=, and the reason complete= cannot appear. Pass grep-in=any (dashes omitted) for every tier. Hit files are parsed on demand under a fixed budget: tier_parsed= how many were classified, tier_budget= which ceiling stopped it (files or bytes, present only then), tier_unclassified= hits in files nothing classified — always EMITTED, never suppressed. A byte-identical match at OTHER sites in the SAME file folds into the first <hit>'s n= (default 1, unset) and an at-tagged sibling element (l=/in=, self-closing) per extra site — never on a paged or grep-context/-before/-after answer (dashes omitted, illegal in an XML comment), where every site keeps its own <hit>. After the hit rows, <enc> rows list each DISTINCT enclosing symbol NAME of THIS page (first-appearance order, bounded by the page) with callers= its 1-hop DISTINCT-caller count, unioned across same-named defs like the callers verb (a FLOOR — dynamic dispatch contributes no edge), defs= how many defs the name grouped (only when more than one), cx= complexity; amp=/tested= join only when a metrics co-run already computed that lens. On a zero-hit answer a <suggest> element may follow: SUGGESTIONS, never matches — near= the nearest indexed symbol name (did-you-mean), next= a ready-to-paste conceptual fallback; absent for regex/non-word-like patterns or when nothing plausible exists. COMPLETENESS: complete= on the root (value 1) means this listing is EXHAUSTIVE and a consumer need not re-derive it: a LITERAL scan read every indexed file end to end, hit no collection ceiling, and printed every hit it found — so on this answer a zero really is zero and a hit absent above is absent from every indexed file. The claim is complete-within-the-index ONLY: most files the ingest skipped were never scanned (the skipped verb lists exactly which, with reasons; the ONE exception is the unindexed_files_scanned= class right below, itself never covered by complete=), and files outside the indexed roots are outside the claim. It never appears on a regex answer (the prefilter is a performance switch that may not change the answer, so neither mode claims), a capped or paged listing, or a scan that could not read a file; its ABSENCE claims nothing. The enc rows' caller counts stay FLOORS regardless — complete= speaks for the hit rows alone. unindexed_files_scanned= counts files outside the index (unsupported-ext, but text-looking — the skipped verb's own unsupported-ext class) that THIS answer additionally scanned for the same pattern; their hits print inside a trailing unindexed element (present only when it found something), holding its own <f> rows in the same shape as above, and never carry in= — there is no symbol table to check for such a file, which is not the same claim as file scope. unindexed_files_skipped= (present only when nonzero) counts candidates this scan saw but did not read: over the max-file-size ceiling, sniffed binary, or unreadable. unindexed_candidates_capped="1" (present only when true) means the CANDIDATE list itself (the skipped verb's own 500-row-per-class cap) was already a floor, so files past it were never considered here either — see the skipped verb for every row. corpus_excluded= counts files an exclude filter (or built-in crawl policy) kept OUT of the index entirely; corpus_oversize= counts files the crawl SAW but dropped for exceeding the size ceiling. Both answer what an otherwise-empty answer alone cannot: not in this repo, or in a file that was never scanned — the skipped verb itemizes the rows behind either count. raise the default cap with limit=N (offset=M pages); on the root, limit="0" means no explicit limit was given and the verb's own default page size shaped the window — never a zero-row page -->
<grep pattern="DEGRADED_PATH_ALERT" root="." files="51" hits="168" shown="100" capped="1" hits_capped="0" suppressed_comment="91" suppressed_string="21" tier_parsed="77" corpus_oversize="15" unindexed_files_scanned="102" unindexed_files_skipped="1">
<f p="src/abicheck.h">
<hit l="477" in="abicheck::collectAuthoredSites">
<m>
<![CDATA[            DEGRADED_PATH_ALERT( "abi: no merge-base for a ref (unrelated history?) — that ref is counted, not compared" );]]>
</m>
</hit>
</f>
<f p="src/arch.h">
<hit l="353" in="rw::parseArchRules">
<m>
<![CDATA[        DEGRADED_PATH_ALERT( "arch: malformed rules line — rules file rejected" );]]>
</m>
</hit>
<hit l="408" in="rw::parseArchRules">
<m>
<![CDATA[                catch( const std::regex_error& ) { pr.bad = true; DEGRADED_PATH_ALERT( "arch: malformed FROM path-regex — rule skipped" ); }]]>
</m>
</hit>
</f>
<f p="src/atoms.h">
<hit l="365" in="atomdetail::collectExclusions">
<m>
<![CDATA[        DEGRADED_PATH_ALERT( "atoms: an exclusion capture stream spent its whole budget; the rules reading it are suppressed this run" );]]>
</m>
</hit>
</f>
<f p="src/clones.h">
<hit l="809" in="rw::findClonesType3">
… [762 more display lines; full output is 31764 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --grep=DEGRADED_PATH_ALERT --grep-context=1`

*Same search with one line of source context either side.*

`````
<!-- ripwire grep: parallel literal/regex scan; hits GROUP by file under <f p="…">, each <hit> carrying its LINE (l=), matched text (m) and enclosing symbol (in=, a NAME here; the same spelling is a fan-in COUNT in for/pack-task/exemplar; ABSENT (never an empty in= value) when no symbol encloses the hit, which is NOT the same claim as file scope). root= on the root element is the crawl root every <f p=…> is now RELATIVE to (single-root runs only; absent ⇒ p= is the path ingest itself used, unchanged). ORDER: SOURCE files before test/bench files before docs, then path and line. shown=/capped= = rows printed vs found (a count of underlying HITS, the same unit hits= uses, not of printed <hit> elements); hits_capped="1" ⇒ hits= is a FLOOR (collection budget reached). SPAN TIERS: each hit is classified by the tree-sitter span it sits in (code/comment/string) and this answer serves the CODE tier, or — when no hit is code — comment and string TOGETHER; tier= names what was served when it is not code, so a pattern living only in prose is answered, never emptied. suppressed_comment=/suppressed_string= are the classified hits held back: not in hits=, and the reason complete= cannot appear. Pass grep-in=any (dashes omitted) for every tier. Hit files are parsed on demand under a fixed budget: tier_parsed= how many were classified, tier_budget= which ceiling stopped it (files or bytes, present only then), tier_unclassified= hits in files nothing classified — always EMITTED, never suppressed. A byte-identical match at OTHER sites in the SAME file folds into the first <hit>'s n= (default 1, unset) and an at-tagged sibling element (l=/in=, self-closing) per extra site — never on a paged or grep-context/-before/-after answer (dashes omitted, illegal in an XML comment), where every site keeps its own <hit>. After the hit rows, <enc> rows list each DISTINCT enclosing symbol NAME of THIS page (first-appearance order, bounded by the page) with callers= its 1-hop DISTINCT-caller count, unioned across same-named defs like the callers verb (a FLOOR — dynamic dispatch contributes no edge), defs= how many defs the name grouped (only when more than one), cx= complexity; amp=/tested= join only when a metrics co-run already computed that lens. On a zero-hit answer a <suggest> element may follow: SUGGESTIONS, never matches — near= the nearest indexed symbol name (did-you-mean), next= a ready-to-paste conceptual fallback; absent for regex/non-word-like patterns or when nothing plausible exists. COMPLETENESS: complete= on the root (value 1) means this listing is EXHAUSTIVE and a consumer need not re-derive it: a LITERAL scan read every indexed file end to end, hit no collection ceiling, and printed every hit it found — so on this answer a zero really is zero and a hit absent above is absent from every indexed file. The claim is complete-within-the-index ONLY: most files the ingest skipped were never scanned (the skipped verb lists exactly which, with reasons; the ONE exception is the unindexed_files_scanned= class right below, itself never covered by complete=), and files outside the indexed roots are outside the claim. It never appears on a regex answer (the prefilter is a performance switch that may not change the answer, so neither mode claims), a capped or paged listing, or a scan that could not read a file; its ABSENCE claims nothing. The enc rows' caller counts stay FLOORS regardless — complete= speaks for the hit rows alone. unindexed_files_scanned= counts files outside the index (unsupported-ext, but text-looking — the skipped verb's own unsupported-ext class) that THIS answer additionally scanned for the same pattern; their hits print inside a trailing unindexed element (present only when it found something), holding its own <f> rows in the same shape as above, and never carry in= — there is no symbol table to check for such a file, which is not the same claim as file scope. unindexed_files_skipped= (present only when nonzero) counts candidates this scan saw but did not read: over the max-file-size ceiling, sniffed binary, or unreadable. unindexed_candidates_capped="1" (present only when true) means the CANDIDATE list itself (the skipped verb's own 500-row-per-class cap) was already a floor, so files past it were never considered here either — see the skipped verb for every row. corpus_excluded= counts files an exclude filter (or built-in crawl policy) kept OUT of the index entirely; corpus_oversize= counts files the crawl SAW but dropped for exceeding the size ceiling. Both answer what an otherwise-empty answer alone cannot: not in this repo, or in a file that was never scanned — the skipped verb itemizes the rows behind either count. raise the default cap with limit=N (offset=M pages); on the root, limit="0" means no explicit limit was given and the verb's own default page size shaped the window — never a zero-row page -->
<grep pattern="DEGRADED_PATH_ALERT" root="." files="51" hits="168" shown="100" capped="1" hits_capped="0" suppressed_comment="91" suppressed_string="21" tier_parsed="77" corpus_oversize="15" unindexed_files_scanned="102" unindexed_files_skipped="1">
<f p="src/abicheck.h">
<hit l="477" in="abicheck::collectAuthoredSites">
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
</f>
<f p="src/arch.h">
<hit l="353" in="rw::parseArchRules">
<b>
<![CDATA[        std::fprintf( stderr, "ripwire: --arch: %s:%zu: %s — rules file rejected\n", path.c_str(), lineNo, why );]]>
</b>
<m>
<![CDATA[        DEGRADED_PATH_ALERT( "arch: malformed rules line — rules file rejected" );]]>
</m>
<a>
<![CDATA[        return false;]]>
</a>
</hit>
<hit l="408" in="rw::parseArchRules">
<b>
<![CDATA[                try { pr.fromRe = std::regex( fromRe, std::regex::ECMAScript ); }]]>
… [1350 more display lines; full output is 41176 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --regex='fnv1a\w+'`

*Regex search + enclosing symbol.*

`````
<!-- ripwire grep: parallel literal/regex scan; hits GROUP by file under <f p="…">, each <hit> carrying its LINE (l=), matched text (m) and enclosing symbol (in=, a NAME here; the same spelling is a fan-in COUNT in for/pack-task/exemplar; ABSENT (never an empty in= value) when no symbol encloses the hit, which is NOT the same claim as file scope). root= on the root element is the crawl root every <f p=…> is now RELATIVE to (single-root runs only; absent ⇒ p= is the path ingest itself used, unchanged). ORDER: SOURCE files before test/bench files before docs, then path and line. shown=/capped= = rows printed vs found (a count of underlying HITS, the same unit hits= uses, not of printed <hit> elements); hits_capped="1" ⇒ hits= is a FLOOR (collection budget reached). SPAN TIERS: each hit is classified by the tree-sitter span it sits in (code/comment/string) and this answer serves the CODE tier, or — when no hit is code — comment and string TOGETHER; tier= names what was served when it is not code, so a pattern living only in prose is answered, never emptied. suppressed_comment=/suppressed_string= are the classified hits held back: not in hits=, and the reason complete= cannot appear. Pass grep-in=any (dashes omitted) for every tier. Hit files are parsed on demand under a fixed budget: tier_parsed= how many were classified, tier_budget= which ceiling stopped it (files or bytes, present only then), tier_unclassified= hits in files nothing classified — always EMITTED, never suppressed. A byte-identical match at OTHER sites in the SAME file folds into the first <hit>'s n= (default 1, unset) and an at-tagged sibling element (l=/in=, self-closing) per extra site — never on a paged or grep-context/-before/-after answer (dashes omitted, illegal in an XML comment), where every site keeps its own <hit>. After the hit rows, <enc> rows list each DISTINCT enclosing symbol NAME of THIS page (first-appearance order, bounded by the page) with callers= its 1-hop DISTINCT-caller count, unioned across same-named defs like the callers verb (a FLOOR — dynamic dispatch contributes no edge), defs= how many defs the name grouped (only when more than one), cx= complexity; amp=/tested= join only when a metrics co-run already computed that lens. On a zero-hit answer a <suggest> element may follow: SUGGESTIONS, never matches — near= the nearest indexed symbol name (did-you-mean), next= a ready-to-paste conceptual fallback; absent for regex/non-word-like patterns or when nothing plausible exists. COMPLETENESS: complete= on the root (value 1) means this listing is EXHAUSTIVE and a consumer need not re-derive it: a LITERAL scan read every indexed file end to end, hit no collection ceiling, and printed every hit it found — so on this answer a zero really is zero and a hit absent above is absent from every indexed file. The claim is complete-within-the-index ONLY: most files the ingest skipped were never scanned (the skipped verb lists exactly which, with reasons; the ONE exception is the unindexed_files_scanned= class right below, itself never covered by complete=), and files outside the indexed roots are outside the claim. It never appears on a regex answer (the prefilter is a performance switch that may not change the answer, so neither mode claims), a capped or paged listing, or a scan that could not read a file; its ABSENCE claims nothing. The enc rows' caller counts stay FLOORS regardless — complete= speaks for the hit rows alone. unindexed_files_scanned= counts files outside the index (unsupported-ext, but text-looking — the skipped verb's own unsupported-ext class) that THIS answer additionally scanned for the same pattern; their hits print inside a trailing unindexed element (present only when it found something), holding its own <f> rows in the same shape as above, and never carry in= — there is no symbol table to check for such a file, which is not the same claim as file scope. unindexed_files_skipped= (present only when nonzero) counts candidates this scan saw but did not read: over the max-file-size ceiling, sniffed binary, or unreadable. unindexed_candidates_capped="1" (present only when true) means the CANDIDATE list itself (the skipped verb's own 500-row-per-class cap) was already a floor, so files past it were never considered here either — see the skipped verb for every row. corpus_excluded= counts files an exclude filter (or built-in crawl policy) kept OUT of the index entirely; corpus_oversize= counts files the crawl SAW but dropped for exceeding the size ceiling. Both answer what an otherwise-empty answer alone cannot: not in this repo, or in a file that was never scanned — the skipped verb itemizes the rows behind either count. raise the default cap with limit=N (offset=M pages); on the root, limit="0" means no explicit limit was given and the verb's own default page size shaped the window — never a zero-row page -->
<grep pattern="fnv1a\w+" root="." files="16" hits="67" shown="67" capped="0" hits_capped="0" suppressed_comment="34" suppressed_string="10" tier_parsed="25" corpus_oversize="15" unindexed_files_scanned="102" unindexed_files_skipped="1">
<f p="src/arch.h">
<hit l="507" in="rw::fnv1a64">
<m>
<![CDATA[inline std::uint64_t fnv1a64( std::string_view s ) noexcept]]>
</m>
</hit>
<hit l="512" in="rw::fnv1a64">
<m>
<![CDATA[        h = hashutil::fnv1aAbsorb( h, c );]]>
</m>
</hit>
<hit l="585" in="rw::archViolHash">
<m>
<![CDATA[            h = hashutil::fnv1aAbsorb( h, c );]]>
</m>
</hit>
<hit l="588" in="rw::archViolHash">
<m>
<![CDATA[        h = hashutil::fnv1aMultiply( h ); // NUL separator byte]]>
</m>
</hit>
</f>
<f p="src/clones.h">
<hit l="575" in="rw::cloneTokenHash">
<m>
<![CDATA[        h = hashutil::fnv1aAbsorb( h, c );]]>
</m>
</hit>
… [501 more display lines; full output is 19757 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --match='(if_statement)'`

*Tree-sitter structural query WITHOUT a capture — a bare node query gets a capture AUTO-ADDED (auto_captured="1") instead of silently matching nothing.*

`````
<!-- ripwire match: tree-sitter structural query; each hit = a captured node + its enclosing symbol. shown=/capped= = rows printed vs found; hits_capped="1" ⇒ hits= is a FLOOR (engine match limit reached). auto_captured="1" ⇒ the query bound no @capture and ripwire appended `@m` to its single top-level pattern. grammars= names every grammar the query compiled against; eligible_files=/of_files= are corpus files in that language set vs total indexed files. raise the default cap with limit=N (offset=M pages) -->
<match hits="5000" shown="100" capped="1" hits_capped="1" auto_captured="1" grammars="cpp,c,python,go,typescript,swift,objc,javascript,bash,java,csharp" eligible_files="1063" of_files="1304" root=".">
<m p="bench/agentloop/analyze.py:37" in="load_results">if data.get( "schema" ) != SCHEMA:         raise SystemExit( f"{path}: unexpected schema {data.get('schema')!r} (expecte</m>
<m p="bench/agentloop/analyze.py:48" in="load_results">if not str( data.get( "tasks_lock_content_sha256", "" ) ).startswith( "questions:" ):         train_repos = select_tasks</m>
<m p="bench/agentloop/analyze.py:50" in="load_results">if train_repos:             raise SystemExit(                 f"{path}: records from repo(s) that re-derive to LocBench </m>
<m p="bench/agentloop/analyze.py:72" in="pair_by_task_seed">if base and ctx and base["status"] == "ok" and ctx["status"] == "ok":             paired.append( ( instance_id, base["re</m>
<m p="bench/agentloop/analyze.py:101" in="clustered_bootstrap_lower">if not repos: return 0.0, []</m>
<m p="bench/agentloop/analyze.py:117" in="loc_hit_delta">if base["localization_hit"] is None or ctx["localization_hit"] is None: return 0.0</m>
<m p="bench/agentloop/analyze.py:126" in="paired_ratio">if bv: ratios.append( cv / bv - 1 )</m>
<m p="bench/agentloop/analyze.py:127" in="paired_ratio">if not ratios: return None, None</m>
<m p="bench/agentloop/analyze.py:144" in="substitution_rate">if rw is None or native is None:         return None</m>
<m p="bench/agentloop/analyze.py:167" in="analyze">if not paired:         out["note"] = "zero complete paired (baseline,ripwire_cli) runs — nothing to analyze yet"      </m>
<m p="bench/agentloop/analyze.py:204" in="print_report">if contaminated:         print( f"  ** {contaminated} baseline run(s) invoked ripwire despite the no-ripwire contract " </m>
<m p="bench/agentloop/analyze.py:208" in="print_report">if "note" in out:         print( f"  {out['note']}" ); return</m>
<m p="bench/agentloop/analyze.py:292" in="self_test">if out["n_pairs"] != 27: failures.append( f"expected 27 paired runs, got {out['n_pairs']}" )</m>
<m p="bench/agentloop/analyze.py:293" in="self_test">if out["n_incomplete"] != 2:         failures.append( f"expected 2 incomplete pairs (the orphan + the contaminated-basel</m>
<m p="bench/agentloop/analyze.py:296" in="self_test">if out["n_repos"] != 3: failures.append( f"expected 3 repos, got {out['n_repos']}" )</m>
<m p="bench/agentloop/analyze.py:297" in="self_test">if out.get( "n_contaminated_baseline" ) != 1:         failures.append( f"expected exactly 1 contaminated baseline run co</m>
<m p="bench/agentloop/analyze.py:300" in="self_test">if not ( out["resolved_delta_mean"] &gt; 0 ): failures.append( "expected a positive resolved-rate delta" )</m>
<m p="bench/agentloop/analyze.py:301" in="self_test">if not ( out["resolved_delta_bootstrap_95_lower"] &gt; 0 ):         failures.append( "expected a POSITIVE bootstrap 95% low</m>
<m p="bench/agentloop/analyze.py:303" in="self_test">if out["tokens_out_ratio_p50"] is None or abs( out["tokens_out_ratio_p50"] - 0.08 ) &gt; 1e-6:         failures.append( f"e</m>
<m p="bench/agentloop/analyze.py:306" in="self_test">if out.get( "n_resolved_pairs" ) != 27:         failures.append( f"expected all 27 pairs resolution-scored, got {out.get</m>
<m p="bench/agentloop/analyze.py:309" in="self_test">if out.get( "substitution_rate_baseline" ) != 0.0:         failures.append( f"expected baseline substitution rate 0.0 (n</m>
<m p="bench/agentloop/analyze.py:312" in="self_test">if out.get( "substitution_rate_ripwire" ) is None or abs( out["substitution_rate_ripwire"] - 0.75 ) &gt; 1e-9:         fail</m>
<m p="bench/agentloop/analyze.py:315" in="self_test">if out.get( "n_substitution_ripwire" ) != 27:         failures.append( f"expected 27 substitution-scored ripwire runs, g</m>
<m p="bench/agentloop/analyze.py:321" in="self_test">if out3.get( "substitution_rate_ripwire" ) is not None or out3.get( "n_substitution_ripwire" ) != 0:         failures.ap</m>
<m p="bench/agentloop/analyze.py:327" in="self_test">if out2["n_pairs"] != 27:         failures.append( f"evaluator-none: expected 27 pairs, got {out2['n_pairs']}" )</m>
<m p="bench/agentloop/analyze.py:329" in="self_test">if out2["n_resolved_pairs"] != 0:         failures.append( f"evaluator-none: expected 0 resolution-scored pairs, got {ou</m>
<m p="bench/agentloop/analyze.py:331" in="self_test">if out2["resolved_delta_mean"] is not None or out2["resolved_delta_bootstrap_95_lower"] is not None:         failures.ap</m>
<m p="bench/agentloop/analyze.py:333" in="self_test">if out2["tokens_out_ratio_p50"] is None or abs( out2["tokens_out_ratio_p50"] - 0.08 ) &gt; 1e-6:         failures.append( "</m>
… [73 more display lines; full output is 16608 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --match='(if_statement) @i'`

*The same shape query WITH a capture — the form that actually matches.*

`````
<!-- ripwire match: tree-sitter structural query; each hit = a captured node + its enclosing symbol. shown=/capped= = rows printed vs found; hits_capped="1" ⇒ hits= is a FLOOR (engine match limit reached). auto_captured="1" ⇒ the query bound no @capture and ripwire appended `@m` to its single top-level pattern. grammars= names every grammar the query compiled against; eligible_files=/of_files= are corpus files in that language set vs total indexed files. raise the default cap with limit=N (offset=M pages) -->
<match hits="5000" shown="100" capped="1" hits_capped="1" grammars="cpp,c,python,go,typescript,swift,objc,javascript,bash,java,csharp" eligible_files="1063" of_files="1304" root=".">
<m p="bench/agentloop/analyze.py:37" in="load_results">if data.get( "schema" ) != SCHEMA:         raise SystemExit( f"{path}: unexpected schema {data.get('schema')!r} (expecte</m>
<m p="bench/agentloop/analyze.py:48" in="load_results">if not str( data.get( "tasks_lock_content_sha256", "" ) ).startswith( "questions:" ):         train_repos = select_tasks</m>
<m p="bench/agentloop/analyze.py:50" in="load_results">if train_repos:             raise SystemExit(                 f"{path}: records from repo(s) that re-derive to LocBench </m>
<m p="bench/agentloop/analyze.py:72" in="pair_by_task_seed">if base and ctx and base["status"] == "ok" and ctx["status"] == "ok":             paired.append( ( instance_id, base["re</m>
<m p="bench/agentloop/analyze.py:101" in="clustered_bootstrap_lower">if not repos: return 0.0, []</m>
<m p="bench/agentloop/analyze.py:117" in="loc_hit_delta">if base["localization_hit"] is None or ctx["localization_hit"] is None: return 0.0</m>
<m p="bench/agentloop/analyze.py:126" in="paired_ratio">if bv: ratios.append( cv / bv - 1 )</m>
<m p="bench/agentloop/analyze.py:127" in="paired_ratio">if not ratios: return None, None</m>
<m p="bench/agentloop/analyze.py:144" in="substitution_rate">if rw is None or native is None:         return None</m>
<m p="bench/agentloop/analyze.py:167" in="analyze">if not paired:         out["note"] = "zero complete paired (baseline,ripwire_cli) runs — nothing to analyze yet"      </m>
<m p="bench/agentloop/analyze.py:204" in="print_report">if contaminated:         print( f"  ** {contaminated} baseline run(s) invoked ripwire despite the no-ripwire contract " </m>
<m p="bench/agentloop/analyze.py:208" in="print_report">if "note" in out:         print( f"  {out['note']}" ); return</m>
<m p="bench/agentloop/analyze.py:292" in="self_test">if out["n_pairs"] != 27: failures.append( f"expected 27 paired runs, got {out['n_pairs']}" )</m>
<m p="bench/agentloop/analyze.py:293" in="self_test">if out["n_incomplete"] != 2:         failures.append( f"expected 2 incomplete pairs (the orphan + the contaminated-basel</m>
<m p="bench/agentloop/analyze.py:296" in="self_test">if out["n_repos"] != 3: failures.append( f"expected 3 repos, got {out['n_repos']}" )</m>
<m p="bench/agentloop/analyze.py:297" in="self_test">if out.get( "n_contaminated_baseline" ) != 1:         failures.append( f"expected exactly 1 contaminated baseline run co</m>
<m p="bench/agentloop/analyze.py:300" in="self_test">if not ( out["resolved_delta_mean"] &gt; 0 ): failures.append( "expected a positive resolved-rate delta" )</m>
<m p="bench/agentloop/analyze.py:301" in="self_test">if not ( out["resolved_delta_bootstrap_95_lower"] &gt; 0 ):         failures.append( "expected a POSITIVE bootstrap 95% low</m>
<m p="bench/agentloop/analyze.py:303" in="self_test">if out["tokens_out_ratio_p50"] is None or abs( out["tokens_out_ratio_p50"] - 0.08 ) &gt; 1e-6:         failures.append( f"e</m>
<m p="bench/agentloop/analyze.py:306" in="self_test">if out.get( "n_resolved_pairs" ) != 27:         failures.append( f"expected all 27 pairs resolution-scored, got {out.get</m>
<m p="bench/agentloop/analyze.py:309" in="self_test">if out.get( "substitution_rate_baseline" ) != 0.0:         failures.append( f"expected baseline substitution rate 0.0 (n</m>
<m p="bench/agentloop/analyze.py:312" in="self_test">if out.get( "substitution_rate_ripwire" ) is None or abs( out["substitution_rate_ripwire"] - 0.75 ) &gt; 1e-9:         fail</m>
<m p="bench/agentloop/analyze.py:315" in="self_test">if out.get( "n_substitution_ripwire" ) != 27:         failures.append( f"expected 27 substitution-scored ripwire runs, g</m>
<m p="bench/agentloop/analyze.py:321" in="self_test">if out3.get( "substitution_rate_ripwire" ) is not None or out3.get( "n_substitution_ripwire" ) != 0:         failures.ap</m>
<m p="bench/agentloop/analyze.py:327" in="self_test">if out2["n_pairs"] != 27:         failures.append( f"evaluator-none: expected 27 pairs, got {out2['n_pairs']}" )</m>
<m p="bench/agentloop/analyze.py:329" in="self_test">if out2["n_resolved_pairs"] != 0:         failures.append( f"evaluator-none: expected 0 resolution-scored pairs, got {ou</m>
<m p="bench/agentloop/analyze.py:331" in="self_test">if out2["resolved_delta_mean"] is not None or out2["resolved_delta_bootstrap_95_lower"] is not None:         failures.ap</m>
<m p="bench/agentloop/analyze.py:333" in="self_test">if out2["tokens_out_ratio_p50"] is None or abs( out2["tokens_out_ratio_p50"] - 0.08 ) &gt; 1e-6:         failures.append( "</m>
… [73 more display lines; full output is 16590 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --query="teleport pagerank" --top-k=5`

*Raw BM25 ranking (debug lens; --for is the real verb).*

`````
<!-- routed: subtoken+body BM25 (-for's default) — no strong name hit; broad query, plain rg may also win -->
<!-- ripwire v1 t=fn|method|cls|struct|iface|var|sec|macro(#define;degraded:body-is-replacement-text,edges-cross-expansion) p=path layer=arch-layer(opt) n=name id=canonical(path::scope::name,when-scoped) k=rank c=call amb=ambiguous-calls(read-source) overloads=N-same-name-defs-merged-into-this-row(absent-if-1;shown=counts-them-individually,so-rows+sum(overloads-1)=shown) prov=scip(precise;else name-based) hdr:unresolved=call-name-defined-only-in-a-lang-incompatible-file (edges heuristic) r:est_tokens=hdr-copy(none-if-stable) -->
<!-- r:root=crawl-root-every-p=-is-relative-to(single-root-only;absent=>p=is-the-raw-ingest-path) -->
<!-- files=1304 symbols=11348 edges=13926 shown=5 est_tokens=777 ambiguous=5517 unresolved=3202 precise=3 skipped_oversize=15 unindexed="jsonl:25,txt:22,scm:16,tsv:16,lock:6,xml:4" unindexed_exts=17 order=important-first -->
<r root="." est_tokens="777">
<f p="src/main.cpp">
<s t="fn" n="churnRankedGraph" amb="4" k="13.8620">
<c n="resolveSinceScope"/>
<c n="churnTeleport"/>
<c n="churnTeleportWorkspace"/>
<c n="churnDecayTeleport"/>
<c n="churnDecayTeleportWorkspace"/>
<c n="churnWindowStamp"/>
<c n="rankGraphTeleport"/>
<c n="push_back"/>
<c n="push_back"/>
<c n="churnDecayWindowLabel"/>
<c n="empty"/>
<c n="empty"/>
</s>
<s t="cls" n="ChurnRanking" id="./src/main.cpp::ChurnRanking::ChurnRanking" k="11.3793">
</s>
</f>
<f p="src/gitmine.h">
<s t="fn" n="churnPriorFromFreq" id="./src/gitmine.h::rw::churnPriorFromFreq" amb="1" k="12.4783">
<c n="DEGRADED_PATH_ALERT"/>
<c n="DEGRADED_PATH_ALERT"/>
<c n="size"/>
</s>
</f>
… [17 more display lines; full output is 2039 bytes on 1 raw line(s)]
`````


---

# zoom the detail ladder

## `./build/ripwire . --for="pagerank power iteration" --detail=2`

*Importance-weighted detail: FULL bodies for top-2, signatures for the rest.*

`````
<ctx task="pagerank power iteration" route=" [routed: subtoken+body BM25 (--for&apos;s default) — no strong name hit, multi-word conceptual query]" root=".">
<!-- ripwire lens for "pagerank power iteration" [doc mentions: 4 docs discussing 3 top-ranked symbols surfaced]: reusable building blocks + quality facts for what you're about to touch (cx=complexity ccx=cognitive in=reuse-count churn=recent-commits amp=change-amplification clone=1(duplicated) tested=1) — prefer composing/reusing these; watch the high-churn/high-amp/cloned ones -->
<!-- root= is the crawl root; p= below is RELATIVE to it (single-root only; absent => p= is ingest's own path, unchanged). est_tokens="4559" -->
<sigs capped="1">
<f p="scripts/optremarks.py">
<d l="40" n="HOT_FILES" cx="0" ccx="0" in="0" churn="3" amp="37">HOT_FILES = ( &quot;src/pagerank.cpp&quot;, # the power-iteration loop — G2&apos;s no-allocation scope &quot;src/infra/radixSort.h&quot;, # LSD radix entry points &quot;src/infra/radixSort…</d>
</f>
<f p="src/prconverge.h">
<d l="51" n="RankDisclosure" id="./src/prconverge.h::RankDisclosure::RankDisclosure" cx="0" ccx="0" in="0" churn="2" amp="17">
<doc>What a ranked document discloses about the power iteration that ordered it. `isPageRank == false…</doc>struct RankDisclosure</d>
<d l="73" n="renderDisclosure" id="./src/prconverge.h::rw::renderDisclosure" cx="12" ccx="15" in="10" churn="2" amp="27">
<doc>Render one form of the disclosure. Empty string whenever there is nothing to say — no power it…</doc>inline std::string renderDisclosure( const RankDisclosure&amp; d, DiscloseAs as )</d>
</f>
<f p="src/graph.h">
<d l="2103" n="RankedGraph" id="./src/graph.h::RankedGraph::RankedGraph" cx="0" ccx="0" in="0" churn="29" amp="106">
<doc>What a rank call hands back: the vector, and the power iteration&apos;s own account of itself. Struct…</doc>struct RankedGraph</d>
<d l="2112" n="rankGraphTeleport" id="./src/graph.h::rw::rankGraphTeleport" cx="5" ccx="8" in="6" churn="29" amp="112">inline RankedGraph rankGraphTeleport( const Graph&amp; g, const std::vector&lt;float&gt;&amp; p, float alpha = 0.85f )</d>
<d l="2178" n="hits" id="./src/graph.h::rw::hits" cx="9" ccx="16" in="1" churn="29" amp="107">inline std::pair&lt;std::vector&lt;float&gt;, std::vector&lt;float&gt;&gt; hits( const Graph&amp; g, float tol = 1e-6f…</d>
<d l="2489" n="anchoredLexicalRank" id="./src/graph.h::rw::anchoredLexicalRank" cx="10" ccx="10" in="4" churn="29" amp="110">inline std::vector&lt;float&gt; anchoredLexicalRank( const Graph&amp; g, const std::vector&lt;float&gt;&amp; lex )</d>
</f>
<f p="src/pagerank.h">
<d l="11" n="PageRankConfig" id="./src/pagerank.h::PageRankConfig::PageRankConfig" cx="0" ccx="0" in="0" churn="6" amp="20">struct PageRankConfig</d>
<d l="31" n="PageRankRun" id="./src/pagerank.h::PageRankRun::PageRankRun" cx="0" ccx="0" in="0" churn="6" amp="20">struct PageRankRun</d>
</f>
<f p="src/pagerank.cpp">
<d l="54" n="testIterationCeiling" cx="7" ccx="9" in="1" churn="7" amp="21">std::uint32_t testIterationCeiling() noexcept</d>
<d l="95" n="pageRankDouble" id="./src/pagerank.cpp::rw::pageRankDouble" cx="19" ccx="34" in="1" churn="7" amp="21">PageRankRun pageRankDouble( const sparseCsr&lt;float&gt;&amp; inEdges, std::span&lt;const double&gt; weightedOutDegree, std::span&lt;const double&gt; teleport, std::span&lt;double&gt;  … [line truncated: 11 more bytes on this line]
</f>
<f p="src/main.cpp">
<d l="12504" n="churnRankedGraph" cx="13" ccx="18" in="1" churn="141" amp="242">inline ChurnRanking churnRankedGraph( const MainDispatch&amp; d )</d>
… [125 more display lines; full output is 13493 bytes on 86 raw line(s)]
`````

## `./build/ripwire . --pack-signatures --top-k=10`

*Body-elided decl skeletons — recounted on this corpus. Measured as element bytes: the <d> signature+doc elements --pack-signatures emits, against the SAME symbols' full <b> bodies from --expand, with the CORPUS-ROOT PREFIX SUBTRACTED FROM BOTH SIDES. That subtraction is the whole methodology and the figure is meaningless without it: the root repeats inside every element's id= and p=, it is not what this verb elides, and counting it makes the headline a function of how deep the checkout happens to sit on disk — on one corpus, three spellings of the same root read 18.6 points apart before the subtraction and agree exactly after it. Root-neutralised on THIS repo: 86.5% fewer bytes at top-10, 81.4% at top-50, 81.6% at top-100 (V1, 2026-08-15: --expand's <b> bodies now carry sibs=/inc= file-context attributes — see docs/COMMANDS.md's --expand entry — which grows the body side of this ratio and moved the figure up from 70.0/61.0/63.8). top-50 is the number to quote, because the sigs payload is top-50 regardless of --top-k and is therefore what THIS command emits. A single small/trivial body can still invert it (signature+doc bigger than the body), like the --format=columnar sibling below. test/showcasecapturecheck.sh (C) re-derives all three from this repo every run, in the same quantity, and fails if the caption and the recount drift apart.*

`````
<ctx>
<!-- ripwire v1 t=fn|method|cls|struct|iface|var|sec|macro(#define;degraded:body-is-replacement-text,edges-cross-expansion) p=path layer=arch-layer(opt) n=name id=canonical(path::scope::name,when-scoped) k=rank c=call amb=ambiguous-calls(read-source) overloads=N-same-name-defs-merged-into-this-row(absent-if-1;shown=counts-them-individually,so-rows+sum(overloads-1)=shown) prov=scip(precise;else name-based) hdr:unresolved=call-name-defined-only-in-a-lang-incompatible-file (edges heuristic) r:est_tokens=hdr-copy(none-if-stable) -->
<!-- r:root=crawl-root-every-p=-is-relative-to(single-root-only;absent=>p=is-the-raw-ingest-path) -->
<!-- pr_iters=pagerank-power-iterations(stop:L1-residual-below-tol,else-ceiling) pr_converged=0-only-when-ceiling-hit-first(absent=converged;no-such-attr=not-pagerank-ordered) -->
<!-- files=1304 symbols=11348 edges=13926 shown=10 est_tokens=4366 ambiguous=5517 unresolved=3202 precise=3 skipped_oversize=15 unindexed="jsonl:25,txt:22,scm:16,tsv:16,lock:6,xml:4" unindexed_exts=17 order=important-first -->
<r root="." est_tokens="4366" pr_iters="32">
<f p="src/infra/svector.h" layer="infra">
<s t="method" n="size" id="./src/infra/svector.h::svector::size" k="0.0165">
</s>
<s t="method" n="buf" id="./src/infra/svector.h::svector::buf" overloads="2" k="0.0084">
</s>
<s t="method" n="push_back" id="./src/infra/svector.h::svector::push_back" overloads="2" amb="2" k="0.0071">
<c n="buf"/>
<c n="buf"/>
<c n="grow"/>
</s>
<s t="method" n="grow" id="./src/infra/svector.h::svector::grow" amb="1" k="0.0049">
<c n="isSpilled"/>
<c n="buf"/>
<c n="buf"/>
<c n="moveRange"/>
<c n="maxSize"/>
</s>
</f>
<f p="src/notes.h">
<s t="method" n="empty" id="./src/notes.h::NoteIndex::empty" k="0.0081">
</s>
</f>
<f p="src/scipoverlay.h">
<s t="method" n="empty" id="./src/scipoverlay.h::ScipOverlay::empty" k="0.0079">
… [126 more display lines; full output is 10912 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --outline=rankGraphTeleport --top-k=0`

*Control-flow skeleton of one symbol, payload-only via the new --top-k=0.*

`````
<ctx root="."><outline><o t="fn" l="2112" p="src/graph.h" n="rankGraphTeleport"><![CDATA[inline RankedGraph rankGraphTeleport( const Graph& g, const std::vector<float>& p, float alpha = 0.85f )
{
    PROFILE_SCOPE_DESCRIBE( "rankGraph: PageRank (power iteration)" );
    const std::vector<float> pw = biasPrior( g, p );
    const std::size_t N = pw.size();
    std::vector<double> teleport( pw.begin(), pw.end() );
    std::vector<double> rankDouble( N, 0.0 );
    PageRankRun         run{};   // an N == 0 graph never enters the kernel: { 0, converged } — see PageRankRun
    if( N )
    {
  ...
    }
    std::vector<float> r( N, 0.f );
    std::transform( rankDouble.begin(), rankDouble.end(), r.begin(), []( double value ) { return float( value ); } );
    return { std::move( r ), run.iterationCount, run.hasConverged };
}
]]></o></outline></ctx>
`````

## `./build/ripwire . --outline=rankGraphTeleport:1-10 --top-k=0`

*CHANGED: a line range on --outline is now STRIPPED with a stderr note (it used to refuse).*

`````
<ctx root="."><outline><o t="fn" l="2112" p="src/graph.h" n="rankGraphTeleport"><![CDATA[inline RankedGraph rankGraphTeleport( const Graph& g, const std::vector<float>& p, float alpha = 0.85f )
{
    PROFILE_SCOPE_DESCRIBE( "rankGraph: PageRank (power iteration)" );
    const std::vector<float> pw = biasPrior( g, p );
    const std::size_t N = pw.size();
    std::vector<double> teleport( pw.begin(), pw.end() );
    std::vector<double> rankDouble( N, 0.0 );
    PageRankRun         run{};   // an N == 0 graph never enters the kernel: { 0, converged } — see PageRankRun
    if( N )
    {
  ...
    }
    std::vector<float> r( N, 0.f );
    std::transform( rankDouble.begin(), rankDouble.end(), r.begin(), []( double value ) { return float( value ); } );
    return { std::move( r ), run.iterationCount, run.hasConverged };
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
<ctx root=".">
<bodies shown="1" total="1" capped="0">
<b t="fn" l="2112" p="src/graph.h" n="rankGraphTeleport" sibs="Graph,langCompatible,namespaceCompatible,kCommonNameMul,kCommonNameDefThreshold,kPrivateNameMul,kSpecificNameMul,kSpecificMinLen,kSpecificMinWords,wordCount,weight,decodeJniName,splitSegments,isTemplateSegment,pathsMatch,methodsCompatibl … [line truncated: 570 more bytes on this line]
<![CDATA[inline RankedGraph rankGraphTeleport( const Graph& g, const std::vector<float>& p, float alpha = 0.85f )
{
    PROFILE_SCOPE_DESCRIBE( "rankGraph: PageRank (power iteration)" );
    const std::vector<float> pw = biasPrior( g, p );
    const std::size_t N = pw.size();
    std::vector<double> teleport( pw.begin(), pw.end() );
    std::vector<double> rankDouble( N, 0.0 );
    PageRankRun         run{};   // an N == 0 graph never enters the kernel: { 0, converged } — see PageRankRun
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
        run = pageRankDouble( g.inEdges, g.wOutDeg, teleport, rankDouble, PageRankConfig{ .alpha = double( alpha ) } );
    }
    std::vector<float> r( N, 0.f );
    std::transform( rankDouble.begin(), rankDouble.end(), r.begin(), []( double value ) { return float( value ); } );
    return { std::move( r ), run.iterationCount, run.hasConverged };
}]]><calls total="9"><c n="biasPrior" l="2075">inline std::vector&lt;float&gt; biasPrior( const Graph&amp; g, const std::vector&lt;float&gt;&amp; p )</c><c n="PROFILE_SCOPE_DESCRIBE" l="1322">#define PROFILE_SCOPE_DESCRIBE( desc )</c><c n="PROFILE_SCOPE_DESCRIBE" l="1336">#define PROFILE_SCOPE_DESCR … [line truncated: 535 more bytes on this line]
`````

## `./build/ripwire . --expand=rankGraphTeleport:1-12 --top-k=0`

*Body SLICE: lines 1..12 of the symbol's own body, with lines="lo-hi/total" marking it partial.*

`````
<ctx root=".">
<bodies shown="1" total="1" capped="0">
<b t="fn" l="2112" p="src/graph.h" n="rankGraphTeleport" lines="1-12/29" sibs="Graph,langCompatible,namespaceCompatible,kCommonNameMul,kCommonNameDefThreshold,kPrivateNameMul,kSpecificNameMul,kSpecificMinLen,kSpecificMinWords,wordCount,weight,decodeJniName,splitSegments,isTemplateSegment,pathsMatch, … [line truncated: 586 more bytes on this line]
<![CDATA[inline RankedGraph rankGraphTeleport( const Graph& g, const std::vector<float>& p, float alpha = 0.85f )
{
    PROFILE_SCOPE_DESCRIBE( "rankGraph: PageRank (power iteration)" );
    const std::vector<float> pw = biasPrior( g, p );
    const std::size_t N = pw.size();
    std::vector<double> teleport( pw.begin(), pw.end() );
    std::vector<double> rankDouble( N, 0.0 );
    PageRankRun         run{};   // an N == 0 graph never enters the kernel: { 0, converged } — see PageRankRun
    if( N )
    {
        double teleportMass = 0.0;
        for( const double value : teleport )]]><calls total="9"><c n="biasPrior" l="2075">inline std::vector&lt;float&gt; biasPrior( const Graph&amp; g, const std::vector&lt;float&gt;&amp; p )</c><c n="PROFILE_SCOPE_DESCRIBE" l="1322">#define PROFILE_SCOPE_DESCRIBE( desc )</c><c n="PROFILE_SCOPE_DES … [line truncated: 578 more bytes on this line]
`````

## `./build/ripwire . --expand=compressBody --top-k=0 --compress`

*Comments stripped + blank runs collapsed — compressBody is the function that implements --compress itself, chosen because it is comment-heavy enough to show a real reduction (the previously captioned symbol had no comments or blank runs, so before/after were byte-identical under a caption promising a difference).*

`````
<ctx root=".">
<bodies shown="1" total="1" capped="0">
<b t="fn" l="2250" p="src/serialize.h" n="compressBody" sibs="xmlSafeByte,xmlScrubIsLossy,xmlControlCharRef,escapeXml,xmlCommentText,ctxRootOpen,ctxRootJsonScrubKeys,appendCdataSafe,XmlWriter,XmlWriter,XmlWriter,operator=,write,flush,hadWriteError,kCap,appendOneNote,appendOneNote,renderNoteChildren, … [line truncated: 689 more bytes on this line]
<![CDATA[inline std::string compressBody( std::string_view src )
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
… [168 more display lines; full output is 5902 bytes on 195 raw line(s)]
`````

## `./build/ripwire . --expand=readAckRecords --top-k=0 --no-redact`

*--no-redact: emit bodies verbatim (credential redaction is on by default).*

`````
<ctx root=".">
<bodies shown="1" total="1" capped="0">
<b t="fn" l="2912" p="src/quality.h" n="readAckRecords" sibs="kBaselineFile,kMinCloneTokens,kCcxBar,kLocBar,kNestBar,kParamBar,kShortHorizonDays,kShortHorizonMinCommits,kReusedHelperMinFanin,kMinorCcxDelta,kMinorLocDelta,kMinorParamDelta,kAcksFile,rootQualifiedSidecar,baselinePath,acksPath,insertScr … [line truncated: 688 more bytes on this line]
<![CDATA[inline gtl::btree_map<std::string, AckRecord> readAckRecords( const std::string& path )
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
… [19 more display lines; full output is 3797 bytes on 46 raw line(s)]
`````

## `./build/ripwire . --pack-top-n=3 --top-k=0`

*Pack the top-3 ranked symbols' full bodies (deprecated verb; see stderr).*

`````
<ctx root="."><src p="./src/infra/svector.h"><![CDATA[#pragma once

// svector.h — rw::svector: a small-vector with N INLINE slots that spills to the heap only past N.
// 16 bytes at <uint32,2>, with a BRANCH-FREE size(). Both, not one or the other.
//
// ── THE DESIGN, AND WHY IT IS THIS ONE ───────────────────────────────────────────────────────────────
// The shape the host tree leans on hardest is `Map<K, svector<V,N>>` — many tiny id-lists (byName /
// canonByName / shard maps, and ~100 more structures after the conversion wave): WRITE-ONCE during the
// parse/merge, then READ-HOT during resolve.
//
// Three things matter for that shape, and the layout below gets all three:
//   • no per-list malloc — the N small lists that would each allocate are inline;
//   • a BRANCH-FREE size() — `return sz_`, because the size lives in its own field;
//   • 16 BYTES per instance — because `inl_` and `heap_` are never both live, so they share storage.
//
// The union is the whole trick. The previous revision of this file paid 8 extra bytes (24 B) for the
// explicit size field, on the reasoning that a branch-free size() was worth it. That was a false
// choice: union the inline array with the heap pointer and the struct reaches 16 B — ankerl's size —
// while the size stays in its own field and size() stays branch-free.
//
// THE TRADE THAT REMAINS, stated honestly. At 16 bytes you can have:
//   • ankerl::svector's 3 inline slots, with a size() that branches on is_direct() (and, once spilled,
//     dereferences into the heap block to read the size — a dependent load, not just a branch); or
//   • this type's 2 inline slots, with size() branch-free.
// The measurement chose the second. See bench/SVECTORAB.md; the short version is below.
//
// ── WHAT THE MEASUREMENT ACTUALLY SAID (bench/SVECTORAB.md, hardware counters + working-set sweep) ────
// At 200 000 distinct names the profile is memory-bound (IPC 0.70, L1D-MPKI 225, LLC-MPKI 84.9) and this
// layout beats the old 24-byte one by 11.7% on the size-hot loop — 39x that column's 0.3% noise floor.
// Two mechanisms, separable because this type differs from the old one ONLY in size and from ankerl ONLY
… [1209 more lines, 65727 bytes total]
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
<!-- ripwire v1 t=fn|method|cls|struct|iface|var|sec|macro(#define;degraded:body-is-replacement-text,edges-cross-expansion) p=path layer=arch-layer(opt) n=name id=canonical(path::scope::name,when-scoped) k=rank c=call amb=ambiguous-calls(read-source) overloads=N-same-name-defs-merged-into-this-row(absent-if-1;shown=counts-them-individually,so-rows+sum(overloads-1)=shown) prov=scip(precise;else name-based) hdr:unresolved=call-name-defined-only-in-a-lang-incompatible-file (edges heuristic) r:est_tokens=hdr-copy(none-if-stable) -->
<!-- r:root=crawl-root-every-p=-is-relative-to(single-root-only;absent=>p=is-the-raw-ingest-path) -->
<!-- metrics: in=fan-in out=fan-out cx=cyclomatic ccx=cognitive loc=lines params=count nest=MAX-depth humps=regions-reaching-the-nesting-bar deep=lines-inside-them(floor,see deep_floor) (humps/deep are the PROFILE nest= cannot give: nest= is a max, so one deep line and a body that is deep throughout report the same number; deep/loc is the fraction. Both absent exactly when nest<bar — not-deep, never a hidden 0. deep counts LINES and humps counts REGIONS, and two regions can share a line, so deep BELOW humps is legal: a one-line if/else at the bar is 2 regions on 1 line) locals=local-var-decl-count(floor,C/C++-only,see locals_floor) ppalt=preproc-alternative-branches-in-body(#else/#elif; metrics sum ALL branches, no single build compiles them all) ev=essential-cx(McCabe: 1=fully structured, 2+=jumps block extract-method; absent on a cx row means exactly 1; floor per ev_floor — noreturn calls/macro-hidden exits unseen; not counted: &&/||, Rust ? and yield/await/defer, hence Bash carries no ev) ev_why=which-jumps-raised-it tag:count cbo=coupling lcom4=cohesion amp=change-amplification tested=1 role=hub(fan-in 8+; uses spells role call|macro|read|write|import|extends). Absent=N/A, never 0. -->
<!-- pr_iters=pagerank-power-iterations(stop:L1-residual-below-tol,else-ceiling) pr_converged=0-only-when-ceiling-hit-first(absent=converged;no-such-attr=not-pagerank-ordered) -->
<!-- files=1304 symbols=11348 edges=13926 shown=10 est_tokens=1782 ambiguous=5517 unresolved=3202 precise=3 skipped_oversize=15 unindexed="jsonl:25,txt:22,scm:16,tsv:16,lock:6,xml:4" unindexed_exts=17 order=important-first -->
<r root="." est_tokens="1782" pr_iters="32">
<f p="src/infra/svector.h" layer="infra">
<s t="method" n="size" id="./src/infra/svector.h::svector::size" in="533" out="0" cx="1" ccx="0" role="hub" loc="1" params="0" nest="0" locals="0" locals_floor="1" cbo="0" amp="556" tested="1" k="0.0165">
</s>
<s t="method" n="buf" id="./src/infra/svector.h::svector::buf" overloads="2" in="29" out="0" cx="2" ccx="1" role="hub" loc="1" params="0" nest="1" locals="0" locals_floor="1" cbo="0" amp="52" tested="1" k="0.0084">
</s>
<s t="method" n="push_back" id="./src/infra/svector.h::svector::push_back" overloads="2" in="469" out="3" cx="2" ccx="1" role="hub" loc="5" params="1" nest="1" locals="1" locals_floor="1" cbo="3" amp="492" tested="1" amb="2" k="0.0071" ev="2" ev_floor="1" ev_why="guard-return:1">
<c n="buf"/>
<c n="buf"/>
<c n="grow"/>
</s>
<s t="method" n="grow" id="./src/infra/svector.h::svector::grow" in="3" out="5" cx="4" ccx="3" loc="14" params="1" nest="1" locals="4" locals_floor="1" cbo="5" amp="26" tested="1" amb="1" k="0.0049">
<c n="isSpilled"/>
<c n="buf"/>
<c n="buf"/>
<c n="moveRange"/>
<c n="maxSize"/>
</s>
</f>
<f p="src/notes.h">
<s t="method" n="empty" id="./src/notes.h::NoteIndex::empty" in="547" out="0" cx="1" ccx="0" role="hub" loc="1" params="0" nest="0" locals="0" locals_floor="1" cbo="0" amp="581" tested="1" k="0.0081">
</s>
</f>
<f p="src/scipoverlay.h">
<s t="method" n="empty" id="./src/scipoverlay.h::ScipOverlay::empty" in="542" out="0" cx="1" ccx="0" role="hub" loc="1" params="0" nest="0" locals="0" locals_floor="1" cbo="0" amp="542" tested="1" k="0.0079">
… [19 more display lines; full output is 4424 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --deps`

*File->file dependency graph (god-files, cycles).*

`````
<!-- ripwire deps: file-to-file #include/import view, heaviest transitive cone first. files= (root) = files with at least one dependency edge (this listing's own denominator); health files= = the whole indexed corpus; health dep_files= = the dependency-CAPABLE subset of it (the ccd/acd/nccd denominator). raise the default cap with limit=N (offset=M pages). -->
<deps files="303" shown="40" capped="1" root=".">
<health files="1304" dep_files="608" ccd="3230" acd="5.3" nccd="0.64" shape="horizontal"/>
<godfiles total="214" shown="12" capped="1">
<f p="src/model.h" afferent="70"/>
<f p="src/infra/Diagnostics.h" afferent="43"/>
<f p="src/serialize.h" afferent="31"/>
<f p="src/graph.h" afferent="28"/>
<f p="src/ingest.h" afferent="21"/>
<f p="src/arch.h" afferent="19"/>
<f p="src/infra/jsonesc.h" afferent="18"/>
<f p="src/quality.h" afferent="16"/>
<f p="src/graphlegend.h" afferent="12"/>
<f p="src/infra/hashutil.h" afferent="12"/>
<f p="src/pageview.h" afferent="12"/>
<f p="src/docparse.h" afferent="11"/>
</godfiles>
<stabledeps violations="17">
<v from="src/mcp.h" to="src/mcpverbs.h" gap="0.38"/>
<v from="src/gitstamp.h" to="src/quality.h" gap="0.32"/>
<v from="src/infra/profileScope.h" to="src/infra/profilePmc.h" gap="0.25"/>
<v from="src/infra/sortutil.h" to="src/infra/radixSort.h" gap="0.25"/>
<v from="test/cyclecutfix/b.h" to="test/cyclecutfix/c.h" gap="0.25"/>
<v from="test/cyclecutfix/c.h" to="test/cyclecutfix/a.h" gap="0.25"/>
<v from="src/serialize.h" to="src/notes.h" gap="0.22"/>
<v from="src/mcpedit.h" to="src/mcpindex.h" gap="0.21"/>
<v from="src/partition.h" to="src/packtask.h" gap="0.16"/>
<v from="src/model.h" to="src/smallvec.h" gap="0.15"/>
<v from="src/situ.h" to="src/prcontext.h" gap="0.14"/>
<v from="src/ownersview.h" to="src/gitmine.h" gap="0.11"/>
… [757 more display lines; full output is 18667 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --hotspots`

*Complexity x recent git churn (maintenance pain).*

`````
<!-- ripwire hotspots: maintenance-pain = complexity × recent churn (window=12mo). churn=commits touching the file; ccx=Σ cognitive complexity; score=churn×ccx; top=worst function. files= is the DENOMINATOR ranked= is drawn from, and a hotspot needs both factors nonzero, so ranked= + unranked_no_churn= + unranked_no_complexity= = files= exactly. unranked_no_complexity= is a file with commits but no function or method to score (a pure declaration header, markdown, config). unranked_no_churn= is a file no in-window commit was attributed to — and it CONFLATES two cases this verb cannot tell apart: a genuinely quiet file, and one whose path the git-to-index join never bound (a rename, an exclusion, or a spelling the join could not match), which scores zero for a reason that is not about the file. Treat it as an upper bound on quietness, not a measure of it. raise the default cap with limit=N (offset=M pages) -->
<!-- at= is the git commit these numbers were computed at; a trailing +dirty means the working tree differed from that commit, so the numbers describe the tree, not the commit -->
<!-- root= on this element is the crawl root every p= below is RELATIVE to (single-root runs only; absent => p= is the path ingest itself used, unchanged). -->
<hotspots window="12mo" files="1304" ranked="331" unranked_no_churn="0" unranked_no_complexity="973" shown="40" capped="1" root="." at="700e51d49">
<f p="src/main.cpp" churn="141" ccx="4230" score="596430" top="main" top_ccx="390" top_l="14052"/>
<f p="src/ingest.cpp" churn="93" ccx="4071" score="378603" top="ingest" top_ccx="722" top_l="9910"/>
<f p="src/serialize.h" churn="41" ccx="1676" score="68716" top="packSignatures" top_ccx="200" top_l="2647"/>
<f p="src/quality.h" churn="60" ccx="769" score="46140" top="computeDelta" top_ccx="236" top_l="3230"/>
<f p="src/graph.h" churn="29" ccx="1528" score="44312" top="buildGraph" top_ccx="761" top_l="717"/>
<f p="src/cli.h" churn="86" ccx="419" score="36034" top="parseArgs" top_ccx="187" top_l="3276"/>
<f p="src/mcpverbs.h" churn="32" ccx="790" score="25280" top="runBatchSub" top_ccx="100" top_l="3317"/>
<f p="src/mcp.h" churn="22" ccx="487" score="10714" top="dispatchMcpLine" top_ccx="427" top_l="499"/>
<f p="src/search.h" churn="19" ccx="557" score="10583" top="grepCollect" top_ccx="49" top_l="1384"/>
<f p="src/lexical.h" churn="19" ccx="527" score="10013" top="lexicalScoresTiered" top_ccx="366" top_l="116"/>
<f p="src/layout.h" churn="12" ccx="699" score="8388" top="writeLayout" top_ccx="39" top_l="2522"/>
<f p="src/gitmine.h" churn="11" ccx="568" score="6248" top="applyCoChangeBoost" top_ccx="93" top_l="2434"/>
<f p="src/docdrift.h" churn="11" ccx="560" score="6160" top="parseIntLiteral" top_ccx="34" top_l="381"/>
<f p="src/resolve.h" churn="10" ccx="517" score="5170" top="buildPreciseIncludeAdj" top_ccx="56" top_l="1070"/>
<f p="src/naminglens.h" churn="13" ccx="373" score="4849" top="checkScopeGroups" top_ccx="93" top_l="904"/>
<f p="src/clones.h" churn="16" ccx="282" score="4512" top="findClonesType3" top_ccx="115" top_l="608"/>
<f p="src/crossref.h" churn="9" ccx="420" score="3780" top="streamBlobs" top_ccx="43" top_l="463"/>
<f p="bench/agentloop/run_agentloop.py" churn="14" ccx="250" score="3500" top="main" top_ccx="40" top_l="1096"/>
<f p="src/packtask.h" churn="13" ccx="256" score="3328" top="packTaskBundleText" top_ccx="150" top_l="913"/>
<f p="src/mcpindex.h" churn="16" ccx="191" score="3056" top="getIndex" top_ccx="39" top_l="950"/>
<f p="src/skilleval.h" churn="9" ccx="313" score="2817" top="runEvalSkills" top_ccx="97" top_l="649"/>
<f p="src/eval.h" churn="9" ccx="302" score="2718" top="runEval" top_ccx="66" top_l="168"/>
<f p="src/arch.h" churn="10" ccx="262" score="2620" top="computeModuleMetrics" top_ccx="68" top_l="721"/>
<f p="src/model.h" churn="40" ccx="65" score="2600" top="shadowSuppressedSite" top_ccx="13" top_l="959"/>
<f p="src/lanes.h" churn="10" ccx="240" score="2400" top="warnCoincidingClaims" top_ccx="24" top_l="680"/>
<f p="src/lintrules.h" churn="8" ccx="279" score="2232" top="parseLintRuleFile" top_ccx="101" top_l="253"/>
… [15 more display lines; full output is 5565 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --clones`

*Token-normalized duplicate bodies.*

`````
<!-- ripwire clones: function bodies with similar normalized token streams (identifiers/literals normalized, so renamed copies match). type=2 exact/renamed (Type-1/2); type=3 gapped near-miss (an inserted/changed statement, similarity in [0.80,1.0)). Reuse don't reimplement; a fix to one likely belongs in all. groups= and type3= are the two GROUP-TYPE totals (each capped independently, so neither is the row count); total= is the true row total (groups + type3-group-count) and is ALWAYS present, paged or not; shown= is the number of group rows that follow this run. capped="1" means rows were dropped. exempt= on a group ⇒ every member is on a path the quality-delta verb's duplication kind deliberately ignores (fixture dirs / shell test-runners repeat boilerplate by convention) — a fact here, never a gate there; exempt_groups= counts them over ALL groups. gid= on a row is its CLONE COMPONENT: the Type-3 pass reports PAIRS, so three functions that are all near-copies of each other arrive as three rows of two; rows sharing a gid are one cluster, and clone_groups= counts the clusters (union-find over the pair graph, over ALL detected rows, not just the shown ones). dup_pct=duplicated-LOC/total-LOC as a percentage, where duplicated-LOC sums, per cluster, every member's loc EXCEPT the largest member's (one instance is the code you keep, the rest is the redundancy — so a 3-clone cluster counts its lines TWICE) and total-LOC is every function/method body the detector considered; dup_loc= and total_loc= are those two operands. counts_floor="1": the Type-3 pair list is capped upstream, so a dropped pair is a cluster left unmerged — clone_groups/dup_loc/dup_pct are floors, never totals. raise the default cap with limit=N (offset=M pages). -->
<!-- root= on this element is the crawl root every p= below is RELATIVE to (single-root runs only; absent => p= is the path ingest itself used, unchanged). -->
<clones groups="54" type3="253" total="307" exempt_groups="121" clone_groups="182" dup_loc="3504" total_loc="110463" dup_pct="3.2" counts_floor="1" shown="80" capped="1" root=".">
<group type="2" gid="157" tokens="207" n="4" exempt="shell-runner">
<f n="batch_sub" p="test/mcpclidiffcheck.sh:63"/>
<f n="batch_sub" p="test/mcptranchecheck.sh:55"/>
<f n="batch_sub" p="test/mcpw2fixcheck.sh:52"/>
<f n="batch_sub" p="test/mcpw3fixcheck.sh:51"/>
</group>
<group type="2" gid="174" tokens="149" n="3" exempt="shell-runner">
<f n="monotonic_check" p="test/pyimportprecisecheck.sh:89"/>
<f n="monotonic_check" p="test/rustimportprecisecheck.sh:124"/>
<f n="monotonic_check" p="test/tsimportprecisecheck.sh:88"/>
</group>
<group type="2" gid="34" tokens="142" n="2">
<f n="test_tier2_accept_big_quality_small_cost" p="bench/locbench/test_compare_gate.py:130"/>
<f n="test_tier2_reject_small_quality_big_cost" p="bench/locbench/test_compare_gate.py:143"/>
</group>
<group type="2" gid="137" tokens="126" n="2">
<f n="addWholeFileFn" p="test/cloneband_harness.cpp:64"/>
<f n="addWholeFileFn" p="test/type3clone_harness.cpp:47"/>
</group>
<group type="2" gid="59" tokens="118" n="2">
<f n="rankFiles" p="src/eval.h:53"/>
<f n="rankCandidates" p="src/skilleval.h:426"/>
</group>
<group type="2" gid="35" tokens="114" n="2">
<f n="timer" p="bench/representative_perfgate.sh:54"/>
<f n="run_once_ms" p="test/mergescoutcheck.sh:268"/>
</group>
… [308 more display lines; full output is 16995 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --cochange`

*Files that change together in git (hidden coupling).*

`````
<!-- ripwire cochange: file pairs that change together in git but share no transitive static dependency (surprising=1) = hidden coupling. together= is the number of commits in window= that touched BOTH files (3 or more, or the pair is not reported); deg= is that count over the commit count of the LESS-CHANGED of the two files, so 1.00 means the quieter file never changed without the other. conf_ab= is that same fraction over a='s OWN commit count and conf_ba= over b='s, which is the asymmetric form: conf_ab=1.00 means a never changed without b. deg= is by construction the larger of the two, and driver= names which side it came from ("a" or "b") — the file whose changes most reliably imply the other's, and therefore the one to look at first. driver= is OMITTED when the two directions are equal, because a tie is not a finding. recur= is how many of sub_windows= the pair actually co-changed in: the mined window is cut into that many equal-COMMIT-COUNT slices (not equal time — a calendar slice can hold 400 commits or 4), so recur=1 at any together= is one burst of activity and not a persistent coupling, which is the distinction a single window cannot make. sub_windows= is the denominator and is never omitted; it is smaller than the nominal 3 only when the window holds fewer commits than that. min_recur= appears when cochange-recur=K (the flag) filtered the rows, so a short list is explained rather than silent. window= is the mining window: the default 18 months, or the since=REV|DATE value when one resolved. surprising= is only defined where BOTH sides could carry a static dependency at all (the same dependency-capable predicate deps <health dep_files=> uses: source languages yes; sh, md, json, ruby and binary/unknown files no). A pair with a dep-incapable side keeps its row and carries dep_capable=0 instead, because for it "shares no static dependency" is vacuously true. raise the default cap with limit=N (offset=M pages) -->
<!-- at= is the git commit these numbers were computed at; a trailing +dirty means the working tree differed from that commit, so the numbers describe the tree, not the commit -->
<!-- root= on this element is the crawl root every p= below is RELATIVE to (single-root runs only; absent => p= is the path ingest itself used, unchanged). -->
<cochange pairs="449" window="18mo" sub_windows="3" shown="30" capped="1" root="." at="700e51d49">
<pair a="src/arch.h" b="src/clones.h" together="3" deg="1.00" conf_ab="1.00" conf_ba="0.30" driver="a" recur="2" surprising="1"/>
<pair a="bench/agentloop/analyze.py" b="bench/agentloop/run_agentloop.py" together="7" deg="0.88" conf_ab="0.88" conf_ba="0.64" driver="a" recur="3" surprising="1"/>
<pair a="src/ingest.cpp" b="src/workspace.h" together="6" deg="0.86" conf_ab="0.07" conf_ba="0.86" driver="b" recur="2" surprising="1"/>
<pair a="bench/bench_svector3.cpp" b="bench/bench_svector_wave.cpp" together="4" deg="0.80" conf_ab="0.80" conf_ba="0.80" recur="1" surprising="1"/>
<pair a="src/cli.h" b="src/recall.h" together="4" deg="0.80" conf_ab="0.05" conf_ba="0.80" driver="b" recur="2" surprising="1"/>
<pair a="src/cli.h" b="src/nonlocalstate.h" together="4" deg="0.67" conf_ab="0.05" conf_ba="0.67" driver="b" recur="2" surprising="1"/>
<pair a="present/deck5_ripwire_build.js" b="src/cli.h" together="23" deg="0.66" conf_ab="0.66" conf_ba="0.28" driver="a" recur="3" surprising="1"/>
<pair a="present/deck5_ripwire_build.js" b="src/main.cpp" together="23" deg="0.66" conf_ab="0.66" conf_ba="0.17" driver="a" recur="3" surprising="1"/>
<pair a="src/serialize.h" b="src/workspace.h" together="4" deg="0.57" conf_ab="0.11" conf_ba="0.57" driver="b" recur="2" surprising="1"/>
<pair a="src/infra/profileScope.h" b="src/infra/sparseCsr.h" together="4" deg="0.57" conf_ab="0.44" conf_ba="0.57" driver="b" recur="2" surprising="1"/>
<pair a="src/cli.h" b="src/workspace.h" together="4" deg="0.57" conf_ab="0.05" conf_ba="0.57" driver="b" recur="2" surprising="1"/>
<pair a="src/quality.h" b="src/workspace.h" together="4" deg="0.57" conf_ab="0.08" conf_ba="0.57" driver="b" recur="3" surprising="1"/>
<pair a="src/cli.h" b="src/serialize.h" together="19" deg="0.53" conf_ab="0.23" conf_ba="0.53" driver="b" recur="3" surprising="1"/>
<pair a="src/cli.h" b="src/mcp.h" together="8" deg="0.50" conf_ab="0.10" conf_ba="0.50" driver="b" recur="3" surprising="1"/>
<pair a="src/ingest.cpp" b="src/nonlocalstate.h" together="3" deg="0.50" conf_ab="0.04" conf_ba="0.50" driver="b" recur="1" surprising="1"/>
<pair a="src/ingest.cpp" b="src/naminglens.h" together="5" deg="0.45" conf_ab="0.06" conf_ba="0.45" driver="b" recur="3" surprising="1"/>
<pair a="src/ingest.cpp" b="src/mcp.h" together="7" deg="0.44" conf_ab="0.08" conf_ba="0.44" driver="b" recur="3" surprising="1"/>
<pair a="src/cli.h" b="src/graph.h" together="9" deg="0.43" conf_ab="0.11" conf_ba="0.43" driver="b" recur="3" surprising="1"/>
<pair a="src/cli.h" b="src/contextratio.h" together="3" deg="0.43" conf_ab="0.04" conf_ba="0.43" driver="b" recur="3" surprising="1"/>
<pair a="src/ingest.cpp" b="src/serialize.h" together="15" deg="0.42" conf_ab="0.18" conf_ba="0.42" driver="b" recur="3" surprising="1"/>
<pair a="src/graphlegend.h" b="src/ingest.cpp" together="6" deg="0.40" conf_ab="0.40" conf_ba="0.07" driver="a" recur="3" surprising="1"/>
<pair a="src/cli.h" b="src/graphlegend.h" together="6" deg="0.40" conf_ab="0.07" conf_ba="0.40" driver="b" recur="2" surprising="1"/>
<pair a="src/cli.h" b="src/clones.h" together="4" deg="0.40" conf_ab="0.05" conf_ba="0.40" driver="b" recur="3" surprising="1"/>
<pair a="src/cli.h" b="src/mcpindex.h" together="3" deg="0.38" conf_ab="0.04" conf_ba="0.38" driver="b" recur="2" surprising="1"/>
<pair a="src/cli.h" b="src/naminglens.h" together="4" deg="0.36" conf_ab="0.05" conf_ba="0.36" driver="b" recur="3" surprising="1"/>
<pair a="src/graph.h" b="src/graphlegend.h" together="5" deg="0.33" conf_ab="0.24" conf_ba="0.33" driver="b" recur="3" surprising="1"/>
<pair a="src/graphlegend.h" b="src/quality.h" together="5" deg="0.33" conf_ab="0.33" conf_ba="0.09" driver="a" recur="2" surprising="1"/>
<pair a="src/ingest.cpp" b="test/showcase_capture.py" together="7" deg="0.28" conf_ab="0.08" conf_ba="0.28" driver="b" recur="2" surprising="1"/>
<pair a="src/quality.h" b="src/serialize.h" together="10" deg="0.28" conf_ab="0.19" conf_ba="0.28" driver="b" recur="3" surprising="1"/>
<pair a="src/naminglens.h" b="src/quality.h" together="3" deg="0.27" conf_ab="0.27" conf_ba="0.06" driver="a" recur="3" surprising="1"/>
</cochange>
`````

## `./build/ripwire . --hotspots --since="2 weeks ago"`

*Hotspots scoped to RECENT churn (the regression lens).*

`````
<!-- ripwire hotspots: maintenance-pain = complexity × recent churn (window=2 weeks ago). churn=commits touching the file; ccx=Σ cognitive complexity; score=churn×ccx; top=worst function. files= is the DENOMINATOR ranked= is drawn from, and a hotspot needs both factors nonzero, so ranked= + unranked_no_churn= + unranked_no_complexity= = files= exactly. unranked_no_complexity= is a file with commits but no function or method to score (a pure declaration header, markdown, config). unranked_no_churn= is a file no in-window commit was attributed to — and it CONFLATES two cases this verb cannot tell apart: a genuinely quiet file, and one whose path the git-to-index join never bound (a rename, an exclusion, or a spelling the join could not match), which scores zero for a reason that is not about the file. Treat it as an upper bound on quietness, not a measure of it. raise the default cap with limit=N (offset=M pages) -->
<!-- at= is the git commit these numbers were computed at; a trailing +dirty means the working tree differed from that commit, so the numbers describe the tree, not the commit -->
<!-- root= on this element is the crawl root every p= below is RELATIVE to (single-root runs only; absent => p= is the path ingest itself used, unchanged). -->
<hotspots window="2 weeks ago" files="1304" ranked="213" unranked_no_churn="691" unranked_no_complexity="400" shown="40" capped="1" root="." at="700e51d49">
<f p="src/main.cpp" churn="97" ccx="4230" score="410310" top="main" top_ccx="390" top_l="14052"/>
<f p="src/ingest.cpp" churn="73" ccx="4071" score="297183" top="ingest" top_ccx="722" top_l="9910"/>
<f p="src/serialize.h" churn="33" ccx="1676" score="55308" top="packSignatures" top_ccx="200" top_l="2647"/>
<f p="src/quality.h" churn="48" ccx="769" score="36912" top="computeDelta" top_ccx="236" top_l="3230"/>
<f p="src/graph.h" churn="20" ccx="1528" score="30560" top="buildGraph" top_ccx="761" top_l="717"/>
<f p="src/cli.h" churn="51" ccx="419" score="21369" top="parseArgs" top_ccx="187" top_l="3276"/>
<f p="src/mcpverbs.h" churn="24" ccx="790" score="18960" top="runBatchSub" top_ccx="100" top_l="3317"/>
<f p="src/mcp.h" churn="14" ccx="487" score="6818" top="dispatchMcpLine" top_ccx="427" top_l="499"/>
<f p="src/search.h" churn="11" ccx="557" score="6127" top="grepCollect" top_ccx="49" top_l="1384"/>
<f p="src/lexical.h" churn="10" ccx="527" score="5270" top="lexicalScoresTiered" top_ccx="366" top_l="116"/>
<f p="src/layout.h" churn="5" ccx="699" score="3495" top="writeLayout" top_ccx="39" top_l="2522"/>
<f p="src/gitmine.h" churn="5" ccx="568" score="2840" top="applyCoChangeBoost" top_ccx="93" top_l="2434"/>
<f p="src/docdrift.h" churn="5" ccx="560" score="2800" top="parseIntLiteral" top_ccx="34" top_l="381"/>
<f p="src/naminglens.h" churn="7" ccx="373" score="2611" top="checkScopeGroups" top_ccx="93" top_l="904"/>
<f p="src/resolve.h" churn="5" ccx="517" score="2585" top="buildPreciseIncludeAdj" top_ccx="56" top_l="1070"/>
<f p="src/clones.h" churn="9" ccx="282" score="2538" top="findClonesType3" top_ccx="115" top_l="608"/>
<f p="bench/agentloop/run_agentloop.py" churn="9" ccx="250" score="2250" top="main" top_ccx="40" top_l="1096"/>
<f p="src/model.h" churn="32" ccx="65" score="2080" top="shadowSuppressedSite" top_ccx="13" top_l="959"/>
<f p="src/packtask.h" churn="8" ccx="256" score="2048" top="packTaskBundleText" top_ccx="150" top_l="913"/>
<f p="src/nonlocalstate.h" churn="7" ccx="252" score="1764" top="computeNonLocalState" top_ccx="78" top_l="700"/>
<f p="src/crossref.h" churn="4" ccx="420" score="1680" top="streamBlobs" top_ccx="43" top_l="463"/>
<f p="src/fieldaffinity.h" churn="5" ccx="276" score="1380" top="buildStructRow" top_ccx="59" top_l="730"/>
<f p="src/lanes.h" churn="5" ccx="240" score="1200" top="warnCoincidingClaims" top_ccx="24" top_l="680"/>
<f p="src/lintrules.h" churn="4" ccx="279" score="1116" top="parseLintRuleFile" top_ccx="101" top_l="253"/>
<f p="src/arch.h" churn="4" ccx="262" score="1048" top="computeModuleMetrics" top_ccx="68" top_l="721"/>
<f p="src/prcontext.h" churn="5" ccx="209" score="1045" top="writePrContext" top_ccx="142" top_l="698"/>
… [15 more display lines; full output is 5572 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --arch=test/archfix/rules.txt`

*Enforce layering rules (exit 2 on violation) — run against the repo's own test fixture rules.*

`````
<!-- ripwire arch: layering fitness function — edges that violate your declared rules (layer rules and regex path-rules). exit=2 if any NEW (un-baselined) violation. <metrics> = descriptive Martin Ca/Ce/I/A/D + reachability, never gates. Rules — layer substrings and regex path-rules alike — are matched against each file's ROOT-RELATIVE path (src/core/x.cpp), never the absolute or ./-prefixed spelling shown in from=/to=, so a rule means the same thing whatever directory the tree was checked out into. -->
<arch layers="2" rules="1" pathRules="0" violations="0" baselined="0" new_violations="0">
<metrics modules="264" typed_modules="93" zone_pain="74" zone_useless="1" zone_ok="18" zone_na="171" propagation_cost="0.009" note="Martin Ca/Ce/I/A/D + zone (main-sequence heuristic, no independent outcome-based validation — folklore, not proof) + reachability — directory-level estimate from na … [line truncated: 408 more bytes on this line]
<m path="." ca="0" ce="0" types="0" abstract="0" I="0.00" A="0.00" D="1.00" zone="n/a" reachable="1" isolated="1"/>
<m path="./.codex-plugin" ca="0" ce="0" types="0" abstract="0" I="0.00" A="0.00" D="1.00" zone="n/a" reachable="1" isolated="1"/>
<m path="./.github/workflows" ca="0" ce="0" types="0" abstract="0" I="0.00" A="0.00" D="1.00" zone="n/a" reachable="1" isolated="1"/>
<m path="./bench" ca="0" ce="1" types="20" abstract="2" I="1.00" A="0.10" D="0.10" zone="ok" reachable="1"/>
<m path="./bench/agentloop" ca="0" ce="0" types="0" abstract="0" I="0.00" A="0.00" D="1.00" zone="n/a" reachable="1" isolated="1"/>
<m path="./bench/agentloop/fixtures/grader" ca="0" ce="0" types="0" abstract="0" I="0.00" A="0.00" D="1.00" zone="n/a" reachable="1" isolated="1"/>
<m path="./bench/agentloop/results" ca="0" ce="0" types="0" abstract="0" I="0.00" A="0.00" D="1.00" zone="n/a" reachable="1" isolated="1"/>
<m path="./bench/cppbench" ca="0" ce="0" types="1" abstract="0" I="0.00" A="0.00" D="1.00" zone="pain" reachable="1" isolated="1"/>
<m path="./bench/cppbench/results" ca="0" ce="0" types="0" abstract="0" I="0.00" A="0.00" D="1.00" zone="n/a" reachable="1" isolated="1"/>
<m path="./bench/ensemblecal" ca="0" ce="0" types="0" abstract="0" I="0.00" A="0.00" D="1.00" zone="n/a" reachable="1" isolated="1"/>
<m path="./bench/fixround" ca="0" ce="0" types="0" abstract="0" I="0.00" A="0.00" D="1.00" zone="n/a" reachable="1" isolated="1"/>
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
… [239 more display lines; full output is 36818 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --lint`

*Built-in AST checks (c-cast, goto, unsafe-c-fn, ...).*

`````
<!-- ripwire lint: [AST]-only checks (descriptive facts, not gates). rule=the check; sev=user-rule severity; in=enclosing symbol NAME (the same spelling is a fan-in COUNT in for/pack-task/exemplar). A rule named atom-X is an atom of confusion (Gopstein, FSE 2017): a C-family shape that misleads READERS, C/C++/ObjC/CUDA only. Each rule is scanned under its OWN match budget, so no rule is ever starved by a noisier one. A rule that spends its whole budget carries capped="1" — its count= is then a FLOOR (that rule's raw captures reached the per-rule budget; only its own matches can cap it); findings_capped="1" on the root ⇒ at least one rule is a floor. Absent = nothing was capped and every count= is a total. raise the default cap with limit=N (offset=M pages). On the root, shown=/capped= are the ROW-COUNT pair (rows printed vs whether the DEFAULT payload byte-cap trimmed them, absent an explicit limit=) — a different fact from the per-rule capped="1" above, which is a MATCH-BUDGET floor on one rule's own count=; findings= is always the true total either way. A rule row's applicable="0" ⇒ NONE of its registered languages (the lint-catalog listing) are present in this corpus at all — its count="0" is structural inertness, never a measurement; the root's inert_rules=N tallies how many printed rows that is true for. lint-select=/lint-ignore=PREFIX[,...] narrow the printed rows to a family (e.g. cache-); the root then carries selected="K of N" plus the raw select=/ignore= you passed. Each rule row's own shown= is how many of THAT rule's rows fall inside the printed <f> window (the root's shown=/capped= trims a SORTED PREFIX of the combined findings, so a rule whose rows all sort past the cut carries shown="0" while its count= stays the true total — never confuse a capped-away rule with one that measured zero). -->
<lint findings="3263" shown="693" capped="1" findings_capped="1" root=".">
<rule name="c-style-cast" count="294" shown="107"/>
<rule name="goto" count="2" shown="1"/>
<rule name="do-while" count="3" shown="0"/>
<rule name="unsafe-c-fn" count="0" shown="0"/>
<rule name="weak-crypto" count="0" shown="0"/>
<rule name="redundant-parens" count="0" shown="0"/>
<rule name="suspicious-semicolon" count="0" shown="0"/>
<rule name="typedef-over-using" count="12" shown="0"/>
<rule name="magic-number" count="456" shown="296" capped="1"/>
<rule name="empty-catch" count="1" shown="0"/>
<rule name="self-assign" count="3" shown="0"/>
<rule name="large-function" count="205" shown="42"/>
<rule name="deep-nesting" count="205" shown="45"/>
<rule name="inconsistent-return" count="1" shown="0"/>
<rule name="unreachable-code" count="5" shown="0"/>
<rule name="naming-short" count="1013" shown="35"/>
<rule name="naming-wordy" count="72" shown="21"/>
<rule name="naming-series" count="273" shown="0"/>
<rule name="naming-underscore" count="0" shown="0"/>
<rule name="naming-case" count="48" shown="0"/>
<rule name="naming-predicate" count="0" shown="0"/>
<rule name="naming-setter" count="1" shown="0"/>
<rule name="naming-confusable" count="124" shown="14"/>
<rule name="naming-uninformative" count="0" shown="0"/>
<rule name="atom-comma-operator" count="1" shown="0"/>
<rule name="atom-embedded-crement" count="83" shown="17"/>
<rule name="atom-assign-as-value" count="36" shown="9"/>
<rule name="atom-nested-ternary" count="52" shown="9"/>
… [705 more display lines; full output is 68638 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --lint-rules=test/lintrulesfix/rules`

*User lint rules (YAML, ast-grep style) from a directory.*

`````
<!-- ripwire lint: [AST]-only checks (descriptive facts, not gates). rule=the check; sev=user-rule severity; in=enclosing symbol NAME (the same spelling is a fan-in COUNT in for/pack-task/exemplar). A rule named atom-X is an atom of confusion (Gopstein, FSE 2017): a C-family shape that misleads READERS, C/C++/ObjC/CUDA only. Each rule is scanned under its OWN match budget, so no rule is ever starved by a noisier one. A rule that spends its whole budget carries capped="1" — its count= is then a FLOOR (that rule's raw captures reached the per-rule budget; only its own matches can cap it); findings_capped="1" on the root ⇒ at least one rule is a floor. Absent = nothing was capped and every count= is a total. raise the default cap with limit=N (offset=M pages). On the root, shown=/capped= are the ROW-COUNT pair (rows printed vs whether the DEFAULT payload byte-cap trimmed them, absent an explicit limit=) — a different fact from the per-rule capped="1" above, which is a MATCH-BUDGET floor on one rule's own count=; findings= is always the true total either way. A rule row's applicable="0" ⇒ NONE of its registered languages (the lint-catalog listing) are present in this corpus at all — its count="0" is structural inertness, never a measurement; the root's inert_rules=N tallies how many printed rows that is true for. lint-select=/lint-ignore=PREFIX[,...] narrow the printed rows to a family (e.g. cache-); the root then carries selected="K of N" plus the raw select=/ignore= you passed. Each rule row's own shown= is how many of THAT rule's rows fall inside the printed <f> window (the root's shown=/capped= trims a SORTED PREFIX of the combined findings, so a rule whose rows all sort past the cut carries shown="0" while its count= stays the true total — never confuse a capped-away rule with one that measured zero). -->
<lint findings="5" shown="5" capped="0" root=".">
<rule name="broken-query" sev="error" count="0" shown="0"/>
<rule name="no-printf" sev="warn" count="5" shown="5"/>
<f rule="no-printf" sev="warn" p="test/coplintfix/position.cpp:41" in="demo">use LOG() instead of printf</f>
<f rule="no-printf" sev="warn" p="test/coplintfix/safe.cpp:15" in="safe_demo">use LOG() instead of printf</f>
<f rule="no-printf" sev="warn" p="test/coplintfix/safe.cpp:27" in="safe_demo">use LOG() instead of printf</f>
<f rule="no-printf" sev="warn" p="test/lintrulesfix/sample.cpp:8" in="greet">use LOG() instead of printf</f>
<f rule="no-printf" sev="warn" p="test/usesfix/store.cpp:24" in="run">use LOG() instead of printf</f>
</lint>
`````

stderr:

`````
ripwire: lint-rules: test/lintrulesfix/rules/malformed.yaml:5: expected 'key: value' — file skipped
[math degraded] lint-rules: malformed rule file skipped  (lintrules.h:270, auto rw::parseLintRuleFile(const std::string &, std::string_view, std::vector<LintRule> &)::(anonymous class)::operator()(std::size_t, const char *) const — logged once per site)
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
<!-- ripwire lint: [AST]-only checks (descriptive facts, not gates). rule=the check; sev=user-rule severity; in=enclosing symbol NAME (the same spelling is a fan-in COUNT in for/pack-task/exemplar). A rule named atom-X is an atom of confusion (Gopstein, FSE 2017): a C-family shape that misleads READERS, C/C++/ObjC/CUDA only. Each rule is scanned under its OWN match budget, so no rule is ever starved by a noisier one. A rule that spends its whole budget carries capped="1" — its count= is then a FLOOR (that rule's raw captures reached the per-rule budget; only its own matches can cap it); findings_capped="1" on the root ⇒ at least one rule is a floor. Absent = nothing was capped and every count= is a total. raise the default cap with limit=N (offset=M pages). On the root, shown=/capped= are the ROW-COUNT pair (rows printed vs whether the DEFAULT payload byte-cap trimmed them, absent an explicit limit=) — a different fact from the per-rule capped="1" above, which is a MATCH-BUDGET floor on one rule's own count=; findings= is always the true total either way. A rule row's applicable="0" ⇒ NONE of its registered languages (the lint-catalog listing) are present in this corpus at all — its count="0" is structural inertness, never a measurement; the root's inert_rules=N tallies how many printed rows that is true for. lint-select=/lint-ignore=PREFIX[,...] narrow the printed rows to a family (e.g. cache-); the root then carries selected="K of N" plus the raw select=/ignore= you passed. Each rule row's own shown= is how many of THAT rule's rows fall inside the printed <f> window (the root's shown=/capped= trims a SORTED PREFIX of the combined findings, so a rule whose rows all sort past the cut carries shown="0" while its count= stays the true total — never confuse a capped-away rule with one that measured zero). -->
<!-- with-profile: heat_* on a finding = MEASURED inclusive totals of the joined #PROF_TSV scope — the nearest PROFILE_SCOPE site at/above the finding inside its own enclosing symbol. Columns are whatever counter tier the profiled run armed; an ABSENT heat column was not measured, never zero. heat_joined= on the root counts annotated findings; 0 is honest (no finding sits inside a profiled scope), never an error. -->
<lint findings="1" shown="1" capped="0" heat_joined="1" root=".">
<rule name="c-style-cast" count="0" shown="0"/>
<rule name="goto" count="0" shown="0"/>
<rule name="do-while" count="0" shown="0"/>
<rule name="unsafe-c-fn" count="0" shown="0"/>
<rule name="weak-crypto" count="0" shown="0"/>
<rule name="redundant-parens" count="0" shown="0"/>
<rule name="suspicious-semicolon" count="0" shown="0"/>
<rule name="typedef-over-using" count="0" shown="0"/>
<rule name="magic-number" count="0" shown="0"/>
<rule name="empty-catch" count="0" shown="0"/>
<rule name="self-assign" count="0" shown="0"/>
<rule name="large-function" count="0" shown="0"/>
<rule name="deep-nesting" count="0" shown="0"/>
<rule name="inconsistent-return" count="0" shown="0"/>
<rule name="unreachable-code" count="0" shown="0"/>
<rule name="naming-short" count="0" shown="0"/>
<rule name="naming-wordy" count="0" shown="0"/>
<rule name="naming-series" count="0" shown="0"/>
<rule name="naming-underscore" count="0" shown="0"/>
<rule name="naming-case" count="0" shown="0"/>
<rule name="naming-predicate" count="0" shown="0"/>
<rule name="naming-setter" count="0" shown="0"/>
<rule name="naming-confusable" count="0" shown="0"/>
<rule name="naming-uninformative" count="0" shown="0"/>
<rule name="atom-comma-operator" count="0" shown="0"/>
<rule name="atom-embedded-crement" count="0" shown="0"/>
<rule name="atom-assign-as-value" count="0" shown="0"/>
… [14 more display lines; full output is 4531 bytes on 1 raw line(s)]
`````

The joined finding — past the display cut above, extracted so the join is visible:

`````
<f rule="cache-pointer-chase-loop" p="src/x.cpp:11" in="walk" heat_scope="walk: chase pass" heat_calls="12" heat_total_ms="48.500" heat_l1d_mpki="7.250">p = p-&gt;next</f>
`````

## `./build/ripwire . --communities`

*Cluster the call graph into cohesive modules.*

`````
<!-- ripwire communities: cohesive call-graph modules (Louvain); bridge=cross-module edges; isolated=call-graph-edgeless symbols; drill= names the verb that takes an id= from a row below. On each module row size= is its TRUE member count while shown=/capped= describe the member list printed here: this listing is fixed at the 5 top-ranked members and is NOT widened by limit=/offset= (those page the MODULE rows). capped=1 means members were dropped; drill= names the verb that pages the full member list of one module. raise the default cap with limit=N (offset=M pages). pr_iters=pagerank-power-iterations(stop:L1-residual-below-tol,else-ceiling) pr_converged=0-only-when-ceiling-hit-first(absent=converged;no-such-attr=not-pagerank-ordered) -->
<!-- root= on this element is the crawl root every p= below is RELATIVE to (single-root runs only; absent => p= is the path ingest itself used, unchanged). -->
<communities drill="--community=ID" modules="847" shown_modules="30" modules_capped="1" bridges="1206" shown_bridges="12" bridges_capped="1" isolated="6765" isolated_decl="1612" isolated_header="714" isolated_source="2243" isolated_doc="2196" connected_singletons="0" symbols="11348" pr_iters="32" ro … [line truncated: 7 more bytes on this line]
<community id="2530" size="560" dir="src" label="src::min@infra/fastmath.h:51:2347 [run,write,emit]" shown="5" capped="1">
<member t="method" n="empty" p="src/notes.h:396"/>
<member t="method" n="empty" p="src/scipoverlay.h:93"/>
<member t="method" n="clear" p="src/renamemine.h:225"/>
<member t="fn" n="min" p="src/infra/fastmath.h:51"/>
<member t="fn" n="escapeXml" p="src/serialize.h:122"/>
</community>
<community id="2554" size="336" dir="src" label="src::VERIFY@infra/Diagnostics.h:172:8901 [compute,apply,resolve]" shown="5" capped="1">
<member t="method" n="size" p="src/infra/svector.h:285"/>
<member t="fn" n="max" p="src/infra/fastmath.h:54"/>
<member t="macro" n="VERIFY" p="src/infra/Diagnostics.h:172"/>
<member t="method" n="end" p="src/infra/svector.h:270"/>
<member t="method" n="end" p="src/infra/svector.h:272"/>
</community>
<community id="2543" size="297" dir="src" label="src::PROFILE_SCOPE_DESCRIBE@infra/profileScope.h:1322:44988 [compute,add,split]" shown="5" capped="1">
<member t="method" n="push_back" p="src/infra/svector.h:326"/>
<member t="method" n="push_back" p="src/infra/svector.h:331"/>
<member t="method" n="reserve" p="src/infra/svector.h:294"/>
<member t="method" n="back" p="src/infra/svector.h:263"/>
<member t="method" n="back" p="src/infra/svector.h:264"/>
</community>
<community id="2521" size="300" dir="src" label="src::emplace@infra/svector.h:408:22477 [resolve,parse,compute]" shown="5" capped="1">
<member t="method" n="find" p="src/ingest.cpp:11306"/>
<member t="method" n="find" p="src/graph.h:2736"/>
<member t="method" n="empty" p="src/infra/svector.h:284"/>
<member t="method" n="find" p="src/notes.h:399"/>
<member t="fn" n="emplace_back" p="src/infra/svector.h:333"/>
… [187 more display lines; full output is 16486 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --zoom`

*Nested module hierarchy (multi-level Louvain) + cross-module bridges.*

`````
<!-- ripwire zoom: NESTED module hierarchy (multi-level Louvain); indent = one level deeper; module = dominant-dir(symbol-count); leaf lists top-ranked symbols; bridge = cross-top-module call traffic. symbols= is the whole corpus; isolated= is the symbols in NO top-level module (a group of one — the same rule that makes top_modules= count only groups of 2 or more), and they reconcile exactly: symbols= equals isolated= plus the sum of the TOP-LEVEL size= values, every one of them, including any this page did not print. On a level-0 module size= is its true member count and shown=/capped= describe the member list printed here, which is fixed at the 5 top-ranked members and is not widened by limit=/offset= (those page the TOP-LEVEL modules); the community drill verb pages one module's full member list by its level-0 id. A module above level 0 lists every child module, so it carries no shown=/capped= pair. pr_iters=pagerank-power-iterations(stop:L1-residual-below-tol,else-ceiling) pr_converged=0-only-when-ceiling-hit-first(absent=converged;no-such-attr=not-pagerank-ordered) -->
<zoom levels="4" top_modules="313" symbols="11348" isolated="6765" pr_iters="32">
<module level="3" id="422" size="2683" dir="./src">
<module level="2" id="423" size="2573" dir="./src">
<module level="1" id="455" size="1980" dir="./src">
<module level="0" id="2530" size="560" dir="./src" shown="5" capped="1">
<member t="method" n="empty" p="./src/notes.h:396"/>
<member t="method" n="empty" p="./src/scipoverlay.h:93"/>
<member t="method" n="clear" p="./src/renamemine.h:225"/>
<member t="fn" n="min" p="./src/infra/fastmath.h:51"/>
<member t="fn" n="escapeXml" p="./src/serialize.h:122"/>
</module>
<module level="0" id="2554" size="336" dir="./src" shown="5" capped="1">
<member t="method" n="size" p="./src/infra/svector.h:285"/>
<member t="fn" n="max" p="./src/infra/fastmath.h:54"/>
<member t="macro" n="VERIFY" p="./src/infra/Diagnostics.h:172"/>
<member t="method" n="end" p="./src/infra/svector.h:270"/>
<member t="method" n="end" p="./src/infra/svector.h:272"/>
</module>
<module level="0" id="2543" size="297" dir="./src" shown="5" capped="1">
<member t="method" n="push_back" p="./src/infra/svector.h:326"/>
<member t="method" n="push_back" p="./src/infra/svector.h:331"/>
<member t="method" n="reserve" p="./src/infra/svector.h:294"/>
<member t="method" n="back" p="./src/infra/svector.h:263"/>
<member t="method" n="back" p="./src/infra/svector.h:264"/>
</module>
<module level="0" id="2521" size="300" dir="./src" shown="5" capped="1">
<member t="method" n="find" p="./src/ingest.cpp:11306"/>
<member t="method" n="find" p="./src/graph.h:2736"/>
<member t="method" n="empty" p="./src/infra/svector.h:284"/>
… [6391 more display lines; full output is 317515 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --report`

*Architecture summary (modules, god-files, cycles) as markdown.*

`````
<!-- ripwire markdown: no run of 4-or-more backticks in this output — safe to embed inside a wider fence -->

# ripwire architecture report

1304 files · 11348 symbols · 13926 edges · 847 modules (6765 call-graph isolated)

Root: `.`

Call-graph isolate provenance: 1612 declaration, 714 header, 2243 source, 2196 document; 0 connected Louvain singletons

## Modules (call-graph clusters; showing 12 of 847)
- **src::min@infra/fastmath.h:51:2347 [run,write,emit]** — 560 symbols
- **src::VERIFY@infra/Diagnostics.h:172:8901 [compute,apply,resolve]** — 336 symbols
- **src::emplace@infra/svector.h:408:22477 [resolve,parse,compute]** — 300 symbols
- **src::PROFILE_SCOPE_DESCRIBE@infra/profileScope.h:1322:44988 [compute,add,split]** — 297 symbols
- **src::str@ingest.cpp:1977:131885 [read,write,load]** — 50 symbols
- **src::DEGRADED_PATH_ALERT@infra/Diagnostics.h:158:8137 [run,write,split]** — 48 symbols
- **src::try_emplace@infra/dynamic_map.hpp:1344:54522 [resolve,clear,count]** — 33 symbols
- **src/infra::buf@svector.h:125:8942 [insert,compute,move]** — 23 symbols
- **src/infra::read@profilePmc.h:424:18042 [run,read,measure]** — 21 symbols
- **src::identByte@darkflags.h:131:7455 [add,parse,walk]** — 17 symbols
- **src/infra::le@dynamic_map.hpp:177:7831** — 14 symbols
- **test/callformfix/csharp::CondChain@Main.cs:11:383 [run]** — 14 symbols

## God files (most depended-on; showing 10 of 214)
- `src/model.h` — 70 dependents
- `src/infra/Diagnostics.h` — 43 dependents
- `src/serialize.h` — 31 dependents
- `src/graph.h` — 28 dependents
- `src/ingest.h` — 21 dependents
… [31 more lines, 3605 bytes total]
`````

## `./build/ripwire . --seams`

*Cross-module call seams no test reaches. NOW carries seam_pairs/shown/capped.*

`````
<!-- ripwire seams: cross-directory call edges NO test reaches (untested integration seams; a fact, not a mandate). module = parent dir; seam = caller-dir -> callee-dir, spelled from= and to=. Each seam pages its own edge rows with shown=/capped=; an edge names caller= at site p= calling callee= at site cp=. UNIT: untested= here counts cross-directory call EDGES. The test gate verb spells untested= over impacted SYMBOLS and the flip verb over the defs a gate lights, so the three numbers count three different things and must never be compared or summed across verbs. raise the default cap with limit=N (offset=M pages). pr_iters=pagerank-power-iterations(stop:L1-residual-below-tol,else-ceiling) pr_converged=0-only-when-ceiling-hit-first(absent=converged;no-such-attr=not-pagerank-ordered) -->
<!-- root= on this element is the crawl root every p= below is RELATIVE to (single-root runs only; absent => p= is the path ingest itself used, unchanged). -->
<seams modules="262" bridges="4781" untested="4013" test_files="897" seam_pairs="62" shown="20" capped="1" pr_iters="32" root=".">
<seam from="src" to="src/infra" untested="3746" shown="5" capped="1">
<edge caller="popenTrimmed" p="src/quality.h:507" callee="back" cp="src/infra/svector.h:264"/>
<edge caller="popenTrimmed" p="src/quality.h:507" callee="back" cp="src/infra/svector.h:263"/>
<edge caller="popenTrimmed" p="src/quality.h:507" callee="pop_back" cp="src/infra/svector.h:340"/>
<edge caller="gitOneLine" p="src/quality.h:531" callee="shSingleQuote" cp="src/infra/jsonesc.h:268"/>
<edge caller="canonicalId" p="src/resolve.h:1264" callee="size" cp="src/infra/svector.h:285"/>
</seam>
<seam from="bench" to="src/infra" untested="87" shown="5" capped="1">
<edge caller="aggregateMax" p="bench/bench_ordered_map.cpp:85" callee="max" cp="src/infra/fastmath.h:54"/>
<edge caller="applyOne" p="bench/bench_svector_diff.cpp:166" callee="pop_back" cp="src/infra/svector.h:340"/>
<edge caller="applyOne" p="bench/bench_svector_diff.cpp:166" callee="emplace_back" cp="src/infra/svector.h:333"/>
<edge caller="applyOne" p="bench/bench_svector_diff.cpp:166" callee="shrink_to_fit" cp="src/infra/svector.h:305"/>
<edge caller="infraSortSmall" p="bench/bench_radix_ab.cpp:73" callee="sortKeySmall" cp="src/infra/radixSort.h:79"/>
</seam>
<seam from="." to="docs" untested="22" shown="5" capped="1">
<edge caller="What it saves you, in tokens" p="README.md:1000" callee="EVALS" cp="docs/EVALS.md:1"/>
<edge caller="What it answers" p="README.md:466" callee="COMMANDS" cp="docs/COMMANDS.md:1"/>
<edge caller="Measured" p="README.md:892" callee="EVALS" cp="docs/EVALS.md:1"/>
<edge caller="Added — `--nonlocal-state`: the mutable state a function can reach, reads and writes kept apart" p="CHANGELOG.md:166" callee="LINEAGE" cp="docs/LINEAGE.md:1"/>
<edge caller="Measured — `--ensemble`&apos;s four families are near-orthogonal; one of them cannot carry a gate" p="CHANGELOG.md:266" callee="EVALS" cp="docs/EVALS.md:1"/>
</seam>
<seam from="bench" to="test/regexfix" untested="14" shown="5" capped="1">
<edge caller="set_state" p="bench/taskroute_eval.py:44" callee="open" cp="test/regexfix/beta.py:6"/>
<edge caller="instrumented_pass" p="bench/svectorab.py:162" callee="open" cp="test/regexfix/beta.py:6"/>
<edge caller="run_session" p="bench/spec_trace.py:143" callee="open" cp="test/regexfix/beta.py:6"/>
<edge caller="mine_session_file" p="bench/mine_traces.py:169" callee="open" cp="test/regexfix/beta.py:6"/>
<edge caller="read_whole" p="bench/bench_proof.py:27" callee="open" cp="test/regexfix/beta.py:6"/>
… [104 more display lines; full output is 13249 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --mermaid`

*Module (directory) dependency graph as a Mermaid diagram.*

`````
%% ripwire --mermaid: module (directory) dependency graph — node = dir (symbol count), edge = inter-module calls (>= 3). Render at mermaid.live.
flowchart LR
  subgraph sg0 ["src"]
    n75["src<br/>3631"]
    n76["src/infra<br/>491"]
  end
  subgraph sg1 ["test"]
    n77["test<br/>2108"]
    n140["test/expandmodefix<br/>151"]
    n182["test/massfix<br/>77"]
    n173["test/legofix<br/>60"]
    n200["test/optremarksfix<br/>59"]
    n208["test/pyshapefix<br/>58"]
    n192["test/namingconsistencyfix<br/>57"]
    n235["test/swiftshapefix<br/>54"]
    n142["test/expandsibsfix<br/>49"]
    n117["test/constfix<br/>37"]
  end
  subgraph sg2 ["bench"]
    n3["bench<br/>373"]
    n4["bench/agentloop<br/>244"]
    n40["bench/locbench/results/r5_pooling<br/>235"]
    n41["bench/locbench/results/r6_expansion<br/>185"]
    n34["bench/locbench<br/>104"]
    n29["bench/headtohead/r3-headroom-2026-08-03<br/>100"]
    n36["bench/locbench/results/r1cpp_anchorhop<br/>92"]
    n47["bench/nestcal/r1-2026-08-07<br/>84"]
    n26["bench/headtohead<br/>72"]
    n30["bench/headtohead/r4-2026-08-06<br/>72"]
    n48["bench/recalleval<br/>63"]
… [24 more lines, 1629 bytes total]
`````

## `./build/ripwire . --owners`

*Bus-factor: recency-weighted author ownership per file.*

`````
<!-- ripwire owners: recency-weighted author ownership (half-life=6mo). bf=1 = one person holds >80% of weighted commits (bus-factor risk); authors=1 files fold into <uniform/> below; pass detail=1 for the full per-file listing. files= means two different things by DEPTH here and is deliberately not renamed: on the ROOT it is how many files were ANALYSED; on the <uniform/> fold it is how many of them collapsed into that one row. With a SYM, of= echoes it and defs= is how many DEFINITIONS that name has: this report covers the file holding the FIRST of them (lowest node id, the same pick around and lego make), so defs= above 1 means the other definitions' files were NOT analysed. Qualify with file:name to choose one -->
<!-- at= is the git commit these numbers were computed at; a trailing +dirty means the working tree differed from that commit, so the numbers describe the tree, not the commit -->
<!-- root= on this element is the crawl root every p= below is RELATIVE to (single-root runs only; absent => p= is the path ingest itself used, unchanged). -->
<owners files="1304" root="." at="700e51d49">
<uniform authors="1" bf="1" share="1.00" files="793"/>
<f p=".github/workflows/ci.yml" authors="2" bf="1" top="<author>" share="0.94"/>
<f p=".github/workflows/release.yml" authors="3" bf="0" top="<author>" share="0.78"/>
<f p="CHANGELOG.md" authors="2" bf="1" top="<author>" share="0.94"/>
<f p="PLAN.md" authors="2" bf="1" top="<author>" share="0.94"/>
<f p="README.md" authors="4" bf="1" top="<author>" share="0.96"/>
<f p="SECURITY.md" authors="2" bf="0" top="<author>" share="0.50"/>
<f p="THIRD_PARTY.md" authors="2" bf="1" top="<author>" share="0.84"/>
<f p="bench/ANSWERQUALITY.md" authors="2" bf="0" top="<author>" share="0.75"/>
<f p="bench/BENCHMARK.md" authors="2" bf="0" top="<author>" share="0.75"/>
<f p="bench/PROFILE.md" authors="3" bf="1" top="<author>" share="0.88"/>
<f p="bench/agentloop/README.md" authors="2" bf="1" top="<author>" share="0.86"/>
<f p="bench/agentloop/analyze.py" authors="2" bf="1" top="<author>" share="0.91"/>
<f p="bench/agentloop/run_agentloop.py" authors="2" bf="1" top="<author>" share="0.93"/>
<f p="bench/agentloop/select_tasks.py" authors="2" bf="0" top="<author>" share="0.75"/>
<f p="bench/bench_convergence.cpp" authors="2" bf="1" top="<author>" share="0.86"/>
<f p="bench/bench_fixedstr.cpp" authors="2" bf="0" top="<author>" share="0.67"/>
<f p="bench/bench_ordered_map.cpp" authors="2" bf="0" top="<author>" share="0.67"/>
<f p="bench/bench_proof.py" authors="2" bf="0" top="<author>" share="0.50"/>
<f p="bench/bench_radix_ab.cpp" authors="2" bf="1" top="<author>" share="0.84"/>
<f p="bench/bench_sort_large.cpp" authors="2" bf="1" top="<author>" share="0.84"/>
<f p="bench/bench_svector3.cpp" authors="2" bf="1" top="<author>" share="0.90"/>
<f p="bench/calib_json.py" authors="2" bf="0" top="<author>" share="0.67"/>
<f p="bench/cppbench/README.md" authors="2" bf="0" top="<author>" share="0.67"/>
<f p="bench/cppbench/results/sfml.json" authors="2" bf="0" top="<author>" share="0.67"/>
<f p="bench/cppbench/results/sfml_scoreboard.md" authors="2" bf="0" top="<author>" share="0.51"/>
… [487 more display lines; full output is 61441 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --dead-code=src`

*High-confidence internal functions with no caller. NOTE the filter is a path-COMPONENT match: 'src' matches any .../src/... segment; use ./src to pin the root directory.*

`````
<!-- ripwire dead-code: high-confidence source functions with internal linkage and no caller in the indexed tree. A bare-name filter matches by path COMPONENT: filter="src" keeps any path with a src segment at any depth (test/x/src/y.cpp included); anchor with ./ (filter="./src") to pin the root-level directory only. Graph evidence is local to the indexed tree; verify before deleting -->
<dead-code count="1" confidence="high" evidence="internal-linkage+zero-callers" filter="src" root=".">
<d n="unused_helper" t="fn" p="test/archmetricsfix/src/orphan/util.cpp" l="1"/>
</dead-code>
`````

## `./build/ripwire . --exercises=test/regression.sh`

*Which symbols a TEST FILE exercises — the reverse direction of --affected.*

`````
<!-- ripwire exercises: the NON-TEST symbols this test transitively calls into — what it covers (the inverse of the affected verb). <t> = the seed test files the pattern matched; <s> = the covered symbols, PageRank desc. harness=script|mixed says the seed set contains shell gates, whose subprocess coverage this walk cannot see. pr_iters=pagerank-power-iterations(stop:L1-residual-below-tol,else-ceiling) pr_converged=0-only-when-ceiling-hit-first(absent=converged;no-such-attr=not-pagerank-ordered) -->
<!-- root= on this element is the crawl root every p= below is RELATIVE to (single-root runs only; absent => p= is the path ingest itself used, unchanged). -->
<exercises of="test/regression.sh" seed_files="1" shown_seed_files="1" seed_files_capped="0" test_symbols="3" reaches="0" harness="script" note="a shell gate invokes the compiled binary as a subprocess; script-to-binary edges are not modelled, so reaches= counts call-graph reach only and cannot see  … [line truncated: 72 more bytes on this line]
<t p="test/regression.sh"/>
</exercises>
`````

## `./build/ripwire . --community=0`

*Drill into ONE call-graph community by id — the drill= the --communities output itself advertises.*

`````
<!-- ripwire community: ONE module from the communities/zoom partition — its ranked members and its bridge edges to other modules. size= is the module's TRUE member count; shown=/capped= are this page. partition= is the FULL label space (every id 0..partition-1, incl. isolated singletons) — the range the id= argument ranges over; modules= counts the NON-isolated communities (size>=2), the SAME predicate the communities-listing verb's modules= uses, so parent and child agree. pr_iters=pagerank-power-iterations(stop:L1-residual-below-tol,else-ceiling) pr_converged=0-only-when-ceiling-hit-first(absent=converged;no-such-attr=not-pagerank-ordered) -->
<!-- root= on this element is the crawl root every p= below is RELATIVE to (single-root runs only; absent => p= is the path ingest itself used, unchanged). -->
<community id="0" size="1" dir=".codex-plugin" label=".codex-plugin::name@plugin.json:2:4" bridges="0" shown_bridges="0" bridges_capped="0" partition="7612" modules="847" shown="1" capped="0" pr_iters="32" root=".">
<member t="sec" n="name" p=".codex-plugin/plugin.json:2"/>
</community>
`````

## `./build/ripwire . --quality-delta`

*On a CLEAN tree: nothing got worse, exit 0. The gating shape is in the sandbox section below.*

**wall time: 3.00s**

`````
<!-- ripwire quality-delta: only what a change made WORSE against the floor named by baseline= below. FOUR floors, and they are not interchangeable: sidecar = the pinned .ripwire_quality_baseline snapshot, honored only because it was pinned at the CURRENT git HEAD; git-HEAD = no sidecar existed, so the working tree was auto-compared against the HEAD tree; git-HEAD (stale sidecar removed) = a sidecar existed, was pinned at a DIFFERENT sha, and this run DELETED it from your working tree before falling back to HEAD (re-pin with quality-baseline); git-HEAD (stale sidecar ignored) = same staleness verdict, but the file was left on disk (the read-only MCP arm, or an unlink that failed). Only the first is a floor YOU chose; the other three compare against HEAD, so anything already committed cannot appear. A FIFTH marker, ref-pair, means none of those: the verb was given a RANGE, so it compared two COMMITTED trees and no sidecar was read, written or deleted. Those reports carry base_ref= and target_ref= (the two RESOLVED shas, at full length, because a wave number gets quoted into handoffs) and OMIT at=, since the pair is the anchor. They also carry churn set to unavailable, which is the honest statement that one of the ten kinds, short-horizon-churn, cannot be measured there at all: it needs git history at the tree being judged, and both trees are materialized OUT of the repo into temp dirs. Its silence in such a report is therefore not evidence that nothing churned. at= is the git commit (plus a dirty marker when the working tree differs) this list was computed at. Findings: complexity over the ccx bar, verbosity (LOC)/nesting/params regressions, new duplication, newly-dead, new public api-surface (contract drift), error-masking, short-horizon churn, new clone of a reused helper. THREE independent axes, applied in this order: (1) acked findings are suppressed entirely (acked= counts them, honestly); (2) ORIGIN — a finding on a symbol that EXISTED at the baseline is preexisting-worse (no origin= attribute), one that exists only because the code is NEW carries origin="new-symbol"; (3) MATERIALITY — a small numeric delta is sev="minor". EXIT 2 fires only on preexisting-worse AND major, i.e. gating="N" above; new-symbol rows never gate. Clone kinds classify by their member set (a group is new-symbol only if EVERY member is new); short-horizon-churn is preexisting by construction. exit 0 is NOT a verdict on the new-symbol rows — nothing that existed got worse, but the new debt is yours: read them. LIMIT: origin is canonId identity (path::scope::name), so a RENAMED or MOVED symbol reads as new — a regression carried in with a move classifies new-symbol and will not gate. Descriptive: weigh + fix the real ones, do not game the number (a wrong abstraction beats a low score). stale="N" is a SEPARATE axis, never gating, over the .ripwire_quality_acks ledger: an ack whose target no longer applies. Each sa row's why is target-gone (the key names no symbol/group any more) or finding-gone (the target survived, this kind just does not fire on it) — hygiene disclosure only, the ledger file is never auto-edited. Each row carries kind= (which of the measured axes regressed) and sym= (the canonical id it regressed on) — except duplication rows, which name the whole clone group rather than one symbol: members= is the group's member list and tokens= its shared normalized-token count (the same per-group pair the clones verb reports) — plus p="path:line" (root-relative; the first-sorting member for the clone kinds; omitted, never faked, when no locator resolves), and every row the header's gating= counter counts also carries a gating attribute set to 1 — those are the rows the exit code fires on, and they are now marked positively rather than by the ABSENCE of sev/origin. (This sentence deliberately spells no attribute=value literal: the header counters are parsed by grep in several gates, and a quoted numeric example here would be matched first.) -->
<quality-delta baseline="git-HEAD" regressions="0" minor="0" acked="0" stale="16" preexisting-worse="0" new-symbol="0" gating="0" at="700e51d49">
<sa kind="complexity" key="f8f91456c234074f" why="target-gone"/>
<sa kind="complexity" key="fcc9389382ada1b0" why="target-gone"/>
<sa kind="dead-code:preexisting" key="44da49cd9a05e5cc" why="finding-gone"/>
<sa kind="dead-code:preexisting" key="b89dc1827832d2fd" why="finding-gone"/>
<sa kind="duplication" key="4a6d699a2b38f977" why="finding-gone"/>
<sa kind="duplication" key="69ca0068a413b01f" why="finding-gone"/>
<sa kind="duplication" key="6bbb331c18a5deaf" why="finding-gone"/>
<sa kind="short-horizon-churn" key="1b8cc1b791b2c572" why="target-gone"/>
<sa kind="short-horizon-churn" key="1fb1007e9ca0c20b" why="target-gone"/>
<sa kind="short-horizon-churn" key="8bd48de4f0863ced" why="target-gone"/>
<sa kind="short-horizon-churn" key="c00a0f11de7e013b" why="target-gone"/>
<sa kind="verbosity" key="0c653cfea680bc82" why="target-gone"/>
<sa kind="verbosity" key="5fb2e376a4a3a687" why="target-gone"/>
<sa kind="verbosity" key="69b66b3ba85ecc62" why="finding-gone"/>
<sa kind="verbosity" key="cbde843c21e1be3b" why="target-gone"/>
<sa kind="verbosity" key="f8f91456c234074f" why="target-gone"/>
</quality-delta>
`````

stderr:

`````
ripwire: no ./.ripwire_quality_baseline — auto-comparing the working tree vs git HEAD (commit the baseline with --quality-baseline to pin it)
`````

## `./build/ripwire . --edit-check=rankGraphTeleport`

*Fast per-symbol post-edit contract check vs git HEAD (unchanged on a clean tree).*

`````
<!-- ripwire edit-check: SYM's contract (param count + publicness) NOW vs git HEAD — unchanged/new-symbol/contract-change — plus its 1-hop callers. A caller is flagged incompatible="1" when its argument count was reliably counted and NO definition in the folded set could accept it: every one has a FIXED arity that disagrees. A variadic, defaulted or implicit-receiver definition (a Python/Ruby method, whose params counts the self/cls the call site never writes) has no fixed arity and is never flagged. That makes the ARITY half one-sided — a call the compared definitions could accept is never flagged — but it is NOT a proof that the call site binds to THIS definition. Call edges are matched by NAME, so a receiver-qualified call to a same-named callee this tool does not index (a standard-library or third-party method) is measured against the one definition it does index; a clean, compiling tree can therefore carry a nonzero incompatible= with nothing edited at all, and on a widely-shared name it can be most of that name's callers. Read incompatible= as a fact about the tree as it stands — call sites worth OPENING, not a verdict — and status= as a fact about the edit. Warm path hits the qheadsnap/qsnap cache — never a full quality-delta style recompute. defs= is how many DEFINITIONS at this site (same file, same scope, same name — the overload set) are folded into this one contract; a selector matching more than one SITE is refused instead, so defs= only ever counts overloads. params_was and params_now are the MAX over that set on each side (the same MAX the baseline snapshot stores), and publicness is the OR. That MAX has TWO consequences, in opposite directions. It can read like a break and not be one: adding a WIDER overload beside an unchanged one raises params_now with no existing definition altered, so it reports status="contract-change" with incompatible="0" and a def row still carrying the old parameter count — no seen caller breaks. And it can read like safety and not be: REMOVING an overload whose parameter count is BELOW the MAX moves neither number, because the MAX survives on both sides, while the call site that used the removed definition no longer binds. defs_was=/defs_now= is what closes that: the count of definitions sharing this symbol's CANONICAL ID on each side. That population is the one the baseline snapshot buckets by, so the two numbers answer the same question and are equal on an unedited tree — it is deliberately NOT the root's defs=, which is the same bucket narrowed to this FILE (a contract is per definition site), so where a scope-less name also exists in another file defs= is the smaller of the two. status is therefore the join of THREE was-vs-now facts — the params MAX, publicness, and the definition COUNT — and change= names which of them carried it. change= adds broken-callers when a seen caller is also flagged, but never on its own — for the reason stated at the top: incompatible= describes the TREE and status= describes the EDIT, so a headline must not turn on it. RESIDUAL: an overload whose arity changes BELOW the MAX while the COUNT stays the same moves none of the three. The root's incompatible= is the COUNT of flagged callers (a c row's incompatible="1" is the per-caller flag). p= is the definition the selector resolved to; when defs is above 1 EVERY folded definition is listed as its own def row (p=, t=, params=), which is what tells a widened single definition apart from an added overload. At defs="1" no def row is emitted: the root's own p=/t= is that definition, and params_now is its parameter count. counts_floor="1" means every count on this element is a FLOOR, never a total. Call edges are extracted from source text by NAME, so a call that reaches its target through dynamic dispatch (a virtual, interface or duck-typed receiver), or a declaration that parses without a call expression (C++ most-vexing-parse) contributes no edge and is missing here. A call through a function pointer or callback resolves only when ONE function is bound to that variable in scope (C-family; a reassigned, table-indexed, lambda-bound or escaped pointer — its address taken or reference-bound — still contributes no edge). A binding written as a plain name rather than an address-of (fp = handler, not fp = &handler) is read as a function only when the variable is PROVEN able to hold one: a function-pointer declarator, or a function-pointer typedef declared in the SAME FILE, or a type the parse cannot pin down at all (auto, a template type). Under any other concrete written type it is a value copy and contributes no edge, so a variable whose function-pointer typedef lives in a HEADER is missed. A macro-generated call site contributes a role="macro" edge when its name uniquely names an indexed function-like #define (C-family, t="macro"); a name shared with any non-macro definition stays a plain call for the resolver, and an unindexed macro's call site contributes no edge. Read a zero as "none found", never as "none exists". COUNTING UNIT, and it differs by verb — which is why two of them report different numbers for one symbol. The callers, callees, edit-check, graph-query and pr-context counts are DISTINCT SYMBOLS: repeated calls from one caller, and calls to two overloads of one name, collapse into ONE row, their multiplicity surviving only in the call graph's edge weight. The reach counts (impact's reaches=, pr-context's dependents=) are the size of a transitive reach SET, each symbol counted once — not a count of calls or edges. The uses verb counts call SITES, one row per occurrence, so a larger count= there for the same symbol is these units agreeing, not disagreeing. The map header's edges= is a unit again different — distinct (caller,callee) PAIRS — and that document carries neither this marker nor this clause, so its numbers answer a different question. -->
<edit-check sym="rankGraphTeleport" t="fn" p="src/graph.h:2112" status="unchanged" defs="1" callers="6" incompatible="0" at="700e51d49" counts_floor="1" root=".">
<c n="runEval" p="src/eval.h:168"/>
<c n="rankGraph" p="src/graph.h:2153"/>
<c n="anchoredLexicalRank" p="src/graph.h:2489"/>
<c n="churnRankedGraph" p="src/main.cpp:12504"/>
<c n="runDefaultMap" p="src/main.cpp:12619"/>
<c n="getIndex" p="src/mcpindex.h:950"/>
</edit-check>
`````

## `./build/ripwire . --pr-context`

*No-LLM review-evidence bundle for the working-tree diff (clean tree = empty).*

`````
<!-- ripwire pr-context: no-LLM review-evidence bundle per changed file — defined symbols, their callers, blast radius (transitive dependents), affected tests, co-change partners not in the diff, and owners. base=working-tree. skipped_mode_only=diffs that changed a file's MODE and nothing else (e.g. chmod) excluded from the changed set; a pure RENAME is content-identical too but is NOT excluded — it is a changed file, listed at its new path. files= means two different things by DEPTH here and is deliberately not renamed (15 consumers read the root one): on the ROOT it is the CHANGED file count; on each <impact/> child it is the distinct files dependents= reaches (changed + non-changed), so dependents="0" implies files="0" and vice versa — never an impossible-looking dependents>0/files=0. files_other= on the same <impact/> is the non-changed subset (a changed file's dependents inside OTHER changed files have no <f> row of their own — they are already shown as their own <file> section); it is NOT the <f> row count — see the row-cap sentence below. Files are ordered by BLAST RADIUS (transitive dependents descending, path breaking ties), not alphabetically. sections= on changed-symbols counts a doc file's headings, collapsed into that number instead of one callers-zero row each; count= still counts every INDEXED symbol, sections included, so count minus sections is the number of rows that follow. Every nested list below is a TOP-N subset of its element's own total, fixed per element (impact <f> at 20, per-symbol <caller> at 12, cochange <partner> at 12, tests <test> at 40, owners <author> at 5 — the L0 defaults; max-tokens only lowers these further via the trim ladder, nothing raises them past L0): each capped element carries its own shown=/capped= pair so the cut is never silent — for the untrimmed list use impact=SYM/callers=SYM (blast radius/callers), affected=FILE or situ (tests), cochange (partners), or owners (authors) instead. direction= names which SIDE this bundle reviews (worktree-since-head, head-since-fork, head-since-ref-tip); a no-ref-work row says the base ref's tip IS the merge base, i.e. it carries no divergent work of its own. deterministic. counts_floor="1" means every count on this element is a FLOOR, never a total. Call edges are extracted from source text by NAME, so a call that reaches its target through dynamic dispatch (a virtual, interface or duck-typed receiver), or a declaration that parses without a call expression (C++ most-vexing-parse) contributes no edge and is missing here. A call through a function pointer or callback resolves only when ONE function is bound to that variable in scope (C-family; a reassigned, table-indexed, lambda-bound or escaped pointer — its address taken or reference-bound — still contributes no edge). A binding written as a plain name rather than an address-of (fp = handler, not fp = &handler) is read as a function only when the variable is PROVEN able to hold one: a function-pointer declarator, or a function-pointer typedef declared in the SAME FILE, or a type the parse cannot pin down at all (auto, a template type). Under any other concrete written type it is a value copy and contributes no edge, so a variable whose function-pointer typedef lives in a HEADER is missed. A macro-generated call site contributes a role="macro" edge when its name uniquely names an indexed function-like #define (C-family, t="macro"); a name shared with any non-macro definition stays a plain call for the resolver, and an unindexed macro's call site contributes no edge. Read a zero as "none found", never as "none exists". COUNTING UNIT, and it differs by verb — which is why two of them report different numbers for one symbol. The callers, callees, edit-check, graph-query and pr-context counts are DISTINCT SYMBOLS: repeated calls from one caller, and calls to two overloads of one name, collapse into ONE row, their multiplicity surviving only in the call graph's edge weight. The reach counts (impact's reaches=, pr-context's dependents=) are the size of a transitive reach SET, each symbol counted once — not a count of calls or edges. The uses verb counts call SITES, one row per occurrence, so a larger count= there for the same symbol is these units agreeing, not disagreeing. The map header's edges= is a unit again different — distinct (caller,callee) PAIRS — and that document carries neither this marker nor this clause, so its numbers answer a different question. -->
<pr-context base="working-tree" root="." direction="worktree-since-head" files="0" skipped_mode_only="0" at="700e51d49" counts_floor="1">
<!-- no changed files in the index (clean tree, or the diff touched only non-indexed files) -->
</pr-context>
`````

## `./build/ripwire . --pr-context=main~1`

*The BASEREF form: diffed against merge-base(BASEREF, HEAD), never the ref tip — here the previous mainline commit.*

`````
<!-- ripwire pr-context: no-LLM review-evidence bundle per changed file — defined symbols, their callers, blast radius (transitive dependents), affected tests, co-change partners not in the diff, and owners. base=main~1. skipped_mode_only=diffs that changed a file's MODE and nothing else (e.g. chmod) excluded from the changed set; a pure RENAME is content-identical too but is NOT excluded — it is a changed file, listed at its new path. files= means two different things by DEPTH here and is deliberately not renamed (15 consumers read the root one): on the ROOT it is the CHANGED file count; on each <impact/> child it is the distinct files dependents= reaches (changed + non-changed), so dependents="0" implies files="0" and vice versa — never an impossible-looking dependents>0/files=0. files_other= on the same <impact/> is the non-changed subset (a changed file's dependents inside OTHER changed files have no <f> row of their own — they are already shown as their own <file> section); it is NOT the <f> row count — see the row-cap sentence below. Files are ordered by BLAST RADIUS (transitive dependents descending, path breaking ties), not alphabetically. sections= on changed-symbols counts a doc file's headings, collapsed into that number instead of one callers-zero row each; count= still counts every INDEXED symbol, sections included, so count minus sections is the number of rows that follow. Every nested list below is a TOP-N subset of its element's own total, fixed per element (impact <f> at 20, per-symbol <caller> at 12, cochange <partner> at 12, tests <test> at 40, owners <author> at 5 — the L0 defaults; max-tokens only lowers these further via the trim ladder, nothing raises them past L0): each capped element carries its own shown=/capped= pair so the cut is never silent — for the untrimmed list use impact=SYM/callers=SYM (blast radius/callers), affected=FILE or situ (tests), cochange (partners), or owners (authors) instead. direction= names which SIDE this bundle reviews (worktree-since-head, head-since-fork, head-since-ref-tip); a no-ref-work row says the base ref's tip IS the merge base, i.e. it carries no divergent work of its own. deterministic. counts_floor="1" means every count on this element is a FLOOR, never a total. Call edges are extracted from source text by NAME, so a call that reaches its target through dynamic dispatch (a virtual, interface or duck-typed receiver), or a declaration that parses without a call expression (C++ most-vexing-parse) contributes no edge and is missing here. A call through a function pointer or callback resolves only when ONE function is bound to that variable in scope (C-family; a reassigned, table-indexed, lambda-bound or escaped pointer — its address taken or reference-bound — still contributes no edge). A binding written as a plain name rather than an address-of (fp = handler, not fp = &handler) is read as a function only when the variable is PROVEN able to hold one: a function-pointer declarator, or a function-pointer typedef declared in the SAME FILE, or a type the parse cannot pin down at all (auto, a template type). Under any other concrete written type it is a value copy and contributes no edge, so a variable whose function-pointer typedef lives in a HEADER is missed. A macro-generated call site contributes a role="macro" edge when its name uniquely names an indexed function-like #define (C-family, t="macro"); a name shared with any non-macro definition stays a plain call for the resolver, and an unindexed macro's call site contributes no edge. Read a zero as "none found", never as "none exists". COUNTING UNIT, and it differs by verb — which is why two of them report different numbers for one symbol. The callers, callees, edit-check, graph-query and pr-context counts are DISTINCT SYMBOLS: repeated calls from one caller, and calls to two overloads of one name, collapse into ONE row, their multiplicity surviving only in the call graph's edge weight. The reach counts (impact's reaches=, pr-context's dependents=) are the size of a transitive reach SET, each symbol counted once — not a count of calls or edges. The uses verb counts call SITES, one row per occurrence, so a larger count= there for the same symbol is these units agreeing, not disagreeing. The map header's edges= is a unit again different — distinct (caller,callee) PAIRS — and that document carries neither this marker nor this clause, so its numbers answer a different question. -->
<!-- anchoring: a base ref was given, so this diff is anchored at merge base(BASEREF, HEAD), NOT at the ref's tip — the bundle is what THIS work changed since it forked, not how the two trees differ today. base_moved= counts paths the BASE REF moved since the fork that this work never touched (excluded here, and the same row class the abi verb names head moved: the other line moved, we did not author it). anchor="ref tip two dot" instead means there was no merge base at all (unrelated history) and the two dot view is what you are reading. -->
<pr-context base="main~1" root="." anchor="merge-base" base_sha="9540aff8e" base_moved="0" direction="head-since-fork" files="143" skipped_mode_only="0" at="700e51d49" counts_floor="1">
<no-ref-work note="main~1 tip == merge-base, so that ref has no divergent work of its own; this bundle is HEAD's work since the fork. For the ref's OWN diff see merge-scout or stray-content"/>
<file p="src/graph.h" symbols="113">
<impact dependents="553" files="77" files_other="47" shown="20" capped="1">
<f p="src/gitmine.h" deps="29"/>
<f p="src/docdrift.h" deps="24"/>
<f p="src/crossref.h" deps="22"/>
<f p="src/resolve.h" deps="14"/>
<f p="src/flipimpact.h" deps="13"/>
<f p="src/naminglens.h" deps="13"/>
<f p="src/recall.h" deps="12"/>
<f p="src/testmap.h" deps="11"/>
<f p="src/lanes.h" deps="9"/>
<f p="src/tracein.h" deps="9"/>
<f p="src/skilleval.h" deps="8"/>
<f p="src/clones.h" deps="7"/>
<f p="src/mergescout.h" deps="7"/>
<f p="src/taskroute.h" deps="7"/>
<f p="src/filter.h" deps="6"/>
<f p="src/gitoracle.h" deps="6"/>
<f p="src/mcpserver.h" deps="5"/>
<f p="src/renamemine.h" deps="5"/>
<f p="src/accessshape.h" deps="4"/>
<f p="src/ensemble.h" deps="4"/>
</impact>
<tests count="6" shown="6" capped="0">
<test p="test/cloneband_harness.cpp" run="bash test/clonebandcheck.sh"/>
<test p="test/clonelex_harness.cpp" run="bash test/clonelexcheck.sh"/>
… [10598 more display lines; full output is 500874 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --merge-scout=main~2,main~1`

*Pairwise cross-arm conflict sites + suggested landing order (any committish works as an arm).*

**wall time: 1.84s**

`````
<!-- ripwire merge-scout: read-only cross-branch overlap for 2 arm(s) — same-symbol change on two arms = conflict, same-file/different-symbol = textual risk. landing = fewest-conflicts-first greedy (ties: ref name asc). Every tree is a git-archive TEMP COPY (read-only); the real working tree/refs are never touched. ANCHORING: every arm is diffed against its OWN merge base with HEAD (the working tree arm against HEAD itself), never against live HEAD — so a file an arm never opened can never appear here just because the live line moved. head_conflicts= is the one thing that anchor hides, kept as its own row class: symbols this arm changed that the LIVE LINE also changed since the arm forked, a merge fight no pairwise ARM comparison can see because HEAD is not an arm. -->
<merge-scout arms="2" head="700e51d49">
<arm ref="main~2" base="0b888ab8b" ok="1" changed="0" head_conflicts="0">
<no-work note="no divergent work vs merge-base — see --stray-content"/>
</arm>
<arm ref="main~1" base="9540aff8e" ok="1" changed="0" head_conflicts="0">
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
<stray-content head="700e51d49" head_ref="integration/harvestexec-2026-08-20" refs="35" blobs="0" unmerged="0" superseded="0" merged="35" unknown="0">
</stray-content>
`````

## `./build/ripwire . --stray-content=worktree-agent-a1`

*A ref family that IS fully merged — the omit-merged-refs contract, with the counters still reconciling against refs=.*

`````
<!-- ripwire stray-content: per ref, the lines its own divergent work AUTHORED (vs its merge-base with HEAD) that the live line does NOT have. v="superseded" means the live line removed the same base code this ref removed (redone/del) — it re-implemented the work, the case `git cherry` cannot see; v="unmerged" means the work is genuinely absent; merged refs are omitted. Read-only: git cat-file/diff/ls-tree only, one batched cat-file for the whole sweep, every blob reduced once per sha. Line-granular, not semantic: see the ripwire help text for the limits. ANCHORING is a deliberate hybrid: the SCOPE is base anchored (only lines the ref itself authored vs its merge base are ever considered, so a file the ref never opened cannot appear because the live line moved), while the ABSENCE test is HEAD anchored on purpose (does the live line have this content TODAY is the question being asked, and it is only answerable against live HEAD). v="unknown" with ok="0" means this ref could NOT be analysed at all because it has no merge base with HEAD, which on a SHALLOW clone (the checkout default in CI) is every ref: it is not a claim that the ref is merged, and the fix is to deepen the clone. The four buckets are exhaustive, so unmerged plus superseded plus merged plus unknown always equals refs. SCOPE: refs/heads only, which is every local branch (worktree branches included). Remote tracking refs are NOT scanned: they mirror local ones in the usual checkout and would double every row. The consequence on a FRESH CLONE, where the branches live under refs/remotes/origin and only the checked out one has a local head, is that there is nothing here to be stray FROM; refs= is that fact as a number. TRUNCATION: a ref row ends with a more element (more files=N) when its own file listing was capped; shown plus that number equals the ref's files= total, always. That inner listing is a SECONDARY listing (it repeats complete and identical on every page) and is capped by detail, not by limit / offset, which page the OUTER ref listing and report their own shown= / capped=. -->
<stray-content head="700e51d49" head_ref="integration/harvestexec-2026-08-20" refs="1" blobs="0" unmerged="0" superseded="0" merged="1" unknown="0">
</stray-content>
`````

## `./build/ripwire . --stray-content=r27 --plan`

*Select the genuinely-unmerged refs and feed them to merge-scout for a landing order.*

`````
<!-- ripwire landing-plan: stray-content's cheap per-blob sweep composed with merge-scout's per-arm overlap oracle — of every local branch, which still hold REAL work (v="unmerged"), which were already re-implemented on the live line (v="superseded", EXCLUDED below — landing them re-does work that is already done) or are already merged (omitted entirely, counted in merged= on the root element), and the fewest-conflicts-first order to land what remains. scouted="0" on an unmerged ref means it was NOT fed to merge-scout this run (the cost bound, not a verdict) — it is still real, unscouted work; bounded= on the root element counts them and detail lifts the bound. merge-scout is the EXPENSIVE step here (git-archive + full ingest per arm) — stray-content's own sweep is the cheap one. An undetermined row is a ref that could NOT be analysed at all (no merge base with HEAD, which on a SHALLOW clone is every ref): it is neither scouted nor excluded nor merged, because nothing was measured — treat it as unfinished business and deepen the clone, never as a clean branch. Read-only throughout: no checkout, no ref write, no working-tree mutation. The root carries BOTH head= and at= and they are the same commit: head= is the bare 9 hex chars this verb has always printed, at= is the tool wide anchor and is head= plus a "+dirty" suffix when the working tree is not clean. Prefer at= (it is the one spelling every other repo reading verb uses, and the only one that tells you whether uncommitted work was in scope); head= is kept for callers already keyed to it. -->
<landing-plan head="700e51d49" refs="0" unmerged="0" superseded="0" merged="0" undetermined="0" scouted="0" bounded="0" scout-ok="1" at="700e51d49">
</landing-plan>
`````

## `./build/ripwire . --stray-content=lane --abi`

*Cross-branch ABI-break gate: struct byte-contract drift on each ref's AUTHORED paths.*

**wall time: 1.27s**

`````
<!-- ripwire abi: the cross-branch ABI-BREAK gate — layout(STRUCT) crossed with stray-content(BRANCH). Scope is what each ref AUTHORED: the paths `diff base..tip` reports against its own merge base, never `diff HEAD..tip` (a file the branch never opened cannot be a break the branch introduced, and on a long-lived tree that one distinction took 487 drift rows to 4). For each such path the SAME field-offset model layout uses is run LEXICALLY on the ref's git blob (never indexed) and compared against HEAD's computed fields. LISTED kinds: drift = the byte contract differs (the bug this check exists for, the only kind that exits 2); unknown = the ref-side copy could not be modelled (see ref_caveat) and is NEVER reported as unchanged; absent = the ref does not define the struct at that path. COUNTED but not listed (pass detail=N to print them): rename = identical slots and field types under different field NAMES, so every byte stayed where it was (a same-type field REORDER is lexically identical to a rename and lands here too); spelling and stub mirror layout's own harmless cases; head-moved = the ref's copy equals its own merge-base copy, so the LIVE LINE is what changed. head_only= counts candidate sites on paths only the live line touched (outside the authored scope); unmodelable= counts sites skipped because HEAD's own copy carries no baseline; every excluded row is on a counter, nothing is dropped silently. Structs that match are omitted entirely; a ref with no rows at all is counted in quiet=, and a ref whose every row is an excluded kind is counted in excluded_refs= and prints under detail=N. LIMITS: HEAD's own side is the WORKING TREE's layout answer, not a re-fetched git blob at HEAD's commit; a nested field type that ALSO changed on the ref resolves via HEAD's copy, not the ref's; the ref-side locator is index-free and file-scope (one namespace deep) only, so a struct nested in a class or wrapped in an extern C block reads absent rather than compared; the authorship anchor is per PATH, so a branch changing struct S in one file while the live line changes S's mirror in another is a merge hazard only layout(S) on the merged result can see. Single-root; read-only (cat-file/diff/merge-base only). -->
<abi head="700e51d49" head_ref="integration/harvestexec-2026-08-20" refs="35" candidates="771" compared="0" blobs="0" rows="0" shown="0" capped="0" dropped="0" excluded="0" head_only="11681" unmodelable="0" unrelated="0" broken_refs="0" quiet="35" excluded_refs="0" root=".">
</abi>
`````

stderr:

`````
ripwire: --stray-content takes precedence when several verbs are given — IGNORED this run: --abi. The winner is fixed by ripwire's dispatch order, NOT by the order you typed them; pass one verb per run.
`````

## `./build/ripwire . --whereis=rankGraphTeleport`

*Which ref's tree defines or mentions SYM — HEAD first, then every local branch.*

**wall time: 2.13s**

`````
<!-- ripwire whereis: every LOCAL ref whose TREE contains this symbol, HEAD first, and within a ref SOURCE files before test files before docs, then definitions before references, then path and line. The doc demotion is ORDER ONLY: a doc line that quotes a signature still reads as a definition to the heuristic below and still says kind="def", it is simply printed after the code. kind= is answered by TWO different mechanisms, and head_labels= says which one answered for HEAD: with head_labels="index" a HEAD row is kind="def" iff the PARSED index puts a definition there (one row per index def site), while every NON-HEAD row — and every row when head_labels="lexical" (no index was supplied, the index knows no def of this name, or the working tree has drifted from HEAD) — is a LEXICAL shape heuristic over raw blob text that was never ingested: it reads a quoted signature in a doc as a definition and can miss an unusual declarator. refs_scanned= is the SCAN DENOMINATOR (how many refs besides HEAD were read), NOT a count of refs that matched — hits= and the rows are the matched set. on-head="0" alongside ref hits is the case this verb exists for: content that lives only on a branch. A TREE scan can only find content some ref still carries, so hits="0" on its own does not distinguish a name this repo never had from one it deleted; run with the with_history flag and the fate row says which, naming the commit that removed it. ANCHORING: none, by design. This verb runs no diff at all — it scans each ref's FULL tree, which is what lets it find content a branch merely INHERITED (exactly what a merge base anchored diff would exclude), so nothing here can fire merely because HEAD moved. at= is sha-only here (never +dirty): a tree scan reads committed blobs, so the working tree's cleanliness does not enter the answer. SELECTOR: this verb takes a BARE symbol name, not the file:name spelling that callers, uses, impact, around, lego and edit_check accept. A file:name spelling is searched as a LITERAL string, no tree contains it, and the result is a true but useless hits="0" shaped exactly like a name this repo never had. When that is what happened, a selector-note element says so and its retry= is the bare name to re-run with. Its absence beside hits="0" means the zero IS a measurement. SCOPE: refs/heads only, which is every local branch (worktree branches included). Remote tracking refs are NOT scanned: they mirror local ones in the usual checkout and would double every row. The consequence on a FRESH CLONE, where the branches live under refs/remotes/origin and only the checked out one has a local head, is that this verb sees essentially one tree; refs_scanned= is that fact as a number, so read it before reading hits=. TRUNCATION: the trailing more element (more hits=N) is the rows AFTER this page, so shown plus more equals the rows from this page's offset on. It is not a second cap, and not a second vocabulary to page by: it is the SAME fact shown= / capped= / next_offset= carry, restated from the other end (what this page did not print). Page with limit= and offset=; the more element is absent exactly when this page reached the end of the hit list. COMPLETENESS: complete= on the root (value 1) means this listing is EXHAUSTIVE and a consumer need not re-derive it: every occurrence of the symbol in every TEXT blob of every scanned ref's full tree is printed above — nothing was capped or paged out, and no blob was oversized (over the 2 MB blob ceiling), missing or cut short by the stream. The denominator is refs_scanned= plus HEAD, under SCOPE above (local heads only), so with complete= present a ref absent from the rows genuinely lacks the symbol in its committed tree. Binary blobs are outside the claim (a text symbol cannot occur in one); an oversized TEXT blob suppresses the claim instead of being silently skipped. Its ABSENCE claims nothing. raise the default cap with limit=N (offset=M pages) -->
<whereis sym="rankGraphTeleport" on-head="1" refs_scanned="106" blobs="3034" hits="49233" head_labels="index" shown="60" capped="1" at="700e51d49">
<hit ref="HEAD" tip="700e51d49" date="2026-08-20" p="src/graph.h" l="2112" kind="def" t="inline RankedGraph rankGraphTeleport( const Graph&amp; g, const std::vector&lt;float&gt;&amp; p, float alpha = 0.85f )"/>
<hit ref="HEAD" tip="700e51d49" date="2026-08-20" p="present/deck5_ripwire_build.js" l="479" kind="ref" t="s.addText(&quot;$ ripwire . --callers=rankGraphTeleport&quot;, { x: 8.68, y: 2.1, w: 3.8, h: 0.3, fontFace: MONO, fontSize: 10, color: MUTED, margin: 0 });"/>
<hit ref="HEAD" tip="700e51d49" date="2026-08-20" p="present/deck5_ripwire_build.js" l="481" kind="ref" t="{ text: &quot;&lt;callers of=\&quot;rankGraphTeleport\&quot;\n  defs=\&quot;1\&quot; count=\&quot;6\&quot; &quot;, options: { color: TEXT } },"/>
<hit ref="HEAD" tip="700e51d49" date="2026-08-20" p="src/crossref.h" l="1602" kind="ref" t="// code above the real definition: `--whereis=rankGraphTeleport` opened with three kind=&quot;def&quot; rows into"/>
<hit ref="HEAD" tip="700e51d49" date="2026-08-20" p="src/eval.h" l="322" kind="ref" t="const std::vector&lt;float&gt; r = rankGraphTeleport( g, diffTeleport( ing, seedMask ) ).rank;"/>
<hit ref="HEAD" tip="700e51d49" date="2026-08-20" p="src/graph.h" l="90" kind="ref" t="// renormalized to Σ=1 in rankGraphTeleport — so every teleport-based"/>
<hit ref="HEAD" tip="700e51d49" date="2026-08-20" p="src/graph.h" l="2055" kind="ref" t="// prior (never the edges) and renormalized in rankGraphTeleport. Every symbol whose name is missing from"/>
<hit ref="HEAD" tip="700e51d49" date="2026-08-20" p="src/graph.h" l="2100" kind="ref" t="// discard out. That is what this used to be: rankGraphTeleport called pageRankDouble, threw away its return,"/>
<hit ref="HEAD" tip="700e51d49" date="2026-08-20" p="src/graph.h" l="2145" kind="ref" t="// `rank = takeRank( rankGraphTeleport( … ), d )` is the only spelling, and it fills both or neither."/>
<hit ref="HEAD" tip="700e51d49" date="2026-08-20" p="src/graph.h" l="2156" kind="ref" t="return rankGraphTeleport( g, std::vector&lt;float&gt;( N, N ? 1.0f / float( N ) : 0.f ), alpha );"/>
<hit ref="HEAD" tip="700e51d49" date="2026-08-20" p="src/graph.h" l="2485" kind="ref" t="// cliff), run the EXISTING PPR machinery (rankGraphTeleport — the same biasPrior/det-gate seam every"/>
<hit ref="HEAD" tip="700e51d49" date="2026-08-20" p="src/graph.h" l="2533" kind="ref" t="const std::vector&lt;float&gt; ppr = rankGraphTeleport( g, p ).rank;"/>
<hit ref="HEAD" tip="700e51d49" date="2026-08-20" p="src/main.cpp" l="12528" kind="ref" t="rw::RankedGraph    ranked = isDecay ? rankGraphTeleport( d.g, churnDecayTeleportWorkspace( rootDirs, d.ing, &amp;hasChurnEvidence ) )"/>
<hit ref="HEAD" tip="700e51d49" date="2026-08-20" p="src/main.cpp" l="12529" kind="ref" t=": rankGraphTeleport( d.g, churnTeleportWorkspace( rootDirs, d.ing, &quot;18 months ago&quot;, &amp;hasChurnEvidence ) );"/>
<hit ref="HEAD" tip="700e51d49" date="2026-08-20" p="src/main.cpp" l="12539" kind="ref" t="rw::RankedGraph    ranked = rankGraphTeleport( d.g, churnDecayTeleport( d.root, d.ing, d.cfg.since.empty() ? nullptr : &amp;sinceScope, &amp;hasChurnEvidence ) );"/>
<hit ref="HEAD" tip="700e51d49" date="2026-08-20" p="src/main.cpp" l="12545" kind="ref" t="rw::RankedGraph    ranked = rankGraphTeleport( d.g, churnTeleport( d.root, d.ing, &quot;18 months ago&quot;, d.cfg.since.empty() ? nullptr : &amp;sinceScope, &amp;hasChurnEvidence ) );"/>
<hit ref="HEAD" tip="700e51d49" date="2026-08-20" p="src/main.cpp" l="12716" kind="ref" t="rank = rw::takeRank( rankGraphTeleport( g, diffTeleport( ing, changed ) ), rankDisclosure );"/>
<hit ref="HEAD" tip="700e51d49" date="2026-08-20" p="src/mcpindex.h" l="1008" kind="ref" t="// symbols, the rest uniform, then rankGraphTeleport (which also applies the name-quality biasPrior"/>
<hit ref="HEAD" tip="700e51d49" date="2026-08-20" p="src/mcpindex.h" l="1041" kind="ref" t="const auto [ wsRank, wsIters, wsConverged ] = rankGraphTeleport( ix.g, diffTeleport( ix.ing, changed ) );"/>
<hit ref="HEAD" tip="700e51d49" date="2026-08-20" p="src/selectorrefuse.h" l="7" kind="ref" t="// (&quot;that file defines no &apos;rankGraphTeleport&apos;&quot;), names the files that DO define the name, and hands back a"/>
<hit ref="HEAD" tip="700e51d49" date="2026-08-20" p="bench/nestcal/r1-2026-08-07/post-ripwire-src.tsv" l="651" kind="ref" t="graph.h::rw::rankGraphTeleport&#9;3&#9;0&#9;0&#9;5&#9;8&#9;28"/>
<hit ref="HEAD" tip="700e51d49" date="2026-08-20" p="bench/nestcal/r1-2026-08-07/pre-ripwire-src.tsv" l="651" kind="ref" t="graph.h::rw::rankGraphTeleport&#9;3&#9;0&#9;0&#9;5&#9;8&#9;28"/>
<hit ref="HEAD" tip="700e51d49" date="2026-08-20" p="bench/recalleval/labels_ranking.tsv" l="49" kind="ref" t="power iteration rank convergence damping factor&#9;src/pagerank.cpp#pageRankDouble&#9;src/graph.h#rankGraphTeleport,src/pagerank.h#pageRankDouble&#9;concept"/>
<hit ref="HEAD" tip="700e51d49" date="2026-08-20" p="bench/recalleval/labels_ranking.tsv" l="68" kind="ref" t="pagerank power iteration&#9;src/pagerank.cpp#pageRankDouble&#9;src/pagerank.h#pageRankDouble,src/graph.h#rankGraphTeleport&#9;adversarial"/>
<hit ref="HEAD" tip="700e51d49" date="2026-08-20" p="bench/recalleval/snapshot.mdpack" l="1706" kind="ref" t="shifted `readmeexamplecheck`&apos;s pinned `--callers=rankGraphTeleport` example by +9 lines"/>
<hit ref="HEAD" tip="700e51d49" date="2026-08-20" p="bench/recalleval/snapshot.mdpack" l="2758" kind="ref" t="$ ripwire . --callers=rankGraphTeleport"/>
<hit ref="HEAD" tip="700e51d49" date="2026-08-20" p="bench/recalleval/snapshot.mdpack" l="2759" kind="ref" t="&lt;callers of=&quot;rankGraphTeleport&quot; defs=&quot;1&quot; count=&quot;6&quot; counts_floor=&quot;1&quot;&gt;"/>
<hit ref="HEAD" tip="700e51d49" date="2026-08-20" p="bench/recalleval/snapshot.mdpack" l="7559" kind="ref" t="$ ./build/ripwire . --for=&quot;rankGraphTeleport&quot;"/>
… [34 more display lines; full output is 17985 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --whereis=computeOnePairOverlap --with-history`

*Same, plus a git-history <fate> row (never / removed-by-commit) for names no tree carries.*

**wall time: 3.85s**

`````
<!-- ripwire whereis: every LOCAL ref whose TREE contains this symbol, HEAD first, and within a ref SOURCE files before test files before docs, then definitions before references, then path and line. The doc demotion is ORDER ONLY: a doc line that quotes a signature still reads as a definition to the heuristic below and still says kind="def", it is simply printed after the code. kind= is answered by TWO different mechanisms, and head_labels= says which one answered for HEAD: with head_labels="index" a HEAD row is kind="def" iff the PARSED index puts a definition there (one row per index def site), while every NON-HEAD row — and every row when head_labels="lexical" (no index was supplied, the index knows no def of this name, or the working tree has drifted from HEAD) — is a LEXICAL shape heuristic over raw blob text that was never ingested: it reads a quoted signature in a doc as a definition and can miss an unusual declarator. refs_scanned= is the SCAN DENOMINATOR (how many refs besides HEAD were read), NOT a count of refs that matched — hits= and the rows are the matched set. on-head="0" alongside ref hits is the case this verb exists for: content that lives only on a branch. A TREE scan can only find content some ref still carries, so hits="0" on its own does not distinguish a name this repo never had from one it deleted; run with the with_history flag and the fate row says which, naming the commit that removed it. ANCHORING: none, by design. This verb runs no diff at all — it scans each ref's FULL tree, which is what lets it find content a branch merely INHERITED (exactly what a merge base anchored diff would exclude), so nothing here can fire merely because HEAD moved. at= is sha-only here (never +dirty): a tree scan reads committed blobs, so the working tree's cleanliness does not enter the answer. SELECTOR: this verb takes a BARE symbol name, not the file:name spelling that callers, uses, impact, around, lego and edit_check accept. A file:name spelling is searched as a LITERAL string, no tree contains it, and the result is a true but useless hits="0" shaped exactly like a name this repo never had. When that is what happened, a selector-note element says so and its retry= is the bare name to re-run with. Its absence beside hits="0" means the zero IS a measurement. SCOPE: refs/heads only, which is every local branch (worktree branches included). Remote tracking refs are NOT scanned: they mirror local ones in the usual checkout and would double every row. The consequence on a FRESH CLONE, where the branches live under refs/remotes/origin and only the checked out one has a local head, is that this verb sees essentially one tree; refs_scanned= is that fact as a number, so read it before reading hits=. TRUNCATION: the trailing more element (more hits=N) is the rows AFTER this page, so shown plus more equals the rows from this page's offset on. It is not a second cap, and not a second vocabulary to page by: it is the SAME fact shown= / capped= / next_offset= carry, restated from the other end (what this page did not print). Page with limit= and offset=; the more element is absent exactly when this page reached the end of the hit list. COMPLETENESS: complete= on the root (value 1) means this listing is EXHAUSTIVE and a consumer need not re-derive it: every occurrence of the symbol in every TEXT blob of every scanned ref's full tree is printed above — nothing was capped or paged out, and no blob was oversized (over the 2 MB blob ceiling), missing or cut short by the stream. The denominator is refs_scanned= plus HEAD, under SCOPE above (local heads only), so with complete= present a ref absent from the rows genuinely lacks the symbol in its committed tree. Binary blobs are outside the claim (a text symbol cannot occur in one); an oversized TEXT blob suppresses the claim instead of being silently skipped. Its ABSENCE claims nothing. raise the default cap with limit=N (offset=M pages) -->
<whereis sym="computeOnePairOverlap" on-head="1" refs_scanned="106" blobs="3034" hits="5009" head_labels="index" shown="60" capped="1" at="700e51d49">
<history probed="1" head="700e51d49" commits="682" removed-names="22714"/>
<fate sym="computeOnePairOverlap" v="removed" commit="b2120f201" date="2026-08-14" p="docs/captures/COMMANDS_showcase_2026-08-12.md" note="the newest commit reachable from HEAD that removed a line carrying this name — so for a name HEAD no longer has, that is when it left"/>
<hit ref="HEAD" tip="700e51d49" date="2026-08-20" p="src/mergescout.h" l="528" kind="def" t="inline PairOverlap computeOnePairOverlap( std::size_t a, std::size_t b, const Arm&amp; armA, const Arm&amp; armB )"/>
<hit ref="HEAD" tip="700e51d49" date="2026-08-20" p="src/lanes.h" l="17" kind="ref" t="// and the landing order are mergescout::computeOnePairOverlap / computeOverlaps / landingOrder, fed SYNTHETIC"/>
<hit ref="HEAD" tip="700e51d49" date="2026-08-20" p="src/lanes.h" l="65" kind="ref" t="//   same_file_risk[] — different keys, same file. AGGREGATED PER FILE: computeOnePairOverlap is a nested loop"/>
<hit ref="HEAD" tip="700e51d49" date="2026-08-20" p="src/mergescout.h" l="555" kind="ref" t="pairs.push_back( computeOnePairOverlap( a, b, arms[a], arms[b] ) );"/>
<hit ref="HEAD" tip="700e51d49" date="2026-08-20" p="bench/nestcal/r1-2026-08-07/post-ripwire-src.tsv" l="1588" kind="ref" t="mergescout.h::mergescout::computeOnePairOverlap&#9;3&#9;0&#9;0&#9;5&#9;7&#9;19"/>
<hit ref="HEAD" tip="700e51d49" date="2026-08-20" p="bench/nestcal/r1-2026-08-07/pre-ripwire-src.tsv" l="1588" kind="ref" t="mergescout.h::mergescout::computeOnePairOverlap&#9;4&#9;1&#9;1&#9;5&#9;7&#9;19"/>
<hit ref="HEAD" tip="700e51d49" date="2026-08-20" p="bench/recalleval/snapshot.mdpack" l="14503" kind="ref" t="## `./build/ripwire . --whereis=computeOnePairOverlap --with-history`"/>
<hit ref="HEAD" tip="700e51d49" date="2026-08-20" p="bench/recalleval/snapshot.mdpack" l="14511" kind="ref" t="&lt;whereis sym=&quot;computeOnePairOverlap&quot; on-head=&quot;1&quot; refs_scanned=&quot;0&quot; blobs=&quot;1047&quot; hits=&quot;19&quot; head_labels=&quot;index&quot; shown=&quot;19&qu … [line truncated: 56 more bytes on this line]
<hit ref="HEAD" tip="700e51d49" date="2026-08-20" p="bench/recalleval/snapshot.mdpack" l="14513" kind="ref" t="&lt;fate sym=&quot;computeOnePairOverlap&quot; v=&quot;removed&quot; commit=&quot;93dbc7972&quot; date=&quot;2026-08-01&quot; p=&quot;docs/captures/COMMANDS_showcase_2026-08-01.md&quot; not … [line truncated: 157 more bytes on this line]
<hit ref="HEAD" tip="700e51d49" date="2026-08-20" p="bench/recalleval/snapshot.mdpack" l="14514" kind="ref" t="&lt;hit ref=&quot;HEAD&quot; tip=&quot;bc09d0260&quot; date=&quot;2026-08-01&quot; p=&quot;src/mergescout.h&quot; l=&quot;470&quot; kind=&quot;def&quot; t=&quot;inline PairOverlap computeOn … [line truncated: 108 more bytes on this line]
<hit ref="HEAD" tip="700e51d49" date="2026-08-20" p="bench/recalleval/snapshot.mdpack" l="14515" kind="ref" t="&lt;hit ref=&quot;HEAD&quot; tip=&quot;bc09d0260&quot; date=&quot;2026-08-01&quot; p=&quot;src/lanes.h&quot; l=&quot;17&quot; kind=&quot;ref&quot; t=&quot;// and the landing order are merge … [line truncated: 90 more bytes on this line]
<hit ref="HEAD" tip="700e51d49" date="2026-08-20" p="bench/recalleval/snapshot.mdpack" l="14516" kind="ref" t="&lt;hit ref=&quot;HEAD&quot; tip=&quot;bc09d0260&quot; date=&quot;2026-08-01&quot; p=&quot;src/lanes.h&quot; l=&quot;64&quot; kind=&quot;ref&quot; t=&quot;//   same_file_risk[] — differen … [line truncated: 92 more bytes on this line]
<hit ref="HEAD" tip="700e51d49" date="2026-08-20" p="bench/recalleval/snapshot.mdpack" l="14517" kind="ref" t="&lt;hit ref=&quot;HEAD&quot; tip=&quot;bc09d0260&quot; date=&quot;2026-08-01&quot; p=&quot;src/mergescout.h&quot; l=&quot;487&quot; kind=&quot;ref&quot; t=&quot;pairs.push_back( computeOneP … [line truncated: 53 more bytes on this line]
<hit ref="HEAD" tip="700e51d49" date="2026-08-20" p="bench/recalleval/snapshot.mdpack" l="14518" kind="ref" t="&lt;hit ref=&quot;HEAD&quot; tip=&quot;bc09d0260&quot; date=&quot;2026-08-01&quot; p=&quot;test/showcase_capture.py&quot; l=&quot;190&quot; kind=&quot;ref&quot; t=&quot;add(S4, f&amp;quot;{ … [line truncated: 254 more bytes on this line]
<hit ref="HEAD" tip="700e51d49" date="2026-08-20" p="bench/recalleval/snapshot.mdpack" l="14519" kind="ref" t="&lt;hit ref=&quot;HEAD&quot; tip=&quot;bc09d0260&quot; date=&quot;2026-08-01&quot; p=&quot;docs/captures/COMMANDS_showcase_2026-08-01.md&quot; l=&quot;2211&quot; kind=&quot;ref&quot; t=&quo … [line truncated: 85 more bytes on this line]
<hit ref="HEAD" tip="700e51d49" date="2026-08-20" p="bench/recalleval/snapshot.mdpack" l="14520" kind="ref" t="&lt;hit ref=&quot;HEAD&quot; tip=&quot;bc09d0260&quot; date=&quot;2026-08-01&quot; p=&quot;docs/captures/COMMANDS_showcase_2026-08-01.md&quot; l=&quot;2217&quot; kind=&quot;ref&quot; t=&quo … [line truncated: 283 more bytes on this line]
<hit ref="HEAD" tip="700e51d49" date="2026-08-20" p="bench/recalleval/snapshot.mdpack" l="14521" kind="ref" t="&lt;hit ref=&quot;HEAD&quot; tip=&quot;bc09d0260&quot; date=&quot;2026-08-01&quot; p=&quot;docs/captures/COMMANDS_showcase_2026-08-01.md&quot; l=&quot;2219&quot; kind=&quot;ref&quot; t=&quo … [line truncated: 272 more bytes on this line]
<hit ref="HEAD" tip="700e51d49" date="2026-08-20" p="test/showcase_capture.py" l="228" kind="ref" t="add(S4, f&quot;{BIN} . --whereis=computeOnePairOverlap --with-history&quot;, &quot;Same, plus a git-history &lt;fate&gt; row (never / removed-by-commit) for names no tree carries.&quot;, timeout=600) … [line truncated: 3 more bytes on this line]
<hit ref="HEAD" tip="700e51d49" date="2026-08-20" p="docs/captures/COMMANDS_showcase_2026-08-10.md" l="2319" kind="ref" t="## `./build/ripwire . --whereis=computeOnePairOverlap --with-history`"/>
<hit ref="HEAD" tip="700e51d49" date="2026-08-20" p="docs/captures/COMMANDS_showcase_2026-08-10.md" l="2327" kind="ref" t="&lt;whereis sym=&quot;computeOnePairOverlap&quot; on-head=&quot;1&quot; refs_scanned=&quot;123&quot; blobs=&quot;2414&quot; hits=&quot;2657&quot; head_labels=&quot;index&quot; s … [line truncated: 72 more bytes on this line]
<hit ref="HEAD" tip="700e51d49" date="2026-08-20" p="docs/captures/COMMANDS_showcase_2026-08-10.md" l="2329" kind="ref" t="&lt;fate sym=&quot;computeOnePairOverlap&quot; v=&quot;removed&quot; commit=&quot;5579dd63f&quot; date=&quot;2026-08-09&quot; p=&quot;docs/captures/COMMANDS_showcase_2026-08-09. … [line truncated: 169 more bytes on this line]
<hit ref="HEAD" tip="700e51d49" date="2026-08-20" p="docs/captures/COMMANDS_showcase_2026-08-10.md" l="2330" kind="ref" t="&lt;hit ref=&quot;HEAD&quot; tip=&quot;dd6d9768c&quot; date=&quot;2026-08-10&quot; p=&quot;src/mergescout.h&quot; l=&quot;530&quot; kind=&quot;def&quot; t=&quot;inline PairOverl … [line truncated: 120 more bytes on this line]
<hit ref="HEAD" tip="700e51d49" date="2026-08-20" p="docs/captures/COMMANDS_showcase_2026-08-10.md" l="2331" kind="ref" t="&lt;hit ref=&quot;HEAD&quot; tip=&quot;dd6d9768c&quot; date=&quot;2026-08-10&quot; p=&quot;src/lanes.h&quot; l=&quot;17&quot; kind=&quot;ref&quot; t=&quot;// and the landing ord … [line truncated: 102 more bytes on this line]
<hit ref="HEAD" tip="700e51d49" date="2026-08-20" p="docs/captures/COMMANDS_showcase_2026-08-10.md" l="2332" kind="ref" t="&lt;hit ref=&quot;HEAD&quot; tip=&quot;dd6d9768c&quot; date=&quot;2026-08-10&quot; p=&quot;src/lanes.h&quot; l=&quot;64&quot; kind=&quot;ref&quot; t=&quot;//   same_file_risk[]  … [line truncated: 104 more bytes on this line]
<hit ref="HEAD" tip="700e51d49" date="2026-08-20" p="docs/captures/COMMANDS_showcase_2026-08-10.md" l="2333" kind="ref" t="&lt;hit ref=&quot;HEAD&quot; tip=&quot;dd6d9768c&quot; date=&quot;2026-08-10&quot; p=&quot;src/mergescout.h&quot; l=&quot;557&quot; kind=&quot;ref&quot; t=&quot;pairs.push_back( … [line truncated: 65 more bytes on this line]
<hit ref="HEAD" tip="700e51d49" date="2026-08-20" p="docs/captures/COMMANDS_showcase_2026-08-10.md" l="2334" kind="ref" t="&lt;hit ref=&quot;HEAD&quot; tip=&quot;dd6d9768c&quot; date=&quot;2026-08-10&quot; p=&quot;bench/nestcal/r1-2026-08-07/post-ripwire-src.tsv&quot; l=&quot;1588&quot; kind=&quot;r … [line truncated: 133 more bytes on this line]
… [36 more display lines; full output is 28914 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --flags`

*The dark-content dashboard: gates BUILT but OFF. CHANGED: no longer invents gates from comments/heredocs, so the count only reflects real ifndef/define, CMake option(), and getenv gates.*

`````
<!-- ripwire flags: what is BUILT but DARK here. Three gate patterns in one report: ifndef/define header gates (kind="compile"), CMake option() switches (kind="cmake"), and getenv reads (kind="env", default unset). dark="1" means the default keeps the guarded code out of the build; regions/loc size what it turns off. When one name is BOTH a header gate and a CMake option the CMake default wins (that is what the build passes) and the header shows as an also row. Lexical, not preprocessed: this reports the in-repo default, never the value your build used. dark_gates on this root is the COUNT of dark gates; it was spelled dark until that collided with the child bool. files= is THIS verb's own harvest scan (source + CMakeLists files it read looking for gates) — a wider crawl than the map's indexed corpus, so it will not equal the map's files= -->
<flags gates="66" dark_gates="59" compile="12" cmake="12" env="42" files="1308">
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
… [258 more display lines; full output is 16142 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --flags --flip=RIPWIRE_ASAN`

*Blast radius of turning ONE gate on: live code, symbols, transitive reach, covering tests.*

`````
<!-- ripwire flip: the blast radius of turning ONE gate ON. lights = the code that becomes live: r rows are #if regions, b rows are C++ branch sites (a gate read as a VALUE through a constexpr bool, via= names the binding). hosts = the indexed defs that code sits inside; downstream = what those defs transitively CALL (what starts executing); dependents = what transitively calls THEM. tests = test files reaching the hosts; untested = hosts no test reaches (the honest is it safe answer). An alias MASTER rolls its children in (member rows); flipping a CHILD lights only that child and names its parent. kind=cmake also steers the BUILD graph, which no C++ side analysis follows: those sites are c rows. kind=env is RUNTIME (runtime=1) so every row is conditional at its read. Lexical and single line, never preprocessed: the value lane reads C family source only and treats a file declaring its OWN constant of that name as shadowing the gate's, but a third header's same named constant (included, not redeclared) would still count. A lit site inside no indexed def counts into filescope instead of a host. UNIT: untested= here counts HOSTS (indexed defs this gate lights that no test reaches). The test gate verb spells untested= over impacted SYMBOLS and the seams verb over cross-directory call EDGES, so the three numbers count three different things and must never be compared or summed across verbs. -->
<flip gate="RIPWIRE_ASAN" kind="cmake" default="OFF" dark="1" runtime="0" p="CMakeLists.txt" l="14" family="1" regions="0" loc="0" branches="0" bindings="0" hosts="0" filescope="0" downstream="0" dependents="0" tests="0" untested="0" files="1308">
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
<c p="CMakeLists.txt" l="763"/>
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
{"v":1,"verb":"plan-lanes","at":"700e51d49","root":".","task":"add a --since filter to the doc-drift verb and cover it with tests","source":"partition","requested":3,"lane_count":3,"claim_key":"path+scope+name","on_conflict":"producing-lane-rebases","corpus":{"files":1304,"symbols":11348,"edges":139 … [line truncated: 351 more bytes on this line]
"symbols":[{"p":"./src/docdrift.h","n":"computeDocDrift","scope":"docdrift","l":2283,"id":"./src/docdrift.h::docdrift::computeDocDrift"},
{"p":"./src/docdrift.h","n":"kDocDriftLegend","scope":"docdrift","l":2560,"id":"./src/docdrift.h::docdrift::kDocDriftLegend"},
{"p":"./src/docdrift.h","n":"writeDocDriftPage","scope":"docdrift","l":2663,"id":"./src/docdrift.h::docdrift::writeDocDriftPage"},
{"p":"./src/main.cpp","n":"runDocDrift","scope":"","l":9535,"id":null},
{"p":"./src/mcprefusal.h","n":"kMcpRequiredFields","scope":"rw::mcprefuse","l":64,"id":"./src/mcprefusal.h::rw::mcprefuse::kMcpRequiredFields"},
{"p":"./src/mcpverbs.h","n":"docDriftText","scope":"rw","l":464,"id":"./src/mcpverbs.h::rw::docDriftText"}]},"lanes":[{"id":"lane-0","task":"add a --since filter to the doc-drift verb and cover it with tests","claims":{"symbols":[{"p":"./src/situ.h","n":"kTestGateLegend","scope":"rw","key":"06e66a3c … [line truncated: 169 more bytes on this line]
{"p":"./src/mcp.h","n":"isMcpEditVerb","scope":"rw","key":"29a5a2524a95d6c2","id":"./src/mcp.h::rw::isMcpEditVerb","id_addressable":true,"id_collides_with":0,"l":433,"ord":0,"overloads":1,"amb":0,"cx":3,"ccx":3,"churn":22,"tested":0},
{"p":"./src/mcprefusal.h","n":"notFound","scope":"rw::mcprefuse","key":"2f350cb55c4c61ac","id":"./src/mcprefusal.h::rw::mcprefuse::notFound","id_addressable":true,"id_collides_with":0,"l":801,"ord":0,"overloads":1,"amb":0,"cx":4,"ccx":3,"churn":9,"tested":0},
{"p":"./src/recall.h","n":"docFileMask","scope":"rw","key":"3149a219f599664c","id":"./src/recall.h::rw::docFileMask","id_addressable":true,"id_collides_with":0,"l":104,"ord":0,"overloads":1,"amb":0,"cx":4,"ccx":4,"churn":9,"tested":0},
{"p":"./src/main.cpp","n":"kCochangeGroupLegend","scope":"","key":"55e325f58393414b","id":null,"id_addressable":false,"id_collides_with":0,"l":4286,"ord":0,"overloads":1,"amb":0,"cx":0,"ccx":0,"churn":141,"tested":0},
{"p":"./src/main.cpp","n":"jsonUnsupportedVerb","scope":"","key":"6e4dbe9b6d8ebac4","id":null,"id_addressable":false,"id_collides_with":0,"l":13684,"ord":0,"overloads":1,"amb":30,"cx":77,"ccx":77,"churn":141,"tested":0},
{"p":"./src/testmap.h","n":"scriptGatesUnmodelledCount","scope":"rw","key":"98c4487e2e9e08bc","id":"./src/testmap.h::rw::scriptGatesUnmodelledCount","id_addressable":true,"id_collides_with":0,"l":360,"ord":0,"overloads":1,"amb":0,"cx":5,"ccx":4,"churn":4,"tested":0},
{"p":"./src/main.cpp","n":"scanReportVerbPrecedence","scope":"","key":"9ab981e987e8108e","id":null,"id_addressable":false,"id_collides_with":0,"l":13515,"ord":0,"overloads":1,"amb":28,"cx":7,"ccx":10,"churn":141,"tested":0},
{"p":"./src/ensemble.h","n":"kEnsembleChurnSince","scope":"ensemble","key":"a34fc78c05bf56a8","id":"./src/ensemble.h::ensemble::kEnsembleChurnSince","id_addressable":true,"id_collides_with":0,"l":115,"ord":0,"overloads":1,"amb":0,"cx":0,"ccx":0,"churn":10,"tested":0},
{"p":"./src/layout.h","n":"layoutContractBroken","scope":"layout","key":"c66e49d8b044e1e9","id":"./src/layout.h::layout::layoutContractBroken","id_addressable":true,"id_collides_with":0,"l":1007,"ord":0,"overloads":1,"amb":0,"cx":3,"ccx":3,"churn":12,"tested":0},
{"p":"./src/mcp.h","n":"dispatchMcpLine","scope":"rw","key":"d63db6944aa504a7","id":"./src/mcp.h::rw::dispatchMcpLine","id_addressable":true,"id_collides_with":0,"l":499,"ord":0,"overloads":1,"amb":140,"cx":223,"ccx":427,"churn":22,"tested":0},
{"p":"./src/commentcoherence.h","n":"kCommentCoherenceLegend","scope":"rw","key":"d66a8e164f6323fd","id":"./src/commentcoherence.h::rw::kCommentCoherenceLegend","id_addressable":true,"id_collides_with":0,"l":300,"ord":0,"overloads":1,"amb":0,"cx":0,"ccx":0,"churn":4,"tested":0}],
"files":[{"p":"./src/commentcoherence.h","symbols":1,"churn":4,"ccx":0,"hotspot_rank":103},
{"p":"./src/ensemble.h","symbols":1,"churn":10,"ccx":0,"hotspot_rank":39},
{"p":"./src/layout.h","symbols":1,"churn":12,"ccx":3,"hotspot_rank":11},
{"p":"./src/main.cpp","symbols":3,"churn":141,"ccx":87,"hotspot_rank":1},
{"p":"./src/mcp.h","symbols":2,"churn":22,"ccx":430,"hotspot_rank":8},
{"p":"./src/mcprefusal.h","symbols":1,"churn":9,"ccx":3,"hotspot_rank":33},
{"p":"./src/recall.h","symbols":1,"churn":9,"ccx":4,"hotspot_rank":32},
{"p":"./src/situ.h","symbols":1,"churn":6,"ccx":0,"hotspot_rank":49},
{"p":"./src/testmap.h","symbols":1,"churn":4,"ccx":4,"hotspot_rank":95}]},"blast_radius":{"reaches":18,"files_total":6,"capped":false,"files":["./src/main.cpp","./src/mcp.h","./src/mcpserver.h","./src/mcpverbs.h","./src/recall.h","./src/situ.h"]},"tests_to_run":[],
"tests_total":0,"tests_capped":false,"tests_granularity":"claimed-symbols","untested":18,"module_span":6,"notes":[]},
{"id":"lane-1","task":"add a --since filter to the doc-drift verb and cover it with tests","claims":{"symbols":[{"p":"./src/cli.h","n":"kPagingHonoringVerbs","scope":"rw","key":"1624b02e9104560e","id":"./src/cli.h::rw::kPagingHonoringVerbs","id_addressable":true,"id_collides_with":0,"l":2440,"ord":0 … [line truncated: 61 more bytes on this line]
{"p":"./src/gitmine.h","n":"gitWindowBoundarySha","scope":"rw","key":"18627516699d7062","id":"./src/gitmine.h::rw::gitWindowBoundarySha","id_addressable":true,"id_collides_with":0,"l":1175,"ord":0,"overloads":1,"amb":3,"cx":3,"ccx":2,"churn":11,"tested":0},
… [64 more display lines; full output is 18546 bytes on 1 raw line(s)]
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
{"v":1,"verb":"plan-lanes","at":"700e51d49","root":".","task":null,"source":"brief","requested":3,"lane_count":3,"claim_key":"path+scope+name","on_conflict":"producing-lane-rebases","corpus":{"files":1304,"symbols":11348,"edges":13926,"ambiguous":5517,"unresolved":3202},"carve":null,"core":{"files": … [line truncated: 3 more bytes on this line]
"symbols":[]},"lanes":[{"id":"lane-0","task":"add a --since filter to the doc-drift verb","claims":{"symbols":[{"p":"./src/docdrift.h","n":"recordUnchecked","scope":"docdrift","key":"12641dab14abc8fd","id":"./src/docdrift.h::docdrift::recordUnchecked","id_addressable":true,"id_collides_with":0,"l":2 … [line truncated: 72 more bytes on this line]
{"p":"./src/docdrift.h","n":"sortWeakGroupsByPath","scope":"docdrift","key":"1944ba506280ff80","id":"./src/docdrift.h::docdrift::sortWeakGroupsByPath","id_addressable":true,"id_collides_with":0,"l":2243,"ord":0,"overloads":1,"amb":0,"cx":1,"ccx":0,"churn":11,"tested":0},
{"p":"./src/mcpverbs.h","n":"docDriftText","scope":"rw","key":"1fa68e8d93c05a59","id":"./src/mcpverbs.h::rw::docDriftText","id_addressable":true,"id_collides_with":0,"l":464,"ord":0,"overloads":1,"amb":0,"cx":1,"ccx":0,"churn":32,"tested":0},
{"p":"./src/cli.h","n":"kViewFlags","scope":"rw","key":"2a2f2487082cc6d8","id":"./src/cli.h::rw::kViewFlags","id_addressable":true,"id_collides_with":0,"l":1987,"ord":0,"overloads":1,"amb":0,"cx":0,"ccx":0,"churn":86,"tested":0},
{"p":"./src/recall.h","n":"docFileMask","scope":"rw","key":"3149a219f599664c","id":"./src/recall.h::rw::docFileMask","id_addressable":true,"id_collides_with":0,"l":104,"ord":0,"overloads":1,"amb":0,"cx":4,"ccx":4,"churn":9,"tested":0},
{"p":"./src/docdrift.h","n":"writeDocDriftPage","scope":"docdrift","key":"380b7de5df1cfd73","id":"./src/docdrift.h::docdrift::writeDocDriftPage","id_addressable":true,"id_collides_with":0,"l":2663,"ord":0,"overloads":1,"amb":2,"cx":9,"ccx":10,"churn":11,"tested":0},
{"p":"./src/docdrift.h","n":"computeDocDrift","scope":"docdrift","key":"3b19cc3d8996c3b2","id":"./src/docdrift.h::docdrift::computeDocDrift","id_addressable":true,"id_collides_with":0,"l":2283,"ord":0,"overloads":1,"amb":10,"cx":20,"ccx":33,"churn":11,"tested":0},
{"p":"./src/ensemble.h","n":"kEnsembleChurnSince","scope":"ensemble","key":"a34fc78c05bf56a8","id":"./src/ensemble.h::ensemble::kEnsembleChurnSince","id_addressable":true,"id_collides_with":0,"l":115,"ord":0,"overloads":1,"amb":0,"cx":0,"ccx":0,"churn":10,"tested":0},
{"p":"./src/mcprefusal.h","n":"kMcpRequiredFields","scope":"rw::mcprefuse","key":"c5f1ad5fc3a12368","id":"./src/mcprefusal.h::rw::mcprefuse::kMcpRequiredFields","id_addressable":true,"id_collides_with":0,"l":64,"ord":0,"overloads":1,"amb":0,"cx":0,"ccx":0,"churn":9,"tested":0},
{"p":"./src/mcpverbs.h","n":"unknownSubVerbRefusal","scope":"rw","key":"e336d39b0a6addea","id":"./src/mcpverbs.h::rw::unknownSubVerbRefusal","id_addressable":true,"id_collides_with":0,"l":3288,"ord":0,"overloads":1,"amb":2,"cx":3,"ccx":2,"churn":32,"tested":0},
{"p":"./src/main.cpp","n":"runDocDrift","scope":"","key":"ebf80a749e6eca28","id":null,"id_addressable":false,"id_collides_with":0,"l":9535,"ord":0,"overloads":1,"amb":0,"cx":4,"ccx":3,"churn":141,"tested":0},
{"p":"./src/docdrift.h","n":"kDocDriftLegend","scope":"docdrift","key":"ff2ba74637bbbebf","id":"./src/docdrift.h::docdrift::kDocDriftLegend","id_addressable":true,"id_collides_with":0,"l":2560,"ord":0,"overloads":1,"amb":0,"cx":0,"ccx":0,"churn":11,"tested":0}],
"files":[{"p":"./src/cli.h","symbols":1,"churn":86,"ccx":0,"hotspot_rank":6},
{"p":"./src/docdrift.h","symbols":5,"churn":11,"ccx":44,"hotspot_rank":13},
{"p":"./src/ensemble.h","symbols":1,"churn":10,"ccx":0,"hotspot_rank":39},
{"p":"./src/main.cpp","symbols":1,"churn":141,"ccx":3,"hotspot_rank":1},
{"p":"./src/mcprefusal.h","symbols":1,"churn":9,"ccx":0,"hotspot_rank":33},
{"p":"./src/mcpverbs.h","symbols":2,"churn":32,"ccx":2,"hotspot_rank":7},
{"p":"./src/recall.h","symbols":1,"churn":9,"ccx":4,"hotspot_rank":32}]},"blast_radius":{"reaches":11,"files_total":6,"capped":false,"files":["./src/docdrift.h","./src/main.cpp","./src/mcp.h","./src/mcpserver.h","./src/mcpverbs.h","./src/recall.h"]},"tests_to_run":[],
"tests_total":0,"tests_capped":false,"tests_granularity":"claimed-symbols","untested":11,"module_span":9,"notes":[]},
{"id":"lane-1","task":"add the CLI parse arm and help text for the new filter","claims":{"symbols":[{"p":"./src/gitmine.h","n":"churnWindowStamp","scope":"rw","key":"0000d19d7c13cbc7","id":"./src/gitmine.h::rw::churnWindowStamp","id_addressable":true,"id_collides_with":0,"l":1687,"ord":0,"overloads" … [line truncated: 49 more bytes on this line]
{"p":"./scripts/optremarks.py","n":"main","scope":"","key":"01b3b880f77d1512","id":null,"id_addressable":false,"id_collides_with":69,"l":178,"ord":0,"overloads":1,"amb":0,"cx":23,"ccx":31,"churn":3,"tested":0},
{"p":"./src/cli.h","n":"kViewFlags","scope":"rw","key":"2a2f2487082cc6d8","id":"./src/cli.h::rw::kViewFlags","id_addressable":true,"id_collides_with":0,"l":1987,"ord":0,"overloads":1,"amb":0,"cx":0,"ccx":0,"churn":86,"tested":0},
{"p":"./src/mcpverbs.h","n":"whereisText","scope":"rw","key":"39588f57bd7b46b5","id":"./src/mcpverbs.h::rw::whereisText","id_addressable":true,"id_collides_with":0,"l":418,"ord":0,"overloads":1,"amb":0,"cx":2,"ccx":1,"churn":32,"tested":0},
{"p":"./docs/docs_commands_build.py","n":"main","scope":"","key":"4015853681ded3bc","id":null,"id_addressable":false,"id_collides_with":69,"l":527,"ord":0,"overloads":1,"amb":0,"cx":19,"ccx":28,"churn":5,"tested":0},
{"p":"./src/mcprefusal.h","n":"kMcpValueFields","scope":"rw::mcprefuse","key":"4a7106e488a2aa80","id":"./src/mcprefusal.h::rw::mcprefuse::kMcpValueFields","id_addressable":true,"id_collides_with":0,"l":266,"ord":0,"overloads":1,"amb":0,"cx":0,"ccx":0,"churn":9,"tested":0},
{"p":"./src/query.h","n":"tryParsePredicateOnAll","scope":"query","key":"786acc4dbfec612b","id":"./src/query.h::query::tryParsePredicateOnAll","id_addressable":false,"id_collides_with":1,"l":107,"ord":0,"overloads":2,"amb":0,"cx":1,"ccx":0,"churn":8,"tested":0},
{"p":"./src/mcpverbs.h","n":"lensSurfaceIds","scope":"rw","key":"995243b3e267c798","id":"./src/mcpverbs.h::rw::lensSurfaceIds","id_addressable":true,"id_collides_with":0,"l":1306,"ord":0,"overloads":1,"amb":0,"cx":1,"ccx":0,"churn":32,"tested":0},
{"p":"./src/ingest.h","n":"kDefaultMaxFileBytes","scope":"rw","key":"9d3ec8a557b7d7dc","id":"./src/ingest.h::rw::kDefaultMaxFileBytes","id_addressable":true,"id_collides_with":0,"l":32,"ord":0,"overloads":1,"amb":0,"cx":0,"ccx":0,"churn":19,"tested":0},
… [59 more display lines; full output is 17175 bytes on 1 raw line(s)]
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
<!-- root= on this element is the crawl root every p= below is RELATIVE to (single-root runs only; absent => p= is the path ingest itself used, unchanged). -->
<layout sym="Symbol" found="1" defs="1" mirror="single" asserts="1" conflicts="0" scanned="420" root=".">
<def p="src/model.h" l="186" agg="struct" modeled="0" fields="23">
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
<f n="testScope" ty="std::uint8_t" sz="1" al="1"/>
<f n="name" ty="std::string" sized="0"/>
<f n="scope" ty="std::string" sized="0"/>
<caveat k="compound-type" d="evWhy: std::array&lt;std::uint8_t, kEvWhyTagCount&gt;"/>
<caveat k="unknown-type" d="evWhy: std::array&lt;std::uint8_t, kEvWhyTagCount&gt;" count="3"/>
</def>
<assert p="src/model.h" l="340" kind="mention" t="static_assert( sizeof( Symbol ) == 64 + 2 * sizeof( std::string ), &quot;Symbol size changed — verify the new field uses the smallest type + is grouped (SoA); see model.h&quot; )"/>
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
<!-- ripwire doc drift: the CHECKABLE anchors in this repo's markdown, verified against the live index, reporting only the ones that no longer hold. Four kinds: file:line refs (missing-file / past-eof / line-moved, the last only when the doc names a symbol on that line), backticked symbol mentions (undefined), `= N` constants and `[N]` array extents (value/extent vs the declaration). Every lane under reports on purpose: a name is stale only when it occurs NOWHERE in the code as an identifier, and a number is compared only against a declaration shaped literal the corpus binds uniquely. checked + unchecked == anchors: nothing is dropped silently, and the unchecked rows say what was not proved. Read why="undefined" precisely: it says the name is defined NOWHERE in this repo, which is not the same as DELETED — in a plan or design doc naming work not yet built, that is expected rather than rot. Run with the with_history flag to have git history separate the two: the lane then reports why="deleted" with the commit that removed the name, and downgrades a name this repo never had to unchecked r="never in history". A failed anchor the AUTHOR DATED is split out as kind="dated-record" and counted in dated= rather than drift=: an audit finding, a ledger row or an as-of-DATE hedge records what was true then, so drift= is the LIVE rot and drift + dated is every anchor that no longer holds. rec= names the evidence (line / block / title / stamp), and a doc that never writes its own date anywhere a machine can read reports LIVE — the lane reads dating marks, it does not guess genre. Attribute vocabulary, one name one meaning: at= appears ONLY on this root element and is the commit the run was measured against (short sha, plus dirty when the tree had uncommitted changes); ref= is the anchor as the DOC writes it; got= is what the corpus actually says; and tgt= is the corpus SITE backing got= (a path, or path:line). On the <a/> rows k= and kind= are DIFFERENT things and both are kept: k= is the ANCHOR kind (file-line / symbol / const / array), kind= is the record classification (dated-record). k= cannot be renamed to kind= here for the obvious reason that kind= is already taken on the same element; note that in the ranked map the same k= spelling is a PageRank score instead. Docs are ordered by LIVE drift descending (path breaks ties), so the worst rot leads and a fully dated doc, which is drift zero by construction, sinks on the same key. Prose claims, Status lines and dates are NOT checked. A `path:A-B` RANGE gets one more structural check: why="range-straddles" fires when A's innermost symbol does not reach B (got= then names whatever occupies B instead, tgt= that site), regardless of whether the doc names a symbol. weak-file-line, the one unchecked reason that names no symbol, gets a FREE disclosure instead of a verdict: <weak-file-line p= n=> groups, one per doc, list every such anchor whose line DOES sit inside an indexed symbol, and each <w> row's resolves-to= names it — the verb still does not know if that is the symbol the doc meant. This section sits beside, not inside, the <doc> rows: a doc can appear in it while still counting toward clean=, and every row it lists still counts once in the unchecked r="weak-file-line" tally below. FOUR COUNTERS on this element name four DIFFERENT populations, stated here because one of them openly disagrees with a number the map reports elsewhere. docs= is the DOCUMENTS scanned for anchors (markdown by extension, after any filter); it is the denominator of the doc rows below. clean= is how many of those docs came out with NO failed anchor — drift and dated both zero for that doc — so docs minus clean is exactly the number of <doc> rows below, before any paging window is applied. A doc whose anchors were all unchecked, or all prose, is clean here: clean means nothing was found rotten, not that everything was verified. prose= is the anchors dropped as prose, so it is SUBTRACTED from anchors= rather than added to it, and the verb does not claim to have checked them; only the VALUE shapes (`= N` and `[N]`) can be dropped this way, and the drop is itself a corpus lookup — the name was searched for and not found in code — not a pre-check guess. corpus= is the file population the anchors were checked AGAINST, and it is its OWN population rather than a relation to the map's files=: the indexed files this walk could re-read, PLUS a fixed set of config, shader and build-file extensions (CMakeLists.txt, .cmake, .yml/.yaml, .toml, .metal/.glsl/.hlsl and the like — an extension whitelist, never a content sniff), MINUS every file this walk could not open or that exceeded its own 4 MiB read ceiling, which is dropped silently and never counted. So corpus= is USUALLY larger than files= and that is the normal case, but it is not always: a crawl run whose max file size ceiling was raised above 4 MiB indexes files this walk still refuses, and a file the index lists but this run cannot open is counted by one and not the other. Neither number is wrong. corpus="0" means the corpus scan never ran at all, which happens only when the docs raised no anchor SHAPE whatsoever — prose ones included — so anchors="0" beside a non-zero prose= still scanned, and still reports the corpus it scanned. -->
<doc-drift docs="134" clean="119" anchors="1389" checked="525" unchecked="864" drift="44" dated="14" prose="9" corpus="1331" at="700e51d49">
<doc p="docs/COMMANDS.md" anchors="74" checked="21" drift="21" dated="0">
<a k="const" l="2370" c="53" why="const-value" ref="kDriftedLimit = 10" want="10" got="15" tgt="test/docdriftfix/code.h:11"/>
<a k="array" l="2371" c="54" why="array-extent" ref="kDriftedTable[16]" want="16" got="18" tgt="test/docdriftfix/code.h:14"/>
<a k="const" l="2372" c="53" why="const-value" ref="kDriftedLimit = 10" want="10" got="15" tgt="test/docdriftfix/code.h:11"/>
<a k="array" l="2373" c="54" why="array-extent" ref="kDriftedTable[16]" want="16" got="18" tgt="test/docdriftfix/code.h:14"/>
<a k="const" l="2374" c="53" why="const-value" ref="kDriftedLimit = 10" want="10" got="15" tgt="test/docdriftfix/code.h:11"/>
<a k="const" l="2375" c="53" why="const-value" ref="kDriftedLimit = 10" want="10" got="15" tgt="test/docdriftfix/code.h:11"/>
<a k="array" l="2376" c="54" why="array-extent" ref="kDriftedTable[16]" want="16" got="18" tgt="test/docdriftfix/code.h:14"/>
<a k="const" l="2377" c="53" why="const-value" ref="kDriftedLimit = 10" want="10" got="15" tgt="test/docdriftfix/code.h:11"/>
<a k="array" l="2378" c="54" why="array-extent" ref="kDriftedTable[16]" want="16" got="18" tgt="test/docdriftfix/code.h:14"/>
<a k="const" l="2379" c="53" why="const-value" ref="kDriftedLimit = 10" want="10" got="15" tgt="test/docdriftfix/code.h:11"/>
<a k="array" l="2380" c="54" why="array-extent" ref="kDriftedTable[16]" want="16" got="18" tgt="test/docdriftfix/code.h:14"/>
<a k="const" l="2408" c="53" why="const-value" ref="kDriftedLimit = 10" want="10" got="15" tgt="test/docdriftfix/code.h:11"/>
<more drift="9"/>
</doc>
<doc p="test/docdriftfix/NOTES.md" anchors="30" checked="21" drift="7" dated="0">
<a k="file-line" l="9" c="64" why="line-moved" ref="code.h:23" sym="stableHelper" got="movedHelper" tgt="test/docdriftfix/code.h:17"/>
<a k="file-line" l="10" c="58" why="past-eof" ref="code.h:900" sym="stableHelper" got="33 lines" tgt="test/docdriftfix/code.h"/>
<a k="file-line" l="11" c="53" why="missing-file" ref="deletedFile.h:12"/>
<a k="const" l="26" c="29" why="const-value" ref="kDriftedLimit = 10" want="10" got="15" tgt="test/docdriftfix/code.h:11"/>
<a k="array" l="28" c="49" why="array-extent" ref="kDriftedTable[16]" want="16" got="18" tgt="test/docdriftfix/code.h:14"/>
<a k="array" l="29" c="61" why="array-extent" ref="[16]" want="16" got="18" tgt="test/docdriftfix/code.h:14"/>
<a k="file-line" l="42" c="49" why="range-straddles" ref="code.h:18-23" got="movedHelper" tgt="test/docdriftfix/code.h:23"/>
</doc>
<doc p="PLAN.md" anchors="104" checked="64" drift="4" dated="1">
<a k="file-line" l="407" c="63" why="line-moved" kind="dated-record" rec="block" ref="naminglens.h:526" sym="checkNameShape" got="(file scope)" tgt="src/naminglens.h:618"/>
<a k="file-line" l="553" c="81" why="line-moved" ref="ingest.cpp:7175" sym="astQuery" got="(file scope)" tgt="src/ingest.cpp:12711"/>
<a k="file-line" l="1014" c="71" why="line-moved" ref="src/ingest.cpp:477" sym="jsonNestsTooDeep" got="(file scope)" tgt="src/ingest.cpp:600"/>
… [104 more display lines; full output is 17077 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --doc-drift --gateability`

*The finishable to-do list: docs whose LIVE failing anchors a date-stamp would reclassify.*

`````
<!-- ripwire doc drift: the CHECKABLE anchors in this repo's markdown, verified against the live index, reporting only the ones that no longer hold. Four kinds: file:line refs (missing-file / past-eof / line-moved, the last only when the doc names a symbol on that line), backticked symbol mentions (undefined), `= N` constants and `[N]` array extents (value/extent vs the declaration). Every lane under reports on purpose: a name is stale only when it occurs NOWHERE in the code as an identifier, and a number is compared only against a declaration shaped literal the corpus binds uniquely. checked + unchecked == anchors: nothing is dropped silently, and the unchecked rows say what was not proved. Read why="undefined" precisely: it says the name is defined NOWHERE in this repo, which is not the same as DELETED — in a plan or design doc naming work not yet built, that is expected rather than rot. Run with the with_history flag to have git history separate the two: the lane then reports why="deleted" with the commit that removed the name, and downgrades a name this repo never had to unchecked r="never in history". A failed anchor the AUTHOR DATED is split out as kind="dated-record" and counted in dated= rather than drift=: an audit finding, a ledger row or an as-of-DATE hedge records what was true then, so drift= is the LIVE rot and drift + dated is every anchor that no longer holds. rec= names the evidence (line / block / title / stamp), and a doc that never writes its own date anywhere a machine can read reports LIVE — the lane reads dating marks, it does not guess genre. Attribute vocabulary, one name one meaning: at= appears ONLY on this root element and is the commit the run was measured against (short sha, plus dirty when the tree had uncommitted changes); ref= is the anchor as the DOC writes it; got= is what the corpus actually says; and tgt= is the corpus SITE backing got= (a path, or path:line). On the <a/> rows k= and kind= are DIFFERENT things and both are kept: k= is the ANCHOR kind (file-line / symbol / const / array), kind= is the record classification (dated-record). k= cannot be renamed to kind= here for the obvious reason that kind= is already taken on the same element; note that in the ranked map the same k= spelling is a PageRank score instead. Docs are ordered by LIVE drift descending (path breaks ties), so the worst rot leads and a fully dated doc, which is drift zero by construction, sinks on the same key. Prose claims, Status lines and dates are NOT checked. A `path:A-B` RANGE gets one more structural check: why="range-straddles" fires when A's innermost symbol does not reach B (got= then names whatever occupies B instead, tgt= that site), regardless of whether the doc names a symbol. weak-file-line, the one unchecked reason that names no symbol, gets a FREE disclosure instead of a verdict: <weak-file-line p= n=> groups, one per doc, list every such anchor whose line DOES sit inside an indexed symbol, and each <w> row's resolves-to= names it — the verb still does not know if that is the symbol the doc meant. This section sits beside, not inside, the <doc> rows: a doc can appear in it while still counting toward clean=, and every row it lists still counts once in the unchecked r="weak-file-line" tally below. FOUR COUNTERS on this element name four DIFFERENT populations, stated here because one of them openly disagrees with a number the map reports elsewhere. docs= is the DOCUMENTS scanned for anchors (markdown by extension, after any filter); it is the denominator of the doc rows below. clean= is how many of those docs came out with NO failed anchor — drift and dated both zero for that doc — so docs minus clean is exactly the number of <doc> rows below, before any paging window is applied. A doc whose anchors were all unchecked, or all prose, is clean here: clean means nothing was found rotten, not that everything was verified. prose= is the anchors dropped as prose, so it is SUBTRACTED from anchors= rather than added to it, and the verb does not claim to have checked them; only the VALUE shapes (`= N` and `[N]`) can be dropped this way, and the drop is itself a corpus lookup — the name was searched for and not found in code — not a pre-check guess. corpus= is the file population the anchors were checked AGAINST, and it is its OWN population rather than a relation to the map's files=: the indexed files this walk could re-read, PLUS a fixed set of config, shader and build-file extensions (CMakeLists.txt, .cmake, .yml/.yaml, .toml, .metal/.glsl/.hlsl and the like — an extension whitelist, never a content sniff), MINUS every file this walk could not open or that exceeded its own 4 MiB read ceiling, which is dropped silently and never counted. So corpus= is USUALLY larger than files= and that is the normal case, but it is not always: a crawl run whose max file size ceiling was raised above 4 MiB indexes files this walk still refuses, and a file the index lists but this run cannot open is counted by one and not the other. Neither number is wrong. corpus="0" means the corpus scan never ran at all, which happens only when the docs raised no anchor SHAPE whatsoever — prose ones included — so anchors="0" beside a non-zero prose= still scanned, and still reports the corpus it scanned. -->
<doc-drift docs="134" clean="119" anchors="1389" checked="525" unchecked="864" drift="44" dated="14" prose="9" corpus="1331" at="700e51d49">
<doc p="docs/COMMANDS.md" anchors="74" checked="21" drift="21" dated="0">
<a k="const" l="2370" c="53" why="const-value" ref="kDriftedLimit = 10" want="10" got="15" tgt="test/docdriftfix/code.h:11"/>
<a k="array" l="2371" c="54" why="array-extent" ref="kDriftedTable[16]" want="16" got="18" tgt="test/docdriftfix/code.h:14"/>
<a k="const" l="2372" c="53" why="const-value" ref="kDriftedLimit = 10" want="10" got="15" tgt="test/docdriftfix/code.h:11"/>
<a k="array" l="2373" c="54" why="array-extent" ref="kDriftedTable[16]" want="16" got="18" tgt="test/docdriftfix/code.h:14"/>
<a k="const" l="2374" c="53" why="const-value" ref="kDriftedLimit = 10" want="10" got="15" tgt="test/docdriftfix/code.h:11"/>
<a k="const" l="2375" c="53" why="const-value" ref="kDriftedLimit = 10" want="10" got="15" tgt="test/docdriftfix/code.h:11"/>
<a k="array" l="2376" c="54" why="array-extent" ref="kDriftedTable[16]" want="16" got="18" tgt="test/docdriftfix/code.h:14"/>
<a k="const" l="2377" c="53" why="const-value" ref="kDriftedLimit = 10" want="10" got="15" tgt="test/docdriftfix/code.h:11"/>
<a k="array" l="2378" c="54" why="array-extent" ref="kDriftedTable[16]" want="16" got="18" tgt="test/docdriftfix/code.h:14"/>
<a k="const" l="2379" c="53" why="const-value" ref="kDriftedLimit = 10" want="10" got="15" tgt="test/docdriftfix/code.h:11"/>
<a k="array" l="2380" c="54" why="array-extent" ref="kDriftedTable[16]" want="16" got="18" tgt="test/docdriftfix/code.h:14"/>
<a k="const" l="2408" c="53" why="const-value" ref="kDriftedLimit = 10" want="10" got="15" tgt="test/docdriftfix/code.h:11"/>
<more drift="9"/>
</doc>
<doc p="test/docdriftfix/NOTES.md" anchors="30" checked="21" drift="7" dated="0">
<a k="file-line" l="9" c="64" why="line-moved" ref="code.h:23" sym="stableHelper" got="movedHelper" tgt="test/docdriftfix/code.h:17"/>
<a k="file-line" l="10" c="58" why="past-eof" ref="code.h:900" sym="stableHelper" got="33 lines" tgt="test/docdriftfix/code.h"/>
<a k="file-line" l="11" c="53" why="missing-file" ref="deletedFile.h:12"/>
<a k="const" l="26" c="29" why="const-value" ref="kDriftedLimit = 10" want="10" got="15" tgt="test/docdriftfix/code.h:11"/>
<a k="array" l="28" c="49" why="array-extent" ref="kDriftedTable[16]" want="16" got="18" tgt="test/docdriftfix/code.h:14"/>
<a k="array" l="29" c="61" why="array-extent" ref="[16]" want="16" got="18" tgt="test/docdriftfix/code.h:14"/>
<a k="file-line" l="42" c="49" why="range-straddles" ref="code.h:18-23" got="movedHelper" tgt="test/docdriftfix/code.h:23"/>
</doc>
<doc p="PLAN.md" anchors="104" checked="64" drift="4" dated="1">
<a k="file-line" l="407" c="63" why="line-moved" kind="dated-record" rec="block" ref="naminglens.h:526" sym="checkNameShape" got="(file scope)" tgt="src/naminglens.h:618"/>
<a k="file-line" l="553" c="81" why="line-moved" ref="ingest.cpp:7175" sym="astQuery" got="(file scope)" tgt="src/ingest.cpp:12711"/>
<a k="file-line" l="1014" c="71" why="line-moved" ref="src/ingest.cpp:477" sym="jsonNestsTooDeep" got="(file scope)" tgt="src/ingest.cpp:600"/>
… [118 more display lines; full output is 18401 bytes on 1 raw line(s)]
`````

Tail of the same output — the `<gateability>` section:

`````
<gateability docs="11" projected_drift="0">
<fix p="docs/COMMANDS.md" live="21"/>
<fix p="test/docdriftfix/NOTES.md" live="7"/>
<fix p="PLAN.md" live="4"/>
<fix p="README.md" live="3"/>
<fix p="test/docdriftfix/live_notes.md" live="2"/>
<fix p="test/gateabilityfix/UNDATED.md" live="2"/>
<fix p="CONTRIBUTING.md" live="1"/>
<fix p="bench/nestcal/r1-2026-08-07/REPORT.md" live="1"/>
<fix p="docs/EVALS.md" live="1"/>
<fix p="test/docdriftfix/record_line.md" live="1"/>
<fix p="test/gateabilityfix/MIXED.md" live="1"/>
</gateability>
</doc-drift>
`````

## `./build/ripwire . --doc-drift --with-history`

*Same report, with git history splitting stale mentions into deleted-by-commit vs never-existed.*

`````
<!-- ripwire doc drift: the CHECKABLE anchors in this repo's markdown, verified against the live index, reporting only the ones that no longer hold. Four kinds: file:line refs (missing-file / past-eof / line-moved, the last only when the doc names a symbol on that line), backticked symbol mentions (undefined), `= N` constants and `[N]` array extents (value/extent vs the declaration). Every lane under reports on purpose: a name is stale only when it occurs NOWHERE in the code as an identifier, and a number is compared only against a declaration shaped literal the corpus binds uniquely. checked + unchecked == anchors: nothing is dropped silently, and the unchecked rows say what was not proved. Read why="undefined" precisely: it says the name is defined NOWHERE in this repo, which is not the same as DELETED — in a plan or design doc naming work not yet built, that is expected rather than rot. Run with the with_history flag to have git history separate the two: the lane then reports why="deleted" with the commit that removed the name, and downgrades a name this repo never had to unchecked r="never in history". A failed anchor the AUTHOR DATED is split out as kind="dated-record" and counted in dated= rather than drift=: an audit finding, a ledger row or an as-of-DATE hedge records what was true then, so drift= is the LIVE rot and drift + dated is every anchor that no longer holds. rec= names the evidence (line / block / title / stamp), and a doc that never writes its own date anywhere a machine can read reports LIVE — the lane reads dating marks, it does not guess genre. Attribute vocabulary, one name one meaning: at= appears ONLY on this root element and is the commit the run was measured against (short sha, plus dirty when the tree had uncommitted changes); ref= is the anchor as the DOC writes it; got= is what the corpus actually says; and tgt= is the corpus SITE backing got= (a path, or path:line). On the <a/> rows k= and kind= are DIFFERENT things and both are kept: k= is the ANCHOR kind (file-line / symbol / const / array), kind= is the record classification (dated-record). k= cannot be renamed to kind= here for the obvious reason that kind= is already taken on the same element; note that in the ranked map the same k= spelling is a PageRank score instead. Docs are ordered by LIVE drift descending (path breaks ties), so the worst rot leads and a fully dated doc, which is drift zero by construction, sinks on the same key. Prose claims, Status lines and dates are NOT checked. A `path:A-B` RANGE gets one more structural check: why="range-straddles" fires when A's innermost symbol does not reach B (got= then names whatever occupies B instead, tgt= that site), regardless of whether the doc names a symbol. weak-file-line, the one unchecked reason that names no symbol, gets a FREE disclosure instead of a verdict: <weak-file-line p= n=> groups, one per doc, list every such anchor whose line DOES sit inside an indexed symbol, and each <w> row's resolves-to= names it — the verb still does not know if that is the symbol the doc meant. This section sits beside, not inside, the <doc> rows: a doc can appear in it while still counting toward clean=, and every row it lists still counts once in the unchecked r="weak-file-line" tally below. FOUR COUNTERS on this element name four DIFFERENT populations, stated here because one of them openly disagrees with a number the map reports elsewhere. docs= is the DOCUMENTS scanned for anchors (markdown by extension, after any filter); it is the denominator of the doc rows below. clean= is how many of those docs came out with NO failed anchor — drift and dated both zero for that doc — so docs minus clean is exactly the number of <doc> rows below, before any paging window is applied. A doc whose anchors were all unchecked, or all prose, is clean here: clean means nothing was found rotten, not that everything was verified. prose= is the anchors dropped as prose, so it is SUBTRACTED from anchors= rather than added to it, and the verb does not claim to have checked them; only the VALUE shapes (`= N` and `[N]`) can be dropped this way, and the drop is itself a corpus lookup — the name was searched for and not found in code — not a pre-check guess. corpus= is the file population the anchors were checked AGAINST, and it is its OWN population rather than a relation to the map's files=: the indexed files this walk could re-read, PLUS a fixed set of config, shader and build-file extensions (CMakeLists.txt, .cmake, .yml/.yaml, .toml, .metal/.glsl/.hlsl and the like — an extension whitelist, never a content sniff), MINUS every file this walk could not open or that exceeded its own 4 MiB read ceiling, which is dropped silently and never counted. So corpus= is USUALLY larger than files= and that is the normal case, but it is not always: a crawl run whose max file size ceiling was raised above 4 MiB indexes files this walk still refuses, and a file the index lists but this run cannot open is counted by one and not the other. Neither number is wrong. corpus="0" means the corpus scan never ran at all, which happens only when the docs raised no anchor SHAPE whatsoever — prose ones included — so anchors="0" beside a non-zero prose= still scanned, and still reports the corpus it scanned. -->
<doc-drift docs="134" clean="123" anchors="1389" checked="519" unchecked="870" drift="42" dated="10" prose="9" corpus="1331" at="700e51d49">
<history probed="1" head="700e51d49" commits="682" removed-names="22714"/>
<doc p="docs/COMMANDS.md" anchors="74" checked="21" drift="21" dated="0">
<a k="const" l="2370" c="53" why="const-value" ref="kDriftedLimit = 10" want="10" got="15" tgt="test/docdriftfix/code.h:11"/>
<a k="array" l="2371" c="54" why="array-extent" ref="kDriftedTable[16]" want="16" got="18" tgt="test/docdriftfix/code.h:14"/>
<a k="const" l="2372" c="53" why="const-value" ref="kDriftedLimit = 10" want="10" got="15" tgt="test/docdriftfix/code.h:11"/>
<a k="array" l="2373" c="54" why="array-extent" ref="kDriftedTable[16]" want="16" got="18" tgt="test/docdriftfix/code.h:14"/>
<a k="const" l="2374" c="53" why="const-value" ref="kDriftedLimit = 10" want="10" got="15" tgt="test/docdriftfix/code.h:11"/>
<a k="const" l="2375" c="53" why="const-value" ref="kDriftedLimit = 10" want="10" got="15" tgt="test/docdriftfix/code.h:11"/>
<a k="array" l="2376" c="54" why="array-extent" ref="kDriftedTable[16]" want="16" got="18" tgt="test/docdriftfix/code.h:14"/>
<a k="const" l="2377" c="53" why="const-value" ref="kDriftedLimit = 10" want="10" got="15" tgt="test/docdriftfix/code.h:11"/>
<a k="array" l="2378" c="54" why="array-extent" ref="kDriftedTable[16]" want="16" got="18" tgt="test/docdriftfix/code.h:14"/>
<a k="const" l="2379" c="53" why="const-value" ref="kDriftedLimit = 10" want="10" got="15" tgt="test/docdriftfix/code.h:11"/>
<a k="array" l="2380" c="54" why="array-extent" ref="kDriftedTable[16]" want="16" got="18" tgt="test/docdriftfix/code.h:14"/>
<a k="const" l="2408" c="53" why="const-value" ref="kDriftedLimit = 10" want="10" got="15" tgt="test/docdriftfix/code.h:11"/>
<more drift="9"/>
</doc>
<doc p="test/docdriftfix/NOTES.md" anchors="30" checked="21" drift="7" dated="0">
<a k="file-line" l="9" c="64" why="line-moved" ref="code.h:23" sym="stableHelper" got="movedHelper" tgt="test/docdriftfix/code.h:17"/>
<a k="file-line" l="10" c="58" why="past-eof" ref="code.h:900" sym="stableHelper" got="33 lines" tgt="test/docdriftfix/code.h"/>
<a k="file-line" l="11" c="53" why="missing-file" ref="deletedFile.h:12"/>
<a k="const" l="26" c="29" why="const-value" ref="kDriftedLimit = 10" want="10" got="15" tgt="test/docdriftfix/code.h:11"/>
<a k="array" l="28" c="49" why="array-extent" ref="kDriftedTable[16]" want="16" got="18" tgt="test/docdriftfix/code.h:14"/>
<a k="array" l="29" c="61" why="array-extent" ref="[16]" want="16" got="18" tgt="test/docdriftfix/code.h:14"/>
<a k="file-line" l="42" c="49" why="range-straddles" ref="code.h:18-23" got="movedHelper" tgt="test/docdriftfix/code.h:23"/>
</doc>
<doc p="PLAN.md" anchors="104" checked="64" drift="4" dated="1">
<a k="file-line" l="407" c="63" why="line-moved" kind="dated-record" rec="block" ref="naminglens.h:526" sym="checkNameShape" got="(file scope)" tgt="src/naminglens.h:618"/>
<a k="file-line" l="553" c="81" why="line-moved" ref="ingest.cpp:7175" sym="astQuery" got="(file scope)" tgt="src/ingest.cpp:12711"/>
… [92 more display lines; full output is 16816 bytes on 1 raw line(s)]
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
<frame rank="3" n="runDefaultMap" t="fn" p="src/main.cpp:5155" resolved_by="name" line_encloses="resolveDeltaBasis"/>
<frame rank="4" n="main" t="fn" p="src/main.cpp:5594" resolved_by="name" line_encloses="runDmm"/>
</trace>
<sigs>
<f p="./src/graph.h">
<d l="2112" n="rankGraphTeleport" id="./src/graph.h::rw::rankGraphTeleport" cx="5" ccx="8" in="6">
<doc>PageRank with an explicit teleport / personalization vector p (Σp = 1). The prior is name-quality-biased through biasPrior() so all rank modes share one weighting seam; the transition matrix (edges</doc>inline RankedGraph rankGraphTeleport( const Graph&amp; g, const std::vector&lt;float&gt;&am … [line truncated: 31 more bytes on this line]
<d l="2153" n="rankGraph" id="./src/graph.h::rw::rankGraph" cx="2" ccx="1" in="9">
<doc>uniform-teleport PageRank (the default</doc>inline RankedGraph rankGraph( const Graph&amp; g, float alpha = 0.85f )</d>
</f>
<f p="./src/main.cpp">
<d l="12619" n="runDefaultMap" cx="134" ccx="197" in="1">int runDefaultMap( const MainDispatch&amp; d )</d>
<d l="14052" n="main" cx="222" ccx="390" in="0">int main( int argc, char** argv )</d>
</f>
</sigs>
<bodies shown="1" total="1" capped="0">
<b t="fn" l="2112" p="./src/graph.h" n="rankGraphTeleport">
<![CDATA[inline RankedGraph rankGraphTeleport( const Graph& g, const std::vector<float>& p, float alpha = 0.85f )
{
    PROFILE_SCOPE_DESCRIBE( "rankGraph: PageRank (power iteration)" );
    const std::vector<float> pw = biasPrior( g, p );
    const std::size_t N = pw.size();
    std::vector<double> teleport( pw.begin(), pw.end() );
    std::vector<double> rankDouble( N, 0.0 );
    PageRankRun         run{};   // an N == 0 graph never enters the kernel: { 0, converged } — see PageRankRun
… [21 more display lines; full output is 5194 bytes on 29 raw line(s)]
`````

## `./build/ripwire . --notes`

*List all field notes (write-side memory). This repo still has no .ripwire_notes.*

`````
<ctx><!-- ripwire field notes: notes=0 targets=0 dangling=0 (a target with no matching indexed symbol/file — legal: listed here, surfaced nowhere) --><notes></notes></ctx>
`````

## `./build/ripwire . --pack-task="add a new output format flag to the CLI"`

*ONE budget-shared bundle: ranking + top bodies + caller sigs + notes + tests_to_run. CHANGED: <d> rows now carry n=/id=.*

`````
<ctx task="add a new output format flag to the CLI" route=" [routed: subtoken+body BM25 (--for&apos;s default) — no strong name hit, multi-word conceptual query]" root=".">
<!-- ripwire task bundle for "add a new output format flag to the CLI": one-call orientation under ONE budget — sections in FIXED order ranking > bodies > callers > notes > tests, quotas per section are FIXED (rank40/body30/caller15/note5/test10, percent of budget), unused quota ROLLS FORWARD to the next section — a small budget still zeroes a section, but never past its own share. each truncates rank-adaptively; every truncation reported here (no silent caps): on every section shown=rows kept, total=rows that qualified, capped=1 when they differ. bodies fill rank-first, so a bigger budget can keep FEWER, larger bodies — the count is not a quality measure. Row keys: n=name (chain it), id=canonical(when scoped), in=reuse-count (absent = not measured, never a false 0), l=line, p=path, t=kind, cx=cyclomatic, ccx=cognitive, rel=caller|callee; far=ranked but over 1 hop out; of_top denominator is per-section. budget=12744 bytes (6000-token target, ceiling 14160) | ranking: full | bodies: 6 of 6 | callers: 3 of 3 | notes: none | tests: none | far: 6 of 6 -->
<!-- root= on this element is the crawl root every p= below is RELATIVE to (single-root runs only; absent => p= is the path ingest itself used, unchanged). -->
<sigs>
<f p="src/tracein.h">
<d l="103" n="toUint" id="./src/tracein.h::detail::toUint" cx="3" ccx="3" in="3">
<doc>F7: a hostile/garbled frame line number (e.g. a fuzzed or truncated trace) can exceed UINT32_MAX; unchecked `v*10+d` wraps mod 2^32 (4294967297 -&gt; 1), which then confidently maps to a REAL line in the</doc>inline std::uint32_t toUint( std::string_view s, bool&amp; overflowed ) noexcept</d>
</f>
<f p="src/mcprefusal.h">
<d l="64" n="kMcpRequiredFields" id="./src/mcprefusal.h::rw::mcprefuse::kMcpRequiredFields" cx="0" ccx="0" in="0" pure="1">inline constexpr McpFieldSpec kMcpRequiredFields[] =</d>
<d l="235" n="McpValueSpec" id="./src/mcprefusal.h::McpValueSpec::McpValueSpec" cx="0" ccx="0" in="0">
<doc>verifier N2/N3/N11: the bad-VALUE refusal table</doc>struct McpValueSpec</d>
</f>
<f p="src/main.cpp">
<d l="14007" n="kJsonShapeModifiers" cx="0" ccx="0" in="0" pure="1">
<doc>B1.4: the output-SHAPE members of the list above, as a table rather than a second if-chain. A flag in here selects an ENCODING for rows some verb already produced, so &quot;--json is not supported for X</doc>inline constexpr const char* kJsonShapeModifiers[] =</d>
</f>
<f p="src/cli.h">
<d l="1803" n="BoolFlag" id="./src/cli.h::BoolFlag::BoolFlag" cx="0" ccx="0" in="0">
<doc>offsetof, which would be UB on a non-standard-layout type. ORDER. The tables are scanned in DECLARATION ORDER, exacts before prefixes, ahead of the hand-written arms — so the chain&apos;s original preced</doc>struct BoolFlag</d>
<d l="2243" n="kHandWrittenFlagArms" id="./src/cli.h::rw::kHandWrittenFlagArms" cx="0" ccx="0" in="0" pure="1">
<doc>table was the disease, so 23 of them became kViewFlags rows (33 → 56) once that table grew the EmptyValue and isSetFlag columns. kTotalFlagArms is unchanged, which is exactly what this tripwire is f</doc>inline constexpr std::size_t kHandWrittenFlagArms = 22</d>
</f>
<far of_top="12" shown="6" total="6" capped="0">
<s t="fn" n="formatRecallSeparator" p="src/recall.h:642"/>
<s t="fn" n="jsonUnsupportedVerb" p="src/main.cpp:13684"/>
<s t="fn" n="qualityDeltaJson" p="src/mcpverbs.h:2483"/>
<s t="fn" n="readAckRecords" p="src/quality.h:2912"/>
<s t="method" n="operator new" p="src/alloccount.cpp:116"/>
<s t="cls" n="LensRanking" p="src/packtask.h:41"/>
… [79 more display lines; full output is 12106 bytes on 75 raw line(s)]
`````

## `./build/ripwire . --pack-task="add a new output format flag to the CLI" --partition=3`

*Fan-out form: one shared core + 3 per-agent slices carved along call-graph communities.*

`````
<ctx-partitions partitions="3" requested="3" core_symbols="6" surface="42" modules="18" split="0" budget_per_agent_tokens="6000" core_budget_tokens="2040" partition_budget_tokens="3960" total_bytes="28379" overlap_mean="0.046" overlap_max="0.107" shared_symbols="10" union_symbols="100" core_overlap= … [line truncated: 8 more bytes on this line]
<!-- ripwire partitioned task bundle: ONE shared common core plus N minimally overlapping per agent slices, carved along the call graph's own community structure. Each bundle wraps one ctx document, exactly what a standalone pack task call with that slice would emit, so an orchestrator hands one bundle to one agent verbatim. budget_per_agent_tokens is the budget for core PLUS one partition, not the whole document; total_bytes is the bundles' combined size. overlap_mean/overlap_max are pairwise Jaccard over the ids each partition names (ranking window, bodies, and their 1 hop neighbors), measured BEFORE budget trimming, so they are a ceiling. shared_symbols counts the ids TWO OR MORE partitions name — NOT the ids every partition names; an id two of sixteen slices both carry is already duplicated work — and union_symbols the ids ANY partition names: one GLOBAL at-least-two over at-least-one pair, not an average. That ratio and overlap_mean (an average of PAIRWISE Jaccard) therefore answer different questions. They COINCIDE at partitions=2, where there is one pair and at-least-two IS its intersection while at-least-one IS its union, so the ratio equals that pair's Jaccard by identity; from 3 partitions on the two genuinely diverge, and neither is wrong. The remaining root counters, one clause each. requested= is the partition count N asked for and partitions= the bundles actually carved; partitions is lower only where the plan could not reach N, which is either a ranked surface that fit entirely in the shared core (partitions=0, nothing left to carve) or a surface holding fewer separable modules than N even after splitting. modules= is the distinct groups found on the assignable surface BEFORE any cut (a call-graph community, or the FILE where that surface carries no call edges), and split= the community cuts forced because those modules numbered fewer than N, so modules + split is the group count the bundles were packed from and split=0 means no cut was needed. core_symbols= is the shared core's size — the body anchors a plain pack task would have expanded, held out of every partition — and surface= is core_symbols plus the assignable remainder, i.e. the whole positive-rank window this plan carved up. core_budget_tokens= and partition_budget_tokens= are budget_per_agent_tokens split between the two halves one agent receives, and they sum to it. core_overlap is the share of the core bundle's own surface a partition reaches anyway. On each bundle, est_tokens and tokens are the SAME number: tokens is the original name kept for compatibility, est_tokens is the spelling the rest of the tool uses and the one to read. Both are that bundle's own bytes= divided by 2.36 B/tok — the DENSEST calibrated language rate — which is a different (deliberately conservative) currency from the default map's est_tokens, where the divisor is that corpus's own language-weighted rate: measured over real emitted bytes either way, but a bundle's number reads slightly HIGH, which is the safe direction for a per-agent budget. On this root element the unit is carried in the NAME instead (budget_per_agent_tokens, total_bytes) rather than by a separate unit attribute, which is a deliberate exception to the est_tokens convention and not a second estimator. -->
<bundle role="core" symbols="6" bytes="3947" tokens="1672" est_tokens="1672">
<ctx task="add a new output format flag to the CLI" route=" [routed: subtoken+body BM25 (--for&apos;s default) — no strong name hit, multi-word conceptual query]" root=".">
<!-- ripwire task bundle for "add a new output format flag to the CLI": one-call orientation under ONE budget — sections in FIXED order ranking > bodies > callers > notes > tests, quotas per section are FIXED (rank40/body30/caller15/note5/test10, percent of budget), unused quota ROLLS FORWARD to the next section — a small budget still zeroes a section, but never past its own share. each truncates rank-adaptively; every truncation reported here (no silent caps): on every section shown=rows kept, total=rows that qualified, capped=1 when they differ. bodies fill rank-first, so a bigger budget can keep FEWER, larger bodies — the count is not a quality measure. Row keys: n=name (chain it), id=canonical(when scoped), in=reuse-count (absent = not measured, never a false 0), l=line, p=path, t=kind, cx=cyclomatic, ccx=cognitive, rel=caller|callee; far=ranked but over 1 hop out; of_top denominator is per-section. budget=4332 bytes (2040-token target, ceiling 4814) | ranking: capped | bodies: kept 4 of 6 (capped) | callers: kept 2 of 3 | notes: none | tests: none | far: none -->
<!-- root= on this element is the crawl root every p= below is RELATIVE to (single-root runs only; absent => p= is the path ingest itself used, unchanged). -->
<sigs capped="1">
<f p="src/tracein.h">
<d l="103" n="toUint" id="./src/tracein.h::detail::toUint" cx="3" ccx="3" in="3">
<doc>F7: a hostile/garbled frame line number (e.g. a fuzzed or truncated trace) can exceed UINT32_MAX…</doc>inline std::uint32_t toUint( std::string_view s, bool&amp; overflowed ) noexcept</d>
</f>
<f p="src/mcprefusal.h">
<d l="235" n="McpValueSpec" id="./src/mcprefusal.h::McpValueSpec::McpValueSpec" cx="0" ccx="0" in="0">
<doc>verifier N2/N3/N11: the bad-VALUE refusal table</doc>struct McpValueSpec</d>
</f>
<f p="src/main.cpp">
<d l="14007" n="kJsonShapeModifiers" cx="0" ccx="0" in="0" pure="1">
<doc>B1.4: the output-SHAPE members of the list above, as a table rather than a second if-chain. A fl…</doc>inline constexpr const char* kJsonShapeModifiers[] =</d>
</f>
<f p="src/cli.h">
<d l="2243" n="kHandWrittenFlagArms" id="./src/cli.h::rw::kHandWrittenFlagArms" cx="0" ccx="0" in="0" pure="1">
<doc>table was the disease, so 23 of them became kViewFlags rows (33 → 56) once that table grew the…</doc>inline constexpr std::size_t kHandWrittenFlagArms = 22</d>
</f>
</sigs>
<bodies shown="4" total="6" capped="1">
<b t="fn" l="103" p="src/tracein.h" n="toUint">
<![CDATA[inline std::uint32_t toUint( std::string_view s, bool& overflowed ) noexcept
{
    std::uint32_t v = 0;
    for( const char c : s )   // callers pass only isDigits() spans
… [325 more display lines; full output is 32416 bytes on 267 raw line(s)]
`````

## `./build/ripwire . --for="pagerank power iteration" --with-graph`

*Task lens + a compact Mermaid flowchart of the top anchors' 1-hop edges.*

`````
<ctx task="pagerank power iteration" route=" [routed: subtoken+body BM25 (--for&apos;s default) — no strong name hit, multi-word conceptual query]" root="." bundle="auto" bodies="2">
<!-- ripwire lens for "pagerank power iteration" [doc mentions: 4 docs discussing 3 top-ranked symbols surfaced]: reusable building blocks + quality facts for what you're about to touch (cx=complexity ccx=cognitive in=reuse-count churn=recent-commits amp=change-amplification clone=1(duplicated) tested=1) — prefer composing/reusing these; watch the high-churn/high-amp/cloned ones; bundle=auto: the top-ranked FULL bodies ride inline after the signatures in a bodies section (bodies=N on this root counts them; bodies=0 reason=budget when none fit the remaining budget whole; the signatures-only flag (no-bodies mode) opts out) — read them here instead of opening the files. The bodies element discloses the house way: total=requested, shown=printed, capped=1 when they differ; each body's calls child lists its callee signatures, total= always, shown=/capped= only when that list is cut -->
<!-- root= is the crawl root; p= below is RELATIVE to it (single-root only; absent => p= is ingest's own path, unchanged). est_tokens="4995" -->
<sigs capped="1">
<f p="scripts/optremarks.py">
<d l="40" n="HOT_FILES" cx="0" ccx="0" in="0" churn="3" amp="37">HOT_FILES = ( &quot;src/pagerank.cpp&quot;, # the power-iteration loop — G2&apos;s no-allocation scope &quot;src/infra/radixSort.h&quot;, # LSD radix entry points &quot;src/infra/radixSort…</d>
</f>
<f p="src/prconverge.h">
<d l="51" n="RankDisclosure" id="./src/prconverge.h::RankDisclosure::RankDisclosure" cx="0" ccx="0" in="0" churn="2" amp="17">
<doc>What a ranked document discloses about the power iteration that ordered it. `isPageRank == false…</doc>struct RankDisclosure</d>
<d l="73" n="renderDisclosure" id="./src/prconverge.h::rw::renderDisclosure" cx="12" ccx="15" in="10" churn="2" amp="27">
<doc>Render one form of the disclosure. Empty string whenever there is nothing to say — no power it…</doc>inline std::string renderDisclosure( const RankDisclosure&amp; d, DiscloseAs as )</d>
</f>
<f p="src/graph.h">
<d l="2103" n="RankedGraph" id="./src/graph.h::RankedGraph::RankedGraph" cx="0" ccx="0" in="0" churn="29" amp="106">
<doc>What a rank call hands back: the vector, and the power iteration&apos;s own account of itself. Struct…</doc>struct RankedGraph</d>
<d l="2112" n="rankGraphTeleport" id="./src/graph.h::rw::rankGraphTeleport" cx="5" ccx="8" in="6" churn="29" amp="112">inline RankedGraph rankGraphTeleport( const Graph&amp; g, const std::vector&lt;float&gt;&amp; p, float alpha = 0.85f )</d>
<d l="2178" n="hits" id="./src/graph.h::rw::hits" cx="9" ccx="16" in="1" churn="29" amp="107">inline std::pair&lt;std::vector&lt;float&gt;, std::vector&lt;float&gt;&gt; hits( const Graph&amp; g, float tol = 1e-6f…</d>
<d l="2489" n="anchoredLexicalRank" id="./src/graph.h::rw::anchoredLexicalRank" cx="10" ccx="10" in="4" churn="29" amp="110">inline std::vector&lt;float&gt; anchoredLexicalRank( const Graph&amp; g, const std::vector&lt;float&gt;&amp; lex )</d>
</f>
<f p="src/pagerank.h">
<d l="11" n="PageRankConfig" id="./src/pagerank.h::PageRankConfig::PageRankConfig" cx="0" ccx="0" in="0" churn="6" amp="20">struct PageRankConfig</d>
<d l="31" n="PageRankRun" id="./src/pagerank.h::PageRankRun::PageRankRun" cx="0" ccx="0" in="0" churn="6" amp="20">struct PageRankRun</d>
</f>
<f p="src/pagerank.cpp">
<d l="54" n="testIterationCeiling" cx="7" ccx="9" in="1" churn="7" amp="21">std::uint32_t testIterationCeiling() noexcept</d>
<d l="95" n="pageRankDouble" id="./src/pagerank.cpp::rw::pageRankDouble" cx="19" ccx="34" in="1" churn="7" amp="21">PageRankRun pageRankDouble( const sparseCsr&lt;float&gt;&amp; inEdges, std::span&lt;const double&gt; weightedOutDegree, std::span&lt;const double&gt; teleport, std::span&lt;double&gt;  … [line truncated: 11 more bytes on this line]
</f>
<f p="src/main.cpp">
<d l="12504" n="churnRankedGraph" cx="13" ccx="18" in="1" churn="141" amp="242">inline ChurnRanking churnRankedGraph( const MainDispatch&amp; d )</d>
… [136 more display lines; full output is 14651 bytes on 97 raw line(s)]
`````

## `./build/ripwire . --export=cc.json:<scratch>/aux/ripwire2.cc.json`

*Per-file metrics as CodeCharta cc.json.*

`````
(empty)
`````

Artifact written:

`````
  193480 <scratch>/aux/ripwire2.cc.json
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
<![CDATA[<ctx task="incremental cache invalidation" route=" [routed: subtoken+body BM25 (--for&apos;s default) — no strong name hit, multi-word conceptual query]" root=".">
<!-- ripwire lens for "incremental cache invalidation" [doc mentions: 1 doc discussing 1 top-ranked symbol surfaced]: reusable building blocks (cx=complexity, in=reuse-count) — prefer composing/reusing these over reimplementing -->
<!-- root= is the crawl root; p= below is RELATIVE to it (single-root only; absent => p= is ingest's own path, unchanged). -->
<sigs capped="1">
<f p="src/ingest.cpp">
<d l="169" n="LexPair" id="./src/ingest.cpp::LexPair::LexPair" cx="0" ccx="0" in="0">struct LexPair</d>
<d l="541" n="measureFileHealth" cx="18" ccx="21" in="1">FileHealth measureFileHealth( TSNode root, std::string_view bytes )</d>
<d l="870" n="collectSources" cx="39" ccx="80" in="1">CrawlResult collectSources( const char* rootDir, const std::vector&lt;std::string&gt;&amp; excludeSubstr, …</d>
<d l="1154" n="StatInfo" id="./src/ingest.cpp::StatInfo::StatInfo" cx="0" ccx="0" in="0">struct StatInfo</d>
<d l="1187" n="PathShape" cx="0" ccx="0" in="0">enum class PathShape : std::uint8_t</d>
<d l="1199" n="isReadableCacheBlob" cx="2" ccx="1" in="1">inline bool isReadableCacheBlob( const std::string&amp; path ) noexcept</d>
<d l="1211" n="wallClockNs" cx="1" ccx="0" in="1">inline long long wallClockNs() noexcept</d>
<d l="1247" n="CompiledQueryCache" id="./src/ingest.cpp::CompiledQueryCache::CompiledQueryCache" cx="0" ccx="0" in="0">struct CompiledQueryCache</d>
<d l="1251" n="CompiledQueryCache" id="./src/ingest.cpp::CompiledQueryCache::CompiledQueryCache" cx="1" ccx="0" in="0">CompiledQueryCache()</d>
<d l="1252" n="CompiledQueryCache" id="./src/ingest.cpp::CompiledQueryCache::CompiledQueryCache" cx="1" ccx="0" in="0">CompiledQueryCache( const CompiledQueryCache&amp; )</d>
<d l="1253" n="operator=" id="./src/ingest.cpp::CompiledQueryCache::operator=" cx="1" ccx="0" in="0">operator=( const CompiledQueryCache&amp; )</d>
<d l="1271" n="compiledQueryCache" cx="1" ccx="0" in="2">HashMap&lt;const TSLanguage*, TSQuery*&gt;&amp; compiledQueryCache()</d>
<d l="1298" n="compileQueryStandalone" cx="4" ccx="3" in="1">TSQuery* compileQueryStandalone( const LangEntry&amp; le )</d>
<d l="1320" n="compiledQueryFor" cx="3" ccx="2" in="1">TSQuery* compiledQueryFor( const LangEntry&amp; le )</d>
<d l="1412" n="RawRouteUse" id="./src/ingest.cpp::RawRouteUse::RawRouteUse" cx="0" ccx="0" in="0">struct RawRouteUse</d>
<d l="1425" n="kCacheMagic" cx="0" ccx="0" in="0" pure="1">
<doc>incremental cache (--cache): per-file content hash + raw facts so a re-run re-parses ONLY      c…</doc>constexpr std::uint32_t kCacheMagic = 0x4b505443</d>
<d l="1437" n="kCacheVersion" cx="0" ccx="0" in="0" pure="1">constexpr std::uint32_t kCacheVersion = 13</d>
<d l="1905" n="kArtifactArch" cx="0" ccx="0" in="0" pure="1">constexpr std::uint8_t kArtifactArch = static_cast&lt;std::uint8_t&gt;( ( __BYTE_ORDER__ == __ORDER_BI…</d>
<d l="1923" n="parserVerFor" cx="2" ccx="1" in="2">inline std::uint32_t parserVerFor( bool captureValueUses ) noexcept</d>
<d l="1932" n="contentHash64" cx="2" ccx="1" in="1">inline std::uint64_t contentHash64( std::string_view s ) noexcept</d>
<d l="1947" n="blobChecksum" cx="5" ccx="5" in="2">inline std::uint64_t blobChecksum( std::string_view s ) noexcept</d>
… [71 more display lines; full output is 20909 bytes on 1 raw line(s)]
`````


---

# self-diagnosis

## `./build/ripwire . --doctor`

*Environment self-check: binary staleness, grammars, cache dir, git, tracked-binary staleness.*

**exit code: 1**

`````
<doctor checks="6" passed="5" at="700e51d49">
<c n="binary-path" ok="0" self="./build/ripwire" which="/opt/homebrew/bin/ripwire" on_path="1" same_file="0" self_mtime="1787254255" self_size="40487256" which_mtime="1786573138" which_size="38785080" hint="STALE: /opt/homebrew/bin/ripwire is older th … [line truncated: 209 more bytes on this line]
<c n="grammars" ok="1" loaded="19" expected="19"/>
<c n="cache-dir" ok="1" dir="<tmp>" blobs="4096" bytes="905930362" many="1" truncated="1"/>
<c n="git" ok="1" git="1" repo="1" history="1" head="700e51d49"/>
<c n="tree-sitter" ok="1" core_abi="15" cpp_grammar_abi="14" languages="19"/>
<c n="tracked-binaries" ok="1" tracked="1641" binaries="6" non_git="0" truncated="0" stale="0"/>
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
<!-- ripwire v1 t=fn|method|cls|struct|iface|var|sec|macro(#define;degraded:body-is-replacement-text,edges-cross-expansion) p=path layer=arch-layer(opt) n=name id=canonical(path::scope::name,when-scoped) k=rank c=call amb=ambiguous-calls(read-source) overloads=N-same-name-defs-merged-into-this-row(absent-if-1;shown=counts-them-individually,so-rows+sum(overloads-1)=shown) prov=scip(precise;else name-based) hdr:unresolved=call-name-defined-only-in-a-lang-incompatible-file (edges heuristic) r:est_tokens=hdr-copy(none-if-stable) -->
<!-- r:root=crawl-root-every-p=-is-relative-to(single-root-only;absent=>p=is-the-raw-ingest-path) -->
<!-- rank_by=churn: k= is a git CHANGE-FREQUENCY prior over window=, not call-graph importance; the same corpus ranked by pagerank orders differently -->
<!-- at= is the git commit these numbers were computed at; a trailing +dirty means the working tree differed from that commit, so the numbers describe the tree, not the commit -->
<!-- pr_iters=pagerank-power-iterations(stop:L1-residual-below-tol,else-ceiling) pr_converged=0-only-when-ceiling-hit-first(absent=converged;no-such-attr=not-pagerank-ordered) -->
<!-- files=1304 symbols=11348 edges=13926 shown=5 est_tokens=761 ambiguous=5517 unresolved=3202 precise=3 skipped_oversize=15 unindexed="jsonl:25,txt:22,scm:16,tsv:16,lock:6,xml:4" unindexed_exts=17 order=important-first -->
<r at="700e51d49" root="." rank_by="churn" window="18mo" est_tokens="761" pr_iters="28">
<f p="src/notes.h">
<s t="method" n="empty" id="./src/notes.h::NoteIndex::empty" k="0.0148">
</s>
</f>
<f p="src/infra/svector.h" layer="infra">
<s t="method" n="size" id="./src/infra/svector.h::svector::size" k="0.0147">
</s>
<s t="method" n="buf" id="./src/infra/svector.h::svector::buf" overloads="2" k="0.0122">
</s>
</f>
<f p="src/scipoverlay.h">
<s t="method" n="empty" id="./src/scipoverlay.h::ScipOverlay::empty" k="0.0146">
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
ripwire: --rank-by: unknown value 'bogus' (supported: pagerank|authority|hub|rrf|churn|churn-decay)
`````

## `./build/ripwire . --callers=rankGraphTeleport --format=columnar`

*Columnar output: paths table + parallel arrays, ~15-60% fewer tokens on MANY-row lists — small results can be LARGER (the columnar legend is a fixed cost).*

`````
<!-- ripwire callers/callees: the 1-hop call hierarchy read straight off the call graph. The callers form lists the symbols that CALL of=; the callees form lists the symbols of= itself calls. of= is the selector you passed, defs= how many DEFINITIONS that name resolved to (the rows UNION every def's neighbours), and count= the number of DISTINCT neighbour symbols (a floor, per counts_floor=), which the rows window with limit= and offset=. A neighbour that is an indexed function-like #define is a macro row (t="macro", role="macro" on the XML row): the edge crosses a macro expansion, not a plain call — rows carry no role= otherwise. counts_floor="1" means every count on this element is a FLOOR, never a total. Call edges are extracted from source text by NAME, so a call that reaches its target through dynamic dispatch (a virtual, interface or duck-typed receiver), or a declaration that parses without a call expression (C++ most-vexing-parse) contributes no edge and is missing here. A call through a function pointer or callback resolves only when ONE function is bound to that variable in scope (C-family; a reassigned, table-indexed, lambda-bound or escaped pointer — its address taken or reference-bound — still contributes no edge). A binding written as a plain name rather than an address-of (fp = handler, not fp = &handler) is read as a function only when the variable is PROVEN able to hold one: a function-pointer declarator, or a function-pointer typedef declared in the SAME FILE, or a type the parse cannot pin down at all (auto, a template type). Under any other concrete written type it is a value copy and contributes no edge, so a variable whose function-pointer typedef lives in a HEADER is missed. A macro-generated call site contributes a role="macro" edge when its name uniquely names an indexed function-like #define (C-family, t="macro"); a name shared with any non-macro definition stays a plain call for the resolver, and an unindexed macro's call site contributes no edge. Read a zero as "none found", never as "none exists". COUNTING UNIT, and it differs by verb — which is why two of them report different numbers for one symbol. The callers, callees, edit-check, graph-query and pr-context counts are DISTINCT SYMBOLS: repeated calls from one caller, and calls to two overloads of one name, collapse into ONE row, their multiplicity surviving only in the call graph's edge weight. The reach counts (impact's reaches=, pr-context's dependents=) are the size of a transitive reach SET, each symbol counted once — not a count of calls or edges. The uses verb counts call SITES, one row per occurrence, so a larger count= there for the same symbol is these units agreeing, not disagreeing. The map header's edges= is a unit again different — distinct (caller,callee) PAIRS — and that document carries neither this marker nor this clause, so its numbers answer a different question. -->
<!-- root= on this element is the crawl root every p= below is RELATIVE to (single-root runs only; absent => p= is the path ingest itself used, unchanged). -->
<!-- format=columnar: PARALLEL ARRAYS, not per-row attributes — the t=/n=/p= attributes this verb's XML row form carries are NOT emitted in this form. Zip by index: <paths> maps `I=path`; each array under <cols> holds exactly n= comma-separated values in ONE shared row order, and the path column is an index into <paths>. fields= names the columns, in array order. n="0" (an empty page) means every array is present and empty. A ',' inside a VALUE is escaped as &#44; (ordinary XML entity decoding restores it), so splitting a row array on ',' can never mis-zip. -->
<callers of="rankGraphTeleport" defs="1" count="6" root="." counts_floor="1" format="columnar">
<paths>0=src/eval.h 1=src/graph.h 2=src/main.cpp 3=src/mcpindex.h</paths>
<cols n="6" fields="path,name,line,kind">
<path>0,1,1,2,2,3</path>
<name>runEval,rankGraph,anchoredLexicalRank,churnRankedGraph,runDefaultMap,getIndex</name>
<line>168,2153,2489,12504,12619,950</line>
<kind>fn,fn,fn,fn,fn,fn</kind>
</cols>
</callers>
`````

## `./build/ripwire . --for="cache invalidation" --format=candidates --top-k=5`

*Flat top-K export for an external reranker.*

`````
<!-- ripwire candidates: flat top K export for an external reranker. r=rank(1 based) s=SCORE n=name id=canonical k=KIND-tag p=path l=line. Note k= is the kind here and the PageRank score in the ranked map; on this row the score is s=. Root: count= rows exported of total= RANKED CORPUS symbols (total is the corpus size, never a match count), capped="1" means the top-k cut dropped some; route= names the ranker (s= is comparable only within one route); anchored= counts query-mention lifts (0 = the anchor ran and moved nothing); weak="1" means the top raw lexical score is below the confidence bar, so these rows rest on thin textual evidence. -->
<candidates count="5" total="11348" capped="1" route="subtoken+body" anchored="0">
<cand r="1" s="9.17092" n="legoImplementorsOnSurface" id="./src/serialize.h::rw::legoImplementorsOnSurface" k="fn" p="./src/serialize.h" l="4528">
<sig>inline std::vector&lt;std::vector&lt;NodeId&gt;&gt; legoImplementorsOnSurface( const IngestResult&amp; ing, const std::vector&lt;std::vector&lt;NodeId&gt;&gt;&amp; implementors, const std::vector&lt;NodeId&gt;&amp; surfaceIds )</sig>
</cand>
<cand r="2" s="6.04385" n="sweepStaleCacheBlobsOnce" id="./src/quality.h::quality::sweepStaleCacheBlobsOnce" k="fn" p="./src/quality.h" l="1170">
<sig>inline void sweepStaleCacheBlobsOnce( const std::string&amp; dir, const std::string&amp; keepPath )</sig>
</cand>
<cand r="3" s="6.03845" n="mcpCachePath" id="./src/mcpindex.h::rw::mcpCachePath" k="fn" p="./src/mcpindex.h" l="554">
<sig>inline std::string mcpCachePath( const std::string&amp; root )</sig>
</cand>
<cand r="4" s="6.03427" n="kCacheRuleNames" id="./src/cachelint.h::rw::cachelint::kCacheRuleNames" k="var" p="./src/cachelint.h" l="60">
<sig>inline constexpr std::array&lt;std::string_view, 8&gt; kCacheRuleNames =</sig>
</cand>
<cand r="5" s="6.03361" n="compiledQueryCache" id="compiledQueryCache" k="fn" p="./src/ingest.cpp" l="1271">
<sig>HashMap&lt;const TSLanguage*, TSQuery*&gt;&amp; compiledQueryCache()</sig>
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
{"of":"rankGraphTeleport","defs":1,"count":6,"root":".","counts_floor":true,"callers":[{"t":"fn","n":"runEval","p":"src/eval.h:168"},
{"t":"fn","n":"rankGraph","p":"src/graph.h:2153"},
{"t":"fn","n":"anchoredLexicalRank","p":"src/graph.h:2489"},
{"t":"fn","n":"churnRankedGraph","p":"src/main.cpp:12504"},
{"t":"fn","n":"runDefaultMap","p":"src/main.cpp:12619"},
{"t":"fn","n":"getIndex","p":"src/mcpindex.h:950"}]}
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
<!-- root= on this element is the crawl root every p= below is RELATIVE to (single-root runs only; absent => p= is the path ingest itself used, unchanged). -->
<hotspots window="12mo" files="1304" ranked="331" unranked_no_churn="0" unranked_no_complexity="973" shown="3" capped="1" total="331" has_more="1" next_offset="6" offset="3" limit="3" root="." at="700e51d49">
<f p="src/quality.h" churn="60" ccx="769" score="46140" top="computeDelta" top_ccx="236" top_l="3230"/>
<f p="src/graph.h" churn="29" ccx="1528" score="44312" top="buildGraph" top_ccx="761" top_l="717"/>
<f p="src/cli.h" churn="86" ccx="419" score="36034" top="parseArgs" top_ccx="187" top_l="3276"/>
</hotspots>
`````

## `./build/ripwire . --ignore-tests --top-k=5`

*Drop test paths from the corpus before ranking.*

`````
<!-- ripwire v1 t=fn|method|cls|struct|iface|var|sec|macro(#define;degraded:body-is-replacement-text,edges-cross-expansion) p=path layer=arch-layer(opt) n=name id=canonical(path::scope::name,when-scoped) k=rank c=call amb=ambiguous-calls(read-source) overloads=N-same-name-defs-merged-into-this-row(absent-if-1;shown=counts-them-individually,so-rows+sum(overloads-1)=shown) hdr:unresolved=call-name-defined-only-in-a-lang-incompatible-file (edges heuristic) r:est_tokens=hdr-copy(none-if-stable) -->
<!-- r:root=crawl-root-every-p=-is-relative-to(single-root-only;absent=>p=is-the-raw-ingest-path) -->
<!-- pr_iters=pagerank-power-iterations(stop:L1-residual-below-tol,else-ceiling) pr_converged=0-only-when-ceiling-hit-first(absent=converged;no-such-attr=not-pagerank-ordered) -->
<!-- files=1304 symbols=7121 edges=12457 shown=5 est_tokens=591 ambiguous=5439 unresolved=2530 skipped_oversize=15 unindexed="jsonl:25,txt:22,scm:16,tsv:16,lock:6,xml:4" unindexed_exts=17 order=important-first -->
<r root="." est_tokens="591" pr_iters="21">
<f p="src/infra/svector.h" layer="infra">
<s t="method" n="size" id="./src/infra/svector.h::svector::size" k="0.0219">
</s>
<s t="method" n="buf" id="./src/infra/svector.h::svector::buf" overloads="2" k="0.0112">
</s>
</f>
<f p="src/notes.h">
<s t="method" n="empty" id="./src/notes.h::NoteIndex::empty" k="0.0110">
</s>
</f>
<f p="src/scipoverlay.h">
<s t="method" n="empty" id="./src/scipoverlay.h::ScipOverlay::empty" k="0.0106">
</s>
</f>
</r>
`````

## `./build/ripwire . --exclude=present --exclude=bench --top-k=5`

*Drop matching paths (repeatable) before ranking.*

`````
<!-- ripwire v1 t=fn|method|cls|struct|iface|var|sec|macro(#define;degraded:body-is-replacement-text,edges-cross-expansion) p=path layer=arch-layer(opt) n=name id=canonical(path::scope::name,when-scoped) k=rank c=call amb=ambiguous-calls(read-source) overloads=N-same-name-defs-merged-into-this-row(absent-if-1;shown=counts-them-individually,so-rows+sum(overloads-1)=shown) prov=scip(precise;else name-based) hdr:unresolved=call-name-defined-only-in-a-lang-incompatible-file (edges heuristic) r:est_tokens=hdr-copy(none-if-stable) -->
<!-- r:root=crawl-root-every-p=-is-relative-to(single-root-only;absent=>p=is-the-raw-ingest-path) -->
<!-- pr_iters=pagerank-power-iterations(stop:L1-residual-below-tol,else-ceiling) pr_converged=0-only-when-ceiling-hit-first(absent=converged;no-such-attr=not-pagerank-ordered) -->
<!-- files=1135 symbols=9181 edges=12979 shown=5 est_tokens=601 ambiguous=5475 unresolved=1710 precise=3 unindexed="scm:16,txt:11,xml:4,arch:2,cmake:2,jsonl:2" unindexed_exts=13 order=important-first -->
<r root="." est_tokens="601" pr_iters="33">
<f p="src/infra/svector.h" layer="infra">
<s t="method" n="size" id="./src/infra/svector.h::svector::size" k="0.0192">
</s>
<s t="method" n="buf" id="./src/infra/svector.h::svector::buf" overloads="2" k="0.0097">
</s>
</f>
<f p="src/notes.h">
<s t="method" n="empty" id="./src/notes.h::NoteIndex::empty" k="0.0095">
</s>
</f>
<f p="src/scipoverlay.h">
<s t="method" n="empty" id="./src/scipoverlay.h::ScipOverlay::empty" k="0.0091">
</s>
</f>
</r>
`````

## `./build/ripwire . --map-diff --top-k=5`

*Full map re-ranked with teleport toward git-changed files — clean tree, so changed=0 and it degrades to the plain map.*

`````
<!-- ripwire v1 t=fn|method|cls|struct|iface|var|sec|macro(#define;degraded:body-is-replacement-text,edges-cross-expansion) p=path layer=arch-layer(opt) n=name id=canonical(path::scope::name,when-scoped) k=rank c=call amb=ambiguous-calls(read-source) overloads=N-same-name-defs-merged-into-this-row(absent-if-1;shown=counts-them-individually,so-rows+sum(overloads-1)=shown) prov=scip(precise;else name-based) hdr:unresolved=call-name-defined-only-in-a-lang-incompatible-file (edges heuristic) r:est_tokens=hdr-copy(none-if-stable) -->
<!-- r:root=crawl-root-every-p=-is-relative-to(single-root-only;absent=>p=is-the-raw-ingest-path) -->
<!-- at= is the git commit these numbers were computed at; a trailing +dirty means the working tree differed from that commit, so the numbers describe the tree, not the commit -->
<!-- pr_iters=pagerank-power-iterations(stop:L1-residual-below-tol,else-ceiling) pr_converged=0-only-when-ceiling-hit-first(absent=converged;no-such-attr=not-pagerank-ordered) -->
<!-- files=1304 symbols=11348 edges=13926 shown=5 est_tokens=692 ambiguous=5517 unresolved=3202 precise=3 changed=0 skipped_oversize=15 unindexed="jsonl:25,txt:22,scm:16,tsv:16,lock:6,xml:4" unindexed_exts=17 order=important-first -->
<r at="700e51d49" root="." est_tokens="692" pr_iters="32">
<f p="src/infra/svector.h" layer="infra">
<s t="method" n="size" id="./src/infra/svector.h::svector::size" k="0.0165">
</s>
<s t="method" n="buf" id="./src/infra/svector.h::svector::buf" overloads="2" k="0.0084">
</s>
</f>
<f p="src/notes.h">
<s t="method" n="empty" id="./src/notes.h::NoteIndex::empty" k="0.0081">
</s>
</f>
<f p="src/scipoverlay.h">
<s t="method" n="empty" id="./src/scipoverlay.h::ScipOverlay::empty" k="0.0079">
</s>
</f>
</r>
`````

## `./build/ripwire . --no-cache --top-k=3`

*Force a cold parse (bypass the warm TMPDIR cache) — shows the cold-vs-warm cost.*

`````
<!-- ripwire v1 t=fn|method|cls|struct|iface|var|sec|macro(#define;degraded:body-is-replacement-text,edges-cross-expansion) p=path layer=arch-layer(opt) n=name id=canonical(path::scope::name,when-scoped) k=rank c=call amb=ambiguous-calls(read-source) overloads=N-same-name-defs-merged-into-this-row(absent-if-1;shown=counts-them-individually,so-rows+sum(overloads-1)=shown) prov=scip(precise;else name-based) hdr:unresolved=call-name-defined-only-in-a-lang-incompatible-file (edges heuristic) r:est_tokens=hdr-copy(none-if-stable) -->
<!-- r:root=crawl-root-every-p=-is-relative-to(single-root-only;absent=>p=is-the-raw-ingest-path) -->
<!-- pr_iters=pagerank-power-iterations(stop:L1-residual-below-tol,else-ceiling) pr_converged=0-only-when-ceiling-hit-first(absent=converged;no-such-attr=not-pagerank-ordered) -->
<!-- files=1304 symbols=11348 edges=13926 shown=3 est_tokens=524 ambiguous=5517 unresolved=3202 precise=3 skipped_oversize=15 unindexed="jsonl:25,txt:22,scm:16,tsv:16,lock:6,xml:4" unindexed_exts=17 order=important-first -->
<r root="." est_tokens="524" pr_iters="32">
<f p="src/infra/svector.h" layer="infra">
<s t="method" n="size" id="./src/infra/svector.h::svector::size" k="0.0165">
</s>
<s t="method" n="buf" id="./src/infra/svector.h::svector::buf" overloads="2" k="0.0084">
</s>
</f>
</r>
`````

## `./build/ripwire . --cache=<scratch>/aux/warm2.ripwirecache --top-k=3`

*Explicit incremental cache at a path OUTSIDE the repo (first call writes it).*

`````
<!-- ripwire v1 t=fn|method|cls|struct|iface|var|sec|macro(#define;degraded:body-is-replacement-text,edges-cross-expansion) p=path layer=arch-layer(opt) n=name id=canonical(path::scope::name,when-scoped) k=rank c=call amb=ambiguous-calls(read-source) overloads=N-same-name-defs-merged-into-this-row(absent-if-1;shown=counts-them-individually,so-rows+sum(overloads-1)=shown) prov=scip(precise;else name-based) hdr:unresolved=call-name-defined-only-in-a-lang-incompatible-file (edges heuristic) r:est_tokens=hdr-copy(none-if-stable) -->
<!-- r:root=crawl-root-every-p=-is-relative-to(single-root-only;absent=>p=is-the-raw-ingest-path) -->
<!-- pr_iters=pagerank-power-iterations(stop:L1-residual-below-tol,else-ceiling) pr_converged=0-only-when-ceiling-hit-first(absent=converged;no-such-attr=not-pagerank-ordered) -->
<!-- files=1304 symbols=11348 edges=13926 shown=3 est_tokens=524 ambiguous=5517 unresolved=3202 precise=3 skipped_oversize=15 unindexed="jsonl:25,txt:22,scm:16,tsv:16,lock:6,xml:4" unindexed_exts=17 order=important-first -->
<r root="." est_tokens="524" pr_iters="32">
<f p="src/infra/svector.h" layer="infra">
<s t="method" n="size" id="./src/infra/svector.h::svector::size" k="0.0165">
</s>
<s t="method" n="buf" id="./src/infra/svector.h::svector::buf" overloads="2" k="0.0084">
</s>
</f>
</r>
`````

Artifact written:

`````
 6716360 <scratch>/aux/warm2.ripwirecache
`````

## `./build/ripwire . --max-file-size=8K --top-k=3`

*Skip files above a size bound before parsing (note the corpus shrink in the header).*

`````
<!-- ripwire v1 t=fn|method|cls|struct|iface|var|sec|macro(#define;degraded:body-is-replacement-text,edges-cross-expansion) p=path layer=arch-layer(opt) n=name id=canonical(path::scope::name,when-scoped) k=rank c=call amb=ambiguous-calls(read-source) overloads=N-same-name-defs-merged-into-this-row(absent-if-1;shown=counts-them-individually,so-rows+sum(overloads-1)=shown) prov=scip(precise;else name-based) hdr:unresolved=call-name-defined-only-in-a-lang-incompatible-file (edges heuristic) r:est_tokens=hdr-copy(none-if-stable) -->
<!-- r:root=crawl-root-every-p=-is-relative-to(single-root-only;absent=>p=is-the-raw-ingest-path) -->
<!-- pr_iters=pagerank-power-iterations(stop:L1-residual-below-tol,else-ceiling) pr_converged=0-only-when-ceiling-hit-first(absent=converged;no-such-attr=not-pagerank-ordered) -->
<!-- files=773 symbols=3309 edges=865 shown=3 est_tokens=563 ambiguous=37 unresolved=263 precise=3 skipped_oversize=546 unindexed="jsonl:25,txt:22,scm:16,tsv:16,lock:6,xml:4" unindexed_exts=17 order=important-first -->
<r root="." est_tokens="563" pr_iters="42">
<f p="test/regexfix/beta.py" layer="test">
<s t="fn" n="open" id="./test/regexfix/beta.py::Widget::open" k="0.0038">
</s>
</f>
<f p="src/infra/fastmath.h" layer="infra">
<s t="fn" n="max" id="./src/infra/fastmath.h::fastmath::max" k="0.0029">
</s>
</f>
<f p="src/alloccount.cpp">
<s t="fn" n="countedFree" k="0.0028">
</s>
</f>
</r>
`````

## `./build/ripwire . --scip=does_not_exist.scip --callers=rankGraphTeleport`

*SCIP overlay with a missing index: degrades to name-based, never fails.*

`````
<!-- ripwire callers/callees: the 1-hop call hierarchy read straight off the call graph. The callers form lists the symbols that CALL of=; the callees form lists the symbols of= itself calls. of= is the selector you passed, defs= how many DEFINITIONS that name resolved to (the rows UNION every def's neighbours), and count= the number of DISTINCT neighbour symbols (a floor, per counts_floor=), which the rows window with limit= and offset=. A neighbour that is an indexed function-like #define is a macro row (t="macro", role="macro" on the XML row): the edge crosses a macro expansion, not a plain call — rows carry no role= otherwise. counts_floor="1" means every count on this element is a FLOOR, never a total. Call edges are extracted from source text by NAME, so a call that reaches its target through dynamic dispatch (a virtual, interface or duck-typed receiver), or a declaration that parses without a call expression (C++ most-vexing-parse) contributes no edge and is missing here. A call through a function pointer or callback resolves only when ONE function is bound to that variable in scope (C-family; a reassigned, table-indexed, lambda-bound or escaped pointer — its address taken or reference-bound — still contributes no edge). A binding written as a plain name rather than an address-of (fp = handler, not fp = &handler) is read as a function only when the variable is PROVEN able to hold one: a function-pointer declarator, or a function-pointer typedef declared in the SAME FILE, or a type the parse cannot pin down at all (auto, a template type). Under any other concrete written type it is a value copy and contributes no edge, so a variable whose function-pointer typedef lives in a HEADER is missed. A macro-generated call site contributes a role="macro" edge when its name uniquely names an indexed function-like #define (C-family, t="macro"); a name shared with any non-macro definition stays a plain call for the resolver, and an unindexed macro's call site contributes no edge. Read a zero as "none found", never as "none exists". COUNTING UNIT, and it differs by verb — which is why two of them report different numbers for one symbol. The callers, callees, edit-check, graph-query and pr-context counts are DISTINCT SYMBOLS: repeated calls from one caller, and calls to two overloads of one name, collapse into ONE row, their multiplicity surviving only in the call graph's edge weight. The reach counts (impact's reaches=, pr-context's dependents=) are the size of a transitive reach SET, each symbol counted once — not a count of calls or edges. The uses verb counts call SITES, one row per occurrence, so a larger count= there for the same symbol is these units agreeing, not disagreeing. The map header's edges= is a unit again different — distinct (caller,callee) PAIRS — and that document carries neither this marker nor this clause, so its numbers answer a different question. -->
<!-- root= on this element is the crawl root every p= below is RELATIVE to (single-root runs only; absent => p= is the path ingest itself used, unchanged). -->
<callers of="rankGraphTeleport" defs="1" count="6" root="." counts_floor="1">
<s t="fn" n="runEval" p="src/eval.h:168"/>
<s t="fn" n="rankGraph" p="src/graph.h:2153"/>
<s t="fn" n="anchoredLexicalRank" p="src/graph.h:2489"/>
<s t="fn" n="churnRankedGraph" p="src/main.cpp:12504"/>
<s t="fn" n="runDefaultMap" p="src/main.cpp:12619"/>
<s t="fn" n="getIndex" p="src/mcpindex.h:950"/>
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
<!-- ripwire v1 t=fn|method|cls|struct|iface|var|sec|macro(#define;degraded:body-is-replacement-text,edges-cross-expansion) p=path layer=arch-layer(opt) n=name id=canonical(path::scope::name,when-scoped) k=rank c=call amb=ambiguous-calls(read-source) overloads=N-same-name-defs-merged-into-this-row(absent-if-1;shown=counts-them-individually,so-rows+sum(overloads-1)=shown) prov=scip(precise;else name-based) hdr:unresolved=call-name-defined-only-in-a-lang-incompatible-file (edges heuristic) r:est_tokens=hdr-copy(none-if-stable) -->
<!-- pr_iters=pagerank-power-iterations(stop:L1-residual-below-tol,else-ceiling) pr_converged=0-only-when-ceiling-hit-first(absent=converged;no-such-attr=not-pagerank-ordered) -->
<!-- files=1063 symbols=8308 edges=12770 shown=5 est_tokens=584 ambiguous=5467 unresolved=1424 precise=3 roots=2 unindexed="txt:9,xml:4,arch:2,jsonl:2,tsv:2,cmake:1" unindexed_exts=11 order=important-first -->
<r est_tokens="584" pr_iters="34">
<root label="src" p="src"/>
<root label="test" p="test"/>
<f p="src/./infra/svector.h" layer="infra">
<s t="method" n="size" id="src/./infra/svector.h::svector::size" k="0.0209">
</s>
<s t="method" n="buf" id="src/./infra/svector.h::svector::buf" overloads="2" k="0.0106">
</s>
</f>
<f p="src/./notes.h">
<s t="method" n="empty" id="src/./notes.h::NoteIndex::empty" k="0.0103">
</s>
</f>
<f p="src/./scipoverlay.h">
<s t="method" n="empty" id="src/./scipoverlay.h::ScipOverlay::empty" k="0.0100">
</s>
</f>
</r>
`````

## `./build/ripwire . --eval`

*Self-eval: co-change recall vs BM25.*

**wall time: 3.82s**

`````
ripwire --eval  (co-change recovery, averaged over 80 historical commits)
  ranker     recall@5  recall@10  recall@20
  ripwire        3.1%       5.3%       8.1%
  BM25          10.3%      16.9%      21.0%
  BM25sub       12.8%      18.6%      28.6%
  BM25body      20.2%      34.2%      41.8%
  fused          5.9%      13.6%      22.7%
  anchored      20.2%      34.0%      41.5%
  same-dir       3.4%       6.5%       7.8%
  random         0.4%       0.8%       1.5%   <- floor (random ranking over F=1304 files)
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

**wall time: 4.97s**

`````
ripwire --eval-retrieval  (known-item, 150 doc-commented symbols; gold is in-corpus by construction)
  ranker    query-mode     MRR  recall@1  recall@5 recall@10
  subtoken  name         0.609     49.3%     75.3%     84.7%
  subtoken  doc-phrase   0.746     70.0%     78.7%     82.0%
  name-exact name         0.836     76.0%     94.7%     98.0%
  name-exact doc-phrase   0.022      1.3%      2.7%      3.3%
  anchored  name         0.608     50.0%     73.3%     80.0%
  anchored  doc-phrase   0.742     70.0%     78.0%     80.0%
  routed    name         0.838     76.0%     94.7%     99.3%
  routed    doc-phrase   0.743     70.0%     78.0%     81.3%
  note: routing chose name-exact on 148/150 NAME queries (a NAME query is always identifier-shaped);
        the confidence gate routes doc-phrase queries to name-exact ONLY when EVERY content word names a symbol
        (or an explicit camel/snake token appears) AND every matched name is specific enough to anchor on —
        a common name (many definitions, or a subtoken carried by many symbol names) declines the route — so
        conceptual prose falls back to subtoken+body; routed tracks the better ranker on BOTH modes
        (routed==name-exact on name, ~=subtoken+body on doc-phrase).
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
  overlap       66.7%  100.0%   0.833     0.667    50.0% (th=-1.000)
  name          33.3%   66.7%   0.533     0.667    50.0% (th=0.000)
  bm25-desc    100.0%  100.0%   1.000     1.000   100.0% (th=1.817)
  bm25-full     66.7%  100.0%   0.833     1.000    75.0% (th=0.266)
  for-routed    33.3%   66.7%   0.611     1.000    50.0% (th=0.573)
  random         5.9%   11.8%   0.202     0.500   <- floor (uniform-random ranking; auc 0.5 by definition)
  provenance hit@1 (bm25-desc): router 0/0, desc 0/0, judged 3/3 (desc rows quote the descriptions - expect them easiest; judged is the honest number)
  judged-only hit@1 per arm: overlap 2/3, name 1/3, bm25-desc 3/3, bm25-full 2/3, for-routed 1/3
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
… [19 more lines, 3514 bytes total]
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
# (no-MCP one-shot orientation: ripwire . --for="<task>" --token-budget=2000)
bash skills/install.sh   # deploy to ~/.claude/skills (drift-gated)
bash skills/install.sh --hook   # RECOMMENDED: advisory Read/Grep -> ripwire CLI nudge + session primer (opt-in, never blocks)
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
Defaults to break (less context is measurably MORE accurate, not just cheaper — code-repair
accuracy fell 29% -> 3% as context grew 32K -> 256K tokens, LongCodeBench):
- Do NOT open a file you have not located first: rank with `--for`/`--grep`, then read what it names.
- Do NOT read a whole file to understand one symbol: `--expand=SYM` gives the body + callee sigs.
- Do NOT fan reads across several files to learn one thing: `--pack-task="<task>"` is one call.
# --- end paste ---
`````

## `./build/ripwire --version`

*Version + short build info.*

`````
ripwire 0.3.8 (dev, AppleClang 21.0.0.21000101)
`````


---

# the dirty-tree verbs (throwaway clone, NOT the read-only repo)

Everything below runs with `cwd` = the throwaway clone at `<scratch>/dirty` (`git clone --local` of this repo, then one deliberate regression in `src/infra/sortutil.h`). The read-only repo is never touched. The binary is the same `build/ripwire`, addressed absolutely.

## `./build/ripwire . --situ`

*Situational report for a real diff: blast radius + tests + co-change + forgotten co-change partners.*

`````
ripwire situational-awareness — 1 changed file(s), 12 symbols in them
root: .
  [1] blast radius: 85 symbols across 20 files transitively depend on these changes (showing 8 of 20 files; --pr-context's own per-file blast-radius list is also capped, at 20)
        src/mcpverbs.h  (27 dependent symbols)
        src/main.cpp  (16 dependent symbols)
        src/serialize.h  (8 dependent symbols)
        bench/bench_sort_large.cpp  (5 dependent symbols)
        bench/bench_radix_ab.cpp  (3 dependent symbols)
        src/lanes.h  (3 dependent symbols)
        src/partition.h  (3 dependent symbols)
        src/editcheck.h  (2 dependent symbols)
  [2] tests to run (2):
        test/verify_radix.cpp
        test/adaptivecutshapefix/adaptive_cut_shape_test.cpp   (run: bash test/adaptivecutshapecheck.sh)
        (456 test/*.sh gates are NOT modelled: script-to-binary edges are not call edges, so they never appear here — a path count, not every one invokes the binary)
  [3] co-change — usually edited with these but NOT in your diff (0):
        (none, or no git history)
`````

## `./build/ripwire . --test-gate`

*The pre-PR gate with real obligations — exit 4 when tests-to-run or untested blast radius is non-empty.*

**exit code: 4**

`````
<!-- ripwire test-gate (TDAD-parity, arXiv 2603.17973): the tests to run for this change + the UNTESTED blast radius. A queryable call-graph+test map cut agent-caused regressions -70% (6.08%->1.82%); this gate names the obligations, the agent runs the tests then relies on green. exit 4 if tests OR untested is non-empty. TWO INDEPENDENT LISTINGS, each with its own row count: shown_tests= counts the <t> tests-to-run rows and shown_untested= counts the <u> blast-radius rows (a single shown= could only ever have described one of them). The <t> rows are the COMPLETE obligation and are never windowed, so they REPEAT VERBATIM on every page — a walker that concatenates pages must take them from one page only; offset=/limit= window the <u> rows alone. The <u> listing shows 25 rows by default: raise the default cap with limit=N (offset=M pages). script_gates_unmodelled= counts test/*.sh runners in the corpus (a path count; not every one invokes the binary) - script-to-binary edges are NOT modelled, so those gates are invisible to this walk and never counted in tests=. UNIT: untested= here counts impacted SYMBOLS. The seams verb spells untested= over cross-directory call EDGES and the flip verb over the defs a gate lights, so the three numbers count three different things and must never be compared or summed across verbs. -->
<test-gate changed="1" impacted="85" tests="2" untested="81" shown_tests="2" tests_capped="0" shown_untested="25" untested_capped="1" script_gates_unmodelled="456" at="700e51d49+dirty">
<t p="./test/adaptivecutshapefix/adaptive_cut_shape_test.cpp" run="bash test/adaptivecutshapecheck.sh"/>
<t p="./test/verify_radix.cpp"/>
<u sym="buildGraph" p="./src/graph.h" ccx="761"/>
<u sym="dispatchMcpLine" p="./src/mcp.h" ccx="427"/>
<u sym="main" p="./src/main.cpp" ccx="390"/>
<u sym="runQualityDelta" p="./src/main.cpp" ccx="201"/>
<u sym="packSignatures" p="./src/serialize.h" ccx="200"/>
<u sym="runDefaultMap" p="./src/main.cpp" ccx="197"/>
<u sym="serialize" p="./src/serialize.h" ccx="191"/>
<u sym="runForLens" p="./src/main.cpp" ccx="184"/>
<u sym="packTaskBundleText" p="./src/packtask.h" ccx="150"/>
<u sym="runBatchSub" p="./src/mcpverbs.h" ccx="100"/>
<u sym="packLego" p="./src/serialize.h" ccx="85"/>
<u sym="serializeJson" p="./src/serialize.h" ccx="85"/>
<u sym="runMcpHttp" p="./src/mcpserver.h" ccx="81"/>
<u sym="fetchBody" p="./src/mcpverbs.h" ccx="72"/>
<u sym="runEval" p="./src/eval.h" ccx="66"/>
<u sym="forTaskText" p="./src/mcpverbs.h" ccx="43"/>
<u sym="qualityDeltaJson" p="./src/mcpverbs.h" ccx="40"/>
<u sym="runTargetedViews" p="./src/main.cpp" ccx="39"/>
<u sym="getIndex" p="./src/mcpindex.h" ccx="39"/>
<u sym="packTaskText" p="./src/mcpverbs.h" ccx="30"/>
<u sym="packSignaturesJson" p="./src/serialize.h" ccx="29"/>
<u sym="situationDiffJson" p="./src/mcpverbs.h" ccx="27"/>
<u sym="usesText" p="./src/mcpverbs.h" ccx="27"/>
<u sym="packTaskPartitionText" p="./src/partition.h" ccx="27"/>
<u sym="packGraphBlock" p="./src/serialize.h" ccx="24"/>
</test-gate>
`````

## `./build/ripwire . --quality-delta`

*CHANGED: every row now carries p="file:line", the gating rows are marked gating="1", and exit 2 prints a naming line on stderr.*

**exit code: 2** — **wall time: 3.20s**

`````
<!-- ripwire quality-delta: only what a change made WORSE against the floor named by baseline= below. FOUR floors, and they are not interchangeable: sidecar = the pinned .ripwire_quality_baseline snapshot, honored only because it was pinned at the CURRENT git HEAD; git-HEAD = no sidecar existed, so the working tree was auto-compared against the HEAD tree; git-HEAD (stale sidecar removed) = a sidecar existed, was pinned at a DIFFERENT sha, and this run DELETED it from your working tree before falling back to HEAD (re-pin with quality-baseline); git-HEAD (stale sidecar ignored) = same staleness verdict, but the file was left on disk (the read-only MCP arm, or an unlink that failed). Only the first is a floor YOU chose; the other three compare against HEAD, so anything already committed cannot appear. A FIFTH marker, ref-pair, means none of those: the verb was given a RANGE, so it compared two COMMITTED trees and no sidecar was read, written or deleted. Those reports carry base_ref= and target_ref= (the two RESOLVED shas, at full length, because a wave number gets quoted into handoffs) and OMIT at=, since the pair is the anchor. They also carry churn set to unavailable, which is the honest statement that one of the ten kinds, short-horizon-churn, cannot be measured there at all: it needs git history at the tree being judged, and both trees are materialized OUT of the repo into temp dirs. Its silence in such a report is therefore not evidence that nothing churned. at= is the git commit (plus a dirty marker when the working tree differs) this list was computed at. Findings: complexity over the ccx bar, verbosity (LOC)/nesting/params regressions, new duplication, newly-dead, new public api-surface (contract drift), error-masking, short-horizon churn, new clone of a reused helper. THREE independent axes, applied in this order: (1) acked findings are suppressed entirely (acked= counts them, honestly); (2) ORIGIN — a finding on a symbol that EXISTED at the baseline is preexisting-worse (no origin= attribute), one that exists only because the code is NEW carries origin="new-symbol"; (3) MATERIALITY — a small numeric delta is sev="minor". EXIT 2 fires only on preexisting-worse AND major, i.e. gating="N" above; new-symbol rows never gate. Clone kinds classify by their member set (a group is new-symbol only if EVERY member is new); short-horizon-churn is preexisting by construction. exit 0 is NOT a verdict on the new-symbol rows — nothing that existed got worse, but the new debt is yours: read them. LIMIT: origin is canonId identity (path::scope::name), so a RENAMED or MOVED symbol reads as new — a regression carried in with a move classifies new-symbol and will not gate. Descriptive: weigh + fix the real ones, do not game the number (a wrong abstraction beats a low score). stale="N" is a SEPARATE axis, never gating, over the .ripwire_quality_acks ledger: an ack whose target no longer applies. Each sa row's why is target-gone (the key names no symbol/group any more) or finding-gone (the target survived, this kind just does not fire on it) — hygiene disclosure only, the ledger file is never auto-edited. Each row carries kind= (which of the measured axes regressed) and sym= (the canonical id it regressed on) — except duplication rows, which name the whole clone group rather than one symbol: members= is the group's member list and tokens= its shared normalized-token count (the same per-group pair the clones verb reports) — plus p="path:line" (root-relative; the first-sorting member for the clone kinds; omitted, never faked, when no locator resolves), and every row the header's gating= counter counts also carries a gating attribute set to 1 — those are the rows the exit code fires on, and they are now marked positively rather than by the ABSENCE of sev/origin. (This sentence deliberately spells no attribute=value literal: the header counters are parsed by grep in several gates, and a quoted numeric example here would be matched first.) -->
<quality-delta baseline="git-HEAD" regressions="8" minor="2" acked="0" stale="16" preexisting-worse="5" new-symbol="3" gating="5" at="700e51d49+dirty">
<r kind="api-surface" sym="src/infra/sortutil.h::rw::sortutil::nonNegativeFloatAscKeyCopy" sev="minor" surface="new-symbol" origin="new-symbol" p="src/infra/sortutil.h:84"/>
<r kind="api-surface" sym="src/infra/sortutil.h::rw::sortutil::nonNegativeFloatDescKey" was="1" now="2" surface="contract-change" p="src/infra/sortutil.h:74" gating="1"/>
<r kind="api-surface" sym="src/infra/sortutil.h::rw::sortutil::sortScoredIdsWithOptions" sev="minor" surface="new-symbol" origin="new-symbol" p="src/infra/sortutil.h:94"/>
<r kind="complexity" sym="src/infra/sortutil.h::rw::sortutil::lessByScoreDescId" was="1" now="67" p="src/infra/sortutil.h:14" gating="1"/>
<r kind="duplication" members="src/infra/sortutil.h::rw::sortutil::nonNegativeFloatAscKeyCopy | src/infra/sortutil.h::rw::sortutil::nonNegativeFloatDescKey" tokens="59" p="src/infra/sortutil.h:84" gating="1"/>
<r kind="nesting" sym="src/infra/sortutil.h::rw::sortutil::lessByScoreDescId" was="1" now="6" p="src/infra/sortutil.h:14" gating="1"/>
<r kind="new-clone-of-reused-helper" sym="src/infra/sortutil.h::rw::sortutil::nonNegativeFloatAscKeyCopy | src/infra/sortutil.h::rw::sortutil::nonNegativeFloatDescKey" was="0" now="4" p="src/infra/sortutil.h:84" gating="1"/>
<r kind="params" sym="src/infra/sortutil.h::rw::sortutil::sortScoredIdsWithOptions" was="0" now="8" origin="new-symbol" p="src/infra/sortutil.h:94"/>
<sa kind="complexity" key="f8f91456c234074f" why="target-gone"/>
<sa kind="complexity" key="fcc9389382ada1b0" why="target-gone"/>
<sa kind="dead-code:preexisting" key="44da49cd9a05e5cc" why="finding-gone"/>
<sa kind="dead-code:preexisting" key="b89dc1827832d2fd" why="finding-gone"/>
<sa kind="duplication" key="4a6d699a2b38f977" why="finding-gone"/>
<sa kind="duplication" key="69ca0068a413b01f" why="finding-gone"/>
<sa kind="duplication" key="6bbb331c18a5deaf" why="finding-gone"/>
<sa kind="short-horizon-churn" key="1b8cc1b791b2c572" why="target-gone"/>
<sa kind="short-horizon-churn" key="1fb1007e9ca0c20b" why="target-gone"/>
<sa kind="short-horizon-churn" key="8bd48de4f0863ced" why="target-gone"/>
<sa kind="short-horizon-churn" key="c00a0f11de7e013b" why="target-gone"/>
<sa kind="verbosity" key="0c653cfea680bc82" why="target-gone"/>
<sa kind="verbosity" key="5fb2e376a4a3a687" why="target-gone"/>
<sa kind="verbosity" key="69b66b3ba85ecc62" why="finding-gone"/>
<sa kind="verbosity" key="cbde843c21e1be3b" why="target-gone"/>
<sa kind="verbosity" key="f8f91456c234074f" why="target-gone"/>
</quality-delta>
`````

stderr:

`````
ripwire: no ./.ripwire_quality_baseline — auto-comparing the working tree vs git HEAD (commit the baseline with --quality-baseline to pin it)
ripwire: --quality-delta gating: 5 preexisting-worse major finding(s); first: api-surface ./src/infra/sortutil.h::rw::sortutil::nonNegativeFloatDescKey at src/infra/sortutil.h:74 (was=1 now=2)
`````

## `./build/ripwire . --quality-delta --json`

*The same findings as JSON (one of the CI/scripting verbs --json supports).*

**exit code: 2** — **wall time: 1.30s**

`````
{"baseline":"git-HEAD","regressions":8,"minor":2,"acked":0,"stale":16,"preexisting-worse":5,"new-symbol":3,"gating":5,"at":"700e51d49+dirty","r":[{"kind":"api-surface","sym":"src/infra/sortutil.h::rw::sortutil::nonNegativeFloatAscKeyCopy","p":"src/infra/sortutil.h:84","sev":"minor","surface":"new-sy … [line truncated: 29 more bytes on this line]
{"kind":"api-surface","sym":"src/infra/sortutil.h::rw::sortutil::nonNegativeFloatDescKey","was":1,"now":2,"p":"src/infra/sortutil.h:74","gating":true,"surface":"contract-change"},
{"kind":"api-surface","sym":"src/infra/sortutil.h::rw::sortutil::sortScoredIdsWithOptions","p":"src/infra/sortutil.h:94","sev":"minor","surface":"new-symbol","origin":"new-symbol"},
{"kind":"complexity","sym":"src/infra/sortutil.h::rw::sortutil::lessByScoreDescId","was":1,"now":67,"p":"src/infra/sortutil.h:14","gating":true},
{"kind":"duplication","members":"src/infra/sortutil.h::rw::sortutil::nonNegativeFloatAscKeyCopy | src/infra/sortutil.h::rw::sortutil::nonNegativeFloatDescKey","tokens":59,"p":"src/infra/sortutil.h:84","gating":true},
{"kind":"nesting","sym":"src/infra/sortutil.h::rw::sortutil::lessByScoreDescId","was":1,"now":6,"p":"src/infra/sortutil.h:14","gating":true},
{"kind":"new-clone-of-reused-helper","sym":"src/infra/sortutil.h::rw::sortutil::nonNegativeFloatAscKeyCopy | src/infra/sortutil.h::rw::sortutil::nonNegativeFloatDescKey","was":0,"now":4,"p":"src/infra/sortutil.h:84","gating":true},
{"kind":"params","sym":"src/infra/sortutil.h::rw::sortutil::sortScoredIdsWithOptions","was":0,"now":8,"p":"src/infra/sortutil.h:94","origin":"new-symbol"}],
"sa":[{"kind":"complexity","key":"f8f91456c234074f","why":"target-gone"},
{"kind":"complexity","key":"fcc9389382ada1b0","why":"target-gone"},
{"kind":"dead-code:preexisting","key":"44da49cd9a05e5cc","why":"finding-gone"},
{"kind":"dead-code:preexisting","key":"b89dc1827832d2fd","why":"finding-gone"},
{"kind":"duplication","key":"4a6d699a2b38f977","why":"finding-gone"},
{"kind":"duplication","key":"69ca0068a413b01f","why":"finding-gone"},
{"kind":"duplication","key":"6bbb331c18a5deaf","why":"finding-gone"},
{"kind":"short-horizon-churn","key":"1b8cc1b791b2c572","why":"target-gone"},
{"kind":"short-horizon-churn","key":"1fb1007e9ca0c20b","why":"target-gone"},
{"kind":"short-horizon-churn","key":"8bd48de4f0863ced","why":"target-gone"},
{"kind":"short-horizon-churn","key":"c00a0f11de7e013b","why":"target-gone"},
{"kind":"verbosity","key":"0c653cfea680bc82","why":"target-gone"},
{"kind":"verbosity","key":"5fb2e376a4a3a687","why":"target-gone"},
{"kind":"verbosity","key":"69b66b3ba85ecc62","why":"finding-gone"},
{"kind":"verbosity","key":"cbde843c21e1be3b","why":"target-gone"},
{"kind":"verbosity","key":"f8f91456c234074f","why":"target-gone"}]}
`````

stderr:

`````
ripwire: no ./.ripwire_quality_baseline — auto-comparing the working tree vs git HEAD (commit the baseline with --quality-baseline to pin it)
ripwire: --quality-delta gating: 5 preexisting-worse major finding(s); first: api-surface ./src/infra/sortutil.h::rw::sortutil::nonNegativeFloatDescKey at src/infra/sortutil.h:74 (was=1 now=2)
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
ripwire: --ack-only=zzznope matched none of the 8 finding(s) — nothing written
`````

## `./build/ripwire . --quality-delta --quality-ack --ack-only=api-surface`

*NEW FLAG: ack only the api-surface findings — a per-finding ratchet instead of a rubber stamp.*

`````
(empty)
`````

stderr:

`````
ripwire: no ./.ripwire_quality_baseline — auto-comparing the working tree vs git HEAD (commit the baseline with --quality-baseline to pin it)
ripwire: acknowledged 3 of 8 finding(s) (5 left UNACKED by --ack-only, 0 already acked) → ./.ripwire_quality_acks
`````

## `./build/ripwire . --quality-delta`

*Re-run after the partial ack: acked=3, the rest still gate.*

**exit code: 2** — **wall time: 1.27s**

`````
<!-- ripwire quality-delta: only what a change made WORSE against the floor named by baseline= below. FOUR floors, and they are not interchangeable: sidecar = the pinned .ripwire_quality_baseline snapshot, honored only because it was pinned at the CURRENT git HEAD; git-HEAD = no sidecar existed, so the working tree was auto-compared against the HEAD tree; git-HEAD (stale sidecar removed) = a sidecar existed, was pinned at a DIFFERENT sha, and this run DELETED it from your working tree before falling back to HEAD (re-pin with quality-baseline); git-HEAD (stale sidecar ignored) = same staleness verdict, but the file was left on disk (the read-only MCP arm, or an unlink that failed). Only the first is a floor YOU chose; the other three compare against HEAD, so anything already committed cannot appear. A FIFTH marker, ref-pair, means none of those: the verb was given a RANGE, so it compared two COMMITTED trees and no sidecar was read, written or deleted. Those reports carry base_ref= and target_ref= (the two RESOLVED shas, at full length, because a wave number gets quoted into handoffs) and OMIT at=, since the pair is the anchor. They also carry churn set to unavailable, which is the honest statement that one of the ten kinds, short-horizon-churn, cannot be measured there at all: it needs git history at the tree being judged, and both trees are materialized OUT of the repo into temp dirs. Its silence in such a report is therefore not evidence that nothing churned. at= is the git commit (plus a dirty marker when the working tree differs) this list was computed at. Findings: complexity over the ccx bar, verbosity (LOC)/nesting/params regressions, new duplication, newly-dead, new public api-surface (contract drift), error-masking, short-horizon churn, new clone of a reused helper. THREE independent axes, applied in this order: (1) acked findings are suppressed entirely (acked= counts them, honestly); (2) ORIGIN — a finding on a symbol that EXISTED at the baseline is preexisting-worse (no origin= attribute), one that exists only because the code is NEW carries origin="new-symbol"; (3) MATERIALITY — a small numeric delta is sev="minor". EXIT 2 fires only on preexisting-worse AND major, i.e. gating="N" above; new-symbol rows never gate. Clone kinds classify by their member set (a group is new-symbol only if EVERY member is new); short-horizon-churn is preexisting by construction. exit 0 is NOT a verdict on the new-symbol rows — nothing that existed got worse, but the new debt is yours: read them. LIMIT: origin is canonId identity (path::scope::name), so a RENAMED or MOVED symbol reads as new — a regression carried in with a move classifies new-symbol and will not gate. Descriptive: weigh + fix the real ones, do not game the number (a wrong abstraction beats a low score). stale="N" is a SEPARATE axis, never gating, over the .ripwire_quality_acks ledger: an ack whose target no longer applies. Each sa row's why is target-gone (the key names no symbol/group any more) or finding-gone (the target survived, this kind just does not fire on it) — hygiene disclosure only, the ledger file is never auto-edited. Each row carries kind= (which of the measured axes regressed) and sym= (the canonical id it regressed on) — except duplication rows, which name the whole clone group rather than one symbol: members= is the group's member list and tokens= its shared normalized-token count (the same per-group pair the clones verb reports) — plus p="path:line" (root-relative; the first-sorting member for the clone kinds; omitted, never faked, when no locator resolves), and every row the header's gating= counter counts also carries a gating attribute set to 1 — those are the rows the exit code fires on, and they are now marked positively rather than by the ABSENCE of sev/origin. (This sentence deliberately spells no attribute=value literal: the header counters are parsed by grep in several gates, and a quoted numeric example here would be matched first.) -->
<quality-delta baseline="git-HEAD" regressions="5" minor="0" acked="3" stale="16" preexisting-worse="4" new-symbol="1" gating="4" at="700e51d49+dirty">
<r kind="complexity" sym="src/infra/sortutil.h::rw::sortutil::lessByScoreDescId" was="1" now="67" p="src/infra/sortutil.h:14" gating="1"/>
<r kind="duplication" members="src/infra/sortutil.h::rw::sortutil::nonNegativeFloatAscKeyCopy | src/infra/sortutil.h::rw::sortutil::nonNegativeFloatDescKey" tokens="59" p="src/infra/sortutil.h:84" gating="1"/>
<r kind="nesting" sym="src/infra/sortutil.h::rw::sortutil::lessByScoreDescId" was="1" now="6" p="src/infra/sortutil.h:14" gating="1"/>
<r kind="new-clone-of-reused-helper" sym="src/infra/sortutil.h::rw::sortutil::nonNegativeFloatAscKeyCopy | src/infra/sortutil.h::rw::sortutil::nonNegativeFloatDescKey" was="0" now="4" p="src/infra/sortutil.h:84" gating="1"/>
<r kind="params" sym="src/infra/sortutil.h::rw::sortutil::sortScoredIdsWithOptions" was="0" now="8" origin="new-symbol" p="src/infra/sortutil.h:94"/>
<sa kind="complexity" key="f8f91456c234074f" why="target-gone"/>
<sa kind="complexity" key="fcc9389382ada1b0" why="target-gone"/>
<sa kind="dead-code:preexisting" key="44da49cd9a05e5cc" why="finding-gone"/>
<sa kind="dead-code:preexisting" key="b89dc1827832d2fd" why="finding-gone"/>
<sa kind="duplication" key="4a6d699a2b38f977" why="finding-gone"/>
<sa kind="duplication" key="69ca0068a413b01f" why="finding-gone"/>
<sa kind="duplication" key="6bbb331c18a5deaf" why="finding-gone"/>
<sa kind="short-horizon-churn" key="1b8cc1b791b2c572" why="target-gone"/>
<sa kind="short-horizon-churn" key="1fb1007e9ca0c20b" why="target-gone"/>
<sa kind="short-horizon-churn" key="8bd48de4f0863ced" why="target-gone"/>
<sa kind="short-horizon-churn" key="c00a0f11de7e013b" why="target-gone"/>
<sa kind="verbosity" key="0c653cfea680bc82" why="target-gone"/>
<sa kind="verbosity" key="5fb2e376a4a3a687" why="target-gone"/>
<sa kind="verbosity" key="69b66b3ba85ecc62" why="finding-gone"/>
<sa kind="verbosity" key="cbde843c21e1be3b" why="target-gone"/>
<sa kind="verbosity" key="f8f91456c234074f" why="target-gone"/>
</quality-delta>
`````

stderr:

`````
ripwire: no ./.ripwire_quality_baseline — auto-comparing the working tree vs git HEAD (commit the baseline with --quality-baseline to pin it)
ripwire: --quality-delta gating: 4 preexisting-worse major finding(s); first: complexity ./src/infra/sortutil.h::rw::sortutil::lessByScoreDescId at src/infra/sortutil.h:14 (was=1 now=67)
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
<!-- ripwire edit-check: SYM's contract (param count + publicness) NOW vs git HEAD — unchanged/new-symbol/contract-change — plus its 1-hop callers. A caller is flagged incompatible="1" when its argument count was reliably counted and NO definition in the folded set could accept it: every one has a FIXED arity that disagrees. A variadic, defaulted or implicit-receiver definition (a Python/Ruby method, whose params counts the self/cls the call site never writes) has no fixed arity and is never flagged. That makes the ARITY half one-sided — a call the compared definitions could accept is never flagged — but it is NOT a proof that the call site binds to THIS definition. Call edges are matched by NAME, so a receiver-qualified call to a same-named callee this tool does not index (a standard-library or third-party method) is measured against the one definition it does index; a clean, compiling tree can therefore carry a nonzero incompatible= with nothing edited at all, and on a widely-shared name it can be most of that name's callers. Read incompatible= as a fact about the tree as it stands — call sites worth OPENING, not a verdict — and status= as a fact about the edit. Warm path hits the qheadsnap/qsnap cache — never a full quality-delta style recompute. defs= is how many DEFINITIONS at this site (same file, same scope, same name — the overload set) are folded into this one contract; a selector matching more than one SITE is refused instead, so defs= only ever counts overloads. params_was and params_now are the MAX over that set on each side (the same MAX the baseline snapshot stores), and publicness is the OR. That MAX has TWO consequences, in opposite directions. It can read like a break and not be one: adding a WIDER overload beside an unchanged one raises params_now with no existing definition altered, so it reports status="contract-change" with incompatible="0" and a def row still carrying the old parameter count — no seen caller breaks. And it can read like safety and not be: REMOVING an overload whose parameter count is BELOW the MAX moves neither number, because the MAX survives on both sides, while the call site that used the removed definition no longer binds. defs_was=/defs_now= is what closes that: the count of definitions sharing this symbol's CANONICAL ID on each side. That population is the one the baseline snapshot buckets by, so the two numbers answer the same question and are equal on an unedited tree — it is deliberately NOT the root's defs=, which is the same bucket narrowed to this FILE (a contract is per definition site), so where a scope-less name also exists in another file defs= is the smaller of the two. status is therefore the join of THREE was-vs-now facts — the params MAX, publicness, and the definition COUNT — and change= names which of them carried it. change= adds broken-callers when a seen caller is also flagged, but never on its own — for the reason stated at the top: incompatible= describes the TREE and status= describes the EDIT, so a headline must not turn on it. RESIDUAL: an overload whose arity changes BELOW the MAX while the COUNT stays the same moves none of the three. The root's incompatible= is the COUNT of flagged callers (a c row's incompatible="1" is the per-caller flag). p= is the definition the selector resolved to; when defs is above 1 EVERY folded definition is listed as its own def row (p=, t=, params=), which is what tells a widened single definition apart from an added overload. At defs="1" no def row is emitted: the root's own p=/t= is that definition, and params_now is its parameter count. counts_floor="1" means every count on this element is a FLOOR, never a total. Call edges are extracted from source text by NAME, so a call that reaches its target through dynamic dispatch (a virtual, interface or duck-typed receiver), or a declaration that parses without a call expression (C++ most-vexing-parse) contributes no edge and is missing here. A call through a function pointer or callback resolves only when ONE function is bound to that variable in scope (C-family; a reassigned, table-indexed, lambda-bound or escaped pointer — its address taken or reference-bound — still contributes no edge). A binding written as a plain name rather than an address-of (fp = handler, not fp = &handler) is read as a function only when the variable is PROVEN able to hold one: a function-pointer declarator, or a function-pointer typedef declared in the SAME FILE, or a type the parse cannot pin down at all (auto, a template type). Under any other concrete written type it is a value copy and contributes no edge, so a variable whose function-pointer typedef lives in a HEADER is missed. A macro-generated call site contributes a role="macro" edge when its name uniquely names an indexed function-like #define (C-family, t="macro"); a name shared with any non-macro definition stays a plain call for the resolver, and an unindexed macro's call site contributes no edge. Read a zero as "none found", never as "none exists". COUNTING UNIT, and it differs by verb — which is why two of them report different numbers for one symbol. The callers, callees, edit-check, graph-query and pr-context counts are DISTINCT SYMBOLS: repeated calls from one caller, and calls to two overloads of one name, collapse into ONE row, their multiplicity surviving only in the call graph's edge weight. The reach counts (impact's reaches=, pr-context's dependents=) are the size of a transitive reach SET, each symbol counted once — not a count of calls or edges. The uses verb counts call SITES, one row per occurrence, so a larger count= there for the same symbol is these units agreeing, not disagreeing. The map header's edges= is a unit again different — distinct (caller,callee) PAIRS — and that document carries neither this marker nor this clause, so its numbers answer a different question. -->
<edit-check sym="nonNegativeFloatDescKey" t="fn" p="src/infra/sortutil.h:74" status="contract-change" defs="1" params_was="1" params_now="2" public_was="1" public_now="1" defs_was="1" defs_now="1" change="params,broken-callers" callers="4" incompatible="4" at="700e51d49+dirty" counts_floor="1" root= … [line truncated: 4 more bytes on this line]
<c n="benchScores" p="bench/bench_radix_ab.cpp:133" incompatible="1"/>
<c n="benchAdaptive" p="bench/bench_radix_ab.cpp:157" incompatible="1"/>
<c n="radixSortNonNegativeFloatsDesc" p="src/infra/sortutil.h:103" incompatible="1"/>
<c n="radixSortByScoreDescId" p="src/infra/sortutil.h:118" incompatible="1"/>
</edit-check>
`````

## `./build/ripwire . --pr-context`

*The review-evidence bundle with an actual changed file.*

`````
<!-- ripwire pr-context: no-LLM review-evidence bundle per changed file — defined symbols, their callers, blast radius (transitive dependents), affected tests, co-change partners not in the diff, and owners. base=working-tree. skipped_mode_only=diffs that changed a file's MODE and nothing else (e.g. chmod) excluded from the changed set; a pure RENAME is content-identical too but is NOT excluded — it is a changed file, listed at its new path. files= means two different things by DEPTH here and is deliberately not renamed (15 consumers read the root one): on the ROOT it is the CHANGED file count; on each <impact/> child it is the distinct files dependents= reaches (changed + non-changed), so dependents="0" implies files="0" and vice versa — never an impossible-looking dependents>0/files=0. files_other= on the same <impact/> is the non-changed subset (a changed file's dependents inside OTHER changed files have no <f> row of their own — they are already shown as their own <file> section); it is NOT the <f> row count — see the row-cap sentence below. Files are ordered by BLAST RADIUS (transitive dependents descending, path breaking ties), not alphabetically. sections= on changed-symbols counts a doc file's headings, collapsed into that number instead of one callers-zero row each; count= still counts every INDEXED symbol, sections included, so count minus sections is the number of rows that follow. Every nested list below is a TOP-N subset of its element's own total, fixed per element (impact <f> at 20, per-symbol <caller> at 12, cochange <partner> at 12, tests <test> at 40, owners <author> at 5 — the L0 defaults; max-tokens only lowers these further via the trim ladder, nothing raises them past L0): each capped element carries its own shown=/capped= pair so the cut is never silent — for the untrimmed list use impact=SYM/callers=SYM (blast radius/callers), affected=FILE or situ (tests), cochange (partners), or owners (authors) instead. direction= names which SIDE this bundle reviews (worktree-since-head, head-since-fork, head-since-ref-tip); a no-ref-work row says the base ref's tip IS the merge base, i.e. it carries no divergent work of its own. deterministic. counts_floor="1" means every count on this element is a FLOOR, never a total. Call edges are extracted from source text by NAME, so a call that reaches its target through dynamic dispatch (a virtual, interface or duck-typed receiver), or a declaration that parses without a call expression (C++ most-vexing-parse) contributes no edge and is missing here. A call through a function pointer or callback resolves only when ONE function is bound to that variable in scope (C-family; a reassigned, table-indexed, lambda-bound or escaped pointer — its address taken or reference-bound — still contributes no edge). A binding written as a plain name rather than an address-of (fp = handler, not fp = &handler) is read as a function only when the variable is PROVEN able to hold one: a function-pointer declarator, or a function-pointer typedef declared in the SAME FILE, or a type the parse cannot pin down at all (auto, a template type). Under any other concrete written type it is a value copy and contributes no edge, so a variable whose function-pointer typedef lives in a HEADER is missed. A macro-generated call site contributes a role="macro" edge when its name uniquely names an indexed function-like #define (C-family, t="macro"); a name shared with any non-macro definition stays a plain call for the resolver, and an unindexed macro's call site contributes no edge. Read a zero as "none found", never as "none exists". COUNTING UNIT, and it differs by verb — which is why two of them report different numbers for one symbol. The callers, callees, edit-check, graph-query and pr-context counts are DISTINCT SYMBOLS: repeated calls from one caller, and calls to two overloads of one name, collapse into ONE row, their multiplicity surviving only in the call graph's edge weight. The reach counts (impact's reaches=, pr-context's dependents=) are the size of a transitive reach SET, each symbol counted once — not a count of calls or edges. The uses verb counts call SITES, one row per occurrence, so a larger count= there for the same symbol is these units agreeing, not disagreeing. The map header's edges= is a unit again different — distinct (caller,callee) PAIRS — and that document carries neither this marker nor this clause, so its numbers answer a different question. -->
<pr-context base="working-tree" root="." direction="worktree-since-head" files="1" skipped_mode_only="0" at="700e51d49+dirty" counts_floor="1">
<file p="src/infra/sortutil.h" symbols="12">
<impact dependents="85" files="20" files_other="20" shown="20" capped="0">
<f p="src/mcpverbs.h" deps="27"/>
<f p="src/main.cpp" deps="16"/>
<f p="src/serialize.h" deps="8"/>
<f p="bench/bench_sort_large.cpp" deps="5"/>
<f p="bench/bench_radix_ab.cpp" deps="3"/>
<f p="src/lanes.h" deps="3"/>
<f p="src/partition.h" deps="3"/>
<f p="src/editcheck.h" deps="2"/>
<f p="src/graph.h" deps="2"/>
<f p="src/mcp.h" deps="2"/>
<f p="src/mcpindex.h" deps="2"/>
<f p="src/packtask.h" deps="2"/>
<f p="src/quality.h" deps="2"/>
<f p="test/verify_radix.cpp" deps="2"/>
<f p="src/eval.h" deps="1"/>
<f p="src/lexical.h" deps="1"/>
<f p="src/mcpedit.h" deps="1"/>
<f p="src/mcpserver.h" deps="1"/>
<f p="src/tracelocus.h" deps="1"/>
<f p="test/adaptivecutshapefix/adaptive_cut_shape_test.cpp" deps="1"/>
</impact>
<tests count="2" shown="2" capped="0">
<test p="test/adaptivecutshapefix/adaptive_cut_shape_test.cpp" run="bash test/adaptivecutshapecheck.sh"/>
<test p="test/verify_radix.cpp"/>
</tests>
<changed-symbols count="12">
… [71 more display lines; full output is 9523 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --map-diff --top-k=5`

*The map re-ranked with a teleport toward the changed file (changed=1 here, not 0).*

`````
<!-- ripwire v1 t=fn|method|cls|struct|iface|var|sec|macro(#define;degraded:body-is-replacement-text,edges-cross-expansion) p=path layer=arch-layer(opt) n=name id=canonical(path::scope::name,when-scoped) k=rank c=call amb=ambiguous-calls(read-source) overloads=N-same-name-defs-merged-into-this-row(absent-if-1;shown=counts-them-individually,so-rows+sum(overloads-1)=shown) prov=scip(precise;else name-based) hdr:unresolved=call-name-defined-only-in-a-lang-incompatible-file (edges heuristic) r:est_tokens=hdr-copy(none-if-stable) -->
<!-- r:root=crawl-root-every-p=-is-relative-to(single-root-only;absent=>p=is-the-raw-ingest-path) -->
<!-- at= is the git commit these numbers were computed at; a trailing +dirty means the working tree differed from that commit, so the numbers describe the tree, not the commit -->
<!-- pr_iters=pagerank-power-iterations(stop:L1-residual-below-tol,else-ceiling) pr_converged=0-only-when-ceiling-hit-first(absent=converged;no-such-attr=not-pagerank-ordered) -->
<!-- files=1304 symbols=11350 edges=13929 shown=5 est_tokens=1055 ambiguous=5520 unresolved=3202 precise=3 changed=1 skipped_oversize=15 unindexed="jsonl:25,txt:22,scm:16,tsv:16,lock:6,xml:4" unindexed_exts=17 order=important-first -->
<r at="700e51d49+dirty" root="." est_tokens="1055" pr_iters="22">
<f p="src/infra/sortutil.h" layer="infra">
<s t="fn" n="radixSortByScoreDescId" id="./src/infra/sortutil.h::rw::sortutil::radixSortByScoreDescId" amb="9" k="0.0919">
<c n="size"/>
<c n="begin"/>
<c n="end"/>
<c n="begin"/>
<c n="end"/>
<c n="begin"/>
<c n="end"/>
<c n="begin"/>
<c n="end"/>
<c n="lessByScoreDescId"/>
<c n="radixSortUint32ByKey"/>
<c n="nonNegativeFloatDescKey"/>
<c n="begin"/>
<c n="end"/>
<c n="begin"/>
<c n="end"/>
<c n="size"/>
</s>
<s t="fn" n="radixSortByFromTo" id="./src/infra/sortutil.h::rw::sortutil::radixSortByFromTo" amb="8" k="0.0630">
<c n="size"/>
<c n="begin"/>
<c n="end"/>
… [35 more display lines; full output is 2621 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --clones`

*The duplicated helper the sandbox edit introduced shows up as a clone group.*

`````
<!-- ripwire clones: function bodies with similar normalized token streams (identifiers/literals normalized, so renamed copies match). type=2 exact/renamed (Type-1/2); type=3 gapped near-miss (an inserted/changed statement, similarity in [0.80,1.0)). Reuse don't reimplement; a fix to one likely belongs in all. groups= and type3= are the two GROUP-TYPE totals (each capped independently, so neither is the row count); total= is the true row total (groups + type3-group-count) and is ALWAYS present, paged or not; shown= is the number of group rows that follow this run. capped="1" means rows were dropped. exempt= on a group ⇒ every member is on a path the quality-delta verb's duplication kind deliberately ignores (fixture dirs / shell test-runners repeat boilerplate by convention) — a fact here, never a gate there; exempt_groups= counts them over ALL groups. gid= on a row is its CLONE COMPONENT: the Type-3 pass reports PAIRS, so three functions that are all near-copies of each other arrive as three rows of two; rows sharing a gid are one cluster, and clone_groups= counts the clusters (union-find over the pair graph, over ALL detected rows, not just the shown ones). dup_pct=duplicated-LOC/total-LOC as a percentage, where duplicated-LOC sums, per cluster, every member's loc EXCEPT the largest member's (one instance is the code you keep, the rest is the redundancy — so a 3-clone cluster counts its lines TWICE) and total-LOC is every function/method body the detector considered; dup_loc= and total_loc= are those two operands. counts_floor="1": the Type-3 pair list is capped upstream, so a dropped pair is a cluster left unmerged — clone_groups/dup_loc/dup_pct are floors, never totals. raise the default cap with limit=N (offset=M pages). -->
<!-- root= on this element is the crawl root every p= below is RELATIVE to (single-root runs only; absent => p= is the path ingest itself used, unchanged). -->
<clones groups="55" type3="253" total="308" exempt_groups="121" clone_groups="183" dup_loc="3513" total_loc="110517" dup_pct="3.2" counts_floor="1" shown="80" capped="1" root=".">
<group type="2" gid="158" tokens="207" n="4" exempt="shell-runner">
<f n="batch_sub" p="test/mcpclidiffcheck.sh:63"/>
<f n="batch_sub" p="test/mcptranchecheck.sh:55"/>
<f n="batch_sub" p="test/mcpw2fixcheck.sh:52"/>
<f n="batch_sub" p="test/mcpw3fixcheck.sh:51"/>
</group>
<group type="2" gid="175" tokens="149" n="3" exempt="shell-runner">
<f n="monotonic_check" p="test/pyimportprecisecheck.sh:89"/>
<f n="monotonic_check" p="test/rustimportprecisecheck.sh:124"/>
<f n="monotonic_check" p="test/tsimportprecisecheck.sh:88"/>
</group>
<group type="2" gid="34" tokens="142" n="2">
<f n="test_tier2_accept_big_quality_small_cost" p="bench/locbench/test_compare_gate.py:130"/>
<f n="test_tier2_reject_small_quality_big_cost" p="bench/locbench/test_compare_gate.py:143"/>
</group>
<group type="2" gid="138" tokens="126" n="2">
<f n="addWholeFileFn" p="test/cloneband_harness.cpp:64"/>
<f n="addWholeFileFn" p="test/type3clone_harness.cpp:47"/>
</group>
<group type="2" gid="59" tokens="118" n="2">
<f n="rankFiles" p="src/eval.h:53"/>
<f n="rankCandidates" p="src/skilleval.h:426"/>
</group>
<group type="2" gid="35" tokens="114" n="2">
<f n="timer" p="bench/representative_perfgate.sh:54"/>
<f n="run_once_ms" p="test/mergescoutcheck.sh:268"/>
</group>
… [308 more display lines; full output is 16989 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --stray-content=zz-orphan`

*CHANGED: a ref with NO merge base with HEAD now reports v="unknown" ok="0" in its own bucket — the absence of an answer, never a claim it is merged. (The sandbox carries a deliberately parentless branch built with `git commit-tree`; a shallow CI clone puts every ref here.)*

`````
<!-- ripwire stray-content: per ref, the lines its own divergent work AUTHORED (vs its merge-base with HEAD) that the live line does NOT have. v="superseded" means the live line removed the same base code this ref removed (redone/del) — it re-implemented the work, the case `git cherry` cannot see; v="unmerged" means the work is genuinely absent; merged refs are omitted. Read-only: git cat-file/diff/ls-tree only, one batched cat-file for the whole sweep, every blob reduced once per sha. Line-granular, not semantic: see the ripwire help text for the limits. ANCHORING is a deliberate hybrid: the SCOPE is base anchored (only lines the ref itself authored vs its merge base are ever considered, so a file the ref never opened cannot appear because the live line moved), while the ABSENCE test is HEAD anchored on purpose (does the live line have this content TODAY is the question being asked, and it is only answerable against live HEAD). v="unknown" with ok="0" means this ref could NOT be analysed at all because it has no merge base with HEAD, which on a SHALLOW clone (the checkout default in CI) is every ref: it is not a claim that the ref is merged, and the fix is to deepen the clone. The four buckets are exhaustive, so unmerged plus superseded plus merged plus unknown always equals refs. SCOPE: refs/heads only, which is every local branch (worktree branches included). Remote tracking refs are NOT scanned: they mirror local ones in the usual checkout and would double every row. The consequence on a FRESH CLONE, where the branches live under refs/remotes/origin and only the checked out one has a local head, is that there is nothing here to be stray FROM; refs= is that fact as a number. TRUNCATION: a ref row ends with a more element (more files=N) when its own file listing was capped; shown plus that number equals the ref's files= total, always. That inner listing is a SECONDARY listing (it repeats complete and identical on every page) and is capped by detail, not by limit / offset, which page the OUTER ref listing and report their own shown= / capped=. -->
<stray-content head="700e51d49" head_ref="integration/harvestexec-2026-08-20" refs="1" blobs="0" unmerged="0" superseded="0" merged="0" unknown="1">
<ref name="zz-orphan-lane" tip="ccd42d9f9" date="2026-08-20" base="" ok="0" v="unknown" stray="0" files="0" superseded="0">
</ref>
</stray-content>
`````

stderr:

`````
[math degraded] crossref: no merge-base for ref (shallow clone or unrelated history?) — verdict is unknown, not merged  (crossref.h:1034, RefPlumbing rw::crossref::probeRefBase(const std::string &, const RefInfo &, const std::string &) — logged once per site)
`````

## `./build/ripwire . --stray-content=zz-orphan --plan`

*CHANGED: --plan surfaces those same refs as an <undetermined> row rather than silently dropping them.*

`````
<!-- ripwire landing-plan: stray-content's cheap per-blob sweep composed with merge-scout's per-arm overlap oracle — of every local branch, which still hold REAL work (v="unmerged"), which were already re-implemented on the live line (v="superseded", EXCLUDED below — landing them re-does work that is already done) or are already merged (omitted entirely, counted in merged= on the root element), and the fewest-conflicts-first order to land what remains. scouted="0" on an unmerged ref means it was NOT fed to merge-scout this run (the cost bound, not a verdict) — it is still real, unscouted work; bounded= on the root element counts them and detail lifts the bound. merge-scout is the EXPENSIVE step here (git-archive + full ingest per arm) — stray-content's own sweep is the cheap one. An undetermined row is a ref that could NOT be analysed at all (no merge base with HEAD, which on a SHALLOW clone is every ref): it is neither scouted nor excluded nor merged, because nothing was measured — treat it as unfinished business and deepen the clone, never as a clean branch. Read-only throughout: no checkout, no ref write, no working-tree mutation. The root carries BOTH head= and at= and they are the same commit: head= is the bare 9 hex chars this verb has always printed, at= is the tool wide anchor and is head= plus a "+dirty" suffix when the working tree is not clean. Prefer at= (it is the one spelling every other repo reading verb uses, and the only one that tells you whether uncommitted work was in scope); head= is kept for callers already keyed to it. -->
<landing-plan head="700e51d49" refs="1" unmerged="0" superseded="0" merged="0" undetermined="1" scouted="0" bounded="0" scout-ok="1" at="700e51d49+dirty">
<undetermined name="zz-orphan-lane" v="unknown" reason="no merge base with HEAD (shallow clone or unrelated history) — this ref could not be analysed, it is NOT known to be merged; deepen the clone and re-run"/>
</landing-plan>
`````

stderr:

`````
[math degraded] crossref: no merge-base for ref (shallow clone or unrelated history?) — verdict is unknown, not merged  (crossref.h:1034, RefPlumbing rw::crossref::probeRefBase(const std::string &, const RefInfo &, const std::string &) — logged once per site)
`````
