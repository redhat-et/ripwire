# ripwire — every verb, run for real

- **Date:** 2026-09-05 (regenerated capture; supersedes any older `docs/captures/COMMANDS_showcase_*.md`)
- **Lives in `docs/captures/`** — a directory the crawl/retrieval lenses SKIP (`kCrawlSkipDirs`, src/ingest.h): a generated doc that quotes every verb's output out-scores the source for any query about the tool and was measured at 77% of `--recall` on this repo when it sat at the root. `test/argvdiffcheck.sh` harvests its `## `-heading command lines as differential vectors — keep that format.
- **Version:** `ripwire 0.3.8 (dev, AppleClang 21.0.0.21000101, built_from=c7725f3ef)`
- **Repo:** the ripwire repo @ `c7725f3e` — **CLEAN — `git status --porcelain` is empty**. The diff-aware verbs (`--situ`/`--test-gate`/`--quality-delta`/`--pr-context`/`--map-diff`/`--edit-check`) answer a question about the WORKING TREE, so that condition is part of their answer and every one of their captions below states which tree it recorded against. A clean tree is the honest default for a showcase, so they appear TWICE: once here on the clean tree (their empty/exit-0 shape) and once in the final section against a throwaway `git clone --local` sandbox carrying one deliberate regression, so their real gating shapes are visible without writing a byte into the read-only repo.
- **Corpus:** the ripwire repo itself (dogfood), via `./build/ripwire`
- **Sandbox diff** (the last section only): `.ripwire_notes        |  2 ++
 .ripwire_quality_acks |  3 +++
 src/infra/sortutil.h  | 31 ++++++++++++++++++++++++++++---
 3 files changed, 33 insertions(+), 3 deletions(-)` — one preexisting function made deeply nested, one function's arity changed 1 -> 2, one copy-paste duplicate helper, one new 8-parameter public function.

**How to read the blocks:** ripwire's real XML output is minified — often ONE long line. For scanability, long minified lines are displayed re-wrapped with a line break at every tag seam (`><`). Header COMMENT lines (the legends) always appear in full — they are exempt from the per-line cut; any OTHER display line over 300 bytes is cut with a `… [line truncated: N more bytes]` marker, which can hit a long root element or row. `--plan-lanes` emits JSON and is re-wrapped at object seams the same way. Long outputs are cut to their first ~30 display lines with a `… [N more display lines; full output is M bytes]` marker giving the true size. Exit codes are recorded when non-zero; wall time when >1s.

**Not run (and why):** `ripwire <git-url>` (network clone), `--listen` / `--mcp-token` / `--allow-remote-edits` (the HTTP-server posture; `--mcp` itself IS captured in its own section as a one-shot stdio JSON-RPC exchange, and `wrap claude` shows the wiring), `--arch --baseline[-update]` (state writer against the read-only repo — `--note-add` / `--quality-baseline` / `--quality-ack` / the three edit verbs / `--edit-plan` ARE shown, inside the throwaway sandbox clone; `--index-out` / `--pin-census` write to scratch), `--eval-mined` (needs a `minedpair.jsonl` artifact from `bench/mine_traces.py`; none present in the tree), `--refetch` (git-url only), `--force` (wrap-only modifier), `--scan-skills` bare form (would sweep `~/.claude/skills`; the explicit-DIR form is shown instead), `--help` (1514 lines — read it from the binary).


---

# understand a codebase cold

## `./build/ripwire .`

*The default ranked symbol map — start here when landing cold in a repo.*

`````
<!-- ripwire v1 t=fn|method|cls|struct|iface|var|sec|macro(#define;degraded:body-is-replacement-text,edges-cross-expansion) p=path layer=arch-layer(opt) n=name id=canonical(path::scope::name,when-scoped) k=rank c=call amb=ambiguous-calls(read-source) lpin=calls-pinned-by-locality-prior-alone(a-disclosed-guess;read-source;absent-if-0) overloads=N-same-name-defs-merged-into-this-row(absent-if-1;shown=counts-them-individually,so-rows+sum(overloads-1)=shown) prov=scip(precise;else name-based) hdr:unresolved=call-name-defined-only-in-a-lang-incompatible-file (edges heuristic) hdr:locality_pinned=sum-of-lpin(absent-if-0) hdr:external=calls-refused-as-bound-outside-the-tree(builtin/stdlib-name-without-in-repo-evidence,external-import,super-past-the-tree;no-edge;absent-if-0) r:est_tokens=hdr-copy(none-if-stable) -->
<!-- r:root=crawl-root-every-p=-is-relative-to(single-root-only;absent=>p=is-the-raw-ingest-path) -->
<!-- pr_iters=pagerank-power-iterations(stop:L1-residual-below-tol,else-ceiling) pr_converged=0-only-when-ceiling-hit-first(absent=converged;no-such-attr=not-pagerank-ordered) -->
<!-- files=1588 symbols=13849 edges=17058 shown=200 est_tokens=9090 ambiguous=6085 unresolved=3093 locality_pinned=6 external=788 precise=3 skipped_oversize=15 unindexed="txt:59,jsonl:26,tsv:21,scm:18,expected:15,lock:7" unindexed_exts=19 order=important-first -->
<r root="." est_tokens="9090" pr_iters="31">
<f p="src/infra/svector.h" layer="infra">
<s t="method" n="size" id="src/infra/svector.h::svector::size" k="0.0169">
</s>
<s t="method" n="buf" id="src/infra/svector.h::svector::buf" overloads="2" k="0.0071">
</s>
<s t="method" n="push_back" id="src/infra/svector.h::svector::push_back" overloads="2" amb="2" k="0.0054">
<c n="buf"/>
<c n="buf"/>
<c n="grow"/>
</s>
<s t="method" n="grow" id="src/infra/svector.h::svector::grow" amb="1" k="0.0041">
<c n="isSpilled"/>
<c n="buf"/>
<c n="buf"/>
<c n="moveRange"/>
<c n="maxSize"/>
</s>
<s t="method" n="empty" id="src/infra/svector.h::svector::empty" k="0.0030">
</s>
<s t="method" n="end" id="src/infra/svector.h::svector::end" overloads="2" amb="1" k="0.0023">
<c n="buf"/>
<c n="buf"/>
</s>
<s t="method" n="reserve" id="src/infra/svector.h::svector::reserve" k="0.0022">
<c n="grow"/>
… [769 more display lines; full output is 22514 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --top-k=5`

*Same map, capped to the 5 highest-ranked symbols.*

`````
<!-- ripwire v1 t=fn|method|cls|struct|iface|var|sec|macro(#define;degraded:body-is-replacement-text,edges-cross-expansion) p=path layer=arch-layer(opt) n=name id=canonical(path::scope::name,when-scoped) k=rank c=call amb=ambiguous-calls(read-source) lpin=calls-pinned-by-locality-prior-alone(a-disclosed-guess;read-source;absent-if-0) overloads=N-same-name-defs-merged-into-this-row(absent-if-1;shown=counts-them-individually,so-rows+sum(overloads-1)=shown) prov=scip(precise;else name-based) hdr:unresolved=call-name-defined-only-in-a-lang-incompatible-file (edges heuristic) hdr:locality_pinned=sum-of-lpin(absent-if-0) hdr:external=calls-refused-as-bound-outside-the-tree(builtin/stdlib-name-without-in-repo-evidence,external-import,super-past-the-tree;no-edge;absent-if-0) r:est_tokens=hdr-copy(none-if-stable) -->
<!-- r:root=crawl-root-every-p=-is-relative-to(single-root-only;absent=>p=is-the-raw-ingest-path) -->
<!-- pr_iters=pagerank-power-iterations(stop:L1-residual-below-tol,else-ceiling) pr_converged=0-only-when-ceiling-hit-first(absent=converged;no-such-attr=not-pagerank-ordered) -->
<!-- files=1588 symbols=13849 edges=17058 shown=5 est_tokens=736 ambiguous=6085 unresolved=3093 locality_pinned=6 external=788 precise=3 skipped_oversize=15 unindexed="txt:59,jsonl:26,tsv:21,scm:18,expected:15,lock:7" unindexed_exts=19 order=important-first -->
<r root="." est_tokens="736" pr_iters="31">
<f p="src/infra/svector.h" layer="infra">
<s t="method" n="size" id="src/infra/svector.h::svector::size" k="0.0169">
</s>
<s t="method" n="buf" id="src/infra/svector.h::svector::buf" overloads="2" k="0.0071">
</s>
</f>
<f p="src/notes.h">
<s t="method" n="empty" id="src/notes.h::NoteIndex::empty" k="0.0099">
</s>
</f>
<f p="src/scipoverlay.h">
<s t="method" n="empty" id="src/scipoverlay.h::ScipOverlay::empty" k="0.0097">
</s>
</f>
</r>
`````

## `./build/ripwire . --top-k=0 --expand=rankGraphTeleport`

*NEW since the last capture: --top-k=0 means PAYLOAD-ONLY — no ranked map rides along with the body you asked for.*

`````
<ctx root="." est_tokens="949">
<!-- a body's sibs="a,b,..." sibs_total=N are the file's OTHER indexed symbols (this body's own name excluded), source order, capped at 8 (sibs_capped="1" when the cap fired); inc="x.h,..." inc_total=N are the file's own #include/import targets, source order, capped at 24 (inc_capped="1" when the cap fired) — both absent when the count is 0 (a documented zero, not a degrade). Each body's own calls child (1-hop callee signatures) carries total=/shown=/capped="1" the usual way: capped="1" only when shown is below total. A body's CDATA is the bytes on disk unless the element says otherwise: scrubbed="1" = a ]]> was split (]]]]>
<![CDATA[>, rejoin it) or a C0/invalid-UTF-8 byte was replaced; redacted="1" = a credential shape was rewritten to a [REDACTED:kind] marker (the no-redact flag serves the bytes; the edit verbs refuse a payload carrying MORE such markers than the bytes it would replace already do, so source that spel … [line truncated: 59 more bytes on this line]
<bodies shown="1" total="1" capped="0">
<b t="fn" l="2501" p="src/graph.h" n="rankGraphTeleport" sibs="Graph,langCompatible,namespaceCompatible,kCommonNameMul,kCommonNameDefThreshold,kPrivateNameMul,kSpecificNameMul,kSpecificMinLen" sibs_total="148" sibs_capped="1" inc="model.h,filter.h,pageview.h,graphlegend.h,lintrules.h,infra/sparseCsr … [line truncated: 228 more bytes on this line]
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
}]]><calls total="9"><c n="biasPrior" l="2464">inline std::vector&lt;float&gt; biasPrior( const Graph&amp; g, const std::vector&lt;float&gt;&amp; p )</c><c n="PROFILE_SCOPE_DESCRIBE" l="1322">#define PROFILE_SCOPE_DESCRIBE( desc )</c><c n="PROFILE_SCOPE_DESCRIBE" l="1336">#define PROFILE_SCOPE_DESCR … [line truncated: 535 more bytes on this line]
`````

## `./build/ripwire . --top-k=0`

*--top-k=0 with NO payload verb asked for — REFUSES (exit 1) naming the payload verbs, never an empty map.*

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
<!-- ripwire v1 t=fn|method|cls|struct|iface|var|sec|macro(#define;degraded:body-is-replacement-text,edges-cross-expansion) p=path layer=arch-layer(opt) n=name id=canonical(path::scope::name,when-scoped) k=rank c=call amb=ambiguous-calls(read-source) lpin=calls-pinned-by-locality-prior-alone(a-disclosed-guess;read-source;absent-if-0) overloads=N-same-name-defs-merged-into-this-row(absent-if-1;shown=counts-them-individually,so-rows+sum(overloads-1)=shown) prov=scip(precise;else name-based) hdr:unresolved=call-name-defined-only-in-a-lang-incompatible-file (edges heuristic) hdr:locality_pinned=sum-of-lpin(absent-if-0) hdr:external=calls-refused-as-bound-outside-the-tree(builtin/stdlib-name-without-in-repo-evidence,external-import,super-past-the-tree;no-edge;absent-if-0) r:est_tokens=hdr-copy(none-if-stable) -->
<!-- r:root=crawl-root-every-p=-is-relative-to(single-root-only;absent=>p=is-the-raw-ingest-path) -->
<!-- max_tokens=asked fit_bytes=honoured: fit_bytes = max_tokens x 2.36 (densest-language B/tok) x 0.90 headroom, a CONSERVATIVE cap, so est_tokens (this corpus's own rate) lands ~10-20% BELOW max_tokens by design; the token-budget gate compares against est_tokens, not fit_bytes; over_ceiling=floor-alone-exceeded-fit_bytes(absent=cap-held) -->
<!-- pr_iters=pagerank-power-iterations(stop:L1-residual-below-tol,else-ceiling) pr_converged=0-only-when-ceiling-hit-first(absent=converged;no-such-attr=not-pagerank-ordered) -->
<!-- files=1588 symbols=13849 edges=17058 shown=13 est_tokens=1239 ambiguous=6085 unresolved=3093 locality_pinned=6 external=788 precise=3 skipped_oversize=15 unindexed="txt:59,jsonl:26,tsv:21,scm:18,expected:15,lock:7" unindexed_exts=19 max_tokens=1500 fit_bytes=3186 order=important-first -->
<r root="." est_tokens="1239" pr_iters="31">
<f p="src/infra/svector.h" layer="infra">
<s t="method" n="size" id="src/infra/svector.h::svector::size" k="0.0169">
</s>
<s t="method" n="buf" id="src/infra/svector.h::svector::buf" overloads="2" k="0.0071">
</s>
<s t="method" n="push_back" id="src/infra/svector.h::svector::push_back" overloads="2" amb="2" k="0.0054">
<c n="buf"/>
<c n="buf"/>
<c n="grow"/>
</s>
<s t="method" n="grow" id="src/infra/svector.h::svector::grow" amb="1" k="0.0041">
<c n="isSpilled"/>
<c n="buf"/>
<c n="buf"/>
<c n="moveRange"/>
<c n="maxSize"/>
</s>
<s t="method" n="empty" id="src/infra/svector.h::svector::empty" k="0.0030">
</s>
</f>
<f p="src/notes.h">
<s t="method" n="empty" id="src/notes.h::NoteIndex::empty" k="0.0099">
</s>
<s t="method" n="find" id="src/notes.h::NoteIndex::find" amb="1" k="0.0027">
… [25 more display lines; full output is 3078 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --token-budget=100`

*GATE form: exit 3 if the map's own est_tokens exceeds the budget (over-budget failure shape).*

**exit code: 3**

`````
<r withheld_est_tokens="9090" budget="100" withheld="1"/>
`````

stderr:

`````
ripwire: --token-budget exceeded: withheld_est_tokens=9090 > budget=100
`````

## `./build/ripwire . --for="incremental cache invalidation when a file content hash changes"`

*The task lens: ranked signatures + quality metrics framed for the task.*

`````
<ctx task="incremental cache invalidation when a file content hash changes" route="routed: subtoken+body BM25 (--for&apos;s default) — no strong name hit, multi-word conceptual query" root="." confidence="low" margin_pct="0" at="c7725f3ef" doc_mentions="1" bundle="compact" bodies="0" reason="compa … [line truncated: 28 more bytes on this line]
<!-- ripwire lens for "incremental cache invalidation when a file content hash changes" [doc mentions: 1 doc discussing 1 top-ranked symbol surfaced; doc_mentions= on the root repeats the doc count] [confidence= derives from the ranked head's largest relative score drop (margin_pct=, whole percent, 0 = none; the same gap the adaptive flag cuts at). low = flat ranking: treat the set as a starting point, not an answer]: reusable building blocks + quality facts for what you're about to touch (cx=complexity ccx=cognitive in=reuse-count churn=recent-commits amp=change-amplification clone=1(duplicated) tested=1) — prefer composing/reusing these; watch the high-churn/high-amp/cloned ones; bundle=compact: conceptual query, so this map ships one-hop EDGE context, no bodies (bodies=0, reason=compact-route or no_candidates). hops rows are h l=line p=file n=name, and a row's calls child names its callees (c n= l=). hops and calls disclose total=requested shown=printed capped=1 when the BUDGET cut a listing; noedge=N counts ranked symbols with no RESOLVED callee found (never none exists). For a body: expand=p:n pasted off a row; the auto-bodies flag puts the bodies back; tail: file-grain tail, WEAKER evidence than the ranked rows (paths only): the remaining candidate files with a positive score, best-symbol rank order; rows are t p=file; total=candidate files, shown=printed, capped=1 when they differ. r= on a ranked row is its 1-based rank in this lens ranking, rows in r= order, p= the file (a gap = a budget-trimmed row) -->
<!-- root= is the crawl root; p= below is RELATIVE to it (single-root only; absent => p= is ingest's own path, unchanged); at=this commit(+dirty). dropped_positive="23" est_tokens= prices this bundle in tokens -->
<sigs shown="17" total="40" capped="1">
<d l="106" n="kCacheMagic" p="src/ingest_cache.h" cx="0" ccx="0" in="0" churn="11" amp="71" pure="1" r="1" next="--expand=src/ingest_cache.h:kCacheMagic">
<doc>incremental cache (--cache): per-file content hash + raw facts so a re-run re-parses ONLY      c…</doc>constexpr std::uint32_t kCacheMagic = 0x4b505443</d>
<d l="1354" n="kHeadSnapCacheScheme" id="src/quality.h::quality::kHeadSnapCacheScheme" p="src/quality.h" cx="0" ccx="0" in="0" churn="106" amp="244" pure="1" r="2">
<doc>and every file whose content hash differs is re-parsed — so a stale or foreign blob self-heals…</doc>constexpr std::uint32_t kHeadSnapCacheScheme = 1</d>
<d l="516" n="McpIndex" id="src/mcpindex.h::McpIndex::McpIndex" p="src/mcpindex.h" cx="0" ccx="0" in="0" churn="20" amp="41" r="3">
<doc>persistent in-memory index (parse once, reuse across MCP calls) ---- The MCP server is long-live…</doc>struct McpIndex</d>
<d l="1104" n="getIndex" id="src/mcpindex.h::rw::getIndex" p="src/mcpindex.h" cx="22" ccx="39" in="32" churn="20" amp="73" r="4">
<doc>the cached index for `root`, rebuilt only when stale (otherwise returned as-is, no parse, no gra…</doc>inline const McpIndex&amp; getIndex( const std::string&amp; root )</d>
<d l="770" n="mcpRebuildBaseline" id="src/mcpindex.h::rw::mcpRebuildBaseline" p="src/mcpindex.h" cx="2" ccx="1" in="1" churn="20" amp="42" r="5">inline McpRebuildBaseline mcpRebuildBaseline( const McpIndex&amp; ix, bool isIncrementalPass )</d>
<d l="751" n="contentHash64" p="src/ingest_cache.h" cx="2" ccx="1" in="4" churn="11" amp="75" tested="1" r="6">inline std::uint64_t contentHash64( std::string_view s ) noexcept</d>
<d l="852" n="CacheEntry" id="src/ingest_cache.h::CacheEntry::CacheEntry" p="src/ingest_cache.h" cx="0" ccx="0" in="0" churn="11" amp="71" r="7">struct CacheEntry</d>
<d l="77" n="prewarmTagsQueries" p="src/ingest_prewarm.h" cx="53" ccx="160" in="1" churn="2" amp="10" tested="1" r="8">inline void prewarmTagsQueries( const std::vector&lt;std::string&gt;&amp; files, const HashMap&lt;std::string, FileFacts&gt;&amp; cache, long long cacheWriteNs, IngestFileScan&amp;  … [line truncated: 10 more bytes on this line]
<d l="931" n="contentIdsBySym" id="src/quality.h::quality::contentIdsBySym" p="src/quality.h" cx="3" ccx="3" in="1" churn="106" amp="245" r="9">inline ContentIdIndex contentIdsBySym( const IngestResult&amp; ing, const Graph&amp; g, std::string_view root )</d>
<d l="766" n="blobChecksum" p="src/ingest_cache.h" cx="5" ccx="5" in="3" churn="11" amp="74" tested="1" r="10">inline std::uint64_t blobChecksum( std::string_view s ) noexcept</d>
<d l="1748" n="buildCacheWritePlan" p="src/ingest_cache.h" cx="11" ccx="14" in="1" churn="11" amp="72" tested="1" r="11">inline std::vector&lt;CacheWriteRow&gt; buildCacheWritePlan( const std::vector&lt;std::uint32_t&gt;&amp; orderIn, const std::vector&lt;std::uint64_t&gt;&amp; pathHashes, const std … [line truncated: 14 more bytes on this line]
<d l="5537" n="legoImplementorsOnSurface" id="src/serialize.h::rw::legoImplementorsOnSurface" p="src/serialize.h" cx="10" ccx="13" in="2" churn="99" amp="248" r="12">inline std::vector&lt;std::vector&lt;NodeId&gt;&gt; legoImplementorsOnSurface( const IngestResult&amp; ing, const std::vector&lt;std:: … [line truncated: 65 more bytes on this line]
<d l="247" n="ingestCommitTree" id="src/dmm.h::rw::dmm::ingestCommitTree" p="src/dmm.h" cx="6" ccx="5" in="1" churn="6" amp="27" r="13">inline bool ingestCommitTree( const std::string&amp; root, const std::string&amp; sha, const std::vector&lt;std::string&gt;&amp; excludes, std::size_t maxFileBytes, … [line truncated: 28 more bytes on this line]
<d l="1347" n="reAbsolutize" p="src/ingest_cache.h" cx="4" ccx="3" in="1" churn="11" amp="72" tested="1" r="14">inline std::string reAbsolutize( std::string_view rel, std::string_view root )</d>
<d l="573" n="runParsePool" p="src/ingest_parsepool.h" cx="25" ccx="65" in="1" churn="3" amp="12" tested="1" r="15">inline RawFacts runParsePool( IngestResult&amp; result, const char* rootDir, std::string_view cacheFile, bool captureValueUses, HashMap&lt;std::string, FileFacts&gt;&amp; cache, const  … [line truncated: 86 more bytes on this line]
<d l="1717" n="buildCachePathKeys" p="src/ingest_cache.h" cx="3" ccx="3" in="1" churn="11" amp="72" tested="1" r="16">inline CachePathKeys buildCachePathKeys( const std::vector&lt;std::string&gt;&amp; files, std::string_view rootDir )</d>
<d l="485" n="indexContentHash" id="src/mcpindex.h::mcpdetail::indexContentHash" p="src/mcpindex.h" cx="5" ccx="7" in="1" churn="20" amp="42" r="17">inline std::uint64_t indexContentHash( const std::vector&lt;std::string&gt;&amp; files, const std::vector&lt;long long&gt;&amp; fileMtime, const std::v … [line truncated: 50 more bytes on this line]
</sigs>
<compose>
<field name="ing" type="IngestResult" owner="ResolveContext" rel="uses"/>
<field name="ing" type="IngestResult" owner="ExternalVeto" rel="uses"/>
<field name="gate" type="QueryReadyGate" owner="ParsePoolShared" rel="uses"/>
… [67 more display lines; full output is 9686 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --for="rankGraphTeleport"`

*Name-shaped query: the router picks name-exact BM25 (header says which/why).*

`````
<ctx task="rankGraphTeleport" route="routed: name-exact BM25 — query names a symbol (rankGraphTeleport); anchors: rankGraphTeleport(src/graph.h)" root="." confidence="high" margin_pct="45" at="c7725f3ef" doc_mentions="2" bundle="auto" bodies="1" est_tokens="1890">
<!-- ripwire lens for "rankGraphTeleport" [doc mentions: 2 docs discussing 1 top-ranked symbol surfaced; doc_mentions= on the root repeats the doc count] [relevance floor: kept 3 of 40 - the other 37 scored zero on this query, so the bundle shrank instead of padding] [confidence= derives from the ranked head's largest relative score drop (margin_pct=, whole percent, 0 = none; the same gap the adaptive flag cuts at). low = flat ranking: treat the set as a starting point, not an answer]: reusable building blocks + quality facts for what you're about to touch (cx=complexity ccx=cognitive in=reuse-count churn=recent-commits amp=change-amplification clone=1(duplicated) tested=1) — prefer composing/reusing these; watch the high-churn/high-amp/cloned ones; bundle=auto: the top-ranked FULL bodies ride inline after the signatures in a bodies section (bodies=N on this root counts them; bodies=0 reason=budget when none fit the remaining budget whole; the signatures-only flag (no-bodies mode) opts out) — read them here instead of opening the files. The bodies element discloses the house way: total=requested, shown=printed, capped=1 when they differ; each body's calls child lists its callee signatures, total= always, shown=/capped= only when that list is cut; tail: file-grain tail, WEAKER evidence than the ranked rows (paths only): the remaining candidate files with a positive score, best-symbol rank order; rows are t p=file; total=candidate files, shown=printed, capped=1 when they differ. r= on a ranked row is its 1-based rank in this lens ranking, rows in r= order, p= the file (a gap = a budget-trimmed row) -->
<!-- root= is the crawl root; p= below is RELATIVE to it (single-root only; absent => p= is ingest's own path, unchanged); at=this commit(+dirty). est_tokens= prices this bundle in tokens -->
<sigs>
<d l="2501" n="rankGraphTeleport" id="src/graph.h::rw::rankGraphTeleport" p="src/graph.h" cx="5" ccx="8" in="6" churn="59" amp="200" r="1" next="--expand=src/graph.h:rankGraphTeleport">
<doc>PageRank with an explicit teleport / personalization vector p (Σp = 1). The prior is name-quality-biased through biasPrior() so all rank modes share one weighting seam; the transition matrix (edges</doc>inline RankedGraph rankGraphTeleport( const Graph&amp; g, const std::vector&lt;float&gt;&am … [line truncated: 31 more bytes on this line]
<d l="248" n="The convergence disclosure contract" id="docs/ARCHITECTURE.md::rank — Personalized PageRank::The convergence disclosure contract" p="docs/ARCHITECTURE.md" cx="0" ccx="0" in="0" churn="15" amp="87" r="2">#### The convergence disclosure contract</d>
<d l="5542" n="Wave-2 adversarial verification (2026-08-19) — six probes against `aa97c9e`" id="docs/EVALS.md::6. Correctness and quality instruments::Wave-2 adversarial verification (2026-08-19) — six probes against `aa97c9e`" p="docs/EVALS.md" cx="0" ccx="0" in="0" churn="492" amp="683" r="3"> … [line truncated: 85 more bytes on this line]
</sigs>
<tail total="0" shown="0" capped="0">
</tail>
<bodies shown="1" total="1" capped="0">
<b t="fn" l="2501" p="src/graph.h" n="rankGraphTeleport">
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
… [12 more display lines; full output is 5459 bytes on 29 raw line(s)]
`````

## `./build/ripwire . --for="rankGraphTeleport" --no-route`

*Same query with routing forced OFF (plain subtoken+body BM25) — contrast with the routed run.*

`````
<ctx task="rankGraphTeleport" root="." confidence="low" margin_pct="0" at="c7725f3ef" doc_mentions="6" bundle="auto" bodies="5" est_tokens="5417">
<!-- ripwire lens for "rankGraphTeleport" [doc mentions: 6 docs discussing 4 top-ranked symbols surfaced; doc_mentions= on the root repeats the doc count] [confidence= derives from the ranked head's largest relative score drop (margin_pct=, whole percent, 0 = none; the same gap the adaptive flag cuts at). low = flat ranking: treat the set as a starting point, not an answer]: reusable building blocks + quality facts for what you're about to touch (cx=complexity ccx=cognitive in=reuse-count churn=recent-commits amp=change-amplification clone=1(duplicated) tested=1) — prefer composing/reusing these; watch the high-churn/high-amp/cloned ones; bundle=auto: the top-ranked FULL bodies ride inline after the signatures in a bodies section (bodies=N on this root counts them; bodies=0 reason=budget when none fit the remaining budget whole; the signatures-only flag (no-bodies mode) opts out) — read them here instead of opening the files. The bodies element discloses the house way: total=requested, shown=printed, capped=1 when they differ; each body's calls child lists its callee signatures, total= always, shown=/capped= only when that list is cut; tail: file-grain tail, WEAKER evidence than the ranked rows (paths only): the remaining candidate files with a positive score, best-symbol rank order; rows are t p=file; total=candidate files, shown=printed, capped=1 when they differ. r= on a ranked row is its 1-based rank in this lens ranking, rows in r= order, p= the file (a gap = a budget-trimmed row) -->
<!-- root= is the crawl root; p= below is RELATIVE to it (single-root only; absent => p= is ingest's own path, unchanged); at=this commit(+dirty). dropped_positive="20" est_tokens= prices this bundle in tokens -->
<sigs shown="20" total="40" capped="1">
<d l="2542" n="rankGraph" id="src/graph.h::rw::rankGraph" p="src/graph.h" cx="2" ccx="1" in="9" churn="59" amp="203" r="1" next="--expand=src/graph.h:rankGraph">
<doc>uniform-teleport PageRank (the default</doc>inline RankedGraph rankGraph( const Graph&amp; g, float alpha = 0.85f )</d>
<d l="2501" n="rankGraphTeleport" id="src/graph.h::rw::rankGraphTeleport" p="src/graph.h" cx="5" ccx="8" in="6" churn="59" amp="200" r="2">
<doc>PageRank with an explicit teleport / personalization vector p (Σp = 1). The prior is name-quali…</doc>inline RankedGraph rankGraphTeleport( const Graph&amp; g, const std::vector&lt;float&gt;&amp; p, float alpha = 0.85f )</d>
<d l="983" n="churnRankedGraph" p="src/main.cpp" cx="13" ccx="18" in="1" churn="271" amp="420" r="3">inline ChurnRanking churnRankedGraph( const MainDispatch&amp; d )</d>
<d l="1550" n="kChurnRankLegend" id="src/serialize.h::rw::kChurnRankLegend" p="src/serialize.h" cx="0" ccx="0" in="0" churn="99" amp="246" pure="1" r="4">
<doc>L10 (2026-09-04): the old wording claimed &quot;the same corpus ranked by pagerank orders differently…</doc>inline constexpr const char* kChurnRankLegend = &quot;&lt;!-- rank_by=churn: k= is PageRank re-run with the teleport BIASED by git CHANGE-FREQUENCY over window= &quot; &quot;(a c…</d>
<d l="2492" n="RankedGraph" id="src/graph.h::RankedGraph::RankedGraph" p="src/graph.h" cx="0" ccx="0" in="0" churn="59" amp="194" r="5">struct RankedGraph</d>
<d l="3034" n="anchoredLexicalRank" id="src/graph.h::rw::anchoredLexicalRank" p="src/graph.h" cx="10" ccx="10" in="4" churn="59" amp="198" r="6">inline std::vector&lt;float&gt; anchoredLexicalRank( const Graph&amp; g, const std::vector&lt;float&gt;&amp; lex )</d>
<d l="2535" n="takeRank" id="src/graph.h::rw::takeRank" p="src/graph.h" cx="1" ccx="0" in="1" churn="59" amp="195" r="7">inline std::vector&lt;float&gt; takeRank( RankedGraph ranked, RankDisclosure&amp; disclosureOut )</d>
<d l="2464" n="biasPrior" id="src/graph.h::rw::biasPrior" p="src/graph.h" cx="5" ccx="4" in="1" churn="59" amp="195" r="8">inline std::vector&lt;float&gt; biasPrior( const Graph&amp; g, const std::vector&lt;float&gt;&amp; p )</d>
<d l="1561" n="churnTeleportWorkspace" id="src/gitmine.h::rw::churnTeleportWorkspace" p="src/gitmine.h" cx="6" ccx="9" in="1" churn="17" amp="50" r="9">inline std::vector&lt;float&gt; churnTeleportWorkspace( const std::vector&lt;std::string&gt;&amp; rootDirs, const IngestResult&amp; ing, const char* … [line truncated: 49 more bytes on this line]
<d l="39" n="pageRankDouble" id="src/pagerank.h::rw::pageRankDouble" p="src/pagerank.h" cx="1" ccx="0" in="0" churn="6" amp="20" r="10">PageRankRun pageRankDouble( const sparseCsr&lt;float&gt;&amp; inEdges, std::span&lt;const double&gt; weightedOutDegree, std::span&lt;const double&gt; teleport, std: … [line truncated: 31 more bytes on this line]
<d l="240" n="didYouMean" id="src/didyoumean.h::rw::didYouMean" p="src/didyoumean.h" cx="2" ccx="1" in="6" churn="8" amp="36" r="11">inline std::string didYouMean( const IngestResult&amp; ing, std::string_view name )</d>
<d l="1735" n="churnDecayTeleport" id="src/gitmine.h::rw::churnDecayTeleport" p="src/gitmine.h" cx="4" ccx="3" in="1" churn="17" amp="50" r="12">inline std::vector&lt;float&gt; churnDecayTeleport( const std::string&amp; root, const IngestResult&amp; ing, const SinceScope* scope = nullptr, bool* outH … [line truncated: 26 more bytes on this line]
<d l="1104" n="getIndex" id="src/mcpindex.h::rw::getIndex" p="src/mcpindex.h" cx="22" ccx="39" in="32" churn="20" amp="73" r="13">inline const McpIndex&amp; getIndex( const std::string&amp; root )</d>
<d l="95" n="pageRankDouble" id="src/pagerank.cpp::rw::pageRankDouble" p="src/pagerank.cpp" cx="19" ccx="34" in="2" churn="7" amp="22" tested="1" r="14">PageRankRun pageRankDouble( const sparseCsr&lt;float&gt;&amp; inEdges, std::span&lt;const double&gt; weightedOutDegree, std::span&lt;const double&g … [line truncated: 70 more bytes on this line]
<d l="39" n="Graph" id="src/graph.h::Graph::Graph" p="src/graph.h" cx="0" ccx="0" in="0" churn="59" amp="194" r="15">struct Graph</d>
<d l="1752" n="churnDecayTeleportWorkspace" id="src/gitmine.h::rw::churnDecayTeleportWorkspace" p="src/gitmine.h" cx="5" ccx="6" in="1" churn="17" amp="50" r="16">inline std::vector&lt;float&gt; churnDecayTeleportWorkspace( const std::vector&lt;std::string&gt;&amp; rootDirs, const IngestResult&amp;  … [line truncated: 46 more bytes on this line]
<d l="168" n="runEval" id="src/eval.h::rw::runEval" p="src/eval.h" cx="44" ccx="66" in="1" churn="9" amp="24" r="17">inline int runEval( const std::string&amp; root, const IngestResult&amp; ing, const Graph&amp; g, const std::vector&lt;char&gt;&amp; currentDiff )</d>
<d l="248" n="The convergence disclosure contract" id="docs/ARCHITECTURE.md::rank — Personalized PageRank::The convergence disclosure contract" p="docs/ARCHITECTURE.md" cx="0" ccx="0" in="0" churn="15" amp="87" r="18">#### The convergence disclosure contract</d>
<d l="5542" n="Wave-2 adversarial verification (2026-08-19) — six probes against `aa97c9e`" id="docs/EVALS.md::6. Correctness and quality instruments::Wave-2 adversarial verification (2026-08-19) — six probes against `aa97c9e`" p="docs/EVALS.md" cx="0" ccx="0" in="0" churn="492" amp="683" r="19" … [line truncated: 86 more bytes on this line]
<d l="968" n="ChurnRanking" id="src/main.cpp::ChurnRanking::ChurnRanking" p="src/main.cpp" cx="0" ccx="0" in="0" churn="271" amp="419" r="20">struct ChurnRanking</d>
</sigs>
<compose>
<field name="graph" type="Graph" owner="FieldUsesArgs" rel="uses"/>
… [134 more display lines; full output is 15758 bytes on 88 raw line(s)]
`````

## `./build/ripwire . --for="rankGraphTeleport" --signatures-only`

*T3 opt-out: the signatures-only lens (no auto bodies, no bundle="auto" attribute) — contrast with the terminal default above.*

`````
<ctx task="rankGraphTeleport" route="routed: name-exact BM25 — query names a symbol (rankGraphTeleport); anchors: rankGraphTeleport(src/graph.h)" root="." confidence="high" margin_pct="45" at="c7725f3ef" doc_mentions="2" est_tokens="1112">
<!-- ripwire lens for "rankGraphTeleport" [doc mentions: 2 docs discussing 1 top-ranked symbol surfaced; doc_mentions= on the root repeats the doc count] [relevance floor: kept 3 of 40 - the other 37 scored zero on this query, so the bundle shrank instead of padding] [confidence= derives from the ranked head's largest relative score drop (margin_pct=, whole percent, 0 = none; the same gap the adaptive flag cuts at). low = flat ranking: treat the set as a starting point, not an answer]: reusable building blocks + quality facts for what you're about to touch (cx=complexity ccx=cognitive in=reuse-count churn=recent-commits amp=change-amplification clone=1(duplicated) tested=1) — prefer composing/reusing these; watch the high-churn/high-amp/cloned ones; tail: file-grain tail, WEAKER evidence than the ranked rows (paths only): the remaining candidate files with a positive score, best-symbol rank order; rows are t p=file; total=candidate files, shown=printed, capped=1 when they differ. r= on a ranked row is its 1-based rank in this lens ranking, rows in r= order, p= the file (a gap = a budget-trimmed row) -->
<!-- root= is the crawl root; p= below is RELATIVE to it (single-root only; absent => p= is ingest's own path, unchanged); at=this commit(+dirty). est_tokens= prices this bundle in tokens -->
<sigs>
<d l="2501" n="rankGraphTeleport" id="src/graph.h::rw::rankGraphTeleport" p="src/graph.h" cx="5" ccx="8" in="6" churn="59" amp="200" r="1" next="--expand=src/graph.h:rankGraphTeleport">
<doc>PageRank with an explicit teleport / personalization vector p (Σp = 1). The prior is name-quality-biased through biasPrior() so all rank modes share one weighting seam; the transition matrix (edges</doc>inline RankedGraph rankGraphTeleport( const Graph&amp; g, const std::vector&lt;float&gt;&am … [line truncated: 31 more bytes on this line]
<d l="248" n="The convergence disclosure contract" id="docs/ARCHITECTURE.md::rank — Personalized PageRank::The convergence disclosure contract" p="docs/ARCHITECTURE.md" cx="0" ccx="0" in="0" churn="15" amp="87" r="2">#### The convergence disclosure contract</d>
<d l="5542" n="Wave-2 adversarial verification (2026-08-19) — six probes against `aa97c9e`" id="docs/EVALS.md::6. Correctness and quality instruments::Wave-2 adversarial verification (2026-08-19) — six probes against `aa97c9e`" p="docs/EVALS.md" cx="0" ccx="0" in="0" churn="492" amp="683" r="3"> … [line truncated: 85 more bytes on this line]
</sigs>
<tail total="0" shown="0" capped="0">
</tail>
</ctx>
`````

## `./build/ripwire . --for="tree-sitter parse of a source file" --adaptive`

*Cut the result at the relevance cliff (Adaptive-k) — on a flat ranking nothing is cut and the header says so ([adaptive: kept N of N]).*

`````
<ctx task="tree-sitter parse of a source file" route="routed: subtoken+body BM25 (--for&apos;s default) — no strong name hit, multi-word conceptual query" root="." confidence="low" margin_pct="0" at="c7725f3ef" bundle="compact" bodies="0" reason="compact-route" est_tokens="3991">
<!-- ripwire lens for "tree-sitter parse of a source file" [adaptive: kept 40 of 40 - no relevance cliff (broad query saturates the score); capped at the ceiling] [confidence= derives from the ranked head's largest relative score drop (margin_pct=, whole percent, 0 = none; the same gap the adaptive flag cuts at). low = flat ranking: treat the set as a starting point, not an answer]: reusable building blocks + quality facts for what you're about to touch (cx=complexity ccx=cognitive in=reuse-count churn=recent-commits amp=change-amplification clone=1(duplicated) tested=1) — prefer composing/reusing these; watch the high-churn/high-amp/cloned ones; bundle=compact: conceptual query, so this map ships one-hop EDGE context, no bodies (bodies=0, reason=compact-route or no_candidates). hops rows are h l=line p=file n=name, and a row's calls child names its callees (c n= l=). hops and calls disclose total=requested shown=printed capped=1 when the BUDGET cut a listing; noedge=N counts ranked symbols with no RESOLVED callee found (never none exists). For a body: expand=p:n pasted off a row; the auto-bodies flag puts the bodies back; tail: file-grain tail, WEAKER evidence than the ranked rows (paths only): the remaining candidate files with a positive score, best-symbol rank order; rows are t p=file; total=candidate files, shown=printed, capped=1 when they differ. r= on a ranked row is its 1-based rank in this lens ranking, rows in r= order, p= the file (a gap = a budget-trimmed row) -->
<!-- root= is the crawl root; p= below is RELATIVE to it (single-root only; absent => p= is ingest's own path, unchanged); at=this commit(+dirty). dropped_positive="12" est_tokens= prices this bundle in tokens -->
<sigs shown="28" total="40" capped="1">
<d l="40" n="kDefaultMaxFileBytes" id="src/ingest.h::rw::kDefaultMaxFileBytes" p="src/ingest.h" cx="0" ccx="0" in="0" churn="25" amp="74" pure="1" r="1" next="--expand=src/ingest.h:kDefaultMaxFileBytes">
<doc>The crawl&apos;s per-file byte ceiling. A text file larger than this is skipped: at this size it is o…</doc>constexpr std::size_t kDefaultMaxFileBytes = 4u * 1024u * 1024u</d>
<d l="1064" n="parseTree" p="src/ingest_sidecap.h" cx="1" ccx="0" in="1" churn="3" amp="37" tested="1" r="2">TSTree* parseTree( TSParser* parser, std::string_view src )</d>
<d l="185" n="doctorProbeGrammars" p="src/verbs_doctor.h" cx="7" ccx="17" in="1" churn="6" amp="36" r="3">inline DoctorGrammarProbe doctorProbeGrammars()</d>
<d l="789" n="FileHealth" id="src/model.h::FileHealth::FileHealth" p="src/model.h" cx="0" ccx="0" in="0" churn="57" amp="156" r="4">
<doc>errNodes/errBytes are a PARSER-STATE fact, never a syntax verdict: tree-sitter error recovery fi…</doc>struct FileHealth</d>
<d l="314" n="AstWalk" id="src/ingest.h::rw::AstWalk" p="src/ingest.h" cx="0" ccx="0" in="0" churn="25" amp="74" r="5">enum class AstWalk : std::uint8_t</d>
<d l="1778" n="collectGatedLocalNames" id="src/ingest_astquery.h::rw::collectGatedLocalNames" p="src/ingest_astquery.h" cx="7" ccx="6" in="1" churn="5" amp="43" r="6">std::vector&lt;LocalNameFact&gt; collectGatedLocalNames( std::string_view defBytes, std::uint32_t defStartLine, Lang lang )</d>
<d l="230" n="indexCommittish" id="src/mergescout.h::mergescout::indexCommittish" p="src/mergescout.h" cx="5" ccx="4" in="1" churn="14" amp="46" r="7">inline SymTreeIndex indexCommittish( const std::string&amp; root, const std::string&amp; committish, const std::vector&lt;std::string&gt;&amp; exclud … [line truncated: 36 more bytes on this line]
<d l="191" n="hasPhantomScopeSeparator" p="src/ingest_names.h" cx="2" ccx="1" in="1" churn="3" amp="31" tested="1" r="8">inline bool hasPhantomScopeSeparator( TSNode qualified ) noexcept</d>
<d l="681" n="builtInLintCaptures" p="src/verbs_lint.h" cx="1" ccx="0" in="1" churn="8" amp="34" r="9">std::vector&lt;std::vector&lt;rw::AstMatch&gt;&gt; builtInLintCaptures( const rw::IngestResult&amp; ing, const std::vector&lt;rw::AstQuerySpec&gt;&amp; checks, std::vector&lt;std::string&gt;&amp;  … [line truncated: 7 more bytes on this line]
<d l="1976" n="sliceScanDefinition" id="src/slice.h::slicev::sliceScanDefinition" p="src/slice.h" cx="10" ccx="9" in="3" churn="24" amp="36" r="10">inline SliceScan sliceScanDefinition( const std::string&amp; src, const Symbol&amp; sym, SliceFam fam, const ::TSLanguage* grammar, std::string_view var … [line truncated: 10 more bytes on this line]
<d l="1481" n="spanTiersOfFiles" id="src/ingest_astquery.h::rw::spanTiersOfFiles" p="src/ingest_astquery.h" cx="27" ccx="52" in="1" churn="5" amp="43" r="11">SpanTierBatch spanTiersOfFiles( std::span&lt;const std::string&gt; diskPaths, bool useMemo )</d>
<d l="478" n="jsonNestsTooDeep" p="src/ingest_crawl.h" cx="13" ccx="20" in="1" churn="6" amp="44" tested="1" r="12">bool jsonNestsTooDeep( std::string_view bytes ) noexcept</d>
<d l="99" n="kMaxYamlNestDepth" id="src/ingest.h::rw::kMaxYamlNestDepth" p="src/ingest.h" cx="0" ccx="0" in="0" churn="25" amp="74" pure="1" r="13">constexpr std::uint32_t kMaxYamlNestDepth = 64u</d>
<d l="40" n="LintRule" id="src/lintrules.h::LintRule::LintRule" p="src/lintrules.h" cx="0" ccx="0" in="0" churn="12" amp="46" r="14">struct LintRule</d>
<d l="60" n="kLangTable" p="src/ingest_crawl.h" cx="0" ccx="0" in="0" churn="6" amp="43" pure="1" r="15">constexpr std::array&lt;LangEntry, 40&gt; kLangTable =</d>
<d l="280" n="AstQuerySpec" id="src/ingest.h::AstQuerySpec::AstQuerySpec" p="src/ingest.h" cx="0" ccx="0" in="0" churn="25" amp="74" r="16">struct AstQuerySpec</d>
<d l="1468" n="spanTierMemoTryLoad" id="src/ingest_astquery.h::rw::spanTierMemoTryLoad" p="src/ingest_astquery.h" cx="3" ccx="1" in="1" churn="5" amp="43" r="17">inline bool spanTierMemoTryLoad( bool useMemo, const std::string&amp; diskPath, const StatInfo&amp; now, SpanTierMap&amp; out )</d>
<d l="462" n="SpanTier" id="src/ingest.h::rw::SpanTier" p="src/ingest.h" cx="0" ccx="0" in="1" churn="25" amp="75" r="18">enum class SpanTier : std::uint8_t</d>
<d l="516" n="McpIndex" id="src/mcpindex.h::McpIndex::McpIndex" p="src/mcpindex.h" cx="0" ccx="0" in="0" churn="20" amp="41" r="19">struct McpIndex</d>
<d l="239" n="runParseWorker" p="src/ingest_parsepool.h" cx="49" ccx="107" in="1" churn="3" amp="12" tested="1" r="20">inline void runParseWorker( ParsePoolShared&amp; sh, unsigned t )</d>
<d l="218" n="cc_declHasStructuredBinding" p="src/ingest_metrics.h" cx="5" ccx="6" in="1" churn="2" amp="27" tested="1" r="21">inline bool cc_declHasStructuredBinding( TSNode n, int depth ) noexcept</d>
<d l="107" n="tryParsePredicateOnAll" id="src/query.h::query::tryParsePredicateOnAll" p="src/query.h" cx="1" ccx="0" in="0" churn="10" amp="40" r="22">bool tryParsePredicateOnAll( Eval&amp; e, std::function&lt;std::vector&lt;NodeId&gt;( std::vector&lt;NodeId&gt; )&gt;&amp; apply )</d>
<d l="1298" n="kSpanTierMemoMinBytes" id="src/ingest_astquery.h::rw::kSpanTierMemoMinBytes" p="src/ingest_astquery.h" cx="0" ccx="0" in="0" churn="5" amp="42" pure="1" r="23">constexpr long long kSpanTierMemoMinBytes = 32ll &lt;&lt; 10</d>
<d l="935" n="ErrorMaskRule" id="src/lintrules.h::ErrorMaskRule::ErrorMaskRule" p="src/lintrules.h" cx="0" ccx="0" in="0" churn="12" amp="46" r="24">struct ErrorMaskRule</d>
… [61 more display lines; full output is 9977 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --for="why does src/lexical.h chooseForRanker pick name-exact BM25"`

*Mention anchoring (default-on): a path and a Symbol literally named in the task get lifted; the header says what anchored.*

`````
<ctx task="why does src/lexical.h chooseForRanker pick name-exact BM25" route="routed: subtoken+body BM25 (--for&apos;s default) — no strong name hit, multi-word conceptual query" root="." confidence="low" margin_pct="0" at="c7725f3ef" mention_anchored="3" doc_mentions="2" bundle="compact" bodies= … [line truncated: 45 more bytes on this line]
<!-- ripwire lens for "why does src/lexical.h chooseForRanker pick name-exact BM25" [mention anchor: 1 file + 2 symbols named in the task, score lifted to within 5% of the top score; mention_anchored= on the root repeats this total] [doc mentions: 2 docs discussing 1 top-ranked symbol surfaced; doc_mentions= on the root repeats the doc count] [confidence= derives from the ranked head's largest relative score drop (margin_pct=, whole percent, 0 = none; the same gap the adaptive flag cuts at). low = flat ranking: treat the set as a starting point, not an answer]: reusable building blocks + quality facts for what you're about to touch (cx=complexity ccx=cognitive in=reuse-count churn=recent-commits amp=change-amplification clone=1(duplicated) tested=1) — prefer composing/reusing these; watch the high-churn/high-amp/cloned ones; bundle=compact: conceptual query, so this map ships one-hop EDGE context, no bodies (bodies=0, reason=compact-route or no_candidates). hops rows are h l=line p=file n=name, and a row's calls child names its callees (c n= l=). hops and calls disclose total=requested shown=printed capped=1 when the BUDGET cut a listing; noedge=N counts ranked symbols with no RESOLVED callee found (never none exists). For a body: expand=p:n pasted off a row; the auto-bodies flag puts the bodies back; tail: file-grain tail, WEAKER evidence than the ranked rows (paths only): the remaining candidate files with a positive score, best-symbol rank order; rows are t p=file; total=candidate files, shown=printed, capped=1 when they differ. r= on a ranked row is its 1-based rank in this lens ranking, rows in r= order, p= the file (a gap = a budget-trimmed row) -->
<!-- root= is the crawl root; p= below is RELATIVE to it (single-root only; absent => p= is ingest's own path, unchanged); at=this commit(+dirty). dropped_positive="16" est_tokens= prices this bundle in tokens -->
<sigs shown="24" total="40" capped="1">
<d l="498" n="runEvalRetrieval" id="src/eval.h::rw::runEvalRetrieval" p="src/eval.h" cx="15" ccx="25" in="1" churn="9" amp="24" r="1" next="--expand=src/eval.h:runEvalRetrieval">inline int runEvalRetrieval( const IngestResult&amp; ing, const Graph&amp; g )</d>
<d l="155" n="printEvalRankerNote" id="src/eval.h::rw::printEvalRankerNote" p="src/eval.h" cx="1" ccx="0" in="1" churn="9" amp="24" r="2">
<doc>P11.12: the interpretive footer for --eval&apos;s ranker table, pulled into its own function so the 9…</doc>inline void printEvalRankerNote()</d>
<d l="1212" n="lexicalScoresNameExactRanked" id="src/lexical.h::rw::lexicalScoresNameExactRanked" p="src/lexical.h" cx="1" ccx="0" in="4" churn="31" amp="49" r="3">
<doc>The name-exact ranker AS THE RETRIEVAL LENS SERVES IT: whole-name BM25 plus the definition-over-…</doc>inline std::vector&lt;float&gt; lexicalScoresNameExactRanked( const IngestResult&amp; ing, std::string_view query, const std::vector&lt;float&gt;* symbolScoreMul )</d>
<d l="91" n="kWeakLexicalScoreThreshold" id="src/lexical.h::rw::kWeakLexicalScoreThreshold" p="src/lexical.h" cx="0" ccx="0" in="0" churn="31" amp="45" pure="1" r="4">
<doc>calling agent knows to reformulate rather than trust the ranking. Calibrated empirically (2026-0…</doc>inline constexpr float kWeakLexicalScoreThreshold = 1.0f</d>
<d l="1638" n="chooseForRanker" id="src/lexical.h::rw::chooseForRanker" p="src/lexical.h" cx="26" ccx="34" in="7" churn="31" amp="52" r="5">inline RouteChoice chooseForRanker( const IngestResult&amp; ing, std::string_view query )</d>
<d l="42" n="LensRanking" id="src/packtask.h::LensRanking::LensRanking" p="src/packtask.h" cx="0" ccx="0" in="0" churn="34" amp="102" r="6">struct LensRanking</d>
<d l="3856" n="candidatesRootTag" id="src/serialize.h::rw::candidatesRootTag" p="src/serialize.h" cx="5" ccx="4" in="1" churn="99" amp="247" r="7">inline std::string candidatesRootTag( std::size_t keep, std::size_t corpusCount, const CandidateProvenance&amp; prov )</d>
<d l="649" n="runEvalSkills" id="src/skilleval.h::rw::runEvalSkills" p="src/skilleval.h" cx="56" ccx="97" in="1" churn="9" amp="25" r="8">inline int runEvalSkills( const std::string&amp; root, const IngestResult&amp; ing, const Graph&amp; g, const std::string&amp; labelsPath )</d>
<d l="1614" n="declinedRouteReason" id="src/lexical.h::rw::declinedRouteReason" p="src/lexical.h" cx="1" ccx="0" in="1" churn="31" amp="46" r="9">inline std::string declinedRouteReason( const ImplausibleAnchor&amp; imp )</d>
<d l="901" n="runEvalMined" id="src/eval.h::rw::runEvalMined" p="src/eval.h" cx="25" ccx="38" in="1" churn="9" amp="24" r="10">inline int runEvalMined( const std::string&amp; root, const IngestResult&amp; ing, const Graph&amp; g, const std::string&amp; path )</d>
<d l="789" n="NameCorpusStats" id="src/naminglens.h::NameCorpusStats::NameCorpusStats" p="src/naminglens.h" cx="0" ccx="0" in="0" churn="14" amp="44" r="11">struct NameCorpusStats</d>
<d l="3252" n="packTaskText" id="src/mcpverbs.h::rw::packTaskText" p="src/mcpverbs.h" cx="21" ccx="30" in="1" churn="117" amp="245" r="12">inline std::string packTaskText( const std::string&amp; root, const std::string&amp; task, std::size_t budgetTokens, RedactCounts* redact = nullptr, std::uint32_ … [line truncated: 14 more bytes on this line]
<d l="930" n="lexicalScoresNameExactTiered" id="src/lexical.h::rw::lexicalScoresNameExactTiered" p="src/lexical.h" cx="35" ccx="61" in="2" churn="31" amp="47" r="13">inline std::vector&lt;float&gt; lexicalScoresNameExactTiered( const IngestResult&amp; ing, std::string_view query, const std::vector&l … [line truncated: 33 more bytes on this line]
<d l="168" n="runEval" id="src/eval.h::rw::runEval" p="src/eval.h" cx="44" ccx="66" in="1" churn="9" amp="24" r="14">inline int runEval( const std::string&amp; root, const IngestResult&amp; ing, const Graph&amp; g, const std::vector&lt;char&gt;&amp; currentDiff )</d>
<d l="37" n="computeLensRanking" p="src/verbs_for.h" cx="49" ccx="79" in="3" churn="29" amp="94" r="15">rw::LensRanking computeLensRanking( const MainDispatch&amp; d, std::string_view task, bool compactCandidate = false, bool fullDistribution = false ) // deep-tail: the file-grain tail reads the WHO … [line truncated: 52 more bytes on this line]
<d l="322" n="takeQualifiedIdent" id="src/layout.h::layout::takeQualifiedIdent" p="src/layout.h" cx="9" ccx="8" in="6" churn="13" amp="47" r="16">inline std::string_view takeQualifiedIdent( std::string_view src, std::size_t&amp; i )</d>
<d l="3835" n="CandidateProvenance" id="src/serialize.h::CandidateProvenance::CandidateProvenance" p="src/serialize.h" cx="0" ccx="0" in="0" churn="99" amp="246" r="17">struct CandidateProvenance</d>
<d l="537" n="runEvalViews" p="src/main.cpp" cx="5" ccx="4" in="1" churn="271" amp="420" r="18">std::optional&lt;int&gt; runEvalViews( const MainDispatch&amp; d )</d>
<d l="29" n="kLexWeightDoc" id="src/lexindex.h::rw::kLexWeightDoc" p="src/lexindex.h" cx="0" ccx="0" in="0" churn="6" amp="12" pure="1" r="19">inline constexpr int kLexWeightDoc = 2</d>
<d l="1071" n="lexicalScoresNameExact" id="src/lexical.h::rw::lexicalScoresNameExact" p="src/lexical.h" cx="1" ccx="0" in="3" churn="31" amp="48" r="20">inline std::vector&lt;float&gt; lexicalScoresNameExact( const IngestResult&amp; ing, std::string_view query )</d>
<d l="3112" n="canonicalIdMatches" id="src/graph.h::rw::canonicalIdMatches" p="src/graph.h" cx="1" ccx="0" in="2" churn="59" amp="196" r="21">inline bool canonicalIdMatches( std::string_view canonAbs, std::string_view spec ) noexcept</d>
<d l="150" n="kEditCheckSpellingsShown" id="src/editcheck.h::rw::kEditCheckSpellingsShown" p="src/editcheck.h" cx="0" ccx="0" in="0" churn="15" amp="77" pure="1" r="22">constexpr std::size_t kEditCheckSpellingsShown = 6</d>
<d l="217" n="resolveExemplarKind" id="src/exemplar.h::rw::resolveExemplarKind" p="src/exemplar.h" cx="12" ccx="14" in="1" churn="5" amp="14" r="23">inline bool resolveExemplarKind( const IngestResult&amp; ing, const Graph&amp; g, std::string_view kindOrTask, ExemplarPick&amp; pick )</d>
… [52 more display lines; full output is 9798 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --for="why does src/lexical.h chooseForRanker pick name-exact BM25" --no-mention-boost`

*Same task with the anchor disabled — the contrast the flag exists for.*

`````
<ctx task="why does src/lexical.h chooseForRanker pick name-exact BM25" route="routed: subtoken+body BM25 (--for&apos;s default) — no strong name hit, multi-word conceptual query" root="." confidence="low" margin_pct="0" at="c7725f3ef" doc_mentions="2" bundle="compact" bodies="0" reason="compact-r … [line truncated: 24 more bytes on this line]
<!-- ripwire lens for "why does src/lexical.h chooseForRanker pick name-exact BM25" [doc mentions: 2 docs discussing 1 top-ranked symbol surfaced; doc_mentions= on the root repeats the doc count] [confidence= derives from the ranked head's largest relative score drop (margin_pct=, whole percent, 0 = none; the same gap the adaptive flag cuts at). low = flat ranking: treat the set as a starting point, not an answer]: reusable building blocks + quality facts for what you're about to touch (cx=complexity ccx=cognitive in=reuse-count churn=recent-commits amp=change-amplification clone=1(duplicated) tested=1) — prefer composing/reusing these; watch the high-churn/high-amp/cloned ones; bundle=compact: conceptual query, so this map ships one-hop EDGE context, no bodies (bodies=0, reason=compact-route or no_candidates). hops rows are h l=line p=file n=name, and a row's calls child names its callees (c n= l=). hops and calls disclose total=requested shown=printed capped=1 when the BUDGET cut a listing; noedge=N counts ranked symbols with no RESOLVED callee found (never none exists). For a body: expand=p:n pasted off a row; the auto-bodies flag puts the bodies back; tail: file-grain tail, WEAKER evidence than the ranked rows (paths only): the remaining candidate files with a positive score, best-symbol rank order; rows are t p=file; total=candidate files, shown=printed, capped=1 when they differ. r= on a ranked row is its 1-based rank in this lens ranking, rows in r= order, p= the file (a gap = a budget-trimmed row) -->
<!-- root= is the crawl root; p= below is RELATIVE to it (single-root only; absent => p= is ingest's own path, unchanged); at=this commit(+dirty). dropped_positive="15" est_tokens= prices this bundle in tokens -->
<sigs shown="25" total="40" capped="1">
<d l="498" n="runEvalRetrieval" id="src/eval.h::rw::runEvalRetrieval" p="src/eval.h" cx="15" ccx="25" in="1" churn="9" amp="24" r="1" next="--expand=src/eval.h:runEvalRetrieval">inline int runEvalRetrieval( const IngestResult&amp; ing, const Graph&amp; g )</d>
<d l="155" n="printEvalRankerNote" id="src/eval.h::rw::printEvalRankerNote" p="src/eval.h" cx="1" ccx="0" in="1" churn="9" amp="24" r="2">
<doc>P11.12: the interpretive footer for --eval&apos;s ranker table, pulled into its own function so the 9…</doc>inline void printEvalRankerNote()</d>
<d l="1212" n="lexicalScoresNameExactRanked" id="src/lexical.h::rw::lexicalScoresNameExactRanked" p="src/lexical.h" cx="1" ccx="0" in="4" churn="31" amp="49" r="3">
<doc>The name-exact ranker AS THE RETRIEVAL LENS SERVES IT: whole-name BM25 plus the definition-over-…</doc>inline std::vector&lt;float&gt; lexicalScoresNameExactRanked( const IngestResult&amp; ing, std::string_view query, const std::vector&lt;float&gt;* symbolScoreMul )</d>
<d l="91" n="kWeakLexicalScoreThreshold" id="src/lexical.h::rw::kWeakLexicalScoreThreshold" p="src/lexical.h" cx="0" ccx="0" in="0" churn="31" amp="45" pure="1" r="4">
<doc>calling agent knows to reformulate rather than trust the ranking. Calibrated empirically (2026-0…</doc>inline constexpr float kWeakLexicalScoreThreshold = 1.0f</d>
<d l="42" n="LensRanking" id="src/packtask.h::LensRanking::LensRanking" p="src/packtask.h" cx="0" ccx="0" in="0" churn="34" amp="102" r="5">struct LensRanking</d>
<d l="1638" n="chooseForRanker" id="src/lexical.h::rw::chooseForRanker" p="src/lexical.h" cx="26" ccx="34" in="7" churn="31" amp="52" r="6">inline RouteChoice chooseForRanker( const IngestResult&amp; ing, std::string_view query )</d>
<d l="3856" n="candidatesRootTag" id="src/serialize.h::rw::candidatesRootTag" p="src/serialize.h" cx="5" ccx="4" in="1" churn="99" amp="247" r="7">inline std::string candidatesRootTag( std::size_t keep, std::size_t corpusCount, const CandidateProvenance&amp; prov )</d>
<d l="649" n="runEvalSkills" id="src/skilleval.h::rw::runEvalSkills" p="src/skilleval.h" cx="56" ccx="97" in="1" churn="9" amp="25" r="8">inline int runEvalSkills( const std::string&amp; root, const IngestResult&amp; ing, const Graph&amp; g, const std::string&amp; labelsPath )</d>
<d l="1614" n="declinedRouteReason" id="src/lexical.h::rw::declinedRouteReason" p="src/lexical.h" cx="1" ccx="0" in="1" churn="31" amp="46" r="9">inline std::string declinedRouteReason( const ImplausibleAnchor&amp; imp )</d>
<d l="901" n="runEvalMined" id="src/eval.h::rw::runEvalMined" p="src/eval.h" cx="25" ccx="38" in="1" churn="9" amp="24" r="10">inline int runEvalMined( const std::string&amp; root, const IngestResult&amp; ing, const Graph&amp; g, const std::string&amp; path )</d>
<d l="789" n="NameCorpusStats" id="src/naminglens.h::NameCorpusStats::NameCorpusStats" p="src/naminglens.h" cx="0" ccx="0" in="0" churn="14" amp="44" r="11">struct NameCorpusStats</d>
<d l="3252" n="packTaskText" id="src/mcpverbs.h::rw::packTaskText" p="src/mcpverbs.h" cx="21" ccx="30" in="1" churn="117" amp="245" r="12">inline std::string packTaskText( const std::string&amp; root, const std::string&amp; task, std::size_t budgetTokens, RedactCounts* redact = nullptr, std::uint32_ … [line truncated: 14 more bytes on this line]
<d l="930" n="lexicalScoresNameExactTiered" id="src/lexical.h::rw::lexicalScoresNameExactTiered" p="src/lexical.h" cx="35" ccx="61" in="2" churn="31" amp="47" r="13">inline std::vector&lt;float&gt; lexicalScoresNameExactTiered( const IngestResult&amp; ing, std::string_view query, const std::vector&l … [line truncated: 33 more bytes on this line]
<d l="168" n="runEval" id="src/eval.h::rw::runEval" p="src/eval.h" cx="44" ccx="66" in="1" churn="9" amp="24" r="14">inline int runEval( const std::string&amp; root, const IngestResult&amp; ing, const Graph&amp; g, const std::vector&lt;char&gt;&amp; currentDiff )</d>
<d l="37" n="computeLensRanking" p="src/verbs_for.h" cx="49" ccx="79" in="3" churn="29" amp="94" r="15">rw::LensRanking computeLensRanking( const MainDispatch&amp; d, std::string_view task, bool compactCandidate = false, bool fullDistribution = false ) // deep-tail: the file-grain tail reads the WHO … [line truncated: 52 more bytes on this line]
<d l="322" n="takeQualifiedIdent" id="src/layout.h::layout::takeQualifiedIdent" p="src/layout.h" cx="9" ccx="8" in="6" churn="13" amp="47" r="16">inline std::string_view takeQualifiedIdent( std::string_view src, std::size_t&amp; i )</d>
<d l="3835" n="CandidateProvenance" id="src/serialize.h::CandidateProvenance::CandidateProvenance" p="src/serialize.h" cx="0" ccx="0" in="0" churn="99" amp="246" r="17">struct CandidateProvenance</d>
<d l="537" n="runEvalViews" p="src/main.cpp" cx="5" ccx="4" in="1" churn="271" amp="420" r="18">std::optional&lt;int&gt; runEvalViews( const MainDispatch&amp; d )</d>
<d l="29" n="kLexWeightDoc" id="src/lexindex.h::rw::kLexWeightDoc" p="src/lexindex.h" cx="0" ccx="0" in="0" churn="6" amp="12" pure="1" r="19">inline constexpr int kLexWeightDoc = 2</d>
<d l="1071" n="lexicalScoresNameExact" id="src/lexical.h::rw::lexicalScoresNameExact" p="src/lexical.h" cx="1" ccx="0" in="3" churn="31" amp="48" r="20">inline std::vector&lt;float&gt; lexicalScoresNameExact( const IngestResult&amp; ing, std::string_view query )</d>
<d l="3112" n="canonicalIdMatches" id="src/graph.h::rw::canonicalIdMatches" p="src/graph.h" cx="1" ccx="0" in="2" churn="59" amp="196" r="21">inline bool canonicalIdMatches( std::string_view canonAbs, std::string_view spec ) noexcept</d>
<d l="150" n="kEditCheckSpellingsShown" id="src/editcheck.h::rw::kEditCheckSpellingsShown" p="src/editcheck.h" cx="0" ccx="0" in="0" churn="15" amp="77" pure="1" r="22">constexpr std::size_t kEditCheckSpellingsShown = 6</d>
<d l="217" n="resolveExemplarKind" id="src/exemplar.h::rw::resolveExemplarKind" p="src/exemplar.h" cx="12" ccx="14" in="1" churn="5" amp="14" r="23">inline bool resolveExemplarKind( const IngestResult&amp; ing, const Graph&amp; g, std::string_view kindOrTask, ExemplarPick&amp; pick )</d>
… [53 more display lines; full output is 9827 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --lego=Vehicle`

*Interface -> implementors view: every existing impl of the named interface; the method contract is extracted for the C-family/Java/TS/Python tiers — for a Rust trait (this fixture) it discloses caveat="not-extracted-for-lang" rather than an empty list.*

`````
<ctx root=".">
<!-- ripwire lego: ONE interface/base type — its method contract (<m>, where the language captures it soundly) and every implementor (<impl>) the extends/implements edges reach, own-language only; implementors= counts them. counts_floor="1": every graph-derived count here is a FLOOR, never a total. Call edges are extracted from source text by NAME, so dynamic dispatch, callbacks, macros and cross-language calls can be missing; read a zero as "none found", never as "none exists". graph_ambiguous=/graph_unresolved= are the whole graph's resolver gauge (calls split over several defs / calls whose in-repo defs were all language-filtered), the map header's ambiguous=/unresolved=. On a NAMED target only, methods="0" caveat="not-extracted-for-lang" means the method contract itself is not read soundly for this interface's language (currently C++/ObjC only) — implementors= still stands, this caveat is about <m> rows alone. -->
<lego graph_ambiguous="6085" graph_unresolved="3093" counts_floor="1">
<iface n="Vehicle" p="test/legofix/vehicle.rs" methods="0" caveat="not-extracted-for-lang" defs="1" implementors="2">
<impl n="Car" p="test/legofix/vehicle.rs"/>
<impl n="Bike" p="test/legofix/vehicle.rs"/>
</iface>
</lego>
</ctx>
`````

## `./build/ripwire . --exemplar="format byte sizes for humans"`

*The repo's best-in-class instance to imitate before writing new code (picked by ROLE).*

`````
<!-- ripwire exemplar for "format byte sizes for humans" (task -> kind=fn, low-confidence: weak match, fell back to fn): the repo's best-in-class fn to imitate — chosen by ROLE, NEVER by text similarity to your task: candidates are first filtered to cognitive complexity at or under the ccx ceiling (4x the complexity bar), then ordered non-fixture path before test-fixture path, tested before untested, higher fan-in, lower complexity, fewer lines, lowest id. low_confidence=1 marks a weak task-to-kind match that fell back to fn; over_ccx_bar=1 marks a corpus where nothing was under the ceiling, so the pick is the least bad rather than a clean one; candidates= counts the ELIGIBLE instances of the kind (post-ceiling), not every instance. On the root, the three attributes that ARE that ordering's evidence: in=reuse-count (callers), ccx=cognitive complexity, tested=1 when a test reaches it (OMITTED, never 0, when none does). The body follows in a bodies section, its callee signatures in a calls child; both disclose truncation the house way: total= is how many qualified, shown= how many are printed, capped=1 when the two differ (calls omits shown= and capped= when its list is complete). Copy its shape, not its text. -->
<exemplar kind="fn" candidates="7717" n="min" p="src/infra/fastmath.h:51" in="125" ccx="1" root="." tested="1" low_confidence="1">
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
ripwire recall — "quality delta gating exit codes" — 74 relevant of 148 document files, best-first — total=74 shown=1 capped=1 truncated=1 generated_demoted=1 max_tokens=8000 est_tokens=6584  [lines= on a doc is its SELECTED section range — pre-truncation; the per-doc truncation marker names … [line truncated: 28 more bytes on this line]

━━ skills/ripwire-quality-bar/SKILL.md  (relevance 6.527) ━━  [sections: 8 of 10, section-granular; whole doc 31569 B; lines="54-137,138-258,259-287,288-308,309-340,341-350,351-361,362-367"]  [truncated: 16103 of 27368 bytes]
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
… [184 more lines, 16837 bytes total]
`````

## `./build/ripwire . --tree`

*File-by-file orientation map (top symbols per file).*

`````
<!-- ripwire tree: each file + its top symbols by rank, files ordered by their best symbol's rank (path breaks ties) — a session-start orientation map. files= is the indexed corpus; rows list files WITH symbols; files_unlisted= holds the symbol-less remainder — files equals files_unlisted plus the LISTABLE file set, which is what the rows below enumerate before any paging window is applied; under explicit paging (limit=/offset=) that listable count is emitted as total= and shown= says how many of it these rows are. The rows are a WINDOW even without explicit paging: the default prints the 80 files with the best-ranked symbols (shown=/capped=/total=/has_more=/next_offset= disclose the cut) and next= pastes the next page; limit= raises it. pr_iters=pagerank-power-iterations(stop:L1-residual-below-tol,else-ceiling) pr_converged=0-only-when-ceiling-hit-first(absent=converged;no-such-attr=not-pagerank-ordered) -->
<!-- root= on this element is the crawl root every p= below is RELATIVE to (single-root runs only; absent => p= is the path ingest itself used, unchanged). -->
<tree files="1588" files_unlisted="74" shown="80" capped="1" total="1514" has_more="1" next_offset="80" offset="0" limit="0" pr_iters="31" root="." next="--tree --offset=80">
<file p="src/infra/svector.h" symbols="68">
<s t="method" n="size"/>
<s t="method" n="buf"/>
<s t="method" n="buf"/>
</file>
<file p="src/notes.h" symbols="26">
<s t="method" n="empty"/>
<s t="method" n="find"/>
<s t="fn" n="sortNotes"/>
</file>
<file p="src/scipoverlay.h" symbols="9">
<s t="method" n="empty"/>
<s t="method" n="targetsOf"/>
<s t="method" n="isPrecise"/>
</file>
<file p="src/ingest_model.h" symbols="17">
<s t="method" n="find"/>
<s t="fn" n="dedupRawDefs"/>
<s t="fn" n="collapseObjCDeclDefs"/>
</file>
<file p="src/graph.h" symbols="149">
<s t="method" n="find"/>
<s t="fn" n="isTestedByReach"/>
<s t="fn" n="graphCountFloorAttrXml"/>
</file>
<file p="src/renamemine.h" symbols="32">
<s t="method" n="clear"/>
… [372 more display lines; full output is 11797 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --html=<scratch>/aux/map2.html`

*Self-contained HTML force-directed call graph.*

`````
(empty)
`````

Artifact written:

`````
   58719 <scratch>/aux/map2.html
`````

## `./build/ripwire . --order=stable --top-k=5`

*Stable (path/id) emit order — provider KV-cache hits across re-runs.*

`````
<!-- ripwire v1 t=fn|method|cls|struct|iface|var|sec|macro(#define;degraded:body-is-replacement-text,edges-cross-expansion) p=path layer=arch-layer(opt) n=name id=canonical(path::scope::name,when-scoped) k=rank c=call amb=ambiguous-calls(read-source) lpin=calls-pinned-by-locality-prior-alone(a-disclosed-guess;read-source;absent-if-0) overloads=N-same-name-defs-merged-into-this-row(absent-if-1;shown=counts-them-individually,so-rows+sum(overloads-1)=shown) prov=scip(precise;else name-based) hdr:unresolved=call-name-defined-only-in-a-lang-incompatible-file (edges heuristic) hdr:locality_pinned=sum-of-lpin(absent-if-0) hdr:external=calls-refused-as-bound-outside-the-tree(builtin/stdlib-name-without-in-repo-evidence,external-import,super-past-the-tree;no-edge;absent-if-0) r:est_tokens=hdr-copy(none-if-stable) -->
<!-- r:root=crawl-root-every-p=-is-relative-to(single-root-only;absent=>p=is-the-raw-ingest-path) -->
<!-- pr_iters=pagerank-power-iterations(stop:L1-residual-below-tol,else-ceiling) pr_converged=0-only-when-ceiling-hit-first(absent=converged;no-such-attr=not-pagerank-ordered) -->
<r root="." pr_iters="31" lens="k,est_tokens">
<f p="src/infra/svector.h" layer="infra">
<s t="method" n="buf" id="src/infra/svector.h::svector::buf" overloads="2">
</s>
<s t="method" n="size" id="src/infra/svector.h::svector::size">
</s>
</f>
<f p="src/notes.h">
<s t="method" n="empty" id="src/notes.h::NoteIndex::empty">
</s>
</f>
<f p="src/scipoverlay.h">
<s t="method" n="empty" id="src/scipoverlay.h::ScipOverlay::empty">
</s>
</f>
</r>
<!-- files=1588 symbols=13849 edges=17058 shown=5 est_tokens=716 ambiguous=6085 unresolved=3093 locality_pinned=6 external=788 precise=3 skipped_oversize=15 unindexed="txt:59,jsonl:26,tsv:21,scm:18,expected:15,lock:7" unindexed_exts=19 order=stable -->
`````


---

# navigate / answer a question

## `./build/ripwire . --around=rankGraphTeleport`

*Ego graph around one symbol — depth 1 BY DEFAULT now (the root's depth= says so): ~6 KB where the 2-hop neighbourhood is ~64 KB on this repo.*

`````
<!-- ripwire v1 t=fn|method|cls|struct|iface|var|sec|macro(#define;degraded:body-is-replacement-text,edges-cross-expansion) p=path layer=arch-layer(opt) n=name id=canonical(path::scope::name,when-scoped) k=rank c=call amb=ambiguous-calls(read-source) lpin=calls-pinned-by-locality-prior-alone(a-disclosed-guess;read-source;absent-if-0) overloads=N-same-name-defs-merged-into-this-row(absent-if-1;shown=counts-them-individually,so-rows+sum(overloads-1)=shown) prov=scip(precise;else name-based) hdr:unresolved=call-name-defined-only-in-a-lang-incompatible-file (edges heuristic) hdr:locality_pinned=sum-of-lpin(absent-if-0) hdr:external=calls-refused-as-bound-outside-the-tree(builtin/stdlib-name-without-in-repo-evidence,external-import,super-past-the-tree;no-edge;absent-if-0) r:est_tokens=hdr-copy(none-if-stable) -->
<!-- r:root=crawl-root-every-p=-is-relative-to(single-root-only;absent=>p=is-the-raw-ingest-path) -->
<!-- of= is the resolved SEED this neighbourhood is centred on; depth= call hops walked and fanout= neighbours kept per hop are its whole boundary, so a row's absence means outside them, not nonexistent. defs= (only when >1) = that NAME has N definitions and the lowest-id one was walked; qualify with file:name or @FILE:LINE to pick another. -->
<!-- files=1588 symbols=13849 edges=17058 shown=16 est_tokens=2542 ambiguous=6085 unresolved=3093 locality_pinned=6 external=788 precise=3 skipped_oversize=15 unindexed="txt:59,jsonl:26,tsv:21,scm:18,expected:15,lock:7" unindexed_exts=19 order=important-first -->
<r root="." of="rankGraphTeleport" depth="1" fanout="32" est_tokens="2542">
<f p="src/graph.h">
<s t="fn" n="rankGraphTeleport" id="src/graph.h::rw::rankGraphTeleport" amb="6" k="1.0000">
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
<s t="fn" n="biasPrior" id="src/graph.h::rw::biasPrior" k="0.5000">
<c n="size"/>
</s>
<s t="fn" n="rankGraph" id="src/graph.h::rw::rankGraph" k="0.5000">
<c n="rankGraphTeleport"/>
<c n="size"/>
</s>
<s t="fn" n="anchoredLexicalRank" id="src/graph.h::rw::anchoredLexicalRank" amb="7" k="0.5000">
<c n="rankGraphTeleport"/>
<c n="blendMaxNorm"/>
<c n="min"/>
<c n="back"/>
<c n="back"/>
… [186 more display lines; full output is 6303 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --around=rankGraphTeleport --around-depth=2`

*The restoring knob: --around-depth=2 brings back the whole 2-hop neighbourhood (depth="2" on the root) — pay for it only when the 1-hop view was not enough.*

`````
<!-- ripwire v1 t=fn|method|cls|struct|iface|var|sec|macro(#define;degraded:body-is-replacement-text,edges-cross-expansion) p=path layer=arch-layer(opt) n=name id=canonical(path::scope::name,when-scoped) k=rank c=call amb=ambiguous-calls(read-source) lpin=calls-pinned-by-locality-prior-alone(a-disclosed-guess;read-source;absent-if-0) overloads=N-same-name-defs-merged-into-this-row(absent-if-1;shown=counts-them-individually,so-rows+sum(overloads-1)=shown) prov=scip(precise;else name-based) hdr:unresolved=call-name-defined-only-in-a-lang-incompatible-file (edges heuristic) hdr:locality_pinned=sum-of-lpin(absent-if-0) hdr:external=calls-refused-as-bound-outside-the-tree(builtin/stdlib-name-without-in-repo-evidence,external-import,super-past-the-tree;no-edge;absent-if-0) r:est_tokens=hdr-copy(none-if-stable) -->
<!-- r:root=crawl-root-every-p=-is-relative-to(single-root-only;absent=>p=is-the-raw-ingest-path) -->
<!-- of= is the resolved SEED this neighbourhood is centred on; depth= call hops walked and fanout= neighbours kept per hop are its whole boundary, so a row's absence means outside them, not nonexistent. defs= (only when >1) = that NAME has N definitions and the lowest-id one was walked; qualify with file:name or @FILE:LINE to pick another. -->
<!-- files=1588 symbols=13849 edges=17058 shown=205 est_tokens=25975 ambiguous=6085 unresolved=3093 locality_pinned=6 external=788 precise=3 skipped_oversize=15 unindexed="txt:59,jsonl:26,tsv:21,scm:18,expected:15,lock:7" unindexed_exts=19 order=important-first -->
<r root="." of="rankGraphTeleport" depth="2" fanout="32" est_tokens="25975">
<f p="src/graph.h">
<s t="fn" n="rankGraphTeleport" id="src/graph.h::rw::rankGraphTeleport" amb="6" k="1.0000">
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
<s t="fn" n="biasPrior" id="src/graph.h::rw::biasPrior" k="0.5000">
<c n="size"/>
</s>
<s t="fn" n="rankGraph" id="src/graph.h::rw::rankGraph" k="0.5000">
<c n="rankGraphTeleport"/>
<c n="size"/>
</s>
<s t="fn" n="anchoredLexicalRank" id="src/graph.h::rw::anchoredLexicalRank" amb="7" k="0.5000">
<c n="rankGraphTeleport"/>
<c n="blendMaxNorm"/>
<c n="min"/>
<c n="back"/>
<c n="back"/>
… [2784 more display lines; full output is 64375 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --around=rankGraphTeleport --around-fanout=4`

*The other knob: --around-fanout=4 keeps only the 4 strongest edges per node (default 32) — the same 1-hop depth, a quarter of the rows.*

`````
<!-- ripwire v1 t=fn|method|cls|struct|iface|var|sec|macro(#define;degraded:body-is-replacement-text,edges-cross-expansion) p=path layer=arch-layer(opt) n=name id=canonical(path::scope::name,when-scoped) k=rank c=call amb=ambiguous-calls(read-source) lpin=calls-pinned-by-locality-prior-alone(a-disclosed-guess;read-source;absent-if-0) overloads=N-same-name-defs-merged-into-this-row(absent-if-1;shown=counts-them-individually,so-rows+sum(overloads-1)=shown) prov=scip(precise;else name-based) hdr:unresolved=call-name-defined-only-in-a-lang-incompatible-file (edges heuristic) hdr:locality_pinned=sum-of-lpin(absent-if-0) hdr:external=calls-refused-as-bound-outside-the-tree(builtin/stdlib-name-without-in-repo-evidence,external-import,super-past-the-tree;no-edge;absent-if-0) r:est_tokens=hdr-copy(none-if-stable) -->
<!-- r:root=crawl-root-every-p=-is-relative-to(single-root-only;absent=>p=is-the-raw-ingest-path) -->
<!-- of= is the resolved SEED this neighbourhood is centred on; depth= call hops walked and fanout= neighbours kept per hop are its whole boundary, so a row's absence means outside them, not nonexistent. defs= (only when >1) = that NAME has N definitions and the lowest-id one was walked; qualify with file:name or @FILE:LINE to pick another. -->
<!-- files=1588 symbols=13849 edges=17058 shown=5 est_tokens=1118 ambiguous=6085 unresolved=3093 locality_pinned=6 external=788 precise=3 skipped_oversize=15 unindexed="txt:59,jsonl:26,tsv:21,scm:18,expected:15,lock:7" unindexed_exts=19 order=important-first -->
<r root="." of="rankGraphTeleport" depth="1" fanout="4" est_tokens="1118">
<f p="src/graph.h">
<s t="fn" n="rankGraphTeleport" id="src/graph.h::rw::rankGraphTeleport" amb="6" k="1.0000">
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
<s t="fn" n="biasPrior" id="src/graph.h::rw::biasPrior" k="0.5000">
<c n="size"/>
</s>
<s t="fn" n="rankGraph" id="src/graph.h::rw::rankGraph" k="0.5000">
<c n="rankGraphTeleport"/>
<c n="size"/>
</s>
<s t="fn" n="anchoredLexicalRank" id="src/graph.h::rw::anchoredLexicalRank" amb="7" k="0.5000">
<c n="rankGraphTeleport"/>
<c n="blendMaxNorm"/>
<c n="min"/>
<c n="back"/>
<c n="back"/>
… [29 more display lines; full output is 2775 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --callers=rankGraphTeleport`

*Who calls SYM (1-hop in-edges).*

`````
<!-- ripwire callers/callees: the 1-hop call hierarchy read off the call graph — the callers form lists symbols that CALL of=; the callees form lists symbols of= itself calls. of= is the selector you passed, defs= how many DEFINITIONS it resolved to (rows UNION every def's neighbours), count= the DISTINCT neighbour symbols (a floor, per counts_floor=), windowed by limit= and offset=. A neighbour that is an indexed function-like #define is a macro row (t="macro", role="macro" on the XML row): the edge crosses a macro expansion, not a plain call — rows carry no role= otherwise. Rows are ordered SOURCE first, then test/bench, then docs, by path within a tier. hop_tested=/hop_untested= partition count= by the tested= lens below (1-hop, never transitive). tested="1" on a row means an indexed test transitively reaches it (never 0, omitted when it does not). BLIND SPOT the test-gate legend also names: only a CALL EDGE from an INDEXED test symbol counts here, so a shell or CLI-level test running a built binary as a SUBPROCESS is invisible to it and a repo tested that way reads all-untested. Read untested= as no in-process test reaches it, not as no test covers it. next= is the one pasteable follow-up (the uses verb on this selector: the call sites). counts_floor="1" means every count here is a FLOOR, never a total: edges are extracted from source TEXT by NAME. Missing: dynamic dispatch (virtual/interface/duck-typed), a most-vexing-parse declaration with no call expression, a function-pointer/callback bound to more than one function in scope (reassigned, table-indexed, lambda-bound, or address-taken/reference-bound), and a plain-name binding (fp=handler) whose variable type is not PROVABLY a function pointer (a same-file typedef/declarator; a HEADER typedef is missed; auto/template types are read as unpinned, so KEPT). A macro-generated call site is role="macro" only when its name uniquely names an indexed function-like #define (C-family, t="macro"); a shared name stays a plain call, an unindexed macro is no edge. Read a zero as "none found", never as "none exists". graph_ambiguous=/graph_unresolved= are the whole graph's resolver gauge (calls split over several defs / calls whose in-repo defs were all language-filtered), the map header's ambiguous=/unresolved=. COUNTING UNIT differs by verb: callers, callees, edit-check, graph-query and pr-context counts are DISTINCT SYMBOLS (repeated calls from one caller, and calls to two overloads, collapse into ONE row; multiplicity survives only in the call graph's edge weight). The reach counts (impact's reaches=, pr-context's dependents=) are the size of a transitive reach SET, each symbol counted once. The uses verb counts call SITES, one row per occurrence — a larger count there for the same symbol is these units agreeing, not disagreeing. The map header's edges= is a unit again different — distinct (caller,callee) PAIRS — and that document carries neither this marker nor this clause. -->
<!-- root= on this element is the crawl root every p= below is RELATIVE to (single-root runs only; absent => p= is the path ingest itself used, unchanged). -->
<callers of="rankGraphTeleport" defs="1" count="6" root="." hop_tested="0" hop_untested="6" graph_ambiguous="6085" graph_unresolved="3093" counts_floor="1" next="--uses=rankGraphTeleport">
<s t="fn" n="runEval" p="src/eval.h:168"/>
<s t="fn" n="rankGraph" p="src/graph.h:2542"/>
<s t="fn" n="anchoredLexicalRank" p="src/graph.h:3034"/>
<s t="fn" n="churnRankedGraph" p="src/main.cpp:983"/>
<s t="fn" n="runDefaultMap" p="src/main.cpp:1098"/>
<s t="fn" n="getIndex" p="src/mcpindex.h:1104"/>
</callers>
`````

## `./build/ripwire . --callers=rankGraphTeleport --legend=compact`

*The same rows under --legend=compact: the prose legend becomes one <=400 B comment plus schema="ripwire.callers/v1" on the root — every row byte and every completeness attribute (counts_floor=, graph_ambiguous=, next=) identical, ~3 KB of legend gone. Works on EVERY XML verb now, not four.*

`````
<!-- ripwire callers ripwire.callers/v1: 1-hop CALLERS of of= (defs= matched, count= distinct symbols): <s t= n= p=>; hop_tested=/hop_untested=. counts_floor=1: every count is a FLOOR, never a total. graph_ambiguous=/graph_unresolved=: resolver gauge. root=: p= relative to it. next=: the one pasteable follow-up. -->
<callers schema="ripwire.callers/v1" of="rankGraphTeleport" defs="1" count="6" root="." hop_tested="0" hop_untested="6" graph_ambiguous="6085" graph_unresolved="3093" counts_floor="1" next="--uses=rankGraphTeleport">
<s t="fn" n="runEval" p="src/eval.h:168"/>
<s t="fn" n="rankGraph" p="src/graph.h:2542"/>
<s t="fn" n="anchoredLexicalRank" p="src/graph.h:3034"/>
<s t="fn" n="churnRankedGraph" p="src/main.cpp:983"/>
<s t="fn" n="runDefaultMap" p="src/main.cpp:1098"/>
<s t="fn" n="getIndex" p="src/mcpindex.h:1104"/>
</callers>
`````

## `./build/ripwire . --callers=DoesNotExist`

*Unknown-symbol REFUSAL shape (exit 1) with a did-you-mean from real edit distance.*

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
<!-- ripwire callers/callees: the 1-hop call hierarchy read off the call graph — the callers form lists symbols that CALL of=; the callees form lists symbols of= itself calls. of= is the selector you passed, defs= how many DEFINITIONS it resolved to (rows UNION every def's neighbours), count= the DISTINCT neighbour symbols (a floor, per counts_floor=), windowed by limit= and offset=. A neighbour that is an indexed function-like #define is a macro row (t="macro", role="macro" on the XML row): the edge crosses a macro expansion, not a plain call — rows carry no role= otherwise. Rows are ordered SOURCE first, then test/bench, then docs, by path within a tier. hop_tested=/hop_untested= partition count= by the tested= lens below (1-hop, never transitive). tested="1" on a row means an indexed test transitively reaches it (never 0, omitted when it does not). BLIND SPOT the test-gate legend also names: only a CALL EDGE from an INDEXED test symbol counts here, so a shell or CLI-level test running a built binary as a SUBPROCESS is invisible to it and a repo tested that way reads all-untested. Read untested= as no in-process test reaches it, not as no test covers it. callees-only: bodyless_defs= (when present) counts defs= that are bodyless declarations (header-only or forward-declared); zero callees may mean no body to read callees from, not truly no dependencies. next= is the one pasteable follow-up (expand on this selector: the body). counts_floor="1" means every count here is a FLOOR, never a total: edges are extracted from source TEXT by NAME. Missing: dynamic dispatch (virtual/interface/duck-typed), a most-vexing-parse declaration with no call expression, a function-pointer/callback bound to more than one function in scope (reassigned, table-indexed, lambda-bound, or address-taken/reference-bound), and a plain-name binding (fp=handler) whose variable type is not PROVABLY a function pointer (a same-file typedef/declarator; a HEADER typedef is missed; auto/template types are read as unpinned, so KEPT). A macro-generated call site is role="macro" only when its name uniquely names an indexed function-like #define (C-family, t="macro"); a shared name stays a plain call, an unindexed macro is no edge. Read a zero as "none found", never as "none exists". graph_ambiguous=/graph_unresolved= are the whole graph's resolver gauge (calls split over several defs / calls whose in-repo defs were all language-filtered), the map header's ambiguous=/unresolved=. COUNTING UNIT differs by verb: callers, callees, edit-check, graph-query and pr-context counts are DISTINCT SYMBOLS (repeated calls from one caller, and calls to two overloads, collapse into ONE row; multiplicity survives only in the call graph's edge weight). The reach counts (impact's reaches=, pr-context's dependents=) are the size of a transitive reach SET, each symbol counted once. The uses verb counts call SITES, one row per occurrence — a larger count there for the same symbol is these units agreeing, not disagreeing. The map header's edges= is a unit again different — distinct (caller,callee) PAIRS — and that document carries neither this marker nor this clause. -->
<!-- root= on this element is the crawl root every p= below is RELATIVE to (single-root runs only; absent => p= is the path ingest itself used, unchanged). -->
<callees of="rankGraphTeleport" defs="1" count="9" root="." hop_tested="8" hop_untested="1" graph_ambiguous="6085" graph_unresolved="3093" counts_floor="1" next="--expand=rankGraphTeleport">
<s t="fn" n="biasPrior" p="src/graph.h:2464"/>
<s t="macro" n="PROFILE_SCOPE_DESCRIBE" p="src/infra/profileScope.h:1322" role="macro" tested="1"/>
<s t="macro" n="PROFILE_SCOPE_DESCRIBE" p="src/infra/profileScope.h:1336" role="macro" tested="1"/>
<s t="method" n="begin" p="src/infra/svector.h:269" tested="1"/>
<s t="method" n="end" p="src/infra/svector.h:270" tested="1"/>
<s t="method" n="begin" p="src/infra/svector.h:271" tested="1"/>
<s t="method" n="end" p="src/infra/svector.h:272" tested="1"/>
<s t="method" n="size" p="src/infra/svector.h:285" tested="1"/>
<s t="fn" n="pageRankDouble" p="src/pagerank.cpp:95" tested="1"/>
</callees>
`````

## `./build/ripwire . --uses=rankGraphTeleport`

*The resolvable use-sites (call/read/write/import/extends) with file:line; count= is a floor.*

`````
<!-- ripwire uses: STATICALLY RESOLVABLE use-sites of SYM (role=call|macro|read|write|import|extends|type; p=file:line) — a floor, see counts_floor below; that role list is the whole vocabulary. role="type" is a bare TYPE mention (a signature, declaration or template argument) with NO call edge — real but not an invocation, so it never reaches the call graph, PageRank or the ranked map; captured C/C++/ObjC only, and only a plain leaf spelling (a qualified or aliased spelling contributes no row). A base clause is role="extends", never role="type"; a type's own DEFINITION is never a use of itself. role="macro" is the call-shaped invocation of a name uniquely naming an indexed function-like #define — never role="call" (an expansion is not a plain call); a name shared with a non-macro definition stays role="call". Rows are ordered SOURCE first, then test/bench, then docs, by path within a tier. A MEMBER selector (Owner.field) is resolved per site instead of name-matched — that run's legend says how. in_id=canonical id (root-relative path::scope::name) of the symbol the site sits INSIDE; a scope-less enclosing symbol degrades to its bare name; absent at file scope. Reference-name-based (same heuristic level as call edges) — verify in source if a name is overloaded. external="1" ⇒ SYM has no definition in the indexed tree under ANY spelling (stdlib/third-party) — never merely none in the file you qualified with (that spelling refuses instead). A "file:name" SYM narrows defs= AND the role="call" sites, which are kept only where the call RESOLVES to a chosen def (the callers verb's own narrowing, read the other way, so the two agree); read/write/import/extends carry no resolution and stay name-matched across every def sharing the name. narrowed_roles= names what narrowed, and defs_of_name=/call_sites_of_name= (file: qualifier only) are the un-narrowed totals. counts_floor="1" means every count here is a FLOOR, never a total: edges are extracted from source TEXT by NAME. Missing: dynamic dispatch (virtual/interface/duck-typed), a most-vexing-parse declaration with no call expression, a function-pointer/callback bound to more than one function in scope (reassigned, table-indexed, lambda-bound, or address-taken/reference-bound), and a plain-name binding (fp=handler) whose variable type is not PROVABLY a function pointer (a same-file typedef/declarator; a HEADER typedef is missed; auto/template types are read as unpinned, so KEPT). A macro-generated call site is role="macro" only when its name uniquely names an indexed function-like #define (C-family, t="macro"); a shared name stays a plain call, an unindexed macro is no edge. Read a zero as "none found", never as "none exists". graph_ambiguous=/graph_unresolved= are the whole graph's resolver gauge (calls split over several defs / calls whose in-repo defs were all language-filtered), the map header's ambiguous=/unresolved=. COUNTING UNIT differs by verb: callers, callees, edit-check, graph-query and pr-context counts are DISTINCT SYMBOLS (repeated calls from one caller, and calls to two overloads, collapse into ONE row; multiplicity survives only in the call graph's edge weight). The reach counts (impact's reaches=, pr-context's dependents=) are the size of a transitive reach SET, each symbol counted once. The uses verb counts call SITES, one row per occurrence — a larger count there for the same symbol is these units agreeing, not disagreeing. The map header's edges= is a unit again different — distinct (caller,callee) PAIRS — and that document carries neither this marker nor this clause. -->
<!-- root= on this element is the crawl root every p= below is RELATIVE to (single-root runs only; absent => p= is the path ingest itself used, unchanged). -->
<uses of="rankGraphTeleport" defs="1" external="0" count="9" root="." graph_ambiguous="6085" graph_unresolved="3093" counts_floor="1">
<u role="call" p="src/eval.h:322" in_id="src/eval.h::rw::runEval"/>
<u role="call" p="src/graph.h:2545" in_id="src/graph.h::rw::rankGraph"/>
<u role="call" p="src/graph.h:3078" in_id="src/graph.h::rw::anchoredLexicalRank"/>
<u role="call" p="src/main.cpp:1007" in_id="churnRankedGraph"/>
<u role="call" p="src/main.cpp:1008" in_id="churnRankedGraph"/>
<u role="call" p="src/main.cpp:1018" in_id="churnRankedGraph"/>
<u role="call" p="src/main.cpp:1024" in_id="churnRankedGraph"/>
<u role="call" p="src/main.cpp:1195" in_id="runDefaultMap"/>
<u role="call" p="src/mcpindex.h:1200" in_id="src/mcpindex.h::rw::getIndex"/>
</uses>
`````

## `./build/ripwire . --graph-query='and(callers(name("rankGraphTeleport"),2),kind(all,fn))'`

*Composable node-set query: functions within 2 caller-hops of rankGraphTeleport.*

`````
<!-- ripwire graph-query: a fixed-operator node-set query over the call graph (sources name/all; filters kind/cx/fanin/file/layer; bounded closure callers/callees; joins and/or/not), ranked by importance + capped at the top-k limit (default 200); narrow the query or raise top-k for more. NOT Datalog. counts_floor="1" means every count here is a FLOOR, never a total: edges are extracted from source TEXT by NAME. Missing: dynamic dispatch (virtual/interface/duck-typed), a most-vexing-parse declaration with no call expression, a function-pointer/callback bound to more than one function in scope (reassigned, table-indexed, lambda-bound, or address-taken/reference-bound), and a plain-name binding (fp=handler) whose variable type is not PROVABLY a function pointer (a same-file typedef/declarator; a HEADER typedef is missed; auto/template types are read as unpinned, so KEPT). A macro-generated call site is role="macro" only when its name uniquely names an indexed function-like #define (C-family, t="macro"); a shared name stays a plain call, an unindexed macro is no edge. Read a zero as "none found", never as "none exists". graph_ambiguous=/graph_unresolved= are the whole graph's resolver gauge (calls split over several defs / calls whose in-repo defs were all language-filtered), the map header's ambiguous=/unresolved=. COUNTING UNIT differs by verb: callers, callees, edit-check, graph-query and pr-context counts are DISTINCT SYMBOLS (repeated calls from one caller, and calls to two overloads, collapse into ONE row; multiplicity survives only in the call graph's edge weight). The reach counts (impact's reaches=, pr-context's dependents=) are the size of a transitive reach SET, each symbol counted once. The uses verb counts call SITES, one row per occurrence — a larger count there for the same symbol is these units agreeing, not disagreeing. The map header's edges= is a unit again different — distinct (caller,callee) PAIRS — and that document carries neither this marker nor this clause. pr_iters=pagerank-power-iterations(stop:L1-residual-below-tol,else-ceiling) pr_converged=0-only-when-ceiling-hit-first(absent=converged;no-such-attr=not-pagerank-ordered) -->
<query expr="and(callers(name(&quot;rankGraphTeleport&quot;),2),kind(all,fn))" count="51" shown="51" capped="0" graph_ambiguous="6085" graph_unresolved="3093" counts_floor="1" root="." pr_iters="31">
<s t="fn" n="getIndex" p="src/mcpindex.h:1104"/>
<s t="fn" n="emitCommunitiesReport" p="src/verbs_report.h:2107"/>
<s t="fn" n="anchoredLexicalRank" p="src/graph.h:3034"/>
<s t="fn" n="emitCommunityDrill" p="src/verbs_report.h:2268"/>
<s t="fn" n="rankGraph" p="src/graph.h:2542"/>
<s t="fn" n="dispatchMain" p="src/main.cpp:2653"/>
<s t="fn" n="computeLensRanking" p="src/verbs_for.h:37"/>
<s t="fn" n="postCheckJson" p="src/mcpedit.h:1075"/>
<s t="fn" n="fetchBody" p="src/mcpverbs.h:3840"/>
<s t="fn" n="runEvalRetrieval" p="src/eval.h:498"/>
<s t="fn" n="runEvalMined" p="src/eval.h:901"/>
<s t="fn" n="runEditVerb" p="src/mcpedit.h:1137"/>
<s t="fn" n="dispatchMcpLine" p="src/mcp.h:535"/>
<s t="fn" n="fetchBodyByName" p="src/mcpverbs.h:3770"/>
<s t="fn" n="anchoredFileScore" p="src/eval.h:108"/>
<s t="fn" n="symbolQueryJson" p="src/mcpverbs.h:556"/>
<s t="fn" n="analyzeToString" p="src/mcpverbs.h:398"/>
<s t="fn" n="grepHitsJson" p="src/mcpverbs.h:875"/>
<s t="fn" n="cochangePartnersJson" p="src/mcpverbs.h:1030"/>
<s t="fn" n="mentionsJson" p="src/mcpverbs.h:1331"/>
<s t="fn" n="forTaskText" p="src/mcpverbs.h:1463"/>
<s t="fn" n="legoText" p="src/mcpverbs.h:1809"/>
<s t="fn" n="ownersText" p="src/mcpverbs.h:1842"/>
<s t="fn" n="exemplarText" p="src/mcpverbs.h:1982"/>
<s t="fn" n="impactText" p="src/mcpverbs.h:2069"/>
<s t="fn" n="usesText" p="src/mcpverbs.h:2296"/>
<s t="fn" n="pathText" p="src/mcpverbs.h:2413"/>
<s t="fn" n="sliceText" p="src/mcpverbs.h:3463"/>
… [24 more display lines; full output is 5046 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --external-surface`

*Names referenced but never defined in-corpus (stdlib/third-party surface). The root carries names/shown/capped; the default is a 100-row window now, so total= and a pasteable next= join them when it bites (the explicit --limit form carries the same quintet). The sh BUILTINS (cd/echo/set…) are dropped and COUNTED as builtins_excluded= — grep/sed/git stay, they ARE the surface.*

`````
<!-- ripwire external-surface: names CALLED/IMPORTED/EXTENDED but never defined in the indexed tree = the stdlib/third-party surface the code depends on (refs=use-sites, calls=of-which-calls). builtins_excluded= counts the sh BUILTIN rows (echo printf cd exit test …) dropped from names= by default — the interpreter, not a dependency; the include-builtins flag keeps them. The rows are a WINDOW (default 100; shown=/capped=/total=/has_more=/next_offset= disclose the cut, limit=/offset= page it) and next= pastes the next page. -->
<external-surface names="1427" builtins_excluded="19" shown="100" capped="1" total="1427" has_more="1" next_offset="100" offset="0" limit="0" next="--external-surface --offset=100">
<x n="grep" lang="sh" refs="7659" calls="7659"/>
<x n="head" lang="sh" refs="1616" calls="1616"/>
<x n="cat" lang="sh" refs="1354" calls="1354"/>
<x n="tr" lang="sh" refs="1064" calls="1064"/>
<x n="c_str" lang="cpp" refs="1061" calls="1061"/>
<x n="string" lang="cpp" refs="1020" calls="1020"/>
<x n="fprintf" lang="cpp" refs="882" calls="882"/>
<x n="python3" lang="sh" refs="876" calls="876"/>
<x n="sed" lang="sh" refs="830" calls="830"/>
<x n="mkdir" lang="sh" refs="810" calls="810"/>
<x n="print" lang="py" refs="761" calls="761"/>
<x n="len" lang="py" refs="675" calls="675"/>
<x n="substr" lang="cpp" refs="661" calls="661"/>
<x n="strcmp" lang="cpp" refs="643" calls="643"/>
<x n="mktemp" lang="sh" refs="632" calls="632"/>
<x n="printf" lang="cpp" refs="605" calls="605"/>
<x n="dirname" lang="sh" refs="598" calls="598"/>
<x n="to_string" lang="cpp" refs="544" calls="544"/>
<x n="wc" lang="sh" refs="527" calls="527"/>
<x n="uint32_t" lang="cpp" refs="482" calls="482"/>
<x n="diff" lang="sh" refs="476" calls="476"/>
<x n="xmllint" lang="sh" refs="456" calls="456"/>
<x n="append" lang="py" refs="450" calls="450"/>
<x n="size_t" lang="cpp" refs="361" calls="361"/>
<x n="sort" lang="cpp" refs="358" calls="358"/>
<x n="ex" lang="cpp" refs="349" calls="349"/>
<x n="string_view" lang="cpp" refs="348" calls="348"/>
<x n="cmp" lang="sh" refs="290" calls="290"/>
… [73 more display lines; full output is 5586 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --external-surface --include-builtins`

*The restoring knob: --include-builtins keeps the shell builtins in the same 100-row window (they now compete for rows, so the window's tail differs).*

`````
<!-- ripwire external-surface: names CALLED/IMPORTED/EXTENDED but never defined in the indexed tree = the stdlib/third-party surface the code depends on (refs=use-sites, calls=of-which-calls). builtins_excluded= counts the sh BUILTIN rows (echo printf cd exit test …) dropped from names= by default — the interpreter, not a dependency; the include-builtins flag keeps them. The rows are a WINDOW (default 100; shown=/capped=/total=/has_more=/next_offset= disclose the cut, limit=/offset= page it) and next= pastes the next page. -->
<external-surface names="1446" shown="100" capped="1" total="1446" has_more="1" next_offset="100" offset="0" limit="0" next="--external-surface --offset=100">
<x n="grep" lang="sh" refs="7659" calls="7659"/>
<x n="printf" lang="sh" refs="6941" calls="6941"/>
<x n="echo" lang="sh" refs="5505" calls="5505"/>
<x n="exit" lang="sh" refs="2096" calls="2096"/>
<x n="head" lang="sh" refs="1616" calls="1616"/>
<x n="cat" lang="sh" refs="1354" calls="1354"/>
<x n="cd" lang="sh" refs="1313" calls="1313"/>
<x n="tr" lang="sh" refs="1064" calls="1064"/>
<x n="c_str" lang="cpp" refs="1061" calls="1061"/>
<x n="string" lang="cpp" refs="1020" calls="1020"/>
<x n="fprintf" lang="cpp" refs="882" calls="882"/>
<x n="python3" lang="sh" refs="876" calls="876"/>
<x n="sed" lang="sh" refs="830" calls="830"/>
<x n="mkdir" lang="sh" refs="810" calls="810"/>
<x n="print" lang="py" refs="761" calls="761"/>
<x n="len" lang="py" refs="675" calls="675"/>
<x n="substr" lang="cpp" refs="661" calls="661"/>
<x n="command" lang="sh" refs="644" calls="644"/>
<x n="strcmp" lang="cpp" refs="643" calls="643"/>
<x n="mktemp" lang="sh" refs="632" calls="632"/>
<x n="printf" lang="cpp" refs="605" calls="605"/>
<x n="dirname" lang="sh" refs="598" calls="598"/>
<x n="pwd" lang="sh" refs="572" calls="572"/>
<x n="to_string" lang="cpp" refs="544" calls="544"/>
<x n="trap" lang="sh" refs="536" calls="536"/>
<x n="wc" lang="sh" refs="527" calls="527"/>
<x n="uint32_t" lang="cpp" refs="482" calls="482"/>
<x n="diff" lang="sh" refs="476" calls="476"/>
… [73 more display lines; full output is 5529 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --path=main,rankGraphTeleport`

*Shortest directed call-path SRC -> DST. CHANGED: now reports from_p/to_p/from_defs and resolves the right `main` (was reachable="0").*

`````
<!-- ripwire path: one DIRECTED call path from= to to= (each <s> a hop); reachable= is 0 and hops= 0 when the graph holds none. counts_floor="1": every graph-derived count here is a FLOOR, never a total. Call edges are extracted from source text by NAME, so dynamic dispatch, callbacks, macros and cross-language calls can be missing; read a zero as "none found", never as "none exists". graph_ambiguous=/graph_unresolved= are the whole graph's resolver gauge (calls split over several defs / calls whose in-repo defs were all language-filtered), the map header's ambiguous=/unresolved=. -->
<!-- root= on this element is the crawl root every p= below is RELATIVE to (single-root runs only; absent => p= is the path ingest itself used, unchanged). -->
<path from="main" to="rankGraphTeleport" from_p="src/main.cpp:2634" to_p="src/graph.h:2501" from_defs="88" to_defs="1" reachable="1" hops="4" root="." graph_ambiguous="6085" graph_unresolved="3093" counts_floor="1">
<s t="fn" n="main" p="src/main.cpp:2634"/>
<s t="fn" n="runWithCompactLegend" p="src/main.cpp:2573"/>
<s t="fn" n="dispatchMain" p="src/main.cpp:2653"/>
<s t="fn" n="runDefaultMap" p="src/main.cpp:1098"/>
<s t="fn" n="rankGraphTeleport" p="src/graph.h:2501"/>
</path>
`````

## `./build/ripwire . --connect=rankGraphTeleport,runEval,getIndex`

*Minimal connecting subgraph over 3 symbols (finds shared-caller joins).*

`````
<!-- ripwire connect: minimal joining subgraph over N task symbols (metric-closure 2-approx Steiner; search is undirected so SHARED-CALLER joins are found, every <e f= t=/> keeps its TRUE caller->callee direction; graph-structured navigation per CodeCompass, arXiv 2602.20048). Call edges are name-based: dynamic dispatch / callbacks may hide connections. counts_floor="1": every graph-derived count here (nodes=, edges=, groups=) is a FLOOR, never a total; read a zero as "none found", never as "none exists". graph_ambiguous=/graph_unresolved= are the whole graph's resolver gauge (calls split over several defs / calls whose in-repo defs were all language-filtered), the map header's ambiguous=/unresolved=. defs= on a terminal row = that NAME has N definitions and the lowest-id one was used; qualify with file:name to pick another. Steiner rows never carry it. max_tokens= is the token ceiling this bundle was SHAPED against (the max_tokens flag; absent = none was asked for); est_tokens= is what it cost, truncated="paths" says the shaping had to cut, and over_ceiling="1" says est_tokens exceeds max_tokens anyway (the trim ran out of things to drop before it reached the ceiling; the bundle is then complete, not further trimmed) -->
<!-- root= on this element is the crawl root every p= below is RELATIVE to (single-root runs only; absent => p= is the path ingest itself used, unchanged). -->
<connect terminals="3" nodes="3" edges="2" radius="6" groups="1" est_tokens="740" root="." graph_ambiguous="6085" graph_unresolved="3093" counts_floor="1">
<g terminals="3">
<t n="runEval" t="fn" p="src/eval.h:168"/>
<t n="rankGraphTeleport" t="fn" p="src/graph.h:2501"/>
<t n="getIndex" t="fn" p="src/mcpindex.h:1104"/>
<e f="runEval" t="rankGraphTeleport"/>
<e f="getIndex" t="rankGraphTeleport"/>
</g>
</connect>
`````

## `./build/ripwire . --impact=rankGraphTeleport`

*Transitive blast radius — everything that reaches SYM. NOW carries shown/capped.*

`````
<!-- ripwire impact: transitive blast radius — symbols that reach SYM via calls (review before changing SYM). next= is the one pasteable follow-up (the safe-delete read of SYM). raise the default cap with limit=N (offset=M pages; a cut listing carries total=/has_more=/next_offset= so a paging loop can continue from it); on the root, limit="0" means no explicit limit was given and the verb's own default page size shaped the window — never a zero-row page. importers= is a SECOND, weaker reach: the files that directly include/import a file defining SYM, as <f via="import" p="…" lazy="0|1"/> rows after the symbol rows — not call reach, never added to reaches= (different units, files vs symbols; an importer may use a different symbol from that file, or none at all). DIRECT (one hop), never the transitive include cone. lazy="1" (TS/JS only) means every one of that importer's edges into SYM's file is a require()/import() written INSIDE A FUNCTION BODY, firing only if and when that function runs; lazy="0" means at least one edge is an ordinary top-level require/import (module-load time too). shown_importers=/importers_capped= disclose that listing's own truncation (importers= stays the full count); limit=/offset= window the symbol rows only. tested="1" on a row means an indexed test transitively reaches it (never 0, omitted when it does not). radius_tested=/radius_untested= partition reaches= by that same lens (transitive, unlike callers/callees). BLIND SPOT the test-gate legend also names: only a CALL EDGE from an INDEXED test symbol counts here, so a shell or CLI-level test running a built binary as a SUBPROCESS is invisible to it and a repo tested that way reads all-untested. Read untested= as no in-process test reaches it, not as no test covers it. counts_floor="1" means every count here is a FLOOR, never a total: edges are extracted from source TEXT by NAME. Missing: dynamic dispatch (virtual/interface/duck-typed), a most-vexing-parse declaration with no call expression, a function-pointer/callback bound to more than one function in scope (reassigned, table-indexed, lambda-bound, or address-taken/reference-bound), and a plain-name binding (fp=handler) whose variable type is not PROVABLY a function pointer (a same-file typedef/declarator; a HEADER typedef is missed; auto/template types are read as unpinned, so KEPT). A macro-generated call site is role="macro" only when its name uniquely names an indexed function-like #define (C-family, t="macro"); a shared name stays a plain call, an unindexed macro is no edge. Read a zero as "none found", never as "none exists". graph_ambiguous=/graph_unresolved= are the whole graph's resolver gauge (calls split over several defs / calls whose in-repo defs were all language-filtered), the map header's ambiguous=/unresolved=. COUNTING UNIT differs by verb: callers, callees, edit-check, graph-query and pr-context counts are DISTINCT SYMBOLS (repeated calls from one caller, and calls to two overloads, collapse into ONE row; multiplicity survives only in the call graph's edge weight). The reach counts (impact's reaches=, pr-context's dependents=) are the size of a transitive reach SET, each symbol counted once. The uses verb counts call SITES, one row per occurrence — a larger count there for the same symbol is these units agreeing, not disagreeing. The map header's edges= is a unit again different — distinct (caller,callee) PAIRS — and that document carries neither this marker nor this clause. pr_iters=pagerank-power-iterations(stop:L1-residual-below-tol,else-ceiling) pr_converged=0-only-when-ceiling-hit-first(absent=converged;no-such-attr=not-pagerank-ordered) -->
<impact of="rankGraphTeleport" defs="1" reaches="63" importers="33" shown_importers="33" importers_capped="0" radius_tested="0" radius_untested="63" root="." shown="40" capped="1" total="63" has_more="1" next_offset="40" offset="0" limit="0" graph_ambiguous="6085" graph_unresolved="3093" counts_floo … [line truncated: 59 more bytes on this line]
<s t="fn" n="getIndex" p="src/mcpindex.h:1104"/>
<s t="fn" n="emitCommunitiesReport" p="src/verbs_report.h:2107"/>
<s t="fn" n="anchoredLexicalRank" p="src/graph.h:3034"/>
<s t="fn" n="emitCommunityDrill" p="src/verbs_report.h:2268"/>
<s t="fn" n="rankGraph" p="src/graph.h:2542"/>
<s t="fn" n="dispatchMain" p="src/main.cpp:2653"/>
<s t="fn" n="computeLensRanking" p="src/verbs_for.h:37"/>
<s t="fn" n="postCheckJson" p="src/mcpedit.h:1075"/>
<s t="fn" n="fetchBody" p="src/mcpverbs.h:3840"/>
<s t="fn" n="receiptOperation" p="src/editplan.h:332"/>
<s t="fn" n="runEvalRetrieval" p="src/eval.h:498"/>
<s t="fn" n="runEvalMined" p="src/eval.h:901"/>
<s t="fn" n="runEditVerb" p="src/mcpedit.h:1137"/>
<s t="fn" n="dispatchMcpLine" p="src/mcp.h:535"/>
<s t="fn" n="runWithCompactLegend" p="src/main.cpp:2573"/>
<s t="fn" n="fetchBodyByName" p="src/mcpverbs.h:3770"/>
<s t="fn" n="anchoredFileScore" p="src/eval.h:108"/>
<s t="fn" n="symbolQueryJson" p="src/mcpverbs.h:556"/>
<s t="fn" n="analyzeToString" p="src/mcpverbs.h:398"/>
<s t="fn" n="grepHitsJson" p="src/mcpverbs.h:875"/>
<s t="fn" n="cochangePartnersJson" p="src/mcpverbs.h:1030"/>
<s t="fn" n="mentionsJson" p="src/mcpverbs.h:1331"/>
<s t="fn" n="forTaskText" p="src/mcpverbs.h:1463"/>
<s t="fn" n="legoText" p="src/mcpverbs.h:1809"/>
<s t="fn" n="ownersText" p="src/mcpverbs.h:1842"/>
<s t="fn" n="exemplarText" p="src/mcpverbs.h:1982"/>
<s t="fn" n="impactText" p="src/mcpverbs.h:2069"/>
<s t="fn" n="usesText" p="src/mcpverbs.h:2296"/>
… [46 more display lines; full output is 7645 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --mentions=rankGraphTeleport`

*Markdown docs that name SYM in a backtick (doc<->code edges).*

`````
<!-- ripwire mentions: markdown FILES that name this symbol in a `backtick` (doc<->code; NOT a call edge). docs= is the row count (distinct files); sections= counts the underlying markdown-section mentions before file-collapse (docs <= sections). Each row's mentions= is its own section-mention count. An @FILE:LINE seed rebinds to the innermost definition enclosing that line — sym= names it, of= echoes the seed as typed. No line locator: the doc edge is stored at file granularity — a fabricated always-1 l= was removed; absent beats fake -->
<!-- root= on this element is the crawl root every p= below is RELATIVE to (single-root runs only; absent => p= is the path ingest itself used, unchanged). -->
<mentions of="rankGraphTeleport" defs="1" docs="2" sections="2" root=".">
<doc p="docs/ARCHITECTURE.md" mentions="1"/>
<doc p="docs/EVALS.md" mentions="1"/>
</mentions>
`````

## `./build/ripwire . --affected=src/graph.h`

*Test files that transitively reach the changed file.*

`````
<!-- ripwire affected: test files that transitively reach the changed files/symbols (run these); seeded_by= says which reading the argument took. seed_test_files= how many of the matched files are TEST files: a test cannot reach a change it is part of, so its own symbols are not seeds of the caller walk and its row carries seed_kind="test" — it is listed because the argument matched it (it changed, run it), not because it reaches the change. script_gates_unmodelled= counts test/*.sh runners in the corpus (a path count; not every one invokes the binary) — script-to-binary edges are NOT modelled, so those gates are invisible to this walk and never counted in tests=/reached=. counts_floor="1": every graph-derived count here is a FLOOR, never a total. Call edges are extracted from source text by NAME, so dynamic dispatch, callbacks, macros and cross-language calls can be missing; read a zero as "none found", never as "none exists". graph_ambiguous=/graph_unresolved= are the whole graph's resolver gauge (calls split over several defs / calls whose in-repo defs were all language-filtered), the map header's ambiguous=/unresolved=. -->
<!-- root= on this element is the crawl root every p= below is RELATIVE to (single-root runs only; absent => p= is the path ingest itself used, unchanged). -->
<affected changed="src/graph.h" seeded_by="file" seeds="149" seed_test_files="0" tests="8" reached="840" script_gates_unmodelled="574" root="." graph_ambiguous="6085" graph_unresolved="3093" counts_floor="1">
<test p="test/cloneband_harness.cpp" run="bash test/clonebandcheck.sh"/>
<test p="test/clonelex_harness.cpp" run="bash test/clonelexcheck.sh"/>
<test p="test/columnarcommafix/columnar_comma_test.cpp" run="bash test/columnarcommacheck.sh"/>
<test p="test/connectcore_harness.cpp" run="bash test/connectcorecheck.sh"/>
<test p="test/includeprecise_unit.cpp" run="bash test/includeprecisecheck.sh"/>
<test p="test/rustimport_unit.cpp" run="bash test/rustimportprecisecheck.sh"/>
<test p="test/type3clone_harness.cpp" run="bash test/type3clonecheck.sh"/>
<test p="test/verify_csr.cpp" run="bash test/a9disclosurecheck.sh"/>
</affected>
`````

## `./build/ripwire . --situ`

*Mid-task situational report for the current git diff — recorded against a CLEAN tree (contrast with the sandbox run below).*

`````
ripwire situational-awareness — 0 changed file(s), 0 symbols in them
root: .
at: c7725f3ef
  (0 changed files — working tree is clean, nothing to analyze)
`````

## `./build/ripwire . --test-gate`

*Pre-PR gate on a CLEAN tree: no obligations, exit 0.*

`````
<!-- ripwire test-gate (TDAD-parity, arXiv 2603.17973, -70% agent-caused regressions): tests to run for this change + the UNTESTED blast radius; exit 4 if tests OR untested is non-empty, else run them and rely on green. shown_tests=/shown_untested= are TWO INDEPENDENT row counts: the <t> tests-to-run rows and the <u> blast-radius rows. script_gates_unmodelled= is the legacy test/*.sh corpus path count; script_gates_registered= counts suite members; script_gates_mapped= those with exact dependency evidence; script_gates_unresolved_dynamic= is the registered remainder, disclosed rather than guessed. Shell <t> rows join tests= only via evidence=script_literal (script text contains the changed path) or evidence=manifest_declared (RIPWIRE_TEST_DEPS metadata). counts_floor=1 keeps these static evidence counts honest about shell expansion and generated paths they cannot resolve; graph_ambiguous=/graph_unresolved= are the map header's ambiguous=/unresolved= (the resolver gauge: calls split over several defs / calls whose in-repo defs were all language-filtered). next= is the one pasteable follow-up: the first <t> row's run= (a shell line), else a ripwire invocation. ccx_bar= is the cognitive-complexity bar a <u> row's ccx= is read against (quality-delta's own). UNIT: untested= here counts impacted SYMBOLS. The seams verb spells untested= over cross-directory call EDGES and the flip verb over the defs a gate lights — three different things, never compared or summed across verbs. -->
<test-gate changed="0" impacted="0" tests="0" untested="0" shown_tests="0" tests_capped="0" shown_untested="0" untested_capped="0" script_gates_unmodelled="574" script_gates_registered="555" script_gates_mapped="128" script_gates_unresolved_dynamic="427" ccx_bar="15" graph_ambiguous="6085" graph_unr … [line truncated: 61 more bytes on this line]
</test-gate>
`````

## `./build/ripwire . --grep=DEGRADED_PATH_ALERT`

*Literal trigram-indexed search. Each hit carries its MATCHED line as the <hit> element's own CDATA (the <m> wrapper is gone), plus shown/capped/hits_capped and a pasteable next= on the root.*

`````
<!-- ripwire grep: parallel literal/regex scan; hits GROUP by file under <f p="…">, each <hit> carrying its LINE (l=), its matched text as the hit's own CDATA and enclosing symbol (in=, a NAME here; the same spelling is a fan-in COUNT in for/pack-task/exemplar; ABSENT (never an empty in= value) when no symbol encloses the hit, which is NOT the same claim as file scope — and on a file row carrying parse_degraded="1" it is NO CLAIM AT ALL: that file's parse holds ERROR/MISSING nodes (the skipped verb itemizes err=/err_ratio=), symbols there may be unextracted, so read in= absence inside it as UNKNOWN, not as file scope; absence of parse_degraded= on a row means the parse was clean, except that a file the ingest never parsed at all — doc-format, binary-sniffed, unreadable — is also unmarked, the skipped verb's unmeasured class). root= on the root element is the crawl root every <f p=…> is now RELATIVE to (single-root runs only; absent ⇒ p= is the path ingest itself used, unchanged). ORDER: SOURCE files before test/bench files before docs, then path and line. shown=/capped= = rows printed vs found (a count of underlying HITS, the same unit hits= uses, not of printed <hit> elements); hits_capped="1" ⇒ hits= is a FLOOR (collection budget reached) and the root then also carries counts_floor="1" and capped="1" — rows exist that no page holds. SPAN TIERS: each hit is classified by the tree-sitter span it sits in (code/comment/string) and this answer serves the CODE tier, or — when no hit is code — comment and string TOGETHER; tier= names what was served when it is not code, so a pattern living only in prose is answered, never emptied. tier_partial= (value 1, present only then) qualifies that label: it was elected over the CLASSIFIED hits ALONE while tier_unclassified= hits were never classified, so read it as the tightest tier PROVEN present, never as proof that no hit is code. Nothing past the budget is suppressed, so the partiality narrows what the LABEL may be read to mean, never which rows you got; its absence beside a tier= means the label is a fact. suppressed_comment=/suppressed_string= are the classified hits held back: not in hits=, and the reason complete= cannot appear. Pass grep-in=any (dashes omitted) for every tier. Hit files are parsed on demand under a fixed budget: tier_parsed= how many were classified, tier_budget= which ceiling stopped it (files or bytes, present only then — and the root then also carries counts_floor="1": the tier counts are floors while hits= stays exact and every row is served), tier_unclassified= hits in files nothing classified — always EMITTED, never suppressed. A byte-identical match at OTHER sites in the SAME file folds into the first <hit>'s n= (default 1, unset) and an at-tagged sibling element (l=/in=, self-closing) per extra site — never on a paged or grep-context/-before/-after answer (dashes omitted, illegal in an XML comment), where every site keeps its own <hit>. After the hit rows, <enc> rows list each DISTINCT enclosing symbol NAME of THIS page (first-appearance order, bounded by the page) with callers= its 1-hop DISTINCT-caller count, unioned across same-named defs like the callers verb (a FLOOR — dynamic dispatch contributes no edge), defs= how many defs the name grouped (only when more than one), cx= complexity; amp=/tested= join only when a metrics co-run already computed that lens. On a zero-hit answer a <suggest> element may follow: SUGGESTIONS, never matches — near= the nearest indexed symbol name (did-you-mean), next= a ready-to-paste conceptual fallback; absent for regex/non-word-like patterns or when nothing plausible exists. COMPLETENESS: complete= on the root (value 1) means this listing is EXHAUSTIVE and a consumer need not re-derive it: a LITERAL scan read every indexed file end to end, hit no collection ceiling, and printed every hit it found — so on this answer a zero really is zero and a hit absent above is absent from every indexed file. The claim is complete-within-the-index ONLY: most files the ingest skipped were never scanned (the skipped verb lists exactly which, with reasons; the ONE exception is the unindexed_files_scanned= class right below, itself never covered by complete=), and files outside the indexed roots are outside the claim. It never appears on a regex answer (the prefilter is a performance switch that may not change the answer, so neither mode claims), a capped or paged listing, or a scan that could not read a file; its ABSENCE claims nothing. The enc rows' caller counts stay FLOORS regardless — complete= speaks for the hit rows alone. unindexed_files_scanned= counts files outside the index (unsupported-ext, but text-looking — the skipped verb's own unsupported-ext class) that THIS answer additionally scanned for the same pattern; their hits print inside a trailing unindexed element (present only when it found something), holding its own <f> rows in the same shape as above, and never carry in= — there is no symbol table to check for such a file, which is not the same claim as file scope. THE TWO POPULATIONS: every count above — files, hits, shown, capped, total, complete — is the IN-INDEX search ALONE. unindexed_hits= sizes the second one, always stated (a zero included); the trailing unindexed element carries that same number as its own count= beside shown=/capped= and obeys the SAME window limit/offset set here (dashes omitted), so a one-row page is one row on BOTH lists and a page past its end is empty, not repeated. unindexed_files_skipped= (present only when nonzero) counts candidates this scan saw but did not read: over the max-file-size ceiling, sniffed binary, or unreadable. unindexed_candidates_capped="1" (present only when true) means the CANDIDATE list itself (the skipped verb's own 500-row-per-class cap) was already a floor, so files past it were never considered here either — see the skipped verb for every row. corpus_excluded= counts files an exclude filter (or built-in crawl policy) kept OUT of the index entirely; corpus_oversize= counts files the crawl SAW but dropped for exceeding the size ceiling. Both answer what an otherwise-empty answer alone cannot: not in this repo, or in a file that was never scanned — the skipped verb itemizes the rows behind either count. next= is the one pasteable follow-up: the at verb on the top hit; the next page (compact legend) when cut; the conceptual lens on a zero-hit answer. raise the default cap with limit=N (offset=M pages; a cut listing carries total=/has_more=/next_offset= so a paging loop can continue from it); on the root, limit="0" means no explicit limit was given and the verb's own default page size shaped the window — never a zero-row page -->
<grep pattern="DEGRADED_PATH_ALERT" root="." files="66" hits="231" shown="100" capped="1" total="231" has_more="1" next_offset="100" offset="0" limit="0" hits_capped="0" suppressed_comment="101" suppressed_string="33" tier_parsed="95" corpus_oversize="15" unindexed_hits="29" unindexed_files_scanned= … [line truncated: 98 more bytes on this line]
<f p="src/abicheck.h" parse_degraded="1">
<hit l="482" in="abicheck::collectAuthoredSites">
<![CDATA[            DEGRADED_PATH_ALERT( "abi: no merge-base for a ref (unrelated history?) — that ref is counted, not compared" );]]>
</hit>
</f>
<f p="src/arch.h">
<hit l="353" in="rw::parseArchRules">
<![CDATA[        DEGRADED_PATH_ALERT( "arch: malformed rules line — rules file rejected" );]]>
</hit>
<hit l="408" in="rw::parseArchRules">
<![CDATA[                catch( const std::regex_error& ) { pr.bad = true; DEGRADED_PATH_ALERT( "arch: malformed FROM path-regex — rule skipped" ); }]]>
</hit>
</f>
<f p="src/atoms.h">
<hit l="365" in="atomdetail::collectExclusions">
<![CDATA[        DEGRADED_PATH_ALERT( "atoms: an exclusion capture stream spent its whole budget; the rules reading it are suppressed this run" );]]>
</hit>
</f>
<f p="src/clones.h">
<hit l="816" in="rw::findClonesType3">
<![CDATA[                if( comparedPairs >= kType3MaxPairs ) { DEGRADED_PATH_ALERT( "clones: Type-3 pair cap hit — first N compared (both-gate-surviving) near-misses kept, rest skipped" ); goto done; }]]>
</hit>
</f>
<f p="src/commentcoherence.h" parse_degraded="1">
<hit l="204" in="rw::computeCommentCoherence">
<![CDATA[                DEGRADED_PATH_ALERT( "comment-coherence: an indexed file could not be read — its functions are absent from the report" );]]>
</hit>
</f>
… [511 more display lines; full output is 32972 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --grep=DEGRADED_PATH_ALERT --grep-context=1`

*Same search with one line of source context either side.*

`````
<!-- ripwire grep: parallel literal/regex scan; hits GROUP by file under <f p="…">, each <hit> carrying its LINE (l=), its matched text as the hit's own CDATA and enclosing symbol (in=, a NAME here; the same spelling is a fan-in COUNT in for/pack-task/exemplar; ABSENT (never an empty in= value) when no symbol encloses the hit, which is NOT the same claim as file scope — and on a file row carrying parse_degraded="1" it is NO CLAIM AT ALL: that file's parse holds ERROR/MISSING nodes (the skipped verb itemizes err=/err_ratio=), symbols there may be unextracted, so read in= absence inside it as UNKNOWN, not as file scope; absence of parse_degraded= on a row means the parse was clean, except that a file the ingest never parsed at all — doc-format, binary-sniffed, unreadable — is also unmarked, the skipped verb's unmeasured class). root= on the root element is the crawl root every <f p=…> is now RELATIVE to (single-root runs only; absent ⇒ p= is the path ingest itself used, unchanged). ORDER: SOURCE files before test/bench files before docs, then path and line. shown=/capped= = rows printed vs found (a count of underlying HITS, the same unit hits= uses, not of printed <hit> elements); hits_capped="1" ⇒ hits= is a FLOOR (collection budget reached) and the root then also carries counts_floor="1" and capped="1" — rows exist that no page holds. SPAN TIERS: each hit is classified by the tree-sitter span it sits in (code/comment/string) and this answer serves the CODE tier, or — when no hit is code — comment and string TOGETHER; tier= names what was served when it is not code, so a pattern living only in prose is answered, never emptied. tier_partial= (value 1, present only then) qualifies that label: it was elected over the CLASSIFIED hits ALONE while tier_unclassified= hits were never classified, so read it as the tightest tier PROVEN present, never as proof that no hit is code. Nothing past the budget is suppressed, so the partiality narrows what the LABEL may be read to mean, never which rows you got; its absence beside a tier= means the label is a fact. suppressed_comment=/suppressed_string= are the classified hits held back: not in hits=, and the reason complete= cannot appear. Pass grep-in=any (dashes omitted) for every tier. Hit files are parsed on demand under a fixed budget: tier_parsed= how many were classified, tier_budget= which ceiling stopped it (files or bytes, present only then — and the root then also carries counts_floor="1": the tier counts are floors while hits= stays exact and every row is served), tier_unclassified= hits in files nothing classified — always EMITTED, never suppressed. A byte-identical match at OTHER sites in the SAME file folds into the first <hit>'s n= (default 1, unset) and an at-tagged sibling element (l=/in=, self-closing) per extra site — never on a paged or grep-context/-before/-after answer (dashes omitted, illegal in an XML comment), where every site keeps its own <hit>. After the hit rows, <enc> rows list each DISTINCT enclosing symbol NAME of THIS page (first-appearance order, bounded by the page) with callers= its 1-hop DISTINCT-caller count, unioned across same-named defs like the callers verb (a FLOOR — dynamic dispatch contributes no edge), defs= how many defs the name grouped (only when more than one), cx= complexity; amp=/tested= join only when a metrics co-run already computed that lens. On a zero-hit answer a <suggest> element may follow: SUGGESTIONS, never matches — near= the nearest indexed symbol name (did-you-mean), next= a ready-to-paste conceptual fallback; absent for regex/non-word-like patterns or when nothing plausible exists. COMPLETENESS: complete= on the root (value 1) means this listing is EXHAUSTIVE and a consumer need not re-derive it: a LITERAL scan read every indexed file end to end, hit no collection ceiling, and printed every hit it found — so on this answer a zero really is zero and a hit absent above is absent from every indexed file. The claim is complete-within-the-index ONLY: most files the ingest skipped were never scanned (the skipped verb lists exactly which, with reasons; the ONE exception is the unindexed_files_scanned= class right below, itself never covered by complete=), and files outside the indexed roots are outside the claim. It never appears on a regex answer (the prefilter is a performance switch that may not change the answer, so neither mode claims), a capped or paged listing, or a scan that could not read a file; its ABSENCE claims nothing. The enc rows' caller counts stay FLOORS regardless — complete= speaks for the hit rows alone. unindexed_files_scanned= counts files outside the index (unsupported-ext, but text-looking — the skipped verb's own unsupported-ext class) that THIS answer additionally scanned for the same pattern; their hits print inside a trailing unindexed element (present only when it found something), holding its own <f> rows in the same shape as above, and never carry in= — there is no symbol table to check for such a file, which is not the same claim as file scope. THE TWO POPULATIONS: every count above — files, hits, shown, capped, total, complete — is the IN-INDEX search ALONE. unindexed_hits= sizes the second one, always stated (a zero included); the trailing unindexed element carries that same number as its own count= beside shown=/capped= and obeys the SAME window limit/offset set here (dashes omitted), so a one-row page is one row on BOTH lists and a page past its end is empty, not repeated. unindexed_files_skipped= (present only when nonzero) counts candidates this scan saw but did not read: over the max-file-size ceiling, sniffed binary, or unreadable. unindexed_candidates_capped="1" (present only when true) means the CANDIDATE list itself (the skipped verb's own 500-row-per-class cap) was already a floor, so files past it were never considered here either — see the skipped verb for every row. corpus_excluded= counts files an exclude filter (or built-in crawl policy) kept OUT of the index entirely; corpus_oversize= counts files the crawl SAW but dropped for exceeding the size ceiling. Both answer what an otherwise-empty answer alone cannot: not in this repo, or in a file that was never scanned — the skipped verb itemizes the rows behind either count. next= is the one pasteable follow-up: the at verb on the top hit; the next page (compact legend) when cut; the conceptual lens on a zero-hit answer. raise the default cap with limit=N (offset=M pages; a cut listing carries total=/has_more=/next_offset= so a paging loop can continue from it); on the root, limit="0" means no explicit limit was given and the verb's own default page size shaped the window — never a zero-row page -->
<grep pattern="DEGRADED_PATH_ALERT" root="." files="66" hits="231" shown="100" capped="1" total="231" has_more="1" next_offset="100" offset="0" limit="0" hits_capped="0" suppressed_comment="101" suppressed_string="33" tier_parsed="95" corpus_oversize="15" unindexed_hits="29" unindexed_files_scanned= … [line truncated: 98 more bytes on this line]
<f p="src/abicheck.h" parse_degraded="1">
<hit l="482" in="abicheck::collectAuthoredSites">
<b>
<![CDATA[        {]]>
</b>
<![CDATA[            DEGRADED_PATH_ALERT( "abi: no merge-base for a ref (unrelated history?) — that ref is counted, not compared" );]]>
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
<![CDATA[        DEGRADED_PATH_ALERT( "arch: malformed rules line — rules file rejected" );]]>
<a>
<![CDATA[        return false;]]>
</a>
</hit>
<hit l="408" in="rw::parseArchRules">
<b>
<![CDATA[                try { pr.fromRe = std::regex( fromRe, std::regex::ECMAScript ); }]]>
</b>
<![CDATA[                catch( const std::regex_error& ) { pr.bad = true; DEGRADED_PATH_ALERT( "arch: malformed FROM path-regex — rule skipped" ); }]]>
<a>
<![CDATA[                r.pathRules.push_back( std::move( pr ) );]]>
… [1099 more display lines; full output is 42174 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --grep=DEGRADED_PATH_ALERT --grep-before=1 --grep-after=2 --limit=3`

*The asymmetric spelling of the same context: one line before and two after each hit (ripgrep's -B/-A), on a three-hit window.*

`````
<!-- ripwire grep: parallel literal/regex scan; hits GROUP by file under <f p="…">, each <hit> carrying its LINE (l=), its matched text as the hit's own CDATA and enclosing symbol (in=, a NAME here; the same spelling is a fan-in COUNT in for/pack-task/exemplar; ABSENT (never an empty in= value) when no symbol encloses the hit, which is NOT the same claim as file scope — and on a file row carrying parse_degraded="1" it is NO CLAIM AT ALL: that file's parse holds ERROR/MISSING nodes (the skipped verb itemizes err=/err_ratio=), symbols there may be unextracted, so read in= absence inside it as UNKNOWN, not as file scope; absence of parse_degraded= on a row means the parse was clean, except that a file the ingest never parsed at all — doc-format, binary-sniffed, unreadable — is also unmarked, the skipped verb's unmeasured class). root= on the root element is the crawl root every <f p=…> is now RELATIVE to (single-root runs only; absent ⇒ p= is the path ingest itself used, unchanged). ORDER: SOURCE files before test/bench files before docs, then path and line. shown=/capped= = rows printed vs found (a count of underlying HITS, the same unit hits= uses, not of printed <hit> elements); hits_capped="1" ⇒ hits= is a FLOOR (collection budget reached) and the root then also carries counts_floor="1" and capped="1" — rows exist that no page holds. SPAN TIERS: each hit is classified by the tree-sitter span it sits in (code/comment/string) and this answer serves the CODE tier, or — when no hit is code — comment and string TOGETHER; tier= names what was served when it is not code, so a pattern living only in prose is answered, never emptied. tier_partial= (value 1, present only then) qualifies that label: it was elected over the CLASSIFIED hits ALONE while tier_unclassified= hits were never classified, so read it as the tightest tier PROVEN present, never as proof that no hit is code. Nothing past the budget is suppressed, so the partiality narrows what the LABEL may be read to mean, never which rows you got; its absence beside a tier= means the label is a fact. suppressed_comment=/suppressed_string= are the classified hits held back: not in hits=, and the reason complete= cannot appear. Pass grep-in=any (dashes omitted) for every tier. Hit files are parsed on demand under a fixed budget: tier_parsed= how many were classified, tier_budget= which ceiling stopped it (files or bytes, present only then — and the root then also carries counts_floor="1": the tier counts are floors while hits= stays exact and every row is served), tier_unclassified= hits in files nothing classified — always EMITTED, never suppressed. A byte-identical match at OTHER sites in the SAME file folds into the first <hit>'s n= (default 1, unset) and an at-tagged sibling element (l=/in=, self-closing) per extra site — never on a paged or grep-context/-before/-after answer (dashes omitted, illegal in an XML comment), where every site keeps its own <hit>. After the hit rows, <enc> rows list each DISTINCT enclosing symbol NAME of THIS page (first-appearance order, bounded by the page) with callers= its 1-hop DISTINCT-caller count, unioned across same-named defs like the callers verb (a FLOOR — dynamic dispatch contributes no edge), defs= how many defs the name grouped (only when more than one), cx= complexity; amp=/tested= join only when a metrics co-run already computed that lens. On a zero-hit answer a <suggest> element may follow: SUGGESTIONS, never matches — near= the nearest indexed symbol name (did-you-mean), next= a ready-to-paste conceptual fallback; absent for regex/non-word-like patterns or when nothing plausible exists. COMPLETENESS: complete= on the root (value 1) means this listing is EXHAUSTIVE and a consumer need not re-derive it: a LITERAL scan read every indexed file end to end, hit no collection ceiling, and printed every hit it found — so on this answer a zero really is zero and a hit absent above is absent from every indexed file. The claim is complete-within-the-index ONLY: most files the ingest skipped were never scanned (the skipped verb lists exactly which, with reasons; the ONE exception is the unindexed_files_scanned= class right below, itself never covered by complete=), and files outside the indexed roots are outside the claim. It never appears on a regex answer (the prefilter is a performance switch that may not change the answer, so neither mode claims), a capped or paged listing, or a scan that could not read a file; its ABSENCE claims nothing. The enc rows' caller counts stay FLOORS regardless — complete= speaks for the hit rows alone. unindexed_files_scanned= counts files outside the index (unsupported-ext, but text-looking — the skipped verb's own unsupported-ext class) that THIS answer additionally scanned for the same pattern; their hits print inside a trailing unindexed element (present only when it found something), holding its own <f> rows in the same shape as above, and never carry in= — there is no symbol table to check for such a file, which is not the same claim as file scope. THE TWO POPULATIONS: every count above — files, hits, shown, capped, total, complete — is the IN-INDEX search ALONE. unindexed_hits= sizes the second one, always stated (a zero included); the trailing unindexed element carries that same number as its own count= beside shown=/capped= and obeys the SAME window limit/offset set here (dashes omitted), so a one-row page is one row on BOTH lists and a page past its end is empty, not repeated. unindexed_files_skipped= (present only when nonzero) counts candidates this scan saw but did not read: over the max-file-size ceiling, sniffed binary, or unreadable. unindexed_candidates_capped="1" (present only when true) means the CANDIDATE list itself (the skipped verb's own 500-row-per-class cap) was already a floor, so files past it were never considered here either — see the skipped verb for every row. corpus_excluded= counts files an exclude filter (or built-in crawl policy) kept OUT of the index entirely; corpus_oversize= counts files the crawl SAW but dropped for exceeding the size ceiling. Both answer what an otherwise-empty answer alone cannot: not in this repo, or in a file that was never scanned — the skipped verb itemizes the rows behind either count. next= is the one pasteable follow-up: the at verb on the top hit; the next page (compact legend) when cut; the conceptual lens on a zero-hit answer. raise the default cap with limit=N (offset=M pages; a cut listing carries total=/has_more=/next_offset= so a paging loop can continue from it); on the root, limit="0" means no explicit limit was given and the verb's own default page size shaped the window — never a zero-row page -->
<grep pattern="DEGRADED_PATH_ALERT" root="." files="66" hits="231" shown="3" capped="1" total="231" has_more="1" next_offset="3" offset="0" limit="3" hits_capped="0" suppressed_comment="101" suppressed_string="33" tier_parsed="95" corpus_oversize="15" unindexed_hits="29" unindexed_files_scanned="168 … [line truncated: 92 more bytes on this line]
<f p="src/abicheck.h" parse_degraded="1">
<hit l="482" in="abicheck::collectAuthoredSites">
<b>
<![CDATA[        {]]>
</b>
<![CDATA[            DEGRADED_PATH_ALERT( "abi: no merge-base for a ref (unrelated history?) — that ref is counted, not compared" );]]>
<a>
<![CDATA[            ++result.unrelated;
            continue;]]></a></hit></f><f p="src/arch.h"><hit l="353" in="rw::parseArchRules"><b><![CDATA[        std::fprintf( stderr, "ripwire: --arch: %s:%zu: %s — rules file rejected\n", path.c_str(), lineNo, why );]]></b><![CDATA[        DEGRADED_PATH_ALERT( "arch: malformed rules line — rul … [line truncated: 56 more bytes on this line]
    };]]></a></hit><hit l="408" in="rw::parseArchRules"><b><![CDATA[                try { pr.fromRe = std::regex( fromRe, std::regex::ECMAScript ); }]]></b><![CDATA[                catch( const std::regex_error& ) { pr.bad = true; DEGRADED_PATH_ALERT( "arch: malformed FROM path-regex — rule skippe … [line truncated: 79 more bytes on this line]
            }]]></a></hit></f><unindexed count="29" shown="3" capped="1"><f p="CMakeLists.txt"><hit l="97"><![CDATA[# VERIFY and DEGRADED_PATH_ALERT live, which is the only configuration that can catch an]]></hit><hit l="285"><![CDATA[# -DCMAKE_BUILD_TYPE=Release" locally — Release defines NDEBUG, … [line truncated: 315 more bytes on this line]
`````

## `./build/ripwire . --regex='fnv1a\w+'`

*Regex search + enclosing symbol.*

`````
<!-- ripwire grep: parallel literal/regex scan; hits GROUP by file under <f p="…">, each <hit> carrying its LINE (l=), its matched text as the hit's own CDATA and enclosing symbol (in=, a NAME here; the same spelling is a fan-in COUNT in for/pack-task/exemplar; ABSENT (never an empty in= value) when no symbol encloses the hit, which is NOT the same claim as file scope — and on a file row carrying parse_degraded="1" it is NO CLAIM AT ALL: that file's parse holds ERROR/MISSING nodes (the skipped verb itemizes err=/err_ratio=), symbols there may be unextracted, so read in= absence inside it as UNKNOWN, not as file scope; absence of parse_degraded= on a row means the parse was clean, except that a file the ingest never parsed at all — doc-format, binary-sniffed, unreadable — is also unmarked, the skipped verb's unmeasured class). root= on the root element is the crawl root every <f p=…> is now RELATIVE to (single-root runs only; absent ⇒ p= is the path ingest itself used, unchanged). ORDER: SOURCE files before test/bench files before docs, then path and line. shown=/capped= = rows printed vs found (a count of underlying HITS, the same unit hits= uses, not of printed <hit> elements); hits_capped="1" ⇒ hits= is a FLOOR (collection budget reached) and the root then also carries counts_floor="1" and capped="1" — rows exist that no page holds. SPAN TIERS: each hit is classified by the tree-sitter span it sits in (code/comment/string) and this answer serves the CODE tier, or — when no hit is code — comment and string TOGETHER; tier= names what was served when it is not code, so a pattern living only in prose is answered, never emptied. tier_partial= (value 1, present only then) qualifies that label: it was elected over the CLASSIFIED hits ALONE while tier_unclassified= hits were never classified, so read it as the tightest tier PROVEN present, never as proof that no hit is code. Nothing past the budget is suppressed, so the partiality narrows what the LABEL may be read to mean, never which rows you got; its absence beside a tier= means the label is a fact. suppressed_comment=/suppressed_string= are the classified hits held back: not in hits=, and the reason complete= cannot appear. Pass grep-in=any (dashes omitted) for every tier. Hit files are parsed on demand under a fixed budget: tier_parsed= how many were classified, tier_budget= which ceiling stopped it (files or bytes, present only then — and the root then also carries counts_floor="1": the tier counts are floors while hits= stays exact and every row is served), tier_unclassified= hits in files nothing classified — always EMITTED, never suppressed. A byte-identical match at OTHER sites in the SAME file folds into the first <hit>'s n= (default 1, unset) and an at-tagged sibling element (l=/in=, self-closing) per extra site — never on a paged or grep-context/-before/-after answer (dashes omitted, illegal in an XML comment), where every site keeps its own <hit>. After the hit rows, <enc> rows list each DISTINCT enclosing symbol NAME of THIS page (first-appearance order, bounded by the page) with callers= its 1-hop DISTINCT-caller count, unioned across same-named defs like the callers verb (a FLOOR — dynamic dispatch contributes no edge), defs= how many defs the name grouped (only when more than one), cx= complexity; amp=/tested= join only when a metrics co-run already computed that lens. On a zero-hit answer a <suggest> element may follow: SUGGESTIONS, never matches — near= the nearest indexed symbol name (did-you-mean), next= a ready-to-paste conceptual fallback; absent for regex/non-word-like patterns or when nothing plausible exists. COMPLETENESS: complete= on the root (value 1) means this listing is EXHAUSTIVE and a consumer need not re-derive it: a LITERAL scan read every indexed file end to end, hit no collection ceiling, and printed every hit it found — so on this answer a zero really is zero and a hit absent above is absent from every indexed file. The claim is complete-within-the-index ONLY: most files the ingest skipped were never scanned (the skipped verb lists exactly which, with reasons; the ONE exception is the unindexed_files_scanned= class right below, itself never covered by complete=), and files outside the indexed roots are outside the claim. It never appears on a regex answer (the prefilter is a performance switch that may not change the answer, so neither mode claims), a capped or paged listing, or a scan that could not read a file; its ABSENCE claims nothing. The enc rows' caller counts stay FLOORS regardless — complete= speaks for the hit rows alone. unindexed_files_scanned= counts files outside the index (unsupported-ext, but text-looking — the skipped verb's own unsupported-ext class) that THIS answer additionally scanned for the same pattern; their hits print inside a trailing unindexed element (present only when it found something), holding its own <f> rows in the same shape as above, and never carry in= — there is no symbol table to check for such a file, which is not the same claim as file scope. THE TWO POPULATIONS: every count above — files, hits, shown, capped, total, complete — is the IN-INDEX search ALONE. unindexed_hits= sizes the second one, always stated (a zero included); the trailing unindexed element carries that same number as its own count= beside shown=/capped= and obeys the SAME window limit/offset set here (dashes omitted), so a one-row page is one row on BOTH lists and a page past its end is empty, not repeated. unindexed_files_skipped= (present only when nonzero) counts candidates this scan saw but did not read: over the max-file-size ceiling, sniffed binary, or unreadable. unindexed_candidates_capped="1" (present only when true) means the CANDIDATE list itself (the skipped verb's own 500-row-per-class cap) was already a floor, so files past it were never considered here either — see the skipped verb for every row. corpus_excluded= counts files an exclude filter (or built-in crawl policy) kept OUT of the index entirely; corpus_oversize= counts files the crawl SAW but dropped for exceeding the size ceiling. Both answer what an otherwise-empty answer alone cannot: not in this repo, or in a file that was never scanned — the skipped verb itemizes the rows behind either count. next= is the one pasteable follow-up: the at verb on the top hit; the next page (compact legend) when cut; the conceptual lens on a zero-hit answer. raise the default cap with limit=N (offset=M pages; a cut listing carries total=/has_more=/next_offset= so a paging loop can continue from it); on the root, limit="0" means no explicit limit was given and the verb's own default page size shaped the window — never a zero-row page -->
<grep pattern="fnv1a\w+" root="." files="19" hits="77" shown="77" capped="0" hits_capped="0" suppressed_comment="49" suppressed_string="10" tier_parsed="32" corpus_oversize="15" unindexed_hits="23" unindexed_files_scanned="168" unindexed_files_skipped="1" next="--at=src/arch.h:507">
<f p="src/arch.h">
<hit l="507" in="rw::fnv1a64">
<![CDATA[inline std::uint64_t fnv1a64( std::string_view s ) noexcept]]>
</hit>
<hit l="512" in="rw::fnv1a64">
<![CDATA[        h = hashutil::fnv1aAbsorb( h, c );]]>
</hit>
<hit l="620" in="rw::archViolHash">
<![CDATA[            h = hashutil::fnv1aAbsorb( h, c );]]>
</hit>
<hit l="623" in="rw::archViolHash">
<![CDATA[        h = hashutil::fnv1aMultiply( h ); // NUL separator byte]]>
</hit>
</f>
<f p="src/cloneidiom.h">
<hit l="606" in="rw::classifyCloneGroupIdioms">
<![CDATA[                ids.push_back( fnv1a64( t.text ) );]]>
</hit>
</f>
<f p="src/clones.h">
<hit l="582" in="rw::cloneTokenHash">
<![CDATA[        h = hashutil::fnv1aAbsorb( h, c );]]>
</hit>
<hit l="584" in="rw::cloneTokenHash">
<![CDATA[    h ^= 0x9e3779b97f4a7c15ull;  h = hashutil::fnv1aMultiply( h );   // token separator so [ab][c] != [a][bc]]]>
</hit>
<hit l="689" in="rw::findClonesType3">
<![CDATA[                    sh = hashutil::fnv1aAbsorb( sh, c );]]>
… [373 more display lines; full output is 23364 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --match='(if_statement)'`

*Tree-sitter structural query WITHOUT a capture — a bare node query gets a capture AUTO-ADDED (auto_captured="1") and matches the same nodes the explicit form does.*

`````
<!-- ripwire match: tree-sitter structural query; each hit = a captured node + its enclosing symbol. shown=/capped= = rows printed vs found; hits_capped="1" ⇒ hits= is a FLOOR (engine match limit reached) and the root then also carries counts_floor="1" and capped="1" — rows exist that NO page holds (the engine cap, not the window, dropped them; narrow the query), while has_more= keeps its window meaning so a loop still terminates. auto_captured="1" ⇒ the query bound no @capture and ripwire appended `@m` to its single top-level pattern. grammars= names every grammar the query compiled against; eligible_files=/of_files= are corpus files in that language set vs total indexed files. raise the default cap with limit=N (offset=M pages; a cut listing carries total=/has_more=/next_offset= so a paging loop can continue from it) -->
<match hits="5000" shown="100" capped="1" total="5000" has_more="1" next_offset="100" offset="0" limit="0" counts_floor="1" hits_capped="1" auto_captured="1" grammars="cpp,c,python,go,typescript,swift,objc,javascript,bash,java,csharp,php,lua" eligible_files="1332" of_files="1588" root=".">
<m p="bench/agentloop/analyze.py:37" in="load_results">if data.get( "schema" ) != SCHEMA:         raise SystemExit( f"{path}: unexpected schema {data.get('schema')!r} (expecte</m>
<m p="bench/agentloop/analyze.py:48" in="load_results">if not str( data.get( "tasks_lock_content_sha256", "" ) ).startswith( "questions:" ):         train_repos = select_tasks</m>
<m p="bench/agentloop/analyze.py:50" in="load_results">if train_repos:             raise SystemExit(                 f"{path}: records from repo(s) that re-derive to LocBench </m>
<m p="bench/agentloop/analyze.py:72" in="pair_by_task_seed">if base and ctx and base["status"] == "ok" and ctx["status"] == "ok":             paired.append( ( instance_id, base["re</m>
<m p="bench/agentloop/analyze.py:101" in="clustered_bootstrap_lower">if not repos: return 0.0, []</m>
<m p="bench/agentloop/analyze.py:117" in="loc_hit_delta">if base["localization_hit"] is None or ctx["localization_hit"] is None: return 0.0</m>
<m p="bench/agentloop/analyze.py:126" in="paired_ratio">if bv: ratios.append( cv / bv - 1 )</m>
<m p="bench/agentloop/analyze.py:127" in="paired_ratio">if not ratios: return None, None</m>
<m p="bench/agentloop/analyze.py:146" in="substitution_rate">if rw is None or native is None:         return None</m>
<m p="bench/agentloop/analyze.py:169" in="analyze">if not paired:         out["note"] = "zero complete paired (baseline,ripwire_cli) runs — nothing to analyze yet"      </m>
<m p="bench/agentloop/analyze.py:206" in="print_report">if contaminated:         print( f"  ** {contaminated} baseline run(s) invoked ripwire despite the no-ripwire contract " </m>
<m p="bench/agentloop/analyze.py:210" in="print_report">if "note" in out:         print( f"  {out['note']}" ); return</m>
<m p="bench/agentloop/analyze.py:295" in="self_test">if out["n_pairs"] != 27: failures.append( f"expected 27 paired runs, got {out['n_pairs']}" )</m>
<m p="bench/agentloop/analyze.py:296" in="self_test">if out["n_incomplete"] != 2:         failures.append( f"expected 2 incomplete pairs (the orphan + the contaminated-basel</m>
<m p="bench/agentloop/analyze.py:299" in="self_test">if out["n_repos"] != 3: failures.append( f"expected 3 repos, got {out['n_repos']}" )</m>
<m p="bench/agentloop/analyze.py:300" in="self_test">if out.get( "n_contaminated_baseline" ) != 1:         failures.append( f"expected exactly 1 contaminated baseline run co</m>
<m p="bench/agentloop/analyze.py:303" in="self_test">if not ( out["resolved_delta_mean"] &gt; 0 ): failures.append( "expected a positive resolved-rate delta" )</m>
<m p="bench/agentloop/analyze.py:304" in="self_test">if not ( out["resolved_delta_bootstrap_95_lower"] &gt; 0 ):         failures.append( "expected a POSITIVE bootstrap 95% low</m>
<m p="bench/agentloop/analyze.py:306" in="self_test">if out["tokens_out_ratio_p50"] is None or abs( out["tokens_out_ratio_p50"] - 0.08 ) &gt; 1e-6:         failures.append( f"e</m>
<m p="bench/agentloop/analyze.py:309" in="self_test">if out.get( "n_resolved_pairs" ) != 27:         failures.append( f"expected all 27 pairs resolution-scored, got {out.get</m>
<m p="bench/agentloop/analyze.py:312" in="self_test">if out.get( "substitution_rate_baseline" ) != 0.0:         failures.append( f"expected baseline substitution rate 0.0 (n</m>
<m p="bench/agentloop/analyze.py:315" in="self_test">if out.get( "substitution_rate_ripwire" ) is None or abs( out["substitution_rate_ripwire"] - 0.75 ) &gt; 1e-9:         fail</m>
<m p="bench/agentloop/analyze.py:318" in="self_test">if out.get( "n_substitution_ripwire" ) != 27:         failures.append( f"expected 27 substitution-scored ripwire runs, g</m>
<m p="bench/agentloop/analyze.py:324" in="self_test">if out3.get( "substitution_rate_ripwire" ) is not None or out3.get( "n_substitution_ripwire" ) != 0:         failures.ap</m>
<m p="bench/agentloop/analyze.py:330" in="self_test">if out2["n_pairs"] != 27:         failures.append( f"evaluator-none: expected 27 pairs, got {out2['n_pairs']}" )</m>
<m p="bench/agentloop/analyze.py:332" in="self_test">if out2["n_resolved_pairs"] != 0:         failures.append( f"evaluator-none: expected 0 resolution-scored pairs, got {ou</m>
<m p="bench/agentloop/analyze.py:334" in="self_test">if out2["resolved_delta_mean"] is not None or out2["resolved_delta_bootstrap_95_lower"] is not None:         failures.ap</m>
<m p="bench/agentloop/analyze.py:336" in="self_test">if out2["tokens_out_ratio_p50"] is None or abs( out2["tokens_out_ratio_p50"] - 0.08 ) &gt; 1e-6:         failures.append( "</m>
… [73 more display lines; full output is 17166 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --match='(if_statement) @i'`

*The same shape query WITH an explicit capture — identical hits, no auto_captured= attribute.*

`````
<!-- ripwire match: tree-sitter structural query; each hit = a captured node + its enclosing symbol. shown=/capped= = rows printed vs found; hits_capped="1" ⇒ hits= is a FLOOR (engine match limit reached) and the root then also carries counts_floor="1" and capped="1" — rows exist that NO page holds (the engine cap, not the window, dropped them; narrow the query), while has_more= keeps its window meaning so a loop still terminates. auto_captured="1" ⇒ the query bound no @capture and ripwire appended `@m` to its single top-level pattern. grammars= names every grammar the query compiled against; eligible_files=/of_files= are corpus files in that language set vs total indexed files. raise the default cap with limit=N (offset=M pages; a cut listing carries total=/has_more=/next_offset= so a paging loop can continue from it) -->
<match hits="5000" shown="100" capped="1" total="5000" has_more="1" next_offset="100" offset="0" limit="0" counts_floor="1" hits_capped="1" grammars="cpp,c,python,go,typescript,swift,objc,javascript,bash,java,csharp,php,lua" eligible_files="1332" of_files="1588" root=".">
<m p="bench/agentloop/analyze.py:37" in="load_results">if data.get( "schema" ) != SCHEMA:         raise SystemExit( f"{path}: unexpected schema {data.get('schema')!r} (expecte</m>
<m p="bench/agentloop/analyze.py:48" in="load_results">if not str( data.get( "tasks_lock_content_sha256", "" ) ).startswith( "questions:" ):         train_repos = select_tasks</m>
<m p="bench/agentloop/analyze.py:50" in="load_results">if train_repos:             raise SystemExit(                 f"{path}: records from repo(s) that re-derive to LocBench </m>
<m p="bench/agentloop/analyze.py:72" in="pair_by_task_seed">if base and ctx and base["status"] == "ok" and ctx["status"] == "ok":             paired.append( ( instance_id, base["re</m>
<m p="bench/agentloop/analyze.py:101" in="clustered_bootstrap_lower">if not repos: return 0.0, []</m>
<m p="bench/agentloop/analyze.py:117" in="loc_hit_delta">if base["localization_hit"] is None or ctx["localization_hit"] is None: return 0.0</m>
<m p="bench/agentloop/analyze.py:126" in="paired_ratio">if bv: ratios.append( cv / bv - 1 )</m>
<m p="bench/agentloop/analyze.py:127" in="paired_ratio">if not ratios: return None, None</m>
<m p="bench/agentloop/analyze.py:146" in="substitution_rate">if rw is None or native is None:         return None</m>
<m p="bench/agentloop/analyze.py:169" in="analyze">if not paired:         out["note"] = "zero complete paired (baseline,ripwire_cli) runs — nothing to analyze yet"      </m>
<m p="bench/agentloop/analyze.py:206" in="print_report">if contaminated:         print( f"  ** {contaminated} baseline run(s) invoked ripwire despite the no-ripwire contract " </m>
<m p="bench/agentloop/analyze.py:210" in="print_report">if "note" in out:         print( f"  {out['note']}" ); return</m>
<m p="bench/agentloop/analyze.py:295" in="self_test">if out["n_pairs"] != 27: failures.append( f"expected 27 paired runs, got {out['n_pairs']}" )</m>
<m p="bench/agentloop/analyze.py:296" in="self_test">if out["n_incomplete"] != 2:         failures.append( f"expected 2 incomplete pairs (the orphan + the contaminated-basel</m>
<m p="bench/agentloop/analyze.py:299" in="self_test">if out["n_repos"] != 3: failures.append( f"expected 3 repos, got {out['n_repos']}" )</m>
<m p="bench/agentloop/analyze.py:300" in="self_test">if out.get( "n_contaminated_baseline" ) != 1:         failures.append( f"expected exactly 1 contaminated baseline run co</m>
<m p="bench/agentloop/analyze.py:303" in="self_test">if not ( out["resolved_delta_mean"] &gt; 0 ): failures.append( "expected a positive resolved-rate delta" )</m>
<m p="bench/agentloop/analyze.py:304" in="self_test">if not ( out["resolved_delta_bootstrap_95_lower"] &gt; 0 ):         failures.append( "expected a POSITIVE bootstrap 95% low</m>
<m p="bench/agentloop/analyze.py:306" in="self_test">if out["tokens_out_ratio_p50"] is None or abs( out["tokens_out_ratio_p50"] - 0.08 ) &gt; 1e-6:         failures.append( f"e</m>
<m p="bench/agentloop/analyze.py:309" in="self_test">if out.get( "n_resolved_pairs" ) != 27:         failures.append( f"expected all 27 pairs resolution-scored, got {out.get</m>
<m p="bench/agentloop/analyze.py:312" in="self_test">if out.get( "substitution_rate_baseline" ) != 0.0:         failures.append( f"expected baseline substitution rate 0.0 (n</m>
<m p="bench/agentloop/analyze.py:315" in="self_test">if out.get( "substitution_rate_ripwire" ) is None or abs( out["substitution_rate_ripwire"] - 0.75 ) &gt; 1e-9:         fail</m>
<m p="bench/agentloop/analyze.py:318" in="self_test">if out.get( "n_substitution_ripwire" ) != 27:         failures.append( f"expected 27 substitution-scored ripwire runs, g</m>
<m p="bench/agentloop/analyze.py:324" in="self_test">if out3.get( "substitution_rate_ripwire" ) is not None or out3.get( "n_substitution_ripwire" ) != 0:         failures.ap</m>
<m p="bench/agentloop/analyze.py:330" in="self_test">if out2["n_pairs"] != 27:         failures.append( f"evaluator-none: expected 27 pairs, got {out2['n_pairs']}" )</m>
<m p="bench/agentloop/analyze.py:332" in="self_test">if out2["n_resolved_pairs"] != 0:         failures.append( f"evaluator-none: expected 0 resolution-scored pairs, got {ou</m>
<m p="bench/agentloop/analyze.py:334" in="self_test">if out2["resolved_delta_mean"] is not None or out2["resolved_delta_bootstrap_95_lower"] is not None:         failures.ap</m>
<m p="bench/agentloop/analyze.py:336" in="self_test">if out2["tokens_out_ratio_p50"] is None or abs( out2["tokens_out_ratio_p50"] - 0.08 ) &gt; 1e-6:         failures.append( "</m>
… [73 more display lines; full output is 17148 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --query="teleport pagerank" --top-k=5`

*Raw BM25 ranking (debug lens; --for is the real verb).*

`````
<!-- routed: subtoken+body BM25 (-for's default) — no strong name hit; broad query, plain rg may also win -->
<!-- ripwire v1 t=fn|method|cls|struct|iface|var|sec|macro(#define;degraded:body-is-replacement-text,edges-cross-expansion) p=path layer=arch-layer(opt) n=name id=canonical(path::scope::name,when-scoped) k=rank c=call amb=ambiguous-calls(read-source) lpin=calls-pinned-by-locality-prior-alone(a-disclosed-guess;read-source;absent-if-0) overloads=N-same-name-defs-merged-into-this-row(absent-if-1;shown=counts-them-individually,so-rows+sum(overloads-1)=shown) prov=scip(precise;else name-based) hdr:unresolved=call-name-defined-only-in-a-lang-incompatible-file (edges heuristic) hdr:locality_pinned=sum-of-lpin(absent-if-0) hdr:external=calls-refused-as-bound-outside-the-tree(builtin/stdlib-name-without-in-repo-evidence,external-import,super-past-the-tree;no-edge;absent-if-0) r:est_tokens=hdr-copy(none-if-stable) -->
<!-- r:root=crawl-root-every-p=-is-relative-to(single-root-only;absent=>p=is-the-raw-ingest-path) -->
<!-- files=1588 symbols=13849 edges=17058 shown=5 est_tokens=914 ambiguous=6085 unresolved=3093 locality_pinned=6 external=788 precise=3 skipped_oversize=15 unindexed="txt:59,jsonl:26,tsv:21,scm:18,expected:15,lock:7" unindexed_exts=19 order=important-first -->
<r root="." est_tokens="914">
<f p="src/serialize.h">
<s t="var" n="kChurnRankLegend" id="src/serialize.h::rw::kChurnRankLegend" k="18.4659">
</s>
</f>
<f p="src/main.cpp">
<s t="fn" n="churnRankedGraph" amb="4" k="14.4454">
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
<s t="cls" n="ChurnRanking" id="src/main.cpp::ChurnRanking::ChurnRanking" k="12.1610">
</s>
</f>
<f p="src/gitmine.h">
<s t="fn" n="churnPriorFromFreq" id="src/gitmine.h::rw::churnPriorFromFreq" amb="1" k="13.2585">
<c n="DEGRADED_PATH_ALERT"/>
… [18 more display lines; full output is 2380 bytes on 1 raw line(s)]
`````


---

# zoom the detail ladder

## `./build/ripwire . --for="pagerank power iteration" --detail=2`

*Importance-weighted detail: FULL bodies for top-2, signatures for the rest.*

`````
<ctx task="pagerank power iteration" route="routed: subtoken+body BM25 (--for&apos;s default) — no strong name hit, multi-word conceptual query" root="." confidence="low" margin_pct="0" at="c7725f3ef" doc_mentions="4" est_tokens="5130">
<!-- ripwire lens for "pagerank power iteration" [doc mentions: 4 docs discussing 3 top-ranked symbols surfaced; doc_mentions= on the root repeats the doc count] [confidence= derives from the ranked head's largest relative score drop (margin_pct=, whole percent, 0 = none; the same gap the adaptive flag cuts at). low = flat ranking: treat the set as a starting point, not an answer]: reusable building blocks + quality facts for what you're about to touch (cx=complexity ccx=cognitive in=reuse-count churn=recent-commits amp=change-amplification clone=1(duplicated) tested=1) — prefer composing/reusing these; watch the high-churn/high-amp/cloned ones; tail: file-grain tail, WEAKER evidence than the ranked rows (paths only): the remaining candidate files with a positive score, best-symbol rank order; rows are t p=file; total=candidate files, shown=printed, capped=1 when they differ. r= on a ranked row is its 1-based rank in this lens ranking, rows in r= order, p= the file (a gap = a budget-trimmed row) -->
<!-- root= is the crawl root; p= below is RELATIVE to it (single-root only; absent => p= is ingest's own path, unchanged); at=this commit(+dirty). dropped_positive="16" est_tokens= prices this bundle in tokens -->
<sigs shown="24" total="40" capped="1">
<d l="40" n="HOT_FILES" p="scripts/optremarks.py" cx="0" ccx="0" in="0" churn="3" amp="37" r="1" next="--expand=scripts/optremarks.py:HOT_FILES">HOT_FILES = ( &quot;src/pagerank.cpp&quot;, # the power-iteration loop — G2&apos;s no-allocation scope &quot;src/infra/radixSort.h&quot;, # LSD radix ent … [line truncated: 42 more bytes on this line]
<d l="73" n="renderDisclosure" id="src/prconverge.h::rw::renderDisclosure" p="src/prconverge.h" cx="12" ccx="15" in="13" churn="2" amp="30" r="2">
<doc>Render one form of the disclosure. Empty string whenever there is nothing to say — no power it…</doc>inline std::string renderDisclosure( const RankDisclosure&amp; d, DiscloseAs as )</d>
<d l="51" n="RankDisclosure" id="src/prconverge.h::RankDisclosure::RankDisclosure" p="src/prconverge.h" cx="0" ccx="0" in="0" churn="2" amp="17" r="3">
<doc>What a ranked document discloses about the power iteration that ordered it. `isPageRank == false…</doc>struct RankDisclosure</d>
<d l="2492" n="RankedGraph" id="src/graph.h::RankedGraph::RankedGraph" p="src/graph.h" cx="0" ccx="0" in="0" churn="59" amp="194" r="4">
<doc>What a rank call hands back: the vector, and the power iteration&apos;s own account of itself. Struct…</doc>struct RankedGraph</d>
<d l="1550" n="kChurnRankLegend" id="src/serialize.h::rw::kChurnRankLegend" p="src/serialize.h" cx="0" ccx="0" in="0" churn="99" amp="246" pure="1" r="5">inline constexpr const char* kChurnRankLegend = &quot;&lt;!-- rank_by=churn: k= is PageRank re-run with the teleport BIASED by git CHANGE-FREQUENC … [line truncated: 39 more bytes on this line]
<d l="31" n="PageRankRun" id="src/pagerank.h::PageRankRun::PageRankRun" p="src/pagerank.h" cx="0" ccx="0" in="0" churn="6" amp="20" r="6">struct PageRankRun</d>
<d l="95" n="pageRankDouble" id="src/pagerank.cpp::rw::pageRankDouble" p="src/pagerank.cpp" cx="19" ccx="34" in="2" churn="7" amp="22" tested="1" r="7">PageRankRun pageRankDouble( const sparseCsr&lt;float&gt;&amp; inEdges, std::span&lt;const double&gt; weightedOutDegree, std::span&lt;const double&gt … [line truncated: 47 more bytes on this line]
<d l="2501" n="rankGraphTeleport" id="src/graph.h::rw::rankGraphTeleport" p="src/graph.h" cx="5" ccx="8" in="6" churn="59" amp="200" r="8">inline RankedGraph rankGraphTeleport( const Graph&amp; g, const std::vector&lt;float&gt;&amp; p, float alpha = 0.85f )</d>
<d l="983" n="churnRankedGraph" p="src/main.cpp" cx="13" ccx="18" in="1" churn="271" amp="420" r="9">inline ChurnRanking churnRankedGraph( const MainDispatch&amp; d )</d>
<d l="5542" n="Wave-2 adversarial verification (2026-08-19) — six probes against `aa97c9e`" id="docs/EVALS.md::6. Correctness and quality instruments::Wave-2 adversarial verification (2026-08-19) — six probes against `aa97c9e`" p="docs/EVALS.md" cx="0" ccx="0" in="0" churn="492" amp="683" r="10" … [line truncated: 86 more bytes on this line]
<d l="1389" n="MapAnnotations" id="src/serialize.h::MapAnnotations::MapAnnotations" p="src/serialize.h" cx="0" ccx="0" in="0" churn="99" amp="246" r="11">struct MapAnnotations</d>
<d l="2199" n="leftmost_leaf" id="src/infra/dynamic_map.hpp::dynamic_map::leftmost_leaf" p="src/infra/dynamic_map.hpp" layer="infra" cx="2" ccx="1" in="7" churn="4" amp="24" tested="1" pure="1" r="12">handle_t leftmost_leaf() const</d>
<d l="54" n="testIterationCeiling" p="src/pagerank.cpp" cx="7" ccx="9" in="1" churn="7" amp="21" tested="1" r="13">std::uint32_t testIterationCeiling() noexcept</d>
<d l="1490" n="rankByLegendFor" id="src/serialize.h::rw::rankByLegendFor" p="src/serialize.h" cx="4" ccx="4" in="1" churn="99" amp="247" r="14">inline const char* rankByLegendFor( const char* label ) noexcept</d>
<d l="1008" n="denseIdOfRoot" id="src/clones.h::rw::denseIdOfRoot" p="src/clones.h" cx="1" ccx="0" in="0" churn="17" amp="53" r="15">std::vector&lt;std::uint32_t&gt; denseIdOfRoot( symbolCount, UINT32_MAX )</d>
<d l="998" n="finalizeCrawlSkips" p="src/ingest_crawl.h" cx="2" ccx="1" in="1" churn="6" amp="44" tested="1" r="16">void finalizeCrawlSkips( CrawlSkips&amp; skips, const HashMap&lt;std::string, std::uint64_t&gt;&amp; extTally )</d>
<d l="132" n="probe_args" p="test/budgetpolicycheck.sh" layer="test" cx="2" ccx="0" in="1" churn="2" amp="13" r="17">probe_args()</d>
<d l="57" n="ColdParseReserve" id="src/ingest_parsepool.h::ColdParseReserve::ColdParseReserve" p="src/ingest_parsepool.h" cx="0" ccx="0" in="0" churn="3" amp="11" r="18">struct ColdParseReserve</d>
<d l="104" n="CommunityGroups" id="src/partition.h::CommunityGroups::CommunityGroups" p="src/partition.h" cx="0" ccx="0" in="0" churn="11" amp="19" r="19">struct CommunityGroups</d>
<d l="11" n="PageRankConfig" id="src/pagerank.h::PageRankConfig::PageRankConfig" p="src/pagerank.h" cx="0" ccx="0" in="0" churn="6" amp="20" r="20">struct PageRankConfig</d>
<d l="1163" n="values_begin" id="src/infra/dynamic_map.hpp::dynamic_map::values_begin" p="src/infra/dynamic_map.hpp" layer="infra" cx="2" ccx="1" in="3" churn="4" amp="20" tested="1" r="21">value_iterator values_begin()</d>
<d l="759" n="enclosingShadowScope" p="src/ingest_binds.h" cx="9" ccx="7" in="1" churn="4" amp="39" tested="1" r="22">inline ShadowScope enclosingShadowScope( TSNode n )</d>
<d l="37" n="ownershipRowsToPrint" id="src/ownersview.h::rw::ownershipRowsToPrint" p="src/ownersview.h" cx="6" ccx="6" in="2" churn="4" amp="6" r="23">inline std::vector&lt;std::size_t&gt; ownershipRowsToPrint( const std::vector&lt;FileOwnership&gt;&amp; ownerships, int cap, bool detail )</d>
… [129 more display lines; full output is 14919 bytes on 86 raw line(s)]
`````

## `./build/ripwire . --pack-signatures --top-k=10`

*Body-elided decl skeletons — recounted on this corpus. Measured as element bytes: the <d> signature+doc elements --pack-signatures emits, against the SAME symbols' full <b> bodies from --expand, with the CORPUS-ROOT PREFIX SUBTRACTED FROM BOTH SIDES. That subtraction is the whole methodology and the figure is meaningless without it: the root repeats inside every element's id= and p=, it is not what this verb elides, and counting it makes the headline a function of how deep the checkout happens to sit on disk — on one corpus, three spellings of the same root read 18.6 points apart before the subtraction and agree exactly after it. Root-neutralised on THIS repo: 80.9% fewer bytes at top-10, 75.6% at top-50, 73.7% at top-100 (re-derived 2026-09-05 at the capture-audit close: lane L7's P16 caps --expand's sibs= at 8 names, which SHRINKS the body side of this ratio and moved the figure down from 84.5/80.2/80.6 — the V1 2026-08-15 re-center, when sibs=/inc= first grew the body side from 70.0/61.0/63.8, in reverse; both were real re-derivations, not tolerance edits). top-50 is the number to quote, because the sigs payload is top-50 regardless of --top-k and is therefore what THIS command emits. A single small/trivial body can still invert it (signature+doc bigger than the body), like the --format=columnar sibling below. test/showcasecapturecheck.sh (C) re-derives all three from this repo every run, in the same quantity, and fails if the caption and the recount drift apart.*

`````
<ctx>
<!-- ripwire v1 t=fn|method|cls|struct|iface|var|sec|macro(#define;degraded:body-is-replacement-text,edges-cross-expansion) p=path layer=arch-layer(opt) n=name id=canonical(path::scope::name,when-scoped) k=rank c=call amb=ambiguous-calls(read-source) lpin=calls-pinned-by-locality-prior-alone(a-disclosed-guess;read-source;absent-if-0) overloads=N-same-name-defs-merged-into-this-row(absent-if-1;shown=counts-them-individually,so-rows+sum(overloads-1)=shown) prov=scip(precise;else name-based) hdr:unresolved=call-name-defined-only-in-a-lang-incompatible-file (edges heuristic) hdr:locality_pinned=sum-of-lpin(absent-if-0) hdr:external=calls-refused-as-bound-outside-the-tree(builtin/stdlib-name-without-in-repo-evidence,external-import,super-past-the-tree;no-edge;absent-if-0) r:est_tokens=hdr-copy(none-if-stable) -->
<!-- r:root=crawl-root-every-p=-is-relative-to(single-root-only;absent=>p=is-the-raw-ingest-path) -->
<!-- pr_iters=pagerank-power-iterations(stop:L1-residual-below-tol,else-ceiling) pr_converged=0-only-when-ceiling-hit-first(absent=converged;no-such-attr=not-pagerank-ordered) -->
<!-- files=1588 symbols=13849 edges=17058 shown=10 est_tokens=4633 ambiguous=6085 unresolved=3093 locality_pinned=6 external=788 precise=3 skipped_oversize=15 unindexed="txt:59,jsonl:26,tsv:21,scm:18,expected:15,lock:7" unindexed_exts=19 order=important-first -->
<r root="." est_tokens="4633" pr_iters="31">
<f p="src/infra/svector.h" layer="infra">
<s t="method" n="size" id="src/infra/svector.h::svector::size" k="0.0169">
</s>
<s t="method" n="buf" id="src/infra/svector.h::svector::buf" overloads="2" k="0.0071">
</s>
<s t="method" n="push_back" id="src/infra/svector.h::svector::push_back" amb="2" k="0.0054">
<c n="buf"/>
<c n="buf"/>
<c n="grow"/>
</s>
<s t="method" n="grow" id="src/infra/svector.h::svector::grow" amb="1" k="0.0041">
<c n="isSpilled"/>
<c n="buf"/>
<c n="buf"/>
<c n="moveRange"/>
<c n="maxSize"/>
</s>
<s t="method" n="empty" id="src/infra/svector.h::svector::empty" k="0.0030">
</s>
</f>
<f p="src/notes.h">
<s t="method" n="empty" id="src/notes.h::NoteIndex::empty" k="0.0099">
</s>
</f>
… [129 more display lines; full output is 11578 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --outline=rankGraphTeleport --top-k=0`

*Control-flow skeleton of one symbol, payload-only via the new --top-k=0.*

`````
<ctx root="." est_tokens="219"><outline><o t="fn" l="2501" p="src/graph.h" n="rankGraphTeleport"><![CDATA[inline RankedGraph rankGraphTeleport( const Graph& g, const std::vector<float>& p, float alpha = 0.85f )
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
<ctx root="." est_tokens="219"><outline><o t="fn" l="2501" p="src/graph.h" n="rankGraphTeleport"><![CDATA[inline RankedGraph rankGraphTeleport( const Graph& g, const std::vector<float>& p, float alpha = 0.85f )
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
<ctx root="." est_tokens="949">
<!-- a body's sibs="a,b,..." sibs_total=N are the file's OTHER indexed symbols (this body's own name excluded), source order, capped at 8 (sibs_capped="1" when the cap fired); inc="x.h,..." inc_total=N are the file's own #include/import targets, source order, capped at 24 (inc_capped="1" when the cap fired) — both absent when the count is 0 (a documented zero, not a degrade). Each body's own calls child (1-hop callee signatures) carries total=/shown=/capped="1" the usual way: capped="1" only when shown is below total. A body's CDATA is the bytes on disk unless the element says otherwise: scrubbed="1" = a ]]> was split (]]]]>
<![CDATA[>, rejoin it) or a C0/invalid-UTF-8 byte was replaced; redacted="1" = a credential shape was rewritten to a [REDACTED:kind] marker (the no-redact flag serves the bytes; the edit verbs refuse a payload carrying MORE such markers than the bytes it would replace already do, so source that spel … [line truncated: 59 more bytes on this line]
<bodies shown="1" total="1" capped="0">
<b t="fn" l="2501" p="src/graph.h" n="rankGraphTeleport" sibs="Graph,langCompatible,namespaceCompatible,kCommonNameMul,kCommonNameDefThreshold,kPrivateNameMul,kSpecificNameMul,kSpecificMinLen" sibs_total="148" sibs_capped="1" inc="model.h,filter.h,pageview.h,graphlegend.h,lintrules.h,infra/sparseCsr … [line truncated: 228 more bytes on this line]
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
}]]><calls total="9"><c n="biasPrior" l="2464">inline std::vector&lt;float&gt; biasPrior( const Graph&amp; g, const std::vector&lt;float&gt;&amp; p )</c><c n="PROFILE_SCOPE_DESCRIBE" l="1322">#define PROFILE_SCOPE_DESCRIBE( desc )</c><c n="PROFILE_SCOPE_DESCRIBE" l="1336">#define PROFILE_SCOPE_DESCR … [line truncated: 535 more bytes on this line]
`````

## `./build/ripwire . --expand=rankGraphTeleport:1-12 --top-k=0`

*Body SLICE: lines 1..12 of the symbol's own body, with lines="lo-hi/total" marking it partial.*

`````
<ctx root="." est_tokens="788">
<!-- a body's sibs="a,b,..." sibs_total=N are the file's OTHER indexed symbols (this body's own name excluded), source order, capped at 8 (sibs_capped="1" when the cap fired); inc="x.h,..." inc_total=N are the file's own #include/import targets, source order, capped at 24 (inc_capped="1" when the cap fired) — both absent when the count is 0 (a documented zero, not a degrade). Each body's own calls child (1-hop callee signatures) carries total=/shown=/capped="1" the usual way: capped="1" only when shown is below total. A body's CDATA is the bytes on disk unless the element says otherwise: scrubbed="1" = a ]]> was split (]]]]>
<![CDATA[>, rejoin it) or a C0/invalid-UTF-8 byte was replaced; redacted="1" = a credential shape was rewritten to a [REDACTED:kind] marker (the no-redact flag serves the bytes; the edit verbs refuse a payload carrying MORE such markers than the bytes it would replace already do, so source that spel … [line truncated: 59 more bytes on this line]
<bodies shown="1" total="1" capped="0">
<b t="fn" l="2501" p="src/graph.h" n="rankGraphTeleport" lines="1-12/29" sibs="Graph,langCompatible,namespaceCompatible,kCommonNameMul,kCommonNameDefThreshold,kPrivateNameMul,kSpecificNameMul,kSpecificMinLen" sibs_total="148" sibs_capped="1" inc="model.h,filter.h,pageview.h,graphlegend.h,lintrules.h … [line truncated: 244 more bytes on this line]
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
        for( const double value : teleport )]]><calls total="9"><c n="biasPrior" l="2464">inline std::vector&lt;float&gt; biasPrior( const Graph&amp; g, const std::vector&lt;float&gt;&amp; p )</c><c n="PROFILE_SCOPE_DESCRIBE" l="1322">#define PROFILE_SCOPE_DESCRIBE( desc )</c><c n="PROFILE_SCOPE_DES … [line truncated: 578 more bytes on this line]
`````

## `./build/ripwire . --expand=compressBody --top-k=0 --compress`

*Comments stripped + blank runs collapsed — compressBody is the function that implements --compress itself, chosen because it is comment-heavy enough to show a real reduction (the previously captioned symbol had no comments or blank runs, so before/after were byte-identical under a caption promising a difference).*

`````
<ctx root="." est_tokens="1671">
<!-- a body's sibs="a,b,..." sibs_total=N are the file's OTHER indexed symbols (this body's own name excluded), source order, capped at 8 (sibs_capped="1" when the cap fired); inc="x.h,..." inc_total=N are the file's own #include/import targets, source order, capped at 24 (inc_capped="1" when the cap fired) — both absent when the count is 0 (a documented zero, not a degrade). Each body's own calls child (1-hop callee signatures) carries total=/shown=/capped="1" the usual way: capped="1" only when shown is below total. A body's CDATA is the bytes on disk unless the element says otherwise: scrubbed="1" = a ]]> was split (]]]]>
<![CDATA[>, rejoin it) or a C0/invalid-UTF-8 byte was replaced; redacted="1" = a credential shape was rewritten to a [REDACTED:kind] marker (the no-redact flag serves the bytes; the edit verbs refuse a payload carrying MORE such markers than the bytes it would replace already do, so source that spel … [line truncated: 59 more bytes on this line]
<bodies shown="1" total="1" capped="0" compress="1">
<b t="fn" l="2775" p="src/serialize.h" n="compressBody" sibs="xmlSafeByte,xmlScrubIsLossy,xmlControlCharRef,escapeXml,writeMultiRootTable,kMultiRootTableLegend,multiRootTableLegend,xmlCommentText" sibs_total="210" sibs_capped="1" inc="model.h,nextverb.h,arch.h,graph.h,graphlegend.h,lintrules.h,resol … [line truncated: 180 more bytes on this line]
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
… [170 more display lines; full output is 6389 bytes on 195 raw line(s)]
`````

## `./build/ripwire . --expand=readAckRecords --top-k=0 --no-redact`

*--no-redact: emit bodies verbatim (credential redaction is on by default).*

`````
<ctx root="." est_tokens="1349">
<!-- a body's sibs="a,b,..." sibs_total=N are the file's OTHER indexed symbols (this body's own name excluded), source order, capped at 8 (sibs_capped="1" when the cap fired); inc="x.h,..." inc_total=N are the file's own #include/import targets, source order, capped at 24 (inc_capped="1" when the cap fired) — both absent when the count is 0 (a documented zero, not a degrade). Each body's own calls child (1-hop callee signatures) carries total=/shown=/capped="1" the usual way: capped="1" only when shown is below total. A body's CDATA is the bytes on disk unless the element says otherwise: scrubbed="1" = a ]]> was split (]]]]>
<![CDATA[>, rejoin it) or a C0/invalid-UTF-8 byte was replaced; redacted="1" = a credential shape was rewritten to a [REDACTED:kind] marker (the no-redact flag serves the bytes; the edit verbs refuse a payload carrying MORE such markers than the bytes it would replace already do, so source that spel … [line truncated: 59 more bytes on this line]
<bodies shown="1" total="1" capped="0">
<b t="fn" l="4087" p="src/quality.h" n="readAckRecords" sibs="kBaselineFile,kMinCloneTokens,kCcxBar,kLocBar,kNestBar,kParamBar,kShortHorizonDays,kShortHorizonMinCommits" sibs_total="211" sibs_capped="1" inc="model.h,ingest.h,graph.h,clones.h,cloneidiom.h,lintrules.h,arch.h,gitmine.h,docparse.h,filte … [line truncated: 186 more bytes on this line]
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
… [33 more display lines; full output is 5163 bytes on 58 raw line(s)]
`````

## `./build/ripwire . --pack-top-n=3 --top-k=0`

*Pack the top-3 ranked symbols' full bodies (deprecated verb; see stderr).*

`````
<ctx root="." est_tokens="17281"><src p="./src/infra/svector.h"><![CDATA[#pragma once

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
… [1081 more lines, 65706 bytes total]
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
<!-- ripwire v1 t=fn|method|cls|struct|iface|var|sec|macro(#define;degraded:body-is-replacement-text,edges-cross-expansion) p=path layer=arch-layer(opt) n=name id=canonical(path::scope::name,when-scoped) k=rank c=call amb=ambiguous-calls(read-source) lpin=calls-pinned-by-locality-prior-alone(a-disclosed-guess;read-source;absent-if-0) overloads=N-same-name-defs-merged-into-this-row(absent-if-1;shown=counts-them-individually,so-rows+sum(overloads-1)=shown) prov=scip(precise;else name-based) hdr:unresolved=call-name-defined-only-in-a-lang-incompatible-file (edges heuristic) hdr:locality_pinned=sum-of-lpin(absent-if-0) hdr:external=calls-refused-as-bound-outside-the-tree(builtin/stdlib-name-without-in-repo-evidence,external-import,super-past-the-tree;no-edge;absent-if-0) r:est_tokens=hdr-copy(none-if-stable) -->
<!-- r:root=crawl-root-every-p=-is-relative-to(single-root-only;absent=>p=is-the-raw-ingest-path) -->
<!-- metrics: in=fan-in out=fan-out cx=cyclomatic ccx=cognitive loc=lines params=count nest=MAX-depth humps=regions-reaching-the-nesting-bar deep=lines-inside-them(floor,see deep_floor) (humps/deep are the PROFILE nest= cannot give: nest= is a max, so one deep line and a body that is deep throughout report the same number; deep/loc is the fraction. Both absent exactly when nest<bar — not-deep, never a hidden 0. deep counts LINES and humps counts REGIONS, and two regions can share a line, so deep BELOW humps is legal: a one-line if/else at the bar is 2 regions on 1 line) locals=local-var-decl-count(floor,C/C++-only,see locals_floor) ppalt=preproc-alternative-branches-in-body(#else/#elif; metrics sum ALL branches, no single build compiles them all) ev=essential-cx(McCabe: 1=fully structured, 2+=jumps block extract-method; absent on a cx row means exactly 1; floor per ev_floor — noreturn calls/macro-hidden exits unseen; not counted: &&/||, Rust ? and yield/await/defer, hence Bash carries no ev) ev_why=which-jumps-raised-it tag:count cbo=coupling lcom4=cohesion amp=change-amplification tested=1 role=hub(fan-in 8+; uses spells role call|macro|read|write|import|extends). Absent=N/A, never 0. -->
<!-- pr_iters=pagerank-power-iterations(stop:L1-residual-below-tol,else-ceiling) pr_converged=0-only-when-ceiling-hit-first(absent=converged;no-such-attr=not-pagerank-ordered) -->
<!-- files=1588 symbols=13849 edges=17058 shown=10 est_tokens=1962 ambiguous=6085 unresolved=3093 locality_pinned=6 external=788 precise=3 skipped_oversize=15 unindexed="txt:59,jsonl:26,tsv:21,scm:18,expected:15,lock:7" unindexed_exts=19 order=important-first -->
<r root="." est_tokens="1962" pr_iters="31">
<f p="src/infra/svector.h" layer="infra">
<s t="method" n="size" id="src/infra/svector.h::svector::size" in="636" out="0" cx="1" ccx="0" role="hub" loc="1" params="0" nest="0" locals="0" locals_floor="1" cbo="0" amp="659" tested="1" k="0.0169">
</s>
<s t="method" n="buf" id="src/infra/svector.h::svector::buf" overloads="2" in="29" out="0" cx="2" ccx="1" role="hub" loc="1" params="0" nest="1" locals="0" locals_floor="1" cbo="0" amp="52" tested="1" k="0.0071">
</s>
<s t="method" n="push_back" id="src/infra/svector.h::svector::push_back" in="458" out="3" cx="2" ccx="1" role="hub" loc="5" params="1" nest="1" locals="1" locals_floor="1" cbo="3" amp="481" tested="1" amb="2" k="0.0054" ev="2" ev_floor="1" ev_why="guard-return:1">
<c n="buf"/>
<c n="buf"/>
<c n="grow"/>
</s>
<s t="method" n="grow" id="src/infra/svector.h::svector::grow" in="3" out="5" cx="4" ccx="3" loc="14" params="1" nest="1" locals="4" locals_floor="1" cbo="5" amp="26" tested="1" amb="1" k="0.0041">
<c n="isSpilled"/>
<c n="buf"/>
<c n="buf"/>
<c n="moveRange"/>
<c n="maxSize"/>
</s>
<s t="method" n="empty" id="src/infra/svector.h::svector::empty" in="122" out="0" cx="1" ccx="0" role="hub" loc="1" params="0" nest="0" locals="0" locals_floor="1" cbo="0" amp="145" tested="1" k="0.0030">
</s>
</f>
<f p="src/notes.h">
<s t="method" n="empty" id="src/notes.h::NoteIndex::empty" in="760" out="0" cx="1" ccx="0" role="hub" loc="1" params="0" nest="0" locals="0" locals_floor="1" cbo="0" amp="801" tested="1" k="0.0099">
</s>
</f>
… [17 more display lines; full output is 4870 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --deps`

*File->file dependency graph (god-files, cycles).*

`````
<!-- ripwire deps: file-to-file #include/import view, heaviest transitive cone first. files= (root) = files with at least one dependency edge (this listing's own denominator); health files= = the whole indexed corpus; health dep_files= = the dependency-CAPABLE subset of it (the ccd/acd/nccd denominator). raise the default cap with limit=N (offset=M pages; a cut listing carries total=/has_more=/next_offset= so a paging loop can continue from it). -->
<deps files="370" shown="40" capped="1" total="370" has_more="1" next_offset="40" offset="0" limit="0" root=".">
<health files="1588" dep_files="750" ccd="4378" acd="5.8" nccd="0.68" shape="horizontal"/>
<godfiles total="262" shown="12" capped="1">
<f p="src/model.h" afferent="76"/>
<f p="src/infra/Diagnostics.h" afferent="44"/>
<f p="src/serialize.h" afferent="34"/>
<f p="src/graph.h" afferent="33"/>
<f p="src/ingest.h" afferent="23"/>
<f p="src/arch.h" afferent="20"/>
<f p="src/infra/jsonesc.h" afferent="20"/>
<f p="src/quality.h" afferent="19"/>
<f p="src/gitstamp.h" afferent="18"/>
<f p="src/graphlegend.h" afferent="15"/>
<f p="src/pageview.h" afferent="15"/>
<f p="src/docparse.h" afferent="14"/>
</godfiles>
<stabledeps violations="21">
<v from="src/graph.h" to="src/pincensus.h" gap="0.41"/>
<v from="src/gitstamp.h" to="src/quality.h" gap="0.35"/>
<v from="src/mcp.h" to="src/mcpverbs.h" gap="0.33"/>
<v from="src/infra/sortutil.h" to="src/infra/radixSort.h" gap="0.33"/>
<v from="src/filter.h" to="src/queryshape.h" gap="0.32"/>
<v from="src/quality.h" to="src/cloneidiom.h" gap="0.26"/>
<v from="src/infra/profileScope.h" to="src/infra/profilePmc.h" gap="0.25"/>
<v from="test/cyclecutfix/b.h" to="test/cyclecutfix/c.h" gap="0.25"/>
<v from="test/cyclecutfix/c.h" to="test/cyclecutfix/a.h" gap="0.25"/>
<v from="src/serialize.h" to="src/notes.h" gap="0.21"/>
<v from="src/partition.h" to="src/packtask.h" gap="0.18"/>
<v from="src/graph.h" to="src/externalnames.h" gap="0.16"/>
… [764 more display lines; full output is 19052 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --hotspots`

*Complexity x recent git churn (maintenance pain).*

`````
<!-- ripwire hotspots: maintenance-pain = complexity × recent churn (window=12mo). churn=commits touching the file; ccx=Σ cognitive complexity; score=churn×ccx; top=worst function. files= is the DENOMINATOR ranked= is drawn from, and a hotspot needs both factors nonzero, so ranked= + unranked_no_churn= + unranked_no_complexity= = files= exactly. unranked_no_complexity= is a file with commits but no function or method to score (a pure declaration header, markdown, config). unranked_no_churn= is a file no in-window commit was attributed to — and it CONFLATES two cases this verb cannot tell apart: a genuinely quiet file, and one whose path the git-to-index join never bound (a rename, an exclusion, or a spelling the join could not match), which scores zero for a reason that is not about the file. Treat it as an upper bound on quietness, not a measure of it. raise the default cap with limit=N (offset=M pages; a cut listing carries total=/has_more=/next_offset= so a paging loop can continue from it) -->
<!-- at= is the git commit these numbers were computed at; a trailing +dirty means the working tree differed from that commit, so the numbers describe the tree, not the commit -->
<!-- root= on this element is the crawl root every p= below is RELATIVE to (single-root runs only; absent => p= is the path ingest itself used, unchanged). -->
<hotspots window="12mo" files="1588" ranked="438" unranked_no_churn="0" unranked_no_complexity="1150" shown="40" capped="1" total="438" has_more="1" next_offset="40" offset="0" limit="0" root="." at="c7725f3ef">
<f p="src/main.cpp" churn="271" ccx="885" score="239835" top="dispatchMain" top_ccx="405" top_l="2653"/>
<f p="src/serialize.h" churn="99" ccx="1860" score="184140" top="packSignatures" top_ccx="220" top_l="3316"/>
<f p="src/quality.h" churn="106" ccx="1182" score="125292" top="computeDelta" top_ccx="243" top_l="5284"/>
<f p="src/mcpverbs.h" churn="117" ccx="981" score="114777" top="runBatchSub" top_ccx="112" top_l="4266"/>
<f p="src/graph.h" churn="59" ccx="1834" score="108206" top="buildGraph" top_ccx="779" top_l="962"/>
<f p="src/cli.h" churn="212" ccx="501" score="106212" top="parseArgs" top_ccx="191" top_l="4132"/>
<f p="src/mcp.h" churn="52" ccx="577" score="30004" top="dispatchMcpLine" top_ccx="517" top_l="535"/>
<f p="src/verbs_navigate.h" churn="32" ccx="599" score="19168" top="runVerify" top_ccx="130" top_l="1316"/>
<f p="src/slice.h" churn="24" ccx="785" score="18840" top="sliceClassify" top_ccx="183" top_l="529"/>
<f p="src/lexical.h" churn="31" ccx="563" score="17453" top="lexicalScoresTiered" top_ccx="366" top_l="121"/>
<f p="src/verbs_report.h" churn="16" ccx="1001" score="16016" top="runStructureText" top_ccx="241" top_l="2707"/>
<f p="src/verbs_for.h" churn="29" ccx="496" score="14384" top="runForLens" top_ccx="239" top_l="1447"/>
<f p="src/verbs_quality.h" churn="26" ccx="474" score="12324" top="runQualityDelta" top_ccx="259" top_l="940"/>
<f p="src/search.h" churn="20" ccx="557" score="11140" top="grepCollect" top_ccx="49" top_l="1384"/>
<f p="src/verbs_change.h" churn="25" ccx="444" score="11100" top="runChangeViews" top_ccx="157" top_l="267"/>
<f p="src/crossref.h" churn="24" ccx="438" score="10512" top="streamBlobs" top_ccx="43" top_l="464"/>
<f p="src/gitmine.h" churn="17" ccx="606" score="10302" top="applyCoChangeBoost" top_ccx="93" top_l="2532"/>
<f p="src/packtask.h" churn="34" ccx="296" score="10064" top="packTaskBundleText" top_ccx="166" top_l="1082"/>
<f p="src/resolve.h" churn="18" ccx="548" score="9864" top="buildPreciseIncludeAdj" top_ccx="58" top_l="1094"/>
<f p="src/layout.h" churn="13" ccx="699" score="9087" top="writeLayout" top_ccx="39" top_l="2522"/>
<f p="src/docdrift.h" churn="13" ccx="563" score="7319" top="computeDocDrift" top_ccx="35" top_l="2289"/>
<f p="bench/agentloop/run_agentloop.py" churn="20" ccx="316" score="6320" top="parse_claude_session_metrics" top_ccx="40" top_l="582"/>
<f p="src/mcpedit.h" churn="23" ccx="269" score="6187" top="resolveOneForEdit" top_ccx="30" top_l="342"/>
<f p="src/verbs_lint.h" churn="8" ccx="668" score="5344" top="runLint" top_ccx="326" top_l="1175"/>
<f p="src/naminglens.h" churn="14" ccx="373" score="5222" top="checkScopeGroups" top_ccx="93" top_l="904"/>
<f p="src/prcontext.h" churn="21" ccx="229" score="4809" top="writePrContext" top_ccx="154" top_l="869"/>
… [15 more display lines; full output is 5821 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --clones`

*Token-normalized duplicate bodies.*

`````
<!-- ripwire clones: function bodies with similar normalized token streams (identifiers/literals normalized, so renamed copies match). type=2 exact/renamed (Type-1/2); type=3 gapped near-miss (an inserted/changed statement, similarity in [0.80,1.0)). Reuse don't reimplement; a fix to one likely belongs in all. groups= and type3= are the two GROUP-TYPE totals (each capped independently, so neither is the row count); total= is the true row total (groups + type3-group-count) and is ALWAYS present, paged or not; shown= is the number of group rows that follow this run. capped="1" means rows were dropped. exempt= on a group ⇒ every member is on a path the quality-delta verb's duplication kind deliberately ignores (fixture dirs / shell test-runners repeat boilerplate by convention) — a fact here, never a gate there; exempt_groups= counts them over ALL groups. idiom= on a group names the RECOGNIZED SHAPE every one of its members classifies to, from a CLOSED set of three: threshold-ladder (a chain of if-compare-return and nothing else), switch-name-table (a switch whose every arm is a label plus a literal return), builder-chain (a param-struct initializer chain). demoted="1" additionally means the quality-delta verb's duplication kind reports this group as minor rather than gating on it, which happens only when the WHOLE conjunction holds: every member the same recognized idiom, no two members sharing a single non-keyword identifier, no two members sharing an enclosing context (file plus scope), and the group under 80 normalized tokens. Five cross-domain bucketing ladders that share only the idiom are noise; two ladders over the same enum, or two in one namespace, are a copy. The idiom name is printed precisely so a human can overrule the demotion by reading the members: a demoted row is annotated, never removed. idiom_groups= and demoted_groups= count each of those over ALL groups. FLOOR on the classifier, since a silence here would read as coverage: the shape is read off the body's TOKEN stream and not a parse tree, so a macro-assembled body classifies as whatever its raw tokens spell; the table arm models case-labelled switches only; and builder-chain models the field-assignment spelling, not the fluent chained-call one. gid= on a row is its CLONE COMPONENT: the Type-3 pass reports PAIRS, so three functions that are all near-copies of each other arrive as three rows of two; rows sharing a gid are one cluster, and clone_groups= counts the clusters (union-find over the pair graph, over ALL detected rows, not just the shown ones). dup_pct=duplicated-LOC/total-LOC as a percentage, where duplicated-LOC sums, per cluster, every member's loc EXCEPT the largest member's (one instance is the code you keep, the rest is the redundancy — so a 3-clone cluster counts its lines TWICE) and total-LOC is every function/method body the detector considered; dup_loc= and total_loc= are those two operands. counts_floor="1": the Type-3 pair list is capped upstream, so a dropped pair is a cluster left unmerged — clone_groups/dup_loc/dup_pct are floors, never totals. raise the default cap with limit=N (offset=M pages; a cut listing carries total=/has_more=/next_offset= so a paging loop can continue from it). -->
<!-- root= on this element is the crawl root every p= below is RELATIVE to (single-root runs only; absent => p= is the path ingest itself used, unchanged). -->
<clones groups="75" type3="342" exempt_groups="201" idiom_groups="14" demoted_groups="10" clone_groups="220" dup_loc="4342" total_loc="136527" dup_pct="3.2" counts_floor="1" shown="80" capped="1" total="417" has_more="1" next_offset="80" offset="0" limit="0" root=".">
<group type="2" gid="194" tokens="211" n="4" exempt="shell-runner">
<f n="batch_sub" p="test/mcpclidiffcheck.sh:63"/>
<f n="batch_sub" p="test/mcptranchecheck.sh:55"/>
<f n="batch_sub" p="test/mcpw2fixcheck.sh:52"/>
<f n="batch_sub" p="test/mcpw3fixcheck.sh:51"/>
</group>
<group type="2" gid="212" tokens="149" n="3" exempt="shell-runner">
<f n="monotonic_check" p="test/pyimportprecisecheck.sh:89"/>
<f n="monotonic_check" p="test/rustimportprecisecheck.sh:124"/>
<f n="monotonic_check" p="test/tsimportprecisecheck.sh:88"/>
</group>
<group type="2" gid="39" tokens="142" n="2">
<f n="test_tier2_accept_big_quality_small_cost" p="bench/locbench/test_compare_gate.py:130"/>
<f n="test_tier2_reject_small_quality_big_cost" p="bench/locbench/test_compare_gate.py:143"/>
</group>
<group type="2" gid="158" tokens="126" n="2">
<f n="addWholeFileFn" p="test/cloneband_harness.cpp:64"/>
<f n="addWholeFileFn" p="test/type3clone_harness.cpp:47"/>
</group>
<group type="2" gid="46" tokens="121" n="2">
<f n="resolve_arm" p="hooks/ripwire-claude-route.sh:75"/>
<f n="resolve_arm" p="hooks/ripwire-claude-toolroute.sh:134"/>
</group>
<group type="2" gid="70" tokens="118" n="2">
<f n="rankFiles" p="src/eval.h:53"/>
<f n="rankCandidates" p="src/skilleval.h:426"/>
</group>
… [309 more display lines; full output is 18694 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --cochange`

*Files that change together in git (hidden coupling).*

`````
<!-- ripwire cochange: file pairs that change together in git but share no transitive static dependency (surprising=1) = hidden coupling. together= is the number of commits in window= that touched BOTH files (3 or more, or the pair is not reported); deg= is that count over the commit count of the LESS-CHANGED of the two files, so 1.00 means the quieter file never changed without the other. conf_ab= is that same fraction over a='s OWN commit count and conf_ba= over b='s, which is the asymmetric form: conf_ab=1.00 means a never changed without b. deg= is by construction the larger of the two, and driver= names which side it came from ("a" or "b") — the file whose changes most reliably imply the other's, and therefore the one to look at first. driver= is OMITTED when the two directions are equal, because a tie is not a finding. recur= is how many of sub_windows= the pair actually co-changed in: the mined window is cut into that many equal-COMMIT-COUNT slices (not equal time — a calendar slice can hold 400 commits or 4), so recur=1 at any together= is one burst of activity and not a persistent coupling, which is the distinction a single window cannot make. sub_windows= is the denominator and is never omitted; it is smaller than the nominal 3 only when the window holds fewer commits than that. min_recur= appears when cochange-recur=K (the flag) filtered the rows, so a short list is explained rather than silent. window= is the mining window: the default 18 months, or the since=REV|DATE value when one resolved. surprising= is only defined where BOTH sides could carry a static dependency at all (the same dependency-capable predicate deps <health dep_files=> uses: source languages yes; sh, md, json, ruby and binary/unknown files no). A pair with a dep-incapable side keeps its row and carries dep_capable=0 instead, because for it "shares no static dependency" is vacuously true. raise the default cap with limit=N (offset=M pages; a cut listing carries total=/has_more=/next_offset= so a paging loop can continue from it) -->
<!-- at= is the git commit these numbers were computed at; a trailing +dirty means the working tree differed from that commit, so the numbers describe the tree, not the commit -->
<!-- root= on this element is the crawl root every p= below is RELATIVE to (single-root runs only; absent => p= is the path ingest itself used, unchanged). -->
<cochange pairs="1051" window="18mo" sub_windows="3" shown="30" capped="1" total="1051" has_more="1" next_offset="30" offset="0" limit="0" root="." at="c7725f3ef">
<pair a="src/cli.h" b="src/editpreview.h" together="4" deg="1.00" conf_ab="0.02" conf_ba="1.00" driver="b" recur="1" surprising="1"/>
<pair a="src/crossref.h" b="src/darkflags.h" together="3" deg="1.00" conf_ab="0.18" conf_ba="1.00" driver="b" recur="2" surprising="1"/>
<pair a="bench/scip_pin_precision.py" b="src/graph.h" together="3" deg="1.00" conf_ab="1.00" conf_ba="0.06" driver="a" recur="1" surprising="1"/>
<pair a="bench/scip_pin_precision.py" b="src/pincensus.h" together="3" deg="1.00" conf_ab="1.00" conf_ba="0.60" driver="a" recur="1" surprising="1"/>
<pair a="src/serialize.h" b="src/tsprobe.cpp" together="3" deg="1.00" conf_ab="0.03" conf_ba="1.00" driver="b" recur="2" surprising="1"/>
<pair a="src/quality.h" b="src/tsprobe.cpp" together="3" deg="1.00" conf_ab="0.03" conf_ba="1.00" driver="b" recur="2" surprising="1"/>
<pair a="src/lintrules.h" b="src/tsprobe.cpp" together="3" deg="1.00" conf_ab="0.50" conf_ba="1.00" driver="b" recur="2" surprising="1"/>
<pair a="src/ingest.cpp" b="src/tsprobe.cpp" together="3" deg="1.00" conf_ab="0.03" conf_ba="1.00" driver="b" recur="2" surprising="1"/>
<pair a="src/fieldaffinity.h" b="test/accessshapefix/walks.cpp" together="3" deg="1.00" conf_ab="0.50" conf_ba="1.00" driver="b" recur="2" surprising="1"/>
<pair a="src/accessshape.h" b="test/accessshapefix/walks.cpp" together="3" deg="1.00" conf_ab="1.00" conf_ba="1.00" recur="2" surprising="1"/>
<pair a="src/clones.h" b="src/tsprobe.cpp" together="3" deg="1.00" conf_ab="0.27" conf_ba="1.00" driver="b" recur="2" surprising="1"/>
<pair a="src/cli.h" b="src/tsprobe.cpp" together="3" deg="1.00" conf_ab="0.01" conf_ba="1.00" driver="b" recur="2" surprising="1"/>
<pair a="src/cli.h" b="src/sarif.h" together="3" deg="1.00" conf_ab="0.01" conf_ba="1.00" driver="b" recur="3" surprising="1"/>
<pair a="src/fielduses.h" b="src/nonlocalstate.h" together="3" deg="1.00" conf_ab="1.00" conf_ba="0.27" driver="a" recur="1" surprising="1"/>
<pair a="bench/agentloop/analyze.py" b="bench/agentloop/run_agentloop.py" together="8" deg="0.89" conf_ab="0.89" conf_ba="0.47" driver="a" recur="2" surprising="1"/>
<pair a="src/ingest_cache.h" b="src/quality.h" together="9" deg="0.82" conf_ab="0.82" conf_ba="0.09" driver="a" recur="1" surprising="1"/>
<pair a="bench/bench_svector3.cpp" b="bench/bench_svector_wave.cpp" together="4" deg="0.80" conf_ab="0.80" conf_ba="0.80" recur="1" surprising="1"/>
<pair a="src/cli.h" b="src/compactlegend.h" together="7" deg="0.78" conf_ab="0.03" conf_ba="0.78" driver="b" recur="1" surprising="1"/>
<pair a="src/ingest.h" b="src/pattern.h" together="3" deg="0.75" conf_ab="0.14" conf_ba="0.75" driver="b" recur="1" surprising="1"/>
<pair a="src/serialize.h" b="src/verify.h" together="3" deg="0.75" conf_ab="0.03" conf_ba="0.75" driver="b" recur="1" surprising="1"/>
<pair a="src/graphlegend.h" b="src/verify.h" together="3" deg="0.75" conf_ab="0.09" conf_ba="0.75" driver="b" recur="1" surprising="1"/>
<pair a="src/verbs_navigate.h" b="src/verify.h" together="3" deg="0.75" conf_ab="0.09" conf_ba="0.75" driver="b" recur="1" surprising="1"/>
<pair a="src/namingconsistency.h" b="src/readability.h" together="3" deg="0.75" conf_ab="0.75" conf_ba="0.50" driver="a" recur="2" surprising="1"/>
<pair a="src/ingest_binds.h" b="src/quality.h" together="3" deg="0.75" conf_ab="0.75" conf_ba="0.03" driver="a" recur="1" surprising="1"/>
<pair a="src/ingest_binds.h" b="src/ingest_cache.h" together="3" deg="0.75" conf_ab="0.75" conf_ba="0.27" driver="a" recur="1" surprising="1"/>
<pair a="src/graph.h" b="src/ingest_binds.h" together="3" deg="0.75" conf_ab="0.06" conf_ba="0.75" driver="b" recur="1" surprising="1"/>
<pair a="src/cli.h" b="src/mcpedit.h" together="12" deg="0.71" conf_ab="0.06" conf_ba="0.71" driver="b" recur="3" surprising="1"/>
<pair a="src/serialize.h" b="src/workspace.h" together="7" deg="0.70" conf_ab="0.07" conf_ba="0.70" driver="b" recur="3" surprising="1"/>
<pair a="src/mcpverbs.h" b="src/verbs_for.h" together="20" deg="0.69" conf_ab="0.18" conf_ba="0.69" driver="b" recur="1" surprising="1"/>
<pair a="src/cli.h" b="src/lintrules.h" together="4" deg="0.67" conf_ab="0.02" conf_ba="0.67" driver="b" recur="3" surprising="1"/>
</cochange>
`````

## `./build/ripwire . --hotspots --since="2 weeks ago"`

*Hotspots scoped to RECENT churn (the regression lens).*

`````
<!-- ripwire hotspots: maintenance-pain = complexity × recent churn (window=2 weeks ago). churn=commits touching the file; ccx=Σ cognitive complexity; score=churn×ccx; top=worst function. files= is the DENOMINATOR ranked= is drawn from, and a hotspot needs both factors nonzero, so ranked= + unranked_no_churn= + unranked_no_complexity= = files= exactly. unranked_no_complexity= is a file with commits but no function or method to score (a pure declaration header, markdown, config). unranked_no_churn= is a file no in-window commit was attributed to — and it CONFLATES two cases this verb cannot tell apart: a genuinely quiet file, and one whose path the git-to-index join never bound (a rename, an exclusion, or a spelling the join could not match), which scores zero for a reason that is not about the file. Treat it as an upper bound on quietness, not a measure of it. raise the default cap with limit=N (offset=M pages; a cut listing carries total=/has_more=/next_offset= so a paging loop can continue from it) -->
<!-- at= is the git commit these numbers were computed at; a trailing +dirty means the working tree differed from that commit, so the numbers describe the tree, not the commit -->
<!-- root= on this element is the crawl root every p= below is RELATIVE to (single-root runs only; absent => p= is the path ingest itself used, unchanged). -->
<hotspots window="2 weeks ago" files="1588" ranked="222" unranked_no_churn="1045" unranked_no_complexity="321" shown="40" capped="1" total="222" has_more="1" next_offset="40" offset="0" limit="0" root="." at="c7725f3ef">
<f p="src/main.cpp" churn="103" ccx="885" score="91155" top="dispatchMain" top_ccx="405" top_l="2653"/>
<f p="src/serialize.h" churn="45" ccx="1860" score="83700" top="packSignatures" top_ccx="220" top_l="3316"/>
<f p="src/mcpverbs.h" churn="77" ccx="981" score="75537" top="runBatchSub" top_ccx="112" top_l="4266"/>
<f p="src/cli.h" churn="115" ccx="501" score="57615" top="parseArgs" top_ccx="191" top_l="4132"/>
<f p="src/quality.h" churn="40" ccx="1182" score="47280" top="computeDelta" top_ccx="243" top_l="5284"/>
<f p="src/graph.h" churn="24" ccx="1834" score="44016" top="buildGraph" top_ccx="779" top_l="962"/>
<f p="src/verbs_navigate.h" churn="32" ccx="599" score="19168" top="runVerify" top_ccx="130" top_l="1316"/>
<f p="src/slice.h" churn="24" ccx="785" score="18840" top="sliceClassify" top_ccx="183" top_l="529"/>
<f p="src/mcp.h" churn="29" ccx="577" score="16733" top="dispatchMcpLine" top_ccx="517" top_l="535"/>
<f p="src/verbs_report.h" churn="16" ccx="1001" score="16016" top="runStructureText" top_ccx="241" top_l="2707"/>
<f p="src/verbs_for.h" churn="29" ccx="496" score="14384" top="runForLens" top_ccx="239" top_l="1447"/>
<f p="src/verbs_quality.h" churn="26" ccx="474" score="12324" top="runQualityDelta" top_ccx="259" top_l="940"/>
<f p="src/verbs_change.h" churn="25" ccx="444" score="11100" top="runChangeViews" top_ccx="157" top_l="267"/>
<f p="src/crossref.h" churn="15" ccx="438" score="6570" top="streamBlobs" top_ccx="43" top_l="464"/>
<f p="src/packtask.h" churn="19" ccx="296" score="5624" top="packTaskBundleText" top_ccx="166" top_l="1082"/>
<f p="src/verbs_lint.h" churn="8" ccx="668" score="5344" top="runLint" top_ccx="326" top_l="1175"/>
<f p="src/mcpedit.h" churn="15" ccx="269" score="4035" top="resolveOneForEdit" top_ccx="30" top_l="342"/>
<f p="src/lexical.h" churn="7" ccx="563" score="3941" top="lexicalScoresTiered" top_ccx="366" top_l="121"/>
<f p="src/gitmine.h" churn="6" ccx="606" score="3636" top="applyCoChangeBoost" top_ccx="93" top_l="2532"/>
<f p="src/situ.h" churn="20" ccx="179" score="3580" top="writeSituation" top_ccx="52" top_l="235"/>
<f p="src/resolve.h" churn="6" ccx="548" score="3288" top="buildPreciseIncludeAdj" top_ccx="58" top_l="1094"/>
<f p="src/ingest_cache.h" churn="11" ccx="296" score="3256" top="saveCache" top_ccx="80" top_l="1844"/>
<f p="src/ingest_astquery.h" churn="5" ccx="625" score="3125" top="astQueryGrouped" top_ccx="244" top_l="562"/>
<f p="src/mcprefusal.h" churn="14" ccx="184" score="2576" top="inputSchemaFor" top_ccx="23" top_l="1272"/>
<f p="src/prcontext.h" churn="11" ccx="229" score="2519" top="writePrContext" top_ccx="154" top_l="869"/>
<f p="src/ingest_crawl.h" churn="6" ccx="356" score="2136" top="collectSources" top_ccx="83" top_l="1024"/>
… [15 more display lines; full output is 5809 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --arch=test/archfix/rules.txt`

*Enforce layering rules (exit 2 on violation) — run against the repo's own test fixture rules.*

`````
<!-- ripwire arch: layering fitness function — edges that violate your declared rules (layer rules and regex path-rules). exit=2 if any NEW (un-baselined) violation. <metrics> = descriptive Martin Ca/Ce/I/A/D + reachability, never gates. Rules — layer substrings and regex path-rules alike — are matched against each file's ROOT-RELATIVE path (src/core/x.cpp), never the absolute or ./-prefixed spelling shown in from=/to=, so a rule means the same thing whatever directory the tree was checked out into. -->
<arch layers="2" rules="1" pathRules="0" violations="0" baselined="0" new_violations="0">
<metrics modules="302" typed_modules="115" zone_pain="96" zone_useless="1" zone_ok="18" zone_na="187" propagation_cost="0.008" note="Martin Ca/Ce/I/A/D + zone (main-sequence heuristic, no independent outcome-based validation — folklore, not proof) + reachability — directory-level estimate from n … [line truncated: 409 more bytes on this line]
<m path="." ca="0" ce="0" types="0" abstract="0" I="0.00" A="0.00" D="1.00" zone="n/a" reachable="1" isolated="1"/>
<m path="./.codex-plugin" ca="0" ce="0" types="0" abstract="0" I="0.00" A="0.00" D="1.00" zone="n/a" reachable="1" isolated="1"/>
<m path="./.github/workflows" ca="0" ce="0" types="0" abstract="0" I="0.00" A="0.00" D="1.00" zone="n/a" reachable="1" isolated="1"/>
<m path="./bench" ca="0" ce="1" types="20" abstract="2" I="1.00" A="0.10" D="0.10" zone="ok" reachable="1"/>
<m path="./bench/agentloop" ca="0" ce="0" types="0" abstract="0" I="0.00" A="0.00" D="1.00" zone="n/a" reachable="1" isolated="1"/>
<m path="./bench/agentloop/editsuite" ca="0" ce="0" types="0" abstract="0" I="0.00" A="0.00" D="1.00" zone="n/a" reachable="1" isolated="1"/>
<m path="./bench/agentloop/editsuite/fixture" ca="0" ce="0" types="1" abstract="0" I="0.00" A="0.00" D="1.00" zone="pain" reachable="1" isolated="1"/>
<m path="./bench/agentloop/editsuite/fixture/test" ca="0" ce="0" types="0" abstract="0" I="0.00" A="0.00" D="1.00" zone="n/a" reachable="1" isolated="1"/>
<m path="./bench/agentloop/fixtures/grader" ca="0" ce="0" types="0" abstract="0" I="0.00" A="0.00" D="1.00" zone="n/a" reachable="1" isolated="1"/>
<m path="./bench/agentloop/results" ca="0" ce="0" types="0" abstract="0" I="0.00" A="0.00" D="1.00" zone="n/a" reachable="1" isolated="1"/>
<m path="./bench/arb" ca="0" ce="0" types="0" abstract="0" I="0.00" A="0.00" D="1.00" zone="n/a" reachable="1" isolated="1"/>
<m path="./bench/arise-h2h" ca="0" ce="0" types="0" abstract="0" I="0.00" A="0.00" D="1.00" zone="n/a" reachable="1" isolated="1"/>
<m path="./bench/arise-h2h/swe_agent_bundle_ripwire" ca="0" ce="0" types="0" abstract="0" I="0.00" A="0.00" D="1.00" zone="n/a" reachable="1" isolated="1"/>
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
… [277 more display lines; full output is 42068 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --lint`

*Built-in AST checks (c-cast, goto, unsafe-c-fn, ...).*

`````
<!-- ripwire lint: [AST]-only checks (descriptive facts, not gates). rule=the check; sev=user-rule severity; in=enclosing symbol NAME (the same spelling is a fan-in COUNT in for/pack-task/exemplar). A rule named atom-X is an atom of confusion (Gopstein, FSE 2017): a C-family shape that misleads READERS, C/C++/ObjC/CUDA only. Each rule is scanned under its OWN match budget, so no rule is ever starved by a noisier one. A rule that spends its whole budget carries count_capped="1" — its count= is then a FLOOR (that rule's raw captures reached the per-rule budget; only its own matches can cap it); findings_capped="1" on the root ⇒ at least one PRINTED rule row is a floor (never inherited from a rule lint-select/lint-ignore dropped), and the root then also carries counts_floor="1" and capped="1": findings= and total= are floors, rows exist that no page holds. Absent = nothing was capped and every count= is a total. raise the default cap with limit=N (offset=M pages; a cut listing carries total=/has_more=/next_offset= so a paging loop can continue from it). On the root, shown=/capped= are the ROW-COUNT pair (rows printed vs whether the DEFAULT payload byte-cap trimmed them, absent an explicit limit=) — a different fact from the per-rule count_capped="1" above, which is a MATCH-BUDGET floor on one rule's own count=; findings= is the true total unless findings_capped="1" floors it. A rule row's applicable="0" ⇒ NONE of its registered languages (the lint-catalog listing) are present in this corpus at all — its count="0" is structural inertness, never a measurement; the root's inert_rules=N tallies how many printed rows that is true for. lint-select=/lint-ignore=PREFIX[,...] narrow the printed rows to a family (e.g. cache-); the root then carries selected="K of N" plus the raw select=/ignore= you passed. naming_locals="1" on the root ⇒ the opt-in naming-locals modifier was on (the naming-* rules also read local variables inside already-flagged functions); absent ⇒ off, and the naming-* counts cover declarations only. Each rule row's own shown_rows=/rows_capped= is how many of THAT rule's rows fall inside the printed <f> window (the root's shown=/capped= trims a SORTED PREFIX of the combined findings, so a rule whose rows all sort past the cut carries shown_rows="0" rows_capped="1" while its count= stays the true total — never confuse a capped-away rule with one that measured zero); this is a DIFFERENT fact from the row's own count_capped="1" above (that rule's own raw-capture stream hit its per-rule match budget) — the two can disagree on the same row. A lint-rules row's compiled="0" ⇒ that rule's tree-sitter QUERY failed to compile for every linked grammar (a malformed or misspelled pattern) — its count="0" never ran at all, a different claim from applicable="0" above (a well-formed query whose declared language just is not in this corpus) and from an ordinary count="0" (a well-formed query that ran and found nothing); absent ⇒ the query compiled. -->
<lint findings="3836" shown="688" capped="1" total="3836" has_more="1" next_offset="688" offset="0" limit="0" counts_floor="1" findings_capped="1" root=".">
<rule name="c-style-cast" count="307" shown_rows="104" rows_capped="1"/>
<rule name="goto" count="3" shown_rows="1" rows_capped="1"/>
<rule name="do-while" count="5" shown_rows="0" rows_capped="1"/>
<rule name="unsafe-c-fn" count="0" shown_rows="0" rows_capped="0"/>
<rule name="weak-crypto" count="0" shown_rows="0" rows_capped="0"/>
<rule name="redundant-parens" count="0" shown_rows="0" rows_capped="0"/>
<rule name="suspicious-semicolon" count="0" shown_rows="0" rows_capped="0"/>
<rule name="typedef-over-using" count="12" shown_rows="0" rows_capped="1"/>
<rule name="magic-number" count="507" shown_rows="308" rows_capped="1" count_capped="1"/>
<rule name="empty-catch" count="1" shown_rows="0" rows_capped="1"/>
<rule name="self-assign" count="3" shown_rows="0" rows_capped="1"/>
<rule name="large-function" count="248" shown_rows="45" rows_capped="1"/>
<rule name="deep-nesting" count="232" shown_rows="41" rows_capped="1"/>
<rule name="inconsistent-return" count="1" shown_rows="0" rows_capped="1"/>
<rule name="unreachable-code" count="5" shown_rows="0" rows_capped="1"/>
<rule name="naming-short" count="1257" shown_rows="36" rows_capped="1"/>
<rule name="naming-wordy" count="98" shown_rows="17" rows_capped="1"/>
<rule name="naming-series" count="325" shown_rows="0" rows_capped="1"/>
<rule name="naming-underscore" count="0" shown_rows="0" rows_capped="0"/>
<rule name="naming-case" count="50" shown_rows="0" rows_capped="1"/>
<rule name="naming-predicate" count="0" shown_rows="0" rows_capped="0"/>
<rule name="naming-setter" count="1" shown_rows="0" rows_capped="1"/>
<rule name="naming-confusable" count="152" shown_rows="18" rows_capped="1"/>
<rule name="naming-uninformative" count="0" shown_rows="0" rows_capped="0"/>
<rule name="atom-comma-operator" count="1" shown_rows="0" rows_capped="1"/>
<rule name="atom-embedded-crement" count="90" shown_rows="12" rows_capped="1"/>
<rule name="atom-assign-as-value" count="48" shown_rows="9" rows_capped="1"/>
<rule name="atom-nested-ternary" count="75" shown_rows="14" rows_capped="1"/>
… [700 more display lines; full output is 70694 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --lint-rules=test/lintrulesfix/rules`

*User lint rules (YAML, ast-grep style) from a directory.*

`````
<!-- ripwire lint: [AST]-only checks (descriptive facts, not gates). rule=the check; sev=user-rule severity; in=enclosing symbol NAME (the same spelling is a fan-in COUNT in for/pack-task/exemplar). A rule named atom-X is an atom of confusion (Gopstein, FSE 2017): a C-family shape that misleads READERS, C/C++/ObjC/CUDA only. Each rule is scanned under its OWN match budget, so no rule is ever starved by a noisier one. A rule that spends its whole budget carries count_capped="1" — its count= is then a FLOOR (that rule's raw captures reached the per-rule budget; only its own matches can cap it); findings_capped="1" on the root ⇒ at least one PRINTED rule row is a floor (never inherited from a rule lint-select/lint-ignore dropped), and the root then also carries counts_floor="1" and capped="1": findings= and total= are floors, rows exist that no page holds. Absent = nothing was capped and every count= is a total. raise the default cap with limit=N (offset=M pages; a cut listing carries total=/has_more=/next_offset= so a paging loop can continue from it). On the root, shown=/capped= are the ROW-COUNT pair (rows printed vs whether the DEFAULT payload byte-cap trimmed them, absent an explicit limit=) — a different fact from the per-rule count_capped="1" above, which is a MATCH-BUDGET floor on one rule's own count=; findings= is the true total unless findings_capped="1" floors it. A rule row's applicable="0" ⇒ NONE of its registered languages (the lint-catalog listing) are present in this corpus at all — its count="0" is structural inertness, never a measurement; the root's inert_rules=N tallies how many printed rows that is true for. lint-select=/lint-ignore=PREFIX[,...] narrow the printed rows to a family (e.g. cache-); the root then carries selected="K of N" plus the raw select=/ignore= you passed. naming_locals="1" on the root ⇒ the opt-in naming-locals modifier was on (the naming-* rules also read local variables inside already-flagged functions); absent ⇒ off, and the naming-* counts cover declarations only. Each rule row's own shown_rows=/rows_capped= is how many of THAT rule's rows fall inside the printed <f> window (the root's shown=/capped= trims a SORTED PREFIX of the combined findings, so a rule whose rows all sort past the cut carries shown_rows="0" rows_capped="1" while its count= stays the true total — never confuse a capped-away rule with one that measured zero); this is a DIFFERENT fact from the row's own count_capped="1" above (that rule's own raw-capture stream hit its per-rule match budget) — the two can disagree on the same row. A lint-rules row's compiled="0" ⇒ that rule's tree-sitter QUERY failed to compile for every linked grammar (a malformed or misspelled pattern) — its count="0" never ran at all, a different claim from applicable="0" above (a well-formed query whose declared language just is not in this corpus) and from an ordinary count="0" (a well-formed query that ran and found nothing); absent ⇒ the query compiled. -->
<lint findings="5" shown="5" capped="0" root=".">
<rule name="broken-query" sev="error" count="0" shown_rows="0" rows_capped="0" compiled="0"/>
<rule name="no-printf" sev="warn" count="5" shown_rows="5" rows_capped="0"/>
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
[math degraded] lint-rules: malformed rule file skipped  (lintrules.h:278, auto rw::parseLintRuleFile(const std::string &, std::string_view, std::vector<LintRule> &)::(anonymous class)::operator()(std::size_t, const char *) const — logged once per site)
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
<!-- ripwire lint: [AST]-only checks (descriptive facts, not gates). rule=the check; sev=user-rule severity; in=enclosing symbol NAME (the same spelling is a fan-in COUNT in for/pack-task/exemplar). A rule named atom-X is an atom of confusion (Gopstein, FSE 2017): a C-family shape that misleads READERS, C/C++/ObjC/CUDA only. Each rule is scanned under its OWN match budget, so no rule is ever starved by a noisier one. A rule that spends its whole budget carries count_capped="1" — its count= is then a FLOOR (that rule's raw captures reached the per-rule budget; only its own matches can cap it); findings_capped="1" on the root ⇒ at least one PRINTED rule row is a floor (never inherited from a rule lint-select/lint-ignore dropped), and the root then also carries counts_floor="1" and capped="1": findings= and total= are floors, rows exist that no page holds. Absent = nothing was capped and every count= is a total. raise the default cap with limit=N (offset=M pages; a cut listing carries total=/has_more=/next_offset= so a paging loop can continue from it). On the root, shown=/capped= are the ROW-COUNT pair (rows printed vs whether the DEFAULT payload byte-cap trimmed them, absent an explicit limit=) — a different fact from the per-rule count_capped="1" above, which is a MATCH-BUDGET floor on one rule's own count=; findings= is the true total unless findings_capped="1" floors it. A rule row's applicable="0" ⇒ NONE of its registered languages (the lint-catalog listing) are present in this corpus at all — its count="0" is structural inertness, never a measurement; the root's inert_rules=N tallies how many printed rows that is true for. lint-select=/lint-ignore=PREFIX[,...] narrow the printed rows to a family (e.g. cache-); the root then carries selected="K of N" plus the raw select=/ignore= you passed. naming_locals="1" on the root ⇒ the opt-in naming-locals modifier was on (the naming-* rules also read local variables inside already-flagged functions); absent ⇒ off, and the naming-* counts cover declarations only. Each rule row's own shown_rows=/rows_capped= is how many of THAT rule's rows fall inside the printed <f> window (the root's shown=/capped= trims a SORTED PREFIX of the combined findings, so a rule whose rows all sort past the cut carries shown_rows="0" rows_capped="1" while its count= stays the true total — never confuse a capped-away rule with one that measured zero); this is a DIFFERENT fact from the row's own count_capped="1" above (that rule's own raw-capture stream hit its per-rule match budget) — the two can disagree on the same row. A lint-rules row's compiled="0" ⇒ that rule's tree-sitter QUERY failed to compile for every linked grammar (a malformed or misspelled pattern) — its count="0" never ran at all, a different claim from applicable="0" above (a well-formed query whose declared language just is not in this corpus) and from an ordinary count="0" (a well-formed query that ran and found nothing); absent ⇒ the query compiled. -->
<!-- with-profile: heat_* on a finding = MEASURED inclusive totals of the joined #PROF_TSV scope — the nearest PROFILE_SCOPE site at/above the finding inside its own enclosing symbol. Columns are whatever counter tier the profiled run armed; an ABSENT heat column was not measured, never zero. heat_joined= on the root counts annotated findings; 0 is honest (no finding sits inside a profiled scope), never an error. -->
<lint findings="1" shown="1" capped="0" heat_joined="1" root=".">
<rule name="c-style-cast" count="0" shown_rows="0" rows_capped="0"/>
<rule name="goto" count="0" shown_rows="0" rows_capped="0"/>
<rule name="do-while" count="0" shown_rows="0" rows_capped="0"/>
<rule name="unsafe-c-fn" count="0" shown_rows="0" rows_capped="0"/>
<rule name="weak-crypto" count="0" shown_rows="0" rows_capped="0"/>
<rule name="redundant-parens" count="0" shown_rows="0" rows_capped="0"/>
<rule name="suspicious-semicolon" count="0" shown_rows="0" rows_capped="0"/>
<rule name="typedef-over-using" count="0" shown_rows="0" rows_capped="0"/>
<rule name="magic-number" count="0" shown_rows="0" rows_capped="0"/>
<rule name="empty-catch" count="0" shown_rows="0" rows_capped="0"/>
<rule name="self-assign" count="0" shown_rows="0" rows_capped="0"/>
<rule name="large-function" count="0" shown_rows="0" rows_capped="0"/>
<rule name="deep-nesting" count="0" shown_rows="0" rows_capped="0"/>
<rule name="inconsistent-return" count="0" shown_rows="0" rows_capped="0"/>
<rule name="unreachable-code" count="0" shown_rows="0" rows_capped="0"/>
<rule name="naming-short" count="0" shown_rows="0" rows_capped="0"/>
<rule name="naming-wordy" count="0" shown_rows="0" rows_capped="0"/>
<rule name="naming-series" count="0" shown_rows="0" rows_capped="0"/>
<rule name="naming-underscore" count="0" shown_rows="0" rows_capped="0"/>
<rule name="naming-case" count="0" shown_rows="0" rows_capped="0"/>
<rule name="naming-predicate" count="0" shown_rows="0" rows_capped="0"/>
<rule name="naming-setter" count="0" shown_rows="0" rows_capped="0"/>
<rule name="naming-confusable" count="0" shown_rows="0" rows_capped="0"/>
<rule name="naming-uninformative" count="0" shown_rows="0" rows_capped="0"/>
<rule name="atom-comma-operator" count="0" shown_rows="0" rows_capped="0"/>
<rule name="atom-embedded-crement" count="0" shown_rows="0" rows_capped="0"/>
<rule name="atom-assign-as-value" count="0" shown_rows="0" rows_capped="0"/>
… [14 more display lines; full output is 6520 bytes on 1 raw line(s)]
`````

The joined finding — past the display cut above, extracted so the join is visible:

`````
<f rule="cache-pointer-chase-loop" p="src/x.cpp:11" in="walk" heat_scope="walk: chase pass" heat_calls="12" heat_total_ms="48.500" heat_l1d_mpki="7.250">p = p-&gt;next</f>
`````

## `./build/ripwire . --communities`

*Cluster the call graph into cohesive modules.*

`````
<!-- ripwire communities: cohesive call-graph modules (Louvain); bridge=cross-module edges; isolated=call-graph-edgeless symbols; drill= names the verb that takes an id= from a row below. On each module row size= is its TRUE member count while shown=/capped= describe the member list printed here: this listing is fixed at the 5 top-ranked members and is NOT widened by limit=/offset= (those page the MODULE rows). capped=1 means members were dropped; drill= names the verb that pages the full member list of one module. raise the default cap with limit=N (offset=M pages; a cut listing carries total=/has_more=/next_offset= so a paging loop can continue from it). counts_floor="1": every graph-derived count here is a FLOOR, never a total. Call edges are extracted from source text by NAME, so dynamic dispatch, callbacks, macros and cross-language calls can be missing; read a zero as "none found", never as "none exists". graph_ambiguous=/graph_unresolved= are the whole graph's resolver gauge (calls split over several defs / calls whose in-repo defs were all language-filtered), the map header's ambiguous=/unresolved=. pr_iters=pagerank-power-iterations(stop:L1-residual-below-tol,else-ceiling) pr_converged=0-only-when-ceiling-hit-first(absent=converged;no-such-attr=not-pagerank-ordered) -->
<!-- root= on this element is the crawl root every p= below is RELATIVE to (single-root runs only; absent => p= is the path ingest itself used, unchanged). -->
<communities drill="--community=ID" modules="1081" shown_modules="30" modules_capped="1" bridges="1528" shown_bridges="12" bridges_capped="1" isolated="8131" isolated_decl="2004" isolated_header="1018" isolated_source="2712" isolated_doc="2397" connected_singletons="0" symbols="13849" total="1081" h … [line truncated: 137 more bytes on this line]
<community id="2897" size="520" dir="src" label="src::min@infra/fastmath.h:51:2347 [run,write,emit]" shown="5" capped="1">
<member t="method" n="empty" p="src/notes.h:431"/>
<member t="method" n="empty" p="src/scipoverlay.h:106"/>
<member t="fn" n="min" p="src/infra/fastmath.h:51"/>
<member t="method" n="reserve" p="src/mergescout.h:347"/>
<member t="fn" n="escapeXml" p="src/serialize.h:124"/>
</community>
<community id="2920" size="393" dir="src" label="src::VERIFY@infra/Diagnostics.h:172:8901 [compute,apply,resolve]" shown="5" capped="1">
<member t="method" n="size" p="src/infra/svector.h:285"/>
<member t="fn" n="max" p="src/infra/fastmath.h:54"/>
<member t="method" n="end" p="src/infra/svector.h:270"/>
<member t="method" n="end" p="src/infra/svector.h:272"/>
<member t="macro" n="VERIFY" p="src/infra/Diagnostics.h:172"/>
</community>
<community id="2887" size="441" dir="src" label="src::emplace@infra/svector.h:408:22477 [parse,resolve,pack]" shown="5" capped="1">
<member t="method" n="find" p="src/ingest_model.h:385"/>
<member t="method" n="find" p="src/graph.h:3782"/>
<member t="method" n="find" p="src/notes.h:434"/>
<member t="method" n="back" p="src/infra/svector.h:263"/>
<member t="method" n="back" p="src/infra/svector.h:264"/>
</community>
<community id="2886" size="360" dir="src" label="src::assign@infra/svector.h:342:19905 [compute,add,resolve]" shown="5" capped="1">
<member t="method" n="push_back" p="src/infra/svector.h:326"/>
<member t="method" n="empty" p="src/infra/svector.h:284"/>
<member t="method" n="push_back" p="src/infra/svector.h:331"/>
<member t="method" n="reserve" p="src/infra/svector.h:294"/>
<member t="fn" n="fnv1a64" p="src/arch.h:507"/>
… [187 more display lines; full output is 16941 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --zoom`

*Nested module hierarchy (multi-level Louvain) + cross-module bridges — levels_shown="2" of levels= BY DEFAULT over the 40 largest top modules (~8 KB, where the whole tree is ~220 KB); a module AT the cut carries children=.*

`````
<!-- ripwire zoom: NESTED module hierarchy (multi-level Louvain); indent = one level deeper; module = dominant-dir(symbol-count); leaf lists top-ranked symbols; bridge = cross-top-module call traffic. symbols= is the whole corpus; isolated= is the symbols in NO top-level module (a group of one — the same rule that makes top_modules= count only groups of 2 or more), and they reconcile exactly: symbols= equals isolated= plus the sum of the TOP-LEVEL size= values, every one of them, including any this page did not print. On a level-0 module size= is its true member count and shown=/capped= describe the member list printed here, which is fixed at the 5 top-ranked members and is not widened by limit=/offset= (those page the TOP-LEVEL modules); the community drill verb pages one module's full member list by its level-0 id. A module above level 0 lists every child module, so it carries no shown=/capped= pair. levels_shown= is how many of the levels= this document prints from the top (default 2; the zoom-levels flag sets it, 0 = all): a module AT the cut carries children= (its child modules, none printed) instead of nesting. The top-level module rows are a WINDOW (shown=/capped=/total=/next_offset=, default 40 largest; limit=/offset= page it) and next= pastes the next page. counts_floor="1": every graph-derived count here is a FLOOR, never a total. Call edges are extracted from source text by NAME, so dynamic dispatch, callbacks, macros and cross-language calls can be missing; read a zero as "none found", never as "none exists". graph_ambiguous=/graph_unresolved= are the whole graph's resolver gauge (calls split over several defs / calls whose in-repo defs were all language-filtered), the map header's ambiguous=/unresolved=. pr_iters=pagerank-power-iterations(stop:L1-residual-below-tol,else-ceiling) pr_converged=0-only-when-ceiling-hit-first(absent=converged;no-such-attr=not-pagerank-ordered) -->
<zoom levels="5" levels_shown="2" top_modules="398" symbols="13849" isolated="8131" shown="40" capped="1" total="398" has_more="1" next_offset="40" offset="0" limit="0" pr_iters="31" graph_ambiguous="6085" graph_unresolved="3093" counts_floor="1" next="--zoom --offset=40">
<module level="4" id="488" size="3320" dir="./src">
<module level="3" id="488" size="3320" dir="./src" children="5">
</module>
</module>
<module level="4" id="253" size="610" dir="./bench">
<module level="3" id="253" size="294" dir="./bench/agentloop" children="5">
</module>
<module level="3" id="516" size="259" dir="./bench" children="4">
</module>
<module level="3" id="1772" size="57" dir="./bench/recalleval" children="2">
</module>
</module>
<module level="4" id="47" size="67" dir=".">
<module level="3" id="47" size="67" dir="." children="1">
</module>
</module>
<module level="4" id="8525" size="32" dir="./test/zoomfix/core">
<module level="3" id="8527" size="32" dir="./test/zoomfix/core" children="1">
</module>
</module>
<module level="4" id="6481" size="45" dir="./test/massfix">
<module level="3" id="6483" size="45" dir="./test/massfix" children="1">
</module>
</module>
<module level="4" id="5184" size="43" dir="./test">
<module level="3" id="5186" size="43" dir="./test" children="1">
</module>
</module>
… [137 more display lines; full output is 8158 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --zoom --zoom-levels=3`

*The restoring knob: --zoom-levels=N prints N levels (0 = the whole tree); here three, ~11 KB.*

`````
<!-- ripwire zoom: NESTED module hierarchy (multi-level Louvain); indent = one level deeper; module = dominant-dir(symbol-count); leaf lists top-ranked symbols; bridge = cross-top-module call traffic. symbols= is the whole corpus; isolated= is the symbols in NO top-level module (a group of one — the same rule that makes top_modules= count only groups of 2 or more), and they reconcile exactly: symbols= equals isolated= plus the sum of the TOP-LEVEL size= values, every one of them, including any this page did not print. On a level-0 module size= is its true member count and shown=/capped= describe the member list printed here, which is fixed at the 5 top-ranked members and is not widened by limit=/offset= (those page the TOP-LEVEL modules); the community drill verb pages one module's full member list by its level-0 id. A module above level 0 lists every child module, so it carries no shown=/capped= pair. levels_shown= is how many of the levels= this document prints from the top (default 2; the zoom-levels flag sets it, 0 = all): a module AT the cut carries children= (its child modules, none printed) instead of nesting. The top-level module rows are a WINDOW (shown=/capped=/total=/next_offset=, default 40 largest; limit=/offset= page it) and next= pastes the next page. counts_floor="1": every graph-derived count here is a FLOOR, never a total. Call edges are extracted from source text by NAME, so dynamic dispatch, callbacks, macros and cross-language calls can be missing; read a zero as "none found", never as "none exists". graph_ambiguous=/graph_unresolved= are the whole graph's resolver gauge (calls split over several defs / calls whose in-repo defs were all language-filtered), the map header's ambiguous=/unresolved=. pr_iters=pagerank-power-iterations(stop:L1-residual-below-tol,else-ceiling) pr_converged=0-only-when-ceiling-hit-first(absent=converged;no-such-attr=not-pagerank-ordered) -->
<zoom levels="5" levels_shown="3" top_modules="398" symbols="13849" isolated="8131" shown="40" capped="1" total="398" has_more="1" next_offset="40" offset="0" limit="0" pr_iters="31" graph_ambiguous="6085" graph_unresolved="3093" counts_floor="1" next="--zoom --offset=40">
<module level="4" id="488" size="3320" dir="./src">
<module level="3" id="488" size="3320" dir="./src">
<module level="2" id="491" size="3071" dir="./src" children="40">
</module>
<module level="2" id="3246" size="144" dir="./src" children="7">
</module>
<module level="2" id="515" size="60" dir="./src/infra" children="4">
</module>
<module level="2" id="3218" size="10" dir="./src/infra" children="2">
</module>
<module level="2" id="3357" size="35" dir="./src" children="3">
</module>
</module>
</module>
<module level="4" id="253" size="610" dir="./bench">
<module level="3" id="253" size="294" dir="./bench/agentloop">
<module level="2" id="255" size="98" dir="./bench/agentloop" children="7">
</module>
<module level="2" id="254" size="77" dir="./bench/agentloop" children="5">
</module>
<module level="2" id="253" size="58" dir="./docs" children="5">
</module>
<module level="2" id="444" size="33" dir="./bench/arb" children="2">
</module>
<module level="2" id="610" size="28" dir="./bench/ensemblecal" children="3">
</module>
</module>
<module level="3" id="516" size="259" dir="./bench">
… [245 more display lines; full output is 11873 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --report`

*Architecture summary (modules, god-files, cycles) as markdown.*

`````
<!-- ripwire markdown: no run of 4-or-more backticks in this output — safe to embed inside a wider fence -->

# ripwire architecture report

1588 files · 13849 symbols · 17058 edges · 1081 modules (8131 call-graph isolated)

Root: `.`

Call-graph isolate provenance: 2004 declaration, 1018 header, 2712 source, 2397 document; 0 connected Louvain singletons

## Modules (call-graph clusters; showing 12 of 1081)
- **src::min@infra/fastmath.h:51:2347 [run,write,emit]** — 520 symbols
- **src::emplace@infra/svector.h:408:22477 [parse,resolve,pack]** — 441 symbols
- **src::VERIFY@infra/Diagnostics.h:172:8901 [compute,apply,resolve]** — 393 symbols
- **src::assign@infra/svector.h:342:19905 [compute,add,resolve]** — 360 symbols
- **src::DEGRADED_PATH_ALERT@infra/Diagnostics.h:158:8137 [resolve,compute,collect]** — 145 symbols
- **src::str@ingest_cache.h:1082:97946 [read,write,scan]** — 55 symbols
- **src/infra::buf@svector.h:125:8942 [insert,pack,render]** — 40 symbols
- **src::sliceKindIs@slice.h:290:19182 [pop,match]** — 29 symbols
- **src::PROFILE_SCOPE_DESCRIBE@infra/profileScope.h:1322:44988 [read,check]** — 27 symbols
- **src/infra::read@profilePmc.h:424:18042 [read,run,measure]** — 19 symbols
- **src::ackMapKey@quality.h:3866:234409 [read,count,find]** — 19 symbols
- **bench/headtohead/r4-2026-08-06::timed@r4_worker.py:67:3882 [load,dedup]** — 15 symbols

## God files (most depended-on; showing 10 of 262)
- `src/model.h` — 76 dependents
- `src/infra/Diagnostics.h` — 44 dependents
- `src/serialize.h` — 34 dependents
- `src/graph.h` — 33 dependents
- `src/ingest.h` — 23 dependents
… [31 more lines, 3561 bytes total]
`````

## `./build/ripwire . --seams`

*Cross-module call seams no test reaches. NOW carries seam_pairs/shown/capped.*

`````
<!-- ripwire seams: cross-directory call edges NO test reaches (untested integration seams; a fact, not a mandate). module = parent dir; seam = caller-dir -> callee-dir, spelled from= and to=. Each seam pages its own edge rows with shown=/capped=; an edge names caller= at site p= calling callee= at site cp=. UNIT: untested= here counts cross-directory call EDGES. The test gate verb spells untested= over impacted SYMBOLS and the flip verb over the defs a gate lights, so the three numbers count three different things and must never be compared or summed across verbs. raise the default cap with limit=N (offset=M pages; a cut listing carries total=/has_more=/next_offset= so a paging loop can continue from it). counts_floor="1": every graph-derived count here is a FLOOR, never a total. Call edges are extracted from source text by NAME, so dynamic dispatch, callbacks, macros and cross-language calls can be missing; read a zero as "none found", never as "none exists". graph_ambiguous=/graph_unresolved= are the whole graph's resolver gauge (calls split over several defs / calls whose in-repo defs were all language-filtered), the map header's ambiguous=/unresolved=. pr_iters=pagerank-power-iterations(stop:L1-residual-below-tol,else-ceiling) pr_converged=0-only-when-ceiling-hit-first(absent=converged;no-such-attr=not-pagerank-ordered) -->
<!-- root= on this element is the crawl root every p= below is RELATIVE to (single-root runs only; absent => p= is the path ingest itself used, unchanged). -->
<seams modules="300" bridges="4933" untested="4146" test_files="1106" seam_pairs="40" shown="20" capped="1" total="40" has_more="1" next_offset="20" offset="0" limit="0" pr_iters="31" root="." graph_ambiguous="6085" graph_unresolved="3093" counts_floor="1">
<seam from="src" to="src/infra" untested="3943" shown="5" capped="1">
<edge caller="gitOneLine" p="src/quality.h:1013" callee="shSingleQuote" cp="src/infra/jsonesc.h:268"/>
<edge caller="popenTrimmed" p="src/gitmine.h:223" callee="readByteSafeLine" cp="src/infra/stdinline.h:44"/>
<edge caller="popenTrimmed" p="src/gitmine.h:223" callee="back" cp="src/infra/svector.h:263"/>
<edge caller="popenTrimmed" p="src/gitmine.h:223" callee="back" cp="src/infra/svector.h:264"/>
<edge caller="popenTrimmed" p="src/gitmine.h:223" callee="pop_back" cp="src/infra/svector.h:340"/>
</seam>
<seam from="bench" to="src/infra" untested="87" shown="5" capped="1">
<edge caller="aggregateMax" p="bench/bench_ordered_map.cpp:85" callee="max" cp="src/infra/fastmath.h:54"/>
<edge caller="applyOne" p="bench/bench_svector_diff.cpp:166" callee="pop_back" cp="src/infra/svector.h:340"/>
<edge caller="applyOne" p="bench/bench_svector_diff.cpp:166" callee="emplace_back" cp="src/infra/svector.h:333"/>
<edge caller="applyOne" p="bench/bench_svector_diff.cpp:166" callee="shrink_to_fit" cp="src/infra/svector.h:305"/>
<edge caller="infraSortSmall" p="bench/bench_radix_ab.cpp:73" callee="sortKeySmall" cp="src/infra/radixSort.h:79"/>
</seam>
<seam from="." to="docs" untested="24" shown="5" capped="1">
<edge caller="What it saves you, in tokens" p="README.md:1224" callee="EVALS" cp="docs/EVALS.md:1"/>
<edge caller="Measured" p="README.md:1077" callee="EVALS" cp="docs/EVALS.md:1"/>
<edge caller="Graph-Ranked Retrieval: It finds the right files more often than the alternatives" p="README.md:204" callee="EVALS" cp="docs/EVALS.md:1"/>
<edge caller="What it answers" p="README.md:546" callee="COMMANDS" cp="docs/COMMANDS.md:1"/>
<edge caller="Added — `--nonlocal-state`: the mutable state a function can reach, reads and writes kept apart" p="CHANGELOG.md:266" callee="LINEAGE" cp="docs/LINEAGE.md:1"/>
</seam>
<seam from="src" to="test/regexfix" untested="8" shown="5" capped="1">
<edge caller="collectGrepScanPhases" p="src/verbs_grep.h:410" callee="span" cp="test/regexfix/alpha.cpp:14"/>
<edge caller="emitGrepReport" p="src/verbs_grep.h:501" callee="span" cp="test/regexfix/alpha.cpp:14"/>
<edge caller="grepApplySpanTiers" p="src/search.h:2018" callee="span" cp="test/regexfix/alpha.cpp:14"/>
<edge caller="grepHitsJson" p="src/mcpverbs.h:875" callee="span" cp="test/regexfix/alpha.cpp:14"/>
<edge caller="impactText" p="src/mcpverbs.h:2069" callee="span" cp="test/regexfix/alpha.cpp:14"/>
… [91 more display lines; full output is 12150 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --mermaid`

*Module (directory) dependency graph as a Mermaid diagram.*

`````
%% ripwire --mermaid: module (directory) dependency graph — node = dir (symbol count), edge = inter-module calls (>= 3). Render at mermaid.live.
flowchart LR
  subgraph sg0 ["src"]
    n83["src<br/>4586"]
    n84["src/infra<br/>498"]
  end
  subgraph sg1 ["test"]
    n85["test<br/>2726"]
    n163["test/expandmodefix<br/>151"]
    n210["test/massfix<br/>77"]
    n199["test/legofix<br/>60"]
    n230["test/optremarksfix<br/>59"]
    n269["test/sliceflowsensfix<br/>59"]
    n242["test/pyshapefix<br/>58"]
    n220["test/namingconsistencyfix<br/>57"]
    n272["test/swiftshapefix<br/>54"]
    n165["test/expandsibsfix<br/>49"]
  end
  n58["docs<br/>516"]
  subgraph sg3 ["bench"]
    n3["bench<br/>484"]
    n4["bench/agentloop<br/>321"]
    n46["bench/locbench/results/r5_pooling<br/>235"]
    n47["bench/locbench/results/r6_expansion<br/>185"]
    n54["bench/recalleval<br/>108"]
    n40["bench/locbench<br/>104"]
    n35["bench/headtohead/r3-headroom-2026-08-03<br/>100"]
    n42["bench/locbench/results/r1cpp_anchorhop<br/>92"]
    n53["bench/nestcal/r1-2026-08-07<br/>84"]
    n10["bench/arb<br/>79"]
… [18 more lines, 1535 bytes total]
`````

## `./build/ripwire . --owners`

*Bus-factor: recency-weighted author ownership per file.*

`````
<!-- ripwire owners: recency-weighted author ownership (half-life=6mo). bf=1 = one person holds >80% of weighted commits (bus-factor risk); authors=1 files fold into <uniform/> below; pass detail=1 for the full per-file listing. files= means two different things by DEPTH here and is deliberately not renamed: on the ROOT it is how many files were ANALYSED; on the <uniform/> fold it is how many of them collapsed into that one row. With a SYM, of= echoes it and defs= is how many DEFINITIONS that name has: this report covers the file holding the FIRST of them (lowest node id, the same pick around and lego make), so defs= above 1 means the other definitions' files were NOT analysed. Qualify with file:name to choose one. An @FILE:LINE seed rebinds to the innermost definition enclosing that line (sym= names it) and covers exactly that definition's file -->
<!-- at= is the git commit these numbers were computed at; a trailing +dirty means the working tree differed from that commit, so the numbers describe the tree, not the commit -->
<!-- root= on this element is the crawl root every p= below is RELATIVE to (single-root runs only; absent => p= is the path ingest itself used, unchanged). -->
<owners files="1588" root="." at="c7725f3ef">
<uniform authors="1" bf="1" share="1.00" files="1568"/>
<f p="CHANGELOG.md" authors="3" bf="1" top="<author>" share="0.92"/>
<f p="CLAUDE.md" authors="2" bf="1" top="<author>" share="0.82"/>
<f p="README.md" authors="2" bf="1" top="<author>" share="0.99"/>
<f p="bench/PROFILE.md" authors="2" bf="1" top="<author>" share="0.97"/>
<f p="docs/COMMANDS.md" authors="3" bf="1" top="<author>" share="0.99"/>
<f p="docs/EVALS.md" authors="2" bf="1" top="<author>" share="1.00"/>
<f p="docs/METHODOLOGY.md" authors="2" bf="1" top="<author>" share="0.87"/>
<f p="docs/README.md" authors="3" bf="1" top="<author>" share="0.84"/>
<f p="skills/ripwire-efficient/SKILL.md" authors="2" bf="1" top="<author>" share="0.93"/>
<f p="src/cli.h" authors="2" bf="1" top="<author>" share="1.00"/>
<f p="src/infra/profilePmc.h" authors="2" bf="1" top="<author>" share="0.83"/>
<f p="src/infra/profileScope.h" authors="2" bf="1" top="<author>" share="0.91"/>
<f p="src/lanes.h" authors="2" bf="1" top="<author>" share="0.91"/>
<f p="src/taskroute.h" authors="2" bf="1" top="<author>" share="0.87"/>
<f p="src/wrap.h" authors="2" bf="1" top="<author>" share="0.85"/>
<f p="test/planlanescheck.sh" authors="2" bf="1" top="<author>" share="0.82"/>
<f p="test/pmccheck_harness.cpp" authors="2" bf="1" top="<author>" share="0.80"/>
<f p="test/showcase_capture.py" authors="2" bf="1" top="<author>" share="0.94"/>
<f p="test/taskroutecheck.sh" authors="2" bf="1" top="<author>" share="0.89"/>
<f p="test/testgatepagecheck.sh" authors="2" bf="1" top="<author>" share="0.85"/>
</owners>
`````

## `./build/ripwire . --dead-code=src`

*High-confidence internal functions with no caller. NOTE the filter is a path-COMPONENT match: 'src' matches any .../src/... segment; use ./src to pin the root directory.*

`````
<!-- ripwire dead-code: high-confidence source functions with internal linkage and no caller in the indexed tree. A bare-name filter matches by path COMPONENT: filter="src" keeps any path with a src segment at any depth (test/x/src/y.cpp included); anchor with ./ (filter="./src") to pin the root-level directory only. register-macro-excluded= counts symbols excluded because their OWN definition is a registered self-registering test/benchmark macro call (doctest/Catch2 TEST_CASE family, GoogleTest TEST/TEST_F/TEST_P, Google Benchmark BENCHMARK family, plus any name a .ripwire_config register_macros= line adds): such a symbol registers itself through a static initializer the call graph cannot see, so zero in-edges on it is not evidence of anything — never a finding, never gating, absent nothing (0 is printed, not omitted). config-warnings= counts two DISCLOSED .ripwire_config problems, each also written to stderr — an unrecognized key, and a register_macros= name matching no indexed symbol — never gating, present only when non-zero. Graph evidence is local to the indexed tree; verify before deleting. counts_floor="1": every graph-derived count here is a FLOOR, never a total. Call edges are extracted from source text by NAME, so dynamic dispatch, callbacks, macros and cross-language calls can be missing; read a zero as "none found", never as "none exists". graph_ambiguous=/graph_unresolved= are the whole graph's resolver gauge (calls split over several defs / calls whose in-repo defs were all language-filtered), the map header's ambiguous=/unresolved=. -->
<dead-code count="1" confidence="high" evidence="internal-linkage+zero-callers" register-macro-excluded="0" filter="src" root="." graph_ambiguous="6085" graph_unresolved="3093" counts_floor="1">
<d n="unused_helper" t="fn" p="test/archmetricsfix/src/orphan/util.cpp" l="1"/>
</dead-code>
`````

## `./build/ripwire . --exercises=test/regression.sh`

*Which symbols a TEST FILE exercises — the reverse direction of --affected.*

`````
<!-- ripwire exercises: the NON-TEST symbols this test transitively calls into — what it covers (the inverse of the affected verb). <t> = the seed test files the pattern matched; <s> = the covered symbols, PageRank desc. harness=script|mixed says the seed set contains shell gates, whose subprocess coverage this walk cannot see. counts_floor="1": every graph-derived count here is a FLOOR, never a total. Call edges are extracted from source text by NAME, so dynamic dispatch, callbacks, macros and cross-language calls can be missing; read a zero as "none found", never as "none exists". graph_ambiguous=/graph_unresolved= are the whole graph's resolver gauge (calls split over several defs / calls whose in-repo defs were all language-filtered), the map header's ambiguous=/unresolved=. pr_iters=pagerank-power-iterations(stop:L1-residual-below-tol,else-ceiling) pr_converged=0-only-when-ceiling-hit-first(absent=converged;no-such-attr=not-pagerank-ordered) -->
<!-- root= on this element is the crawl root every p= below is RELATIVE to (single-root runs only; absent => p= is the path ingest itself used, unchanged). -->
<exercises of="test/regression.sh" seed_files="1" shown_seed_files="1" seed_files_capped="0" test_symbols="3" reaches="0" harness="script" note="a shell gate invokes the compiled binary as a subprocess; script-to-binary edges are not modelled, so reaches= counts call-graph reach only and cannot see  … [line truncated: 136 more bytes on this line]
<t p="test/regression.sh" run="bash test/regression.sh"/>
</exercises>
`````

## `./build/ripwire . --community=0`

*Drill into ONE call-graph community by id — the drill= the --communities output itself advertises.*

`````
<!-- ripwire community: ONE module from the communities/zoom partition — its ranked members and its bridge edges to other modules. size= is the module's TRUE member count; shown=/capped= are this page. partition= is the FULL label space (every id 0..partition-1, incl. isolated singletons) — the range the id= argument ranges over; modules= counts the NON-isolated communities (size>=2), the SAME predicate the communities-listing verb's modules= uses, so parent and child agree. counts_floor="1": every graph-derived count here is a FLOOR, never a total. Call edges are extracted from source text by NAME, so dynamic dispatch, callbacks, macros and cross-language calls can be missing; read a zero as "none found", never as "none exists". graph_ambiguous=/graph_unresolved= are the whole graph's resolver gauge (calls split over several defs / calls whose in-repo defs were all language-filtered), the map header's ambiguous=/unresolved=. pr_iters=pagerank-power-iterations(stop:L1-residual-below-tol,else-ceiling) pr_converged=0-only-when-ceiling-hit-first(absent=converged;no-such-attr=not-pagerank-ordered) -->
<!-- root= on this element is the crawl root every p= below is RELATIVE to (single-root runs only; absent => p= is the path ingest itself used, unchanged). -->
<community id="0" size="1" dir=".codex-plugin" label=".codex-plugin::name@plugin.json:2:4" bridges="0" shown_bridges="0" bridges_capped="0" partition="9212" modules="1081" shown="1" capped="0" pr_iters="31" root="." graph_ambiguous="6085" graph_unresolved="3093" counts_floor="1">
<member t="sec" n="name" p=".codex-plugin/plugin.json:2"/>
</community>
`````

## `./build/ripwire . --quality-delta`

*On a CLEAN tree: nothing got worse, exit 0. The gating shape is in the sandbox section below.*

**wall time: 3.56s**

`````
<!-- ripwire quality-delta: only what a change made WORSE against the floor baseline= names below. Descriptive: weigh and fix the real ones, do not game the number (a wrong abstraction beats a low score). TEN KINDS, and kind= on every row names which one: complexity over the ccx bar, verbosity (LOC), nesting, params, duplication, dead-code, api-surface (new public contract drift), error-masking, short-horizon-churn, new-clone-of-reused-helper. THREE independent axes, in this order: (1) acked findings are suppressed entirely (acked= counts them); (2) ORIGIN — a finding on a symbol that EXISTED at the baseline is preexisting-worse (no origin attribute), one that exists only because the code is NEW carries origin="new-symbol"; (3) MATERIALITY — a small numeric delta is sev="minor", and minor= counts them. EXIT 2 fires only on preexisting-worse AND major, the gating= count; new-symbol rows never gate, so exit 0 is NOT a verdict on them — nothing that existed got worse, but the new debt is yours: read them. Clone kinds are new-symbol only when EVERY member is new; short-horizon-churn is preexisting by construction. preexisting-worse= and new-symbol= partition regressions=. stale= is a FOURTH axis, never gating and never counted in regressions=: rows in the .ripwire_quality_acks ledger whose target no longer applies. register-macro-excluded= is a FLOOR, not a finding: symbols this run excluded from the dead-code kind because their own definition is a registered self-registering test/benchmark macro call. Never gates, never counted in regressions=, printed even at zero (zero means none excluded, not that the check did not run). A gating row's next= is the one pasteable follow-up: expand on FILE:NAME, the body to fix (a duplication row names a SET and carries none). bar= on a complexity/verbosity/nesting/params row is the threshold now= is judged against (ccx 15, loc 60, nest 4, params 5). baseline="git-HEAD" means no sidecar existed, so the working tree was auto-compared against the HEAD tree — anything already committed cannot appear. at= is the git commit (plus a dirty marker when the working tree differs) this list was computed at. The registered families are doctest/Catch2 TEST_CASE, GoogleTest TEST/TEST_F/TEST_P, Google Benchmark BENCHMARK, plus any name a .ripwire_config register_macros= line adds; each registers itself through a static initializer the call graph cannot see, so zero in-edges on one is not evidence of anything. IDENTITY across a rename or a move: a finding is keyed path::scope::name, which a rename would destroy, so the baseline and the .ripwire_quality_acks ledger are both re-filed into the CURRENT tree's identity before either is read, by two EXACT mechanisms — git's own rename record, and equality of a whitespace-and-name-scrubbed body hash — never a similarity heuristic. renames= is how many rename pairs were read, rename_window_commits= how deep the commit window went, acked_by_rename= and acked_by_content= how many of the acked= suppressions each mechanism is responsible for. Three appear ONLY when true, so an absent one is not a silent no: renames_window_truncated= (history is deeper than the window), renames_truncated= (the pair cap was hit), renames_ambiguous= (an ancestor two current symbols both claim — refused rather than guessed). ORIGIN reads the re-filed baseline too, so a regression carried in with a rename is judged preexisting-worse and GATES instead of slipping through as new-symbol. FLOORS, stated because silence here would read as a guarantee: the two clone kinds key on a member-SET hash and are NOT re-filed, so a clone ack still dies on a rename; ORIGIN follows the rename record but never content, because the baseline stores no content id at all; and a move git recorded no rename for still reads as new-symbol. Each sa row carries key= (the ack identity as stored) and why=, which is target-gone (the key names no symbol or group any more) or finding-gone (the target survived, this kind just does not fire on it). sym= and p=path:line name WHICH ack it is, and are present exactly when the key still names a live symbol: on every finding-gone row, on none of the target-gone rows (there is nothing left to name), and on neither clone kind — a clone key hashes a member SET that no single symbol carries, so those rows are unnameable by construction rather than guessed at. Hygiene disclosure only — the ledger file is never auto-edited. -->
<quality-delta baseline="git-HEAD" regressions="0" minor="0" acked="0" stale="19" preexisting-worse="0" new-symbol="0" gating="0" register-macro-excluded="3" at="c7725f3ef" renames="55" rename_window_commits="400" acked_by_rename="0" acked_by_content="0" renames_window_truncated="1">
<sa kind="api-surface" key="298e798c7f075715" why="target-gone"/>
<sa kind="api-surface" key="5a07390012b46e06" why="target-gone"/>
<sa kind="api-surface:new-symbol" key="1926b0d9e94541a0" why="target-gone"/>
<sa kind="api-surface:new-symbol" key="79625906f9f71ad0" why="target-gone"/>
<sa kind="api-surface:new-symbol" key="995375dfa4e63104" why="target-gone"/>
<sa kind="complexity" key="4b309450f25c2b44" why="finding-gone" sym="src/ingest.cpp::rw::ingest" p="src/ingest.cpp:191"/>
<sa kind="complexity" key="53a1214d5505fa41" why="finding-gone" sym="main" p="src/main.cpp:2634"/>
<sa kind="duplication" key="160ac41979d9ebaf" why="finding-gone"/>
<sa kind="duplication" key="af2e342eda9648ed" why="finding-gone"/>
<sa kind="duplication" key="c8b32435256b863e" why="finding-gone"/>
<sa kind="nesting" key="1bded1f8f88d3b85" why="finding-gone" sym="src/slice.h::slicev::sliceFlowCompute" p="src/slice.h:2286"/>
<sa kind="nesting" key="3c07d993bfdbce53" why="finding-gone" sym="src/slice.h::slicev::sliceBundleText" p="src/slice.h:2685"/>
<sa kind="new-clone-of-reused-helper" key="0e9742973611fd71" why="finding-gone"/>
<sa kind="new-clone-of-reused-helper" key="5a0ff811529d5c95" why="finding-gone"/>
<sa kind="new-clone-of-reused-helper" key="c8b32435256b863e" why="finding-gone"/>
<sa kind="new-clone-of-reused-helper" key="d11c67611bc73d49" why="finding-gone"/>
<sa kind="params" key="f6dedd851e4b2a25" why="finding-gone" sym="src/slice.h::slicev::sliceWalk" p="src/slice.h:1122"/>
<sa kind="verbosity" key="15061a69cb5b451f" why="finding-gone" sym="src/packtask.h::rw::packTaskHeaderText" p="src/packtask.h:226"/>
<sa kind="verbosity" key="53a1214d5505fa41" why="finding-gone" sym="main" p="src/main.cpp:2634"/>
</quality-delta>
`````

stderr:

`````
ripwire: no ./.ripwire_quality_baseline — auto-comparing the working tree vs git HEAD (commit the baseline with --quality-baseline to pin it)
`````

## `./build/ripwire . --edit-check=rankGraphTeleport`

*Fast per-symbol post-edit contract check vs git HEAD (unchanged on a clean tree).*

`````
<!-- ripwire edit-check: SYM's contract (param count + publicness) NOW vs git HEAD — unchanged/new-symbol/contract-change — plus its 1-hop callers. A caller is flagged incompatible="1" when its argument count was reliably counted and NO definition in the folded set could accept it: every one has a FIXED arity that disagrees. A variadic, defaulted or implicit-receiver definition (a Python/Ruby method, whose params counts the self/cls the call site never writes) has no fixed arity and is never flagged. That makes the ARITY half one-sided — a call the compared definitions could accept is never flagged — but it is NOT a proof that the call site binds to THIS definition. Call edges are matched by NAME, so a receiver-qualified call to a same-named callee this tool does not index (a standard-library or third-party method) is measured against the one definition it does index; a clean, compiling tree can therefore carry a nonzero incompatible= with nothing edited at all, and on a widely-shared name it can be most of that name's callers. Read incompatible= as a fact about the tree as it stands — call sites worth OPENING, not a verdict — and status= as a fact about the edit. Warm path hits the qheadsnap/qsnap cache — never a full quality-delta style recompute. defs= is how many DEFINITIONS at this site (same file, same scope, same name — the overload set) are folded into this one contract; a selector matching more than one SITE is refused instead, so defs= only ever counts overloads. params_was and params_now are the MAX over that set on each side (the same MAX the baseline snapshot stores), and publicness is the OR. That MAX has TWO consequences, in opposite directions. It can read like a break and not be one: adding a WIDER overload beside an unchanged one raises params_now with no existing definition altered, so it reports status="contract-change" with incompatible="0" and a def row still carrying the old parameter count — no seen caller breaks. And it can read like safety and not be: REMOVING an overload whose parameter count is BELOW the MAX moves neither number, because the MAX survives on both sides, while the call site that used the removed definition no longer binds. defs_was=/defs_now= is what closes that: the count of definitions sharing this symbol's DEFINITION SITE — same file, same scope, same name — on each side. That is the population the baseline snapshot buckets by, so the two numbers answer the same question and are equal on an unedited tree. A same-named definition in ANOTHER FILE is a different contract and is counted on neither side, so defs_now= agrees with the root's defs= by construction and only defs_was= can move it. status is therefore the join of THREE was-vs-now facts — the params MAX, publicness, and the definition COUNT — and change= names which of them carried it. change= adds broken-callers when a seen caller is also flagged, but never on its own — for the reason stated at the top: incompatible= describes the TREE and status= describes the EDIT, so a headline must not turn on it. RESIDUAL: an overload whose arity changes BELOW the MAX while the COUNT stays the same moves none of the three. The root's incompatible= is the COUNT of flagged callers (a c row's incompatible="1" is the per-caller flag). sites_l= rides on a flagged row only: a c row's p= is where that CALLER is DEFINED, and sites_l= is the ascending LINE list of its call-role reference sites to this name — the lines to open, the same rows the uses verb prints, including the ones whose argument count could not be counted (so sites_l= can be wider than the evidence the flag rests on). Two calls on one line are ONE site. p= is the definition the selector resolved to; when defs is above 1 EVERY folded definition is listed as its own def row (p=, t=, params=), which is what tells a widened single definition apart from an added overload. At defs="1" no def row is emitted: the root's own p=/t= is that definition, and params_now is its parameter count. next= is the one pasteable follow-up: on a contract-change the uses verb on SYM (the call sites), otherwise the test gate on the definition's file. counts_floor="1" means every count here is a FLOOR, never a total: edges are extracted from source TEXT by NAME. Missing: dynamic dispatch (virtual/interface/duck-typed), a most-vexing-parse declaration with no call expression, a function-pointer/callback bound to more than one function in scope (reassigned, table-indexed, lambda-bound, or address-taken/reference-bound), and a plain-name binding (fp=handler) whose variable type is not PROVABLY a function pointer (a same-file typedef/declarator; a HEADER typedef is missed; auto/template types are read as unpinned, so KEPT). A macro-generated call site is role="macro" only when its name uniquely names an indexed function-like #define (C-family, t="macro"); a shared name stays a plain call, an unindexed macro is no edge. Read a zero as "none found", never as "none exists". graph_ambiguous=/graph_unresolved= are the whole graph's resolver gauge (calls split over several defs / calls whose in-repo defs were all language-filtered), the map header's ambiguous=/unresolved=. COUNTING UNIT differs by verb: callers, callees, edit-check, graph-query and pr-context counts are DISTINCT SYMBOLS (repeated calls from one caller, and calls to two overloads, collapse into ONE row; multiplicity survives only in the call graph's edge weight). The reach counts (impact's reaches=, pr-context's dependents=) are the size of a transitive reach SET, each symbol counted once. The uses verb counts call SITES, one row per occurrence — a larger count there for the same symbol is these units agreeing, not disagreeing. The map header's edges= is a unit again different — distinct (caller,callee) PAIRS — and that document carries neither this marker nor this clause. -->
<edit-check sym="rankGraphTeleport" t="fn" p="src/graph.h:2501" status="unchanged" defs="1" callers="6" incompatible="0" at="c7725f3ef" graph_ambiguous="6085" graph_unresolved="3093" counts_floor="1" root="." next="--test-gate=src/graph.h">
<c n="runEval" p="src/eval.h:168"/>
<c n="rankGraph" p="src/graph.h:2542"/>
<c n="anchoredLexicalRank" p="src/graph.h:3034"/>
<c n="churnRankedGraph" p="src/main.cpp:983"/>
<c n="runDefaultMap" p="src/main.cpp:1098"/>
<c n="getIndex" p="src/mcpindex.h:1104"/>
</edit-check>
`````

## `./build/ripwire . --pr-context`

*No-LLM review-evidence bundle for the working-tree diff (clean tree = empty).*

`````
<!-- ripwire pr-context: no-LLM review-evidence bundle per changed file — defined symbols, their callers, blast radius (transitive dependents), affected tests, co-change partners not in the diff, and owners. base=working-tree. skipped_mode_only=diffs that changed a file's MODE and nothing else (e.g. chmod) excluded from the changed set; a pure RENAME is content-identical too but is NOT excluded — it is a changed file, listed at its new path. files= means two different things by DEPTH here and is deliberately not renamed (15 consumers read the root one): on the ROOT it is the CHANGED file count; on each <impact/> child it is the distinct files dependents= reaches (changed + non-changed), so dependents="0" implies files="0" and vice versa — never an impossible-looking dependents>0/files=0. files_other= on the same <impact/> is the non-changed subset (a changed file's dependents inside OTHER changed files have no <f> row of their own — they are already shown as their own <file> section); it is NOT the <f> row count — see the row-cap sentence below. Files are ordered by BLAST RADIUS (transitive dependents descending, path breaking ties), not alphabetically. sections= on changed-symbols counts a doc file's headings, collapsed into that number instead of one callers-zero row each; count= still counts every INDEXED symbol, sections included, so count minus sections is the number of rows that follow. Every nested list below is a TOP-N subset of its element's own total, fixed per element (impact <f> at 20, per-symbol <caller> at 12, cochange <partner> at 12, tests <test> at 40, owners <author> at 5 — the L0 defaults; max-tokens only lowers these further via the trim ladder, nothing raises them past L0): each capped element carries its own shown=/capped= pair so the cut is never silent — for the untrimmed list use impact=SYM/callers=SYM (blast radius/callers), affected=FILE or situ (tests), cochange (partners), or owners (authors) instead. direction= names which SIDE this bundle reviews (worktree-since-head, head-since-fork, head-since-ref-tip); a no-ref-work row says the base ref's tip IS the merge base, i.e. it carries no divergent work of its own. deterministic. BUDGET: the bundle is budgeted by default — budget_tokens= is the ceiling in force (8000 unless token-budget/max-tokens set it; budget_default=1 says the default applied); est_tokens= prices the WHOLE document this bundle emits, this legend included, at the map's markup rate of 2.50 bytes per token, and IS the number the ladder fits, so recounting the delivered bytes reproduces it; trim_level=/truncated= what the ladder dropped. When even the structural floor of every changed file exceeds it, the FILES are windowed in blast-radius order: shown= of files=, capped=1 with total=/has_more=/next_offset=/offset=/limit= (limit=0 = the default window), and next= is the one pasteable follow-up (the next page). truncated= carrying budget-floor-exceeded means the smallest document this bundle can render is STILL over budget_tokens= — including on a clean tree, whose whole document is this legend and has no ladder to descend; est_tokens= is then the honest ceiling, never a silent overshoot. counts_floor="1" means every count here is a FLOOR, never a total: edges are extracted from source TEXT by NAME. Missing: dynamic dispatch (virtual/interface/duck-typed), a most-vexing-parse declaration with no call expression, a function-pointer/callback bound to more than one function in scope (reassigned, table-indexed, lambda-bound, or address-taken/reference-bound), and a plain-name binding (fp=handler) whose variable type is not PROVABLY a function pointer (a same-file typedef/declarator; a HEADER typedef is missed; auto/template types are read as unpinned, so KEPT). A macro-generated call site is role="macro" only when its name uniquely names an indexed function-like #define (C-family, t="macro"); a shared name stays a plain call, an unindexed macro is no edge. Read a zero as "none found", never as "none exists". graph_ambiguous=/graph_unresolved= are the whole graph's resolver gauge (calls split over several defs / calls whose in-repo defs were all language-filtered), the map header's ambiguous=/unresolved=. COUNTING UNIT differs by verb: callers, callees, edit-check, graph-query and pr-context counts are DISTINCT SYMBOLS (repeated calls from one caller, and calls to two overloads, collapse into ONE row; multiplicity survives only in the call graph's edge weight). The reach counts (impact's reaches=, pr-context's dependents=) are the size of a transitive reach SET, each symbol counted once. The uses verb counts call SITES, one row per occurrence — a larger count there for the same symbol is these units agreeing, not disagreeing. The map header's edges= is a unit again different — distinct (caller,callee) PAIRS — and that document carries neither this marker nor this clause. -->
<pr-context base="working-tree" root="." direction="worktree-since-head" files="0" skipped_mode_only="0" budget_tokens="8000" est_tokens="2123" trim_level="0" truncated="none" budget_default="1" at="c7725f3ef" graph_ambiguous="6085" graph_unresolved="3093" counts_floor="1">
<!-- no changed files in the index (clean tree, or the diff touched only non-indexed files) -->
</pr-context>
`````

## `./build/ripwire . --pr-context=HEAD~1`

*The BASEREF form: diffed against merge-base(BASEREF, HEAD), never the ref tip — here the previous commit on the current line (a ref with NO merge base falls back to a disclosed two-dot diff: anchor="ref-tip-two-dot").*

`````
<!-- ripwire pr-context: no-LLM review-evidence bundle per changed file — defined symbols, their callers, blast radius (transitive dependents), affected tests, co-change partners not in the diff, and owners. base=HEAD~1. skipped_mode_only=diffs that changed a file's MODE and nothing else (e.g. chmod) excluded from the changed set; a pure RENAME is content-identical too but is NOT excluded — it is a changed file, listed at its new path. files= means two different things by DEPTH here and is deliberately not renamed (15 consumers read the root one): on the ROOT it is the CHANGED file count; on each <impact/> child it is the distinct files dependents= reaches (changed + non-changed), so dependents="0" implies files="0" and vice versa — never an impossible-looking dependents>0/files=0. files_other= on the same <impact/> is the non-changed subset (a changed file's dependents inside OTHER changed files have no <f> row of their own — they are already shown as their own <file> section); it is NOT the <f> row count — see the row-cap sentence below. Files are ordered by BLAST RADIUS (transitive dependents descending, path breaking ties), not alphabetically. sections= on changed-symbols counts a doc file's headings, collapsed into that number instead of one callers-zero row each; count= still counts every INDEXED symbol, sections included, so count minus sections is the number of rows that follow. Every nested list below is a TOP-N subset of its element's own total, fixed per element (impact <f> at 20, per-symbol <caller> at 12, cochange <partner> at 12, tests <test> at 40, owners <author> at 5 — the L0 defaults; max-tokens only lowers these further via the trim ladder, nothing raises them past L0): each capped element carries its own shown=/capped= pair so the cut is never silent — for the untrimmed list use impact=SYM/callers=SYM (blast radius/callers), affected=FILE or situ (tests), cochange (partners), or owners (authors) instead. direction= names which SIDE this bundle reviews (worktree-since-head, head-since-fork, head-since-ref-tip); a no-ref-work row says the base ref's tip IS the merge base, i.e. it carries no divergent work of its own. deterministic. BUDGET: the bundle is budgeted by default — budget_tokens= is the ceiling in force (8000 unless token-budget/max-tokens set it; budget_default=1 says the default applied); est_tokens= prices the WHOLE document this bundle emits, this legend included, at the map's markup rate of 2.50 bytes per token, and IS the number the ladder fits, so recounting the delivered bytes reproduces it; trim_level=/truncated= what the ladder dropped. When even the structural floor of every changed file exceeds it, the FILES are windowed in blast-radius order: shown= of files=, capped=1 with total=/has_more=/next_offset=/offset=/limit= (limit=0 = the default window), and next= is the one pasteable follow-up (the next page). truncated= carrying budget-floor-exceeded means the smallest document this bundle can render is STILL over budget_tokens= — including on a clean tree, whose whole document is this legend and has no ladder to descend; est_tokens= is then the honest ceiling, never a silent overshoot. counts_floor="1" means every count here is a FLOOR, never a total: edges are extracted from source TEXT by NAME. Missing: dynamic dispatch (virtual/interface/duck-typed), a most-vexing-parse declaration with no call expression, a function-pointer/callback bound to more than one function in scope (reassigned, table-indexed, lambda-bound, or address-taken/reference-bound), and a plain-name binding (fp=handler) whose variable type is not PROVABLY a function pointer (a same-file typedef/declarator; a HEADER typedef is missed; auto/template types are read as unpinned, so KEPT). A macro-generated call site is role="macro" only when its name uniquely names an indexed function-like #define (C-family, t="macro"); a shared name stays a plain call, an unindexed macro is no edge. Read a zero as "none found", never as "none exists". graph_ambiguous=/graph_unresolved= are the whole graph's resolver gauge (calls split over several defs / calls whose in-repo defs were all language-filtered), the map header's ambiguous=/unresolved=. COUNTING UNIT differs by verb: callers, callees, edit-check, graph-query and pr-context counts are DISTINCT SYMBOLS (repeated calls from one caller, and calls to two overloads, collapse into ONE row; multiplicity survives only in the call graph's edge weight). The reach counts (impact's reaches=, pr-context's dependents=) are the size of a transitive reach SET, each symbol counted once. The uses verb counts call SITES, one row per occurrence — a larger count there for the same symbol is these units agreeing, not disagreeing. The map header's edges= is a unit again different — distinct (caller,callee) PAIRS — and that document carries neither this marker nor this clause. -->
<!-- anchoring: a base ref was given, so this diff is anchored at merge base(BASEREF, HEAD), NOT at the ref's tip — the bundle is what THIS work changed since it forked, not how the two trees differ today. base_moved= counts paths the BASE REF moved since the fork that this work never touched (excluded here, and the same row class the abi verb names head moved: the other line moved, we did not author it). anchor="ref-tip-two-dot" instead means there was no merge base at all (unrelated history) and the two dot view is what you are reading. -->
<pr-context base="HEAD~1" root="." anchor="merge-base" base_sha="58d67dc1e" base_moved="0" direction="head-since-fork" files="1" skipped_mode_only="0" budget_tokens="8000" est_tokens="4193" trim_level="0" truncated="none" budget_default="1" at="c7725f3ef" graph_ambiguous="6085" graph_unresolved="309 … [line truncated: 20 more bytes on this line]
<no-ref-work note="HEAD~1 tip == merge-base, so that ref has no divergent work of its own; this bundle is HEAD's work since the fork. For the ref's OWN diff see merge-scout or stray-content"/>
<file p="test/pargates.py" symbols="40">
<impact dependents="0" files="0" files_other="0" shown="0" capped="0">
</impact>
<tests count="0" shown="0" capped="0">
</tests>
<changed-symbols count="40">
<s t="var" n="root" p="test/pargates.py:20" callers="0" shown="0" capped="0">
</s>
<s t="var" n="binp" p="test/pargates.py:21" callers="0" shown="0" capped="0">
</s>
<s t="var" n="jobs" p="test/pargates.py:22" callers="0" shown="0" capped="0">
</s>
<s t="var" n="only" p="test/pargates.py:23" callers="0" shown="0" capped="0">
</s>
<s t="var" n="jsonout" p="test/pargates.py:24" callers="0" shown="0" capped="0">
</s>
<s t="var" n="args" p="test/pargates.py:25" callers="0" shown="0" capped="0">
</s>
<s t="var" n="testdir" p="test/pargates.py:34" callers="0" shown="0" capped="0">
</s>
<s t="var" n="gates" p="test/pargates.py:38" callers="0" shown="0" capped="0">
</s>
<s t="var" n="skip" p="test/pargates.py:40" callers="0" shown="0" capped="0">
</s>
<s t="var" n="gates" p="test/pargates.py:41" callers="0" shown="0" capped="0">
</s>
… [79 more display lines; full output is 10483 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --merge-scout=HEAD~2,HEAD~1`

*Pairwise cross-arm conflict sites + suggested landing order (any committish sharing a merge base with HEAD works as an arm; one that does not is reported ok="0", never compared).*

**wall time: 2.99s**

`````
<!-- ripwire merge-scout: read-only cross-branch overlap for 2 arm(s) — same-symbol change on two arms = conflict, same-file/different-symbol = textual risk. landing = fewest-conflicts-first greedy (ties: ref name asc). Every tree is a git-archive TEMP COPY (read-only); the real working tree/refs are never touched. ANCHORING: every arm is diffed against its OWN merge base with HEAD (the working tree arm against HEAD itself), never against live HEAD — so a file an arm never opened can never appear here just because the live line moved. head_conflicts= is the one thing that anchor hides, kept as its own row class: symbols this arm changed that the LIVE LINE also changed since the arm forked, a merge fight no pairwise ARM comparison can see because HEAD is not an arm. A row carrying anchoring=file-level is a whole-file fallback for a file with zero real-body symbols (no tree-sitter symbol spans it) — counted and conflict-checked like any other row, just not attributed to a symbol inside it. at= is the git commit these numbers were computed at; a trailing +dirty means the working tree differed from that commit (head= is the same commit, bare sha, kept for compatibility). -->
<merge-scout arms="2" head="c7725f3ef" at="c7725f3ef">
<arm ref="HEAD~2" base="323bd4ce3" ok="1" changed="0" head_conflicts="0">
<no-work note="no divergent work vs merge-base — see --stray-content"/>
</arm>
<arm ref="HEAD~1" base="58d67dc1e" ok="1" changed="0" head_conflicts="0">
<no-work note="no divergent work vs merge-base — see --stray-content"/>
</arm>
<pair a="HEAD~2" b="HEAD~1" conflicts="0" risks="0"/>
<landing order=""/>
</merge-scout>
`````

## `./build/ripwire . --stray-content=lane`

*Which lane-* refs still hold divergent authored work vs HEAD, with verdicts.*

`````
<!-- ripwire stray-content: per ref, the lines its own divergent work AUTHORED (vs its merge-base with HEAD) that the live line does NOT have. v="superseded" means the live line removed the same base code this ref removed (redone/del) — it re-implemented the work, the case `git cherry` cannot see; v="unmerged" means the work is genuinely absent; merged refs are omitted. Read-only: git cat-file/diff/ls-tree only, one batched cat-file for the whole sweep, every blob reduced once per sha. Line-granular, not semantic: see the ripwire help text for the limits. ANCHORING is a deliberate hybrid: the SCOPE is base anchored (only lines the ref itself authored vs its merge base are ever considered, so a file the ref never opened cannot appear because the live line moved), while the ABSENCE test is HEAD anchored on purpose (does the live line have this content TODAY is the question being asked, and it is only answerable against live HEAD). v="unknown" with ok="0" means this ref could NOT be analysed at all because it has no merge base with HEAD, which on a SHALLOW clone (the checkout default in CI) is every ref: it is not a claim that the ref is merged, and the fix is to deepen the clone. The four buckets are exhaustive, so unmerged plus superseded plus merged plus unknown always equals refs. SCOPE: refs/heads only, which is every local branch (worktree branches included). Remote tracking refs are NOT scanned: they mirror local ones in the usual checkout and would double every row. The consequence on a FRESH CLONE, where the branches live under refs/remotes/origin and only the checked out one has a local head, is that there is nothing here to be stray FROM; refs= is that fact as a number. TRUNCATION: a ref row ends with a more element (more files=N) when its own file listing was capped; shown plus that number equals the ref's files= total, always. That inner listing is a SECONDARY listing (it repeats complete and identical on every page) and is capped by detail, not by limit / offset, which page the OUTER ref listing and report their own shown= / capped=. at= is the git commit these numbers were computed at; a trailing +dirty means the working tree differed from that commit (head= is the same commit, bare sha, kept for compatibility). -->
<stray-content head="c7725f3ef" head_ref="integration/terminality-2026-09-05" refs="41" blobs="53" unmerged="1" superseded="3" merged="18" unknown="19" filter="lane" at="c7725f3ef">
<ref name="lane/ca-P15" tip="2e305e5ea" date="2026-09-04" base="b38a488f8" ok="1" v="unmerged" stray="72" files="3" superseded="0">
<file p="test/readmedriftcheck.sh" v="unmerged" stray="69" authored="79" del="0" redone="0" sim="0.78" head-touched="0"/>
<file p="README.md" v="unmerged" stray="2" authored="2" del="2" redone="0" sim="0.99" head-touched="1"/>
<file p="skills/ripwire-efficient/compress-ladder.md" v="unmerged" stray="1" authored="1" del="1" redone="0" sim="1.00" head-touched="0"/>
</ref>
<ref name="lane/ca-L4" tip="232c33796" date="2026-09-05" base="30192e6ae" ok="1" v="superseded" stray="24" files="8" superseded="24">
<file p="test/lintprecisioncheck.sh" v="superseded" stray="7" authored="7" del="2" redone="2" sim="0.82" head-touched="1"/>
<file p="test/donelegendcheck.sh" v="superseded" stray="4" authored="4" del="1" redone="1" sim="0.94" head-touched="1"/>
<file p="test/fixedbufsweep.sh" v="superseded" stray="4" authored="4" del="1" redone="1" sim="0.84" head-touched="1"/>
<file p="test/rustqualcheck.sh" v="superseded" stray="3" authored="3" del="1" redone="1" sim="1.00" head-touched="1"/>
<file p="README.md" v="superseded" stray="2" authored="3" del="3" redone="3" sim="0.99" head-touched="1"/>
<file p="test/panellegendcheck.sh" v="superseded" stray="2" authored="5" del="3" redone="3" sim="0.35" head-touched="1"/>
<file p="test/detailcheck.sh" v="superseded" stray="1" authored="1" del="1" redone="1" sim="0.87" head-touched="1"/>
<file p="test/nsfiltercheck.sh" v="superseded" stray="1" authored="2" del="1" redone="1" sim="0.98" head-touched="1"/>
</ref>
<ref name="lane/ca-L1" tip="e8d27c400" date="2026-09-05" base="9b4513ba6" ok="1" v="superseded" stray="17" files="4" superseded="12">
<file p="src/cli.h" v="superseded" stray="6" authored="6" del="1" redone="1" sim="0.91" head-touched="1"/>
<file p="test/shapingflagcheck.sh" v="unmerged" stray="5" authored="5" del="0" redone="0" sim="0.74" head-touched="1"/>
<file p="test/cppqualcheck.sh" v="superseded" stray="4" authored="7" del="3" redone="3" sim="0.45" head-touched="1"/>
<file p=".ripwire_quality_acks" v="superseded" stray="2" authored="2" del="2" redone="2" sim="0.38" head-touched="1"/>
</ref>
<ref name="lane/ca-L10b" tip="16b121b91" date="2026-09-05" base="20e2b90d6" ok="1" v="superseded" stray="8" files="3" superseded="8">
<file p="test/a9disclosurecheck.sh" v="superseded" stray="6" authored="6" del="1" redone="1" sim="0.98" head-touched="1"/>
<file p="test/docdemotegolden_for.xml" v="superseded" stray="1" authored="1" del="1" redone="1" sim="0.92" head-touched="1"/>
<file p="test/floormarkcheck.sh" v="superseded" stray="1" authored="1" del="1" redone="1" sim="0.80" head-touched="1"/>
</ref>
<ref name="lane/af-grepfast" tip="71ae8c5ba" date="2026-08-29" base="" ok="0" v="unknown" stray="0" files="0" superseded="0">
</ref>
… [37 more display lines; full output is 7670 bytes on 1 raw line(s)]
`````

stderr:

`````
[math degraded] crossref: no merge-base for ref (shallow clone or unrelated history?) — verdict is unknown, not merged  (crossref.h:1053, RefPlumbing rw::crossref::probeRefBase(const std::string &, const RefInfo &, const std::string &) — logged once per site)
`````

## `./build/ripwire . --stray-content=worktree-agent-`

*A second ref family (the substring picked at capture time from the refs this checkout really has): merged refs are OMITTED from the rows and counted in merged=; refs sharing no merge base with HEAD (a shallow clone, or a pre-rewrite history) land in unknown= with ok="0" — the counters always reconcile against refs=.*

`````
<!-- ripwire stray-content: per ref, the lines its own divergent work AUTHORED (vs its merge-base with HEAD) that the live line does NOT have. v="superseded" means the live line removed the same base code this ref removed (redone/del) — it re-implemented the work, the case `git cherry` cannot see; v="unmerged" means the work is genuinely absent; merged refs are omitted. Read-only: git cat-file/diff/ls-tree only, one batched cat-file for the whole sweep, every blob reduced once per sha. Line-granular, not semantic: see the ripwire help text for the limits. ANCHORING is a deliberate hybrid: the SCOPE is base anchored (only lines the ref itself authored vs its merge base are ever considered, so a file the ref never opened cannot appear because the live line moved), while the ABSENCE test is HEAD anchored on purpose (does the live line have this content TODAY is the question being asked, and it is only answerable against live HEAD). v="unknown" with ok="0" means this ref could NOT be analysed at all because it has no merge base with HEAD, which on a SHALLOW clone (the checkout default in CI) is every ref: it is not a claim that the ref is merged, and the fix is to deepen the clone. The four buckets are exhaustive, so unmerged plus superseded plus merged plus unknown always equals refs. SCOPE: refs/heads only, which is every local branch (worktree branches included). Remote tracking refs are NOT scanned: they mirror local ones in the usual checkout and would double every row. The consequence on a FRESH CLONE, where the branches live under refs/remotes/origin and only the checked out one has a local head, is that there is nothing here to be stray FROM; refs= is that fact as a number. TRUNCATION: a ref row ends with a more element (more files=N) when its own file listing was capped; shown plus that number equals the ref's files= total, always. That inner listing is a SECONDARY listing (it repeats complete and identical on every page) and is capped by detail, not by limit / offset, which page the OUTER ref listing and report their own shown= / capped=. at= is the git commit these numbers were computed at; a trailing +dirty means the working tree differed from that commit (head= is the same commit, bare sha, kept for compatibility). -->
<stray-content head="c7725f3ef" head_ref="integration/terminality-2026-09-05" refs="4" blobs="0" unmerged="0" superseded="0" merged="0" unknown="4" filter="worktree-agent-" at="c7725f3ef">
<ref name="worktree-agent-a452c3a68b8e23a13" tip="8d91da738" date="2026-08-09" base="" ok="0" v="unknown" stray="0" files="0" superseded="0">
</ref>
<ref name="worktree-agent-a4f7fc619b4225bbf" tip="8d91da738" date="2026-08-09" base="" ok="0" v="unknown" stray="0" files="0" superseded="0">
</ref>
<ref name="worktree-agent-aba5c7b36339f9fb2" tip="8d91da738" date="2026-08-09" base="" ok="0" v="unknown" stray="0" files="0" superseded="0">
</ref>
<ref name="worktree-agent-ae45795e1a8e40789" tip="31b7d0d07" date="2026-08-31" base="" ok="0" v="unknown" stray="0" files="0" superseded="0">
</ref>
</stray-content>
`````

stderr:

`````
[math degraded] crossref: no merge-base for ref (shallow clone or unrelated history?) — verdict is unknown, not merged  (crossref.h:1053, RefPlumbing rw::crossref::probeRefBase(const std::string &, const RefInfo &, const std::string &) — logged once per site)
`````

## `./build/ripwire . --stray-content=lane/ --plan`

*Select the genuinely-unmerged refs of one family and feed them to merge-scout for a landing order (a merged family yields an empty landing set — still a measurement, disclosed on the root).*

**wall time: 2.92s**

`````
<!-- ripwire landing-plan: stray-content's cheap per-blob sweep composed with merge-scout's per-arm overlap oracle — of every local branch, which still hold REAL work (v="unmerged"), which were already re-implemented on the live line (v="superseded", EXCLUDED below — landing them re-does work that is already done) or are already merged (omitted entirely, counted in merged= on the root element), and the fewest-conflicts-first order to land what remains. scouted="0" on an unmerged ref means it was NOT fed to merge-scout this run (the cost bound, not a verdict) — it is still real, unscouted work; bounded= on the root element counts them and detail lifts the bound. merge-scout is the EXPENSIVE step here (git-archive + full ingest per arm) — stray-content's own sweep is the cheap one. An undetermined row is a ref that could NOT be analysed at all (no merge base with HEAD, which on a SHALLOW clone is every ref): it is neither scouted nor excluded nor merged, because nothing was measured — treat it as unfinished business and deepen the clone, never as a clean branch. Read-only throughout: no checkout, no ref write, no working-tree mutation. The root carries BOTH head= and at= and they are the same commit: head= is the bare 9 hex chars this verb has always printed, at= is the tool wide anchor and is head= plus a "+dirty" suffix when the working tree is not clean. Prefer at= (it is the one spelling every other repo reading verb uses, and the only one that tells you whether uncommitted work was in scope); head= is kept for callers already keyed to it. -->
<landing-plan head="c7725f3ef" refs="41" unmerged="1" superseded="3" merged="18" undetermined="19" scouted="1" bounded="0" scout-ok="1" at="c7725f3ef">
<ref name="lane/ca-P15" v="unmerged" stray="72" files="3" scouted="1"/>
<undetermined name="lane/af-grepfast" v="unknown" reason="no merge base with HEAD (shallow clone or unrelated history) — this ref could not be analysed, it is NOT known to be merged; deepen the clone and re-run"/>
<undetermined name="lane/af-hookdrift" v="unknown" reason="no merge base with HEAD (shallow clone or unrelated history) — this ref could not be analysed, it is NOT known to be merged; deepen the clone and re-run"/>
<undetermined name="lane/af-idiom" v="unknown" reason="no merge base with HEAD (shallow clone or unrelated history) — this ref could not be analysed, it is NOT known to be merged; deepen the clone and re-run"/>
<undetermined name="lane/af-planlint" v="unknown" reason="no merge base with HEAD (shallow clone or unrelated history) — this ref could not be analysed, it is NOT known to be merged; deepen the clone and re-run"/>
<undetermined name="lane/af-regmacro" v="unknown" reason="no merge base with HEAD (shallow clone or unrelated history) — this ref could not be analysed, it is NOT known to be merged; deepen the clone and re-run"/>
<undetermined name="lane/af-scope" v="unknown" reason="no merge base with HEAD (shallow clone or unrelated history) — this ref could not be analysed, it is NOT known to be merged; deepen the clone and re-run"/>
<undetermined name="lane/arise-h2h" v="unknown" reason="no merge base with HEAD (shallow clone or unrelated history) — this ref could not be analysed, it is NOT known to be merged; deepen the clone and re-run"/>
<undetermined name="lane/bin-override" v="unknown" reason="no merge base with HEAD (shallow clone or unrelated history) — this ref could not be analysed, it is NOT known to be merged; deepen the clone and re-run"/>
<undetermined name="lane/candhead-ugrep" v="unknown" reason="no merge base with HEAD (shallow clone or unrelated history) — this ref could not be analysed, it is NOT known to be merged; deepen the clone and re-run"/>
<undetermined name="lane/count-conservation" v="unknown" reason="no merge base with HEAD (shallow clone or unrelated history) — this ref could not be analysed, it is NOT known to be merged; deepen the clone and re-run"/>
<undetermined name="lane/fnbody-require" v="unknown" reason="no merge base with HEAD (shallow clone or unrelated history) — this ref could not be analysed, it is NOT known to be merged; deepen the clone and re-run"/>
<undetermined name="lane/gitignore" v="unknown" reason="no merge base with HEAD (shallow clone or unrelated history) — this ref could not be analysed, it is NOT known to be merged; deepen the clone and re-run"/>
<undetermined name="lane/identity-round" v="unknown" reason="no merge base with HEAD (shallow clone or unrelated history) — this ref could not be analysed, it is NOT known to be merged; deepen the clone and re-run"/>
<undetermined name="lane/impact-requires" v="unknown" reason="no merge base with HEAD (shallow clone or unrelated history) — this ref could not be analysed, it is NOT known to be merged; deepen the clone and re-run"/>
<undetermined name="lane/topic-branch" v="unknown" reason="no merge base with HEAD (shallow clone or unrelated history) — this ref could not be analysed, it is NOT known to be merged; deepen the clone and re-run"/>
<undetermined name="lane/recall-rootrel-rank" v="unknown" reason="no merge base with HEAD (shallow clone or unrelated history) — this ref could not be analysed, it is NOT known to be merged; deepen the clone and re-run"/>
<undetermined name="lane/safe-delete" v="unknown" reason="no merge base with HEAD (shallow clone or unrelated history) — this ref could not be analysed, it is NOT known to be merged; deepen the clone and re-run"/>
<undetermined name="lane/scopeless-fold" v="unknown" reason="no merge base with HEAD (shallow clone or unrelated history) — this ref could not be analysed, it is NOT known to be merged; deepen the clone and re-run"/>
<undetermined name="lane/t3-body-budget" v="unknown" reason="no merge base with HEAD (shallow clone or unrelated history) — this ref could not be analysed, it is NOT known to be merged; deepen the clone and re-run"/>
<excluded name="lane/ca-L4" v="superseded" stray="24" reason="already re-implemented on the live line"/>
<excluded name="lane/ca-L1" v="superseded" stray="17" reason="already re-implemented on the live line"/>
<excluded name="lane/ca-L10b" v="superseded" stray="8" reason="already re-implemented on the live line"/>
<arm ref="lane/ca-P15" base="b38a488f8" ok="1" changed="8" head_conflicts="2">
<sym p="skills/ripwire-efficient/compress-ladder.md" id="The detail ladder (and --compress) with ripwire"/>
<sym p="README.md" id="README.md::Rip&apos;n Fast. Less Tokens. Better Code.::Quickstart"/>
<sym p="test/readmedriftcheck.sh" id="start_here_lines"/>
<sym p="skills/ripwire-efficient/compress-ladder.md" id="compress-ladder"/>
<sym p="README.md" id="README"/>
<sym p="README.md" id="Rip&apos;n Fast. Less Tokens. Better Code."/>
<sym p="skills/ripwire-efficient/compress-ladder.md" id="skills/ripwire-efficient/compress-ladder.md::The detail ladder (and --compress) with ripwire::The ladder — climb one rung at a time"/>
<sym p="test/readmedriftcheck.sh" id="bare_start_here"/>
<head-conflict p="README.md" id="README"/>
<head-conflict p="README.md" id="Rip&apos;n Fast. Less Tokens. Better Code."/>
</arm>
<landing order="lane/ca-P15"/>
</landing-plan>
`````

stderr:

`````
[math degraded] crossref: no merge-base for ref (shallow clone or unrelated history?) — verdict is unknown, not merged  (crossref.h:1053, RefPlumbing rw::crossref::probeRefBase(const std::string &, const RefInfo &, const std::string &) — logged once per site)
`````

## `./build/ripwire . --stray-content=zzzz-no-such-ref --plan`

*A --plan filter that selects NO ref REFUSES (exit 1) naming the substring — before the wave-3 close this fell through to the '>512 refs match' sentence, and --abi under the same filter answered an empty measurement at exit 0.*

**exit code: 1**

`````
(empty)
`````

stderr:

`````
ripwire: --plan: --stray-content=zzzz-no-such-ref matches no local ref — a zero here would be a failure, not a measurement
  (the filter is a substring match against refs/heads names; run bare --stray-content to list them, e.g. --stray-content=feat/)
`````

## `./build/ripwire . --stray-content=lane --abi`

*Cross-branch ABI-break gate: struct byte-contract drift on each ref's AUTHORED paths.*

**wall time: 1.30s**

`````
<!-- ripwire abi: the cross-branch ABI-BREAK gate — layout(STRUCT) crossed with stray-content(BRANCH). Scope is what each ref AUTHORED: the paths `diff base..tip` reports against its own merge base, never `diff HEAD..tip` (a file the branch never opened cannot be a break the branch introduced, and on a long-lived tree that one distinction took 487 drift rows to 4). For each such path the SAME field-offset model layout uses is run LEXICALLY on the ref's git blob (never indexed) and compared against HEAD's computed fields. LISTED kinds: drift = the byte contract differs (the bug this check exists for, the only kind that exits 2); unknown = the ref-side copy could not be modelled (see ref_caveat) and is NEVER reported as unchanged; absent = the ref does not define the struct at that path. COUNTED but not listed (pass detail=N to print them): rename = identical slots and field types under different field NAMES, so every byte stayed where it was (a same-type field REORDER is lexically identical to a rename and lands here too); spelling and stub mirror layout's own harmless cases; head-moved = the ref's copy equals its own merge-base copy, so the LIVE LINE is what changed. head_only= counts candidate sites on paths only the live line touched (outside the authored scope); unmodelable= counts sites skipped because HEAD's own copy carries no baseline; every excluded row is on a counter, nothing is dropped silently. Structs that match are omitted entirely; unrelated= counts refs with no merge-base against HEAD at all (unrelated history — never even compared, so nothing for them CAN be dropped silently either) and, because such a ref never gets the chance to acquire a row, it ALSO lands in quiet= below (the two counters are not disjoint: a ref with no rows at all is counted in quiet= whether that is because nothing broke or because nothing was ever compared), and a ref whose every row is an excluded kind is counted in excluded_refs= and prints under detail=N. LIMITS: HEAD's own side is the WORKING TREE's layout answer, not a re-fetched git blob at HEAD's commit; a nested field type that ALSO changed on the ref resolves via HEAD's copy, not the ref's; the ref-side locator is index-free and file-scope (one namespace deep) only, so a struct nested in a class or wrapped in an extern C block reads absent rather than compared; the authorship anchor is per PATH, so a branch changing struct S in one file while the live line changes S's mirror in another is a merge hazard only layout(S) on the merged result can see. Single-root; read-only (cat-file/diff/merge-base only). at= is the git commit these numbers were computed at; a trailing +dirty means the working tree differed from that commit (head= is the same commit, bare sha, kept for compatibility). -->
<abi head="c7725f3ef" head_ref="integration/terminality-2026-09-05" refs="41" candidates="931" compared="0" blobs="2" rows="0" shown="0" capped="0" dropped="0" excluded="0" head_only="6560" unmodelable="7" unrelated="19" broken_refs="0" quiet="41" excluded_refs="0" at="c7725f3ef" root=".">
</abi>
`````

stderr:

`````
[math degraded] abi: no merge-base for a ref (unrelated history?) — that ref is counted, not compared  (abicheck.h:482, void rw::abicheck::collectAuthoredSites(const std::string &, const std::vector<crossref::RefInfo> &, const PathIndex &, SweepState &, Tally) — logged once per site)
`````

## `./build/ripwire . --whereis=rankGraphTeleport`

*Which ref's tree defines or mentions SYM — HEAD first, then every local branch.*

**wall time: 1.79s**

`````
<!-- ripwire whereis: every LOCAL ref whose TREE contains this symbol, HEAD first, and within a ref SOURCE files before test files before docs, then definitions before references, then path and line. The doc demotion is ORDER ONLY: a doc line that quotes a signature still reads as a definition to the heuristic below and still says kind="def", it is simply printed after the code. kind= is answered by TWO different mechanisms, and head_labels= says which one answered for HEAD: with head_labels="index" a HEAD row is kind="def" iff the PARSED index puts a definition there (one row per index def site), while every NON-HEAD row — and every row when head_labels="lexical" (no index was supplied, the index knows no def of this name, or the working tree has drifted from HEAD) — is a LEXICAL shape heuristic over raw blob text that was never ingested: it reads a quoted signature in a doc as a definition and can miss an unusual declarator. refs_scanned= is the SCAN DENOMINATOR (how many refs besides HEAD were read), NOT a count of refs that matched — hits= and the rows are the matched set. on-head="0" alongside ref hits is the case this verb exists for: content that lives only on a branch. A TREE scan can only find content some ref still carries, so hits="0" on its own does not distinguish a name this repo never had from one it deleted; run with the with_history flag and the fate row says which, naming the commit that removed it. ANCHORING: none, by design. This verb runs no diff at all — it scans each ref's FULL tree, which is what lets it find content a branch merely INHERITED (exactly what a merge base anchored diff would exclude), so nothing here can fire merely because HEAD moved. at= is sha-only here (never +dirty): a tree scan reads committed blobs, so the working tree's cleanliness does not enter the answer. SELECTOR: this verb takes a BARE symbol name, not the file:name spelling that callers, uses, impact, around, lego and edit_check accept. A file:name spelling is searched as a LITERAL string, no tree contains it, and the result is a true but useless hits="0" shaped exactly like a name this repo never had. When that is what happened, a selector-note element says so and its retry= is the bare name to re-run with. That element has three reasons, and r= names which: qualified-selector (a file:name spelling was searched literally), line-seed (an @FILE:LINE selector was RESOLVED to the definition enclosing that line before the scan, so sym= is that definition's name and spec= is what you typed), and near-miss (the scan found nothing and the INDEX holds a name one or two edits away — the tree zero is still a measurement, the note only says which zero it is). Its absence beside hits="0" means the zero IS a measurement. SCOPE: refs/heads only, which is every local branch (worktree branches included). Remote tracking refs are NOT scanned: they mirror local ones in the usual checkout and would double every row. The consequence on a FRESH CLONE, where the branches live under refs/remotes/origin and only the checked out one has a local head, is that this verb sees essentially one tree; refs_scanned= is that fact as a number, so read it before reading hits=. TRUNCATION: the trailing more element (more hits=N) is the rows AFTER this page, so shown plus more equals the rows from this page's offset on. It is not a second cap, and not a second vocabulary to page by: it is the SAME fact shown= / capped= / next_offset= carry, restated from the other end (what this page did not print). Page with limit= and offset=; the more element is absent exactly when this page reached the end of the hit list. COMPLETENESS: complete= on the root (value 1) means this listing is EXHAUSTIVE and a consumer need not re-derive it: every occurrence of the symbol in every TEXT blob of every scanned ref's full tree is printed above — nothing was capped or paged out, and no blob was oversized (over the 2 MB blob ceiling), missing or cut short by the stream. The denominator is refs_scanned= plus HEAD, under SCOPE above (local heads only), so with complete= present a ref absent from the rows genuinely lacks the symbol in its committed tree. Binary blobs are outside the claim (a text symbol cannot occur in one); an oversized TEXT blob suppresses the claim instead of being silently skipped. Its ABSENCE claims nothing. raise the default cap with limit=N (offset=M pages; a cut listing carries total=/has_more=/next_offset= so a paging loop can continue from it). -->
<whereis sym="rankGraphTeleport" on-head="1" refs_scanned="67" blobs="4270" hits="58077" head_labels="index" shown="60" capped="1" total="58077" has_more="1" next_offset="60" offset="0" limit="0" at="c7725f3ef">
<hit ref="HEAD" tip="c7725f3ef" date="2026-09-05" p="src/graph.h" l="2501" kind="def" t="inline RankedGraph rankGraphTeleport( const Graph&amp; g, const std::vector&lt;float&gt;&amp; p, float alpha = 0.85f )"/>
<hit ref="HEAD" tip="c7725f3ef" date="2026-09-05" p="present/deck5_ripwire_build.js" l="631" kind="ref" t="s.addText(&quot;$ ripwire . --callers=rankGraphTeleport&quot;, { x: 8.68, y: 2.1, w: 3.8, h: 0.3, fontFace: MONO, fontSize: 10, color: MUTED, margin: 0 });"/>
<hit ref="HEAD" tip="c7725f3ef" date="2026-09-05" p="present/deck5_ripwire_build.js" l="633" kind="ref" t="{ text: &quot;&lt;callers of=\&quot;rankGraphTeleport\&quot;\n  defs=\&quot;1\&quot; count=\&quot;6\&quot; &quot;, options: { color: TEXT } },"/>
<hit ref="HEAD" tip="c7725f3ef" date="2026-09-05" p="src/cli.h" l="72" kind="ref" t="// tokens on --around=rankGraphTeleport vs 5,860 B at depth 1; the root&apos;s"/>
<hit ref="HEAD" tip="c7725f3ef" date="2026-09-05" p="src/crossref.h" l="1632" kind="ref" t="// code above the real definition: `--whereis=rankGraphTeleport` opened with three kind=&quot;def&quot; rows into"/>
<hit ref="HEAD" tip="c7725f3ef" date="2026-09-05" p="src/didyoumean.h" l="238" kind="ref" t="// `--path=rankGraphTeleport,` printed &quot;endpoint not found:  (did you mean &apos;A&apos;?)&quot;. Guarded at the shared walk"/>
<hit ref="HEAD" tip="c7725f3ef" date="2026-09-05" p="src/eval.h" l="322" kind="ref" t="const std::vector&lt;float&gt; r = rankGraphTeleport( g, diffTeleport( ing, seedMask ) ).rank;"/>
<hit ref="HEAD" tip="c7725f3ef" date="2026-09-05" p="src/graph.h" l="108" kind="ref" t="// renormalized to Σ=1 in rankGraphTeleport — so every teleport-based"/>
<hit ref="HEAD" tip="c7725f3ef" date="2026-09-05" p="src/graph.h" l="2444" kind="ref" t="// prior (never the edges) and renormalized in rankGraphTeleport. Every symbol whose name is missing from"/>
<hit ref="HEAD" tip="c7725f3ef" date="2026-09-05" p="src/graph.h" l="2489" kind="ref" t="// discard out. That is what this used to be: rankGraphTeleport called pageRankDouble, threw away its return,"/>
<hit ref="HEAD" tip="c7725f3ef" date="2026-09-05" p="src/graph.h" l="2534" kind="ref" t="// `rank = takeRank( rankGraphTeleport( … ), d )` is the only spelling, and it fills both or neither."/>
<hit ref="HEAD" tip="c7725f3ef" date="2026-09-05" p="src/graph.h" l="2545" kind="ref" t="return rankGraphTeleport( g, std::vector&lt;float&gt;( N, N ? 1.0f / float( N ) : 0.f ), alpha );"/>
<hit ref="HEAD" tip="c7725f3ef" date="2026-09-05" p="src/graph.h" l="3030" kind="ref" t="// cliff), run the EXISTING PPR machinery (rankGraphTeleport — the same biasPrior/det-gate seam every"/>
<hit ref="HEAD" tip="c7725f3ef" date="2026-09-05" p="src/graph.h" l="3078" kind="ref" t="const std::vector&lt;float&gt; ppr = rankGraphTeleport( g, p ).rank;"/>
<hit ref="HEAD" tip="c7725f3ef" date="2026-09-05" p="src/main.cpp" l="1007" kind="ref" t="rw::RankedGraph    ranked = isDecay ? rankGraphTeleport( d.g, churnDecayTeleportWorkspace( rootDirs, d.ing, &amp;hasChurnEvidence ) )"/>
<hit ref="HEAD" tip="c7725f3ef" date="2026-09-05" p="src/main.cpp" l="1008" kind="ref" t=": rankGraphTeleport( d.g, churnTeleportWorkspace( rootDirs, d.ing, &quot;18 months ago&quot;, &amp;hasChurnEvidence ) );"/>
<hit ref="HEAD" tip="c7725f3ef" date="2026-09-05" p="src/main.cpp" l="1018" kind="ref" t="rw::RankedGraph    ranked = rankGraphTeleport( d.g, churnDecayTeleport( d.root, d.ing, d.cfg.since.empty() ? nullptr : &amp;sinceScope, &amp;hasChurnEvidence ) );"/>
<hit ref="HEAD" tip="c7725f3ef" date="2026-09-05" p="src/main.cpp" l="1024" kind="ref" t="rw::RankedGraph    ranked = rankGraphTeleport( d.g, churnTeleport( d.root, d.ing, &quot;18 months ago&quot;, d.cfg.since.empty() ? nullptr : &amp;sinceScope, &amp;hasChurnEvidence ) );"/>
<hit ref="HEAD" tip="c7725f3ef" date="2026-09-05" p="src/main.cpp" l="1195" kind="ref" t="rank = rw::takeRank( rankGraphTeleport( g, diffTeleport( ing, changed ) ), rankDisclosure );"/>
<hit ref="HEAD" tip="c7725f3ef" date="2026-09-05" p="src/mcp.h" l="1769" kind="ref" t="//   queries:[&quot;callers:rankGraphTeleport&quot;, {&quot;verb&quot;:&quot;slice&quot;,&quot;symbol&quot;:&quot;…&quot;}]"/>
<hit ref="HEAD" tip="c7725f3ef" date="2026-09-05" p="src/mcpindex.h" l="1167" kind="ref" t="// symbols, the rest uniform, then rankGraphTeleport (which also applies the name-quality biasPrior"/>
<hit ref="HEAD" tip="c7725f3ef" date="2026-09-05" p="src/mcpindex.h" l="1200" kind="ref" t="const auto [ wsRank, wsIters, wsConverged ] = rankGraphTeleport( ix.g, diffTeleport( ix.ing, changed ) );"/>
<hit ref="HEAD" tip="c7725f3ef" date="2026-09-05" p="src/mcpverbs.h" l="4169" kind="ref" t="// the colon is a SEPARATOR, and `callers: rankGraphTeleport` is how a human writes one. Untrimmed, the"/>
<hit ref="HEAD" tip="c7725f3ef" date="2026-09-05" p="src/mcpverbs.h" l="4171" kind="ref" t="//   symbol not found: &apos; rankGraphTeleport&apos; (did you mean &apos;rankGraphTeleport&apos;?)"/>
<hit ref="HEAD" tip="c7725f3ef" date="2026-09-05" p="src/selectorrefuse.h" l="7" kind="ref" t="// (&quot;that file defines no &apos;rankGraphTeleport&apos;&quot;), names the files that DO define the name, and hands back a"/>
<hit ref="HEAD" tip="c7725f3ef" date="2026-09-05" p="bench/nestcal/r1-2026-08-07/post-ripwire-src.tsv" l="651" kind="ref" t="graph.h::rw::rankGraphTeleport&#9;3&#9;0&#9;0&#9;5&#9;8&#9;28"/>
<hit ref="HEAD" tip="c7725f3ef" date="2026-09-05" p="bench/nestcal/r1-2026-08-07/pre-ripwire-src.tsv" l="651" kind="ref" t="graph.h::rw::rankGraphTeleport&#9;3&#9;0&#9;0&#9;5&#9;8&#9;28"/>
<hit ref="HEAD" tip="c7725f3ef" date="2026-09-05" p="bench/recalleval/labels_ranking.tsv" l="49" kind="ref" t="power iteration rank convergence damping factor&#9;src/pagerank.cpp#pageRankDouble&#9;src/graph.h#rankGraphTeleport,src/pagerank.h#pageRankDouble&#9;concept"/>
… [34 more display lines; full output is 18260 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --whereis=computeOnePairOverlap --with-history`

*Same, plus a git-history <fate> row (never / removed-by-commit) for names no tree carries.*

**wall time: 4.01s**

`````
<!-- ripwire whereis: every LOCAL ref whose TREE contains this symbol, HEAD first, and within a ref SOURCE files before test files before docs, then definitions before references, then path and line. The doc demotion is ORDER ONLY: a doc line that quotes a signature still reads as a definition to the heuristic below and still says kind="def", it is simply printed after the code. kind= is answered by TWO different mechanisms, and head_labels= says which one answered for HEAD: with head_labels="index" a HEAD row is kind="def" iff the PARSED index puts a definition there (one row per index def site), while every NON-HEAD row — and every row when head_labels="lexical" (no index was supplied, the index knows no def of this name, or the working tree has drifted from HEAD) — is a LEXICAL shape heuristic over raw blob text that was never ingested: it reads a quoted signature in a doc as a definition and can miss an unusual declarator. refs_scanned= is the SCAN DENOMINATOR (how many refs besides HEAD were read), NOT a count of refs that matched — hits= and the rows are the matched set. on-head="0" alongside ref hits is the case this verb exists for: content that lives only on a branch. A TREE scan can only find content some ref still carries, so hits="0" on its own does not distinguish a name this repo never had from one it deleted; run with the with_history flag and the fate row says which, naming the commit that removed it. ANCHORING: none, by design. This verb runs no diff at all — it scans each ref's FULL tree, which is what lets it find content a branch merely INHERITED (exactly what a merge base anchored diff would exclude), so nothing here can fire merely because HEAD moved. at= is sha-only here (never +dirty): a tree scan reads committed blobs, so the working tree's cleanliness does not enter the answer. SELECTOR: this verb takes a BARE symbol name, not the file:name spelling that callers, uses, impact, around, lego and edit_check accept. A file:name spelling is searched as a LITERAL string, no tree contains it, and the result is a true but useless hits="0" shaped exactly like a name this repo never had. When that is what happened, a selector-note element says so and its retry= is the bare name to re-run with. That element has three reasons, and r= names which: qualified-selector (a file:name spelling was searched literally), line-seed (an @FILE:LINE selector was RESOLVED to the definition enclosing that line before the scan, so sym= is that definition's name and spec= is what you typed), and near-miss (the scan found nothing and the INDEX holds a name one or two edits away — the tree zero is still a measurement, the note only says which zero it is). Its absence beside hits="0" means the zero IS a measurement. SCOPE: refs/heads only, which is every local branch (worktree branches included). Remote tracking refs are NOT scanned: they mirror local ones in the usual checkout and would double every row. The consequence on a FRESH CLONE, where the branches live under refs/remotes/origin and only the checked out one has a local head, is that this verb sees essentially one tree; refs_scanned= is that fact as a number, so read it before reading hits=. TRUNCATION: the trailing more element (more hits=N) is the rows AFTER this page, so shown plus more equals the rows from this page's offset on. It is not a second cap, and not a second vocabulary to page by: it is the SAME fact shown= / capped= / next_offset= carry, restated from the other end (what this page did not print). Page with limit= and offset=; the more element is absent exactly when this page reached the end of the hit list. COMPLETENESS: complete= on the root (value 1) means this listing is EXHAUSTIVE and a consumer need not re-derive it: every occurrence of the symbol in every TEXT blob of every scanned ref's full tree is printed above — nothing was capped or paged out, and no blob was oversized (over the 2 MB blob ceiling), missing or cut short by the stream. The denominator is refs_scanned= plus HEAD, under SCOPE above (local heads only), so with complete= present a ref absent from the rows genuinely lacks the symbol in its committed tree. Binary blobs are outside the claim (a text symbol cannot occur in one); an oversized TEXT blob suppresses the claim instead of being silently skipped. Its ABSENCE claims nothing. raise the default cap with limit=N (offset=M pages; a cut listing carries total=/has_more=/next_offset= so a paging loop can continue from it). history probed="1" means the git-log name-history walk ran: commits= is how many it read (runProbe's own no-merges log, so a name deleted only inside a merge commit is invisible and not counted either), removed-names= how many distinct names it saw deleted at least once, and truncated="1" (absent = not hit) means the walk stopped at its own commit ceiling before reaching the root. probed="0" r= says why it did not run at all (not-a-git-repo or probe-failed) — none of the other attributes are then present. -->
<whereis sym="computeOnePairOverlap" on-head="1" refs_scanned="67" blobs="4270" hits="7107" head_labels="index" shown="60" capped="1" total="7107" has_more="1" next_offset="60" offset="0" limit="0" at="c7725f3ef">
<history probed="1" head="c7725f3ef" commits="1398" removed-names="29937"/>
<hit ref="HEAD" tip="c7725f3ef" date="2026-09-05" p="src/mergescout.h" l="601" kind="def" t="inline PairOverlap computeOnePairOverlap( std::size_t a, std::size_t b, const Arm&amp; armA, const Arm&amp; armB )"/>
<hit ref="HEAD" tip="c7725f3ef" date="2026-09-05" p="src/lanes.h" l="17" kind="ref" t="// and the landing order are mergescout::computeOnePairOverlap / computeOverlaps / landingOrder, fed SYNTHETIC"/>
<hit ref="HEAD" tip="c7725f3ef" date="2026-09-05" p="src/lanes.h" l="65" kind="ref" t="//   same_file_risk[] — different keys, same file. AGGREGATED PER FILE: computeOnePairOverlap is a nested loop"/>
<hit ref="HEAD" tip="c7725f3ef" date="2026-09-05" p="src/mergescout.h" l="39" kind="ref" t="// computeOnePairOverlap&apos;s conflict/risk split, the r26 head-conflict lane — all key off `bodyHash`/"/>
<hit ref="HEAD" tip="c7725f3ef" date="2026-09-05" p="src/mergescout.h" l="628" kind="ref" t="pairs.push_back( computeOnePairOverlap( a, b, arms[a], arms[b] ) );"/>
<hit ref="HEAD" tip="c7725f3ef" date="2026-09-05" p="bench/nestcal/r1-2026-08-07/post-ripwire-src.tsv" l="1588" kind="ref" t="mergescout.h::mergescout::computeOnePairOverlap&#9;3&#9;0&#9;0&#9;5&#9;7&#9;19"/>
<hit ref="HEAD" tip="c7725f3ef" date="2026-09-05" p="bench/nestcal/r1-2026-08-07/pre-ripwire-src.tsv" l="1588" kind="ref" t="mergescout.h::mergescout::computeOnePairOverlap&#9;4&#9;1&#9;1&#9;5&#9;7&#9;19"/>
<hit ref="HEAD" tip="c7725f3ef" date="2026-09-05" p="bench/recalleval/snapshot.mdpack" l="14503" kind="ref" t="## `./build/ripwire . --whereis=computeOnePairOverlap --with-history`"/>
<hit ref="HEAD" tip="c7725f3ef" date="2026-09-05" p="bench/recalleval/snapshot.mdpack" l="14511" kind="ref" t="&lt;whereis sym=&quot;computeOnePairOverlap&quot; on-head=&quot;1&quot; refs_scanned=&quot;0&quot; blobs=&quot;1047&quot; hits=&quot;19&quot; head_labels=&quot;index&quot; shown=&quot;19&qu … [line truncated: 56 more bytes on this line]
<hit ref="HEAD" tip="c7725f3ef" date="2026-09-05" p="bench/recalleval/snapshot.mdpack" l="14513" kind="ref" t="&lt;fate sym=&quot;computeOnePairOverlap&quot; v=&quot;removed&quot; commit=&quot;93dbc7972&quot; date=&quot;2026-08-01&quot; p=&quot;docs/captures/COMMANDS_showcase_2026-08-01.md&quot; not … [line truncated: 157 more bytes on this line]
<hit ref="HEAD" tip="c7725f3ef" date="2026-09-05" p="bench/recalleval/snapshot.mdpack" l="14514" kind="ref" t="&lt;hit ref=&quot;HEAD&quot; tip=&quot;bc09d0260&quot; date=&quot;2026-08-01&quot; p=&quot;src/mergescout.h&quot; l=&quot;470&quot; kind=&quot;def&quot; t=&quot;inline PairOverlap computeOn … [line truncated: 108 more bytes on this line]
<hit ref="HEAD" tip="c7725f3ef" date="2026-09-05" p="bench/recalleval/snapshot.mdpack" l="14515" kind="ref" t="&lt;hit ref=&quot;HEAD&quot; tip=&quot;bc09d0260&quot; date=&quot;2026-08-01&quot; p=&quot;src/lanes.h&quot; l=&quot;17&quot; kind=&quot;ref&quot; t=&quot;// and the landing order are merge … [line truncated: 90 more bytes on this line]
<hit ref="HEAD" tip="c7725f3ef" date="2026-09-05" p="bench/recalleval/snapshot.mdpack" l="14516" kind="ref" t="&lt;hit ref=&quot;HEAD&quot; tip=&quot;bc09d0260&quot; date=&quot;2026-08-01&quot; p=&quot;src/lanes.h&quot; l=&quot;64&quot; kind=&quot;ref&quot; t=&quot;//   same_file_risk[] — differen … [line truncated: 92 more bytes on this line]
<hit ref="HEAD" tip="c7725f3ef" date="2026-09-05" p="bench/recalleval/snapshot.mdpack" l="14517" kind="ref" t="&lt;hit ref=&quot;HEAD&quot; tip=&quot;bc09d0260&quot; date=&quot;2026-08-01&quot; p=&quot;src/mergescout.h&quot; l=&quot;487&quot; kind=&quot;ref&quot; t=&quot;pairs.push_back( computeOneP … [line truncated: 53 more bytes on this line]
<hit ref="HEAD" tip="c7725f3ef" date="2026-09-05" p="bench/recalleval/snapshot.mdpack" l="14518" kind="ref" t="&lt;hit ref=&quot;HEAD&quot; tip=&quot;bc09d0260&quot; date=&quot;2026-08-01&quot; p=&quot;test/showcase_capture.py&quot; l=&quot;190&quot; kind=&quot;ref&quot; t=&quot;add(S4, f&amp;quot;{ … [line truncated: 254 more bytes on this line]
<hit ref="HEAD" tip="c7725f3ef" date="2026-09-05" p="bench/recalleval/snapshot.mdpack" l="14519" kind="ref" t="&lt;hit ref=&quot;HEAD&quot; tip=&quot;bc09d0260&quot; date=&quot;2026-08-01&quot; p=&quot;docs/captures/COMMANDS_showcase_2026-08-01.md&quot; l=&quot;2211&quot; kind=&quot;ref&quot; t=&quo … [line truncated: 85 more bytes on this line]
<hit ref="HEAD" tip="c7725f3ef" date="2026-09-05" p="bench/recalleval/snapshot.mdpack" l="14520" kind="ref" t="&lt;hit ref=&quot;HEAD&quot; tip=&quot;bc09d0260&quot; date=&quot;2026-08-01&quot; p=&quot;docs/captures/COMMANDS_showcase_2026-08-01.md&quot; l=&quot;2217&quot; kind=&quot;ref&quot; t=&quo … [line truncated: 283 more bytes on this line]
<hit ref="HEAD" tip="c7725f3ef" date="2026-09-05" p="bench/recalleval/snapshot.mdpack" l="14521" kind="ref" t="&lt;hit ref=&quot;HEAD&quot; tip=&quot;bc09d0260&quot; date=&quot;2026-08-01&quot; p=&quot;docs/captures/COMMANDS_showcase_2026-08-01.md&quot; l=&quot;2219&quot; kind=&quot;ref&quot; t=&quo … [line truncated: 272 more bytes on this line]
<hit ref="HEAD" tip="c7725f3ef" date="2026-09-05" p="test/showcase_capture.py" l="281" kind="ref" t="add(S4, f&quot;{BIN} . --whereis=computeOnePairOverlap --with-history&quot;, &quot;Same, plus a git-history &lt;fate&gt; row (never / removed-by-commit) for names no tree carries.&quot;, timeout=600) … [line truncated: 3 more bytes on this line]
<hit ref="HEAD" tip="c7725f3ef" date="2026-09-05" p="docs/captures/COMMANDS_showcase_2026-08-10.md" l="2319" kind="ref" t="## `./build/ripwire . --whereis=computeOnePairOverlap --with-history`"/>
<hit ref="HEAD" tip="c7725f3ef" date="2026-09-05" p="docs/captures/COMMANDS_showcase_2026-08-10.md" l="2327" kind="ref" t="&lt;whereis sym=&quot;computeOnePairOverlap&quot; on-head=&quot;1&quot; refs_scanned=&quot;123&quot; blobs=&quot;2414&quot; hits=&quot;2657&quot; head_labels=&quot;index&quot; s … [line truncated: 72 more bytes on this line]
<hit ref="HEAD" tip="c7725f3ef" date="2026-09-05" p="docs/captures/COMMANDS_showcase_2026-08-10.md" l="2329" kind="ref" t="&lt;fate sym=&quot;computeOnePairOverlap&quot; v=&quot;removed&quot; commit=&quot;5579dd63f&quot; date=&quot;2026-08-09&quot; p=&quot;docs/captures/COMMANDS_showcase_2026-08-09. … [line truncated: 169 more bytes on this line]
<hit ref="HEAD" tip="c7725f3ef" date="2026-09-05" p="docs/captures/COMMANDS_showcase_2026-08-10.md" l="2330" kind="ref" t="&lt;hit ref=&quot;HEAD&quot; tip=&quot;dd6d9768c&quot; date=&quot;2026-08-10&quot; p=&quot;src/mergescout.h&quot; l=&quot;530&quot; kind=&quot;def&quot; t=&quot;inline PairOverl … [line truncated: 120 more bytes on this line]
<hit ref="HEAD" tip="c7725f3ef" date="2026-09-05" p="docs/captures/COMMANDS_showcase_2026-08-10.md" l="2331" kind="ref" t="&lt;hit ref=&quot;HEAD&quot; tip=&quot;dd6d9768c&quot; date=&quot;2026-08-10&quot; p=&quot;src/lanes.h&quot; l=&quot;17&quot; kind=&quot;ref&quot; t=&quot;// and the landing ord … [line truncated: 102 more bytes on this line]
<hit ref="HEAD" tip="c7725f3ef" date="2026-09-05" p="docs/captures/COMMANDS_showcase_2026-08-10.md" l="2332" kind="ref" t="&lt;hit ref=&quot;HEAD&quot; tip=&quot;dd6d9768c&quot; date=&quot;2026-08-10&quot; p=&quot;src/lanes.h&quot; l=&quot;64&quot; kind=&quot;ref&quot; t=&quot;//   same_file_risk[]  … [line truncated: 104 more bytes on this line]
<hit ref="HEAD" tip="c7725f3ef" date="2026-09-05" p="docs/captures/COMMANDS_showcase_2026-08-10.md" l="2333" kind="ref" t="&lt;hit ref=&quot;HEAD&quot; tip=&quot;dd6d9768c&quot; date=&quot;2026-08-10&quot; p=&quot;src/mergescout.h&quot; l=&quot;557&quot; kind=&quot;ref&quot; t=&quot;pairs.push_back( … [line truncated: 65 more bytes on this line]
<hit ref="HEAD" tip="c7725f3ef" date="2026-09-05" p="docs/captures/COMMANDS_showcase_2026-08-10.md" l="2334" kind="ref" t="&lt;hit ref=&quot;HEAD&quot; tip=&quot;dd6d9768c&quot; date=&quot;2026-08-10&quot; p=&quot;bench/nestcal/r1-2026-08-07/post-ripwire-src.tsv&quot; l=&quot;1588&quot; kind=&quot;r … [line truncated: 133 more bytes on this line]
… [35 more display lines; full output is 29574 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --flags`

*The dark-content dashboard: gates BUILT but OFF. CHANGED: no longer invents gates from comments/heredocs, so the count only reflects real ifndef/define, CMake option(), and getenv gates.*

`````
<!-- ripwire flags: what is BUILT but DARK here. Three gate patterns in one report: ifndef/define header gates (kind="compile"), CMake option() switches (kind="cmake"), and getenv reads (kind="env", default unset). dark="1" means the default keeps the guarded code out of the build; regions/loc size what it turns off. When one name is BOTH a header gate and a CMake option the CMake default wins (that is what the build passes) and the header shows as an also row. Lexical, not preprocessed: this reports the in-repo default, never the value your build used. dark_gates on this root is the COUNT of dark gates; it was spelled dark until that collided with the child bool. files= is THIS verb's own harvest scan (source + CMakeLists files it read looking for gates) — a wider crawl than the map's indexed corpus, so it will not equal the map's files= -->
<flags gates="69" dark_gates="62" compile="12" cmake="12" env="45" files="1593">
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
… [274 more display lines; full output is 17049 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --flags --flip=RIPWIRE_ASAN`

*Blast radius of turning ONE gate on: live code, symbols, transitive reach, covering tests.*

`````
<!-- ripwire flip: the blast radius of turning ONE gate ON. lights = the code that becomes live: r rows are #if regions, b rows are C++ branch sites (a gate read as a VALUE through a constexpr bool, via= names the binding). hosts = the indexed defs that code sits inside; downstream = what those defs transitively CALL (what starts executing); dependents = what transitively calls THEM. tests = test files reaching the hosts; untested = hosts no test reaches (the honest is it safe answer). An alias MASTER rolls its children in (member rows); flipping a CHILD lights only that child and names its parent. kind=cmake also steers the BUILD graph, which no C++ side analysis follows: those sites are c rows. kind=env is RUNTIME (runtime=1) so every row is conditional at its read. Lexical and single line, never preprocessed: the value lane reads C family source only and treats a file declaring its OWN constant of that name as shadowing the gate's, but a third header's same named constant (included, not redeclared) would still count. A lit site inside no indexed def counts into filescope instead of a host. run= is the command that discharges a test row; run_unknown="1" means none is derivable for that harness (a guess would be worse than none) — a row carries one or the other, never neither. UNIT: untested= here counts HOSTS (indexed defs this gate lights that no test reaches). The test gate verb spells untested= over impacted SYMBOLS and the seams verb over cross-directory call EDGES, so the three numbers count three different things and must never be compared or summed across verbs. -->
<flip gate="RIPWIRE_ASAN" kind="cmake" default="OFF" dark="1" runtime="0" p="CMakeLists.txt" l="14" family="1" regions="0" loc="0" branches="0" bindings="0" hosts="0" filescope="0" downstream="0" dependents="0" tests="0" untested="0" files="1593">
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
<c p="CMakeLists.txt" l="808"/>
</build>
</flip>
`````

## `./build/ripwire . --flags --flip=RIPWIRE_ASA`

*Unknown-gate refusal (exit 1) with a did-you-mean from a real edit distance (one character off RIPWIRE_ASAN).*

**exit code: 1**

`````
(empty)
`````

stderr:

`````
ripwire: --flip: no gate named 'RIPWIRE_ASA' in . (did you mean 'RIPWIRE_ASAN'?)
ripwire: run `ripwire . --flags` for the gate table
`````

## `./build/ripwire . --plan-lanes=3 --task="add a --since filter to the doc-drift verb and cover it with tests"`

*NEW VERB: pre-hoc lane plan — which of 3 parallel worktrees would COLLIDE, before a line is written. JSON on stdout.*

`````
{"v":1,"verb":"plan-lanes","at":"c7725f3ef","root":".","task":"add a --since filter to the doc-drift verb and cover it with tests","source":"partition","requested":3,"lane_count":3,"claim_key":"path+scope+name","on_conflict":"producing-lane-rebases","corpus":{"files":1588,"symbols":13849,"edges":170 … [line truncated: 357 more bytes on this line]
"symbols":[{"p":"./src/docdrift.h","n":"DriftResult","scope":"DriftResult","l":274,"id":"./src/docdrift.h::DriftResult::DriftResult"},
{"p":"./src/docdrift.h","n":"computeDocDrift","scope":"docdrift","l":2289,"id":"./src/docdrift.h::docdrift::computeDocDrift"},
{"p":"./src/docdrift.h","n":"kDocDriftLegend","scope":"docdrift","l":2576,"id":"./src/docdrift.h::docdrift::kDocDriftLegend"},
{"p":"./src/mcprefusal.h","n":"kMcpRequiredFields","scope":"rw::mcprefuse","l":66,"id":"./src/mcprefusal.h::rw::mcprefuse::kMcpRequiredFields"},
{"p":"./src/mcpverbs.h","n":"docDriftText","scope":"rw","l":530,"id":"./src/mcpverbs.h::rw::docDriftText"},
{"p":"./src/verbs_change.h","n":"runDocDrift","scope":"","l":1654,"id":null}]},"lanes":[{"id":"lane-0","task":"add a --since filter to the doc-drift verb and cover it with tests","claims":{"symbols":[{"p":"./src/verbs_change.h","n":"runAbiCheck","scope":"","key":"183da9aaf74a4a92","id":null,"id_addr … [line truncated: 113 more bytes on this line]
{"p":"./src/main.cpp","n":"dispatchMain","scope":"","key":"3298be65bf6058ef","id":null,"id_addressable":false,"id_collides_with":1,"l":2653,"ord":1,"overloads":2,"amb":81,"cx":237,"ccx":405,"churn":271,"tested":0},
{"p":"./src/docdrift.h","n":"writeDocDriftPage","scope":"docdrift","key":"380b7de5df1cfd73","id":"./src/docdrift.h::docdrift::writeDocDriftPage","id_addressable":true,"id_collides_with":0,"l":2682,"ord":0,"overloads":1,"amb":2,"cx":10,"ccx":11,"churn":13,"tested":0},
{"p":"./src/crossref.h","n":"writeWhereisPage","scope":"crossref","key":"3a0425468e6a18cf","id":"./src/crossref.h::crossref::writeWhereisPage","id_addressable":true,"id_collides_with":0,"l":2088,"ord":0,"overloads":1,"amb":5,"cx":22,"ccx":23,"churn":24,"tested":0},
{"p":"./src/mcprefusal.h","n":"kMcpValueFields","scope":"rw::mcprefuse","key":"4a7106e488a2aa80","id":"./src/mcprefusal.h::rw::mcprefuse::kMcpValueFields","id_addressable":true,"id_collides_with":0,"l":289,"ord":0,"overloads":1,"amb":0,"cx":0,"ccx":0,"churn":24,"tested":0},
{"p":"./src/darkflags.h","n":"writeFlags","scope":"darkflags","key":"5c2c4a2b311b8dba","id":"./src/darkflags.h::darkflags::writeFlags","id_addressable":true,"id_collides_with":0,"l":1092,"ord":0,"overloads":1,"amb":1,"cx":3,"ccx":2,"churn":9,"tested":0},
{"p":"./src/verbs_change.h","n":"runCrossRef","scope":"","key":"639de1c3670999f9","id":null,"id_addressable":false,"id_collides_with":0,"l":1465,"ord":0,"overloads":1,"amb":6,"cx":34,"ccx":69,"churn":25,"tested":0},
{"p":"./src/testmap.h","n":"scriptGatesUnmodelledCount","scope":"rw","key":"98c4487e2e9e08bc","id":"./src/testmap.h::rw::scriptGatesUnmodelledCount","id_addressable":true,"id_collides_with":0,"l":511,"ord":0,"overloads":1,"amb":0,"cx":5,"ccx":4,"churn":11,"tested":0},
{"p":"./src/main.cpp","n":"scanReportVerbPrecedence","scope":"","key":"9ab981e987e8108e","id":null,"id_addressable":false,"id_collides_with":0,"l":2007,"ord":0,"overloads":1,"amb":33,"cx":8,"ccx":11,"churn":271,"tested":0},
{"p":"./src/gitmine.h","n":"gitChurnCounts","scope":"rw","key":"cc1e357ae3abf4b0","id":"./src/gitmine.h::rw::gitChurnCounts","id_addressable":true,"id_collides_with":0,"l":2757,"ord":0,"overloads":1,"amb":1,"cx":5,"ccx":4,"churn":17,"tested":0},
{"p":"./src/mcp.h","n":"dispatchMcpLine","scope":"rw","key":"d63db6944aa504a7","id":"./src/mcp.h::rw::dispatchMcpLine","id_addressable":true,"id_collides_with":0,"l":535,"ord":0,"overloads":1,"amb":158,"cx":259,"ccx":517,"churn":52,"tested":0},
{"p":"./src/mcpverbs.h","n":"unknownSubVerbRefusal","scope":"rw","key":"e336d39b0a6addea","id":"./src/mcpverbs.h::rw::unknownSubVerbRefusal","id_addressable":true,"id_collides_with":0,"l":4237,"ord":0,"overloads":1,"amb":2,"cx":3,"ccx":2,"churn":117,"tested":0}],
"files":[{"p":"./src/crossref.h","symbols":1,"churn":24,"ccx":23,"hotspot_rank":16},
{"p":"./src/darkflags.h","symbols":1,"churn":9,"ccx":2,"hotspot_rank":42},
{"p":"./src/docdrift.h","symbols":1,"churn":13,"ccx":11,"hotspot_rank":21},
{"p":"./src/gitmine.h","symbols":1,"churn":17,"ccx":4,"hotspot_rank":17},
{"p":"./src/main.cpp","symbols":2,"churn":271,"ccx":416,"hotspot_rank":1},
{"p":"./src/mcp.h","symbols":1,"churn":52,"ccx":517,"hotspot_rank":7},
{"p":"./src/mcprefusal.h","symbols":1,"churn":24,"ccx":0,"hotspot_rank":30},
{"p":"./src/mcpverbs.h","symbols":1,"churn":117,"ccx":2,"hotspot_rank":4},
{"p":"./src/testmap.h","symbols":1,"churn":11,"ccx":4,"hotspot_rank":48},
{"p":"./src/verbs_change.h","symbols":2,"churn":25,"ccx":77,"hotspot_rank":15}]},"blast_radius":{"reaches":31,"files_total":13,"capped":false,"files":["./src/crossref.h","./src/docdrift.h","./src/editplan.h","./src/gitmine.h","./src/main.cpp","./src/mcp.h","./src/mcpedit.h","./src/mcpserver.h","./sr … [line truncated: 119 more bytes on this line]
"tests_total":0,"tests_capped":false,"tests_granularity":"claimed-symbols","untested":31,"module_span":2,"notes":[],
"execution":{"policy":"codex-lane/v1","model":"gpt-5.6-sol","reasoning":"xhigh","rule":"wide-contract-work","basis":"structural-only","signals":{"claims":12,"files":10,"module_span":2,"max_ccx":517,"sum_ccx":1056,"ambiguous_calls":290,"blast_reaches":31,"contract_touches":5,"conflicts":0,"untested": … [line truncated: 144 more bytes on this line]
… [77 more display lines; full output is 20872 bytes on 1 raw line(s)]
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
{"v":1,"verb":"plan-lanes","at":"c7725f3ef","root":".","task":null,"source":"brief","requested":3,"lane_count":3,"claim_key":"path+scope+name","on_conflict":"producing-lane-rebases","corpus":{"files":1588,"symbols":13849,"edges":17058,"ambiguous":6085,"unresolved":3093},"carve":null,"core":{"files": … [line truncated: 3 more bytes on this line]
"symbols":[]},"lanes":[{"id":"lane-0","task":"add a --since filter to the doc-drift verb","claims":{"symbols":[{"p":"./src/docdrift.h","n":"recordUnchecked","scope":"docdrift","key":"12641dab14abc8fd","id":"./src/docdrift.h::docdrift::recordUnchecked","id_addressable":true,"id_collides_with":0,"l":2 … [line truncated: 72 more bytes on this line]
{"p":"./src/docdrift.h","n":"sortWeakGroupsByPath","scope":"docdrift","key":"1944ba506280ff80","id":"./src/docdrift.h::docdrift::sortWeakGroupsByPath","id_addressable":true,"id_collides_with":0,"l":2249,"ord":0,"overloads":1,"amb":0,"cx":1,"ccx":0,"churn":13,"tested":0},
{"p":"./src/mcpverbs.h","n":"docDriftText","scope":"rw","key":"1fa68e8d93c05a59","id":"./src/mcpverbs.h::rw::docDriftText","id_addressable":true,"id_collides_with":0,"l":530,"ord":0,"overloads":1,"amb":0,"cx":1,"ccx":0,"churn":117,"tested":0},
{"p":"./src/cli.h","n":"kViewFlags","scope":"rw","key":"2a2f2487082cc6d8","id":"./src/cli.h::rw::kViewFlags","id_addressable":true,"id_collides_with":0,"l":2456,"ord":0,"overloads":1,"amb":0,"cx":0,"ccx":0,"churn":212,"tested":0},
{"p":"./src/recall.h","n":"docFileMask","scope":"rw","key":"3149a219f599664c","id":"./src/recall.h::rw::docFileMask","id_addressable":true,"id_collides_with":0,"l":106,"ord":0,"overloads":1,"amb":0,"cx":4,"ccx":4,"churn":17,"tested":0},
{"p":"./src/docdrift.h","n":"writeDocDriftPage","scope":"docdrift","key":"380b7de5df1cfd73","id":"./src/docdrift.h::docdrift::writeDocDriftPage","id_addressable":true,"id_collides_with":0,"l":2682,"ord":0,"overloads":1,"amb":2,"cx":10,"ccx":11,"churn":13,"tested":0},
{"p":"./src/docdrift.h","n":"computeDocDrift","scope":"docdrift","key":"3b19cc3d8996c3b2","id":"./src/docdrift.h::docdrift::computeDocDrift","id_addressable":true,"id_collides_with":0,"l":2289,"ord":0,"overloads":1,"amb":12,"cx":22,"ccx":35,"churn":13,"tested":0},
{"p":"./src/docdrift.h","n":"DriftResult","scope":"DriftResult","key":"422ab39546b6e0bd","id":"./src/docdrift.h::DriftResult::DriftResult","id_addressable":true,"id_collides_with":0,"l":274,"ord":0,"overloads":1,"amb":0,"cx":0,"ccx":0,"churn":13,"tested":0},
{"p":"./src/verbs_change.h","n":"runDocDrift","scope":"","key":"904831e5c0f66b39","id":null,"id_addressable":false,"id_collides_with":0,"l":1654,"ord":0,"overloads":1,"amb":0,"cx":5,"ccx":4,"churn":25,"tested":0},
{"p":"./src/ensemble.h","n":"kEnsembleChurnSince","scope":"ensemble","key":"a34fc78c05bf56a8","id":"./src/ensemble.h::ensemble::kEnsembleChurnSince","id_addressable":true,"id_collides_with":0,"l":116,"ord":0,"overloads":1,"amb":0,"cx":0,"ccx":0,"churn":15,"tested":0},
{"p":"./src/mcprefusal.h","n":"kMcpRequiredFields","scope":"rw::mcprefuse","key":"c5f1ad5fc3a12368","id":"./src/mcprefusal.h::rw::mcprefuse::kMcpRequiredFields","id_addressable":true,"id_collides_with":0,"l":66,"ord":0,"overloads":1,"amb":0,"cx":0,"ccx":0,"churn":24,"tested":0},
{"p":"./src/docdrift.h","n":"kDocDriftLegend","scope":"docdrift","key":"ff2ba74637bbbebf","id":"./src/docdrift.h::docdrift::kDocDriftLegend","id_addressable":true,"id_collides_with":0,"l":2576,"ord":0,"overloads":1,"amb":0,"cx":0,"ccx":0,"churn":13,"tested":0}],
"files":[{"p":"./src/cli.h","symbols":1,"churn":212,"ccx":0,"hotspot_rank":6},
{"p":"./src/docdrift.h","symbols":6,"churn":13,"ccx":47,"hotspot_rank":21},
{"p":"./src/ensemble.h","symbols":1,"churn":15,"ccx":0,"hotspot_rank":47},
{"p":"./src/mcprefusal.h","symbols":1,"churn":24,"ccx":0,"hotspot_rank":30},
{"p":"./src/mcpverbs.h","symbols":1,"churn":117,"ccx":0,"hotspot_rank":4},
{"p":"./src/recall.h","symbols":1,"churn":17,"ccx":4,"hotspot_rank":32},
{"p":"./src/verbs_change.h","symbols":1,"churn":25,"ccx":4,"hotspot_rank":15}]},"blast_radius":{"reaches":12,"files_total":7,"capped":false,"files":["./src/docdrift.h","./src/main.cpp","./src/mcp.h","./src/mcpserver.h","./src/mcpverbs.h","./src/recall.h","./src/verbs_for.h"]},"tests_to_run":[],
"tests_total":0,"tests_capped":false,"tests_granularity":"claimed-symbols","untested":12,"module_span":8,"notes":[],
"execution":{"policy":"codex-lane/v1","model":"gpt-5.6-sol","reasoning":"xhigh","rule":"wide-contract-work","basis":"structural-only","signals":{"claims":12,"files":7,"module_span":8,"max_ccx":35,"sum_ccx":55,"ambiguous_calls":15,"blast_reaches":12,"contract_touches":0,"conflicts":3,"untested":12,"t … [line truncated: 139 more bytes on this line]
{"id":"lane-1","task":"add the CLI parse arm and help text for the new filter","claims":{"symbols":[{"p":"./scripts/optremarks.py","n":"main","scope":"","key":"01b3b880f77d1512","id":null,"id_addressable":false,"id_collides_with":87,"l":178,"ord":0,"overloads":1,"amb":0,"cx":23,"ccx":31,"churn":3,"t … [line truncated: 10 more bytes on this line]
{"p":"./src/cli.h","n":"kViewFlags","scope":"rw","key":"2a2f2487082cc6d8","id":"./src/cli.h::rw::kViewFlags","id_addressable":true,"id_collides_with":0,"l":2456,"ord":0,"overloads":1,"amb":0,"cx":0,"ccx":0,"churn":212,"tested":0},
{"p":"./docs/docs_commands_build.py","n":"main","scope":"","key":"4015853681ded3bc","id":null,"id_addressable":false,"id_collides_with":87,"l":580,"ord":0,"overloads":1,"amb":0,"cx":19,"ccx":28,"churn":6,"tested":0},
{"p":"./src/mcprefusal.h","n":"kMcpValueFields","scope":"rw::mcprefuse","key":"4a7106e488a2aa80","id":"./src/mcprefusal.h::rw::mcprefuse::kMcpValueFields","id_addressable":true,"id_collides_with":0,"l":289,"ord":0,"overloads":1,"amb":0,"cx":0,"ccx":0,"churn":24,"tested":0},
{"p":"./src/mcprefusal.h","n":"degradedParseNote","scope":"rw::mcprefuse","key":"5bdc80b53ca474f0","id":"./src/mcprefusal.h::rw::mcprefuse::degradedParseNote","id_addressable":true,"id_collides_with":0,"l":857,"ord":0,"overloads":1,"amb":0,"cx":2,"ccx":1,"churn":24,"tested":0},
{"p":"./src/query.h","n":"tryParsePredicateOnAll","scope":"query","key":"786acc4dbfec612b","id":"./src/query.h::query::tryParsePredicateOnAll","id_addressable":false,"id_collides_with":1,"l":107,"ord":0,"overloads":2,"amb":0,"cx":1,"ccx":0,"churn":10,"tested":0},
{"p":"./src/mcprefusal.h","n":"kMcpVerbFields","scope":"rw::mcprefuse","key":"82b1e3c6a4919914","id":"./src/mcprefusal.h::rw::mcprefuse::kMcpVerbFields","id_addressable":true,"id_collides_with":0,"l":965,"ord":0,"overloads":1,"amb":0,"cx":0,"ccx":0,"churn":24,"tested":0},
{"p":"./src/selectorrefuse.h","n":"degradedParseClause","scope":"rw","key":"88033bd3a9290e24","id":"./src/selectorrefuse.h::rw::degradedParseClause","id_addressable":true,"id_collides_with":0,"l":75,"ord":0,"overloads":1,"amb":0,"cx":2,"ccx":1,"churn":9,"tested":0},
… [60 more display lines; full output is 18931 bytes on 1 raw line(s)]
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
<!-- ripwire layout: field offsets COMPUTED from the source text under standard-layout assumptions on a 64-bit Apple/LP64 target (natural alignment, interior padding, trailing pad to the aggregate's own alignment). NOT the ABI: pragma pack, bitfields, virtuals, base classes, nested aggregates, preprocessor-conditional members and unsized field types are DETECTED and set modeled="0" with a caveat rather than numbered; a caveat row's count="N" means that ONE row stands for N member sites of the same kind (absent = one). Every same-name definition is compared: kind="drift" means the BYTE contract differs (the bug this verb exists for, and the only one that exits non-zero); kind="stub" is an empty placeholder aggregate and kind="spelling" is the two arms of one ifdef block naming the same bytes differently (simd::float4 vs float4) — both reported, neither a break. agree="0" on an assert row means a sizeof tripwire contradicts the computed size. Definitions and asserts come from the INDEXED files. -->
<!-- root= on this element is the crawl root every p= below is RELATIVE to (single-root runs only; absent => p= is the path ingest itself used, unchanged). -->
<layout sym="Symbol" found="1" defs="1" mirror="single" asserts="1" conflicts="0" scanned="500" root=".">
<def p="src/model.h" l="224" agg="struct" modeled="0" fields="23">
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
<assert p="src/model.h" l="378" kind="mention" t="static_assert( sizeof( Symbol ) == 64 + 2 * sizeof( std::string ), &quot;Symbol size changed — verify the new field uses the smallest type + is grouped (SoA); see model.h&quot; )"/>
</layout>
`````

## `./build/ripwire . --layout=Lang`

*The honest refusal (exit 1): Lang is an `enum class`, not a struct — no offsets are fabricated.*

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
<doc-drift docs="145" clean="126" anchors="2468" checked="965" unchecked="1503" drift="61" dated="80" prose="9" corpus="1619" at="c7725f3ef">
<doc p="docs/COMMANDS.md" anchors="137" checked="37" drift="32" dated="0">
<a k="const" l="3619" c="53" why="const-value" ref="kDriftedLimit = 10" want="10" got="15" tgt="test/docdriftfix/code.h:11"/>
<a k="array" l="3620" c="54" why="array-extent" ref="kDriftedTable[16]" want="16" got="18" tgt="test/docdriftfix/code.h:14"/>
<a k="const" l="3621" c="53" why="const-value" ref="kDriftedLimit = 10" want="10" got="15" tgt="test/docdriftfix/code.h:11"/>
<a k="array" l="3622" c="54" why="array-extent" ref="kDriftedTable[16]" want="16" got="18" tgt="test/docdriftfix/code.h:14"/>
<a k="const" l="3623" c="53" why="const-value" ref="kDriftedLimit = 10" want="10" got="15" tgt="test/docdriftfix/code.h:11"/>
<a k="const" l="3624" c="53" why="const-value" ref="kDriftedLimit = 10" want="10" got="15" tgt="test/docdriftfix/code.h:11"/>
<a k="array" l="3625" c="54" why="array-extent" ref="kDriftedTable[16]" want="16" got="18" tgt="test/docdriftfix/code.h:14"/>
<a k="const" l="3626" c="53" why="const-value" ref="kDriftedLimit = 10" want="10" got="15" tgt="test/docdriftfix/code.h:11"/>
<a k="array" l="3627" c="54" why="array-extent" ref="kDriftedTable[16]" want="16" got="18" tgt="test/docdriftfix/code.h:14"/>
<a k="const" l="3628" c="53" why="const-value" ref="kDriftedLimit = 10" want="10" got="15" tgt="test/docdriftfix/code.h:11"/>
<a k="array" l="3629" c="54" why="array-extent" ref="kDriftedTable[16]" want="16" got="18" tgt="test/docdriftfix/code.h:14"/>
<a k="const" l="3656" c="53" why="const-value" ref="kDriftedLimit = 10" want="10" got="15" tgt="test/docdriftfix/code.h:11"/>
<more drift="20"/>
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
<doc p="docs/EVALS.md" anchors="1162" checked="555" drift="6" dated="70">
<a k="symbol" l="1674" c="55" why="undefined" kind="dated-record" rec="block" ref="RuntimeTemplate"/>
<a k="file-line" l="2848" c="84" why="line-moved" kind="dated-record" rec="block" ref="graph.h:648" sym="buildFieldNarrowTables" got="(file scope)" tgt="src/graph.h:670"/>
<a k="file-line" l="2979" c="37" why="line-moved" kind="dated-record" rec="block" ref="graph.h:648" sym="buildFieldNarrowTables" got="(file scope)" tgt="src/graph.h:670"/>
… [120 more display lines; full output is 18291 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --doc-drift --gateability`

*The finishable to-do list: docs whose LIVE failing anchors a date-stamp would reclassify.*

`````
<!-- ripwire doc drift: the CHECKABLE anchors in this repo's markdown, verified against the live index, reporting only the ones that no longer hold. Four kinds: file:line refs (missing-file / past-eof / line-moved, the last only when the doc names a symbol on that line), backticked symbol mentions (undefined), `= N` constants and `[N]` array extents (value/extent vs the declaration). Every lane under reports on purpose: a name is stale only when it occurs NOWHERE in the code as an identifier, and a number is compared only against a declaration shaped literal the corpus binds uniquely. checked + unchecked == anchors: nothing is dropped silently, and the unchecked rows say what was not proved. Read why="undefined" precisely: it says the name is defined NOWHERE in this repo, which is not the same as DELETED — in a plan or design doc naming work not yet built, that is expected rather than rot. Run with the with_history flag to have git history separate the two: the lane then reports why="deleted" with the commit that removed the name, and downgrades a name this repo never had to unchecked r="never in history". A failed anchor the AUTHOR DATED is split out as kind="dated-record" and counted in dated= rather than drift=: an audit finding, a ledger row or an as-of-DATE hedge records what was true then, so drift= is the LIVE rot and drift + dated is every anchor that no longer holds. rec= names the evidence (line / block / title / stamp), and a doc that never writes its own date anywhere a machine can read reports LIVE — the lane reads dating marks, it does not guess genre. Attribute vocabulary, one name one meaning: at= appears ONLY on this root element and is the commit the run was measured against (short sha, plus dirty when the tree had uncommitted changes); ref= is the anchor as the DOC writes it; got= is what the corpus actually says; and tgt= is the corpus SITE backing got= (a path, or path:line). On the <a/> rows k= and kind= are DIFFERENT things and both are kept: k= is the ANCHOR kind (file-line / symbol / const / array), kind= is the record classification (dated-record). k= cannot be renamed to kind= here for the obvious reason that kind= is already taken on the same element; note that in the ranked map the same k= spelling is a PageRank score instead. Docs are ordered by LIVE drift descending (path breaks ties), so the worst rot leads and a fully dated doc, which is drift zero by construction, sinks on the same key. Prose claims, Status lines and dates are NOT checked. A `path:A-B` RANGE gets one more structural check: why="range-straddles" fires when A's innermost symbol does not reach B (got= then names whatever occupies B instead, tgt= that site), regardless of whether the doc names a symbol. weak-file-line, the one unchecked reason that names no symbol, gets a FREE disclosure instead of a verdict: <weak-file-line p= n=> groups, one per doc, list every such anchor whose line DOES sit inside an indexed symbol, and each <w> row's resolves-to= names it — the verb still does not know if that is the symbol the doc meant. This section sits beside, not inside, the <doc> rows: a doc can appear in it while still counting toward clean=, and every row it lists still counts once in the unchecked r="weak-file-line" tally below. FOUR COUNTERS on this element name four DIFFERENT populations, stated here because one of them openly disagrees with a number the map reports elsewhere. docs= is the DOCUMENTS scanned for anchors (markdown by extension, after any filter); it is the denominator of the doc rows below. clean= is how many of those docs came out with NO failed anchor — drift and dated both zero for that doc — so docs minus clean is exactly the number of <doc> rows below, before any paging window is applied. A doc whose anchors were all unchecked, or all prose, is clean here: clean means nothing was found rotten, not that everything was verified. prose= is the anchors dropped as prose, so it is SUBTRACTED from anchors= rather than added to it, and the verb does not claim to have checked them; only the VALUE shapes (`= N` and `[N]`) can be dropped this way, and the drop is itself a corpus lookup — the name was searched for and not found in code — not a pre-check guess. corpus= is the file population the anchors were checked AGAINST, and it is its OWN population rather than a relation to the map's files=: the indexed files this walk could re-read, PLUS a fixed set of config, shader and build-file extensions (CMakeLists.txt, .cmake, .yml/.yaml, .toml, .metal/.glsl/.hlsl and the like — an extension whitelist, never a content sniff), MINUS every file this walk could not open or that exceeded its own 4 MiB read ceiling, which is dropped silently and never counted. So corpus= is USUALLY larger than files= and that is the normal case, but it is not always: a crawl run whose max file size ceiling was raised above 4 MiB indexes files this walk still refuses, and a file the index lists but this run cannot open is counted by one and not the other. Neither number is wrong. corpus="0" means the corpus scan never ran at all, which happens only when the docs raised no anchor SHAPE whatsoever — prose ones included — so anchors="0" beside a non-zero prose= still scanned, and still reports the corpus it scanned. -->
<doc-drift docs="145" clean="126" anchors="2468" checked="965" unchecked="1503" drift="61" dated="80" prose="9" corpus="1619" at="c7725f3ef">
<doc p="docs/COMMANDS.md" anchors="137" checked="37" drift="32" dated="0">
<a k="const" l="3619" c="53" why="const-value" ref="kDriftedLimit = 10" want="10" got="15" tgt="test/docdriftfix/code.h:11"/>
<a k="array" l="3620" c="54" why="array-extent" ref="kDriftedTable[16]" want="16" got="18" tgt="test/docdriftfix/code.h:14"/>
<a k="const" l="3621" c="53" why="const-value" ref="kDriftedLimit = 10" want="10" got="15" tgt="test/docdriftfix/code.h:11"/>
<a k="array" l="3622" c="54" why="array-extent" ref="kDriftedTable[16]" want="16" got="18" tgt="test/docdriftfix/code.h:14"/>
<a k="const" l="3623" c="53" why="const-value" ref="kDriftedLimit = 10" want="10" got="15" tgt="test/docdriftfix/code.h:11"/>
<a k="const" l="3624" c="53" why="const-value" ref="kDriftedLimit = 10" want="10" got="15" tgt="test/docdriftfix/code.h:11"/>
<a k="array" l="3625" c="54" why="array-extent" ref="kDriftedTable[16]" want="16" got="18" tgt="test/docdriftfix/code.h:14"/>
<a k="const" l="3626" c="53" why="const-value" ref="kDriftedLimit = 10" want="10" got="15" tgt="test/docdriftfix/code.h:11"/>
<a k="array" l="3627" c="54" why="array-extent" ref="kDriftedTable[16]" want="16" got="18" tgt="test/docdriftfix/code.h:14"/>
<a k="const" l="3628" c="53" why="const-value" ref="kDriftedLimit = 10" want="10" got="15" tgt="test/docdriftfix/code.h:11"/>
<a k="array" l="3629" c="54" why="array-extent" ref="kDriftedTable[16]" want="16" got="18" tgt="test/docdriftfix/code.h:14"/>
<a k="const" l="3656" c="53" why="const-value" ref="kDriftedLimit = 10" want="10" got="15" tgt="test/docdriftfix/code.h:11"/>
<more drift="20"/>
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
<doc p="docs/EVALS.md" anchors="1162" checked="555" drift="6" dated="70">
<a k="symbol" l="1674" c="55" why="undefined" kind="dated-record" rec="block" ref="RuntimeTemplate"/>
<a k="file-line" l="2848" c="84" why="line-moved" kind="dated-record" rec="block" ref="graph.h:648" sym="buildFieldNarrowTables" got="(file scope)" tgt="src/graph.h:670"/>
<a k="file-line" l="2979" c="37" why="line-moved" kind="dated-record" rec="block" ref="graph.h:648" sym="buildFieldNarrowTables" got="(file scope)" tgt="src/graph.h:670"/>
… [138 more display lines; full output is 19818 bytes on 1 raw line(s)]
`````

Tail of the same output — the `<gateability>` section:

`````
<gateability docs="15" projected_drift="0">
<fix p="docs/COMMANDS.md" live="32"/>
<fix p="test/docdriftfix/NOTES.md" live="7"/>
<fix p="docs/EVALS.md" live="6"/>
<fix p="README.md" live="3"/>
<fix p="test/docdriftfix/live_notes.md" live="2"/>
<fix p="test/gateabilityfix/UNDATED.md" live="2"/>
<fix p="CONTRIBUTING.md" live="1"/>
<fix p="bench/PROFILE.md" live="1"/>
<fix p="bench/nestcal/r1-2026-08-07/REPORT.md" live="1"/>
<fix p="docs/OPTREMARKS.md" live="1"/>
<fix p="skills/ripwire-fresh-eyes/SKILL.md" live="1"/>
<fix p="skills/ripwire-mcp/SKILL.md" live="1"/>
<fix p="skills/ripwire-opt-remarks/SKILL.md" live="1"/>
<fix p="test/docdriftfix/record_line.md" live="1"/>
<fix p="test/gateabilityfix/MIXED.md" live="1"/>
</gateability>
</doc-drift>
`````

## `./build/ripwire . --doc-drift --with-history`

*Same report, with git history splitting stale mentions into deleted-by-commit vs never-existed.*

`````
<!-- ripwire doc drift: the CHECKABLE anchors in this repo's markdown, verified against the live index, reporting only the ones that no longer hold. Four kinds: file:line refs (missing-file / past-eof / line-moved, the last only when the doc names a symbol on that line), backticked symbol mentions (undefined), `= N` constants and `[N]` array extents (value/extent vs the declaration). Every lane under reports on purpose: a name is stale only when it occurs NOWHERE in the code as an identifier, and a number is compared only against a declaration shaped literal the corpus binds uniquely. checked + unchecked == anchors: nothing is dropped silently, and the unchecked rows say what was not proved. Read why="undefined" precisely: it says the name is defined NOWHERE in this repo, which is not the same as DELETED — in a plan or design doc naming work not yet built, that is expected rather than rot. Run with the with_history flag to have git history separate the two: the lane then reports why="deleted" with the commit that removed the name, and downgrades a name this repo never had to unchecked r="never in history". A failed anchor the AUTHOR DATED is split out as kind="dated-record" and counted in dated= rather than drift=: an audit finding, a ledger row or an as-of-DATE hedge records what was true then, so drift= is the LIVE rot and drift + dated is every anchor that no longer holds. rec= names the evidence (line / block / title / stamp), and a doc that never writes its own date anywhere a machine can read reports LIVE — the lane reads dating marks, it does not guess genre. Attribute vocabulary, one name one meaning: at= appears ONLY on this root element and is the commit the run was measured against (short sha, plus dirty when the tree had uncommitted changes); ref= is the anchor as the DOC writes it; got= is what the corpus actually says; and tgt= is the corpus SITE backing got= (a path, or path:line). On the <a/> rows k= and kind= are DIFFERENT things and both are kept: k= is the ANCHOR kind (file-line / symbol / const / array), kind= is the record classification (dated-record). k= cannot be renamed to kind= here for the obvious reason that kind= is already taken on the same element; note that in the ranked map the same k= spelling is a PageRank score instead. Docs are ordered by LIVE drift descending (path breaks ties), so the worst rot leads and a fully dated doc, which is drift zero by construction, sinks on the same key. Prose claims, Status lines and dates are NOT checked. A `path:A-B` RANGE gets one more structural check: why="range-straddles" fires when A's innermost symbol does not reach B (got= then names whatever occupies B instead, tgt= that site), regardless of whether the doc names a symbol. weak-file-line, the one unchecked reason that names no symbol, gets a FREE disclosure instead of a verdict: <weak-file-line p= n=> groups, one per doc, list every such anchor whose line DOES sit inside an indexed symbol, and each <w> row's resolves-to= names it — the verb still does not know if that is the symbol the doc meant. This section sits beside, not inside, the <doc> rows: a doc can appear in it while still counting toward clean=, and every row it lists still counts once in the unchecked r="weak-file-line" tally below. FOUR COUNTERS on this element name four DIFFERENT populations, stated here because one of them openly disagrees with a number the map reports elsewhere. docs= is the DOCUMENTS scanned for anchors (markdown by extension, after any filter); it is the denominator of the doc rows below. clean= is how many of those docs came out with NO failed anchor — drift and dated both zero for that doc — so docs minus clean is exactly the number of <doc> rows below, before any paging window is applied. A doc whose anchors were all unchecked, or all prose, is clean here: clean means nothing was found rotten, not that everything was verified. prose= is the anchors dropped as prose, so it is SUBTRACTED from anchors= rather than added to it, and the verb does not claim to have checked them; only the VALUE shapes (`= N` and `[N]`) can be dropped this way, and the drop is itself a corpus lookup — the name was searched for and not found in code — not a pre-check guess. corpus= is the file population the anchors were checked AGAINST, and it is its OWN population rather than a relation to the map's files=: the indexed files this walk could re-read, PLUS a fixed set of config, shader and build-file extensions (CMakeLists.txt, .cmake, .yml/.yaml, .toml, .metal/.glsl/.hlsl and the like — an extension whitelist, never a content sniff), MINUS every file this walk could not open or that exceeded its own 4 MiB read ceiling, which is dropped silently and never counted. So corpus= is USUALLY larger than files= and that is the normal case, but it is not always: a crawl run whose max file size ceiling was raised above 4 MiB indexes files this walk still refuses, and a file the index lists but this run cannot open is counted by one and not the other. Neither number is wrong. corpus="0" means the corpus scan never ran at all, which happens only when the docs raised no anchor SHAPE whatsoever — prose ones included — so anchors="0" beside a non-zero prose= still scanned, and still reports the corpus it scanned. history probed="1" means the git-log name-history walk ran: commits= is how many it read (runProbe's own no-merges log, so a name deleted only inside a merge commit is invisible and not counted either), removed-names= how many distinct names it saw deleted at least once, and truncated="1" (absent = not hit) means the walk stopped at its own commit ceiling before reaching the root. probed="0" r= says why it did not run at all (not-a-git-repo or probe-failed) — none of the other attributes are then present. -->
<doc-drift docs="145" clean="129" anchors="2468" checked="955" unchecked="1513" drift="60" dated="71" prose="9" corpus="1619" at="c7725f3ef">
<history probed="1" head="c7725f3ef" commits="1398" removed-names="29937"/>
<doc p="docs/COMMANDS.md" anchors="137" checked="37" drift="32" dated="0">
<a k="const" l="3619" c="53" why="const-value" ref="kDriftedLimit = 10" want="10" got="15" tgt="test/docdriftfix/code.h:11"/>
<a k="array" l="3620" c="54" why="array-extent" ref="kDriftedTable[16]" want="16" got="18" tgt="test/docdriftfix/code.h:14"/>
<a k="const" l="3621" c="53" why="const-value" ref="kDriftedLimit = 10" want="10" got="15" tgt="test/docdriftfix/code.h:11"/>
<a k="array" l="3622" c="54" why="array-extent" ref="kDriftedTable[16]" want="16" got="18" tgt="test/docdriftfix/code.h:14"/>
<a k="const" l="3623" c="53" why="const-value" ref="kDriftedLimit = 10" want="10" got="15" tgt="test/docdriftfix/code.h:11"/>
<a k="const" l="3624" c="53" why="const-value" ref="kDriftedLimit = 10" want="10" got="15" tgt="test/docdriftfix/code.h:11"/>
<a k="array" l="3625" c="54" why="array-extent" ref="kDriftedTable[16]" want="16" got="18" tgt="test/docdriftfix/code.h:14"/>
<a k="const" l="3626" c="53" why="const-value" ref="kDriftedLimit = 10" want="10" got="15" tgt="test/docdriftfix/code.h:11"/>
<a k="array" l="3627" c="54" why="array-extent" ref="kDriftedTable[16]" want="16" got="18" tgt="test/docdriftfix/code.h:14"/>
<a k="const" l="3628" c="53" why="const-value" ref="kDriftedLimit = 10" want="10" got="15" tgt="test/docdriftfix/code.h:11"/>
<a k="array" l="3629" c="54" why="array-extent" ref="kDriftedTable[16]" want="16" got="18" tgt="test/docdriftfix/code.h:14"/>
<a k="const" l="3656" c="53" why="const-value" ref="kDriftedLimit = 10" want="10" got="15" tgt="test/docdriftfix/code.h:11"/>
<more drift="20"/>
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
<doc p="docs/EVALS.md" anchors="1162" checked="550" drift="6" dated="65">
<a k="symbol" l="1674" c="55" why="deleted" kind="dated-record" rec="block" ref="RuntimeTemplate" got="removed in 27209b7c7 (2026-08-08)" tgt="bench/r7/out/webpack/scores.tsv"/>
<a k="file-line" l="2848" c="84" why="line-moved" kind="dated-record" rec="block" ref="graph.h:648" sym="buildFieldNarrowTables" got="(file scope)" tgt="src/graph.h:670"/>
… [111 more display lines; full output is 18894 bytes on 1 raw line(s)]
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
<ctx task="&lt;stdin&gt;" next="--slice=@src/graph.h:1148" est_tokens="2298">
<!-- ripwire trace-to-locus for "<stdin>": frames of a asan trace mapped onto indexed symbols, ranked INNERMOST-first. frame_lines=5 parsed=4 in_corpus=4 skipped=0 (out of every root - listed, never ranked) merged=0 unresolved=0. frame_lines = frame-shaped lines the INPUT presented (a #N marker, a leading "at ", or a Python File "..." line, plus every line that did extract); parsed = how many of them yielded a usable path:line, so frame_lines - parsed is the count that matched no format shape and enters no bucket below. in_corpus = suspects + merged + unresolved, so every file-matched frame is visible: merged= folded into an already-claimed symbol, unresolved= listed as <unresolved> (indexed file, no def by name or by line). resolved_by="name" means the frame's OWN function name bound to a unique def (line_encloses=, when present, names the different symbol today's line sits in: the tell that the trace predates this checkout); resolved_by="line" means the name was absent, unknown or ambiguous, so the def enclosing that line was used. p= on a frame is the FRAME's own locator (the trace's path:line, verbatim); definition sites live in <sigs> l=. On a <sigs> row (rows in r= order): n=name, id=canonical(when scoped), p=file, t=kind, cx=cyclomatic complexity, ccx=cognitive complexity, in=reuse-count (absent = not measured, never a false 0). rank 1 = the innermost in-corpus frame; its FULL body follows, other suspects as signatures. budget=7500 bytes (allowance 9583 bytes = ceiling + the single-entry overshoot a whole first signature costs). On the root: est_tokens= prices the delivered bundle in tokens, budget_tokens= is the token target you passed (absent when none), max_tokens= is the body ceiling you passed via the max_tokens flag (absent when none); over_ceiling= is 1 when est_tokens exceeds the smallest ceiling named here (the bundle is then complete, not trimmed). next= is the one pasteable follow-up: the slice at the innermost in-corpus frame (@FILE:LINE); absent when none landed. -->
<trace src="&lt;stdin&gt;" format="asan" frame_lines="5" parsed="4" in_corpus="4" skipped="0" merged="0" unresolved="0" suspects="4">
<frame rank="1" n="rankGraphTeleport" t="fn" p="src/graph.h:1148" resolved_by="name" line_encloses="buildGraph" innermost="1"/>
<frame rank="2" n="rankGraph" t="fn" p="src/graph.h:1174" resolved_by="name" line_encloses="buildGraph"/>
<frame rank="3" n="runDefaultMap" t="fn" p="src/main.cpp:5155" resolved_by="name"/>
<frame rank="4" n="main" t="fn" p="src/main.cpp:5594" resolved_by="name"/>
</trace>
<sigs>
<d l="2501" n="rankGraphTeleport" id="src/graph.h::rw::rankGraphTeleport" p="src/graph.h" cx="5" ccx="8" in="6" r="1" next="--expand=src/graph.h:rankGraphTeleport">
<doc>PageRank with an explicit teleport / personalization vector p (Σp = 1). The prior is name-quality-biased through biasPrior() so all rank modes share one weighting seam; the transition matrix (edges</doc>inline RankedGraph rankGraphTeleport( const Graph&amp; g, const std::vector&lt;float&gt;&am … [line truncated: 31 more bytes on this line]
<d l="2542" n="rankGraph" id="src/graph.h::rw::rankGraph" p="src/graph.h" cx="2" ccx="1" in="9" r="2">
<doc>uniform-teleport PageRank (the default</doc>inline RankedGraph rankGraph( const Graph&amp; g, float alpha = 0.85f )</d>
<d l="1098" n="runDefaultMap" p="src/main.cpp" cx="135" ccx="198" in="1" r="3">int runDefaultMap( const MainDispatch&amp; d )</d>
<d l="2634" n="main" p="src/main.cpp" cx="4" ccx="3" in="0" r="4">int main( int argc, char** argv )</d>
</sigs>
<bodies shown="1" total="1" capped="0">
<b t="fn" l="2501" p="src/graph.h" n="rankGraphTeleport">
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
… [17 more display lines; full output is 5744 bytes on 29 raw line(s)]
`````

## `./build/ripwire . --notes`

*List all field notes (write-side memory) — the committed .ripwire_notes at the repo root, each with the sha/branch it was recorded at.*

`````
<ctx>
<!-- ripwire field notes: notes=1 targets=1 dangling=0 (a target with no matching indexed symbol/file — legal: listed here, surfaced nowhere). Each note row: d= is the ISO date it was recorded; sha= the abbreviated commit and branch= the branch checked out at record time, both omitted entirely on a note stored before provenance stamping (absent means none recorded, never empty) -->
<notes>
<target id="test/manifestcheck.sh" dangling="0">
<note d="2026-08-23" sha="42634f5" branch="claude/fervent-volhard-ddfd9f">
<![CDATA[README.md's single '<N> gate scripts' claim (~line 1305) is NOT enforced — the derived-vs-stated sibling loop here covers docs/EVALS.md only. It drifted 407→451 unnoticed (fixed 2026-08-23). To close: grep both files ('file:line:' parsing) in the gateCountClaims arm.]]>
</note>
</target>
</notes>
</ctx>
`````

## `./build/ripwire . --pack-task="add a new output format flag to the CLI"`

*ONE budget-shared bundle: ranking + top bodies + caller sigs + notes + tests_to_run. CHANGED: <d> rows now carry n=/id=.*

`````
<ctx task="add a new output format flag to the CLI" route="routed: subtoken+body BM25 (--for&apos;s default) — no strong name hit, multi-word conceptual query" root="." est_tokens="3670" budget_tokens="6000">
<!-- ripwire task bundle for "add a new output format flag to the CLI": one-call orientation under ONE budget — sections in FIXED order ranking > bodies > callers > notes > tests, quotas per section are FIXED (rank40/body30/caller15/note5/test10, percent of budget), unused quota ROLLS FORWARD to the next section — a small budget still zeroes a section, but never past its own share. each truncates rank-adaptively; every truncation reported here (no silent caps): on every section shown=rows kept, total=rows that qualified, capped=1 when they differ. bodies fill rank-first, so a bigger budget can keep FEWER, larger bodies — the count is not a quality measure. Row keys: n=name (chain it), id=canonical(when scoped), in=reuse-count (absent = not measured, never a false 0), l=line, p=path, t=kind, cx=cyclomatic, ccx=cognitive, rel=caller|callee, r=rank in this ranking (rows in r= order); far=ranked but over 1 hop out; of_top denominator is per-section. callers: sorted by shared desc (ties=site order); shared=# of top-K anchors reached, omitted at 1. On the root: est_tokens= prices the delivered bundle in tokens (markup at the map rate, bodies at the body rate), budget_tokens= is the token target; over_ceiling= is 1 when est_tokens exceeds it (the bundle is then complete, not trimmed). budget=12744 bytes (6000-token target, ceiling 14160) | ranking: full | bodies: 6 of 6 | callers: 13 of 13 | notes: none | tests: none | far: 6 of 6 -->
<!-- root= on this element is the crawl root every p= below is RELATIVE to (single-root runs only; absent => p= is the path ingest itself used, unchanged). -->
<sigs>
<d l="103" n="toUint" id="src/tracein.h::detail::toUint" p="src/tracein.h" cx="3" ccx="3" in="3" r="1" next="--expand=src/tracein.h:toUint">
<doc>F7: a hostile/garbled frame line number (e.g. a fuzzed or truncated trace) can exceed UINT32_MAX; unchecked `v*10+d` wraps mod 2^32 (4294967297 -&gt; 1), which then confidently maps to a REAL line in the</doc>inline std::uint32_t toUint( std::string_view s, bool&amp; overflowed ) noexcept</d>
<d l="253" n="McpValueSpec" id="src/mcprefusal.h::McpValueSpec::McpValueSpec" p="src/mcprefusal.h" cx="0" ccx="0" in="0" r="2">
<doc>verifier N2/N3/N11: the bad-VALUE refusal table</doc>struct McpValueSpec</d>
<d l="2366" n="kJsonShapeModifiers" p="src/main.cpp" cx="0" ccx="0" in="0" pure="1" r="3">
<doc>B1.4: the output-SHAPE members of the list above, as a table rather than a second if-chain. A flag in here selects an ENCODING for rows some verb already produced, so &quot;--json is not supported for X</doc>inline constexpr std::string_view kJsonShapeModifiers[] =</d>
<d l="2748" n="kHandWrittenFlagArms" id="src/cli.h::rw::kHandWrittenFlagArms" p="src/cli.h" cx="0" ccx="0" in="0" pure="1" r="4">
<doc>table was the disease, so 23 of them became kViewFlags rows (33 → 56) once that table grew the EmptyValue and isSetFlag columns. kTotalFlagArms is unchanged, which is exactly what this tripwire is f</doc>inline constexpr std::size_t kHandWrittenFlagArms = 22</d>
<d l="2264" n="BoolFlag" id="src/cli.h::BoolFlag::BoolFlag" p="src/cli.h" cx="0" ccx="0" in="0" r="5">
<doc>offsetof, which would be UB on a non-standard-layout type. ORDER. The tables are scanned in DECLARATION ORDER, exacts before prefixes, ahead of the hand-written arms — so the chain&apos;s original preced</doc>struct BoolFlag</d>
<d l="4434" n="addSchemeAliases" id="src/quality.h::quality::addSchemeAliases" p="src/quality.h" cx="14" ccx="18" in="1" r="6">
<doc>byte strings), so a migrated ledger passes through untouched. No ledger version flag, no transition window, and --quality-ack writes the healed rows back so a rescued ack stops depending on the replay</doc>inline void addSchemeAliases( IdentityAliases&amp; al, const IngestResult&amp; ing, const … [line truncated: 42 more bytes on this line]
<far of_top="12" shown="6" total="6" capped="0">
<s t="var" n="kMcpRequiredFields" p="src/mcprefusal.h:66"/>
<s t="fn" n="formatRecallSeparator" p="src/recall.h:677"/>
<s t="fn" n="mcpFreshFields" p="src/mcpindex.h:873"/>
<s t="fn" n="gitDiffHunksVsHead" p="src/quality.h:3465"/>
<s t="fn" n="runProbe" p="src/gitoracle.h:592"/>
<s t="fn" n="qualityDeltaJson" p="src/mcpverbs.h:3106"/>
</far>
</sigs>
<bodies shown="6" total="6" capped="0">
<b t="fn" l="103" p="src/tracein.h" n="toUint">
<![CDATA[inline std::uint32_t toUint( std::string_view s, bool& overflowed ) noexcept
{
    std::uint32_t v = 0;
… [63 more display lines; full output is 10716 bytes on 66 raw line(s)]
`````

## `./build/ripwire . --pack-task="add a new output format flag to the CLI" --partition=3`

*Fan-out form: one shared core + 3 per-agent slices carved along call-graph communities.*

`````
<ctx-partitions partitions="3" requested="3" core_symbols="6" surface="42" modules="18" split="0" budget_per_agent_tokens="6000" core_budget_tokens="2040" partition_budget_tokens="3960" total_bytes="23330" overlap_mean="0.010" overlap_max="0.017" shared_symbols="2" union_symbols="94" core_overlap="0 … [line truncated: 6 more bytes on this line]
<!-- ripwire partitioned task bundle: ONE shared core plus N minimally overlapping slices along call-graph communities; each <bundle> is one agent's ctx. requested=N asked, partitions= carved; modules=/split= groups found / cuts forced; core_symbols= the shared core, surface= core plus the assignable remainder; budget_per_agent_tokens= core plus ONE partition (= core_budget_tokens + partition_budget_tokens), total_bytes= all bundles; overlap_mean=/overlap_max= pairwise Jaccard over the ids partitions name, pre-trim; shared_symbols= the ids TWO OR MORE partitions name, union_symbols= ids any names (ratio and overlap_mean COINCIDE at partitions=2 only); core_overlap= the core surface a partition reaches anyway; tokens= = est_tokens= (bytes / 2.36). Each ctx carries NO legend: the task-bundle legend follows once; a trimmed slice carries one data comment. -->
<!-- ripwire task bundle (every ctx below): one-call orientation under ONE budget — sections in FIXED order ranking > bodies > callers > notes > tests, quotas per section are FIXED (rank40/body30/caller15/note5/test10, percent of budget), unused quota ROLLS FORWARD to the next section — a small budget still zeroes a section, but never past its own share. each truncates rank-adaptively; every truncation reported here (no silent caps): on every section shown=rows kept, total=rows that qualified, capped=1 when they differ. bodies fill rank-first, so a bigger budget can keep FEWER, larger bodies — the count is not a quality measure. Row keys: n=name (chain it), id=canonical(when scoped), in=reuse-count (absent = not measured, never a false 0), l=line, p=path, t=kind, cx=cyclomatic, ccx=cognitive, rel=caller|callee, r=rank in this ranking (rows in r= order); far=ranked but over 1 hop out; of_top denominator is per-section. callers: sorted by shared desc (ties=site order); shared=# of top-K anchors reached, omitted at 1. On the root: est_tokens= prices the delivered bundle in tokens (markup at the map rate, bodies at the body rate), budget_tokens= is the token target; over_ceiling= is 1 when est_tokens exceeds it (the bundle is then complete, not trimmed).  -->
<bundle role="core" symbols="6" bytes="2785" tokens="1180" est_tokens="1180">
<ctx task="add a new output format flag to the CLI" route="routed: subtoken+body BM25 (--for&apos;s default) — no strong name hit, multi-word conceptual query" root="." dropped_positive="2" est_tokens="963" budget_tokens="2040">
<!-- slice budget=4332 bytes (2040-token target, ceiling 4814) | ranking: capped | bodies: kept 4 of 6 (capped) | callers: kept 1 of 13 | notes: none | tests: none | far: none -->
<sigs shown="4" total="6" capped="1">
<d l="103" n="toUint" id="src/tracein.h::detail::toUint" p="src/tracein.h" cx="3" ccx="3" in="3" r="1" next="--expand=src/tracein.h:toUint">
<doc>F7: a hostile/garbled frame line number (e.g. a fuzzed or truncated trace) can exceed UINT32_MAX…</doc>inline std::uint32_t toUint( std::string_view s, bool&amp; overflowed ) noexcept</d>
<d l="253" n="McpValueSpec" id="src/mcprefusal.h::McpValueSpec::McpValueSpec" p="src/mcprefusal.h" cx="0" ccx="0" in="0" r="2">
<doc>verifier N2/N3/N11: the bad-VALUE refusal table</doc>struct McpValueSpec</d>
<d l="2366" n="kJsonShapeModifiers" p="src/main.cpp" cx="0" ccx="0" in="0" pure="1" r="3">
<doc>B1.4: the output-SHAPE members of the list above, as a table rather than a second if-chain. A fl…</doc>inline constexpr std::string_view kJsonShapeModifiers[] =</d>
<d l="2748" n="kHandWrittenFlagArms" id="src/cli.h::rw::kHandWrittenFlagArms" p="src/cli.h" cx="0" ccx="0" in="0" pure="1" r="4">
<doc>table was the disease, so 23 of them became kViewFlags rows (33 → 56) once that table grew the…</doc>inline constexpr std::size_t kHandWrittenFlagArms = 22</d>
</sigs>
<bodies shown="4" total="6" capped="1">
<b t="fn" l="103" p="src/tracein.h" n="toUint">
<![CDATA[inline std::uint32_t toUint( std::string_view s, bool& overflowed ) noexcept
{
    std::uint32_t v = 0;
    for( const char c : s )   // callers pass only isDigits() spans
    {
        const std::uint32_t d = std::uint32_t( c - '0' );
        if( v > ( UINT32_MAX - d ) / 10u ) { overflowed = true; return 0; }
        v = v * 10u + d;
    }
    return v;
}]]></b><b t="var" l="2366" p="src/main.cpp" n="kJsonShapeModifiers"><![CDATA[inline constexpr std::string_view kJsonShapeModifiers[] = { "--format=columnar", "--format=candidates", "--detail", "--scip" };]]></b><b t="var" l="2748" p="src/cli.h" n="kHandWrittenFlagArms"><![CDATA[inline constexpr std … [line truncated: 3788 more bytes on this line]
{
… [206 more display lines; full output is 26217 bytes on 135 raw line(s)]
`````

## `./build/ripwire . --for="pagerank power iteration" --with-graph`

*Task lens + a compact Mermaid flowchart of the top anchors' 1-hop edges.*

`````
<ctx task="pagerank power iteration" route="routed: subtoken+body BM25 (--for&apos;s default) — no strong name hit, multi-word conceptual query" root="." confidence="low" margin_pct="0" at="c7725f3ef" doc_mentions="4" bundle="compact" bodies="0" reason="compact-route" est_tokens="3923">
<!-- ripwire lens for "pagerank power iteration" [doc mentions: 4 docs discussing 3 top-ranked symbols surfaced; doc_mentions= on the root repeats the doc count] [confidence= derives from the ranked head's largest relative score drop (margin_pct=, whole percent, 0 = none; the same gap the adaptive flag cuts at). low = flat ranking: treat the set as a starting point, not an answer]: reusable building blocks + quality facts for what you're about to touch (cx=complexity ccx=cognitive in=reuse-count churn=recent-commits amp=change-amplification clone=1(duplicated) tested=1) — prefer composing/reusing these; watch the high-churn/high-amp/cloned ones; bundle=compact: conceptual query, so this map ships one-hop EDGE context, no bodies (bodies=0, reason=compact-route or no_candidates). hops rows are h l=line p=file n=name, and a row's calls child names its callees (c n= l=). hops and calls disclose total=requested shown=printed capped=1 when the BUDGET cut a listing; noedge=N counts ranked symbols with no RESOLVED callee found (never none exists). For a body: expand=p:n pasted off a row; the auto-bodies flag puts the bodies back; tail: file-grain tail, WEAKER evidence than the ranked rows (paths only): the remaining candidate files with a positive score, best-symbol rank order; rows are t p=file; total=candidate files, shown=printed, capped=1 when they differ. r= on a ranked row is its 1-based rank in this lens ranking, rows in r= order, p= the file (a gap = a budget-trimmed row) -->
<!-- root= is the crawl root; p= below is RELATIVE to it (single-root only; absent => p= is ingest's own path, unchanged); at=this commit(+dirty). dropped_positive="16" est_tokens= prices this bundle in tokens -->
<sigs shown="24" total="40" capped="1">
<d l="40" n="HOT_FILES" p="scripts/optremarks.py" cx="0" ccx="0" in="0" churn="3" amp="37" r="1" next="--expand=scripts/optremarks.py:HOT_FILES">HOT_FILES = ( &quot;src/pagerank.cpp&quot;, # the power-iteration loop — G2&apos;s no-allocation scope &quot;src/infra/radixSort.h&quot;, # LSD radix ent … [line truncated: 42 more bytes on this line]
<d l="73" n="renderDisclosure" id="src/prconverge.h::rw::renderDisclosure" p="src/prconverge.h" cx="12" ccx="15" in="13" churn="2" amp="30" r="2">
<doc>Render one form of the disclosure. Empty string whenever there is nothing to say — no power it…</doc>inline std::string renderDisclosure( const RankDisclosure&amp; d, DiscloseAs as )</d>
<d l="51" n="RankDisclosure" id="src/prconverge.h::RankDisclosure::RankDisclosure" p="src/prconverge.h" cx="0" ccx="0" in="0" churn="2" amp="17" r="3">
<doc>What a ranked document discloses about the power iteration that ordered it. `isPageRank == false…</doc>struct RankDisclosure</d>
<d l="2492" n="RankedGraph" id="src/graph.h::RankedGraph::RankedGraph" p="src/graph.h" cx="0" ccx="0" in="0" churn="59" amp="194" r="4">
<doc>What a rank call hands back: the vector, and the power iteration&apos;s own account of itself. Struct…</doc>struct RankedGraph</d>
<d l="1550" n="kChurnRankLegend" id="src/serialize.h::rw::kChurnRankLegend" p="src/serialize.h" cx="0" ccx="0" in="0" churn="99" amp="246" pure="1" r="5">inline constexpr const char* kChurnRankLegend = &quot;&lt;!-- rank_by=churn: k= is PageRank re-run with the teleport BIASED by git CHANGE-FREQUENC … [line truncated: 39 more bytes on this line]
<d l="31" n="PageRankRun" id="src/pagerank.h::PageRankRun::PageRankRun" p="src/pagerank.h" cx="0" ccx="0" in="0" churn="6" amp="20" r="6">struct PageRankRun</d>
<d l="95" n="pageRankDouble" id="src/pagerank.cpp::rw::pageRankDouble" p="src/pagerank.cpp" cx="19" ccx="34" in="2" churn="7" amp="22" tested="1" r="7">PageRankRun pageRankDouble( const sparseCsr&lt;float&gt;&amp; inEdges, std::span&lt;const double&gt; weightedOutDegree, std::span&lt;const double&gt … [line truncated: 47 more bytes on this line]
<d l="2501" n="rankGraphTeleport" id="src/graph.h::rw::rankGraphTeleport" p="src/graph.h" cx="5" ccx="8" in="6" churn="59" amp="200" r="8">inline RankedGraph rankGraphTeleport( const Graph&amp; g, const std::vector&lt;float&gt;&amp; p, float alpha = 0.85f )</d>
<d l="983" n="churnRankedGraph" p="src/main.cpp" cx="13" ccx="18" in="1" churn="271" amp="420" r="9">inline ChurnRanking churnRankedGraph( const MainDispatch&amp; d )</d>
<d l="5542" n="Wave-2 adversarial verification (2026-08-19) — six probes against `aa97c9e`" id="docs/EVALS.md::6. Correctness and quality instruments::Wave-2 adversarial verification (2026-08-19) — six probes against `aa97c9e`" p="docs/EVALS.md" cx="0" ccx="0" in="0" churn="492" amp="683" r="10" … [line truncated: 86 more bytes on this line]
<d l="1389" n="MapAnnotations" id="src/serialize.h::MapAnnotations::MapAnnotations" p="src/serialize.h" cx="0" ccx="0" in="0" churn="99" amp="246" r="11">struct MapAnnotations</d>
<d l="2199" n="leftmost_leaf" id="src/infra/dynamic_map.hpp::dynamic_map::leftmost_leaf" p="src/infra/dynamic_map.hpp" layer="infra" cx="2" ccx="1" in="7" churn="4" amp="24" tested="1" pure="1" r="12">handle_t leftmost_leaf() const</d>
<d l="54" n="testIterationCeiling" p="src/pagerank.cpp" cx="7" ccx="9" in="1" churn="7" amp="21" tested="1" r="13">std::uint32_t testIterationCeiling() noexcept</d>
<d l="1490" n="rankByLegendFor" id="src/serialize.h::rw::rankByLegendFor" p="src/serialize.h" cx="4" ccx="4" in="1" churn="99" amp="247" r="14">inline const char* rankByLegendFor( const char* label ) noexcept</d>
<d l="1008" n="denseIdOfRoot" id="src/clones.h::rw::denseIdOfRoot" p="src/clones.h" cx="1" ccx="0" in="0" churn="17" amp="53" r="15">std::vector&lt;std::uint32_t&gt; denseIdOfRoot( symbolCount, UINT32_MAX )</d>
<d l="998" n="finalizeCrawlSkips" p="src/ingest_crawl.h" cx="2" ccx="1" in="1" churn="6" amp="44" tested="1" r="16">void finalizeCrawlSkips( CrawlSkips&amp; skips, const HashMap&lt;std::string, std::uint64_t&gt;&amp; extTally )</d>
<d l="132" n="probe_args" p="test/budgetpolicycheck.sh" layer="test" cx="2" ccx="0" in="1" churn="2" amp="13" r="17">probe_args()</d>
<d l="57" n="ColdParseReserve" id="src/ingest_parsepool.h::ColdParseReserve::ColdParseReserve" p="src/ingest_parsepool.h" cx="0" ccx="0" in="0" churn="3" amp="11" r="18">struct ColdParseReserve</d>
<d l="104" n="CommunityGroups" id="src/partition.h::CommunityGroups::CommunityGroups" p="src/partition.h" cx="0" ccx="0" in="0" churn="11" amp="19" r="19">struct CommunityGroups</d>
<d l="11" n="PageRankConfig" id="src/pagerank.h::PageRankConfig::PageRankConfig" p="src/pagerank.h" cx="0" ccx="0" in="0" churn="6" amp="20" r="20">struct PageRankConfig</d>
<d l="1163" n="values_begin" id="src/infra/dynamic_map.hpp::dynamic_map::values_begin" p="src/infra/dynamic_map.hpp" layer="infra" cx="2" ccx="1" in="3" churn="4" amp="20" tested="1" r="21">value_iterator values_begin()</d>
<d l="759" n="enclosingShadowScope" p="src/ingest_binds.h" cx="9" ccx="7" in="1" churn="4" amp="39" tested="1" r="22">inline ShadowScope enclosingShadowScope( TSNode n )</d>
<d l="37" n="ownershipRowsToPrint" id="src/ownersview.h::rw::ownershipRowsToPrint" p="src/ownersview.h" cx="6" ccx="6" in="2" churn="4" amp="6" r="23">inline std::vector&lt;std::size_t&gt; ownershipRowsToPrint( const std::vector&lt;FileOwnership&gt;&amp; ownerships, int cap, bool detail )</d>
… [55 more display lines; full output is 9807 bytes on 11 raw line(s)]
`````

## `./build/ripwire . --export=cc.json:<scratch>/aux/ripwire2.cc.json`

*Per-file metrics as CodeCharta cc.json.*

`````
(empty)
`````

Artifact written:

`````
  234885 <scratch>/aux/ripwire2.cc.json
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
<![CDATA[<ctx task="incremental cache invalidation" route="routed: subtoken+body BM25 (--for&apos;s default) — no strong name hit, multi-word conceptual query" root="." confidence="high" margin_pct="20" at="c7725f3ef" doc_mentions="2" bundle="sigs" lens="churn,amp,tested" est_tokens="3509">
<!-- ripwire lens for "incremental cache invalidation" [doc mentions: 2 docs discussing 2 top-ranked symbols surfaced; doc_mentions= on the root repeats the doc count]: reusable building blocks (cx=complexity, in=reuse-count) — prefer composing/reusing these over reimplementing; bundle=sigs: signatures only in this bundle, no inline bodies — fetch a symbol's full body with the fetch_body verb [confidence= derives from the ranked head's largest relative score drop (margin_pct=, whole percent, 0 = none; the same gap the adaptive flag cuts at). low = flat ranking: treat the set as a starting point, not an answer]; lens="churn,amp,tested": the three per-row quality columns the CLI for lens carries and this dialect does NOT (they need a git and a quality pass this server does not run per request); an absent column here means NOT MEASURED, never measured-and-zero; est_tokens= prices this bundle in tokens; tail: file-grain tail, WEAKER evidence than the ranked rows (paths only): the remaining candidate files with a positive score, best-symbol rank order; rows are t p=file; total=candidate files, shown=printed, capped=1 when they differ. r= on a ranked row is its 1-based rank in this lens ranking, rows in r= order, p= the file (a gap = a budget-trimmed row) -->
<!-- root= is the crawl root; p= below is RELATIVE to it (single-root only; absent => p= is ingest's own path, unchanged). dropped_positive="16" -->
<sigs shown="24" total="40" capped="1">
<d l="106" n="kCacheMagic" p="src/ingest_cache.h" cx="0" ccx="0" in="0" pure="1" r="1" next="--expand=src/ingest_cache.h:kCacheMagic">
<doc>incremental cache (--cache): per-file content hash + raw facts so a re-run re-parses ONLY      c…</doc>constexpr std::uint32_t kCacheMagic = 0x4b505443</d>
<d l="1307" n="spanTierMemoPath" id="src/ingest_astquery.h::rw::spanTierMemoPath" p="src/ingest_astquery.h" cx="1" ccx="0" in="2" r="2">
<doc>Composed exactly the way every OTHER blob family is (quality.h): one fixed-width identity hex pe…</doc>inline std::string spanTierMemoPath( const std::string&amp; diskPath )</d>
<d l="247" n="ingestCommitTree" id="src/dmm.h::rw::dmm::ingestCommitTree" p="src/dmm.h" cx="6" ccx="5" in="1" r="3">
<doc>Ingest the tree at `sha`, materialized out of `root`&apos;s object store. The HEAD side reuses the SA…</doc>inline bool ingestCommitTree( const std::string&amp; root, const std::string&amp; sha, const std::vector&lt;std::string&gt;&amp; excludes, std::size_t maxFileBytes, IngestResult&amp;… … [line truncated: 4 more bytes on this line]
<d l="841" n="mcpRefreshedThisRequest" id="src/mcpindex.h::rw::mcpRefreshedThisRequest" p="src/mcpindex.h" cx="1" ccx="0" in="2" r="4">
<doc>P1-15 — the `_reingest` envelope field for a response whose handling ran an INCREMENTAL pass, …</doc>inline bool mcpRefreshedThisRequest( std::uint64_t passesAtEntry )</d>
<d l="789" n="FileHealth" id="src/model.h::FileHealth::FileHealth" p="src/model.h" cx="0" ccx="0" in="0" r="5">struct FileHealth</d>
<d l="770" n="mcpRebuildBaseline" id="src/mcpindex.h::rw::mcpRebuildBaseline" p="src/mcpindex.h" cx="2" ccx="1" in="1" r="6">inline McpRebuildBaseline mcpRebuildBaseline( const McpIndex&amp; ix, bool isIncrementalPass )</d>
<d l="5537" n="legoImplementorsOnSurface" id="src/serialize.h::rw::legoImplementorsOnSurface" p="src/serialize.h" cx="10" ccx="13" in="2" r="7">inline std::vector&lt;std::vector&lt;NodeId&gt;&gt; legoImplementorsOnSurface( const IngestResult&amp; ing, const std::vector&lt;std::vector&lt;NodeId&gt;&g … [line truncated: 43 more bytes on this line]
<d l="1104" n="getIndex" id="src/mcpindex.h::rw::getIndex" p="src/mcpindex.h" cx="22" ccx="39" in="32" r="8">inline const McpIndex&amp; getIndex( const std::string&amp; root )</d>
<d l="516" n="McpIndex" id="src/mcpindex.h::McpIndex::McpIndex" p="src/mcpindex.h" cx="0" ccx="0" in="0" r="9">struct McpIndex</d>
<d l="873" n="mcpFreshFields" id="src/mcpindex.h::rw::mcpFreshFields" p="src/mcpindex.h" cx="2" ccx="1" in="1" r="10">inline std::string mcpFreshFields( std::uint64_t passesAtEntry )</d>
<d l="23" n="No API key. No embeddings. No index server. No daemon." id="README.md::Give your coding agent a map before it reads the repo.::No API key. No embeddings. No index server. No daemon." p="README.md" cx="0" ccx="0" in="0" r="11">### No API key. No embeddings. No index server. No daemon.</d … [line truncated: 1 more bytes on this line]
<d l="2446" n="computeHeadSnapshot" id="src/quality.h::quality::computeHeadSnapshot" p="src/quality.h" cx="18" ccx="20" in="5" r="12">inline std::pair&lt;Snapshot, bool&gt; computeHeadSnapshot( const std::string&amp; root, const std::string_view* cacheNever = nullptr, std::size_t maxFileBytes = kDef … [line truncated: 11 more bytes on this line]
<d l="1058" n="receiptNextFor" id="src/mcpedit.h::mcpedit::receiptNextFor" p="src/mcpedit.h" cx="4" ccx="3" in="1" r="13">inline std::string receiptNextFor( const std::string&amp; fileIdentity, const std::string&amp; symbolName, const std::string&amp; foldJson, const std::string&amp; firstTestRun )< … [line truncated: 3 more bytes on this line]
<d l="191" n="ingest" id="src/ingest.cpp::rw::ingest" p="src/ingest.cpp" cx="4" ccx="3" in="14" r="14">IngestResult ingest( const char* rootDir, const std::vector&lt;std::string&gt;&amp; excludeSubstr, std::string_view cacheFile, std::size_t maxFileBytes, bool captureValueUses, std::string_view excl … [line truncated: 37 more bytes on this line]
<d l="573" n="runParsePool" p="src/ingest_parsepool.h" cx="25" ccx="65" in="1" r="15">inline RawFacts runParsePool( IngestResult&amp; result, const char* rootDir, std::string_view cacheFile, bool captureValueUses, HashMap&lt;std::string, FileFacts&gt;&amp; cache, const CacheLoadStats&amp; cacheStats … [line truncated: 56 more bytes on this line]
<d l="584" n="mcpCachePath" id="src/mcpindex.h::rw::mcpCachePath" p="src/mcpindex.h" cx="2" ccx="1" in="1" r="16">inline std::string mcpCachePath( const std::string&amp; root )</d>
<d l="1844" n="sweepStaleCacheBlobsOnce" id="src/quality.h::quality::sweepStaleCacheBlobsOnce" p="src/quality.h" cx="2" ccx="1" in="1" r="17">inline void sweepStaleCacheBlobsOnce( const std::string&amp; dir, const std::string&amp; keepPath )</d>
<d l="60" n="kCacheRuleNames" id="src/cachelint.h::rw::cachelint::kCacheRuleNames" p="src/cachelint.h" cx="0" ccx="0" in="0" pure="1" r="18">inline constexpr std::array&lt;std::string_view, 8&gt; kCacheRuleNames =</d>
<d l="1455" n="compiledQueryCache" p="src/ingest_crawl.h" cx="1" ccx="0" in="2" r="19">HashMap&lt;const TSLanguage*, TSQuery*&gt;&amp; compiledQueryCache()</d>
… [59 more display lines; full output is 24637 bytes on 1 raw line(s)]
`````


---

# self-diagnosis

## `./build/ripwire . --doctor`

*Environment self-check: binary staleness, grammars, cache dir, git, tracked-binary staleness — exit 1 when any check fails (here: the PATH install is older than ./build).*

**exit code: 1**

`````
<!-- doctor: checks=/passed= are the row count/how many passed; each <c name= ok=> is one check, its OTHER attributes are check-specific (see help). cache-dir's blobs= is capped at 4096 (kMaxCacheBlobCount); blobs_floor="1" means the cap fired and blobs= is AT LEAST that many, not exactly (absent = the true count); truncated="1" covers that AND an I/O error mid-scan, so blobs_floor= is the narrower, more useful claim when both matter. volatile= on a row NAMES that row's own attributes that read LIVE machine state — cache-dir scans a per-user directory every ripwire process writes into, so two runs of this deterministic binary legitimately differ in exactly those fields and in nothing else; a determinism comparison strips the named attributes, never the row. tracked-binaries' truncated="1" means the git-history scan was SKIPPED entirely (too many tracked files), so its stale="0" there means unmeasured, never a clean scan. -->
<doctor checks="6" passed="5" at="c7725f3ef" built_from="c7725f3ef">
<c n="binary-path" ok="0" self="./build/ripwire" which="/opt/homebrew/bin/ripwire" on_path="1" same_file="0" self_mtime="1788647941" self_size="43113720" which_mtime="1788495666" which_size="40702928" hint="STALE: /opt/homebrew/bin/ripwire is  … [line truncated: 233 more bytes on this line]
<c n="grammars" ok="1" loaded="21" expected="21"/>
<c n="cache-dir" ok="1" dir="<tmp>" blobs="4096" bytes="1558720823" many="1" truncated="0" volatile="blobs,blobs_floor,bytes,many,truncated"/>
<c n="git" ok="1" git="1" repo="1" history="1" head="c7725f3ef"/>
<c n="tree-sitter" ok="1" core_abi="15" cpp_grammar_abi="14" languages="21"/>
<c n="tracked-binaries" ok="1" tracked="2019" binaries="6" non_git="0" truncated="0" stale="0"/>
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
<!-- ripwire v1 t=fn|method|cls|struct|iface|var|sec|macro(#define;degraded:body-is-replacement-text,edges-cross-expansion) p=path layer=arch-layer(opt) n=name id=canonical(path::scope::name,when-scoped) k=rank c=call amb=ambiguous-calls(read-source) lpin=calls-pinned-by-locality-prior-alone(a-disclosed-guess;read-source;absent-if-0) overloads=N-same-name-defs-merged-into-this-row(absent-if-1;shown=counts-them-individually,so-rows+sum(overloads-1)=shown) prov=scip(precise;else name-based) hdr:unresolved=call-name-defined-only-in-a-lang-incompatible-file (edges heuristic) hdr:locality_pinned=sum-of-lpin(absent-if-0) hdr:external=calls-refused-as-bound-outside-the-tree(builtin/stdlib-name-without-in-repo-evidence,external-import,super-past-the-tree;no-edge;absent-if-0) r:est_tokens=hdr-copy(none-if-stable) -->
<!-- r:root=crawl-root-every-p=-is-relative-to(single-root-only;absent=>p=is-the-raw-ingest-path) -->
<!-- rank_by=churn: k= is PageRank re-run with the teleport BIASED by git CHANGE-FREQUENCY over window= (a churn-weighted PageRank, not a raw frequency count), so call-graph structure still shapes k=; top ranks can coincide with rank_by=pagerank when structure and churn agree, and diverge where a heavily-churned symbol has little call-graph support -->
<!-- at= is the git commit these numbers were computed at; a trailing +dirty means the working tree differed from that commit, so the numbers describe the tree, not the commit -->
<!-- pr_iters=pagerank-power-iterations(stop:L1-residual-below-tol,else-ceiling) pr_converged=0-only-when-ceiling-hit-first(absent=converged;no-such-attr=not-pagerank-ordered) -->
<!-- files=1588 symbols=13849 edges=17058 shown=5 est_tokens=993 ambiguous=6085 unresolved=3093 locality_pinned=6 external=788 precise=3 skipped_oversize=15 unindexed="txt:59,jsonl:26,tsv:21,scm:18,expected:15,lock:7" unindexed_exts=19 order=important-first -->
<r at="c7725f3ef" root="." rank_by="churn" window="18mo" est_tokens="993" pr_iters="29">
<f p="src/infra/svector.h" layer="infra">
<s t="method" n="size" id="src/infra/svector.h::svector::size" k="0.0168">
</s>
<s t="method" n="empty" id="src/infra/svector.h::svector::empty" k="0.0089">
</s>
<s t="method" n="buf" id="src/infra/svector.h::svector::buf" k="0.0078">
</s>
</f>
<f p="src/notes.h">
<s t="method" n="empty" id="src/notes.h::NoteIndex::empty" k="0.0154">
</s>
</f>
<f p="src/scipoverlay.h">
<s t="method" n="empty" id="src/scipoverlay.h::ScipOverlay::empty" k="0.0152">
</s>
</f>
</r>
`````

## `./build/ripwire . --rank-by=bogus --top-k=5`

*An unknown value REFUSES (exit 1), NAMED, with the supported set listed.*

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
<!-- ripwire callers/callees: the 1-hop call hierarchy read off the call graph — the callers form lists symbols that CALL of=; the callees form lists symbols of= itself calls. of= is the selector you passed, defs= how many DEFINITIONS it resolved to (rows UNION every def's neighbours), count= the DISTINCT neighbour symbols (a floor, per counts_floor=), windowed by limit= and offset=. A neighbour that is an indexed function-like #define is a macro row (t="macro", role="macro" on the XML row): the edge crosses a macro expansion, not a plain call — rows carry no role= otherwise. Rows are ordered SOURCE first, then test/bench, then docs, by path within a tier. hop_tested=/hop_untested= partition count= by the tested= lens below (1-hop, never transitive). tested="1" on a row means an indexed test transitively reaches it (never 0, omitted when it does not). BLIND SPOT the test-gate legend also names: only a CALL EDGE from an INDEXED test symbol counts here, so a shell or CLI-level test running a built binary as a SUBPROCESS is invisible to it and a repo tested that way reads all-untested. Read untested= as no in-process test reaches it, not as no test covers it. next= is the one pasteable follow-up (the uses verb on this selector: the call sites). counts_floor="1" means every count here is a FLOOR, never a total: edges are extracted from source TEXT by NAME. Missing: dynamic dispatch (virtual/interface/duck-typed), a most-vexing-parse declaration with no call expression, a function-pointer/callback bound to more than one function in scope (reassigned, table-indexed, lambda-bound, or address-taken/reference-bound), and a plain-name binding (fp=handler) whose variable type is not PROVABLY a function pointer (a same-file typedef/declarator; a HEADER typedef is missed; auto/template types are read as unpinned, so KEPT). A macro-generated call site is role="macro" only when its name uniquely names an indexed function-like #define (C-family, t="macro"); a shared name stays a plain call, an unindexed macro is no edge. Read a zero as "none found", never as "none exists". graph_ambiguous=/graph_unresolved= are the whole graph's resolver gauge (calls split over several defs / calls whose in-repo defs were all language-filtered), the map header's ambiguous=/unresolved=. COUNTING UNIT differs by verb: callers, callees, edit-check, graph-query and pr-context counts are DISTINCT SYMBOLS (repeated calls from one caller, and calls to two overloads, collapse into ONE row; multiplicity survives only in the call graph's edge weight). The reach counts (impact's reaches=, pr-context's dependents=) are the size of a transitive reach SET, each symbol counted once. The uses verb counts call SITES, one row per occurrence — a larger count there for the same symbol is these units agreeing, not disagreeing. The map header's edges= is a unit again different — distinct (caller,callee) PAIRS — and that document carries neither this marker nor this clause. -->
<!-- root= on this element is the crawl root every p= below is RELATIVE to (single-root runs only; absent => p= is the path ingest itself used, unchanged). -->
<!-- format=columnar: PARALLEL ARRAYS, not per-row attributes — the t=/n=/p= attributes this verb's XML row form carries are NOT emitted in this form. Zip by index: <paths> maps `I=path`; each array under <cols> holds exactly n= comma-separated values in ONE shared row order, and the path column is an index into <paths>. fields= names the columns, in array order. n="0" (an empty page) means every array is present and empty. A ',' inside a VALUE is escaped as &#44; (ordinary XML entity decoding restores it), so splitting a row array on ',' can never mis-zip. -->
<callers of="rankGraphTeleport" defs="1" count="6" hop_tested="0" hop_untested="6" root="." graph_ambiguous="6085" graph_unresolved="3093" counts_floor="1" next="--uses=rankGraphTeleport" format="columnar">
<paths>0=src/eval.h 1=src/graph.h 2=src/main.cpp 3=src/mcpindex.h</paths>
<cols n="6" fields="path,name,line,kind,tested">
<path>0,1,1,2,2,3</path>
<name>runEval,rankGraph,anchoredLexicalRank,churnRankedGraph,runDefaultMap,getIndex</name>
<line>168,2542,3034,983,1098,1104</line>
<kind>fn,fn,fn,fn,fn,fn</kind>
<tested>0,0,0,0,0,0</tested>
</cols>
</callers>
`````

## `./build/ripwire . --for="cache invalidation" --format=candidates --top-k=5`

*Flat top-K export for an external reranker.*

`````
<!-- ripwire candidates: flat top K export for an external reranker. r=rank(1 based) s=SCORE n=name id=canonical k=KIND-tag p=path l=line. Note k= is the kind here and the PageRank score in the ranked map; on this row the score is s=. Root: count= rows exported of total= RANKED CORPUS symbols (total is the corpus size, never a match count), capped="1" means the top-k cut dropped some; route= names the ranker (s= is comparable only within one route); anchored= counts query-mention lifts (0 = the anchor ran and moved nothing); weak="1" means the top raw lexical score is below the confidence bar, so these rows rest on thin textual evidence; doc_tier= names the query SHAPE (a pasted trace, a pasted bug-report form) that scored documents down for this run, absent when none did. -->
<candidates count="5" total="13849" capped="1" route="subtoken+body" anchored="0">
<cand r="1" s="14.3229" n="spanTierMemoPath" id="src/ingest_astquery.h::rw::spanTierMemoPath" k="fn" p="src/ingest_astquery.h" l="1307">
<sig>inline std::string spanTierMemoPath( const std::string&amp; diskPath )</sig>
</cand>
<cand r="2" s="9.94085" n="legoImplementorsOnSurface" id="src/serialize.h::rw::legoImplementorsOnSurface" k="fn" p="src/serialize.h" l="5537">
<sig>inline std::vector&lt;std::vector&lt;NodeId&gt;&gt; legoImplementorsOnSurface( const IngestResult&amp; ing, const std::vector&lt;std::vector&lt;NodeId&gt;&gt;&amp; implementors, const std::vector&lt;NodeId&gt;&amp; surfaceIds )</sig>
</cand>
<cand r="3" s="7.87758" n="No API key. No embeddings. No index server. No daemon." id="README.md::Give your coding agent a map before it reads the repo.::No API key. No embeddings. No index server. No daemon." k="sec" p="README.md" l="23">
<sig>### No API key. No embeddings. No index server. No daemon.</sig>
</cand>
<cand r="4" s="7.63973" n="receiptNextFor" id="src/mcpedit.h::mcpedit::receiptNextFor" k="fn" p="src/mcpedit.h" l="1058">
<sig>inline std::string receiptNextFor( const std::string&amp; fileIdentity, const std::string&amp; symbolName, const std::string&amp; foldJson, const std::string&amp; firstTestRun )</sig>
</cand>
<cand r="5" s="6.09241" n="mcpCachePath" id="src/mcpindex.h::rw::mcpCachePath" k="fn" p="src/mcpindex.h" l="584">
<sig>inline std::string mcpCachePath( const std::string&amp; root )</sig>
</cand>
</candidates>
`````

## `./build/ripwire . --callers=rankGraphTeleport --format=bogus`

*An unknown --format value REFUSES (exit 1), named, with the supported set listed.*

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
{"of":"rankGraphTeleport","defs":1,"count":6,"root":".","hop_tested":0,"hop_untested":6,"graph_ambiguous":6085,"graph_unresolved":3093,"counts_floor":true,"callers":[{"t":"fn","n":"runEval","p":"src/eval.h:168"},
{"t":"fn","n":"rankGraph","p":"src/graph.h:2542"},
{"t":"fn","n":"anchoredLexicalRank","p":"src/graph.h:3034"},
{"t":"fn","n":"churnRankedGraph","p":"src/main.cpp:983"},
{"t":"fn","n":"runDefaultMap","p":"src/main.cpp:1098"},
{"t":"fn","n":"getIndex","p":"src/mcpindex.h:1104"}]}
`````

## `./build/ripwire . --hotspots --json`

*JSON refusal shape: an unsupported verb refuses loudly instead of silently falling back to XML.*

**exit code: 1**

`````
(empty)
`````

stderr:

`````
ripwire: --json is not yet supported for --hotspots — supported: the default map, --for, --pack-task, --callers/--callees, --impact, --quality-delta, --test-gate, --metrics, and --plan-lanes which is JSON-native (e.g. ripwire <dir> --callers=SYM --json)
`````

## `./build/ripwire . --hotspots --limit=3 --offset=3`

*Pagination: 3 items, skipping the first 3 (deterministic seams).*

`````
<!-- ripwire hotspots: maintenance-pain = complexity × recent churn (window=12mo). churn=commits touching the file; ccx=Σ cognitive complexity; score=churn×ccx; top=worst function. files= is the DENOMINATOR ranked= is drawn from, and a hotspot needs both factors nonzero, so ranked= + unranked_no_churn= + unranked_no_complexity= = files= exactly. unranked_no_complexity= is a file with commits but no function or method to score (a pure declaration header, markdown, config). unranked_no_churn= is a file no in-window commit was attributed to — and it CONFLATES two cases this verb cannot tell apart: a genuinely quiet file, and one whose path the git-to-index join never bound (a rename, an exclusion, or a spelling the join could not match), which scores zero for a reason that is not about the file. Treat it as an upper bound on quietness, not a measure of it. raise the default cap with limit=N (offset=M pages; a cut listing carries total=/has_more=/next_offset= so a paging loop can continue from it) -->
<!-- at= is the git commit these numbers were computed at; a trailing +dirty means the working tree differed from that commit, so the numbers describe the tree, not the commit -->
<!-- root= on this element is the crawl root every p= below is RELATIVE to (single-root runs only; absent => p= is the path ingest itself used, unchanged). -->
<hotspots window="12mo" files="1588" ranked="438" unranked_no_churn="0" unranked_no_complexity="1150" shown="3" capped="1" total="438" has_more="1" next_offset="6" offset="3" limit="3" root="." at="c7725f3ef">
<f p="src/mcpverbs.h" churn="117" ccx="981" score="114777" top="runBatchSub" top_ccx="112" top_l="4266"/>
<f p="src/graph.h" churn="59" ccx="1834" score="108206" top="buildGraph" top_ccx="779" top_l="962"/>
<f p="src/cli.h" churn="212" ccx="501" score="106212" top="parseArgs" top_ccx="191" top_l="4132"/>
</hotspots>
`````

## `./build/ripwire . --ignore-tests --top-k=5`

*Drop test paths from the corpus before ranking.*

`````
<!-- ripwire v1 t=fn|method|cls|struct|iface|var|sec|macro(#define;degraded:body-is-replacement-text,edges-cross-expansion) p=path layer=arch-layer(opt) n=name id=canonical(path::scope::name,when-scoped) k=rank c=call amb=ambiguous-calls(read-source) lpin=calls-pinned-by-locality-prior-alone(a-disclosed-guess;read-source;absent-if-0) overloads=N-same-name-defs-merged-into-this-row(absent-if-1;shown=counts-them-individually,so-rows+sum(overloads-1)=shown) hdr:unresolved=call-name-defined-only-in-a-lang-incompatible-file (edges heuristic) hdr:locality_pinned=sum-of-lpin(absent-if-0) hdr:external=calls-refused-as-bound-outside-the-tree(builtin/stdlib-name-without-in-repo-evidence,external-import,super-past-the-tree;no-edge;absent-if-0) r:est_tokens=hdr-copy(none-if-stable) -->
<!-- r:root=crawl-root-every-p=-is-relative-to(single-root-only;absent=>p=is-the-raw-ingest-path) -->
<!-- pr_iters=pagerank-power-iterations(stop:L1-residual-below-tol,else-ceiling) pr_converged=0-only-when-ceiling-hit-first(absent=converged;no-such-attr=not-pagerank-ordered) -->
<!-- files=1588 symbols=8615 edges=15571 shown=5 est_tokens=710 ambiguous=6004 unresolved=2327 external=569 skipped_oversize=15 unindexed="txt:59,jsonl:26,tsv:21,scm:18,expected:15,lock:7" unindexed_exts=19 order=important-first -->
<r root="." est_tokens="710" pr_iters="21">
<f p="src/infra/svector.h" layer="infra">
<s t="method" n="size" id="src/infra/svector.h::svector::size" k="0.0219">
</s>
<s t="method" n="buf" id="src/infra/svector.h::svector::buf" overloads="2" k="0.0093">
</s>
</f>
<f p="src/notes.h">
<s t="method" n="empty" id="src/notes.h::NoteIndex::empty" k="0.0130">
</s>
</f>
<f p="src/scipoverlay.h">
<s t="method" n="empty" id="src/scipoverlay.h::ScipOverlay::empty" k="0.0127">
</s>
</f>
</r>
`````

## `./build/ripwire . --exclude=present --exclude=bench --top-k=5`

*Drop matching paths (repeatable) before ranking.*

`````
<!-- ripwire v1 t=fn|method|cls|struct|iface|var|sec|macro(#define;degraded:body-is-replacement-text,edges-cross-expansion) p=path layer=arch-layer(opt) n=name id=canonical(path::scope::name,when-scoped) k=rank c=call amb=ambiguous-calls(read-source) lpin=calls-pinned-by-locality-prior-alone(a-disclosed-guess;read-source;absent-if-0) overloads=N-same-name-defs-merged-into-this-row(absent-if-1;shown=counts-them-individually,so-rows+sum(overloads-1)=shown) prov=scip(precise;else name-based) hdr:unresolved=call-name-defined-only-in-a-lang-incompatible-file (edges heuristic) hdr:locality_pinned=sum-of-lpin(absent-if-0) hdr:external=calls-refused-as-bound-outside-the-tree(builtin/stdlib-name-without-in-repo-evidence,external-import,super-past-the-tree;no-edge;absent-if-0) r:est_tokens=hdr-copy(none-if-stable) -->
<!-- r:root=crawl-root-every-p=-is-relative-to(single-root-only;absent=>p=is-the-raw-ingest-path) -->
<!-- pr_iters=pagerank-power-iterations(stop:L1-residual-below-tol,else-ceiling) pr_converged=0-only-when-ceiling-hit-first(absent=converged;no-such-attr=not-pagerank-ordered) -->
<!-- files=1386 symbols=11272 edges=15855 shown=5 est_tokens=725 ambiguous=6045 unresolved=2094 locality_pinned=6 external=104 precise=3 unindexed="txt:48,scm:18,xml:6,tsv:5,cmake:3,jsonl:3" unindexed_exts=14 order=important-first -->
<r root="." est_tokens="725" pr_iters="32">
<f p="src/infra/svector.h" layer="infra">
<s t="method" n="size" id="src/infra/svector.h::svector::size" k="0.0197">
</s>
<s t="method" n="buf" id="src/infra/svector.h::svector::buf" overloads="2" k="0.0083">
</s>
</f>
<f p="src/notes.h">
<s t="method" n="empty" id="src/notes.h::NoteIndex::empty" k="0.0116">
</s>
</f>
<f p="src/scipoverlay.h">
<s t="method" n="empty" id="src/scipoverlay.h::ScipOverlay::empty" k="0.0113">
</s>
</f>
</r>
`````

## `./build/ripwire . --map-diff --top-k=5`

*Full map re-ranked with teleport toward git-changed files — clean tree, so changed=0 and it degrades to the plain map.*

`````
<!-- ripwire v1 t=fn|method|cls|struct|iface|var|sec|macro(#define;degraded:body-is-replacement-text,edges-cross-expansion) p=path layer=arch-layer(opt) n=name id=canonical(path::scope::name,when-scoped) k=rank c=call amb=ambiguous-calls(read-source) lpin=calls-pinned-by-locality-prior-alone(a-disclosed-guess;read-source;absent-if-0) overloads=N-same-name-defs-merged-into-this-row(absent-if-1;shown=counts-them-individually,so-rows+sum(overloads-1)=shown) prov=scip(precise;else name-based) hdr:unresolved=call-name-defined-only-in-a-lang-incompatible-file (edges heuristic) hdr:locality_pinned=sum-of-lpin(absent-if-0) hdr:external=calls-refused-as-bound-outside-the-tree(builtin/stdlib-name-without-in-repo-evidence,external-import,super-past-the-tree;no-edge;absent-if-0) r:est_tokens=hdr-copy(none-if-stable) -->
<!-- r:root=crawl-root-every-p=-is-relative-to(single-root-only;absent=>p=is-the-raw-ingest-path) -->
<!-- at= is the git commit these numbers were computed at; a trailing +dirty means the working tree differed from that commit, so the numbers describe the tree, not the commit -->
<!-- pr_iters=pagerank-power-iterations(stop:L1-residual-below-tol,else-ceiling) pr_converged=0-only-when-ceiling-hit-first(absent=converged;no-such-attr=not-pagerank-ordered) -->
<!-- files=1588 symbols=13849 edges=17058 shown=5 est_tokens=818 ambiguous=6085 unresolved=3093 locality_pinned=6 external=788 precise=3 changed=0 skipped_oversize=15 unindexed="txt:59,jsonl:26,tsv:21,scm:18,expected:15,lock:7" unindexed_exts=19 order=important-first -->
<r at="c7725f3ef" root="." est_tokens="818" pr_iters="31">
<f p="src/infra/svector.h" layer="infra">
<s t="method" n="size" id="src/infra/svector.h::svector::size" k="0.0169">
</s>
<s t="method" n="buf" id="src/infra/svector.h::svector::buf" overloads="2" k="0.0071">
</s>
</f>
<f p="src/notes.h">
<s t="method" n="empty" id="src/notes.h::NoteIndex::empty" k="0.0099">
</s>
</f>
<f p="src/scipoverlay.h">
<s t="method" n="empty" id="src/scipoverlay.h::ScipOverlay::empty" k="0.0097">
</s>
</f>
</r>
`````

## `./build/ripwire . --no-cache --top-k=3`

*Force a cold parse (bypass the warm TMPDIR cache) — shows the cold-vs-warm cost.*

`````
<!-- ripwire v1 t=fn|method|cls|struct|iface|var|sec|macro(#define;degraded:body-is-replacement-text,edges-cross-expansion) p=path layer=arch-layer(opt) n=name id=canonical(path::scope::name,when-scoped) k=rank c=call amb=ambiguous-calls(read-source) lpin=calls-pinned-by-locality-prior-alone(a-disclosed-guess;read-source;absent-if-0) overloads=N-same-name-defs-merged-into-this-row(absent-if-1;shown=counts-them-individually,so-rows+sum(overloads-1)=shown) prov=scip(precise;else name-based) hdr:unresolved=call-name-defined-only-in-a-lang-incompatible-file (edges heuristic) hdr:locality_pinned=sum-of-lpin(absent-if-0) hdr:external=calls-refused-as-bound-outside-the-tree(builtin/stdlib-name-without-in-repo-evidence,external-import,super-past-the-tree;no-edge;absent-if-0) r:est_tokens=hdr-copy(none-if-stable) -->
<!-- r:root=crawl-root-every-p=-is-relative-to(single-root-only;absent=>p=is-the-raw-ingest-path) -->
<!-- pr_iters=pagerank-power-iterations(stop:L1-residual-below-tol,else-ceiling) pr_converged=0-only-when-ceiling-hit-first(absent=converged;no-such-attr=not-pagerank-ordered) -->
<!-- files=1588 symbols=13849 edges=17058 shown=3 est_tokens=698 ambiguous=6085 unresolved=3093 locality_pinned=6 external=788 precise=3 skipped_oversize=15 unindexed="txt:59,jsonl:26,tsv:21,scm:18,expected:15,lock:7" unindexed_exts=19 order=important-first -->
<r root="." est_tokens="698" pr_iters="31">
<f p="src/infra/svector.h" layer="infra">
<s t="method" n="size" id="src/infra/svector.h::svector::size" k="0.0169">
</s>
</f>
<f p="src/notes.h">
<s t="method" n="empty" id="src/notes.h::NoteIndex::empty" k="0.0099">
</s>
</f>
<f p="src/scipoverlay.h">
<s t="method" n="empty" id="src/scipoverlay.h::ScipOverlay::empty" k="0.0097">
</s>
</f>
</r>
`````

## `./build/ripwire . --cache=<scratch>/aux/warm2.ripwirecache --top-k=3`

*Explicit incremental cache at a path OUTSIDE the repo (first call writes it).*

`````
<!-- ripwire v1 t=fn|method|cls|struct|iface|var|sec|macro(#define;degraded:body-is-replacement-text,edges-cross-expansion) p=path layer=arch-layer(opt) n=name id=canonical(path::scope::name,when-scoped) k=rank c=call amb=ambiguous-calls(read-source) lpin=calls-pinned-by-locality-prior-alone(a-disclosed-guess;read-source;absent-if-0) overloads=N-same-name-defs-merged-into-this-row(absent-if-1;shown=counts-them-individually,so-rows+sum(overloads-1)=shown) prov=scip(precise;else name-based) hdr:unresolved=call-name-defined-only-in-a-lang-incompatible-file (edges heuristic) hdr:locality_pinned=sum-of-lpin(absent-if-0) hdr:external=calls-refused-as-bound-outside-the-tree(builtin/stdlib-name-without-in-repo-evidence,external-import,super-past-the-tree;no-edge;absent-if-0) r:est_tokens=hdr-copy(none-if-stable) -->
<!-- r:root=crawl-root-every-p=-is-relative-to(single-root-only;absent=>p=is-the-raw-ingest-path) -->
<!-- pr_iters=pagerank-power-iterations(stop:L1-residual-below-tol,else-ceiling) pr_converged=0-only-when-ceiling-hit-first(absent=converged;no-such-attr=not-pagerank-ordered) -->
<!-- files=1588 symbols=13849 edges=17058 shown=3 est_tokens=698 ambiguous=6085 unresolved=3093 locality_pinned=6 external=788 precise=3 skipped_oversize=15 unindexed="txt:59,jsonl:26,tsv:21,scm:18,expected:15,lock:7" unindexed_exts=19 order=important-first -->
<r root="." est_tokens="698" pr_iters="31">
<f p="src/infra/svector.h" layer="infra">
<s t="method" n="size" id="src/infra/svector.h::svector::size" k="0.0169">
</s>
</f>
<f p="src/notes.h">
<s t="method" n="empty" id="src/notes.h::NoteIndex::empty" k="0.0099">
</s>
</f>
<f p="src/scipoverlay.h">
<s t="method" n="empty" id="src/scipoverlay.h::ScipOverlay::empty" k="0.0097">
</s>
</f>
</r>
`````

Artifact written:

`````
 9517522 <scratch>/aux/warm2.ripwirecache
`````

## `./build/ripwire . --max-file-size=8K --top-k=3`

*Skip files above a size bound before parsing (note the corpus shrink in the header).*

`````
<!-- ripwire v1 t=fn|method|cls|struct|iface|var|sec|macro(#define;degraded:body-is-replacement-text,edges-cross-expansion) p=path layer=arch-layer(opt) n=name id=canonical(path::scope::name,when-scoped) k=rank c=call amb=ambiguous-calls(read-source) lpin=calls-pinned-by-locality-prior-alone(a-disclosed-guess;read-source;absent-if-0) overloads=N-same-name-defs-merged-into-this-row(absent-if-1;shown=counts-them-individually,so-rows+sum(overloads-1)=shown) prov=scip(precise;else name-based) hdr:unresolved=call-name-defined-only-in-a-lang-incompatible-file (edges heuristic) hdr:locality_pinned=sum-of-lpin(absent-if-0) hdr:external=calls-refused-as-bound-outside-the-tree(builtin/stdlib-name-without-in-repo-evidence,external-import,super-past-the-tree;no-edge;absent-if-0) r:est_tokens=hdr-copy(none-if-stable) -->
<!-- r:root=crawl-root-every-p=-is-relative-to(single-root-only;absent=>p=is-the-raw-ingest-path) -->
<!-- pr_iters=pagerank-power-iterations(stop:L1-residual-below-tol,else-ceiling) pr_converged=0-only-when-ceiling-hit-first(absent=converged;no-such-attr=not-pagerank-ordered) -->
<!-- files=905 symbols=3829 edges=990 shown=3 est_tokens=694 ambiguous=40 unresolved=95 locality_pinned=6 external=125 precise=3 skipped_oversize=698 unindexed="txt:59,jsonl:26,tsv:21,scm:18,expected:15,lock:7" unindexed_exts=19 order=important-first -->
<r root="." est_tokens="694" pr_iters="41">
<f p="test/extvetofix/ext.py" layer="test">
<s t="fn" n="get" id="test/extvetofix/ext.py::Rep::get" k="0.0035">
</s>
</f>
<f p="src/scipoverlay.h">
<s t="method" n="empty" id="src/scipoverlay.h::ScipOverlay::empty" k="0.0029">
</s>
</f>
<f p="test/scipfix/make_index.py" layer="test">
<s t="fn" n="varint" k="0.0027">
</s>
</f>
</r>
`````

## `./build/ripwire . --scip=does_not_exist.scip --callers=rankGraphTeleport`

*SCIP overlay with a missing index REFUSES (exit 1) naming the file — never silently serves the name-based map you named a precision index to improve on (it used to degrade in silence).*

**exit code: 1**

`````
(empty)
`````

stderr:

`````
ripwire: --scip=does_not_exist.scip: cannot open the index — refusing rather than serving the name-based map you named a precision index to improve on (generate one with scip-clang/scip-python, or drop --scip)
`````

## `./build/ripwire src test --top-k=5`

*Multi-root workspace: ONE merged graph over two roots, paths labeled <root>/<rel>.*

`````
<!-- ripwire v1 t=fn|method|cls|struct|iface|var|sec|macro(#define;degraded:body-is-replacement-text,edges-cross-expansion) p=path layer=arch-layer(opt) n=name id=canonical(path::scope::name,when-scoped) k=rank c=call amb=ambiguous-calls(read-source) lpin=calls-pinned-by-locality-prior-alone(a-disclosed-guess;read-source;absent-if-0) overloads=N-same-name-defs-merged-into-this-row(absent-if-1;shown=counts-them-individually,so-rows+sum(overloads-1)=shown) prov=scip(precise;else name-based) hdr:unresolved=call-name-defined-only-in-a-lang-incompatible-file (edges heuristic) hdr:locality_pinned=sum-of-lpin(absent-if-0) hdr:external=calls-refused-as-bound-outside-the-tree(builtin/stdlib-name-without-in-repo-evidence,external-import,super-past-the-tree;no-edge;absent-if-0) r:est_tokens=hdr-copy(none-if-stable) -->
<!-- pr_iters=pagerank-power-iterations(stop:L1-residual-below-tol,else-ceiling) pr_converged=0-only-when-ceiling-hit-first(absent=converged;no-such-attr=not-pagerank-ordered) -->
<!-- files=1311 symbols=10272 edges=15614 shown=5 est_tokens=704 ambiguous=6037 unresolved=1724 locality_pinned=6 external=84 precise=3 roots=2 unindexed="txt:46,xml:6,tsv:5,jsonl:3,arch:2,scip:2" unindexed_exts=12 order=important-first -->
<r est_tokens="704" pr_iters="32">
<root label="src" p="src"/>
<root label="test" p="test"/>
<f p="src/infra/svector.h" layer="infra">
<s t="method" n="size" id="src/infra/svector.h::svector::size" k="0.0214">
</s>
<s t="method" n="buf" id="src/infra/svector.h::svector::buf" overloads="2" k="0.0090">
</s>
</f>
<f p="src/notes.h">
<s t="method" n="empty" id="src/notes.h::NoteIndex::empty" k="0.0126">
</s>
</f>
<f p="src/scipoverlay.h">
<s t="method" n="empty" id="src/scipoverlay.h::ScipOverlay::empty" k="0.0123">
</s>
</f>
</r>
`````

## `./build/ripwire . --eval`

*Self-eval: co-change recall vs BM25.*

**wall time: 3.85s**

`````
ripwire --eval  (co-change recovery, averaged over 80 historical commits)
  ranker     recall@5  recall@10  recall@20
  ripwire        0.4%       1.1%       2.0%
  BM25          14.1%      15.8%      21.9%
  BM25sub       11.9%      14.9%      20.9%
  BM25body      10.4%      18.5%      22.8%
  fused          1.8%       6.6%      14.4%
  anchored      10.0%      18.5%      22.8%
  same-dir       1.2%       3.6%       6.5%
  random         0.3%       0.6%       1.3%   <- floor (random ranking over F=1588 files)
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

**wall time: 6.36s**

`````
ripwire --eval-retrieval  (known-item, 150 doc-commented symbols; gold is in-corpus by construction)
  ranker    query-mode     MRR  recall@1  recall@5 recall@10
  subtoken  name         0.598     49.3%     74.0%     82.7%
  subtoken  doc-phrase   0.744     70.0%     78.7%     80.7%
  name-exact name         0.829     75.3%     94.7%     97.3%
  name-exact doc-phrase   0.020      1.3%      2.7%      3.3%
  anchored  name         0.589     47.3%     72.0%     79.3%
  anchored  doc-phrase   0.741     70.0%     78.0%     80.0%
  routed    name         0.830     75.3%     94.7%     98.7%
  routed    doc-phrase   0.741     70.0%     78.0%     80.0%
  note: routing chose name-exact on 148/150 NAME queries (a NAME query is always identifier-shaped);
        the confidence gate routes doc-phrase queries to name-exact ONLY when EVERY content word names a symbol
        (or an explicit camel/snake token appears) AND every matched name is specific enough to anchor on —
        a common name (many definitions, or a subtoken carried by many symbol names) declines the route — so
        conceptual prose falls back to subtoken+body; routed tracks the better ranker on BOTH modes
        (routed==name-exact on name, ~=subtoken+body on doc-phrase).
`````

## `./build/ripwire . --eval-stray=<scratch>/aux/stray_labels2.tsv`

*Labelled verdict-accuracy eval for --stray-content — three labels over REAL local refs (names resolved at capture time); exit 3 when accuracy is under the floor. Read got= against v= in the stray-content run: a ref the verb could not analyse (unknown) must never be credited as a merged hit.*

**exit code: 3**

Input file:

`````
# ref<TAB>verdict labels for --eval-stray (the first three local branches, resolved at capture time; a missing branch is padded with a nonexistent name on purpose)
claude/awesome-swartz-67ebab	merged
claude/determined-panini-f56633	unmerged
claude/exciting-greider-8564fe	merged
`````

`````
<!-- ripwire stray-content eval: labelled verdict accuracy. Each row is one branch whose true state was established by hand; want= is the label, got= is what the classifier said. A branch absent from the report scores as merged ONLY when it is a real ref this repo has (merged refs are omitted by design); a label naming a ref that does not exist is refused, not scored (see badRefs on refusal). unknown= on the root counts cases whose verdict is unknown (no merge-base / unrelated history); its own bucket, never folded into merged. Use this to MEASURE a threshold change instead of eyeballing it. -->
<stray-eval cases="3" correct="0" unknown="3" accuracy="0.0">
<case ref="claude/awesome-swartz-67ebab" want="merged" got="unknown" hit="0" reported="1"/>
<case ref="claude/determined-panini-f56633" want="unmerged" got="unknown" hit="0" reported="1"/>
<case ref="claude/exciting-greider-8564fe" want="merged" got="unknown" hit="0" reported="1"/>
</stray-eval>
`````

stderr:

`````
[math degraded] crossref: no merge-base for ref (shallow clone or unrelated history?) — verdict is unknown, not merged  (crossref.h:1053, RefPlumbing rw::crossref::probeRefBase(const std::string &, const RefInfo &, const std::string &) — logged once per site)
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
ripwire --eval-skills  (skill routing over K=17 candidate skills [ripwire-router excluded]; 3 positive + 1 negative prompts; corpus '<tmp> … [line truncated: 48 more bytes on this line]
  arm           hit@1   hit@2     mrr   sep-auc   fire/abstain@ORACLE-th (upper bound)
  overlap       66.7%  100.0%   0.833     0.667    50.0% (th=-1.000)
  name          33.3%   66.7%   0.533     0.667    50.0% (th=0.000)
  bm25-desc    100.0%  100.0%   1.000     1.000   100.0% (th=1.817)
  bm25-full     66.7%  100.0%   0.833     1.000    75.0% (th=0.267)
  for-routed    33.3%   66.7%   0.611     1.000    50.0% (th=0.546)
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
… [19 more lines, 3610 bytes total]
`````

## `./build/ripwire wrap claude`

*Print the recipe to wire ripwire into Claude Code as an MCP server.*

`````
# ripwire -> Claude Code (MCP — deterministic, no LLM, no embeddings)
claude mcp add ripwire -- ripwire --mcp
# verbs the agent can then call mid-task (31 total):
#   read:             analyze, find_symbol, find_referencing_symbols, grep, cochange, memory_recall, situational_awareness, mentions, for, lego, owners, fetch_body, batch, flags, doc_drift, slice
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
- One task: `--pack-task="<task>"`; before parallel agents: `--plan-lanes=N --task="<goal>"`, then read `lanes[].execution`.
- Have a stack trace / build error: `ripwire <dir> --from-trace=FILE` (`-` = stdin) —
  paste the error, don't paraphrase it into a query.
- Who calls X: `--callers=SYM`. "Is it safe to change X?" needs the full blast radius:
  `--impact=SYM` (transitive) plus `--uses=SYM` (every read/write/import site).
- Apply a whole-symbol edit without a whole-file Read: `--replace-symbol-body=SYM` plus `--edit-payload=FILE|-`
  (or insert-before/after); the receipt carries region, blob_sha, edit_check, tests_to_run + ONE next= — no re-read after it; `--edit-check=SYM` is for a contract question WITHOUT an edit in hand.
- Before writing a new fn/class/helper: `--exemplar="<what you're writing>"` — duplicates are born on small tasks.
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
ripwire 0.3.8 (dev, AppleClang 21.0.0.21000101, built_from=c7725f3ef)
`````


---

# navigate — seeds, claims, slices, shapes

## `./build/ripwire . --at=src/graph.h:1148`

*Hold a LOCATION, not a name: the enclosing-definition chain at FILE:LINE (a compiler error, a diff hunk, a stack frame), outermost -> innermost.*

`````
<!-- ripwire at: the ENCLOSING-DEFINITION CHAIN at one FILE:LINE seed. p= the resolved file, l= the 1-based seed line, sym= the innermost enclosing definition's name (what the same seed resolves to in a selector position), chain= the row count. Rows are INDEXED definitions only, outermost first, innermost last: n= the definition's name, t= its kind tag, l= its own start line, el= its end line (1-based, inclusive). A namespace or any construct the index does not carry is NOT a row, so an outer scope can be absent rather than misnamed; a seed line inside no indexed definition is refused, never served as an empty chain. The same seed composes into any SYM selector as @FILE:LINE (callers, callees, impact, around, expand, uses, edit-check, slice, safe-delete, path, connect) and resolves to the innermost row. -->
<!-- root= on this element is the crawl root every p= below is RELATIVE to (single-root runs only; absent => p= is the path ingest itself used, unchanged). -->
<at p="src/graph.h" l="1148" sym="buildGraph" chain="1" root=".">
<s n="buildGraph" t="fn" l="962" el="2455"/>
</at>
`````

## `./build/ripwire . --callers=@src/graph.h:1148`

*The same seed in a SELECTOR position: @FILE:LINE resolves to the innermost enclosing definition, then --callers runs on it.*

`````
<!-- ripwire callers/callees: the 1-hop call hierarchy read off the call graph — the callers form lists symbols that CALL of=; the callees form lists symbols of= itself calls. of= is the selector you passed, defs= how many DEFINITIONS it resolved to (rows UNION every def's neighbours), count= the DISTINCT neighbour symbols (a floor, per counts_floor=), windowed by limit= and offset=. A neighbour that is an indexed function-like #define is a macro row (t="macro", role="macro" on the XML row): the edge crosses a macro expansion, not a plain call — rows carry no role= otherwise. Rows are ordered SOURCE first, then test/bench, then docs, by path within a tier. hop_tested=/hop_untested= partition count= by the tested= lens below (1-hop, never transitive). tested="1" on a row means an indexed test transitively reaches it (never 0, omitted when it does not). BLIND SPOT the test-gate legend also names: only a CALL EDGE from an INDEXED test symbol counts here, so a shell or CLI-level test running a built binary as a SUBPROCESS is invisible to it and a repo tested that way reads all-untested. Read untested= as no in-process test reaches it, not as no test covers it. next= is the one pasteable follow-up (the uses verb on this selector: the call sites). counts_floor="1" means every count here is a FLOOR, never a total: edges are extracted from source TEXT by NAME. Missing: dynamic dispatch (virtual/interface/duck-typed), a most-vexing-parse declaration with no call expression, a function-pointer/callback bound to more than one function in scope (reassigned, table-indexed, lambda-bound, or address-taken/reference-bound), and a plain-name binding (fp=handler) whose variable type is not PROVABLY a function pointer (a same-file typedef/declarator; a HEADER typedef is missed; auto/template types are read as unpinned, so KEPT). A macro-generated call site is role="macro" only when its name uniquely names an indexed function-like #define (C-family, t="macro"); a shared name stays a plain call, an unindexed macro is no edge. Read a zero as "none found", never as "none exists". graph_ambiguous=/graph_unresolved= are the whole graph's resolver gauge (calls split over several defs / calls whose in-repo defs were all language-filtered), the map header's ambiguous=/unresolved=. COUNTING UNIT differs by verb: callers, callees, edit-check, graph-query and pr-context counts are DISTINCT SYMBOLS (repeated calls from one caller, and calls to two overloads, collapse into ONE row; multiplicity survives only in the call graph's edge weight). The reach counts (impact's reaches=, pr-context's dependents=) are the size of a transitive reach SET, each symbol counted once. The uses verb counts call SITES, one row per occurrence — a larger count there for the same symbol is these units agreeing, not disagreeing. The map header's edges= is a unit again different — distinct (caller,callee) PAIRS — and that document carries neither this marker nor this clause. -->
<!-- root= on this element is the crawl root every p= below is RELATIVE to (single-root runs only; absent => p= is the path ingest itself used, unchanged). -->
<callers of="@src/graph.h:1148" defs="1" count="9" root="." hop_tested="0" hop_untested="9" graph_ambiguous="6085" graph_unresolved="3093" counts_floor="1" next="--uses=@src/graph.h:1148">
<s t="fn" n="run" p="src/editpreview.h:316"/>
<s t="fn" n="dispatchMain" p="src/main.cpp:2653"/>
<s t="fn" n="getIndex" p="src/mcpindex.h:1104"/>
<s t="fn" n="computeQualityDelta" p="src/mcpverbs.h:3019"/>
<s t="fn" n="qualityBaselineJson" p="src/mcpverbs.h:3209"/>
<s t="fn" n="editCheckText" p="src/mcpverbs.h:3399"/>
<s t="fn" n="computeHeadSnapshot" p="src/quality.h:2446"/>
<s t="fn" n="loadRefTree" p="src/quality.h:2584"/>
<s t="fn" n="production buildGraph stores caller to callee as target-row source-column" p="test/verify_csr.cpp:147"/>
</callers>
`````

## `./build/ripwire . --at=src/graph.h:999999`

*A seed past the end of the file — the refusal shape for a faulted location.*

**exit code: 1**

`````
(empty)
`````

stderr:

`````
ripwire: the at flag's seed 'src/graph.h:999999' named no location (./src/graph.h has only 5183 lines — the seed asked for line 999999)
`````

## `./build/ripwire . --verify="calls(runDefaultMap, rankGraphTeleport)"`

*VERIFY a closed claim in one call: three-valued verdict (confirmed / refuted / not-established) with the evidence rows inline.*

`````
<!-- ripwire verify: ONE structured claim in, a three-valued verdict out, evidence inline. verdict= is confirmed (a witness exists and is printed: a call path, use-sites, hits, a definition row), refuted (only with COMPLETE evidence: a literal-scan absence carries complete=, an absence-claim is refuted by printed witness sites), or not-established (the absence is real WITHIN THE MODEL but the model is a floor; limit= names the limiting factor and it NEVER means false). The limits: call-graph-floor (call edges are name-based — dynamic dispatch, unbound fn-pointers and unindexed macros contribute no edge), reference-floor (references are identifier-based — a string-keyed or reflective use is invisible), collection-ceiling (the scan's collection budget was reached, so counts are floors), scan-degraded (a file could not be read), extraction-floor (the name occurs in the file but no definition was extracted — a construct the parser may not model). complete= on the root (value 1) means the printed evidence is EXHAUSTIVE over the index for a literal scan and the verdict may be trusted as a complete-within-the-index answer: files the ingest skipped were never scanned (the skipped verb lists them). counts_floor= on the root marks every count as a FLOOR, never a total — the two claims are mutually exclusive by construction; graph_ambiguous=/graph_unresolved= beside it are the whole graph's resolver gauge (calls split over several defs / calls whose in-repo defs were all language-filtered), the map header's ambiguous=/unresolved=. calls/reaches can never refute; unused can never confirm. defines() does not require the symbol to exist anywhere (the claim is about the FILE), so a refuted defines means the name token never occurs in that file's indexed bytes. reaches' direction: some symbol defined in the named file or layer transitively CALLS the target. Evidence rows are a bounded sample when capped (disclosed on the root); every total lives in the attributes. A uses()/unused() <u> row's in_id= is the canonical id (root-relative path::scope::name) of the enclosing symbol, degrading to a bare name when unscoped and absent at file scope. -->
<!-- root= on this element is the crawl root every p= below is RELATIVE to (single-root runs only; absent => p= is the path ingest itself used, unchanged). -->
<verify claim="calls(runDefaultMap, rankGraphTeleport)" shape="calls" verdict="confirmed" from_defs="1" to_defs="1" hops="1" root="." graph_ambiguous="6085" graph_unresolved="3093" counts_floor="1" shown="2" capped="0">
<s t="fn" n="runDefaultMap" p="src/main.cpp:1098"/>
<s t="fn" n="rankGraphTeleport" p="src/graph.h:2501"/>
</verify>
`````

## `./build/ripwire . --verify="unused(rankGraphTeleport)"`

*A claim that is FALSE — the refuted shape, with the references that refute it.*

`````
<!-- ripwire verify: ONE structured claim in, a three-valued verdict out, evidence inline. verdict= is confirmed (a witness exists and is printed: a call path, use-sites, hits, a definition row), refuted (only with COMPLETE evidence: a literal-scan absence carries complete=, an absence-claim is refuted by printed witness sites), or not-established (the absence is real WITHIN THE MODEL but the model is a floor; limit= names the limiting factor and it NEVER means false). The limits: call-graph-floor (call edges are name-based — dynamic dispatch, unbound fn-pointers and unindexed macros contribute no edge), reference-floor (references are identifier-based — a string-keyed or reflective use is invisible), collection-ceiling (the scan's collection budget was reached, so counts are floors), scan-degraded (a file could not be read), extraction-floor (the name occurs in the file but no definition was extracted — a construct the parser may not model). complete= on the root (value 1) means the printed evidence is EXHAUSTIVE over the index for a literal scan and the verdict may be trusted as a complete-within-the-index answer: files the ingest skipped were never scanned (the skipped verb lists them). counts_floor= on the root marks every count as a FLOOR, never a total — the two claims are mutually exclusive by construction; graph_ambiguous=/graph_unresolved= beside it are the whole graph's resolver gauge (calls split over several defs / calls whose in-repo defs were all language-filtered), the map header's ambiguous=/unresolved=. calls/reaches can never refute; unused can never confirm. defines() does not require the symbol to exist anywhere (the claim is about the FILE), so a refuted defines means the name token never occurs in that file's indexed bytes. reaches' direction: some symbol defined in the named file or layer transitively CALLS the target. Evidence rows are a bounded sample when capped (disclosed on the root); every total lives in the attributes. A uses()/unused() <u> row's in_id= is the canonical id (root-relative path::scope::name) of the enclosing symbol, degrading to a bare name when unscoped and absent at file scope. -->
<!-- root= on this element is the crawl root every p= below is RELATIVE to (single-root runs only; absent => p= is the path ingest itself used, unchanged). -->
<verify claim="unused(rankGraphTeleport)" shape="unused" verdict="refuted" defs="1" external="0" count="9" root="." graph_ambiguous="6085" graph_unresolved="3093" counts_floor="1" shown="9" capped="0">
<u role="call" p="src/eval.h:322" in_id="src/eval.h::rw::runEval"/>
<u role="call" p="src/graph.h:2545" in_id="src/graph.h::rw::rankGraph"/>
<u role="call" p="src/graph.h:3078" in_id="src/graph.h::rw::anchoredLexicalRank"/>
<u role="call" p="src/main.cpp:1007" in_id="churnRankedGraph"/>
<u role="call" p="src/main.cpp:1008" in_id="churnRankedGraph"/>
<u role="call" p="src/main.cpp:1018" in_id="churnRankedGraph"/>
<u role="call" p="src/main.cpp:1024" in_id="churnRankedGraph"/>
<u role="call" p="src/main.cpp:1195" in_id="runDefaultMap"/>
<u role="call" p="src/mcpindex.h:1200" in_id="src/mcpindex.h::rw::getIndex"/>
</verify>
`````

## `./build/ripwire . --verify="contains(src/graph.h, \"no such literal anywhere\")"`

*A literal-scan absence: refuted only with complete= evidence, never on a partial scan.*

`````
<!-- ripwire verify: ONE structured claim in, a three-valued verdict out, evidence inline. verdict= is confirmed (a witness exists and is printed: a call path, use-sites, hits, a definition row), refuted (only with COMPLETE evidence: a literal-scan absence carries complete=, an absence-claim is refuted by printed witness sites), or not-established (the absence is real WITHIN THE MODEL but the model is a floor; limit= names the limiting factor and it NEVER means false). The limits: call-graph-floor (call edges are name-based — dynamic dispatch, unbound fn-pointers and unindexed macros contribute no edge), reference-floor (references are identifier-based — a string-keyed or reflective use is invisible), collection-ceiling (the scan's collection budget was reached, so counts are floors), scan-degraded (a file could not be read), extraction-floor (the name occurs in the file but no definition was extracted — a construct the parser may not model). complete= on the root (value 1) means the printed evidence is EXHAUSTIVE over the index for a literal scan and the verdict may be trusted as a complete-within-the-index answer: files the ingest skipped were never scanned (the skipped verb lists them). counts_floor= on the root marks every count as a FLOOR, never a total — the two claims are mutually exclusive by construction; graph_ambiguous=/graph_unresolved= beside it are the whole graph's resolver gauge (calls split over several defs / calls whose in-repo defs were all language-filtered), the map header's ambiguous=/unresolved=. calls/reaches can never refute; unused can never confirm. defines() does not require the symbol to exist anywhere (the claim is about the FILE), so a refuted defines means the name token never occurs in that file's indexed bytes. reaches' direction: some symbol defined in the named file or layer transitively CALLS the target. Evidence rows are a bounded sample when capped (disclosed on the root); every total lives in the attributes. A uses()/unused() <u> row's in_id= is the canonical id (root-relative path::scope::name) of the enclosing symbol, degrading to a bare name when unscoped and absent at file scope. -->
<!-- root= on this element is the crawl root every p= below is RELATIVE to (single-root runs only; absent => p= is the path ingest itself used, unchanged). -->
<verify claim="contains(src/graph.h, &quot;no such literal anywhere&quot;)" shape="contains" verdict="refuted" hits="0" root="." complete="1" shown="0" capped="0">
</verify>
`````

## `./build/ripwire . --verify="frobnicate(x)"`

*An unparseable claim — the refusal names the accepted shapes.*

**exit code: 1**

`````
(empty)
`````

stderr:

`````
ripwire: --verify claim not recognized: 'frobnicate(x)' — unknown shape word. The claim language is CLOSED; the shapes are: calls(A, B) does A transitively call B · uses(SYM) is SYM referenced anywhere · unused(SYM) is SYM referenced nowhere · contains(FILE, "LITERAL") do FILE's bytes contain t … [line truncated: 218 more bytes on this line]
`````

## `./build/ripwire . --slice=rankGraphTeleport`

*Bare --slice=SYM: the INVENTORY of sliceable locals (<v n= l= t=/>), so a caller can pick VAR.*

`````
<!-- ripwire slice: NAME-BASED intra-procedural def-use slice of one variable inside ONE resolved definition (ARISE, arXiv:2605.03117). ROWS: one <s> per LINE touching VAR, source order — k= def|use|both|scope (both = the line writes AND reads it, `x += y`; scope = a Python global/nonlocal statement: neither read nor write, it introduces the name and never anchors a flow), t= the strongest role on the line (param > decl > assign > call-arg > read > global/nonlocal), CDATA = the trimmed line. Bare slice=SYM lists the sliceable locals: <v n= l= t=/> per BINDING at its declaration line, vars= their count. COUNTS: counts="as-classified" — not the graph verbs' counts_floor= — defs=, uses=, vars= and steps= are exact counts of what this classifier ROWED, neither floors nor totals of the program's truth: LOW where a write hides behind a call (limit 2), HIGH where a rowed occurrence is not this variable's (a pp="1" row, or a same-spelled member/attribute a grammar exposes as a bare identifier — Python/Java `o.v`). LIMITS, stated not implied: (1) reach= on the root names the REACHING-DEFINITION rule behind rd=: cfg (C-family, Python) = flow-sensitive — the next unconditional def of a binding KILLS on every path; defs JOIN at if/elif/else, switch (cases fall through), a loop's back-edge, try handlers/finally, for/while-else, match, #ifdef; return/break/continue/throw/raise end a path. linear (JS/TS, Go, Java, Rust) = source order, nothing joins. rd= on a use row = the lines of the defs reaching it (- = none); flow and since edges are this same table. The UNIT is the STATEMENT: uses read the state entering it, its defs apply after (x += 1 reads then kills). NOT branched, per construct: ?:, short-circuit, a conditional expression/comprehension, a lambda/closure/nested def/class body fold into their statement (a def inside applies there, once); goto falls through, untracked; global/nonlocal is tracked like a local (outside writes invisible); a try handler sees the state before every statement of its innermost try body; no alias analysis — a pointer/reference alias is invisible. (2) A WRITE HIDDEN BEHIND A CALL IS NOT A DEF: receiver mutation (v.push_back(x), buf.append(s)) rows k="use" t="read", and a write through an ARGUMENT — a by-reference/pointer parameter, an out-parameter, a function-like macro (SETIT( m )) — rows k="use" t="call-arg", because proving either writes needs the callee's body or the macro's expansion, which this slicer lacks; a false def is worse than a missing one (the flow walk stops at the NEXT def), so it declines to guess — such a variable reports defs= as its introduction alone and a flow of steps="0": no provable edge, not "never written". (3) BLOCK SCOPES ARE SEPARATED: a name declared more than once inside the definition is that many variables; an occurrence binds to the innermost enclosing scope whose declaration precedes it (blocks, loop/if/switch heads, catch clauses, lambdas/closures, per family; JS/TS let/const per block, var per function; Go `v := v+1` and Rust `let v = v+1` read the previous binding in their own initializer; Python is function-scoped — one binding per name, comprehension/lambda scopes not separated). A shadowed seed carries bindings= on the root and b= on every row — the declaration line it binds to; b="0" = no declaration inside the definition binds it (an outer name, or a use before its declaration). (4) PREPROCESSOR (C-family): a conditional region starting inside the definition is decided only by its literal — the body of `#if 0` and the `#else` of `#if 1` are dead, their rows dropped and counted as preproc_rows= (absent when zero); every other conditional (`#ifdef`, `#ifndef`, `#if defined(X)`, `#if EXPR`, `#elif`) is build-dependent: its rows are kept and flagged pp="1", and in a flow a pp def does not kill the reach of the unconditional def before it (both are emitted); macro names in directive text are never occurrences. (5) JS/TS destructuring binders (`const { x, y: yy, z = 3, ...rest } = o`, `[a, b] = arr`, destructured parameters, for-of patterns) are locals defined at the pattern line; a default's right side and a computed key are reads. (6) A reserved word is never an occurrence (a degraded-parse artifact); slicing one refuses like any unknown VAR. (7) Intra-procedural: rows never cross into callees/callers (callers/uses give that half). Served: C/C++/ObjC (+CUDA/Metal), Python, JS/TS, Go, Java, Rust — any other language refuses loudly, never an empty success. -->
<slice sym="rankGraphTeleport" p="src/graph.h:2501" t="fn" lang="cpp" vars="14" at="c7725f3ef" root="." counts="as-classified">
<v n="alpha" l="2501" t="param"/>
<v n="g" l="2501" t="param"/>
<v n="p" l="2501" t="param"/>
<v n="pw" l="2504" t="decl"/>
<v n="N" l="2505" t="decl"/>
<v n="teleport" l="2506" t="decl"/>
<v n="rankDouble" l="2507" t="decl"/>
<v n="run" l="2508" t="decl"/>
<v n="teleportMass" l="2511" t="decl"/>
<v n="value" l="2512" t="decl"/>
<v n="inverseMass" l="2518" t="decl"/>
<v n="value" l="2519" t="decl"/>
<v n="r" l="2526" t="decl"/>
<v n="value" l="2527" t="param"/>
</slice>
`````

## `./build/ripwire . --slice=rankGraphTeleport:teleport`

*Intra-procedural def-use slice of ONE variable: one <s> row per line touching it, k=def|use|both, reaching definitions flow-sensitive (reach=cfg).*

`````
<!-- ripwire slice: NAME-BASED intra-procedural def-use slice of one variable inside ONE resolved definition (ARISE, arXiv:2605.03117). ROWS: one <s> per LINE touching VAR, source order — k= def|use|both|scope (both = the line writes AND reads it, `x += y`; scope = a Python global/nonlocal statement: neither read nor write, it introduces the name and never anchors a flow), t= the strongest role on the line (param > decl > assign > call-arg > read > global/nonlocal), CDATA = the trimmed line. Bare slice=SYM lists the sliceable locals: <v n= l= t=/> per BINDING at its declaration line, vars= their count. COUNTS: counts="as-classified" — not the graph verbs' counts_floor= — defs=, uses=, vars= and steps= are exact counts of what this classifier ROWED, neither floors nor totals of the program's truth: LOW where a write hides behind a call (limit 2), HIGH where a rowed occurrence is not this variable's (a pp="1" row, or a same-spelled member/attribute a grammar exposes as a bare identifier — Python/Java `o.v`). LIMITS, stated not implied: (1) reach= on the root names the REACHING-DEFINITION rule behind rd=: cfg (C-family, Python) = flow-sensitive — the next unconditional def of a binding KILLS on every path; defs JOIN at if/elif/else, switch (cases fall through), a loop's back-edge, try handlers/finally, for/while-else, match, #ifdef; return/break/continue/throw/raise end a path. linear (JS/TS, Go, Java, Rust) = source order, nothing joins. rd= on a use row = the lines of the defs reaching it (- = none); flow and since edges are this same table. The UNIT is the STATEMENT: uses read the state entering it, its defs apply after (x += 1 reads then kills). NOT branched, per construct: ?:, short-circuit, a conditional expression/comprehension, a lambda/closure/nested def/class body fold into their statement (a def inside applies there, once); goto falls through, untracked; global/nonlocal is tracked like a local (outside writes invisible); a try handler sees the state before every statement of its innermost try body; no alias analysis — a pointer/reference alias is invisible. (2) A WRITE HIDDEN BEHIND A CALL IS NOT A DEF: receiver mutation (v.push_back(x), buf.append(s)) rows k="use" t="read", and a write through an ARGUMENT — a by-reference/pointer parameter, an out-parameter, a function-like macro (SETIT( m )) — rows k="use" t="call-arg", because proving either writes needs the callee's body or the macro's expansion, which this slicer lacks; a false def is worse than a missing one (the flow walk stops at the NEXT def), so it declines to guess — such a variable reports defs= as its introduction alone and a flow of steps="0": no provable edge, not "never written". (3) BLOCK SCOPES ARE SEPARATED: a name declared more than once inside the definition is that many variables; an occurrence binds to the innermost enclosing scope whose declaration precedes it (blocks, loop/if/switch heads, catch clauses, lambdas/closures, per family; JS/TS let/const per block, var per function; Go `v := v+1` and Rust `let v = v+1` read the previous binding in their own initializer; Python is function-scoped — one binding per name, comprehension/lambda scopes not separated). A shadowed seed carries bindings= on the root and b= on every row — the declaration line it binds to; b="0" = no declaration inside the definition binds it (an outer name, or a use before its declaration). (4) PREPROCESSOR (C-family): a conditional region starting inside the definition is decided only by its literal — the body of `#if 0` and the `#else` of `#if 1` are dead, their rows dropped and counted as preproc_rows= (absent when zero); every other conditional (`#ifdef`, `#ifndef`, `#if defined(X)`, `#if EXPR`, `#elif`) is build-dependent: its rows are kept and flagged pp="1", and in a flow a pp def does not kill the reach of the unconditional def before it (both are emitted); macro names in directive text are never occurrences. (5) JS/TS destructuring binders (`const { x, y: yy, z = 3, ...rest } = o`, `[a, b] = arr`, destructured parameters, for-of patterns) are locals defined at the pattern line; a default's right side and a computed key are reads. (6) A reserved word is never an occurrence (a degraded-parse artifact); slicing one refuses like any unknown VAR. (7) Intra-procedural: rows never cross into callees/callers (callers/uses give that half). Served: C/C++/ObjC (+CUDA/Metal), Python, JS/TS, Go, Java, Rust — any other language refuses loudly, never an empty success. -->
<slice sym="rankGraphTeleport" p="src/graph.h:2501" t="fn" lang="cpp" var="teleport" defs="1" uses="3" reach="cfg" at="c7725f3ef" root="." counts="as-classified">
<s l="2506" k="def" t="decl">
<![CDATA[std::vector<double> teleport( pw.begin(), pw.end() );]]>
</s>
<s l="2512" k="use" t="read" rd="2506">
<![CDATA[for( const double value : teleport )]]>
</s>
<s l="2519" k="use" t="read" rd="2506">
<![CDATA[for( double& value : teleport )]]>
</s>
<s l="2524" k="use" t="call-arg" rd="2506">
<![CDATA[run = pageRankDouble( g.inEdges, g.wOutDeg, teleport, rankDouble, PageRankConfig{ .alpha = double( alpha ) } );]]>
</s>
</slice>
`````

## `./build/ripwire . --slice=rankGraphTeleport:teleport --slice-flow=back --slice-depth=3`

*TRANSITIVE backward value-flow from the seed variable, bounded BFS (depth= disclosed; a cut frontier says flow_truncated=1).*

`````
<!-- ripwire slice: NAME-BASED intra-procedural def-use slice of one variable inside ONE resolved definition (ARISE, arXiv:2605.03117). ROWS: one <s> per LINE touching VAR, source order — k= def|use|both|scope (both = the line writes AND reads it, `x += y`; scope = a Python global/nonlocal statement: neither read nor write, it introduces the name and never anchors a flow), t= the strongest role on the line (param > decl > assign > call-arg > read > global/nonlocal), CDATA = the trimmed line. Bare slice=SYM lists the sliceable locals: <v n= l= t=/> per BINDING at its declaration line, vars= their count. COUNTS: counts="as-classified" — not the graph verbs' counts_floor= — defs=, uses=, vars= and steps= are exact counts of what this classifier ROWED, neither floors nor totals of the program's truth: LOW where a write hides behind a call (limit 2), HIGH where a rowed occurrence is not this variable's (a pp="1" row, or a same-spelled member/attribute a grammar exposes as a bare identifier — Python/Java `o.v`). LIMITS, stated not implied: (1) reach= on the root names the REACHING-DEFINITION rule behind rd=: cfg (C-family, Python) = flow-sensitive — the next unconditional def of a binding KILLS on every path; defs JOIN at if/elif/else, switch (cases fall through), a loop's back-edge, try handlers/finally, for/while-else, match, #ifdef; return/break/continue/throw/raise end a path. linear (JS/TS, Go, Java, Rust) = source order, nothing joins. rd= on a use row = the lines of the defs reaching it (- = none); flow and since edges are this same table. The UNIT is the STATEMENT: uses read the state entering it, its defs apply after (x += 1 reads then kills). NOT branched, per construct: ?:, short-circuit, a conditional expression/comprehension, a lambda/closure/nested def/class body fold into their statement (a def inside applies there, once); goto falls through, untracked; global/nonlocal is tracked like a local (outside writes invisible); a try handler sees the state before every statement of its innermost try body; no alias analysis — a pointer/reference alias is invisible. (2) A WRITE HIDDEN BEHIND A CALL IS NOT A DEF: receiver mutation (v.push_back(x), buf.append(s)) rows k="use" t="read", and a write through an ARGUMENT — a by-reference/pointer parameter, an out-parameter, a function-like macro (SETIT( m )) — rows k="use" t="call-arg", because proving either writes needs the callee's body or the macro's expansion, which this slicer lacks; a false def is worse than a missing one (the flow walk stops at the NEXT def), so it declines to guess — such a variable reports defs= as its introduction alone and a flow of steps="0": no provable edge, not "never written". (3) BLOCK SCOPES ARE SEPARATED: a name declared more than once inside the definition is that many variables; an occurrence binds to the innermost enclosing scope whose declaration precedes it (blocks, loop/if/switch heads, catch clauses, lambdas/closures, per family; JS/TS let/const per block, var per function; Go `v := v+1` and Rust `let v = v+1` read the previous binding in their own initializer; Python is function-scoped — one binding per name, comprehension/lambda scopes not separated). A shadowed seed carries bindings= on the root and b= on every row — the declaration line it binds to; b="0" = no declaration inside the definition binds it (an outer name, or a use before its declaration). (4) PREPROCESSOR (C-family): a conditional region starting inside the definition is decided only by its literal — the body of `#if 0` and the `#else` of `#if 1` are dead, their rows dropped and counted as preproc_rows= (absent when zero); every other conditional (`#ifdef`, `#ifndef`, `#if defined(X)`, `#if EXPR`, `#elif`) is build-dependent: its rows are kept and flagged pp="1", and in a flow a pp def does not kill the reach of the unconditional def before it (both are emitted); macro names in directive text are never occurrences. (5) JS/TS destructuring binders (`const { x, y: yy, z = 3, ...rest } = o`, `[a, b] = arr`, destructured parameters, for-of patterns) are locals defined at the pattern line; a default's right side and a computed key are reads. (6) A reserved word is never an occurrence (a degraded-parse artifact); slicing one refuses like any unknown VAR. (7) Intra-procedural: rows never cross into callees/callers (callers/uses give that half). Served: C/C++/ObjC (+CUDA/Metal), Python, JS/TS, Go, Java, Rust — any other language refuses loudly, never an empty success. -->
<!-- slice-flow: TRANSITIVE cross-statement data-flow — bounded BFS from the seed variable over reaching-definition edges: a use reaches exactly the defs its rd= names (limit 1's reach= rule; the ARISE slicer's rule; stops at the function boundary like the paper's). flow= back = statements whose values feed the seed | fwd = statements the seed's value reaches | both = the union (backward first, deduplicated). Seed rows are depth 0 in the v1 shape; each FLOW row adds v= the variable at that step, d= its BFS depth, f= the line it was reached FROM (b= as in v1 when v= is shadowed); rows order by (d=, l=, v=). steps= counts flow rows; depth= is the bound in force (default 8, slice-depth sets it); flow_truncated="1" = the bound suppressed at least one row — bounded here, not proven complete. steps="0" = no PROVABLE edge from this seed — its commonest cause is limit (2): receiver mutation leaves no def to anchor on — read the rows, not just the count. EXTRA LIMITS: rows are line-granular (a multi-statement line merges and may over-connect) while chaining is statement-anchored (a statement spanning lines chains as ONE unit keyed on its first line); data dependence only — no control dependence: the guard (if/loop) deciding whether a def executes is never a row. -->
<slice sym="rankGraphTeleport" p="src/graph.h:2501" t="fn" lang="cpp" var="teleport" defs="1" uses="3" reach="cfg" flow="back" depth="3" steps="3" at="c7725f3ef" root="." counts="as-classified">
<s l="2506" k="def" t="decl">
<![CDATA[std::vector<double> teleport( pw.begin(), pw.end() );]]>
</s>
<s l="2512" k="use" t="read" rd="2506">
<![CDATA[for( const double value : teleport )]]>
</s>
<s l="2519" k="use" t="read" rd="2506">
<![CDATA[for( double& value : teleport )]]>
</s>
<s l="2524" k="use" t="call-arg" rd="2506">
<![CDATA[run = pageRankDouble( g.inEdges, g.wOutDeg, teleport, rankDouble, PageRankConfig{ .alpha = double( alpha ) } );]]>
</s>
<s l="2504" k="def" t="decl" v="pw" d="1" f="2506">
<![CDATA[const std::vector<float> pw = biasPrior( g, p );]]>
</s>
<s l="2501" k="def" t="param" v="g" d="2" f="2504">
<![CDATA[inline RankedGraph rankGraphTeleport( const Graph& g, const std::vector<float>& p, float alpha = 0.85f )]]>
</s>
<s l="2501" k="def" t="param" v="p" d="2" f="2504">
<![CDATA[inline RankedGraph rankGraphTeleport( const Graph& g, const std::vector<float>& p, float alpha = 0.85f )]]>
</s>
</slice>
`````

## `./build/ripwire . --slice=rankGraphTeleport:teleport --slice-flow=fwd`

*Forward flow: which statements the seed's value reaches, at the default depth bound.*

`````
<!-- ripwire slice: NAME-BASED intra-procedural def-use slice of one variable inside ONE resolved definition (ARISE, arXiv:2605.03117). ROWS: one <s> per LINE touching VAR, source order — k= def|use|both|scope (both = the line writes AND reads it, `x += y`; scope = a Python global/nonlocal statement: neither read nor write, it introduces the name and never anchors a flow), t= the strongest role on the line (param > decl > assign > call-arg > read > global/nonlocal), CDATA = the trimmed line. Bare slice=SYM lists the sliceable locals: <v n= l= t=/> per BINDING at its declaration line, vars= their count. COUNTS: counts="as-classified" — not the graph verbs' counts_floor= — defs=, uses=, vars= and steps= are exact counts of what this classifier ROWED, neither floors nor totals of the program's truth: LOW where a write hides behind a call (limit 2), HIGH where a rowed occurrence is not this variable's (a pp="1" row, or a same-spelled member/attribute a grammar exposes as a bare identifier — Python/Java `o.v`). LIMITS, stated not implied: (1) reach= on the root names the REACHING-DEFINITION rule behind rd=: cfg (C-family, Python) = flow-sensitive — the next unconditional def of a binding KILLS on every path; defs JOIN at if/elif/else, switch (cases fall through), a loop's back-edge, try handlers/finally, for/while-else, match, #ifdef; return/break/continue/throw/raise end a path. linear (JS/TS, Go, Java, Rust) = source order, nothing joins. rd= on a use row = the lines of the defs reaching it (- = none); flow and since edges are this same table. The UNIT is the STATEMENT: uses read the state entering it, its defs apply after (x += 1 reads then kills). NOT branched, per construct: ?:, short-circuit, a conditional expression/comprehension, a lambda/closure/nested def/class body fold into their statement (a def inside applies there, once); goto falls through, untracked; global/nonlocal is tracked like a local (outside writes invisible); a try handler sees the state before every statement of its innermost try body; no alias analysis — a pointer/reference alias is invisible. (2) A WRITE HIDDEN BEHIND A CALL IS NOT A DEF: receiver mutation (v.push_back(x), buf.append(s)) rows k="use" t="read", and a write through an ARGUMENT — a by-reference/pointer parameter, an out-parameter, a function-like macro (SETIT( m )) — rows k="use" t="call-arg", because proving either writes needs the callee's body or the macro's expansion, which this slicer lacks; a false def is worse than a missing one (the flow walk stops at the NEXT def), so it declines to guess — such a variable reports defs= as its introduction alone and a flow of steps="0": no provable edge, not "never written". (3) BLOCK SCOPES ARE SEPARATED: a name declared more than once inside the definition is that many variables; an occurrence binds to the innermost enclosing scope whose declaration precedes it (blocks, loop/if/switch heads, catch clauses, lambdas/closures, per family; JS/TS let/const per block, var per function; Go `v := v+1` and Rust `let v = v+1` read the previous binding in their own initializer; Python is function-scoped — one binding per name, comprehension/lambda scopes not separated). A shadowed seed carries bindings= on the root and b= on every row — the declaration line it binds to; b="0" = no declaration inside the definition binds it (an outer name, or a use before its declaration). (4) PREPROCESSOR (C-family): a conditional region starting inside the definition is decided only by its literal — the body of `#if 0` and the `#else` of `#if 1` are dead, their rows dropped and counted as preproc_rows= (absent when zero); every other conditional (`#ifdef`, `#ifndef`, `#if defined(X)`, `#if EXPR`, `#elif`) is build-dependent: its rows are kept and flagged pp="1", and in a flow a pp def does not kill the reach of the unconditional def before it (both are emitted); macro names in directive text are never occurrences. (5) JS/TS destructuring binders (`const { x, y: yy, z = 3, ...rest } = o`, `[a, b] = arr`, destructured parameters, for-of patterns) are locals defined at the pattern line; a default's right side and a computed key are reads. (6) A reserved word is never an occurrence (a degraded-parse artifact); slicing one refuses like any unknown VAR. (7) Intra-procedural: rows never cross into callees/callers (callers/uses give that half). Served: C/C++/ObjC (+CUDA/Metal), Python, JS/TS, Go, Java, Rust — any other language refuses loudly, never an empty success. -->
<!-- slice-flow: TRANSITIVE cross-statement data-flow — bounded BFS from the seed variable over reaching-definition edges: a use reaches exactly the defs its rd= names (limit 1's reach= rule; the ARISE slicer's rule; stops at the function boundary like the paper's). flow= back = statements whose values feed the seed | fwd = statements the seed's value reaches | both = the union (backward first, deduplicated). Seed rows are depth 0 in the v1 shape; each FLOW row adds v= the variable at that step, d= its BFS depth, f= the line it was reached FROM (b= as in v1 when v= is shadowed); rows order by (d=, l=, v=). steps= counts flow rows; depth= is the bound in force (default 8, slice-depth sets it); flow_truncated="1" = the bound suppressed at least one row — bounded here, not proven complete. steps="0" = no PROVABLE edge from this seed — its commonest cause is limit (2): receiver mutation leaves no def to anchor on — read the rows, not just the count. EXTRA LIMITS: rows are line-granular (a multi-statement line merges and may over-connect) while chaining is statement-anchored (a statement spanning lines chains as ONE unit keyed on its first line); data dependence only — no control dependence: the guard (if/loop) deciding whether a def executes is never a row. -->
<slice sym="rankGraphTeleport" p="src/graph.h:2501" t="fn" lang="cpp" var="teleport" defs="1" uses="3" reach="cfg" flow="fwd" depth="8" steps="7" at="c7725f3ef" root="." counts="as-classified">
<s l="2506" k="def" t="decl">
<![CDATA[std::vector<double> teleport( pw.begin(), pw.end() );]]>
</s>
<s l="2512" k="use" t="read" rd="2506">
<![CDATA[for( const double value : teleport )]]>
</s>
<s l="2519" k="use" t="read" rd="2506">
<![CDATA[for( double& value : teleport )]]>
</s>
<s l="2524" k="use" t="call-arg" rd="2506">
<![CDATA[run = pageRankDouble( g.inEdges, g.wOutDeg, teleport, rankDouble, PageRankConfig{ .alpha = double( alpha ) } );]]>
</s>
<s l="2514" k="use" t="read" v="value" d="2" f="2512" b="2512">
<![CDATA[teleportMass += value;]]>
</s>
<s l="2521" k="both" t="assign" v="value" d="2" f="2519" b="2519">
<![CDATA[value *= inverseMass;]]>
</s>
<s l="2528" k="use" t="read" v="run" d="2" f="2524">
<![CDATA[return { std::move( r ), run.iterationCount, run.hasConverged };]]>
</s>
<s l="2514" k="both" t="assign" v="teleportMass" d="3" f="2514">
<![CDATA[teleportMass += value;]]>
</s>
<s l="2516" k="use" t="read" v="teleportMass" d="3" f="2514">
<![CDATA[if( teleportMass > 0.0 )]]>
</s>
<s l="2518" k="use" t="read" v="teleportMass" d="3" f="2514">
<![CDATA[const double inverseMass = 1.0 / teleportMass;]]>
</s>
<s l="2521" k="use" t="read" v="inverseMass" d="4" f="2518">
<![CDATA[value *= inverseMass;]]>
</s>
</slice>
`````

## `./build/ripwire . --slice=rankGraphTeleport:nosuchvar`

*A variable the definition does not bind — the refusal shape, naming the inventory.*

**exit code: 1**

`````
(empty)
`````

stderr:

`````
ripwire: --slice: no occurrence of 'nosuchvar' in rankGraphTeleport — sliceable locals: alpha, g, p, pw, N, teleport, rankDouble, run, teleportMass, value, inverseMass, r (bare --slice=rankGraphTeleport lists them with first-def lines)
`````

## `./build/ripwire . --slice-depth=3`

*--slice-depth without --slice-flow is refused loudly rather than silently ignored.*

**exit code: 1**

`````
(empty)
`````

stderr:

`````
ripwire: --slice-depth bounds the --slice-flow BFS — pass both (e.g. ripwire <dir> --slice=parseArgs:argIndex --slice-flow=fwd --slice-depth=4)
`````

## `./build/ripwire . --slice=rankGraphTeleport:teleport --legend=compact`

*The compact legend posture: rows byte-identical, a versioned schema id replaces the repeated explanatory prose — for a many-small-calls loop.*

`````
<!-- ripwire slice ripwire.slice/v1: name-based def-use rows of one variable in one definition: <s l= k=def|use|both|scope t= [b= pp= rd=]> (rd= reaching-def lines per reach=cfg|linear), <v n= l= t=> inventory; steps=/depth= flow. at=: commit(+dirty). root=: p= relative to it. -->
<slice sym="rankGraphTeleport" p="src/graph.h:2501" t="fn" lang="cpp" schema="ripwire.slice/v1" var="teleport" defs="1" uses="3" reach="cfg" at="c7725f3ef" root="." counts="as-classified">
<s l="2506" k="def" t="decl">
<![CDATA[std::vector<double> teleport( pw.begin(), pw.end() );]]>
</s>
<s l="2512" k="use" t="read" rd="2506">
<![CDATA[for( const double value : teleport )]]>
</s>
<s l="2519" k="use" t="read" rd="2506">
<![CDATA[for( double& value : teleport )]]>
</s>
<s l="2524" k="use" t="call-arg" rd="2506">
<![CDATA[run = pageRankDouble( g.inEdges, g.wOutDeg, teleport, rankDouble, PageRankConfig{ .alpha = double( alpha ) } );]]>
</s>
</slice>
`````

## `./build/ripwire . --pattern='rankGraphTeleport($A, $B, $C)'`

*Structural search written in CODE: $NAME binds one node; grammars=/shapes= disclose what the pattern became per grammar (a 3-argument call shape — the 2-argument spelling has no call site in this repo and correctly reports hits=0).*

`````
<!-- ripwire pattern: structural search written in CODE, not in tree-sitter node kinds; each hit = a matching node + its enclosing symbol. q= is the pattern as received. grammars= names every served grammar the pattern resolved for and shapes= the node KIND it became in each, so what was actually searched for is auditable; unsupported= names the families this verb does not serve at all (a zero there would be a lie, so it never reports one). Every grammar name here is per grammar OBJECT, so a dialect that borrows another's templates is spelled apart from it (cpp/cu = the CUDA grammar, typescript/tsx = the TSX one); a bare cpp NEVER stands for its dialects. eligible_files= = corpus files whose grammar the pattern resolved for, i.e. the files actually SCANNED; skipped_files= = files in a served language it did NOT resolve for, which were never read at all; of_files= = total indexed files. $NAME binds one node and the same $NAME twice must match structurally; $_ binds nothing; the ellipsis is matched by a single first-match-wins probe (never an exhaustive search) under the disclosed ellipsis_bound sibling cap. Comments are transparent on both sides; everything else is kind- and text-exact. unresolved_in= names the served grammars the pattern did not resolve for, and appears whenever that could mislead - on a zero result (the zero may be theirs, not the code's) or on any run with skipped_files above zero. shown=/capped= = rows printed vs found. hits= is a FLOOR, not a total, when EITHER hits_capped="1" (engine match limit reached; the root then also carries counts_floor="1" and capped="1" — rows exist that no page holds) or ellipsis_capped="1"; the latter means an ellipsis probe gave up on ellipsis_skipped= candidate nodes whose sibling run exceeded ellipsis_bound, so a node that would have matched can be missing (ellipsis_skipped= counts ABANDONS and is itself a floor on those nodes). raise the default cap with limit=N (offset=M pages; a cut listing carries total=/has_more=/next_offset= so a paging loop can continue from it) -->
<pattern hits="1" shown="1" capped="0" hits_capped="0" q="rankGraphTeleport($A, $B, $C)" grammars="cpp,cpp/cu,c,python,go,rust,typescript,typescript/tsx,swift,objc,javascript,java,csharp" shapes="cpp:call_expression,cpp/cu:call_expression,c:call_expression,python:call,go:call_expression,rust:call_ex … [line truncated: 302 more bytes on this line]
<m p="src/graph.h:2545" in="rankGraph">rankGraphTeleport( g, std::vector&lt;float&gt;( N, N ? 1.0f / float( N ) : 0.f ), alpha )</m>
</pattern>
`````

## `./build/ripwire . --pattern='DEGRADED_PATH_ALERT(...)'`

*The ellipsis form over a macro-shaped call site; unsupported= names the families this verb does not serve.*

`````
<!-- ripwire pattern: structural search written in CODE, not in tree-sitter node kinds; each hit = a matching node + its enclosing symbol. q= is the pattern as received. grammars= names every served grammar the pattern resolved for and shapes= the node KIND it became in each, so what was actually searched for is auditable; unsupported= names the families this verb does not serve at all (a zero there would be a lie, so it never reports one). Every grammar name here is per grammar OBJECT, so a dialect that borrows another's templates is spelled apart from it (cpp/cu = the CUDA grammar, typescript/tsx = the TSX one); a bare cpp NEVER stands for its dialects. eligible_files= = corpus files whose grammar the pattern resolved for, i.e. the files actually SCANNED; skipped_files= = files in a served language it did NOT resolve for, which were never read at all; of_files= = total indexed files. $NAME binds one node and the same $NAME twice must match structurally; $_ binds nothing; the ellipsis is matched by a single first-match-wins probe (never an exhaustive search) under the disclosed ellipsis_bound sibling cap. Comments are transparent on both sides; everything else is kind- and text-exact. unresolved_in= names the served grammars the pattern did not resolve for, and appears whenever that could mislead - on a zero result (the zero may be theirs, not the code's) or on any run with skipped_files above zero. shown=/capped= = rows printed vs found. hits= is a FLOOR, not a total, when EITHER hits_capped="1" (engine match limit reached; the root then also carries counts_floor="1" and capped="1" — rows exist that no page holds) or ellipsis_capped="1"; the latter means an ellipsis probe gave up on ellipsis_skipped= candidate nodes whose sibling run exceeded ellipsis_bound, so a node that would have matched can be missing (ellipsis_skipped= counts ABANDONS and is itself a floor on those nodes). raise the default cap with limit=N (offset=M pages; a cut listing carries total=/has_more=/next_offset= so a paging loop can continue from it) -->
<pattern hits="174" shown="100" capped="1" total="174" has_more="1" next_offset="100" offset="0" limit="0" hits_capped="0" q="DEGRADED_PATH_ALERT(...)" grammars="cpp,cpp/cu,c,python,go,rust,typescript,typescript/tsx,swift,objc,javascript,java,csharp" shapes="cpp:call_expression,cpp/cu:call_expressio … [line truncated: 450 more bytes on this line]
<m p="src/abicheck.h:482" in="collectAuthoredSites">DEGRADED_PATH_ALERT( "abi: no merge-base for a ref (unrelated history?) — that ref is counted, not compared" )</m>
<m p="src/arch.h:353" in="parseArchRules">DEGRADED_PATH_ALERT( "arch: malformed rules line — rules file rejected" )</m>
<m p="src/arch.h:408" in="parseArchRules">DEGRADED_PATH_ALERT( "arch: malformed FROM path-regex — rule skipped" )</m>
<m p="src/atoms.h:365" in="collectExclusions">DEGRADED_PATH_ALERT( "atoms: an exclusion capture stream spent its whole budget; the rules reading it are suppressed thi</m>
<m p="src/clones.h:816" in="findClonesType3">DEGRADED_PATH_ALERT( "clones: Type-3 pair cap hit — first N compared (both-gate-surviving) near-misses kept, rest skip</m>
<m p="src/commentcoherence.h:204" in="computeCommentCoherence">DEGRADED_PATH_ALERT( "comment-coherence: an indexed file could not be read — its functions are absent from the report"</m>
<m p="src/crossref.h:483" in="streamBlobs">DEGRADED_PATH_ALERT( "crossref: cannot write the blob-batch list — cross-branch content unavailable" )</m>
<m p="src/crossref.h:500" in="streamBlobs">DEGRADED_PATH_ALERT( "crossref: git cat-file --batch failed to start — cross-branch content unavailable" )</m>
<m p="src/crossref.h:563" in="streamBlobs">DEGRADED_PATH_ALERT( "crossref: git cat-file stream ended mid-blob — stopping the batch rather than risk misattributin</m>
<m p="src/crossref.h:730" in="enumerateRefs">DEGRADED_PATH_ALERT( "crossref: for-each-ref yielded a ref whose tip is not an object name — skipping it" )</m>
<m p="src/crossref.h:762" in="diffRaw">DEGRADED_PATH_ALERT( "crossref: refusing a diff whose revision arguments are not resolved object names" )</m>
<m p="src/crossref.h:842" in="parallelIndexed">DEGRADED_PATH_ALERT( "crossref: a git worker threw — this shard of the sweep is incomplete" )</m>
<m p="src/crossref.h:1033" in="probeRefBase">DEGRADED_PATH_ALERT( "crossref: ref tip or HEAD is not a resolved object name — refusing to probe, verdict is unknown"</m>
<m p="src/crossref.h:1044" in="probeRefBase">DEGRADED_PATH_ALERT( "crossref: merge-base returned something that is not an object name — discarding it" )</m>
<m p="src/crossref.h:1053" in="probeRefBase">DEGRADED_PATH_ALERT( "crossref: no merge-base for ref (shallow clone or unrelated history?) — verdict is unknown, not </m>
<m p="src/crossref.h:1529" in="lsTree">DEGRADED_PATH_ALERT( "crossref: refusing to list a tree whose revision argument is not a resolved object name" )</m>
<m p="src/crossref.h:1613" in="relabelHeadHitsFromIndex">DEGRADED_PATH_ALERT( "whereis: the index's def sites match no HEAD row (working tree drifted from HEAD?) — keeping the</m>
<m p="src/darkflags.h:765" in="collectCMakeFiles">DEGRADED_PATH_ALERT( "flags: cannot walk root for CMake files — cmake gates omitted" )</m>
<m p="src/dmm.h:271" in="ingestCommitTree">DEGRADED_PATH_ALERT( "dmm: a materialized commit tree ingested empty" )</m>
<m p="src/docdrift.h:1689" in="collectRepoPaths">DEGRADED_PATH_ALERT( "doc-drift: cannot walk the root — the on-disk existence probe is skipped" )</m>
<m p="src/docdrift.h:2336" in="computeDocDrift">DEGRADED_PATH_ALERT( "doc-drift: cannot read a markdown file — its anchors are omitted" )</m>
<m p="src/docdrift.h:2550" in="writeGateability">DEGRADED_PATH_ALERT( "doc-drift gateability: live total disagrees with drift= — projected_drift clamped to a floor of </m>
<m p="src/docparse.h:457" in="runMarkitdown">DEGRADED_PATH_ALERT( "docparse: popen failed for markitdown bridge" )</m>
<m p="src/docparse.h:491" in="parseDocFile">DEGRADED_PATH_ALERT( "docparse: cannot read document file" )</m>
<m p="src/editcheck.h:247" in="editCheckContractVsHead">DEGRADED_PATH_ALERT( "edit-check: no git HEAD baseline available — treating SYM as new-symbol" )</m>
<m p="src/editcheck.h:264" in="editCheckContractVsHead">DEGRADED_PATH_ALERT( "edit-check: baseline snapshot has no definition count for SYM — defs_was suppressed" )</m>
<m p="src/editpreview.h:264" in="ingestOneFile">DEGRADED_PATH_ALERT( "edit-preview: cannot write the spliced file into the temp root" )</m>
<m p="src/editpreview.h:272" in="ingestOneFile">DEGRADED_PATH_ALERT( "edit-preview: short write of the spliced file" )</m>
… [73 more display lines; full output is 18063 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --pattern='x'`

*A pattern that collapses to a bare token is REFUSED — never reported as hits=0.*

**exit code: 1**

`````
(empty)
`````

stderr:

`````
ripwire: --pattern: this pattern collapses to a single bare token, which is a TEXT search, not a structural one — a clean parse is not enough (a bare word parses fine in most grammars and means nothing structural). Give it a shape (foo($X), $A + $B, if ($C) { ... }) or use the grep flag for litera … [line truncated: 187 more bytes on this line]
`````

## `./build/ripwire . --grep=DEGRADED_PATH_ALERT --and=cache`

*Boolean grep: hits where BOTH literals share the matched line (--grep-scope=line is the default).*

`````
<!-- ripwire grep: parallel literal/regex scan; hits GROUP by file under <f p="…">, each <hit> carrying its LINE (l=), its matched text as the hit's own CDATA and enclosing symbol (in=, a NAME here; the same spelling is a fan-in COUNT in for/pack-task/exemplar; ABSENT (never an empty in= value) when no symbol encloses the hit, which is NOT the same claim as file scope — and on a file row carrying parse_degraded="1" it is NO CLAIM AT ALL: that file's parse holds ERROR/MISSING nodes (the skipped verb itemizes err=/err_ratio=), symbols there may be unextracted, so read in= absence inside it as UNKNOWN, not as file scope; absence of parse_degraded= on a row means the parse was clean, except that a file the ingest never parsed at all — doc-format, binary-sniffed, unreadable — is also unmarked, the skipped verb's unmeasured class). root= on the root element is the crawl root every <f p=…> is now RELATIVE to (single-root runs only; absent ⇒ p= is the path ingest itself used, unchanged). ORDER: SOURCE files before test/bench files before docs, then path and line. shown=/capped= = rows printed vs found (a count of underlying HITS, the same unit hits= uses, not of printed <hit> elements); hits_capped="1" ⇒ hits= is a FLOOR (collection budget reached) and the root then also carries counts_floor="1" and capped="1" — rows exist that no page holds. terms= (present only with and/not) restates the whole boolean query as it was EVALUATED: the base pattern, then each and term prefixed +, each not term prefixed -. scope=line (default) requires every term on the SAME matched line as the base pattern; scope=file requires every term ANYWHERE in the file, independent of which line matched. terms_suppressed= counts the raw hits the boolean filter REJECTED — a different axis from hits_capped= (a collection-budget ceiling): hits=/shown=/etc. already read the FILTERED count, so terms_suppressed= exists only so a reader can recover how many the un-filtered scan would have shown. SPAN TIERS: each hit is classified by the tree-sitter span it sits in (code/comment/string) and this answer serves the CODE tier, or — when no hit is code — comment and string TOGETHER; tier= names what was served when it is not code, so a pattern living only in prose is answered, never emptied. tier_partial= (value 1, present only then) qualifies that label: it was elected over the CLASSIFIED hits ALONE while tier_unclassified= hits were never classified, so read it as the tightest tier PROVEN present, never as proof that no hit is code. Nothing past the budget is suppressed, so the partiality narrows what the LABEL may be read to mean, never which rows you got; its absence beside a tier= means the label is a fact. suppressed_comment=/suppressed_string= are the classified hits held back: not in hits=, and the reason complete= cannot appear. Pass grep-in=any (dashes omitted) for every tier. Hit files are parsed on demand under a fixed budget: tier_parsed= how many were classified, tier_budget= which ceiling stopped it (files or bytes, present only then — and the root then also carries counts_floor="1": the tier counts are floors while hits= stays exact and every row is served), tier_unclassified= hits in files nothing classified — always EMITTED, never suppressed. A byte-identical match at OTHER sites in the SAME file folds into the first <hit>'s n= (default 1, unset) and an at-tagged sibling element (l=/in=, self-closing) per extra site — never on a paged or grep-context/-before/-after answer (dashes omitted, illegal in an XML comment), where every site keeps its own <hit>. After the hit rows, <enc> rows list each DISTINCT enclosing symbol NAME of THIS page (first-appearance order, bounded by the page) with callers= its 1-hop DISTINCT-caller count, unioned across same-named defs like the callers verb (a FLOOR — dynamic dispatch contributes no edge), defs= how many defs the name grouped (only when more than one), cx= complexity; amp=/tested= join only when a metrics co-run already computed that lens. On a zero-hit answer a <suggest> element may follow: SUGGESTIONS, never matches — near= the nearest indexed symbol name (did-you-mean), next= a ready-to-paste conceptual fallback; absent for regex/non-word-like patterns or when nothing plausible exists. COMPLETENESS: complete= on the root (value 1) means this listing is EXHAUSTIVE and a consumer need not re-derive it: a LITERAL scan read every indexed file end to end, hit no collection ceiling, and printed every hit it found — so on this answer a zero really is zero and a hit absent above is absent from every indexed file. The claim is complete-within-the-index ONLY: most files the ingest skipped were never scanned (the skipped verb lists exactly which, with reasons; the ONE exception is the unindexed_files_scanned= class right below, itself never covered by complete=), and files outside the indexed roots are outside the claim. It never appears on a regex answer (the prefilter is a performance switch that may not change the answer, so neither mode claims), a capped or paged listing, or a scan that could not read a file; its ABSENCE claims nothing. The enc rows' caller counts stay FLOORS regardless — complete= speaks for the hit rows alone. unindexed_files_scanned= counts files outside the index (unsupported-ext, but text-looking — the skipped verb's own unsupported-ext class) that THIS answer additionally scanned for the same pattern; their hits print inside a trailing unindexed element (present only when it found something), holding its own <f> rows in the same shape as above, and never carry in= — there is no symbol table to check for such a file, which is not the same claim as file scope. THE TWO POPULATIONS: every count above — files, hits, shown, capped, total, complete — is the IN-INDEX search ALONE. unindexed_hits= sizes the second one, always stated (a zero included); the trailing unindexed element carries that same number as its own count= beside shown=/capped= and obeys the SAME window limit/offset set here (dashes omitted), so a one-row page is one row on BOTH lists and a page past its end is empty, not repeated. unindexed_files_skipped= (present only when nonzero) counts candidates this scan saw but did not read: over the max-file-size ceiling, sniffed binary, or unreadable. unindexed_candidates_capped="1" (present only when true) means the CANDIDATE list itself (the skipped verb's own 500-row-per-class cap) was already a floor, so files past it were never considered here either — see the skipped verb for every row. corpus_excluded= counts files an exclude filter (or built-in crawl policy) kept OUT of the index entirely; corpus_oversize= counts files the crawl SAW but dropped for exceeding the size ceiling. Both answer what an otherwise-empty answer alone cannot: not in this repo, or in a file that was never scanned — the skipped verb itemizes the rows behind either count. next= is the one pasteable follow-up: the at verb on the top hit; the next page (compact legend) when cut; the conceptual lens on a zero-hit answer. raise the default cap with limit=N (offset=M pages; a cut listing carries total=/has_more=/next_offset= so a paging loop can continue from it); on the root, limit="0" means no explicit limit was given and the verb's own default page size shaped the window — never a zero-row page -->
<grep pattern="DEGRADED_PATH_ALERT" root="." terms="DEGRADED_PATH_ALERT +cache" scope="line" terms_suppressed="333" files="6" hits="27" shown="27" capped="0" hits_capped="0" suppressed_comment="1" suppressed_string="4" tier_parsed="8" corpus_oversize="15" unindexed_hits="29" unindexed_files_scanned= … [line truncated: 66 more bytes on this line]
<f p="src/gitoracle.h">
<hit l="321" in="gitoracle::saveOracleCache">
<![CDATA[        DEGRADED_PATH_ALERT( "gitoracle: cannot write the history cache — the probe stays correct but re-runs cold" );]]>
</hit>
<hit l="329" in="gitoracle::saveOracleCache">
<![CDATA[        DEGRADED_PATH_ALERT( "gitoracle: history cache write/rename failed — the probe stays correct but re-runs cold" );]]>
</hit>
</f>
<f p="src/ingest_cache.h">
<hit l="975" in="openCacheFrame">
<![CDATA[            DEGRADED_PATH_ALERT( "ingest: cache blob is a different format version — rejected and rebuilt (full reparse)" );]]>
</hit>
<hit l="980" in="openCacheFrame">
<![CDATA[            DEGRADED_PATH_ALERT( "ingest: cache blob parserVer/arch mismatch (older or foreign binary) — rejected and rebuilt (full reparse)" );]]>
</hit>
<hit l="1004" in="openCacheFrame">
<![CDATA[        DEGRADED_PATH_ALERT( "ingest: cache blob trailer does not describe the file (torn write) — cache treated as corrupt" );]]>
</hit>
<hit l="1019" in="openCacheFrame">
<![CDATA[        DEGRADED_PATH_ALERT( "ingest: cache offset-table checksum mismatch — cache treated as corrupt (full reparse)" );]]>
</hit>
<hit l="1039" in="openCacheFrame">
<![CDATA[            DEGRADED_PATH_ALERT( "ingest: cache offset-table entry out of bounds or out of order — cache treated as corrupt" );]]>
</hit>
<hit l="1393" in="readFileRecord">
<![CDATA[        DEGRADED_PATH_ALERT( "ingest: cache record count exceeds remaining bytes — cache treated as corrupt" );]]>
</hit>
<hit l="1429" in="readFileRecord">
… [179 more display lines; full output is 17230 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --grep=DEGRADED_PATH_ALERT --not=test --grep-scope=file`

*Drop every hit in a file that ALSO contains the --not literal anywhere (file scope).*

`````
<!-- ripwire grep: parallel literal/regex scan; hits GROUP by file under <f p="…">, each <hit> carrying its LINE (l=), its matched text as the hit's own CDATA and enclosing symbol (in=, a NAME here; the same spelling is a fan-in COUNT in for/pack-task/exemplar; ABSENT (never an empty in= value) when no symbol encloses the hit, which is NOT the same claim as file scope — and on a file row carrying parse_degraded="1" it is NO CLAIM AT ALL: that file's parse holds ERROR/MISSING nodes (the skipped verb itemizes err=/err_ratio=), symbols there may be unextracted, so read in= absence inside it as UNKNOWN, not as file scope; absence of parse_degraded= on a row means the parse was clean, except that a file the ingest never parsed at all — doc-format, binary-sniffed, unreadable — is also unmarked, the skipped verb's unmeasured class). root= on the root element is the crawl root every <f p=…> is now RELATIVE to (single-root runs only; absent ⇒ p= is the path ingest itself used, unchanged). ORDER: SOURCE files before test/bench files before docs, then path and line. shown=/capped= = rows printed vs found (a count of underlying HITS, the same unit hits= uses, not of printed <hit> elements); hits_capped="1" ⇒ hits= is a FLOOR (collection budget reached) and the root then also carries counts_floor="1" and capped="1" — rows exist that no page holds. terms= (present only with and/not) restates the whole boolean query as it was EVALUATED: the base pattern, then each and term prefixed +, each not term prefixed -. scope=line (default) requires every term on the SAME matched line as the base pattern; scope=file requires every term ANYWHERE in the file, independent of which line matched. terms_suppressed= counts the raw hits the boolean filter REJECTED — a different axis from hits_capped= (a collection-budget ceiling): hits=/shown=/etc. already read the FILTERED count, so terms_suppressed= exists only so a reader can recover how many the un-filtered scan would have shown. SPAN TIERS: each hit is classified by the tree-sitter span it sits in (code/comment/string) and this answer serves the CODE tier, or — when no hit is code — comment and string TOGETHER; tier= names what was served when it is not code, so a pattern living only in prose is answered, never emptied. tier_partial= (value 1, present only then) qualifies that label: it was elected over the CLASSIFIED hits ALONE while tier_unclassified= hits were never classified, so read it as the tightest tier PROVEN present, never as proof that no hit is code. Nothing past the budget is suppressed, so the partiality narrows what the LABEL may be read to mean, never which rows you got; its absence beside a tier= means the label is a fact. suppressed_comment=/suppressed_string= are the classified hits held back: not in hits=, and the reason complete= cannot appear. Pass grep-in=any (dashes omitted) for every tier. Hit files are parsed on demand under a fixed budget: tier_parsed= how many were classified, tier_budget= which ceiling stopped it (files or bytes, present only then — and the root then also carries counts_floor="1": the tier counts are floors while hits= stays exact and every row is served), tier_unclassified= hits in files nothing classified — always EMITTED, never suppressed. A byte-identical match at OTHER sites in the SAME file folds into the first <hit>'s n= (default 1, unset) and an at-tagged sibling element (l=/in=, self-closing) per extra site — never on a paged or grep-context/-before/-after answer (dashes omitted, illegal in an XML comment), where every site keeps its own <hit>. After the hit rows, <enc> rows list each DISTINCT enclosing symbol NAME of THIS page (first-appearance order, bounded by the page) with callers= its 1-hop DISTINCT-caller count, unioned across same-named defs like the callers verb (a FLOOR — dynamic dispatch contributes no edge), defs= how many defs the name grouped (only when more than one), cx= complexity; amp=/tested= join only when a metrics co-run already computed that lens. On a zero-hit answer a <suggest> element may follow: SUGGESTIONS, never matches — near= the nearest indexed symbol name (did-you-mean), next= a ready-to-paste conceptual fallback; absent for regex/non-word-like patterns or when nothing plausible exists. COMPLETENESS: complete= on the root (value 1) means this listing is EXHAUSTIVE and a consumer need not re-derive it: a LITERAL scan read every indexed file end to end, hit no collection ceiling, and printed every hit it found — so on this answer a zero really is zero and a hit absent above is absent from every indexed file. The claim is complete-within-the-index ONLY: most files the ingest skipped were never scanned (the skipped verb lists exactly which, with reasons; the ONE exception is the unindexed_files_scanned= class right below, itself never covered by complete=), and files outside the indexed roots are outside the claim. It never appears on a regex answer (the prefilter is a performance switch that may not change the answer, so neither mode claims), a capped or paged listing, or a scan that could not read a file; its ABSENCE claims nothing. The enc rows' caller counts stay FLOORS regardless — complete= speaks for the hit rows alone. unindexed_files_scanned= counts files outside the index (unsupported-ext, but text-looking — the skipped verb's own unsupported-ext class) that THIS answer additionally scanned for the same pattern; their hits print inside a trailing unindexed element (present only when it found something), holding its own <f> rows in the same shape as above, and never carry in= — there is no symbol table to check for such a file, which is not the same claim as file scope. THE TWO POPULATIONS: every count above — files, hits, shown, capped, total, complete — is the IN-INDEX search ALONE. unindexed_hits= sizes the second one, always stated (a zero included); the trailing unindexed element carries that same number as its own count= beside shown=/capped= and obeys the SAME window limit/offset set here (dashes omitted), so a one-row page is one row on BOTH lists and a page past its end is empty, not repeated. unindexed_files_skipped= (present only when nonzero) counts candidates this scan saw but did not read: over the max-file-size ceiling, sniffed binary, or unreadable. unindexed_candidates_capped="1" (present only when true) means the CANDIDATE list itself (the skipped verb's own 500-row-per-class cap) was already a floor, so files past it were never considered here either — see the skipped verb for every row. corpus_excluded= counts files an exclude filter (or built-in crawl policy) kept OUT of the index entirely; corpus_oversize= counts files the crawl SAW but dropped for exceeding the size ceiling. Both answer what an otherwise-empty answer alone cannot: not in this repo, or in a file that was never scanned — the skipped verb itemizes the rows behind either count. next= is the one pasteable follow-up: the at verb on the top hit; the next page (compact legend) when cut; the conceptual lens on a zero-hit answer. raise the default cap with limit=N (offset=M pages; a cut listing carries total=/has_more=/next_offset= so a paging loop can continue from it); on the root, limit="0" means no explicit limit was given and the verb's own default page size shaped the window — never a zero-row page -->
<grep pattern="DEGRADED_PATH_ALERT" root="." terms="DEGRADED_PATH_ALERT -test" scope="file" terms_suppressed="348" files="7" hits="8" shown="8" capped="0" hits_capped="0" suppressed_comment="9" tier_parsed="10" corpus_oversize="15" unindexed_hits="29" unindexed_files_scanned="168" unindexed_files_sk … [line truncated: 49 more bytes on this line]
<f p="src/commentcoherence.h" parse_degraded="1">
<hit l="204" in="rw::computeCommentCoherence">
<![CDATA[                DEGRADED_PATH_ALERT( "comment-coherence: an indexed file could not be read — its functions are absent from the report" );]]>
</hit>
</f>
<f p="src/infra/Diagnostics.h">
<hit l="158" in="DEGRADED_PATH_ALERT">
<![CDATA[#define DEGRADED_PATH_ALERT(msg)                                                \]]>
</hit>
<hit l="166" in="DEGRADED_PATH_ALERT">
<![CDATA[#define DEGRADED_PATH_ALERT(msg)        do { } while (0)]]>
</hit>
</f>
<f p="src/ingest.cpp">
<hit l="205" in="rw::ingest">
<![CDATA[        DEGRADED_PATH_ALERT( "ingest: null root directory — empty result" );]]>
</hit>
</f>
<f p="src/ingest_docpass.h">
<hit l="149" in="runDocPostPass">
<![CDATA[                        DEGRADED_PATH_ALERT( "ingest: doc post-pass worker exception on a file — skipped" );]]>
</hit>
</f>
<f p="src/ingest_prewarm.h">
<hit l="279" in="prewarmTagsQueries">
<![CDATA[                        DEGRADED_PATH_ALERT( "ingest: prewarm hash worker exception on a file — treated as no-miss" );]]>
</hit>
</f>
… [120 more display lines; full output is 13479 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --grep=DEGRADED_PATH_ALERT --grep=cache`

*A second --grep= REFUSES and names --and= as the AND spelling — no silent overwrite.*

**exit code: 1**

`````
(empty)
`````

stderr:

`````
ripwire: --grep given twice; did you mean --grep='A' --and='B'?
`````

## `./build/ripwire . --grep=DEGRADED_PATH_ALERT --grep-in=any`

*Span tiers off: the exhaustive view — the comment and string hits the default tier held back (suppressed_comment=96 / suppressed_string=29 in the plain --grep block above) now print alongside the code hits; hits= grows accordingly.*

`````
<!-- ripwire grep: parallel literal/regex scan; hits GROUP by file under <f p="…">, each <hit> carrying its LINE (l=), its matched text as the hit's own CDATA and enclosing symbol (in=, a NAME here; the same spelling is a fan-in COUNT in for/pack-task/exemplar; ABSENT (never an empty in= value) when no symbol encloses the hit, which is NOT the same claim as file scope — and on a file row carrying parse_degraded="1" it is NO CLAIM AT ALL: that file's parse holds ERROR/MISSING nodes (the skipped verb itemizes err=/err_ratio=), symbols there may be unextracted, so read in= absence inside it as UNKNOWN, not as file scope; absence of parse_degraded= on a row means the parse was clean, except that a file the ingest never parsed at all — doc-format, binary-sniffed, unreadable — is also unmarked, the skipped verb's unmeasured class). root= on the root element is the crawl root every <f p=…> is now RELATIVE to (single-root runs only; absent ⇒ p= is the path ingest itself used, unchanged). ORDER: SOURCE files before test/bench files before docs, then path and line. shown=/capped= = rows printed vs found (a count of underlying HITS, the same unit hits= uses, not of printed <hit> elements); hits_capped="1" ⇒ hits= is a FLOOR (collection budget reached) and the root then also carries counts_floor="1" and capped="1" — rows exist that no page holds. A byte-identical match at OTHER sites in the SAME file folds into the first <hit>'s n= (default 1, unset) and an at-tagged sibling element (l=/in=, self-closing) per extra site — never on a paged or grep-context/-before/-after answer (dashes omitted, illegal in an XML comment), where every site keeps its own <hit>. After the hit rows, <enc> rows list each DISTINCT enclosing symbol NAME of THIS page (first-appearance order, bounded by the page) with callers= its 1-hop DISTINCT-caller count, unioned across same-named defs like the callers verb (a FLOOR — dynamic dispatch contributes no edge), defs= how many defs the name grouped (only when more than one), cx= complexity; amp=/tested= join only when a metrics co-run already computed that lens. On a zero-hit answer a <suggest> element may follow: SUGGESTIONS, never matches — near= the nearest indexed symbol name (did-you-mean), next= a ready-to-paste conceptual fallback; absent for regex/non-word-like patterns or when nothing plausible exists. COMPLETENESS: complete= on the root (value 1) means this listing is EXHAUSTIVE and a consumer need not re-derive it: a LITERAL scan read every indexed file end to end, hit no collection ceiling, and printed every hit it found — so on this answer a zero really is zero and a hit absent above is absent from every indexed file. The claim is complete-within-the-index ONLY: most files the ingest skipped were never scanned (the skipped verb lists exactly which, with reasons; the ONE exception is the unindexed_files_scanned= class right below, itself never covered by complete=), and files outside the indexed roots are outside the claim. It never appears on a regex answer (the prefilter is a performance switch that may not change the answer, so neither mode claims), a capped or paged listing, or a scan that could not read a file; its ABSENCE claims nothing. The enc rows' caller counts stay FLOORS regardless — complete= speaks for the hit rows alone. unindexed_files_scanned= counts files outside the index (unsupported-ext, but text-looking — the skipped verb's own unsupported-ext class) that THIS answer additionally scanned for the same pattern; their hits print inside a trailing unindexed element (present only when it found something), holding its own <f> rows in the same shape as above, and never carry in= — there is no symbol table to check for such a file, which is not the same claim as file scope. THE TWO POPULATIONS: every count above — files, hits, shown, capped, total, complete — is the IN-INDEX search ALONE. unindexed_hits= sizes the second one, always stated (a zero included); the trailing unindexed element carries that same number as its own count= beside shown=/capped= and obeys the SAME window limit/offset set here (dashes omitted), so a one-row page is one row on BOTH lists and a page past its end is empty, not repeated. unindexed_files_skipped= (present only when nonzero) counts candidates this scan saw but did not read: over the max-file-size ceiling, sniffed binary, or unreadable. unindexed_candidates_capped="1" (present only when true) means the CANDIDATE list itself (the skipped verb's own 500-row-per-class cap) was already a floor, so files past it were never considered here either — see the skipped verb for every row. corpus_excluded= counts files an exclude filter (or built-in crawl policy) kept OUT of the index entirely; corpus_oversize= counts files the crawl SAW but dropped for exceeding the size ceiling. Both answer what an otherwise-empty answer alone cannot: not in this repo, or in a file that was never scanned — the skipped verb itemizes the rows behind either count. next= is the one pasteable follow-up: the at verb on the top hit; the next page (compact legend) when cut; the conceptual lens on a zero-hit answer. raise the default cap with limit=N (offset=M pages; a cut listing carries total=/has_more=/next_offset= so a paging loop can continue from it); on the root, limit="0" means no explicit limit was given and the verb's own default page size shaped the window — never a zero-row page -->
<grep pattern="DEGRADED_PATH_ALERT" root="." files="95" hits="365" shown="100" capped="1" total="365" has_more="1" next_offset="100" offset="0" limit="0" hits_capped="0" corpus_oversize="15" unindexed_hits="29" unindexed_files_scanned="168" unindexed_files_skipped="1" next="--grep=DEGRADED_PATH_ALER … [line truncated: 33 more bytes on this line]
<f p=".github/workflows/ci.yml">
<hit l="115" in="release">
<![CDATA[    #   Release — defines NDEBUG, which compiles DEGRADED_PATH_ALERT out; the optimizer-visible build.]]>
</hit>
<hit l="116" in="release">
<![CDATA[    #   plain   — NDEBUG off, so DEGRADED_PATH_ALERT compiles in and the degrade-path gates can observe]]>
</hit>
</f>
<f p="src/abicheck.h" parse_degraded="1">
<hit l="108">
<![CDATA[#include "infra/Diagnostics.h"  // VERIFY / DEGRADED_PATH_ALERT]]>
</hit>
<hit l="482" in="abicheck::collectAuthoredSites">
<![CDATA[            DEGRADED_PATH_ALERT( "abi: no merge-base for a ref (unrelated history?) — that ref is counted, not compared" );]]>
</hit>
</f>
<f p="src/accessshape.h">
<hit l="132">
<![CDATA[#include "infra/Diagnostics.h"  // VERIFY / DEGRADED_PATH_ALERT]]>
</hit>
</f>
<f p="src/arch.h">
<hit l="31">
<![CDATA[#include "infra/Diagnostics.h"  // DEGRADED_PATH_ALERT — graceful-degrade on a malformed path-regex (never throw at match time)]]>
</hit>
<hit l="353" in="rw::parseArchRules">
<![CDATA[        DEGRADED_PATH_ALERT( "arch: malformed rules line — rules file rejected" );]]>
</hit>
… [485 more display lines; full output is 29284 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --grep=deterministic`

*A literal whose classified hits are all prose: the answer serves tier="comment+string" rather than an empty code tier, and tier_unclassified= says how many hits the fixed parse budget never classified.*

`````
<!-- ripwire grep: parallel literal/regex scan; hits GROUP by file under <f p="…">, each <hit> carrying its LINE (l=), its matched text as the hit's own CDATA and enclosing symbol (in=, a NAME here; the same spelling is a fan-in COUNT in for/pack-task/exemplar; ABSENT (never an empty in= value) when no symbol encloses the hit, which is NOT the same claim as file scope — and on a file row carrying parse_degraded="1" it is NO CLAIM AT ALL: that file's parse holds ERROR/MISSING nodes (the skipped verb itemizes err=/err_ratio=), symbols there may be unextracted, so read in= absence inside it as UNKNOWN, not as file scope; absence of parse_degraded= on a row means the parse was clean, except that a file the ingest never parsed at all — doc-format, binary-sniffed, unreadable — is also unmarked, the skipped verb's unmeasured class). root= on the root element is the crawl root every <f p=…> is now RELATIVE to (single-root runs only; absent ⇒ p= is the path ingest itself used, unchanged). ORDER: SOURCE files before test/bench files before docs, then path and line. shown=/capped= = rows printed vs found (a count of underlying HITS, the same unit hits= uses, not of printed <hit> elements); hits_capped="1" ⇒ hits= is a FLOOR (collection budget reached) and the root then also carries counts_floor="1" and capped="1" — rows exist that no page holds. SPAN TIERS: each hit is classified by the tree-sitter span it sits in (code/comment/string) and this answer serves the CODE tier, or — when no hit is code — comment and string TOGETHER; tier= names what was served when it is not code, so a pattern living only in prose is answered, never emptied. tier_partial= (value 1, present only then) qualifies that label: it was elected over the CLASSIFIED hits ALONE while tier_unclassified= hits were never classified, so read it as the tightest tier PROVEN present, never as proof that no hit is code. Nothing past the budget is suppressed, so the partiality narrows what the LABEL may be read to mean, never which rows you got; its absence beside a tier= means the label is a fact. suppressed_comment=/suppressed_string= are the classified hits held back: not in hits=, and the reason complete= cannot appear. Pass grep-in=any (dashes omitted) for every tier. Hit files are parsed on demand under a fixed budget: tier_parsed= how many were classified, tier_budget= which ceiling stopped it (files or bytes, present only then — and the root then also carries counts_floor="1": the tier counts are floors while hits= stays exact and every row is served), tier_unclassified= hits in files nothing classified — always EMITTED, never suppressed. A byte-identical match at OTHER sites in the SAME file folds into the first <hit>'s n= (default 1, unset) and an at-tagged sibling element (l=/in=, self-closing) per extra site — never on a paged or grep-context/-before/-after answer (dashes omitted, illegal in an XML comment), where every site keeps its own <hit>. After the hit rows, <enc> rows list each DISTINCT enclosing symbol NAME of THIS page (first-appearance order, bounded by the page) with callers= its 1-hop DISTINCT-caller count, unioned across same-named defs like the callers verb (a FLOOR — dynamic dispatch contributes no edge), defs= how many defs the name grouped (only when more than one), cx= complexity; amp=/tested= join only when a metrics co-run already computed that lens. On a zero-hit answer a <suggest> element may follow: SUGGESTIONS, never matches — near= the nearest indexed symbol name (did-you-mean), next= a ready-to-paste conceptual fallback; absent for regex/non-word-like patterns or when nothing plausible exists. COMPLETENESS: complete= on the root (value 1) means this listing is EXHAUSTIVE and a consumer need not re-derive it: a LITERAL scan read every indexed file end to end, hit no collection ceiling, and printed every hit it found — so on this answer a zero really is zero and a hit absent above is absent from every indexed file. The claim is complete-within-the-index ONLY: most files the ingest skipped were never scanned (the skipped verb lists exactly which, with reasons; the ONE exception is the unindexed_files_scanned= class right below, itself never covered by complete=), and files outside the indexed roots are outside the claim. It never appears on a regex answer (the prefilter is a performance switch that may not change the answer, so neither mode claims), a capped or paged listing, or a scan that could not read a file; its ABSENCE claims nothing. The enc rows' caller counts stay FLOORS regardless — complete= speaks for the hit rows alone. unindexed_files_scanned= counts files outside the index (unsupported-ext, but text-looking — the skipped verb's own unsupported-ext class) that THIS answer additionally scanned for the same pattern; their hits print inside a trailing unindexed element (present only when it found something), holding its own <f> rows in the same shape as above, and never carry in= — there is no symbol table to check for such a file, which is not the same claim as file scope. THE TWO POPULATIONS: every count above — files, hits, shown, capped, total, complete — is the IN-INDEX search ALONE. unindexed_hits= sizes the second one, always stated (a zero included); the trailing unindexed element carries that same number as its own count= beside shown=/capped= and obeys the SAME window limit/offset set here (dashes omitted), so a one-row page is one row on BOTH lists and a page past its end is empty, not repeated. unindexed_files_skipped= (present only when nonzero) counts candidates this scan saw but did not read: over the max-file-size ceiling, sniffed binary, or unreadable. unindexed_candidates_capped="1" (present only when true) means the CANDIDATE list itself (the skipped verb's own 500-row-per-class cap) was already a floor, so files past it were never considered here either — see the skipped verb for every row. corpus_excluded= counts files an exclude filter (or built-in crawl policy) kept OUT of the index entirely; corpus_oversize= counts files the crawl SAW but dropped for exceeding the size ceiling. Both answer what an otherwise-empty answer alone cannot: not in this repo, or in a file that was never scanned — the skipped verb itemizes the rows behind either count. next= is the one pasteable follow-up: the at verb on the top hit; the next page (compact legend) when cut; the conceptual lens on a zero-hit answer. raise the default cap with limit=N (offset=M pages; a cut listing carries total=/has_more=/next_offset= so a paging loop can continue from it); on the root, limit="0" means no explicit limit was given and the verb's own default page size shaped the window — never a zero-row page -->
<grep pattern="deterministic" root="." files="520" hits="1387" shown="100" capped="1" total="1387" has_more="1" next_offset="100" offset="0" limit="0" hits_capped="0" tier="comment+string" tier_partial="1" tier_parsed="128" tier_unclassified="924" tier_budget="files" counts_floor="1" corpus_oversize … [line truncated: 143 more bytes on this line]
<f p="hooks/ripwire-claude-route.sh">
<hit l="2">
<![CDATA[# hooks/ripwire-claude-route.sh — OPT-IN Claude Code UserPromptSubmit router. Ask the deterministic]]>
</hit>
</f>
<f p="hooks/ripwire-codex-route.sh">
<hit l="2">
<![CDATA[# Codex UserPromptSubmit router: ask the deterministic --help-task classifier before the first tool]]>
</hit>
</f>
<f p="present/deck5_ripwire_build.js">
<hit l="62">
<![CDATA[  s.addText("A zero-runtime-dependency C++23 CLI that maps any codebase into a ranked, deterministic\ncall graph for coding agents — and puts a tripwire on every claim it emits.",]]>
</hit>
<hit l="525">
<![CDATA[    ["parallel parse", "query compile overlaps parse scheduling; files schedule by size — ids stay deterministic"],]]>
</hit>
<hit l="853">
<![CDATA[  foot(s, "the MCP server exposes the same deterministic engine — one index, shared with the CLI, staleness-checked");]]>
</hit>
<hit l="870">
<![CDATA[    ["2009", "Reciprocal Rank Fusion — Cormack et al.", "deterministic signal fusion (--rank-by=rrf)"],]]>
</hit>
</f>
<f p="scripts/scorecard.sh">
<hit l="12">
<![CDATA[# Output is deterministic (same table on every run of the same tree).]]>
</hit>
… [681 more display lines; full output is 43755 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --grep=DEGRADED_PATH_ALERT --handles`

*h= on each editable enclosing-symbol row: a freshness-pinned identity an edit verb can target and must refuse on after any file change.*

`````
<!-- ripwire grep: parallel literal/regex scan; hits GROUP by file under <f p="…">, each <hit> carrying its LINE (l=), its matched text as the hit's own CDATA and enclosing symbol (in=, a NAME here; the same spelling is a fan-in COUNT in for/pack-task/exemplar; ABSENT (never an empty in= value) when no symbol encloses the hit, which is NOT the same claim as file scope — and on a file row carrying parse_degraded="1" it is NO CLAIM AT ALL: that file's parse holds ERROR/MISSING nodes (the skipped verb itemizes err=/err_ratio=), symbols there may be unextracted, so read in= absence inside it as UNKNOWN, not as file scope; absence of parse_degraded= on a row means the parse was clean, except that a file the ingest never parsed at all — doc-format, binary-sniffed, unreadable — is also unmarked, the skipped verb's unmeasured class). root= on the root element is the crawl root every <f p=…> is now RELATIVE to (single-root runs only; absent ⇒ p= is the path ingest itself used, unchanged). ORDER: SOURCE files before test/bench files before docs, then path and line. shown=/capped= = rows printed vs found (a count of underlying HITS, the same unit hits= uses, not of printed <hit> elements); hits_capped="1" ⇒ hits= is a FLOOR (collection budget reached) and the root then also carries counts_floor="1" and capped="1" — rows exist that no page holds. SPAN TIERS: each hit is classified by the tree-sitter span it sits in (code/comment/string) and this answer serves the CODE tier, or — when no hit is code — comment and string TOGETHER; tier= names what was served when it is not code, so a pattern living only in prose is answered, never emptied. tier_partial= (value 1, present only then) qualifies that label: it was elected over the CLASSIFIED hits ALONE while tier_unclassified= hits were never classified, so read it as the tightest tier PROVEN present, never as proof that no hit is code. Nothing past the budget is suppressed, so the partiality narrows what the LABEL may be read to mean, never which rows you got; its absence beside a tier= means the label is a fact. suppressed_comment=/suppressed_string= are the classified hits held back: not in hits=, and the reason complete= cannot appear. Pass grep-in=any (dashes omitted) for every tier. Hit files are parsed on demand under a fixed budget: tier_parsed= how many were classified, tier_budget= which ceiling stopped it (files or bytes, present only then — and the root then also carries counts_floor="1": the tier counts are floors while hits= stays exact and every row is served), tier_unclassified= hits in files nothing classified — always EMITTED, never suppressed. A byte-identical match at OTHER sites in the SAME file folds into the first <hit>'s n= (default 1, unset) and an at-tagged sibling element (l=/in=, self-closing) per extra site — never on a paged or grep-context/-before/-after answer (dashes omitted, illegal in an XML comment), where every site keeps its own <hit>. After the hit rows, <enc> rows list each DISTINCT enclosing symbol NAME of THIS page (first-appearance order, bounded by the page) with callers= its 1-hop DISTINCT-caller count, unioned across same-named defs like the callers verb (a FLOOR — dynamic dispatch contributes no edge), defs= how many defs the name grouped (only when more than one), cx= complexity; amp=/tested= join only when a metrics co-run already computed that lens. On a zero-hit answer a <suggest> element may follow: SUGGESTIONS, never matches — near= the nearest indexed symbol name (did-you-mean), next= a ready-to-paste conceptual fallback; absent for regex/non-word-like patterns or when nothing plausible exists. COMPLETENESS: complete= on the root (value 1) means this listing is EXHAUSTIVE and a consumer need not re-derive it: a LITERAL scan read every indexed file end to end, hit no collection ceiling, and printed every hit it found — so on this answer a zero really is zero and a hit absent above is absent from every indexed file. The claim is complete-within-the-index ONLY: most files the ingest skipped were never scanned (the skipped verb lists exactly which, with reasons; the ONE exception is the unindexed_files_scanned= class right below, itself never covered by complete=), and files outside the indexed roots are outside the claim. It never appears on a regex answer (the prefilter is a performance switch that may not change the answer, so neither mode claims), a capped or paged listing, or a scan that could not read a file; its ABSENCE claims nothing. The enc rows' caller counts stay FLOORS regardless — complete= speaks for the hit rows alone. unindexed_files_scanned= counts files outside the index (unsupported-ext, but text-looking — the skipped verb's own unsupported-ext class) that THIS answer additionally scanned for the same pattern; their hits print inside a trailing unindexed element (present only when it found something), holding its own <f> rows in the same shape as above, and never carry in= — there is no symbol table to check for such a file, which is not the same claim as file scope. THE TWO POPULATIONS: every count above — files, hits, shown, capped, total, complete — is the IN-INDEX search ALONE. unindexed_hits= sizes the second one, always stated (a zero included); the trailing unindexed element carries that same number as its own count= beside shown=/capped= and obeys the SAME window limit/offset set here (dashes omitted), so a one-row page is one row on BOTH lists and a page past its end is empty, not repeated. unindexed_files_skipped= (present only when nonzero) counts candidates this scan saw but did not read: over the max-file-size ceiling, sniffed binary, or unreadable. unindexed_candidates_capped="1" (present only when true) means the CANDIDATE list itself (the skipped verb's own 500-row-per-class cap) was already a floor, so files past it were never considered here either — see the skipped verb for every row. corpus_excluded= counts files an exclude filter (or built-in crawl policy) kept OUT of the index entirely; corpus_oversize= counts files the crawl SAW but dropped for exceeding the size ceiling. Both answer what an otherwise-empty answer alone cannot: not in this repo, or in a file that was never scanned — the skipped verb itemizes the rows behind either count. next= is the one pasteable follow-up: the at verb on the top hit; the next page (compact legend) when cut; the conceptual lens on a zero-hit answer. raise the default cap with limit=N (offset=M pages; a cut listing carries total=/has_more=/next_offset= so a paging loop can continue from it); on the root, limit="0" means no explicit limit was given and the verb's own default page size shaped the window — never a zero-row page -->
<!-- ripwire grep handles: h= is sym#<stable-identity-hash>@<whole-file-content-hash>; the content half pins the exact file bytes scanned, so an edit after any file change refuses as stale. Only one editable enclosing definition receives h=. handle_omitted=ambiguous means the name grouped several definitions; non-code means a document/data section has no safe definition span; unreadable means no content hash could be proven. -->
<grep pattern="DEGRADED_PATH_ALERT" root="." files="66" hits="231" shown="100" capped="1" total="231" has_more="1" next_offset="100" offset="0" limit="0" hits_capped="0" suppressed_comment="101" suppressed_string="33" tier_parsed="95" corpus_oversize="15" unindexed_hits="29" unindexed_files_scanned= … [line truncated: 98 more bytes on this line]
<f p="src/abicheck.h" parse_degraded="1">
<hit l="482" in="abicheck::collectAuthoredSites">
<![CDATA[            DEGRADED_PATH_ALERT( "abi: no merge-base for a ref (unrelated history?) — that ref is counted, not compared" );]]>
</hit>
</f>
<f p="src/arch.h">
<hit l="353" in="rw::parseArchRules">
<![CDATA[        DEGRADED_PATH_ALERT( "arch: malformed rules line — rules file rejected" );]]>
</hit>
<hit l="408" in="rw::parseArchRules">
<![CDATA[                catch( const std::regex_error& ) { pr.bad = true; DEGRADED_PATH_ALERT( "arch: malformed FROM path-regex — rule skipped" ); }]]>
</hit>
</f>
<f p="src/atoms.h">
<hit l="365" in="atomdetail::collectExclusions">
<![CDATA[        DEGRADED_PATH_ALERT( "atoms: an exclusion capture stream spent its whole budget; the rules reading it are suppressed this run" );]]>
</hit>
</f>
<f p="src/clones.h">
<hit l="816" in="rw::findClonesType3">
<![CDATA[                if( comparedPairs >= kType3MaxPairs ) { DEGRADED_PATH_ALERT( "clones: Type-3 pair cap hit — first N compared (both-gate-surviving) near-misses kept, rest skipped" ); goto done; }]]>
</hit>
</f>
<f p="src/commentcoherence.h" parse_degraded="1">
<hit l="204" in="rw::computeCommentCoherence">
<![CDATA[                DEGRADED_PATH_ALERT( "comment-coherence: an indexed file could not be read — its functions are absent from the report" );]]>
</hit>
… [512 more display lines; full output is 36161 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --grep=DEGRADED_PATH_ALERT --legend=compact`

*The grep compact legend (ripwire.grep/v1).*

`````
<!-- ripwire grep ripwire.grep/v1: literal/regex scan grouped by file: <f p=>
<hit l= in=>CDATA text</hit> (<b>/<a> context around it); complete=1 only for an exhaustive literal scan; <unindexed> = off-index. window: shown= total= capped= has_more= next_offset= offset= limit= (capped=1 cut; next_offset= pastes as offset=). hits_capped=1: hits= is a floor. root=: p= relative t … [line truncated: 90 more bytes on this line]
<grep pattern="DEGRADED_PATH_ALERT" schema="ripwire.grep/v1" root="." files="66" hits="231" shown="100" capped="1" total="231" has_more="1" next_offset="100" offset="0" limit="0" hits_capped="0" suppressed_comment="101" suppressed_string="33" tier_parsed="95" corpus_oversize="15" unindexed_hits="29" … [line truncated: 123 more bytes on this line]
<f p="src/abicheck.h" parse_degraded="1">
<hit l="482" in="abicheck::collectAuthoredSites">
<![CDATA[            DEGRADED_PATH_ALERT( "abi: no merge-base for a ref (unrelated history?) — that ref is counted, not compared" );]]>
</hit>
</f>
<f p="src/arch.h">
<hit l="353" in="rw::parseArchRules">
<![CDATA[        DEGRADED_PATH_ALERT( "arch: malformed rules line — rules file rejected" );]]>
</hit>
<hit l="408" in="rw::parseArchRules">
<![CDATA[                catch( const std::regex_error& ) { pr.bad = true; DEGRADED_PATH_ALERT( "arch: malformed FROM path-regex — rule skipped" ); }]]>
</hit>
</f>
<f p="src/atoms.h">
<hit l="365" in="atomdetail::collectExclusions">
<![CDATA[        DEGRADED_PATH_ALERT( "atoms: an exclusion capture stream spent its whole budget; the rules reading it are suppressed this run" );]]>
</hit>
</f>
<f p="src/clones.h">
<hit l="816" in="rw::findClonesType3">
<![CDATA[                if( comparedPairs >= kType3MaxPairs ) { DEGRADED_PATH_ALERT( "clones: Type-3 pair cap hit — first N compared (both-gate-surviving) near-misses kept, rest skipped" ); goto done; }]]>
</hit>
</f>
<f p="src/commentcoherence.h" parse_degraded="1">
<hit l="204" in="rw::computeCommentCoherence">
<![CDATA[                DEGRADED_PATH_ALERT( "comment-coherence: an indexed file could not be read — its functions are absent from the report" );]]>
</hit>
… [512 more display lines; full output is 26704 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --for="tree-sitter parse of a source file" --legend=compact`

*The --for compact legend (ripwire.for/v1) — every data/completeness attribute kept.*

`````
<ctx task="tree-sitter parse of a source file" route="routed: subtoken+body BM25 (--for&apos;s default) — no strong name hit, multi-word conceptual query" root="." confidence="low" margin_pct="0" at="c7725f3ef" schema="ripwire.for/v1" bundle="compact" bodies="0" reason="compact-route" est_tokens=" … [line truncated: 6 more bytes on this line]
<!-- ripwire for ripwire.for/v1: task/route/root and bundle/bodies/reason are root facts; sigs and hops use total/requested, shown/printed and capped=1 for truncation; cx/ccx/in/churn/amp/clone/tested are the quality/reuse lens; calls are resolved callees and counts remain floors where stated [confidence=/margin_pct=: the ranked head's largest relative score drop; low = flat ranking, a starting point]; tail: file-grain tail (paths only, WEAKER than the ranked rows): <t p=> rows, total=/shown=/capped=1 when cut; r= = a ranked row's 1-based lens rank, rows in r= order, p= the file (a gap = a budget-trimmed row) -->
<!-- root= is the crawl root; p= below is RELATIVE to it (single-root only; absent => p= is ingest's own path, unchanged); at=this commit(+dirty). dropped_positive="10" est_tokens= prices this bundle in tokens -->
<sigs shown="30" total="40" capped="1">
<d l="40" n="kDefaultMaxFileBytes" id="src/ingest.h::rw::kDefaultMaxFileBytes" p="src/ingest.h" cx="0" ccx="0" in="0" churn="25" amp="74" pure="1" r="1" next="--expand=src/ingest.h:kDefaultMaxFileBytes">
<doc>The crawl&apos;s per-file byte ceiling. A text file larger than this is skipped: at this size it is o…</doc>constexpr std::size_t kDefaultMaxFileBytes = 4u * 1024u * 1024u</d>
<d l="1064" n="parseTree" p="src/ingest_sidecap.h" cx="1" ccx="0" in="1" churn="3" amp="37" tested="1" r="2">TSTree* parseTree( TSParser* parser, std::string_view src )</d>
<d l="185" n="doctorProbeGrammars" p="src/verbs_doctor.h" cx="7" ccx="17" in="1" churn="6" amp="36" r="3">inline DoctorGrammarProbe doctorProbeGrammars()</d>
<d l="789" n="FileHealth" id="src/model.h::FileHealth::FileHealth" p="src/model.h" cx="0" ccx="0" in="0" churn="57" amp="156" r="4">
<doc>errNodes/errBytes are a PARSER-STATE fact, never a syntax verdict: tree-sitter error recovery fi…</doc>struct FileHealth</d>
<d l="314" n="AstWalk" id="src/ingest.h::rw::AstWalk" p="src/ingest.h" cx="0" ccx="0" in="0" churn="25" amp="74" r="5">enum class AstWalk : std::uint8_t</d>
<d l="1778" n="collectGatedLocalNames" id="src/ingest_astquery.h::rw::collectGatedLocalNames" p="src/ingest_astquery.h" cx="7" ccx="6" in="1" churn="5" amp="43" r="6">std::vector&lt;LocalNameFact&gt; collectGatedLocalNames( std::string_view defBytes, std::uint32_t defStartLine, Lang lang )</d>
<d l="230" n="indexCommittish" id="src/mergescout.h::mergescout::indexCommittish" p="src/mergescout.h" cx="5" ccx="4" in="1" churn="14" amp="46" r="7">inline SymTreeIndex indexCommittish( const std::string&amp; root, const std::string&amp; committish, const std::vector&lt;std::string&gt;&amp; exclud … [line truncated: 36 more bytes on this line]
<d l="191" n="hasPhantomScopeSeparator" p="src/ingest_names.h" cx="2" ccx="1" in="1" churn="3" amp="31" tested="1" r="8">inline bool hasPhantomScopeSeparator( TSNode qualified ) noexcept</d>
<d l="681" n="builtInLintCaptures" p="src/verbs_lint.h" cx="1" ccx="0" in="1" churn="8" amp="34" r="9">std::vector&lt;std::vector&lt;rw::AstMatch&gt;&gt; builtInLintCaptures( const rw::IngestResult&amp; ing, const std::vector&lt;rw::AstQuerySpec&gt;&amp; checks, std::vector&lt;std::string&gt;&amp;  … [line truncated: 7 more bytes on this line]
<d l="1976" n="sliceScanDefinition" id="src/slice.h::slicev::sliceScanDefinition" p="src/slice.h" cx="10" ccx="9" in="3" churn="24" amp="36" r="10">inline SliceScan sliceScanDefinition( const std::string&amp; src, const Symbol&amp; sym, SliceFam fam, const ::TSLanguage* grammar, std::string_view var … [line truncated: 10 more bytes on this line]
<d l="1481" n="spanTiersOfFiles" id="src/ingest_astquery.h::rw::spanTiersOfFiles" p="src/ingest_astquery.h" cx="27" ccx="52" in="1" churn="5" amp="43" r="11">SpanTierBatch spanTiersOfFiles( std::span&lt;const std::string&gt; diskPaths, bool useMemo )</d>
<d l="478" n="jsonNestsTooDeep" p="src/ingest_crawl.h" cx="13" ccx="20" in="1" churn="6" amp="44" tested="1" r="12">bool jsonNestsTooDeep( std::string_view bytes ) noexcept</d>
<d l="99" n="kMaxYamlNestDepth" id="src/ingest.h::rw::kMaxYamlNestDepth" p="src/ingest.h" cx="0" ccx="0" in="0" churn="25" amp="74" pure="1" r="13">constexpr std::uint32_t kMaxYamlNestDepth = 64u</d>
<d l="40" n="LintRule" id="src/lintrules.h::LintRule::LintRule" p="src/lintrules.h" cx="0" ccx="0" in="0" churn="12" amp="46" r="14">struct LintRule</d>
<d l="60" n="kLangTable" p="src/ingest_crawl.h" cx="0" ccx="0" in="0" churn="6" amp="43" pure="1" r="15">constexpr std::array&lt;LangEntry, 40&gt; kLangTable =</d>
<d l="280" n="AstQuerySpec" id="src/ingest.h::AstQuerySpec::AstQuerySpec" p="src/ingest.h" cx="0" ccx="0" in="0" churn="25" amp="74" r="16">struct AstQuerySpec</d>
<d l="1468" n="spanTierMemoTryLoad" id="src/ingest_astquery.h::rw::spanTierMemoTryLoad" p="src/ingest_astquery.h" cx="3" ccx="1" in="1" churn="5" amp="43" r="17">inline bool spanTierMemoTryLoad( bool useMemo, const std::string&amp; diskPath, const StatInfo&amp; now, SpanTierMap&amp; out )</d>
<d l="462" n="SpanTier" id="src/ingest.h::rw::SpanTier" p="src/ingest.h" cx="0" ccx="0" in="1" churn="25" amp="75" r="18">enum class SpanTier : std::uint8_t</d>
<d l="516" n="McpIndex" id="src/mcpindex.h::McpIndex::McpIndex" p="src/mcpindex.h" cx="0" ccx="0" in="0" churn="20" amp="41" r="19">struct McpIndex</d>
<d l="239" n="runParseWorker" p="src/ingest_parsepool.h" cx="49" ccx="107" in="1" churn="3" amp="12" tested="1" r="20">inline void runParseWorker( ParsePoolShared&amp; sh, unsigned t )</d>
<d l="218" n="cc_declHasStructuredBinding" p="src/ingest_metrics.h" cx="5" ccx="6" in="1" churn="2" amp="27" tested="1" r="21">inline bool cc_declHasStructuredBinding( TSNode n, int depth ) noexcept</d>
<d l="107" n="tryParsePredicateOnAll" id="src/query.h::query::tryParsePredicateOnAll" p="src/query.h" cx="1" ccx="0" in="0" churn="10" amp="40" r="22">bool tryParsePredicateOnAll( Eval&amp; e, std::function&lt;std::vector&lt;NodeId&gt;( std::vector&lt;NodeId&gt; )&gt;&amp; apply )</d>
<d l="1298" n="kSpanTierMemoMinBytes" id="src/ingest_astquery.h::rw::kSpanTierMemoMinBytes" p="src/ingest_astquery.h" cx="0" ccx="0" in="0" churn="5" amp="42" pure="1" r="23">constexpr long long kSpanTierMemoMinBytes = 32ll &lt;&lt; 10</d>
<d l="935" n="ErrorMaskRule" id="src/lintrules.h::ErrorMaskRule::ErrorMaskRule" p="src/lintrules.h" cx="0" ccx="0" in="0" churn="12" amp="46" r="24">struct ErrorMaskRule</d>
… [63 more display lines; full output is 9524 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --for="tree-sitter parse of a source file" --auto-bodies`

*Opt OUT of compact conceptual serving: restore the rank-first auto <bodies> walk (bundle="auto").*

`````
<ctx task="tree-sitter parse of a source file" route="routed: subtoken+body BM25 (--for&apos;s default) — no strong name hit, multi-word conceptual query" root="." confidence="low" margin_pct="0" at="c7725f3ef" bundle="auto" bodies="4" est_tokens="5432">
<!-- ripwire lens for "tree-sitter parse of a source file" [confidence= derives from the ranked head's largest relative score drop (margin_pct=, whole percent, 0 = none; the same gap the adaptive flag cuts at). low = flat ranking: treat the set as a starting point, not an answer]: reusable building blocks + quality facts for what you're about to touch (cx=complexity ccx=cognitive in=reuse-count churn=recent-commits amp=change-amplification clone=1(duplicated) tested=1) — prefer composing/reusing these; watch the high-churn/high-amp/cloned ones; bundle=auto: the top-ranked FULL bodies ride inline after the signatures in a bodies section (bodies=N on this root counts them; bodies=0 reason=budget when none fit the remaining budget whole; the signatures-only flag (no-bodies mode) opts out) — read them here instead of opening the files. The bodies element discloses the house way: total=requested, shown=printed, capped=1 when they differ; each body's calls child lists its callee signatures, total= always, shown=/capped= only when that list is cut; tail: file-grain tail, WEAKER evidence than the ranked rows (paths only): the remaining candidate files with a positive score, best-symbol rank order; rows are t p=file; total=candidate files, shown=printed, capped=1 when they differ. r= on a ranked row is its 1-based rank in this lens ranking, rows in r= order, p= the file (a gap = a budget-trimmed row) -->
<!-- root= is the crawl root; p= below is RELATIVE to it (single-root only; absent => p= is ingest's own path, unchanged); at=this commit(+dirty). dropped_positive="12" est_tokens= prices this bundle in tokens -->
<sigs shown="28" total="40" capped="1">
<d l="40" n="kDefaultMaxFileBytes" id="src/ingest.h::rw::kDefaultMaxFileBytes" p="src/ingest.h" cx="0" ccx="0" in="0" churn="25" amp="74" pure="1" r="1" next="--expand=src/ingest.h:kDefaultMaxFileBytes">
<doc>The crawl&apos;s per-file byte ceiling. A text file larger than this is skipped: at this size it is o…</doc>constexpr std::size_t kDefaultMaxFileBytes = 4u * 1024u * 1024u</d>
<d l="1064" n="parseTree" p="src/ingest_sidecap.h" cx="1" ccx="0" in="1" churn="3" amp="37" tested="1" r="2">TSTree* parseTree( TSParser* parser, std::string_view src )</d>
<d l="185" n="doctorProbeGrammars" p="src/verbs_doctor.h" cx="7" ccx="17" in="1" churn="6" amp="36" r="3">inline DoctorGrammarProbe doctorProbeGrammars()</d>
<d l="789" n="FileHealth" id="src/model.h::FileHealth::FileHealth" p="src/model.h" cx="0" ccx="0" in="0" churn="57" amp="156" r="4">
<doc>errNodes/errBytes are a PARSER-STATE fact, never a syntax verdict: tree-sitter error recovery fi…</doc>struct FileHealth</d>
<d l="314" n="AstWalk" id="src/ingest.h::rw::AstWalk" p="src/ingest.h" cx="0" ccx="0" in="0" churn="25" amp="74" r="5">enum class AstWalk : std::uint8_t</d>
<d l="1778" n="collectGatedLocalNames" id="src/ingest_astquery.h::rw::collectGatedLocalNames" p="src/ingest_astquery.h" cx="7" ccx="6" in="1" churn="5" amp="43" r="6">std::vector&lt;LocalNameFact&gt; collectGatedLocalNames( std::string_view defBytes, std::uint32_t defStartLine, Lang lang )</d>
<d l="230" n="indexCommittish" id="src/mergescout.h::mergescout::indexCommittish" p="src/mergescout.h" cx="5" ccx="4" in="1" churn="14" amp="46" r="7">inline SymTreeIndex indexCommittish( const std::string&amp; root, const std::string&amp; committish, const std::vector&lt;std::string&gt;&amp; exclud … [line truncated: 36 more bytes on this line]
<d l="191" n="hasPhantomScopeSeparator" p="src/ingest_names.h" cx="2" ccx="1" in="1" churn="3" amp="31" tested="1" r="8">inline bool hasPhantomScopeSeparator( TSNode qualified ) noexcept</d>
<d l="681" n="builtInLintCaptures" p="src/verbs_lint.h" cx="1" ccx="0" in="1" churn="8" amp="34" r="9">std::vector&lt;std::vector&lt;rw::AstMatch&gt;&gt; builtInLintCaptures( const rw::IngestResult&amp; ing, const std::vector&lt;rw::AstQuerySpec&gt;&amp; checks, std::vector&lt;std::string&gt;&amp;  … [line truncated: 7 more bytes on this line]
<d l="1976" n="sliceScanDefinition" id="src/slice.h::slicev::sliceScanDefinition" p="src/slice.h" cx="10" ccx="9" in="3" churn="24" amp="36" r="10">inline SliceScan sliceScanDefinition( const std::string&amp; src, const Symbol&amp; sym, SliceFam fam, const ::TSLanguage* grammar, std::string_view var … [line truncated: 10 more bytes on this line]
<d l="1481" n="spanTiersOfFiles" id="src/ingest_astquery.h::rw::spanTiersOfFiles" p="src/ingest_astquery.h" cx="27" ccx="52" in="1" churn="5" amp="43" r="11">SpanTierBatch spanTiersOfFiles( std::span&lt;const std::string&gt; diskPaths, bool useMemo )</d>
<d l="478" n="jsonNestsTooDeep" p="src/ingest_crawl.h" cx="13" ccx="20" in="1" churn="6" amp="44" tested="1" r="12">bool jsonNestsTooDeep( std::string_view bytes ) noexcept</d>
<d l="99" n="kMaxYamlNestDepth" id="src/ingest.h::rw::kMaxYamlNestDepth" p="src/ingest.h" cx="0" ccx="0" in="0" churn="25" amp="74" pure="1" r="13">constexpr std::uint32_t kMaxYamlNestDepth = 64u</d>
<d l="40" n="LintRule" id="src/lintrules.h::LintRule::LintRule" p="src/lintrules.h" cx="0" ccx="0" in="0" churn="12" amp="46" r="14">struct LintRule</d>
<d l="60" n="kLangTable" p="src/ingest_crawl.h" cx="0" ccx="0" in="0" churn="6" amp="43" pure="1" r="15">constexpr std::array&lt;LangEntry, 40&gt; kLangTable =</d>
<d l="280" n="AstQuerySpec" id="src/ingest.h::AstQuerySpec::AstQuerySpec" p="src/ingest.h" cx="0" ccx="0" in="0" churn="25" amp="74" r="16">struct AstQuerySpec</d>
<d l="1468" n="spanTierMemoTryLoad" id="src/ingest_astquery.h::rw::spanTierMemoTryLoad" p="src/ingest_astquery.h" cx="3" ccx="1" in="1" churn="5" amp="43" r="17">inline bool spanTierMemoTryLoad( bool useMemo, const std::string&amp; diskPath, const StatInfo&amp; now, SpanTierMap&amp; out )</d>
<d l="462" n="SpanTier" id="src/ingest.h::rw::SpanTier" p="src/ingest.h" cx="0" ccx="0" in="1" churn="25" amp="75" r="18">enum class SpanTier : std::uint8_t</d>
<d l="516" n="McpIndex" id="src/mcpindex.h::McpIndex::McpIndex" p="src/mcpindex.h" cx="0" ccx="0" in="0" churn="20" amp="41" r="19">struct McpIndex</d>
<d l="239" n="runParseWorker" p="src/ingest_parsepool.h" cx="49" ccx="107" in="1" churn="3" amp="12" tested="1" r="20">inline void runParseWorker( ParsePoolShared&amp; sh, unsigned t )</d>
<d l="218" n="cc_declHasStructuredBinding" p="src/ingest_metrics.h" cx="5" ccx="6" in="1" churn="2" amp="27" tested="1" r="21">inline bool cc_declHasStructuredBinding( TSNode n, int depth ) noexcept</d>
<d l="107" n="tryParsePredicateOnAll" id="src/query.h::query::tryParsePredicateOnAll" p="src/query.h" cx="1" ccx="0" in="0" churn="10" amp="40" r="22">bool tryParsePredicateOnAll( Eval&amp; e, std::function&lt;std::vector&lt;NodeId&gt;( std::vector&lt;NodeId&gt; )&gt;&amp; apply )</d>
<d l="1298" n="kSpanTierMemoMinBytes" id="src/ingest_astquery.h::rw::kSpanTierMemoMinBytes" p="src/ingest_astquery.h" cx="0" ccx="0" in="0" churn="5" amp="42" pure="1" r="23">constexpr long long kSpanTierMemoMinBytes = 32ll &lt;&lt; 10</d>
<d l="935" n="ErrorMaskRule" id="src/lintrules.h::ErrorMaskRule::ErrorMaskRule" p="src/lintrules.h" cx="0" ccx="0" in="0" churn="12" amp="46" r="24">struct ErrorMaskRule</d>
… [150 more display lines; full output is 15797 bytes on 105 raw line(s)]
`````

## `./build/ripwire . --for="quality delta acks ledger rubber stamp"`

*Doc-mention surfacing (default ON): a markdown doc naming a top-resolved symbol in a backtick rides in below that symbol — the legend's [doc mentions: …] clause says it fired.*

`````
<ctx task="quality delta acks ledger rubber stamp" route="routed: subtoken+body BM25 (--for&apos;s default) — no strong name hit, multi-word conceptual query" root="." confidence="low" margin_pct="0" at="c7725f3ef" doc_mentions="1" bundle="compact" bodies="0" reason="compact-route" est_tokens="391 … [line truncated: 3 more bytes on this line]
<!-- ripwire lens for "quality delta acks ledger rubber stamp" [doc mentions: 1 doc discussing 1 top-ranked symbol surfaced; doc_mentions= on the root repeats the doc count] [confidence= derives from the ranked head's largest relative score drop (margin_pct=, whole percent, 0 = none; the same gap the adaptive flag cuts at). low = flat ranking: treat the set as a starting point, not an answer]: reusable building blocks + quality facts for what you're about to touch (cx=complexity ccx=cognitive in=reuse-count churn=recent-commits amp=change-amplification clone=1(duplicated) tested=1) — prefer composing/reusing these; watch the high-churn/high-amp/cloned ones; bundle=compact: conceptual query, so this map ships one-hop EDGE context, no bodies (bodies=0, reason=compact-route or no_candidates). hops rows are h l=line p=file n=name, and a row's calls child names its callees (c n= l=). hops and calls disclose total=requested shown=printed capped=1 when the BUDGET cut a listing; noedge=N counts ranked symbols with no RESOLVED callee found (never none exists). For a body: expand=p:n pasted off a row; the auto-bodies flag puts the bodies back; tail: file-grain tail, WEAKER evidence than the ranked rows (paths only): the remaining candidate files with a positive score, best-symbol rank order; rows are t p=file; total=candidate files, shown=printed, capped=1 when they differ. r= on a ranked row is its 1-based rank in this lens ranking, rows in r= order, p= the file (a gap = a budget-trimmed row) -->
<!-- root= is the crawl root; p= below is RELATIVE to it (single-root only; absent => p= is ingest's own path, unchanged); at=this commit(+dirty). dropped_positive="16" est_tokens= prices this bundle in tokens -->
<sigs shown="24" total="40" capped="1">
<d l="3019" n="computeQualityDelta" id="src/mcpverbs.h::rw::computeQualityDelta" p="src/mcpverbs.h" cx="5" ccx="7" in="1" churn="117" amp="245" r="1" next="--expand=src/mcpverbs.h:computeQualityDelta">inline QualityDeltaOutcome computeQualityDelta( const std::string&amp; root )</d>
<d l="401" n="refuseForeignAckSelection" p="src/verbs_quality.h" cx="9" ccx="12" in="1" churn="26" amp="90" r="2">std::optional&lt;int&gt; refuseForeignAckSelection( const rw::Config&amp; cfg, const rw::quality::Scope&amp; scope, const std::vector&lt;rw::quality::Regression&gt;&amp; outOfScope, st … [line truncated: 7 more bytes on this line]
<d l="940" n="runQualityDelta" p="src/verbs_quality.h" cx="103" ccx="259" in="1" churn="26" amp="90" r="3">
<doc>runQualityViews was NOT a dispatch chain — it held two branches, one of which was 298 lines. T…</doc>std::optional&lt;int&gt; runQualityDelta( const MainDispatch&amp; d )</d>
<d l="147" n="DeltaBasis" id="src/verbs_quality.h::DeltaBasis::DeltaBasis" p="src/verbs_quality.h" cx="0" ccx="0" in="0" churn="26" amp="89" r="4">
<doc>WHAT this delta is measured AGAINST, and on WHICH tree — the one place --quality-delta decides…</doc>struct DeltaBasis</d>
<d l="812" n="ackNothingToAccept" p="src/verbs_quality.h" cx="6" ccx="7" in="1" churn="26" amp="90" r="5">int ackNothingToAccept( const std::string&amp; acksFile, const gtl::btree_map&lt;std::string, rw::quality::AckRecord&gt;&amp; acks, const rw::quality::Scope&amp; scope, std::size…</d>
<d l="96" n="kAcksFile" id="src/quality.h::quality::kAcksFile" p="src/quality.h" cx="0" ccx="0" in="0" churn="106" amp="244" r="6">inline const char* kAcksFile = &quot;.ripwire_quality_acks&quot;</d>
<d l="3106" n="qualityDeltaJson" id="src/mcpverbs.h::rw::qualityDeltaJson" p="src/mcpverbs.h" cx="20" ccx="33" in="1" churn="117" amp="245" r="7">inline std::string qualityDeltaJson( const std::string&amp; root, std::string&amp; errOut )</d>
<d l="864" n="inspectDirtyBaselinePin" p="src/verbs_quality.h" cx="6" ccx="7" in="1" churn="26" amp="90" r="8">DirtyPinVerdict inspectDirtyBaselinePin( const MainDispatch&amp; d, const std::string&amp; acksFile )</d>
<d l="4691" n="IdentityHealing" id="src/quality.h::IdentityHealing::IdentityHealing" p="src/quality.h" cx="0" ccx="0" in="0" churn="106" amp="244" r="9">struct IdentityHealing</d>
<d l="5132" n="staleAcksXml" id="src/quality.h::quality::staleAcksXml" p="src/quality.h" cx="5" ccx="8" in="1" churn="106" amp="245" r="10">inline std::string staleAcksXml( const std::vector&lt;StaleAck&gt;&amp; staleAcks, EscapeFn esc )</d>
<d l="2965" n="QualityDeltaOutcome" id="src/mcpverbs.h::QualityDeltaOutcome::QualityDeltaOutcome" p="src/mcpverbs.h" cx="0" ccx="0" in="0" churn="117" amp="244" r="11">struct QualityDeltaOutcome</d>
<d l="164" n="resolveDeltaBasis" p="src/verbs_quality.h" cx="6" ccx="8" in="1" churn="26" amp="90" r="12">std::optional&lt;int&gt; resolveDeltaBasis( const MainDispatch&amp; d, const std::string&amp; baselineFile, RefPairDelta&amp; refs, DeltaBasis&amp; out )</d>
<d l="2252" n="atomicWriteFile" id="src/quality.h::quality::atomicWriteFile" p="src/quality.h" cx="4" ccx="3" in="4" churn="106" amp="248" r="13">inline bool atomicWriteFile( const std::string&amp; path, const std::string&amp; blob )</d>
<d l="4275" n="writeAckRecords" id="src/quality.h::quality::writeAckRecords" p="src/quality.h" cx="2" ccx="1" in="2" churn="106" amp="246" r="14">inline bool writeAckRecords( const std::string&amp; path, const gtl::btree_map&lt;std::string, AckRecord&gt;&amp; acks )</d>
<d l="4244" n="renderAckRecords" id="src/quality.h::quality::renderAckRecords" p="src/quality.h" cx="5" ccx="7" in="2" churn="106" amp="246" r="15">inline std::string renderAckRecords( const gtl::btree_map&lt;std::string, AckRecord&gt;&amp; acks )</d>
<d l="1511" n="kAtStampLegend" id="src/serialize.h::rw::kAtStampLegend" p="src/serialize.h" cx="0" ccx="0" in="0" churn="99" amp="246" pure="1" r="16">inline constexpr const char* kAtStampLegend = &quot;&lt;!-- at= is the git commit these numbers were computed at</d>
<d l="2960" n="qualityAcksPath" id="src/mcpverbs.h::rw::qualityAcksPath" p="src/mcpverbs.h" cx="1" ccx="0" in="1" churn="117" amp="245" r="17">inline std::string qualityAcksPath( const std::string&amp; root )</d>
<d l="1176" n="gitHeadSha" id="src/quality.h::quality::gitHeadSha" p="src/quality.h" cx="1" ccx="0" in="15" churn="106" amp="259" r="18">inline std::string gitHeadSha( const std::string&amp; root )</d>
<d l="903" n="runQualityBaselinePin" p="src/verbs_quality.h" cx="7" ccx="6" in="1" churn="26" amp="90" r="19">int runQualityBaselinePin( const MainDispatch&amp; d, const std::string&amp; baselineFile, const std::string&amp; acksFile )</d>
<d l="283" n="computeDmm" id="src/dmm.h::rw::dmm::computeDmm" p="src/dmm.h" cx="9" ccx="6" in="1" churn="6" amp="27" r="20">inline Result computeDmm( const std::string&amp; root, std::string_view spec, const IngestResult&amp; workingIng, const std::vector&lt;std::string&gt;&amp; excludes, std::size_ … [line truncated: 20 more bytes on this line]
<d l="2959" n="qualityBaselinePath" id="src/mcpverbs.h::rw::qualityBaselinePath" p="src/mcpverbs.h" cx="1" ccx="0" in="2" churn="117" amp="246" r="21">inline std::string qualityBaselinePath( const std::string&amp; root )</d>
<d l="667" n="QualityDeltaLegendParts" id="src/verbs_quality.h::QualityDeltaLegendParts::QualityDeltaLegendParts" p="src/verbs_quality.h" cx="0" ccx="0" in="0" churn="26" amp="89" r="22">struct QualityDeltaLegendParts</d>
<d l="579" n="kQdSchemeLegend" p="src/verbs_quality.h" cx="0" ccx="0" in="0" churn="26" amp="89" pure="1" r="23">inline constexpr const char* kQdSchemeLegend = &quot;A THIRD re-filing, git-independent: on 2026-08-25 the per-symbol quality key stopped being a &quot; &quot;canonical-id hash (which deg … [line truncated: 72 more bytes on this line]
<d l="634" n="kScopeLegend" p="src/verbs_quality.h" cx="0" ccx="0" in="0" churn="26" amp="89" pure="1" r="24">inline constexpr const char* kScopeLegend = &quot;SCOPE, present only when the scope flag was given, and it NARROWS WHAT THIS REPORT &quot; &quot;CLAIMS: scope= is the pattern list it was gi … [line truncated: 79 more bytes on this line]
… [51 more display lines; full output is 9775 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --for="quality delta acks ledger rubber stamp" --no-doc-mention`

*The same task with doc-mention surfacing OFF — the contrast the flag exists for (no [doc mentions] clause, one fewer row).*

`````
<ctx task="quality delta acks ledger rubber stamp" route="routed: subtoken+body BM25 (--for&apos;s default) — no strong name hit, multi-word conceptual query" root="." confidence="low" margin_pct="0" at="c7725f3ef" bundle="compact" bodies="0" reason="compact-route" est_tokens="3948">
<!-- ripwire lens for "quality delta acks ledger rubber stamp" [confidence= derives from the ranked head's largest relative score drop (margin_pct=, whole percent, 0 = none; the same gap the adaptive flag cuts at). low = flat ranking: treat the set as a starting point, not an answer]: reusable building blocks + quality facts for what you're about to touch (cx=complexity ccx=cognitive in=reuse-count churn=recent-commits amp=change-amplification clone=1(duplicated) tested=1) — prefer composing/reusing these; watch the high-churn/high-amp/cloned ones; bundle=compact: conceptual query, so this map ships one-hop EDGE context, no bodies (bodies=0, reason=compact-route or no_candidates). hops rows are h l=line p=file n=name, and a row's calls child names its callees (c n= l=). hops and calls disclose total=requested shown=printed capped=1 when the BUDGET cut a listing; noedge=N counts ranked symbols with no RESOLVED callee found (never none exists). For a body: expand=p:n pasted off a row; the auto-bodies flag puts the bodies back; tail: file-grain tail, WEAKER evidence than the ranked rows (paths only): the remaining candidate files with a positive score, best-symbol rank order; rows are t p=file; total=candidate files, shown=printed, capped=1 when they differ. r= on a ranked row is its 1-based rank in this lens ranking, rows in r= order, p= the file (a gap = a budget-trimmed row) -->
<!-- root= is the crawl root; p= below is RELATIVE to it (single-root only; absent => p= is ingest's own path, unchanged); at=this commit(+dirty). dropped_positive="15" est_tokens= prices this bundle in tokens -->
<sigs shown="25" total="40" capped="1">
<d l="3019" n="computeQualityDelta" id="src/mcpverbs.h::rw::computeQualityDelta" p="src/mcpverbs.h" cx="5" ccx="7" in="1" churn="117" amp="245" r="1" next="--expand=src/mcpverbs.h:computeQualityDelta">inline QualityDeltaOutcome computeQualityDelta( const std::string&amp; root )</d>
<d l="401" n="refuseForeignAckSelection" p="src/verbs_quality.h" cx="9" ccx="12" in="1" churn="26" amp="90" r="2">std::optional&lt;int&gt; refuseForeignAckSelection( const rw::Config&amp; cfg, const rw::quality::Scope&amp; scope, const std::vector&lt;rw::quality::Regression&gt;&amp; outOfScope, st … [line truncated: 7 more bytes on this line]
<d l="940" n="runQualityDelta" p="src/verbs_quality.h" cx="103" ccx="259" in="1" churn="26" amp="90" r="3">
<doc>runQualityViews was NOT a dispatch chain — it held two branches, one of which was 298 lines. T…</doc>std::optional&lt;int&gt; runQualityDelta( const MainDispatch&amp; d )</d>
<d l="147" n="DeltaBasis" id="src/verbs_quality.h::DeltaBasis::DeltaBasis" p="src/verbs_quality.h" cx="0" ccx="0" in="0" churn="26" amp="89" r="4">
<doc>WHAT this delta is measured AGAINST, and on WHICH tree — the one place --quality-delta decides…</doc>struct DeltaBasis</d>
<d l="812" n="ackNothingToAccept" p="src/verbs_quality.h" cx="6" ccx="7" in="1" churn="26" amp="90" r="5">int ackNothingToAccept( const std::string&amp; acksFile, const gtl::btree_map&lt;std::string, rw::quality::AckRecord&gt;&amp; acks, const rw::quality::Scope&amp; scope, std::size…</d>
<d l="96" n="kAcksFile" id="src/quality.h::quality::kAcksFile" p="src/quality.h" cx="0" ccx="0" in="0" churn="106" amp="244" r="6">inline const char* kAcksFile = &quot;.ripwire_quality_acks&quot;</d>
<d l="3106" n="qualityDeltaJson" id="src/mcpverbs.h::rw::qualityDeltaJson" p="src/mcpverbs.h" cx="20" ccx="33" in="1" churn="117" amp="245" r="7">inline std::string qualityDeltaJson( const std::string&amp; root, std::string&amp; errOut )</d>
<d l="864" n="inspectDirtyBaselinePin" p="src/verbs_quality.h" cx="6" ccx="7" in="1" churn="26" amp="90" r="8">DirtyPinVerdict inspectDirtyBaselinePin( const MainDispatch&amp; d, const std::string&amp; acksFile )</d>
<d l="4691" n="IdentityHealing" id="src/quality.h::IdentityHealing::IdentityHealing" p="src/quality.h" cx="0" ccx="0" in="0" churn="106" amp="244" r="9">struct IdentityHealing</d>
<d l="5132" n="staleAcksXml" id="src/quality.h::quality::staleAcksXml" p="src/quality.h" cx="5" ccx="8" in="1" churn="106" amp="245" r="10">inline std::string staleAcksXml( const std::vector&lt;StaleAck&gt;&amp; staleAcks, EscapeFn esc )</d>
<d l="2965" n="QualityDeltaOutcome" id="src/mcpverbs.h::QualityDeltaOutcome::QualityDeltaOutcome" p="src/mcpverbs.h" cx="0" ccx="0" in="0" churn="117" amp="244" r="11">struct QualityDeltaOutcome</d>
<d l="164" n="resolveDeltaBasis" p="src/verbs_quality.h" cx="6" ccx="8" in="1" churn="26" amp="90" r="12">std::optional&lt;int&gt; resolveDeltaBasis( const MainDispatch&amp; d, const std::string&amp; baselineFile, RefPairDelta&amp; refs, DeltaBasis&amp; out )</d>
<d l="2252" n="atomicWriteFile" id="src/quality.h::quality::atomicWriteFile" p="src/quality.h" cx="4" ccx="3" in="4" churn="106" amp="248" r="13">inline bool atomicWriteFile( const std::string&amp; path, const std::string&amp; blob )</d>
<d l="4275" n="writeAckRecords" id="src/quality.h::quality::writeAckRecords" p="src/quality.h" cx="2" ccx="1" in="2" churn="106" amp="246" r="14">inline bool writeAckRecords( const std::string&amp; path, const gtl::btree_map&lt;std::string, AckRecord&gt;&amp; acks )</d>
<d l="4244" n="renderAckRecords" id="src/quality.h::quality::renderAckRecords" p="src/quality.h" cx="5" ccx="7" in="2" churn="106" amp="246" r="15">inline std::string renderAckRecords( const gtl::btree_map&lt;std::string, AckRecord&gt;&amp; acks )</d>
<d l="1511" n="kAtStampLegend" id="src/serialize.h::rw::kAtStampLegend" p="src/serialize.h" cx="0" ccx="0" in="0" churn="99" amp="246" pure="1" r="16">inline constexpr const char* kAtStampLegend = &quot;&lt;!-- at= is the git commit these numbers were computed at</d>
<d l="2960" n="qualityAcksPath" id="src/mcpverbs.h::rw::qualityAcksPath" p="src/mcpverbs.h" cx="1" ccx="0" in="1" churn="117" amp="245" r="17">inline std::string qualityAcksPath( const std::string&amp; root )</d>
<d l="1176" n="gitHeadSha" id="src/quality.h::quality::gitHeadSha" p="src/quality.h" cx="1" ccx="0" in="15" churn="106" amp="259" r="18">inline std::string gitHeadSha( const std::string&amp; root )</d>
<d l="903" n="runQualityBaselinePin" p="src/verbs_quality.h" cx="7" ccx="6" in="1" churn="26" amp="90" r="19">int runQualityBaselinePin( const MainDispatch&amp; d, const std::string&amp; baselineFile, const std::string&amp; acksFile )</d>
<d l="283" n="computeDmm" id="src/dmm.h::rw::dmm::computeDmm" p="src/dmm.h" cx="9" ccx="6" in="1" churn="6" amp="27" r="20">inline Result computeDmm( const std::string&amp; root, std::string_view spec, const IngestResult&amp; workingIng, const std::vector&lt;std::string&gt;&amp; excludes, std::size_ … [line truncated: 20 more bytes on this line]
<d l="2959" n="qualityBaselinePath" id="src/mcpverbs.h::rw::qualityBaselinePath" p="src/mcpverbs.h" cx="1" ccx="0" in="2" churn="117" amp="246" r="21">inline std::string qualityBaselinePath( const std::string&amp; root )</d>
<d l="667" n="QualityDeltaLegendParts" id="src/verbs_quality.h::QualityDeltaLegendParts::QualityDeltaLegendParts" p="src/verbs_quality.h" cx="0" ccx="0" in="0" churn="26" amp="89" r="22">struct QualityDeltaLegendParts</d>
<d l="579" n="kQdSchemeLegend" p="src/verbs_quality.h" cx="0" ccx="0" in="0" churn="26" amp="89" pure="1" r="23">inline constexpr const char* kQdSchemeLegend = &quot;A THIRD re-filing, git-independent: on 2026-08-25 the per-symbol quality key stopped being a &quot; &quot;canonical-id hash (which deg … [line truncated: 72 more bytes on this line]
<d l="634" n="kScopeLegend" p="src/verbs_quality.h" cx="0" ccx="0" in="0" churn="26" amp="89" pure="1" r="24">inline constexpr const char* kScopeLegend = &quot;SCOPE, present only when the scope flag was given, and it NARROWS WHAT THIS REPORT &quot; &quot;CLAIMS: scope= is the pattern list it was gi … [line truncated: 79 more bytes on this line]
… [52 more display lines; full output is 9871 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --safe-delete=rankGraphTeleport`

*"Can I delete this?" — callers + transitive impact + every use site + how much of the radius is tested, composed in ONE call; risk= names what was found, never a verdict.*

`````
<!-- ripwire safe-delete: composes signals the tool already computes into one "can I delete this?" READ — never a verdict. defs= is resolveAllByNameQualified's match count, exactly as the impact/uses/callers verbs already disclose it. callers= is the 1-hop caller count (the callers verb's own walk over defs' in-edges); impact_reaches= is the FULL transitive blast radius (the impact verb's own walk); uses= is every read/write/import/call/extends SITE of the name (the uses verb's own walk), reference-name-based, so an overloaded name unions every definition's sites. All three are counts_floor= FLOORS, never totals — see COUNTING UNIT below. tested_self= is 1 when an indexed test transitively CALLS this symbol (the tested= lens; a test symbol itself is never counted, matching the metrics/for/exemplar verbs' rule), and radius_tested= plus radius_untested= partition impact_reaches= by that same lens — radius_untested= equal to impact_reaches= means NOTHING downstream is covered by an indexed test, the strongest signal here. dead_code_candidate= is 1 ONLY when this selector resolves to exactly ONE definition and it is the dead-code verb's own high-confidence shape (a source free function, non-header, internal/static linkage, zero direct callers); a 0 never means "in use", only that this narrow detector's preconditions do not hold here — run the dead-code verb for the full-corpus scan. ambiguous_callers= counts callers whose OWN outgoing calls include at least one that resolved to more than one candidate definition (g.ambOut, the same counter a ranked row's amb= reads). That is a caveat that one of the callers below MAY be reaching a different same-named definition, never proof that this one is (such a caller row carries amb=K, K its ambiguous calls, the map row's amb=); read the source if which-target matters. risk= NAMES what was found, never a go/no-go verdict, and this run reports untested-radius: callers or uses exist, and NONE of the transitive blast radius is test-covered. counts_floor="1" means every count here is a FLOOR, never a total: edges are extracted from source TEXT by NAME. Missing: dynamic dispatch (virtual/interface/duck-typed), a most-vexing-parse declaration with no call expression, a function-pointer/callback bound to more than one function in scope (reassigned, table-indexed, lambda-bound, or address-taken/reference-bound), and a plain-name binding (fp=handler) whose variable type is not PROVABLY a function pointer (a same-file typedef/declarator; a HEADER typedef is missed; auto/template types are read as unpinned, so KEPT). A macro-generated call site is role="macro" only when its name uniquely names an indexed function-like #define (C-family, t="macro"); a shared name stays a plain call, an unindexed macro is no edge. Read a zero as "none found", never as "none exists". graph_ambiguous=/graph_unresolved= are the whole graph's resolver gauge (calls split over several defs / calls whose in-repo defs were all language-filtered), the map header's ambiguous=/unresolved=. COUNTING UNIT differs by verb: callers, callees, edit-check, graph-query and pr-context counts are DISTINCT SYMBOLS (repeated calls from one caller, and calls to two overloads, collapse into ONE row; multiplicity survives only in the call graph's edge weight). The reach counts (impact's reaches=, pr-context's dependents=) are the size of a transitive reach SET, each symbol counted once. The uses verb counts call SITES, one row per occurrence — a larger count there for the same symbol is these units agreeing, not disagreeing. The map header's edges= is a unit again different — distinct (caller,callee) PAIRS — and that document carries neither this marker nor this clause. -->
<!-- root= on this element is the crawl root every p= below is RELATIVE to (single-root runs only; absent => p= is the path ingest itself used, unchanged). -->
<safe-delete sym="rankGraphTeleport" t="fn" p="src/graph.h:2501" defs="1" callers="6" ambiguous_callers="5" impact_reaches="63" uses="9" tested_self="0" radius_tested="0" radius_untested="63" dead_code_candidate="0" risk="untested-radius" shown="6" capped="0" graph_ambiguous="6085" graph_unresolved= … [line truncated: 33 more bytes on this line]
<c n="runEval" p="src/eval.h:168" amb="7"/>
<c n="rankGraph" p="src/graph.h:2542"/>
<c n="anchoredLexicalRank" p="src/graph.h:3034" amb="7"/>
<c n="churnRankedGraph" p="src/main.cpp:983" amb="4"/>
<c n="runDefaultMap" p="src/main.cpp:1098" amb="43"/>
<c n="getIndex" p="src/mcpindex.h:1104" amb="8"/>
</safe-delete>
`````

## `./build/ripwire . --safe-delete=DoesNotExist`

*Unknown-symbol refusal shape for --safe-delete.*

**exit code: 1**

`````
(empty)
`````

stderr:

`````
ripwire: --safe-delete symbol not found: DoesNotExist
`````

## `./build/ripwire . --handoff`

*The continuation packet for the NEXT session: <verified> disk truth (branch/sha, changed symbols, blast radius, tests) + <heuristic> labeled suggestions. Recorded against a CLEAN tree.*

`````
<!-- ripwire handoff: the continuation packet for the NEXT session. <verified> is disk truth (branch=/at=<sha>[+dirty]/subject=<commit subject text>, changed files+symbols via git numstat, blast_files=transitive dependent files, tests-to-run); run= is the command that discharges a test row; run_unknown="1" means none is derivable for that harness (a guess would be worse than none) — a row carries one or the other, never neither. <heuristic> is labeled non-verified suggestion (cochange=usually-edited-together deg=degree, note=committed .ripwire_notes row, doc=plan/design pointer s=lexical score for the branch+commit-subject query). branch= is git's own answer, so on a DETACHED head it reads HEAD and detached=1 says so (the commit is at=); detached= is absent when a branch is checked out. &lt;heuristic n= candidates= capped=&gt;: n= is the rows in the packet, candidates= how many the three classes produced before their own per-class caps (cochange 8, notes 8, docs 4), capped=1 when a cap dropped one — so candidates - n - withheld_rows is what the caps removed and nothing is lost silently. budget= is the token-budget cap; withheld=1 when heuristic rows were dropped to fit it, withheld_rows= how many (the map's spelling: a boolean, the count beside it) — verified rows are never dropped; est_tokens= prices the delivered packet in tokens and over_ceiling= is 1 when even the verified floor exceeds budget= (the packet is then complete, not trimmed). gitok=0 means the git diff probe failed and changed counts are floors. -->
<handoff at="c7725f3ef" root="." branch="integration/terminality-2026-09-05" subject="test(gates): N1 — shapingflagcheck&apos;s timeout budget back to 1200; compactlegendcheck stays at 900" gitok="1" est_tokens="1025">
<verified changed="0" blast_files="0">
<tests n="0">
</tests>
</verified>
<heuristic n="5" candidates="130" capped="1">
<note target="test/manifestcheck.sh" txt="README.md&apos;s single &apos;&lt;N&gt; gate scripts&apos; claim (~line 1305) is NOT enforced — the derived-vs-stated sibling loop here covers docs/EVALS.md only. It drifted 407→451 unnoticed (fixed 2026-08-23). To close: grep both files (&apos;file:line … [line truncated: 47 more bytes on this line]
<doc p="docs/SUBSTITUTION_METER.md" s="8.687"/>
<doc p="docs/EVALS.md" s="8.650"/>
<doc p="docs/METHODOLOGY.md" s="8.533"/>
<doc p="docs/CODEX_ORCHESTRATION.md" s="7.624"/>
</heuristic>
</handoff>
`````

## `./build/ripwire . --handoff --token-budget=1200`

*The same packet under a hard ceiling: heuristic rows drop tail-first (withheld= disclosed), verified rows never drop.*

`````
<!-- ripwire handoff: the continuation packet for the NEXT session. <verified> is disk truth (branch=/at=<sha>[+dirty]/subject=<commit subject text>, changed files+symbols via git numstat, blast_files=transitive dependent files, tests-to-run); run= is the command that discharges a test row; run_unknown="1" means none is derivable for that harness (a guess would be worse than none) — a row carries one or the other, never neither. <heuristic> is labeled non-verified suggestion (cochange=usually-edited-together deg=degree, note=committed .ripwire_notes row, doc=plan/design pointer s=lexical score for the branch+commit-subject query). branch= is git's own answer, so on a DETACHED head it reads HEAD and detached=1 says so (the commit is at=); detached= is absent when a branch is checked out. &lt;heuristic n= candidates= capped=&gt;: n= is the rows in the packet, candidates= how many the three classes produced before their own per-class caps (cochange 8, notes 8, docs 4), capped=1 when a cap dropped one — so candidates - n - withheld_rows is what the caps removed and nothing is lost silently. budget= is the token-budget cap; withheld=1 when heuristic rows were dropped to fit it, withheld_rows= how many (the map's spelling: a boolean, the count beside it) — verified rows are never dropped; est_tokens= prices the delivered packet in tokens and over_ceiling= is 1 when even the verified floor exceeds budget= (the packet is then complete, not trimmed). gitok=0 means the git diff probe failed and changed counts are floors. -->
<handoff at="c7725f3ef" root="." branch="integration/terminality-2026-09-05" subject="test(gates): N1 — shapingflagcheck&apos;s timeout budget back to 1200; compactlegendcheck stays at 900" gitok="1" budget="1200" withheld="0" withheld_rows="0" est_tokens="1044">
<verified changed="0" blast_files="0">
<tests n="0">
</tests>
</verified>
<heuristic n="5" candidates="130" capped="1">
<note target="test/manifestcheck.sh" txt="README.md&apos;s single &apos;&lt;N&gt; gate scripts&apos; claim (~line 1305) is NOT enforced — the derived-vs-stated sibling loop here covers docs/EVALS.md only. It drifted 407→451 unnoticed (fixed 2026-08-23). To close: grep both files (&apos;file:line … [line truncated: 47 more bytes on this line]
<doc p="docs/SUBSTITUTION_METER.md" s="8.687"/>
<doc p="docs/EVALS.md" s="8.650"/>
<doc p="docs/METHODOLOGY.md" s="8.533"/>
<doc p="docs/CODEX_ORCHESTRATION.md" s="7.624"/>
</heuristic>
</handoff>
`````

## `./build/ripwire . --skipped`

*WHY a file is not in the index (oversize / excluded / unsupported-ext / gitignored) and which indexed files it cannot vouch for (degraded-parse, minified-suspect), plus the per-language census.*

`````
<ctx>
<!-- ripwire skipped report: WHY the index does not contain a file, and which files it DOES contain but cannot vouch for. Two row kinds. <f p= why= bytes= .../> = a file the crawl passed over, one row per drop, why= being oversize (exceeded a size ceiling; limit= names which — the max-file-size flag's value in max_file_size=, or the fixed .json/.yaml config ceilings that flag does not raise, json_ceiling=), excluded (matched an exclude substring; ext= is its extension), or unsupported-ext (ext= has no grammar and no doc handler in this build — the class that hides a whole LANGUAGE). <h p= why= .../> = a file that IS indexed and stays indexed, flagged for the reader: why=degraded-parse means the parse contains ERROR/MISSING nodes (err= counts them, err_ratio= is the share of the file's bytes covered by top-most ERROR spans) and is a PARSER-STATE fact, never a syntax verdict — a valid file in a dialect this grammar predates reads degraded too; why=minified-suspect means whitespace frequency ws_freq= is under 0.070 across the leading 4096 bytes (files under 256 bytes are never flagged — too little text to judge). Nothing here is dropped by these two flags. <lang n= files= symbols=/> = corpus composition BY LANGUAGE: one row per language this build extracted at least one symbol OR one file for, sorted files DESC then name ASC, absent languages simply not rowed. files= is a FLOOR (derived from symbol-bearing files only — a file with zero extracted symbols is not attributed to any language); symbols= is exact, every run. unindexed= (below) is its mirror: languages this build could not read at all; this is what it DID read, broken down. HEADER: indexed= is files= on the map; the ACCOUNTING INVARIANT is indexed= + oversize= + excluded= = the candidate population the crawl ENUMERATED, at every ceiling and exclude setting. unsupported_ext= counts source/text-looking files outside that population (binary/asset extensions are deliberately not counted — an unindexed .png is a picture, not a language this build failed to read); its per-extension breakdown is the <e x= files=/> rows, which the map header rolls up as unindexed= — a TOP-6 list, and the map's unindexed_exts= beside it names how many DISTINCT such extensions exist, present exactly when that list was cut and absent when it is complete. excluded_dirs= counts SUBTREES an exclude pruned: the walk stopped at the directory, so how many files are under them is UNKNOWN, not zero, and they are in no count here. pruned_dirs= counts the subtrees this build ALWAYS prunes by policy — the committed noise/vendor/build denylist and any directory holding a CMakeCache.txt — with the same consequence: the walk stopped there, their contents are UNKNOWN rather than zero, and they are in no count here. The two are separate because the answer to "why is my tree missing" differs: one is a rule you passed, the other is a rule this build carries. degraded_parse= / minified_suspect= count the h rows. ignored= is ignored_files= on the map: files git's OWN ignore rules cover (.gitignore / .git/info/exclude / core.excludesFile), tested LAST — after the extension, the exclude and the built-in denylist — so it only ever counts a file that would OTHERWISE have been indexed, and the accounting invariant above reads indexed= + oversize= + excluded= + ignored=. ignored_dirs= counts SUBTREES those rules pruned, with the same consequence excluded_dirs= carries: the walk stopped at the directory, contents UNKNOWN rather than zero. Both classes are rowed (why="ignored" for the files, why="ignored-dir" for the subtrees, bytes="0" on a subtree because a directory has no size this verb can honestly report). ignore_mode= names WHICH rule set applied: git (consulted and applied), off (the no-ignore flag), unavailable (no git work tree at this root, or no git binary — the full walk), root-ignored (the root is ITSELF inside an ignored subtree, so honouring the rules would empty the map — the full walk). Only ignore_mode="git" can put a non-zero number beside the two counters; every other mode means nothing was consulted, which is not the same claim as nothing being ignored. unmeasured= counts indexed files this run never parsed (a doc-format file extracted by the doc pass, a binary sniff or nesting guard refusal, a read failure) — they are absent from the health counts, not clean. rows_capped="1" means a row list hit its 500-row ceiling, so the rows are a SAMPLE of the count beside them; every count stays exact. A zero means none found. -->
<skipped indexed="1588" oversize="15" excluded="0" unsupported_ext="169" excluded_dirs="0" pruned_dirs="11" ignored="0" ignored_dirs="0" ignore_mode="git" degraded_parse="64" minified_suspect="1" unmeasured="5" max_file_size="4194304" json_ceiling="262144" yaml_ceiling="524288" root=".">
<f p="bench/locbench/full560.json" why="oversize" bytes="679702" limit="262144"/>
<f p="bench/locbench/results/r1_anchorhop/heldout_baseline_release.json" why="oversize" bytes="365776" limit="262144"/>
<f p="bench/locbench/results/r1_anchorhop/heldout_candidate_release.json" why="oversize" bytes="365761" limit="262144"/>
<f p="bench/locbench/results/r3_pathtok/heldout_baseline.json" why="oversize" bytes="440937" limit="262144"/>
<f p="bench/locbench/results/r3_pathtok/heldout_candidate_w3.json" why="oversize" bytes="440925" limit="262144"/>
<f p="bench/locbench/results/r3_pathtok/train_w0.json" why="oversize" bytes="342194" limit="262144"/>
<f p="bench/locbench/results/r3_pathtok/train_w1.json" why="oversize" bytes="342123" limit="262144"/>
<f p="bench/locbench/results/r3_pathtok/train_w2.json" why="oversize" bytes="342117" limit="262144"/>
<f p="bench/locbench/results/r3_pathtok/train_w3.json" why="oversize" bytes="342138" limit="262144"/>
<f p="bench/locbench/results/r4_siblift/train_1x1.json" why="oversize" bytes="342197" limit="262144"/>
<f p="bench/locbench/results/r4_siblift/train_1x2.json" why="oversize" bytes="342194" limit="262144"/>
<f p="bench/locbench/results/r4_siblift/train_2x1.json" why="oversize" bytes="342187" limit="262144"/>
<f p="bench/locbench/results/r4_siblift/train_2x2.json" why="oversize" bytes="342210" limit="262144"/>
<f p="bench/locbench/results/r4_siblift/train_base.json" why="oversize" bytes="342194" limit="262144"/>
<f p="bench/locbench/results/vt2_pooling_freestat/vt2_train_base.json" why="oversize" bytes="342396" limit="262144"/>
<f p="CMakeLists.txt" why="unsupported-ext" bytes="62782" ext=".txt"/>
<f p="bench/agentloop/editsuite/expected/i1/stats.py.expected" why="unsupported-ext" bytes="603" ext=".expected"/>
<f p="bench/agentloop/editsuite/expected/i2/matrix.cpp.expected" why="unsupported-ext" bytes="973" ext=".expected"/>
<f p="bench/agentloop/editsuite/expected/i3/text.py.expected" why="unsupported-ext" bytes="338" ext=".expected"/>
<f p="bench/agentloop/editsuite/expected/p1/geometry.cpp.expected" why="unsupported-ext" bytes="723" ext=".expected"/>
<f p="bench/agentloop/editsuite/expected/p2/stats.py.expected" why="unsupported-ext" bytes="575" ext=".expected"/>
<f p="bench/agentloop/editsuite/expected/p2/text.py.expected" why="unsupported-ext" bytes="312" ext=".expected"/>
<f p="bench/agentloop/editsuite/expected/p3/matrix.cpp.expected" why="unsupported-ext" bytes="824" ext=".expected"/>
<f p="bench/agentloop/editsuite/expected/p3/stats.py.expected" why="unsupported-ext" bytes="593" ext=".expected"/>
<f p="bench/agentloop/editsuite/expected/p3/text.py.expected" why="unsupported-ext" bytes="285" ext=".expected"/>
<f p="bench/agentloop/editsuite/expected/r1/geometry.cpp.expected" why="unsupported-ext" bytes="625" ext=".expected"/>
<f p="bench/agentloop/editsuite/expected/r2/stats.py.expected" why="unsupported-ext" bytes="587" ext=".expected"/>
… [262 more display lines; full output is 30310 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --no-ignore --top-k=3`

*Crawl paths the repo's own .gitignore covers (default honours it and discloses ignored_files=/ignored_dirs= only when it dropped anything — this repo's crawl drops nothing, so the header is identical to the default map's; --skipped's ignore_mode= says which rule applied).*

`````
<!-- ripwire v1 t=fn|method|cls|struct|iface|var|sec|macro(#define;degraded:body-is-replacement-text,edges-cross-expansion) p=path layer=arch-layer(opt) n=name id=canonical(path::scope::name,when-scoped) k=rank c=call amb=ambiguous-calls(read-source) lpin=calls-pinned-by-locality-prior-alone(a-disclosed-guess;read-source;absent-if-0) overloads=N-same-name-defs-merged-into-this-row(absent-if-1;shown=counts-them-individually,so-rows+sum(overloads-1)=shown) prov=scip(precise;else name-based) hdr:unresolved=call-name-defined-only-in-a-lang-incompatible-file (edges heuristic) hdr:locality_pinned=sum-of-lpin(absent-if-0) hdr:external=calls-refused-as-bound-outside-the-tree(builtin/stdlib-name-without-in-repo-evidence,external-import,super-past-the-tree;no-edge;absent-if-0) r:est_tokens=hdr-copy(none-if-stable) -->
<!-- r:root=crawl-root-every-p=-is-relative-to(single-root-only;absent=>p=is-the-raw-ingest-path) -->
<!-- pr_iters=pagerank-power-iterations(stop:L1-residual-below-tol,else-ceiling) pr_converged=0-only-when-ceiling-hit-first(absent=converged;no-such-attr=not-pagerank-ordered) -->
<!-- files=1588 symbols=13849 edges=17058 shown=3 est_tokens=698 ambiguous=6085 unresolved=3093 locality_pinned=6 external=788 precise=3 skipped_oversize=15 unindexed="txt:59,jsonl:26,tsv:21,scm:18,expected:15,lock:7" unindexed_exts=19 order=important-first -->
<r root="." est_tokens="698" pr_iters="31">
<f p="src/infra/svector.h" layer="infra">
<s t="method" n="size" id="src/infra/svector.h::svector::size" k="0.0169">
</s>
</f>
<f p="src/notes.h">
<s t="method" n="empty" id="src/notes.h::NoteIndex::empty" k="0.0099">
</s>
</f>
<f p="src/scipoverlay.h">
<s t="method" n="empty" id="src/scipoverlay.h::ScipOverlay::empty" k="0.0097">
</s>
</f>
</r>
`````

## `./build/ripwire . --no-stable --top-k=3`

*--no-stable outside --mcp: what the flag does (or says) when there is no stable-by-default ordering to opt out of.*

`````
<!-- ripwire v1 t=fn|method|cls|struct|iface|var|sec|macro(#define;degraded:body-is-replacement-text,edges-cross-expansion) p=path layer=arch-layer(opt) n=name id=canonical(path::scope::name,when-scoped) k=rank c=call amb=ambiguous-calls(read-source) lpin=calls-pinned-by-locality-prior-alone(a-disclosed-guess;read-source;absent-if-0) overloads=N-same-name-defs-merged-into-this-row(absent-if-1;shown=counts-them-individually,so-rows+sum(overloads-1)=shown) prov=scip(precise;else name-based) hdr:unresolved=call-name-defined-only-in-a-lang-incompatible-file (edges heuristic) hdr:locality_pinned=sum-of-lpin(absent-if-0) hdr:external=calls-refused-as-bound-outside-the-tree(builtin/stdlib-name-without-in-repo-evidence,external-import,super-past-the-tree;no-edge;absent-if-0) r:est_tokens=hdr-copy(none-if-stable) -->
<!-- r:root=crawl-root-every-p=-is-relative-to(single-root-only;absent=>p=is-the-raw-ingest-path) -->
<!-- pr_iters=pagerank-power-iterations(stop:L1-residual-below-tol,else-ceiling) pr_converged=0-only-when-ceiling-hit-first(absent=converged;no-such-attr=not-pagerank-ordered) -->
<!-- files=1588 symbols=13849 edges=17058 shown=3 est_tokens=698 ambiguous=6085 unresolved=3093 locality_pinned=6 external=788 precise=3 skipped_oversize=15 unindexed="txt:59,jsonl:26,tsv:21,scm:18,expected:15,lock:7" unindexed_exts=19 order=important-first -->
<r root="." est_tokens="698" pr_iters="31">
<f p="src/infra/svector.h" layer="infra">
<s t="method" n="size" id="src/infra/svector.h::svector::size" k="0.0169">
</s>
</f>
<f p="src/notes.h">
<s t="method" n="empty" id="src/notes.h::NoteIndex::empty" k="0.0099">
</s>
</f>
<f p="src/scipoverlay.h">
<s t="method" n="empty" id="src/scipoverlay.h::ScipOverlay::empty" k="0.0097">
</s>
</f>
</r>
`````

stderr:

`````
ripwire: --no-stable is read only by --mcp/--listen (it opts out of the stable ordering the server turns on) — it changed nothing here; the CLI map orders important-first unless you pass --order=stable
`````

## `./build/ripwire . --run-trace="cat <scratch>/aux/asan_trace_now.txt; exit 1"`

*EXEC-MODE --from-trace: run a command, and on a non-zero exit map its captured output onto indexed symbols in the same call — the whole fix-loop entry.*

**exit code: 4**

`````
<ctx task="run-trace: cat <scratch>/aux/asan_trace_now.txt; exit 1" next="--slice=@src/graph.h:1148" est_tokens="3410">
<!-- ripwire trace-to-locus for "run-trace: cat <tmp>; exit 1": frames of a asan trace mapped onto indexed symbols, ranked INNERMOST-first. frame_lines=5 parsed=4 in_corpus=4 skipped=0 (out of every root - listed, never ranked) merged=0 unresolved=0. frame_lines = frame-shaped lines the INPUT presented (a #N marker, a leading "at ", or a Python File "..." line, plus every line that did extract); parsed = how many of them yielded a usable path:line, so frame_lines - parsed is the count that matched no format shape and enters no bucket below. in_corpus = suspects + merged + unresolved, so every file-matched frame is visible: merged= folded into an already-claimed symbol, unresolved= listed as <unresolved> (indexed file, no def by name or by line). resolved_by="name" means the frame's OWN function name bound to a unique def (line_encloses=, when present, names the different symbol today's line sits in: the tell that the trace predates this checkout); resolved_by="line" means the name was absent, unknown or ambiguous, so the def enclosing that line was used. p= on a frame is the FRAME's own locator (the trace's path:line, verbatim); definition sites live in <sigs> l=. On a <sigs> row (rows in r= order): n=name, id=canonical(when scoped), p=file, t=kind, cx=cyclomatic complexity, ccx=cognitive complexity, in=reuse-count (absent = not measured, never a false 0). rank 1 = the innermost in-corpus frame; its FULL body follows, other suspects as signatures. budget=7500 bytes (allowance 9583 bytes = ceiling + the single-entry overshoot a whole first signature costs). On the root: est_tokens= prices the delivered bundle in tokens, budget_tokens= is the token target you passed (absent when none), max_tokens= is the body ceiling you passed via the max_tokens flag (absent when none); over_ceiling= is 1 when est_tokens exceeds the smallest ceiling named here (the bundle is then complete, not trimmed). next= is the one pasteable follow-up: the slice at the innermost in-corpus frame (@FILE:LINE); absent when none landed. -->
<!-- ripwire run-trace: executed "cat <tmp>; exit 1" under sh -c (the make trust model: your user, inherited environment, stdin=/dev/null, NO sandbox), stdout+stderr captured interleaved. On <run>: exit= the command's OWN exit code; signal= the signal that killed it; timed_out="1" = the timeout_s= cap killed the whole process group (an honest TIMEOUT, never an empty success); duration_ms= wall clock; lines= the capture's non-empty line count; bytes= the whole capture; dropped_bytes= middle bytes the capture cap dropped (head+tail kept). duration_ms and the captured output are MEASURED, not deterministic (and not claimed to be); every byte derived FROM the captured text - the <lines> cut and any mapping - is a deterministic function of it. <lines view="tail"> = the last shown= of total= output lines; view="relevant" = shown= of the relevant= error-marked / frame-shaped lines out of total= (capped="1" = first+last halves kept, the omitted middle disclosed inline). The command FAILED and the captured text carried mappable frames: the <trace>/<sigs>/<bodies> bundle below is the byte-deterministic from-trace mapping of that text (its own legend precedes it above). est_tokens= on the root prices duration_ms= at a fixed width (6 digits), so the price is deterministic while the value is measured. -->
<run exit="1" duration_ms="8" timeout_s="600" lines="9" bytes="604"/>
<lines view="relevant" shown="7" relevant="7" total="9">
<![CDATA[AddressSanitizer:DEADLYSIGNAL
==41337==ERROR: AddressSanitizer: SEGV on unknown address 0x000000000018 (pc 0x000102f4a1c8 bp 0x00016d2f1a40 sp 0x00016d2f19e0 T0)
    #0 0x102f4a1c8 in rw::rankGraphTeleport(Graph const&, std::vector<float> const&, float) src/graph.h:1148
    #1 0x102f3e884 in rw::rankGraph(Graph const&, float) src/graph.h:1174
    #2 0x102e11f30 in runDefaultMap(MainDispatch const&) src/main.cpp:5155
    #3 0x102e01a44 in main src/main.cpp:5594
    #4 0x1a2b3c0dc in start+0x9dc (dyld:arm64e+0x60dc)]]></lines><trace src="run-trace: cat <tmp>; exit 1" format … [line truncated: 1672 more bytes on this line]
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
}]]><calls total="9"><c n="biasPrior" l="2464">inline std::vector&lt;float&gt; biasPrior( const Graph&amp; g, const std::vector&lt;float&gt;&amp; p )</c><c n="PROFILE_SCOPE_DESCRIBE" l="1322">#define PROFILE_SCOPE_DESCRIBE( desc )</c><c n="PROFILE_SCOPE_DESCRIBE" l="1336">#define PROFILE_SCOPE_DESCR … [line truncated: 535 more bytes on this line]
`````

## `./build/ripwire . --run-trace="true"`

*A command that exits 0: a minimal success record (exit, measured duration, disclosed output tail) and NO bundle — nothing failed, nothing to map.*

`````
<ctx task="run-trace: true">
<!-- ripwire run-trace: executed "true" under sh -c (the make trust model: your user, inherited environment, stdin=/dev/null, NO sandbox), stdout+stderr captured interleaved. On <run>: exit= the command's OWN exit code; signal= the signal that killed it; timed_out="1" = the timeout_s= cap killed the whole process group (an honest TIMEOUT, never an empty success); duration_ms= wall clock; lines= the capture's non-empty line count; bytes= the whole capture; dropped_bytes= middle bytes the capture cap dropped (head+tail kept). duration_ms and the captured output are MEASURED, not deterministic (and not claimed to be); every byte derived FROM the captured text - the <lines> cut and any mapping - is a deterministic function of it. <lines view="tail"> = the last shown= of total= output lines; view="relevant" = shown= of the relevant= error-marked / frame-shaped lines out of total= (capped="1" = first+last halves kept, the omitted middle disclosed inline). The command exited 0: nothing failed, so there is NOTHING TO MAP - no trace bundle is served for a passing command. -->
<run exit="0" duration_ms="6" timeout_s="600" lines="0" bytes="0"/>
</ctx>
`````

## `./build/ripwire . --run-trace="sleep 30" --run-timeout=2`

*A command still running at the cap: its process group is killed and the run reports timed_out=1 — an honest timeout, never an empty success.*

**exit code: 4** — **wall time: 2.09s**

`````
<ctx task="run-trace: sleep 30">
<!-- ripwire run-trace: executed "sleep 30" under sh -c (the make trust model: your user, inherited environment, stdin=/dev/null, NO sandbox), stdout+stderr captured interleaved. On <run>: exit= the command's OWN exit code; signal= the signal that killed it; timed_out="1" = the timeout_s= cap killed the whole process group (an honest TIMEOUT, never an empty success); duration_ms= wall clock; lines= the capture's non-empty line count; bytes= the whole capture; dropped_bytes= middle bytes the capture cap dropped (head+tail kept). duration_ms and the captured output are MEASURED, not deterministic (and not claimed to be); every byte derived FROM the captured text - the <lines> cut and any mapping - is a deterministic function of it. <lines view="tail"> = the last shown= of total= output lines; view="relevant" = shown= of the relevant= error-marked / frame-shaped lines out of total= (capped="1" = first+last halves kept, the omitted middle disclosed inline). The command FAILED but the captured output carried no stack-trace / sanitizer / compiler frames (frames="0" on <run>): nothing to map onto the corpus - the run record and lines here are the whole answer. -->
<run timed_out="1" signal="9" duration_ms="2001" timeout_s="2" lines="0" bytes="0" frames="0"/>
</ctx>
`````

stderr:

`````
ripwire: --run-trace: TIMEOUT — the command exceeded the 2 s cap; its process group was killed
`````

## `./build/ripwire . --run-timeout=5`

*--run-timeout alone is refused loudly (it only modifies --run-trace).*

**exit code: 1**

`````
(empty)
`````

stderr:

`````
ripwire: --run-timeout=SECONDS modifies --run-trace — pass it too (e.g. ripwire <dir> --run-trace="make -j" --run-timeout=60)
`````


---

# assess quality — the wider lens family

## `./build/ripwire . --quality-panel`

*THE single wide-angle quality read: six families in one pass, an eligible/ranked shortlist rather than a firehose.*

**wall time: 1.63s**

`````
<!-- ripwire quality-panel: THE SINGLE COMMAND, the whole panel of software-quality checks in ONE report, ranked ONLY by the COUNT OF DISTINCT EVIDENCE FAMILIES that fire; NO composite score, by contract. Rationale + worked reading: docs/COMMANDS.md quality-panel; every threshold is reused from its source lens. SIX FAMILIES, partitioned by KIND of evidence: structural (shape: complexity, size, nesting, params, readability rank) lexical (identifier text: naming rules) confusion (syntax: the atom rules) historical (git change frequency, measured PER FILE: every symbol carries its file's churn= and hrank= verbatim, file evidence inherited by the row, not the row's own history) colocation (how much you must READ outside this file) state (this function's OWN BODY touching non-local MUTABLE state). preset=the preset that produced this enabled=the families it COUNTS enabled_n=how many cut=distinct enabled families that must agree for a row families=how many exist. Presets SELECT and CUT, never weight: strict=the five families measured stable enough to stand behind a gate, cut 2 (historical is deliberately absent: a moving 12-month window re-shuffles on unchanged code) default=all six, cut 2 lenient=all six, cut 1. eligible=functions/methods with a body, the denominator ranked=rows that met the cut below_cut=fired at least one enabled family but fewer than the cut no_family=no enabled family fired (ranked= + below_cut= + no_family= = eligible=, always). s=one symbol: p=path:line n=name fam=distinct ENABLED families that fired of=enabled families EVALUABLE for it fired=their names uncounted=fired but not enabled here unavail=not measurable here. e=evidence in one fired family: f=family counted=1 when this preset counts it why=the measurements that crossed (a rule that fired N times reads rule*N). Absolute bars: bar_ccx=cognitive complexity bar_loc=physical lines bar_nest=max nesting depth bar_params=param count; a row shows only the ones that crossed. Rankings fire for the worst decile of their OWN corpus (RELATIVE: 'worst in THIS corpus', never 'bad in absolute terms'): rrank=readability rank (0 least readable) rcut=decile width rmeasured=functions measured; hrank=file churn rank (0 most changed) churn=in-window commit count hcut=decile width hranked=files with any in-window commit window=the churn window; crank=local-reasoning rank (0 reads most from outside its file) ccut=decile width cranked=functions resolving any outside definition. state has no threshold (fires on a direct access site): writes= reads= distinct cells the own body writes/reads. HONESTY: unavailable=families not evaluated at all unavailable_why=one reason each; a family listed there was NOT measured, so its absence from fired= is not evidence of health. An empty ranking or language coverage counts as not measured (hranked=0 voids historical, cranked=0 colocation); published denominators: cfiles=files the atom rules read cscope=eligible symbols in them lscope=symbols the naming rules read sfiles=files the state lens reads sscope=symbols in them cells=non-local mutable cells found. of= is enabled_n= minus the unavailable (a row never counts a family it could not evaluate); cut_reachable=0 when the cut exceeds of=, a fact about the corpus, never a clean bill of health. unreadable_files=files readability could not read (rrank= a floor); findings_capped=1 when a rule spent its per-rule budget, floor_rules=naming them (those families are FLOORS and the root carries counts_floor=1); state_floor=1 when the state lens saturated its budget (a FLOOR too). join=deep+untested is an annotation, NOT a seventh family (changes nothing: not fam=, not of=, not the order): deep= structural evidence (a body that SUSTAINS depth at bar_nest) that no indexed test reaches. tested_scope=symbols an indexed test reaches, the join's honest denominator; at tested_scope=0 the annotation is emitted on NO row. deep_untested=rows carrying it across the WHOLE set (unchanged by limit=). shown=symbol rows printed capped=1 when rows were dropped; the one limit=N offset=M window also prints total= has_more= next_offset= -->
<!-- at= is the git commit these numbers were computed at; a trailing +dirty means the working tree differed from that commit, so the numbers describe the tree, not the commit -->
<!-- root= on this element is the crawl root every p= below is RELATIVE to (single-root runs only; absent => p= is the path ingest itself used, unchanged). -->
<quality_panel preset="default" families="6" enabled="structural,lexical,confusion,historical,colocation,state" enabled_n="6" cut="2" cut_reachable="1" eligible="7979" ranked="470" below_cut="3152" no_family="4357" bar_ccx="15" bar_loc="60" bar_nest="4" bar_params="5" rcut="40" rmeasured="7979" hcut … [line truncated: 288 more bytes on this line]
<s p="src/graph.h:962" n="buildGraph" fam="4" of="6" fired="structural,confusion,historical,colocation">
<e f="structural" counted="1" why="ccx=779 loc=1494 nest=8 humps=33 deep=305 ev=100 rrank=0"/>
<e f="confusion" counted="1" why="atom-embedded-crement*4"/>
<e f="historical" counted="1" why="hrank=11 churn=59"/>
<e f="colocation" counted="1" why="crank=29"/>
</s>
<s p="src/main.cpp:1098" n="runDefaultMap" fam="4" of="6" fired="structural,confusion,historical,colocation" join="deep+untested">
<e f="structural" counted="1" why="ccx=198 loc=816 nest=4 humps=2 deep=8 ev=14 rrank=8"/>
<e f="confusion" counted="1" why="atom-nested-ternary"/>
<e f="historical" counted="1" why="hrank=3 churn=271"/>
<e f="colocation" counted="1" why="crank=1"/>
</s>
<s p="src/main.cpp:2653" n="dispatchMain" fam="4" of="6" fired="structural,confusion,historical,colocation" join="deep+untested">
<e f="structural" counted="1" why="ccx=405 loc=1259 nest=6 humps=16 deep=54 ev=107 rrank=2"/>
<e f="confusion" counted="1" why="atom-assign-as-value"/>
<e f="historical" counted="1" why="hrank=3 churn=271"/>
<e f="colocation" counted="1" why="crank=0"/>
</s>
<s p="src/mcp.h:535" n="dispatchMcpLine" fam="4" of="6" fired="structural,confusion,historical,colocation" join="deep+untested">
<e f="structural" counted="1" why="ccx=517 loc=1369 nest=7 params=5 humps=24 deep=125 ev=21 rrank=1"/>
<e f="confusion" counted="1" why="atom-nested-ternary*3"/>
<e f="historical" counted="1" why="hrank=13 churn=52"/>
<e f="colocation" counted="1" why="crank=2"/>
</s>
<s p="src/mcpverbs.h:875" n="grepHitsJson" fam="4" of="6" fired="structural,confusion,historical,colocation">
<e f="structural" counted="1" why="ccx=28 loc=146"/>
… [185 more display lines; full output is 17383 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --readability --limit=8`

*Per-function readability, LEAST readable first (Halstead volume, token entropy, lines, Posnett) — a RANKING lens, not a grade.*

`````
<!-- ripwire readability: the Posnett/Hindle/Devanbu (MSR 2011) closed-form lens, one row per function or method, LEAST READABLE FIRST. p=path:line n=symbol name lines=L, the definition's physical line span toks=N, the operator+operand tokens of the whole definition (signature included) ops=N1, the operator half of toks (keywords and punctuation; the rest are identifiers and literals) vocab=eta, distinct tokens vol=Halstead volume V, N*log2(eta) ent=E, Shannon entropy of the token frequency distribution, in bits posnett=P, sigmoid(8.87 - 0.033V + 0.40L - 1.5E), the paper's published fit. ONE token-class table serves every language, so V is a cross-language APPROXIMATION, not a per-grammar count. P was fitted on snippets of 20 lines or fewer: read the ORDER, not the number, and never as a grade. The sigmoid SATURATES at the least-readable extreme (a high-volume function's argument clamps at +/-40), so several head rows can print posnett="0.000" alike; those ties (and every tie) break by vol= descending, so the ORDER stays real even where P itself has run out of visible precision. functions=functions and methods measured (a declaration with no body is not measured) shown=rows printed capped=1 when rows were dropped; raise the default cap with limit=N (offset=M pages; a cut listing carries total=/has_more=/next_offset= so a paging loop can continue from it), which also prints total= has_more= next_offset= offset= limit= unreadable_files=indexed files this pass could not read; their functions are absent, so functions= is a FLOOR -->
<!-- root= on this element is the crawl root every p= below is RELATIVE to (single-root runs only; absent => p= is the path ingest itself used, unchanged). -->
<readability functions="7979" shown="8" capped="1" total="7979" has_more="1" next_offset="8" offset="0" limit="8" root=".">
<fn p="src/graph.h:962" n="buildGraph" lines="1494" toks="8023" ops="5154" vocab="453" vol="70789.9" ent="6.36" posnett="0.000"/>
<fn p="src/mcp.h:535" n="dispatchMcpLine" lines="1369" toks="6674" ops="4212" vocab="597" vol="61544.9" ent="6.37" posnett="0.000"/>
<fn p="src/main.cpp:2653" n="dispatchMain" lines="1259" toks="6032" ops="3909" vocab="531" vol="54605.1" ent="6.25" posnett="0.000"/>
<fn p="src/packtask.h:1082" n="packTaskBundleText" lines="655" toks="4900" ops="2987" vocab="439" vol="43012.6" ent="6.46" posnett="0.000"/>
<fn p="src/verbs_lint.h:1175" n="runLint" lines="781" toks="4736" ops="2982" vocab="441" vol="41604.0" ent="6.39" posnett="0.000"/>
<fn p="src/verbs_report.h:2707" n="runStructureText" lines="529" toks="4810" ops="2936" vocab="335" vol="40346.4" ent="6.14" posnett="0.000"/>
<fn p="src/lexical.h:121" n="lexicalScoresTiered" lines="780" toks="4816" ops="3051" vocab="324" vol="40164.7" ent="6.26" posnett="0.000"/>
<fn p="src/verbs_for.h:1447" n="runForLens" lines="993" toks="4441" ops="2721" vocab="410" vol="38545.6" ent="6.34" posnett="0.000"/>
</readability>
`````

## `./build/ripwire . --comment-coherence --limit=8`

*Functions WITH a doc comment, most name-restating first: c_coeff (high = the comment repeats the name) and cic (Jaccard of comment vs identifier vocabulary), both reported, never collapsed.*

`````
<!-- ripwire comment-coherence: two content measures per documented function/method, MOST NAME-RESTATING FIRST. p=path:line n=symbol name c_coeff=Steidl/Hummel/Juergens coherence coefficient (ICPC 2013): fraction of the comment's words within Levenshtein distance under 2 of a word in the symbol's own (split) name. HIGH c_coeff IS BAD: it means the comment mostly repeats the name and adds no information; this is the OPPOSITE of the naive 'high coherence sounds good' reading. words=the comment's total word count (c_coeff's denominator, UNFILTERED: stopwords kept, matching the paper) restate=the numerator, words that matched a name word cic=Scalabrino Comments-Identifiers Consistency (ICPC 2016 / JSEP 2018): Jaccard overlap of two method-local TERM SETS: the comment's vocabulary vs every identifier the definition's own span uses (parameters, locals, callees, fields), both preprocessed (operators/keywords stripped by construction, camelCase/snake_case split, English stopwords dropped, deduplicated). c_terms=|Comments(m)| i_terms=|Ids(m)| shared=size of their overlap; from these, cic = shared/(c_terms+i_terms-shared). c_coeff and cic measure DIFFERENT things and are expected to DISAGREE: report both, never collapse to one number. Fires ONLY where a doc comment actually exists immediately above the definition; a symbol with none (or one that tokenizes to zero words) is UNAVAILABLE for this measure, never scored: counted in no_comment=, never as a zero. Complements doc-drift, which checks markdown CLAIM staleness, a disjoint axis over disjoint input; this verb never checks staleness and doc-drift never checks content. documented=functions/methods measured (rows emitted) no_comment=eligible symbols with nothing to measure unreadable_files=indexed files this pass could not read; their functions are absent, so documented= is a FLOOR shown=rows printed capped=1 when rows were dropped; raise the default cap with limit=N (offset=M pages; a cut listing carries total=/has_more=/next_offset= so a paging loop can continue from it), which also prints total= has_more= next_offset= offset= limit= -->
<comment_coherence documented="2295" no_comment="5684" shown="8" capped="1" total="2295" has_more="1" next_offset="8" offset="0" limit="8" root=".">
<fn p="src/query.h:231" n="sourceAll" c_coeff="1.000" words="1" restate="1" cic="0.000" c_terms="1" i_terms="12" shared="0"/>
<fn p="src/verbs_quality.h:1514" n="runDmm" c_coeff="1.000" words="1" restate="1" cic="0.032" c_terms="1" i_terms="31" shared="1"/>
<fn p="src/infra/dynamic_map.hpp:1956" n="erase_rec" c_coeff="1.000" words="1" restate="1" cic="0.048" c_terms="1" i_terms="21" shared="1"/>
<fn p="test/lintfix/bad.cpp:23" n="emptyCatchFunc" c_coeff="1.000" words="2" restate="2" cic="0.400" c_terms="2" i_terms="5" shared="2"/>
<fn p="test/bm25fix/common.cpp:18" n="module_validate_handle" c_coeff="0.667" words="6" restate="4" cic="0.400" c_terms="4" i_terms="3" shared="2"/>
<fn p="test/bm25fix/common.cpp:6" n="module_startup_log" c_coeff="0.571" words="7" restate="4" cic="0.286" c_terms="5" i_terms="4" shared="2"/>
<fn p="test/bm25fix/common.cpp:12" n="module_shutdown_log" c_coeff="0.571" words="7" restate="4" cic="0.286" c_terms="5" i_terms="4" shared="2"/>
<fn p="test/jsmetricsfix/shapes.js:29" n="callsLeafAndDeep" c_coeff="0.533" words="15" restate="8" cic="0.364" c_terms="10" i_terms="5" shared="4"/>
</comment_coherence>
`````

## `./build/ripwire . --context-ratio --limit=8`

*The local-reasoning lens: to understand this symbol, how much must you know that is NOT in front of you (ent_ratio= edge share, read_ratio= token-weighted).*

`````
<!-- ripwire context-ratio: the LOCAL-REASONING lens — for one symbol (and the same numbers rolled up per file), how much of what you must resolve to understand it lives OUTSIDE its own file. ATTRIBUTION, because the fraction itself is published: the share of a unit's coupling that stays inside its own boundary is Beck and Diehl's per-class congruence (FSE 2011) and Martin's instability Ce/(Ca+Ce) is its crude ancestor. This verb is a REFINEMENT of that measure, not a new one. Two things are refined. First, the ratio is also taken over what a reader must READ (read_ratio=, weighted by the estimated tokens of the definitions to open) and not only over edge counts (ent_ratio=) — both are printed side by side so the weighting can be seen doing work. Second, the reference set is EVERY use site (call, value read, write, import, base class, member type), not calls alone, so a type whose whole outside context is a base class and a field is measured rather than missed. s=one measured symbol: p=path:line n=symbol name t=symbol kind. f=the same columns rolled up per file, which is a UNION over every reference site in the file — including the file-scope ones like includes and imports that belong to no symbol — and therefore NOT the sum of that file's symbol rows. sites=reference sites scanned for this unit, in every role ents=distinct in-corpus definitions those sites resolve to ents_out=how many of them are defined outside this unit's own file ent_ratio=ents_out divided by ents, the edge-count form files=distinct files holding those definitions files_out=how many of them are not this unit's own file rtok=estimated tokens of every entity definition, the whole span at 3.80 bytes per token, which is what a reader must actually read rtok_out=the outside-the-file part of rtok read_ratio=rtok_out divided by rtok, the READER-WEIGHTED form and the one this verb exists for. Both ratios print 0.000 when there is nothing to resolve (ents=0), which is not the same claim as a self-contained unit — read ents= first. ext=distinct referenced names with NO in-corpus definition. Local variables and parameters produce read and write sites, so they DOMINATE ext= on real code: it is not a count of external dependencies and it is excluded from both ratios. amb_names=distinct referenced names that resolved to more than one definition (a per-NAME tally; the map row's amb= is a per-CALL count of a different resolver), each of which is counted as an entity — resolution is NAME-BASED and language-gated, the same heuristic level the uses verb works at, never the call graph's narrowed resolution, because four of the five reference roles carry no resolution at all. defs_per_name_cap=the most definitions ONE name may contribute (the first that many in symbol id order); a corpus-ubiquitous name would otherwise swamp every row it appears in. defs_capped="1" ⇒ some name HAD more than that and its extra definitions were not counted, so the root also carries counts_floor="1" (ents=/rtok= are floors); absent ⇒ every name's definitions were all counted. body_bytes_per_token=the rate rtok= is converted at. ents= and files= are FLOORS: a name-based static scan cannot see dynamic dispatch, reflection, or a macro invocation whose #define is not indexed, so a zero means none FOUND, never none exists. units=symbols measured file_units=files measured. Rows come out most-outside-reading-first (rtok_out descending, then ents_out, then rtok, then id) — an ORDERING, never a grade, and never a threshold. shown_syms=symbol rows printed syms_capped=1 when symbol rows were dropped shown_files=file rows printed files_capped=1 when file rows were dropped; the symbol listing is the one limit=N and offset=M window, which also prints total= has_more= next_offset= offset= limit= -->
<!-- root= on this element is the crawl root every p= below is RELATIVE to (single-root runs only; absent => p= is the path ingest itself used, unchanged). -->
<contextratio units="11345" file_units="1290" defs_per_name_cap="8" body_bytes_per_token="3.80" shown_syms="8" syms_capped="1" shown_files="40" files_capped="1" total="11345" has_more="1" next_offset="8" offset="0" limit="8" defs_capped="1" counts_floor="1" root=".">
<s p="src/main.cpp:2653" n="dispatchMain" t="fn" sites="956" ents="151" ents_out="136" ent_ratio="0.901" files="48" files_out="47" rtok="205409" rtok_out="180485" read_ratio="0.879" ext="129" amb_names="18"/>
<s p="src/main.cpp:1098" n="runDefaultMap" t="fn" sites="690" ents="74" ents_out="68" ent_ratio="0.919" files="23" files_out="22" rtok="61494" rtok_out="58937" read_ratio="0.958" ext="102" amb_names="9"/>
<s p="src/mcp.h:535" n="dispatchMcpLine" t="fn" sites="1047" ents="144" ents_out="128" ent_ratio="0.889" files="22" files_out="21" rtok="61075" rtok_out="58586" read_ratio="0.959" ext="135" amb_names="13"/>
<s p="src/mcpverbs.h:3019" n="computeQualityDelta" t="fn" sites="62" ents="30" ents_out="27" ent_ratio="0.900" files="13" files_out="12" rtok="40509" rtok_out="40301" read_ratio="0.995" ext="10" amb_names="6"/>
<s p="src/mcpverbs.h:1463" n="forTaskText" t="fn" sites="358" ents="84" ents_out="81" ent_ratio="0.964" files="22" files_out="21" rtok="39163" rtok_out="38848" read_ratio="0.992" ext="67" amb_names="12"/>
<s p="src/mcpverbs.h:3252" n="packTaskText" t="fn" sites="116" ents="31" ents_out="31" ent_ratio="1.000" files="17" files_out="17" rtok="36647" rtok_out="36647" read_ratio="1.000" ext="23" amb_names="4"/>
<s p="src/mcpserver.h:415" n="runMcpHttp" t="fn" sites="254" ents="32" ents_out="22" ent_ratio="0.688" files="15" files_out="14" rtok="37467" rtok_out="35256" read_ratio="0.941" ext="52" amb_names="3"/>
<s p="src/mcpverbs.h:3399" n="editCheckText" t="fn" sites="36" ents="30" ents_out="30" ent_ratio="1.000" files="20" files_out="20" rtok="33180" rtok_out="33180" read_ratio="1.000" ext="6" amb_names="6"/>
<f p="src/main.cpp" sites="2756" ents="308" ents_out="270" ent_ratio="0.877" files="83" files_out="82" rtok="340792" rtok_out="293144" read_ratio="0.860" ext="449" amb_names="31"/>
<f p="src/mcpverbs.h" sites="3928" ents="376" ents_out="317" ent_ratio="0.843" files="78" files_out="77" rtok="223967" rtok_out="183425" read_ratio="0.819" ext="484" amb_names="36"/>
<f p="src/verbs_for.h" sites="1924" ents="169" ents_out="140" ent_ratio="0.828" files="41" files_out="40" rtok="89206" rtok_out="73294" read_ratio="0.822" ext="267" amb_names="18"/>
<f p="src/verbs_change.h" sites="1301" ents="182" ents_out="152" ent_ratio="0.835" files="53" files_out="52" rtok="69164" rtok_out="63737" read_ratio="0.922" ext="178" amb_names="21"/>
<f p="src/mcp.h" sites="1207" ents="164" ents_out="139" ent_ratio="0.848" files="27" files_out="26" rtok="94418" rtok_out="59517" read_ratio="0.630" ext="184" amb_names="15"/>
<f p="src/verbs_navigate.h" sites="2557" ents="199" ents_out="184" ent_ratio="0.925" files="57" files_out="56" rtok="60699" rtok_out="54719" read_ratio="0.901" ext="262" amb_names="25"/>
<f p="src/verbs_quality.h" sites="1309" ents="196" ents_out="162" ent_ratio="0.827" files="48" files_out="47" rtok="58535" rtok_out="46621" read_ratio="0.796" ext="170" amb_names="22"/>
<f p="src/quality.h" sites="3310" ents="318" ents_out="161" ent_ratio="0.506" files="65" files_out="64" rtok="72343" rtok_out="43866" read_ratio="0.606" ext="481" amb_names="40"/>
<f p="src/verbs_report.h" sites="3312" ents="235" ents_out="190" ent_ratio="0.809" files="48" files_out="47" rtok="60524" rtok_out="43266" read_ratio="0.715" ext="382" amb_names="28"/>
<f p="src/mcpindex.h" sites="705" ents="128" ents_out="90" ent_ratio="0.703" files="38" files_out="37" rtok="43767" rtok_out="36552" read_ratio="0.835" ext="163" amb_names="19"/>
<f p="src/mcpserver.h" sites="487" ents="56" ents_out="40" ent_ratio="0.714" files="22" files_out="21" rtok="38761" rtok_out="36044" read_ratio="0.930" ext="96" amb_names="8"/>
<f p="src/editpreview.h" sites="412" ents="88" ents_out="82" ent_ratio="0.932" files="32" files_out="31" rtok="36709" rtok_out="34556" read_ratio="0.941" ext="80" amb_names="17"/>
<f p="src/packtask.h" sites="1287" ents="160" ents_out="118" ent_ratio="0.738" files="30" files_out="29" rtok="36708" rtok_out="27593" read_ratio="0.752" ext="201" amb_names="22"/>
<f p="src/ingest_parsepool.h" sites="555" ents="108" ents_out="97" ent_ratio="0.898" files="33" files_out="32" rtok="28281" rtok_out="23286" read_ratio="0.823" ext="102" amb_names="19"/>
<f p="src/graph.h" sites="3497" ents="259" ents_out="176" ent_ratio="0.680" files="49" files_out="48" rtok="35475" rtok_out="22898" read_ratio="0.645" ext="423" amb_names="41"/>
<f p="src/partition.h" sites="453" ents="97" ents_out="80" ent_ratio="0.825" files="19" files_out="18" rtok="26425" rtok_out="22711" read_ratio="0.859" ext="72" amb_names="17"/>
<f p="test/verify_csr.cpp" sites="163" ents="39" ents_out="34" ent_ratio="0.872" files="15" files_out="14" rtok="23417" rtok_out="22648" read_ratio="0.967" ext="31" amb_names="12"/>
<f p="src/ingest.cpp" sites="224" ents="58" ents_out="50" ent_ratio="0.862" files="26" files_out="25" rtok="21822" rtok_out="21194" read_ratio="0.971" ext="98" amb_names="9"/>
<f p="src/verbs_lint.h" sites="1524" ents="138" ents_out="114" ent_ratio="0.826" files="36" files_out="35" rtok="31336" rtok_out="20065" read_ratio="0.640" ext="239" amb_names="22"/>
… [22 more display lines; full output is 13320 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --nonlocal-state --limit=8`

*Per function, the non-local MUTABLE state it can reach (transitively), most writes first — unsound by construction, and the legend says where.*

**wall time: 1.11s**

`````
<!-- ripwire nonlocal-state: per function, the NON-LOCAL MUTABLE STATE it can reach, reads and writes kept apart. A cell is one mutable datum declared outside any local scope: a file or namespace scope variable, a function-local static (local in name only), or a Python module global. A const, constexpr or consteval declaration is NOT a cell. An INSTANCE FIELD is not a cell either, by definition: per-object state is a different hazard, answered per member by the uses verb's Owner.field selector — so a member access (o.x, this->x) and a bare name the enclosing method's own class declares as a field are never charged to a same-named global here. Rows are ordered MOST WRITES FIRST, then most reads. p=path:line n=symbol name writes=distinct cells this function or its transitive callees WRITE reads=distinct cells this function or its transitive callees READ direct_writes=the writes= subset written in this function's OWN body direct_reads=the reads= subset read in this function's OWN body cells_total=distinct cells reached (a cell both read and written counts once) cells_shown=cell children printed cells_capped=1 when a row's children were truncated. Each cell child: n=cell name p=the cell's declaration path:line dir=r for read, w for write, rw for both, taken over this function's OWN BODY AND its callee closure together at=one use site in this function's own body (direct cells; there may be more) at_dir=what the OWN-BODY sites do, which can be NARROWER than dir=: at_dir=r with dir=rw means this body only reads the cell and a callee is what writes it via=the nearest callee whose own body touches the cell (transitive cells; exactly one of at= or via= is present). cells=cells found in the corpus functions=functions reaching at least one cell shown=rows printed capped=1 when rows were dropped; raise the default cap with limit=N (offset=M pages; a cut listing carries total=/has_more=/next_offset= so a paging loop can continue from it), which also prints total= has_more= next_offset= offset= limit= unanalyzed_langs=indexed languages this lens does NOT analyse, so their files contribute NO cells and NO rows; the analysis covers C++, ObjC and Python, the languages whose read and write use sites the index carries. Their absence is NOT a measurement of zero. unanalyzed_files=indexed files in those languages undecided_decls=declarations whose specifiers ran past the text window, so mutability could not be decided; dropped, never guessed cells_capped=1 on the ROOT when the cell universe hit its ceiling decls_capped=1 when a declaration query hit its match budget. counts_floor=1 because this analysis is UNSOUND BY CONSTRUCTION and every count here is a FLOOR (graph_ambiguous=/graph_unresolved= are the whole graph's resolver gauge: calls split over several defs / calls whose in-repo defs were all language-filtered, the map header's ambiguous=/unresolved=). It cannot see: an indirect call (a virtual, an unbound or reassigned function pointer or callback, or a macro invocation whose #define is not indexed), so the callee closure stops early; a write through a pointer or reference that ALIASES a cell without naming it; a cell named only inside a macro; reflection-like or duck-typed dispatch. It can also OVER-count in one way: a local that SHADOWS a cell's name is charged to the cell unless ingest recorded a type binding for that local, which it does for typed and constructed locals only. Read a zero as none found, never as none exists, and read a row as a place to look rather than a verdict. -->
<nonlocal_state cells="580" functions="538" shown="8" capped="1" total="538" has_more="1" next_offset="8" offset="0" limit="8" graph_ambiguous="6085" graph_unresolved="3093" counts_floor="1" unanalyzed_langs="c,go,rust,javascript,typescript,java,csharp,swift,ruby,bash" unanalyzed_files="727" root=". … [line truncated: 2 more bytes on this line]
<fn p="bench/bench_svector_wave.cpp:346" n="main" writes="8" reads="14" direct_writes="0" direct_reads="4" cells_total="14" cells_shown="12" cells_capped="1">
<cell n="kNames" p="bench/bench_svector_wave.cpp:98" dir="rw" at="bench/bench_svector_wave.cpp:358" at_dir="r"/>
<cell n="kPush" p="bench/bench_svector_wave.cpp:99" dir="rw" at="bench/bench_svector_wave.cpp:358" at_dir="r"/>
<cell n="kReads" p="bench/bench_svector_wave.cpp:100" dir="rw" at="bench/bench_svector_wave.cpp:358" at_dir="r"/>
<cell n="kSamples" p="bench/bench_svector_wave.cpp:101" dir="rw" at="bench/bench_svector_wave.cpp:358" at_dir="r"/>
<cell n="g_api" p="src/infra/profilePmc.h:137" dir="rw" via="ensure_thread_counting"/>
<cell n="g_keyOf" p="bench/bench_svector_wave.cpp:145" dir="rw" via="regenerate"/>
<cell n="g_perf" p="src/infra/profilePmc.h:284" dir="rw" via="ensure_thread_counting"/>
<cell n="g_readOf" p="bench/bench_svector_wave.cpp:146" dir="rw" via="regenerate"/>
<cell n="g_arm" p="bench/bench_svector_wave.cpp:65" dir="r" via="runArm"/>
<cell n="g_bytes" p="bench/bench_svector_wave.cpp:67" dir="r" via="runArm"/>
<cell n="g_count" p="bench/bench_svector_wave.cpp:66" dir="r" via="runArm"/>
<cell n="g_once" p="src/infra/profilePmc.h:285" dir="r" via="ensure_thread_counting"/>
</fn>
<fn p="bench/bench_svector_wave.cpp:295" n="sweep" writes="6" reads="13" direct_writes="4" direct_reads="1" cells_total="13" cells_shown="12" cells_capped="1">
<cell n="kNames" p="bench/bench_svector_wave.cpp:98" dir="rw" at="bench/bench_svector_wave.cpp:317" at_dir="w"/>
<cell n="kPush" p="bench/bench_svector_wave.cpp:99" dir="rw" at="bench/bench_svector_wave.cpp:318" at_dir="w"/>
<cell n="kReads" p="bench/bench_svector_wave.cpp:100" dir="rw" at="bench/bench_svector_wave.cpp:319" at_dir="rw"/>
<cell n="kSamples" p="bench/bench_svector_wave.cpp:101" dir="rw" at="bench/bench_svector_wave.cpp:313" at_dir="w"/>
<cell n="g_keyOf" p="bench/bench_svector_wave.cpp:145" dir="rw" via="regenerate"/>
<cell n="g_readOf" p="bench/bench_svector_wave.cpp:146" dir="rw" via="regenerate"/>
<cell n="g_api" p="src/infra/profilePmc.h:137" dir="r" via="read"/>
<cell n="g_arm" p="bench/bench_svector_wave.cpp:65" dir="r" via="runArm"/>
<cell n="g_bytes" p="bench/bench_svector_wave.cpp:67" dir="r" via="runArm"/>
<cell n="g_count" p="bench/bench_svector_wave.cpp:66" dir="r" via="runArm"/>
<cell n="g_perf" p="src/infra/profilePmc.h:284" dir="r" via="read"/>
<cell n="g_pool" p="bench/bench_svector_wave.cpp:144" dir="r" via="regenerate"/>
</fn>
… [46 more display lines; full output is 10183 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --ensemble --limit=8`

*The family join: per function, which of four orthogonal evidence families fire, ranked by how many agree.*

`````
<!-- ripwire ensemble: the FAMILY JOIN over four orthogonal evidence families, ranked by the COUNT OF DISTINCT FAMILIES that fire and by nothing else. There is NO composite score here, by contract: averaging correlated metrics re-weights one signal and calls it three, and a single quotable number is wrong the moment it is quoted. fam= is ordinal and every row carries its own evidence. The four families are structural (the shape of the code), lexical (the identifier text: the naming rules), confusion (the syntactic construct: the atom rules) and historical (git change frequency, measured PER FILE: every symbol in a file carries that file's churn= and hrank= verbatim, so this family is file evidence inherited by the row, not the row's own history). families=how many families exist eligible=functions and methods with a body, the denominator ranked=eligible symbols where at least one family fired no_family=eligible symbols where none did (ranked= + no_family= = eligible= exactly, on every run). s=one joined symbol: p=path:line n=symbol name fam=how many DISTINCT families fired of=how many families could be EVALUATED at all fired=their names unavail=families that could not be measured here. e=the evidence inside one fired family: f=family name why=the measurements that crossed, space separated; a lexical or confusion rule that fired N times reads rule*N. f=the per-file rollup: p=path top=the file's most corroborated symbol top_l=its line top_fam=its family count union_fam=how many distinct families fire ANYWHERE in the file union=their names syms=symbols in the file with at least one family. top_fam= is the STRONGER claim (several families agreeing on ONE symbol); union_fam= is weaker (different families on different symbols) and the rollup is ranked by the stronger one. THRESHOLDS, all stated here. Four structural signals are ABSOLUTE bars, reused verbatim from the quality-delta bars: bar_ccx=cognitive complexity bar_loc=physical lines bar_nest=max nesting depth bar_params=parameter count; a row shows only the ones that crossed, with the value that crossed. Two signals are RANKINGS with no defensible absolute cut, so each fires for the worst decile of its own ranking, at least one row and at most 40 (each verb's own default window): rrank=the symbol's rank in the readability lens (0 is least readable) rcut=how many ranks that decile covers rmeasured=functions the readability lens measured; hrank=the file's rank by git churn (0 is most changed) churn=its in-window commit count hcut=how many ranks that decile covers hranked=files with any in-window commit window=the churn window. An ordinal cut is RELATIVE: some symbol is always in the worst decile of its own corpus, so rrank= and hrank= mean 'worst in THIS corpus', never 'bad in absolute terms'. The historical family ranks by churn ALONE, not by the hotspots score (churn x complexity), because half of that product is the structural family and two families that cannot disagree are one family counted twice. unavailable=families that could not be evaluated at all, with unavailable_why= saying why, one reason per unavailable family (§L10: both absent, never ="", when every family was measured — house convention, absent means none). UNAVAILABLE is never the same as silent: an ABSENT unavailable= means every family was measured, and a family listed there was NOT measured, so its absence from fired= is not evidence of health. An EMPTY ranking counts as not measured, so hranked=0 makes the historical family unavailable: a corpus scanned from outside the repository that tracks it mines zero churn for every file, and that silence is not a fact about the code. So does an empty LANGUAGE COVERAGE. The confusion family is the atom pack, which by design runs only on C/C++/ObjC/CUDA paths, so on a corpus with no eligible function in one it was never applicable rather than quiet: cfiles=indexed files it can read cscope=eligible symbols inside them, and cscope=0 makes it unavailable. The lexical family is the naming pack, which has no opinion about a data or doc language: lscope=eligible symbols in a language it reads, and lscope=0 makes it unavailable. The structural family has no such precondition - its bars and its readability rank are computed for every language. of= on each row is 4 minus the unavailable families, so a row NEVER counts a family that could not have been evaluated for it, and fam= cannot reach 4 on a corpus where one family was never applicable. unreadable_files=indexed files the readability lens could not read, so rrank= is a floor over what it saw. findings_capped=1 when a lexical or confusion rule spent its per-rule budget, with floor_rules= naming them: those families are then FLOORS and the root carries counts_floor=1. A naming or atom finding that lies outside every function body is not joined to any symbol and is not counted here. shown_syms=symbol rows printed syms_capped=1 when symbol rows were dropped shown_files=file rows printed files_capped=1 when file rows were dropped; the symbol listing is the one limit=N and offset=M window, which also prints total= has_more= next_offset= offset= limit= -->
<!-- at= is the git commit these numbers were computed at; a trailing +dirty means the working tree differed from that commit, so the numbers describe the tree, not the commit -->
<!-- root= on this element is the crawl root every p= below is RELATIVE to (single-root runs only; absent => p= is the path ingest itself used, unchanged). -->
<ensemble families="4" eligible="7979" ranked="3397" no_family="4582" bar_ccx="15" bar_loc="60" bar_nest="4" bar_params="5" rcut="40" rmeasured="7979" hcut="40" hranked="1588" window="12mo" cfiles="500" cscope="4151" lscope="7979" shown_syms="8" syms_capped="1" shown_files="20" files_capped="1" tota … [line truncated: 83 more bytes on this line]
<s p="src/serialize.h:5844" n="packDeps" fam="4" of="4" fired="structural,lexical,confusion,historical">
<e f="structural" why="ccx=110 loc=249 nest=5 params=13 humps=4 deep=14 ev=5 rrank=21"/>
<e f="lexical" why="naming-confusable"/>
<e f="confusion" why="atom-nested-ternary*2"/>
<e f="historical" why="hrank=9 churn=99"/>
</s>
<s p="src/crossref.h:1773" n="evalStray" fam="3" of="4" fired="structural,confusion,historical">
<e f="structural" why="ccx=23 loc=86 ev=9"/>
<e f="confusion" why="atom-assign-as-value"/>
<e f="historical" why="hrank=29 churn=24"/>
</s>
<s p="src/crossref.h:2088" n="writeWhereisPage" fam="3" of="4" fired="structural,confusion,historical">
<e f="structural" why="ccx=23 loc=157 params=5"/>
<e f="confusion" why="atom-nested-ternary"/>
<e f="historical" why="hrank=29 churn=24"/>
</s>
<s p="src/gitmine.h:892" n="addRootFilesToGitPathIndex" fam="3" of="4" fired="structural,lexical,confusion">
<e f="structural" why="ccx=25 ev=6"/>
<e f="lexical" why="naming-wordy"/>
<e f="confusion" why="atom-embedded-crement*2"/>
</s>
<s p="src/graph.h:962" n="buildGraph" fam="3" of="4" fired="structural,confusion,historical">
<e f="structural" why="ccx=779 loc=1494 nest=8 humps=33 deep=305 ev=100 rrank=0"/>
<e f="confusion" why="atom-embedded-crement*4"/>
<e f="historical" why="hrank=11 churn=59"/>
</s>
… [36 more display lines; full output is 10727 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --field-affinity`

*The cache-locality lens over every aggregate: fields READ TOGETHER but declared FAR APART (split-line / straddle findings, Chilimbi separation weight) — advice only, never a rewrite.*

`````
<!-- ripwire field-affinity: which fields are READ TOGETHER but declared far apart, diffed against 64-byte cache-line geometry. PRIOR ART, claimed by NOBODY here as new: the field affinity graph, the static field-access enumeration without pointer analysis, and the separation weight wt(fi,fj) = (block - dist)/block are Chilimbi, Davidson and Larus, Cache-Conscious Structure Definition, PLDI 1999 (bbcache), which also validated against UltraSPARC hardware counters; the advice-instead-of-transform posture and per-field counter attribution are Hundt, Mannarswamy and Chakrabarti, CGO 2006. What is new here is only the delivery: source level, no debug info, whole repo, ranked. TWO HONEST LIMITS. (1) Static access counts are NOT dynamic frequency: one field in a hot loop beats fifty on cold paths and nothing static can tell them apart, so fns= is a FLOOR of DISTINCT INDEXED FUNCTIONS and w= is a call-graph reachability PROXY (sum of 1 + fan-in), never a measured frequency. Only member-access syntax (dot and arrow) is counted; a bare field name inside its own method is not, because a local of the same name is indistinguishable here. (2) True sizeof and alignment are unknowable from source under templates, virtuals, bases and the target ABI: all geometry is the layout verb's LP64 standard-layout MODEL, model="lp64-approx", and a definition it refused (modeled="0") contributes its affinity graph and NO geometry finding; why=names layout's own refusal kind(s) for THIS definition (bitfield/virtual/base-class/template/…, the layout verb's own legend names the class, this the instance). Exactly two findings fire, both with a defensible direction: split-line (co-accessed by 2+ functions at wt 0.00, so no field order can share a line) and straddle (one co-accessed field crossing a line boundary). Pack-tighter and sort-by-size advice is deliberately ABSENT: tight packing can induce false sharing, which is why the Go team keeps fieldalignment out of vet and gopls. ADVICE ONLY, never a transformation. validate= names the instrumented PROFILE_SCOPE whose counters would confirm the hypothesis; see docs/FIELDAFFINITY.md. PHASE A/B (report-only): as_* counts a corpus-wide, purely static for-loop advance-shape classification (index/chase/mixed/unknown, via astQuery TSQuery patterns, never execution); a chase-shaped field is disclosed on its <f> row as chase="1" loops="N", with shape_conf="self-ref"/"tmpl-approx" only when the field's OWN declared type textually self-references its aggregate. Refusals are per-cause: as_stem_ambiguous= chase field names declared by 2+ modeled aggregates, as_stem_unowned= by NONE (forward-declared/vendored traversal target), as_stem_nonptr= a sole owner whose declared type has no pointer/reference marker (provably not a raw-pointer chase target). as_query_capped=1 means the classification hit its query budget, making every as_* count a floor. NEVER ranking-affecting yet: the required real-corpus, blind-reviewed precision floor has not run, so sepcost= is IDENTICAL with or without this disclosure. See src/accessshape.h and docs/FIELDAFFINITY.md sec 8. -->
<fieldaffinity block="64" model="lp64-approx" counts_floor="1" weighting="fanin-floor" aggregates="931" files="229" fns_scanned="4740" accesses="8432" amb_skipped="16187" structs="506" shown="20" capped="1" findings="16" min_fns="2" as_loops="1849" as_index="4" as_chase="5" as_mixed="1" as_unknown=" … [line truncated: 76 more bytes on this line]
<s n="MainDispatch" p="src/main.cpp" l="489" agg="struct" modeled="1" fields="20" touched="15" fns="21" pairs="70" sepcost="108.25" findings="12" size="160" align="8" lines="3">
<f n="multiRoot" acc="13" fns="11" sz="1" off="32" ln="0"/>
<f n="ws" acc="7" fns="7" sz="8" off="40" ln="0"/>
<f n="fanInPtr" acc="6" fns="6" sz="8" off="56" ln="0"/>
<f n="qmetrics" acc="1" fns="1" sz="8" off="64" ln="1"/>
<f n="ampPtr" acc="7" fns="7" sz="8" off="72" ln="1"/>
<f n="cboPtr" acc="2" fns="2" sz="8" off="80" ln="1"/>
<f n="testedPtr" acc="8" fns="8" sz="8" off="88" ln="1"/>
<f n="lcom4Ptr" acc="2" fns="2" sz="8" off="96" ln="1"/>
<f n="impurePtr" acc="5" fns="5" sz="8" off="104" ln="1"/>
<f n="forChurn" acc="2" fns="2" sz="8" off="112" ln="1"/>
<f n="redactCounts" acc="10" fns="6" sz="8" off="120" ln="1"/>
<f n="redactPtr" acc="10" fns="9" sz="8" off="128" ln="2"/>
<f n="notesPtr" acc="10" fns="7" sz="8" off="136" ln="2"/>
<f n="grepPhases" acc="1" fns="1" sz="8" off="144" ln="2"/>
<f n="valueUses" acc="2" fns="2" sz="1" off="152" ln="2"/>
<pair a="ampPtr" b="testedPtr" fns="7" w="7" dist="16" wt="0.75"/>
<pair a="multiRoot" b="ws" fns="7" w="7" dist="8" wt="0.88"/>
<pair a="testedPtr" b="notesPtr" fns="6" w="6" dist="48" wt="0.25"/>
<pair a="fanInPtr" b="testedPtr" fns="6" w="6" dist="32" wt="0.50"/>
<pair a="fanInPtr" b="ampPtr" fns="6" w="6" dist="16" wt="0.75"/>
<pair a="redactCounts" b="redactPtr" fns="6" w="6" dist="8" wt="0.88"/>
<pair a="fanInPtr" b="notesPtr" fns="5" w="5" dist="80" wt="0.00"/>
<pair a="fanInPtr" b="redactPtr" fns="5" w="5" dist="72" wt="0.00"/>
<pair a="fanInPtr" b="redactCounts" fns="5" w="5" dist="64" wt="0.00"/>
<pair a="ampPtr" b="notesPtr" fns="5" w="5" dist="64" wt="0.00"/>
<pair a="ampPtr" b="redactPtr" fns="5" w="5" dist="56" wt="0.12"/>
<pair a="fanInPtr" b="impurePtr" fns="5" w="5" dist="48" wt="0.25"/>
… [493 more display lines; full output is 43605 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --field-affinity=Symbol`

*The same lens narrowed to ONE struct — the one --layout=Symbol shows the offsets for.*

`````
<!-- ripwire field-affinity: which fields are READ TOGETHER but declared far apart, diffed against 64-byte cache-line geometry. PRIOR ART, claimed by NOBODY here as new: the field affinity graph, the static field-access enumeration without pointer analysis, and the separation weight wt(fi,fj) = (block - dist)/block are Chilimbi, Davidson and Larus, Cache-Conscious Structure Definition, PLDI 1999 (bbcache), which also validated against UltraSPARC hardware counters; the advice-instead-of-transform posture and per-field counter attribution are Hundt, Mannarswamy and Chakrabarti, CGO 2006. What is new here is only the delivery: source level, no debug info, whole repo, ranked. TWO HONEST LIMITS. (1) Static access counts are NOT dynamic frequency: one field in a hot loop beats fifty on cold paths and nothing static can tell them apart, so fns= is a FLOOR of DISTINCT INDEXED FUNCTIONS and w= is a call-graph reachability PROXY (sum of 1 + fan-in), never a measured frequency. Only member-access syntax (dot and arrow) is counted; a bare field name inside its own method is not, because a local of the same name is indistinguishable here. (2) True sizeof and alignment are unknowable from source under templates, virtuals, bases and the target ABI: all geometry is the layout verb's LP64 standard-layout MODEL, model="lp64-approx", and a definition it refused (modeled="0") contributes its affinity graph and NO geometry finding; why=names layout's own refusal kind(s) for THIS definition (bitfield/virtual/base-class/template/…, the layout verb's own legend names the class, this the instance). Exactly two findings fire, both with a defensible direction: split-line (co-accessed by 2+ functions at wt 0.00, so no field order can share a line) and straddle (one co-accessed field crossing a line boundary). Pack-tighter and sort-by-size advice is deliberately ABSENT: tight packing can induce false sharing, which is why the Go team keeps fieldalignment out of vet and gopls. ADVICE ONLY, never a transformation. validate= names the instrumented PROFILE_SCOPE whose counters would confirm the hypothesis; see docs/FIELDAFFINITY.md. PHASE A/B (report-only): as_* counts a corpus-wide, purely static for-loop advance-shape classification (index/chase/mixed/unknown, via astQuery TSQuery patterns, never execution); a chase-shaped field is disclosed on its <f> row as chase="1" loops="N", with shape_conf="self-ref"/"tmpl-approx" only when the field's OWN declared type textually self-references its aggregate. Refusals are per-cause: as_stem_ambiguous= chase field names declared by 2+ modeled aggregates, as_stem_unowned= by NONE (forward-declared/vendored traversal target), as_stem_nonptr= a sole owner whose declared type has no pointer/reference marker (provably not a raw-pointer chase target). as_query_capped=1 means the classification hit its query budget, making every as_* count a floor. NEVER ranking-affecting yet: the required real-corpus, blind-reviewed precision floor has not run, so sepcost= is IDENTICAL with or without this disclosure. See src/accessshape.h and docs/FIELDAFFINITY.md sec 8. -->
<fieldaffinity block="64" model="lp64-approx" counts_floor="1" weighting="fanin-floor" aggregates="931" files="229" fns_scanned="4740" accesses="8432" amb_skipped="16187" structs="1" shown="1" capped="0" findings="0" min_fns="2" as_loops="1849" as_index="4" as_chase="5" as_mixed="1" as_unknown="1839 … [line truncated: 85 more bytes on this line]
<s n="Symbol" p="src/model.h" l="224" agg="struct" modeled="0" fields="23" touched="2" fns="69" pairs="1" sepcost="0.00" findings="0" why="compound-type,unknown-type">
<f n="sigStartByte" acc="132" fns="53" sz="4" placed="0"/>
<f n="sigEndByte" acc="55" fns="37" sz="4" placed="0"/>
<pair a="sigStartByte" b="sigEndByte" fns="21" w="21" measured="0"/>
<fn n="computeCommentCoherence" p="src/commentcoherence.h" l="166" fanin="0" touched="2" f="sigStartByte,sigEndByte"/>
<fn n="readerTokensOf" p="src/contextratio.h" l="125" fanin="0" touched="2" f="sigStartByte,sigEndByte"/>
<fn n="assignFields" p="src/ingest_model.h" l="178" fanin="0" touched="2" f="sigStartByte,sigEndByte"/>
<fn n="assignSymbols" p="src/ingest_model.h" l="208" fanin="0" touched="2" f="sigStartByte,sigEndByte" scope="ingest/build-model: lex stats CSR + file signatures (B0)"/>
<fn n="packConnect" p="src/mcpverbs.h" l="2684" fanin="0" touched="2" f="sigStartByte,sigEndByte"/>
<fn n="namingLensChecks" p="src/naminglens.h" l="1075" fanin="0" touched="2" f="sigStartByte,sigEndByte" scope="naminglens: final sort"/>
<fn n="resolveD1Signature" p="src/packtask.h" l="571" fanin="0" touched="2" f="sigStartByte,sigEndByte"/>
<fn n="computeReadability" p="src/readability.h" l="117" fanin="0" touched="2" f="sigStartByte,sigEndByte"/>
<validate scopes="7" status="instrumented" counter="l1d-cache-misses">
<scope n="buildGraph: resolve refs + build CSR"/>
<scope n="ingest/build-model: lex stats CSR + file signatures (B0)"/>
<scope n="lexical: pass 2 via persisted subtoken stats (cached tf/dl, no corpus re-tokenize)"/>
<scope n="lint: mergeCachePack"/>
<scope n="naminglens/sym: checkNameInformativenessInBytes"/>
<scope n="naminglens: checkScopeGroups (series + confusable)"/>
<scope n="naminglens: final sort"/>
</validate>
</s>
</fieldaffinity>
`````

## `./build/ripwire . --naming-consistency --limit=8`

*The corpus's OWN case-convention vote per (language, kind) group; off-convention names get a mechanical propose= (a suggestion, never a blind rename).*

`````
<!-- ripwire naming-consistency: TIER A convention normalization (NOTES.md section 9.2): the corpus's OWN case-convention choice, voted per (language, kind) group among MULTI-TOKEN eligible names (a single-token name, or one split only on digit boundaries, carries no case signal and is silently excluded from both voting and flagging). A group DECIDES only when its leading style clears both a sample floor and an agreement floor; short of either it reports style=UNAVAILABLE with why= naming which bar it missed, never a guessed winner. Every off-convention name in a DECIDED group gets propose=: its OWN subtokens mechanically recombined into the dominant style: no dictionary, no synonym judgment, so this is safe to suggest for that reason alone. propose= is a SUGGESTION, never a safe-to-blind-apply rename: an actual rename needs the uses verb to prove the complete reference set first. A mixed name (naming-case's own finding: a snake separator AND a camel transition inside ONE identifier) never wins a vote and is always flagged when its group has a decided convention. Exit 0 always: a lens, not a gate. groups=(language,kind) pairs with at least one styled name candidates=styled names scanned decided=groups that cleared both floors flagged=off-convention names in decided groups g rows: lang= kind=fn|var style=the group's dominant convention, or UNAVAILABLE agree=leading-style votes total=all voting-style votes in this group why=insufficient-sample|no-clear-convention when style is UNAVAILABLE (absent otherwise) f rows: p=path:line n=name lang= kind=fn|var style=this name's own convention (mixed for the internally inconsistent case) propose=the mechanically recombined form in the group's dominant style. Pages limit=N (offset=M); default 40 rows, shown= capped= disclose the cut, and a cut listing carries total=/has_more=/next_offset= so a paging loop can continue from it. -->
<!-- root= on this element is the crawl root every p= below is RELATIVE to (single-root runs only; absent => p= is the path ingest itself used, unchanged). -->
<naming-consistency groups="26" candidates="6062" decided="6" flagged="275" shown="8" capped="1" total="275" has_more="1" next_offset="8" offset="0" limit="8" root=".">
<g lang="cpp" kind="fn" style="camel" agree="3061" total="3257"/>
<g lang="cpp" kind="var" style="camel" agree="731" total="740"/>
<g lang="py" kind="fn" style="snake" agree="580" total="595"/>
<g lang="py" kind="var" style="UNAVAILABLE" why="no-clear-convention" total="333"/>
<g lang="ts" kind="fn" style="camel" agree="37" total="38"/>
<g lang="ts" kind="var" style="UNAVAILABLE" why="insufficient-sample" total="5"/>
<g lang="go" kind="fn" style="UNAVAILABLE" why="insufficient-sample" total="11"/>
<g lang="go" kind="var" style="UNAVAILABLE" why="insufficient-sample" total="2"/>
<g lang="rs" kind="fn" style="UNAVAILABLE" why="no-clear-convention" total="49"/>
<g lang="rs" kind="var" style="UNAVAILABLE" why="insufficient-sample" total="4"/>
<g lang="swift" kind="fn" style="UNAVAILABLE" why="insufficient-sample" total="19"/>
<g lang="swift" kind="var" style="UNAVAILABLE" why="insufficient-sample" total="17"/>
<g lang="objc" kind="fn" style="UNAVAILABLE" why="insufficient-sample" total="10"/>
<g lang="js" kind="fn" style="camel" agree="19" total="20"/>
<g lang="js" kind="var" style="UNAVAILABLE" why="insufficient-sample" total="3"/>
<g lang="sh" kind="fn" style="UNAVAILABLE" why="no-clear-convention" total="644"/>
<g lang="java" kind="fn" style="UNAVAILABLE" why="insufficient-sample" total="12"/>
<g lang="java" kind="var" style="UNAVAILABLE" why="insufficient-sample" total="1"/>
<g lang="rb" kind="fn" style="UNAVAILABLE" why="insufficient-sample" total="11"/>
<g lang="rb" kind="var" style="UNAVAILABLE" why="insufficient-sample" total="2"/>
<g lang="cs" kind="fn" style="UNAVAILABLE" why="insufficient-sample" total="12"/>
<g lang="cs" kind="var" style="UNAVAILABLE" why="insufficient-sample" total="3"/>
<g lang="c" kind="fn" style="camel" agree="212" total="215"/>
<g lang="c" kind="var" style="UNAVAILABLE" why="insufficient-sample" total="5"/>
<g lang="php" kind="fn" style="UNAVAILABLE" why="insufficient-sample" total="2"/>
<g lang="php" kind="var" style="UNAVAILABLE" why="insufficient-sample" total="1"/>
<f p="bench/agentloop/editsuite/fixture/geometry.cpp:5" n="area_of_triangle" lang="cpp" kind="fn" style="snake" propose="areaOfTriangle"/>
<f p="bench/agentloop/editsuite/fixture/geometry.cpp:27" n="scale_point" lang="cpp" kind="fn" style="snake" propose="scalePoint"/>
<f p="src/atoms.h:112" n="SpanIndex" lang="cpp" kind="fn" style="pascal" propose="spanIndex"/>
<f p="src/atoms.h:177" n="OwnerIndex" lang="cpp" kind="fn" style="pascal" propose="ownerIndex"/>
<f p="src/cachelint.h:169" n="LoopIndex" lang="cpp" kind="fn" style="pascal" propose="loopIndex"/>
<f p="src/crossref.h:590" n="BlobStore" lang="cpp" kind="fn" style="pascal" propose="blobStore"/>
<f p="src/gitmine.h:2077" n="StaticIncludeCoupling" lang="cpp" kind="fn" style="pascal" propose="staticIncludeCoupling"/>
<f p="src/graph.h:3775" n="UnionFind" lang="cpp" kind="fn" style="pascal" propose="unionFind"/>
</naming-consistency>
`````

## `./build/ripwire . --naming-calibration`

*Score the naming-* rules against this repo's own rename history: proxy=old/(old+new) per rule, 0.50 = chance; read pairs= (sample size) first.*

**wall time: 2.54s**

`````
<!-- ripwire naming-calibration: each naming lint rule scored against this repo's OWN rename history. A NOISY PROXY, and that is the headline, not a footnote: developers rename for reasons that have nothing to do with name quality (rebrands, moves, API changes, type changes, reverts), so a pair labelled old to new is only WEAK evidence that the old spelling was the worse one. Read pairs= first; a small sample means nothing whatever the proxy says. pairs=labelled rename pairs that survived the join, the SAMPLE SIZE for every number below candidates=raw substitutions mined from the patch stream, before the join commits=commits walked hunks=diff hunks with content on both sides wide_hunks=hunks dropped for exceeding the per-side pairing cap drop_old_alive=candidates dropped because the old spelling is still an indexed name (so it was not renamed away) drop_new_absent=candidates dropped because the new spelling is no eligible indexed symbol at HEAD drop_ambiguous=candidates dropped because a name appeared on both sides of several candidates (a split, rework or revert) drop_old_skipped=candidates dropped because the lens would skip the old spelling, so no rule could ever have fired on it truncated=1 when a walk bound was hit, which makes candidates= a FLOOR probed=0 when there is no history to mine; r= says why the root's own at= is the git commit these numbers were computed at (a trailing +dirty means the working tree differed from that commit); a p row's at= below is unrelated — a path:line location, not a commit r rows: n=rule name old=pairs where the rule fired on the ABANDONED spelling new=pairs where it fired on the CHOSEN spelling fired=old+new proxy=old/fired, the crude precision proxy, absent when fired=0 (0.50 is exactly chance: a rule that fires equally on both spellings has no signal) scope=group-rule marks a rule that fires on a RELATIONSHIP between co-visible names, which one pair cannot carry evidence about; it is reported unscored rather than as a meaningless 0/0. p rows: one labelled pair. o=old spelling n=new spelling sup=distinct hunks that showed the substitution at=path:line of the symbol the pair joined to old_fires=rules that fired on the old spelling new_fires=rules that fired on the new spelling (both absent when empty) -->
<naming-calibration probed="1" pairs="37" candidates="622" commits="1398" hunks="25474" wide_hunks="333" drop_old_alive="105" drop_new_absent="471" drop_ambiguous="9" drop_old_skipped="0" at="c7725f3ef">
<r n="naming-short" old="1" new="1" fired="2" proxy="0.500"/>
<r n="naming-wordy" old="0" new="0" fired="0"/>
<r n="naming-series" scope="group-rule"/>
<r n="naming-underscore" old="0" new="0" fired="0"/>
<r n="naming-case" old="0" new="0" fired="0"/>
<r n="naming-predicate" old="0" new="0" fired="0"/>
<r n="naming-setter" old="0" new="0" fired="0"/>
<r n="naming-confusable" scope="group-rule"/>
<p o="ARM_CTXPACK" n="ARM_RIPWIRE" sup="3" at="./bench/agentloop/analyze.py:31"/>
<p o="CTXPACK" n="RIPWIRE" sup="12" at="./bench/headtohead/r3-headroom-2026-08-03/harness.py:42"/>
<p o="CTXPACK_BASH_RE" n="RIPWIRE_BASH_RE" sup="1" at="./bench/mine_traces.py:47"/>
<p o="CTXPACK_REPO" n="RIPWIRE_REPO" sup="4" at="./bench/headtohead/r2-2026-08-03/worker.py:20"/>
<p o="advice" n="next" sup="1" at="./bench/bench_svector_diff.cpp:76"/>
<p o="atomicWriteQSnap" n="atomicWriteFile" sup="5" at="./src/quality.h:2252"/>
<p o="checkNotSurprising" n="fixNotSurprising" sup="1" at="./test/cochangesurprisecheck.sh:154"/>
<p o="cmake" n="cmake_cc" sup="1" at="./test/optremarkscheck.sh:160"/>
<p o="constant" n="field" sup="1" at="./hooks/ripwire-nudge.sh:1082"/>
<p o="control" n="retired" sup="1" at="./test/truncvocabcheck.sh:331"/>
<p o="copyRange" n="moveRange" sup="2" at="./src/infra/svector.h:130"/>
<p o="cpuRelax" n="isFiniteFast" sup="1" at="./src/infra/fastmath.h:37"/>
<p o="ctxpack_context" n="ripwire_context" sup="2" at="./bench/swebench_eval.py:36"/>
<p o="enclosingBlockSpan" n="enclosingShadowScope" sup="2" at="./src/ingest_binds.h:759"/>
<p o="fired" n="dedup" sup="1" at="./bench/mine_traces.py:266"/>
<p o="fixture" n="example" sup="2" at="./bench/scip_match_diag.py:246"/>
<p o="for_files" n="for_json" sup="1" at="./bench/arb/run_arb.py:224"/>
<p o="four" n="arm" sup="1" at="./src/mcpindex.h:275"/>
<p o="ge" n="gt" sup="1" at="./test/cppqualdecoyfix/decoy.cpp:70" old_fires="naming-short" new_fires="naming-short"/>
<p o="install_hook" n="install_claude_hook" sup="1" at="./skills/install.sh:104"/>
… [18 more display lines; full output is 5783 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --lint --naming-locals`

*The opt-in --lint modifier: naming predicates over LOCAL variable names too, C/C++ only, only inside functions already past a size/complexity gate.*

`````
<!-- ripwire lint: [AST]-only checks (descriptive facts, not gates). rule=the check; sev=user-rule severity; in=enclosing symbol NAME (the same spelling is a fan-in COUNT in for/pack-task/exemplar). A rule named atom-X is an atom of confusion (Gopstein, FSE 2017): a C-family shape that misleads READERS, C/C++/ObjC/CUDA only. Each rule is scanned under its OWN match budget, so no rule is ever starved by a noisier one. A rule that spends its whole budget carries count_capped="1" — its count= is then a FLOOR (that rule's raw captures reached the per-rule budget; only its own matches can cap it); findings_capped="1" on the root ⇒ at least one PRINTED rule row is a floor (never inherited from a rule lint-select/lint-ignore dropped), and the root then also carries counts_floor="1" and capped="1": findings= and total= are floors, rows exist that no page holds. Absent = nothing was capped and every count= is a total. raise the default cap with limit=N (offset=M pages; a cut listing carries total=/has_more=/next_offset= so a paging loop can continue from it). On the root, shown=/capped= are the ROW-COUNT pair (rows printed vs whether the DEFAULT payload byte-cap trimmed them, absent an explicit limit=) — a different fact from the per-rule count_capped="1" above, which is a MATCH-BUDGET floor on one rule's own count=; findings= is the true total unless findings_capped="1" floors it. A rule row's applicable="0" ⇒ NONE of its registered languages (the lint-catalog listing) are present in this corpus at all — its count="0" is structural inertness, never a measurement; the root's inert_rules=N tallies how many printed rows that is true for. lint-select=/lint-ignore=PREFIX[,...] narrow the printed rows to a family (e.g. cache-); the root then carries selected="K of N" plus the raw select=/ignore= you passed. naming_locals="1" on the root ⇒ the opt-in naming-locals modifier was on (the naming-* rules also read local variables inside already-flagged functions); absent ⇒ off, and the naming-* counts cover declarations only. Each rule row's own shown_rows=/rows_capped= is how many of THAT rule's rows fall inside the printed <f> window (the root's shown=/capped= trims a SORTED PREFIX of the combined findings, so a rule whose rows all sort past the cut carries shown_rows="0" rows_capped="1" while its count= stays the true total — never confuse a capped-away rule with one that measured zero); this is a DIFFERENT fact from the row's own count_capped="1" above (that rule's own raw-capture stream hit its per-rule match budget) — the two can disagree on the same row. A lint-rules row's compiled="0" ⇒ that rule's tree-sitter QUERY failed to compile for every linked grammar (a malformed or misspelled pattern) — its count="0" never ran at all, a different claim from applicable="0" above (a well-formed query whose declared language just is not in this corpus) and from an ordinary count="0" (a well-formed query that ran and found nothing); absent ⇒ the query compiled. -->
<lint findings="5035" shown="639" capped="1" total="5035" has_more="1" next_offset="639" offset="0" limit="0" counts_floor="1" findings_capped="1" naming_locals="1" root=".">
<rule name="c-style-cast" count="307" shown_rows="96" rows_capped="1"/>
<rule name="goto" count="3" shown_rows="1" rows_capped="1"/>
<rule name="do-while" count="5" shown_rows="0" rows_capped="1"/>
<rule name="unsafe-c-fn" count="0" shown_rows="0" rows_capped="0"/>
<rule name="weak-crypto" count="0" shown_rows="0" rows_capped="0"/>
<rule name="redundant-parens" count="0" shown_rows="0" rows_capped="0"/>
<rule name="suspicious-semicolon" count="0" shown_rows="0" rows_capped="0"/>
<rule name="typedef-over-using" count="12" shown_rows="0" rows_capped="1"/>
<rule name="magic-number" count="507" shown_rows="222" rows_capped="1" count_capped="1"/>
<rule name="empty-catch" count="1" shown_rows="0" rows_capped="1"/>
<rule name="self-assign" count="3" shown_rows="0" rows_capped="1"/>
<rule name="large-function" count="248" shown_rows="28" rows_capped="1"/>
<rule name="deep-nesting" count="232" shown_rows="26" rows_capped="1"/>
<rule name="inconsistent-return" count="1" shown_rows="0" rows_capped="1"/>
<rule name="unreachable-code" count="5" shown_rows="0" rows_capped="1"/>
<rule name="naming-short" count="2452" shown_rows="171" rows_capped="1"/>
<rule name="naming-wordy" count="102" shown_rows="11" rows_capped="1"/>
<rule name="naming-series" count="325" shown_rows="0" rows_capped="1"/>
<rule name="naming-underscore" count="0" shown_rows="0" rows_capped="0"/>
<rule name="naming-case" count="50" shown_rows="0" rows_capped="1"/>
<rule name="naming-predicate" count="0" shown_rows="0" rows_capped="0"/>
<rule name="naming-setter" count="1" shown_rows="0" rows_capped="1"/>
<rule name="naming-confusable" count="152" shown_rows="16" rows_capped="1"/>
<rule name="naming-uninformative" count="0" shown_rows="0" rows_capped="0"/>
<rule name="atom-comma-operator" count="1" shown_rows="0" rows_capped="1"/>
<rule name="atom-embedded-crement" count="90" shown_rows="6" rows_capped="1"/>
<rule name="atom-assign-as-value" count="48" shown_rows="6" rows_capped="1"/>
<rule name="atom-nested-ternary" count="75" shown_rows="5" rows_capped="1"/>
… [651 more display lines; full output is 73158 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --lint-catalog`

*The built-in rule registry — one row per rule with sev=/category=/rationale/lang=/since=; no corpus needed.*

`````
<!-- ripwire lint-catalog: the built-in lint rule registry, one row per rule, in the SAME order the plain lint run's own tally uses. sev/cat/rationale describe the rule; lang= is the language TOKEN SET (the spelling the lint-rules loader's own language: field accepts) whose grammar can ever satisfy this rule's query or scan — a STRUCTURAL ceiling, not which languages happen to be in any one corpus (that disclosure is the lint run's own applicable=/inert_rules=). since= is the ripwire release the rule first shipped in. -->
<lintcatalog rules="39">
<rule name="c-style-cast" sev="warn" cat="style" lang="cpp,c,objc,java,cs" since="v0.1.0">a C-style cast — cppcoreguidelines-pro-type-cstyle-cast prefers the explicit static_cast/const_cast/reinterpret_cast</rule>
<rule name="goto" sev="warn" cat="control-flow" lang="cpp,c,objc,go,cs" since="v0.1.0">a goto statement — cppcoreguidelines-avoid-goto</rule>
<rule name="do-while" sev="info" cat="style" lang="cpp,c,objc,ts,js,swift,java,cs" since="v0.1.0">a do/while loop shape (on Swift, its do/catch block shares the same grammar node and also matches)</rule>
<rule name="unsafe-c-fn" sev="error" cat="security" lang="cpp,c,objc,ts,js,go,rs" since="v0.1.0">a call to an unbounded C string function (strcpy/strcat/sprintf/gets)</rule>
<rule name="weak-crypto" sev="error" cat="security" lang="cpp,c,objc,ts,js,go,rs" since="v0.1.0">a call to a broken hash or cipher (MD5/SHA1/MD4/RC4)</rule>
<rule name="redundant-parens" sev="info" cat="style" lang="cpp,c,objc,py,ts,js,go,rs,java,cs" since="v0.1.0">a doubly-parenthesized expression — readability-redundant-parentheses</rule>
<rule name="suspicious-semicolon" sev="warn" cat="correctness" lang="cpp,c,objc" since="v0.1.0">an if-body that is just `;` — bugprone-suspicious-semicolon</rule>
<rule name="typedef-over-using" sev="info" cat="style" lang="cpp,c,objc" since="v0.1.0">a C-style typedef struct/union where `using` is preferred</rule>
<rule name="magic-number" sev="info" cat="maintainability" lang="cpp,c,objc" since="v0.1.0">a non-trivial numeric literal inside a function body, outside a const/constexpr init</rule>
<rule name="empty-catch" sev="warn" cat="error-masking" lang="cpp,c,objc" since="v0.1.0">a catch block with an empty body</rule>
<rule name="self-assign" sev="warn" cat="correctness" lang="cpp,c,objc,ts,js,rs,java,cs" since="v0.1.0">x = x — almost always a copy-paste bug</rule>
<rule name="large-function" sev="info" cat="maintainability" lang="cpp,c" since="v0.1.0">a function body over 80 lines</rule>
<rule name="deep-nesting" sev="info" cat="maintainability" lang="cpp,c" since="v0.1.0">brace nesting depth over 4 inside a function body</rule>
<rule name="inconsistent-return" sev="info" cat="maintainability" lang="cpp,c" since="v0.1.0">a bare `return;` mixed with a value-returning return in the same function</rule>
<rule name="unreachable-code" sev="warn" cat="correctness" lang="cpp,c,objc,py,ts,js,go,java,cs" since="v0.1.0">a statement after an unconditional return/break/continue/throw/raise in the same block</rule>
<rule name="naming-short" sev="info" cat="naming" lang="cpp,c,objc,py,ts,js,go,rs,swift,java,cs,rb,sh,php,lua" since="v0.2.2">a 1-2 letter Function/Method/Var name — visible far beyond any tiny scope [Beniamini/Hofmeister]</rule>
<rule name="naming-wordy" sev="info" cat="naming" lang="cpp,c,objc,py,ts,js,go,rs,swift,java,cs,rb,sh,php,lua" since="v0.2.2">more than 5 split tokens in one name [Butler; AlSuhaibani]</rule>
<rule name="naming-series" sev="info" cat="naming" lang="cpp,c,objc,py,ts,js,go,rs,swift,java,cs,rb,sh,php,lua" since="v0.2.2">foo1/foo2/... digit-suffix siblings sharing a base name in one scope [Butler]</rule>
<rule name="naming-underscore" sev="info" cat="naming" lang="cpp,c,objc,py,ts,js,go,rs,swift,java,cs,rb,sh,php,lua" since="v0.2.2">internal consecutive underscores, or a C-family reserved __x/_X form [Butler]</rule>
<rule name="naming-case" sev="info" cat="naming" lang="cpp,c,objc,py,ts,js,go,rs,swift,java,cs,rb,sh,php,lua" since="v0.2.2">snake_case and camelCase mixed inside one name [Butler]</rule>
<rule name="naming-predicate" sev="info" cat="naming" lang="cpp,c,objc,py,ts,js,go,rs,swift,java,cs,rb,sh,php,lua" since="v0.2.2">an is/has/can/should/was-prefixed name whose KNOWN return type is not bool-like [LAPD A2]</rule>
<rule name="naming-setter" sev="info" cat="naming" lang="cpp,c,objc,py,ts,js,go,rs,swift,java,cs,rb,sh,php,lua" since="v0.2.2">a set-prefixed name whose KNOWN return type is not void-like [LAPD A3]</rule>
<rule name="naming-confusable" sev="info" cat="naming" lang="cpp,c,objc,py,ts,js,go,rs,swift,java,cs,rb,sh,php,lua" since="v0.2.2">a co-visible pair within edit distance &lt;=2, reordered tokens, or a bare/digit-suffixed twin [Namesake]</rule>
<rule name="naming-uninformative" sev="info" cat="naming" lang="cpp,c,objc,py,ts,js,go,rs,swift,java,cs,rb,sh,php,lua" since="v0.2.2">every split subtoken is corpus-ubiquitous (BM25 idf) on a body past the size floor — fires only at the low end [Sparck Jones 1972]</rule>
<rule name="atom-comma-operator" sev="info" cat="readability" lang="cpp,c,objc" since="v0.2.2">the comma operator inside an expression (never a for-header comma) [Gopstein FSE 2017]</rule>
<rule name="atom-embedded-crement" sev="info" cat="readability" lang="cpp,c,objc" since="v0.2.2">++/-- evaluated inside a larger expression (never a whole statement) [Gopstein FSE 2017]</rule>
<rule name="atom-assign-as-value" sev="info" cat="readability" lang="cpp,c,objc" since="v0.2.2">an assignment whose VALUE is consumed (a condition, an argument, ...) [Gopstein FSE 2017]</rule>
<rule name="atom-nested-ternary" sev="info" cat="readability" lang="cpp,c,objc" since="v0.2.2">a conditional expression inside a conditional expression [Gopstein FSE 2017]</rule>
… [12 more display lines; full output is 7932 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --lint --lint-select=cache-`

*Run ONLY one rule family; the root carries selected="K of N" so a filtered zero is never confusable with an unfiltered one.*

`````
<!-- ripwire lint: [AST]-only checks (descriptive facts, not gates). rule=the check; sev=user-rule severity; in=enclosing symbol NAME (the same spelling is a fan-in COUNT in for/pack-task/exemplar). A rule named atom-X is an atom of confusion (Gopstein, FSE 2017): a C-family shape that misleads READERS, C/C++/ObjC/CUDA only. Each rule is scanned under its OWN match budget, so no rule is ever starved by a noisier one. A rule that spends its whole budget carries count_capped="1" — its count= is then a FLOOR (that rule's raw captures reached the per-rule budget; only its own matches can cap it); findings_capped="1" on the root ⇒ at least one PRINTED rule row is a floor (never inherited from a rule lint-select/lint-ignore dropped), and the root then also carries counts_floor="1" and capped="1": findings= and total= are floors, rows exist that no page holds. Absent = nothing was capped and every count= is a total. raise the default cap with limit=N (offset=M pages; a cut listing carries total=/has_more=/next_offset= so a paging loop can continue from it). On the root, shown=/capped= are the ROW-COUNT pair (rows printed vs whether the DEFAULT payload byte-cap trimmed them, absent an explicit limit=) — a different fact from the per-rule count_capped="1" above, which is a MATCH-BUDGET floor on one rule's own count=; findings= is the true total unless findings_capped="1" floors it. A rule row's applicable="0" ⇒ NONE of its registered languages (the lint-catalog listing) are present in this corpus at all — its count="0" is structural inertness, never a measurement; the root's inert_rules=N tallies how many printed rows that is true for. lint-select=/lint-ignore=PREFIX[,...] narrow the printed rows to a family (e.g. cache-); the root then carries selected="K of N" plus the raw select=/ignore= you passed. naming_locals="1" on the root ⇒ the opt-in naming-locals modifier was on (the naming-* rules also read local variables inside already-flagged functions); absent ⇒ off, and the naming-* counts cover declarations only. Each rule row's own shown_rows=/rows_capped= is how many of THAT rule's rows fall inside the printed <f> window (the root's shown=/capped= trims a SORTED PREFIX of the combined findings, so a rule whose rows all sort past the cut carries shown_rows="0" rows_capped="1" while its count= stays the true total — never confuse a capped-away rule with one that measured zero); this is a DIFFERENT fact from the row's own count_capped="1" above (that rule's own raw-capture stream hit its per-rule match budget) — the two can disagree on the same row. A lint-rules row's compiled="0" ⇒ that rule's tree-sitter QUERY failed to compile for every linked grammar (a malformed or misspelled pattern) — its count="0" never ran at all, a different claim from applicable="0" above (a well-formed query whose declared language just is not in this corpus) and from an ordinary count="0" (a well-formed query that ran and found nothing); absent ⇒ the query compiled. -->
<lint findings="400" shown="400" capped="0" selected="8 of 39" select="cache-" root=".">
<rule name="cache-node-container" count="16" shown_rows="16" rows_capped="0"/>
<rule name="cache-vector-of-raw-ptr" count="32" shown_rows="32" rows_capped="0"/>
<rule name="cache-vector-of-indirect" count="133" shown_rows="133" rows_capped="0"/>
<rule name="cache-heap-alloc-in-loop" count="3" shown_rows="3" rows_capped="0"/>
<rule name="cache-pointer-chase-loop" count="8" shown_rows="8" rows_capped="0"/>
<rule name="cache-gather-subscript" count="203" shown_rows="203" rows_capped="0"/>
<rule name="cache-shared-ptr-by-value" count="2" shown_rows="2" rows_capped="0"/>
<rule name="cache-manual-prefetch" count="3" shown_rows="3" rows_capped="0"/>
<f rule="cache-vector-of-indirect" p="bench/agentloop/editsuite/fixture/matrix.cpp:3" in="">vector&lt;std::vector&lt;double&gt;&gt;</f>
<f rule="cache-gather-subscript" p="bench/bench_chase_ab.cpp:106" in="linkChain">nodes[ perm[i] ]</f>
<f rule="cache-gather-subscript" p="bench/bench_chase_ab.cpp:106" in="linkChain">nodes[ perm[ i + 1 ] ]</f>
<f rule="cache-pointer-chase-loop" p="bench/bench_chase_ab.cpp:118" in="chase">p = p-&gt;next</f>
<f rule="cache-node-container" p="bench/bench_convergence.cpp:40" in="">map</f>
<f rule="cache-gather-subscript" p="bench/bench_convergence.cpp:77" in="main">byName[ symN[i] ]</f>
<f rule="cache-vector-of-indirect" p="bench/bench_convergence.cpp:82" in="tBuckets">vector&lt;std::vector&lt;std::vector&lt;std::uint32_t&gt;&gt;&gt;</f>
<f rule="cache-vector-of-indirect" p="bench/bench_convergence.cpp:82" in="tBuckets">vector&lt;std::vector&lt;std::uint32_t&gt;&gt;</f>
<f rule="cache-gather-subscript" p="bench/bench_convergence.cpp:97" in="main">m[ symN[id] ]</f>
<f rule="cache-vector-of-indirect" p="bench/bench_newline_ab.cpp:279" in="main">vector&lt;std::vector&lt;double&gt;&gt;</f>
<f rule="cache-gather-subscript" p="bench/bench_ordered_map.cpp:89" in="aggregateMax">m[ in.keys[ i ] ]</f>
<f rule="cache-node-container" p="bench/bench_svector3.cpp:62" in="">map</f>
<f rule="cache-vector-of-indirect" p="bench/bench_svector3.cpp:85" in="tBuckets">vector&lt;std::vector&lt;std::vector&lt;std::uint32_t&gt;&gt;&gt;</f>
<f rule="cache-vector-of-indirect" p="bench/bench_svector3.cpp:85" in="tBuckets">vector&lt;std::vector&lt;std::uint32_t&gt;&gt;</f>
<f rule="cache-gather-subscript" p="bench/bench_svector3.cpp:95" in="main">m[ symN[id] ]</f>
<f rule="cache-node-container" p="bench/bench_svector_wave.cpp:94" in="">map</f>
<f rule="cache-gather-subscript" p="bench/bench_svector_wave.cpp:155" in="build">m[ g_pool[ g_keyOf[i] ] ]</f>
<f rule="cache-gather-subscript" p="bench/bench_svector_wave.cpp:162" in="readSize">g_pool[ g_readOf[i] ]</f>
<f rule="cache-gather-subscript" p="bench/bench_svector_wave.cpp:172" in="readIterate">g_pool[ g_readOf[i] ]</f>
<f rule="cache-gather-subscript" p="bench/bench_svector_wave.cpp:184" in="rehash">m[ g_pool[i] ]</f>
… [381 more display lines; full output is 48611 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --lint --lint-ignore=naming-,cache-`

*DROP two families, applied after selection; the raw select=/ignore= you passed rides on the root.*

`````
<!-- ripwire lint: [AST]-only checks (descriptive facts, not gates). rule=the check; sev=user-rule severity; in=enclosing symbol NAME (the same spelling is a fan-in COUNT in for/pack-task/exemplar). A rule named atom-X is an atom of confusion (Gopstein, FSE 2017): a C-family shape that misleads READERS, C/C++/ObjC/CUDA only. Each rule is scanned under its OWN match budget, so no rule is ever starved by a noisier one. A rule that spends its whole budget carries count_capped="1" — its count= is then a FLOOR (that rule's raw captures reached the per-rule budget; only its own matches can cap it); findings_capped="1" on the root ⇒ at least one PRINTED rule row is a floor (never inherited from a rule lint-select/lint-ignore dropped), and the root then also carries counts_floor="1" and capped="1": findings= and total= are floors, rows exist that no page holds. Absent = nothing was capped and every count= is a total. raise the default cap with limit=N (offset=M pages; a cut listing carries total=/has_more=/next_offset= so a paging loop can continue from it). On the root, shown=/capped= are the ROW-COUNT pair (rows printed vs whether the DEFAULT payload byte-cap trimmed them, absent an explicit limit=) — a different fact from the per-rule count_capped="1" above, which is a MATCH-BUDGET floor on one rule's own count=; findings= is the true total unless findings_capped="1" floors it. A rule row's applicable="0" ⇒ NONE of its registered languages (the lint-catalog listing) are present in this corpus at all — its count="0" is structural inertness, never a measurement; the root's inert_rules=N tallies how many printed rows that is true for. lint-select=/lint-ignore=PREFIX[,...] narrow the printed rows to a family (e.g. cache-); the root then carries selected="K of N" plus the raw select=/ignore= you passed. naming_locals="1" on the root ⇒ the opt-in naming-locals modifier was on (the naming-* rules also read local variables inside already-flagged functions); absent ⇒ off, and the naming-* counts cover declarations only. Each rule row's own shown_rows=/rows_capped= is how many of THAT rule's rows fall inside the printed <f> window (the root's shown=/capped= trims a SORTED PREFIX of the combined findings, so a rule whose rows all sort past the cut carries shown_rows="0" rows_capped="1" while its count= stays the true total — never confuse a capped-away rule with one that measured zero); this is a DIFFERENT fact from the row's own count_capped="1" above (that rule's own raw-capture stream hit its per-rule match budget) — the two can disagree on the same row. A lint-rules row's compiled="0" ⇒ that rule's tree-sitter QUERY failed to compile for every linked grammar (a malformed or misspelled pattern) — its count="0" never ran at all, a different claim from applicable="0" above (a well-formed query whose declared language just is not in this corpus) and from an ordinary count="0" (a well-formed query that ran and found nothing); absent ⇒ the query compiled. -->
<lint findings="1553" shown="729" capped="1" total="1553" has_more="1" next_offset="729" offset="0" limit="0" counts_floor="1" findings_capped="1" selected="22 of 39" ignore="naming-,cache-" root=".">
<rule name="c-style-cast" count="307" shown_rows="118" rows_capped="1"/>
<rule name="goto" count="3" shown_rows="1" rows_capped="1"/>
<rule name="do-while" count="5" shown_rows="0" rows_capped="1"/>
<rule name="unsafe-c-fn" count="0" shown_rows="0" rows_capped="0"/>
<rule name="weak-crypto" count="0" shown_rows="0" rows_capped="0"/>
<rule name="redundant-parens" count="0" shown_rows="0" rows_capped="0"/>
<rule name="suspicious-semicolon" count="0" shown_rows="0" rows_capped="0"/>
<rule name="typedef-over-using" count="12" shown_rows="0" rows_capped="1"/>
<rule name="magic-number" count="507" shown_rows="431" rows_capped="1" count_capped="1"/>
<rule name="empty-catch" count="1" shown_rows="0" rows_capped="1"/>
<rule name="self-assign" count="3" shown_rows="1" rows_capped="1"/>
<rule name="large-function" count="248" shown_rows="58" rows_capped="1"/>
<rule name="deep-nesting" count="232" shown_rows="58" rows_capped="1"/>
<rule name="inconsistent-return" count="1" shown_rows="0" rows_capped="1"/>
<rule name="unreachable-code" count="5" shown_rows="0" rows_capped="1"/>
<rule name="atom-comma-operator" count="1" shown_rows="0" rows_capped="1"/>
<rule name="atom-embedded-crement" count="90" shown_rows="34" rows_capped="1"/>
<rule name="atom-assign-as-value" count="48" shown_rows="11" rows_capped="1"/>
<rule name="atom-nested-ternary" count="75" shown_rows="15" rows_capped="1"/>
<rule name="atom-implicit-predicate" count="3" shown_rows="2" rows_capped="1"/>
<rule name="atom-octal-literal" count="12" shown_rows="0" rows_capped="1"/>
<rule name="atom-reversed-subscript" count="0" shown_rows="0" rows_capped="0"/>
<f rule="magic-number" p="bench/agentloop/editsuite/fixture/geometry.cpp:7" in="area_of_triangle">0.5</f>
<f rule="magic-number" p="bench/bench_chase_ab.cpp:100" in="linkChain">1023u</f>
<f rule="large-function" p="bench/bench_chase_ab.cpp:161" in="main">main (90 lines)</f>
<f rule="magic-number" p="bench/bench_chase_ab.cpp:167" in="main">20</f>
<f rule="atom-implicit-predicate" p="bench/bench_chase_ab.cpp:234" in="main">delta &lt; 0.02 &amp;&amp; delta &gt; -0.02</f>
<f rule="magic-number" p="bench/bench_chase_ab.cpp:234" in="main">0.02</f>
… [724 more display lines; full output is 67013 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --lint --lint-select=cach-`

*An unresolvable PREFIX refuses (exit 1) with a did-you-mean from a real edit distance (one character off cache-).*

**exit code: 1**

`````
(empty)
`````

stderr:

`````
ripwire: --lint-select: 'cach-' matches no rule or family (did you mean 'cache-'?) — see --lint-catalog for the full registry
`````

## `./build/ripwire . --lint --lint-select=nosuchfamily`

*A PREFIX with no near miss at all: the refusal points at --lint-catalog instead of guessing.*

**exit code: 1**

`````
(empty)
`````

stderr:

`````
ripwire: --lint-select: 'nosuchfamily' matches no rule or family — see --lint-catalog for the full registry
`````

## `./build/ripwire . --lint --sarif`

*The SAME findings as SARIF 2.1.0 (what github/codeql-action/upload-sarif consumes) — pure re-serialization, results count == the native run's.*

`````
{"version":"2.1.0","$schema":"https://raw.githubusercontent.com/oasis-tcs/sarif-spec/master/Schemata/sarif-schema-2.1.0.json","runs":[{"tool":{"driver":{"name":"ripwire","rules":[{"id":"c-style-cast","shortDescription":{"text":"c-style-cast"},"properties":{"builtin":true,"capped":false,"applicable": … [line truncated: 7 more bytes on this line]
{"id":"goto","shortDescription":{"text":"goto"},"properties":{"builtin":true,"capped":false,"applicable":true}},
{"id":"do-while","shortDescription":{"text":"do-while"},"properties":{"builtin":true,"capped":false,"applicable":true}},
{"id":"unsafe-c-fn","shortDescription":{"text":"unsafe-c-fn"},"properties":{"builtin":true,"capped":false,"applicable":true}},
{"id":"weak-crypto","shortDescription":{"text":"weak-crypto"},"properties":{"builtin":true,"capped":false,"applicable":true}},
{"id":"redundant-parens","shortDescription":{"text":"redundant-parens"},"properties":{"builtin":true,"capped":false,"applicable":true}},
{"id":"suspicious-semicolon","shortDescription":{"text":"suspicious-semicolon"},"properties":{"builtin":true,"capped":false,"applicable":true}},
{"id":"typedef-over-using","shortDescription":{"text":"typedef-over-using"},"properties":{"builtin":true,"capped":false,"applicable":true}},
{"id":"magic-number","shortDescription":{"text":"magic-number"},"properties":{"builtin":true,"capped":true,"applicable":true}},
{"id":"empty-catch","shortDescription":{"text":"empty-catch"},"properties":{"builtin":true,"capped":false,"applicable":true}},
{"id":"self-assign","shortDescription":{"text":"self-assign"},"properties":{"builtin":true,"capped":false,"applicable":true}},
{"id":"large-function","shortDescription":{"text":"large-function"},"properties":{"builtin":true,"capped":false,"applicable":true}},
{"id":"deep-nesting","shortDescription":{"text":"deep-nesting"},"properties":{"builtin":true,"capped":false,"applicable":true}},
{"id":"inconsistent-return","shortDescription":{"text":"inconsistent-return"},"properties":{"builtin":true,"capped":false,"applicable":true}},
{"id":"unreachable-code","shortDescription":{"text":"unreachable-code"},"properties":{"builtin":true,"capped":false,"applicable":true}},
{"id":"naming-short","shortDescription":{"text":"naming-short"},"properties":{"builtin":true,"capped":false,"applicable":true}},
{"id":"naming-wordy","shortDescription":{"text":"naming-wordy"},"properties":{"builtin":true,"capped":false,"applicable":true}},
{"id":"naming-series","shortDescription":{"text":"naming-series"},"properties":{"builtin":true,"capped":false,"applicable":true}},
{"id":"naming-underscore","shortDescription":{"text":"naming-underscore"},"properties":{"builtin":true,"capped":false,"applicable":true}},
{"id":"naming-case","shortDescription":{"text":"naming-case"},"properties":{"builtin":true,"capped":false,"applicable":true}},
{"id":"naming-predicate","shortDescription":{"text":"naming-predicate"},"properties":{"builtin":true,"capped":false,"applicable":true}},
{"id":"naming-setter","shortDescription":{"text":"naming-setter"},"properties":{"builtin":true,"capped":false,"applicable":true}},
{"id":"naming-confusable","shortDescription":{"text":"naming-confusable"},"properties":{"builtin":true,"capped":false,"applicable":true}},
{"id":"naming-uninformative","shortDescription":{"text":"naming-uninformative"},"properties":{"builtin":true,"capped":false,"applicable":true}},
{"id":"atom-comma-operator","shortDescription":{"text":"atom-comma-operator"},"properties":{"builtin":true,"capped":false,"applicable":true}},
{"id":"atom-embedded-crement","shortDescription":{"text":"atom-embedded-crement"},"properties":{"builtin":true,"capped":false,"applicable":true}},
{"id":"atom-assign-as-value","shortDescription":{"text":"atom-assign-as-value"},"properties":{"builtin":true,"capped":false,"applicable":true}},
{"id":"atom-nested-ternary","shortDescription":{"text":"atom-nested-ternary"},"properties":{"builtin":true,"capped":false,"applicable":true}},
{"id":"atom-implicit-predicate","shortDescription":{"text":"atom-implicit-predicate"},"properties":{"builtin":true,"capped":false,"applicable":true}},
{"id":"atom-octal-literal","shortDescription":{"text":"atom-octal-literal"},"properties":{"builtin":true,"capped":false,"applicable":true}},
… [7681 more display lines; full output is 1060398 bytes on 1 raw line(s)]
`````

Parsed summary of the same SARIF (past the display cut):

`````
sarif 2.1.0 rules= 39 results= 3836
`````

## `./build/ripwire . --lint --sarif --limit=5`

*SARIF is always the FULL result set: paging alongside it refuses loudly.*

**exit code: 1**

`````
(empty)
`````

stderr:

`````
ripwire: --sarif always emits the full result set — drop --limit=N/--offset=M
`````

## `./build/ripwire . --dmm`

*The Delta Maintainability Model scalar for the WORKING TREE vs HEAD — recorded against a CLEAN tree (the sandbox section shows a real delta). UNAVAILABLE is a stated reason, never 0 or 1.*

`````
<!-- ripwire dmm: the Delta Maintainability Model (di Biase, Rastogi, Bruntink, van Deursen, TechDebt 2019), ONE comparable scalar per change. Thresholds and arithmetic are PyDriller's deltamaintainability reference implementation. A UNIT is a function or method definition WITH A BODY; its VOLUME is its line span. Per property a unit is LOW risk iff size: loc at most 15, complexity: cyclomatic at most 5, interfacing: params at most 2. good=volume of low-risk code ADDED plus high-risk code REMOVED bad=volume of low-risk code REMOVED plus high-risk code ADDED dmm=good/(good+bad), in [0,1]: 1.000 means every line this change moved made the code healthier. THIS IS A DELTA, NOT A LEVEL: editing bad code without growing it moves nothing and scores nothing, which is deliberate. dmm=UNAVAILABLE means good+bad was 0, i.e. the change moved no unit's size, complexity or parameter count, and is NEVER to be read as 1.000 or 0.000; reason= says which case it was. base=the earlier tree's commit target=the later tree's commit, or working-tree base_units= target_units= units measured on each side base_volume= target_volume= their total line span combine=how the root dmm= pools the three sub-scores (pooled = summed good over summed good+bad; the paper publishes the three separately and no aggregate, so this one is ripwire's) size_metric=physical-loc: volume is the definition's PHYSICAL line span, where the reference implementation uses non-comment non-blank lines, so a heavily commented unit crosses the size threshold here earlier at= is the git commit this comparison RAN at (HEAD, not base/target — those name what was compared); a trailing +dirty means the working tree differed from that commit available=0 when no score could be produced at all low_loc=/low_cx=/low_params= are the low-risk ceilings a unit is judged against (lines / cyclomatic complexity / parameters). p=one property row k=its name (size|complexity|interfacing) d_low=change in low-risk volume d_high=change in high-risk volume. Every indexed language and every indexed path counts, tests and fixtures included; params and cyclomatic complexity come from the index, so a definition whose grammar exposes no parameter list contributes params=0 and classifies LOW on interfacing. -->
<dmm base="c7725f3ef85892534460f952e35816caad67dac2" target="working-tree" at="c7725f3ef" available="0" combine="pooled" size_metric="physical-loc" low_loc="15" low_cx="5" low_params="2" dmm="UNAVAILABLE" good="0" bad="0" base_units="7979" base_volume="136527" target_units="7979" target_volume="1365 … [line truncated: 121 more bytes on this line]
<p k="size" dmm="UNAVAILABLE" good="0" bad="0" d_low="0" d_high="0"/>
<p k="complexity" dmm="UNAVAILABLE" good="0" bad="0" d_low="0" d_high="0"/>
<p k="interfacing" dmm="UNAVAILABLE" good="0" bad="0" d_low="0" d_high="0"/>
</dmm>
`````

## `./build/ripwire . --dmm=HEAD`

*The per-commit scalar: HEAD vs its first parent, with the three separately actionable sub-scores.*

**wall time: 1.69s**

`````
<!-- ripwire dmm: the Delta Maintainability Model (di Biase, Rastogi, Bruntink, van Deursen, TechDebt 2019), ONE comparable scalar per change. Thresholds and arithmetic are PyDriller's deltamaintainability reference implementation. A UNIT is a function or method definition WITH A BODY; its VOLUME is its line span. Per property a unit is LOW risk iff size: loc at most 15, complexity: cyclomatic at most 5, interfacing: params at most 2. good=volume of low-risk code ADDED plus high-risk code REMOVED bad=volume of low-risk code REMOVED plus high-risk code ADDED dmm=good/(good+bad), in [0,1]: 1.000 means every line this change moved made the code healthier. THIS IS A DELTA, NOT A LEVEL: editing bad code without growing it moves nothing and scores nothing, which is deliberate. dmm=UNAVAILABLE means good+bad was 0, i.e. the change moved no unit's size, complexity or parameter count, and is NEVER to be read as 1.000 or 0.000; reason= says which case it was. base=the earlier tree's commit target=the later tree's commit, or working-tree base_units= target_units= units measured on each side base_volume= target_volume= their total line span combine=how the root dmm= pools the three sub-scores (pooled = summed good over summed good+bad; the paper publishes the three separately and no aggregate, so this one is ripwire's) size_metric=physical-loc: volume is the definition's PHYSICAL line span, where the reference implementation uses non-comment non-blank lines, so a heavily commented unit crosses the size threshold here earlier at= is the git commit this comparison RAN at (HEAD, not base/target — those name what was compared); a trailing +dirty means the working tree differed from that commit available=0 when no score could be produced at all low_loc=/low_cx=/low_params= are the low-risk ceilings a unit is judged against (lines / cyclomatic complexity / parameters). p=one property row k=its name (size|complexity|interfacing) d_low=change in low-risk volume d_high=change in high-risk volume. Every indexed language and every indexed path counts, tests and fixtures included; params and cyclomatic complexity come from the index, so a definition whose grammar exposes no parameter list contributes params=0 and classifies LOW on interfacing. -->
<dmm base="58d67dc1eb61eccdc6b673ba84dc02801803537c" target="c7725f3ef85892534460f952e35816caad67dac2" at="c7725f3ef" available="0" combine="pooled" size_metric="physical-loc" low_loc="15" low_cx="5" low_params="2" dmm="UNAVAILABLE" good="0" bad="0" base_units="7979" base_volume="136527" target_unit … [line truncated: 149 more bytes on this line]
<p k="size" dmm="UNAVAILABLE" good="0" bad="0" d_low="0" d_high="0"/>
<p k="complexity" dmm="UNAVAILABLE" good="0" bad="0" d_low="0" d_high="0"/>
<p k="interfacing" dmm="UNAVAILABLE" good="0" bad="0" d_low="0" d_high="0"/>
</dmm>
`````

## `./build/ripwire . --dmm=HEAD~3..HEAD`

*The range form: tree HEAD vs tree HEAD~3.*

**wall time: 1.67s**

`````
<!-- ripwire dmm: the Delta Maintainability Model (di Biase, Rastogi, Bruntink, van Deursen, TechDebt 2019), ONE comparable scalar per change. Thresholds and arithmetic are PyDriller's deltamaintainability reference implementation. A UNIT is a function or method definition WITH A BODY; its VOLUME is its line span. Per property a unit is LOW risk iff size: loc at most 15, complexity: cyclomatic at most 5, interfacing: params at most 2. good=volume of low-risk code ADDED plus high-risk code REMOVED bad=volume of low-risk code REMOVED plus high-risk code ADDED dmm=good/(good+bad), in [0,1]: 1.000 means every line this change moved made the code healthier. THIS IS A DELTA, NOT A LEVEL: editing bad code without growing it moves nothing and scores nothing, which is deliberate. dmm=UNAVAILABLE means good+bad was 0, i.e. the change moved no unit's size, complexity or parameter count, and is NEVER to be read as 1.000 or 0.000; reason= says which case it was. base=the earlier tree's commit target=the later tree's commit, or working-tree base_units= target_units= units measured on each side base_volume= target_volume= their total line span combine=how the root dmm= pools the three sub-scores (pooled = summed good over summed good+bad; the paper publishes the three separately and no aggregate, so this one is ripwire's) size_metric=physical-loc: volume is the definition's PHYSICAL line span, where the reference implementation uses non-comment non-blank lines, so a heavily commented unit crosses the size threshold here earlier at= is the git commit this comparison RAN at (HEAD, not base/target — those name what was compared); a trailing +dirty means the working tree differed from that commit available=0 when no score could be produced at all low_loc=/low_cx=/low_params= are the low-risk ceilings a unit is judged against (lines / cyclomatic complexity / parameters). p=one property row k=its name (size|complexity|interfacing) d_low=change in low-risk volume d_high=change in high-risk volume. Every indexed language and every indexed path counts, tests and fixtures included; params and cyclomatic complexity come from the index, so a definition whose grammar exposes no parameter list contributes params=0 and classifies LOW on interfacing. -->
<dmm base="fc7164013e5480524cfea0de636388cd1d3d8316" target="c7725f3ef85892534460f952e35816caad67dac2" at="c7725f3ef" available="1" combine="pooled" size_metric="physical-loc" low_loc="15" low_cx="5" low_params="2" dmm="0.415" good="147" bad="207" base_units="7974" base_volume="136409" target_units= … [line truncated: 30 more bytes on this line]
<p k="size" dmm="0.169" good="20" bad="98" d_low="20" d_high="98"/>
<p k="complexity" dmm="0.559" good="66" bad="52" d_low="66" d_high="52"/>
<p k="interfacing" dmm="0.517" good="61" bad="57" d_low="61" d_high="57"/>
</dmm>
`````

## `./build/ripwire . --cochange --cochange-groups`

*Modularity-violation GROUPS instead of pairs: "X co-changes with {A,B,C}, none of which it depends on" — a greedy cover, disclosed as greedy.*

`````
<!-- ripwire cochange groups: the surprising=1 violating pairs, collapsed around the file each group names. core= is the file to look at; each <f p=> under it is a partner it co-changes with and has no transitive static dependency on, so one group replaces its partners= pair rows. together=/recur=/conf_core= are that pair's own numbers: together= is the shared commit count, recur= how many of sub_windows= equal-commit-count slices of window= it recurs in, and conf_core= is conf(core => partner) — of the CORE's commits, the fraction that also touched this partner. groups= is a GREEDY cover, not a proven minimal one (minimum set cover is NP-hard): it is an upper bound on the smallest number of groups, and repeatedly picking the file covering the most still-uncovered pairs is what produced it. pairs_covered= is the total membership count and equals the number of surprising=1 pairs, because every violating pair lands in exactly one group. min_recur= appears when cochange-recur=K (the flag) filtered the pairs BEFORE they were grouped. Pairs that are not surprising=1, and pairs with a dep-incapable side (dep_capable=0), are not violations and are absent here — drop the cochange-groups flag for the full pair list. raise the default cap with limit=N (offset=M pages; a cut listing carries total=/has_more=/next_offset= so a paging loop can continue from it) -->
<!-- at= is the git commit these numbers were computed at; a trailing +dirty means the working tree differed from that commit, so the numbers describe the tree, not the commit -->
<!-- root= on this element is the crawl root every p= below is RELATIVE to (single-root runs only; absent => p= is the path ingest itself used, unchanged). -->
<cochange groups="30" pairs_covered="195" cover="greedy" window="18mo" sub_windows="3" shown="30" capped="0" root="." at="c7725f3ef">
<group core="src/cli.h" partners="53">
<f p="present/deck5_ripwire_build.js" together="33" recur="3" conf_core="0.16"/>
<f p="src/clones.h" together="5" recur="2" conf_core="0.02"/>
<f p="src/compactlegend.h" together="7" recur="1" conf_core="0.03"/>
<f p="src/contextratio.h" together="3" recur="2" conf_core="0.01"/>
<f p="src/crossref.h" together="8" recur="2" conf_core="0.04"/>
<f p="src/didyoumean.h" together="3" recur="3" conf_core="0.01"/>
<f p="src/editcheck.h" together="4" recur="2" conf_core="0.02"/>
<f p="src/editplan.h" together="8" recur="2" conf_core="0.04"/>
<f p="src/editpreview.h" together="4" recur="1" conf_core="0.02"/>
<f p="src/ensemble.h" together="4" recur="2" conf_core="0.02"/>
<f p="src/gitmine.h" together="4" recur="3" conf_core="0.02"/>
<f p="src/graph.h" together="19" recur="3" conf_core="0.09"/>
<f p="src/graphlegend.h" together="13" recur="3" conf_core="0.06"/>
<f p="src/handoff.h" together="4" recur="2" conf_core="0.02"/>
<f p="src/ingest.cpp" together="27" recur="3" conf_core="0.13"/>
<f p="src/lanes.h" together="3" recur="2" conf_core="0.01"/>
<f p="src/lexical.h" together="3" recur="3" conf_core="0.01"/>
<f p="src/lintrules.h" together="4" recur="3" conf_core="0.02"/>
<f p="src/mcp.h" together="25" recur="3" conf_core="0.12"/>
<f p="src/mcpedit.h" together="12" recur="3" conf_core="0.06"/>
<f p="src/mcpindex.h" together="4" recur="2" conf_core="0.02"/>
<f p="src/mcprefusal.h" together="6" recur="2" conf_core="0.03"/>
<f p="src/mcpverbs.h" together="34" recur="3" conf_core="0.16"/>
<f p="src/naminglens.h" together="5" recur="3" conf_core="0.02"/>
<f p="src/nonlocalstate.h" together="7" recur="3" conf_core="0.03"/>
… [230 more display lines; full output is 16043 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --cochange --cochange-recur=2`

*Only pairs whose co-change RECURS in 2+ sub-windows of the mined window (sub_windows= is the denominator) — a one-off sprint stops reading like a structural defect.*

`````
<!-- ripwire cochange: file pairs that change together in git but share no transitive static dependency (surprising=1) = hidden coupling. together= is the number of commits in window= that touched BOTH files (3 or more, or the pair is not reported); deg= is that count over the commit count of the LESS-CHANGED of the two files, so 1.00 means the quieter file never changed without the other. conf_ab= is that same fraction over a='s OWN commit count and conf_ba= over b='s, which is the asymmetric form: conf_ab=1.00 means a never changed without b. deg= is by construction the larger of the two, and driver= names which side it came from ("a" or "b") — the file whose changes most reliably imply the other's, and therefore the one to look at first. driver= is OMITTED when the two directions are equal, because a tie is not a finding. recur= is how many of sub_windows= the pair actually co-changed in: the mined window is cut into that many equal-COMMIT-COUNT slices (not equal time — a calendar slice can hold 400 commits or 4), so recur=1 at any together= is one burst of activity and not a persistent coupling, which is the distinction a single window cannot make. sub_windows= is the denominator and is never omitted; it is smaller than the nominal 3 only when the window holds fewer commits than that. min_recur= appears when cochange-recur=K (the flag) filtered the rows, so a short list is explained rather than silent. window= is the mining window: the default 18 months, or the since=REV|DATE value when one resolved. surprising= is only defined where BOTH sides could carry a static dependency at all (the same dependency-capable predicate deps <health dep_files=> uses: source languages yes; sh, md, json, ruby and binary/unknown files no). A pair with a dep-incapable side keeps its row and carries dep_capable=0 instead, because for it "shares no static dependency" is vacuously true. raise the default cap with limit=N (offset=M pages; a cut listing carries total=/has_more=/next_offset= so a paging loop can continue from it) -->
<!-- at= is the git commit these numbers were computed at; a trailing +dirty means the working tree differed from that commit, so the numbers describe the tree, not the commit -->
<!-- root= on this element is the crawl root every p= below is RELATIVE to (single-root runs only; absent => p= is the path ingest itself used, unchanged). -->
<cochange pairs="642" window="18mo" sub_windows="3" min_recur="2" shown="30" capped="1" total="642" has_more="1" next_offset="30" offset="0" limit="0" root="." at="c7725f3ef">
<pair a="src/cli.h" b="src/sarif.h" together="3" deg="1.00" conf_ab="0.01" conf_ba="1.00" driver="b" recur="3" surprising="1"/>
<pair a="src/crossref.h" b="src/darkflags.h" together="3" deg="1.00" conf_ab="0.18" conf_ba="1.00" driver="b" recur="2" surprising="1"/>
<pair a="src/cli.h" b="src/tsprobe.cpp" together="3" deg="1.00" conf_ab="0.01" conf_ba="1.00" driver="b" recur="2" surprising="1"/>
<pair a="src/fieldaffinity.h" b="test/accessshapefix/walks.cpp" together="3" deg="1.00" conf_ab="0.50" conf_ba="1.00" driver="b" recur="2" surprising="1"/>
<pair a="src/clones.h" b="src/tsprobe.cpp" together="3" deg="1.00" conf_ab="0.27" conf_ba="1.00" driver="b" recur="2" surprising="1"/>
<pair a="src/ingest.cpp" b="src/tsprobe.cpp" together="3" deg="1.00" conf_ab="0.03" conf_ba="1.00" driver="b" recur="2" surprising="1"/>
<pair a="src/lintrules.h" b="src/tsprobe.cpp" together="3" deg="1.00" conf_ab="0.50" conf_ba="1.00" driver="b" recur="2" surprising="1"/>
<pair a="src/accessshape.h" b="test/accessshapefix/walks.cpp" together="3" deg="1.00" conf_ab="1.00" conf_ba="1.00" recur="2" surprising="1"/>
<pair a="src/quality.h" b="src/tsprobe.cpp" together="3" deg="1.00" conf_ab="0.03" conf_ba="1.00" driver="b" recur="2" surprising="1"/>
<pair a="src/serialize.h" b="src/tsprobe.cpp" together="3" deg="1.00" conf_ab="0.03" conf_ba="1.00" driver="b" recur="2" surprising="1"/>
<pair a="bench/agentloop/analyze.py" b="bench/agentloop/run_agentloop.py" together="8" deg="0.89" conf_ab="0.89" conf_ba="0.47" driver="a" recur="2" surprising="1"/>
<pair a="src/namingconsistency.h" b="src/readability.h" together="3" deg="0.75" conf_ab="0.75" conf_ba="0.50" driver="a" recur="2" surprising="1"/>
<pair a="src/cli.h" b="src/mcpedit.h" together="12" deg="0.71" conf_ab="0.06" conf_ba="0.71" driver="b" recur="3" surprising="1"/>
<pair a="src/serialize.h" b="src/workspace.h" together="7" deg="0.70" conf_ab="0.07" conf_ba="0.70" driver="b" recur="3" surprising="1"/>
<pair a="src/cli.h" b="src/lintrules.h" together="4" deg="0.67" conf_ab="0.02" conf_ba="0.67" driver="b" recur="3" surprising="1"/>
<pair a="src/cli.h" b="src/nonlocalstate.h" together="7" deg="0.64" conf_ab="0.03" conf_ba="0.64" driver="b" recur="3" surprising="1"/>
<pair a="src/cli.h" b="src/editplan.h" together="8" deg="0.62" conf_ab="0.04" conf_ba="0.62" driver="b" recur="2" surprising="1"/>
<pair a="src/cli.h" b="src/query.h" together="3" deg="0.60" conf_ab="0.01" conf_ba="0.60" driver="b" recur="3" surprising="1"/>
<pair a="src/cli.h" b="src/didyoumean.h" together="3" deg="0.60" conf_ab="0.01" conf_ba="0.60" driver="b" recur="3" surprising="1"/>
<pair a="src/nonlocalstate.h" b="src/query.h" together="3" deg="0.60" conf_ab="0.27" conf_ba="0.60" driver="b" recur="2" surprising="1"/>
<pair a="src/ingest.cpp" b="src/query.h" together="3" deg="0.60" conf_ab="0.03" conf_ba="0.60" driver="b" recur="2" surprising="1"/>
<pair a="src/columnar.h" b="src/mcpverbs.h" together="3" deg="0.60" conf_ab="0.60" conf_ba="0.03" driver="a" recur="3" surprising="1"/>
<pair a="src/query.h" b="src/serialize.h" together="3" deg="0.60" conf_ab="0.60" conf_ba="0.03" driver="a" recur="2" surprising="1"/>
<pair a="present/deck5_ripwire_build.js" b="src/cli.h" together="33" deg="0.57" conf_ab="0.57" conf_ba="0.16" driver="a" recur="3" surprising="1"/>
<pair a="src/ingest.cpp" b="src/nonlocalstate.h" together="6" deg="0.55" conf_ab="0.05" conf_ba="0.55" driver="b" recur="3" surprising="1"/>
<pair a="src/cli.h" b="src/mcp.h" together="25" deg="0.54" conf_ab="0.12" conf_ba="0.54" driver="b" recur="3" surprising="1"/>
<pair a="src/cli.h" b="src/slice.h" together="13" deg="0.54" conf_ab="0.06" conf_ba="0.54" driver="b" recur="2" surprising="1"/>
<pair a="src/cli.h" b="src/recall.h" together="7" deg="0.54" conf_ab="0.03" conf_ba="0.54" driver="b" recur="3" surprising="1"/>
<pair a="present/deck5_ripwire_build.js" b="src/main.cpp" together="29" deg="0.50" conf_ab="0.50" conf_ba="0.11" driver="a" recur="3" surprising="1"/>
<pair a="src/cli.h" b="src/tracelocus.h" together="6" deg="0.50" conf_ab="0.03" conf_ba="0.50" driver="b" recur="2" surprising="1"/>
</cochange>
`````

## `./build/ripwire . --html=<scratch>/aux/map2.html --color-by=community`

*The HTML graph with the initial colour mode set to community (the page embeds all five modes and keeps a live selector).*

`````
(empty)
`````

Artifact written:

`````
   58724 <scratch>/aux/map2.html
`````

## `./build/ripwire . --index-out=<scratch>/aux/ci_index`

*CI generate-and-exit: cold-parse and write BOTH committable cache families (lean + rich), no map on stdout.*

`````
(empty)
`````

stderr:

`````
ripwire: --index-out wrote <scratch>/aux/ci_index.lean.ripwirecache (9517522 bytes, lean family)
ripwire: --index-out wrote <scratch>/aux/ci_index.rich.ripwirecache (22534666 bytes, rich family)
`````

Artifact written:

`````
 9517522 <scratch>/aux/ci_index.lean.ripwirecache
 22534666 <scratch>/aux/ci_index.rich.ripwirecache
 32052188 total
`````

## `./build/ripwire . --cache=<scratch>/aux/ci_index.lean.ripwirecache --top-k=3`

*Consume the lean artifact in a PR job: restore-equivalence, never blob-byte-identity.*

`````
<!-- ripwire v1 t=fn|method|cls|struct|iface|var|sec|macro(#define;degraded:body-is-replacement-text,edges-cross-expansion) p=path layer=arch-layer(opt) n=name id=canonical(path::scope::name,when-scoped) k=rank c=call amb=ambiguous-calls(read-source) lpin=calls-pinned-by-locality-prior-alone(a-disclosed-guess;read-source;absent-if-0) overloads=N-same-name-defs-merged-into-this-row(absent-if-1;shown=counts-them-individually,so-rows+sum(overloads-1)=shown) prov=scip(precise;else name-based) hdr:unresolved=call-name-defined-only-in-a-lang-incompatible-file (edges heuristic) hdr:locality_pinned=sum-of-lpin(absent-if-0) hdr:external=calls-refused-as-bound-outside-the-tree(builtin/stdlib-name-without-in-repo-evidence,external-import,super-past-the-tree;no-edge;absent-if-0) r:est_tokens=hdr-copy(none-if-stable) -->
<!-- r:root=crawl-root-every-p=-is-relative-to(single-root-only;absent=>p=is-the-raw-ingest-path) -->
<!-- pr_iters=pagerank-power-iterations(stop:L1-residual-below-tol,else-ceiling) pr_converged=0-only-when-ceiling-hit-first(absent=converged;no-such-attr=not-pagerank-ordered) -->
<!-- files=1588 symbols=13849 edges=17058 shown=3 est_tokens=698 ambiguous=6085 unresolved=3093 locality_pinned=6 external=788 precise=3 skipped_oversize=15 unindexed="txt:59,jsonl:26,tsv:21,scm:18,expected:15,lock:7" unindexed_exts=19 order=important-first -->
<r root="." est_tokens="698" pr_iters="31">
<f p="src/infra/svector.h" layer="infra">
<s t="method" n="size" id="src/infra/svector.h::svector::size" k="0.0169">
</s>
</f>
<f p="src/notes.h">
<s t="method" n="empty" id="src/notes.h::NoteIndex::empty" k="0.0099">
</s>
</f>
<f p="src/scipoverlay.h">
<s t="method" n="empty" id="src/scipoverlay.h::ScipOverlay::empty" k="0.0097">
</s>
</f>
</r>
`````

## `./build/ripwire . --pin-census=<scratch>/aux/pin_census.tsv --top-k=3`

*Eval-only: a per-call-site census of WHICH mechanism resolved each call, and the canonical id of every surviving target.*

`````
<!-- ripwire v1 t=fn|method|cls|struct|iface|var|sec|macro(#define;degraded:body-is-replacement-text,edges-cross-expansion) p=path layer=arch-layer(opt) n=name id=canonical(path::scope::name,when-scoped) k=rank c=call amb=ambiguous-calls(read-source) lpin=calls-pinned-by-locality-prior-alone(a-disclosed-guess;read-source;absent-if-0) overloads=N-same-name-defs-merged-into-this-row(absent-if-1;shown=counts-them-individually,so-rows+sum(overloads-1)=shown) prov=scip(precise;else name-based) hdr:unresolved=call-name-defined-only-in-a-lang-incompatible-file (edges heuristic) hdr:locality_pinned=sum-of-lpin(absent-if-0) hdr:external=calls-refused-as-bound-outside-the-tree(builtin/stdlib-name-without-in-repo-evidence,external-import,super-past-the-tree;no-edge;absent-if-0) r:est_tokens=hdr-copy(none-if-stable) -->
<!-- r:root=crawl-root-every-p=-is-relative-to(single-root-only;absent=>p=is-the-raw-ingest-path) -->
<!-- pr_iters=pagerank-power-iterations(stop:L1-residual-below-tol,else-ceiling) pr_converged=0-only-when-ceiling-hit-first(absent=converged;no-such-attr=not-pagerank-ordered) -->
<!-- files=1588 symbols=13849 edges=17058 shown=3 est_tokens=698 ambiguous=6085 unresolved=3093 locality_pinned=6 external=788 precise=3 skipped_oversize=15 unindexed="txt:59,jsonl:26,tsv:21,scm:18,expected:15,lock:7" unindexed_exts=19 order=important-first -->
<r root="." est_tokens="698" pr_iters="31">
<f p="src/infra/svector.h" layer="infra">
<s t="method" n="size" id="src/infra/svector.h::svector::size" k="0.0169">
</s>
</f>
<f p="src/notes.h">
<s t="method" n="empty" id="src/notes.h::NoteIndex::empty" k="0.0099">
</s>
</f>
<f p="src/scipoverlay.h">
<s t="method" n="empty" id="src/scipoverlay.h::ScipOverlay::empty" k="0.0097">
</s>
</f>
</r>
`````

Artifact written:

`````
# ripwire pin-census v2	C=kind\tmech\tpre\tpost\tflags\tcaller_id\tcallee\ttargets(|-sep)\tline
# line is the 1-based call-site line in the caller's file (v2, appended LAST so v1 readers are unchanged):
#   the key a SCIP occurrence joins on, so a coverage loss can be classified per site instead of guessed.
# O rows (only under --scip) are the SCIP oracle: O\tcaller_id\tcallee\ttargets(|-sep)
#   a target of @external (a builtin / another package) or @nondef (an in-index parameter, local or
#   attribute ripwire extracts no symbol for) means SCIP resolved the site to something that is NOT a
#   ripwire definition — the index spoke, and disagrees with every in-repo target the C row names.
# S rows (v2) are the DEFINITION universe, one per symbol: S\tid\tkind\tline — the def side of the
   37861 <scratch>/aux/pin_census.tsv
`````

## `./build/ripwire . --plan-lint=test/planlintfix/wave.md`

*The house PLAN/DESIGN format's STRUCTURE check — never semantics; exit 2 when a card or ledger row gates.*

**exit code: 2**

`````
<!-- ripwire plan-lint: STRUCTURE only, never semantics (the doc-drift lane already owns citation truth). A card is exactly an H3 heading opening with a task id ("T" + digits + up to three letters). A ledger is exactly one heading whose text, stripped of a leading section mark, reads "Status" case-insensitively. A card's status is satisfied EITHER by a glyph on the LAST non-blank line of its own body OR by a ledger line naming its id (folded by digits, so a bare card is also satisfied by a lettered ledger mention of the same number, e.g. a ledger entry for "T7a" answers for card "T7") that itself carries a glyph — the card's own body wins when it has one, the ledger is read only when it does not. Neither convention is universal even in this house's own plan corpus, so a file showing neither is reported dialect="0" and nothing further is checked — this lint is opt-in per file, never a directory sweep, and a plan that never adopted the convention is not a failing one. Findings, only once dialect="1": a card whose status did not resolve (status="missing", why="unlaunched" when a ledger exists and never names this id or a lettered sub-task of it, why="unresolved" when the ledger names it with no glyph nearby, why="no-glyph" when this document carries no ledger at all); an hourglass line whose blamed commit sits more than stale_commits= commits behind HEAD (never claimed outside a git repo — disclosed via git="0", or the card's own missing since=; blames whichever line the status resolved to, named by src="ledger" when that is the ledger rather than the card); a task id named in the ledger's own body with no matching card, digit-folded the same way (ledger-orphan); an owed/OWED mention with no check-mark or cross anywhere LATER in this same document (single-document only — a successor plan that discharges it is invisible here, a stated limit). Every gating row carries gating="1" and the header's own gating= sums them. NOT CHECKED AT ALL: whether any card's claims are true, a heading level other than three for a card, a ledger heading spelled any other way, any discharge outside this one document, and a document that uses card headings as plain labels with no status mechanism anywhere (no ledger, no glyph) — every one of its cards reads "missing" too, a known, disclosed gap rather than a guessed-at fix. Exit 2 when dialect="1" and gating is non-zero; exit 0 when clean or dialect="0"; exit 1 only when FILE could not be read — a usage error, never a finding. -->
<plan-lint file="test/planlintfix/wave.md" dialect="1" cards="3" ledger="1" ledger_line="21" at="c7725f3ef" git="1" stale_commits="20" gating="3">
<card id="T1" line="10" status="check" tline="12"/>
<card id="T2" line="14" status="cross" tline="16"/>
<card id="T5" line="18" status="missing" tline="19" why="unlaunched" gating="1"/>
<ledger-orphan id="T9" line="24" gating="1"/>
<owed line="22">
<![CDATA[- 2026-08-01 — T2 owed a re-check]]>
</owed>
<owed line="24" gating="1">
<![CDATA[- 2026-08-03 — T9 owed a kickoff review, still pending]]>
</owed>
</plan-lint>
`````

## `./build/ripwire . --plan-lint=test/planlintfix/wave_ledger.md`

*The ledger-shaped fixture through the same check (exit 2: one gating card).*

**exit code: 2**

`````
<!-- ripwire plan-lint: STRUCTURE only, never semantics (the doc-drift lane already owns citation truth). A card is exactly an H3 heading opening with a task id ("T" + digits + up to three letters). A ledger is exactly one heading whose text, stripped of a leading section mark, reads "Status" case-insensitively. A card's status is satisfied EITHER by a glyph on the LAST non-blank line of its own body OR by a ledger line naming its id (folded by digits, so a bare card is also satisfied by a lettered ledger mention of the same number, e.g. a ledger entry for "T7a" answers for card "T7") that itself carries a glyph — the card's own body wins when it has one, the ledger is read only when it does not. Neither convention is universal even in this house's own plan corpus, so a file showing neither is reported dialect="0" and nothing further is checked — this lint is opt-in per file, never a directory sweep, and a plan that never adopted the convention is not a failing one. Findings, only once dialect="1": a card whose status did not resolve (status="missing", why="unlaunched" when a ledger exists and never names this id or a lettered sub-task of it, why="unresolved" when the ledger names it with no glyph nearby, why="no-glyph" when this document carries no ledger at all); an hourglass line whose blamed commit sits more than stale_commits= commits behind HEAD (never claimed outside a git repo — disclosed via git="0", or the card's own missing since=; blames whichever line the status resolved to, named by src="ledger" when that is the ledger rather than the card); a task id named in the ledger's own body with no matching card, digit-folded the same way (ledger-orphan); an owed/OWED mention with no check-mark or cross anywhere LATER in this same document (single-document only — a successor plan that discharges it is invisible here, a stated limit). Every gating row carries gating="1" and the header's own gating= sums them. NOT CHECKED AT ALL: whether any card's claims are true, a heading level other than three for a card, a ledger heading spelled any other way, any discharge outside this one document, and a document that uses card headings as plain labels with no status mechanism anywhere (no ledger, no glyph) — every one of its cards reads "missing" too, a known, disclosed gap rather than a guessed-at fix. Exit 2 when dialect="1" and gating is non-zero; exit 0 when clean or dialect="0"; exit 1 only when FILE could not be read — a usage error, never a finding. -->
<plan-lint file="test/planlintfix/wave_ledger.md" dialect="1" cards="4" ledger="1" ledger_line="17" at="c7725f3ef" git="1" stale_commits="20" gating="1">
<card id="T1" line="4" status="check" tline="6"/>
<card id="T2" line="8" status="check" tline="18" src="ledger"/>
<card id="T5" line="11" status="missing" tline="12" why="unlaunched" gating="1"/>
<card id="T7" line="14" status="check" tline="20" src="ledger"/>
</plan-lint>
`````

## `./build/ripwire . --doctor --agent=claude`

*--doctor plus a LIVE integration inspection for one agent: PATH binary, installed-skill manifest parity, hook executability, MCP wiring — read-only, fixed repair commands, never config contents; exit 1 when any check fails.*

**exit code: 1**

`````
<!-- doctor: checks=/passed= are the row count/how many passed; each <c name= ok=> is one check, its OTHER attributes are check-specific (see help). cache-dir's blobs= is capped at 4096 (kMaxCacheBlobCount); blobs_floor="1" means the cap fired and blobs= is AT LEAST that many, not exactly (absent = the true count); truncated="1" covers that AND an I/O error mid-scan, so blobs_floor= is the narrower, more useful claim when both matter. volatile= on a row NAMES that row's own attributes that read LIVE machine state — cache-dir scans a per-user directory every ripwire process writes into, so two runs of this deterministic binary legitimately differ in exactly those fields and in nothing else; a determinism comparison strips the named attributes, never the row. tracked-binaries' truncated="1" means the git-history scan was SKIPPED entirely (too many tracked files), so its stale="0" there means unmeasured, never a clean scan. -->
<doctor checks="9" passed="7" agent="claude" at="c7725f3ef" built_from="c7725f3ef">
<c n="binary-path" ok="0" self="./build/ripwire" which="/opt/homebrew/bin/ripwire" on_path="1" same_file="0" self_mtime="1788647941" self_size="43113720" which_mtime="1788495666" which_size="40702928" hint="STALE: /opt/homebrew/bin/ripwire is  … [line truncated: 233 more bytes on this line]
<c n="grammars" ok="1" loaded="21" expected="21"/>
<c n="cache-dir" ok="1" dir="<tmp>" blobs="4096" bytes="1562474548" many="1" truncated="0" volatile="blobs,blobs_floor,bytes,many,truncated"/>
<c n="git" ok="1" git="1" repo="1" history="1" head="c7725f3ef"/>
<c n="tree-sitter" ok="1" core_abi="15" cpp_grammar_abi="14" languages="21"/>
<c n="tracked-binaries" ok="1" tracked="2019" binaries="6" non_git="0" truncated="0" stale="0"/>
<c n="claude-binary" ok="0" on_path="1" same_file="0" copied_heuristic="0" hint="reinstall the current build so Claude Code shell calls and this doctor resolve the same ripwire binary"/>
<c n="claude-skills" ok="1" manifest="1" declared="18" live="18"/>
<c n="claude-hooks" ok="1" configured="1" nudge_refs="2" route_hook="1"/>
</doctor>
`````

## `./build/ripwire . --doctor --agent=nosuch`

*Other --agent values refuse.*

**exit code: 1**

`````
(empty)
`````

stderr:

`````
ripwire: unsupported --agent value 'nosuch' (supported: codex, claude)
`````


---

# the dirty-tree verbs (throwaway clone, NOT the read-only repo)

Everything below runs with `cwd` = the throwaway clone at `<scratch>/dirty` (`git clone --local` of this repo, then one deliberate regression in `src/infra/sortutil.h`). The read-only repo is never touched. The binary is the same `build/ripwire`, addressed absolutely.

## `./build/ripwire . --situ`

*Situational report for a real diff: blast radius + tests + co-change + forgotten co-change partners.*

**wall time: 1.62s**

`````
ripwire situational-awareness — 1 changed file(s), 13 symbols in them
root: .
at: c7725f3ef+dirty
  [1] blast radius: 103 symbols across 27 files transitively depend on these changes (showing 8 of 27 files; --pr-context's own per-file blast-radius list is also capped, at 20)
        counts_floor=1: every count above is a FLOOR, never a total (call edges are name-based; dynamic dispatch, callbacks and macros can be missing) — read a zero as "none found", never as "none exists"; graph_ambiguous=6088 graph_unresolved=3093 is the whole graph's resolver gauge (calls split  … [line truncated: 113 more bytes on this line]
        src/mcpverbs.h  (30 dependent symbols)
        src/serialize.h  (9 dependent symbols)
        src/main.cpp  (7 dependent symbols)
        src/verbs_quality.h  (6 dependent symbols)
        bench/bench_sort_large.cpp  (5 dependent symbols)
        src/verbs_for.h  (5 dependent symbols)
        src/editplan.h  (4 dependent symbols)
        bench/bench_radix_ab.cpp  (3 dependent symbols)
  [2] tests to run (3):
        test/verify_radix.cpp   (run: bash test/greptiercheck.sh)
        test/adaptivecutshapefix/adaptive_cut_shape_test.cpp   (run: bash test/adaptivecutshapecheck.sh)
        test/verify_csr.cpp   (run: bash test/a9disclosurecheck.sh)
        (574 test/*.sh gates are NOT modelled: script-to-binary edges are not call edges, so they never appear here — a path count, not every one invokes the binary)
  [3] co-change — usually edited with these but NOT in your diff (0):
        (none, or no git history)
  next: --test-gate
`````

## `./build/ripwire . --test-gate`

*The pre-PR gate with real obligations — exit 4 when tests-to-run or untested blast radius is non-empty.*

**exit code: 4**

`````
<!-- ripwire test-gate (TDAD-parity, arXiv 2603.17973, -70% agent-caused regressions): tests to run for this change + the UNTESTED blast radius; exit 4 if tests OR untested is non-empty, else run them and rely on green. shown_tests=/shown_untested= are TWO INDEPENDENT row counts: the <t> tests-to-run rows and the <u> blast-radius rows. script_gates_unmodelled= is the legacy test/*.sh corpus path count; script_gates_registered= counts suite members; script_gates_mapped= those with exact dependency evidence; script_gates_unresolved_dynamic= is the registered remainder, disclosed rather than guessed. Shell <t> rows join tests= only via evidence=script_literal (script text contains the changed path) or evidence=manifest_declared (RIPWIRE_TEST_DEPS metadata). counts_floor=1 keeps these static evidence counts honest about shell expansion and generated paths they cannot resolve; graph_ambiguous=/graph_unresolved= are the map header's ambiguous=/unresolved= (the resolver gauge: calls split over several defs / calls whose in-repo defs were all language-filtered). next= is the one pasteable follow-up: the first <t> row's run= (a shell line), else a ripwire invocation. ccx_bar= is the cognitive-complexity bar a <u> row's ccx= is read against (quality-delta's own). UNIT: untested= here counts impacted SYMBOLS. The seams verb spells untested= over cross-directory call EDGES and the flip verb over the defs a gate lights — three different things, never compared or summed across verbs. The <t> rows are the COMPLETE obligation, never windowed, so they REPEAT VERBATIM on every page (concatenate from one page only); offset=/limit= window the <u> rows alone, default 25 (raise with limit=N, offset=M pages; a cut window carries total=/has_more=/next_offset= so a loop can continue). A <u> row is sym= at p=:l=, ccx= its cognitive complexity. run= is the command that discharges a test row; run_unknown="1" means none is derivable for that harness (a guess would be worse than none) — a row carries one or the other, never neither. -->
<!-- root= on this element is the crawl root every p= below is RELATIVE to (single-root runs only; absent => p= is the path ingest itself used, unchanged). -->
<test-gate changed="1" impacted="103" tests="3" untested="97" shown_tests="3" tests_capped="0" shown_untested="25" untested_capped="1" script_gates_unmodelled="574" script_gates_registered="555" script_gates_mapped="128" script_gates_unresolved_dynamic="427" ccx_bar="15" graph_ambiguous="6088" graph … [line truncated: 170 more bytes on this line]
<t p="test/adaptivecutshapefix/adaptive_cut_shape_test.cpp" run="bash test/adaptivecutshapecheck.sh"/>
<t p="test/verify_csr.cpp" run="bash test/a9disclosurecheck.sh"/>
<t p="test/verify_radix.cpp" run="bash test/greptiercheck.sh"/>
<u sym="dispatchMcpLine" p="src/mcp.h" l="535" ccx="517"/>
<u sym="dispatchMain" p="src/main.cpp" l="2653" ccx="405"/>
<u sym="runQualityDelta" p="src/verbs_quality.h" l="940" ccx="259"/>
<u sym="runForLens" p="src/verbs_for.h" l="1447" ccx="239"/>
<u sym="packSignatures" p="src/serialize.h" l="3316" ccx="220"/>
<u sym="serialize" p="src/serialize.h" l="1805" ccx="201"/>
<u sym="runDefaultMap" p="src/main.cpp" l="1098" ccx="198"/>
<u sym="packTaskBundleText" p="src/packtask.h" l="1082" ccx="166"/>
<u sym="runBatchSub" p="src/mcpverbs.h" l="4266" ccx="112"/>
<u sym="packLego" p="src/serialize.h" l="5669" ccx="89"/>
<u sym="runMcpHttp" p="src/mcpserver.h" l="415" ccx="81"/>
<u sym="serializeJson" p="src/serialize.h" l="6517" ccx="81"/>
<u sym="fetchBody" p="src/mcpverbs.h" l="3840" ccx="73"/>
<u sym="runEval" p="src/eval.h" l="168" ccx="66"/>
<u sym="sliceText" p="src/mcpverbs.h" l="3463" ccx="56"/>
<u sym="forTaskText" p="src/mcpverbs.h" l="1463" ccx="50"/>
<u sym="packSignaturesJson" p="src/serialize.h" l="7092" ccx="45"/>
<u sym="runTargetedViews" p="src/verbs_for.h" l="2441" ccx="44"/>
<u sym="getIndex" p="src/mcpindex.h" l="1104" ccx="39"/>
<u sym="fromTraceBundleText" p="src/tracelocus.h" l="832" ccx="39"/>
<u sym="qualityDeltaJson" p="src/mcpverbs.h" l="3106" ccx="33"/>
<u sym="usesText" p="src/mcpverbs.h" l="2296" ccx="33"/>
<u sym="packTaskText" p="src/mcpverbs.h" l="3252" ccx="30"/>
<u sym="runEditVerb" p="src/mcpedit.h" l="1137" ccx="29"/>
<u sym="grepHitsJson" p="src/mcpverbs.h" l="875" ccx="28"/>
</test-gate>
`````

## `./build/ripwire . --quality-delta`

*Every row carries p="file:line", the gating rows are marked gating="1" and now bar= (the threshold each numeric row is judged against), and the exit-2 refusal prints a naming line on stderr; a gating row carries a pasteable next=.*

**exit code: 2** — **wall time: 4.45s**

`````
<!-- ripwire quality-delta: only what a change made WORSE against the floor baseline= names below. Descriptive: weigh and fix the real ones, do not game the number (a wrong abstraction beats a low score). TEN KINDS, and kind= on every row names which one: complexity over the ccx bar, verbosity (LOC), nesting, params, duplication, dead-code, api-surface (new public contract drift), error-masking, short-horizon-churn, new-clone-of-reused-helper. THREE independent axes, in this order: (1) acked findings are suppressed entirely (acked= counts them); (2) ORIGIN — a finding on a symbol that EXISTED at the baseline is preexisting-worse (no origin attribute), one that exists only because the code is NEW carries origin="new-symbol"; (3) MATERIALITY — a small numeric delta is sev="minor", and minor= counts them. EXIT 2 fires only on preexisting-worse AND major, the gating= count; new-symbol rows never gate, so exit 0 is NOT a verdict on them — nothing that existed got worse, but the new debt is yours: read them. Clone kinds are new-symbol only when EVERY member is new; short-horizon-churn is preexisting by construction. preexisting-worse= and new-symbol= partition regressions=. stale= is a FOURTH axis, never gating and never counted in regressions=: rows in the .ripwire_quality_acks ledger whose target no longer applies. register-macro-excluded= is a FLOOR, not a finding: symbols this run excluded from the dead-code kind because their own definition is a registered self-registering test/benchmark macro call. Never gates, never counted in regressions=, printed even at zero (zero means none excluded, not that the check did not run). A gating row's next= is the one pasteable follow-up: expand on FILE:NAME, the body to fix (a duplication row names a SET and carries none). bar= on a complexity/verbosity/nesting/params row is the threshold now= is judged against (ccx 15, loc 60, nest 4, params 5). baseline="git-HEAD" means no sidecar existed, so the working tree was auto-compared against the HEAD tree — anything already committed cannot appear. at= is the git commit (plus a dirty marker when the working tree differs) this list was computed at. The registered families are doctest/Catch2 TEST_CASE, GoogleTest TEST/TEST_F/TEST_P, Google Benchmark BENCHMARK, plus any name a .ripwire_config register_macros= line adds; each registers itself through a static initializer the call graph cannot see, so zero in-edges on one is not evidence of anything. IDENTITY across a rename or a move: a finding is keyed path::scope::name, which a rename would destroy, so the baseline and the .ripwire_quality_acks ledger are both re-filed into the CURRENT tree's identity before either is read, by two EXACT mechanisms — git's own rename record, and equality of a whitespace-and-name-scrubbed body hash — never a similarity heuristic. renames= is how many rename pairs were read, rename_window_commits= how deep the commit window went, acked_by_rename= and acked_by_content= how many of the acked= suppressions each mechanism is responsible for. Three appear ONLY when true, so an absent one is not a silent no: renames_window_truncated= (history is deeper than the window), renames_truncated= (the pair cap was hit), renames_ambiguous= (an ancestor two current symbols both claim — refused rather than guessed). ORIGIN reads the re-filed baseline too, so a regression carried in with a rename is judged preexisting-worse and GATES instead of slipping through as new-symbol. FLOORS, stated because silence here would read as a guarantee: the two clone kinds key on a member-SET hash and are NOT re-filed, so a clone ack still dies on a rename; ORIGIN follows the rename record but never content, because the baseline stores no content id at all; and a move git recorded no rename for still reads as new-symbol. Each sa row carries key= (the ack identity as stored) and why=, which is target-gone (the key names no symbol or group any more) or finding-gone (the target survived, this kind just does not fire on it). sym= and p=path:line name WHICH ack it is, and are present exactly when the key still names a live symbol: on every finding-gone row, on none of the target-gone rows (there is nothing left to name), and on neither clone kind — a clone key hashes a member SET that no single symbol carries, so those rows are unnameable by construction rather than guessed at. Hygiene disclosure only — the ledger file is never auto-edited. ROWS: sym= is the canonical id the finding regressed on; was= and now= carry the before/after value for the numeric kinds; p="path:line" is the locator (root-relative; the first-sorting member for the clone kinds; omitted, never faked, when none resolves). churn= and surface= are per-kind classification facets (short-horizon-churn's self/ambient split; api-surface's new-symbol/contract-change tier). Every row the header's gating= counter counts also carries a gating attribute set to 1 — marked positively, never by the ABSENCE of sev or origin. CLONE ROWS name the whole group rather than one symbol: members= is the member list and tokens= its shared normalized-token count (the same per-group pair the clones verb reports). idiom= names a RECOGNIZED BODY SHAPE every member spells, out of a closed set of three (threshold-ladder, switch-name-table, builder-chain). idiom= alone changes nothing; a group that ALSO shares no non-keyword identifier between any two members, sits in pairwise-distinct enclosing contexts, and stays under 80 normalized tokens is an idiom COLLISION rather than a copy, and is reported minor instead of gating. Break any one of those and it gates as before, idiom= and all: two bucketing ladders over the SAME enum are a copy. The shape is read off the body's token stream and not a parse tree, so a macro-assembled body classifies as whatever its raw tokens spell — the name is printed so the call can be overruled by reading. -->
<quality-delta baseline="git-HEAD" regressions="8" minor="2" acked="0" stale="19" preexisting-worse="5" new-symbol="3" gating="5" register-macro-excluded="3" at="c7725f3ef+dirty" renames="55" rename_window_commits="400" acked_by_rename="0" acked_by_content="0" renames_window_truncated="1">
<r kind="api-surface" sym="src/infra/sortutil.h::rw::sortutil::nonNegativeFloatAscKeyCopy" sev="minor" surface="new-symbol" origin="new-symbol" p="src/infra/sortutil.h:119"/>
<r kind="api-surface" sym="src/infra/sortutil.h::rw::sortutil::nonNegativeFloatDescKey" was="1" now="2" surface="contract-change" p="src/infra/sortutil.h:109" gating="1" next="--expand=src/infra/sortutil.h:nonNegativeFloatDescKey"/>
<r kind="api-surface" sym="src/infra/sortutil.h::rw::sortutil::sortScoredIdsWithOptions" sev="minor" surface="new-symbol" origin="new-symbol" p="src/infra/sortutil.h:129"/>
<r kind="complexity" sym="src/infra/sortutil.h::rw::sortutil::lessByScoreDescId" was="1" now="67" bar="15" p="src/infra/sortutil.h:49" gating="1" next="--expand=src/infra/sortutil.h:lessByScoreDescId"/>
<r kind="duplication" members="src/infra/sortutil.h::rw::sortutil::nonNegativeFloatAscKeyCopy | src/infra/sortutil.h::rw::sortutil::nonNegativeFloatDescKey" tokens="59" p="src/infra/sortutil.h:119" gating="1"/>
<r kind="nesting" sym="src/infra/sortutil.h::rw::sortutil::lessByScoreDescId" was="1" now="6" bar="4" p="src/infra/sortutil.h:49" gating="1" next="--expand=src/infra/sortutil.h:lessByScoreDescId"/>
<r kind="new-clone-of-reused-helper" sym="src/infra/sortutil.h::rw::sortutil::nonNegativeFloatAscKeyCopy | src/infra/sortutil.h::rw::sortutil::nonNegativeFloatDescKey" was="0" now="4" p="src/infra/sortutil.h:119" gating="1" next="--expand=src/infra/sortutil.h:nonNegativeFloatDescKey"/>
<r kind="params" sym="src/infra/sortutil.h::rw::sortutil::sortScoredIdsWithOptions" was="0" now="8" bar="5" origin="new-symbol" p="src/infra/sortutil.h:129"/>
<sa kind="api-surface" key="298e798c7f075715" why="target-gone"/>
<sa kind="api-surface" key="5a07390012b46e06" why="target-gone"/>
<sa kind="api-surface:new-symbol" key="1926b0d9e94541a0" why="target-gone"/>
<sa kind="api-surface:new-symbol" key="79625906f9f71ad0" why="target-gone"/>
<sa kind="api-surface:new-symbol" key="995375dfa4e63104" why="target-gone"/>
<sa kind="complexity" key="4b309450f25c2b44" why="finding-gone" sym="src/ingest.cpp::rw::ingest" p="src/ingest.cpp:191"/>
<sa kind="complexity" key="53a1214d5505fa41" why="finding-gone" sym="main" p="src/main.cpp:2634"/>
<sa kind="duplication" key="160ac41979d9ebaf" why="finding-gone"/>
<sa kind="duplication" key="af2e342eda9648ed" why="finding-gone"/>
<sa kind="duplication" key="c8b32435256b863e" why="finding-gone"/>
<sa kind="nesting" key="1bded1f8f88d3b85" why="finding-gone" sym="src/slice.h::slicev::sliceFlowCompute" p="src/slice.h:2286"/>
<sa kind="nesting" key="3c07d993bfdbce53" why="finding-gone" sym="src/slice.h::slicev::sliceBundleText" p="src/slice.h:2685"/>
<sa kind="new-clone-of-reused-helper" key="0e9742973611fd71" why="finding-gone"/>
<sa kind="new-clone-of-reused-helper" key="5a0ff811529d5c95" why="finding-gone"/>
<sa kind="new-clone-of-reused-helper" key="c8b32435256b863e" why="finding-gone"/>
<sa kind="new-clone-of-reused-helper" key="d11c67611bc73d49" why="finding-gone"/>
<sa kind="params" key="f6dedd851e4b2a25" why="finding-gone" sym="src/slice.h::slicev::sliceWalk" p="src/slice.h:1122"/>
<sa kind="verbosity" key="15061a69cb5b451f" why="finding-gone" sym="src/packtask.h::rw::packTaskHeaderText" p="src/packtask.h:226"/>
<sa kind="verbosity" key="53a1214d5505fa41" why="finding-gone" sym="main" p="src/main.cpp:2634"/>
</quality-delta>
`````

stderr:

`````
ripwire: no ./.ripwire_quality_baseline — auto-comparing the working tree vs git HEAD (commit the baseline with --quality-baseline to pin it)
ripwire: --quality-delta gating: 5 preexisting-worse major finding(s); first: api-surface src/infra/sortutil.h::rw::sortutil::nonNegativeFloatDescKey at src/infra/sortutil.h:109 (was=1 now=2)
`````

## `./build/ripwire . --quality-delta --legend=compact`

*The same gating report under --legend=compact — same rows, same exit 2, schema="ripwire.quality-delta/v1", ~4 KB of legend down to one comment: the shape an agent's edit loop should run.*

**exit code: 2** — **wall time: 1.83s**

`````
<!-- ripwire quality-delta ripwire.quality-delta/v1: only what the change made WORSE vs baseline=: regressions= minor= gating=; <r kind= sym= p= was= now= gating= bar=>, <sa> acked. at=: commit(+dirty). next=: the one pasteable follow-up. -->
<quality-delta schema="ripwire.quality-delta/v1" baseline="git-HEAD" regressions="8" minor="2" acked="0" stale="19" preexisting-worse="5" new-symbol="3" gating="5" register-macro-excluded="3" at="c7725f3ef+dirty" renames="55" rename_window_commits="400" acked_by_rename="0" acked_by_content="0" renam … [line truncated: 24 more bytes on this line]
<r kind="api-surface" sym="src/infra/sortutil.h::rw::sortutil::nonNegativeFloatAscKeyCopy" sev="minor" surface="new-symbol" origin="new-symbol" p="src/infra/sortutil.h:119"/>
<r kind="api-surface" sym="src/infra/sortutil.h::rw::sortutil::nonNegativeFloatDescKey" was="1" now="2" surface="contract-change" p="src/infra/sortutil.h:109" gating="1" next="--expand=src/infra/sortutil.h:nonNegativeFloatDescKey"/>
<r kind="api-surface" sym="src/infra/sortutil.h::rw::sortutil::sortScoredIdsWithOptions" sev="minor" surface="new-symbol" origin="new-symbol" p="src/infra/sortutil.h:129"/>
<r kind="complexity" sym="src/infra/sortutil.h::rw::sortutil::lessByScoreDescId" was="1" now="67" bar="15" p="src/infra/sortutil.h:49" gating="1" next="--expand=src/infra/sortutil.h:lessByScoreDescId"/>
<r kind="duplication" members="src/infra/sortutil.h::rw::sortutil::nonNegativeFloatAscKeyCopy | src/infra/sortutil.h::rw::sortutil::nonNegativeFloatDescKey" tokens="59" p="src/infra/sortutil.h:119" gating="1"/>
<r kind="nesting" sym="src/infra/sortutil.h::rw::sortutil::lessByScoreDescId" was="1" now="6" bar="4" p="src/infra/sortutil.h:49" gating="1" next="--expand=src/infra/sortutil.h:lessByScoreDescId"/>
<r kind="new-clone-of-reused-helper" sym="src/infra/sortutil.h::rw::sortutil::nonNegativeFloatAscKeyCopy | src/infra/sortutil.h::rw::sortutil::nonNegativeFloatDescKey" was="0" now="4" p="src/infra/sortutil.h:119" gating="1" next="--expand=src/infra/sortutil.h:nonNegativeFloatDescKey"/>
<r kind="params" sym="src/infra/sortutil.h::rw::sortutil::sortScoredIdsWithOptions" was="0" now="8" bar="5" origin="new-symbol" p="src/infra/sortutil.h:129"/>
<sa kind="api-surface" key="298e798c7f075715" why="target-gone"/>
<sa kind="api-surface" key="5a07390012b46e06" why="target-gone"/>
<sa kind="api-surface:new-symbol" key="1926b0d9e94541a0" why="target-gone"/>
<sa kind="api-surface:new-symbol" key="79625906f9f71ad0" why="target-gone"/>
<sa kind="api-surface:new-symbol" key="995375dfa4e63104" why="target-gone"/>
<sa kind="complexity" key="4b309450f25c2b44" why="finding-gone" sym="src/ingest.cpp::rw::ingest" p="src/ingest.cpp:191"/>
<sa kind="complexity" key="53a1214d5505fa41" why="finding-gone" sym="main" p="src/main.cpp:2634"/>
<sa kind="duplication" key="160ac41979d9ebaf" why="finding-gone"/>
<sa kind="duplication" key="af2e342eda9648ed" why="finding-gone"/>
<sa kind="duplication" key="c8b32435256b863e" why="finding-gone"/>
<sa kind="nesting" key="1bded1f8f88d3b85" why="finding-gone" sym="src/slice.h::slicev::sliceFlowCompute" p="src/slice.h:2286"/>
<sa kind="nesting" key="3c07d993bfdbce53" why="finding-gone" sym="src/slice.h::slicev::sliceBundleText" p="src/slice.h:2685"/>
<sa kind="new-clone-of-reused-helper" key="0e9742973611fd71" why="finding-gone"/>
<sa kind="new-clone-of-reused-helper" key="5a0ff811529d5c95" why="finding-gone"/>
<sa kind="new-clone-of-reused-helper" key="c8b32435256b863e" why="finding-gone"/>
<sa kind="new-clone-of-reused-helper" key="d11c67611bc73d49" why="finding-gone"/>
<sa kind="params" key="f6dedd851e4b2a25" why="finding-gone" sym="src/slice.h::slicev::sliceWalk" p="src/slice.h:1122"/>
<sa kind="verbosity" key="15061a69cb5b451f" why="finding-gone" sym="src/packtask.h::rw::packTaskHeaderText" p="src/packtask.h:226"/>
<sa kind="verbosity" key="53a1214d5505fa41" why="finding-gone" sym="main" p="src/main.cpp:2634"/>
</quality-delta>
`````

stderr:

`````
ripwire: no ./.ripwire_quality_baseline — auto-comparing the working tree vs git HEAD (commit the baseline with --quality-baseline to pin it)
ripwire: --quality-delta gating: 5 preexisting-worse major finding(s); first: api-surface src/infra/sortutil.h::rw::sortutil::nonNegativeFloatDescKey at src/infra/sortutil.h:109 (was=1 now=2)
`````

## `./build/ripwire . --quality-delta --json`

*The same findings as JSON (one of the CI/scripting verbs --json supports) — same exit 2 as the XML form.*

**exit code: 2** — **wall time: 1.84s**

`````
{"baseline":"git-HEAD","regressions":8,"minor":2,"acked":0,"stale":19,"preexisting-worse":5,"new-symbol":3,"gating":5,"register-macro-excluded":3,"at":"c7725f3ef+dirty","renames":55,"rename_window_commits":400,"acked_by_rename":0,"acked_by_content":0,"renames_window_truncated":1,"r":[{"kind":"api-su … [line truncated: 169 more bytes on this line]
{"kind":"api-surface","sym":"src/infra/sortutil.h::rw::sortutil::nonNegativeFloatDescKey","was":1,"now":2,"p":"src/infra/sortutil.h:109","gating":true,"surface":"contract-change"},
{"kind":"api-surface","sym":"src/infra/sortutil.h::rw::sortutil::sortScoredIdsWithOptions","p":"src/infra/sortutil.h:129","sev":"minor","surface":"new-symbol","origin":"new-symbol"},
{"kind":"complexity","sym":"src/infra/sortutil.h::rw::sortutil::lessByScoreDescId","was":1,"now":67,"p":"src/infra/sortutil.h:49","gating":true},
{"kind":"duplication","members":"src/infra/sortutil.h::rw::sortutil::nonNegativeFloatAscKeyCopy | src/infra/sortutil.h::rw::sortutil::nonNegativeFloatDescKey","tokens":59,"p":"src/infra/sortutil.h:119","gating":true},
{"kind":"nesting","sym":"src/infra/sortutil.h::rw::sortutil::lessByScoreDescId","was":1,"now":6,"p":"src/infra/sortutil.h:49","gating":true},
{"kind":"new-clone-of-reused-helper","sym":"src/infra/sortutil.h::rw::sortutil::nonNegativeFloatAscKeyCopy | src/infra/sortutil.h::rw::sortutil::nonNegativeFloatDescKey","was":0,"now":4,"p":"src/infra/sortutil.h:119","gating":true},
{"kind":"params","sym":"src/infra/sortutil.h::rw::sortutil::sortScoredIdsWithOptions","was":0,"now":8,"p":"src/infra/sortutil.h:129","origin":"new-symbol"}],
"sa":[{"kind":"api-surface","key":"298e798c7f075715","why":"target-gone"},
{"kind":"api-surface","key":"5a07390012b46e06","why":"target-gone"},
{"kind":"api-surface:new-symbol","key":"1926b0d9e94541a0","why":"target-gone"},
{"kind":"api-surface:new-symbol","key":"79625906f9f71ad0","why":"target-gone"},
{"kind":"api-surface:new-symbol","key":"995375dfa4e63104","why":"target-gone"},
{"kind":"complexity","key":"4b309450f25c2b44","why":"finding-gone","sym":"src/ingest.cpp::rw::ingest","p":"src/ingest.cpp:191"},
{"kind":"complexity","key":"53a1214d5505fa41","why":"finding-gone","sym":"main","p":"src/main.cpp:2634"},
{"kind":"duplication","key":"160ac41979d9ebaf","why":"finding-gone"},
{"kind":"duplication","key":"af2e342eda9648ed","why":"finding-gone"},
{"kind":"duplication","key":"c8b32435256b863e","why":"finding-gone"},
{"kind":"nesting","key":"1bded1f8f88d3b85","why":"finding-gone","sym":"src/slice.h::slicev::sliceFlowCompute","p":"src/slice.h:2286"},
{"kind":"nesting","key":"3c07d993bfdbce53","why":"finding-gone","sym":"src/slice.h::slicev::sliceBundleText","p":"src/slice.h:2685"},
{"kind":"new-clone-of-reused-helper","key":"0e9742973611fd71","why":"finding-gone"},
{"kind":"new-clone-of-reused-helper","key":"5a0ff811529d5c95","why":"finding-gone"},
{"kind":"new-clone-of-reused-helper","key":"c8b32435256b863e","why":"finding-gone"},
{"kind":"new-clone-of-reused-helper","key":"d11c67611bc73d49","why":"finding-gone"},
{"kind":"params","key":"f6dedd851e4b2a25","why":"finding-gone","sym":"src/slice.h::slicev::sliceWalk","p":"src/slice.h:1122"},
{"kind":"verbosity","key":"15061a69cb5b451f","why":"finding-gone","sym":"src/packtask.h::rw::packTaskHeaderText","p":"src/packtask.h:226"},
{"kind":"verbosity","key":"53a1214d5505fa41","why":"finding-gone","sym":"main","p":"src/main.cpp:2634"}]}
`````

stderr:

`````
ripwire: no ./.ripwire_quality_baseline — auto-comparing the working tree vs git HEAD (commit the baseline with --quality-baseline to pin it)
ripwire: --quality-delta gating: 5 preexisting-worse major finding(s); first: api-surface src/infra/sortutil.h::rw::sortutil::nonNegativeFloatDescKey at src/infra/sortutil.h:109 (was=1 now=2)
`````

## `./build/ripwire . --quality-delta --quality-ack --ack-only=zzznope`

*NEW FLAG: --ack-only matching nothing REFUSES rather than falling back to acking everything.*

**exit code: 1** — **wall time: 1.19s**

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

**wall time: 1.18s**

`````
(empty)
`````

stderr:

`````
ripwire: no ./.ripwire_quality_baseline — auto-comparing the working tree vs git HEAD (commit the baseline with --quality-baseline to pin it)
ripwire: acknowledged 3 of 8 finding(s) (5 left UNACKED by --ack-only, 0 already acked) → ./.ripwire_quality_acks
`````

## `./build/ripwire . --quality-delta`

*Re-run after the partial ack: acked=3, the rest still gate (exit 2).*

**exit code: 2** — **wall time: 1.84s**

`````
<!-- ripwire quality-delta: only what a change made WORSE against the floor baseline= names below. Descriptive: weigh and fix the real ones, do not game the number (a wrong abstraction beats a low score). TEN KINDS, and kind= on every row names which one: complexity over the ccx bar, verbosity (LOC), nesting, params, duplication, dead-code, api-surface (new public contract drift), error-masking, short-horizon-churn, new-clone-of-reused-helper. THREE independent axes, in this order: (1) acked findings are suppressed entirely (acked= counts them); (2) ORIGIN — a finding on a symbol that EXISTED at the baseline is preexisting-worse (no origin attribute), one that exists only because the code is NEW carries origin="new-symbol"; (3) MATERIALITY — a small numeric delta is sev="minor", and minor= counts them. EXIT 2 fires only on preexisting-worse AND major, the gating= count; new-symbol rows never gate, so exit 0 is NOT a verdict on them — nothing that existed got worse, but the new debt is yours: read them. Clone kinds are new-symbol only when EVERY member is new; short-horizon-churn is preexisting by construction. preexisting-worse= and new-symbol= partition regressions=. stale= is a FOURTH axis, never gating and never counted in regressions=: rows in the .ripwire_quality_acks ledger whose target no longer applies. register-macro-excluded= is a FLOOR, not a finding: symbols this run excluded from the dead-code kind because their own definition is a registered self-registering test/benchmark macro call. Never gates, never counted in regressions=, printed even at zero (zero means none excluded, not that the check did not run). A gating row's next= is the one pasteable follow-up: expand on FILE:NAME, the body to fix (a duplication row names a SET and carries none). bar= on a complexity/verbosity/nesting/params row is the threshold now= is judged against (ccx 15, loc 60, nest 4, params 5). baseline="git-HEAD" means no sidecar existed, so the working tree was auto-compared against the HEAD tree — anything already committed cannot appear. at= is the git commit (plus a dirty marker when the working tree differs) this list was computed at. The registered families are doctest/Catch2 TEST_CASE, GoogleTest TEST/TEST_F/TEST_P, Google Benchmark BENCHMARK, plus any name a .ripwire_config register_macros= line adds; each registers itself through a static initializer the call graph cannot see, so zero in-edges on one is not evidence of anything. IDENTITY across a rename or a move: a finding is keyed path::scope::name, which a rename would destroy, so the baseline and the .ripwire_quality_acks ledger are both re-filed into the CURRENT tree's identity before either is read, by two EXACT mechanisms — git's own rename record, and equality of a whitespace-and-name-scrubbed body hash — never a similarity heuristic. renames= is how many rename pairs were read, rename_window_commits= how deep the commit window went, acked_by_rename= and acked_by_content= how many of the acked= suppressions each mechanism is responsible for. Three appear ONLY when true, so an absent one is not a silent no: renames_window_truncated= (history is deeper than the window), renames_truncated= (the pair cap was hit), renames_ambiguous= (an ancestor two current symbols both claim — refused rather than guessed). ORIGIN reads the re-filed baseline too, so a regression carried in with a rename is judged preexisting-worse and GATES instead of slipping through as new-symbol. FLOORS, stated because silence here would read as a guarantee: the two clone kinds key on a member-SET hash and are NOT re-filed, so a clone ack still dies on a rename; ORIGIN follows the rename record but never content, because the baseline stores no content id at all; and a move git recorded no rename for still reads as new-symbol. The two mechanisms in full, because a suppression is a claim about identity: git's rename record is read with rename detection and the similarity threshold PINNED in the command, never inherited from the repo config, over a fixed COMMIT window rather than a wall-clock one, so the answer is the same everywhere; the content match is equality of a body hash scrubbed of whitespace and of the symbol's own name, for a move git recorded no rename for. A body that CHANGED is a different finding and is matched by neither. Each sa row carries key= (the ack identity as stored) and why=, which is target-gone (the key names no symbol or group any more) or finding-gone (the target survived, this kind just does not fire on it). sym= and p=path:line name WHICH ack it is, and are present exactly when the key still names a live symbol: on every finding-gone row, on none of the target-gone rows (there is nothing left to name), and on neither clone kind — a clone key hashes a member SET that no single symbol carries, so those rows are unnameable by construction rather than guessed at. Hygiene disclosure only — the ledger file is never auto-edited. ROWS: sym= is the canonical id the finding regressed on; was= and now= carry the before/after value for the numeric kinds; p="path:line" is the locator (root-relative; the first-sorting member for the clone kinds; omitted, never faked, when none resolves). churn= and surface= are per-kind classification facets (short-horizon-churn's self/ambient split; api-surface's new-symbol/contract-change tier). Every row the header's gating= counter counts also carries a gating attribute set to 1 — marked positively, never by the ABSENCE of sev or origin. CLONE ROWS name the whole group rather than one symbol: members= is the member list and tokens= its shared normalized-token count (the same per-group pair the clones verb reports). idiom= names a RECOGNIZED BODY SHAPE every member spells, out of a closed set of three (threshold-ladder, switch-name-table, builder-chain). idiom= alone changes nothing; a group that ALSO shares no non-keyword identifier between any two members, sits in pairwise-distinct enclosing contexts, and stays under 80 normalized tokens is an idiom COLLISION rather than a copy, and is reported minor instead of gating. Break any one of those and it gates as before, idiom= and all: two bucketing ladders over the SAME enum are a copy. The shape is read off the body's token stream and not a parse tree, so a macro-assembled body classifies as whatever its raw tokens spell — the name is printed so the call can be overruled by reading. -->
<quality-delta baseline="git-HEAD" regressions="5" minor="0" acked="3" stale="19" preexisting-worse="4" new-symbol="1" gating="4" register-macro-excluded="3" at="c7725f3ef+dirty" renames="55" rename_window_commits="400" acked_by_rename="0" acked_by_content="0" renames_window_truncated="1">
<r kind="complexity" sym="src/infra/sortutil.h::rw::sortutil::lessByScoreDescId" was="1" now="67" bar="15" p="src/infra/sortutil.h:49" gating="1" next="--expand=src/infra/sortutil.h:lessByScoreDescId"/>
<r kind="duplication" members="src/infra/sortutil.h::rw::sortutil::nonNegativeFloatAscKeyCopy | src/infra/sortutil.h::rw::sortutil::nonNegativeFloatDescKey" tokens="59" p="src/infra/sortutil.h:119" gating="1"/>
<r kind="nesting" sym="src/infra/sortutil.h::rw::sortutil::lessByScoreDescId" was="1" now="6" bar="4" p="src/infra/sortutil.h:49" gating="1" next="--expand=src/infra/sortutil.h:lessByScoreDescId"/>
<r kind="new-clone-of-reused-helper" sym="src/infra/sortutil.h::rw::sortutil::nonNegativeFloatAscKeyCopy | src/infra/sortutil.h::rw::sortutil::nonNegativeFloatDescKey" was="0" now="4" p="src/infra/sortutil.h:119" gating="1" next="--expand=src/infra/sortutil.h:nonNegativeFloatDescKey"/>
<r kind="params" sym="src/infra/sortutil.h::rw::sortutil::sortScoredIdsWithOptions" was="0" now="8" bar="5" origin="new-symbol" p="src/infra/sortutil.h:129"/>
<sa kind="api-surface" key="298e798c7f075715" why="target-gone"/>
<sa kind="api-surface" key="5a07390012b46e06" why="target-gone"/>
<sa kind="api-surface:new-symbol" key="1926b0d9e94541a0" why="target-gone"/>
<sa kind="api-surface:new-symbol" key="79625906f9f71ad0" why="target-gone"/>
<sa kind="api-surface:new-symbol" key="995375dfa4e63104" why="target-gone"/>
<sa kind="complexity" key="4b309450f25c2b44" why="finding-gone" sym="src/ingest.cpp::rw::ingest" p="src/ingest.cpp:191"/>
<sa kind="complexity" key="53a1214d5505fa41" why="finding-gone" sym="main" p="src/main.cpp:2634"/>
<sa kind="duplication" key="160ac41979d9ebaf" why="finding-gone"/>
<sa kind="duplication" key="af2e342eda9648ed" why="finding-gone"/>
<sa kind="duplication" key="c8b32435256b863e" why="finding-gone"/>
<sa kind="nesting" key="1bded1f8f88d3b85" why="finding-gone" sym="src/slice.h::slicev::sliceFlowCompute" p="src/slice.h:2286"/>
<sa kind="nesting" key="3c07d993bfdbce53" why="finding-gone" sym="src/slice.h::slicev::sliceBundleText" p="src/slice.h:2685"/>
<sa kind="new-clone-of-reused-helper" key="0e9742973611fd71" why="finding-gone"/>
<sa kind="new-clone-of-reused-helper" key="5a0ff811529d5c95" why="finding-gone"/>
<sa kind="new-clone-of-reused-helper" key="c8b32435256b863e" why="finding-gone"/>
<sa kind="new-clone-of-reused-helper" key="d11c67611bc73d49" why="finding-gone"/>
<sa kind="params" key="f6dedd851e4b2a25" why="finding-gone" sym="src/slice.h::slicev::sliceWalk" p="src/slice.h:1122"/>
<sa kind="verbosity" key="15061a69cb5b451f" why="finding-gone" sym="src/packtask.h::rw::packTaskHeaderText" p="src/packtask.h:226"/>
<sa kind="verbosity" key="53a1214d5505fa41" why="finding-gone" sym="main" p="src/main.cpp:2634"/>
</quality-delta>
`````

stderr:

`````
ripwire: no ./.ripwire_quality_baseline — auto-comparing the working tree vs git HEAD (commit the baseline with --quality-baseline to pin it)
ripwire: --quality-delta gating: 4 preexisting-worse major finding(s); first: complexity src/infra/sortutil.h::rw::sortutil::lessByScoreDescId at src/infra/sortutil.h:49 (was=1 now=67)
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

*A real contract-change: was=1 now=2 params, with the call sites that are now provably incompatible, and a pasteable next= (--uses=SYM) on the root.*

`````
<!-- ripwire edit-check: SYM's contract (param count + publicness) NOW vs git HEAD — unchanged/new-symbol/contract-change — plus its 1-hop callers. A caller is flagged incompatible="1" when its argument count was reliably counted and NO definition in the folded set could accept it: every one has a FIXED arity that disagrees. A variadic, defaulted or implicit-receiver definition (a Python/Ruby method, whose params counts the self/cls the call site never writes) has no fixed arity and is never flagged. That makes the ARITY half one-sided — a call the compared definitions could accept is never flagged — but it is NOT a proof that the call site binds to THIS definition. Call edges are matched by NAME, so a receiver-qualified call to a same-named callee this tool does not index (a standard-library or third-party method) is measured against the one definition it does index; a clean, compiling tree can therefore carry a nonzero incompatible= with nothing edited at all, and on a widely-shared name it can be most of that name's callers. Read incompatible= as a fact about the tree as it stands — call sites worth OPENING, not a verdict — and status= as a fact about the edit. Warm path hits the qheadsnap/qsnap cache — never a full quality-delta style recompute. defs= is how many DEFINITIONS at this site (same file, same scope, same name — the overload set) are folded into this one contract; a selector matching more than one SITE is refused instead, so defs= only ever counts overloads. params_was and params_now are the MAX over that set on each side (the same MAX the baseline snapshot stores), and publicness is the OR. That MAX has TWO consequences, in opposite directions. It can read like a break and not be one: adding a WIDER overload beside an unchanged one raises params_now with no existing definition altered, so it reports status="contract-change" with incompatible="0" and a def row still carrying the old parameter count — no seen caller breaks. And it can read like safety and not be: REMOVING an overload whose parameter count is BELOW the MAX moves neither number, because the MAX survives on both sides, while the call site that used the removed definition no longer binds. defs_was=/defs_now= is what closes that: the count of definitions sharing this symbol's DEFINITION SITE — same file, same scope, same name — on each side. That is the population the baseline snapshot buckets by, so the two numbers answer the same question and are equal on an unedited tree. A same-named definition in ANOTHER FILE is a different contract and is counted on neither side, so defs_now= agrees with the root's defs= by construction and only defs_was= can move it. status is therefore the join of THREE was-vs-now facts — the params MAX, publicness, and the definition COUNT — and change= names which of them carried it. change= adds broken-callers when a seen caller is also flagged, but never on its own — for the reason stated at the top: incompatible= describes the TREE and status= describes the EDIT, so a headline must not turn on it. RESIDUAL: an overload whose arity changes BELOW the MAX while the COUNT stays the same moves none of the three. The root's incompatible= is the COUNT of flagged callers (a c row's incompatible="1" is the per-caller flag). sites_l= rides on a flagged row only: a c row's p= is where that CALLER is DEFINED, and sites_l= is the ascending LINE list of its call-role reference sites to this name — the lines to open, the same rows the uses verb prints, including the ones whose argument count could not be counted (so sites_l= can be wider than the evidence the flag rests on). Two calls on one line are ONE site. p= is the definition the selector resolved to; when defs is above 1 EVERY folded definition is listed as its own def row (p=, t=, params=), which is what tells a widened single definition apart from an added overload. At defs="1" no def row is emitted: the root's own p=/t= is that definition, and params_now is its parameter count. next= is the one pasteable follow-up: on a contract-change the uses verb on SYM (the call sites), otherwise the test gate on the definition's file. counts_floor="1" means every count here is a FLOOR, never a total: edges are extracted from source TEXT by NAME. Missing: dynamic dispatch (virtual/interface/duck-typed), a most-vexing-parse declaration with no call expression, a function-pointer/callback bound to more than one function in scope (reassigned, table-indexed, lambda-bound, or address-taken/reference-bound), and a plain-name binding (fp=handler) whose variable type is not PROVABLY a function pointer (a same-file typedef/declarator; a HEADER typedef is missed; auto/template types are read as unpinned, so KEPT). A macro-generated call site is role="macro" only when its name uniquely names an indexed function-like #define (C-family, t="macro"); a shared name stays a plain call, an unindexed macro is no edge. Read a zero as "none found", never as "none exists". graph_ambiguous=/graph_unresolved= are the whole graph's resolver gauge (calls split over several defs / calls whose in-repo defs were all language-filtered), the map header's ambiguous=/unresolved=. COUNTING UNIT differs by verb: callers, callees, edit-check, graph-query and pr-context counts are DISTINCT SYMBOLS (repeated calls from one caller, and calls to two overloads, collapse into ONE row; multiplicity survives only in the call graph's edge weight). The reach counts (impact's reaches=, pr-context's dependents=) are the size of a transitive reach SET, each symbol counted once. The uses verb counts call SITES, one row per occurrence — a larger count there for the same symbol is these units agreeing, not disagreeing. The map header's edges= is a unit again different — distinct (caller,callee) PAIRS — and that document carries neither this marker nor this clause. -->
<edit-check sym="nonNegativeFloatDescKey" t="fn" p="src/infra/sortutil.h:109" status="contract-change" defs="1" params_was="1" params_now="2" public_was="1" public_now="1" defs_was="1" defs_now="1" change="params,broken-callers" callers="4" incompatible="4" at="c7725f3ef+dirty" graph_ambiguous="6088 … [line truncated: 90 more bytes on this line]
<c n="benchScores" p="bench/bench_radix_ab.cpp:133" incompatible="1" sites_l="146,152"/>
<c n="benchAdaptive" p="bench/bench_radix_ab.cpp:157" incompatible="1" sites_l="162"/>
<c n="radixSortNonNegativeFloatsDesc" p="src/infra/sortutil.h:138" incompatible="1" sites_l="147"/>
<c n="radixSortByScoreDescId" p="src/infra/sortutil.h:153" incompatible="1" sites_l="213"/>
</edit-check>
`````

## `./build/ripwire . --edit-check=nonNegativeFloatDescKey --legend=compact`

*The same verdict under --legend=compact: ~5.7 KB of legend becomes one comment, every <c incompatible=> row identical — the post-edit reflex at its cheapest.*

`````
<!-- ripwire edit-check ripwire.edit-check/v1: sym='s contract NOW vs HEAD: status=unchanged|new-symbol|contract-change; <c n= p= incompatible=1 sites_l=> callers. counts_floor=1: every count is a FLOOR, never a total. graph_ambiguous=/graph_unresolved=: resolver gauge. at=: commit(+dirty). root=: p= relative to it. next=: the one pasteable follow-up. -->
<edit-check schema="ripwire.edit-check/v1" sym="nonNegativeFloatDescKey" t="fn" p="src/infra/sortutil.h:109" status="contract-change" defs="1" params_was="1" params_now="2" public_was="1" public_now="1" defs_was="1" defs_now="1" change="params,broken-callers" callers="4" incompatible="4" at="c7725f3 … [line truncated: 121 more bytes on this line]
<c n="benchScores" p="bench/bench_radix_ab.cpp:133" incompatible="1" sites_l="146,152"/>
<c n="benchAdaptive" p="bench/bench_radix_ab.cpp:157" incompatible="1" sites_l="162"/>
<c n="radixSortNonNegativeFloatsDesc" p="src/infra/sortutil.h:138" incompatible="1" sites_l="147"/>
<c n="radixSortByScoreDescId" p="src/infra/sortutil.h:153" incompatible="1" sites_l="213"/>
</edit-check>
`````

## `./build/ripwire . --pr-context`

*The review-evidence bundle with an actual changed file.*

`````
<!-- ripwire pr-context: no-LLM review-evidence bundle per changed file — defined symbols, their callers, blast radius (transitive dependents), affected tests, co-change partners not in the diff, and owners. base=working-tree. skipped_mode_only=diffs that changed a file's MODE and nothing else (e.g. chmod) excluded from the changed set; a pure RENAME is content-identical too but is NOT excluded — it is a changed file, listed at its new path. files= means two different things by DEPTH here and is deliberately not renamed (15 consumers read the root one): on the ROOT it is the CHANGED file count; on each <impact/> child it is the distinct files dependents= reaches (changed + non-changed), so dependents="0" implies files="0" and vice versa — never an impossible-looking dependents>0/files=0. files_other= on the same <impact/> is the non-changed subset (a changed file's dependents inside OTHER changed files have no <f> row of their own — they are already shown as their own <file> section); it is NOT the <f> row count — see the row-cap sentence below. Files are ordered by BLAST RADIUS (transitive dependents descending, path breaking ties), not alphabetically. sections= on changed-symbols counts a doc file's headings, collapsed into that number instead of one callers-zero row each; count= still counts every INDEXED symbol, sections included, so count minus sections is the number of rows that follow. Every nested list below is a TOP-N subset of its element's own total, fixed per element (impact <f> at 20, per-symbol <caller> at 12, cochange <partner> at 12, tests <test> at 40, owners <author> at 5 — the L0 defaults; max-tokens only lowers these further via the trim ladder, nothing raises them past L0): each capped element carries its own shown=/capped= pair so the cut is never silent — for the untrimmed list use impact=SYM/callers=SYM (blast radius/callers), affected=FILE or situ (tests), cochange (partners), or owners (authors) instead. direction= names which SIDE this bundle reviews (worktree-since-head, head-since-fork, head-since-ref-tip); a no-ref-work row says the base ref's tip IS the merge base, i.e. it carries no divergent work of its own. deterministic. BUDGET: the bundle is budgeted by default — budget_tokens= is the ceiling in force (8000 unless token-budget/max-tokens set it; budget_default=1 says the default applied); est_tokens= prices the WHOLE document this bundle emits, this legend included, at the map's markup rate of 2.50 bytes per token, and IS the number the ladder fits, so recounting the delivered bytes reproduces it; trim_level=/truncated= what the ladder dropped. When even the structural floor of every changed file exceeds it, the FILES are windowed in blast-radius order: shown= of files=, capped=1 with total=/has_more=/next_offset=/offset=/limit= (limit=0 = the default window), and next= is the one pasteable follow-up (the next page). truncated= carrying budget-floor-exceeded means the smallest document this bundle can render is STILL over budget_tokens= — including on a clean tree, whose whole document is this legend and has no ladder to descend; est_tokens= is then the honest ceiling, never a silent overshoot. counts_floor="1" means every count here is a FLOOR, never a total: edges are extracted from source TEXT by NAME. Missing: dynamic dispatch (virtual/interface/duck-typed), a most-vexing-parse declaration with no call expression, a function-pointer/callback bound to more than one function in scope (reassigned, table-indexed, lambda-bound, or address-taken/reference-bound), and a plain-name binding (fp=handler) whose variable type is not PROVABLY a function pointer (a same-file typedef/declarator; a HEADER typedef is missed; auto/template types are read as unpinned, so KEPT). A macro-generated call site is role="macro" only when its name uniquely names an indexed function-like #define (C-family, t="macro"); a shared name stays a plain call, an unindexed macro is no edge. Read a zero as "none found", never as "none exists". graph_ambiguous=/graph_unresolved= are the whole graph's resolver gauge (calls split over several defs / calls whose in-repo defs were all language-filtered), the map header's ambiguous=/unresolved=. COUNTING UNIT differs by verb: callers, callees, edit-check, graph-query and pr-context counts are DISTINCT SYMBOLS (repeated calls from one caller, and calls to two overloads, collapse into ONE row; multiplicity survives only in the call graph's edge weight). The reach counts (impact's reaches=, pr-context's dependents=) are the size of a transitive reach SET, each symbol counted once. The uses verb counts call SITES, one row per occurrence — a larger count there for the same symbol is these units agreeing, not disagreeing. The map header's edges= is a unit again different — distinct (caller,callee) PAIRS — and that document carries neither this marker nor this clause. -->
<pr-context base="working-tree" root="." direction="worktree-since-head" files="1" skipped_mode_only="0" budget_tokens="8000" est_tokens="4108" trim_level="0" truncated="none" budget_default="1" at="c7725f3ef+dirty" graph_ambiguous="6088" graph_unresolved="3093" counts_floor="1">
<file p="src/infra/sortutil.h" symbols="13">
<impact dependents="103" files="27" files_other="27" shown="20" capped="1">
<f p="src/mcpverbs.h" deps="30"/>
<f p="src/serialize.h" deps="9"/>
<f p="src/main.cpp" deps="7"/>
<f p="src/verbs_quality.h" deps="6"/>
<f p="bench/bench_sort_large.cpp" deps="5"/>
<f p="src/verbs_for.h" deps="5"/>
<f p="src/editplan.h" deps="4"/>
<f p="bench/bench_radix_ab.cpp" deps="3"/>
<f p="src/lanes.h" deps="3"/>
<f p="src/mcpedit.h" deps="3"/>
<f p="src/partition.h" deps="3"/>
<f p="src/verbs_change.h" deps="3"/>
<f p="src/editcheck.h" deps="2"/>
<f p="src/graph.h" deps="2"/>
<f p="src/mcp.h" deps="2"/>
<f p="src/mcpindex.h" deps="2"/>
<f p="src/packtask.h" deps="2"/>
<f p="src/quality.h" deps="2"/>
<f p="test/verify_radix.cpp" deps="2"/>
<f p="src/editpreview.h" deps="1"/>
</impact>
<tests count="3" shown="3" capped="0">
<test p="test/adaptivecutshapefix/adaptive_cut_shape_test.cpp" run="bash test/adaptivecutshapecheck.sh"/>
<test p="test/verify_csr.cpp" run="bash test/a9disclosurecheck.sh"/>
<test p="test/verify_radix.cpp" run="bash test/greptiercheck.sh"/>
</tests>
… [74 more display lines; full output is 10271 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --map-diff --top-k=5`

*The map re-ranked with a teleport toward the changed file (changed=1 here, not 0).*

`````
<!-- ripwire v1 t=fn|method|cls|struct|iface|var|sec|macro(#define;degraded:body-is-replacement-text,edges-cross-expansion) p=path layer=arch-layer(opt) n=name id=canonical(path::scope::name,when-scoped) k=rank c=call amb=ambiguous-calls(read-source) lpin=calls-pinned-by-locality-prior-alone(a-disclosed-guess;read-source;absent-if-0) overloads=N-same-name-defs-merged-into-this-row(absent-if-1;shown=counts-them-individually,so-rows+sum(overloads-1)=shown) prov=scip(precise;else name-based) hdr:unresolved=call-name-defined-only-in-a-lang-incompatible-file (edges heuristic) hdr:locality_pinned=sum-of-lpin(absent-if-0) hdr:external=calls-refused-as-bound-outside-the-tree(builtin/stdlib-name-without-in-repo-evidence,external-import,super-past-the-tree;no-edge;absent-if-0) r:est_tokens=hdr-copy(none-if-stable) -->
<!-- r:root=crawl-root-every-p=-is-relative-to(single-root-only;absent=>p=is-the-raw-ingest-path) -->
<!-- at= is the git commit these numbers were computed at; a trailing +dirty means the working tree differed from that commit, so the numbers describe the tree, not the commit -->
<!-- pr_iters=pagerank-power-iterations(stop:L1-residual-below-tol,else-ceiling) pr_converged=0-only-when-ceiling-hit-first(absent=converged;no-such-attr=not-pagerank-ordered) -->
<!-- files=1588 symbols=13851 edges=17061 shown=5 est_tokens=1181 ambiguous=6088 unresolved=3093 locality_pinned=6 external=788 precise=3 changed=1 skipped_oversize=15 unindexed="txt:59,jsonl:26,tsv:21,scm:18,expected:15,lock:7" unindexed_exts=19 order=important-first -->
<r at="c7725f3ef+dirty" root="." est_tokens="1181" pr_iters="21">
<f p="src/infra/sortutil.h" layer="infra">
<s t="fn" n="radixSortByScoreDescId" id="src/infra/sortutil.h::rw::sortutil::radixSortByScoreDescId" amb="9" k="0.0872">
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
<s t="fn" n="radixSortByFromTo" id="src/infra/sortutil.h::rw::sortutil::radixSortByFromTo" amb="8" k="0.0598">
<c n="size"/>
<c n="begin"/>
<c n="end"/>
… [35 more display lines; full output is 2933 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --clones`

*The duplicated helper the sandbox edit introduced shows up as a clone group.*

`````
<!-- ripwire clones: function bodies with similar normalized token streams (identifiers/literals normalized, so renamed copies match). type=2 exact/renamed (Type-1/2); type=3 gapped near-miss (an inserted/changed statement, similarity in [0.80,1.0)). Reuse don't reimplement; a fix to one likely belongs in all. groups= and type3= are the two GROUP-TYPE totals (each capped independently, so neither is the row count); total= is the true row total (groups + type3-group-count) and is ALWAYS present, paged or not; shown= is the number of group rows that follow this run. capped="1" means rows were dropped. exempt= on a group ⇒ every member is on a path the quality-delta verb's duplication kind deliberately ignores (fixture dirs / shell test-runners repeat boilerplate by convention) — a fact here, never a gate there; exempt_groups= counts them over ALL groups. idiom= on a group names the RECOGNIZED SHAPE every one of its members classifies to, from a CLOSED set of three: threshold-ladder (a chain of if-compare-return and nothing else), switch-name-table (a switch whose every arm is a label plus a literal return), builder-chain (a param-struct initializer chain). demoted="1" additionally means the quality-delta verb's duplication kind reports this group as minor rather than gating on it, which happens only when the WHOLE conjunction holds: every member the same recognized idiom, no two members sharing a single non-keyword identifier, no two members sharing an enclosing context (file plus scope), and the group under 80 normalized tokens. Five cross-domain bucketing ladders that share only the idiom are noise; two ladders over the same enum, or two in one namespace, are a copy. The idiom name is printed precisely so a human can overrule the demotion by reading the members: a demoted row is annotated, never removed. idiom_groups= and demoted_groups= count each of those over ALL groups. FLOOR on the classifier, since a silence here would read as coverage: the shape is read off the body's TOKEN stream and not a parse tree, so a macro-assembled body classifies as whatever its raw tokens spell; the table arm models case-labelled switches only; and builder-chain models the field-assignment spelling, not the fluent chained-call one. gid= on a row is its CLONE COMPONENT: the Type-3 pass reports PAIRS, so three functions that are all near-copies of each other arrive as three rows of two; rows sharing a gid are one cluster, and clone_groups= counts the clusters (union-find over the pair graph, over ALL detected rows, not just the shown ones). dup_pct=duplicated-LOC/total-LOC as a percentage, where duplicated-LOC sums, per cluster, every member's loc EXCEPT the largest member's (one instance is the code you keep, the rest is the redundancy — so a 3-clone cluster counts its lines TWICE) and total-LOC is every function/method body the detector considered; dup_loc= and total_loc= are those two operands. counts_floor="1": the Type-3 pair list is capped upstream, so a dropped pair is a cluster left unmerged — clone_groups/dup_loc/dup_pct are floors, never totals. raise the default cap with limit=N (offset=M pages; a cut listing carries total=/has_more=/next_offset= so a paging loop can continue from it). -->
<!-- root= on this element is the crawl root every p= below is RELATIVE to (single-root runs only; absent => p= is the path ingest itself used, unchanged). -->
<clones groups="76" type3="342" exempt_groups="201" idiom_groups="14" demoted_groups="10" clone_groups="221" dup_loc="4351" total_loc="136581" dup_pct="3.2" counts_floor="1" shown="80" capped="1" total="418" has_more="1" next_offset="80" offset="0" limit="0" root=".">
<group type="2" gid="195" tokens="211" n="4" exempt="shell-runner">
<f n="batch_sub" p="test/mcpclidiffcheck.sh:63"/>
<f n="batch_sub" p="test/mcptranchecheck.sh:55"/>
<f n="batch_sub" p="test/mcpw2fixcheck.sh:52"/>
<f n="batch_sub" p="test/mcpw3fixcheck.sh:51"/>
</group>
<group type="2" gid="213" tokens="149" n="3" exempt="shell-runner">
<f n="monotonic_check" p="test/pyimportprecisecheck.sh:89"/>
<f n="monotonic_check" p="test/rustimportprecisecheck.sh:124"/>
<f n="monotonic_check" p="test/tsimportprecisecheck.sh:88"/>
</group>
<group type="2" gid="39" tokens="142" n="2">
<f n="test_tier2_accept_big_quality_small_cost" p="bench/locbench/test_compare_gate.py:130"/>
<f n="test_tier2_reject_small_quality_big_cost" p="bench/locbench/test_compare_gate.py:143"/>
</group>
<group type="2" gid="159" tokens="126" n="2">
<f n="addWholeFileFn" p="test/cloneband_harness.cpp:64"/>
<f n="addWholeFileFn" p="test/type3clone_harness.cpp:47"/>
</group>
<group type="2" gid="46" tokens="121" n="2">
<f n="resolve_arm" p="hooks/ripwire-claude-route.sh:75"/>
<f n="resolve_arm" p="hooks/ripwire-claude-toolroute.sh:134"/>
</group>
<group type="2" gid="70" tokens="118" n="2">
<f n="rankFiles" p="src/eval.h:53"/>
<f n="rankCandidates" p="src/skilleval.h:426"/>
</group>
… [309 more display lines; full output is 18625 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --stray-content=zz-orphan`

*CHANGED: a ref with NO merge base with HEAD now reports v="unknown" ok="0" in its own bucket — the absence of an answer, never a claim it is merged. (The sandbox carries a deliberately parentless branch built with `git commit-tree`; a shallow CI clone puts every ref here.)*

`````
<!-- ripwire stray-content: per ref, the lines its own divergent work AUTHORED (vs its merge-base with HEAD) that the live line does NOT have. v="superseded" means the live line removed the same base code this ref removed (redone/del) — it re-implemented the work, the case `git cherry` cannot see; v="unmerged" means the work is genuinely absent; merged refs are omitted. Read-only: git cat-file/diff/ls-tree only, one batched cat-file for the whole sweep, every blob reduced once per sha. Line-granular, not semantic: see the ripwire help text for the limits. ANCHORING is a deliberate hybrid: the SCOPE is base anchored (only lines the ref itself authored vs its merge base are ever considered, so a file the ref never opened cannot appear because the live line moved), while the ABSENCE test is HEAD anchored on purpose (does the live line have this content TODAY is the question being asked, and it is only answerable against live HEAD). v="unknown" with ok="0" means this ref could NOT be analysed at all because it has no merge base with HEAD, which on a SHALLOW clone (the checkout default in CI) is every ref: it is not a claim that the ref is merged, and the fix is to deepen the clone. The four buckets are exhaustive, so unmerged plus superseded plus merged plus unknown always equals refs. SCOPE: refs/heads only, which is every local branch (worktree branches included). Remote tracking refs are NOT scanned: they mirror local ones in the usual checkout and would double every row. The consequence on a FRESH CLONE, where the branches live under refs/remotes/origin and only the checked out one has a local head, is that there is nothing here to be stray FROM; refs= is that fact as a number. TRUNCATION: a ref row ends with a more element (more files=N) when its own file listing was capped; shown plus that number equals the ref's files= total, always. That inner listing is a SECONDARY listing (it repeats complete and identical on every page) and is capped by detail, not by limit / offset, which page the OUTER ref listing and report their own shown= / capped=. at= is the git commit these numbers were computed at; a trailing +dirty means the working tree differed from that commit (head= is the same commit, bare sha, kept for compatibility). -->
<stray-content head="c7725f3ef" head_ref="integration/terminality-2026-09-05" refs="1" blobs="0" unmerged="0" superseded="0" merged="0" unknown="1" filter="zz-orphan" at="c7725f3ef+dirty">
<ref name="zz-orphan-lane" tip="aac7ba331" date="2026-09-05" base="" ok="0" v="unknown" stray="0" files="0" superseded="0">
</ref>
</stray-content>
`````

stderr:

`````
[math degraded] crossref: no merge-base for ref (shallow clone or unrelated history?) — verdict is unknown, not merged  (crossref.h:1053, RefPlumbing rw::crossref::probeRefBase(const std::string &, const RefInfo &, const std::string &) — logged once per site)
`````

## `./build/ripwire . --stray-content=zz-orphan --plan`

*CHANGED: --plan surfaces those same refs as an <undetermined> row rather than silently dropping them.*

`````
<!-- ripwire landing-plan: stray-content's cheap per-blob sweep composed with merge-scout's per-arm overlap oracle — of every local branch, which still hold REAL work (v="unmerged"), which were already re-implemented on the live line (v="superseded", EXCLUDED below — landing them re-does work that is already done) or are already merged (omitted entirely, counted in merged= on the root element), and the fewest-conflicts-first order to land what remains. scouted="0" on an unmerged ref means it was NOT fed to merge-scout this run (the cost bound, not a verdict) — it is still real, unscouted work; bounded= on the root element counts them and detail lifts the bound. merge-scout is the EXPENSIVE step here (git-archive + full ingest per arm) — stray-content's own sweep is the cheap one. An undetermined row is a ref that could NOT be analysed at all (no merge base with HEAD, which on a SHALLOW clone is every ref): it is neither scouted nor excluded nor merged, because nothing was measured — treat it as unfinished business and deepen the clone, never as a clean branch. Read-only throughout: no checkout, no ref write, no working-tree mutation. The root carries BOTH head= and at= and they are the same commit: head= is the bare 9 hex chars this verb has always printed, at= is the tool wide anchor and is head= plus a "+dirty" suffix when the working tree is not clean. Prefer at= (it is the one spelling every other repo reading verb uses, and the only one that tells you whether uncommitted work was in scope); head= is kept for callers already keyed to it. -->
<landing-plan head="c7725f3ef" refs="1" unmerged="0" superseded="0" merged="0" undetermined="1" scouted="0" bounded="0" scout-ok="1" at="c7725f3ef+dirty">
<undetermined name="zz-orphan-lane" v="unknown" reason="no merge base with HEAD (shallow clone or unrelated history) — this ref could not be analysed, it is NOT known to be merged; deepen the clone and re-run"/>
</landing-plan>
`````

stderr:

`````
[math degraded] crossref: no merge-base for ref (shallow clone or unrelated history?) — verdict is unknown, not merged  (crossref.h:1053, RefPlumbing rw::crossref::probeRefBase(const std::string &, const RefInfo &, const std::string &) — logged once per site)
`````

## `./build/ripwire . --dmm`

*The DMM scalar on a REAL delta: the sandbox edit grew one unit past the nesting/complexity thresholds and added an 8-parameter one, so dmm is low and the three sub-scores say which property moved.*

`````
<!-- ripwire dmm: the Delta Maintainability Model (di Biase, Rastogi, Bruntink, van Deursen, TechDebt 2019), ONE comparable scalar per change. Thresholds and arithmetic are PyDriller's deltamaintainability reference implementation. A UNIT is a function or method definition WITH A BODY; its VOLUME is its line span. Per property a unit is LOW risk iff size: loc at most 15, complexity: cyclomatic at most 5, interfacing: params at most 2. good=volume of low-risk code ADDED plus high-risk code REMOVED bad=volume of low-risk code REMOVED plus high-risk code ADDED dmm=good/(good+bad), in [0,1]: 1.000 means every line this change moved made the code healthier. THIS IS A DELTA, NOT A LEVEL: editing bad code without growing it moves nothing and scores nothing, which is deliberate. dmm=UNAVAILABLE means good+bad was 0, i.e. the change moved no unit's size, complexity or parameter count, and is NEVER to be read as 1.000 or 0.000; reason= says which case it was. base=the earlier tree's commit target=the later tree's commit, or working-tree base_units= target_units= units measured on each side base_volume= target_volume= their total line span combine=how the root dmm= pools the three sub-scores (pooled = summed good over summed good+bad; the paper publishes the three separately and no aggregate, so this one is ripwire's) size_metric=physical-loc: volume is the definition's PHYSICAL line span, where the reference implementation uses non-comment non-blank lines, so a heavily commented unit crosses the size threshold here earlier at= is the git commit this comparison RAN at (HEAD, not base/target — those name what was compared); a trailing +dirty means the working tree differed from that commit available=0 when no score could be produced at all low_loc=/low_cx=/low_params= are the low-risk ceilings a unit is judged against (lines / cyclomatic complexity / parameters). p=one property row k=its name (size|complexity|interfacing) d_low=change in low-risk volume d_high=change in high-risk volume. Every indexed language and every indexed path counts, tests and fixtures included; params and cyclomatic complexity come from the index, so a definition whose grammar exposes no parameter list contributes params=0 and classifies LOW on interfacing. -->
<dmm base="c7725f3ef85892534460f952e35816caad67dac2" target="working-tree" at="c7725f3ef+dirty" available="1" combine="pooled" size_metric="physical-loc" low_loc="15" low_cx="5" low_params="2" dmm="0.142" good="23" bad="139" base_units="7979" base_volume="136527" target_units="7981" target_volume="1 … [line truncated: 7 more bytes on this line]
<p k="size" dmm="0.130" good="7" bad="47" d_low="7" d_high="47"/>
<p k="complexity" dmm="0.130" good="7" bad="47" d_low="7" d_high="47"/>
<p k="interfacing" dmm="0.167" good="9" bad="45" d_low="9" d_high="45"/>
</dmm>
`````

## `./build/ripwire . --quality-delta --scope=src/graph.h`

*OWNERSHIP partition for a shared tree: every regression here lives in src/infra/, so under a scope naming src/graph.h they ALL print under <out-of-scope> with a do-not-ack banner and never gate — scoped-out-gating= says how many would have.*

**wall time: 1.85s**

`````
<!-- ripwire quality-delta: only what a change made WORSE against the floor baseline= names below. Descriptive: weigh and fix the real ones, do not game the number (a wrong abstraction beats a low score). TEN KINDS, and kind= on every row names which one: complexity over the ccx bar, verbosity (LOC), nesting, params, duplication, dead-code, api-surface (new public contract drift), error-masking, short-horizon-churn, new-clone-of-reused-helper. THREE independent axes, in this order: (1) acked findings are suppressed entirely (acked= counts them); (2) ORIGIN — a finding on a symbol that EXISTED at the baseline is preexisting-worse (no origin attribute), one that exists only because the code is NEW carries origin="new-symbol"; (3) MATERIALITY — a small numeric delta is sev="minor", and minor= counts them. EXIT 2 fires only on preexisting-worse AND major, the gating= count; new-symbol rows never gate, so exit 0 is NOT a verdict on them — nothing that existed got worse, but the new debt is yours: read them. Clone kinds are new-symbol only when EVERY member is new; short-horizon-churn is preexisting by construction. preexisting-worse= and new-symbol= partition regressions=. stale= is a FOURTH axis, never gating and never counted in regressions=: rows in the .ripwire_quality_acks ledger whose target no longer applies. register-macro-excluded= is a FLOOR, not a finding: symbols this run excluded from the dead-code kind because their own definition is a registered self-registering test/benchmark macro call. Never gates, never counted in regressions=, printed even at zero (zero means none excluded, not that the check did not run). A gating row's next= is the one pasteable follow-up: expand on FILE:NAME, the body to fix (a duplication row names a SET and carries none). bar= on a complexity/verbosity/nesting/params row is the threshold now= is judged against (ccx 15, loc 60, nest 4, params 5). baseline="git-HEAD" means no sidecar existed, so the working tree was auto-compared against the HEAD tree — anything already committed cannot appear. at= is the git commit (plus a dirty marker when the working tree differs) this list was computed at. The registered families are doctest/Catch2 TEST_CASE, GoogleTest TEST/TEST_F/TEST_P, Google Benchmark BENCHMARK, plus any name a .ripwire_config register_macros= line adds; each registers itself through a static initializer the call graph cannot see, so zero in-edges on one is not evidence of anything. IDENTITY across a rename or a move: a finding is keyed path::scope::name, which a rename would destroy, so the baseline and the .ripwire_quality_acks ledger are both re-filed into the CURRENT tree's identity before either is read, by two EXACT mechanisms — git's own rename record, and equality of a whitespace-and-name-scrubbed body hash — never a similarity heuristic. renames= is how many rename pairs were read, rename_window_commits= how deep the commit window went, acked_by_rename= and acked_by_content= how many of the acked= suppressions each mechanism is responsible for. Three appear ONLY when true, so an absent one is not a silent no: renames_window_truncated= (history is deeper than the window), renames_truncated= (the pair cap was hit), renames_ambiguous= (an ancestor two current symbols both claim — refused rather than guessed). ORIGIN reads the re-filed baseline too, so a regression carried in with a rename is judged preexisting-worse and GATES instead of slipping through as new-symbol. FLOORS, stated because silence here would read as a guarantee: the two clone kinds key on a member-SET hash and are NOT re-filed, so a clone ack still dies on a rename; ORIGIN follows the rename record but never content, because the baseline stores no content id at all; and a move git recorded no rename for still reads as new-symbol. Each sa row carries key= (the ack identity as stored) and why=, which is target-gone (the key names no symbol or group any more) or finding-gone (the target survived, this kind just does not fire on it). sym= and p=path:line name WHICH ack it is, and are present exactly when the key still names a live symbol: on every finding-gone row, on none of the target-gone rows (there is nothing left to name), and on neither clone kind — a clone key hashes a member SET that no single symbol carries, so those rows are unnameable by construction rather than guessed at. Hygiene disclosure only — the ledger file is never auto-edited. ROWS: sym= is the canonical id the finding regressed on; was= and now= carry the before/after value for the numeric kinds; p="path:line" is the locator (root-relative; the first-sorting member for the clone kinds; omitted, never faked, when none resolves). churn= and surface= are per-kind classification facets (short-horizon-churn's self/ambient split; api-surface's new-symbol/contract-change tier). Every row the header's gating= counter counts also carries a gating attribute set to 1 — marked positively, never by the ABSENCE of sev or origin. CLONE ROWS name the whole group rather than one symbol: members= is the member list and tokens= its shared normalized-token count (the same per-group pair the clones verb reports). idiom= names a RECOGNIZED BODY SHAPE every member spells, out of a closed set of three (threshold-ladder, switch-name-table, builder-chain). idiom= alone changes nothing; a group that ALSO shares no non-keyword identifier between any two members, sits in pairwise-distinct enclosing contexts, and stays under 80 normalized tokens is an idiom COLLISION rather than a copy, and is reported minor instead of gating. Break any one of those and it gates as before, idiom= and all: two bucketing ladders over the SAME enum are a copy. The shape is read off the body's token stream and not a parse tree, so a macro-assembled body classifies as whatever its raw tokens spell — the name is printed so the call can be overruled by reading. SCOPE, present only when the scope flag was given, and it NARROWS WHAT THIS REPORT CLAIMS: scope= is the pattern list it was given, verbatim. Every counter above (regressions=, minor=, acked=, preexisting-worse=, new-symbol=, gating=) is then over the IN-SCOPE findings alone, and the exit code follows gating= as always. The rest are not dropped: scoped-out= counts the findings filed to somebody else, and every one of them is printed inside an out-of-scope element carrying n= (the same count), would-gate= and note= (the do-not-ack banner). scoped-out-gating= repeats would-gate= on the root because it is the number a reader must not miss: it is how many disclosed rows WOULD have fired the exit code, so exit 0 under a scope means "nothing of YOURS is broken", never "the tree is clean". Rows inside that element carry the identical attributes to the ones above it and never carry the gating attribute, since they are not what this exit code fires on. HOW A FINDING IS FILED: by its p= path, matched root-relative against the patterns; a clone kind is in scope when ANY member matches, not just the first-sorting one; and a finding with no locator at all is filed OUT of scope, because under a scope "we cannot say where this is" honestly reads as not provably yours. -->
<quality-delta baseline="git-HEAD" regressions="0" minor="0" acked="0" stale="19" preexisting-worse="0" new-symbol="0" gating="0" register-macro-excluded="3" at="c7725f3ef+dirty" renames="55" rename_window_commits="400" acked_by_rename="0" acked_by_content="0" renames_window_truncated="1" scope="src … [line truncated: 47 more bytes on this line]
<out-of-scope n="8" would-gate="4" note="not yours - do not ack: these rows lie outside the scope this run named. They are disclosed rather than hidden, they never gate this exit code, and the ack refuses to write them.">
<r kind="api-surface" sym="src/infra/sortutil.h::rw::sortutil::nonNegativeFloatAscKeyCopy" sev="minor" surface="new-symbol" origin="new-symbol" p="src/infra/sortutil.h:119"/>
<r kind="api-surface" sym="src/infra/sortutil.h::rw::sortutil::nonNegativeFloatDescKey" was="1" now="2" surface="contract-change" p="src/infra/sortutil.h:109"/>
<r kind="api-surface" sym="src/infra/sortutil.h::rw::sortutil::sortScoredIdsWithOptions" sev="minor" surface="new-symbol" origin="new-symbol" p="src/infra/sortutil.h:129"/>
<r kind="complexity" sym="src/infra/sortutil.h::rw::sortutil::lessByScoreDescId" was="1" now="67" bar="15" p="src/infra/sortutil.h:49"/>
<r kind="duplication" members="src/infra/sortutil.h::rw::sortutil::nonNegativeFloatAscKeyCopy | src/infra/sortutil.h::rw::sortutil::nonNegativeFloatDescKey" tokens="59" p="src/infra/sortutil.h:119"/>
<r kind="nesting" sym="src/infra/sortutil.h::rw::sortutil::lessByScoreDescId" was="1" now="6" bar="4" p="src/infra/sortutil.h:49"/>
<r kind="new-clone-of-reused-helper" sym="src/infra/sortutil.h::rw::sortutil::nonNegativeFloatAscKeyCopy | src/infra/sortutil.h::rw::sortutil::nonNegativeFloatDescKey" was="0" now="4" p="src/infra/sortutil.h:119"/>
<r kind="params" sym="src/infra/sortutil.h::rw::sortutil::sortScoredIdsWithOptions" was="0" now="8" bar="5" origin="new-symbol" p="src/infra/sortutil.h:129"/>
</out-of-scope>
<sa kind="api-surface" key="298e798c7f075715" why="target-gone"/>
<sa kind="api-surface" key="5a07390012b46e06" why="target-gone"/>
<sa kind="api-surface:new-symbol" key="1926b0d9e94541a0" why="target-gone"/>
<sa kind="api-surface:new-symbol" key="79625906f9f71ad0" why="target-gone"/>
<sa kind="api-surface:new-symbol" key="995375dfa4e63104" why="target-gone"/>
<sa kind="complexity" key="4b309450f25c2b44" why="finding-gone" sym="src/ingest.cpp::rw::ingest" p="src/ingest.cpp:191"/>
<sa kind="complexity" key="53a1214d5505fa41" why="finding-gone" sym="main" p="src/main.cpp:2634"/>
<sa kind="duplication" key="160ac41979d9ebaf" why="finding-gone"/>
<sa kind="duplication" key="af2e342eda9648ed" why="finding-gone"/>
<sa kind="duplication" key="c8b32435256b863e" why="finding-gone"/>
<sa kind="nesting" key="1bded1f8f88d3b85" why="finding-gone" sym="src/slice.h::slicev::sliceFlowCompute" p="src/slice.h:2286"/>
<sa kind="nesting" key="3c07d993bfdbce53" why="finding-gone" sym="src/slice.h::slicev::sliceBundleText" p="src/slice.h:2685"/>
<sa kind="new-clone-of-reused-helper" key="0e9742973611fd71" why="finding-gone"/>
<sa kind="new-clone-of-reused-helper" key="5a0ff811529d5c95" why="finding-gone"/>
<sa kind="new-clone-of-reused-helper" key="c8b32435256b863e" why="finding-gone"/>
<sa kind="new-clone-of-reused-helper" key="d11c67611bc73d49" why="finding-gone"/>
<sa kind="params" key="f6dedd851e4b2a25" why="finding-gone" sym="src/slice.h::slicev::sliceWalk" p="src/slice.h:1122"/>
<sa kind="verbosity" key="15061a69cb5b451f" why="finding-gone" sym="src/packtask.h::rw::packTaskHeaderText" p="src/packtask.h:226"/>
<sa kind="verbosity" key="53a1214d5505fa41" why="finding-gone" sym="main" p="src/main.cpp:2634"/>
</quality-delta>
`````

stderr:

`````
ripwire: no ./.ripwire_quality_baseline — auto-comparing the working tree vs git HEAD (commit the baseline with --quality-baseline to pin it)
`````

## `./build/ripwire . --quality-delta --quality-ack --scope=src/graph.h --ack-only=api-surface`

*The rubber-stamp guard: an --ack-only that names an OUT-OF-SCOPE row refuses (exit 1) and writes nothing.*

**exit code: 1** — **wall time: 1.19s**

`````
(empty)
`````

stderr:

`````
ripwire: no ./.ripwire_quality_baseline — auto-comparing the working tree vs git HEAD (commit the baseline with --quality-baseline to pin it)
ripwire: --ack-only=api-surface selects 3 finding(s) OUT OF SCOPE for --scope=src/graph.h — refusing, and writing nothing at all:
    api-surface src/infra/sortutil.h::rw::sortutil::nonNegativeFloatAscKeyCopy at src/infra/sortutil.h:119
    api-surface src/infra/sortutil.h::rw::sortutil::nonNegativeFloatDescKey at src/infra/sortutil.h:109
    api-surface src/infra/sortutil.h::rw::sortutil::sortScoredIdsWithOptions at src/infra/sortutil.h:129
  those rows belong to whoever is editing those paths. Acking them here writes their debt into a committed ledger under YOUR
  reason string, which is how a per-finding ratchet becomes a rubber stamp. Narrow the pattern, or widen the scope if they really are yours.
`````

## `./build/ripwire . --handoff`

*The continuation packet with a REAL diff: verified changed symbols + blast radius + tests-to-run, then the heuristic rows.*

`````
<!-- ripwire handoff: the continuation packet for the NEXT session. <verified> is disk truth (branch=/at=<sha>[+dirty]/subject=<commit subject text>, changed files+symbols via git numstat, blast_files=transitive dependent files, tests-to-run); run= is the command that discharges a test row; run_unknown="1" means none is derivable for that harness (a guess would be worse than none) — a row carries one or the other, never neither. <heuristic> is labeled non-verified suggestion (cochange=usually-edited-together deg=degree, note=committed .ripwire_notes row, doc=plan/design pointer s=lexical score for the branch+commit-subject query). branch= is git's own answer, so on a DETACHED head it reads HEAD and detached=1 says so (the commit is at=); detached= is absent when a branch is checked out. &lt;heuristic n= candidates= capped=&gt;: n= is the rows in the packet, candidates= how many the three classes produced before their own per-class caps (cochange 8, notes 8, docs 4), capped=1 when a cap dropped one — so candidates - n - withheld_rows is what the caps removed and nothing is lost silently. budget= is the token-budget cap; withheld=1 when heuristic rows were dropped to fit it, withheld_rows= how many (the map's spelling: a boolean, the count beside it) — verified rows are never dropped; est_tokens= prices the delivered packet in tokens and over_ceiling= is 1 when even the verified floor exceeds budget= (the packet is then complete, not trimmed). gitok=0 means the git diff probe failed and changed counts are floors. -->
<handoff at="c7725f3ef+dirty" root="." branch="integration/terminality-2026-09-05" subject="test(gates): N1 — shapingflagcheck&apos;s timeout budget back to 1200; compactlegendcheck stays at 900" gitok="1" est_tokens="1064">
<verified changed="1" blast_files="27">
<f p="src/infra/sortutil.h">
<s n="svLess"/>
<s n="lessByScoreDescId"/>
<s n="radixSortUint32ByKey"/>
<s n="nonNegativeFloatDescKey"/>
<s n="nonNegativeFloatAscKeyCopy"/>
<s n="sortScoredIdsWithOptions"/>
</f>
<tests n="3">
<t p="test/adaptivecutshapefix/adaptive_cut_shape_test.cpp" run="bash test/adaptivecutshapecheck.sh"/>
<t p="test/verify_csr.cpp" run="bash test/a9disclosurecheck.sh"/>
<t p="test/verify_radix.cpp" run="bash test/greptiercheck.sh"/>
</tests>
</verified>
<heuristic n="4" candidates="129" capped="1">
<doc p="docs/SUBSTITUTION_METER.md" s="8.687"/>
<doc p="docs/EVALS.md" s="8.651"/>
<doc p="docs/METHODOLOGY.md" s="8.533"/>
<doc p="docs/CODEX_ORCHESTRATION.md" s="7.624"/>
</heuristic>
</handoff>
`````

## `./build/ripwire . --note-add="lessByScoreDescId: keep this branch-free — it sits inside the PageRank sort comparator"`

*Pin a field note (write-side memory) to a symbol; committed to .ripwire_notes in the sandbox. The BARE name is resolved through the same resolver the read verbs use and stored as the canonical id — the rewrite is echoed on stderr, because a silent one is not a disclosure.*

`````
src/infra/sortutil.h::rw::sortutil::lessByScoreDescId	2026-09-05	keep this branch-free — it sits inside the PageRank sort comparator	c7725f3ef85892534460f952e35816caad67dac2	integration/terminality-2026-09-05
`````

stderr:

`````
ripwire: --note-add: tip: notes that say "chose X over Y because Z" surface better — consider adding the why
ripwire: --note-add: target 'lessByScoreDescId' canonicalised to 'src/infra/sortutil.h::rw::sortutil::lessByScoreDescId' — that is the id --for/--expand key notes by
`````

## `./build/ripwire . --notes`

*The note is listed under the canonical id, dangling="0" — i.e. it will actually surface. (Before the H1 fix the bare name was stored verbatim and read dangling="1": recorded, and surfaced nowhere.)*

`````
<ctx>
<!-- ripwire field notes: notes=2 targets=2 dangling=0 (a target with no matching indexed symbol/file — legal: listed here, surfaced nowhere). Each note row: d= is the ISO date it was recorded; sha= the abbreviated commit and branch= the branch checked out at record time, both omitted entirely on a note stored before provenance stamping (absent means none recorded, never empty) -->
<notes>
<target id="src/infra/sortutil.h::rw::sortutil::lessByScoreDescId" dangling="0">
<note d="2026-09-05" sha="c7725f3" branch="integration/terminality-2026-09-05">
<![CDATA[keep this branch-free — it sits inside the PageRank sort comparator]]>
</note>
</target>
<target id="test/manifestcheck.sh" dangling="0">
<note d="2026-08-23" sha="42634f5" branch="claude/fervent-volhard-ddfd9f">
<![CDATA[README.md's single '<N> gate scripts' claim (~line 1305) is NOT enforced — the derived-vs-stated sibling loop here covers docs/EVALS.md only. It drifted 407→451 unnoticed (fixed 2026-08-23). To close: grep both files ('file:line:' parsing) in the gateCountClaims arm.]]>
</note>
</target>
</notes>
</ctx>
`````

## `./build/ripwire . --note-add="gitOneLine: which one?"`

*Two definitions carry this name, so the write REFUSES rather than pick one: a note keys ONE canonical id, and an ambiguous selector is refused, never silently narrowed. Every candidate is named, with a runnable retry.*

**exit code: 1**

`````
(empty)
`````

stderr:

`````
ripwire: --note-add: tip: notes that say "chose X over Y because Z" surface better — consider adding the why
ripwire: --note-add: target 'gitOneLine' is ambiguous — it matches 2 definitions in 2 distinct contracts, and a note keys ONE canonical id (it would surface on one of them and look absent on the rest). Qualify one: ./src/handoff.h:gitOneLine, ./src/quality.h:gitOneLine — e.g. --note-add="./src/h … [line truncated: 33 more bytes on this line]
`````

## `./build/ripwire . --note-add="lessByScoreDescIdd: typo"`

*A name that resolves to nothing is refused with the read verbs' own did-you-mean — never written as a dead note.*

**exit code: 1**

`````
(empty)
`````

stderr:

`````
ripwire: --note-add: tip: notes that say "chose X over Y because Z" surface better — consider adding the why
ripwire: --note-add: target not found: lessByScoreDescIdd (did you mean 'lessByScoreDescId'?) — a note keys the canonical id a read verb resolves; to note a FILE instead, pass a path (one with a '/' or an extension), which may name a file that does not exist yet
`````

## `./build/ripwire . --note-add="src/infra/sortutil.h::rw::sortutil::lessByScoreDescId: chose the flat two-branch compare over the nested ladder because the comparator sits inside the PageRank sort"`

*The same symbol addressed by its CANONICAL id: already canonical, so nothing is rewritten and both notes land on ONE target.*

`````
src/infra/sortutil.h::rw::sortutil::lessByScoreDescId	2026-09-05	chose the flat two-branch compare over the nested ladder because the comparator sits inside the PageRank sort	c7725f3ef85892534460f952e35816caad67dac2	integration/terminality-2026-09-05
`````

## `./build/ripwire . --expand=lessByScoreDescId --top-k=0`

*Both notes riding along with the symbol's body — the <note> elements follow the body, past the display cut, so they are extracted below.*

`````
<ctx root="." est_tokens="958">
<!-- a body's sibs="a,b,..." sibs_total=N are the file's OTHER indexed symbols (this body's own name excluded), source order, capped at 8 (sibs_capped="1" when the cap fired); inc="x.h,..." inc_total=N are the file's own #include/import targets, source order, capped at 24 (inc_capped="1" when the cap fired) — both absent when the count is 0 (a documented zero, not a degrade). Each body's own calls child (1-hop callee signatures) carries total=/shown=/capped="1" the usual way: capped="1" only when shown is below total. A body's CDATA is the bytes on disk unless the element says otherwise: scrubbed="1" = a ]]> was split (]]]]>
<![CDATA[>, rejoin it) or a C0/invalid-UTF-8 byte was replaced; redacted="1" = a credential shape was rewritten to a [REDACTED:kind] marker (the no-redact flag serves the bytes; the edit verbs refuse a payload carrying MORE such markers than the bytes it would replace already do, so source that spel … [line truncated: 59 more bytes on this line]
<bodies shown="1" total="1" capped="0">
<b t="fn" l="49" p="src/infra/sortutil.h" n="lessByScoreDescId" sibs="svLess,radixSortUint32ByKey,nonNegativeFloatDescKey,nonNegativeFloatAscKeyCopy,sortScoredIdsWithOptions,radixSortNonNegativeFloatsDesc,scratch,radixSortByScoreDescId" sibs_total="12" sibs_capped="1" inc="radixSort.h,algorithm,bit, … [line truncated: 56 more bytes on this line]
<![CDATA[inline bool lessByScoreDescId( const std::vector<float>& scores, std::uint32_t a, std::uint32_t b ) noexcept
{
    if( a < scores.size() )
    {
        if( b < scores.size() )
        {
            if( scores[ a ] != scores[ b ] )
            {
                if( scores[ a ] > scores[ b ] )
                {
                    if( scores[ a ] > 0.0f && scores[ b ] > 0.0f ) return true;
                    else if( scores[ a ] > 0.0f && scores[ b ] == 0.0f ) return true;
                    else if( scores[ a ] == 0.0f || scores[ b ] == 0.0f ) return true;
                    else return true;
                }
                else
                {
                    if( scores[ b ] > 0.0f && scores[ a ] > 0.0f ) return false;
                    else if( scores[ b ] > 0.0f && scores[ a ] == 0.0f ) return false;
                    else if( scores[ b ] == 0.0f || scores[ a ] == 0.0f ) return false;
                    else return false;
                }
            }
            else
            {
… [22 more display lines; full output is 3677 bytes on 47 raw line(s)]
`````

The <note> element on the same output — past the 30-line display cut above:

`````
<note d="2026-09-05" sha="c7725f3" branch="integration/terminality-2026-09-05">
<![CDATA[chose the flat two-branch compare over the nested ladder because the comparator sits inside the PageRank sort]]>
</note>
<note d="2026-09-05" sha="c7725f3" branch="integration/terminality-2026-09-05">
<![CDATA[keep this branch-free — it sits inside the PageRank sort comparator]]>
</note>
`````

## `./build/ripwire . --replace-symbol-body=lessByScoreDescId --edit-payload=<scratch>/aux/empty_payload.h`

*An EMPTY payload refuses — it never implies deletion.*

**exit code: 1**

`````
(empty)
`````

stderr:

`````
ripwire: --edit-payload is empty; empty never means delete
`````

## `./build/ripwire . --replace-symbol-body=lessByScoreDescId --edit-payload=<scratch>/aux/payload_lessByScoreDescId.h`

*Whole-symbol replace without a whole-file read: the payload is the ORIGINAL flat body, so this edit undoes the sandbox's deep-nesting regression. The receipt's span is the POST-edit byte range; replaced_bytes counts the old bytes overwritten.*

Input file:

`````
inline bool lessByScoreDescId( const std::vector<float>& scores, std::uint32_t a, std::uint32_t b ) noexcept
{
    if( scores[a] != scores[b] )
    {
        return scores[a] > scores[b];
    }
    return a < b;
}
`````

`````
{"applied":"replace_symbol_body","symbol":"lessByScoreDescId","file":"src/infra/sortutil.h","span":{"start":2162,"end":2375},"lines":{"start":49,"end":56},"replaced_bytes":1718,"old_file_bytes":9918,"new_file_bytes":8413,"file_eol":"lf","eol_normalized":false,"trailing_newline_folded":true,"separato … [line truncated: 713 more bytes on this line]
"graph_ambiguous":6085,"graph_unresolved":3093,"counts_floor":true},"tests_to_run":[{"p":"test/adaptivecutshapefix/adaptive_cut_shape_test.cpp","run":"bash test/adaptivecutshapecheck.sh"},
{"p":"test/verify_csr.cpp","run":"bash test/a9disclosurecheck.sh"},
{"p":"test/verify_radix.cpp","run":"bash test/greptiercheck.sh"}],
"tests":3,"script_gates_unmodelled":574,"graph_ambiguous":6085,"graph_unresolved":3093,"counts_floor":true,"next":"bash test/adaptivecutshapecheck.sh"}
`````

stderr:

`````
ripwire edit: applied atomically; receipt carries region, blob_sha, edit_check, tests_to_run; next: bash test/adaptivecutshapecheck.sh
`````

## `./build/ripwire . --edit-check=lessByScoreDescId`

*The closed loop: contract unchanged (same params, same publicness) after the replace — nothing provably incompatible.*

`````
<!-- ripwire edit-check: SYM's contract (param count + publicness) NOW vs git HEAD — unchanged/new-symbol/contract-change — plus its 1-hop callers. A caller is flagged incompatible="1" when its argument count was reliably counted and NO definition in the folded set could accept it: every one has a FIXED arity that disagrees. A variadic, defaulted or implicit-receiver definition (a Python/Ruby method, whose params counts the self/cls the call site never writes) has no fixed arity and is never flagged. That makes the ARITY half one-sided — a call the compared definitions could accept is never flagged — but it is NOT a proof that the call site binds to THIS definition. Call edges are matched by NAME, so a receiver-qualified call to a same-named callee this tool does not index (a standard-library or third-party method) is measured against the one definition it does index; a clean, compiling tree can therefore carry a nonzero incompatible= with nothing edited at all, and on a widely-shared name it can be most of that name's callers. Read incompatible= as a fact about the tree as it stands — call sites worth OPENING, not a verdict — and status= as a fact about the edit. Warm path hits the qheadsnap/qsnap cache — never a full quality-delta style recompute. defs= is how many DEFINITIONS at this site (same file, same scope, same name — the overload set) are folded into this one contract; a selector matching more than one SITE is refused instead, so defs= only ever counts overloads. params_was and params_now are the MAX over that set on each side (the same MAX the baseline snapshot stores), and publicness is the OR. That MAX has TWO consequences, in opposite directions. It can read like a break and not be one: adding a WIDER overload beside an unchanged one raises params_now with no existing definition altered, so it reports status="contract-change" with incompatible="0" and a def row still carrying the old parameter count — no seen caller breaks. And it can read like safety and not be: REMOVING an overload whose parameter count is BELOW the MAX moves neither number, because the MAX survives on both sides, while the call site that used the removed definition no longer binds. defs_was=/defs_now= is what closes that: the count of definitions sharing this symbol's DEFINITION SITE — same file, same scope, same name — on each side. That is the population the baseline snapshot buckets by, so the two numbers answer the same question and are equal on an unedited tree. A same-named definition in ANOTHER FILE is a different contract and is counted on neither side, so defs_now= agrees with the root's defs= by construction and only defs_was= can move it. status is therefore the join of THREE was-vs-now facts — the params MAX, publicness, and the definition COUNT — and change= names which of them carried it. change= adds broken-callers when a seen caller is also flagged, but never on its own — for the reason stated at the top: incompatible= describes the TREE and status= describes the EDIT, so a headline must not turn on it. RESIDUAL: an overload whose arity changes BELOW the MAX while the COUNT stays the same moves none of the three. The root's incompatible= is the COUNT of flagged callers (a c row's incompatible="1" is the per-caller flag). sites_l= rides on a flagged row only: a c row's p= is where that CALLER is DEFINED, and sites_l= is the ascending LINE list of its call-role reference sites to this name — the lines to open, the same rows the uses verb prints, including the ones whose argument count could not be counted (so sites_l= can be wider than the evidence the flag rests on). Two calls on one line are ONE site. p= is the definition the selector resolved to; when defs is above 1 EVERY folded definition is listed as its own def row (p=, t=, params=), which is what tells a widened single definition apart from an added overload. At defs="1" no def row is emitted: the root's own p=/t= is that definition, and params_now is its parameter count. next= is the one pasteable follow-up: on a contract-change the uses verb on SYM (the call sites), otherwise the test gate on the definition's file. counts_floor="1" means every count here is a FLOOR, never a total: edges are extracted from source TEXT by NAME. Missing: dynamic dispatch (virtual/interface/duck-typed), a most-vexing-parse declaration with no call expression, a function-pointer/callback bound to more than one function in scope (reassigned, table-indexed, lambda-bound, or address-taken/reference-bound), and a plain-name binding (fp=handler) whose variable type is not PROVABLY a function pointer (a same-file typedef/declarator; a HEADER typedef is missed; auto/template types are read as unpinned, so KEPT). A macro-generated call site is role="macro" only when its name uniquely names an indexed function-like #define (C-family, t="macro"); a shared name stays a plain call, an unindexed macro is no edge. Read a zero as "none found", never as "none exists". graph_ambiguous=/graph_unresolved= are the whole graph's resolver gauge (calls split over several defs / calls whose in-repo defs were all language-filtered), the map header's ambiguous=/unresolved=. COUNTING UNIT differs by verb: callers, callees, edit-check, graph-query and pr-context counts are DISTINCT SYMBOLS (repeated calls from one caller, and calls to two overloads, collapse into ONE row; multiplicity survives only in the call graph's edge weight). The reach counts (impact's reaches=, pr-context's dependents=) are the size of a transitive reach SET, each symbol counted once. The uses verb counts call SITES, one row per occurrence — a larger count there for the same symbol is these units agreeing, not disagreeing. The map header's edges= is a unit again different — distinct (caller,callee) PAIRS — and that document carries neither this marker nor this clause. -->
<edit-check sym="lessByScoreDescId" t="fn" p="src/infra/sortutil.h:49" status="unchanged" defs="1" callers="4" incompatible="0" at="c7725f3ef+dirty" graph_ambiguous="6085" graph_unresolved="3093" counts_floor="1" root="." next="--test-gate=src/infra/sortutil.h">
<note d="2026-09-05" sha="c7725f3" branch="integration/terminality-2026-09-05">
<![CDATA[chose the flat two-branch compare over the nested ladder because the comparator sits inside the PageRank sort]]>
</note>
<note d="2026-09-05" sha="c7725f3" branch="integration/terminality-2026-09-05">
<![CDATA[keep this branch-free — it sits inside the PageRank sort comparator]]>
</note>
<c n="benchScores" p="bench/bench_radix_ab.cpp:133"/>
<c n="benchScoreCase" p="bench/bench_sort_large.cpp:230"/>
<c n="radixSortByScoreDescId" p="src/infra/sortutil.h:114"/>
<c n="verifyRipwireWrappers" p="test/verify_radix.cpp:249"/>
</edit-check>
`````

## `./build/ripwire . --insert-after-symbol=lessByScoreDescId --edit-payload=<scratch>/aux/payload_note.h`

*Insert immediately AFTER one uniquely-resolved definition; replaced_bytes=0 because the insert verbs never overwrite. The receipt carries the folded post-edit verification (lines=, edit_check, tests_to_run) so the loop closes in one call.*

`````
{"applied":"insert_after_symbol","symbol":"lessByScoreDescId","file":"src/infra/sortutil.h","span":{"start":2375,"end":2463},"lines":{"start":56,"end":58},"replaced_bytes":0,"old_file_bytes":8413,"new_file_bytes":8501,"file_eol":"lf","eol_normalized":false,"trailing_newline_folded":true,"separator_p … [line truncated: 639 more bytes on this line]
"graph_ambiguous":6085,"graph_unresolved":3093,"counts_floor":true},"tests_to_run":[{"p":"test/adaptivecutshapefix/adaptive_cut_shape_test.cpp","run":"bash test/adaptivecutshapecheck.sh"},
{"p":"test/verify_csr.cpp","run":"bash test/a9disclosurecheck.sh"},
{"p":"test/verify_radix.cpp","run":"bash test/greptiercheck.sh"}],
"tests":3,"script_gates_unmodelled":574,"graph_ambiguous":6085,"graph_unresolved":3093,"counts_floor":true,"next":"bash test/adaptivecutshapecheck.sh"}
`````

stderr:

`````
ripwire edit: applied atomically; receipt carries region, blob_sha, edit_check, tests_to_run; next: bash test/adaptivecutshapecheck.sh
`````

## `./build/ripwire . --insert-after-symbol=lessByScoreDescId --edit-payload=<scratch>/aux/payload_note.h --no-post-check`

*The opt-out: the same insert with the folded verification skipped — lines= still rides (it is free), edit_check/tests_to_run do not, and the two pasteable commands stay on stderr.*

`````
{"applied":"insert_after_symbol","symbol":"lessByScoreDescId","file":"src/infra/sortutil.h","span":{"start":2375,"end":2463},"lines":{"start":56,"end":58},"replaced_bytes":0,"old_file_bytes":8501,"new_file_bytes":8589,"file_eol":"lf","eol_normalized":false,"trailing_newline_folded":true,"separator_p … [line truncated: 570 more bytes on this line]
`````

stderr:

`````
ripwire edit: applied atomically; receipt carries region, blob_sha (post-check skipped); next: --edit-check=src/infra/sortutil.h:lessByScoreDescId
`````

## `./build/ripwire . --insert-before-symbol=nonNegativeFloatDescKey --edit-payload=<scratch>/aux/payload_note.h --edit-target-file=src/infra/sortutil.h`

*Insert BEFORE, with --edit-target-file pinning which same-named definition (here unambiguous — the disambiguator is simply honoured).*

`````
{"applied":"insert_before_symbol","symbol":"nonNegativeFloatDescKey","file":"src/infra/sortutil.h","span":{"start":2895,"end":2983},"lines":{"start":74,"end":75},"replaced_bytes":0,"old_file_bytes":8589,"new_file_bytes":8677,"file_eol":"lf","eol_normalized":false,"trailing_newline_folded":false,"sep … [line truncated: 742 more bytes on this line]
{"n":"benchAdaptive","p":"bench/bench_radix_ab.cpp:157","l":[162]},
{"n":"radixSortNonNegativeFloatsDesc","p":"src/infra/sortutil.h:105","l":[114]},
{"n":"radixSortByScoreDescId","p":"src/infra/sortutil.h:120","l":[180]}],
"graph_ambiguous":6085,"graph_unresolved":3093,"counts_floor":true},"tests_to_run":[{"p":"test/adaptivecutshapefix/adaptive_cut_shape_test.cpp","run":"bash test/adaptivecutshapecheck.sh"},
{"p":"test/verify_csr.cpp","run":"bash test/a9disclosurecheck.sh"},
{"p":"test/verify_radix.cpp","run":"bash test/greptiercheck.sh"}],
"tests":3,"script_gates_unmodelled":574,"graph_ambiguous":6085,"graph_unresolved":3093,"counts_floor":true,"next":"--uses=src/infra/sortutil.h:nonNegativeFloatDescKey"}
`````

stderr:

`````
ripwire edit: applied atomically; receipt carries region, blob_sha, edit_check, tests_to_run; next: --uses=src/infra/sortutil.h:nonNegativeFloatDescKey
`````

## `./build/ripwire . --replace-symbol-body=DoesNotExist --edit-payload=<scratch>/aux/payload_note.h`

*An unknown TARGET refuses and leaves every file byte-identical.*

**exit code: 1**

`````
(empty)
`````

stderr:

`````
ripwire: --replace-symbol-body: symbol 'DoesNotExist' not found
`````

## `./build/ripwire . --edit-plan=<scratch>/aux/edit_plan.json --dry-run`

*A versioned multi-edit TRANSACTION preflighted without writing: the receipt shows what each op would read and touch.*

Input file:

`````
{
 "version": 1,
 "edits": [
  {
   "op": "insert_before_symbol",
   "target": "nonNegativeFloatDescKey",
   "payload": "plan_note.h"
  }
 ]
}
`````

`````
{"schema":"ripwire.edit-plan/v1","mode":"dry-run","edits":1,"files":1,"callers_union":4,"graph_ambiguous":6085,"graph_unresolved":3093,"counts_floor":true,"atomic_scope":"per-file","rollback_on_write_error":true,"recheck_before_each_write":true,"multifile_crash_atomic":false,"operations":[{"op":"ins … [line truncated: 418 more bytes on this line]
`````

## `./build/ripwire . --edit-plan=<scratch>/aux/edit_plan.json --apply`

*The same plan committed: per-file locks, re-verify-before-write, atomic rename, rollback on a later failure.*

`````
{"schema":"ripwire.edit-plan/v1","mode":"apply","edits":1,"files":1,"callers_union":4,"graph_ambiguous":6085,"graph_unresolved":3093,"counts_floor":true,"applied":1,"atomic_files":1,"atomic_scope":"per-file","rollback_on_write_error":true,"recheck_before_each_write":true,"multifile_crash_atomic":fal … [line truncated: 591 more bytes on this line]
{"n":"benchAdaptive","p":"bench/bench_radix_ab.cpp:157","l":[162]},
{"n":"radixSortNonNegativeFloatsDesc","p":"src/infra/sortutil.h:107","l":[116]},
{"n":"radixSortByScoreDescId","p":"src/infra/sortutil.h:122","l":[182]}],
"graph_ambiguous":6085,"graph_unresolved":3093,"counts_floor":true}}]}
`````

## `./build/ripwire . --edit-plan=<scratch>/aux/edit_plan.json`

*Neither --dry-run nor --apply: the mode is explicit, so this refuses.*

**exit code: 1**

`````
(empty)
`````

stderr:

`````
ripwire: --edit-plan requires exactly one of --dry-run or --apply
`````

## `./build/ripwire . --quality-delta`

*After the agent's edits: the complexity/nesting rows on lessByScoreDescId are gone (the replace undid them), the rest still gate (exit 2).*

**exit code: 2** — **wall time: 1.96s**

`````
<!-- ripwire quality-delta: only what a change made WORSE against the floor baseline= names below. Descriptive: weigh and fix the real ones, do not game the number (a wrong abstraction beats a low score). TEN KINDS, and kind= on every row names which one: complexity over the ccx bar, verbosity (LOC), nesting, params, duplication, dead-code, api-surface (new public contract drift), error-masking, short-horizon-churn, new-clone-of-reused-helper. THREE independent axes, in this order: (1) acked findings are suppressed entirely (acked= counts them); (2) ORIGIN — a finding on a symbol that EXISTED at the baseline is preexisting-worse (no origin attribute), one that exists only because the code is NEW carries origin="new-symbol"; (3) MATERIALITY — a small numeric delta is sev="minor", and minor= counts them. EXIT 2 fires only on preexisting-worse AND major, the gating= count; new-symbol rows never gate, so exit 0 is NOT a verdict on them — nothing that existed got worse, but the new debt is yours: read them. Clone kinds are new-symbol only when EVERY member is new; short-horizon-churn is preexisting by construction. preexisting-worse= and new-symbol= partition regressions=. stale= is a FOURTH axis, never gating and never counted in regressions=: rows in the .ripwire_quality_acks ledger whose target no longer applies. register-macro-excluded= is a FLOOR, not a finding: symbols this run excluded from the dead-code kind because their own definition is a registered self-registering test/benchmark macro call. Never gates, never counted in regressions=, printed even at zero (zero means none excluded, not that the check did not run). A gating row's next= is the one pasteable follow-up: expand on FILE:NAME, the body to fix (a duplication row names a SET and carries none). bar= on a complexity/verbosity/nesting/params row is the threshold now= is judged against (ccx 15, loc 60, nest 4, params 5). baseline="git-HEAD" means no sidecar existed, so the working tree was auto-compared against the HEAD tree — anything already committed cannot appear. at= is the git commit (plus a dirty marker when the working tree differs) this list was computed at. The registered families are doctest/Catch2 TEST_CASE, GoogleTest TEST/TEST_F/TEST_P, Google Benchmark BENCHMARK, plus any name a .ripwire_config register_macros= line adds; each registers itself through a static initializer the call graph cannot see, so zero in-edges on one is not evidence of anything. IDENTITY across a rename or a move: a finding is keyed path::scope::name, which a rename would destroy, so the baseline and the .ripwire_quality_acks ledger are both re-filed into the CURRENT tree's identity before either is read, by two EXACT mechanisms — git's own rename record, and equality of a whitespace-and-name-scrubbed body hash — never a similarity heuristic. renames= is how many rename pairs were read, rename_window_commits= how deep the commit window went, acked_by_rename= and acked_by_content= how many of the acked= suppressions each mechanism is responsible for. Three appear ONLY when true, so an absent one is not a silent no: renames_window_truncated= (history is deeper than the window), renames_truncated= (the pair cap was hit), renames_ambiguous= (an ancestor two current symbols both claim — refused rather than guessed). ORIGIN reads the re-filed baseline too, so a regression carried in with a rename is judged preexisting-worse and GATES instead of slipping through as new-symbol. FLOORS, stated because silence here would read as a guarantee: the two clone kinds key on a member-SET hash and are NOT re-filed, so a clone ack still dies on a rename; ORIGIN follows the rename record but never content, because the baseline stores no content id at all; and a move git recorded no rename for still reads as new-symbol. The two mechanisms in full, because a suppression is a claim about identity: git's rename record is read with rename detection and the similarity threshold PINNED in the command, never inherited from the repo config, over a fixed COMMIT window rather than a wall-clock one, so the answer is the same everywhere; the content match is equality of a body hash scrubbed of whitespace and of the symbol's own name, for a move git recorded no rename for. A body that CHANGED is a different finding and is matched by neither. Each sa row carries key= (the ack identity as stored) and why=, which is target-gone (the key names no symbol or group any more) or finding-gone (the target survived, this kind just does not fire on it). sym= and p=path:line name WHICH ack it is, and are present exactly when the key still names a live symbol: on every finding-gone row, on none of the target-gone rows (there is nothing left to name), and on neither clone kind — a clone key hashes a member SET that no single symbol carries, so those rows are unnameable by construction rather than guessed at. Hygiene disclosure only — the ledger file is never auto-edited. ROWS: sym= is the canonical id the finding regressed on; was= and now= carry the before/after value for the numeric kinds; p="path:line" is the locator (root-relative; the first-sorting member for the clone kinds; omitted, never faked, when none resolves). churn= and surface= are per-kind classification facets (short-horizon-churn's self/ambient split; api-surface's new-symbol/contract-change tier). Every row the header's gating= counter counts also carries a gating attribute set to 1 — marked positively, never by the ABSENCE of sev or origin. CLONE ROWS name the whole group rather than one symbol: members= is the member list and tokens= its shared normalized-token count (the same per-group pair the clones verb reports). idiom= names a RECOGNIZED BODY SHAPE every member spells, out of a closed set of three (threshold-ladder, switch-name-table, builder-chain). idiom= alone changes nothing; a group that ALSO shares no non-keyword identifier between any two members, sits in pairwise-distinct enclosing contexts, and stays under 80 normalized tokens is an idiom COLLISION rather than a copy, and is reported minor instead of gating. Break any one of those and it gates as before, idiom= and all: two bucketing ladders over the SAME enum are a copy. The shape is read off the body's token stream and not a parse tree, so a macro-assembled body classifies as whatever its raw tokens spell — the name is printed so the call can be overruled by reading. -->
<quality-delta baseline="git-HEAD" regressions="3" minor="0" acked="3" stale="19" preexisting-worse="2" new-symbol="1" gating="2" register-macro-excluded="3" at="c7725f3ef+dirty" renames="55" rename_window_commits="400" acked_by_rename="0" acked_by_content="0" renames_window_truncated="1">
<r kind="duplication" members="src/infra/sortutil.h::rw::sortutil::nonNegativeFloatAscKeyCopy | src/infra/sortutil.h::rw::sortutil::nonNegativeFloatDescKey" tokens="59" p="src/infra/sortutil.h:88" gating="1"/>
<r kind="new-clone-of-reused-helper" sym="src/infra/sortutil.h::rw::sortutil::nonNegativeFloatAscKeyCopy | src/infra/sortutil.h::rw::sortutil::nonNegativeFloatDescKey" was="0" now="4" p="src/infra/sortutil.h:88" gating="1" next="--expand=src/infra/sortutil.h:nonNegativeFloatDescKey"/>
<r kind="params" sym="src/infra/sortutil.h::rw::sortutil::sortScoredIdsWithOptions" was="0" now="8" bar="5" origin="new-symbol" p="src/infra/sortutil.h:98"/>
<sa kind="api-surface" key="298e798c7f075715" why="target-gone"/>
<sa kind="api-surface" key="5a07390012b46e06" why="target-gone"/>
<sa kind="api-surface:new-symbol" key="1926b0d9e94541a0" why="target-gone"/>
<sa kind="api-surface:new-symbol" key="79625906f9f71ad0" why="target-gone"/>
<sa kind="api-surface:new-symbol" key="995375dfa4e63104" why="target-gone"/>
<sa kind="complexity" key="4b309450f25c2b44" why="finding-gone" sym="src/ingest.cpp::rw::ingest" p="src/ingest.cpp:191"/>
<sa kind="complexity" key="53a1214d5505fa41" why="finding-gone" sym="main" p="src/main.cpp:2634"/>
<sa kind="duplication" key="160ac41979d9ebaf" why="finding-gone"/>
<sa kind="duplication" key="af2e342eda9648ed" why="finding-gone"/>
<sa kind="duplication" key="c8b32435256b863e" why="finding-gone"/>
<sa kind="nesting" key="1bded1f8f88d3b85" why="finding-gone" sym="src/slice.h::slicev::sliceFlowCompute" p="src/slice.h:2286"/>
<sa kind="nesting" key="3c07d993bfdbce53" why="finding-gone" sym="src/slice.h::slicev::sliceBundleText" p="src/slice.h:2685"/>
<sa kind="new-clone-of-reused-helper" key="0e9742973611fd71" why="finding-gone"/>
<sa kind="new-clone-of-reused-helper" key="5a0ff811529d5c95" why="finding-gone"/>
<sa kind="new-clone-of-reused-helper" key="c8b32435256b863e" why="finding-gone"/>
<sa kind="new-clone-of-reused-helper" key="d11c67611bc73d49" why="finding-gone"/>
<sa kind="params" key="f6dedd851e4b2a25" why="finding-gone" sym="src/slice.h::slicev::sliceWalk" p="src/slice.h:1122"/>
<sa kind="verbosity" key="15061a69cb5b451f" why="finding-gone" sym="src/packtask.h::rw::packTaskHeaderText" p="src/packtask.h:226"/>
<sa kind="verbosity" key="53a1214d5505fa41" why="finding-gone" sym="main" p="src/main.cpp:2634"/>
</quality-delta>
`````

stderr:

`````
ripwire: no ./.ripwire_quality_baseline — auto-comparing the working tree vs git HEAD (commit the baseline with --quality-baseline to pin it)
ripwire: --quality-delta gating: 2 preexisting-worse major finding(s); first: duplication src/infra/sortutil.h::rw::sortutil::nonNegativeFloatAscKeyCopy | src/infra/sortutil.h::rw::sortutil::nonNegativeFloatDescKey at src/infra/sortutil.h:88 (was=0 now=59)
`````

## `./build/ripwire . --quality-baseline`

*REFUSES, exit 1: this sandbox tree is already regressed, and pinning here would swallow that debt into the floor so every later delta read clean. It names how many gating findings it would absorb, the first of them, and the way forward.*

**exit code: 1** — **wall time: 1.18s**

`````
(empty)
`````

stderr:

`````
ripwire: --quality-baseline: this tree already holds 2 gating finding(s) against HEAD — pinning here would absorb
  them into the floor, and every later --quality-delta would read clean. First: duplication src/infra/sortutil.h::rw::sortutil::nonNegativeFloatAscKeyCopy | src/infra/sortutil.h::rw::sortutil::nonNegativeFloatDescKey (was=0 now=59)
  Commit the tree first, or pass --allow-dirty to pin anyway (the sidecar then records the 2 absorbed, and every
  report against it carries baseline_absorbed="2").
`````

## `./build/ripwire . --quality-baseline --allow-dirty`

*The consent form: pin anyway. The sidecar is stamped with the dirty pin and the absorbed count, so the fact outlives the process that knew it.*

**wall time: 1.82s**

`````
(empty)
`````

stderr:

`````
ripwire: --quality-baseline --allow-dirty: pinned with 2 gating finding(s) ABSORBED into the floor (stamped in the sidecar; every --quality-delta against it carries baseline_absorbed="2")
ripwire: wrote ./.ripwire_quality_baseline (snapshot of 13343 per-symbol rows, 13851 indexed symbols total)
`````

Artifact written:

`````
 2269144 .ripwire_quality_baseline
# ripwire quality baseline v4 — regenerate with --quality-baseline; do not hand-edit
head c7725f3ef85892534460f952e35816caad67dac2
dirty 1
absorbed 2
ccx d19d7c13cbc7 1
ccx 1f7edbff929e5 29
ccx 94c5dbe9ae9a6 21
ccx cac92a0451eb9 0
ccx 156cfc56beb697 0
ccx 1599ac5c991b5e 0
ccx 18a6d4f69c62a7 15
ccx
`````

## `./build/ripwire . --quality-delta`

*Against that sidecar the same tree reads regressions=0 — but baseline_absorbed= is on the root, so this green means clean SINCE THE PIN, never clean. A baseline is a floor YOU chose, and it belongs BEFORE the change.*

**wall time: 1.83s**

`````
<!-- ripwire quality-delta: only what a change made WORSE against the floor baseline= names below. Descriptive: weigh and fix the real ones, do not game the number (a wrong abstraction beats a low score). TEN KINDS, and kind= on every row names which one: complexity over the ccx bar, verbosity (LOC), nesting, params, duplication, dead-code, api-surface (new public contract drift), error-masking, short-horizon-churn, new-clone-of-reused-helper. THREE independent axes, in this order: (1) acked findings are suppressed entirely (acked= counts them); (2) ORIGIN — a finding on a symbol that EXISTED at the baseline is preexisting-worse (no origin attribute), one that exists only because the code is NEW carries origin="new-symbol"; (3) MATERIALITY — a small numeric delta is sev="minor", and minor= counts them. EXIT 2 fires only on preexisting-worse AND major, the gating= count; new-symbol rows never gate, so exit 0 is NOT a verdict on them — nothing that existed got worse, but the new debt is yours: read them. Clone kinds are new-symbol only when EVERY member is new; short-horizon-churn is preexisting by construction. preexisting-worse= and new-symbol= partition regressions=. stale= is a FOURTH axis, never gating and never counted in regressions=: rows in the .ripwire_quality_acks ledger whose target no longer applies. register-macro-excluded= is a FLOOR, not a finding: symbols this run excluded from the dead-code kind because their own definition is a registered self-registering test/benchmark macro call. Never gates, never counted in regressions=, printed even at zero (zero means none excluded, not that the check did not run). A gating row's next= is the one pasteable follow-up: expand on FILE:NAME, the body to fix (a duplication row names a SET and carries none). bar= on a complexity/verbosity/nesting/params row is the threshold now= is judged against (ccx 15, loc 60, nest 4, params 5). baseline="sidecar" is the pinned .ripwire_quality_baseline snapshot, honored because it was pinned at the CURRENT git HEAD: the one floor YOU chose. baseline_absorbed="N" means that sidecar was pinned with the allow-dirty flag on a tree that ALREADY held N gating finding(s) against HEAD, and those N are inside the floor: a green exit beside this attribute reads "clean since the pin", never "clean". Re-pin on a committed tree to clear it. at= is the git commit (plus a dirty marker when the working tree differs) this list was computed at. The registered families are doctest/Catch2 TEST_CASE, GoogleTest TEST/TEST_F/TEST_P, Google Benchmark BENCHMARK, plus any name a .ripwire_config register_macros= line adds; each registers itself through a static initializer the call graph cannot see, so zero in-edges on one is not evidence of anything. IDENTITY across a rename or a move: a finding is keyed path::scope::name, which a rename would destroy, so the baseline and the .ripwire_quality_acks ledger are both re-filed into the CURRENT tree's identity before either is read, by two EXACT mechanisms — git's own rename record, and equality of a whitespace-and-name-scrubbed body hash — never a similarity heuristic. renames= is how many rename pairs were read, rename_window_commits= how deep the commit window went, acked_by_rename= and acked_by_content= how many of the acked= suppressions each mechanism is responsible for. Three appear ONLY when true, so an absent one is not a silent no: renames_window_truncated= (history is deeper than the window), renames_truncated= (the pair cap was hit), renames_ambiguous= (an ancestor two current symbols both claim — refused rather than guessed). ORIGIN reads the re-filed baseline too, so a regression carried in with a rename is judged preexisting-worse and GATES instead of slipping through as new-symbol. FLOORS, stated because silence here would read as a guarantee: the two clone kinds key on a member-SET hash and are NOT re-filed, so a clone ack still dies on a rename; ORIGIN follows the rename record but never content, because the baseline stores no content id at all; and a move git recorded no rename for still reads as new-symbol. Each sa row carries key= (the ack identity as stored) and why=, which is target-gone (the key names no symbol or group any more) or finding-gone (the target survived, this kind just does not fire on it). sym= and p=path:line name WHICH ack it is, and are present exactly when the key still names a live symbol: on every finding-gone row, on none of the target-gone rows (there is nothing left to name), and on neither clone kind — a clone key hashes a member SET that no single symbol carries, so those rows are unnameable by construction rather than guessed at. Hygiene disclosure only — the ledger file is never auto-edited. -->
<quality-delta baseline="sidecar" regressions="0" minor="0" acked="0" stale="19" preexisting-worse="0" new-symbol="0" gating="0" register-macro-excluded="3" at="c7725f3ef+dirty" renames="55" rename_window_commits="400" acked_by_rename="0" acked_by_content="0" renames_window_truncated="1" baseline_ab … [line truncated: 11 more bytes on this line]
<sa kind="api-surface" key="298e798c7f075715" why="target-gone"/>
<sa kind="api-surface" key="5a07390012b46e06" why="target-gone"/>
<sa kind="api-surface:new-symbol" key="1926b0d9e94541a0" why="target-gone"/>
<sa kind="api-surface:new-symbol" key="79625906f9f71ad0" why="target-gone"/>
<sa kind="api-surface:new-symbol" key="995375dfa4e63104" why="target-gone"/>
<sa kind="complexity" key="4b309450f25c2b44" why="finding-gone" sym="src/ingest.cpp::rw::ingest" p="src/ingest.cpp:191"/>
<sa kind="complexity" key="53a1214d5505fa41" why="finding-gone" sym="main" p="src/main.cpp:2634"/>
<sa kind="duplication" key="160ac41979d9ebaf" why="finding-gone"/>
<sa kind="duplication" key="af2e342eda9648ed" why="finding-gone"/>
<sa kind="duplication" key="c8b32435256b863e" why="finding-gone"/>
<sa kind="nesting" key="1bded1f8f88d3b85" why="finding-gone" sym="src/slice.h::slicev::sliceFlowCompute" p="src/slice.h:2286"/>
<sa kind="nesting" key="3c07d993bfdbce53" why="finding-gone" sym="src/slice.h::slicev::sliceBundleText" p="src/slice.h:2685"/>
<sa kind="new-clone-of-reused-helper" key="0e9742973611fd71" why="finding-gone"/>
<sa kind="new-clone-of-reused-helper" key="5a0ff811529d5c95" why="finding-gone"/>
<sa kind="new-clone-of-reused-helper" key="c8b32435256b863e" why="finding-gone"/>
<sa kind="new-clone-of-reused-helper" key="d11c67611bc73d49" why="finding-gone"/>
<sa kind="params" key="f6dedd851e4b2a25" why="finding-gone" sym="src/slice.h::slicev::sliceWalk" p="src/slice.h:1122"/>
<sa kind="verbosity" key="15061a69cb5b451f" why="finding-gone" sym="src/packtask.h::rw::packTaskHeaderText" p="src/packtask.h:226"/>
<sa kind="verbosity" key="53a1214d5505fa41" why="finding-gone" sym="main" p="src/main.cpp:2634"/>
</quality-delta>
`````


---

# the MCP dialect — the same verbs over stdio JSON-RPC (one-shot exchange, not a persistent server)

## `printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize"}' '{"jsonrpc":"2.0","id":2,"method":"tools/list"}' | ./build/ripwire --mcp`

*initialize + tools/list: the manifest an agent host loads at session start — every verb's name, description and input schema.*

`````
{"jsonrpc":"2.0","id":1,"result":{"protocolVersion":"2025-11-25","serverInfo":{"name":"ripwire","version":"1.0"},"capabilities":{"tools":{}},"instructions":"Map before reading files. Start a new task with explore; use from_trace for an error; use impact plus uses before changing a symbol; run edit_c … [line truncated: 249 more bytes on this line]
{"jsonrpc":"2.0","id":2,"result":{"tools":[{"name":"analyze","description":"Architecture map for a directory: signatures and the call graph for the top symbols. Use when landing cold in a repo or subdir, before reading files; for a task-scoped inventory use 'for', for one symbol's neighborhood find_ … [line truncated: 729 more bytes on this line]
{"name":"find_symbol","description":"A symbol's 1-hop neighborhood: the symbol (with a fetch_body handle) plus direct callers (calledBy) and callees (calls). Full transitive reach: 'impact'. Read/write/import sites, not just calls: 'uses'. JSON {symbol, calledBy, calls, defs, count, hop_tested, hop_ … [line truncated: 1095 more bytes on this line]
{"name":"find_referencing_symbols","description":"Direct (1-hop) callers of a symbol, each with a fetch_body handle. For the full transitive blast radius use 'impact', for read/write/import sites 'uses'. JSON {symbol, calledBy, defs, count, hop_tested, hop_untested, counts_floor}; calledBy is a FLOO … [line truncated: 797 more bytes on this line]
{"name":"grep","description":"Trigram literal search; each hit annotated with its enclosing symbol (which function/class it is in). pattern = the literal; in=any lifts the span tiering (by default the tightest non-empty tier is served and what was held back rides as suppressed_comment/suppressed_str … [line truncated: 827 more bytes on this line]
{"name":"cochange","description":"Files that historically change together with this file — the co-edit partners. dep_capable=false means neither side could carry one (sh/md/json/binary), so surprising is undefined rather than informative. file = the file (a path SUFFIX is enough); limit/offset pag … [line truncated: 655 more bytes on this line]
{"name":"memory_recall","description":"Most relevant memory notes / docs for a task, full text — the few that matter, not the whole corpus. path = docs/memory dir; task = what you're working on; top_k = docs to return, 1..1000 (default 8), refused outside that band, never clamped; budget_tokens =  … [line truncated: 790 more bytes on this line]
{"name":"situational_awareness","description":"The 5 things to know about a diff, as JSON: blast_radius, tests_to_run, forgotten (usual co-change partners missing from this diff), hotspot_alert, modules_touched. diff/files optional — defaults to 'git diff HEAD'. files is a STRING of comma-separate … [line truncated: 685 more bytes on this line]
{"name":"mentions","description":"Docs (markdown plans/designs) that name a code symbol in a backtick. symbol = the code symbol name; limit/offset page the files. An @FILE:LINE line-seed rebinds to the innermost definition enclosing that line and answers for it, disclosing the rebound name as 'sym'  … [line truncated: 625 more bytes on this line]
{"name":"for","description":"Task-lens ranked, signatures-only inventory of the building blocks most relevant to a task (cx=complexity, in=reuse-count). task = the task in plain words; budget_tokens = an optional ceiling (the CLI --for --token-budget). The header carries route= (which ranker answere … [line truncated: 674 more bytes on this line]
{"name":"lego","description":"Interface-to-impls view for ONE named interface/base: its method contract plus EVERY implementor (own-language only), each with file path. Use when implementing against a KNOWN interface (contrast 'for', which sprays top interfaces for a task). type = interface/base nam … [line truncated: 630 more bytes on this line]
{"name":"owners","description":"Bus-factor: recency-weighted (6-month half-life) author ownership per file. symbol = optional, restricts to the file that defines it; limit/offset page the rows. at= is the commit these numbers were computed at (+dirty = the working tree differed). An @FILE:LINE line- … [line truncated: 866 more bytes on this line]
{"name":"replace_symbol_body","description":"Replace a symbol's ENTIRE definition (signature through closing brace) with new_body — splices over the full def span, preserving every byte outside it verbatim; new_body must be a complete, well-formed definition. One trailing newline folds (trailing_n … [line truncated: 1323 more bytes on this line]
{"name":"insert_before_symbol","description":"Insert text immediately BEFORE a symbol's definition (its first byte); padded to the file's own blank-line seam (separator_padded=N). Same refusal contract as replace_symbol_body (not found / ambiguous / stale index / symlink / concurrent write, file unc … [line truncated: 877 more bytes on this line]
{"name":"insert_after_symbol","description":"Insert text immediately AFTER a symbol's definition (past its final byte, which is preserved exactly); padded to the file's own blank-line seam (separator_padded=N); one trailing newline folds (trailing_newline_folded). Same refusal contract as replace_sy … [line truncated: 878 more bytes on this line]
{"name":"fetch_body","description":"Full (or partial-range) source of a symbol's definition, addressed by the stable `handle` a read verb attached to it (bodies on request, not by default). start_line/end_line are optional, 1-based, INCLUSIVE and BODY-RELATIVE (line 1 = the def's first line), clampe … [line truncated: 1049 more bytes on this line]
{"name":"exemplar","description":"BEFORE writing a function / method / class / struct / interface / variable, get the repo's single best-in-class instance of that kind to imitate — signature AND full body. chosen by ROLE, NEVER by text similarity to your task: candidates are first filtered to cogn … [line truncated: 1188 more bytes on this line]
"anyOf":[{"required":["kind"]},
{"required":["task"]}]},"annotations":{"readOnlyHint":true,"destructiveHint":false,"openWorldHint":false}},
{"name":"quality_delta","description":"Your PR self-check, run every time you think a change is DONE — pairs with the CLI-only --test-gate (names the tests to run + the untested blast radius; not MCP-exposed) to form the two-step pre-PR gate. Reports ONLY what your working tree made WORSE vs basel … [line truncated: 797 more bytes on this line]
{"name":"quality_baseline","description":"PIN the quality floor: writes .ripwire_quality_baseline stamped with the current git HEAD sha, snapshotting complexity / duplication / dead-code / API surface. Call once at the start of non-trivial work, then quality_delta compares against this pinned floor  … [line truncated: 459 more bytes on this line]
{"name":"impact","description":"IS IT SAFE TO CHANGE X? — the TRANSITIVE blast radius of a symbol via calls, ranked by PageRank. Use before modifying or deleting a symbol; it beats find_referencing_symbols (direct callers only), and 'uses' catches the read/write/import sites calls miss. Call edges … [line truncated: 1279 more bytes on this line]
{"name":"uses","description":"The STATICALLY RESOLVABLE use-sites of a symbol, not just calls: role (call | read | write | import | extends), file:line, and enclosing symbol. Use to see the footprint before renaming or changing a name — find_referencing_symbols and impact follow only calls. extern … [line truncated: 1119 more bytes on this line]
{"name":"path_between","description":"Does A REACH B, and HOW? — the shortest directed CALL path between two symbols, hop-by-hop. reachable=\"0\" hops=\"0\" is a valid 'not reachable' answer — call edges are name-based, so a missing dynamic/callback edge can hide a real path. Named path_between  … [line truncated: 682 more bytes on this line]
{"name":"connect","description":"When a task touches 2..16 named symbols, returns the minimal subgraph RELATING them - terminals, the fewest joining intermediaries (with signatures), and call edges in true direction - finding the shared-caller joins a directed path_between cannot; unrelated symbols  … [line truncated: 923 more bytes on this line]
{"name":"explore","description":"ONE-call task orientation: the routed+anchored ranking, full bodies of the top hits, their 1-hop callers, field notes, and tests_to_run — ALL under one deterministic byte budget, in a fixed section order (ranking > bodies > callers > notes > tests) that degrades gr … [line truncated: 1473 more bytes on this line]
{"name":"from_trace","description":"Paste a stack trace / sanitizer report / compiler error and get it mapped onto indexed symbols, ranked INNERMOST-first: the parsed <trace> frame map, the ranked suspects' signatures, and the innermost in-corpus symbol's FULL body. Out-of-corpus frames are listed a … [line truncated: 1199 more bytes on this line]
{"name":"edit_check","description":"Just edited a symbol? Did its CONTRACT (param count + publicness) change vs git HEAD, and which 1-hop callers are NOW INCOMPATIBLE with the new arity by fixed-arity evidence (not a guess — every folded definition disagrees)? This is call sites worth OPENING, not … [line truncated: 1647 more bytes on this line]
{"name":"whereis","description":"WHERE DOES THIS CONTENT LIVE? Which branch's tree defines or mentions a symbol, HEAD first, with on-head=0 naming the case this verb exists for: content that lives only on a branch (a finished fix stranded on 1 of 30 refs). Each distinct blob is read once (content-ad … [line truncated: 1177 more bytes on this line]
{"name":"stray_content","description":"Per branch: the lines its own divergent work AUTHORED (vs its merge-base with HEAD) that the live line does NOT have. Four verdicts (unmerged+superseded+merged+unknown=refs): v=unmerged is genuinely absent; v=superseded means the live line re-implemented the wo … [line truncated: 1110 more bytes on this line]
{"name":"flags","description":"WHAT IS BUILT BUT DARK here — the answer to 'why don't I see feature X?'. Harvests all three gate patterns (ifndef/define header gates, CMake option(), getenv reads) with each gate's kind, DEFAULT, the size of the code it guards, and its read sites. When a name is bo … [line truncated: 1092 more bytes on this line]
{"name":"doc_drift","description":"WHICH OF THIS REPO'S DOC CLAIMS ARE NOW FALSE. Verifies the CHECKABLE anchors in every markdown file against the live index and returns ONLY the ones that no longer hold: file:line refs (missing-file / past-eof / line-moved), backticked symbol mentions (undefined), … [line truncated: 1154 more bytes on this line]
{"name":"slice","description":"WHERE IS THIS VARIABLE DEFINED AND USED inside one function — NAME-BASED intra-procedural def-use rows of one variable inside ONE uniquely-resolved definition (the ARISE slicer, arXiv:2605.03117). symbol alone lists the sliceable locals to pick from; add var (or spel … [line truncated: 1695 more bytes on this line]
{"name":"batch","description":"ONE-TURN CONTEXT SWEEP: answer up to 16 heterogeneous READ sub-queries in a single call (the deterministic $0 counterpart of a parallel-search agent). queries = array over the SAME path, in EITHER grammar: {verb, ...args} objects, or the CLI --batch file's own \"verb:a … [line truncated: 1968 more bytes on this line]
`````

The manifest, summarised (name / description bytes / required args) — what the host pays in context every session:

`````
tools= 31  manifest_bytes= 41020  (~tokens at 4 bytes/token: 10255 )
batch                        desc_bytes= 1190 schema_bytes=  935 required=['queries']
slice                        desc_bytes=  953 schema_bytes=  905 required=['symbol']
edit_check                   desc_bytes= 1130 schema_bytes=  678 required=['symbol']
explore                      desc_bytes= 1016 schema_bytes=  620 required=['task']
replace_symbol_body          desc_bytes=  865 schema_bytes=  610 required=['symbol', 'new_body']
exemplar                     desc_bytes=  954 schema_bytes=  536 required=[]
impact                       desc_bytes=  802 schema_bytes=  639 required=['symbol']
from_trace                   desc_bytes=  829 schema_bytes=  532 required=['trace']
whereis                      desc_bytes=  655 schema_bytes=  687 required=['symbol']
doc_drift                    desc_bytes=  728 schema_bytes=  591 required=[]
uses                         desc_bytes=  626 schema_bytes=  655 required=['symbol']
stray_content                desc_bytes=  678 schema_bytes=  591 required=[]
find_symbol                  desc_bytes=  666 schema_bytes=  590 required=['symbol']
flags                        desc_bytes=  736 schema_bytes=  523 required=[]
fetch_body                   desc_bytes=  623 schema_bytes=  588 required=['handle']
connect                      desc_bytes=  535 schema_bytes=  553 required=['symbols']
insert_after_symbol          desc_bytes=  458 schema_bytes=  577 required=['symbol', 'text']
insert_before_symbol         desc_bytes=  455 schema_bytes=  578 required=['symbol', 'text']
owners                       desc_bytes=  425 schema_bytes=  612 required=[]
grep                         desc_bytes=  435 schema_bytes=  562 required=['pattern']
find_referencing_symbols     desc_bytes=  357 schema_bytes=  590 required=['symbol']
memory_recall                desc_bytes=  447 schema_bytes=  500 required=['task']
quality_delta                desc_bytes=  749 schema_bytes=  207 required=[]
path_between                 desc_bytes=  357 schema_bytes=  479 required=['from', 'to']
situational_awareness        desc_bytes=  423 schema_bytes=  411 required=[]
analyze                      desc_bytes=  546 schema_bytes=  305 required=[]
for                          desc_bytes=  445 schema_bytes=  398 required=['task']
cochange                     desc_bytes=  343 schema_bytes=  476 required=['file']
mentions                     desc_bytes=  305 schema_bytes=  486 required=['symbol']
lego                         desc_bytes=  360 schema_bytes=  440 required=['type']
quality_baseline             desc_bytes=  407 schema_bytes=  207 required=[]
`````

## `printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize"}' '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"for","arguments":{"path":".","task":"pagerank power iteration"}}}' | ./build/ripwire --mcp`

*MCP `for`: always bundle=sigs (never the CLI's compact route), the same ranked signatures as --for.*

`````
{"jsonrpc":"2.0","id":1,"result":{"protocolVersion":"2025-11-25","serverInfo":{"name":"ripwire","version":"1.0"},"capabilities":{"tools":{}},"instructions":"Map before reading files. Start a new task with explore; use from_trace for an error; use impact plus uses before changing a symbol; run edit_c … [line truncated: 249 more bytes on this line]
{"jsonrpc":"2.0","id":2,"result":{"content":[{"type":"text","text":"<ctx task=\"pagerank power iteration\" route=\"routed: subtoken+body BM25 (--for&apos;s default) — no strong name hit, multi-word conceptual query\" root=\".\" confidence=\"low\" margin_pct=\"0\" at=\"c7725f3ef\" doc_mentions=\"4\ … [line truncated: 9129 more bytes on this line]
"_index":"[index: files=1588 symbols=13849 hash=575f5b17]","_fresh":"ok"}}
`````

## `printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize"}' '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"explore","arguments":{"path":".","task":"add a new output format flag to the CLI","budget_tokens":2000}}}' | ./build/ripwire --mcp`

*MCP `explore` = --pack-task under a token budget, one call.*

`````
{"jsonrpc":"2.0","id":1,"result":{"protocolVersion":"2025-11-25","serverInfo":{"name":"ripwire","version":"1.0"},"capabilities":{"tools":{}},"instructions":"Map before reading files. Start a new task with explore; use from_trace for an error; use impact plus uses before changing a symbol; run edit_c … [line truncated: 249 more bytes on this line]
{"jsonrpc":"2.0","id":2,"result":{"content":[{"type":"text","text":"<ctx schema=\"ripwire.pack-task/v1\" task=\"add a new output format flag to the CLI\" route=\"routed: subtoken+body BM25 (--for&apos;s default) — no strong name hit, multi-word conceptual query\" root=\".\" dropped_positive=\"2\"  … [line truncated: 2956 more bytes on this line]
"_index":"[index: files=1588 symbols=13849 hash=575f5b17]","_fresh":"ok"}}
`````

## `printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize"}' '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"fetch_body","arguments":{"path":".","handle":"rankGraphTeleport"}}}' | ./build/ripwire --mcp`

*MCP `fetch_body`: the lazy-body handle posture — bodies only after ranked retrieval, by bare name here.*

`````
{"jsonrpc":"2.0","id":1,"result":{"protocolVersion":"2025-11-25","serverInfo":{"name":"ripwire","version":"1.0"},"capabilities":{"tools":{}},"instructions":"Map before reading files. Start a new task with explore; use from_trace for an error; use impact plus uses before changing a symbol; run edit_c … [line truncated: 249 more bytes on this line]
{"jsonrpc":"2.0","id":2,"result":{"content":[{"type":"text","text":"{\"resolved_from_name\":\"rankGraphTeleport\",\"handle\":\"sym#cfb3dc25a9d1fa2c@450dcd925d95850d\",\"name\":\"rankGraphTeleport\",\"kind\":\"fn\",\"file\":\"src/graph.h\",\"line\":2501,\"start_line\":1,\"end_line\":29,\"total_lines\ … [line truncated: 1329 more bytes on this line]
"_index":"[index: files=1588 symbols=13849 hash=575f5b17]","_fresh":"ok"}}
`````

## `printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize"}' '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"grep","arguments":{"path":".","pattern":"DEGRADED_PATH_ALERT","limit":3}}}' | ./build/ripwire --mcp`

*MCP `grep` with paging args.*

`````
{"jsonrpc":"2.0","id":1,"result":{"protocolVersion":"2025-11-25","serverInfo":{"name":"ripwire","version":"1.0"},"capabilities":{"tools":{}},"instructions":"Map before reading files. Start a new task with explore; use from_trace for an error; use impact plus uses before changing a symbol; run edit_c … [line truncated: 249 more bytes on this line]
{"jsonrpc":"2.0","id":2,"result":{"content":[{"type":"text","text":"{\"pattern\":\"DEGRADED_PATH_ALERT\",\"root\":\".\",\"files\":66,\"shown\":3,\"capped\":true,\"total\":231,\"has_more\":true,\"next_offset\":3,\"offset\":0,\"limit\":3,\"hits_capped\":false,\"next\":\"--grep=DEGRADED_PATH_ALERT --of … [line truncated: 406 more bytes on this line]
{\"file\":\"src/arch.h\",\"line\":353,\"in\":\"rw::parseArchRules\"},
{\"file\":\"src/arch.h\",\"line\":408,\"in\":\"rw::parseArchRules\"}],\"parse_degraded_note\":\"a hit carrying parse_degraded:true sits in a file whose parse holds ERROR/MISSING nodes (the skipped verb itemizes err=/err_ratio=): symbols there may be unextracted, so read an absent in on such a hit as … [line truncated: 319 more bytes on this line]
{\"file\":\"CMakeLists.txt\",\"line\":285},
{\"file\":\"CMakeLists.txt\",\"line\":655}]},\"enclosing\":[{\"n\":\"abicheck::collectAuthoredSites\",\"callers\":1,\"cx\":9},
{\"n\":\"rw::parseArchRules\",\"callers\":1,\"cx\":30}]}"}],
"_index":"[index: files=1588 symbols=13849 hash=575f5b17]","_fresh":"ok"}}
`````

## `printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize"}' '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"slice","arguments":{"path":".","symbol":"rankGraphTeleport","var":"teleport","flow":"back","depth":3}}}' | ./build/ripwire --mcp`

*MCP `slice` — the CLI's --slice/--slice-flow/--slice-depth as one verb.*

`````
{"jsonrpc":"2.0","id":1,"result":{"protocolVersion":"2025-11-25","serverInfo":{"name":"ripwire","version":"1.0"},"capabilities":{"tools":{}},"instructions":"Map before reading files. Start a new task with explore; use from_trace for an error; use impact plus uses before changing a symbol; run edit_c … [line truncated: 249 more bytes on this line]
{"jsonrpc":"2.0","id":2,"result":{"content":[{"type":"text","text":"<!-- ripwire slice ripwire.slice/v1: name-based def-use rows of one variable in one definition: <s l= k=def|use|both|scope t= [b= pp= rd=]> (rd= reaching-def lines per reach=cfg|linear), <v n= l= t=> inventory; steps=/depth= flow. a … [line truncated: 1279 more bytes on this line]
"_index":"[index: files=1588 symbols=13849 hash=575f5b17]","_fresh":"ok"}}
`````

## `printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize"}' '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"find_symbol","arguments":{"path":".","symbol":"DoesNotExist"}}}' | ./build/ripwire --mcp`

*MCP error shape: an unknown symbol comes back as a JSON-RPC error/refusal, not an empty success.*

`````
{"jsonrpc":"2.0","id":1,"result":{"protocolVersion":"2025-11-25","serverInfo":{"name":"ripwire","version":"1.0"},"capabilities":{"tools":{}},"instructions":"Map before reading files. Start a new task with explore; use from_trace for an error; use impact plus uses before changing a symbol; run edit_c … [line truncated: 249 more bytes on this line]
{"jsonrpc":"2.0","id":2,"error":{"code":-32602,"message":"symbol not found: 'DoesNotExist' — pass the final name segment; add scope to disambiguate — or @FILE:LINE when you hold a location"}}
`````

## `printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize"}' '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"batch","arguments":{"path":".","queries":[{"verb":"for","task":"incremental cache invalidation"},{"verb":"find_referencing_symbols","symbol":"rankGraphTeleport"},{"verb":"grep","pattern":"DEGRADED_PATH_ALERT","limit":2}]}}}' | ./build/ripwire --mcp`

*MCP `batch`: three independent read queries answered in ONE round-trip — NOTE the sub-query grammar is {verb, ...args} objects with MCP verb names, not the CLI --batch file's verb:arg lines.*

`````
{"jsonrpc":"2.0","id":1,"result":{"protocolVersion":"2025-11-25","serverInfo":{"name":"ripwire","version":"1.0"},"capabilities":{"tools":{}},"instructions":"Map before reading files. Start a new task with explore; use from_trace for an error; use impact plus uses before changing a symbol; run edit_c … [line truncated: 249 more bytes on this line]
{"jsonrpc":"2.0","id":2,"result":{"content":[{"type":"text","text":"<batch schema=\"ripwire.batch/v1\" n=\"3\" requested=\"3\" cap=\"16\"><!-- ripwire batch ripwire.batch/v1: n= read sub-queries in one sweep (requested=, cap=): each <q> wraps one sub-answer verbatim in CDATA. --><q i=\"0\" verb=\"fo … [line truncated: 9787 more bytes on this line]
{\"name\":\"rankGraph\",\"kind\":\"fn\",\"file\":\"src/graph.h\",\"line\":2542,\"handle\":\"sym#b90da690b120eeb3@450dcd925d95850d\"},
{\"name\":\"anchoredLexicalRank\",\"kind\":\"fn\",\"file\":\"src/graph.h\",\"line\":3034,\"handle\":\"sym#b3a5ca7873636567@450dcd925d95850d\"},
{\"name\":\"churnRankedGraph\",\"kind\":\"fn\",\"file\":\"src/main.cpp\",\"line\":983,\"handle\":\"sym#4b5b63d3932ca0ff@7cb2a63217ad3292\"},
{\"name\":\"runDefaultMap\",\"kind\":\"fn\",\"file\":\"src/main.cpp\",\"line\":1098,\"handle\":\"sym#6e2725cb96590ec8@7cb2a63217ad3292\"},
{\"name\":\"getIndex\",\"kind\":\"fn\",\"file\":\"src/mcpindex.h\",\"line\":1104,\"handle\":\"sym#a6a2eb0bcd3b1383@55fd5e605f32a628\"}],\"graph_ambiguous\":6085,\"graph_unresolved\":3093,\"counts_floor\":true}]]></q><q i=\"2\" verb=\"grep\" ok=\"1\"><![CDATA[{\"pattern\":\"DEGRADED_PATH_ALERT\",\"ro … [line truncated: 597 more bytes on this line]
{\"file\":\"src/arch.h\",\"line\":353,\"in\":\"rw::parseArchRules\"}],\"parse_degraded_note\":\"a hit carrying parse_degraded:true sits in a file whose parse holds ERROR/MISSING nodes (the skipped verb itemizes err=/err_ratio=): symbols there may be unextracted, so read an absent in on such a hit as … [line truncated: 319 more bytes on this line]
{\"file\":\"CMakeLists.txt\",\"line\":285}]},\"enclosing\":[{\"n\":\"abicheck::collectAuthoredSites\",\"callers\":1,\"cx\":9},
{\"n\":\"rw::parseArchRules\",\"callers\":1,\"cx\":30}]}]]></q></batch>"}],
"_index":"[index: files=1588 symbols=13849 hash=575f5b17]","_fresh":"ok"}}
`````

## `printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize"}' '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"batch","arguments":{"path":".","queries":["for:incremental cache invalidation","callers:rankGraphTeleport"]}}}' | ./build/ripwire --mcp`

*The CLI --batch spelling handed to MCP `batch`: refused, with the accepted shape named.*

`````
{"jsonrpc":"2.0","id":1,"result":{"protocolVersion":"2025-11-25","serverInfo":{"name":"ripwire","version":"1.0"},"capabilities":{"tools":{}},"instructions":"Map before reading files. Start a new task with explore; use from_trace for an error; use impact plus uses before changing a symbol; run edit_c … [line truncated: 249 more bytes on this line]
{"jsonrpc":"2.0","id":2,"result":{"content":[{"type":"text","text":"<batch schema=\"ripwire.batch/v1\" n=\"2\" requested=\"2\" cap=\"16\"><!-- ripwire batch ripwire.batch/v1: n= read sub-queries in one sweep (requested=, cap=): each <q> wraps one sub-answer verbatim in CDATA. --><q i=\"0\" verb=\"fo … [line truncated: 9770 more bytes on this line]
{\"name\":\"rankGraph\",\"kind\":\"fn\",\"file\":\"src/graph.h\",\"line\":2542,\"handle\":\"sym#b90da690b120eeb3@450dcd925d95850d\"},
{\"name\":\"anchoredLexicalRank\",\"kind\":\"fn\",\"file\":\"src/graph.h\",\"line\":3034,\"handle\":\"sym#b3a5ca7873636567@450dcd925d95850d\"},
{\"name\":\"churnRankedGraph\",\"kind\":\"fn\",\"file\":\"src/main.cpp\",\"line\":983,\"handle\":\"sym#4b5b63d3932ca0ff@7cb2a63217ad3292\"},
{\"name\":\"runDefaultMap\",\"kind\":\"fn\",\"file\":\"src/main.cpp\",\"line\":1098,\"handle\":\"sym#6e2725cb96590ec8@7cb2a63217ad3292\"},
{\"name\":\"getIndex\",\"kind\":\"fn\",\"file\":\"src/mcpindex.h\",\"line\":1104,\"handle\":\"sym#a6a2eb0bcd3b1383@55fd5e605f32a628\"}],\"graph_ambiguous\":6085,\"graph_unresolved\":3093,\"counts_floor\":true}]]></q></batch>"}],
"_index":"[index: files=1588 symbols=13849 hash=575f5b17]","_fresh":"ok"}}
`````

## `printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize"}' '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"edit_check","arguments":{"path":".","symbol":"rankGraphTeleport"}}}' | ./build/ripwire --mcp`

*MCP `edit_check` on a CLEAN tree.*

`````
{"jsonrpc":"2.0","id":1,"result":{"protocolVersion":"2025-11-25","serverInfo":{"name":"ripwire","version":"1.0"},"capabilities":{"tools":{}},"instructions":"Map before reading files. Start a new task with explore; use from_trace for an error; use impact plus uses before changing a symbol; run edit_c … [line truncated: 249 more bytes on this line]
{"jsonrpc":"2.0","id":2,"result":{"content":[{"type":"text","text":"<!-- ripwire edit-check ripwire.edit-check/v1: sym='s contract NOW vs HEAD: status=unchanged|new-symbol|contract-change; <c n= p= incompatible=1 sites_l=> callers. counts_floor=1: every count is a FLOOR, never a total. graph_ambiguo … [line truncated: 719 more bytes on this line]
"_index":"[index: files=1588 symbols=13849 hash=575f5b17]","_fresh":"ok"}}
`````

## `printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize"}' '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"edit_check","arguments":{"path":".","symbol":"rankGraphTeleport","legend":"compact"}}}' | ./build/ripwire --mcp`

*The same MCP `edit_check` with legend:"compact" — the CLI --legend=compact dialect on the MCP side (declared on the 16 XML verbs): ~5.5 KB of legend down to ~600 B, rows identical; an unknown or empty legend value is refused, never read as the default.*

`````
{"jsonrpc":"2.0","id":1,"result":{"protocolVersion":"2025-11-25","serverInfo":{"name":"ripwire","version":"1.0"},"capabilities":{"tools":{}},"instructions":"Map before reading files. Start a new task with explore; use from_trace for an error; use impact plus uses before changing a symbol; run edit_c … [line truncated: 249 more bytes on this line]
{"jsonrpc":"2.0","id":2,"result":{"content":[{"type":"text","text":"<!-- ripwire edit-check ripwire.edit-check/v1: sym='s contract NOW vs HEAD: status=unchanged|new-symbol|contract-change; <c n= p= incompatible=1 sites_l=> callers. counts_floor=1: every count is a FLOOR, never a total. graph_ambiguo … [line truncated: 719 more bytes on this line]
"_index":"[index: files=1588 symbols=13849 hash=575f5b17]","_fresh":"ok"}}
`````

## `printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize"}' '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"nosuchverb","arguments":{"path":"."}}}' | ./build/ripwire --mcp`

*An unknown verb name — the JSON-RPC error shape.*

`````
{"jsonrpc":"2.0","id":1,"result":{"protocolVersion":"2025-11-25","serverInfo":{"name":"ripwire","version":"1.0"},"capabilities":{"tools":{}},"instructions":"Map before reading files. Start a new task with explore; use from_trace for an error; use impact plus uses before changing a symbol; run edit_c … [line truncated: 249 more bytes on this line]
{"jsonrpc":"2.0","id":2,"error":{"code":-32602,"message":"unknown tool: 'nosuchverb' — call tools/list for the 31 available tools"}}
`````
