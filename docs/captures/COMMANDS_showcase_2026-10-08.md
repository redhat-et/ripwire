# ripwire — every verb, run for real

- **Date:** 2026-10-08 (regenerated capture; supersedes any older `docs/captures/COMMANDS_showcase_*.md`)
- **Lives in `docs/captures/`** — a directory the crawl/retrieval lenses SKIP (`kCrawlSkipDirs`, src/ingest.h): a generated doc that quotes every verb's output out-scores the source for any query about the tool and was measured at 77% of `--recall` on this repo when it sat at the root. `test/argvdiffcheck.sh` harvests its `## `-heading command lines as differential vectors — keep that format.
- **Version:** `ripwire 0.6.5 (dev, AppleClang 21.0.0.21000101, emit=std::print, built_from=c7920353a)`
- **Repo:** the ripwire repo @ `c7920353` — **CLEAN — `git status --porcelain` is empty**. The diff-aware verbs (`--situ`/`--test-gate`/`--quality-delta`/`--pr-context`/`--map-diff`/`--edit-check`) answer a question about the WORKING TREE, so that condition is part of their answer and every one of their captions below states which tree it recorded against. A clean tree is the honest default for a showcase, so they appear TWICE: once here on the clean tree (their empty/exit-0 shape) and once in the final section against a throwaway `git clone --local` sandbox carrying one deliberate regression, so their real gating shapes are visible without writing a byte into the read-only repo.
- **Corpus:** the ripwire repo itself (dogfood), via `./build/ripwire`
- **Sandbox diff** (the last section only): `.ripwire_notes        |  2 ++
 .ripwire_quality_acks |  1 +
 src/infra/sortutil.h  | 31 ++++++++++++++++++++++++++++---
 3 files changed, 31 insertions(+), 3 deletions(-)` — one preexisting function made deeply nested, one function's arity changed 1 -> 2, one copy-paste duplicate helper, one new 8-parameter public function.

**How to read the blocks:** ripwire's real XML output is minified — often ONE long line. For scanability, long minified lines are displayed re-wrapped with a line break at every tag seam (`><`). Header COMMENT lines (the legends) always appear in full — they are exempt from the per-line cut; any OTHER display line over 300 bytes is cut with a `… [line truncated: N more bytes]` marker, which can hit a long root element or row. `--plan-lanes` emits JSON and is re-wrapped at object seams the same way. Long outputs are cut to their first ~30 display lines with a `… [N more display lines; full output is M bytes]` marker giving the true size. Exit codes are recorded when non-zero; wall time when >1s.

**Not run (and why):** `ripwire <git-url>` (network clone), `--listen` / `--mcp-token` / `--allow-remote-edits` (the HTTP-server posture; `--mcp` itself IS captured in its own section as a one-shot stdio JSON-RPC exchange, and `wrap claude` shows the wiring), `--arch --baseline[-update]` (state writer against the read-only repo — `--note-add` / `--quality-baseline` / `--quality-ack` / the three edit verbs / `--edit-plan` ARE shown, inside the throwaway sandbox clone; `--index-out` / `--pin-census` write to scratch), `--eval-mined` (needs a `minedpair.jsonl` artifact from `bench/mine_traces.py`; none present in the tree), `--refetch` (git-url only), `--lsp` (the editor transport — its one-shot dialogues are gated by `test/lspcheck.sh`, not by showcase blocks), `--max-memory` (the memory guard is silent on this repo by construction; its stops are gated by `test/memguardcheck.sh`), `--force` (wrap-only modifier), `--scan-skills` bare form (would sweep `~/.claude/skills`; the explicit-DIR form is shown instead), `--help` (207 lines — read it from the binary).


---

# understand a codebase cold

## `./build/ripwire .`

*The default ranked symbol map — start here when landing cold in a repo.*

`````
<!-- ripwire map schema=ripwire.map/v1: ranked symbol map: <f p= layer=> groups <s t= n= sc= k= amb=> rows (k= rank), <c n=> resolved callees; the header comment is data. est_tokens=: price as emitted (an upper bound under compact). root=: p= relative to it. pr_iters=N: PageRank iterations. data_sections_cut=N: N data Sections (headings, data keys) swapped out of this top-K for lower-ranked code rows; next= pages them first. declined=K: K calls left unbound (no evidence chose one def). external=K: K calls proven outside the tree, no edge. locality_pinned=K: K calls pinned by locality alone (a guess). extent_suspect_syms=K: K defs failed containment, corpus-wide. macro_blanked_files=K: K files indexed from a macro-blanked re-parse. overloads=N: N same-name defs merged in this row; shown= counts each. prov=scip|binding|import|split|final-segment: how that <c> edge bound (absent: one unique name); split = one arm of an amb= pick; final-segment = a qualified type matched by last name only. files=/symbols=: files and symbols indexed; edges= distinct call edges; shown= symbols printed, a merged row counting each def; ambiguous= calls split over several defs, corpus-wide; unresolved= calls with in-tree evidence and no edge (every def language-filtered or unreachable, or binding refused); order= rows by rank (important-first, important-last; (auto:fill) = flipped past a size threshold) or by path (stable). skipped_oversize=K: K files over a size ceiling, not indexed. unindexed=ext:N: N text files of that extension no grammar reads (6 extensions at most). unindexed_exts=E: E such extensions in all, the list cut. sc=: enclosing scope; the full id is p::sc::n (p= of the row or its <f>) and selectors take it. amb=K: K calls split over several defs. next=: the one pasteable follow-up. -->
<!-- t=modscope=a-file's-MODULE-SCOPE(n=<file-scope>):the-statements-outside-every-named-definition,where-a-top-level-call-and-an-anonymous-callback-body's-calls-live;a-CALLER-never-a-callee(nothing-in-the-source-can-name-it)-with-no-body-to-expand;a-file-with-no-such-call-has-no-such-row -->
<!-- files=2484 symbols=23851 edges=34236 shown=200 est_tokens=8928 ambiguous=10278 unresolved=12878 locality_pinned=12 external=7345 declined=9922 extent_suspect_syms=10 macro_blanked_files=7 skipped_oversize=15 unindexed="txt:73,tsv:49,jsonl:26,scm:23,expected:15,xml:13" unindexed_exts=20 order=important-first -->
<r schema="ripwire.map/v1" root="." est_tokens="8928" pr_iters="28" data_sections_cut="1" next="--graph-query=&apos;kind(all,sec)&apos; --offset=0 --limit=200">
<f p="src/infra/svector.h" layer="infra">
<s t="method" n="buf" sc="svector" overloads="2" k="0.0072">
</s>
<s t="method" n="push_back" sc="svector" overloads="2" amb="2" k="0.0053">
<c n="buf" prov="split"/>
<c n="buf" prov="split"/>
<c n="grow"/>
</s>
<s t="method" n="grow" sc="svector" amb="1" k="0.0037">
<c n="isSpilled"/>
<c n="buf" prov="split"/>
<c n="buf" prov="split"/>
<c n="moveRange"/>
<c n="maxSize"/>
</s>
<s t="method" n="end" sc="svector" overloads="2" amb="1" k="0.0025">
<c n="buf" prov="split"/>
<c n="buf" prov="split"/>
</s>
<s t="method" n="empty" sc="svector" k="0.0021">
</s>
<s t="method" n="reserve" sc="svector" k="0.0018">
<c n="grow"/>
</s>
<s t="method" n="begin" sc="svector" overloads="2" amb="1" k="0.0012">
<c n="buf" prov="split"/>
… [800 more display lines; full output is 22162 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --top-k=5`

*Same map, capped to the 5 highest-ranked symbols.*

`````
<!-- ripwire map schema=ripwire.map/v1: ranked symbol map: <f p= layer=> groups <s t= n= sc= k= amb=> rows (k= rank), <c n=> resolved callees; the header comment is data. est_tokens=: price as emitted (an upper bound under compact). root=: p= relative to it. pr_iters=N: PageRank iterations. declined=K: K calls left unbound (no evidence chose one def). external=K: K calls proven outside the tree, no edge. locality_pinned=K: K calls pinned by locality alone (a guess). extent_suspect_syms=K: K defs failed containment, corpus-wide. macro_blanked_files=K: K files indexed from a macro-blanked re-parse. overloads=N: N same-name defs merged in this row; shown= counts each. files=/symbols=: files and symbols indexed; edges= distinct call edges; shown= symbols printed, a merged row counting each def; ambiguous= calls split over several defs, corpus-wide; unresolved= calls with in-tree evidence and no edge (every def language-filtered or unreachable, or binding refused); order= rows by rank (important-first, important-last; (auto:fill) = flipped past a size threshold) or by path (stable). skipped_oversize=K: K files over a size ceiling, not indexed. unindexed=ext:N: N text files of that extension no grammar reads (6 extensions at most). unindexed_exts=E: E such extensions in all, the list cut. sc=: enclosing scope; the full id is p::sc::n (p= of the row or its <f>) and selectors take it. -->
<!-- t=modscope=a-file's-MODULE-SCOPE(n=<file-scope>):the-statements-outside-every-named-definition,where-a-top-level-call-and-an-anonymous-callback-body's-calls-live;a-CALLER-never-a-callee(nothing-in-the-source-can-name-it)-with-no-body-to-expand;a-file-with-no-such-call-has-no-such-row -->
<!-- files=2484 symbols=23851 edges=34236 shown=5 est_tokens=988 ambiguous=10278 unresolved=12878 locality_pinned=12 external=7345 declined=9922 extent_suspect_syms=10 macro_blanked_files=7 skipped_oversize=15 unindexed="txt:73,tsv:49,jsonl:26,scm:23,expected:15,xml:13" unindexed_exts=20 order=important-first -->
<r schema="ripwire.map/v1" root="." est_tokens="988" pr_iters="28">
<f p="src/infra/svector.h" layer="infra">
<s t="method" n="buf" sc="svector" overloads="2" k="0.0072">
</s>
</f>
<f p="src/resolve.h">
<s t="method" n="empty" sc="RubyConstantIndex" k="0.0071">
</s>
</f>
<f p="src/infra/os_win32_logic.h" layer="infra">
<s t="method" n="ok" sc="WidePath" k="0.0063">
</s>
</f>
<f p="src/notes.h">
<s t="method" n="empty" sc="NoteIndex" k="0.0053">
</s>
</f>
</r>
`````

## `./build/ripwire . --top-k=0 --expand=rankGraphTeleport`

*NEW since the last capture: --top-k=0 means PAYLOAD-ONLY — no ranked map rides along with the body you asked for.*

`````
<ctx schema="ripwire.expand/v1" root="." est_tokens="1261">
<!-- ripwire expand schema=ripwire.expand/v1: full bodies: <bodies shown= total= capped=> of <b t= l= p= n= sibs= sibs_total= sibs_capped= inc=>; <calls>
<c n= l=> resolved callees. window: shown= total= capped= (capped=1 cut). sibs_capped=/inc_capped=: 1 = cut. est_tokens=: price as emitted (an upper bound under compact). root=: p= relative to it. scrubbed=1: this CDATA is not the bytes (]]> split or C0 replaced). redacted=1: a credential shape rewr … [line truncated: 165 more bytes on this line]
<bodies shown="1" total="1" capped="0">
<b t="fn" l="5565" p="src/graph.h" n="rankGraphTeleport" sibs="Graph,provLabel,langCompatible,namespaceCompatible,kCommonNameMul,kCommonNameDefThreshold,kPrivateNameMul,kSpecificNameMul,kSpecificMinLen,kSpecificMinWords,wordCount,weight,decodeJniName,splitSegments,isTemplateSegment,pathsMatch,method … [line truncated: 1808 more bytes on this line]
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
}]]><calls total="8"><c n="biasPrior" l="5524">inline std::vector&lt;float&gt; biasPrior( const Graph&amp; g, const std::vector&lt;float&gt;&amp; p )</c><c n="PROFILE_SCOPE_DESCRIBE" l="1279">#define PROFILE_SCOPE_DESCRIBE( desc )</c><c n="PROFILE_SCOPE_DESCRIBE" l="1293">#define PROFILE_SCOPE_DESCR … [line truncated: 480 more bytes on this line]
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
<!-- ripwire map schema=ripwire.map/v1: ranked symbol map: <f p= layer=> groups <s t= n= sc= k= amb=> rows (k= rank), <c n=> resolved callees; the header comment is data. est_tokens=: price as emitted (an upper bound under compact). over_ceiling=1: budget not met. root=: p= relative to it. pr_iters=N: PageRank iterations. declined=K: K calls left unbound (no evidence chose one def). external=K: K calls proven outside the tree, no edge. locality_pinned=K: K calls pinned by locality alone (a guess). extent_suspect_syms=K: K defs failed containment, corpus-wide. macro_blanked_files=K: K files indexed from a macro-blanked re-parse. max_tokens=/fit_bytes=: tokens asked/the byte cap applied. files=/symbols=: files and symbols indexed; edges= distinct call edges; shown= symbols printed, a merged row counting each def; ambiguous= calls split over several defs, corpus-wide; unresolved= calls with in-tree evidence and no edge (every def language-filtered or unreachable, or binding refused); order= rows by rank (important-first, important-last; (auto:fill) = flipped past a size threshold) or by path (stable). skipped_oversize=K: K files over a size ceiling, not indexed. unindexed=ext:N: N text files of that extension no grammar reads (6 extensions at most). unindexed_exts=E: E such extensions in all, the list cut. sc=: enclosing scope; the full id is p::sc::n (p= of the row or its <f>) and selectors take it. -->
<!-- t=modscope=a-file's-MODULE-SCOPE(n=<file-scope>):the-statements-outside-every-named-definition,where-a-top-level-call-and-an-anonymous-callback-body's-calls-live;a-CALLER-never-a-callee(nothing-in-the-source-can-name-it)-with-no-body-to-expand;a-file-with-no-such-call-has-no-such-row -->
<!-- files=2484 symbols=23851 edges=34236 shown=1 est_tokens=900 ambiguous=10278 unresolved=12878 locality_pinned=12 external=7345 declined=9922 extent_suspect_syms=10 macro_blanked_files=7 skipped_oversize=15 unindexed="txt:73,tsv:49,jsonl:26,scm:23,expected:15,xml:13" unindexed_exts=20 max_tokens=1500 fit_bytes=3186 over_ceiling=1 order=important-first -->
<r schema="ripwire.map/v1" root="." est_tokens="900" pr_iters="28">
<f p="src/infra/svector.h" layer="infra">
<s t="method" n="buf" sc="svector" k="0.0072">
</s>
</f>
</r>
`````

## `./build/ripwire . --token-budget=100`

*GATE form: exit 3 if the map's own est_tokens exceeds the budget (over-budget failure shape).*

**exit code: 3**

`````
<!-- ripwire map schema=ripwire.map/v1: the ranked map WITHHELD whole, no rows: withheld=1 marks this record, withheld_est_tokens= the map's price, over budget= (the token budget asked); rerun with a larger token budget, or max-tokens to shape a map that fits. -->
<r schema="ripwire.map/v1" withheld_est_tokens="8928" budget="100" withheld="1"/>
`````

stderr:

`````
ripwire: --token-budget exceeded: withheld_est_tokens=8928 > budget=100
`````

## `./build/ripwire . --for="incremental cache invalidation when a file content hash changes"`

*The task lens: ranked signatures + quality metrics framed for the task.*

**wall time: 1.80s**

`````
<ctx task="incremental cache invalidation when a file content hash changes" route="subtoken+body" root="." confidence="low" margin_pct="0" at="c7920353a" doc_mentions="5" schema="ripwire.for/v1" bundle="compact" bodies="0" reason="compact-route" budget_bytes="7500" doc_mentions_capped="1" doc_mentio … [line truncated: 31 more bytes on this line]
<!-- ripwire for schema=ripwire.for/v1: bundle=/bodies=/reason= the body posture; d: cx= ccx= complexity, in= callers (absent cx/ccx/in = 0), churn= amp= change, clone= tested= 1, sc= scope, id=p::sc::n; total= shown= capped=1 if cut; task= the query; d pure=1 const/constexpr sig, next= the follow-up to paste; route= name-exact(X)|subtoken+body[:broad|:declined]; confidence=/margin_pct= head score drop (low=flat); h l= p= n=, c n= l= (joined for same-named callees, shown= counts them), noedge= no callee resolved; t p= file outside sigs (weaker), r= rank (gap = trimmed); field name= type= owner= rel=: a member of owner=, rel=creates held by value, uses by reference/pointer; iface implementors=N: types implementing it, m= its method contract; d layer=: built-in arch layer (game|infra|render|math|audio|ai|test) from a dir name in p= [doc mentions: 5 docs, 3 symbols; doc_mentions=] -->
<!-- root= is the crawl root; p= below is RELATIVE to it (single-root only; absent => p= is ingest's own path, unchanged); at=this commit(+dirty). dropped_positive="17" [budget_bytes= is the default BYTE ceiling this ranked payload was shaped against; it bounds that payload, not the whole document est_tokens prices] [docs_dropped=N: N shown rows have a doc comment not printed (r>24 always, r5..24 if capped)] [cut: doc_mentions_capped="1" doc_mentions_total="6" — an indexing cap dropped content not shown here]; lego/compose collapse to a counted stub by default (a disclosed cut): total= that section's own pre-cap row count, shown="0" capped="1" (nothing rendered here), next= names the sections=lego,compose flag that restores both sections byte-identically in one call est_tokens= prices this bundle in tokens -->
<sigs shown="23" total="40" capped="1" docs_dropped="16">
<d l="125" n="kCacheMagic" p="src/ingest_cache.h" churn="185" amp="332" pure="1" r="1" next="--expand=src/ingest_cache.h:kCacheMagic">
<doc>incremental cache (--cache): per-file content hash + raw facts so a re-run re-parses ONLY      c…</doc>constexpr std::uint32_t kCacheMagic = 0x4b505443</d>
<d l="2070" n="kHeadSnapCacheScheme" sc="quality" p="src/quality.h" churn="357" amp="510" pure="1" r="2">
<doc>and every file whose content hash differs is re-parsed — so a stale or foreign blob self-heals…</doc>constexpr std::uint32_t kHeadSnapCacheScheme = 1</d>
<d l="493" n="McpIndex" sc="McpIndex" p="src/mcpindex.h" churn="48" amp="111" r="3">
<doc>persistent in-memory index (parse once, reuse across MCP calls) ---- The MCP server is long-live…</doc>struct McpIndex</d>
<d l="1165" n="getIndex" sc="rw" p="src/mcpindex.h" cx="22" ccx="39" in="35" churn="48" amp="146" r="4">
<doc>the cached index for `root`, rebuilt only when stale (otherwise returned as-is, no parse, no gra…</doc>inline const McpIndex&amp; getIndex( const std::string&amp; root )</d>
<d l="766" n="mcpRebuildBaseline" sc="rw" p="src/mcpindex.h" cx="2" ccx="1" in="1" churn="48" amp="112" r="5">inline McpRebuildBaseline mcpRebuildBaseline( const McpIndex&amp; ix, bool isIncrementalPass )</d>
<d l="1541" n="contentHash64" p="src/ingest_cache.h" cx="2" ccx="1" in="4" churn="185" amp="336" tested="1" r="6">inline std::uint64_t contentHash64( std::string_view s ) noexcept</d>
<d l="1642" n="CacheEntry" sc="CacheEntry" p="src/ingest_cache.h" churn="185" amp="332" r="7">struct CacheEntry</d>
<d l="279" n="prewarmTagsQueries" p="src/ingest_prewarm.h" cx="53" ccx="160" in="1" churn="14" amp="52" tested="1" r="8">inline void prewarmTagsQueries( const std::vector&lt;std::string&gt;&amp; files, const HashMap&lt;std::string, FileFacts&gt;&amp; cache, long long cacheWriteNs, IngestFileScan&amp … [line truncated: 12 more bytes on this line]
<d l="1556" n="blobChecksum" p="src/ingest_cache.h" cx="5" ccx="5" in="4" churn="185" amp="336" tested="1" r="9">inline std::uint64_t blobChecksum( std::string_view s ) noexcept</d>
<d l="1628" n="contentIdsBySym" sc="quality" p="src/quality.h" cx="3" ccx="3" in="1" churn="357" amp="511" r="10">inline ContentIdIndex contentIdsBySym( const IngestResult&amp; ing, const Graph&amp; g, std::string_view root )</d>
<d l="277" n="ingestCommitTree" sc="rw::dmm" p="src/dmm.h" cx="6" ccx="5" in="1" churn="16" amp="77" r="11">inline bool ingestCommitTree( const std::string&amp; root, const std::string&amp; sha, const std::vector&lt;std::string&gt;&amp; excludes, std::size_t maxFileBytes, IngestResult&amp;…</d>
<d l="2771" n="buildCacheWritePlan" p="src/ingest_cache.h" cx="11" ccx="14" in="1" churn="185" amp="333" tested="1" r="12">inline std::vector&lt;CacheWriteRow&gt; buildCacheWritePlan( const std::vector&lt;std::uint32_t&gt;&amp; orderIn, const std::vector&lt;std::uint64_t&gt;&amp; pathHashes, const s … [line truncated: 16 more bytes on this line]
<d l="7592" n="legoImplementorsOnSurface" sc="rw" p="src/serialize.h" cx="10" ccx="13" in="2" churn="249" amp="389" r="13">inline std::vector&lt;std::vector&lt;NodeId&gt;&gt; legoImplementorsOnSurface( const IngestResult&amp; ing, const std::vector&lt;std::vector&lt;NodeId&gt;&gt;&amp; implementors, … [line truncated: 54 more bytes on this line]
<d l="2283" n="reAbsolutize" p="src/ingest_cache.h" cx="4" ccx="3" in="1" churn="185" amp="333" tested="1" r="14">inline std::string reAbsolutize( std::string_view rel, std::string_view root )</d>
<d l="2740" n="buildCachePathKeys" p="src/ingest_cache.h" cx="3" ccx="3" in="1" churn="185" amp="333" tested="1" r="15">inline CachePathKeys buildCachePathKeys( const std::vector&lt;std::string&gt;&amp; files, std::string_view rootDir )</d>
<d l="25" n="IngestFileScan" sc="IngestFileScan" p="src/ingest_prewarm.h" churn="14" amp="51" r="16">struct IngestFileScan</d>
<d l="462" n="indexContentHash" sc="mcpdetail" p="src/mcpindex.h" cx="5" ccx="7" in="1" churn="48" amp="112" r="17">inline std::uint64_t indexContentHash( const std::vector&lt;std::string&gt;&amp; files, const std::vector&lt;long long&gt;&amp; fileMtime, const std::vector&lt;std::uint64_t&gt;&amp; f … [line truncated: 17 more bytes on this line]
<d l="399" n="makeHandle" sc="mcpdetail" p="src/mcpindex.h" cx="1" in="2" churn="48" amp="113" r="18">inline std::string makeHandle( const std::string&amp; canonId, const std::string&amp; path, const std::string&amp; name, std::uint64_t contentHash )</d>
<d l="753" n="runParsePool" p="src/ingest_parsepool.h" cx="25" ccx="54" in="1" churn="47" amp="125" tested="1" r="19">inline RawFacts runParsePool( IngestResult&amp; result, const char* rootDir, std::string_view cacheFile, bool captureValueUses, HashMap&lt;std::string, FileFacts&gt;&amp; cache, cons … [line truncated: 91 more bytes on this line]
<d l="1628" n="spanTierMemoPath" sc="rw" p="src/ingest_astquery.h" cx="1" in="3" churn="41" amp="136" tested="1" r="20">inline std::string spanTierMemoPath( const std::string&amp; diskPath )</d>
<d l="131" n="collectExtractPartials" p="src/ingest_prewarm.h" cx="1" in="1" churn="14" amp="52" clone="1" tested="1" r="21">inline void collectExtractPartials( const IngestFileScan&amp; scan, IngestResult&amp; result )</d>
<d l="1391" n="resolveHandleAll" sc="rw" p="src/mcpindex.h" cx="4" ccx="6" in="3" churn="48" amp="114" r="22">inline NodeId resolveHandleAll( const McpIndex&amp; ix, std::uint64_t idHash, std::vector&lt; NodeId &gt;&amp; matches )</d>
… [46 more display lines; full output is 8961 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --for="rankGraphTeleport"`

*Name-shaped query: the router picks name-exact BM25 (header says which/why).*

`````
<ctx task="rankGraphTeleport" route="name-exact(rankGraphTeleport); anchors: rankGraphTeleport(src/graph.h)" root="." confidence="high" margin_pct="45" at="c7920353a" doc_mentions="2" schema="ripwire.for/v1" bundle="auto" bodies="1" doc_mentions_capped="1" doc_mentions_total="13" est_tokens="1430">
<!-- ripwire for schema=ripwire.for/v1: bundle=/bodies=/reason= the body posture; d: cx= ccx= complexity, in= callers (absent cx/ccx/in = 0), churn= amp= change, clone= tested= 1, sc= scope, id=p::sc::n; total= shown= capped=1 if cut; task= the query; d pure=1 const/constexpr sig, next= the follow-up to paste; route= name-exact(X)|subtoken+body[:broad|:declined]; confidence=/margin_pct= head score drop (low=flat); b t= n= p= l= full bodies, c n= l= callee signatures; t p= file outside sigs (weaker), r= rank (gap = trimmed) [doc mentions: 2 docs, 1 symbol; doc_mentions=] [floor: kept 3 of 40] -->
<!-- root= is the crawl root; p= below is RELATIVE to it (single-root only; absent => p= is ingest's own path, unchanged); at=this commit(+dirty). [cut: doc_mentions_capped="1" doc_mentions_total="13" — an indexing cap dropped content not shown here] est_tokens= prices this bundle in tokens -->
<sigs>
<d l="5565" n="rankGraphTeleport" sc="rw" p="src/graph.h" cx="5" ccx="8" in="7" churn="245" amp="401" r="1" next="--expand=src/graph.h:rankGraphTeleport">
<doc>PageRank with an explicit teleport / personalization vector p (Σp = 1). The prior is name-quality-biased through biasPrior() so all rank modes share one weighting seam; the transition matrix (edges</doc>inline RankedGraph rankGraphTeleport( const Graph&amp; g, const std::vector&lt;float&gt;&am … [line truncated: 31 more bytes on this line]
<d l="456" n="The convergence disclosure contract" sc="rank — Personalized PageRank" p="docs/ARCHITECTURE.md" churn="49" amp="153" r="2">#### The convergence disclosure contract</d>
<d l="6303" n="Wave-2 adversarial verification (2026-08-19) — six probes against `aa97c9e`" sc="6. Correctness and quality instruments" p="docs/EVALS.md" churn="834" amp="1058" r="3">### Wave-2 adversarial verification (2026-08-19) — six probes against `aa97c9e`</d>
</sigs>
<tail total="0" shown="0" capped="0">
</tail>
<bodies shown="1" total="1" capped="0">
<b t="fn" l="5565" p="src/graph.h" n="rankGraphTeleport">
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
… [12 more display lines; full output is 4288 bytes on 29 raw line(s)]
`````

## `./build/ripwire . --for="rankGraphTeleport" --no-route`

*Same query with routing forced OFF (plain subtoken+body BM25) — contrast with the routed run.*

`````
<ctx task="rankGraphTeleport" root="." confidence="low" margin_pct="0" at="c7920353a" doc_mentions="6" schema="ripwire.for/v1" bundle="auto" bodies="3" budget_bytes="7500" doc_mentions_capped="1" doc_mentions_total="20" est_tokens="5065">
<!-- ripwire for schema=ripwire.for/v1: bundle=/bodies=/reason= the body posture; d: cx= ccx= complexity, in= callers (absent cx/ccx/in = 0), churn= amp= change, clone= tested= 1, sc= scope, id=p::sc::n; total= shown= capped=1 if cut; task= the query; d pure=1 const/constexpr sig, next= the follow-up to paste; confidence=/margin_pct= head score drop (low=flat); b t= n= p= l= full bodies, c n= l= callee signatures; t p= file outside sigs (weaker), r= rank (gap = trimmed); field name= type= owner= rel=: a member of owner=, rel=creates held by value, uses by reference/pointer; d layer=: built-in arch layer (game|infra|render|math|audio|ai|test) from a dir name in p= [doc mentions: 6 docs, 3 symbols; doc_mentions=] -->
<!-- root= is the crawl root; p= below is RELATIVE to it (single-root only; absent => p= is ingest's own path, unchanged); at=this commit(+dirty). dropped_positive="17" [budget_bytes= is the default BYTE ceiling this ranked payload was shaped against; it bounds that payload, not the whole document est_tokens prices] [docs_dropped=N: N shown rows have a doc comment not printed (r>24 always, r5..24 if capped)] [cut: doc_mentions_capped="1" doc_mentions_total="20" — an indexing cap dropped content not shown here]; lego/compose collapse to a counted stub by default (a disclosed cut): total= that section's own pre-cap row count, shown="0" capped="1" (nothing rendered here), next= names the sections=lego,compose flag that restores both sections byte-identically in one call est_tokens= prices this bundle in tokens -->
<sigs shown="23" total="40" capped="1" docs_dropped="15">
<d l="5606" n="rankGraph" sc="rw" p="src/graph.h" cx="2" ccx="1" in="10" churn="245" amp="404" r="1" next="--expand=src/graph.h:rankGraph">
<doc>uniform-teleport PageRank (the default</doc>inline RankedGraph rankGraph( const Graph&amp; g, float alpha = 0.85f )</d>
<d l="5565" n="rankGraphTeleport" sc="rw" p="src/graph.h" cx="5" ccx="8" in="7" churn="245" amp="401" r="2">
<doc>PageRank with an explicit teleport / personalization vector p (Σp = 1). The prior is name-quali…</doc>inline RankedGraph rankGraphTeleport( const Graph&amp; g, const std::vector&lt;float&gt;&amp; p, float alpha = 0.85f )</d>
<d l="1419" n="churnRankedGraph" p="src/main.cpp" cx="10" ccx="12" in="1" churn="414" amp="516" r="3">inline ChurnRanking churnRankedGraph( const MainDispatch&amp; d )</d>
<d l="2206" n="kChurnRankLegend" sc="rw" p="src/serialize.h" churn="249" amp="387" pure="1" r="4">
<doc>L10 (2026-09-04): the old wording claimed &quot;the same corpus ranked by pagerank orders differently…</doc>inline constexpr const char* kChurnRankLegend = &quot;&lt;!-- rank_by=churn: k= is PageRank re-run with the teleport BIASED by git CHANGE-FREQUENCY over window= &quot; &quot;(a c…</d>
<d l="5556" n="RankedGraph" sc="RankedGraph" p="src/graph.h" churn="245" amp="394" r="5">struct RankedGraph</d>
<d l="5599" n="takeRank" sc="rw" p="src/graph.h" cx="1" in="2" churn="245" amp="396" r="6">inline std::vector&lt;float&gt; takeRank( RankedGraph ranked, RankDisclosure&amp; disclosureOut )</d>
<d l="5524" n="biasPrior" sc="rw" p="src/graph.h" cx="5" ccx="4" in="1" churn="245" amp="395" r="7">inline std::vector&lt;float&gt; biasPrior( const Graph&amp; g, const std::vector&lt;float&gt;&amp; p )</d>
<d l="1914" n="churnTeleportWorkspace" sc="rw" p="src/gitmine.h" cx="6" ccx="9" in="1" churn="59" amp="114" r="8">inline std::vector&lt;float&gt; churnTeleportWorkspace( const std::vector&lt;std::string&gt;&amp; rootDirs, const IngestResult&amp; ing, const char* since = &quot;18 months ago&quot;, bo … [line truncated: 11 more bytes on this line]
<d l="1380" n="churnDecayRanking" p="src/main.cpp" cx="7" ccx="7" in="1" churn="414" amp="516" r="9">inline ChurnRanking churnDecayRanking( const MainDispatch&amp; d, const rw::SinceScope&amp; sinceScope, bool isScoped, const char* verbLabel )</d>
<d l="474" n="rankByText" sc="rw" p="src/mcpverbs.h" cx="10" ccx="17" in="1" churn="309" amp="406" r="10">inline std::string rankByText( const std::string&amp; root, std::string_view mode, int topK, bool stable = false )</d>
<d l="48" n="pageRankDouble" sc="rw" p="src/pagerank.h" cx="1" churn="8" amp="37" r="11">PageRankRun pageRankDouble( const sparseCsr&lt;float&gt;&amp; inEdges, std::span&lt;const double&gt; weightedOutDegree, std::span&lt;const double&gt; teleport, std::span&lt;double&gt; rank…</d>
<d l="240" n="didYouMean" sc="rw" p="src/didyoumean.h" cx="2" ccx="1" in="7" churn="9" amp="38" r="12">inline std::string didYouMean( const IngestResult&amp; ing, std::string_view name )</d>
<d l="2121" n="churnDecayTeleport" sc="rw" p="src/gitmine.h" cx="4" ccx="3" churn="59" amp="113" r="13">inline std::vector&lt;float&gt; churnDecayTeleport( const std::string&amp; root, const IngestResult&amp; ing, const SinceScope* scope = nullptr, bool* outHasChurnEvidence = nullptr )</d>
<d l="99" n="pageRankDouble" sc="rw" p="src/pagerank.cpp" cx="19" ccx="34" in="2" churn="14" amp="44" tested="1" r="14">PageRankRun pageRankDouble( const sparseCsr&lt;float&gt;&amp; inEdges, std::span&lt;const double&gt; weightedOutDegree, std::span&lt;const double&gt; teleport, std::span&lt;double& … [line truncated: 37 more bytes on this line]
<d l="1165" n="getIndex" sc="rw" p="src/mcpindex.h" cx="22" ccx="39" in="35" churn="48" amp="146" r="15">inline const McpIndex&amp; getIndex( const std::string&amp; root )</d>
<d l="2219" n="churnDecayTeleportWorkspace" sc="rw" p="src/gitmine.h" cx="5" ccx="6" in="1" churn="59" amp="114" r="16">inline std::vector&lt;float&gt; churnDecayTeleportWorkspace( const std::vector&lt;std::string&gt;&amp; rootDirs, const IngestResult&amp; ing, bool* outHasChurnEvidence = nullptr )< … [line truncated: 3 more bytes on this line]
<d l="1946" n="DataSectionsCut" sc="DataSectionsCut" p="src/serialize.h" churn="249" amp="387" r="17">struct DataSectionsCut</d>
<d l="171" n="runEval" sc="rw" p="src/eval.h" cx="44" ccx="66" in="1" churn="16" amp="29" r="18">inline int runEval( const std::string&amp; root, const IngestResult&amp; ing, const Graph&amp; g, const std::vector&lt;char&gt;&amp; currentDiff )</d>
<d l="6252" n="anchoredLexicalRank" sc="rw" p="src/graph.h" cx="11" ccx="12" in="4" churn="245" amp="398" r="19">inline std::vector&lt;float&gt; anchoredLexicalRank( const Graph&amp; g, const std::vector&lt;float&gt;&amp; lex )</d>
<d l="1882" n="kChurnMergeBombMaxFiles" sc="rw" p="src/gitmine.h" churn="59" amp="113" pure="1" r="20">inline constexpr std::size_t kChurnMergeBombMaxFiles = 100</d>
<d l="2497" n="Fixed — `rank_by` over MCP no longer answers a different ranking than `--rank-by` on a tree with uncommitted changes" sc="[0.6.2] — 2026-09-21" p="CHANGELOG.md" churn="688" amp="624" r="21">### Fixed — `rank_by` over MCP no longer answers a different ranking than `--rank-by` on  … [line truncated: 35 more bytes on this line]
<d l="14284" n="2. Gates for A" sc="Map data Sections never crowd code out of the default map (#339 F1) — PRE-REGISTERED 2026-09-30 (before any fix code or arm number)" p="docs/EVALS.md" churn="834" amp="1058" r="22">### 2. Gates for A</d>
<d l="456" n="The convergence disclosure contract" sc="rank — Personalized PageRank" p="docs/ARCHITECTURE.md" churn="49" amp="153" r="23">#### The convergence disclosure contract</d>
… [102 more display lines; full output is 14999 bytes on 72 raw line(s)]
`````

## `./build/ripwire . --for="rankGraphTeleport" --signatures-only`

*T3 opt-out: the signatures-only lens (no auto bodies, no bundle="auto" attribute) — contrast with the terminal default above.*

`````
<ctx task="rankGraphTeleport" route="name-exact(rankGraphTeleport); anchors: rankGraphTeleport(src/graph.h)" root="." confidence="high" margin_pct="45" at="c7920353a" doc_mentions="2" schema="ripwire.for/v1" doc_mentions_capped="1" doc_mentions_total="13" est_tokens="848">
<!-- ripwire for schema=ripwire.for/v1: bundle=/bodies=/reason= the body posture; d: cx= ccx= complexity, in= callers (absent cx/ccx/in = 0), churn= amp= change, clone= tested= 1, sc= scope, id=p::sc::n; total= shown= capped=1 if cut; task= the query; d pure=1 const/constexpr sig, next= the follow-up to paste; route= name-exact(X)|subtoken+body[:broad|:declined]; confidence=/margin_pct= head score drop (low=flat); t p= file outside sigs (weaker), r= rank (gap = trimmed) [doc mentions: 2 docs, 1 symbol; doc_mentions=] [floor: kept 3 of 40] -->
<!-- root= is the crawl root; p= below is RELATIVE to it (single-root only; absent => p= is ingest's own path, unchanged); at=this commit(+dirty). [cut: doc_mentions_capped="1" doc_mentions_total="13" — an indexing cap dropped content not shown here] est_tokens= prices this bundle in tokens -->
<sigs>
<d l="5565" n="rankGraphTeleport" sc="rw" p="src/graph.h" cx="5" ccx="8" in="7" churn="245" amp="401" r="1" next="--expand=src/graph.h:rankGraphTeleport">
<doc>PageRank with an explicit teleport / personalization vector p (Σp = 1). The prior is name-quality-biased through biasPrior() so all rank modes share one weighting seam; the transition matrix (edges</doc>inline RankedGraph rankGraphTeleport( const Graph&amp; g, const std::vector&lt;float&gt;&am … [line truncated: 31 more bytes on this line]
<d l="456" n="The convergence disclosure contract" sc="rank — Personalized PageRank" p="docs/ARCHITECTURE.md" churn="49" amp="153" r="2">#### The convergence disclosure contract</d>
<d l="6303" n="Wave-2 adversarial verification (2026-08-19) — six probes against `aa97c9e`" sc="6. Correctness and quality instruments" p="docs/EVALS.md" churn="834" amp="1058" r="3">### Wave-2 adversarial verification (2026-08-19) — six probes against `aa97c9e`</d>
</sigs>
<tail total="0" shown="0" capped="0">
</tail>
</ctx>
`````

## `./build/ripwire . --for="tree-sitter parse of a source file" --adaptive`

*Cut the result at the relevance cliff (Adaptive-k) — on a flat ranking nothing is cut and the header says so ([adaptive: kept N of N]).*

`````
<ctx task="tree-sitter parse of a source file" route="subtoken+body" root="." confidence="low" margin_pct="0" at="c7920353a" doc_mentions="3" schema="ripwire.for/v1" bundle="compact" bodies="0" reason="compact-route" budget_bytes="7500" est_tokens="3577">
<!-- ripwire for schema=ripwire.for/v1: bundle=/bodies=/reason= the body posture; d: cx= ccx= complexity, in= callers (absent cx/ccx/in = 0), churn= amp= change, clone= tested= 1, sc= scope, id=p::sc::n; total= shown= capped=1 if cut; task= the query; d pure=1 const/constexpr sig, next= the follow-up to paste; route= name-exact(X)|subtoken+body[:broad|:declined]; confidence=/margin_pct= head score drop (low=flat); h l= p= n=, c n= l= (joined for same-named callees, shown= counts them), noedge= no callee resolved; t p= file outside sigs (weaker), r= rank (gap = trimmed); field name= type= owner= rel=: a member of owner=, rel=creates held by value, uses by reference/pointer; iface implementors=N: types implementing it, m= its method contract; d layer=: built-in arch layer (game|infra|render|math|audio|ai|test) from a dir name in p= [adaptive: kept 40 of 40 - no relevance cliff (broad query saturates the score); capped at the ceiling] [doc mentions: 3 docs, 2 symbols; doc_mentions=] -->
<!-- root= is the crawl root; p= below is RELATIVE to it (single-root only; absent => p= is ingest's own path, unchanged); at=this commit(+dirty). dropped_positive="11" [budget_bytes= is the default BYTE ceiling this ranked payload was shaped against; it bounds that payload, not the whole document est_tokens prices] [docs_dropped=N: N shown rows have a doc comment not printed (r>24 always, r5..24 if capped)]; lego/compose collapse to a counted stub by default (a disclosed cut): total= that section's own pre-cap row count, shown="0" capped="1" (nothing rendered here), next= names the sections=lego,compose flag that restores both sections byte-identically in one call est_tokens= prices this bundle in tokens -->
<sigs shown="29" total="40" capped="1" docs_dropped="23">
<d l="28" n="topLevelEvidence" sc="rw::pythonrunner" p="src/pythonrunner.h" cx="4" ccx="3" in="2" churn="5" amp="15" r="1" next="--expand=src/pythonrunner.h:topLevelEvidence">inline bool topLevelEvidence( std::string_view source, const TSLanguage* language, const Predicate&amp; predicate )</d>
<d l="45" n="kDefaultMaxFileBytes" sc="rw" p="src/ingest.h" churn="57" amp="162" pure="1" r="2">
<doc>The crawl&apos;s per-file byte ceiling. A text file larger than this is skipped: at this size it is o…</doc>constexpr std::size_t kDefaultMaxFileBytes = 4u * 1024u * 1024u</d>
<d l="1153" n="parseTree" p="src/ingest_sidecap.h" cx="1" in="2" churn="81" amp="217" tested="1" r="3">TSTree* parseTree( TSParser* parser, std::string_view src )</d>
<d l="588" n="doctorProbeGrammars" p="src/verbs_doctor.h" cx="7" ccx="17" in="1" churn="43" amp="127" r="4">
<doc>Exercise every registered grammar and its embedded query, reporting loaded and expected totals</doc>inline DoctorGrammarProbe doctorProbeGrammars()</d>
<d l="1233" n="FileHealth" sc="FileHealth" p="src/model.h" churn="136" amp="315" r="5">struct FileHealth</d>
<d l="456" n="AstWalk" sc="rw" p="src/ingest.h" churn="57" amp="162" r="6">enum class AstWalk : std::uint8_t</d>
<d l="369" n="sliceAtRev" sc="slicediff" p="src/slicediff.h" cx="13" ccx="13" in="1" churn="11" amp="61" r="7">inline RevSide sliceAtRev( const std::string&amp; root, const std::string&amp; sha, const std::string&amp; rel, const Symbol&amp; sym, SliceFam fam, const ::TSLanguage* grammar…</d>
<d l="308" n="SliceScan" sc="SliceScan" p="src/slice.h" churn="51" amp="102" r="8">struct SliceScan</d>
<d l="1222" n="astroFenceTailIsBlank" p="src/ingest_sidecap.h" cx="1" in="2" churn="81" amp="217" tested="1" r="9">inline bool astroFenceTailIsBlank( std::string_view src, std::size_t from, std::size_t to ) noexcept</d>
<d l="96" n="kLangTable" p="src/ingest_crawl.h" churn="66" amp="191" pure="1" r="10">constexpr std::array&lt;LangEntry, 51&gt; kLangTable =</d>
<d l="134" n="kMaxKotlinStringNestDepth" sc="rw" p="src/ingest.h" churn="57" amp="162" pure="1" r="11">constexpr std::uint32_t kMaxKotlinStringNestDepth = 128u</d>
<d l="255" n="hasPhantomScopeSeparator" p="src/ingest_names.h" cx="2" ccx="1" in="2" churn="43" amp="143" tested="1" r="12">inline bool hasPhantomScopeSeparator( TSNode qualified ) noexcept</d>
<d l="2115" n="collectGatedLocalNames" sc="rw" p="src/ingest_astquery.h" cx="6" ccx="5" in="1" churn="41" amp="134" r="13">std::vector&lt;LocalNameFact&gt; collectGatedLocalNames( std::string_view defBytes, std::uint32_t defStartLine, Lang lang )</d>
<d l="881" n="scanModule" sc="detail" p="src/jsrunner.h" cx="16" ccx="15" in="3" churn="17" amp="81" r="14">inline ModuleScan scanModule( std::string_view source, std::string_view path )</d>
<d l="708" n="builtInLintCaptures" p="src/verbs_lint.h" cx="1" in="1" churn="30" amp="118" r="15">std::vector&lt;std::vector&lt;rw::AstMatch&gt;&gt; builtInLintCaptures( const rw::IngestResult&amp; ing, const std::vector&lt;rw::AstQuerySpec&gt;&amp; checks, std::vector&lt;std::string&gt;&amp; keptBy … [line truncated: 9 more bytes on this line]
<d l="683" n="jsonNestsTooDeep" p="src/ingest_crawl.h" cx="13" ccx="20" in="1" churn="66" amp="192" tested="1" r="16">bool jsonNestsTooDeep( std::string_view bytes ) noexcept</d>
<d l="104" n="kMaxYamlNestDepth" sc="rw" p="src/ingest.h" churn="57" amp="162" pure="1" r="17">constexpr std::uint32_t kMaxYamlNestDepth = 64u</d>
<d l="1812" n="spanTiersOfFiles" sc="rw" p="src/ingest_astquery.h" cx="28" ccx="55" in="1" churn="41" amp="134" r="18">SpanTierBatch spanTiersOfFiles( std::span&lt;const std::string&gt; diskPaths, bool useMemo )</d>
<d l="87" n="hasMainGuard" sc="rw::pythonrunner" p="src/pythonrunner.h" cx="2" ccx="2" in="1" churn="5" amp="14" r="19">inline bool hasMainGuard( std::string_view source )</d>
<d l="351" n="runParseWorker" p="src/ingest_parsepool.h" cx="50" ccx="116" in="1" churn="47" amp="125" tested="1" r="20">inline void runParseWorker( ParsePoolShared&amp; sh, unsigned t )</d>
<d l="2599" n="sliceScanDefinition" sc="slicev" p="src/slice.h" cx="12" ccx="11" in="3" churn="51" amp="105" r="21">inline SliceScan sliceScanDefinition( const std::string&amp; src, const Symbol&amp; sym, SliceFam fam, const ::TSLanguage* grammar, std::string_view varName )</d>
<d l="48" n="LintRule" sc="LintRule" p="src/lintrules.h" churn="49" amp="134" r="22">struct LintRule</d>
<d l="326" n="DisclosureWhy" sc="SliceScan" p="src/slice.h" churn="51" amp="102" r="23">enum class DisclosureWhy : std::uint8_t</d>
<d l="2558" n="buildMemoryStopAttr" sc="rw" p="src/serialize.h" cx="7" ccx="8" in="2" churn="249" amp="389" r="24">inline std::string buildMemoryStopAttr( const IngestResult&amp; ing, bool json )</d>
… [55 more display lines; full output is 8943 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --for="why does src/lexical.h chooseForRanker pick name-exact BM25"`

*Mention anchoring (default-on): a path and a Symbol literally named in the task get lifted; the header says what anchored.*

`````
<ctx task="why does src/lexical.h chooseForRanker pick name-exact BM25" route="subtoken+body" root="." confidence="high" margin_pct="22" at="c7920353a" mention_anchored="3" doc_mentions="4" schema="ripwire.for/v1" bundle="compact" bodies="0" reason="compact-route" budget_bytes="7500" doc_mentions_ca … [line truncated: 50 more bytes on this line]
<!-- ripwire for schema=ripwire.for/v1: bundle=/bodies=/reason= the body posture; d: cx= ccx= complexity, in= callers (absent cx/ccx/in = 0), churn= amp= change, clone= tested= 1, sc= scope, id=p::sc::n; total= shown= capped=1 if cut; task= the query; d pure=1 const/constexpr sig, next= the follow-up to paste; route= name-exact(X)|subtoken+body[:broad|:declined]; confidence=/margin_pct= head score drop (low=flat); h l= p= n=, c n= l= (joined for same-named callees, shown= counts them), noedge= no callee resolved; t p= file outside sigs (weaker), r= rank (gap = trimmed); field name= type= owner= rel=: a member of owner=, rel=creates held by value, uses by reference/pointer; iface implementors=N: types implementing it, m= its method contract; d layer=: built-in arch layer (game|infra|render|math|audio|ai|test) from a dir name in p= [mention anchor: 1 file + 2 symbols; mention_anchored=] [doc mentions: 4 docs, 2 symbols; doc_mentions=] -->
<!-- root= is the crawl root; p= below is RELATIVE to it (single-root only; absent => p= is ingest's own path, unchanged); at=this commit(+dirty). dropped_positive="14" [budget_bytes= is the default BYTE ceiling this ranked payload was shaped against; it bounds that payload, not the whole document est_tokens prices] [docs_dropped=N: N shown rows have a doc comment not printed (r>24 always, r5..24 if capped)] [cut: doc_mentions_capped="1" doc_mentions_total="7" — an indexing cap dropped content not shown here] est_tokens= prices this bundle in tokens -->
<sigs shown="26" total="40" capped="1" docs_dropped="15">
<d l="1769" n="lexicalScoresNameExactRanked" sc="rw" p="src/lexical.h" cx="1" in="4" churn="62" amp="119" r="1" next="--expand=src/lexical.h:lexicalScoresNameExactRanked">
<doc>The name-exact ranker AS THE RETRIEVAL LENS SERVES IT: whole-name BM25 plus the definition-over-…</doc>inline std::vector&lt;float&gt; lexicalScoresNameExactRanked( const IngestResult&amp; ing, std::string_view query, const std::vector&lt;float&gt;* symbolScoreMul )</d>
<d l="158" n="printEvalRankerNote" sc="rw" p="src/eval.h" cx="1" in="1" churn="16" amp="29" r="2">
<doc>P11.12: the interpretive footer for --eval&apos;s ranker table, pulled into its own function so the 9…</doc>inline void printEvalRankerNote()</d>
<d l="713" n="runEvalRetrieval" sc="rw" p="src/eval.h" cx="7" ccx="10" in="1" churn="16" amp="29" r="3">inline int runEvalRetrieval( const IngestResult&amp; ing, const Graph&amp; g )</d>
<d l="140" n="kWeakLexicalScoreThreshold" sc="rw" p="src/lexical.h" churn="62" amp="115" pure="1" r="4">
<doc>calling agent knows to reformulate rather than trust the ranking. Calibrated empirically (2026-0…</doc>inline constexpr float kWeakLexicalScoreThreshold = 1.0f</d>
<d l="2213" n="chooseForRanker" sc="rw" p="src/lexical.h" cx="18" ccx="23" in="7" churn="62" amp="122" r="5">inline RouteChoice chooseForRanker( const IngestResult&amp; ing, std::string_view query )</d>
<d l="5310" n="candidatesRootTag" sc="rw" p="src/serialize.h" cx="5" ccx="4" in="1" churn="249" amp="388" r="6">inline std::string candidatesRootTag( std::size_t keep, std::size_t corpusCount, const CandidateProvenance&amp; prov )</d>
<d l="1472" n="lexicalScoresNameExactTiered" sc="rw" p="src/lexical.h" cx="38" ccx="65" in="2" churn="62" amp="117" r="7">inline std::vector&lt;float&gt; lexicalScoresNameExactTiered( const IngestResult&amp; ing, std::string_view query, const std::vector&lt;float&gt;* symbolScoreMul )</d>
<d l="687" n="runEvalSkills" sc="rw" p="src/skilleval.h" cx="56" ccx="97" in="1" churn="19" amp="75" r="8">inline int runEvalSkills( const std::string&amp; root, const IngestResult&amp; ing, const Graph&amp; g, const std::string&amp; labelsPath )</d>
<d l="1086" n="runEvalMined" sc="rw" p="src/eval.h" cx="25" ccx="38" in="1" churn="16" amp="29" r="9">inline int runEvalMined( const std::string&amp; root, const IngestResult&amp; ing, const Graph&amp; g, const std::string&amp; path )</d>
<d l="792" n="NameCorpusStats" sc="NameCorpusStats" p="src/naminglens.h" churn="18" amp="44" r="10">struct NameCorpusStats</d>
<d l="47" n="LensRanking" sc="LensRanking" p="src/packtask.h" churn="81" amp="188" r="11">struct LensRanking</d>
<d l="47" n="hasIdentifierShape" sc="namesplit" p="src/infra/namesplit.h" layer="infra" cx="8" ccx="7" in="3" churn="9" amp="38" r="12">inline bool hasIdentifierShape( std::string_view w ) noexcept</d>
<d l="171" n="runEval" sc="rw" p="src/eval.h" cx="44" ccx="66" in="1" churn="16" amp="29" r="13">inline int runEval( const std::string&amp; root, const IngestResult&amp; ing, const Graph&amp; g, const std::vector&lt;char&gt;&amp; currentDiff )</d>
<d l="158" n="Bm25Params" sc="Bm25Params" p="src/lexical.h" churn="62" amp="115" r="14">struct Bm25Params</d>
<d l="222" n="bm25ImpactBound" sc="rw" p="src/lexical.h" cx="1" in="1" churn="62" amp="116" r="15">inline double bm25ImpactBound( double idf, double T, const Bm25Params&amp; p ) noexcept</d>
<d l="4149" n="packTaskText" sc="rw" p="src/mcpverbs.h" cx="25" ccx="33" in="1" churn="309" amp="406" r="16">inline std::string packTaskText( const std::string&amp; root, const std::string&amp; task, std::size_t budgetTokens, RedactCounts* redact = nullptr, std::uint32_t partitionCount = 0, bool noR … [line truncated: 18 more bytes on this line]
<d l="78" n="computeLensRanking" p="src/verbs_for.h" cx="50" ccx="81" in="3" churn="103" amp="202" r="17">rw::LensRanking computeLensRanking( const MainDispatch&amp; d, std::string_view task, bool compactCandidate = false, bool fullDistribution = false ) // deep-tail: the file-grain tail reads the W … [line truncated: 57 more bytes on this line]
<d l="5289" n="CandidateProvenance" sc="CandidateProvenance" p="src/serialize.h" churn="249" amp="387" r="18">struct CandidateProvenance</d>
<d l="609" n="runEvalViews" p="src/main.cpp" cx="5" ccx="4" in="1" churn="414" amp="516" r="19">std::optional&lt;int&gt; runEvalViews( const MainDispatch&amp; d )</d>
<d l="31" n="kLexWeightDoc" sc="rw" p="src/lexindex.h" churn="9" amp="13" pure="1" r="20">inline constexpr int kLexWeightDoc = 2</d>
<d l="329" n="takeQualifiedIdent" sc="layout" p="src/layout.h" cx="9" ccx="8" in="6" churn="30" amp="119" r="21">inline std::string_view takeQualifiedIdent( std::string_view src, std::size_t&amp; i )</d>
<d l="839" n="RecallSectionPick" sc="RecallSectionPick" p="src/recall.h" churn="27" amp="72" r="22">struct RecallSectionPick</d>
<d l="1628" n="lexicalScoresNameExact" sc="rw" p="src/lexical.h" cx="1" in="3" churn="62" amp="118" r="23">inline std::vector&lt;float&gt; lexicalScoresNameExact( const IngestResult&amp; ing, std::string_view query )</d>
… [55 more display lines; full output is 9161 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --for="why does src/lexical.h chooseForRanker pick name-exact BM25" --no-mention-boost`

*Same task with the anchor disabled — the contrast the flag exists for.*

`````
<ctx task="why does src/lexical.h chooseForRanker pick name-exact BM25" route="subtoken+body" root="." confidence="low" margin_pct="0" at="c7920353a" doc_mentions="2" schema="ripwire.for/v1" bundle="compact" bodies="0" reason="compact-route" budget_bytes="7500" doc_mentions_capped="1" doc_mentions_t … [line truncated: 27 more bytes on this line]
<!-- ripwire for schema=ripwire.for/v1: bundle=/bodies=/reason= the body posture; d: cx= ccx= complexity, in= callers (absent cx/ccx/in = 0), churn= amp= change, clone= tested= 1, sc= scope, id=p::sc::n; total= shown= capped=1 if cut; task= the query; d pure=1 const/constexpr sig, next= the follow-up to paste; route= name-exact(X)|subtoken+body[:broad|:declined]; confidence=/margin_pct= head score drop (low=flat); h l= p= n=, c n= l= (joined for same-named callees, shown= counts them), noedge= no callee resolved; t p= file outside sigs (weaker), r= rank (gap = trimmed); field name= type= owner= rel=: a member of owner=, rel=creates held by value, uses by reference/pointer; iface implementors=N: types implementing it, m= its method contract; d layer=: built-in arch layer (game|infra|render|math|audio|ai|test) from a dir name in p= [doc mentions: 2 docs, 1 symbol; doc_mentions=] -->
<!-- root= is the crawl root; p= below is RELATIVE to it (single-root only; absent => p= is ingest's own path, unchanged); at=this commit(+dirty). dropped_positive="11" [budget_bytes= is the default BYTE ceiling this ranked payload was shaped against; it bounds that payload, not the whole document est_tokens prices] [docs_dropped=N: N shown rows have a doc comment not printed (r>24 always, r5..24 if capped)] [cut: doc_mentions_capped="1" doc_mentions_total="3" — an indexing cap dropped content not shown here] est_tokens= prices this bundle in tokens -->
<sigs shown="29" total="40" capped="1" docs_dropped="20">
<d l="1769" n="lexicalScoresNameExactRanked" sc="rw" p="src/lexical.h" cx="1" in="4" churn="62" amp="119" r="1" next="--expand=src/lexical.h:lexicalScoresNameExactRanked">
<doc>The name-exact ranker AS THE RETRIEVAL LENS SERVES IT: whole-name BM25 plus the definition-over-…</doc>inline std::vector&lt;float&gt; lexicalScoresNameExactRanked( const IngestResult&amp; ing, std::string_view query, const std::vector&lt;float&gt;* symbolScoreMul )</d>
<d l="158" n="printEvalRankerNote" sc="rw" p="src/eval.h" cx="1" in="1" churn="16" amp="29" r="2">
<doc>P11.12: the interpretive footer for --eval&apos;s ranker table, pulled into its own function so the 9…</doc>inline void printEvalRankerNote()</d>
<d l="713" n="runEvalRetrieval" sc="rw" p="src/eval.h" cx="7" ccx="10" in="1" churn="16" amp="29" r="3">inline int runEvalRetrieval( const IngestResult&amp; ing, const Graph&amp; g )</d>
<d l="140" n="kWeakLexicalScoreThreshold" sc="rw" p="src/lexical.h" churn="62" amp="115" pure="1" r="4">
<doc>calling agent knows to reformulate rather than trust the ranking. Calibrated empirically (2026-0…</doc>inline constexpr float kWeakLexicalScoreThreshold = 1.0f</d>
<d l="5310" n="candidatesRootTag" sc="rw" p="src/serialize.h" cx="5" ccx="4" in="1" churn="249" amp="388" r="5">inline std::string candidatesRootTag( std::size_t keep, std::size_t corpusCount, const CandidateProvenance&amp; prov )</d>
<d l="1472" n="lexicalScoresNameExactTiered" sc="rw" p="src/lexical.h" cx="38" ccx="65" in="2" churn="62" amp="117" r="6">inline std::vector&lt;float&gt; lexicalScoresNameExactTiered( const IngestResult&amp; ing, std::string_view query, const std::vector&lt;float&gt;* symbolScoreMul )</d>
<d l="687" n="runEvalSkills" sc="rw" p="src/skilleval.h" cx="56" ccx="97" in="1" churn="19" amp="75" r="7">inline int runEvalSkills( const std::string&amp; root, const IngestResult&amp; ing, const Graph&amp; g, const std::string&amp; labelsPath )</d>
<d l="1086" n="runEvalMined" sc="rw" p="src/eval.h" cx="25" ccx="38" in="1" churn="16" amp="29" r="8">inline int runEvalMined( const std::string&amp; root, const IngestResult&amp; ing, const Graph&amp; g, const std::string&amp; path )</d>
<d l="792" n="NameCorpusStats" sc="NameCorpusStats" p="src/naminglens.h" churn="18" amp="44" r="9">struct NameCorpusStats</d>
<d l="47" n="LensRanking" sc="LensRanking" p="src/packtask.h" churn="81" amp="188" r="10">struct LensRanking</d>
<d l="47" n="hasIdentifierShape" sc="namesplit" p="src/infra/namesplit.h" layer="infra" cx="8" ccx="7" in="3" churn="9" amp="38" r="11">inline bool hasIdentifierShape( std::string_view w ) noexcept</d>
<d l="2213" n="chooseForRanker" sc="rw" p="src/lexical.h" cx="18" ccx="23" in="7" churn="62" amp="122" r="12">inline RouteChoice chooseForRanker( const IngestResult&amp; ing, std::string_view query )</d>
<d l="171" n="runEval" sc="rw" p="src/eval.h" cx="44" ccx="66" in="1" churn="16" amp="29" r="13">inline int runEval( const std::string&amp; root, const IngestResult&amp; ing, const Graph&amp; g, const std::vector&lt;char&gt;&amp; currentDiff )</d>
<d l="158" n="Bm25Params" sc="Bm25Params" p="src/lexical.h" churn="62" amp="115" r="14">struct Bm25Params</d>
<d l="222" n="bm25ImpactBound" sc="rw" p="src/lexical.h" cx="1" in="1" churn="62" amp="116" r="15">inline double bm25ImpactBound( double idf, double T, const Bm25Params&amp; p ) noexcept</d>
<d l="4149" n="packTaskText" sc="rw" p="src/mcpverbs.h" cx="25" ccx="33" in="1" churn="309" amp="406" r="16">inline std::string packTaskText( const std::string&amp; root, const std::string&amp; task, std::size_t budgetTokens, RedactCounts* redact = nullptr, std::uint32_t partitionCount = 0, bool noR … [line truncated: 18 more bytes on this line]
<d l="78" n="computeLensRanking" p="src/verbs_for.h" cx="50" ccx="81" in="3" churn="103" amp="202" r="17">rw::LensRanking computeLensRanking( const MainDispatch&amp; d, std::string_view task, bool compactCandidate = false, bool fullDistribution = false ) // deep-tail: the file-grain tail reads the W … [line truncated: 57 more bytes on this line]
<d l="5289" n="CandidateProvenance" sc="CandidateProvenance" p="src/serialize.h" churn="249" amp="387" r="18">struct CandidateProvenance</d>
<d l="609" n="runEvalViews" p="src/main.cpp" cx="5" ccx="4" in="1" churn="414" amp="516" r="19">std::optional&lt;int&gt; runEvalViews( const MainDispatch&amp; d )</d>
<d l="31" n="kLexWeightDoc" sc="rw" p="src/lexindex.h" churn="9" amp="13" pure="1" r="20">inline constexpr int kLexWeightDoc = 2</d>
<d l="329" n="takeQualifiedIdent" sc="layout" p="src/layout.h" cx="9" ccx="8" in="6" churn="30" amp="119" r="21">inline std::string_view takeQualifiedIdent( std::string_view src, std::size_t&amp; i )</d>
<d l="839" n="RecallSectionPick" sc="RecallSectionPick" p="src/recall.h" churn="27" amp="72" r="22">struct RecallSectionPick</d>
<d l="1628" n="lexicalScoresNameExact" sc="rw" p="src/lexical.h" cx="1" in="3" churn="62" amp="118" r="23">inline std::vector&lt;float&gt; lexicalScoresNameExact( const IngestResult&amp; ing, std::string_view query )</d>
… [58 more display lines; full output is 9391 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --lego=Vehicle`

*Interface -> implementors view: every existing impl of the named interface; the method contract is extracted for the C-family/Java/TS/Python tiers — for a Rust trait (this fixture) it discloses caveat="not-extracted-for-lang" rather than an empty list.*

`````
<ctx schema="ripwire.lego/v1" root=".">
<!-- ripwire lego schema=ripwire.lego/v1: ONE interface/base type: <iface n= p= defs= implementors=>, its <m> method contract, every implementor. counts_floor=1: every count is a FLOOR, never a total. graph_ambiguous=/graph_unresolved=: resolver gauge. graph_unindexed=N: N files no grammar could read (the map header's unindexed=); their calls raise neither gauge. root=: p= relative to it. methods=0 caveat=not-extracted-for-lang: no <m> contract read for this language. -->
<lego graph_ambiguous="10278" graph_unresolved="12878" graph_unindexed="237" counts_floor="1">
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
<!-- ripwire exemplar schema=ripwire.exemplar/v1: the best-in-class instance of kind= for the task, chosen by role: n= p= in= ccx= tested=, <bodies>
<b> to imitate. window: shown= total= capped= (capped=1 cut). root=: p= relative to it. candidates=N: instances of kind= under the ccx ceiling the pick was ranked from. low_confidence=1: weak task-to-kind match, fell back to fn; pass a kind (fn|method|class...) instead. -->
<exemplar schema="ripwire.exemplar/v1" kind="fn" candidates="11699" n="emitTo" p="src/infra/emit.h:78" in="279" ccx="2" root="." tested="1" low_confidence="1">
<bodies shown="1" total="1" capped="0">
<b t="fn" l="78" p="src/infra/emit.h" n="emitTo">
<![CDATA[inline void emitTo( std::FILE* stream, std::format_string<A...> f, A&&... a )
{
    // A fixed char[] must arrive as rw::cstr( buf ). printf's %s always meant "bytes to the first NUL";
    // `{}` on a char[N] is a different question that library versions answer differently, and an
    // implementation that formats the ARRAY emits the trailing NUL and the uninitialised bytes after it.
    // A regex sweep missed sites twice, so the compiler enforces it instead of a reviewer.
    // Only a MUTABLE char[N] is rejected. A string literal is const char[N]; every implementation formats
    // that as a string, and the hazard here is the reusable buffer that was written short.
    static_assert( ( ... && !( std::is_array_v<std::remove_reference_t<A>>
                               && !std::is_const_v<std::remove_extent_t<std::remove_reference_t<A>>> ) ),
                   "pass rw::cstr( buf ) for a fixed char buffer: {} on a char[N] is not printf's %s" );
    std::fputs( std::format( f, std::forward<A>( a )... ).c_str(), stream );
}]]><calls total="1"><c n="c_str" l="484">[[nodiscard]] const char16_t* c_str() const noexcept</c></calls></b></bodies></exemplar>
`````

## `./build/ripwire . --help-task="calls(runDefaultMap, rankGraphTeleport)"`

*Deterministic enhanced help: a closed claim in the task is a structured shape, so the router recommends the ONE command that answers it (--verify) with the evidence behind the pick. Advice only — nothing executes.*

`````
<!-- ripwire help-task schema=ripwire.help-task/v1: which verb answers this task: status=recommend|abstain confidence= score= margin=, <facts> the evidence. choice intent= skill= reason=: the route matched, the skill owning it, the evidence in words. git=/dirty=: the root is a git repo / its tree differs from HEAD (the stamp's +dirty). trace=1: the task text has a stack/sanitizer trace shape; it routes to from-trace. resolved_symbols=N: indexed names the task NAMES; a bare short/common word needs backticks or F(). -->
<task-route schema="ripwire.help-task/v1" status="recommend" confidence="high" score="100" margin="100">
<facts git="1" dirty="0" trace="0" resolved_symbols="2"/>
<choice intent="verify-claim" skill="ripwire-navigate" reason="closed claim grammar" score="100">
<run>ripwire &apos;.&apos; --verify=&apos;calls(runDefaultMap, rankGraphTeleport)&apos;</run>
</choice>
</task-route>
`````

## `./build/ripwire . --help-task="write a cheerful release announcement"`

*The honest half of the contract: a task with no ripwire-shaped evidence ABSTAINS with zero commands rather than guessing.*

`````
<!-- ripwire help-task schema=ripwire.help-task/v1: which verb answers this task: status=recommend|abstain confidence= score= margin=, <facts> the evidence. git=/dirty=: the root is a git repo / its tree differs from HEAD (the stamp's +dirty). trace=1: the task text has a stack/sanitizer trace shape; it routes to from-trace. resolved_symbols=N: indexed names the task NAMES; a bare short/common word needs backticks or F(). -->
<task-route schema="ripwire.help-task/v1" status="abstain" confidence="none" score="0" margin="0">
<facts git="1" dirty="0" trace="0" resolved_symbols="0"/>
</task-route>
`````

## `./build/ripwire . --recall="quality delta gating exit codes"`

*Most relevant DOCS' full bodies (markdown only) — recall what is already written down.*

`````
ripwire recall — "quality delta gating exit codes" — 113 relevant of 210 document files, best-first — total=113 shown=8 capped=1 truncated=7 generated_demoted=3 max_tokens=8000 share_bytes=2161 est_tokens=5489

━━ README.md  (relevance 7.970) ━━  [sections: 2 of 25 selected (60 in doc), section-granular; whole doc 213934 B; lines="2707-2719,2720-2727"; dropped_by_budget=23]
#### 6.2 Exit codes

This is the part to wire into a script.

| Code | Meaning |
| --- | --- |
| 0 | The command completed. |
| 1 | The command refused the request. A refusal names the reason on stderr. When `--callers`, `--callees`, `--uses`, `--impact` or `--path` refuse a selector that matches no indexed definition, they also print an answer on stdout: the verb's element with `found="0"` and the name to retry with. |
| 2 | A policy gate fired: `--arch` found a layering violation, `--scan-skill` found a CRITICAL, `--quality-delta` found new debt. |
| 3 | The output exceeded the token budget that you set. |
| 4 | `--test-gate` found an open obligation. |
| 5 | The memory guard stopped the run: over `--max-memory` (default 65% of the machine's memory) with no partial answer possible, or a verb other than the default map facing a partial index. One stderr line names the limit and the override. |

#### 6.3 JSON output

`--json` emits JSON instead of XML, with keys mirroring the XML attribute names one to one. It is an
allow-list: the default map, `--for`, `--pack-task`, `--callers`, `--callees`, `--impact`,
`--quality-delta`, `--test-gate`, `--metrics`, and `--plan-lanes`, which is JSON-native. Every other
verb refuses on stderr with exit 1 rather than silently falling back to XML, so a verb added tomorrow
refuses by default.



━━ prompts/help-wanted/quality-delta-unchanged-tree-zero.md  (relevance 7.324) ━━  [sections: 1 of 18 selected (21 in doc), section-granular; whole doc 25463 B; lines="133-158"; dropped_by_budget=17]
### Root spelling (maintainer-owned; reproduce it once so you recognise it)

```bash
… [159 more lines, 14007 bytes total]
`````

## `./build/ripwire <scratch>/aux/kbcorpus --recall="field affinity cache line data layout which fields are read together" --top-k=3 --max-tokens=1200`

*The directory-as-knowledge-base pattern: --recall pointed at a 1411912-byte scratch dir of DUMPED TOOL OUTPUT (a git log, this repo's own generated command reference, --help text, an architecture doc, a fabricated JSON access log) instead of a source repo — no index to build, no daemon.*

`````
ripwire recall — "field affinity cache line data layout which fields are read together" — 2 relevant of 2 document files, best-first — total=2 shown=1 capped=1 truncated=1 max_tokens=1200 share_bytes=2040 est_tokens=952

━━ commands.md  (relevance 11.013) ━━  [sections: 1 of 159 selected (187 in doc), section-granular; whole doc 546809 B; lines="528-553"; dropped_by_budget=158]  [truncated: 1854 of 4293 bytes]
#### Pattern: a directory of dumped tool output as a knowledge base

**Answers:** can `--recall` serve as a zero-setup knowledge base over dumped tool output — a
`git log`, an API response dump, a fetched doc, `<tool> --help` text — sitting in a scratch
directory, instead of a source repo?

Yes, unmodified. `--recall` never distinguishes "a codebase" from any other directory it can
walk: point it at the scratch dir and query it. No index to build, no daemon, no mutable store
between runs — the whole cost is one cold parse. Two conditions decide whether it works at all,
and both are yours, because the file you write is the only thing that sets them:

1. **Dump to `.md`.** `--recall` ranks DOCUMENT files: `.md`, plus the docparse'd
   `.ipynb`/`.html`/`.csv` (and Office/PDF through the optional markitdown bridge). `.txt`,
   `.log`, `.json` and extensionless files are **not** documents to it. A directory of those
   answers `0 relevant of 0 document files` and exits 0 — which reads like "nothing matched
   your terms" when what happened is "nothing was indexed at all". Redirect to `notes.md`,
   never `notes.txt`. The recorded run below is that rule's own demonstration: its scratch dir
   holds five dumps, and the header says `2 relevant of 2 document files` because only the two
   `.md` ones are documents — the `git log`, the `--help` text and the JSON access log are not
   in the population at all.

2. **Keep `##` headings in the dump.** A headed document is served as whole ranked SECTIONS, so
   an answer buried mid-file arrives at a small `--max-tokens`, and — while the served document
   SET stays fixed — a larger ceiling returns a strict superset of it; the `[sections: S of R
   selected (N in doc) … lines="…"; dropped_by_budget=D]` note names the ranges you actually got
   and what the ceiling cost. …

(capped: 1 of 2 relevant document files omitted — raise --max-tokens/budget_tokens or narrow the query for 1 more (~2548-byte budget))
`````

stderr:

`````
ripwire: redacted 1 secret from emitted context (keyword-gated-secret=1) — pass --no-redact to disable
`````

## `./build/ripwire . --tree`

*File-by-file orientation map (top symbols per file).*

`````
<!-- ripwire tree schema=ripwire.tree/v1: each file with its top 3 symbols by rank, files by best symbol: <file p= symbols=> of <s t= n=>; of files= indexed, files_unlisted= have none. window: shown= total= capped= has_more= next_offset= offset= limit= (capped=1 cut; next_offset= pastes as offset=). symbols_capped=: 1 = cut. root=: p= relative to it. pr_iters=N: PageRank iterations. shown_symbols=: <s> rows printed. next=: the one pasteable follow-up. -->
<tree schema="ripwire.tree/v1" files="2484" files_unlisted="66" shown="80" capped="1" total="2418" has_more="1" next_offset="80" offset="0" limit="0" pr_iters="28" root="." shown_symbols="233" symbols_capped="1" next="--tree --offset=80">
<file p="src/infra/svector.h" symbols="68">
<s t="method" n="buf"/>
<s t="method" n="buf"/>
<s t="method" n="push_back"/>
</file>
<file p="src/resolve.h" symbols="316">
<s t="method" n="empty"/>
<s t="method" n="string"/>
<s t="method" n="unescape"/>
</file>
<file p="src/infra/os_win32_logic.h" symbols="94">
<s t="method" n="ok"/>
<s t="method" n="size"/>
<s t="method" n="c_str"/>
</file>
<file p="src/notes.h" symbols="34">
<s t="method" n="empty"/>
<s t="method" n="find"/>
<s t="fn" n="sortNotes"/>
</file>
<file p="src/scipoverlay.h" symbols="9">
<s t="method" n="empty"/>
<s t="method" n="targetsOf"/>
<s t="method" n="isPrecise"/>
</file>
<file p="src/ingest_model.h" symbols="23">
<s t="method" n="find"/>
<s t="method" n="findOwnedDef"/>
… [366 more display lines; full output is 11120 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --html=<scratch>/aux/map2.html`

*Self-contained HTML force-directed call graph.*

**wall time: 1.08s**

`````
(empty)
`````

Artifact written:

`````
  158883 <scratch>/aux/map2.html
`````

## `./build/ripwire . --order=stable --top-k=5`

*Stable (path/id) emit order — provider KV-cache hits across re-runs.*

`````
<!-- ripwire map schema=ripwire.map/v1: ranked symbol map: <f p= layer=> groups <s t= n= sc= k= amb=> rows (k= rank), <c n=> resolved callees; the header comment is data. est_tokens=: price as emitted (an upper bound under compact). root=: p= relative to it. pr_iters=N: PageRank iterations. declined=K: K calls left unbound (no evidence chose one def). external=K: K calls proven outside the tree, no edge. locality_pinned=K: K calls pinned by locality alone (a guess). extent_suspect_syms=K: K defs failed containment, corpus-wide. macro_blanked_files=K: K files indexed from a macro-blanked re-parse. overloads=N: N same-name defs merged in this row; shown= counts each. files=/symbols=: files and symbols indexed; edges= distinct call edges; shown= symbols printed, a merged row counting each def; ambiguous= calls split over several defs, corpus-wide; unresolved= calls with in-tree evidence and no edge (every def language-filtered or unreachable, or binding refused); order= rows by rank (important-first, important-last; (auto:fill) = flipped past a size threshold) or by path (stable). skipped_oversize=K: K files over a size ceiling, not indexed. unindexed=ext:N: N text files of that extension no grammar reads (6 extensions at most). unindexed_exts=E: E such extensions in all, the list cut. lens=: attributes another form of this answer serves, withheld here. sc=: enclosing scope; the full id is p::sc::n (p= of the row or its <f>) and selectors take it. -->
<!-- t=modscope=a-file's-MODULE-SCOPE(n=<file-scope>):the-statements-outside-every-named-definition,where-a-top-level-call-and-an-anonymous-callback-body's-calls-live;a-CALLER-never-a-callee(nothing-in-the-source-can-name-it)-with-no-body-to-expand;a-file-with-no-such-call-has-no-such-row -->
<r schema="ripwire.map/v1" root="." pr_iters="28" lens="k,est_tokens">
<f p="src/infra/os_win32_logic.h" layer="infra">
<s t="method" n="ok" sc="WidePath">
</s>
</f>
<f p="src/infra/svector.h" layer="infra">
<s t="method" n="buf" sc="svector" overloads="2">
</s>
</f>
<f p="src/notes.h">
<s t="method" n="empty" sc="NoteIndex">
</s>
</f>
<f p="src/resolve.h">
<s t="method" n="empty" sc="RubyConstantIndex">
</s>
</f>
</r>
<!-- files=2484 symbols=23851 edges=34236 shown=5 est_tokens=996 ambiguous=10278 unresolved=12878 locality_pinned=12 external=7345 declined=9922 extent_suspect_syms=10 macro_blanked_files=7 skipped_oversize=15 unindexed="txt:73,tsv:49,jsonl:26,scm:23,expected:15,xml:13" unindexed_exts=20 order=stable -->
`````


---

# navigate / answer a question

## `./build/ripwire . --around=rankGraphTeleport`

*Ego graph around one symbol — depth 1 BY DEFAULT now (the root's depth= says so): ~6 KB where the 2-hop neighbourhood is ~64 KB on this repo.*

`````
<!-- ripwire around schema=ripwire.around/v1: call neighbourhood of of=: depth= hops, fanout= kept per hop; absent rows lie outside that boundary. est_tokens=: price as emitted (an upper bound under compact). root=: p= relative to it. declined=K: K calls left unbound (no evidence chose one def). external=K: K calls proven outside the tree, no edge. locality_pinned=K: K calls pinned by locality alone (a guess). extent_suspect_syms=K: K defs failed containment, corpus-wide. macro_blanked_files=K: K files indexed from a macro-blanked re-parse. overloads=N: N same-name defs merged in this row; shown= counts each. prov=scip|binding|import|split|final-segment: how that <c> edge bound (absent: one unique name); split = one arm of an amb= pick; final-segment = a qualified type matched by last name only. files=/symbols=: files and symbols indexed; edges= distinct call edges; shown= symbols printed, a merged row counting each def; ambiguous= calls split over several defs, corpus-wide; unresolved= calls with in-tree evidence and no edge (every def language-filtered or unreachable, or binding refused); order= rows by rank (important-first, important-last; (auto:fill) = flipped past a size threshold) or by path (stable). skipped_oversize=K: K files over a size ceiling, not indexed. unindexed=ext:N: N text files of that extension no grammar reads (6 extensions at most). unindexed_exts=E: E such extensions in all, the list cut. sc=: enclosing scope; the full id is p::sc::n (p= of the row or its <f>) and selectors take it. amb=K: K calls split over several defs. layer=: built-in arch layer (game|infra|render|math|audio|ai|test) from a dir name in p=; absent if none. -->
<!-- t=modscope=a-file's-MODULE-SCOPE(n=<file-scope>):the-statements-outside-every-named-definition,where-a-top-level-call-and-an-anonymous-callback-body's-calls-live;a-CALLER-never-a-callee(nothing-in-the-source-can-name-it)-with-no-body-to-expand;a-file-with-no-such-call-has-no-such-row -->
<!-- a bound BIT this walk, so raising it would return more: depth_truncated=1 means at least one symbol one hop past depth= is absent; fanout_cut=N means N distinct symbols were dropped by the fanout= cap and appear NOWHERE here (exact, not a floor: a neighbour another hub re-admitted is not counted). Neither attribute is emitted when its bound cut nothing, so absent means that bound did not bind and raising it returns nothing new. The knobs are around-depth=N and around-fanout=K. -->
<!-- files=2484 symbols=23851 edges=34236 shown=16 est_tokens=3695 ambiguous=10278 unresolved=12878 locality_pinned=12 external=7345 declined=9922 extent_suspect_syms=10 macro_blanked_files=7 skipped_oversize=15 unindexed="txt:73,tsv:49,jsonl:26,scm:23,expected:15,xml:13" unindexed_exts=20 order=important-first -->
<r schema="ripwire.around/v1" root="." of="rankGraphTeleport" depth="1" fanout="32" depth_truncated="1" est_tokens="3695">
<f p="src/graph.h">
<s t="fn" n="rankGraphTeleport" sc="rw" amb="6" k="1.0000">
<c n="biasPrior"/>
<c n="PROFILE_SCOPE_DESCRIBE" prov="split"/>
<c n="PROFILE_SCOPE_DESCRIBE" prov="split"/>
<c n="begin" prov="split"/>
<c n="end" prov="split"/>
<c n="begin" prov="split"/>
<c n="end" prov="split"/>
<c n="pageRankDouble"/>
</s>
<s t="fn" n="biasPrior" sc="rw" k="0.5000">
<c n="ASSUME_NO_ALIAS_BUF"/>
</s>
<s t="fn" n="rankGraph" sc="rw" k="0.5000">
<c n="rankGraphTeleport"/>
</s>
<s t="fn" n="anchoredLexicalRank" sc="rw" amb="7" k="0.5000">
<c n="rankGraphTeleport"/>
<c n="blendMaxNorm"/>
<c n="ASSUME"/>
<c n="back" prov="split"/>
<c n="back" prov="split"/>
<c n="begin" prov="split"/>
<c n="end" prov="split"/>
… [225 more display lines; full output is 9149 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --around=rankGraphTeleport --around-depth=2`

*The restoring knob: --around-depth=2 brings back the whole 2-hop neighbourhood (depth="2" on the root) — pay for it only when the 1-hop view was not enough.*

`````
<!-- ripwire around schema=ripwire.around/v1: call neighbourhood of of=: depth= hops, fanout= kept per hop; absent rows lie outside that boundary. est_tokens=: price as emitted (an upper bound under compact). root=: p= relative to it. declined=K: K calls left unbound (no evidence chose one def). external=K: K calls proven outside the tree, no edge. locality_pinned=K: K calls pinned by locality alone (a guess). extent_suspect_syms=K: K defs failed containment, corpus-wide. macro_blanked_files=K: K files indexed from a macro-blanked re-parse. lpin=K: K calls pinned by locality alone (a guess). overloads=N: N same-name defs merged in this row; shown= counts each. prov=scip|binding|import|split|final-segment: how that <c> edge bound (absent: one unique name); split = one arm of an amb= pick; final-segment = a qualified type matched by last name only. files=/symbols=: files and symbols indexed; edges= distinct call edges; shown= symbols printed, a merged row counting each def; ambiguous= calls split over several defs, corpus-wide; unresolved= calls with in-tree evidence and no edge (every def language-filtered or unreachable, or binding refused); order= rows by rank (important-first, important-last; (auto:fill) = flipped past a size threshold) or by path (stable). skipped_oversize=K: K files over a size ceiling, not indexed. unindexed=ext:N: N text files of that extension no grammar reads (6 extensions at most). unindexed_exts=E: E such extensions in all, the list cut. sc=: enclosing scope; the full id is p::sc::n (p= of the row or its <f>) and selectors take it. amb=K: K calls split over several defs. layer=: built-in arch layer (game|infra|render|math|audio|ai|test) from a dir name in p=; absent if none. -->
<!-- t=modscope=a-file's-MODULE-SCOPE(n=<file-scope>):the-statements-outside-every-named-definition,where-a-top-level-call-and-an-anonymous-callback-body's-calls-live;a-CALLER-never-a-callee(nothing-in-the-source-can-name-it)-with-no-body-to-expand;a-file-with-no-such-call-has-no-such-row -->
<!-- a bound BIT this walk, so raising it would return more: depth_truncated=1 means at least one symbol one hop past depth= is absent; fanout_cut=N means N distinct symbols were dropped by the fanout= cap and appear NOWHERE here (exact, not a floor: a neighbour another hub re-admitted is not counted). Neither attribute is emitted when its bound cut nothing, so absent means that bound did not bind and raising it returns nothing new. The knobs are around-depth=N and around-fanout=K. -->
<!-- files=2484 symbols=23851 edges=34236 shown=208 est_tokens=31988 ambiguous=10278 unresolved=12878 locality_pinned=12 external=7345 declined=9922 extent_suspect_syms=10 macro_blanked_files=7 skipped_oversize=15 unindexed="txt:73,tsv:49,jsonl:26,scm:23,expected:15,xml:13" unindexed_exts=20 order=important-first -->
<r schema="ripwire.around/v1" root="." of="rankGraphTeleport" depth="2" fanout="32" depth_truncated="1" fanout_cut="443" est_tokens="31988">
<f p="src/graph.h">
<s t="fn" n="rankGraphTeleport" sc="rw" amb="6" k="1.0000">
<c n="biasPrior"/>
<c n="PROFILE_SCOPE_DESCRIBE" prov="split"/>
<c n="PROFILE_SCOPE_DESCRIBE" prov="split"/>
<c n="begin" prov="split"/>
<c n="end" prov="split"/>
<c n="begin" prov="split"/>
<c n="end" prov="split"/>
<c n="pageRankDouble"/>
</s>
<s t="fn" n="biasPrior" sc="rw" k="0.5000">
<c n="ASSUME_NO_ALIAS_BUF"/>
</s>
<s t="fn" n="rankGraph" sc="rw" k="0.5000">
<c n="rankGraphTeleport"/>
</s>
<s t="fn" n="anchoredLexicalRank" sc="rw" amb="7" k="0.5000">
<c n="rankGraphTeleport"/>
<c n="blendMaxNorm"/>
<c n="ASSUME"/>
<c n="back" prov="split"/>
<c n="back" prov="split"/>
<c n="begin" prov="split"/>
<c n="end" prov="split"/>
… [2996 more display lines; full output is 79305 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --around=rankGraphTeleport --around-fanout=4`

*The other knob: --around-fanout=4 keeps only the 4 strongest edges per node (default 32) — the same 1-hop depth, a quarter of the rows.*

`````
<!-- ripwire around schema=ripwire.around/v1: call neighbourhood of of=: depth= hops, fanout= kept per hop; absent rows lie outside that boundary. est_tokens=: price as emitted (an upper bound under compact). root=: p= relative to it. declined=K: K calls left unbound (no evidence chose one def). external=K: K calls proven outside the tree, no edge. locality_pinned=K: K calls pinned by locality alone (a guess). extent_suspect_syms=K: K defs failed containment, corpus-wide. macro_blanked_files=K: K files indexed from a macro-blanked re-parse. prov=scip|binding|import|split|final-segment: how that <c> edge bound (absent: one unique name); split = one arm of an amb= pick; final-segment = a qualified type matched by last name only. files=/symbols=: files and symbols indexed; edges= distinct call edges; shown= symbols printed, a merged row counting each def; ambiguous= calls split over several defs, corpus-wide; unresolved= calls with in-tree evidence and no edge (every def language-filtered or unreachable, or binding refused); order= rows by rank (important-first, important-last; (auto:fill) = flipped past a size threshold) or by path (stable). skipped_oversize=K: K files over a size ceiling, not indexed. unindexed=ext:N: N text files of that extension no grammar reads (6 extensions at most). unindexed_exts=E: E such extensions in all, the list cut. sc=: enclosing scope; the full id is p::sc::n (p= of the row or its <f>) and selectors take it. amb=K: K calls split over several defs. -->
<!-- t=modscope=a-file's-MODULE-SCOPE(n=<file-scope>):the-statements-outside-every-named-definition,where-a-top-level-call-and-an-anonymous-callback-body's-calls-live;a-CALLER-never-a-callee(nothing-in-the-source-can-name-it)-with-no-body-to-expand;a-file-with-no-such-call-has-no-such-row -->
<!-- a bound BIT this walk, so raising it would return more: depth_truncated=1 means at least one symbol one hop past depth= is absent; fanout_cut=N means N distinct symbols were dropped by the fanout= cap and appear NOWHERE here (exact, not a floor: a neighbour another hub re-admitted is not counted). Neither attribute is emitted when its bound cut nothing, so absent means that bound did not bind and raising it returns nothing new. The knobs are around-depth=N and around-fanout=K. -->
<!-- files=2484 symbols=23851 edges=34236 shown=5 est_tokens=1683 ambiguous=10278 unresolved=12878 locality_pinned=12 external=7345 declined=9922 extent_suspect_syms=10 macro_blanked_files=7 skipped_oversize=15 unindexed="txt:73,tsv:49,jsonl:26,scm:23,expected:15,xml:13" unindexed_exts=20 order=important-first -->
<r schema="ripwire.around/v1" root="." of="rankGraphTeleport" depth="1" fanout="4" depth_truncated="1" fanout_cut="11" est_tokens="1683">
<f p="src/graph.h">
<s t="fn" n="rankGraphTeleport" sc="rw" amb="6" k="1.0000">
<c n="biasPrior"/>
<c n="PROFILE_SCOPE_DESCRIBE" prov="split"/>
<c n="PROFILE_SCOPE_DESCRIBE" prov="split"/>
<c n="begin" prov="split"/>
<c n="end" prov="split"/>
<c n="begin" prov="split"/>
<c n="end" prov="split"/>
<c n="pageRankDouble"/>
</s>
<s t="fn" n="biasPrior" sc="rw" k="0.5000">
<c n="ASSUME_NO_ALIAS_BUF"/>
</s>
<s t="fn" n="rankGraph" sc="rw" k="0.5000">
<c n="rankGraphTeleport"/>
</s>
<s t="fn" n="anchoredLexicalRank" sc="rw" amb="7" k="0.5000">
<c n="rankGraphTeleport"/>
<c n="blendMaxNorm"/>
<c n="ASSUME"/>
<c n="back" prov="split"/>
<c n="back" prov="split"/>
<c n="begin" prov="split"/>
<c n="end" prov="split"/>
… [31 more display lines; full output is 4174 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --callers=rankGraphTeleport`

*Who calls SYM (1-hop in-edges).*

`````
<!-- ripwire callers schema=ripwire.callers/v1: 1-hop CALLERS of of= (defs= matched, count= distinct symbols): <s t= n= p=>; hop_tested=/hop_untested=. counts_floor=1: every count is a FLOOR, never a total. graph_ambiguous=/graph_unresolved=: resolver gauge. graph_unindexed=N: N files no grammar could read (the map header's unindexed=); their calls raise neither gauge. root=: p= relative to it. next=: the one pasteable follow-up. -->
<callers schema="ripwire.callers/v1" of="rankGraphTeleport" defs="1" count="7" root="." hop_tested="0" hop_untested="7" graph_ambiguous="10278" graph_unresolved="12878" graph_unindexed="237" counts_floor="1" next="--uses=rankGraphTeleport">
<s t="fn" n="getIndex" p="src/mcpindex.h:1165"/>
<s t="fn" n="rankGraph" p="src/graph.h:5606"/>
<s t="fn" n="anchoredLexicalRank" p="src/graph.h:6252"/>
<s t="fn" n="runEval" p="src/eval.h:171"/>
<s t="fn" n="churnDecayRanking" p="src/main.cpp:1380"/>
<s t="fn" n="churnRankedGraph" p="src/main.cpp:1419"/>
<s t="fn" n="runDefaultMap" p="src/main.cpp:1629"/>
</callers>
`````

## `./build/ripwire . --callers=rankGraphTeleport --legend=full`

*The same rows under --legend=full: the default is the compact dialect (one compact comment plus schema="ripwire.callers/v1" on the root), and --legend=full restores the prose legend — every row byte and every completeness attribute (counts_floor=, graph_ambiguous=, next=) identical, ~3 KB more legend. Works on EVERY XML verb.*

`````
<!-- ripwire callers/callees: the 1-hop call hierarchy read off the call graph — the callers form lists symbols that CALL of=; the callees form lists symbols of= itself calls. of= is the selector you passed, defs= how many DEFINITIONS it resolved to (rows UNION every def's neighbours), count= the DISTINCT neighbour symbols (a floor, per counts_floor=), windowed by limit= and offset=. A neighbour that is an indexed function-like #define is a macro row (t="macro", role="macro" on the XML row): the edge crosses a macro expansion, not a plain call — rows carry no role= otherwise. Rows are ordered SOURCE first, then test/bench, then docs; within a tier callers rank by each row's own caller count (most-called first); callees keep path order. hop_tested=/hop_untested= partition count= by the tested= lens below (1-hop, never transitive). tested="1" on a row means an indexed test transitively reaches it (never 0, omitted when it does not). BLIND SPOT the test-gate legend also names: only a CALL EDGE from an INDEXED test symbol counts here, so a shell or CLI-level test running a built binary as a SUBPROCESS is invisible to it and a repo tested that way reads all-untested. Read untested= as no in-process test reaches it, not as no test covers it. next= is the one pasteable follow-up (the uses verb on this selector: the call sites). counts_floor="1" means every count here is a FLOOR, never a total: edges are extracted from source TEXT by NAME. Missing: dynamic dispatch (virtual/interface/duck-typed), a most-vexing-parse declaration with no call expression, a function-pointer/callback bound to more than one function in scope (reassigned, table-indexed, lambda-bound, or address-taken/reference-bound), and a plain-name binding (fp=handler) whose variable type is not PROVABLY a function pointer (a same-file typedef/declarator; a HEADER typedef is missed; auto/template types are read as unpinned, so KEPT). A macro-generated call site is role="macro" only when its name uniquely names an indexed function-like #define (C-family, t="macro"); a shared name stays a plain call, an unindexed macro is no edge. Read a zero as "none found", never as "none exists". graph_ambiguous=/graph_unresolved= are the whole graph's resolver gauge (calls split over several defs / calls whose in-repo defs were all language-filtered), the map header's ambiguous=/unresolved=. graph_unindexed=N is a third gauge: files no grammar could read (the map header's unindexed=), whose calls raise neither gauge above; absent when zero, and so is this sentence. COUNTING UNIT differs by verb: callers, callees, edit-check, graph-query and pr-context counts are DISTINCT SYMBOLS (repeated calls from one caller, and calls to two overloads, collapse into ONE row; multiplicity survives only in the call graph's edge weight). The reach counts (impact's reaches=, pr-context's dependents=) are the size of a transitive reach SET, each symbol counted once. The uses verb counts call SITES, one row per occurrence — a larger count there for the same symbol is these units agreeing, not disagreeing. The map header's edges= is a unit again different — distinct (caller,callee) PAIRS — and that document carries neither this marker nor this clause. -->
<!-- root= on this element is the crawl root every p= below is RELATIVE to (single-root runs only; absent => p= is the path ingest itself used, unchanged). -->
<callers of="rankGraphTeleport" defs="1" count="7" root="." hop_tested="0" hop_untested="7" graph_ambiguous="10278" graph_unresolved="12878" graph_unindexed="237" counts_floor="1" next="--uses=rankGraphTeleport">
<s t="fn" n="getIndex" p="src/mcpindex.h:1165"/>
<s t="fn" n="rankGraph" p="src/graph.h:5606"/>
<s t="fn" n="anchoredLexicalRank" p="src/graph.h:6252"/>
<s t="fn" n="runEval" p="src/eval.h:171"/>
<s t="fn" n="churnDecayRanking" p="src/main.cpp:1380"/>
<s t="fn" n="churnRankedGraph" p="src/main.cpp:1419"/>
<s t="fn" n="runDefaultMap" p="src/main.cpp:1629"/>
</callers>
`````

## `./build/ripwire . --callers=DoesNotExist`

*Unknown-symbol REFUSAL shape (exit 1) with a did-you-mean from real edit distance.*

**exit code: 1**

`````
<!-- ripwire callers schema=ripwire.callers/v1: 1-hop CALLERS of of= (defs= matched, count= distinct symbols): <s t= n= p=>; hop_tested=/hop_untested=. found=0: no indexed definition matched the selector, nothing listed or counted (zero = none found, not none exists); exit stays 1. -->
<callers schema="ripwire.callers/v1" of="DoesNotExist" found="0"/>
`````

stderr:

`````
ripwire: --callers symbol not found: DoesNotExist
`````

## `./build/ripwire . --callees=rankGraphTeleport`

*What SYM calls (1-hop out-edges).*

`````
<!-- ripwire callees schema=ripwire.callees/v1: 1-hop CALLEES of of= (defs= matched, count= distinct symbols): <s t= n= p= role= tested=>. counts_floor=1: every count is a FLOOR, never a total. graph_ambiguous=/graph_unresolved=: resolver gauge. graph_unindexed=N: N files no grammar could read (the map header's unindexed=); their calls raise neither gauge. declined_calls=K: K call sites left unbound (no evidence chose one def), in no count or row. root=: p= relative to it. <s tested=1>: a non-test row an indexed test transitively reaches (absent otherwise, never 0). next=: the one pasteable follow-up. hop_tested=/hop_untested=: count= split by whether an indexed test reaches the row (in-process calls only). -->
<callees schema="ripwire.callees/v1" of="rankGraphTeleport" defs="1" count="8" root="." hop_tested="7" hop_untested="1" declined_calls="1" graph_ambiguous="10278" graph_unresolved="12878" graph_unindexed="237" counts_floor="1" next="--expand=rankGraphTeleport">
<s t="fn" n="biasPrior" p="src/graph.h:5524"/>
<s t="macro" n="PROFILE_SCOPE_DESCRIBE" p="src/infra/profileScope.h:1279" role="macro" tested="1"/>
<s t="macro" n="PROFILE_SCOPE_DESCRIBE" p="src/infra/profileScope.h:1293" role="macro" tested="1"/>
<s t="method" n="begin" p="src/infra/svector.h:269" tested="1"/>
<s t="method" n="end" p="src/infra/svector.h:270" tested="1"/>
<s t="method" n="begin" p="src/infra/svector.h:271" tested="1"/>
<s t="method" n="end" p="src/infra/svector.h:272" tested="1"/>
<s t="fn" n="pageRankDouble" p="src/pagerank.cpp:99" tested="1"/>
</callees>
`````

## `./build/ripwire . --uses=rankGraphTeleport`

*The resolvable use-sites (call/read/write/import/extends) with file:line; count= is a floor.*

`````
<!-- ripwire uses schema=ripwire.uses/v1: resolvable use-sites of of=: <u role=call|macro|read|write|import|extends|type p=file:line in_id=>. counts_floor=1: every count is a FLOOR, never a total. graph_ambiguous=/graph_unresolved=: resolver gauge. graph_unindexed=N: N files no grammar could read (the map header's unindexed=); their calls raise neither gauge. root=: p= relative to it. defs=N: definitions the selector matched; qualify file:name to narrow the call sites. external=1: of= has no definition in the indexed tree under any spelling (stdlib/third-party). count=N: use-site rows in all (a floor). -->
<uses schema="ripwire.uses/v1" of="rankGraphTeleport" defs="1" external="0" count="9" root="." graph_ambiguous="10278" graph_unresolved="12878" graph_unindexed="237" counts_floor="1">
<u role="call" p="src/mcpindex.h:1268" in_id="src/mcpindex.h::rw::getIndex"/>
<u role="call" p="src/graph.h:5609" in_id="src/graph.h::rw::rankGraph"/>
<u role="call" p="src/graph.h:6303" in_id="src/graph.h::rw::anchoredLexicalRank"/>
<u role="call" p="src/eval.h:325" in_id="src/eval.h::rw::runEval"/>
<u role="call" p="src/main.cpp:1394" in_id="churnDecayRanking"/>
<u role="call" p="src/main.cpp:1433" in_id="churnRankedGraph"/>
<u role="call" p="src/main.cpp:1434" in_id="churnRankedGraph"/>
<u role="call" p="src/main.cpp:1448" in_id="churnRankedGraph"/>
<u role="call" p="src/main.cpp:1749" in_id="runDefaultMap"/>
</uses>
`````

## `./build/ripwire . --graph-query='and(callers(name("rankGraphTeleport"),2),kind(all,fn))'`

*Composable node-set query: functions within 2 caller-hops of rankGraphTeleport.*

`````
<!-- ripwire graph-query schema=ripwire.graph-query/v1: graph-query expression over the symbol graph: <s t= n= p=> matching rows. window: shown= capped= (capped=1 cut). counts_floor=1: every count is a FLOOR, never a total. graph_ambiguous=/graph_unresolved=: resolver gauge. graph_unindexed=N: N files no grammar could read (the map header's unindexed=); their calls raise neither gauge. root=: p= relative to it. pr_iters=N: PageRank iterations. expr=: the expression as given; count=: symbols it matched (rows page by shown=/total=). -->
<query schema="ripwire.graph-query/v1" expr="and(callers(name(&quot;rankGraphTeleport&quot;),2),kind(all,fn))" count="55" shown="55" capped="0" graph_ambiguous="10278" graph_unresolved="12878" graph_unindexed="237" counts_floor="1" root="." pr_iters="28">
<s t="fn" n="getIndex" p="src/mcpindex.h:1165"/>
<s t="fn" n="anchoredLexicalRank" p="src/graph.h:6252"/>
<s t="fn" n="emitCommunitiesReport" p="src/verbs_report.h:2517"/>
<s t="fn" n="emitCommunityDrill" p="src/verbs_report.h:2678"/>
<s t="fn" n="rankGraph" p="src/graph.h:5606"/>
<s t="fn" n="dispatchMain" p="src/main.cpp:4108"/>
<s t="fn" n="computeLensRanking" p="src/verbs_for.h:78"/>
<s t="fn" n="postCheckJson" p="src/mcpedit.h:1116"/>
<s t="fn" n="fetchBody" p="src/mcpverbs.h:4787"/>
<s t="fn" n="dispatchMcpLine" p="src/mcp.h:1118"/>
<s t="fn" n="runEvalRetrieval" p="src/eval.h:713"/>
<s t="fn" n="runEvalMined" p="src/eval.h:1086"/>
<s t="fn" n="churnDecayRanking" p="src/main.cpp:1380"/>
<s t="fn" n="runEditVerb" p="src/mcpedit.h:1189"/>
<s t="fn" n="fetchBodyByName" p="src/mcpverbs.h:4710"/>
<s t="fn" n="anchoredFileScore" p="src/eval.h:111"/>
<s t="fn" n="symbolQueryJson" p="src/mcpverbs.h:690"/>
<s t="fn" n="analyzeToString" p="src/mcpverbs.h:428"/>
<s t="fn" n="grepHitsJson" p="src/mcpverbs.h:1084"/>
<s t="fn" n="cochangePartnersJson" p="src/mcpverbs.h:1251"/>
<s t="fn" n="mentionsJson" p="src/mcpverbs.h:1643"/>
<s t="fn" n="forTaskText" p="src/mcpverbs.h:1818"/>
<s t="fn" n="legoText" p="src/mcpverbs.h:2431"/>
<s t="fn" n="ownersText" p="src/mcpverbs.h:2469"/>
<s t="fn" n="exemplarText" p="src/mcpverbs.h:2610"/>
<s t="fn" n="impactText" p="src/mcpverbs.h:2692"/>
<s t="fn" n="usesText" p="src/mcpverbs.h:3002"/>
<s t="fn" n="pathText" p="src/mcpverbs.h:3168"/>
… [28 more display lines; full output is 3649 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --external-surface`

*Names referenced but never defined in-corpus (stdlib/third-party surface). The root carries names/shown/capped; the default is a 100-row window now, so total= and a pasteable next= join them when it bites (the explicit --limit form carries the same quintet). The sh BUILTINS (cd/echo/set…) are dropped and COUNTED as builtins_excluded= — grep/sed/git stay, they ARE the surface.*

`````
<!-- ripwire external-surface schema=ripwire.external-surface/v1: names used but never defined in the index: <x n= lang= refs= calls=>. window: shown= total= capped= has_more= next_offset= offset= limit= (capped=1 cut; next_offset= pastes as offset=). next=: the one pasteable follow-up. names=N: distinct external names (the x rows' total). builtins_excluded=N: sh BUILTIN rows (echo printf cd exit test ...) dropped from names=; the include-builtins flag keeps them. -->
<external-surface schema="ripwire.external-surface/v1" names="2529" builtins_excluded="19" shown="100" capped="1" total="2529" has_more="1" next_offset="100" offset="0" limit="0" next="--external-surface --offset=100">
<x n="grep" lang="sh" refs="12326" calls="12326"/>
<x n="cat" lang="sh" refs="2136" calls="2136"/>
<x n="tr" lang="sh" refs="1909" calls="1909"/>
<x n="sed" lang="sh" refs="1510" calls="1510"/>
<x n="python3" lang="sh" refs="1502" calls="1502"/>
<x n="substr" lang="cpp" refs="1046" calls="1046"/>
<x n="print" lang="py" refs="937" calls="937"/>
<x n="wc" lang="sh" refs="839" calls="839"/>
<x n="mktemp" lang="sh" refs="806" calls="806"/>
<x n="dirname" lang="sh" refs="767" calls="767"/>
<x n="to_string" lang="cpp" refs="761" calls="761"/>
<x n="string_view" lang="cpp" refs="681" calls="681"/>
<x n="stdout" lang="cpp" refs="661" calls="0"/>
<x n="xmllint" lang="sh" refs="598" calls="598"/>
<x n="uint32_t" lang="cpp" refs="594" calls="594"/>
<x n="diff" lang="sh" refs="560" calls="560"/>
<x n="cmp" lang="sh" refs="553" calls="553"/>
<x n="stderr" lang="cpp" refs="535" calls="0"/>
<x n="cp" lang="sh" refs="507" calls="507"/>
<x n="ts_node_is_null" lang="cpp" refs="502" calls="502"/>
<x n="size_t" lang="cpp" refs="471" calls="471"/>
<x n="ex" lang="cpp" refs="453" calls="363"/>
<x n="awk" lang="sh" refs="437" calls="437"/>
<x n="tail" lang="sh" refs="405" calls="405"/>
<x n="ts_node_type" lang="cpp" refs="353" calls="353"/>
<x n="rm" lang="sh" refs="325" calls="325"/>
<x n="add_argument" lang="py" refs="300" calls="300"/>
<x n="sorted" lang="py" refs="221" calls="221"/>
… [73 more display lines; full output is 5563 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --external-surface --include-builtins`

*The restoring knob: --include-builtins keeps the shell builtins in the same 100-row window (they now compete for rows, so the window's tail differs).*

`````
<!-- ripwire external-surface schema=ripwire.external-surface/v1: names used but never defined in the index: <x n= lang= refs= calls=>. window: shown= total= capped= has_more= next_offset= offset= limit= (capped=1 cut; next_offset= pastes as offset=). next=: the one pasteable follow-up. names=N: distinct external names (the x rows' total). -->
<external-surface schema="ripwire.external-surface/v1" names="2548" shown="100" capped="1" total="2548" has_more="1" next_offset="100" offset="0" limit="0" next="--external-surface --include-builtins --offset=100">
<x n="grep" lang="sh" refs="12326" calls="12326"/>
<x n="printf" lang="sh" refs="11464" calls="11464"/>
<x n="echo" lang="sh" refs="7488" calls="7488"/>
<x n="exit" lang="sh" refs="2642" calls="2642"/>
<x n="cat" lang="sh" refs="2136" calls="2136"/>
<x n="tr" lang="sh" refs="1909" calls="1909"/>
<x n="cd" lang="sh" refs="1862" calls="1862"/>
<x n="sed" lang="sh" refs="1510" calls="1510"/>
<x n="python3" lang="sh" refs="1502" calls="1502"/>
<x n="return" lang="sh" refs="1178" calls="1178"/>
<x n="substr" lang="cpp" refs="1046" calls="1046"/>
<x n="print" lang="py" refs="937" calls="937"/>
<x n="command" lang="sh" refs="906" calls="906"/>
<x n="wc" lang="sh" refs="839" calls="839"/>
<x n="mktemp" lang="sh" refs="806" calls="806"/>
<x n="dirname" lang="sh" refs="767" calls="767"/>
<x n="to_string" lang="cpp" refs="761" calls="761"/>
<x n="pwd" lang="sh" refs="722" calls="722"/>
<x n="trap" lang="sh" refs="686" calls="686"/>
<x n="string_view" lang="cpp" refs="681" calls="681"/>
<x n="stdout" lang="cpp" refs="661" calls="0"/>
<x n="xmllint" lang="sh" refs="598" calls="598"/>
<x n="uint32_t" lang="cpp" refs="594" calls="594"/>
<x n="diff" lang="sh" refs="560" calls="560"/>
<x n="cmp" lang="sh" refs="553" calls="553"/>
<x n="stderr" lang="cpp" refs="535" calls="0"/>
<x n="cp" lang="sh" refs="507" calls="507"/>
<x n="ts_node_is_null" lang="cpp" refs="502" calls="502"/>
… [73 more display lines; full output is 5441 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --path=main,rankGraphTeleport`

*Shortest directed call-path SRC -> DST. CHANGED: now reports from_p/to_p/from_defs and resolves the right `main` (was reachable="0").*

`````
<!-- ripwire path schema=ripwire.path/v1: one DIRECTED call path from= to to=, each <s t= n= p=> a hop; reachable=0 hops=0 when none. counts_floor=1: every count is a FLOOR, never a total. graph_ambiguous=/graph_unresolved=: resolver gauge. graph_unindexed=N: N files no grammar could read (the map header's unindexed=); their calls raise neither gauge. root=: p= relative to it. from_p=/to_p=: the definitions from= and to= were bound to. from_defs=/to_defs=: definitions of each name, all searched; above 1, qualify file:name. -->
<path schema="ripwire.path/v1" from="main" to="rankGraphTeleport" from_p="src/main.cpp:3973" to_p="src/graph.h:5565" from_defs="108" to_defs="1" reachable="1" hops="4" root="." graph_ambiguous="10278" graph_unresolved="12878" graph_unindexed="237" counts_floor="1">
<s t="fn" n="main" p="src/main.cpp:3973"/>
<s t="fn" n="runWithCompactLegend" p="src/main.cpp:3909"/>
<s t="fn" n="dispatchMain" p="src/main.cpp:4108"/>
<s t="fn" n="runDefaultMap" p="src/main.cpp:1629"/>
<s t="fn" n="rankGraphTeleport" p="src/graph.h:5565"/>
</path>
`````

## `./build/ripwire . --connect=rankGraphTeleport,runEval,getIndex`

*Minimal connecting subgraph over 3 symbols (finds shared-caller joins).*

`````
<!-- ripwire connect schema=ripwire.connect/v1: minimal joining subgraph: <g> groups, <t> terminals, <s connects=> joins, <e f= t=> edges, <unconnected>. counts_floor=1: every count is a FLOOR, never a total. graph_ambiguous=/graph_unresolved=: resolver gauge. graph_unindexed=N: N files no grammar could read (the map header's unindexed=); their calls raise neither gauge. est_tokens=: price as emitted (an upper bound under compact). root=: p= relative to it. hub_floor=D: connects= >= D is hub=1, vacuous. nodes=N: symbols printed, terminals plus joins (a floor). radius=N: undirected hop bound searched (default 6, max 12); raise it with connect-radius=N. terminals=/groups=/edges=: task symbols resolved, connected groups (g), e edges printed. -->
<connect schema="ripwire.connect/v1" terminals="3" nodes="3" edges="2" radius="6" groups="1" est_tokens="512" hub_floor="263" root="." graph_ambiguous="10278" graph_unresolved="12878" graph_unindexed="237" counts_floor="1">
<g terminals="3">
<t n="runEval" t="fn" p="src/eval.h:171"/>
<t n="rankGraphTeleport" t="fn" p="src/graph.h:5565"/>
<t n="getIndex" t="fn" p="src/mcpindex.h:1165"/>
<e f="runEval" t="rankGraphTeleport"/>
<e f="getIndex" t="rankGraphTeleport"/>
</g>
</connect>
`````

## `./build/ripwire . --impact=rankGraphTeleport`

*Transitive blast radius — everything that reaches SYM. NOW carries shown/capped.*

`````
<!-- ripwire impact schema=ripwire.impact/v1: transitive blast radius of of=: <s t= n= p=> reach set, <f via= p=> importers; defs= matched, reaches= their transitive callers, radius_tested= non-tests an indexed test reaches, radius_untested= the rest; importers= files that #include/import a def's file. window: shown= total= capped= has_more= next_offset= offset= limit= (capped=1 cut; next_offset= pastes as offset=). importers_capped=: 1 = cut. counts_floor=1: every count is a FLOOR, never a total. graph_ambiguous=/graph_unresolved=: resolver gauge. graph_unindexed=N: N files no grammar could read (the map header's unindexed=); their calls raise neither gauge. root=: p= relative to it. pr_iters=N: PageRank iterations. shown_importers=: <f> rows (limit= sizes them). <f lazy=1>: every edge from that importer into a def file is deferred (in a function/block body, or an autoload), firing only if reached; lazy=0: at least one is load-time. <s d=N>: hops to of= (1 = direct caller), set where it changes. by_depth=k:n: n of reaches= at depth k, shallowest rows first. next=: the one pasteable follow-up. -->
<impact schema="ripwire.impact/v1" of="rankGraphTeleport" defs="1" reaches="67" by_depth="1:7,2:48,3:10,4:2" importers="35" shown_importers="35" importers_capped="0" radius_tested="0" radius_untested="67" root="." shown="40" capped="1" total="67" has_more="1" next_offset="40" offset="0" limit="0" gr … [line truncated: 139 more bytes on this line]
<s t="fn" n="getIndex" p="src/mcpindex.h:1165" d="1"/>
<s t="fn" n="anchoredLexicalRank" p="src/graph.h:6252"/>
<s t="fn" n="rankGraph" p="src/graph.h:5606"/>
<s t="fn" n="churnDecayRanking" p="src/main.cpp:1380"/>
<s t="fn" n="churnRankedGraph" p="src/main.cpp:1419"/>
<s t="fn" n="runDefaultMap" p="src/main.cpp:1629"/>
<s t="fn" n="runEval" p="src/eval.h:171"/>
<s t="fn" n="emitCommunitiesReport" p="src/verbs_report.h:2517" d="2"/>
<s t="fn" n="emitCommunityDrill" p="src/verbs_report.h:2678"/>
<s t="fn" n="dispatchMain" p="src/main.cpp:4108"/>
<s t="fn" n="computeLensRanking" p="src/verbs_for.h:78"/>
<s t="fn" n="postCheckJson" p="src/mcpedit.h:1116"/>
<s t="fn" n="fetchBody" p="src/mcpverbs.h:4787"/>
<s t="fn" n="dispatchMcpLine" p="src/mcp.h:1118"/>
<s t="fn" n="runEvalRetrieval" p="src/eval.h:713"/>
<s t="fn" n="runEvalMined" p="src/eval.h:1086"/>
<s t="fn" n="runEditVerb" p="src/mcpedit.h:1189"/>
<s t="fn" n="fetchBodyByName" p="src/mcpverbs.h:4710"/>
<s t="fn" n="anchoredFileScore" p="src/eval.h:111"/>
<s t="fn" n="symbolQueryJson" p="src/mcpverbs.h:690"/>
<s t="fn" n="analyzeToString" p="src/mcpverbs.h:428"/>
<s t="fn" n="grepHitsJson" p="src/mcpverbs.h:1084"/>
<s t="fn" n="cochangePartnersJson" p="src/mcpverbs.h:1251"/>
<s t="fn" n="mentionsJson" p="src/mcpverbs.h:1643"/>
<s t="fn" n="forTaskText" p="src/mcpverbs.h:1818"/>
<s t="fn" n="legoText" p="src/mcpverbs.h:2431"/>
<s t="fn" n="ownersText" p="src/mcpverbs.h:2469"/>
<s t="fn" n="exemplarText" p="src/mcpverbs.h:2610"/>
… [48 more display lines; full output is 5280 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --mentions=rankGraphTeleport`

*Markdown docs that name SYM in a backtick (doc<->code edges).*

`````
<!-- ripwire mentions schema=ripwire.mentions/v1: markdown FILES naming of= in backticks (docs=, sections=): <doc p= mentions=>; not a call edge. root=: p= relative to it. defs=N: definitions of= resolved to; rows union their doc mentions. -->
<!-- unbackticked_docs=N: N more markdown files, over readable indexed markdown, name of= as a whole word but not as a clean one-line backtick span (prose, a code block, a span broken across lines) - not in docs=; a text match, so a ceiling -->
<mentions schema="ripwire.mentions/v1" of="rankGraphTeleport" defs="1" docs="6" sections="13" unbackticked_docs="4" root=".">
<doc p="docs/ARCHITECTURE.md" mentions="1"/>
<doc p="docs/EVALS.md" mentions="3"/>
<doc p="prompts/help-wanted/certified-ranking-order.md" mentions="2"/>
<doc p="prompts/help-wanted/correctness-fuzzers.md" mentions="1"/>
<doc p="prompts/help-wanted/graph-unit-tests.md" mentions="5"/>
<doc p="prompts/help-wanted/next-uses-bare-name.md" mentions="1"/>
</mentions>
`````

## `./build/ripwire . --affected=src/graph.h`

*Test files that transitively reach the changed file.*

`````
<!-- ripwire affected schema=ripwire.affected/v1: test files that transitively reach the changed files/symbols: <test p= partner= hops= run=> in evidence order (order= partners=); seeded_by= the reading taken. counts_floor=1: every count is a FLOOR, never a total. graph_ambiguous=/graph_unresolved=: resolver gauge. graph_unindexed=N: N files no grammar could read (the map header's unindexed=); their calls raise neither gauge. run_unknown=1: no runner derivable (a guess would be worse). <g n= p=a,b,c>: n runner-less rows with equal attrs as ONE row, paths verbatim; a path holding ',' is never grouped, so p= splits into exactly n=; shown=/total= over these rows counts test FILES. root=: p= relative to it. seeds=N: symbols the argument matched; only those outside test files seed the caller walk. seed_test_files=N: matched files that are TESTS; listed to run (seed_kind=test), never walk seeds. tests=N: test files listed to run (the rows). reached=N: symbols the transitive caller walk reached from the seeds (seeds excluded). script_gates_unmodelled=N: test/*.sh runners; their subprocess reach is unmodelled, never in tests=/reached=. run_first=N: the first N test files have the most direct evidence (changed/partner/hops=1, else nearest hops=); not a skip list. changed=: the files/symbols argument as given. -->
<affected schema="ripwire.affected/v1" changed="src/graph.h" seeded_by="file" seeds="263" seed_test_files="0" tests="19" reached="1746" script_gates_unmodelled="729" run_first="3" order="evidence" partners="0" root="." graph_ambiguous="10278" graph_unresolved="12878" graph_unindexed="237" counts_flo … [line truncated: 7 more bytes on this line]
<test p="test/connectcore_harness.cpp" hops="1" run="bash test/connectcorecheck.sh"/>
<test p="test/cppqualtmplfix/member.cpp" hops="1" run="bash test/cppqualcheck.sh"/>
<test p="test/verify_csr.cpp" hops="1" run="bash test/a9disclosurecheck.sh"/>
<test p="test/cloneband_harness.cpp" hops="2" run="bash test/clonebandcheck.sh"/>
<test p="test/clonelex_harness.cpp" hops="2" run="bash test/clonelexcheck.sh"/>
<test p="test/diagnotice_harness.cpp" hops="2" run="bash test/binoverridecheck.sh"/>
<g hops="2" n="4" p="test/fuzz/readers/readers_domain.cpp,test/fuzz/readers/readers_ingest.cpp,test/fuzz/readers/readers_light.cpp,test/fuzz/readers/readers_mcphttp.cpp" run_unknown="1"/>
<test p="test/includeprecise_unit.cpp" hops="2" run="bash test/includeprecisecheck.sh"/>
<test p="test/rustimport_unit.cpp" hops="2" run="bash test/rustimportprecisecheck.sh"/>
<test p="test/type3clone_harness.cpp" hops="2" run="bash test/type3clonecheck.sh"/>
<test p="test/verify_os_win32_logic.cpp" hops="2" run="bash test/binoverridecheck.sh"/>
<test p="test/verify_strkern.cpp" hops="2" run="bash test/binoverridecheck.sh"/>
<test p="test/fuzz/readers/fuzzsupport.h" hops="3" run_unknown="1"/>
<test p="test/redactshape_harness.cpp" hops="3" run="bash test/regexguardcheck.sh"/>
<test p="test/columnarcommafix/columnar_comma_test.cpp" hops="4" run="bash test/columnarcommacheck.sh"/>
<test p="test/regexlines_harness.cpp" hops="4" run="bash test/regexguardcheck.sh"/>
</affected>
`````

## `./build/ripwire . --situ`

*Mid-task situational report for the current git diff — recorded against a CLEAN tree (contrast with the sandbox run below).*

`````
ripwire situational-awareness — 0 changed file(s), 0 symbols in them
root: .
at: c7920353a
  (0 changed files — working tree is clean, nothing to analyze)
`````

## `./build/ripwire . --test-gate`

*Pre-PR gate on a CLEAN tree: no obligations, exit 0.*

**wall time: 1.87s**

`````
<!-- ripwire test-gate schema=ripwire.test-gate/v1: tests <t p= changed= partner= hops= run=> + untested blast radius <u sym= p= l= ccx=>; exit 4 while either exists. tests_capped=/untested_capped=: 1 = cut. counts_floor=1: every count is a FLOOR, never a total. graph_ambiguous=/graph_unresolved=: resolver gauge. graph_unindexed=N: N files no grammar could read (the map header's unindexed=); their calls raise neither gauge. at=: commit+dirty+shallow. next=: the one pasteable follow-up. impacted=N: symbols that transitively call the change (changed symbols excluded). shown_tests=/shown_untested=: t rows and u rows printed, two independent counts. script_gates_unmodelled=N: test/*.sh runners in the corpus, a path count; not call-graph modelled. script_gates_registered=N: shell gates test/regression.sh registers as suite members. script_gates_mapped=N: registered gates with exact dependency evidence (literal paths or RIPWIRE_TEST_DEPS). script_gates_unresolved_dynamic=N: registered gates with no mappable deps; they may cover the change unlisted. ccx_bar=N: the cognitive-complexity bar a u row's ccx= is read against. untested_modscope=N: <file-scope> owners excluded from untested= (#324, uncallable); still in impacted=. tests=/untested=: tests to run (t total) / impacted symbols no test reaches (u total). -->
<test-gate schema="ripwire.test-gate/v1" changed="0" impacted="0" tests="0" untested="0" untested_modscope="0" shown_tests="0" tests_capped="0" shown_untested="0" untested_capped="0" script_gates_unmodelled="729" script_gates_registered="683" script_gates_mapped="202" script_gates_unresolved_dynamic … [line truncated: 137 more bytes on this line]
</test-gate>
`````

## `./build/ripwire . --grep=DISCLOSE`

*Literal trigram-indexed search. Each hit carries its MATCHED line as the <hit> element's own CDATA (the <m> wrapper is gone), plus shown/capped/hits_capped and a pasteable next= on the root.*

`````
<!-- ripwire grep schema=ripwire.grep/v1: literal/regex scan grouped by file: <f p=>
<hit l= in=>CDATA text</hit> (<b>/<a> context around it); complete=1 only for an exhaustive literal scan; <unindexed> = off-index. window: shown= total= capped= has_more= next_offset= offset= limit= (capped=1 cut; next_offset= pastes as offset=). counts_floor=1: every count is a FLOOR, never a total … [line truncated: 1666 more bytes on this line]
<grep pattern="DISCLOSE" schema="ripwire.grep/v1" root="." files="240" hits="793" shown="100" capped="1" total="793" has_more="1" next_offset="100" offset="0" limit="0" hits_capped="0" suppressed_comment="201" suppressed_string="5" tier_parsed="82" tier_unclassified="538" tier_budget="bytes" tier_fi … [line truncated: 201 more bytes on this line]
<f p=".coderabbit.yaml">
<hit l="30" in="path_instructions" n="2">
<![CDATA[        A degrade path uses DISCLOSE( sink, why ), never ASSUME(false): a one-argument DISCLOSE( msg ) is a debug trace]]>
<at l="30" in="path_instructions"/>
</hit>
</f>
<f p="src/abicheck.h" parse_degraded="1">
<hit l="493" in="abicheck::collectAuthoredSites">
<![CDATA[            DISCLOSE( result, AbiResult::DisclosureWhy::NoMergeBase, "abi: no merge-base for a ref (unrelated history?) — that ref is counted, not compared" );]]>
</hit>
</f>
<f p="src/arch.h">
<hit l="505" in="rw::parseArchRules">
<![CDATA[        DISCLOSE( Diagnostics::answerRefused, "--arch exits 1 with path:line and the reason on stderr; no report is printed",]]>
</hit>
<hit l="844" in="rw::readArchBaselineSidecar">
<![CDATA[    if( sidecar.refused ) { DISCLOSE( baseline, ArchBaselineRead::DisclosureWhy::SymlinkRefused, "arch: refusing to read the arch baseline sidecar through a symlink" ); }]]>
</hit>
<hit l="895" in="rw::openArchBaselineSidecar">
<![CDATA[        DISCLOSE( Diagnostics::answerRefused, "--baseline exits 1: pathguard names the refused link on stderr and the verb says it cannot write the sidecar",]]>
</hit>
</f>
<f p="src/atoms.h">
<hit l="372" in="atomdetail::collectExclusions">
<![CDATA[        DISCLOSE( ex, Exclusions::DisclosureWhy::ForHeaderSaturated, "atoms: the for-header exclusion stream spent its whole budget; the rules reading it are suppressed this run" );]]>
</hit>
<hit l="376" in="atomdetail::collectExclusions">
… [393 more display lines; full output is 25803 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --grep=DISCLOSE --grep-context=1`

*Same search with one line of source context either side.*

`````
<!-- ripwire grep schema=ripwire.grep/v1: literal/regex scan grouped by file: <f p=>
<hit l= in=>CDATA text</hit> (<b>/<a> context around it); complete=1 only for an exhaustive literal scan; <unindexed> = off-index. window: shown= total= capped= has_more= next_offset= offset= limit= (capped=1 cut; next_offset= pastes as offset=). counts_floor=1: every count is a FLOOR, never a total … [line truncated: 1666 more bytes on this line]
<grep pattern="DISCLOSE" schema="ripwire.grep/v1" root="." files="240" hits="793" shown="100" capped="1" total="793" has_more="1" next_offset="100" offset="0" limit="0" hits_capped="0" suppressed_comment="201" suppressed_string="5" tier_parsed="82" tier_unclassified="538" tier_budget="bytes" tier_fi … [line truncated: 201 more bytes on this line]
<f p=".coderabbit.yaml">
<hit l="30" in="path_instructions">
<b>
<![CDATA[        External input (files, git, env, argv, MCP/JSON, data read back from a cache) is checked with VALIDATE.]]>
</b>
<![CDATA[        A degrade path uses DISCLOSE( sink, why ), never ASSUME(false): a one-argument DISCLOSE( msg ) is a debug trace]]>
<a>
<![CDATA[        that ships nothing, and a Diagnostics::answerUnchanged reason must be true. A count that cannot be a total must be]]>
</a>
</hit>
<hit l="30" in="path_instructions">
<b>
<![CDATA[        External input (files, git, env, argv, MCP/JSON, data read back from a cache) is checked with VALIDATE.]]>
</b>
<![CDATA[        A degrade path uses DISCLOSE( sink, why ), never ASSUME(false): a one-argument DISCLOSE( msg ) is a debug trace]]>
<a>
<![CDATA[        that ships nothing, and a Diagnostics::answerUnchanged reason must be true. A count that cannot be a total must be]]>
</a>
</hit>
</f>
<f p="src/abicheck.h" parse_degraded="1">
<hit l="493" in="abicheck::collectAuthoredSites">
<b>
<![CDATA[        {]]>
</b>
<![CDATA[            DISCLOSE( result, AbiResult::DisclosureWhy::NoMergeBase, "abi: no merge-base for a ref (unrelated history?) — that ref is counted, not compared" );]]>
<a>
… [990 more display lines; full output is 39704 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --grep=DISCLOSE --grep-before=1 --grep-after=2 --limit=3`

*The asymmetric spelling of the same context: one line before and two after each hit (ripgrep's -B/-A), on a three-hit window.*

`````
<!-- ripwire grep schema=ripwire.grep/v1: literal/regex scan grouped by file: <f p=>
<hit l= in=>CDATA text</hit> (<b>/<a> context around it); complete=1 only for an exhaustive literal scan; <unindexed> = off-index. window: shown= total= capped= has_more= next_offset= offset= limit= (capped=1 cut; next_offset= pastes as offset=). counts_floor=1: every count is a FLOOR, never a total … [line truncated: 1531 more bytes on this line]
<grep pattern="DISCLOSE" schema="ripwire.grep/v1" root="." files="240" hits="793" shown="3" capped="1" total="793" has_more="1" next_offset="3" offset="0" limit="3" hits_capped="0" suppressed_comment="201" suppressed_string="5" tier_parsed="82" tier_unclassified="538" tier_budget="bytes" tier_files= … [line truncated: 195 more bytes on this line]
<f p=".coderabbit.yaml">
<hit l="30" in="path_instructions">
<b>
<![CDATA[        External input (files, git, env, argv, MCP/JSON, data read back from a cache) is checked with VALIDATE.]]>
</b>
<![CDATA[        A degrade path uses DISCLOSE( sink, why ), never ASSUME(false): a one-argument DISCLOSE( msg ) is a debug trace]]>
<a>
<![CDATA[        that ships nothing, and a Diagnostics::answerUnchanged reason must be true. A count that cannot be a total must be
        labelled a floor; a zero means none found. Flag silent zeros, undisclosed truncation, and gate arms]]></a></hit><hit l="30" in="path_instructions"><b><![CDATA[        External input (files, git, env, argv, MCP/JSON, data read back from a cache) is checked with VALIDATE.]]></b><![CDATA[       … [line truncated: 250 more bytes on this line]
        labelled a floor; a zero means none found. Flag silent zeros, undisclosed truncation, and gate arms]]></a></hit></f><f p="src/abicheck.h" parse_degraded="1"><hit l="493" in="abicheck::collectAuthoredSites"><b><![CDATA[        {]]></b><![CDATA[            DISCLOSE( result, AbiResult::Disclosu … [line truncated: 148 more bytes on this line]
        }]]></a></hit></f><unindexed count="8" shown="3" capped="1"><f p="CMakeLists.txt"><hit l="122"><![CDATA[# ASSUME and the DISCLOSE( msg ) trace live, which is the only configuration that can catch an]]></hit><hit l="321"><![CDATA[# -DCMAKE_BUILD_TYPE=Release" locally — Release defines NDEBU … [line truncated: 320 more bytes on this line]
`````

## `./build/ripwire . --regex='fnv1a\w+'`

*Regex search + enclosing symbol.*

`````
<!-- ripwire grep schema=ripwire.grep/v1: literal/regex scan grouped by file: <f p=>
<hit l= in=>CDATA text</hit> (<b>/<a> context around it); complete=1 only for an exhaustive literal scan; <unindexed> = off-index. window: shown= capped= (capped=1 cut). hits_capped=1: hits= is a floor. regex_lines_skipped=N: N lines too long for the regex engine, never matched. root=: p= relative t … [line truncated: 1359 more bytes on this line]
<grep pattern="fnv1a\w+" schema="ripwire.grep/v1" root="." files="25" hits="81" shown="81" capped="0" hits_capped="0" suppressed_comment="62" suppressed_string="26" tier_parsed="41" tier_unclassified="0" corpus_oversize="15" corpus_pruned_dirs="8" unindexed_hits="23" unindexed_files_scanned="236" un … [line truncated: 77 more bytes on this line]
<f p="src/arch.h">
<hit l="676" in="rw::fnv1a64">
<![CDATA[inline std::uint64_t fnv1a64( std::string_view s ) noexcept]]>
</hit>
<hit l="681" in="rw::fnv1a64">
<![CDATA[        h = hashutil::fnv1aAbsorb( h, c );]]>
</hit>
<hit l="786" in="rw::archViolHash">
<![CDATA[            h = hashutil::fnv1aAbsorb( h, c );]]>
</hit>
<hit l="789" in="rw::archViolHash">
<![CDATA[        h = hashutil::fnv1aMultiply( h ); // NUL separator byte]]>
</hit>
</f>
<f p="src/cloneidiom.h">
<hit l="607" in="rw::classifyCloneGroupIdioms">
<![CDATA[                ids.push_back( fnv1a64( t.text ) );]]>
</hit>
</f>
<f p="src/clones.h">
<hit l="675" in="rw::cloneTokenHash">
<![CDATA[        h = hashutil::fnv1aAbsorb( h, c );]]>
</hit>
<hit l="677" in="rw::cloneTokenHash">
<![CDATA[    h ^= 0x9e3779b97f4a7c15ull;  h = hashutil::fnv1aMultiply( h );   // token separator so [ab][c] != [a][bc]]]>
</hit>
<hit l="782" in="rw::findClonesType3">
… [399 more display lines; full output is 19816 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --match='(if_statement)'`

*Tree-sitter structural query WITHOUT a capture — a bare node query gets a capture AUTO-ADDED (auto_captured="1") and matches the same nodes the explicit form does.*

`````
<!-- ripwire match schema=ripwire.match/v1: tree-sitter structural query: <m p= in=> captured nodes with their enclosing symbol; grammars=/eligible_files= the scope. window: shown= total= capped= has_more= next_offset= offset= limit= (capped=1 cut; next_offset= pastes as offset=). counts_floor=1: every count is a FLOOR, never a total. hits_capped=1: hits= is a floor. root=: p= relative to it. auto_captured=1: the query bound no @capture, so @m was appended to its single top-level pattern. of_files=: indexed files in all (eligible_files= of them are in the query's languages). -->
<match schema="ripwire.match/v1" hits="5000" shown="100" capped="1" total="5000" has_more="1" next_offset="100" offset="0" limit="0" counts_floor="1" hits_capped="1" auto_captured="1" grammars="cpp,c,python,go,typescript,tsx,swift,objc,javascript,bash,java,csharp,php,dart,lua,gdscript" eligible_file … [line truncated: 34 more bytes on this line]
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
… [73 more display lines; full output is 16956 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --match='(if_statement) @i'`

*The same shape query WITH an explicit capture — identical hits, no auto_captured= attribute.*

`````
<!-- ripwire match schema=ripwire.match/v1: tree-sitter structural query: <m p= in=> captured nodes with their enclosing symbol; grammars=/eligible_files= the scope. window: shown= total= capped= has_more= next_offset= offset= limit= (capped=1 cut; next_offset= pastes as offset=). counts_floor=1: every count is a FLOOR, never a total. hits_capped=1: hits= is a floor. root=: p= relative to it. of_files=: indexed files in all (eligible_files= of them are in the query's languages). -->
<match schema="ripwire.match/v1" hits="5000" shown="100" capped="1" total="5000" has_more="1" next_offset="100" offset="0" limit="0" counts_floor="1" hits_capped="1" grammars="cpp,c,python,go,typescript,tsx,swift,objc,javascript,bash,java,csharp,php,dart,lua,gdscript" eligible_files="1969" of_files= … [line truncated: 16 more bytes on this line]
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
… [73 more display lines; full output is 16840 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --query="teleport pagerank" --top-k=5`

*Raw BM25 ranking (debug lens; --for is the real verb).*

`````
<!-- routed: subtoken+body:broad -->
<!-- ripwire query schema=ripwire.query/v1: lexical-rank map for the query term, the map's row vocabulary. est_tokens=: price as emitted (an upper bound under compact). root=: p= relative to it. declined=K: K calls left unbound (no evidence chose one def). external=K: K calls proven outside the tree, no edge. locality_pinned=K: K calls pinned by locality alone (a guess). extent_suspect_syms=K: K defs failed containment, corpus-wide. macro_blanked_files=K: K files indexed from a macro-blanked re-parse. prov=scip|binding|import|split|final-segment: how that <c> edge bound (absent: one unique name); split = one arm of an amb= pick; final-segment = a qualified type matched by last name only. files=/symbols=: files and symbols indexed; edges= distinct call edges; shown= symbols printed, a merged row counting each def; ambiguous= calls split over several defs, corpus-wide; unresolved= calls with in-tree evidence and no edge (every def language-filtered or unreachable, or binding refused); order= rows by rank (important-first, important-last; (auto:fill) = flipped past a size threshold) or by path (stable). skipped_oversize=K: K files over a size ceiling, not indexed. unindexed=ext:N: N text files of that extension no grammar reads (6 extensions at most). unindexed_exts=E: E such extensions in all, the list cut. sc=: enclosing scope; the full id is p::sc::n (p= of the row or its <f>) and selectors take it. amb=K: K calls split over several defs. -->
<!-- t=modscope=a-file's-MODULE-SCOPE(n=<file-scope>):the-statements-outside-every-named-definition,where-a-top-level-call-and-an-anonymous-callback-body's-calls-live;a-CALLER-never-a-callee(nothing-in-the-source-can-name-it)-with-no-body-to-expand;a-file-with-no-such-call-has-no-such-row -->
<!-- files=2484 symbols=23851 edges=34236 shown=5 est_tokens=1339 ambiguous=10278 unresolved=12878 locality_pinned=12 external=7345 declined=9922 extent_suspect_syms=10 macro_blanked_files=7 skipped_oversize=15 unindexed="txt:73,tsv:49,jsonl:26,scm:23,expected:15,xml:13" unindexed_exts=20 order=important-first -->
<r schema="ripwire.query/v1" root="." est_tokens="1339">
<f p="src/serialize.h">
<s t="var" n="kChurnRankLegend" sc="rw" k="18.7810">
</s>
</f>
<f p="src/mcpverbs.h">
<s t="fn" n="rankByText" sc="rw" amb="3" k="15.4288">
<c n="takeRank"/>
<c n="rankGraph"/>
<c n="hits"/>
<c n="rrfFuse"/>
<c n="getIndex"/>
<c n="captureXml"/>
<c n="empty" prov="split"/>
<c n="empty" prov="split"/>
<c n="empty" prov="split"/>
<c n="serialize"/>
</s>
</f>
<f p="src/gitmine.h">
<s t="fn" n="churnPriorFromFreq" sc="rw" k="13.5307">
<c n="DISCLOSE"/>
</s>
</f>
<f p="src/pagerank.cpp">
<s t="fn" n="pageRankDouble" sc="rw" amb="3" k="13.2458">
… [28 more display lines; full output is 3359 bytes on 1 raw line(s)]
`````


---

# zoom the detail ladder

## `./build/ripwire . --for="pagerank power iteration" --detail=2`

*Importance-weighted detail: FULL bodies for top-2, signatures for the rest.*

`````
<ctx task="pagerank power iteration" route="subtoken+body" root="." confidence="high" margin_pct="20" at="c7920353a" doc_mentions="5" schema="ripwire.for/v1" budget_bytes="7500" doc_mentions_capped="1" doc_mentions_total="16" est_tokens="4726">
<!-- ripwire for schema=ripwire.for/v1: bundle=/bodies=/reason= the body posture; d: cx= ccx= complexity, in= callers (absent cx/ccx/in = 0), churn= amp= change, clone= tested= 1, sc= scope, id=p::sc::n; total= shown= capped=1 if cut; task= the query; d pure=1 const/constexpr sig, next= the follow-up to paste; route= name-exact(X)|subtoken+body[:broad|:declined]; confidence=/margin_pct= head score drop (low=flat); t p= file outside sigs (weaker), r= rank (gap = trimmed); field name= type= owner= rel=: a member of owner=, rel=creates held by value, uses by reference/pointer; d layer=: built-in arch layer (game|infra|render|math|audio|ai|test) from a dir name in p= [doc mentions: 5 docs, 3 symbols; doc_mentions=] -->
<!-- root= is the crawl root; p= below is RELATIVE to it (single-root only; absent => p= is ingest's own path, unchanged); at=this commit(+dirty). dropped_positive="17" [budget_bytes= is the default BYTE ceiling this ranked payload was shaped against; it bounds that payload, not the whole document est_tokens prices] [docs_dropped=N: N shown rows have a doc comment not printed (r>24 always, r5..24 if capped)] [cut: doc_mentions_capped="1" doc_mentions_total="16" — an indexing cap dropped content not shown here]; lego/compose collapse to a counted stub by default (a disclosed cut): total= that section's own pre-cap row count, shown="0" capped="1" (nothing rendered here), next= names the sections=lego,compose flag that restores both sections byte-identically in one call est_tokens= prices this bundle in tokens -->
<sigs shown="23" total="40" capped="1" docs_dropped="11">
<d l="419" n="kScoreTieAbsEps" sc="rw" p="src/eval.h" churn="16" amp="28" pure="1" r="1" next="--expand=src/eval.h:kScoreTieAbsEps">
<doc>NodeId order. Renumbering an otherwise-identical graph (the exact &quot;same probe file, different so…</doc>inline constexpr float kScoreTieAbsEps = 1e-6f</d>
<d l="73" n="renderDisclosure" sc="rw" p="src/prconverge.h" cx="12" ccx="15" in="14" churn="3" amp="41" r="2">
<doc>Render one form of the disclosure. Empty string whenever there is nothing to say — no power it…</doc>inline std::string renderDisclosure( const RankDisclosure&amp; d, DiscloseAs as )</d>
<d l="99" n="pageRankDouble" sc="rw" p="src/pagerank.cpp" cx="19" ccx="34" in="2" churn="14" amp="44" tested="1" r="3">
<doc>The PageRank power iteration itself — the numeric kernel every ranked document&apos;s order comes f…</doc>PageRankRun pageRankDouble( const sparseCsr&lt;float&gt;&amp; inEdges, std::span&lt;const double&gt; weightedOutDegree, std::span&lt;const double&gt; teleport, std::span&lt;double&gt; r … [line truncated: 10 more bytes on this line]
<d l="51" n="RankDisclosure" sc="RankDisclosure" p="src/prconverge.h" churn="3" amp="27" r="4">
<doc>What a ranked document discloses about the power iteration that ordered it. `isPageRank == false…</doc>struct RankDisclosure</d>
<d l="474" n="rankByText" sc="rw" p="src/mcpverbs.h" cx="10" ccx="17" in="1" churn="309" amp="406" r="5">inline std::string rankByText( const std::string&amp; root, std::string_view mode, int topK, bool stable = false )</d>
<d l="5556" n="RankedGraph" sc="RankedGraph" p="src/graph.h" churn="245" amp="394" r="6">struct RankedGraph</d>
<d l="2206" n="kChurnRankLegend" sc="rw" p="src/serialize.h" churn="249" amp="387" pure="1" r="7">inline constexpr const char* kChurnRankLegend = &quot;&lt;!-- rank_by=churn: k= is PageRank re-run with the teleport BIASED by git CHANGE-FREQUENCY over window= &quot; &quot;(a c…</d>
<d l="1372" n="sliceRdIterationCeiling" sc="slicev" p="src/slice.h" cx="9" ccx="12" in="1" churn="51" amp="103" r="8">inline std::uint32_t sliceRdIterationCeiling() noexcept</d>
<d l="31" n="PageRankRun" sc="PageRankRun" p="src/pagerank.h" churn="8" amp="37" r="9">struct PageRankRun</d>
<d l="7386" n="navRelevanceWeight" sc="rw" p="src/graph.h" cx="2" ccx="1" in="2" churn="245" amp="396" r="10">inline std::uint32_t navRelevanceWeight( const Graph&amp; g, NodeId n ) noexcept</d>
<d l="5565" n="rankGraphTeleport" sc="rw" p="src/graph.h" cx="5" ccx="8" in="7" churn="245" amp="401" r="11">inline RankedGraph rankGraphTeleport( const Graph&amp; g, const std::vector&lt;float&gt;&amp; p, float alpha = 0.85f )</d>
<d l="58" n="HOT_FILES" p="scripts/optremarks.py" churn="10" amp="60" r="12">HOT_FILES = ( &quot;src/pagerank.cpp&quot;, # the power-iteration loop — G2&apos;s no-allocation scope &quot;src/infra/radixSort.h&quot;, # LSD radix entry points &quot;src/infra/radixSort…</d>
<d l="1247" n="kPowerShellPathPrependScope" sc="rw::oswin" p="src/infra/os_win32_logic.h" layer="infra" churn="20" amp="50" pure="1" r="13">inline constexpr std::string_view kPowerShellPathPrependScope = &quot;in PowerShell, for this window</d>
<d l="1241" n="powerShellPathPrependHint" sc="rw::oswin" p="src/infra/os_win32_logic.h" layer="infra" cx="1" in="4" churn="20" amp="54" tested="1" r="14">inline std::string powerShellPathPrependHint( std::string_view programDir ) noexcept</d>
<d l="1207" n="powerShellSingleQuote" sc="rw::oswin" p="src/infra/os_win32_logic.h" layer="infra" cx="8" ccx="6" in="2" churn="20" amp="52" tested="1" r="15">inline std::string powerShellSingleQuote( std::string_view s ) noexcept</d>
<d l="967" n="path_prepend_hint" sc="rw::os" p="src/infra/os.h" layer="infra" cx="1" in="1" churn="29" amp="70" r="16">inline std::string path_prepend_hint( std::string_view dir )</d>
<d l="6303" n="Wave-2 adversarial verification (2026-08-19) — six probes against `aa97c9e`" sc="6. Correctness and quality instruments" p="docs/EVALS.md" churn="834" amp="1058" r="17">### Wave-2 adversarial verification (2026-08-19) — six probes against `aa97c9e`</d>
<d l="227" n="Same answer, a fraction of the tokens — read this table first if your agent is on a budget" sc="Rip&apos;n Fast. Fewer Tokens. Better Code." p="README.md" churn="889" amp="889" r="18">### Same answer, a fraction of the tokens — read this table first if your agent is on a budget</d>
<d l="1693" n="Anchor-only auto bodies — T3 substitution round, PRE-REGISTERED 2026-08-22 (before any fix code)" sc="4. Ranking changes, measured" p="docs/EVALS.md" churn="834" amp="1058" r="19">### Anchor-only auto bodies — T3 substitution round, PRE-REGISTERED 2026-08-22 (before any fix code)< … [line truncated: 3 more bytes on this line]
<d l="36" n="Background — read these, in this order" sc="Certified ranking order — say how far down the order is provably right" p="prompts/help-wanted/certified-ranking-order.md" churn="1" r="20">## Background — read these, in this order</d>
<d l="117" n="Design space and constraints" sc="Certified ranking order — say how far down the order is provably right" p="prompts/help-wanted/certified-ranking-order.md" churn="1" r="21">## Design space and constraints</d>
<d l="97" n="COLD_FILES" p="scripts/optremarks.py" churn="10" amp="60" r="22">COLD_FILES = ( # ── ingest sections that are not on the per-file / per-symbol default path ──────────────────── ( &quot;src/ingest_astquery.h&quot;, &quot;the --match / --lint AS … [line truncated: 40 more bytes on this line]
… [106 more display lines; full output is 13660 bytes on 72 raw line(s)]
`````

## `./build/ripwire . --pack-signatures --top-k=10`

*Body-elided decl skeletons — recounted on this corpus. Measured as element bytes: the <d> signature+doc elements --pack-signatures emits, against the SAME symbols' full <b> bodies from --expand, with the CORPUS-ROOT PREFIX SUBTRACTED FROM BOTH SIDES. That subtraction is the whole methodology and the figure is meaningless without it: the root repeats inside every element's id= and p=, it is not what this verb elides, and counting it makes the headline a function of how deep the checkout happens to sit on disk — on one corpus, three spellings of the same root read 18.6 points apart before the subtraction and agree exactly after it. Root-neutralised on THIS repo: 92.7% fewer bytes at top-10, 88.7% at top-50, 87.6% at top-100 (re-derived 2026-09-20 when the native Windows port landed: src/infra/os_win32.cpp and os_win32_logic.h are ~3,900 lines of new, heavily commented infra that the ranked top-10/50/100 now reach, and their bodies are this ratio's DENOMINATOR, so the figure rises without --pack-signatures eliding anything new, from top-50 87.1. Measured by test/showcasecapturecheck.sh's own recount arm on the combined tree, which is the gate that would otherwise report the drift; before that, re-derived 2026-09-17 at the self-check macro vocabulary rename: VERIFY/VERIFY_TEXT/VERIFY_DEBUG_ONLY/VERIFY_NOT_REACHED/VERIFY_SAME_THREAD/VERIFY_NO_ALIAS*/DYNMAP_VERIFY/DEGRADED_PATH_ALERT renamed to ASSUME/EXPECTS/ENSURES/DASSERT/UNREACHABLE/ASSUME_SAME_THREAD*/ASSUME_NO_ALIAS*/DYNMAP_ASSUME/DISCLOSE (plus new VALIDATE sites) across 839 identifier renames in 179 files, and a hand-written Diagnostics.h/diagnostics.cpp replacing the old ones outright: this moves both WHICH symbols the ranked top-10/50/100 hold and how large their bodies are, from top-50 85.2. A real re-derivation of a corpus that changed, not a tolerance edit; previously re-derived 2026-09-12 when the <d> rows dropped the path-repeating id= for the short sc= scope: the signature side shrank, the bodies did not; before that, 89.5% / 81.8% / 84.3% re-derived 2026-09-10 at the sibs= cap raise: kMaxExpandSibs went 8 -> 100, so --expand's <b> bodies now carry the file context the old cap hid — 89.3% of all sibling names — and the body side is this ratio's DENOMINATOR, so the figure rises without --pack-signatures eliding anything new. Measured on a fixed tree with the top-50 membership and the signature side unchanged: top-50 from 71.0. A real re-derivation of a corpus that changed, not a tolerance edit; previously re-derived 2026-09-09 at the printf-family -> std::print conversion: converting ~1,500 emitter call sites to rw::emitTo/emitRaw/formatTo across 93 files changes how large the ranked symbols' BODIES are, and the body side is this ratio's denominator — top-50 from 72.3. A real re-derivation of a corpus that changed, not a tolerance edit; previously re-derived 2026-09-08 at the confident-zero round, issues #62/#63/#66: that change adds symbols to src/graphlegend.h and the new src/preprocdead.h and re-homes two long comment blocks from call sites onto the helpers they explain, which moves both WHICH symbols the ranked top-50 holds and how large their bodies are — top-50 from 74.0. A real re-derivation of a corpus that changed, not a tolerance edit; previously re-derived 2026-09-06 at the stranger-audit fix round: the doctor, cache-sweep and html-provenance bodies grew this corpus's BODY side, moving top-50 from 75.6 — a real re-derivation, not a tolerance edit; before that, re-derived 2026-09-05 at the capture-audit close: lane L7's P16 caps --expand's sibs= at 8 names, which SHRINKS the body side of this ratio and moved the figure down from 84.5/80.2/80.6 — the V1 2026-08-15 re-center, when sibs=/inc= first grew the body side from 70.0/61.0/63.8, in reverse; both were real re-derivations, not tolerance edits). top-50 is the number to quote, because the sigs payload is top-50 regardless of --top-k and is therefore what THIS command emits. A single small/trivial body can still invert it (signature+doc bigger than the body), like the --format=columnar sibling below. test/showcasecapturecheck.sh (C) re-derives all three from this repo every run, in the same quantity, and fails if the caption and the recount drift apart.*

`````
<ctx schema="ripwire.pack-signatures/v1">
<!-- ripwire pack-signatures schema=ripwire.pack-signatures/v1: the ranked map plus <sigs>
<d l= n= sc= pure=> signature rows. est_tokens=: price as emitted (an upper bound under compact). root=: p= relative to it. pr_iters=N: PageRank iterations. declined=K: K calls left unbound (no evidence chose one def). external=K: K calls proven outside the tree, no edge. locality_pinned=K: K calls  … [line truncated: 1304 more bytes on this line]
<!-- t=modscope=a-file's-MODULE-SCOPE(n=<file-scope>):the-statements-outside-every-named-definition,where-a-top-level-call-and-an-anonymous-callback-body's-calls-live;a-CALLER-never-a-callee(nothing-in-the-source-can-name-it)-with-no-body-to-expand;a-file-with-no-such-call-has-no-such-row -->
<!-- files=2484 symbols=23851 edges=34236 shown=10 est_tokens=4730 ambiguous=10278 unresolved=12878 locality_pinned=12 external=7345 declined=9922 extent_suspect_syms=10 macro_blanked_files=7 skipped_oversize=15 unindexed="txt:73,tsv:49,jsonl:26,scm:23,expected:15,xml:13" unindexed_exts=20 order=important-first -->
<r root="." est_tokens="5454" pr_iters="28">
<f p="src/infra/svector.h" layer="infra">
<s t="method" n="buf" sc="svector" overloads="2" k="0.0072">
</s>
<s t="method" n="push_back" sc="svector" amb="2" k="0.0053">
<c n="buf" prov="split"/>
<c n="buf" prov="split"/>
<c n="grow"/>
</s>
</f>
<f p="src/resolve.h">
<s t="method" n="empty" sc="RubyConstantIndex" k="0.0071">
</s>
</f>
<f p="src/infra/os_win32_logic.h" layer="infra">
<s t="method" n="ok" sc="WidePath" k="0.0063">
</s>
<s t="method" n="size" sc="WidePath" k="0.0049">
<c n="ok"/>
</s>
</f>
<f p="src/notes.h">
<s t="method" n="empty" sc="NoteIndex" k="0.0053">
</s>
</f>
… [135 more display lines; full output is 11815 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --outline=rankGraphTeleport --top-k=0`

*Control-flow skeleton of one symbol, payload-only via the new --top-k=0.*

`````
<!-- ripwire pack-signatures schema=ripwire.pack-signatures/v1: the ranked map plus <sigs>
<d l= n= sc= pure=> signature rows. est_tokens=: price as emitted (an upper bound under compact). root=: p= relative to it. -->
<ctx schema="ripwire.pack-signatures/v1" root="." est_tokens="327">
<outline>
<o t="fn" l="5565" p="src/graph.h" n="rankGraphTeleport">
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
<!-- ripwire pack-signatures schema=ripwire.pack-signatures/v1: the ranked map plus <sigs>
<d l= n= sc= pure=> signature rows. est_tokens=: price as emitted (an upper bound under compact). root=: p= relative to it. -->
<ctx schema="ripwire.pack-signatures/v1" root="." est_tokens="327">
<outline>
<o t="fn" l="5565" p="src/graph.h" n="rankGraphTeleport">
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
<ctx schema="ripwire.expand/v1" root="." est_tokens="1261">
<!-- ripwire expand schema=ripwire.expand/v1: full bodies: <bodies shown= total= capped=> of <b t= l= p= n= sibs= sibs_total= sibs_capped= inc=>; <calls>
<c n= l=> resolved callees. window: shown= total= capped= (capped=1 cut). sibs_capped=/inc_capped=: 1 = cut. est_tokens=: price as emitted (an upper bound under compact). root=: p= relative to it. scrubbed=1: this CDATA is not the bytes (]]> split or C0 replaced). redacted=1: a credential shape rewr … [line truncated: 165 more bytes on this line]
<bodies shown="1" total="1" capped="0">
<b t="fn" l="5565" p="src/graph.h" n="rankGraphTeleport" sibs="Graph,provLabel,langCompatible,namespaceCompatible,kCommonNameMul,kCommonNameDefThreshold,kPrivateNameMul,kSpecificNameMul,kSpecificMinLen,kSpecificMinWords,wordCount,weight,decodeJniName,splitSegments,isTemplateSegment,pathsMatch,method … [line truncated: 1808 more bytes on this line]
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
}]]><calls total="8"><c n="biasPrior" l="5524">inline std::vector&lt;float&gt; biasPrior( const Graph&amp; g, const std::vector&lt;float&gt;&amp; p )</c><c n="PROFILE_SCOPE_DESCRIBE" l="1279">#define PROFILE_SCOPE_DESCRIBE( desc )</c><c n="PROFILE_SCOPE_DESCRIBE" l="1293">#define PROFILE_SCOPE_DESCR … [line truncated: 480 more bytes on this line]
`````

## `./build/ripwire . --expand=rankGraphTeleport:1-12 --top-k=0`

*Body SLICE: lines 1..12 of the symbol's own body, with lines="lo-hi/total" marking it partial.*

`````
<ctx schema="ripwire.expand/v1" root="." est_tokens="1100">
<!-- ripwire expand schema=ripwire.expand/v1: full bodies: <bodies shown= total= capped=> of <b t= l= p= n= sibs= sibs_total= sibs_capped= inc=>; <calls>
<c n= l=> resolved callees. window: shown= total= capped= (capped=1 cut). sibs_capped=/inc_capped=: 1 = cut. est_tokens=: price as emitted (an upper bound under compact). root=: p= relative to it. scrubbed=1: this CDATA is not the bytes (]]> split or C0 replaced). redacted=1: a credential shape rewr … [line truncated: 165 more bytes on this line]
<bodies shown="1" total="1" capped="0">
<b t="fn" l="5565" p="src/graph.h" n="rankGraphTeleport" lines="1-12/29" sibs="Graph,provLabel,langCompatible,namespaceCompatible,kCommonNameMul,kCommonNameDefThreshold,kPrivateNameMul,kSpecificNameMul,kSpecificMinLen,kSpecificMinWords,wordCount,weight,decodeJniName,splitSegments,isTemplateSegment,p … [line truncated: 1824 more bytes on this line]
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
        for( const double value : teleport )]]><calls total="8"><c n="biasPrior" l="5524">inline std::vector&lt;float&gt; biasPrior( const Graph&amp; g, const std::vector&lt;float&gt;&amp; p )</c><c n="PROFILE_SCOPE_DESCRIBE" l="1279">#define PROFILE_SCOPE_DESCRIBE( desc )</c><c n="PROFILE_SCOPE_DES … [line truncated: 523 more bytes on this line]
`````

## `./build/ripwire . --expand=compressBody --top-k=0 --compress`

*Comments stripped + blank runs collapsed — compressBody is the function that implements --compress itself, chosen because it is comment-heavy enough to show a real reduction (the previously captioned symbol had no comments or blank runs, so before/after were byte-identical under a caption promising a difference).*

`````
<ctx schema="ripwire.expand/v1" root="." est_tokens="2060">
<!-- ripwire expand schema=ripwire.expand/v1: full bodies: <bodies shown= total= capped=> of <b t= l= p= n= sibs= sibs_total= sibs_capped= inc=>; <calls>
<c n= l=> resolved callees. window: shown= total= capped= (capped=1 cut). sibs_capped=/inc_capped=: 1 = cut. est_tokens=: price as emitted (an upper bound under compact). root=: p= relative to it. scrubbed=1: this CDATA is not the bytes (]]> split or C0 replaced). redacted=1: a credential shape rewr … [line truncated: 165 more bytes on this line]
<bodies shown="1" total="1" capped="0" compress="1">
<b t="fn" l="3877" p="src/serialize.h" n="compressBody" sibs="xmlSafeByte,xmlScrubIsLossy,xmlControlCharRef,kXmlEscapeByteset,escapeXml,writeMultiRootTable,kMultiRootTableLegend,multiRootTableLegend,xmlCommentText,ctxRootOpen,ctxRootJsonScrubKeys,appendCdataSafe,XmlWriter,XmlWriter,XmlWriter,operato … [line truncated: 1835 more bytes on this line]
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
… [170 more display lines; full output is 7866 bytes on 195 raw line(s)]
`````

## `./build/ripwire . --expand=readAckRecords --top-k=0 --no-redact`

*--no-redact: emit bodies verbatim (credential redaction is on by default).*

`````
<ctx schema="ripwire.expand/v1" root="." est_tokens="3219">
<!-- ripwire expand schema=ripwire.expand/v1: full bodies: <bodies shown= total= capped=> of <b t= l= p= n= sibs= sibs_total= sibs_capped= inc=>; <calls>
<c n= l=> resolved callees. window: shown= total= capped= (capped=1 cut). sibs_capped=/inc_capped=: 1 = cut. est_tokens=: price as emitted (an upper bound under compact). root=: p= relative to it. scrubbed=1: this CDATA is not the bytes (]]> split or C0 replaced). redacted=1: a credential shape rewr … [line truncated: 336 more bytes on this line]
<bodies shown="3" total="3" capped="0">
<b t="fn" l="6693" p="src/quality.h" n="readAckRecords" sibs="&lt;file-scope&gt;,kBaselineFile,kMinCloneTokens,kCcxBar,kLocBar,kNestBar,kParamBar,kShortHorizonDays,kShortHorizonMinCommits,kReusedHelperMinFanin,kMinorCcxDelta,kMinorLocDelta,kMinorParamDelta,kMaterialGrowthPct,kSubBarGrowthPct,subBarG … [line truncated: 1863 more bytes on this line]
<![CDATA[inline gtl::btree_map<std::string, AckRecord> readAckRecords( const std::string& path, std::size_t& badLines );]]>
</b>
<b t="fn" l="6695" p="src/quality.h" n="readAckRecords" sibs="&lt;file-scope&gt;,kBaselineFile,kMinCloneTokens,kCcxBar,kLocBar,kNestBar,kParamBar,kShortHorizonDays,kShortHorizonMinCommits,kReusedHelperMinFanin,kMinorCcxDelta,kMinorLocDelta,kMinorParamDelta,kMaterialGrowthPct,kSubBarGrowthPct,subBarG … [line truncated: 1863 more bytes on this line]
<![CDATA[inline gtl::btree_map<std::string, AckRecord> readAckRecords( const std::string& path )
{
    std::size_t ignored = 0;
    return readAckRecords( path, ignored );
}]]><calls total="1"><c n="readAckRecords" l="6701">inline gtl::btree_map&lt;std::string, AckRecord&gt; readAckRecords( const std::string&amp; path, std::size_t&amp; badLines )</c></calls></b><b t="fn" l="6701" p="src/quality.h" n="readAckRecords" sibs="&lt;file-scope&gt;,kBaselineFile,kMinCloneToke … [line truncated: 2174 more bytes on this line]
{
    badLines = 0;
    gtl::btree_map<std::string, AckRecord> out;
    // openRegularFileStream, not a stream opened on the name: a FIFO planted at the ledger's name blocked that open until
    // a writer appeared, so --quality-delta hung before any output, and a link to /dev/zero never reached end of file.
    // Anything that is not a regular file now reads as no ledger, and stderr says so (docparse.h). Still one line at a
    // time, as the std::ifstream it replaces read it: a large ledger is never held whole.
    rw::pathguard::NoFollowRead ledger = docparse::detail::openRegularFileStream( "the quality-acks ledger", path );
    std::string                 line;
    while( ledger.readLine( line ) )
    {
        while( !line.empty() && ( line.back() == '\r' || line.back() == '\n' ) )
        {
            line.pop_back(); // CRLF tolerance (merged-in Windows checkout)
        }
        if( line.empty() || line[0] == '#' )
        {
… [46 more display lines; full output is 12269 bytes on 68 raw line(s)]
`````

## `./build/ripwire . --pack-top-n=3 --top-k=0`

*Pack the top-3 ranked symbols' full bodies (deprecated verb; see stderr).*

`````
<ctx schema="ripwire.pack-top-n/v1" root="." est_tokens="17460">
<!-- ripwire pack-top-n schema=ripwire.pack-top-n/v1: the ranked map plus <src p=> bodies of the top-N symbols. window: shown= total= capped= (capped=1 cut). est_tokens=: price as emitted (an upper bound under compact). root=: p= relative to it. <src truncated=1 lines=1-K/T>: cut at a line end at the byte budget; K of its T lines. <src_cut shown= total= capped=1 budget_bytes=>: files served of the top-N asked, the rest over the byte ceiling; unreadable=N not readable. -->
<src_cut shown="2" total="3" capped="1" budget_bytes="65536"/>
<src p="./src/infra/svector.h">
<![CDATA[#pragma once

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
… [1088 more display lines; full output is 66245 bytes on 1114 raw line(s)]
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
<!-- ripwire metrics schema=ripwire.metrics/v1: the ranked map with per-symbol metrics: in/out, cx/ccx, loc, params, nest, humps/deep, locals, cbo, amp, tested, ev. est_tokens=: price as emitted (an upper bound under compact). root=: p= relative to it. pr_iters=N: PageRank iterations. declined=K: K calls left unbound (no evidence chose one def). external=K: K calls proven outside the tree, no edge. locality_pinned=K: K calls pinned by locality alone (a guess). extent_suspect_syms=K: K defs failed containment, corpus-wide. macro_blanked_files=K: K files indexed from a macro-blanked re-parse. prov=scip|binding|import|split|final-segment: how that <c> edge bound (absent: one unique name); split = one arm of an amb= pick; final-segment = a qualified type matched by last name only. files=/symbols=: files and symbols indexed; edges= distinct call edges; shown= symbols printed, a merged row counting each def; ambiguous= calls split over several defs, corpus-wide; unresolved= calls with in-tree evidence and no edge (every def language-filtered or unreachable, or binding refused); order= rows by rank (important-first, important-last; (auto:fill) = flipped past a size threshold) or by path (stable). skipped_oversize=K: K files over a size ceiling, not indexed. unindexed=ext:N: N text files of that extension no grammar reads (6 extensions at most). unindexed_exts=E: E such extensions in all, the list cut. <s tested=1>: a non-test row an indexed test transitively reaches (absent otherwise, never 0). sc=: enclosing scope; the full id is p::sc::n (p= of the row or its <f>) and selectors take it. amb=K: K calls split over several defs. locals_floor=1: locals= is a floor. role=hub: in= is 8 or more. s in= out= cx= ccx= loc= params= nest= cbo= amp=: callers, callees, cyclomatic/cognitive complexity, lines, parameters, nesting depth, coupled types, callers + co-changed files. ev=/ev_why=: essential complexity (2+: jumps block extract-method; absent: 1) / the jumps behind it, tag:count. ev_floor=1: ev= is a FLOOR; noreturn calls, macro-hidden exits and unresolved gotos are unseen. layer=: built-in arch layer (game|infra|render|math|audio|ai|test) from a dir name in p=; absent if none. l=N: start line; only on a same-name overload's row, one row per body (bodyless decls fold into overloads=). -->
<!-- t=modscope=a-file's-MODULE-SCOPE(n=<file-scope>):the-statements-outside-every-named-definition,where-a-top-level-call-and-an-anonymous-callback-body's-calls-live;a-CALLER-never-a-callee(nothing-in-the-source-can-name-it)-with-no-body-to-expand;a-file-with-no-such-call-has-no-such-row -->
<!-- files=2484 symbols=23851 edges=34236 shown=10 est_tokens=2132 ambiguous=10278 unresolved=12878 locality_pinned=12 external=7345 declined=9922 extent_suspect_syms=10 macro_blanked_files=7 skipped_oversize=15 unindexed="txt:73,tsv:49,jsonl:26,scm:23,expected:15,xml:13" unindexed_exts=20 order=important-first -->
<r schema="ripwire.metrics/v1" root="." est_tokens="2132" pr_iters="28">
<f p="src/infra/svector.h" layer="infra">
<s t="method" n="buf" sc="svector" l="125" in="29" out="0" cx="2" ccx="1" role="hub" loc="1" params="0" nest="1" locals="0" locals_floor="1" cbo="0" amp="52" tested="1" k="0.0072">
</s>
<s t="method" n="buf" sc="svector" l="126" in="29" out="0" cx="2" ccx="1" role="hub" loc="1" params="0" nest="1" locals="0" locals_floor="1" cbo="0" amp="52" tested="1" k="0.0072">
</s>
<s t="method" n="push_back" sc="svector" in="694" out="3" cx="2" ccx="1" role="hub" loc="5" params="1" nest="1" locals="1" locals_floor="1" cbo="3" amp="717" tested="1" amb="2" k="0.0053" ev="2" ev_floor="1" ev_why="guard-return:1">
<c n="buf" prov="split"/>
<c n="buf" prov="split"/>
<c n="grow"/>
</s>
</f>
<f p="src/resolve.h">
<s t="method" n="empty" sc="RubyConstantIndex" in="1200" out="0" cx="1" ccx="0" role="hub" loc="1" params="0" nest="0" locals="0" locals_floor="1" cbo="0" amp="1377" tested="1" k="0.0071">
</s>
</f>
<f p="src/infra/os_win32_logic.h" layer="infra">
<s t="method" n="ok" sc="WidePath" in="7" out="0" cx="1" ccx="0" loc="1" params="0" nest="0" locals="0" locals_floor="1" cbo="0" amp="57" tested="1" k="0.0063">
</s>
<s t="method" n="size" sc="WidePath" in="346" out="1" cx="2" ccx="1" role="hub" loc="1" params="0" nest="1" locals="0" locals_floor="1" cbo="1" amp="396" tested="1" k="0.0049">
<c n="ok"/>
</s>
</f>
<f p="src/notes.h">
<s t="method" n="empty" sc="NoteIndex" in="1093" out="0" cx="1" ccx="0" role="hub" loc="1" params="0" nest="0" locals="0" locals_floor="1" cbo="0" amp="1174" tested="1" k="0.0053">
</s>
</f>
… [18 more display lines; full output is 5295 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --deps`

*File->file dependency graph (god-files, cycles).*

`````
<!-- ripwire deps schema=ripwire.deps/v1: file-to-file include/import view, heaviest cone first: <f p= afferent= includes= instab= transitive=>, <health>, <godfiles>, <cycles>. window: shown= total= capped= has_more= next_offset= offset= limit= (capped=1 cut; next_offset= pastes as offset=). root=: p= relative to it. files=N: files with at least one include/import directive; this listing's denominator (health files= = corpus). violations=N: edges into a file more unstable by over 0.05 (Martin I); only the worst 12 are listed. from=: the including file of a stable-deps violation; it depends on the more unstable to=. gap=: instab of to= minus instab of from=, project includes only; worst first. health dep_files=N: dependency-capable files (dep_langs=), the ccd/acd/nccd denominator. health dep_langs=: the languages dep_files= counts; compare its numbers across builds only when equal. ccd=/acd=/nccd=: Lakos: sum of per-file transitive cones (self incl) / per file / over a balanced tree's. health shape=: the nccd= verdict: horizontal below 1, vertical 1 to 2, tangled above 2 (a heuristic). health lazy_edges=N: in-closure (lazy) include pairs kept OUT of cones, cycles and ccd; absent at 0. cycle size=/cost=: files in that include cycle / size squared, the cycle's share of ccd=. cycle cut=/cutrefs=: SUGGESTED edge to break it (fewest directives) / that edge's directive count; nothing cut. -->
<deps schema="ripwire.deps/v1" files="903" shown="40" capped="1" total="903" has_more="1" next_offset="40" offset="0" limit="0" root=".">
<health files="2484" dep_files="2141" ccd="9263" acd="4.3" nccd="0.43" shape="horizontal" lazy_edges="61" dep_langs="cpp,py,ts,go,rs,swift,objc,js,sh,java,rb,cs,c,php,lua,ex,kt"/>
<godfiles total="445" shown="12" capped="1">
<f p="test/lib/clean-env.sh" afferent="181"/>
<f p="src/infra/emit.h" afferent="86"/>
<f p="src/model.h" afferent="85"/>
<f p="src/infra/Diagnostics.h" afferent="58"/>
<f p="src/serialize.h" afferent="39"/>
<f p="src/graph.h" afferent="36"/>
<f p="src/infra/os.h" afferent="35"/>
<f p="scripts/cxxstd.sh" afferent="27"/>
<f p="src/infra/jsonesc.h" afferent="25"/>
<f p="src/ingest.h" afferent="24"/>
<f p="src/arch.h" afferent="22"/>
<f p="src/docparse.h" afferent="22"/>
</godfiles>
<stabledeps violations="30">
<v from="src/gitstamp.h" to="src/quality.h" gap="0.45"/>
<v from="src/graph.h" to="src/pincensus.h" gap="0.45"/>
<v from="src/infra/sortutil.h" to="src/infra/radixSort.h" gap="0.44"/>
<v from="src/model.h" to="src/structlayout.h" gap="0.44"/>
<v from="src/infra/profileScope.h" to="src/infra/profilePmc.h" gap="0.33"/>
<v from="src/testmap.h" to="src/jsrunner.h" gap="0.30"/>
<v from="src/model.h" to="src/infra/profileScope.h" gap="0.28"/>
<v from="src/filter.h" to="src/queryshape.h" gap="0.25"/>
<v from="test/cyclecutfix/b.h" to="test/cyclecutfix/c.h" gap="0.25"/>
<v from="test/cyclecutfix/c.h" to="test/cyclecutfix/a.h" gap="0.25"/>
<v from="src/testmap.h" to="src/pythonrunner.h" gap="0.23"/>
<v from="src/quality.h" to="src/valuerefindex.h" gap="0.21"/>
… [888 more display lines; full output is 23141 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --hotspots`

*Complexity x recent git churn (maintenance pain).*

**wall time: 1.07s**

`````
<!-- ripwire hotspots schema=ripwire.hotspots/v1: maintenance pain = churn x ccx over window=: <f p= churn= ccx= score= top= top_ccx= top_l=>; unranked_*= no churn/complexity. window: shown= total= capped= has_more= next_offset= offset= limit= (capped=1 cut; next_offset= pastes as offset=). at=: commit+dirty+shallow. root=: p= relative to it. files=/ranked=: files in the window / those with both churn and complexity; ranked + unranked_no_churn + unranked_no_complexity = files. unranked_no_churn=/unranked_no_complexity=: files left out for no commit in window= / no measured complexity. -->
<!-- extent_suspect_syms=K on a row = K of the file's functions failed an extent/scope containment check (the map, the bundles and the skipped verb mark each one, reasons and all) and are LEFT OUT of that row's ccx=, score= and top=, so its ccx= is a FLOOR of the file's true sum rather than a total. unranked_extent_suspect= counts files with commits whose every scorable function was left out that way (or whose trusted remainder scores 0), so ranked= + unranked_no_churn= + unranked_no_complexity= + unranked_extent_suspect= = files= exactly. Absent = nothing excluded. -->
<hotspots schema="ripwire.hotspots/v1" window="12mo@HEAD" files="2484" ranked="663" unranked_no_churn="0" unranked_no_complexity="1819" unranked_extent_suspect="2" shown="40" capped="1" total="663" has_more="1" next_offset="40" offset="0" limit="0" root="." at="c7920353a">
<f p="src/graph.h" churn="245" ccx="2842" score="696290" top="buildGraph" top_ccx="909" top_l="3578"/>
<f p="src/quality.h" churn="357" ccx="1687" score="602259" top="computeDelta" top_ccx="324" top_l="7967"/>
<f p="src/serialize.h" churn="249" ccx="2082" score="518418" top="serialize" top_ccx="271" top_l="2602"/>
<f p="src/main.cpp" churn="414" ccx="1165" score="482310" top="dispatchMain" top_ccx="471" top_l="4108"/>
<f p="src/mcpverbs.h" churn="309" ccx="1146" score="354114" top="runBatchSub" top_ccx="138" top_l="5220"/>
<f p="src/cli.h" churn="436" ccx="642" score="279912" top="parseArgs" top_ccx="213" top_l="5180"/>
<f p="src/resolve.h" churn="122" ccx="1812" score="221064" top="buildPreciseIncludeAdjWithContext" top_ccx="84" top_l="4196"/>
<f p="src/mcp.h" churn="125" ccx="927" score="115875" top="dispatchMcpLine" top_ccx="735" top_l="1118"/>
<f p="src/verbs_report.h" churn="76" ccx="1136" score="86336" top="runStructureText" top_ccx="258" top_l="3143"/>
<f p="src/verbs_navigate.h" churn="124" ccx="668" score="82832" top="runVerify" top_ccx="142" top_l="1554"/>
<f p="src/verbs_for.h" churn="103" ccx="672" score="69216" top="runForLens" top_ccx="322" top_l="2221"/>
<f p="src/ingest_sidecap.h" churn="81" ccx="840" score="68040" top="captureTagsFacts" top_ccx="403" top_l="1730"/>
<f p="src/ingest_cache.h" churn="185" ccx="343" score="63455" top="saveCache" top_ccx="95" top_l="2869"/>
<f p="src/compactlegend.h" churn="185" ccx="313" score="57905" top="applyCompactDialectOnce" top_ccx="47" top_l="2056"/>
<f p="src/verbs_quality.h" churn="79" ccx="544" score="42976" top="runQualityDelta" top_ccx="288" top_l="1111"/>
<f p="src/lexical.h" churn="62" ccx="689" score="42718" top="lexicalScoresTiered" top_ccx="450" top_l="470"/>
<f p="src/slice.h" churn="51" ccx="831" score="42381" top="sliceClassify" top_ccx="183" top_l="608"/>
<f p="src/crossref.h" churn="68" ccx="618" score="42024" top="streamBlobs" top_ccx="43" top_l="509"/>
<f p="src/gitmine.h" churn="59" ccx="664" score="39176" top="applyCoChangeBoost" top_ccx="95" top_l="3030"/>
<f p="src/ingest_crawl.h" churn="66" ccx="495" score="32670" top="collectSources" top_ccx="90" top_l="1546"/>
<f p="src/ingest_binds.h" churn="47" ccx="670" score="31490" top="bindsVisitNode" top_ccx="85" top_l="2387"/>
<f p="src/packtask.h" churn="81" ccx="386" score="31266" top="packTaskBundleText" top_ccx="213" top_l="1409"/>
<f p="src/verbs_change.h" churn="70" ccx="438" score="30660" top="runChangeViews" top_ccx="157" top_l="245"/>
<f p="src/ingest_astquery.h" churn="41" ccx="720" score="29520" top="astQueryGrouped" top_ccx="260" top_l="837"/>
<f p="src/search.h" churn="50" ccx="557" score="27850" top="grepCollect" top_ccx="59" top_l="1405"/>
<f p="src/ingest_relations.h" churn="45" ccx="588" score="26460" top="captureFields" top_ccx="81" top_l="782"/>
<f p="src/skillscan.h" churn="47" ccx="521" score="24487" top="scanSkillTextOn" top_ccx="199" top_l="1162"/>
… [14 more display lines; full output is 5750 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --clones`

*Token-normalized duplicate bodies.*

**wall time: 2.55s**

`````
<!-- ripwire clones schema=ripwire.clones/v1: similar normalized-token bodies: <group type=2|3 gid= tokens= n= similarity=> of <f n= p=>; dup_loc=/dup_pct=. window: shown= total= capped= has_more= next_offset= offset= limit= (capped=1 cut; next_offset= pastes as offset=). root=: p= relative to it. groups=/type3=: Type-2 and Type-3 group totals over all groups; total= is their sum. exempt_groups=N: groups whose members all sit on fixture/shell-runner paths quality-delta duplication ignores. idiom_groups=/demoted_groups=: groups of one recognized idiom / those quality-delta demotes to minor; floors. clone_groups=N: clusters after merging pairs (rows sharing gid=); a floor under type3_capped=1. total_loc=N: lines of every function body the detector considered; dup_pct= is dup_loc= over it. group exempt=fixture|shell-runner: every member is on such a path; quality-delta duplication ignores it. group idiom=: the recognized shape every member spells: threshold-ladder, switch-name-table, builder-chain. -->
<clones schema="ripwire.clones/v1" groups="118" type3="523" exempt_groups="353" idiom_groups="19" demoted_groups="12" clone_groups="312" dup_loc="6852" total_loc="198744" dup_pct="3.4" shown="80" capped="1" total="641" has_more="1" next_offset="80" offset="0" limit="0" root=".">
<group type="2" gid="49" tokens="338" n="3">
<f n="rw_is_ripwire_call" p="hooks/ripwire-claude-route.sh:181"/>
<f n="rw_is_ripwire_call" p="hooks/ripwire-codex-route.sh:104"/>
<f n="rw_is_ripwire_call" p="hooks/ripwire-nudge.sh:618"/>
</group>
<group type="2" gid="212" tokens="213" n="2" exempt="shell-runner">
<f n="call_sites" p="test/declinecheck.sh:114"/>
<f n="call_sites" p="test/usesselectorcheck.sh:49"/>
</group>
<group type="2" gid="266" tokens="211" n="4" exempt="shell-runner">
<f n="batch_sub" p="test/mcpclidiffcheck.sh:64"/>
<f n="batch_sub" p="test/mcptranchecheck.sh:55"/>
<f n="batch_sub" p="test/mcpw2fixcheck.sh:52"/>
<f n="batch_sub" p="test/mcpw3fixcheck.sh:51"/>
</group>
<group type="2" gid="48" tokens="163" n="3">
<f n="rw_cmd_word" p="hooks/ripwire-claude-route.sh:151"/>
<f n="rw_cmd_word" p="hooks/ripwire-codex-route.sh:74"/>
<f n="rw_cmd_word" p="hooks/ripwire-nudge.sh:588"/>
</group>
<group type="2" gid="188" tokens="153" n="2" exempt="shell-runner">
<f n="mcp_text" p="test/blindspotcheck.sh:120"/>
<f n="mcp_text" p="test/xmlwellformed.sh:320"/>
</group>
<group type="2" gid="284" tokens="151" n="3" exempt="shell-runner">
<f n="monotonic_check" p="test/pyimportprecisecheck.sh:89"/>
<f n="monotonic_check" p="test/rustimportprecisecheck.sh:141"/>
<f n="monotonic_check" p="test/tsimportprecisecheck.sh:170"/>
… [307 more display lines; full output is 16180 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --cochange`

*Files that change together in git (hidden coupling).*

**wall time: 1.69s**

`````
<!-- ripwire cochange schema=ripwire.cochange/v1: files that change together in git: <pair a= b= together= deg= conf_ab= conf_ba= surprising=>, or for of= <f p= together= conf_rev=>. window: shown= total= capped= has_more= next_offset= offset= limit= (capped=1 cut; next_offset= pastes as offset=). at=: commit+dirty+shallow. root=: p= relative to it. pairs=N: file pairs with 3+ shared commits in window= (after min_recur), surprising or not. sub_windows=N: equal-commit-count slices of window=; the denominator of recur=. driver=a|b: the side whose changes best imply the other's, look there first; absent on a tie. recur=K: slices of sub_windows= the pair co-changed in; 1 = one burst, not a standing coupling. -->
<cochange schema="ripwire.cochange/v1" pairs="3479" window="18mo@HEAD" sub_windows="3" shown="30" capped="1" total="3479" has_more="1" next_offset="30" offset="0" limit="0" root="." at="c7920353a">
<pair a="test/headsnapcachecheck.sh" b="test/qsnapcachecheck.sh" together="4" deg="1.00" conf_ab="1.00" conf_ba="1.00" recur="2" surprising="1"/>
<pair a="src/layout.h" b="test/layoutfix/attrfields.h" together="4" deg="1.00" conf_ab="0.19" conf_ba="1.00" driver="b" recur="1" surprising="1"/>
<pair a="test/qsnapcachecheck.sh" b="test/qsnapprefetchcheck.sh" together="4" deg="1.00" conf_ab="1.00" conf_ba="0.67" driver="a" recur="2" surprising="1"/>
<pair a="test/headsnapcachecheck.sh" b="test/qsnapprefetchcheck.sh" together="4" deg="1.00" conf_ab="1.00" conf_ba="0.67" driver="a" recur="2" surprising="1"/>
<pair a="test/javamethodreffix/A.java" b="test/javamethodreffix/Widget.java" together="3" deg="1.00" conf_ab="0.75" conf_ba="1.00" driver="b" recur="2" surprising="1"/>
<pair a="test/droppedpositivecheck.sh" b="test/regression.sh" together="3" deg="1.00" conf_ab="1.00" conf_ba="0.01" driver="a" recur="2" surprising="1"/>
<pair a="test/luacheck.sh" b="test/phpcheck.sh" together="3" deg="1.00" conf_ab="0.75" conf_ba="1.00" driver="b" recur="2" surprising="1"/>
<pair a="test/mcpslicecheck.sh" b="test/mcpverbscheck.sh" together="3" deg="1.00" conf_ab="1.00" conf_ba="0.21" driver="a" recur="3" surprising="1"/>
<pair a="src/accessshape.h" b="test/accessshapefix/walks.cpp" together="3" deg="1.00" conf_ab="0.75" conf_ba="1.00" driver="b" recur="1" surprising="1"/>
<pair a="src/fieldaffinity.h" b="test/accessshapefix/walks.cpp" together="3" deg="1.00" conf_ab="0.43" conf_ba="1.00" driver="b" recur="1" surprising="1"/>
<pair a="test/qschemetripcheck.sh" b="test/rubyrequirecheck.sh" together="3" deg="1.00" conf_ab="0.02" conf_ba="1.00" driver="b" recur="1" surprising="1"/>
<pair a="test/rubyrecvcheck.sh" b="test/rubyrequirecheck.sh" together="3" deg="1.00" conf_ab="0.50" conf_ba="1.00" driver="b" recur="1" surprising="1"/>
<pair a="test/grepcontextcheck.sh" b="test/grepscancheck.sh" together="3" deg="1.00" conf_ab="1.00" conf_ba="1.00" recur="2" surprising="1"/>
<pair a="test/cachesplitcheck.sh" b="test/evictioncheck.sh" together="3" deg="1.00" conf_ab="1.00" conf_ba="0.23" driver="a" recur="2" surprising="1"/>
<pair a="test/grepcheck.sh" b="test/grepcontextcheck.sh" together="3" deg="1.00" conf_ab="0.50" conf_ba="1.00" driver="b" recur="2" surprising="1"/>
<pair a="test/grepcheck.sh" b="test/grepscancheck.sh" together="3" deg="1.00" conf_ab="0.50" conf_ba="1.00" driver="b" recur="2" surprising="1"/>
<pair a="hooks/ripwire-claude-route.sh" b="hooks/ripwire-codex-route.sh" together="16" deg="0.94" conf_ab="0.94" conf_ba="0.84" driver="a" recur="3" surprising="1"/>
<pair a="bench/agentloop/analyze.py" b="bench/agentloop/run_agentloop.py" together="8" deg="0.89" conf_ab="0.89" conf_ba="0.44" driver="a" recur="1" surprising="1"/>
<pair a="src/graph.h" b="src/ingest_jsimports.h" together="6" deg="0.86" conf_ab="0.03" conf_ba="0.86" driver="b" recur="2" surprising="1"/>
<pair a="src/fielduses.h" b="src/verbs_navigate.h" together="5" deg="0.83" conf_ab="0.83" conf_ba="0.04" driver="a" recur="3" surprising="1"/>
<pair a="src/serialize.h" b="src/verify.h" together="5" deg="0.83" conf_ab="0.02" conf_ba="0.83" driver="b" recur="2" surprising="1"/>
<pair a="src/cli.h" b="src/sarif.h" together="5" deg="0.83" conf_ab="0.01" conf_ba="0.83" driver="b" recur="2" surprising="1"/>
<pair a="bench/bench_svector3.cpp" b="bench/bench_svector_wave.cpp" together="4" deg="0.80" conf_ab="0.80" conf_ba="0.80" recur="1" surprising="1"/>
<pair a="test/nestedimportcheck.sh" b="test/preproccondcheck.sh" together="4" deg="0.80" conf_ab="0.67" conf_ba="0.80" driver="b" recur="2" surprising="1"/>
<pair a="src/ingest_model.h" b="src/model.h" together="18" deg="0.78" conf_ab="0.78" conf_ba="0.14" driver="a" recur="3" surprising="1"/>
<pair a="src/ingest_cache.h" b="src/quality.h" together="132" deg="0.77" conf_ab="0.77" conf_ba="0.40" driver="a" recur="3" surprising="1"/>
<pair a="src/ingest_valuerefs.h" b="src/valuerefs.h" together="6" deg="0.75" conf_ab="0.55" conf_ba="0.75" driver="b" recur="1" surprising="1"/>
<pair a="src/ingest_sidecap.h" b="src/preprocdead.h" together="3" deg="0.75" conf_ab="0.04" conf_ba="0.75" driver="b" recur="1" surprising="1"/>
<pair a="test/regression.sh" b="test/subtokencheck.sh" together="3" deg="0.75" conf_ab="0.01" conf_ba="0.75" driver="b" recur="2" surprising="1"/>
<pair a="test/localscountcheck.sh" b="test/naminglocalscheck.sh" together="3" deg="0.75" conf_ab="0.75" conf_ba="0.60" driver="a" recur="1" surprising="1"/>
</cochange>
`````

## `./build/ripwire . --hotspots --since="2 weeks ago"`

*Hotspots scoped to RECENT churn (the regression lens).*

**wall time: 1.29s**

`````
<!-- ripwire hotspots schema=ripwire.hotspots/v1: maintenance pain = churn x ccx over window=: <f p= churn= ccx= score= top= top_ccx= top_l=>; unranked_*= no churn/complexity. window: shown= total= capped= has_more= next_offset= offset= limit= (capped=1 cut; next_offset= pastes as offset=). at=: commit+dirty+shallow. root=: p= relative to it. files=/ranked=: files in the window / those with both churn and complexity; ranked + unranked_no_churn + unranked_no_complexity = files. unranked_no_churn=/unranked_no_complexity=: files left out for no commit in window= / no measured complexity. -->
<hotspots schema="ripwire.hotspots/v1" window="2 weeks ago" files="2484" ranked="196" unranked_no_churn="1985" unranked_no_complexity="303" shown="40" capped="1" total="196" has_more="1" next_offset="40" offset="0" limit="0" root="." at="c7920353a">
<f p="src/graph.h" churn="52" ccx="2842" score="147784" top="buildGraph" top_ccx="909" top_l="3578"/>
<f p="src/quality.h" churn="56" ccx="1687" score="94472" top="computeDelta" top_ccx="324" top_l="7967"/>
<f p="src/serialize.h" churn="33" ccx="2082" score="68706" top="serialize" top_ccx="271" top_l="2602"/>
<f p="src/mcpverbs.h" churn="54" ccx="1146" score="61884" top="runBatchSub" top_ccx="138" top_l="5220"/>
<f p="src/cli.h" churn="70" ccx="642" score="44940" top="parseArgs" top_ccx="213" top_l="5180"/>
<f p="src/resolve.h" churn="24" ccx="1812" score="43488" top="buildPreciseIncludeAdjWithContext" top_ccx="84" top_l="4196"/>
<f p="src/main.cpp" churn="29" ccx="1165" score="33785" top="dispatchMain" top_ccx="471" top_l="4108"/>
<f p="src/compactlegend.h" churn="93" ccx="313" score="29109" top="applyCompactDialectOnce" top_ccx="47" top_l="2056"/>
<f p="src/mcp.h" churn="30" ccx="927" score="27810" top="dispatchMcpLine" top_ccx="735" top_l="1118"/>
<f p="src/verbs_navigate.h" churn="38" ccx="668" score="25384" top="runVerify" top_ccx="142" top_l="1554"/>
<f p="src/verbs_report.h" churn="19" ccx="1136" score="21584" top="runStructureText" top_ccx="258" top_l="3143"/>
<f p="src/ingest_sidecap.h" churn="19" ccx="840" score="15960" top="captureTagsFacts" top_ccx="403" top_l="1730"/>
<f p="src/skillscan.h" churn="25" ccx="521" score="13025" top="scanSkillTextOn" top_ccx="199" top_l="1162"/>
<f p="src/crossref.h" churn="20" ccx="618" score="12360" top="streamBlobs" top_ccx="43" top_l="509"/>
<f p="src/ingest_cache.h" churn="33" ccx="343" score="11319" top="saveCache" top_ccx="95" top_l="2869"/>
<f p="src/mention.h" churn="19" ccx="506" score="9614" top="applyMentionBoost" top_ccx="92" top_l="980"/>
<f p="src/verbs_quality.h" churn="17" ccx="544" score="9248" top="runQualityDelta" top_ccx="288" top_l="1111"/>
<f p="src/ingest_relations.h" churn="12" ccx="588" score="7056" top="captureFields" top_ccx="81" top_l="782"/>
<f p="src/ingest_valuerefs.h" churn="11" ccx="525" score="5775" top="classify" top_ccx="99" top_l="1083"/>
<f p="src/verbs_for.h" churn="8" ccx="672" score="5376" top="runForLens" top_ccx="322" top_l="2221"/>
<f p="src/ingest_names.h" churn="11" ccx="477" score="5247" top="testMacroBlockPartsOf" top_ccx="17" top_l="1638"/>
<f p="src/ingest_binds.h" churn="7" ccx="670" score="4690" top="bindsVisitNode" top_ccx="85" top_l="2387"/>
<f p="src/situ.h" churn="15" ccx="241" score="3615" top="writeSituation" top_ccx="49" top_l="639"/>
<f p="src/jsrunner.h" churn="11" ccx="305" score="3355" top="stringValue" top_ccx="30" top_l="315"/>
<f p="src/search.h" churn="6" ccx="557" score="3342" top="grepCollect" top_ccx="59" top_l="1405"/>
<f p="src/handlershape.h" churn="12" ccx="268" score="3216" top="withoutTrailingCalls" top_ccx="32" top_l="474"/>
<f p="src/docdrift.h" churn="5" ccx="582" score="2910" top="computeDocDrift" top_ccx="38" top_l="2441"/>
<f p="src/ingest_astquery.h" churn="4" ccx="720" score="2880" top="astQueryGrouped" top_ccx="260" top_l="837"/>
… [13 more display lines; full output is 5099 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --arch=test/archfix/rules.txt`

*Enforce layering rules (exit 2 on violation) — run against the repo's own test fixture rules.*

`````
<!-- ripwire arch schema=ripwire.arch/v1: layering rules fit: allowed/denied file-to-file edges, each violation a row. -->
<arch schema="ripwire.arch/v1" layers="2" rules="1" pathRules="0" violations="0" baselined="0" new_violations="0">
<metrics modules="588" typed_modules="232" zone_pain="199" zone_useless="1" zone_ok="32" zone_na="356" propagation_cost="0.002" note="Martin Ca/Ce/I/A/D + zone (main-sequence heuristic, no independent outcome-based validation — folklore, not proof) + reachability — directory-level estimate from  … [line truncated: 410 more bytes on this line]
<m path="." ca="0" ce="0" types="0" abstract="0" I="0.00" A="0.00" D="1.00" zone="n/a" reachable="1" isolated="1"/>
<m path="./.codex-plugin" ca="0" ce="0" types="0" abstract="0" I="0.00" A="0.00" D="1.00" zone="n/a" reachable="1" isolated="1"/>
<m path="./.github" ca="0" ce="0" types="0" abstract="0" I="0.00" A="0.00" D="1.00" zone="n/a" reachable="1" isolated="1"/>
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
<m path="./bench/capsweep" ca="0" ce="0" types="0" abstract="0" I="0.00" A="0.00" D="1.00" zone="n/a" reachable="1" isolated="1"/>
<m path="./bench/cppbench" ca="0" ce="0" types="1" abstract="0" I="0.00" A="0.00" D="1.00" zone="pain" reachable="1" isolated="1"/>
<m path="./bench/cppbench/results" ca="0" ce="0" types="0" abstract="0" I="0.00" A="0.00" D="1.00" zone="n/a" reachable="1" isolated="1"/>
<m path="./bench/ensemblecal" ca="0" ce="0" types="0" abstract="0" I="0.00" A="0.00" D="1.00" zone="n/a" reachable="1" isolated="1"/>
<m path="./bench/fixround" ca="0" ce="0" types="0" abstract="0" I="0.00" A="0.00" D="1.00" zone="n/a" reachable="1" isolated="1"/>
<m path="./bench/graft-h2h" ca="0" ce="0" types="0" abstract="0" I="0.00" A="0.00" D="1.00" zone="n/a" reachable="1" isolated="1"/>
<m path="./bench/h4fixtures/bash" ca="0" ce="0" types="0" abstract="0" I="0.00" A="0.00" D="1.00" zone="n/a" reachable="1" isolated="1"/>
<m path="./bench/h4fixtures/c" ca="0" ce="0" types="1" abstract="0" I="0.00" A="0.00" D="1.00" zone="pain" reachable="1" isolated="1"/>
<m path="./bench/h4fixtures/cpp" ca="0" ce="0" types="2" abstract="1" I="0.00" A="0.50" D="0.50" zone="ok" reachable="1" isolated="1"/>
<m path="./bench/h4fixtures/cppvex" ca="0" ce="0" types="0" abstract="0" I="0.00" A="0.00" D="1.00" zone="n/a" reachable="1" isolated="1"/>
<m path="./bench/h4fixtures/csharp" ca="0" ce="0" types="3" abstract="0" I="0.00" A="0.00" D="1.00" zone="pain" reachable="1" isolated="1"/>
<m path="./bench/h4fixtures/go" ca="0" ce="0" types="1" abstract="0" I="0.00" A="0.00" D="1.00" zone="pain" reachable="1" isolated="1"/>
<m path="./bench/h4fixtures/go2" ca="0" ce="0" types="1" abstract="0" I="0.00" A="0.00" D="1.00" zone="pain" reachable="1" isolated="1"/>
… [563 more display lines; full output is 82067 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --lint`

*Built-in AST checks (c-cast, goto, unsafe-c-fn, ...).*

**wall time: 1.69s**

`````
<!-- ripwire lint schema=ripwire.lint/v1: AST-only checks, facts not gates: <rule name= count= shown_rows= rows_capped= count_capped=> of <f rule= p= in=>. window: shown= total= capped= has_more= next_offset= offset= limit= (capped=1 cut; next_offset= pastes as offset=). findings_capped=/rows_capped=/count_capped=: 1 = cut. counts_floor=1: every count is a FLOOR, never a total. root=: p= relative to it. findings=N: findings over the printed rules; a floor when findings_capped=1. -->
<lint schema="ripwire.lint/v1" findings="5005" shown="684" capped="1" total="5005" has_more="1" next_offset="684" offset="0" limit="0" counts_floor="1" findings_capped="1" root=".">
<rule name="c-style-cast" count="420" shown_rows="106" rows_capped="1"/>
<rule name="goto" count="15" shown_rows="1" rows_capped="1"/>
<rule name="do-while" count="14" shown_rows="0" rows_capped="1"/>
<rule name="unsafe-c-fn" count="0" shown_rows="0" rows_capped="0"/>
<rule name="weak-crypto" count="0" shown_rows="0" rows_capped="0"/>
<rule name="redundant-parens" count="0" shown_rows="0" rows_capped="0"/>
<rule name="suspicious-semicolon" count="0" shown_rows="0" rows_capped="0"/>
<rule name="typedef-over-using" count="12" shown_rows="0" rows_capped="1"/>
<rule name="magic-number" count="445" shown_rows="282" rows_capped="1" count_capped="1"/>
<rule name="empty-catch" count="1" shown_rows="0" rows_capped="1"/>
<rule name="self-assign" count="3" shown_rows="0" rows_capped="1"/>
<rule name="large-function" count="283" shown_rows="39" rows_capped="1"/>
<rule name="deep-nesting" count="298" shown_rows="34" rows_capped="1"/>
<rule name="inconsistent-return" count="2" shown_rows="0" rows_capped="1"/>
<rule name="unreachable-code" count="5" shown_rows="0" rows_capped="1"/>
<rule name="naming-short" count="1578" shown_rows="74" rows_capped="1"/>
<rule name="naming-wordy" count="222" shown_rows="15" rows_capped="1"/>
<rule name="naming-series" count="427" shown_rows="0" rows_capped="1"/>
<rule name="naming-underscore" count="2" shown_rows="0" rows_capped="1"/>
<rule name="naming-case" count="58" shown_rows="0" rows_capped="1"/>
<rule name="naming-predicate" count="1" shown_rows="0" rows_capped="1"/>
<rule name="naming-setter" count="1" shown_rows="0" rows_capped="1"/>
<rule name="naming-confusable" count="300" shown_rows="28" rows_capped="1"/>
<rule name="naming-uninformative" count="0" shown_rows="0" rows_capped="0"/>
<rule name="atom-comma-operator" count="3" shown_rows="0" rows_capped="1"/>
<rule name="atom-embedded-crement" count="149" shown_rows="12" rows_capped="1"/>
<rule name="atom-assign-as-value" count="65" shown_rows="8" rows_capped="1"/>
<rule name="atom-nested-ternary" count="135" shown_rows="15" rows_capped="1"/>
… [696 more display lines; full output is 69779 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --lint-rules=test/lintrulesfix/rules`

*User lint rules (YAML, ast-grep style) from a directory.*

`````
<!-- ripwire lint schema=ripwire.lint/v1: AST-only checks, facts not gates: <rule name= count= shown_rows= rows_capped= count_capped=> of <f rule= p= in=>. window: shown= capped= (capped=1 cut). rows_capped=: 1 = cut. root=: p= relative to it. findings=N: findings over the printed rules; a floor when findings_capped=1. -->
<lint schema="ripwire.lint/v1" findings="5" shown="5" capped="0" root=".">
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
[math degraded] lint-rules: malformed rule file skipped  (lintrules.h:395, auto rw::parseLintRuleFile(const std::string &, std::string_view, std::vector<LintRule> &)::(anonymous class)::operator()(std::size_t, const char *) const — logged once per site)
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
<!-- ripwire lint schema=ripwire.lint/v1: AST-only checks, facts not gates: <rule name= count= shown_rows= rows_capped= count_capped=> of <f rule= p= in=>. window: shown= capped= (capped=1 cut). rows_capped=: 1 = cut. root=: p= relative to it. findings=N: findings over the printed rules; a floor when findings_capped=1. -->
<lint schema="ripwire.lint/v1" findings="1" shown="1" capped="0" heat_joined="1" root=".">
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
<rule name="atom-nested-ternary" count="0" shown_rows="0" rows_capped="0"/>
… [13 more display lines; full output is 3428 bytes on 1 raw line(s)]
`````

The joined finding — past the display cut above, extracted so the join is visible:

`````
<f rule="cache-pointer-chase-loop" p="src/x.cpp:11" in="walk" heat_scope="walk: chase pass" heat_calls="12" heat_total_ms="48.500" heat_l1d_mpki="7.250">p = p-&gt;next</f>
`````

## `./build/ripwire . --communities`

*Cluster the call graph into cohesive modules.*

`````
<!-- ripwire communities schema=ripwire.communities/v1: call-graph modules (Louvain): <community id= size= dir= label=> of <member t= n= p=>; drill= the verb taking a row's id=; shown_modules=/shown_bridges= <community>/<bridge> rows listed; bridges= community pairs joined by a call edge; isolated= symbols with no call edge: isolated_doc= doc sections, isolated_decl= other bodyless, isolated_header= other header defs, isolated_source= the rest; modules= modules of 2+ symbols; connected_singletons= 1-symbol modules with a call edge; symbols= indexed symbols. window: shown= total= capped= has_more= next_offset= offset= limit= (capped=1 cut; next_offset= pastes as offset=). modules_capped=/bridges_capped=: 1 = cut. counts_floor=1: every count is a FLOOR, never a total. graph_ambiguous=/graph_unresolved=: resolver gauge. graph_unindexed=N: N files no grammar could read (the map header's unindexed=); their calls raise neither gauge. root=: p= relative to it. pr_iters=N: PageRank iterations. <bridge a= b=>: two module ids joined by call edges. from_label=/to_label=: the label= of a=/b=. <bridge edges=>: call edges between the two, either direction. -->
<communities schema="ripwire.communities/v1" drill="--community=ID" modules="2324" shown_modules="30" modules_capped="1" bridges="2711" shown_bridges="12" bridges_capped="1" isolated="10910" isolated_decl="2889" isolated_header="1577" isolated_source="1922" isolated_doc="4522" connected_singletons=" … [line truncated: 194 more bytes on this line]
<community id="4870" size="1374" dir="src" label="src::emitTo@infra/emit.h:53:2760 [write,run,emit]" shown="5" capped="1">
<member t="method" n="empty" p="src/resolve.h:1552"/>
<member t="method" n="ok" p="src/infra/os_win32_logic.h:482"/>
<member t="method" n="empty" p="src/notes.h:540"/>
<member t="method" n="empty" p="src/scipoverlay.h:106"/>
<member t="method" n="size" p="src/infra/os_win32_logic.h:485"/>
</community>
<community id="4880" size="1135" dir="src" label="src::append@elixir_resolve.h:111:4875 [resolve,collect,add]" shown="5" capped="1">
<member t="method" n="push_back" p="src/infra/svector.h:326"/>
<member t="method" n="find" p="src/ingest_model.h:641"/>
<member t="method" n="find" p="src/graph.h:7419"/>
<member t="method" n="push_back" p="src/infra/svector.h:331"/>
<member t="method" n="append" p="src/elixir_resolve.h:111"/>
</community>
<community id="4900" size="534" dir="src" label="src::compare@structlayout.h:166:4708 [read,close,parse]" shown="5" capped="1">
<member t="method" n="empty" p="src/infra/svector.h:284"/>
<member t="fn" n="compare" p="src/structlayout.h:166"/>
<member t="method" n="pop_back" p="src/infra/svector.h:340"/>
<member t="method" n="data" p="src/infra/svector.h:265"/>
<member t="method" n="data" p="src/infra/svector.h:266"/>
</community>
<community id="5927" size="256" dir="src" label="src::kindIs@infra/nodekind.h:46:3271 [emit,collect,push]" shown="5" capped="1">
<member t="fn" n="kindIs" p="src/infra/nodekind.h:46"/>
<member t="fn" n="nodeTextOf" p="src/ingest_metrics.h:161"/>
<member t="fn" n="fieldChild" p="src/infra/fieldid.h:221"/>
<member t="fn" n="forEachChild" p="src/infra/tschildren.h:89"/>
<member t="fn" n="firstChildOfKind" p="src/infra/tschildren.h:158"/>
</community>
… [187 more display lines; full output is 16530 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --zoom`

*Nested module hierarchy (multi-level Louvain) + cross-module bridges — levels_shown="2" of levels= BY DEFAULT over the 40 largest top modules (~8 KB, where the whole tree is ~220 KB); a module AT the cut carries children=.*

`````
<!-- ripwire zoom schema=ripwire.zoom/v1: nested module hierarchy: <module level= id= size= dir= shown= capped=> of <member t= n= p=>; levels_shown= of levels= printed; symbols= = isolated= + size= of all top_modules=. window: shown= total= capped= has_more= next_offset= offset= limit= (capped=1 cut; next_offset= pastes as offset=). counts_floor=1: every count is a FLOOR, never a total. graph_ambiguous=/graph_unresolved=: resolver gauge. graph_unindexed=N: N files no grammar could read (the map header's unindexed=); their calls raise neither gauge. pr_iters=N: PageRank iterations. children=K: K child modules below the levels_shown= cut, unprinted. next=: the one pasteable follow-up. -->
<zoom schema="ripwire.zoom/v1" levels="4" levels_shown="2" top_modules="944" symbols="23851" isolated="10910" shown="40" capped="1" total="944" has_more="1" next_offset="40" offset="0" limit="0" pr_iters="28" graph_ambiguous="10278" graph_unresolved="12878" graph_unindexed="237" counts_floor="1" nex … [line truncated: 23 more bytes on this line]
<module level="3" id="1526" size="5816" dir="./src">
<module level="2" id="1528" size="5399" dir="./src" children="63">
</module>
<module level="2" id="4706" size="206" dir="./test" children="10">
</module>
<module level="2" id="5351" size="61" dir="./src/infra" children="6">
</module>
<module level="2" id="5367" size="35" dir="./src/infra" children="3">
</module>
<module level="2" id="6182" size="22" dir="./src" children="3">
</module>
<module level="2" id="5474" size="22" dir="./src/infra" children="2">
</module>
<module level="2" id="5189" size="19" dir="./test/cppqualtmplfix" children="2">
</module>
<module level="2" id="1549" size="26" dir="./bench" children="3">
</module>
<module level="2" id="4885" size="11" dir="./src" children="2">
</module>
<module level="2" id="5674" size="15" dir="./src/infra" children="2">
</module>
</module>
<module level="3" id="1304" size="1831" dir="./test">
<module level="2" id="1305" size="1579" dir="./test" children="67">
</module>
<module level="2" id="7991" size="87" dir="./test" children="4">
</module>
<module level="2" id="8164" size="78" dir="./test" children="5">
… [171 more display lines; full output is 8315 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --zoom --zoom-levels=3`

*The restoring knob: --zoom-levels=N prints N levels (0 = the whole tree); here three, ~11 KB.*

`````
<!-- ripwire zoom schema=ripwire.zoom/v1: nested module hierarchy: <module level= id= size= dir= shown= capped=> of <member t= n= p=>; levels_shown= of levels= printed; symbols= = isolated= + size= of all top_modules=. window: shown= total= capped= has_more= next_offset= offset= limit= (capped=1 cut; next_offset= pastes as offset=). counts_floor=1: every count is a FLOOR, never a total. graph_ambiguous=/graph_unresolved=: resolver gauge. graph_unindexed=N: N files no grammar could read (the map header's unindexed=); their calls raise neither gauge. pr_iters=N: PageRank iterations. children=K: K child modules below the levels_shown= cut, unprinted. next=: the one pasteable follow-up. -->
<zoom schema="ripwire.zoom/v1" levels="4" levels_shown="3" top_modules="944" symbols="23851" isolated="10910" shown="40" capped="1" total="944" has_more="1" next_offset="40" offset="0" limit="0" pr_iters="28" graph_ambiguous="10278" graph_unresolved="12878" graph_unindexed="237" counts_floor="1" nex … [line truncated: 39 more bytes on this line]
<module level="3" id="1526" size="5816" dir="./src">
<module level="2" id="1528" size="5399" dir="./src">
<module level="1" id="1551" size="4129" dir="./src" children="199">
</module>
<module level="1" id="4897" size="402" dir="./src" children="33">
</module>
<module level="1" id="1540" size="103" dir="./src/infra" children="13">
</module>
<module level="1" id="1553" size="83" dir="./src/infra" children="11">
</module>
<module level="1" id="7285" size="59" dir="./src" children="7">
</module>
<module level="1" id="4647" size="35" dir="./src" children="6">
</module>
<module level="1" id="5540" size="5" dir="./src/infra" children="2">
</module>
<module level="1" id="5566" size="32" dir="./src" children="10">
</module>
<module level="1" id="5551" size="18" dir="./src" children="5">
</module>
<module level="1" id="7046" size="27" dir="./src" children="7">
</module>
<module level="1" id="4885" size="15" dir="./src" children="3">
</module>
<module level="1" id="6120" size="27" dir="./src" children="3">
</module>
<module level="1" id="4844" size="14" dir="./src" children="4">
</module>
… [699 more display lines; full output is 27481 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --report`

*Architecture summary (modules, god-files, cycles) as markdown.*

`````
<!-- ripwire markdown: no run of 4-or-more backticks in this output — safe to embed inside a wider fence -->

# ripwire architecture report

2484 files · 23851 symbols · 34236 edges · 2324 modules (10910 call-graph isolated)

Root: `.`

Call-graph isolate provenance: 2889 declaration, 1577 header, 1922 source, 4522 document; 0 connected Louvain singletons

## Modules (call-graph clusters; showing 12 of 2324)
- **src::emitTo@infra/emit.h:53:2760 [write,run,emit]** — 1374 symbols
- **src::append@elixir_resolve.h:111:4875 [resolve,collect,add]** — 1135 symbols
- **src::compare@structlayout.h:166:4708 [read,close,parse]** — 534 symbols
- **src::kindIs@infra/nodekind.h:46:3271 [emit,collect,push]** — 256 symbols
- **docs::`--top-k=N`@COMMANDS.md:59:8861 [pack,allow,insert]** — 177 symbols
- **src::realpath@infra/os.h:199:13067 [parse,split,read]** — 63 symbols
- **src::relForHash@model.h:1438:116507 [compute,clone,read]** — 60 symbols
- **src::assign@infra/svector.h:342:19905 [scan,run,resolve]** — 54 symbols
- **src/infra::DYNMAP_ASSUME@dynamic_map.hpp:90:4411 [erase,find,count]** — 51 symbols
- **src/infra::active@profilePmc.h:845:34910 [print,ensure,report]** — 49 symbols
- **src::rowOffsets@infra/sparseCsr.h:248:8990 [compute,connect,verify]** — 38 symbols
- **test::no@decltodefcheck.sh:127:11708 [run]** — 30 symbols

## God files (most depended-on; showing 10 of 445)
- `test/lib/clean-env.sh` — 181 dependents
- `src/infra/emit.h` — 86 dependents
- `src/model.h` — 85 dependents
- `src/infra/Diagnostics.h` — 58 dependents
- `src/serialize.h` — 39 dependents
… [32 more lines, 3523 bytes total]
`````

## `./build/ripwire . --seams`

*Cross-module call seams no test reaches. NOW carries seam_pairs/shown/capped.*

`````
<!-- ripwire seams schema=ripwire.seams/v1: cross-directory call edges NO test reaches: <seam from= to= untested= shown= capped=> of <edge caller= p= callee= cp=>. window: shown= total= capped= has_more= next_offset= offset= limit= (capped=1 cut; next_offset= pastes as offset=). counts_floor=1: every count is a FLOOR, never a total. graph_ambiguous=/graph_unresolved=: resolver gauge. graph_unindexed=N: N files no grammar could read (the map header's unindexed=); their calls raise neither gauge. root=: p= relative to it. pr_iters=N: PageRank iterations. modules=N: directories holding indexed symbols (a module = parent dir). bridges=N: cross-directory call edges, tested or not; untested= is those no test reaches. test_files=N: test files whose calls seed the reach; 0 means every seam reads untested. seam_pairs=N: directed dir pairs with an untested edge (the seam rows' total). <file-scope> (t=modscope): a file's MODULE SCOPE — where a top-level call and an anonymous callback body's calls live; a CALLER, never a callee, with no body to expand. -->
<seams schema="ripwire.seams/v1" modules="586" bridges="8946" untested="6021" test_files="1855" seam_pairs="37" shown="20" capped="1" total="37" has_more="1" next_offset="20" offset="0" limit="0" pr_iters="28" root="." graph_ambiguous="10278" graph_unresolved="12878" graph_unindexed="237" counts_flo … [line truncated: 7 more bytes on this line]
<seam from="src" to="src/infra" untested="5814" shown="5" capped="1">
<edge caller="gitOneLine" p="src/quality.h:1744" callee="shSingleQuote" cp="src/infra/shquote.h:19"/>
<edge caller="write" p="src/serialize.h:409" callee="data" cp="src/infra/svector.h:265"/>
<edge caller="write" p="src/serialize.h:409" callee="data" cp="src/infra/svector.h:266"/>
<edge caller="jsonEscape" p="src/mcpjson.h:877" callee="escapeMcp" cp="src/infra/jsonesc.h:230"/>
<edge caller="popenTrimmed" p="src/gitmine.h:245" callee="back" cp="src/infra/svector.h:264"/>
</seam>
<seam from="bench" to="src/infra" untested="73" shown="5" capped="1">
<edge caller="applyOne" p="bench/bench_svector_diff.cpp:166" callee="pop_back" cp="src/infra/svector.h:340"/>
<edge caller="applyOne" p="bench/bench_svector_diff.cpp:166" callee="emplace_back" cp="src/infra/svector.h:333"/>
<edge caller="applyOne" p="bench/bench_svector_diff.cpp:166" callee="shrink_to_fit" cp="src/infra/svector.h:305"/>
<edge caller="infraSortSmall" p="bench/bench_radix_ab.cpp:73" callee="sortKeySmall" cp="src/infra/radixSort.h:91"/>
<edge caller="isSorted" p="bench/bench_sort_large.cpp:42" callee="lessByFromTo" cp="src/infra/sortutil.h:210"/>
</seam>
<seam from="." to="docs" untested="30" shown="5" capped="1">
<edge caller="What it saves you, in tokens" p="README.md:1767" callee="EVALS" cp="docs/EVALS.md:1"/>
<edge caller="Measured" p="README.md:1606" callee="EVALS" cp="docs/EVALS.md:1"/>
<edge caller="Where its own cycles go — hardware counters, per scope" p="README.md:1813" callee="OPTREMARKS" cp="docs/OPTREMARKS.md:1"/>
<edge caller="Languages" p="README.md:2275" callee="ARCHITECTURE" cp="docs/ARCHITECTURE.md:1"/>
<edge caller="Documentation" p="README.md:3107" callee="TUNING" cp="docs/TUNING.md:1"/>
</seam>
<seam from="bench/multiswe" to="bench/locbench" untested="8" shown="5" capped="1">
<edge caller="main" p="bench/multiswe/run_multiswe.py:301" callee="run_ctx" cp="bench/locbench/run_locbench.py:166"/>
<edge caller="main" p="bench/multiswe/run_multiswe.py:301" callee="parse_candidates" cp="bench/locbench/run_locbench.py:223"/>
<edge caller="main" p="bench/multiswe/run_multiswe.py:301" callee="norm_path" cp="bench/locbench/run_locbench.py:241"/>
<edge caller="main" p="bench/multiswe/run_multiswe.py:301" callee="ranked_files_from_candidates" cp="bench/locbench/run_locbench.py:245"/>
<edge caller="main" p="bench/multiswe/run_multiswe.py:301" callee="file_ranks" cp="bench/locbench/run_locbench.py:251"/>
</seam>
… [102 more display lines; full output is 13425 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --mermaid`

*Module (directory) dependency graph as a Mermaid diagram.*

`````
%% ripwire --mermaid: module (directory) dependency graph — node = dir (symbol count), edge = inter-module calls (>= 3). Render at mermaid.live.
flowchart LR
  subgraph sg0 ["src"]
    n101["src<br/>7066"]
    n102["src/infra<br/>1276"]
  end
  subgraph sg1 ["test"]
    n103["test<br/>4853"]
    n328["test/fixtures/recallpassage<br/>314"]
    n280["test/expandmodefix<br/>151"]
    n282["test/expandsibsfix<br/>149"]
    n458["test/rubyattrsfix<br/>85"]
    n395["test/massfix<br/>77"]
    n360["test/javamethodreffix<br/>62"]
  end
  n73["docs<br/>831"]
  n2[".github<br/>598"]
  subgraph sg4 ["bench"]
    n4["bench<br/>531"]
    n5["bench/agentloop<br/>331"]
    n49["bench/locbench/results/r5_pooling<br/>237"]
    n50["bench/locbench/results/r6_expansion<br/>187"]
    n59["bench/recalleval<br/>113"]
    n43["bench/locbench<br/>107"]
    n38["bench/headtohead/r3-headroom-2026-08-03<br/>102"]
    n65["bench/skillrater/results/2026-09-07/arms<br/>100"]
    n62["bench/shotgun<br/>96"]
    n45["bench/locbench/results/r1cpp_anchorhop<br/>94"]
    n11["bench/arb<br/>85"]
    n56["bench/nestcal/r1-2026-08-07<br/>84"]
… [21 more lines, 1606 bytes total]
`````

## `./build/ripwire . --owners`

*Bus-factor: recency-weighted author ownership per file.*

**wall time: 1.56s**

`````
<!-- ripwire owners schema=ripwire.owners/v1: recency-weighted author ownership (half-life 6mo): <f p= authors= bf= top= share=>; bf=1 = one person holds it. at=: commit+dirty+shallow. root=: p= relative to it. files=N: files analysed. files=N: single-author files folded into this one row; detail=1 lists each. -->
<owners schema="ripwire.owners/v1" files="2484" root="." at="c7920353a">
<uniform authors="1" bf="1" share="1.00" files="1574"/>
<f p=".coderabbit.yaml" authors="2" bf="0" top="<author>" share="0.75"/>
<f p=".github/pargates-shard-weights.json" authors="3" bf="1" top="<author>" share="0.86"/>
<f p=".github/workflows/ci.yml" authors="6" bf="0" top="<author>" share="0.47"/>
<f p=".github/workflows/nightly.yml" authors="2" bf="1" top="<author>" share="0.86"/>
<f p=".github/workflows/release.yml" authors="3" bf="0" top="<author>" share="0.49"/>
<f p="AGENTS.md" authors="2" bf="0" top="<author>" share="0.71"/>
<f p="CHANGELOG.md" authors="12" bf="0" top="<author>" share="0.80"/>
<f p="CLAUDE.md" authors="5" bf="0" top="<author>" share="0.41"/>
<f p="CONTRIBUTING.md" authors="5" bf="0" top="<author>" share="0.62"/>
<f p="README.md" authors="19" bf="0" top="<author>" share="0.46"/>
<f p="SECURITY.md" authors="2" bf="0" top="<author>" share="0.63"/>
<f p="THIRD_PARTY.md" authors="7" bf="0" top="<author>" share="0.42"/>
<f p="bench/ANSWERQUALITY.md" authors="2" bf="0" top="<author>" share="0.72"/>
<f p="bench/PROFILE.md" authors="5" bf="0" top="<author>" share="0.78"/>
<f p="bench/agentloop/README.md" authors="2" bf="1" top="<author>" share="0.89"/>
<f p="bench/agentloop/grade_answers.py" authors="3" bf="0" top="<author>" share="0.51"/>
<f p="bench/agentloop/run_agentloop.py" authors="3" bf="1" top="<author>" share="0.90"/>
<f p="bench/agentloop/run_editsuite.py" authors="2" bf="0" top="<author>" share="0.80"/>
<f p="bench/arb/run_arb.py" authors="2" bf="0" top="<author>" share="0.65"/>
<f p="bench/capsweep/capsweep.py" authors="2" bf="1" top="<author>" share="0.92"/>
<f p="bench/mine_traces.py" authors="2" bf="0" top="<author>" share="0.72"/>
<f p="bench/representative_perfgate.sh" authors="3" bf="0" top="<author>" share="0.68"/>
<f p="bench/scip_match_diag.py" authors="2" bf="0" top="<author>" share="0.51"/>
<f p="bench/scip_pin_precision.py" authors="2" bf="0" top="<author>" share="0.74"/>
<f p="bench/shotgun/README.md" authors="3" bf="0" top="<author>" share="0.49"/>
<f p="bench/shotgun/cc_static.py" authors="2" bf="0" top="<author>" share="0.50"/>
<f p="bench/shotgun/cc_vs_history.py" authors="2" bf="0" top="<author>" share="0.51"/>
… [884 more display lines; full output is 97571 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --dead-code=src`

*Internal functions with no caller found in the index — a name-based graph reading, not a confidence score. NOTE the filter is a path-COMPONENT match: 'src' matches any .../src/... segment; use ./src to pin the root directory.*

`````
<!-- ripwire dead-code schema=ripwire.dead-code/v1: internal-linkage functions with no caller found in the index (not a confidence score): <d n= t= p= l=>; filter= path component. counts_floor=1: every count is a FLOOR, never a total. graph_ambiguous=/graph_unresolved=: resolver gauge. graph_unindexed=N: N files no grammar could read (the map header's unindexed=); their calls raise neither gauge. root=: p= relative to it. evidence=: the rule every row met, internal linkage and no caller in the index; verify before deleting. register-macro-excluded=N: symbols skipped as self-registering test/bench macros (TEST, BENCHMARK...); a floor. count=N: candidates meeting evidence= (a floor). -->
<dead-code schema="ripwire.dead-code/v1" count="1" evidence="internal-linkage+zero-callers" register-macro-excluded="0" filter="src" root="." graph_ambiguous="10278" graph_unresolved="12878" graph_unindexed="237" counts_floor="1">
<d n="unused_helper" t="fn" p="test/archmetricsfix/src/orphan/util.cpp" l="1"/>
</dead-code>
`````

## `./build/ripwire . --exercises=test/regression.sh`

*Which symbols a TEST FILE exercises — the reverse direction of --affected.*

`````
<!-- ripwire exercises schema=ripwire.exercises/v1: NON-TEST symbols this test transitively calls (what it covers): <t p= run=>; the inverse of affected. window: shown= capped= (capped=1 cut). seed_files_capped=: 1 = cut. counts_floor=1: every count is a FLOOR, never a total. graph_ambiguous=/graph_unresolved=: resolver gauge. graph_unindexed=N: N files no grammar could read (the map header's unindexed=); their calls raise neither gauge. root=: p= relative to it. pr_iters=N: PageRank iterations. seed_files=N: test files the pattern matched. shown_seed_files=N: of those, printed as t rows (at most 20). test_symbols=N: symbols in those test files, the walk's seeds. reaches=N: non-test symbols the tests transitively call (the s rows' total). harness=script|mixed: seeds include shell gates, whose subprocess coverage is unseen; note= says so. of=: the test file pattern given. -->
<exercises schema="ripwire.exercises/v1" of="test/regression.sh" seed_files="1" shown_seed_files="1" seed_files_capped="0" test_symbols="4" reaches="0" harness="script" note="a shell gate invokes the compiled binary as a subprocess; script-to-binary edges are not modelled, so reaches= counts call-gr … [line truncated: 190 more bytes on this line]
<t p="test/regression.sh" run="bash test/regression.sh"/>
</exercises>
`````

## `./build/ripwire . --community=0`

*Drill into ONE call-graph community by id — the drill= the --communities output itself advertises.*

`````
<!-- ripwire community schema=ripwire.community/v1: ONE module id=: <member t= n= p=> ranked members, its <bridge> edges; size= the TRUE count; dir= its members' most common directory (a top-level file's own path); label= dir::name@file:line:byte of its top fan-in member (non-accessors first) [up to 3 top name verbs]; bridges= modules a call edge joins to it; partition= module count incl. singletons (ids 0..partition-1); modules= those of 2+ symbols; shown_bridges= <bridge> rows listed. window: shown= capped= (capped=1 cut). bridges_capped=: 1 = cut. counts_floor=1: every count is a FLOOR, never a total. graph_ambiguous=/graph_unresolved=: resolver gauge. graph_unindexed=N: N files no grammar could read (the map header's unindexed=); their calls raise neither gauge. root=: p= relative to it. pr_iters=N: PageRank iterations. -->
<community schema="ripwire.community/v1" id="0" size="1" dir=".coderabbit.yaml" label=".coderabbit.yaml::reviews@.coderabbit.yaml:10:751" bridges="0" shown_bridges="0" bridges_capped="0" partition="13234" modules="2324" shown="1" capped="0" pr_iters="28" root="." graph_ambiguous="10278" graph_unreso … [line truncated: 52 more bytes on this line]
<member t="sec" n="reviews" p=".coderabbit.yaml:10"/>
</community>
`````

## `./build/ripwire . --quality-delta`

*On a CLEAN tree: nothing got worse, exit 0. The gating shape is in the sandbox section below.*

**wall time: 15.01s**

`````
<!-- ripwire quality-delta schema=ripwire.quality-delta/v1: only what the change made WORSE vs baseline=: regressions= minor= gating=; <r kind= sym= p= was= now= gating= bar=>, <sa> acked. value-ref-excluded=N: internal functions kept off because a table, field or argument holds them (matched by name, not a proven call); a floor. at=: commit+dirty+shallow. stale=N: ack ledger rows whose target no longer applies (sa rows); never gating. preexisting-worse=N: regressions on symbols that existed at baseline; only these gate (when major). new-symbol=N: regressions on NEW code; never gate, but the debt is yours: read them. register-macro-excluded=N: symbols kept out of dead-code as self-registering test/bench macros; a floor. api-new-surface=N: new PUBLIC symbols; a count, never gates, not in regressions=. renames=/rename_window_commits=: git rename pairs read over that many commits, to re-file baseline and acks. acked_by_rename=/acked_by_content=: acked= suppressions matched via git renames / an equal body hash. renames_window_truncated=1: history is deeper than the rename window, older renames unread. acked=N: findings suppressed by the ack ledger, listed as sa rows; never gating. sa key=/why=: the stale ack's ledger hash / target-gone (names nothing now) or finding-gone (no longer fires). head_basis=identity: the floor is this tree's own snapshot; archived-index-hidden: refused, a tracked path is skip-worktree/assume-unchanged; absent: the archived HEAD tree. -->
<quality-delta schema="ripwire.quality-delta/v1" baseline="git-HEAD" regressions="0" minor="0" acked="0" stale="134" preexisting-worse="0" new-symbol="0" gating="0" register-macro-excluded="62" api-new-surface="0" at="c7920353a" renames="57" rename_window_commits="400" acked_by_rename="0" acked_by_c … [line truncated: 86 more bytes on this line]
<sa kind="api-surface" key="085e3d408c2c4a35" why="target-gone"/>
<sa kind="api-surface" key="155d74d341a49f3c" why="target-gone"/>
<sa kind="api-surface" key="1a15386c2d1e47af" why="target-gone"/>
<sa kind="api-surface" key="298e798c7f075715" why="target-gone"/>
<sa kind="api-surface" key="56acdf9b5c314a14" why="target-gone"/>
<sa kind="api-surface" key="5a07390012b46e06" why="target-gone"/>
<sa kind="api-surface" key="6eef859578c8c376" why="target-gone"/>
<sa kind="api-surface" key="6f2394762f82a855" why="target-gone"/>
<sa kind="api-surface" key="7f2c3eefdf6e512e" why="target-gone"/>
<sa kind="api-surface" key="802e513731103806" why="target-gone"/>
<sa kind="api-surface" key="b6a24afef32a68a8" why="target-gone"/>
<sa kind="api-surface" key="c923e661c197b265" why="target-gone"/>
<sa kind="api-surface:new-symbol" key="1926b0d9e94541a0" why="target-gone"/>
<sa kind="api-surface:new-symbol" key="1d3814ba687a4aef" why="target-gone"/>
<sa kind="api-surface:new-symbol" key="1db76028879244ef" why="target-gone"/>
<sa kind="api-surface:new-symbol" key="36e39c7ab0fc1686" why="target-gone"/>
<sa kind="api-surface:new-symbol" key="4bce64bd920de0c3" why="target-gone"/>
<sa kind="api-surface:new-symbol" key="61f0e361ef7dee27" why="target-gone"/>
<sa kind="api-surface:new-symbol" key="79625906f9f71ad0" why="target-gone"/>
<sa kind="api-surface:new-symbol" key="8ecb190954dce18a" why="target-gone"/>
<sa kind="api-surface:new-symbol" key="995375dfa4e63104" why="target-gone"/>
<sa kind="api-surface:new-symbol" key="ee71e4fffa361902" why="target-gone"/>
<sa kind="complexity" key="0001f7edbff929e5" why="finding-gone" sym="src/cli.h::rw::validateLegendModifier" p="src/cli.h:4344"/>
<sa kind="complexity" key="3a0425468e6a18cf" why="finding-gone" sym="src/crossref.h::crossref::writeWhereisPage" p="src/crossref.h:3193"/>
<sa kind="complexity" key="4b309450f25c2b44" why="finding-gone" sym="src/ingest.cpp::rw::ingest" p="src/ingest.cpp:292"/>
<sa kind="complexity" key="7051b3950aaf4c14" why="finding-gone" sym="src/mention.h::rw::applyDocMentionBoost" p="src/mention.h:1336"/>
<sa kind="complexity" key="7a04eee0ff6ec2d7" why="finding-gone" sym="src/recall.h::rw::buildSectionGranularBody" p="src/recall.h:1225"/>
<sa kind="complexity" key="a9f76a08efdb3d50" why="finding-gone" sym="runAffected" p="src/verbs_change.h:69"/>
… [107 more display lines; full output is 13557 bytes on 1 raw line(s)]
`````

stderr:

`````
ripwire: no ./.ripwire_quality_baseline — auto-comparing the working tree vs git HEAD (commit the baseline with --quality-baseline to pin it)
`````

## `./build/ripwire . --edit-check=rankGraphTeleport`

*Fast per-symbol post-edit contract check vs git HEAD (unchanged on a clean tree).*

**wall time: 6.84s**

`````
<!-- ripwire edit-check schema=ripwire.edit-check/v1: sym='s contract NOW vs HEAD: status=unchanged|new-symbol|contract-change; <c n= p= incompatible=1 sites_l=> callers. counts_floor=1: every count is a FLOOR, never a total. graph_ambiguous=/graph_unresolved=: resolver gauge. graph_unindexed=N: N files no grammar could read (the map header's unindexed=); their calls raise neither gauge. est_tokens=: price as emitted (an upper bound under compact). at=: commit+dirty+shallow. root=: p= relative to it. next=: the one pasteable follow-up. defs=N: overloads at this site (same file, scope, name) folded into one contract; params compared by MAX. callers=N: callers of sym= (the c rows' total; a floor). -->
<edit-check schema="ripwire.edit-check/v1" sym="rankGraphTeleport" t="fn" p="src/graph.h:5565" status="unchanged" defs="1" callers="7" incompatible="0" at="c7920353a" graph_ambiguous="10278" graph_unresolved="12878" graph_unindexed="237" counts_floor="1" root="." next="--test-gate=src/graph.h" est_t … [line truncated: 12 more bytes on this line]
<c n="runEval" p="src/eval.h:171"/>
<c n="rankGraph" p="src/graph.h:5606"/>
<c n="anchoredLexicalRank" p="src/graph.h:6252"/>
<c n="churnDecayRanking" p="src/main.cpp:1380"/>
<c n="churnRankedGraph" p="src/main.cpp:1419"/>
<c n="runDefaultMap" p="src/main.cpp:1629"/>
<c n="getIndex" p="src/mcpindex.h:1165"/>
</edit-check>
`````

## `./build/ripwire . --pr-context`

*No-LLM review-evidence bundle for the working-tree diff (clean tree = empty).*

`````
<!-- ripwire pr-context schema=ripwire.pr-context/v1: review bundle per changed file vs base=: symbols, callers, blast radius, tests, owners. counts_floor=1: every count is a FLOOR, never a total. graph_ambiguous=/graph_unresolved=: resolver gauge. graph_unindexed=N: N files no grammar could read (the map header's unindexed=); their calls raise neither gauge. est_tokens=: price as emitted (an upper bound under compact). at=: commit+dirty+shallow. root=: p= relative to it. truncated=: what the trim ladder dropped to fit budget_tokens= (budget-floor-exceeded: still over). direction=: side reviewed: worktree-since-head, head-since-fork or head-since-ref-tip. skipped_mode_only=N: mode-only (chmod) diffs left out of the changed files; renames stay in. trim_level=0-4: trim ladder step taken to fit budget_tokens= (0 none, 4 counts only); raise token-budget. budget_default=1: the default 8000-token budget applied (no token-budget or max-tokens given). files=N: changed files in the diff (shown= of them listed). -->
<pr-context schema="ripwire.pr-context/v1" base="working-tree" root="." direction="worktree-since-head" files="0" skipped_mode_only="0" budget_tokens="8000" est_tokens="584" trim_level="0" truncated="none" budget_default="1" at="c7920353a" graph_ambiguous="10278" graph_unresolved="12878" graph_unind … [line truncated: 28 more bytes on this line]
<!-- no changed files in the index (clean tree, or the diff touched only non-indexed files) -->
</pr-context>
`````

## `./build/ripwire . --pr-context=HEAD~1`

*The BASEREF form: diffed against merge-base(BASEREF, HEAD), never the ref tip — here the previous commit on the current line (a ref with NO merge base falls back to a disclosed two-dot diff: anchor="ref-tip-two-dot").*

**wall time: 2.11s**

`````
<!-- ripwire pr-context schema=ripwire.pr-context/v1: review bundle per changed file vs base=: symbols, callers, blast radius, tests, owners. window: shown= capped= (capped=1 cut). counts_floor=1: every count is a FLOOR, never a total. graph_ambiguous=/graph_unresolved=: resolver gauge. graph_unindexed=N: N files no grammar could read (the map header's unindexed=); their calls raise neither gauge. est_tokens=: price as emitted (an upper bound under compact). at=: commit+dirty+shallow. root=: p= relative to it. truncated=: what the trim ladder dropped to fit budget_tokens= (budget-floor-exceeded: still over). anchor=merge-base: diffed from merge base(base, HEAD); ref-tip-two-dot = no merge base, two-dot view. base_sha=: the merge-base commit (9 hex) the diff is anchored at. base_moved=N: paths the base ref changed since the fork that this work never touched; excluded. direction=: side reviewed: worktree-since-head, head-since-fork or head-since-ref-tip. skipped_mode_only=N: mode-only (chmod) diffs left out of the changed files; renames stay in. trim_level=0-4: trim ladder step taken to fit budget_tokens= (0 none, 4 counts only); raise token-budget. budget_default=1: the default 8000-token budget applied (no token-budget or max-tokens given). commits=N: this file's commits in window=; 0 = the window could not look, not no partners. partners=N: co-change partners NOT in the diff; rows are its top shown= (the cochange verb lists all). dependents=N: distinct symbols transitively calling this file's symbols (reach set, a FLOOR). files_other=N: non-changed files among those reached; the f rows are its top shown=. authors=N: distinct authors of this file (0 = no git data). bf=1: one author holds over 80% of recency-weighted commits (bus-factor risk). no-ref-work note=: the base ref's tip is the merge base, so it has no work of its own; rows are HEAD's. files=N: changed files in the diff (shown= of them listed). file symbols=: indexed symbols in that changed file. changed-symbols count= / tests count=: that section's full count (shown= of it listed). tests count=: test files reaching this file (shown= of them listed). impact files=: files holding the transitive callers (dependents=). impactf deps=: transitive callers in that file. test run=: the command that runs that test file (run_unknown=1: none derivable). changed-symbols sections=N: doc headings folded into count=, no row each; count minus sections = rows. -->
<pr-context schema="ripwire.pr-context/v1" base="HEAD~1" root="." anchor="merge-base" base_sha="219aaaacd" base_moved="0" direction="head-since-fork" files="12" skipped_mode_only="0" budget_tokens="8000" est_tokens="3062" trim_level="3" truncated="per-symbol-rows+cochange-list+owner-list-dropped" bu … [line truncated: 120 more bytes on this line]
<no-ref-work note="HEAD~1 tip == merge-base, so that ref has no divergent work of its own; this bundle is HEAD's work since the fork. For the ref's OWN diff see merge-scout or stray-content"/>
<file p="src/crossref.h" symbols="150">
<impact dependents="81" files="16" files_other="15" shown="2" capped="1">
<f p="src/slice.h" deps="27"/>
<f p="src/graph.h" deps="8"/>
</impact>
<tests count="1" shown="1" capped="0">
<test p="test/connectcore_harness.cpp" run="bash test/connectcorecheck.sh"/>
</tests>
<changed-symbols count="150"/>
<cochange window="18mo@HEAD" commits="54" partners="50" shown="0" capped="1"/>
<owners authors="5" bf="0" shown="0" capped="1"/>
</file>
<file p="src/compactlegend.h" symbols="53">
<impact dependents="50" files="12" files_other="10" shown="2" capped="1">
<f p="src/legenddict.h" deps="15"/>
<f p="src/main.cpp" deps="9"/>
</impact>
<tests count="0" shown="0" capped="0">
</tests>
<changed-symbols count="53"/>
<cochange window="18mo@HEAD" commits="181" partners="74" shown="0" capped="1"/>
<owners authors="4" bf="0" shown="0" capped="1"/>
</file>
<file p="src/mcprefusal.h" symbols="62">
<impact dependents="36" files="6" files_other="5" shown="2" capped="1">
<f p="src/verbs_lint.h" deps="4"/>
<f p="src/main.cpp" deps="3"/>
… [96 more display lines; full output is 7654 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --merge-scout=HEAD~2,HEAD~1`

*Pairwise cross-arm conflict sites + suggested landing order (any committish sharing a merge base with HEAD works as an arm; one that does not is reported ok="0", never compared).*

**wall time: 10.70s**

`````
<!-- ripwire merge-scout schema=ripwire.merge-scout/v1: cross-branch overlap of arms= refs: <arm ref= base= changed= head_conflicts=>, <pair a= b= conflicts= risks=>, <landing order=>. at=: commit+dirty+shallow. head=: the HEAD commit, bare 9-hex sha (at= adds +dirty). ok=1 on an arm row means the comparison RAN, so changed=/head_conflicts= are real and may legitimately be 0 (an empty but materialized tree is a real index); ok=0 means it did not run at all. no-work note=: arm compared and has no divergent work vs its merge base, so no landing slot. -->
<merge-scout schema="ripwire.merge-scout/v1" arms="2" head="c7920353a" at="c7920353a">
<arm ref="HEAD~2" base="6e579475a" ok="1" changed="0" head_conflicts="0">
<no-work note="no divergent work vs merge-base — see --stray-content"/>
</arm>
<arm ref="HEAD~1" base="219aaaacd" ok="1" changed="0" head_conflicts="0">
<no-work note="no divergent work vs merge-base — see --stray-content"/>
</arm>
<pair a="HEAD~2" b="HEAD~1" conflicts="0" risks="0"/>
<landing order=""/>
</merge-scout>
`````

## `./build/ripwire . --stray-content=lane/`

*Which refs of the `lane/` ref family still hold divergent authored work vs HEAD, with verdicts.*

**wall time: 3.02s**

`````
<!-- ripwire stray-content schema=ripwire.stray-content/v1: per local ref, lines/symbols NOT in HEAD: <ref ok= v= base= stray=>; v=unknown = no merge base. at=: commit+dirty+shallow. head=: the HEAD commit, bare 9-hex sha (at= adds +dirty). head_ref=: HEAD's branch (HEAD when detached); that branch itself is not scanned. refs=N: local branches scanned (refs/heads only); unmerged + superseded + merged + unknown = refs. blobs=N: distinct git blobs read for the sweep. unmerged=N: refs whose authored work the live line genuinely lacks. superseded=N: refs whose work the live line re-implemented (removed the same base code). merged=N: refs whose work HEAD already has; omitted from the rows. name=: the local branch. tip=: the branch tip commit (9 hex). date=: the tip's committer date, YYYY-MM-DD. files=N: files with stray lines; rows capped at 12, a more element counts the rest (detail=1 lists all). ref superseded=N>: of this ref's stray= lines, those in files the live line re-implemented. authored=N: lines this ref authored in the file vs its merge base. del=N: base lines this ref removed (0 = pure addition). redone=N: of del=, the base lines HEAD removed too (the supersession evidence). sim=: minhash containment, 0 to 1, of the ref's blob in HEAD's (pure-addition evidence). head-touched=1: the live line changed this path since the merge base. more files=N: N more file rows of this ref withheld; shown + N = the ref's files=; detail=1 lists all. unknown=N: refs that could not be analysed (v=unknown, e.g. no merge base); never counted merged. -->
<stray-content schema="ripwire.stray-content/v1" head="c7920353a" head_ref="lane/lean-answers-068" refs="102" blobs="971" unmerged="31" superseded="0" merged="71" unknown="0" filter="lane/" at="c7920353a">
<ref name="lane/arise-result" tip="13292db7a" date="2026-09-23" base="60b65f026" ok="1" v="unmerged" stray="16331" files="18" superseded="55">
<file p="bench/slice/results/arise_line_rank_prereg/narrowpool-results.json" v="unmerged" stray="8629" authored="8629" del="0" redone="0" sim="0.00" head-touched="0"/>
<file p="bench/slice/results/arise_line_rank_prereg/results.json" v="unmerged" stray="3810" authored="3810" del="0" redone="0" sim="0.00" head-touched="0"/>
<file p="bench/slice/results/arise_line_rank_prereg/scorer-results.json" v="unmerged" stray="1213" authored="1213" del="0" redone="0" sim="0.00" head-touched="0"/>
<file p="docs/research/arise-line-ranking-prereg.md" v="unmerged" stray="625" authored="625" del="0" redone="0" sim="0.00" head-touched="0"/>
<file p="bench/slice/score_arise_linerank.py" v="unmerged" stray="537" authored="537" del="0" redone="0" sim="0.00" head-touched="0"/>
<file p="bench/slice/run_slice_linerecall_r3.py" v="unmerged" stray="326" authored="326" del="0" redone="0" sim="0.00" head-touched="0"/>
<file p="test/slicerank_unit.cpp" v="unmerged" stray="258" authored="258" del="0" redone="0" sim="0.00" head-touched="0"/>
<file p="bench/slice/score_arise_narrowpool.py" v="unmerged" stray="199" authored="199" del="0" redone="0" sim="0.00" head-touched="0"/>
<file p="bench/slice/results/arise_line_rank_prereg/instance_ids.txt" v="unmerged" stray="182" authored="182" del="0" redone="0" sim="0.00" head-touched="0"/>
<file p="src/slice.h" v="unmerged" stray="132" authored="172" del="6" redone="0" sim="0.98" head-touched="1"/>
<file p="bench/slice/results/arise_line_rank_prereg/RESULTS.md" v="unmerged" stray="126" authored="126" del="0" redone="0" sim="0.00" head-touched="0"/>
<file p="bench/slice/results/arise_line_rank_prereg/scorer-summary.json" v="unmerged" stray="82" authored="82" del="0" redone="0" sim="0.00" head-touched="0"/>
<more files="6"/>
</ref>
<ref name="lane/margin-rescore" tip="9ffd3628c" date="2026-09-23" base="755f9026f" ok="1" v="unmerged" stray="13920" files="12" superseded="0">
<file p="bench/locbench/results/margin_rescore/calib.json" v="unmerged" stray="6592" authored="6592" del="0" redone="0" sim="0.00" head-touched="0"/>
<file p="bench/locbench/results/served_syms_prereg/calib.json" v="unmerged" stray="3862" authored="3862" del="0" redone="0" sim="0.00" head-touched="0"/>
<file p="docs/research/confidence-and-abstention.md" v="unmerged" stray="828" authored="828" del="0" redone="0" sim="0.00" head-touched="0"/>
<file p="bench/locbench/calibrate_confidence.py" v="unmerged" stray="745" authored="745" del="0" redone="0" sim="0.00" head-touched="0"/>
<file p="bench/locbench/served_syms_signal.py" v="unmerged" stray="671" authored="671" del="0" redone="0" sim="0.00" head-touched="0"/>
<file p="bench/locbench/test_served_syms_signal.py" v="unmerged" stray="588" authored="588" del="0" redone="0" sim="0.00" head-touched="0"/>
<file p="bench/locbench/results/margin_rescore/calib.md" v="unmerged" stray="214" authored="214" del="0" redone="0" sim="0.00" head-touched="0"/>
<file p="bench/locbench/results/served_syms_prereg/calib.md" v="unmerged" stray="111" authored="111" del="0" redone="0" sim="0.00" head-touched="0"/>
<file p="bench/locbench/results/margin_rescore/instance_ids.txt" v="unmerged" stray="92" authored="92" del="0" redone="0" sim="0.00" head-touched="0"/>
<file p="bench/locbench/results/served_syms_prereg/instance_ids.txt" v="unmerged" stray="92" authored="92" del="0" redone="0" sim="0.00" head-touched="0"/>
<file p="bench/locbench/results/margin_rescore/POPULATION.md" v="unmerged" stray="63" authored="63" del="0" redone="0" sim="0.00" head-touched="0"/>
<file p="bench/locbench/results/served_syms_prereg/POPULATION.md" v="unmerged" stray="62" authored="62" del="0" redone="0" sim="0.00" head-touched="0"/>
… [319 more display lines; full output is 39445 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --stray-content=arm/for-howitworks-067-f2add`

*A second selection, the one branch `arm/for-howitworks-067-f2add` (no ref family left to select on this checkout), picked at capture time from the refs this checkout really has and never the selection above: merged refs are OMITTED from the rows and counted in merged=; refs sharing no merge base with HEAD (a shallow clone, or a pre-rewrite history) land in unknown= with ok="0" — the counters always reconcile against refs=.*

`````
<!-- ripwire stray-content schema=ripwire.stray-content/v1: per local ref, lines/symbols NOT in HEAD: <ref ok= v= base= stray=>; v=unknown = no merge base. at=: commit+dirty+shallow. head=: the HEAD commit, bare 9-hex sha (at= adds +dirty). head_ref=: HEAD's branch (HEAD when detached); that branch itself is not scanned. refs=N: local branches scanned (refs/heads only); unmerged + superseded + merged + unknown = refs. blobs=N: distinct git blobs read for the sweep. unmerged=N: refs whose authored work the live line genuinely lacks. superseded=N: refs whose work the live line re-implemented (removed the same base code). merged=N: refs whose work HEAD already has; omitted from the rows. name=: the local branch. tip=: the branch tip commit (9 hex). date=: the tip's committer date, YYYY-MM-DD. files=N: files with stray lines; rows capped at 12, a more element counts the rest (detail=1 lists all). ref superseded=N>: of this ref's stray= lines, those in files the live line re-implemented. authored=N: lines this ref authored in the file vs its merge base. del=N: base lines this ref removed (0 = pure addition). redone=N: of del=, the base lines HEAD removed too (the supersession evidence). sim=: minhash containment, 0 to 1, of the ref's blob in HEAD's (pure-addition evidence). head-touched=1: the live line changed this path since the merge base. more files=N: N more file rows of this ref withheld; shown + N = the ref's files=; detail=1 lists all. unknown=N: refs that could not be analysed (v=unknown, e.g. no merge base); never counted merged. -->
<stray-content schema="ripwire.stray-content/v1" head="c7920353a" head_ref="lane/lean-answers-068" refs="1" blobs="91" unmerged="1" superseded="0" merged="0" unknown="0" filter="arm/for-howitworks-067-f2add" at="c7920353a">
<ref name="arm/for-howitworks-067-f2add" tip="abcbd8b7f" date="2026-10-02" base="953818d6f" ok="1" v="unmerged" stray="3270" files="38" superseded="40">
<file p="src/forhow.h" v="unmerged" stray="2160" authored="2160" del="0" redone="0" sim="0.00" head-touched="0"/>
<file p="test/forhowcheck.sh" v="unmerged" stray="472" authored="472" del="0" redone="0" sim="0.00" head-touched="0"/>
<file p="src/forhowbase.h" v="unmerged" stray="141" authored="141" del="0" redone="0" sim="0.00" head-touched="0"/>
<file p=".ripwire_quality_acks" v="unmerged" stray="73" authored="73" del="7" redone="0" sim="0.95" head-touched="1"/>
<file p="src/mcpverbs.h" v="unmerged" stray="62" authored="76" del="21" redone="0" sim="0.95" head-touched="1"/>
<file p="CHANGELOG.md" v="unmerged" stray="52" authored="52" del="0" redone="0" sim="0.82" head-touched="1"/>
<file p="test/compactroutecheck.sh" v="unmerged" stray="31" authored="32" del="1" redone="0" sim="0.59" head-touched="0"/>
<file p="src/legenddict.h" v="unmerged" stray="26" authored="35" del="4" redone="0" sim="0.98" head-touched="1"/>
<file p="src/verbs_for.h" v="unmerged" stray="26" authored="26" del="60" redone="0" sim="0.98" head-touched="1"/>
<file p="test/callsrankordercheck.sh" v="unmerged" stray="24" authored="25" del="5" redone="0" sim="0.43" head-touched="0"/>
<file p="test/mentioncheck.sh" v="unmerged" stray="23" authored="24" del="4" redone="0" sim="0.96" head-touched="0"/>
<file p="src/cli.h" v="unmerged" stray="21" authored="21" del="1" redone="0" sim="0.99" head-touched="1"/>
<more files="26"/>
</ref>
</stray-content>
`````

## `./build/ripwire . --stray-content=lane/ --plan`

*Select the genuinely-unmerged refs of the `lane/` ref family and feed them to merge-scout for a landing order (a fully merged selection yields an empty landing set — still a measurement, disclosed on the root).*

**wall time: 59.44s**

`````
<!-- ripwire landing-plan schema=ripwire.landing-plan/v1: stranded-work landing order across refs, fewest conflicts first. at=: commit+dirty+shallow. -->
<landing-plan schema="ripwire.landing-plan/v1" head="c7920353a" refs="102" unmerged="31" superseded="0" merged="71" undetermined="0" scouted="12" bounded="19" scout-ok="1" at="c7920353a">
<ref name="lane/arise-result" v="unmerged" stray="16331" files="18" scouted="1"/>
<ref name="lane/margin-rescore" v="unmerged" stray="13920" files="12" scouted="1"/>
<ref name="lane/fe-b-receiver-evidence" v="unmerged" stray="12232" files="233" scouted="1"/>
<ref name="lane/cr-qd-kinds-068" v="unmerged" stray="11192" files="52" scouted="1"/>
<ref name="lane/partition-date-068" v="unmerged" stray="6920" files="37" scouted="1"/>
<ref name="lane/served-syms-result" v="unmerged" stray="6345" files="8" scouted="1"/>
<ref name="lane/orient-narrow-v3" v="unmerged" stray="3270" files="46" scouted="1"/>
<ref name="lane/for-howitworks-067" v="unmerged" stray="3247" files="38" scouted="1"/>
<ref name="lane/m1-lookback-harness" v="unmerged" stray="3164" files="14" scouted="1"/>
<ref name="lane/orient-map-067" v="unmerged" stray="2472" files="40" scouted="1"/>
<ref name="lane/served-syms-prereg" v="unmerged" stray="2134" files="4" scouted="1"/>
<ref name="lane/crossctx-external-prereg" v="unmerged" stray="2054" files="6" scouted="1"/>
<ref name="lane/for-spine-span-068" v="unmerged" stray="1686" files="61" scouted="0"/>
<ref name="lane/arise-line-ranking" v="unmerged" stray="1538" files="7" scouted="0"/>
<ref name="lane/knob-honesty-068" v="unmerged" stray="1137" files="35" scouted="0"/>
<ref name="lane/count-floor-068" v="unmerged" stray="1028" files="22" scouted="0"/>
<ref name="lane/honesty-small-068" v="unmerged" stray="922" files="39" scouted="0"/>
<ref name="lane/research-abstention" v="unmerged" stray="898" files="2" scouted="0"/>
<ref name="lane/asan-reload-068" v="unmerged" stray="849" files="8" scouted="0"/>
<ref name="lane/route-channel-381" v="unmerged" stray="629" files="15" scouted="0"/>
<ref name="lane/train25-cr2-followup" v="unmerged" stray="626" files="35" scouted="0"/>
<ref name="lane/tracked-in-skipdirs-065" v="unmerged" stray="332" files="14" scouted="0"/>
<ref name="lane/testgate-subdir-335" v="unmerged" stray="268" files="4" scouted="0"/>
<ref name="lane/asan-toolchain-probe-068" v="unmerged" stray="206" files="9" scouted="0"/>
<ref name="lane/perf-hoist-068" v="unmerged" stray="198" files="16" scouted="0"/>
<ref name="lane/cr-siblings-068" v="unmerged" stray="121" files="4" scouted="0"/>
<ref name="lane/agent-surface-scan-066" v="unmerged" stray="79" files="4" scouted="0"/>
<ref name="lane/deck-refresh-068" v="unmerged" stray="16" files="1" scouted="0"/>
… [115194 more display lines; full output is 12883655 bytes on 1 raw line(s)]
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

## `./build/ripwire . --stray-content=lane/ --abi`

*Cross-branch ABI-break gate over the `lane/` ref family: struct byte-contract drift on each ref's AUTHORED paths — exit 2 when any drift row is found (the only kind that gates), 0 when the compared refs are clean, and exit 1 if the --stray-content filter matches no ref at all.*

**exit code: 2** — **wall time: 14.23s**

`````
<!-- ripwire abi schema=ripwire.abi/v1: contract diff of the indexed symbols between two refs: added/removed/changed signatures. window: shown= capped= (capped=1 cut). at=: commit+dirty+shallow. root=: p= relative to it. -->
<abi schema="ripwire.abi/v1" head="c7920353a" head_ref="lane/lean-answers-068" refs="102" candidates="1426" compared="571" blobs="227" rows="140" shown="10" capped="0" dropped="0" excluded="130" head_only="65820" unmodelable="1961" unrelated="0" broken_refs="5" quiet="85" excluded_refs="9" at="c7920 … [line truncated: 65 more bytes on this line]
<ref name="lane/for-spine-span-068" tip="639165805" date="2026-10-08" rows="9" shown="2" capped="0" excluded="7" head_only="77" drift="2" head-moved="7">
<struct n="JsonSigLens" p="src/serialize.h" l="9045" kind="drift" head_size="72" ref_size="80" size_differs="1" size_delta="8">
<d n="endLines" a="absent" b="bool@72"/>
<d n="docsAfterCode" a="absent" b="bool@73"/>
</struct>
<struct n="SigsCutReport" p="src/serialize.h" l="4514" kind="drift" head_size="32" ref_size="40" size_differs="1" size_delta="8">
<d n="docsAfterCode" a="absent" b="std::size_t@32"/>
</struct>
</ref>
<ref name="lane/perf-hoist-068" tip="c577d46b4" date="2026-10-07" rows="14" shown="2" capped="0" excluded="12" head_only="135" drift="2" head-moved="12">
<struct n="PerfState" p="src/infra/profilePmc.h" l="544" kind="drift" head_size="168" ref_size="240" size_differs="1" size_delta="72">
<d n="event_count" a="unsigned@4" b="unsigned@40"/>
<d n="table_index" a="unsigned x8@8" b="absent"/>
<d n="names" a="const char** x8@40" b="const char** x8@48"/>
<d n="labels" a="const char** x8@104" b="const char** x8@112"/>
<d n="db" a="absent" b="kpep_db**@8"/>
<d n="cfg" a="absent" b="kpep_config**@16"/>
<d n="classes" a="absent" b="uint32_t@24"/>
<d n="prev_forced" a="absent" b="int@28"/>
<d n="forced" a="absent" b="bool@32"/>
<d n="counter_count" a="absent" b="uint32_t@36"/>
<d n="kpc_map" a="absent" b="size_t x8@176"/>
</struct>
<struct n="PerfState" p="src/infra/profilePmc.h" l="272" kind="drift" head_size="232" ref_size="240" size_differs="1" size_delta="8">
<d n="counter_count" a="uint32_t@28" b="uint32_t@36"/>
<d n="event_count" a="unsigned@32" b="unsigned@40"/>
<d n="names" a="const char** x8@40" b="const char** x8@48"/>
<d n="labels" a="const char** x8@104" b="const char** x8@112"/>
… [37 more display lines; full output is 4510 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --whereis=rankGraphTeleport`

*Which ref's tree defines or mentions SYM — HEAD first, then every local branch. The default lists the kind="def" rows (here the first 60, most on branches, each carrying tip= and date=) and counts the references in <refs count= next=>: on this symbol HEAD's references would fill the 60-row cap before the branch definitions arrive, so the whole list (below) shows fewer definitions, and the default serves the page that shows more of them, whatever its bytes.*

**wall time: 9.47s**

`````
<!-- ripwire whereis schema=ripwire.whereis/v1: every LOCAL ref whose tree holds sym= (refs_scanned=, blobs=), HEAD first: <hit ref= tip= date= p= l= kind= t=>. window: shown= total= capped= has_more= next_offset= offset= limit= (capped=1 cut; next_offset= pastes as offset=). at=: commit+dirty+shallow. next=: the one pasteable follow-up. hits=N: occurrences in HEAD plus every scanned local ref's full tree (the total rows). on-head=1|0: whether HEAD's tree holds it; 0 beside hits = it lives only on a branch. head_labels=index: HEAD kind= from the parsed index; lexical: text heuristic (non-HEAD rows always are). hit test_local=1: a definition in a test scope or under a test/bench/fixture path, ordered after the production definitions (only when both exist; nothing dropped). more hits=N: rows after this page; page on with offset=next_offset. listing=defs|refs: only those kind= rows listed; under defs <refs count=N next=> counts the kind=ref rows and next= lists them; the window counts listed rows; default: defs if it lists more defs than all, else if shorter; a def the parser does not model (define_method, setattr, assignment) is a counted ref. head_date=: a hit without tip= date= has tip= at=, date= this. -->
<whereis schema="ripwire.whereis/v1" sym="rankGraphTeleport" on-head="1" refs_scanned="136" blobs="6012" hits="332882" head_labels="index" shown="60" capped="1" total="9859" has_more="1" next_offset="60" offset="0" limit="0" listing="defs" head_date="2026-10-08" at="c7920353a">
<hit ref="HEAD" p="src/graph.h" l="5565" kind="def" t="inline RankedGraph rankGraphTeleport( const Graph&amp; g, const std::vector&lt;float&gt;&amp; p, float alpha = 0.85f )"/>
<hit ref="arm/for-howitworks-067-f2add" tip="abcbd8b7f" date="2026-10-02" p="src/graph.h" l="4645" kind="def" t="inline RankedGraph rankGraphTeleport( const Graph&amp; g, const std::vector&lt;float&gt;&amp; p, float alpha = 0.85f )"/>
<hit ref="arm/for-howitworks-067-f2add" tip="abcbd8b7f" date="2026-10-02" p="src/main.cpp" l="1434" kind="def" t="rw::RankedGraph    ranked = isDecay ? rankGraphTeleport( d.g, churnDecayTeleportWorkspace( rootDirs, d.ing, &amp;hasChurnEvidence ) )"/>
<hit ref="arm/for-howitworks-067-f2add" tip="abcbd8b7f" date="2026-10-02" p="bench/recalleval/snapshot.mdpack" l="14490" kind="def" test_local="1" t="&lt;hit ref=&quot;HEAD&quot; tip=&quot;bc09d0260&quot; date=&quot;2026-08-01&quot; p=&quot;test/crossrefcheck.sh&quot; l=&quot;234&quot; kind=&quot;re … [line truncated: 191 more bytes on this line]
<hit ref="arm/for-howitworks-067-f2add" tip="abcbd8b7f" date="2026-10-02" p="bench/recalleval/snapshot.mdpack" l="14935" kind="def" test_local="1" t="&lt;![CDATA[inline std::vector&lt;float&gt; rankGraphTeleport( const Graph&amp; g, const std::vector&lt;float&gt;&amp; p, float alpha = 0.85f )"/>
<hit ref="arm/for-howitworks-067-f2add" tip="abcbd8b7f" date="2026-10-02" p="test/crossrefcheck.sh" l="234" kind="def" test_local="1" t="&quot;def src/graph.h&quot;) ok &quot;whereis: rankGraphTeleport&apos;s first def row is src/graph.h (was a docs/captures CDATA row)&quot; ;;"/>
<hit ref="arm/for-howitworks-067-f2add" tip="abcbd8b7f" date="2026-10-02" p="test/showcase_capture.py" l="174" kind="def" test_local="1" t="#0 0x102f4a1c8 in rw::rankGraphTeleport(Graph const&amp;, std::vector&lt;float&gt; const&amp;, float) src/graph.h:{TELEPORT_LN}"/>
<hit ref="arm/for-howitworks-067-f2add" tip="abcbd8b7f" date="2026-10-02" p="docs/COMMANDS.md" l="202" kind="def" t="&lt;![CDATA[inline RankedGraph rankGraphTeleport( const Graph&amp; g, const std::vector&lt;float&gt;&amp; p, float alpha = 0.85f )"/>
<hit ref="arm/for-howitworks-067-f2add" tip="abcbd8b7f" date="2026-10-02" p="docs/COMMANDS.md" l="1591" kind="def" t="&lt;![CDATA[inline RankedGraph rankGraphTeleport( const Graph&amp; g, const std::vector&lt;float&gt;&amp; p, float alpha = 0.85f )"/>
<hit ref="arm/for-howitworks-067-f2add" tip="abcbd8b7f" date="2026-10-02" p="docs/captures/COMMANDS_showcase_2026-08-10.md" l="2767" kind="def" t="&lt;![CDATA[inline std::vector&lt;float&gt; rankGraphTeleport( const Graph&amp; g, const std::vector&lt;float&gt;&amp; p, float alpha = 0.85f )"/>
<hit ref="arm/for-howitworks-067-f2add" tip="abcbd8b7f" date="2026-10-02" p="docs/captures/COMMANDS_showcase_2026-08-14.md" l="2858" kind="def" t="&lt;![CDATA[inline std::vector&lt;float&gt; rankGraphTeleport( const Graph&amp; g, const std::vector&lt;float&gt;&amp; p, float alpha = 0.85f )"/>
<hit ref="arm/for-howitworks-067-f2add" tip="abcbd8b7f" date="2026-10-02" p="docs/captures/COMMANDS_showcase_2026-08-15.md" l="92" kind="def" t="&lt;![CDATA[inline std::vector&lt;float&gt; rankGraphTeleport( const Graph&amp; g, const std::vector&lt;float&gt;&amp; p, float alpha = 0.85f )"/>
<hit ref="arm/for-howitworks-067-f2add" tip="abcbd8b7f" date="2026-10-02" p="docs/captures/COMMANDS_showcase_2026-08-15.md" l="1339" kind="def" t="&lt;![CDATA[inline std::vector&lt;float&gt; rankGraphTeleport( const Graph&amp; g, const std::vector&lt;float&gt;&amp; p, float alpha = 0.85f )"/>
<hit ref="arm/for-howitworks-067-f2add" tip="abcbd8b7f" date="2026-10-02" p="docs/captures/COMMANDS_showcase_2026-08-15.md" l="1377" kind="def" t="&lt;![CDATA[inline std::vector&lt;float&gt; rankGraphTeleport( const Graph&amp; g, const std::vector&lt;float&gt;&amp; p, float alpha = 0.85f )"/>
<hit ref="arm/for-howitworks-067-f2add" tip="abcbd8b7f" date="2026-10-02" p="docs/captures/COMMANDS_showcase_2026-08-15.md" l="2918" kind="def" t="&lt;![CDATA[inline std::vector&lt;float&gt; rankGraphTeleport( const Graph&amp; g, const std::vector&lt;float&gt;&amp; p, float alpha = 0.85f )"/>
<hit ref="arm/for-howitworks-067-f2add" tip="abcbd8b7f" date="2026-10-02" p="docs/captures/COMMANDS_showcase_2026-08-20.md" l="94" kind="def" t="&lt;![CDATA[inline RankedGraph rankGraphTeleport( const Graph&amp; g, const std::vector&lt;float&gt;&amp; p, float alpha = 0.85f )"/>
<hit ref="arm/for-howitworks-067-f2add" tip="abcbd8b7f" date="2026-10-02" p="docs/captures/COMMANDS_showcase_2026-08-20.md" l="1303" kind="def" t="&lt;![CDATA[inline RankedGraph rankGraphTeleport( const Graph&amp; g, const std::vector&lt;float&gt;&amp; p, float alpha = 0.85f )"/>
<hit ref="arm/for-howitworks-067-f2add" tip="abcbd8b7f" date="2026-10-02" p="docs/captures/COMMANDS_showcase_2026-08-20.md" l="1342" kind="def" t="&lt;![CDATA[inline RankedGraph rankGraphTeleport( const Graph&amp; g, const std::vector&lt;float&gt;&amp; p, float alpha = 0.85f )"/>
<hit ref="arm/for-howitworks-067-f2add" tip="abcbd8b7f" date="2026-10-02" p="docs/captures/COMMANDS_showcase_2026-08-20.md" l="2788" kind="def" t="&lt;![CDATA[inline RankedGraph rankGraphTeleport( const Graph&amp; g, const std::vector&lt;float&gt;&amp; p, float alpha = 0.85f )"/>
<hit ref="arm/for-howitworks-067-f2add" tip="abcbd8b7f" date="2026-10-02" p="docs/captures/COMMANDS_showcase_2026-08-21.md" l="94" kind="def" t="&lt;![CDATA[inline RankedGraph rankGraphTeleport( const Graph&amp; g, const std::vector&lt;float&gt;&amp; p, float alpha = 0.85f )"/>
<hit ref="arm/for-howitworks-067-f2add" tip="abcbd8b7f" date="2026-10-02" p="docs/captures/COMMANDS_showcase_2026-08-21.md" l="1314" kind="def" t="&lt;![CDATA[inline RankedGraph rankGraphTeleport( const Graph&amp; g, const std::vector&lt;float&gt;&amp; p, float alpha = 0.85f )"/>
<hit ref="arm/for-howitworks-067-f2add" tip="abcbd8b7f" date="2026-10-02" p="docs/captures/COMMANDS_showcase_2026-08-21.md" l="1353" kind="def" t="&lt;![CDATA[inline RankedGraph rankGraphTeleport( const Graph&amp; g, const std::vector&lt;float&gt;&amp; p, float alpha = 0.85f )"/>
<hit ref="arm/for-howitworks-067-f2add" tip="abcbd8b7f" date="2026-10-02" p="docs/captures/COMMANDS_showcase_2026-08-21.md" l="2833" kind="def" t="&lt;![CDATA[inline RankedGraph rankGraphTeleport( const Graph&amp; g, const std::vector&lt;float&gt;&amp; p, float alpha = 0.85f )"/>
<hit ref="arm/for-howitworks-067-f2add" tip="abcbd8b7f" date="2026-10-02" p="docs/captures/COMMANDS_showcase_2026-08-22.md" l="94" kind="def" t="&lt;![CDATA[inline RankedGraph rankGraphTeleport( const Graph&amp; g, const std::vector&lt;float&gt;&amp; p, float alpha = 0.85f )"/>
<hit ref="arm/for-howitworks-067-f2add" tip="abcbd8b7f" date="2026-10-02" p="docs/captures/COMMANDS_showcase_2026-08-22.md" l="255" kind="def" t="&lt;![CDATA[inline RankedGraph rankGraphTeleport( const Graph&amp; g, const std::vector&lt;float&gt;&amp; p, float alpha = 0.85f )"/>
<hit ref="arm/for-howitworks-067-f2add" tip="abcbd8b7f" date="2026-10-02" p="docs/captures/COMMANDS_showcase_2026-08-22.md" l="1288" kind="def" t="&lt;![CDATA[inline RankedGraph rankGraphTeleport( const Graph&amp; g, const std::vector&lt;float&gt;&amp; p, float alpha = 0.85f )"/>
<hit ref="arm/for-howitworks-067-f2add" tip="abcbd8b7f" date="2026-10-02" p="docs/captures/COMMANDS_showcase_2026-08-22.md" l="1327" kind="def" t="&lt;![CDATA[inline RankedGraph rankGraphTeleport( const Graph&amp; g, const std::vector&lt;float&gt;&amp; p, float alpha = 0.85f )"/>
<hit ref="arm/for-howitworks-067-f2add" tip="abcbd8b7f" date="2026-10-02" p="docs/captures/COMMANDS_showcase_2026-08-22.md" l="2782" kind="def" t="&lt;![CDATA[inline RankedGraph rankGraphTeleport( const Graph&amp; g, const std::vector&lt;float&gt;&amp; p, float alpha = 0.85f )"/>
… [35 more display lines; full output is 18444 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --whereis=rankGraphTeleport --whereis-listing=all`

*The whole hit list asked for by name: under the same 60-row cap HEAD's references fill the list, so it shows far fewer definitions (here HEAD's one) than the default above (here 60). The default serves the all page only when it shows the same definitions as the defs page in strictly fewer bytes (a tie serves it too).*

**wall time: 9.48s**

`````
<!-- ripwire whereis schema=ripwire.whereis/v1: every LOCAL ref whose tree holds sym= (refs_scanned=, blobs=), HEAD first: <hit ref= tip= date= p= l= kind= t=>. window: shown= total= capped= has_more= next_offset= offset= limit= (capped=1 cut; next_offset= pastes as offset=). at=: commit+dirty+shallow. hits=N: occurrences in HEAD plus every scanned local ref's full tree (the total rows). on-head=1|0: whether HEAD's tree holds it; 0 beside hits = it lives only on a branch. head_labels=index: HEAD kind= from the parsed index; lexical: text heuristic (non-HEAD rows always are). more hits=N: rows after this page; page on with offset=next_offset. head_date=: a hit without tip= date= has tip= at=, date= this. -->
<whereis schema="ripwire.whereis/v1" sym="rankGraphTeleport" on-head="1" refs_scanned="136" blobs="6012" hits="332882" head_labels="index" shown="60" capped="1" total="332882" has_more="1" next_offset="60" offset="0" limit="0" head_date="2026-10-08" at="c7920353a">
<hit ref="HEAD" p="src/graph.h" l="5565" kind="def" t="inline RankedGraph rankGraphTeleport( const Graph&amp; g, const std::vector&lt;float&gt;&amp; p, float alpha = 0.85f )"/>
<hit ref="HEAD" p=".ripwire_quality_acks" l="1226" kind="ref" t="ack short-horizon-churn 89b3fd14c192c899 116 cid=b6e271ab92996f75 by=src/* macro-vocabulary rename (VERIFY/DEGRADED_PATH_ALERT family -&gt; ASSUME/EXPECTS/ENSURES/DASSERT/UNREACHABLE/VALIDATE/DISCLOSE): identifier-only churn across 179 … [line truncated: 586 more bytes on this line]
<hit ref="HEAD" p="present/deck5_ripwire_build.js" l="1157" kind="ref" t="s.addText(&quot;$ ripwire . --callers=rankGraphTeleport&quot;, { x: 8.68, y: 2.1, w: 3.8, h: 0.3, fontFace: MONO, fontSize: 10, color: MUTED, margin: 0 });"/>
<hit ref="HEAD" p="present/deck5_ripwire_build.js" l="1159" kind="ref" t="{ text: &quot;&lt;callers of=\&quot;rankGraphTeleport\&quot;\n  defs=\&quot;1\&quot; count=\&quot;7\&quot; &quot;, options: { color: TEXT } },"/>
<hit ref="HEAD" p="present/deck5_ripwire_build.js" l="1173" kind="ref" t="&quot;- The --callers example: `ripwire . --callers=rankGraphTeleport` answered defs=\&quot;1\&quot; count=\&quot;6\&quot; counts_floor=\&quot;1\&quot;, with runEval and rankGraph as its first two rows, on main 40a1895b. On ma … [line truncated: 260 more bytes on this line]
<hit ref="HEAD" p="src/cli.h" l="85" kind="ref" t="// tokens on --around=rankGraphTeleport vs 5,860 B at depth 1; the root&apos;s"/>
<hit ref="HEAD" p="src/crossref.h" l="2240" kind="ref" t="// code above the real definition: `--whereis=rankGraphTeleport` opened with three kind=&quot;def&quot; rows into"/>
<hit ref="HEAD" p="src/didyoumean.h" l="238" kind="ref" t="// `--path=rankGraphTeleport,` printed &quot;endpoint not found:  (did you mean &apos;A&apos;?)&quot;. Guarded at the shared walk"/>
<hit ref="HEAD" p="src/eval.h" l="325" kind="ref" t="const std::vector&lt;float&gt; r = rankGraphTeleport( g, diffTeleport( ing, seedMask ) ).rank;"/>
<hit ref="HEAD" p="src/graph.h" l="165" kind="ref" t="// renormalized to Σ=1 in rankGraphTeleport — so every teleport-based"/>
<hit ref="HEAD" p="src/graph.h" l="5504" kind="ref" t="// prior (never the edges) and renormalized in rankGraphTeleport. Every symbol whose name is missing from"/>
<hit ref="HEAD" p="src/graph.h" l="5553" kind="ref" t="// discard out. That is what this used to be: rankGraphTeleport called pageRankDouble, threw away its return,"/>
<hit ref="HEAD" p="src/graph.h" l="5598" kind="ref" t="// `rank = takeRank( rankGraphTeleport( … ), d )` is the only spelling, and it fills both or neither."/>
<hit ref="HEAD" p="src/graph.h" l="5609" kind="ref" t="return rankGraphTeleport( g, std::vector&lt;float&gt;( N, N ? 1.0f / float( N ) : 0.f ), alpha );"/>
<hit ref="HEAD" p="src/graph.h" l="6233" kind="ref" t="// the anchor-count is not a cliff), run the EXISTING PPR machinery (rankGraphTeleport — the same"/>
<hit ref="HEAD" p="src/graph.h" l="6303" kind="ref" t="const std::vector&lt;float&gt; ppr = rankGraphTeleport( g, p ).rank;"/>
<hit ref="HEAD" p="src/main.cpp" l="1394" kind="ref" t="rw::RankedGraph ranked  = stubbed ? rw::RankedGraph{} : rankGraphTeleport( d.g, churnPriorFromDecayed( d.ing, mined.weights, mined.anyHistory ) );"/>
<hit ref="HEAD" p="src/main.cpp" l="1433" kind="ref" t="rw::RankedGraph    ranked = isDecay ? rankGraphTeleport( d.g, churnDecayTeleportWorkspace( rootDirs, d.ing, &amp;hasChurnEvidence ) )"/>
<hit ref="HEAD" p="src/main.cpp" l="1434" kind="ref" t=": rankGraphTeleport( d.g, churnTeleportWorkspace( rootDirs, d.ing, &quot;18 months ago&quot;, &amp;hasChurnEvidence ) );"/>
<hit ref="HEAD" p="src/main.cpp" l="1448" kind="ref" t="rw::RankedGraph    ranked = rankGraphTeleport( d.g, churnTeleport( d.root, d.ing, &quot;18 months ago&quot;, d.cfg.since.empty() ? nullptr : &amp;sinceScope, &amp;hasChurnEvidence ) );"/>
<hit ref="HEAD" p="src/main.cpp" l="1749" kind="ref" t="rank = rw::takeRank( rankGraphTeleport( g, diffTeleport( ing, changed ) ), rankDisclosure );"/>
<hit ref="HEAD" p="src/mcp.h" l="2682" kind="ref" t="//   queries:[&quot;callers:rankGraphTeleport&quot;, {&quot;verb&quot;:&quot;slice&quot;,&quot;symbol&quot;:&quot;…&quot;}]"/>
<hit ref="HEAD" p="src/mcpindex.h" l="1232" kind="ref" t="// symbols, the rest uniform, then rankGraphTeleport (which also applies the name-quality biasPrior"/>
<hit ref="HEAD" p="src/mcpindex.h" l="1268" kind="ref" t="const auto [ wsRank, wsIters, wsConverged ] = rankGraphTeleport( ix.g, diffTeleport( ix.ing, changed ) );"/>
<hit ref="HEAD" p="src/mcpverbs.h" l="5123" kind="ref" t="// the colon is a SEPARATOR, and `callers: rankGraphTeleport` is how a human writes one. Untrimmed, the"/>
<hit ref="HEAD" p="src/mcpverbs.h" l="5125" kind="ref" t="//   symbol not found: &apos; rankGraphTeleport&apos; (did you mean &apos;rankGraphTeleport&apos;?)"/>
<hit ref="HEAD" p="src/selectorrefuse.h" l="7" kind="ref" t="// (&quot;that file defines no &apos;rankGraphTeleport&apos;&quot;), names the files that DO define the name, and hands back a"/>
<hit ref="HEAD" p="bench/capsweep/capsweep.py" l="173" kind="ref" t="# all and passes through untouched — `. --pattern=\&apos;rankGraphTeleport($A, $B, $C)\&apos;` is a tree-sitter pattern"/>
… [34 more display lines; full output is 13695 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --whereis=computeOnePairOverlap --with-history`

*Same, plus a git-history <fate> row (never / removed-by-commit) for names no tree carries.*

**wall time: 16.05s**

`````
<!-- ripwire whereis schema=ripwire.whereis/v1: every LOCAL ref whose tree holds sym= (refs_scanned=, blobs=), HEAD first: <hit ref= tip= date= p= l= kind= t=>. window: shown= total= capped= has_more= next_offset= offset= limit= (capped=1 cut; next_offset= pastes as offset=). at=: commit+dirty+shallow. next=: the one pasteable follow-up. hits=N: occurrences in HEAD plus every scanned local ref's full tree (the total rows). on-head=1|0: whether HEAD's tree holds it; 0 beside hits = it lives only on a branch. head_labels=index: HEAD kind= from the parsed index; lexical: text heuristic (non-HEAD rows always are). more hits=N: rows after this page; page on with offset=next_offset. listing=defs|refs: only those kind= rows listed; under defs <refs count=N next=> counts the kind=ref rows and next= lists them; the window counts listed rows; default: defs if it lists more defs than all, else if shorter; a def the parser does not model (define_method, setattr, assignment) is a counted ref. head_date=: a hit without tip= date= has tip= at=, date= this. -->
<whereis schema="ripwire.whereis/v1" sym="computeOnePairOverlap" on-head="1" refs_scanned="136" blobs="6012" hits="37159" head_labels="index" shown="60" capped="1" total="137" has_more="1" next_offset="60" offset="0" limit="0" listing="defs" head_date="2026-10-08" at="c7920353a">
<history probed="1" head="c7920353a" commits="3565" removed-names="42542"/>
<hit ref="HEAD" p="src/mergescout.h" l="696" kind="def" t="inline PairOverlap computeOnePairOverlap( std::size_t a, std::size_t b, const Arm&amp; armA, const Arm&amp; armB )"/>
<hit ref="arm/for-howitworks-067-f2add" tip="abcbd8b7f" date="2026-10-02" p="src/mergescout.h" l="696" kind="def" t="inline PairOverlap computeOnePairOverlap( std::size_t a, std::size_t b, const Arm&amp; armA, const Arm&amp; armB )"/>
<hit ref="arm/for-howitworks-067-placebo" tip="20cd12362" date="2026-10-02" p="src/mergescout.h" l="696" kind="def" t="inline PairOverlap computeOnePairOverlap( std::size_t a, std::size_t b, const Arm&amp; armA, const Arm&amp; armB )"/>
<hit ref="arm/orient-map-067-narrow" tip="cf40f2e31" date="2026-10-02" p="src/mergescout.h" l="696" kind="def" t="inline PairOverlap computeOnePairOverlap( std::size_t a, std::size_t b, const Arm&amp; armA, const Arm&amp; armB )"/>
<hit ref="arm/orient-map-067-placebo" tip="b1cfb6a18" date="2026-10-02" p="src/mergescout.h" l="696" kind="def" t="inline PairOverlap computeOnePairOverlap( std::size_t a, std::size_t b, const Arm&amp; armA, const Arm&amp; armB )"/>
<hit ref="arm/orient-narrow-v3-placebo" tip="b01c70c1c" date="2026-10-04" p="src/mergescout.h" l="696" kind="def" t="inline PairOverlap computeOnePairOverlap( std::size_t a, std::size_t b, const Arm&amp; armA, const Arm&amp; armB )"/>
<hit ref="backup/train-26a-a3cdcce3" tip="a3cdcce34" date="2026-10-07" p="src/mergescout.h" l="696" kind="def" t="inline PairOverlap computeOnePairOverlap( std::size_t a, std::size_t b, const Arm&amp; armA, const Arm&amp; armB )"/>
<hit ref="integration/train-17" tip="33c391528" date="2026-09-23" p="src/mergescout.h" l="696" kind="def" t="inline PairOverlap computeOnePairOverlap( std::size_t a, std::size_t b, const Arm&amp; armA, const Arm&amp; armB )"/>
<hit ref="integration/train-18" tip="a2faa5255" date="2026-09-24" p="src/mergescout.h" l="696" kind="def" t="inline PairOverlap computeOnePairOverlap( std::size_t a, std::size_t b, const Arm&amp; armA, const Arm&amp; armB )"/>
<hit ref="integration/train-19" tip="179634105" date="2026-09-24" p="src/mergescout.h" l="696" kind="def" t="inline PairOverlap computeOnePairOverlap( std::size_t a, std::size_t b, const Arm&amp; armA, const Arm&amp; armB )"/>
<hit ref="integration/train-20" tip="f4db53be0" date="2026-09-25" p="src/mergescout.h" l="696" kind="def" t="inline PairOverlap computeOnePairOverlap( std::size_t a, std::size_t b, const Arm&amp; armA, const Arm&amp; armB )"/>
<hit ref="integration/train-21" tip="912e3cd79" date="2026-09-27" p="src/mergescout.h" l="696" kind="def" t="inline PairOverlap computeOnePairOverlap( std::size_t a, std::size_t b, const Arm&amp; armA, const Arm&amp; armB )"/>
<hit ref="integration/train-23" tip="365c25cca" date="2026-10-02" p="src/mergescout.h" l="696" kind="def" t="inline PairOverlap computeOnePairOverlap( std::size_t a, std::size_t b, const Arm&amp; armA, const Arm&amp; armB )"/>
<hit ref="integration/train-24" tip="17e37c8ec" date="2026-10-03" p="src/mergescout.h" l="696" kind="def" t="inline PairOverlap computeOnePairOverlap( std::size_t a, std::size_t b, const Arm&amp; armA, const Arm&amp; armB )"/>
<hit ref="integration/train-25" tip="0c1153103" date="2026-10-04" p="src/mergescout.h" l="696" kind="def" t="inline PairOverlap computeOnePairOverlap( std::size_t a, std::size_t b, const Arm&amp; armA, const Arm&amp; armB )"/>
<hit ref="integration/train-26a" tip="cd87e30e1" date="2026-10-07" p="src/mergescout.h" l="696" kind="def" t="inline PairOverlap computeOnePairOverlap( std::size_t a, std::size_t b, const Arm&amp; armA, const Arm&amp; armB )"/>
<hit ref="lane/ack-backfill-followups" tip="2e6ad58f4" date="2026-09-23" p="src/mergescout.h" l="696" kind="def" t="inline PairOverlap computeOnePairOverlap( std::size_t a, std::size_t b, const Arm&amp; armA, const Arm&amp; armB )"/>
<hit ref="lane/agent-surface-scan-066" tip="e07f63046" date="2026-09-28" p="src/mergescout.h" l="696" kind="def" t="inline PairOverlap computeOnePairOverlap( std::size_t a, std::size_t b, const Arm&amp; armA, const Arm&amp; armB )"/>
<hit ref="lane/answer-completeness-design" tip="2066dc0b1" date="2026-09-23" p="src/mergescout.h" l="696" kind="def" t="inline PairOverlap computeOnePairOverlap( std::size_t a, std::size_t b, const Arm&amp; armA, const Arm&amp; armB )"/>
<hit ref="lane/answer-honesty-067" tip="95fed7e5b" date="2026-10-02" p="src/mergescout.h" l="696" kind="def" t="inline PairOverlap computeOnePairOverlap( std::size_t a, std::size_t b, const Arm&amp; armA, const Arm&amp; armB )"/>
<hit ref="lane/answers-next-064" tip="04b5396ed" date="2026-09-25" p="src/mergescout.h" l="696" kind="def" t="inline PairOverlap computeOnePairOverlap( std::size_t a, std::size_t b, const Arm&amp; armA, const Arm&amp; armB )"/>
<hit ref="lane/arise-line-ranking" tip="5b7f01c40" date="2026-09-23" p="src/mergescout.h" l="696" kind="def" t="inline PairOverlap computeOnePairOverlap( std::size_t a, std::size_t b, const Arm&amp; armA, const Arm&amp; armB )"/>
<hit ref="lane/arise-result" tip="13292db7a" date="2026-09-23" p="src/mergescout.h" l="696" kind="def" t="inline PairOverlap computeOnePairOverlap( std::size_t a, std::size_t b, const Arm&amp; armA, const Arm&amp; armB )"/>
<hit ref="lane/asan-reload-068" tip="530d8d572" date="2026-10-07" p="src/mergescout.h" l="696" kind="def" t="inline PairOverlap computeOnePairOverlap( std::size_t a, std::size_t b, const Arm&amp; armA, const Arm&amp; armB )"/>
<hit ref="lane/asan-toolchain-probe-068" tip="f981b1d01" date="2026-10-07" p="src/mergescout.h" l="696" kind="def" t="inline PairOverlap computeOnePairOverlap( std::size_t a, std::size_t b, const Arm&amp; armA, const Arm&amp; armB )"/>
<hit ref="lane/builtin-bind-065" tip="f2eb061e3" date="2026-09-26" p="src/mergescout.h" l="696" kind="def" t="inline PairOverlap computeOnePairOverlap( std::size_t a, std::size_t b, const Arm&amp; armA, const Arm&amp; armB )"/>
<hit ref="lane/c4-fixloop-067" tip="37dbb7123" date="2026-09-30" p="src/mergescout.h" l="696" kind="def" t="inline PairOverlap computeOnePairOverlap( std::size_t a, std::size_t b, const Arm&amp; armA, const Arm&amp; armB )"/>
… [36 more display lines; full output is 15188 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --flags`

*The dark-content dashboard: gates BUILT but OFF. CHANGED: no longer invents gates from comments/heredocs, so the count only reflects real ifndef/define, CMake option(), and getenv gates.*

`````
<!-- ripwire flags schema=ripwire.flags/v1: BUILT but DARK: <gate name= kind=compile|cmake|env default= dark= regions=/loc=(#if only) reads= p= l=> with <read p= l=> sites. reads_capped=: 1 = cut. next=: the one pasteable follow-up. gates=/dark_gates=: gate rows (never cut) / those whose default keeps the guarded code out of the build. compile=/cmake=/env=: gates by kind: ifndef/define header gate, CMake option(), getenv read. files=N: files this verb scanned for gates (source + CMakeLists), wider than the map's corpus. -->
<!-- ROWS AND WHAT IS NEVER CUT: the gate rows ARE the answer this verb was asked for and are never windowed, capped or paged, and gates/dark_gates/compile/cmake/env/files on the root plus regions/loc/reads/dark on every gate are counted over the FULL set before any cap exists. What pages is the read SITES under one gate, at 8 a gate by default: a gate whose sites were cut says shown_reads= (the rows this run printed) with reads_capped="1", against the reads= total already on the same element, and the more reads= child keeps naming the remainder. The pair is emitted ONLY on a gate that was cut, never as a capped="0" on the gates that fit. limit=N raises the per gate cap (offset=M skips that many sites in every gate), detail lifts it entirely, and next= on the root is the exact pasteable invocation that shows every site this run dropped. -->
<flags schema="ripwire.flags/v1" gates="94" dark_gates="86" compile="13" cmake="12" env="69" files="2491" next="--flags --limit=18">
<gate name="FIXTURE_DARK_FEATURE" kind="compile" default="0" dark="1" regions="2" loc="13" reads="2" p="test/flagsfix/wiringFlags.h" l="10">
<read p="test/flagsfix/feature.cpp" l="10"/>
<read p="test/flagsfix/sub/nested.cpp" l="5"/>
</gate>
<gate name="PROFILE_PMC_VERBOSE" kind="compile" default="0" dark="1" regions="2" loc="10" reads="2" p="src/infra/profilePmc.h" l="78">
<read p="src/infra/profilePmc.h" l="81"/>
<read p="src/infra/profilePmc.h" l="437"/>
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
<gate name="PROFILE_BARRIER" kind="compile" default="0" dark="1" regions="1" loc="3" reads="1" p="src/infra/profileScope.h" l="60">
<read p="src/infra/profileScope.h" l="122"/>
</gate>
<gate name="FIXTURE_CMAKE_DARK" kind="cmake" default="OFF" dark="1" regions="1" loc="1" reads="3" p="test/flagsfix/CMakeLists.txt" l="4">
<read p="test/flagsfix/CMakeLists.txt" l="4"/>
<read p="test/flagsfix/CMakeLists.txt" l="10"/>
… [366 more display lines; full output is 22644 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --flags --flip=RIPWIRE_ASAN`

*Blast radius of turning ONE gate on: live code, symbols, transitive reach, covering tests.*

`````
<!-- ripwire flip schema=ripwire.flip/v1: the blast radius of flipping one build gate: the regions and symbols it toggles. root=: p= relative to it. -->
<flip schema="ripwire.flip/v1" gate="RIPWIRE_ASAN" kind="cmake" default="OFF" dark="1" runtime="0" p="CMakeLists.txt" l="14" family="1" regions="0" loc="0" branches="0" bindings="0" hosts="0" filescope="0" downstream="0" dependents="0" tests="0" untested="0" files="2491" root=".">
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
<build n="10" note="CMake read sites: a switch here can add whole translation units or link targets, which this verb does NOT follow">
<c p="CMakeLists.txt" l="14"/>
<c p="CMakeLists.txt" l="18"/>
<c p="CMakeLists.txt" l="24"/>
<c p="CMakeLists.txt" l="36"/>
<c p="CMakeLists.txt" l="38"/>
<c p="CMakeLists.txt" l="1017"/>
<c p="CMakeLists.txt" l="1023"/>
<c p="CMakeLists.txt" l="1050"/>
<c p="CMakeLists.txt" l="1103"/>
<c p="CMakeLists.txt" l="1105"/>
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

**wall time: 1.27s**

`````
{"v":1,"verb":"plan-lanes","at":"c7920353a","root":".","task":"add a --since filter to the doc-drift verb and cover it with tests","source":"partition","requested":3,"lane_count":3,"claim_key":"path+scope+name","on_conflict":"producing-lane-rebases","corpus":{"files":2484,"symbols":23851,"edges":342 … [line truncated: 339 more bytes on this line]
"symbols":[{"p":"./src/docdrift.h","n":"DriftResult","scope":"DriftResult","l":286,"id":"./src/docdrift.h::DriftResult::DriftResult"},
{"p":"./src/docdrift.h","n":"computeDocDrift","scope":"docdrift","l":2441,"id":"./src/docdrift.h::docdrift::computeDocDrift"},
{"p":"./src/docdrift.h","n":"kDocDriftLegend","scope":"docdrift","l":2739,"id":"./src/docdrift.h::docdrift::kDocDriftLegend"},
{"p":"./src/docdrift.h","n":"writeDocDriftPage","scope":"docdrift","l":2909,"id":"./src/docdrift.h::docdrift::writeDocDriftPage"},
{"p":"./src/mcpverbs.h","n":"docDriftText","scope":"rw","l":640,"id":"./src/mcpverbs.h::rw::docDriftText"},
{"p":"./src/verbs_change.h","n":"runDocDrift","scope":"","l":1642,"id":null}]},"lanes":[{"id":"lane-0","task":"add a --since filter to the doc-drift verb and cover it with tests","claims":{"symbols":[{"p":"./src/verbs_change.h","n":"runAbiCheck","scope":"","key":"183da9aaf74a4a92","id":null,"id_addr … [line truncated: 113 more bytes on this line]
{"p":"./src/docdrift.h","n":"writeGateability","scope":"docdrift","key":"42c456dfb55faee4","id":"./src/docdrift.h::docdrift::writeGateability","id_addressable":true,"id_collides_with":0,"l":2685,"ord":0,"overloads":1,"amb":3,"cx":6,"ccx":6,"churn":36,"tested":0},
{"p":"./src/darkflags.h","n":"writeFlags","scope":"darkflags","key":"5c2c4a2b311b8dba","id":"./src/darkflags.h::darkflags::writeFlags","id_addressable":true,"id_collides_with":0,"l":1298,"ord":0,"overloads":1,"amb":2,"cx":8,"ccx":8,"churn":31,"tested":0},
{"p":"./src/docdrift.h","n":"docDriftNextAttr","scope":"docdrift","key":"7723ed789a1c9c09","id":"./src/docdrift.h::docdrift::docDriftNextAttr","id_addressable":true,"id_collides_with":0,"l":2864,"ord":0,"overloads":1,"amb":0,"cx":6,"ccx":5,"churn":36,"tested":0},
{"p":"./src/docdrift.h","n":"recordWeakDisclosures","scope":"docdrift","key":"972779210e49c0cf","id":"./src/docdrift.h::docdrift::recordWeakDisclosures","id_addressable":true,"id_collides_with":0,"l":2430,"ord":0,"overloads":1,"amb":2,"cx":2,"ccx":1,"churn":36,"tested":0},
{"p":"./src/testmap.h","n":"scriptGatesUnmodelledCount","scope":"rw","key":"98c4487e2e9e08bc","id":"./src/testmap.h::rw::scriptGatesUnmodelledCount","id_addressable":true,"id_collides_with":0,"l":1344,"ord":0,"overloads":1,"amb":0,"cx":4,"ccx":4,"churn":48,"tested":0},
{"p":"./src/main.cpp","n":"scanReportVerbPrecedence","scope":"","key":"9ab981e987e8108e","id":null,"id_addressable":false,"id_collides_with":0,"l":2863,"ord":0,"overloads":1,"amb":33,"cx":8,"ccx":11,"churn":414,"tested":0},
{"p":"./src/gitmine.h","n":"resolveSinceScope","scope":"rw","key":"9caaa3dbeaa688d0","id":"./src/gitmine.h::rw::resolveSinceScope","id_addressable":true,"id_collides_with":0,"l":326,"ord":0,"overloads":1,"amb":3,"cx":7,"ccx":7,"churn":59,"tested":0},
{"p":"./src/pageview.h","n":"secondaryCutAttrs","scope":"rw","key":"a10ea8d3bdca1dfb","id":"./src/pageview.h::rw::secondaryCutAttrs","id_addressable":true,"id_collides_with":0,"l":350,"ord":0,"overloads":1,"amb":0,"cx":3,"ccx":2,"churn":18,"tested":0},
{"p":"./src/main.cpp","n":"emitNoteAddUnprovenDefs","scope":"","key":"a950332ccfce6b8d","id":null,"id_addressable":false,"id_collides_with":0,"l":685,"ord":0,"overloads":1,"amb":1,"cx":2,"ccx":1,"churn":414,"tested":0},
{"p":"./src/taskroute.h","n":"testCoverageTaskChoice","scope":"rw::taskroute","key":"bf72991aa28355c7","id":"./src/taskroute.h::rw::taskroute::testCoverageTaskChoice","id_addressable":true,"id_collides_with":0,"l":1365,"ord":0,"overloads":1,"amb":1,"cx":3,"ccx":2,"churn":34,"tested":0},
{"p":"./src/docdrift.h","n":"sortDocsByLiveDrift","scope":"docdrift","key":"d5de682411b9a9a9","id":"./src/docdrift.h::docdrift::sortDocsByLiveDrift","id_addressable":true,"id_collides_with":0,"l":2390,"ord":0,"overloads":1,"amb":0,"cx":2,"ccx":2,"churn":36,"tested":0},
{"p":"./src/mcpverbs.h","n":"unknownSubVerbRefusal","scope":"rw","key":"e336d39b0a6addea","id":"./src/mcpverbs.h::rw::unknownSubVerbRefusal","id_addressable":true,"id_collides_with":0,"l":5191,"ord":0,"overloads":1,"amb":1,"cx":3,"ccx":2,"churn":309,"tested":0}],
"files":[{"p":"./src/darkflags.h","symbols":1,"churn":31,"ccx":8,"hotspot_rank":45},
{"p":"./src/docdrift.h","symbols":4,"churn":36,"ccx":14,"hotspot_rank":31},
{"p":"./src/gitmine.h","symbols":1,"churn":59,"ccx":7,"hotspot_rank":19},
{"p":"./src/main.cpp","symbols":2,"churn":414,"ccx":12,"hotspot_rank":4},
{"p":"./src/mcpverbs.h","symbols":1,"churn":309,"ccx":2,"hotspot_rank":5},
{"p":"./src/pageview.h","symbols":1,"churn":18,"ccx":2,"hotspot_rank":134},
{"p":"./src/taskroute.h","symbols":1,"churn":34,"ccx":2,"hotspot_rank":41},
{"p":"./src/testmap.h","symbols":1,"churn":48,"ccx":4,"hotspot_rank":34},
{"p":"./src/verbs_change.h","symbols":1,"churn":70,"ccx":8,"hotspot_rank":23}]},"blast_radius":{"reaches":51,"files_total":17,"capped":false,"files":["./src/darkflags.h","./src/docdrift.h","./src/editplan.h","./src/flipimpact.h","./src/gitmine.h","./src/main.cpp","./src/mcp.h","./src/mcpedit.h","./s … [line truncated: 203 more bytes on this line]
"tests_total":0,"tests_capped":false,"tests_granularity":"claimed-symbols","untested":51,"module_span":1,"notes":[],
"execution":{"policy":"codex-lane/v1","model":"gpt-5.6-sol","reasoning":"high","rule":"complex-or-wide","basis":"structural-only","signals":{"claims":13,"files":9,"module_span":1,"max_ccx":11,"sum_ccx":59,"ambiguous_calls":49,"blast_reaches":51,"contract_touches":0,"conflicts":0,"untested":51,"tests … [line truncated: 135 more bytes on this line]
… [72 more display lines; full output is 20570 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --plan-lanes --brief=<scratch>/aux/lanes_brief.txt`

*NEW VERB, explicit form: one line per lane, lane boundaries are the ones you wrote (the defensible mode).*

**wall time: 1.34s**

Input file:

`````
add a --since filter to the doc-drift verb
add the CLI parse arm and help text for the new filter
write regression tests for the new filter
`````

`````
{"v":1,"verb":"plan-lanes","at":"c7920353a","root":".","task":null,"source":"brief","requested":3,"lane_count":3,"claim_key":"path+scope+name","on_conflict":"producing-lane-rebases","corpus":{"files":2484,"symbols":23851,"edges":34236,"ambiguous":10278,"unresolved":12878},"carve":null,"core":{"files … [line truncated: 5 more bytes on this line]
"symbols":[]},"lanes":[{"id":"lane-0","task":"add a --since filter to the doc-drift verb","claims":{"symbols":[{"p":"./src/docdrift.h","n":"recordUnchecked","scope":"docdrift","key":"12641dab14abc8fd","id":"./src/docdrift.h::docdrift::recordUnchecked","id_addressable":true,"id_collides_with":0,"l":2 … [line truncated: 72 more bytes on this line]
{"p":"./src/docdrift.h","n":"sortWeakGroupsByPath","scope":"docdrift","key":"1944ba506280ff80","id":"./src/docdrift.h::docdrift::sortWeakGroupsByPath","id_addressable":true,"id_collides_with":0,"l":2401,"ord":0,"overloads":1,"amb":0,"cx":1,"ccx":0,"churn":36,"tested":0},
{"p":"./src/mcpverbs.h","n":"docDriftText","scope":"rw","key":"1fa68e8d93c05a59","id":"./src/mcpverbs.h::rw::docDriftText","id_addressable":true,"id_collides_with":0,"l":640,"ord":0,"overloads":1,"amb":0,"cx":1,"ccx":0,"churn":309,"tested":0},
{"p":"./src/cli.h","n":"kViewFlags","scope":"rw","key":"2a2f2487082cc6d8","id":"./src/cli.h::rw::kViewFlags","id_addressable":true,"id_collides_with":0,"l":3204,"ord":0,"overloads":1,"amb":0,"cx":0,"ccx":0,"churn":436,"tested":0},
{"p":"./src/recall.h","n":"docFileMask","scope":"rw","key":"3149a219f599664c","id":"./src/recall.h::rw::docFileMask","id_addressable":true,"id_collides_with":0,"l":110,"ord":0,"overloads":1,"amb":0,"cx":4,"ccx":4,"churn":27,"tested":0},
{"p":"./src/docdrift.h","n":"writeDocDriftPage","scope":"docdrift","key":"380b7de5df1cfd73","id":"./src/docdrift.h::docdrift::writeDocDriftPage","id_addressable":true,"id_collides_with":0,"l":2909,"ord":0,"overloads":1,"amb":12,"cx":14,"ccx":15,"churn":36,"tested":0},
{"p":"./src/docdrift.h","n":"computeDocDrift","scope":"docdrift","key":"3b19cc3d8996c3b2","id":"./src/docdrift.h::docdrift::computeDocDrift","id_addressable":true,"id_collides_with":0,"l":2441,"ord":0,"overloads":1,"amb":12,"cx":26,"ccx":38,"churn":36,"tested":0},
{"p":"./src/docdrift.h","n":"DriftResult","scope":"DriftResult","key":"422ab39546b6e0bd","id":"./src/docdrift.h::DriftResult::DriftResult","id_addressable":true,"id_collides_with":0,"l":286,"ord":0,"overloads":1,"amb":0,"cx":0,"ccx":0,"churn":36,"tested":0},
{"p":"./src/verbs_change.h","n":"runDocDrift","scope":"","key":"904831e5c0f66b39","id":null,"id_addressable":false,"id_collides_with":0,"l":1642,"ord":0,"overloads":1,"amb":1,"cx":5,"ccx":4,"churn":70,"tested":0},
{"p":"./src/ensemble.h","n":"kEnsembleChurnSince","scope":"ensemble","key":"a34fc78c05bf56a8","id":"./src/ensemble.h::ensemble::kEnsembleChurnSince","id_addressable":true,"id_collides_with":0,"l":120,"ord":0,"overloads":1,"amb":0,"cx":0,"ccx":0,"churn":23,"tested":0},
{"p":"./src/mcprefusal.h","n":"kMcpRequiredFields","scope":"rw::mcprefuse","key":"c5f1ad5fc3a12368","id":"./src/mcprefusal.h::rw::mcprefuse::kMcpRequiredFields","id_addressable":true,"id_collides_with":0,"l":67,"ord":0,"overloads":1,"amb":0,"cx":0,"ccx":0,"churn":41,"tested":0},
{"p":"./src/docdrift.h","n":"kDocDriftLegend","scope":"docdrift","key":"ff2ba74637bbbebf","id":"./src/docdrift.h::docdrift::kDocDriftLegend","id_addressable":true,"id_collides_with":0,"l":2739,"ord":0,"overloads":1,"amb":0,"cx":0,"ccx":0,"churn":36,"tested":0}],
"files":[{"p":"./src/cli.h","symbols":1,"churn":436,"ccx":0,"hotspot_rank":6},
{"p":"./src/docdrift.h","symbols":6,"churn":36,"ccx":54,"hotspot_rank":31},
{"p":"./src/ensemble.h","symbols":1,"churn":23,"ccx":0,"hotspot_rank":87},
{"p":"./src/mcprefusal.h","symbols":1,"churn":41,"ccx":0,"hotspot_rank":54},
{"p":"./src/mcpverbs.h","symbols":1,"churn":309,"ccx":0,"hotspot_rank":5},
{"p":"./src/recall.h","symbols":1,"churn":27,"ccx":4,"hotspot_rank":52},
{"p":"./src/verbs_change.h","symbols":1,"churn":70,"ccx":4,"hotspot_rank":23}],
"symbols_total":3147,"symbols_capped":true},"blast_radius":{"reaches":12,"files_total":7,"capped":false,"files":["./src/docdrift.h","./src/main.cpp","./src/mcp.h","./src/mcpserver.h","./src/mcpverbs.h","./src/recall.h","./src/verbs_for.h"]},"tests_to_run":[],
"tests_total":0,"tests_capped":false,"tests_granularity":"claimed-symbols","untested":12,"module_span":6,"notes":[],
"execution":{"policy":"codex-lane/v1","model":"gpt-5.6-sol","reasoning":"xhigh","rule":"wide-contract-work","basis":"structural-only","signals":{"claims":12,"files":7,"module_span":6,"max_ccx":38,"sum_ccx":62,"ambiguous_calls":26,"blast_reaches":12,"contract_touches":1,"conflicts":3,"untested":12,"t … [line truncated: 139 more bytes on this line]
{"id":"lane-1","task":"add the CLI parse arm and help text for the new filter","claims":{"symbols":[{"p":"./scripts/optremarks.py","n":"main","scope":"","key":"01b3b880f77d1512","id":null,"id_addressable":false,"id_collides_with":107,"l":271,"ord":0,"overloads":1,"amb":0,"cx":23,"ccx":31,"churn":10, … [line truncated: 12 more bytes on this line]
{"p":"./src/cli.h","n":"HelpLine","scope":"rw","key":"1489844dbc310b82","id":"./src/cli.h::rw::HelpLine","id_addressable":true,"id_collides_with":0,"l":2828,"ord":0,"overloads":1,"amb":0,"cx":0,"ccx":0,"churn":436,"tested":0},
{"p":"./src/cli.h","n":"kViewFlags","scope":"rw","key":"2a2f2487082cc6d8","id":"./src/cli.h::rw::kViewFlags","id_addressable":true,"id_collides_with":0,"l":3204,"ord":0,"overloads":1,"amb":0,"cx":0,"ccx":0,"churn":436,"tested":0},
{"p":"./src/cli.h","n":"HelpFilter","scope":"HelpFilter","key":"3103a5e8bfc33d38","id":"./src/cli.h::HelpFilter::HelpFilter","id_addressable":true,"id_collides_with":0,"l":2907,"ord":0,"overloads":1,"amb":0,"cx":0,"ccx":0,"churn":436,"tested":0},
{"p":"./docs/docs_commands_build.py","n":"main","scope":"","key":"4015853681ded3bc","id":null,"id_addressable":false,"id_collides_with":107,"l":865,"ord":0,"overloads":1,"amb":0,"cx":19,"ccx":28,"churn":17,"tested":0},
{"p":"./src/slice.h","n":"sliceRdIterationCeiling","scope":"slicev","key":"449132b302bb4324","id":"./src/slice.h::slicev::sliceRdIterationCeiling","id_addressable":true,"id_collides_with":0,"l":1372,"ord":0,"overloads":1,"amb":0,"cx":9,"ccx":12,"churn":51,"tested":0},
{"p":"./src/mcprefusal.h","n":"kMcpValueFields","scope":"rw::mcprefuse","key":"4a7106e488a2aa80","id":"./src/mcprefusal.h::rw::mcprefuse::kMcpValueFields","id_addressable":true,"id_collides_with":0,"l":304,"ord":0,"overloads":1,"amb":0,"cx":0,"ccx":0,"churn":41,"tested":0},
… [63 more display lines; full output is 19235 bytes on 1 raw line(s)]
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
<!-- ripwire layout schema=ripwire.layout/v1: struct field layout vs cache lines: offsets, padding, hot/cold split candidates. root=: p= relative to it. sym=: the aggregate name asked for. found=1: a C-family struct/class/union body was located for sym=. defs=N: same-name aggregate defs found; a more element counts any not shown. mirror=: single|match|mismatch (byte drift, exits nonzero)|stub|spelling, over same-name defs. asserts=N: static_assert tripwires in indexed files that mention sym=. conflicts=N: asserts contradicting the computed size (agree=0 rows); nonzero exits nonzero. scanned=N: indexed C-family files read for asserts. agg=: struct, class or union. fields=N: member rows listed. modeled=0: size/align/tail pad not computed; off= only up to the first unknown. ty=: the field type as written, before macro expansion (as= gives the expansion). sz=N: field bytes incl. array extent (LP64 model); sized=0 instead when unknown. al=N: field alignment in bytes (LP64 model). off=N: computed byte offset; absent after an earlier field of unknown size. d=: caveat detail: the first site this kind fired on, or a plain description. count=N: member sites this one caveat row stands for (absent = 1). -->
<layout schema="ripwire.layout/v1" sym="Symbol" found="1" defs="1" mirror="single" asserts="2" conflicts="0" scanned="632" root=".">
<def p="src/model.h" l="427" agg="struct" modeled="0" fields="23">
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
<f n="extentSuspect" ty="std::uint8_t" sz="1" al="1"/>
<f n="name" ty="std::string" sized="0"/>
<f n="scope" ty="std::string" sized="0"/>
<caveat k="compound-type" d="evWhy: std::array&lt;std::uint8_t, kEvWhyTagCount&gt;"/>
<caveat k="unknown-type" d="evWhy: std::array&lt;std::uint8_t, kEvWhyTagCount&gt;" count="3"/>
<caveat k="bitfield" d="the bit allocation unit and packing order are implementation-defined" count="4"/>
</def>
<assert p="src/model.h" l="618" kind="mention" t="static_assert( sizeof( Symbol ) == 64 + 2 * sizeof( std::string ), &quot;Symbol size changed — verify the new field uses the smallest type + is grouped (SoA); see model.h&quot; )"/>
<assert p="src/renamemine.h" l="512" kind="mention" t="static_assert( kRuleCount &lt;= std::numeric_limits&lt;decltype( firedRuleMask( std::declval&lt;const Symbol&amp;&gt;(), std::string_view() ) )&gt;::digits, &quot;firedRuleMask holds one bit per naming rule — widen it before kRuleCount outgro" … [line truncated: 2 more bytes on this line]
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
<!-- ripwire doc-drift schema=ripwire.doc-drift/v1: markdown anchors that no longer hold: <doc p=> of <a k= l= c= why= ref= want= got= tgt=>; unchecked/dated rows disclose the rest. failed_capped=/weak_capped=: 1 = cut. at=: commit+dirty+shallow. next=: the one pasteable follow-up. docs=N: markdown docs scanned for anchors; docs minus clean = the doc rows. clean=N: docs with no failed anchor (drift and dated 0); not proof every anchor was checked. checked=N: anchors verified against the index; checked + unchecked = anchors. prose=N: value anchors dropped as prose (name not in code); subtracted from anchors=, never checked. corpus=N: files the anchors were checked against (index + config/build exts); 0 = no anchor shape, no scan. drift=/dated=: anchors that no longer hold / anchors skipped as dated (unverifiable by date). unchecked=N: anchors not proved (the unchecked rows give each reason); checked + unchecked = anchors. doc shown_failed=/failed_total=: a rows printed / all failed anchors (drift+dated); cut at 12, detail=1 lifts. a kind=/rec=: dated-record, an author-dated failed anchor in dated= / its evidence: line|block|title|stamp. a sym=: the symbol the doc names on that file:line; line-moved = that symbol no longer spans the line. more weak=N: w rows of this group withheld; shown_weak + N = its n=; detail=1 lists all. shown_weak=N: w rows printed of n= (cut at 12 a doc, weak_capped=1); detail=1 lists all. w resolves-to=: the indexed symbol spanning that line; not proof it is the one the doc meant. unchecked r=/note=: why n= anchors were not proved, and what was still checked for them. dated r=/note=: the dating mark that moved n= failed anchors into dated= instead of drift=. -->
<doc-drift schema="ripwire.doc-drift/v1" docs="207" clean="178" anchors="6355" checked="2979" unchecked="3376" drift="106" dated="107" prose="26" corpus="2522" at="c7920353a" next="--doc-drift --detail=1">
<doc p="docs/COMMANDS.md" anchors="220" checked="57" drift="29" dated="0" shown_failed="12" failed_capped="1" failed_total="29">
<a k="const" l="506" c="153" why="const-value" ref="dropped_by_budget=23" want="23" got="298" tgt="test/recallpassagecheck.sh:96"/>
<a k="const" l="575" c="148" why="const-value" ref="dropped_by_budget=156" want="156" got="298" tgt="test/recallpassagecheck.sh:96"/>
<a k="const" l="3768" c="53" why="const-value" ref="dropped_by_budget=23" want="23" got="298" tgt="test/recallpassagecheck.sh:96"/>
<a k="const" l="3769" c="53" why="const-value" ref="dropped_by_budget=157" want="157" got="298" tgt="test/recallpassagecheck.sh:96"/>
<a k="const" l="3770" c="53" why="const-value" ref="dropped_by_budget=19" want="19" got="298" tgt="test/recallpassagecheck.sh:96"/>
<a k="const" l="3771" c="53" why="const-value" ref="dropped_by_budget=150" want="150" got="298" tgt="test/recallpassagecheck.sh:96"/>
<a k="const" l="3772" c="53" why="const-value" ref="dropped_by_budget=9" want="9" got="298" tgt="test/recallpassagecheck.sh:96"/>
<a k="const" l="3773" c="53" why="const-value" ref="dropped_by_budget=149" want="149" got="298" tgt="test/recallpassagecheck.sh:96"/>
<a k="const" l="3774" c="53" why="const-value" ref="dropped_by_budget=9" want="9" got="298" tgt="test/recallpassagecheck.sh:96"/>
<a k="const" l="3775" c="53" why="const-value" ref="dropped_by_budget=149" want="149" got="298" tgt="test/recallpassagecheck.sh:96"/>
<a k="const" l="3776" c="53" why="const-value" ref="dropped_by_budget=9" want="9" got="298" tgt="test/recallpassagecheck.sh:96"/>
<a k="const" l="3803" c="53" why="const-value" ref="dropped_by_budget=23" want="23" got="298" tgt="test/recallpassagecheck.sh:96"/>
<more drift="17"/>
</doc>
<doc p="docs/research/answer-completeness.md" anchors="187" checked="85" drift="16" dated="0" shown_failed="12" failed_capped="1" failed_total="16">
<a k="file-line" l="349" c="99" why="line-moved" ref="src/serialize.h:4169" sym="kForLensDefaultTopN" got="sigRowTail" tgt="src/serialize.h:920"/>
<a k="file-line" l="353" c="89" why="line-moved" ref="src/serialize.h:4435" sym="kForPayloadBudgetBytes" got="trimSigLadder" tgt="src/serialize.h:906"/>
<a k="file-line" l="356" c="42" why="line-moved" ref="src/serialize.h:1010" sym="kForFileTailShownCap" got="computeFileTail" tgt="src/serialize.h:995"/>
<a k="file-line" l="358" c="89" why="line-moved" ref="src/serialize.h:5481" sym="kForAnchorBodyBudgetBytes" got="sliceBodyLines" tgt="src/serialize.h:974"/>
<a k="file-line" l="360" c="88" why="line-moved" ref="src/serialize.h:5800" sym="kForCompactSurfaceBudgetBytes" got="appendMergedCalleeNameRows" tgt="src/serialize.h:1153"/>
<a k="file-line" l="366" c="43" why="line-moved" ref="src/serialize.h:6534" sym="kWithGraphNodeCap" got="packBodies" tgt="src/serialize.h:7463"/>
<a k="file-line" l="367" c="51" why="line-moved" ref="src/forpage.h:287" sym="kForPageRowsDefault" got="renderForFilePageXml" tgt="src/forpage.h:59"/>
<a k="file-line" l="368" c="65" why="line-moved" ref="src/verbs_for.h:3315" sym="legendDroppedNote" got="runForLens" tgt="src/verbs_for.h:692"/>
<a k="file-line" l="380" c="44" why="line-moved" ref="src/serialize.h:2460" sym="kFillOrderThreshold" got="(file scope)" tgt="src/serialize.h:1492"/>
<a k="file-line" l="382" c="62" why="line-moved" ref="src/main.cpp:1283" sym="kRecentRows" got="scopedMapNextInvocation" tgt="src/main.cpp:1190"/>
<a k="file-line" l="399" c="48" why="line-moved" ref="src/serialize.h:5317" sym="kMaxExpandSibs" got="candidatesRootTag" tgt="src/serialize.h:5936"/>
<a k="file-line" l="400" c="50" why="line-moved" ref="src/serialize.h:5342" sym="kMaxExpandIncludes" got="packCandidates" tgt="src/serialize.h:5945"/>
… [243 more display lines; full output is 25199 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --doc-drift --gateability`

*The finishable to-do list: docs whose LIVE failing anchors a date-stamp would reclassify.*

`````
<!-- ripwire doc-drift schema=ripwire.doc-drift/v1: markdown anchors that no longer hold: <doc p=> of <a k= l= c= why= ref= want= got= tgt=>; unchecked/dated rows disclose the rest. failed_capped=/weak_capped=: 1 = cut. at=: commit+dirty+shallow. next=: the one pasteable follow-up. docs=N: markdown docs scanned for anchors; docs minus clean = the doc rows. clean=N: docs with no failed anchor (drift and dated 0); not proof every anchor was checked. checked=N: anchors verified against the index; checked + unchecked = anchors. prose=N: value anchors dropped as prose (name not in code); subtracted from anchors=, never checked. corpus=N: files the anchors were checked against (index + config/build exts); 0 = no anchor shape, no scan. drift=/dated=: anchors that no longer hold / anchors skipped as dated (unverifiable by date). unchecked=N: anchors not proved (the unchecked rows give each reason); checked + unchecked = anchors. doc shown_failed=/failed_total=: a rows printed / all failed anchors (drift+dated); cut at 12, detail=1 lifts. a kind=/rec=: dated-record, an author-dated failed anchor in dated= / its evidence: line|block|title|stamp. a sym=: the symbol the doc names on that file:line; line-moved = that symbol no longer spans the line. more weak=N: w rows of this group withheld; shown_weak + N = its n=; detail=1 lists all. shown_weak=N: w rows printed of n= (cut at 12 a doc, weak_capped=1); detail=1 lists all. w resolves-to=: the indexed symbol spanning that line; not proof it is the one the doc meant. unchecked r=/note=: why n= anchors were not proved, and what was still checked for them. dated r=/note=: the dating mark that moved n= failed anchors into dated= instead of drift=. -->
<doc-drift schema="ripwire.doc-drift/v1" docs="207" clean="178" anchors="6355" checked="2979" unchecked="3376" drift="106" dated="107" prose="26" corpus="2522" at="c7920353a" next="--doc-drift --detail=1">
<doc p="docs/COMMANDS.md" anchors="220" checked="57" drift="29" dated="0" shown_failed="12" failed_capped="1" failed_total="29">
<a k="const" l="506" c="153" why="const-value" ref="dropped_by_budget=23" want="23" got="298" tgt="test/recallpassagecheck.sh:96"/>
<a k="const" l="575" c="148" why="const-value" ref="dropped_by_budget=156" want="156" got="298" tgt="test/recallpassagecheck.sh:96"/>
<a k="const" l="3768" c="53" why="const-value" ref="dropped_by_budget=23" want="23" got="298" tgt="test/recallpassagecheck.sh:96"/>
<a k="const" l="3769" c="53" why="const-value" ref="dropped_by_budget=157" want="157" got="298" tgt="test/recallpassagecheck.sh:96"/>
<a k="const" l="3770" c="53" why="const-value" ref="dropped_by_budget=19" want="19" got="298" tgt="test/recallpassagecheck.sh:96"/>
<a k="const" l="3771" c="53" why="const-value" ref="dropped_by_budget=150" want="150" got="298" tgt="test/recallpassagecheck.sh:96"/>
<a k="const" l="3772" c="53" why="const-value" ref="dropped_by_budget=9" want="9" got="298" tgt="test/recallpassagecheck.sh:96"/>
<a k="const" l="3773" c="53" why="const-value" ref="dropped_by_budget=149" want="149" got="298" tgt="test/recallpassagecheck.sh:96"/>
<a k="const" l="3774" c="53" why="const-value" ref="dropped_by_budget=9" want="9" got="298" tgt="test/recallpassagecheck.sh:96"/>
<a k="const" l="3775" c="53" why="const-value" ref="dropped_by_budget=149" want="149" got="298" tgt="test/recallpassagecheck.sh:96"/>
<a k="const" l="3776" c="53" why="const-value" ref="dropped_by_budget=9" want="9" got="298" tgt="test/recallpassagecheck.sh:96"/>
<a k="const" l="3803" c="53" why="const-value" ref="dropped_by_budget=23" want="23" got="298" tgt="test/recallpassagecheck.sh:96"/>
<more drift="17"/>
</doc>
<doc p="docs/research/answer-completeness.md" anchors="187" checked="85" drift="16" dated="0" shown_failed="12" failed_capped="1" failed_total="16">
<a k="file-line" l="349" c="99" why="line-moved" ref="src/serialize.h:4169" sym="kForLensDefaultTopN" got="sigRowTail" tgt="src/serialize.h:920"/>
<a k="file-line" l="353" c="89" why="line-moved" ref="src/serialize.h:4435" sym="kForPayloadBudgetBytes" got="trimSigLadder" tgt="src/serialize.h:906"/>
<a k="file-line" l="356" c="42" why="line-moved" ref="src/serialize.h:1010" sym="kForFileTailShownCap" got="computeFileTail" tgt="src/serialize.h:995"/>
<a k="file-line" l="358" c="89" why="line-moved" ref="src/serialize.h:5481" sym="kForAnchorBodyBudgetBytes" got="sliceBodyLines" tgt="src/serialize.h:974"/>
<a k="file-line" l="360" c="88" why="line-moved" ref="src/serialize.h:5800" sym="kForCompactSurfaceBudgetBytes" got="appendMergedCalleeNameRows" tgt="src/serialize.h:1153"/>
<a k="file-line" l="366" c="43" why="line-moved" ref="src/serialize.h:6534" sym="kWithGraphNodeCap" got="packBodies" tgt="src/serialize.h:7463"/>
<a k="file-line" l="367" c="51" why="line-moved" ref="src/forpage.h:287" sym="kForPageRowsDefault" got="renderForFilePageXml" tgt="src/forpage.h:59"/>
<a k="file-line" l="368" c="65" why="line-moved" ref="src/verbs_for.h:3315" sym="legendDroppedNote" got="runForLens" tgt="src/verbs_for.h:692"/>
<a k="file-line" l="380" c="44" why="line-moved" ref="src/serialize.h:2460" sym="kFillOrderThreshold" got="(file scope)" tgt="src/serialize.h:1492"/>
<a k="file-line" l="382" c="62" why="line-moved" ref="src/main.cpp:1283" sym="kRecentRows" got="scopedMapNextInvocation" tgt="src/main.cpp:1190"/>
<a k="file-line" l="399" c="48" why="line-moved" ref="src/serialize.h:5317" sym="kMaxExpandSibs" got="candidatesRootTag" tgt="src/serialize.h:5936"/>
<a k="file-line" l="400" c="50" why="line-moved" ref="src/serialize.h:5342" sym="kMaxExpandIncludes" got="packCandidates" tgt="src/serialize.h:5945"/>
… [269 more display lines; full output is 26398 bytes on 1 raw line(s)]
`````

Tail of the same output — the `<gateability>` section:

`````
<gateability docs="24" projected_drift="0">
<fix p="docs/COMMANDS.md" live="29"/>
<fix p="docs/research/answer-completeness.md" live="16"/>
<fix p="prompts/help-wanted/graph-unit-tests.md" live="8"/>
<fix p="prompts/help-wanted/kotlin-scope-functions.md" live="8"/>
<fix p="test/docdriftfix/NOTES.md" live="7"/>
<fix p="CHANGELOG.md" live="6"/>
<fix p="THIRD_PARTY.md" live="6"/>
<fix p="README.md" live="4"/>
<fix p="docs/LSP.md" live="4"/>
<fix p="prompts/help-wanted/uses-qualified-selector.md" live="2"/>
<fix p="test/docdriftfix/live_notes.md" live="2"/>
<fix p="test/gateabilityfix/UNDATED.md" live="2"/>
<fix p="CONTRIBUTING.md" live="1"/>
<fix p="bench/nestcal/r1-2026-08-07/REPORT.md" live="1"/>
<fix p="docs/EVALS.md" live="1"/>
<fix p="docs/LINEAGE.md" live="1"/>
<fix p="docs/OPTREMARKS.md" live="1"/>
<fix p="prompts/help-wanted/nesting-refusals-visible.md" live="1"/>
<fix p="prompts/help-wanted/scala-jvm-bridge.md" live="1"/>
<fix p="prompts/help-wanted/ts-literal-receivers.md" live="1"/>
<fix p="skills/ripwire-fresh-eyes/SKILL.md" live="1"/>
<fix p="skills/ripwire-mcp/SKILL.md" live="1"/>
<fix p="test/docdriftfix/record_line.md" live="1"/>
<fix p="test/gateabilityfix/MIXED.md" live="1"/>
`````

## `./build/ripwire . --doc-drift --with-history`

*Same report, with git history splitting stale mentions into deleted-by-commit vs never-existed.*

`````
<!-- ripwire doc-drift schema=ripwire.doc-drift/v1: markdown anchors that no longer hold: <doc p=> of <a k= l= c= why= ref= want= got= tgt=>; unchecked/dated rows disclose the rest. failed_capped=/weak_capped=: 1 = cut. at=: commit+dirty+shallow. next=: the one pasteable follow-up. docs=N: markdown docs scanned for anchors; docs minus clean = the doc rows. clean=N: docs with no failed anchor (drift and dated 0); not proof every anchor was checked. checked=N: anchors verified against the index; checked + unchecked = anchors. prose=N: value anchors dropped as prose (name not in code); subtracted from anchors=, never checked. corpus=N: files the anchors were checked against (index + config/build exts); 0 = no anchor shape, no scan. drift=/dated=: anchors that no longer hold / anchors skipped as dated (unverifiable by date). unchecked=N: anchors not proved (the unchecked rows give each reason); checked + unchecked = anchors. doc shown_failed=/failed_total=: a rows printed / all failed anchors (drift+dated); cut at 12, detail=1 lifts. a kind=/rec=: dated-record, an author-dated failed anchor in dated= / its evidence: line|block|title|stamp. a sym=: the symbol the doc names on that file:line; line-moved = that symbol no longer spans the line. more weak=N: w rows of this group withheld; shown_weak + N = its n=; detail=1 lists all. shown_weak=N: w rows printed of n= (cut at 12 a doc, weak_capped=1); detail=1 lists all. w resolves-to=: the indexed symbol spanning that line; not proof it is the one the doc meant. unchecked r=/note=: why n= anchors were not proved, and what was still checked for them. dated r=/note=: the dating mark that moved n= failed anchors into dated= instead of drift=. -->
<doc-drift schema="ripwire.doc-drift/v1" docs="207" clean="183" anchors="6355" checked="2962" unchecked="3393" drift="97" dated="99" prose="26" corpus="2522" at="c7920353a" next="--doc-drift --detail=1">
<history probed="1" head="c7920353a" commits="3565" removed-names="42542"/>
<doc p="docs/COMMANDS.md" anchors="220" checked="57" drift="29" dated="0" shown_failed="12" failed_capped="1" failed_total="29">
<a k="const" l="506" c="153" why="const-value" ref="dropped_by_budget=23" want="23" got="298" tgt="test/recallpassagecheck.sh:96"/>
<a k="const" l="575" c="148" why="const-value" ref="dropped_by_budget=156" want="156" got="298" tgt="test/recallpassagecheck.sh:96"/>
<a k="const" l="3768" c="53" why="const-value" ref="dropped_by_budget=23" want="23" got="298" tgt="test/recallpassagecheck.sh:96"/>
<a k="const" l="3769" c="53" why="const-value" ref="dropped_by_budget=157" want="157" got="298" tgt="test/recallpassagecheck.sh:96"/>
<a k="const" l="3770" c="53" why="const-value" ref="dropped_by_budget=19" want="19" got="298" tgt="test/recallpassagecheck.sh:96"/>
<a k="const" l="3771" c="53" why="const-value" ref="dropped_by_budget=150" want="150" got="298" tgt="test/recallpassagecheck.sh:96"/>
<a k="const" l="3772" c="53" why="const-value" ref="dropped_by_budget=9" want="9" got="298" tgt="test/recallpassagecheck.sh:96"/>
<a k="const" l="3773" c="53" why="const-value" ref="dropped_by_budget=149" want="149" got="298" tgt="test/recallpassagecheck.sh:96"/>
<a k="const" l="3774" c="53" why="const-value" ref="dropped_by_budget=9" want="9" got="298" tgt="test/recallpassagecheck.sh:96"/>
<a k="const" l="3775" c="53" why="const-value" ref="dropped_by_budget=149" want="149" got="298" tgt="test/recallpassagecheck.sh:96"/>
<a k="const" l="3776" c="53" why="const-value" ref="dropped_by_budget=9" want="9" got="298" tgt="test/recallpassagecheck.sh:96"/>
<a k="const" l="3803" c="53" why="const-value" ref="dropped_by_budget=23" want="23" got="298" tgt="test/recallpassagecheck.sh:96"/>
<more drift="17"/>
</doc>
<doc p="docs/research/answer-completeness.md" anchors="187" checked="85" drift="16" dated="0" shown_failed="12" failed_capped="1" failed_total="16">
<a k="file-line" l="349" c="99" why="line-moved" ref="src/serialize.h:4169" sym="kForLensDefaultTopN" got="sigRowTail" tgt="src/serialize.h:920"/>
<a k="file-line" l="353" c="89" why="line-moved" ref="src/serialize.h:4435" sym="kForPayloadBudgetBytes" got="trimSigLadder" tgt="src/serialize.h:906"/>
<a k="file-line" l="356" c="42" why="line-moved" ref="src/serialize.h:1010" sym="kForFileTailShownCap" got="computeFileTail" tgt="src/serialize.h:995"/>
<a k="file-line" l="358" c="89" why="line-moved" ref="src/serialize.h:5481" sym="kForAnchorBodyBudgetBytes" got="sliceBodyLines" tgt="src/serialize.h:974"/>
<a k="file-line" l="360" c="88" why="line-moved" ref="src/serialize.h:5800" sym="kForCompactSurfaceBudgetBytes" got="appendMergedCalleeNameRows" tgt="src/serialize.h:1153"/>
<a k="file-line" l="366" c="43" why="line-moved" ref="src/serialize.h:6534" sym="kWithGraphNodeCap" got="packBodies" tgt="src/serialize.h:7463"/>
<a k="file-line" l="367" c="51" why="line-moved" ref="src/forpage.h:287" sym="kForPageRowsDefault" got="renderForFilePageXml" tgt="src/forpage.h:59"/>
<a k="file-line" l="368" c="65" why="line-moved" ref="src/verbs_for.h:3315" sym="legendDroppedNote" got="runForLens" tgt="src/verbs_for.h:692"/>
<a k="file-line" l="380" c="44" why="line-moved" ref="src/serialize.h:2460" sym="kFillOrderThreshold" got="(file scope)" tgt="src/serialize.h:1492"/>
<a k="file-line" l="382" c="62" why="line-moved" ref="src/main.cpp:1283" sym="kRecentRows" got="scopedMapNextInvocation" tgt="src/main.cpp:1190"/>
<a k="file-line" l="399" c="48" why="line-moved" ref="src/serialize.h:5317" sym="kMaxExpandSibs" got="candidatesRootTag" tgt="src/serialize.h:5936"/>
… [221 more display lines; full output is 25113 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --from-trace=-`

*Map a pasted stack trace onto indexed symbols. CHANGED: in_corpus= now reports the real count (was 0).*

Input file:

`````
AddressSanitizer:DEADLYSIGNAL
=================================================================
==41337==ERROR: AddressSanitizer: SEGV on unknown address 0x000000000018 (pc 0x000102f4a1c8 bp 0x00016d2f1a40 sp 0x00016d2f19e0 T0)
    #0 0x102f4a1c8 in rw::rankGraphTeleport(Graph const&, std::vector<float> const&, float) src/graph.h:5567
    #1 0x102f3e884 in rw::rankGraph(Graph const&, float) src/graph.h:5608
    #2 0x102e11f30 in runDefaultMap(MainDispatch const&) src/main.cpp:1631
    #3 0x102e01a44 in main src/main.cpp:3975
    #4 0x1a2b3c0dc in start+0x9dc (dyld:arm64e+0x60dc)
==41337==ABORTING
`````

`````
<ctx schema="ripwire.from-trace/v1" task="&lt;stdin&gt;" next="--slice=@src/graph.h:5567" est_tokens="2041">
<!-- ripwire from-trace schema=ripwire.from-trace/v1: trace frames mapped to indexed symbols, innermost first; the innermost in-corpus body included. window: shown= total= capped= (capped=1 cut). est_tokens=: price as emitted (an upper bound under compact). <d r=N>: rank N in this ranking, rows in r= order. <d cx= ccx=>: cyclomatic/cognitive complexity. <d in=N>: N callers in the index (absent: not measured). sc=: enclosing scope; the full id is p::sc::n (p= of the row or its <f>) and selectors take it. next=: the one pasteable follow-up. task=: the trace source this bundle maps, verbatim (a file path, stdin, or an MCP label). src=/format=: the trace read and its dominant frame format, python|asan|node|compiler|generic. frame_lines=/parsed=: frame-shaped input lines / those yielding a path:line; the rest matched no format. in_corpus=: parsed frames in indexed files; always suspects= + merged= + unresolved=. suspects=/merged=/unresolved=: frame rows / folded into a claimed symbol / unresolved rows (indexed file, no def). skipped=N: frames outside every root, listed as skipped rows, never ranked. rank=N: frame order, innermost in-corpus first; p= is the trace's own path:line, defs are sigs l=. resolved_by=name|line: bound by the frame's own name, else by the def enclosing its line. innermost=1: the innermost in-corpus frame (rank 1); its full body is served. -->
<!-- ledger: budget=7500 bytes (allowance 9583 bytes = ceiling + the single-entry overshoot a whole first signature costs) -->
<trace src="&lt;stdin&gt;" format="asan" frame_lines="5" parsed="4" in_corpus="4" skipped="0" merged="0" unresolved="0" suspects="4">
<frame rank="1" n="rankGraphTeleport" t="fn" p="src/graph.h:5567" resolved_by="name" innermost="1"/>
<frame rank="2" n="rankGraph" t="fn" p="src/graph.h:5608" resolved_by="name"/>
<frame rank="3" n="runDefaultMap" t="fn" p="src/main.cpp:1631" resolved_by="name"/>
<frame rank="4" n="main" t="fn" p="src/main.cpp:3975" resolved_by="name"/>
</trace>
<sigs>
<d l="5565" n="rankGraphTeleport" sc="rw" p="src/graph.h" cx="5" ccx="8" in="7" r="1" next="--expand=src/graph.h:rankGraphTeleport">
<doc>PageRank with an explicit teleport / personalization vector p (Σp = 1). The prior is name-quality-biased through biasPrior() so all rank modes share one weighting seam; the transition matrix (edges</doc>inline RankedGraph rankGraphTeleport( const Graph&amp; g, const std::vector&lt;float&gt;&am … [line truncated: 31 more bytes on this line]
<d l="5606" n="rankGraph" sc="rw" p="src/graph.h" cx="2" ccx="1" in="10" r="2">
<doc>uniform-teleport PageRank (the default</doc>inline RankedGraph rankGraph( const Graph&amp; g, float alpha = 0.85f )</d>
<d l="1629" n="runDefaultMap" p="src/main.cpp" cx="197" ccx="284" in="1" r="3">int runDefaultMap( const MainDispatch&amp; d )</d>
<d l="3973" n="main" p="src/main.cpp" cx="17" ccx="20" in="0" r="4">int main( int argc, char** argv )</d>
</sigs>
<bodies shown="1" total="1" capped="0">
<b t="fn" l="5565" p="src/graph.h" n="rankGraphTeleport">
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
… [18 more display lines; full output is 5100 bytes on 29 raw line(s)]
`````

## `./build/ripwire . --notes`

*List all field notes (write-side memory) — the committed .ripwire_notes at the repo root, each with the sha/branch it was recorded at.*

`````
<ctx schema="ripwire.notes/v1">
<!-- ripwire notes schema=ripwire.notes/v1: field notes by target: <target id= dangling=> holds <note d= sha= branch=>; the kept count comment: notes= rows, targets= <target> rows, dangling= targets matching nothing indexed (listed, surfaced nowhere). dangling=1: matches nothing indexed. -->
<!-- notes=2 targets=2 dangling=0 -->
<notes>
<target id="src/infra/Diagnostics.h" dangling="0">
<note d="2026-09-12" sha="42b7c8d" branch="lane/noalias-docs">
<![CDATA[ASSUME_NO_ALIAS is an optimizer fact in release (separate_storage) only where the compiler consumes it: clang 18+ by default, LLVM 17/AppleClang 16 via the CMake -mllvm flag (scalars only), GCC never (debug check only); never on two members of one object; ASSUME_NO_ALIAS_BUF for OWNING cont … [line truncated: 22 more bytes on this line]
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

## `./build/ripwire . --pack-task="add a new output format flag to the CLI"`

*ONE budget-shared bundle: ranking + top bodies + caller sigs + notes + tests_to_run. CHANGED: <d> rows now carry n=/id=.*

`````
<ctx schema="ripwire.pack-task/v1" task="add a new output format flag to the CLI" route="subtoken+body:declined(add;116-carriers,41-defs)" root="." est_tokens="3466" budget_tokens="6000">
<!-- ripwire pack-task schema=ripwire.pack-task/v1: one-call task bundle for task= under budget_tokens=: <sigs>
<d n= sc= l= p=> ranking, <far>
<s t= n= p=> ranked but over 1 hop out (of_top= ranked rows) > <bodies>
<b t= n= p= l=> with <calls>
<c n= l=> callees > <callers>
<s rel=caller|callee shared=> 1-hop from the bodies (of_top= bodies; shared= bodies reached, absent at 1) > notes > <tests>
<test p= run=> (run= when derivable). window: shown= total= capped= (capped=1 cut). run_unknown=1: no runner derivable (a guess would be worse). est_tokens=: price as emitted (an upper bound under compact). root=: p= relative to it. <d r=N>: rank N in this ranking, rows in r= order. <d cx= ccx=>: cy … [line truncated: 546 more bytes on this line]
<!-- ledger: budget=12744 bytes (6000-token target, ceiling 14160) | ranking: full | bodies: kept 5 of 6 (capped) | callers: 20 of 20 | notes: none | tests: 1 of 1 | far: 6 of 6 -->
<sigs>
<d l="2968" n="printUsage" sc="rw" p="src/cli.h" cx="1" ccx="0" in="1" r="1" next="--expand=src/cli.h:printUsage">
<doc>Print the authoritative CLI usage and flag catalog to the caller-provided output stream</doc>inline void printUsage( std::FILE* out ) noexcept</d>
<d l="459" n="wrapCliAddPost" sc="rw" p="src/wrap.h" cx="4" ccx="2" in="1" r="2">
<doc>claude&apos;s `mcp add … -- ripwire --mcp`: the flag goes on the end of that command line, ahead of its newline</doc>inline std::string wrapCliAddPost( const AgentTarget&amp; row, std::string_view toolsArg )</d>
<d l="699" n="wrapEmitCliFirst" sc="rw" p="src/wrap.h" cx="10" ccx="5" in="1" r="3">
<doc>ONE recipe path for every agent that can shell out, and the point is that the RECOMMENDATION does not vary by agent — only the MCP alternative does. Before this there were four near-identical CLI-fi</doc>inline void wrapEmitCliFirst( const AgentTarget&amp; row, const std::string&amp; token, c … [line truncated: 83 more bytes on this line]
<d l="442" n="wrapWritesToolsArg" sc="rw" p="src/wrap.h" cx="6" ccx="1" in="2" r="4">
<doc>mcp-tools pass-through. Written into the server command only where its argument shape is known to be one more plain argument: the JSON args arrays (cursor/windsurf/gemini), opencode&apos;s command array</doc>inline bool wrapWritesToolsArg( const AgentTarget&amp; row ) noexcept</d>
<d l="103" n="toUint" sc="detail" p="src/tracein.h" cx="3" ccx="3" in="4" r="5">
<doc>F7: a hostile/garbled frame line number (e.g. a fuzzed or truncated trace) can exceed UINT32_MAX; unchecked `v*10+d` wraps mod 2^32 (4294967297 -&gt; 1), which then confidently maps to a REAL line in the</doc>inline std::uint32_t toUint( std::string_view s, bool&amp; overflowed ) noexcept</d>
<d l="3199" n="kInRideAlong" p="src/main.cpp" cx="0" ccx="0" in="0" pure="1" r="6">
<doc>knows; these are all OUTSIDE that table. DERIVED, NOT ENUMERATED — the argument htmlPreemptedBy makes in full above, which applies here verbatim: firstFlagOutside() walks the rows parseArgs itself m</doc>inline constexpr std::string_view kInRideAlong[] =</d>
<far of_top="12" shown="6" total="6" capped="0">
<s t="cls" n="AgentTarget" p="src/wrap.h:110"/>
<s t="cls" n="McpValueSpec" p="src/mcprefusal.h:268"/>
<s t="var" n="kJsonShapeModifiers" p="src/main.cpp:3368"/>
<s t="cls" n="BoolFlag" p="src/cli.h:3011"/>
<s t="fn" n="cliRefusesFileList" p="src/situ.h:211"/>
<s t="fn" n="formatRecallSeparator" p="src/recall.h:717"/>
</far>
… [47 more display lines; full output is 9435 bytes on 38 raw line(s)]
`````

## `./build/ripwire . --pack-task="add a new output format flag to the CLI" --partition=3`

*Fan-out form: one shared core + 3 per-agent slices carved along call-graph communities.*

`````
<ctx-partitions schema="ripwire.pack-task/v1" partitions="3" requested="3" core_symbols="6" surface="42" modules="15" split="0" budget_per_agent_tokens="6000" core_budget_tokens="2040" partition_budget_tokens="3960" total_bytes="20667" overlap_mean="0.066" overlap_max="0.114" shared_symbols="13" uni … [line truncated: 37 more bytes on this line]
<!-- ripwire pack-task schema=ripwire.pack-task/v1: N minimally overlapping agent bundles carved along call-graph communities plus one shared core; each <bundle> wraps a <ctx>; bundle role=core|partition i= symbols= modules= bytes= tokens=: one agent's ctx, symbols= ids assigned, bytes= its size; tokens= = est_tokens= = bytes/2.36 (flat, the densest rate; the inner ctx est_tokens= is language-weighted). Inner ctx task= root= budget_tokens= dropped_positive=: the task, p= base, the slice's token target, ranked candidates its budget cut. of_top=: rows ranked (far) / bodies (callers); s rel=caller|callee shared=: 1-hop edge, bodies reached (absent at 1). window: shown= total= capped= (capped=1 cut). run_unknown=1: no runner derivable (a guess would be worse). est_tokens=: price as emitted (an upper bound under compact). <d r=N>: rank N in this ranking, rows in r= order. <d cx= ccx=>: cyclomatic/cognitive complexity. <d in=N>: N callers in the index (absent: not measured). route=: the ranker: name-exact(X) = the task names symbol X (anchors: its evidence), subtoken+body = conceptual BM25 (:broad = 1-2 plain words, plain rg may also win; :declined(...) = a name hit refused as a common name). sc=: enclosing scope; the full id is p::sc::n (p= of the row or its <f>) and selectors take it. next=: the one pasteable follow-up. pure=1: const/constexpr signature (Swift: non-mutating) and no transitive side effect found; a hint. partitions=/requested=: partitions carved / asked for. modules=/split=: call-graph groups found / cuts forced to split one. core_symbols=/surface=: ids in the shared core / core plus the assignable remainder. budget_per_agent_tokens=: one agent's budget, core_budget_tokens= plus partition_budget_tokens=. total_bytes=N: bytes of all bundles together. overlap_mean=/overlap_max=: pairwise Jaccard over the ids partitions name, before trimming. shared_symbols=/union_symbols=: ids two or more partitions name / ids any partition names. core_overlap=: share of the core surface a partition reaches anyway. -->
<bundle role="core" symbols="6" bytes="3023" tokens="1281" est_tokens="1281">
<ctx task="add a new output format flag to the CLI" route="subtoken+body:declined(add;116-carriers,41-defs)" root="." dropped_positive="2" est_tokens="1057" budget_tokens="2040">
<!-- slice budget=4332 bytes (2040-token target, ceiling 4814) | ranking: capped | bodies: kept 2 of 6 (capped) | callers: kept 2 of 20 | notes: none | tests: 1 of 1 | far: none -->
<sigs shown="4" total="6" capped="1">
<d l="2968" n="printUsage" sc="rw" p="src/cli.h" cx="1" ccx="0" in="1" r="1" next="--expand=src/cli.h:printUsage">
<doc>Print the authoritative CLI usage and flag catalog to the caller-provided output stream</doc>inline void printUsage( std::FILE* out ) noexcept</d>
<d l="459" n="wrapCliAddPost" sc="rw" p="src/wrap.h" cx="4" ccx="2" in="1" r="2">
<doc>claude&apos;s `mcp add … -- ripwire --mcp`: the flag goes on the end of that command line, ahead of…</doc>inline std::string wrapCliAddPost( const AgentTarget&amp; row, std::string_view toolsArg )</d>
<d l="699" n="wrapEmitCliFirst" sc="rw" p="src/wrap.h" cx="10" ccx="5" in="1" r="3">
<doc>ONE recipe path for every agent that can shell out, and the point is that the RECOMMENDATION doe…</doc>inline void wrapEmitCliFirst( const AgentTarget&amp; row, const std::string&amp; token, const std::string_view executablePath, const WrapListing&amp; listing ) noexcept</d>
<d l="442" n="wrapWritesToolsArg" sc="rw" p="src/wrap.h" cx="6" ccx="1" in="2" r="4">
<doc>mcp-tools pass-through. Written into the server command only where its argument shape is known t…</doc>inline bool wrapWritesToolsArg( const AgentTarget&amp; row ) noexcept</d>
</sigs>
<bodies shown="2" total="6" capped="1">
<b t="fn" l="2968" p="src/cli.h" n="printUsage">
<![CDATA[inline void printUsage( std::FILE* out ) noexcept { printUsageTier( out, HelpTier::Full, {} ); }]]>
<calls total="1">
<c n="printUsageTier" l="2958">inline bool printUsageTier( std::FILE* out, HelpTier tier, std::string_view want ) noexcept</c>
</calls>
</b>
<b t="fn" l="442" p="src/wrap.h" n="wrapWritesToolsArg">
<![CDATA[inline bool wrapWritesToolsArg( const AgentTarget& row ) noexcept
{
    switch( row.mcpForm )
    {
        case McpForm::Json:
        case McpForm::JsonMcpKey:
            return true;
… [70 more display lines; full output is 23483 bytes on 77 raw line(s)]
`````

## `./build/ripwire . --for="pagerank power iteration" --with-graph`

*Task lens + a compact Mermaid flowchart of the top anchors' 1-hop edges.*

**wall time: 1.06s**

`````
<ctx task="pagerank power iteration" route="subtoken+body" root="." confidence="high" margin_pct="20" at="c7920353a" doc_mentions="5" schema="ripwire.for/v1" bundle="compact" bodies="0" reason="compact-route" budget_bytes="7500" doc_mentions_capped="1" doc_mentions_total="16" est_tokens="3735">
<!-- ripwire for schema=ripwire.for/v1: bundle=/bodies=/reason= the body posture; d: cx= ccx= complexity, in= callers (absent cx/ccx/in = 0), churn= amp= change, clone= tested= 1, sc= scope, id=p::sc::n; total= shown= capped=1 if cut; task= the query; d pure=1 const/constexpr sig, next= the follow-up to paste; route= name-exact(X)|subtoken+body[:broad|:declined]; confidence=/margin_pct= head score drop (low=flat); h l= p= n=, c n= l= (joined for same-named callees, shown= counts them), noedge= no callee resolved; t p= file outside sigs (weaker), r= rank (gap = trimmed); field name= type= owner= rel=: a member of owner=, rel=creates held by value, uses by reference/pointer; d layer=: built-in arch layer (game|infra|render|math|audio|ai|test) from a dir name in p= [doc mentions: 5 docs, 3 symbols; doc_mentions=] -->
<!-- root= is the crawl root; p= below is RELATIVE to it (single-root only; absent => p= is ingest's own path, unchanged); at=this commit(+dirty). dropped_positive="17" [budget_bytes= is the default BYTE ceiling this ranked payload was shaped against; it bounds that payload, not the whole document est_tokens prices] [docs_dropped=N: N shown rows have a doc comment not printed (r>24 always, r5..24 if capped)] [cut: doc_mentions_capped="1" doc_mentions_total="16" — an indexing cap dropped content not shown here]; lego/compose collapse to a counted stub by default (a disclosed cut): total= that section's own pre-cap row count, shown="0" capped="1" (nothing rendered here), next= names the sections=lego,compose flag that restores both sections byte-identically in one call est_tokens= prices this bundle in tokens -->
<sigs shown="23" total="40" capped="1" docs_dropped="11">
<d l="419" n="kScoreTieAbsEps" sc="rw" p="src/eval.h" churn="16" amp="28" pure="1" r="1" next="--expand=src/eval.h:kScoreTieAbsEps">
<doc>NodeId order. Renumbering an otherwise-identical graph (the exact &quot;same probe file, different so…</doc>inline constexpr float kScoreTieAbsEps = 1e-6f</d>
<d l="73" n="renderDisclosure" sc="rw" p="src/prconverge.h" cx="12" ccx="15" in="14" churn="3" amp="41" r="2">
<doc>Render one form of the disclosure. Empty string whenever there is nothing to say — no power it…</doc>inline std::string renderDisclosure( const RankDisclosure&amp; d, DiscloseAs as )</d>
<d l="99" n="pageRankDouble" sc="rw" p="src/pagerank.cpp" cx="19" ccx="34" in="2" churn="14" amp="44" tested="1" r="3">
<doc>The PageRank power iteration itself — the numeric kernel every ranked document&apos;s order comes f…</doc>PageRankRun pageRankDouble( const sparseCsr&lt;float&gt;&amp; inEdges, std::span&lt;const double&gt; weightedOutDegree, std::span&lt;const double&gt; teleport, std::span&lt;double&gt; r … [line truncated: 10 more bytes on this line]
<d l="51" n="RankDisclosure" sc="RankDisclosure" p="src/prconverge.h" churn="3" amp="27" r="4">
<doc>What a ranked document discloses about the power iteration that ordered it. `isPageRank == false…</doc>struct RankDisclosure</d>
<d l="474" n="rankByText" sc="rw" p="src/mcpverbs.h" cx="10" ccx="17" in="1" churn="309" amp="406" r="5">inline std::string rankByText( const std::string&amp; root, std::string_view mode, int topK, bool stable = false )</d>
<d l="5556" n="RankedGraph" sc="RankedGraph" p="src/graph.h" churn="245" amp="394" r="6">struct RankedGraph</d>
<d l="2206" n="kChurnRankLegend" sc="rw" p="src/serialize.h" churn="249" amp="387" pure="1" r="7">inline constexpr const char* kChurnRankLegend = &quot;&lt;!-- rank_by=churn: k= is PageRank re-run with the teleport BIASED by git CHANGE-FREQUENCY over window= &quot; &quot;(a c…</d>
<d l="1372" n="sliceRdIterationCeiling" sc="slicev" p="src/slice.h" cx="9" ccx="12" in="1" churn="51" amp="103" r="8">inline std::uint32_t sliceRdIterationCeiling() noexcept</d>
<d l="31" n="PageRankRun" sc="PageRankRun" p="src/pagerank.h" churn="8" amp="37" r="9">struct PageRankRun</d>
<d l="7386" n="navRelevanceWeight" sc="rw" p="src/graph.h" cx="2" ccx="1" in="2" churn="245" amp="396" r="10">inline std::uint32_t navRelevanceWeight( const Graph&amp; g, NodeId n ) noexcept</d>
<d l="5565" n="rankGraphTeleport" sc="rw" p="src/graph.h" cx="5" ccx="8" in="7" churn="245" amp="401" r="11">inline RankedGraph rankGraphTeleport( const Graph&amp; g, const std::vector&lt;float&gt;&amp; p, float alpha = 0.85f )</d>
<d l="58" n="HOT_FILES" p="scripts/optremarks.py" churn="10" amp="60" r="12">HOT_FILES = ( &quot;src/pagerank.cpp&quot;, # the power-iteration loop — G2&apos;s no-allocation scope &quot;src/infra/radixSort.h&quot;, # LSD radix entry points &quot;src/infra/radixSort…</d>
<d l="1247" n="kPowerShellPathPrependScope" sc="rw::oswin" p="src/infra/os_win32_logic.h" layer="infra" churn="20" amp="50" pure="1" r="13">inline constexpr std::string_view kPowerShellPathPrependScope = &quot;in PowerShell, for this window</d>
<d l="1241" n="powerShellPathPrependHint" sc="rw::oswin" p="src/infra/os_win32_logic.h" layer="infra" cx="1" in="4" churn="20" amp="54" tested="1" r="14">inline std::string powerShellPathPrependHint( std::string_view programDir ) noexcept</d>
<d l="1207" n="powerShellSingleQuote" sc="rw::oswin" p="src/infra/os_win32_logic.h" layer="infra" cx="8" ccx="6" in="2" churn="20" amp="52" tested="1" r="15">inline std::string powerShellSingleQuote( std::string_view s ) noexcept</d>
<d l="967" n="path_prepend_hint" sc="rw::os" p="src/infra/os.h" layer="infra" cx="1" in="1" churn="29" amp="70" r="16">inline std::string path_prepend_hint( std::string_view dir )</d>
<d l="6303" n="Wave-2 adversarial verification (2026-08-19) — six probes against `aa97c9e`" sc="6. Correctness and quality instruments" p="docs/EVALS.md" churn="834" amp="1058" r="17">### Wave-2 adversarial verification (2026-08-19) — six probes against `aa97c9e`</d>
<d l="227" n="Same answer, a fraction of the tokens — read this table first if your agent is on a budget" sc="Rip&apos;n Fast. Fewer Tokens. Better Code." p="README.md" churn="889" amp="889" r="18">### Same answer, a fraction of the tokens — read this table first if your agent is on a budget</d>
<d l="1693" n="Anchor-only auto bodies — T3 substitution round, PRE-REGISTERED 2026-08-22 (before any fix code)" sc="4. Ranking changes, measured" p="docs/EVALS.md" churn="834" amp="1058" r="19">### Anchor-only auto bodies — T3 substitution round, PRE-REGISTERED 2026-08-22 (before any fix code)< … [line truncated: 3 more bytes on this line]
<d l="36" n="Background — read these, in this order" sc="Certified ranking order — say how far down the order is provably right" p="prompts/help-wanted/certified-ranking-order.md" churn="1" r="20">## Background — read these, in this order</d>
<d l="117" n="Design space and constraints" sc="Certified ranking order — say how far down the order is provably right" p="prompts/help-wanted/certified-ranking-order.md" churn="1" r="21">## Design space and constraints</d>
<d l="97" n="COLD_FILES" p="scripts/optremarks.py" churn="10" amp="60" r="22">COLD_FILES = ( # ── ingest sections that are not on the per-file / per-symbol default path ──────────────────── ( &quot;src/ingest_astquery.h&quot;, &quot;the --match / --lint AS … [line truncated: 40 more bytes on this line]
… [60 more display lines; full output is 9337 bytes on 10 raw line(s)]
`````

## `./build/ripwire . --export=cc.json:<scratch>/aux/ripwire2.cc.json`

*Per-file metrics as CodeCharta cc.json.*

**wall time: 1.02s**

`````
(empty)
`````

Artifact written:

`````
  374998 <scratch>/aux/ripwire2.cc.json
{"projectName":"project","apiVersion":"1.3","attributeDescriptors":{"loc":{"title":"Lines of Code","description":"Physical line count","direction":-1},"symbols":{"title":"Symbols","description":"Definitions in the file","direction":-1},"cx":{"title":"Cyclomatic Complexity","description":"Sum of per-symbol cyclomatic complexity","direction":-1},"cognitive_cx":{"title":"Cognitive Complexity","descri
`````

## `./build/ripwire . --batch=<scratch>/aux/batch2.txt`

*One-turn sweep: 4 newline-delimited verb:arg sub-queries answered in ONE deduped <batch>.*

**wall time: 1.37s**

Input file:

`````
for:incremental cache invalidation
callers:rankGraphTeleport
grep:DISCLOSE
lego:Vehicle
`````

`````
<batch schema="ripwire.batch/v1" n="4" requested="4" cap="16">
<!-- ripwire batch schema=ripwire.batch/v1: n= read sub-queries in one sweep (requested=, cap=): each <q> wraps one sub-answer verbatim in CDATA. i=/verb=/ok=: sub-query index, its verb text, 1 answered (payload in CDATA) or 0 failed. -->
<q i="0" verb="for" ok="1">
<![CDATA[<ctx task="incremental cache invalidation" route="subtoken+body" root="." confidence="high" margin_pct="22" at="c7920353a" doc_mentions="5" doc_mentions_capped="1" doc_mentions_total="7" bundle="sigs" lens="churn,amp,tested" budget_bytes="7500" est_tokens="3718">
<!-- ripwire lens for "incremental cache invalidation" [doc mentions: 5 docs discussing 3 top-ranked symbols surfaced; doc_mentions= on the root repeats the doc count] [cut: doc_mentions_capped="1" doc_mentions_total="7" — an indexing cap dropped content not shown here]: reusable building blocks (cx=complexity, in=reuse-count; an absent cx/ccx/in is 0) — prefer composing/reusing these over reimplementing; sc=scope (full id p::sc::n); route= name-exact(X)|subtoken+body[:broad|:declined]; bundle=sigs: signatures only in this bundle, no inline bodies — fetch a symbol's full body with the fetch_body verb [confidence= derives from the ranked head's largest relative score drop (margin_pct=, whole percent, 0 = none; the same gap the adaptive flag cuts at). low = flat ranking: treat the set as a starting point, not an answer]; lens="churn,amp,tested": the three per-row quality columns the CLI for lens carries and this dialect does NOT (they need a git and a quality pass this server does not run per request); an absent column here means NOT MEASURED, never measured-and-zero; est_tokens= prices this bundle in tokens; tail: file-grain tail, WEAKER evidence than the ranked rows (paths only): every positive-score file NOT among the shown sigs rows — the files of trimmed rows first, best-symbol rank order; rows are t p=file; total=such files, shown=printed, capped=1 when they differ. r= on a ranked row is its 1-based rank in this lens ranking, rows in r= order, p= the file (a gap = a budget-trimmed row); lego/compose collapse to a counted stub by default (a disclosed cut): total= that section's own pre-cap row count, shown="0" capped="1" (nothing rendered here), next= names the sections=lego,compose flag that restores both sections byte-identically in one call -->
<!-- root= is the crawl root; p= below is RELATIVE to it (single-root only; absent => p= is ingest's own path, unchanged); at=this commit(+dirty). dropped_positive="13" [budget_bytes= is the default BYTE ceiling this ranked payload was shaped against; it bounds that payload, not the whole document est_tokens prices] [docs_dropped=N: N shown rows have a doc comment not printed (r>24 always, r5..24 if capped)] -->
<!-- <d cx= ccx=>: cyclomatic/cognitive complexity. pure=1: const/constexpr signature (Swift: non-mutating) and no transitive side effect found; a hint. task=: the trace source this bundle maps, verbatim (a file path, stdin, or an MCP label). layer=: built-in arch layer (game|infra|render|math|audio|ai|test) from a dir name in p=; absent if none. -->
<sigs shown="27" total="40" capped="1" docs_dropped="10">
<d l="125" n="kCacheMagic" p="src/ingest_cache.h" pure="1" r="1" next="--expand=src/ingest_cache.h:kCacheMagic">
<doc>incremental cache (--cache): per-file content hash + raw facts so a re-run re-parses ONLY      c…</doc>constexpr std::uint32_t kCacheMagic = 0x4b505443</d>
<d l="1628" n="spanTierMemoPath" sc="rw" p="src/ingest_astquery.h" cx="1" in="3" r="2">
<doc>Composed exactly the way every OTHER blob family is (quality.h): one fixed-width identity hex pe…</doc>inline std::string spanTierMemoPath( const std::string&amp; diskPath )</d>
<d l="277" n="ingestCommitTree" sc="rw::dmm" p="src/dmm.h" cx="6" ccx="5" in="1" r="3">
<doc>Ingest the tree at `sha`, materialized out of `root`&apos;s object store. The HEAD side reuses the SA…</doc>inline bool ingestCommitTree( const std::string&amp; root, const std::string&amp; sha, const std::vector&lt;std::string&gt;&amp; excludes, std::size_t maxFileBytes, IngestResult&amp;… … [line truncated: 4 more bytes on this line]
<d l="890" n="mcpRefreshedThisRequest" sc="rw" p="src/mcpindex.h" cx="1" in="2" r="4">
<doc>P1-15 — the `_reingest` envelope field for a response whose handling ran an INCREMENTAL pass, …</doc>inline bool mcpRefreshedThisRequest( std::uint64_t passesAtEntry )</d>
<d l="766" n="mcpRebuildBaseline" sc="rw" p="src/mcpindex.h" cx="2" ccx="1" in="1" r="5">inline McpRebuildBaseline mcpRebuildBaseline( const McpIndex&amp; ix, bool isIncrementalPass )</d>
<d l="1233" n="FileHealth" sc="FileHealth" p="src/model.h" r="6">struct FileHealth</d>
<d l="7592" n="legoImplementorsOnSurface" sc="rw" p="src/serialize.h" cx="10" ccx="13" in="2" r="7">inline std::vector&lt;std::vector&lt;NodeId&gt;&gt; legoImplementorsOnSurface( const IngestResult&amp; ing, const std::vector&lt;std::vector&lt;NodeId&gt;&gt;&amp; implementors, const std::vec…</d>
<d l="1165" n="getIndex" sc="rw" p="src/mcpindex.h" cx="22" ccx="39" in="35" r="8">inline const McpIndex&amp; getIndex( const std::string&amp; root )</d>
<d l="922" n="mcpFreshFields" sc="rw" p="src/mcpindex.h" cx="2" ccx="1" in="1" r="9">inline std::string mcpFreshFields( std::uint64_t passesAtEntry )</d>
<d l="493" n="McpIndex" sc="McpIndex" p="src/mcpindex.h" r="10">struct McpIndex</d>
<d l="310" n="See the map — not just the numbers" sc="Rip&apos;n Fast. Fewer Tokens. Better Code." p="README.md" r="11">### See the map — not just the numbers</d>
<d l="4013" n="computeHeadSnapshot" sc="quality" p="src/quality.h" cx="19" ccx="21" in="3" r="12">inline std::pair&lt;Snapshot, bool&gt; computeHeadSnapshot( const std::string&amp; root, const std::string_view* cacheNever = nullptr, std::size_t maxFileBytes = kDefault…</d>
<d l="1099" n="receiptNextFor" sc="mcpedit" p="src/mcpedit.h" cx="4" ccx="3" in="1" r="13">inline std::string receiptNextFor( const std::string&amp; fileIdentity, const std::string&amp; symbolName, const std::string&amp; foldJson, const std::string&amp; firstTestRun )</d>
<d l="753" n="runParsePool" p="src/ingest_parsepool.h" cx="25" ccx="54" in="1" r="14">inline RawFacts runParsePool( IngestResult&amp; result, const char* rootDir, std::string_view cacheFile, bool captureValueUses, HashMap&lt;std::string, FileFacts&gt;&amp; cache, const CacheLoadStats&amp; cacheStats … [line truncated: 59 more bytes on this line]
<d l="292" n="ingest" sc="rw" p="src/ingest.cpp" cx="12" ccx="15" in="14" r="15">IngestResult ingest( const char* rootDir, const std::vector&lt;std::string&gt;&amp; excludeSubstr, std::string_view cacheFile, std::size_t maxFileBytes, bool captureValueUses, std::string_view excludeLabel, bool respect … [line truncated: 29 more bytes on this line]
<d l="222" n="cacheArtifactVerdict" sc="rw" p="src/ingest.cpp" cx="1" in="1" r="16">const char* cacheArtifactVerdict( const std::string&amp; path, bool captureValueUses )</d>
<d l="3646" n="cachePathIsDirectory" p="src/main.cpp" cx="3" ccx="2" in="1" r="17">static bool cachePathIsDirectory( const std::string&amp; cachePath )</d>
<d l="60" n="kCacheRuleNames" sc="rw::cachelint" p="src/cachelint.h" pure="1" r="18">inline constexpr std::array&lt;std::string_view, 8&gt; kCacheRuleNames =</d>
… [57 more display lines; full output is 41093 bytes on 1 raw line(s)]
`````


---

# self-diagnosis

## `./build/ripwire . --doctor`

*Environment self-check: binary staleness, grammars, cache dir, git, tracked-binary staleness — exit 1 when any check fails (here: the PATH install is older than ./build).*

**exit code: 1** — **wall time: 2.61s**

`````
<!-- ripwire doctor schema=ripwire.doctor/v1: setup health: <c n= ok=> checks; exit 1 when one fails. at=: commit+dirty+shallow. n=: the check's name (binary-path, grammars, cache-dir, git, tree-sitter, index-cache, layout ...). loaded=/expected=: grammars whose tags query compiled / grammars compiled in; a shortfall fails the row. dir=: the per-user cache directory scanned (TMPDIR/XDG_CACHE_HOME ladder); unwritable fails the row. blobs=N: ripwire cache blobs in dir=; the scan stops at 4096 (blobs_floor=1 then). bytes=N: total size in bytes of the blobs counted (short when truncated=1). many=1: more than 50 blobs; an eviction-sanity flag, informational, never fails the row. truncated=1: cache-dir, blob scan cut (cap or I/O error); tracked-binaries, scan SKIPPED, stale=0 unmeasured. locks=N: advisory edit-lock files under locks/; unheld ones over a day old are swept on a cache write. volatile=: this row's attributes that read LIVE machine state; a determinism diff strips them, never the row. git=0|1: git runs from PATH; 0 fails the row (churn verbs need it). repo=0|1: the root is inside a git work tree; 0 is a diagnosis, not a failure. history=0|1: the repo has at least one commit; head= prints only when it does. head=: HEAD's short sha (9 hex, the at= width). core_abi=/cpp_grammar_abi=: tree-sitter core language ABI / the C++ grammar's ABI; informational. languages=N: distinct compiled-in grammars (the grammars row's expected=). tracked=N: git ls-files count, printed even when truncated=1 (over 20000 files skips the scan). binaries=N: tracked paths that sniff as binary content. non_git=1: no git history to compare; the row passes unscanned. stale=N: tracked binaries committed before a same-dir same-stem source changed; any fails the row. cache_version=/parser_ver_lean=/parser_ver_rich=/artifact_arch=: index identity; reuse needs all four. rich_verbs=: the verbs that consume the rich artifact (rich=); every other verb reads the lean one. source=: auto (per-root blob), cache-flag (named by the cache flag) or disabled (no-cache: nothing read). lean_path=/rich_path=: the artifact files checked; one path when the cache flag named it. lean=/rich=: can THIS binary open that artifact (ok, absent, parser-version ...); format, never freshness. fsmonitor=: the checkout's core.fsmonitor at startup: unset, builtin, off, or hook (a command git runs). neutralised=1: a hook fsmonitor was overridden to false for this run; 0 when none was needed. state=: layout records agree, disagree (mixed binary: rebuild clean-first), not-checked or no-records. checked=1: the cross-unit layout comparison ran; 0 = under two comparable records. units=N: translation units that registered a layout record. types=N: layout types recorded (only those registered in src/model.h); omitted on state=disagree. checks=/passed=: checks run / how many passed; exit 1 when passed= is below checks=. built_from=: the commit this binary was built from; at= is the tree HEAD now, a mismatch is normal. self=/which=: this binary's path and the one which ripwire finds on PATH; which_version= is the version line that one prints when they differ. on_path=0|1: whether a ripwire is on PATH; 0 fails the row and hint= carries the export line. same_file=1: the PATH copy is this very file (same device and inode). same_bytes=1: a different file with identical content, a copied install (ok); 0 fails the row; unknown: a file was unreadable; the row fails unverified (hint= names it). self_mtime=/self_size=/which_mtime=/which_size=: epoch mtime and byte size of each binary. hint=: the row's verdict and fix in plain text (which binary is stale, what to run). -->
<doctor schema="ripwire.doctor/v1" checks="9" passed="8" at="c7920353a" built_from="c7920353a">
<c n="binary-path" ok="0" self="./build/ripwire" which="/opt/homebrew/bin/ripwire" on_path="1" same_file="0" same_bytes="0" self_mtime="1791441871" self_size="55777512" which_mtime="1790819582" which_size="53425560" which_version="ripwir … [line truncated: 399 more bytes on this line]
<c n="grammars" ok="1" loaded="25" expected="25"/>
<c n="cache-dir" ok="1" dir="<tmp>" blobs="1020" bytes="1880324224" many="1" truncated="0" locks="741" volatile="blobs,blobs_floor,bytes,many,truncated,locks"/>
<c n="git" ok="1" git="1" repo="1" history="1" head="c7920353a"/>
<c n="tree-sitter" ok="1" core_abi="15" cpp_grammar_abi="14" languages="25"/>
<c n="tracked-binaries" ok="1" tracked="3094" binaries="33" non_git="0" truncated="0" stale="0"/>
<c n="index-cache" ok="1" cache_version="28" parser_ver_lean="143" parser_ver_rich="144" artifact_arch="16" rich_verbs="for,uses,metrics,exemplar,context-ratio,nonlocal-state,quality-panel,verify,eval-retrieval,eval-mined,eval-skills" source="auto" lean_path="<tmp> … [line truncated: 219 more bytes on this line]
<c n="git-config-trust" ok="1" fsmonitor="unset" neutralised="0"/>
<c n="layout" ok="1" state="agree" checked="1" units="2" types="12"/>
</doctor>
`````


---

# security

## `./build/ripwire --scan-skill=skills/ripwire-orient/SKILL.md`

*Scan a single skill file for injection/exfiltration patterns before installing.*

`````
<!-- ripwire scan-skills schema=ripwire.scan-skills/v1: injection/exfiltration/path-traversal scan of skill files: files= findings= skipped= verdict=. files=N: files scanned (unscannable ones are skipped=). findings=N: pattern hits; rows print up to 200 (shown= capped=1 past that). verdict=clean|warn|critical: the worst finding's severity, the same as exit 0/1/2. -->
<skillscan schema="ripwire.scan-skills/v1" files="1" findings="0" verdict="clean">
</skillscan>
`````

stderr:

`````
ripwire scan: 0 finding(s) in skills/ripwire-orient/SKILL.md
`````

## `./build/ripwire --scan-skills=skills`

*Scan a whole skills directory (exit 2 = CRITICAL, 1 = WARN). Explicit-DIR form only.*

`````
<!-- ripwire scan-skills schema=ripwire.scan-skills/v1: injection/exfiltration/path-traversal scan of skill files: files= findings= skipped= verdict=. files=N: files scanned (unscannable ones are skipped=). findings=N: pattern hits; rows print up to 200 (shown= capped=1 past that). verdict=clean|warn|critical: the worst finding's severity, the same as exit 0/1/2. -->
<skillscan schema="ripwire.scan-skills/v1" files="26" findings="0" verdict="clean">
</skillscan>
`````

stderr:

`````
ripwire scan: 0 finding(s) total (26 skill file(s) scanned, 0 unscannable file(s) skipped, 0 denylisted subtree(s) not descended)
`````


---

# knobs / modes

## `./build/ripwire . --rank-by=churn --top-k=5`

*Rank by git change-frequency prior instead of PageRank.*

**wall time: 1.07s**

`````
<!-- ripwire map schema=ripwire.map/v1: ranked symbol map: <f p= layer=> groups <s t= n= sc= k= amb=> rows (k= rank), <c n=> resolved callees; the header comment is data. est_tokens=: price as emitted (an upper bound under compact). at=: commit+dirty+shallow. root=: p= relative to it. pr_iters=N: PageRank iterations. rank_by=: the ranker behind k=. window=: the git span mined. declined=K: K calls left unbound (no evidence chose one def). external=K: K calls proven outside the tree, no edge. locality_pinned=K: K calls pinned by locality alone (a guess). extent_suspect_syms=K: K defs failed containment, corpus-wide. macro_blanked_files=K: K files indexed from a macro-blanked re-parse. overloads=N: N same-name defs merged in this row; shown= counts each. files=/symbols=: files and symbols indexed; edges= distinct call edges; shown= symbols printed, a merged row counting each def; ambiguous= calls split over several defs, corpus-wide; unresolved= calls with in-tree evidence and no edge (every def language-filtered or unreachable, or binding refused); order= rows by rank (important-first, important-last; (auto:fill) = flipped past a size threshold) or by path (stable). skipped_oversize=K: K files over a size ceiling, not indexed. unindexed=ext:N: N text files of that extension no grammar reads (6 extensions at most). unindexed_exts=E: E such extensions in all, the list cut. sc=: enclosing scope; the full id is p::sc::n (p= of the row or its <f>) and selectors take it. -->
<!-- t=modscope=a-file's-MODULE-SCOPE(n=<file-scope>):the-statements-outside-every-named-definition,where-a-top-level-call-and-an-anonymous-callback-body's-calls-live;a-CALLER-never-a-callee(nothing-in-the-source-can-name-it)-with-no-body-to-expand;a-file-with-no-such-call-has-no-such-row -->
<!-- files=2484 symbols=23851 edges=34236 shown=5 est_tokens=1039 ambiguous=10278 unresolved=12878 locality_pinned=12 external=7345 declined=9922 extent_suspect_syms=10 macro_blanked_files=7 skipped_oversize=15 unindexed="txt:73,tsv:49,jsonl:26,scm:23,expected:15,xml:13" unindexed_exts=20 order=important-first -->
<r schema="ripwire.map/v1" at="c7920353a" root="." rank_by="churn" window="18mo@HEAD" est_tokens="1039" pr_iters="27">
<f p="src/resolve.h">
<s t="method" n="empty" sc="RubyConstantIndex" k="0.0115">
</s>
</f>
<f p="src/infra/svector.h" layer="infra">
<s t="method" n="buf" sc="svector" overloads="2" k="0.0088">
</s>
</f>
<f p="src/notes.h">
<s t="method" n="empty" sc="NoteIndex" k="0.0082">
</s>
</f>
<f p="src/scipoverlay.h">
<s t="method" n="empty" sc="ScipOverlay" k="0.0081">
</s>
</f>
</r>
`````

## `./build/ripwire . --rank-by=churn-decay --since=HEAD~3 --exclude=test --exclude=docs --exclude=skills --in=src --limit=3`

*Scope the recent-changes answer to ONE directory. The global <recent> block stays byte-identical, a second <recent scope="src"> page follows it — n=/of= are its counts (of= IS the total, so the paging half carries no total=), capped="1" has_more="1" next_offset= offset= limit= page it, and next= replays THIS run's own corpus flags (--since/--exclude) so the page it names is a page of the same answer. The symbol map collapses to a disclosed <symbols stubbed="1" would_show= next=/> stub — the map was not asked for and was not ranked at all, which is why the header carries no pr_iters=. merge_bombs_skipped= stays on the global block: it counts the window's skipped commits, not the directory's.*

`````
<!-- ripwire map schema=ripwire.map/v1: ranked symbol map: <f p= layer=> groups <s t= n= sc= k= amb=> rows (k= rank), <c n=> resolved callees; the header comment is data. window: capped= has_more= next_offset= (capped=1 cut; next_offset= pastes as offset=). est_tokens=: price as emitted (an upper bound under compact). at=: commit+dirty+shallow. root=: p= relative to it. rank_by=: the ranker behind k=. window=: the git span mined. declined=K: K calls left unbound (no evidence chose one def). external=K: K calls proven outside the tree, no edge. locality_pinned=K: K calls pinned by locality alone (a guess). <recent n= of=>: the n= newest-touched of of= touched files; <rc age_d=> days since its last commit, w= decayed weight. merge_bombs_skipped=N: N commits touching more than 100 INDEXED files skipped, uncounted; a file only they touched is absent; the window's count, so the global block only. <recent scope=DIR>: a second block riding when the global one does, DIR's files only (p= root-relative); of= is its total; capped=/has_more=/next_offset=/offset=/limit= page it, next= is that page. <symbols stubbed=1 would_show=N next=>: the symbol map in= did not ask for was not rendered; N is that run's own shown= — definitions counted individually as shown= counts them, so its rows follow from rows+sum(overloads-1)=shown (not the header's symbols= corpus count); next= fetches it. files=/symbols=: files and symbols indexed; edges= distinct call edges; shown= symbols printed, a merged row counting each def; ambiguous= calls split over several defs, corpus-wide; unresolved= calls with in-tree evidence and no edge (every def language-filtered or unreachable, or binding refused); order= rows by rank (important-first, important-last; (auto:fill) = flipped past a size threshold) or by path (stable). skipped_oversize=K: K files over a size ceiling, not indexed. unindexed=ext:N: N text files of that extension no grammar reads (6 extensions at most). unindexed_exts=E: E such extensions in all, the list cut. next=: the one pasteable follow-up. -->
<!-- t=modscope=a-file's-MODULE-SCOPE(n=<file-scope>):the-statements-outside-every-named-definition,where-a-top-level-call-and-an-anonymous-callback-body's-calls-live;a-CALLER-never-a-callee(nothing-in-the-source-can-name-it)-with-no-body-to-expand;a-file-with-no-such-call-has-no-such-row -->
<!-- files=526 symbols=13059 edges=26114 shown=0 est_tokens=1431 ambiguous=9279 unresolved=3565 locality_pinned=9 external=4558 declined=7973 skipped_oversize=15 unindexed="tsv:42,txt:24,jsonl:23,scm:23,expected:15,lock:7" unindexed_exts=12 order=important-first -->
<r schema="ripwire.map/v1" at="c7920353a" root="." rank_by="churn-decay" window="HEAD~3 half-life=90d" est_tokens="1431">
<recent n="7" of="7" merge_bombs_skipped="0">
<rc p="CHANGELOG.md" age_d="0" w="1"/>
<rc p="src/cli.h" age_d="0" w="1"/>
<rc p="src/compactlegend.h" age_d="0" w="1"/>
<rc p="src/crossref.h" age_d="0" w="1"/>
<rc p="src/mcprefusal.h" age_d="0" w="1"/>
<rc p="src/mcpverbs.h" age_d="0" w="1"/>
<rc p="present/deck5_ripwire_build.js" age_d="0" w="0.999"/>
</recent>
<recent scope="src" n="3" of="5" capped="1" has_more="1" next_offset="3" offset="0" limit="3" next="--rank-by=churn-decay --since=HEAD~3 --exclude=test --exclude=docs --exclude=skills --in=src --offset=3 --limit=3">
<rc p="src/cli.h" age_d="0" w="1"/>
<rc p="src/compactlegend.h" age_d="0" w="1"/>
<rc p="src/crossref.h" age_d="0" w="1"/>
</recent>
<symbols stubbed="1" would_show="200" next="--rank-by=churn-decay --since=HEAD~3 --exclude=test --exclude=docs --exclude=skills"/>
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
<!-- ripwire callers schema=ripwire.callers/v1: 1-hop CALLERS of of= (defs= matched, count= distinct symbols): <s t= n= p=>; hop_tested=/hop_untested=. counts_floor=1: every count is a FLOOR, never a total. graph_ambiguous=/graph_unresolved=: resolver gauge. graph_unindexed=N: N files no grammar could read (the map header's unindexed=); their calls raise neither gauge. root=: p= relative to it. format=columnar: parallel arrays, not row attributes: <paths> maps I=path, each <cols> array holds n= comma-separated values in one row order, fields= naming them (the path column indexes <paths>; &#44; is a comma). <tested> column: 1 = a non-test row an indexed test transitively reaches; 0 = none found, or a test row. next=: the one pasteable follow-up. -->
<callers schema="ripwire.callers/v1" of="rankGraphTeleport" defs="1" count="7" hop_tested="0" hop_untested="7" root="." graph_ambiguous="10278" graph_unresolved="12878" graph_unindexed="237" counts_floor="1" next="--uses=rankGraphTeleport" format="columnar">
<paths>0=src/mcpindex.h 1=src/graph.h 2=src/eval.h 3=src/main.cpp</paths>
<cols n="7" fields="path,name,line,kind,tested">
<path>0,1,1,2,3,3,3</path>
<name>getIndex,rankGraph,anchoredLexicalRank,runEval,churnDecayRanking,churnRankedGraph,runDefaultMap</name>
<line>1165,5606,6252,171,1380,1419,1629</line>
<kind>fn,fn,fn,fn,fn,fn,fn</kind>
<tested>0,0,0,0,0,0,0</tested>
</cols>
</callers>
`````

## `./build/ripwire . --for="cache invalidation" --format=candidates --top-k=5`

*Flat top-K export for an external reranker.*

`````
<!-- ripwire candidates: flat top K export for an external reranker. r=rank(1 based) s=SCORE n=name id=canonical k=KIND-tag p=path l=line. Note k= is the kind here and the PageRank score in the ranked map; on this row the score is s=. Root: count= rows exported of total= RANKED CORPUS symbols (total is the corpus size, never a match count), capped="1" means the top-k cut dropped some; route= names the ranker (s= is comparable only within one route); anchored= counts query-mention lifts (0 = the anchor ran and moved nothing); weak="1" means the top raw lexical score is below the confidence bar, so these rows rest on thin textual evidence; doc_tier= names the query SHAPE (a pasted trace, a pasted bug-report form) that scored documents down for this run, absent when none did. -->
<candidates count="5" total="23851" capped="1" route="subtoken+body" anchored="0">
<cand r="1" s="14.7766" n="spanTierMemoPath" id="src/ingest_astquery.h::rw::spanTierMemoPath" k="fn" p="src/ingest_astquery.h" l="1628">
<sig>inline std::string spanTierMemoPath( const std::string&amp; diskPath )</sig>
</cand>
<cand r="2" s="9.96218" n="legoImplementorsOnSurface" id="src/serialize.h::rw::legoImplementorsOnSurface" k="fn" p="src/serialize.h" l="7592">
<sig>inline std::vector&lt;std::vector&lt;NodeId&gt;&gt; legoImplementorsOnSurface( const IngestResult&amp; ing, const std::vector&lt;std::vector&lt;NodeId&gt;&gt;&amp; implementors, const std::vector&lt;NodeId&gt;&amp; surfaceIds )</sig>
</cand>
<cand r="3" s="8.12713" n="See the map — not just the numbers" id="README.md::Rip&apos;n Fast. Fewer Tokens. Better Code.::See the map — not just the numbers" k="sec" p="README.md" l="310">
<sig>### See the map — not just the numbers</sig>
</cand>
<cand r="4" s="7.63931" n="receiptNextFor" id="src/mcpedit.h::mcpedit::receiptNextFor" k="fn" p="src/mcpedit.h" l="1099">
<sig>inline std::string receiptNextFor( const std::string&amp; fileIdentity, const std::string&amp; symbolName, const std::string&amp; foldJson, const std::string&amp; firstTestRun )</sig>
</cand>
<cand r="5" s="6.22287" n="cacheArtifactVerdict" id="src/ingest.cpp::rw::cacheArtifactVerdict" k="fn" p="src/ingest.cpp" l="222">
<sig>const char* cacheArtifactVerdict( const std::string&amp; path, bool captureValueUses )</sig>
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
{"of":"rankGraphTeleport","defs":1,"count":7,"root":".","hop_tested":0,"hop_untested":7,"graph_ambiguous":10278,"graph_unresolved":12878,"graph_unindexed":237,"counts_floor":true,"callers":[{"t":"fn","n":"getIndex","p":"src/mcpindex.h:1165"},
{"t":"fn","n":"rankGraph","p":"src/graph.h:5606"},
{"t":"fn","n":"anchoredLexicalRank","p":"src/graph.h:6252"},
{"t":"fn","n":"runEval","p":"src/eval.h:171"},
{"t":"fn","n":"churnDecayRanking","p":"src/main.cpp:1380"},
{"t":"fn","n":"churnRankedGraph","p":"src/main.cpp:1419"},
{"t":"fn","n":"runDefaultMap","p":"src/main.cpp:1629"}]}
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

**wall time: 1.06s**

`````
<!-- ripwire hotspots schema=ripwire.hotspots/v1: maintenance pain = churn x ccx over window=: <f p= churn= ccx= score= top= top_ccx= top_l=>; unranked_*= no churn/complexity. window: shown= total= capped= has_more= next_offset= offset= limit= (capped=1 cut; next_offset= pastes as offset=). at=: commit+dirty+shallow. root=: p= relative to it. files=/ranked=: files in the window / those with both churn and complexity; ranked + unranked_no_churn + unranked_no_complexity = files. unranked_no_churn=/unranked_no_complexity=: files left out for no commit in window= / no measured complexity. -->
<!-- extent_suspect_syms=K on a row = K of the file's functions failed an extent/scope containment check (the map, the bundles and the skipped verb mark each one, reasons and all) and are LEFT OUT of that row's ccx=, score= and top=, so its ccx= is a FLOOR of the file's true sum rather than a total. unranked_extent_suspect= counts files with commits whose every scorable function was left out that way (or whose trusted remainder scores 0), so ranked= + unranked_no_churn= + unranked_no_complexity= + unranked_extent_suspect= = files= exactly. Absent = nothing excluded. -->
<hotspots schema="ripwire.hotspots/v1" window="12mo@HEAD" files="2484" ranked="663" unranked_no_churn="0" unranked_no_complexity="1819" unranked_extent_suspect="2" shown="3" capped="1" total="663" has_more="1" next_offset="6" offset="3" limit="3" root="." at="c7920353a">
<f p="src/main.cpp" churn="414" ccx="1165" score="482310" top="dispatchMain" top_ccx="471" top_l="4108"/>
<f p="src/mcpverbs.h" churn="309" ccx="1146" score="354114" top="runBatchSub" top_ccx="138" top_l="5220"/>
<f p="src/cli.h" churn="436" ccx="642" score="279912" top="parseArgs" top_ccx="213" top_l="5180"/>
</hotspots>
`````

## `./build/ripwire . --ignore-tests --top-k=5`

*Drop test paths from the corpus before ranking.*

`````
<!-- ripwire map schema=ripwire.map/v1: ranked symbol map: <f p= layer=> groups <s t= n= sc= k= amb=> rows (k= rank), <c n=> resolved callees; the header comment is data. est_tokens=: price as emitted (an upper bound under compact). root=: p= relative to it. pr_iters=N: PageRank iterations. declined=K: K calls left unbound (no evidence chose one def). external=K: K calls proven outside the tree, no edge. locality_pinned=K: K calls pinned by locality alone (a guess). macro_blanked_files=K: K files indexed from a macro-blanked re-parse. overloads=N: N same-name defs merged in this row; shown= counts each. files=/symbols=: files and symbols indexed; edges= distinct call edges; shown= symbols printed, a merged row counting each def; ambiguous= calls split over several defs, corpus-wide; unresolved= calls with in-tree evidence and no edge (every def language-filtered or unreachable, or binding refused); order= rows by rank (important-first, important-last; (auto:fill) = flipped past a size threshold) or by path (stable). skipped_oversize=K: K files over a size ceiling, not indexed. unindexed=ext:N: N text files of that extension no grammar reads (6 extensions at most). unindexed_exts=E: E such extensions in all, the list cut. sc=: enclosing scope; the full id is p::sc::n (p= of the row or its <f>) and selectors take it. -->
<!-- t=modscope=a-file's-MODULE-SCOPE(n=<file-scope>):the-statements-outside-every-named-definition,where-a-top-level-call-and-an-anonymous-callback-body's-calls-live;a-CALLER-never-a-callee(nothing-in-the-source-can-name-it)-with-no-body-to-expand;a-file-with-no-such-call-has-no-such-row -->
<!-- files=2484 symbols=14307 edges=27107 shown=5 est_tokens=952 ambiguous=9454 unresolved=3755 locality_pinned=9 external=4692 declined=8161 macro_blanked_files=7 skipped_oversize=15 unindexed="txt:73,tsv:49,jsonl:26,scm:23,expected:15,xml:13" unindexed_exts=20 order=important-first -->
<r schema="ripwire.map/v1" root="." est_tokens="952" pr_iters="22">
<f p="src/infra/svector.h" layer="infra">
<s t="method" n="buf" sc="svector" overloads="2" k="0.0098">
</s>
</f>
<f p="src/resolve.h">
<s t="method" n="empty" sc="RubyConstantIndex" k="0.0098">
</s>
</f>
<f p="src/infra/os_win32_logic.h" layer="infra">
<s t="method" n="ok" sc="WidePath" k="0.0086">
</s>
</f>
<f p="src/notes.h">
<s t="method" n="empty" sc="NoteIndex" k="0.0074">
</s>
</f>
</r>
`````

## `./build/ripwire . --exclude=present --exclude=bench --top-k=5`

*Drop matching paths (repeatable) before ranking.*

`````
<!-- ripwire map schema=ripwire.map/v1: ranked symbol map: <f p= layer=> groups <s t= n= sc= k= amb=> rows (k= rank), <c n=> resolved callees; the header comment is data. est_tokens=: price as emitted (an upper bound under compact). root=: p= relative to it. pr_iters=N: PageRank iterations. declined=K: K calls left unbound (no evidence chose one def). external=K: K calls proven outside the tree, no edge. locality_pinned=K: K calls pinned by locality alone (a guess). extent_suspect_syms=K: K defs failed containment, corpus-wide. macro_blanked_files=K: K files indexed from a macro-blanked re-parse. overloads=N: N same-name defs merged in this row; shown= counts each. files=/symbols=: files and symbols indexed; edges= distinct call edges; shown= symbols printed, a merged row counting each def; ambiguous= calls split over several defs, corpus-wide; unresolved= calls with in-tree evidence and no edge (every def language-filtered or unreachable, or binding refused); order= rows by rank (important-first, important-last; (auto:fill) = flipped past a size threshold) or by path (stable). unindexed=ext:N: N text files of that extension no grammar reads (6 extensions at most). unindexed_exts=E: E such extensions in all, the list cut. sc=: enclosing scope; the full id is p::sc::n (p= of the row or its <f>) and selectors take it. -->
<!-- t=modscope=a-file's-MODULE-SCOPE(n=<file-scope>):the-statements-outside-every-named-definition,where-a-top-level-call-and-an-anonymous-callback-body's-calls-live;a-CALLER-never-a-callee(nothing-in-the-source-can-name-it)-with-no-body-to-expand;a-file-with-no-such-call-has-no-such-row -->
<!-- files=2221 symbols=20623 edges=32834 shown=5 est_tokens=952 ambiguous=10237 unresolved=9512 locality_pinned=12 external=4769 declined=8798 extent_suspect_syms=10 macro_blanked_files=7 unindexed="txt:52,scm:23,xml:13,mod:7,tsv:7,cmake:5" unindexed_exts=15 order=important-first -->
<r schema="ripwire.map/v1" root="." est_tokens="952" pr_iters="29">
<f p="src/infra/svector.h" layer="infra">
<s t="method" n="buf" sc="svector" overloads="2" k="0.0080">
</s>
</f>
<f p="src/resolve.h">
<s t="method" n="empty" sc="RubyConstantIndex" k="0.0079">
</s>
</f>
<f p="src/infra/os_win32_logic.h" layer="infra">
<s t="method" n="ok" sc="WidePath" k="0.0070">
</s>
</f>
<f p="src/notes.h">
<s t="method" n="empty" sc="NoteIndex" k="0.0059">
</s>
</f>
</r>
`````

## `./build/ripwire . --map-diff --top-k=5`

*Full map re-ranked with teleport toward git-changed files — clean tree, so changed=0 and it degrades to the plain map.*

`````
<!-- ripwire map-diff schema=ripwire.map-diff/v1: the ranked map anchored at at=: what the diff touched, the map's row vocabulary. est_tokens=: price as emitted (an upper bound under compact). at=: commit+dirty+shallow. root=: p= relative to it. pr_iters=N: PageRank iterations. declined=K: K calls left unbound (no evidence chose one def). external=K: K calls proven outside the tree, no edge. locality_pinned=K: K calls pinned by locality alone (a guess). extent_suspect_syms=K: K defs failed containment, corpus-wide. macro_blanked_files=K: K files indexed from a macro-blanked re-parse. overloads=N: N same-name defs merged in this row; shown= counts each. files=/symbols=: files and symbols indexed; edges= distinct call edges; shown= symbols printed, a merged row counting each def; ambiguous= calls split over several defs, corpus-wide; unresolved= calls with in-tree evidence and no edge (every def language-filtered or unreachable, or binding refused); order= rows by rank (important-first, important-last; (auto:fill) = flipped past a size threshold) or by path (stable). changed=K: K indexed git-changed files seed the PageRank teleport (0: uniform, incl. no git). skipped_oversize=K: K files over a size ceiling, not indexed. unindexed=ext:N: N text files of that extension no grammar reads (6 extensions at most). unindexed_exts=E: E such extensions in all, the list cut. sc=: enclosing scope; the full id is p::sc::n (p= of the row or its <f>) and selectors take it. layer=: built-in arch layer (game|infra|render|math|audio|ai|test) from a dir name in p=; absent if none. -->
<!-- t=modscope=a-file's-MODULE-SCOPE(n=<file-scope>):the-statements-outside-every-named-definition,where-a-top-level-call-and-an-anonymous-callback-body's-calls-live;a-CALLER-never-a-callee(nothing-in-the-source-can-name-it)-with-no-body-to-expand;a-file-with-no-such-call-has-no-such-row -->
<!-- files=2484 symbols=23851 edges=34236 shown=5 est_tokens=1075 ambiguous=10278 unresolved=12878 locality_pinned=12 external=7345 declined=9922 extent_suspect_syms=10 macro_blanked_files=7 changed=0 skipped_oversize=15 unindexed="txt:73,tsv:49,jsonl:26,scm:23,expected:15,xml:13" unindexed_exts=20 order=important-first -->
<r schema="ripwire.map-diff/v1" at="c7920353a" root="." est_tokens="1075" pr_iters="28">
<f p="src/infra/svector.h" layer="infra">
<s t="method" n="buf" sc="svector" overloads="2" k="0.0072">
</s>
</f>
<f p="src/resolve.h">
<s t="method" n="empty" sc="RubyConstantIndex" k="0.0071">
</s>
</f>
<f p="src/infra/os_win32_logic.h" layer="infra">
<s t="method" n="ok" sc="WidePath" k="0.0063">
</s>
</f>
<f p="src/notes.h">
<s t="method" n="empty" sc="NoteIndex" k="0.0053">
</s>
</f>
</r>
`````

## `./build/ripwire . --no-cache --top-k=3`

*Force a cold parse (bypass the warm TMPDIR cache) — shows the cold-vs-warm cost.*

**wall time: 1.72s**

`````
<!-- ripwire map schema=ripwire.map/v1: ranked symbol map: <f p= layer=> groups <s t= n= sc= k= amb=> rows (k= rank), <c n=> resolved callees; the header comment is data. est_tokens=: price as emitted (an upper bound under compact). root=: p= relative to it. pr_iters=N: PageRank iterations. declined=K: K calls left unbound (no evidence chose one def). external=K: K calls proven outside the tree, no edge. locality_pinned=K: K calls pinned by locality alone (a guess). extent_suspect_syms=K: K defs failed containment, corpus-wide. macro_blanked_files=K: K files indexed from a macro-blanked re-parse. overloads=N: N same-name defs merged in this row; shown= counts each. files=/symbols=: files and symbols indexed; edges= distinct call edges; shown= symbols printed, a merged row counting each def; ambiguous= calls split over several defs, corpus-wide; unresolved= calls with in-tree evidence and no edge (every def language-filtered or unreachable, or binding refused); order= rows by rank (important-first, important-last; (auto:fill) = flipped past a size threshold) or by path (stable). skipped_oversize=K: K files over a size ceiling, not indexed. unindexed=ext:N: N text files of that extension no grammar reads (6 extensions at most). unindexed_exts=E: E such extensions in all, the list cut. sc=: enclosing scope; the full id is p::sc::n (p= of the row or its <f>) and selectors take it. -->
<!-- t=modscope=a-file's-MODULE-SCOPE(n=<file-scope>):the-statements-outside-every-named-definition,where-a-top-level-call-and-an-anonymous-callback-body's-calls-live;a-CALLER-never-a-callee(nothing-in-the-source-can-name-it)-with-no-body-to-expand;a-file-with-no-such-call-has-no-such-row -->
<!-- files=2484 symbols=23851 edges=34236 shown=3 est_tokens=916 ambiguous=10278 unresolved=12878 locality_pinned=12 external=7345 declined=9922 extent_suspect_syms=10 macro_blanked_files=7 skipped_oversize=15 unindexed="txt:73,tsv:49,jsonl:26,scm:23,expected:15,xml:13" unindexed_exts=20 order=important-first -->
<r schema="ripwire.map/v1" root="." est_tokens="916" pr_iters="28">
<f p="src/infra/svector.h" layer="infra">
<s t="method" n="buf" sc="svector" overloads="2" k="0.0072">
</s>
</f>
<f p="src/resolve.h">
<s t="method" n="empty" sc="RubyConstantIndex" k="0.0071">
</s>
</f>
</r>
`````

## `./build/ripwire . --cache=<scratch>/aux/warm2.ripwirecache --top-k=3`

*Explicit incremental cache at a path OUTSIDE the repo (first call writes it).*

**wall time: 1.80s**

`````
<!-- ripwire map schema=ripwire.map/v1: ranked symbol map: <f p= layer=> groups <s t= n= sc= k= amb=> rows (k= rank), <c n=> resolved callees; the header comment is data. est_tokens=: price as emitted (an upper bound under compact). root=: p= relative to it. pr_iters=N: PageRank iterations. declined=K: K calls left unbound (no evidence chose one def). external=K: K calls proven outside the tree, no edge. locality_pinned=K: K calls pinned by locality alone (a guess). extent_suspect_syms=K: K defs failed containment, corpus-wide. macro_blanked_files=K: K files indexed from a macro-blanked re-parse. overloads=N: N same-name defs merged in this row; shown= counts each. files=/symbols=: files and symbols indexed; edges= distinct call edges; shown= symbols printed, a merged row counting each def; ambiguous= calls split over several defs, corpus-wide; unresolved= calls with in-tree evidence and no edge (every def language-filtered or unreachable, or binding refused); order= rows by rank (important-first, important-last; (auto:fill) = flipped past a size threshold) or by path (stable). skipped_oversize=K: K files over a size ceiling, not indexed. unindexed=ext:N: N text files of that extension no grammar reads (6 extensions at most). unindexed_exts=E: E such extensions in all, the list cut. sc=: enclosing scope; the full id is p::sc::n (p= of the row or its <f>) and selectors take it. -->
<!-- t=modscope=a-file's-MODULE-SCOPE(n=<file-scope>):the-statements-outside-every-named-definition,where-a-top-level-call-and-an-anonymous-callback-body's-calls-live;a-CALLER-never-a-callee(nothing-in-the-source-can-name-it)-with-no-body-to-expand;a-file-with-no-such-call-has-no-such-row -->
<!-- files=2484 symbols=23851 edges=34236 shown=3 est_tokens=916 ambiguous=10278 unresolved=12878 locality_pinned=12 external=7345 declined=9922 extent_suspect_syms=10 macro_blanked_files=7 skipped_oversize=15 unindexed="txt:73,tsv:49,jsonl:26,scm:23,expected:15,xml:13" unindexed_exts=20 order=important-first -->
<r schema="ripwire.map/v1" root="." est_tokens="916" pr_iters="28">
<f p="src/infra/svector.h" layer="infra">
<s t="method" n="buf" sc="svector" overloads="2" k="0.0072">
</s>
</f>
<f p="src/resolve.h">
<s t="method" n="empty" sc="RubyConstantIndex" k="0.0071">
</s>
</f>
</r>
`````

Artifact written:

`````
 18649971 <scratch>/aux/warm2.ripwirecache
`````

## `./build/ripwire . --max-file-size=8K --top-k=3`

*Skip files above a size bound before parsing (note the corpus shrink in the header).*

`````
<!-- ripwire map schema=ripwire.map/v1: ranked symbol map: <f p= layer=> groups <s t= n= sc= k= amb=> rows (k= rank), <c n=> resolved callees; the header comment is data. est_tokens=: price as emitted (an upper bound under compact). root=: p= relative to it. pr_iters=N: PageRank iterations. declined=K: K calls left unbound (no evidence chose one def). external=K: K calls proven outside the tree, no edge. locality_pinned=K: K calls pinned by locality alone (a guess). extent_suspect_syms=K: K defs failed containment, corpus-wide. macro_blanked_files=K: K files indexed from a macro-blanked re-parse. files=/symbols=: files and symbols indexed; edges= distinct call edges; shown= symbols printed, a merged row counting each def; ambiguous= calls split over several defs, corpus-wide; unresolved= calls with in-tree evidence and no edge (every def language-filtered or unreachable, or binding refused); order= rows by rank (important-first, important-last; (auto:fill) = flipped past a size threshold) or by path (stable). skipped_oversize=K: K files over a size ceiling, not indexed. unindexed=ext:N: N text files of that extension no grammar reads (6 extensions at most). unindexed_exts=E: E such extensions in all, the list cut. -->
<!-- t=modscope=a-file's-MODULE-SCOPE(n=<file-scope>):the-statements-outside-every-named-definition,where-a-top-level-call-and-an-anonymous-callback-body's-calls-live;a-CALLER-never-a-callee(nothing-in-the-source-can-name-it)-with-no-body-to-expand;a-file-with-no-such-call-has-no-such-row -->
<!-- files=1538 symbols=6120 edges=1918 shown=3 est_tokens=858 ambiguous=101 unresolved=837 locality_pinned=3 external=810 declined=417 extent_suspect_syms=10 macro_blanked_files=7 skipped_oversize=961 unindexed="txt:73,tsv:49,jsonl:26,scm:23,expected:15,xml:13" unindexed_exts=20 order=important-first -->
<r schema="ripwire.map/v1" root="." est_tokens="858" pr_iters="38">
<f p="test/fnliteralfix/arrows.ts" layer="test">
<s t="fn" n="sink" k="0.0021">
</s>
</f>
<f p="src/alloccount.cpp">
<s t="fn" n="countedFree" k="0.0015">
</s>
</f>
<f p="test/fnliteralfix/arrows.js" layer="test">
<s t="fn" n="sinkJs" k="0.0012">
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

**wall time: 1.59s**

`````
<!-- ripwire map schema=ripwire.map/v1: ranked symbol map: <f p= layer=> groups <s t= n= sc= k= amb=> rows (k= rank), <c n=> resolved callees; the header comment is data. est_tokens=: price as emitted (an upper bound under compact). <root label= p=>: a workspace root; label= prefixes every p=/id=. pr_iters=N: PageRank iterations. declined=K: K calls left unbound (no evidence chose one def). external=K: K calls proven outside the tree, no edge. locality_pinned=K: K calls pinned by locality alone (a guess). extent_suspect_syms=K: K defs failed containment, corpus-wide. macro_blanked_files=K: K files indexed from a macro-blanked re-parse. overloads=N: N same-name defs merged in this row; shown= counts each. files=/symbols=: files and symbols indexed; edges= distinct call edges; shown= symbols printed, a merged row counting each def; ambiguous= calls split over several defs, corpus-wide; unresolved= calls with in-tree evidence and no edge (every def language-filtered or unreachable, or binding refused); order= rows by rank (important-first, important-last; (auto:fill) = flipped past a size threshold) or by path (stable). roots=N: N workspace roots. unindexed=ext:N: N text files of that extension no grammar reads (6 extensions at most). unindexed_exts=E: E such extensions in all, the list cut. sc=: enclosing scope; the full id is p::sc::n (p= of the row or its <f>) and selectors take it. -->
<!-- t=modscope=a-file's-MODULE-SCOPE(n=<file-scope>):the-statements-outside-every-named-definition,where-a-top-level-call-and-an-anonymous-callback-body's-calls-live;a-CALLER-never-a-callee(nothing-in-the-source-can-name-it)-with-no-body-to-expand;a-file-with-no-such-call-has-no-such-row -->
<!-- files=2098 symbols=17838 edges=31964 shown=5 est_tokens=1003 ambiguous=10157 unresolved=6251 locality_pinned=12 external=3554 declined=8441 extent_suspect_syms=10 macro_blanked_files=7 roots=2 unindexed="txt:49,xml:13,mod:7,tsv:5,jsonl:3,manifest:3" unindexed_exts=13 order=important-first -->
<r schema="ripwire.map/v1" est_tokens="1003" pr_iters="29">
<root label="src" p="src"/>
<root label="test" p="test"/>
<f p="src/resolve.h">
<s t="method" n="empty" sc="RubyConstantIndex" k="0.0089">
</s>
</f>
<f p="src/infra/svector.h" layer="infra">
<s t="method" n="buf" sc="svector" overloads="2" k="0.0089">
</s>
</f>
<f p="src/infra/os_win32_logic.h" layer="infra">
<s t="method" n="ok" sc="WidePath" k="0.0077">
</s>
</f>
<f p="src/notes.h">
<s t="method" n="empty" sc="NoteIndex" k="0.0066">
</s>
</f>
</r>
`````

## `./build/ripwire . --eval`

*Self-eval: co-change recall vs BM25.*

**wall time: 16.02s**

`````
ripwire --eval  (co-change recovery, averaged over 80 historical commits)
  ranker     recall@5  recall@10  recall@20
  ripwire        4.1%       8.3%      15.1%
  BM25          13.0%      15.1%      20.2%
  BM25sub       17.3%      23.3%      31.6%
  BM25body      13.7%      25.7%      44.5%
  fused         14.2%      18.3%      29.6%
  anchored      13.7%      25.7%      44.5%
  same-dir       0.0%       8.8%      13.8%
  random         0.2%       0.4%       0.8%   <- floor (random ranking over F=2484 files)
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

**wall time: 134.50s**

`````
ripwire --eval-retrieval  (known-item, 4000 doc-commented symbols; gold is in-corpus by construction)
  sample: population=5833 scored=4000 rule=smallest-key CAPPED — a SUBSET, not the population
          (smallest fnv1a64(scope::name) over the population, cut on the key so an identity is never split;
           path- and order-independent, but a corpus this size is NOT graded exhaustively — say so when citing it)
  ingest: lex=rich (persisted subtoken stats; no per-query corpus re-tokenize)
  ranker    query-mode     MRR  recall@1  recall@5 recall@10
  subtoken  name         0.693     56.1%     85.8%     90.8%
  subtoken  doc-phrase   0.920     90.0%     94.0%     94.9%
  name-exact name         0.905     83.5%     96.1%     97.4%
  name-exact doc-phrase   0.013      0.5%      1.8%      2.6%
  anchored  name         0.698     57.6%     85.2%     89.2%
  anchored  doc-phrase   0.917     89.5%     94.0%     94.5%
  routed    name         0.908     83.7%     96.3%     97.7%
  routed    doc-phrase   0.919     90.0%     93.8%     94.7%
  note: routing chose name-exact on 3986/4000 NAME queries (a NAME query is always identifier-shaped);
        the confidence gate routes doc-phrase queries to name-exact ONLY when EVERY content word names a symbol
        (or an explicit camel/snake token appears) AND every matched name is specific enough to anchor on —
        a common name (many definitions, or a subtoken carried by many symbol names) declines the route — so
        conceptual prose falls back to subtoken+body; routed tracks the better ranker on BOTH modes
        (routed==name-exact on name, ~=subtoken+body on doc-phrase).
`````

## `./build/ripwire . --eval-stray=<scratch>/aux/stray_labels2.tsv`

*Labelled verdict-accuracy eval for --stray-content — three labels over REAL local refs (names resolved at capture time); exit 3 when accuracy is under the floor. Read got= against v= in the stray-content run: a ref the verb could not analyse (unknown) must never be credited as a merged hit.*

**exit code: 3** — **wall time: 7.70s**

Input file:

`````
# ref<TAB>verdict labels for --eval-stray (the first three local branches, resolved at capture time; a missing branch is padded with a nonexistent name on purpose)
arm/for-howitworks-067-f2add	merged
arm/for-howitworks-067-placebo	unmerged
arm/orient-map-067-narrow	merged
`````

`````
<!-- ripwire stray-content eval: labelled verdict accuracy. Each row is one branch whose true state was established by hand; want= is the label, got= is what the classifier said. A branch absent from the report scores as merged ONLY when it is a real ref this repo has (merged refs are omitted by design); a label naming a ref that does not exist is refused, not scored (see badRefs on refusal). unknown= on the root counts cases whose verdict is unknown (no merge-base / unrelated history); its own bucket, never folded into merged. Use this to MEASURE a threshold change instead of eyeballing it. -->
<stray-eval cases="3" correct="1" unknown="0" accuracy="33.3">
<case ref="arm/for-howitworks-067-f2add" want="merged" got="unmerged" hit="0" reported="1"/>
<case ref="arm/for-howitworks-067-placebo" want="unmerged" got="unmerged" hit="1" reported="1"/>
<case ref="arm/orient-map-067-narrow" want="merged" got="unmerged" hit="0" reported="1"/>
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
ripwire --eval-skills  (skill routing over K=16 candidate skills [ripwire-router excluded]; 3 positive + 1 negative prompts; corpus '<scratch>/aux/skills_labels2.tsv'; split test=4 dev=0)
  arm           hit@1   hit@2     mrr   sep-auc   fire/abstain@ORACLE-th (upper bound)
  overlap       66.7%   66.7%   0.690     0.000    50.0% (th=-1.000)
  name          33.3%   66.7%   0.537     0.667    50.0% (th=0.000)
  bm25-desc     66.7%   66.7%   0.690     0.667    75.0% (th=2.958)
  bm25-full     33.3%   66.7%   0.611     1.000    50.0% (th=0.426)
  for-routed    33.3%   33.3%   0.556     1.000    50.0% (th=0.685)
  random         6.2%   12.5%   0.211     0.500   <- floor (uniform-random ranking; auc 0.5 by definition)
  provenance hit@1 (bm25-desc): router 0/0, desc 0/0, judged 2/3 (desc rows quote the descriptions - expect them easiest; judged is the honest number)
  judged-only hit@1 per arm: overlap 2/3, name 1/3, bm25-desc 2/3, bm25-full 1/3, for-routed 1/3
  router-magnet: with ripwire-router ADMITTED as a candidate it takes top-1 on 1/3 positive prompts (bm25-desc arm) - why it is excluded above
  per-skill (bm25-desc): name / permitted-rows / won / pos-fires / false-fires / neg-fires
    ripwire-before-you-build     0     0     1     1     0
    ripwire-change-check         1     0     0     0     0
    ripwire-find-bug             0     0     0     0     0
    ripwire-fresh-eyes           0     0     0     0     1
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
    line 3   want=ripwire-change-check got=ripwire-before-you-build "plan parallel worktrees so the lanes do not collide"
… [19 more lines, 3665 bytes total]
`````

## `./build/ripwire wrap claude`

*Print the recipe to wire ripwire into Claude Code as an MCP server.*

`````
# ripwire -> Claude Code (CLI-first)
# RECOMMENDED — this agent can run shell commands, so call the CLI directly. It costs
# nothing until you invoke it, and it reads CLAUDE.md, so the paste block below IS the wiring:
ripwire . --for="<your task>" --token-budget=2000
#
# ...every follow-up call answers with the compact legend by default (terse definitions of only the
# attributes the answer carries; the payload is byte-identical either way). Add --legend=full when a
# definition's reasoning is needed -- `ripwire --help` carries the measured saving (one place,
# gate-held) -- this line does not repeat it, because two copies of a number is one that goes stale:
#   ripwire . --callers=SYM --legend=full
#
# ALTERNATIVE — register the MCP server instead, for a warm index across calls:
claude mcp add ripwire -- ripwire --mcp
# verbs the agent can then call mid-task (33 total):
#   read:             analyze, rank_by, find_symbol, find_referencing_symbols, grep, cochange, memory_recall, situational_awareness, mentions, for, lego, owners, fetch_body, batch, flags, doc_drift, slice
#   flagship reflex:  exemplar, quality_delta, quality_baseline, impact, uses, affected, path_between, connect, explore, from_trace, edit_check, whereis, stray_content
#   edit:             replace_symbol_body, insert_before_symbol, insert_after_symbol
bash skills/install.sh   # deploy to ${CLAUDE_CONFIG_DIR:-~/.claude}/skills (drift-gated)
bash skills/install.sh --hook   # RECOMMENDED: advisory Read/Grep -> ripwire CLI nudge + session primer (opt-in, never blocks)
#
# context wiring — a binary on PATH is invisible to an agent until its rules file says when
# to reach for it. Paste the block below into CLAUDE.md:
# --- paste into CLAUDE.md ---
## ripwire — deterministic codebase maps (on PATH as `ripwire`)
Reach for it BEFORE blind grep + whole-file reads. First call ~1s cold; after that warm, ~0.1s.
- Orient on a task: `ripwire <dir> --for="<task in words>"` — ranked, quality-annotated
  signatures. Paste symbol/file names from the issue verbatim; named mentions get anchored.
- One task: `--pack-task="<task>" --legend=compact`; before parallel agents: `--plan-lanes=N --task="<goal>"`, then read `lanes[].execution`.
- Have a stack trace / build error: `ripwire <dir> --from-trace=FILE --legend=compact` (`-` = stdin) —
  paste the error, don't paraphrase it into a query.
… [14 more lines, 4078 bytes total]
`````

## `./build/ripwire --version`

*Version + short build info.*

`````
ripwire 0.6.5 (dev, AppleClang 21.0.0.21000101, emit=std::print, built_from=c7920353a)
`````


---

# navigate — seeds, claims, slices, shapes

## `./build/ripwire . --at=src/graph.h:5567`

*Hold a LOCATION, not a name: the enclosing-definition chain at FILE:LINE (a compiler error, a diff hunk, a stack frame), outermost -> innermost.*

`````
<!-- ripwire at schema=ripwire.at/v1: enclosing-definition chain at p=:l=: sym= innermost, chain= outermost-first, <s n= t= l= el=> spans. root=: p= relative to it. -->
<at schema="ripwire.at/v1" p="src/graph.h" l="5567" sym="rankGraphTeleport" chain="1" root=".">
<s n="rankGraphTeleport" t="fn" l="5565" el="5593"/>
</at>
`````

## `./build/ripwire . --callers=@src/graph.h:5567`

*The same seed in a SELECTOR position: @FILE:LINE resolves to the innermost enclosing definition, then --callers runs on it.*

`````
<!-- ripwire callers schema=ripwire.callers/v1: 1-hop CALLERS of of= (defs= matched, count= distinct symbols): <s t= n= p=>; hop_tested=/hop_untested=. counts_floor=1: every count is a FLOOR, never a total. graph_ambiguous=/graph_unresolved=: resolver gauge. graph_unindexed=N: N files no grammar could read (the map header's unindexed=); their calls raise neither gauge. root=: p= relative to it. next=: the one pasteable follow-up. -->
<callers schema="ripwire.callers/v1" of="@src/graph.h:5567" defs="1" count="7" root="." hop_tested="0" hop_untested="7" graph_ambiguous="10278" graph_unresolved="12878" graph_unindexed="237" counts_floor="1" next="--uses=@src/graph.h:5567">
<s t="fn" n="getIndex" p="src/mcpindex.h:1165"/>
<s t="fn" n="rankGraph" p="src/graph.h:5606"/>
<s t="fn" n="anchoredLexicalRank" p="src/graph.h:6252"/>
<s t="fn" n="runEval" p="src/eval.h:171"/>
<s t="fn" n="churnDecayRanking" p="src/main.cpp:1380"/>
<s t="fn" n="churnRankedGraph" p="src/main.cpp:1419"/>
<s t="fn" n="runDefaultMap" p="src/main.cpp:1629"/>
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
ripwire: the at flag's seed 'src/graph.h:999999' named no location (./src/graph.h has only 9418 lines — the seed asked for line 999999)
`````

## `./build/ripwire . --verify="calls(runDefaultMap, rankGraphTeleport)"`

*VERIFY a closed claim in one call: three-valued verdict (confirmed / refuted / not-established) with the evidence rows inline.*

`````
<!-- ripwire verify schema=ripwire.verify/v1: ONE structured claim, verdict=confirmed|refuted|unknown, its witness rows <s t= n= p=> inline. window: shown= capped= (capped=1 cut). counts_floor=1: every count is a FLOOR, never a total. graph_ambiguous=/graph_unresolved=: resolver gauge. graph_unindexed=N: N files no grammar could read (the map header's unindexed=); their calls raise neither gauge. root=: p= relative to it. claim=/shape=: the claim as given and its shape; from_defs=/to_defs=: defs each name resolved to. hops=N: call edges on the witness path (a confirmed reach claim only). -->
<verify schema="ripwire.verify/v1" claim="calls(runDefaultMap, rankGraphTeleport)" shape="calls" verdict="confirmed" from_defs="1" to_defs="1" hops="1" root="." graph_ambiguous="10278" graph_unresolved="12878" graph_unindexed="237" counts_floor="1" shown="2" capped="0">
<s t="fn" n="runDefaultMap" p="src/main.cpp:1629"/>
<s t="fn" n="rankGraphTeleport" p="src/graph.h:5565"/>
</verify>
`````

## `./build/ripwire . --verify="unused(rankGraphTeleport)"`

*A claim that is FALSE — the refuted shape, with the references that refute it.*

`````
<!-- ripwire verify schema=ripwire.verify/v1: ONE structured claim, verdict=confirmed|refuted|unknown, its witness rows <s t= n= p=> inline. window: shown= capped= (capped=1 cut). counts_floor=1: every count is a FLOOR, never a total. graph_ambiguous=/graph_unresolved=: resolver gauge. graph_unindexed=N: N files no grammar could read (the map header's unindexed=); their calls raise neither gauge. root=: p= relative to it. claim=/shape=: the claim as given and its shape; from_defs=/to_defs=: defs each name resolved to. -->
<verify schema="ripwire.verify/v1" claim="unused(rankGraphTeleport)" shape="unused" verdict="refuted" defs="1" external="0" count="9" root="." graph_ambiguous="10278" graph_unresolved="12878" graph_unindexed="237" counts_floor="1" shown="9" capped="0">
<u role="call" p="src/eval.h:325" in_id="src/eval.h::rw::runEval"/>
<u role="call" p="src/graph.h:5609" in_id="src/graph.h::rw::rankGraph"/>
<u role="call" p="src/graph.h:6303" in_id="src/graph.h::rw::anchoredLexicalRank"/>
<u role="call" p="src/main.cpp:1394" in_id="churnDecayRanking"/>
<u role="call" p="src/main.cpp:1433" in_id="churnRankedGraph"/>
<u role="call" p="src/main.cpp:1434" in_id="churnRankedGraph"/>
<u role="call" p="src/main.cpp:1448" in_id="churnRankedGraph"/>
<u role="call" p="src/main.cpp:1749" in_id="runDefaultMap"/>
<u role="call" p="src/mcpindex.h:1268" in_id="src/mcpindex.h::rw::getIndex"/>
</verify>
`````

## `./build/ripwire . --verify="contains(src/graph.h, \"no such literal anywhere\")"`

*A literal-scan absence: refuted only with complete= evidence, never on a partial scan.*

`````
<!-- ripwire verify schema=ripwire.verify/v1: ONE structured claim, verdict=confirmed|refuted|unknown, its witness rows <s t= n= p=> inline. window: shown= capped= (capped=1 cut). root=: p= relative to it. claim=/shape=: the claim as given and its shape; from_defs=/to_defs=: defs each name resolved to. -->
<verify schema="ripwire.verify/v1" claim="contains(src/graph.h, &quot;no such literal anywhere&quot;)" shape="contains" verdict="refuted" hits="0" root="." complete="1" shown="0" capped="0">
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

**wall time: 1.02s**

`````
<!-- ripwire slice schema=ripwire.slice/v1: name-based def-use rows of one variable in one definition: <s l= k=def|use|both|scope t= [b= pp= rd=]> (rd= reaching-def lines per reach=cfg|linear), <v n= l= t=> inventory; steps=/depth= flow. at=: commit+dirty+shallow. root=: p= relative to it. sym=/lang=: the sliced definition's name and language; p= is its file:line. vars=N: sliceable local bindings in the definition, one v row each; name one to slice it. counts=as-classified: defs=/uses=/vars=/steps= count what the name classifier rowed; neither floors nor totals. -->
<slice sym="rankGraphTeleport" p="src/graph.h:5565" t="fn" lang="cpp" schema="ripwire.slice/v1" vars="14" at="c7920353a" root="." counts="as-classified">
<v n="alpha" l="5565" t="param"/>
<v n="g" l="5565" t="param"/>
<v n="p" l="5565" t="param"/>
<v n="pw" l="5568" t="decl"/>
<v n="N" l="5569" t="decl"/>
<v n="teleport" l="5570" t="decl"/>
<v n="rankDouble" l="5571" t="decl"/>
<v n="run" l="5572" t="decl"/>
<v n="teleportMass" l="5575" t="decl"/>
<v n="value" l="5576" t="decl"/>
<v n="inverseMass" l="5582" t="decl"/>
<v n="value" l="5583" t="decl"/>
<v n="r" l="5590" t="decl"/>
<v n="value" l="5591" t="param"/>
</slice>
`````

## `./build/ripwire . --slice=rankGraphTeleport:teleport`

*Intra-procedural def-use slice of ONE variable: one <s> row per line touching it, k=def|use|both, reaching definitions flow-sensitive (reach=cfg).*

`````
<!-- ripwire slice schema=ripwire.slice/v1: name-based def-use rows of one variable in one definition: <s l= k=def|use|both|scope t= [b= pp= rd=]> (rd= reaching-def lines per reach=cfg|linear), <v n= l= t=> inventory; steps=/depth= flow. at=: commit+dirty+shallow. root=: p= relative to it. sym=/lang=: the sliced definition's name and language; p= is its file:line. order=defuse: seed s rows (no v=) ranked among these rows by def-use coverage (distinct local names on the line) desc, then line; not source order, not a whole-function ranking (measured at chance — docs/EVALS.md) — flow s rows (v=) keep their (d=,l=,v=) order. counts=as-classified: defs=/uses=/vars=/steps= count what the name classifier rowed; neither floors nor totals. -->
<slice sym="rankGraphTeleport" p="src/graph.h:5565" t="fn" lang="cpp" schema="ripwire.slice/v1" var="teleport" defs="1" uses="3" reach="cfg" order="defuse" at="c7920353a" root="." counts="as-classified">
<s l="5588" k="use" t="call-arg" rd="5570">
<![CDATA[run = pageRankDouble( g.inEdges, g.wOutDeg, teleport, rankDouble, PageRankConfig{ .alpha = double( alpha ) } );]]>
</s>
<s l="5570" k="def" t="decl">
<![CDATA[std::vector<double> teleport( pw.begin(), pw.end() );]]>
</s>
<s l="5576" k="use" t="read" rd="5570">
<![CDATA[for( const double value : teleport )]]>
</s>
<s l="5583" k="use" t="read" rd="5570">
<![CDATA[for( double& value : teleport )]]>
</s>
</slice>
`````

## `./build/ripwire . --slice=rankGraphTeleport:teleport --slice-flow=back --slice-depth=3`

*TRANSITIVE backward value-flow from the seed variable, bounded BFS (depth= disclosed; a cut frontier says flow_truncated=1).*

**wall time: 1.04s**

`````
<!-- ripwire slice schema=ripwire.slice/v1: name-based def-use rows of one variable in one definition: <s l= k=def|use|both|scope t= [b= pp= rd=]> (rd= reaching-def lines per reach=cfg|linear), <v n= l= t=> inventory; steps=/depth= flow. at=: commit+dirty+shallow. root=: p= relative to it. sym=/lang=: the sliced definition's name and language; p= is its file:line. order=defuse: seed s rows (no v=) ranked among these rows by def-use coverage (distinct local names on the line) desc, then line; not source order, not a whole-function ranking (measured at chance — docs/EVALS.md) — flow s rows (v=) keep their (d=,l=,v=) order. counts=as-classified: defs=/uses=/vars=/steps= count what the name classifier rowed; neither floors nor totals. -->
<slice sym="rankGraphTeleport" p="src/graph.h:5565" t="fn" lang="cpp" schema="ripwire.slice/v1" var="teleport" defs="1" uses="3" reach="cfg" flow="back" depth="3" steps="3" order="defuse" at="c7920353a" root="." counts="as-classified">
<s l="5588" k="use" t="call-arg" rd="5570">
<![CDATA[run = pageRankDouble( g.inEdges, g.wOutDeg, teleport, rankDouble, PageRankConfig{ .alpha = double( alpha ) } );]]>
</s>
<s l="5570" k="def" t="decl">
<![CDATA[std::vector<double> teleport( pw.begin(), pw.end() );]]>
</s>
<s l="5576" k="use" t="read" rd="5570">
<![CDATA[for( const double value : teleport )]]>
</s>
<s l="5583" k="use" t="read" rd="5570">
<![CDATA[for( double& value : teleport )]]>
</s>
<s l="5568" k="def" t="decl" v="pw" d="1" f="5570">
<![CDATA[const std::vector<float> pw = biasPrior( g, p );]]>
</s>
<s l="5565" k="def" t="param" v="g" d="2" f="5568">
<![CDATA[inline RankedGraph rankGraphTeleport( const Graph& g, const std::vector<float>& p, float alpha = 0.85f )]]>
</s>
<s l="5565" k="def" t="param" v="p" d="2" f="5568">
<![CDATA[inline RankedGraph rankGraphTeleport( const Graph& g, const std::vector<float>& p, float alpha = 0.85f )]]>
</s>
</slice>
`````

## `./build/ripwire . --slice=rankGraphTeleport:teleport --slice-flow=fwd`

*Forward flow: which statements the seed's value reaches, at the default depth bound.*

`````
<!-- ripwire slice schema=ripwire.slice/v1: name-based def-use rows of one variable in one definition: <s l= k=def|use|both|scope t= [b= pp= rd=]> (rd= reaching-def lines per reach=cfg|linear), <v n= l= t=> inventory; steps=/depth= flow. at=: commit+dirty+shallow. root=: p= relative to it. sym=/lang=: the sliced definition's name and language; p= is its file:line. order=defuse: seed s rows (no v=) ranked among these rows by def-use coverage (distinct local names on the line) desc, then line; not source order, not a whole-function ranking (measured at chance — docs/EVALS.md) — flow s rows (v=) keep their (d=,l=,v=) order. counts=as-classified: defs=/uses=/vars=/steps= count what the name classifier rowed; neither floors nor totals. -->
<slice sym="rankGraphTeleport" p="src/graph.h:5565" t="fn" lang="cpp" schema="ripwire.slice/v1" var="teleport" defs="1" uses="3" reach="cfg" flow="fwd" depth="8" steps="7" order="defuse" at="c7920353a" root="." counts="as-classified">
<s l="5588" k="use" t="call-arg" rd="5570">
<![CDATA[run = pageRankDouble( g.inEdges, g.wOutDeg, teleport, rankDouble, PageRankConfig{ .alpha = double( alpha ) } );]]>
</s>
<s l="5570" k="def" t="decl">
<![CDATA[std::vector<double> teleport( pw.begin(), pw.end() );]]>
</s>
<s l="5576" k="use" t="read" rd="5570">
<![CDATA[for( const double value : teleport )]]>
</s>
<s l="5583" k="use" t="read" rd="5570">
<![CDATA[for( double& value : teleport )]]>
</s>
<s l="5578" k="use" t="read" v="value" d="2" f="5576" b="5576">
<![CDATA[teleportMass += value;]]>
</s>
<s l="5585" k="both" t="assign" v="value" d="2" f="5583" b="5583">
<![CDATA[value *= inverseMass;]]>
</s>
<s l="5592" k="use" t="read" v="run" d="2" f="5588">
<![CDATA[return { std::move( r ), run.iterationCount, run.hasConverged };]]>
</s>
<s l="5578" k="both" t="assign" v="teleportMass" d="3" f="5578">
<![CDATA[teleportMass += value;]]>
</s>
<s l="5580" k="use" t="read" v="teleportMass" d="3" f="5578">
<![CDATA[if( teleportMass > 0.0 )]]>
</s>
<s l="5582" k="use" t="read" v="teleportMass" d="3" f="5578">
<![CDATA[const double inverseMass = 1.0 / teleportMass;]]>
</s>
<s l="5585" k="use" t="read" v="inverseMass" d="4" f="5582">
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
<!-- ripwire slice schema=ripwire.slice/v1: name-based def-use rows of one variable in one definition: <s l= k=def|use|both|scope t= [b= pp= rd=]> (rd= reaching-def lines per reach=cfg|linear), <v n= l= t=> inventory; steps=/depth= flow. at=: commit+dirty+shallow. root=: p= relative to it. sym=/lang=: the sliced definition's name and language; p= is its file:line. order=defuse: seed s rows (no v=) ranked among these rows by def-use coverage (distinct local names on the line) desc, then line; not source order, not a whole-function ranking (measured at chance — docs/EVALS.md) — flow s rows (v=) keep their (d=,l=,v=) order. counts=as-classified: defs=/uses=/vars=/steps= count what the name classifier rowed; neither floors nor totals. -->
<slice sym="rankGraphTeleport" p="src/graph.h:5565" t="fn" lang="cpp" schema="ripwire.slice/v1" var="teleport" defs="1" uses="3" reach="cfg" order="defuse" at="c7920353a" root="." counts="as-classified">
<s l="5588" k="use" t="call-arg" rd="5570">
<![CDATA[run = pageRankDouble( g.inEdges, g.wOutDeg, teleport, rankDouble, PageRankConfig{ .alpha = double( alpha ) } );]]>
</s>
<s l="5570" k="def" t="decl">
<![CDATA[std::vector<double> teleport( pw.begin(), pw.end() );]]>
</s>
<s l="5576" k="use" t="read" rd="5570">
<![CDATA[for( const double value : teleport )]]>
</s>
<s l="5583" k="use" t="read" rd="5570">
<![CDATA[for( double& value : teleport )]]>
</s>
</slice>
`````

## `./build/ripwire . --pattern='rankGraphTeleport($A, $B, $C)'`

*Structural search written in CODE: $NAME binds one node; grammars=/shapes= disclose what the pattern became per grammar (a 3-argument call shape — the 2-argument spelling has no call site in this repo and correctly reports hits=0).*

**wall time: 1.82s**

`````
<!-- ripwire pattern schema=ripwire.pattern/v1: structural pattern hits with their enclosing symbol. window: shown= capped= (capped=1 cut). hits_capped=1: hits= is a floor. root=: p= relative to it. -->
<pattern schema="ripwire.pattern/v1" hits="1" shown="1" capped="0" hits_capped="0" q="rankGraphTeleport($A, $B, $C)" grammars="cpp,cpp/cu,c,python,go,rust,typescript,tsx,swift,objc,javascript,java,csharp" shapes="cpp:call_expression,cpp/cu:call_expression,c:call_expression,python:call,go:call_expres … [line truncated: 309 more bytes on this line]
<m p="src/graph.h:5609" in="rankGraph">rankGraphTeleport( g, std::vector&lt;float&gt;( N, N ? 1.0f / float( N ) : 0.f ), alpha )</m>
</pattern>
`````

## `./build/ripwire . --pattern='DISCLOSE(...)'`

*The ellipsis form over a macro-shaped call site; unsupported= names the families this verb does not serve.*

**wall time: 1.67s**

`````
<!-- ripwire pattern schema=ripwire.pattern/v1: structural pattern hits with their enclosing symbol. window: shown= total= capped= has_more= next_offset= offset= limit= (capped=1 cut; next_offset= pastes as offset=). ellipsis_capped=: 1 = cut. hits_capped=1: hits= is a floor. root=: p= relative to it. -->
<pattern schema="ripwire.pattern/v1" hits="263" shown="100" capped="1" total="263" has_more="1" next_offset="100" offset="0" limit="0" hits_capped="0" q="DISCLOSE(...)" grammars="cpp,cpp/cu,c,python,go,rust,typescript,tsx,swift,objc,javascript,java,csharp" shapes="cpp:call_expression,cpp/cu:call_exp … [line truncated: 446 more bytes on this line]
<m p="src/abicheck.h:493" in="collectAuthoredSites">DISCLOSE( result, AbiResult::DisclosureWhy::NoMergeBase, "abi: no merge-base for a ref (unrelated history?) — that ref</m>
<m p="src/arch.h:505" in="parseArchRules">DISCLOSE( Diagnostics::answerRefused, "--arch exits 1 with path:line and the reason on stderr; no report is printed",   </m>
<m p="src/arch.h:844" in="readArchBaselineSidecar">DISCLOSE( baseline, ArchBaselineRead::DisclosureWhy::SymlinkRefused, "arch: refusing to read the arch baseline sidecar t</m>
<m p="src/arch.h:895" in="openArchBaselineSidecar">DISCLOSE( Diagnostics::answerRefused, "--baseline exits 1: pathguard names the refused link on stderr and the verb says </m>
<m p="src/atoms.h:372" in="collectExclusions">DISCLOSE( ex, Exclusions::DisclosureWhy::ForHeaderSaturated, "atoms: the for-header exclusion stream spent its whole bud</m>
<m p="src/atoms.h:376" in="collectExclusions">DISCLOSE( ex, Exclusions::DisclosureWhy::StmtCrementSaturated, "atoms: the statement-crement exclusion stream spent its </m>
<m p="src/atoms.h:380" in="collectExclusions">DISCLOSE( ex, Exclusions::DisclosureWhy::StmtAssignSaturated, "atoms: the statement-assign exclusion stream spent its wh</m>
<m p="src/atoms.h:384" in="collectExclusions">DISCLOSE( ex, Exclusions::DisclosureWhy::InnerCommaSaturated, "atoms: the inner-comma exclusion stream spent its whole b</m>
<m p="src/clones.h:909" in="findClonesType3">DISCLOSE( st, Type3Stats::DisclosureWhy::PairCapHit, "clones: Type-3 pair cap hit — first N compared (both-gate-surviv</m>
<m p="src/commentcoherence.h:216" in="computeCommentCoherence">DISCLOSE( scan, CommentCoherenceScan::DisclosureWhy::UnreadableFile, "comment-coherence: an indexed file could not be re</m>
<m p="src/crossref.h:527" in="streamBlobs">DISCLOSE( st, StreamBlobStats::DisclosureWhy::ListUnwritable, "crossref: cannot write the blob-batch list — cross-bran</m>
<m p="src/crossref.h:543" in="streamBlobs">DISCLOSE( st, StreamBlobStats::DisclosureWhy::BatchNotStarted, "crossref: git cat-file --batch failed to start — cross</m>
<m p="src/crossref.h:604" in="streamBlobs">DISCLOSE( st, StreamBlobStats::DisclosureWhy::StreamEndedMidBlob,                       "crossref: git cat-file stream e</m>
<m p="src/crossref.h:793" in="enumerateRefs">DISCLOSE( dropSink, RefEnumeration::DisclosureWhy::TipNotObjectName, "crossref: for-each-ref yielded a ref whose tip is </m>
<m p="src/crossref.h:825" in="diffRaw">DISCLOSE( "crossref: refusing a diff whose revision arguments are not resolved object names" )</m>
<m p="src/crossref.h:928" in="parallelIndexed">DISCLOSE( sweep, ParallelSweep::DisclosureWhy::WorkerThrew, "crossref: a git worker threw — this shard of the sweep is</m>
<m p="src/crossref.h:1155" in="probeRefBase">DISCLOSE( plumb, RefPlumbing::DisclosureWhy::RevisionNotObjectName, "crossref: ref tip or HEAD is not a resolved object </m>
<m p="src/crossref.h:1166" in="probeRefBase">DISCLOSE( plumb, RefPlumbing::DisclosureWhy::MergeBaseNotObjectName, "crossref: merge-base returned something that is no</m>
<m p="src/crossref.h:1173" in="probeRefBase">DISCLOSE( plumb, RefPlumbing::DisclosureWhy::NoMergeBase, "crossref: no merge-base for ref (shallow clone or unrelated h</m>
<m p="src/crossref.h:1701" in="lsTree">DISCLOSE( "crossref: refusing to list a tree whose revision argument is not a resolved object name" )</m>
<m p="src/crossref.h:1785" in="relabelHeadHitsFromIndex">DISCLOSE( "whereis: the index's def sites match no HEAD row (working tree drifted from HEAD?) — keeping the lexical la</m>
<m p="src/crossref.h:1963" in="scanWorktree">DISCLOSE( scan, WorktreeScan::DisclosureWhy::ListingFailed, "whereis: git could not list the working tree's changes — </m>
<m p="src/crossref.h:1973" in="scanWorktree">DISCLOSE( scan, WorktreeScan::DisclosureWhy::OverPathCap, "whereis: more changed paths than the overlay reads — the re</m>
<m p="src/crossref.h:1984" in="scanWorktree">DISCLOSE( scan, WorktreeScan::DisclosureWhy::CopyUnread, "whereis: a changed path could not be read from the working tre</m>
<m p="src/darkflags.h:968" in="collectCMakeFiles">DISCLOSE( out, CMakeScan::DisclosureWhy::SymlinkEscapesRoot, "flags: a CMake file's symlink target leaves the root — f</m>
<m p="src/darkflags.h:976" in="collectCMakeFiles">DISCLOSE( out, CMakeScan::DisclosureWhy::RootWalkFailed, "flags: cannot walk root for CMake files — cmake gates omitte</m>
<m p="src/dmm.h:349" in="computeDmm">DISCLOSE( r, Result::DisclosureWhy::BaseTreeUnavailable, "dmm: the base commit's tree could not be materialized or parse</m>
<m p="src/dmm.h:363" in="computeDmm">DISCLOSE( r, Result::DisclosureWhy::TargetTreeUnavailable, "dmm: the target commit's tree could not be materialized or p</m>
… [73 more display lines; full output is 17739 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --pattern='x'`

*A pattern that collapses to a bare token is REFUSED — never reported as hits=0.*

**exit code: 1**

`````
(empty)
`````

stderr:

`````
ripwire: --pattern: this pattern collapses to a single bare token, which is a TEXT search, not a structural one — a clean parse is not enough (a bare word parses fine in most grammars and means nothing structural). Give it a shape (foo($X), $A + $B, if ($C) { ... }) or use the grep flag for litera … [line truncated: 176 more bytes on this line]
`````

## `./build/ripwire . --grep=DISCLOSE --and=cache`

*Boolean grep: hits where BOTH literals share the matched line (--grep-scope=line is the default).*

`````
<!-- ripwire grep schema=ripwire.grep/v1: literal/regex scan grouped by file: <f p=>
<hit l= in=>CDATA text</hit> (<b>/<a> context around it); complete=1 only for an exhaustive literal scan; <unindexed> = off-index. window: shown= capped= (capped=1 cut). hits_capped=1: hits= is a floor. root=: p= relative to it. parse_degraded=1: ERROR nodes in that parse. next=: the one pasteable f … [line truncated: 1338 more bytes on this line]
<grep pattern="DISCLOSE" schema="ripwire.grep/v1" root="." terms="DISCLOSE +cache" scope="line" terms_suppressed="961" files="9" hits="28" shown="28" capped="0" hits_capped="0" suppressed_comment="2" suppressed_string="8" tier_parsed="13" tier_unclassified="0" corpus_oversize="15" corpus_pruned_dirs … [line truncated: 118 more bytes on this line]
<f p="src/ingest_cache.h">
<hit l="1823" in="openCacheFrame" n="5">
<![CDATA[            DISCLOSE( Diagnostics::answerUnchanged, "a rejected cache is rebuilt from source: this run parses and answers byte-identically",]]>
<at l="1831" in="openCacheFrame"/>
<at l="1839" in="openCacheFrame"/>
<at l="1911" in="openCacheFrame"/>
<at l="2006" in="ByteR::fitsBelow"/>
</hit>
<hit l="1871" in="openCacheFrame" n="3">
<![CDATA[        DISCLOSE( Diagnostics::answerUnchanged, "a rejected cache is rebuilt from source: this run parses and answers byte-identically",]]>
<at l="1889" in="openCacheFrame"/>
<at l="2330" in="readFileRecord"/>
</hit>
<hit l="2368" in="readFileRecord">
<![CDATA[                DISCLOSE( Diagnostics::answerUnchanged, "a rejected cache is rebuilt from source: this run parses and answers byte-identically",]]>
</hit>
<hit l="3147" in="saveCache">
<![CDATA[        DISCLOSE( Diagnostics::answerUnchanged, "this answer is already computed in memory: only the next run starts cold", "ingest: saveCache rename(tmp -> cache) failed — old cache preserved" );]]>
</hit>
</f>
<f p="src/ingest_crawl.h" parse_degraded="1">
<hit l="1954" in="isReadableCacheBlob">
<![CDATA[        DISCLOSE( Diagnostics::answerUnchanged, "a rejected cache is rebuilt from source: this run parses and answers byte-identically",]]>
</hit>
</f>
<f p="src/ingest_docpass.h">
<hit l="34" in="rw::publishDocBridgeBlob" n="3">
… [110 more display lines; full output is 10449 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --grep=DISCLOSE --not=test --grep-scope=file`

*Drop every hit in a file that ALSO contains the --not literal anywhere (file scope).*

`````
<!-- ripwire grep schema=ripwire.grep/v1: literal/regex scan grouped by file: <f p=>
<hit l= in=>CDATA text</hit> (<b>/<a> context around it); complete=1 only for an exhaustive literal scan; <unindexed> = off-index. window: shown= capped= (capped=1 cut). hits_capped=1: hits= is a floor. root=: p= relative to it. parse_degraded=1: ERROR nodes in that parse. next=: the one pasteable f … [line truncated: 1241 more bytes on this line]
<grep pattern="DISCLOSE" schema="ripwire.grep/v1" root="." terms="DISCLOSE -test" scope="file" terms_suppressed="961" files="4" hits="11" shown="11" capped="0" hits_capped="0" suppressed_comment="27" tier_parsed="19" tier_unclassified="0" corpus_oversize="15" corpus_pruned_dirs="8" unindexed_hits="8 … [line truncated: 99 more bytes on this line]
<f p="src/commentcoherence.h" parse_degraded="1">
<hit l="216" in="rw::computeCommentCoherence">
<![CDATA[                DISCLOSE( scan, CommentCoherenceScan::DisclosureWhy::UnreadableFile, "comment-coherence: an indexed file could not be read — its functions are absent from the report" );]]>
</hit>
</f>
<f p="src/ingest_docpass.h">
<hit l="34" in="rw::publishDocBridgeBlob" n="3">
<![CDATA[        DISCLOSE( Diagnostics::answerUnchanged, "the doc text is kept for this run: only the bridge cache is not written",]]>
<at l="42" in="rw::publishDocBridgeBlob"/>
<at l="48" in="rw::publishDocBridgeBlob"/>
</hit>
<hit l="174" in="runDocPostPass">
<![CDATA[                        DISCLOSE( "ingest: doc post-pass worker exception on a file — skipped" );]]>
</hit>
</f>
<f p="src/ingest_prewarm.h">
<hit l="213" in="refuseNesting">
<![CDATA[            DISCLOSE( refusal, NestRefusal::DisclosureWhy::JsonNesting,]]>
</hit>
<hit l="225" in="refuseNesting">
<![CDATA[            DISCLOSE( refusal, NestRefusal::DisclosureWhy::YamlNesting,]]>
</hit>
<hit l="237" in="refuseNesting">
<![CDATA[            DISCLOSE( refusal, NestRefusal::DisclosureWhy::MarkdownBlockNesting,]]>
</hit>
<hit l="249" in="refuseNesting">
<![CDATA[            DISCLOSE( refusal, NestRefusal::DisclosureWhy::KotlinStringTemplates,]]>
… [53 more display lines; full output is 6081 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --grep=DISCLOSE --grep=cache`

*A second --grep= REFUSES and names --and= as the AND spelling — no silent overwrite.*

**exit code: 1**

`````
(empty)
`````

stderr:

`````
ripwire: --grep given twice; did you mean --grep='A' --and='B'?
`````

## `./build/ripwire . --grep=DISCLOSE --grep-in=any`

*Span tiers off: the exhaustive view — the comment and string hits the default tier held back (suppressed_comment=96 / suppressed_string=29 in the plain --grep block above) now print alongside the code hits; hits= grows accordingly.*

**wall time: 1.03s**

`````
<!-- ripwire grep schema=ripwire.grep/v1: literal/regex scan grouped by file: <f p=>
<hit l= in=>CDATA text</hit> (<b>/<a> context around it); complete=1 only for an exhaustive literal scan; <unindexed> = off-index. window: shown= total= capped= has_more= next_offset= offset= limit= (capped=1 cut; next_offset= pastes as offset=). hits_capped=1: hits= is a floor. root=: p= relative t … [line truncated: 1024 more bytes on this line]
<grep pattern="DISCLOSE" schema="ripwire.grep/v1" root="." files="266" hits="999" shown="100" capped="1" total="999" has_more="1" next_offset="100" offset="0" limit="0" hits_capped="0" corpus_oversize="15" corpus_pruned_dirs="8" unindexed_hits="8" unindexed_files_scanned="236" unindexed_files_skippe … [line truncated: 59 more bytes on this line]
<f p=".coderabbit.yaml">
<hit l="30" in="path_instructions" n="2">
<![CDATA[        A degrade path uses DISCLOSE( sink, why ), never ASSUME(false): a one-argument DISCLOSE( msg ) is a debug trace]]>
<at l="30" in="path_instructions"/>
</hit>
</f>
<f p=".github/workflows/ci.yml">
<hit l="243" in="release">
<![CDATA[    #   Release — defines NDEBUG, which compiles the DISCLOSE( msg ) trace out; the optimizer-visible build.]]>
</hit>
<hit l="244" in="release">
<![CDATA[    #   plain   — NDEBUG off, so the DISCLOSE( msg ) trace compiles in and the degrade-path gates can observe]]>
</hit>
</f>
<f p="docs/limits_build.py">
<hit l="3">
<![CDATA[# whether the file it lives in DISCLOSES a truncation when it fires.]]>
</hit>
</f>
<f p="scripts/optremarks.py">
<hit l="138" in="COLD_FILES">
<![CDATA[      "the ASSUME / DISCLOSE handlers. They run on a degrade path: once, after something has already gone wrong." ),]]>
</hit>
</f>
<f p="src/abicheck.h" parse_degraded="1">
<hit l="111">
<![CDATA[#include "infra/Diagnostics.h"  // ASSUME / DISCLOSE]]>
… [413 more display lines; full output is 25005 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --grep=deterministic`

*A literal whose classified hits are all prose: the answer serves tier="comment+string" rather than an empty code tier, and tier_unclassified= says how many hits the fixed parse budget never classified.*

`````
<!-- ripwire grep schema=ripwire.grep/v1: literal/regex scan grouped by file: <f p=>
<hit l= in=>CDATA text</hit> (<b>/<a> context around it); complete=1 only for an exhaustive literal scan; <unindexed> = off-index. window: shown= total= capped= has_more= next_offset= offset= limit= (capped=1 cut; next_offset= pastes as offset=). counts_floor=1: every count is a FLOOR, never a total … [line truncated: 1701 more bytes on this line]
<grep pattern="deterministic" schema="ripwire.grep/v1" root="." files="513" hits="1345" shown="100" capped="1" total="1345" has_more="1" next_offset="100" offset="0" limit="0" hits_capped="0" suppressed_comment="317" tier="code+string" tier_partial="1" tier_parsed="90" tier_unclassified="1318" tier_ … [line truncated: 230 more bytes on this line]
<f p=".github/workflows/ci.yml">
<hit l="842" in="windows">
<![CDATA[          # on the machine is not one deterministic build step (G3). Read it back rather than assume it took.]]>
</hit>
<hit l="879" in="windows">
<![CDATA[          # 951-byte legend plus one bare <r>, is deterministic across two runs, and parses as well-formed]]>
</hit>
</f>
<f p="present/deck5_ripwire_build.js">
<hit l="124">
<![CDATA[  s.addText("A zero-runtime-dependency C++23 CLI that maps any codebase into a ranked, deterministic call graph for coding agents — and puts a tripwire on every claim it emits.",]]>
</hit>
<hit l="362">
<![CDATA[    ["Kotlin", "by @xCatG: calls resolve between Kotlin and Java, both ways; no sanitizer finding across 501 real .kt files, deterministic on ~9,500 more (#126)", CYAN],]]>
</hit>
<hit l="388" line_bytes="574">
<![CDATA[    "- Kotlin — merged: #126, merge commit 1ad9184a (2026-09-11); PR body, PR author xCatG: “vendored fwcd/tree-sitter-kotlin grammar … a JVM interop bridge that resolves Kotlin↔Java calls bidirectionally”; “Zero ASan/UBSan/LSan findings across 501 real .kt files (8 local Androi … [line truncated: 224 more bytes on this line]
</hit>
<hit l="458" line_bytes="532">
<![CDATA[    "FOOTER (the instruments). From the release notes' Highlights: 'Three readouts, all registered before the work began, and none of them a model's opinion. A frozen bank of 30 retrieval questions, each answered in ONE call on a 2,066-file C++ corpus pinned at one commit, scored on the gol … [line truncated: 224 more bytes on this line]
</hit>
<hit l="1051">
<![CDATA[    ["parallel parse", "query compile overlaps parse scheduling; files schedule by size — ids stay deterministic"],]]>
</hit>
<hit l="1386">
<![CDATA[  foot(s, "the MCP server exposes the same deterministic engine — one index, shared with the CLI, staleness-checked");]]>
</hit>
… [670 more display lines; full output is 39761 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --grep=DISCLOSE --handles`

*h= on each editable enclosing-symbol row: a freshness-pinned identity an edit verb can target and must refuse on after any file change.*

`````
<!-- ripwire grep schema=ripwire.grep/v1: literal/regex scan grouped by file: <f p=>
<hit l= in=>CDATA text</hit> (<b>/<a> context around it); complete=1 only for an exhaustive literal scan; <unindexed> = off-index. window: shown= total= capped= has_more= next_offset= offset= limit= (capped=1 cut; next_offset= pastes as offset=). counts_floor=1: every count is a FLOOR, never a total … [line truncated: 1666 more bytes on this line]
<grep pattern="DISCLOSE" schema="ripwire.grep/v1" root="." files="240" hits="793" shown="100" capped="1" total="793" has_more="1" next_offset="100" offset="0" limit="0" hits_capped="0" suppressed_comment="201" suppressed_string="5" tier_parsed="82" tier_unclassified="538" tier_budget="bytes" tier_fi … [line truncated: 201 more bytes on this line]
<f p=".coderabbit.yaml">
<hit l="30" in="path_instructions" n="2">
<![CDATA[        A degrade path uses DISCLOSE( sink, why ), never ASSUME(false): a one-argument DISCLOSE( msg ) is a debug trace]]>
<at l="30" in="path_instructions"/>
</hit>
</f>
<f p="src/abicheck.h" parse_degraded="1">
<hit l="493" in="abicheck::collectAuthoredSites">
<![CDATA[            DISCLOSE( result, AbiResult::DisclosureWhy::NoMergeBase, "abi: no merge-base for a ref (unrelated history?) — that ref is counted, not compared" );]]>
</hit>
</f>
<f p="src/arch.h">
<hit l="505" in="rw::parseArchRules">
<![CDATA[        DISCLOSE( Diagnostics::answerRefused, "--arch exits 1 with path:line and the reason on stderr; no report is printed",]]>
</hit>
<hit l="844" in="rw::readArchBaselineSidecar">
<![CDATA[    if( sidecar.refused ) { DISCLOSE( baseline, ArchBaselineRead::DisclosureWhy::SymlinkRefused, "arch: refusing to read the arch baseline sidecar through a symlink" ); }]]>
</hit>
<hit l="895" in="rw::openArchBaselineSidecar">
<![CDATA[        DISCLOSE( Diagnostics::answerRefused, "--baseline exits 1: pathguard names the refused link on stderr and the verb says it cannot write the sidecar",]]>
</hit>
</f>
<f p="src/atoms.h">
<hit l="372" in="atomdetail::collectExclusions">
<![CDATA[        DISCLOSE( ex, Exclusions::DisclosureWhy::ForHeaderSaturated, "atoms: the for-header exclusion stream spent its whole budget; the rules reading it are suppressed this run" );]]>
</hit>
<hit l="376" in="atomdetail::collectExclusions">
… [393 more display lines; full output is 28250 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --grep=DISCLOSE --legend=compact`

*The grep compact legend (ripwire.grep/v1).*

`````
<!-- ripwire grep schema=ripwire.grep/v1: literal/regex scan grouped by file: <f p=>
<hit l= in=>CDATA text</hit> (<b>/<a> context around it); complete=1 only for an exhaustive literal scan; <unindexed> = off-index. window: shown= total= capped= has_more= next_offset= offset= limit= (capped=1 cut; next_offset= pastes as offset=). counts_floor=1: every count is a FLOOR, never a total … [line truncated: 1666 more bytes on this line]
<grep pattern="DISCLOSE" schema="ripwire.grep/v1" root="." files="240" hits="793" shown="100" capped="1" total="793" has_more="1" next_offset="100" offset="0" limit="0" hits_capped="0" suppressed_comment="201" suppressed_string="5" tier_parsed="82" tier_unclassified="538" tier_budget="bytes" tier_fi … [line truncated: 201 more bytes on this line]
<f p=".coderabbit.yaml">
<hit l="30" in="path_instructions" n="2">
<![CDATA[        A degrade path uses DISCLOSE( sink, why ), never ASSUME(false): a one-argument DISCLOSE( msg ) is a debug trace]]>
<at l="30" in="path_instructions"/>
</hit>
</f>
<f p="src/abicheck.h" parse_degraded="1">
<hit l="493" in="abicheck::collectAuthoredSites">
<![CDATA[            DISCLOSE( result, AbiResult::DisclosureWhy::NoMergeBase, "abi: no merge-base for a ref (unrelated history?) — that ref is counted, not compared" );]]>
</hit>
</f>
<f p="src/arch.h">
<hit l="505" in="rw::parseArchRules">
<![CDATA[        DISCLOSE( Diagnostics::answerRefused, "--arch exits 1 with path:line and the reason on stderr; no report is printed",]]>
</hit>
<hit l="844" in="rw::readArchBaselineSidecar">
<![CDATA[    if( sidecar.refused ) { DISCLOSE( baseline, ArchBaselineRead::DisclosureWhy::SymlinkRefused, "arch: refusing to read the arch baseline sidecar through a symlink" ); }]]>
</hit>
<hit l="895" in="rw::openArchBaselineSidecar">
<![CDATA[        DISCLOSE( Diagnostics::answerRefused, "--baseline exits 1: pathguard names the refused link on stderr and the verb says it cannot write the sidecar",]]>
</hit>
</f>
<f p="src/atoms.h">
<hit l="372" in="atomdetail::collectExclusions">
<![CDATA[        DISCLOSE( ex, Exclusions::DisclosureWhy::ForHeaderSaturated, "atoms: the for-header exclusion stream spent its whole budget; the rules reading it are suppressed this run" );]]>
</hit>
<hit l="376" in="atomdetail::collectExclusions">
… [393 more display lines; full output is 25803 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --for="tree-sitter parse of a source file" --legend=compact`

*The --for compact legend (ripwire.for/v1) — every data/completeness attribute kept.*

`````
<ctx task="tree-sitter parse of a source file" route="subtoken+body" root="." confidence="low" margin_pct="0" at="c7920353a" doc_mentions="3" schema="ripwire.for/v1" bundle="compact" bodies="0" reason="compact-route" budget_bytes="7500" est_tokens="3536">
<!-- ripwire for schema=ripwire.for/v1: bundle=/bodies=/reason= the body posture; d: cx= ccx= complexity, in= callers (absent cx/ccx/in = 0), churn= amp= change, clone= tested= 1, sc= scope, id=p::sc::n; total= shown= capped=1 if cut; task= the query; d pure=1 const/constexpr sig, next= the follow-up to paste; route= name-exact(X)|subtoken+body[:broad|:declined]; confidence=/margin_pct= head score drop (low=flat); h l= p= n=, c n= l= (joined for same-named callees, shown= counts them), noedge= no callee resolved; t p= file outside sigs (weaker), r= rank (gap = trimmed); field name= type= owner= rel=: a member of owner=, rel=creates held by value, uses by reference/pointer; iface implementors=N: types implementing it, m= its method contract; d layer=: built-in arch layer (game|infra|render|math|audio|ai|test) from a dir name in p= [doc mentions: 3 docs, 2 symbols; doc_mentions=] -->
<!-- root= is the crawl root; p= below is RELATIVE to it (single-root only; absent => p= is ingest's own path, unchanged); at=this commit(+dirty). dropped_positive="11" [budget_bytes= is the default BYTE ceiling this ranked payload was shaped against; it bounds that payload, not the whole document est_tokens prices] [docs_dropped=N: N shown rows have a doc comment not printed (r>24 always, r5..24 if capped)]; lego/compose collapse to a counted stub by default (a disclosed cut): total= that section's own pre-cap row count, shown="0" capped="1" (nothing rendered here), next= names the sections=lego,compose flag that restores both sections byte-identically in one call est_tokens= prices this bundle in tokens -->
<sigs shown="29" total="40" capped="1" docs_dropped="23">
<d l="28" n="topLevelEvidence" sc="rw::pythonrunner" p="src/pythonrunner.h" cx="4" ccx="3" in="2" churn="5" amp="15" r="1" next="--expand=src/pythonrunner.h:topLevelEvidence">inline bool topLevelEvidence( std::string_view source, const TSLanguage* language, const Predicate&amp; predicate )</d>
<d l="45" n="kDefaultMaxFileBytes" sc="rw" p="src/ingest.h" churn="57" amp="162" pure="1" r="2">
<doc>The crawl&apos;s per-file byte ceiling. A text file larger than this is skipped: at this size it is o…</doc>constexpr std::size_t kDefaultMaxFileBytes = 4u * 1024u * 1024u</d>
<d l="1153" n="parseTree" p="src/ingest_sidecap.h" cx="1" in="2" churn="81" amp="217" tested="1" r="3">TSTree* parseTree( TSParser* parser, std::string_view src )</d>
<d l="588" n="doctorProbeGrammars" p="src/verbs_doctor.h" cx="7" ccx="17" in="1" churn="43" amp="127" r="4">
<doc>Exercise every registered grammar and its embedded query, reporting loaded and expected totals</doc>inline DoctorGrammarProbe doctorProbeGrammars()</d>
<d l="1233" n="FileHealth" sc="FileHealth" p="src/model.h" churn="136" amp="315" r="5">struct FileHealth</d>
<d l="456" n="AstWalk" sc="rw" p="src/ingest.h" churn="57" amp="162" r="6">enum class AstWalk : std::uint8_t</d>
<d l="369" n="sliceAtRev" sc="slicediff" p="src/slicediff.h" cx="13" ccx="13" in="1" churn="11" amp="61" r="7">inline RevSide sliceAtRev( const std::string&amp; root, const std::string&amp; sha, const std::string&amp; rel, const Symbol&amp; sym, SliceFam fam, const ::TSLanguage* grammar…</d>
<d l="308" n="SliceScan" sc="SliceScan" p="src/slice.h" churn="51" amp="102" r="8">struct SliceScan</d>
<d l="1222" n="astroFenceTailIsBlank" p="src/ingest_sidecap.h" cx="1" in="2" churn="81" amp="217" tested="1" r="9">inline bool astroFenceTailIsBlank( std::string_view src, std::size_t from, std::size_t to ) noexcept</d>
<d l="96" n="kLangTable" p="src/ingest_crawl.h" churn="66" amp="191" pure="1" r="10">constexpr std::array&lt;LangEntry, 51&gt; kLangTable =</d>
<d l="134" n="kMaxKotlinStringNestDepth" sc="rw" p="src/ingest.h" churn="57" amp="162" pure="1" r="11">constexpr std::uint32_t kMaxKotlinStringNestDepth = 128u</d>
<d l="255" n="hasPhantomScopeSeparator" p="src/ingest_names.h" cx="2" ccx="1" in="2" churn="43" amp="143" tested="1" r="12">inline bool hasPhantomScopeSeparator( TSNode qualified ) noexcept</d>
<d l="2115" n="collectGatedLocalNames" sc="rw" p="src/ingest_astquery.h" cx="6" ccx="5" in="1" churn="41" amp="134" r="13">std::vector&lt;LocalNameFact&gt; collectGatedLocalNames( std::string_view defBytes, std::uint32_t defStartLine, Lang lang )</d>
<d l="881" n="scanModule" sc="detail" p="src/jsrunner.h" cx="16" ccx="15" in="3" churn="17" amp="81" r="14">inline ModuleScan scanModule( std::string_view source, std::string_view path )</d>
<d l="708" n="builtInLintCaptures" p="src/verbs_lint.h" cx="1" in="1" churn="30" amp="118" r="15">std::vector&lt;std::vector&lt;rw::AstMatch&gt;&gt; builtInLintCaptures( const rw::IngestResult&amp; ing, const std::vector&lt;rw::AstQuerySpec&gt;&amp; checks, std::vector&lt;std::string&gt;&amp; keptBy … [line truncated: 9 more bytes on this line]
<d l="683" n="jsonNestsTooDeep" p="src/ingest_crawl.h" cx="13" ccx="20" in="1" churn="66" amp="192" tested="1" r="16">bool jsonNestsTooDeep( std::string_view bytes ) noexcept</d>
<d l="104" n="kMaxYamlNestDepth" sc="rw" p="src/ingest.h" churn="57" amp="162" pure="1" r="17">constexpr std::uint32_t kMaxYamlNestDepth = 64u</d>
<d l="1812" n="spanTiersOfFiles" sc="rw" p="src/ingest_astquery.h" cx="28" ccx="55" in="1" churn="41" amp="134" r="18">SpanTierBatch spanTiersOfFiles( std::span&lt;const std::string&gt; diskPaths, bool useMemo )</d>
<d l="87" n="hasMainGuard" sc="rw::pythonrunner" p="src/pythonrunner.h" cx="2" ccx="2" in="1" churn="5" amp="14" r="19">inline bool hasMainGuard( std::string_view source )</d>
<d l="351" n="runParseWorker" p="src/ingest_parsepool.h" cx="50" ccx="116" in="1" churn="47" amp="125" tested="1" r="20">inline void runParseWorker( ParsePoolShared&amp; sh, unsigned t )</d>
<d l="2599" n="sliceScanDefinition" sc="slicev" p="src/slice.h" cx="12" ccx="11" in="3" churn="51" amp="105" r="21">inline SliceScan sliceScanDefinition( const std::string&amp; src, const Symbol&amp; sym, SliceFam fam, const ::TSLanguage* grammar, std::string_view varName )</d>
<d l="48" n="LintRule" sc="LintRule" p="src/lintrules.h" churn="49" amp="134" r="22">struct LintRule</d>
<d l="326" n="DisclosureWhy" sc="SliceScan" p="src/slice.h" churn="51" amp="102" r="23">enum class DisclosureWhy : std::uint8_t</d>
<d l="2558" n="buildMemoryStopAttr" sc="rw" p="src/serialize.h" cx="7" ccx="8" in="2" churn="249" amp="389" r="24">inline std::string buildMemoryStopAttr( const IngestResult&amp; ing, bool json )</d>
… [55 more display lines; full output is 8839 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --for="tree-sitter parse of a source file" --sections=lego,compose`

*Restore the <lego>/<compose> sections the --for bundle collapses to a counted stub by default (this is the stub's own next= spelling).*

`````
<ctx task="tree-sitter parse of a source file" route="subtoken+body" root="." confidence="low" margin_pct="0" at="c7920353a" doc_mentions="3" schema="ripwire.for/v1" bundle="compact" bodies="0" reason="compact-route" budget_bytes="7500" est_tokens="3669">
<!-- ripwire for schema=ripwire.for/v1: bundle=/bodies=/reason= the body posture; d: cx= ccx= complexity, in= callers (absent cx/ccx/in = 0), churn= amp= change, clone= tested= 1, sc= scope, id=p::sc::n; total= shown= capped=1 if cut; task= the query; d pure=1 const/constexpr sig, next= the follow-up to paste; route= name-exact(X)|subtoken+body[:broad|:declined]; confidence=/margin_pct= head score drop (low=flat); h l= p= n=, c n= l= (joined for same-named callees, shown= counts them), noedge= no callee resolved; t p= file outside sigs (weaker), r= rank (gap = trimmed); field name= type= owner= rel=: a member of owner=, rel=creates held by value, uses by reference/pointer; iface implementors=N: types implementing it, m= its method contract; d layer=: built-in arch layer (game|infra|render|math|audio|ai|test) from a dir name in p= [doc mentions: 3 docs, 2 symbols; doc_mentions=] -->
<!-- root= is the crawl root; p= below is RELATIVE to it (single-root only; absent => p= is ingest's own path, unchanged); at=this commit(+dirty). dropped_positive="11" [budget_bytes= is the default BYTE ceiling this ranked payload was shaped against; it bounds that payload, not the whole document est_tokens prices] [docs_dropped=N: N shown rows have a doc comment not printed (r>24 always, r5..24 if capped)] est_tokens= prices this bundle in tokens -->
<sigs shown="29" total="40" capped="1" docs_dropped="23">
<d l="28" n="topLevelEvidence" sc="rw::pythonrunner" p="src/pythonrunner.h" cx="4" ccx="3" in="2" churn="5" amp="15" r="1" next="--expand=src/pythonrunner.h:topLevelEvidence">inline bool topLevelEvidence( std::string_view source, const TSLanguage* language, const Predicate&amp; predicate )</d>
<d l="45" n="kDefaultMaxFileBytes" sc="rw" p="src/ingest.h" churn="57" amp="162" pure="1" r="2">
<doc>The crawl&apos;s per-file byte ceiling. A text file larger than this is skipped: at this size it is o…</doc>constexpr std::size_t kDefaultMaxFileBytes = 4u * 1024u * 1024u</d>
<d l="1153" n="parseTree" p="src/ingest_sidecap.h" cx="1" in="2" churn="81" amp="217" tested="1" r="3">TSTree* parseTree( TSParser* parser, std::string_view src )</d>
<d l="588" n="doctorProbeGrammars" p="src/verbs_doctor.h" cx="7" ccx="17" in="1" churn="43" amp="127" r="4">
<doc>Exercise every registered grammar and its embedded query, reporting loaded and expected totals</doc>inline DoctorGrammarProbe doctorProbeGrammars()</d>
<d l="1233" n="FileHealth" sc="FileHealth" p="src/model.h" churn="136" amp="315" r="5">struct FileHealth</d>
<d l="456" n="AstWalk" sc="rw" p="src/ingest.h" churn="57" amp="162" r="6">enum class AstWalk : std::uint8_t</d>
<d l="369" n="sliceAtRev" sc="slicediff" p="src/slicediff.h" cx="13" ccx="13" in="1" churn="11" amp="61" r="7">inline RevSide sliceAtRev( const std::string&amp; root, const std::string&amp; sha, const std::string&amp; rel, const Symbol&amp; sym, SliceFam fam, const ::TSLanguage* grammar…</d>
<d l="308" n="SliceScan" sc="SliceScan" p="src/slice.h" churn="51" amp="102" r="8">struct SliceScan</d>
<d l="1222" n="astroFenceTailIsBlank" p="src/ingest_sidecap.h" cx="1" in="2" churn="81" amp="217" tested="1" r="9">inline bool astroFenceTailIsBlank( std::string_view src, std::size_t from, std::size_t to ) noexcept</d>
<d l="96" n="kLangTable" p="src/ingest_crawl.h" churn="66" amp="191" pure="1" r="10">constexpr std::array&lt;LangEntry, 51&gt; kLangTable =</d>
<d l="134" n="kMaxKotlinStringNestDepth" sc="rw" p="src/ingest.h" churn="57" amp="162" pure="1" r="11">constexpr std::uint32_t kMaxKotlinStringNestDepth = 128u</d>
<d l="255" n="hasPhantomScopeSeparator" p="src/ingest_names.h" cx="2" ccx="1" in="2" churn="43" amp="143" tested="1" r="12">inline bool hasPhantomScopeSeparator( TSNode qualified ) noexcept</d>
<d l="2115" n="collectGatedLocalNames" sc="rw" p="src/ingest_astquery.h" cx="6" ccx="5" in="1" churn="41" amp="134" r="13">std::vector&lt;LocalNameFact&gt; collectGatedLocalNames( std::string_view defBytes, std::uint32_t defStartLine, Lang lang )</d>
<d l="881" n="scanModule" sc="detail" p="src/jsrunner.h" cx="16" ccx="15" in="3" churn="17" amp="81" r="14">inline ModuleScan scanModule( std::string_view source, std::string_view path )</d>
<d l="708" n="builtInLintCaptures" p="src/verbs_lint.h" cx="1" in="1" churn="30" amp="118" r="15">std::vector&lt;std::vector&lt;rw::AstMatch&gt;&gt; builtInLintCaptures( const rw::IngestResult&amp; ing, const std::vector&lt;rw::AstQuerySpec&gt;&amp; checks, std::vector&lt;std::string&gt;&amp; keptBy … [line truncated: 9 more bytes on this line]
<d l="683" n="jsonNestsTooDeep" p="src/ingest_crawl.h" cx="13" ccx="20" in="1" churn="66" amp="192" tested="1" r="16">bool jsonNestsTooDeep( std::string_view bytes ) noexcept</d>
<d l="104" n="kMaxYamlNestDepth" sc="rw" p="src/ingest.h" churn="57" amp="162" pure="1" r="17">constexpr std::uint32_t kMaxYamlNestDepth = 64u</d>
<d l="1812" n="spanTiersOfFiles" sc="rw" p="src/ingest_astquery.h" cx="28" ccx="55" in="1" churn="41" amp="134" r="18">SpanTierBatch spanTiersOfFiles( std::span&lt;const std::string&gt; diskPaths, bool useMemo )</d>
<d l="87" n="hasMainGuard" sc="rw::pythonrunner" p="src/pythonrunner.h" cx="2" ccx="2" in="1" churn="5" amp="14" r="19">inline bool hasMainGuard( std::string_view source )</d>
<d l="351" n="runParseWorker" p="src/ingest_parsepool.h" cx="50" ccx="116" in="1" churn="47" amp="125" tested="1" r="20">inline void runParseWorker( ParsePoolShared&amp; sh, unsigned t )</d>
<d l="2599" n="sliceScanDefinition" sc="slicev" p="src/slice.h" cx="12" ccx="11" in="3" churn="51" amp="105" r="21">inline SliceScan sliceScanDefinition( const std::string&amp; src, const Symbol&amp; sym, SliceFam fam, const ::TSLanguage* grammar, std::string_view varName )</d>
<d l="48" n="LintRule" sc="LintRule" p="src/lintrules.h" churn="49" amp="134" r="22">struct LintRule</d>
<d l="326" n="DisclosureWhy" sc="SliceScan" p="src/slice.h" churn="51" amp="102" r="23">enum class DisclosureWhy : std::uint8_t</d>
<d l="2558" n="buildMemoryStopAttr" sc="rw" p="src/serialize.h" cx="7" ccx="8" in="2" churn="249" amp="389" r="24">inline std::string buildMemoryStopAttr( const IngestResult&amp; ing, bool json )</d>
… [66 more display lines; full output is 9172 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --for="tree-sitter parse of a source file" --auto-bodies`

*Opt OUT of compact conceptual serving: restore the rank-first auto <bodies> walk (bundle="auto").*

`````
<ctx task="tree-sitter parse of a source file" route="subtoken+body" root="." confidence="low" margin_pct="0" at="c7920353a" doc_mentions="3" schema="ripwire.for/v1" bundle="auto" bodies="4" budget_bytes="7500" est_tokens="4397">
<!-- ripwire for schema=ripwire.for/v1: bundle=/bodies=/reason= the body posture; d: cx= ccx= complexity, in= callers (absent cx/ccx/in = 0), churn= amp= change, clone= tested= 1, sc= scope, id=p::sc::n; total= shown= capped=1 if cut; task= the query; d pure=1 const/constexpr sig, next= the follow-up to paste; route= name-exact(X)|subtoken+body[:broad|:declined]; confidence=/margin_pct= head score drop (low=flat); b t= n= p= l= full bodies, c n= l= callee signatures; t p= file outside sigs (weaker), r= rank (gap = trimmed); field name= type= owner= rel=: a member of owner=, rel=creates held by value, uses by reference/pointer; iface implementors=N: types implementing it, m= its method contract; d layer=: built-in arch layer (game|infra|render|math|audio|ai|test) from a dir name in p= [doc mentions: 3 docs, 2 symbols; doc_mentions=] -->
<!-- root= is the crawl root; p= below is RELATIVE to it (single-root only; absent => p= is ingest's own path, unchanged); at=this commit(+dirty). dropped_positive="11" [budget_bytes= is the default BYTE ceiling this ranked payload was shaped against; it bounds that payload, not the whole document est_tokens prices] [docs_dropped=N: N shown rows have a doc comment not printed (r>24 always, r5..24 if capped)]; lego/compose collapse to a counted stub by default (a disclosed cut): total= that section's own pre-cap row count, shown="0" capped="1" (nothing rendered here), next= names the sections=lego,compose flag that restores both sections byte-identically in one call est_tokens= prices this bundle in tokens -->
<sigs shown="29" total="40" capped="1" docs_dropped="23">
<d l="28" n="topLevelEvidence" sc="rw::pythonrunner" p="src/pythonrunner.h" cx="4" ccx="3" in="2" churn="5" amp="15" r="1" next="--expand=src/pythonrunner.h:topLevelEvidence">inline bool topLevelEvidence( std::string_view source, const TSLanguage* language, const Predicate&amp; predicate )</d>
<d l="45" n="kDefaultMaxFileBytes" sc="rw" p="src/ingest.h" churn="57" amp="162" pure="1" r="2">
<doc>The crawl&apos;s per-file byte ceiling. A text file larger than this is skipped: at this size it is o…</doc>constexpr std::size_t kDefaultMaxFileBytes = 4u * 1024u * 1024u</d>
<d l="1153" n="parseTree" p="src/ingest_sidecap.h" cx="1" in="2" churn="81" amp="217" tested="1" r="3">TSTree* parseTree( TSParser* parser, std::string_view src )</d>
<d l="588" n="doctorProbeGrammars" p="src/verbs_doctor.h" cx="7" ccx="17" in="1" churn="43" amp="127" r="4">
<doc>Exercise every registered grammar and its embedded query, reporting loaded and expected totals</doc>inline DoctorGrammarProbe doctorProbeGrammars()</d>
<d l="1233" n="FileHealth" sc="FileHealth" p="src/model.h" churn="136" amp="315" r="5">struct FileHealth</d>
<d l="456" n="AstWalk" sc="rw" p="src/ingest.h" churn="57" amp="162" r="6">enum class AstWalk : std::uint8_t</d>
<d l="369" n="sliceAtRev" sc="slicediff" p="src/slicediff.h" cx="13" ccx="13" in="1" churn="11" amp="61" r="7">inline RevSide sliceAtRev( const std::string&amp; root, const std::string&amp; sha, const std::string&amp; rel, const Symbol&amp; sym, SliceFam fam, const ::TSLanguage* grammar…</d>
<d l="308" n="SliceScan" sc="SliceScan" p="src/slice.h" churn="51" amp="102" r="8">struct SliceScan</d>
<d l="1222" n="astroFenceTailIsBlank" p="src/ingest_sidecap.h" cx="1" in="2" churn="81" amp="217" tested="1" r="9">inline bool astroFenceTailIsBlank( std::string_view src, std::size_t from, std::size_t to ) noexcept</d>
<d l="96" n="kLangTable" p="src/ingest_crawl.h" churn="66" amp="191" pure="1" r="10">constexpr std::array&lt;LangEntry, 51&gt; kLangTable =</d>
<d l="134" n="kMaxKotlinStringNestDepth" sc="rw" p="src/ingest.h" churn="57" amp="162" pure="1" r="11">constexpr std::uint32_t kMaxKotlinStringNestDepth = 128u</d>
<d l="255" n="hasPhantomScopeSeparator" p="src/ingest_names.h" cx="2" ccx="1" in="2" churn="43" amp="143" tested="1" r="12">inline bool hasPhantomScopeSeparator( TSNode qualified ) noexcept</d>
<d l="2115" n="collectGatedLocalNames" sc="rw" p="src/ingest_astquery.h" cx="6" ccx="5" in="1" churn="41" amp="134" r="13">std::vector&lt;LocalNameFact&gt; collectGatedLocalNames( std::string_view defBytes, std::uint32_t defStartLine, Lang lang )</d>
<d l="881" n="scanModule" sc="detail" p="src/jsrunner.h" cx="16" ccx="15" in="3" churn="17" amp="81" r="14">inline ModuleScan scanModule( std::string_view source, std::string_view path )</d>
<d l="708" n="builtInLintCaptures" p="src/verbs_lint.h" cx="1" in="1" churn="30" amp="118" r="15">std::vector&lt;std::vector&lt;rw::AstMatch&gt;&gt; builtInLintCaptures( const rw::IngestResult&amp; ing, const std::vector&lt;rw::AstQuerySpec&gt;&amp; checks, std::vector&lt;std::string&gt;&amp; keptBy … [line truncated: 9 more bytes on this line]
<d l="683" n="jsonNestsTooDeep" p="src/ingest_crawl.h" cx="13" ccx="20" in="1" churn="66" amp="192" tested="1" r="16">bool jsonNestsTooDeep( std::string_view bytes ) noexcept</d>
<d l="104" n="kMaxYamlNestDepth" sc="rw" p="src/ingest.h" churn="57" amp="162" pure="1" r="17">constexpr std::uint32_t kMaxYamlNestDepth = 64u</d>
<d l="1812" n="spanTiersOfFiles" sc="rw" p="src/ingest_astquery.h" cx="28" ccx="55" in="1" churn="41" amp="134" r="18">SpanTierBatch spanTiersOfFiles( std::span&lt;const std::string&gt; diskPaths, bool useMemo )</d>
<d l="87" n="hasMainGuard" sc="rw::pythonrunner" p="src/pythonrunner.h" cx="2" ccx="2" in="1" churn="5" amp="14" r="19">inline bool hasMainGuard( std::string_view source )</d>
<d l="351" n="runParseWorker" p="src/ingest_parsepool.h" cx="50" ccx="116" in="1" churn="47" amp="125" tested="1" r="20">inline void runParseWorker( ParsePoolShared&amp; sh, unsigned t )</d>
<d l="2599" n="sliceScanDefinition" sc="slicev" p="src/slice.h" cx="12" ccx="11" in="3" churn="51" amp="105" r="21">inline SliceScan sliceScanDefinition( const std::string&amp; src, const Symbol&amp; sym, SliceFam fam, const ::TSLanguage* grammar, std::string_view varName )</d>
<d l="48" n="LintRule" sc="LintRule" p="src/lintrules.h" churn="49" amp="134" r="22">struct LintRule</d>
<d l="326" n="DisclosureWhy" sc="SliceScan" p="src/slice.h" churn="51" amp="102" r="23">enum class DisclosureWhy : std::uint8_t</d>
<d l="2558" n="buildMemoryStopAttr" sc="rw" p="src/serialize.h" cx="7" ccx="8" in="2" churn="249" amp="389" r="24">inline std::string buildMemoryStopAttr( const IngestResult&amp; ing, bool json )</d>
… [90 more display lines; full output is 12411 bytes on 55 raw line(s)]
`````

## `./build/ripwire . --for="quality delta acks ledger rubber stamp"`

*Doc-mention surfacing (default ON): a markdown doc naming a top-resolved symbol in a backtick rides in below that symbol — the legend's [doc mentions: …] clause says it fired.*

`````
<ctx task="quality delta acks ledger rubber stamp" route="subtoken+body" root="." confidence="low" margin_pct="0" at="c7920353a" doc_mentions="1" schema="ripwire.for/v1" bundle="compact" bodies="0" reason="compact-route" budget_bytes="7500" est_tokens="3626">
<!-- ripwire for schema=ripwire.for/v1: bundle=/bodies=/reason= the body posture; d: cx= ccx= complexity, in= callers (absent cx/ccx/in = 0), churn= amp= change, clone= tested= 1, sc= scope, id=p::sc::n; total= shown= capped=1 if cut; task= the query; d pure=1 const/constexpr sig, next= the follow-up to paste; route= name-exact(X)|subtoken+body[:broad|:declined]; confidence=/margin_pct= head score drop (low=flat); h l= p= n=, c n= l= (joined for same-named callees, shown= counts them), noedge= no callee resolved; t p= file outside sigs (weaker), r= rank (gap = trimmed); field name= type= owner= rel=: a member of owner=, rel=creates held by value, uses by reference/pointer; iface implementors=N: types implementing it, m= its method contract; d layer=: built-in arch layer (game|infra|render|math|audio|ai|test) from a dir name in p= [doc mentions: 1 doc, 1 symbol; doc_mentions=] -->
<!-- root= is the crawl root; p= below is RELATIVE to it (single-root only; absent => p= is ingest's own path, unchanged); at=this commit(+dirty). dropped_positive="13" [budget_bytes= is the default BYTE ceiling this ranked payload was shaped against; it bounds that payload, not the whole document est_tokens prices] [docs_dropped=N: N shown rows have a doc comment not printed (r>24 always, r5..24 if capped)] est_tokens= prices this bundle in tokens -->
<sigs shown="27" total="40" capped="1" docs_dropped="18">
<d l="3896" n="computeQualityDelta" sc="rw" p="src/mcpverbs.h" cx="4" ccx="4" in="1" churn="309" amp="406" r="1" next="--expand=src/mcpverbs.h:computeQualityDelta">inline QualityDeltaOutcome computeQualityDelta( const std::string&amp; root )</d>
<d l="467" n="refuseForeignAckSelection" p="src/verbs_quality.h" cx="9" ccx="12" in="1" churn="79" amp="192" r="2">std::optional&lt;int&gt; refuseForeignAckSelection( const rw::Config&amp; cfg, const rw::quality::Scope&amp; scope, const std::vector&lt;rw::quality::Regression&gt;&amp; outOfScope, st … [line truncated: 7 more bytes on this line]
<d l="1111" n="runQualityDelta" p="src/verbs_quality.h" cx="117" ccx="288" in="1" churn="79" amp="192" r="3">
<doc>runQualityViews was NOT a dispatch chain — it held two branches, one of which was 298 lines. T…</doc>std::optional&lt;int&gt; runQualityDelta( const MainDispatch&amp; d )</d>
<d l="971" n="ackNothingToAccept" p="src/verbs_quality.h" cx="6" ccx="7" in="1" churn="79" amp="192" r="4">
<doc>H10 (capture-audit 2026-09-04): the --quality-ack run that has NOTHING to accept. It used to re-…</doc>int ackNothingToAccept( const std::string&amp; acksFile, const gtl::btree_map&lt;std::string, rw::quality::AckRecord&gt;&amp; acks, const rw::quality::Scope&amp; scope, std::size…</d>
<d l="172" n="DeltaBasis" sc="DeltaBasis" p="src/verbs_quality.h" churn="79" amp="191" r="5">struct DeltaBasis</d>
<d l="191" n="kAcksFile" sc="quality" p="src/quality.h" churn="357" amp="510" r="6">inline const char* kAcksFile = &quot;.ripwire_quality_acks&quot;</d>
<d l="1022" n="inspectDirtyBaselinePin" p="src/verbs_quality.h" cx="6" ccx="7" in="1" churn="79" amp="192" r="7">DirtyPinVerdict inspectDirtyBaselinePin( const MainDispatch&amp; d, const std::string&amp; acksFile )</d>
<d l="7368" n="IdentityHealing" sc="IdentityHealing" p="src/quality.h" churn="357" amp="510" r="8">struct IdentityHealing</d>
<d l="3982" n="qualityDeltaJson" sc="rw" p="src/mcpverbs.h" cx="22" ccx="35" in="1" churn="309" amp="406" r="9">inline std::pair&lt;std::string, std::string&gt; qualityDeltaJson( const std::string&amp; root )</d>
<d l="6949" n="writeAckRecords" sc="quality" p="src/quality.h" cx="2" ccx="1" in="2" churn="357" amp="512" r="10">inline bool writeAckRecords( const std::string&amp; path, const gtl::btree_map&lt;std::string, AckRecord&gt;&amp; acks )</d>
<d l="202" n="resolveDeltaBasis" p="src/verbs_quality.h" cx="10" ccx="13" in="1" churn="79" amp="192" r="11">std::optional&lt;int&gt; resolveDeltaBasis( const MainDispatch&amp; d, const std::string&amp; baselineFile, RefPairDelta&amp; refs, DeltaBasis&amp; out )</d>
<d l="7815" n="staleAcksXml" sc="quality" p="src/quality.h" cx="5" ccx="8" in="1" churn="357" amp="511" r="12">inline std::string staleAcksXml( const std::vector&lt;StaleAck&gt;&amp; staleAcks, EscapeFn esc )</d>
<d l="3793" n="QualityDeltaOutcome" sc="QualityDeltaOutcome" p="src/mcpverbs.h" churn="309" amp="405" r="13">struct QualityDeltaOutcome</d>
<d l="3710" n="atomicWriteFile" sc="quality" p="src/quality.h" cx="3" ccx="2" in="4" churn="357" amp="514" r="14">inline bool atomicWriteFile( const std::string&amp; path, const std::string&amp; blob )</d>
<d l="3788" n="qualityAcksPath" sc="rw" p="src/mcpverbs.h" cx="1" in="1" churn="309" amp="406" r="15">inline std::string qualityAcksPath( const std::string&amp; root )</d>
<d l="2167" n="kAtStampLegend" sc="rw" p="src/serialize.h" churn="249" amp="387" pure="1" r="16">inline constexpr const char* kAtStampLegend = &quot;&lt;!-- at= is the git commit these numbers were computed at</d>
<d l="1907" n="gitHeadSha" sc="quality" p="src/quality.h" cx="1" in="16" churn="357" amp="526" r="17">inline std::string gitHeadSha( const std::string&amp; root )</d>
<d l="6701" n="readAckRecords" sc="quality" p="src/quality.h" cx="15" ccx="22" in="5" churn="357" amp="515" tested="1" r="18">inline gtl::btree_map&lt;std::string, AckRecord&gt; readAckRecords( const std::string&amp; path, std::size_t&amp; badLines )</d>
<d l="243" n="openRegularFileStream" sc="detail" p="src/docparse.h" cx="7" ccx="8" in="2" churn="28" amp="71" tested="1" r="19">inline rw::pathguard::NoFollowRead openRegularFileStream( std::string_view what, const std::string&amp; path )</d>
<d l="6917" n="renderAckRecords" sc="quality" p="src/quality.h" cx="5" ccx="7" in="3" churn="357" amp="513" r="20">inline std::string renderAckRecords( const gtl::btree_map&lt;std::string, AckRecord&gt;&amp; acks )</d>
<d l="1065" n="runQualityBaselinePin" p="src/verbs_quality.h" cx="7" ccx="7" in="1" churn="79" amp="192" r="21">int runQualityBaselinePin( const MainDispatch&amp; d, const std::string&amp; baselineFile, const std::string&amp; acksFile )</d>
<d l="314" n="computeDmm" sc="rw::dmm" p="src/dmm.h" cx="9" ccx="6" in="1" churn="16" amp="77" r="22">inline Result computeDmm( const std::string&amp; root, std::string_view spec, const IngestResult&amp; workingIng, const std::vector&lt;std::string&gt;&amp; excludes, std::size_t maxFileBytes )</d>
<d l="684" n="kQdSchemeLegend" p="src/verbs_quality.h" churn="79" amp="191" pure="1" r="23">inline constexpr const char* kQdSchemeLegend = &quot;A THIRD re-filing, git-independent: on 2026-08-25 the per-symbol quality key stopped being a &quot; &quot;canonical-id hash (which degraded to a BARE NAME  … [line truncated: 54 more bytes on this line]
<d l="3787" n="qualityBaselinePath" sc="rw" p="src/mcpverbs.h" cx="1" in="2" churn="309" amp="407" r="24">inline std::string qualityBaselinePath( const std::string&amp; root )</d>
… [52 more display lines; full output is 9064 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --for="quality delta acks ledger rubber stamp" --no-doc-mention`

*The same task with doc-mention surfacing OFF — the contrast the flag exists for (no [doc mentions] clause, one fewer row).*

`````
<ctx task="quality delta acks ledger rubber stamp" route="subtoken+body" root="." confidence="low" margin_pct="0" at="c7920353a" schema="ripwire.for/v1" bundle="compact" bodies="0" reason="compact-route" budget_bytes="7500" est_tokens="3692">
<!-- ripwire for schema=ripwire.for/v1: bundle=/bodies=/reason= the body posture; d: cx= ccx= complexity, in= callers (absent cx/ccx/in = 0), churn= amp= change, clone= tested= 1, sc= scope, id=p::sc::n; total= shown= capped=1 if cut; task= the query; d pure=1 const/constexpr sig, next= the follow-up to paste; route= name-exact(X)|subtoken+body[:broad|:declined]; confidence=/margin_pct= head score drop (low=flat); h l= p= n=, c n= l= (joined for same-named callees, shown= counts them), noedge= no callee resolved; t p= file outside sigs (weaker), r= rank (gap = trimmed); field name= type= owner= rel=: a member of owner=, rel=creates held by value, uses by reference/pointer; iface implementors=N: types implementing it, m= its method contract; d layer=: built-in arch layer (game|infra|render|math|audio|ai|test) from a dir name in p= -->
<!-- root= is the crawl root; p= below is RELATIVE to it (single-root only; absent => p= is ingest's own path, unchanged); at=this commit(+dirty). dropped_positive="12" [budget_bytes= is the default BYTE ceiling this ranked payload was shaped against; it bounds that payload, not the whole document est_tokens prices] [docs_dropped=N: N shown rows have a doc comment not printed (r>24 always, r5..24 if capped)] est_tokens= prices this bundle in tokens -->
<sigs shown="28" total="40" capped="1" docs_dropped="19">
<d l="3896" n="computeQualityDelta" sc="rw" p="src/mcpverbs.h" cx="4" ccx="4" in="1" churn="309" amp="406" r="1" next="--expand=src/mcpverbs.h:computeQualityDelta">inline QualityDeltaOutcome computeQualityDelta( const std::string&amp; root )</d>
<d l="467" n="refuseForeignAckSelection" p="src/verbs_quality.h" cx="9" ccx="12" in="1" churn="79" amp="192" r="2">std::optional&lt;int&gt; refuseForeignAckSelection( const rw::Config&amp; cfg, const rw::quality::Scope&amp; scope, const std::vector&lt;rw::quality::Regression&gt;&amp; outOfScope, st … [line truncated: 7 more bytes on this line]
<d l="1111" n="runQualityDelta" p="src/verbs_quality.h" cx="117" ccx="288" in="1" churn="79" amp="192" r="3">
<doc>runQualityViews was NOT a dispatch chain — it held two branches, one of which was 298 lines. T…</doc>std::optional&lt;int&gt; runQualityDelta( const MainDispatch&amp; d )</d>
<d l="971" n="ackNothingToAccept" p="src/verbs_quality.h" cx="6" ccx="7" in="1" churn="79" amp="192" r="4">
<doc>H10 (capture-audit 2026-09-04): the --quality-ack run that has NOTHING to accept. It used to re-…</doc>int ackNothingToAccept( const std::string&amp; acksFile, const gtl::btree_map&lt;std::string, rw::quality::AckRecord&gt;&amp; acks, const rw::quality::Scope&amp; scope, std::size…</d>
<d l="172" n="DeltaBasis" sc="DeltaBasis" p="src/verbs_quality.h" churn="79" amp="191" r="5">struct DeltaBasis</d>
<d l="191" n="kAcksFile" sc="quality" p="src/quality.h" churn="357" amp="510" r="6">inline const char* kAcksFile = &quot;.ripwire_quality_acks&quot;</d>
<d l="1022" n="inspectDirtyBaselinePin" p="src/verbs_quality.h" cx="6" ccx="7" in="1" churn="79" amp="192" r="7">DirtyPinVerdict inspectDirtyBaselinePin( const MainDispatch&amp; d, const std::string&amp; acksFile )</d>
<d l="7368" n="IdentityHealing" sc="IdentityHealing" p="src/quality.h" churn="357" amp="510" r="8">struct IdentityHealing</d>
<d l="3982" n="qualityDeltaJson" sc="rw" p="src/mcpverbs.h" cx="22" ccx="35" in="1" churn="309" amp="406" r="9">inline std::pair&lt;std::string, std::string&gt; qualityDeltaJson( const std::string&amp; root )</d>
<d l="6949" n="writeAckRecords" sc="quality" p="src/quality.h" cx="2" ccx="1" in="2" churn="357" amp="512" r="10">inline bool writeAckRecords( const std::string&amp; path, const gtl::btree_map&lt;std::string, AckRecord&gt;&amp; acks )</d>
<d l="202" n="resolveDeltaBasis" p="src/verbs_quality.h" cx="10" ccx="13" in="1" churn="79" amp="192" r="11">std::optional&lt;int&gt; resolveDeltaBasis( const MainDispatch&amp; d, const std::string&amp; baselineFile, RefPairDelta&amp; refs, DeltaBasis&amp; out )</d>
<d l="7815" n="staleAcksXml" sc="quality" p="src/quality.h" cx="5" ccx="8" in="1" churn="357" amp="511" r="12">inline std::string staleAcksXml( const std::vector&lt;StaleAck&gt;&amp; staleAcks, EscapeFn esc )</d>
<d l="3793" n="QualityDeltaOutcome" sc="QualityDeltaOutcome" p="src/mcpverbs.h" churn="309" amp="405" r="13">struct QualityDeltaOutcome</d>
<d l="3710" n="atomicWriteFile" sc="quality" p="src/quality.h" cx="3" ccx="2" in="4" churn="357" amp="514" r="14">inline bool atomicWriteFile( const std::string&amp; path, const std::string&amp; blob )</d>
<d l="3788" n="qualityAcksPath" sc="rw" p="src/mcpverbs.h" cx="1" in="1" churn="309" amp="406" r="15">inline std::string qualityAcksPath( const std::string&amp; root )</d>
<d l="2167" n="kAtStampLegend" sc="rw" p="src/serialize.h" churn="249" amp="387" pure="1" r="16">inline constexpr const char* kAtStampLegend = &quot;&lt;!-- at= is the git commit these numbers were computed at</d>
<d l="1907" n="gitHeadSha" sc="quality" p="src/quality.h" cx="1" in="16" churn="357" amp="526" r="17">inline std::string gitHeadSha( const std::string&amp; root )</d>
<d l="6701" n="readAckRecords" sc="quality" p="src/quality.h" cx="15" ccx="22" in="5" churn="357" amp="515" tested="1" r="18">inline gtl::btree_map&lt;std::string, AckRecord&gt; readAckRecords( const std::string&amp; path, std::size_t&amp; badLines )</d>
<d l="243" n="openRegularFileStream" sc="detail" p="src/docparse.h" cx="7" ccx="8" in="2" churn="28" amp="71" tested="1" r="19">inline rw::pathguard::NoFollowRead openRegularFileStream( std::string_view what, const std::string&amp; path )</d>
<d l="6917" n="renderAckRecords" sc="quality" p="src/quality.h" cx="5" ccx="7" in="3" churn="357" amp="513" r="20">inline std::string renderAckRecords( const gtl::btree_map&lt;std::string, AckRecord&gt;&amp; acks )</d>
<d l="1065" n="runQualityBaselinePin" p="src/verbs_quality.h" cx="7" ccx="7" in="1" churn="79" amp="192" r="21">int runQualityBaselinePin( const MainDispatch&amp; d, const std::string&amp; baselineFile, const std::string&amp; acksFile )</d>
<d l="314" n="computeDmm" sc="rw::dmm" p="src/dmm.h" cx="9" ccx="6" in="1" churn="16" amp="77" r="22">inline Result computeDmm( const std::string&amp; root, std::string_view spec, const IngestResult&amp; workingIng, const std::vector&lt;std::string&gt;&amp; excludes, std::size_t maxFileBytes )</d>
<d l="684" n="kQdSchemeLegend" p="src/verbs_quality.h" churn="79" amp="191" pure="1" r="23">inline constexpr const char* kQdSchemeLegend = &quot;A THIRD re-filing, git-independent: on 2026-08-25 the per-symbol quality key stopped being a &quot; &quot;canonical-id hash (which degraded to a BARE NAME  … [line truncated: 54 more bytes on this line]
<d l="3787" n="qualityBaselinePath" sc="rw" p="src/mcpverbs.h" cx="1" in="2" churn="309" amp="407" r="24">inline std::string qualityBaselinePath( const std::string&amp; root )</d>
… [53 more display lines; full output is 9230 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --safe-delete=rankGraphTeleport`

*"Can I delete this?" — callers + transitive impact + every use site + how much of the radius is tested, composed in ONE call; risk= names what was found, never a verdict.*

`````
<!-- ripwire safe-delete schema=ripwire.safe-delete/v1: can sym= go, a READ never a verdict: callers= impact_reaches= uses= tested_self= risk=; <c n= p= amb=>; radius_tested= non-tests of impact_reaches= an indexed test reaches, radius_untested= the rest; t= p= its lowest-id match's kind and file:line; defs= matched; ambiguous_callers= callers with a call split over several defs; dead_code_candidate=1 only at defs=1 with no caller, for a t=fn with a body, outside .h/.hpp/.hh/.hxx, whose signature spells static (0 never means in use). window: shown= capped= (capped=1 cut). counts_floor=1: every count is a FLOOR, never a total. graph_ambiguous=/graph_unresolved=: resolver gauge. graph_unindexed=N: N files no grammar could read (the map header's unindexed=); their calls raise neither gauge. root=: p= relative to it. amb=K: K calls split over several defs. -->
<safe-delete schema="ripwire.safe-delete/v1" sym="rankGraphTeleport" t="fn" p="src/graph.h:5565" defs="1" callers="7" ambiguous_callers="6" impact_reaches="67" uses="9" tested_self="0" radius_tested="0" radius_untested="67" dead_code_candidate="0" risk="untested-radius" shown="7" capped="0" graph_am … [line truncated: 89 more bytes on this line]
<c n="runEval" p="src/eval.h:171" amb="11"/>
<c n="rankGraph" p="src/graph.h:5606"/>
<c n="anchoredLexicalRank" p="src/graph.h:6252" amb="7"/>
<c n="churnDecayRanking" p="src/main.cpp:1380" amb="2"/>
<c n="churnRankedGraph" p="src/main.cpp:1419" amb="3"/>
<c n="runDefaultMap" p="src/main.cpp:1629" amb="62"/>
<c n="getIndex" p="src/mcpindex.h:1165" amb="8"/>
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

**wall time: 1.35s**

`````
<!-- ripwire handoff schema=ripwire.handoff/v1: continuation packet for the NEXT session: <verified changed= blast_files=>, <tests n=>, <heuristic n= candidates=>, <note>, <doc p=>. window: capped= (capped=1 cut). est_tokens=: price as emitted (an upper bound under compact). at=: commit+dirty+shallow. root=: p= relative to it. branch=/subject=: the checked out branch and HEAD commit subject; gitok=0: the git diff probe failed, changed counts are floors. cochange_window=/cochange_commits=: the git window the cochange rows were mined in and the commits it held (0: could not look). doc s=: lexical score of that plan/design doc for the branch+subject query. note target=/txt=: a committed notes row on this work (symbol id or path) and its text; a suggestion. -->
<handoff schema="ripwire.handoff/v1" at="c7920353a" root="." branch="lane/lean-answers-068" subject="whereis: the default serves the page that lists more definitions, then the shorter" gitok="1" est_tokens="867">
<verified changed="0" blast_files="0">
<tests n="0">
</tests>
</verified>
<heuristic n="6" candidates="199" capped="1" cochange_window="18mo@HEAD" cochange_commits="3939">
<note target="src/infra/Diagnostics.h" txt="ASSUME_NO_ALIAS is an optimizer fact in release (separate_storage) only where the compiler consumes it: clang 18+ by default, LLVM 17/AppleClang 16 via the CMake -mllvm flag (scalars only), GCC never (debug check only); never on two members of one object;  … [line truncated: 57 more bytes on this line]
<note target="test/manifestcheck.sh" txt="README.md&apos;s single &apos;&lt;N&gt; gate scripts&apos; claim (~line 1305) is NOT enforced — the derived-vs-stated sibling loop here covers docs/EVALS.md only. It drifted 407→451 unnoticed (fixed 2026-08-23). To close: grep both files (&apos;file:line … [line truncated: 47 more bytes on this line]
<doc p="CHANGELOG.md" s="20.546"/>
<doc p="docs/COMMANDS.md" s="14.830"/>
<doc p="docs/research/answer-completeness.md" s="8.508"/>
<doc p="skills/ripwire-mcp/SKILL.md" s="7.623"/>
</heuristic>
</handoff>
`````

## `./build/ripwire . --handoff --token-budget=1200`

*The same packet under a hard ceiling: heuristic rows drop tail-first (withheld= disclosed), verified rows never drop.*

**wall time: 1.32s**

`````
<!-- ripwire handoff schema=ripwire.handoff/v1: continuation packet for the NEXT session: <verified changed= blast_files=>, <tests n=>, <heuristic n= candidates=>, <note>, <doc p=>. window: capped= (capped=1 cut). est_tokens=: price as emitted (an upper bound under compact). over_ceiling=1: budget not met. withheld=: rows the budget cut. at=: commit+dirty+shallow. root=: p= relative to it. branch=/subject=: the checked out branch and HEAD commit subject; gitok=0: the git diff probe failed, changed counts are floors. cochange_window=/cochange_commits=: the git window the cochange rows were mined in and the commits it held (0: could not look). doc s=: lexical score of that plan/design doc for the branch+subject query. note target=/txt=: a committed notes row on this work (symbol id or path) and its text; a suggestion. budget=: the token-budget cap this packet was fitted to; est_tokens= prices what it delivers. withheld_rows=N: heuristic rows the budget dropped (withheld=1 says so); verified rows are never dropped. -->
<handoff schema="ripwire.handoff/v1" at="c7920353a" root="." branch="lane/lean-answers-068" subject="whereis: the default serves the page that lists more definitions, then the shorter" gitok="1" budget="1200" withheld="1" withheld_rows="3" est_tokens="939" over_ceiling="1">
<verified changed="0" blast_files="0">
<tests n="0">
</tests>
</verified>
<heuristic n="3" candidates="199" capped="1" cochange_window="18mo@HEAD" cochange_commits="3939">
<note target="src/infra/Diagnostics.h" txt="ASSUME_NO_ALIAS is an optimizer fact in release (separate_storage) only where the compiler consumes it: clang 18+ by default, LLVM 17/AppleClang 16 via the CMake -mllvm flag (scalars only), GCC never (debug check only); never on two members of one object;  … [line truncated: 57 more bytes on this line]
<note target="test/manifestcheck.sh" txt="README.md&apos;s single &apos;&lt;N&gt; gate scripts&apos; claim (~line 1305) is NOT enforced — the derived-vs-stated sibling loop here covers docs/EVALS.md only. It drifted 407→451 unnoticed (fixed 2026-08-23). To close: grep both files (&apos;file:line … [line truncated: 47 more bytes on this line]
<doc p="CHANGELOG.md" s="20.546"/>
</heuristic>
</handoff>
`````

## `./build/ripwire . --skipped`

*WHY a file is not in the index (oversize / excluded / unsupported-ext / gitignored) and which indexed files it cannot vouch for (degraded-parse, minified-suspect), plus the per-language census.*

`````
<ctx schema="ripwire.skipped/v1">
<!-- ripwire skipped schema=ripwire.skipped/v1: why the index lacks a file <f p= why= bytes= limit= ext=>; indexed but unvouched <h p= why= err= err_ratio=>; <lang> census. root=: p= relative to it. indexed=N: the map's files=; indexed= + oversize= + excluded= + ignored= = every file the crawl enumerated. oversize=N: files dropped for exceeding a size ceiling (row limit= names which). excluded=N: files dropped by an exclude substring you passed. unsupported_ext=N: source/text files no grammar reads; binary assets and excluded/ignored files not counted. excluded_dirs=N: subtrees an exclude pruned; their files are UNKNOWN, not zero, and in no count here. pruned_dirs=N: subtrees pruned by built-in policy (vendor/build, CMakeCache.txt dirs); contents UNKNOWN. ignored=/ignored_dirs=: files / subtrees git ignore rules hid (else indexed); subtree contents UNKNOWN. ignore_mode=: git (rules applied), off (no-ignore flag), unavailable/root-ignored (not consulted, full walk). degraded_parse=/minified_suspect=: counts of the h rows of each why=; those files stay indexed. unmeasured=N: indexed files never parsed (doc pass, binary sniff, nest guard, read error); not health-counted. max_file_size=B: the effective per-file size ceiling in bytes (the max-file-size flag raises it). json_ceiling=/yaml_ceiling=: fixed .json/.yaml byte ceilings the max-file-size flag does NOT raise. ws_freq=R: whitespace share of the leading 4096 bytes; under 0.070 = minified-suspect (never under 256 B). x=/files=: an unindexed extension and its file count (full list; the map's unindexed= is the top 6). files=/symbols=: per language, files with its symbols (FLOOR: symbol-less files uncounted) / symbols (exact). -->
<!-- why=extent-suspect on an <h> row = the file holds extent_suspect_syms= definitions whose extent, scope or kind FAILED a containment check (the map and bundle rows carry the reasons as extent_suspect=: name, head, scope, error); joined to the parse-health reasons comma-separated, and rowed even when the parse itself is clean. extent_suspect_files= on the root counts such rows. Nothing is dropped. -->
<!-- why=macro-blanked on an <h> row = this file's symbols come from a SECOND parse. Its first parse held error bytes, so macro_blanked= semicolon-less ALL-CAPS function-like macro invocations, each alone on its line directly inside a class/struct/union body (a shape the C-family grammars misread as a field missing its semicolon, letting one body swallow what follows it), were replaced by spaces with every offset and line unchanged, and that re-parse was adopted because it held STRICTLY FEWER error bytes; names, spans and bodies still read the original bytes. err=, err_ratio= and degraded-parse on such a row describe the ADOPTED parse: a row without degraded-parse parsed clean once blanked. A blanked invocation stays a use of the macro name for the uses verb (role=type, as the unrepaired parse recorded it) but is no call edge, and identifiers inside its parentheses are not recorded. macro_blanked_files= on the root counts such rows. Nothing is dropped. -->
<skipped indexed="2484" oversize="15" excluded="0" unsupported_ext="237" excluded_dirs="0" pruned_dirs="8" ignored="0" ignored_dirs="0" ignore_mode="git" degraded_parse="112" minified_suspect="2" extent_suspect_files="3" macro_blanked_files="7" unmeasured="20" max_file_size="4194304" json_ceiling="2 … [line truncated: 38 more bytes on this line]
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
<f p=".github/pargates-macos-plain-skip.txt" why="unsupported-ext" bytes="986" ext=".txt"/>
<f p="CMakeLists.txt" why="unsupported-ext" bytes="100647" ext=".txt"/>
<f p="bench/agentloop/editsuite/expected/i1/stats.py.expected" why="unsupported-ext" bytes="603" ext=".expected"/>
<f p="bench/agentloop/editsuite/expected/i2/matrix.cpp.expected" why="unsupported-ext" bytes="973" ext=".expected"/>
<f p="bench/agentloop/editsuite/expected/i3/text.py.expected" why="unsupported-ext" bytes="338" ext=".expected"/>
<f p="bench/agentloop/editsuite/expected/p1/geometry.cpp.expected" why="unsupported-ext" bytes="723" ext=".expected"/>
<f p="bench/agentloop/editsuite/expected/p2/stats.py.expected" why="unsupported-ext" bytes="575" ext=".expected"/>
<f p="bench/agentloop/editsuite/expected/p2/text.py.expected" why="unsupported-ext" bytes="312" ext=".expected"/>
<f p="bench/agentloop/editsuite/expected/p3/matrix.cpp.expected" why="unsupported-ext" bytes="824" ext=".expected"/>
<f p="bench/agentloop/editsuite/expected/p3/stats.py.expected" why="unsupported-ext" bytes="593" ext=".expected"/>
… [393 more display lines; full output is 42252 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --no-ignore --top-k=3`

*Crawl paths the repo's own .gitignore covers (default honours it and discloses ignored_files=/ignored_dirs= only when it dropped anything — this repo's crawl drops nothing, so the header is identical to the default map's; --skipped's ignore_mode= says which rule applied).*

`````
<!-- ripwire map schema=ripwire.map/v1: ranked symbol map: <f p= layer=> groups <s t= n= sc= k= amb=> rows (k= rank), <c n=> resolved callees; the header comment is data. est_tokens=: price as emitted (an upper bound under compact). root=: p= relative to it. pr_iters=N: PageRank iterations. declined=K: K calls left unbound (no evidence chose one def). external=K: K calls proven outside the tree, no edge. locality_pinned=K: K calls pinned by locality alone (a guess). extent_suspect_syms=K: K defs failed containment, corpus-wide. macro_blanked_files=K: K files indexed from a macro-blanked re-parse. overloads=N: N same-name defs merged in this row; shown= counts each. files=/symbols=: files and symbols indexed; edges= distinct call edges; shown= symbols printed, a merged row counting each def; ambiguous= calls split over several defs, corpus-wide; unresolved= calls with in-tree evidence and no edge (every def language-filtered or unreachable, or binding refused); order= rows by rank (important-first, important-last; (auto:fill) = flipped past a size threshold) or by path (stable). skipped_oversize=K: K files over a size ceiling, not indexed. unindexed=ext:N: N text files of that extension no grammar reads (6 extensions at most). unindexed_exts=E: E such extensions in all, the list cut. sc=: enclosing scope; the full id is p::sc::n (p= of the row or its <f>) and selectors take it. -->
<!-- t=modscope=a-file's-MODULE-SCOPE(n=<file-scope>):the-statements-outside-every-named-definition,where-a-top-level-call-and-an-anonymous-callback-body's-calls-live;a-CALLER-never-a-callee(nothing-in-the-source-can-name-it)-with-no-body-to-expand;a-file-with-no-such-call-has-no-such-row -->
<!-- files=2484 symbols=23851 edges=34236 shown=3 est_tokens=916 ambiguous=10278 unresolved=12878 locality_pinned=12 external=7345 declined=9922 extent_suspect_syms=10 macro_blanked_files=7 skipped_oversize=15 unindexed="txt:73,tsv:49,jsonl:26,scm:23,expected:15,xml:13" unindexed_exts=20 order=important-first -->
<r schema="ripwire.map/v1" root="." est_tokens="916" pr_iters="28">
<f p="src/infra/svector.h" layer="infra">
<s t="method" n="buf" sc="svector" overloads="2" k="0.0072">
</s>
</f>
<f p="src/resolve.h">
<s t="method" n="empty" sc="RubyConstantIndex" k="0.0071">
</s>
</f>
</r>
`````

## `./build/ripwire . --no-stable --top-k=3`

*--no-stable outside --mcp: what the flag does (or says) when there is no stable-by-default ordering to opt out of.*

`````
<!-- ripwire map schema=ripwire.map/v1: ranked symbol map: <f p= layer=> groups <s t= n= sc= k= amb=> rows (k= rank), <c n=> resolved callees; the header comment is data. est_tokens=: price as emitted (an upper bound under compact). root=: p= relative to it. pr_iters=N: PageRank iterations. declined=K: K calls left unbound (no evidence chose one def). external=K: K calls proven outside the tree, no edge. locality_pinned=K: K calls pinned by locality alone (a guess). extent_suspect_syms=K: K defs failed containment, corpus-wide. macro_blanked_files=K: K files indexed from a macro-blanked re-parse. overloads=N: N same-name defs merged in this row; shown= counts each. files=/symbols=: files and symbols indexed; edges= distinct call edges; shown= symbols printed, a merged row counting each def; ambiguous= calls split over several defs, corpus-wide; unresolved= calls with in-tree evidence and no edge (every def language-filtered or unreachable, or binding refused); order= rows by rank (important-first, important-last; (auto:fill) = flipped past a size threshold) or by path (stable). skipped_oversize=K: K files over a size ceiling, not indexed. unindexed=ext:N: N text files of that extension no grammar reads (6 extensions at most). unindexed_exts=E: E such extensions in all, the list cut. sc=: enclosing scope; the full id is p::sc::n (p= of the row or its <f>) and selectors take it. -->
<!-- t=modscope=a-file's-MODULE-SCOPE(n=<file-scope>):the-statements-outside-every-named-definition,where-a-top-level-call-and-an-anonymous-callback-body's-calls-live;a-CALLER-never-a-callee(nothing-in-the-source-can-name-it)-with-no-body-to-expand;a-file-with-no-such-call-has-no-such-row -->
<!-- files=2484 symbols=23851 edges=34236 shown=3 est_tokens=916 ambiguous=10278 unresolved=12878 locality_pinned=12 external=7345 declined=9922 extent_suspect_syms=10 macro_blanked_files=7 skipped_oversize=15 unindexed="txt:73,tsv:49,jsonl:26,scm:23,expected:15,xml:13" unindexed_exts=20 order=important-first -->
<r schema="ripwire.map/v1" root="." est_tokens="916" pr_iters="28">
<f p="src/infra/svector.h" layer="infra">
<s t="method" n="buf" sc="svector" overloads="2" k="0.0072">
</s>
</f>
<f p="src/resolve.h">
<s t="method" n="empty" sc="RubyConstantIndex" k="0.0071">
</s>
</f>
</r>
`````

stderr:

`````
ripwire: --no-stable is read only by --mcp/--listen (it opts out of the stable ordering the server turns on) — it changed nothing here; the CLI map orders important-first unless you pass --order=stable
`````

## `./build/ripwire . --run-trace="cat <scratch>/aux/asan_trace_now.txt; exit 1"`

*EXEC-MODE --from-trace: run a command, and on a non-zero exit map its captured output onto indexed symbols in the same call — the whole fix-loop entry. ripwire exits 4 here because the wrapped command failed, which is the signal, not an incident.*

**exit code: 4**

`````
<ctx schema="ripwire.from-trace/v1" task="run-trace: cat <scratch>/aux/asan_trace_now.txt; exit 1" next="--slice=@src/graph.h:5567" est_tokens="2611">
<!-- ripwire from-trace schema=ripwire.from-trace/v1: trace frames mapped to indexed symbols, innermost first; the innermost in-corpus body included. window: shown= total= capped= (capped=1 cut). est_tokens=: price as emitted (an upper bound under compact). <d r=N>: rank N in this ranking, rows in r= order. <d cx= ccx=>: cyclomatic/cognitive complexity. <d in=N>: N callers in the index (absent: not measured). sc=: enclosing scope; the full id is p::sc::n (p= of the row or its <f>) and selectors take it. next=: the one pasteable follow-up. task=: the trace source this bundle maps, verbatim (a file path, stdin, or an MCP label). src=/format=: the trace read and its dominant frame format, python|asan|node|compiler|generic. frame_lines=/parsed=: frame-shaped input lines / those yielding a path:line; the rest matched no format. in_corpus=: parsed frames in indexed files; always suspects= + merged= + unresolved=. suspects=/merged=/unresolved=: frame rows / folded into a claimed symbol / unresolved rows (indexed file, no def). skipped=N: frames outside every root, listed as skipped rows, never ranked. rank=N: frame order, innermost in-corpus first; p= is the trace's own path:line, defs are sigs l=. resolved_by=name|line: bound by the frame's own name, else by the def enclosing its line. innermost=1: the innermost in-corpus frame (rank 1); its full body is served. run exit=: the command's OWN exit code; signal=: the signal that killed it; timed_out=1: the timeout_s= cap did. run duration_ms=: wall clock, MEASURED, not deterministic; timeout_s=: the cap it ran under. run lines=: non-empty captured lines; bytes=: the whole capture; dropped_bytes=: middle bytes the cap dropped. lines view=tail: the last shown= of total= output lines; view=relevant: shown= of relevant= error/frame-shaped ones. lines relevant=N: captured lines that are error-marked or frame-shaped; the relevant view picks from these. -->
<!-- ledger: budget=7500 bytes (allowance 9583 bytes = ceiling + the single-entry overshoot a whole first signature costs) -->
<run exit="1" duration_ms="48" timeout_s="600" lines="9" bytes="604"/>
<lines view="relevant" shown="7" relevant="7" total="9">
<![CDATA[AddressSanitizer:DEADLYSIGNAL
==41337==ERROR: AddressSanitizer: SEGV on unknown address 0x000000000018 (pc 0x000102f4a1c8 bp 0x00016d2f1a40 sp 0x00016d2f19e0 T0)
    #0 0x102f4a1c8 in rw::rankGraphTeleport(Graph const&, std::vector<float> const&, float) src/graph.h:5567
    #1 0x102f3e884 in rw::rankGraph(Graph const&, float) src/graph.h:5608
    #2 0x102e11f30 in runDefaultMap(MainDispatch const&) src/main.cpp:1631
    #3 0x102e01a44 in main src/main.cpp:3975
    #4 0x1a2b3c0dc in start+0x9dc (dyld:arm64e+0x60dc)]]></lines><trace src="run-trace: cat <scratch>/aux/asan_trace_now.txt; exit 1" format="asan" frame_lines="5" parsed="4" in_corpus="4" skipped="0" merged="0" unresolved="0" suspects … [line truncated: 1470 more bytes on this line]
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
}]]><calls total="8"><c n="biasPrior" l="5524">inline std::vector&lt;float&gt; biasPrior( const Graph&amp; g, const std::vector&lt;float&gt;&amp; p )</c><c n="PROFILE_SCOPE_DESCRIBE" l="1279">#define PROFILE_SCOPE_DESCRIBE( desc )</c><c n="PROFILE_SCOPE_DESCRIBE" l="1293">#define PROFILE_SCOPE_DESCR … [line truncated: 480 more bytes on this line]
`````

## `./build/ripwire . --run-trace="true"`

*A command that exits 0: a minimal success record (exit, measured duration, disclosed output tail) and NO bundle — nothing failed, nothing to map.*

`````
<ctx schema="ripwire.from-trace/v1" task="run-trace: true">
<!-- ripwire from-trace schema=ripwire.from-trace/v1: trace frames mapped to indexed symbols, innermost first; the innermost in-corpus body included. task=: the trace source this bundle maps, verbatim (a file path, stdin, or an MCP label). run exit=: the command's OWN exit code; signal=: the signal that killed it; timed_out=1: the timeout_s= cap did. run duration_ms=: wall clock, MEASURED, not deterministic; timeout_s=: the cap it ran under. run lines=: non-empty captured lines; bytes=: the whole capture; dropped_bytes=: middle bytes the cap dropped. -->
<run exit="0" duration_ms="16" timeout_s="600" lines="0" bytes="0"/>
</ctx>
`````

## `./build/ripwire . --run-trace="sleep 30" --run-timeout=2`

*A command still running at the cap: its process group is killed and the run reports timed_out=1 — an honest timeout, never an empty success.*

**exit code: 4** — **wall time: 2.43s**

`````
<ctx schema="ripwire.from-trace/v1" task="run-trace: sleep 30">
<!-- ripwire from-trace schema=ripwire.from-trace/v1: trace frames mapped to indexed symbols, innermost first; the innermost in-corpus body included. task=: the trace source this bundle maps, verbatim (a file path, stdin, or an MCP label). run duration_ms=: wall clock, MEASURED, not deterministic; timeout_s=: the cap it ran under. run lines=: non-empty captured lines; bytes=: the whole capture; dropped_bytes=: middle bytes the cap dropped. run frames=0: the command FAILED but its output carried no mappable frame, so no bundle follows. -->
<run timed_out="1" signal="9" duration_ms="2002" timeout_s="2" lines="0" bytes="0" frames="0"/>
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

**wall time: 3.98s**

`````
<!-- ripwire quality-panel schema=ripwire.quality-panel/v1: every quality family in ONE report, ranked by distinct families fired: <s p= n= fam= of= fired= join=>; bar_*= thresholds. window: shown= total= capped= has_more= next_offset= offset= limit= (capped=1 cut; next_offset= pastes as offset=). at=: commit+dirty+shallow. root=: p= relative to it. preset=: strict (5 stable families, cut 2), default (6, cut 2), lenient (6, cut 1); selects, never weights. families=6: evidence families: structural lexical confusion historical colocation state. enabled=/enabled_n=: the families this preset COUNTS, and how many. cut=N: distinct enabled families that must fire for a row to rank. cut_reachable=0: cut= exceeds the evaluable families (of=); a corpus fact, never a clean bill of health. eligible=N: functions/methods with a body; ranked= + below_cut= + no_family= = eligible=, always. ranked=N: rows that met the cut (total=); only shown= print, page with offset=. below_cut=N: fired at least one enabled family, but fewer than cut=. no_family=N: no enabled family fired; unavailable= families were never measured. bar_ccx=/bar_loc=/bar_nest=/bar_params=: absolute bars: cognitive complexity, lines, nesting, params. rcut=/rmeasured=: readability decile width (rrank= under it fires) / functions measured. hcut=/hranked=: file churn decile width / files with an in-window commit (hranked=0 voids historical). window=: the git churn window hrank= and churn= are counted over (RELATIVE to this corpus). ccut=/cranked=: colocation decile width / functions reading any outside definition (0 voids it). cfiles=/cscope=: files the confusion atom rules read / eligible symbols in them. lscope=N: symbols the lexical naming rules read. sfiles=/sscope=: files the state lens reads / symbols in them. cells=N: non-local mutable cells the state lens found. tested_scope=N: symbols an indexed test reaches; at 0 no row can carry join=deep+untested. deep_untested=N: rows carrying join=deep+untested across the WHOLE set, not just this page. e f=: the fired family this evidence row belongs to. counted=1: this preset counts the family toward fam=; 0 = fired, not counted. why=: the measurements that crossed (rule*N fired N times; hrank=/churn= are the file's, inherited). -->
<quality_panel schema="ripwire.quality-panel/v1" preset="default" families="6" enabled="structural,lexical,confusion,historical,colocation,state" enabled_n="6" cut="2" cut_reachable="1" eligible="12879" ranked="734" below_cut="4670" no_family="7475" bar_ccx="15" bar_loc="60" bar_nest="4" bar_params= … [line truncated: 326 more bytes on this line]
<s p="src/gitmine.h:1206" n="addRootFilesToGitPathIndex" fam="4" of="6" fired="structural,lexical,confusion,historical">
<e f="structural" counted="1" why="ccx=25 ev=6"/>
<e f="lexical" counted="1" why="naming-wordy"/>
<e f="confusion" counted="1" why="atom-embedded-crement*2"/>
<e f="historical" counted="1" why="hrank=38 churn=59"/>
</s>
<s p="src/graph.h:3578" n="buildGraph" fam="4" of="6" fired="structural,confusion,historical,colocation">
<e f="structural" counted="1" why="ccx=909 loc=1938 nest=8 humps=47 deep=370 ev=127 rrank=0"/>
<e f="confusion" counted="1" why="atom-embedded-crement*5"/>
<e f="historical" counted="1" why="hrank=11 churn=245"/>
<e f="colocation" counted="1" why="crank=23"/>
</s>
<s p="src/ingest_sidecap.h:1730" n="captureTagsFacts" fam="4" of="6" fired="structural,confusion,historical,colocation">
<e f="structural" counted="1" why="ccx=403 loc=677 nest=6 params=11 humps=27 deep=153 ev=38 rrank=12"/>
<e f="confusion" counted="1" why="atom-nested-ternary"/>
<e f="historical" counted="1" why="hrank=24 churn=81"/>
<e f="colocation" counted="1" why="crank=18"/>
</s>
<s p="src/main.cpp:1629" n="runDefaultMap" fam="4" of="6" fired="structural,confusion,historical,colocation" join="deep+untested">
<e f="structural" counted="1" why="ccx=284 loc=1141 nest=4 humps=5 deep=11 ev=19 rrank=4"/>
<e f="confusion" counted="1" why="atom-nested-ternary"/>
<e f="historical" counted="1" why="hrank=6 churn=414"/>
<e f="colocation" counted="1" why="crank=2"/>
</s>
<s p="src/main.cpp:4108" n="dispatchMain" fam="4" of="6" fired="structural,confusion,historical,colocation" join="deep+untested">
<e f="structural" counted="1" why="ccx=471 loc=1482 nest=6 humps=18 deep=77 ev=126 rrank=2"/>
<e f="confusion" counted="1" why="atom-assign-as-value"/>
<e f="historical" counted="1" why="hrank=6 churn=414"/>
… [186 more display lines; full output is 15787 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --biggest-first --limit=8`

*Per-function size ranking, largest Halstead volume/token entropy/lines first — a size proxy, not a readability order (withdrawn, docs/EVALS.md §8) — a RANKING lens, not a grade.*

`````
<!-- ripwire readability schema=ripwire.readability/v1: Posnett/Hindle/Devanbu lens, largest Halstead volume first (a size proxy): <fn p= n= lines= toks= ops= vocab= vol= ent= posnett=>. window: shown= total= capped= has_more= next_offset= offset= limit= (capped=1 cut; next_offset= pastes as offset=). root=: p= relative to it. functions=N: functions and methods measured (bodyless declarations are not). -->
<readability schema="ripwire.readability/v1" functions="12879" shown="8" capped="1" total="12879" has_more="1" next_offset="8" offset="0" limit="8" root=".">
<fn p="src/graph.h:3578" n="buildGraph" lines="1938" toks="10055" ops="6405" vocab="634" vol="93595.3" ent="6.52" posnett="0.000"/>
<fn p="src/mcp.h:1118" n="dispatchMcpLine" lines="1711" toks="8787" ops="5578" vocab="773" vol="84305.3" ent="6.52" posnett="0.000"/>
<fn p="src/main.cpp:4108" n="dispatchMain" lines="1482" toks="7144" ops="4591" vocab="632" vol="66466.2" ent="6.34" posnett="0.000"/>
<fn p="src/verbs_for.h:2221" n="runForLens" lines="1335" toks="6035" ops="3705" vocab="559" vol="55079.7" ent="6.50" posnett="0.000"/>
<fn p="src/main.cpp:1629" n="runDefaultMap" lines="1141" toks="6037" ops="3711" vocab="500" vol="54126.4" ent="6.46" posnett="0.000"/>
<fn p="src/packtask.h:1409" n="packTaskBundleText" lines="829" toks="5752" ops="3518" vocab="524" vol="51960.2" ent="6.55" posnett="0.000"/>
<fn p="src/lexical.h:470" n="lexicalScoresTiered" lines="972" toks="5633" ops="3570" vocab="369" vol="48035.3" ent="6.33" posnett="0.000"/>
<fn p="src/verbs_report.h:3143" n="runStructureText" lines="570" toks="5184" ops="3146" vocab="360" vol="44021.8" ent="6.20" posnett="0.000"/>
</readability>
`````

## `./build/ripwire . --comment-coherence --limit=8`

*Functions WITH a doc comment, most name-restating first: c_coeff (high = the comment repeats the name) and cic (Jaccard of comment vs identifier vocabulary), both reported, never collapsed.*

`````
<!-- ripwire comment-coherence schema=ripwire.comment-coherence/v1: two comment/name content measures per documented function, most name-restating first: <fn p= n= c_coeff= cic=>. window: shown= total= capped= has_more= next_offset= offset= limit= (capped=1 cut; next_offset= pastes as offset=). root=: p= relative to it. documented=N: functions with a doc comment, measured (the rows); a FLOOR when unreadable_files= shows. no_comment=N: eligible symbols with no measurable comment; UNAVAILABLE, never scored as zero. words=/restate=: comment word count (c_coeff= denominator, stopwords kept) / words matching a name word. c_terms=/i_terms=/shared=: comment term set / identifiers the body uses / overlap; cic= shared over union. -->
<comment_coherence schema="ripwire.comment-coherence/v1" documented="3832" no_comment="9047" shown="8" capped="1" total="3832" has_more="1" next_offset="8" offset="0" limit="8" root=".">
<fn p="src/infra/os.h:446" n="socket" c_coeff="1.000" words="1" restate="1" cic="0.000" c_terms="1" i_terms="5" shared="0"/>
<fn p="src/lsp.h:473" n="lspLocationJson" c_coeff="1.000" words="1" restate="1" cic="0.000" c_terms="1" i_terms="26" shared="0"/>
<fn p="src/query.h:264" n="sourceAll" c_coeff="1.000" words="1" restate="1" cic="0.000" c_terms="1" i_terms="12" shared="0"/>
<fn p="src/verbs_quality.h:1771" n="runDmm" c_coeff="1.000" words="1" restate="1" cic="0.029" c_terms="1" i_terms="35" shared="1"/>
<fn p="src/infra/dynamic_map.hpp:1955" n="erase_rec" c_coeff="1.000" words="1" restate="1" cic="0.048" c_terms="1" i_terms="21" shared="1"/>
<fn p="test/verify_os_win32_logic.cpp:249" n="WidePath: separators, the Git Bash drive spelling, and nothing else rewritten" c_coeff="1.000" words="2" restate="2" cic="0.133" c_terms="2" i_terms="15" shared="2"/>
<fn p="test/verify_os_win32_logic.cpp:191" n="utf: every scalar value round-trips UTF-8 -&gt; UTF-16 -&gt; UTF-8 byte-exactly" c_coeff="1.000" words="5" restate="5" cic="0.150" c_terms="4" i_terms="19" shared="3"/>
<fn p="test/lintfix/bad.cpp:23" n="emptyCatchFunc" c_coeff="1.000" words="2" restate="2" cic="0.400" c_terms="2" i_terms="5" shared="2"/>
</comment_coherence>
`````

## `./build/ripwire . --context-ratio --limit=8`

*The local-reasoning lens: to understand this symbol, how much must you know that is NOT in front of you (ent_ratio= edge share, read_ratio= token-weighted).*

`````
<!-- ripwire context-ratio schema=ripwire.context-ratio/v1: LOCAL-REASONING lens: the share of a unit's context outside its file: <s p= n= sites= ents_out= ent_ratio= read_ratio=>. window: total= has_more= next_offset= offset= limit= (capped=1 cut; next_offset= pastes as offset=). syms_capped=/files_capped=/defs_capped=: 1 = cut. counts_floor=1: every count is a FLOOR, never a total. root=: p= relative to it. units=N: symbols measured (the s row population). file_units=N: files measured (the f row population). defs_per_name_cap=N: most defs one name adds (lowest ids); defs_capped=1 = cut, ents=/rtok= floors. body_bytes_per_token=: the bytes-per-token rate rtok= is estimated at. shown_syms=N: symbol rows printed; the rest page with offset=next_offset. shown_files=N: file rows printed (fixed cap 40, not paged); files_capped=1 = rows dropped. ents=N: distinct in-corpus defs its reference sites resolve to, by name (a FLOOR). files=N: distinct files holding those defs (a FLOOR). files_out=N: of files=, those other than the unit's own file. rtok=N: est. tokens of every resolved def, what a reader must read. rtok_out=N: the part of rtok= defined outside the unit's own file. ext=N: referenced names with no in-corpus def; mostly locals/params, NOT external deps; in neither ratio. amb_names=N: referenced names with 2+ defs, each counted (per name; not the map's per-call amb=). ents=N: distinct in-corpus defs the file's sites resolve to (a FLOOR; a union, not the sum of s rows). files=N: distinct files holding those defs (a FLOOR). files_out=N: of files=, those other than this file. rtok=N: est. tokens of every resolved def, what a reader must read. rtok_out=N: the part of rtok= defined outside this file. ext=N: referenced names with no in-corpus def; mostly locals/params, NOT external deps; in neither ratio. amb_names=N: referenced names with 2+ defs, each counted (per name; not the map's per-call amb=). -->
<contextratio schema="ripwire.context-ratio/v1" units="18992" file_units="2094" defs_per_name_cap="8" body_bytes_per_token="3.80" shown_syms="8" syms_capped="1" shown_files="40" files_capped="1" total="18992" has_more="1" next_offset="8" offset="0" limit="8" defs_capped="1" counts_floor="1" root="." … [line truncated: 1 more bytes on this line]
<s p="src/main.cpp:4108" n="dispatchMain" t="fn" sites="1144" ents="194" ents_out="172" ent_ratio="0.887" files="58" files_out="57" rtok="259352" rtok_out="224092" read_ratio="0.864" ext="134" amb_names="23"/>
<s p="src/mcp.h:1118" n="dispatchMcpLine" t="fn" sites="1357" ents="208" ents_out="182" ent_ratio="0.875" files="39" files_out="38" rtok="83386" rtok_out="78279" read_ratio="0.939" ext="168" amb_names="18"/>
<s p="src/main.cpp:1629" n="runDefaultMap" t="fn" sites="1075" ents="123" ents_out="113" ent_ratio="0.919" files="34" files_out="33" rtok="81419" rtok_out="77112" read_ratio="0.947" ext="145" amb_names="15"/>
<s p="src/mcpverbs.h:3896" n="computeQualityDelta" t="fn" sites="66" ents="42" ents_out="38" ent_ratio="0.905" files="15" files_out="14" rtok="57094" rtok_out="56223" read_ratio="0.985" ext="7" amb_names="8"/>
<s p="src/mcpverbs.h:1818" n="forTaskText" t="fn" sites="644" ents="150" ents_out="146" ent_ratio="0.973" files="40" files_out="39" rtok="56520" rtok_out="55905" read_ratio="0.989" ext="102" amb_names="20"/>
<s p="src/mcpverbs.h:4149" n="packTaskText" t="fn" sites="165" ents="43" ents_out="43" ent_ratio="1.000" files="20" files_out="20" rtok="48261" rtok_out="48261" read_ratio="1.000" ext="27" amb_names="7"/>
<s p="src/mcpverbs.h:4322" n="editCheckText" t="fn" sites="46" ents="37" ents_out="37" ent_ratio="1.000" files="21" files_out="21" rtok="48234" rtok_out="48234" read_ratio="1.000" ext="6" amb_names="7"/>
<s p="src/mcpserver.h:418" n="runMcpHttp" t="fn" sites="235" ents="74" ents_out="64" ent_ratio="0.865" files="18" files_out="17" rtok="48037" rtok_out="45823" read_ratio="0.954" ext="31" amb_names="13"/>
<f p="src/main.cpp" sites="3963" ents="469" ents_out="396" ent_ratio="0.844" files="97" files_out="96" rtok="437127" rtok_out="368305" read_ratio="0.843" ext="559" amb_names="46"/>
<f p="src/mcpverbs.h" sites="4809" ents="502" ents_out="438" ent_ratio="0.873" files="89" files_out="88" rtok="301597" rtok_out="247830" read_ratio="0.822" ext="580" amb_names="46"/>
<f p="src/verbs_for.h" sites="2929" ents="260" ents_out="204" ent_ratio="0.785" files="60" files_out="59" rtok="122046" rtok_out="98390" read_ratio="0.806" ext="358" amb_names="26"/>
<f p="src/quality.h" sites="5116" ents="513" ents_out="281" ent_ratio="0.548" files="72" files_out="71" rtok="132055" rtok_out="85806" read_ratio="0.650" ext="615" amb_names="65"/>
<f p="src/mcp.h" sites="1930" ents="275" ents_out="220" ent_ratio="0.800" files="47" files_out="46" rtok="130859" rtok_out="83174" read_ratio="0.636" ext="246" amb_names="23"/>
<f p="src/verbs_navigate.h" sites="3290" ents="300" ents_out="279" ent_ratio="0.930" files="68" files_out="67" rtok="89114" rtok_out="80469" read_ratio="0.903" ext="310" amb_names="31"/>
<f p="src/verbs_change.h" sites="1397" ents="234" ents_out="208" ent_ratio="0.889" files="61" files_out="60" rtok="83545" rtok_out="78099" read_ratio="0.935" ext="141" amb_names="28"/>
<f p="src/mcpindex.h" sites="738" ents="199" ents_out="162" ent_ratio="0.814" files="43" files_out="42" rtok="68636" rtok_out="61581" read_ratio="0.897" ext="142" amb_names="35"/>
<f p="src/verbs_quality.h" sites="1721" ents="242" ents_out="201" ent_ratio="0.831" files="60" files_out="59" rtok="75924" rtok_out="60946" read_ratio="0.803" ext="175" amb_names="27"/>
<f p="src/verbs_report.h" sites="4123" ents="267" ents_out="220" ent_ratio="0.824" files="55" files_out="54" rtok="71936" rtok_out="50616" read_ratio="0.704" ext="429" amb_names="28"/>
<f p="src/editpreview.h" sites="497" ents="113" ents_out="107" ent_ratio="0.947" files="38" files_out="37" rtok="51793" rtok_out="49462" read_ratio="0.955" ext="81" amb_names="19"/>
<f p="src/mcpserver.h" sites="471" ents="107" ents_out="91" ent_ratio="0.850" files="28" files_out="27" rtok="50115" rtok_out="47390" read_ratio="0.946" ext="70" amb_names="20"/>
<f p="src/ingest_sidecap.h" sites="1832" ents="267" ents_out="208" ent_ratio="0.779" files="52" files_out="51" rtok="57695" rtok_out="44953" read_ratio="0.779" ext="241" amb_names="30"/>
<f p="src/graph.h" sites="6693" ents="449" ents_out="279" ent_ratio="0.621" files="72" files_out="71" rtok="84719" rtok_out="42811" read_ratio="0.505" ext="714" amb_names="52"/>
<f p="src/packtask.h" sites="1797" ents="211" ents_out="161" ent_ratio="0.763" files="43" files_out="42" rtok="54755" rtok_out="42558" read_ratio="0.777" ext="238" amb_names="25"/>
<f p="test/verify_csr.cpp" sites="210" ents="45" ents_out="42" ent_ratio="0.933" files="20" files_out="19" rtok="37035" rtok_out="36290" read_ratio="0.980" ext="34" amb_names="13"/>
<f p="src/ingest_parsepool.h" sites="735" ents="144" ents_out="133" ent_ratio="0.924" files="39" files_out="38" rtok="42084" rtok_out="35072" read_ratio="0.833" ext="117" amb_names="25"/>
<f p="src/ingest.cpp" sites="384" ents="146" ents_out="137" ent_ratio="0.938" files="43" files_out="42" rtok="32422" rtok_out="31215" read_ratio="0.963" ext="128" amb_names="24"/>
<f p="src/partition.h" sites="526" ents="114" ents_out="98" ent_ratio="0.860" files="27" files_out="26" rtok="34522" rtok_out="30832" read_ratio="0.893" ext="78" amb_names="17"/>
<f p="src/tracelocus.h" sites="1074" ents="163" ents_out="132" ent_ratio="0.810" files="43" files_out="42" rtok="35266" rtok_out="28413" read_ratio="0.806" ext="143" amb_names="19"/>
… [21 more display lines; full output is 11209 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --nonlocal-state --limit=8`

*Per function, the non-local MUTABLE state it can reach (transitively), most writes first — unsound by construction, and the legend says where.*

**wall time: 3.31s**

`````
<!-- ripwire nonlocal-state schema=ripwire.nonlocal-state/v1: per function, the non-local MUTABLE state it reaches: <fn p= n= writes= reads=> over <cell n= p= dir= via=> rows. window: shown= total= capped= has_more= next_offset= offset= limit= (capped=1 cut; next_offset= pastes as offset=). cells_capped=: 1 = cut. counts_floor=1: every count is a FLOOR, never a total. graph_ambiguous=/graph_unresolved=: resolver gauge. graph_unindexed=N: N files no grammar could read (the map header's unindexed=); their calls raise neither gauge. root=: p= relative to it. cells=N: mutable non-local cells found in the corpus (globals, statics, Python module globals; FLOOR). functions=N: functions reaching at least one cell, directly or via callees (all rows, before paging). direct_writes=/direct_reads=: the writes=/reads= cells this function's OWN body writes/reads. cells_total=N: distinct cells reached (read and written counts once); at most 12 cell rows print. at=/at_dir=: one own-body use site (may be more) and what own-body sites do (can be narrower than dir=). cells_shown=/cells_capped=1: only this many of cells_total= cell rows print (cap 12). unanalyzed_langs=/unanalyzed_files=: indexed languages (and their files) this lens skips; NOT zero cells. -->
<nonlocal_state schema="ripwire.nonlocal-state/v1" cells="925" functions="705" shown="8" capped="1" total="705" has_more="1" next_offset="8" offset="0" limit="8" graph_ambiguous="10278" graph_unresolved="12878" graph_unindexed="237" counts_floor="1" unanalyzed_langs="c,go,rust,javascript,typescript, … [line truncated: 98 more bytes on this line]
<fn p="bench/bench_svector_wave.cpp:346" n="main" writes="8" reads="14" direct_writes="0" direct_reads="4" cells_total="14" cells_shown="12" cells_capped="1">
<cell n="kNames" p="bench/bench_svector_wave.cpp:98" dir="rw" at="bench/bench_svector_wave.cpp:358" at_dir="r"/>
<cell n="kPush" p="bench/bench_svector_wave.cpp:99" dir="rw" at="bench/bench_svector_wave.cpp:358" at_dir="r"/>
<cell n="kReads" p="bench/bench_svector_wave.cpp:100" dir="rw" at="bench/bench_svector_wave.cpp:358" at_dir="r"/>
<cell n="kSamples" p="bench/bench_svector_wave.cpp:101" dir="rw" at="bench/bench_svector_wave.cpp:358" at_dir="r"/>
<cell n="g_api" p="src/infra/profilePmc.h:139" dir="rw" via="ensure_thread_counting"/>
<cell n="g_keyOf" p="bench/bench_svector_wave.cpp:145" dir="rw" via="regenerate"/>
<cell n="g_perf" p="src/infra/profilePmc.h:286" dir="rw" via="ensure_thread_counting"/>
<cell n="g_readOf" p="bench/bench_svector_wave.cpp:146" dir="rw" via="regenerate"/>
<cell n="g_arm" p="bench/bench_svector_wave.cpp:65" dir="r" via="runArm"/>
<cell n="g_bytes" p="bench/bench_svector_wave.cpp:67" dir="r" via="runArm"/>
<cell n="g_count" p="bench/bench_svector_wave.cpp:66" dir="r" via="runArm"/>
<cell n="g_once" p="src/infra/profilePmc.h:287" dir="r" via="ensure_thread_counting"/>
</fn>
<fn p="bench/bench_svector_wave.cpp:295" n="sweep" writes="6" reads="13" direct_writes="4" direct_reads="1" cells_total="13" cells_shown="12" cells_capped="1">
<cell n="kNames" p="bench/bench_svector_wave.cpp:98" dir="rw" at="bench/bench_svector_wave.cpp:317" at_dir="w"/>
<cell n="kPush" p="bench/bench_svector_wave.cpp:99" dir="rw" at="bench/bench_svector_wave.cpp:318" at_dir="w"/>
<cell n="kReads" p="bench/bench_svector_wave.cpp:100" dir="rw" at="bench/bench_svector_wave.cpp:319" at_dir="rw"/>
<cell n="kSamples" p="bench/bench_svector_wave.cpp:101" dir="rw" at="bench/bench_svector_wave.cpp:313" at_dir="w"/>
<cell n="g_keyOf" p="bench/bench_svector_wave.cpp:145" dir="rw" via="regenerate"/>
<cell n="g_readOf" p="bench/bench_svector_wave.cpp:146" dir="rw" via="regenerate"/>
<cell n="g_api" p="src/infra/profilePmc.h:139" dir="r" via="read"/>
<cell n="g_arm" p="bench/bench_svector_wave.cpp:65" dir="r" via="runArm"/>
<cell n="g_bytes" p="bench/bench_svector_wave.cpp:67" dir="r" via="runArm"/>
<cell n="g_count" p="bench/bench_svector_wave.cpp:66" dir="r" via="runArm"/>
<cell n="g_perf" p="src/infra/profilePmc.h:286" dir="r" via="read"/>
<cell n="g_pool" p="bench/bench_svector_wave.cpp:144" dir="r" via="regenerate"/>
</fn>
… [41 more display lines; full output is 7593 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --ensemble --limit=8`

*The family join: per function, which of four orthogonal evidence families fire, ranked by how many agree.*

**wall time: 2.62s**

`````
<!-- ripwire ensemble schema=ripwire.ensemble/v1: four orthogonal evidence families joined, ranked by DISTINCT families fired (no composite score): <s p= n= fam= of= fired=>. window: total= has_more= next_offset= offset= limit= (capped=1 cut; next_offset= pastes as offset=). syms_capped=/files_capped=: 1 = cut. at=: commit+dirty+shallow. root=: p= relative to it. eligible=N: functions and methods with a body, the denominator; ranked + no_family = eligible. no_family=N: eligible symbols where no family fired. bar_ccx=/bar_loc=/bar_nest=/bar_params=: absolute structural bars: cognitive cx, lines, nesting, params. rcut=N: ranks the worst readability decile covers (1 to 40); rrank= inside it fires structural. rmeasured=N: functions the readability lens measured. hcut=N: file ranks the worst churn decile covers (1 to 40); hrank= inside it fires historical. hranked=N: files with any in-window commit; 0 = historical family unavailable. cfiles=N: indexed files the confusion (atom) pack can read: C/C++/ObjC/CUDA. cscope=N: eligible symbols in those files; 0 = confusion family unavailable. lscope=N: eligible symbols in a language the naming pack reads; 0 = lexical family unavailable. shown_syms=N: symbol rows printed; the rest page with offset=next_offset. shown_files=N: file rows printed (fixed cap 20, not paged); files_capped=1 = rows dropped. e f=: the fired family: structural, lexical, confusion or historical. why=: the measurements that crossed, space separated; rule*N = that rule fired N times. top=: the file's most corroborated symbol (most families on one symbol). top_l=: that symbol's line. top_fam=N: families fired on top=, the stronger claim; file rows rank by it. union_fam=N: distinct families firing anywhere in the file (weaker: may be different symbols). union=: the names of those families. syms=N: symbols in the file where at least one family fired. families=N: evidence families joined; ranked=N: symbols at least one fired on; window=: the git span the historical family read. -->
<ensemble schema="ripwire.ensemble/v1" families="4" eligible="12879" ranked="5082" no_family="7797" bar_ccx="15" bar_loc="60" bar_nest="4" bar_params="5" rcut="40" rmeasured="12879" hcut="40" hranked="2484" window="12mo" cfiles="632" cscope="6916" lscope="12879" shown_syms="8" syms_capped="1" shown_ … [line truncated: 115 more bytes on this line]
<s p="src/gitmine.h:1206" n="addRootFilesToGitPathIndex" fam="4" of="4" fired="structural,lexical,confusion,historical">
<e f="structural" why="ccx=25 ev=6"/>
<e f="lexical" why="naming-wordy"/>
<e f="confusion" why="atom-embedded-crement*2"/>
<e f="historical" why="hrank=38 churn=59"/>
</s>
<s p="src/serialize.h:7908" n="packDeps" fam="4" of="4" fired="structural,lexical,confusion,historical">
<e f="structural" why="ccx=120 loc=294 nest=5 params=16 humps=4 deep=14 ev=5 rrank=22"/>
<e f="lexical" why="naming-confusable"/>
<e f="confusion" why="atom-nested-ternary*2"/>
<e f="historical" why="hrank=10 churn=249"/>
</s>
<s p="src/compactlegend.h:1502" n="payloadSubCapAttrs" fam="3" of="4" fired="structural,confusion,historical">
<e f="structural" why="ccx=45 nest=6 humps=2 deep=11"/>
<e f="confusion" why="atom-assign-as-value"/>
<e f="historical" why="hrank=13 churn=185"/>
</s>
<s p="src/compactlegend.h:2056" n="applyCompactDialectOnce" fam="3" of="4" fired="structural,confusion,historical">
<e f="structural" why="ccx=47 loc=113 nest=4 humps=1 deep=1 ev=3"/>
<e f="confusion" why="atom-nested-ternary"/>
<e f="historical" why="hrank=13 churn=185"/>
</s>
<s p="src/crossref.h:2373" n="evalStray" fam="3" of="4" fired="structural,confusion,historical">
<e f="structural" why="ccx=23 loc=86 ev=9"/>
<e f="confusion" why="atom-assign-as-value"/>
<e f="historical" why="hrank=34 churn=68"/>
</s>
<s p="src/crossref.h:2981" n="writeWhereisRows" fam="3" of="4" fired="structural,lexical,historical">
… [35 more display lines; full output is 7334 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --field-affinity`

*The cache-locality lens over every aggregate: fields READ TOGETHER but declared FAR APART (split-line / straddle findings, Chilimbi separation weight) — advice only, never a rewrite.*

**wall time: 1.78s**

`````
<!-- ripwire field-affinity schema=ripwire.field-affinity/v1: fields read together but declared far apart vs 64-byte lines: <s n= p=> structs, <pair a= b= fns= dist=>, <finding k= f= g=>. window: shown= capped= (capped=1 cut). counts_floor=1: every count is a FLOOR, never a total. root=: p= relative to it. block=64: ASSUMED cache-line bytes; all geometry (dist= wt= ln= lines= findings) is against it. model=lp64-approx: sizes/offsets are the layout verb's LP64 standard-layout MODEL, not the real ABI. weighting=fanin-floor: w= sums 1 + fan-in per co-accessing fn; a reachability proxy, not a frequency. aggregates=N: C-family structs/classes the layout model located a body for (the scanned universe). files=N: C-family files declaring at least one struct/class the modelling pass visited. fns_scanned=N: C-family functions/methods with a readable body scanned for dot/arrow member accesses. accesses=N: member-access sites tied to one aggregate field (FLOOR: bare in-method names uncounted). amb_skipped=N: access sites REFUSED, not guessed: 2+ aggregates declare that field name; in no count here. structs=N: aggregates with 1+ attributed access; the top 20 by sepcost= print (shown=/capped=). findings=N: split-line + straddle findings over ALL structs=, not just the printed rows. min_fns=2: a pair fires split-line only when co-accessed by this many distinct functions. as_loops=N: for-loops the static advance-shape pass classified corpus-wide; report-only, never ranks. as_index=/as_chase=/as_mixed=/as_unknown=: as_loops= by advance shape (chase = pointer chase). agg=: the aggregate keyword (struct, class ...). modeled=1: layout model placed the fields; 0 = affinity only, no geometry, no finding (why= says why). fields=N: fields declared (before the touched-only filter). touched=N: fields with 1+ attributed access; at most 32 f rows print. pairs=N: co-accessed field pairs in all; at most 12 pair rows print (most fns= first). sepcost=: sum over measured pairs of fns x (1 - wt); the struct ranking key. findings=N: this struct's findings, every one printed. size=/align=/lines=: modeled sizeof, alignment, cache lines spanned (modeled=1 only). acc=N: member-access sites attributed to this field (FLOOR). sz=B: the field's modeled size in bytes (absent when the model could not size it). off=/ln=: modeled byte offset and its cache line (off/64); placed=0 instead when the model refused. w=: sum of 1 + fan-in over the co-accessing functions; a static reachability proxy, never a frequency. wt=: separation weight (64 - dist)/64, 0.00 = the two can never share a line; measured=0 instead when unplaced. wt=0.00: split-line fires only when the pair can never share a 64-byte line. w=: the split-line pair's 1 + fan-in weight sum (proxy); straddle rows carry none. off=/sz=/crosses=: straddle field offset, size, and the line its last byte lands on (lines start at off/64). fanin=N: this function's caller count (the w= proxy input). touched=N: distinct fields of this struct the function touches (named in f=); at most 8 fn rows of fns= print. scope=: the function's PROFILE_SCOPE description (first 120 chars), a counter to confirm with. scopes=N: distinct PROFILE_SCOPEs among the co-accessing functions (the scope children). status=: instrumented (a scope exists to measure) or uninstrumented (no witness yet). counter=: the hardware counter to compare across the two layouts. hint=: how to add the missing instrumentation (uninstrumented only). as_stem_ambiguous=/as_stem_unowned=/as_stem_nonptr=: chase names REFUSED - 2+ owners / no owner / owner type has no pointer marker. -->
<fieldaffinity schema="ripwire.field-affinity/v1" block="64" model="lp64-approx" counts_floor="1" weighting="fanin-floor" aggregates="1426" files="313" fns_scanned="7401" accesses="10390" amb_skipped="23901" structs="699" shown="20" capped="1" findings="19" min_fns="2" as_loops="2384" as_index="8" a … [line truncated: 113 more bytes on this line]
<s n="MainDispatch" p="src/main.cpp" l="496" agg="struct" modeled="1" fields="21" touched="15" fns="21" pairs="69" sepcost="101.62" findings="9" size="168" align="8" lines="3">
<f n="multiRoot" acc="12" fns="10" sz="1" off="32" ln="0"/>
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
<f n="notesPtr" acc="11" fns="7" sz="8" off="136" ln="2"/>
<f n="grepPhases" acc="1" fns="1" sz="8" off="152" ln="2"/>
<f n="valueUses" acc="2" fns="2" sz="1" off="160" ln="2"/>
<pair a="ampPtr" b="testedPtr" fns="7" w="7" dist="16" wt="0.75"/>
<pair a="testedPtr" b="notesPtr" fns="6" w="6" dist="48" wt="0.25"/>
<pair a="fanInPtr" b="testedPtr" fns="6" w="6" dist="32" wt="0.50"/>
<pair a="fanInPtr" b="ampPtr" fns="6" w="6" dist="16" wt="0.75"/>
<pair a="multiRoot" b="ws" fns="6" w="6" dist="8" wt="0.88"/>
<pair a="redactCounts" b="redactPtr" fns="6" w="6" dist="8" wt="0.88"/>
<pair a="fanInPtr" b="notesPtr" fns="5" w="5" dist="80" wt="0.00"/>
<pair a="fanInPtr" b="redactPtr" fns="5" w="5" dist="72" wt="0.00"/>
<pair a="fanInPtr" b="redactCounts" fns="5" w="5" dist="64" wt="0.00"/>
<pair a="ampPtr" b="notesPtr" fns="5" w="5" dist="64" wt="0.00"/>
<pair a="ampPtr" b="redactPtr" fns="5" w="5" dist="56" wt="0.12"/>
<pair a="fanInPtr" b="impurePtr" fns="5" w="5" dist="48" wt="0.25"/>
… [509 more display lines; full output is 45771 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --field-affinity=Symbol`

*The same lens narrowed to ONE struct — the one --layout=Symbol shows the offsets for.*

**wall time: 1.41s**

`````
<!-- ripwire field-affinity schema=ripwire.field-affinity/v1: fields read together but declared far apart vs 64-byte lines: <s n= p=> structs, <pair a= b= fns= dist=>, <finding k= f= g=>. window: shown= capped= (capped=1 cut). counts_floor=1: every count is a FLOOR, never a total. root=: p= relative to it. sym=: the struct asked for; only its own fields and pairs are reported. block=64: ASSUMED cache-line bytes; all geometry (dist= wt= ln= lines= findings) is against it. model=lp64-approx: sizes/offsets are the layout verb's LP64 standard-layout MODEL, not the real ABI. weighting=fanin-floor: w= sums 1 + fan-in per co-accessing fn; a reachability proxy, not a frequency. aggregates=N: C-family structs/classes the layout model located a body for (the scanned universe). files=N: C-family files declaring at least one struct/class the modelling pass visited. fns_scanned=N: C-family functions/methods with a readable body scanned for dot/arrow member accesses. accesses=N: member-access sites tied to one aggregate field (FLOOR: bare in-method names uncounted). amb_skipped=N: access sites REFUSED, not guessed: 2+ aggregates declare that field name; in no count here. structs=N: aggregates with 1+ attributed access; the top 20 by sepcost= print (shown=/capped=). findings=N: split-line + straddle findings over ALL structs=, not just the printed rows. min_fns=2: a pair fires split-line only when co-accessed by this many distinct functions. as_loops=N: for-loops the static advance-shape pass classified corpus-wide; report-only, never ranks. as_index=/as_chase=/as_mixed=/as_unknown=: as_loops= by advance shape (chase = pointer chase). agg=: the aggregate keyword (struct, class ...). modeled=1: layout model placed the fields; 0 = affinity only, no geometry, no finding (why= says why). fields=N: fields declared (before the touched-only filter). touched=N: fields with 1+ attributed access; at most 32 f rows print. pairs=N: co-accessed field pairs in all; at most 12 pair rows print (most fns= first). sepcost=: sum over measured pairs of fns x (1 - wt); the struct ranking key. findings=N: this struct's findings, every one printed. acc=N: member-access sites attributed to this field (FLOOR). sz=B: the field's modeled size in bytes (absent when the model could not size it). w=: sum of 1 + fan-in over the co-accessing functions; a static reachability proxy, never a frequency. fanin=N: this function's caller count (the w= proxy input). touched=N: distinct fields of this struct the function touches (named in f=); at most 8 fn rows of fns= print. scope=: the function's PROFILE_SCOPE description (first 120 chars), a counter to confirm with. scopes=N: distinct PROFILE_SCOPEs among the co-accessing functions (the scope children). status=: instrumented (a scope exists to measure) or uninstrumented (no witness yet). counter=: the hardware counter to compare across the two layouts. placed=0: the model gave no offset for this field; no off=/ln= and no geometry for its pairs. measured=0: an endpoint is unplaced, so no dist=/wt= and no finding for this pair. as_stem_ambiguous=/as_stem_unowned=/as_stem_nonptr=: chase names REFUSED - 2+ owners / no owner / owner type has no pointer marker. -->
<fieldaffinity schema="ripwire.field-affinity/v1" block="64" model="lp64-approx" counts_floor="1" weighting="fanin-floor" aggregates="1426" files="313" fns_scanned="7401" accesses="10390" amb_skipped="23901" structs="1" shown="1" capped="0" findings="0" min_fns="2" as_loops="2384" as_index="8" as_ch … [line truncated: 122 more bytes on this line]
<s n="Symbol" p="src/model.h" l="427" agg="struct" modeled="0" fields="23" touched="2" fns="88" pairs="1" sepcost="0.00" findings="0" why="compound-type,unknown-type,bitfield">
<f n="extentSuspect" acc="15" fns="9" sz="1" placed="0"/>
<f n="sigStartByte" acc="211" fns="82" sz="4" placed="0"/>
<pair a="sigStartByte" b="extentSuspect" fns="3" w="3" measured="0"/>
<fn n="markExtentSuspects" p="src/ingest_model.h" l="580" fanin="0" touched="2" f="sigStartByte,extentSuspect" scope="ingest/build-model: extent honesty (containment check)"/>
<fn n="packSignatures" p="src/serialize.h" l="4640" fanin="0" touched="2" f="sigStartByte,extentSuspect"/>
<fn n="packBodies" p="src/serialize.h" l="6217" fanin="0" touched="2" f="sigStartByte,extentSuspect"/>
<fn n="buildCandidates" p="src/abicheck.h" l="303" fanin="0" touched="1" f="sigStartByte"/>
<fn n="OwnerIndex" p="src/atoms.h" l="167" fanin="0" touched="1" f="sigStartByte"/>
<fn n="ownerOf" p="src/atoms.h" l="174" fanin="0" touched="1" f="sigStartByte"/>
<fn n="tsContractSignatures" p="src/callhierarchy.h" l="135" fanin="0" touched="1" f="sigStartByte"/>
<fn n="computeCommentCoherence" p="src/commentcoherence.h" l="178" fanin="0" touched="1" f="sigStartByte"/>
<validate scopes="9" status="instrumented" counter="l1d-cache-misses">
<scope n="buildGraph/2e: Java Class::method members (issue #74)"/>
<scope n="buildGraph/2g: JS/TS import tables"/>
<scope n="buildGraph/2h: FE-A false-edge rules"/>
<scope n="ingest/build-model: extent honesty (containment check)"/>
<scope n="ingest/build-model: lex stats CSR + file signatures (B0)"/>
<scope n="lexical: pass 2 via persisted subtoken stats (cached tf/dl, no corpus re-tokenize)"/>
<scope n="lint: mergeCachePack"/>
<scope n="naminglens: checkScopeGroups (series + confusable)"/>
<scope n="naminglens: final sort"/>
</validate>
</s>
</fieldaffinity>
`````

## `./build/ripwire . --naming-consistency --limit=8`

*The corpus's OWN case-convention vote per (language, kind) group; off-convention names get a mechanical propose= (a suggestion, never a blind rename).*

`````
<!-- ripwire naming-consistency schema=ripwire.naming-consistency/v1: the corpus's case-convention vote per (language, kind): <g lang= kind= style= agree= total=>, <f p= n= propose=> outliers. window: shown= total= capped= has_more= next_offset= offset= limit= (capped=1 cut; next_offset= pastes as offset=). root=: p= relative to it. component_exempt=N: PascalCase .tsx/.jsx functions (read as JSX components by extension alone), kept out of voting and flagging. groups=N: (language, kind) groups with at least one styled name. candidates=N: multi-token styled names scanned. decided=N: groups whose leading style cleared both the sample and agreement floors. flagged=N: off-convention names in decided groups (the f rows). g why=insufficient-sample|no-clear-convention: which bar a style=UNAVAILABLE group missed. -->
<naming-consistency schema="ripwire.naming-consistency/v1" groups="32" candidates="9998" decided="9" flagged="442" component_exempt="8" shown="8" capped="1" total="442" has_more="1" next_offset="8" offset="0" limit="8" root=".">
<g lang="cpp" kind="fn" style="camel" agree="5108" total="5442"/>
<g lang="cpp" kind="var" style="camel" agree="1216" total="1228"/>
<g lang="py" kind="fn" style="snake" agree="763" total="786"/>
<g lang="py" kind="var" style="UNAVAILABLE" why="no-clear-convention" total="472"/>
<g lang="ts" kind="fn" style="camel" agree="88" total="90"/>
<g lang="ts" kind="var" style="UNAVAILABLE" why="insufficient-sample" total="5"/>
<g lang="go" kind="fn" style="UNAVAILABLE" why="no-clear-convention" total="20"/>
<g lang="go" kind="var" style="UNAVAILABLE" why="insufficient-sample" total="2"/>
<g lang="rs" kind="fn" style="UNAVAILABLE" why="no-clear-convention" total="57"/>
<g lang="rs" kind="var" style="UNAVAILABLE" why="insufficient-sample" total="4"/>
<g lang="swift" kind="fn" style="UNAVAILABLE" why="no-clear-convention" total="22"/>
<g lang="swift" kind="var" style="UNAVAILABLE" why="insufficient-sample" total="17"/>
<g lang="objc" kind="fn" style="UNAVAILABLE" why="insufficient-sample" total="16"/>
<g lang="js" kind="fn" style="camel" agree="64" total="64"/>
<g lang="js" kind="var" style="UNAVAILABLE" why="insufficient-sample" total="3"/>
<g lang="sh" kind="fn" style="UNAVAILABLE" why="no-clear-convention" total="1178"/>
<g lang="java" kind="fn" style="camel" agree="68" total="68"/>
<g lang="java" kind="var" style="UNAVAILABLE" why="insufficient-sample" total="1"/>
<g lang="rb" kind="fn" style="snake" agree="33" total="33"/>
<g lang="rb" kind="var" style="UNAVAILABLE" why="insufficient-sample" total="17"/>
<g lang="cs" kind="fn" style="UNAVAILABLE" why="insufficient-sample" total="16"/>
<g lang="cs" kind="var" style="UNAVAILABLE" why="insufficient-sample" total="3"/>
<g lang="c" kind="fn" style="camel" agree="313" total="324"/>
<g lang="c" kind="var" style="UNAVAILABLE" why="insufficient-sample" total="6"/>
<g lang="php" kind="fn" style="UNAVAILABLE" why="insufficient-sample" total="9"/>
<g lang="php" kind="var" style="UNAVAILABLE" why="insufficient-sample" total="1"/>
<g lang="lua" kind="fn" style="UNAVAILABLE" why="insufficient-sample" total="15"/>
<g lang="ex" kind="fn" style="snake" agree="20" total="20"/>
… [13 more display lines; full output is 4383 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --naming-calibration`

*Score the naming-* rules against this repo's own rename history: proxy=old/(old+new) per rule, 0.50 = chance; read pairs= (sample size) first.*

**wall time: 12.45s**

`````
<!-- ripwire naming-calibration schema=ripwire.naming-calibration/v1: naming lint rules scored against this repo's OWN rename history (a noisy proxy): <r n= old= new= fired= proxy=>. at=: commit+dirty+shallow. probed=0: no history to mine, nothing scored (r= says why); 1 = the git walk ran. pairs=N: labelled rename pairs that survived the join, the SAMPLE SIZE; a small one means nothing. candidates=N: raw substitutions mined from the patch stream before the join; FLOOR when truncated=1. commits=N: non-merge commits walked (the walk stops at 40000). hunks=N: diff hunks with content on both sides. wide_hunks=N: hunks DROPPED for exceeding the 24-line per-side pairing cap; never mined. drop_old_alive=N: candidates dropped: the old spelling is still an indexed name. drop_new_absent=N: candidates dropped: the new spelling is no eligible indexed symbol at HEAD. drop_ambiguous=N: candidates dropped: a name on both sides of several (split, rework, revert). drop_old_skipped=N: candidates dropped: the lens skips the old spelling, no rule could fire. scope=group-rule: the rule judges co-visible names, which one pair cannot evidence; unscored, not 0/0. o=/n=: one labelled pair's old (abandoned) and new (chosen) spelling. sup=N: distinct hunks that showed this substitution. p at=: path:line of the symbol the pair joined to, not a commit (the root at= is). old_fires=: rules that fired on the old spelling; absent when none. new_fires=: rules that fired on the new spelling; absent when none. -->
<naming-calibration schema="ripwire.naming-calibration/v1" probed="1" pairs="138" candidates="1700" commits="3565" hunks="77518" wide_hunks="843" drop_old_alive="366" drop_new_absent="1135" drop_ambiguous="61" drop_old_skipped="0" at="c7920353a">
<r n="naming-short" old="1" new="0" fired="1" proxy="1.000"/>
<r n="naming-wordy" old="0" new="1" fired="1" proxy="0.000"/>
<r n="naming-series" scope="group-rule"/>
<r n="naming-underscore" old="0" new="0" fired="0"/>
<r n="naming-case" old="0" new="0" fired="0"/>
<r n="naming-predicate" old="1" new="0" fired="1" proxy="1.000"/>
<r n="naming-setter" old="0" new="0" fired="0"/>
<r n="naming-confusable" scope="group-rule"/>
<!-- 4 rename rows withheld: the project's own rebrand, which names a private pre-release identifier -->
<p o="ATTR" n="ATTR_RE" sup="1" at="./bench/recalleval/run_recalleval.py:84"/>
<p o="DEGRADED_PATH_ALERT" n="DISCLOSE" sup="405" at="./test/showcase_coverage_check.py:154"/>
<p o="ELOOP" n="err" sup="1" at="./test/sliceflowcheck.sh:242"/>
<p o="InRepoImportCounter" n="ImportResolver" sup="1" at="./src/resolve.h:3439"/>
<p o="PACK_MAGIC" n="payload" sup="1" at="./test/legendcostcheck.sh:48"/>
<p o="TTCA" n="answer" sup="1" at="./test/dartfix/math.dart:11"/>
<p o="_famBIsFamily" n="_famBKind" sup="1" at="./test/showcase_capture.py:484"/>
<p o="above" n="below" sup="1" at="./test/verify_os_win32_logic.cpp:608"/>
<p o="advice" n="next" sup="1" at="./bench/bench_svector_diff.cpp:76"/>
<p o="appendCalleeNameRow" n="collectCalleeNameRow" sup="1" at="./src/serialize.h:5755"/>
<p o="atomicWriteQSnap" n="atomicWriteFile" sup="5" at="./src/quality.h:3710"/>
<p o="bool" n="GaugeClauses" sup="3" at="./src/graphlegend.h:154"/>
<p o="cacheBuildTag" n="rootBlobTail" sup="5" at="./src/quality.h:2637"/>
<p o="capped" n="dropped" sup="6" at="./test/mcpforparitycheck.sh:89"/>
<p o="cat" n="rootOf" sup="2" at="./test/ceilingverdictcheck.sh:99"/>
<p o="cfg" n="rel" sup="3" at="./bench/capsweep/capsweep.py:955"/>
… [119 more display lines; full output is 12978 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --lint --naming-locals`

*The opt-in --lint modifier: naming predicates over LOCAL variable names too, C/C++ only, only inside functions already past a size/complexity gate.*

**wall time: 3.89s**

`````
<!-- ripwire lint schema=ripwire.lint/v1: AST-only checks, facts not gates: <rule name= count= shown_rows= rows_capped= count_capped=> of <f rule= p= in=>. window: shown= total= capped= has_more= next_offset= offset= limit= (capped=1 cut; next_offset= pastes as offset=). findings_capped=/rows_capped=/count_capped=: 1 = cut. counts_floor=1: every count is a FLOOR, never a total. root=: p= relative to it. findings=N: findings over the printed rules; a floor when findings_capped=1. -->
<lint schema="ripwire.lint/v1" findings="6282" shown="628" capped="1" total="6282" has_more="1" next_offset="628" offset="0" limit="0" counts_floor="1" findings_capped="1" naming_locals="1" root=".">
<rule name="c-style-cast" count="420" shown_rows="56" rows_capped="1"/>
<rule name="goto" count="15" shown_rows="1" rows_capped="1"/>
<rule name="do-while" count="14" shown_rows="0" rows_capped="1"/>
<rule name="unsafe-c-fn" count="0" shown_rows="0" rows_capped="0"/>
<rule name="weak-crypto" count="0" shown_rows="0" rows_capped="0"/>
<rule name="redundant-parens" count="0" shown_rows="0" rows_capped="0"/>
<rule name="suspicious-semicolon" count="0" shown_rows="0" rows_capped="0"/>
<rule name="typedef-over-using" count="12" shown_rows="0" rows_capped="1"/>
<rule name="magic-number" count="445" shown_rows="203" rows_capped="1" count_capped="1"/>
<rule name="empty-catch" count="1" shown_rows="0" rows_capped="1"/>
<rule name="self-assign" count="3" shown_rows="0" rows_capped="1"/>
<rule name="large-function" count="283" shown_rows="29" rows_capped="1"/>
<rule name="deep-nesting" count="298" shown_rows="22" rows_capped="1"/>
<rule name="inconsistent-return" count="2" shown_rows="0" rows_capped="1"/>
<rule name="unreachable-code" count="5" shown_rows="0" rows_capped="1"/>
<rule name="naming-short" count="2847" shown_rows="216" rows_capped="1"/>
<rule name="naming-wordy" count="230" shown_rows="10" rows_capped="1"/>
<rule name="naming-series" count="427" shown_rows="0" rows_capped="1"/>
<rule name="naming-underscore" count="2" shown_rows="0" rows_capped="1"/>
<rule name="naming-case" count="58" shown_rows="0" rows_capped="1"/>
<rule name="naming-predicate" count="1" shown_rows="0" rows_capped="1"/>
<rule name="naming-setter" count="1" shown_rows="0" rows_capped="1"/>
<rule name="naming-confusable" count="300" shown_rows="23" rows_capped="1"/>
<rule name="naming-uninformative" count="0" shown_rows="0" rows_capped="0"/>
<rule name="atom-comma-operator" count="3" shown_rows="0" rows_capped="1"/>
<rule name="atom-embedded-crement" count="149" shown_rows="5" rows_capped="1"/>
<rule name="atom-assign-as-value" count="65" shown_rows="4" rows_capped="1"/>
<rule name="atom-nested-ternary" count="135" shown_rows="9" rows_capped="1"/>
… [640 more display lines; full output is 72432 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --lint-catalog`

*The built-in rule registry — one row per rule with sev=/category=/rationale/lang=/since=; no corpus needed.*

`````
<!-- ripwire lint-catalog schema=ripwire.lint-catalog/v1: the built-in lint rule registry: <rule name= sev= cat= lang= since=>. rules=N: rules in the built-in registry, one rule row each, never cut. -->
<lintcatalog schema="ripwire.lint-catalog/v1" rules="39">
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
<rule name="naming-short" sev="info" cat="naming" lang="cpp,c,objc,py,ts,js,go,rs,swift,java,cs,rb,sh,php,lua,ex,dart,kt,gd" since="v0.2.2">a 1-2 letter Function/Method/Var name — visible far beyond any tiny scope [Beniamini/Hofmeister]</rule>
<rule name="naming-wordy" sev="info" cat="naming" lang="cpp,c,objc,py,ts,js,go,rs,swift,java,cs,rb,sh,php,lua,ex,dart,kt,gd" since="v0.2.2">more than 5 split tokens in one name [Butler; AlSuhaibani]</rule>
<rule name="naming-series" sev="info" cat="naming" lang="cpp,c,objc,py,ts,js,go,rs,swift,java,cs,rb,sh,php,lua,ex,dart,kt,gd" since="v0.2.2">foo1/foo2/... digit-suffix siblings sharing a base name in one scope [Butler]</rule>
<rule name="naming-underscore" sev="info" cat="naming" lang="cpp,c,objc,py,ts,js,go,rs,swift,java,cs,rb,sh,php,lua,ex,dart,kt,gd" since="v0.2.2">internal consecutive underscores, or a C-family reserved __x/_X form [Butler]</rule>
<rule name="naming-case" sev="info" cat="naming" lang="cpp,c,objc,py,ts,js,go,rs,swift,java,cs,rb,sh,php,lua,ex,dart,kt,gd" since="v0.2.2">snake_case and camelCase mixed inside one name [Butler]</rule>
<rule name="naming-predicate" sev="info" cat="naming" lang="cpp,c,objc,py,ts,js,go,rs,swift,java,cs,rb,sh,php,lua,ex,dart,kt,gd" since="v0.2.2">an is/has/can/should/was-prefixed name whose KNOWN return type is not bool-like [LAPD A2]</rule>
<rule name="naming-setter" sev="info" cat="naming" lang="cpp,c,objc,py,ts,js,go,rs,swift,java,cs,rb,sh,php,lua,ex,dart,kt,gd" since="v0.2.2">a set-prefixed name whose KNOWN return type is not void-like [LAPD A3]</rule>
<rule name="naming-confusable" sev="info" cat="naming" lang="cpp,c,objc,py,ts,js,go,rs,swift,java,cs,rb,sh,php,lua,ex,dart,kt,gd" since="v0.2.2">a co-visible pair within edit distance &lt;=2, reordered tokens, or a bare/digit-suffixed twin [Namesake]</rule>
<rule name="naming-uninformative" sev="info" cat="naming" lang="cpp,c,objc,py,ts,js,go,rs,swift,java,cs,rb,sh,php,lua,ex,dart,kt,gd" since="v0.2.2">every split subtoken is corpus-ubiquitous (BM25 idf) on a body past the size floor — fires only at the low end [Sparck Jones 1972]</rule>
<rule name="atom-comma-operator" sev="info" cat="readability" lang="cpp,c,objc" since="v0.2.2">the comma operator inside an expression (never a for-header comma) [Gopstein FSE 2017]</rule>
<rule name="atom-embedded-crement" sev="info" cat="readability" lang="cpp,c,objc" since="v0.2.2">++/-- evaluated inside a larger expression (never a whole statement) [Gopstein FSE 2017]</rule>
<rule name="atom-assign-as-value" sev="info" cat="readability" lang="cpp,c,objc" since="v0.2.2">an assignment whose VALUE is consumed (a condition, an argument, ...) [Gopstein FSE 2017]</rule>
<rule name="atom-nested-ternary" sev="info" cat="readability" lang="cpp,c,objc" since="v0.2.2">a conditional expression inside a conditional expression [Gopstein FSE 2017]</rule>
… [12 more display lines; full output is 7764 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --legend-dict`

*The session legend dictionary the MCP server serves as ripwire://legend-dict/full — one definition per line, headed by its dictv= version; no corpus needed. =roster lists the completeness attributes it defines.*

`````
ripwire legend dictionary ripwire.dict/v1 dictv=c888cb4b5732610c entries=786
<about legend="ref" dict= dictv=>: the answer's rows come first; its root keeps only task= changed= from= to=, and this LAST child carries every other root attribute unchanged (schema= included); legend="ref": a definition is sent once per session (this dictionary's core, or the first answer that ne … [line truncated: 83 more bytes on this line]
schema=ripwire.KEY/v1: the line ripwire.KEY/v1 below reads the answer's rows
window: shown= total= capped= has_more= next_offset= offset= limit= page a list (capped=1 cut; next_offset= pastes as offset=)
X_capped= (any attribute ending _capped): 1 = cut
under ref, est_tokens= and over_ceiling= price the answer with its inline legend: an upper bound
under ref, a <g n= p=> group of n <= 8 runner-less rows prints as its n single rows, each run_unknown=1
ripwire.map/v1 <r>: ranked symbol map: <f p= layer=> groups <s t= n= sc= k= amb=> rows (k= rank), <c n=> resolved callees; the header comment is data
ripwire.map-diff/v1 <r>: the ranked map anchored at at=: what the diff touched, the map's row vocabulary
ripwire.metrics/v1 <r>: the ranked map with per-symbol metrics: in/out, cx/ccx, loc, params, nest, humps/deep, locals, cbo, amp, tested, ev
ripwire.around/v1 <r>: call neighbourhood of of=: depth= hops, fanout= kept per hop; absent rows lie outside that boundary
ripwire.query/v1 <r>: lexical-rank map for the query term, the map's row vocabulary
ripwire.pack-signatures/v1 <ctx>: the ranked map plus <sigs><d l= n= sc= pure=> signature rows
ripwire.pack-top-n/v1 <ctx>: the ranked map plus <src p=> bodies of the top-N symbols
ripwire.skipped/v1 <ctx>: why the index lacks a file <f p= why= bytes= limit= ext=>; indexed but unvouched <h p= why= err= err_ratio=>; <lang> census
ripwire.notes/v1 <ctx>: field notes by target: <target id= dangling=> holds <note d= sha= branch=>; the kept count comment: notes= rows, targets= <target> rows, dangling= targets matching nothing indexed (listed, surfaced nowhere)
ripwire.lego/v1 <ctx>: ONE interface/base type: <iface n= p= defs= implementors=>, its <m> method contract, every implementor
ripwire.expand/v1 <ctx>: full bodies: <bodies shown= total= capped=> of <b t= l= p= n= sibs= sibs_total= sibs_capped= inc=>; <calls><c n= l=> resolved callees
ripwire.expand-file/v1 <ctx>: the file's own text: <src p= sym=>; <s n= sc= l=/> per scoped symbol; full id = p::sc::n
ripwire.pack-task/v1 <ctx>: one-call task bundle for task= under budget_tokens=: <sigs><d n= sc= l= p=> ranking, <far><s t= n= p=> ranked but over 1 hop out (of_top= ranked rows) > <bodies><b t= n= p= l=> with <calls><c n= l=> callees > <callers><s rel=caller|callee shared=> 1-hop from the bodies (o … [line truncated: 105 more bytes on this line]
ripwire.from-trace/v1 <ctx>: trace frames mapped to indexed symbols, innermost first; the innermost in-corpus body included
ripwire.exemplar/v1 <ctx>: the best-in-class instance of kind= for the task, chosen by role: <exemplar n= p= in= ccx= tested=>, <bodies><b> to imitate
ripwire.pack-task/v1 <ctx-partitions>: N minimally overlapping agent bundles carved along call-graph communities plus one shared core; each <bundle> wraps a <ctx>; bundle role=core|partition i= symbols= modules= bytes= tokens=: one agent's ctx, symbols= ids assigned, bytes= its size; tokens= = est_t … [line truncated: 345 more bytes on this line]
ripwire.callers/v1 <callers>: 1-hop CALLERS of of= (defs= matched, count= distinct symbols): <s t= n= p=>; hop_tested=/hop_untested=
ripwire.callees/v1 <callees>: 1-hop CALLEES of of= (defs= matched, count= distinct symbols): <s t= n= p= role= tested=>
ripwire.uses/v1 <uses>: resolvable use-sites of of=: <u role=call|macro|read|write|import|extends|type p=file:line in_id=>
ripwire.impact/v1 <impact>: transitive blast radius of of=: <s t= n= p=> reach set, <f via= p=> importers; defs= matched, reaches= their transitive callers, radius_tested= non-tests an indexed test reaches, radius_untested= the rest; importers= files that #include/import a def's file
ripwire.path/v1 <path>: one DIRECTED call path from= to to=, each <s t= n= p=> a hop; reachable=0 hops=0 when none
ripwire.connect/v1 <connect>: minimal joining subgraph: <g> groups, <t> terminals, <s connects=> joins, <e f= t=> edges, <unconnected>
ripwire.at/v1 <at>: enclosing-definition chain at p=:l=: sym= innermost, chain= outermost-first, <s n= t= l= el=> spans
… [757 more display lines; full output is 78308 bytes on 787 raw line(s)]
`````

## `./build/ripwire . --lint --lint-select=cache-`

*Run ONLY one rule family; the root carries selected="K of N" so a filtered zero is never confusable with an unfiltered one.*

**wall time: 3.27s**

`````
<!-- ripwire lint schema=ripwire.lint/v1: AST-only checks, facts not gates: <rule name= count= shown_rows= rows_capped= count_capped=> of <f rule= p= in=>. window: shown= capped= (capped=1 cut). rows_capped=: 1 = cut. root=: p= relative to it. findings=N: findings over the printed rules; a floor when findings_capped=1. -->
<lint schema="ripwire.lint/v1" findings="524" shown="524" capped="0" selected="8 of 39" select="cache-" root=".">
<rule name="cache-node-container" count="17" shown_rows="17" rows_capped="0"/>
<rule name="cache-vector-of-raw-ptr" count="43" shown_rows="43" rows_capped="0"/>
<rule name="cache-vector-of-indirect" count="180" shown_rows="180" rows_capped="0"/>
<rule name="cache-heap-alloc-in-loop" count="5" shown_rows="5" rows_capped="0"/>
<rule name="cache-pointer-chase-loop" count="8" shown_rows="8" rows_capped="0"/>
<rule name="cache-gather-subscript" count="249" shown_rows="249" rows_capped="0"/>
<rule name="cache-shared-ptr-by-value" count="21" shown_rows="21" rows_capped="0"/>
<rule name="cache-manual-prefetch" count="1" shown_rows="1" rows_capped="0"/>
<f rule="cache-vector-of-indirect" p="bench/agentloop/editsuite/fixture/matrix.cpp:3" in="">vector&lt;std::vector&lt;double&gt;&gt;</f>
<f rule="cache-gather-subscript" p="bench/bench_chase_ab.cpp:106" in="linkChain">nodes[ perm[i] ]</f>
<f rule="cache-gather-subscript" p="bench/bench_chase_ab.cpp:106" in="linkChain">nodes[ perm[ i + 1 ] ]</f>
<f rule="cache-pointer-chase-loop" p="bench/bench_chase_ab.cpp:118" in="chase">p = p-&gt;next</f>
<f rule="cache-node-container" p="bench/bench_convergence.cpp:40" in="">map</f>
<f rule="cache-gather-subscript" p="bench/bench_convergence.cpp:77" in="main">byName[ symN[i] ]</f>
<f rule="cache-vector-of-indirect" p="bench/bench_convergence.cpp:82" in="main">vector&lt;std::vector&lt;std::vector&lt;std::uint32_t&gt;&gt;&gt;</f>
<f rule="cache-vector-of-indirect" p="bench/bench_convergence.cpp:82" in="main">vector&lt;std::vector&lt;std::uint32_t&gt;&gt;</f>
<f rule="cache-gather-subscript" p="bench/bench_convergence.cpp:97" in="main">m[ symN[id] ]</f>
<f rule="cache-vector-of-indirect" p="bench/bench_newline_ab.cpp:279" in="main">vector&lt;std::vector&lt;double&gt;&gt;</f>
<f rule="cache-gather-subscript" p="bench/bench_ordered_map.cpp:89" in="aggregateMax">m[ in.keys[ i ] ]</f>
<f rule="cache-node-container" p="bench/bench_svector3.cpp:62" in="">map</f>
<f rule="cache-vector-of-indirect" p="bench/bench_svector3.cpp:85" in="main">vector&lt;std::vector&lt;std::vector&lt;std::uint32_t&gt;&gt;&gt;</f>
<f rule="cache-vector-of-indirect" p="bench/bench_svector3.cpp:85" in="main">vector&lt;std::vector&lt;std::uint32_t&gt;&gt;</f>
<f rule="cache-gather-subscript" p="bench/bench_svector3.cpp:95" in="main">m[ symN[id] ]</f>
<f rule="cache-node-container" p="bench/bench_svector_wave.cpp:94" in="">map</f>
<f rule="cache-gather-subscript" p="bench/bench_svector_wave.cpp:155" in="build">m[ g_pool[ g_keyOf[i] ] ]</f>
<f rule="cache-gather-subscript" p="bench/bench_svector_wave.cpp:162" in="readSize">g_pool[ g_readOf[i] ]</f>
<f rule="cache-gather-subscript" p="bench/bench_svector_wave.cpp:172" in="readIterate">g_pool[ g_readOf[i] ]</f>
<f rule="cache-gather-subscript" p="bench/bench_svector_wave.cpp:184" in="rehash">m[ g_pool[i] ]</f>
… [505 more display lines; full output is 61080 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --lint --lint-ignore=naming-,cache-`

*DROP two families, applied after selection; the raw select=/ignore= you passed rides on the root.*

**wall time: 2.65s**

`````
<!-- ripwire lint schema=ripwire.lint/v1: AST-only checks, facts not gates: <rule name= count= shown_rows= rows_capped= count_capped=> of <f rule= p= in=>. window: shown= total= capped= has_more= next_offset= offset= limit= (capped=1 cut; next_offset= pastes as offset=). findings_capped=/rows_capped=/count_capped=: 1 = cut. counts_floor=1: every count is a FLOOR, never a total. root=: p= relative to it. findings=N: findings over the printed rules; a floor when findings_capped=1. -->
<lint schema="ripwire.lint/v1" findings="1892" shown="734" capped="1" total="1892" has_more="1" next_offset="734" offset="0" limit="0" counts_floor="1" findings_capped="1" selected="22 of 39" ignore="naming-,cache-" root=".">
<rule name="c-style-cast" count="420" shown_rows="121" rows_capped="1"/>
<rule name="goto" count="15" shown_rows="1" rows_capped="1"/>
<rule name="do-while" count="14" shown_rows="0" rows_capped="1"/>
<rule name="unsafe-c-fn" count="0" shown_rows="0" rows_capped="0"/>
<rule name="weak-crypto" count="0" shown_rows="0" rows_capped="0"/>
<rule name="redundant-parens" count="0" shown_rows="0" rows_capped="0"/>
<rule name="suspicious-semicolon" count="0" shown_rows="0" rows_capped="0"/>
<rule name="typedef-over-using" count="12" shown_rows="0" rows_capped="1"/>
<rule name="magic-number" count="445" shown_rows="429" rows_capped="1" count_capped="1"/>
<rule name="empty-catch" count="1" shown_rows="0" rows_capped="1"/>
<rule name="self-assign" count="3" shown_rows="0" rows_capped="1"/>
<rule name="large-function" count="283" shown_rows="56" rows_capped="1"/>
<rule name="deep-nesting" count="298" shown_rows="58" rows_capped="1"/>
<rule name="inconsistent-return" count="2" shown_rows="0" rows_capped="1"/>
<rule name="unreachable-code" count="5" shown_rows="0" rows_capped="1"/>
<rule name="atom-comma-operator" count="3" shown_rows="0" rows_capped="1"/>
<rule name="atom-embedded-crement" count="149" shown_rows="29" rows_capped="1"/>
<rule name="atom-assign-as-value" count="65" shown_rows="11" rows_capped="1"/>
<rule name="atom-nested-ternary" count="135" shown_rows="26" rows_capped="1"/>
<rule name="atom-implicit-predicate" count="3" shown_rows="2" rows_capped="1"/>
<rule name="atom-octal-literal" count="39" shown_rows="1" rows_capped="1"/>
<rule name="atom-reversed-subscript" count="0" shown_rows="0" rows_capped="0"/>
<f rule="magic-number" p="bench/agentloop/editsuite/fixture/geometry.cpp:7" in="area_of_triangle">0.5</f>
<f rule="magic-number" p="bench/bench_chase_ab.cpp:100" in="linkChain">1023u</f>
<f rule="large-function" p="bench/bench_chase_ab.cpp:161" in="main">main (90 lines)</f>
<f rule="magic-number" p="bench/bench_chase_ab.cpp:167" in="main">20</f>
<f rule="atom-implicit-predicate" p="bench/bench_chase_ab.cpp:234" in="main">delta &lt; 0.02 &amp;&amp; delta &gt; -0.02</f>
<f rule="magic-number" p="bench/bench_chase_ab.cpp:234" in="main">0.02</f>
… [729 more display lines; full output is 65896 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --lint --lint-select=cach-`

*An unresolvable PREFIX refuses (exit 1) with a did-you-mean from a real edit distance (one character off cache-).*

**exit code: 1** — **wall time: 3.00s**

`````
(empty)
`````

stderr:

`````
ripwire: --lint-select: 'cach-' matches no rule or family (did you mean 'cache-'?) — see --lint-catalog for the full registry
`````

## `./build/ripwire . --lint --lint-select=nosuchfamily`

*A PREFIX with no near miss at all: the refusal points at --lint-catalog instead of guessing.*

**exit code: 1** — **wall time: 2.92s**

`````
(empty)
`````

stderr:

`````
ripwire: --lint-select: 'nosuchfamily' matches no rule or family — see --lint-catalog for the full registry
`````

## `./build/ripwire . --lint --sarif`

*The SAME findings as SARIF 2.1.0 (what github/codeql-action/upload-sarif consumes) — pure re-serialization, results count == the native run's.*

**wall time: 2.82s**

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
… [10019 more display lines; full output is 1403667 bytes on 1 raw line(s)]
`````

Parsed summary of the same SARIF (past the display cut):

`````
sarif 2.1.0 rules= 39 results= 5005
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

**wall time: 4.45s**

`````
<!-- ripwire dmm schema=ripwire.dmm/v1: Delta Maintainability Model base=→target=: dmm= good/(good+bad) units by size_metric=; <p k= dmm= good= bad= d_low= d_high=>. at=: commit+dirty+shallow. available=0: no score at all (dmm=UNAVAILABLE, reason= says why); never read as 1.000 or 0.000. combine=pooled: root dmm= is summed good over summed good+bad of the 3 properties (ripwire's own). low_loc=/low_cx=/low_params=: a unit is LOW risk at or under these lines / cyclomatic / params. base_units=/base_volume=/target_units=/target_volume=: units with a body and their line span per side. reason=: why no score (no unit's size, complexity or params moved; a tree failed to parse ...). -->
<dmm schema="ripwire.dmm/v1" base="c7920353a6d41f95f6ad61193358a10a3b255acf" target="working-tree" at="c7920353a" available="0" combine="pooled" size_metric="physical-loc" low_loc="15" low_cx="5" low_params="2" dmm="UNAVAILABLE" good="0" bad="0" base_units="12879" base_volume="198744" target_units=" … [line truncated: 147 more bytes on this line]
<p k="size" dmm="UNAVAILABLE" good="0" bad="0" d_low="0" d_high="0"/>
<p k="complexity" dmm="UNAVAILABLE" good="0" bad="0" d_low="0" d_high="0"/>
<p k="interfacing" dmm="UNAVAILABLE" good="0" bad="0" d_low="0" d_high="0"/>
</dmm>
`````

## `./build/ripwire . --dmm=HEAD`

*The per-commit scalar: HEAD vs its first parent, with the three separately actionable sub-scores.*

**wall time: 10.09s**

`````
<!-- ripwire dmm schema=ripwire.dmm/v1: Delta Maintainability Model base=→target=: dmm= good/(good+bad) units by size_metric=; <p k= dmm= good= bad= d_low= d_high=>. at=: commit+dirty+shallow. available=0: no score at all (dmm=UNAVAILABLE, reason= says why); never read as 1.000 or 0.000. combine=pooled: root dmm= is summed good over summed good+bad of the 3 properties (ripwire's own). low_loc=/low_cx=/low_params=: a unit is LOW risk at or under these lines / cyclomatic / params. base_units=/base_volume=/target_units=/target_volume=: units with a body and their line span per side. -->
<dmm schema="ripwire.dmm/v1" base="219aaaacd982c3074585fad3e7b08f654b7569ca" target="c7920353a6d41f95f6ad61193358a10a3b255acf" at="c7920353a" available="1" combine="pooled" size_metric="physical-loc" low_loc="15" low_cx="5" low_params="2" dmm="0.133" good="8" bad="52" base_units="12877" base_volume= … [line truncated: 53 more bytes on this line]
<p k="size" dmm="0.100" good="2" bad="18" d_low="2" d_high="18"/>
<p k="complexity" dmm="0.200" good="4" bad="16" d_low="4" d_high="16"/>
<p k="interfacing" dmm="0.100" good="2" bad="18" d_low="2" d_high="18"/>
</dmm>
`````

## `./build/ripwire . --dmm=HEAD~3..HEAD`

*The range form: tree HEAD vs tree HEAD~3.*

**wall time: 9.73s**

`````
<!-- ripwire dmm schema=ripwire.dmm/v1: Delta Maintainability Model base=→target=: dmm= good/(good+bad) units by size_metric=; <p k= dmm= good= bad= d_low= d_high=>. at=: commit+dirty+shallow. available=0: no score at all (dmm=UNAVAILABLE, reason= says why); never read as 1.000 or 0.000. combine=pooled: root dmm= is summed good over summed good+bad of the 3 properties (ripwire's own). low_loc=/low_cx=/low_params=: a unit is LOW risk at or under these lines / cyclomatic / params. base_units=/base_volume=/target_units=/target_volume=: units with a body and their line span per side. -->
<dmm schema="ripwire.dmm/v1" base="481149caa6b991d84c2022914a3b73c154d4f34d" target="c7920353a6d41f95f6ad61193358a10a3b255acf" at="c7920353a" available="1" combine="pooled" size_metric="physical-loc" low_loc="15" low_cx="5" low_params="2" dmm="0.133" good="8" bad="52" base_units="12877" base_volume= … [line truncated: 53 more bytes on this line]
<p k="size" dmm="0.100" good="2" bad="18" d_low="2" d_high="18"/>
<p k="complexity" dmm="0.200" good="4" bad="16" d_low="4" d_high="16"/>
<p k="interfacing" dmm="0.100" good="2" bad="18" d_low="2" d_high="18"/>
</dmm>
`````

## `./build/ripwire . --cochange --cochange-groups`

*Modularity-violation GROUPS instead of pairs: "X co-changes with {A,B,C}, none of which it depends on" — a greedy cover, disclosed as greedy.*

**wall time: 1.79s**

`````
<!-- ripwire cochange schema=ripwire.cochange/v1: files that change together in git: <pair a= b= together= deg= conf_ab= conf_ba= surprising=>, or for of= <f p= together= conf_rev=>. window: shown= total= capped= has_more= next_offset= offset= limit= (capped=1 cut; next_offset= pastes as offset=). at=: commit+dirty+shallow. root=: p= relative to it. sub_windows=N: equal-commit-count slices of window=; the denominator of recur=. recur=K: slices of sub_windows= the pair co-changed in; 1 = one burst, not a standing coupling. -->
<cochange schema="ripwire.cochange/v1" groups="108" pairs_covered="867" cover="greedy" window="18mo@HEAD" sub_windows="3" shown="30" capped="1" total="108" has_more="1" next_offset="30" offset="0" limit="0" root="." at="c7920353a">
<group core="src/cli.h" partners="79">
<f p="src/abicheck.h" together="3" recur="2" conf_core="0.01"/>
<f p="src/arch.h" together="5" recur="3" conf_core="0.01"/>
<f p="src/callhierarchy.h" together="3" recur="1" conf_core="0.01"/>
<f p="src/clones.h" together="6" recur="2" conf_core="0.01"/>
<f p="src/codexdoctor.h" together="3" recur="2" conf_core="0.01"/>
<f p="src/commentcoherence.h" together="3" recur="2" conf_core="0.01"/>
<f p="src/compactlegend.h" together="65" recur="2" conf_core="0.15"/>
<f p="src/contextratio.h" together="4" recur="2" conf_core="0.01"/>
<f p="src/crossref.h" together="16" recur="3" conf_core="0.04"/>
<f p="src/darkflags.h" together="4" recur="3" conf_core="0.01"/>
<f p="src/didyoumean.h" together="3" recur="2" conf_core="0.01"/>
<f p="src/dmm.h" together="4" recur="2" conf_core="0.01"/>
<f p="src/editcheck.h" together="5" recur="2" conf_core="0.01"/>
<f p="src/editplan.h" together="9" recur="2" conf_core="0.02"/>
<f p="src/editpreview.h" together="5" recur="2" conf_core="0.01"/>
<f p="src/ensemble.h" together="7" recur="3" conf_core="0.02"/>
<f p="src/eval.h" together="3" recur="2" conf_core="0.01"/>
<f p="src/filter.h" together="4" recur="1" conf_core="0.01"/>
<f p="src/flipimpact.h" together="4" recur="3" conf_core="0.01"/>
<f p="src/githarden.h" together="3" recur="1" conf_core="0.01"/>
<f p="src/gitmine.h" together="11" recur="3" conf_core="0.03"/>
<f p="src/graph.h" together="40" recur="3" conf_core="0.09"/>
<f p="src/graphlegend.h" together="32" recur="3" conf_core="0.08"/>
<f p="src/handoff.h" together="6" recur="2" conf_core="0.01"/>
<f p="src/ingest.cpp" together="43" recur="3" conf_core="0.10"/>
<f p="src/ingest_astquery.h" together="7" recur="3" conf_core="0.02"/>
<f p="src/ingest_cache.h" together="20" recur="3" conf_core="0.05"/>
… [726 more display lines; full output is 47798 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --cochange --cochange-recur=2`

*Only pairs whose co-change RECURS in 2+ sub-windows of the mined window (sub_windows= is the denominator) — a one-off sprint stops reading like a structural defect.*

**wall time: 1.44s**

`````
<!-- ripwire cochange schema=ripwire.cochange/v1: files that change together in git: <pair a= b= together= deg= conf_ab= conf_ba= surprising=>, or for of= <f p= together= conf_rev=>. window: shown= total= capped= has_more= next_offset= offset= limit= (capped=1 cut; next_offset= pastes as offset=). at=: commit+dirty+shallow. root=: p= relative to it. pairs=N: file pairs with 3+ shared commits in window= (after min_recur), surprising or not. sub_windows=N: equal-commit-count slices of window=; the denominator of recur=. driver=a|b: the side whose changes best imply the other's, look there first; absent on a tie. recur=K: slices of sub_windows= the pair co-changed in; 1 = one burst, not a standing coupling. -->
<cochange schema="ripwire.cochange/v1" pairs="2635" window="18mo@HEAD" sub_windows="3" min_recur="2" shown="30" capped="1" total="2635" has_more="1" next_offset="30" offset="0" limit="0" root="." at="c7920353a">
<pair a="test/headsnapcachecheck.sh" b="test/qsnapcachecheck.sh" together="4" deg="1.00" conf_ab="1.00" conf_ba="1.00" recur="2" surprising="1"/>
<pair a="test/headsnapcachecheck.sh" b="test/qsnapprefetchcheck.sh" together="4" deg="1.00" conf_ab="1.00" conf_ba="0.67" driver="a" recur="2" surprising="1"/>
<pair a="test/qsnapcachecheck.sh" b="test/qsnapprefetchcheck.sh" together="4" deg="1.00" conf_ab="1.00" conf_ba="0.67" driver="a" recur="2" surprising="1"/>
<pair a="test/mcpslicecheck.sh" b="test/mcpverbscheck.sh" together="3" deg="1.00" conf_ab="1.00" conf_ba="0.21" driver="a" recur="3" surprising="1"/>
<pair a="test/grepcheck.sh" b="test/grepcontextcheck.sh" together="3" deg="1.00" conf_ab="0.50" conf_ba="1.00" driver="b" recur="2" surprising="1"/>
<pair a="test/javamethodreffix/A.java" b="test/javamethodreffix/Widget.java" together="3" deg="1.00" conf_ab="0.75" conf_ba="1.00" driver="b" recur="2" surprising="1"/>
<pair a="test/cachesplitcheck.sh" b="test/evictioncheck.sh" together="3" deg="1.00" conf_ab="1.00" conf_ba="0.23" driver="a" recur="2" surprising="1"/>
<pair a="test/droppedpositivecheck.sh" b="test/regression.sh" together="3" deg="1.00" conf_ab="1.00" conf_ba="0.01" driver="a" recur="2" surprising="1"/>
<pair a="test/grepcontextcheck.sh" b="test/grepscancheck.sh" together="3" deg="1.00" conf_ab="1.00" conf_ba="1.00" recur="2" surprising="1"/>
<pair a="test/luacheck.sh" b="test/phpcheck.sh" together="3" deg="1.00" conf_ab="0.75" conf_ba="1.00" driver="b" recur="2" surprising="1"/>
<pair a="test/grepcheck.sh" b="test/grepscancheck.sh" together="3" deg="1.00" conf_ab="0.50" conf_ba="1.00" driver="b" recur="2" surprising="1"/>
<pair a="hooks/ripwire-claude-route.sh" b="hooks/ripwire-codex-route.sh" together="16" deg="0.94" conf_ab="0.94" conf_ba="0.84" driver="a" recur="3" surprising="1"/>
<pair a="src/graph.h" b="src/ingest_jsimports.h" together="6" deg="0.86" conf_ab="0.03" conf_ba="0.86" driver="b" recur="2" surprising="1"/>
<pair a="src/serialize.h" b="src/verify.h" together="5" deg="0.83" conf_ab="0.02" conf_ba="0.83" driver="b" recur="2" surprising="1"/>
<pair a="src/cli.h" b="src/sarif.h" together="5" deg="0.83" conf_ab="0.01" conf_ba="0.83" driver="b" recur="2" surprising="1"/>
<pair a="src/fielduses.h" b="src/verbs_navigate.h" together="5" deg="0.83" conf_ab="0.83" conf_ba="0.04" driver="a" recur="3" surprising="1"/>
<pair a="test/nestedimportcheck.sh" b="test/preproccondcheck.sh" together="4" deg="0.80" conf_ab="0.67" conf_ba="0.80" driver="b" recur="2" surprising="1"/>
<pair a="src/ingest_model.h" b="src/model.h" together="18" deg="0.78" conf_ab="0.78" conf_ba="0.14" driver="a" recur="3" surprising="1"/>
<pair a="src/ingest_cache.h" b="src/quality.h" together="132" deg="0.77" conf_ab="0.77" conf_ba="0.40" driver="a" recur="3" surprising="1"/>
<pair a="src/infra/diagnostics.cpp" b="test/diagnotice_harness.cpp" together="3" deg="0.75" conf_ab="0.60" conf_ba="0.75" driver="b" recur="2" surprising="1"/>
<pair a="test/regression.sh" b="test/subtokencheck.sh" together="3" deg="0.75" conf_ab="0.01" conf_ba="0.75" driver="b" recur="2" surprising="1"/>
<pair a="test/regression.sh" b="test/rubysettercheck.sh" together="3" deg="0.75" conf_ab="0.01" conf_ba="0.75" driver="b" recur="2" surprising="1"/>
<pair a="src/ingest_model.h" b="src/quality.h" together="17" deg="0.74" conf_ab="0.74" conf_ba="0.05" driver="a" recur="3" surprising="1"/>
<pair a="test/anchorcheck.sh" b="test/routecheck.sh" together="8" deg="0.73" conf_ab="0.73" conf_ba="0.62" driver="a" recur="3" surprising="1"/>
<pair a="src/ingest_cache.h" b="src/ingest_jsimports.h" together="5" deg="0.71" conf_ab="0.03" conf_ba="0.71" driver="b" recur="2" surprising="1"/>
<pair a="hooks/ripwire-codex-route.sh" b="test/codexpromptroutecheck.sh" together="5" deg="0.71" conf_ab="0.26" conf_ba="0.71" driver="b" recur="3" surprising="1"/>
<pair a="src/ingest_jsimports.h" b="src/quality.h" together="5" deg="0.71" conf_ab="0.71" conf_ba="0.01" driver="a" recur="2" surprising="1"/>
<pair a="src/commentcoherence.h" b="src/readability.h" together="5" deg="0.71" conf_ab="0.71" conf_ba="0.42" driver="a" recur="3" surprising="1"/>
<pair a="src/callhierarchy.h" b="src/verbs_navigate.h" together="12" deg="0.71" conf_ab="0.71" conf_ba="0.10" driver="a" recur="2" surprising="1"/>
<pair a="src/ingest_parsepool.h" b="src/ingest_prewarm.h" together="7" deg="0.70" conf_ab="0.17" conf_ba="0.70" driver="b" recur="3" surprising="1"/>
</cochange>
`````

## `./build/ripwire . --html=<scratch>/aux/map2.html --color-by=community`

*The HTML graph with the initial colour mode set to community (the page embeds all five modes and keeps a live selector).*

**wall time: 1.62s**

`````
(empty)
`````

Artifact written:

`````
  158888 <scratch>/aux/map2.html
`````

## `./build/ripwire . --index-out=<scratch>/aux/ci_index`

*CI generate-and-exit: cold-parse and write BOTH committable cache families (lean + rich), no map on stdout.*

**wall time: 5.03s**

`````
(empty)
`````

stderr:

`````
ripwire: --index-out wrote <scratch>/aux/ci_index.lean.ripwirecache (18649971 bytes, lean family)
ripwire: --index-out wrote <scratch>/aux/ci_index.rich.ripwirecache (39975434 bytes, rich family)
`````

Artifact written:

`````
 18649971 <scratch>/aux/ci_index.lean.ripwirecache
 39975434 <scratch>/aux/ci_index.rich.ripwirecache
 58625405 total
`````

## `./build/ripwire . --cache=<scratch>/aux/ci_index.lean.ripwirecache --top-k=3`

*Consume the lean artifact in a PR job: restore-equivalence, never blob-byte-identity.*

`````
<!-- ripwire map schema=ripwire.map/v1: ranked symbol map: <f p= layer=> groups <s t= n= sc= k= amb=> rows (k= rank), <c n=> resolved callees; the header comment is data. est_tokens=: price as emitted (an upper bound under compact). root=: p= relative to it. pr_iters=N: PageRank iterations. declined=K: K calls left unbound (no evidence chose one def). external=K: K calls proven outside the tree, no edge. locality_pinned=K: K calls pinned by locality alone (a guess). extent_suspect_syms=K: K defs failed containment, corpus-wide. macro_blanked_files=K: K files indexed from a macro-blanked re-parse. overloads=N: N same-name defs merged in this row; shown= counts each. files=/symbols=: files and symbols indexed; edges= distinct call edges; shown= symbols printed, a merged row counting each def; ambiguous= calls split over several defs, corpus-wide; unresolved= calls with in-tree evidence and no edge (every def language-filtered or unreachable, or binding refused); order= rows by rank (important-first, important-last; (auto:fill) = flipped past a size threshold) or by path (stable). skipped_oversize=K: K files over a size ceiling, not indexed. unindexed=ext:N: N text files of that extension no grammar reads (6 extensions at most). unindexed_exts=E: E such extensions in all, the list cut. sc=: enclosing scope; the full id is p::sc::n (p= of the row or its <f>) and selectors take it. -->
<!-- t=modscope=a-file's-MODULE-SCOPE(n=<file-scope>):the-statements-outside-every-named-definition,where-a-top-level-call-and-an-anonymous-callback-body's-calls-live;a-CALLER-never-a-callee(nothing-in-the-source-can-name-it)-with-no-body-to-expand;a-file-with-no-such-call-has-no-such-row -->
<!-- files=2484 symbols=23851 edges=34236 shown=3 est_tokens=916 ambiguous=10278 unresolved=12878 locality_pinned=12 external=7345 declined=9922 extent_suspect_syms=10 macro_blanked_files=7 skipped_oversize=15 unindexed="txt:73,tsv:49,jsonl:26,scm:23,expected:15,xml:13" unindexed_exts=20 order=important-first -->
<r schema="ripwire.map/v1" root="." est_tokens="916" pr_iters="28">
<f p="src/infra/svector.h" layer="infra">
<s t="method" n="buf" sc="svector" overloads="2" k="0.0072">
</s>
</f>
<f p="src/resolve.h">
<s t="method" n="empty" sc="RubyConstantIndex" k="0.0071">
</s>
</f>
</r>
`````

## `./build/ripwire . --pin-census=<scratch>/aux/pin_census.tsv --top-k=3`

*Eval-only: a per-call-site census of WHICH mechanism resolved each call, and the canonical id of every surviving target.*

`````
<!-- ripwire map schema=ripwire.map/v1: ranked symbol map: <f p= layer=> groups <s t= n= sc= k= amb=> rows (k= rank), <c n=> resolved callees; the header comment is data. est_tokens=: price as emitted (an upper bound under compact). root=: p= relative to it. pr_iters=N: PageRank iterations. declined=K: K calls left unbound (no evidence chose one def). external=K: K calls proven outside the tree, no edge. locality_pinned=K: K calls pinned by locality alone (a guess). extent_suspect_syms=K: K defs failed containment, corpus-wide. macro_blanked_files=K: K files indexed from a macro-blanked re-parse. overloads=N: N same-name defs merged in this row; shown= counts each. files=/symbols=: files and symbols indexed; edges= distinct call edges; shown= symbols printed, a merged row counting each def; ambiguous= calls split over several defs, corpus-wide; unresolved= calls with in-tree evidence and no edge (every def language-filtered or unreachable, or binding refused); order= rows by rank (important-first, important-last; (auto:fill) = flipped past a size threshold) or by path (stable). skipped_oversize=K: K files over a size ceiling, not indexed. unindexed=ext:N: N text files of that extension no grammar reads (6 extensions at most). unindexed_exts=E: E such extensions in all, the list cut. sc=: enclosing scope; the full id is p::sc::n (p= of the row or its <f>) and selectors take it. -->
<!-- t=modscope=a-file's-MODULE-SCOPE(n=<file-scope>):the-statements-outside-every-named-definition,where-a-top-level-call-and-an-anonymous-callback-body's-calls-live;a-CALLER-never-a-callee(nothing-in-the-source-can-name-it)-with-no-body-to-expand;a-file-with-no-such-call-has-no-such-row -->
<!-- files=2484 symbols=23851 edges=34236 shown=3 est_tokens=916 ambiguous=10278 unresolved=12878 locality_pinned=12 external=7345 declined=9922 extent_suspect_syms=10 macro_blanked_files=7 skipped_oversize=15 unindexed="txt:73,tsv:49,jsonl:26,scm:23,expected:15,xml:13" unindexed_exts=20 order=important-first -->
<r schema="ripwire.map/v1" root="." est_tokens="916" pr_iters="28">
<f p="src/infra/svector.h" layer="infra">
<s t="method" n="buf" sc="svector" overloads="2" k="0.0072">
</s>
</f>
<f p="src/resolve.h">
<s t="method" n="empty" sc="RubyConstantIndex" k="0.0071">
</s>
</f>
</r>
`````

Artifact written:

`````
# ripwire pin-census v3	C=kind\tmech\tpre\tpost\tflags\tcaller_id\tcallee\ttargets(|-sep)\tline
# v3 field escape: every id and callee field is escaped, so no separator occurs inside one. A backslash is
#   written \\, TAB \t, LF \n, CR \r, every other control byte 0x00-0x1f and the targets separator | as \xHH
#   (lowercase hex). Split lines on LF, fields on TAB and targets on |, THEN decode. Columns are unchanged
#   from v2 and an id without those bytes is spelled exactly as in v2; a C++ out-of-line template member
#   whose template-argument list spans lines keeps its line break as \n instead of splitting the row.
# line is the 1-based call-site line in the caller's file (v2, appended LAST so v1 readers are unchanged):
#   the key a SCIP occurrence joins on, so a coverage loss can be classified per site instead of guessed.
  114971 <scratch>/aux/pin_census.tsv
`````

## `./build/ripwire . --plan-lint=test/planlintfix/wave.md`

*The house PLAN/DESIGN format's STRUCTURE check — never semantics; exit 2 when a card or ledger row gates.*

**exit code: 2**

`````
<!-- ripwire plan-lint schema=ripwire.plan-lint/v1: structural lint of a plan document: each finding names the section and the rule. at=: commit+dirty+shallow. file=/dialect=: the plan read and whether the PLAN dialect was detected (dialect=0: nothing to lint). cards=/ledger=: card rows found / whether the doc carries a ledger (ledger_line= names its line). git=1: git was available, so the staleness read ran; stale_commits=N: a waiting card N commits behind HEAD is stale. gating=N: findings that fail the plan (exit 2); the rest are advisory. -->
<plan-lint schema="ripwire.plan-lint/v1" file="test/planlintfix/wave.md" dialect="1" cards="3" ledger="1" ledger_line="21" at="c7920353a" git="1" stale_commits="20" gating="3">
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
<!-- ripwire plan-lint schema=ripwire.plan-lint/v1: structural lint of a plan document: each finding names the section and the rule. at=: commit+dirty+shallow. file=/dialect=: the plan read and whether the PLAN dialect was detected (dialect=0: nothing to lint). cards=/ledger=: card rows found / whether the doc carries a ledger (ledger_line= names its line). git=1: git was available, so the staleness read ran; stale_commits=N: a waiting card N commits behind HEAD is stale. gating=N: findings that fail the plan (exit 2); the rest are advisory. -->
<plan-lint schema="ripwire.plan-lint/v1" file="test/planlintfix/wave_ledger.md" dialect="1" cards="4" ledger="1" ledger_line="17" at="c7920353a" git="1" stale_commits="20" gating="1">
<card id="T1" line="4" status="check" tline="6"/>
<card id="T2" line="8" status="check" tline="18" src="ledger"/>
<card id="T5" line="11" status="missing" tline="12" why="unlaunched" gating="1"/>
<card id="T7" line="14" status="check" tline="20" src="ledger"/>
</plan-lint>
`````

## `./build/ripwire . --doctor --agent=claude`

*--doctor plus a LIVE integration inspection for one agent: PATH binary, installed-skill manifest parity, hook executability, MCP wiring — read-only, fixed repair commands, never config contents; exit 1 when any check fails.*

**exit code: 1** — **wall time: 2.78s**

`````
<!-- ripwire doctor schema=ripwire.doctor/v1: setup health: <c n= ok=> checks; exit 1 when one fails. at=: commit+dirty+shallow. n=: the check's name (binary-path, grammars, cache-dir, git, tree-sitter, index-cache, layout ...). agent=: the agent named by the agent flag; its live-integration c rows follow the built-in checks. loaded=/expected=: grammars whose tags query compiled / grammars compiled in; a shortfall fails the row. dir=: the per-user cache directory scanned (TMPDIR/XDG_CACHE_HOME ladder); unwritable fails the row. blobs=N: ripwire cache blobs in dir=; the scan stops at 4096 (blobs_floor=1 then). bytes=N: total size in bytes of the blobs counted (short when truncated=1). many=1: more than 50 blobs; an eviction-sanity flag, informational, never fails the row. truncated=1: cache-dir, blob scan cut (cap or I/O error); tracked-binaries, scan SKIPPED, stale=0 unmeasured. locks=N: advisory edit-lock files under locks/; unheld ones over a day old are swept on a cache write. volatile=: this row's attributes that read LIVE machine state; a determinism diff strips them, never the row. git=0|1: git runs from PATH; 0 fails the row (churn verbs need it). repo=0|1: the root is inside a git work tree; 0 is a diagnosis, not a failure. history=0|1: the repo has at least one commit; head= prints only when it does. head=: HEAD's short sha (9 hex, the at= width). core_abi=/cpp_grammar_abi=: tree-sitter core language ABI / the C++ grammar's ABI; informational. languages=N: distinct compiled-in grammars (the grammars row's expected=). tracked=N: git ls-files count, printed even when truncated=1 (over 20000 files skips the scan). binaries=N: tracked paths that sniff as binary content. non_git=1: no git history to compare; the row passes unscanned. stale=N: tracked binaries committed before a same-dir same-stem source changed; any fails the row. cache_version=/parser_ver_lean=/parser_ver_rich=/artifact_arch=: index identity; reuse needs all four. rich_verbs=: the verbs that consume the rich artifact (rich=); every other verb reads the lean one. source=: auto (per-root blob), cache-flag (named by the cache flag) or disabled (no-cache: nothing read). lean_path=/rich_path=: the artifact files checked; one path when the cache flag named it. lean=/rich=: can THIS binary open that artifact (ok, absent, parser-version ...); format, never freshness. fsmonitor=: the checkout's core.fsmonitor at startup: unset, builtin, off, or hook (a command git runs). neutralised=1: a hook fsmonitor was overridden to false for this run; 0 when none was needed. state=: layout records agree, disagree (mixed binary: rebuild clean-first), not-checked or no-records. checked=1: the cross-unit layout comparison ran; 0 = under two comparable records. units=N: translation units that registered a layout record. types=N: layout types recorded (only those registered in src/model.h); omitted on state=disagree. checks=/passed=: checks run / how many passed; exit 1 when passed= is below checks=. built_from=: the commit this binary was built from; at= is the tree HEAD now, a mismatch is normal. self=/which=: this binary's path and the one which ripwire finds on PATH; which_version= is the version line that one prints when they differ. on_path=0|1: whether a ripwire is on PATH; 0 fails the row and hint= carries the export line. same_file=1: the PATH copy is this very file (same device and inode). same_bytes=1: a different file with identical content, a copied install (ok); 0 fails the row; unknown: a file was unreadable; the row fails unverified (hint= names it). self_mtime=/self_size=/which_mtime=/which_size=: epoch mtime and byte size of each binary. hint=: the row's verdict and fix in plain text (which binary is stale, what to run). -->
<doctor schema="ripwire.doctor/v1" checks="12" passed="10" agent="claude" at="c7920353a" built_from="c7920353a">
<c n="binary-path" ok="0" self="./build/ripwire" which="/opt/homebrew/bin/ripwire" on_path="1" same_file="0" same_bytes="0" self_mtime="1791441871" self_size="55777512" which_mtime="1790819582" which_size="53425560" which_version="ripwir … [line truncated: 399 more bytes on this line]
<c n="grammars" ok="1" loaded="25" expected="25"/>
<c n="cache-dir" ok="1" dir="<tmp>" blobs="1040" bytes="1898644900" many="1" truncated="0" locks="741" volatile="blobs,blobs_floor,bytes,many,truncated,locks"/>
<c n="git" ok="1" git="1" repo="1" history="1" head="c7920353a"/>
<c n="tree-sitter" ok="1" core_abi="15" cpp_grammar_abi="14" languages="25"/>
<c n="tracked-binaries" ok="1" tracked="3094" binaries="33" non_git="0" truncated="0" stale="0"/>
<c n="index-cache" ok="1" cache_version="28" parser_ver_lean="143" parser_ver_rich="144" artifact_arch="16" rich_verbs="for,uses,metrics,exemplar,context-ratio,nonlocal-state,quality-panel,verify,eval-retrieval,eval-mined,eval-skills" source="auto" lean_path="<tmp> … [line truncated: 219 more bytes on this line]
<c n="git-config-trust" ok="1" fsmonitor="unset" neutralised="0"/>
<c n="layout" ok="1" state="agree" checked="1" units="2" types="12"/>
<c n="claude-binary" ok="0" on_path="1" same_file="0" copied_heuristic="0" hint="reinstall the current build so Claude Code shell calls and this doctor resolve the same ripwire binary"/>
<c n="claude-skills" ok="1" manifest="1" declared="16" live="16"/>
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

**wall time: 5.04s**

`````
ripwire situational-awareness — 1 changed file(s), 13 symbols in them
root: .
at: c7920353a+dirty
  [1] blast radius: 190 symbols across 46 files transitively depend on these changes (showing 8 of 46 files — shown=8 total=46 capped=1 prcontext_cap=20 (--pr-context's own per-file list is cut at 20 too); next: --situ --limit=46)
        counts_floor=1 graph_ambiguous=10281 graph_unresolved=12878 graph_unindexed=237 (files no grammar in this build could read at all) (the map header's own gauges) — every count above is a FLOOR, never a total: call edges are name-based, so dynamic dispatch, callbacks and macros can be missin … [line truncated: 46 more bytes on this line]
        src/mcpverbs.h  (32 dependent symbols)
        src/slice.h  (30 dependent symbols)
        src/serialize.h  (9 dependent symbols)
        src/quality.h  (8 dependent symbols)
        src/verbs_navigate.h  (8 dependent symbols)
        src/main.cpp  (7 dependent symbols)
        src/verbs_quality.h  (7 dependent symbols)
        src/mergescout.h  (6 dependent symbols)
  [2] tests to run (5) order=evidence: [changed] you edited it, [partner] named after a changed file, then hops asc (1 = direct); "(n): a, b" = n runner-less files sharing that evidence; a (run: …) is relative to root:
        test/verify_radix.cpp [hops=1]   (run: bash test/greptiercheck.sh)
        test/adaptivecutshapefix/adaptive_cut_shape_test.cpp [hops=2]   (run: bash test/adaptivecutshapecheck.sh)
        test/includeprecise_unit.cpp [hops=2]   (run: bash test/includeprecisecheck.sh)
        test/verify_csr.cpp [hops=2]   (run: bash test/a9disclosurecheck.sh)
        test/rustimport_unit.cpp [hops=4]   (run: bash test/rustimportprecisecheck.sh)
        script_gates_unmodelled=729 — test/*.sh gates never appear above: script-to-binary edges are not call edges (a path count)
  [3] co-change — usually edited with these but NOT in your diff (0) window="18mo@HEAD" commits="3939":
        (none — 3939 commits were mined and none co-edited a file outside your diff)
  next: --test-gate
`````

## `./build/ripwire . --test-gate`

*The pre-PR gate with real obligations — exit 4 when tests-to-run or untested blast radius is non-empty.*

**exit code: 4** — **wall time: 5.17s**

`````
<!-- ripwire test-gate schema=ripwire.test-gate/v1: tests <t p= changed= partner= hops= run=> + untested blast radius <u sym= p= l= ccx=>; exit 4 while either exists. window: total= has_more= next_offset= offset= limit= (capped=1 cut; next_offset= pastes as offset=). tests_capped=/untested_capped=: 1 = cut. counts_floor=1: every count is a FLOOR, never a total. graph_ambiguous=/graph_unresolved=: resolver gauge. graph_unindexed=N: N files no grammar could read (the map header's unindexed=); their calls raise neither gauge. declined_calls=K: K call sites left unbound (no evidence chose one def), in no count or row. at=: commit+dirty+shallow. root=: p= relative to it. next=: the one pasteable follow-up. impacted=N: symbols that transitively call the change (changed symbols excluded). shown_tests=/shown_untested=: t rows and u rows printed, two independent counts. script_gates_unmodelled=N: test/*.sh runners in the corpus, a path count; not call-graph modelled. run_first=N: the first N t rows have the most direct evidence (changed/partner/hops=1, else nearest hops=); not a skip list. script_gates_registered=N: shell gates test/regression.sh registers as suite members. script_gates_mapped=N: registered gates with exact dependency evidence (literal paths or RIPWIRE_TEST_DEPS). script_gates_unresolved_dynamic=N: registered gates with no mappable deps; they may cover the change unlisted. ccx_bar=N: the cognitive-complexity bar a u row's ccx= is read against. untested_modscope=N: <file-scope> owners excluded from untested= (#324, uncallable); still in impacted=. tests=/untested=: tests to run (t total) / impacted symbols no test reaches (u total). -->
<test-gate schema="ripwire.test-gate/v1" changed="1" impacted="190" tests="5" untested="178" untested_modscope="0" shown_tests="5" tests_capped="0" shown_untested="25" untested_capped="1" script_gates_unmodelled="729" script_gates_registered="683" script_gates_mapped="202" script_gates_unresolved_dy … [line truncated: 273 more bytes on this line]
<t p="test/verify_radix.cpp" hops="1" run="bash test/greptiercheck.sh"/>
<t p="test/adaptivecutshapefix/adaptive_cut_shape_test.cpp" hops="2" run="bash test/adaptivecutshapecheck.sh"/>
<t p="test/includeprecise_unit.cpp" hops="2" run="bash test/includeprecisecheck.sh"/>
<t p="test/verify_csr.cpp" hops="2" run="bash test/a9disclosurecheck.sh"/>
<t p="test/rustimport_unit.cpp" hops="4" run="bash test/rustimportprecisecheck.sh"/>
<u sym="dispatchMcpLine" p="src/mcp.h" l="1118" ccx="735"/>
<u sym="dispatchMain" p="src/main.cpp" l="4108" ccx="471"/>
<u sym="computeDelta" p="src/quality.h" l="7967" ccx="324"/>
<u sym="runForLens" p="src/verbs_for.h" l="2221" ccx="322"/>
<u sym="runQualityDelta" p="src/verbs_quality.h" l="1111" ccx="288"/>
<u sym="runDefaultMap" p="src/main.cpp" l="1629" ccx="284"/>
<u sym="serialize" p="src/serialize.h" l="2602" ccx="271"/>
<u sym="packTaskBundleText" p="src/packtask.h" l="1409" ccx="213"/>
<u sym="packSignatures" p="src/serialize.h" l="4640" ccx="197"/>
<u sym="runChangeViews" p="src/verbs_change.h" l="245" ccx="157"/>
<u sym="runBatchSub" p="src/mcpverbs.h" l="5220" ccx="138"/>
<u sym="forTaskText" p="src/mcpverbs.h" l="1818" ccx="109"/>
<u sym="serializeJson" p="src/serialize.h" l="8680" ccx="100"/>
<u sym="applyMentionBoost" p="src/mention.h" l="980" ccx="92"/>
<u sym="packLego" p="src/serialize.h" l="7724" ccx="92"/>
<u sym="runLsp" p="src/lsp.h" l="902" ccx="85"/>
<u sym="computeLensRanking" p="src/verbs_for.h" l="78" ccx="81"/>
<u sym="sliceEmitBody" p="src/slice.h" l="3272" ccx="78"/>
<u sym="compute" p="src/slicediff.h" l="546" ccx="75"/>
<u sym="fetchBody" p="src/mcpverbs.h" l="4787" ccx="74"/>
<u sym="runCrossRef" p="src/verbs_change.h" l="1443" ccx="73"/>
<u sym="runMcpHttp" p="src/mcpserver.h" l="418" ccx="68"/>
<u sym="runEval" p="src/eval.h" l="171" ccx="66"/>
<u sym="runSlice" p="src/verbs_navigate.h" l="1304" ccx="62"/>
<u sym="writeHandoffPacket" p="src/handoff.h" l="237" ccx="57"/>
</test-gate>
`````

## `./build/ripwire . --quality-delta`

*Every row carries p="file:line", the gating rows are marked gating="1" and now bar= (the threshold each numeric row is judged against), and the exit-2 refusal prints a naming line on stderr; a gating row carries a pasteable next=.*

**exit code: 2** — **wall time: 22.67s**

`````
<!-- ripwire quality-delta schema=ripwire.quality-delta/v1: only what the change made WORSE vs baseline=: regressions= minor= gating=; <r kind= sym= p= was= now= gating= bar=>, <sa> acked. value-ref-excluded=N: internal functions kept off because a table, field or argument holds them (matched by name, not a proven call); a floor. at=: commit+dirty+shallow. next=: the one pasteable follow-up. stale=N: ack ledger rows whose target no longer applies (sa rows); never gating. preexisting-worse=N: regressions on symbols that existed at baseline; only these gate (when major). new-symbol=N: regressions on NEW code; never gate, but the debt is yours: read them. register-macro-excluded=N: symbols kept out of dead-code as self-registering test/bench macros; a floor. api-new-surface=N: new PUBLIC symbols; a count, never gates, not in regressions=. renames=/rename_window_commits=: git rename pairs read over that many commits, to re-file baseline and acks. acked_by_rename=/acked_by_content=: acked= suppressions matched via git renames / an equal body hash. renames_window_truncated=1: history is deeper than the rename window, older renames unread. r surface=: the api-surface tier, new-symbol or contract-change. acked=N: findings suppressed by the ack ledger, listed as sa rows; never gating. r sev=minor: a small numeric delta, counted in minor=, never gating (absent: major). r origin=new-symbol: the finding is on NEW code, never gating (absent: preexisting-worse). sa key=/why=: the stale ack's ledger hash / target-gone (names nothing now) or finding-gone (no longer fires). r members=/tokens=: a duplication row's clone group (member ids) / their shared normalized-token count. -->
<quality-delta schema="ripwire.quality-delta/v1" baseline="git-HEAD" regressions="9" minor="1" acked="0" stale="134" preexisting-worse="6" new-symbol="3" gating="5" register-macro-excluded="62" api-new-surface="2" at="c7920353a+dirty" renames="57" rename_window_commits="400" acked_by_rename="0" acke … [line truncated: 70 more bytes on this line]
<r kind="api-surface" sym="src/infra/sortutil.h::rw::sortutil::nonNegativeFloatDescKey" was="1" now="2" surface="contract-change" p="src/infra/sortutil.h:109" gating="1" next="--expand=src/infra/sortutil.h:nonNegativeFloatDescKey"/>
<r kind="complexity" sym="src/infra/sortutil.h::rw::sortutil::lessByScoreDescId" was="1" now="67" bar="15" p="src/infra/sortutil.h:49" gating="1" next="--expand=src/infra/sortutil.h:lessByScoreDescId"/>
<r kind="dead-code" sym="src/infra/sortutil.h::rw::sortutil::nonNegativeFloatAscKeyCopy" origin="new-symbol" p="src/infra/sortutil.h:119"/>
<r kind="dead-code" sym="src/infra/sortutil.h::rw::sortutil::sortScoredIdsWithOptions" origin="new-symbol" p="src/infra/sortutil.h:129"/>
<r kind="duplication" members="src/infra/sortutil.h::rw::sortutil::nonNegativeFloatAscKeyCopy | src/infra/sortutil.h::rw::sortutil::nonNegativeFloatDescKey" tokens="59" p="src/infra/sortutil.h:119" gating="1"/>
<r kind="nesting" sym="src/infra/sortutil.h::rw::sortutil::lessByScoreDescId" was="1" now="6" bar="4" p="src/infra/sortutil.h:49" gating="1" next="--expand=src/infra/sortutil.h:lessByScoreDescId"/>
<r kind="new-clone-of-reused-helper" sym="src/infra/sortutil.h::rw::sortutil::nonNegativeFloatAscKeyCopy | src/infra/sortutil.h::rw::sortutil::nonNegativeFloatDescKey" was="0" now="4" p="src/infra/sortutil.h:119" gating="1" next="--expand=src/infra/sortutil.h:nonNegativeFloatDescKey"/>
<r kind="params" sym="src/infra/sortutil.h::rw::sortutil::sortScoredIdsWithOptions" was="0" now="8" bar="5" origin="new-symbol" p="src/infra/sortutil.h:129"/>
<r kind="verbosity" sym="src/infra/sortutil.h::rw::sortutil::lessByScoreDescId" was="8" now="47" bar="60" sev="minor" p="src/infra/sortutil.h:49"/>
<sa kind="api-surface" key="085e3d408c2c4a35" why="target-gone"/>
<sa kind="api-surface" key="155d74d341a49f3c" why="target-gone"/>
<sa kind="api-surface" key="1a15386c2d1e47af" why="target-gone"/>
<sa kind="api-surface" key="298e798c7f075715" why="target-gone"/>
<sa kind="api-surface" key="56acdf9b5c314a14" why="target-gone"/>
<sa kind="api-surface" key="5a07390012b46e06" why="target-gone"/>
<sa kind="api-surface" key="6eef859578c8c376" why="target-gone"/>
<sa kind="api-surface" key="6f2394762f82a855" why="target-gone"/>
<sa kind="api-surface" key="7f2c3eefdf6e512e" why="target-gone"/>
<sa kind="api-surface" key="802e513731103806" why="target-gone"/>
<sa kind="api-surface" key="b6a24afef32a68a8" why="target-gone"/>
<sa kind="api-surface" key="c923e661c197b265" why="target-gone"/>
<sa kind="api-surface:new-symbol" key="1926b0d9e94541a0" why="target-gone"/>
<sa kind="api-surface:new-symbol" key="1d3814ba687a4aef" why="target-gone"/>
<sa kind="api-surface:new-symbol" key="1db76028879244ef" why="target-gone"/>
<sa kind="api-surface:new-symbol" key="36e39c7ab0fc1686" why="target-gone"/>
<sa kind="api-surface:new-symbol" key="4bce64bd920de0c3" why="target-gone"/>
<sa kind="api-surface:new-symbol" key="61f0e361ef7dee27" why="target-gone"/>
<sa kind="api-surface:new-symbol" key="79625906f9f71ad0" why="target-gone"/>
… [116 more display lines; full output is 15456 bytes on 1 raw line(s)]
`````

stderr:

`````
ripwire: no ./.ripwire_quality_baseline — auto-comparing the working tree vs git HEAD (commit the baseline with --quality-baseline to pin it)
ripwire: --quality-delta gating: 5 preexisting-worse major finding(s); first: api-surface src/infra/sortutil.h::rw::sortutil::nonNegativeFloatDescKey at src/infra/sortutil.h:109 (was=1 now=2)
`````

## `./build/ripwire . --quality-delta --legend=full`

*The same gating report under --legend=full — same rows, same exit 2; the default compact comment (schema="ripwire.quality-delta/v1", the shape an agent's edit loop should run) becomes ~4 KB of prose legend.*

**exit code: 2** — **wall time: 8.55s**

`````
<!-- ripwire quality-delta: only what a change made WORSE against the floor baseline= names below. Descriptive: weigh and fix the real ones, do not game the number (a wrong abstraction beats a low score). ELEVEN KINDS, and kind= on every row names which one: complexity over the ccx bar, verbosity (LOC), nesting, params, duplication, dead-code, api-surface (new public contract drift), error-masking, short-horizon-churn, new-clone-of-reused-helper, placeholder (added stub/TODO). THREE independent axes, in this order: (1) acked findings are suppressed entirely (acked= counts them); (2) ORIGIN — a finding on a symbol that EXISTED at the baseline is preexisting-worse (no origin attribute), one that exists only because the code is NEW carries origin="new-symbol"; (3) MATERIALITY — a small numeric delta is sev="minor", and minor= counts them. EXIT 2 fires only on preexisting-worse AND major, the gating= count; new-symbol rows never gate, so exit 0 is NOT a verdict on them — nothing that existed got worse, but the new debt is yours: read them. Clone kinds are new-symbol only when EVERY member is new; short-horizon-churn is preexisting by construction. preexisting-worse= and new-symbol= partition regressions=. stale= is a FOURTH axis, never gating and never counted in regressions=: rows in the .ripwire_quality_acks ledger whose target no longer applies. api-new-surface= COUNTS the new PUBLIC symbols (never gates, not in regressions=, printed even at zero). register-macro-excluded= is a FLOOR, not a finding: symbols this run excluded from the dead-code kind because their own definition is a registered self-registering test/benchmark macro call. Never gates, never counted in regressions=, printed even at zero (zero means none excluded, not that the check did not run). A gating row's next= is the one pasteable follow-up: expand on FILE:NAME, the body to fix (a duplication row names a SET and carries none). bar= on a complexity/verbosity/nesting/params row is the threshold now= is judged against (ccx 15, loc 60, nest 4, params 5). baseline="git-HEAD" means no sidecar existed, so the working tree was auto-compared against the HEAD tree — anything already committed cannot appear. at= is the git commit (plus a dirty marker when the working tree differs) this list was computed at. The registered families are doctest/Catch2 TEST_CASE, GoogleTest TEST/TEST_F/TEST_P, Google Benchmark BENCHMARK, plus any name a .ripwire_config register_macros= line adds; each registers itself through a static initializer the call graph cannot see, so zero in-edges on one is not evidence of anything. value-ref-excluded= is a FLOOR, not a finding: symbols this run kept out of the dead-code kind only because a table, field, argument or registering decorator holds them as a VALUE (matched by name; it is not a proven call; the callers verb lists the sites; @classmethod-style wrappers do not count), the --dead-code verb's own rule. Never gates; absent at zero. IDENTITY across a rename or a move: a finding is keyed path::scope::name, which a rename would destroy, so the baseline and the .ripwire_quality_acks ledger are both re-filed into the CURRENT tree's identity before either is read, by two EXACT mechanisms — git's own rename record, and equality of a whitespace-and-name-scrubbed body hash — never a similarity heuristic. renames= is how many rename pairs were read, rename_window_commits= how deep the commit window went, acked_by_rename= and acked_by_content= how many of the acked= suppressions each mechanism is responsible for. Three appear ONLY when true, so an absent one is not a silent no: renames_window_truncated= (history is deeper than the window), renames_truncated= (the pair cap was hit), renames_ambiguous= (an ancestor two current symbols both claim — refused rather than guessed). ORIGIN reads the re-filed baseline too, so a regression carried in with a rename is judged preexisting-worse and GATES instead of slipping through as new-symbol. FLOORS, stated because silence here would read as a guarantee: the two clone kinds key on a member-SET hash and are NOT re-filed, so a clone ack still dies on a rename; ORIGIN follows the rename record but never content, because the baseline stores no content id at all; and a move git recorded no rename for still reads as new-symbol. Each sa row carries key= (the ack identity as stored) and why=, which is target-gone (the key names no symbol or group any more) or finding-gone (the target survived, this kind just does not fire on it). sym= and p=path:line name WHICH ack it is, and are present exactly when the key still names a live symbol: on every finding-gone row, on none of the target-gone rows (there is nothing left to name), and on neither clone kind — a clone key hashes a member SET that no single symbol carries, so those rows are unnameable by construction rather than guessed at. Hygiene disclosure only — the ledger file is never auto-edited. ROWS: sym= is the canonical id the finding regressed on; was= and now= carry the before/after value for the numeric kinds; p="path:line" is the locator (root-relative; the first-sorting member for the clone kinds; omitted, never faked, when none resolves). churn= and surface= are per-kind classification facets (short-horizon-churn's self/ambient split; api-surface's new-symbol/contract-change tier). churn= facets never gate alone: the kind gates only on 2+ COMMITTED in-window rewrites of the edited lines. Every row the header's gating= counter counts also carries a gating attribute set to 1 — marked positively, never by the ABSENCE of sev or origin. CLONE ROWS name the whole group rather than one symbol: members= is the member list and tokens= its shared normalized-token count (the same per-group pair the clones verb reports). idiom= names a RECOGNIZED BODY SHAPE every member spells, out of a closed set of three (threshold-ladder, switch-name-table, builder-chain). idiom= alone changes nothing; a group that ALSO shares no non-keyword identifier between any two members, sits in pairwise-distinct enclosing contexts, and stays under 80 normalized tokens is an idiom COLLISION rather than a copy, and is reported minor instead of gating. Break any one of those and it gates as before, idiom= and all: two bucketing ladders over the SAME enum are a copy. The shape is read off the body's token stream and not a parse tree, so a macro-assembled body classifies as whatever its raw tokens spell — the name is printed so the call can be overruled by reading. -->
<quality-delta baseline="git-HEAD" regressions="9" minor="1" acked="0" stale="134" preexisting-worse="6" new-symbol="3" gating="5" register-macro-excluded="62" api-new-surface="2" at="c7920353a+dirty" renames="57" rename_window_commits="400" acked_by_rename="0" acked_by_content="0" renames_window_tr … [line truncated: 36 more bytes on this line]
<r kind="api-surface" sym="src/infra/sortutil.h::rw::sortutil::nonNegativeFloatDescKey" was="1" now="2" surface="contract-change" p="src/infra/sortutil.h:109" gating="1" next="--expand=src/infra/sortutil.h:nonNegativeFloatDescKey"/>
<r kind="complexity" sym="src/infra/sortutil.h::rw::sortutil::lessByScoreDescId" was="1" now="67" bar="15" p="src/infra/sortutil.h:49" gating="1" next="--expand=src/infra/sortutil.h:lessByScoreDescId"/>
<r kind="dead-code" sym="src/infra/sortutil.h::rw::sortutil::nonNegativeFloatAscKeyCopy" origin="new-symbol" p="src/infra/sortutil.h:119"/>
<r kind="dead-code" sym="src/infra/sortutil.h::rw::sortutil::sortScoredIdsWithOptions" origin="new-symbol" p="src/infra/sortutil.h:129"/>
<r kind="duplication" members="src/infra/sortutil.h::rw::sortutil::nonNegativeFloatAscKeyCopy | src/infra/sortutil.h::rw::sortutil::nonNegativeFloatDescKey" tokens="59" p="src/infra/sortutil.h:119" gating="1"/>
<r kind="nesting" sym="src/infra/sortutil.h::rw::sortutil::lessByScoreDescId" was="1" now="6" bar="4" p="src/infra/sortutil.h:49" gating="1" next="--expand=src/infra/sortutil.h:lessByScoreDescId"/>
<r kind="new-clone-of-reused-helper" sym="src/infra/sortutil.h::rw::sortutil::nonNegativeFloatAscKeyCopy | src/infra/sortutil.h::rw::sortutil::nonNegativeFloatDescKey" was="0" now="4" p="src/infra/sortutil.h:119" gating="1" next="--expand=src/infra/sortutil.h:nonNegativeFloatDescKey"/>
<r kind="params" sym="src/infra/sortutil.h::rw::sortutil::sortScoredIdsWithOptions" was="0" now="8" bar="5" origin="new-symbol" p="src/infra/sortutil.h:129"/>
<r kind="verbosity" sym="src/infra/sortutil.h::rw::sortutil::lessByScoreDescId" was="8" now="47" bar="60" sev="minor" p="src/infra/sortutil.h:49"/>
<sa kind="api-surface" key="085e3d408c2c4a35" why="target-gone"/>
<sa kind="api-surface" key="155d74d341a49f3c" why="target-gone"/>
<sa kind="api-surface" key="1a15386c2d1e47af" why="target-gone"/>
<sa kind="api-surface" key="298e798c7f075715" why="target-gone"/>
<sa kind="api-surface" key="56acdf9b5c314a14" why="target-gone"/>
<sa kind="api-surface" key="5a07390012b46e06" why="target-gone"/>
<sa kind="api-surface" key="6eef859578c8c376" why="target-gone"/>
<sa kind="api-surface" key="6f2394762f82a855" why="target-gone"/>
<sa kind="api-surface" key="7f2c3eefdf6e512e" why="target-gone"/>
<sa kind="api-surface" key="802e513731103806" why="target-gone"/>
<sa kind="api-surface" key="b6a24afef32a68a8" why="target-gone"/>
<sa kind="api-surface" key="c923e661c197b265" why="target-gone"/>
<sa kind="api-surface:new-symbol" key="1926b0d9e94541a0" why="target-gone"/>
<sa kind="api-surface:new-symbol" key="1d3814ba687a4aef" why="target-gone"/>
<sa kind="api-surface:new-symbol" key="1db76028879244ef" why="target-gone"/>
<sa kind="api-surface:new-symbol" key="36e39c7ab0fc1686" why="target-gone"/>
<sa kind="api-surface:new-symbol" key="4bce64bd920de0c3" why="target-gone"/>
<sa kind="api-surface:new-symbol" key="61f0e361ef7dee27" why="target-gone"/>
<sa kind="api-surface:new-symbol" key="79625906f9f71ad0" why="target-gone"/>
… [116 more display lines; full output is 20270 bytes on 1 raw line(s)]
`````

stderr:

`````
ripwire: no ./.ripwire_quality_baseline — auto-comparing the working tree vs git HEAD (commit the baseline with --quality-baseline to pin it)
ripwire: --quality-delta gating: 5 preexisting-worse major finding(s); first: api-surface src/infra/sortutil.h::rw::sortutil::nonNegativeFloatDescKey at src/infra/sortutil.h:109 (was=1 now=2)
`````

## `./build/ripwire . --quality-delta --json`

*The same findings as JSON (one of the CI/scripting verbs --json supports) — same exit 2 as the XML form.*

**exit code: 2** — **wall time: 8.82s**

`````
{"baseline":"git-HEAD","regressions":9,"minor":1,"acked":0,"stale":134,"preexisting-worse":6,"new-symbol":3,"gating":5,"register-macro-excluded":62,"api-new-surface":2,"at":"c7920353a+dirty","renames":57,"rename_window_commits":400,"acked_by_rename":0,"acked_by_content":0,"renames_window_truncated": … [line truncated: 211 more bytes on this line]
{"kind":"complexity","sym":"src/infra/sortutil.h::rw::sortutil::lessByScoreDescId","was":1,"now":67,"p":"src/infra/sortutil.h:49","gating":true},
{"kind":"dead-code","sym":"src/infra/sortutil.h::rw::sortutil::nonNegativeFloatAscKeyCopy","p":"src/infra/sortutil.h:119","origin":"new-symbol"},
{"kind":"dead-code","sym":"src/infra/sortutil.h::rw::sortutil::sortScoredIdsWithOptions","p":"src/infra/sortutil.h:129","origin":"new-symbol"},
{"kind":"duplication","members":"src/infra/sortutil.h::rw::sortutil::nonNegativeFloatAscKeyCopy | src/infra/sortutil.h::rw::sortutil::nonNegativeFloatDescKey","tokens":59,"p":"src/infra/sortutil.h:119","gating":true},
{"kind":"nesting","sym":"src/infra/sortutil.h::rw::sortutil::lessByScoreDescId","was":1,"now":6,"p":"src/infra/sortutil.h:49","gating":true},
{"kind":"new-clone-of-reused-helper","sym":"src/infra/sortutil.h::rw::sortutil::nonNegativeFloatAscKeyCopy | src/infra/sortutil.h::rw::sortutil::nonNegativeFloatDescKey","was":0,"now":4,"p":"src/infra/sortutil.h:119","gating":true},
{"kind":"params","sym":"src/infra/sortutil.h::rw::sortutil::sortScoredIdsWithOptions","was":0,"now":8,"p":"src/infra/sortutil.h:129","origin":"new-symbol"},
{"kind":"verbosity","sym":"src/infra/sortutil.h::rw::sortutil::lessByScoreDescId","was":8,"now":47,"p":"src/infra/sortutil.h:49","sev":"minor"}],
"sa":[{"kind":"api-surface","key":"085e3d408c2c4a35","why":"target-gone"},
{"kind":"api-surface","key":"155d74d341a49f3c","why":"target-gone"},
{"kind":"api-surface","key":"1a15386c2d1e47af","why":"target-gone"},
{"kind":"api-surface","key":"298e798c7f075715","why":"target-gone"},
{"kind":"api-surface","key":"56acdf9b5c314a14","why":"target-gone"},
{"kind":"api-surface","key":"5a07390012b46e06","why":"target-gone"},
{"kind":"api-surface","key":"6eef859578c8c376","why":"target-gone"},
{"kind":"api-surface","key":"6f2394762f82a855","why":"target-gone"},
{"kind":"api-surface","key":"7f2c3eefdf6e512e","why":"target-gone"},
{"kind":"api-surface","key":"802e513731103806","why":"target-gone"},
{"kind":"api-surface","key":"b6a24afef32a68a8","why":"target-gone"},
{"kind":"api-surface","key":"c923e661c197b265","why":"target-gone"},
{"kind":"api-surface:new-symbol","key":"1926b0d9e94541a0","why":"target-gone"},
{"kind":"api-surface:new-symbol","key":"1d3814ba687a4aef","why":"target-gone"},
{"kind":"api-surface:new-symbol","key":"1db76028879244ef","why":"target-gone"},
{"kind":"api-surface:new-symbol","key":"36e39c7ab0fc1686","why":"target-gone"},
{"kind":"api-surface:new-symbol","key":"4bce64bd920de0c3","why":"target-gone"},
{"kind":"api-surface:new-symbol","key":"61f0e361ef7dee27","why":"target-gone"},
{"kind":"api-surface:new-symbol","key":"79625906f9f71ad0","why":"target-gone"},
{"kind":"api-surface:new-symbol","key":"8ecb190954dce18a","why":"target-gone"},
{"kind":"api-surface:new-symbol","key":"995375dfa4e63104","why":"target-gone"},
… [113 more display lines; full output is 14067 bytes on 1 raw line(s)]
`````

stderr:

`````
ripwire: no ./.ripwire_quality_baseline — auto-comparing the working tree vs git HEAD (commit the baseline with --quality-baseline to pin it)
ripwire: --quality-delta gating: 5 preexisting-worse major finding(s); first: api-surface src/infra/sortutil.h::rw::sortutil::nonNegativeFloatDescKey at src/infra/sortutil.h:109 (was=1 now=2)
`````

## `./build/ripwire . --quality-delta --quality-ack --ack-only=zzznope`

*NEW FLAG: --ack-only matching nothing REFUSES rather than falling back to acking everything.*

**exit code: 1** — **wall time: 5.63s**

`````
(empty)
`````

stderr:

`````
ripwire: no ./.ripwire_quality_baseline — auto-comparing the working tree vs git HEAD (commit the baseline with --quality-baseline to pin it)
ripwire: ack provenance backfill — 0 clone row(s) reconstructed from the current tree, 224 re-derived, 9 left UNVERIFIED (their group was not found here — a floor, not proof it is gone), 57 left legacy (member set not found cloning here — a floor, not proof it is gone), 1328 ineligible (no cur … [line truncated: 198 more bytes on this line]
ripwire: --ack-only=zzznope matched none of the 9 finding(s) — nothing written
`````

## `./build/ripwire . --quality-delta --quality-ack --ack-only=api-surface`

*NEW FLAG: ack only the api-surface findings — a per-finding ratchet instead of a rubber stamp.*

**wall time: 5.59s**

`````
(empty)
`````

stderr:

`````
ripwire: no ./.ripwire_quality_baseline — auto-comparing the working tree vs git HEAD (commit the baseline with --quality-baseline to pin it)
ripwire: ack provenance backfill — 0 clone row(s) reconstructed from the current tree, 224 re-derived, 9 left UNVERIFIED (their group was not found here — a floor, not proof it is gone), 57 left legacy (member set not found cloning here — a floor, not proof it is gone), 1328 ineligible (no cur … [line truncated: 198 more bytes on this line]
ripwire: acknowledged 1 of 9 finding(s) (8 left UNACKED by --ack-only, 0 already acked) → ./.ripwire_quality_acks
`````

## `./build/ripwire . --quality-delta`

*Re-run after the partial ack: acked=3, the rest still gate (exit 2).*

**exit code: 2** — **wall time: 11.33s**

`````
<!-- ripwire quality-delta schema=ripwire.quality-delta/v1: only what the change made WORSE vs baseline=: regressions= minor= gating=; <r kind= sym= p= was= now= gating= bar=>, <sa> acked. value-ref-excluded=N: internal functions kept off because a table, field or argument holds them (matched by name, not a proven call); a floor. at=: commit+dirty+shallow. next=: the one pasteable follow-up. stale=N: ack ledger rows whose target no longer applies (sa rows); never gating. preexisting-worse=N: regressions on symbols that existed at baseline; only these gate (when major). new-symbol=N: regressions on NEW code; never gate, but the debt is yours: read them. register-macro-excluded=N: symbols kept out of dead-code as self-registering test/bench macros; a floor. api-new-surface=N: new PUBLIC symbols; a count, never gates, not in regressions=. renames=/rename_window_commits=: git rename pairs read over that many commits, to re-file baseline and acks. acked_by_rename=/acked_by_content=: acked= suppressions matched via git renames / an equal body hash. renames_window_truncated=1: history is deeper than the rename window, older renames unread. acked=N: findings suppressed by the ack ledger, listed as sa rows; never gating. r sev=minor: a small numeric delta, counted in minor=, never gating (absent: major). r origin=new-symbol: the finding is on NEW code, never gating (absent: preexisting-worse). sa key=/why=: the stale ack's ledger hash / target-gone (names nothing now) or finding-gone (no longer fires). r members=/tokens=: a duplication row's clone group (member ids) / their shared normalized-token count. -->
<quality-delta schema="ripwire.quality-delta/v1" baseline="git-HEAD" regressions="8" minor="1" acked="1" stale="134" preexisting-worse="5" new-symbol="3" gating="4" register-macro-excluded="62" api-new-surface="2" at="c7920353a+dirty" renames="57" rename_window_commits="400" acked_by_rename="0" acke … [line truncated: 70 more bytes on this line]
<r kind="complexity" sym="src/infra/sortutil.h::rw::sortutil::lessByScoreDescId" was="1" now="67" bar="15" p="src/infra/sortutil.h:49" gating="1" next="--expand=src/infra/sortutil.h:lessByScoreDescId"/>
<r kind="dead-code" sym="src/infra/sortutil.h::rw::sortutil::nonNegativeFloatAscKeyCopy" origin="new-symbol" p="src/infra/sortutil.h:119"/>
<r kind="dead-code" sym="src/infra/sortutil.h::rw::sortutil::sortScoredIdsWithOptions" origin="new-symbol" p="src/infra/sortutil.h:129"/>
<r kind="duplication" members="src/infra/sortutil.h::rw::sortutil::nonNegativeFloatAscKeyCopy | src/infra/sortutil.h::rw::sortutil::nonNegativeFloatDescKey" tokens="59" p="src/infra/sortutil.h:119" gating="1"/>
<r kind="nesting" sym="src/infra/sortutil.h::rw::sortutil::lessByScoreDescId" was="1" now="6" bar="4" p="src/infra/sortutil.h:49" gating="1" next="--expand=src/infra/sortutil.h:lessByScoreDescId"/>
<r kind="new-clone-of-reused-helper" sym="src/infra/sortutil.h::rw::sortutil::nonNegativeFloatAscKeyCopy | src/infra/sortutil.h::rw::sortutil::nonNegativeFloatDescKey" was="0" now="4" p="src/infra/sortutil.h:119" gating="1" next="--expand=src/infra/sortutil.h:nonNegativeFloatDescKey"/>
<r kind="params" sym="src/infra/sortutil.h::rw::sortutil::sortScoredIdsWithOptions" was="0" now="8" bar="5" origin="new-symbol" p="src/infra/sortutil.h:129"/>
<r kind="verbosity" sym="src/infra/sortutil.h::rw::sortutil::lessByScoreDescId" was="8" now="47" bar="60" sev="minor" p="src/infra/sortutil.h:49"/>
<sa kind="api-surface" key="085e3d408c2c4a35" why="target-gone"/>
<sa kind="api-surface" key="155d74d341a49f3c" why="target-gone"/>
<sa kind="api-surface" key="1a15386c2d1e47af" why="target-gone"/>
<sa kind="api-surface" key="298e798c7f075715" why="target-gone"/>
<sa kind="api-surface" key="56acdf9b5c314a14" why="target-gone"/>
<sa kind="api-surface" key="5a07390012b46e06" why="target-gone"/>
<sa kind="api-surface" key="6eef859578c8c376" why="target-gone"/>
<sa kind="api-surface" key="6f2394762f82a855" why="target-gone"/>
<sa kind="api-surface" key="7f2c3eefdf6e512e" why="target-gone"/>
<sa kind="api-surface" key="802e513731103806" why="target-gone"/>
<sa kind="api-surface" key="b6a24afef32a68a8" why="target-gone"/>
<sa kind="api-surface" key="c923e661c197b265" why="target-gone"/>
<sa kind="api-surface:new-symbol" key="1926b0d9e94541a0" why="target-gone"/>
<sa kind="api-surface:new-symbol" key="1d3814ba687a4aef" why="target-gone"/>
<sa kind="api-surface:new-symbol" key="1db76028879244ef" why="target-gone"/>
<sa kind="api-surface:new-symbol" key="36e39c7ab0fc1686" why="target-gone"/>
<sa kind="api-surface:new-symbol" key="4bce64bd920de0c3" why="target-gone"/>
<sa kind="api-surface:new-symbol" key="61f0e361ef7dee27" why="target-gone"/>
<sa kind="api-surface:new-symbol" key="79625906f9f71ad0" why="target-gone"/>
<sa kind="api-surface:new-symbol" key="8ecb190954dce18a" why="target-gone"/>
… [115 more display lines; full output is 15159 bytes on 1 raw line(s)]
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

**wall time: 1.64s**

`````
<!-- ripwire edit-check schema=ripwire.edit-check/v1: sym='s contract NOW vs HEAD: status=unchanged|new-symbol|contract-change; <c n= p= incompatible=1 sites_l=> callers. counts_floor=1: every count is a FLOOR, never a total. graph_ambiguous=/graph_unresolved=: resolver gauge. graph_unindexed=N: N files no grammar could read (the map header's unindexed=); their calls raise neither gauge. est_tokens=: price as emitted (an upper bound under compact). at=: commit+dirty+shallow. root=: p= relative to it. next=: the one pasteable follow-up. defs=N: overloads at this site (same file, scope, name) folded into one contract; params compared by MAX. callers=N: callers of sym= (the c rows' total; a floor). -->
<edit-check schema="ripwire.edit-check/v1" sym="nonNegativeFloatDescKey" t="fn" p="src/infra/sortutil.h:109" status="contract-change" defs="1" params_was="1" params_now="2" public_was="1" public_now="1" defs_was="1" defs_now="1" change="params,broken-callers" callers="4" incompatible="4" at="c792035 … [line truncated: 162 more bytes on this line]
<c n="benchScores" p="bench/bench_radix_ab.cpp:133" incompatible="1" sites_l="146,152"/>
<c n="benchAdaptive" p="bench/bench_radix_ab.cpp:157" incompatible="1" sites_l="162"/>
<c n="radixSortNonNegativeFloatsDesc" p="src/infra/sortutil.h:138" incompatible="1" sites_l="147"/>
<c n="radixSortByScoreDescId" p="src/infra/sortutil.h:153" incompatible="1" sites_l="213"/>
</edit-check>
`````

## `./build/ripwire . --edit-check=nonNegativeFloatDescKey --legend=full`

*The same verdict under --legend=full: the default's one compact comment (the post-edit reflex at its cheapest) becomes ~5.7 KB of prose legend, every <c incompatible=> row identical.*

**wall time: 1.33s**

`````
<!-- ripwire edit-check: SYM's contract (param count + publicness) NOW vs git HEAD — unchanged/new-symbol/contract-change, or no-baseline when the root has no git HEAD to compare against (not a repository, or no commit yet): then NOTHING is claimed about the contract, and a symbol is never called new for want of a baseline — plus its 1-hop callers. A caller is flagged incompatible="1" when its argument count was reliably counted and NO definition in the folded set could accept it: every one has a FIXED arity that disagrees. A variadic, defaulted or implicit-receiver definition (a Python/Ruby method, whose params counts the self/cls the call site never writes) has no fixed arity and is never flagged. That makes the ARITY half one-sided — a call the compared definitions could accept is never flagged — but it is NOT a proof that the call site binds to THIS definition. Call edges are matched by NAME, so a receiver-qualified call to a same-named callee this tool does not index (a standard-library or third-party method) is measured against the one definition it does index; a clean, compiling tree can therefore carry a nonzero incompatible= with nothing edited at all, and on a widely-shared name it can be most of that name's callers. Read incompatible= as a fact about the tree as it stands — call sites worth OPENING, not a verdict — and status= as a fact about the edit. Warm path hits the qheadsnap/qsnap cache — never a full quality-delta style recompute. defs= is how many DEFINITIONS at this site (same file, same scope, same name — the overload set) are folded into this one contract; a selector matching more than one SITE is refused instead, so defs= only ever counts overloads. params_was and params_now are the MAX over that set on each side (the same MAX the baseline snapshot stores), and publicness is the OR. That MAX has TWO consequences, in opposite directions. It can read like a break and not be one: adding a WIDER overload beside an unchanged one raises params_now with no existing definition altered, so it reports status="contract-change" with incompatible="0" and a def row still carrying the old parameter count — no seen caller breaks. And it can read like safety and not be: REMOVING an overload whose parameter count is BELOW the MAX moves neither number, because the MAX survives on both sides, while the call site that used the removed definition no longer binds. defs_was=/defs_now= is what closes that: the count of definitions sharing this symbol's DEFINITION SITE — same file, same scope, same name — on each side. That is the population the baseline snapshot buckets by, so the two numbers answer the same question and are equal on an unedited tree. A same-named definition in ANOTHER FILE is a different contract and is counted on neither side, so defs_now= agrees with the root's defs= by construction and only defs_was= can move it. status is therefore the join of THREE was-vs-now facts — the params MAX, publicness, and the definition COUNT — and change= names which of them carried it. change= adds broken-callers when a seen caller is also flagged, but never on its own — for the reason stated at the top: incompatible= describes the TREE and status= describes the EDIT, so a headline must not turn on it. RESIDUAL: an overload whose arity changes BELOW the MAX while the COUNT stays the same moves none of the three. The root's incompatible= is the COUNT of flagged callers (a c row's incompatible="1" is the per-caller flag). sites_l= rides on a flagged row only: a c row's p= is where that CALLER is DEFINED, and sites_l= is the ascending LINE list of its call-role reference sites to this name — the lines to open, the same rows the uses verb prints, including the ones whose argument count could not be counted (so sites_l= can be wider than the evidence the flag rests on). Two calls on one line are ONE site. p= is the definition the selector resolved to; when defs is above 1 EVERY folded definition is listed as its own def row (p=, t=, params=), which is what tells a widened single definition apart from an added overload. At defs="1" no def row is emitted: the root's own p=/t= is that definition, and params_now is its parameter count. next= is the one pasteable follow-up: on a contract-change the uses verb on SYM (the call sites), otherwise the test gate on the definition's file. est_tokens= prices THIS document, through the tool's ONE emitted-bytes estimator. counts_floor="1" means every count here is a FLOOR, never a total: edges are extracted from source TEXT by NAME. Missing: dynamic dispatch (virtual/interface/duck-typed), a most-vexing-parse declaration with no call expression, a function-pointer/callback bound to more than one function in scope (reassigned, table-indexed, lambda-bound, or address-taken/reference-bound), and a plain-name binding (fp=handler) whose variable type is not PROVABLY a function pointer (a same-file typedef/declarator; a HEADER typedef is missed; auto/template types are read as unpinned, so KEPT). A macro-generated call site is role="macro" only when its name uniquely names an indexed function-like #define (C-family, t="macro"); a shared name stays a plain call, an unindexed macro is no edge. Read a zero as "none found", never as "none exists". graph_ambiguous=/graph_unresolved= are the whole graph's resolver gauge (calls split over several defs / calls whose in-repo defs were all language-filtered), the map header's ambiguous=/unresolved=. graph_unindexed=N is a third gauge: files no grammar could read (the map header's unindexed=), whose calls raise neither gauge above; absent when zero, and so is this sentence. COUNTING UNIT differs by verb: callers, callees, edit-check, graph-query and pr-context counts are DISTINCT SYMBOLS (repeated calls from one caller, and calls to two overloads, collapse into ONE row; multiplicity survives only in the call graph's edge weight). The reach counts (impact's reaches=, pr-context's dependents=) are the size of a transitive reach SET, each symbol counted once. The uses verb counts call SITES, one row per occurrence — a larger count there for the same symbol is these units agreeing, not disagreeing. The map header's edges= is a unit again different — distinct (caller,callee) PAIRS — and that document carries neither this marker nor this clause. -->
<edit-check sym="nonNegativeFloatDescKey" t="fn" p="src/infra/sortutil.h:109" status="contract-change" defs="1" params_was="1" params_now="2" public_was="1" public_now="1" defs_was="1" defs_now="1" change="params,broken-callers" callers="4" incompatible="4" at="c7920353a+dirty" graph_ambiguous="1028 … [line truncated: 132 more bytes on this line]
<c n="benchScores" p="bench/bench_radix_ab.cpp:133" incompatible="1" sites_l="146,152"/>
<c n="benchAdaptive" p="bench/bench_radix_ab.cpp:157" incompatible="1" sites_l="162"/>
<c n="radixSortNonNegativeFloatsDesc" p="src/infra/sortutil.h:138" incompatible="1" sites_l="147"/>
<c n="radixSortByScoreDescId" p="src/infra/sortutil.h:153" incompatible="1" sites_l="213"/>
</edit-check>
`````

## `./build/ripwire . --pr-context`

*The review-evidence bundle with an actual changed file.*

**wall time: 3.10s**

`````
<!-- ripwire pr-context schema=ripwire.pr-context/v1: review bundle per changed file vs base=: symbols, callers, blast radius, tests, owners. window: shown= capped= (capped=1 cut). counts_floor=1: every count is a FLOOR, never a total. graph_ambiguous=/graph_unresolved=: resolver gauge. graph_unindexed=N: N files no grammar could read (the map header's unindexed=); their calls raise neither gauge. est_tokens=: price as emitted (an upper bound under compact). at=: commit+dirty+shallow. root=: p= relative to it. truncated=: what the trim ladder dropped to fit budget_tokens= (budget-floor-exceeded: still over). direction=: side reviewed: worktree-since-head, head-since-fork or head-since-ref-tip. skipped_mode_only=N: mode-only (chmod) diffs left out of the changed files; renames stay in. trim_level=0-4: trim ladder step taken to fit budget_tokens= (0 none, 4 counts only); raise token-budget. budget_default=1: the default 8000-token budget applied (no token-budget or max-tokens given). commits=N: this file's commits in window=; 0 = the window could not look, not no partners. partners=N: co-change partners NOT in the diff; rows are its top shown= (the cochange verb lists all). dependents=N: distinct symbols transitively calling this file's symbols (reach set, a FLOOR). files_other=N: non-changed files among those reached; the f rows are its top shown=. authors=N: distinct authors of this file (0 = no git data). bf=1: one author holds over 80% of recency-weighted commits (bus-factor risk). files=N: changed files in the diff (shown= of them listed). file symbols=: indexed symbols in that changed file. changed-symbols count= / tests count=: that section's full count (shown= of it listed). tests count=: test files reaching this file (shown= of them listed). impact files=: files holding the transitive callers (dependents=). impactf deps=: transitive callers in that file. test run=: the command that runs that test file (run_unknown=1: none derivable). author email=/share=: a committer of this file / its fraction of the recency-weighted commits. s callers=N: direct callers of that changed symbol; caller rows are its top shown= (callers verb: all). -->
<pr-context schema="ripwire.pr-context/v1" base="working-tree" root="." direction="worktree-since-head" files="1" skipped_mode_only="0" budget_tokens="8000" est_tokens="3380" trim_level="0" truncated="none" budget_default="1" at="c7920353a+dirty" graph_ambiguous="10281" graph_unresolved="12878" grap … [line truncated: 35 more bytes on this line]
<file p="src/infra/sortutil.h" symbols="13">
<impact dependents="190" files="46" files_other="46" shown="20" capped="1">
<f p="src/mcpverbs.h" deps="32"/>
<f p="src/slice.h" deps="30"/>
<f p="src/serialize.h" deps="9"/>
<f p="src/quality.h" deps="8"/>
<f p="src/verbs_navigate.h" deps="8"/>
<f p="src/main.cpp" deps="7"/>
<f p="src/verbs_quality.h" deps="7"/>
<f p="src/mergescout.h" deps="6"/>
<f p="src/verbs_change.h" deps="6"/>
<f p="src/verbs_for.h" deps="6"/>
<f p="bench/bench_sort_large.cpp" deps="5"/>
<f p="src/situ.h" deps="5"/>
<f p="src/editplan.h" deps="4"/>
<f p="src/mention.h" deps="4"/>
<f p="bench/bench_radix_ab.cpp" deps="3"/>
<f p="src/callhierarchy.h" deps="3"/>
<f p="src/lanes.h" deps="3"/>
<f p="src/mcpedit.h" deps="3"/>
<f p="src/partition.h" deps="3"/>
<f p="src/crossref.h" deps="2"/>
</impact>
<tests count="5" shown="5" capped="0">
<test p="test/adaptivecutshapefix/adaptive_cut_shape_test.cpp" run="bash test/adaptivecutshapecheck.sh"/>
<test p="test/includeprecise_unit.cpp" run="bash test/includeprecisecheck.sh"/>
<test p="test/rustimport_unit.cpp" run="bash test/rustimportprecisecheck.sh"/>
<test p="test/verify_csr.cpp" run="bash test/a9disclosurecheck.sh"/>
… [87 more display lines; full output is 8449 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --map-diff --top-k=5`

*The map re-ranked with a teleport toward the changed file (changed=1 here, not 0).*

**wall time: 2.21s**

`````
<!-- ripwire map-diff schema=ripwire.map-diff/v1: the ranked map anchored at at=: what the diff touched, the map's row vocabulary. est_tokens=: price as emitted (an upper bound under compact). at=: commit+dirty+shallow. root=: p= relative to it. pr_iters=N: PageRank iterations. declined=K: K calls left unbound (no evidence chose one def). external=K: K calls proven outside the tree, no edge. locality_pinned=K: K calls pinned by locality alone (a guess). extent_suspect_syms=K: K defs failed containment, corpus-wide. macro_blanked_files=K: K files indexed from a macro-blanked re-parse. prov=scip|binding|import|split|final-segment: how that <c> edge bound (absent: one unique name); split = one arm of an amb= pick; final-segment = a qualified type matched by last name only. files=/symbols=: files and symbols indexed; edges= distinct call edges; shown= symbols printed, a merged row counting each def; ambiguous= calls split over several defs, corpus-wide; unresolved= calls with in-tree evidence and no edge (every def language-filtered or unreachable, or binding refused); order= rows by rank (important-first, important-last; (auto:fill) = flipped past a size threshold) or by path (stable). changed=K: K indexed git-changed files seed the PageRank teleport (0: uniform, incl. no git). skipped_oversize=K: K files over a size ceiling, not indexed. unindexed=ext:N: N text files of that extension no grammar reads (6 extensions at most). unindexed_exts=E: E such extensions in all, the list cut. sc=: enclosing scope; the full id is p::sc::n (p= of the row or its <f>) and selectors take it. amb=K: K calls split over several defs. layer=: built-in arch layer (game|infra|render|math|audio|ai|test) from a dir name in p=; absent if none. -->
<!-- t=modscope=a-file's-MODULE-SCOPE(n=<file-scope>):the-statements-outside-every-named-definition,where-a-top-level-call-and-an-anonymous-callback-body's-calls-live;a-CALLER-never-a-callee(nothing-in-the-source-can-name-it)-with-no-body-to-expand;a-file-with-no-such-call-has-no-such-row -->
<!-- files=2484 symbols=23853 edges=34240 shown=5 est_tokens=1684 ambiguous=10281 unresolved=12878 locality_pinned=12 external=7345 declined=9922 extent_suspect_syms=10 macro_blanked_files=7 changed=1 skipped_oversize=15 unindexed="txt:73,tsv:49,jsonl:26,scm:23,expected:15,xml:13" unindexed_exts=20 order=important-first -->
<r schema="ripwire.map-diff/v1" at="c7920353a+dirty" root="." est_tokens="1684" pr_iters="19">
<f p="src/infra/sortutil.h" layer="infra">
<s t="fn" n="radixSortByScoreDescId" sc="rw::sortutil" amb="9" k="0.0796">
<c n="size" prov="split"/>
<c n="begin" prov="split"/>
<c n="end" prov="split"/>
<c n="begin" prov="split"/>
<c n="end" prov="split"/>
<c n="begin" prov="split"/>
<c n="end" prov="split"/>
<c n="begin" prov="split"/>
<c n="end" prov="split"/>
<c n="size" prov="split"/>
<c n="lessByScoreDescId"/>
<c n="radixSortUint32ByKey"/>
<c n="nonNegativeFloatDescKey"/>
<c n="begin" prov="split"/>
<c n="end" prov="split"/>
<c n="begin" prov="split"/>
<c n="end" prov="split"/>
<c n="size" prov="split"/>
</s>
<s t="fn" n="radixSortByFromTo" sc="rw::sortutil" amb="8" k="0.0545">
<c n="size" prov="split"/>
<c n="begin" prov="split"/>
<c n="end" prov="split"/>
<c n="begin" prov="split"/>
… [37 more display lines; full output is 4185 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --clones`

*The duplicated helper the sandbox edit introduced shows up as a clone group.*

**wall time: 2.28s**

`````
<!-- ripwire clones schema=ripwire.clones/v1: similar normalized-token bodies: <group type=2|3 gid= tokens= n= similarity=> of <f n= p=>; dup_loc=/dup_pct=. window: shown= total= capped= has_more= next_offset= offset= limit= (capped=1 cut; next_offset= pastes as offset=). root=: p= relative to it. groups=/type3=: Type-2 and Type-3 group totals over all groups; total= is their sum. exempt_groups=N: groups whose members all sit on fixture/shell-runner paths quality-delta duplication ignores. idiom_groups=/demoted_groups=: groups of one recognized idiom / those quality-delta demotes to minor; floors. clone_groups=N: clusters after merging pairs (rows sharing gid=); a floor under type3_capped=1. total_loc=N: lines of every function body the detector considered; dup_pct= is dup_loc= over it. group exempt=fixture|shell-runner: every member is on such a path; quality-delta duplication ignores it. group idiom=: the recognized shape every member spells: threshold-ladder, switch-name-table, builder-chain. -->
<clones schema="ripwire.clones/v1" groups="119" type3="523" exempt_groups="353" idiom_groups="19" demoted_groups="12" clone_groups="313" dup_loc="6861" total_loc="198798" dup_pct="3.5" shown="80" capped="1" total="642" has_more="1" next_offset="80" offset="0" limit="0" root=".">
<group type="2" gid="49" tokens="338" n="3">
<f n="rw_is_ripwire_call" p="hooks/ripwire-claude-route.sh:181"/>
<f n="rw_is_ripwire_call" p="hooks/ripwire-codex-route.sh:104"/>
<f n="rw_is_ripwire_call" p="hooks/ripwire-nudge.sh:618"/>
</group>
<group type="2" gid="213" tokens="213" n="2" exempt="shell-runner">
<f n="call_sites" p="test/declinecheck.sh:114"/>
<f n="call_sites" p="test/usesselectorcheck.sh:49"/>
</group>
<group type="2" gid="267" tokens="211" n="4" exempt="shell-runner">
<f n="batch_sub" p="test/mcpclidiffcheck.sh:64"/>
<f n="batch_sub" p="test/mcptranchecheck.sh:55"/>
<f n="batch_sub" p="test/mcpw2fixcheck.sh:52"/>
<f n="batch_sub" p="test/mcpw3fixcheck.sh:51"/>
</group>
<group type="2" gid="48" tokens="163" n="3">
<f n="rw_cmd_word" p="hooks/ripwire-claude-route.sh:151"/>
<f n="rw_cmd_word" p="hooks/ripwire-codex-route.sh:74"/>
<f n="rw_cmd_word" p="hooks/ripwire-nudge.sh:588"/>
</group>
<group type="2" gid="189" tokens="153" n="2" exempt="shell-runner">
<f n="mcp_text" p="test/blindspotcheck.sh:120"/>
<f n="mcp_text" p="test/xmlwellformed.sh:320"/>
</group>
<group type="2" gid="285" tokens="151" n="3" exempt="shell-runner">
<f n="monotonic_check" p="test/pyimportprecisecheck.sh:89"/>
<f n="monotonic_check" p="test/rustimportprecisecheck.sh:141"/>
<f n="monotonic_check" p="test/tsimportprecisecheck.sh:170"/>
… [307 more display lines; full output is 16180 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --stray-content=zz-orphan`

*CHANGED: a ref with NO merge base with HEAD now reports v="unknown" ok="0" in its own bucket — the absence of an answer, never a claim it is merged. (The sandbox carries a deliberately parentless branch built with `git commit-tree`; a shallow CI clone puts every ref here.)*

**wall time: 1.82s**

`````
<!-- ripwire stray-content schema=ripwire.stray-content/v1: per local ref, lines/symbols NOT in HEAD: <ref ok= v= base= stray=>; v=unknown = no merge base. at=: commit+dirty+shallow. head=: the HEAD commit, bare 9-hex sha (at= adds +dirty). head_ref=: HEAD's branch (HEAD when detached); that branch itself is not scanned. refs=N: local branches scanned (refs/heads only); unmerged + superseded + merged + unknown = refs. blobs=N: distinct git blobs read for the sweep. unmerged=N: refs whose authored work the live line genuinely lacks. superseded=N: refs whose work the live line re-implemented (removed the same base code). merged=N: refs whose work HEAD already has; omitted from the rows. name=: the local branch. tip=: the branch tip commit (9 hex). date=: the tip's committer date, YYYY-MM-DD. files=N: files with stray lines; rows capped at 12, a more element counts the rest (detail=1 lists all). ref superseded=N>: of this ref's stray= lines, those in files the live line re-implemented. unknown=N: refs that could not be analysed (v=unknown, e.g. no merge base); never counted merged. -->
<stray-content schema="ripwire.stray-content/v1" head="c7920353a" head_ref="lane/lean-answers-068" refs="1" blobs="0" unmerged="0" superseded="0" merged="0" unknown="1" filter="zz-orphan" at="c7920353a+dirty">
<ref name="zz-orphan-lane" tip="ca25e7b1a" date="2026-10-08" base="" ok="0" v="unknown" stray="0" files="0" superseded="0">
</ref>
</stray-content>
`````

stderr:

`````
[math degraded] crossref: no merge-base for ref (shallow clone or unrelated history?) — verdict is unknown, not merged  (crossref.h:1173, RefPlumbing rw::crossref::probeRefBase(const std::string &, const RefInfo &, const std::string &) — logged once per site)
`````

## `./build/ripwire . --stray-content=zz-orphan --plan`

*CHANGED: --plan surfaces those same refs as an <undetermined> row rather than silently dropping them.*

**wall time: 2.57s**

`````
<!-- ripwire landing-plan schema=ripwire.landing-plan/v1: stranded-work landing order across refs, fewest conflicts first. at=: commit+dirty+shallow. -->
<landing-plan schema="ripwire.landing-plan/v1" head="c7920353a" refs="1" unmerged="0" superseded="0" merged="0" undetermined="1" scouted="0" bounded="0" scout-ok="1" at="c7920353a+dirty">
<undetermined name="zz-orphan-lane" v="unknown" reason="no merge base with HEAD (shallow clone or unrelated history) — this ref could not be analysed, it is NOT known to be merged; deepen the clone and re-run"/>
</landing-plan>
`````

stderr:

`````
[math degraded] crossref: no merge-base for ref (shallow clone or unrelated history?) — verdict is unknown, not merged  (crossref.h:1173, RefPlumbing rw::crossref::probeRefBase(const std::string &, const RefInfo &, const std::string &) — logged once per site)
`````

## `./build/ripwire . --dmm`

*The DMM scalar on a REAL delta: the sandbox edit grew one unit past the nesting/complexity thresholds and added an 8-parameter one, so dmm is low and the three sub-scores say which property moved.*

**wall time: 3.73s**

`````
<!-- ripwire dmm schema=ripwire.dmm/v1: Delta Maintainability Model base=→target=: dmm= good/(good+bad) units by size_metric=; <p k= dmm= good= bad= d_low= d_high=>. at=: commit+dirty+shallow. available=0: no score at all (dmm=UNAVAILABLE, reason= says why); never read as 1.000 or 0.000. combine=pooled: root dmm= is summed good over summed good+bad of the 3 properties (ripwire's own). low_loc=/low_cx=/low_params=: a unit is LOW risk at or under these lines / cyclomatic / params. base_units=/base_volume=/target_units=/target_volume=: units with a body and their line span per side. -->
<dmm schema="ripwire.dmm/v1" base="c7920353a6d41f95f6ad61193358a10a3b255acf" target="working-tree" at="c7920353a+dirty" available="1" combine="pooled" size_metric="physical-loc" low_loc="15" low_cx="5" low_params="2" dmm="0.142" good="23" bad="139" base_units="12879" base_volume="198744" target_unit … [line truncated: 33 more bytes on this line]
<p k="size" dmm="0.130" good="7" bad="47" d_low="7" d_high="47"/>
<p k="complexity" dmm="0.130" good="7" bad="47" d_low="7" d_high="47"/>
<p k="interfacing" dmm="0.167" good="9" bad="45" d_low="9" d_high="45"/>
</dmm>
`````

## `./build/ripwire . --quality-delta --scope=src/graph.h`

*OWNERSHIP partition for a shared tree: every regression here lives in src/infra/, so under a scope naming src/graph.h they ALL print under <out-of-scope> with a do-not-ack banner and never gate — scoped-out-gating= says how many would have.*

**wall time: 9.69s**

`````
<!-- ripwire quality-delta schema=ripwire.quality-delta/v1: only what the change made WORSE vs baseline=: regressions= minor= gating=; <r kind= sym= p= was= now= gating= bar=>, <sa> acked. value-ref-excluded=N: internal functions kept off because a table, field or argument holds them (matched by name, not a proven call); a floor. at=: commit+dirty+shallow. stale=N: ack ledger rows whose target no longer applies (sa rows); never gating. preexisting-worse=N: regressions on symbols that existed at baseline; only these gate (when major). new-symbol=N: regressions on NEW code; never gate, but the debt is yours: read them. register-macro-excluded=N: symbols kept out of dead-code as self-registering test/bench macros; a floor. api-new-surface=N: new PUBLIC symbols; a count, never gates, not in regressions=. renames=/rename_window_commits=: git rename pairs read over that many commits, to re-file baseline and acks. acked_by_rename=/acked_by_content=: acked= suppressions matched via git renames / an equal body hash. renames_window_truncated=1: history is deeper than the rename window, older renames unread. r surface=: the api-surface tier, new-symbol or contract-change. acked=N: findings suppressed by the ack ledger, listed as sa rows; never gating. r sev=minor: a small numeric delta, counted in minor=, never gating (absent: major). r origin=new-symbol: the finding is on NEW code, never gating (absent: preexisting-worse). sa key=/why=: the stale ack's ledger hash / target-gone (names nothing now) or finding-gone (no longer fires). r members=/tokens=: a duplication row's clone group (member ids) / their shared normalized-token count. -->
<quality-delta schema="ripwire.quality-delta/v1" baseline="git-HEAD" regressions="0" minor="0" acked="0" stale="134" preexisting-worse="0" new-symbol="0" gating="0" register-macro-excluded="62" api-new-surface="2" at="c7920353a+dirty" renames="57" rename_window_commits="400" acked_by_rename="0" acke … [line truncated: 127 more bytes on this line]
<out-of-scope n="9" would-gate="4" note="not yours - do not ack: these rows lie outside the scope this run named. They are disclosed rather than hidden, they never gate this exit code, and the ack refuses to write them.">
<r kind="api-surface" sym="src/infra/sortutil.h::rw::sortutil::nonNegativeFloatDescKey" was="1" now="2" surface="contract-change" p="src/infra/sortutil.h:109"/>
<r kind="complexity" sym="src/infra/sortutil.h::rw::sortutil::lessByScoreDescId" was="1" now="67" bar="15" p="src/infra/sortutil.h:49"/>
<r kind="dead-code" sym="src/infra/sortutil.h::rw::sortutil::nonNegativeFloatAscKeyCopy" origin="new-symbol" p="src/infra/sortutil.h:119"/>
<r kind="dead-code" sym="src/infra/sortutil.h::rw::sortutil::sortScoredIdsWithOptions" origin="new-symbol" p="src/infra/sortutil.h:129"/>
<r kind="duplication" members="src/infra/sortutil.h::rw::sortutil::nonNegativeFloatAscKeyCopy | src/infra/sortutil.h::rw::sortutil::nonNegativeFloatDescKey" tokens="59" p="src/infra/sortutil.h:119"/>
<r kind="nesting" sym="src/infra/sortutil.h::rw::sortutil::lessByScoreDescId" was="1" now="6" bar="4" p="src/infra/sortutil.h:49"/>
<r kind="new-clone-of-reused-helper" sym="src/infra/sortutil.h::rw::sortutil::nonNegativeFloatAscKeyCopy | src/infra/sortutil.h::rw::sortutil::nonNegativeFloatDescKey" was="0" now="4" p="src/infra/sortutil.h:119"/>
<r kind="params" sym="src/infra/sortutil.h::rw::sortutil::sortScoredIdsWithOptions" was="0" now="8" bar="5" origin="new-symbol" p="src/infra/sortutil.h:129"/>
<r kind="verbosity" sym="src/infra/sortutil.h::rw::sortutil::lessByScoreDescId" was="8" now="47" bar="60" sev="minor" p="src/infra/sortutil.h:49"/>
</out-of-scope>
<sa kind="api-surface" key="085e3d408c2c4a35" why="target-gone"/>
<sa kind="api-surface" key="155d74d341a49f3c" why="target-gone"/>
<sa kind="api-surface" key="1a15386c2d1e47af" why="target-gone"/>
<sa kind="api-surface" key="298e798c7f075715" why="target-gone"/>
<sa kind="api-surface" key="56acdf9b5c314a14" why="target-gone"/>
<sa kind="api-surface" key="5a07390012b46e06" why="target-gone"/>
<sa kind="api-surface" key="6eef859578c8c376" why="target-gone"/>
<sa kind="api-surface" key="6f2394762f82a855" why="target-gone"/>
<sa kind="api-surface" key="7f2c3eefdf6e512e" why="target-gone"/>
<sa kind="api-surface" key="802e513731103806" why="target-gone"/>
<sa kind="api-surface" key="b6a24afef32a68a8" why="target-gone"/>
<sa kind="api-surface" key="c923e661c197b265" why="target-gone"/>
<sa kind="api-surface:new-symbol" key="1926b0d9e94541a0" why="target-gone"/>
<sa kind="api-surface:new-symbol" key="1d3814ba687a4aef" why="target-gone"/>
<sa kind="api-surface:new-symbol" key="1db76028879244ef" why="target-gone"/>
<sa kind="api-surface:new-symbol" key="36e39c7ab0fc1686" why="target-gone"/>
<sa kind="api-surface:new-symbol" key="4bce64bd920de0c3" why="target-gone"/>
… [118 more display lines; full output is 15426 bytes on 1 raw line(s)]
`````

stderr:

`````
ripwire: no ./.ripwire_quality_baseline — auto-comparing the working tree vs git HEAD (commit the baseline with --quality-baseline to pin it)
`````

## `./build/ripwire . --quality-delta --quality-ack --scope=src/graph.h --ack-only=api-surface`

*The rubber-stamp guard: an --ack-only that names an OUT-OF-SCOPE row refuses (exit 1) and writes nothing.*

**exit code: 1** — **wall time: 5.72s**

`````
(empty)
`````

stderr:

`````
ripwire: no ./.ripwire_quality_baseline — auto-comparing the working tree vs git HEAD (commit the baseline with --quality-baseline to pin it)
ripwire: --ack-only=api-surface selects 1 finding(s) OUT OF SCOPE for --scope=src/graph.h — refusing, and writing nothing at all:
    api-surface src/infra/sortutil.h::rw::sortutil::nonNegativeFloatDescKey at src/infra/sortutil.h:109
  those rows belong to whoever is editing those paths. Acking them here writes their debt into a committed ledger under YOUR
  reason string, which is how a per-finding ratchet becomes a rubber stamp. Narrow the pattern, or widen the scope if they really are yours.
`````

## `./build/ripwire . --handoff`

*The continuation packet with a REAL diff: verified changed symbols + blast radius + tests-to-run, then the heuristic rows.*

**wall time: 2.56s**

`````
<!-- ripwire handoff schema=ripwire.handoff/v1: continuation packet for the NEXT session: <verified changed= blast_files=>, <tests n=>, <heuristic n= candidates=>, <note>, <doc p=>. window: capped= (capped=1 cut). est_tokens=: price as emitted (an upper bound under compact). at=: commit+dirty+shallow. root=: p= relative to it. branch=/subject=: the checked out branch and HEAD commit subject; gitok=0: the git diff probe failed, changed counts are floors. cochange_window=/cochange_commits=: the git window the cochange rows were mined in and the commits it held (0: could not look). doc s=: lexical score of that plan/design doc for the branch+subject query. t run=: the command that runs that test (run_unknown=1: none derivable). -->
<handoff schema="ripwire.handoff/v1" at="c7920353a+dirty" root="." branch="lane/lean-answers-068" subject="whereis: the default serves the page that lists more definitions, then the shorter" gitok="1" est_tokens="893">
<verified changed="1" blast_files="46">
<f p="src/infra/sortutil.h">
<s n="svLess"/>
<s n="lessByScoreDescId"/>
<s n="radixSortUint32ByKey"/>
<s n="nonNegativeFloatDescKey"/>
<s n="nonNegativeFloatAscKeyCopy"/>
<s n="sortScoredIdsWithOptions"/>
<s n="radixSortNonNegativeFloatsDesc"/>
<s n="radixSortByScoreDescId"/>
<s n="radixSortByScoreDescId"/>
<s n="radixSortIdsAscending"/>
<s n="lessByFromTo"/>
<s n="radixSortByFromTo"/>
<s n="radixSortByFromTo"/>
</f>
<tests n="5">
<t p="test/verify_radix.cpp" run="bash test/greptiercheck.sh"/>
<t p="test/adaptivecutshapefix/adaptive_cut_shape_test.cpp" run="bash test/adaptivecutshapecheck.sh"/>
<t p="test/includeprecise_unit.cpp" run="bash test/includeprecisecheck.sh"/>
<t p="test/verify_csr.cpp" run="bash test/a9disclosurecheck.sh"/>
<t p="test/rustimport_unit.cpp" run="bash test/rustimportprecisecheck.sh"/>
</tests>
</verified>
<heuristic n="4" candidates="197" capped="1" cochange_window="18mo@HEAD" cochange_commits="3939">
<doc p="CHANGELOG.md" s="20.546"/>
<doc p="docs/COMMANDS.md" s="14.830"/>
<doc p="docs/research/answer-completeness.md" s="8.508"/>
<doc p="skills/ripwire-mcp/SKILL.md" s="7.623"/>
</heuristic>
</handoff>
`````

## `./build/ripwire . --note-add="lessByScoreDescId: keep this branch-free — it sits inside the PageRank sort comparator"`

*Pin a field note (write-side memory) to a symbol; committed to .ripwire_notes in the sandbox. The BARE name is resolved through the same resolver the read verbs use and stored as the canonical id — the rewrite is echoed on stderr, because a silent one is not a disclosure.*

`````
src/infra/sortutil.h::rw::sortutil::lessByScoreDescId	2026-10-08	keep this branch-free — it sits inside the PageRank sort comparator	c7920353a6d41f95f6ad61193358a10a3b255acf	lane/lean-answers-068
`````

stderr:

`````
ripwire: --note-add: tip: notes that say "chose X over Y because Z" surface better — consider adding the why
ripwire: --note-add: target 'lessByScoreDescId' canonicalised to 'src/infra/sortutil.h::rw::sortutil::lessByScoreDescId' — that is the id --for/--expand key notes by
`````

## `./build/ripwire . --notes`

*The note is listed under the canonical id, dangling="0" — i.e. it will actually surface. (Before the H1 fix the bare name was stored verbatim and read dangling="1": recorded, and surfaced nowhere.)*

`````
<ctx schema="ripwire.notes/v1">
<!-- ripwire notes schema=ripwire.notes/v1: field notes by target: <target id= dangling=> holds <note d= sha= branch=>; the kept count comment: notes= rows, targets= <target> rows, dangling= targets matching nothing indexed (listed, surfaced nowhere). dangling=1: matches nothing indexed. -->
<!-- notes=3 targets=3 dangling=0 -->
<notes>
<target id="src/infra/Diagnostics.h" dangling="0">
<note d="2026-09-12" sha="42b7c8d" branch="lane/noalias-docs">
<![CDATA[ASSUME_NO_ALIAS is an optimizer fact in release (separate_storage) only where the compiler consumes it: clang 18+ by default, LLVM 17/AppleClang 16 via the CMake -mllvm flag (scalars only), GCC never (debug check only); never on two members of one object; ASSUME_NO_ALIAS_BUF for OWNING cont … [line truncated: 22 more bytes on this line]
</note>
</target>
<target id="src/infra/sortutil.h::rw::sortutil::lessByScoreDescId" dangling="0">
<note d="2026-10-08" sha="c792035" branch="lane/lean-answers-068">
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
src/infra/sortutil.h::rw::sortutil::lessByScoreDescId	2026-10-08	chose the flat two-branch compare over the nested ladder because the comparator sits inside the PageRank sort	c7920353a6d41f95f6ad61193358a10a3b255acf	lane/lean-answers-068
`````

## `./build/ripwire . --expand=lessByScoreDescId --top-k=0`

*Both notes riding along with the symbol's body — the <note> elements follow the body, past the display cut, so they are extracted below.*

`````
<ctx schema="ripwire.expand/v1" root="." est_tokens="889">
<!-- ripwire expand schema=ripwire.expand/v1: full bodies: <bodies shown= total= capped=> of <b t= l= p= n= sibs= sibs_total= sibs_capped= inc=>; <calls>
<c n= l=> resolved callees. window: shown= total= capped= (capped=1 cut). est_tokens=: price as emitted (an upper bound under compact). root=: p= relative to it. scrubbed=1: this CDATA is not the bytes (]]> split or C0 replaced). redacted=1: a credential shape rewritten to [REDACTED:kind]; the no-re … [line truncated: 130 more bytes on this line]
<bodies shown="1" total="1" capped="0">
<b t="fn" l="49" p="src/infra/sortutil.h" n="lessByScoreDescId" sibs="svLess,radixSortUint32ByKey,nonNegativeFloatDescKey,nonNegativeFloatAscKeyCopy,sortScoredIdsWithOptions,radixSortNonNegativeFloatsDesc,radixSortByScoreDescId,radixSortByScoreDescId,radixSortIdsAscending,lessByFromTo,radixSortByFro … [line truncated: 126 more bytes on this line]
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
… [22 more display lines; full output is 3409 bytes on 47 raw line(s)]
`````

The <note> element on the same output — past the 30-line display cut above:

`````
<note d="2026-10-08" sha="c792035" branch="lane/lean-answers-068">
<![CDATA[chose the flat two-branch compare over the nested ladder because the comparator sits inside the PageRank sort]]>
</note>
<note d="2026-10-08" sha="c792035" branch="lane/lean-answers-068">
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

**wall time: 4.87s**

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
{"applied":"replace_symbol_body","symbol":"lessByScoreDescId","file":"src/infra/sortutil.h","span":{"start":2162,"end":2375},"lines":{"start":49,"end":56},"replaced_bytes":1718,"old_file_bytes":12329,"new_file_bytes":10824,"file_eol":"lf","eol_normalized":false,"trailing_newline_folded":true,"separa … [line truncated: 726 more bytes on this line]
"graph_ambiguous":10278,"graph_unresolved":12878,"graph_unindexed":237,"counts_floor":true},"tests_to_run":[{"p":"test/verify_radix.cpp","hops":1,"run":"bash test/greptiercheck.sh"},
{"p":"test/adaptivecutshapefix/adaptive_cut_shape_test.cpp","hops":2,"run":"bash test/adaptivecutshapecheck.sh"},
{"p":"test/includeprecise_unit.cpp","hops":2,"run":"bash test/includeprecisecheck.sh"},
{"p":"test/verify_csr.cpp","hops":2,"run":"bash test/a9disclosurecheck.sh"},
{"p":"test/rustimport_unit.cpp","hops":4,"run":"bash test/rustimportprecisecheck.sh"}],
"order":"evidence","partners":0,"run_first":1,"tests":5,"script_gates_unmodelled":729,"graph_ambiguous":10278,"graph_unresolved":12878,"graph_unindexed":237,"counts_floor":true,"next":"bash test/greptiercheck.sh"}
`````

stderr:

`````
ripwire edit: applied atomically; receipt carries region, blob_sha, edit_check, tests_to_run; next: bash test/greptiercheck.sh
`````

## `./build/ripwire . --edit-check=lessByScoreDescId`

*The closed loop: contract unchanged (same params, same publicness) after the replace — nothing provably incompatible.*

**wall time: 1.42s**

`````
<!-- ripwire edit-check schema=ripwire.edit-check/v1: sym='s contract NOW vs HEAD: status=unchanged|new-symbol|contract-change; <c n= p= incompatible=1 sites_l=> callers. counts_floor=1: every count is a FLOOR, never a total. graph_ambiguous=/graph_unresolved=: resolver gauge. graph_unindexed=N: N files no grammar could read (the map header's unindexed=); their calls raise neither gauge. est_tokens=: price as emitted (an upper bound under compact). at=: commit+dirty+shallow. root=: p= relative to it. next=: the one pasteable follow-up. defs=N: overloads at this site (same file, scope, name) folded into one contract; params compared by MAX. callers=N: callers of sym= (the c rows' total; a floor). -->
<edit-check schema="ripwire.edit-check/v1" sym="lessByScoreDescId" t="fn" p="src/infra/sortutil.h:49" status="unchanged" defs="1" callers="4" incompatible="0" at="c7920353a+dirty" graph_ambiguous="10278" graph_unresolved="12878" graph_unindexed="237" counts_floor="1" root="." next="--test-gate=src/i … [line truncated: 34 more bytes on this line]
<note d="2026-10-08" sha="c792035" branch="lane/lean-answers-068">
<![CDATA[chose the flat two-branch compare over the nested ladder because the comparator sits inside the PageRank sort]]>
</note>
<note d="2026-10-08" sha="c792035" branch="lane/lean-answers-068">
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

**wall time: 3.09s**

`````
{"applied":"insert_after_symbol","symbol":"lessByScoreDescId","file":"src/infra/sortutil.h","span":{"start":2375,"end":2463},"lines":{"start":56,"end":58},"replaced_bytes":0,"old_file_bytes":10824,"new_file_bytes":10912,"file_eol":"lf","eol_normalized":false,"trailing_newline_folded":true,"separator … [line truncated: 652 more bytes on this line]
"graph_ambiguous":10278,"graph_unresolved":12878,"graph_unindexed":237,"counts_floor":true},"tests_to_run":[{"p":"test/verify_radix.cpp","hops":1,"run":"bash test/greptiercheck.sh"},
{"p":"test/adaptivecutshapefix/adaptive_cut_shape_test.cpp","hops":2,"run":"bash test/adaptivecutshapecheck.sh"},
{"p":"test/includeprecise_unit.cpp","hops":2,"run":"bash test/includeprecisecheck.sh"},
{"p":"test/verify_csr.cpp","hops":2,"run":"bash test/a9disclosurecheck.sh"},
{"p":"test/rustimport_unit.cpp","hops":4,"run":"bash test/rustimportprecisecheck.sh"}],
"order":"evidence","partners":0,"run_first":1,"tests":5,"script_gates_unmodelled":729,"graph_ambiguous":10278,"graph_unresolved":12878,"graph_unindexed":237,"counts_floor":true,"next":"bash test/greptiercheck.sh"}
`````

stderr:

`````
ripwire edit: applied atomically; receipt carries region, blob_sha, edit_check, tests_to_run; next: bash test/greptiercheck.sh
`````

## `./build/ripwire . --insert-after-symbol=lessByScoreDescId --edit-payload=<scratch>/aux/payload_note.h --no-post-check`

*The opt-out: the same insert with the folded verification skipped — lines= still rides (it is free), edit_check/tests_to_run do not, and the two pasteable commands stay on stderr.*

**wall time: 1.47s**

`````
{"applied":"insert_after_symbol","symbol":"lessByScoreDescId","file":"src/infra/sortutil.h","span":{"start":2375,"end":2463},"lines":{"start":56,"end":58},"replaced_bytes":0,"old_file_bytes":10912,"new_file_bytes":11000,"file_eol":"lf","eol_normalized":false,"trailing_newline_folded":true,"separator … [line truncated: 572 more bytes on this line]
`````

stderr:

`````
ripwire edit: applied atomically; receipt carries region, blob_sha (post-check skipped); next: --edit-check=src/infra/sortutil.h:lessByScoreDescId
`````

## `./build/ripwire . --insert-before-symbol=nonNegativeFloatDescKey --edit-payload=<scratch>/aux/payload_note.h --edit-target-file=src/infra/sortutil.h`

*Insert BEFORE, with --edit-target-file pinning which same-named definition (here unambiguous — the disambiguator is simply honoured).*

**wall time: 3.37s**

`````
{"applied":"insert_before_symbol","symbol":"nonNegativeFloatDescKey","file":"src/infra/sortutil.h","span":{"start":2895,"end":2983},"lines":{"start":74,"end":75},"replaced_bytes":0,"old_file_bytes":11000,"new_file_bytes":11088,"file_eol":"lf","eol_normalized":false,"trailing_newline_folded":false,"s … [line truncated: 755 more bytes on this line]
{"n":"benchAdaptive","p":"bench/bench_radix_ab.cpp:157","l":[162]},
{"n":"radixSortNonNegativeFloatsDesc","p":"src/infra/sortutil.h:105","l":[114]},
{"n":"radixSortByScoreDescId","p":"src/infra/sortutil.h:120","l":[180]}],
"graph_ambiguous":10278,"graph_unresolved":12878,"graph_unindexed":237,"counts_floor":true},"tests_to_run":[{"p":"test/verify_radix.cpp","hops":1,"run":"bash test/greptiercheck.sh"},
{"p":"test/adaptivecutshapefix/adaptive_cut_shape_test.cpp","hops":2,"run":"bash test/adaptivecutshapecheck.sh"},
{"p":"test/includeprecise_unit.cpp","hops":2,"run":"bash test/includeprecisecheck.sh"},
{"p":"test/verify_csr.cpp","hops":2,"run":"bash test/a9disclosurecheck.sh"},
{"p":"test/rustimport_unit.cpp","hops":4,"run":"bash test/rustimportprecisecheck.sh"}],
"order":"evidence","partners":0,"run_first":1,"tests":5,"script_gates_unmodelled":729,"graph_ambiguous":10278,"graph_unresolved":12878,"graph_unindexed":237,"counts_floor":true,"next":"--uses=src/infra/sortutil.h:nonNegativeFloatDescKey"}
`````

stderr:

`````
ripwire edit: applied atomically; receipt carries region, blob_sha, edit_check, tests_to_run; next: --uses=src/infra/sortutil.h:nonNegativeFloatDescKey
`````

## `./build/ripwire . --replace-symbol-body=DoesNotExist --edit-payload=<scratch>/aux/payload_note.h`

*An unknown TARGET refuses and leaves every file byte-identical.*

**exit code: 1** — **wall time: 1.49s**

`````
(empty)
`````

stderr:

`````
ripwire: --replace-symbol-body: symbol 'DoesNotExist' not found
`````

## `./build/ripwire . --edit-plan=<scratch>/aux/edit_plan.json --dry-run`

*A versioned multi-edit TRANSACTION preflighted without writing: the receipt shows what each op would read and touch.*

**wall time: 1.47s**

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
{"schema":"ripwire.edit-plan/v1","mode":"dry-run","edits":1,"files":1,"callers_union":4,"graph_ambiguous":10278,"graph_unresolved":12878,"graph_unindexed":237,"counts_floor":true,"atomic_scope":"per-file","rollback_on_write_error":true,"recheck_before_each_write":true,"multifile_crash_atomic":false, … [line truncated: 354 more bytes on this line]
`````

## `./build/ripwire . --edit-plan=<scratch>/aux/edit_plan.json --apply`

*The same plan committed: per-file locks, re-verify-before-write, atomic rename, rollback on a later failure.*

**wall time: 3.02s**

`````
{"schema":"ripwire.edit-plan/v1","mode":"apply","edits":1,"files":1,"callers_union":4,"graph_ambiguous":10278,"graph_unresolved":12878,"graph_unindexed":237,"counts_floor":true,"applied":1,"atomic_files":1,"atomic_scope":"per-file","rollback_on_write_error":true,"recheck_before_each_write":true,"mul … [line truncated: 538 more bytes on this line]
{"n":"benchAdaptive","p":"bench/bench_radix_ab.cpp:157","l":[162]},
{"n":"radixSortNonNegativeFloatsDesc","p":"src/infra/sortutil.h:107","l":[116]},
{"n":"radixSortByScoreDescId","p":"src/infra/sortutil.h:122","l":[182]}],
"graph_ambiguous":10278,"graph_unresolved":12878,"graph_unindexed":237,"counts_floor":true}}]}
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

**exit code: 2** — **wall time: 9.05s**

`````
<!-- ripwire quality-delta schema=ripwire.quality-delta/v1: only what the change made WORSE vs baseline=: regressions= minor= gating=; <r kind= sym= p= was= now= gating= bar=>, <sa> acked. value-ref-excluded=N: internal functions kept off because a table, field or argument holds them (matched by name, not a proven call); a floor. at=: commit+dirty+shallow. next=: the one pasteable follow-up. stale=N: ack ledger rows whose target no longer applies (sa rows); never gating. preexisting-worse=N: regressions on symbols that existed at baseline; only these gate (when major). new-symbol=N: regressions on NEW code; never gate, but the debt is yours: read them. register-macro-excluded=N: symbols kept out of dead-code as self-registering test/bench macros; a floor. api-new-surface=N: new PUBLIC symbols; a count, never gates, not in regressions=. renames=/rename_window_commits=: git rename pairs read over that many commits, to re-file baseline and acks. acked_by_rename=/acked_by_content=: acked= suppressions matched via git renames / an equal body hash. renames_window_truncated=1: history is deeper than the rename window, older renames unread. acked=N: findings suppressed by the ack ledger, listed as sa rows; never gating. r origin=new-symbol: the finding is on NEW code, never gating (absent: preexisting-worse). sa key=/why=: the stale ack's ledger hash / target-gone (names nothing now) or finding-gone (no longer fires). r members=/tokens=: a duplication row's clone group (member ids) / their shared normalized-token count. -->
<quality-delta schema="ripwire.quality-delta/v1" baseline="git-HEAD" regressions="5" minor="0" acked="1" stale="134" preexisting-worse="2" new-symbol="3" gating="2" register-macro-excluded="62" api-new-surface="2" at="c7920353a+dirty" renames="57" rename_window_commits="400" acked_by_rename="0" acke … [line truncated: 70 more bytes on this line]
<r kind="dead-code" sym="src/infra/sortutil.h::rw::sortutil::nonNegativeFloatAscKeyCopy" origin="new-symbol" p="src/infra/sortutil.h:88"/>
<r kind="dead-code" sym="src/infra/sortutil.h::rw::sortutil::sortScoredIdsWithOptions" origin="new-symbol" p="src/infra/sortutil.h:98"/>
<r kind="duplication" members="src/infra/sortutil.h::rw::sortutil::nonNegativeFloatAscKeyCopy | src/infra/sortutil.h::rw::sortutil::nonNegativeFloatDescKey" tokens="59" p="src/infra/sortutil.h:88" gating="1"/>
<r kind="new-clone-of-reused-helper" sym="src/infra/sortutil.h::rw::sortutil::nonNegativeFloatAscKeyCopy | src/infra/sortutil.h::rw::sortutil::nonNegativeFloatDescKey" was="0" now="4" p="src/infra/sortutil.h:88" gating="1" next="--expand=src/infra/sortutil.h:nonNegativeFloatDescKey"/>
<r kind="params" sym="src/infra/sortutil.h::rw::sortutil::sortScoredIdsWithOptions" was="0" now="8" bar="5" origin="new-symbol" p="src/infra/sortutil.h:98"/>
<sa kind="api-surface" key="085e3d408c2c4a35" why="target-gone"/>
<sa kind="api-surface" key="155d74d341a49f3c" why="target-gone"/>
<sa kind="api-surface" key="1a15386c2d1e47af" why="target-gone"/>
<sa kind="api-surface" key="298e798c7f075715" why="target-gone"/>
<sa kind="api-surface" key="56acdf9b5c314a14" why="target-gone"/>
<sa kind="api-surface" key="5a07390012b46e06" why="target-gone"/>
<sa kind="api-surface" key="6eef859578c8c376" why="target-gone"/>
<sa kind="api-surface" key="6f2394762f82a855" why="target-gone"/>
<sa kind="api-surface" key="7f2c3eefdf6e512e" why="target-gone"/>
<sa kind="api-surface" key="802e513731103806" why="target-gone"/>
<sa kind="api-surface" key="b6a24afef32a68a8" why="target-gone"/>
<sa kind="api-surface" key="c923e661c197b265" why="target-gone"/>
<sa kind="api-surface:new-symbol" key="1926b0d9e94541a0" why="target-gone"/>
<sa kind="api-surface:new-symbol" key="1d3814ba687a4aef" why="target-gone"/>
<sa kind="api-surface:new-symbol" key="1db76028879244ef" why="target-gone"/>
<sa kind="api-surface:new-symbol" key="36e39c7ab0fc1686" why="target-gone"/>
<sa kind="api-surface:new-symbol" key="4bce64bd920de0c3" why="target-gone"/>
<sa kind="api-surface:new-symbol" key="61f0e361ef7dee27" why="target-gone"/>
<sa kind="api-surface:new-symbol" key="79625906f9f71ad0" why="target-gone"/>
<sa kind="api-surface:new-symbol" key="8ecb190954dce18a" why="target-gone"/>
<sa kind="api-surface:new-symbol" key="995375dfa4e63104" why="target-gone"/>
<sa kind="api-surface:new-symbol" key="ee71e4fffa361902" why="target-gone"/>
<sa kind="complexity" key="0001f7edbff929e5" why="finding-gone" sym="src/cli.h::rw::validateLegendModifier" p="src/cli.h:4344"/>
… [112 more display lines; full output is 14523 bytes on 1 raw line(s)]
`````

stderr:

`````
ripwire: no ./.ripwire_quality_baseline — auto-comparing the working tree vs git HEAD (commit the baseline with --quality-baseline to pin it)
ripwire: --quality-delta gating: 2 preexisting-worse major finding(s); first: duplication src/infra/sortutil.h::rw::sortutil::nonNegativeFloatAscKeyCopy | src/infra/sortutil.h::rw::sortutil::nonNegativeFloatDescKey at src/infra/sortutil.h:88 (was=0 now=59)
`````

## `./build/ripwire . --quality-baseline`

*REFUSES, exit 1: this sandbox tree is already regressed, and pinning here would swallow that debt into the floor so every later delta read clean. It names how many gating findings it would absorb, the first of them, and the way forward.*

**exit code: 1** — **wall time: 7.01s**

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

**wall time: 10.01s**

`````
(empty)
`````

stderr:

`````
ripwire: --quality-baseline --allow-dirty: pinned with 2 gating finding(s) ABSORBED into the floor (stamped in the sidecar; every --quality-delta against it carries baseline_absorbed="2")
ripwire: wrote ./.ripwire_quality_baseline (snapshot of 23138 per-symbol rows, 23853 indexed symbols total)
`````

Artifact written:

`````
 3876272 .ripwire_quality_baseline
# ripwire quality baseline v6 — regenerate with --quality-baseline; do not hand-edit
producer 075ad01d2576bcb1b0bdac7efeb7b3b61d37df7c7fb9adbf3794b90643e96ba0
head c7920353a6d41f95f6ad61193358a10a3b255acf
dirty 1
absorbed 2
ccx d19d7c13cbc7 2
ccx 1f7edbff929e5 10
ccx 6a732f6699bdb 0
ccx 7d8862be4e
`````

## `./build/ripwire . --quality-delta`

*Against that sidecar the same tree reads regressions=0 — but baseline_absorbed= is on the root, so this green means clean SINCE THE PIN, never clean. A baseline is a floor YOU chose, and it belongs BEFORE the change.*

**wall time: 11.55s**

`````
<!-- ripwire quality-delta schema=ripwire.quality-delta/v1: only what the change made WORSE vs baseline=: regressions= minor= gating=; <r kind= sym= p= was= now= gating= bar=>, <sa> acked. value-ref-excluded=N: internal functions kept off because a table, field or argument holds them (matched by name, not a proven call); a floor. at=: commit+dirty+shallow. stale=N: ack ledger rows whose target no longer applies (sa rows); never gating. preexisting-worse=N: regressions on symbols that existed at baseline; only these gate (when major). new-symbol=N: regressions on NEW code; never gate, but the debt is yours: read them. register-macro-excluded=N: symbols kept out of dead-code as self-registering test/bench macros; a floor. api-new-surface=N: new PUBLIC symbols; a count, never gates, not in regressions=. renames=/rename_window_commits=: git rename pairs read over that many commits, to re-file baseline and acks. acked_by_rename=/acked_by_content=: acked= suppressions matched via git renames / an equal body hash. renames_window_truncated=1: history is deeper than the rename window, older renames unread. acked=N: findings suppressed by the ack ledger, listed as sa rows; never gating. sa key=/why=: the stale ack's ledger hash / target-gone (names nothing now) or finding-gone (no longer fires). -->
<quality-delta schema="ripwire.quality-delta/v1" baseline="sidecar" regressions="0" minor="0" acked="0" stale="134" preexisting-worse="0" new-symbol="0" gating="0" register-macro-excluded="62" api-new-surface="0" at="c7920353a+dirty" renames="57" rename_window_commits="400" acked_by_rename="0" acked … [line truncated: 91 more bytes on this line]
<sa kind="api-surface" key="085e3d408c2c4a35" why="target-gone"/>
<sa kind="api-surface" key="155d74d341a49f3c" why="target-gone"/>
<sa kind="api-surface" key="1a15386c2d1e47af" why="target-gone"/>
<sa kind="api-surface" key="298e798c7f075715" why="target-gone"/>
<sa kind="api-surface" key="56acdf9b5c314a14" why="target-gone"/>
<sa kind="api-surface" key="5a07390012b46e06" why="target-gone"/>
<sa kind="api-surface" key="6eef859578c8c376" why="target-gone"/>
<sa kind="api-surface" key="6f2394762f82a855" why="target-gone"/>
<sa kind="api-surface" key="7f2c3eefdf6e512e" why="target-gone"/>
<sa kind="api-surface" key="802e513731103806" why="target-gone"/>
<sa kind="api-surface" key="b6a24afef32a68a8" why="target-gone"/>
<sa kind="api-surface" key="c923e661c197b265" why="target-gone"/>
<sa kind="api-surface:new-symbol" key="1926b0d9e94541a0" why="target-gone"/>
<sa kind="api-surface:new-symbol" key="1d3814ba687a4aef" why="target-gone"/>
<sa kind="api-surface:new-symbol" key="1db76028879244ef" why="target-gone"/>
<sa kind="api-surface:new-symbol" key="36e39c7ab0fc1686" why="target-gone"/>
<sa kind="api-surface:new-symbol" key="4bce64bd920de0c3" why="target-gone"/>
<sa kind="api-surface:new-symbol" key="61f0e361ef7dee27" why="target-gone"/>
<sa kind="api-surface:new-symbol" key="79625906f9f71ad0" why="target-gone"/>
<sa kind="api-surface:new-symbol" key="8ecb190954dce18a" why="target-gone"/>
<sa kind="api-surface:new-symbol" key="995375dfa4e63104" why="target-gone"/>
<sa kind="api-surface:new-symbol" key="ee71e4fffa361902" why="target-gone"/>
<sa kind="complexity" key="0001f7edbff929e5" why="finding-gone" sym="src/cli.h::rw::validateLegendModifier" p="src/cli.h:4344"/>
<sa kind="complexity" key="3a0425468e6a18cf" why="finding-gone" sym="src/crossref.h::crossref::writeWhereisPage" p="src/crossref.h:3193"/>
<sa kind="complexity" key="4b309450f25c2b44" why="finding-gone" sym="src/ingest.cpp::rw::ingest" p="src/ingest.cpp:292"/>
<sa kind="complexity" key="7051b3950aaf4c14" why="finding-gone" sym="src/mention.h::rw::applyDocMentionBoost" p="src/mention.h:1336"/>
<sa kind="complexity" key="7a04eee0ff6ec2d7" why="finding-gone" sym="src/recall.h::rw::buildSectionGranularBody" p="src/recall.h:1225"/>
<sa kind="complexity" key="a9f76a08efdb3d50" why="finding-gone" sym="runAffected" p="src/verbs_change.h:69"/>
… [107 more display lines; full output is 13388 bytes on 1 raw line(s)]
`````


---

# the MCP dialect — the same verbs over stdio JSON-RPC (one-shot exchange, not a persistent server)

## `printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize"}' '{"jsonrpc":"2.0","id":2,"method":"tools/list"}' | ./build/ripwire --mcp`

*initialize + tools/list: the manifest an agent host loads at session start — every verb's name, description and input schema.*

`````
{"jsonrpc":"2.0","id":1,"result":{"protocolVersion":"2025-11-25","serverInfo":{"name":"ripwire","version":"1.0"},"capabilities":{"tools":{},"resources":{}},"instructions":"Map before reading files. Start a new task with explore; use from_trace for an error; use impact plus uses before changing a sym … [line truncated: 738 more bytes on this line]
{"jsonrpc":"2.0","id":2,"result":{"tools":[{"name":"analyze","description":"Architecture map for a directory: signatures and the call graph for the top symbols. Use when landing cold in a repo or subdir, before reading files; for a task-scoped inventory use 'for', for one symbol's neighborhood find_ … [line truncated: 742 more bytes on this line]
{"name":"rank_by","description":"The SAME architecture map 'analyze' serves, ranked by a different signal instead of plain PageRank. rank_by = pagerank (default, omit it — the CLI's own unbiased --rank-by=pagerank; 'analyze' can rank differently on a tree with uncommitted changes, where it biases  … [line truncated: 1077 more bytes on this line]
{"name":"find_symbol","description":"A symbol's 1-hop neighborhood: the symbol (with a fetch_body handle) plus direct callers (calledBy) and callees (calls). Full transitive reach: 'impact'. Read/write/import sites, not just calls: 'uses'. JSON {symbol, calledBy, calls, defs, count, hop_tested, hop_ … [line truncated: 1181 more bytes on this line]
{"name":"find_referencing_symbols","description":"Direct (1-hop) callers of a symbol, each with a fetch_body handle. For the full transitive blast radius use 'impact', for read/write/import sites 'uses'. JSON {symbol, calledBy, defs, count, hop_tested, hop_untested, declined_calls, counts_floor}; ca … [line truncated: 945 more bytes on this line]
{"name":"grep","description":"Trigram literal search; each hit annotated with its enclosing symbol (which function/class it is in). Hits carry text; enclosing rows a fetch_body handle. pattern = the literal; in=any lifts the span tiering (default: tightest non-empty tier; rest rides as suppressed_co … [line truncated: 837 more bytes on this line]
{"name":"cochange","description":"Files that historically change together with this file — the co-edit partners. Fowler's Shotgun Surgery as change coupling. dep_capable=false means neither side could carry one (sh/md/json/binary), so surprising is undefined rather than informative. file = the fil … [line truncated: 700 more bytes on this line]
{"name":"memory_recall","description":"Most relevant memory notes / docs for a task, full text — the few that matter, not the whole corpus. path = docs/memory dir; task = what you're working on; top_k = docs to return, 1..1000 (default 8), refused outside that band, never clamped; budget_tokens =  … [line truncated: 790 more bytes on this line]
{"name":"situational_awareness","description":"The 5 things to know about a diff, as JSON: blast_radius, tests_to_run, forgotten (usual co-change partners missing from this diff), hotspot_alert, modules_touched. forgotten = the Shotgun Surgery check. diff/files optional — defaults to 'git diff HEA … [line truncated: 1297 more bytes on this line]
{"name":"mentions","description":"Docs (markdown plans/designs) that name a code symbol in a backtick. symbol = the code symbol name; limit/offset page the files. An @FILE:LINE line-seed rebinds to the innermost definition enclosing that line and answers for it, disclosing the rebound name as 'sym'  … [line truncated: 625 more bytes on this line]
{"name":"for","description":"Task-lens ranked, signatures-only inventory of the building blocks most relevant to a task (cx=complexity, in=reuse-count). task = the task in plain words; budget_tokens = an optional ceiling (the CLI --for --token-budget). The header carries route= (which ranker answere … [line truncated: 1053 more bytes on this line]
{"name":"lego","description":"Interface-to-impls view for ONE named interface/base: its method contract plus EVERY implementor (own-language only), each with file path. Use when implementing against a KNOWN interface (contrast 'for', which sprays top interfaces for a task). type = interface/base nam … [line truncated: 657 more bytes on this line]
{"name":"owners","description":"Bus-factor: recency-weighted (6-month half-life) author ownership per file. symbol = optional, restricts to the file that defines it; limit/offset page the rows. at= is the commit these numbers were computed at (+dirty = the working tree differed). An @FILE:LINE line- … [line truncated: 879 more bytes on this line]
{"name":"replace_symbol_body","description":"Replace a symbol's ENTIRE definition (signature through closing brace) with new_body — splices over the full def span, preserving every byte outside it verbatim; new_body must be a complete, well-formed definition. One trailing newline folds (trailing_n … [line truncated: 1323 more bytes on this line]
{"name":"insert_before_symbol","description":"Insert text immediately BEFORE a symbol's definition (its first byte); padded to the file's own blank-line seam (separator_padded=N). Same refusal contract as replace_symbol_body (not found / ambiguous / stale index / symlink / concurrent write, file unc … [line truncated: 877 more bytes on this line]
{"name":"insert_after_symbol","description":"Insert text immediately AFTER a symbol's definition (past its final byte, which is preserved exactly); padded to the file's own blank-line seam (separator_padded=N); one trailing newline folds (trailing_newline_folded). Same refusal contract as replace_sy … [line truncated: 878 more bytes on this line]
{"name":"fetch_body","description":"Full (or partial-range) source of a symbol's definition, addressed by the stable `handle` a read verb attached to it (bodies on request, not by default). start_line/end_line are optional, 1-based, INCLUSIVE and BODY-RELATIVE (line 1 = the def's first line), clampe … [line truncated: 1049 more bytes on this line]
{"name":"exemplar","description":"BEFORE writing a function / method / class / struct / interface / variable, get the repo's single best-in-class instance of that kind to imitate — signature AND full body. chosen by ROLE, NEVER by text similarity to your task: candidates are first filtered to cogn … [line truncated: 1375 more bytes on this line]
{"name":"quality_delta","description":"Your PR self-check, run every time you think a change is DONE — pairs with the CLI-only --test-gate (names the tests to run + the untested blast radius; not MCP-exposed) to form the two-step pre-PR gate. Reports ONLY what your working tree made WORSE vs basel … [line truncated: 806 more bytes on this line]
{"name":"quality_baseline","description":"PIN the quality floor: writes .ripwire_quality_baseline stamped with the current git HEAD sha, snapshotting complexity / duplication / dead-code / API surface. Call once at the start of non-trivial work, then quality_delta compares against this pinned floor  … [line truncated: 445 more bytes on this line]
{"name":"impact","description":"IS IT SAFE TO CHANGE X? — the TRANSITIVE blast radius of a symbol via calls, nearest first (d= hop depth), then PageRank. Use before modifying or deleting a symbol; it beats find_referencing_symbols (direct callers only), and 'uses' catches the read/write/import sit … [line truncated: 1325 more bytes on this line]
{"name":"uses","description":"The STATICALLY RESOLVABLE use-sites of a symbol, not just calls: role (call | read | write | import | extends), file:line, and enclosing symbol. Use to see the footprint before renaming or changing a name — find_referencing_symbols and impact follow only calls. extern … [line truncated: 1146 more bytes on this line]
{"name":"affected","description":"WHICH TESTS TO RUN for a change — test files that transitively reach the changed files/symbols, ranked by evidence (edited > partner-named > hop distance). files = changed files and/or symbols, comma-separated: each item is tried as an indexed PATH pattern first,  … [line truncated: 1238 more bytes on this line]
{"name":"path_between","description":"Does A REACH B, and HOW? — the shortest directed CALL path between two symbols, hop-by-hop. reachable=\"0\" hops=\"0\" is a valid 'not reachable' answer — call edges are name-based, so a missing dynamic/callback edge can hide a real path. Named path_between  … [line truncated: 709 more bytes on this line]
{"name":"connect","description":"When a task touches 2..16 named symbols, returns the minimal subgraph RELATING them - terminals, the fewest joining intermediaries (with signatures), and call edges in true direction - finding the shared-caller joins a directed path_between cannot; unrelated symbols  … [line truncated: 950 more bytes on this line]
{"name":"explore","description":"ONE-call task orientation: the routed+anchored ranking, full bodies of the top hits, their 1-hop callers, field notes, and tests_to_run — ALL under one deterministic byte budget, in a fixed section order (ranking > bodies > callers > notes > tests) that degrades gr … [line truncated: 1933 more bytes on this line]
{"name":"from_trace","description":"Paste a stack trace / sanitizer report / compiler error and get it mapped onto indexed symbols, ranked INNERMOST-first: the parsed <trace> frame map, the ranked suspects' signatures, and the innermost in-corpus symbol's FULL body. Out-of-corpus frames are listed a … [line truncated: 1226 more bytes on this line]
{"name":"edit_check","description":"Just edited a symbol? Did its CONTRACT (param count + publicness) change vs git HEAD, and which 1-hop callers are NOW INCOMPATIBLE with the new arity by fixed-arity evidence (not a guess — every folded definition disagrees)? This is call sites worth OPENING, not … [line truncated: 1908 more bytes on this line]
{"name":"whereis","description":"WHERE DOES THIS CONTENT LIVE? Which branch's tree defines or mentions a symbol, HEAD first, with on-head=0 naming the case this verb exists for: content that lives only on a branch (a finished fix stranded on 1 of 30 refs). Each distinct blob is read once (content-ad … [line truncated: 1387 more bytes on this line]
{"name":"stray_content","description":"Per branch: the lines its own divergent work AUTHORED (vs its merge-base with HEAD) that the live line does NOT have. Four verdicts (unmerged+superseded+merged+unknown=refs): v=unmerged is genuinely absent; v=superseded means the live line re-implemented the wo … [line truncated: 1123 more bytes on this line]
{"name":"flags","description":"WHAT IS BUILT BUT DARK here — the answer to 'why don't I see feature X?'. Harvests all three gate patterns (ifndef/define header gates, CMake option(), getenv reads) with each gate's kind, DEFAULT, the size of the code it guards, and its read sites. When a name is bo … [line truncated: 1434 more bytes on this line]
{"name":"doc_drift","description":"WHICH OF THIS REPO'S DOC CLAIMS ARE NOW FALSE. Verifies the CHECKABLE anchors in every markdown file against the live index and returns ONLY the ones that no longer hold: file:line refs (missing-file / past-eof / line-moved), backticked symbol mentions (undefined), … [line truncated: 1167 more bytes on this line]
{"name":"slice","description":"WHERE IS THIS VARIABLE DEFINED AND USED inside one function — NAME-BASED intra-procedural def-use rows of one variable inside ONE uniquely-resolved definition (the ARISE slicer, arXiv:2605.03117). symbol alone lists the sliceable locals to pick from; add var (or spel … [line truncated: 1722 more bytes on this line]
{"name":"batch","description":"ONE-TURN CONTEXT SWEEP: answer up to 16 heterogeneous READ sub-queries in a single call (the deterministic $0 counterpart of a parallel-search agent). queries = array over the SAME path, in EITHER grammar: {verb, ...args} objects, or the CLI --batch file's own \"verb:a … [line truncated: 2040 more bytes on this line]
`````

The manifest, summarised (name / description bytes / required args) — what the host pays in context every session:

`````
tools= 33  manifest_bytes= 46903  (~tokens at 4 bytes/token: 11725 )
batch                        desc_bytes= 1235 schema_bytes=  962 required=['queries']
explore                      desc_bytes= 1322 schema_bytes=  774 required=['task']
edit_check                   desc_bytes= 1180 schema_bytes=  889 required=['symbol']
slice                        desc_bytes=  953 schema_bytes=  932 required=['symbol']
flags                        desc_bytes=  881 schema_bytes=  720 required=[]
whereis                      desc_bytes=  701 schema_bytes=  851 required=['symbol']
exemplar                     desc_bytes=  954 schema_bytes=  591 required=[]
replace_symbol_body          desc_bytes=  865 schema_bytes=  610 required=['symbol', 'new_body']
impact                       desc_bytes=  821 schema_bytes=  666 required=['symbol']
situational_awareness        desc_bytes=  865 schema_bytes=  581 required=[]
affected                     desc_bytes=  790 schema_bytes=  610 required=['files']
from_trace                   desc_bytes=  829 schema_bytes=  559 required=['trace']
find_symbol                  desc_bytes=  752 schema_bytes=  590 required=['symbol']
doc_drift                    desc_bytes=  728 schema_bytes=  604 required=[]
uses                         desc_bytes=  626 schema_bytes=  682 required=['symbol']
stray_content                desc_bytes=  678 schema_bytes=  604 required=[]
rank_by                      desc_bytes=  758 schema_bytes=  481 required=[]
for                          desc_bytes=  445 schema_bytes=  777 required=['task']
fetch_body                   desc_bytes=  623 schema_bytes=  588 required=['handle']
connect                      desc_bytes=  535 schema_bytes=  580 required=['symbols']
find_referencing_symbols     desc_bytes=  505 schema_bytes=  590 required=['symbol']
insert_after_symbol          desc_bytes=  458 schema_bytes=  577 required=['symbol', 'text']
insert_before_symbol         desc_bytes=  455 schema_bytes=  578 required=['symbol', 'text']
owners                       desc_bytes=  425 schema_bytes=  625 required=[]
grep                         desc_bytes=  445 schema_bytes=  562 required=['pattern']
memory_recall                desc_bytes=  447 schema_bytes=  500 required=['task']
quality_delta                desc_bytes=  772 schema_bytes=  193 required=[]
path_between                 desc_bytes=  357 schema_bytes=  506 required=['from', 'to']
cochange                     desc_bytes=  388 schema_bytes=  476 required=['file']
analyze                      desc_bytes=  546 schema_bytes=  318 required=[]
lego                         desc_bytes=  360 schema_bytes=  467 required=['type']
mentions                     desc_bytes=  305 schema_bytes=  486 required=['symbol']
quality_baseline             desc_bytes=  407 schema_bytes=  193 required=[]
`````

## `printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize"}' '{"jsonrpc":"2.0","id":2,"method":"tools/list"}' | ./build/ripwire --mcp --mcp-tools=core`

*--mcp-tools=core: the server lists only the core profile's tools (explore, batch, from_trace, impact, uses, fetch_body, edit_check, quality_delta), so a host that loads every schema at session start pays only for those.*

`````
{"jsonrpc":"2.0","id":1,"result":{"protocolVersion":"2025-11-25","serverInfo":{"name":"ripwire","version":"1.0"},"capabilities":{"tools":{},"resources":{}},"instructions":"Map before reading files. Start a new task with explore; use from_trace for an error; use impact plus uses before changing a sym … [line truncated: 955 more bytes on this line]
{"jsonrpc":"2.0","id":2,"result":{"tools":[{"name":"fetch_body","description":"Full (or partial-range) source of a symbol's definition, addressed by the stable `handle` a read verb attached to it (bodies on request, not by default). start_line/end_line are optional, 1-based, INCLUSIVE and BODY-RELAT … [line truncated: 1092 more bytes on this line]
{"name":"quality_delta","description":"Your PR self-check, run every time you think a change is DONE — pairs with the CLI-only --test-gate (names the tests to run + the untested blast radius; not MCP-exposed) to form the two-step pre-PR gate. Reports ONLY what your working tree made WORSE vs basel … [line truncated: 806 more bytes on this line]
{"name":"impact","description":"IS IT SAFE TO CHANGE X? — the TRANSITIVE blast radius of a symbol via calls, nearest first (d= hop depth), then PageRank. Use before modifying or deleting a symbol; it beats find_referencing_symbols (direct callers only), and 'uses' catches the read/write/import sit … [line truncated: 1325 more bytes on this line]
{"name":"uses","description":"The STATICALLY RESOLVABLE use-sites of a symbol, not just calls: role (call | read | write | import | extends), file:line, and enclosing symbol. Use to see the footprint before renaming or changing a name — find_referencing_symbols and impact follow only calls. extern … [line truncated: 1146 more bytes on this line]
{"name":"explore","description":"ONE-call task orientation: the routed+anchored ranking, full bodies of the top hits, their 1-hop callers, field notes, and tests_to_run — ALL under one deterministic byte budget, in a fixed section order (ranking > bodies > callers > notes > tests) that degrades gr … [line truncated: 1933 more bytes on this line]
{"name":"from_trace","description":"Paste a stack trace / sanitizer report / compiler error and get it mapped onto indexed symbols, ranked INNERMOST-first: the parsed <trace> frame map, the ranked suspects' signatures, and the innermost in-corpus symbol's FULL body. Out-of-corpus frames are listed a … [line truncated: 1226 more bytes on this line]
{"name":"edit_check","description":"Just edited a symbol? Did its CONTRACT (param count + publicness) change vs git HEAD, and which 1-hop callers are NOW INCOMPATIBLE with the new arity by fixed-arity evidence (not a guess — every folded definition disagrees)? This is call sites worth OPENING, not … [line truncated: 1908 more bytes on this line]
{"name":"batch","description":"ONE-TURN CONTEXT SWEEP: answer up to 16 heterogeneous READ sub-queries in a single call (the deterministic $0 counterpart of a parallel-search agent). queries = array over the SAME path, in EITHER grammar: {verb, ...args} objects, or the CLI --batch file's own \"verb:a … [line truncated: 2040 more bytes on this line]
`````

The core manifest, summarised (name / description bytes / required args):

`````
tools= 8  manifest_bytes= 13921  (~tokens at 4 bytes/token: 3480 )
batch                        desc_bytes= 1235 schema_bytes=  962 required=['queries']
explore                      desc_bytes= 1322 schema_bytes=  774 required=['task']
edit_check                   desc_bytes= 1180 schema_bytes=  889 required=['symbol']
impact                       desc_bytes=  821 schema_bytes=  666 required=['symbol']
from_trace                   desc_bytes=  829 schema_bytes=  559 required=['trace']
uses                         desc_bytes=  626 schema_bytes=  682 required=['symbol']
fetch_body                   desc_bytes=  623 schema_bytes=  588 required=['handle']
quality_delta                desc_bytes=  772 schema_bytes=  193 required=[]
`````

## `printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize"}' '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"for","arguments":{"path":".","task":"pagerank power iteration"}}}' | ./build/ripwire --mcp`

*MCP `for`: always bundle=sigs (never the CLI's compact route), the same ranked signatures as --for.*

**wall time: 1.25s**

`````
{"jsonrpc":"2.0","id":1,"result":{"protocolVersion":"2025-11-25","serverInfo":{"name":"ripwire","version":"1.0"},"capabilities":{"tools":{},"resources":{}},"instructions":"Map before reading files. Start a new task with explore; use from_trace for an error; use impact plus uses before changing a sym … [line truncated: 738 more bytes on this line]
{"jsonrpc":"2.0","id":2,"result":{"content":[{"type":"text","text":"<ctx task=\"pagerank power iteration\" route=\"subtoken+body\" root=\".\" confidence=\"high\" margin_pct=\"20\" at=\"c7920353a\" doc_mentions=\"5\" doc_mentions_capped=\"1\" doc_mentions_total=\"16\" bundle=\"sigs\" lens=\"churn,amp … [line truncated: 8971 more bytes on this line]
"_index":"[index: files=2484 symbols=23851 hash=dab62389]","_fresh":"ok"}}
`````

## `printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize"}' '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"whereis","arguments":{"path":".","symbol":"rankGraphTeleport"}}}' '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"whereis","arguments":{"path":".","symbol":"computeOnePairOverlap"}}}' | ./build/ripwire --mcp --mcp-legend=inline`

*--mcp-legend=inline: every answer of the stdio session carries its own legend (the default, session, sends each definition once per session after the first answer).*

**wall time: 20.77s**

`````
{"jsonrpc":"2.0","id":1,"result":{"protocolVersion":"2025-11-25","serverInfo":{"name":"ripwire","version":"1.0"},"capabilities":{"tools":{},"resources":{}},"instructions":"Map before reading files. Start a new task with explore; use from_trace for an error; use impact plus uses before changing a sym … [line truncated: 735 more bytes on this line]
{"jsonrpc":"2.0","id":2,"result":{"content":[{"type":"text","text":"<!-- ripwire whereis schema=ripwire.whereis/v1: every LOCAL ref whose tree holds sym= (refs_scanned=, blobs=), HEAD first: <hit ref= tip= date= p= l= kind= t=>. window: shown= total= capped= has_more= next_offset= offset= limit= (ca … [line truncated: 19100 more bytes on this line]
"_index":"[index: files=2484 symbols=23851 hash=dab62389]","_fresh":"ok"}}
{"jsonrpc":"2.0","id":3,"result":{"content":[{"type":"text","text":"<!-- ripwire whereis schema=ripwire.whereis/v1: every LOCAL ref whose tree holds sym= (refs_scanned=, blobs=), HEAD first: <hit ref= tip= date= p= l= kind= t=>. window: shown= total= capped= has_more= next_offset= offset= limit= (ca … [line truncated: 15761 more bytes on this line]
"_index":"[index: files=2484 symbols=23851 hash=dab62389]","_fresh":"ok"}}
`````

## `printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize"}' '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"explore","arguments":{"path":".","task":"add a new output format flag to the CLI","budget_tokens":2000}}}' | ./build/ripwire --mcp`

*MCP `explore` = --pack-task under a token budget, one call.*

`````
{"jsonrpc":"2.0","id":1,"result":{"protocolVersion":"2025-11-25","serverInfo":{"name":"ripwire","version":"1.0"},"capabilities":{"tools":{},"resources":{}},"instructions":"Map before reading files. Start a new task with explore; use from_trace for an error; use impact plus uses before changing a sym … [line truncated: 738 more bytes on this line]
{"jsonrpc":"2.0","id":2,"result":{"content":[{"type":"text","text":"<ctx schema=\"ripwire.pack-task/v1\" task=\"add a new output format flag to the CLI\" route=\"subtoken+body:declined(add;116-carriers,41-defs)\" root=\".\" dropped_positive=\"2\" est_tokens=\"1596\" budget_tokens=\"2000\"><!-- ripwi … [line truncated: 4236 more bytes on this line]
"_index":"[index: files=2484 symbols=23851 hash=dab62389]","_fresh":"ok"}}
`````

## `printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize"}' '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"fetch_body","arguments":{"path":".","handle":"rankGraphTeleport"}}}' | ./build/ripwire --mcp`

*MCP `fetch_body`: the lazy-body handle posture — bodies only after ranked retrieval, by bare name here.*

`````
{"jsonrpc":"2.0","id":1,"result":{"protocolVersion":"2025-11-25","serverInfo":{"name":"ripwire","version":"1.0"},"capabilities":{"tools":{},"resources":{}},"instructions":"Map before reading files. Start a new task with explore; use from_trace for an error; use impact plus uses before changing a sym … [line truncated: 738 more bytes on this line]
{"jsonrpc":"2.0","id":2,"result":{"content":[{"type":"text","text":"{\"resolved_from_name\":\"rankGraphTeleport\",\"handle\":\"sym#cfb3dc25a9d1fa2c@22dd8dc035d156cf\",\"name\":\"rankGraphTeleport\",\"kind\":\"fn\",\"file\":\"src/graph.h\",\"line\":5565,\"start_line\":1,\"end_line\":29,\"total_lines\ … [line truncated: 1329 more bytes on this line]
"_index":"[index: files=2484 symbols=23851 hash=dab62389]","_fresh":"ok"}}
`````

## `printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize"}' '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"grep","arguments":{"path":".","pattern":"DISCLOSE","limit":3}}}' | ./build/ripwire --mcp`

*MCP `grep` with paging args.*

`````
{"jsonrpc":"2.0","id":1,"result":{"protocolVersion":"2025-11-25","serverInfo":{"name":"ripwire","version":"1.0"},"capabilities":{"tools":{},"resources":{}},"instructions":"Map before reading files. Start a new task with explore; use from_trace for an error; use impact plus uses before changing a sym … [line truncated: 738 more bytes on this line]
{"jsonrpc":"2.0","id":2,"result":{"content":[{"type":"text","text":"{\"pattern\":\"DISCLOSE\",\"root\":\".\",\"files\":240,\"shown\":3,\"capped\":true,\"total\":793,\"has_more\":true,\"next_offset\":3,\"offset\":0,\"limit\":3,\"hits_capped\":false,\"next\":\"--grep=DISCLOSE --offset=3 --legend=compa … [line truncated: 598 more bytes on this line]
{\"file\":\".coderabbit.yaml\",\"line\":30,\"in\":\"path_instructions\",\"text\":\"        A degrade path uses DISCLOSE( sink, why ), never ASSUME(false): a one-argument DISCLOSE( msg ) is a debug trace\"},
{\"file\":\"src/abicheck.h\",\"line\":493,\"in\":\"abicheck::collectAuthoredSites\",\"parse_degraded\":true,\"text\":\"            DISCLOSE( result, AbiResult::DisclosureWhy::NoMergeBase, \\\"abi: no merge-base for a ref (unrelated history?) — that ref is counted, not compared\\\" );\"}],\"parse_d … [line truncated: 540 more bytes on this line]
{\"file\":\"CMakeLists.txt\",\"line\":321},
{\"file\":\"CMakeLists.txt\",\"line\":836}]},\"enclosing\":[{\"n\":\"path_instructions\",\"callers\":0,\"handle_omitted\":\"non-code\"},
{\"n\":\"abicheck::collectAuthoredSites\",\"callers\":1,\"cx\":9,\"handle\":\"sym#1ab32951dcc2d860@40a0924238e63587\"}]}"}],
"_index":"[index: files=2484 symbols=23851 hash=dab62389]","_fresh":"ok"}}
`````

## `printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize"}' '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"slice","arguments":{"path":".","symbol":"rankGraphTeleport","var":"teleport","flow":"back","depth":3}}}' | ./build/ripwire --mcp`

*MCP `slice` — the CLI's --slice/--slice-flow/--slice-depth as one verb.*

`````
{"jsonrpc":"2.0","id":1,"result":{"protocolVersion":"2025-11-25","serverInfo":{"name":"ripwire","version":"1.0"},"capabilities":{"tools":{},"resources":{}},"instructions":"Map before reading files. Start a new task with explore; use from_trace for an error; use impact plus uses before changing a sym … [line truncated: 738 more bytes on this line]
{"jsonrpc":"2.0","id":2,"result":{"content":[{"type":"text","text":"<!-- ripwire slice schema=ripwire.slice/v1: name-based def-use rows of one variable in one definition: <s l= k=def|use|both|scope t= [b= pp= rd=]> (rd= reaching-def lines per reach=cfg|linear), <v n= l= t=> inventory; steps=/depth=  … [line truncated: 1763 more bytes on this line]
"_index":"[index: files=2484 symbols=23851 hash=dab62389]","_fresh":"ok"}}
`````

## `printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize"}' '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"find_symbol","arguments":{"path":".","symbol":"DoesNotExist"}}}' | ./build/ripwire --mcp`

*MCP error shape: an unknown symbol comes back as a JSON-RPC error/refusal, not an empty success.*

`````
{"jsonrpc":"2.0","id":1,"result":{"protocolVersion":"2025-11-25","serverInfo":{"name":"ripwire","version":"1.0"},"capabilities":{"tools":{},"resources":{}},"instructions":"Map before reading files. Start a new task with explore; use from_trace for an error; use impact plus uses before changing a sym … [line truncated: 738 more bytes on this line]
{"jsonrpc":"2.0","id":2,"error":{"code":-32602,"message":"symbol not found: 'DoesNotExist' — pass the final name segment; add scope to disambiguate — or @FILE:LINE when you hold a location","data":{"answer":"{\"of\":\"DoesNotExist\",\"found\":0}"}}}
`````

## `printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize"}' '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"batch","arguments":{"path":".","queries":[{"verb":"for","task":"incremental cache invalidation"},{"verb":"find_referencing_symbols","symbol":"rankGraphTeleport"},{"verb":"grep","pattern":"DISCLOSE","limit":2}]}}}' | ./build/ripwire --mcp`

*MCP `batch`: three independent read queries answered in ONE round-trip — NOTE the sub-query grammar is {verb, ...args} objects with MCP verb names, not the CLI --batch file's verb:arg lines.*

`````
{"jsonrpc":"2.0","id":1,"result":{"protocolVersion":"2025-11-25","serverInfo":{"name":"ripwire","version":"1.0"},"capabilities":{"tools":{},"resources":{}},"instructions":"Map before reading files. Start a new task with explore; use from_trace for an error; use impact plus uses before changing a sym … [line truncated: 738 more bytes on this line]
{"jsonrpc":"2.0","id":2,"result":{"content":[{"type":"text","text":"<batch schema=\"ripwire.batch/v1\" n=\"3\" requested=\"3\" cap=\"16\"><!-- ripwire batch schema=ripwire.batch/v1: n= read sub-queries in one sweep (requested=, cap=): each <q> wraps one sub-answer verbatim in CDATA. i=/verb=/ok=: su … [line truncated: 10382 more bytes on this line]
{\"name\":\"rankGraph\",\"kind\":\"fn\",\"file\":\"src/graph.h\",\"line\":5606,\"handle\":\"sym#b90da690b120eeb3@22dd8dc035d156cf\"},
{\"name\":\"anchoredLexicalRank\",\"kind\":\"fn\",\"file\":\"src/graph.h\",\"line\":6252,\"handle\":\"sym#b3a5ca7873636567@22dd8dc035d156cf\"},
{\"name\":\"runEval\",\"kind\":\"fn\",\"file\":\"src/eval.h\",\"line\":171,\"handle\":\"sym#358fe2cb69804698@667191fb1cea06ca\"},
{\"name\":\"churnDecayRanking\",\"kind\":\"fn\",\"file\":\"src/main.cpp\",\"line\":1380,\"handle\":\"sym#f43b7580f05a651a@1df32c4fc809a394\"},
{\"name\":\"churnRankedGraph\",\"kind\":\"fn\",\"file\":\"src/main.cpp\",\"line\":1419,\"handle\":\"sym#4b5b63d3932ca0ff@1df32c4fc809a394\"},
{\"name\":\"runDefaultMap\",\"kind\":\"fn\",\"file\":\"src/main.cpp\",\"line\":1629,\"handle\":\"sym#6e2725cb96590ec8@1df32c4fc809a394\"}],\"graph_ambiguous\":10278,\"graph_unresolved\":12878,\"graph_unindexed\":237,\"counts_floor\":true}]]></q><q i=\"2\" verb=\"grep\" ok=\"1\"><![CDATA[{\"pattern\" … [line truncated: 818 more bytes on this line]
{\"file\":\".coderabbit.yaml\",\"line\":30,\"in\":\"path_instructions\",\"text\":\"        A degrade path uses DISCLOSE( sink, why ), never ASSUME(false): a one-argument DISCLOSE( msg ) is a debug trace\"}],\"unindexed\":{\"count\":8,\"shown\":2,\"capped\":true,\"rows\":[{\"file\":\"CMakeLists.txt\" … [line truncated: 15 more bytes on this line]
{\"file\":\"CMakeLists.txt\",\"line\":321}]},\"enclosing\":[{\"n\":\"path_instructions\",\"callers\":0,\"handle_omitted\":\"non-code\"}]}]]></q></batch>"}],
"_index":"[index: files=2484 symbols=23851 hash=dab62389]","_fresh":"ok"}}
`````

## `printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize"}' '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"batch","arguments":{"path":".","queries":["for:incremental cache invalidation","callers:rankGraphTeleport"]}}}' | ./build/ripwire --mcp`

*The CLI --batch spelling handed to MCP `batch`: refused, with the accepted shape named.*

`````
{"jsonrpc":"2.0","id":1,"result":{"protocolVersion":"2025-11-25","serverInfo":{"name":"ripwire","version":"1.0"},"capabilities":{"tools":{},"resources":{}},"instructions":"Map before reading files. Start a new task with explore; use from_trace for an error; use impact plus uses before changing a sym … [line truncated: 738 more bytes on this line]
{"jsonrpc":"2.0","id":2,"result":{"content":[{"type":"text","text":"<batch schema=\"ripwire.batch/v1\" n=\"2\" requested=\"2\" cap=\"16\"><!-- ripwire batch schema=ripwire.batch/v1: n= read sub-queries in one sweep (requested=, cap=): each <q> wraps one sub-answer verbatim in CDATA. i=/verb=/ok=: su … [line truncated: 10365 more bytes on this line]
{\"name\":\"rankGraph\",\"kind\":\"fn\",\"file\":\"src/graph.h\",\"line\":5606,\"handle\":\"sym#b90da690b120eeb3@22dd8dc035d156cf\"},
{\"name\":\"anchoredLexicalRank\",\"kind\":\"fn\",\"file\":\"src/graph.h\",\"line\":6252,\"handle\":\"sym#b3a5ca7873636567@22dd8dc035d156cf\"},
{\"name\":\"runEval\",\"kind\":\"fn\",\"file\":\"src/eval.h\",\"line\":171,\"handle\":\"sym#358fe2cb69804698@667191fb1cea06ca\"},
{\"name\":\"churnDecayRanking\",\"kind\":\"fn\",\"file\":\"src/main.cpp\",\"line\":1380,\"handle\":\"sym#f43b7580f05a651a@1df32c4fc809a394\"},
{\"name\":\"churnRankedGraph\",\"kind\":\"fn\",\"file\":\"src/main.cpp\",\"line\":1419,\"handle\":\"sym#4b5b63d3932ca0ff@1df32c4fc809a394\"},
{\"name\":\"runDefaultMap\",\"kind\":\"fn\",\"file\":\"src/main.cpp\",\"line\":1629,\"handle\":\"sym#6e2725cb96590ec8@1df32c4fc809a394\"}],\"graph_ambiguous\":10278,\"graph_unresolved\":12878,\"graph_unindexed\":237,\"counts_floor\":true}]]></q></batch>"}],
"_index":"[index: files=2484 symbols=23851 hash=dab62389]","_fresh":"ok"}}
`````

## `printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize"}' '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"edit_check","arguments":{"path":".","symbol":"rankGraphTeleport"}}}' | ./build/ripwire --mcp`

*MCP `edit_check` on a CLEAN tree.*

**wall time: 3.02s**

`````
{"jsonrpc":"2.0","id":1,"result":{"protocolVersion":"2025-11-25","serverInfo":{"name":"ripwire","version":"1.0"},"capabilities":{"tools":{},"resources":{}},"instructions":"Map before reading files. Start a new task with explore; use from_trace for an error; use impact plus uses before changing a sym … [line truncated: 738 more bytes on this line]
{"jsonrpc":"2.0","id":2,"result":{"content":[{"type":"text","text":"<!-- ripwire edit-check schema=ripwire.edit-check/v1: sym='s contract NOW vs HEAD: status=unchanged|new-symbol|contract-change; <c n= p= incompatible=1 sites_l=> callers. counts_floor=1: every count is a FLOOR, never a total. graph_ … [line truncated: 1168 more bytes on this line]
"_index":"[index: files=2484 symbols=23851 hash=dab62389]","_fresh":"ok"}}
`````

## `printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize"}' '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"edit_check","arguments":{"path":".","symbol":"rankGraphTeleport","legend":"compact"}}}' | ./build/ripwire --mcp`

*The same MCP `edit_check` with legend:"compact" — the CLI --legend=compact dialect on the MCP side (declared on the 16 XML verbs): ~5.5 KB of legend down to ~600 B, rows identical; an unknown or empty legend value is refused, never read as the default.*

**wall time: 3.17s**

`````
{"jsonrpc":"2.0","id":1,"result":{"protocolVersion":"2025-11-25","serverInfo":{"name":"ripwire","version":"1.0"},"capabilities":{"tools":{},"resources":{}},"instructions":"Map before reading files. Start a new task with explore; use from_trace for an error; use impact plus uses before changing a sym … [line truncated: 738 more bytes on this line]
{"jsonrpc":"2.0","id":2,"result":{"content":[{"type":"text","text":"<!-- ripwire edit-check schema=ripwire.edit-check/v1: sym='s contract NOW vs HEAD: status=unchanged|new-symbol|contract-change; <c n= p= incompatible=1 sites_l=> callers. counts_floor=1: every count is a FLOOR, never a total. graph_ … [line truncated: 1168 more bytes on this line]
"_index":"[index: files=2484 symbols=23851 hash=dab62389]","_fresh":"ok"}}
`````

## `printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize"}' '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"nosuchverb","arguments":{"path":"."}}}' | ./build/ripwire --mcp`

*An unknown verb name — the JSON-RPC error shape.*

`````
{"jsonrpc":"2.0","id":1,"result":{"protocolVersion":"2025-11-25","serverInfo":{"name":"ripwire","version":"1.0"},"capabilities":{"tools":{},"resources":{}},"instructions":"Map before reading files. Start a new task with explore; use from_trace for an error; use impact plus uses before changing a sym … [line truncated: 738 more bytes on this line]
{"jsonrpc":"2.0","id":2,"error":{"code":-32602,"message":"unknown tool: 'nosuchverb' — call tools/list for the 33 available tools"}}
`````
