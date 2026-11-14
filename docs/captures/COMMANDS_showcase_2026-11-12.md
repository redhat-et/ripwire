# ripwire — every verb, run for real

- **Date:** 2026-11-12 (regenerated capture; supersedes any older `docs/captures/COMMANDS_showcase_*.md`)
- **Lives in `docs/captures/`** — a directory the crawl/retrieval lenses SKIP (`kCrawlSkipDirs`, src/ingest.h): a generated doc that quotes every verb's output out-scores the source for any query about the tool and was measured at 77% of `--recall` on this repo when it sat at the root. `test/argvdiffcheck.sh` harvests its `## `-heading command lines as differential vectors — keep that format.
- **Version:** `ripwire 0.6.10 (dev, AppleClang 21.0.0.21000101, emit=std::print, built_from=d1f3ba3d5)`
- **Repo:** the ripwire repo @ `0412539b9` — **CLEAN — `git status --porcelain` is empty**. The diff-aware verbs (`--situ`/`--test-gate`/`--quality-delta`/`--pr-context`/`--map-diff`/`--edit-check`) answer a question about the WORKING TREE, so that condition is part of their answer and every one of their captions below states which tree it recorded against. A clean tree is the honest default for a showcase, so they appear TWICE: once here on the clean tree (their empty/exit-0 shape) and once in the final section against a throwaway `git clone --local` sandbox carrying one deliberate regression, so their real gating shapes are visible without writing a byte into the read-only repo.
- **Corpus:** the ripwire repo itself (dogfood), via `./build/ripwire`
- **Sandbox diff** (the last section only): `.ripwire_notes        |  2 ++
 .ripwire_quality_acks |  1 +
 src/infra/sortutil.h  | 31 ++++++++++++++++++++++++++++---
 3 files changed, 31 insertions(+), 3 deletions(-)` — one preexisting function made deeply nested, one function's arity changed 1 -> 2, one copy-paste duplicate helper, one new 8-parameter public function.

**How to read the blocks:** ripwire's real XML output is minified — often ONE long line. For scanability, long minified lines are displayed re-wrapped with a line break at every tag seam (`><`). Header COMMENT lines (the legends) always appear in full — they are exempt from the per-line cut; any OTHER display line over 300 bytes is cut with a `… [line truncated: N more bytes]` marker, which can hit a long root element or row. `--plan-lanes` emits JSON and is re-wrapped at object seams the same way. Long outputs are cut to their first ~30 display lines with a `… [N more display lines; full output is M bytes]` marker giving the true size. Exit codes are recorded when non-zero; wall time when >1s.

**Not run (and why):** `ripwire <git-url>` (network clone), `--listen` / `--mcp-token` / `--allow-remote-edits` (the HTTP-server posture; `--mcp` itself IS captured in its own section as a one-shot stdio JSON-RPC exchange, and `wrap claude` shows the wiring), `--arch --baseline[-update]` (state writer against the read-only repo — `--note-add` / `--quality-baseline` / `--quality-ack` / the three edit verbs / `--edit-plan` ARE shown, inside the throwaway sandbox clone; `--index-out` / `--pin-census` write to scratch), `--eval-mined` (needs a `minedpair.jsonl` artifact from `bench/mine_traces.py`; none present in the tree), `--refetch` (git-url only), `--lsp` (the editor transport — its one-shot dialogues are gated by `test/lspcheck.sh`, not by showcase blocks), `--max-memory` (the memory guard is silent on this repo by construction; its stops are gated by `test/memguardcheck.sh`), `--force` (wrap-only modifier), `--deadline-ms` (a timing modifier on `--help-task`: a warm index prints exactly the `--help-task` blocks shown only when it finishes within the deadline (a warm run past it abstains as well), and the cold abstention depends on wall-clock timing; gated by `test/helptaskdeadlinecheck.sh`), `--scan-skills` bare form (would sweep `~/.claude/skills`; the explicit-DIR form is shown instead), `--help` (215 lines — read it from the binary).


---

# understand a codebase cold

## `./build/ripwire .`

*The default ranked symbol map — start here when landing cold in a repo.*

**wall time: 3.51s**

`````
<!-- ripwire map schema=ripwire.map/v1: ranked symbol map: <f p= layer=> groups <s t= n= sc= k= amb=> rows (k= rank), <c n=> resolved callees; the header comment is data. est_tokens=: price as emitted (an upper bound under compact). root=: p= relative to it. pr_iters=N: PageRank iterations. data_sections_cut=N: N data Sections (headings, data keys) swapped out of this top-K for lower-ranked code rows; next= pages them first. <inv listed= unlisted=>: files the ranked rows show / do not (sum = files=), each named or counted below. <entry p= n=>: a program entry by its language's convention (C/Go/Rust main, Java/C# static main, a script main its module scope calls, __main__.py), callees as c rows; manifest entries not read. <ls p= n= f=>: n= unshown files under dir p=; f= names its code files, the rest (tests, docs, config, test/doc/example dirs) counted. declined=K: K call sites without edges, including inert Elixir quote sites after unquote/unquote_splicing re-entry. external=K: K calls proven outside the tree, no edge. locality_pinned=K: K calls pinned by locality alone (a guess). extent_suspect_syms=K: K defs failed containment, corpus-wide. macro_blanked_files=K: K files indexed from a macro-blanked re-parse. overloads=N: N same-name defs merged in this row; shown= counts each. prov=scip|binding|import|split|final-segment: how that <c> edge bound (absent: one unique name); split = one arm of an amb= pick; final-segment = a qualified type matched by last name only. files=/symbols=: files and symbols indexed; edges= distinct call edges; shown= symbols printed, a merged row counting each def; ambiguous= calls split over several defs, corpus-wide; unresolved= calls with in-tree evidence and no edge (every def language-filtered or unreachable, or binding refused); order= rows by rank (important-first, important-last; (auto:fill) = flipped past a size threshold) or by path (stable). skipped_oversize=K: K files over a size ceiling, not indexed. unindexed=ext:N: N text files of that extension no grammar reads (6 extensions at most). unindexed_exts=E: E such extensions in all, the list cut. <c via="name">: that callee matched by name alone (receiver unproven); it does NOT mean the edge is false. <c x=N>: N same-named via=name rows merged; callees=FILE:SYM lists all. sc=: enclosing scope; the full id is p::sc::n (p= of the row or its <f>) and selectors take it. amb=K: K calls split over several defs. next=: the one pasteable follow-up. -->
<!-- t=modscope=a-file's-MODULE-SCOPE(n=<file-scope>):the-statements-outside-every-named-definition,where-a-top-level-call-and-an-anonymous-callback-body's-calls-live;a-CALLER-never-a-callee(nothing-in-the-source-can-name-it)-with-no-body-to-expand;a-file-with-no-such-call-has-no-such-row -->
<!-- t=type|alias|functype=a-Go-named-type-by-its-written-form:type=a-defined-type-whose-WRITTEN-form-is-not-a-struct/iface/func-literal(type-N-string;type-W-Pair-too,whatever-Pair-is-underneath),alias=type-A=B,functype=type-F-func(...) -->
<!-- t=alias|functype-in-C++-and-.h:alias=using-X=Y(also-templated-or-class-scope)or-namespace-L=lib(defs=X-prints-its-written-target-as-to=),functype=a-typedef-of-a-function-or-function-pointer-type(typedef-void(*F)(int));other-typedefs-read-t=struct -->
<!-- stem="1": the class/struct/interface a file is named for (2+ name words, all in the file name), added after the file's top-K rows because the rank cut left it out (no kept row dropped; counted in shown=) -->
<!-- files=4497 symbols=39562 edges=38970 shown=204 est_tokens=10635 ambiguous=3456 unresolved=18664 locality_pinned=11 external=11109 declined=41448 extent_suspect_syms=12 macro_blanked_files=7 skipped_oversize=15 unindexed="txt:81,tsv:53,mod:33,jsonl:26,scm:25,expected:15" unindexed_exts=23 order=important-first -->
<r schema="ripwire.map/v1" root="." est_tokens="10635" pr_iters="38" data_sections_cut="1" next="--graph-query=&apos;kind(all,sec)&apos; --offset=0 --limit=200">
<f p="src/infra/nodekind.h" layer="infra">
<s t="fn" n="kindIs" sc="rw" k="0.0031">
</s>
</f>
<f p="src/ingest_metrics.h">
<s t="fn" n="nodeTextOf" k="0.0020">
</s>
</f>
<f p="src/model.h">
<s t="fn" n="relForHash" sc="rw" k="0.0020">
</s>
<s t="fn" n="rootRelPath" sc="rw" k="0.0019">
<c n="relForHash"/>
</s>
<s t="fn" n="isStructOrNamedType" sc="rw" k="0.0009">
</s>
<s t="fn" n="diskPath" sc="rw" k="0.0007">
</s>
<s t="alias" n="NodeId" sc="rw" k="0.0006">
</s>
<s t="fn" n="isDefinitionNotDeclaration" sc="rw" k="0.0004">
<c n="isStructOrNamedType"/>
</s>
… [778 more display lines; full output is 26387 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --top-k=5`

*Same map, capped to the 5 highest-ranked symbols.*

**wall time: 2.20s**

`````
<!-- ripwire map schema=ripwire.map/v1: ranked symbol map: <f p= layer=> groups <s t= n= sc= k= amb=> rows (k= rank), <c n=> resolved callees; the header comment is data. est_tokens=: price as emitted (an upper bound under compact). root=: p= relative to it. pr_iters=N: PageRank iterations. <inv listed= unlisted=>: files the ranked rows show / do not (sum = files=), each named or counted below. <entry p= n=>: a program entry by its language's convention (C/Go/Rust main, Java/C# static main, a script main its module scope calls, __main__.py), callees as c rows; manifest entries not read. <ls p= n= f=>: n= unshown files under dir p=; f= names its code files, the rest (tests, docs, config, test/doc/example dirs) counted. declined=K: K call sites without edges, including inert Elixir quote sites after unquote/unquote_splicing re-entry. external=K: K calls proven outside the tree, no edge. locality_pinned=K: K calls pinned by locality alone (a guess). extent_suspect_syms=K: K defs failed containment, corpus-wide. macro_blanked_files=K: K files indexed from a macro-blanked re-parse. prov=scip|binding|import|split|final-segment: how that <c> edge bound (absent: one unique name); split = one arm of an amb= pick; final-segment = a qualified type matched by last name only. files=/symbols=: files and symbols indexed; edges= distinct call edges; shown= symbols printed, a merged row counting each def; ambiguous= calls split over several defs, corpus-wide; unresolved= calls with in-tree evidence and no edge (every def language-filtered or unreachable, or binding refused); order= rows by rank (important-first, important-last; (auto:fill) = flipped past a size threshold) or by path (stable). skipped_oversize=K: K files over a size ceiling, not indexed. unindexed=ext:N: N text files of that extension no grammar reads (6 extensions at most). unindexed_exts=E: E such extensions in all, the list cut. sc=: enclosing scope; the full id is p::sc::n (p= of the row or its <f>) and selectors take it. amb=K: K calls split over several defs. -->
<!-- t=modscope=a-file's-MODULE-SCOPE(n=<file-scope>):the-statements-outside-every-named-definition,where-a-top-level-call-and-an-anonymous-callback-body's-calls-live;a-CALLER-never-a-callee(nothing-in-the-source-can-name-it)-with-no-body-to-expand;a-file-with-no-such-call-has-no-such-row -->
<!-- t=type|alias|functype=a-Go-named-type-by-its-written-form:type=a-defined-type-whose-WRITTEN-form-is-not-a-struct/iface/func-literal(type-N-string;type-W-Pair-too,whatever-Pair-is-underneath),alias=type-A=B,functype=type-F-func(...) -->
<!-- t=alias|functype-in-C++-and-.h:alias=using-X=Y(also-templated-or-class-scope)or-namespace-L=lib(defs=X-prints-its-written-target-as-to=),functype=a-typedef-of-a-function-or-function-pointer-type(typedef-void(*F)(int));other-typedefs-read-t=struct -->
<!-- files=4497 symbols=39562 edges=38970 shown=5 est_tokens=4017 ambiguous=3456 unresolved=18664 locality_pinned=11 external=11109 declined=41448 extent_suspect_syms=12 macro_blanked_files=7 skipped_oversize=15 unindexed="txt:81,tsv:53,mod:33,jsonl:26,scm:25,expected:15" unindexed_exts=23 order=important-first -->
<r schema="ripwire.map/v1" root="." est_tokens="4017" pr_iters="38">
<f p="src/infra/nodekind.h" layer="infra">
<s t="fn" n="kindIs" sc="rw" k="0.0031">
</s>
</f>
<f p="src/ingest_metrics.h">
<s t="fn" n="nodeTextOf" k="0.0020">
</s>
</f>
<f p="src/model.h">
<s t="fn" n="relForHash" sc="rw" k="0.0020">
</s>
<s t="fn" n="rootRelPath" sc="rw" k="0.0019">
<c n="relForHash"/>
</s>
</f>
<f p="src/infra/Diagnostics.h" layer="infra">
<s t="macro" n="ASSUME" amb="1" k="0.0019">
<c n="RW_ASSUME_" prov="split"/>
<c n="RW_ASSUME_" prov="split"/>
</s>
</f>
<inv listed="4" unlisted="4493">
<entry p="scripts/changelog_assemble.py" n="main">
<c n="repoRoot"/>
… [93 more display lines; full output is 10015 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --top-k=5 --no-inventory`

*The same capped map without its inventory tier: --top-k=5 leaves files out, so the default map appends <inv listed= unlisted=> (program entries, and the files the ranked rows left out) after its rows; --no-inventory drops that tier, and the ranked rows are the same.*

**wall time: 1.85s**

`````
<!-- ripwire map schema=ripwire.map/v1: ranked symbol map: <f p= layer=> groups <s t= n= sc= k= amb=> rows (k= rank), <c n=> resolved callees; the header comment is data. est_tokens=: price as emitted (an upper bound under compact). root=: p= relative to it. pr_iters=N: PageRank iterations. declined=K: K call sites without edges, including inert Elixir quote sites after unquote/unquote_splicing re-entry. external=K: K calls proven outside the tree, no edge. locality_pinned=K: K calls pinned by locality alone (a guess). extent_suspect_syms=K: K defs failed containment, corpus-wide. macro_blanked_files=K: K files indexed from a macro-blanked re-parse. prov=scip|binding|import|split|final-segment: how that <c> edge bound (absent: one unique name); split = one arm of an amb= pick; final-segment = a qualified type matched by last name only. files=/symbols=: files and symbols indexed; edges= distinct call edges; shown= symbols printed, a merged row counting each def; ambiguous= calls split over several defs, corpus-wide; unresolved= calls with in-tree evidence and no edge (every def language-filtered or unreachable, or binding refused); order= rows by rank (important-first, important-last; (auto:fill) = flipped past a size threshold) or by path (stable). skipped_oversize=K: K files over a size ceiling, not indexed. unindexed=ext:N: N text files of that extension no grammar reads (6 extensions at most). unindexed_exts=E: E such extensions in all, the list cut. sc=: enclosing scope; the full id is p::sc::n (p= of the row or its <f>) and selectors take it. amb=K: K calls split over several defs. -->
<!-- t=modscope=a-file's-MODULE-SCOPE(n=<file-scope>):the-statements-outside-every-named-definition,where-a-top-level-call-and-an-anonymous-callback-body's-calls-live;a-CALLER-never-a-callee(nothing-in-the-source-can-name-it)-with-no-body-to-expand;a-file-with-no-such-call-has-no-such-row -->
<!-- t=type|alias|functype=a-Go-named-type-by-its-written-form:type=a-defined-type-whose-WRITTEN-form-is-not-a-struct/iface/func-literal(type-N-string;type-W-Pair-too,whatever-Pair-is-underneath),alias=type-A=B,functype=type-F-func(...) -->
<!-- t=alias|functype-in-C++-and-.h:alias=using-X=Y(also-templated-or-class-scope)or-namespace-L=lib(defs=X-prints-its-written-target-as-to=),functype=a-typedef-of-a-function-or-function-pointer-type(typedef-void(*F)(int));other-typedefs-read-t=struct -->
<!-- files=4497 symbols=39562 edges=38970 shown=5 est_tokens=1306 ambiguous=3456 unresolved=18664 locality_pinned=11 external=11109 declined=41448 extent_suspect_syms=12 macro_blanked_files=7 skipped_oversize=15 unindexed="txt:81,tsv:53,mod:33,jsonl:26,scm:25,expected:15" unindexed_exts=23 order=important-first -->
<r schema="ripwire.map/v1" root="." est_tokens="1306" pr_iters="38">
<f p="src/infra/nodekind.h" layer="infra">
<s t="fn" n="kindIs" sc="rw" k="0.0031">
</s>
</f>
<f p="src/ingest_metrics.h">
<s t="fn" n="nodeTextOf" k="0.0020">
</s>
</f>
<f p="src/model.h">
<s t="fn" n="relForHash" sc="rw" k="0.0020">
</s>
<s t="fn" n="rootRelPath" sc="rw" k="0.0019">
<c n="relForHash"/>
</s>
</f>
<f p="src/infra/Diagnostics.h" layer="infra">
<s t="macro" n="ASSUME" amb="1" k="0.0019">
<c n="RW_ASSUME_" prov="split"/>
<c n="RW_ASSUME_" prov="split"/>
</s>
</f>
</r>
`````

## `./build/ripwire . --top-k=0 --expand=rankGraphTeleport`

*NEW since the last capture: --top-k=0 means PAYLOAD-ONLY — no ranked map rides along with the body you asked for.*

**wall time: 1.77s**

`````
<ctx schema="ripwire.expand/v1" root="." est_tokens="1217">
<!-- ripwire expand schema=ripwire.expand/v1: full bodies: <bodies shown= total= capped=> of <b t= l= p= n= sibs= sibs_total= sibs_capped= inc=>; <calls>
<c n= l=> resolved callees. window: shown= total= capped= (capped=1 cut). sibs_capped=/inc_capped=: 1 = cut. est_tokens=: price as emitted (an upper bound under compact). root=: p= relative to it. scrubbed=1: this CDATA is not the bytes (]]> split or C0 replaced). redacted=1: a credential shape rewr … [line truncated: 336 more bytes on this line]
<bodies shown="1" total="1" capped="0">
<b t="fn" l="13631" p="src/graph.h" n="rankGraphTeleport" sibs="&lt;file-scope&gt;,DeclinedSiteKind,kNoDeclinedList,Graph,localityKeyAt,ImplementorRow,implementorClosure,LegoClosure,LegoClosureWalk,LegoClosureWalk,take,boundOf,add,expand,legoImplementorClosure,kEdgeName,kEdgeLink,kEdgeKindMask,edgeK … [line truncated: 1665 more bytes on this line]
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
}]]><calls total="4"><c n="biasPrior" l="13590">inline std::vector&lt;float&gt; biasPrior( const Graph&amp; g, const std::vector&lt;float&gt;&amp; p )</c><c n="PROFILE_SCOPE_DESCRIBE" l="1282">#define PROFILE_SCOPE_DESCRIBE( desc )</c><c n="PROFILE_SCOPE_DESCRIBE" l="1296">#define PROFILE_SCOPE_DESC … [line truncated: 289 more bytes on this line]
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

**wall time: 1.93s**

`````
<!-- ripwire map schema=ripwire.map/v1: ranked symbol map: <f p= layer=> groups <s t= n= sc= k= amb=> rows (k= rank), <c n=> resolved callees; the header comment is data. est_tokens=: price as emitted (an upper bound under compact). over_ceiling=1: budget not met. root=: p= relative to it. pr_iters=N: PageRank iterations. declined=K: K call sites without edges, including inert Elixir quote sites after unquote/unquote_splicing re-entry. external=K: K calls proven outside the tree, no edge. locality_pinned=K: K calls pinned by locality alone (a guess). extent_suspect_syms=K: K defs failed containment, corpus-wide. macro_blanked_files=K: K files indexed from a macro-blanked re-parse. max_tokens=/fit_bytes=: tokens asked/the byte cap applied. files=/symbols=: files and symbols indexed; edges= distinct call edges; shown= symbols printed, a merged row counting each def; ambiguous= calls split over several defs, corpus-wide; unresolved= calls with in-tree evidence and no edge (every def language-filtered or unreachable, or binding refused); order= rows by rank (important-first, important-last; (auto:fill) = flipped past a size threshold) or by path (stable). skipped_oversize=K: K files over a size ceiling, not indexed. unindexed=ext:N: N text files of that extension no grammar reads (6 extensions at most). unindexed_exts=E: E such extensions in all, the list cut. sc=: enclosing scope; the full id is p::sc::n (p= of the row or its <f>) and selectors take it. -->
<!-- t=modscope=a-file's-MODULE-SCOPE(n=<file-scope>):the-statements-outside-every-named-definition,where-a-top-level-call-and-an-anonymous-callback-body's-calls-live;a-CALLER-never-a-callee(nothing-in-the-source-can-name-it)-with-no-body-to-expand;a-file-with-no-such-call-has-no-such-row -->
<!-- t=type|alias|functype=a-Go-named-type-by-its-written-form:type=a-defined-type-whose-WRITTEN-form-is-not-a-struct/iface/func-literal(type-N-string;type-W-Pair-too,whatever-Pair-is-underneath),alias=type-A=B,functype=type-F-func(...) -->
<!-- t=alias|functype-in-C++-and-.h:alias=using-X=Y(also-templated-or-class-scope)or-namespace-L=lib(defs=X-prints-its-written-target-as-to=),functype=a-typedef-of-a-function-or-function-pointer-type(typedef-void(*F)(int));other-typedefs-read-t=struct -->
<!-- files=4497 symbols=39562 edges=38970 shown=1 est_tokens=1124 ambiguous=3456 unresolved=18664 locality_pinned=11 external=11109 declined=41448 extent_suspect_syms=12 macro_blanked_files=7 skipped_oversize=15 unindexed="txt:81,tsv:53,mod:33,jsonl:26,scm:25,expected:15" unindexed_exts=23 max_tokens=1500 fit_bytes=3186 over_ceiling=1 order=important-first -->
<r schema="ripwire.map/v1" root="." est_tokens="1124" pr_iters="38">
<f p="src/infra/nodekind.h" layer="infra">
<s t="fn" n="kindIs" sc="rw" k="0.0031">
</s>
</f>
</r>
`````

## `./build/ripwire . --token-budget=100`

*GATE form: exit 3 if the map's own est_tokens exceeds the budget (over-budget failure shape).*

**exit code: 3** — **wall time: 1.43s**

`````
<!-- ripwire map schema=ripwire.map/v1: the ranked map WITHHELD whole, no rows: withheld=1 marks this record, withheld_est_tokens= the map's price, over budget= (the token budget asked); rerun with a larger token budget, or max-tokens to shape a map that fits. -->
<r schema="ripwire.map/v1" withheld_est_tokens="10635" budget="100" withheld="1"/>
`````

stderr:

`````
ripwire: --token-budget exceeded: withheld_est_tokens=10635 > budget=100
`````

## `./build/ripwire . --for="incremental cache invalidation when a file content hash changes"`

*The task lens: ranked signatures + quality metrics framed for the task.*

**wall time: 5.11s**

`````
<ctx task="incremental cache invalidation when a file content hash changes" route="subtoken+body" root="." confidence="low" margin_pct="0" at="0412539b9" doc_mentions="5" schema="ripwire.for/v1" bundle="compact" bodies="0" reason="compact-route" budget_bytes="7500" doc_mentions_capped="1" doc_mentio … [line truncated: 31 more bytes on this line]
<!-- ripwire for schema=ripwire.for/v1: bundle=/bodies=/reason= the body posture; d: cx= ccx= complexity, in= callers (absent cx/ccx/in = 0), churn= amp= change, clone= tested= 1, sc= scope, id=p::sc::n; total= shown= capped=1 if cut; task= the query; d pure=1 const/constexpr sig, next= the follow-up to paste; route= name-exact(X)|subtoken+body[:broad|:declined]; confidence=/margin_pct= head score drop (low=flat); h l= p= n=, c n= l= (joined for same-named callees, shown= counts them), noedge= no callee resolved; h calls capped=1 next= the call listing every callee; fold kind=bodies: b t= n= p= l= top ranked rows' whole bodies, not the answer; served= of total= in budget_bytes=; slice/skip p= n= l=; skip bytes= next=; a skip makes sigs next= it, sigs_next= the signatures-only re-call; d mem= an owner's direct member names by the index (question words first, names only), mem_more= names cut; t p= file outside sigs (weaker), t sym= its top symbols not in sigs/syms (a pointer, not the answer), r= rank (gap = trimmed); t order: code files first, then doc files (a code question); t page rows go on to file-page row 160 (code question: 160 code rows, docs within row 160); past page 0 (code question: past 40 code rows, a doc past row 40) listed last, head files skipped; past 120 of those p= only, p_only= counts them; t folded=class=N: N p= only rows of that class (doc|config|script|testdata|other) not listed, next= pages to them; d e= its last line (absent=unknown, never 0; l= the name's line); c via=name: that callee matched by name alone, receiver unproven (NOT a claim the edge is false) [doc mentions: 5 docs, 3 symbols; doc_mentions=] -->
<!-- root= is the crawl root; p= below is RELATIVE to it (single-root only; absent => p= is ingest's own path, unchanged); at=this commit(+dirty). [budget_bytes= is the default BYTE target this ranked payload was shaped toward: row text shortens toward it, no row of the ranked head is removed for it (sigs past_target=)] [sigs capped=1 with shown=total: rows shrunk, none dropped] [sigs past_target=K: the last K rows are past the budget_bytes target, served because they are rows of the ranked head; none is cut] [sigs next=: one call serving all total= rows uncut] [docs_dropped=N: N shown rows have a doc comment not printed (r>24 always, r5..24 if capped)] [files_first=N: N rows moved so r=1..8 are distinct files' best rows, score order, a repeated name once; same rows; fold, hops keep score order] [cut: doc_mentions_capped="1" doc_mentions_total="6" — an indexing cap dropped content not shown here]; lego/compose collapse to a counted stub by default (a disclosed cut): total= that section's own pre-cap row count, shown="0" capped="1" (nothing rendered here), next= names the sections=lego,compose flag that restores both sections byte-identically in one call est_tokens= prices this bundle in tokens -->
<sigs shown="40" total="40" capped="1" past_target="14" docs_dropped="30" files_first="18" next="--for=&apos;incremental cache invalidation when a file content hash changes&apos; --signatures-only --token-budget=6700">
<d l="141" e="141" n="kCacheMagic" p="src/ingest_cache.h" churn="358" amp="563" pure="1" r="1" next="--expand=src/ingest_cache.h:kCacheMagic">
<doc>incremental cache (--cache): per-file content hash + raw facts so a re-run re-parses ONLY      c…</doc>constexpr std::uint32_t kCacheMagic = 0x4b505443</d>
<d l="2429" e="2429" n="kHeadSnapCacheScheme" sc="quality" p="src/quality.h" churn="584" amp="779" pure="1" r="2">
<doc>and every file whose content hash differs is re-parsed — so a stale or foreign blob self-heals…</doc>constexpr std::uint32_t kHeadSnapCacheScheme = 1</d>
<d l="769" e="776" n="mcpRebuildBaseline" sc="rw" p="src/mcpindex.h" cx="2" ccx="1" in="1" churn="54" amp="135" r="3">inline McpRebuildBaseline mcpRebuildBaseline( const McpIndex&amp; ix, bool isIncrementalPass )</d>
<d l="374" e="391" n="noteFactlessMiss" p="src/ingest_parsepool.h" cx="3" ccx="2" in="1" churn="66" amp="174" tested="1" r="4">inline void noteFactlessMiss( ParsePoolShared&amp; sh, std::size_t fileId, bool nestRefused ) noexcept</d>
<d l="280" e="579" n="prewarmTagsQueries" p="src/ingest_prewarm.h" cx="53" ccx="160" in="1" churn="19" amp="72" tested="1" r="5">inline void prewarmTagsQueries( const std::vector&lt;std::string&gt;&amp; files, const CacheRecords&amp; cache, long long cacheWriteNs, IngestFileScan&amp; scan, QueryPrew … [line truncated: 18 more bytes on this line]
<d l="277" e="306" n="ingestCommitTree" sc="rw::dmm" p="src/dmm.h" cx="6" ccx="5" in="1" churn="16" amp="77" r="6">inline bool ingestCommitTree( const std::string&amp; root, const std::string&amp; sha, const std::vector&lt;std::string&gt;&amp; excludes, std::size_t maxFileBytes, IngestResult&amp; ou … [line truncated: 7 more bytes on this line]
<d l="9737" e="9768" n="legoImplementorsOnSurface" sc="rw" p="src/serialize.h" cx="10" ccx="13" in="2" churn="486" amp="579" r="7">inline std::vector&lt;std::vector&lt;NodeId&gt;&gt; legoImplementorsOnSurface( const IngestResult&amp; ing, const std::vector&lt;std::vector&lt;NodeId&gt;&gt;&amp; imple … [line truncated: 62 more bytes on this line]
<d l="1642" e="1647" n="spanTierMemoPath" sc="rw" p="src/ingest_astquery.h" cx="1" in="3" churn="48" amp="158" tested="1" r="8">inline std::string spanTierMemoPath( const std::string&amp; diskPath )</d>
<d l="496" e="571" n="McpIndex" sc="McpIndex" p="src/mcpindex.h" churn="54" amp="134" r="9">
<doc>persistent in-memory index (parse once, reuse across MCP calls) ---- The MCP server is long-live…</doc>struct McpIndex</d>
<d l="1211" e="1382" n="getIndex" sc="rw" p="src/mcpindex.h" cx="23" ccx="40" in="35" churn="54" amp="169" r="10">inline const McpIndex&amp; getIndex( const std::string&amp; root )</d>
<!-- demote: a <t> in sigs is a lower same-file sibling past answer row 10, a pointer (p= file, sym= name, r= rank), not the answer -->
<t p="src/ingest_cache.h" sym="contentHash64" r="11"/>
<t p="src/ingest_cache.h" sym="CacheEntry" r="12"/>
<t p="src/ingest_cache.h" sym="blobChecksum" r="13"/>
<t p="src/quality.h" sym="contentIdsBySym" r="14"/>
<t p="src/ingest_cache.h" sym="buildCachePathKeys" r="15"/>
<t p="src/ingest_cache.h" sym="buildCacheWritePlan" r="16"/>
<d l="465" e="485" n="indexContentHash" sc="mcpdetail" p="src/mcpindex.h" cx="5" ccx="7" in="1" churn="54" amp="135" r="17">inline std::uint64_t indexContentHash( const std::vector&lt;std::string&gt;&amp; files, const std::vector&lt;long long&gt;&amp; fileMtime, const std::vector&lt;std::uint64_t&gt … [line truncated: 25 more bytes on this line]
<t p="src/mcpindex.h" sym="makeHandle" r="18"/>
<d l="25" e="45" n="IngestFileScan" sc="IngestFileScan" p="src/ingest_prewarm.h" churn="19" amp="71" r="19" mem="markExtractPartial">struct IngestFileScan</d>
<t p="src/ingest_prewarm.h" sym="forgetNestRefusalsForCache" r="20"/>
<d l="356" e="361" n="byteHash" sc="mcpdetail" p="src/mcpindex.h" cx="2" ccx="1" in="7" churn="54" amp="141" r="21">inline std::uint64_t byteHash( const char* data, std::size_t n ) noexcept</d>
<d l="131" e="142" n="emitGrepHandleLegend" p="src/verbs_grep.h" cx="2" ccx="1" in="1" churn="54" amp="128" r="22">void emitGrepHandleLegend( bool enabled )</d>
… [213 more display lines; full output is 23911 bytes on 8 raw line(s)]
`````

## `./build/ripwire . --for="rankGraphTeleport"`

*Name-shaped query: the router picks name-exact BM25 (header says which/why).*

**wall time: 4.81s**

`````
<ctx task="rankGraphTeleport" route="name-exact(rankGraphTeleport); anchors: rankGraphTeleport(src/graph.h)" root="." confidence="high" margin_pct="45" at="0412539b9" doc_mentions="2" schema="ripwire.for/v1" bundle="auto" bodies="1" doc_mentions_capped="1" doc_mentions_total="13" est_tokens="2071">
<!-- ripwire for schema=ripwire.for/v1: bundle=/bodies=/reason= the body posture; d: cx= ccx= complexity, in= callers (absent cx/ccx/in = 0), churn= amp= change, clone= tested= 1, sc= scope, id=p::sc::n; total= shown= capped=1 if cut; task= the query; d pure=1 const/constexpr sig, next= the follow-up to paste; route= name-exact(X)|subtoken+body[:broad|:declined]; confidence=/margin_pct= head score drop (low=flat); b t= n= p= l= full bodies, c n= l= callee signatures; callers of=: the one function's 1-hop callers, s t= n= sc= p=file:line (n=Owner.name folds sc= on a member; sites_at= its call sites, sites_total= if cut; via=name by name only), shown= of total=; d=2 rows: their callers (via=name if every path has a by-name hop), d2_shown= of d2=; capped=1 if cut; floors; next= the radius; t p= file outside sigs (weaker), t sym= its top symbols not in sigs/syms (a pointer, not the answer), r= rank (gap = trimmed); t order: code files first, then doc files (a code question); d e= its last line (absent=unknown, never 0; l= the name's line); c prov=split: a resolver split arm; may be another arm's (NOT a claim the edge is false) [doc mentions: 2 docs, 1 symbol; doc_mentions=] [floor: kept 3 of 40] -->
<!-- root= is the crawl root; p= below is RELATIVE to it (single-root only; absent => p= is ingest's own path, unchanged); at=this commit(+dirty). [cut: doc_mentions_capped="1" doc_mentions_total="13" — an indexing cap dropped content not shown here] est_tokens= prices this bundle in tokens -->
<sigs>
<d l="13631" e="13659" n="rankGraphTeleport" sc="rw" p="src/graph.h" cx="5" ccx="8" in="7" churn="640" amp="874" r="1" next="--expand=src/graph.h:rankGraphTeleport">
<doc>PageRank with an explicit teleport / personalization vector p (Σp = 1). The prior is name-quality-biased through biasPrior() so all rank modes share one weighting seam; the transition matrix (edges</doc>inline RankedGraph rankGraphTeleport( const Graph&amp; g, const std::vector&lt;float&gt;&am … [line truncated: 31 more bytes on this line]
<d l="501" n="The convergence disclosure contract" sc="rank — Personalized PageRank" p="docs/ARCHITECTURE.md" churn="79" amp="202" r="2">#### The convergence disclosure contract</d>
<d l="6342" n="Wave-2 adversarial verification (2026-08-19) — six probes against `aa97c9e`" sc="6. Correctness and quality instruments" p="docs/EVALS.md" churn="1073" amp="1349" r="3">### Wave-2 adversarial verification (2026-08-19) — six probes against `aa97c9e`</d>
</sigs>
<tail total="3" shown="3" capped="0">
<t p="src/graph.h"/>
<t p="docs/ARCHITECTURE.md"/>
<t p="docs/EVALS.md"/>
</tail>
<callers of="rw::rankGraphTeleport" shown="7" total="7" capped="1" d2="48" d2_shown="4" next="--impact=rw::rankGraphTeleport">
<s t="fn" n="getIndex" sc="rw" p="src/mcpindex.h:1211" sites_at="src/mcpindex.h:1323"/>
<s t="fn" n="rankGraph" sc="rw" p="src/graph.h:13674" sites_at="src/graph.h:13678"/>
<s t="fn" n="anchoredLexicalRank" sc="rw" p="src/graph.h:14321" sites_at="src/graph.h:14372"/>
<s t="fn" n="runEval" sc="rw" p="src/eval.h:171" sites_at="src/eval.h:328"/>
<s t="fn" n="churnDecayRanking" p="src/main.cpp:1433" sites_at="src/main.cpp:1447"/>
<s t="fn" n="churnRankedGraph" p="src/main.cpp:1472" sites_at="src/main.cpp:1486 src/main.cpp:1487 src/main.cpp:1501"/>
<s t="fn" n="runDefaultMap" p="src/main.cpp:1759" sites_at="src/main.cpp:1879"/>
<s t="fn" n="symbolQueryJson" sc="rw" p="src/mcpverbs.h:775" d="2"/>
<s t="fn" n="pathText" sc="rw" p="src/mcpverbs.h:3962" d="2"/>
<s t="fn" n="fetchBody" sc="rw" p="src/mcpverbs.h:5789" d="2"/>
<s t="fn" n="computeLensRanking" p="src/verbs_for.h:110" d="2"/>
</callers>
<bodies shown="1" total="1" capped="0">
<b t="fn" l="13631" p="src/graph.h" n="rankGraphTeleport">
<![CDATA[inline RankedGraph rankGraphTeleport( const Graph& g, const std::vector<float>& p, float alpha = 0.85f )
… [28 more display lines; full output is 6348 bytes on 29 raw line(s)]
`````

## `./build/ripwire . --for="rankGraphTeleport" --no-route`

*Same query with routing forced OFF (plain subtoken+body BM25) — contrast with the routed run.*

**wall time: 4.32s**

`````
<ctx task="rankGraphTeleport" root="." confidence="low" margin_pct="0" at="0412539b9" doc_mentions="6" schema="ripwire.for/v1" bundle="auto" bodies="3" budget_bytes="7500" doc_mentions_capped="1" doc_mentions_total="21" est_tokens="11132">
<!-- ripwire for schema=ripwire.for/v1: bundle=/bodies=/reason= the body posture; d: cx= ccx= complexity, in= callers (absent cx/ccx/in = 0), churn= amp= change, clone= tested= 1, sc= scope, id=p::sc::n; total= shown= capped=1 if cut; task= the query; d pure=1 const/constexpr sig, next= the follow-up to paste; confidence=/margin_pct= head score drop (low=flat); b t= n= p= l= full bodies, c n= l= callee signatures; t p= file outside sigs (weaker), t sym= its top symbols not in sigs/syms (a pointer, not the answer), r= rank (gap = trimmed); t order: code files first, then doc files (a code question); t page rows go on to file-page row 160 (code question: 160 code rows, docs within row 160); past page 0 (code question: past 40 code rows, a doc past row 40) listed last, head files skipped; past 120 of those p= only, p_only= counts them; t folded=class=N: N p= only rows of that class (doc|config|script|testdata|other) not listed, next= pages to them; field name= type= owner= rel=: a member of owner=, rel=creates held by value, uses by reference/pointer; d e= its last line (absent=unknown, never 0; l= the name's line); c prov=split: a resolver split arm; may be another arm's (NOT a claim the edge is false) [doc mentions: 6 docs, 3 symbols; doc_mentions=] -->
<!-- root= is the crawl root; p= below is RELATIVE to it (single-root only; absent => p= is ingest's own path, unchanged); at=this commit(+dirty). [budget_bytes= is the default BYTE target this ranked payload was shaped toward: row text shortens toward it, no row of the ranked head is removed for it (sigs past_target=)] [sigs capped=1 with shown=total: rows shrunk, none dropped] [sigs past_target=K: the last K rows are past the budget_bytes target, served because they are rows of the ranked head; none is cut] [sigs next=: one call serving all total= rows uncut] [docs_dropped=N: N shown rows have a doc comment not printed (r>24 always, r5..24 if capped)] [cut: doc_mentions_capped="1" doc_mentions_total="21" — an indexing cap dropped content not shown here] est_tokens= prices this bundle in tokens -->
<sigs shown="40" total="40" capped="1" past_target="15" docs_dropped="25" next="--for=rankGraphTeleport --signatures-only --no-route --token-budget=6800">
<d l="13631" e="13659" n="rankGraphTeleport" sc="rw" p="src/graph.h" cx="5" ccx="8" in="7" churn="640" amp="874" r="1" next="--expand=src/graph.h:rankGraphTeleport">
<doc>PageRank with an explicit teleport / personalization vector p (Σp = 1). The prior is name-quali…</doc>inline RankedGraph rankGraphTeleport( const Graph&amp; g, const std::vector&lt;float&gt;&amp; p, float alpha = 0.85f )</d>
<d l="13674" e="13679" n="rankGraph" sc="rw" p="src/graph.h" cx="2" ccx="1" in="10" churn="640" amp="877" r="2">
<doc>uniform-teleport PageRank (the default). A kRankFlagNotNamed unit (model.h) has no edge and a 0 …</doc>inline RankedGraph rankGraph( const Graph&amp; g, float alpha = 0.85f )</d>
<d l="1472" e="1511" n="churnRankedGraph" p="src/main.cpp" cx="10" ccx="12" in="1" churn="478" amp="610" r="3">inline ChurnRanking churnRankedGraph( const MainDispatch&amp; d )</d>
<d l="2532" e="2536" n="kChurnRankLegend" sc="rw" p="src/serialize.h" churn="486" amp="577" pure="1" r="4">
<doc>L10 (2026-09-04): the old wording claimed &quot;the same corpus ranked by pagerank orders differently…</doc>inline constexpr const char* kChurnRankLegend = &quot;&lt;!-- rank_by=churn: k= is PageRank re-run with the teleport BIASED by git CHANGE-FREQUENCY over window= &quot; &quot;(a c…</d>
<d l="13622" e="13627" n="RankedGraph" sc="RankedGraph" p="src/graph.h" churn="640" amp="867" r="5">struct RankedGraph</d>
<d l="13665" e="13669" n="takeRank" sc="rw" p="src/graph.h" cx="1" in="2" churn="640" amp="869" r="6">inline std::vector&lt;float&gt; takeRank( RankedGraph ranked, RankDisclosure&amp; disclosureOut )</d>
<d l="13590" e="13614" n="biasPrior" sc="rw" p="src/graph.h" cx="5" ccx="4" in="1" churn="640" amp="868" r="7">inline std::vector&lt;float&gt; biasPrior( const Graph&amp; g, const std::vector&lt;float&gt;&amp; p )</d>
<d l="2470" e="2496" n="churnTeleportWorkspace" sc="rw" p="src/gitmine.h" cx="6" ccx="9" in="1" churn="103" amp="152" r="8">inline std::vector&lt;float&gt; churnTeleportWorkspace( const std::vector&lt;std::string&gt;&amp; rootDirs, const IngestResult&amp; ing, const char* since = &quot;18 months ago … [line truncated: 21 more bytes on this line]
<d l="1433" e="1470" n="churnDecayRanking" p="src/main.cpp" cx="7" ccx="7" in="1" churn="478" amp="610" r="9">inline ChurnRanking churnDecayRanking( const MainDispatch&amp; d, const rw::SinceScope&amp; sinceScope, bool isScoped, const char* verbLabel )</d>
<d l="497" e="543" n="rankByText" sc="rw" p="src/mcpverbs.h" cx="11" ccx="19" in="1" churn="612" amp="645" r="10">inline std::string rankByText( const std::string&amp; root, std::string_view mode, int topK, bool stable = false )</d>
<d l="48" e="49" n="pageRankDouble" sc="rw" p="src/pagerank.h" cx="1" churn="8" amp="37" r="11">PageRankRun pageRankDouble( const sparseCsr&lt;float&gt;&amp; inEdges, std::span&lt;const double&gt; weightedOutDegree, std::span&lt;const double&gt; teleport, std::span&lt;double&gt; rank…</d>
<!-- demote: a <t> in sigs is a lower same-file sibling past answer row 10, a pointer (p= file, sym= name, r= rank), not the answer -->
<t p="src/gitmine.h" sym="churnDecayTeleport" r="12"/>
<d l="99" e="206" n="pageRankDouble" sc="rw" p="src/pagerank.cpp" cx="19" ccx="34" in="2" churn="14" amp="44" tested="1" r="13">PageRankRun pageRankDouble( const sparseCsr&lt;float&gt;&amp; inEdges, std::span&lt;const double&gt; weightedOutDegree, std::span&lt;const double&gt; teleport, std::span&lt … [line truncated: 45 more bytes on this line]
<d l="240" e="244" n="didYouMean" sc="rw" p="src/didyoumean.h" cx="2" ccx="1" in="7" churn="10" amp="59" r="14">inline std::string didYouMean( const IngestResult&amp; ing, std::string_view name )</d>
<d l="2750" e="2777" n="churnDecayTeleportWorkspace" sc="rw" p="src/gitmine.h" cx="5" ccx="6" in="1" churn="103" amp="152" r="15">inline std::vector&lt;float&gt; churnDecayTeleportWorkspace( const std::vector&lt;std::string&gt;&amp; rootDirs, const IngestResult&amp; ing, bool* outHasChurnEvidence =  … [line truncated: 13 more bytes on this line]
<d l="1211" e="1382" n="getIndex" sc="rw" p="src/mcpindex.h" cx="23" ccx="40" in="35" churn="54" amp="169" r="16">inline const McpIndex&amp; getIndex( const std::string&amp; root )</d>
<t p="src/serialize.h" sym="DataSectionsCut" r="17"/>
<d l="501" n="The convergence disclosure contract" sc="rank — Personalized PageRank" p="docs/ARCHITECTURE.md" churn="79" amp="202" r="18">#### The convergence disclosure contract</d>
<d l="6342" n="Wave-2 adversarial verification (2026-08-19) — six probes against `aa97c9e`" sc="6. Correctness and quality instruments" p="docs/EVALS.md" churn="1073" amp="1349" r="19">### Wave-2 adversarial verification (2026-08-19) — six probes against `aa97c9e`</d>
<t p="src/gitmine.h" sym="kChurnMergeBombMaxFiles" r="20"/>
<d l="6817" n="Fixed — `rank_by` over MCP no longer answers a different ranking than `--rank-by` on a tree with uncommitted changes" sc="[0.6.2] — 2026-09-21" p="CHANGELOG.md" churn="1063" amp="917" r="21">### Fixed — `rank_by` over MCP no longer answers a different ranking than `--rank-by` on … [line truncated: 36 more bytes on this line]
<t p="docs/EVALS.md" sym="2. Gates for A" r="22"/>
… [271 more display lines; full output is 30749 bytes on 73 raw line(s)]
`````

## `./build/ripwire . --for="rankGraphTeleport" --signatures-only`

*T3 opt-out: the signatures-only lens (no auto bodies, no bundle="auto" attribute) — contrast with the terminal default above.*

**wall time: 12.39s**

`````
<ctx task="rankGraphTeleport" route="name-exact(rankGraphTeleport); anchors: rankGraphTeleport(src/graph.h)" root="." confidence="high" margin_pct="45" at="0412539b9" doc_mentions="2" schema="ripwire.for/v1" doc_mentions_capped="1" doc_mentions_total="13" est_tokens="959">
<!-- ripwire for schema=ripwire.for/v1: bundle=/bodies=/reason= the body posture; d: cx= ccx= complexity, in= callers (absent cx/ccx/in = 0), churn= amp= change, clone= tested= 1, sc= scope, id=p::sc::n; total= shown= capped=1 if cut; task= the query; d pure=1 const/constexpr sig, next= the follow-up to paste; route= name-exact(X)|subtoken+body[:broad|:declined]; confidence=/margin_pct= head score drop (low=flat); t p= file outside sigs (weaker), t sym= its top symbols not in sigs/syms (a pointer, not the answer), r= rank (gap = trimmed); t order: code files first, then doc files (a code question); d e= its last line (absent=unknown, never 0; l= the name's line) [doc mentions: 2 docs, 1 symbol; doc_mentions=] [floor: kept 3 of 40] -->
<!-- root= is the crawl root; p= below is RELATIVE to it (single-root only; absent => p= is ingest's own path, unchanged); at=this commit(+dirty). [cut: doc_mentions_capped="1" doc_mentions_total="13" — an indexing cap dropped content not shown here] est_tokens= prices this bundle in tokens -->
<sigs>
<d l="13631" e="13659" n="rankGraphTeleport" sc="rw" p="src/graph.h" cx="5" ccx="8" in="7" churn="640" amp="874" r="1" next="--expand=src/graph.h:rankGraphTeleport">
<doc>PageRank with an explicit teleport / personalization vector p (Σp = 1). The prior is name-quality-biased through biasPrior() so all rank modes share one weighting seam; the transition matrix (edges</doc>inline RankedGraph rankGraphTeleport( const Graph&amp; g, const std::vector&lt;float&gt;&am … [line truncated: 31 more bytes on this line]
<d l="501" n="The convergence disclosure contract" sc="rank — Personalized PageRank" p="docs/ARCHITECTURE.md" churn="79" amp="202" r="2">#### The convergence disclosure contract</d>
<d l="6342" n="Wave-2 adversarial verification (2026-08-19) — six probes against `aa97c9e`" sc="6. Correctness and quality instruments" p="docs/EVALS.md" churn="1073" amp="1349" r="3">### Wave-2 adversarial verification (2026-08-19) — six probes against `aa97c9e`</d>
</sigs>
<tail total="3" shown="3" capped="0">
<t p="src/graph.h"/>
<t p="docs/ARCHITECTURE.md"/>
<t p="docs/EVALS.md"/>
</tail>
<!-- syms: leads, not the answer: first 6 shown files' symbols it lacks, p=file:line n=Owner.name; by=name task word, by=callee a head <d> row calls it (via=name name-only, prov=split one arm); name_total= callee_total= files_total= cut by the 3-row, 6-file cap; files= head= if under 6, 8 -->
<syms files="3" head="3" name_total="17">
<y p="src/graph.h:13674" n="rankGraph" by="name"/>
<y p="src/graph.h:19114" n="graphCountFloorAttrXml" by="name"/>
<y p="src/graph.h:19123" n="graphGaugeClauses" by="name"/>
</syms>
</ctx>
`````

## `./build/ripwire . --for="tree-sitter parse of a source file" --adaptive`

*Cut the result at the relevance cliff (Adaptive-k) — on a flat ranking nothing is cut and the header says so ([adaptive: kept N of N]).*

**wall time: 10.76s**

`````
<ctx task="tree-sitter parse of a source file" route="subtoken+body" root="." confidence="low" margin_pct="0" at="0412539b9" doc_mentions="1" schema="ripwire.for/v1" bundle="compact" bodies="0" reason="compact-route" budget_bytes="7500" est_tokens="9950">
<!-- ripwire for schema=ripwire.for/v1: bundle=/bodies=/reason= the body posture; d: cx= ccx= complexity, in= callers (absent cx/ccx/in = 0), churn= amp= change, clone= tested= 1, sc= scope, id=p::sc::n; total= shown= capped=1 if cut; task= the query; d pure=1 const/constexpr sig, next= the follow-up to paste; d same_as=N: doc+sig text as row n=N (not repeated); route= name-exact(X)|subtoken+body[:broad|:declined]; confidence=/margin_pct= head score drop (low=flat); h l= p= n=, c n= l= (joined for same-named callees, shown= counts them), noedge= no callee resolved; fold kind=bodies: b t= n= p= l= top ranked rows' whole bodies, not the answer; served= of total= in budget_bytes=; slice/skip p= n= l=; skip bytes= next=; a skip makes sigs next= it, sigs_next= the signatures-only re-call; d mem= an owner's direct member names by the index (question words first, names only), mem_more= names cut; t p= file outside sigs (weaker), t sym= its top symbols not in sigs/syms (a pointer, not the answer), r= rank (gap = trimmed); t order: code files first, then doc files (a code question); t page rows go on to file-page row 160 (code question: 160 code rows, docs within row 160); past page 0 (code question: past 40 code rows, a doc past row 40) listed last, head files skipped; past 120 of those p= only, p_only= counts them; t folded=class=N: N p= only rows of that class (doc|config|script|testdata|other) not listed, next= pages to them; d e= its last line (absent=unknown, never 0; l= the name's line) [adaptive: kept 40 of 40 - no relevance cliff (broad query saturates the score); capped at the ceiling] [doc mentions: 1 doc, 1 symbol; doc_mentions=] -->
<!-- root= is the crawl root; p= below is RELATIVE to it (single-root only; absent => p= is ingest's own path, unchanged); at=this commit(+dirty). [budget_bytes= is the default BYTE target this ranked payload was shaped toward: row text shortens toward it, no row of the ranked head is removed for it (sigs past_target=)] [sigs capped=1 with shown=total: rows shrunk, none dropped] [sigs past_target=K: the last K rows are past the budget_bytes target, served because they are rows of the ranked head; none is cut] [sigs next=: one call serving all total= rows uncut] [docs_dropped=N: N shown rows have a doc comment not printed (r>24 always, r5..24 if capped)] [files_first=N: N rows moved so r=1..8 are distinct files' best rows, score order, a repeated name once; same rows; fold, hops keep score order]; lego/compose collapse to a counted stub by default (a disclosed cut): total= that section's own pre-cap row count, shown="0" capped="1" (nothing rendered here), next= names the sections=lego,compose flag that restores both sections byte-identically in one call est_tokens= prices this bundle in tokens -->
<sigs shown="40" total="40" capped="1" past_target="7" docs_dropped="24" files_first="7" next="--for=&apos;tree-sitter parse of a source file&apos; --signatures-only --adaptive --token-budget=5500">
<d l="28" e="63" n="topLevelEvidence" sc="rw::pythonrunner" p="src/pythonrunner.h" cx="4" ccx="3" in="2" churn="5" amp="15" r="1" next="--expand=src/pythonrunner.h:topLevelEvidence">inline bool topLevelEvidence( std::string_view source, const TSLanguage* language, const Predicate&amp; predicate )</d … [line truncated: 1 more bytes on this line]
<d l="45" e="45" n="kDefaultMaxFileBytes" sc="rw" p="src/ingest.h" churn="61" amp="166" pure="1" r="2">
<doc>The crawl&apos;s per-file byte ceiling. A text file larger than this is skipped: at this size it is o…</doc>constexpr std::size_t kDefaultMaxFileBytes = 4u * 1024u * 1024u</d>
<d l="1247" e="1255" n="parseTree" p="src/ingest_sidecap.h" cx="1" in="3" churn="170" amp="340" tested="1" r="3">TSTree* parseTree( TSParser* parser, std::string_view src )</d>
<d l="527" e="565" n="SourceReader" sc="SourceReader" p="src/forselfhook.h" churn="8" amp="8" r="4">
<doc>The parses of the files the sites sit in, a few kept: the sites of one method sit in few files</doc>class SourceReader</d>
<d l="594" e="669" n="doctorProbeGrammars" p="src/verbs_doctor.h" cx="7" ccx="17" in="1" churn="46" amp="135" r="5">inline DoctorGrammarProbe doctorProbeGrammars()</d>
<d l="104" e="238" n="kLangTable" p="src/ingest_crawl.h" churn="87" amp="218" pure="1" r="6">constexpr std::array&lt;LangEntry, 58&gt; kLangTable =</d>
<d l="2247" e="2262" n="FileHealth" sc="FileHealth" p="src/model.h" churn="327" amp="539" r="7" mem="operator==">struct FileHealth</d>
<d l="308" e="343" n="SliceScan" sc="SliceScan" p="src/slice.h" churn="51" amp="102" r="8" mem="disclose">struct SliceScan</d>
<d l="138" e="152" n="ParsedFile::ParsedFile" p="src/forselfhook.h" cx="2" ccx="1" churn="8" amp="8" r="9">explicit ParsedFile( std::string bytes ) : m_bytes( std::move( bytes ) )</d>
<d l="135" e="177" n="ParsedFile" sc="ParsedFile" p="src/forselfhook.h" churn="8" amp="8" r="10" mem="operator=,usable,root,text">class ParsedFile</d>
<!-- demote: a <t> in sigs is a lower same-file sibling past answer row 10, a pointer (p= file, sym= name, r= rank), not the answer -->
<t p="src/ingest.h" sym="AstWalk" r="11"/>
<t p="src/ingest_sidecap.h" sym="astroFenceTailIsBlank" r="12"/>
<d l="386" e="459" n="sliceAtRev" sc="slicediff" p="src/slicediff.h" cx="14" ccx="15" in="1" churn="14" amp="76" r="13">inline RevSide sliceAtRev( const std::string&amp; root, const std::string&amp; sha, const std::string&amp; rel, const Symbol&amp; sym, SliceFam fam, const ::TSLanguage* grammar, st … [line truncated: 77 more bytes on this line]
<d l="2129" e="2158" n="collectGatedLocalNames" sc="rw" p="src/ingest_astquery.h" cx="6" ccx="5" in="1" churn="48" amp="156" r="14">std::vector&lt;LocalNameFact&gt; collectGatedLocalNames( std::string_view defBytes, std::uint32_t defStartLine, Lang lang )</d>
<t p="src/ingest.h" sym="kMaxKotlinStringNestDepth" r="15"/>
<d l="927" e="978" n="scanModule" sc="detail" p="src/jsrunner.h" cx="16" ccx="15" in="3" churn="22" amp="109" r="16">inline ModuleScan scanModule( std::string_view source, std::string_view path )</d>
<d l="255" e="259" n="hasPhantomScopeSeparator" p="src/ingest_names.h" cx="2" ccx="1" in="2" churn="71" amp="208" tested="1" r="17">inline bool hasPhantomScopeSeparator( TSNode qualified ) noexcept</d>
<d l="87" e="97" n="hasMainGuard" sc="rw::pythonrunner" p="src/pythonrunner.h" cx="2" ccx="2" in="1" churn="5" amp="14" r="18">inline bool hasMainGuard( std::string_view source )</d>
<t p="src/ingest_crawl.h" sym="jsonNestsTooDeep" r="19"/>
<t p="src/slice.h" sym="DisclosureWhy" r="20"/>
<t p="src/ingest.h" sym="kMaxYamlNestDepth" r="21"/>
<t p="src/ingest_astquery.h" sym="spanTiersOfFiles" r="22"/>
<t p="src/slice.h" sym="sliceScanDefinition" r="23"/>
… [243 more display lines; full output is 26232 bytes on 44 raw line(s)]
`````

## `./build/ripwire . --for="why does src/lexical.h chooseForRanker pick name-exact BM25"`

*Mention anchoring (default-on): a path and a Symbol literally named in the task get lifted; the header says what anchored.*

**wall time: 9.30s**

`````
<ctx task="why does src/lexical.h chooseForRanker pick name-exact BM25" route="subtoken+body" root="." confidence="low" margin_pct="0" at="0412539b9" mention_anchored="3" doc_mentions="4" schema="ripwire.for/v1" bundle="compact" bodies="0" reason="compact-route" budget_bytes="7500" doc_mentions_capp … [line truncated: 49 more bytes on this line]
<!-- ripwire for schema=ripwire.for/v1: bundle=/bodies=/reason= the body posture; d: cx= ccx= complexity, in= callers (absent cx/ccx/in = 0), churn= amp= change, clone= tested= 1, sc= scope, id=p::sc::n; total= shown= capped=1 if cut; task= the query; d pure=1 const/constexpr sig, next= the follow-up to paste; route= name-exact(X)|subtoken+body[:broad|:declined]; confidence=/margin_pct= head score drop (low=flat); h l= p= n=, c n= l= (joined for same-named callees, shown= counts them), noedge= no callee resolved; h qword= its name (case-folded, leading _#$@ dropped) equals that question word (by name, not resolved, not the only one), first, calls to 100 (capped=1 next= all); qword_cut= owners not so served, next= the first; fold kind=bodies: b t= n= p= l= top ranked rows' whole bodies, not the answer; served= of total= in budget_bytes=; slice/skip p= n= l=; skip bytes= next=; a skip makes sigs next= it, sigs_next= the signatures-only re-call; t p= file outside sigs (weaker), t sym= its top symbols not in sigs/syms (a pointer, not the answer), r= rank (gap = trimmed); t order: code files first, then doc files (a code question); t page rows go on to file-page row 160 (code question: 160 code rows, docs within row 160); past page 0 (code question: past 40 code rows, a doc past row 40) listed last, head files skipped; past 120 of those p= only, p_only= counts them; t folded=class=N: N p= only rows of that class (doc|config|script|testdata|other) not listed, next= pages to them; d layer=: built-in arch layer (game|infra|render|math|audio|ai|test) from a dir name in p=; d e= its last line (absent=unknown, never 0; l= the name's line); c prov=split: a resolver split arm; may be another arm's (NOT a claim the edge is false) [mention anchor: 1 file + 2 symbols; mention_anchored=] [doc mentions: 4 docs, 2 symbols; doc_mentions=] -->
<!-- root= is the crawl root; p= below is RELATIVE to it (single-root only; absent => p= is ingest's own path, unchanged); at=this commit(+dirty). [budget_bytes= is the default BYTE target this ranked payload was shaped toward: row text shortens toward it, no row of the ranked head is removed for it (sigs past_target=)] [sigs capped=1 with shown=total: rows shrunk, none dropped] [sigs past_target=K: the last K rows are past the budget_bytes target, served because they are rows of the ranked head; none is cut] [sigs next=: one call serving all total= rows uncut] [docs_dropped=N: N shown rows have a doc comment not printed (r>24 always, r5..24 if capped)] [docs_after_code=N: N doc rows of the shown set moved below its code rows; same rows, reordered, none added or removed; a question naming docs keeps score order] [cut: doc_mentions_capped="1" doc_mentions_total="7" — an indexing cap dropped content not shown here]; lego/compose collapse to a counted stub by default (a disclosed cut): total= that section's own pre-cap row count, shown="0" capped="1" (nothing rendered here), next= names the sections=lego,compose flag that restores both sections byte-identically in one call est_tokens= prices this bundle in tokens -->
<sigs shown="40" total="40" capped="1" past_target="13" docs_dropped="28" docs_after_code="2" next="--for=&apos;why does src/lexical.h chooseForRanker pick name-exact BM25&apos; --signatures-only --token-budget=6400">
<d l="1880" e="1886" n="lexicalScoresNameExactRanked" sc="rw" p="src/lexical.h" cx="1" in="4" churn="85" amp="145" r="1" next="--expand=src/lexical.h:lexicalScoresNameExactRanked">
<doc>The name-exact ranker AS THE RETRIEVAL LENS SERVES IT: whole-name BM25 plus the definition-over-…</doc>inline std::vector&lt;float&gt; lexicalScoresNameExactRanked( const IngestResult&amp; ing, std::string_view query, const std::vector&lt;float&gt;* symbolScoreMul )</d>
<d l="158" e="169" n="printEvalRankerNote" sc="rw" p="src/eval.h" cx="1" in="1" churn="18" amp="52" r="2">
<doc>P11.12: the interpretive footer for --eval&apos;s ranker table, pulled into its own function so the 9…</doc>inline void printEvalRankerNote()</d>
<d l="152" e="152" n="kWeakLexicalScoreThreshold" sc="rw" p="src/lexical.h" churn="85" amp="141" pure="1" r="3">
<doc>calling agent knows to reformulate rather than trust the ranking. Calibrated empirically (2026-0…</doc>inline constexpr float kWeakLexicalScoreThreshold = 1.0f</d>
<d l="2638" e="2747" n="chooseForRanker" sc="rw" p="src/lexical.h" cx="18" ccx="23" in="6" churn="85" amp="147" r="4">inline RouteChoice chooseForRanker( const IngestResult&amp; ing, std::string_view query )</d>
<d l="716" e="795" n="runEvalRetrieval" sc="rw" p="src/eval.h" cx="7" ccx="10" in="1" churn="18" amp="52" r="5">inline int runEvalRetrieval( const IngestResult&amp; ing, const Graph&amp; g )</d>
<d l="751" e="797" n="chooseSubjectRouteUnchecked" sc="rw" p="src/subjectanchor.h" cx="17" ccx="16" in="1" churn="33" amp="22" r="6">inline SubjectRoute chooseSubjectRouteUnchecked( const IngestResult&amp; ing, const Graph&amp; g, std::string_view task, bool servesBodiesAndCallers )</d>
<d l="6886" e="6899" n="candidatesRootTag" sc="rw" p="src/serialize.h" cx="5" ccx="4" in="1" churn="486" amp="578" r="7">inline std::string candidatesRootTag( std::size_t keep, std::size_t corpusCount, const CandidateProvenance&amp; prov )</d>
<d l="1576" e="1736" n="lexicalScoresNameExactTiered" sc="rw" p="src/lexical.h" cx="40" ccx="68" in="2" churn="85" amp="143" r="8">inline std::vector&lt;float&gt; lexicalScoresNameExactTiered( const IngestResult&amp; ing, std::string_view query, const std::vector&lt;float&gt;* symbolScoreMul )</d>
<d l="1091" e="1108" n="chooseSubjectRoute" sc="rw" p="src/subjectanchor.h" cx="6" ccx="5" in="3" churn="33" amp="24" r="9">inline SubjectRoute chooseSubjectRoute( const IngestResult&amp; ing, const Graph&amp; g, std::string_view task, bool servesBodiesAndCallers )</d>
<d l="792" e="796" n="NameCorpusStats" sc="NameCorpusStats" p="src/naminglens.h" churn="19" amp="54" r="10">struct NameCorpusStats</d>
<d l="1047" e="1087" n="applyAnchorHonesty" sc="rw" p="src/subjectanchor.h" cx="12" ccx="17" in="1" churn="33" amp="22" r="11">inline std::vector&lt;SourceSyntaxAnchor&gt; applyAnchorHonesty( const IngestResult&amp; ing, std::string_view task, SubjectRoute&amp; out )</d>
<d l="1089" e="1190" n="runEvalMined" sc="rw" p="src/eval.h" cx="25" ccx="38" in="1" churn="18" amp="52" r="12">inline int runEvalMined( const std::string&amp; root, const IngestResult&amp; ing, const Graph&amp; g, const std::string&amp; path )</d>
<!-- demote: a <t> in sigs is a lower same-file sibling past answer row 10, a pointer (p= file, sym= name, r= rank), not the answer -->
<t p="src/subjectanchor.h" sym="routeAnchorFallThrough" r="13"/>
<d l="47" e="98" n="LensRanking" sc="LensRanking" p="src/packtask.h" churn="91" amp="210" r="14">struct LensRanking</d>
<d l="48" e="63" n="hasIdentifierShape" sc="namesplit" p="src/infra/namesplit.h" layer="infra" cx="8" ccx="7" in="5" churn="12" amp="45" r="15">inline bool hasIdentifierShape( std::string_view w ) noexcept</d>
<d l="687" e="972" n="runEvalSkills" sc="rw" p="src/skilleval.h" cx="56" ccx="97" in="1" churn="19" amp="75" r="16">inline int runEvalSkills( const std::string&amp; root, const IngestResult&amp; ing, const Graph&amp; g, const std::string&amp; labelsPath )</d>
<t p="src/lexical.h" sym="Bm25Params" r="17"/>
<t p="src/lexical.h" sym="bm25ImpactBound" r="18"/>
<d l="171" e="380" n="runEval" sc="rw" p="src/eval.h" cx="46" ccx="69" in="1" churn="18" amp="52" r="19">inline int runEval( const std::string&amp; root, const IngestResult&amp; ing, const Graph&amp; g, const std::vector&lt;char&gt;&amp; currentDiff )</d>
<d l="31" e="31" n="kLexWeightDoc" sc="rw" p="src/lexindex.h" churn="9" amp="13" pure="1" r="20">inline constexpr int kLexWeightDoc = 2</d>
<d l="351" e="365" n="hedgeOffTaskPick" sc="rw" p="src/exemplar.h" cx="5" ccx="3" in="1" churn="9" amp="20" r="21">inline void hedgeOffTaskPick( const IngestResult&amp; ing, ExemplarPick&amp; pick )</d>
<d l="1739" e="1742" n="lexicalScoresNameExact" sc="rw" p="src/lexical.h" cx="1" in="3" churn="85" amp="144" r="22">inline std::vector&lt;float&gt; lexicalScoresNameExact( const IngestResult&amp; ing, std::string_view query )</d>
… [271 more display lines; full output is 30767 bytes on 18 raw line(s)]
`````

## `./build/ripwire . --for="why does src/lexical.h chooseForRanker pick name-exact BM25" --no-mention-boost`

*Same task with the anchor disabled — the contrast the flag exists for.*

**wall time: 8.86s**

`````
<ctx task="why does src/lexical.h chooseForRanker pick name-exact BM25" route="subtoken+body" root="." confidence="low" margin_pct="0" at="0412539b9" doc_mentions="2" schema="ripwire.for/v1" bundle="compact" bodies="0" reason="compact-route" budget_bytes="7500" doc_mentions_capped="1" doc_mentions_t … [line truncated: 28 more bytes on this line]
<!-- ripwire for schema=ripwire.for/v1: bundle=/bodies=/reason= the body posture; d: cx= ccx= complexity, in= callers (absent cx/ccx/in = 0), churn= amp= change, clone= tested= 1, sc= scope, id=p::sc::n; total= shown= capped=1 if cut; task= the query; d pure=1 const/constexpr sig, next= the follow-up to paste; route= name-exact(X)|subtoken+body[:broad|:declined]; confidence=/margin_pct= head score drop (low=flat); h l= p= n=, c n= l= (joined for same-named callees, shown= counts them), noedge= no callee resolved; h qword= its name (case-folded, leading _#$@ dropped) equals that question word (by name, not resolved, not the only one), first, calls to 100 (capped=1 next= all); qword_cut= owners not so served, next= the first; fold kind=bodies: b t= n= p= l= top ranked rows' whole bodies, not the answer; served= of total= in budget_bytes=; slice/skip p= n= l=; skip bytes= next=; a skip makes sigs next= it, sigs_next= the signatures-only re-call; t p= file outside sigs (weaker), t sym= its top symbols not in sigs/syms (a pointer, not the answer), r= rank (gap = trimmed); t order: code files first, then doc files (a code question); t page rows go on to file-page row 160 (code question: 160 code rows, docs within row 160); past page 0 (code question: past 40 code rows, a doc past row 40) listed last, head files skipped; past 120 of those p= only, p_only= counts them; t folded=class=N: N p= only rows of that class (doc|config|script|testdata|other) not listed, next= pages to them; d layer=: built-in arch layer (game|infra|render|math|audio|ai|test) from a dir name in p=; d e= its last line (absent=unknown, never 0; l= the name's line); c prov=split: a resolver split arm; may be another arm's (NOT a claim the edge is false) [doc mentions: 2 docs, 1 symbol; doc_mentions=] -->
<!-- root= is the crawl root; p= below is RELATIVE to it (single-root only; absent => p= is ingest's own path, unchanged); at=this commit(+dirty). [budget_bytes= is the default BYTE target this ranked payload was shaped toward: row text shortens toward it, no row of the ranked head is removed for it (sigs past_target=)] [sigs capped=1 with shown=total: rows shrunk, none dropped] [sigs past_target=K: the last K rows are past the budget_bytes target, served because they are rows of the ranked head; none is cut] [sigs sigs_next=: one call serving all total= rows uncut] [docs_dropped=N: N shown rows have a doc comment not printed (r>24 always, r5..24 if capped)] [cut: doc_mentions_capped="1" doc_mentions_total="3" — an indexing cap dropped content not shown here]; lego/compose collapse to a counted stub by default (a disclosed cut): total= that section's own pre-cap row count, shown="0" capped="1" (nothing rendered here), next= names the sections=lego,compose flag that restores both sections byte-identically in one call est_tokens= prices this bundle in tokens -->
<sigs shown="40" total="40" capped="1" past_target="11" docs_dropped="30" sigs_next="--for=&apos;why does src/lexical.h chooseForRanker pick name-exact BM25&apos; --signatures-only --no-mention-boost --token-budget=6200" next="--expand=src/eval.h:716:runEvalRetrieval">
<d l="1880" e="1886" n="lexicalScoresNameExactRanked" sc="rw" p="src/lexical.h" cx="1" in="4" churn="85" amp="145" r="1" next="--expand=src/lexical.h:lexicalScoresNameExactRanked">
<doc>The name-exact ranker AS THE RETRIEVAL LENS SERVES IT: whole-name BM25 plus the definition-over-…</doc>inline std::vector&lt;float&gt; lexicalScoresNameExactRanked( const IngestResult&amp; ing, std::string_view query, const std::vector&lt;float&gt;* symbolScoreMul )</d>
<d l="158" e="169" n="printEvalRankerNote" sc="rw" p="src/eval.h" cx="1" in="1" churn="18" amp="52" r="2">
<doc>P11.12: the interpretive footer for --eval&apos;s ranker table, pulled into its own function so the 9…</doc>inline void printEvalRankerNote()</d>
<d l="716" e="795" n="runEvalRetrieval" sc="rw" p="src/eval.h" cx="7" ccx="10" in="1" churn="18" amp="52" r="3">inline int runEvalRetrieval( const IngestResult&amp; ing, const Graph&amp; g )</d>
<d l="751" e="797" n="chooseSubjectRouteUnchecked" sc="rw" p="src/subjectanchor.h" cx="17" ccx="16" in="1" churn="33" amp="22" r="4">
<doc>The route the subject reading picks, before the CONFIDENCE-ANCHOR check. `servesBodiesAndCallers…</doc>inline SubjectRoute chooseSubjectRouteUnchecked( const IngestResult&amp; ing, const Graph&amp; g, std::string_view task, bool servesBodiesAndCallers )</d>
<d l="152" e="152" n="kWeakLexicalScoreThreshold" sc="rw" p="src/lexical.h" churn="85" amp="141" pure="1" r="5">inline constexpr float kWeakLexicalScoreThreshold = 1.0f</d>
<d l="6886" e="6899" n="candidatesRootTag" sc="rw" p="src/serialize.h" cx="5" ccx="4" in="1" churn="486" amp="578" r="6">inline std::string candidatesRootTag( std::size_t keep, std::size_t corpusCount, const CandidateProvenance&amp; prov )</d>
<d l="1576" e="1736" n="lexicalScoresNameExactTiered" sc="rw" p="src/lexical.h" cx="40" ccx="68" in="2" churn="85" amp="143" r="7">inline std::vector&lt;float&gt; lexicalScoresNameExactTiered( const IngestResult&amp; ing, std::string_view query, const std::vector&lt;float&gt;* symbolScoreMul )</d>
<d l="1091" e="1108" n="chooseSubjectRoute" sc="rw" p="src/subjectanchor.h" cx="6" ccx="5" in="3" churn="33" amp="24" r="8">inline SubjectRoute chooseSubjectRoute( const IngestResult&amp; ing, const Graph&amp; g, std::string_view task, bool servesBodiesAndCallers )</d>
<d l="792" e="796" n="NameCorpusStats" sc="NameCorpusStats" p="src/naminglens.h" churn="19" amp="54" r="9">struct NameCorpusStats</d>
<d l="1047" e="1087" n="applyAnchorHonesty" sc="rw" p="src/subjectanchor.h" cx="12" ccx="17" in="1" churn="33" amp="22" r="10">inline std::vector&lt;SourceSyntaxAnchor&gt; applyAnchorHonesty( const IngestResult&amp; ing, std::string_view task, SubjectRoute&amp; out )</d>
<d l="1089" e="1190" n="runEvalMined" sc="rw" p="src/eval.h" cx="25" ccx="38" in="1" churn="18" amp="52" r="11">inline int runEvalMined( const std::string&amp; root, const IngestResult&amp; ing, const Graph&amp; g, const std::string&amp; path )</d>
<!-- demote: a <t> in sigs is a lower same-file sibling past answer row 10, a pointer (p= file, sym= name, r= rank), not the answer -->
<t p="src/subjectanchor.h" sym="routeAnchorFallThrough" r="12"/>
<d l="47" e="98" n="LensRanking" sc="LensRanking" p="src/packtask.h" churn="91" amp="210" r="13">struct LensRanking</d>
<d l="48" e="63" n="hasIdentifierShape" sc="namesplit" p="src/infra/namesplit.h" layer="infra" cx="8" ccx="7" in="5" churn="12" amp="45" r="14">inline bool hasIdentifierShape( std::string_view w ) noexcept</d>
<d l="687" e="972" n="runEvalSkills" sc="rw" p="src/skilleval.h" cx="56" ccx="97" in="1" churn="19" amp="75" r="15">inline int runEvalSkills( const std::string&amp; root, const IngestResult&amp; ing, const Graph&amp; g, const std::string&amp; labelsPath )</d>
<t p="src/lexical.h" sym="Bm25Params" r="16"/>
<t p="src/lexical.h" sym="bm25ImpactBound" r="17"/>
<d l="2638" e="2747" n="chooseForRanker" sc="rw" p="src/lexical.h" cx="18" ccx="23" in="6" churn="85" amp="147" r="18">inline RouteChoice chooseForRanker( const IngestResult&amp; ing, std::string_view query )</d>
<d l="171" e="380" n="runEval" sc="rw" p="src/eval.h" cx="46" ccx="69" in="1" churn="18" amp="52" r="19">inline int runEval( const std::string&amp; root, const IngestResult&amp; ing, const Graph&amp; g, const std::vector&lt;char&gt;&amp; currentDiff )</d>
<d l="31" e="31" n="kLexWeightDoc" sc="rw" p="src/lexindex.h" churn="9" amp="13" pure="1" r="20">inline constexpr int kLexWeightDoc = 2</d>
<d l="351" e="365" n="hedgeOffTaskPick" sc="rw" p="src/exemplar.h" cx="5" ccx="3" in="1" churn="9" amp="20" r="21">inline void hedgeOffTaskPick( const IngestResult&amp; ing, ExemplarPick&amp; pick )</d>
<d l="1739" e="1742" n="lexicalScoresNameExact" sc="rw" p="src/lexical.h" cx="1" in="3" churn="85" amp="144" r="22">inline std::vector&lt;float&gt; lexicalScoresNameExact( const IngestResult&amp; ing, std::string_view query )</d>
… [271 more display lines; full output is 30316 bytes on 18 raw line(s)]
`````

## `./build/ripwire . --lego=Vehicle`

*Interface -> implementors view: every existing impl of the named interface; the method contract is extracted for the C-family/Java/TS/Python tiers — for a Rust trait (this fixture) it discloses caveat="not-extracted-for-lang" rather than an empty list.*

**wall time: 2.28s**

`````
<ctx schema="ripwire.lego/v1" root=".">
<!-- ripwire lego schema=ripwire.lego/v1: ONE interface/base type: <iface n= p= defs= implementors=>, its <m> method contract, every implementor. counts_floor=1: every count is a FLOOR, never a total. graph_ambiguous=/graph_unresolved=: resolver gauge. graph_unindexed=N: N files no grammar could read (the map header's unindexed=); their calls raise neither gauge. root=: p= relative to it. methods=0 caveat=not-extracted-for-lang: no <m> contract read for this language. -->
<lego graph_ambiguous="3456" graph_unresolved="18664" graph_unindexed="286" counts_floor="1">
<iface n="Vehicle" p="test/legofix/vehicle.rs" methods="0" caveat="not-extracted-for-lang" defs="1" implementors="2">
<impl n="Car" p="test/legofix/vehicle.rs:12"/>
<impl n="Bike" p="test/legofix/vehicle.rs:13"/>
</iface>
</lego>
</ctx>
`````

## `./build/ripwire . --exemplar="format byte sizes for humans"`

*The repo's best-in-class instance to imitate before writing new code (picked by ROLE).*

**wall time: 2.90s**

`````
<!-- ripwire exemplar schema=ripwire.exemplar/v1: the best-in-class instance of kind= for the task, chosen by role: n= p= in= ccx= tested=, <bodies>
<b> to imitate. window: shown= total= capped= (capped=1 cut). root=: p= relative to it. candidates=N: instances of kind= under the ccx ceiling the pick was ranked from. low_confidence=1: weak task-to-kind match, fell back to fn unless off_task=1; pass a kind (fn|method|class...). -->
<exemplar schema="ripwire.exemplar/v1" kind="fn" candidates="19064" n="kindIs" p="src/infra/nodekind.h:46" in="390" ccx="3" root="." tested="1" low_confidence="1">
<bodies shown="1" total="1" capped="0">
<b t="fn" l="46" p="src/infra/nodekind.h" n="kindIs">
<![CDATA[inline bool kindIs( const char* t, const char ( &lit )[N] ) noexcept
{
    for( std::size_t i = 0; i < N; ++i )   // N includes lit's NUL — comparing it is what makes this equality, not a prefix test
    {
        if( t[i] != lit[i] )
        {
            return false;
        }
    }
    return true;
}]]></b></bodies></exemplar>
`````

## `./build/ripwire . --help-task="calls(runDefaultMap, rankGraphTeleport)"`

*Deterministic enhanced help: a closed claim in the task is a structured shape, so the router recommends the ONE command that answers it (--verify) with the evidence behind the pick. Advice only — nothing executes.*

**wall time: 3.80s**

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

**wall time: 6.61s**

`````
<!-- ripwire help-task schema=ripwire.help-task/v1: which verb answers this task: status=recommend|abstain confidence= score= margin=, <facts> the evidence. next=: the one pasteable follow-up. git=/dirty=: the root is a git repo / its tree differs from HEAD (the stamp's +dirty). trace=1: the task text has a stack/sanitizer trace shape; it routes to from-trace. resolved_symbols=N: indexed names the task NAMES; a bare short/common word needs backticks or F(). -->
<task-route schema="ripwire.help-task/v1" status="abstain" confidence="none" score="0" margin="0" next="--for=&apos;write a cheerful release announcement&apos;">
<facts git="1" dirty="0" trace="0" resolved_symbols="0"/>
</task-route>
`````

## `./build/ripwire . --recall="quality delta gating exit codes"`

*Most relevant DOCS' full bodies (markdown only) — recall what is already written down.*

**wall time: 2.58s**

`````
ripwire recall — "quality delta gating exit codes" — 118 relevant of 273 document files, best-first — total=118 shown=6 capped=1 truncated=6 generated_demoted=2 generated_demoted_paths="docs/TUNING.md,docs/LIMITS.md" max_tokens=8000 share_bytes=2628 est_tokens=4635

━━ README.md  (relevance 22.122) ━━  [sections: 2 of 25 selected (62 in doc), section-granular; whole doc 235701 B; lines="2772-2784,2785-2792"; dropped_by_budget=23]
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



━━ CHANGELOG.md  (relevance 21.022) ━━  [sections: 1 of 129 selected (611 in doc), section-granular; whole doc 1298822 B; lines="2552-2575"; dropped_by_budget=128]  [truncated: 2431 of 3826 bytes]
### Changed — `--quality-delta=A..B` answers the kinds it can under memory pressure, and exits 6 when that answer has no gating row (#387 follow-up)

A tripped memory guard in the range form used to give exit 5 and nothing, so on a large repository a four-file change
… [101 more lines, 11826 bytes total]
`````

stderr:

`````
ripwire: redacted 1 secret from emitted context (keyword-gated-secret=1) — pass --no-redact to disable
`````

## `./build/ripwire <scratch>/aux/kbcorpus --recall="field affinity cache line data layout which fields are read together" --top-k=3 --max-tokens=1200`

*The directory-as-knowledge-base pattern: --recall pointed at a 1319937-byte scratch dir of DUMPED TOOL OUTPUT (a git log, this repo's own generated command reference, --help text, an architecture doc, a fabricated JSON access log) instead of a source repo — no index to build, no daemon.*

**wall time: 1.03s**

`````
ripwire recall — "field affinity cache line data layout which fields are read together" — 2 relevant of 2 document files, best-first — total=2 shown=1 capped=1 truncated=1 max_tokens=1200 share_bytes=2040 est_tokens=957

━━ commands.md  (relevance 33.722) ━━  [sections: 1 of 165 selected (194 in doc), section-granular; whole doc 615362 B; lines="3892-3896"; dropped_by_budget=164]  [truncated: 1865 of 7753 bytes]
### `--field-affinity[=STRUCT]`

**Answers:** find fields that are read together but declared far apart — the cache-locality lens the CACHE-LOCALITY lens: which fields are READ TOGETHER but declared FAR APART.

Builds a static field CO-ACCESS affinity graph (one observation per indexed C-family function body) and diffs it against the DECLARED field order and 64-byte cache-line geometry, reusing --layout's LP64 offset model. Bare = every aggregate in the repo, ranked by separation cost; =STRUCT narrows the  … [line truncated: 1355 more bytes on this line]

(capped: 1 of 2 relevant document files omitted — raise --max-tokens/budget_tokens or narrow the query for 1 more (~2548-byte budget))
`````

stderr:

`````
ripwire: redacted 1 secret from emitted context (keyword-gated-secret=1) — pass --no-redact to disable
`````

## `./build/ripwire . --tree`

*File-by-file orientation map (top symbols per file).*

**wall time: 3.66s**

`````
<!-- ripwire tree schema=ripwire.tree/v1: each file with its top 3 symbols by rank, files by best symbol: <file p= symbols=> of <s t= n=>; of files= indexed, files_unlisted= have none. window: shown= total= capped= has_more= next_offset= offset= limit= (capped=1 cut; next_offset= pastes as offset=). symbols_capped=: 1 = cut. root=: p= relative to it. pr_iters=N: PageRank iterations. shown_symbols=: <s> rows printed. next=: the one pasteable follow-up. -->
<tree schema="ripwire.tree/v1" files="4497" files_unlisted="107" shown="80" capped="1" total="4390" has_more="1" next_offset="80" offset="0" limit="0" pr_iters="38" root="." shown_symbols="233" symbols_capped="1" next="--tree --offset=80">
<file p="src/infra/nodekind.h" symbols="1">
<s t="fn" n="kindIs"/>
</file>
<file p="src/ingest_metrics.h" symbols="60">
<s t="fn" n="nodeTextOf"/>
<s t="fn" n="nodeFieldText"/>
<s t="struct" n="CtrlKind"/>
</file>
<file p="src/model.h" symbols="236">
<s t="fn" n="relForHash"/>
<s t="fn" n="rootRelPath"/>
<s t="fn" n="isStructOrNamedType"/>
</file>
<file p="src/infra/Diagnostics.h" symbols="101">
<s t="macro" n="ASSUME"/>
<s t="macro" n="RW_ASSUME_"/>
<s t="macro" n="RW_ASSUME_"/>
</file>
<file p="src/infra/namesplit.h" symbols="11">
<s t="fn" n="isIdentChar"/>
<s t="fn" n="afterLast"/>
<s t="fn" n="stripQuotePair"/>
</file>
<file p="src/infra/diagnostics.cpp" symbols="15">
<s t="method" n="handleAssert"/>
<s t="fn" n="orEmpty"/>
<s t="fn" n="writeNotice"/>
</file>
… [366 more display lines; full output is 11103 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --html=<scratch>/aux/map2.html`

*Self-contained HTML force-directed call graph.*

**wall time: 11.90s**

`````
(empty)
`````

Artifact written:

`````
  155499 <scratch>/aux/map2.html
`````

## `./build/ripwire . --order=stable --top-k=5`

*Stable (path/id) emit order — provider KV-cache hits across re-runs.*

**wall time: 2.41s**

`````
<!-- ripwire map schema=ripwire.map/v1: ranked symbol map: <f p= layer=> groups <s t= n= sc= k= amb=> rows (k= rank), <c n=> resolved callees; the header comment is data. est_tokens=: price as emitted (an upper bound under compact). root=: p= relative to it. pr_iters=N: PageRank iterations. <inv listed= unlisted=>: files the ranked rows show / do not (sum = files=), each named or counted below. <entry p= n=>: a program entry by its language's convention (C/Go/Rust main, Java/C# static main, a script main its module scope calls, __main__.py), callees as c rows; manifest entries not read. <ls p= n= f=>: n= unshown files under dir p=; f= names its code files, the rest (tests, docs, config, test/doc/example dirs) counted. declined=K: K call sites without edges, including inert Elixir quote sites after unquote/unquote_splicing re-entry. external=K: K calls proven outside the tree, no edge. locality_pinned=K: K calls pinned by locality alone (a guess). extent_suspect_syms=K: K defs failed containment, corpus-wide. macro_blanked_files=K: K files indexed from a macro-blanked re-parse. prov=scip|binding|import|split|final-segment: how that <c> edge bound (absent: one unique name); split = one arm of an amb= pick; final-segment = a qualified type matched by last name only. files=/symbols=: files and symbols indexed; edges= distinct call edges; shown= symbols printed, a merged row counting each def; ambiguous= calls split over several defs, corpus-wide; unresolved= calls with in-tree evidence and no edge (every def language-filtered or unreachable, or binding refused); order= rows by rank (important-first, important-last; (auto:fill) = flipped past a size threshold) or by path (stable). skipped_oversize=K: K files over a size ceiling, not indexed. unindexed=ext:N: N text files of that extension no grammar reads (6 extensions at most). unindexed_exts=E: E such extensions in all, the list cut. lens=: attributes another form of this answer serves, withheld here. sc=: enclosing scope; the full id is p::sc::n (p= of the row or its <f>) and selectors take it. amb=K: K calls split over several defs. -->
<!-- t=modscope=a-file's-MODULE-SCOPE(n=<file-scope>):the-statements-outside-every-named-definition,where-a-top-level-call-and-an-anonymous-callback-body's-calls-live;a-CALLER-never-a-callee(nothing-in-the-source-can-name-it)-with-no-body-to-expand;a-file-with-no-such-call-has-no-such-row -->
<!-- t=type|alias|functype=a-Go-named-type-by-its-written-form:type=a-defined-type-whose-WRITTEN-form-is-not-a-struct/iface/func-literal(type-N-string;type-W-Pair-too,whatever-Pair-is-underneath),alias=type-A=B,functype=type-F-func(...) -->
<!-- t=alias|functype-in-C++-and-.h:alias=using-X=Y(also-templated-or-class-scope)or-namespace-L=lib(defs=X-prints-its-written-target-as-to=),functype=a-typedef-of-a-function-or-function-pointer-type(typedef-void(*F)(int));other-typedefs-read-t=struct -->
<r schema="ripwire.map/v1" root="." pr_iters="38" lens="k,est_tokens">
<f p="src/infra/Diagnostics.h" layer="infra">
<s t="macro" n="ASSUME" amb="1">
<c n="RW_ASSUME_" prov="split"/>
<c n="RW_ASSUME_" prov="split"/>
</s>
</f>
<f p="src/infra/nodekind.h" layer="infra">
<s t="fn" n="kindIs" sc="rw">
</s>
</f>
<f p="src/ingest_metrics.h">
<s t="fn" n="nodeTextOf">
</s>
</f>
<f p="src/model.h">
<s t="fn" n="relForHash" sc="rw">
</s>
<s t="fn" n="rootRelPath" sc="rw">
<c n="relForHash"/>
</s>
</f>
<inv listed="4" unlisted="4493">
<entry p="scripts/changelog_assemble.py" n="main">
<c n="repoRoot"/>
<c n="fragmentNames"/>
… [93 more display lines; full output is 10022 bytes on 1 raw line(s)]
`````


---

# navigate / answer a question

## `./build/ripwire . --around=rankGraphTeleport`

*Ego graph around one symbol — depth 1 BY DEFAULT now (the root's depth= says so): ~6 KB where the 2-hop neighbourhood is ~64 KB on this repo.*

**wall time: 1.80s**

`````
<!-- ripwire around schema=ripwire.around/v1: call neighbourhood of of=: depth= hops, fanout= kept per hop; absent rows lie outside that boundary. est_tokens=: price as emitted (an upper bound under compact). root=: p= relative to it. declined=K: K call sites without edges, including inert Elixir quote sites after unquote/unquote_splicing re-entry. external=K: K calls proven outside the tree, no edge. locality_pinned=K: K calls pinned by locality alone (a guess). extent_suspect_syms=K: K defs failed containment, corpus-wide. macro_blanked_files=K: K files indexed from a macro-blanked re-parse. overloads=N: N same-name defs merged in this row; shown= counts each. prov=scip|binding|import|split|final-segment: how that <c> edge bound (absent: one unique name); split = one arm of an amb= pick; final-segment = a qualified type matched by last name only. files=/symbols=: files and symbols indexed; edges= distinct call edges; shown= symbols printed, a merged row counting each def; ambiguous= calls split over several defs, corpus-wide; unresolved= calls with in-tree evidence and no edge (every def language-filtered or unreachable, or binding refused); order= rows by rank (important-first, important-last; (auto:fill) = flipped past a size threshold) or by path (stable). skipped_oversize=K: K files over a size ceiling, not indexed. unindexed=ext:N: N text files of that extension no grammar reads (6 extensions at most). unindexed_exts=E: E such extensions in all, the list cut. <c via="name">: that callee matched by name alone (receiver unproven); it does NOT mean the edge is false. <c x=N>: N same-named via=name rows merged; callees=FILE:SYM lists all. sc=: enclosing scope; the full id is p::sc::n (p= of the row or its <f>) and selectors take it. amb=K: K calls split over several defs. layer=: built-in arch layer (game|infra|render|math|audio|ai|test) from a dir name in p=; absent if none. -->
<!-- t=modscope=a-file's-MODULE-SCOPE(n=<file-scope>):the-statements-outside-every-named-definition,where-a-top-level-call-and-an-anonymous-callback-body's-calls-live;a-CALLER-never-a-callee(nothing-in-the-source-can-name-it)-with-no-body-to-expand;a-file-with-no-such-call-has-no-such-row -->
<!-- t=type|alias|functype=a-Go-named-type-by-its-written-form:type=a-defined-type-whose-WRITTEN-form-is-not-a-struct/iface/func-literal(type-N-string;type-W-Pair-too,whatever-Pair-is-underneath),alias=type-A=B,functype=type-F-func(...) -->
<!-- t=alias|functype-in-C++-and-.h:alias=using-X=Y(also-templated-or-class-scope)or-namespace-L=lib(defs=X-prints-its-written-target-as-to=),functype=a-typedef-of-a-function-or-function-pointer-type(typedef-void(*F)(int));other-typedefs-read-t=struct -->
<!-- a bound BIT this walk, so raising it would return more: depth_truncated=1 means at least one symbol one hop past depth= is absent; fanout_cut=N means N distinct symbols were dropped by the fanout= cap and appear NOWHERE here (exact, not a floor: a neighbour another hub re-admitted is not counted). Neither attribute is emitted when its bound cut nothing, so absent means that bound did not bind and raising it returns nothing new. The knobs are around-depth=N and around-fanout=K. -->
<!-- files=4497 symbols=39562 edges=38970 shown=12 est_tokens=3394 ambiguous=3456 unresolved=18664 locality_pinned=11 external=11109 declined=41448 extent_suspect_syms=12 macro_blanked_files=7 skipped_oversize=15 unindexed="txt:81,tsv:53,mod:33,jsonl:26,scm:25,expected:15" unindexed_exts=23 order=important-first -->
<r schema="ripwire.around/v1" root="." of="rankGraphTeleport" depth="1" fanout="32" depth_truncated="1" est_tokens="3394">
<f p="src/graph.h">
<s t="fn" n="rankGraphTeleport" sc="rw" amb="1" k="1.0000">
<c n="biasPrior"/>
<c n="PROFILE_SCOPE_DESCRIBE" prov="split"/>
<c n="PROFILE_SCOPE_DESCRIBE" prov="split"/>
<c n="pageRankDouble"/>
</s>
<s t="fn" n="biasPrior" sc="rw" k="0.5000">
<c n="ASSUME_NO_ALIAS_BUF"/>
</s>
<s t="fn" n="rankGraph" sc="rw" k="0.5000">
<c n="rankGraphTeleport"/>
</s>
<s t="fn" n="anchoredLexicalRank" sc="rw" k="0.5000">
<c n="localityKeyAt"/>
<c n="rankGraphTeleport"/>
<c n="blendMaxNorm"/>
<c n="ASSUME"/>
<c n="NodeId"/>
</s>
</f>
<f p="src/eval.h">
<s t="fn" n="runEval" sc="rw" amb="5" k="0.5000">
… [170 more display lines; full output is 8398 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --around=rankGraphTeleport --around-depth=2`

*The restoring knob: --around-depth=2 brings back the whole 2-hop neighbourhood (depth="2" on the root) — pay for it only when the 1-hop view was not enough.*

**wall time: 2.13s**

`````
<ctx schema="ripwire.pack-signatures/v1">
<!-- ripwire pack-signatures schema=ripwire.pack-signatures/v1: the ranked map plus <sigs>
<d l= n= sc= pure=> signature rows. est_tokens=: price as emitted (an upper bound under compact). root=: p= relative to it. declined=K: K call sites without edges, including inert Elixir quote sites after unquote/unquote_splicing re-entry. external=K: K calls proven outside the tree, no edge. locali … [line truncated: 1504 more bytes on this line]
<!-- t=modscope=a-file's-MODULE-SCOPE(n=<file-scope>):the-statements-outside-every-named-definition,where-a-top-level-call-and-an-anonymous-callback-body's-calls-live;a-CALLER-never-a-callee(nothing-in-the-source-can-name-it)-with-no-body-to-expand;a-file-with-no-such-call-has-no-such-row -->
<!-- t=type|alias|functype=a-Go-named-type-by-its-written-form:type=a-defined-type-whose-WRITTEN-form-is-not-a-struct/iface/func-literal(type-N-string;type-W-Pair-too,whatever-Pair-is-underneath),alias=type-A=B,functype=type-F-func(...) -->
<!-- t=alias|functype-in-C++-and-.h:alias=using-X=Y(also-templated-or-class-scope)or-namespace-L=lib(defs=X-prints-its-written-target-as-to=),functype=a-typedef-of-a-function-or-function-pointer-type(typedef-void(*F)(int));other-typedefs-read-t=struct -->
<!-- a bound BIT this walk, so raising it would return more: depth_truncated=1 means at least one symbol one hop past depth= is absent; fanout_cut=N means N distinct symbols were dropped by the fanout= cap and appear NOWHERE here (exact, not a floor: a neighbour another hub re-admitted is not counted). Neither attribute is emitted when its bound cut nothing, so absent means that bound did not bind and raising it returns nothing new. The knobs are around-depth=N and around-fanout=K. -->
<!-- files=4497 symbols=39562 edges=38970 shown=158 est_tokens=28555 ambiguous=3456 unresolved=18664 locality_pinned=11 external=11109 declined=41448 extent_suspect_syms=12 macro_blanked_files=7 skipped_oversize=15 unindexed="txt:81,tsv:53,mod:33,jsonl:26,scm:25,expected:15" unindexed_exts=23 order=important-first -->
<r root="." of="rankGraphTeleport" depth="2" fanout="32" depth_truncated="1" fanout_cut="99" est_tokens="29164">
<f p="src/graph.h">
<s t="fn" n="rankGraphTeleport" sc="rw" amb="1" k="1.0000">
<c n="biasPrior"/>
<c n="PROFILE_SCOPE_DESCRIBE" prov="split"/>
<c n="PROFILE_SCOPE_DESCRIBE" prov="split"/>
<c n="pageRankDouble"/>
</s>
<s t="fn" n="biasPrior" sc="rw" k="0.5000">
<c n="ASSUME_NO_ALIAS_BUF"/>
</s>
<s t="fn" n="rankGraph" sc="rw" k="0.5000">
<c n="rankGraphTeleport"/>
</s>
<s t="fn" n="anchoredLexicalRank" sc="rw" k="0.5000">
<c n="localityKeyAt"/>
<c n="rankGraphTeleport"/>
<c n="blendMaxNorm"/>
<c n="ASSUME"/>
<c n="NodeId"/>
</s>
<s t="method" n="localityKeyAt" sc="Graph" k="0.3333">
… [2345 more display lines; full output is 70835 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --around=rankGraphTeleport --around-fanout=4`

*The other knob: --around-fanout=4 keeps only the 4 strongest edges per node (default 32) — the same 1-hop depth, a quarter of the rows.*

**wall time: 2.33s**

`````
<!-- ripwire around schema=ripwire.around/v1: call neighbourhood of of=: depth= hops, fanout= kept per hop; absent rows lie outside that boundary. est_tokens=: price as emitted (an upper bound under compact). root=: p= relative to it. declined=K: K call sites without edges, including inert Elixir quote sites after unquote/unquote_splicing re-entry. external=K: K calls proven outside the tree, no edge. locality_pinned=K: K calls pinned by locality alone (a guess). extent_suspect_syms=K: K defs failed containment, corpus-wide. macro_blanked_files=K: K files indexed from a macro-blanked re-parse. prov=scip|binding|import|split|final-segment: how that <c> edge bound (absent: one unique name); split = one arm of an amb= pick; final-segment = a qualified type matched by last name only. files=/symbols=: files and symbols indexed; edges= distinct call edges; shown= symbols printed, a merged row counting each def; ambiguous= calls split over several defs, corpus-wide; unresolved= calls with in-tree evidence and no edge (every def language-filtered or unreachable, or binding refused); order= rows by rank (important-first, important-last; (auto:fill) = flipped past a size threshold) or by path (stable). skipped_oversize=K: K files over a size ceiling, not indexed. unindexed=ext:N: N text files of that extension no grammar reads (6 extensions at most). unindexed_exts=E: E such extensions in all, the list cut. sc=: enclosing scope; the full id is p::sc::n (p= of the row or its <f>) and selectors take it. amb=K: K calls split over several defs. -->
<!-- t=modscope=a-file's-MODULE-SCOPE(n=<file-scope>):the-statements-outside-every-named-definition,where-a-top-level-call-and-an-anonymous-callback-body's-calls-live;a-CALLER-never-a-callee(nothing-in-the-source-can-name-it)-with-no-body-to-expand;a-file-with-no-such-call-has-no-such-row -->
<!-- t=type|alias|functype=a-Go-named-type-by-its-written-form:type=a-defined-type-whose-WRITTEN-form-is-not-a-struct/iface/func-literal(type-N-string;type-W-Pair-too,whatever-Pair-is-underneath),alias=type-A=B,functype=type-F-func(...) -->
<!-- t=alias|functype-in-C++-and-.h:alias=using-X=Y(also-templated-or-class-scope)or-namespace-L=lib(defs=X-prints-its-written-target-as-to=),functype=a-typedef-of-a-function-or-function-pointer-type(typedef-void(*F)(int));other-typedefs-read-t=struct -->
<!-- a bound BIT this walk, so raising it would return more: depth_truncated=1 means at least one symbol one hop past depth= is absent; fanout_cut=N means N distinct symbols were dropped by the fanout= cap and appear NOWHERE here (exact, not a floor: a neighbour another hub re-admitted is not counted). Neither attribute is emitted when its bound cut nothing, so absent means that bound did not bind and raising it returns nothing new. The knobs are around-depth=N and around-fanout=K. -->
<!-- files=4497 symbols=39562 edges=38970 shown=5 est_tokens=1693 ambiguous=3456 unresolved=18664 locality_pinned=11 external=11109 declined=41448 extent_suspect_syms=12 macro_blanked_files=7 skipped_oversize=15 unindexed="txt:81,tsv:53,mod:33,jsonl:26,scm:25,expected:15" unindexed_exts=23 order=important-first -->
<r schema="ripwire.around/v1" root="." of="rankGraphTeleport" depth="1" fanout="4" depth_truncated="1" fanout_cut="7" est_tokens="1693">
<f p="src/graph.h">
<s t="fn" n="rankGraphTeleport" sc="rw" amb="1" k="1.0000">
<c n="biasPrior"/>
<c n="PROFILE_SCOPE_DESCRIBE" prov="split"/>
<c n="PROFILE_SCOPE_DESCRIBE" prov="split"/>
<c n="pageRankDouble"/>
</s>
<s t="fn" n="biasPrior" sc="rw" k="0.5000">
<c n="ASSUME_NO_ALIAS_BUF"/>
</s>
<s t="fn" n="rankGraph" sc="rw" k="0.5000">
<c n="rankGraphTeleport"/>
</s>
<s t="fn" n="anchoredLexicalRank" sc="rw" k="0.5000">
<c n="localityKeyAt"/>
<c n="rankGraphTeleport"/>
<c n="blendMaxNorm"/>
<c n="ASSUME"/>
<c n="NodeId"/>
</s>
</f>
<f p="src/main.cpp">
<s t="fn" n="churnRankedGraph" k="0.5000">
… [14 more display lines; full output is 4187 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --callers=rankGraphTeleport`

*Who calls SYM (1-hop in-edges).*

**wall time: 3.29s**

`````
<!-- ripwire callers schema=ripwire.callers/v1: 1-hop CALLERS of of= (defs= matched, count= distinct symbols): <s t= n= p=>; hop_tested=/hop_untested=. counts_floor=1: every count is a FLOOR, never a total. graph_ambiguous=/graph_unresolved=: resolver gauge. graph_unindexed=N: N files no grammar could read (the map header's unindexed=); their calls raise neither gauge. root=: p= relative to it. <s sites_at=>: its calls of the leaf name, any receiver, as file:line (p= is its def line); not proof each binds. next=: the one pasteable follow-up. -->
<callers schema="ripwire.callers/v1" of="rankGraphTeleport" defs="1" count="7" root="." hop_tested="0" hop_untested="7" graph_ambiguous="3456" graph_unresolved="18664" graph_unindexed="286" counts_floor="1" next="--uses=rankGraphTeleport">
<s t="fn" n="getIndex" p="src/mcpindex.h:1211" sites_at="src/mcpindex.h:1323"/>
<s t="fn" n="rankGraph" p="src/graph.h:13674" sites_at="src/graph.h:13678"/>
<s t="fn" n="anchoredLexicalRank" p="src/graph.h:14321" sites_at="src/graph.h:14372"/>
<s t="fn" n="runEval" p="src/eval.h:171" sites_at="src/eval.h:328"/>
<s t="fn" n="churnDecayRanking" p="src/main.cpp:1433" sites_at="src/main.cpp:1447"/>
<s t="fn" n="churnRankedGraph" p="src/main.cpp:1472" sites_at="src/main.cpp:1486 src/main.cpp:1487 src/main.cpp:1501"/>
<s t="fn" n="runDefaultMap" p="src/main.cpp:1759" sites_at="src/main.cpp:1879"/>
</callers>
`````

## `./build/ripwire . --callers=rankGraphTeleport --legend=full`

*The same rows under --legend=full: the default is the compact dialect (one compact comment plus schema="ripwire.callers/v1" on the root), and --legend=full restores the prose legend — every row byte and every completeness attribute (counts_floor=, graph_ambiguous=, next=) identical, ~3 KB more legend. Works on EVERY XML verb.*

**wall time: 2.81s**

`````
<!-- ripwire callers/callees: the 1-hop call hierarchy read off the call graph — the callers form lists symbols that CALL of=; the callees form lists symbols of= itself calls. of= is the selector you passed, defs= how many DEFINITIONS it resolved to (rows UNION every def's neighbours), count= the DISTINCT neighbour symbols (a floor, per counts_floor=), windowed by limit= and offset=. A neighbour that is an indexed function-like #define is a macro row (t="macro", role="macro" on the XML row): the edge crosses a macro expansion, not a plain call — rows carry no role= otherwise. Rows are ordered SOURCE first, then test/bench, then docs; within a tier callers rank by each row's own caller count (most-called first); callees keep path order. hop_tested=/hop_untested= partition count= by the tested= lens below (1-hop, never transitive). tested="1" on a row means an indexed test transitively reaches it (never 0, omitted when it does not). BLIND SPOT the test-gate legend also names: only a CALL EDGE from an INDEXED test symbol counts here, so a shell or CLI-level test running a built binary as a SUBPROCESS is invisible to it and a repo tested that way reads all-untested. Read untested= as no in-process test reaches it, not as no test covers it. next= is the one pasteable follow-up (the uses verb on this selector: the call sites). sites_at= on a caller row: its calls of the called LEAF name, any receiver or qualifier, as file:line tokens (space-separated, ascending; two calls on one line are one site); p= stays where the caller is DEFINED. Matched by name like the uses verb's call rows, so not proof each binds here; absent when no call there is spelled like it (an aliased import). counts_floor="1" means every count here is a FLOOR, never a total: edges are extracted from source TEXT by NAME. Missing: dynamic dispatch (virtual/interface/duck-typed), a most-vexing-parse declaration with no call expression, a function-pointer/callback bound to more than one function in scope (reassigned, table-indexed, lambda-bound, or address-taken/reference-bound), and a plain-name binding (fp=handler) whose variable type is not PROVABLY a function pointer (a same-file typedef/declarator; a HEADER typedef is missed; auto/template types are read as unpinned, so KEPT). A macro-generated call site is role="macro" only when its name uniquely names an indexed function-like #define (C-family, t="macro"); a shared name stays a plain call, an unindexed macro is no edge. Read a zero as "none found", never as "none exists". graph_ambiguous=/graph_unresolved= are the whole graph's resolver gauge (calls split over several defs / calls whose in-repo defs were all language-filtered), the map header's ambiguous=/unresolved=. graph_unindexed=N is a third gauge: files no grammar could read (the map header's unindexed=), whose calls raise neither gauge above; absent when zero, and so is this sentence. COUNTING UNIT differs by verb: callers, callees, edit-check, graph-query and pr-context counts are DISTINCT SYMBOLS (repeated calls from one caller, and calls to two overloads, collapse into ONE row; multiplicity survives only in the call graph's edge weight). The reach counts (impact's reaches=, pr-context's dependents=) are the size of a transitive reach SET, each symbol counted once. The uses verb counts call SITES, one row per occurrence — a larger count there for the same symbol is these units agreeing, not disagreeing. The map header's edges= is a unit again different — distinct (caller,callee) PAIRS — and that document carries neither this marker nor this clause. -->
<!-- root= on this element is the crawl root every p= below is RELATIVE to (single-root runs only; absent => p= is the path ingest itself used, unchanged). -->
<callers of="rankGraphTeleport" defs="1" count="7" root="." hop_tested="0" hop_untested="7" graph_ambiguous="3456" graph_unresolved="18664" graph_unindexed="286" counts_floor="1" next="--uses=rankGraphTeleport">
<s t="fn" n="getIndex" p="src/mcpindex.h:1211" sites_at="src/mcpindex.h:1323"/>
<s t="fn" n="rankGraph" p="src/graph.h:13674" sites_at="src/graph.h:13678"/>
<s t="fn" n="anchoredLexicalRank" p="src/graph.h:14321" sites_at="src/graph.h:14372"/>
<s t="fn" n="runEval" p="src/eval.h:171" sites_at="src/eval.h:328"/>
<s t="fn" n="churnDecayRanking" p="src/main.cpp:1433" sites_at="src/main.cpp:1447"/>
<s t="fn" n="churnRankedGraph" p="src/main.cpp:1472" sites_at="src/main.cpp:1486 src/main.cpp:1487 src/main.cpp:1501"/>
<s t="fn" n="runDefaultMap" p="src/main.cpp:1759" sites_at="src/main.cpp:1879"/>
</callers>
`````

## `./build/ripwire . --callers=DoesNotExist`

*Unknown-symbol REFUSAL shape (exit 1) with a did-you-mean from real edit distance.*

**exit code: 1** — **wall time: 10.01s**

`````
<!-- ripwire callers schema=ripwire.callers/v1: 1-hop CALLERS of of= (defs= matched, count= distinct symbols): <s t= n= p=>; hop_tested=/hop_untested=. found=0: no indexed definition matched the selector, nothing listed or counted (zero = none found, not none exists); exit stays 1. -->
<callers schema="ripwire.callers/v1" of="DoesNotExist" found="0"/>
`````

stderr:

`````
ripwire: --callers symbol not found: DoesNotExist (note: the lexical definition scan stopped at its budget, 4096 files or 16 MiB, before reading every file, so this miss is not proof the bytes define nothing; --grep=DoesNotExist lists its text uses)
`````

## `./build/ripwire . --callees=rankGraphTeleport`

*What SYM calls (1-hop out-edges).*

**wall time: 3.16s**

`````
<!-- ripwire callees schema=ripwire.callees/v1: 1-hop CALLEES of of= (defs= matched, count= distinct symbols): <s t= n= p= role= tested=>. counts_floor=1: every count is a FLOOR, never a total. graph_ambiguous=/graph_unresolved=: resolver gauge. graph_unindexed=N: N files no grammar could read (the map header's unindexed=); their calls raise neither gauge. stdm n= calls=: of declined_calls=, calls named like a standard-type member of their language (C++ container/string/optional/smart pointer, Rust collection/string/Option/Result; n=) on a receiver no rule tied to an in-tree class (Rust: one of an in-tree type no rule typed too: a generic bound, dyn or impl Trait, a type alias, a glob of a glob, a tuple-struct field, a non-plain pattern, behind Option / Result / Rc / Arc / RefCell / Cell / Mutex / RwLock); no edge or row (may be the std member). root=: p= relative to it. prov=scip|binding|import|split|final-segment: how that <c> edge bound (absent: one unique name); split = one arm of an amb= pick; final-segment = a qualified type matched by last name only. <s tested=1>: a non-test row an indexed test transitively reaches (absent otherwise, never 0). declined_calls=K: K call sites left unbound, in no count; <dc n= l=|in= p= cands=K via=declined>: one such call SITE (callees: called name, line; callers: calling def, file:line); NOT an edge or a caller/callee claim; cands=K: K in-tree defs it could have meant (K may be 1), the resolver proved none; not a claim this call reaches any of them. dc gate=: builtin or std, a name gate declined it; side, a Ruby call whose in-reach defs answer on the other side of self. next=: the one pasteable follow-up. hop_tested=/hop_untested=: count= split by whether an indexed test reaches the row (in-process calls only). -->
<callees schema="ripwire.callees/v1" of="rankGraphTeleport" defs="1" count="4" root="." hop_tested="3" hop_untested="1" declined_calls="6" graph_ambiguous="3456" graph_unresolved="18664" graph_unindexed="286" counts_floor="1" next="--expand=rankGraphTeleport">
<s t="fn" n="biasPrior" p="src/graph.h:13590"/>
<s t="macro" n="PROFILE_SCOPE_DESCRIBE" p="src/infra/profileScope.h:1282" role="macro" tested="1" prov="split"/>
<s t="macro" n="PROFILE_SCOPE_DESCRIBE" p="src/infra/profileScope.h:1296" role="macro" tested="1" prov="split"/>
<s t="fn" n="pageRankDouble" p="src/pagerank.cpp:99" tested="1"/>
<stdm n="begin,end,size" calls="6"/>
<dc n="size" l="13635" cands="1" via="declined" gate="std"/>
<dc n="begin" l="13636" cands="7" via="declined"/>
<dc n="end" l="13636" cands="7" via="declined"/>
<dc n="begin" l="13657" cands="7" via="declined"/>
<dc n="end" l="13657" cands="7" via="declined"/>
<dc n="begin" l="13657" cands="7" via="declined"/>
</callees>
`````

## `./build/ripwire . --uses=rankGraphTeleport`

*The resolvable use-sites (call/read/write/import/extends) with file:line; count= is a floor.*

**wall time: 2.15s**

`````
<!-- ripwire uses schema=ripwire.uses/v1: resolvable use-sites of of=: <u role=call|macro|read|write|import|extends|type p=file:line in_id=>. counts_floor=1: every count is a FLOOR, never a total. graph_ambiguous=/graph_unresolved=: resolver gauge. graph_unindexed=N: N files no grammar could read (the map header's unindexed=); their calls raise neither gauge. root=: p= relative to it. defs=N: definitions the selector matched; qualify file:name to narrow the call sites. external=1: of= has no definition in the indexed tree under any spelling (stdlib/third-party). count=N: unhedged use-site rows (a floor). -->
<uses schema="ripwire.uses/v1" of="rankGraphTeleport" defs="1" external="0" count="9" root="." graph_ambiguous="3456" graph_unresolved="18664" graph_unindexed="286" counts_floor="1">
<u role="call" p="src/mcpindex.h:1323" in_id="src/mcpindex.h::rw::getIndex"/>
<u role="call" p="src/graph.h:13678" in_id="src/graph.h::rw::rankGraph"/>
<u role="call" p="src/graph.h:14372" in_id="src/graph.h::rw::anchoredLexicalRank"/>
<u role="call" p="src/eval.h:328" in_id="src/eval.h::rw::runEval"/>
<u role="call" p="src/main.cpp:1447" in_id="churnDecayRanking"/>
<u role="call" p="src/main.cpp:1486" in_id="churnRankedGraph"/>
<u role="call" p="src/main.cpp:1487" in_id="churnRankedGraph"/>
<u role="call" p="src/main.cpp:1501" in_id="churnRankedGraph"/>
<u role="call" p="src/main.cpp:1879" in_id="runDefaultMap"/>
</uses>
`````

## `./build/ripwire . --graph-query='and(callers(name("rankGraphTeleport"),2),kind(all,fn))'`

*Composable node-set query: functions within 2 caller-hops of rankGraphTeleport.*

**wall time: 2.18s**

`````
<!-- ripwire graph-query schema=ripwire.graph-query/v1: graph-query expression over the symbol graph: <s t= n= p=> matching rows. window: shown= capped= (capped=1 cut). counts_floor=1: every count is a FLOOR, never a total. graph_ambiguous=/graph_unresolved=: resolver gauge. graph_unindexed=N: N files no grammar could read (the map header's unindexed=); their calls raise neither gauge. root=: p= relative to it. pr_iters=N: PageRank iterations. expr=: the expression as given; count=: symbols it matched (rows page by shown=/total=). -->
<query schema="ripwire.graph-query/v1" expr="and(callers(name(&quot;rankGraphTeleport&quot;),2),kind(all,fn))" count="55" shown="55" capped="0" graph_ambiguous="3456" graph_unresolved="18664" graph_unindexed="286" counts_floor="1" root="." pr_iters="38">
<s t="fn" n="getIndex" p="src/mcpindex.h:1211"/>
<s t="fn" n="anchoredLexicalRank" p="src/graph.h:14321"/>
<s t="fn" n="emitCommunitiesReport" p="src/verbs_report.h:2695"/>
<s t="fn" n="emitCommunityDrill" p="src/verbs_report.h:2856"/>
<s t="fn" n="dispatchMainBody" p="src/main.cpp:4438"/>
<s t="fn" n="rankGraph" p="src/graph.h:13674"/>
<s t="fn" n="computeLensRanking" p="src/verbs_for.h:110"/>
<s t="fn" n="postCheckJsonBuilt" p="src/mcpedit.h:1118"/>
<s t="fn" n="fetchBody" p="src/mcpverbs.h:5789"/>
<s t="fn" n="runEvalRetrieval" p="src/eval.h:716"/>
<s t="fn" n="runEvalMined" p="src/eval.h:1089"/>
<s t="fn" n="dispatchMcpLine" p="src/mcp.h:1146"/>
<s t="fn" n="runEditVerb" p="src/mcpedit.h:1215"/>
<s t="fn" n="churnDecayRanking" p="src/main.cpp:1433"/>
<s t="fn" n="fetchBodyByName" p="src/mcpverbs.h:5712"/>
<s t="fn" n="symbolQueryJson" p="src/mcpverbs.h:775"/>
<s t="fn" n="anchoredFileScore" p="src/eval.h:111"/>
<s t="fn" n="pathText" p="src/mcpverbs.h:3962"/>
<s t="fn" n="analyzeToString" p="src/mcpverbs.h:450"/>
<s t="fn" n="grepHitsJson" p="src/mcpverbs.h:1321"/>
<s t="fn" n="cochangePartnersJson" p="src/mcpverbs.h:1501"/>
<s t="fn" n="mentionsJson" p="src/mcpverbs.h:1913"/>
<s t="fn" n="forTaskText" p="src/mcpverbs.h:2583"/>
<s t="fn" n="legoText" p="src/mcpverbs.h:3160"/>
<s t="fn" n="ownersText" p="src/mcpverbs.h:3201"/>
<s t="fn" n="exemplarText" p="src/mcpverbs.h:3342"/>
<s t="fn" n="impactText" p="src/mcpverbs.h:3422"/>
<s t="fn" n="usesText" p="src/mcpverbs.h:3781"/>
… [28 more display lines; full output is 3660 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --external-surface`

*Names referenced but never defined in-corpus (stdlib/third-party surface). The root carries names/shown/capped; the default is a 100-row window now, so total= and a pasteable next= join them when it bites (the explicit --limit form carries the same quintet). The sh BUILTINS (cd/echo/set…) are dropped and COUNTED as builtins_excluded= — grep/sed/git stay, they ARE the surface.*

**wall time: 4.81s**

`````
<!-- ripwire external-surface schema=ripwire.external-surface/v1: names used but never defined in the index: <x n= lang= refs= calls=>. window: shown= total= capped= has_more= next_offset= offset= limit= (capped=1 cut; next_offset= pastes as offset=). next=: the one pasteable follow-up. names=N: distinct external names (the x rows' total). builtins_excluded=N: sh BUILTIN rows (echo printf cd exit test ...) dropped from names=; the include-builtins flag keeps them. -->
<external-surface schema="ripwire.external-surface/v1" names="3502" builtins_excluded="18" shown="100" capped="1" total="3502" has_more="1" next_offset="100" offset="0" limit="0" next="--external-surface --offset=100">
<x n="grep" lang="sh" refs="16779" calls="16779"/>
<x n="cat" lang="sh" refs="3246" calls="3246"/>
<x n="tr" lang="sh" refs="2555" calls="2555"/>
<x n="python3" lang="sh" refs="2308" calls="2308"/>
<x n="sed" lang="sh" refs="2038" calls="2038"/>
<x n="string_view" lang="cpp" refs="1396" calls="1396"/>
<x n="to_string" lang="cpp" refs="1264" calls="1264"/>
<x n="wc" lang="sh" refs="1092" calls="1092"/>
<x n="print" lang="py" refs="1032" calls="1032"/>
<x n="ts_node_is_null" lang="cpp" refs="1031" calls="1031"/>
<x n="mktemp" lang="sh" refs="963" calls="963"/>
<x n="dirname" lang="sh" refs="935" calls="935"/>
<x n="uint32_t" lang="cpp" refs="842" calls="842"/>
<x n="ts_node_type" lang="cpp" refs="797" calls="797"/>
<x n="size_t" lang="cpp" refs="795" calls="795"/>
<x n="cmp" lang="sh" refs="783" calls="783"/>
<x n="stdout" lang="cpp" refs="714" calls="0"/>
<x n="xmllint" lang="sh" refs="706" calls="706"/>
<x n="starts_with" lang="cpp" refs="631" calls="631"/>
<x n="stderr" lang="cpp" refs="600" calls="0"/>
<x n="diff" lang="sh" refs="585" calls="585"/>
<x n="awk" lang="sh" refs="582" calls="582"/>
<x n="rm" lang="sh" refs="461" calls="461"/>
<x n="rfind" lang="cpp" refs="430" calls="430"/>
<x n="any_of" lang="cpp" refs="338" calls="338"/>
<x n="add_argument" lang="py" refs="331" calls="331"/>
<x n="ends_with" lang="cpp" refs="276" calls="276"/>
<x n="perl" lang="sh" refs="275" calls="275"/>
… [73 more display lines; full output is 5617 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --external-surface --include-builtins`

*The restoring knob: --include-builtins keeps the shell builtins in the same 100-row window (they now compete for rows, so the window's tail differs).*

**wall time: 3.04s**

`````
<!-- ripwire external-surface schema=ripwire.external-surface/v1: names used but never defined in the index: <x n= lang= refs= calls=>. window: shown= total= capped= has_more= next_offset= offset= limit= (capped=1 cut; next_offset= pastes as offset=). next=: the one pasteable follow-up. names=N: distinct external names (the x rows' total). -->
<external-surface schema="ripwire.external-surface/v1" names="3520" shown="100" capped="1" total="3520" has_more="1" next_offset="100" offset="0" limit="0" next="--external-surface --include-builtins --offset=100">
<x n="grep" lang="sh" refs="16779" calls="16779"/>
<x n="printf" lang="sh" refs="15717" calls="15717"/>
<x n="echo" lang="sh" refs="9259" calls="9259"/>
<x n="exit" lang="sh" refs="3371" calls="3371"/>
<x n="cat" lang="sh" refs="3246" calls="3246"/>
<x n="cd" lang="sh" refs="2664" calls="2664"/>
<x n="tr" lang="sh" refs="2555" calls="2555"/>
<x n="python3" lang="sh" refs="2308" calls="2308"/>
<x n="sed" lang="sh" refs="2038" calls="2038"/>
<x n="return" lang="sh" refs="1689" calls="1689"/>
<x n="string_view" lang="cpp" refs="1396" calls="1396"/>
<x n="to_string" lang="cpp" refs="1264" calls="1264"/>
<x n="command" lang="sh" refs="1108" calls="1108"/>
<x n="wc" lang="sh" refs="1092" calls="1092"/>
<x n="print" lang="py" refs="1032" calls="1032"/>
<x n="ts_node_is_null" lang="cpp" refs="1031" calls="1031"/>
<x n="mktemp" lang="sh" refs="963" calls="963"/>
<x n="dirname" lang="sh" refs="935" calls="935"/>
<x n="pwd" lang="sh" refs="870" calls="870"/>
<x n="uint32_t" lang="cpp" refs="842" calls="842"/>
<x n="trap" lang="sh" refs="829" calls="829"/>
<x n="ts_node_type" lang="cpp" refs="797" calls="797"/>
<x n="size_t" lang="cpp" refs="795" calls="795"/>
<x n="cmp" lang="sh" refs="783" calls="783"/>
<x n="stdout" lang="cpp" refs="714" calls="0"/>
<x n="xmllint" lang="sh" refs="706" calls="706"/>
<x n="starts_with" lang="cpp" refs="631" calls="631"/>
<x n="stderr" lang="cpp" refs="600" calls="0"/>
… [73 more display lines; full output is 5498 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --path=main,rankGraphTeleport`

*Shortest directed call-path SRC -> DST. CHANGED: now reports from_p/to_p/from_defs and resolves the right `main` (was reachable="0").*

**wall time: 2.72s**

`````
<!-- ripwire path schema=ripwire.path/v1: one DIRECTED call path from= to to=, each <s t= n= p=> a hop; reachable=0 hops=0 when none shown. counts_floor=1: every count is a FLOOR, never a total. graph_ambiguous=/graph_unresolved=: resolver gauge. graph_unindexed=N: N files no grammar could read (the map header's unindexed=); their calls raise neither gauge. root=: p= relative to it. next=: the one pasteable follow-up. s site=: a call of this row's name in the row above (arity fit, then owner, first); by name, not proof. s sites=N: N such lines. s call=: its text, <=3 lines/120 B, U+2026=cut; pair 1 only. s sig=: this row's signature, <=160 B; pair 1 only. alts side=from|to of=: further definitions that endpoint's name binds, not printed above (the pick is not provably unique): <d p= sel= class=>, sel= pastes as that endpoint. alts alts_shown=K defs=N: K of the other rows shown; next= pages the rest. from_p=/to_p=: the definitions from= and to= were bound to. from_defs=/to_defs=: definitions of each name, all searched; above 1, qualify file:name. -->
<path schema="ripwire.path/v1" from="main" to="rankGraphTeleport" from_p="src/main.cpp:4268" to_p="src/graph.h:13631" from_defs="179" to_defs="1" reachable="1" hops="6" next="--expand=src/main.cpp:4349:finishMainRun" root="." graph_ambiguous="3456" graph_unresolved="18664" graph_unindexed="286" coun … [line truncated: 13 more bytes on this line]
<s t="fn" n="main" p="src/main.cpp:4268"/>
<s t="fn" n="finishMainRun" p="src/main.cpp:4349" site="src/main.cpp:4343" call="const int rc = finishMainRun( cfg, argv );" sig="static int finishMainRun( const rw::Config&amp; cfg, char** argv )"/>
<s t="fn" n="runWithCompactLegend" p="src/main.cpp:4202" site="src/main.cpp:4352" call="const int rc = runWithCompactLegend( cfg, argv );" sig="static int runWithCompactLegend( const rw::Config&amp; cfg, char** argv )"/>
<s t="fn" n="dispatchMain" p="src/main.cpp:6036" site="src/main.cpp:4207" sites="4" call="return dispatchMain( cfg, argv );" sig="static int dispatchMain( const rw::Config&amp; cfg, char** argv )"/>
<s t="fn" n="dispatchMainBody" p="src/main.cpp:4438" site="src/main.cpp:6040" call="return dispatchMainBody( cfg, argv );" sig="static int dispatchMainBody( const rw::Config&amp; cfg, char** argv )"/>
<s t="fn" n="runDefaultMap" p="src/main.cpp:1759" site="src/main.cpp:5797" sites="2" call="return runDefaultMap( dsp );" sig="int runDefaultMap( const MainDispatch&amp; d )"/>
<s t="fn" n="rankGraphTeleport" p="src/graph.h:13631" site="src/main.cpp:1879" call="rank = rw::takeRank( rankGraphTeleport( g, diffTeleport( ing, changed ) ), rankDisclosure );" sig="inline RankedGraph rankGraphTeleport( const Graph&amp; g, const std::vector&lt;float&gt;&amp; p, float alpha = 0.85f … [line truncated: 5 more bytes on this line]
<alts side="from" of="main" alts_shown="16" defs="173" next="--defs=main --offset=17">
<d p="docs/counts_snapshot.py:230" sel="docs/counts_snapshot.py:main" class="source"/>
<d p="docs/docs_commands_build.py:900" sel="docs/docs_commands_build.py:main" class="source"/>
<d p="scripts/changelog_assemble.py:170" sel="scripts/changelog_assemble.py:main" class="source"/>
<d p="scripts/merge_resolve.py:208" sel="scripts/merge_resolve.py:main" class="source"/>
<d p="scripts/optremarks.py:285" sel="scripts/optremarks.py:main" class="source"/>
<d p="scripts/tidyadvisory_diff.py:313" sel="scripts/tidyadvisory_diff.py:main" class="source"/>
<d p="src/tsprobe.cpp:70" sel="src/tsprobe.cpp:main" class="source"/>
<d p="bench/agentloop/analyze.py:345" sel="bench/agentloop/analyze.py:main" class="test"/>
<d p="bench/agentloop/backfill_claude_transcripts.py:104" sel="bench/agentloop/backfill_claude_transcripts.py:main" class="test"/>
<d p="bench/agentloop/editsuite/gen_expected.py:47" sel="bench/agentloop/editsuite/gen_expected.py:main" class="test"/>
<d p="bench/agentloop/followup_calls.py:160" sel="bench/agentloop/followup_calls.py:main" class="test"/>
<d p="bench/agentloop/grade_answers.py:604" sel="bench/agentloop/grade_answers.py:main" class="test"/>
<d p="bench/agentloop/power_sim.py:209" sel="bench/agentloop/power_sim.py:main" class="test"/>
<d p="bench/agentloop/run_agentloop.py:1237" sel="bench/agentloop/run_agentloop.py:main" class="test"/>
<d p="bench/agentloop/run_editsuite.py:530" sel="bench/agentloop/run_editsuite.py:main" class="test"/>
<d p="bench/agentloop/select_tasks.py:144" sel="bench/agentloop/select_tasks.py:main" class="test"/>
</alts>
</path>
`````

## `./build/ripwire . --defs=main,rankGraphTeleport`

*Which definitions each name binds, one row per definition group with sel= (the spelling that picks it alone in any verb), class=source|test and in= callers; source first.*

**wall time: 3.19s**

`````
<!-- ripwire defs schema=ripwire.defs/v1: per <name q= defs=> the parsed definitions the name binds (defs= groups; a prototype with its definition is one): <d n= t= p= sel= lang= class=source|test in=>, sel= binds that one alone in any SYM verb, in= distinct callers (a floor); source first, then in=, then path. window: shown= offset= (capped=1 cut). root=: p= relative to it. <d in=N>: N callers in the index (absent: not measured). next=: the one pasteable follow-up. name data_defs=K: data keys or doc headings of that name (JSON/YAML key, markdown heading), not code, not in defs=. name shown=K offset=M: rows M..M+K of defs=; next= pages the rest. name next=: the next page, or (defs=0) the single-name call whose refusal names near names. -->
<defs schema="ripwire.defs/v1" root=".">
<name q="main" defs="173" data_defs="6" shown="16" offset="0" next="--defs=main --offset=16">
<d n="main" t="fn" p="docs/counts_snapshot.py:230" sel="docs/counts_snapshot.py:main" lang="py" class="source" in="1"/>
<d n="main" t="fn" p="docs/docs_commands_build.py:900" sel="docs/docs_commands_build.py:main" lang="py" class="source" in="1"/>
<d n="main" t="fn" p="scripts/changelog_assemble.py:170" sel="scripts/changelog_assemble.py:main" lang="py" class="source" in="1"/>
<d n="main" t="fn" p="scripts/merge_resolve.py:208" sel="scripts/merge_resolve.py:main" lang="py" class="source" in="1"/>
<d n="main" t="fn" p="scripts/optremarks.py:285" sel="scripts/optremarks.py:main" lang="py" class="source" in="1"/>
<d n="main" t="fn" p="scripts/tidyadvisory_diff.py:313" sel="scripts/tidyadvisory_diff.py:main" lang="py" class="source" in="1"/>
<d n="main" t="fn" p="src/main.cpp:4268" sel="src/main.cpp:main" lang="cpp" class="source" in="0"/>
<d n="main" t="fn" p="src/tsprobe.cpp:70" sel="src/tsprobe.cpp:main" lang="cpp" class="source" in="0"/>
<d n="main" t="fn" p="bench/agentloop/analyze.py:345" sel="bench/agentloop/analyze.py:main" lang="py" class="test" in="1"/>
<d n="main" t="fn" p="bench/agentloop/backfill_claude_transcripts.py:104" sel="bench/agentloop/backfill_claude_transcripts.py:main" lang="py" class="test" in="1"/>
<d n="main" t="fn" p="bench/agentloop/editsuite/gen_expected.py:47" sel="bench/agentloop/editsuite/gen_expected.py:main" lang="py" class="test" in="1"/>
<d n="main" t="fn" p="bench/agentloop/followup_calls.py:160" sel="bench/agentloop/followup_calls.py:main" lang="py" class="test" in="1"/>
<d n="main" t="fn" p="bench/agentloop/grade_answers.py:604" sel="bench/agentloop/grade_answers.py:main" lang="py" class="test" in="1"/>
<d n="main" t="fn" p="bench/agentloop/power_sim.py:209" sel="bench/agentloop/power_sim.py:main" lang="py" class="test" in="1"/>
<d n="main" t="fn" p="bench/agentloop/run_agentloop.py:1237" sel="bench/agentloop/run_agentloop.py:main" lang="py" class="test" in="1"/>
<d n="main" t="fn" p="bench/agentloop/run_editsuite.py:530" sel="bench/agentloop/run_editsuite.py:main" lang="py" class="test" in="1"/>
</name>
<name q="rankGraphTeleport" defs="1">
<d n="rankGraphTeleport" t="fn" p="src/graph.h:13631" sel="rankGraphTeleport" lang="cpp" class="source" in="7"/>
</name>
</defs>
`````

## `./build/ripwire . --connect=rankGraphTeleport,runEval,getIndex`

*Minimal connecting subgraph over 3 symbols (finds shared-caller joins).*

**wall time: 4.54s**

`````
<!-- ripwire connect schema=ripwire.connect/v1: minimal joining subgraph: <g> groups, <t> terminals, <s connects=> joins, <e f= t=> edges, <unconnected>. counts_floor=1: every count is a FLOOR, never a total. graph_ambiguous=/graph_unresolved=: resolver gauge. graph_unindexed=N: N files no grammar could read (the map header's unindexed=); their calls raise neither gauge. est_tokens=: price as emitted (an upper bound under compact). root=: p= relative to it. hub_floor=D: connects= >= D is hub=1, vacuous. nodes=N: symbols printed, terminals plus joins (a floor). radius=N: undirected hop bound searched (default 6, max 12); raise it with connect-radius=N. e site=: a call of t= in f= (arity fit, then owner, first); by name, not proof. e call=: its text, <=3 lines/120 B, U+2026=cut. e sig=: t='s signature, <=160 B, once per callee. terminals=/groups=/edges=: task symbols resolved, connected groups (g), e edges printed. -->
<connect schema="ripwire.connect/v1" terminals="3" nodes="3" edges="2" radius="6" groups="1" est_tokens="734" hub_floor="280" root="." graph_ambiguous="3456" graph_unresolved="18664" graph_unindexed="286" counts_floor="1">
<g terminals="3">
<t n="runEval" t="fn" p="src/eval.h:171"/>
<t n="rankGraphTeleport" t="fn" p="src/graph.h:13631"/>
<t n="getIndex" t="fn" p="src/mcpindex.h:1211"/>
<e f="runEval" t="rankGraphTeleport" site="src/eval.h:328" call="const std::vector&lt;float&gt; r = rankGraphTeleport( g, diffTeleport( ing, seedMask ) ).rank;" sig="inline RankedGraph rankGraphTeleport( const Graph&amp; g, const std::vector&lt;float&gt;&amp; p, float alpha = 0.85f )"/>
<e f="getIndex" t="rankGraphTeleport" site="src/mcpindex.h:1323" call="const auto [ wsRank, wsIters, wsConverged ] = rankGraphTeleport( ix.g, diffTeleport( ix.ing, changed ) );"/>
</g>
</connect>
`````

## `./build/ripwire . --impact=rankGraphTeleport`

*Transitive blast radius — everything that reaches SYM. NOW carries shown/capped.*

**wall time: 3.41s**

`````
<!-- ripwire impact schema=ripwire.impact/v1: transitive blast radius of of=: <s t= n= p=> reach set, <f via= p=> importers; defs= matched, reaches= their transitive callers, radius_tested= non-tests an indexed test reaches, radius_untested= the rest; importers= files that #include/import a def's file. window: shown= total= capped= has_more= next_offset= offset= limit= (capped=1 cut; next_offset= pastes as offset=). importers_capped=/files_capped=: 1 = cut. counts_floor=1: every count is a FLOOR, never a total. graph_ambiguous=/graph_unresolved=: resolver gauge. graph_unindexed=N: N files no grammar could read (the map header's unindexed=); their calls raise neither gauge. root=: p= relative to it. pr_iters=N: PageRank iterations. shown_importers=: <f> rows (limit= sizes them). importers_next=: the call listing every importer. importers_tests=/importers_dirs=: over EVERY importer of a cut tier: test/bench/fixture files / the 3 dirs (2 path segments) holding most, dir:count. files files=/shown_files=: files the WHOLE reach set touches (rides beside a cut symbol window) / listed; rf syms= reached symbols there, d= fewest hops; files_capped=1 + files_next= when cut. <f lazy=1>: every edge from that importer into a def file is deferred (in a function/block body, or an autoload), firing only if reached; lazy=0: at least one is load-time. declined_calls=K: K call sites left unbound, in no count; <dc n= l=|in= p= cands=K via=declined>: one such call SITE (callees: called name, line; callers: calling def, file:line); NOT an edge or a caller/callee claim; cands=K: K in-tree defs it could have meant (K may be 1), the resolver proved none; not a claim this call reaches any of them. <s d=N>: hops to of= (1 = direct caller), set where it changes. by_depth=k:n: n of reaches= at depth k, shallowest rows first. next=: the one pasteable follow-up. -->
<impact schema="ripwire.impact/v1" of="rankGraphTeleport" defs="1" reaches="70" by_depth="1:7,2:48,3:10,4:3,5:1,6:1" importers="67" shown_importers="40" importers_capped="1" importers_next="--impact=rankGraphTeleport --limit=67" importers_tests="2" importers_dirs="src:65,test:2" radius_tested="0" ra … [line truncated: 271 more bytes on this line]
<files files="14" shown_files="14" files_capped="0">
<rf p="src/main.cpp" syms="11" d="1"/>
<rf p="src/eval.h" syms="4" d="1"/>
<rf p="src/graph.h" syms="2" d="1"/>
<rf p="src/mcpindex.h" syms="1" d="1"/>
<rf p="src/mcpverbs.h" syms="28" d="2"/>
<rf p="src/verbs_report.h" syms="6" d="2"/>
<rf p="src/editplan.h" syms="4" d="2"/>
<rf p="src/mcpedit.h" syms="3" d="2"/>
<rf p="src/verbs_for.h" syms="3" d="2"/>
<rf p="src/mcp.h" syms="2" d="2"/>
<rf p="src/verbs_change.h" syms="2" d="2"/>
<rf p="src/verbs_navigate.h" syms="2" d="2"/>
<rf p="src/lsp.h" syms="1" d="2"/>
<rf p="src/mcpserver.h" syms="1" d="2"/>
</files>
<s t="fn" n="getIndex" p="src/mcpindex.h:1211" d="1"/>
<s t="fn" n="anchoredLexicalRank" p="src/graph.h:14321"/>
<s t="fn" n="rankGraph" p="src/graph.h:13674"/>
<s t="fn" n="churnDecayRanking" p="src/main.cpp:1433"/>
<s t="fn" n="runDefaultMap" p="src/main.cpp:1759"/>
<s t="fn" n="churnRankedGraph" p="src/main.cpp:1472"/>
<s t="fn" n="runEval" p="src/eval.h:171"/>
<s t="fn" n="emitCommunitiesReport" p="src/verbs_report.h:2695" d="2"/>
<s t="fn" n="emitCommunityDrill" p="src/verbs_report.h:2856"/>
<s t="fn" n="dispatchMainBody" p="src/main.cpp:4438"/>
<s t="fn" n="computeLensRanking" p="src/verbs_for.h:110"/>
<s t="fn" n="postCheckJsonBuilt" p="src/mcpedit.h:1118"/>
… [71 more display lines; full output is 7201 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --mentions=rankGraphTeleport`

*Markdown docs that name SYM in a backtick (doc<->code edges).*

**wall time: 3.73s**

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

**wall time: 3.29s**

`````
<!-- ripwire affected schema=ripwire.affected/v1: test files that transitively reach the changed files/symbols: <test p= partner= hops= run=> in evidence order (order= partners=); seeded_by= the reading taken. counts_floor=1: every count is a FLOOR, never a total. graph_ambiguous=/graph_unresolved=: resolver gauge. graph_unindexed=N: N files no grammar could read (the map header's unindexed=); their calls raise neither gauge. run_unknown=1: no runner derivable (a guess would be worse). root=: p= relative to it. seeds=N: symbols the argument matched; only those outside test files seed the caller walk. seed_test_files=N: matched files that are TESTS; listed to run (seed_kind=test), never walk seeds. tests=N: test files listed to run (the rows). reached=N: symbols the transitive caller walk reached from the seeds (seeds excluded). script_gates_unmodelled=N: test/*.sh runners; their subprocess reach is unmodelled, never in tests=/reached=. run_first=N: the first N test files have the most direct evidence (changed/partner/hops=1, else nearest hops=); not a skip list. changed=: the files/symbols argument as given. -->
<affected schema="ripwire.affected/v1" changed="src/graph.h" seeded_by="file" seeds="730" seed_test_files="0" tests="10" reached="937" script_gates_unmodelled="872" run_first="3" order="evidence" partners="0" root="." graph_ambiguous="3456" graph_unresolved="18664" graph_unindexed="286" counts_floor … [line truncated: 5 more bytes on this line]
<test p="test/connectcore_harness.cpp" hops="1" run="bash test/connectcorecheck.sh"/>
<test p="test/cppqualtmplfix/member.cpp" hops="1" run="bash test/cppqualcheck.sh"/>
<test p="test/verify_csr.cpp" hops="1" run="bash test/a9disclosurecheck.sh"/>
<test p="test/fuzz/readers/readers_ingest.cpp" hops="2" run_unknown="1"/>
<test p="test/includeprecise_unit.cpp" hops="3" run="bash test/includeprecisecheck.sh"/>
<test p="test/rustimport_unit.cpp" hops="3" run="bash test/rustimportprecisecheck.sh"/>
<test p="test/columnarcommafix/columnar_comma_test.cpp" hops="4" run="bash test/columnarcommacheck.sh"/>
<test p="test/cloneband_harness.cpp" hops="5" run="bash test/clonebandcheck.sh"/>
<test p="test/type3clone_harness.cpp" hops="5" run="bash test/type3clonecheck.sh"/>
<test p="test/fuzz/readers/readers_light.cpp" hops="6" run_unknown="1"/>
</affected>
`````

## `./build/ripwire . --situ`

*Mid-task situational report for the current git diff — recorded against a CLEAN tree (contrast with the sandbox run below).*

**wall time: 8.37s**

`````
ripwire situational-awareness — 0 changed file(s), 0 symbols in them
root: .
at: 0412539b9
  (0 changed files — working tree is clean, nothing to analyze)
`````

## `./build/ripwire . --test-gate`

*Pre-PR gate on a CLEAN tree: no obligations, exit 0.*

**wall time: 20.15s**

`````
<!-- ripwire test-gate schema=ripwire.test-gate/v1: tests <t p= changed= partner= hops= run=> + untested blast radius <u sym= p= l= ccx=>; exit 4 while either exists. tests_capped=/untested_capped=: 1 = cut. counts_floor=1: every count is a FLOOR, never a total. graph_ambiguous=/graph_unresolved=: resolver gauge. graph_unindexed=N: N files no grammar could read (the map header's unindexed=); their calls raise neither gauge. at=: commit+dirty+shallow. next=: the one pasteable follow-up. impacted=N: symbols that transitively call the change (changed symbols excluded). shown_tests=/shown_untested=: t rows and u rows printed, two independent counts. script_gates_unmodelled=N: test/*.sh runners in the corpus, a path count; not call-graph modelled. script_gates_registered=N: shell gates test/regression.sh registers as suite members. script_gates_mapped=N: registered gates with exact dependency evidence (literal paths or RIPWIRE_TEST_DEPS). script_gates_unresolved_dynamic=N: registered gates with no mappable deps; they may cover the change unlisted. ccx_bar=N: the cognitive-complexity bar a u row's ccx= is read against. untested_modscope=N: <file-scope> owners excluded from untested= (#324, uncallable); still in impacted=. tests=/untested=: tests to run (t total) / impacted symbols no test reaches (u total). -->
<test-gate schema="ripwire.test-gate/v1" changed="0" impacted="0" tests="0" untested="0" untested_modscope="0" shown_tests="0" tests_capped="0" shown_untested="0" untested_capped="0" script_gates_unmodelled="872" script_gates_registered="823" script_gates_mapped="271" script_gates_unresolved_dynamic … [line truncated: 136 more bytes on this line]
</test-gate>
`````

## `./build/ripwire . --grep=DISCLOSE`

*Literal trigram-indexed search. Each hit carries its MATCHED line as the <hit> element's own CDATA (the <m> wrapper is gone), plus shown/capped/hits_capped and a pasteable next= on the root.*

**wall time: 3.79s**

`````
<!-- ripwire grep schema=ripwire.grep/v1: literal/regex scan grouped by file: <f p=>
<hit l= in=>CDATA text</hit> (<b>/<a> context around it); complete=1 only for an exhaustive literal scan (beside pattern_meta=, of the literal reading only); <unindexed> = off-index. window: shown= total= capped= has_more= next_offset= offset= limit= (capped=1 cut; next_offset= pastes as offset=). c … [line truncated: 2184 more bytes on this line]
<grep pattern="DISCLOSE" schema="ripwire.grep/v1" root="." files="274" hits="934" shown="100" capped="1" total="934" has_more="1" next_offset="100" offset="0" limit="0" hits_capped="0" suppressed_comment="155" suppressed_string="5" tier_parsed="78" tier_unclassified="716" tier_budget="bytes" tier_fi … [line truncated: 202 more bytes on this line]
<f p=".coderabbit.yaml">
<hit l="33" in="path_instructions" occ="2">
<![CDATA[        A degrade path uses DISCLOSE( sink, why ), never ASSUME(false): a one-argument DISCLOSE( msg ) is a debug trace]]>
</hit>
</f>
<f p="src/abicheck.h" parse_degraded="1">
<hit l="494" in="abicheck::collectAuthoredSites">
<![CDATA[            DISCLOSE( result, AbiResult::DisclosureWhy::NoMergeBase, "abi: no merge-base for a ref (unrelated history?) — that ref is counted, not compared" );]]>
</hit>
</f>
<f p="src/arch.h">
<hit l="511" in="rw::parseArchRules">
<![CDATA[        DISCLOSE( Diagnostics::answerRefused, "--arch exits 1 with path:line and the reason on stderr; no report is printed",]]>
</hit>
<hit l="850" in="rw::readArchBaselineSidecar">
<![CDATA[    if( sidecar.refused ) { DISCLOSE( baseline, ArchBaselineRead::DisclosureWhy::SymlinkRefused, "arch: refusing to read the arch baseline sidecar through a symlink" ); }]]>
</hit>
<hit l="901" in="rw::openArchBaselineSidecar">
<![CDATA[        DISCLOSE( Diagnostics::answerRefused, "--baseline exits 1: pathguard names the refused link on stderr and the verb says it cannot write the sidecar",]]>
</hit>
</f>
<f p="src/atoms.h">
<hit l="372" in="atomdetail::collectExclusions">
<![CDATA[        DISCLOSE( ex, Exclusions::DisclosureWhy::ForHeaderSaturated, "atoms: the for-header exclusion stream spent its whole budget; the rules reading it are suppressed this run" );]]>
</hit>
<hit l="376" in="atomdetail::collectExclusions">
<![CDATA[        DISCLOSE( ex, Exclusions::DisclosureWhy::StmtCrementSaturated, "atoms: the statement-crement exclusion stream spent its whole budget; the rules reading it are suppressed this run" );]]>
… [450 more display lines; full output is 29628 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --grep=DISCLOSE --grep-context=1`

*Same search with one line of source context either side.*

**wall time: 2.31s**

`````
<!-- ripwire grep schema=ripwire.grep/v1: literal/regex scan grouped by file: <f p=>
<hit l= in=>CDATA text</hit> (<b>/<a> context around it); complete=1 only for an exhaustive literal scan (beside pattern_meta=, of the literal reading only); <unindexed> = off-index. window: shown= total= capped= has_more= next_offset= offset= limit= (capped=1 cut; next_offset= pastes as offset=). c … [line truncated: 2184 more bytes on this line]
<grep pattern="DISCLOSE" schema="ripwire.grep/v1" root="." files="274" hits="934" shown="100" capped="1" total="934" has_more="1" next_offset="100" offset="0" limit="0" hits_capped="0" suppressed_comment="155" suppressed_string="5" tier_parsed="78" tier_unclassified="716" tier_budget="bytes" tier_fi … [line truncated: 202 more bytes on this line]
<f p=".coderabbit.yaml">
<hit l="33" in="path_instructions" occ="2">
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
<hit l="494" in="abicheck::collectAuthoredSites">
<b>
<![CDATA[        {]]>
</b>
<![CDATA[            DISCLOSE( result, AbiResult::DisclosureWhy::NoMergeBase, "abi: no merge-base for a ref (unrelated history?) — that ref is counted, not compared" );]]>
<a>
<![CDATA[            continue;]]>
</a>
</hit>
</f>
<f p="src/arch.h">
<hit l="511" in="rw::parseArchRules">
<b>
<![CDATA[        rw::emitTo( stderr, "ripwire: --arch: {}:{}: {} — rules file rejected\n", path.c_str(), lineNo, why );]]>
</b>
… [1037 more display lines; full output is 42174 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --grep=DISCLOSE --grep-before=1 --grep-after=2 --limit=3`

*The asymmetric spelling of the same context: one line before and two after each hit (ripgrep's -B/-A), on a three-hit window.*

**wall time: 2.79s**

`````
<!-- ripwire grep schema=ripwire.grep/v1: literal/regex scan grouped by file: <f p=>
<hit l= in=>CDATA text</hit> (<b>/<a> context around it); complete=1 only for an exhaustive literal scan (beside pattern_meta=, of the literal reading only); <unindexed> = off-index. window: shown= total= capped= has_more= next_offset= offset= limit= (capped=1 cut; next_offset= pastes as offset=). c … [line truncated: 1687 more bytes on this line]
<grep pattern="DISCLOSE" schema="ripwire.grep/v1" root="." files="274" hits="934" shown="3" capped="1" total="934" has_more="1" next_offset="3" offset="0" limit="3" hits_capped="0" suppressed_comment="155" suppressed_string="5" tier_parsed="78" tier_unclassified="716" tier_budget="bytes" tier_files= … [line truncated: 196 more bytes on this line]
<f p=".coderabbit.yaml">
<hit l="33" in="path_instructions" occ="2">
<b>
<![CDATA[        External input (files, git, env, argv, MCP/JSON, data read back from a cache) is checked with VALIDATE.]]>
</b>
<![CDATA[        A degrade path uses DISCLOSE( sink, why ), never ASSUME(false): a one-argument DISCLOSE( msg ) is a debug trace]]>
<a>
<![CDATA[        that ships nothing, and a Diagnostics::answerUnchanged reason must be true. A count that cannot be a total must be
        labelled a floor; a zero means none found. Flag silent zeros, undisclosed truncation, and gate arms]]></a></hit></f><f p="src/abicheck.h" parse_degraded="1"><hit l="494" in="abicheck::collectAuthoredSites"><b><![CDATA[        {]]></b><![CDATA[            DISCLOSE( result, AbiResult::Disclosu … [line truncated: 148 more bytes on this line]
        }]]></a></hit></f><f p="src/arch.h"><hit l="511" in="rw::parseArchRules"><b><![CDATA[        rw::emitTo( stderr, "ripwire: --arch: {}:{}: {} — rules file rejected\n", path.c_str(), lineNo, why );]]></b><![CDATA[        DISCLOSE( Diagnostics::answerRefused, "--arch exits 1 with path:line an … [line truncated: 134 more bytes on this line]
        return false;]]></a></hit></f><unindexed count="13" shown="3" capped="1"><f p="CMakeLists.txt"><hit l="122"><![CDATA[# ASSUME and the DISCLOSE( msg ) trace live, which is the only configuration that can catch an]]></hit><hit l="347"><![CDATA[# -DCMAKE_BUILD_TYPE=Release" locally — Release  … [line truncated: 382 more bytes on this line]
`````

## `./build/ripwire . --regex='fnv1a\w+'`

*Regex search + enclosing symbol.*

**wall time: 2.68s**

`````
<!-- ripwire grep schema=ripwire.grep/v1: literal/regex scan grouped by file: <f p=>
<hit l= in=>CDATA text</hit> (<b>/<a> context around it); complete=1 only for an exhaustive literal scan (beside pattern_meta=, of the literal reading only); <unindexed> = off-index. window: shown= capped= (capped=1 cut). hits_capped=1: hits= is a floor. regex_lines_skipped=N: N lines too long for t … [line truncated: 1773 more bytes on this line]
<grep pattern="fnv1a\w+" schema="ripwire.grep/v1" root="." files="27" hits="88" shown="88" capped="0" hits_capped="0" suppressed_comment="65" suppressed_string="26" tier_parsed="44" tier_unclassified="0" corpus_oversize="15" corpus_pruned_dirs="7" unindexed_hits="23" unindexed_files_scanned="285" un … [line truncated: 77 more bytes on this line]
<f p="src/arch.h">
<hit l="682" in="rw::fnv1a64">
<![CDATA[inline std::uint64_t fnv1a64( std::string_view s ) noexcept]]>
</hit>
<hit l="687" in="rw::fnv1a64">
<![CDATA[        h = hashutil::fnv1aAbsorb( h, c );]]>
</hit>
<hit l="792" in="rw::archViolHash">
<![CDATA[            h = hashutil::fnv1aAbsorb( h, c );]]>
</hit>
<hit l="795" in="rw::archViolHash">
<![CDATA[        h = hashutil::fnv1aMultiply( h ); // NUL separator byte]]>
</hit>
</f>
<f p="src/cloneidiom.h">
<hit l="607" in="rw::classifyCloneGroupIdioms">
<![CDATA[                ids.push_back( fnv1a64( t.text ) );]]>
</hit>
</f>
<f p="src/clones.h">
<hit l="416" in="rw::cloneBodyKey">
<![CDATA[                            hash = hashutil::fnv1aAbsorb( hash, c );]]>
</hit>
<hit l="418" in="rw::cloneBodyKey">
<![CDATA[                        hash = hashutil::fnv1aAbsorb( hash, ' ' );]]>
</hit>
<hit l="854" in="rw::cloneTokenHash">
… [429 more display lines; full output is 21501 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --match='(if_statement)'`

*Tree-sitter structural query WITHOUT a capture — a bare node query gets a capture AUTO-ADDED (auto_captured="1") and matches the same nodes the explicit form does.*

**wall time: 4.18s**

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

**wall time: 6.89s**

`````
<!-- ripwire match schema=ripwire.match/v1: tree-sitter structural query: <m p= in=> captured nodes with their enclosing symbol; grammars=/eligible_files= the scope. window: shown= total= capped= has_more= next_offset= offset= limit= (capped=1 cut; next_offset= pastes as offset=). counts_floor=1: every count is a FLOOR, never a total. hits_capped=1: hits= is a floor. root=: p= relative to it. of_files=: indexed files in all (eligible_files= of them are in the query's languages). -->
<match schema="ripwire.match/v1" hits="5000" shown="100" capped="1" total="5000" has_more="1" next_offset="100" offset="0" limit="0" counts_floor="1" hits_capped="1" grammars="cpp,c,python,go,typescript,tsx,swift,objc,javascript,bash,java,csharp,php,dart,lua,gdscript" eligible_files="3413" of_files= … [line truncated: 16 more bytes on this line]
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

**wall time: 4.85s**

`````
<!-- routed: subtoken+body:broad -->
<!-- ripwire query schema=ripwire.query/v1: lexical-rank map for the query term, the map's row vocabulary. est_tokens=: price as emitted (an upper bound under compact). root=: p= relative to it. declined=K: K call sites without edges, including inert Elixir quote sites after unquote/unquote_splicing re-entry. external=K: K calls proven outside the tree, no edge. locality_pinned=K: K calls pinned by locality alone (a guess). extent_suspect_syms=K: K defs failed containment, corpus-wide. macro_blanked_files=K: K files indexed from a macro-blanked re-parse. prov=scip|binding|import|split|final-segment: how that <c> edge bound (absent: one unique name); split = one arm of an amb= pick; final-segment = a qualified type matched by last name only. files=/symbols=: files and symbols indexed; edges= distinct call edges; shown= symbols printed, a merged row counting each def; ambiguous= calls split over several defs, corpus-wide; unresolved= calls with in-tree evidence and no edge (every def language-filtered or unreachable, or binding refused); order= rows by rank (important-first, important-last; (auto:fill) = flipped past a size threshold) or by path (stable). skipped_oversize=K: K files over a size ceiling, not indexed. unindexed=ext:N: N text files of that extension no grammar reads (6 extensions at most). unindexed_exts=E: E such extensions in all, the list cut. sc=: enclosing scope; the full id is p::sc::n (p= of the row or its <f>) and selectors take it. amb=K: K calls split over several defs. -->
<!-- t=modscope=a-file's-MODULE-SCOPE(n=<file-scope>):the-statements-outside-every-named-definition,where-a-top-level-call-and-an-anonymous-callback-body's-calls-live;a-CALLER-never-a-callee(nothing-in-the-source-can-name-it)-with-no-body-to-expand;a-file-with-no-such-call-has-no-such-row -->
<!-- t=type|alias|functype=a-Go-named-type-by-its-written-form:type=a-defined-type-whose-WRITTEN-form-is-not-a-struct/iface/func-literal(type-N-string;type-W-Pair-too,whatever-Pair-is-underneath),alias=type-A=B,functype=type-F-func(...) -->
<!-- t=alias|functype-in-C++-and-.h:alias=using-X=Y(also-templated-or-class-scope)or-namespace-L=lib(defs=X-prints-its-written-target-as-to=),functype=a-typedef-of-a-function-or-function-pointer-type(typedef-void(*F)(int));other-typedefs-read-t=struct -->
<!-- files=4497 symbols=39562 edges=38970 shown=5 est_tokens=1486 ambiguous=3456 unresolved=18664 locality_pinned=11 external=11109 declined=41448 extent_suspect_syms=12 macro_blanked_files=7 skipped_oversize=15 unindexed="txt:81,tsv:53,mod:33,jsonl:26,scm:25,expected:15" unindexed_exts=23 order=important-first -->
<r schema="ripwire.query/v1" root="." est_tokens="1486">
<f p="src/serialize.h">
<s t="var" n="kChurnRankLegend" sc="rw" k="19.5835">
</s>
</f>
<f p="src/mcpverbs.h">
<s t="fn" n="rankByText" sc="rw" k="15.4202">
<c n="takeRank"/>
<c n="rankGraph"/>
<c n="hits"/>
<c n="rrfFuse"/>
<c n="getIndex"/>
<c n="captureXml"/>
<c n="serialize"/>
</s>
</f>
<f p="src/gitmine.h">
<s t="fn" n="churnPriorFromFreq" sc="rw" k="13.5188">
<c n="DISCLOSE"/>
</s>
</f>
<f p="src/pagerank.cpp">
<s t="fn" n="pageRankDouble" sc="rw" amb="3" k="13.3438">
<c n="ASSUME"/>
… [23 more display lines; full output is 3716 bytes on 1 raw line(s)]
`````


---

# zoom the detail ladder

## `./build/ripwire . --for="pagerank power iteration" --detail=2`

*Importance-weighted detail: FULL bodies for top-2, signatures for the rest.*

**wall time: 6.97s**

`````
<ctx task="pagerank power iteration" route="subtoken+body" root="." confidence="high" margin_pct="22" at="0412539b9" doc_mentions="5" schema="ripwire.for/v1" budget_bytes="7500" doc_mentions_capped="1" doc_mentions_total="14" est_tokens="8580">
<!-- ripwire for schema=ripwire.for/v1: bundle=/bodies=/reason= the body posture; d: cx= ccx= complexity, in= callers (absent cx/ccx/in = 0), churn= amp= change, clone= tested= 1, sc= scope, id=p::sc::n; total= shown= capped=1 if cut; task= the query; d pure=1 const/constexpr sig, next= the follow-up to paste; d same_as=N: doc+sig text as row n=N (not repeated); route= name-exact(X)|subtoken+body[:broad|:declined]; confidence=/margin_pct= head score drop (low=flat); t p= file outside sigs (weaker), t sym= its top symbols not in sigs/syms (a pointer, not the answer), r= rank (gap = trimmed); t order: code files first, then doc files (a code question); t page rows go on to file-page row 160 (code question: 160 code rows, docs within row 160); past page 0 (code question: past 40 code rows, a doc past row 40) listed last, head files skipped; past 120 of those p= only, p_only= counts them; t folded=class=N: N p= only rows of that class (doc|config|script|testdata|other) not listed, next= pages to them; d layer=: built-in arch layer (game|infra|render|math|audio|ai|test) from a dir name in p=; d e= its last line (absent=unknown, never 0; l= the name's line) [doc mentions: 5 docs, 3 symbols; doc_mentions=] -->
<!-- root= is the crawl root; p= below is RELATIVE to it (single-root only; absent => p= is ingest's own path, unchanged); at=this commit(+dirty). [budget_bytes= is the default BYTE target this ranked payload was shaped toward: row text shortens toward it, no row of the ranked head is removed for it (sigs past_target=)] [sigs capped=1 with shown=total: rows shrunk, none dropped] [sigs past_target=K: the last K rows are past the budget_bytes target, served because they are rows of the ranked head; none is cut] [sigs next=: one call serving all total= rows uncut] [docs_dropped=N: N shown rows have a doc comment not printed (r>24 always, r5..24 if capped)] [docs_after_code=N: N doc rows of the shown set moved below its code rows; same rows, reordered, none added or removed; a question naming docs keeps score order] [files_first=N: N rows moved so r=1..8 are distinct files' best rows, score order, a repeated name once; same rows; fold, hops keep score order] [cut: doc_mentions_capped="1" doc_mentions_total="14" — an indexing cap dropped content not shown here]; lego/compose collapse to a counted stub by default (a disclosed cut): total= that section's own pre-cap row count, shown="0" capped="1" (nothing rendered here), next= names the sections=lego,compose flag that restores both sections byte-identically in one call est_tokens= prices this bundle in tokens -->
<sigs shown="40" total="40" capped="1" past_target="14" docs_dropped="24" docs_after_code="6" files_first="7" next="--for=&apos;pagerank power iteration&apos; --signatures-only --token-budget=6100">
<d l="422" e="422" n="kScoreTieAbsEps" sc="rw" p="src/eval.h" churn="18" amp="51" pure="1" r="1" next="--expand=src/eval.h:kScoreTieAbsEps">
<doc>NodeId order. Renumbering an otherwise-identical graph (the exact &quot;same probe file, different so…</doc>inline constexpr float kScoreTieAbsEps = 1e-6f</d>
<d l="73" e="144" n="renderDisclosure" sc="rw" p="src/prconverge.h" cx="12" ccx="15" in="14" churn="3" amp="41" r="2">
<doc>Render one form of the disclosure. Empty string whenever there is nothing to say — no power it…</doc>inline std::string renderDisclosure( const RankDisclosure&amp; d, DiscloseAs as )</d>
<d l="99" e="206" n="pageRankDouble" sc="rw" p="src/pagerank.cpp" cx="19" ccx="34" in="2" churn="14" amp="44" tested="1" r="3">
<doc>The PageRank power iteration itself — the numeric kernel every ranked document&apos;s order comes f…</doc>PageRankRun pageRankDouble( const sparseCsr&lt;float&gt;&amp; inEdges, std::span&lt;const double&gt; weightedOutDegree, std::span&lt;const double&gt; teleport, std::span&lt;double&gt; r … [line truncated: 10 more bytes on this line]
<d l="497" e="543" n="rankByText" sc="rw" p="src/mcpverbs.h" cx="11" ccx="19" in="1" churn="612" amp="645" r="4">inline std::string rankByText( const std::string&amp; root, std::string_view mode, int topK, bool stable = false )</d>
<d l="13622" e="13627" n="RankedGraph" sc="RankedGraph" p="src/graph.h" churn="640" amp="867" r="5">struct RankedGraph</d>
<d l="2532" e="2536" n="kChurnRankLegend" sc="rw" p="src/serialize.h" churn="486" amp="577" pure="1" r="6">inline constexpr const char* kChurnRankLegend = &quot;&lt;!-- rank_by=churn: k= is PageRank re-run with the teleport BIASED by git CHANGE-FREQUENCY over window= &quot; &quot;(a c…</d>
<d l="1372" e="1393" n="sliceRdIterationCeiling" sc="slicev" p="src/slice.h" cx="9" ccx="12" in="1" churn="51" amp="103" r="7">inline std::uint32_t sliceRdIterationCeiling() noexcept</d>
<d l="31" e="44" n="PageRankRun" sc="PageRankRun" p="src/pagerank.h" churn="8" amp="37" r="8">struct PageRankRun</d>
<d l="51" e="56" n="RankDisclosure" sc="RankDisclosure" p="src/prconverge.h" churn="3" amp="27" r="9">
<doc>What a ranked document discloses about the power iteration that ordered it. `isPageRank == false…</doc>struct RankDisclosure</d>
<d l="16408" e="16417" n="navRelevanceWeight" sc="rw" p="src/graph.h" cx="2" ccx="1" in="2" churn="640" amp="869" r="10">inline std::uint32_t navRelevanceWeight( const Graph&amp; g, NodeId n ) noexcept</d>
<d l="13631" e="13659" n="rankGraphTeleport" sc="rw" p="src/graph.h" cx="5" ccx="8" in="7" churn="640" amp="874" r="11">inline RankedGraph rankGraphTeleport( const Graph&amp; g, const std::vector&lt;float&gt;&amp; p, float alpha = 0.85f )</d>
<d l="1247" e="1247" n="kPowerShellPathPrependScope" sc="rw::oswin" p="src/infra/os_win32_logic.h" layer="infra" churn="20" amp="50" pure="1" r="12">inline constexpr std::string_view kPowerShellPathPrependScope = &quot;in PowerShell, for this window</d>
<!-- demote: a <t> in sigs is a lower same-file sibling past answer row 10, a pointer (p= file, sym= name, r= rank), not the answer -->
<t p="src/infra/os_win32_logic.h" sym="powerShellPathPrependHint" r="13"/>
<d l="1168" e="1168" n="path_prepend_hint" sc="rw::os" p="src/infra/os.h" layer="infra" cx="1" in="1" churn="39" amp="85" r="14">inline std::string path_prepend_hint( std::string_view dir )</d>
<t p="src/infra/os_win32_logic.h" sym="powerShellSingleQuote" r="15"/>
<d l="58" e="90" n="HOT_FILES" p="scripts/optremarks.py" churn="18" amp="80" r="16">HOT_FILES = ( &quot;src/pagerank.cpp&quot;, # the power-iteration loop — G2&apos;s no-allocation scope &quot;src/infra/radixSort.h&quot;, # LSD radix entry points &quot;src/infra/radixSort.inl&quot;, # the counting … [line truncated: 76 more bytes on this line]
<d l="2198" e="2206" n="dynamic_map::leftmost_leaf" p="src/infra/dynamic_map.hpp" layer="infra" cx="2" ccx="1" in="7" churn="7" amp="38" pure="1" r="17">handle_t leftmost_leaf() const</d>
<d l="294" e="299" n="doctorPathPrependLine" p="src/verbs_doctor.h" cx="2" ccx="1" in="2" churn="46" amp="136" r="18">inline std::string doctorPathPrependLine( const std::string&amp; selfPath )</d>
<t p="src/infra/dynamic_map.hpp" sym="reverse_iterator" r="19"/>
<t p="src/verbs_doctor.h" sym="doctorWhichRipwire" r="20"/>
<t p="src/serialize.h" sym="rankByLegendFor" r="21"/>
… [194 more display lines; full output is 23764 bytes on 72 raw line(s)]
`````

## `./build/ripwire . --pack-signatures --top-k=10`

*Body-elided decl skeletons — recounted on this corpus. Measured as element bytes: the <d> signature+doc elements --pack-signatures emits, against the SAME symbols' full <b> bodies from --expand, with the CORPUS-ROOT PREFIX SUBTRACTED FROM BOTH SIDES. That subtraction is the whole methodology and the figure is meaningless without it: the root repeats inside every element's id= and p=, it is not what this verb elides, and counting it makes the headline a function of how deep the checkout happens to sit on disk — on one corpus, three spellings of the same root read 18.6 points apart before the subtraction and agree exactly after it. Root-neutralised on THIS repo: 89.7% fewer bytes at top-10, 88.0% at top-50, 87.8% at top-100 (re-derived 2026-10-10 when the C++ standard-member gate stopped std::vector/std::string calls such as out.push_back() and s.empty() from binding to in-tree namesakes by name: the ranked top-10/50 lost one-line container accessors (svector::push_back, WidePath::c_str, every empty) and gained one-line forwarding helpers and macros (kindIs, ASSUME, formatTo, emitTo) whose signature is nearly the whole body, so less of the set is elidable, from 92.7/88.7/87.6; before that, re-derived 2026-09-20 when the native Windows port landed: src/infra/os_win32.cpp and os_win32_logic.h are ~3,900 lines of new, heavily commented infra that the ranked top-10/50/100 now reach, and their bodies are this ratio's DENOMINATOR, so the figure rises without --pack-signatures eliding anything new, from top-50 87.1. Measured by test/showcasecapturecheck.sh's own recount arm on the combined tree, which is the gate that would otherwise report the drift; before that, re-derived 2026-09-17 at the self-check macro vocabulary rename: VERIFY/VERIFY_TEXT/VERIFY_DEBUG_ONLY/VERIFY_NOT_REACHED/VERIFY_SAME_THREAD/VERIFY_NO_ALIAS*/DYNMAP_VERIFY/DEGRADED_PATH_ALERT renamed to ASSUME/EXPECTS/ENSURES/DASSERT/UNREACHABLE/ASSUME_SAME_THREAD*/ASSUME_NO_ALIAS*/DYNMAP_ASSUME/DISCLOSE (plus new VALIDATE sites) across 839 identifier renames in 179 files, and a hand-written Diagnostics.h/diagnostics.cpp replacing the old ones outright: this moves both WHICH symbols the ranked top-10/50/100 hold and how large their bodies are, from top-50 85.2. A real re-derivation of a corpus that changed, not a tolerance edit; previously re-derived 2026-09-12 when the <d> rows dropped the path-repeating id= for the short sc= scope: the signature side shrank, the bodies did not; before that, 89.5% / 81.8% / 84.3% re-derived 2026-09-10 at the sibs= cap raise: kMaxExpandSibs went 8 -> 100, so --expand's <b> bodies now carry the file context the old cap hid — 89.3% of all sibling names — and the body side is this ratio's DENOMINATOR, so the figure rises without --pack-signatures eliding anything new. Measured on a fixed tree with the top-50 membership and the signature side unchanged: top-50 from 71.0. A real re-derivation of a corpus that changed, not a tolerance edit; previously re-derived 2026-09-09 at the printf-family -> std::print conversion: converting ~1,500 emitter call sites to rw::emitTo/emitRaw/formatTo across 93 files changes how large the ranked symbols' BODIES are, and the body side is this ratio's denominator — top-50 from 72.3. A real re-derivation of a corpus that changed, not a tolerance edit; previously re-derived 2026-09-08 at the confident-zero round, issues #62/#63/#66: that change adds symbols to src/graphlegend.h and the new src/preprocdead.h and re-homes two long comment blocks from call sites onto the helpers they explain, which moves both WHICH symbols the ranked top-50 holds and how large their bodies are — top-50 from 74.0. A real re-derivation of a corpus that changed, not a tolerance edit; previously re-derived 2026-09-06 at the stranger-audit fix round: the doctor, cache-sweep and html-provenance bodies grew this corpus's BODY side, moving top-50 from 75.6 — a real re-derivation, not a tolerance edit; before that, re-derived 2026-09-05 at the capture-audit close: lane L7's P16 caps --expand's sibs= at 8 names, which SHRINKS the body side of this ratio and moved the figure down from 84.5/80.2/80.6 — the V1 2026-08-15 re-center, when sibs=/inc= first grew the body side from 70.0/61.0/63.8, in reverse; both were real re-derivations, not tolerance edits). top-50 is the number to quote, because the sigs payload is top-50 regardless of --top-k and is therefore what THIS command emits. A single small/trivial body can still invert it (signature+doc bigger than the body), like the --format=columnar sibling below. test/showcasecapturecheck.sh (C) re-derives all three from this repo every run, in the same quantity, and fails if the caption and the recount drift apart.*

**wall time: 3.63s**

`````
<ctx schema="ripwire.pack-signatures/v1">
<!-- ripwire pack-signatures schema=ripwire.pack-signatures/v1: the ranked map plus <sigs>
<d l= n= sc= pure=> signature rows. est_tokens=: price as emitted (an upper bound under compact). root=: p= relative to it. pr_iters=N: PageRank iterations. declined=K: K call sites without edges, including inert Elixir quote sites after unquote/unquote_splicing re-entry. external=K: K calls proven  … [line truncated: 1465 more bytes on this line]
<!-- t=modscope=a-file's-MODULE-SCOPE(n=<file-scope>):the-statements-outside-every-named-definition,where-a-top-level-call-and-an-anonymous-callback-body's-calls-live;a-CALLER-never-a-callee(nothing-in-the-source-can-name-it)-with-no-body-to-expand;a-file-with-no-such-call-has-no-such-row -->
<!-- t=type|alias|functype=a-Go-named-type-by-its-written-form:type=a-defined-type-whose-WRITTEN-form-is-not-a-struct/iface/func-literal(type-N-string;type-W-Pair-too,whatever-Pair-is-underneath),alias=type-A=B,functype=type-F-func(...) -->
<!-- t=alias|functype-in-C++-and-.h:alias=using-X=Y(also-templated-or-class-scope)or-namespace-L=lib(defs=X-prints-its-written-target-as-to=),functype=a-typedef-of-a-function-or-function-pointer-type(typedef-void(*F)(int));other-typedefs-read-t=struct -->
<!-- files=4497 symbols=39562 edges=38970 shown=10 est_tokens=6256 ambiguous=3456 unresolved=18664 locality_pinned=11 external=11109 declined=41448 extent_suspect_syms=12 macro_blanked_files=7 skipped_oversize=15 unindexed="txt:81,tsv:53,mod:33,jsonl:26,scm:25,expected:15" unindexed_exts=23 order=important-first -->
<r root="." est_tokens="7080" pr_iters="38">
<f p="src/infra/nodekind.h" layer="infra">
<s t="fn" n="kindIs" sc="rw" k="0.0031">
</s>
</f>
<f p="src/ingest_metrics.h">
<s t="fn" n="nodeTextOf" k="0.0020">
</s>
</f>
<f p="src/model.h">
<s t="fn" n="relForHash" sc="rw" k="0.0020">
</s>
<s t="fn" n="rootRelPath" sc="rw" k="0.0019">
<c n="relForHash"/>
</s>
</f>
<f p="src/infra/Diagnostics.h" layer="infra">
<s t="macro" n="ASSUME" amb="1" k="0.0019">
<c n="RW_ASSUME_" prov="split"/>
<c n="RW_ASSUME_" prov="split"/>
</s>
<s t="macro" n="RW_ASSUME_" overloads="2" k="0.0019">
<c n="RW_CHECK_"/>
… [143 more display lines; full output is 15623 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --outline=rankGraphTeleport --top-k=0`

*Control-flow skeleton of one symbol, payload-only via the new --top-k=0.*

**wall time: 3.39s**

`````
<!-- ripwire pack-signatures schema=ripwire.pack-signatures/v1: the ranked map plus <sigs>
<d l= n= sc= pure=> signature rows. est_tokens=: price as emitted (an upper bound under compact). root=: p= relative to it. -->
<ctx schema="ripwire.pack-signatures/v1" root="." est_tokens="327">
<outline>
<o t="fn" l="13631" p="src/graph.h" n="rankGraphTeleport">
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

**wall time: 2.05s**

`````
<!-- ripwire pack-signatures schema=ripwire.pack-signatures/v1: the ranked map plus <sigs>
<d l= n= sc= pure=> signature rows. est_tokens=: price as emitted (an upper bound under compact). root=: p= relative to it. -->
<ctx schema="ripwire.pack-signatures/v1" root="." est_tokens="327">
<outline>
<o t="fn" l="13631" p="src/graph.h" n="rankGraphTeleport">
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

**wall time: 3.48s**

`````
<ctx schema="ripwire.expand/v1" root="." est_tokens="1217">
<!-- ripwire expand schema=ripwire.expand/v1: full bodies: <bodies shown= total= capped=> of <b t= l= p= n= sibs= sibs_total= sibs_capped= inc=>; <calls>
<c n= l=> resolved callees. window: shown= total= capped= (capped=1 cut). sibs_capped=/inc_capped=: 1 = cut. est_tokens=: price as emitted (an upper bound under compact). root=: p= relative to it. scrubbed=1: this CDATA is not the bytes (]]> split or C0 replaced). redacted=1: a credential shape rewr … [line truncated: 336 more bytes on this line]
<bodies shown="1" total="1" capped="0">
<b t="fn" l="13631" p="src/graph.h" n="rankGraphTeleport" sibs="&lt;file-scope&gt;,DeclinedSiteKind,kNoDeclinedList,Graph,localityKeyAt,ImplementorRow,implementorClosure,LegoClosure,LegoClosureWalk,LegoClosureWalk,take,boundOf,add,expand,legoImplementorClosure,kEdgeName,kEdgeLink,kEdgeKindMask,edgeK … [line truncated: 1665 more bytes on this line]
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
}]]><calls total="4"><c n="biasPrior" l="13590">inline std::vector&lt;float&gt; biasPrior( const Graph&amp; g, const std::vector&lt;float&gt;&amp; p )</c><c n="PROFILE_SCOPE_DESCRIBE" l="1282">#define PROFILE_SCOPE_DESCRIBE( desc )</c><c n="PROFILE_SCOPE_DESCRIBE" l="1296">#define PROFILE_SCOPE_DESC … [line truncated: 289 more bytes on this line]
`````

## `./build/ripwire . --expand=rankGraphTeleport:1-12 --top-k=0`

*Body SLICE: lines 1..12 of the symbol's own body, with lines="lo-hi/total" marking it partial.*

**wall time: 3.29s**

`````
<ctx schema="ripwire.expand/v1" root="." est_tokens="1056">
<!-- ripwire expand schema=ripwire.expand/v1: full bodies: <bodies shown= total= capped=> of <b t= l= p= n= sibs= sibs_total= sibs_capped= inc=>; <calls>
<c n= l=> resolved callees. window: shown= total= capped= (capped=1 cut). sibs_capped=/inc_capped=: 1 = cut. est_tokens=: price as emitted (an upper bound under compact). root=: p= relative to it. scrubbed=1: this CDATA is not the bytes (]]> split or C0 replaced). redacted=1: a credential shape rewr … [line truncated: 336 more bytes on this line]
<bodies shown="1" total="1" capped="0">
<b t="fn" l="13631" p="src/graph.h" n="rankGraphTeleport" lines="1-12/29" sibs="&lt;file-scope&gt;,DeclinedSiteKind,kNoDeclinedList,Graph,localityKeyAt,ImplementorRow,implementorClosure,LegoClosure,LegoClosureWalk,LegoClosureWalk,take,boundOf,add,expand,legoImplementorClosure,kEdgeName,kEdgeLink,kEd … [line truncated: 1681 more bytes on this line]
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
        for( const double value : teleport )]]><calls total="4"><c n="biasPrior" l="13590">inline std::vector&lt;float&gt; biasPrior( const Graph&amp; g, const std::vector&lt;float&gt;&amp; p )</c><c n="PROFILE_SCOPE_DESCRIBE" l="1282">#define PROFILE_SCOPE_DESCRIBE( desc )</c><c n="PROFILE_SCOPE_DE … [line truncated: 332 more bytes on this line]
`````

## `./build/ripwire . --expand=compressBody --top-k=0 --compress`

*Comments stripped + blank runs collapsed — compressBody is the function that implements --compress itself, chosen because it is comment-heavy enough to show a real reduction (the previously captioned symbol had no comments or blank runs, so before/after were byte-identical under a caption promising a difference).*

**wall time: 2.84s**

`````
<ctx schema="ripwire.expand/v1" root="." est_tokens="1952">
<!-- ripwire expand schema=ripwire.expand/v1: full bodies: <bodies shown= total= capped=> of <b t= l= p= n= sibs= sibs_total= sibs_capped= inc=>; <calls>
<c n= l=> resolved callees. window: shown= total= capped= (capped=1 cut). sibs_capped=/inc_capped=: 1 = cut. est_tokens=: price as emitted (an upper bound under compact). root=: p= relative to it. scrubbed=1: this CDATA is not the bytes (]]> split or C0 replaced). redacted=1: a credential shape rewr … [line truncated: 336 more bytes on this line]
<bodies shown="1" total="1" capped="0" compress="1">
<b t="fn" l="4616" p="src/serialize.h" n="compressBody" sibs="&lt;file-scope&gt;,xmlSafeByte,xmlScrubIsLossy,xmlControlCharRef,eraseAbsentClause,spliceClauseAfter,kXmlEscapeByteset,escapeXml,writeMultiRootTable,kMultiRootTableLegend,multiRootTableLegend,xmlCommentText,ctxRootOpen,ctxRootJsonScrubKey … [line truncated: 1996 more bytes on this line]
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
… [170 more display lines; full output is 7456 bytes on 195 raw line(s)]
`````

## `./build/ripwire . --expand=readAckRecords --top-k=0 --no-redact`

*--no-redact: emit bodies verbatim (credential redaction is on by default).*

**wall time: 3.35s**

`````
<ctx schema="ripwire.expand/v1" root="." est_tokens="3099">
<!-- ripwire expand schema=ripwire.expand/v1: full bodies: <bodies shown= total= capped=> of <b t= l= p= n= sibs= sibs_total= sibs_capped= inc=>; <calls>
<c n= l=> resolved callees. window: shown= total= capped= (capped=1 cut). sibs_capped=/inc_capped=: 1 = cut. est_tokens=: price as emitted (an upper bound under compact). root=: p= relative to it. <c via="name">: that callee matched by name alone (receiver unproven); it does NOT mean the edge is fal … [line truncated: 443 more bytes on this line]
<bodies shown="3" total="3" capped="0">
<b t="fn" l="7952" p="src/quality.h" n="readAckRecords" sibs="&lt;file-scope&gt;,kBaselineFile,kMinCloneTokens,kCcxBar,kLocBar,kNestBar,kParamBar,kShortHorizonDays,kShortHorizonMinCommits,kReusedHelperMinFanin,kMinorCcxDelta,kMinorLocDelta,kMinorParamDelta,kMaterialGrowthPct,kSubBarGrowthPct,subBarG … [line truncated: 1784 more bytes on this line]
<![CDATA[inline gtl::btree_map<std::string, AckRecord> readAckRecords( const std::string& path, std::size_t& badLines );]]>
</b>
<b t="fn" l="7954" p="src/quality.h" n="readAckRecords" sibs="&lt;file-scope&gt;,kBaselineFile,kMinCloneTokens,kCcxBar,kLocBar,kNestBar,kParamBar,kShortHorizonDays,kShortHorizonMinCommits,kReusedHelperMinFanin,kMinorCcxDelta,kMinorLocDelta,kMinorParamDelta,kMaterialGrowthPct,kSubBarGrowthPct,subBarG … [line truncated: 1784 more bytes on this line]
<![CDATA[inline gtl::btree_map<std::string, AckRecord> readAckRecords( const std::string& path )
{
    std::size_t ignored = 0;
    return readAckRecords( path, ignored );
}]]><calls total="1"><c n="readAckRecords" l="7960">inline gtl::btree_map&lt;std::string, AckRecord&gt; readAckRecords( const std::string&amp; path, std::size_t&amp; badLines )</c></calls></b><b t="fn" l="7960" p="src/quality.h" n="readAckRecords" sibs="&lt;file-scope&gt;,kBaselineFile,kMinCloneToke … [line truncated: 2095 more bytes on this line]
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
… [46 more display lines; full output is 11812 bytes on 68 raw line(s)]
`````

## `./build/ripwire . --pack-top-n=3 --top-k=0`

*Pack the top-3 ranked symbols' full bodies (deprecated verb; see stderr).*

**wall time: 3.39s**

`````
<ctx schema="ripwire.pack-top-n/v1" root="." est_tokens="17444">
<!-- ripwire pack-top-n schema=ripwire.pack-top-n/v1: the ranked map plus <src p=> bodies of the top-N symbols. window: shown= total= capped= (capped=1 cut). est_tokens=: price as emitted (an upper bound under compact). root=: p= relative to it. <src truncated=1 lines=1-K/T>: cut at a line end at the byte budget; K of its T lines. <src_cut shown= total= capped=1 budget_bytes=>: files served of the top-N asked, the rest over the byte ceiling; unreadable=N not readable. -->
<src_cut shown="1" total="3" capped="1" budget_bytes="65536"/>
<src p="./src/graph.h" truncated="1" lines="1-1043/19366">
<![CDATA[#pragma once

// graph.h — resolve references → graph, build the in-edge CSR for PageRank, and the
// resolved out-edges for serialization. Ranking lives in pagerank.cpp.

#include "model.h"
#include "elixir_resolve.h"      // lexical module/name/arity resolution; reuses cached Binding records
#include "filter.h"              // isTestPath — for the Q2 tested= post-pass
#include "pageview.h"            // LB-H: kImportReachRowCap — the import tier's display cap lives with the rest of the truncation vocabulary
#include "nextverb.h"            // cut-fix E: nextFlag / nextAttrXml — the import tier's importers_next=
#include "graphlegend.h"         // M15: graphGaugeAttrXml/Json + kGraphCountFloorAttrXml/Json — graphCountFloorAttrXml( g ) below
#include "lintrules.h"           // langOfPath / dependencyCapable — the file-language classification
                                 // restrictDependencyHealth() needs (owns the extension table, kept in sync
                                 // by hand with ingest.cpp's kLangTable per its own header comment)
#include "infra/sparseCsr.h"     // first-party infra math (src/infra/)
#include "infra/csrverify.h"     // structural gate, ASSUME'd after every production CSR build
#include "infra/hashutil.h"      // fnv1aAbsorb — internDeclinedList buckets a declined call's candidate list by its bytes
#include "pagerank.h"            // double-precision PageRank kernel over float CSR storage
#include "prconverge.h"          // RankDisclosure — the power iteration's own account, carried with its result
#include "smallvec.h"            // rw::SmallVec — THE ONE ALIAS (src/smallvec.h picks the implementation)
#include "resolve.h"             // P2-D one-hop type narrowing (Rule 1: class membership) — applied before the name-based fallback
#include "receiverevidence.h"    // FE-B: typed receivers RESOLVE; a call nothing proves keeps its rows marked via="name"
#include "ifacedispatch.h"       // lane L6: a call on an interface-typed receiver names its implementors' methods (BaseBound)
#include "langfacts.h"           // langFacts(l): the per-language facts the resolver reads instead of a Lang:: compare
#include "scipoverlay.h"         // SCIP precision overlay (data struct only; parser lives in scip.h)
#include "pincensus.h"           // eval-only per-call-site decision census (--pin-census); inert unless armed
… [1017 more display lines; full output is 66186 bytes on 1043 raw line(s)]
`````

stderr:

`````
ripwire: --pack-top-n is deprecated — use --pack-task/--detail instead (unchanged behavior for now)
`````


---

# assess quality / structure

## `./build/ripwire . --metrics --top-k=10`

*Fan-in/out + complexity annotations on the map.*

**wall time: 6.11s**

`````
<!-- ripwire metrics schema=ripwire.metrics/v1: the ranked map with per-symbol metrics. est_tokens=: price as emitted (an upper bound under compact). root=: p= relative to it. pr_iters=N: PageRank iterations. <inv listed= unlisted=>: files the ranked rows show / do not (sum = files=), each named or counted below. <entry p= n=>: a program entry by its language's convention (C/Go/Rust main, Java/C# static main, a script main its module scope calls, __main__.py), callees as c rows; manifest entries not read. <ls p= n= f=>: n= unshown files under dir p=; f= names its code files, the rest (tests, docs, config, test/doc/example dirs) counted. declined=K: K call sites without edges, including inert Elixir quote sites after unquote/unquote_splicing re-entry. external=K: K calls proven outside the tree, no edge. locality_pinned=K: K calls pinned by locality alone (a guess). extent_suspect_syms=K: K defs failed containment, corpus-wide. macro_blanked_files=K: K files indexed from a macro-blanked re-parse. prov=scip|binding|import|split|final-segment: how that <c> edge bound (absent: one unique name); split = one arm of an amb= pick; final-segment = a qualified type matched by last name only. files=/symbols=: files and symbols indexed; edges= distinct call edges; shown= symbols printed, a merged row counting each def; ambiguous= calls split over several defs, corpus-wide; unresolved= calls with in-tree evidence and no edge (every def language-filtered or unreachable, or binding refused); order= rows by rank (important-first, important-last; (auto:fill) = flipped past a size threshold) or by path (stable). skipped_oversize=K: K files over a size ceiling, not indexed. unindexed=ext:N: N text files of that extension no grammar reads (6 extensions at most). unindexed_exts=E: E such extensions in all, the list cut. <s tested=1>: a non-test row an indexed test transitively reaches (absent otherwise, never 0). <c via="name">: that callee matched by name alone (receiver unproven); it does NOT mean the edge is false. sc=: enclosing scope; the full id is p::sc::n (p= of the row or its <f>) and selectors take it. amb=K: K calls split over several defs. locals_floor=1: locals= is a floor. role=hub: in= is 8 or more. s in= out= cx= ccx= loc= params= nest= cbo= lcom4= amp=: callers, callees, cyclomatic/cognitive complexity, lines, parameters, nesting depth, coupled types, class cohesion, callers + co-changed files. ev=/ev_why=: essential complexity (2+: jumps block extract-method; absent: 1) / the jumps behind it, tag:count. ev_floor=1: ev= is a FLOOR; noreturn calls, macro-hidden exits and unresolved gotos are unseen. layer=: built-in arch layer (game|infra|render|math|audio|ai|test) from a dir name in p=; absent if none. l=N: start line; only on a same-name overload's row, one row per body (bodyless decls fold into overloads=). -->
<!-- t=modscope=a-file's-MODULE-SCOPE(n=<file-scope>):the-statements-outside-every-named-definition,where-a-top-level-call-and-an-anonymous-callback-body's-calls-live;a-CALLER-never-a-callee(nothing-in-the-source-can-name-it)-with-no-body-to-expand;a-file-with-no-such-call-has-no-such-row -->
<!-- t=type|alias|functype=a-Go-named-type-by-its-written-form:type=a-defined-type-whose-WRITTEN-form-is-not-a-struct/iface/func-literal(type-N-string;type-W-Pair-too,whatever-Pair-is-underneath),alias=type-A=B,functype=type-F-func(...) -->
<!-- t=alias|functype-in-C++-and-.h:alias=using-X=Y(also-templated-or-class-scope)or-namespace-L=lib(defs=X-prints-its-written-target-as-to=),functype=a-typedef-of-a-function-or-function-pointer-type(typedef-void(*F)(int));other-typedefs-read-t=struct -->
<!-- files=4497 symbols=39562 edges=38970 shown=10 est_tokens=5011 ambiguous=3456 unresolved=18664 locality_pinned=11 external=11109 declined=41448 extent_suspect_syms=12 macro_blanked_files=7 skipped_oversize=15 unindexed="txt:81,tsv:53,mod:33,jsonl:26,scm:25,expected:15" unindexed_exts=23 order=important-first -->
<r schema="ripwire.metrics/v1" root="." est_tokens="5011" pr_iters="38">
<f p="src/infra/nodekind.h" layer="infra">
<s t="fn" n="kindIs" sc="rw" in="390" out="0" cx="3" ccx="3" role="hub" loc="11" params="2" nest="2" locals="0" locals_floor="1" cbo="0" amp="403" tested="1" k="0.0031" ev="3" ev_floor="1" ev_why="guard-return:1">
</s>
</f>
<f p="src/ingest_metrics.h">
<s t="fn" n="nodeTextOf" in="165" out="0" cx="4" ccx="3" role="hub" loc="9" params="2" nest="1" locals="2" locals_floor="1" cbo="0" amp="300" tested="1" k="0.0020" ev="2" ev_floor="1" ev_why="guard-return:1">
</s>
</f>
<f p="src/model.h">
<s t="fn" n="relForHash" sc="rw" in="48" out="0" cx="17" ccx="13" role="hub" loc="35" params="2" nest="2" locals="2" locals_floor="1" cbo="0" amp="587" tested="1" k="0.0020">
</s>
<s t="fn" n="rootRelPath" sc="rw" in="240" out="1" cx="2" ccx="1" role="hub" loc="5" params="2" nest="1" locals="1" locals_floor="1" cbo="1" amp="779" tested="1" k="0.0019">
<c n="relForHash"/>
</s>
</f>
<f p="src/infra/Diagnostics.h" layer="infra">
<s t="macro" n="ASSUME" in="180" out="2" cx="0" ccx="0" role="hub" loc="2" cbo="2" amp="249" tested="1" amb="1" k="0.0019">
<c n="RW_ASSUME_" prov="split"/>
<c n="RW_ASSUME_" prov="split"/>
</s>
<s t="macro" n="RW_ASSUME_" l="322" in="3" out="1" cx="0" ccx="0" loc="2" cbo="1" amp="72" tested="1" k="0.0019">
<c n="RW_CHECK_"/>
</s>
<s t="macro" n="RW_ASSUME_" l="364" in="3" out="3" cx="0" ccx="0" loc="7" cbo="3" amp="72" tested="1" amb="1" k="0.0019">
… [112 more display lines; full output is 12440 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --deps`

*File->file dependency graph (god-files, cycles).*

**wall time: 5.75s**

`````
<!-- ripwire deps schema=ripwire.deps/v1: file-to-file include/import view, heaviest cone first: <f p= afferent= includes= instab= transitive=>, <health>, <godfiles>, <cycles>. window: shown= total= capped= has_more= next_offset= offset= limit= (capped=1 cut; next_offset= pastes as offset=). graph_partial=1: measured over resolved edges; unresolved imports could add, merge or remove cycles and change ratios. no_file_edges=LANGS: this build resolves almost none of these languages' imports to files (Go only across go.mod replace); counts over them (ca/ce and violations= of the arch verb) are floors over the resolved edges only, and a coupling number absent beside it is unknown, not zero. unmeasured_files=N: files in the no_file_edges= languages; an edge to or from them is in a count only where this build resolved it. masked_files=N: no_file_edges= files, left out of dep_files=/ccd/nccd/shape and propagation_cost (an edgeless one would count as a cone of one; one with an edge has only a floor). health cyclic_files=N: dep_files= files inside an include cycle (all cycles, not only the listed ones); absent at 0. health containment_edges=N: Rust mod x; pairs whose only directive is the declaration, out of transitive=/cycles/ccd/shape, in Ca/Ce. root=: p= relative to it. files=N: files with at least one include/import directive; this listing's denominator (health files= = corpus). violations=N: edges into a file more unstable by over 0.05 (Martin I); only the worst 12 are listed. from=: the including file of a stable-deps violation; it depends on the more unstable to=. gap=: instab of to= minus instab of from=, project includes only; worst first. godfiles f layer=: built-in arch layer (game|infra|render|math|audio|ai|test) from a dir name in p=; absent if none. layer=test only for a file under a test directory whose dependents are all test paths, by path. health dep_files=N: dependency-capable files (dep_langs=), the ccd/acd/nccd denominator. health dep_langs=: the languages dep_files= counts; compare its numbers across builds only when equal. ccd=/acd=/nccd=: Lakos: sum of per-file transitive cones (self incl) / per file / over a balanced tree's. health shape=: tangled when cyclic_files= is 1 in 20 of dep_files= or more, else nccd= below 1 horizontal, from 1 vertical (a heuristic). health lazy_edges=N: in-closure (lazy) include pairs kept OUT of cones, cycles and ccd; absent at 0. cycle size=/cost=: files in that include cycle / size squared, the cycle's share of ccd=. cycle cut=/cutrefs=: SUGGESTED edge to break it (fewest directives) / that edge's directive count; nothing cut. -->
<deps schema="ripwire.deps/v1" files="1723" shown="40" capped="1" total="1723" has_more="1" next_offset="40" offset="0" limit="0" root="." no_file_edges="go,swift,java,cs,php,dart,kt,gd,clj" unmeasured_files="390" graph_partial="1">
<health files="4497" dep_files="3557" ccd="19771" acd="5.6" nccd="0.51" shape="horizontal" cyclic_files="15" masked_files="376" lazy_edges="82" containment_edges="120" dep_langs="cpp,py,ts,go,rs,swift,objc,js,sh,java,rb,cs,c,php,lua,ex,kt"/>
<godfiles total="880" shown="12" capped="1">
<f p="test/lib/clean-env.sh" afferent="248" layer="test"/>
<f p="src/model.h" afferent="135"/>
<f p="src/infra/emit.h" afferent="95" layer="infra"/>
<f p="src/infra/Diagnostics.h" afferent="72" layer="infra"/>
<f p="src/serialize.h" afferent="72"/>
<f p="src/graph.h" afferent="68"/>
<f p="src/infra/sortutil.h" afferent="45" layer="infra"/>
<f p="src/nextverb.h" afferent="41"/>
<f p="src/infra/os.h" afferent="40" layer="infra"/>
<f p="src/filter.h" afferent="39"/>
<f p="test/falseedgefix/jsrebind/src/eng.js" afferent="34" layer="test"/>
<f p="src/infra/namesplit.h" afferent="33" layer="infra"/>
</godfiles>
<stabledeps violations="72">
<v from="src/graph.h" to="src/ifacedispatch.h" gap="0.53"/>
<v from="src/graph.h" to="src/pincensus.h" gap="0.53"/>
<v from="src/graph.h" to="src/restlinks.h" gap="0.53"/>
<v from="test/declinedsitefix/rb/lib/rake/task.rb" to="test/legotransitivefix/rb/task.rb" gap="0.50"/>
<v from="src/gitstamp.h" to="src/quality.h" gap="0.48"/>
<v from="test/ifacedispatchfix/rs/src/render/mod.rs" to="test/ifacedispatchfix/rs/src/render/impls.rs" gap="0.47"/>
<v from="src/docparse.h" to="src/htmldoc.h" gap="0.46"/>
<v from="src/refnames.h" to="src/infra/internedtext.h" gap="0.42"/>
<v from="src/serialize.h" to="src/mapinventory.h" gap="0.35"/>
<v from="src/serialize.h" to="src/countfloor.h" gap="0.33"/>
<v from="src/defattrib.h" to="src/hoprecord.h" gap="0.32"/>
<v from="src/resolve.h" to="src/pythonstdlib.h" gap="0.31"/>
… [871 more display lines; full output is 25127 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --hotspots`

*Complexity x recent git churn (maintenance pain).*

**wall time: 13.61s**

`````
<!-- ripwire hotspots schema=ripwire.hotspots/v1: maintenance pain = churn x ccx over window=: <f p= churn= ccx= score= top= top_ccx= top_l=>; unranked_*= no churn/complexity. window: shown= total= capped= has_more= next_offset= offset= limit= (capped=1 cut; next_offset= pastes as offset=). at=: commit+dirty+shallow. root=: p= relative to it. files=/ranked=: files in the window / those with both churn and complexity; ranked + unranked_no_churn + unranked_no_complexity = files. unranked_no_churn=/unranked_no_complexity=: files left out for no commit in window= / no measured complexity. -->
<!-- extent_suspect_syms=K on a row = K of the file's functions failed an extent/scope containment check (the map, the bundles and the skipped verb mark each one, reasons and all) and are LEFT OUT of that row's ccx=, score= and top=, so its ccx= is a FLOOR of the file's true sum rather than a total. unranked_extent_suspect= counts files with commits whose every scorable function was left out that way (or whose trusted remainder scores 0), so ranked= + unranked_no_churn= + unranked_no_complexity= + unranked_extent_suspect= = files= exactly. Absent = nothing excluded. -->
<hotspots schema="ripwire.hotspots/v1" window="12mo@HEAD" files="4497" ranked="1013" unranked_no_churn="0" unranked_no_complexity="3482" unranked_extent_suspect="2" shown="40" capped="1" total="1013" has_more="1" next_offset="40" offset="0" limit="0" root="." at="0412539b9">
<f p="src/graph.h" churn="640" ccx="6262" score="4007680" top="buildGraph" top_ccx="2002" top_l="9618"/>
<f p="src/serialize.h" churn="486" ccx="2668" score="1296648" top="serialize" top_ccx="310" top_l="3256"/>
<f p="src/quality.h" churn="584" ccx="2080" score="1214720" top="computeDelta" top_ccx="304" top_l="9567"/>
<f p="src/mcpverbs.h" churn="612" ccx="1364" score="834768" top="runBatchSub" top_ccx="142" top_l="6222"/>
<f p="src/main.cpp" churn="478" ccx="1289" score="616142" top="dispatchMainBody" top_ccx="502" top_l="4438"/>
<f p="src/verbs_for.h" churn="380" ccx="1254" score="476520" top="runForLensPass" top_ccx="691" top_l="3356"/>
<f p="src/resolve.h" churn="195" ccx="2296" score="447720" top="buildPreciseIncludeAdjWithContext" top_ccx="93" top_l="5467"/>
<f p="src/cli.h" churn="575" ccx="669" score="384675" top="parseArgs" top_ccx="213" top_l="5459"/>
<f p="src/ingest_binds.h" churn="137" ccx="2424" score="332088" top="bindsVisitNode" top_ccx="102" top_l="7335"/>
<f p="src/verbs_navigate.h" churn="303" ccx="1090" score="330270" top="runVerify" top_ccx="144" top_l="2225"/>
<f p="src/mcp.h" churn="179" ccx="991" score="177389" top="dispatchMcpLine" top_ccx="794" top_l="1146"/>
<f p="src/ingest_sidecap.h" churn="170" ccx="1002" score="170340" top="captureTagsFacts" top_ccx="558" top_l="1857"/>
<f p="src/compactlegend.h" churn="450" ccx="325" score="146250" top="applyCompactDialectOnce" top_ccx="49" top_l="2464"/>
<f p="src/ingest_cache.h" churn="358" ccx="388" score="138904" top="saveCache" top_ccx="108" top_l="3543"/>
<f p="src/verbs_report.h" churn="108" ccx="1188" score="128304" top="runStructureText" top_ccx="270" top_l="3321"/>
<f p="src/verbs_quality.h" churn="135" ccx="853" score="115155" top="runQualityDelta" top_ccx="352" top_l="1757"/>
<f p="src/ingest_valuerefs.h" churn="76" ccx="1495" score="113620" top="classify" top_ccx="119" top_l="2450"/>
<f p="src/forliteral.h" churn="59" ccx="1777" score="104843" top="renderForLiteral" top_ccx="277" top_l="4202"/>
<f p="src/receiverevidence.h" churn="90" ccx="1136" score="102240" top="bareClassAt" top_ccx="77" top_l="715"/>
<f p="src/crossref.h" churn="97" ccx="1017" score="98649" top="streamBlobs" top_ccx="43" top_l="538"/>
<f p="src/gitmine.h" churn="103" ccx="738" score="76014" top="applyCoChangeBoost" top_ccx="95" top_l="3600"/>
<f p="src/lexical.h" churn="85" ccx="889" score="75565" top="lexicalScoresTiered" top_ccx="509" top_l="501"/>
<f p="src/ingest_relations.h" churn="87" ccx="737" score="64119" top="captureFields" top_ccx="99" top_l="1419"/>
<f p="src/valuerefindex.h" churn="69" ccx="897" score="61893" top="resolveName" top_ccx="47" top_l="1948"/>
<f p="src/model.h" churn="327" ccx="160" score="52320" top="shadowSuppressedSite" top_ccx="14" top_l="2794"/>
<f p="src/ingest_names.h" churn="71" ccx="698" score="49558" top="finalTypeSegment" top_ccx="26" top_l="1271"/>
<f p="src/ingest_crawl.h" churn="87" ccx="545" score="47415" top="collectSources" top_ccx="91" top_l="1927"/>
… [14 more display lines; full output is 5790 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --clones`

*Token-normalized duplicate bodies.*

**wall time: 3.75s**

`````
<!-- ripwire clones schema=ripwire.clones/v1: similar normalized-token bodies: <group type=2|3 gid= tokens= n= similarity=> of <f n= p=>; dup_loc=/dup_pct=. window: shown= total= capped= has_more= next_offset= offset= limit= (capped=1 cut; next_offset= pastes as offset=). root=: p= relative to it. groups=/type3=: Type-2 and Type-3 group totals over all groups; total= is their sum. exempt_groups=N: groups whose members all sit on fixture/shell-runner paths quality-delta duplication ignores. idiom_groups=/demoted_groups=: groups of one recognized idiom / those quality-delta demotes to minor; floors. clone_groups=N: clusters after merging pairs (rows sharing gid=); a floor under type3_capped=1. total_loc=N: lines of every function body the detector considered; dup_pct= is dup_loc= over it. group exempt=fixture|shell-runner: every member is on such a path; quality-delta duplication ignores it. group idiom=: the recognized shape every member spells: threshold-ladder, switch-name-table, builder-chain. -->
<clones schema="ripwire.clones/v1" groups="158" type3="810" exempt_groups="635" idiom_groups="20" demoted_groups="12" clone_groups="424" dup_loc="8539" total_loc="301968" dup_pct="2.8" shown="80" capped="1" total="968" has_more="1" next_offset="80" offset="0" limit="0" root=".">
<group type="2" gid="49" tokens="338" n="3">
<f n="rw_is_ripwire_call" p="hooks/ripwire-claude-route.sh:187"/>
<f n="rw_is_ripwire_call" p="hooks/ripwire-codex-route.sh:104"/>
<f n="rw_is_ripwire_call" p="hooks/ripwire-nudge.sh:623"/>
</group>
<group type="2" gid="266" tokens="213" n="2" exempt="shell-runner">
<f n="call_sites" p="test/declinecheck.sh:116"/>
<f n="call_sites" p="test/usesselectorcheck.sh:49"/>
</group>
<group type="2" gid="355" tokens="211" n="4" exempt="shell-runner">
<f n="batch_sub" p="test/mcpclidiffcheck.sh:64"/>
<f n="batch_sub" p="test/mcptranchecheck.sh:55"/>
<f n="batch_sub" p="test/mcpw2fixcheck.sh:52"/>
<f n="batch_sub" p="test/mcpw3fixcheck.sh:51"/>
</group>
<group type="2" gid="225" tokens="210" n="2" exempt="shell-runner">
<f n="mcpfor" p="test/anchorhonestycheck.sh:35"/>
<f n="mcpfor" p="test/foranchornscheck.sh:29"/>
</group>
<group type="2" gid="377" tokens="198" n="2" exempt="shell-runner">
<f n="classify" p="test/preludevetocheck.sh:41"/>
<f n="classify" p="test/rustmacropathcheck.sh:39"/>
</group>
<group type="2" gid="261" tokens="175" n="2" exempt="shell-runner">
<f n="mcp" p="test/pathfewestcheck.sh:320"/>
<f n="mcp" p="test/pathroutecheck.sh:468"/>
</group>
<group type="2" gid="48" tokens="163" n="3">
… [308 more display lines; full output is 16278 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --cochange`

*Files that change together in git (hidden coupling).*

**wall time: 10.55s**

`````
<!-- ripwire cochange schema=ripwire.cochange/v1: files that change together in git: <pair a= b= together= deg= conf_ab= conf_ba= surprising=>, or for of= <f p= together= conf_rev=>. window: shown= total= capped= has_more= next_offset= offset= limit= (capped=1 cut; next_offset= pastes as offset=). at=: commit+dirty+shallow. root=: p= relative to it. pairs=N: file pairs with 3+ shared commits in window= (after min_recur), surprising or not. sub_windows=N: equal-commit-count slices of window=; the denominator of recur=. driver=a|b: the side whose changes best imply the other's, look there first; absent on a tie. recur=K: slices of sub_windows= the pair co-changed in; 1 = one burst, not a standing coupling. -->
<cochange schema="ripwire.cochange/v1" pairs="5197" window="18mo@HEAD" sub_windows="3" shown="30" capped="1" total="5197" has_more="1" next_offset="30" offset="0" limit="0" root="." at="0412539b9">
<pair a="src/aliasdef.h" b="src/ingest_sidecap.h" together="5" deg="1.00" conf_ab="1.00" conf_ba="0.03" driver="a" recur="1" surprising="1"/>
<pair a="test/headsnapcachecheck.sh" b="test/qsnapcachecheck.sh" together="5" deg="1.00" conf_ab="1.00" conf_ba="1.00" recur="3" surprising="1"/>
<pair a="src/layout.h" b="test/layoutfix/attrfields.h" together="4" deg="1.00" conf_ab="0.14" conf_ba="1.00" driver="b" recur="1" surprising="1"/>
<pair a="src/foraliashop.h" b="src/verbs_navigate.h" together="4" deg="1.00" conf_ab="1.00" conf_ba="0.01" driver="a" recur="1" surprising="1"/>
<pair a="test/gatecountcheck.sh" b="test/regression.sh" together="3" deg="1.00" conf_ab="1.00" conf_ba="0.00" driver="a" recur="2" surprising="1"/>
<pair a="test/pincensuscheck.sh" b="test/scipjoincheck.sh" together="3" deg="1.00" conf_ab="0.38" conf_ba="1.00" driver="b" recur="2" surprising="1"/>
<pair a="src/binstale.h" b="src/crossref.h" together="3" deg="1.00" conf_ab="1.00" conf_ba="0.04" driver="a" recur="2" surprising="1"/>
<pair a="src/ingest_valuerefs.h" b="src/pydottedpath.h" together="3" deg="1.00" conf_ab="0.04" conf_ba="1.00" driver="b" recur="1" surprising="1"/>
<pair a="src/verbs_report.h" b="test/fileset_unit.cpp" together="3" deg="1.00" conf_ab="0.03" conf_ba="1.00" driver="b" recur="1" surprising="1"/>
<pair a="test/fnslotcpp2/dep.cc" b="test/fnslotcpp2/use_bnd.cc" together="3" deg="1.00" conf_ab="1.00" conf_ba="0.75" driver="a" recur="1" surprising="1"/>
<pair a="test/grepcheck.sh" b="test/grepcontextcheck.sh" together="3" deg="1.00" conf_ab="0.50" conf_ba="1.00" driver="b" recur="1" surprising="1"/>
<pair a="test/grepcheck.sh" b="test/grepscancheck.sh" together="3" deg="1.00" conf_ab="0.50" conf_ba="1.00" driver="b" recur="1" surprising="1"/>
<pair a="test/grepcontextcheck.sh" b="test/grepscancheck.sh" together="3" deg="1.00" conf_ab="1.00" conf_ba="1.00" recur="1" surprising="1"/>
<pair a="src/ingest_cache.h" b="src/refnames.h" together="3" deg="1.00" conf_ab="0.01" conf_ba="1.00" driver="b" recur="1" surprising="1"/>
<pair a="src/graph.h" b="test/fileset_unit.cpp" together="3" deg="1.00" conf_ab="0.00" conf_ba="1.00" driver="b" recur="1" surprising="1"/>
<pair a="src/arch.h" b="test/fileset_unit.cpp" together="3" deg="1.00" conf_ab="0.08" conf_ba="1.00" driver="b" recur="1" surprising="1"/>
<pair a="test/cachesplitcheck.sh" b="test/evictioncheck.sh" together="3" deg="1.00" conf_ab="1.00" conf_ba="0.23" driver="a" recur="2" surprising="1"/>
<pair a="test/elixircheck.sh" b="test/elixirsemanticcheck.sh" together="3" deg="1.00" conf_ab="0.13" conf_ba="1.00" driver="b" recur="3" surprising="1"/>
<pair a="src/accessshape.h" b="test/accessshapefix/walks.cpp" together="3" deg="1.00" conf_ab="0.60" conf_ba="1.00" driver="b" recur="1" surprising="1"/>
<pair a="src/fieldaffinity.h" b="test/accessshapefix/walks.cpp" together="3" deg="1.00" conf_ab="0.33" conf_ba="1.00" driver="b" recur="1" surprising="1"/>
<pair a="test/mcpslicecheck.sh" b="test/mcpverbscheck.sh" together="3" deg="1.00" conf_ab="1.00" conf_ba="0.16" driver="a" recur="2" surprising="1"/>
<pair a="test/rubyrecvcheck.sh" b="test/rubyrequirecheck.sh" together="3" deg="1.00" conf_ab="0.50" conf_ba="1.00" driver="b" recur="1" surprising="1"/>
<pair a="test/qschemetripcheck.sh" b="test/rubyrequirecheck.sh" together="3" deg="1.00" conf_ab="0.01" conf_ba="1.00" driver="b" recur="1" surprising="1"/>
<pair a="test/luacheck.sh" b="test/phpcheck.sh" together="3" deg="1.00" conf_ab="0.75" conf_ba="1.00" driver="b" recur="2" surprising="1"/>
<pair a="test/gatecountcheck.sh" b="test/manifestcheck.sh" together="3" deg="1.00" conf_ab="1.00" conf_ba="0.23" driver="a" recur="2" surprising="1"/>
<pair a="bench/agentloop/analyze.py" b="bench/agentloop/run_agentloop.py" together="8" deg="0.89" conf_ab="0.89" conf_ba="0.44" driver="a" recur="1" surprising="1"/>
<pair a="src/cli.h" b="src/sarif.h" together="6" deg="0.86" conf_ab="0.01" conf_ba="0.86" driver="b" recur="2" surprising="1"/>
<pair a="scripts/merge_main.sh" b="test/mergemaincheck.sh" together="6" deg="0.86" conf_ab="0.75" conf_ba="0.86" driver="b" recur="1" surprising="1"/>
<pair a="src/ingest_model.h" b="src/model.h" together="50" deg="0.83" conf_ab="0.83" conf_ba="0.16" driver="a" recur="3" surprising="1"/>
<pair a="hooks/ripwire-claude-route.sh" b="hooks/ripwire-codex-route.sh" together="20" deg="0.83" conf_ab="0.83" conf_ba="0.83" recur="3" surprising="1"/>
</cochange>
`````

## `./build/ripwire . --hotspots --since="2 weeks ago"`

*Hotspots scoped to RECENT churn (the regression lens).*

**wall time: 16.35s**

`````
<!-- ripwire hotspots schema=ripwire.hotspots/v1: maintenance pain = churn x ccx over window=: <f p= churn= ccx= score= top= top_ccx= top_l=>; unranked_*= no churn/complexity. window: shown= total= capped= has_more= next_offset= offset= limit= (capped=1 cut; next_offset= pastes as offset=). at=: commit+dirty+shallow. root=: p= relative to it. files=/ranked=: files in the window / those with both churn and complexity; ranked + unranked_no_churn + unranked_no_complexity = files. unranked_no_churn=/unranked_no_complexity=: files left out for no commit in window= / no measured complexity. -->
<hotspots schema="ripwire.hotspots/v1" window="2 weeks ago" files="4497" ranked="315" unranked_no_churn="3954" unranked_no_complexity="228" shown="40" capped="1" total="315" has_more="1" next_offset="40" offset="0" limit="0" root="." at="0412539b9">
<f p="src/graph.h" churn="124" ccx="6262" score="776488" top="buildGraph" top_ccx="2002" top_l="9618"/>
<f p="src/serialize.h" churn="68" ccx="2668" score="181424" top="serialize" top_ccx="310" top_l="3256"/>
<f p="src/verbs_for.h" churn="129" ccx="1254" score="161766" top="runForLensPass" top_ccx="691" top_l="3356"/>
<f p="src/mcpverbs.h" churn="107" ccx="1364" score="145948" top="runBatchSub" top_ccx="142" top_l="6222"/>
<f p="src/quality.h" churn="67" ccx="2080" score="139360" top="computeDelta" top_ccx="304" top_l="9567"/>
<f p="src/resolve.h" churn="47" ccx="2296" score="107912" top="buildPreciseIncludeAdjWithContext" top_ccx="93" top_l="5467"/>
<f p="src/forliteral.h" churn="56" ccx="1777" score="99512" top="renderForLiteral" top_ccx="277" top_l="4202"/>
<f p="src/verbs_navigate.h" churn="41" ccx="1090" score="44690" top="runVerify" top_ccx="144" top_l="2225"/>
<f p="src/cli.h" churn="54" ccx="669" score="36126" top="parseArgs" top_ccx="213" top_l="5459"/>
<f p="src/forreexport.h" churn="38" ccx="931" score="35378" top="genPathOf" top_ccx="92" top_l="2298"/>
<f p="src/verbs_report.h" churn="27" ccx="1188" score="32076" top="runStructureText" top_ccx="270" top_l="3321"/>
<f p="src/ingest_valuerefs.h" churn="21" ccx="1495" score="31395" top="classify" top_ccx="119" top_l="2450"/>
<f p="src/main.cpp" churn="23" ccx="1289" score="29647" top="dispatchMainBody" top_ccx="502" top_l="4438"/>
<f p="src/forunused.h" churn="21" ccx="1359" score="28539" top="classifyFiles" top_ccx="111" top_l="2909"/>
<f p="src/ingest_binds.h" churn="11" ccx="2424" score="26664" top="bindsVisitNode" top_ccx="102" top_l="7335"/>
<f p="src/compactlegend.h" churn="75" ccx="325" score="24375" top="applyCompactDialectOnce" top_ccx="49" top_l="2464"/>
<f p="src/ingest_cache.h" churn="57" ccx="388" score="22116" top="saveCache" top_ccx="108" top_l="3543"/>
<f p="src/receiverevidence.h" churn="19" ccx="1136" score="21584" top="bareClassAt" top_ccx="77" top_l="715"/>
<f p="src/ingest_sidecap.h" churn="21" ccx="1002" score="21042" top="captureTagsFacts" top_ccx="558" top_l="1857"/>
<f p="src/verbs_quality.h" churn="21" ccx="853" score="17913" top="runQualityDelta" top_ccx="352" top_l="1757"/>
<f p="src/gitmine.h" churn="22" ccx="738" score="16236" top="applyCoChangeBoost" top_ccx="95" top_l="3600"/>
<f p="src/lexical.h" churn="18" ccx="889" score="16002" top="lexicalScoresTiered" top_ccx="509" top_l="501"/>
<f p="src/mcp.h" churn="16" ccx="991" score="15856" top="dispatchMcpLine" top_ccx="794" top_l="1146"/>
<f p="src/exemplarfamily.h" churn="20" ccx="733" score="14660" top="openSpanAfter" top_ccx="37" top_l="1291"/>
<f p="src/recall.h" churn="21" ccx="481" score="10101" top="buildRecall" top_ccx="45" top_l="2261"/>
<f p="src/subjectanchor.h" churn="33" ccx="303" score="9999" top="routeAnchorHasSourceDef" top_ccx="28" top_l="461"/>
<f p="src/model.h" churn="60" ccx="160" score="9600" top="shadowSuppressedSite" top_ccx="14" top_l="2794"/>
<f p="src/forpage.h" churn="27" ccx="329" score="8883" top="forCandidatePageDoc" top_ccx="99" top_l="257"/>
… [13 more display lines; full output is 5146 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --arch=test/archfix/rules.txt`

*Enforce layering rules (exit 2 on violation) — run against the repo's own test fixture rules.*

**wall time: 2.92s**

`````
<!-- ripwire arch schema=ripwire.arch/v1: layering rules fit: allowed/denied file-to-file edges, each violation a row. graph_partial=1: measured over resolved edges; unresolved imports could add, merge or remove cycles and change ratios. no_file_edges=LANGS: this build resolves almost none of these languages' imports to files (Go only across go.mod replace); counts over them (ca/ce and violations= of the arch verb) are floors over the resolved edges only, and a coupling number absent beside it is unknown, not zero. unmeasured_files=N: files in the no_file_edges= languages; an edge to or from them is in a count only where this build resolved it. masked_files=N: no_file_edges= files, left out of dep_files=/ccd/nccd/shape and propagation_cost (an edgeless one would count as a cone of one; one with an edge has only a floor). -->
<arch schema="ripwire.arch/v1" layers="2" rules="1" pathRules="0" violations="0" baselined="0" new_violations="0" no_file_edges="go,swift,java,cs,php,dart,kt,gd,clj" unmeasured_files="390" graph_partial="1">
<metrics modules="1363" typed_modules="668" zone_pain="365" zone_useless="3" zone_ok="135" zone_na="623" zone_unknown="237" propagation_cost="0.002" masked_files="376" note="Martin Ca/Ce/I/A/D + zone (main-sequence heuristic, no independent outcome-based validation — folklore, not proof) + reachab … [line truncated: 632 more bytes on this line]
<m path="." ca="0" ce="0" types="0" abstract="0" I="0.00" A="0.00" D="1.00" zone="n/a" reachable="1" isolated="1"/>
<m path="./.codex-plugin" ca="0" ce="0" types="0" abstract="0" I="0.00" A="0.00" D="1.00" zone="n/a" reachable="1" isolated="1"/>
<m path="./.github" ca="0" ce="0" types="0" abstract="0" I="0.00" A="0.00" D="1.00" zone="n/a" reachable="1" isolated="1"/>
<m path="./.github/workflows" ca="0" ce="0" types="0" abstract="0" I="0.00" A="0.00" D="1.00" zone="n/a" reachable="1" isolated="1"/>
<m path="./bench" ca="0" ce="1" types="24" abstract="2" I="1.00" A="0.08" D="0.08" zone="ok" reachable="1"/>
<m path="./bench/agentloop" ca="0" ce="0" types="0" abstract="0" I="0.00" A="0.00" D="1.00" zone="n/a" reachable="1" isolated="1"/>
<m path="./bench/agentloop/editsuite" ca="0" ce="0" types="0" abstract="0" I="0.00" A="0.00" D="1.00" zone="n/a" reachable="1" isolated="1"/>
<m path="./bench/agentloop/editsuite/fixture" ca="0" ce="0" types="2" abstract="0" I="0.00" A="0.00" D="1.00" zone="pain" reachable="1" isolated="1"/>
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
<m path="./bench/h4fixtures/csharp" types="3" abstract="0" A="0.00" zone="unknown" no_file_edges="cs"/>
<m path="./bench/h4fixtures/go" types="1" abstract="0" A="0.00" zone="unknown" no_file_edges="go"/>
<m path="./bench/h4fixtures/go2" types="1" abstract="0" A="0.00" zone="unknown" no_file_edges="go"/>
… [1338 more display lines; full output is 188955 bytes on 1 raw line(s)]
`````

stderr:

`````
ripwire arch: 390 file(s) in go,swift,java,cs,php,dart,kt,gd,clj: this build resolves almost none of their imports to files, so an edge through one was mostly never judged: violations= is a floor
`````

## `./build/ripwire . --lint`

*Built-in AST checks (c-cast, goto, unsafe-c-fn, ...).*

**wall time: 5.67s**

`````
<!-- ripwire lint schema=ripwire.lint/v1: AST-only checks, facts not gates: <rule name= count= shown_rows= rows_capped= count_capped=> of <f rule= p= in=>. window: shown= total= capped= has_more= next_offset= offset= limit= (capped=1 cut; next_offset= pastes as offset=). findings_capped=/rows_capped=/count_capped=: 1 = cut. counts_floor=1: every count is a FLOOR, never a total. root=: p= relative to it. findings=N: findings over the printed rules; a floor when findings_capped=1. findings_next=: the call counting the floored rules' rest (count_capped=1 rules only, 10x per-rule budget). -->
<lint schema="ripwire.lint/v1" findings="8351" shown="669" capped="1" total="8351" has_more="1" next_offset="669" offset="0" limit="0" counts_floor="1" findings_capped="1" findings_next="--lint --lint-select=magic-number --lint-max-per-rule=50000" root=".">
<rule name="c-style-cast" count="693" shown_rows="74" rows_capped="1"/>
<rule name="goto" count="17" shown_rows="0" rows_capped="1"/>
<rule name="do-while" count="20" shown_rows="0" rows_capped="1"/>
<rule name="unsafe-c-fn" count="0" shown_rows="0" rows_capped="0"/>
<rule name="weak-crypto" count="0" shown_rows="0" rows_capped="0"/>
<rule name="redundant-parens" count="0" shown_rows="0" rows_capped="0"/>
<rule name="suspicious-semicolon" count="0" shown_rows="0" rows_capped="0"/>
<rule name="typedef-over-using" count="49" shown_rows="0" rows_capped="1"/>
<rule name="magic-number" count="430" shown_rows="244" rows_capped="1" count_capped="1"/>
<rule name="empty-catch" count="1" shown_rows="0" rows_capped="1"/>
<rule name="self-assign" count="3" shown_rows="0" rows_capped="1"/>
<rule name="large-function" count="371" shown_rows="33" rows_capped="1"/>
<rule name="deep-nesting" count="492" shown_rows="46" rows_capped="1"/>
<rule name="inconsistent-return" count="2" shown_rows="0" rows_capped="1"/>
<rule name="unreachable-code" count="5" shown_rows="0" rows_capped="1"/>
<rule name="naming-short" count="2148" shown_rows="77" rows_capped="1"/>
<rule name="naming-wordy" count="444" shown_rows="16" rows_capped="1"/>
<rule name="naming-series" count="979" shown_rows="0" rows_capped="1"/>
<rule name="naming-underscore" count="2" shown_rows="0" rows_capped="1"/>
<rule name="naming-case" count="84" shown_rows="0" rows_capped="1"/>
<rule name="naming-predicate" count="1" shown_rows="0" rows_capped="1"/>
<rule name="naming-setter" count="3" shown_rows="0" rows_capped="1"/>
<rule name="naming-confusable" count="1056" shown_rows="32" rows_capped="1"/>
<rule name="naming-uninformative" count="0" shown_rows="0" rows_capped="0"/>
<rule name="atom-comma-operator" count="4" shown_rows="0" rows_capped="1"/>
<rule name="atom-embedded-crement" count="220" shown_rows="10" rows_capped="1"/>
<rule name="atom-assign-as-value" count="87" shown_rows="11" rows_capped="1"/>
<rule name="atom-nested-ternary" count="313" shown_rows="21" rows_capped="1"/>
… [681 more display lines; full output is 70804 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --lint-rules=test/lintrulesfix/rules`

*User lint rules (YAML, ast-grep style) from a directory.*

**wall time: 2.28s**

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
[math degraded] lint-rules: malformed rule file skipped  (lintrules.h:493, auto rw::parseLintRuleFile(const std::string &, std::string_view, std::vector<LintRule> &)::(anonymous class)::operator()(std::size_t, const char *) const — logged once per site)
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

**wall time: 3.15s**

`````
<!-- ripwire communities schema=ripwire.communities/v1: call-graph modules (Louvain): <community id= size= dir= label=> of <member t= n= p=>; drill= the verb taking a row's id=; shown_modules=/shown_bridges= <community>/<bridge> rows listed; bridges= community pairs joined by a call edge; isolated= symbols with no call edge: isolated_doc= doc sections, isolated_decl= other bodyless, isolated_header= other header defs, isolated_source= the rest; modules= modules of 2+ symbols; connected_singletons= 1-symbol modules with a call edge; symbols= indexed symbols. window: shown= total= capped= has_more= next_offset= offset= limit= (capped=1 cut; next_offset= pastes as offset=). modules_capped=/bridges_capped=: 1 = cut. counts_floor=1: every count is a FLOOR, never a total. graph_ambiguous=/graph_unresolved=: resolver gauge. graph_unindexed=N: N files no grammar could read (the map header's unindexed=); their calls raise neither gauge. root=: p= relative to it. pr_iters=N: PageRank iterations. <bridge a= b=>: two module ids joined by call edges. from_label=/to_label=: the label= of a=/b=. <bridge edges=>: call edges between the two, either direction. -->
<communities schema="ripwire.communities/v1" drill="--community=ID" modules="4675" shown_modules="30" modules_capped="1" bridges="7240" shown_bridges="12" bridges_capped="1" isolated="18367" isolated_decl="5260" isolated_header="3129" isolated_source="4394" isolated_doc="5584" connected_singletons=" … [line truncated: 193 more bytes on this line]
<community id="5422" size="1022" dir="src" label="src::rootRelPath@model.h:2519:209682 [render,append,write]" shown="5" capped="1">
<member t="fn" n="rootRelPath" p="src/model.h:2519"/>
<member t="fn" n="escapeXml" p="src/serialize.h:185"/>
<member t="fn" n="formatTo" p="src/infra/emit.h:141"/>
<member t="fn" n="utf8SeqLen" p="src/infra/jsonesc.h:59"/>
<member t="fn" n="rootRelativeUri" p="src/sarif.h:147"/>
</community>
<community id="1941" size="754" dir="src" label="src::emitTo@infra/emit.h:53:2760 [write,run,emit]" shown="5" capped="1">
<member t="fn" n="emitTo" p="src/infra/emit.h:53"/>
<member t="fn" n="emitTo" p="src/infra/emit.h:78"/>
<member t="fn" n="emitRaw" p="src/infra/emit.h:104"/>
<member t="fn" n="escapeMcp" p="src/infra/jsonesc.h:247"/>
<member t="fn" n="jsonStr" p="src/serialize.h:10736"/>
</community>
<community id="5415" size="568" dir="src" label="src::kindIs@infra/nodekind.h:46:3271 [push,emit,collect]" shown="5" capped="1">
<member t="fn" n="kindIs" p="src/infra/nodekind.h:46"/>
<member t="fn" n="nodeTextOf" p="src/ingest_metrics.h:161"/>
<member t="fn" n="fieldChild" p="src/infra/fieldid.h:223"/>
<member t="fn" n="forEachChild" p="src/infra/tschildren.h:89"/>
<member t="fn" n="parentOf" p="src/infra/tsparent.h:155"/>
</community>
<community id="5394" size="269" dir="src" label="src::DISCLOSE@infra/Diagnostics.h:616:43369 [read,run,compute]" shown="5" capped="1">
<member t="macro" n="DISCLOSE" p="src/infra/Diagnostics.h:616"/>
<member t="fn" n="shSingleQuote" p="src/infra/shquote.h:19"/>
<member t="fn" n="gitOneLine" p="src/quality.h:2092"/>
<member t="fn" n="gitCmd" p="src/gitcmd.h:174"/>
<member t="fn" n="readAllOfStream" p="src/docparse.h:266"/>
</community>
… [191 more display lines; full output is 16753 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --zoom`

*Nested module hierarchy (multi-level Louvain) + cross-module bridges — levels_shown="2" of levels= BY DEFAULT over the 40 largest top modules (~8 KB, where the whole tree is ~220 KB); a module AT the cut carries children=.*

**wall time: 3.08s**

`````
<!-- ripwire zoom schema=ripwire.zoom/v1: nested module hierarchy: <module level= id= size= dir= shown= capped=> of <member t= n= p=>; levels_shown= of levels= printed; symbols= = isolated= + size= of all top_modules=. window: shown= total= capped= has_more= next_offset= offset= limit= (capped=1 cut; next_offset= pastes as offset=). counts_floor=1: every count is a FLOOR, never a total. graph_ambiguous=/graph_unresolved=: resolver gauge. graph_unindexed=N: N files no grammar could read (the map header's unindexed=); their calls raise neither gauge. pr_iters=N: PageRank iterations. children=K: K child modules below the levels_shown= cut, unprinted. next=: the one pasteable follow-up. -->
<zoom schema="ripwire.zoom/v1" levels="5" levels_shown="2" top_modules="1626" symbols="39563" isolated="18367" shown="40" capped="1" total="1626" has_more="1" next_offset="40" offset="0" limit="0" pr_iters="38" graph_ambiguous="3456" graph_unresolved="18664" graph_unindexed="286" counts_floor="1" ne … [line truncated: 24 more bytes on this line]
<module level="4" id="1829" size="9739" dir="./src">
<module level="3" id="1830" size="9065" dir="./src" children="17">
</module>
<module level="3" id="1842" size="610" dir="./src/infra" children="5">
</module>
<module level="3" id="5233" size="64" dir="./src" children="2">
</module>
</module>
<module level="4" id="4798" size="2324" dir="./test">
<module level="3" id="10016" size="1644" dir="./test" children="5">
</module>
<module level="3" id="4800" size="506" dir="./test" children="2">
</module>
<module level="3" id="10794" size="174" dir="./test" children="2">
</module>
</module>
<module level="4" id="1583" size="509" dir="./bench/agentloop">
<module level="3" id="1646" size="361" dir="./test" children="6">
</module>
<module level="3" id="1583" size="148" dir="./bench/agentloop" children="3">
</module>
</module>
<module level="4" id="726" size="315" dir="./docs">
<module level="3" id="726" size="315" dir="./docs" children="1">
</module>
</module>
<module level="4" id="17121" size="106" dir="./test/ownerhopfix/py/pkg">
<module level="3" id="17126" size="106" dir="./test/ownerhopfix/py/pkg" children="1">
… [143 more display lines; full output is 7746 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --zoom --zoom-levels=3`

*The restoring knob: --zoom-levels=N prints N levels (0 = the whole tree); here three, ~11 KB.*

**wall time: 3.28s**

`````
<!-- ripwire zoom schema=ripwire.zoom/v1: nested module hierarchy: <module level= id= size= dir= shown= capped=> of <member t= n= p=>; levels_shown= of levels= printed; symbols= = isolated= + size= of all top_modules=. window: shown= total= capped= has_more= next_offset= offset= limit= (capped=1 cut; next_offset= pastes as offset=). counts_floor=1: every count is a FLOOR, never a total. graph_ambiguous=/graph_unresolved=: resolver gauge. graph_unindexed=N: N files no grammar could read (the map header's unindexed=); their calls raise neither gauge. pr_iters=N: PageRank iterations. children=K: K child modules below the levels_shown= cut, unprinted. next=: the one pasteable follow-up. -->
<zoom schema="ripwire.zoom/v1" levels="5" levels_shown="3" top_modules="1626" symbols="39563" isolated="18367" shown="40" capped="1" total="1626" has_more="1" next_offset="40" offset="0" limit="0" pr_iters="38" graph_ambiguous="3456" graph_unresolved="18664" graph_unindexed="286" counts_floor="1" ne … [line truncated: 40 more bytes on this line]
<module level="4" id="1829" size="9739" dir="./src">
<module level="3" id="1830" size="9065" dir="./src">
<module level="2" id="1832" size="7651" dir="./src" children="100">
</module>
<module level="2" id="5296" size="563" dir="./src" children="28">
</module>
<module level="2" id="5035" size="256" dir="./src" children="13">
</module>
<module level="2" id="6907" size="55" dir="./src/infra" children="5">
</module>
<module level="2" id="5027" size="135" dir="./src" children="10">
</module>
<module level="2" id="5669" size="74" dir="./src" children="6">
</module>
<module level="2" id="5650" size="58" dir="./src" children="5">
</module>
<module level="2" id="6210" size="67" dir="./src" children="6">
</module>
<module level="2" id="5316" size="45" dir="./src" children="4">
</module>
<module level="2" id="5859" size="39" dir="./src" children="2">
</module>
<module level="2" id="9244" size="30" dir="./src" children="3">
</module>
<module level="2" id="9070" size="18" dir="./src" children="2">
</module>
<module level="2" id="6586" size="19" dir="./test/cppqualtmplfix" children="2">
</module>
… [305 more display lines; full output is 13726 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --report`

*Architecture summary (modules, god-files, cycles) as markdown.*

**wall time: 3.18s**

`````
<!-- ripwire markdown: no run of 4-or-more backticks in this output — safe to embed inside a wider fence -->

# ripwire architecture report

4497 files · 39563 symbols · 38970 edges · 4675 modules (18367 call-graph isolated)

Root: `.`

Call-graph isolate provenance: 5260 declaration, 3129 header, 4394 source, 5584 document; 0 connected Louvain singletons

## Modules (call-graph clusters; showing 12 of 4675)
- **src::rootRelPath@model.h:2519:209682 [render,append,write]** — 1022 symbols
- **src::emitTo@infra/emit.h:53:2760 [write,run,emit]** — 754 symbols
- **src::kindIs@infra/nodekind.h:46:3271 [push,emit,collect]** — 568 symbols
- **src::DISCLOSE@infra/Diagnostics.h:616:43369 [read,run,compute]** — 269 symbols
- **docs::`--top-k=N`@COMMANDS.md:59:9208 [pack,allow,insert]** — 183 symbols
- **test/ownerhopfix/py/pkg::big_handler_001@broadcast.py:3:72** — 106 symbols
- **src::isIdentChar@infra/namesplit.h:35:1884 [read,scan,drop]** — 102 symbols
- **src/infra::fail@os_win32.cpp:63:2553 [open,get,close]** — 101 symbols
- **src::multi@defattrib.h:92:6576 [call,emit,run]** — 91 symbols
- **src::active@pathpairs.h:106:7669 [emit,run,split]** — 80 symbols
- **src::rowOffsets@infra/sparseCsr.h:248:8990 [connect,compute,collect]** — 68 symbols
- **test::no@estchargecheck.sh:52:4108 [skip,set]** — 63 symbols

Not measured: 390 files in go,swift,java,cs,php,dart,kt,gd,clj (imports almost never resolved to files), so the god files and cycles below cover the resolved edges only.

## God files (most depended-on; showing 10 of 287)
- `src/model.h` — 135 dependents
- `src/infra/emit.h` — 95 dependents
- `src/infra/Diagnostics.h` — 72 dependents
… [38 more lines, 4338 bytes total]
`````

## `./build/ripwire . --seams`

*Cross-module call seams no test reaches. NOW carries seam_pairs/shown/capped.*

**wall time: 2.61s**

`````
<!-- ripwire seams schema=ripwire.seams/v1: cross-directory call edges NO test reaches: <seam from= to= untested= shown= capped=> of <edge caller= p= callee= cp=>. window: shown= total= capped= has_more= next_offset= offset= limit= (capped=1 cut; next_offset= pastes as offset=). counts_floor=1: every count is a FLOOR, never a total. graph_ambiguous=/graph_unresolved=: resolver gauge. graph_unindexed=N: N files no grammar could read (the map header's unindexed=); their calls raise neither gauge. root=: p= relative to it. pr_iters=N: PageRank iterations. modules=N: directories holding indexed symbols (a module = parent dir). bridges=N: cross-directory call edges, tested or not; untested= is those no test reaches. test_files=N: test files whose calls seed the reach; 0 means every seam reads untested. seam_pairs=N: directed dir pairs with an untested edge (the seam rows' total). doc_links=N: cross-directory links between two document sections, not in bridges= or untested= (no test exercises a document link); absent at 0. <file-scope> (t=modscope): a file's MODULE SCOPE — where a top-level call and an anonymous callback body's calls live; a CALLER, never a callee, with no body to expand. -->
<seams schema="ripwire.seams/v1" modules="1358" bridges="5062" untested="2581" doc_links="81" test_files="3706" seam_pairs="39" shown="20" capped="1" total="39" has_more="1" next_offset="20" offset="0" limit="0" pr_iters="38" root="." graph_ambiguous="3456" graph_unresolved="18664" graph_unindexed=" … [line truncated: 22 more bytes on this line]
<seam from="src" to="src/infra" untested="2413" shown="5" capped="1">
<edge caller="baseNameOf" p="src/mention.h:336" callee="afterLast" cp="src/infra/namesplit.h:158"/>
<edge caller="jsonStr" p="src/serialize.h:10736" callee="escapeMcp" cp="src/infra/jsonesc.h:247"/>
<edge caller="boundedEditDistance" p="src/didyoumean.h:34" callee="swap" cp="src/infra/svector.h:439"/>
<edge caller="nextAttrXml" p="src/nextverb.h:46" callee="utf8SeqLen" cp="src/infra/jsonesc.h:59"/>
<edge caller="jsonEscape" p="src/mcpjson.h:865" callee="escapeMcp" cp="src/infra/jsonesc.h:247"/>
</seam>
<seam from="bench" to="src/infra" untested="78" shown="5" capped="1">
<edge caller="infraSortSmall" p="bench/bench_radix_ab.cpp:73" callee="sortKeySmall" cp="src/infra/radixSort.h:91"/>
<edge caller="isSorted" p="bench/bench_sort_large.cpp:42" callee="lessByFromTo" cp="src/infra/sortutil.h:170"/>
<edge caller="benchScores" p="bench/bench_radix_ab.cpp:133" callee="nonNegativeFloatDescKey" cp="src/infra/sortutil.h:73"/>
<edge caller="benchScores" p="bench/bench_radix_ab.cpp:133" callee="lessByScoreDescId" cp="src/infra/sortutil.h:52"/>
<edge caller="benchAdaptive" p="bench/bench_radix_ab.cpp:157" callee="nonNegativeFloatDescKey" cp="src/infra/sortutil.h:73"/>
</seam>
<seam from="bench/multiswe" to="bench/locbench" untested="8" shown="5" capped="1">
<edge caller="main" p="bench/multiswe/run_multiswe.py:301" callee="run_ctx" cp="bench/locbench/run_locbench.py:166"/>
<edge caller="main" p="bench/multiswe/run_multiswe.py:301" callee="parse_candidates" cp="bench/locbench/run_locbench.py:223"/>
<edge caller="main" p="bench/multiswe/run_multiswe.py:301" callee="norm_path" cp="bench/locbench/run_locbench.py:241"/>
<edge caller="main" p="bench/multiswe/run_multiswe.py:301" callee="ranked_files_from_candidates" cp="bench/locbench/run_locbench.py:245"/>
<edge caller="main" p="bench/multiswe/run_multiswe.py:301" callee="file_ranks" cp="bench/locbench/run_locbench.py:251"/>
</seam>
<seam from="bench/cppbench" to="bench/locbench" untested="7" shown="5" capped="1">
<edge caller="main" p="bench/cppbench/run_cppbench.py:280" callee="run_ctx" cp="bench/locbench/run_locbench.py:166"/>
<edge caller="main" p="bench/cppbench/run_cppbench.py:280" callee="parse_candidates" cp="bench/locbench/run_locbench.py:223"/>
<edge caller="main" p="bench/cppbench/run_cppbench.py:280" callee="norm_path" cp="bench/locbench/run_locbench.py:241"/>
<edge caller="main" p="bench/cppbench/run_cppbench.py:280" callee="ranked_files_from_candidates" cp="bench/locbench/run_locbench.py:245"/>
<edge caller="main" p="bench/cppbench/run_cppbench.py:280" callee="file_ranks" cp="bench/locbench/run_locbench.py:251"/>
</seam>
… [82 more display lines; full output is 12134 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --mermaid`

*Module (directory) dependency graph as a Mermaid diagram.*

**wall time: 2.10s**

`````
%% ripwire --mermaid: module (directory) dependency graph — node = dir (symbol count), edge = inter-module calls (>= 3). Render at mermaid.live.
flowchart LR
  subgraph sg0 ["src"]
    n102["src<br/>12786"]
    n103["src/infra<br/>1596"]
  end
  subgraph sg1 ["test"]
    n104["test<br/>6426"]
    n715["test/legochargefix<br/>546"]
    n452["test/fixtures/recallpassage<br/>314"]
    n471["test/fnslotcpp2<br/>285"]
    n684["test/ifacepeelfix/cpp<br/>206"]
    n1214["test/slotjoinfix<br/>182"]
    n878["test/lib<br/>178"]
    n982["test/ownerhopfix/py/pkg<br/>158"]
    n388["test/expandmodefix<br/>151"]
    n390["test/expandsibsfix<br/>149"]
    n1186["test/rubyschemafix<br/>99"]
    n507["test/forbodyfoldfix/py<br/>98"]
  end
  n74["docs<br/>940"]
  n0["(root)<br/>767"]
  n2[".github<br/>636"]
  subgraph sg5 ["bench"]
    n4["bench<br/>558"]
    n5["bench/agentloop<br/>331"]
    n49["bench/locbench/results/r5_pooling<br/>237"]
    n50["bench/locbench/results/r6_expansion<br/>187"]
    n59["bench/recalleval<br/>113"]
    n43["bench/locbench<br/>107"]
… [22 more lines, 1627 bytes total]
`````

## `./build/ripwire . --owners`

*Bus-factor: recency-weighted author ownership per file.*

**wall time: 10.20s**

`````
<!-- ripwire owners schema=ripwire.owners/v1: recency-weighted author ownership (half-life 6mo): <f p= authors= bf= top= share=>; bf=1 = one person holds it. at=: commit+dirty+shallow. root=: p= relative to it. files=N: files analysed. files=N: single-author files folded into this one row; detail=1 lists each. -->
<owners schema="ripwire.owners/v1" files="4497" root="." at="0412539b9">
<uniform authors="1" bf="1" share="1.00" files="3457"/>
<f p=".coderabbit.yaml" authors="2" bf="0" top="<author>" share="0.59"/>
<f p=".github/pargates-shard-weights.json" authors="3" bf="0" top="<author>" share="0.42"/>
<f p=".github/workflows/ci.yml" authors="6" bf="0" top="<author>" share="0.43"/>
<f p=".github/workflows/nightly.yml" authors="2" bf="1" top="<author>" share="0.86"/>
<f p=".github/workflows/release.yml" authors="3" bf="0" top="<author>" share="0.59"/>
<f p="AGENTS.md" authors="2" bf="0" top="<author>" share="0.71"/>
<f p="CHANGELOG.md" authors="18" bf="0" top="<author>" share="0.51"/>
<f p="CLAUDE.md" authors="5" bf="0" top="<author>" share="0.41"/>
<f p="CONTRIBUTING.md" authors="7" bf="0" top="<author>" share="0.37"/>
<f p="INSTALL.md" authors="3" bf="0" top="<author>" share="0.77"/>
<f p="README.md" authors="22" bf="0" top="<author>" share="0.50"/>
<f p="SECURITY.md" authors="3" bf="0" top="<author>" share="0.46"/>
<f p="THIRD_PARTY.md" authors="8" bf="0" top="<author>" share="0.41"/>
<f p="bench/ANSWERQUALITY.md" authors="2" bf="0" top="<author>" share="0.72"/>
<f p="bench/PROFILE.md" authors="5" bf="0" top="<author>" share="0.78"/>
<f p="bench/agentloop/README.md" authors="2" bf="1" top="<author>" share="0.89"/>
<f p="bench/agentloop/grade_answers.py" authors="3" bf="0" top="<author>" share="0.51"/>
<f p="bench/agentloop/run_agentloop.py" authors="3" bf="1" top="<author>" share="0.90"/>
<f p="bench/agentloop/run_editsuite.py" authors="2" bf="0" top="<author>" share="0.80"/>
<f p="bench/arb/run_arb.py" authors="2" bf="0" top="<author>" share="0.65"/>
<f p="bench/capsweep/capsweep.py" authors="3" bf="0" top="<author>" share="0.78"/>
<f p="bench/mine_traces.py" authors="2" bf="0" top="<author>" share="0.72"/>
<f p="bench/representative_perfgate.sh" authors="3" bf="0" top="<author>" share="0.68"/>
<f p="bench/routing_ab_report.py" authors="2" bf="0" top="<author>" share="0.63"/>
<f p="bench/scip_match_diag.py" authors="2" bf="0" top="<author>" share="0.51"/>
<f p="bench/scip_pin_precision.py" authors="2" bf="0" top="<author>" share="0.74"/>
<f p="bench/shotgun/README.md" authors="3" bf="0" top="<author>" share="0.49"/>
… [1014 more display lines; full output is 112489 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --dead-code=src`

*Internal functions with no caller found in the index — a name-based graph reading, not a confidence score. NOTE the filter is a path-COMPONENT match: 'src' matches any .../src/... segment; use ./src to pin the root directory.*

**wall time: 4.88s**

`````
<!-- ripwire dead-code schema=ripwire.dead-code/v1: internal-linkage functions with no caller found in the index (not a confidence score): <d n= t= p= l=>; filter= path component. window: shown= total= (capped=1 cut). counts_floor=1: every count is a FLOOR, never a total. graph_ambiguous=/graph_unresolved=: resolver gauge. graph_unindexed=N: N files no grammar could read (the map header's unindexed=); their calls raise neither gauge. value-ref-excluded=N: internal functions kept off because a table, field or argument in another function or at file scope holds them (matched by name, not a proven call); a floor. root=: p= relative to it. evidence=: the rule every row met, internal linkage and no caller in the index; verify before deleting. register-macro-excluded=N: symbols skipped as self-registering test/bench macros (TEST, BENCHMARK...); a floor. exported linkage=exported evidence=no-non-test-caller: PUBLIC free functions of the filtered files with no non-test caller in the graph, <e> rows after d/to; not dead, not in count=, code outside the tree may call them (zero means none found here); total= found, shown= printed (capped=1 rows cut), files= read of files_total= filtered files holding a non-internal free function with no non-test caller (first by path; total=0 can follow), unseen=N a floor on text files unread, unseen_by= the cap or failure behind each, extra=skipped verdicts fixed by indexed files so unindexed ones unread (counts, at= are floors). e n= t= p= l= v=unused no mention in any text file under the root outside its def (prose docs not read)|test-only only tests|file-only same-file words only|unknown why= names what may reach it: string (__all__, getattr, a registry key)|value|framework (decorator, hook)|import (re-export)|barrel|api|name|by-name|declined|built-name|dispatch|members|manifest|in-file|unimported|unseen; tests= text= str= imp= same= word counts, defs= overloads, at= sites to read. count=N: candidates meeting evidence= (a floor). -->
<dead-code schema="ripwire.dead-code/v1" count="1" evidence="internal-linkage+zero-callers" register-macro-excluded="0" value-ref-excluded="10" filter="src" root="." graph_ambiguous="3456" graph_unresolved="18664" graph_unindexed="286" counts_floor="1">
<d n="unused_helper" t="fn" p="test/archmetricsfix/src/orphan/util.cpp" l="1"/>
<exported linkage="exported" evidence="no-non-test-caller" total="82" shown="82" files="1" files_total="1" unseen="1" unseen_by="size=1,total=0,files=0,read=0,walk=0">
<e n="Unique" t="cls" p="src/infra/os_win32.cpp" l="85" v="unknown" defs="3" why="name,members,unseen" text="7" same="13" at="src/pincensus.h:57,src/pincensus.h:83"/>
<e n="StreamLock" t="cls" p="src/infra/os_win32.cpp" l="205" v="unknown" defs="2" why="unseen" same="6"/>
<e n="NativePath" t="cls" p="src/infra/os_win32.cpp" l="370" v="unknown" defs="2" why="members,unseen" tests="1" same="14"/>
<e n="SocketTable" t="cls" p="src/infra/os_win32.cpp" l="425" v="unknown" defs="2" why="unseen" same="5"/>
<e n="WinsockSession" t="cls" p="src/infra/os_win32.cpp" l="439" v="unknown" defs="2" why="members,unseen" same="6"/>
<e n="open" t="fn" p="src/infra/os_win32.cpp" l="1003" v="unknown" defs="2" why="name,declined,string,manifest,unseen" tests="2140" text="1140" str="57" at=".coderabbit.yaml:4,.coderabbit.yaml:15"/>
<e n="openat" t="fn" p="src/infra/os_win32.cpp" l="1023" v="unknown" why="name,unseen" tests="12" text="5" at="src/infra/os.h:167,src/infra/os.h:167"/>
<e n="read" t="fn" p="src/infra/os_win32.cpp" l="1075" v="unknown" why="name,string,manifest,unseen" tests="3008" text="2451" str="127" same="2" at=".coderabbit.yaml:32,.github/workflows/ci.yml:62"/>
<e n="pread" t="fn" p="src/infra/os_win32.cpp" l="1087" v="unknown" why="name,built-name,unseen" tests="1" text="5" at="src/infra/os.h:171,src/infra/os.h:171"/>
<e n="fstat" t="fn" p="src/infra/os_win32.cpp" l="1106" v="unknown" why="name,unseen" tests="13" text="14" at="src/docparse.h:3,src/docparse.h:338"/>
<e n="stat" t="fn" p="src/infra/os_win32.cpp" l="1122" v="unknown" why="name,string,unseen" tests="86" text="157" str="5" at=".github/workflows/ci.yml:854,bench/agentloop/run_agentloop.py:640"/>
<e n="lstat" t="fn" p="src/infra/os_win32.cpp" l="1126" v="unknown" why="name,unseen" tests="8" text="9" at="src/editplan.h:4,src/editplan.h:257"/>
<e n="dup" t="fn" p="src/infra/os_win32.cpp" l="1170" v="unknown" why="name,string,unseen" tests="281" text="41" str="3" at="bench/capsweep/capsweep.py:862,bench/capsweep/capsweep.py:865"/>
<e n="dup_cloexec" t="fn" p="src/infra/os_win32.cpp" l="1171" v="unknown" why="name,unseen" text="3" at="src/infra/os.h:179,src/infra/os.h:1127"/>
<e n="write_nosigpipe" t="fn" p="src/infra/os_win32.cpp" l="1172" v="unknown" why="name,unseen" text="3" at="src/helpdeadline.h:532,src/infra/os.h:183"/>
<e n="dup2" t="fn" p="src/infra/os_win32.cpp" l="1173" v="unknown" why="name,unseen" tests="11" text="14" at="src/helpdeadline.h:392,src/helpdeadline.h:393"/>
<e n="ftruncate" t="fn" p="src/infra/os_win32.cpp" l="1175" v="unknown" why="name,unseen" tests="3" text="3" at="src/infra/os.h:191,src/infra/os.h:191"/>
<e n="fsync" t="fn" p="src/infra/os_win32.cpp" l="1181" v="unknown" why="name,unseen" tests="1" text="8" at="present/deck5_ripwire_build.js:1462,present/ripwire-showcase.pptx:621"/>
<e n="fchmod" t="fn" p="src/infra/os_win32.cpp" l="1184" v="unknown" why="name,unseen" tests="2" text="4" at="src/infra/os.h:193,src/infra/os.h:193"/>
<e n="flock" t="fn" p="src/infra/os_win32.cpp" l="1206" v="unknown" why="name,string,unseen" tests="13" text="12" str="1" at="src/helpdeadline.h:250,src/helpdeadline.h:329"/>
<e n="pipe_cloexec" t="fn" p="src/infra/os_win32.cpp" l="1229" v="unknown" why="name,unseen" tests="4" text="3" at="src/helpdeadline.h:371,src/infra/os.h:199"/>
<e n="poll" t="fn" p="src/infra/os_win32.cpp" l="1234" v="unknown" why="name,unseen" tests="67" text="69" at="bench/recalleval/run_depthinvariance.py:134,bench/recalleval/run_depthinvariance.py:135"/>
<e n="fdopen" t="fn" p="src/infra/os_win32.cpp" l="1269" v="unknown" why="name,unseen" tests="22" text="17" at="src/docparse.h:3,src/docparse.h:330"/>
<e n="fileno" t="fn" p="src/infra/os_win32.cpp" l="1270" v="unknown" why="name,unseen" tests="4" text="9" at="src/docparse.h:338,src/infra/os.h:217"/>
<e n="getline" t="fn" p="src/infra/os_win32.cpp" l="1276" v="unknown" why="name,string,unseen" tests="14" text="20" str="1" at="bench/bench_fixedstr.cpp:16,src/arch.h:519"/>
<e n="memoryStreamMutex" t="fn" p="src/infra/os_win32.cpp" l="1330" v="unknown" why="unseen" same="3"/>
… [58 more display lines; full output is 15969 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --exercises=test/regression.sh`

*Which symbols a TEST FILE exercises — the reverse direction of --affected.*

**wall time: 1.56s**

`````
<!-- ripwire exercises schema=ripwire.exercises/v1: NON-TEST symbols this test transitively calls (what it covers): <t p= run=>; the inverse of affected. window: shown= capped= (capped=1 cut). seed_files_capped=: 1 = cut. counts_floor=1: every count is a FLOOR, never a total. graph_ambiguous=/graph_unresolved=: resolver gauge. graph_unindexed=N: N files no grammar could read (the map header's unindexed=); their calls raise neither gauge. root=: p= relative to it. pr_iters=N: PageRank iterations. seed_files=N: test files the pattern matched. shown_seed_files=N: of those, printed as t rows (at most 20). test_symbols=N: symbols in those test files, the walk's seeds. reaches=N: non-test symbols the tests transitively call (the s rows' total). harness=script|mixed: seeds include shell gates, whose subprocess coverage is unseen; note= says so. of=: the test file pattern given. -->
<exercises schema="ripwire.exercises/v1" of="test/regression.sh" seed_files="1" shown_seed_files="1" seed_files_capped="0" test_symbols="4" reaches="0" harness="script" note="a shell gate invokes the compiled binary as a subprocess; script-to-binary edges are not modelled, so reaches= counts call-gr … [line truncated: 189 more bytes on this line]
<t p="test/regression.sh" run="bash test/regression.sh"/>
</exercises>
`````

## `./build/ripwire . --community=0`

*Drill into ONE call-graph community by id — the drill= the --communities output itself advertises.*

**wall time: 1.53s**

`````
<!-- ripwire community schema=ripwire.community/v1: ONE module id=: <member t= n= p=> ranked members, its <bridge> edges; size= the TRUE count; dir= its members' most common directory (a top-level file's own path); label= dir::name@file:line:byte of its top fan-in member (non-accessors first) [up to 3 top name verbs]; bridges= modules a call edge joins to it; partition= module count incl. singletons (ids 0..partition-1); modules= those of 2+ symbols; shown_bridges= <bridge> rows listed. window: shown= capped= (capped=1 cut). bridges_capped=: 1 = cut. counts_floor=1: every count is a FLOOR, never a total. graph_ambiguous=/graph_unresolved=: resolver gauge. graph_unindexed=N: N files no grammar could read (the map header's unindexed=); their calls raise neither gauge. root=: p= relative to it. pr_iters=N: PageRank iterations. -->
<community schema="ripwire.community/v1" id="0" size="1" dir=".coderabbit.yaml" label=".coderabbit.yaml::reviews@.coderabbit.yaml:12:928" bridges="0" shown_bridges="0" bridges_capped="0" partition="23042" modules="4675" shown="1" capped="0" pr_iters="38" root="." graph_ambiguous="3456" graph_unresol … [line truncated: 51 more bytes on this line]
<member t="sec" n="reviews" p=".coderabbit.yaml:12"/>
</community>
`````

## `./build/ripwire . --quality-delta`

*On a CLEAN tree: nothing got worse, exit 0. The gating shape is in the sandbox section below.*

**wall time: 35.82s**

`````
<!-- ripwire quality-delta schema=ripwire.quality-delta/v1: only what the change made WORSE vs baseline=: regressions= minor= gating=; <r kind= sym= p= was= now= gating= bar=>, <sa> acked. at=: commit+dirty+shallow. stale=N: ack ledger rows whose target no longer applies (sa rows); never gating. stale_by_kind=: stale= split by ack kind (kind:N,...); the sa rows are collapsed. stale_next=: the call printing the sa rows and the full header. head_basis=identity: the floor is this tree's own snapshot; archived-index-hidden: refused, a tracked path is skip-worktree/assume-unchanged; absent: the archived HEAD tree. -->
<quality-delta schema="ripwire.quality-delta/v1" baseline="git-HEAD" regressions="0" gating="0" stale="163" at="0412539b9" head_basis="identity" stale_by_kind="api-surface:24,complexity:12,dead-code:9,duplication:62,nesting:3,new-clone-of-reused-helper:19,params:1,short-horizon-churn:9,verbosity:24" … [line truncated: 43 more bytes on this line]
</quality-delta>
`````

stderr:

`````
ripwire: no ./.ripwire_quality_baseline — auto-comparing the working tree vs git HEAD (commit the baseline with --quality-baseline to pin it)
`````

## `./build/ripwire . --quality-delta --show-stale`

*The same clean verdict with what it folded printed back: every stale acknowledgement as an <sa kind= key= why=> row and the full header. The regression-free answer above keeps only stale= and stale_by_kind= (and stale_next= names this call), and folds only when that saves a quarter of the bytes. Refused without --quality-delta.*

**wall time: 37.50s**

`````
<!-- ripwire quality-delta schema=ripwire.quality-delta/v1: only what the change made WORSE vs baseline=: regressions= minor= gating=; <r kind= sym= p= was= now= gating= bar=>, <sa> acked. value-ref-excluded=N: internal functions kept off because a table, field or argument in another function or at file scope holds them (matched by name, not a proven call); a floor. at=: commit+dirty+shallow. stale=N: ack ledger rows whose target no longer applies (sa rows); never gating. preexisting-worse=N: regressions on symbols that existed at baseline; they gate when major. new-symbol=N: findings on NEW code; new-symbol rows never gate, except defect-shape format-arity. register-macro-excluded=N: symbols kept out of dead-code as self-registering test/bench macros; a floor. declined-call-excluded=N: symbols kept out of dead-code only because a declined call may mean them; a floor. api-new-surface=N: new PUBLIC symbols; a count, never gates, not in regressions=. renames=/rename_window_commits=: git rename pairs read over that many commits, to re-file baseline and acks. acked_by_rename=/acked_by_content=: acked= suppressions matched via git renames / an equal body hash. renames_window_truncated=1: history is deeper than the rename window, older renames unread. acked=N: findings suppressed by the ack ledger, listed as sa rows; never gating. sa key=/why=: the stale ack's ledger hash / target-gone (names nothing now) or finding-gone (no longer fires). head_basis=identity: the floor is this tree's own snapshot; archived-index-hidden: refused, a tracked path is skip-worktree/assume-unchanged; absent: the archived HEAD tree. -->
<quality-delta schema="ripwire.quality-delta/v1" baseline="git-HEAD" regressions="0" minor="0" acked="0" stale="163" preexisting-worse="0" new-symbol="0" gating="0" register-macro-excluded="62" api-new-surface="0" at="0412539b9" renames="67" rename_window_commits="400" acked_by_rename="0" acked_by_c … [line truncated: 115 more bytes on this line]
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
<sa kind="api-surface:new-symbol" key="25c9f0504fd376a4" why="target-gone"/>
<sa kind="api-surface:new-symbol" key="26aa7c55d54c4341" why="target-gone"/>
<sa kind="api-surface:new-symbol" key="36e39c7ab0fc1686" why="target-gone"/>
<sa kind="api-surface:new-symbol" key="4bce64bd920de0c3" why="target-gone"/>
<sa kind="api-surface:new-symbol" key="61f0e361ef7dee27" why="target-gone"/>
<sa kind="api-surface:new-symbol" key="79625906f9f71ad0" why="target-gone"/>
<sa kind="api-surface:new-symbol" key="8ecb190954dce18a" why="target-gone"/>
<sa kind="api-surface:new-symbol" key="995375dfa4e63104" why="target-gone"/>
<sa kind="api-surface:new-symbol" key="ee71e4fffa361902" why="target-gone"/>
<sa kind="complexity" key="0001f7edbff929e5" why="finding-gone" sym="src/cli.h::rw::validateLegendModifier" p="src/cli.h:4580"/>
<sa kind="complexity" key="20b8113908960e36" why="finding-gone" sym="runPath" p="src/verbs_navigate.h:3222"/>
<sa kind="complexity" key="2570a290e1506158" why="target-gone"/>
<sa kind="complexity" key="3298be65bf6058ef" why="finding-gone" sym="dispatchMain" p="src/main.cpp:3926"/>
… [136 more display lines; full output is 16077 bytes on 1 raw line(s)]
`````

stderr:

`````
ripwire: no ./.ripwire_quality_baseline — auto-comparing the working tree vs git HEAD (commit the baseline with --quality-baseline to pin it)
`````

## `./build/ripwire . --edit-check=rankGraphTeleport`

*Fast per-symbol post-edit contract check vs git HEAD (unchanged on a clean tree).*

**wall time: 46.53s**

`````
<!-- ripwire edit-check schema=ripwire.edit-check/v1: sym='s contract NOW vs HEAD: status=unchanged|new-symbol|contract-change; <c n= p= incompatible=1 sites_l=> callers. counts_floor=1: every count is a FLOOR, never a total. graph_ambiguous=/graph_unresolved=: resolver gauge. graph_unindexed=N: N files no grammar could read (the map header's unindexed=); their calls raise neither gauge. est_tokens=: price as emitted (an upper bound under compact). at=: commit+dirty+shallow. root=: p= relative to it. next=: the one pasteable follow-up. defs=N: overloads at this site (same file, scope, name) folded into one contract; params compared by MAX. callers=N: callers of sym= (the c rows' total; a floor). -->
<edit-check schema="ripwire.edit-check/v1" sym="rankGraphTeleport" t="fn" p="src/graph.h:13631" status="unchanged" defs="1" callers="7" incompatible="0" at="0412539b9" graph_ambiguous="3456" graph_unresolved="18664" graph_unindexed="286" counts_floor="1" root="." next="--test-gate=src/graph.h" est_t … [line truncated: 12 more bytes on this line]
<c n="runEval" p="src/eval.h:171"/>
<c n="rankGraph" p="src/graph.h:13674"/>
<c n="anchoredLexicalRank" p="src/graph.h:14321"/>
<c n="churnDecayRanking" p="src/main.cpp:1433"/>
<c n="churnRankedGraph" p="src/main.cpp:1472"/>
<c n="runDefaultMap" p="src/main.cpp:1759"/>
<c n="getIndex" p="src/mcpindex.h:1211"/>
</edit-check>
`````

## `./build/ripwire . --pr-context`

*No-LLM review-evidence bundle for the working-tree diff (clean tree = empty).*

**wall time: 13.51s**

`````
<!-- ripwire pr-context schema=ripwire.pr-context/v1: review bundle per changed file vs base=: symbols, callers, blast radius, tests, owners. counts_floor=1: every count is a FLOOR, never a total. graph_ambiguous=/graph_unresolved=: resolver gauge. graph_unindexed=N: N files no grammar could read (the map header's unindexed=); their calls raise neither gauge. est_tokens=: price as emitted (an upper bound under compact). at=: commit+dirty+shallow. root=: p= relative to it. truncated=: what the trim ladder dropped to fit budget_tokens= (budget-floor-exceeded: still over). direction=: side reviewed: worktree-since-head, head-since-fork or head-since-ref-tip. skipped_mode_only=N: mode-only (chmod) diffs left out of the changed files; renames stay in. trim_level=0-4: trim ladder step taken to fit budget_tokens= (0 none, 4 counts only); raise token-budget. budget_default=1: the default 8000-token budget applied (no token-budget or max-tokens given). files=N: changed files in the diff (shown= of them listed). -->
<pr-context schema="ripwire.pr-context/v1" base="working-tree" root="." direction="worktree-since-head" files="0" skipped_mode_only="0" budget_tokens="8000" est_tokens="584" trim_level="0" truncated="none" budget_default="1" at="0412539b9" graph_ambiguous="3456" graph_unresolved="18664" graph_uninde … [line truncated: 27 more bytes on this line]
<!-- no changed files in the index (clean tree, or the diff touched only non-indexed files) -->
</pr-context>
`````

## `./build/ripwire . --pr-context=HEAD~1`

*The BASEREF form: diffed against merge-base(BASEREF, HEAD), never the ref tip — here the previous commit on the current line (a ref with NO merge base falls back to a disclosed two-dot diff: anchor="ref-tip-two-dot").*

**wall time: 24.67s**

`````
<!-- ripwire pr-context schema=ripwire.pr-context/v1: review bundle per changed file vs base=: symbols, callers, blast radius, tests, owners. window: shown= capped= (capped=1 cut). counts_floor=1: every count is a FLOOR, never a total. graph_ambiguous=/graph_unresolved=: resolver gauge. graph_unindexed=N: N files no grammar could read (the map header's unindexed=); their calls raise neither gauge. est_tokens=: price as emitted (an upper bound under compact). at=: commit+dirty+shallow. root=: p= relative to it. truncated=: what the trim ladder dropped to fit budget_tokens= (budget-floor-exceeded: still over). anchor=merge-base: diffed from merge base(base, HEAD); ref-tip-two-dot = no merge base, two-dot view. base_sha=: the merge-base commit (9 hex) the diff is anchored at. base_moved=N: paths the base ref changed since the fork that this work never touched; excluded. direction=: side reviewed: worktree-since-head, head-since-fork or head-since-ref-tip. skipped_mode_only=N: mode-only (chmod) diffs left out of the changed files; renames stay in. trim_level=0-4: trim ladder step taken to fit budget_tokens= (0 none, 4 counts only); raise token-budget. budget_default=1: the default 8000-token budget applied (no token-budget or max-tokens given). commits=N: this file's commits in window=; 0 = the window could not look, not no partners. partners=N: co-change partners NOT in the diff; rows are its top shown= (the cochange verb lists all). dependents=N: distinct symbols transitively calling this file's symbols (reach set, a FLOOR). files_other=N: non-changed files among those reached; the f rows are its top shown=. authors=N: distinct authors of this file (0 = no git data). bf=1: one author holds over 80% of recency-weighted commits (bus-factor risk). no-ref-work note=: the base ref's tip is the merge base, so it has no work of its own; rows are HEAD's. files=N: changed files in the diff (shown= of them listed). file symbols=: indexed symbols in that changed file. changed-symbols count= / tests count=: that section's full count (shown= of it listed). tests count=: test files reaching this file (shown= of them listed). impact files=: files holding the transitive callers (dependents=). impactf deps=: transitive callers in that file. author email=/share=: a committer of this file / its fraction of the recency-weighted commits. partner deg=: of this file's commits in window=, the fraction that partner shares. partner dep_capable=0: a side cannot carry a static dependency, so surprising= is undefined. changed-symbols sections=N: doc headings folded into count=, no row each; count minus sections = rows. -->
<pr-context schema="ripwire.pr-context/v1" base="HEAD~1" root="." anchor="merge-base" base_sha="d1f3ba3d5" base_moved="0" direction="head-since-fork" files="3" skipped_mode_only="0" budget_tokens="8000" est_tokens="2270" trim_level="0" truncated="none" budget_default="1" at="0412539b9" graph_ambiguo … [line truncated: 74 more bytes on this line]
<no-ref-work note="HEAD~1 tip == merge-base, so that ref has no divergent work of its own; this bundle is HEAD's work since the fork. For the ref's OWN diff see merge-scout or stray-content"/>
<file p="docs/COMMANDS.md" symbols="195">
<impact dependents="7" files="3" files_other="3" shown="3" capped="0">
<f p="README.md" deps="5"/>
<f p="docs/LINEAGE.md" deps="1"/>
<f p="docs/README.md" deps="1"/>
</impact>
<tests count="0" shown="0" capped="0">
</tests>
<changed-symbols count="195" sections="195">
</changed-symbols>
<cochange window="18mo@HEAD" commits="737" partners="182" shown="12" capped="1">
<partner p="src/cli.h" deg="0.48" dep_capable="0"/>
<partner p="README.md" deg="0.31" dep_capable="0"/>
<partner p="test/regression.sh" deg="0.25" dep_capable="0"/>
<partner p="docs/EVALS.md" deg="0.24" dep_capable="0"/>
<partner p="CHANGELOG.md" deg="0.22" dep_capable="0"/>
<partner p="src/compactlegend.h" deg="0.18" dep_capable="0"/>
<partner p="src/main.cpp" deg="0.18" dep_capable="0"/>
<partner p="present/deck5_ripwire_build.js" deg="0.15" dep_capable="0"/>
<partner p="src/mcpverbs.h" deg="0.13" dep_capable="0"/>
<partner p="src/serialize.h" deg="0.11" dep_capable="0"/>
<partner p="src/quality.h" deg="0.09" dep_capable="0"/>
<partner p="src/graph.h" deg="0.09" dep_capable="0"/>
</cochange>
<owners authors="21" bf="0" shown="5" capped="1">
<author email="<author>" share="0.51"/>
<author email="<author>" share="0.29"/>
… [33 more display lines; full output is 5675 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --merge-scout=HEAD~2,HEAD~1`

*Pairwise cross-arm conflict sites + suggested landing order (any committish sharing a merge base with HEAD works as an arm; one that does not is reported ok="0", never compared).*

**wall time: 61.35s**

`````
<!-- ripwire merge-scout schema=ripwire.merge-scout/v1: cross-branch overlap of arms= refs: <arm ref= base= changed= head_conflicts=>, <pair a= b= conflicts= risks=>, <landing order=>. at=: commit+dirty+shallow. head=: the HEAD commit, bare 9-hex sha (at= adds +dirty). ok=1 on an arm row means the comparison RAN, so changed=/head_conflicts= are real and may legitimately be 0 (an empty but materialized tree is a real index); ok=0 means it did not run at all. no-work note=: arm compared and has no divergent work vs its merge base, so no landing slot. -->
<merge-scout schema="ripwire.merge-scout/v1" arms="2" head="0412539b9" at="0412539b9">
<arm ref="HEAD~2" base="48169aace" ok="1" changed="0" head_conflicts="0">
<no-work note="no divergent work vs merge-base — see --stray-content"/>
</arm>
<arm ref="HEAD~1" base="d1f3ba3d5" ok="1" changed="0" head_conflicts="0">
<no-work note="no divergent work vs merge-base — see --stray-content"/>
</arm>
<pair a="HEAD~2" b="HEAD~1" conflicts="0" risks="0"/>
<landing order=""/>
</merge-scout>
`````

## `./build/ripwire . --stray-content=lane/`

*Which refs of the `lane/` ref family still hold divergent authored work vs HEAD, with verdicts.*

**wall time: 149.26s**

`````
<!-- ripwire stray-content schema=ripwire.stray-content/v1: per local ref, lines/symbols NOT in HEAD: <ref ok= v= base= stray=>; v=unknown = no merge base. at=: commit+dirty+shallow. head=: the HEAD commit, bare 9-hex sha (at= adds +dirty). head_ref=: HEAD's branch (HEAD when detached); that branch itself is not scanned. refs=N: local branches scanned (refs/heads only); unmerged + superseded + merged + unknown = refs. blobs=N: distinct git blobs read for the sweep. unmerged=N: refs whose authored work the live line genuinely lacks. superseded=N: refs whose work the live line re-implemented (removed the same base code). merged=N: refs whose work HEAD already has; omitted from the rows. name=: the local branch. tip=: the branch tip commit (9 hex). date=: the tip's committer date, YYYY-MM-DD. files=N: files with stray lines; rows capped at 12, a more element counts the rest (detail=1 lists all). ref superseded=N>: of this ref's stray= lines, those in files the live line re-implemented. authored=N: lines this ref authored in the file vs its merge base. del=N: base lines this ref removed (0 = pure addition). redone=N: of del=, the base lines HEAD removed too (the supersession evidence). sim=: minhash containment, 0 to 1, of the ref's blob in HEAD's (pure-addition evidence). head-touched=1: the live line changed this path since the merge base. more files=N: N more file rows of this ref withheld; shown + N = the ref's files=; detail=1 lists all. unknown=N: refs that could not be analysed (v=unknown, e.g. no merge base); never counted merged. -->
<stray-content schema="ripwire.stray-content/v1" head="0412539b9" head_ref="integration/train-1111c" refs="393" blobs="959" unmerged="43" superseded="2" merged="348" unknown="0" filter="lane/" at="0412539b9">
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
… [460 more display lines; full output is 55223 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --stray-content=fix/`

*A second selection, the `fix/` ref family, picked at capture time from the refs this checkout really has and never the selection above: merged refs are OMITTED from the rows and counted in merged=; refs sharing no merge base with HEAD (a shallow clone, or a pre-rewrite history) land in unknown= with ok="0" — the counters always reconcile against refs=.*

**wall time: 10.45s**

`````
<!-- ripwire stray-content schema=ripwire.stray-content/v1: per local ref, lines/symbols NOT in HEAD: <ref ok= v= base= stray=>; v=unknown = no merge base. at=: commit+dirty+shallow. head=: the HEAD commit, bare 9-hex sha (at= adds +dirty). head_ref=: HEAD's branch (HEAD when detached); that branch itself is not scanned. refs=N: local branches scanned (refs/heads only); unmerged + superseded + merged + unknown = refs. blobs=N: distinct git blobs read for the sweep. unmerged=N: refs whose authored work the live line genuinely lacks. superseded=N: refs whose work the live line re-implemented (removed the same base code). merged=N: refs whose work HEAD already has; omitted from the rows. unknown=N: refs that could not be analysed (v=unknown, e.g. no merge base); never counted merged. -->
<stray-content schema="ripwire.stray-content/v1" head="0412539b9" head_ref="integration/train-1111c" refs="1" blobs="0" unmerged="0" superseded="0" merged="1" unknown="0" filter="fix/" at="0412539b9">
</stray-content>
`````

## `./build/ripwire . --stray-content=lane/ --plan`

*Select the genuinely-unmerged refs of the `lane/` ref family and feed them to merge-scout for a landing order (a fully merged selection yields an empty landing set — still a measurement, disclosed on the root).*

**wall time: 266.95s**

`````
<!-- ripwire landing-plan schema=ripwire.landing-plan/v1: stranded-work landing order across refs, fewest conflicts first. at=: commit+dirty+shallow. -->
<landing-plan schema="ripwire.landing-plan/v1" head="0412539b9" refs="393" unmerged="43" superseded="2" merged="348" undetermined="0" scouted="12" bounded="31" scout-ok="1" at="0412539b9">
<ref name="lane/arise-result" v="unmerged" stray="16331" files="18" scouted="1"/>
<ref name="lane/margin-rescore" v="unmerged" stray="13920" files="12" scouted="1"/>
<ref name="lane/recv-xfile" v="unmerged" stray="9240" files="34" scouted="1"/>
<ref name="lane/py-local-bind" v="unmerged" stray="7070" files="8" scouted="1"/>
<ref name="lane/served-syms-result" v="unmerged" stray="6345" files="8" scouted="1"/>
<ref name="lane/orient-narrow-v3" v="unmerged" stray="3273" files="46" scouted="1"/>
<ref name="lane/for-howitworks-067" v="unmerged" stray="3247" files="39" scouted="1"/>
<ref name="lane/m1-lookback-harness" v="unmerged" stray="3164" files="14" scouted="1"/>
<ref name="lane/orient-map-067" v="unmerged" stray="2475" files="40" scouted="1"/>
<ref name="lane/served-syms-prereg" v="unmerged" stray="2134" files="4" scouted="1"/>
<ref name="lane/crossctx-external-prereg" v="unmerged" stray="2054" files="6" scouted="1"/>
<ref name="lane/for-noise" v="unmerged" stray="1820" files="47" scouted="1"/>
<ref name="lane/manifest-row" v="unmerged" stray="1747" files="8" scouted="0"/>
<ref name="lane/for-tonly" v="unmerged" stray="1728" files="11" scouted="0"/>
<ref name="lane/arise-line-ranking" v="unmerged" stray="1538" files="7" scouted="0"/>
<ref name="lane/for-noise-body-slot" v="unmerged" stray="1524" files="39" scouted="0"/>
<ref name="lane/row-features-2" v="unmerged" stray="1218" files="11" scouted="0"/>
<ref name="lane/research-abstention" v="unmerged" stray="898" files="2" scouted="0"/>
<ref name="lane/agent-trap" v="unmerged" stray="863" files="13" scouted="0"/>
<ref name="lane/row-features" v="unmerged" stray="840" files="10" scouted="0"/>
<ref name="lane/rank-fusion" v="unmerged" stray="581" files="13" scouted="0"/>
<ref name="lane/dup-short" v="unmerged" stray="520" files="23" scouted="0"/>
<ref name="lane/legend-g" v="unmerged" stray="376" files="13" scouted="0"/>
<ref name="lane/ind5-glob-imports" v="unmerged" stray="354" files="11" scouted="0"/>
<ref name="lane/ts-const-defs" v="unmerged" stray="347" files="24" scouted="0"/>
<ref name="lane/tracked-in-skipdirs-065" v="unmerged" stray="330" files="14" scouted="0"/>
<ref name="lane/for-transients" v="unmerged" stray="324" files="6" scouted="0"/>
<ref name="lane/nc-union" v="unmerged" stray="311" files="2" scouted="0"/>
… [54615 more display lines; full output is 8028703 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --stray-content=zzzz-no-such-ref --plan`

*A --plan filter that selects NO ref REFUSES (exit 1) naming the substring — before the wave-3 close this fell through to the '>512 refs match' sentence, and --abi under the same filter answered an empty measurement at exit 0.*

**exit code: 1** — **wall time: 7.51s**

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

**exit code: timeout** — **wall time: 600.02s**

`````
(empty)
`````

stderr:

`````

[TIMED OUT]
`````

## `./build/ripwire . --whereis=rankGraphTeleport`

*Which ref's tree defines or mentions SYM — HEAD first, then every local branch. The default lists the kind="def" rows (here the first 60, most on branches, each carrying tip= and date=) and counts the references in <refs count= next=>: on this symbol HEAD's references would fill the 60-row cap before the branch definitions arrive, so the whole list (below) shows fewer definitions, and the default serves the page that shows more of them, whatever its bytes.*

**wall time: 43.37s**

`````
<!-- ripwire whereis schema=ripwire.whereis/v1: every LOCAL ref whose tree holds sym= (refs_scanned=, blobs=), HEAD first: <hit ref= tip= date= p= l= kind= t=>. window: shown= total= capped= has_more= next_offset= offset= limit= (capped=1 cut; next_offset= pastes as offset=). at=: commit+dirty+shallow. next=: the one pasteable follow-up. hits=N: occurrences in HEAD plus every scanned local ref's full tree (the total rows). on-head=1|0: whether HEAD's tree holds it; 0 beside hits = it lives only on a branch. head_labels=index: HEAD kind= from the parsed index; lexical: text heuristic. ref_labels=parsed: another ref's kind= from the index's own tags parse of its blob (one per blob and path; HEAD's own blob takes HEAD's labels); a blob with no line a loose lexical test calls worth parsing is not parsed and its rows read ref; kind=text: such a line no parse read, never a def. unparsed blobs=N: other refs' blobs holding a line worth parsing that no parse read (past the runaway guard, or the parser could not finish); those lines read kind=text; next= lifts the guard. unparsed rows=N: the kind=text rows those blobs gave. hit t_bytes=N: t= previews an N-byte line (over 300 B): 200 B at most, its first bytes cut on a UTF-8 boundary plus an ellipsis. t_cut rows=N: rows of this page whose t= is a preview (each carries t_bytes=); next= replays this page (same listing, window, rows) with every line whole. more hits=N: rows after this page; page on with offset=next_offset. head_date=: a hit without tip= date= has tip= at=, date= this. -->
<whereis schema="ripwire.whereis/v1" sym="rankGraphTeleport" on-head="1" refs_scanned="498" blobs="12640" hits="2242413" head_labels="index" shown="60" capped="1" total="2242413" has_more="1" next_offset="60" offset="0" limit="0" ref_labels="parsed" head_date="2026-11-12" at="0412539b9">
<unparsed blobs="554" rows="3078" next="--whereis=rankGraphTeleport --detail=1"/>
<t_cut rows="4" next="--whereis=rankGraphTeleport --whereis-listing=all --whereis-full-text"/>
<hit ref="HEAD" p="src/graph.h" l="13631" kind="def" t="inline RankedGraph rankGraphTeleport( const Graph&amp; g, const std::vector&lt;float&gt;&amp; p, float alpha = 0.85f )"/>
<hit ref="HEAD" p="present/deck5_ripwire_build.js" l="1157" kind="ref" t="s.addText(&quot;$ ripwire . --callers=rankGraphTeleport&quot;, { x: 8.68, y: 2.1, w: 3.8, h: 0.3, fontFace: MONO, fontSize: 10, color: MUTED, margin: 0 });"/>
<hit ref="HEAD" p="present/deck5_ripwire_build.js" l="1159" kind="ref" t="{ text: &quot;&lt;callers of=\&quot;rankGraphTeleport\&quot;\n  defs=\&quot;1\&quot; count=\&quot;7\&quot; &quot;, options: { color: TEXT } },"/>
<hit ref="HEAD" p="present/deck5_ripwire_build.js" l="1173" kind="ref" t_bytes="413" t="&quot;- The --callers example: `ripwire . --callers=rankGraphTeleport` answered defs=\&quot;1\&quot; count=\&quot;6\&quot; counts_floor=\&quot;1\&quot;, with runEval and rankGraph as its first two rows, on main 4 … [line truncated: 26 more bytes on this line]
<hit ref="HEAD" p="src/cli.h" l="89" kind="ref" t="// tokens on --around=rankGraphTeleport vs 5,860 B at depth 1; the root&apos;s"/>
<hit ref="HEAD" p="src/crossref.h" l="3672" kind="ref" t="// code above the real definition: `--whereis=rankGraphTeleport` opened with three kind=&quot;def&quot; rows into"/>
<hit ref="HEAD" p="src/didyoumean.h" l="238" kind="ref" t="// `--path=rankGraphTeleport,` printed &quot;endpoint not found:  (did you mean &apos;A&apos;?)&quot;. Guarded at the shared walk"/>
<hit ref="HEAD" p="src/eval.h" l="328" kind="ref" t="const std::vector&lt;float&gt; r = rankGraphTeleport( g, diffTeleport( ing, seedMask ) ).rank;"/>
<hit ref="HEAD" p="src/graph.h" l="248" kind="ref" t="// renormalized to Σ=1 in rankGraphTeleport — so every teleport-based"/>
<hit ref="HEAD" p="src/graph.h" l="13562" kind="ref" t="// prior (never the edges) and renormalized in rankGraphTeleport. Every symbol whose name is missing from"/>
<hit ref="HEAD" p="src/graph.h" l="13619" kind="ref" t="// discard out. That is what this used to be: rankGraphTeleport called pageRankDouble, threw away its return,"/>
<hit ref="HEAD" p="src/graph.h" l="13664" kind="ref" t="// `rank = takeRank( rankGraphTeleport( … ), d )` is the only spelling, and it fills both or neither."/>
<hit ref="HEAD" p="src/graph.h" l="13678" kind="ref" t="return rankGraphTeleport( g, std::vector&lt;float&gt;( N, ranked ? 1.0f / float( ranked ) : 0.f ), alpha );"/>
<hit ref="HEAD" p="src/graph.h" l="14302" kind="ref" t="// the anchor-count is not a cliff), run the EXISTING PPR machinery (rankGraphTeleport — the same"/>
<hit ref="HEAD" p="src/graph.h" l="14372" kind="ref" t="const std::vector&lt;float&gt; ppr = rankGraphTeleport( g, p ).rank;"/>
<hit ref="HEAD" p="src/main.cpp" l="1447" kind="ref" t="rw::RankedGraph ranked  = stubbed ? rw::RankedGraph{} : rankGraphTeleport( d.g, churnPriorFromDecayed( d.ing, mined.weights, mined.anyHistory ) );"/>
<hit ref="HEAD" p="src/main.cpp" l="1486" kind="ref" t="rw::RankedGraph    ranked = isDecay ? rankGraphTeleport( d.g, churnDecayTeleportWorkspace( rootDirs, d.ing, &amp;hasChurnEvidence ) )"/>
<hit ref="HEAD" p="src/main.cpp" l="1487" kind="ref" t=": rankGraphTeleport( d.g, churnTeleportWorkspace( rootDirs, d.ing, &quot;18 months ago&quot;, &amp;hasChurnEvidence ) );"/>
<hit ref="HEAD" p="src/main.cpp" l="1501" kind="ref" t="rw::RankedGraph    ranked = rankGraphTeleport( d.g, churnTeleport( d.root, d.ing, &quot;18 months ago&quot;, d.cfg.since.empty() ? nullptr : &amp;sinceScope, &amp;hasChurnEvidence ) );"/>
<hit ref="HEAD" p="src/main.cpp" l="1879" kind="ref" t="rank = rw::takeRank( rankGraphTeleport( g, diffTeleport( ing, changed ) ), rankDisclosure );"/>
<hit ref="HEAD" p="src/mcp.h" l="2831" kind="ref" t="//   queries:[&quot;callers:rankGraphTeleport&quot;, {&quot;verb&quot;:&quot;slice&quot;,&quot;symbol&quot;:&quot;…&quot;}]"/>
<hit ref="HEAD" p="src/mcpindex.h" l="1287" kind="ref" t="// symbols, the rest uniform, then rankGraphTeleport (which also applies the name-quality biasPrior"/>
<hit ref="HEAD" p="src/mcpindex.h" l="1323" kind="ref" t="const auto [ wsRank, wsIters, wsConverged ] = rankGraphTeleport( ix.g, diffTeleport( ix.ing, changed ) );"/>
<hit ref="HEAD" p="src/mcpverbs.h" l="6125" kind="ref" t="// the colon is a SEPARATOR, and `callers: rankGraphTeleport` is how a human writes one. Untrimmed, the"/>
<hit ref="HEAD" p="src/mcpverbs.h" l="6127" kind="ref" t="//   symbol not found: &apos; rankGraphTeleport&apos; (did you mean &apos;rankGraphTeleport&apos;?)"/>
<hit ref="HEAD" p="src/selectorrefuse.h" l="7" kind="ref" t="// (&quot;that file defines no &apos;rankGraphTeleport&apos;&quot;), names the files that DO define the name, and hands back a"/>
… [36 more display lines; full output is 13204 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --whereis=rankGraphTeleport --whereis-listing=all`

*The whole hit list asked for by name: under the same 60-row cap HEAD's references fill the list, so it shows far fewer definitions (here HEAD's one) than the default above (here 60). The default serves the all page only when it shows the same definitions as the defs page in strictly fewer bytes (a tie serves it too).*

**wall time: 36.80s**

`````
<!-- ripwire whereis schema=ripwire.whereis/v1: every LOCAL ref whose tree holds sym= (refs_scanned=, blobs=), HEAD first: <hit ref= tip= date= p= l= kind= t=>. window: shown= total= capped= has_more= next_offset= offset= limit= (capped=1 cut; next_offset= pastes as offset=). at=: commit+dirty+shallow. next=: the one pasteable follow-up. hits=N: occurrences in HEAD plus every scanned local ref's full tree (the total rows). on-head=1|0: whether HEAD's tree holds it; 0 beside hits = it lives only on a branch. head_labels=index: HEAD kind= from the parsed index; lexical: text heuristic. ref_labels=parsed: another ref's kind= from the index's own tags parse of its blob (one per blob and path; HEAD's own blob takes HEAD's labels); a blob with no line a loose lexical test calls worth parsing is not parsed and its rows read ref; kind=text: such a line no parse read, never a def. unparsed blobs=N: other refs' blobs holding a line worth parsing that no parse read (past the runaway guard, or the parser could not finish); those lines read kind=text; next= lifts the guard. unparsed rows=N: the kind=text rows those blobs gave. hit t_bytes=N: t= previews an N-byte line (over 300 B): 200 B at most, its first bytes cut on a UTF-8 boundary plus an ellipsis. t_cut rows=N: rows of this page whose t= is a preview (each carries t_bytes=); next= replays this page (same listing, window, rows) with every line whole. more hits=N: rows after this page; page on with offset=next_offset. head_date=: a hit without tip= date= has tip= at=, date= this. -->
<whereis schema="ripwire.whereis/v1" sym="rankGraphTeleport" on-head="1" refs_scanned="498" blobs="12640" hits="2242413" head_labels="index" shown="60" capped="1" total="2242413" has_more="1" next_offset="60" offset="0" limit="0" ref_labels="parsed" head_date="2026-11-12" at="0412539b9">
<unparsed blobs="554" rows="3078" next="--whereis=rankGraphTeleport --whereis-listing=all --detail=1"/>
<t_cut rows="4" next="--whereis=rankGraphTeleport --whereis-listing=all --whereis-full-text"/>
<hit ref="HEAD" p="src/graph.h" l="13631" kind="def" t="inline RankedGraph rankGraphTeleport( const Graph&amp; g, const std::vector&lt;float&gt;&amp; p, float alpha = 0.85f )"/>
<hit ref="HEAD" p="present/deck5_ripwire_build.js" l="1157" kind="ref" t="s.addText(&quot;$ ripwire . --callers=rankGraphTeleport&quot;, { x: 8.68, y: 2.1, w: 3.8, h: 0.3, fontFace: MONO, fontSize: 10, color: MUTED, margin: 0 });"/>
<hit ref="HEAD" p="present/deck5_ripwire_build.js" l="1159" kind="ref" t="{ text: &quot;&lt;callers of=\&quot;rankGraphTeleport\&quot;\n  defs=\&quot;1\&quot; count=\&quot;7\&quot; &quot;, options: { color: TEXT } },"/>
<hit ref="HEAD" p="present/deck5_ripwire_build.js" l="1173" kind="ref" t_bytes="413" t="&quot;- The --callers example: `ripwire . --callers=rankGraphTeleport` answered defs=\&quot;1\&quot; count=\&quot;6\&quot; counts_floor=\&quot;1\&quot;, with runEval and rankGraph as its first two rows, on main 4 … [line truncated: 26 more bytes on this line]
<hit ref="HEAD" p="src/cli.h" l="89" kind="ref" t="// tokens on --around=rankGraphTeleport vs 5,860 B at depth 1; the root&apos;s"/>
<hit ref="HEAD" p="src/crossref.h" l="3672" kind="ref" t="// code above the real definition: `--whereis=rankGraphTeleport` opened with three kind=&quot;def&quot; rows into"/>
<hit ref="HEAD" p="src/didyoumean.h" l="238" kind="ref" t="// `--path=rankGraphTeleport,` printed &quot;endpoint not found:  (did you mean &apos;A&apos;?)&quot;. Guarded at the shared walk"/>
<hit ref="HEAD" p="src/eval.h" l="328" kind="ref" t="const std::vector&lt;float&gt; r = rankGraphTeleport( g, diffTeleport( ing, seedMask ) ).rank;"/>
<hit ref="HEAD" p="src/graph.h" l="248" kind="ref" t="// renormalized to Σ=1 in rankGraphTeleport — so every teleport-based"/>
<hit ref="HEAD" p="src/graph.h" l="13562" kind="ref" t="// prior (never the edges) and renormalized in rankGraphTeleport. Every symbol whose name is missing from"/>
<hit ref="HEAD" p="src/graph.h" l="13619" kind="ref" t="// discard out. That is what this used to be: rankGraphTeleport called pageRankDouble, threw away its return,"/>
<hit ref="HEAD" p="src/graph.h" l="13664" kind="ref" t="// `rank = takeRank( rankGraphTeleport( … ), d )` is the only spelling, and it fills both or neither."/>
<hit ref="HEAD" p="src/graph.h" l="13678" kind="ref" t="return rankGraphTeleport( g, std::vector&lt;float&gt;( N, ranked ? 1.0f / float( ranked ) : 0.f ), alpha );"/>
<hit ref="HEAD" p="src/graph.h" l="14302" kind="ref" t="// the anchor-count is not a cliff), run the EXISTING PPR machinery (rankGraphTeleport — the same"/>
<hit ref="HEAD" p="src/graph.h" l="14372" kind="ref" t="const std::vector&lt;float&gt; ppr = rankGraphTeleport( g, p ).rank;"/>
<hit ref="HEAD" p="src/main.cpp" l="1447" kind="ref" t="rw::RankedGraph ranked  = stubbed ? rw::RankedGraph{} : rankGraphTeleport( d.g, churnPriorFromDecayed( d.ing, mined.weights, mined.anyHistory ) );"/>
<hit ref="HEAD" p="src/main.cpp" l="1486" kind="ref" t="rw::RankedGraph    ranked = isDecay ? rankGraphTeleport( d.g, churnDecayTeleportWorkspace( rootDirs, d.ing, &amp;hasChurnEvidence ) )"/>
<hit ref="HEAD" p="src/main.cpp" l="1487" kind="ref" t=": rankGraphTeleport( d.g, churnTeleportWorkspace( rootDirs, d.ing, &quot;18 months ago&quot;, &amp;hasChurnEvidence ) );"/>
<hit ref="HEAD" p="src/main.cpp" l="1501" kind="ref" t="rw::RankedGraph    ranked = rankGraphTeleport( d.g, churnTeleport( d.root, d.ing, &quot;18 months ago&quot;, d.cfg.since.empty() ? nullptr : &amp;sinceScope, &amp;hasChurnEvidence ) );"/>
<hit ref="HEAD" p="src/main.cpp" l="1879" kind="ref" t="rank = rw::takeRank( rankGraphTeleport( g, diffTeleport( ing, changed ) ), rankDisclosure );"/>
<hit ref="HEAD" p="src/mcp.h" l="2831" kind="ref" t="//   queries:[&quot;callers:rankGraphTeleport&quot;, {&quot;verb&quot;:&quot;slice&quot;,&quot;symbol&quot;:&quot;…&quot;}]"/>
<hit ref="HEAD" p="src/mcpindex.h" l="1287" kind="ref" t="// symbols, the rest uniform, then rankGraphTeleport (which also applies the name-quality biasPrior"/>
<hit ref="HEAD" p="src/mcpindex.h" l="1323" kind="ref" t="const auto [ wsRank, wsIters, wsConverged ] = rankGraphTeleport( ix.g, diffTeleport( ix.ing, changed ) );"/>
<hit ref="HEAD" p="src/mcpverbs.h" l="6125" kind="ref" t="// the colon is a SEPARATOR, and `callers: rankGraphTeleport` is how a human writes one. Untrimmed, the"/>
<hit ref="HEAD" p="src/mcpverbs.h" l="6127" kind="ref" t="//   symbol not found: &apos; rankGraphTeleport&apos; (did you mean &apos;rankGraphTeleport&apos;?)"/>
<hit ref="HEAD" p="src/selectorrefuse.h" l="7" kind="ref" t="// (&quot;that file defines no &apos;rankGraphTeleport&apos;&quot;), names the files that DO define the name, and hands back a"/>
… [36 more display lines; full output is 13226 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --quality-delta=HEAD~1..HEAD --quality-kinds=complexity,dead-code`

*A ref range run for two of the twelve kinds only: the named kinds' rows are exactly their rows in the full answer, the header names the others (kinds_skipped=, skipped_why="selector"), and a pass no named kind needs does not run. The replay a memory-stopped range answer hands back (kinds_next=) is this flag. Refused without --quality-delta=A..B.*

**wall time: 33.41s**

`````
<!-- ripwire quality-delta schema=ripwire.quality-delta/v1: only what the change made WORSE vs baseline=: regressions= minor= gating=; <r kind= sym= p= was= now= gating= bar=>, <sa> acked. value-ref-excluded=N: internal functions kept off because a table, field or argument in another function or at file scope holds them (matched by name, not a proven call); a floor. stale=N: ack ledger rows whose target no longer applies (sa rows); never gating. stale_by_kind=: stale= split by ack kind (kind:N,...); the sa rows are collapsed. stale_next=: the call printing the sa rows and the full header. preexisting-worse=N: regressions on symbols that existed at baseline; they gate when major. new-symbol=N: findings on NEW code; new-symbol rows never gate, except defect-shape format-arity. register-macro-excluded=N: symbols kept out of dead-code as self-registering test/bench macros; a floor. declined-call-excluded=N: symbols kept out of dead-code only because a declined call may mean them; a floor. api-new-surface=N: new PUBLIC symbols; a count, never gates, not in regressions=. renames=/rename_window_commits=: git rename pairs read over that many commits, to re-file baseline and acks. acked_by_rename=/acked_by_content=: acked= suppressions matched via git renames / an equal body hash. kinds_skipped=: kinds NOT run, so none of their rows is here and every count covers the rest; a count only they feed is absent. skipped_why=selector (the caller chose; stale acks judged for those kinds only) | memory (see ingest_scope=) | selector,memory (both). acked=N: findings suppressed by the ack ledger, listed as sa rows; never gating. base_ref=/target_ref=: the two resolved full shas a range compared (committed trees; at= omitted). churn=unavailable: range form; short-horizon-churn cannot be measured, so its silence is not no churn. -->
<quality-delta schema="ripwire.quality-delta/v1" baseline="ref-pair" regressions="0" minor="0" acked="0" stale="21" preexisting-worse="0" new-symbol="0" gating="0" register-macro-excluded="62" api-new-surface="0" base_ref="d1f3ba3d56a71c2184186f649aa546b578bb8196" target_ref="0412539b91400096c84f50d … [line truncated: 442 more bytes on this line]
</quality-delta>
`````

## `./build/ripwire . --whereis=rankGraphTeleport --whereis-listing=all --whereis-full-text`

*The same page with every t= line whole: the page above previews each line over 300 B (200 B and t_bytes=, the <t_cut rows= next=> naming this call), and --whereis-full-text replays it with the same listing, window, rows and labels. MCP: full_text=true.*

**wall time: 35.35s**

`````
<!-- ripwire whereis schema=ripwire.whereis/v1: every LOCAL ref whose tree holds sym= (refs_scanned=, blobs=), HEAD first: <hit ref= tip= date= p= l= kind= t=>. window: shown= total= capped= has_more= next_offset= offset= limit= (capped=1 cut; next_offset= pastes as offset=). at=: commit+dirty+shallow. next=: the one pasteable follow-up. hits=N: occurrences in HEAD plus every scanned local ref's full tree (the total rows). on-head=1|0: whether HEAD's tree holds it; 0 beside hits = it lives only on a branch. head_labels=index: HEAD kind= from the parsed index; lexical: text heuristic. ref_labels=parsed: another ref's kind= from the index's own tags parse of its blob (one per blob and path; HEAD's own blob takes HEAD's labels); a blob with no line a loose lexical test calls worth parsing is not parsed and its rows read ref; kind=text: such a line no parse read, never a def. unparsed blobs=N: other refs' blobs holding a line worth parsing that no parse read (past the runaway guard, or the parser could not finish); those lines read kind=text; next= lifts the guard. unparsed rows=N: the kind=text rows those blobs gave. more hits=N: rows after this page; page on with offset=next_offset. head_date=: a hit without tip= date= has tip= at=, date= this. -->
<whereis schema="ripwire.whereis/v1" sym="rankGraphTeleport" on-head="1" refs_scanned="498" blobs="12640" hits="2242413" head_labels="index" shown="60" capped="1" total="2242413" has_more="1" next_offset="60" offset="0" limit="0" ref_labels="parsed" head_date="2026-11-12" at="0412539b9">
<unparsed blobs="554" rows="3078" next="--whereis=rankGraphTeleport --whereis-listing=all --detail=1"/>
<hit ref="HEAD" p="src/graph.h" l="13631" kind="def" t="inline RankedGraph rankGraphTeleport( const Graph&amp; g, const std::vector&lt;float&gt;&amp; p, float alpha = 0.85f )"/>
<hit ref="HEAD" p="present/deck5_ripwire_build.js" l="1157" kind="ref" t="s.addText(&quot;$ ripwire . --callers=rankGraphTeleport&quot;, { x: 8.68, y: 2.1, w: 3.8, h: 0.3, fontFace: MONO, fontSize: 10, color: MUTED, margin: 0 });"/>
<hit ref="HEAD" p="present/deck5_ripwire_build.js" l="1159" kind="ref" t="{ text: &quot;&lt;callers of=\&quot;rankGraphTeleport\&quot;\n  defs=\&quot;1\&quot; count=\&quot;7\&quot; &quot;, options: { color: TEXT } },"/>
<hit ref="HEAD" p="present/deck5_ripwire_build.js" l="1173" kind="ref" t="&quot;- The --callers example: `ripwire . --callers=rankGraphTeleport` answered defs=\&quot;1\&quot; count=\&quot;6\&quot; counts_floor=\&quot;1\&quot;, with runEval and rankGraph as its first two rows, on main 40a1895b. On ma … [line truncated: 260 more bytes on this line]
<hit ref="HEAD" p="src/cli.h" l="89" kind="ref" t="// tokens on --around=rankGraphTeleport vs 5,860 B at depth 1; the root&apos;s"/>
<hit ref="HEAD" p="src/crossref.h" l="3672" kind="ref" t="// code above the real definition: `--whereis=rankGraphTeleport` opened with three kind=&quot;def&quot; rows into"/>
<hit ref="HEAD" p="src/didyoumean.h" l="238" kind="ref" t="// `--path=rankGraphTeleport,` printed &quot;endpoint not found:  (did you mean &apos;A&apos;?)&quot;. Guarded at the shared walk"/>
<hit ref="HEAD" p="src/eval.h" l="328" kind="ref" t="const std::vector&lt;float&gt; r = rankGraphTeleport( g, diffTeleport( ing, seedMask ) ).rank;"/>
<hit ref="HEAD" p="src/graph.h" l="248" kind="ref" t="// renormalized to Σ=1 in rankGraphTeleport — so every teleport-based"/>
<hit ref="HEAD" p="src/graph.h" l="13562" kind="ref" t="// prior (never the edges) and renormalized in rankGraphTeleport. Every symbol whose name is missing from"/>
<hit ref="HEAD" p="src/graph.h" l="13619" kind="ref" t="// discard out. That is what this used to be: rankGraphTeleport called pageRankDouble, threw away its return,"/>
<hit ref="HEAD" p="src/graph.h" l="13664" kind="ref" t="// `rank = takeRank( rankGraphTeleport( … ), d )` is the only spelling, and it fills both or neither."/>
<hit ref="HEAD" p="src/graph.h" l="13678" kind="ref" t="return rankGraphTeleport( g, std::vector&lt;float&gt;( N, ranked ? 1.0f / float( ranked ) : 0.f ), alpha );"/>
<hit ref="HEAD" p="src/graph.h" l="14302" kind="ref" t="// the anchor-count is not a cliff), run the EXISTING PPR machinery (rankGraphTeleport — the same"/>
<hit ref="HEAD" p="src/graph.h" l="14372" kind="ref" t="const std::vector&lt;float&gt; ppr = rankGraphTeleport( g, p ).rank;"/>
<hit ref="HEAD" p="src/main.cpp" l="1447" kind="ref" t="rw::RankedGraph ranked  = stubbed ? rw::RankedGraph{} : rankGraphTeleport( d.g, churnPriorFromDecayed( d.ing, mined.weights, mined.anyHistory ) );"/>
<hit ref="HEAD" p="src/main.cpp" l="1486" kind="ref" t="rw::RankedGraph    ranked = isDecay ? rankGraphTeleport( d.g, churnDecayTeleportWorkspace( rootDirs, d.ing, &amp;hasChurnEvidence ) )"/>
<hit ref="HEAD" p="src/main.cpp" l="1487" kind="ref" t=": rankGraphTeleport( d.g, churnTeleportWorkspace( rootDirs, d.ing, &quot;18 months ago&quot;, &amp;hasChurnEvidence ) );"/>
<hit ref="HEAD" p="src/main.cpp" l="1501" kind="ref" t="rw::RankedGraph    ranked = rankGraphTeleport( d.g, churnTeleport( d.root, d.ing, &quot;18 months ago&quot;, d.cfg.since.empty() ? nullptr : &amp;sinceScope, &amp;hasChurnEvidence ) );"/>
<hit ref="HEAD" p="src/main.cpp" l="1879" kind="ref" t="rank = rw::takeRank( rankGraphTeleport( g, diffTeleport( ing, changed ) ), rankDisclosure );"/>
<hit ref="HEAD" p="src/mcp.h" l="2831" kind="ref" t="//   queries:[&quot;callers:rankGraphTeleport&quot;, {&quot;verb&quot;:&quot;slice&quot;,&quot;symbol&quot;:&quot;…&quot;}]"/>
<hit ref="HEAD" p="src/mcpindex.h" l="1287" kind="ref" t="// symbols, the rest uniform, then rankGraphTeleport (which also applies the name-quality biasPrior"/>
<hit ref="HEAD" p="src/mcpindex.h" l="1323" kind="ref" t="const auto [ wsRank, wsIters, wsConverged ] = rankGraphTeleport( ix.g, diffTeleport( ix.ing, changed ) );"/>
<hit ref="HEAD" p="src/mcpverbs.h" l="6125" kind="ref" t="// the colon is a SEPARATOR, and `callers: rankGraphTeleport` is how a human writes one. Untrimmed, the"/>
<hit ref="HEAD" p="src/mcpverbs.h" l="6127" kind="ref" t="//   symbol not found: &apos; rankGraphTeleport&apos; (did you mean &apos;rankGraphTeleport&apos;?)"/>
<hit ref="HEAD" p="src/selectorrefuse.h" l="7" kind="ref" t="// (&quot;that file defines no &apos;rankGraphTeleport&apos;&quot;), names the files that DO define the name, and hands back a"/>
<hit ref="HEAD" p="bench/capsweep/capsweep.py" l="173" kind="ref" t="# all and passes through untouched — `. --pattern=\&apos;rankGraphTeleport($A, $B, $C)\&apos;` is a tree-sitter pattern"/>
… [35 more display lines; full output is 13638 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --whereis=computeOnePairOverlap --with-history`

*Same, plus a git-history <fate> row (never / removed-by-commit) for names no tree carries.*

**wall time: 43.56s**

`````
<!-- ripwire whereis schema=ripwire.whereis/v1: every LOCAL ref whose tree holds sym= (refs_scanned=, blobs=), HEAD first: <hit ref= tip= date= p= l= kind= t=>. window: shown= capped= (capped=1 cut). at=: commit+dirty+shallow. next=: the one pasteable follow-up. hits=N: occurrences in HEAD plus every scanned local ref's full tree (the total rows). on-head=1|0: whether HEAD's tree holds it; 0 beside hits = it lives only on a branch. head_labels=index: HEAD kind= from the parsed index; lexical: text heuristic. ref_labels=parsed: another ref's kind= from the index's own tags parse of its blob (one per blob and path; HEAD's own blob takes HEAD's labels); a blob with no line a loose lexical test calls worth parsing is not parsed and its rows read ref; kind=text: such a line no parse read, never a def. hit refs=N: N scanned refs hold this same definition (or kind=text) line (path + text); printed once for the first by name, whose ref= tip= date= l= it carries; defs page only, absent = one ref; hits= counts every copy, listing=all prints each. folded=N: def (or text) rows of other refs a listed row's refs= stands for; shown + more + folded + refs count = hits on the first page. listing=defs|refs: only those kind= rows listed (defs: def and text); under defs <refs count=N next=> counts the kind=ref rows and next= lists them; the window counts listed rows; default: defs if it lists more defs than all, else if shorter; a def the parser does not model (define_method, setattr, assignment) is a counted ref. head_date=: a hit without tip= date= has tip= at=, date= this. -->
<whereis schema="ripwire.whereis/v1" sym="computeOnePairOverlap" on-head="1" refs_scanned="498" blobs="12640" hits="175253" head_labels="index" shown="2" capped="0" listing="defs" folded="497" ref_labels="parsed" head_date="2026-11-12" at="0412539b9">
<history probed="1" head="0412539b9" commits="6445" removed-names="55428"/>
<hit ref="HEAD" p="src/mergescout.h" l="696" kind="def" t="inline PairOverlap computeOnePairOverlap( std::size_t a, std::size_t b, const Arm&amp; armA, const Arm&amp; armB )"/>
<hit ref="arm/for-howitworks-067-f2add" tip="abcbd8b7f" date="2026-10-02" p="src/mergescout.h" l="696" kind="def" refs="498" t="inline PairOverlap computeOnePairOverlap( std::size_t a, std::size_t b, const Arm&amp; armA, const Arm&amp; armB )"/>
<refs count="174754" next="--whereis=computeOnePairOverlap --whereis-listing=refs"/>
</whereis>
`````

## `./build/ripwire . --flags`

*The dark-content dashboard: gates BUILT but OFF. CHANGED: no longer invents gates from comments/heredocs, so the count only reflects real ifndef/define, CMake option(), and getenv gates.*

**wall time: 2.75s**

`````
<!-- ripwire flags schema=ripwire.flags/v1: BUILT but DARK: <gate name= kind=compile|cmake|env default= dark= regions=/loc=(#if only) reads= p= l=> with <read p= l=> sites. reads_capped=: 1 = cut. next=: the one pasteable follow-up. gates=/dark_gates=: gate rows (never cut) / those whose default keeps the guarded code out of the build. compile=/cmake=/env=: gates by kind: ifndef/define header gate, CMake option(), getenv read. files=N: files this verb scanned for gates (source + CMakeLists), wider than the map's corpus. -->
<!-- ROWS AND WHAT IS NEVER CUT: the gate rows ARE the answer this verb was asked for and are never windowed, capped or paged, and gates/dark_gates/compile/cmake/env/files on the root plus regions/loc/reads/dark on every gate are counted over the FULL set before any cap exists. What pages is the read SITES under one gate, at 8 a gate by default: a gate whose sites were cut says shown_reads= (the rows this run printed) with reads_capped="1", against the reads= total already on the same element, and the more reads= child keeps naming the remainder. The pair is emitted ONLY on a gate that was cut, never as a capped="0" on the gates that fit. limit=N raises the per gate cap (offset=M skips that many sites in every gate), detail lifts it entirely, and next= on the root is the exact pasteable invocation that shows every site this run dropped. -->
<flags schema="ripwire.flags/v1" gates="151" dark_gates="142" compile="13" cmake="13" env="125" files="4506" next="--flags --limit=19">
<gate name="FIXTURE_DARK_FEATURE" kind="compile" default="0" dark="1" regions="2" loc="13" reads="2" p="test/flagsfix/wiringFlags.h" l="10">
<read p="test/flagsfix/feature.cpp" l="10"/>
<read p="test/flagsfix/sub/nested.cpp" l="5"/>
</gate>
<gate name="PROFILE_PMC_VERBOSE" kind="compile" default="0" dark="1" regions="2" loc="11" reads="2" p="src/infra/profilePmc.h" l="78">
<read p="src/infra/profilePmc.h" l="81"/>
<read p="src/infra/profilePmc.h" l="480"/>
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
… [552 more display lines; full output is 33218 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --flags --flip=RIPWIRE_ASAN`

*Blast radius of turning ONE gate on: live code, symbols, transitive reach, covering tests.*

**wall time: 3.54s**

`````
<!-- ripwire flip schema=ripwire.flip/v1: the blast radius of flipping one build gate: the regions and symbols it toggles. root=: p= relative to it. -->
<flip schema="ripwire.flip/v1" gate="RIPWIRE_ASAN" kind="cmake" default="OFF" dark="1" runtime="0" p="CMakeLists.txt" l="14" family="1" regions="0" loc="0" branches="0" bindings="0" hosts="0" filescope="0" downstream="0" dependents="0" tests="0" untested="0" files="4506" root=".">
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
<build n="14" note="CMake read sites: a switch here can add whole translation units or link targets, which this verb does NOT follow">
<c p="CMakeLists.txt" l="14"/>
<c p="CMakeLists.txt" l="18"/>
<c p="CMakeLists.txt" l="24"/>
<c p="CMakeLists.txt" l="36"/>
<c p="CMakeLists.txt" l="38"/>
<c p="CMakeLists.txt" l="785"/>
<c p="CMakeLists.txt" l="1075"/>
<c p="CMakeLists.txt" l="1080"/>
<c p="CMakeLists.txt" l="1116"/>
<c p="CMakeLists.txt" l="1129"/>
<c p="CMakeLists.txt" l="1134"/>
<c p="CMakeLists.txt" l="1173"/>
<c p="CMakeLists.txt" l="1226"/>
<c p="CMakeLists.txt" l="1228"/>
</build>
</flip>
`````

## `./build/ripwire . --flags --flip=RIPWIRE_ASA`

*Unknown-gate refusal (exit 1) with a did-you-mean from a real edit distance (one character off RIPWIRE_ASAN).*

**exit code: 1** — **wall time: 2.61s**

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

**wall time: 8.53s**

`````
{"v":1,"verb":"plan-lanes","at":"0412539b9","root":".","task":"add a --since filter to the doc-drift verb and cover it with tests","source":"partition","requested":3,"lane_count":3,"claim_key":"path+scope+name","on_conflict":"producing-lane-rebases","corpus":{"files":4497,"symbols":39563,"edges":389 … [line truncated: 338 more bytes on this line]
"symbols":[{"p":"./src/docdrift.h","n":"DriftResult","scope":"DriftResult","l":286,"id":"./src/docdrift.h::DriftResult::DriftResult"},
{"p":"./src/docdrift.h","n":"computeDocDrift","scope":"docdrift","l":2441,"id":"./src/docdrift.h::docdrift::computeDocDrift"},
{"p":"./src/docdrift.h","n":"kDocDriftLegend","scope":"docdrift","l":2739,"id":"./src/docdrift.h::docdrift::kDocDriftLegend"},
{"p":"./src/docdrift.h","n":"writeDocDriftPage","scope":"docdrift","l":2909,"id":"./src/docdrift.h::docdrift::writeDocDriftPage"},
{"p":"./src/mcpverbs.h","n":"docDriftText","scope":"rw","l":672,"id":"./src/mcpverbs.h::rw::docDriftText"},
{"p":"./src/verbs_change.h","n":"runDocDrift","scope":"","l":1689,"id":null}]},"lanes":[{"id":"lane-0","task":"add a --since filter to the doc-drift verb and cover it with tests","claims":{"symbols":[{"p":"./src/recall.h","n":"RecallDocSections","scope":"RecallDocSections","key":"1fde8981b6f3e741"," … [line truncated: 179 more bytes on this line]
{"p":"./src/docdrift.h","n":"writeGateability","scope":"docdrift","key":"42c456dfb55faee4","id":"./src/docdrift.h::docdrift::writeGateability","id_addressable":true,"id_collides_with":0,"l":2685,"ord":0,"overloads":1,"amb":2,"cx":6,"ccx":6,"churn":37,"tested":0},
{"p":"./src/serialize.h","n":"kForFileTailCodeFirstLegend","scope":"rw","key":"5289e55d3d76c1b9","id":"./src/serialize.h::rw::kForFileTailCodeFirstLegend","id_addressable":true,"id_collides_with":0,"l":1181,"ord":0,"overloads":1,"amb":0,"cx":0,"ccx":0,"churn":486,"tested":0},
{"p":"./src/darkflags.h","n":"writeFlags","scope":"darkflags","key":"5c2c4a2b311b8dba","id":"./src/darkflags.h::darkflags::writeFlags","id_addressable":true,"id_collides_with":0,"l":1298,"ord":0,"overloads":1,"amb":1,"cx":8,"ccx":8,"churn":32,"tested":0},
{"p":"./src/docdrift.h","n":"docDriftNextAttr","scope":"docdrift","key":"7723ed789a1c9c09","id":"./src/docdrift.h::docdrift::docDriftNextAttr","id_addressable":true,"id_collides_with":0,"l":2864,"ord":0,"overloads":1,"amb":0,"cx":6,"ccx":5,"churn":37,"tested":0},
{"p":"./src/docdrift.h","n":"recordWeakDisclosures","scope":"docdrift","key":"972779210e49c0cf","id":"./src/docdrift.h::docdrift::recordWeakDisclosures","id_addressable":true,"id_collides_with":0,"l":2430,"ord":0,"overloads":1,"amb":0,"cx":2,"ccx":1,"churn":37,"tested":0},
{"p":"./src/main.cpp","n":"scanReportVerbPrecedence","scope":"","key":"9ab981e987e8108e","id":null,"id_addressable":false,"id_collides_with":0,"l":3039,"ord":0,"overloads":1,"amb":0,"cx":8,"ccx":11,"churn":478,"tested":0},
{"p":"./src/pageview.h","n":"secondaryCutAttrs","scope":"rw","key":"a10ea8d3bdca1dfb","id":"./src/pageview.h::rw::secondaryCutAttrs","id_addressable":true,"id_collides_with":0,"l":399,"ord":0,"overloads":1,"amb":0,"cx":3,"ccx":2,"churn":28,"tested":0},
{"p":"./src/main.cpp","n":"emitNoteAddUnprovenDefs","scope":"","key":"a950332ccfce6b8d","id":null,"id_addressable":false,"id_collides_with":0,"l":696,"ord":0,"overloads":1,"amb":1,"cx":2,"ccx":1,"churn":478,"tested":0},
{"p":"./src/docdrift.h","n":"sortDocsByLiveDrift","scope":"docdrift","key":"d5de682411b9a9a9","id":"./src/docdrift.h::docdrift::sortDocsByLiveDrift","id_addressable":true,"id_collides_with":0,"l":2390,"ord":0,"overloads":1,"amb":0,"cx":2,"ccx":2,"churn":37,"tested":0},
{"p":"./src/mcpverbs.h","n":"unknownSubVerbRefusal","scope":"rw","key":"e336d39b0a6addea","id":"./src/mcpverbs.h::rw::unknownSubVerbRefusal","id_addressable":true,"id_collides_with":0,"l":6193,"ord":0,"overloads":1,"amb":0,"cx":3,"ccx":2,"churn":612,"tested":0},
{"p":"./src/cli.h","n":"validateModifierGuards","scope":"rw","key":"ec2848a4801493a2","id":"./src/cli.h::rw::validateModifierGuards","id_addressable":true,"id_collides_with":0,"l":4769,"ord":0,"overloads":1,"amb":2,"cx":79,"ccx":72,"churn":575,"tested":0}],
"files":[{"p":"./src/cli.h","symbols":1,"churn":575,"ccx":72,"hotspot_rank":8},
{"p":"./src/darkflags.h","symbols":1,"churn":32,"ccx":8,"hotspot_rank":68},
{"p":"./src/docdrift.h","symbols":4,"churn":37,"ccx":14,"hotspot_rank":45},
{"p":"./src/main.cpp","symbols":2,"churn":478,"ccx":12,"hotspot_rank":5},
{"p":"./src/mcpverbs.h","symbols":1,"churn":612,"ccx":2,"hotspot_rank":4},
{"p":"./src/pageview.h","symbols":1,"churn":28,"ccx":2,"hotspot_rank":165},
{"p":"./src/recall.h","symbols":1,"churn":48,"ccx":0,"hotspot_rank":43},
{"p":"./src/serialize.h","symbols":1,"churn":486,"ccx":0,"hotspot_rank":2}]},"blast_radius":{"reaches":30,"files_total":10,"capped":false,"files":["./src/cli.h","./src/darkflags.h","./src/docdrift.h","./src/flipimpact.h","./src/main.cpp","./src/mcp.h","./src/mcpserver.h","./src/mcpverbs.h","./src/ve … [line truncated: 57 more bytes on this line]
"tests_total":0,"tests_capped":false,"tests_granularity":"claimed-symbols","untested":30,"module_span":4,"notes":[],
"execution":{"policy":"codex-lane/v1","model":"gpt-5.6-sol","reasoning":"xhigh","rule":"wide-contract-work","basis":"structural-only","signals":{"claims":12,"files":8,"module_span":4,"max_ccx":72,"sum_ccx":110,"ambiguous_calls":6,"blast_reaches":30,"contract_touches":1,"conflicts":0,"untested":30,"t … [line truncated: 139 more bytes on this line]
{"id":"lane-1","task":"add a --since filter to the doc-drift verb and cover it with tests","claims":{"symbols":[{"p":"./src/gitmine.h","n":"gitWindowBoundarySha","scope":"rw","key":"18627516699d7062","id":"./src/gitmine.h::rw::gitWindowBoundarySha","id_addressable":true,"id_collides_with":0,"l":2178 … [line truncated: 70 more bytes on this line]
{"p":"./src/jsrunner.h","n":"matchesDefaultInclude","scope":"rw::jsrunner","key":"1e885c432f6da6bb","id":"./src/jsrunner.h::rw::jsrunner::matchesDefaultInclude","id_addressable":true,"id_collides_with":0,"l":549,"ord":0,"overloads":1,"amb":0,"cx":11,"ccx":11,"churn":22,"tested":0},
… [70 more display lines; full output is 20666 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --plan-lanes --brief=<scratch>/aux/lanes_brief.txt`

*NEW VERB, explicit form: one line per lane, lane boundaries are the ones you wrote (the defensible mode).*

**wall time: 9.38s**

Input file:

`````
add a --since filter to the doc-drift verb
add the CLI parse arm and help text for the new filter
write regression tests for the new filter
`````

`````
{"v":1,"verb":"plan-lanes","at":"0412539b9","root":".","task":null,"source":"brief","requested":3,"lane_count":3,"claim_key":"path+scope+name","on_conflict":"producing-lane-rebases","corpus":{"files":4497,"symbols":39563,"edges":38970,"ambiguous":3456,"unresolved":18664},"carve":null,"core":{"files" … [line truncated: 4 more bytes on this line]
"symbols":[]},"lanes":[{"id":"lane-0","task":"add a --since filter to the doc-drift verb","claims":{"symbols":[{"p":"./src/docdrift.h","n":"recordUnchecked","scope":"docdrift","key":"12641dab14abc8fd","id":"./src/docdrift.h::docdrift::recordUnchecked","id_addressable":true,"id_collides_with":0,"l":2 … [line truncated: 72 more bytes on this line]
{"p":"./src/docdrift.h","n":"sortWeakGroupsByPath","scope":"docdrift","key":"1944ba506280ff80","id":"./src/docdrift.h::docdrift::sortWeakGroupsByPath","id_addressable":true,"id_collides_with":0,"l":2401,"ord":0,"overloads":1,"amb":0,"cx":1,"ccx":0,"churn":37,"tested":0},
{"p":"./src/mcpverbs.h","n":"docDriftText","scope":"rw","key":"1fa68e8d93c05a59","id":"./src/mcpverbs.h::rw::docDriftText","id_addressable":true,"id_collides_with":0,"l":672,"ord":0,"overloads":1,"amb":0,"cx":1,"ccx":0,"churn":612,"tested":0},
{"p":"./src/recall.h","n":"docFileMask","scope":"rw","key":"3149a219f599664c","id":"./src/recall.h::rw::docFileMask","id_addressable":true,"id_collides_with":0,"l":113,"ord":0,"overloads":1,"amb":0,"cx":4,"ccx":4,"churn":48,"tested":0},
{"p":"./src/docdrift.h","n":"writeDocDriftPage","scope":"docdrift","key":"380b7de5df1cfd73","id":"./src/docdrift.h::docdrift::writeDocDriftPage","id_addressable":true,"id_collides_with":0,"l":2909,"ord":0,"overloads":1,"amb":10,"cx":14,"ccx":15,"churn":37,"tested":0},
{"p":"./src/docdrift.h","n":"computeDocDrift","scope":"docdrift","key":"3b19cc3d8996c3b2","id":"./src/docdrift.h::docdrift::computeDocDrift","id_addressable":true,"id_collides_with":0,"l":2441,"ord":0,"overloads":1,"amb":1,"cx":26,"ccx":38,"churn":37,"tested":0},
{"p":"./src/docdrift.h","n":"DriftResult","scope":"DriftResult","key":"422ab39546b6e0bd","id":"./src/docdrift.h::DriftResult::DriftResult","id_addressable":true,"id_collides_with":0,"l":286,"ord":0,"overloads":1,"amb":0,"cx":0,"ccx":0,"churn":37,"tested":0},
{"p":"./src/docdrift.h","n":"writeGateability","scope":"docdrift","key":"42c456dfb55faee4","id":"./src/docdrift.h::docdrift::writeGateability","id_addressable":true,"id_collides_with":0,"l":2685,"ord":0,"overloads":1,"amb":2,"cx":6,"ccx":6,"churn":37,"tested":0},
{"p":"./src/verbs_change.h","n":"runDocDrift","scope":"","key":"904831e5c0f66b39","id":null,"id_addressable":false,"id_collides_with":0,"l":1689,"ord":0,"overloads":1,"amb":1,"cx":5,"ccx":4,"churn":83,"tested":0},
{"p":"./src/ensemble.h","n":"kEnsembleChurnSince","scope":"ensemble","key":"a34fc78c05bf56a8","id":"./src/ensemble.h::ensemble::kEnsembleChurnSince","id_addressable":true,"id_collides_with":0,"l":120,"ord":0,"overloads":1,"amb":0,"cx":0,"ccx":0,"churn":23,"tested":0},
{"p":"./src/mcpverbs.h","n":"unknownSubVerbRefusal","scope":"rw","key":"e336d39b0a6addea","id":"./src/mcpverbs.h::rw::unknownSubVerbRefusal","id_addressable":true,"id_collides_with":0,"l":6193,"ord":0,"overloads":1,"amb":0,"cx":3,"ccx":2,"churn":612,"tested":0},
{"p":"./src/docdrift.h","n":"kDocDriftLegend","scope":"docdrift","key":"ff2ba74637bbbebf","id":"./src/docdrift.h::docdrift::kDocDriftLegend","id_addressable":true,"id_collides_with":0,"l":2739,"ord":0,"overloads":1,"amb":0,"cx":0,"ccx":0,"churn":37,"tested":0}],
"files":[{"p":"./src/docdrift.h","symbols":7,"churn":37,"ccx":60,"hotspot_rank":45},
{"p":"./src/ensemble.h","symbols":1,"churn":23,"ccx":0,"hotspot_rank":123},
{"p":"./src/mcpverbs.h","symbols":2,"churn":612,"ccx":2,"hotspot_rank":4},
{"p":"./src/recall.h","symbols":1,"churn":48,"ccx":4,"hotspot_rank":43},
{"p":"./src/verbs_change.h","symbols":1,"churn":83,"ccx":4,"hotspot_rank":34}],
"symbols_total":3814,"symbols_capped":true},"blast_radius":{"reaches":24,"files_total":8,"capped":false,"files":["./src/docdrift.h","./src/fordocbody.h","./src/main.cpp","./src/mcp.h","./src/mcpserver.h","./src/mcpverbs.h","./src/recall.h","./src/verbs_for.h"]},"tests_to_run":[],
"tests_total":0,"tests_capped":false,"tests_granularity":"claimed-symbols","untested":24,"module_span":5,"notes":[],
"execution":{"policy":"codex-lane/v1","model":"gpt-5.6-sol","reasoning":"xhigh","rule":"wide-contract-work","basis":"structural-only","signals":{"claims":12,"files":5,"module_span":5,"max_ccx":38,"sum_ccx":70,"ambiguous_calls":14,"blast_reaches":24,"contract_touches":1,"conflicts":0,"untested":24,"t … [line truncated: 139 more bytes on this line]
{"id":"lane-1","task":"add the CLI parse arm and help text for the new filter","claims":{"symbols":[{"p":"./scripts/optremarks.py","n":"main","scope":"","key":"01b3b880f77d1512","id":null,"id_addressable":false,"id_collides_with":178,"l":285,"ord":0,"overloads":1,"amb":0,"cx":23,"ccx":31,"churn":18, … [line truncated: 12 more bytes on this line]
{"p":"./scripts/merge_resolve.py","n":"main","scope":"","key":"0618162fab697309","id":null,"id_addressable":false,"id_collides_with":178,"l":208,"ord":0,"overloads":1,"amb":0,"cx":17,"ccx":34,"churn":4,"tested":0},
{"p":"./src/cli.h","n":"HelpLine","scope":"rw","key":"1489844dbc310b82","id":"./src/cli.h::rw::HelpLine","id_addressable":true,"id_collides_with":0,"l":3017,"ord":0,"overloads":1,"amb":0,"cx":0,"ccx":0,"churn":575,"tested":0},
{"p":"./src/cli.h","n":"HelpFilter","scope":"HelpFilter","key":"3103a5e8bfc33d38","id":"./src/cli.h::HelpFilter::HelpFilter","id_addressable":true,"id_collides_with":0,"l":3096,"ord":0,"overloads":1,"amb":0,"cx":0,"ccx":0,"churn":575,"tested":0},
{"p":"./docs/docs_commands_build.py","n":"main","scope":"","key":"4015853681ded3bc","id":null,"id_addressable":false,"id_collides_with":178,"l":900,"ord":0,"overloads":1,"amb":0,"cx":19,"ccx":28,"churn":19,"tested":0},
{"p":"./src/mcprefusal.h","n":"kMcpValueFields","scope":"rw::mcprefuse","key":"4a7106e488a2aa80","id":"./src/mcprefusal.h::rw::mcprefuse::kMcpValueFields","id_addressable":true,"id_collides_with":0,"l":304,"ord":0,"overloads":1,"amb":0,"cx":0,"ccx":0,"churn":51,"tested":0},
{"p":"./src/query.h","n":"tryParsePredicateOnAll","scope":"query","key":"786acc4dbfec612b","id":"./src/query.h::query::tryParsePredicateOnAll","id_addressable":false,"id_collides_with":1,"l":113,"ord":0,"overloads":2,"amb":0,"cx":1,"ccx":0,"churn":20,"tested":0},
{"p":"./src/cli.h","n":"printUsageTier","scope":"rw","key":"82b7af67acdca479","id":"./src/cli.h::rw::printUsageTier","id_addressable":true,"id_collides_with":0,"l":3147,"ord":0,"overloads":1,"amb":0,"cx":2,"ccx":1,"churn":575,"tested":0},
{"p":"./src/crossref.h","n":"writeWhereisTextCut","scope":"crossref","key":"9a3ef6403f53ce21","id":"./src/crossref.h::crossref::writeWhereisTextCut","id_addressable":true,"id_collides_with":0,"l":4563,"ord":0,"overloads":1,"amb":1,"cx":3,"ccx":3,"churn":97,"tested":0},
… [59 more display lines; full output is 18803 bytes on 1 raw line(s)]
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

**wall time: 2.04s**

`````
<!-- ripwire layout schema=ripwire.layout/v1: struct field layout vs cache lines: offsets, padding, hot/cold split candidates. root=: p= relative to it. sym=: the aggregate name asked for. found=1: a C-family struct/class/union body was located for sym=. defs=N: same-name aggregate defs found; a more element counts any not shown. mirror=: single|match|mismatch (byte drift, exits nonzero)|stub|spelling, over same-name defs. asserts=N: static_assert tripwires in indexed files that mention sym=. conflicts=N: asserts contradicting the computed size (agree=0 rows); nonzero exits nonzero. scanned=N: indexed C-family files read for asserts. agg=: struct, class or union. fields=N: member rows listed. modeled=0: size/align/tail pad not computed; off= only up to the first unknown. ty=: the field type as written, before macro expansion (as= gives the expansion). sz=N: field bytes incl. array extent (LP64 model); sized=0 instead when unknown. al=N: field alignment in bytes (LP64 model). off=N: computed byte offset; absent after an earlier field of unknown size. bits=N bit=B: a bitfield N bits wide from bit B of its 1-byte unit at off=. std_abi=: the C++ standard library (libc++|libstdc++) whose std:: member sizes were used: the one this binary was built against. def size=/align=/tail_pad=: computed bytes, alignment, trailing padding (modeled=1 only). -->
<layout schema="ripwire.layout/v1" sym="Symbol" found="1" defs="1" mirror="single" asserts="2" conflicts="0" scanned="1043" std_abi="libc++" root=".">
<def p="src/model.h" l="817" agg="struct" modeled="1" fields="29" size="112" align="8" tail_pad="0">
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
<f n="evWhy" ty="std::array&lt;std::uint8_t, kEvWhyTagCount&gt;" sz="8" al="1" off="50"/>
<f n="params" ty="std::uint16_t" sz="2" al="2" off="58"/>
<f n="maxNest" ty="std::uint8_t" sz="1" al="1" off="60"/>
<f n="arityExact" ty="std::uint8_t" sz="1" al="1" off="61"/>
<f n="testScope" ty="std::uint8_t" bits="1" bit="0" sz="1" al="1" off="62"/>
<f n="internalLinkage" ty="std::uint8_t" bits="1" bit="1" sz="1" al="1" off="62"/>
<f n="scopeRootsStd" ty="std::uint8_t" bits="1" bit="2" sz="1" al="1" off="62"/>
<f n="fnLocal" ty="std::uint8_t" bits="1" bit="3" sz="1" al="1" off="62"/>
<f n="paramsMin" ty="std::uint8_t" bits="4" bit="4" sz="1" al="1" off="62"/>
<f n="extentSuspect" ty="std::uint8_t" bits="4" bit="0" sz="1" al="1" off="63"/>
<f n="rankFlags" ty="std::uint8_t" bits="4" bit="4" sz="1" al="1" off="63"/>
<f n="name" ty="std::string" sz="24" al="8" off="64"/>
<f n="scope" ty="std::string" sz="24" al="8" off="88"/>
</def>
<assert p="src/model.h" l="1025" kind="mention" t="static_assert( sizeof( Symbol ) == 64 + 2 * sizeof( std::string ), &quot;Symbol size changed — verify the new field uses the smallest type + is grouped (SoA); see model.h&quot; )"/>
<assert p="src/renamemine.h" l="616" kind="mention" t="static_assert( kRuleCount &lt;= std::numeric_limits&lt;decltype( firedRuleMask( std::declval&lt;const Symbol&amp;&gt;(), std::string_view() ) )&gt;::digits, &quot;firedRuleMask holds one bit per naming rule — widen it before kRuleCount outgro" … [line truncated: 2 more bytes on this line]
</layout>
`````

## `./build/ripwire . --layout=Lang`

*The honest refusal (exit 1): Lang is an `enum class`, not a struct — no offsets are fabricated.*

**exit code: 1** — **wall time: 1.77s**

`````
(empty)
`````

stderr:

`````
ripwire: --layout: 'Lang' is an enum, --layout models structs (a scoped/unscoped enum's underlying type is not a byte layout)
`````

## `./build/ripwire . --doc-drift`

*Which of this repo's doc claims are now false. CHANGED: row attribute at= renamed to tgt= (at= is now only the root sha stamp).*

**wall time: 4.66s**

`````
<!-- ripwire doc-drift schema=ripwire.doc-drift/v1: markdown anchors that no longer hold: <doc p=> of <a k= l= c= why= ref= want= got= tgt=>; unchecked/dated rows disclose the rest. failed_capped=/weak_capped=: 1 = cut. at=: commit+dirty+shallow. next=: the one pasteable follow-up. docs=N: markdown docs scanned for anchors; docs minus clean = the doc rows. clean=N: docs with no failed anchor (drift and dated 0); not proof every anchor was checked. checked=N: anchors verified against the index; checked + unchecked = anchors. prose=N: value anchors dropped as prose (name not in code); subtracted from anchors=, never checked. corpus=N: files the anchors were checked against (index + config/build exts); 0 = no anchor shape, no scan. drift=/dated=: anchors that no longer hold / anchors skipped as dated (unverifiable by date). unchecked=N: anchors not proved (the unchecked rows give each reason); checked + unchecked = anchors. doc shown_failed=/failed_total=: a rows printed / all failed anchors (drift+dated); cut at 12, detail=1 lifts. a kind=/rec=: dated-record, an author-dated failed anchor in dated= / its evidence: line|block|title|stamp. a sym=: the symbol the doc names on that file:line; line-moved = that symbol no longer spans the line. more weak=N: w rows of this group withheld; shown_weak + N = its n=; detail=1 lists all. shown_weak=N: w rows printed of n= (cut at 12 a doc, weak_capped=1); detail=1 lists all. w resolves-to=: the indexed symbol spanning that line; not proof it is the one the doc meant. unchecked r=/note=: why n= anchors were not proved, and what was still checked for them. dated r=/note=: the dating mark that moved n= failed anchors into dated= instead of drift=. -->
<doc-drift schema="ripwire.doc-drift/v1" docs="270" clean="239" anchors="7711" checked="3648" unchecked="4063" drift="85" dated="116" prose="26" corpus="4660" at="0412539b9" next="--doc-drift --detail=1">
<doc p="docs/research/answer-completeness.md" anchors="187" checked="83" drift="16" dated="0" shown_failed="12" failed_capped="1" failed_total="16">
<a k="file-line" l="341" c="25" why="line-moved" ref="src/pageview.h:292" sym="pageDisclosure" got="(file scope)" tgt="src/pageview.h:346"/>
<a k="file-line" l="349" c="99" why="line-moved" ref="src/serialize.h:4169" sym="kForLensDefaultTopN" got="serialize" tgt="src/serialize.h:1074"/>
<a k="file-line" l="353" c="89" why="line-moved" ref="src/serialize.h:4435" sym="kForPayloadBudgetBytes" got="cleanSig" tgt="src/serialize.h:963"/>
<a k="file-line" l="356" c="42" why="line-moved" ref="src/serialize.h:1010" sym="kForFileTailShownCap" got="forSigsBudgets" tgt="src/serialize.h:1151"/>
<a k="file-line" l="358" c="89" why="line-moved" ref="src/serialize.h:5481" sym="kForAnchorBodyBudgetBytes" got="(file scope)" tgt="src/serialize.h:1127"/>
<a k="file-line" l="360" c="88" why="line-moved" ref="src/serialize.h:5800" sym="kForCompactSurfaceBudgetBytes" got="(file scope)" tgt="src/serialize.h:1246"/>
<a k="file-line" l="366" c="43" why="line-moved" ref="src/serialize.h:6534" sym="kWithGraphNodeCap" got="packSignatures" tgt="src/serialize.h:9532"/>
<a k="file-line" l="367" c="51" why="line-moved" ref="src/forpage.h:287" sym="kForPageRowsDefault" got="forCandidatePageDoc" tgt="src/forpage.h:71"/>
<a k="file-line" l="380" c="44" why="line-moved" ref="src/serialize.h:2460" sym="kFillOrderThreshold" got="kRankByDisclosure" tgt="src/serialize.h:1618"/>
<a k="file-line" l="382" c="62" why="line-moved" ref="src/main.cpp:1283" sym="kRecentRows" got="(file scope)" tgt="src/main.cpp:1230"/>
<a k="file-line" l="399" c="48" why="line-moved" ref="src/serialize.h:5317" sym="kMaxExpandSibs" got="(file scope)" tgt="src/serialize.h:7713"/>
<a k="file-line" l="400" c="50" why="line-moved" ref="src/serialize.h:5342" sym="kMaxExpandIncludes" got="headRoundRobinOrder" tgt="src/serialize.h:7722"/>
<more drift="4"/>
</doc>
<doc p="prompts/help-wanted/graph-unit-tests.md" anchors="164" checked="95" drift="8" dated="0">
<a k="file-line" l="96" c="6" why="range-straddles" ref="src/infra/Diagnostics.h:265-321" got="RW_CHECK_" tgt="src/infra/Diagnostics.h:321"/>
<a k="file-line" l="99" c="57" why="line-moved" ref="Diagnostics.h:543-550" sym="DISCLOSE" got="(file scope)" tgt="src/infra/Diagnostics.h:616"/>
<a k="file-line" l="132" c="18" why="range-straddles" ref="src/graph.h:2742-2755" sym="buildGraph" got="recordSubmoduleBind" tgt="src/graph.h:2755"/>
<a k="file-line" l="155" c="17" why="line-moved" ref="src/graph.h:3228" sym="biasPrior" got="buildExternalVetoTables" tgt="src/graph.h:13590"/>
<a k="file-line" l="170" c="3" why="line-moved" ref="src/graph.h:3915" sym="computeImpure" got="StringTokenPosition" tgt="src/graph.h:16304"/>
<a k="const" l="301" c="421" why="const-value" ref="maxIterationCount = 90" want="90" got="400" tgt="test/verify_pagerank.cpp:59"/>
<a k="const" l="301" c="510" why="const-value" ref="maxIterationCount = 89" want="89" got="400" tgt="test/verify_pagerank.cpp:59"/>
<a k="const" l="303" c="18" why="const-value" ref="maxIterationCount = 1" want="1" got="400" tgt="test/verify_pagerank.cpp:59"/>
</doc>
<doc p="CHANGELOG.md" anchors="1948" checked="800" drift="7" dated="15" shown_failed="12" failed_capped="1" failed_total="22">
<a k="file-line" l="1300" c="5" why="missing-file" kind="dated-record" rec="block" ref="cmd-split-window.c:58"/>
<a k="file-line" l="1432" c="43" why="missing-file" kind="dated-record" rec="block" ref="cmd-queue.c:625"/>
… [251 more display lines; full output is 25354 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --doc-drift --gateability`

*The finishable to-do list: docs whose LIVE failing anchors a date-stamp would reclassify.*

**wall time: 4.84s**

`````
<!-- ripwire doc-drift schema=ripwire.doc-drift/v1: markdown anchors that no longer hold: <doc p=> of <a k= l= c= why= ref= want= got= tgt=>; unchecked/dated rows disclose the rest. failed_capped=/weak_capped=: 1 = cut. at=: commit+dirty+shallow. next=: the one pasteable follow-up. docs=N: markdown docs scanned for anchors; docs minus clean = the doc rows. clean=N: docs with no failed anchor (drift and dated 0); not proof every anchor was checked. checked=N: anchors verified against the index; checked + unchecked = anchors. prose=N: value anchors dropped as prose (name not in code); subtracted from anchors=, never checked. corpus=N: files the anchors were checked against (index + config/build exts); 0 = no anchor shape, no scan. drift=/dated=: anchors that no longer hold / anchors skipped as dated (unverifiable by date). unchecked=N: anchors not proved (the unchecked rows give each reason); checked + unchecked = anchors. doc shown_failed=/failed_total=: a rows printed / all failed anchors (drift+dated); cut at 12, detail=1 lifts. a kind=/rec=: dated-record, an author-dated failed anchor in dated= / its evidence: line|block|title|stamp. a sym=: the symbol the doc names on that file:line; line-moved = that symbol no longer spans the line. more weak=N: w rows of this group withheld; shown_weak + N = its n=; detail=1 lists all. shown_weak=N: w rows printed of n= (cut at 12 a doc, weak_capped=1); detail=1 lists all. w resolves-to=: the indexed symbol spanning that line; not proof it is the one the doc meant. unchecked r=/note=: why n= anchors were not proved, and what was still checked for them. dated r=/note=: the dating mark that moved n= failed anchors into dated= instead of drift=. -->
<doc-drift schema="ripwire.doc-drift/v1" docs="270" clean="239" anchors="7711" checked="3648" unchecked="4063" drift="85" dated="116" prose="26" corpus="4660" at="0412539b9" next="--doc-drift --detail=1">
<doc p="docs/research/answer-completeness.md" anchors="187" checked="83" drift="16" dated="0" shown_failed="12" failed_capped="1" failed_total="16">
<a k="file-line" l="341" c="25" why="line-moved" ref="src/pageview.h:292" sym="pageDisclosure" got="(file scope)" tgt="src/pageview.h:346"/>
<a k="file-line" l="349" c="99" why="line-moved" ref="src/serialize.h:4169" sym="kForLensDefaultTopN" got="serialize" tgt="src/serialize.h:1074"/>
<a k="file-line" l="353" c="89" why="line-moved" ref="src/serialize.h:4435" sym="kForPayloadBudgetBytes" got="cleanSig" tgt="src/serialize.h:963"/>
<a k="file-line" l="356" c="42" why="line-moved" ref="src/serialize.h:1010" sym="kForFileTailShownCap" got="forSigsBudgets" tgt="src/serialize.h:1151"/>
<a k="file-line" l="358" c="89" why="line-moved" ref="src/serialize.h:5481" sym="kForAnchorBodyBudgetBytes" got="(file scope)" tgt="src/serialize.h:1127"/>
<a k="file-line" l="360" c="88" why="line-moved" ref="src/serialize.h:5800" sym="kForCompactSurfaceBudgetBytes" got="(file scope)" tgt="src/serialize.h:1246"/>
<a k="file-line" l="366" c="43" why="line-moved" ref="src/serialize.h:6534" sym="kWithGraphNodeCap" got="packSignatures" tgt="src/serialize.h:9532"/>
<a k="file-line" l="367" c="51" why="line-moved" ref="src/forpage.h:287" sym="kForPageRowsDefault" got="forCandidatePageDoc" tgt="src/forpage.h:71"/>
<a k="file-line" l="380" c="44" why="line-moved" ref="src/serialize.h:2460" sym="kFillOrderThreshold" got="kRankByDisclosure" tgt="src/serialize.h:1618"/>
<a k="file-line" l="382" c="62" why="line-moved" ref="src/main.cpp:1283" sym="kRecentRows" got="(file scope)" tgt="src/main.cpp:1230"/>
<a k="file-line" l="399" c="48" why="line-moved" ref="src/serialize.h:5317" sym="kMaxExpandSibs" got="(file scope)" tgt="src/serialize.h:7713"/>
<a k="file-line" l="400" c="50" why="line-moved" ref="src/serialize.h:5342" sym="kMaxExpandIncludes" got="headRoundRobinOrder" tgt="src/serialize.h:7722"/>
<more drift="4"/>
</doc>
<doc p="prompts/help-wanted/graph-unit-tests.md" anchors="164" checked="95" drift="8" dated="0">
<a k="file-line" l="96" c="6" why="range-straddles" ref="src/infra/Diagnostics.h:265-321" got="RW_CHECK_" tgt="src/infra/Diagnostics.h:321"/>
<a k="file-line" l="99" c="57" why="line-moved" ref="Diagnostics.h:543-550" sym="DISCLOSE" got="(file scope)" tgt="src/infra/Diagnostics.h:616"/>
<a k="file-line" l="132" c="18" why="range-straddles" ref="src/graph.h:2742-2755" sym="buildGraph" got="recordSubmoduleBind" tgt="src/graph.h:2755"/>
<a k="file-line" l="155" c="17" why="line-moved" ref="src/graph.h:3228" sym="biasPrior" got="buildExternalVetoTables" tgt="src/graph.h:13590"/>
<a k="file-line" l="170" c="3" why="line-moved" ref="src/graph.h:3915" sym="computeImpure" got="StringTokenPosition" tgt="src/graph.h:16304"/>
<a k="const" l="301" c="421" why="const-value" ref="maxIterationCount = 90" want="90" got="400" tgt="test/verify_pagerank.cpp:59"/>
<a k="const" l="301" c="510" why="const-value" ref="maxIterationCount = 89" want="89" got="400" tgt="test/verify_pagerank.cpp:59"/>
<a k="const" l="303" c="18" why="const-value" ref="maxIterationCount = 1" want="1" got="400" tgt="test/verify_pagerank.cpp:59"/>
</doc>
<doc p="CHANGELOG.md" anchors="1948" checked="800" drift="7" dated="15" shown_failed="12" failed_capped="1" failed_total="22">
<a k="file-line" l="1300" c="5" why="missing-file" kind="dated-record" rec="block" ref="cmd-split-window.c:58"/>
<a k="file-line" l="1432" c="43" why="missing-file" kind="dated-record" rec="block" ref="cmd-queue.c:625"/>
… [279 more display lines; full output is 26643 bytes on 1 raw line(s)]
`````

Tail of the same output — the `<gateability>` section:

`````
<gateability docs="26" projected_drift="0">
<fix p="docs/research/answer-completeness.md" live="16"/>
<fix p="prompts/help-wanted/graph-unit-tests.md" live="8"/>
<fix p="CHANGELOG.md" live="7"/>
<fix p="test/docdriftfix/NOTES.md" live="7"/>
<fix p="THIRD_PARTY.md" live="6"/>
<fix p="README.md" live="5"/>
<fix p="changelog.d/uses-unarmed.md" live="4"/>
<fix p="docs/LSP.md" live="4"/>
<fix p="prompts/help-wanted/kotlin-scope-functions.md" live="4"/>
<fix p="changelog.d/touch-sym.md" live="3"/>
<fix p="CONTRIBUTING.md" live="2"/>
<fix p="docs/COMMANDS.md" live="2"/>
<fix p="prompts/help-wanted/uses-qualified-selector.md" live="2"/>
<fix p="test/docdriftfix/live_notes.md" live="2"/>
<fix p="test/gateabilityfix/UNDATED.md" live="2"/>
<fix p="bench/nestcal/r1-2026-08-07/REPORT.md" live="1"/>
<fix p="docs/EVALS.md" live="1"/>
<fix p="docs/LINEAGE.md" live="1"/>
<fix p="docs/OPTREMARKS.md" live="1"/>
<fix p="prompts/help-wanted/nesting-refusals-visible.md" live="1"/>
<fix p="prompts/help-wanted/scala-jvm-bridge.md" live="1"/>
<fix p="prompts/help-wanted/ts-literal-receivers.md" live="1"/>
<fix p="skills/ripwire-fresh-eyes/SKILL.md" live="1"/>
<fix p="skills/ripwire-mcp/SKILL.md" live="1"/>
`````

## `./build/ripwire . --doc-drift --with-history`

*Same report, with git history splitting stale mentions into deleted-by-commit vs never-existed.*

**wall time: 6.41s**

`````
<!-- ripwire doc-drift schema=ripwire.doc-drift/v1: markdown anchors that no longer hold: <doc p=> of <a k= l= c= why= ref= want= got= tgt=>; unchecked/dated rows disclose the rest. failed_capped=/weak_capped=: 1 = cut. at=: commit+dirty+shallow. next=: the one pasteable follow-up. docs=N: markdown docs scanned for anchors; docs minus clean = the doc rows. clean=N: docs with no failed anchor (drift and dated 0); not proof every anchor was checked. checked=N: anchors verified against the index; checked + unchecked = anchors. prose=N: value anchors dropped as prose (name not in code); subtracted from anchors=, never checked. corpus=N: files the anchors were checked against (index + config/build exts); 0 = no anchor shape, no scan. drift=/dated=: anchors that no longer hold / anchors skipped as dated (unverifiable by date). unchecked=N: anchors not proved (the unchecked rows give each reason); checked + unchecked = anchors. doc shown_failed=/failed_total=: a rows printed / all failed anchors (drift+dated); cut at 12, detail=1 lifts. a kind=/rec=: dated-record, an author-dated failed anchor in dated= / its evidence: line|block|title|stamp. a sym=: the symbol the doc names on that file:line; line-moved = that symbol no longer spans the line. more weak=N: w rows of this group withheld; shown_weak + N = its n=; detail=1 lists all. shown_weak=N: w rows printed of n= (cut at 12 a doc, weak_capped=1); detail=1 lists all. w resolves-to=: the indexed symbol spanning that line; not proof it is the one the doc meant. unchecked r=/note=: why n= anchors were not proved, and what was still checked for them. dated r=/note=: the dating mark that moved n= failed anchors into dated= instead of drift=. -->
<doc-drift schema="ripwire.doc-drift/v1" docs="270" clean="244" anchors="7711" checked="3630" unchecked="4081" drift="75" dated="108" prose="26" corpus="4660" at="0412539b9" next="--doc-drift --detail=1">
<history probed="1" head="0412539b9" commits="6445" removed-names="55428"/>
<doc p="docs/research/answer-completeness.md" anchors="187" checked="83" drift="16" dated="0" shown_failed="12" failed_capped="1" failed_total="16">
<a k="file-line" l="341" c="25" why="line-moved" ref="src/pageview.h:292" sym="pageDisclosure" got="(file scope)" tgt="src/pageview.h:346"/>
<a k="file-line" l="349" c="99" why="line-moved" ref="src/serialize.h:4169" sym="kForLensDefaultTopN" got="serialize" tgt="src/serialize.h:1074"/>
<a k="file-line" l="353" c="89" why="line-moved" ref="src/serialize.h:4435" sym="kForPayloadBudgetBytes" got="cleanSig" tgt="src/serialize.h:963"/>
<a k="file-line" l="356" c="42" why="line-moved" ref="src/serialize.h:1010" sym="kForFileTailShownCap" got="forSigsBudgets" tgt="src/serialize.h:1151"/>
<a k="file-line" l="358" c="89" why="line-moved" ref="src/serialize.h:5481" sym="kForAnchorBodyBudgetBytes" got="(file scope)" tgt="src/serialize.h:1127"/>
<a k="file-line" l="360" c="88" why="line-moved" ref="src/serialize.h:5800" sym="kForCompactSurfaceBudgetBytes" got="(file scope)" tgt="src/serialize.h:1246"/>
<a k="file-line" l="366" c="43" why="line-moved" ref="src/serialize.h:6534" sym="kWithGraphNodeCap" got="packSignatures" tgt="src/serialize.h:9532"/>
<a k="file-line" l="367" c="51" why="line-moved" ref="src/forpage.h:287" sym="kForPageRowsDefault" got="forCandidatePageDoc" tgt="src/forpage.h:71"/>
<a k="file-line" l="380" c="44" why="line-moved" ref="src/serialize.h:2460" sym="kFillOrderThreshold" got="kRankByDisclosure" tgt="src/serialize.h:1618"/>
<a k="file-line" l="382" c="62" why="line-moved" ref="src/main.cpp:1283" sym="kRecentRows" got="(file scope)" tgt="src/main.cpp:1230"/>
<a k="file-line" l="399" c="48" why="line-moved" ref="src/serialize.h:5317" sym="kMaxExpandSibs" got="(file scope)" tgt="src/serialize.h:7713"/>
<a k="file-line" l="400" c="50" why="line-moved" ref="src/serialize.h:5342" sym="kMaxExpandIncludes" got="headRoundRobinOrder" tgt="src/serialize.h:7722"/>
<more drift="4"/>
</doc>
<doc p="prompts/help-wanted/graph-unit-tests.md" anchors="164" checked="95" drift="8" dated="0">
<a k="file-line" l="96" c="6" why="range-straddles" ref="src/infra/Diagnostics.h:265-321" got="RW_CHECK_" tgt="src/infra/Diagnostics.h:321"/>
<a k="file-line" l="99" c="57" why="line-moved" ref="Diagnostics.h:543-550" sym="DISCLOSE" got="(file scope)" tgt="src/infra/Diagnostics.h:616"/>
<a k="file-line" l="132" c="18" why="range-straddles" ref="src/graph.h:2742-2755" sym="buildGraph" got="recordSubmoduleBind" tgt="src/graph.h:2755"/>
<a k="file-line" l="155" c="17" why="line-moved" ref="src/graph.h:3228" sym="biasPrior" got="buildExternalVetoTables" tgt="src/graph.h:13590"/>
<a k="file-line" l="170" c="3" why="line-moved" ref="src/graph.h:3915" sym="computeImpure" got="StringTokenPosition" tgt="src/graph.h:16304"/>
<a k="const" l="301" c="421" why="const-value" ref="maxIterationCount = 90" want="90" got="400" tgt="test/verify_pagerank.cpp:59"/>
<a k="const" l="301" c="510" why="const-value" ref="maxIterationCount = 89" want="89" got="400" tgt="test/verify_pagerank.cpp:59"/>
<a k="const" l="303" c="18" why="const-value" ref="maxIterationCount = 1" want="1" got="400" tgt="test/verify_pagerank.cpp:59"/>
</doc>
<doc p="test/docdriftfix/NOTES.md" anchors="30" checked="21" drift="7" dated="0">
<a k="file-line" l="9" c="64" why="line-moved" ref="code.h:23" sym="stableHelper" got="movedHelper" tgt="test/docdriftfix/code.h:17"/>
… [230 more display lines; full output is 25560 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --from-trace=-`

*Map a pasted stack trace onto indexed symbols. CHANGED: in_corpus= now reports the real count (was 0).*

**wall time: 1.97s**

Input file:

`````
AddressSanitizer:DEADLYSIGNAL
=================================================================
==41337==ERROR: AddressSanitizer: SEGV on unknown address 0x000000000018 (pc 0x000102f4a1c8 bp 0x00016d2f1a40 sp 0x00016d2f19e0 T0)
    #0 0x102f4a1c8 in rw::rankGraphTeleport(Graph const&, std::vector<float> const&, float) src/graph.h:13633
    #1 0x102f3e884 in rw::rankGraph(Graph const&, float) src/graph.h:13676
    #2 0x102e11f30 in runDefaultMap(MainDispatch const&) src/main.cpp:1761
    #3 0x102e01a44 in main src/main.cpp:4270
    #4 0x1a2b3c0dc in start+0x9dc (dyld:arm64e+0x60dc)
==41337==ABORTING
`````

`````
<ctx schema="ripwire.from-trace/v1" task="&lt;stdin&gt;" next="--slice=@src/graph.h:13633" est_tokens="2033">
<!-- ripwire from-trace schema=ripwire.from-trace/v1: trace frames mapped to indexed symbols, innermost first; the innermost in-corpus body included. window: shown= total= capped= (capped=1 cut). est_tokens=: price as emitted (an upper bound under compact). <d r=N>: rank N in this ranking, rows in r= order. <d cx= ccx=>: cyclomatic/cognitive complexity. <d in=N>: N callers in the index (absent: not measured). sc=: enclosing scope; the full id is p::sc::n (p= of the row or its <f>) and selectors take it. next=: the one pasteable follow-up. task=: the trace source this bundle maps, verbatim (a file path, stdin, or an MCP label). src=/format=: the trace read and its dominant frame format, python|asan|node|compiler|generic. frame_lines=/parsed=: frame-shaped input lines / those yielding a path:line; the rest matched no format. in_corpus=: parsed frames in indexed files; always suspects= + merged= + unresolved=. suspects=/merged=/unresolved=: frame rows / folded into a claimed symbol / unresolved rows (indexed file, no def). skipped=N: frames outside every root, listed as skipped rows, never ranked. rank=N: frame order, innermost in-corpus first; p= is the trace's own path:line, defs are sigs l=. resolved_by=name|line: bound by the frame's own name, else by the def enclosing its line. innermost=1: the innermost in-corpus frame (rank 1); its full body is served. -->
<!-- ledger: budget=7500 bytes (allowance 9583 bytes = ceiling + the single-entry overshoot a whole first signature costs) -->
<trace src="&lt;stdin&gt;" format="asan" frame_lines="5" parsed="4" in_corpus="4" skipped="0" merged="0" unresolved="0" suspects="4">
<frame rank="1" n="rankGraphTeleport" t="fn" p="src/graph.h:13633" resolved_by="name" innermost="1"/>
<frame rank="2" n="rankGraph" t="fn" p="src/graph.h:13676" resolved_by="name"/>
<frame rank="3" n="runDefaultMap" t="fn" p="src/main.cpp:1761" resolved_by="name"/>
<frame rank="4" n="main" t="fn" p="src/main.cpp:4270" resolved_by="name"/>
</trace>
<sigs>
<d l="13631" n="rankGraphTeleport" sc="rw" p="src/graph.h" cx="5" ccx="8" in="7" r="1" next="--expand=src/graph.h:rankGraphTeleport">
<doc>PageRank with an explicit teleport / personalization vector p (Σp = 1). The prior is name-quality-biased through biasPrior() so all rank modes share one weighting seam; the transition matrix (edges</doc>inline RankedGraph rankGraphTeleport( const Graph&amp; g, const std::vector&lt;float&gt;&am … [line truncated: 31 more bytes on this line]
<d l="13674" n="rankGraph" sc="rw" p="src/graph.h" cx="2" ccx="1" in="10" r="2">
<doc>uniform-teleport PageRank (the default). A kRankFlagNotNamed unit (model.h) has no edge and a 0 prior weight, so the uniform share is over the ranked nodes: every other node&apos;s teleport is the value it</doc>inline RankedGraph rankGraph( const Graph&amp; g, float alpha = 0.85f )</d>
<d l="1759" n="runDefaultMap" p="src/main.cpp" cx="224" ccx="313" in="1" r="3">int runDefaultMap( const MainDispatch&amp; d )</d>
<d l="4268" n="main" p="src/main.cpp" cx="20" ccx="22" in="0" r="4">int main( int argc, char** argv )</d>
</sigs>
<bodies shown="1" total="1" capped="0">
<b t="fn" l="13631" p="src/graph.h" n="rankGraphTeleport">
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
… [18 more display lines; full output is 5082 bytes on 29 raw line(s)]
`````

## `./build/ripwire . --notes`

*List all field notes (write-side memory) — the committed .ripwire_notes at the repo root, each with the sha/branch it was recorded at.*

**wall time: 2.16s**

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

**wall time: 2.00s**

`````
<ctx schema="ripwire.pack-task/v1" task="add a new output format flag to the CLI" route="subtoken+body:declined(add;189-carriers,62-defs)" root="." est_tokens="4066" budget_tokens="6000">
<!-- ripwire pack-task schema=ripwire.pack-task/v1: one-call task bundle for task= under budget_tokens=: <sigs>
<d n= sc= l= p=> ranking, <far>
<s t= n= p=> ranked but over 1 hop out (of_top= ranked rows) > <bodies>
<b t= n= p= l=> with <calls>
<c n= l=> callees > <callers>
<s rel=caller|callee shared=> 1-hop from the bodies (of_top= bodies; shared= bodies reached, absent at 1) > notes > <tests>
<test p= run=> (run= when derivable). window: shown= total= capped= (capped=1 cut). est_tokens=: price as emitted (an upper bound under compact). root=: p= relative to it. <d r=N>: rank N in this ranking, rows in r= order. <d cx= ccx=>: cyclomatic/cognitive complexity. <d in=N>: N callers in the ind … [line truncated: 384 more bytes on this line]
<!-- ledger: budget=12744 bytes (6000-token target, ceiling 14160) | ranking: full | bodies: kept 5 of 6 (capped) | callers: 16 of 16 | notes: none | tests: none | far: 6 of 6 -->
<sigs>
<d l="3157" n="printUsage" sc="rw" p="src/cli.h" cx="1" ccx="0" in="1" r="1" next="--expand=src/cli.h:printUsage">
<doc>Print the authoritative CLI usage and flag catalog to the caller-provided output stream</doc>inline void printUsage( std::FILE* out ) noexcept</d>
<d l="480" n="wrapCliAddPost" sc="rw" p="src/wrap.h" cx="4" ccx="2" in="1" r="2">
<doc>claude&apos;s `mcp add … -- ripwire --mcp`: the flag goes on the end of that command line, ahead of its newline</doc>inline std::string wrapCliAddPost( const AgentTarget&amp; row, std::string_view toolsArg )</d>
<d l="111" n="AgentTarget" sc="AgentTarget" p="src/wrap.h" cx="0" ccx="0" in="0" r="3">struct AgentTarget</d>
<d l="736" n="wrapEmitCliFirst" sc="rw" p="src/wrap.h" cx="10" ccx="5" in="1" r="4">
<doc>ONE recipe path for every agent that can shell out, and the point is that the RECOMMENDATION does not vary by agent — only the MCP alternative does. Before this there were four near-identical CLI-fi</doc>inline void wrapEmitCliFirst( const AgentTarget&amp; row, const std::string&amp; token, c … [line truncated: 83 more bytes on this line]
<d l="463" n="wrapWritesToolsArg" sc="rw" p="src/wrap.h" cx="6" ccx="1" in="3" r="5">
<doc>mcp-tools pass-through. Written into the server command only where its argument shape is known to be one more plain argument: the JSON args arrays (cursor/windsurf/gemini), opencode&apos;s command array</doc>inline bool wrapWritesToolsArg( const AgentTarget&amp; row ) noexcept</d>
<d l="1950" n="classNewGroupXml" sc="rw" p="src/testmap.h" cx="8" ccx="11" in="1" r="6">inline std::string classNewGroupXml( const IngestResult&amp; ing, std::span&lt;const ClassNewRow&gt; rows, std::string_view rootPrefix, EscapeFn ex )</d>
<far of_top="12" shown="6" total="6" capped="0">
<s t="fn" n="callHierarchyPageNext" p="src/nextverb.h:190"/>
<s t="fn" n="fileSubjectNote" p="src/forfilepage.h:711"/>
<s t="var" n="kJsonShapeModifiers" p="src/main.cpp:3545"/>
<s t="fn" n="cliRefusesFileList" p="src/situ.h:213"/>
<s t="fn" n="toUint" p="src/tracein.h:103"/>
<s t="cls" n="McpValueSpec" p="src/mcprefusal.h:268"/>
</far>
</sigs>
<bodies shown="5" total="6" capped="1">
… [84 more display lines; full output is 12156 bytes on 77 raw line(s)]
`````

## `./build/ripwire . --pack-task="add a new output format flag to the CLI" --partition=3`

*Fan-out form: one shared core + 3 per-agent slices carved along call-graph communities.*

**wall time: 3.25s**

`````
<ctx-partitions schema="ripwire.pack-task/v1" partitions="3" requested="3" core_symbols="6" surface="42" modules="20" split="0" budget_per_agent_tokens="6000" core_budget_tokens="2040" partition_budget_tokens="3960" total_bytes="21347" overlap_mean="0.024" overlap_max="0.037" shared_symbols="2" unio … [line truncated: 36 more bytes on this line]
<!-- ripwire pack-task schema=ripwire.pack-task/v1: N minimally overlapping agent bundles carved along call-graph communities plus one shared core; each <bundle> wraps a <ctx>; bundle role=core|partition i= symbols= modules= bytes= tokens=: one agent's ctx, symbols= ids assigned, bytes= its size; tokens= = est_tokens= = bytes/2.36 (flat, the densest rate; the inner ctx est_tokens= is language-weighted). Inner ctx task= root= budget_tokens= dropped_positive=: the task, p= base, the slice's token target, ranked candidates its budget cut. of_top=: rows ranked (far) / bodies (callers); s rel=caller|callee shared=: 1-hop edge, bodies reached (absent at 1). window: shown= total= capped= (capped=1 cut). run_unknown=1: no runner derivable (a guess would be worse). est_tokens=: price as emitted (an upper bound under compact). <d r=N>: rank N in this ranking, rows in r= order. <d cx= ccx=>: cyclomatic/cognitive complexity. <d in=N>: N callers in the index (absent: not measured). route=: the ranker: name-exact(X) = the task names symbol X (anchors: its evidence), subtoken+body = conceptual BM25 (:broad = 1-2 plain words, plain rg may also win; :declined(...) = a name hit refused as a common name). sc=: enclosing scope; the full id is p::sc::n (p= of the row or its <f>) and selectors take it. next=: the one pasteable follow-up. pure=1: const/constexpr signature (Swift: non-mutating) and no transitive side effect found; a hint. partitions=/requested=: partitions carved / asked for. modules=/split=: call-graph groups found / cuts forced to split one. core_symbols=/surface=: ids in the shared core / core plus the assignable remainder. budget_per_agent_tokens=: one agent's budget, core_budget_tokens= plus partition_budget_tokens=. total_bytes=N: bytes of all bundles together. overlap_mean=/overlap_max=: pairwise Jaccard over the ids partitions name, before trimming. shared_symbols=/union_symbols=: ids two or more partitions name / ids any partition names. core_overlap=: share of the core surface a partition reaches anyway. layer=: built-in arch layer (game|infra|render|math|audio|ai|test) from a dir name in p=; absent if none. -->
<bundle role="core" symbols="6" bytes="2735" tokens="1159" est_tokens="1159">
<ctx task="add a new output format flag to the CLI" route="subtoken+body:declined(add;189-carriers,62-defs)" root="." dropped_positive="2" est_tokens="937" budget_tokens="2040">
<!-- slice budget=4332 bytes (2040-token target, ceiling 4814) | ranking: capped | bodies: kept 2 of 6 (capped) | callers: kept 1 of 16 | notes: none | tests: none | far: none -->
<sigs shown="4" total="6" capped="1">
<d l="3157" n="printUsage" sc="rw" p="src/cli.h" cx="1" ccx="0" in="1" r="1" next="--expand=src/cli.h:printUsage">
<doc>Print the authoritative CLI usage and flag catalog to the caller-provided output stream</doc>inline void printUsage( std::FILE* out ) noexcept</d>
<d l="480" n="wrapCliAddPost" sc="rw" p="src/wrap.h" cx="4" ccx="2" in="1" r="2">
<doc>claude&apos;s `mcp add … -- ripwire --mcp`: the flag goes on the end of that command line, ahead of…</doc>inline std::string wrapCliAddPost( const AgentTarget&amp; row, std::string_view toolsArg )</d>
<d l="111" n="AgentTarget" sc="AgentTarget" p="src/wrap.h" cx="0" ccx="0" in="0" r="3">struct AgentTarget</d>
<d l="736" n="wrapEmitCliFirst" sc="rw" p="src/wrap.h" cx="10" ccx="5" in="1" r="4">
<doc>ONE recipe path for every agent that can shell out, and the point is that the RECOMMENDATION doe…</doc>inline void wrapEmitCliFirst( const AgentTarget&amp; row, const std::string&amp; token, const std::string_view executablePath, const WrapListing&amp; listing ) noexcept</d>
</sigs>
<bodies shown="2" total="6" capped="1">
<b t="fn" l="3157" p="src/cli.h" n="printUsage">
<![CDATA[inline void printUsage( std::FILE* out ) noexcept { printUsageTier( out, HelpTier::Full, {} ); }]]>
<calls total="1">
<c n="printUsageTier" l="3147">inline bool printUsageTier( std::FILE* out, HelpTier tier, std::string_view want ) noexcept</c>
</calls>
</b>
<b t="fn" l="480" p="src/wrap.h" n="wrapCliAddPost">
<![CDATA[inline std::string wrapCliAddPost( const AgentTarget& row, std::string_view toolsArg )
{
    std::string post( row.mcpAddPost );
    if( !toolsArg.empty() && wrapWritesToolsArg( row ) && post.ends_with( '\n' ) )
    {
        post.insert( post.size() - 1, " " + std::string( toolsArg ) );
    }
    return post;
… [75 more display lines; full output is 24268 bytes on 83 raw line(s)]
`````

## `./build/ripwire . --for="pagerank power iteration" --with-graph`

*Task lens + a compact Mermaid flowchart of the top anchors' 1-hop edges.*

**wall time: 6.57s**

`````
<ctx task="pagerank power iteration" route="subtoken+body" root="." confidence="high" margin_pct="22" at="0412539b9" doc_mentions="5" schema="ripwire.for/v1" bundle="compact" bodies="0" reason="compact-route" budget_bytes="7500" doc_mentions_capped="1" doc_mentions_total="14" est_tokens="8044">
<!-- ripwire for schema=ripwire.for/v1: bundle=/bodies=/reason= the body posture; d: cx= ccx= complexity, in= callers (absent cx/ccx/in = 0), churn= amp= change, clone= tested= 1, sc= scope, id=p::sc::n; total= shown= capped=1 if cut; task= the query; d pure=1 const/constexpr sig, next= the follow-up to paste; d same_as=N: doc+sig text as row n=N (not repeated); route= name-exact(X)|subtoken+body[:broad|:declined]; confidence=/margin_pct= head score drop (low=flat); h l= p= n=, c n= l= (joined for same-named callees, shown= counts them), noedge= no callee resolved; fold kind=bodies: b t= n= p= l= top ranked rows' whole bodies, not the answer; served= of total= in budget_bytes=; slice/skip p= n= l=; skip bytes= next=; a skip makes sigs next= it, sigs_next= the signatures-only re-call; d mem= an owner's direct member names by the index (question words first, names only), mem_more= names cut; t p= file outside sigs (weaker), t sym= its top symbols not in sigs/syms (a pointer, not the answer), r= rank (gap = trimmed); t order: code files first, then doc files (a code question); t page rows go on to file-page row 160 (code question: 160 code rows, docs within row 160); past page 0 (code question: past 40 code rows, a doc past row 40) listed last, head files skipped; past 120 of those p= only, p_only= counts them; t folded=class=N: N p= only rows of that class (doc|config|script|testdata|other) not listed, next= pages to them; d layer=: built-in arch layer (game|infra|render|math|audio|ai|test) from a dir name in p=; d e= its last line (absent=unknown, never 0; l= the name's line); c prov=split: a resolver split arm; may be another arm's (NOT a claim the edge is false) [doc mentions: 5 docs, 3 symbols; doc_mentions=] -->
<!-- root= is the crawl root; p= below is RELATIVE to it (single-root only; absent => p= is ingest's own path, unchanged); at=this commit(+dirty). [budget_bytes= is the default BYTE target this ranked payload was shaped toward: row text shortens toward it, no row of the ranked head is removed for it (sigs past_target=)] [sigs capped=1 with shown=total: rows shrunk, none dropped] [sigs past_target=K: the last K rows are past the budget_bytes target, served because they are rows of the ranked head; none is cut] [sigs sigs_next=: one call serving all total= rows uncut] [docs_dropped=N: N shown rows have a doc comment not printed (r>24 always, r5..24 if capped)] [docs_after_code=N: N doc rows of the shown set moved below its code rows; same rows, reordered, none added or removed; a question naming docs keeps score order] [files_first=N: N rows moved so r=1..8 are distinct files' best rows, score order, a repeated name once; same rows; fold, hops keep score order] [cut: doc_mentions_capped="1" doc_mentions_total="14" — an indexing cap dropped content not shown here]; lego/compose collapse to a counted stub by default (a disclosed cut): total= that section's own pre-cap row count, shown="0" capped="1" (nothing rendered here), next= names the sections=lego,compose flag that restores both sections byte-identically in one call est_tokens= prices this bundle in tokens -->
<sigs shown="40" total="40" capped="1" past_target="14" docs_dropped="24" docs_after_code="6" files_first="7" sigs_next="--for=&apos;pagerank power iteration&apos; --signatures-only --token-budget=6100" next="--expand=src/prconverge.h:73:renderDisclosure">
<d l="422" e="422" n="kScoreTieAbsEps" sc="rw" p="src/eval.h" churn="18" amp="51" pure="1" r="1" next="--expand=src/eval.h:kScoreTieAbsEps">
<doc>NodeId order. Renumbering an otherwise-identical graph (the exact &quot;same probe file, different so…</doc>inline constexpr float kScoreTieAbsEps = 1e-6f</d>
<d l="73" e="144" n="renderDisclosure" sc="rw" p="src/prconverge.h" cx="12" ccx="15" in="14" churn="3" amp="41" r="2">
<doc>Render one form of the disclosure. Empty string whenever there is nothing to say — no power it…</doc>inline std::string renderDisclosure( const RankDisclosure&amp; d, DiscloseAs as )</d>
<d l="99" e="206" n="pageRankDouble" sc="rw" p="src/pagerank.cpp" cx="19" ccx="34" in="2" churn="14" amp="44" tested="1" r="3">
<doc>The PageRank power iteration itself — the numeric kernel every ranked document&apos;s order comes f…</doc>PageRankRun pageRankDouble( const sparseCsr&lt;float&gt;&amp; inEdges, std::span&lt;const double&gt; weightedOutDegree, std::span&lt;const double&gt; teleport, std::span&lt;double&gt; r … [line truncated: 10 more bytes on this line]
<d l="497" e="543" n="rankByText" sc="rw" p="src/mcpverbs.h" cx="11" ccx="19" in="1" churn="612" amp="645" r="4">inline std::string rankByText( const std::string&amp; root, std::string_view mode, int topK, bool stable = false )</d>
<d l="13622" e="13627" n="RankedGraph" sc="RankedGraph" p="src/graph.h" churn="640" amp="867" r="5">struct RankedGraph</d>
<d l="2532" e="2536" n="kChurnRankLegend" sc="rw" p="src/serialize.h" churn="486" amp="577" pure="1" r="6">inline constexpr const char* kChurnRankLegend = &quot;&lt;!-- rank_by=churn: k= is PageRank re-run with the teleport BIASED by git CHANGE-FREQUENCY over window= &quot; &quot;(a c…</d>
<d l="1372" e="1393" n="sliceRdIterationCeiling" sc="slicev" p="src/slice.h" cx="9" ccx="12" in="1" churn="51" amp="103" r="7">inline std::uint32_t sliceRdIterationCeiling() noexcept</d>
<d l="31" e="44" n="PageRankRun" sc="PageRankRun" p="src/pagerank.h" churn="8" amp="37" r="8" mem="disclose">struct PageRankRun</d>
<d l="51" e="56" n="RankDisclosure" sc="RankDisclosure" p="src/prconverge.h" churn="3" amp="27" r="9">
<doc>What a ranked document discloses about the power iteration that ordered it. `isPageRank == false…</doc>struct RankDisclosure</d>
<d l="16408" e="16417" n="navRelevanceWeight" sc="rw" p="src/graph.h" cx="2" ccx="1" in="2" churn="640" amp="869" r="10">inline std::uint32_t navRelevanceWeight( const Graph&amp; g, NodeId n ) noexcept</d>
<d l="13631" e="13659" n="rankGraphTeleport" sc="rw" p="src/graph.h" cx="5" ccx="8" in="7" churn="640" amp="874" r="11">inline RankedGraph rankGraphTeleport( const Graph&amp; g, const std::vector&lt;float&gt;&amp; p, float alpha = 0.85f )</d>
<d l="1247" e="1247" n="kPowerShellPathPrependScope" sc="rw::oswin" p="src/infra/os_win32_logic.h" layer="infra" churn="20" amp="50" pure="1" r="12">inline constexpr std::string_view kPowerShellPathPrependScope = &quot;in PowerShell, for this window</d>
<!-- demote: a <t> in sigs is a lower same-file sibling past answer row 10, a pointer (p= file, sym= name, r= rank), not the answer -->
<t p="src/infra/os_win32_logic.h" sym="powerShellPathPrependHint" r="13"/>
<d l="1168" e="1168" n="path_prepend_hint" sc="rw::os" p="src/infra/os.h" layer="infra" cx="1" in="1" churn="39" amp="85" r="14">inline std::string path_prepend_hint( std::string_view dir )</d>
<t p="src/infra/os_win32_logic.h" sym="powerShellSingleQuote" r="15"/>
<d l="58" e="90" n="HOT_FILES" p="scripts/optremarks.py" churn="18" amp="80" r="16">HOT_FILES = ( &quot;src/pagerank.cpp&quot;, # the power-iteration loop — G2&apos;s no-allocation scope &quot;src/infra/radixSort.h&quot;, # LSD radix entry points &quot;src/infra/radixSort.inl&quot;, # the counting … [line truncated: 76 more bytes on this line]
<d l="2198" e="2206" n="dynamic_map::leftmost_leaf" p="src/infra/dynamic_map.hpp" layer="infra" cx="2" ccx="1" in="7" churn="7" amp="38" pure="1" r="17">handle_t leftmost_leaf() const</d>
<d l="294" e="299" n="doctorPathPrependLine" p="src/verbs_doctor.h" cx="2" ccx="1" in="2" churn="46" amp="136" r="18">inline std::string doctorPathPrependLine( const std::string&amp; selfPath )</d>
<t p="src/infra/dynamic_map.hpp" sym="reverse_iterator" r="19"/>
<t p="src/verbs_doctor.h" sym="doctorWhichRipwire" r="20"/>
<t p="src/serialize.h" sym="rankByLegendFor" r="21"/>
… [164 more display lines; full output is 20225 bytes on 15 raw line(s)]
`````

## `./build/ripwire . --export=cc.json:<scratch>/aux/ripwire2.cc.json`

*Per-file metrics as CodeCharta cc.json.*

**wall time: 7.21s**

`````
(empty)
`````

Artifact written:

`````
  690461 <scratch>/aux/ripwire2.cc.json
{"projectName":"project","apiVersion":"1.3","attributeDescriptors":{"loc":{"title":"Lines of Code","description":"Physical line count","direction":-1},"symbols":{"title":"Symbols","description":"Definitions in the file","direction":-1},"cx":{"title":"Cyclomatic Complexity","description":"Sum of per-symbol cyclomatic complexity","direction":-1},"cognitive_cx":{"title":"Cognitive Complexity","descri
`````

## `./build/ripwire . --batch=<scratch>/aux/batch2.txt`

*One-turn sweep: 4 newline-delimited verb:arg sub-queries answered in ONE deduped <batch>.*

**wall time: 11.29s**

Input file:

`````
for:incremental cache invalidation
callers:rankGraphTeleport
grep:DISCLOSE
lego:Vehicle
`````

`````
<batch schema="ripwire.batch/v1" n="4" requested="4" cap="16">
<!-- ripwire batch schema=ripwire.batch/v1: n= read sub-queries in one sweep (requested=, cap=): each <q> wraps one sub-answer verbatim in CDATA. i=/verb=/ok=: sub-query index, its verb text, 1 answered (payload in CDATA) or 0 failed. <file-scope> (t=modscope): a file's MODULE SCOPE — where a top-level call and an anonymous callback body's calls live; a CALLER, never a callee, with no body to expand. -->
<q i="0" verb="for" ok="1">
<![CDATA[<ctx task="incremental cache invalidation" route="subtoken+body" root="." confidence="high" margin_pct="22" at="0412539b9" doc_mentions="3" bundle="sigs" lens="churn,amp,tested" budget_bytes="7500" est_tokens="9799">
<!-- ripwire lens for "incremental cache invalidation" [doc mentions: 3 docs discussing 2 top-ranked symbols surfaced; doc_mentions= on the root repeats the doc count]: reusable building blocks (cx=complexity, in=reuse-count; an absent cx/ccx/in is 0) — prefer composing/reusing these over reimplementing; sc=scope (full id p::sc::n); route= name-exact(X)|subtoken+body[:broad|:declined]; bundle=sigs: signatures only in this bundle, no inline bodies — fetch a symbol's full body with the fetch_body verb [confidence= derives from the ranked head's largest relative score drop (margin_pct=, whole percent, 0 = none; the same gap the adaptive flag cuts at). low = flat ranking: treat the set as a starting point, not an answer]; lens="churn,amp,tested": the three per-row quality columns the CLI for lens carries and this dialect does NOT (they need a git and a quality pass this server does not run per request); an absent column here means NOT MEASURED, never measured-and-zero; est_tokens= prices this bundle in tokens; tail: file-grain rows, WEAKER evidence than the ranked rows: first the positive-score files NOT among the shown sigs rows, the files of trimmed rows first, best-symbol rank order; then the file page's first 40 rows not listed above, file-first (the IDF share of the query's subtokens its top 8 symbols cover); sym= its top symbols by lens rank, minus names a sigs row or the syms block shows (a pointer, not the answer); total=every positive-score file, shown=printed, capped=1 when they differ, next= the page from its first unprinted row. r= on a ranked row is its 1-based rank in this lens ranking, rows in r= order, p= the file (a gap = a budget-trimmed row); tail order on this code question: every code file of both parts first, each part in the order above, then the doc files (.md, .rst, a Sphinx .txt page) in that order; tail walk: the page rows go on to the file page's first 160 rows (a code question: its first 160 code rows, plus the doc rows within its first 160 rows); a row past page 0 (a code question: past its first 40 code rows, a doc past row 40) comes after every page 0 row, skips files the head shows and carries sym= too; past 120 such rows p= only, p_only= counts them; tail folded=class=N: on a code question, N rows past page 0 of that file class (doc, config, script, testdata, other) are not listed, unless the task names the class (adding a new X, or a quoted message, keeps doc and config); next= pages from the first one; e= on a d row: the 1-based line where that definition ends, body-inclusive; absent when the extent is not known (extent_suspect, docs, config), never 0; l= is the line of the definition's name, so a definition can start above l=; lego/compose collapse to a counted stub by default (a disclosed cut): total= that section's own pre-cap row count, shown="0" capped="1" (nothing rendered here), next= names the sections=lego,compose flag that restores both sections byte-identically in one call -->
<!-- root= is the crawl root; p= below is RELATIVE to it (single-root only; absent => p= is ingest's own path, unchanged); at=this commit(+dirty). [budget_bytes= is the default BYTE target this ranked payload was shaped toward: row text shortens toward it, no row of the ranked head is removed for it (sigs past_target=)] [sigs capped=1 with shown=total: rows shrunk, none dropped] [sigs past_target=K: the last K rows are past the budget_bytes target, served because they are rows of the ranked head; none is cut] [sigs next_budget_tokens=: call this tool again with that budget_tokens to get all total= rows uncut] [docs_dropped=N: N shown rows have a doc comment not printed (r>24 always, r5..24 if capped)] [docs_after_code=N: N doc rows of the shown set moved below its code rows; same rows, reordered, none added or removed; a question naming docs keeps score order] [files_first=N: N rows moved so r=1..8 are distinct files' best rows, score order, a repeated name once; same rows; fold, hops keep score order] -->
<!-- <d cx= ccx=>: cyclomatic/cognitive complexity. pure=1: const/constexpr signature (Swift: non-mutating) and no transitive side effect found; a hint. task=: the trace source this bundle maps, verbatim (a file path, stdin, or an MCP label). layer=: built-in arch layer (game|infra|render|math|audio|ai|test) from a dir name in p=; absent if none. -->
<sigs shown="40" total="40" capped="1" past_target="10" docs_dropped="14" docs_after_code="1" files_first="9" next_budget_tokens="5600">
<d l="141" e="141" n="kCacheMagic" p="src/ingest_cache.h" pure="1" r="1" next="--expand=src/ingest_cache.h:kCacheMagic">
<doc>incremental cache (--cache): per-file content hash + raw facts so a re-run re-parses ONLY      c…</doc>constexpr std::uint32_t kCacheMagic = 0x4b505443</d>
<d l="1642" e="1647" n="spanTierMemoPath" sc="rw" p="src/ingest_astquery.h" cx="1" in="3" r="2">
<doc>Composed exactly the way every OTHER blob family is (quality.h): one fixed-width identity hex pe…</doc>inline std::string spanTierMemoPath( const std::string&amp; diskPath )</d>
<d l="893" e="896" n="mcpRefreshedThisRequest" sc="rw" p="src/mcpindex.h" cx="1" in="2" r="3">
<doc>P1-15 — the `_reingest` envelope field for a response whose handling ran an INCREMENTAL pass, …</doc>inline bool mcpRefreshedThisRequest( std::uint64_t passesAtEntry )</d>
<d l="277" e="306" n="ingestCommitTree" sc="rw::dmm" p="src/dmm.h" cx="6" ccx="5" in="1" r="4">
<doc>Ingest the tree at `sha`, materialized out of `root`&apos;s object store. The HEAD side reuses the SA…</doc>inline bool ingestCommitTree( const std::string&amp; root, const std::string&amp; sha, const std::vector&lt;std::string&gt;&amp; excludes, std::size_t maxFileBytes, IngestResult&amp;… … [line truncated: 4 more bytes on this line]
<d l="2247" e="2262" n="FileHealth" sc="FileHealth" p="src/model.h" r="5">struct FileHealth</d>
<d l="9737" e="9768" n="legoImplementorsOnSurface" sc="rw" p="src/serialize.h" cx="10" ccx="13" in="2" r="6">inline std::vector&lt;std::vector&lt;NodeId&gt;&gt; legoImplementorsOnSurface( const IngestResult&amp; ing, const std::vector&lt;std::vector&lt;NodeId&gt;&gt;&amp; implementors, const std::ve … [line truncated: 8 more bytes on this line]
<d l="4581" e="4691" n="computeHeadSnapshot" sc="quality" p="src/quality.h" cx="19" ccx="21" in="3" r="7">inline std::pair&lt;Snapshot, bool&gt; computeHeadSnapshot( const std::string&amp; root, const std::string_view* cacheNever = nullptr, std::size_t maxFileBytes = kDefault…</d>
<d l="902" e="1108" n="runParsePool" p="src/ingest_parsepool.h" cx="25" ccx="54" in="1" r="8">inline RawFacts runParsePool( IngestResult&amp; result, const char* rootDir, std::string_view cacheFile, bool captureValueUses, CacheRecords&amp; cache, const CacheLoadStats&amp; cacheStats, IngestFileScan& … [line truncated: 61 more bytes on this line]
<d l="769" e="776" n="mcpRebuildBaseline" sc="rw" p="src/mcpindex.h" cx="2" ccx="1" in="1" r="9">inline McpRebuildBaseline mcpRebuildBaseline( const McpIndex&amp; ix, bool isIncrementalPass )</d>
<d l="925" e="932" n="mcpFreshFields" sc="rw" p="src/mcpindex.h" cx="2" ccx="1" in="1" r="10">inline std::string mcpFreshFields( std::uint64_t passesAtEntry )</d>
<!-- demote: a <t> in sigs is a lower same-file sibling past answer row 10, a pointer (p= file, sym= name, r= rank), not the answer -->
<t p="src/mcpindex.h" sym="getIndex" r="11"/>
<t p="src/mcpindex.h" sym="McpIndex" r="12"/>
<d l="1101" e="1114" n="receiptNextFor" sc="mcpedit" p="src/mcpedit.h" cx="4" ccx="3" in="1" r="13">inline std::string receiptNextFor( const std::string&amp; fileIdentity, const std::string&amp; symbolName, const std::string&amp; foldJson, const std::string&amp; firstTestRun )</d>
<d l="174" e="183" n="AncestorCacheScope::AncestorCacheScope" p="src/infra/tsparent.h" layer="infra" cx="2" ccx="1" r="14">AncestorCacheScope( TSNode root, bool enabled ) : previous( tAncestorCache )</d>
<t p="src/infra/tsparent.h" sym="AncestorCacheScope" r="15"/>
<d l="237" e="240" n="cacheArtifactVerdict" sc="rw" p="src/ingest.cpp" cx="1" in="1" r="16">const char* cacheArtifactVerdict( const std::string&amp; path, bool captureValueUses )</d>
<d l="27" e="31" n="parentCacheOn" p="src/ingest_sidecap.h" cx="1" r="17">inline bool parentCacheOn()</d>
… [236 more display lines; full output is 59834 bytes on 1 raw line(s)]
`````


---

# self-diagnosis

## `./build/ripwire . --doctor`

*Environment self-check: binary staleness, grammars, cache dir, git, tracked-binary staleness — exit 1 when any check fails (here: the PATH install is older than ./build).*

**exit code: 1** — **wall time: 40.78s**

`````
<!-- ripwire doctor schema=ripwire.doctor/v1: setup health: <c n= ok=> checks; exit 1 when one fails. at=: commit+dirty+shallow. n=: the check's name (binary-path, grammars, cache-dir, git, tree-sitter, index-cache, layout ...). loaded=/expected=: grammars whose tags query compiled / grammars compiled in; a shortfall fails the row. dir=: the per-user cache directory scanned (TMPDIR/XDG_CACHE_HOME ladder); unwritable fails the row. blobs=N: ripwire cache blobs in dir=; the scan stops at 4096 (blobs_floor=1 then). bytes=N: total size in bytes of the blobs counted (short when truncated=1). many=1: more than 50 blobs; an eviction-sanity flag, informational, never fails the row. truncated=1: cache-dir, blob scan cut (cap or I/O error); tracked-binaries, scan SKIPPED, stale=0 unmeasured. locks=N: advisory edit-lock files under locks/; unheld ones over a day old are swept on a cache write. volatile=: this row's attributes that read LIVE machine state; a determinism diff strips them, never the row. git=0|1: git runs from PATH; 0 fails the row (churn verbs need it). repo=0|1: the root is inside a git work tree; 0 is a diagnosis, not a failure. history=0|1: the repo has at least one commit; head= prints only when it does. head=: HEAD's short sha (9 hex, the at= width). core_abi=/cpp_grammar_abi=: tree-sitter core language ABI / the C++ grammar's ABI; informational. languages=N: distinct compiled-in grammars (the grammars row's expected=). tracked=N: git ls-files count, printed even when truncated=1 (over 20000 files skips the scan). binaries=N: tracked paths that sniff as binary content. non_git=1: no git history to compare; the row passes unscanned. stale=N: tracked binaries committed before a same-dir same-stem source changed; any fails the row. cache_version=/parser_ver_lean=/parser_ver_rich=/artifact_arch=: index identity; reuse needs all four. rich_verbs=: the verbs that consume the rich artifact (rich=); every other verb reads the lean one. source=: auto (per-root blob), cache-flag (named by the cache flag) or disabled (no-cache: nothing read). lean_path=/rich_path=: the artifact files checked; one path when the cache flag named it. lean=/rich=: can THIS binary open that artifact (ok, absent, parser-version ...); format, never freshness. fsmonitor=: the checkout's core.fsmonitor at startup: unset, builtin, off, or hook (a command git runs). neutralised=1: a hook fsmonitor was overridden to false for this run; 0 when none was needed. filter_drivers=N: filter drivers the repository's own config defines; filter_scope= local|all, filter_pinned= 1 (run with an empty command) or refused. state=: layout records agree, disagree (mixed binary: rebuild clean-first), not-checked or no-records. checked=1: the cross-unit layout comparison ran; 0 = under two comparable records. units=N: translation units that registered a layout record. types=N: layout types recorded (only those registered in src/model.h); omitted on state=disagree. checks=/passed=: checks run / how many passed; exit 1 when passed= is below checks=. built_from=: the commit this binary was built from; at= is the tree HEAD now, a mismatch is normal. self=/which=: this binary's path and the one which ripwire finds on PATH; which_version= is the version line that one prints when they differ. on_path=0|1: whether a ripwire is on PATH; 0 fails the row and hint= carries the export line. same_file=1: the PATH copy is this very file (same device and inode). same_bytes=1: a different file with identical content, a copied install (ok); 0 fails the row; unknown: a file was unreadable; the row fails unverified (hint= names it). self_mtime=/self_size=/which_mtime=/which_size=: epoch mtime and byte size of each binary. hint=: the row's verdict and fix in plain text (which binary is stale, what to run). -->
<doctor schema="ripwire.doctor/v1" checks="9" passed="8" at="0412539b9" built_from="d1f3ba3d5">
<c n="binary-path" ok="0" self="./build/ripwire" which="<path>" on_path="1" same_file="0" same_bytes="0" self_mtime="1794517301" self_size="63188568" which_mtime="1793517843" which_size="58197960" which_version="ri … [line truncated: 512 more bytes on this line]
<c n="grammars" ok="1" loaded="27" expected="27"/>
<c n="cache-dir" ok="1" dir="<tmp>" blobs="850" bytes="2053414638" many="1" truncated="0" locks="527" volatile="blobs,blobs_floor,bytes,many,truncated,locks"/>
<c n="git" ok="1" git="1" repo="1" history="1" head="0412539b9"/>
<c n="tree-sitter" ok="1" core_abi="15" cpp_grammar_abi="14" languages="27"/>
<c n="tracked-binaries" ok="1" tracked="5207" binaries="33" non_git="0" truncated="0" stale="0"/>
<c n="index-cache" ok="1" cache_version="50" parser_ver_lean="307" parser_ver_rich="308" artifact_arch="16" rich_verbs="for,uses,metrics,exemplar,context-ratio,nonlocal-state,quality-panel,verify,eval-retrieval,eval-mined,eval-skills" source="auto" lean_path="<tmp> … [line truncated: 219 more bytes on this line]
<c n="git-config-trust" ok="1" fsmonitor="unset" neutralised="0" filter_drivers="0"/>
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

**wall time: 9.61s**

`````
<!-- ripwire map schema=ripwire.map/v1: ranked symbol map: <f p= layer=> groups <s t= n= sc= k= amb=> rows (k= rank), <c n=> resolved callees; the header comment is data. est_tokens=: price as emitted (an upper bound under compact). at=: commit+dirty+shallow. root=: p= relative to it. pr_iters=N: PageRank iterations. rank_by=: the ranker behind k=. window=: the git span mined. declined=K: K call sites without edges, including inert Elixir quote sites after unquote/unquote_splicing re-entry. external=K: K calls proven outside the tree, no edge. locality_pinned=K: K calls pinned by locality alone (a guess). extent_suspect_syms=K: K defs failed containment, corpus-wide. macro_blanked_files=K: K files indexed from a macro-blanked re-parse. overloads=N: N same-name defs merged in this row; shown= counts each. prov=scip|binding|import|split|final-segment: how that <c> edge bound (absent: one unique name); split = one arm of an amb= pick; final-segment = a qualified type matched by last name only. files=/symbols=: files and symbols indexed; edges= distinct call edges; shown= symbols printed, a merged row counting each def; ambiguous= calls split over several defs, corpus-wide; unresolved= calls with in-tree evidence and no edge (every def language-filtered or unreachable, or binding refused); order= rows by rank (important-first, important-last; (auto:fill) = flipped past a size threshold) or by path (stable). skipped_oversize=K: K files over a size ceiling, not indexed. unindexed=ext:N: N text files of that extension no grammar reads (6 extensions at most). unindexed_exts=E: E such extensions in all, the list cut. sc=: enclosing scope; the full id is p::sc::n (p= of the row or its <f>) and selectors take it. amb=K: K calls split over several defs. -->
<!-- t=modscope=a-file's-MODULE-SCOPE(n=<file-scope>):the-statements-outside-every-named-definition,where-a-top-level-call-and-an-anonymous-callback-body's-calls-live;a-CALLER-never-a-callee(nothing-in-the-source-can-name-it)-with-no-body-to-expand;a-file-with-no-such-call-has-no-such-row -->
<!-- t=type|alias|functype=a-Go-named-type-by-its-written-form:type=a-defined-type-whose-WRITTEN-form-is-not-a-struct/iface/func-literal(type-N-string;type-W-Pair-too,whatever-Pair-is-underneath),alias=type-A=B,functype=type-F-func(...) -->
<!-- t=alias|functype-in-C++-and-.h:alias=using-X=Y(also-templated-or-class-scope)or-namespace-L=lib(defs=X-prints-its-written-target-as-to=),functype=a-typedef-of-a-function-or-function-pointer-type(typedef-void(*F)(int));other-typedefs-read-t=struct -->
<!-- files=4497 symbols=39562 edges=38970 shown=5 est_tokens=1370 ambiguous=3456 unresolved=18664 locality_pinned=11 external=11109 declined=41448 extent_suspect_syms=12 macro_blanked_files=7 skipped_oversize=15 unindexed="txt:81,tsv:53,mod:33,jsonl:26,scm:25,expected:15" unindexed_exts=23 order=important-first -->
<r schema="ripwire.map/v1" at="0412539b9" root="." rank_by="churn" window="18mo@HEAD" est_tokens="1370" pr_iters="36">
<f p="src/resolve.h">
<s t="method" n="appendUint" sc="Narrower" k="0.0042">
</s>
</f>
<f p="src/infra/Diagnostics.h" layer="infra">
<s t="macro" n="RW_ASSUME_" overloads="2" k="0.0035">
<c n="RW_CHECK_"/>
</s>
<s t="macro" n="ASSUME" amb="1" k="0.0034">
<c n="RW_ASSUME_" prov="split"/>
<c n="RW_ASSUME_" prov="split"/>
</s>
</f>
<f p="src/graph.h">
<s t="fn" n="fileNameKey" sc="rw" k="0.0033">
<c n="appendUint"/>
</s>
</f>
</r>
`````

## `./build/ripwire . --rank-by=churn-decay --since=HEAD~3 --exclude=test --exclude=docs --exclude=skills --exclude=changelog.d --in=src --limit=3`

*Scope the recent-changes answer to ONE directory. The global <recent> block stays byte-identical, a second <recent scope="src"> page follows it — n=/of= are its counts (of= IS the total, so the paging half carries no total=), capped="1" has_more="1" next_offset= offset= limit= page it, and next= replays THIS run's own corpus flags (--since/--exclude) so the page it names is a page of the same answer. The symbol map collapses to a disclosed <symbols stubbed="1" would_show= next=/> stub — the map was not asked for and was not ranked at all, which is why the header carries no pr_iters=. merge_bombs_skipped= stays on the global block: it counts the window's skipped commits, not the directory's.*

**wall time: 10.11s**

`````
<!-- ripwire map schema=ripwire.map/v1: ranked symbol map: <f p= layer=> groups <s t= n= sc= k= amb=> rows (k= rank), <c n=> resolved callees; the header comment is data. window: capped= has_more= next_offset= (capped=1 cut; next_offset= pastes as offset=). est_tokens=: price as emitted (an upper bound under compact). at=: commit+dirty+shallow. root=: p= relative to it. rank_by=: the ranker behind k=. window=: the git span mined. declined=K: K calls left unbound (no evidence chose one def). external=K: K calls proven outside the tree, no edge. locality_pinned=K: K calls pinned by locality alone (a guess). <recent n= of=>: the n= newest-touched of of= touched files; <rc age_d=> days since its last commit, w= decayed weight. merge_bombs_skipped=N: N commits touching more than 100 INDEXED files skipped, uncounted; a file only they touched is absent; the window's count, so the global block only. <recent scope=DIR>: a second block riding when the global one does, DIR's files only (p= root-relative); of= is its total; capped=/has_more=/next_offset=/offset=/limit= page it, next= is that page. <symbols stubbed=1 would_show=N next=>: the symbol map in= did not ask for was not rendered; N is that run's own shown= — definitions counted individually as shown= counts them, so its rows follow from rows+sum(overloads-1)=shown (not the header's symbols= corpus count); next= fetches it. files=/symbols=: files and symbols indexed; edges= distinct call edges; shown= symbols printed, a merged row counting each def; ambiguous= calls split over several defs, corpus-wide; unresolved= calls with in-tree evidence and no edge (every def language-filtered or unreachable, or binding refused); order= rows by rank (important-first, important-last; (auto:fill) = flipped past a size threshold) or by path (stable). skipped_oversize=K: K files over a size ceiling, not indexed. unindexed=ext:N: N text files of that extension no grammar reads (6 extensions at most). unindexed_exts=E: E such extensions in all, the list cut. next=: the one pasteable follow-up. -->
<!-- t=modscope=a-file's-MODULE-SCOPE(n=<file-scope>):the-statements-outside-every-named-definition,where-a-top-level-call-and-an-anonymous-callback-body's-calls-live;a-CALLER-never-a-callee(nothing-in-the-source-can-name-it)-with-no-body-to-expand;a-file-with-no-such-call-has-no-such-row -->
<!-- t=alias|functype-in-C++-and-.h:alias=using-X=Y(also-templated-or-class-scope)or-namespace-L=lib(defs=X-prints-its-written-target-as-to=),functype=a-typedef-of-a-function-or-function-pointer-type(typedef-void(*F)(int));other-typedefs-read-t=struct -->
<!-- files=612 symbols=19468 edges=26087 shown=0 est_tokens=1728 ambiguous=2324 unresolved=5071 locality_pinned=8 external=7482 declined=36429 skipped_oversize=15 unindexed="tsv:42,scm:25,txt:25,jsonl:23,expected:15,lock:7" unindexed_exts=12 order=important-first -->
<r schema="ripwire.map/v1" at="0412539b9" root="." rank_by="churn-decay" window="HEAD~3 half-life=90d" est_tokens="1728">
<recent n="16" of="16" merge_bombs_skipped="0">
<rc p="src/fielduses.h" age_d="0" w="6.98"/>
<rc p="src/compactlegend.h" age_d="0" w="5.97"/>
<rc p="src/layout.h" age_d="0" w="5.96"/>
<rc p="src/mcpverbs.h" age_d="0" w="4.98"/>
<rc p="src/degradedscan.h" age_d="0" w="4.97"/>
<rc p="src/subjectanchor.h" age_d="0" w="4.96"/>
<rc p="README.md" age_d="0" w="3.99"/>
<rc p="present/deck5_ripwire_build.js" age_d="0" w="3.99"/>
<rc p="src/countfloor.h" age_d="0" w="3.97"/>
<rc p="src/graph.h" age_d="0" w="2.99"/>
<rc p="src/langfacts.h" age_d="0" w="2.99"/>
<rc p="src/cli.h" age_d="0" w="1.99"/>
<rc p="src/mcprefusal.h" age_d="0" w="1.99"/>
<rc p="src/selectorrefuse.h" age_d="0" w="1.99"/>
<rc p="src/verbs_navigate.h" age_d="1" w="1.98"/>
<rc p="src/accessshape.h" age_d="1" w="0.992"/>
</recent>
<recent scope="src" n="3" of="14" capped="1" has_more="1" next_offset="3" offset="0" limit="3" next="--rank-by=churn-decay --since=HEAD~3 --exclude=test --exclude=docs --exclude=skills --exclude=changelog.d --in=src --offset=3 --limit=3">
<rc p="src/fielduses.h" age_d="0" w="6.98"/>
<rc p="src/compactlegend.h" age_d="0" w="5.97"/>
<rc p="src/layout.h" age_d="0" w="5.96"/>
</recent>
<symbols stubbed="1" would_show="200" next="--rank-by=churn-decay --since=HEAD~3 --exclude=test --exclude=docs --exclude=skills --exclude=changelog.d"/>
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

**wall time: 2.64s**

`````
<!-- ripwire callers schema=ripwire.callers/v1: 1-hop CALLERS of of= (defs= matched, count= distinct symbols): <s t= n= p=>; hop_tested=/hop_untested=. counts_floor=1: every count is a FLOOR, never a total. graph_ambiguous=/graph_unresolved=: resolver gauge. graph_unindexed=N: N files no grammar could read (the map header's unindexed=); their calls raise neither gauge. root=: p= relative to it. format=columnar: parallel arrays, not row attributes: <paths> maps I=path, each <cols> array holds n= comma-separated values in one row order, fields= naming them (the path column indexes <paths>; &#44; is a comma). <tested> column: 1 = a non-test row an indexed test transitively reaches; 0 = none found, or a test row. <sites_at> column: each row's calls of the leaf name, any receiver, as file:line, space-separated; not proof each binds. next=: the one pasteable follow-up. -->
<callers schema="ripwire.callers/v1" of="rankGraphTeleport" defs="1" count="7" hop_tested="0" hop_untested="7" root="." graph_ambiguous="3456" graph_unresolved="18664" graph_unindexed="286" counts_floor="1" next="--uses=rankGraphTeleport" format="columnar">
<paths>0=src/mcpindex.h 1=src/graph.h 2=src/eval.h 3=src/main.cpp</paths>
<cols n="7" fields="path,name,line,kind,tested,sites_at">
<path>0,1,1,2,3,3,3</path>
<name>getIndex,rankGraph,anchoredLexicalRank,runEval,churnDecayRanking,churnRankedGraph,runDefaultMap</name>
<line>1211,13674,14321,171,1433,1472,1759</line>
<kind>fn,fn,fn,fn,fn,fn,fn</kind>
<tested>0,0,0,0,0,0,0</tested>
<sites_at>src/mcpindex.h:1323,src/graph.h:13678,src/graph.h:14372,src/eval.h:328,src/main.cpp:1447,src/main.cpp:1486 src/main.cpp:1487 src/main.cpp:1501,src/main.cpp:1879</sites_at>
</cols>
</callers>
`````

## `./build/ripwire . --for="cache invalidation" --format=candidates --top-k=5`

*Flat top-K export for an external reranker.*

**wall time: 7.48s**

`````
<!-- ripwire candidates: flat top K export for an external reranker. r=rank(1 based) s=SCORE n=name id=canonical k=KIND-tag p=path l=line. Note k= is the kind here and the PageRank score in the ranked map; on this row the score is s=. Root: count= rows exported of total= RANKED CORPUS symbols (total is the corpus size, never a match count), capped="1" means the top-k cut dropped some; route= names the ranker (s= is comparable only within one route); anchored= counts query-mention lifts (0 = the anchor ran and moved nothing); weak="1" means the top raw lexical score is below the confidence bar, so these rows rest on thin textual evidence; doc_tier= names the query SHAPE (a pasted trace, a pasted bug-report form) that scored documents down for this run, absent when none did. -->
<candidates count="5" total="39563" capped="1" route="subtoken+body" anchored="0">
<cand r="1" s="14.9441" n="spanTierMemoPath" id="src/ingest_astquery.h::rw::spanTierMemoPath" k="fn" p="src/ingest_astquery.h" l="1642">
<sig>inline std::string spanTierMemoPath( const std::string&amp; diskPath )</sig>
</cand>
<cand r="2" s="9.60954" n="legoImplementorsOnSurface" id="src/serialize.h::rw::legoImplementorsOnSurface" k="fn" p="src/serialize.h" l="9737">
<sig>inline std::vector&lt;std::vector&lt;NodeId&gt;&gt; legoImplementorsOnSurface( const IngestResult&amp; ing, const std::vector&lt;std::vector&lt;NodeId&gt;&gt;&amp; implementors, const std::vector&lt;NodeId&gt;&amp; surfaceIds )</sig>
</cand>
<cand r="3" s="8.21926" n="See the map — not just the numbers" id="README.md::Rip&apos;n Fast. Fewer Tokens. Better Code.::See the map — not just the numbers" k="sec" p="README.md" l="344">
<sig>### See the map — not just the numbers</sig>
</cand>
<cand r="4" s="7.3551" n="receiptNextFor" id="src/mcpedit.h::mcpedit::receiptNextFor" k="fn" p="src/mcpedit.h" l="1101">
<sig>inline std::string receiptNextFor( const std::string&amp; fileIdentity, const std::string&amp; symbolName, const std::string&amp; foldJson, const std::string&amp; firstTestRun )</sig>
</cand>
<cand r="5" s="6.86411" n="AncestorCacheScope" id="src/infra/tsparent.h::AncestorCacheScope::AncestorCacheScope" k="fn" p="src/infra/tsparent.h" l="174">
<sig>AncestorCacheScope( TSNode root, bool enabled ) : previous( tAncestorCache )</sig>
</cand>
</candidates>
`````

## `./build/ripwire . --callers=rankGraphTeleport --format=bogus`

*An unknown --format value REFUSES (exit 1), named, with the supported set listed.*

**exit code: 1** — **wall time: 1.28s**

`````
(empty)
`````

stderr:

`````
ripwire: --format: unknown value 'bogus' (supported: xml|columnar|rows|candidates)
`````

## `./build/ripwire . --callers=rankGraphTeleport --json`

*Machine-parseable JSON, same content, keys mirror the XML attrs.*

**wall time: 3.20s**

`````
{"of":"rankGraphTeleport","defs":1,"count":7,"root":".","hop_tested":0,"hop_untested":7,"graph_ambiguous":3456,"graph_unresolved":18664,"graph_unindexed":286,"counts_floor":true,"callers":[{"t":"fn","n":"getIndex","p":"src/mcpindex.h:1211","sites_at":["src/mcpindex.h:1323"]},
{"t":"fn","n":"rankGraph","p":"src/graph.h:13674","sites_at":["src/graph.h:13678"]},
{"t":"fn","n":"anchoredLexicalRank","p":"src/graph.h:14321","sites_at":["src/graph.h:14372"]},
{"t":"fn","n":"runEval","p":"src/eval.h:171","sites_at":["src/eval.h:328"]},
{"t":"fn","n":"churnDecayRanking","p":"src/main.cpp:1433","sites_at":["src/main.cpp:1447"]},
{"t":"fn","n":"churnRankedGraph","p":"src/main.cpp:1472","sites_at":["src/main.cpp:1486","src/main.cpp:1487","src/main.cpp:1501"]},
{"t":"fn","n":"runDefaultMap","p":"src/main.cpp:1759","sites_at":["src/main.cpp:1879"]}]}
`````

## `./build/ripwire . --hotspots --json`

*JSON refusal shape: an unsupported verb refuses loudly instead of silently falling back to XML.*

**exit code: 1**

`````
(empty)
`````

stderr:

`````
ripwire: --json is not yet supported for --hotspots — supported: the default map, --for, --pack-task, --callers/--callees, --impact, --quality-delta, --test-gate, --metrics, --defs, and --plan-lanes which is JSON-native (e.g. ripwire <dir> --callers=SYM --json)
`````

## `./build/ripwire . --hotspots --limit=3 --offset=3`

*Pagination: 3 items, skipping the first 3 (deterministic seams).*

**wall time: 12.17s**

`````
<!-- ripwire hotspots schema=ripwire.hotspots/v1: maintenance pain = churn x ccx over window=: <f p= churn= ccx= score= top= top_ccx= top_l=>; unranked_*= no churn/complexity. window: shown= total= capped= has_more= next_offset= offset= limit= (capped=1 cut; next_offset= pastes as offset=). at=: commit+dirty+shallow. root=: p= relative to it. files=/ranked=: files in the window / those with both churn and complexity; ranked + unranked_no_churn + unranked_no_complexity = files. unranked_no_churn=/unranked_no_complexity=: files left out for no commit in window= / no measured complexity. -->
<!-- extent_suspect_syms=K on a row = K of the file's functions failed an extent/scope containment check (the map, the bundles and the skipped verb mark each one, reasons and all) and are LEFT OUT of that row's ccx=, score= and top=, so its ccx= is a FLOOR of the file's true sum rather than a total. unranked_extent_suspect= counts files with commits whose every scorable function was left out that way (or whose trusted remainder scores 0), so ranked= + unranked_no_churn= + unranked_no_complexity= + unranked_extent_suspect= = files= exactly. Absent = nothing excluded. -->
<hotspots schema="ripwire.hotspots/v1" window="12mo@HEAD" files="4497" ranked="1013" unranked_no_churn="0" unranked_no_complexity="3482" unranked_extent_suspect="2" shown="3" capped="1" total="1013" has_more="1" next_offset="6" offset="3" limit="3" root="." at="0412539b9">
<f p="src/mcpverbs.h" churn="612" ccx="1364" score="834768" top="runBatchSub" top_ccx="142" top_l="6222"/>
<f p="src/main.cpp" churn="478" ccx="1289" score="616142" top="dispatchMainBody" top_ccx="502" top_l="4438"/>
<f p="src/verbs_for.h" churn="380" ccx="1254" score="476520" top="runForLensPass" top_ccx="691" top_l="3356"/>
</hotspots>
`````

## `./build/ripwire . --ignore-tests --top-k=5`

*Drop test paths from the corpus before ranking.*

**wall time: 4.39s**

`````
<!-- ripwire map schema=ripwire.map/v1: ranked symbol map: <f p= layer=> groups <s t= n= sc= k= amb=> rows (k= rank), <c n=> resolved callees; the header comment is data. est_tokens=: price as emitted (an upper bound under compact). root=: p= relative to it. pr_iters=N: PageRank iterations. <inv listed= unlisted=>: files the ranked rows show / do not (sum = files=), each named or counted below. <entry p= n=>: a program entry by its language's convention (C/Go/Rust main, Java/C# static main, a script main its module scope calls, __main__.py), callees as c rows; manifest entries not read. <ls p= n= f=>: n= unshown files under dir p=; f= names its code files, the rest (tests, docs, config, test/doc/example dirs) counted. declined=K: K calls left unbound (no evidence chose one def). external=K: K calls proven outside the tree, no edge. locality_pinned=K: K calls pinned by locality alone (a guess). macro_blanked_files=K: K files indexed from a macro-blanked re-parse. prov=scip|binding|import|split|final-segment: how that <c> edge bound (absent: one unique name); split = one arm of an amb= pick; final-segment = a qualified type matched by last name only. files=/symbols=: files and symbols indexed; edges= distinct call edges; shown= symbols printed, a merged row counting each def; ambiguous= calls split over several defs, corpus-wide; unresolved= calls with in-tree evidence and no edge (every def language-filtered or unreachable, or binding refused); order= rows by rank (important-first, important-last; (auto:fill) = flipped past a size threshold) or by path (stable). skipped_oversize=K: K files over a size ceiling, not indexed. unindexed=ext:N: N text files of that extension no grammar reads (6 extensions at most). unindexed_exts=E: E such extensions in all, the list cut. sc=: enclosing scope; the full id is p::sc::n (p= of the row or its <f>) and selectors take it. amb=K: K calls split over several defs. -->
<!-- t=modscope=a-file's-MODULE-SCOPE(n=<file-scope>):the-statements-outside-every-named-definition,where-a-top-level-call-and-an-anonymous-callback-body's-calls-live;a-CALLER-never-a-callee(nothing-in-the-source-can-name-it)-with-no-body-to-expand;a-file-with-no-such-call-has-no-such-row -->
<!-- t=alias|functype-in-C++-and-.h:alias=using-X=Y(also-templated-or-class-scope)or-namespace-L=lib(defs=X-prints-its-written-target-as-to=),functype=a-typedef-of-a-function-or-function-pointer-type(typedef-void(*F)(int));other-typedefs-read-t=struct -->
<!-- files=4497 symbols=20938 edges=26889 shown=5 est_tokens=3863 ambiguous=2343 unresolved=5247 locality_pinned=8 external=7750 declined=36990 macro_blanked_files=7 skipped_oversize=15 unindexed="txt:81,tsv:53,mod:33,jsonl:26,scm:25,expected:15" unindexed_exts=23 order=important-first -->
<r schema="ripwire.map/v1" root="." est_tokens="3863" pr_iters="37">
<f p="src/infra/nodekind.h" layer="infra">
<s t="fn" n="kindIs" sc="rw" k="0.0046">
</s>
</f>
<f p="src/ingest_metrics.h">
<s t="fn" n="nodeTextOf" k="0.0030">
</s>
</f>
<f p="src/model.h">
<s t="fn" n="relForHash" sc="rw" k="0.0030">
</s>
<s t="fn" n="rootRelPath" sc="rw" k="0.0029">
<c n="relForHash"/>
</s>
</f>
<f p="src/infra/Diagnostics.h" layer="infra">
<s t="macro" n="ASSUME" amb="1" k="0.0028">
<c n="RW_ASSUME_" prov="split"/>
<c n="RW_ASSUME_" prov="split"/>
</s>
</f>
<inv listed="4" unlisted="4493">
<entry p="scripts/changelog_assemble.py" n="main">
<c n="repoRoot"/>
<c n="fragmentNames"/>
… [92 more display lines; full output is 9632 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --exclude=present --exclude=bench --top-k=5`

*Drop matching paths (repeatable) before ranking.*

**wall time: 9.16s**

`````
<!-- ripwire map schema=ripwire.map/v1: ranked symbol map: <f p= layer=> groups <s t= n= sc= k= amb=> rows (k= rank), <c n=> resolved callees; the header comment is data. est_tokens=: price as emitted (an upper bound under compact). root=: p= relative to it. pr_iters=N: PageRank iterations. <inv listed= unlisted=>: files the ranked rows show / do not (sum = files=), each named or counted below. <entry p= n=>: a program entry by its language's convention (C/Go/Rust main, Java/C# static main, a script main its module scope calls, __main__.py), callees as c rows; manifest entries not read. <ls p= n= f=>: n= unshown files under dir p=; f= names its code files, the rest (tests, docs, config, test/doc/example dirs) counted. declined=K: K call sites without edges, including inert Elixir quote sites after unquote/unquote_splicing re-entry. external=K: K calls proven outside the tree, no edge. locality_pinned=K: K calls pinned by locality alone (a guess). extent_suspect_syms=K: K defs failed containment, corpus-wide. macro_blanked_files=K: K files indexed from a macro-blanked re-parse. prov=scip|binding|import|split|final-segment: how that <c> edge bound (absent: one unique name); split = one arm of an amb= pick; final-segment = a qualified type matched by last name only. files=/symbols=: files and symbols indexed; edges= distinct call edges; shown= symbols printed, a merged row counting each def; ambiguous= calls split over several defs, corpus-wide; unresolved= calls with in-tree evidence and no edge (every def language-filtered or unreachable, or binding refused); order= rows by rank (important-first, important-last; (auto:fill) = flipped past a size threshold) or by path (stable). unindexed=ext:N: N text files of that extension no grammar reads (6 extensions at most). unindexed_exts=E: E such extensions in all, the list cut. sc=: enclosing scope; the full id is p::sc::n (p= of the row or its <f>) and selectors take it. amb=K: K calls split over several defs. -->
<!-- t=modscope=a-file's-MODULE-SCOPE(n=<file-scope>):the-statements-outside-every-named-definition,where-a-top-level-call-and-an-anonymous-callback-body's-calls-live;a-CALLER-never-a-callee(nothing-in-the-source-can-name-it)-with-no-body-to-expand;a-file-with-no-such-call-has-no-such-row -->
<!-- t=type|alias|functype=a-Go-named-type-by-its-written-form:type=a-defined-type-whose-WRITTEN-form-is-not-a-struct/iface/func-literal(type-N-string;type-W-Pair-too,whatever-Pair-is-underneath),alias=type-A=B,functype=type-F-func(...) -->
<!-- t=alias|functype-in-C++-and-.h:alias=using-X=Y(also-templated-or-class-scope)or-namespace-L=lib(defs=X-prints-its-written-target-as-to=),functype=a-typedef-of-a-function-or-function-pointer-type(typedef-void(*F)(int));other-typedefs-read-t=struct -->
<!-- files=4233 symbols=36304 edges=37526 shown=5 est_tokens=3952 ambiguous=3402 unresolved=17792 locality_pinned=11 external=8778 declined=39156 extent_suspect_syms=12 macro_blanked_files=7 unindexed="txt:60,mod:33,scm:25,xml:13,tsv:11,cmake:5" unindexed_exts=18 order=important-first -->
<r schema="ripwire.map/v1" root="." est_tokens="3952" pr_iters="39">
<f p="src/infra/nodekind.h" layer="infra">
<s t="fn" n="kindIs" sc="rw" k="0.0033">
</s>
</f>
<f p="src/ingest_metrics.h">
<s t="fn" n="nodeTextOf" k="0.0022">
</s>
</f>
<f p="src/model.h">
<s t="fn" n="relForHash" sc="rw" k="0.0022">
</s>
<s t="fn" n="rootRelPath" sc="rw" k="0.0020">
<c n="relForHash"/>
</s>
</f>
<f p="src/infra/Diagnostics.h" layer="infra">
<s t="macro" n="ASSUME" amb="1" k="0.0020">
<c n="RW_ASSUME_" prov="split"/>
<c n="RW_ASSUME_" prov="split"/>
</s>
</f>
<inv listed="4" unlisted="4229">
<entry p="scripts/changelog_assemble.py" n="main">
<c n="repoRoot"/>
… [91 more display lines; full output is 9853 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --map-diff --top-k=5`

*Full map re-ranked with teleport toward git-changed files — clean tree, so changed=0 and it degrades to the plain map.*

**wall time: 13.45s**

`````
<!-- ripwire map-diff schema=ripwire.map-diff/v1: the ranked map anchored at at=: what the diff touched, the map's row vocabulary. est_tokens=: price as emitted (an upper bound under compact). at=: commit+dirty+shallow. root=: p= relative to it. pr_iters=N: PageRank iterations. declined=K: K call sites without edges, including inert Elixir quote sites after unquote/unquote_splicing re-entry. external=K: K calls proven outside the tree, no edge. locality_pinned=K: K calls pinned by locality alone (a guess). extent_suspect_syms=K: K defs failed containment, corpus-wide. macro_blanked_files=K: K files indexed from a macro-blanked re-parse. prov=scip|binding|import|split|final-segment: how that <c> edge bound (absent: one unique name); split = one arm of an amb= pick; final-segment = a qualified type matched by last name only. files=/symbols=: files and symbols indexed; edges= distinct call edges; shown= symbols printed, a merged row counting each def; ambiguous= calls split over several defs, corpus-wide; unresolved= calls with in-tree evidence and no edge (every def language-filtered or unreachable, or binding refused); order= rows by rank (important-first, important-last; (auto:fill) = flipped past a size threshold) or by path (stable). changed=K: K indexed git-changed files seed the PageRank teleport (0: uniform, incl. no git). skipped_oversize=K: K files over a size ceiling, not indexed. unindexed=ext:N: N text files of that extension no grammar reads (6 extensions at most). unindexed_exts=E: E such extensions in all, the list cut. sc=: enclosing scope; the full id is p::sc::n (p= of the row or its <f>) and selectors take it. amb=K: K calls split over several defs. layer=: built-in arch layer (game|infra|render|math|audio|ai|test) from a dir name in p=; absent if none. -->
<!-- t=modscope=a-file's-MODULE-SCOPE(n=<file-scope>):the-statements-outside-every-named-definition,where-a-top-level-call-and-an-anonymous-callback-body's-calls-live;a-CALLER-never-a-callee(nothing-in-the-source-can-name-it)-with-no-body-to-expand;a-file-with-no-such-call-has-no-such-row -->
<!-- t=type|alias|functype=a-Go-named-type-by-its-written-form:type=a-defined-type-whose-WRITTEN-form-is-not-a-struct/iface/func-literal(type-N-string;type-W-Pair-too,whatever-Pair-is-underneath),alias=type-A=B,functype=type-F-func(...) -->
<!-- t=alias|functype-in-C++-and-.h:alias=using-X=Y(also-templated-or-class-scope)or-namespace-L=lib(defs=X-prints-its-written-target-as-to=),functype=a-typedef-of-a-function-or-function-pointer-type(typedef-void(*F)(int));other-typedefs-read-t=struct -->
<!-- files=4497 symbols=39562 edges=38970 shown=5 est_tokens=1394 ambiguous=3456 unresolved=18664 locality_pinned=11 external=11109 declined=41448 extent_suspect_syms=12 macro_blanked_files=7 changed=0 skipped_oversize=15 unindexed="txt:81,tsv:53,mod:33,jsonl:26,scm:25,expected:15" unindexed_exts=23 order=important-first -->
<r schema="ripwire.map-diff/v1" at="0412539b9" root="." est_tokens="1394" pr_iters="38">
<f p="src/infra/nodekind.h" layer="infra">
<s t="fn" n="kindIs" sc="rw" k="0.0031">
</s>
</f>
<f p="src/ingest_metrics.h">
<s t="fn" n="nodeTextOf" k="0.0020">
</s>
</f>
<f p="src/model.h">
<s t="fn" n="relForHash" sc="rw" k="0.0020">
</s>
<s t="fn" n="rootRelPath" sc="rw" k="0.0019">
<c n="relForHash"/>
</s>
</f>
<f p="src/infra/Diagnostics.h" layer="infra">
<s t="macro" n="ASSUME" amb="1" k="0.0019">
<c n="RW_ASSUME_" prov="split"/>
<c n="RW_ASSUME_" prov="split"/>
</s>
</f>
</r>
`````

## `./build/ripwire . --no-cache --top-k=3`

*Force a cold parse (bypass the warm TMPDIR cache) — shows the cold-vs-warm cost.*

**wall time: 8.28s**

`````
<!-- ripwire map schema=ripwire.map/v1: ranked symbol map: <f p= layer=> groups <s t= n= sc= k= amb=> rows (k= rank), <c n=> resolved callees; the header comment is data. est_tokens=: price as emitted (an upper bound under compact). root=: p= relative to it. pr_iters=N: PageRank iterations. <inv listed= unlisted=>: files the ranked rows show / do not (sum = files=), each named or counted below. <entry p= n=>: a program entry by its language's convention (C/Go/Rust main, Java/C# static main, a script main its module scope calls, __main__.py), callees as c rows; manifest entries not read. <ls p= n= f=>: n= unshown files under dir p=; f= names its code files, the rest (tests, docs, config, test/doc/example dirs) counted. declined=K: K call sites without edges, including inert Elixir quote sites after unquote/unquote_splicing re-entry. external=K: K calls proven outside the tree, no edge. locality_pinned=K: K calls pinned by locality alone (a guess). extent_suspect_syms=K: K defs failed containment, corpus-wide. macro_blanked_files=K: K files indexed from a macro-blanked re-parse. prov=scip|binding|import|split|final-segment: how that <c> edge bound (absent: one unique name); split = one arm of an amb= pick; final-segment = a qualified type matched by last name only. files=/symbols=: files and symbols indexed; edges= distinct call edges; shown= symbols printed, a merged row counting each def; ambiguous= calls split over several defs, corpus-wide; unresolved= calls with in-tree evidence and no edge (every def language-filtered or unreachable, or binding refused); order= rows by rank (important-first, important-last; (auto:fill) = flipped past a size threshold) or by path (stable). skipped_oversize=K: K files over a size ceiling, not indexed. unindexed=ext:N: N text files of that extension no grammar reads (6 extensions at most). unindexed_exts=E: E such extensions in all, the list cut. sc=: enclosing scope; the full id is p::sc::n (p= of the row or its <f>) and selectors take it. -->
<!-- t=modscope=a-file's-MODULE-SCOPE(n=<file-scope>):the-statements-outside-every-named-definition,where-a-top-level-call-and-an-anonymous-callback-body's-calls-live;a-CALLER-never-a-callee(nothing-in-the-source-can-name-it)-with-no-body-to-expand;a-file-with-no-such-call-has-no-such-row -->
<!-- t=type|alias|functype=a-Go-named-type-by-its-written-form:type=a-defined-type-whose-WRITTEN-form-is-not-a-struct/iface/func-literal(type-N-string;type-W-Pair-too,whatever-Pair-is-underneath),alias=type-A=B,functype=type-F-func(...) -->
<!-- t=alias|functype-in-C++-and-.h:alias=using-X=Y(also-templated-or-class-scope)or-namespace-L=lib(defs=X-prints-its-written-target-as-to=),functype=a-typedef-of-a-function-or-function-pointer-type(typedef-void(*F)(int));other-typedefs-read-t=struct -->
<!-- files=4497 symbols=39562 edges=38970 shown=3 est_tokens=3914 ambiguous=3456 unresolved=18664 locality_pinned=11 external=11109 declined=41448 extent_suspect_syms=12 macro_blanked_files=7 skipped_oversize=15 unindexed="txt:81,tsv:53,mod:33,jsonl:26,scm:25,expected:15" unindexed_exts=23 order=important-first -->
<r schema="ripwire.map/v1" root="." est_tokens="3914" pr_iters="38">
<f p="src/infra/nodekind.h" layer="infra">
<s t="fn" n="kindIs" sc="rw" k="0.0031">
</s>
</f>
<f p="src/ingest_metrics.h">
<s t="fn" n="nodeTextOf" k="0.0020">
</s>
</f>
<f p="src/model.h">
<s t="fn" n="relForHash" sc="rw" k="0.0020">
</s>
</f>
<inv listed="3" unlisted="4494">
<entry p="scripts/changelog_assemble.py" n="main">
<c n="repoRoot"/>
<c n="fragmentNames"/>
<c n="check"/>
<c n="assembledEntries"/>
<c n="release"/>
</entry>
<entry p="scripts/merge_resolve.py" n="main">
<c n="generator_constants"/>
<c n="git"/>
<c n="parse"/>
… [84 more display lines; full output is 9761 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --cache=<scratch>/aux/warm2.ripwirecache --top-k=3`

*Explicit incremental cache at a path OUTSIDE the repo (first call writes it).*

**wall time: 6.41s**

`````
<!-- ripwire map schema=ripwire.map/v1: ranked symbol map: <f p= layer=> groups <s t= n= sc= k= amb=> rows (k= rank), <c n=> resolved callees; the header comment is data. est_tokens=: price as emitted (an upper bound under compact). root=: p= relative to it. pr_iters=N: PageRank iterations. <inv listed= unlisted=>: files the ranked rows show / do not (sum = files=), each named or counted below. <entry p= n=>: a program entry by its language's convention (C/Go/Rust main, Java/C# static main, a script main its module scope calls, __main__.py), callees as c rows; manifest entries not read. <ls p= n= f=>: n= unshown files under dir p=; f= names its code files, the rest (tests, docs, config, test/doc/example dirs) counted. declined=K: K call sites without edges, including inert Elixir quote sites after unquote/unquote_splicing re-entry. external=K: K calls proven outside the tree, no edge. locality_pinned=K: K calls pinned by locality alone (a guess). extent_suspect_syms=K: K defs failed containment, corpus-wide. macro_blanked_files=K: K files indexed from a macro-blanked re-parse. prov=scip|binding|import|split|final-segment: how that <c> edge bound (absent: one unique name); split = one arm of an amb= pick; final-segment = a qualified type matched by last name only. files=/symbols=: files and symbols indexed; edges= distinct call edges; shown= symbols printed, a merged row counting each def; ambiguous= calls split over several defs, corpus-wide; unresolved= calls with in-tree evidence and no edge (every def language-filtered or unreachable, or binding refused); order= rows by rank (important-first, important-last; (auto:fill) = flipped past a size threshold) or by path (stable). skipped_oversize=K: K files over a size ceiling, not indexed. unindexed=ext:N: N text files of that extension no grammar reads (6 extensions at most). unindexed_exts=E: E such extensions in all, the list cut. sc=: enclosing scope; the full id is p::sc::n (p= of the row or its <f>) and selectors take it. -->
<!-- t=modscope=a-file's-MODULE-SCOPE(n=<file-scope>):the-statements-outside-every-named-definition,where-a-top-level-call-and-an-anonymous-callback-body's-calls-live;a-CALLER-never-a-callee(nothing-in-the-source-can-name-it)-with-no-body-to-expand;a-file-with-no-such-call-has-no-such-row -->
<!-- t=type|alias|functype=a-Go-named-type-by-its-written-form:type=a-defined-type-whose-WRITTEN-form-is-not-a-struct/iface/func-literal(type-N-string;type-W-Pair-too,whatever-Pair-is-underneath),alias=type-A=B,functype=type-F-func(...) -->
<!-- t=alias|functype-in-C++-and-.h:alias=using-X=Y(also-templated-or-class-scope)or-namespace-L=lib(defs=X-prints-its-written-target-as-to=),functype=a-typedef-of-a-function-or-function-pointer-type(typedef-void(*F)(int));other-typedefs-read-t=struct -->
<!-- files=4497 symbols=39562 edges=38970 shown=3 est_tokens=3914 ambiguous=3456 unresolved=18664 locality_pinned=11 external=11109 declined=41448 extent_suspect_syms=12 macro_blanked_files=7 skipped_oversize=15 unindexed="txt:81,tsv:53,mod:33,jsonl:26,scm:25,expected:15" unindexed_exts=23 order=important-first -->
<r schema="ripwire.map/v1" root="." est_tokens="3914" pr_iters="38">
<f p="src/infra/nodekind.h" layer="infra">
<s t="fn" n="kindIs" sc="rw" k="0.0031">
</s>
</f>
<f p="src/ingest_metrics.h">
<s t="fn" n="nodeTextOf" k="0.0020">
</s>
</f>
<f p="src/model.h">
<s t="fn" n="relForHash" sc="rw" k="0.0020">
</s>
</f>
<inv listed="3" unlisted="4494">
<entry p="scripts/changelog_assemble.py" n="main">
<c n="repoRoot"/>
<c n="fragmentNames"/>
<c n="check"/>
<c n="assembledEntries"/>
<c n="release"/>
</entry>
<entry p="scripts/merge_resolve.py" n="main">
<c n="generator_constants"/>
<c n="git"/>
<c n="parse"/>
… [84 more display lines; full output is 9761 bytes on 1 raw line(s)]
`````

Artifact written:

`````
 36383482 <scratch>/aux/warm2.ripwirecache
`````

## `./build/ripwire . --max-file-size=8K --top-k=3`

*Skip files above a size bound before parsing (note the corpus shrink in the header).*

**wall time: 3.20s**

`````
<!-- ripwire map schema=ripwire.map/v1: ranked symbol map: <f p= layer=> groups <s t= n= sc= k= amb=> rows (k= rank), <c n=> resolved callees; the header comment is data. est_tokens=: price as emitted (an upper bound under compact). root=: p= relative to it. pr_iters=N: PageRank iterations. <inv listed= unlisted=>: files the ranked rows show / do not (sum = files=), each named or counted below. <entry p= n=>: a program entry by its language's convention (C/Go/Rust main, Java/C# static main, a script main its module scope calls, __main__.py), callees as c rows; manifest entries not read. <ls p= n= f=>: n= unshown files under dir p=; f= names its code files, the rest (tests, docs, config, test/doc/example dirs) counted. declined=K: K call sites without edges, including inert Elixir quote sites after unquote/unquote_splicing re-entry. external=K: K calls proven outside the tree, no edge. locality_pinned=K: K calls pinned by locality alone (a guess). extent_suspect_syms=K: K defs failed containment, corpus-wide. macro_blanked_files=K: K files indexed from a macro-blanked re-parse. files=/symbols=: files and symbols indexed; edges= distinct call edges; shown= symbols printed, a merged row counting each def; ambiguous= calls split over several defs, corpus-wide; unresolved= calls with in-tree evidence and no edge (every def language-filtered or unreachable, or binding refused); order= rows by rank (important-first, important-last; (auto:fill) = flipped past a size threshold) or by path (stable). skipped_oversize=K: K files over a size ceiling, not indexed. unindexed=ext:N: N text files of that extension no grammar reads (6 extensions at most). unindexed_exts=E: E such extensions in all, the list cut. sc=: enclosing scope; the full id is p::sc::n (p= of the row or its <f>) and selectors take it. -->
<!-- t=modscope=a-file's-MODULE-SCOPE(n=<file-scope>):the-statements-outside-every-named-definition,where-a-top-level-call-and-an-anonymous-callback-body's-calls-live;a-CALLER-never-a-callee(nothing-in-the-source-can-name-it)-with-no-body-to-expand;a-file-with-no-such-call-has-no-such-row -->
<!-- t=type|alias|functype=a-Go-named-type-by-its-written-form:type=a-defined-type-whose-WRITTEN-form-is-not-a-struct/iface/func-literal(type-N-string;type-W-Pair-too,whatever-Pair-is-underneath),alias=type-A=B,functype=type-F-func(...) -->
<!-- t=alias|functype-in-C++-and-.h:alias=using-X=Y(also-templated-or-class-scope)or-namespace-L=lib(defs=X-prints-its-written-target-as-to=),functype=a-typedef-of-a-function-or-function-pointer-type(typedef-void(*F)(int));other-typedefs-read-t=struct -->
<!-- files=3322 symbols=13080 edges=4258 shown=3 est_tokens=1984 ambiguous=334 unresolved=1121 locality_pinned=3 external=1141 declined=1393 extent_suspect_syms=12 macro_blanked_files=7 skipped_oversize=1190 unindexed="txt:81,tsv:53,mod:33,jsonl:26,scm:25,expected:15" unindexed_exts=23 order=important-first -->
<r schema="ripwire.map/v1" root="." est_tokens="1984" pr_iters="34">
<f p="test/forcallerhopfix/d2inherit/pycap/m.py" layer="test">
<s t="fn" n="post_entry" sc="Ledger" k="0.0018">
</s>
</f>
<f p="test/forcallerhopfix/c/fan.c" layer="test">
<s t="fn" n="fan_target" k="0.0018">
</s>
</f>
<f p="test/pyaliascallfix/decoy.py" layer="test">
<s t="fn" n="g" k="0.0012">
</s>
</f>
<inv listed="3" unlisted="3319">
<entry p="src/tsprobe.cpp" n="main">
<c n="langIndex"/>
<c n="kindIndex"/>
<c n="langName"/>
</entry>
<ls p="." n="6"/>
<ls p=".codex-plugin" n="1"/>
<ls p="bench" n="137"/>
<ls p="changelog.d" n="32"/>
<ls p="docs" n="3"/>
<ls p="hooks" n="1"/>
… [20 more display lines; full output is 4904 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --scip=does_not_exist.scip --callers=rankGraphTeleport`

*SCIP overlay with a missing index REFUSES (exit 1) naming the file — never silently serves the name-based map you named a precision index to improve on (it used to degrade in silence).*

**exit code: 1** — **wall time: 2.06s**

`````
(empty)
`````

stderr:

`````
ripwire: --scip=does_not_exist.scip: cannot open the index — refusing rather than serving the name-based map you named a precision index to improve on (generate one with scip-clang/scip-python, or drop --scip)
`````

## `./build/ripwire src test --top-k=5`

*Multi-root workspace: ONE merged graph over two roots, paths labeled <root>/<rel>.*

**wall time: 9.41s**

`````
<!-- ripwire map schema=ripwire.map/v1: ranked symbol map: <f p= layer=> groups <s t= n= sc= k= amb=> rows (k= rank), <c n=> resolved callees; the header comment is data. est_tokens=: price as emitted (an upper bound under compact). <root label= p=>: a workspace root; label= prefixes every p=/id=. pr_iters=N: PageRank iterations. declined=K: K call sites without edges, including inert Elixir quote sites after unquote/unquote_splicing re-entry. external=K: K calls proven outside the tree, no edge. locality_pinned=K: K calls pinned by locality alone (a guess). extent_suspect_syms=K: K defs failed containment, corpus-wide. macro_blanked_files=K: K files indexed from a macro-blanked re-parse. files=/symbols=: files and symbols indexed; edges= distinct call edges; shown= symbols printed, a merged row counting each def; ambiguous= calls split over several defs, corpus-wide; unresolved= calls with in-tree evidence and no edge (every def language-filtered or unreachable, or binding refused); order= rows by rank (important-first, important-last; (auto:fill) = flipped past a size threshold) or by path (stable). roots=N: N workspace roots. unindexed=ext:N: N text files of that extension no grammar reads (6 extensions at most). unindexed_exts=E: E such extensions in all, the list cut. sc=: enclosing scope; the full id is p::sc::n (p= of the row or its <f>) and selectors take it. -->
<!-- t=modscope=a-file's-MODULE-SCOPE(n=<file-scope>):the-statements-outside-every-named-definition,where-a-top-level-call-and-an-anonymous-callback-body's-calls-live;a-CALLER-never-a-callee(nothing-in-the-source-can-name-it)-with-no-body-to-expand;a-file-with-no-such-call-has-no-such-row -->
<!-- t=type|alias|functype=a-Go-named-type-by-its-written-form:type=a-defined-type-whose-WRITTEN-form-is-not-a-struct/iface/func-literal(type-N-string;type-W-Pair-too,whatever-Pair-is-underneath),alias=type-A=B,functype=type-F-func(...) -->
<!-- t=alias|functype-in-C++-and-.h:alias=using-X=Y(also-templated-or-class-scope)or-namespace-L=lib(defs=X-prints-its-written-target-as-to=),functype=a-typedef-of-a-function-or-function-pointer-type(typedef-void(*F)(int));other-typedefs-read-t=struct -->
<!-- files=4071 symbols=32958 edges=36443 shown=5 est_tokens=1209 ambiguous=3304 unresolved=12709 locality_pinned=11 external=7019 declined=38672 extent_suspect_syms=12 macro_blanked_files=7 roots=2 unindexed="txt:56,mod:33,xml:13,tsv:8,am:4,cfg:4" unindexed_exts=16 order=important-first -->
<r schema="ripwire.map/v1" est_tokens="1209" pr_iters="39">
<root label="src" p="src"/>
<root label="test" p="test"/>
<f p="src/infra/nodekind.h" layer="infra">
<s t="fn" n="kindIs" sc="rw" k="0.0036">
</s>
</f>
<f p="src/ingest_metrics.h">
<s t="fn" n="nodeTextOf" k="0.0024">
</s>
</f>
<f p="src/model.h">
<s t="fn" n="relForHash" sc="rw" k="0.0023">
</s>
<s t="fn" n="rootRelPath" sc="rw" k="0.0022">
<c n="relForHash"/>
</s>
</f>
<f p="src/infra/Diagnostics.h" layer="infra">
<s t="macro" n="RW_ASSUME_" k="0.0022">
<c n="RW_CHECK_"/>
</s>
</f>
</r>
`````

## `./build/ripwire . --eval`

*Self-eval: co-change recall vs BM25.*

**wall time: 36.18s**

`````
ripwire --eval  (co-change recovery, averaged over 80 historical commits)
  ranker     recall@5  recall@10  recall@20
  ripwire        0.5%       1.8%       2.5%
  BM25          11.0%      11.3%      15.1%
  BM25sub       10.6%      15.1%      20.1%
  BM25body      14.4%      23.6%      29.6%
  fused          3.0%       5.3%      16.8%
  anchored      14.4%      18.0%      29.6%
  same-dir       1.2%       4.6%       7.3%
  random         0.1%       0.2%       0.4%   <- floor (random ranking over F=4497 files)
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

**wall time: 211.20s**

`````
ripwire --eval-retrieval  (known-item, 4000 doc-commented symbols; gold is in-corpus by construction)
  sample: population=10633 scored=4000 rule=smallest-key CAPPED — a SUBSET, not the population
          (smallest fnv1a64(scope::name) over the population, cut on the key so an identity is never split;
           path- and order-independent, but a corpus this size is NOT graded exhaustively — say so when citing it)
  ingest: lex=rich (persisted subtoken stats; no per-query corpus re-tokenize)
  ranker    query-mode     MRR  recall@1  recall@5 recall@10
  subtoken  name         0.661     52.5%     82.5%     87.9%
  subtoken  doc-phrase   0.877     85.2%     89.8%     90.9%
  name-exact name         0.878     79.5%     94.2%     96.7%
  name-exact doc-phrase   0.009      0.4%      1.3%      1.9%
  anchored  name         0.666     54.0%     81.3%     86.2%
  anchored  doc-phrase   0.870     84.5%     89.5%     90.1%
  routed    name         0.880     79.7%     94.3%     96.9%
  routed    doc-phrase   0.875     85.2%     89.6%     90.6%
  note: routing chose name-exact on 3991/4000 NAME queries (a NAME query is always identifier-shaped);
        the confidence gate routes doc-phrase queries to name-exact ONLY when EVERY content word names a symbol
        (or an explicit camel/snake token appears) AND every matched name is specific enough to anchor on —
        a common name (many definitions, or a subtoken carried by many symbol names) declines the route — so
        conceptual prose falls back to subtoken+body; routed tracks the better ranker on BOTH modes
        (routed==name-exact on name, ~=subtoken+body on doc-phrase).
`````

## `./build/ripwire . --eval-stray=<scratch>/aux/stray_labels2.tsv`

*Labelled verdict-accuracy eval for --stray-content — three labels over REAL local refs (names resolved at capture time); exit 3 when accuracy is under the floor. Read got= against v= in the stray-content run: a ref the verb could not analyse (unknown) must never be credited as a merged hit.*

**exit code: 3** — **wall time: 107.70s**

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

**wall time: 1.12s**

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
  overlap       66.7%   66.7%   0.689     0.000    50.0% (th=-1.000)
  name          33.3%   66.7%   0.537     0.667    50.0% (th=0.000)
  bm25-desc     66.7%   66.7%   0.689     0.667    75.0% (th=2.865)
  bm25-full     33.3%   66.7%   0.611     1.000    50.0% (th=0.427)
  for-routed    33.3%   33.3%   0.556     1.000    50.0% (th=0.725)
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
ripwire . --for="<your task>"
#
# ...every follow-up call answers with the compact legend by default (terse definitions of only the
# attributes the answer carries; the payload is byte-identical either way). Add --legend=full when a
# definition's reasoning is needed -- `ripwire --help` carries the measured saving (one place,
# gate-held) -- this line does not repeat it, because two copies of a number is one that goes stale:
#   ripwire . --callers=SYM --legend=full
#
# ALTERNATIVE — register the MCP server instead, for a warm index across calls:
claude mcp add ripwire -- ripwire --mcp --mcp-tools=no-edit
# verbs the agent can then call mid-task (30 total):
#   read:             analyze, rank_by, find_symbol, find_referencing_symbols, grep, cochange, memory_recall, situational_awareness, mentions, for, lego, owners, fetch_body, batch, flags, doc_drift, slice
#   flagship reflex:  exemplar, quality_delta, quality_baseline, impact, uses, affected, path_between, connect, explore, from_trace, edit_check, whereis, stray_content
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
- Who calls X: `--callers=SYM --legend=compact`. "Is it safe to change X?" needs the full blast radius:
… [13 more lines, 3961 bytes total]
`````

## `./build/ripwire --version`

*Version + short build info.*

`````
ripwire 0.6.10 (dev, AppleClang 21.0.0.21000101, emit=std::print, built_from=d1f3ba3d5)
`````


---

# navigate — seeds, claims, slices, shapes

## `./build/ripwire . --at=src/graph.h:13633`

*Hold a LOCATION, not a name: the enclosing-definition chain at FILE:LINE (a compiler error, a diff hunk, a stack frame), outermost -> innermost.*

**wall time: 1.27s**

`````
<!-- ripwire at schema=ripwire.at/v1: enclosing-definition chain at p=:l=: sym= innermost, chain= outermost-first, <s n= t= l= el=> spans. root=: p= relative to it. -->
<at schema="ripwire.at/v1" p="src/graph.h" l="13633" sym="rankGraphTeleport" chain="1" root=".">
<s n="rankGraphTeleport" t="fn" l="13631" el="13659"/>
</at>
`````

## `./build/ripwire . --callers=@src/graph.h:13633`

*The same seed in a SELECTOR position: @FILE:LINE resolves to the innermost enclosing definition, then --callers runs on it.*

**wall time: 1.58s**

`````
<!-- ripwire callers schema=ripwire.callers/v1: 1-hop CALLERS of of= (defs= matched, count= distinct symbols): <s t= n= p=>; hop_tested=/hop_untested=. counts_floor=1: every count is a FLOOR, never a total. graph_ambiguous=/graph_unresolved=: resolver gauge. graph_unindexed=N: N files no grammar could read (the map header's unindexed=); their calls raise neither gauge. root=: p= relative to it. <s sites_at=>: its calls of the leaf name, any receiver, as file:line (p= is its def line); not proof each binds. next=: the one pasteable follow-up. -->
<callers schema="ripwire.callers/v1" of="@src/graph.h:13633" defs="1" count="7" root="." hop_tested="0" hop_untested="7" graph_ambiguous="3456" graph_unresolved="18664" graph_unindexed="286" counts_floor="1" next="--uses=@src/graph.h:13633">
<s t="fn" n="getIndex" p="src/mcpindex.h:1211" sites_at="src/mcpindex.h:1323"/>
<s t="fn" n="rankGraph" p="src/graph.h:13674" sites_at="src/graph.h:13678"/>
<s t="fn" n="anchoredLexicalRank" p="src/graph.h:14321" sites_at="src/graph.h:14372"/>
<s t="fn" n="runEval" p="src/eval.h:171" sites_at="src/eval.h:328"/>
<s t="fn" n="churnDecayRanking" p="src/main.cpp:1433" sites_at="src/main.cpp:1447"/>
<s t="fn" n="churnRankedGraph" p="src/main.cpp:1472" sites_at="src/main.cpp:1486 src/main.cpp:1487 src/main.cpp:1501"/>
<s t="fn" n="runDefaultMap" p="src/main.cpp:1759" sites_at="src/main.cpp:1879"/>
</callers>
`````

## `./build/ripwire . --at=src/graph.h:999999`

*A seed past the end of the file — the refusal shape for a faulted location.*

**exit code: 1** — **wall time: 1.29s**

`````
(empty)
`````

stderr:

`````
ripwire: the at flag's seed 'src/graph.h:999999' named no location (./src/graph.h has only 19366 lines — the seed asked for line 999999)
`````

## `./build/ripwire . --verify="calls(runDefaultMap, rankGraphTeleport)"`

*VERIFY a closed claim in one call: three-valued verdict (confirmed / refuted / not-established) with the evidence rows inline.*

**wall time: 1.55s**

`````
<!-- ripwire verify schema=ripwire.verify/v1: ONE structured claim, verdict=confirmed|refuted|unknown, its witness rows <s t= n= p=> inline. window: shown= capped= (capped=1 cut). counts_floor=1: every count is a FLOOR, never a total. graph_ambiguous=/graph_unresolved=: resolver gauge. graph_unindexed=N: N files no grammar could read (the map header's unindexed=); their calls raise neither gauge. root=: p= relative to it. claim=/shape=: the claim as given and its shape; from_defs=/to_defs=: defs each name resolved to. hops=N: call edges on the witness path (a confirmed reach claim only). -->
<verify schema="ripwire.verify/v1" claim="calls(runDefaultMap, rankGraphTeleport)" shape="calls" verdict="confirmed" from_defs="1" to_defs="1" hops="1" root="." graph_ambiguous="3456" graph_unresolved="18664" graph_unindexed="286" counts_floor="1" shown="2" capped="0">
<s t="fn" n="runDefaultMap" p="src/main.cpp:1759"/>
<s t="fn" n="rankGraphTeleport" p="src/graph.h:13631"/>
</verify>
`````

## `./build/ripwire . --verify="unused(rankGraphTeleport)"`

*A claim that is FALSE — the refuted shape, with the references that refute it.*

**wall time: 1.36s**

`````
<!-- ripwire verify schema=ripwire.verify/v1: ONE structured claim, verdict=confirmed|refuted|unknown, its witness rows <s t= n= p=> inline. window: shown= capped= (capped=1 cut). counts_floor=1: every count is a FLOOR, never a total. graph_ambiguous=/graph_unresolved=: resolver gauge. graph_unindexed=N: N files no grammar could read (the map header's unindexed=); their calls raise neither gauge. root=: p= relative to it. claim=/shape=: the claim as given and its shape; from_defs=/to_defs=: defs each name resolved to. -->
<verify schema="ripwire.verify/v1" claim="unused(rankGraphTeleport)" shape="unused" verdict="refuted" defs="1" external="0" count="9" root="." graph_ambiguous="3456" graph_unresolved="18664" graph_unindexed="286" counts_floor="1" shown="9" capped="0">
<u role="call" p="src/eval.h:328" in_id="src/eval.h::rw::runEval"/>
<u role="call" p="src/graph.h:13678" in_id="src/graph.h::rw::rankGraph"/>
<u role="call" p="src/graph.h:14372" in_id="src/graph.h::rw::anchoredLexicalRank"/>
<u role="call" p="src/main.cpp:1447" in_id="churnDecayRanking"/>
<u role="call" p="src/main.cpp:1486" in_id="churnRankedGraph"/>
<u role="call" p="src/main.cpp:1487" in_id="churnRankedGraph"/>
<u role="call" p="src/main.cpp:1501" in_id="churnRankedGraph"/>
<u role="call" p="src/main.cpp:1879" in_id="runDefaultMap"/>
<u role="call" p="src/mcpindex.h:1323" in_id="src/mcpindex.h::rw::getIndex"/>
</verify>
`````

## `./build/ripwire . --verify="contains(src/graph.h, \"no such literal anywhere\")"`

*A literal-scan absence: refuted only with complete= evidence, never on a partial scan.*

**wall time: 1.70s**

`````
<!-- ripwire verify schema=ripwire.verify/v1: ONE structured claim, verdict=confirmed|refuted|unknown, its witness rows <s t= n= p=> inline. window: shown= capped= (capped=1 cut). root=: p= relative to it. claim=/shape=: the claim as given and its shape; from_defs=/to_defs=: defs each name resolved to. -->
<verify schema="ripwire.verify/v1" claim="contains(src/graph.h, &quot;no such literal anywhere&quot;)" shape="contains" verdict="refuted" hits="0" root="." complete="1" shown="0" capped="0">
</verify>
`````

## `./build/ripwire . --verify="frobnicate(x)"`

*An unparseable claim — the refusal names the accepted shapes.*

**exit code: 1** — **wall time: 1.96s**

`````
(empty)
`````

stderr:

`````
ripwire: --verify claim not recognized: 'frobnicate(x)' — unknown shape word. The claim language is CLOSED; the shapes are: calls(A, B) does A transitively call B · uses(SYM) is SYM referenced anywhere · unused(SYM) is SYM referenced nowhere · contains(FILE, "LITERAL") do FILE's bytes contain t … [line truncated: 218 more bytes on this line]
`````

## `./build/ripwire . --slice=rankGraphTeleport`

*Bare --slice=SYM: the INVENTORY of sliceable locals (<v n= l= t=/>), so a caller can pick VAR.*

**wall time: 4.34s**

`````
<!-- ripwire slice schema=ripwire.slice/v1: name-based def-use rows of one variable in one definition: <s l= k=def|use|both|scope t= [b= pp= rd=]> (rd= reaching-def lines per reach=cfg|linear), <v n= l= t=> inventory; steps=/depth= flow. at=: commit+dirty+shallow. root=: p= relative to it. sym=/lang=: the sliced definition's name and language; p= is its file:line. vars=N: sliceable local bindings in the definition, one v row each; name one to slice it. counts=as-classified: defs=/uses=/vars=/steps= count what the name classifier rowed; neither floors nor totals. -->
<slice sym="rankGraphTeleport" p="src/graph.h:13631" t="fn" lang="cpp" schema="ripwire.slice/v1" vars="14" at="0412539b9" root="." counts="as-classified">
<v n="alpha" l="13631" t="param"/>
<v n="g" l="13631" t="param"/>
<v n="p" l="13631" t="param"/>
<v n="pw" l="13634" t="decl"/>
<v n="N" l="13635" t="decl"/>
<v n="teleport" l="13636" t="decl"/>
<v n="rankDouble" l="13637" t="decl"/>
<v n="run" l="13638" t="decl"/>
<v n="teleportMass" l="13641" t="decl"/>
<v n="value" l="13642" t="decl"/>
<v n="inverseMass" l="13648" t="decl"/>
<v n="value" l="13649" t="decl"/>
<v n="r" l="13656" t="decl"/>
<v n="value" l="13657" t="param"/>
</slice>
`````

## `./build/ripwire . --slice=rankGraphTeleport:teleport`

*Intra-procedural def-use slice of ONE variable: one <s> row per line touching it, k=def|use|both, reaching definitions flow-sensitive (reach=cfg).*

**wall time: 4.46s**

`````
<!-- ripwire slice schema=ripwire.slice/v1: name-based def-use rows of one variable in one definition: <s l= k=def|use|both|scope t= [b= pp= rd=]> (rd= reaching-def lines per reach=cfg|linear), <v n= l= t=> inventory; steps=/depth= flow. at=: commit+dirty+shallow. root=: p= relative to it. sym=/lang=: the sliced definition's name and language; p= is its file:line. order=defuse: seed s rows (no v=) ranked among these rows by def-use coverage (distinct local names on the line) desc, then line; not source order, not a whole-function ranking (measured at chance — docs/EVALS.md) — flow s rows (v=) keep their (d=,l=,v=) order. counts=as-classified: defs=/uses=/vars=/steps= count what the name classifier rowed; neither floors nor totals. -->
<slice sym="rankGraphTeleport" p="src/graph.h:13631" t="fn" lang="cpp" schema="ripwire.slice/v1" var="teleport" defs="1" uses="3" reach="cfg" order="defuse" at="0412539b9" root="." counts="as-classified">
<s l="13654" k="use" t="call-arg" rd="13636">
<![CDATA[run = pageRankDouble( g.inEdges, g.wOutDeg, teleport, rankDouble, PageRankConfig{ .alpha = double( alpha ) } );]]>
</s>
<s l="13636" k="def" t="decl">
<![CDATA[std::vector<double> teleport( pw.begin(), pw.end() );]]>
</s>
<s l="13642" k="use" t="read" rd="13636">
<![CDATA[for( const double value : teleport )]]>
</s>
<s l="13649" k="use" t="read" rd="13636">
<![CDATA[for( double& value : teleport )]]>
</s>
</slice>
`````

## `./build/ripwire . --slice=rankGraphTeleport:teleport --slice-flow=back --slice-depth=3`

*TRANSITIVE backward value-flow from the seed variable, bounded BFS (depth= disclosed; a cut frontier says flow_truncated=1).*

**wall time: 5.03s**

`````
<!-- ripwire slice schema=ripwire.slice/v1: name-based def-use rows of one variable in one definition: <s l= k=def|use|both|scope t= [b= pp= rd=]> (rd= reaching-def lines per reach=cfg|linear), <v n= l= t=> inventory; steps=/depth= flow. at=: commit+dirty+shallow. root=: p= relative to it. sym=/lang=: the sliced definition's name and language; p= is its file:line. order=defuse: seed s rows (no v=) ranked among these rows by def-use coverage (distinct local names on the line) desc, then line; not source order, not a whole-function ranking (measured at chance — docs/EVALS.md) — flow s rows (v=) keep their (d=,l=,v=) order. counts=as-classified: defs=/uses=/vars=/steps= count what the name classifier rowed; neither floors nor totals. -->
<slice sym="rankGraphTeleport" p="src/graph.h:13631" t="fn" lang="cpp" schema="ripwire.slice/v1" var="teleport" defs="1" uses="3" reach="cfg" flow="back" depth="3" steps="3" order="defuse" at="0412539b9" root="." counts="as-classified">
<s l="13654" k="use" t="call-arg" rd="13636">
<![CDATA[run = pageRankDouble( g.inEdges, g.wOutDeg, teleport, rankDouble, PageRankConfig{ .alpha = double( alpha ) } );]]>
</s>
<s l="13636" k="def" t="decl">
<![CDATA[std::vector<double> teleport( pw.begin(), pw.end() );]]>
</s>
<s l="13642" k="use" t="read" rd="13636">
<![CDATA[for( const double value : teleport )]]>
</s>
<s l="13649" k="use" t="read" rd="13636">
<![CDATA[for( double& value : teleport )]]>
</s>
<s l="13634" k="def" t="decl" v="pw" d="1" f="13636">
<![CDATA[const std::vector<float> pw = biasPrior( g, p );]]>
</s>
<s l="13631" k="def" t="param" v="g" d="2" f="13634">
<![CDATA[inline RankedGraph rankGraphTeleport( const Graph& g, const std::vector<float>& p, float alpha = 0.85f )]]>
</s>
<s l="13631" k="def" t="param" v="p" d="2" f="13634">
<![CDATA[inline RankedGraph rankGraphTeleport( const Graph& g, const std::vector<float>& p, float alpha = 0.85f )]]>
</s>
</slice>
`````

## `./build/ripwire . --slice=rankGraphTeleport:teleport --slice-flow=fwd`

*Forward flow: which statements the seed's value reaches, at the default depth bound.*

**wall time: 4.44s**

`````
<!-- ripwire slice schema=ripwire.slice/v1: name-based def-use rows of one variable in one definition: <s l= k=def|use|both|scope t= [b= pp= rd=]> (rd= reaching-def lines per reach=cfg|linear), <v n= l= t=> inventory; steps=/depth= flow. at=: commit+dirty+shallow. root=: p= relative to it. sym=/lang=: the sliced definition's name and language; p= is its file:line. order=defuse: seed s rows (no v=) ranked among these rows by def-use coverage (distinct local names on the line) desc, then line; not source order, not a whole-function ranking (measured at chance — docs/EVALS.md) — flow s rows (v=) keep their (d=,l=,v=) order. counts=as-classified: defs=/uses=/vars=/steps= count what the name classifier rowed; neither floors nor totals. -->
<slice sym="rankGraphTeleport" p="src/graph.h:13631" t="fn" lang="cpp" schema="ripwire.slice/v1" var="teleport" defs="1" uses="3" reach="cfg" flow="fwd" depth="8" steps="7" order="defuse" at="0412539b9" root="." counts="as-classified">
<s l="13654" k="use" t="call-arg" rd="13636">
<![CDATA[run = pageRankDouble( g.inEdges, g.wOutDeg, teleport, rankDouble, PageRankConfig{ .alpha = double( alpha ) } );]]>
</s>
<s l="13636" k="def" t="decl">
<![CDATA[std::vector<double> teleport( pw.begin(), pw.end() );]]>
</s>
<s l="13642" k="use" t="read" rd="13636">
<![CDATA[for( const double value : teleport )]]>
</s>
<s l="13649" k="use" t="read" rd="13636">
<![CDATA[for( double& value : teleport )]]>
</s>
<s l="13644" k="use" t="read" v="value" d="2" f="13642" b="13642">
<![CDATA[teleportMass += value;]]>
</s>
<s l="13651" k="both" t="assign" v="value" d="2" f="13649" b="13649">
<![CDATA[value *= inverseMass;]]>
</s>
<s l="13658" k="use" t="read" v="run" d="2" f="13654">
<![CDATA[return { std::move( r ), run.iterationCount, run.hasConverged };]]>
</s>
<s l="13644" k="both" t="assign" v="teleportMass" d="3" f="13644">
<![CDATA[teleportMass += value;]]>
</s>
<s l="13646" k="use" t="read" v="teleportMass" d="3" f="13644">
<![CDATA[if( teleportMass > 0.0 )]]>
</s>
<s l="13648" k="use" t="read" v="teleportMass" d="3" f="13644">
<![CDATA[const double inverseMass = 1.0 / teleportMass;]]>
</s>
<s l="13651" k="use" t="read" v="inverseMass" d="4" f="13648">
<![CDATA[value *= inverseMass;]]>
</s>
</slice>
`````

## `./build/ripwire . --slice=rankGraphTeleport:nosuchvar`

*A variable the definition does not bind — the refusal shape, naming the inventory.*

**exit code: 1** — **wall time: 2.33s**

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

**wall time: 4.62s**

`````
<!-- ripwire slice schema=ripwire.slice/v1: name-based def-use rows of one variable in one definition: <s l= k=def|use|both|scope t= [b= pp= rd=]> (rd= reaching-def lines per reach=cfg|linear), <v n= l= t=> inventory; steps=/depth= flow. at=: commit+dirty+shallow. root=: p= relative to it. sym=/lang=: the sliced definition's name and language; p= is its file:line. order=defuse: seed s rows (no v=) ranked among these rows by def-use coverage (distinct local names on the line) desc, then line; not source order, not a whole-function ranking (measured at chance — docs/EVALS.md) — flow s rows (v=) keep their (d=,l=,v=) order. counts=as-classified: defs=/uses=/vars=/steps= count what the name classifier rowed; neither floors nor totals. -->
<slice sym="rankGraphTeleport" p="src/graph.h:13631" t="fn" lang="cpp" schema="ripwire.slice/v1" var="teleport" defs="1" uses="3" reach="cfg" order="defuse" at="0412539b9" root="." counts="as-classified">
<s l="13654" k="use" t="call-arg" rd="13636">
<![CDATA[run = pageRankDouble( g.inEdges, g.wOutDeg, teleport, rankDouble, PageRankConfig{ .alpha = double( alpha ) } );]]>
</s>
<s l="13636" k="def" t="decl">
<![CDATA[std::vector<double> teleport( pw.begin(), pw.end() );]]>
</s>
<s l="13642" k="use" t="read" rd="13636">
<![CDATA[for( const double value : teleport )]]>
</s>
<s l="13649" k="use" t="read" rd="13636">
<![CDATA[for( double& value : teleport )]]>
</s>
</slice>
`````

## `./build/ripwire . --pattern='rankGraphTeleport($A, $B, $C)'`

*Structural search written in CODE: $NAME binds one node; grammars=/shapes= disclose what the pattern became per grammar (a 3-argument call shape — the 2-argument spelling has no call site in this repo and correctly reports hits=0).*

**wall time: 2.89s**

`````
<!-- ripwire pattern schema=ripwire.pattern/v1: structural pattern hits with their enclosing symbol. window: shown= capped= (capped=1 cut). hits_capped=1: hits= is a floor. root=: p= relative to it. -->
<pattern schema="ripwire.pattern/v1" hits="1" shown="1" capped="0" hits_capped="0" q="rankGraphTeleport($A, $B, $C)" grammars="cpp,cpp/cu,c,python,go,rust,typescript,tsx,swift,objc,javascript,java,csharp" shapes="cpp:call_expression,cpp/cu:call_expression,c:call_expression,python:call,go:call_expres … [line truncated: 309 more bytes on this line]
<m p="src/graph.h:13678" in="rankGraph">rankGraphTeleport( g, std::vector&lt;float&gt;( N, ranked ? 1.0f / float( ranked ) : 0.f ), alpha )</m>
</pattern>
`````

## `./build/ripwire . --pattern='DISCLOSE(...)'`

*The ellipsis form over a macro-shaped call site; unsupported= names the families this verb does not serve.*

**wall time: 3.79s**

`````
<!-- ripwire pattern schema=ripwire.pattern/v1: structural pattern hits with their enclosing symbol. window: shown= total= capped= has_more= next_offset= offset= limit= (capped=1 cut; next_offset= pastes as offset=). ellipsis_capped=: 1 = cut. hits_capped=1: hits= is a floor. root=: p= relative to it. -->
<pattern schema="ripwire.pattern/v1" hits="339" shown="100" capped="1" total="339" has_more="1" next_offset="100" offset="0" limit="0" hits_capped="0" q="DISCLOSE(...)" grammars="cpp,cpp/cu,c,python,go,rust,typescript,tsx,swift,objc,javascript,java,csharp" shapes="cpp:call_expression,cpp/cu:call_exp … [line truncated: 446 more bytes on this line]
<m p="src/abicheck.h:494" in="collectAuthoredSites">DISCLOSE( result, AbiResult::DisclosureWhy::NoMergeBase, "abi: no merge-base for a ref (unrelated history?) — that ref</m>
<m p="src/arch.h:511" in="parseArchRules">DISCLOSE( Diagnostics::answerRefused, "--arch exits 1 with path:line and the reason on stderr; no report is printed",   </m>
<m p="src/arch.h:850" in="readArchBaselineSidecar">DISCLOSE( baseline, ArchBaselineRead::DisclosureWhy::SymlinkRefused, "arch: refusing to read the arch baseline sidecar t</m>
<m p="src/arch.h:901" in="openArchBaselineSidecar">DISCLOSE( Diagnostics::answerRefused, "--baseline exits 1: pathguard names the refused link on stderr and the verb says </m>
<m p="src/atoms.h:372" in="collectExclusions">DISCLOSE( ex, Exclusions::DisclosureWhy::ForHeaderSaturated, "atoms: the for-header exclusion stream spent its whole bud</m>
<m p="src/atoms.h:376" in="collectExclusions">DISCLOSE( ex, Exclusions::DisclosureWhy::StmtCrementSaturated, "atoms: the statement-crement exclusion stream spent its </m>
<m p="src/atoms.h:380" in="collectExclusions">DISCLOSE( ex, Exclusions::DisclosureWhy::StmtAssignSaturated, "atoms: the statement-assign exclusion stream spent its wh</m>
<m p="src/atoms.h:384" in="collectExclusions">DISCLOSE( ex, Exclusions::DisclosureWhy::InnerCommaSaturated, "atoms: the inner-comma exclusion stream spent its whole b</m>
<m p="src/clones.h:1117" in="walkByBucket">DISCLOSE( st_, Type3Stats::DisclosureWhy::PairCapHit, "clones: Type-3 pair cap hit — first N compared (both-gate-survi</m>
<m p="src/commentcoherence.h:216" in="computeCommentCoherence">DISCLOSE( scan, CommentCoherenceScan::DisclosureWhy::UnreadableFile, "comment-coherence: an indexed file could not be re</m>
<m p="src/crossref.h:558" in="streamBlobs">DISCLOSE( st, StreamBlobStats::DisclosureWhy::ListUnwritable, "crossref: cannot write the blob-batch list — cross-bran</m>
<m p="src/crossref.h:574" in="streamBlobs">DISCLOSE( st, StreamBlobStats::DisclosureWhy::BatchNotStarted, "crossref: git cat-file --batch failed to start — cross</m>
<m p="src/crossref.h:636" in="streamBlobs">DISCLOSE( st, StreamBlobStats::DisclosureWhy::StreamEndedMidBlob,                       "crossref: git cat-file stream e</m>
<m p="src/crossref.h:859" in="enumerateRefs">DISCLOSE( dropSink, RefEnumeration::DisclosureWhy::TipNotObjectName, "crossref: for-each-ref yielded a ref whose tip is </m>
<m p="src/crossref.h:891" in="diffRaw">DISCLOSE( "crossref: refusing a diff whose revision arguments are not resolved object names" )</m>
<m p="src/crossref.h:994" in="parallelIndexed">DISCLOSE( sweep, ParallelSweep::DisclosureWhy::WorkerThrew, "crossref: a git worker threw — this shard of the sweep is</m>
<m p="src/crossref.h:1048" in="streamBlobsInSlices">DISCLOSE( stats, StreamBlobStats::DisclosureWhy::BatchNotStarted, "crossref: a blob-stream slice was never read — comp</m>
<m p="src/crossref.h:1266" in="probeRefBase">DISCLOSE( plumb, RefPlumbing::DisclosureWhy::RevisionNotObjectName, "crossref: ref tip or HEAD is not a resolved object </m>
<m p="src/crossref.h:1277" in="probeRefBase">DISCLOSE( plumb, RefPlumbing::DisclosureWhy::MergeBaseNotObjectName, "crossref: merge-base returned something that is no</m>
<m p="src/crossref.h:1284" in="probeRefBase">DISCLOSE( plumb, RefPlumbing::DisclosureWhy::NoMergeBase, "crossref: no merge-base for ref (shallow clone or unrelated h</m>
<m p="src/crossref.h:2274" in="lsTree">DISCLOSE( "crossref: refusing to list a tree whose revision argument is not a resolved object name" )</m>
<m p="src/crossref.h:2670" in="relabelHeadHitsFromIndex">DISCLOSE( "whereis: the index's def sites match no HEAD row (working tree drifted from HEAD?) — keeping the lexical la</m>
<m p="src/crossref.h:2903" in="readBranchParseBatch">DISCLOSE( reads[ k ], BranchBlobReadBack::DisclosureWhy::NotReadBackWhole,                       "whereis: a blob the pa</m>
<m p="src/crossref.h:3131" in="scanWorktree">DISCLOSE( scan, WorktreeScan::DisclosureWhy::ListingFailed, "whereis: git could not list the working tree's changes — </m>
<m p="src/crossref.h:3141" in="scanWorktree">DISCLOSE( scan, WorktreeScan::DisclosureWhy::OverPathCap, "whereis: more changed paths than the overlay reads — the re</m>
<m p="src/crossref.h:3152" in="scanWorktree">DISCLOSE( scan, WorktreeScan::DisclosureWhy::CopyUnread, "whereis: a changed path could not be read from the working tre</m>
<m p="src/crossref.h:3537" in="whereisSitesOf">DISCLOSE( Diagnostics::answerUnchanged, "lsTree lists the same rows per ref: only slower",                   "crossref: </m>
<m p="src/darkflags.h:968" in="collectCMakeFiles">DISCLOSE( out, CMakeScan::DisclosureWhy::SymlinkEscapesRoot, "flags: a CMake file's symlink target leaves the root — f</m>
… [73 more display lines; full output is 17755 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --pattern='x'`

*A pattern that collapses to a bare token is REFUSED — never reported as hits=0.*

**exit code: 1** — **wall time: 2.49s**

`````
(empty)
`````

stderr:

`````
ripwire: --pattern: this pattern collapses to a single bare token, which is a TEXT search, not a structural one — a clean parse is not enough (a bare word parses fine in most grammars and means nothing structural). Give it a shape (foo($X), $A + $B, if ($C) { ... }) or use the grep flag for litera … [line truncated: 176 more bytes on this line]
`````

## `./build/ripwire . --grep=DISCLOSE --and=cache`

*Boolean grep: hits where BOTH literals share the matched line (--grep-scope=line is the default).*

**wall time: 3.09s**

`````
<!-- ripwire grep schema=ripwire.grep/v1: literal/regex scan grouped by file: <f p=>
<hit l= in=>CDATA text</hit> (<b>/<a> context around it); complete=1 only for an exhaustive literal scan (beside pattern_meta=, of the literal reading only); <unindexed> = off-index. window: shown= capped= (capped=1 cut). hits_capped=1: hits= is a floor. root=: p= relative to it. parse_degraded=1: E … [line truncated: 1494 more bytes on this line]
<grep pattern="DISCLOSE" schema="ripwire.grep/v1" root="." terms="DISCLOSE +cache" scope="line" terms_suppressed="1081" files="9" hits="30" shown="30" capped="0" hits_capped="0" suppressed_comment="2" suppressed_string="8" tier_parsed="13" tier_unclassified="0" corpus_oversize="15" corpus_pruned_dir … [line truncated: 120 more bytes on this line]
<f p="src/ingest_cache.h">
<hit l="2253" in="openCacheFrame" n="6">
<![CDATA[            DISCLOSE( Diagnostics::answerUnchanged, "a rejected cache is rebuilt from source: this run parses and answers byte-identically",]]>
<at l="2261" in="openCacheFrame"/>
<at l="2269" in="openCacheFrame"/>
<at l="2341" in="openCacheFrame"/>
<at l="2459" in="ByteR::fitsBelow"/>
<at l="2881" in="readFileRecord"/>
</hit>
<hit l="2301" in="openCacheFrame" n="6">
<![CDATA[        DISCLOSE( Diagnostics::answerUnchanged, "a rejected cache is rebuilt from source: this run parses and answers byte-identically",]]>
<at l="2319" in="openCacheFrame"/>
<at l="2635" in="readRefQualifier"/>
<at l="2704" in="readDef"/>
<at l="2714" in="readDef"/>
<at l="2890" in="readFileRecord"/>
</hit>
<hit l="2926" in="readFileRecord" n="2">
<![CDATA[                DISCLOSE( Diagnostics::answerUnchanged, "a rejected cache is rebuilt from source: this run parses and answers byte-identically",]]>
<at l="3314" in="loadCache"/>
</hit>
<hit l="3875" in="saveCache">
<![CDATA[        DISCLOSE( Diagnostics::answerUnchanged, "this answer is already computed in memory: only the next run starts cold", "ingest: saveCache rename(tmp -> cache) failed — old cache preserved" );]]>
</hit>
</f>
<f p="src/ingest_crawl.h" parse_degraded="1">
<hit l="2336" in="isReadableCacheBlob">
… [127 more display lines; full output is 11171 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --grep=DISCLOSE --not=test --grep-scope=file`

*Drop every hit in a file that ALSO contains the --not literal anywhere (file scope).*

**wall time: 3.63s**

`````
<!-- ripwire grep schema=ripwire.grep/v1: literal/regex scan grouped by file: <f p=>
<hit l= in=>CDATA text</hit> (<b>/<a> context around it); complete=1 only for an exhaustive literal scan (beside pattern_meta=, of the literal reading only); <unindexed> = off-index. window: shown= capped= (capped=1 cut). hits_capped=1: hits= is a floor. root=: p= relative to it. parse_degraded=1: E … [line truncated: 1390 more bytes on this line]
<grep pattern="DISCLOSE" schema="ripwire.grep/v1" root="." terms="DISCLOSE -test" scope="file" terms_suppressed="1070" files="6" hits="18" shown="18" capped="0" hits_capped="0" suppressed_comment="31" suppressed_string="3" tier_parsed="25" tier_unclassified="0" corpus_oversize="15" corpus_pruned_dir … [line truncated: 123 more bytes on this line]
<f p="src/commentcoherence.h" parse_degraded="1">
<hit l="216" in="rw::computeCommentCoherence">
<![CDATA[                DISCLOSE( scan, CommentCoherenceScan::DisclosureWhy::UnreadableFile, "comment-coherence: an indexed file could not be read — its functions are absent from the report" );]]>
</hit>
</f>
<f p="src/forctorhop.h">
<hit l="168" in="rw::spliceCtorHop">
<![CDATA[        DISCLOSE( Diagnostics::answerUnchanged, "no row carries ctor_l=: the answer is the one without the constructor hop",]]>
</hit>
</f>
<f p="src/forrowfeatures.h">
<hit l="127" in="rw::armRowFeatures">
<![CDATA[        DISCLOSE( Diagnostics::answerUnchanged, "the dump is a side file; the answer never reads it", "RIPWIRE_ROW_FEATURES: not a path" );]]>
</hit>
<hit l="134" in="rw::armRowFeatures">
<![CDATA[        DISCLOSE( Diagnostics::answerUnchanged, "the dump is a side file; the answer never reads it", "RIPWIRE_ROW_FEATURES: a directory" );]]>
</hit>
<hit l="140" in="rw::armRowFeatures">
<![CDATA[        DISCLOSE( Diagnostics::answerUnchanged, "the dump is a side file; the answer never reads it", "RIPWIRE_ROW_FEATURES: posture not captured" );]]>
</hit>
<hit l="758" in="rw::rowFeaturesNoteCapture">
<![CDATA[    DISCLOSE( Diagnostics::answerUnchanged, "the dump is a side file; the answer never reads it", "RIPWIRE_ROW_FEATURES: answer not captured whole" );]]>
</hit>
<hit l="799" in="rw::rowFeaturesFinish">
<![CDATA[        DISCLOSE( Diagnostics::answerUnchanged, "the dump is a side file written after the answer; the answer never reads it", "RIPWIRE_ROW_FEATURES: write failed" );]]>
</hit>
</f>
… [100 more display lines; full output is 8705 bytes on 1 raw line(s)]
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

**wall time: 1.74s**

`````
<!-- ripwire grep schema=ripwire.grep/v1: literal/regex scan grouped by file: <f p=>
<hit l= in=>CDATA text</hit> (<b>/<a> context around it); complete=1 only for an exhaustive literal scan (beside pattern_meta=, of the literal reading only); <unindexed> = off-index. window: shown= total= capped= has_more= next_offset= offset= limit= (capped=1 cut; next_offset= pastes as offset=). h … [line truncated: 1542 more bytes on this line]
<grep pattern="DISCLOSE" schema="ripwire.grep/v1" root="." files="298" hits="1092" shown="100" capped="1" total="1092" has_more="1" next_offset="100" offset="0" limit="0" hits_capped="0" corpus_oversize="15" corpus_pruned_dirs="7" unindexed_hits="13" unindexed_files_scanned="285" unindexed_files_ski … [line truncated: 62 more bytes on this line]
<f p=".coderabbit.yaml">
<hit l="33" in="path_instructions" occ="2">
<![CDATA[        A degrade path uses DISCLOSE( sink, why ), never ASSUME(false): a one-argument DISCLOSE( msg ) is a debug trace]]>
</hit>
</f>
<f p=".github/workflows/ci.yml">
<hit l="376" in="release">
<![CDATA[    #   Release — defines NDEBUG, which compiles the DISCLOSE( msg ) trace out; the optimizer-visible build.]]>
</hit>
<hit l="377" in="release">
<![CDATA[    #   plain   — NDEBUG off, so the DISCLOSE( msg ) trace compiles in and the degrade-path gates can observe]]>
</hit>
</f>
<f p="docs/limits_build.py">
<hit l="3">
<![CDATA[# whether the file it lives in DISCLOSES a truncation when it fires.]]>
</hit>
</f>
<f p="scripts/optremarks.py">
<hit l="152" in="COLD_FILES">
<![CDATA[      "the ASSUME / DISCLOSE handlers. They run on a degrade path: once, after something has already gone wrong." ),]]>
</hit>
</f>
<f p="src/abicheck.h" parse_degraded="1">
<hit l="111">
<![CDATA[#include "infra/Diagnostics.h"  // ASSUME / DISCLOSE]]>
</hit>
… [438 more display lines; full output is 27677 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --grep=deterministic`

*A literal whose classified hits are all prose: the answer serves tier="comment+string" rather than an empty code tier, and tier_unclassified= says how many hits the fixed parse budget never classified.*

**wall time: 1.68s**

`````
<!-- ripwire grep schema=ripwire.grep/v1: literal/regex scan grouped by file: <f p=>
<hit l= in=>CDATA text</hit> (<b>/<a> context around it); complete=1 only for an exhaustive literal scan (beside pattern_meta=, of the literal reading only); <unindexed> = off-index. window: shown= total= capped= has_more= next_offset= offset= limit= (capped=1 cut; next_offset= pastes as offset=). c … [line truncated: 2219 more bytes on this line]
<grep pattern="deterministic" schema="ripwire.grep/v1" root="." files="562" hits="1336" shown="100" capped="1" total="1336" has_more="1" next_offset="100" offset="0" limit="0" hits_capped="0" suppressed_comment="245" tier="code+string" tier_partial="1" tier_parsed="76" tier_unclassified="1443" tier_ … [line truncated: 230 more bytes on this line]
<f p=".github/workflows/ci.yml">
<hit l="987" in="windows">
<![CDATA[          # on the machine is not one deterministic build step (G3). Read it back rather than assume it took.]]>
</hit>
<hit l="1024" in="windows">
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
… [668 more display lines; full output is 40109 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --grep=DISCLOSE --handles`

*h= on each editable enclosing-symbol row: a freshness-pinned identity an edit verb can target and must refuse on after any file change.*

**wall time: 1.73s**

`````
<!-- ripwire grep schema=ripwire.grep/v1: literal/regex scan grouped by file: <f p=>
<hit l= in=>CDATA text</hit> (<b>/<a> context around it); complete=1 only for an exhaustive literal scan (beside pattern_meta=, of the literal reading only); <unindexed> = off-index. window: shown= total= capped= has_more= next_offset= offset= limit= (capped=1 cut; next_offset= pastes as offset=). c … [line truncated: 2184 more bytes on this line]
<grep pattern="DISCLOSE" schema="ripwire.grep/v1" root="." files="274" hits="934" shown="100" capped="1" total="934" has_more="1" next_offset="100" offset="0" limit="0" hits_capped="0" suppressed_comment="155" suppressed_string="5" tier_parsed="78" tier_unclassified="716" tier_budget="bytes" tier_fi … [line truncated: 202 more bytes on this line]
<f p=".coderabbit.yaml">
<hit l="33" in="path_instructions" occ="2">
<![CDATA[        A degrade path uses DISCLOSE( sink, why ), never ASSUME(false): a one-argument DISCLOSE( msg ) is a debug trace]]>
</hit>
</f>
<f p="src/abicheck.h" parse_degraded="1">
<hit l="494" in="abicheck::collectAuthoredSites">
<![CDATA[            DISCLOSE( result, AbiResult::DisclosureWhy::NoMergeBase, "abi: no merge-base for a ref (unrelated history?) — that ref is counted, not compared" );]]>
</hit>
</f>
<f p="src/arch.h">
<hit l="511" in="rw::parseArchRules">
<![CDATA[        DISCLOSE( Diagnostics::answerRefused, "--arch exits 1 with path:line and the reason on stderr; no report is printed",]]>
</hit>
<hit l="850" in="rw::readArchBaselineSidecar">
<![CDATA[    if( sidecar.refused ) { DISCLOSE( baseline, ArchBaselineRead::DisclosureWhy::SymlinkRefused, "arch: refusing to read the arch baseline sidecar through a symlink" ); }]]>
</hit>
<hit l="901" in="rw::openArchBaselineSidecar">
<![CDATA[        DISCLOSE( Diagnostics::answerRefused, "--baseline exits 1: pathguard names the refused link on stderr and the verb says it cannot write the sidecar",]]>
</hit>
</f>
<f p="src/atoms.h">
<hit l="372" in="atomdetail::collectExclusions">
<![CDATA[        DISCLOSE( ex, Exclusions::DisclosureWhy::ForHeaderSaturated, "atoms: the for-header exclusion stream spent its whole budget; the rules reading it are suppressed this run" );]]>
</hit>
<hit l="376" in="atomdetail::collectExclusions">
<![CDATA[        DISCLOSE( ex, Exclusions::DisclosureWhy::StmtCrementSaturated, "atoms: the statement-crement exclusion stream spent its whole budget; the rules reading it are suppressed this run" );]]>
… [450 more display lines; full output is 32495 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --grep=DISCLOSE --legend=compact`

*The grep compact legend (ripwire.grep/v1).*

**wall time: 1.87s**

`````
<!-- ripwire grep schema=ripwire.grep/v1: literal/regex scan grouped by file: <f p=>
<hit l= in=>CDATA text</hit> (<b>/<a> context around it); complete=1 only for an exhaustive literal scan (beside pattern_meta=, of the literal reading only); <unindexed> = off-index. window: shown= total= capped= has_more= next_offset= offset= limit= (capped=1 cut; next_offset= pastes as offset=). c … [line truncated: 2184 more bytes on this line]
<grep pattern="DISCLOSE" schema="ripwire.grep/v1" root="." files="274" hits="934" shown="100" capped="1" total="934" has_more="1" next_offset="100" offset="0" limit="0" hits_capped="0" suppressed_comment="155" suppressed_string="5" tier_parsed="78" tier_unclassified="716" tier_budget="bytes" tier_fi … [line truncated: 202 more bytes on this line]
<f p=".coderabbit.yaml">
<hit l="33" in="path_instructions" occ="2">
<![CDATA[        A degrade path uses DISCLOSE( sink, why ), never ASSUME(false): a one-argument DISCLOSE( msg ) is a debug trace]]>
</hit>
</f>
<f p="src/abicheck.h" parse_degraded="1">
<hit l="494" in="abicheck::collectAuthoredSites">
<![CDATA[            DISCLOSE( result, AbiResult::DisclosureWhy::NoMergeBase, "abi: no merge-base for a ref (unrelated history?) — that ref is counted, not compared" );]]>
</hit>
</f>
<f p="src/arch.h">
<hit l="511" in="rw::parseArchRules">
<![CDATA[        DISCLOSE( Diagnostics::answerRefused, "--arch exits 1 with path:line and the reason on stderr; no report is printed",]]>
</hit>
<hit l="850" in="rw::readArchBaselineSidecar">
<![CDATA[    if( sidecar.refused ) { DISCLOSE( baseline, ArchBaselineRead::DisclosureWhy::SymlinkRefused, "arch: refusing to read the arch baseline sidecar through a symlink" ); }]]>
</hit>
<hit l="901" in="rw::openArchBaselineSidecar">
<![CDATA[        DISCLOSE( Diagnostics::answerRefused, "--baseline exits 1: pathguard names the refused link on stderr and the verb says it cannot write the sidecar",]]>
</hit>
</f>
<f p="src/atoms.h">
<hit l="372" in="atomdetail::collectExclusions">
<![CDATA[        DISCLOSE( ex, Exclusions::DisclosureWhy::ForHeaderSaturated, "atoms: the for-header exclusion stream spent its whole budget; the rules reading it are suppressed this run" );]]>
</hit>
<hit l="376" in="atomdetail::collectExclusions">
<![CDATA[        DISCLOSE( ex, Exclusions::DisclosureWhy::StmtCrementSaturated, "atoms: the statement-crement exclusion stream spent its whole budget; the rules reading it are suppressed this run" );]]>
… [450 more display lines; full output is 29628 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --for="tree-sitter parse of a source file" --legend=compact`

*The --for compact legend (ripwire.for/v1) — every data/completeness attribute kept.*

**wall time: 7.26s**

`````
<ctx task="tree-sitter parse of a source file" route="subtoken+body" root="." confidence="low" margin_pct="0" at="0412539b9" doc_mentions="1" schema="ripwire.for/v1" bundle="compact" bodies="0" reason="compact-route" budget_bytes="7500" est_tokens="9904">
<!-- ripwire for schema=ripwire.for/v1: bundle=/bodies=/reason= the body posture; d: cx= ccx= complexity, in= callers (absent cx/ccx/in = 0), churn= amp= change, clone= tested= 1, sc= scope, id=p::sc::n; total= shown= capped=1 if cut; task= the query; d pure=1 const/constexpr sig, next= the follow-up to paste; d same_as=N: doc+sig text as row n=N (not repeated); route= name-exact(X)|subtoken+body[:broad|:declined]; confidence=/margin_pct= head score drop (low=flat); h l= p= n=, c n= l= (joined for same-named callees, shown= counts them), noedge= no callee resolved; fold kind=bodies: b t= n= p= l= top ranked rows' whole bodies, not the answer; served= of total= in budget_bytes=; slice/skip p= n= l=; skip bytes= next=; a skip makes sigs next= it, sigs_next= the signatures-only re-call; d mem= an owner's direct member names by the index (question words first, names only), mem_more= names cut; t p= file outside sigs (weaker), t sym= its top symbols not in sigs/syms (a pointer, not the answer), r= rank (gap = trimmed); t order: code files first, then doc files (a code question); t page rows go on to file-page row 160 (code question: 160 code rows, docs within row 160); past page 0 (code question: past 40 code rows, a doc past row 40) listed last, head files skipped; past 120 of those p= only, p_only= counts them; t folded=class=N: N p= only rows of that class (doc|config|script|testdata|other) not listed, next= pages to them; d e= its last line (absent=unknown, never 0; l= the name's line) [doc mentions: 1 doc, 1 symbol; doc_mentions=] -->
<!-- root= is the crawl root; p= below is RELATIVE to it (single-root only; absent => p= is ingest's own path, unchanged); at=this commit(+dirty). [budget_bytes= is the default BYTE target this ranked payload was shaped toward: row text shortens toward it, no row of the ranked head is removed for it (sigs past_target=)] [sigs capped=1 with shown=total: rows shrunk, none dropped] [sigs past_target=K: the last K rows are past the budget_bytes target, served because they are rows of the ranked head; none is cut] [sigs next=: one call serving all total= rows uncut] [docs_dropped=N: N shown rows have a doc comment not printed (r>24 always, r5..24 if capped)] [files_first=N: N rows moved so r=1..8 are distinct files' best rows, score order, a repeated name once; same rows; fold, hops keep score order]; lego/compose collapse to a counted stub by default (a disclosed cut): total= that section's own pre-cap row count, shown="0" capped="1" (nothing rendered here), next= names the sections=lego,compose flag that restores both sections byte-identically in one call est_tokens= prices this bundle in tokens -->
<sigs shown="40" total="40" capped="1" past_target="7" docs_dropped="24" files_first="7" next="--for=&apos;tree-sitter parse of a source file&apos; --signatures-only --token-budget=5500">
<d l="28" e="63" n="topLevelEvidence" sc="rw::pythonrunner" p="src/pythonrunner.h" cx="4" ccx="3" in="2" churn="5" amp="15" r="1" next="--expand=src/pythonrunner.h:topLevelEvidence">inline bool topLevelEvidence( std::string_view source, const TSLanguage* language, const Predicate&amp; predicate )</d … [line truncated: 1 more bytes on this line]
<d l="45" e="45" n="kDefaultMaxFileBytes" sc="rw" p="src/ingest.h" churn="61" amp="166" pure="1" r="2">
<doc>The crawl&apos;s per-file byte ceiling. A text file larger than this is skipped: at this size it is o…</doc>constexpr std::size_t kDefaultMaxFileBytes = 4u * 1024u * 1024u</d>
<d l="1247" e="1255" n="parseTree" p="src/ingest_sidecap.h" cx="1" in="3" churn="170" amp="340" tested="1" r="3">TSTree* parseTree( TSParser* parser, std::string_view src )</d>
<d l="527" e="565" n="SourceReader" sc="SourceReader" p="src/forselfhook.h" churn="8" amp="8" r="4">
<doc>The parses of the files the sites sit in, a few kept: the sites of one method sit in few files</doc>class SourceReader</d>
<d l="594" e="669" n="doctorProbeGrammars" p="src/verbs_doctor.h" cx="7" ccx="17" in="1" churn="46" amp="135" r="5">inline DoctorGrammarProbe doctorProbeGrammars()</d>
<d l="104" e="238" n="kLangTable" p="src/ingest_crawl.h" churn="87" amp="218" pure="1" r="6">constexpr std::array&lt;LangEntry, 58&gt; kLangTable =</d>
<d l="2247" e="2262" n="FileHealth" sc="FileHealth" p="src/model.h" churn="327" amp="539" r="7" mem="operator==">struct FileHealth</d>
<d l="308" e="343" n="SliceScan" sc="SliceScan" p="src/slice.h" churn="51" amp="102" r="8" mem="disclose">struct SliceScan</d>
<d l="138" e="152" n="ParsedFile::ParsedFile" p="src/forselfhook.h" cx="2" ccx="1" churn="8" amp="8" r="9">explicit ParsedFile( std::string bytes ) : m_bytes( std::move( bytes ) )</d>
<d l="135" e="177" n="ParsedFile" sc="ParsedFile" p="src/forselfhook.h" churn="8" amp="8" r="10" mem="operator=,usable,root,text">class ParsedFile</d>
<!-- demote: a <t> in sigs is a lower same-file sibling past answer row 10, a pointer (p= file, sym= name, r= rank), not the answer -->
<t p="src/ingest.h" sym="AstWalk" r="11"/>
<t p="src/ingest_sidecap.h" sym="astroFenceTailIsBlank" r="12"/>
<d l="386" e="459" n="sliceAtRev" sc="slicediff" p="src/slicediff.h" cx="14" ccx="15" in="1" churn="14" amp="76" r="13">inline RevSide sliceAtRev( const std::string&amp; root, const std::string&amp; sha, const std::string&amp; rel, const Symbol&amp; sym, SliceFam fam, const ::TSLanguage* grammar, st … [line truncated: 77 more bytes on this line]
<d l="2129" e="2158" n="collectGatedLocalNames" sc="rw" p="src/ingest_astquery.h" cx="6" ccx="5" in="1" churn="48" amp="156" r="14">std::vector&lt;LocalNameFact&gt; collectGatedLocalNames( std::string_view defBytes, std::uint32_t defStartLine, Lang lang )</d>
<t p="src/ingest.h" sym="kMaxKotlinStringNestDepth" r="15"/>
<d l="927" e="978" n="scanModule" sc="detail" p="src/jsrunner.h" cx="16" ccx="15" in="3" churn="22" amp="109" r="16">inline ModuleScan scanModule( std::string_view source, std::string_view path )</d>
<d l="255" e="259" n="hasPhantomScopeSeparator" p="src/ingest_names.h" cx="2" ccx="1" in="2" churn="71" amp="208" tested="1" r="17">inline bool hasPhantomScopeSeparator( TSNode qualified ) noexcept</d>
<d l="87" e="97" n="hasMainGuard" sc="rw::pythonrunner" p="src/pythonrunner.h" cx="2" ccx="2" in="1" churn="5" amp="14" r="18">inline bool hasMainGuard( std::string_view source )</d>
<t p="src/ingest_crawl.h" sym="jsonNestsTooDeep" r="19"/>
<t p="src/slice.h" sym="DisclosureWhy" r="20"/>
<t p="src/ingest.h" sym="kMaxYamlNestDepth" r="21"/>
<t p="src/ingest_astquery.h" sym="spanTiersOfFiles" r="22"/>
<t p="src/slice.h" sym="sliceScanDefinition" r="23"/>
… [243 more display lines; full output is 26117 bytes on 44 raw line(s)]
`````

## `./build/ripwire . --for="tree-sitter parse of a source file" --sections=lego,compose`

*Restore the <lego>/<compose> sections the --for bundle collapses to a counted stub by default (this is the stub's own next= spelling).*

**wall time: 7.00s**

`````
<ctx task="tree-sitter parse of a source file" route="subtoken+body" root="." confidence="low" margin_pct="0" at="0412539b9" doc_mentions="1" schema="ripwire.for/v1" bundle="compact" bodies="0" reason="compact-route" budget_bytes="7500" est_tokens="10436">
<!-- ripwire for schema=ripwire.for/v1: bundle=/bodies=/reason= the body posture; d: cx= ccx= complexity, in= callers (absent cx/ccx/in = 0), churn= amp= change, clone= tested= 1, sc= scope, id=p::sc::n; total= shown= capped=1 if cut; task= the query; d pure=1 const/constexpr sig, next= the follow-up to paste; d same_as=N: doc+sig text as row n=N (not repeated); route= name-exact(X)|subtoken+body[:broad|:declined]; confidence=/margin_pct= head score drop (low=flat); h l= p= n=, c n= l= (joined for same-named callees, shown= counts them), noedge= no callee resolved; fold kind=bodies: b t= n= p= l= top ranked rows' whole bodies, not the answer; served= of total= in budget_bytes=; slice/skip p= n= l=; skip bytes= next=; a skip makes sigs next= it, sigs_next= the signatures-only re-call; d mem= an owner's direct member names by the index (question words first, names only), mem_more= names cut; t p= file outside sigs (weaker), t sym= its top symbols not in sigs/syms (a pointer, not the answer), r= rank (gap = trimmed); t order: code files first, then doc files (a code question); t page rows go on to file-page row 160 (code question: 160 code rows, docs within row 160); past page 0 (code question: past 40 code rows, a doc past row 40) listed last, head files skipped; past 120 of those p= only, p_only= counts them; t folded=class=N: N p= only rows of that class (doc|config|script|testdata|other) not listed, next= pages to them; field name= type= owner= rel=: a member of owner=, rel=creates held by value, uses by reference/pointer; iface implementors=N: types implementing it, m= its method contract; d e= its last line (absent=unknown, never 0; l= the name's line) [doc mentions: 1 doc, 1 symbol; doc_mentions=] -->
<!-- root= is the crawl root; p= below is RELATIVE to it (single-root only; absent => p= is ingest's own path, unchanged); at=this commit(+dirty). [budget_bytes= is the default BYTE target this ranked payload was shaped toward: row text shortens toward it, no row of the ranked head is removed for it (sigs past_target=)] [sigs capped=1 with shown=total: rows shrunk, none dropped] [sigs past_target=K: the last K rows are past the budget_bytes target, served because they are rows of the ranked head; none is cut] [sigs next=: one call serving all total= rows uncut] [docs_dropped=N: N shown rows have a doc comment not printed (r>24 always, r5..24 if capped)] [files_first=N: N rows moved so r=1..8 are distinct files' best rows, score order, a repeated name once; same rows; fold, hops keep score order]; iface implementors=N counts every type an extends/implements clause binds to it (the lego verb's count), never the rows listed: implementors_shown=K only K impl rows here, implementors_next= lists all; implementors_floor=1 an extends clause spelled like it bound nowhere, so N may be short (not proof of another), floor_next= lists every extends site est_tokens= prices this bundle in tokens -->
<sigs shown="40" total="40" capped="1" past_target="7" docs_dropped="24" files_first="7" next="--for=&apos;tree-sitter parse of a source file&apos; --signatures-only --token-budget=5500">
<d l="28" e="63" n="topLevelEvidence" sc="rw::pythonrunner" p="src/pythonrunner.h" cx="4" ccx="3" in="2" churn="5" amp="15" r="1" next="--expand=src/pythonrunner.h:topLevelEvidence">inline bool topLevelEvidence( std::string_view source, const TSLanguage* language, const Predicate&amp; predicate )</d … [line truncated: 1 more bytes on this line]
<d l="45" e="45" n="kDefaultMaxFileBytes" sc="rw" p="src/ingest.h" churn="61" amp="166" pure="1" r="2">
<doc>The crawl&apos;s per-file byte ceiling. A text file larger than this is skipped: at this size it is o…</doc>constexpr std::size_t kDefaultMaxFileBytes = 4u * 1024u * 1024u</d>
<d l="1247" e="1255" n="parseTree" p="src/ingest_sidecap.h" cx="1" in="3" churn="170" amp="340" tested="1" r="3">TSTree* parseTree( TSParser* parser, std::string_view src )</d>
<d l="527" e="565" n="SourceReader" sc="SourceReader" p="src/forselfhook.h" churn="8" amp="8" r="4">
<doc>The parses of the files the sites sit in, a few kept: the sites of one method sit in few files</doc>class SourceReader</d>
<d l="594" e="669" n="doctorProbeGrammars" p="src/verbs_doctor.h" cx="7" ccx="17" in="1" churn="46" amp="135" r="5">inline DoctorGrammarProbe doctorProbeGrammars()</d>
<d l="104" e="238" n="kLangTable" p="src/ingest_crawl.h" churn="87" amp="218" pure="1" r="6">constexpr std::array&lt;LangEntry, 58&gt; kLangTable =</d>
<d l="2247" e="2262" n="FileHealth" sc="FileHealth" p="src/model.h" churn="327" amp="539" r="7" mem="operator==">struct FileHealth</d>
<d l="308" e="343" n="SliceScan" sc="SliceScan" p="src/slice.h" churn="51" amp="102" r="8" mem="disclose">struct SliceScan</d>
<d l="138" e="152" n="ParsedFile::ParsedFile" p="src/forselfhook.h" cx="2" ccx="1" churn="8" amp="8" r="9">explicit ParsedFile( std::string bytes ) : m_bytes( std::move( bytes ) )</d>
<d l="135" e="177" n="ParsedFile" sc="ParsedFile" p="src/forselfhook.h" churn="8" amp="8" r="10" mem="operator=,usable,root,text">class ParsedFile</d>
<!-- demote: a <t> in sigs is a lower same-file sibling past answer row 10, a pointer (p= file, sym= name, r= rank), not the answer -->
<t p="src/ingest.h" sym="AstWalk" r="11"/>
<t p="src/ingest_sidecap.h" sym="astroFenceTailIsBlank" r="12"/>
<d l="386" e="459" n="sliceAtRev" sc="slicediff" p="src/slicediff.h" cx="14" ccx="15" in="1" churn="14" amp="76" r="13">inline RevSide sliceAtRev( const std::string&amp; root, const std::string&amp; sha, const std::string&amp; rel, const Symbol&amp; sym, SliceFam fam, const ::TSLanguage* grammar, st … [line truncated: 77 more bytes on this line]
<d l="2129" e="2158" n="collectGatedLocalNames" sc="rw" p="src/ingest_astquery.h" cx="6" ccx="5" in="1" churn="48" amp="156" r="14">std::vector&lt;LocalNameFact&gt; collectGatedLocalNames( std::string_view defBytes, std::uint32_t defStartLine, Lang lang )</d>
<t p="src/ingest.h" sym="kMaxKotlinStringNestDepth" r="15"/>
<d l="927" e="978" n="scanModule" sc="detail" p="src/jsrunner.h" cx="16" ccx="15" in="3" churn="22" amp="109" r="16">inline ModuleScan scanModule( std::string_view source, std::string_view path )</d>
<d l="255" e="259" n="hasPhantomScopeSeparator" p="src/ingest_names.h" cx="2" ccx="1" in="2" churn="71" amp="208" tested="1" r="17">inline bool hasPhantomScopeSeparator( TSNode qualified ) noexcept</d>
<d l="87" e="97" n="hasMainGuard" sc="rw::pythonrunner" p="src/pythonrunner.h" cx="2" ccx="2" in="1" churn="5" amp="14" r="18">inline bool hasMainGuard( std::string_view source )</d>
<t p="src/ingest_crawl.h" sym="jsonNestsTooDeep" r="19"/>
<t p="src/slice.h" sym="DisclosureWhy" r="20"/>
<t p="src/ingest.h" sym="kMaxYamlNestDepth" r="21"/>
<t p="src/ingest_astquery.h" sym="spanTiersOfFiles" r="22"/>
<t p="src/slice.h" sym="sliceScanDefinition" r="23"/>
… [265 more display lines; full output is 27447 bytes on 44 raw line(s)]
`````

## `./build/ripwire . --for="tree-sitter parse of a source file" --auto-bodies`

*Opt OUT of compact conceptual serving: restore the rank-first auto <bodies> walk (bundle="auto").*

**wall time: 5.40s**

`````
<ctx task="tree-sitter parse of a source file" route="subtoken+body" root="." confidence="low" margin_pct="0" at="0412539b9" doc_mentions="1" schema="ripwire.for/v1" bundle="auto" bodies="5" budget_bytes="7500" est_tokens="10192">
<!-- ripwire for schema=ripwire.for/v1: bundle=/bodies=/reason= the body posture; d: cx= ccx= complexity, in= callers (absent cx/ccx/in = 0), churn= amp= change, clone= tested= 1, sc= scope, id=p::sc::n; total= shown= capped=1 if cut; task= the query; d pure=1 const/constexpr sig, next= the follow-up to paste; d same_as=N: doc+sig text as row n=N (not repeated); route= name-exact(X)|subtoken+body[:broad|:declined]; confidence=/margin_pct= head score drop (low=flat); b t= n= p= l= full bodies, c n= l= callee signatures; t p= file outside sigs (weaker), t sym= its top symbols not in sigs/syms (a pointer, not the answer), r= rank (gap = trimmed); t order: code files first, then doc files (a code question); t page rows go on to file-page row 160 (code question: 160 code rows, docs within row 160); past page 0 (code question: past 40 code rows, a doc past row 40) listed last, head files skipped; past 120 of those p= only, p_only= counts them; t folded=class=N: N p= only rows of that class (doc|config|script|testdata|other) not listed, next= pages to them; d e= its last line (absent=unknown, never 0; l= the name's line) [doc mentions: 1 doc, 1 symbol; doc_mentions=] -->
<!-- root= is the crawl root; p= below is RELATIVE to it (single-root only; absent => p= is ingest's own path, unchanged); at=this commit(+dirty). [budget_bytes= is the default BYTE target this ranked payload was shaped toward: row text shortens toward it, no row of the ranked head is removed for it (sigs past_target=)] [sigs capped=1 with shown=total: rows shrunk, none dropped] [sigs past_target=K: the last K rows are past the budget_bytes target, served because they are rows of the ranked head; none is cut] [sigs next=: one call serving all total= rows uncut] [docs_dropped=N: N shown rows have a doc comment not printed (r>24 always, r5..24 if capped)] [files_first=N: N rows moved so r=1..8 are distinct files' best rows, score order, a repeated name once; same rows; fold, hops keep score order]; lego/compose collapse to a counted stub by default (a disclosed cut): total= that section's own pre-cap row count, shown="0" capped="1" (nothing rendered here), next= names the sections=lego,compose flag that restores both sections byte-identically in one call est_tokens= prices this bundle in tokens -->
<sigs shown="40" total="40" capped="1" past_target="7" docs_dropped="24" files_first="7" next="--for=&apos;tree-sitter parse of a source file&apos; --signatures-only --token-budget=5500">
<d l="28" e="63" n="topLevelEvidence" sc="rw::pythonrunner" p="src/pythonrunner.h" cx="4" ccx="3" in="2" churn="5" amp="15" r="1" next="--expand=src/pythonrunner.h:topLevelEvidence">inline bool topLevelEvidence( std::string_view source, const TSLanguage* language, const Predicate&amp; predicate )</d … [line truncated: 1 more bytes on this line]
<d l="45" e="45" n="kDefaultMaxFileBytes" sc="rw" p="src/ingest.h" churn="61" amp="166" pure="1" r="2">
<doc>The crawl&apos;s per-file byte ceiling. A text file larger than this is skipped: at this size it is o…</doc>constexpr std::size_t kDefaultMaxFileBytes = 4u * 1024u * 1024u</d>
<d l="1247" e="1255" n="parseTree" p="src/ingest_sidecap.h" cx="1" in="3" churn="170" amp="340" tested="1" r="3">TSTree* parseTree( TSParser* parser, std::string_view src )</d>
<d l="527" e="565" n="SourceReader" sc="SourceReader" p="src/forselfhook.h" churn="8" amp="8" r="4">
<doc>The parses of the files the sites sit in, a few kept: the sites of one method sit in few files</doc>class SourceReader</d>
<d l="594" e="669" n="doctorProbeGrammars" p="src/verbs_doctor.h" cx="7" ccx="17" in="1" churn="46" amp="135" r="5">inline DoctorGrammarProbe doctorProbeGrammars()</d>
<d l="104" e="238" n="kLangTable" p="src/ingest_crawl.h" churn="87" amp="218" pure="1" r="6">constexpr std::array&lt;LangEntry, 58&gt; kLangTable =</d>
<d l="2247" e="2262" n="FileHealth" sc="FileHealth" p="src/model.h" churn="327" amp="539" r="7">struct FileHealth</d>
<d l="308" e="343" n="SliceScan" sc="SliceScan" p="src/slice.h" churn="51" amp="102" r="8">struct SliceScan</d>
<d l="138" e="152" n="ParsedFile::ParsedFile" p="src/forselfhook.h" cx="2" ccx="1" churn="8" amp="8" r="9">explicit ParsedFile( std::string bytes ) : m_bytes( std::move( bytes ) )</d>
<d l="135" e="177" n="ParsedFile" sc="ParsedFile" p="src/forselfhook.h" churn="8" amp="8" r="10">class ParsedFile</d>
<!-- demote: a <t> in sigs is a lower same-file sibling past answer row 10, a pointer (p= file, sym= name, r= rank), not the answer -->
<t p="src/ingest.h" sym="AstWalk" r="11"/>
<t p="src/ingest_sidecap.h" sym="astroFenceTailIsBlank" r="12"/>
<d l="386" e="459" n="sliceAtRev" sc="slicediff" p="src/slicediff.h" cx="14" ccx="15" in="1" churn="14" amp="76" r="13">inline RevSide sliceAtRev( const std::string&amp; root, const std::string&amp; sha, const std::string&amp; rel, const Symbol&amp; sym, SliceFam fam, const ::TSLanguage* grammar, st … [line truncated: 77 more bytes on this line]
<d l="2129" e="2158" n="collectGatedLocalNames" sc="rw" p="src/ingest_astquery.h" cx="6" ccx="5" in="1" churn="48" amp="156" r="14">std::vector&lt;LocalNameFact&gt; collectGatedLocalNames( std::string_view defBytes, std::uint32_t defStartLine, Lang lang )</d>
<t p="src/ingest.h" sym="kMaxKotlinStringNestDepth" r="15"/>
<d l="927" e="978" n="scanModule" sc="detail" p="src/jsrunner.h" cx="16" ccx="15" in="3" churn="22" amp="109" r="16">inline ModuleScan scanModule( std::string_view source, std::string_view path )</d>
<d l="255" e="259" n="hasPhantomScopeSeparator" p="src/ingest_names.h" cx="2" ccx="1" in="2" churn="71" amp="208" tested="1" r="17">inline bool hasPhantomScopeSeparator( TSNode qualified ) noexcept</d>
<d l="87" e="97" n="hasMainGuard" sc="rw::pythonrunner" p="src/pythonrunner.h" cx="2" ccx="2" in="1" churn="5" amp="14" r="18">inline bool hasMainGuard( std::string_view source )</d>
<t p="src/ingest_crawl.h" sym="jsonNestsTooDeep" r="19"/>
<t p="src/slice.h" sym="DisclosureWhy" r="20"/>
<t p="src/ingest.h" sym="kMaxYamlNestDepth" r="21"/>
<t p="src/ingest_astquery.h" sym="spanTiersOfFiles" r="22"/>
<t p="src/slice.h" sym="sliceScanDefinition" r="23"/>
… [273 more display lines; full output is 27958 bytes on 96 raw line(s)]
`````

## `./build/ripwire . --for="quality delta acks ledger rubber stamp"`

*Doc-mention surfacing (default ON): a markdown doc naming a top-resolved symbol in a backtick rides in below that symbol — the legend's [doc mentions: …] clause says it fired.*

**wall time: 6.06s**

`````
<ctx task="quality delta acks ledger rubber stamp" route="subtoken+body" root="." confidence="low" margin_pct="0" at="0412539b9" doc_mentions="1" schema="ripwire.for/v1" bundle="compact" bodies="0" reason="compact-route" budget_bytes="7500" est_tokens="11167">
<!-- ripwire for schema=ripwire.for/v1: bundle=/bodies=/reason= the body posture; d: cx= ccx= complexity, in= callers (absent cx/ccx/in = 0), churn= amp= change, clone= tested= 1, sc= scope, id=p::sc::n; total= shown= capped=1 if cut; task= the query; d pure=1 const/constexpr sig, next= the follow-up to paste; route= name-exact(X)|subtoken+body[:broad|:declined]; confidence=/margin_pct= head score drop (low=flat); h l= p= n=, c n= l= (joined for same-named callees, shown= counts them), noedge= no callee resolved; h calls capped=1 next= the call listing every callee; fold kind=bodies: b t= n= p= l= top ranked rows' whole bodies, not the answer; served= of total= in budget_bytes=; slice/skip p= n= l=; skip bytes= next=; a skip makes sigs next= it, sigs_next= the signatures-only re-call; t p= file outside sigs (weaker), t sym= its top symbols not in sigs/syms (a pointer, not the answer), r= rank (gap = trimmed); t order: code files first, then doc files (a code question); t page rows go on to file-page row 160 (code question: 160 code rows, docs within row 160); past page 0 (code question: past 40 code rows, a doc past row 40) listed last, head files skipped; past 120 of those p= only, p_only= counts them; t folded=class=N: N p= only rows of that class (doc|config|script|testdata|other) not listed, next= pages to them; field name= type= owner= rel=: a member of owner=, rel=creates held by value, uses by reference/pointer; d e= its last line (absent=unknown, never 0; l= the name's line); c via=name: that callee matched by name alone, receiver unproven (NOT a claim the edge is false); c prov=split: a resolver split arm; may be another arm's (NOT a claim the edge is false) [doc mentions: 1 doc, 1 symbol; doc_mentions=] -->
<!-- root= is the crawl root; p= below is RELATIVE to it (single-root only; absent => p= is ingest's own path, unchanged); at=this commit(+dirty). [budget_bytes= is the default BYTE target this ranked payload was shaped toward: row text shortens toward it, no row of the ranked head is removed for it (sigs past_target=)] [sigs capped=1 with shown=total: rows shrunk, none dropped] [sigs past_target=K: the last K rows are past the budget_bytes target, served because they are rows of the ranked head; none is cut] [sigs sigs_next=: one call serving all total= rows uncut] [docs_dropped=N: N shown rows have a doc comment not printed (r>24 always, r5..24 if capped)] [docs_after_code=N: N doc rows of the shown set moved below its code rows; same rows, reordered, none added or removed; a question naming docs keeps score order] [files_first=N: N rows moved so r=1..8 are distinct files' best rows, score order, a repeated name once; same rows; fold, hops keep score order] est_tokens= prices this bundle in tokens -->
<sigs shown="40" total="40" capped="1" past_target="13" docs_dropped="25" docs_after_code="1" files_first="34" sigs_next="--for=&apos;quality delta acks ledger rubber stamp&apos; --signatures-only --token-budget=6300" next="--expand=src/mcpverbs.h:4812:computeQualityDelta">
<d l="1615" e="1636" n="refPairStaleAcks" p="src/verbs_quality.h" cx="6" ccx="6" in="1" churn="135" amp="237" r="1" next="--expand=src/verbs_quality.h:refPairStaleAcks">
<doc>L2 stale acks in the range form. A changed-files answer holds no whole target tree to check the …</doc>std::vector&lt;rw::quality::StaleAck&gt; refPairStaleAcks( const gtl::btree_map&lt;std::string, rw::quality::AckRecord&gt;&amp; acks, const RefPairDelta&amp; refs )</d>
<d l="4812" e="4889" n="computeQualityDelta" sc="rw" p="src/mcpverbs.h" cx="5" ccx="5" in="1" churn="612" amp="645" r="2">inline QualityDeltaOutcome computeQualityDelta( const std::string&amp; root )</d>
<d l="9209" e="9224" n="staleByKindValue" sc="quality" p="src/quality.h" cx="5" ccx="7" in="2" churn="584" amp="781" r="3">inline std::string staleByKindValue( const std::vector&lt;StaleAck&gt;&amp; staleAcks )</d>
<d l="2493" e="2495" n="kAtStampLegend" sc="rw" p="src/serialize.h" churn="486" amp="577" pure="1" r="4">inline constexpr const char* kAtStampLegend = &quot;&lt;!-- at= is the git commit these numbers were computed at</d>
<d l="314" e="371" n="computeDmm" sc="rw::dmm" p="src/dmm.h" cx="9" ccx="6" in="1" churn="16" amp="77" r="5">inline Result computeDmm( const std::string&amp; root, std::string_view spec, const IngestResult&amp; workingIng, const std::vector&lt;std::string&gt;&amp; excludes, std::size_t maxFileBytes  … [line truncated: 5 more bytes on this line]
<d l="67" e="67" n="kNotesFile" sc="rw::notes" p="src/notes.h" churn="20" amp="81" r="6">inline const char* kNotesFile = &quot;.ripwire_notes&quot;</d>
<d l="322" e="362" n="openRegularFileStream" sc="detail" p="src/docparse.h" cx="7" ccx="8" in="2" churn="39" amp="96" tested="1" r="7">inline rw::pathguard::NoFollowRead openRegularFileStream( std::string_view what, const std::stri…</d>
<d l="379" e="379" n="IngestLayoutStamp" sc="IngestLayoutStamp" p="src/ingest.h" churn="61" amp="166" r="8">struct IngestLayoutStamp</d>
<d l="537" e="560" n="refPairBasis" p="src/verbs_quality.h" cx="3" ccx="2" in="1" churn="135" amp="237" r="9">
<doc>The REF-PAIR floor&apos;s comparison, once loadRefPairDelta has both sides: the base snapshot is the …</doc>void refPairBasis( const rw::Config&amp; cfg, const std::string&amp; root, RefPairDelta&amp; refs, DeltaBasis&amp; out )</d>
<d l="826" e="861" n="refuseForeignAckSelection" p="src/verbs_quality.h" cx="9" ccx="12" in="1" churn="135" amp="237" r="10">std::optional&lt;int&gt; refuseForeignAckSelection( const rw::Config&amp; cfg, const rw::quality::Scope&amp; scope, const std::vector&lt;rw::quality::Regression&gt;&amp; outOf … [line truncated: 16 more bytes on this line]
<d l="1757" e="2513" n="runQualityDelta" p="src/verbs_quality.h" cx="154" ccx="352" in="2" churn="135" amp="238" r="11">std::optional&lt;int&gt; runQualityDelta( const MainDispatch&amp; d )</d>
<d l="1440" e="1465" n="ackNothingToAccept" p="src/verbs_quality.h" cx="6" ccx="7" in="1" churn="135" amp="237" r="12">int ackNothingToAccept( const std::string&amp; acksFile, const gtl::btree_map&lt;std::string, rw::quality::AckRecord&gt;&amp; acks, const rw::quality::Scope&amp; scope, std::size… … [line truncated: 4 more bytes on this line]
<!-- demote: a <t> in sigs is a lower same-file sibling past answer row 10, a pointer (p= file, sym= name, r= rank), not the answer -->
<t p="src/verbs_quality.h" sym="DeltaBasis" r="13"/>
<t p="src/quality.h" sym="kAcksFile" r="14"/>
<t p="src/verbs_quality.h" sym="inspectDirtyBaselinePin" r="15"/>
<t p="src/quality.h" sym="IdentityHealing" r="16"/>
<d l="4909" e="5024" n="qualityDeltaJson" sc="rw" p="src/mcpverbs.h" cx="26" ccx="39" in="1" churn="612" amp="645" r="17">inline std::pair&lt;std::string, std::string&gt; qualityDeltaJson( const std::string&amp; root, bool showStale = false )</d>
<d l="8208" e="8221" n="writeAckRecords" sc="quality" p="src/quality.h" cx="2" ccx="1" in="2" churn="584" amp="781" r="18">inline bool writeAckRecords( const std::string&amp; path, const gtl::btree_map&lt;std::string, AckRecord&gt;&amp; acks )</d>
<d l="4701" e="4701" n="qualityAcksPath" sc="rw" p="src/mcpverbs.h" cx="1" in="1" churn="612" amp="645" r="19">inline std::string qualityAcksPath( const std::string&amp; root )</d>
<d l="9165" e="9203" n="staleAcksXml" sc="quality" p="src/quality.h" cx="5" ccx="8" in="1" churn="584" amp="780" r="20">inline std::string staleAcksXml( const std::vector&lt;StaleAck&gt;&amp; staleAcks, EscapeFn esc )</d>
<d l="2266" e="2269" n="gitHeadSha" sc="quality" p="src/quality.h" cx="1" in="16" churn="584" amp="795" r="21">inline std::string gitHeadSha( const std::string&amp; root )</d>
<t p="src/mcpverbs.h" sym="QualityDeltaOutcome" r="22"/>
<d l="565" e="668" n="resolveDeltaBasis" p="src/verbs_quality.h" cx="11" ccx="14" in="1" churn="135" amp="237" r="23">std::optional&lt;int&gt; resolveDeltaBasis( const MainDispatch&amp; d, const std::string&amp; baselineFile, RefPairDelta&amp; refs, DeltaBasis&amp; out )</d>
… [314 more display lines; full output is 29737 bytes on 45 raw line(s)]
`````

## `./build/ripwire . --for="quality delta acks ledger rubber stamp" --no-doc-mention`

*The same task with doc-mention surfacing OFF — the contrast the flag exists for (no [doc mentions] clause, one fewer row).*

**wall time: 6.85s**

`````
<ctx task="quality delta acks ledger rubber stamp" route="subtoken+body" root="." confidence="low" margin_pct="0" at="0412539b9" schema="ripwire.for/v1" bundle="compact" bodies="0" reason="compact-route" budget_bytes="7500" est_tokens="11031">
<!-- ripwire for schema=ripwire.for/v1: bundle=/bodies=/reason= the body posture; d: cx= ccx= complexity, in= callers (absent cx/ccx/in = 0), churn= amp= change, clone= tested= 1, sc= scope, id=p::sc::n; total= shown= capped=1 if cut; task= the query; d pure=1 const/constexpr sig, next= the follow-up to paste; route= name-exact(X)|subtoken+body[:broad|:declined]; confidence=/margin_pct= head score drop (low=flat); h l= p= n=, c n= l= (joined for same-named callees, shown= counts them), noedge= no callee resolved; h calls capped=1 next= the call listing every callee; fold kind=bodies: b t= n= p= l= top ranked rows' whole bodies, not the answer; served= of total= in budget_bytes=; slice/skip p= n= l=; skip bytes= next=; a skip makes sigs next= it, sigs_next= the signatures-only re-call; t p= file outside sigs (weaker), t sym= its top symbols not in sigs/syms (a pointer, not the answer), r= rank (gap = trimmed); t order: code files first, then doc files (a code question); t page rows go on to file-page row 160 (code question: 160 code rows, docs within row 160); past page 0 (code question: past 40 code rows, a doc past row 40) listed last, head files skipped; past 120 of those p= only, p_only= counts them; t folded=class=N: N p= only rows of that class (doc|config|script|testdata|other) not listed, next= pages to them; field name= type= owner= rel=: a member of owner=, rel=creates held by value, uses by reference/pointer; d e= its last line (absent=unknown, never 0; l= the name's line); c via=name: that callee matched by name alone, receiver unproven (NOT a claim the edge is false); c prov=split: a resolver split arm; may be another arm's (NOT a claim the edge is false) -->
<!-- root= is the crawl root; p= below is RELATIVE to it (single-root only; absent => p= is ingest's own path, unchanged); at=this commit(+dirty). [budget_bytes= is the default BYTE target this ranked payload was shaped toward: row text shortens toward it, no row of the ranked head is removed for it (sigs past_target=)] [sigs capped=1 with shown=total: rows shrunk, none dropped] [sigs past_target=K: the last K rows are past the budget_bytes target, served because they are rows of the ranked head; none is cut] [sigs sigs_next=: one call serving all total= rows uncut] [docs_dropped=N: N shown rows have a doc comment not printed (r>24 always, r5..24 if capped)] [files_first=N: N rows moved so r=1..8 are distinct files' best rows, score order, a repeated name once; same rows; fold, hops keep score order] est_tokens= prices this bundle in tokens -->
<sigs shown="40" total="40" capped="1" past_target="13" docs_dropped="25" files_first="33" sigs_next="--for=&apos;quality delta acks ledger rubber stamp&apos; --signatures-only --no-doc-mention --token-budget=6200" next="--expand=src/mcpverbs.h:4812:computeQualityDelta">
<d l="1615" e="1636" n="refPairStaleAcks" p="src/verbs_quality.h" cx="6" ccx="6" in="1" churn="135" amp="237" r="1" next="--expand=src/verbs_quality.h:refPairStaleAcks">
<doc>L2 stale acks in the range form. A changed-files answer holds no whole target tree to check the …</doc>std::vector&lt;rw::quality::StaleAck&gt; refPairStaleAcks( const gtl::btree_map&lt;std::string, rw::quality::AckRecord&gt;&amp; acks, const RefPairDelta&amp; refs )</d>
<d l="4812" e="4889" n="computeQualityDelta" sc="rw" p="src/mcpverbs.h" cx="5" ccx="5" in="1" churn="612" amp="645" r="2">inline QualityDeltaOutcome computeQualityDelta( const std::string&amp; root )</d>
<d l="9209" e="9224" n="staleByKindValue" sc="quality" p="src/quality.h" cx="5" ccx="7" in="2" churn="584" amp="781" r="3">inline std::string staleByKindValue( const std::vector&lt;StaleAck&gt;&amp; staleAcks )</d>
<d l="2493" e="2495" n="kAtStampLegend" sc="rw" p="src/serialize.h" churn="486" amp="577" pure="1" r="4">inline constexpr const char* kAtStampLegend = &quot;&lt;!-- at= is the git commit these numbers were computed at</d>
<d l="314" e="371" n="computeDmm" sc="rw::dmm" p="src/dmm.h" cx="9" ccx="6" in="1" churn="16" amp="77" r="5">inline Result computeDmm( const std::string&amp; root, std::string_view spec, const IngestResult&amp; workingIng, const std::vector&lt;std::string&gt;&amp; excludes, std::size_t maxFileBytes  … [line truncated: 5 more bytes on this line]
<d l="67" e="67" n="kNotesFile" sc="rw::notes" p="src/notes.h" churn="20" amp="81" r="6">inline const char* kNotesFile = &quot;.ripwire_notes&quot;</d>
<d l="322" e="362" n="openRegularFileStream" sc="detail" p="src/docparse.h" cx="7" ccx="8" in="2" churn="39" amp="96" tested="1" r="7">inline rw::pathguard::NoFollowRead openRegularFileStream( std::string_view what, const std::stri…</d>
<d l="379" e="379" n="IngestLayoutStamp" sc="IngestLayoutStamp" p="src/ingest.h" churn="61" amp="166" r="8">struct IngestLayoutStamp</d>
<d l="537" e="560" n="refPairBasis" p="src/verbs_quality.h" cx="3" ccx="2" in="1" churn="135" amp="237" r="9">
<doc>The REF-PAIR floor&apos;s comparison, once loadRefPairDelta has both sides: the base snapshot is the …</doc>void refPairBasis( const rw::Config&amp; cfg, const std::string&amp; root, RefPairDelta&amp; refs, DeltaBasis&amp; out )</d>
<d l="826" e="861" n="refuseForeignAckSelection" p="src/verbs_quality.h" cx="9" ccx="12" in="1" churn="135" amp="237" r="10">std::optional&lt;int&gt; refuseForeignAckSelection( const rw::Config&amp; cfg, const rw::quality::Scope&amp; scope, const std::vector&lt;rw::quality::Regression&gt;&amp; outOf … [line truncated: 16 more bytes on this line]
<d l="1757" e="2513" n="runQualityDelta" p="src/verbs_quality.h" cx="154" ccx="352" in="2" churn="135" amp="238" r="11">std::optional&lt;int&gt; runQualityDelta( const MainDispatch&amp; d )</d>
<d l="1440" e="1465" n="ackNothingToAccept" p="src/verbs_quality.h" cx="6" ccx="7" in="1" churn="135" amp="237" r="12">int ackNothingToAccept( const std::string&amp; acksFile, const gtl::btree_map&lt;std::string, rw::quality::AckRecord&gt;&amp; acks, const rw::quality::Scope&amp; scope, std::size… … [line truncated: 4 more bytes on this line]
<!-- demote: a <t> in sigs is a lower same-file sibling past answer row 10, a pointer (p= file, sym= name, r= rank), not the answer -->
<t p="src/verbs_quality.h" sym="DeltaBasis" r="13"/>
<t p="src/quality.h" sym="kAcksFile" r="14"/>
<t p="src/verbs_quality.h" sym="inspectDirtyBaselinePin" r="15"/>
<t p="src/quality.h" sym="IdentityHealing" r="16"/>
<d l="4909" e="5024" n="qualityDeltaJson" sc="rw" p="src/mcpverbs.h" cx="26" ccx="39" in="1" churn="612" amp="645" r="17">inline std::pair&lt;std::string, std::string&gt; qualityDeltaJson( const std::string&amp; root, bool showStale = false )</d>
<d l="8208" e="8221" n="writeAckRecords" sc="quality" p="src/quality.h" cx="2" ccx="1" in="2" churn="584" amp="781" r="18">inline bool writeAckRecords( const std::string&amp; path, const gtl::btree_map&lt;std::string, AckRecord&gt;&amp; acks )</d>
<d l="4701" e="4701" n="qualityAcksPath" sc="rw" p="src/mcpverbs.h" cx="1" in="1" churn="612" amp="645" r="19">inline std::string qualityAcksPath( const std::string&amp; root )</d>
<d l="9165" e="9203" n="staleAcksXml" sc="quality" p="src/quality.h" cx="5" ccx="8" in="1" churn="584" amp="780" r="20">inline std::string staleAcksXml( const std::vector&lt;StaleAck&gt;&amp; staleAcks, EscapeFn esc )</d>
<d l="2266" e="2269" n="gitHeadSha" sc="quality" p="src/quality.h" cx="1" in="16" churn="584" amp="795" r="21">inline std::string gitHeadSha( const std::string&amp; root )</d>
<t p="src/mcpverbs.h" sym="QualityDeltaOutcome" r="22"/>
<d l="565" e="668" n="resolveDeltaBasis" p="src/verbs_quality.h" cx="11" ccx="14" in="1" churn="135" amp="237" r="23">std::optional&lt;int&gt; resolveDeltaBasis( const MainDispatch&amp; d, const std::string&amp; baselineFile, RefPairDelta&amp; refs, DeltaBasis&amp; out )</d>
… [314 more display lines; full output is 29396 bytes on 45 raw line(s)]
`````

## `./build/ripwire . --safe-delete=rankGraphTeleport`

*"Can I delete this?" — callers + transitive impact + every use site + how much of the radius is tested, composed in ONE call; risk= names what was found, never a verdict.*

**wall time: 1.46s**

`````
<!-- ripwire safe-delete schema=ripwire.safe-delete/v1: can sym= go, a READ never a verdict: callers= impact_reaches= uses= tested_self= risk=; <c n= p= amb=>; radius_tested= non-tests of impact_reaches= an indexed test reaches, radius_untested= the rest; t= p= its tower-front match's kind and file:line; defs= matched; ambiguous_callers= callers with a call split over several defs; dead_code_candidate=1 only at defs=1 with no caller, for a t=fn with a body, outside .h/.hpp/.hh/.hxx, whose signature spells static (0 never means in use). window: shown= capped= (capped=1 cut). counts_floor=1: every count is a FLOOR, never a total. graph_ambiguous=/graph_unresolved=: resolver gauge. graph_unindexed=N: N files no grammar could read (the map header's unindexed=); their calls raise neither gauge. root=: p= relative to it. amb=K: K calls split over several defs. c sites_at=: its calls of the leaf name, any receiver, as file:line (p= is its def line); not proof each binds. -->
<safe-delete schema="ripwire.safe-delete/v1" sym="rankGraphTeleport" t="fn" p="src/graph.h:13631" defs="1" callers="7" ambiguous_callers="2" impact_reaches="70" uses="9" tested_self="0" radius_tested="0" radius_untested="70" dead_code_candidate="0" risk="untested-radius" shown="7" capped="0" graph_a … [line truncated: 89 more bytes on this line]
<c n="runEval" p="src/eval.h:171" sites_at="src/eval.h:328" amb="5"/>
<c n="rankGraph" p="src/graph.h:13674" sites_at="src/graph.h:13678"/>
<c n="anchoredLexicalRank" p="src/graph.h:14321" sites_at="src/graph.h:14372"/>
<c n="churnDecayRanking" p="src/main.cpp:1433" sites_at="src/main.cpp:1447"/>
<c n="churnRankedGraph" p="src/main.cpp:1472" sites_at="src/main.cpp:1486 src/main.cpp:1487 src/main.cpp:1501"/>
<c n="runDefaultMap" p="src/main.cpp:1759" sites_at="src/main.cpp:1879" amb="15"/>
<c n="getIndex" p="src/mcpindex.h:1211" sites_at="src/mcpindex.h:1323"/>
</safe-delete>
`````

## `./build/ripwire . --safe-delete=DoesNotExist`

*Unknown-symbol refusal shape for --safe-delete.*

**exit code: 1** — **wall time: 1.85s**

`````
(empty)
`````

stderr:

`````
ripwire: --safe-delete symbol not found: DoesNotExist (note: the lexical definition scan stopped at its budget, 4096 files or 16 MiB, before reading every file, so this miss is not proof the bytes define nothing; --grep=DoesNotExist lists its text uses)
`````

## `./build/ripwire . --handoff`

*The continuation packet for the NEXT session: <verified> disk truth (branch/sha, changed symbols, blast radius, tests) + <heuristic> labeled suggestions. Recorded against a CLEAN tree.*

**wall time: 11.50s**

`````
<!-- ripwire handoff schema=ripwire.handoff/v1: continuation packet for the NEXT session: <verified changed= blast_files=>, <tests n=>, <heuristic n= candidates=>, <note>, <doc p=>. window: capped= (capped=1 cut). est_tokens=: price as emitted (an upper bound under compact). at=: commit+dirty+shallow. root=: p= relative to it. branch=/subject=: the checked out branch and HEAD commit subject; gitok=0: the git diff probe failed, changed counts are floors. cochange_window=/cochange_commits=: the git window the cochange rows were mined in and the commits it held (0: could not look). doc s=: lexical score of that plan/design doc for the branch+subject query. note target=/txt=: a committed notes row on this work (symbol id or path) and its text; a suggestion. -->
<handoff schema="ripwire.handoff/v1" at="0412539b9" root="." branch="integration/train-1111c" subject="Re-pin binary-pinned files from the merged build (parity labels, legend pair, COMMANDS.md)" gitok="1" est_tokens="895">
<verified changed="0" blast_files="0">
<tests n="0">
</tests>
</verified>
<heuristic n="6" candidates="260" capped="1" cochange_window="18mo@HEAD" cochange_commits="6983">
<note target="src/infra/Diagnostics.h" txt="ASSUME_NO_ALIAS is an optimizer fact in release (separate_storage) only where the compiler consumes it: clang 18+ by default, LLVM 17/AppleClang 16 via the CMake -mllvm flag (scalars only), GCC never (debug check only); never on two members of one object;  … [line truncated: 57 more bytes on this line]
<note target="test/manifestcheck.sh" txt="README.md&apos;s single &apos;&lt;N&gt; gate scripts&apos; claim (~line 1305) is NOT enforced — the derived-vs-stated sibling loop here covers docs/EVALS.md only. It drifted 407→451 unnoticed (fixed 2026-08-23). To close: grep both files (&apos;file:line … [line truncated: 47 more bytes on this line]
<doc p="CHANGELOG.md" s="14.326"/>
<doc p="prompts/help-wanted/visual-basic-language.md" s="12.333"/>
<doc p="prompts/help-wanted/uses-qualified-selector.md" s="11.438"/>
<doc p="prompts/help-wanted/next-uses-bare-name.md" s="10.634"/>
</heuristic>
</handoff>
`````

## `./build/ripwire . --handoff --token-budget=1200`

*The same packet under a hard ceiling: heuristic rows drop tail-first (withheld= disclosed), verified rows never drop.*

**wall time: 8.71s**

`````
<!-- ripwire handoff schema=ripwire.handoff/v1: continuation packet for the NEXT session: <verified changed= blast_files=>, <tests n=>, <heuristic n= candidates=>, <note>, <doc p=>. window: capped= (capped=1 cut). est_tokens=: price as emitted (an upper bound under compact). withheld=: rows the budget cut. at=: commit+dirty+shallow. root=: p= relative to it. branch=/subject=: the checked out branch and HEAD commit subject; gitok=0: the git diff probe failed, changed counts are floors. cochange_window=/cochange_commits=: the git window the cochange rows were mined in and the commits it held (0: could not look). note target=/txt=: a committed notes row on this work (symbol id or path) and its text; a suggestion. budget=: the token-budget cap this packet was fitted to; est_tokens= prices what it delivers. withheld_rows=N: heuristic rows the budget dropped (withheld=1 says so); verified rows are never dropped. -->
<handoff schema="ripwire.handoff/v1" at="0412539b9" root="." branch="integration/train-1111c" subject="Re-pin binary-pinned files from the merged build (parity labels, legend pair, COMMANDS.md)" gitok="1" budget="1200" withheld="1" withheld_rows="4" est_tokens="883">
<verified changed="0" blast_files="0">
<tests n="0">
</tests>
</verified>
<heuristic n="2" candidates="260" capped="1" cochange_window="18mo@HEAD" cochange_commits="6983">
<note target="src/infra/Diagnostics.h" txt="ASSUME_NO_ALIAS is an optimizer fact in release (separate_storage) only where the compiler consumes it: clang 18+ by default, LLVM 17/AppleClang 16 via the CMake -mllvm flag (scalars only), GCC never (debug check only); never on two members of one object;  … [line truncated: 57 more bytes on this line]
<note target="test/manifestcheck.sh" txt="README.md&apos;s single &apos;&lt;N&gt; gate scripts&apos; claim (~line 1305) is NOT enforced — the derived-vs-stated sibling loop here covers docs/EVALS.md only. It drifted 407→451 unnoticed (fixed 2026-08-23). To close: grep both files (&apos;file:line … [line truncated: 47 more bytes on this line]
</heuristic>
</handoff>
`````

## `./build/ripwire . --skipped`

*WHY a file is not in the index (oversize / excluded / unsupported-ext / gitignored) and which indexed files it cannot vouch for (degraded-parse, minified-suspect), plus the per-language census.*

**wall time: 1.14s**

`````
<ctx schema="ripwire.skipped/v1">
<!-- ripwire skipped schema=ripwire.skipped/v1: why the index lacks a file <f p= why= bytes= limit= ext=>; indexed but unvouched <h p= why= err= err_ratio=>; <lang> census. root=: p= relative to it. indexed=N: the map's files=; indexed= + oversize= + excluded= + ignored= = every file the crawl enumerated. oversize=N: files dropped for exceeding a size ceiling (row limit= names which). excluded=N: files dropped by an exclude substring you passed. unsupported_ext=N: source/text files no grammar reads; binary assets and excluded/ignored files not counted. excluded_dirs=N: subtrees an exclude pruned; their files are UNKNOWN, not zero, and in no count here. pruned_dirs=N: subtrees pruned by built-in policy (vendor/build, CMakeCache.txt dirs); contents UNKNOWN. ignored=/ignored_dirs=: files / subtrees git ignore rules hid (else indexed); subtree contents UNKNOWN. ignore_mode=: git (rules applied), off (no-ignore flag), unavailable/root-ignored (not consulted, full walk). degraded_parse=/minified_suspect=: counts of the h rows of each why=; those files stay indexed. unmeasured=N: indexed files never parsed (doc pass, binary sniff, nest guard, read error); not health-counted. max_file_size=B: the effective per-file size ceiling in bytes (the max-file-size flag raises it). json_ceiling=/yaml_ceiling=: fixed .json/.yaml byte ceilings the max-file-size flag does NOT raise. ws_freq=R: whitespace share of the leading 4096 bytes; under 0.070 = minified-suspect (never under 256 B). x=/files=: an unindexed extension and its file count (full list; the map's unindexed= is the top 6). files=/symbols=: per language, files with its symbols (FLOOR: symbol-less files uncounted) / symbols (exact). -->
<!-- why=extent-suspect on an <h> row = the file holds extent_suspect_syms= definitions whose extent, scope or kind FAILED a containment check (the map and bundle rows carry the reasons as extent_suspect=: name, head, scope, error); joined to the parse-health reasons comma-separated, and rowed even when the parse itself is clean. extent_suspect_files= on the root counts such rows. Nothing is dropped. -->
<!-- why=macro-blanked on an <h> row = this file's symbols come from a SECOND parse. Its first parse held error bytes, so macro_blanked= semicolon-less ALL-CAPS function-like macro invocations, each alone on its line directly inside a class/struct/union body (a shape the C-family grammars misread as a field missing its semicolon, letting one body swallow what follows it), were replaced by spaces with every offset and line unchanged, and that re-parse was adopted because it held STRICTLY FEWER error bytes; names, spans and bodies still read the original bytes. err=, err_ratio= and degraded-parse on such a row describe the ADOPTED parse: a row without degraded-parse parsed clean once blanked. A blanked invocation stays a use of the macro name for the uses verb (role=type, as the unrepaired parse recorded it) but is no call edge, and identifiers inside its parentheses are not recorded. macro_blanked_files= on the root counts such rows. Nothing is dropped. -->
<!-- why=use-bounds-blanked on an <h> row = this Rust file's symbols come from a SECOND parse. Its first parse held error bytes, so use_bounds_blanked= precise-capturing bounds (a use<..> list on an impl Trait, which this build's Rust grammar predates) were replaced by spaces with every offset and line unchanged, and that re-parse was adopted because it held STRICTLY FEWER error bytes; names, spans and bodies still read the original bytes. A use<..> list names only generic parameters and lifetimes already in scope, so no definition, call or type use is lost. err=, err_ratio= and degraded-parse on such a row describe the ADOPTED parse. use_bounds_blanked_files= on the root counts such rows. Nothing is dropped. -->
<skipped indexed="4497" oversize="15" excluded="0" unsupported_ext="286" excluded_dirs="0" pruned_dirs="7" ignored="0" ignored_dirs="0" ignore_mode="git" degraded_parse="173" minified_suspect="4" extent_suspect_files="4" macro_blanked_files="7" use_bounds_blanked_files="2" unmeasured="41" max_file_s … [line truncated: 67 more bytes on this line]
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
<f p=".clang-tidy-baseline.txt" why="unsupported-ext" bytes="128944" ext=".txt"/>
<f p=".github/pargates-macos-plain-skip.txt" why="unsupported-ext" bytes="986" ext=".txt"/>
<f p="CMakeLists.txt" why="unsupported-ext" bytes="112342" ext=".txt"/>
<f p="bench/agentloop/editsuite/expected/i1/stats.py.expected" why="unsupported-ext" bytes="603" ext=".expected"/>
<f p="bench/agentloop/editsuite/expected/i2/matrix.cpp.expected" why="unsupported-ext" bytes="973" ext=".expected"/>
<f p="bench/agentloop/editsuite/expected/i3/text.py.expected" why="unsupported-ext" bytes="338" ext=".expected"/>
<f p="bench/agentloop/editsuite/expected/p1/geometry.cpp.expected" why="unsupported-ext" bytes="723" ext=".expected"/>
<f p="bench/agentloop/editsuite/expected/p2/stats.py.expected" why="unsupported-ext" bytes="575" ext=".expected"/>
<f p="bench/agentloop/editsuite/expected/p2/text.py.expected" why="unsupported-ext" bytes="312" ext=".expected"/>
… [520 more display lines; full output is 55286 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --no-ignore --top-k=3`

*Crawl paths the repo's own .gitignore covers (default honours it and discloses ignored_files=/ignored_dirs= only when it dropped anything — this repo's crawl drops nothing, so the header is identical to the default map's; --skipped's ignore_mode= says which rule applied).*

**wall time: 1.59s**

`````
<!-- ripwire map schema=ripwire.map/v1: ranked symbol map: <f p= layer=> groups <s t= n= sc= k= amb=> rows (k= rank), <c n=> resolved callees; the header comment is data. est_tokens=: price as emitted (an upper bound under compact). root=: p= relative to it. pr_iters=N: PageRank iterations. <inv listed= unlisted=>: files the ranked rows show / do not (sum = files=), each named or counted below. <entry p= n=>: a program entry by its language's convention (C/Go/Rust main, Java/C# static main, a script main its module scope calls, __main__.py), callees as c rows; manifest entries not read. <ls p= n= f=>: n= unshown files under dir p=; f= names its code files, the rest (tests, docs, config, test/doc/example dirs) counted. declined=K: K call sites without edges, including inert Elixir quote sites after unquote/unquote_splicing re-entry. external=K: K calls proven outside the tree, no edge. locality_pinned=K: K calls pinned by locality alone (a guess). extent_suspect_syms=K: K defs failed containment, corpus-wide. macro_blanked_files=K: K files indexed from a macro-blanked re-parse. prov=scip|binding|import|split|final-segment: how that <c> edge bound (absent: one unique name); split = one arm of an amb= pick; final-segment = a qualified type matched by last name only. files=/symbols=: files and symbols indexed; edges= distinct call edges; shown= symbols printed, a merged row counting each def; ambiguous= calls split over several defs, corpus-wide; unresolved= calls with in-tree evidence and no edge (every def language-filtered or unreachable, or binding refused); order= rows by rank (important-first, important-last; (auto:fill) = flipped past a size threshold) or by path (stable). skipped_oversize=K: K files over a size ceiling, not indexed. unindexed=ext:N: N text files of that extension no grammar reads (6 extensions at most). unindexed_exts=E: E such extensions in all, the list cut. sc=: enclosing scope; the full id is p::sc::n (p= of the row or its <f>) and selectors take it. -->
<!-- t=modscope=a-file's-MODULE-SCOPE(n=<file-scope>):the-statements-outside-every-named-definition,where-a-top-level-call-and-an-anonymous-callback-body's-calls-live;a-CALLER-never-a-callee(nothing-in-the-source-can-name-it)-with-no-body-to-expand;a-file-with-no-such-call-has-no-such-row -->
<!-- t=type|alias|functype=a-Go-named-type-by-its-written-form:type=a-defined-type-whose-WRITTEN-form-is-not-a-struct/iface/func-literal(type-N-string;type-W-Pair-too,whatever-Pair-is-underneath),alias=type-A=B,functype=type-F-func(...) -->
<!-- t=alias|functype-in-C++-and-.h:alias=using-X=Y(also-templated-or-class-scope)or-namespace-L=lib(defs=X-prints-its-written-target-as-to=),functype=a-typedef-of-a-function-or-function-pointer-type(typedef-void(*F)(int));other-typedefs-read-t=struct -->
<!-- files=4497 symbols=39562 edges=38970 shown=3 est_tokens=3914 ambiguous=3456 unresolved=18664 locality_pinned=11 external=11109 declined=41448 extent_suspect_syms=12 macro_blanked_files=7 skipped_oversize=15 unindexed="txt:81,tsv:53,mod:33,jsonl:26,scm:25,expected:15" unindexed_exts=23 order=important-first -->
<r schema="ripwire.map/v1" root="." est_tokens="3914" pr_iters="38">
<f p="src/infra/nodekind.h" layer="infra">
<s t="fn" n="kindIs" sc="rw" k="0.0031">
</s>
</f>
<f p="src/ingest_metrics.h">
<s t="fn" n="nodeTextOf" k="0.0020">
</s>
</f>
<f p="src/model.h">
<s t="fn" n="relForHash" sc="rw" k="0.0020">
</s>
</f>
<inv listed="3" unlisted="4494">
<entry p="scripts/changelog_assemble.py" n="main">
<c n="repoRoot"/>
<c n="fragmentNames"/>
<c n="check"/>
<c n="assembledEntries"/>
<c n="release"/>
</entry>
<entry p="scripts/merge_resolve.py" n="main">
<c n="generator_constants"/>
<c n="git"/>
<c n="parse"/>
… [84 more display lines; full output is 9761 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --no-stable --top-k=3`

*--no-stable outside --mcp: what the flag does (or says) when there is no stable-by-default ordering to opt out of.*

**wall time: 2.64s**

`````
<!-- ripwire map schema=ripwire.map/v1: ranked symbol map: <f p= layer=> groups <s t= n= sc= k= amb=> rows (k= rank), <c n=> resolved callees; the header comment is data. est_tokens=: price as emitted (an upper bound under compact). root=: p= relative to it. pr_iters=N: PageRank iterations. <inv listed= unlisted=>: files the ranked rows show / do not (sum = files=), each named or counted below. <entry p= n=>: a program entry by its language's convention (C/Go/Rust main, Java/C# static main, a script main its module scope calls, __main__.py), callees as c rows; manifest entries not read. <ls p= n= f=>: n= unshown files under dir p=; f= names its code files, the rest (tests, docs, config, test/doc/example dirs) counted. declined=K: K call sites without edges, including inert Elixir quote sites after unquote/unquote_splicing re-entry. external=K: K calls proven outside the tree, no edge. locality_pinned=K: K calls pinned by locality alone (a guess). extent_suspect_syms=K: K defs failed containment, corpus-wide. macro_blanked_files=K: K files indexed from a macro-blanked re-parse. prov=scip|binding|import|split|final-segment: how that <c> edge bound (absent: one unique name); split = one arm of an amb= pick; final-segment = a qualified type matched by last name only. files=/symbols=: files and symbols indexed; edges= distinct call edges; shown= symbols printed, a merged row counting each def; ambiguous= calls split over several defs, corpus-wide; unresolved= calls with in-tree evidence and no edge (every def language-filtered or unreachable, or binding refused); order= rows by rank (important-first, important-last; (auto:fill) = flipped past a size threshold) or by path (stable). skipped_oversize=K: K files over a size ceiling, not indexed. unindexed=ext:N: N text files of that extension no grammar reads (6 extensions at most). unindexed_exts=E: E such extensions in all, the list cut. sc=: enclosing scope; the full id is p::sc::n (p= of the row or its <f>) and selectors take it. -->
<!-- t=modscope=a-file's-MODULE-SCOPE(n=<file-scope>):the-statements-outside-every-named-definition,where-a-top-level-call-and-an-anonymous-callback-body's-calls-live;a-CALLER-never-a-callee(nothing-in-the-source-can-name-it)-with-no-body-to-expand;a-file-with-no-such-call-has-no-such-row -->
<!-- t=type|alias|functype=a-Go-named-type-by-its-written-form:type=a-defined-type-whose-WRITTEN-form-is-not-a-struct/iface/func-literal(type-N-string;type-W-Pair-too,whatever-Pair-is-underneath),alias=type-A=B,functype=type-F-func(...) -->
<!-- t=alias|functype-in-C++-and-.h:alias=using-X=Y(also-templated-or-class-scope)or-namespace-L=lib(defs=X-prints-its-written-target-as-to=),functype=a-typedef-of-a-function-or-function-pointer-type(typedef-void(*F)(int));other-typedefs-read-t=struct -->
<!-- files=4497 symbols=39562 edges=38970 shown=3 est_tokens=3914 ambiguous=3456 unresolved=18664 locality_pinned=11 external=11109 declined=41448 extent_suspect_syms=12 macro_blanked_files=7 skipped_oversize=15 unindexed="txt:81,tsv:53,mod:33,jsonl:26,scm:25,expected:15" unindexed_exts=23 order=important-first -->
<r schema="ripwire.map/v1" root="." est_tokens="3914" pr_iters="38">
<f p="src/infra/nodekind.h" layer="infra">
<s t="fn" n="kindIs" sc="rw" k="0.0031">
</s>
</f>
<f p="src/ingest_metrics.h">
<s t="fn" n="nodeTextOf" k="0.0020">
</s>
</f>
<f p="src/model.h">
<s t="fn" n="relForHash" sc="rw" k="0.0020">
</s>
</f>
<inv listed="3" unlisted="4494">
<entry p="scripts/changelog_assemble.py" n="main">
<c n="repoRoot"/>
<c n="fragmentNames"/>
<c n="check"/>
<c n="assembledEntries"/>
<c n="release"/>
</entry>
<entry p="scripts/merge_resolve.py" n="main">
<c n="generator_constants"/>
<c n="git"/>
<c n="parse"/>
… [84 more display lines; full output is 9761 bytes on 1 raw line(s)]
`````

stderr:

`````
ripwire: --no-stable is read only by --mcp/--listen (it opts out of the stable ordering the server turns on) — it changed nothing here; the CLI map orders important-first unless you pass --order=stable
`````

## `./build/ripwire . --run-trace="cat <scratch>/aux/asan_trace_now.txt; exit 1"`

*EXEC-MODE --from-trace: run a command, and on a non-zero exit map its captured output onto indexed symbols in the same call — the whole fix-loop entry. ripwire exits 4 here because the wrapped command failed, which is the signal, not an incident.*

**exit code: 4** — **wall time: 1.71s**

`````
<ctx schema="ripwire.from-trace/v1" task="run-trace: cat <scratch>/aux/asan_trace_now.txt; exit 1" next="--slice=@src/graph.h:13633" est_tokens="2604">
<!-- ripwire from-trace schema=ripwire.from-trace/v1: trace frames mapped to indexed symbols, innermost first; the innermost in-corpus body included. window: shown= total= capped= (capped=1 cut). est_tokens=: price as emitted (an upper bound under compact). <d r=N>: rank N in this ranking, rows in r= order. <d cx= ccx=>: cyclomatic/cognitive complexity. <d in=N>: N callers in the index (absent: not measured). sc=: enclosing scope; the full id is p::sc::n (p= of the row or its <f>) and selectors take it. next=: the one pasteable follow-up. task=: the trace source this bundle maps, verbatim (a file path, stdin, or an MCP label). src=/format=: the trace read and its dominant frame format, python|asan|node|compiler|generic. frame_lines=/parsed=: frame-shaped input lines / those yielding a path:line; the rest matched no format. in_corpus=: parsed frames in indexed files; always suspects= + merged= + unresolved=. suspects=/merged=/unresolved=: frame rows / folded into a claimed symbol / unresolved rows (indexed file, no def). skipped=N: frames outside every root, listed as skipped rows, never ranked. rank=N: frame order, innermost in-corpus first; p= is the trace's own path:line, defs are sigs l=. resolved_by=name|line: bound by the frame's own name, else by the def enclosing its line. innermost=1: the innermost in-corpus frame (rank 1); its full body is served. run exit=: the command's OWN exit code; signal=: the signal that killed it; timed_out=1: the timeout_s= cap did. run duration_ms=: wall clock, MEASURED, not deterministic; timeout_s=: the cap it ran under. run lines=: non-empty captured lines; bytes=: the whole capture; dropped_bytes=: middle bytes the cap dropped. lines view=tail: the last shown= of total= output lines; view=relevant: shown= of relevant= error/frame-shaped ones. lines relevant=N: captured lines that are error-marked or frame-shaped; the relevant view picks from these. -->
<!-- ledger: budget=7500 bytes (allowance 9583 bytes = ceiling + the single-entry overshoot a whole first signature costs) -->
<run exit="1" duration_ms="321" timeout_s="600" lines="9" bytes="606"/>
<lines view="relevant" shown="7" relevant="7" total="9">
<![CDATA[AddressSanitizer:DEADLYSIGNAL
==41337==ERROR: AddressSanitizer: SEGV on unknown address 0x000000000018 (pc 0x000102f4a1c8 bp 0x00016d2f1a40 sp 0x00016d2f19e0 T0)
    #0 0x102f4a1c8 in rw::rankGraphTeleport(Graph const&, std::vector<float> const&, float) src/graph.h:13633
    #1 0x102f3e884 in rw::rankGraph(Graph const&, float) src/graph.h:13676
    #2 0x102e11f30 in runDefaultMap(MainDispatch const&) src/main.cpp:1761
    #3 0x102e01a44 in main src/main.cpp:4270
    #4 0x1a2b3c0dc in start+0x9dc (dyld:arm64e+0x60dc)]]></lines><trace src="run-trace: cat <scratch>/aux/asan_trace_now.txt; exit 1" format="asan" frame_lines="5" parsed="4" in_corpus="4" skipped="0" merged="0" unresolved="0" suspects … [line truncated: 1642 more bytes on this line]
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
}]]><calls total="4"><c n="biasPrior" l="13590">inline std::vector&lt;float&gt; biasPrior( const Graph&amp; g, const std::vector&lt;float&gt;&amp; p )</c><c n="PROFILE_SCOPE_DESCRIBE" l="1282">#define PROFILE_SCOPE_DESCRIBE( desc )</c><c n="PROFILE_SCOPE_DESCRIBE" l="1296">#define PROFILE_SCOPE_DESC … [line truncated: 289 more bytes on this line]
`````

## `./build/ripwire . --run-trace="true"`

*A command that exits 0: a minimal success record (exit, measured duration, disclosed output tail) and NO bundle — nothing failed, nothing to map.*

**wall time: 1.51s**

`````
<ctx schema="ripwire.from-trace/v1" task="run-trace: true">
<!-- ripwire from-trace schema=ripwire.from-trace/v1: trace frames mapped to indexed symbols, innermost first; the innermost in-corpus body included. task=: the trace source this bundle maps, verbatim (a file path, stdin, or an MCP label). run exit=: the command's OWN exit code; signal=: the signal that killed it; timed_out=1: the timeout_s= cap did. run duration_ms=: wall clock, MEASURED, not deterministic; timeout_s=: the cap it ran under. run lines=: non-empty captured lines; bytes=: the whole capture; dropped_bytes=: middle bytes the cap dropped. -->
<run exit="0" duration_ms="388" timeout_s="600" lines="0" bytes="0"/>
</ctx>
`````

## `./build/ripwire . --run-trace="sleep 30" --run-timeout=2`

*A command still running at the cap: its process group is killed and the run reports timed_out=1 — an honest timeout, never an empty success.*

**exit code: 4** — **wall time: 3.17s**

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

**wall time: 10.28s**

`````
<!-- ripwire quality-panel schema=ripwire.quality-panel/v1: every quality family in ONE report, ranked by distinct families fired: <s p= n= fam= of= fired= join=>; bar_*= thresholds. window: shown= total= capped= has_more= next_offset= offset= limit= (capped=1 cut; next_offset= pastes as offset=). at=: commit+dirty+shallow. root=: p= relative to it. preset=: strict (5 stable families, cut 2), default (6, cut 2), lenient (6, cut 1); selects, never weights. families=6: evidence families: structural lexical confusion historical colocation state. enabled=/enabled_n=: the families this preset COUNTS, and how many. cut=N: distinct enabled families that must fire for a row to rank. cut_reachable=0: cut= exceeds the evaluable families (of=); a corpus fact, never a clean bill of health. eligible=N: functions/methods with a body; ranked= + below_cut= + no_family= = eligible=, always. ranked=N: rows that met the cut (total=); only shown= print, page with offset=. below_cut=N: fired at least one enabled family, but fewer than cut=. no_family=N: no enabled family fired; unavailable= families were never measured. bar_ccx=/bar_loc=/bar_nest=/bar_params=: absolute bars: cognitive complexity, lines, nesting, params. rcut=/rmeasured=: readability decile width (rrank= under it fires) / functions measured. hcut=/hranked=: file churn decile width / files with an in-window commit (hranked=0 voids historical). window=: the git churn window hrank= and churn= are counted over (RELATIVE to this corpus). ccut=/cranked=: colocation decile width / functions reading any outside definition (0 voids it). cfiles=/cscope=: files the confusion atom rules read / eligible symbols in them. lscope=N: symbols the lexical naming rules read. sfiles=/sscope=: files the state lens reads / symbols in them. cells=N: non-local mutable cells the state lens found. tested_scope=N: symbols an indexed test reaches; at 0 no row can carry join=deep+untested. deep_untested=N: rows carrying join=deep+untested across the WHOLE set, not just this page. e f=: the fired family this evidence row belongs to. counted=1: this preset counts the family toward fam=; 0 = fired, not counted. why=: the measurements that crossed (rule*N fired N times; hrank=/churn= are the file's, inherited). -->
<quality_panel schema="ripwire.quality-panel/v1" preset="default" families="6" enabled="structural,lexical,confusion,historical,colocation,state" enabled_n="6" cut="2" cut_reachable="1" eligible="22551" ranked="1238" below_cut="7500" no_family="13813" bar_ccx="15" bar_loc="60" bar_nest="4" bar_param … [line truncated: 335 more bytes on this line]
<s p="src/gitmine.h:1795" n="addRootFilesToGitPathIndex" fam="4" of="6" fired="structural,lexical,confusion,historical">
<e f="structural" counted="1" why="ccx=25 ev=6"/>
<e f="lexical" counted="1" why="naming-wordy"/>
<e f="confusion" counted="1" why="atom-embedded-crement*2"/>
<e f="historical" counted="1" why="hrank=32 churn=103"/>
</s>
<s p="src/graph.h:9618" n="buildGraph" fam="4" of="6" fired="structural,confusion,historical,colocation">
<e f="structural" counted="1" why="ccx=2002 loc=3964 nest=8 humps=102 deep=667 ev=252 rrank=0"/>
<e f="confusion" counted="1" why="atom-embedded-crement*6 atom-nested-ternary*2"/>
<e f="historical" counted="1" why="hrank=5 churn=640"/>
<e f="colocation" counted="1" why="crank=16"/>
</s>
<s p="src/graphlegend.h:770" n="declinedSitesLegend" fam="4" of="6" fired="structural,lexical,confusion,historical">
<e f="structural" counted="1" why="ccx=29 ev=2"/>
<e f="lexical" counted="1" why="naming-confusable"/>
<e f="confusion" counted="1" why="atom-nested-ternary*5"/>
<e f="historical" counted="1" why="hrank=19 churn=219"/>
</s>
<s p="src/ingest_relations.h:320" n="lookupInScope" fam="4" of="6" fired="structural,confusion,historical,state">
<e f="structural" counted="1" why="params=5 ev=6"/>
<e f="confusion" counted="1" why="atom-embedded-crement"/>
<e f="historical" counted="1" why="hrank=38 churn=87"/>
<e f="state" counted="1" why="reads=1"/>
</s>
<s p="src/ingest_sidecap.h:1857" n="captureTagsFacts" fam="4" of="6" fired="structural,confusion,historical,colocation">
<e f="structural" counted="1" why="ccx=558 loc=898 nest=6 params=13 humps=42 deep=222 ev=51 rrank=8"/>
<e f="confusion" counted="1" why="atom-nested-ternary*2"/>
<e f="historical" counted="1" why="hrank=23 churn=170"/>
… [189 more display lines; full output is 15651 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --biggest-first --limit=8`

*Per-function size ranking, largest Halstead volume/token entropy/lines first — a size proxy, not a readability order (withdrawn, docs/EVALS.md §8) — a RANKING lens, not a grade.*

**wall time: 1.91s**

`````
<!-- ripwire readability schema=ripwire.readability/v1: Posnett/Hindle/Devanbu lens, largest Halstead volume first (a size proxy): <fn p= n= lines= toks= ops= vocab= vol= ent= posnett=>. window: shown= total= capped= has_more= next_offset= offset= limit= (capped=1 cut; next_offset= pastes as offset=). root=: p= relative to it. functions=N: functions and methods measured (bodyless declarations are not). -->
<readability schema="ripwire.readability/v1" functions="22551" shown="8" capped="1" total="22551" has_more="1" next_offset="8" offset="0" limit="8" root=".">
<fn p="src/graph.h:9618" n="buildGraph" lines="3964" toks="24785" ops="15929" vocab="1243" vol="254780.1" ent="6.79" posnett="0.000"/>
<fn p="src/verbs_for.h:3356" n="runForLensPass" lines="1957" toks="12046" ops="7366" vocab="895" vol="118120.0" ent="6.58" posnett="0.000"/>
<fn p="src/mcp.h:1146" n="dispatchMcpLine" lines="1851" toks="9435" ops="5999" vocab="827" vol="91441.6" ent="6.56" posnett="0.000"/>
<fn p="src/main.cpp:4438" n="dispatchMainBody" lines="1594" toks="7943" ops="5096" vocab="732" vol="75583.2" ent="6.41" posnett="0.000"/>
<fn p="test/forbodyslotfix/src/c/render.c:7" n="render_screen" lines="176" toks="9485" ops="6322" vocab="181" vol="71136.0" ent="4.54" posnett="0.000"/>
<fn p="src/main.cpp:1759" n="runDefaultMap" lines="1187" toks="6548" ops="4027" vocab="526" vol="59186.8" ent="6.46" posnett="0.000"/>
<fn p="src/lexical.h:501" n="lexicalScoresTiered" lines="1045" toks="6320" ops="4015" vocab="389" vol="54374.9" ent="6.36" posnett="0.000"/>
<fn p="src/packtask.h:1450" n="packTaskBundleText" lines="842" toks="5963" ops="3643" vocab="534" vol="54028.9" ent="6.56" posnett="0.000"/>
</readability>
`````

## `./build/ripwire . --comment-coherence --limit=8`

*Functions WITH a doc comment, most name-restating first: c_coeff (high = the comment repeats the name) and cic (Jaccard of comment vs identifier vocabulary), both reported, never collapsed.*

**wall time: 2.14s**

`````
<!-- ripwire comment-coherence schema=ripwire.comment-coherence/v1: two comment/name content measures per documented function, most name-restating first: <fn p= n= c_coeff= cic=>. window: shown= total= capped= has_more= next_offset= offset= limit= (capped=1 cut; next_offset= pastes as offset=). root=: p= relative to it. documented=N: functions with a doc comment, measured (the rows); a FLOOR when unreadable_files= shows. no_comment=N: eligible symbols with no measurable comment; UNAVAILABLE, never scored as zero. words=/restate=: comment word count (c_coeff= denominator, stopwords kept) / words matching a name word. c_terms=/i_terms=/shared=: comment term set / identifiers the body uses / overlap; cic= shared over union. -->
<comment_coherence schema="ripwire.comment-coherence/v1" documented="6610" no_comment="15941" shown="8" capped="1" total="6610" has_more="1" next_offset="8" offset="0" limit="8" root=".">
<fn p="src/infra/os.h:551" n="socket" c_coeff="1.000" words="1" restate="1" cic="0.000" c_terms="1" i_terms="5" shared="0"/>
<fn p="src/lsp.h:485" n="lspLocationJson" c_coeff="1.000" words="1" restate="1" cic="0.000" c_terms="1" i_terms="26" shared="0"/>
<fn p="src/query.h:267" n="sourceAll" c_coeff="1.000" words="1" restate="1" cic="0.000" c_terms="1" i_terms="12" shared="0"/>
<fn p="src/verbs_quality.h:2549" n="runDmm" c_coeff="1.000" words="1" restate="1" cic="0.029" c_terms="1" i_terms="35" shared="1"/>
<fn p="src/infra/dynamic_map.hpp:1955" n="erase_rec" c_coeff="1.000" words="1" restate="1" cic="0.048" c_terms="1" i_terms="21" shared="1"/>
<fn p="test/verify_os_win32_logic.cpp:249" n="WidePath: separators, the Git Bash drive spelling, and nothing else rewritten" c_coeff="1.000" words="2" restate="2" cic="0.133" c_terms="2" i_terms="15" shared="2"/>
<fn p="test/verify_os_win32_logic.cpp:191" n="utf: every scalar value round-trips UTF-8 -&gt; UTF-16 -&gt; UTF-8 byte-exactly" c_coeff="1.000" words="5" restate="5" cic="0.150" c_terms="4" i_terms="19" shared="3"/>
<fn p="test/lintfix/bad.cpp:23" n="emptyCatchFunc" c_coeff="1.000" words="2" restate="2" cic="0.400" c_terms="2" i_terms="5" shared="2"/>
</comment_coherence>
`````

## `./build/ripwire . --context-ratio --limit=8`

*The local-reasoning lens: to understand this symbol, how much must you know that is NOT in front of you (ent_ratio= edge share, read_ratio= token-weighted).*

**wall time: 1.51s**

`````
<!-- ripwire context-ratio schema=ripwire.context-ratio/v1: LOCAL-REASONING lens: the share of a unit's context outside its file: <s p= n= sites= ents_out= ent_ratio= read_ratio=>. window: total= has_more= next_offset= offset= limit= (capped=1 cut; next_offset= pastes as offset=). syms_capped=/files_capped=/defs_capped=: 1 = cut. counts_floor=1: every count is a FLOOR, never a total. root=: p= relative to it. units=N: symbols measured (the s row population). file_units=N: files measured (the f row population). defs_per_name_cap=N: most defs one name adds (lowest ids); defs_capped=1 = cut, ents=/rtok= floors. body_bytes_per_token=: the bytes-per-token rate rtok= is estimated at. shown_syms=N: symbol rows printed; the rest page with offset=next_offset. shown_files=N: file rows printed (fixed cap 40, not paged); files_capped=1 = rows dropped. ents=N: distinct in-corpus defs its reference sites resolve to, by name (a FLOOR). files=N: distinct files holding those defs (a FLOOR). files_out=N: of files=, those other than the unit's own file. rtok=N: est. tokens of every resolved def, what a reader must read. rtok_out=N: the part of rtok= defined outside the unit's own file. ext=N: referenced names with no in-corpus def; mostly locals/params, NOT external deps; in neither ratio. amb_names=N: referenced names with 2+ defs, each counted (per name; not the map's per-call amb=). ents=N: distinct in-corpus defs the file's sites resolve to (a FLOOR; a union, not the sum of s rows). files=N: distinct files holding those defs (a FLOOR). files_out=N: of files=, those other than this file. rtok=N: est. tokens of every resolved def, what a reader must read. rtok_out=N: the part of rtok= defined outside this file. ext=N: referenced names with no in-corpus def; mostly locals/params, NOT external deps; in neither ratio. amb_names=N: referenced names with 2+ defs, each counted (per name; not the map's per-call amb=). -->
<contextratio schema="ripwire.context-ratio/v1" units="33601" file_units="3851" defs_per_name_cap="8" body_bytes_per_token="3.80" shown_syms="8" syms_capped="1" shown_files="40" files_capped="1" total="33601" has_more="1" next_offset="8" offset="0" limit="8" defs_capped="1" counts_floor="1" root="." … [line truncated: 1 more bytes on this line]
<s p="src/main.cpp:4438" n="dispatchMainBody" t="fn" sites="1169" ents="263" ents_out="240" ent_ratio="0.913" files="82" files_out="81" rtok="281389" rtok_out="245644" read_ratio="0.873" ext="130" amb_names="32"/>
<s p="src/mcpverbs.h:4812" n="computeQualityDelta" t="fn" sites="71" ents="45" ents_out="41" ent_ratio="0.911" files="19" files_out="18" rtok="92052" rtok_out="91181" read_ratio="0.991" ext="9" amb_names="8"/>
<s p="src/mcp.h:1146" n="dispatchMcpLine" t="fn" sites="1368" ents="246" ents_out="220" ent_ratio="0.894" files="54" files_out="53" rtok="94783" rtok_out="89676" read_ratio="0.946" ext="169" amb_names="22"/>
<s p="src/main.cpp:1759" n="runDefaultMap" t="fn" sites="1101" ents="154" ents_out="142" ent_ratio="0.922" files="46" files_out="45" rtok="89409" rtok_out="84710" read_ratio="0.947" ext="148" amb_names="18"/>
<s p="src/mcpverbs.h:5320" n="editCheckText" t="fn" sites="37" ents="44" ents_out="44" ent_ratio="1.000" files="28" files_out="28" rtok="83181" rtok_out="83181" read_ratio="1.000" ext="4" amb_names="8"/>
<s p="src/editpreview.h:342" n="run" t="fn" sites="127" ents="66" ents_out="62" ent_ratio="0.939" files="33" files_out="32" rtok="80406" rtok_out="78083" read_ratio="0.971" ext="31" amb_names="9"/>
<s p="src/mcpindex.h:1211" n="getIndex" t="fn" sites="175" ents="96" ents_out="76" ent_ratio="0.792" files="30" files_out="29" rtok="79423" rtok_out="75565" read_ratio="0.951" ext="20" amb_names="13"/>
<s p="src/mcpverbs.h:5030" n="qualityBaselineJson" t="fn" sites="32" ents="46" ents_out="45" ent_ratio="0.978" files="28" files_out="27" rtok="73158" rtok_out="73129" read_ratio="1.000" ext="4" amb_names="10"/>
<f p="src/main.cpp" sites="4149" ents="581" ents_out="493" ent_ratio="0.849" files="128" files_out="127" rtok="478025" rtok_out="403230" read_ratio="0.844" ext="572" amb_names="60"/>
<f p="src/mcpverbs.h" sites="5897" ents="824" ents_out="743" ent_ratio="0.902" files="140" files_out="139" rtok="436974" rtok_out="365171" read_ratio="0.836" ext="730" amb_names="59"/>
<f p="src/verbs_for.h" sites="4905" ents="600" ents_out="477" ent_ratio="0.795" files="142" files_out="141" rtok="263391" rtok_out="181684" read_ratio="0.690" ext="542" amb_names="51"/>
<f p="src/verbs_navigate.h" sites="4748" ents="592" ents_out="541" ent_ratio="0.914" files="109" files_out="108" rtok="177829" rtok_out="151162" read_ratio="0.850" ext="458" amb_names="47"/>
<f p="src/graph.h" sites="13827" ents="1179" ents_out="635" ent_ratio="0.539" files="148" files_out="147" rtok="240703" rtok_out="130621" read_ratio="0.543" ext="1208" amb_names="138"/>
<f p="src/quality.h" sites="5570" ents="693" ents_out="414" ent_ratio="0.597" files="125" files_out="124" rtok="184794" rtok_out="127492" read_ratio="0.690" ext="681" amb_names="83"/>
<f p="src/mcpindex.h" sites="718" ents="244" ents_out="204" ent_ratio="0.836" files="58" files_out="57" rtok="112959" rtok_out="105652" read_ratio="0.935" ext="126" amb_names="38"/>
<f p="src/mcp.h" sites="1929" ents="322" ents_out="265" ent_ratio="0.823" files="65" files_out="64" rtok="145962" rtok_out="94832" read_ratio="0.650" ext="242" amb_names="28"/>
<f p="src/editpreview.h" sites="449" ents="134" ents_out="128" ent_ratio="0.955" files="47" files_out="46" rtok="87871" rtok_out="85420" read_ratio="0.972" ext="71" amb_names="21"/>
<f p="src/verbs_change.h" sites="1305" ents="267" ents_out="240" ent_ratio="0.899" files="77" files_out="76" rtok="88432" rtok_out="82844" read_ratio="0.937" ext="131" amb_names="32"/>
<f p="src/verbs_quality.h" sites="2573" ents="413" ents_out="330" ent_ratio="0.799" files="94" files_out="93" rtok="117882" rtok_out="75720" read_ratio="0.642" ext="252" amb_names="38"/>
<f p="test/verify_csr.cpp" sites="184" ents="57" ents_out="54" ent_ratio="0.947" files="26" files_out="25" rtok="71975" rtok_out="71230" read_ratio="0.990" ext="31" amb_names="15"/>
<f p="src/ingest_sidecap.h" sites="1891" ents="376" ents_out="312" ent_ratio="0.830" files="88" files_out="87" rtok="74878" rtok_out="61632" read_ratio="0.823" ext="244" amb_names="43"/>
<f p="src/verbs_report.h" sites="3964" ents="333" ents_out="283" ent_ratio="0.850" files="79" files_out="78" rtok="81333" rtok_out="57337" read_ratio="0.705" ext="429" amb_names="30"/>
<f p="src/mcpserver.h" sites="460" ents="128" ents_out="112" ent_ratio="0.875" files="42" files_out="41" rtok="54483" rtok_out="51758" read_ratio="0.950" ext="65" amb_names="22"/>
<f p="src/packtask.h" sites="1555" ents="242" ents_out="190" ent_ratio="0.785" files="57" files_out="56" rtok="61883" rtok_out="49288" read_ratio="0.796" ext="222" amb_names="29"/>
<f p="src/backhops.h" sites="1226" ents="344" ents_out="256" ent_ratio="0.744" files="85" files_out="84" rtok="65515" rtok_out="48799" read_ratio="0.745" ext="148" amb_names="59"/>
<f p="src/forpage.h" sites="1123" ents="249" ents_out="198" ent_ratio="0.795" files="82" files_out="81" rtok="54043" rtok_out="47532" read_ratio="0.880" ext="173" amb_names="29"/>
<f p="src/ingest_parsepool.h" sites="789" ents="206" ents_out="188" ent_ratio="0.913" files="62" files_out="61" rtok="54733" rtok_out="46179" read_ratio="0.844" ext="118" amb_names="31"/>
<f p="src/ingest_astquery.h" sites="1608" ents="292" ents_out="248" ent_ratio="0.849" files="81" files_out="80" rtok="65206" rtok_out="44117" read_ratio="0.677" ext="221" amb_names="48"/>
… [21 more display lines; full output is 11189 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --nonlocal-state --limit=8`

*Per function, the non-local MUTABLE state it can reach (transitively), most writes first — unsound by construction, and the legend says where.*

**wall time: 3.45s**

`````
<!-- ripwire nonlocal-state schema=ripwire.nonlocal-state/v1: per function, the non-local MUTABLE state it reaches: <fn p= n= writes= reads=> over <cell n= p= dir= via=> rows. window: shown= total= capped= has_more= next_offset= offset= limit= (capped=1 cut; next_offset= pastes as offset=). cells_capped=: 1 = cut. counts_floor=1: every count is a FLOOR, never a total. graph_ambiguous=/graph_unresolved=: resolver gauge. graph_unindexed=N: N files no grammar could read (the map header's unindexed=); their calls raise neither gauge. root=: p= relative to it. cells=N: mutable non-local cells found in the corpus (globals, statics, Python module globals; FLOOR). functions=N: functions reaching at least one cell, directly or via callees (all rows, before paging). direct_writes=/direct_reads=: the writes=/reads= cells this function's OWN body writes/reads. cells_total=N: distinct cells reached (read and written counts once); at most 12 cell rows print. at=/at_dir=: one own-body use site (may be more) and what own-body sites do (can be narrower than dir=). cells_shown=/cells_capped=1: only this many of cells_total= cell rows print (cap 12). unanalyzed_langs=/unanalyzed_files=: indexed languages (and their files) this lens skips; NOT zero cells. -->
<nonlocal_state schema="ripwire.nonlocal-state/v1" cells="1070" functions="1242" shown="8" capped="1" total="1242" has_more="1" next_offset="8" offset="0" limit="8" graph_ambiguous="3456" graph_unresolved="18664" graph_unindexed="286" counts_floor="1" unanalyzed_langs="c,go,rust,javascript,typescrip … [line truncated: 108 more bytes on this line]
<fn p="bench/bench_svector_wave.cpp:346" n="main" writes="8" reads="14" direct_writes="0" direct_reads="4" cells_total="14" cells_shown="12" cells_capped="1">
<cell n="kNames" p="bench/bench_svector_wave.cpp:98" dir="rw" at="bench/bench_svector_wave.cpp:358" at_dir="r"/>
<cell n="kPush" p="bench/bench_svector_wave.cpp:99" dir="rw" at="bench/bench_svector_wave.cpp:358" at_dir="r"/>
<cell n="kReads" p="bench/bench_svector_wave.cpp:100" dir="rw" at="bench/bench_svector_wave.cpp:358" at_dir="r"/>
<cell n="kSamples" p="bench/bench_svector_wave.cpp:101" dir="rw" at="bench/bench_svector_wave.cpp:358" at_dir="r"/>
<cell n="g_api" p="src/infra/profilePmc.h:140" dir="rw" via="ensure_thread_counting"/>
<cell n="g_keyOf" p="bench/bench_svector_wave.cpp:145" dir="rw" via="regenerate"/>
<cell n="g_perf" p="src/infra/profilePmc.h:289" dir="rw" via="ensure_thread_counting"/>
<cell n="g_readOf" p="bench/bench_svector_wave.cpp:146" dir="rw" via="regenerate"/>
<cell n="g_arm" p="bench/bench_svector_wave.cpp:65" dir="r" via="runArm"/>
<cell n="g_bytes" p="bench/bench_svector_wave.cpp:67" dir="r" via="runArm"/>
<cell n="g_count" p="bench/bench_svector_wave.cpp:66" dir="r" via="runArm"/>
<cell n="g_once" p="src/infra/profilePmc.h:290" dir="r" via="ensure_thread_counting"/>
</fn>
<fn p="bench/bench_svector_wave.cpp:295" n="sweep" writes="6" reads="13" direct_writes="4" direct_reads="1" cells_total="13" cells_shown="12" cells_capped="1">
<cell n="kNames" p="bench/bench_svector_wave.cpp:98" dir="rw" at="bench/bench_svector_wave.cpp:317" at_dir="w"/>
<cell n="kPush" p="bench/bench_svector_wave.cpp:99" dir="rw" at="bench/bench_svector_wave.cpp:318" at_dir="w"/>
<cell n="kReads" p="bench/bench_svector_wave.cpp:100" dir="rw" at="bench/bench_svector_wave.cpp:319" at_dir="rw"/>
<cell n="kSamples" p="bench/bench_svector_wave.cpp:101" dir="rw" at="bench/bench_svector_wave.cpp:313" at_dir="w"/>
<cell n="g_keyOf" p="bench/bench_svector_wave.cpp:145" dir="rw" via="regenerate"/>
<cell n="g_readOf" p="bench/bench_svector_wave.cpp:146" dir="rw" via="regenerate"/>
<cell n="g_api" p="src/infra/profilePmc.h:140" dir="r" via="read"/>
<cell n="g_arm" p="bench/bench_svector_wave.cpp:65" dir="r" via="runArm"/>
<cell n="g_bytes" p="bench/bench_svector_wave.cpp:67" dir="r" via="runArm"/>
<cell n="g_count" p="bench/bench_svector_wave.cpp:66" dir="r" via="runArm"/>
<cell n="g_perf" p="src/infra/profilePmc.h:289" dir="r" via="read"/>
<cell n="g_pool" p="bench/bench_svector_wave.cpp:144" dir="r" via="regenerate"/>
</fn>
… [45 more display lines; full output is 7616 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --ensemble --limit=8`

*The family join: per function, which of four orthogonal evidence families fire, ranked by how many agree.*

**wall time: 6.77s**

`````
<!-- ripwire ensemble schema=ripwire.ensemble/v1: four orthogonal evidence families joined, ranked by DISTINCT families fired (no composite score): <s p= n= fam= of= fired=>. window: total= has_more= next_offset= offset= limit= (capped=1 cut; next_offset= pastes as offset=). syms_capped=/files_capped=: 1 = cut. at=: commit+dirty+shallow. root=: p= relative to it. eligible=N: functions and methods with a body, the denominator; ranked + no_family = eligible. no_family=N: eligible symbols where no family fired. bar_ccx=/bar_loc=/bar_nest=/bar_params=: absolute structural bars: cognitive cx, lines, nesting, params. rcut=N: ranks the worst readability decile covers (1 to 40); rrank= inside it fires structural. rmeasured=N: functions the readability lens measured. hcut=N: file ranks the worst churn decile covers (1 to 40); hrank= inside it fires historical. hranked=N: files with any in-window commit; 0 = historical family unavailable. cfiles=N: indexed files the confusion (atom) pack can read: C/C++/ObjC/CUDA. cscope=N: eligible symbols in those files; 0 = confusion family unavailable. lscope=N: eligible symbols in a language the naming pack reads; 0 = lexical family unavailable. shown_syms=N: symbol rows printed; the rest page with offset=next_offset. shown_files=N: file rows printed (fixed cap 20, not paged); files_capped=1 = rows dropped. e f=: the fired family: structural, lexical, confusion or historical. why=: the measurements that crossed, space separated; rule*N = that rule fired N times. top=: the file's most corroborated symbol (most families on one symbol). top_l=: that symbol's line. top_fam=N: families fired on top=, the stronger claim; file rows rank by it. union_fam=N: distinct families firing anywhere in the file (weaker: may be different symbols). union=: the names of those families. syms=N: symbols in the file where at least one family fired. families=N: evidence families joined; ranked=N: symbols at least one fired on; window=: the git span the historical family read. -->
<ensemble schema="ripwire.ensemble/v1" families="4" eligible="22551" ranked="8357" no_family="14194" bar_ccx="15" bar_loc="60" bar_nest="4" bar_params="5" rcut="40" rmeasured="22551" hcut="40" hranked="4497" window="12mo" cfiles="1043" cscope="12173" lscope="22551" shown_syms="8" syms_capped="1" sho … [line truncated: 118 more bytes on this line]
<s p="src/gitmine.h:1795" n="addRootFilesToGitPathIndex" fam="4" of="4" fired="structural,lexical,confusion,historical">
<e f="structural" why="ccx=25 ev=6"/>
<e f="lexical" why="naming-wordy"/>
<e f="confusion" why="atom-embedded-crement*2"/>
<e f="historical" why="hrank=32 churn=103"/>
</s>
<s p="src/graphlegend.h:770" n="declinedSitesLegend" fam="4" of="4" fired="structural,lexical,confusion,historical">
<e f="structural" why="ccx=29 ev=2"/>
<e f="lexical" why="naming-confusable"/>
<e f="confusion" why="atom-nested-ternary*5"/>
<e f="historical" why="hrank=19 churn=219"/>
</s>
<s p="src/serialize.h:10350" n="packDeps" fam="4" of="4" fired="structural,lexical,confusion,historical">
<e f="structural" why="ccx=125 loc=343 nest=5 params=16 humps=4 deep=14 ev=5 rrank=22"/>
<e f="lexical" why="naming-confusable"/>
<e f="confusion" why="atom-nested-ternary"/>
<e f="historical" why="hrank=10 churn=486"/>
</s>
<s p="src/compactlegend.h:1894" n="payloadSubCapAttrs" fam="3" of="4" fired="structural,confusion,historical">
<e f="structural" why="ccx=45 nest=6 humps=2 deep=11"/>
<e f="confusion" why="atom-assign-as-value"/>
<e f="historical" why="hrank=12 churn=450"/>
</s>
<s p="src/compactlegend.h:2464" n="applyCompactDialectOnce" fam="3" of="4" fired="structural,confusion,historical">
<e f="structural" why="ccx=49 loc=120 nest=4 humps=1 deep=1 ev=3"/>
<e f="confusion" why="atom-nested-ternary"/>
<e f="historical" why="hrank=12 churn=450"/>
</s>
… [36 more display lines; full output is 7498 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --field-affinity`

*The cache-locality lens over every aggregate: fields READ TOGETHER but declared FAR APART (split-line / straddle findings, Chilimbi separation weight) — advice only, never a rewrite.*

**wall time: 2.74s**

`````
<!-- ripwire field-affinity schema=ripwire.field-affinity/v1: fields read together but declared far apart vs 64-byte lines: <s n= p=> structs, <pair a= b= fns= dist=>, <finding k= f= g=>. window: shown= capped= (capped=1 cut). counts_floor=1: every count is a FLOOR, never a total. root=: p= relative to it. block=64: ASSUMED cache-line bytes; all geometry (dist= wt= ln= lines= findings) is against it. model=lp64-approx: sizes/offsets are the layout verb's LP64 standard-layout MODEL, not the real ABI. weighting=fanin-floor: w= sums 1 + fan-in per co-accessing fn; a reachability proxy, not a frequency. aggregates=N: C-family structs/classes the layout model located a body for (the scanned universe). files=N: C-family files declaring at least one struct/class the modelling pass visited. fns_scanned=N: C-family functions/methods with a readable body scanned for dot/arrow member accesses. accesses=N: member-access sites tied to one aggregate field (FLOOR: bare in-method names uncounted). amb_skipped=N: access sites REFUSED, not guessed: 2+ aggregates declare that field name; in no count here. structs=N: aggregates with 1+ attributed access; the top 20 by sepcost= print (shown=/capped=). findings=N: split-line + straddle findings over ALL structs=, not just the printed rows. min_fns=2: a pair fires split-line only when co-accessed by this many distinct functions. as_loops=N: for-loops the static advance-shape pass classified corpus-wide; report-only, never ranks. as_index=/as_chase=/as_mixed=/as_unknown=: as_loops= by advance shape (chase = pointer chase). agg=: the aggregate keyword (struct, class ...). modeled=1: layout model placed the fields; 0 = affinity only, no geometry, no finding (why= says why). fields=N: fields declared (before the touched-only filter). touched=N: fields with 1+ attributed access; at most 32 f rows print. pairs=N: co-accessed field pairs in all; at most 12 pair rows print (most fns= first). sepcost=: sum over measured pairs of fns x (1 - wt); the struct ranking key. findings=N: this struct's findings, every one printed. size=/align=/lines=: modeled sizeof, alignment, cache lines spanned (modeled=1 only). acc=N: member-access sites attributed to this field (FLOOR). sz=B: the field's modeled size in bytes (absent when the model could not size it). off=/ln=: modeled byte offset and its cache line (off/64); placed=0 instead when the model refused. w=: sum of 1 + fan-in over the co-accessing functions; a static reachability proxy, never a frequency. wt=: separation weight (64 - dist)/64, 0.00 = the two can never share a line; measured=0 instead when unplaced. wt=0.00: split-line fires only when the pair can never share a 64-byte line. w=: the split-line pair's 1 + fan-in weight sum (proxy); straddle rows carry none. off=/sz=/crosses=: straddle field offset, size, and the line its last byte lands on (lines start at off/64). fanin=N: this function's caller count (the w= proxy input). touched=N: distinct fields of this struct the function touches (named in f=); at most 8 fn rows of fns= print. scope=: the function's PROFILE_SCOPE description (first 120 chars), a counter to confirm with. scopes=N: distinct PROFILE_SCOPEs among the co-accessing functions (the scope children). status=: instrumented (a scope exists to measure) or uninstrumented (no witness yet). counter=: the hardware counter to compare across the two layouts. hint=: how to add the missing instrumentation (uninstrumented only). as_stem_ambiguous=/as_stem_unowned=/as_stem_nonptr=: chase names REFUSED - 2+ owners / no owner / owner type has no pointer marker. -->
<fieldaffinity schema="ripwire.field-affinity/v1" block="64" model="lp64-approx" counts_floor="1" weighting="fanin-floor" aggregates="2669" files="548" fns_scanned="13092" accesses="14381" amb_skipped="44412" structs="1021" shown="20" capped="1" findings="572" min_fns="2" as_loops="4138" as_index="9 … [line truncated: 77 more bytes on this line]
<s n="Graph" p="src/graph.h" l="70" agg="struct" modeled="1" fields="47" touched="39" fns="156" pairs="741" sepcost="990.88" findings="105" size="1512" align="8" lines="24">
<f n="inEdges" acc="121" fns="59" sz="48" off="0" ln="0"/>
<f n="wOutDeg" acc="31" fns="27" sz="24" off="48" ln="0"/>
<f n="outVals" acc="5" fns="4" sz="24" off="120" ln="1"/>
<f n="outAnchorMiss" acc="26" fns="17" sz="24" off="192" ln="3"/>
<f n="scipDocsSeen" acc="1" fns="1" sz="8" off="216" ln="3"/>
<f n="scipEdgesPinned" acc="1" fns="1" sz="8" off="224" ln="3"/>
<f n="baseOutsideClauses" acc="10" fns="6" sz="24" off="280" ln="4"/>
<f n="rubyMainMixins" acc="3" fns="3" sz="24" off="304" ln="4"/>
<f n="ambOut" acc="26" fns="14" sz="24" off="352" ln="5"/>
<f n="unresolvedOut" acc="25" fns="13" sz="24" off="376" ln="5"/>
<f n="locPinOut" acc="10" fns="5" sz="24" off="400" ln="6"/>
<f n="unindexedFiles" acc="6" fns="6" sz="8" off="424" ln="6"/>
<f n="rubyBasesUnscoped" acc="5" fns="5" sz="8" off="432" ln="6"/>
<f n="importAdj" acc="3" fns="3" sz="48" off="440" ln="6"/>
<f n="externalCalls" acc="9" fns="5" sz="8" off="488" ln="7"/>
<f n="declinedOut" acc="19" fns="10" sz="24" off="496" ln="7"/>
<f n="inertDeclinedCalls" acc="7" fns="5" sz="8" off="520" ln="8"/>
<f n="inertDeclinedCaller" acc="3" fns="2" sz="24" off="528" ln="8"/>
<f n="declinedListOff" acc="37" fns="13" sz="24" off="552" ln="8"/>
<f n="declinedListCand" acc="17" fns="11" sz="24" off="576" ln="9"/>
<f n="declinedListCallCount" acc="15" fns="6" sz="24" off="600" ln="9"/>
<f n="declinedSiteCaller" acc="22" fns="13" sz="24" off="624" ln="9"/>
<f n="declinedSiteList" acc="18" fns="13" sz="24" off="648" ln="10"/>
<f n="declinedSiteRef" acc="20" fns="10" sz="24" off="672" ln="10"/>
<f n="declinedSiteKind" acc="5" fns="4" sz="24" off="696" ln="10"/>
<f n="declinedSiteBound" acc="2" fns="2" sz="24" off="720" ln="11"/>
<f n="gateDeclinedTarget" acc="6" fns="2" sz="24" off="744" ln="11"/>
… [1070 more display lines; full output is 99014 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --field-affinity=Symbol`

*The same lens narrowed to ONE struct — the one --layout=Symbol shows the offsets for.*

**wall time: 2.75s**

`````
<!-- ripwire field-affinity schema=ripwire.field-affinity/v1: fields read together but declared far apart vs 64-byte lines: <s n= p=> structs, <pair a= b= fns= dist=>, <finding k= f= g=>. window: shown= capped= (capped=1 cut). counts_floor=1: every count is a FLOOR, never a total. root=: p= relative to it. sym=: the struct asked for; only its own fields and pairs are reported. block=64: ASSUMED cache-line bytes; all geometry (dist= wt= ln= lines= findings) is against it. model=lp64-approx: sizes/offsets are the layout verb's LP64 standard-layout MODEL, not the real ABI. weighting=fanin-floor: w= sums 1 + fan-in per co-accessing fn; a reachability proxy, not a frequency. aggregates=N: C-family structs/classes the layout model located a body for (the scanned universe). files=N: C-family files declaring at least one struct/class the modelling pass visited. fns_scanned=N: C-family functions/methods with a readable body scanned for dot/arrow member accesses. accesses=N: member-access sites tied to one aggregate field (FLOOR: bare in-method names uncounted). amb_skipped=N: access sites REFUSED, not guessed: 2+ aggregates declare that field name; in no count here. structs=N: aggregates with 1+ attributed access; the top 20 by sepcost= print (shown=/capped=). findings=N: split-line + straddle findings over ALL structs=, not just the printed rows. min_fns=2: a pair fires split-line only when co-accessed by this many distinct functions. as_loops=N: for-loops the static advance-shape pass classified corpus-wide; report-only, never ranks. as_index=/as_chase=/as_mixed=/as_unknown=: as_loops= by advance shape (chase = pointer chase). agg=: the aggregate keyword (struct, class ...). modeled=1: layout model placed the fields; 0 = affinity only, no geometry, no finding (why= says why). fields=N: fields declared (before the touched-only filter). touched=N: fields with 1+ attributed access; at most 32 f rows print. pairs=N: co-accessed field pairs in all; at most 12 pair rows print (most fns= first). sepcost=: sum over measured pairs of fns x (1 - wt); the struct ranking key. findings=N: this struct's findings, every one printed. size=/align=/lines=: modeled sizeof, alignment, cache lines spanned (modeled=1 only). acc=N: member-access sites attributed to this field (FLOOR). sz=B: the field's modeled size in bytes (absent when the model could not size it). off=/ln=: modeled byte offset and its cache line (off/64); placed=0 instead when the model refused. w=: sum of 1 + fan-in over the co-accessing functions; a static reachability proxy, never a frequency. wt=: separation weight (64 - dist)/64, 0.00 = the two can never share a line; measured=0 instead when unplaced. fanin=N: this function's caller count (the w= proxy input). touched=N: distinct fields of this struct the function touches (named in f=); at most 8 fn rows of fns= print. scope=: the function's PROFILE_SCOPE description (first 120 chars), a counter to confirm with. scopes=N: distinct PROFILE_SCOPEs among the co-accessing functions (the scope children). status=: instrumented (a scope exists to measure) or uninstrumented (no witness yet). counter=: the hardware counter to compare across the two layouts. as_stem_ambiguous=/as_stem_unowned=/as_stem_nonptr=: chase names REFUSED - 2+ owners / no owner / owner type has no pointer marker. -->
<fieldaffinity schema="ripwire.field-affinity/v1" block="64" model="lp64-approx" counts_floor="1" weighting="fanin-floor" aggregates="2669" files="548" fns_scanned="13092" accesses="14381" amb_skipped="44412" structs="1" shown="1" capped="0" findings="0" min_fns="2" as_loops="4138" as_index="9" as_c … [line truncated: 84 more bytes on this line]
<s n="Symbol" p="src/model.h" l="817" agg="struct" modeled="1" fields="29" touched="3" fns="204" pairs="3" sepcost="5.11" findings="0" size="112" align="8" lines="2">
<f n="sigStartByte" acc="445" fns="189" sz="4" off="16" ln="0"/>
<f n="fnLocal" acc="13" fns="12" sz="1" off="62" ln="0"/>
<f n="extentSuspect" acc="17" fns="11" sz="1" off="63" ln="0"/>
<pair a="sigStartByte" b="extentSuspect" fns="4" w="4" dist="47" wt="0.27"/>
<pair a="sigStartByte" b="fnLocal" fns="3" w="3" dist="46" wt="0.28"/>
<pair a="fnLocal" b="extentSuspect" fns="1" w="1" dist="1" wt="0.98"/>
<fn n="coneDefsOf" p="src/forselfhook.h" l="1101" fanin="0" touched="2" f="sigStartByte,fnLocal"/>
<fn n="buildGraph" p="src/graph.h" l="9618" fanin="0" touched="2" f="sigStartByte,fnLocal" scope="buildGraph/8: HTTP-route edges"/>
<fn n="assignSymbols" p="src/ingest_model.h" l="374" fanin="0" touched="2" f="sigStartByte,fnLocal" scope="ingest/build-model: lex stats CSR + file signatures (B0)"/>
<fn n="markExtentSuspects" p="src/ingest_model.h" l="587" fanin="0" touched="2" f="sigStartByte,extentSuspect" scope="ingest/build-model: extent honesty (containment check)"/>
<fn n="ownerOf" p="src/memberowner.h" l="87" fanin="0" touched="2" f="fnLocal,extentSuspect"/>
<fn n="mayCarryEndLine" p="src/serialize.h" l="5034" fanin="0" touched="2" f="sigStartByte,extentSuspect"/>
<fn n="packSignatures" p="src/serialize.h" l="6129" fanin="0" touched="2" f="sigStartByte,extentSuspect"/>
<fn n="packBodies" p="src/serialize.h" l="7994" fanin="0" touched="2" f="sigStartByte,extentSuspect"/>
<validate scopes="9" status="instrumented" counter="l1d-cache-misses">
<scope n="buildGraph/2e: Java Class::method members (issue #74)"/>
<scope n="buildGraph/2h: FE-A false-edge rules"/>
<scope n="buildGraph/8: HTTP-route edges"/>
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

**wall time: 1.33s**

`````
<!-- ripwire naming-consistency schema=ripwire.naming-consistency/v1: the corpus's case-convention vote per (language, kind): <g lang= kind= style= agree= total=>, <f p= n= propose=> outliers. window: shown= total= capped= has_more= next_offset= offset= limit= (capped=1 cut; next_offset= pastes as offset=). root=: p= relative to it. component_exempt=N: PascalCase .tsx/.jsx functions (read as JSX components by extension alone), kept out of voting and flagging. groups=N: (language, kind) groups with at least one styled name. candidates=N: multi-token styled names scanned. decided=N: groups whose leading style cleared both the sample and agreement floors. flagged=N: off-convention names in decided groups (the f rows). g why=insufficient-sample|no-clear-convention: which bar a style=UNAVAILABLE group missed. -->
<naming-consistency schema="ripwire.naming-consistency/v1" groups="32" candidates="17253" decided="11" flagged="728" component_exempt="8" shown="8" capped="1" total="728" has_more="1" next_offset="8" offset="0" limit="8" root=".">
<g lang="cpp" kind="fn" style="camel" agree="9129" total="9708"/>
<g lang="cpp" kind="var" style="camel" agree="2146" total="2167"/>
<g lang="py" kind="fn" style="snake" agree="1379" total="1423"/>
<g lang="py" kind="var" style="UNAVAILABLE" why="no-clear-convention" total="519"/>
<g lang="ts" kind="fn" style="camel" agree="300" total="311"/>
<g lang="ts" kind="var" style="UNAVAILABLE" why="insufficient-sample" total="5"/>
<g lang="go" kind="fn" style="UNAVAILABLE" why="no-clear-convention" total="104"/>
<g lang="go" kind="var" style="UNAVAILABLE" why="insufficient-sample" total="13"/>
<g lang="rs" kind="fn" style="snake" agree="216" total="227"/>
<g lang="rs" kind="var" style="UNAVAILABLE" why="insufficient-sample" total="13"/>
<g lang="swift" kind="fn" style="UNAVAILABLE" why="no-clear-convention" total="50"/>
<g lang="swift" kind="var" style="UNAVAILABLE" why="insufficient-sample" total="17"/>
<g lang="objc" kind="fn" style="UNAVAILABLE" why="insufficient-sample" total="18"/>
<g lang="js" kind="fn" style="camel" agree="167" total="169"/>
<g lang="js" kind="var" style="UNAVAILABLE" why="insufficient-sample" total="3"/>
<g lang="sh" kind="fn" style="UNAVAILABLE" why="no-clear-convention" total="1528"/>
<g lang="java" kind="fn" style="camel" agree="112" total="112"/>
<g lang="java" kind="var" style="UNAVAILABLE" why="insufficient-sample" total="1"/>
<g lang="rb" kind="fn" style="snake" agree="55" total="55"/>
<g lang="rb" kind="var" style="UNAVAILABLE" why="insufficient-sample" total="17"/>
<g lang="cs" kind="fn" style="pascal" agree="39" total="39"/>
<g lang="cs" kind="var" style="UNAVAILABLE" why="insufficient-sample" total="3"/>
<g lang="c" kind="fn" style="UNAVAILABLE" why="no-clear-convention" total="500"/>
<g lang="c" kind="var" style="UNAVAILABLE" why="no-clear-convention" total="20"/>
<g lang="php" kind="fn" style="UNAVAILABLE" why="insufficient-sample" total="9"/>
<g lang="php" kind="var" style="UNAVAILABLE" why="insufficient-sample" total="1"/>
<g lang="lua" kind="fn" style="UNAVAILABLE" why="insufficient-sample" total="15"/>
<g lang="ex" kind="fn" style="snake" agree="20" total="20"/>
… [13 more display lines; full output is 4388 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --naming-calibration`

*Score the naming-* rules against this repo's own rename history: proxy=old/(old+new) per rule, 0.50 = chance; read pairs= (sample size) first.*

**wall time: 18.19s**

`````
<!-- ripwire naming-calibration schema=ripwire.naming-calibration/v1: naming lint rules scored against this repo's OWN rename history (a noisy proxy): <r n= old= new= fired= proxy=>. at=: commit+dirty+shallow. probed=0: no history to mine, nothing scored (r= says why); 1 = the git walk ran. pairs=N: labelled rename pairs that survived the join, the SAMPLE SIZE; a small one means nothing. candidates=N: raw substitutions mined from the patch stream before the join; FLOOR when truncated=1. commits=N: non-merge commits walked (the walk stops at 40000). hunks=N: diff hunks with content on both sides. wide_hunks=N: hunks DROPPED for exceeding the 24-line per-side pairing cap; never mined. drop_old_alive=N: candidates dropped: the old spelling is still an indexed name. drop_new_absent=N: candidates dropped: the new spelling is no eligible indexed symbol at HEAD. drop_ambiguous=N: candidates dropped: a name on both sides of several (split, rework, revert). drop_old_skipped=N: candidates dropped: the lens skips the old spelling, no rule could fire. scope=group-rule: the rule judges co-visible names, which one pair cannot evidence; unscored, not 0/0. o=/n=: one labelled pair's old (abandoned) and new (chosen) spelling. sup=N: distinct hunks that showed this substitution. p at=: path:line of the symbol the pair joined to, not a commit (the root at= is). old_fires=: rules that fired on the old spelling; absent when none. new_fires=: rules that fired on the new spelling; absent when none. -->
<naming-calibration schema="ripwire.naming-calibration/v1" probed="1" pairs="186" candidates="2769" commits="6445" hunks="135405" wide_hunks="1349" drop_old_alive="770" drop_new_absent="1650" drop_ambiguous="163" drop_old_skipped="0" at="0412539b9">
<r n="naming-short" old="2" new="5" fired="7" proxy="0.286"/>
<r n="naming-wordy" old="1" new="7" fired="8" proxy="0.125"/>
<r n="naming-series" scope="group-rule"/>
<r n="naming-underscore" old="0" new="0" fired="0"/>
<r n="naming-case" old="0" new="0" fired="0"/>
<r n="naming-predicate" old="0" new="0" fired="0"/>
<r n="naming-setter" old="0" new="0" fired="0"/>
<r n="naming-confusable" scope="group-rule"/>
<!-- 4 rename rows withheld: the project's own rebrand, which names a private pre-release identifier -->
<p o="ATTR" n="ATTR_RE" sup="1" at="./bench/recalleval/run_recalleval.py:84"/>
<p o="DEGRADED_PATH_ALERT" n="DISCLOSE" sup="329" at="./test/showcase_coverage_check.py:154"/>
<p o="InRepoImportCounter" n="ImportResolver" sup="1" at="./src/resolve.h:4706"/>
<p o="PACK_MAGIC" n="payload" sup="1" at="./test/legendcostcheck.sh:48"/>
<p o="RunEval" n="DriveEval" sup="2" at="./test/attribmultideffix/cpp/eval_user.cc:4"/>
<p o="RunPiece" n="DrivePiece" sup="3" at="./test/attribmultideffix/cpp/piece_user.cc:4"/>
<p o="Rust" n="Go" sup="1" at="./test/fnslotcpp/src/twin_a.cc:1" new_fires="naming-short"/>
<p o="Subtoken" n="Member" sup="1" at="./test/callformfix/csharp/Main.cs:9"/>
<p o="TTCA" n="answer" sup="1" at="./src/ifacedispatch.h:308"/>
<p o="_famBIsFamily" n="_famBKind" sup="1" at="./test/showcase_capture.py:492"/>
<p o="above" n="below" sup="1" at="./src/pathgaps.h:646"/>
<p o="answerWords" n="answerTokens" sup="1" at="./src/forfilesyms.h:235"/>
<p o="appendSubjectGraphVerb" n="appendSubjectGraphVerbBlock" sup="4" at="./src/verbs_for.h:3281"/>
<p o="atomicWriteQSnap" n="atomicWriteFile" sup="4" at="./src/quality.h:4262"/>
<p o="blobs" n="unread" sup="1" at="./src/crossref.h:727"/>
<p o="bodyXml" n="xml" sup="2" at="./src/fordocbody.h:957"/>
… [167 more display lines; full output is 16905 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --lint --naming-locals`

*The opt-in --lint modifier: naming predicates over LOCAL variable names too, C/C++ only, only inside functions already past a size/complexity gate.*

**wall time: 4.19s**

`````
<!-- ripwire lint schema=ripwire.lint/v1: AST-only checks, facts not gates: <rule name= count= shown_rows= rows_capped= count_capped=> of <f rule= p= in=>. window: shown= total= capped= has_more= next_offset= offset= limit= (capped=1 cut; next_offset= pastes as offset=). findings_capped=/rows_capped=/count_capped=: 1 = cut. counts_floor=1: every count is a FLOOR, never a total. root=: p= relative to it. findings=N: findings over the printed rules; a floor when findings_capped=1. findings_next=: the call counting the floored rules' rest (count_capped=1 rules only, 10x per-rule budget). -->
<lint schema="ripwire.lint/v1" findings="10188" shown="630" capped="1" total="10188" has_more="1" next_offset="630" offset="0" limit="0" counts_floor="1" findings_capped="1" findings_next="--lint --naming-locals --lint-select=magic-number --lint-max-per-rule=50000" naming_locals="1" root=".">
<rule name="c-style-cast" count="693" shown_rows="36" rows_capped="1"/>
<rule name="goto" count="17" shown_rows="0" rows_capped="1"/>
<rule name="do-while" count="20" shown_rows="0" rows_capped="1"/>
<rule name="unsafe-c-fn" count="0" shown_rows="0" rows_capped="0"/>
<rule name="weak-crypto" count="0" shown_rows="0" rows_capped="0"/>
<rule name="redundant-parens" count="0" shown_rows="0" rows_capped="0"/>
<rule name="suspicious-semicolon" count="0" shown_rows="0" rows_capped="0"/>
<rule name="typedef-over-using" count="49" shown_rows="0" rows_capped="1"/>
<rule name="magic-number" count="430" shown_rows="205" rows_capped="1" count_capped="1"/>
<rule name="empty-catch" count="1" shown_rows="0" rows_capped="1"/>
<rule name="self-assign" count="3" shown_rows="0" rows_capped="1"/>
<rule name="large-function" count="371" shown_rows="25" rows_capped="1"/>
<rule name="deep-nesting" count="492" shown_rows="35" rows_capped="1"/>
<rule name="inconsistent-return" count="2" shown_rows="0" rows_capped="1"/>
<rule name="unreachable-code" count="5" shown_rows="0" rows_capped="1"/>
<rule name="naming-short" count="3979" shown_rows="198" rows_capped="1"/>
<rule name="naming-wordy" count="450" shown_rows="15" rows_capped="1"/>
<rule name="naming-series" count="979" shown_rows="0" rows_capped="1"/>
<rule name="naming-underscore" count="2" shown_rows="0" rows_capped="1"/>
<rule name="naming-case" count="84" shown_rows="0" rows_capped="1"/>
<rule name="naming-predicate" count="1" shown_rows="0" rows_capped="1"/>
<rule name="naming-setter" count="3" shown_rows="0" rows_capped="1"/>
<rule name="naming-confusable" count="1056" shown_rows="28" rows_capped="1"/>
<rule name="naming-uninformative" count="0" shown_rows="0" rows_capped="0"/>
<rule name="atom-comma-operator" count="4" shown_rows="0" rows_capped="1"/>
<rule name="atom-embedded-crement" count="220" shown_rows="8" rows_capped="1"/>
<rule name="atom-assign-as-value" count="87" shown_rows="7" rows_capped="1"/>
<rule name="atom-nested-ternary" count="313" shown_rows="11" rows_capped="1"/>
… [642 more display lines; full output is 72581 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --lint-catalog`

*The built-in rule registry — one row per rule with sev=/category=/rationale/lang=/since=; no corpus needed.*

**wall time: 1.37s**

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
<rule name="naming-short" sev="info" cat="naming" lang="cpp,c,objc,py,ts,js,go,rs,swift,java,cs,rb,sh,php,lua,ex,dart,kt,gd,clj" since="v0.2.2">a 1-2 letter Function/Method/Var name — visible far beyond any tiny scope [Beniamini/Hofmeister]</rule>
<rule name="naming-wordy" sev="info" cat="naming" lang="cpp,c,objc,py,ts,js,go,rs,swift,java,cs,rb,sh,php,lua,ex,dart,kt,gd,clj" since="v0.2.2">more than 5 split tokens in one name [Butler; AlSuhaibani]</rule>
<rule name="naming-series" sev="info" cat="naming" lang="cpp,c,objc,py,ts,js,go,rs,swift,java,cs,rb,sh,php,lua,ex,dart,kt,gd,clj" since="v0.2.2">foo1/foo2/... digit-suffix siblings sharing a base name in one scope [Butler]</rule>
<rule name="naming-underscore" sev="info" cat="naming" lang="cpp,c,objc,py,ts,js,go,rs,swift,java,cs,rb,sh,php,lua,ex,dart,kt,gd,clj" since="v0.2.2">internal consecutive underscores, or a C-family reserved __x/_X form [Butler]</rule>
<rule name="naming-case" sev="info" cat="naming" lang="cpp,c,objc,py,ts,js,go,rs,swift,java,cs,rb,sh,php,lua,ex,dart,kt,gd,clj" since="v0.2.2">snake_case and camelCase mixed inside one name [Butler]</rule>
<rule name="naming-predicate" sev="info" cat="naming" lang="cpp,c,objc,py,ts,js,go,rs,swift,java,cs,rb,sh,php,lua,ex,dart,kt,gd,clj" since="v0.2.2">an is/has/can/should/was-prefixed name whose KNOWN return type is not bool-like [LAPD A2]</rule>
<rule name="naming-setter" sev="info" cat="naming" lang="cpp,c,objc,py,ts,js,go,rs,swift,java,cs,rb,sh,php,lua,ex,dart,kt,gd,clj" since="v0.2.2">a set-prefixed name whose KNOWN return type is not void-like [LAPD A3]</rule>
<rule name="naming-confusable" sev="info" cat="naming" lang="cpp,c,objc,py,ts,js,go,rs,swift,java,cs,rb,sh,php,lua,ex,dart,kt,gd,clj" since="v0.2.2">a co-visible pair within edit distance &lt;=2, reordered tokens, or a bare/digit-suffixed twin [Namesake]</rule>
<rule name="naming-uninformative" sev="info" cat="naming" lang="cpp,c,objc,py,ts,js,go,rs,swift,java,cs,rb,sh,php,lua,ex,dart,kt,gd,clj" since="v0.2.2">every split subtoken is corpus-ubiquitous (BM25 idf) on a body past the size floor — fires only at the low end [Sparck Jones 1972]</rule>
<rule name="atom-comma-operator" sev="info" cat="readability" lang="cpp,c,objc" since="v0.2.2">the comma operator inside an expression (never a for-header comma) [Gopstein FSE 2017]</rule>
<rule name="atom-embedded-crement" sev="info" cat="readability" lang="cpp,c,objc" since="v0.2.2">++/-- evaluated inside a larger expression (never a whole statement) [Gopstein FSE 2017]</rule>
<rule name="atom-assign-as-value" sev="info" cat="readability" lang="cpp,c,objc" since="v0.2.2">an assignment whose VALUE is consumed (a condition, an argument, ...) [Gopstein FSE 2017]</rule>
<rule name="atom-nested-ternary" sev="info" cat="readability" lang="cpp,c,objc" since="v0.2.2">a conditional expression inside a conditional expression [Gopstein FSE 2017]</rule>
… [12 more display lines; full output is 7800 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --legend-dict`

*The session legend dictionary the MCP server serves as ripwire://legend-dict/full — one definition per line, headed by its dictv= version; no corpus needed. =roster lists the completeness attributes it defines.*

`````
ripwire legend dictionary ripwire.dict/v1 dictv=9310a33a6cc8c16c entries=1108
<about legend="ref" dict= dictv=>: the answer's rows come first; its root keeps only task= changed= from= to=, and this LAST child carries every other root attribute unchanged (schema= included); legend="ref": a definition is sent once per session (this dictionary's core, or the first answer that ne … [line truncated: 83 more bytes on this line]
schema=ripwire.KEY/v1: the line ripwire.KEY/v1 below reads the answer's rows
window: shown= total= capped= has_more= next_offset= offset= limit= page a list (capped=1 cut; next_offset= pastes as offset=)
X_capped= (any attribute ending _capped): 1 = cut
under ref, est_tokens= and over_ceiling= price the answer with its inline legend: an upper bound
under ref, a <g n= p=> group of n <= 8 runner-less rows prints as its n single rows, each run_unknown=1
ripwire.map/v1 <r>: ranked symbol map: <f p= layer=> groups <s t= n= sc= k= amb=> rows (k= rank), <c n=> resolved callees; the header comment is data
ripwire.map-diff/v1 <r>: the ranked map anchored at at=: what the diff touched, the map's row vocabulary
ripwire.metrics/v1 <r>: the ranked map with per-symbol metrics
ripwire.around/v1 <r>: call neighbourhood of of=: depth= hops, fanout= kept per hop; absent rows lie outside that boundary
ripwire.query/v1 <r>: lexical-rank map for the query term, the map's row vocabulary
ripwire.pack-signatures/v1 <ctx>: the ranked map plus <sigs><d l= n= sc= pure=> signature rows
ripwire.pack-top-n/v1 <ctx>: the ranked map plus <src p=> bodies of the top-N symbols
ripwire.skipped/v1 <ctx>: why the index lacks a file <f p= why= bytes= limit= ext=>; indexed but unvouched <h p= why= err= err_ratio=>; <lang> census
ripwire.notes/v1 <ctx>: field notes by target: <target id= dangling=> holds <note d= sha= branch=>; the kept count comment: notes= rows, targets= <target> rows, dangling= targets matching nothing indexed (listed, surfaced nowhere)
ripwire.lego/v1 <ctx>: ONE interface/base type: <iface n= p= defs= implementors=>, its <m> method contract, every implementor
ripwire.expand/v1 <ctx>: full bodies: <bodies shown= total= capped=> of <b t= l= p= n= sibs= sibs_total= sibs_capped= inc=>; <calls><c n= l=> resolved callees
ripwire.expand-file/v1 <ctx>: the file's own text: <src p= sym=>; <s n= sc= l=/> per scoped symbol; full id = p::sc::n
ripwire.candidate-page/v1 <sigs>: budgeted-bundle candidate page: a resumable window over the ranked candidate set the bundle cuts, for task= under budget_tokens=, one tier per page, ranks global across pages
ripwire.pack-task/v1 <ctx>: one-call task bundle for task= under budget_tokens=: <sigs><d n= sc= l= p=> ranking, <far><s t= n= p=> ranked but over 1 hop out (of_top= ranked rows) > <bodies><b t= n= p= l=> with <calls><c n= l=> callees > <callers><s rel=caller|callee shared=> 1-hop from the bodies (o … [line truncated: 105 more bytes on this line]
ripwire.from-trace/v1 <ctx>: trace frames mapped to indexed symbols, innermost first; the innermost in-corpus body included
ripwire.exemplar/v1 <ctx>: the best-in-class instance of kind= for the task, chosen by role: <exemplar n= p= in= ccx= tested=>, <bodies><b> to imitate
ripwire.pack-task/v1 <ctx-partitions>: N minimally overlapping agent bundles carved along call-graph communities plus one shared core; each <bundle> wraps a <ctx>; bundle role=core|partition i= symbols= modules= bytes= tokens=: one agent's ctx, symbols= ids assigned, bytes= its size; tokens= = est_t … [line truncated: 345 more bytes on this line]
ripwire.callers/v1 <callers>: 1-hop CALLERS of of= (defs= matched, count= distinct symbols): <s t= n= p=>; hop_tested=/hop_untested=
ripwire.callees/v1 <callees>: 1-hop CALLEES of of= (defs= matched, count= distinct symbols): <s t= n= p= role= tested=>
ripwire.uses/v1 <uses>: resolvable use-sites of of=: <u role=call|macro|read|write|import|extends|type p=file:line in_id=>
ripwire.impact/v1 <impact>: transitive blast radius of of=: <s t= n= p=> reach set, <f via= p=> importers; defs= matched, reaches= their transitive callers, radius_tested= non-tests an indexed test reaches, radius_untested= the rest; importers= files that #include/import a def's file
ripwire.defs/v1 <defs>: per <name q= defs=> the parsed definitions the name binds (defs= groups; a prototype with its definition is one): <d n= t= p= sel= lang= class=source|test in=>, sel= binds that one alone in any SYM verb, in= distinct callers (a floor); source first, then in=, then path
ripwire.path/v1 <path>: one DIRECTED call path from= to to=, each <s t= n= p=> a hop; reachable=0 hops=0 when none shown
… [1038 more display lines; full output is 119333 bytes on 1068 raw line(s)]
`````

## `./build/ripwire . --lint --lint-select=cache-`

*Run ONLY one rule family; the root carries selected="K of N" so a filtered zero is never confusable with an unfiltered one.*

**wall time: 3.34s**

`````
<!-- ripwire lint schema=ripwire.lint/v1: AST-only checks, facts not gates: <rule name= count= shown_rows= rows_capped= count_capped=> of <f rule= p= in=>. window: shown= total= capped= has_more= next_offset= offset= limit= (capped=1 cut; next_offset= pastes as offset=). rows_capped=: 1 = cut. root=: p= relative to it. findings=N: findings over the printed rules; a floor when findings_capped=1. -->
<lint schema="ripwire.lint/v1" findings="879" shown="630" capped="1" total="879" has_more="1" next_offset="630" offset="0" limit="0" selected="8 of 39" select="cache-" root=".">
<rule name="cache-node-container" count="46" shown_rows="29" rows_capped="1"/>
<rule name="cache-vector-of-raw-ptr" count="139" shown_rows="116" rows_capped="1"/>
<rule name="cache-vector-of-indirect" count="272" shown_rows="190" rows_capped="1"/>
<rule name="cache-heap-alloc-in-loop" count="6" shown_rows="2" rows_capped="1"/>
<rule name="cache-pointer-chase-loop" count="8" shown_rows="1" rows_capped="1"/>
<rule name="cache-gather-subscript" count="386" shown_rows="292" rows_capped="1"/>
<rule name="cache-shared-ptr-by-value" count="21" shown_rows="0" rows_capped="1"/>
<rule name="cache-manual-prefetch" count="1" shown_rows="0" rows_capped="1"/>
<f rule="cache-vector-of-indirect" p="bench/agentloop/editsuite/fixture/matrix.cpp:3" in="Matrix">vector&lt;std::vector&lt;double&gt;&gt;</f>
<f rule="cache-gather-subscript" p="bench/bench_chase_ab.cpp:106" in="linkChain">nodes[ perm[i] ]</f>
<f rule="cache-gather-subscript" p="bench/bench_chase_ab.cpp:106" in="linkChain">nodes[ perm[ i + 1 ] ]</f>
<f rule="cache-pointer-chase-loop" p="bench/bench_chase_ab.cpp:118" in="chase">p = p-&gt;next</f>
<f rule="cache-node-container" p="bench/bench_convergence.cpp:40" in="Map">map</f>
<f rule="cache-gather-subscript" p="bench/bench_convergence.cpp:77" in="main">byName[ symN[i] ]</f>
<f rule="cache-vector-of-indirect" p="bench/bench_convergence.cpp:82" in="main">vector&lt;std::vector&lt;std::vector&lt;std::uint32_t&gt;&gt;&gt;</f>
<f rule="cache-vector-of-indirect" p="bench/bench_convergence.cpp:82" in="main">vector&lt;std::vector&lt;std::uint32_t&gt;&gt;</f>
<f rule="cache-gather-subscript" p="bench/bench_convergence.cpp:97" in="main">m[ symN[id] ]</f>
<f rule="cache-vector-of-indirect" p="bench/bench_newline_ab.cpp:279" in="main">vector&lt;std::vector&lt;double&gt;&gt;</f>
<f rule="cache-gather-subscript" p="bench/bench_ordered_map.cpp:89" in="aggregateMax">m[ in.keys[ i ] ]</f>
<f rule="cache-node-container" p="bench/bench_svector3.cpp:62" in="Map">map</f>
<f rule="cache-vector-of-indirect" p="bench/bench_svector3.cpp:85" in="main">vector&lt;std::vector&lt;std::vector&lt;std::uint32_t&gt;&gt;&gt;</f>
<f rule="cache-vector-of-indirect" p="bench/bench_svector3.cpp:85" in="main">vector&lt;std::vector&lt;std::uint32_t&gt;&gt;</f>
<f rule="cache-gather-subscript" p="bench/bench_svector3.cpp:95" in="main">m[ symN[id] ]</f>
<f rule="cache-node-container" p="bench/bench_svector_wave.cpp:94" in="Map">map</f>
<f rule="cache-gather-subscript" p="bench/bench_svector_wave.cpp:155" in="build">m[ g_pool[ g_keyOf[i] ] ]</f>
<f rule="cache-gather-subscript" p="bench/bench_svector_wave.cpp:162" in="readSize">g_pool[ g_readOf[i] ]</f>
<f rule="cache-gather-subscript" p="bench/bench_svector_wave.cpp:172" in="readIterate">g_pool[ g_readOf[i] ]</f>
<f rule="cache-gather-subscript" p="bench/bench_svector_wave.cpp:184" in="rehash">m[ g_pool[i] ]</f>
… [611 more display lines; full output is 72921 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --lint --lint-ignore=naming-,cache-`

*DROP two families, applied after selection; the raw select=/ignore= you passed rides on the root.*

**wall time: 3.46s**

`````
<!-- ripwire lint schema=ripwire.lint/v1: AST-only checks, facts not gates: <rule name= count= shown_rows= rows_capped= count_capped=> of <f rule= p= in=>. window: shown= total= capped= has_more= next_offset= offset= limit= (capped=1 cut; next_offset= pastes as offset=). findings_capped=/rows_capped=/count_capped=: 1 = cut. counts_floor=1: every count is a FLOOR, never a total. root=: p= relative to it. findings=N: findings over the printed rules; a floor when findings_capped=1. findings_next=: the call counting the floored rules' rest (count_capped=1 rules only, 10x per-rule budget). -->
<lint schema="ripwire.lint/v1" findings="2755" shown="724" capped="1" total="2755" has_more="1" next_offset="724" offset="0" limit="0" counts_floor="1" findings_capped="1" findings_next="--lint --lint-select=magic-number --lint-max-per-rule=50000" selected="22 of 39" ignore="naming-,cache-" root="." … [line truncated: 1 more bytes on this line]
<rule name="c-style-cast" count="693" shown_rows="117" rows_capped="1"/>
<rule name="goto" count="17" shown_rows="0" rows_capped="1"/>
<rule name="do-while" count="20" shown_rows="0" rows_capped="1"/>
<rule name="unsafe-c-fn" count="0" shown_rows="0" rows_capped="0"/>
<rule name="weak-crypto" count="0" shown_rows="0" rows_capped="0"/>
<rule name="redundant-parens" count="0" shown_rows="0" rows_capped="0"/>
<rule name="suspicious-semicolon" count="0" shown_rows="0" rows_capped="0"/>
<rule name="typedef-over-using" count="49" shown_rows="0" rows_capped="1"/>
<rule name="magic-number" count="430" shown_rows="403" rows_capped="1" count_capped="1"/>
<rule name="empty-catch" count="1" shown_rows="0" rows_capped="1"/>
<rule name="self-assign" count="3" shown_rows="0" rows_capped="1"/>
<rule name="large-function" count="371" shown_rows="55" rows_capped="1"/>
<rule name="deep-nesting" count="492" shown_rows="75" rows_capped="1"/>
<rule name="inconsistent-return" count="2" shown_rows="0" rows_capped="1"/>
<rule name="unreachable-code" count="5" shown_rows="0" rows_capped="1"/>
<rule name="atom-comma-operator" count="4" shown_rows="0" rows_capped="1"/>
<rule name="atom-embedded-crement" count="220" shown_rows="21" rows_capped="1"/>
<rule name="atom-assign-as-value" count="87" shown_rows="15" rows_capped="1"/>
<rule name="atom-nested-ternary" count="313" shown_rows="36" rows_capped="1"/>
<rule name="atom-implicit-predicate" count="3" shown_rows="2" rows_capped="1"/>
<rule name="atom-octal-literal" count="45" shown_rows="0" rows_capped="1"/>
<rule name="atom-reversed-subscript" count="0" shown_rows="0" rows_capped="0"/>
<f rule="magic-number" p="bench/agentloop/editsuite/fixture/geometry.cpp:7" in="area_of_triangle">0.5</f>
<f rule="magic-number" p="bench/bench_chase_ab.cpp:100" in="linkChain">1023u</f>
<f rule="large-function" p="bench/bench_chase_ab.cpp:161" in="main">main (90 lines)</f>
<f rule="magic-number" p="bench/bench_chase_ab.cpp:167" in="main">20</f>
<f rule="atom-implicit-predicate" p="bench/bench_chase_ab.cpp:234" in="main">delta &lt; 0.02 &amp;&amp; delta &gt; -0.02</f>
<f rule="magic-number" p="bench/bench_chase_ab.cpp:234" in="main">0.02</f>
… [719 more display lines; full output is 66513 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --lint --lint-select=goto --lint-max-per-rule=4`

*A rule that spends its own match budget (here 4, set BELOW the default 5000 so the floor shows on this repo): goto carries count_capped="1", its count= is a FLOOR, and the root names the call that counts the rest — findings_next= re-runs only the floored rules under a 10x budget.*

**wall time: 3.33s**

`````
<!-- ripwire lint schema=ripwire.lint/v1: AST-only checks, facts not gates: <rule name= count= shown_rows= rows_capped= count_capped=> of <f rule= p= in=>. window: shown= total= capped= has_more= next_offset= offset= limit= (capped=1 cut; next_offset= pastes as offset=). findings_capped=/rows_capped=/count_capped=: 1 = cut. counts_floor=1: every count is a FLOOR, never a total. root=: p= relative to it. findings=N: findings over the printed rules; a floor when findings_capped=1. findings_next=: the call counting the floored rules' rest (count_capped=1 rules only, 10x per-rule budget). -->
<lint schema="ripwire.lint/v1" findings="4" shown="4" capped="1" total="4" has_more="0" next_offset="4" offset="0" limit="0" counts_floor="1" findings_capped="1" findings_next="--lint --lint-select=goto --lint-max-per-rule=40" selected="1 of 39" select="goto" root=".">
<rule name="goto" count="4" shown_rows="4" rows_capped="0" count_capped="1"/>
<f rule="goto" p="src/infra/timsort.hpp:508" in="mergeLo">goto epilogue;</f>
<f rule="goto" p="src/infra/timsort.hpp:517" in="mergeLo">goto epilogue;</f>
<f rule="goto" p="src/infra/timsort.hpp:534" in="mergeLo">goto epilogue;</f>
<f rule="goto" p="src/infra/timsort.hpp:541" in="mergeLo">goto epilogue;</f>
</lint>
`````

## `./build/ripwire . --lint --lint-select=goto --lint-max-per-rule=40`

*Pasting that findings_next=: the same rule under a 10x budget counts its true total — no count_capped=, no findings_next=.*

**wall time: 3.13s**

`````
<!-- ripwire lint schema=ripwire.lint/v1: AST-only checks, facts not gates: <rule name= count= shown_rows= rows_capped= count_capped=> of <f rule= p= in=>. window: shown= capped= (capped=1 cut). rows_capped=: 1 = cut. root=: p= relative to it. findings=N: findings over the printed rules; a floor when findings_capped=1. -->
<lint schema="ripwire.lint/v1" findings="17" shown="17" capped="0" selected="1 of 39" select="goto" root=".">
<rule name="goto" count="17" shown_rows="17" rows_capped="0"/>
<f rule="goto" p="src/infra/timsort.hpp:508" in="mergeLo">goto epilogue;</f>
<f rule="goto" p="src/infra/timsort.hpp:517" in="mergeLo">goto epilogue;</f>
<f rule="goto" p="src/infra/timsort.hpp:534" in="mergeLo">goto epilogue;</f>
<f rule="goto" p="src/infra/timsort.hpp:541" in="mergeLo">goto epilogue;</f>
<f rule="goto" p="src/infra/timsort.hpp:551" in="mergeLo">goto epilogue;</f>
<f rule="goto" p="src/infra/timsort.hpp:558" in="mergeLo">goto epilogue;</f>
<f rule="goto" p="src/infra/timsort.hpp:633" in="mergeHi">goto epilogue;</f>
<f rule="goto" p="src/infra/timsort.hpp:644" in="mergeHi">goto epilogue;</f>
<f rule="goto" p="src/infra/timsort.hpp:663" in="mergeHi">goto epilogue;</f>
<f rule="goto" p="src/infra/timsort.hpp:670" in="mergeHi">goto epilogue;</f>
<f rule="goto" p="src/infra/timsort.hpp:683" in="mergeHi">goto epilogue;</f>
<f rule="goto" p="src/infra/timsort.hpp:689" in="mergeHi">goto epilogue;</f>
<f rule="goto" p="test/forbodyslotfix/src/c/cmd-find.c:101" in="cmd_find_target">goto error;</f>
<f rule="goto" p="test/forbodyslotfix/src/c/cmd-find.c:103" in="cmd_find_target">goto error;</f>
<f rule="goto" p="test/forbodyslotfix/src/c/cmd-find.c:105" in="cmd_find_target">goto error;</f>
<f rule="goto" p="test/sliceflowsensfix/disclosed.cpp:22" in="cd03">goto done;</f>
<f rule="goto" p="test/unreachablefix/dead.cpp:48" in="withGoto">goto done;</f>
</lint>
`````

## `./build/ripwire . --lint --lint-select=cach-`

*An unresolvable PREFIX refuses (exit 1) with a did-you-mean from a real edit distance (one character off cache-).*

**exit code: 1** — **wall time: 3.38s**

`````
(empty)
`````

stderr:

`````
ripwire: --lint-select: 'cach-' matches no rule or family (did you mean 'cache-'?) — see --lint-catalog for the full registry
`````

## `./build/ripwire . --lint --lint-select=nosuchfamily`

*A PREFIX with no near miss at all: the refusal points at --lint-catalog instead of guessing.*

**exit code: 1** — **wall time: 3.30s**

`````
(empty)
`````

stderr:

`````
ripwire: --lint-select: 'nosuchfamily' matches no rule or family — see --lint-catalog for the full registry
`````

## `./build/ripwire . --lint --sarif`

*The SAME findings as SARIF 2.1.0 (what github/codeql-action/upload-sarif consumes) — pure re-serialization, results count == the native run's.*

**wall time: 3.24s**

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
… [16711 more display lines; full output is 2372081 bytes on 1 raw line(s)]
`````

Parsed summary of the same SARIF (past the display cut):

`````
sarif 2.1.0 rules= 39 results= 8351
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

**wall time: 13.59s**

`````
<!-- ripwire dmm schema=ripwire.dmm/v1: Delta Maintainability Model base=→target=: dmm= good/(good+bad) units by size_metric=; <p k= dmm= good= bad= d_low= d_high=>. at=: commit+dirty+shallow. available=0: no score at all (dmm=UNAVAILABLE, reason= says why); never read as 1.000 or 0.000. combine=pooled: root dmm= is summed good over summed good+bad of the 3 properties (ripwire's own). low_loc=/low_cx=/low_params=: a unit is LOW risk at or under these lines / cyclomatic / params. base_units=/base_volume=/target_units=/target_volume=: units with a body and their line span per side. reason=: why no score (no unit's size, complexity or params moved; a tree failed to parse ...). -->
<dmm schema="ripwire.dmm/v1" base="0412539b91400096c84f50d5dd9714966449ea6e" target="working-tree" at="0412539b9" available="0" combine="pooled" size_metric="physical-loc" low_loc="15" low_cx="5" low_params="2" dmm="UNAVAILABLE" good="0" bad="0" base_units="22551" base_volume="301968" target_units=" … [line truncated: 147 more bytes on this line]
<p k="size" dmm="UNAVAILABLE" good="0" bad="0" d_low="0" d_high="0"/>
<p k="complexity" dmm="UNAVAILABLE" good="0" bad="0" d_low="0" d_high="0"/>
<p k="interfacing" dmm="UNAVAILABLE" good="0" bad="0" d_low="0" d_high="0"/>
</dmm>
`````

## `./build/ripwire . --dmm=HEAD`

*The per-commit scalar: HEAD vs its first parent, with the three separately actionable sub-scores.*

**wall time: 22.97s**

`````
<!-- ripwire dmm schema=ripwire.dmm/v1: Delta Maintainability Model base=→target=: dmm= good/(good+bad) units by size_metric=; <p k= dmm= good= bad= d_low= d_high=>. at=: commit+dirty+shallow. available=0: no score at all (dmm=UNAVAILABLE, reason= says why); never read as 1.000 or 0.000. combine=pooled: root dmm= is summed good over summed good+bad of the 3 properties (ripwire's own). low_loc=/low_cx=/low_params=: a unit is LOW risk at or under these lines / cyclomatic / params. base_units=/base_volume=/target_units=/target_volume=: units with a body and their line span per side. reason=: why no score (no unit's size, complexity or params moved; a tree failed to parse ...). -->
<dmm schema="ripwire.dmm/v1" base="d1f3ba3d56a71c2184186f649aa546b578bb8196" target="0412539b91400096c84f50d5dd9714966449ea6e" at="0412539b9" available="0" combine="pooled" size_metric="physical-loc" low_loc="15" low_cx="5" low_params="2" dmm="UNAVAILABLE" good="0" bad="0" base_units="22551" base_vo … [line truncated: 175 more bytes on this line]
<p k="size" dmm="UNAVAILABLE" good="0" bad="0" d_low="0" d_high="0"/>
<p k="complexity" dmm="UNAVAILABLE" good="0" bad="0" d_low="0" d_high="0"/>
<p k="interfacing" dmm="UNAVAILABLE" good="0" bad="0" d_low="0" d_high="0"/>
</dmm>
`````

## `./build/ripwire . --dmm=HEAD~3..HEAD`

*The range form: tree HEAD vs tree HEAD~3.*

**wall time: 26.21s**

`````
<!-- ripwire dmm schema=ripwire.dmm/v1: Delta Maintainability Model base=→target=: dmm= good/(good+bad) units by size_metric=; <p k= dmm= good= bad= d_low= d_high=>. at=: commit+dirty+shallow. available=0: no score at all (dmm=UNAVAILABLE, reason= says why); never read as 1.000 or 0.000. combine=pooled: root dmm= is summed good over summed good+bad of the 3 properties (ripwire's own). low_loc=/low_cx=/low_params=: a unit is LOW risk at or under these lines / cyclomatic / params. base_units=/base_volume=/target_units=/target_volume=: units with a body and their line span per side. -->
<dmm schema="ripwire.dmm/v1" base="53992e3c3cdf2509cac6d3921b34cd6fc3eea32a" target="0412539b91400096c84f50d5dd9714966449ea6e" at="0412539b9" available="1" combine="pooled" size_metric="physical-loc" low_loc="15" low_cx="5" low_params="2" dmm="0.302" good="1275" bad="2952" base_units="22471" base_vo … [line truncated: 58 more bytes on this line]
<p k="size" dmm="0.160" good="225" bad="1184" d_low="225" d_high="1184"/>
<p k="complexity" dmm="0.241" good="339" bad="1070" d_low="339" d_high="1070"/>
<p k="interfacing" dmm="0.505" good="711" bad="698" d_low="711" d_high="698"/>
</dmm>
`````

## `./build/ripwire . --cochange --cochange-groups`

*Modularity-violation GROUPS instead of pairs: "X co-changes with {A,B,C}, none of which it depends on" — a greedy cover, disclosed as greedy.*

**wall time: 5.31s**

`````
<!-- ripwire cochange schema=ripwire.cochange/v1: files that change together in git: <pair a= b= together= deg= conf_ab= conf_ba= surprising=>, or for of= <f p= together= conf_rev=>. window: shown= total= capped= has_more= next_offset= offset= limit= (capped=1 cut; next_offset= pastes as offset=). no_file_edges=LANGS: this build resolves almost none of these languages' imports to files (Go only across go.mod replace); counts over them (ca/ce and violations= of the arch verb) are floors over the resolved edges only, and a coupling number absent beside it is unknown, not zero. unknown_pairs=N: pairs left out of groups= because surprising= is unknown for them, not 0; drop the cochange-groups flag to list them. at=: commit+dirty+shallow. root=: p= relative to it. sub_windows=N: equal-commit-count slices of window=; the denominator of recur=. recur=K: slices of sub_windows= the pair co-changed in; 1 = one burst, not a standing coupling. no_file_edges=LANGS: with unknown_pairs=N, pairs whose side imports are almost never resolved to files and none links them are in no group; groups= may be low. -->
<cochange schema="ripwire.cochange/v1" groups="143" pairs_covered="1199" cover="greedy" window="18mo@HEAD" sub_windows="3" no_file_edges="java" unknown_pairs="1" shown="30" capped="1" total="143" has_more="1" next_offset="30" offset="0" limit="0" root="." at="0412539b9">
<group core="src/cli.h" partners="81">
<f p="src/abicheck.h" together="3" recur="2" conf_core="0.01"/>
<f p="src/arch.h" together="7" recur="3" conf_core="0.01"/>
<f p="src/clones.h" together="6" recur="2" conf_core="0.01"/>
<f p="src/codexdoctor.h" together="3" recur="2" conf_core="0.01"/>
<f p="src/columnar.h" together="3" recur="2" conf_core="0.01"/>
<f p="src/commentcoherence.h" together="3" recur="1" conf_core="0.01"/>
<f p="src/compactlegend.h" together="125" recur="3" conf_core="0.22"/>
<f p="src/contextratio.h" together="4" recur="1" conf_core="0.01"/>
<f p="src/countfloor.h" together="3" recur="1" conf_core="0.01"/>
<f p="src/crossref.h" together="21" recur="3" conf_core="0.04"/>
<f p="src/darkflags.h" together="4" recur="2" conf_core="0.01"/>
<f p="src/didyoumean.h" together="3" recur="1" conf_core="0.01"/>
<f p="src/dmm.h" together="4" recur="1" conf_core="0.01"/>
<f p="src/docparse.h" together="4" recur="1" conf_core="0.01"/>
<f p="src/editcheck.h" together="11" recur="2" conf_core="0.02"/>
<f p="src/editplan.h" together="9" recur="2" conf_core="0.02"/>
<f p="src/editpreview.h" together="6" recur="2" conf_core="0.01"/>
<f p="src/ensemble.h" together="7" recur="2" conf_core="0.01"/>
<f p="src/eval.h" together="3" recur="1" conf_core="0.01"/>
<f p="src/filter.h" together="4" recur="1" conf_core="0.01"/>
<f p="src/flipimpact.h" together="4" recur="2" conf_core="0.01"/>
<f p="src/gitcmd.h" together="3" recur="2" conf_core="0.01"/>
<f p="src/githarden.h" together="5" recur="3" conf_core="0.01"/>
<f p="src/gitmine.h" together="13" recur="3" conf_core="0.02"/>
<f p="src/graph.h" together="59" recur="3" conf_core="0.11"/>
<f p="src/graphlegend.h" together="56" recur="3" conf_core="0.10"/>
<f p="src/handoff.h" together="6" recur="2" conf_core="0.01"/>
… [931 more display lines; full output is 62571 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --cochange --cochange-recur=2`

*Only pairs whose co-change RECURS in 2+ sub-windows of the mined window (sub_windows= is the denominator) — a one-off sprint stops reading like a structural defect.*

**wall time: 8.60s**

`````
<!-- ripwire cochange schema=ripwire.cochange/v1: files that change together in git: <pair a= b= together= deg= conf_ab= conf_ba= surprising=>, or for of= <f p= together= conf_rev=>. window: shown= total= capped= has_more= next_offset= offset= limit= (capped=1 cut; next_offset= pastes as offset=). at=: commit+dirty+shallow. root=: p= relative to it. pairs=N: file pairs with 3+ shared commits in window= (after min_recur), surprising or not. sub_windows=N: equal-commit-count slices of window=; the denominator of recur=. driver=a|b: the side whose changes best imply the other's, look there first; absent on a tie. recur=K: slices of sub_windows= the pair co-changed in; 1 = one burst, not a standing coupling. -->
<cochange schema="ripwire.cochange/v1" pairs="3399" window="18mo@HEAD" sub_windows="3" min_recur="2" shown="30" capped="1" total="3399" has_more="1" next_offset="30" offset="0" limit="0" root="." at="0412539b9">
<pair a="test/headsnapcachecheck.sh" b="test/qsnapcachecheck.sh" together="5" deg="1.00" conf_ab="1.00" conf_ba="1.00" recur="3" surprising="1"/>
<pair a="test/luacheck.sh" b="test/phpcheck.sh" together="3" deg="1.00" conf_ab="0.75" conf_ba="1.00" driver="b" recur="2" surprising="1"/>
<pair a="src/binstale.h" b="src/crossref.h" together="3" deg="1.00" conf_ab="1.00" conf_ba="0.04" driver="a" recur="2" surprising="1"/>
<pair a="test/gatecountcheck.sh" b="test/manifestcheck.sh" together="3" deg="1.00" conf_ab="1.00" conf_ba="0.23" driver="a" recur="2" surprising="1"/>
<pair a="test/pincensuscheck.sh" b="test/scipjoincheck.sh" together="3" deg="1.00" conf_ab="0.38" conf_ba="1.00" driver="b" recur="2" surprising="1"/>
<pair a="test/mcpslicecheck.sh" b="test/mcpverbscheck.sh" together="3" deg="1.00" conf_ab="1.00" conf_ba="0.16" driver="a" recur="2" surprising="1"/>
<pair a="test/gatecountcheck.sh" b="test/regression.sh" together="3" deg="1.00" conf_ab="1.00" conf_ba="0.00" driver="a" recur="2" surprising="1"/>
<pair a="test/elixircheck.sh" b="test/elixirsemanticcheck.sh" together="3" deg="1.00" conf_ab="0.13" conf_ba="1.00" driver="b" recur="3" surprising="1"/>
<pair a="test/cachesplitcheck.sh" b="test/evictioncheck.sh" together="3" deg="1.00" conf_ab="1.00" conf_ba="0.23" driver="a" recur="2" surprising="1"/>
<pair a="src/cli.h" b="src/sarif.h" together="6" deg="0.86" conf_ab="0.01" conf_ba="0.86" driver="b" recur="2" surprising="1"/>
<pair a="src/ingest_model.h" b="src/model.h" together="50" deg="0.83" conf_ab="0.83" conf_ba="0.16" driver="a" recur="3" surprising="1"/>
<pair a="hooks/ripwire-claude-route.sh" b="hooks/ripwire-codex-route.sh" together="20" deg="0.83" conf_ab="0.83" conf_ba="0.83" recur="3" surprising="1"/>
<pair a="src/serialize.h" b="src/verify.h" together="5" deg="0.83" conf_ab="0.01" conf_ba="0.83" driver="b" recur="2" surprising="1"/>
<pair a="test/anchorcheck.sh" b="test/routecheck.sh" together="14" deg="0.82" conf_ab="0.82" conf_ba="0.74" driver="a" recur="3" surprising="1"/>
<pair a="test/headsnapcachecheck.sh" b="test/qsnapprefetchcheck.sh" together="4" deg="0.80" conf_ab="0.80" conf_ba="0.67" driver="a" recur="2" surprising="1"/>
<pair a="test/qsnapcachecheck.sh" b="test/qsnapprefetchcheck.sh" together="4" deg="0.80" conf_ab="0.80" conf_ba="0.67" driver="a" recur="2" surprising="1"/>
<pair a="src/graph.h" b="src/ingest_jsimports.h" together="11" deg="0.79" conf_ab="0.02" conf_ba="0.79" driver="b" recur="3" surprising="1"/>
<pair a="src/graph.h" b="src/ingest_ruby.h" together="7" deg="0.78" conf_ab="0.01" conf_ba="0.78" driver="b" recur="2" surprising="1"/>
<pair a="src/ingest_cache.h" b="src/ingest_ruby.h" together="7" deg="0.78" conf_ab="0.02" conf_ba="0.78" driver="b" recur="2" surprising="1"/>
<pair a="src/ingest_ruby.h" b="src/model.h" together="7" deg="0.78" conf_ab="0.78" conf_ba="0.02" driver="a" recur="2" surprising="1"/>
<pair a="src/ingest_cache.h" b="src/quality.h" together="263" deg="0.77" conf_ab="0.77" conf_ba="0.47" driver="a" recur="3" surprising="1"/>
<pair a="src/callhierarchy.h" b="src/verbs_navigate.h" together="33" deg="0.75" conf_ab="0.75" conf_ba="0.11" driver="a" recur="3" surprising="1"/>
<pair a="src/gitmine.h" b="src/historyread.h" together="6" deg="0.75" conf_ab="0.07" conf_ba="0.75" driver="b" recur="2" surprising="1"/>
<pair a="test/tracecheck.sh" b="test/w3fixbudgetcheck.sh" together="3" deg="0.75" conf_ab="0.75" conf_ba="0.75" recur="2" surprising="1"/>
<pair a="test/estchargecheck.sh" b="test/w3fixbudgetcheck.sh" together="3" deg="0.75" conf_ab="0.05" conf_ba="0.75" driver="b" recur="2" surprising="1"/>
<pair a="test/dartcheck.sh" b="test/elixircheck.sh" together="3" deg="0.75" conf_ab="0.75" conf_ba="0.13" driver="a" recur="2" surprising="1"/>
<pair a="test/estchargecheck.sh" b="test/tracecheck.sh" together="3" deg="0.75" conf_ab="0.05" conf_ba="0.75" driver="b" recur="2" surprising="1"/>
<pair a="src/abicheck.h" b="src/landingplan.h" together="3" deg="0.75" conf_ab="0.27" conf_ba="0.75" driver="b" recur="2" surprising="1"/>
<pair a="hooks/ripwire-claude-route.sh" b="test/routehookcheck.sh" together="14" deg="0.74" conf_ab="0.58" conf_ba="0.74" driver="b" recur="2" surprising="1"/>
<pair a="src/quality.h" b="src/tsprobe.cpp" together="8" deg="0.73" conf_ab="0.01" conf_ba="0.73" driver="b" recur="3" surprising="1"/>
</cochange>
`````

## `./build/ripwire . --html=<scratch>/aux/map2.html --color-by=community`

*The HTML graph with the initial colour mode set to community (the page embeds all five modes and keeps a live selector).*

**wall time: 6.00s**

`````
(empty)
`````

Artifact written:

`````
  155504 <scratch>/aux/map2.html
`````

## `./build/ripwire . --index-out=<scratch>/aux/ci_index`

*CI generate-and-exit: cold-parse and write BOTH committable cache families (lean + rich), no map on stdout.*

**wall time: 11.54s**

`````
(empty)
`````

stderr:

`````
ripwire: --index-out wrote <scratch>/aux/ci_index.lean.ripwirecache (36383482 bytes, lean family)
ripwire: --index-out wrote <scratch>/aux/ci_index.rich.ripwirecache (73359191 bytes, rich family)
`````

Artifact written:

`````
 36383482 <scratch>/aux/ci_index.lean.ripwirecache
 73359191 <scratch>/aux/ci_index.rich.ripwirecache
 109742673 total
`````

## `./build/ripwire . --cache=<scratch>/aux/ci_index.lean.ripwirecache --top-k=3`

*Consume the lean artifact in a PR job: restore-equivalence, never blob-byte-identity.*

**wall time: 2.24s**

`````
<!-- ripwire map schema=ripwire.map/v1: ranked symbol map: <f p= layer=> groups <s t= n= sc= k= amb=> rows (k= rank), <c n=> resolved callees; the header comment is data. est_tokens=: price as emitted (an upper bound under compact). root=: p= relative to it. pr_iters=N: PageRank iterations. <inv listed= unlisted=>: files the ranked rows show / do not (sum = files=), each named or counted below. <entry p= n=>: a program entry by its language's convention (C/Go/Rust main, Java/C# static main, a script main its module scope calls, __main__.py), callees as c rows; manifest entries not read. <ls p= n= f=>: n= unshown files under dir p=; f= names its code files, the rest (tests, docs, config, test/doc/example dirs) counted. declined=K: K call sites without edges, including inert Elixir quote sites after unquote/unquote_splicing re-entry. external=K: K calls proven outside the tree, no edge. locality_pinned=K: K calls pinned by locality alone (a guess). extent_suspect_syms=K: K defs failed containment, corpus-wide. macro_blanked_files=K: K files indexed from a macro-blanked re-parse. prov=scip|binding|import|split|final-segment: how that <c> edge bound (absent: one unique name); split = one arm of an amb= pick; final-segment = a qualified type matched by last name only. files=/symbols=: files and symbols indexed; edges= distinct call edges; shown= symbols printed, a merged row counting each def; ambiguous= calls split over several defs, corpus-wide; unresolved= calls with in-tree evidence and no edge (every def language-filtered or unreachable, or binding refused); order= rows by rank (important-first, important-last; (auto:fill) = flipped past a size threshold) or by path (stable). skipped_oversize=K: K files over a size ceiling, not indexed. unindexed=ext:N: N text files of that extension no grammar reads (6 extensions at most). unindexed_exts=E: E such extensions in all, the list cut. sc=: enclosing scope; the full id is p::sc::n (p= of the row or its <f>) and selectors take it. -->
<!-- t=modscope=a-file's-MODULE-SCOPE(n=<file-scope>):the-statements-outside-every-named-definition,where-a-top-level-call-and-an-anonymous-callback-body's-calls-live;a-CALLER-never-a-callee(nothing-in-the-source-can-name-it)-with-no-body-to-expand;a-file-with-no-such-call-has-no-such-row -->
<!-- t=type|alias|functype=a-Go-named-type-by-its-written-form:type=a-defined-type-whose-WRITTEN-form-is-not-a-struct/iface/func-literal(type-N-string;type-W-Pair-too,whatever-Pair-is-underneath),alias=type-A=B,functype=type-F-func(...) -->
<!-- t=alias|functype-in-C++-and-.h:alias=using-X=Y(also-templated-or-class-scope)or-namespace-L=lib(defs=X-prints-its-written-target-as-to=),functype=a-typedef-of-a-function-or-function-pointer-type(typedef-void(*F)(int));other-typedefs-read-t=struct -->
<!-- files=4497 symbols=39562 edges=38970 shown=3 est_tokens=3914 ambiguous=3456 unresolved=18664 locality_pinned=11 external=11109 declined=41448 extent_suspect_syms=12 macro_blanked_files=7 skipped_oversize=15 unindexed="txt:81,tsv:53,mod:33,jsonl:26,scm:25,expected:15" unindexed_exts=23 order=important-first -->
<r schema="ripwire.map/v1" root="." est_tokens="3914" pr_iters="38">
<f p="src/infra/nodekind.h" layer="infra">
<s t="fn" n="kindIs" sc="rw" k="0.0031">
</s>
</f>
<f p="src/ingest_metrics.h">
<s t="fn" n="nodeTextOf" k="0.0020">
</s>
</f>
<f p="src/model.h">
<s t="fn" n="relForHash" sc="rw" k="0.0020">
</s>
</f>
<inv listed="3" unlisted="4494">
<entry p="scripts/changelog_assemble.py" n="main">
<c n="repoRoot"/>
<c n="fragmentNames"/>
<c n="check"/>
<c n="assembledEntries"/>
<c n="release"/>
</entry>
<entry p="scripts/merge_resolve.py" n="main">
<c n="generator_constants"/>
<c n="git"/>
<c n="parse"/>
… [84 more display lines; full output is 9761 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --pin-census=<scratch>/aux/pin_census.tsv --top-k=3`

*Eval-only: a per-call-site census of WHICH mechanism resolved each call, and the canonical id of every surviving target.*

**wall time: 3.03s**

`````
<!-- ripwire map schema=ripwire.map/v1: ranked symbol map: <f p= layer=> groups <s t= n= sc= k= amb=> rows (k= rank), <c n=> resolved callees; the header comment is data. est_tokens=: price as emitted (an upper bound under compact). root=: p= relative to it. pr_iters=N: PageRank iterations. <inv listed= unlisted=>: files the ranked rows show / do not (sum = files=), each named or counted below. <entry p= n=>: a program entry by its language's convention (C/Go/Rust main, Java/C# static main, a script main its module scope calls, __main__.py), callees as c rows; manifest entries not read. <ls p= n= f=>: n= unshown files under dir p=; f= names its code files, the rest (tests, docs, config, test/doc/example dirs) counted. declined=K: K call sites without edges, including inert Elixir quote sites after unquote/unquote_splicing re-entry. external=K: K calls proven outside the tree, no edge. locality_pinned=K: K calls pinned by locality alone (a guess). extent_suspect_syms=K: K defs failed containment, corpus-wide. macro_blanked_files=K: K files indexed from a macro-blanked re-parse. prov=scip|binding|import|split|final-segment: how that <c> edge bound (absent: one unique name); split = one arm of an amb= pick; final-segment = a qualified type matched by last name only. files=/symbols=: files and symbols indexed; edges= distinct call edges; shown= symbols printed, a merged row counting each def; ambiguous= calls split over several defs, corpus-wide; unresolved= calls with in-tree evidence and no edge (every def language-filtered or unreachable, or binding refused); order= rows by rank (important-first, important-last; (auto:fill) = flipped past a size threshold) or by path (stable). skipped_oversize=K: K files over a size ceiling, not indexed. unindexed=ext:N: N text files of that extension no grammar reads (6 extensions at most). unindexed_exts=E: E such extensions in all, the list cut. sc=: enclosing scope; the full id is p::sc::n (p= of the row or its <f>) and selectors take it. -->
<!-- t=modscope=a-file's-MODULE-SCOPE(n=<file-scope>):the-statements-outside-every-named-definition,where-a-top-level-call-and-an-anonymous-callback-body's-calls-live;a-CALLER-never-a-callee(nothing-in-the-source-can-name-it)-with-no-body-to-expand;a-file-with-no-such-call-has-no-such-row -->
<!-- t=type|alias|functype=a-Go-named-type-by-its-written-form:type=a-defined-type-whose-WRITTEN-form-is-not-a-struct/iface/func-literal(type-N-string;type-W-Pair-too,whatever-Pair-is-underneath),alias=type-A=B,functype=type-F-func(...) -->
<!-- t=alias|functype-in-C++-and-.h:alias=using-X=Y(also-templated-or-class-scope)or-namespace-L=lib(defs=X-prints-its-written-target-as-to=),functype=a-typedef-of-a-function-or-function-pointer-type(typedef-void(*F)(int));other-typedefs-read-t=struct -->
<!-- files=4497 symbols=39562 edges=38970 shown=3 est_tokens=3914 ambiguous=3456 unresolved=18664 locality_pinned=11 external=11109 declined=41448 extent_suspect_syms=12 macro_blanked_files=7 skipped_oversize=15 unindexed="txt:81,tsv:53,mod:33,jsonl:26,scm:25,expected:15" unindexed_exts=23 order=important-first -->
<r schema="ripwire.map/v1" root="." est_tokens="3914" pr_iters="38">
<f p="src/infra/nodekind.h" layer="infra">
<s t="fn" n="kindIs" sc="rw" k="0.0031">
</s>
</f>
<f p="src/ingest_metrics.h">
<s t="fn" n="nodeTextOf" k="0.0020">
</s>
</f>
<f p="src/model.h">
<s t="fn" n="relForHash" sc="rw" k="0.0020">
</s>
</f>
<inv listed="3" unlisted="4494">
<entry p="scripts/changelog_assemble.py" n="main">
<c n="repoRoot"/>
<c n="fragmentNames"/>
<c n="check"/>
<c n="assembledEntries"/>
<c n="release"/>
</entry>
<entry p="scripts/merge_resolve.py" n="main">
<c n="generator_constants"/>
<c n="git"/>
<c n="parse"/>
… [84 more display lines; full output is 9761 bytes on 1 raw line(s)]
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
  163200 <scratch>/aux/pin_census.tsv
`````

## `./build/ripwire . --plan-lint=test/planlintfix/wave.md`

*The house PLAN/DESIGN format's STRUCTURE check — never semantics; exit 2 when a card or ledger row gates.*

**exit code: 2** — **wall time: 4.19s**

`````
<!-- ripwire plan-lint schema=ripwire.plan-lint/v1: structural lint of a plan document: each finding names the section and the rule. at=: commit+dirty+shallow. file=/dialect=: the plan read and whether the PLAN dialect was detected (dialect=0: nothing to lint). cards=/ledger=: card rows found / whether the doc carries a ledger (ledger_line= names its line). git=1: git was available, so the staleness read ran; stale_commits=N: a waiting card N commits behind HEAD is stale. gating=N: findings that fail the plan (exit 2); the rest are advisory. -->
<plan-lint schema="ripwire.plan-lint/v1" file="test/planlintfix/wave.md" dialect="1" cards="3" ledger="1" ledger_line="21" at="0412539b9" git="1" stale_commits="20" gating="3">
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

**exit code: 2** — **wall time: 3.62s**

`````
<!-- ripwire plan-lint schema=ripwire.plan-lint/v1: structural lint of a plan document: each finding names the section and the rule. at=: commit+dirty+shallow. file=/dialect=: the plan read and whether the PLAN dialect was detected (dialect=0: nothing to lint). cards=/ledger=: card rows found / whether the doc carries a ledger (ledger_line= names its line). git=1: git was available, so the staleness read ran; stale_commits=N: a waiting card N commits behind HEAD is stale. gating=N: findings that fail the plan (exit 2); the rest are advisory. -->
<plan-lint schema="ripwire.plan-lint/v1" file="test/planlintfix/wave_ledger.md" dialect="1" cards="4" ledger="1" ledger_line="17" at="0412539b9" git="1" stale_commits="20" gating="1">
<card id="T1" line="4" status="check" tline="6"/>
<card id="T2" line="8" status="check" tline="18" src="ledger"/>
<card id="T5" line="11" status="missing" tline="12" why="unlaunched" gating="1"/>
<card id="T7" line="14" status="check" tline="20" src="ledger"/>
</plan-lint>
`````

## `./build/ripwire . --doctor --agent=claude`

*--doctor plus a LIVE integration inspection for one agent: PATH binary, installed-skill manifest parity, hook executability, MCP wiring — read-only, fixed repair commands, never config contents; exit 1 when any check fails.*

**exit code: 1** — **wall time: 31.87s**

`````
<!-- ripwire doctor schema=ripwire.doctor/v1: setup health: <c n= ok=> checks; exit 1 when one fails. at=: commit+dirty+shallow. n=: the check's name (binary-path, grammars, cache-dir, git, tree-sitter, index-cache, layout ...). agent=: the agent named by the agent flag; its live-integration c rows follow the built-in checks. loaded=/expected=: grammars whose tags query compiled / grammars compiled in; a shortfall fails the row. dir=: the per-user cache directory scanned (TMPDIR/XDG_CACHE_HOME ladder); unwritable fails the row. blobs=N: ripwire cache blobs in dir=; the scan stops at 4096 (blobs_floor=1 then). bytes=N: total size in bytes of the blobs counted (short when truncated=1). many=1: more than 50 blobs; an eviction-sanity flag, informational, never fails the row. truncated=1: cache-dir, blob scan cut (cap or I/O error); tracked-binaries, scan SKIPPED, stale=0 unmeasured. locks=N: advisory edit-lock files under locks/; unheld ones over a day old are swept on a cache write. volatile=: this row's attributes that read LIVE machine state; a determinism diff strips them, never the row. git=0|1: git runs from PATH; 0 fails the row (churn verbs need it). repo=0|1: the root is inside a git work tree; 0 is a diagnosis, not a failure. history=0|1: the repo has at least one commit; head= prints only when it does. head=: HEAD's short sha (9 hex, the at= width). core_abi=/cpp_grammar_abi=: tree-sitter core language ABI / the C++ grammar's ABI; informational. languages=N: distinct compiled-in grammars (the grammars row's expected=). tracked=N: git ls-files count, printed even when truncated=1 (over 20000 files skips the scan). binaries=N: tracked paths that sniff as binary content. non_git=1: no git history to compare; the row passes unscanned. stale=N: tracked binaries committed before a same-dir same-stem source changed; any fails the row. cache_version=/parser_ver_lean=/parser_ver_rich=/artifact_arch=: index identity; reuse needs all four. rich_verbs=: the verbs that consume the rich artifact (rich=); every other verb reads the lean one. source=: auto (per-root blob), cache-flag (named by the cache flag) or disabled (no-cache: nothing read). lean_path=/rich_path=: the artifact files checked; one path when the cache flag named it. lean=/rich=: can THIS binary open that artifact (ok, absent, parser-version ...); format, never freshness. fsmonitor=: the checkout's core.fsmonitor at startup: unset, builtin, off, or hook (a command git runs). neutralised=1: a hook fsmonitor was overridden to false for this run; 0 when none was needed. filter_drivers=N: filter drivers the repository's own config defines; filter_scope= local|all, filter_pinned= 1 (run with an empty command) or refused. state=: layout records agree, disagree (mixed binary: rebuild clean-first), not-checked or no-records. checked=1: the cross-unit layout comparison ran; 0 = under two comparable records. units=N: translation units that registered a layout record. types=N: layout types recorded (only those registered in src/model.h); omitted on state=disagree. checks=/passed=: checks run / how many passed; exit 1 when passed= is below checks=. built_from=: the commit this binary was built from; at= is the tree HEAD now, a mismatch is normal. self=/which=: this binary's path and the one which ripwire finds on PATH; which_version= is the version line that one prints when they differ. on_path=0|1: whether a ripwire is on PATH; 0 fails the row and hint= carries the export line. same_file=1: the PATH copy is this very file (same device and inode). same_bytes=1: a different file with identical content, a copied install (ok); 0 fails the row; unknown: a file was unreadable; the row fails unverified (hint= names it). self_mtime=/self_size=/which_mtime=/which_size=: epoch mtime and byte size of each binary. hint=: the row's verdict and fix in plain text (which binary is stale, what to run). -->
<doctor schema="ripwire.doctor/v1" checks="12" passed="10" agent="claude" at="0412539b9" built_from="d1f3ba3d5">
<c n="binary-path" ok="0" self="./build/ripwire" which="<path>" on_path="1" same_file="0" same_bytes="0" self_mtime="1794517301" self_size="63188568" which_mtime="1793517843" which_size="58197960" which_version="ri … [line truncated: 512 more bytes on this line]
<c n="grammars" ok="1" loaded="27" expected="27"/>
<c n="cache-dir" ok="1" dir="<tmp>" blobs="889" bytes="2069064529" many="1" truncated="0" locks="527" volatile="blobs,blobs_floor,bytes,many,truncated,locks"/>
<c n="git" ok="1" git="1" repo="1" history="1" head="0412539b9"/>
<c n="tree-sitter" ok="1" core_abi="15" cpp_grammar_abi="14" languages="27"/>
<c n="tracked-binaries" ok="1" tracked="5207" binaries="33" non_git="0" truncated="0" stale="0"/>
<c n="index-cache" ok="1" cache_version="50" parser_ver_lean="307" parser_ver_rich="308" artifact_arch="16" rich_verbs="for,uses,metrics,exemplar,context-ratio,nonlocal-state,quality-panel,verify,eval-retrieval,eval-mined,eval-skills" source="auto" lean_path="<tmp> … [line truncated: 219 more bytes on this line]
<c n="git-config-trust" ok="1" fsmonitor="unset" neutralised="0" filter_drivers="0"/>
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

**wall time: 10.85s**

`````
ripwire situational-awareness — 1 changed file(s), 13 symbols in them
root: .
at: 0412539b9+dirty
  change_set: granularity=file changed_symbols=13 file_symbols=13 files_narrowed=0 files_file_granular=1 diff_hunks=7 diff_hunks_located=6 diff_hunks_unlocated=1 — seeds = symbols a diff -U0-vs-HEAD hunk overlaps (function/method body spans only); an unlocated hunk (module-level, deletion, rename) … [line truncated: 34 more bytes on this line]
  [1] blast radius: 318 symbols across 72 files transitively depend on these changes (showing 8 of 72 files — shown=8 total=72 capped=1 prcontext_cap=20 (--pr-context's own per-file list is cut at 20 too); next: --situ --limit=72)
        counts_floor=1 graph_ambiguous=3456 graph_unresolved=18664 graph_unindexed=286 (files no grammar in this build could read at all) (the map header's own gauges) — every count above is a FLOOR, never a total: call edges are name-based, so dynamic dispatch, callbacks and macros can be missing … [line truncated: 45 more bytes on this line]
        src/mcpverbs.h  (35 dependent symbols)
        src/verbs_for.h  (22 dependent symbols)
        src/verbs_navigate.h  (17 dependent symbols)
        src/quality.h  (15 dependent symbols)
        src/verbs_quality.h  (14 dependent symbols)
        src/graph.h  (12 dependent symbols)
        src/forfilesyms.h  (11 dependent symbols)
        src/editcheck.h  (9 dependent symbols)
  [2] tests to run (6) order=evidence: [changed] you edited it, [partner] named after a changed file, then hops asc (1 = direct); "(n): a, b" = n runner-less files sharing that evidence; a (run: …) is relative to root:
        test/verify_radix.cpp [hops=1]   (run: bash test/greptiercheck.sh)
        test/adaptivecutshapefix/adaptive_cut_shape_test.cpp [hops=2]   (run: bash test/adaptivecutshapecheck.sh)
        test/forrowfeatures_unit.cpp [hops=2]   (run: bash test/forrowfeaturescheck.sh)
        test/verify_csr.cpp [hops=2]   (run: bash test/a9disclosurecheck.sh)
        test/includeprecise_unit.cpp [hops=4]   (run: bash test/includeprecisecheck.sh)
        test/rustimport_unit.cpp [hops=4]   (run: bash test/rustimportprecisecheck.sh)
        script_gates_unmodelled=872 — test/*.sh gates never appear above: script-to-binary edges are not call edges (a path count)
  [3] co-change — usually edited with these but NOT in your diff (0) window="18mo@HEAD" commits="6983":
        (none — 6983 commits were mined and none co-edited a file outside your diff)
  next: --test-gate
`````

## `./build/ripwire . --test-gate`

*The pre-PR gate with real obligations — exit 4 when tests-to-run or untested blast radius is non-empty.*

**exit code: 4** — **wall time: 8.43s**

`````
<!-- ripwire test-gate schema=ripwire.test-gate/v1: tests <t p= changed= partner= hops= run=> + untested blast radius <u sym= p= l= ccx=>; exit 4 while either exists. window: total= has_more= next_offset= offset= limit= (capped=1 cut; next_offset= pastes as offset=). tests_capped=/untested_capped=: 1 = cut. counts_floor=1: every count is a FLOOR, never a total. graph_ambiguous=/graph_unresolved=: resolver gauge. graph_unindexed=N: N files no grammar could read (the map header's unindexed=); their calls raise neither gauge. declined_calls=K: K call sites left unbound (no evidence chose one def), in no count or row. at=: commit+dirty+shallow. root=: p= relative to it. next=: the one pasteable follow-up. impacted=N: symbols that transitively call the change (changed symbols excluded). shown_tests=/shown_untested=: t rows and u rows printed, two independent counts. script_gates_unmodelled=N: test/*.sh runners in the corpus, a path count; not call-graph modelled. run_first=N: the first N t rows have the most direct evidence (changed/partner/hops=1, else nearest hops=); not a skip list. script_gates_registered=N: shell gates test/regression.sh registers as suite members. script_gates_mapped=N: registered gates with exact dependency evidence (literal paths or RIPWIRE_TEST_DEPS). script_gates_unresolved_dynamic=N: registered gates with no mappable deps; they may cover the change unlisted. ccx_bar=N: the cognitive-complexity bar a u row's ccx= is read against. change_granularity=: how the change set seeded — symbol = only symbols a git hunk (diff -U0 vs HEAD) locates inside a function/method body; file = whole changed files (an unlocated hunk — module-level, deletion, rename — returns its file to file-granular); mixed = both. changed_symbols=/file_symbols=: the seeds the walk used vs all symbols of the changed files. files_narrowed=/files_file_granular=: changed files under each treatment. diff_hunks=/diff_hunks_located=/diff_hunks_unlocated=: the hunk tally; an unlocated hunk is WHY a file went file-granular. untested_modscope=N: <file-scope> owners excluded from untested= (#324, uncallable); still in impacted=. tests=/untested=: tests to run (t total) / impacted symbols no test reaches (u total). -->
<test-gate schema="ripwire.test-gate/v1" changed="1" impacted="318" tests="6" untested="288" untested_modscope="1" shown_tests="6" tests_capped="0" shown_untested="25" untested_capped="1" script_gates_unmodelled="872" script_gates_registered="823" script_gates_mapped="271" script_gates_unresolved_dy … [line truncated: 443 more bytes on this line]
<t p="test/verify_radix.cpp" hops="1" run="bash test/greptiercheck.sh"/>
<t p="test/adaptivecutshapefix/adaptive_cut_shape_test.cpp" hops="2" run="bash test/adaptivecutshapecheck.sh"/>
<t p="test/forrowfeatures_unit.cpp" hops="2" run="bash test/forrowfeaturescheck.sh"/>
<t p="test/verify_csr.cpp" hops="2" run="bash test/a9disclosurecheck.sh"/>
<t p="test/includeprecise_unit.cpp" hops="4" run="bash test/includeprecisecheck.sh"/>
<t p="test/rustimport_unit.cpp" hops="4" run="bash test/rustimportprecisecheck.sh"/>
<u sym="dispatchMcpLine" p="src/mcp.h" l="1146" ccx="794"/>
<u sym="runForLensPass" p="src/verbs_for.h" l="3356" ccx="691"/>
<u sym="dispatchMainBody" p="src/main.cpp" l="4438" ccx="502"/>
<u sym="runQualityDelta" p="src/verbs_quality.h" l="1757" ccx="352"/>
<u sym="runDefaultMap" p="src/main.cpp" l="1759" ccx="313"/>
<u sym="serialize" p="src/serialize.h" l="3256" ccx="310"/>
<u sym="computeDelta" p="src/quality.h" l="9567" ccx="304"/>
<u sym="runStructureText" p="src/verbs_report.h" l="3321" ccx="270"/>
<u sym="packSignatures" p="src/serialize.h" l="6129" ccx="235"/>
<u sym="packTaskBundleText" p="src/packtask.h" l="1450" ccx="226"/>
<u sym="runChangeViews" p="src/verbs_change.h" l="245" ccx="163"/>
<u sym="runBatchSub" p="src/mcpverbs.h" l="6222" ccx="142"/>
<u sym="pathBridge" p="src/pathgaps.h" l="1265" ccx="139"/>
<u sym="pathNearSink" p="src/pathgaps.h" l="779" ccx="127"/>
<u sym="packLego" p="src/serialize.h" l="10050" ccx="124"/>
<u sym="runArchViews" p="src/verbs_report.h" l="486" ccx="123"/>
<u sym="serializeJson" p="src/serialize.h" l="11332" ccx="118"/>
<u sym="packConnect" p="src/mcpverbs.h" l="4315" ccx="117"/>
<u sym="hopFacts" p="src/hoprecord.h" l="515" ccx="113"/>
<u sym="forTaskText" p="src/mcpverbs.h" l="2583" ccx="113"/>
<u sym="applyMentionBoost" p="src/mention.h" l="1254" ccx="111"/>
<u sym="pathReachingPairs" p="src/pathpairs.h" l="243" ccx="101"/>
<u sym="forCandidatePageDoc" p="src/forpage.h" l="257" ccx="99"/>
<u sym="emitGrepReport" p="src/verbs_grep.h" l="974" ccx="99"/>
<u sym="runPathServed" p="src/verbs_navigate.h" l="3003" ccx="96"/>
</test-gate>
`````

## `./build/ripwire . --quality-delta`

*Every row carries p="file:line", the gating rows are marked gating="1" and now bar= (the threshold each numeric row is judged against), and the exit-2 refusal prints a naming line on stderr; a gating row carries a pasteable next=.*

**exit code: 2** — **wall time: 46.58s**

`````
<!-- ripwire quality-delta schema=ripwire.quality-delta/v1: only what the change made WORSE vs baseline=: regressions= minor= gating=; <r kind= sym= p= was= now= gating= bar=>, <sa> acked. value-ref-excluded=N: internal functions kept off because a table, field or argument in another function or at file scope holds them (matched by name, not a proven call); a floor. at=: commit+dirty+shallow. next=: the one pasteable follow-up. stale=N: ack ledger rows whose target no longer applies (sa rows); never gating. preexisting-worse=N: regressions on symbols that existed at baseline; they gate when major. new-symbol=N: findings on NEW code; new-symbol rows never gate, except defect-shape format-arity. register-macro-excluded=N: symbols kept out of dead-code as self-registering test/bench macros; a floor. declined-call-excluded=N: symbols kept out of dead-code only because a declined call may mean them; a floor. api-new-surface=N: new PUBLIC symbols; a count, never gates, not in regressions=. renames=/rename_window_commits=: git rename pairs read over that many commits, to re-file baseline and acks. acked_by_rename=/acked_by_content=: acked= suppressions matched via git renames / an equal body hash. renames_window_truncated=1: history is deeper than the rename window, older renames unread. r surface=: the api-surface tier, new-symbol or contract-change. acked=N: findings suppressed by the ack ledger, listed as sa rows; never gating. r sev=minor: a small numeric delta, counted in minor=, never gating (absent: major). r origin=new-symbol: a finding on NEW code (absent: preexisting-worse). sa key=/why=: the stale ack's ledger hash / target-gone (names nothing now) or finding-gone (no longer fires). r members=/tokens=: a duplication row's clone group (member ids) / their shared normalized-token count. -->
<quality-delta schema="ripwire.quality-delta/v1" baseline="git-HEAD" regressions="9" minor="1" acked="0" stale="163" preexisting-worse="6" new-symbol="3" gating="5" register-macro-excluded="62" api-new-surface="2" at="0412539b9+dirty" renames="67" rename_window_commits="400" acked_by_rename="0" acke … [line truncated: 99 more bytes on this line]
<r kind="api-surface" sym="src/infra/sortutil.h::rw::sortutil::nonNegativeFloatDescKey" was="1" now="2" surface="contract-change" p="src/infra/sortutil.h:112" gating="1" next="--expand=src/infra/sortutil.h:nonNegativeFloatDescKey"/>
<r kind="complexity" sym="src/infra/sortutil.h::rw::sortutil::lessByScoreDescId" was="1" now="67" bar="15" p="src/infra/sortutil.h:52" gating="1" next="--expand=src/infra/sortutil.h:lessByScoreDescId"/>
<r kind="dead-code" sym="src/infra/sortutil.h::rw::sortutil::nonNegativeFloatAscKeyCopy" origin="new-symbol" p="src/infra/sortutil.h:122"/>
<r kind="dead-code" sym="src/infra/sortutil.h::rw::sortutil::sortScoredIdsWithOptions" origin="new-symbol" p="src/infra/sortutil.h:132"/>
<r kind="duplication" members="src/infra/sortutil.h::rw::sortutil::nonNegativeFloatAscKeyCopy | src/infra/sortutil.h::rw::sortutil::nonNegativeFloatDescKey" tokens="59" p="src/infra/sortutil.h:122" gating="1"/>
<r kind="nesting" sym="src/infra/sortutil.h::rw::sortutil::lessByScoreDescId" was="1" now="6" bar="4" p="src/infra/sortutil.h:52" gating="1" next="--expand=src/infra/sortutil.h:lessByScoreDescId"/>
<r kind="new-clone-of-reused-helper" sym="src/infra/sortutil.h::rw::sortutil::nonNegativeFloatAscKeyCopy | src/infra/sortutil.h::rw::sortutil::nonNegativeFloatDescKey" was="0" now="4" p="src/infra/sortutil.h:122" gating="1" next="--expand=src/infra/sortutil.h:nonNegativeFloatDescKey"/>
<r kind="params" sym="src/infra/sortutil.h::rw::sortutil::sortScoredIdsWithOptions" was="0" now="8" bar="5" origin="new-symbol" p="src/infra/sortutil.h:132"/>
<r kind="verbosity" sym="src/infra/sortutil.h::rw::sortutil::lessByScoreDescId" was="8" now="47" bar="60" sev="minor" p="src/infra/sortutil.h:52"/>
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
<sa kind="api-surface:new-symbol" key="25c9f0504fd376a4" why="target-gone"/>
<sa kind="api-surface:new-symbol" key="26aa7c55d54c4341" why="target-gone"/>
<sa kind="api-surface:new-symbol" key="36e39c7ab0fc1686" why="target-gone"/>
<sa kind="api-surface:new-symbol" key="4bce64bd920de0c3" why="target-gone"/>
… [145 more display lines; full output is 17957 bytes on 1 raw line(s)]
`````

stderr:

`````
ripwire: no ./.ripwire_quality_baseline — auto-comparing the working tree vs git HEAD (commit the baseline with --quality-baseline to pin it)
ripwire: --quality-delta gating: 5 preexisting-worse major finding(s); first: api-surface src/infra/sortutil.h::rw::sortutil::nonNegativeFloatDescKey at src/infra/sortutil.h:112 (was=1 now=2)
`````

## `./build/ripwire . --quality-delta --legend=full`

*The same gating report under --legend=full — same rows, same exit 2; the default compact comment (schema="ripwire.quality-delta/v1", the shape an agent's edit loop should run) becomes ~4 KB of prose legend.*

**exit code: 2** — **wall time: 25.72s**

`````
<!-- ripwire quality-delta: only what a change made WORSE against the floor baseline= names below. Descriptive: weigh and fix the real ones, do not game the number (a wrong abstraction beats a low score). TWELVE KINDS, and kind= on every row names which one: complexity over the ccx bar, verbosity (LOC), nesting, params, duplication, dead-code, api-surface (new public contract drift), error-masking, short-horizon-churn, new-clone-of-reused-helper, placeholder (added stub/TODO), defect-shape (defect= names it). THREE independent axes, in this order: (1) acked findings are suppressed entirely (acked= counts them); (2) ORIGIN — a finding on a symbol that EXISTED at the baseline is preexisting-worse (no origin attribute), one that exists only because the code is NEW carries origin="new-symbol"; (3) MATERIALITY — a small numeric delta is sev="minor", and minor= counts them. EXIT 2 fires only on preexisting-worse AND major, or on format-arity, the gating= count; new-symbol rows never gate, except defect-shape format-arity, so exit 0 is NOT a verdict on them — nothing that existed got worse, but the new debt is yours: read them. Clone kinds are new-symbol only when EVERY member is new; short-horizon-churn is preexisting by construction. preexisting-worse= and new-symbol= partition regressions=. stale= is a FOURTH axis, never gating and never counted in regressions=: rows in the .ripwire_quality_acks ledger whose target no longer applies. api-new-surface= COUNTS the new PUBLIC symbols (never gates, not in regressions=, printed even at zero). register-macro-excluded= is a FLOOR, not a finding: symbols this run excluded from the dead-code kind because their own definition is a registered self-registering test/benchmark macro call. Never gates, never counted in regressions=, printed even at zero (zero means none excluded, not that the check did not run). A gating row's next= is the one pasteable follow-up: expand on FILE:NAME, the body to fix (a duplication row names a SET and carries none). bar= on a complexity/verbosity/nesting/params row is the threshold now= is judged against (ccx 15, loc 60, nest 4, params 5). baseline="git-HEAD" means no sidecar existed, so the working tree was auto-compared against the HEAD tree — anything already committed cannot appear. at= is the git commit (plus a dirty marker when the working tree differs) this list was computed at. The registered families are doctest/Catch2 TEST_CASE, GoogleTest TEST/TEST_F/TEST_P, Google Benchmark BENCHMARK, plus any name a .ripwire_config register_macros= line adds; each registers itself through a static initializer the call graph cannot see, so zero in-edges on one is not evidence of anything. declined-call-excluded= is a FLOOR, not a finding: symbols this run kept out of the dead-code kind only because a call the resolver declined to bind (the map's declined=) could have meant them. Never gates; absent at zero. value-ref-excluded= is a FLOOR, not a finding: symbols this run kept out of the dead-code kind only because a table, field, argument or registering decorator holds them as a VALUE (matched by name; it is not a proven call; the callers verb lists the sites; @classmethod-style wrappers do not count), the --dead-code verb's own rule. Never gates; absent at zero. IDENTITY across a rename or a move: a finding is keyed path::scope::name, which a rename would destroy, so the baseline and the .ripwire_quality_acks ledger are both re-filed into the CURRENT tree's identity before either is read, by two EXACT mechanisms — git's own rename record, and equality of a whitespace-and-name-scrubbed body hash — never a similarity heuristic. renames= is how many rename pairs were read, rename_window_commits= how deep the commit window went, acked_by_rename= and acked_by_content= how many of the acked= suppressions each mechanism is responsible for. Three appear ONLY when true, so an absent one is not a silent no: renames_window_truncated= (history is deeper than the window), renames_truncated= (the pair cap was hit), renames_ambiguous= (an ancestor two current symbols both claim — refused rather than guessed). ORIGIN reads the re-filed baseline too, so a regression carried in with a rename is judged preexisting-worse and GATES instead of slipping through as new-symbol. FLOORS, stated because silence here would read as a guarantee: the two clone kinds key on a member-SET hash and are NOT re-filed, so a clone ack still dies on a rename; ORIGIN follows the rename record but never content, because the baseline stores no content id at all; and a move git recorded no rename for still reads as new-symbol. Each sa row carries key= (the ack identity as stored) and why=, which is target-gone (the key names no symbol or group any more) or finding-gone (the target survived, this kind just does not fire on it). sym= and p=path:line name WHICH ack it is, and are present exactly when the key still names a live symbol: on every finding-gone row, on none of the target-gone rows (there is nothing left to name), and on neither clone kind — a clone key hashes a member SET that no single symbol carries, so those rows are unnameable by construction rather than guessed at. Hygiene disclosure only — the ledger file is never auto-edited. ROWS: sym= is the canonical id the finding regressed on; was= and now= carry the before/after value for the numeric kinds; p="path:line" is the locator (root-relative; the first-sorting member for the clone kinds; omitted, never faked, when none resolves). churn= and surface= are per-kind classification facets (short-horizon-churn's self/ambient split; api-surface's new-symbol/contract-change tier). churn= facets never gate alone: the kind gates only on 2+ COMMITTED in-window rewrites of the edited lines. Every row the header's gating= counter counts also carries a gating attribute set to 1 — marked positively, never by the ABSENCE of sev or origin. CLONE ROWS name the whole group rather than one symbol: members= is the member list and tokens= its shared normalized-token count (the same per-group pair the clones verb reports). idiom= names a RECOGNIZED BODY SHAPE every member spells, out of a closed set of three (threshold-ladder, switch-name-table, builder-chain). idiom= alone changes nothing; a group that ALSO shares no non-keyword identifier between any two members, sits in pairwise-distinct enclosing contexts, and stays under 80 normalized tokens is an idiom COLLISION rather than a copy, and is reported minor instead of gating. Break any one of those and it gates as before, idiom= and all: two bucketing ladders over the SAME enum are a copy. The shape is read off the body's token stream and not a parse tree, so a macro-assembled body classifies as whatever its raw tokens spell — the name is printed so the call can be overruled by reading. -->
<quality-delta baseline="git-HEAD" regressions="9" minor="1" acked="0" stale="163" preexisting-worse="6" new-symbol="3" gating="5" register-macro-excluded="62" api-new-surface="2" at="0412539b9+dirty" renames="67" rename_window_commits="400" acked_by_rename="0" acked_by_content="0" renames_window_tr … [line truncated: 65 more bytes on this line]
<r kind="api-surface" sym="src/infra/sortutil.h::rw::sortutil::nonNegativeFloatDescKey" was="1" now="2" surface="contract-change" p="src/infra/sortutil.h:112" gating="1" next="--expand=src/infra/sortutil.h:nonNegativeFloatDescKey"/>
<r kind="complexity" sym="src/infra/sortutil.h::rw::sortutil::lessByScoreDescId" was="1" now="67" bar="15" p="src/infra/sortutil.h:52" gating="1" next="--expand=src/infra/sortutil.h:lessByScoreDescId"/>
<r kind="dead-code" sym="src/infra/sortutil.h::rw::sortutil::nonNegativeFloatAscKeyCopy" origin="new-symbol" p="src/infra/sortutil.h:122"/>
<r kind="dead-code" sym="src/infra/sortutil.h::rw::sortutil::sortScoredIdsWithOptions" origin="new-symbol" p="src/infra/sortutil.h:132"/>
<r kind="duplication" members="src/infra/sortutil.h::rw::sortutil::nonNegativeFloatAscKeyCopy | src/infra/sortutil.h::rw::sortutil::nonNegativeFloatDescKey" tokens="59" p="src/infra/sortutil.h:122" gating="1"/>
<r kind="nesting" sym="src/infra/sortutil.h::rw::sortutil::lessByScoreDescId" was="1" now="6" bar="4" p="src/infra/sortutil.h:52" gating="1" next="--expand=src/infra/sortutil.h:lessByScoreDescId"/>
<r kind="new-clone-of-reused-helper" sym="src/infra/sortutil.h::rw::sortutil::nonNegativeFloatAscKeyCopy | src/infra/sortutil.h::rw::sortutil::nonNegativeFloatDescKey" was="0" now="4" p="src/infra/sortutil.h:122" gating="1" next="--expand=src/infra/sortutil.h:nonNegativeFloatDescKey"/>
<r kind="params" sym="src/infra/sortutil.h::rw::sortutil::sortScoredIdsWithOptions" was="0" now="8" bar="5" origin="new-symbol" p="src/infra/sortutil.h:132"/>
<r kind="verbosity" sym="src/infra/sortutil.h::rw::sortutil::lessByScoreDescId" was="8" now="47" bar="60" sev="minor" p="src/infra/sortutil.h:52"/>
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
<sa kind="api-surface:new-symbol" key="25c9f0504fd376a4" why="target-gone"/>
<sa kind="api-surface:new-symbol" key="26aa7c55d54c4341" why="target-gone"/>
<sa kind="api-surface:new-symbol" key="36e39c7ab0fc1686" why="target-gone"/>
<sa kind="api-surface:new-symbol" key="4bce64bd920de0c3" why="target-gone"/>
… [145 more display lines; full output is 22949 bytes on 1 raw line(s)]
`````

stderr:

`````
ripwire: no ./.ripwire_quality_baseline — auto-comparing the working tree vs git HEAD (commit the baseline with --quality-baseline to pin it)
ripwire: --quality-delta gating: 5 preexisting-worse major finding(s); first: api-surface src/infra/sortutil.h::rw::sortutil::nonNegativeFloatDescKey at src/infra/sortutil.h:112 (was=1 now=2)
`````

## `./build/ripwire . --quality-delta --json`

*The same findings as JSON (one of the CI/scripting verbs --json supports) — same exit 2 as the XML form.*

**exit code: 2** — **wall time: 20.58s**

`````
{"baseline":"git-HEAD","regressions":9,"minor":1,"acked":0,"stale":163,"preexisting-worse":6,"new-symbol":3,"gating":5,"register-macro-excluded":62,"api-new-surface":2,"at":"0412539b9+dirty","renames":67,"rename_window_commits":400,"acked_by_rename":0,"acked_by_content":0,"renames_window_truncated": … [line truncated: 240 more bytes on this line]
{"kind":"complexity","sym":"src/infra/sortutil.h::rw::sortutil::lessByScoreDescId","was":1,"now":67,"p":"src/infra/sortutil.h:52","gating":true},
{"kind":"dead-code","sym":"src/infra/sortutil.h::rw::sortutil::nonNegativeFloatAscKeyCopy","p":"src/infra/sortutil.h:122","origin":"new-symbol"},
{"kind":"dead-code","sym":"src/infra/sortutil.h::rw::sortutil::sortScoredIdsWithOptions","p":"src/infra/sortutil.h:132","origin":"new-symbol"},
{"kind":"duplication","members":"src/infra/sortutil.h::rw::sortutil::nonNegativeFloatAscKeyCopy | src/infra/sortutil.h::rw::sortutil::nonNegativeFloatDescKey","tokens":59,"p":"src/infra/sortutil.h:122","gating":true},
{"kind":"nesting","sym":"src/infra/sortutil.h::rw::sortutil::lessByScoreDescId","was":1,"now":6,"p":"src/infra/sortutil.h:52","gating":true},
{"kind":"new-clone-of-reused-helper","sym":"src/infra/sortutil.h::rw::sortutil::nonNegativeFloatAscKeyCopy | src/infra/sortutil.h::rw::sortutil::nonNegativeFloatDescKey","was":0,"now":4,"p":"src/infra/sortutil.h:122","gating":true},
{"kind":"params","sym":"src/infra/sortutil.h::rw::sortutil::sortScoredIdsWithOptions","was":0,"now":8,"p":"src/infra/sortutil.h:132","origin":"new-symbol"},
{"kind":"verbosity","sym":"src/infra/sortutil.h::rw::sortutil::lessByScoreDescId","was":8,"now":47,"p":"src/infra/sortutil.h:52","sev":"minor"}],
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
{"kind":"api-surface:new-symbol","key":"25c9f0504fd376a4","why":"target-gone"},
{"kind":"api-surface:new-symbol","key":"26aa7c55d54c4341","why":"target-gone"},
{"kind":"api-surface:new-symbol","key":"36e39c7ab0fc1686","why":"target-gone"},
{"kind":"api-surface:new-symbol","key":"4bce64bd920de0c3","why":"target-gone"},
{"kind":"api-surface:new-symbol","key":"61f0e361ef7dee27","why":"target-gone"},
{"kind":"api-surface:new-symbol","key":"79625906f9f71ad0","why":"target-gone"},
… [142 more display lines; full output is 16559 bytes on 1 raw line(s)]
`````

stderr:

`````
ripwire: no ./.ripwire_quality_baseline — auto-comparing the working tree vs git HEAD (commit the baseline with --quality-baseline to pin it)
ripwire: --quality-delta gating: 5 preexisting-worse major finding(s); first: api-surface src/infra/sortutil.h::rw::sortutil::nonNegativeFloatDescKey at src/infra/sortutil.h:112 (was=1 now=2)
`````

## `./build/ripwire . --quality-delta --quality-ack --ack-only=zzznope`

*NEW FLAG: --ack-only matching nothing REFUSES rather than falling back to acking everything.*

**exit code: 1** — **wall time: 18.39s**

`````
(empty)
`````

stderr:

`````
ripwire: no ./.ripwire_quality_baseline — auto-comparing the working tree vs git HEAD (commit the baseline with --quality-baseline to pin it)
ripwire: ack provenance backfill — 0 clone row(s) reconstructed from the current tree, 210 re-derived, 24 left UNVERIFIED (their group was not found here — a floor, not proof it is gone), 56 left legacy (member set not found cloning here — a floor, not proof it is gone), 1304 ineligible (no cu … [line truncated: 200 more bytes on this line]
ripwire: --ack-only=zzznope matched none of the 9 finding(s) — nothing written
`````

## `./build/ripwire . --quality-delta --quality-ack --ack-only=api-surface`

*NEW FLAG: ack only the api-surface findings — a per-finding ratchet instead of a rubber stamp.*

**wall time: 16.70s**

`````
(empty)
`````

stderr:

`````
ripwire: no ./.ripwire_quality_baseline — auto-comparing the working tree vs git HEAD (commit the baseline with --quality-baseline to pin it)
ripwire: ack provenance backfill — 0 clone row(s) reconstructed from the current tree, 210 re-derived, 24 left UNVERIFIED (their group was not found here — a floor, not proof it is gone), 56 left legacy (member set not found cloning here — a floor, not proof it is gone), 1304 ineligible (no cu … [line truncated: 200 more bytes on this line]
ripwire: acknowledged 1 of 9 finding(s) (8 left UNACKED by --ack-only, 0 already acked) → ./.ripwire_quality_acks
`````

## `./build/ripwire . --quality-delta`

*Re-run after the partial ack: acked=3, the rest still gate (exit 2).*

**exit code: 2** — **wall time: 21.39s**

`````
<!-- ripwire quality-delta schema=ripwire.quality-delta/v1: only what the change made WORSE vs baseline=: regressions= minor= gating=; <r kind= sym= p= was= now= gating= bar=>, <sa> acked. value-ref-excluded=N: internal functions kept off because a table, field or argument in another function or at file scope holds them (matched by name, not a proven call); a floor. at=: commit+dirty+shallow. next=: the one pasteable follow-up. stale=N: ack ledger rows whose target no longer applies (sa rows); never gating. preexisting-worse=N: regressions on symbols that existed at baseline; they gate when major. new-symbol=N: findings on NEW code; new-symbol rows never gate, except defect-shape format-arity. register-macro-excluded=N: symbols kept out of dead-code as self-registering test/bench macros; a floor. declined-call-excluded=N: symbols kept out of dead-code only because a declined call may mean them; a floor. api-new-surface=N: new PUBLIC symbols; a count, never gates, not in regressions=. renames=/rename_window_commits=: git rename pairs read over that many commits, to re-file baseline and acks. acked_by_rename=/acked_by_content=: acked= suppressions matched via git renames / an equal body hash. renames_window_truncated=1: history is deeper than the rename window, older renames unread. acked=N: findings suppressed by the ack ledger, listed as sa rows; never gating. r sev=minor: a small numeric delta, counted in minor=, never gating (absent: major). r origin=new-symbol: a finding on NEW code (absent: preexisting-worse). sa key=/why=: the stale ack's ledger hash / target-gone (names nothing now) or finding-gone (no longer fires). r members=/tokens=: a duplication row's clone group (member ids) / their shared normalized-token count. -->
<quality-delta schema="ripwire.quality-delta/v1" baseline="git-HEAD" regressions="8" minor="1" acked="1" stale="163" preexisting-worse="5" new-symbol="3" gating="4" register-macro-excluded="62" api-new-surface="2" at="0412539b9+dirty" renames="67" rename_window_commits="400" acked_by_rename="0" acke … [line truncated: 99 more bytes on this line]
<r kind="complexity" sym="src/infra/sortutil.h::rw::sortutil::lessByScoreDescId" was="1" now="67" bar="15" p="src/infra/sortutil.h:52" gating="1" next="--expand=src/infra/sortutil.h:lessByScoreDescId"/>
<r kind="dead-code" sym="src/infra/sortutil.h::rw::sortutil::nonNegativeFloatAscKeyCopy" origin="new-symbol" p="src/infra/sortutil.h:122"/>
<r kind="dead-code" sym="src/infra/sortutil.h::rw::sortutil::sortScoredIdsWithOptions" origin="new-symbol" p="src/infra/sortutil.h:132"/>
<r kind="duplication" members="src/infra/sortutil.h::rw::sortutil::nonNegativeFloatAscKeyCopy | src/infra/sortutil.h::rw::sortutil::nonNegativeFloatDescKey" tokens="59" p="src/infra/sortutil.h:122" gating="1"/>
<r kind="nesting" sym="src/infra/sortutil.h::rw::sortutil::lessByScoreDescId" was="1" now="6" bar="4" p="src/infra/sortutil.h:52" gating="1" next="--expand=src/infra/sortutil.h:lessByScoreDescId"/>
<r kind="new-clone-of-reused-helper" sym="src/infra/sortutil.h::rw::sortutil::nonNegativeFloatAscKeyCopy | src/infra/sortutil.h::rw::sortutil::nonNegativeFloatDescKey" was="0" now="4" p="src/infra/sortutil.h:122" gating="1" next="--expand=src/infra/sortutil.h:nonNegativeFloatDescKey"/>
<r kind="params" sym="src/infra/sortutil.h::rw::sortutil::sortScoredIdsWithOptions" was="0" now="8" bar="5" origin="new-symbol" p="src/infra/sortutil.h:132"/>
<r kind="verbosity" sym="src/infra/sortutil.h::rw::sortutil::lessByScoreDescId" was="8" now="47" bar="60" sev="minor" p="src/infra/sortutil.h:52"/>
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
<sa kind="api-surface:new-symbol" key="25c9f0504fd376a4" why="target-gone"/>
<sa kind="api-surface:new-symbol" key="26aa7c55d54c4341" why="target-gone"/>
<sa kind="api-surface:new-symbol" key="36e39c7ab0fc1686" why="target-gone"/>
<sa kind="api-surface:new-symbol" key="4bce64bd920de0c3" why="target-gone"/>
<sa kind="api-surface:new-symbol" key="61f0e361ef7dee27" why="target-gone"/>
… [144 more display lines; full output is 17660 bytes on 1 raw line(s)]
`````

stderr:

`````
ripwire: no ./.ripwire_quality_baseline — auto-comparing the working tree vs git HEAD (commit the baseline with --quality-baseline to pin it)
ripwire: --quality-delta gating: 4 preexisting-worse major finding(s); first: complexity src/infra/sortutil.h::rw::sortutil::lessByScoreDescId at src/infra/sortutil.h:52 (was=1 now=67)
`````

## `./build/ripwire . --ack-only=gating`

*--ack-only WITHOUT --quality-ack REFUSES loudly (exit 1, the pairing named) — it used to be silently ignored.*

**exit code: 1** — **wall time: 1.02s**

`````
(empty)
`````

stderr:

`````
ripwire: --ack-only=SUBSTR narrows --quality-ack — pass both (e.g. ripwire <dir> --quality-delta --ack-only=contract-change --quality-ack="reason")
`````

## `./build/ripwire . --edit-check=nonNegativeFloatDescKey`

*A real contract-change: was=1 now=2 params, with the call sites that are now provably incompatible, and a pasteable next= (--uses=SYM) on the root.*

**wall time: 5.50s**

`````
<!-- ripwire edit-check schema=ripwire.edit-check/v1: sym='s contract NOW vs HEAD: status=unchanged|new-symbol|contract-change; <c n= p= incompatible=1 sites_l=> callers. counts_floor=1: every count is a FLOOR, never a total. graph_ambiguous=/graph_unresolved=: resolver gauge. graph_unindexed=N: N files no grammar could read (the map header's unindexed=); their calls raise neither gauge. est_tokens=: price as emitted (an upper bound under compact). at=: commit+dirty+shallow. root=: p= relative to it. next=: the one pasteable follow-up. defs=N: overloads at this site (same file, scope, name) folded into one contract; params compared by MAX. callers=N: callers of sym= (the c rows' total; a floor). -->
<edit-check schema="ripwire.edit-check/v1" sym="nonNegativeFloatDescKey" t="fn" p="src/infra/sortutil.h:112" status="contract-change" defs="1" params_was="1" params_now="2" public_was="1" public_now="1" defs_was="1" defs_now="1" change="params,broken-callers" callers="4" incompatible="4" at="0412539 … [line truncated: 161 more bytes on this line]
<c n="benchScores" p="bench/bench_radix_ab.cpp:133" incompatible="1" sites_l="146,152"/>
<c n="benchAdaptive" p="bench/bench_radix_ab.cpp:157" incompatible="1" sites_l="162"/>
<c n="radixSortNonNegativeFloatsDesc" p="src/infra/sortutil.h:141" incompatible="1" sites_l="150"/>
<c n="radixSortByScoreDescId" p="src/infra/sortutil.h:156" incompatible="1" sites_l="216"/>
</edit-check>
`````

## `./build/ripwire . --edit-check=nonNegativeFloatDescKey --legend=full`

*The same verdict under --legend=full: the default's one compact comment (the post-edit reflex at its cheapest) becomes ~5.7 KB of prose legend, every <c incompatible=> row identical.*

**wall time: 5.66s**

`````
<!-- ripwire edit-check: SYM's contract (param count + publicness) NOW vs git HEAD — unchanged/new-symbol/contract-change, or no-baseline when the root has no git HEAD to compare against (not a repository, or no commit yet): then NOTHING is claimed about the contract, and a symbol is never called new for want of a baseline — plus its 1-hop callers. A caller is flagged incompatible="1" when its argument count was reliably counted and NO definition in the folded set could accept it: every one has a FIXED arity that disagrees. A variadic, defaulted or implicit-receiver definition (a Python/Ruby method, whose params counts the self/cls the call site never writes) has no fixed arity and is never flagged. That makes the ARITY half one-sided — a call the compared definitions could accept is never flagged — but it is NOT a proof that the call site binds to THIS definition. Call edges are matched by NAME, so a receiver-qualified call to a same-named callee this tool does not index (a standard-library or third-party method) is measured against the one definition it does index; a clean, compiling tree can therefore carry a nonzero incompatible= with nothing edited at all, and on a widely-shared name it can be most of that name's callers. Read incompatible= as a fact about the tree as it stands — call sites worth OPENING, not a verdict — and status= as a fact about the edit. Warm path hits the qheadsnap/qsnap cache — never a full quality-delta style recompute. defs= is how many DEFINITIONS at this site (same file, same scope, same name — the overload set) are folded into this one contract; a selector matching more than one SITE is refused instead, so defs= only ever counts overloads. params_was and params_now are the MAX over that set on each side (the same MAX the baseline snapshot stores), and publicness is the OR. That MAX has TWO consequences, in opposite directions. It can read like a break and not be one: adding a WIDER overload beside an unchanged one raises params_now with no existing definition altered, so it reports status="contract-change" with incompatible="0" and a def row still carrying the old parameter count — no seen caller breaks. And it can read like safety and not be: REMOVING an overload whose parameter count is BELOW the MAX moves neither number, because the MAX survives on both sides, while the call site that used the removed definition no longer binds. defs_was=/defs_now= is what closes that: the count of definitions sharing this symbol's DEFINITION SITE — same file, same scope, same name — on each side. That is the population the baseline snapshot buckets by, so the two numbers answer the same question and are equal on an unedited tree. A same-named definition in ANOTHER FILE is a different contract and is counted on neither side, so defs_now= agrees with the root's defs= by construction and only defs_was= can move it. status is therefore the join of THREE was-vs-now facts — the params MAX, publicness, and the definition COUNT — and change= names which of them carried it. change= adds broken-callers when a seen caller is also flagged, but never on its own — for the reason stated at the top: incompatible= describes the TREE and status= describes the EDIT, so a headline must not turn on it. RESIDUAL: an overload whose arity changes BELOW the MAX while the COUNT stays the same moves none of the three. The root's incompatible= is the COUNT of flagged callers (a c row's incompatible="1" is the per-caller flag). sites_l= rides on a flagged row only: a c row's p= is where that CALLER is DEFINED, and sites_l= is the ascending LINE list of its call-role reference sites to this name — the lines to open, the same rows the uses verb prints, including the ones whose argument count could not be counted (so sites_l= can be wider than the evidence the flag rests on). Two calls on one line are ONE site. p= is the definition the selector resolved to; when defs is above 1 EVERY folded definition is listed as its own def row (p=, t=, params=), which is what tells a widened single definition apart from an added overload. At defs="1" no def row is emitted: the root's own p=/t= is that definition, and params_now is its parameter count. next= is the one pasteable follow-up: on a contract-change the uses verb on SYM (the call sites), otherwise the test gate on the definition's file. est_tokens= prices THIS document, through the tool's ONE emitted-bytes estimator. counts_floor="1" means every count here is a FLOOR, never a total: edges are extracted from source TEXT by NAME. Missing: dynamic dispatch (virtual/interface/duck-typed), a most-vexing-parse declaration with no call expression, a function-pointer/callback bound to more than one function in scope (reassigned, table-indexed, lambda-bound, or address-taken/reference-bound), and a plain-name binding (fp=handler) whose variable type is not PROVABLY a function pointer (a same-file typedef/declarator; a HEADER typedef is missed; auto/template types are read as unpinned, so KEPT). A macro-generated call site is role="macro" only when its name uniquely names an indexed function-like #define (C-family, t="macro"); a shared name stays a plain call, an unindexed macro is no edge. Read a zero as "none found", never as "none exists". graph_ambiguous=/graph_unresolved= are the whole graph's resolver gauge (calls split over several defs / calls whose in-repo defs were all language-filtered), the map header's ambiguous=/unresolved=. graph_unindexed=N is a third gauge: files no grammar could read (the map header's unindexed=), whose calls raise neither gauge above; absent when zero, and so is this sentence. COUNTING UNIT differs by verb: callers, callees, edit-check, graph-query and pr-context counts are DISTINCT SYMBOLS (repeated calls from one caller, and calls to two overloads, collapse into ONE row; multiplicity survives only in the call graph's edge weight). The reach counts (impact's reaches=, pr-context's dependents=) are the size of a transitive reach SET, each symbol counted once. The uses verb counts call SITES, one row per occurrence — a larger count there for the same symbol is these units agreeing, not disagreeing. The map header's edges= is a unit again different — distinct (caller,callee) PAIRS — and that document carries neither this marker nor this clause. -->
<edit-check sym="nonNegativeFloatDescKey" t="fn" p="src/infra/sortutil.h:112" status="contract-change" defs="1" params_was="1" params_now="2" public_was="1" public_now="1" defs_was="1" defs_now="1" change="params,broken-callers" callers="4" incompatible="4" at="0412539b9+dirty" graph_ambiguous="3456 … [line truncated: 131 more bytes on this line]
<c n="benchScores" p="bench/bench_radix_ab.cpp:133" incompatible="1" sites_l="146,152"/>
<c n="benchAdaptive" p="bench/bench_radix_ab.cpp:157" incompatible="1" sites_l="162"/>
<c n="radixSortNonNegativeFloatsDesc" p="src/infra/sortutil.h:141" incompatible="1" sites_l="150"/>
<c n="radixSortByScoreDescId" p="src/infra/sortutil.h:156" incompatible="1" sites_l="216"/>
</edit-check>
`````

## `./build/ripwire . --pr-context`

*The review-evidence bundle with an actual changed file.*

**wall time: 10.27s**

`````
<!-- ripwire pr-context schema=ripwire.pr-context/v1: review bundle per changed file vs base=: symbols, callers, blast radius, tests, owners. window: shown= capped= (capped=1 cut). counts_floor=1: every count is a FLOOR, never a total. graph_ambiguous=/graph_unresolved=: resolver gauge. graph_unindexed=N: N files no grammar could read (the map header's unindexed=); their calls raise neither gauge. est_tokens=: price as emitted (an upper bound under compact). at=: commit+dirty+shallow. root=: p= relative to it. truncated=: what the trim ladder dropped to fit budget_tokens= (budget-floor-exceeded: still over). direction=: side reviewed: worktree-since-head, head-since-fork or head-since-ref-tip. skipped_mode_only=N: mode-only (chmod) diffs left out of the changed files; renames stay in. trim_level=0-4: trim ladder step taken to fit budget_tokens= (0 none, 4 counts only); raise token-budget. budget_default=1: the default 8000-token budget applied (no token-budget or max-tokens given). commits=N: this file's commits in window=; 0 = the window could not look, not no partners. partners=N: co-change partners NOT in the diff; rows are its top shown= (the cochange verb lists all). dependents=N: distinct symbols transitively calling this file's symbols (reach set, a FLOOR). files_other=N: non-changed files among those reached; the f rows are its top shown=. authors=N: distinct authors of this file (0 = no git data). bf=1: one author holds over 80% of recency-weighted commits (bus-factor risk). files=N: changed files in the diff (shown= of them listed). file symbols=: indexed symbols in that changed file. changed-symbols count= / tests count=: that section's full count (shown= of it listed). tests count=: test files reaching this file (shown= of them listed). impact files=: files holding the transitive callers (dependents=). impactf deps=: transitive callers in that file. test run=: the command that runs that test file (run_unknown=1: none derivable). author email=/share=: a committer of this file / its fraction of the recency-weighted commits. s callers=N: direct callers of that changed symbol; caller rows are its top shown= (callers verb: all). -->
<pr-context schema="ripwire.pr-context/v1" base="working-tree" root="." direction="worktree-since-head" files="1" skipped_mode_only="0" budget_tokens="8000" est_tokens="3460" trim_level="0" truncated="none" budget_default="1" at="0412539b9+dirty" graph_ambiguous="3456" graph_unresolved="18664" graph … [line truncated: 34 more bytes on this line]
<file p="src/infra/sortutil.h" symbols="13">
<impact dependents="318" files="72" files_other="72" shown="20" capped="1">
<f p="src/mcpverbs.h" deps="35"/>
<f p="src/verbs_for.h" deps="22"/>
<f p="src/verbs_navigate.h" deps="17"/>
<f p="src/quality.h" deps="15"/>
<f p="src/verbs_quality.h" deps="14"/>
<f p="src/graph.h" deps="12"/>
<f p="src/forfilesyms.h" deps="11"/>
<f p="src/editcheck.h" deps="9"/>
<f p="src/main.cpp" deps="9"/>
<f p="src/exemplarfamily.h" deps="8"/>
<f p="src/resolve.h" deps="8"/>
<f p="src/serialize.h" deps="8"/>
<f p="src/verbs_change.h" deps="7"/>
<f p="bench/bench_sort_large.cpp" deps="6"/>
<f p="src/defattrib.h" deps="6"/>
<f p="src/mergescout.h" deps="6"/>
<f p="src/testmap.h" deps="6"/>
<f p="src/defectshape.h" deps="5"/>
<f p="src/situ.h" deps="5"/>
<f p="src/verbs_grep.h" deps="5"/>
</impact>
<tests count="6" shown="6" capped="0">
<test p="test/adaptivecutshapefix/adaptive_cut_shape_test.cpp" run="bash test/adaptivecutshapecheck.sh"/>
<test p="test/forrowfeatures_unit.cpp" run="bash test/forrowfeaturescheck.sh"/>
<test p="test/includeprecise_unit.cpp" run="bash test/includeprecisecheck.sh"/>
<test p="test/rustimport_unit.cpp" run="bash test/rustimportprecisecheck.sh"/>
… [88 more display lines; full output is 8647 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --map-diff --top-k=5`

*The map re-ranked with a teleport toward the changed file (changed=1 here, not 0).*

**wall time: 10.28s**

`````
<!-- ripwire map-diff schema=ripwire.map-diff/v1: the ranked map anchored at at=: what the diff touched, the map's row vocabulary. est_tokens=: price as emitted (an upper bound under compact). at=: commit+dirty+shallow. root=: p= relative to it. pr_iters=N: PageRank iterations. declined=K: K call sites without edges, including inert Elixir quote sites after unquote/unquote_splicing re-entry. external=K: K calls proven outside the tree, no edge. locality_pinned=K: K calls pinned by locality alone (a guess). extent_suspect_syms=K: K defs failed containment, corpus-wide. macro_blanked_files=K: K files indexed from a macro-blanked re-parse. files=/symbols=: files and symbols indexed; edges= distinct call edges; shown= symbols printed, a merged row counting each def; ambiguous= calls split over several defs, corpus-wide; unresolved= calls with in-tree evidence and no edge (every def language-filtered or unreachable, or binding refused); order= rows by rank (important-first, important-last; (auto:fill) = flipped past a size threshold) or by path (stable). changed=K: K indexed git-changed files seed the PageRank teleport (0: uniform, incl. no git). skipped_oversize=K: K files over a size ceiling, not indexed. unindexed=ext:N: N text files of that extension no grammar reads (6 extensions at most). unindexed_exts=E: E such extensions in all, the list cut. sc=: enclosing scope; the full id is p::sc::n (p= of the row or its <f>) and selectors take it. layer=: built-in arch layer (game|infra|render|math|audio|ai|test) from a dir name in p=; absent if none. -->
<!-- t=modscope=a-file's-MODULE-SCOPE(n=<file-scope>):the-statements-outside-every-named-definition,where-a-top-level-call-and-an-anonymous-callback-body's-calls-live;a-CALLER-never-a-callee(nothing-in-the-source-can-name-it)-with-no-body-to-expand;a-file-with-no-such-call-has-no-such-row -->
<!-- t=type|alias|functype=a-Go-named-type-by-its-written-form:type=a-defined-type-whose-WRITTEN-form-is-not-a-struct/iface/func-literal(type-N-string;type-W-Pair-too,whatever-Pair-is-underneath),alias=type-A=B,functype=type-F-func(...) -->
<!-- t=alias|functype-in-C++-and-.h:alias=using-X=Y(also-templated-or-class-scope)or-namespace-L=lib(defs=X-prints-its-written-target-as-to=),functype=a-typedef-of-a-function-or-function-pointer-type(typedef-void(*F)(int));other-typedefs-read-t=struct -->
<!-- files=4497 symbols=39564 edges=38971 shown=5 est_tokens=1326 ambiguous=3456 unresolved=18664 locality_pinned=11 external=11109 declined=41451 extent_suspect_syms=12 macro_blanked_files=7 changed=1 skipped_oversize=15 unindexed="txt:81,tsv:53,mod:33,jsonl:26,scm:25,expected:15" unindexed_exts=23 order=important-first -->
<r schema="ripwire.map-diff/v1" at="0412539b9+dirty" root="." est_tokens="1326" pr_iters="29">
<f p="src/infra/sortutil.h" layer="infra">
<s t="fn" n="radixSortByScoreDescId" sc="rw::sortutil" k="0.0964">
<c n="lessByScoreDescId"/>
<c n="radixSortUint32ByKey"/>
<c n="nonNegativeFloatDescKey"/>
</s>
<s t="fn" n="nonNegativeFloatDescKey" sc="rw::sortutil" k="0.0757">
</s>
<s t="fn" n="lessByScoreDescId" sc="rw::sortutil" k="0.0699">
</s>
<s t="fn" n="lessByFromTo" sc="rw::sortutil" k="0.0686">
</s>
</f>
<f p="src/infra/radixSort.h" layer="infra">
<s t="fn" n="sortKeySmall" sc="radix" k="0.0874">
</s>
</f>
</r>
`````

## `./build/ripwire . --clones`

*The duplicated helper the sandbox edit introduced shows up as a clone group.*

**wall time: 5.09s**

`````
<!-- ripwire clones schema=ripwire.clones/v1: similar normalized-token bodies: <group type=2|3 gid= tokens= n= similarity=> of <f n= p=>; dup_loc=/dup_pct=. window: shown= total= capped= has_more= next_offset= offset= limit= (capped=1 cut; next_offset= pastes as offset=). root=: p= relative to it. groups=/type3=: Type-2 and Type-3 group totals over all groups; total= is their sum. exempt_groups=N: groups whose members all sit on fixture/shell-runner paths quality-delta duplication ignores. idiom_groups=/demoted_groups=: groups of one recognized idiom / those quality-delta demotes to minor; floors. clone_groups=N: clusters after merging pairs (rows sharing gid=); a floor under type3_capped=1. total_loc=N: lines of every function body the detector considered; dup_pct= is dup_loc= over it. group exempt=fixture|shell-runner: every member is on such a path; quality-delta duplication ignores it. group idiom=: the recognized shape every member spells: threshold-ladder, switch-name-table, builder-chain. -->
<clones schema="ripwire.clones/v1" groups="159" type3="810" exempt_groups="635" idiom_groups="20" demoted_groups="12" clone_groups="425" dup_loc="8548" total_loc="302022" dup_pct="2.8" shown="80" capped="1" total="969" has_more="1" next_offset="80" offset="0" limit="0" root=".">
<group type="2" gid="49" tokens="338" n="3">
<f n="rw_is_ripwire_call" p="hooks/ripwire-claude-route.sh:187"/>
<f n="rw_is_ripwire_call" p="hooks/ripwire-codex-route.sh:104"/>
<f n="rw_is_ripwire_call" p="hooks/ripwire-nudge.sh:623"/>
</group>
<group type="2" gid="267" tokens="213" n="2" exempt="shell-runner">
<f n="call_sites" p="test/declinecheck.sh:116"/>
<f n="call_sites" p="test/usesselectorcheck.sh:49"/>
</group>
<group type="2" gid="356" tokens="211" n="4" exempt="shell-runner">
<f n="batch_sub" p="test/mcpclidiffcheck.sh:64"/>
<f n="batch_sub" p="test/mcptranchecheck.sh:55"/>
<f n="batch_sub" p="test/mcpw2fixcheck.sh:52"/>
<f n="batch_sub" p="test/mcpw3fixcheck.sh:51"/>
</group>
<group type="2" gid="226" tokens="210" n="2" exempt="shell-runner">
<f n="mcpfor" p="test/anchorhonestycheck.sh:35"/>
<f n="mcpfor" p="test/foranchornscheck.sh:29"/>
</group>
<group type="2" gid="378" tokens="198" n="2" exempt="shell-runner">
<f n="classify" p="test/preludevetocheck.sh:41"/>
<f n="classify" p="test/rustmacropathcheck.sh:39"/>
</group>
<group type="2" gid="262" tokens="175" n="2" exempt="shell-runner">
<f n="mcp" p="test/pathfewestcheck.sh:320"/>
<f n="mcp" p="test/pathroutecheck.sh:468"/>
</group>
<group type="2" gid="48" tokens="163" n="3">
… [308 more display lines; full output is 16278 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --stray-content=zz-orphan`

*CHANGED: a ref with NO merge base with HEAD now reports v="unknown" ok="0" in its own bucket — the absence of an answer, never a claim it is merged. (The sandbox carries a deliberately parentless branch built with `git commit-tree`; a shallow CI clone puts every ref here.)*

**wall time: 9.47s**

`````
<!-- ripwire stray-content schema=ripwire.stray-content/v1: per local ref, lines/symbols NOT in HEAD: <ref ok= v= base= stray=>; v=unknown = no merge base. at=: commit+dirty+shallow. head=: the HEAD commit, bare 9-hex sha (at= adds +dirty). head_ref=: HEAD's branch (HEAD when detached); that branch itself is not scanned. refs=N: local branches scanned (refs/heads only); unmerged + superseded + merged + unknown = refs. blobs=N: distinct git blobs read for the sweep. unmerged=N: refs whose authored work the live line genuinely lacks. superseded=N: refs whose work the live line re-implemented (removed the same base code). merged=N: refs whose work HEAD already has; omitted from the rows. name=: the local branch. tip=: the branch tip commit (9 hex). date=: the tip's committer date, YYYY-MM-DD. files=N: files with stray lines; rows capped at 12, a more element counts the rest (detail=1 lists all). ref superseded=N>: of this ref's stray= lines, those in files the live line re-implemented. unknown=N: refs that could not be analysed (v=unknown, e.g. no merge base); never counted merged. -->
<stray-content schema="ripwire.stray-content/v1" head="0412539b9" head_ref="integration/train-1111c" refs="1" blobs="0" unmerged="0" superseded="0" merged="0" unknown="1" filter="zz-orphan" at="0412539b9+dirty">
<ref name="zz-orphan-lane" tip="7c253d8ec" date="2026-11-12" base="" ok="0" v="unknown" stray="0" files="0" superseded="0">
</ref>
</stray-content>
`````

stderr:

`````
[math degraded] crossref: no merge-base for ref (shallow clone or unrelated history?) — verdict is unknown, not merged  (crossref.h:1284, RefPlumbing rw::crossref::probeRefBase(const std::string &, const RefInfo &, const std::string &) — logged once per site)
`````

## `./build/ripwire . --stray-content=zz-orphan --plan`

*CHANGED: --plan surfaces those same refs as an <undetermined> row rather than silently dropping them.*

**wall time: 11.83s**

`````
<!-- ripwire landing-plan schema=ripwire.landing-plan/v1: stranded-work landing order across refs, fewest conflicts first. at=: commit+dirty+shallow. -->
<landing-plan schema="ripwire.landing-plan/v1" head="0412539b9" refs="1" unmerged="0" superseded="0" merged="0" undetermined="1" scouted="0" bounded="0" scout-ok="1" at="0412539b9+dirty">
<undetermined name="zz-orphan-lane" v="unknown" reason="no merge base with HEAD (shallow clone or unrelated history) — this ref could not be analysed, it is NOT known to be merged; deepen the clone and re-run"/>
</landing-plan>
`````

stderr:

`````
[math degraded] crossref: no merge-base for ref (shallow clone or unrelated history?) — verdict is unknown, not merged  (crossref.h:1284, RefPlumbing rw::crossref::probeRefBase(const std::string &, const RefInfo &, const std::string &) — logged once per site)
`````

## `./build/ripwire . --dmm`

*The DMM scalar on a REAL delta: the sandbox edit grew one unit past the nesting/complexity thresholds and added an 8-parameter one, so dmm is low and the three sub-scores say which property moved.*

**wall time: 17.32s**

`````
<!-- ripwire dmm schema=ripwire.dmm/v1: Delta Maintainability Model base=→target=: dmm= good/(good+bad) units by size_metric=; <p k= dmm= good= bad= d_low= d_high=>. at=: commit+dirty+shallow. available=0: no score at all (dmm=UNAVAILABLE, reason= says why); never read as 1.000 or 0.000. combine=pooled: root dmm= is summed good over summed good+bad of the 3 properties (ripwire's own). low_loc=/low_cx=/low_params=: a unit is LOW risk at or under these lines / cyclomatic / params. base_units=/base_volume=/target_units=/target_volume=: units with a body and their line span per side. -->
<dmm schema="ripwire.dmm/v1" base="0412539b91400096c84f50d5dd9714966449ea6e" target="working-tree" at="0412539b9+dirty" available="1" combine="pooled" size_metric="physical-loc" low_loc="15" low_cx="5" low_params="2" dmm="0.142" good="23" bad="139" base_units="22551" base_volume="301968" target_unit … [line truncated: 33 more bytes on this line]
<p k="size" dmm="0.130" good="7" bad="47" d_low="7" d_high="47"/>
<p k="complexity" dmm="0.130" good="7" bad="47" d_low="7" d_high="47"/>
<p k="interfacing" dmm="0.167" good="9" bad="45" d_low="9" d_high="45"/>
</dmm>
`````

## `./build/ripwire . --quality-delta --scope=src/graph.h`

*OWNERSHIP partition for a shared tree: every regression here lives in src/infra/, so under a scope naming src/graph.h they ALL print under <out-of-scope> with a do-not-ack banner and never gate — scoped-out-gating= says how many would have.*

**wall time: 21.81s**

`````
<!-- ripwire quality-delta schema=ripwire.quality-delta/v1: only what the change made WORSE vs baseline=: regressions= minor= gating=; <r kind= sym= p= was= now= gating= bar=>, <sa> acked. value-ref-excluded=N: internal functions kept off because a table, field or argument in another function or at file scope holds them (matched by name, not a proven call); a floor. at=: commit+dirty+shallow. stale=N: ack ledger rows whose target no longer applies (sa rows); never gating. preexisting-worse=N: regressions on symbols that existed at baseline; they gate when major. new-symbol=N: findings on NEW code; new-symbol rows never gate, except defect-shape format-arity. register-macro-excluded=N: symbols kept out of dead-code as self-registering test/bench macros; a floor. declined-call-excluded=N: symbols kept out of dead-code only because a declined call may mean them; a floor. api-new-surface=N: new PUBLIC symbols; a count, never gates, not in regressions=. renames=/rename_window_commits=: git rename pairs read over that many commits, to re-file baseline and acks. acked_by_rename=/acked_by_content=: acked= suppressions matched via git renames / an equal body hash. renames_window_truncated=1: history is deeper than the rename window, older renames unread. r surface=: the api-surface tier, new-symbol or contract-change. acked=N: findings suppressed by the ack ledger, listed as sa rows; never gating. r sev=minor: a small numeric delta, counted in minor=, never gating (absent: major). r origin=new-symbol: a finding on NEW code (absent: preexisting-worse). sa key=/why=: the stale ack's ledger hash / target-gone (names nothing now) or finding-gone (no longer fires). r members=/tokens=: a duplication row's clone group (member ids) / their shared normalized-token count. -->
<quality-delta schema="ripwire.quality-delta/v1" baseline="git-HEAD" regressions="0" minor="0" acked="0" stale="163" preexisting-worse="0" new-symbol="0" gating="0" register-macro-excluded="62" api-new-surface="2" at="0412539b9+dirty" renames="67" rename_window_commits="400" acked_by_rename="0" acke … [line truncated: 156 more bytes on this line]
<out-of-scope n="9" would-gate="4" note="not yours - do not ack: these rows lie outside the scope this run named. They are disclosed rather than hidden, they never gate this exit code, and the ack refuses to write them.">
<r kind="api-surface" sym="src/infra/sortutil.h::rw::sortutil::nonNegativeFloatDescKey" was="1" now="2" surface="contract-change" p="src/infra/sortutil.h:112"/>
<r kind="complexity" sym="src/infra/sortutil.h::rw::sortutil::lessByScoreDescId" was="1" now="67" bar="15" p="src/infra/sortutil.h:52"/>
<r kind="dead-code" sym="src/infra/sortutil.h::rw::sortutil::nonNegativeFloatAscKeyCopy" origin="new-symbol" p="src/infra/sortutil.h:122"/>
<r kind="dead-code" sym="src/infra/sortutil.h::rw::sortutil::sortScoredIdsWithOptions" origin="new-symbol" p="src/infra/sortutil.h:132"/>
<r kind="duplication" members="src/infra/sortutil.h::rw::sortutil::nonNegativeFloatAscKeyCopy | src/infra/sortutil.h::rw::sortutil::nonNegativeFloatDescKey" tokens="59" p="src/infra/sortutil.h:122"/>
<r kind="nesting" sym="src/infra/sortutil.h::rw::sortutil::lessByScoreDescId" was="1" now="6" bar="4" p="src/infra/sortutil.h:52"/>
<r kind="new-clone-of-reused-helper" sym="src/infra/sortutil.h::rw::sortutil::nonNegativeFloatAscKeyCopy | src/infra/sortutil.h::rw::sortutil::nonNegativeFloatDescKey" was="0" now="4" p="src/infra/sortutil.h:122"/>
<r kind="params" sym="src/infra/sortutil.h::rw::sortutil::sortScoredIdsWithOptions" was="0" now="8" bar="5" origin="new-symbol" p="src/infra/sortutil.h:132"/>
<r kind="verbosity" sym="src/infra/sortutil.h::rw::sortutil::lessByScoreDescId" was="8" now="47" bar="60" sev="minor" p="src/infra/sortutil.h:52"/>
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
<sa kind="api-surface:new-symbol" key="25c9f0504fd376a4" why="target-gone"/>
<sa kind="api-surface:new-symbol" key="26aa7c55d54c4341" why="target-gone"/>
… [147 more display lines; full output is 17927 bytes on 1 raw line(s)]
`````

stderr:

`````
ripwire: no ./.ripwire_quality_baseline — auto-comparing the working tree vs git HEAD (commit the baseline with --quality-baseline to pin it)
`````

## `./build/ripwire . --quality-delta --quality-ack --scope=src/graph.h --ack-only=api-surface`

*The rubber-stamp guard: an --ack-only that names an OUT-OF-SCOPE row refuses (exit 1) and writes nothing.*

**exit code: 1** — **wall time: 20.10s**

`````
(empty)
`````

stderr:

`````
ripwire: no ./.ripwire_quality_baseline — auto-comparing the working tree vs git HEAD (commit the baseline with --quality-baseline to pin it)
ripwire: --ack-only=api-surface selects 1 finding(s) OUT OF SCOPE for --scope=src/graph.h — refusing, and writing nothing at all:
    api-surface src/infra/sortutil.h::rw::sortutil::nonNegativeFloatDescKey at src/infra/sortutil.h:112
  those rows belong to whoever is editing those paths. Acking them here writes their debt into a committed ledger under YOUR
  reason string, which is how a per-finding ratchet becomes a rubber stamp. Narrow the pattern, or widen the scope if they really are yours.
`````

## `./build/ripwire . --handoff`

*The continuation packet with a REAL diff: verified changed symbols + blast radius + tests-to-run, then the heuristic rows.*

**wall time: 14.93s**

`````
<!-- ripwire handoff schema=ripwire.handoff/v1: continuation packet for the NEXT session: <verified changed= blast_files=>, <tests n=>, <heuristic n= candidates=>, <note>, <doc p=>. window: capped= (capped=1 cut). est_tokens=: price as emitted (an upper bound under compact). at=: commit+dirty+shallow. root=: p= relative to it. branch=/subject=: the checked out branch and HEAD commit subject; gitok=0: the git diff probe failed, changed counts are floors. cochange_window=/cochange_commits=: the git window the cochange rows were mined in and the commits it held (0: could not look). doc s=: lexical score of that plan/design doc for the branch+subject query. t run=: the command that runs that test (run_unknown=1: none derivable). -->
<handoff schema="ripwire.handoff/v1" at="0412539b9+dirty" root="." branch="integration/train-1111c" subject="Re-pin binary-pinned files from the merged build (parity labels, legend pair, COMMANDS.md)" gitok="1" est_tokens="947">
<verified changed="1" blast_files="72">
<f p="src/infra/sortutil.h">
<s n="svCompare"/>
<s n="svLess"/>
<s n="lessByScoreDescId"/>
<s n="radixSortUint32ByKey"/>
<s n="nonNegativeFloatDescKey"/>
<s n="nonNegativeFloatAscKeyCopy"/>
<s n="sortScoredIdsWithOptions"/>
<s n="radixSortNonNegativeFloatsDesc"/>
<s n="radixSortByScoreDescId"/>
<s n="radixSortByScoreDescId"/>
<s n="lessByFromTo"/>
<s n="radixSortByFromTo"/>
<s n="radixSortByFromTo"/>
</f>
<tests n="6">
<t p="test/verify_radix.cpp" run="bash test/greptiercheck.sh"/>
<t p="test/adaptivecutshapefix/adaptive_cut_shape_test.cpp" run="bash test/adaptivecutshapecheck.sh"/>
<t p="test/forrowfeatures_unit.cpp" run="bash test/forrowfeaturescheck.sh"/>
<t p="test/verify_csr.cpp" run="bash test/a9disclosurecheck.sh"/>
<t p="test/includeprecise_unit.cpp" run="bash test/includeprecisecheck.sh"/>
<t p="test/rustimport_unit.cpp" run="bash test/rustimportprecisecheck.sh"/>
</tests>
</verified>
<heuristic n="4" candidates="258" capped="1" cochange_window="18mo@HEAD" cochange_commits="6983">
<doc p="CHANGELOG.md" s="14.326"/>
<doc p="prompts/help-wanted/visual-basic-language.md" s="12.333"/>
<doc p="prompts/help-wanted/uses-qualified-selector.md" s="11.438"/>
<doc p="prompts/help-wanted/next-uses-bare-name.md" s="10.635"/>
</heuristic>
</handoff>
`````

## `./build/ripwire . --note-add="lessByScoreDescId: keep this branch-free — it sits inside the PageRank sort comparator"`

*Pin a field note (write-side memory) to a symbol; committed to .ripwire_notes in the sandbox. The BARE name is resolved through the same resolver the read verbs use and stored as the canonical id — the rewrite is echoed on stderr, because a silent one is not a disclosure.*

**wall time: 5.67s**

`````
src/infra/sortutil.h::rw::sortutil::lessByScoreDescId	2026-11-12	keep this branch-free — it sits inside the PageRank sort comparator	0412539b91400096c84f50d5dd9714966449ea6e	integration/train-1111c
`````

stderr:

`````
ripwire: --note-add: tip: notes that say "chose X over Y because Z" surface better — consider adding the why
ripwire: --note-add: target 'lessByScoreDescId' canonicalised to 'src/infra/sortutil.h::rw::sortutil::lessByScoreDescId' — that is the id --for/--expand key notes by
`````

## `./build/ripwire . --notes`

*The note is listed under the canonical id, dangling="0" — i.e. it will actually surface. (Before the H1 fix the bare name was stored verbatim and read dangling="1": recorded, and surfaced nowhere.)*

**wall time: 2.61s**

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
<note d="2026-11-12" sha="0412539" branch="integration/train-1111c">
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

**exit code: 1** — **wall time: 1.70s**

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

**exit code: 1** — **wall time: 2.70s**

`````
(empty)
`````

stderr:

`````
ripwire: --note-add: tip: notes that say "chose X over Y because Z" surface better — consider adding the why
ripwire: --note-add: target not found: lessByScoreDescIdd (did you mean 'lessByScoreDescId'?) (note: the lexical definition scan stopped at its budget, 4096 files or 16 MiB, before reading every file, so this miss is not proof the bytes define nothing; --grep=lessByScoreDescIdd lists its text uses)  … [line truncated: 170 more bytes on this line]
`````

## `./build/ripwire . --note-add="src/infra/sortutil.h::rw::sortutil::lessByScoreDescId: chose the flat two-branch compare over the nested ladder because the comparator sits inside the PageRank sort"`

*The same symbol addressed by its CANONICAL id: already canonical, so nothing is rewritten and both notes land on ONE target.*

**wall time: 4.78s**

`````
src/infra/sortutil.h::rw::sortutil::lessByScoreDescId	2026-11-12	chose the flat two-branch compare over the nested ladder because the comparator sits inside the PageRank sort	0412539b91400096c84f50d5dd9714966449ea6e	integration/train-1111c
`````

## `./build/ripwire . --expand=lessByScoreDescId --top-k=0`

*Both notes riding along with the symbol's body — the <note> elements follow the body, past the display cut, so they are extracted below.*

**wall time: 3.09s**

`````
<ctx schema="ripwire.expand/v1" root="." est_tokens="834">
<!-- ripwire expand schema=ripwire.expand/v1: full bodies: <bodies shown= total= capped=> of <b t= l= p= n= sibs= sibs_total= sibs_capped= inc=>; <calls>
<c n= l=> resolved callees. window: shown= total= capped= (capped=1 cut). est_tokens=: price as emitted (an upper bound under compact). root=: p= relative to it. scrubbed=1: this CDATA is not the bytes (]]> split or C0 replaced). redacted=1: a credential shape rewritten to [REDACTED:kind]; the no-re … [line truncated: 130 more bytes on this line]
<bodies shown="1" total="1" capped="0">
<b t="fn" l="52" p="src/infra/sortutil.h" n="lessByScoreDescId" sibs="svCompare,svLess,radixSortUint32ByKey,nonNegativeFloatDescKey,nonNegativeFloatAscKeyCopy,sortScoredIdsWithOptions,radixSortNonNegativeFloatsDesc,radixSortByScoreDescId,radixSortByScoreDescId,lessByFromTo,radixSortByFromTo,radixSor … [line truncated: 122 more bytes on this line]
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
… [22 more display lines; full output is 3203 bytes on 47 raw line(s)]
`````

The <note> element on the same output — past the 30-line display cut above:

`````
<note d="2026-11-12" sha="0412539" branch="integration/train-1111c">
<![CDATA[chose the flat two-branch compare over the nested ladder because the comparator sits inside the PageRank sort]]>
</note>
<note d="2026-11-12" sha="0412539" branch="integration/train-1111c">
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

**wall time: 14.29s**

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
{"applied":"replace_symbol_body","symbol":"lessByScoreDescId","file":"src/infra/sortutil.h","span":{"start":2428,"end":2641},"lines":{"start":52,"end":59},"replaced_bytes":1718,"old_file_bytes":10184,"new_file_bytes":8679,"file_eol":"lf","eol_normalized":false,"trailing_newline_folded":true,"separat … [line truncated: 830 more bytes on this line]
"graph_ambiguous":3456,"graph_unresolved":18664,"graph_unindexed":286,"counts_floor":true},"tests_to_run":[{"p":"test/verify_radix.cpp","hops":1,"run":"bash test/greptiercheck.sh"},
{"p":"test/adaptivecutshapefix/adaptive_cut_shape_test.cpp","hops":2,"run":"bash test/adaptivecutshapecheck.sh"},
{"p":"test/forrowfeatures_unit.cpp","hops":2,"run":"bash test/forrowfeaturescheck.sh"},
{"p":"test/verify_csr.cpp","hops":2,"run":"bash test/a9disclosurecheck.sh"},
{"p":"test/includeprecise_unit.cpp","hops":4,"run":"bash test/includeprecisecheck.sh"},
{"p":"test/rustimport_unit.cpp","hops":4,"run":"bash test/rustimportprecisecheck.sh"}],
"order":"evidence","partners":0,"run_first":1,"tests":6,"script_gates_unmodelled":872,"graph_ambiguous":3456,"graph_unresolved":18664,"graph_unindexed":286,"counts_floor":true,"next":"bash test/greptiercheck.sh"}
`````

stderr:

`````
ripwire: cache <tmp>: over its 2048 MiB budget — evicted 163 blob(s) of other roots or other ripwire builds (this build's blobs for this root are kept)
ripwire edit: applied atomically; receipt carries region, blob_sha, edit_check, tests_to_run; next: bash test/greptiercheck.sh
`````

## `./build/ripwire . --edit-check=lessByScoreDescId`

*The closed loop: contract unchanged (same params, same publicness) after the replace — nothing provably incompatible.*

**wall time: 7.69s**

`````
<!-- ripwire edit-check schema=ripwire.edit-check/v1: sym='s contract NOW vs HEAD: status=unchanged|new-symbol|contract-change; <c n= p= incompatible=1 sites_l=> callers. counts_floor=1: every count is a FLOOR, never a total. graph_ambiguous=/graph_unresolved=: resolver gauge. graph_unindexed=N: N files no grammar could read (the map header's unindexed=); their calls raise neither gauge. est_tokens=: price as emitted (an upper bound under compact). at=: commit+dirty+shallow. root=: p= relative to it. next=: the one pasteable follow-up. defs=N: overloads at this site (same file, scope, name) folded into one contract; params compared by MAX. callers=N: callers of sym= (the c rows' total; a floor). -->
<edit-check schema="ripwire.edit-check/v1" sym="lessByScoreDescId" t="fn" p="src/infra/sortutil.h:52" status="unchanged" defs="1" callers="4" incompatible="0" at="0412539b9+dirty" graph_ambiguous="3456" graph_unresolved="18664" graph_unindexed="286" counts_floor="1" root="." next="--test-gate=src/in … [line truncated: 33 more bytes on this line]
<note d="2026-11-12" sha="0412539" branch="integration/train-1111c">
<![CDATA[chose the flat two-branch compare over the nested ladder because the comparator sits inside the PageRank sort]]>
</note>
<note d="2026-11-12" sha="0412539" branch="integration/train-1111c">
<![CDATA[keep this branch-free — it sits inside the PageRank sort comparator]]>
</note>
<c n="benchScores" p="bench/bench_radix_ab.cpp:133"/>
<c n="benchScoreCase" p="bench/bench_sort_large.cpp:230"/>
<c n="radixSortByScoreDescId" p="src/infra/sortutil.h:117"/>
<c n="verifyRipwireWrappers" p="test/verify_radix.cpp:249"/>
</edit-check>
`````

## `./build/ripwire . --insert-after-symbol=lessByScoreDescId --edit-payload=<scratch>/aux/payload_note.h`

*Insert immediately AFTER one uniquely-resolved definition; replaced_bytes=0 because the insert verbs never overwrite. The receipt carries the folded post-edit verification (lines=, edit_check, tests_to_run) so the loop closes in one call.*

**wall time: 11.67s**

`````
{"applied":"insert_after_symbol","symbol":"lessByScoreDescId","file":"src/infra/sortutil.h","span":{"start":2641,"end":2729},"lines":{"start":59,"end":61},"replaced_bytes":0,"old_file_bytes":8679,"new_file_bytes":8767,"file_eol":"lf","eol_normalized":false,"trailing_newline_folded":true,"separator_p … [line truncated: 650 more bytes on this line]
"graph_ambiguous":3456,"graph_unresolved":18664,"graph_unindexed":286,"counts_floor":true},"tests_to_run":[{"p":"test/verify_radix.cpp","hops":1,"run":"bash test/greptiercheck.sh"},
{"p":"test/adaptivecutshapefix/adaptive_cut_shape_test.cpp","hops":2,"run":"bash test/adaptivecutshapecheck.sh"},
{"p":"test/forrowfeatures_unit.cpp","hops":2,"run":"bash test/forrowfeaturescheck.sh"},
{"p":"test/verify_csr.cpp","hops":2,"run":"bash test/a9disclosurecheck.sh"},
{"p":"test/includeprecise_unit.cpp","hops":4,"run":"bash test/includeprecisecheck.sh"},
{"p":"test/rustimport_unit.cpp","hops":4,"run":"bash test/rustimportprecisecheck.sh"}],
"order":"evidence","partners":0,"run_first":1,"tests":6,"script_gates_unmodelled":872,"graph_ambiguous":3456,"graph_unresolved":18664,"graph_unindexed":286,"counts_floor":true,"next":"bash test/greptiercheck.sh"}
`````

stderr:

`````
ripwire edit: applied atomically; receipt carries region, blob_sha, edit_check, tests_to_run; next: bash test/greptiercheck.sh
`````

## `./build/ripwire . --insert-after-symbol=lessByScoreDescId --edit-payload=<scratch>/aux/payload_note.h --no-post-check`

*The opt-out: the same insert with the folded verification skipped — lines= still rides (it is free), edit_check/tests_to_run do not, and the two pasteable commands stay on stderr.*

**wall time: 4.67s**

`````
{"applied":"insert_after_symbol","symbol":"lessByScoreDescId","file":"src/infra/sortutil.h","span":{"start":2641,"end":2729},"lines":{"start":59,"end":61},"replaced_bytes":0,"old_file_bytes":8767,"new_file_bytes":8855,"file_eol":"lf","eol_normalized":false,"trailing_newline_folded":true,"separator_p … [line truncated: 570 more bytes on this line]
`````

stderr:

`````
ripwire edit: applied atomically; receipt carries region, blob_sha (post-check skipped); next: --edit-check=src/infra/sortutil.h:lessByScoreDescId
`````

## `./build/ripwire . --insert-before-symbol=nonNegativeFloatDescKey --edit-payload=<scratch>/aux/payload_note.h --edit-target-file=src/infra/sortutil.h`

*Insert BEFORE, with --edit-target-file pinning which same-named definition (here unambiguous — the disambiguator is simply honoured).*

**wall time: 12.14s**

`````
{"applied":"insert_before_symbol","symbol":"nonNegativeFloatDescKey","file":"src/infra/sortutil.h","span":{"start":3161,"end":3249},"lines":{"start":77,"end":78},"replaced_bytes":0,"old_file_bytes":8855,"new_file_bytes":8943,"file_eol":"lf","eol_normalized":false,"trailing_newline_folded":false,"sep … [line truncated: 753 more bytes on this line]
{"n":"benchAdaptive","p":"bench/bench_radix_ab.cpp:157","l":[162]},
{"n":"radixSortNonNegativeFloatsDesc","p":"src/infra/sortutil.h:108","l":[117]},
{"n":"radixSortByScoreDescId","p":"src/infra/sortutil.h:123","l":[183]}],
"graph_ambiguous":3456,"graph_unresolved":18664,"graph_unindexed":286,"counts_floor":true},"tests_to_run":[{"p":"test/verify_radix.cpp","hops":1,"run":"bash test/greptiercheck.sh"},
{"p":"test/adaptivecutshapefix/adaptive_cut_shape_test.cpp","hops":2,"run":"bash test/adaptivecutshapecheck.sh"},
{"p":"test/forrowfeatures_unit.cpp","hops":2,"run":"bash test/forrowfeaturescheck.sh"},
{"p":"test/verify_csr.cpp","hops":2,"run":"bash test/a9disclosurecheck.sh"},
{"p":"test/includeprecise_unit.cpp","hops":4,"run":"bash test/includeprecisecheck.sh"},
{"p":"test/rustimport_unit.cpp","hops":4,"run":"bash test/rustimportprecisecheck.sh"}],
"order":"evidence","partners":0,"run_first":1,"tests":6,"script_gates_unmodelled":872,"graph_ambiguous":3456,"graph_unresolved":18664,"graph_unindexed":286,"counts_floor":true,"next":"--uses=src/infra/sortutil.h:nonNegativeFloatDescKey"}
`````

stderr:

`````
ripwire edit: applied atomically; receipt carries region, blob_sha, edit_check, tests_to_run; next: --uses=src/infra/sortutil.h:nonNegativeFloatDescKey
`````

## `./build/ripwire . --replace-symbol-body=DoesNotExist --edit-payload=<scratch>/aux/payload_note.h`

*An unknown TARGET refuses and leaves every file byte-identical.*

**exit code: 1** — **wall time: 6.92s**

`````
(empty)
`````

stderr:

`````
ripwire: --replace-symbol-body: symbol 'DoesNotExist' not found
`````

## `./build/ripwire . --edit-plan=<scratch>/aux/edit_plan.json --dry-run`

*A versioned multi-edit TRANSACTION preflighted without writing: the receipt shows what each op would read and touch.*

**wall time: 5.97s**

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
{"schema":"ripwire.edit-plan/v1","mode":"dry-run","edits":1,"files":1,"callers_union":4,"graph_ambiguous":3456,"graph_unresolved":18664,"graph_unindexed":286,"counts_floor":true,"atomic_scope":"per-file","rollback_on_write_error":true,"recheck_before_each_write":true,"multifile_crash_atomic":false," … [line truncated: 353 more bytes on this line]
`````

## `./build/ripwire . --edit-plan=<scratch>/aux/edit_plan.json --apply`

*The same plan committed: per-file locks, re-verify-before-write, atomic rename, rollback on a later failure.*

**wall time: 10.12s**

`````
{"schema":"ripwire.edit-plan/v1","mode":"apply","edits":1,"files":1,"callers_union":4,"graph_ambiguous":3456,"graph_unresolved":18664,"graph_unindexed":286,"counts_floor":true,"applied":1,"atomic_files":1,"atomic_scope":"per-file","rollback_on_write_error":true,"recheck_before_each_write":true,"mult … [line truncated: 537 more bytes on this line]
{"n":"benchAdaptive","p":"bench/bench_radix_ab.cpp:157","l":[162]},
{"n":"radixSortNonNegativeFloatsDesc","p":"src/infra/sortutil.h:110","l":[119]},
{"n":"radixSortByScoreDescId","p":"src/infra/sortutil.h:125","l":[185]}],
"graph_ambiguous":3456,"graph_unresolved":18664,"graph_unindexed":286,"counts_floor":true}}]}
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

**exit code: 2** — **wall time: 26.90s**

`````
<!-- ripwire quality-delta schema=ripwire.quality-delta/v1: only what the change made WORSE vs baseline=: regressions= minor= gating=; <r kind= sym= p= was= now= gating= bar=>, <sa> acked. value-ref-excluded=N: internal functions kept off because a table, field or argument in another function or at file scope holds them (matched by name, not a proven call); a floor. at=: commit+dirty+shallow. next=: the one pasteable follow-up. stale=N: ack ledger rows whose target no longer applies (sa rows); never gating. preexisting-worse=N: regressions on symbols that existed at baseline; they gate when major. new-symbol=N: findings on NEW code; new-symbol rows never gate, except defect-shape format-arity. register-macro-excluded=N: symbols kept out of dead-code as self-registering test/bench macros; a floor. declined-call-excluded=N: symbols kept out of dead-code only because a declined call may mean them; a floor. api-new-surface=N: new PUBLIC symbols; a count, never gates, not in regressions=. renames=/rename_window_commits=: git rename pairs read over that many commits, to re-file baseline and acks. acked_by_rename=/acked_by_content=: acked= suppressions matched via git renames / an equal body hash. renames_window_truncated=1: history is deeper than the rename window, older renames unread. acked=N: findings suppressed by the ack ledger, listed as sa rows; never gating. r origin=new-symbol: a finding on NEW code (absent: preexisting-worse). sa key=/why=: the stale ack's ledger hash / target-gone (names nothing now) or finding-gone (no longer fires). r members=/tokens=: a duplication row's clone group (member ids) / their shared normalized-token count. -->
<quality-delta schema="ripwire.quality-delta/v1" baseline="git-HEAD" regressions="5" minor="0" acked="1" stale="163" preexisting-worse="2" new-symbol="3" gating="2" register-macro-excluded="62" api-new-surface="2" at="0412539b9+dirty" renames="67" rename_window_commits="400" acked_by_rename="0" acke … [line truncated: 99 more bytes on this line]
<r kind="dead-code" sym="src/infra/sortutil.h::rw::sortutil::nonNegativeFloatAscKeyCopy" origin="new-symbol" p="src/infra/sortutil.h:91"/>
<r kind="dead-code" sym="src/infra/sortutil.h::rw::sortutil::sortScoredIdsWithOptions" origin="new-symbol" p="src/infra/sortutil.h:101"/>
<r kind="duplication" members="src/infra/sortutil.h::rw::sortutil::nonNegativeFloatAscKeyCopy | src/infra/sortutil.h::rw::sortutil::nonNegativeFloatDescKey" tokens="59" p="src/infra/sortutil.h:91" gating="1"/>
<r kind="new-clone-of-reused-helper" sym="src/infra/sortutil.h::rw::sortutil::nonNegativeFloatAscKeyCopy | src/infra/sortutil.h::rw::sortutil::nonNegativeFloatDescKey" was="0" now="4" p="src/infra/sortutil.h:91" gating="1" next="--expand=src/infra/sortutil.h:nonNegativeFloatDescKey"/>
<r kind="params" sym="src/infra/sortutil.h::rw::sortutil::sortScoredIdsWithOptions" was="0" now="8" bar="5" origin="new-symbol" p="src/infra/sortutil.h:101"/>
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
<sa kind="api-surface:new-symbol" key="25c9f0504fd376a4" why="target-gone"/>
<sa kind="api-surface:new-symbol" key="26aa7c55d54c4341" why="target-gone"/>
<sa kind="api-surface:new-symbol" key="36e39c7ab0fc1686" why="target-gone"/>
<sa kind="api-surface:new-symbol" key="4bce64bd920de0c3" why="target-gone"/>
<sa kind="api-surface:new-symbol" key="61f0e361ef7dee27" why="target-gone"/>
<sa kind="api-surface:new-symbol" key="79625906f9f71ad0" why="target-gone"/>
<sa kind="api-surface:new-symbol" key="8ecb190954dce18a" why="target-gone"/>
<sa kind="api-surface:new-symbol" key="995375dfa4e63104" why="target-gone"/>
… [141 more display lines; full output is 17026 bytes on 1 raw line(s)]
`````

stderr:

`````
ripwire: no ./.ripwire_quality_baseline — auto-comparing the working tree vs git HEAD (commit the baseline with --quality-baseline to pin it)
ripwire: --quality-delta gating: 2 preexisting-worse major finding(s); first: duplication src/infra/sortutil.h::rw::sortutil::nonNegativeFloatAscKeyCopy | src/infra/sortutil.h::rw::sortutil::nonNegativeFloatDescKey at src/infra/sortutil.h:91 (was=0 now=59)
`````

## `./build/ripwire . --quality-baseline`

*REFUSES, exit 1: this sandbox tree is already regressed, and pinning here would swallow that debt into the floor so every later delta read clean. It names how many gating findings it would absorb, the first of them, and the way forward.*

**exit code: 1** — **wall time: 26.45s**

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

**wall time: 25.87s**

`````
(empty)
`````

stderr:

`````
ripwire: --quality-baseline --allow-dirty: pinned with 2 gating finding(s) ABSORBED into the floor (stamped in the sidecar; every --quality-delta against it carries baseline_absorbed="2")
ripwire: wrote ./.ripwire_quality_baseline (snapshot of 38362 per-symbol rows, 39565 indexed symbols total)
`````

Artifact written:

`````
 6590802 .ripwire_quality_baseline
# ripwire quality baseline v6 — regenerate with --quality-baseline; do not hand-edit
producer b1201360dffbbb1051c23cc87cc65f3cc29b2de6fe09b5b7c71cb63fc8dcb307
head 0412539b91400096c84f50d5dd9714966449ea6e
dirty 1
absorbed 2
ccx 67c15011ee8b 0
ccx d19d7c13cbc7 2
ccx 1f7edbff929e5 10
ccx 6a732f6699b
`````

## `./build/ripwire . --quality-delta`

*Against that sidecar the same tree reads regressions=0 — but baseline_absorbed= is on the root, so this green means clean SINCE THE PIN, never clean. A baseline is a floor YOU chose, and it belongs BEFORE the change.*

**wall time: 19.85s**

`````
<!-- ripwire quality-delta schema=ripwire.quality-delta/v1: only what the change made WORSE vs baseline=: regressions= minor= gating=; <r kind= sym= p= was= now= gating= bar=>, <sa> acked. value-ref-excluded=N: internal functions kept off because a table, field or argument in another function or at file scope holds them (matched by name, not a proven call); a floor. at=: commit+dirty+shallow. stale=N: ack ledger rows whose target no longer applies (sa rows); never gating. stale_by_kind=: stale= split by ack kind (kind:N,...); the sa rows are collapsed. stale_next=: the call printing the sa rows and the full header. preexisting-worse=N: regressions on symbols that existed at baseline; they gate when major. new-symbol=N: findings on NEW code; new-symbol rows never gate, except defect-shape format-arity. register-macro-excluded=N: symbols kept out of dead-code as self-registering test/bench macros; a floor. declined-call-excluded=N: symbols kept out of dead-code only because a declined call may mean them; a floor. api-new-surface=N: new PUBLIC symbols; a count, never gates, not in regressions=. renames=/rename_window_commits=: git rename pairs read over that many commits, to re-file baseline and acks. acked_by_rename=/acked_by_content=: acked= suppressions matched via git renames / an equal body hash. renames_window_truncated=1: history is deeper than the rename window, older renames unread. acked=N: findings suppressed by the ack ledger, listed as sa rows; never gating. -->
<quality-delta schema="ripwire.quality-delta/v1" baseline="sidecar" regressions="0" minor="0" acked="0" stale="163" preexisting-worse="0" new-symbol="0" gating="0" register-macro-excluded="62" api-new-surface="0" at="0412539b9+dirty" renames="67" rename_window_commits="400" acked_by_rename="0" acked … [line truncated: 318 more bytes on this line]
</quality-delta>
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
{"name":"cochange","description":"Files that historically change together with this file — the co-edit partners. Fowler's Shotgun Surgery as change coupling. dep_capable=false (sh/md/json/binary) or no_file_edges (Go, Java: imports not resolved) makes surprising undefined, not a finding. file = th … [line truncated: 705 more bytes on this line]
{"name":"memory_recall","description":"Most relevant memory notes / docs for a task, full text — the few that matter, not the whole corpus. path = docs/memory dir; task = what you're working on; top_k = docs to return, 1..1000 (default 6), refused outside that band, never clamped; budget_tokens =  … [line truncated: 790 more bytes on this line]
{"name":"situational_awareness","description":"The 5 things to know about a diff, as JSON: blast_radius, tests_to_run, forgotten (usual co-change partners missing from this diff), hotspot_alert, modules_touched. forgotten = the Shotgun Surgery check. diff/files optional — defaults to 'git diff HEA … [line truncated: 1297 more bytes on this line]
{"name":"mentions","description":"Docs (markdown plans/designs) that name a code symbol in a backtick. symbol = the code symbol name; limit/offset page the files. An @FILE:LINE line-seed rebinds to the innermost definition enclosing that line and answers for it, disclosing the rebound name as 'sym'  … [line truncated: 625 more bytes on this line]
{"name":"for","description":"Task-lens ranked, signatures-only inventory of the building blocks most relevant to a task (cx=complexity, in=reuse-count). task = the task in plain words; budget_tokens = an optional soft row target (the CLI --for --token-budget). The header carries route= (which ranker … [line truncated: 1061 more bytes on this line]
{"name":"lego","description":"Interface-to-impls view for ONE named interface/base: its method contract plus EVERY implementor (own-language only), each with file path. Use when implementing against a KNOWN interface (contrast 'for', which sprays top interfaces for a task). type = interface/base nam … [line truncated: 841 more bytes on this line]
{"name":"owners","description":"Bus-factor: recency-weighted (6-month half-life) author ownership per file. symbol = optional, restricts to the file that defines it; limit/offset page the rows. at= is the commit these numbers were computed at (+dirty = the working tree differed). An @FILE:LINE line- … [line truncated: 879 more bytes on this line]
{"name":"replace_symbol_body","description":"Replace a symbol's ENTIRE definition (signature through closing brace) with new_body — splices over the full def span, preserving every byte outside it verbatim; new_body must be a complete, well-formed definition. One trailing newline folds (trailing_n … [line truncated: 1323 more bytes on this line]
{"name":"insert_before_symbol","description":"Insert text immediately BEFORE a symbol's definition (its first byte); padded to the file's own blank-line seam (separator_padded=N). Same refusal contract as replace_symbol_body (not found / ambiguous / stale index / symlink / concurrent write, file unc … [line truncated: 877 more bytes on this line]
{"name":"insert_after_symbol","description":"Insert text immediately AFTER a symbol's definition (past its final byte, which is preserved exactly); padded to the file's own blank-line seam (separator_padded=N); one trailing newline folds (trailing_newline_folded). Same refusal contract as replace_sy … [line truncated: 878 more bytes on this line]
{"name":"fetch_body","description":"Full (or partial-range) source of a symbol's definition, addressed by the stable `handle` a read verb attached to it (bodies on request, not by default). start_line/end_line are optional, 1-based, INCLUSIVE and BODY-RELATIVE (line 1 = the def's first line), clampe … [line truncated: 1049 more bytes on this line]
{"name":"exemplar","description":"BEFORE writing a function / method / class / struct / interface / variable, get the repo's single best-in-class instance of that kind to imitate — signature AND full body. chosen by ROLE, NEVER by text similarity to your task: candidates are first filtered to cogn … [line truncated: 1372 more bytes on this line]
{"name":"quality_delta","description":"Your PR self-check, run every time you think a change is DONE — pairs with the CLI-only --test-gate (names the tests to run + the untested blast radius; not MCP-exposed) to form the two-step pre-PR gate. Reports ONLY what your working tree made WORSE vs basel … [line truncated: 862 more bytes on this line]
{"name":"quality_baseline","description":"PIN the quality floor: writes .ripwire_quality_baseline stamped with the current git HEAD sha, snapshotting complexity / duplication / dead-code / API surface. Call once at the start of non-trivial work, then quality_delta compares against this pinned floor  … [line truncated: 445 more bytes on this line]
{"name":"impact","description":"IS IT SAFE TO CHANGE X? — the TRANSITIVE blast radius of a symbol via calls, nearest first (d= hop depth), then PageRank. Use before modifying or deleting a symbol; it beats find_referencing_symbols (direct callers only), and 'uses' catches the read/write/import sit … [line truncated: 1325 more bytes on this line]
{"name":"uses","description":"The STATICALLY RESOLVABLE use-sites of a symbol, not just calls: role (call | read | write | import | extends), file:line, and enclosing symbol. Use to see the footprint before renaming or changing a name — find_referencing_symbols and impact follow only calls. extern … [line truncated: 1146 more bytes on this line]
{"name":"affected","description":"WHICH TESTS TO RUN for a change — test files that transitively reach the changed files/symbols, ranked by evidence (edited > partner-named > hop distance). files = changed files and/or symbols, comma-separated: each item is tried as an indexed PATH pattern first,  … [line truncated: 1238 more bytes on this line]
{"name":"path_between","description":"Does A REACH B, and HOW? — the shortest directed CALL path between two symbols, hop-by-hop. reachable=\"0\" hops=\"0\" is a valid 'not reachable' answer — call edges are name-based, so a missing dynamic/callback edge can hide a real path. Named path_between  … [line truncated: 709 more bytes on this line]
{"name":"connect","description":"When a task touches 2..16 named symbols, returns the minimal subgraph RELATING them - terminals, the fewest joining intermediaries (with signatures), and call edges in true direction - finding the shared-caller joins a directed path_between cannot; unrelated symbols  … [line truncated: 950 more bytes on this line]
{"name":"explore","description":"ONE-call task orientation: the routed+anchored ranking, full bodies of the top hits, their 1-hop callers, field notes, and tests_to_run — ALL under one deterministic byte budget, in a fixed section order (ranking > bodies > callers > notes > tests) that degrades gr … [line truncated: 2135 more bytes on this line]
{"name":"from_trace","description":"Paste a stack trace / sanitizer report / compiler error and get it mapped onto indexed symbols, ranked INNERMOST-first: the parsed <trace> frame map, the ranked suspects' signatures, and the innermost in-corpus symbol's FULL body. Out-of-corpus frames are listed a … [line truncated: 1233 more bytes on this line]
{"name":"edit_check","description":"Just edited a symbol? Did its CONTRACT (param count + publicness) change vs git HEAD, and which 1-hop callers are NOW INCOMPATIBLE with the new arity by fixed-arity evidence (not a guess — every folded definition disagrees)? This is call sites worth OPENING, not … [line truncated: 1908 more bytes on this line]
{"name":"whereis","description":"WHERE DOES THIS CONTENT LIVE? Which branch's tree defines or mentions a symbol, HEAD first, with on-head=0 naming the case this verb exists for: content that lives only on a branch (a finished fix stranded on 1 of 30 refs). Each distinct blob is read once (content-ad … [line truncated: 1475 more bytes on this line]
{"name":"stray_content","description":"Per branch: the lines its own divergent work AUTHORED (vs its merge-base with HEAD) that the live line does NOT have. Four verdicts (unmerged+superseded+merged+unknown=refs): v=unmerged is genuinely absent; v=superseded means the live line re-implemented the wo … [line truncated: 1123 more bytes on this line]
{"name":"flags","description":"WHAT IS BUILT BUT DARK here — the answer to 'why don't I see feature X?'. Harvests all three gate patterns (ifndef/define header gates, CMake option(), getenv reads) with each gate's kind, DEFAULT, the size of the code it guards, and its read sites. When a name is bo … [line truncated: 1434 more bytes on this line]
{"name":"doc_drift","description":"WHICH OF THIS REPO'S DOC CLAIMS ARE NOW FALSE. Verifies the CHECKABLE anchors in every markdown file against the live index and returns ONLY the ones that no longer hold: file:line refs (missing-file / past-eof / line-moved), backticked symbol mentions (undefined), … [line truncated: 1167 more bytes on this line]
{"name":"slice","description":"WHERE IS THIS VARIABLE DEFINED AND USED inside one function — NAME-BASED intra-procedural def-use rows of one variable inside ONE uniquely-resolved definition (the ARISE slicer, arXiv:2605.03117). symbol alone lists the sliceable locals to pick from; add var (or spel … [line truncated: 1722 more bytes on this line]
{"name":"batch","description":"ONE-TURN CONTEXT SWEEP: answer up to 16 heterogeneous READ sub-queries in a single call (the deterministic $0 counterpart of a parallel-search agent). queries = array over the SAME path, in EITHER grammar: {verb, ...args} objects, or the CLI --batch file's own \"verb:a … [line truncated: 2040 more bytes on this line]
`````

The manifest, summarised (name / description bytes / required args) — what the host pays in context every session:

`````
tools= 33  manifest_bytes= 47447  (~tokens at 4 bytes/token: 11861 )
explore                      desc_bytes= 1340 schema_bytes=  958 required=['task']
batch                        desc_bytes= 1235 schema_bytes=  962 required=['queries']
edit_check                   desc_bytes= 1180 schema_bytes=  889 required=['symbol']
slice                        desc_bytes=  953 schema_bytes=  932 required=['symbol']
whereis                      desc_bytes=  701 schema_bytes=  941 required=['symbol']
flags                        desc_bytes=  881 schema_bytes=  720 required=[]
exemplar                     desc_bytes=  951 schema_bytes=  591 required=[]
replace_symbol_body          desc_bytes=  865 schema_bytes=  610 required=['symbol', 'new_body']
impact                       desc_bytes=  821 schema_bytes=  666 required=['symbol']
situational_awareness        desc_bytes=  865 schema_bytes=  581 required=[]
affected                     desc_bytes=  790 schema_bytes=  610 required=['files']
from_trace                   desc_bytes=  836 schema_bytes=  559 required=['trace']
find_symbol                  desc_bytes=  752 schema_bytes=  590 required=['symbol']
doc_drift                    desc_bytes=  728 schema_bytes=  604 required=[]
uses                         desc_bytes=  626 schema_bytes=  682 required=['symbol']
stray_content                desc_bytes=  678 schema_bytes=  604 required=[]
rank_by                      desc_bytes=  758 schema_bytes=  481 required=[]
for                          desc_bytes=  453 schema_bytes=  777 required=['task']
fetch_body                   desc_bytes=  623 schema_bytes=  588 required=['handle']
connect                      desc_bytes=  535 schema_bytes=  580 required=['symbols']
find_referencing_symbols     desc_bytes=  505 schema_bytes=  590 required=['symbol']
insert_after_symbol          desc_bytes=  458 schema_bytes=  577 required=['symbol', 'text']
insert_before_symbol         desc_bytes=  455 schema_bytes=  578 required=['symbol', 'text']
owners                       desc_bytes=  425 schema_bytes=  625 required=[]
quality_delta                desc_bytes=  742 schema_bytes=  279 required=[]
lego                         desc_bytes=  360 schema_bytes=  651 required=['type']
grep                         desc_bytes=  445 schema_bytes=  562 required=['pattern']
memory_recall                desc_bytes=  447 schema_bytes=  500 required=['task']
path_between                 desc_bytes=  357 schema_bytes=  506 required=['from', 'to']
cochange                     desc_bytes=  393 schema_bytes=  476 required=['file']
analyze                      desc_bytes=  546 schema_bytes=  318 required=[]
mentions                     desc_bytes=  305 schema_bytes=  486 required=['symbol']
quality_baseline             desc_bytes=  407 schema_bytes=  193 required=[]
`````

## `printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize"}' '{"jsonrpc":"2.0","id":2,"method":"tools/list"}' | ./build/ripwire --mcp --mcp-tools=core`

*--mcp-tools=core: the server lists only the core profile's tools (explore, batch, from_trace, impact, uses, fetch_body, edit_check, quality_delta), so a host that loads every schema at session start pays only for those.*

**wall time: 1.82s**

`````
{"jsonrpc":"2.0","id":1,"result":{"protocolVersion":"2025-11-25","serverInfo":{"name":"ripwire","version":"1.0"},"capabilities":{"tools":{},"resources":{}},"instructions":"Map before reading files. Start a new task with explore; use from_trace for an error; use impact plus uses before changing a sym … [line truncated: 955 more bytes on this line]
{"jsonrpc":"2.0","id":2,"result":{"tools":[{"name":"fetch_body","description":"Full (or partial-range) source of a symbol's definition, addressed by the stable `handle` a read verb attached to it (bodies on request, not by default). start_line/end_line are optional, 1-based, INCLUSIVE and BODY-RELAT … [line truncated: 1092 more bytes on this line]
{"name":"quality_delta","description":"Your PR self-check, run every time you think a change is DONE — pairs with the CLI-only --test-gate (names the tests to run + the untested blast radius; not MCP-exposed) to form the two-step pre-PR gate. Reports ONLY what your working tree made WORSE vs basel … [line truncated: 862 more bytes on this line]
{"name":"impact","description":"IS IT SAFE TO CHANGE X? — the TRANSITIVE blast radius of a symbol via calls, nearest first (d= hop depth), then PageRank. Use before modifying or deleting a symbol; it beats find_referencing_symbols (direct callers only), and 'uses' catches the read/write/import sit … [line truncated: 1325 more bytes on this line]
{"name":"uses","description":"The STATICALLY RESOLVABLE use-sites of a symbol, not just calls: role (call | read | write | import | extends), file:line, and enclosing symbol. Use to see the footprint before renaming or changing a name — find_referencing_symbols and impact follow only calls. extern … [line truncated: 1146 more bytes on this line]
{"name":"explore","description":"ONE-call task orientation: the routed+anchored ranking, full bodies of the top hits, their 1-hop callers, field notes, and tests_to_run — ALL under one deterministic byte budget, in a fixed section order (ranking > bodies > callers > notes > tests) that degrades gr … [line truncated: 2135 more bytes on this line]
{"name":"from_trace","description":"Paste a stack trace / sanitizer report / compiler error and get it mapped onto indexed symbols, ranked INNERMOST-first: the parsed <trace> frame map, the ranked suspects' signatures, and the innermost in-corpus symbol's FULL body. Out-of-corpus frames are listed a … [line truncated: 1233 more bytes on this line]
{"name":"edit_check","description":"Just edited a symbol? Did its CONTRACT (param count + publicness) change vs git HEAD, and which 1-hop callers are NOW INCOMPATIBLE with the new arity by fixed-arity evidence (not a guess — every folded definition disagrees)? This is call sites worth OPENING, not … [line truncated: 1908 more bytes on this line]
{"name":"batch","description":"ONE-TURN CONTEXT SWEEP: answer up to 16 heterogeneous READ sub-queries in a single call (the deterministic $0 counterpart of a parallel-search agent). queries = array over the SAME path, in EITHER grammar: {verb, ...args} objects, or the CLI --batch file's own \"verb:a … [line truncated: 2040 more bytes on this line]
`````

The core manifest, summarised (name / description bytes / required args):

`````
tools= 8  manifest_bytes= 14186  (~tokens at 4 bytes/token: 3546 )
explore                      desc_bytes= 1340 schema_bytes=  958 required=['task']
batch                        desc_bytes= 1235 schema_bytes=  962 required=['queries']
edit_check                   desc_bytes= 1180 schema_bytes=  889 required=['symbol']
impact                       desc_bytes=  821 schema_bytes=  666 required=['symbol']
from_trace                   desc_bytes=  836 schema_bytes=  559 required=['trace']
uses                         desc_bytes=  626 schema_bytes=  682 required=['symbol']
fetch_body                   desc_bytes=  623 schema_bytes=  588 required=['handle']
quality_delta                desc_bytes=  742 schema_bytes=  279 required=[]
`````

## `printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize"}' '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"for","arguments":{"path":".","task":"pagerank power iteration"}}}' | ./build/ripwire --mcp`

*MCP `for`: always bundle=sigs (never the CLI's compact route), the same ranked signatures as --for.*

**wall time: 9.47s**

`````
{"jsonrpc":"2.0","id":1,"result":{"protocolVersion":"2025-11-25","serverInfo":{"name":"ripwire","version":"1.0"},"capabilities":{"tools":{},"resources":{}},"instructions":"Map before reading files. Start a new task with explore; use from_trace for an error; use impact plus uses before changing a sym … [line truncated: 738 more bytes on this line]
{"jsonrpc":"2.0","id":2,"result":{"content":[{"type":"text","text":"<ctx task=\"pagerank power iteration\" route=\"subtoken+body\" root=\".\" confidence=\"high\" margin_pct=\"22\" at=\"0412539b9\" doc_mentions=\"5\" doc_mentions_capped=\"1\" doc_mentions_total=\"14\" bundle=\"sigs\" lens=\"churn,amp … [line truncated: 20832 more bytes on this line]
"_index":"[index: files=4497 symbols=39563 hash=683e05f8]","_fresh":"ok"}}
`````

## `printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize"}' '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"whereis","arguments":{"path":".","symbol":"rankGraphTeleport"}}}' '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"whereis","arguments":{"path":".","symbol":"computeOnePairOverlap"}}}' | ./build/ripwire --mcp --mcp-legend=inline`

*--mcp-legend=inline: every answer of the stdio session carries its own legend (the default, session, sends each definition once per session after the first answer).*

**wall time: 66.93s**

`````
{"jsonrpc":"2.0","id":1,"result":{"protocolVersion":"2025-11-25","serverInfo":{"name":"ripwire","version":"1.0"},"capabilities":{"tools":{},"resources":{}},"instructions":"Map before reading files. Start a new task with explore; use from_trace for an error; use impact plus uses before changing a sym … [line truncated: 735 more bytes on this line]
{"jsonrpc":"2.0","id":2,"result":{"content":[{"type":"text","text":"<!-- ripwire whereis schema=ripwire.whereis/v1: every LOCAL ref whose tree holds sym= (refs_scanned=, blobs=), HEAD first: <hit ref= tip= date= p= l= kind= t=>. window: shown= total= capped= has_more= next_offset= offset= limit= (ca … [line truncated: 13645 more bytes on this line]
"_index":"[index: files=4497 symbols=39563 hash=683e05f8]","_fresh":"ok"}}
{"jsonrpc":"2.0","id":3,"result":{"content":[{"type":"text","text":"<!-- ripwire whereis schema=ripwire.whereis/v1: every LOCAL ref whose tree holds sym= (refs_scanned=, blobs=), HEAD first: <hit ref= tip= date= p= l= kind= t=>. window: shown= capped= (capped=1 cut). at=: commit+dirty+shallow. next= … [line truncated: 2182 more bytes on this line]
"_index":"[index: files=4497 symbols=39563 hash=683e05f8]","_fresh":"ok"}}
`````

## `printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize"}' '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"explore","arguments":{"path":".","task":"add a new output format flag to the CLI","budget_tokens":2000}}}' | ./build/ripwire --mcp`

*MCP `explore` = --pack-task under a token budget, one call.*

**wall time: 4.54s**

`````
{"jsonrpc":"2.0","id":1,"result":{"protocolVersion":"2025-11-25","serverInfo":{"name":"ripwire","version":"1.0"},"capabilities":{"tools":{},"resources":{}},"instructions":"Map before reading files. Start a new task with explore; use from_trace for an error; use impact plus uses before changing a sym … [line truncated: 738 more bytes on this line]
{"jsonrpc":"2.0","id":2,"result":{"content":[{"type":"text","text":"<ctx schema=\"ripwire.pack-task/v1\" task=\"add a new output format flag to the CLI\" route=\"subtoken+body:declined(add;189-carriers,62-defs)\" root=\".\" dropped_positive=\"2\" est_tokens=\"1430\" budget_tokens=\"2000\"><!-- ripwi … [line truncated: 3836 more bytes on this line]
"_index":"[index: files=4497 symbols=39563 hash=683e05f8]","_fresh":"ok"}}
`````

## `printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize"}' '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"fetch_body","arguments":{"path":".","handle":"rankGraphTeleport"}}}' | ./build/ripwire --mcp`

*MCP `fetch_body`: the lazy-body handle posture — bodies only after ranked retrieval, by bare name here.*

**wall time: 3.99s**

`````
{"jsonrpc":"2.0","id":1,"result":{"protocolVersion":"2025-11-25","serverInfo":{"name":"ripwire","version":"1.0"},"capabilities":{"tools":{},"resources":{}},"instructions":"Map before reading files. Start a new task with explore; use from_trace for an error; use impact plus uses before changing a sym … [line truncated: 738 more bytes on this line]
{"jsonrpc":"2.0","id":2,"result":{"content":[{"type":"text","text":"{\"resolved_from_name\":\"rankGraphTeleport\",\"handle\":\"sym#cfb3dc25a9d1fa2c@d34b0399e8303cb3\",\"name\":\"rankGraphTeleport\",\"kind\":\"fn\",\"file\":\"src/graph.h\",\"line\":13631,\"start_line\":1,\"end_line\":29,\"total_lines … [line truncated: 1330 more bytes on this line]
"_index":"[index: files=4497 symbols=39563 hash=683e05f8]","_fresh":"ok"}}
`````

## `printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize"}' '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"grep","arguments":{"path":".","pattern":"DISCLOSE","limit":3}}}' | ./build/ripwire --mcp`

*MCP `grep` with paging args.*

**wall time: 5.80s**

`````
{"jsonrpc":"2.0","id":1,"result":{"protocolVersion":"2025-11-25","serverInfo":{"name":"ripwire","version":"1.0"},"capabilities":{"tools":{},"resources":{}},"instructions":"Map before reading files. Start a new task with explore; use from_trace for an error; use impact plus uses before changing a sym … [line truncated: 738 more bytes on this line]
{"jsonrpc":"2.0","id":2,"result":{"content":[{"type":"text","text":"{\"pattern\":\"DISCLOSE\",\"root\":\".\",\"files\":274,\"shown\":3,\"capped\":true,\"total\":934,\"has_more\":true,\"next_offset\":3,\"offset\":0,\"limit\":3,\"hits_capped\":false,\"next\":\"--grep=DISCLOSE --offset=3 --legend=compa … [line truncated: 609 more bytes on this line]
{\"file\":\"src/abicheck.h\",\"line\":494,\"in\":\"abicheck::collectAuthoredSites\",\"parse_degraded\":true,\"text\":\"            DISCLOSE( result, AbiResult::DisclosureWhy::NoMergeBase, \\\"abi: no merge-base for a ref (unrelated history?) — that ref is counted, not compared\\\" );\"},
{\"file\":\"src/arch.h\",\"line\":511,\"in\":\"rw::parseArchRules\",\"text\":\"        DISCLOSE( Diagnostics::answerRefused, \\\"--arch exits 1 with path:line and the reason on stderr; no report is printed\\\",\"}],\"parse_degraded_note\":\"a hit carrying parse_degraded:true sits in a file whose par … [line truncated: 465 more bytes on this line]
{\"file\":\"CMakeLists.txt\",\"line\":347},
{\"file\":\"CMakeLists.txt\",\"line\":894}]},\"enclosing\":[{\"n\":\"path_instructions\",\"callers\":0,\"handle_omitted\":\"non-code\"},
{\"n\":\"abicheck::collectAuthoredSites\",\"callers\":1,\"cx\":9,\"handle\":\"sym#1ab32951dcc2d860@b046719c64b5631a\"},
{\"n\":\"rw::parseArchRules\",\"callers\":2,\"cx\":33,\"handle\":\"sym#f5dd171cfba47899@43229c90b4c23588\"}]}"}],
"_index":"[index: files=4497 symbols=39563 hash=683e05f8]","_fresh":"ok"}}
`````

## `printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize"}' '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"slice","arguments":{"path":".","symbol":"rankGraphTeleport","var":"teleport","flow":"back","depth":3}}}' | ./build/ripwire --mcp`

*MCP `slice` — the CLI's --slice/--slice-flow/--slice-depth as one verb.*

**wall time: 7.28s**

`````
{"jsonrpc":"2.0","id":1,"result":{"protocolVersion":"2025-11-25","serverInfo":{"name":"ripwire","version":"1.0"},"capabilities":{"tools":{},"resources":{}},"instructions":"Map before reading files. Start a new task with explore; use from_trace for an error; use impact plus uses before changing a sym … [line truncated: 738 more bytes on this line]
{"jsonrpc":"2.0","id":2,"result":{"content":[{"type":"text","text":"<!-- ripwire slice schema=ripwire.slice/v1: name-based def-use rows of one variable in one definition: <s l= k=def|use|both|scope t= [b= pp= rd=]> (rd= reaching-def lines per reach=cfg|linear), <v n= l= t=> inventory; steps=/depth=  … [line truncated: 1777 more bytes on this line]
"_index":"[index: files=4497 symbols=39563 hash=683e05f8]","_fresh":"ok"}}
`````

## `printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize"}' '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"find_symbol","arguments":{"path":".","symbol":"DoesNotExist"}}}' | ./build/ripwire --mcp`

*MCP error shape: an unknown symbol comes back as a JSON-RPC error/refusal, not an empty success.*

**wall time: 6.77s**

`````
{"jsonrpc":"2.0","id":1,"result":{"protocolVersion":"2025-11-25","serverInfo":{"name":"ripwire","version":"1.0"},"capabilities":{"tools":{},"resources":{}},"instructions":"Map before reading files. Start a new task with explore; use from_trace for an error; use impact plus uses before changing a sym … [line truncated: 738 more bytes on this line]
{"jsonrpc":"2.0","id":2,"error":{"code":-32602,"message":"symbol not found: 'DoesNotExist' — pass the final name segment; add scope to disambiguate — or @FILE:LINE when you hold a location — note: the lexical definition scan stopped at its budget, 4096 files or 16 MiB, before reading every fil … [line truncated: 165 more bytes on this line]
`````

## `printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize"}' '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"batch","arguments":{"path":".","queries":[{"verb":"for","task":"incremental cache invalidation"},{"verb":"find_referencing_symbols","symbol":"rankGraphTeleport"},{"verb":"grep","pattern":"DISCLOSE","limit":2}]}}}' | ./build/ripwire --mcp`

*MCP `batch`: three independent read queries answered in ONE round-trip — NOTE the sub-query grammar is {verb, ...args} objects with MCP verb names, not the CLI --batch file's verb:arg lines.*

**wall time: 5.29s**

`````
{"jsonrpc":"2.0","id":1,"result":{"protocolVersion":"2025-11-25","serverInfo":{"name":"ripwire","version":"1.0"},"capabilities":{"tools":{},"resources":{}},"instructions":"Map before reading files. Start a new task with explore; use from_trace for an error; use impact plus uses before changing a sym … [line truncated: 738 more bytes on this line]
{"jsonrpc":"2.0","id":2,"result":{"content":[{"type":"text","text":"<batch schema=\"ripwire.batch/v1\" n=\"3\" requested=\"3\" cap=\"16\"><!-- ripwire batch schema=ripwire.batch/v1: n= read sub-queries in one sweep (requested=, cap=): each <q> wraps one sub-answer verbatim in CDATA. i=/verb=/ok=: su … [line truncated: 27750 more bytes on this line]
{\"name\":\"rankGraph\",\"kind\":\"fn\",\"file\":\"src/graph.h\",\"line\":13674,\"handle\":\"sym#b90da690b120eeb3@d34b0399e8303cb3\",\"sites_at\":[\"src/graph.h:13678\"]},
{\"name\":\"anchoredLexicalRank\",\"kind\":\"fn\",\"file\":\"src/graph.h\",\"line\":14321,\"handle\":\"sym#b3a5ca7873636567@d34b0399e8303cb3\",\"sites_at\":[\"src/graph.h:14372\"]},
{\"name\":\"runEval\",\"kind\":\"fn\",\"file\":\"src/eval.h\",\"line\":171,\"handle\":\"sym#358fe2cb69804698@1f9d26ff6c500240\",\"sites_at\":[\"src/eval.h:328\"]},
{\"name\":\"churnDecayRanking\",\"kind\":\"fn\",\"file\":\"src/main.cpp\",\"line\":1433,\"handle\":\"sym#f43b7580f05a651a@aac8a4dc17883754\",\"sites_at\":[\"src/main.cpp:1447\"]},
{\"name\":\"churnRankedGraph\",\"kind\":\"fn\",\"file\":\"src/main.cpp\",\"line\":1472,\"handle\":\"sym#4b5b63d3932ca0ff@aac8a4dc17883754\",\"sites_at\":[\"src/main.cpp:1486\",\"src/main.cpp:1487\",\"src/main.cpp:1501\"]},
{\"name\":\"runDefaultMap\",\"kind\":\"fn\",\"file\":\"src/main.cpp\",\"line\":1759,\"handle\":\"sym#6e2725cb96590ec8@aac8a4dc17883754\",\"sites_at\":[\"src/main.cpp:1879\"]}],\"sites_note\":\"sites_at= on a caller row: its calls of the called LEAF name, any receiver or qualifier, as file:line token … [line truncated: 1242 more bytes on this line]
{\"file\":\"src/abicheck.h\",\"line\":494,\"in\":\"abicheck::collectAuthoredSites\",\"parse_degraded\":true,\"text\":\"            DISCLOSE( result, AbiResult::DisclosureWhy::NoMergeBase, \\\"abi: no merge-base for a ref (unrelated history?) — that ref is counted, not compared\\\" );\"}],\"parse_d … [line truncated: 541 more bytes on this line]
{\"file\":\"CMakeLists.txt\",\"line\":347}]},\"enclosing\":[{\"n\":\"path_instructions\",\"callers\":0,\"handle_omitted\":\"non-code\"},
{\"n\":\"abicheck::collectAuthoredSites\",\"callers\":1,\"cx\":9,\"handle\":\"sym#1ab32951dcc2d860@b046719c64b5631a\"}]}]]></q></batch>"}],
"_index":"[index: files=4497 symbols=39563 hash=683e05f8]","_fresh":"ok"}}
`````

## `printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize"}' '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"batch","arguments":{"path":".","queries":["for:incremental cache invalidation","callers:rankGraphTeleport"]}}}' | ./build/ripwire --mcp`

*The CLI --batch spelling handed to MCP `batch`: refused, with the accepted shape named.*

**wall time: 8.67s**

`````
{"jsonrpc":"2.0","id":1,"result":{"protocolVersion":"2025-11-25","serverInfo":{"name":"ripwire","version":"1.0"},"capabilities":{"tools":{},"resources":{}},"instructions":"Map before reading files. Start a new task with explore; use from_trace for an error; use impact plus uses before changing a sym … [line truncated: 738 more bytes on this line]
{"jsonrpc":"2.0","id":2,"result":{"content":[{"type":"text","text":"<batch schema=\"ripwire.batch/v1\" n=\"2\" requested=\"2\" cap=\"16\"><!-- ripwire batch schema=ripwire.batch/v1: n= read sub-queries in one sweep (requested=, cap=): each <q> wraps one sub-answer verbatim in CDATA. i=/verb=/ok=: su … [line truncated: 27733 more bytes on this line]
{\"name\":\"rankGraph\",\"kind\":\"fn\",\"file\":\"src/graph.h\",\"line\":13674,\"handle\":\"sym#b90da690b120eeb3@d34b0399e8303cb3\",\"sites_at\":[\"src/graph.h:13678\"]},
{\"name\":\"anchoredLexicalRank\",\"kind\":\"fn\",\"file\":\"src/graph.h\",\"line\":14321,\"handle\":\"sym#b3a5ca7873636567@d34b0399e8303cb3\",\"sites_at\":[\"src/graph.h:14372\"]},
{\"name\":\"runEval\",\"kind\":\"fn\",\"file\":\"src/eval.h\",\"line\":171,\"handle\":\"sym#358fe2cb69804698@1f9d26ff6c500240\",\"sites_at\":[\"src/eval.h:328\"]},
{\"name\":\"churnDecayRanking\",\"kind\":\"fn\",\"file\":\"src/main.cpp\",\"line\":1433,\"handle\":\"sym#f43b7580f05a651a@aac8a4dc17883754\",\"sites_at\":[\"src/main.cpp:1447\"]},
{\"name\":\"churnRankedGraph\",\"kind\":\"fn\",\"file\":\"src/main.cpp\",\"line\":1472,\"handle\":\"sym#4b5b63d3932ca0ff@aac8a4dc17883754\",\"sites_at\":[\"src/main.cpp:1486\",\"src/main.cpp:1487\",\"src/main.cpp:1501\"]},
{\"name\":\"runDefaultMap\",\"kind\":\"fn\",\"file\":\"src/main.cpp\",\"line\":1759,\"handle\":\"sym#6e2725cb96590ec8@aac8a4dc17883754\",\"sites_at\":[\"src/main.cpp:1879\"]}],\"sites_note\":\"sites_at= on a caller row: its calls of the called LEAF name, any receiver or qualifier, as file:line token … [line truncated: 370 more bytes on this line]
"_index":"[index: files=4497 symbols=39563 hash=683e05f8]","_fresh":"ok"}}
`````

## `printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize"}' '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"edit_check","arguments":{"path":".","symbol":"rankGraphTeleport"}}}' | ./build/ripwire --mcp`

*MCP `edit_check` on a CLEAN tree.*

**wall time: 16.96s**

`````
{"jsonrpc":"2.0","id":1,"result":{"protocolVersion":"2025-11-25","serverInfo":{"name":"ripwire","version":"1.0"},"capabilities":{"tools":{},"resources":{}},"instructions":"Map before reading files. Start a new task with explore; use from_trace for an error; use impact plus uses before changing a sym … [line truncated: 738 more bytes on this line]
{"jsonrpc":"2.0","id":2,"result":{"content":[{"type":"text","text":"<!-- ripwire edit-check schema=ripwire.edit-check/v1: sym='s contract NOW vs HEAD: status=unchanged|new-symbol|contract-change; <c n= p= incompatible=1 sites_l=> callers. counts_floor=1: every count is a FLOOR, never a total. graph_ … [line truncated: 1170 more bytes on this line]
"_index":"[index: files=4497 symbols=39563 hash=683e05f8]","_fresh":"ok"}}
`````

## `printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize"}' '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"edit_check","arguments":{"path":".","symbol":"rankGraphTeleport","legend":"compact"}}}' | ./build/ripwire --mcp`

*The same MCP `edit_check` with legend:"compact" — the CLI --legend=compact dialect on the MCP side (declared on the 16 XML verbs): ~5.5 KB of legend down to ~600 B, rows identical; an unknown or empty legend value is refused, never read as the default.*

**wall time: 16.45s**

`````
{"jsonrpc":"2.0","id":1,"result":{"protocolVersion":"2025-11-25","serverInfo":{"name":"ripwire","version":"1.0"},"capabilities":{"tools":{},"resources":{}},"instructions":"Map before reading files. Start a new task with explore; use from_trace for an error; use impact plus uses before changing a sym … [line truncated: 738 more bytes on this line]
{"jsonrpc":"2.0","id":2,"result":{"content":[{"type":"text","text":"<!-- ripwire edit-check schema=ripwire.edit-check/v1: sym='s contract NOW vs HEAD: status=unchanged|new-symbol|contract-change; <c n= p= incompatible=1 sites_l=> callers. counts_floor=1: every count is a FLOOR, never a total. graph_ … [line truncated: 1170 more bytes on this line]
"_index":"[index: files=4497 symbols=39563 hash=683e05f8]","_fresh":"ok"}}
`````

## `printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize"}' '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"nosuchverb","arguments":{"path":"."}}}' | ./build/ripwire --mcp`

*An unknown verb name — the JSON-RPC error shape.*

`````
{"jsonrpc":"2.0","id":1,"result":{"protocolVersion":"2025-11-25","serverInfo":{"name":"ripwire","version":"1.0"},"capabilities":{"tools":{},"resources":{}},"instructions":"Map before reading files. Start a new task with explore; use from_trace for an error; use impact plus uses before changing a sym … [line truncated: 738 more bytes on this line]
{"jsonrpc":"2.0","id":2,"error":{"code":-32602,"message":"unknown tool: 'nosuchverb' — call tools/list for the 33 available tools"}}
`````
