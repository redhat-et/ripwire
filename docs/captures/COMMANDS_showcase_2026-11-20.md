# ripwire — every verb, run for real

- **Date:** 2026-11-20 (regenerated capture; supersedes any older `docs/captures/COMMANDS_showcase_*.md`)
- **Lives in `docs/captures/`** — a directory the crawl/retrieval lenses SKIP (`kCrawlSkipDirs`, src/ingest.h): a generated doc that quotes every verb's output out-scores the source for any query about the tool and was measured at 77% of `--recall` on this repo when it sat at the root. `test/argvdiffcheck.sh` harvests its `## `-heading command lines as differential vectors — keep that format.
- **Version:** `ripwire 0.6.10-dev.139+g6ace381eb (dev, AppleClang 21.0.0.21000101, emit=std::print, built_from=6ace381eb)`
- **Repo:** the ripwire repo @ `6ace381eb` — **CLEAN — `git status --porcelain` is empty**. The diff-aware verbs (`--situ`/`--test-gate`/`--quality-delta`/`--pr-context`/`--map-diff`/`--edit-check`) answer a question about the WORKING TREE, so that condition is part of their answer and every one of their captions below states which tree it recorded against. A clean tree is the honest default for a showcase, so they appear TWICE: once here on the clean tree (their empty/exit-0 shape) and once in the final section against a throwaway `git clone --local` sandbox carrying one deliberate regression, so their real gating shapes are visible without writing a byte into the read-only repo.
- **Corpus:** the ripwire repo itself (dogfood), via `./build/ripwire`
- **Sandbox diff** (the last section only): `.ripwire_notes        |  2 ++
 .ripwire_quality_acks |  1 +
 src/infra/sortutil.h  | 31 ++++++++++++++++++++++++++++---
 3 files changed, 31 insertions(+), 3 deletions(-)` — one preexisting function made deeply nested, one function's arity changed 1 -> 2, one copy-paste duplicate helper, one new 8-parameter public function.

**How to read the blocks:** ripwire's real XML output is minified — often ONE long line. For scanability, long minified lines are displayed re-wrapped with a line break at every tag seam (`><`). Header COMMENT lines (the legends) always appear in full — they are exempt from the per-line cut; any OTHER display line over 300 bytes is cut with a `… [line truncated: N more bytes]` marker, which can hit a long root element or row. `--plan-lanes` emits JSON and is re-wrapped at object seams the same way. Long outputs are cut to their first ~30 display lines with a `… [N more display lines; full output is M bytes]` marker giving the true size. Exit codes are recorded when non-zero; wall time when >1s.

**Not run (and why):** `ripwire <git-url>` (network clone), `--legend-have` (a per-CALLER handshake — the caller names the legend dictionary version it already holds — so a one-shot capture has nothing to hold and nothing to show; gated by `test/legendhavecheck.sh`), `--listen` / `--mcp-token` / `--allow-remote-edits` (the HTTP-server posture; `--mcp` itself IS captured in its own section as a one-shot stdio JSON-RPC exchange, and `wrap claude` shows the wiring), `--arch --baseline[-update]` (state writer against the read-only repo — `--note-add` / `--quality-baseline` / `--quality-ack` / the three edit verbs / `--edit-plan` ARE shown, inside the throwaway sandbox clone; `--index-out` / `--pin-census` write to scratch), `--eval-mined` (needs a `minedpair.jsonl` artifact from `bench/mine_traces.py`; none present in the tree), `--refetch` (git-url only), `--lsp` / `--lsp-langmap` (the editor transport and its language-map config — their one-shot dialogues, including every map and hint arm, are gated by `test/lspcheck.sh`, not by showcase blocks), `--max-memory` (the memory guard is silent on this repo by construction; its stops are gated by `test/memguardcheck.sh`), `--force` (wrap-only modifier), `--deadline-ms` (a timing modifier on `--help-task`: a warm index prints exactly the `--help-task` blocks shown only when it finishes within the deadline (a warm run past it abstains as well), and the cold abstention depends on wall-clock timing; gated by `test/helptaskdeadlinecheck.sh`), `--scan-skills` bare form (would sweep `~/.claude/skills`; the explicit-DIR form is shown instead), `--help` (217 lines — read it from the binary).


---

# understand a codebase cold

## `./build/ripwire .`

*The default ranked symbol map — start here when landing cold in a repo.*

**wall time: 2.61s**

`````
<!-- ripwire map schema=ripwire.map/v1: ranked symbol map: <f p= layer=> groups <s t= n= sc= k= amb=> rows (k= rank), <c n=> resolved callees; the header comment is data. est_tokens=: price as emitted (an upper bound under compact). root=: p= relative to it. pr_iters=N: PageRank iterations. data_sections_cut=N: N data Sections (headings, data keys) swapped out of this top-K for lower-ranked code rows; next= pages them first. <inv listed= unlisted=>: files the ranked rows show / do not (sum = files=), each named or counted below. <entry p= n=>: a program entry by its language's convention (C/Go/Rust main, Java/C# static main, a script main its module scope calls, __main__.py), callees as c rows; manifest entries not read. <ls p= n= f=>: n= unshown files under dir p=; f= names its code files, the rest (tests, docs, config, test/doc/example dirs) counted. declined=K: K call sites without edges, including inert Elixir quote sites after unquote/unquote_splicing re-entry. external=K: K calls proven outside the tree, no edge. locality_pinned=K: K calls pinned by locality alone (a guess). extent_suspect_syms=K: K defs failed containment, corpus-wide. macro_blanked_files=K: K files indexed from a macro-blanked re-parse. overloads=N: N same-name defs merged in this row; shown= counts each. prov=scip|binding|import|split|final-segment: how that <c> edge bound (absent: one unique name); split = one arm of an amb= pick; final-segment = a qualified type matched by last name only. files=/symbols=: files and symbols indexed; edges= distinct call edges; shown= symbols printed, a merged row counting each def; ambiguous= calls split over several defs, corpus-wide; unresolved= calls with in-tree evidence and no edge (every def language-filtered or unreachable, or binding refused); order= rows by rank (important-first, important-last; (auto:fill) = flipped past a size threshold) or by path (stable). skipped_oversize=K: K files over a size ceiling, not indexed. unindexed=ext:N: N text files of that extension no grammar reads (6 extensions at most). unindexed_exts=E: E such extensions in all, the list cut. <c via="name">: that callee matched by name alone (receiver unproven); it does NOT mean the edge is false. <c x=N>: N same-named via=name rows merged; callees=FILE:SYM lists all. sc=: enclosing scope; the full id is p::sc::n (p= of the row or its <f>) and selectors take it. amb=K: K calls split over several defs. next=: the one pasteable follow-up. -->
<!-- t=modscope=a-file's-MODULE-SCOPE(n=<file-scope>):the-statements-outside-every-named-definition,where-a-top-level-call-and-an-anonymous-callback-body's-calls-live;a-CALLER-never-a-callee(nothing-in-the-source-can-name-it)-with-no-body-to-expand;a-file-with-no-such-call-has-no-such-row -->
<!-- t=type|alias|functype=a-Go-named-type-by-its-written-form:type=a-defined-type-whose-WRITTEN-form-is-not-a-struct/iface/func-literal(type-N-string;type-W-Pair-too,whatever-Pair-is-underneath),alias=type-A=B,functype=type-F-func(...) -->
<!-- t=alias|functype-in-C++-and-.h:alias=using-X=Y(also-templated-or-class-scope)or-namespace-L=lib(defs=X-prints-its-written-target-as-to=),functype=a-typedef-of-a-function-or-function-pointer-type(typedef-void(*F)(int));other-typedefs-read-t=struct -->
<!-- stem="1": the class/struct/interface a file is named for (2+ name words, all in the file name), added after the file's top-K rows because the rank cut left it out (no kept row dropped; counted in shown=) -->
<!-- files=4838 symbols=44600 edges=44429 shown=205 est_tokens=10513 ambiguous=3634 unresolved=20069 locality_pinned=14 external=12457 declined=45295 extent_suspect_syms=12 macro_blanked_files=7 skipped_oversize=15 unindexed="txt:85,tsv:54,mod:33,xml:33,jsonl:26,scm:25" unindexed_exts=23 order=important-first -->
<r schema="ripwire.map/v1" root="." est_tokens="10513" pr_iters="40" data_sections_cut="1" next="--graph-query='kind(all,sec)' --offset=0 --limit=200">
<f p="src/infra/nodekind.h" layer="infra">
<s t="fn" n="kindIs" sc="rw" k="0.0031">
</s>
</f>
<f p="src/ingest_metrics.h">
<s t="fn" n="nodeTextOf" k="0.0021">
</s>
</f>
<f p="src/infra/namesplit.h" layer="infra">
<s t="fn" n="isIdentChar" sc="namesplit" k="0.0020">
</s>
<s t="fn" n="afterLast" sc="namesplit" k="0.0006">
<c n="EXPECTS"/>
</s>
<s t="fn" n="isIdentStart" sc="namesplit" k="0.0003">
<c n="isIdentChar"/>
</s>
</f>
<f p="src/model.h">
<s t="fn" n="relForHash" sc="rw" k="0.0019">
</s>
<s t="fn" n="rootRelPath" sc="rw" k="0.0018">
<c n="relForHash"/>
… [762 more display lines; full output is 26094 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --top-k=5`

*Same map, capped to the 5 highest-ranked symbols.*

`````
<!-- ripwire map schema=ripwire.map/v1: ranked symbol map: <f p= layer=> groups <s t= n= sc= k= amb=> rows (k= rank), <c n=> resolved callees; the header comment is data. est_tokens=: price as emitted (an upper bound under compact). root=: p= relative to it. pr_iters=N: PageRank iterations. <inv listed= unlisted=>: files the ranked rows show / do not (sum = files=), each named or counted below. <entry p= n=>: a program entry by its language's convention (C/Go/Rust main, Java/C# static main, a script main its module scope calls, __main__.py), callees as c rows; manifest entries not read. <ls p= n= f=>: n= unshown files under dir p=; f= names its code files, the rest (tests, docs, config, test/doc/example dirs) counted. declined=K: K call sites without edges, including inert Elixir quote sites after unquote/unquote_splicing re-entry. external=K: K calls proven outside the tree, no edge. locality_pinned=K: K calls pinned by locality alone (a guess). extent_suspect_syms=K: K defs failed containment, corpus-wide. macro_blanked_files=K: K files indexed from a macro-blanked re-parse. prov=scip|binding|import|split|final-segment: how that <c> edge bound (absent: one unique name); split = one arm of an amb= pick; final-segment = a qualified type matched by last name only. files=/symbols=: files and symbols indexed; edges= distinct call edges; shown= symbols printed, a merged row counting each def; ambiguous= calls split over several defs, corpus-wide; unresolved= calls with in-tree evidence and no edge (every def language-filtered or unreachable, or binding refused); order= rows by rank (important-first, important-last; (auto:fill) = flipped past a size threshold) or by path (stable). skipped_oversize=K: K files over a size ceiling, not indexed. unindexed=ext:N: N text files of that extension no grammar reads (6 extensions at most). unindexed_exts=E: E such extensions in all, the list cut. sc=: enclosing scope; the full id is p::sc::n (p= of the row or its <f>) and selectors take it. -->
<!-- t=modscope=a-file's-MODULE-SCOPE(n=<file-scope>):the-statements-outside-every-named-definition,where-a-top-level-call-and-an-anonymous-callback-body's-calls-live;a-CALLER-never-a-callee(nothing-in-the-source-can-name-it)-with-no-body-to-expand;a-file-with-no-such-call-has-no-such-row -->
<!-- t=type|alias|functype=a-Go-named-type-by-its-written-form:type=a-defined-type-whose-WRITTEN-form-is-not-a-struct/iface/func-literal(type-N-string;type-W-Pair-too,whatever-Pair-is-underneath),alias=type-A=B,functype=type-F-func(...) -->
<!-- t=alias|functype-in-C++-and-.h:alias=using-X=Y(also-templated-or-class-scope)or-namespace-L=lib(defs=X-prints-its-written-target-as-to=),functype=a-typedef-of-a-function-or-function-pointer-type(typedef-void(*F)(int));other-typedefs-read-t=struct -->
<!-- files=4838 symbols=44600 edges=44429 shown=5 est_tokens=4111 ambiguous=3634 unresolved=20069 locality_pinned=14 external=12457 declined=45295 extent_suspect_syms=12 macro_blanked_files=7 skipped_oversize=15 unindexed="txt:85,tsv:54,mod:33,xml:33,jsonl:26,scm:25" unindexed_exts=23 order=important-first -->
<r schema="ripwire.map/v1" root="." est_tokens="4111" pr_iters="40">
<f p="src/infra/nodekind.h" layer="infra">
<s t="fn" n="kindIs" sc="rw" k="0.0031">
</s>
</f>
<f p="src/ingest_metrics.h">
<s t="fn" n="nodeTextOf" k="0.0021">
</s>
</f>
<f p="src/infra/namesplit.h" layer="infra">
<s t="fn" n="isIdentChar" sc="namesplit" k="0.0020">
</s>
</f>
<f p="src/model.h">
<s t="fn" n="relForHash" sc="rw" k="0.0019">
</s>
</f>
<f p="src/infra/Diagnostics.h" layer="infra">
<s t="macro" n="RW_ASSUME_" k="0.0018">
<c n="RW_CHECK_"/>
</s>
</f>
<inv listed="5" unlisted="4833">
<entry p="scripts/changelog_assemble.py" n="main">
<c n="repoRoot"/>
… [89 more display lines; full output is 10249 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --top-k=5 --no-inventory`

*The same capped map without its inventory tier: --top-k=5 leaves files out, so the default map appends <inv listed= unlisted=> (program entries, and the files the ranked rows left out) after its rows; --no-inventory drops that tier, and the ranked rows are the same.*

`````
<!-- ripwire map schema=ripwire.map/v1: ranked symbol map: <f p= layer=> groups <s t= n= sc= k= amb=> rows (k= rank), <c n=> resolved callees; the header comment is data. est_tokens=: price as emitted (an upper bound under compact). root=: p= relative to it. pr_iters=N: PageRank iterations. declined=K: K call sites without edges, including inert Elixir quote sites after unquote/unquote_splicing re-entry. external=K: K calls proven outside the tree, no edge. locality_pinned=K: K calls pinned by locality alone (a guess). extent_suspect_syms=K: K defs failed containment, corpus-wide. macro_blanked_files=K: K files indexed from a macro-blanked re-parse. files=/symbols=: files and symbols indexed; edges= distinct call edges; shown= symbols printed, a merged row counting each def; ambiguous= calls split over several defs, corpus-wide; unresolved= calls with in-tree evidence and no edge (every def language-filtered or unreachable, or binding refused); order= rows by rank (important-first, important-last; (auto:fill) = flipped past a size threshold) or by path (stable). skipped_oversize=K: K files over a size ceiling, not indexed. unindexed=ext:N: N text files of that extension no grammar reads (6 extensions at most). unindexed_exts=E: E such extensions in all, the list cut. sc=: enclosing scope; the full id is p::sc::n (p= of the row or its <f>) and selectors take it. -->
<!-- t=modscope=a-file's-MODULE-SCOPE(n=<file-scope>):the-statements-outside-every-named-definition,where-a-top-level-call-and-an-anonymous-callback-body's-calls-live;a-CALLER-never-a-callee(nothing-in-the-source-can-name-it)-with-no-body-to-expand;a-file-with-no-such-call-has-no-such-row -->
<!-- t=type|alias|functype=a-Go-named-type-by-its-written-form:type=a-defined-type-whose-WRITTEN-form-is-not-a-struct/iface/func-literal(type-N-string;type-W-Pair-too,whatever-Pair-is-underneath),alias=type-A=B,functype=type-F-func(...) -->
<!-- t=alias|functype-in-C++-and-.h:alias=using-X=Y(also-templated-or-class-scope)or-namespace-L=lib(defs=X-prints-its-written-target-as-to=),functype=a-typedef-of-a-function-or-function-pointer-type(typedef-void(*F)(int));other-typedefs-read-t=struct -->
<!-- files=4838 symbols=44600 edges=44429 shown=5 est_tokens=1206 ambiguous=3634 unresolved=20069 locality_pinned=14 external=12457 declined=45295 extent_suspect_syms=12 macro_blanked_files=7 skipped_oversize=15 unindexed="txt:85,tsv:54,mod:33,xml:33,jsonl:26,scm:25" unindexed_exts=23 order=important-first -->
<r schema="ripwire.map/v1" root="." est_tokens="1206" pr_iters="40">
<f p="src/infra/nodekind.h" layer="infra">
<s t="fn" n="kindIs" sc="rw" k="0.0031">
</s>
</f>
<f p="src/ingest_metrics.h">
<s t="fn" n="nodeTextOf" k="0.0021">
</s>
</f>
<f p="src/infra/namesplit.h" layer="infra">
<s t="fn" n="isIdentChar" sc="namesplit" k="0.0020">
</s>
</f>
<f p="src/model.h">
<s t="fn" n="relForHash" sc="rw" k="0.0019">
</s>
</f>
<f p="src/infra/Diagnostics.h" layer="infra">
<s t="macro" n="RW_ASSUME_" k="0.0018">
<c n="RW_CHECK_"/>
</s>
</f>
</r>
`````

## `./build/ripwire . --top-k=0 --expand=rankGraphTeleport`

*NEW since the last capture: --top-k=0 means PAYLOAD-ONLY — no ranked map rides along with the body you asked for.*

`````
<ctx schema="ripwire.expand/v1" root="." est_tokens="1227">
<!-- ripwire expand schema=ripwire.expand/v1: full bodies: <bodies shown= total= capped=> of <b t= l= p= n= sibs= sibs_total= sibs_capped= inc=>; <calls>
<c n= l= p=> resolved callees (p= when not the b's file). window: shown= total= capped= (capped=1 cut). sibs_capped=/inc_capped=: 1 = cut. est_tokens=: price as emitted (an upper bound under compact). root=: p= relative to it. inc_total=N: the file's true include/import count; inc= lists the first 2 … [line truncated: 303 more bytes on this line]
<bodies shown="1" total="1" capped="0">
<b t="fn" l="14619" p="src/graph.h" n="rankGraphTeleport" sibs="&lt;file-scope&gt;,DeclinedSiteKind,kNoDeclinedList,ProvenSite,operator&lt;=&gt;,provenSiteCountsFor,Graph,localityKeyAt,ImplementorRow,implementorClosure,LegoClosure,LegoClosureWalk,LegoClosureWalk,take,boundOf,add,expand,legoImplement … [line truncated: 1657 more bytes on this line]
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
}]]><calls total="4"><c n="biasPrior" l="14578">inline std::vector&lt;float&gt; biasPrior( const Graph&amp; g, const std::vector&lt;float&gt;&amp; p )</c><c n="PROFILE_SCOPE_DESCRIBE" l="1282" p="src/infra/profileScope.h">#define PROFILE_SCOPE_DESCRIBE( desc )</c><c n="PROFILE_SCOPE_DESCRIBE" l="129 … [line truncated: 368 more bytes on this line]
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
<!-- ripwire map schema=ripwire.map/v1: ranked symbol map: <f p= layer=> groups <s t= n= sc= k= amb=> rows (k= rank), <c n=> resolved callees; the header comment is data. est_tokens=: price as emitted (an upper bound under compact). over_ceiling=1: budget not met. root=: p= relative to it. pr_iters=N: PageRank iterations. declined=K: K call sites without edges, including inert Elixir quote sites after unquote/unquote_splicing re-entry. external=K: K calls proven outside the tree, no edge. locality_pinned=K: K calls pinned by locality alone (a guess). extent_suspect_syms=K: K defs failed containment, corpus-wide. macro_blanked_files=K: K files indexed from a macro-blanked re-parse. max_tokens=/fit_bytes=: tokens asked/the byte cap applied. files=/symbols=: files and symbols indexed; edges= distinct call edges; shown= symbols printed, a merged row counting each def; ambiguous= calls split over several defs, corpus-wide; unresolved= calls with in-tree evidence and no edge (every def language-filtered or unreachable, or binding refused); order= rows by rank (important-first, important-last; (auto:fill) = flipped past a size threshold) or by path (stable). skipped_oversize=K: K files over a size ceiling, not indexed. unindexed=ext:N: N text files of that extension no grammar reads (6 extensions at most). unindexed_exts=E: E such extensions in all, the list cut. sc=: enclosing scope; the full id is p::sc::n (p= of the row or its <f>) and selectors take it. -->
<!-- t=modscope=a-file's-MODULE-SCOPE(n=<file-scope>):the-statements-outside-every-named-definition,where-a-top-level-call-and-an-anonymous-callback-body's-calls-live;a-CALLER-never-a-callee(nothing-in-the-source-can-name-it)-with-no-body-to-expand;a-file-with-no-such-call-has-no-such-row -->
<!-- t=type|alias|functype=a-Go-named-type-by-its-written-form:type=a-defined-type-whose-WRITTEN-form-is-not-a-struct/iface/func-literal(type-N-string;type-W-Pair-too,whatever-Pair-is-underneath),alias=type-A=B,functype=type-F-func(...) -->
<!-- t=alias|functype-in-C++-and-.h:alias=using-X=Y(also-templated-or-class-scope)or-namespace-L=lib(defs=X-prints-its-written-target-as-to=),functype=a-typedef-of-a-function-or-function-pointer-type(typedef-void(*F)(int));other-typedefs-read-t=struct -->
<!-- files=4838 symbols=44600 edges=44429 shown=1 est_tokens=1122 ambiguous=3634 unresolved=20069 locality_pinned=14 external=12457 declined=45295 extent_suspect_syms=12 macro_blanked_files=7 skipped_oversize=15 unindexed="txt:85,tsv:54,mod:33,xml:33,jsonl:26,scm:25" unindexed_exts=23 max_tokens=1500 fit_bytes=3186 over_ceiling=1 order=important-first -->
<r schema="ripwire.map/v1" root="." est_tokens="1122" pr_iters="40">
<f p="src/infra/nodekind.h" layer="infra">
<s t="fn" n="kindIs" sc="rw" k="0.0031">
</s>
</f>
</r>
`````

## `./build/ripwire . --token-budget=100`

*GATE form: exit 3 if the map's own est_tokens exceeds the budget (over-budget failure shape).*

**exit code: 3**

`````
<!-- ripwire map schema=ripwire.map/v1: the ranked map WITHHELD whole, no rows: withheld=1 marks this record, withheld_est_tokens= the map's price, over budget= (the token budget asked); rerun with a larger token budget, or max-tokens to shape a map that fits. -->
<r schema="ripwire.map/v1" withheld_est_tokens="10513" budget="100" withheld="1"/>
`````

stderr:

`````
ripwire: --token-budget exceeded: withheld_est_tokens=10513 > budget=100
`````

## `./build/ripwire . --for="incremental cache invalidation when a file content hash changes"`

*The task lens: ranked signatures + quality metrics framed for the task.*

**wall time: 5.38s**

`````
<ctx task="incremental cache invalidation when a file content hash changes" route="subtoken+body" root="." confidence="low" margin_pct="0" at="6ace381eb" doc_mentions="5" schema="ripwire.for/v1" bundle="compact" bodies="0" reason="compact-route" budget_bytes="7500" doc_mentions_capped="1" doc_mentio … [line truncated: 31 more bytes on this line]
<!-- ripwire for schema=ripwire.for/v1: bundle=/bodies=/reason= the body posture; d: cx= ccx= complexity, in= callers (absent cx/ccx/in = 0), churn= amp= change, clone= tested= 1, sc= scope, id=p::sc::n; total= shown= capped=1 if cut; task= the query; d pure=1 const/constexpr sig, next= the follow-up to paste; route= name-exact(X)|subtoken+body[:broad|:declined]; confidence=/margin_pct= head score drop (low=flat); h l= p= n=, c n= l= p= (p= if not h's; same-named joined, shown= counts them), noedge= no callee resolved; h calls capped=1 next= the call listing every callee; fold kind=bodies: b t= n= p= l= top ranked rows' whole bodies, not the answer; served= of total= in budget_bytes=; slice/skip p= n= l=; skip bytes= next=; a skip makes sigs next= it, sigs_next= the signatures-only re-call; d mem= an owner's direct member names only, by the index (question words first, then owner's file, path, line, name), mem_more= names cut; t p= file outside sigs (weaker), t sym= its top symbols not in sigs/syms (a pointer, not the answer), r= rank (gap = trimmed); t order: code files first, then doc files (a code question); t page rows go on to file-page row 160 (code question: 160 code rows, docs within row 160); past page 0 (code question: past 40 code rows, a doc past row 40) listed last, head files skipped; past 120 of those p= only, p_only= counts them; t folded=class=N: N p= only rows of that class (doc|config|script|testdata|other) not listed, next= pages to them; d layer=: built-in arch layer (game|infra|render|math|audio|ai|test) from a dir name in p=; d e= its last line (absent=unknown, never 0; l= the name's line); c via=name: that callee matched by name alone, receiver unproven (NOT a claim the edge is false) [doc mentions: 5 docs, 3 symbols; doc_mentions=] -->
<!-- root= is the crawl root; p= below is RELATIVE to it (single-root only; absent => p= is ingest's own path, unchanged); at=this commit(+dirty). [budget_bytes= is the default BYTE target this ranked payload was shaped toward: row text shortens toward it, no row of the ranked head is removed for it (sigs past_target=)] [sigs capped=1 with shown=total: rows shrunk, none dropped] [sigs past_target=K: the last K rows are past the budget_bytes target, served because they are rows of the ranked head; none is cut] [sigs next=: one call serving all total= rows uncut] [docs_dropped=N: N shown rows have a doc comment not printed (r>24 always, r5..24 if capped)] [files_first=N: N rows moved so r=1..8 are distinct files' best rows, score order, a repeated name once; same rows; fold, hops keep score order] [cut: doc_mentions_capped="1" doc_mentions_total="6" — an indexing cap dropped content not shown here]; lego/compose collapse to a counted stub by default (a disclosed cut): total= that section's own pre-cap row count, shown="0" capped="1" (nothing rendered here), next= names the sections=lego,compose flag that restores both sections byte-identically in one call est_tokens= prices this bundle in tokens -->
<sigs shown="40" total="40" capped="1" past_target="14" docs_dropped="31" files_first="15" next="--for='incremental cache invalidation when a file content hash changes' --signatures-only --token-budget=6600">
<d l="153" e="153" n="kCacheMagic" p="src/ingest_cache.h" churn="389" amp="639" pure="1" r="1" next="--expand=src/ingest_cache.h:kCacheMagic">
<doc>incremental cache (--cache): per-file content hash + raw facts so a re-run re-parses ONLY      c…</doc>constexpr std::uint32_t kCacheMagic = 0x4b505443</d>
<d l="3100" e="3100" n="kHeadSnapCacheScheme" sc="quality" p="src/quality.h" churn="684" amp="867" pure="1" r="2">
<doc>and every file whose content hash differs is re-parsed — so a stale or foreign blob self-heals…</doc>constexpr std::uint32_t kHeadSnapCacheScheme = 1</d>
<d l="779" e="786" n="mcpRebuildBaseline" sc="rw" p="src/mcpindex.h" cx="2" ccx="1" in="1" churn="59" amp="145" r="3">inline McpRebuildBaseline mcpRebuildBaseline( const McpIndex&amp; ix, bool isIncrementalPass )</d>
<d l="364" e="381" n="noteFactlessMiss" p="src/ingest_parsepool.h" cx="3" ccx="2" in="1" churn="75" amp="189" tested="1" r="4">inline void noteFactlessMiss( ParsePoolShared&amp; sh, std::size_t fileId, bool nestRefused ) noexcept</d>
<d l="400" e="449" n="probeCachedRecord" p="src/ingest_prewarm.h" cx="15" ccx="11" in="1" churn="25" amp="82" tested="1" r="5">inline CachedRecordVerdict probeCachedRecord( const PrewarmMissPass&amp; pass, std::size_t fi, const CachedRecordHead&amp; record, std::string&amp; bytes )</d>
<d l="944" e="957" n="setTreeKey" sc="rw::warmsnap" p="src/warmsnap.h" cx="2" ccx="1" in="1" churn="8" amp="55" tested="1" r="6">inline void setTreeKey( Session&amp; s, const std::vector&lt;std::string&gt;&amp; files, std::string_view rootDir, const std::vector&lt;std::uint64_t&gt;&amp; hashes, cons … [line truncated: 20 more bytes on this line]
<d l="277" e="306" n="ingestCommitTree" sc="rw::dmm" p="src/dmm.h" cx="6" ccx="5" in="1" churn="16" amp="77" r="7">inline bool ingestCommitTree( const std::string&amp; root, const std::string&amp; sha, const std::vector&lt;std::string&gt;&amp; excludes, std::size_t maxFileBytes, IngestResult&amp; ou … [line truncated: 7 more bytes on this line]
<d l="25" e="25" n="kFnv1aLegacySeed64" sc="rw::hashutil" p="src/infra/hashutil.h" layer="infra" churn="7" amp="49" pure="1" r="8">inline constexpr std::uint64_t kFnv1aLegacySeed64 = 1469598103934665603ull</d>
<d l="495" e="577" n="McpIndex" sc="McpIndex" p="src/mcpindex.h" churn="59" amp="144" r="9">
<doc>persistent in-memory index (parse once, reuse across MCP calls) ---- The MCP server is long-live…</doc>struct McpIndex</d>
<d l="1224" e="1399" n="getIndex" sc="rw" p="src/mcpindex.h" cx="23" ccx="40" in="36" churn="59" amp="180" r="10">inline const McpIndex&amp; getIndex( const std::string&amp; root )</d>
<!-- demote: a <t> in sigs is a lower same-file sibling past answer row 10, a pointer (p= file, sym= name, r= rank), not the answer -->
<t p="src/ingest_cache.h" sym="contentHash64" r="11"/>
<t p="src/ingest_cache.h" sym="CacheEntry" r="12"/>
<t p="src/ingest_cache.h" sym="blobChecksum" r="13"/>
<t p="src/quality.h" sym="contentIdsBySym" r="14"/>
<t p="src/ingest_cache.h" sym="buildCachePathKeys" r="15"/>
<t p="src/ingest_cache.h" sym="buildCacheWritePlan" r="16"/>
<t p="src/mcpindex.h" sym="makeHandle" r="17"/>
<d l="464" e="484" n="indexContentHash" sc="mcpdetail" p="src/mcpindex.h" cx="5" ccx="7" in="1" churn="59" amp="145" r="18">inline std::uint64_t indexContentHash( const std::vector&lt;std::string&gt;&amp; files, const std::vector&lt;long long&gt;&amp; fileMtime, const std::vector&lt;std::uint64_t&gt … [line truncated: 25 more bytes on this line]
<t p="src/ingest_prewarm.h" sym="PrewarmMissPass" r="19"/>
<d l="28" e="54" n="IngestFileScan" sc="IngestFileScan" p="src/ingest_prewarm.h" churn="25" amp="81" r="20" mem="markExtractPartial">struct IngestFileScan</d>
<t p="src/ingest_prewarm.h" sym="forgetNestRefusalsForCache" r="21"/>
<d l="357" e="360" n="byteHash" sc="mcpdetail" p="src/mcpindex.h" cx="1" in="7" churn="59" amp="151" r="22">inline std::uint64_t byteHash( const char* data, std::size_t n ) noexcept</d>
… [217 more display lines; full output is 24462 bytes on 8 raw line(s)]
`````

stderr:

`````
ripwire: cache <tmp>: over its 2048 MiB budget — evicted 74 blob(s) of other roots or other ripwire builds (this build's blobs for this root are kept)
`````

## `./build/ripwire . --for="rankGraphTeleport"`

*Name-shaped query: the router picks name-exact BM25 (header says which/why).*

**wall time: 2.05s**

`````
<ctx task="rankGraphTeleport" route="name-exact(rankGraphTeleport); anchors: rankGraphTeleport(src/graph.h)" root="." confidence="high" margin_pct="45" at="6ace381eb" doc_mentions="2" schema="ripwire.for/v1" bundle="auto" bodies="1" doc_mentions_capped="1" doc_mentions_total="14" est_tokens="2165">
<!-- ripwire for schema=ripwire.for/v1: bundle=/bodies=/reason= the body posture; d: cx= ccx= complexity, in= callers (absent cx/ccx/in = 0), churn= amp= change, clone= tested= 1, sc= scope, id=p::sc::n; total= shown= capped=1 if cut; task= the query; d pure=1 const/constexpr sig, next= the follow-up to paste; route= name-exact(X)|subtoken+body[:broad|:declined]; confidence=/margin_pct= head score drop (low=flat); b t= n= p= l= full bodies, c n= l= p= callee signatures (p= if not b's); callers of=: the one function's 1-hop callers, s t= n= sc= p=file:line (n=Owner.name folds sc= on a member; sites_at= its calls as [file:]line, sites_total= if cut; via=name by name only), shown= of total=; d=2 rows: their callers (via=name if every path has a by-name hop), shown_d2= of d2= (d2_capped=1 if cut, else 0); capped=1 if cut; floors; next= the radius; windows=1: the radius call lists only a first page of next_total= rows (the impact verb's own count, a floor), so no page is pointed at: next= lists them all, columnar; t p= file outside sigs (weaker), t sym= its top symbols not in sigs/syms (a pointer, not the answer), r= rank (gap = trimmed); t order: code files first, then doc files (a code question); d e= its last line (absent=unknown, never 0; l= the name's line); c prov=split: a resolver split arm; may be another arm's (NOT a claim the edge is false) [doc mentions: 2 docs, 1 symbol; doc_mentions=] [floor: kept 3 of 40] -->
<!-- root= is the crawl root; p= below is RELATIVE to it (single-root only; absent => p= is ingest's own path, unchanged); at=this commit(+dirty). [cut: doc_mentions_capped="1" doc_mentions_total="14" — an indexing cap dropped content not shown here] est_tokens= prices this bundle in tokens -->
<sigs>
<d l="14619" e="14647" n="rankGraphTeleport" sc="rw" p="src/graph.h" cx="5" ccx="8" in="7" churn="713" amp="984" r="1" next="--expand=src/graph.h:rankGraphTeleport">
<doc>PageRank with an explicit teleport / personalization vector p (Σp = 1). The prior is name-quality-biased through biasPrior() so all rank modes share one weighting seam; the transition matrix (edges</doc>inline RankedGraph rankGraphTeleport( const Graph&amp; g, const std::vector&lt;float&gt;&am … [line truncated: 31 more bytes on this line]
<d l="501" n="The convergence disclosure contract" sc="rank — Personalized PageRank" p="docs/ARCHITECTURE.md" churn="79" amp="202" r="2">#### The convergence disclosure contract</d>
<d l="6391" n="Wave-2 adversarial verification (2026-08-19) — six probes against `aa97c9e`" sc="6. Correctness and quality instruments" p="docs/EVALS.md" churn="1178" amp="1393" r="3">### Wave-2 adversarial verification (2026-08-19) — six probes against `aa97c9e`</d>
</sigs>
<tail total="3" shown="3" capped="0">
<t p="src/graph.h"/>
<t p="docs/ARCHITECTURE.md"/>
<t p="docs/EVALS.md"/>
</tail>
<callers of="rw::rankGraphTeleport" shown="7" total="7" capped="1" d2="52" shown_d2="4" d2_capped="1" windows="1" next_total="80" next="--impact=rw::rankGraphTeleport --format=columnar --limit=80">
<s t="fn" n="getIndex" sc="rw" p="src/mcpindex.h:1224" sites_at="1340"/>
<s t="fn" n="rankGraph" sc="rw" p="src/graph.h:14662" sites_at="14666"/>
<s t="fn" n="anchoredLexicalRank" sc="rw" p="src/graph.h:15331" sites_at="15382"/>
<s t="fn" n="runEval" sc="rw" p="src/eval.h:171" sites_at="328"/>
<s t="fn" n="churnDecayRanking" p="src/main.cpp:1432" sites_at="1446"/>
<s t="fn" n="churnRankedGraph" p="src/main.cpp:1471" sites_at="1485 1486 1500"/>
<s t="fn" n="runDefaultMap" p="src/main.cpp:1758" sites_at="1878"/>
<s t="fn" n="symbolQueryJson" sc="rw" p="src/mcpverbs.h:792" d="2"/>
<s t="fn" n="pathText" sc="rw" p="src/mcpverbs.h:4040" d="2"/>
<s t="fn" n="fetchBody" sc="rw" p="src/mcpverbs.h:5901" d="2"/>
<s t="fn" n="computeLensRanking" p="src/verbs_for.h:115" d="2"/>
</callers>
<bodies shown="1" total="1" capped="0">
<b t="fn" l="14619" p="src/graph.h" n="rankGraphTeleport">
<![CDATA[inline RankedGraph rankGraphTeleport( const Graph& g, const std::vector<float>& p, float alpha = 0.85f )
… [28 more display lines; full output is 6611 bytes on 29 raw line(s)]
`````

## `./build/ripwire . --for="rankGraphTeleport" --no-route`

*Same query with routing forced OFF (plain subtoken+body BM25) — contrast with the routed run.*

**wall time: 1.92s**

`````
<ctx task="rankGraphTeleport" root="." confidence="low" margin_pct="0" at="6ace381eb" doc_mentions="6" schema="ripwire.for/v1" bundle="auto" bodies="4" budget_bytes="7500" doc_mentions_capped="1" doc_mentions_total="22" est_tokens="10976">
<!-- ripwire for schema=ripwire.for/v1: bundle=/bodies=/reason= the body posture; d: cx= ccx= complexity, in= callers (absent cx/ccx/in = 0), churn= amp= change, clone= tested= 1, sc= scope, id=p::sc::n; total= shown= capped=1 if cut; task= the query; d pure=1 const/constexpr sig, next= the follow-up to paste; confidence=/margin_pct= head score drop (low=flat); b t= n= p= l= full bodies, c n= l= p= callee signatures (p= if not b's); t p= file outside sigs (weaker), t sym= its top symbols not in sigs/syms (a pointer, not the answer), r= rank (gap = trimmed); t order: code files first, then doc files (a code question); t page rows go on to file-page row 160 (code question: 160 code rows, docs within row 160); past page 0 (code question: past 40 code rows, a doc past row 40) listed last, head files skipped; past 120 of those p= only, p_only= counts them; t folded=class=N: N p= only rows of that class (doc|config|script|testdata|other) not listed, next= pages to them; field name= type= owner= rel=: a member of owner=, rel=creates held by value, uses by reference/pointer; d e= its last line (absent=unknown, never 0; l= the name's line); c prov=split: a resolver split arm; may be another arm's (NOT a claim the edge is false) [doc mentions: 6 docs, 3 symbols; doc_mentions=] -->
<!-- root= is the crawl root; p= below is RELATIVE to it (single-root only; absent => p= is ingest's own path, unchanged); at=this commit(+dirty). [budget_bytes= is the default BYTE target this ranked payload was shaped toward: row text shortens toward it, no row of the ranked head is removed for it (sigs past_target=)] [sigs capped=1 with shown=total: rows shrunk, none dropped] [sigs past_target=K: the last K rows are past the budget_bytes target, served because they are rows of the ranked head; none is cut] [sigs next=: one call serving all total= rows uncut] [docs_dropped=N: N shown rows have a doc comment not printed (r>24 always, r5..24 if capped)] [cut: doc_mentions_capped="1" doc_mentions_total="22" — an indexing cap dropped content not shown here] est_tokens= prices this bundle in tokens -->
<sigs shown="40" total="40" capped="1" past_target="14" docs_dropped="25" next="--for=rankGraphTeleport --signatures-only --no-route --token-budget=6700">
<d l="14619" e="14647" n="rankGraphTeleport" sc="rw" p="src/graph.h" cx="5" ccx="8" in="7" churn="713" amp="984" r="1" next="--expand=src/graph.h:rankGraphTeleport">
<doc>PageRank with an explicit teleport / personalization vector p (Σp = 1). The prior is name-quali…</doc>inline RankedGraph rankGraphTeleport( const Graph&amp; g, const std::vector&lt;float&gt;&amp; p, float alpha = 0.85f )</d>
<d l="14662" e="14667" n="rankGraph" sc="rw" p="src/graph.h" cx="2" ccx="1" in="13" churn="713" amp="990" r="2">
<doc>uniform-teleport PageRank (the default). A kRankFlagNotNamed unit (model.h) has no edge and a 0 …</doc>inline RankedGraph rankGraph( const Graph&amp; g, float alpha = 0.85f )</d>
<d l="105" e="109" n="storedDefaultRank" sc="rw::warmsnap" p="src/warmsnap_graph.h" cx="1" in="3" churn="2" amp="33" r="3">
<doc>The default map&apos;s PageRank — uniform teleport, the one rank that is a function of the Graph al…</doc>inline std::optional&lt;RankedGraph&gt;&amp; storedDefaultRank() noexcept</d>
<d l="1471" e="1510" n="churnRankedGraph" p="src/main.cpp" cx="10" ccx="12" in="1" churn="509" amp="664" r="4">inline ChurnRanking churnRankedGraph( const MainDispatch&amp; d )</d>
<d l="2568" e="2572" n="kChurnRankLegend" sc="rw" p="src/serialize.h" churn="515" amp="626" pure="1" r="5">inline constexpr const char* kChurnRankLegend = &quot;&lt;!-- rank_by=churn: k= is PageRank re-run with the teleport BIASED by git CHANGE-FREQUENCY over window= &quot; &quot;(a c…</d>
<d l="14610" e="14615" n="RankedGraph" sc="RankedGraph" p="src/graph.h" churn="713" amp="977" r="6">struct RankedGraph</d>
<d l="14653" e="14657" n="takeRank" sc="rw" p="src/graph.h" cx="1" in="2" churn="713" amp="979" r="7">inline std::vector&lt;float&gt; takeRank( RankedGraph ranked, RankDisclosure&amp; disclosureOut )</d>
<d l="14578" e="14602" n="biasPrior" sc="rw" p="src/graph.h" cx="5" ccx="4" in="1" churn="713" amp="978" r="8">inline std::vector&lt;float&gt; biasPrior( const Graph&amp; g, const std::vector&lt;float&gt;&amp; p )</d>
<d l="2469" e="2495" n="churnTeleportWorkspace" sc="rw" p="src/gitmine.h" cx="6" ccx="9" in="1" churn="106" amp="153" r="9">inline std::vector&lt;float&gt; churnTeleportWorkspace( const std::vector&lt;std::string&gt;&amp; rootDirs, const IngestResult&amp; ing, const char* since = &quot;18 months ago … [line truncated: 21 more bytes on this line]
<d l="1432" e="1469" n="churnDecayRanking" p="src/main.cpp" cx="7" ccx="7" in="1" churn="509" amp="664" r="10">inline ChurnRanking churnDecayRanking( const MainDispatch&amp; d, const rw::SinceScope&amp; sinceScope, bool isScoped, const char* verbLabel )</d>
<d l="48" e="49" n="pageRankDouble" sc="rw" p="src/pagerank.h" cx="1" churn="8" amp="37" r="11">PageRankRun pageRankDouble( const sparseCsr&lt;float&gt;&amp; inEdges, std::span&lt;const double&gt; weightedOutDegree, std::span&lt;const double&gt; teleport, std::span&lt;double&gt; rank…</d>
<d l="503" e="549" n="rankByText" sc="rw" p="src/mcpverbs.h" cx="11" ccx="19" in="1" churn="675" amp="692" r="12">inline std::string rankByText( const std::string&amp; root, std::string_view mode, int topK, bool stable = false )</d>
<!-- demote: a <t> in sigs is a lower same-file sibling past answer row 10, a pointer (p= file, sym= name, r= rank), not the answer -->
<t p="src/gitmine.h" sym="churnDecayTeleport" r="13"/>
<d l="99" e="206" n="pageRankDouble" sc="rw" p="src/pagerank.cpp" cx="19" ccx="34" in="2" churn="14" amp="44" tested="1" r="14">PageRankRun pageRankDouble( const sparseCsr&lt;float&gt;&amp; inEdges, std::span&lt;const double&gt; weightedOutDegree, std::span&lt;const double&gt; teleport, std::span&lt … [line truncated: 45 more bytes on this line]
<d l="240" e="244" n="didYouMean" sc="rw" p="src/didyoumean.h" cx="2" ccx="1" in="7" churn="10" amp="59" r="15">inline std::string didYouMean( const IngestResult&amp; ing, std::string_view name )</d>
<t p="src/gitmine.h" sym="churnDecayTeleportWorkspace" r="16"/>
<d l="1224" e="1399" n="getIndex" sc="rw" p="src/mcpindex.h" cx="23" ccx="40" in="36" churn="59" amp="180" r="17">inline const McpIndex&amp; getIndex( const std::string&amp; root )</d>
<t p="src/serialize.h" sym="DataSectionsCut" r="18"/>
<d l="110" e="120" n="defaultRank" sc="rw::warmsnap" p="src/warmsnap_graph.h" cx="3" ccx="2" in="1" churn="2" amp="31" r="19">inline RankedGraph defaultRank( const Graph&amp; g )</d>
<d l="501" n="The convergence disclosure contract" sc="rank — Personalized PageRank" p="docs/ARCHITECTURE.md" churn="79" amp="202" r="20">#### The convergence disclosure contract</d>
<d l="6391" n="Wave-2 adversarial verification (2026-08-19) — six probes against `aa97c9e`" sc="6. Correctness and quality instruments" p="docs/EVALS.md" churn="1178" amp="1393" r="21">### Wave-2 adversarial verification (2026-08-19) — six probes against `aa97c9e`</d>
<t p="src/gitmine.h" sym="kChurnMergeBombMaxFiles" r="22"/>
… [276 more display lines; full output is 30309 bytes on 77 raw line(s)]
`````

## `./build/ripwire . --for="rankGraphTeleport" --signatures-only`

*T3 opt-out: the signatures-only lens (no auto bodies, no bundle="auto" attribute) — contrast with the terminal default above.*

**wall time: 1.13s**

`````
<ctx task="rankGraphTeleport" route="name-exact(rankGraphTeleport); anchors: rankGraphTeleport(src/graph.h)" root="." confidence="high" margin_pct="45" at="6ace381eb" doc_mentions="2" schema="ripwire.for/v1" doc_mentions_capped="1" doc_mentions_total="14" est_tokens="959">
<!-- ripwire for schema=ripwire.for/v1: bundle=/bodies=/reason= the body posture; d: cx= ccx= complexity, in= callers (absent cx/ccx/in = 0), churn= amp= change, clone= tested= 1, sc= scope, id=p::sc::n; total= shown= capped=1 if cut; task= the query; d pure=1 const/constexpr sig, next= the follow-up to paste; route= name-exact(X)|subtoken+body[:broad|:declined]; confidence=/margin_pct= head score drop (low=flat); t p= file outside sigs (weaker), t sym= its top symbols not in sigs/syms (a pointer, not the answer), r= rank (gap = trimmed); t order: code files first, then doc files (a code question); d e= its last line (absent=unknown, never 0; l= the name's line) [doc mentions: 2 docs, 1 symbol; doc_mentions=] [floor: kept 3 of 40] -->
<!-- root= is the crawl root; p= below is RELATIVE to it (single-root only; absent => p= is ingest's own path, unchanged); at=this commit(+dirty). [cut: doc_mentions_capped="1" doc_mentions_total="14" — an indexing cap dropped content not shown here] est_tokens= prices this bundle in tokens -->
<sigs>
<d l="14619" e="14647" n="rankGraphTeleport" sc="rw" p="src/graph.h" cx="5" ccx="8" in="7" churn="713" amp="984" r="1" next="--expand=src/graph.h:rankGraphTeleport">
<doc>PageRank with an explicit teleport / personalization vector p (Σp = 1). The prior is name-quality-biased through biasPrior() so all rank modes share one weighting seam; the transition matrix (edges</doc>inline RankedGraph rankGraphTeleport( const Graph&amp; g, const std::vector&lt;float&gt;&am … [line truncated: 31 more bytes on this line]
<d l="501" n="The convergence disclosure contract" sc="rank — Personalized PageRank" p="docs/ARCHITECTURE.md" churn="79" amp="202" r="2">#### The convergence disclosure contract</d>
<d l="6391" n="Wave-2 adversarial verification (2026-08-19) — six probes against `aa97c9e`" sc="6. Correctness and quality instruments" p="docs/EVALS.md" churn="1178" amp="1393" r="3">### Wave-2 adversarial verification (2026-08-19) — six probes against `aa97c9e`</d>
</sigs>
<tail total="3" shown="3" capped="0">
<t p="src/graph.h"/>
<t p="docs/ARCHITECTURE.md"/>
<t p="docs/EVALS.md"/>
</tail>
<!-- syms: leads, not the answer: first 6 shown files' symbols it lacks, p=file:line n=Owner.name; by=name task word, by=callee a head <d> row calls it (via=name name-only, prov=split one arm); name_total= callee_total= files_total= cut by the 3-row, 6-file cap; files= head= if under 6, 8 -->
<syms files="3" head="3" name_total="17">
<y p="src/graph.h:14662" n="rankGraph" by="name"/>
<y p="src/graph.h:20798" n="graphCountFloorAttrXml" by="name"/>
<y p="src/graph.h:20807" n="graphGaugeClauses" by="name"/>
</syms>
</ctx>
`````

## `./build/ripwire . --for="tree-sitter parse of a source file" --adaptive`

*Cut the result at the relevance cliff (Adaptive-k) — on a flat ranking nothing is cut and the header says so ([adaptive: kept N of N]).*

**wall time: 1.05s**

`````
<ctx task="tree-sitter parse of a source file" route="subtoken+body" root="." confidence="low" margin_pct="0" at="6ace381eb" doc_mentions="1" schema="ripwire.for/v1" bundle="compact" bodies="0" reason="compact-route" budget_bytes="7500" est_tokens="10187">
<!-- ripwire for schema=ripwire.for/v1: bundle=/bodies=/reason= the body posture; d: cx= ccx= complexity, in= callers (absent cx/ccx/in = 0), churn= amp= change, clone= tested= 1, sc= scope, id=p::sc::n; total= shown= capped=1 if cut; task= the query; d pure=1 const/constexpr sig, next= the follow-up to paste; d same_as=N: doc+sig text as row n=N (not repeated); route= name-exact(X)|subtoken+body[:broad|:declined]; confidence=/margin_pct= head score drop (low=flat); h l= p= n=, c n= l= p= (p= if not h's; same-named joined, shown= counts them), noedge= no callee resolved; fold kind=bodies: b t= n= p= l= top ranked rows' whole bodies, not the answer; served= of total= in budget_bytes=; slice/skip p= n= l=; skip bytes= next=; a skip makes sigs next= it, sigs_next= the signatures-only re-call; d mem= an owner's direct member names only, by the index (question words first, then owner's file, path, line, name), mem_more= names cut; t p= file outside sigs (weaker), t sym= its top symbols not in sigs/syms (a pointer, not the answer), r= rank (gap = trimmed); t order: code files first, then doc files (a code question); t page rows go on to file-page row 160 (code question: 160 code rows, docs within row 160); past page 0 (code question: past 40 code rows, a doc past row 40) listed last, head files skipped; past 120 of those p= only, p_only= counts them; t folded=class=N: N p= only rows of that class (doc|config|script|testdata|other) not listed, next= pages to them; d layer=: built-in arch layer (game|infra|render|math|audio|ai|test) from a dir name in p=; d e= its last line (absent=unknown, never 0; l= the name's line) [adaptive: kept 40 of 40 - no relevance cliff (broad query saturates the score); capped at the ceiling] [doc mentions: 1 doc, 1 symbol; doc_mentions=] -->
<!-- root= is the crawl root; p= below is RELATIVE to it (single-root only; absent => p= is ingest's own path, unchanged); at=this commit(+dirty). [budget_bytes= is the default BYTE target this ranked payload was shaped toward: row text shortens toward it, no row of the ranked head is removed for it (sigs past_target=)] [sigs capped=1 with shown=total: rows shrunk, none dropped] [sigs past_target=K: the last K rows are past the budget_bytes target, served because they are rows of the ranked head; none is cut] [sigs next=: one call serving all total= rows uncut] [docs_dropped=N: N shown rows have a doc comment not printed (r>24 always, r5..24 if capped)] [files_first=N: N rows moved so r=1..8 are distinct files' best rows, score order, a repeated name once; same rows; fold, hops keep score order]; lego/compose collapse to a counted stub by default (a disclosed cut): total= that section's own pre-cap row count, shown="0" capped="1" (nothing rendered here), next= names the sections=lego,compose flag that restores both sections byte-identically in one call est_tokens= prices this bundle in tokens -->
<sigs shown="40" total="40" capped="1" past_target="7" docs_dropped="25" files_first="7" next="--for='tree-sitter parse of a source file' --signatures-only --adaptive --token-budget=5500">
<d l="28" e="63" n="topLevelEvidence" sc="rw::pythonrunner" p="src/pythonrunner.h" cx="4" ccx="3" in="2" churn="5" amp="15" r="1" next="--expand=src/pythonrunner.h:topLevelEvidence">inline bool topLevelEvidence( std::string_view source, const TSLanguage* language, const Predicate&amp; predicate )</d … [line truncated: 1 more bytes on this line]
<d l="45" e="45" n="kDefaultMaxFileBytes" sc="rw" p="src/ingest.h" churn="72" amp="185" pure="1" r="2">
<doc>The crawl&apos;s per-file byte ceiling. A text file larger than this is skipped: at this size it is o…</doc>constexpr std::size_t kDefaultMaxFileBytes = 4u * 1024u * 1024u</d>
<d l="1247" e="1255" n="parseTree" p="src/ingest_sidecap.h" cx="1" in="4" churn="181" amp="364" tested="1" r="3">TSTree* parseTree( TSParser* parser, std::string_view src )</d>
<d l="594" e="669" n="doctorProbeGrammars" p="src/verbs_doctor.h" cx="7" ccx="17" in="1" churn="51" amp="150" r="4">
<doc>Exercise every registered grammar and its embedded query, reporting loaded and expected totals</doc>inline DoctorGrammarProbe doctorProbeGrammars()</d>
<d l="527" e="565" n="SourceReader" sc="SourceReader" p="src/forselfhook.h" churn="9" amp="8" r="5" mem="parsed">class SourceReader</d>
<d l="104" e="238" n="kLangTable" p="src/ingest_crawl.h" churn="90" amp="225" pure="1" r="6">constexpr std::array&lt;LangEntry, 58&gt; kLangTable =</d>
<d l="2495" e="2510" n="FileHealth" sc="FileHealth" p="src/model.h" churn="338" amp="570" r="7" mem="operator==">struct FileHealth</d>
<d l="308" e="343" n="SliceScan" sc="SliceScan" p="src/slice.h" churn="54" amp="102" r="8" mem="disclose">struct SliceScan</d>
<d l="138" e="152" n="ParsedFile::ParsedFile" p="src/forselfhook.h" cx="2" ccx="1" churn="9" amp="8" r="9">explicit ParsedFile( std::string bytes ) : m_bytes( std::move( bytes ) )</d>
<d l="135" e="177" n="ParsedFile" sc="ParsedFile" p="src/forselfhook.h" churn="9" amp="8" r="10" mem="operator=,usable,root,text">class ParsedFile</d>
<!-- demote: a <t> in sigs is a lower same-file sibling past answer row 10, a pointer (p= file, sym= name, r= rank), not the answer -->
<t p="src/ingest.h" sym="AstWalk" r="11"/>
<t p="src/ingest_sidecap.h" sym="astroFenceTailIsBlank" r="12"/>
<d l="386" e="459" n="sliceAtRev" sc="slicediff" p="src/slicediff.h" cx="14" ccx="15" in="1" churn="14" amp="76" r="13">inline RevSide sliceAtRev( const std::string&amp; root, const std::string&amp; sha, const std::string&amp; rel, const Symbol&amp; sym, SliceFam fam, const ::TSLanguage* grammar, st … [line truncated: 77 more bytes on this line]
<d l="2075" e="2104" n="collectGatedLocalNames" sc="rw" p="src/ingest_astquery.h" cx="6" ccx="5" in="1" churn="61" amp="178" r="14">std::vector&lt;LocalNameFact&gt; collectGatedLocalNames( std::string_view defBytes, std::uint32_t defStartLine, Lang lang )</d>
<d l="927" e="978" n="scanModule" sc="detail" p="src/jsrunner.h" cx="16" ccx="15" in="3" churn="22" amp="109" r="15">inline ModuleScan scanModule( std::string_view source, std::string_view path )</d>
<t p="src/ingest.h" sym="kMaxKotlinStringNestDepth" r="16"/>
<d l="87" e="97" n="hasMainGuard" sc="rw::pythonrunner" p="src/pythonrunner.h" cx="2" ccx="2" in="1" churn="5" amp="14" r="17">inline bool hasMainGuard( std::string_view source )</d>
<d l="255" e="259" n="hasPhantomScopeSeparator" p="src/ingest_names.h" cx="2" ccx="1" in="2" churn="86" amp="248" tested="1" r="18">inline bool hasPhantomScopeSeparator( TSNode qualified ) noexcept</d>
<t p="src/ingest_crawl.h" sym="jsonNestsTooDeep" r="19"/>
<t p="src/slice.h" sym="DisclosureWhy" r="20"/>
<t p="src/ingest.h" sym="kMaxYamlNestDepth" r="21"/>
<t p="src/ingest_astquery.h" sym="spanTiersOfFiles" r="22"/>
<t p="src/slice.h" sym="sliceScanDefinition" r="23"/>
… [242 more display lines; full output is 26826 bytes on 44 raw line(s)]
`````

## `./build/ripwire . --for="why does src/lexical.h chooseForRanker pick name-exact BM25"`

*Mention anchoring (default-on): a path and a Symbol literally named in the task get lifted; the header says what anchored.*

**wall time: 1.20s**

`````
<ctx task="why does src/lexical.h chooseForRanker pick name-exact BM25" route="subtoken+body" root="." confidence="low" margin_pct="0" at="6ace381eb" mention_anchored="3" doc_mentions="4" schema="ripwire.for/v1" bundle="compact" bodies="0" reason="compact-route" budget_bytes="7500" doc_mentions_capp … [line truncated: 49 more bytes on this line]
<!-- ripwire for schema=ripwire.for/v1: bundle=/bodies=/reason= the body posture; d: cx= ccx= complexity, in= callers (absent cx/ccx/in = 0), churn= amp= change, clone= tested= 1, sc= scope, id=p::sc::n; total= shown= capped=1 if cut; task= the query; d pure=1 const/constexpr sig, next= the follow-up to paste; route= name-exact(X)|subtoken+body[:broad|:declined]; confidence=/margin_pct= head score drop (low=flat); h l= p= n=, c n= l= p= (p= if not h's; same-named joined, shown= counts them), noedge= no callee resolved; h qword= its name (case-folded, leading _#$@ dropped) equals that question word (by name, not resolved, not the only one), first, calls to 100 (capped=1 next= all); qword_cut= owners not so served, next= the first; fold kind=bodies: b t= n= p= l= top ranked rows' whole bodies, not the answer; served= of total= in budget_bytes=; slice/skip p= n= l=; skip bytes= next=; a skip makes sigs next= it, sigs_next= the signatures-only re-call; t p= file outside sigs (weaker), t sym= its top symbols not in sigs/syms (a pointer, not the answer), r= rank (gap = trimmed); t tsym= up to 2 more file symbols named by a task word (a name match); t order: code files first, then doc files (a code question); t page rows go on to file-page row 160 (code question: 160 code rows, docs within row 160); past page 0 (code question: past 40 code rows, a doc past row 40) listed last, head files skipped; past 120 of those p= only, p_only= counts them; t folded=class=N: N p= only rows of that class (doc|config|script|testdata|other) not listed, next= pages to them; d layer=: built-in arch layer (game|infra|render|math|audio|ai|test) from a dir name in p=; d e= its last line (absent=unknown, never 0; l= the name's line); c prov=split: a resolver split arm; may be another arm's (NOT a claim the edge is false) [mention anchor: 1 file + 2 symbols; mention_anchored=] [doc mentions: 4 docs, 2 symbols; doc_mentions=] -->
<!-- root= is the crawl root; p= below is RELATIVE to it (single-root only; absent => p= is ingest's own path, unchanged); at=this commit(+dirty). [budget_bytes= is the default BYTE target this ranked payload was shaped toward: row text shortens toward it, no row of the ranked head is removed for it (sigs past_target=)] [sigs capped=1 with shown=total: rows shrunk, none dropped] [sigs past_target=K: the last K rows are past the budget_bytes target, served because they are rows of the ranked head; none is cut] [sigs next=: one call serving all total= rows uncut] [docs_dropped=N: N shown rows have a doc comment not printed (r>24 always, r5..24 if capped)] [docs_after_code=N: N doc rows of the shown set moved below its code rows; same rows, reordered, none added or removed; a question naming docs keeps score order] [cut: doc_mentions_capped="1" doc_mentions_total="7" — an indexing cap dropped content not shown here]; lego/compose collapse to a counted stub by default (a disclosed cut): total= that section's own pre-cap row count, shown="0" capped="1" (nothing rendered here), next= names the sections=lego,compose flag that restores both sections byte-identically in one call est_tokens= prices this bundle in tokens -->
<sigs shown="40" total="40" capped="1" past_target="15" docs_dropped="28" docs_after_code="2" next="--for='why does src/lexical.h chooseForRanker pick name-exact BM25' --signatures-only --token-budget=6400">
<d l="1916" e="1922" n="lexicalScoresNameExactRanked" sc="rw" p="src/lexical.h" cx="1" in="4" churn="92" amp="153" r="1" next="--expand=src/lexical.h:lexicalScoresNameExactRanked">
<doc>The name-exact ranker AS THE RETRIEVAL LENS SERVES IT: whole-name BM25 plus the definition-over-…</doc>inline std::vector&lt;float&gt; lexicalScoresNameExactRanked( const IngestResult&amp; ing, std::string_view query, const std::vector&lt;float&gt;* symbolScoreMul )</d>
<d l="158" e="169" n="printEvalRankerNote" sc="rw" p="src/eval.h" cx="1" in="1" churn="18" amp="52" r="2">
<doc>P11.12: the interpretive footer for --eval&apos;s ranker table, pulled into its own function so the 9…</doc>inline void printEvalRankerNote()</d>
<d l="189" e="189" n="kWeakLexicalScoreThreshold" sc="rw" p="src/lexical.h" churn="92" amp="149" pure="1" r="3">
<doc>calling agent knows to reformulate rather than trust the ranking. Calibrated empirically (2026-0…</doc>inline constexpr float kWeakLexicalScoreThreshold = 1.0f</d>
<d l="2746" e="2855" n="chooseForRanker" sc="rw" p="src/lexical.h" cx="18" ccx="23" in="6" churn="92" amp="155" r="4">inline RouteChoice chooseForRanker( const IngestResult&amp; ing, std::string_view query )</d>
<d l="716" e="795" n="runEvalRetrieval" sc="rw" p="src/eval.h" cx="7" ccx="10" in="1" churn="18" amp="52" r="5">inline int runEvalRetrieval( const IngestResult&amp; ing, const Graph&amp; g )</d>
<d l="1108" e="1145" n="chooseSubjectRouteUnchecked" sc="rw" p="src/subjectanchor.h" cx="14" ccx="11" in="1" churn="51" amp="48" r="6">inline SubjectRoute chooseSubjectRouteUnchecked( const IngestResult&amp; ing, const Graph&amp; g, std::string_view task, bool servesBodiesAndCallers )</d>
<d l="6963" e="6976" n="candidatesRootTag" sc="rw" p="src/serialize.h" cx="5" ccx="4" in="1" churn="515" amp="627" r="7">inline std::string candidatesRootTag( std::size_t keep, std::size_t corpusCount, const CandidateProvenance&amp; prov )</d>
<d l="1613" e="1773" n="lexicalScoresNameExactTiered" sc="rw" p="src/lexical.h" cx="40" ccx="68" in="2" churn="92" amp="151" r="8">inline std::vector&lt;float&gt; lexicalScoresNameExactTiered( const IngestResult&amp; ing, std::string_view query, const std::vector&lt;float&gt;* symbolScoreMul )</d>
<d l="808" e="812" n="NameCorpusStats" sc="NameCorpusStats" p="src/naminglens.h" churn="23" amp="62" r="9">struct NameCorpusStats</d>
<d l="1468" e="1485" n="chooseSubjectRoute" sc="rw" p="src/subjectanchor.h" cx="6" ccx="5" in="3" churn="51" amp="50" r="10">inline SubjectRoute chooseSubjectRoute( const IngestResult&amp; ing, const Graph&amp; g, std::string_view task, bool servesBodiesAndCallers )</d>
<!-- demote: a <t> in sigs is a lower same-file sibling past answer row 10, a pointer (p= file, sym= name, r= rank), not the answer -->
<t p="src/subjectanchor.h" sym="routeAnchorFallThrough" r="11"/>
<d l="1089" e="1190" n="runEvalMined" sc="rw" p="src/eval.h" cx="25" ccx="38" in="1" churn="18" amp="52" r="12">inline int runEvalMined( const std::string&amp; root, const IngestResult&amp; ing, const Graph&amp; g, const std::string&amp; path )</d>
<d l="48" e="99" n="LensRanking" sc="LensRanking" p="src/packtask.h" churn="93" amp="211" r="13">struct LensRanking</d>
<d l="48" e="63" n="hasIdentifierShape" sc="namesplit" p="src/infra/namesplit.h" layer="infra" cx="8" ccx="7" in="5" churn="12" amp="45" r="14">inline bool hasIdentifierShape( std::string_view w ) noexcept</d>
<d l="687" e="972" n="runEvalSkills" sc="rw" p="src/skilleval.h" cx="56" ccx="97" in="1" churn="20" amp="75" r="15">inline int runEvalSkills( const std::string&amp; root, const IngestResult&amp; ing, const Graph&amp; g, const std::string&amp; labelsPath )</d>
<d l="1412" e="1464" n="applyAnchorHonesty" sc="rw" p="src/subjectanchor.h" cx="13" ccx="19" in="1" churn="51" amp="48" r="16">inline std::vector&lt;SourceSyntaxAnchor&gt; applyAnchorHonesty( const IngestResult&amp; ing, std::string_view task, SubjectRoute&amp; out )</d>
<t p="src/lexical.h" sym="Bm25Params" r="17"/>
<t p="src/lexical.h" sym="bm25ImpactBound" r="18"/>
<d l="171" e="380" n="runEval" sc="rw" p="src/eval.h" cx="46" ccx="69" in="1" churn="18" amp="52" r="19">inline int runEval( const std::string&amp; root, const IngestResult&amp; ing, const Graph&amp; g, const std::vector&lt;char&gt;&amp; currentDiff )</d>
<d l="31" e="31" n="kLexWeightDoc" sc="rw" p="src/lexindex.h" churn="10" amp="27" pure="1" r="20">inline constexpr int kLexWeightDoc = 2</d>
<d l="1776" e="1779" n="lexicalScoresNameExact" sc="rw" p="src/lexical.h" cx="1" in="3" churn="92" amp="152" r="21">inline std::vector&lt;float&gt; lexicalScoresNameExact( const IngestResult&amp; ing, std::string_view query )</d>
<d l="351" e="365" n="hedgeOffTaskPick" sc="rw" p="src/exemplar.h" cx="5" ccx="3" in="1" churn="9" amp="20" r="22">inline void hedgeOffTaskPick( const IngestResult&amp; ing, ExemplarPick&amp; pick )</d>
… [275 more display lines; full output is 31856 bytes on 18 raw line(s)]
`````

## `./build/ripwire . --for="why does src/lexical.h chooseForRanker pick name-exact BM25" --no-mention-boost`

*Same task with the anchor disabled — the contrast the flag exists for.*

**wall time: 1.51s**

`````
<ctx task="why does src/lexical.h chooseForRanker pick name-exact BM25" route="subtoken+body" root="." confidence="low" margin_pct="0" at="6ace381eb" doc_mentions="2" schema="ripwire.for/v1" bundle="compact" bodies="0" reason="compact-route" budget_bytes="7500" doc_mentions_capped="1" doc_mentions_t … [line truncated: 28 more bytes on this line]
<!-- ripwire for schema=ripwire.for/v1: bundle=/bodies=/reason= the body posture; d: cx= ccx= complexity, in= callers (absent cx/ccx/in = 0), churn= amp= change, clone= tested= 1, sc= scope, id=p::sc::n; total= shown= capped=1 if cut; task= the query; d pure=1 const/constexpr sig, next= the follow-up to paste; route= name-exact(X)|subtoken+body[:broad|:declined]; confidence=/margin_pct= head score drop (low=flat); h l= p= n=, c n= l= p= (p= if not h's; same-named joined, shown= counts them), noedge= no callee resolved; h qword= its name (case-folded, leading _#$@ dropped) equals that question word (by name, not resolved, not the only one), first, calls to 100 (capped=1 next= all); qword_cut= owners not so served, next= the first; fold kind=bodies: b t= n= p= l= top ranked rows' whole bodies, not the answer; served= of total= in budget_bytes=; slice/skip p= n= l=; skip bytes= next=; a skip makes sigs next= it, sigs_next= the signatures-only re-call; t p= file outside sigs (weaker), t sym= its top symbols not in sigs/syms (a pointer, not the answer), r= rank (gap = trimmed); t tsym= up to 2 more file symbols named by a task word (a name match); t order: code files first, then doc files (a code question); t page rows go on to file-page row 160 (code question: 160 code rows, docs within row 160); past page 0 (code question: past 40 code rows, a doc past row 40) listed last, head files skipped; past 120 of those p= only, p_only= counts them; t folded=class=N: N p= only rows of that class (doc|config|script|testdata|other) not listed, next= pages to them; d layer=: built-in arch layer (game|infra|render|math|audio|ai|test) from a dir name in p=; d e= its last line (absent=unknown, never 0; l= the name's line); c prov=split: a resolver split arm; may be another arm's (NOT a claim the edge is false) [doc mentions: 2 docs, 1 symbol; doc_mentions=] -->
<!-- root= is the crawl root; p= below is RELATIVE to it (single-root only; absent => p= is ingest's own path, unchanged); at=this commit(+dirty). [budget_bytes= is the default BYTE target this ranked payload was shaped toward: row text shortens toward it, no row of the ranked head is removed for it (sigs past_target=)] [sigs capped=1 with shown=total: rows shrunk, none dropped] [sigs past_target=K: the last K rows are past the budget_bytes target, served because they are rows of the ranked head; none is cut] [sigs sigs_next=: one call serving all total= rows uncut] [docs_dropped=N: N shown rows have a doc comment not printed (r>24 always, r5..24 if capped)] [cut: doc_mentions_capped="1" doc_mentions_total="3" — an indexing cap dropped content not shown here]; lego/compose collapse to a counted stub by default (a disclosed cut): total= that section's own pre-cap row count, shown="0" capped="1" (nothing rendered here), next= names the sections=lego,compose flag that restores both sections byte-identically in one call est_tokens= prices this bundle in tokens -->
<sigs shown="40" total="40" capped="1" past_target="12" docs_dropped="30" sigs_next="--for='why does src/lexical.h chooseForRanker pick name-exact BM25' --signatures-only --no-mention-boost --token-budget=6400" next="--expand=src/eval.h:716:runEvalRetrieval">
<d l="1916" e="1922" n="lexicalScoresNameExactRanked" sc="rw" p="src/lexical.h" cx="1" in="4" churn="92" amp="153" r="1" next="--expand=src/lexical.h:lexicalScoresNameExactRanked">
<doc>The name-exact ranker AS THE RETRIEVAL LENS SERVES IT: whole-name BM25 plus the definition-over-…</doc>inline std::vector&lt;float&gt; lexicalScoresNameExactRanked( const IngestResult&amp; ing, std::string_view query, const std::vector&lt;float&gt;* symbolScoreMul )</d>
<d l="158" e="169" n="printEvalRankerNote" sc="rw" p="src/eval.h" cx="1" in="1" churn="18" amp="52" r="2">
<doc>P11.12: the interpretive footer for --eval&apos;s ranker table, pulled into its own function so the 9…</doc>inline void printEvalRankerNote()</d>
<d l="716" e="795" n="runEvalRetrieval" sc="rw" p="src/eval.h" cx="7" ccx="10" in="1" churn="18" amp="52" r="3">inline int runEvalRetrieval( const IngestResult&amp; ing, const Graph&amp; g )</d>
<d l="1108" e="1145" n="chooseSubjectRouteUnchecked" sc="rw" p="src/subjectanchor.h" cx="14" ccx="11" in="1" churn="51" amp="48" r="4">
<doc>The route the subject reading picks, before the CONFIDENCE-ANCHOR check. `servesBodiesAndCallers…</doc>inline SubjectRoute chooseSubjectRouteUnchecked( const IngestResult&amp; ing, const Graph&amp; g, std::string_view task, bool servesBodiesAndCallers )</d>
<d l="189" e="189" n="kWeakLexicalScoreThreshold" sc="rw" p="src/lexical.h" churn="92" amp="149" pure="1" r="5">inline constexpr float kWeakLexicalScoreThreshold = 1.0f</d>
<d l="6963" e="6976" n="candidatesRootTag" sc="rw" p="src/serialize.h" cx="5" ccx="4" in="1" churn="515" amp="627" r="6">inline std::string candidatesRootTag( std::size_t keep, std::size_t corpusCount, const CandidateProvenance&amp; prov )</d>
<d l="1613" e="1773" n="lexicalScoresNameExactTiered" sc="rw" p="src/lexical.h" cx="40" ccx="68" in="2" churn="92" amp="151" r="7">inline std::vector&lt;float&gt; lexicalScoresNameExactTiered( const IngestResult&amp; ing, std::string_view query, const std::vector&lt;float&gt;* symbolScoreMul )</d>
<d l="808" e="812" n="NameCorpusStats" sc="NameCorpusStats" p="src/naminglens.h" churn="23" amp="62" r="8">struct NameCorpusStats</d>
<d l="1468" e="1485" n="chooseSubjectRoute" sc="rw" p="src/subjectanchor.h" cx="6" ccx="5" in="3" churn="51" amp="50" r="9">inline SubjectRoute chooseSubjectRoute( const IngestResult&amp; ing, const Graph&amp; g, std::string_view task, bool servesBodiesAndCallers )</d>
<d l="1238" e="1257" n="routeAnchorFallThrough" sc="rw" p="src/subjectanchor.h" cx="5" ccx="5" in="1" churn="51" amp="48" r="10">inline RouteChoice routeAnchorFallThrough( std::string_view query, const RouteChoice&amp; anchored )</d>
<d l="1089" e="1190" n="runEvalMined" sc="rw" p="src/eval.h" cx="25" ccx="38" in="1" churn="18" amp="52" r="11">inline int runEvalMined( const std::string&amp; root, const IngestResult&amp; ing, const Graph&amp; g, const std::string&amp; path )</d>
<d l="48" e="99" n="LensRanking" sc="LensRanking" p="src/packtask.h" churn="93" amp="211" r="12">struct LensRanking</d>
<d l="48" e="63" n="hasIdentifierShape" sc="namesplit" p="src/infra/namesplit.h" layer="infra" cx="8" ccx="7" in="5" churn="12" amp="45" r="13">inline bool hasIdentifierShape( std::string_view w ) noexcept</d>
<d l="687" e="972" n="runEvalSkills" sc="rw" p="src/skilleval.h" cx="56" ccx="97" in="1" churn="20" amp="75" r="14">inline int runEvalSkills( const std::string&amp; root, const IngestResult&amp; ing, const Graph&amp; g, const std::string&amp; labelsPath )</d>
<d l="1412" e="1464" n="applyAnchorHonesty" sc="rw" p="src/subjectanchor.h" cx="13" ccx="19" in="1" churn="51" amp="48" r="15">inline std::vector&lt;SourceSyntaxAnchor&gt; applyAnchorHonesty( const IngestResult&amp; ing, std::string_view task, SubjectRoute&amp; out )</d>
<!-- demote: a <t> in sigs is a lower same-file sibling past answer row 10, a pointer (p= file, sym= name, r= rank), not the answer -->
<t p="src/lexical.h" sym="Bm25Params" r="16"/>
<t p="src/lexical.h" sym="bm25ImpactBound" r="17"/>
<d l="2746" e="2855" n="chooseForRanker" sc="rw" p="src/lexical.h" cx="18" ccx="23" in="6" churn="92" amp="155" r="18">inline RouteChoice chooseForRanker( const IngestResult&amp; ing, std::string_view query )</d>
<d l="171" e="380" n="runEval" sc="rw" p="src/eval.h" cx="46" ccx="69" in="1" churn="18" amp="52" r="19">inline int runEval( const std::string&amp; root, const IngestResult&amp; ing, const Graph&amp; g, const std::vector&lt;char&gt;&amp; currentDiff )</d>
<d l="31" e="31" n="kLexWeightDoc" sc="rw" p="src/lexindex.h" churn="10" amp="27" pure="1" r="20">inline constexpr int kLexWeightDoc = 2</d>
<d l="1776" e="1779" n="lexicalScoresNameExact" sc="rw" p="src/lexical.h" cx="1" in="3" churn="92" amp="152" r="21">inline std::vector&lt;float&gt; lexicalScoresNameExact( const IngestResult&amp; ing, std::string_view query )</d>
<d l="351" e="365" n="hedgeOffTaskPick" sc="rw" p="src/exemplar.h" cx="5" ccx="3" in="1" churn="9" amp="20" r="22">inline void hedgeOffTaskPick( const IngestResult&amp; ing, ExemplarPick&amp; pick )</d>
… [274 more display lines; full output is 31439 bytes on 18 raw line(s)]
`````

## `./build/ripwire . --lego=Vehicle`

*Interface -> implementors view: every existing impl of the named interface; the method contract is extracted for the C-family/Java/TS/Python tiers — for a Rust trait (this fixture) it discloses caveat="not-extracted-for-lang" rather than an empty list.*

`````
<ctx schema="ripwire.lego/v1" root=".">
<!-- ripwire lego schema=ripwire.lego/v1: ONE interface/base type: <iface n= p= defs= implementors=>, its <m> method contract, every implementor. counts_floor=1: every count is a FLOOR, never a total. graph_ambiguous=/graph_unresolved=: resolver gauge. graph_unindexed=N: N files no grammar could read (the map header's unindexed=); their calls raise neither gauge. root=: p= relative to it. methods=0 caveat=not-extracted-for-lang: no <m> contract read for this language. -->
<lego graph_ambiguous="3634" graph_unresolved="20069" graph_unindexed="313" counts_floor="1">
<iface n="Vehicle" p="test/legofix/vehicle.rs" methods="0" caveat="not-extracted-for-lang" defs="1" implementors="2">
<impl n="Car" p="test/legofix/vehicle.rs:12"/>
<impl n="Bike" p="test/legofix/vehicle.rs:13"/>
</iface>
</lego>
</ctx>
`````

## `./build/ripwire . --exemplar="format byte sizes for humans"`

*The repo's best-in-class instance to imitate before writing new code (picked by ROLE).*

`````
<!-- ripwire exemplar schema=ripwire.exemplar/v1: the best-in-class instance of kind= for the task, chosen by role: n= p= in= ccx= tested=, <bodies>
<b> to imitate. window: shown= total= capped= (capped=1 cut). root=: p= relative to it. candidates=N: instances of kind= under the ccx ceiling the pick was ranked from. low_confidence=1: weak task-to-kind match, fell back to fn unless off_task=1; pass a kind (fn|method|class...). b t= l=: the body's … [line truncated: 25 more bytes on this line]
<exemplar schema="ripwire.exemplar/v1" kind="fn" candidates="20978" n="kindIs" p="src/infra/nodekind.h:46" in="441" ccx="3" root="." tested="1" low_confidence="1">
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
<!-- ripwire help-task schema=ripwire.help-task/v1: which verb answers this task: status=recommend|abstain confidence= score= margin=, <facts> the evidence. next=: the one pasteable follow-up. git=/dirty=: the root is a git repo / its tree differs from HEAD (the stamp's +dirty). trace=1: the task text has a stack/sanitizer trace shape; it routes to from-trace. resolved_symbols=N: indexed names the task NAMES; a bare short/common word needs backticks or F(). -->
<task-route schema="ripwire.help-task/v1" status="abstain" confidence="none" score="0" margin="0" next="--for='write a cheerful release announcement'">
<facts git="1" dirty="0" trace="0" resolved_symbols="0"/>
</task-route>
`````

## `./build/ripwire . --recall="quality delta gating exit codes"`

*Most relevant DOCS' full bodies (markdown only) — recall what is already written down.*

`````
ripwire recall — "quality delta gating exit codes" — 142 relevant of 354 document files, best-first — total=142 shown=6 capped=1 truncated=5 generated_demoted=2 generated_demoted_paths="docs/TUNING.md,docs/LIMITS.md" max_tokens=8000 share_bytes=2792 est_tokens=5385

━━ docs/REFERENCE_GUIDE.md  (relevance 21.958) ━━  [sections: 2 of 12 selected (27 in doc), section-granular; whole doc 43914 B; lines="405-417,418-425"; dropped_by_budget=10]
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
`--quality-delta`, `--test-gate`, `--metrics`, `--flags`, and `--plan-lanes`, which is JSON-native. Every other
verb refuses on stderr with exit 1 rather than silently falling back to XML, so a verb added tomorrow
refuses by default.



━━ CHANGELOG.md  (relevance 21.025) ━━  [sections: 1 of 129 selected (611 in doc), section-granular; whole doc 1298822 B; lines="2552-2576"; dropped_by_budget=128]  [truncated: 2557 of 3826 bytes]
### Changed — `--quality-delta=A..B` answers the kinds it can under memory pressure, and exits 6 when that answer has no gating row (#387 follow-up)

A tripped memory guard in the range form used to give exit 5 and nothing, so on a large repository a four-file change
… [141 more lines, 13749 bytes total]
`````

stderr:

`````
ripwire: redacted 1 secret from emitted context (keyword-gated-secret=1) — pass --no-redact to disable
`````

## `./build/ripwire <scratch>/aux/kbcorpus --recall="field affinity cache line data layout which fields are read together" --top-k=3 --max-tokens=1200`

*The directory-as-knowledge-base pattern: --recall pointed at a 1546900-byte scratch dir of DUMPED TOOL OUTPUT (a git log, this repo's own generated command reference, --help text, an architecture doc, a fabricated JSON access log) instead of a source repo — no index to build, no daemon.*

`````
ripwire recall — "field affinity cache line data layout which fields are read together" — 2 relevant of 2 document files, best-first — total=2 shown=1 capped=1 truncated=1 max_tokens=1200 share_bytes=2040 est_tokens=957

━━ commands.md  (relevance 33.739) ━━  [sections: 1 of 166 selected (196 in doc), section-granular; whole doc 638338 B; lines="3892-3896"; dropped_by_budget=165]  [truncated: 1865 of 7797 bytes]
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

`````
<!-- ripwire tree schema=ripwire.tree/v1: each file with its top 3 symbols by rank, files by best symbol: <file p= symbols=> of <s t= n=>; of files= indexed, files_unlisted= have none. window: shown= total= capped= has_more= next_offset= offset= limit= (capped=1 cut; next_offset= pastes as offset=). symbols_capped=: 1 = cut. root=: p= relative to it. pr_iters=N: PageRank iterations. shown_symbols=: <s> rows printed. next=: the one pasteable follow-up. -->
<tree schema="ripwire.tree/v1" files="4838" files_unlisted="108" shown="80" capped="1" total="4730" has_more="1" next_offset="80" offset="0" limit="0" pr_iters="40" root="." shown_symbols="232" symbols_capped="1" next="--tree --offset=80">
<file p="src/infra/nodekind.h" symbols="1">
<s t="fn" n="kindIs"/>
</file>
<file p="src/ingest_metrics.h" symbols="91">
<s t="fn" n="nodeTextOf"/>
<s t="fn" n="nodeFieldText"/>
<s t="struct" n="CtrlKind"/>
</file>
<file p="src/infra/namesplit.h" symbols="11">
<s t="fn" n="isIdentChar"/>
<s t="fn" n="afterLast"/>
<s t="fn" n="isIdentStart"/>
</file>
<file p="src/model.h" symbols="257">
<s t="fn" n="relForHash"/>
<s t="fn" n="rootRelPath"/>
<s t="fn" n="isStructOrNamedType"/>
</file>
<file p="src/infra/Diagnostics.h" symbols="102">
<s t="macro" n="RW_ASSUME_"/>
<s t="macro" n="RW_ASSUME_"/>
<s t="macro" n="ASSUME"/>
</file>
<file p="src/infra/enumcount.h" symbols="7">
<s t="fn" n="enumTableAt"/>
<s t="fn" n="spellsEnumerator"/>
<s t="fn" n="namesEnumerator"/>
</file>
… [365 more display lines; full output is 10974 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --html=<scratch>/aux/map2.html`

*Self-contained HTML force-directed call graph.*

**wall time: 2.63s**

`````
(empty)
`````

Artifact written:

`````
  155365 <scratch>/aux/map2.html
`````

## `./build/ripwire . --order=stable --top-k=5`

*Stable (path/id) emit order — provider KV-cache hits across re-runs.*

`````
<!-- ripwire map schema=ripwire.map/v1: ranked symbol map: <f p= layer=> groups <s t= n= sc= k= amb=> rows (k= rank), <c n=> resolved callees; the header comment is data. est_tokens=: price as emitted (an upper bound under compact). root=: p= relative to it. pr_iters=N: PageRank iterations. <inv listed= unlisted=>: files the ranked rows show / do not (sum = files=), each named or counted below. <entry p= n=>: a program entry by its language's convention (C/Go/Rust main, Java/C# static main, a script main its module scope calls, __main__.py), callees as c rows; manifest entries not read. <ls p= n= f=>: n= unshown files under dir p=; f= names its code files, the rest (tests, docs, config, test/doc/example dirs) counted. declined=K: K call sites without edges, including inert Elixir quote sites after unquote/unquote_splicing re-entry. external=K: K calls proven outside the tree, no edge. locality_pinned=K: K calls pinned by locality alone (a guess). extent_suspect_syms=K: K defs failed containment, corpus-wide. macro_blanked_files=K: K files indexed from a macro-blanked re-parse. prov=scip|binding|import|split|final-segment: how that <c> edge bound (absent: one unique name); split = one arm of an amb= pick; final-segment = a qualified type matched by last name only. files=/symbols=: files and symbols indexed; edges= distinct call edges; shown= symbols printed, a merged row counting each def; ambiguous= calls split over several defs, corpus-wide; unresolved= calls with in-tree evidence and no edge (every def language-filtered or unreachable, or binding refused); order= rows by rank (important-first, important-last; (auto:fill) = flipped past a size threshold) or by path (stable). skipped_oversize=K: K files over a size ceiling, not indexed. unindexed=ext:N: N text files of that extension no grammar reads (6 extensions at most). unindexed_exts=E: E such extensions in all, the list cut. lens=: attributes another form of this answer serves, withheld here. sc=: enclosing scope; the full id is p::sc::n (p= of the row or its <f>) and selectors take it. -->
<!-- t=modscope=a-file's-MODULE-SCOPE(n=<file-scope>):the-statements-outside-every-named-definition,where-a-top-level-call-and-an-anonymous-callback-body's-calls-live;a-CALLER-never-a-callee(nothing-in-the-source-can-name-it)-with-no-body-to-expand;a-file-with-no-such-call-has-no-such-row -->
<!-- t=type|alias|functype=a-Go-named-type-by-its-written-form:type=a-defined-type-whose-WRITTEN-form-is-not-a-struct/iface/func-literal(type-N-string;type-W-Pair-too,whatever-Pair-is-underneath),alias=type-A=B,functype=type-F-func(...) -->
<!-- t=alias|functype-in-C++-and-.h:alias=using-X=Y(also-templated-or-class-scope)or-namespace-L=lib(defs=X-prints-its-written-target-as-to=),functype=a-typedef-of-a-function-or-function-pointer-type(typedef-void(*F)(int));other-typedefs-read-t=struct -->
<r schema="ripwire.map/v1" root="." pr_iters="40" lens="k,est_tokens">
<f p="src/infra/Diagnostics.h" layer="infra">
<s t="macro" n="RW_ASSUME_">
<c n="RW_CHECK_"/>
</s>
</f>
<f p="src/infra/namesplit.h" layer="infra">
<s t="fn" n="isIdentChar" sc="namesplit">
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
</f>
<inv listed="5" unlisted="4833">
<entry p="scripts/changelog_assemble.py" n="main">
<c n="repoRoot"/>
<c n="fragmentNames"/>
… [89 more display lines; full output is 10256 bytes on 1 raw line(s)]
`````


---

# navigate / answer a question

## `./build/ripwire . --around=rankGraphTeleport`

*Ego graph around one symbol — depth 1 BY DEFAULT now (the root's depth= says so): ~6 KB where the 2-hop neighbourhood is ~64 KB on this repo.*

`````
<!-- ripwire around schema=ripwire.around/v1: call neighbourhood of of=: depth= hops, fanout= kept per hop; absent rows lie outside that boundary. est_tokens=: price as emitted (an upper bound under compact). root=: p= relative to it. declined=K: K call sites without edges, including inert Elixir quote sites after unquote/unquote_splicing re-entry. external=K: K calls proven outside the tree, no edge. locality_pinned=K: K calls pinned by locality alone (a guess). extent_suspect_syms=K: K defs failed containment, corpus-wide. macro_blanked_files=K: K files indexed from a macro-blanked re-parse. overloads=N: N same-name defs merged in this row; shown= counts each. prov=scip|binding|import|split|final-segment: how that <c> edge bound (absent: one unique name); split = one arm of an amb= pick; final-segment = a qualified type matched by last name only. files=/symbols=: files and symbols indexed; edges= distinct call edges; shown= symbols printed, a merged row counting each def; ambiguous= calls split over several defs, corpus-wide; unresolved= calls with in-tree evidence and no edge (every def language-filtered or unreachable, or binding refused); order= rows by rank (important-first, important-last; (auto:fill) = flipped past a size threshold) or by path (stable). skipped_oversize=K: K files over a size ceiling, not indexed. unindexed=ext:N: N text files of that extension no grammar reads (6 extensions at most). unindexed_exts=E: E such extensions in all, the list cut. <c via="name">: that callee matched by name alone (receiver unproven); it does NOT mean the edge is false. <c x=N>: N same-named via=name rows merged; callees=FILE:SYM lists all. sc=: enclosing scope; the full id is p::sc::n (p= of the row or its <f>) and selectors take it. amb=K: K calls split over several defs. layer=: built-in arch layer (game|infra|render|math|audio|ai|test) from a dir name in p=; absent if none. f p=: a file; s t= n=: kind, name; c n=: a resolved callee. s k=: rank. -->
<!-- t=modscope=a-file's-MODULE-SCOPE(n=<file-scope>):the-statements-outside-every-named-definition,where-a-top-level-call-and-an-anonymous-callback-body's-calls-live;a-CALLER-never-a-callee(nothing-in-the-source-can-name-it)-with-no-body-to-expand;a-file-with-no-such-call-has-no-such-row -->
<!-- t=type|alias|functype=a-Go-named-type-by-its-written-form:type=a-defined-type-whose-WRITTEN-form-is-not-a-struct/iface/func-literal(type-N-string;type-W-Pair-too,whatever-Pair-is-underneath),alias=type-A=B,functype=type-F-func(...) -->
<!-- t=alias|functype-in-C++-and-.h:alias=using-X=Y(also-templated-or-class-scope)or-namespace-L=lib(defs=X-prints-its-written-target-as-to=),functype=a-typedef-of-a-function-or-function-pointer-type(typedef-void(*F)(int));other-typedefs-read-t=struct -->
<!-- a bound BIT this walk, so raising it would return more: depth_truncated=1 means at least one symbol one hop past depth= is absent; fanout_cut=N means N distinct symbols were dropped by the fanout= cap and appear NOWHERE here (exact, not a floor: a neighbour another hub re-admitted is not counted). Neither attribute is emitted when its bound cut nothing, so absent means that bound did not bind and raising it returns nothing new. The knobs are around-depth=N and around-fanout=K. -->
<!-- files=4838 symbols=44600 edges=44429 shown=12 est_tokens=3402 ambiguous=3634 unresolved=20069 locality_pinned=14 external=12457 declined=45295 extent_suspect_syms=12 macro_blanked_files=7 skipped_oversize=15 unindexed="txt:85,tsv:54,mod:33,xml:33,jsonl:26,scm:25" unindexed_exts=23 order=important-first -->
<r schema="ripwire.around/v1" root="." of="rankGraphTeleport" depth="1" fanout="32" depth_truncated="1" est_tokens="3402">
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
<s t="fn" n="runEval" sc="rw" amb="4" k="0.5000">
… [169 more display lines; full output is 8418 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --around=rankGraphTeleport --around-depth=2`

*The restoring knob: --around-depth=2 brings back the whole 2-hop neighbourhood (depth="2" on the root) — pay for it only when the 1-hop view was not enough.*

`````
<ctx schema="ripwire.pack-signatures/v1">
<!-- ripwire pack-signatures schema=ripwire.pack-signatures/v1: the ranked map plus <sigs>
<d l= n= sc= pure=> signature rows. est_tokens=: price as emitted (an upper bound under compact). root=: p= relative to it. declined=K: K call sites without edges, including inert Elixir quote sites after unquote/unquote_splicing re-entry. external=K: K calls proven outside the tree, no edge. locali … [line truncated: 1576 more bytes on this line]
<!-- t=modscope=a-file's-MODULE-SCOPE(n=<file-scope>):the-statements-outside-every-named-definition,where-a-top-level-call-and-an-anonymous-callback-body's-calls-live;a-CALLER-never-a-callee(nothing-in-the-source-can-name-it)-with-no-body-to-expand;a-file-with-no-such-call-has-no-such-row -->
<!-- t=type|alias|functype=a-Go-named-type-by-its-written-form:type=a-defined-type-whose-WRITTEN-form-is-not-a-struct/iface/func-literal(type-N-string;type-W-Pair-too,whatever-Pair-is-underneath),alias=type-A=B,functype=type-F-func(...) -->
<!-- t=alias|functype-in-C++-and-.h:alias=using-X=Y(also-templated-or-class-scope)or-namespace-L=lib(defs=X-prints-its-written-target-as-to=),functype=a-typedef-of-a-function-or-function-pointer-type(typedef-void(*F)(int));other-typedefs-read-t=struct -->
<!-- a bound BIT this walk, so raising it would return more: depth_truncated=1 means at least one symbol one hop past depth= is absent; fanout_cut=N means N distinct symbols were dropped by the fanout= cap and appear NOWHERE here (exact, not a floor: a neighbour another hub re-admitted is not counted). Neither attribute is emitted when its bound cut nothing, so absent means that bound did not bind and raising it returns nothing new. The knobs are around-depth=N and around-fanout=K. -->
<!-- files=4838 symbols=44600 edges=44429 shown=158 est_tokens=29968 ambiguous=3634 unresolved=20069 locality_pinned=14 external=12457 declined=45295 extent_suspect_syms=12 macro_blanked_files=7 skipped_oversize=15 unindexed="txt:85,tsv:54,mod:33,xml:33,jsonl:26,scm:25" unindexed_exts=23 order=important-first -->
<r root="." of="rankGraphTeleport" depth="2" fanout="32" depth_truncated="1" fanout_cut="116" est_tokens="30570">
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
… [2441 more display lines; full output is 74348 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --around=rankGraphTeleport --around-fanout=4`

*The other knob: --around-fanout=4 keeps only the 4 strongest edges per node (default 32) — the same 1-hop depth, a quarter of the rows.*

`````
<!-- ripwire around schema=ripwire.around/v1: call neighbourhood of of=: depth= hops, fanout= kept per hop; absent rows lie outside that boundary. est_tokens=: price as emitted (an upper bound under compact). root=: p= relative to it. declined=K: K call sites without edges, including inert Elixir quote sites after unquote/unquote_splicing re-entry. external=K: K calls proven outside the tree, no edge. locality_pinned=K: K calls pinned by locality alone (a guess). extent_suspect_syms=K: K defs failed containment, corpus-wide. macro_blanked_files=K: K files indexed from a macro-blanked re-parse. prov=scip|binding|import|split|final-segment: how that <c> edge bound (absent: one unique name); split = one arm of an amb= pick; final-segment = a qualified type matched by last name only. files=/symbols=: files and symbols indexed; edges= distinct call edges; shown= symbols printed, a merged row counting each def; ambiguous= calls split over several defs, corpus-wide; unresolved= calls with in-tree evidence and no edge (every def language-filtered or unreachable, or binding refused); order= rows by rank (important-first, important-last; (auto:fill) = flipped past a size threshold) or by path (stable). skipped_oversize=K: K files over a size ceiling, not indexed. unindexed=ext:N: N text files of that extension no grammar reads (6 extensions at most). unindexed_exts=E: E such extensions in all, the list cut. sc=: enclosing scope; the full id is p::sc::n (p= of the row or its <f>) and selectors take it. amb=K: K calls split over several defs. f p=: a file; s t= n=: kind, name; c n=: a resolved callee. s k=: rank. -->
<!-- t=modscope=a-file's-MODULE-SCOPE(n=<file-scope>):the-statements-outside-every-named-definition,where-a-top-level-call-and-an-anonymous-callback-body's-calls-live;a-CALLER-never-a-callee(nothing-in-the-source-can-name-it)-with-no-body-to-expand;a-file-with-no-such-call-has-no-such-row -->
<!-- t=type|alias|functype=a-Go-named-type-by-its-written-form:type=a-defined-type-whose-WRITTEN-form-is-not-a-struct/iface/func-literal(type-N-string;type-W-Pair-too,whatever-Pair-is-underneath),alias=type-A=B,functype=type-F-func(...) -->
<!-- t=alias|functype-in-C++-and-.h:alias=using-X=Y(also-templated-or-class-scope)or-namespace-L=lib(defs=X-prints-its-written-target-as-to=),functype=a-typedef-of-a-function-or-function-pointer-type(typedef-void(*F)(int));other-typedefs-read-t=struct -->
<!-- a bound BIT this walk, so raising it would return more: depth_truncated=1 means at least one symbol one hop past depth= is absent; fanout_cut=N means N distinct symbols were dropped by the fanout= cap and appear NOWHERE here (exact, not a floor: a neighbour another hub re-admitted is not counted). Neither attribute is emitted when its bound cut nothing, so absent means that bound did not bind and raising it returns nothing new. The knobs are around-depth=N and around-fanout=K. -->
<!-- files=4838 symbols=44600 edges=44429 shown=5 est_tokens=1719 ambiguous=3634 unresolved=20069 locality_pinned=14 external=12457 declined=45295 extent_suspect_syms=12 macro_blanked_files=7 skipped_oversize=15 unindexed="txt:85,tsv:54,mod:33,xml:33,jsonl:26,scm:25" unindexed_exts=23 order=important-first -->
<r schema="ripwire.around/v1" root="." of="rankGraphTeleport" depth="1" fanout="4" depth_truncated="1" fanout_cut="7" est_tokens="1719">
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
… [14 more display lines; full output is 4254 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --callers=rankGraphTeleport`

*Who calls SYM (1-hop in-edges).*

`````
<!-- ripwire callers schema=ripwire.callers/v1: 1-hop CALLERS of of= (defs= matched, count= distinct symbols): <s t= n= p=>; hop_tested=/hop_untested=. counts_floor=1: every count is a FLOOR, never a total. graph_ambiguous=/graph_unresolved=: resolver gauge. graph_unindexed=N: N files no grammar could read (the map header's unindexed=); their calls raise neither gauge. root=: p= relative to it. <s sites_at=>: its leaf-name calls not proven elsewhere, as [file:]line (p=: def line, default file); not proof each binds. next=: the one pasteable follow-up. -->
<callers schema="ripwire.callers/v1" of="rankGraphTeleport" defs="1" count="7" root="." hop_tested="0" hop_untested="7" graph_ambiguous="3634" graph_unresolved="20069" graph_unindexed="313" counts_floor="1" next="--uses=rankGraphTeleport">
<s t="fn" n="getIndex" p="src/mcpindex.h:1224" sites_at="1340"/>
<s t="fn" n="rankGraph" p="src/graph.h:14662" sites_at="14666"/>
<s t="fn" n="anchoredLexicalRank" p="src/graph.h:15331" sites_at="15382"/>
<s t="fn" n="runEval" p="src/eval.h:171" sites_at="328"/>
<s t="fn" n="churnDecayRanking" p="src/main.cpp:1432" sites_at="1446"/>
<s t="fn" n="churnRankedGraph" p="src/main.cpp:1471" sites_at="1485 1486 1500"/>
<s t="fn" n="runDefaultMap" p="src/main.cpp:1758" sites_at="1878"/>
</callers>
`````

## `./build/ripwire . --callers=rankGraphTeleport --legend=full`

*The same rows under --legend=full: the default is the compact dialect (one compact comment plus schema="ripwire.callers/v1" on the root), and --legend=full restores the prose legend — every row byte and every completeness attribute (counts_floor=, graph_ambiguous=, next=) identical, ~3 KB more legend. Works on EVERY XML verb.*

`````
<!-- ripwire callers/callees: the 1-hop call hierarchy read off the call graph — the callers form lists symbols that CALL of=; the callees form lists symbols of= itself calls. of= is the selector you passed, defs= how many DEFINITIONS it resolved to (rows UNION every def's neighbours), count= the DISTINCT neighbour symbols (a floor, per counts_floor=), windowed by limit= and offset=. A neighbour that is an indexed function-like #define is a macro row (t="macro", role="macro" on the XML row): the edge crosses a macro expansion, not a plain call — rows carry no role= otherwise. Rows are ordered SOURCE first, then test/bench, then docs; within a tier callers rank by each row's own caller count (most-called first); callees keep path order. hop_tested=/hop_untested= partition count= by the tested= lens below (1-hop, never transitive). tested="1" on a row means an indexed test transitively reaches it (never 0, omitted when it does not). BLIND SPOT the test-gate legend also names: only a CALL EDGE from an INDEXED test symbol counts here, so a shell or CLI-level test running a built binary as a SUBPROCESS is invisible to it and a repo tested that way reads all-untested. Read untested= as no in-process test reaches it, not as no test covers it. next= is the one pasteable follow-up (the uses verb on this selector: the call sites). sites_at= on a caller row: its calls of the called LEAF name, bar ones proven elsewhere, as [file:]line (space-separated, ascending; two calls on a line are one site; no file: p='s); p= stays where the caller is DEFINED. Matched by name like the uses verb's call rows, so not proof each binds here; absent when no call there is spelled like it (an aliased import). counts_floor="1" means every count here is a FLOOR, never a total: edges are extracted from source TEXT by NAME. Missing: dynamic dispatch (virtual/interface/duck-typed), a most-vexing-parse declaration with no call expression, a function-pointer/callback bound to more than one function in scope (reassigned, table-indexed, lambda-bound, or address-taken/reference-bound), and a plain-name binding (fp=handler) whose variable type is not PROVABLY a function pointer (a same-file typedef/declarator; a HEADER typedef is missed; auto/template types are read as unpinned, so KEPT). A macro-generated call site is role="macro" only when its name uniquely names an indexed function-like #define (C-family, t="macro"); a shared name stays a plain call, an unindexed macro is no edge. Read a zero as "none found", never as "none exists". graph_ambiguous=/graph_unresolved= are the whole graph's resolver gauge (calls split over several defs / calls whose in-repo defs were all language-filtered), the map header's ambiguous=/unresolved=. graph_unindexed=N is a third gauge: files no grammar could read (the map header's unindexed=), whose calls raise neither gauge above; absent when zero, and so is this sentence. COUNTING UNIT differs by verb: callers, callees, edit-check, graph-query and pr-context counts are DISTINCT SYMBOLS (repeated calls from one caller, and calls to two overloads, collapse into ONE row; multiplicity survives only in the call graph's edge weight). The reach counts (impact's reaches=, pr-context's dependents=) are the size of a transitive reach SET, each symbol counted once. The uses verb counts call SITES, one row per occurrence — a larger count there for the same symbol is these units agreeing, not disagreeing. The map header's edges= is a unit again different — distinct (caller,callee) PAIRS — and that document carries neither this marker nor this clause. -->
<!-- root= on this element is the crawl root every p= below is RELATIVE to (single-root runs only; absent => p= is the path ingest itself used, unchanged). -->
<callers of="rankGraphTeleport" defs="1" count="7" root="." hop_tested="0" hop_untested="7" graph_ambiguous="3634" graph_unresolved="20069" graph_unindexed="313" counts_floor="1" next="--uses=rankGraphTeleport">
<s t="fn" n="getIndex" p="src/mcpindex.h:1224" sites_at="1340"/>
<s t="fn" n="rankGraph" p="src/graph.h:14662" sites_at="14666"/>
<s t="fn" n="anchoredLexicalRank" p="src/graph.h:15331" sites_at="15382"/>
<s t="fn" n="runEval" p="src/eval.h:171" sites_at="328"/>
<s t="fn" n="churnDecayRanking" p="src/main.cpp:1432" sites_at="1446"/>
<s t="fn" n="churnRankedGraph" p="src/main.cpp:1471" sites_at="1485 1486 1500"/>
<s t="fn" n="runDefaultMap" p="src/main.cpp:1758" sites_at="1878"/>
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
ripwire: --callers symbol not found: DoesNotExist (note: the lexical definition scan stopped at its budget, 4096 files or 16 MiB, before reading every file, so this miss is not proof the bytes define nothing; --grep=DoesNotExist lists its text uses)
`````

## `./build/ripwire . --callees=rankGraphTeleport`

*What SYM calls (1-hop out-edges).*

`````
<!-- ripwire callees schema=ripwire.callees/v1: 1-hop CALLEES of of= (defs= matched, count= distinct symbols): <s t= n= p= role= tested=>. counts_floor=1: every count is a FLOOR, never a total. graph_ambiguous=/graph_unresolved=: resolver gauge. graph_unindexed=N: N files no grammar could read (the map header's unindexed=); their calls raise neither gauge. stdm n= calls=: of declined_calls=, calls named like a standard-type member of their language (C++ container/string/optional/smart pointer, Rust collection/string/Option/Result; n=) on a receiver no rule tied to an in-tree class (Rust: one of an in-tree type no rule typed too: a generic bound, dyn or impl Trait, a type alias, a glob of a glob, a tuple-struct field, a non-plain pattern, behind Option / Result / Rc / Arc / RefCell / Cell / Mutex / RwLock); no edge or row (may be the std member). root=: p= relative to it. prov=scip|binding|import|split|final-segment: how that <c> edge bound (absent: one unique name); split = one arm of an amb= pick; final-segment = a qualified type matched by last name only. <s tested=1>: a non-test row an indexed test transitively reaches (absent otherwise, never 0). declined_calls=K: K call sites left unbound, in no count; <dc n= l=|in= p= cands=K via=declined>: one such call SITE (callees: called name, line; callers: calling def, file:line); NOT an edge or a caller/callee claim; cands=K: K in-tree defs it could have meant (K may be 1), the resolver proved none; not a claim this call reaches any of them. dc gate=: builtin or std, a name gate declined it; side, a Ruby call whose in-reach defs answer on the other side of self. next=: the one pasteable follow-up. hop_tested=/hop_untested=: count= split by whether an indexed test reaches the row (in-process calls only). -->
<callees schema="ripwire.callees/v1" of="rankGraphTeleport" defs="1" count="4" root="." hop_tested="3" hop_untested="1" declined_calls="6" graph_ambiguous="3634" graph_unresolved="20069" graph_unindexed="313" counts_floor="1" next="--expand=rankGraphTeleport">
<s t="fn" n="biasPrior" p="src/graph.h:14578"/>
<s t="macro" n="PROFILE_SCOPE_DESCRIBE" p="src/infra/profileScope.h:1282" role="macro" tested="1" prov="split"/>
<s t="macro" n="PROFILE_SCOPE_DESCRIBE" p="src/infra/profileScope.h:1296" role="macro" tested="1" prov="split"/>
<s t="fn" n="pageRankDouble" p="src/pagerank.cpp:99" tested="1"/>
<stdm n="begin,end,size" calls="6"/>
<dc n="size" l="14623" cands="2" via="declined" gate="std"/>
<dc n="begin" l="14624" cands="7" via="declined"/>
<dc n="end" l="14624" cands="7" via="declined"/>
<dc n="begin" l="14645" cands="7" via="declined"/>
<dc n="end" l="14645" cands="7" via="declined"/>
<dc n="begin" l="14645" cands="7" via="declined"/>
</callees>
`````

## `./build/ripwire . --uses=rankGraphTeleport`

*The resolvable use-sites (call/read/write/import/extends) with file:line; count= is a floor.*

`````
<!-- ripwire uses schema=ripwire.uses/v1: resolvable use-sites of of=: <u role=call|macro|read|write|import|extends|type p=file:line in_id=>. counts_floor=1: every count is a FLOOR, never a total. graph_ambiguous=/graph_unresolved=: resolver gauge. graph_unindexed=N: N files no grammar could read (the map header's unindexed=); their calls raise neither gauge. root=: p= relative to it. defs=N: definitions the selector matched; qualify file:name to narrow the call sites. external=1: of= has no definition in the indexed tree under any spelling (stdlib/third-party). count=N: unhedged use-site rows (a floor). -->
<uses schema="ripwire.uses/v1" of="rankGraphTeleport" defs="1" external="0" count="9" root="." graph_ambiguous="3634" graph_unresolved="20069" graph_unindexed="313" counts_floor="1">
<u role="call" p="src/mcpindex.h:1340" in_id="src/mcpindex.h::rw::getIndex"/>
<u role="call" p="src/graph.h:14666" in_id="src/graph.h::rw::rankGraph"/>
<u role="call" p="src/graph.h:15382" in_id="src/graph.h::rw::anchoredLexicalRank"/>
<u role="call" p="src/eval.h:328" in_id="src/eval.h::rw::runEval"/>
<u role="call" p="src/main.cpp:1446" in_id="churnDecayRanking"/>
<u role="call" p="src/main.cpp:1485" in_id="churnRankedGraph"/>
<u role="call" p="src/main.cpp:1486" in_id="churnRankedGraph"/>
<u role="call" p="src/main.cpp:1500" in_id="churnRankedGraph"/>
<u role="call" p="src/main.cpp:1878" in_id="runDefaultMap"/>
</uses>
`````

## `./build/ripwire . --graph-query='and(callers(name("rankGraphTeleport"),2),kind(all,fn))'`

*Composable node-set query: functions within 2 caller-hops of rankGraphTeleport.*

`````
<!-- ripwire graph-query schema=ripwire.graph-query/v1: graph-query expression over the symbol graph: <s t= n= p=> matching rows. window: shown= capped= (capped=1 cut). counts_floor=1: every count is a FLOOR, never a total. graph_ambiguous=/graph_unresolved=: resolver gauge. graph_unindexed=N: N files no grammar could read (the map header's unindexed=); their calls raise neither gauge. root=: p= relative to it. pr_iters=N: PageRank iterations. expr=: the expression as given; count=: symbols it matched (rows page by shown=/total=). -->
<query schema="ripwire.graph-query/v1" expr="and(callers(name(&quot;rankGraphTeleport&quot;),2),kind(all,fn))" count="59" shown="59" capped="0" graph_ambiguous="3634" graph_unresolved="20069" graph_unindexed="313" counts_floor="1" root="." pr_iters="40">
<s t="fn" n="getIndex" p="src/mcpindex.h:1224"/>
<s t="fn" n="rankGraph" p="src/graph.h:14662"/>
<s t="fn" n="anchoredLexicalRank" p="src/graph.h:15331"/>
<s t="fn" n="emitCommunitiesReport" p="src/verbs_report.h:2732"/>
<s t="fn" n="emitCommunityDrill" p="src/verbs_report.h:2893"/>
<s t="fn" n="computeLensRanking" p="src/verbs_for.h:115"/>
<s t="fn" n="dispatchMainBody" p="src/main.cpp:4653"/>
<s t="fn" n="postCheckJsonBuilt" p="src/mcpedit.h:1119"/>
<s t="fn" n="buildGraphRecorded" p="src/warmsnap_graph.h:448"/>
<s t="fn" n="fetchBody" p="src/mcpverbs.h:5901"/>
<s t="fn" n="runEvalRetrieval" p="src/eval.h:716"/>
<s t="fn" n="runEvalMined" p="src/eval.h:1089"/>
<s t="fn" n="dispatchMcpLine" p="src/mcp.h:1151"/>
<s t="fn" n="runEditVerb" p="src/mcpedit.h:1216"/>
<s t="fn" n="churnDecayRanking" p="src/main.cpp:1432"/>
<s t="fn" n="fetchBodyByName" p="src/mcpverbs.h:5824"/>
<s t="fn" n="symbolQueryJson" p="src/mcpverbs.h:792"/>
<s t="fn" n="anchoredFileScore" p="src/eval.h:111"/>
<s t="fn" n="pathText" p="src/mcpverbs.h:4040"/>
<s t="fn" n="analyzeToString" p="src/mcpverbs.h:456"/>
<s t="fn" n="grepHitsJson" p="src/mcpverbs.h:1350"/>
<s t="fn" n="cochangePartnersJson" p="src/mcpverbs.h:1530"/>
<s t="fn" n="mentionsJson" p="src/mcpverbs.h:1942"/>
<s t="fn" n="forTaskText" p="src/mcpverbs.h:2649"/>
<s t="fn" n="legoText" p="src/mcpverbs.h:3230"/>
<s t="fn" n="ownersText" p="src/mcpverbs.h:3271"/>
<s t="fn" n="exemplarText" p="src/mcpverbs.h:3412"/>
<s t="fn" n="impactText" p="src/mcpverbs.h:3492"/>
… [32 more display lines; full output is 3884 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --external-surface`

*Names referenced but never defined in-corpus (stdlib/third-party surface). The root carries names/shown/capped; the default is a 100-row window now, so total= and a pasteable next= join them when it bites (the explicit --limit form carries the same quintet). The sh BUILTINS (cd/echo/set…) are dropped and COUNTED as builtins_excluded= — grep/sed/git stay, they ARE the surface.*

`````
<!-- ripwire external-surface schema=ripwire.external-surface/v1: names used but never defined in the index: <x n= lang= refs= calls=>. window: shown= total= capped= has_more= next_offset= offset= limit= (capped=1 cut; next_offset= pastes as offset=). next=: the one pasteable follow-up. names=N: distinct external names (the x rows' total). builtins_excluded=N: sh BUILTIN rows (echo printf cd exit test ...) dropped from names=; the include-builtins flag keeps them. -->
<external-surface schema="ripwire.external-surface/v1" names="3754" builtins_excluded="21" shown="100" capped="1" total="3754" has_more="1" next_offset="100" offset="0" limit="0" next="--external-surface --offset=100">
<x n="grep" lang="sh" refs="18004" calls="18004"/>
<x n="cat" lang="sh" refs="3606" calls="3606"/>
<x n="tr" lang="sh" refs="2766" calls="2766"/>
<x n="python3" lang="sh" refs="2437" calls="2437"/>
<x n="sed" lang="sh" refs="2248" calls="2248"/>
<x n="string_view" lang="cpp" refs="1533" calls="1533"/>
<x n="to_string" lang="cpp" refs="1395" calls="1395"/>
<x n="wc" lang="sh" refs="1206" calls="1206"/>
<x n="ts_node_is_null" lang="cpp" refs="1177" calls="1177"/>
<x n="print" lang="py" refs="1090" calls="1090"/>
<x n="mktemp" lang="sh" refs="1032" calls="1032"/>
<x n="dirname" lang="sh" refs="1009" calls="1009"/>
<x n="uint32_t" lang="cpp" refs="930" calls="930"/>
<x n="ts_node_type" lang="cpp" refs="923" calls="923"/>
<x n="cmp" lang="sh" refs="879" calls="879"/>
<x n="size_t" lang="cpp" refs="868" calls="868"/>
<x n="xmllint" lang="sh" refs="720" calls="720"/>
<x n="stdout" lang="cpp" refs="718" calls="0"/>
<x n="starts_with" lang="cpp" refs="703" calls="703"/>
<x n="stderr" lang="cpp" refs="641" calls="0"/>
<x n="awk" lang="sh" refs="613" calls="613"/>
<x n="diff" lang="sh" refs="595" calls="595"/>
<x n="rm" lang="sh" refs="482" calls="482"/>
<x n="rfind" lang="cpp" refs="458" calls="458"/>
<x n="any_of" lang="cpp" refs="438" calls="438"/>
<x n="add_argument" lang="py" refs="332" calls="332"/>
<x n="ends_with" lang="cpp" refs="300" calls="300"/>
<x n="ts_node_start_byte" lang="cpp" refs="299" calls="299"/>
… [73 more display lines; full output is 5633 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --external-surface --include-builtins`

*The restoring knob: --include-builtins keeps the shell builtins in the same 100-row window (they now compete for rows, so the window's tail differs).*

`````
<!-- ripwire external-surface schema=ripwire.external-surface/v1: names used but never defined in the index: <x n= lang= refs= calls=>. window: shown= total= capped= has_more= next_offset= offset= limit= (capped=1 cut; next_offset= pastes as offset=). next=: the one pasteable follow-up. names=N: distinct external names (the x rows' total). -->
<external-surface schema="ripwire.external-surface/v1" names="3775" shown="100" capped="1" total="3775" has_more="1" next_offset="100" offset="0" limit="0" next="--external-surface --include-builtins --offset=100">
<x n="grep" lang="sh" refs="18004" calls="18004"/>
<x n="printf" lang="sh" refs="17071" calls="17071"/>
<x n="echo" lang="sh" refs="9844" calls="9844"/>
<x n="exit" lang="sh" refs="3613" calls="3613"/>
<x n="cat" lang="sh" refs="3606" calls="3606"/>
<x n="cd" lang="sh" refs="2901" calls="2901"/>
<x n="tr" lang="sh" refs="2766" calls="2766"/>
<x n="python3" lang="sh" refs="2437" calls="2437"/>
<x n="sed" lang="sh" refs="2248" calls="2248"/>
<x n="return" lang="sh" refs="1823" calls="1823"/>
<x n="string_view" lang="cpp" refs="1533" calls="1533"/>
<x n="to_string" lang="cpp" refs="1395" calls="1395"/>
<x n="wc" lang="sh" refs="1206" calls="1206"/>
<x n="ts_node_is_null" lang="cpp" refs="1177" calls="1177"/>
<x n="command" lang="sh" refs="1170" calls="1170"/>
<x n="print" lang="py" refs="1090" calls="1090"/>
<x n="mktemp" lang="sh" refs="1032" calls="1032"/>
<x n="dirname" lang="sh" refs="1009" calls="1009"/>
<x n="pwd" lang="sh" refs="937" calls="937"/>
<x n="uint32_t" lang="cpp" refs="930" calls="930"/>
<x n="ts_node_type" lang="cpp" refs="923" calls="923"/>
<x n="trap" lang="sh" refs="894" calls="894"/>
<x n="cmp" lang="sh" refs="879" calls="879"/>
<x n="size_t" lang="cpp" refs="868" calls="868"/>
<x n="xmllint" lang="sh" refs="720" calls="720"/>
<x n="stdout" lang="cpp" refs="718" calls="0"/>
<x n="starts_with" lang="cpp" refs="703" calls="703"/>
<x n="stderr" lang="cpp" refs="641" calls="0"/>
… [73 more display lines; full output is 5508 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --path=main,rankGraphTeleport`

*Shortest directed call-path SRC -> DST. CHANGED: now reports from_p/to_p/from_defs and resolves the right `main` (was reachable="0").*

`````
<!-- ripwire path schema=ripwire.path/v1: one DIRECTED call path from= to to=, each <s t= n= p=> a hop; reachable=0 hops=0 when none shown. alts_capped=: 1 = cut. counts_floor=1: every count is a FLOOR, never a total. graph_ambiguous=/graph_unresolved=: resolver gauge. graph_unindexed=N: N files no grammar could read (the map header's unindexed=); their calls raise neither gauge. root=: p= relative to it. next=: the one pasteable follow-up. s site=: a call of this row's name in the row above (arity fit, then owner, first); by name, not proof. s sites=N: N such lines. s call=: its text, <=3 lines/120 B, U+2026=cut; pair 1 only. s sig=: this row's signature, <=160 B; pair 1 only. alts side=from|to of=: further definitions that endpoint's name binds, not printed above (the pick is not provably unique): <d p= sel= class=>, sel= pastes as that endpoint. alts shown_alts=K defs=N: K of the other rows shown; alts_capped=1 they are cut; next= pages the rest. from_p=/to_p=: the definitions from= and to= were bound to. from_defs=/to_defs=: definitions of each name, all searched; above 1, qualify file:name. -->
<path schema="ripwire.path/v1" from="main" to="rankGraphTeleport" from_p="src/main.cpp:4509" to_p="src/graph.h:14619" from_defs="189" to_defs="1" reachable="1" hops="6" next="--expand=src/main.cpp:4564:finishMainRun" root="." graph_ambiguous="3634" graph_unresolved="20069" graph_unindexed="313" coun … [line truncated: 13 more bytes on this line]
<s t="fn" n="main" p="src/main.cpp:4509"/>
<s t="fn" n="finishMainRun" p="src/main.cpp:4564" site="src/main.cpp:4558" call="const int rc = finishMainRun( cfg, argv );" sig="static int finishMainRun( const rw::Config&amp; cfg, char** argv )"/>
<s t="fn" n="runWithCompactLegend" p="src/main.cpp:4377" site="src/main.cpp:4567" call="const int rc = runWithCompactLegend( cfg, argv );" sig="static int runWithCompactLegend( const rw::Config&amp; cfg, char** argv )"/>
<s t="fn" n="dispatchMain" p="src/main.cpp:6267" site="src/main.cpp:4388" sites="4" call="return dispatchMain( cfg, argv );" sig="static int dispatchMain( const rw::Config&amp; cfg, char** argv )"/>
<s t="fn" n="dispatchMainBody" p="src/main.cpp:4653" site="src/main.cpp:6271" call="return dispatchMainBody( cfg, argv );" sig="static int dispatchMainBody( const rw::Config&amp; cfg, char** argv )"/>
<s t="fn" n="runDefaultMap" p="src/main.cpp:1758" site="src/main.cpp:6028" sites="2" call="return runDefaultMap( dsp );" sig="int runDefaultMap( const MainDispatch&amp; d )"/>
<s t="fn" n="rankGraphTeleport" p="src/graph.h:14619" site="src/main.cpp:1878" call="rank = rw::takeRank( rankGraphTeleport( g, diffTeleport( ing, changed ) ), rankDisclosure );" sig="inline RankedGraph rankGraphTeleport( const Graph&amp; g, const std::vector&lt;float&gt;&amp; p, float alpha = 0.85f … [line truncated: 5 more bytes on this line]
<alts side="from" of="main" shown_alts="16" alts_capped="1" defs="183" next="--defs=main --offset=17">
<d p="docs/counts_snapshot.py:230" sel="docs/counts_snapshot.py:main" class="source"/>
<d p="docs/docs_commands_build.py:900" sel="docs/docs_commands_build.py:main" class="source"/>
<d p="scripts/changelog_assemble.py:170" sel="scripts/changelog_assemble.py:main" class="source"/>
<d p="scripts/merge_resolve.py:208" sel="scripts/merge_resolve.py:main" class="source"/>
<d p="scripts/optremarks.py:286" sel="scripts/optremarks.py:main" class="source"/>
<d p="scripts/tidyadvisory_diff.py:313" sel="scripts/tidyadvisory_diff.py:main" class="source"/>
<d p="src/tsprobe.cpp:70" sel="src/tsprobe.cpp:main" class="source"/>
<d p="bench/agentloop/analyze.py:345" sel="bench/agentloop/analyze.py:main" class="test"/>
<d p="bench/agentloop/backfill_claude_transcripts.py:104" sel="bench/agentloop/backfill_claude_transcripts.py:main" class="test"/>
<d p="bench/agentloop/editsuite/gen_expected.py:47" sel="bench/agentloop/editsuite/gen_expected.py:main" class="test"/>
<d p="bench/agentloop/followup_calls.py:160" sel="bench/agentloop/followup_calls.py:main" class="test"/>
<d p="bench/agentloop/grade_answers.py:609" sel="bench/agentloop/grade_answers.py:main" class="test"/>
<d p="bench/agentloop/power_sim.py:209" sel="bench/agentloop/power_sim.py:main" class="test"/>
<d p="bench/agentloop/run_agentloop.py:1237" sel="bench/agentloop/run_agentloop.py:main" class="test"/>
<d p="bench/agentloop/run_editsuite.py:530" sel="bench/agentloop/run_editsuite.py:main" class="test"/>
<d p="bench/agentloop/select_tasks.py:144" sel="bench/agentloop/select_tasks.py:main" class="test"/>
</alts>
</path>
`````

## `./build/ripwire . --defs=main,rankGraphTeleport`

*Which definitions each name binds, one row per definition group with sel= (the spelling that picks it alone in any verb), class=source|test and in= callers; source first.*

`````
<!-- ripwire defs schema=ripwire.defs/v1: per <name q= defs=> the parsed definitions the name binds (defs= groups; a prototype with its definition is one): <d n= t= p= sel= lang= class=source|test in=>, sel= binds that one alone in any SYM verb, in= distinct callers (a floor); source first, then in=, then path. window: shown= offset= (capped=1 cut). root=: p= relative to it. <d in=N>: N callers in the index (absent: not measured). next=: the one pasteable follow-up. name data_defs=K: data keys or doc headings of that name (JSON/YAML key, markdown heading), not code, not in defs=. name shown=K offset=M: rows M..M+K of defs=; next= pages the rest. name next=: the next page, or (defs=0) the single-name call whose refusal names near names. -->
<defs schema="ripwire.defs/v1" root=".">
<name q="main" defs="183" data_defs="6" shown="16" offset="0" next="--defs=main --offset=16">
<d n="main" t="fn" p="docs/counts_snapshot.py:230" sel="docs/counts_snapshot.py:main" lang="py" class="source" in="1"/>
<d n="main" t="fn" p="docs/docs_commands_build.py:900" sel="docs/docs_commands_build.py:main" lang="py" class="source" in="1"/>
<d n="main" t="fn" p="scripts/changelog_assemble.py:170" sel="scripts/changelog_assemble.py:main" lang="py" class="source" in="1"/>
<d n="main" t="fn" p="scripts/merge_resolve.py:208" sel="scripts/merge_resolve.py:main" lang="py" class="source" in="1"/>
<d n="main" t="fn" p="scripts/optremarks.py:286" sel="scripts/optremarks.py:main" lang="py" class="source" in="1"/>
<d n="main" t="fn" p="scripts/tidyadvisory_diff.py:313" sel="scripts/tidyadvisory_diff.py:main" lang="py" class="source" in="1"/>
<d n="main" t="fn" p="src/main.cpp:4509" sel="src/main.cpp:main" lang="cpp" class="source" in="0"/>
<d n="main" t="fn" p="src/tsprobe.cpp:70" sel="src/tsprobe.cpp:main" lang="cpp" class="source" in="0"/>
<d n="main" t="fn" p="bench/agentloop/analyze.py:345" sel="bench/agentloop/analyze.py:main" lang="py" class="test" in="1"/>
<d n="main" t="fn" p="bench/agentloop/backfill_claude_transcripts.py:104" sel="bench/agentloop/backfill_claude_transcripts.py:main" lang="py" class="test" in="1"/>
<d n="main" t="fn" p="bench/agentloop/editsuite/gen_expected.py:47" sel="bench/agentloop/editsuite/gen_expected.py:main" lang="py" class="test" in="1"/>
<d n="main" t="fn" p="bench/agentloop/followup_calls.py:160" sel="bench/agentloop/followup_calls.py:main" lang="py" class="test" in="1"/>
<d n="main" t="fn" p="bench/agentloop/grade_answers.py:609" sel="bench/agentloop/grade_answers.py:main" lang="py" class="test" in="1"/>
<d n="main" t="fn" p="bench/agentloop/power_sim.py:209" sel="bench/agentloop/power_sim.py:main" lang="py" class="test" in="1"/>
<d n="main" t="fn" p="bench/agentloop/run_agentloop.py:1237" sel="bench/agentloop/run_agentloop.py:main" lang="py" class="test" in="1"/>
<d n="main" t="fn" p="bench/agentloop/run_editsuite.py:530" sel="bench/agentloop/run_editsuite.py:main" lang="py" class="test" in="1"/>
</name>
<name q="rankGraphTeleport" defs="1">
<d n="rankGraphTeleport" t="fn" p="src/graph.h:14619" sel="rankGraphTeleport" lang="cpp" class="source" in="7"/>
</name>
</defs>
`````

## `./build/ripwire . --connect=rankGraphTeleport,runEval,getIndex`

*Minimal connecting subgraph over 3 symbols (finds shared-caller joins).*

`````
<!-- ripwire connect schema=ripwire.connect/v1: minimal joining subgraph: <g> groups, <t> terminals, <s connects=> joins, <e f= t=> edges, <unconnected>. counts_floor=1: every count is a FLOOR, never a total. graph_ambiguous=/graph_unresolved=: resolver gauge. graph_unindexed=N: N files no grammar could read (the map header's unindexed=); their calls raise neither gauge. est_tokens=: price as emitted (an upper bound under compact). root=: p= relative to it. hub_floor=D: connects= >= D is hub=1, vacuous. nodes=N: symbols printed, terminals plus joins (a floor). radius=N: undirected hop bound searched (default 6, max 12); raise it with connect-radius=N. e site=: a call of t= in f= (arity fit, then owner, first); by name, not proof. e call=: its text, <=3 lines/120 B, U+2026=cut. e sig=: t='s signature, <=160 B, once per callee. terminals=/groups=/edges=: task symbols resolved, connected groups (g), e edges printed. t n= / s n=: a terminal's / a join's symbol name. -->
<connect schema="ripwire.connect/v1" terminals="3" nodes="3" edges="2" radius="6" groups="1" est_tokens="754" hub_floor="299" root="." graph_ambiguous="3634" graph_unresolved="20069" graph_unindexed="313" counts_floor="1">
<g terminals="3">
<t n="runEval" t="fn" p="src/eval.h:171"/>
<t n="rankGraphTeleport" t="fn" p="src/graph.h:14619"/>
<t n="getIndex" t="fn" p="src/mcpindex.h:1224"/>
<e f="runEval" t="rankGraphTeleport" site="src/eval.h:328" call="const std::vector&lt;float&gt; r = rankGraphTeleport( g, diffTeleport( ing, seedMask ) ).rank;" sig="inline RankedGraph rankGraphTeleport( const Graph&amp; g, const std::vector&lt;float&gt;&amp; p, float alpha = 0.85f )"/>
<e f="getIndex" t="rankGraphTeleport" site="src/mcpindex.h:1340" call="const auto [ wsRank, wsIters, wsConverged ] = rankGraphTeleport( ix.g, diffTeleport( ix.ing, changed ) );"/>
</g>
</connect>
`````

## `./build/ripwire . --impact=rankGraphTeleport`

*Transitive blast radius — everything that reaches SYM. NOW carries shown/capped.*

`````
<!-- ripwire impact schema=ripwire.impact/v1: transitive blast radius of of=: <s t= n= p=> reach set, <f via= p=> importers; defs= matched, reaches= their transitive callers, radius_tested= non-tests an indexed test reaches, radius_untested= the rest; importers= files that #include/import a def's file. window: shown= total= capped= has_more= next_offset= offset= limit= (capped=1 cut; next_offset= pastes as offset=). importers_capped=/files_capped=: 1 = cut. counts_floor=1: every count is a FLOOR, never a total. graph_ambiguous=/graph_unresolved=: resolver gauge. graph_unindexed=N: N files no grammar could read (the map header's unindexed=); their calls raise neither gauge. root=: p= relative to it. pr_iters=N: PageRank iterations. shown_importers=: <f> rows (limit= sizes them). importers_next=: the call listing every importer. importers_tests=/importers_dirs=: over EVERY importer of a cut tier: test/bench/fixture files / the 3 dirs (2 path segments) holding most, dir:count. files files=/shown_files=: files the WHOLE reach set touches (rides beside a cut symbol window) / listed; rf syms= reached symbols there, d= fewest hops; files_capped=1 + files_next= when cut. <f lazy=1>: every edge from that importer into a def file is deferred (in a function/block body, or an autoload), firing only if reached; lazy=0: at least one is load-time. declined_calls=K: K call sites left unbound, in no count; <dc n= l=|in= p= cands=K via=declined>: one such call SITE (callees: called name, line; callers: calling def, file:line); NOT an edge or a caller/callee claim; cands=K: K in-tree defs it could have meant (K may be 1), the resolver proved none; not a claim this call reaches any of them. all_next=: the ONE call listing every row of total= (same rows, columnar); next_offset= pages. <s d=N>: hops to of= (1 = direct caller), set where it changes. by_depth=k:n: n of reaches= at depth k, shallowest rows first. next=: the one pasteable follow-up. -->
<impact schema="ripwire.impact/v1" of="rankGraphTeleport" defs="1" reaches="80" by_depth="1:7,2:52,3:13,4:6,5:1,6:1" importers="73" shown_importers="40" importers_capped="1" importers_next="--impact=rankGraphTeleport --limit=73" importers_tests="2" importers_dirs="src:71,test:2" radius_tested="0" ra … [line truncated: 338 more bytes on this line]
<files files="16" shown_files="16" files_capped="0">
<rf p="src/main.cpp" syms="12" d="1"/>
<rf p="src/eval.h" syms="4" d="1"/>
<rf p="src/graph.h" syms="2" d="1"/>
<rf p="src/mcpindex.h" syms="1" d="1"/>
<rf p="src/mcpverbs.h" syms="29" d="2"/>
<rf p="src/verbs_for.h" syms="7" d="2"/>
<rf p="src/verbs_report.h" syms="6" d="2"/>
<rf p="src/editplan.h" syms="4" d="2"/>
<rf p="src/mcpedit.h" syms="3" d="2"/>
<rf p="src/lsp.h" syms="2" d="2"/>
<rf p="src/mcp.h" syms="2" d="2"/>
<rf p="src/verbs_change.h" syms="2" d="2"/>
<rf p="src/verbs_navigate.h" syms="2" d="2"/>
<rf p="src/warmsnap_graph.h" syms="2" d="2"/>
<rf p="src/forpage.h" syms="1" d="2"/>
<rf p="src/mcpserver.h" syms="1" d="2"/>
</files>
<s t="fn" n="getIndex" p="src/mcpindex.h:1224" d="1"/>
<s t="fn" n="rankGraph" p="src/graph.h:14662"/>
<s t="fn" n="anchoredLexicalRank" p="src/graph.h:15331"/>
<s t="fn" n="churnDecayRanking" p="src/main.cpp:1432"/>
<s t="fn" n="runDefaultMap" p="src/main.cpp:1758"/>
<s t="fn" n="churnRankedGraph" p="src/main.cpp:1471"/>
<s t="fn" n="runEval" p="src/eval.h:171"/>
<s t="fn" n="emitCommunitiesReport" p="src/verbs_report.h:2732" d="2"/>
<s t="fn" n="emitCommunityDrill" p="src/verbs_report.h:2893"/>
<s t="fn" n="computeLensRanking" p="src/verbs_for.h:115"/>
… [73 more display lines; full output is 7439 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --mentions=rankGraphTeleport`

*Markdown docs that name SYM in a backtick (doc<->code edges).*

`````
<!-- ripwire mentions schema=ripwire.mentions/v1: markdown FILES naming of= in backticks (docs=, sections=): <doc p= mentions=>; not a call edge. root=: p= relative to it. defs=N: definitions of= resolved to; rows union their doc mentions. -->
<!-- unbackticked_docs=N: N more markdown files, over readable indexed markdown, name of= as a whole word but not as a clean one-line backtick span (prose, a code block, a span broken across lines) - not in docs=; a text match, so a ceiling -->
<mentions schema="ripwire.mentions/v1" of="rankGraphTeleport" defs="1" docs="6" sections="14" unbackticked_docs="5" root=".">
<doc p="docs/ARCHITECTURE.md" mentions="1"/>
<doc p="docs/EVALS.md" mentions="4"/>
<doc p="prompts/help-wanted/certified-ranking-order.md" mentions="2"/>
<doc p="prompts/help-wanted/correctness-fuzzers.md" mentions="1"/>
<doc p="prompts/help-wanted/graph-unit-tests.md" mentions="5"/>
<doc p="prompts/help-wanted/next-uses-bare-name.md" mentions="1"/>
</mentions>
`````

## `./build/ripwire . --affected=src/graph.h`

*Test files that transitively reach the changed file.*

**wall time: 1.72s**

`````
<!-- ripwire affected schema=ripwire.affected/v1: test files that transitively reach the changed files/symbols: <test p= partner= hops= run=> in evidence order (order= partners=); seeded_by= the reading taken. counts_floor=1: every count is a FLOOR, never a total. graph_ambiguous=/graph_unresolved=: resolver gauge. graph_unindexed=N: N files no grammar could read (the map header's unindexed=); their calls raise neither gauge. run_unknown=1: no runner derivable (a guess would be worse). root=: p= relative to it. seeds=N: symbols the argument matched; only those outside test files seed the caller walk. seed_test_files=N: matched files that are TESTS; listed to run (seed_kind=test), never walk seeds. tests=N: test files listed to run (the rows). reached=N: symbols the transitive caller walk reached from the seeds (seeds excluded). script_gates_unmodelled=N: test/*.sh runners; their subprocess reach is unmodelled, never in tests=/reached=. run_first=N: the first N test files have the most direct evidence (changed/partner/hops=1, else nearest hops=); not a skip list. changed=: the files/symbols argument as given. -->
<affected schema="ripwire.affected/v1" changed="src/graph.h" seeded_by="file" seeds="828" seed_test_files="0" tests="11" reached="1024" script_gates_unmodelled="946" run_first="3" order="evidence" partners="0" root="." graph_ambiguous="3634" graph_unresolved="20069" graph_unindexed="313" counts_floo … [line truncated: 6 more bytes on this line]
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
<test p="test/shstatus_harness.cpp" hops="7" run="bash test/gateexitcheck.sh"/>
</affected>
`````

## `./build/ripwire . --situ`

*Mid-task situational report for the current git diff — recorded against a CLEAN tree (contrast with the sandbox run below).*

`````
ripwire situational-awareness — 0 changed file(s), 0 symbols in them
root: .
at: 6ace381eb
  (0 changed files — working tree is clean, nothing to analyze)
`````

## `./build/ripwire . --test-gate`

*Pre-PR gate on a CLEAN tree: no obligations, exit 0.*

**wall time: 4.57s**

`````
<!-- ripwire test-gate schema=ripwire.test-gate/v1: tests <t p= changed= partner= hops= run=> + untested blast radius <u sym= p= l= ccx=>; exit 4 while either exists. tests_capped=/untested_capped=: 1 = cut. counts_floor=1: every count is a FLOOR, never a total. graph_ambiguous=/graph_unresolved=: resolver gauge. graph_unindexed=N: N files no grammar could read (the map header's unindexed=); their calls raise neither gauge. at=: commit+dirty+shallow. next=: the one pasteable follow-up. impacted=N: symbols that transitively call the change (changed symbols excluded). shown_tests=/shown_untested=: t rows and u rows printed, two independent counts. script_gates_unmodelled=N: test/*.sh runners in the corpus, a path count; not call-graph modelled. script_gates_registered=N: shell gates test/regression.sh registers as suite members. script_gates_mapped=N: registered gates with exact dependency evidence (literal paths or RIPWIRE_TEST_DEPS). script_gates_unresolved_dynamic=N: registered gates with no mappable deps; they may cover the change unlisted. ccx_bar=N: the cognitive-complexity bar a u row's ccx= is read against. untested_modscope=N: <file-scope> owners excluded from untested= (#324, uncallable); still in impacted=. tests=/untested=: tests to run (t total) / impacted symbols no test reaches (u total). -->
<test-gate schema="ripwire.test-gate/v1" changed="0" impacted="0" tests="0" untested="0" untested_modscope="0" shown_tests="0" tests_capped="0" shown_untested="0" untested_capped="0" script_gates_unmodelled="946" script_gates_registered="881" script_gates_mapped="290" script_gates_unresolved_dynamic … [line truncated: 136 more bytes on this line]
</test-gate>
`````

## `./build/ripwire . --grep=DISCLOSE`

*Literal trigram-indexed search. Each hit carries its MATCHED line as the <hit> element's own CDATA (the <m> wrapper is gone), plus shown/capped/hits_capped and a pasteable next= on the root.*

`````
<!-- ripwire grep schema=ripwire.grep/v1: literal/regex scan grouped by file: <f p=>
<hit l= in=>CDATA text</hit> (<b>/<a> context around it); complete=1 only for an exhaustive literal scan (beside pattern_meta=, of the literal reading only); <unindexed> = off-index. window: shown= total= capped= has_more= next_offset= offset= limit= (capped=1 cut; next_offset= pastes as offset=). c … [line truncated: 2304 more bytes on this line]
<grep pattern="DISCLOSE" schema="ripwire.grep/v1" root="." files="291" hits="991" shown="100" capped="1" total="991" has_more="1" next_offset="100" offset="0" limit="0" hits_capped="0" suppressed_comment="159" suppressed_string="4" tier_parsed="77" tier_unclassified="770" tier_budget="bytes" tier_fi … [line truncated: 202 more bytes on this line]
<f p=".coderabbit.yaml">
<hit l="33" in="path_instructions" occ="2">
<![CDATA[        A degrade path uses DISCLOSE( sink, why ), never ASSUME(false): a one-argument DISCLOSE( msg ) is a debug trace]]>
</hit>
</f>
<f p="src/abicheck.h" parse_degraded="1">
<hit l="517" in="abicheck::collectAuthoredSites">
<![CDATA[            DISCLOSE( result, AbiResult::DisclosureWhy::NoMergeBase, "abi: no merge-base for a ref (unrelated history?) — that ref is counted, not compared" );]]>
</hit>
</f>
<f p="src/arch.h">
<hit l="512" in="rw::parseArchRules">
<![CDATA[        DISCLOSE( Diagnostics::answerRefused, "--arch exits 1 with path:line and the reason on stderr; no report is printed",]]>
</hit>
<hit l="846" in="rw::readArchBaselineSidecar">
<![CDATA[    if( sidecar.refused ) { DISCLOSE( baseline, ArchBaselineRead::DisclosureWhy::SymlinkRefused, "arch: refusing to read the arch baseline sidecar through a symlink" ); }]]>
</hit>
<hit l="897" in="rw::openArchBaselineSidecar">
<![CDATA[        DISCLOSE( Diagnostics::answerRefused, "--baseline exits 1: pathguard names the refused link on stderr and the verb says it cannot write the sidecar",]]>
</hit>
</f>
<f p="src/atoms.h">
<hit l="372" in="atomdetail::collectExclusions">
<![CDATA[        DISCLOSE( ex, Exclusions::DisclosureWhy::ForHeaderSaturated, "atoms: the for-header exclusion stream spent its whole budget; the rules reading it are suppressed this run" );]]>
</hit>
<hit l="376" in="atomdetail::collectExclusions">
<![CDATA[        DISCLOSE( ex, Exclusions::DisclosureWhy::StmtCrementSaturated, "atoms: the statement-crement exclusion stream spent its whole budget; the rules reading it are suppressed this run" );]]>
… [463 more display lines; full output is 30177 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --grep=DISCLOSE --grep-context=1`

*Same search with one line of source context either side.*

`````
<!-- ripwire grep schema=ripwire.grep/v1: literal/regex scan grouped by file: <f p=>
<hit l= in=>CDATA text</hit> (<b>/<a> context around it); complete=1 only for an exhaustive literal scan (beside pattern_meta=, of the literal reading only); <unindexed> = off-index. window: shown= total= capped= has_more= next_offset= offset= limit= (capped=1 cut; next_offset= pastes as offset=). c … [line truncated: 2197 more bytes on this line]
<grep pattern="DISCLOSE" schema="ripwire.grep/v1" root="." files="291" hits="991" shown="100" capped="1" total="991" has_more="1" next_offset="100" offset="0" limit="0" hits_capped="0" suppressed_comment="159" suppressed_string="4" tier_parsed="77" tier_unclassified="770" tier_budget="bytes" tier_fi … [line truncated: 202 more bytes on this line]
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
<hit l="517" in="abicheck::collectAuthoredSites">
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
<hit l="512" in="rw::parseArchRules">
<b>
<![CDATA[        rw::emitTo( stderr, "ripwire: --arch: {}:{}: {} — rules file rejected\n", path.c_str(), lineNo, why );]]>
</b>
… [1061 more display lines; full output is 42138 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --grep=DISCLOSE --grep-before=1 --grep-after=2 --limit=3`

*The asymmetric spelling of the same context: one line before and two after each hit (ripgrep's -B/-A), on a three-hit window.*

`````
<!-- ripwire grep schema=ripwire.grep/v1: literal/regex scan grouped by file: <f p=>
<hit l= in=>CDATA text</hit> (<b>/<a> context around it); complete=1 only for an exhaustive literal scan (beside pattern_meta=, of the literal reading only); <unindexed> = off-index. window: shown= total= capped= has_more= next_offset= offset= limit= (capped=1 cut; next_offset= pastes as offset=). c … [line truncated: 1779 more bytes on this line]
<grep pattern="DISCLOSE" schema="ripwire.grep/v1" root="." files="291" hits="991" shown="3" capped="1" total="991" has_more="1" next_offset="3" offset="0" limit="3" hits_capped="0" suppressed_comment="159" suppressed_string="4" tier_parsed="77" tier_unclassified="770" tier_budget="bytes" tier_files= … [line truncated: 196 more bytes on this line]
<f p=".coderabbit.yaml">
<hit l="33" in="path_instructions" occ="2">
<b>
<![CDATA[        External input (files, git, env, argv, MCP/JSON, data read back from a cache) is checked with VALIDATE.]]>
</b>
<![CDATA[        A degrade path uses DISCLOSE( sink, why ), never ASSUME(false): a one-argument DISCLOSE( msg ) is a debug trace]]>
<a>
<![CDATA[        that ships nothing, and a Diagnostics::answerUnchanged reason must be true. A count that cannot be a total must be
        labelled a floor; a zero means none found. Flag silent zeros, undisclosed truncation, and gate arms]]></a></hit></f><f p="src/abicheck.h" parse_degraded="1"><hit l="517" in="abicheck::collectAuthoredSites"><b><![CDATA[        {]]></b><![CDATA[            DISCLOSE( result, AbiResult::Disclosu … [line truncated: 148 more bytes on this line]
        }]]></a></hit></f><f p="src/arch.h"><hit l="512" in="rw::parseArchRules"><b><![CDATA[        rw::emitTo( stderr, "ripwire: --arch: {}:{}: {} — rules file rejected\n", path.c_str(), lineNo, why );]]></b><![CDATA[        DISCLOSE( Diagnostics::answerRefused, "--arch exits 1 with path:line an … [line truncated: 134 more bytes on this line]
        return false;]]></a></hit></f><unindexed count="15" shown="3" capped="1"><f p="CMakeLists.txt"><hit l="122"><![CDATA[# ASSUME and the DISCLOSE( msg ) trace live, which is the only configuration that can catch an]]></hit><hit l="347"><![CDATA[# -DCMAKE_BUILD_TYPE=Release" locally — Release  … [line truncated: 382 more bytes on this line]
`````

## `./build/ripwire . --regex='fnv1a\w+'`

*Regex search + enclosing symbol.*

`````
<!-- ripwire grep schema=ripwire.grep/v1: literal/regex scan grouped by file: <f p=>
<hit l= in=>CDATA text</hit> (<b>/<a> context around it); complete=1 only for an exhaustive literal scan (beside pattern_meta=, of the literal reading only); <unindexed> = off-index. window: shown= total= capped= has_more= next_offset= offset= limit= (capped=1 cut; next_offset= pastes as offset=). h … [line truncated: 2049 more bytes on this line]
<grep pattern="fnv1a\w+" schema="ripwire.grep/v1" root="." files="29" hits="102" shown="100" capped="1" total="102" has_more="1" next_offset="100" offset="0" limit="0" hits_capped="0" suppressed_comment="68" suppressed_string="27" tier_parsed="47" tier_unclassified="0" corpus_oversize="15" corpus_pr … [line truncated: 172 more bytes on this line]
<f p="src/arch.h">
<hit l="683" in="rw::fnv1a64">
<![CDATA[inline std::uint64_t fnv1a64( std::string_view s ) noexcept]]>
</hit>
<hit l="685" in="rw::fnv1a64">
<![CDATA[    return hashutil::fnv1a64( s );]]>
</hit>
<hit l="788" in="rw::archViolHash">
<![CDATA[            h = hashutil::fnv1aAbsorb( h, c );]]>
</hit>
<hit l="791" in="rw::archViolHash">
<![CDATA[        h = hashutil::fnv1aMultiply( h ); // NUL separator byte]]>
</hit>
</f>
<f p="src/cloneidiom.h">
<hit l="919" in="rw::idiomParamTypeKey">
<![CDATA[    return spelled.empty() ? 0 : fnv1a64( spelled );]]>
</hit>
<hit l="1109" in="rw::oneStatementFacts">
<![CDATA[        f.ids.push_back( fnv1a64( w ) );]]>
</hit>
<hit l="1112" in="rw::oneStatementFacts">
<![CDATA[    f.alpha = fnv1a64( renamed );]]>
</hit>
<hit l="1182" in="rw::idiomTokenHashSet">
<![CDATA[            out.push_back( fnv1a64( t.text ) );]]>
</hit>
… [477 more display lines; full output is 23687 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --match='(if_statement)'`

*Tree-sitter structural query WITHOUT a capture — a bare node query gets a capture AUTO-ADDED (auto_captured="1") and matches the same nodes the explicit form does.*

**wall time: 1.18s**

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
… [73 more display lines; full output is 17045 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --match='(if_statement) @i'`

*The same shape query WITH an explicit capture — identical hits, no auto_captured= attribute.*

**wall time: 1.14s**

`````
<!-- ripwire match schema=ripwire.match/v1: tree-sitter structural query: <m p= in=> captured nodes with their enclosing symbol; grammars=/eligible_files= the scope. window: shown= total= capped= has_more= next_offset= offset= limit= (capped=1 cut; next_offset= pastes as offset=). counts_floor=1: every count is a FLOOR, never a total. hits_capped=1: hits= is a floor. root=: p= relative to it. of_files=: indexed files in all (eligible_files= of them are in the query's languages). -->
<match schema="ripwire.match/v1" hits="5000" shown="100" capped="1" total="5000" has_more="1" next_offset="100" offset="0" limit="0" counts_floor="1" hits_capped="1" grammars="cpp,c,python,go,typescript,tsx,swift,objc,javascript,bash,java,csharp,php,dart,lua,gdscript" eligible_files="3625" of_files= … [line truncated: 16 more bytes on this line]
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
… [73 more display lines; full output is 16929 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --query="teleport pagerank" --top-k=5`

*Raw BM25 ranking (debug lens; --for is the real verb).*

`````
<!-- routed: subtoken+body:broad -->
<!-- ripwire query schema=ripwire.query/v1: lexical-rank map for the query term, the map's row vocabulary. est_tokens=: price as emitted (an upper bound under compact). root=: p= relative to it. declined=K: K call sites without edges, including inert Elixir quote sites after unquote/unquote_splicing re-entry. external=K: K calls proven outside the tree, no edge. locality_pinned=K: K calls pinned by locality alone (a guess). extent_suspect_syms=K: K defs failed containment, corpus-wide. macro_blanked_files=K: K files indexed from a macro-blanked re-parse. prov=scip|binding|import|split|final-segment: how that <c> edge bound (absent: one unique name); split = one arm of an amb= pick; final-segment = a qualified type matched by last name only. files=/symbols=: files and symbols indexed; edges= distinct call edges; shown= symbols printed, a merged row counting each def; ambiguous= calls split over several defs, corpus-wide; unresolved= calls with in-tree evidence and no edge (every def language-filtered or unreachable, or binding refused); order= rows by rank (important-first, important-last; (auto:fill) = flipped past a size threshold) or by path (stable). skipped_oversize=K: K files over a size ceiling, not indexed. unindexed=ext:N: N text files of that extension no grammar reads (6 extensions at most). unindexed_exts=E: E such extensions in all, the list cut. sc=: enclosing scope; the full id is p::sc::n (p= of the row or its <f>) and selectors take it. amb=K: K calls split over several defs. f p=: a file; s t= n=: kind, name; c n=: a resolved callee. s k=: rank. -->
<!-- t=modscope=a-file's-MODULE-SCOPE(n=<file-scope>):the-statements-outside-every-named-definition,where-a-top-level-call-and-an-anonymous-callback-body's-calls-live;a-CALLER-never-a-callee(nothing-in-the-source-can-name-it)-with-no-body-to-expand;a-file-with-no-such-call-has-no-such-row -->
<!-- t=type|alias|functype=a-Go-named-type-by-its-written-form:type=a-defined-type-whose-WRITTEN-form-is-not-a-struct/iface/func-literal(type-N-string;type-W-Pair-too,whatever-Pair-is-underneath),alias=type-A=B,functype=type-F-func(...) -->
<!-- t=alias|functype-in-C++-and-.h:alias=using-X=Y(also-templated-or-class-scope)or-namespace-L=lib(defs=X-prints-its-written-target-as-to=),functype=a-typedef-of-a-function-or-function-pointer-type(typedef-void(*F)(int));other-typedefs-read-t=struct -->
<!-- files=4838 symbols=44600 edges=44429 shown=5 est_tokens=1513 ambiguous=3634 unresolved=20069 locality_pinned=14 external=12457 declined=45295 extent_suspect_syms=12 macro_blanked_files=7 skipped_oversize=15 unindexed="txt:85,tsv:54,mod:33,xml:33,jsonl:26,scm:25" unindexed_exts=23 order=important-first -->
<r schema="ripwire.query/v1" root="." est_tokens="1513">
<f p="src/serialize.h">
<s t="var" n="kChurnRankLegend" sc="rw" k="19.7814">
</s>
</f>
<f p="src/mcpverbs.h">
<s t="fn" n="rankByText" sc="rw" k="15.5236">
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
<s t="fn" n="churnPriorFromFreq" sc="rw" k="13.5831">
<c n="DISCLOSE"/>
</s>
</f>
<f p="src/pagerank.cpp">
<s t="fn" n="pageRankDouble" sc="rw" amb="3" k="13.4155">
<c n="ASSUME"/>
… [23 more display lines; full output is 3783 bytes on 1 raw line(s)]
`````


---

# zoom the detail ladder

## `./build/ripwire . --for="pagerank power iteration" --detail=2`

*Importance-weighted detail: FULL bodies for top-2, signatures for the rest.*

`````
<ctx task="pagerank power iteration" route="subtoken+body" root="." confidence="high" margin_pct="22" at="6ace381eb" doc_mentions="4" schema="ripwire.for/v1" budget_bytes="7500" doc_mentions_capped="1" doc_mentions_total="14" est_tokens="7383">
<!-- ripwire for schema=ripwire.for/v1: bundle=/bodies=/reason= the body posture; d: cx= ccx= complexity, in= callers (absent cx/ccx/in = 0), churn= amp= change, clone= tested= 1, sc= scope, id=p::sc::n; total= shown= capped=1 if cut; task= the query; d pure=1 const/constexpr sig, next= the follow-up to paste; d same_as=N: doc+sig text as row n=N (not repeated); route= name-exact(X)|subtoken+body[:broad|:declined]; confidence=/margin_pct= head score drop (low=flat); t p= file outside sigs (weaker), t sym= its top symbols not in sigs/syms (a pointer, not the answer), r= rank (gap = trimmed); t tsym= up to 2 more file symbols named by a task word (a name match); t order: code files first, then doc files (a code question); t page rows go on to file-page row 160 (code question: 160 code rows, docs within row 160); past page 0 (code question: past 40 code rows, a doc past row 40) listed last, head files skipped; past 120 of those p= only, p_only= counts them; t folded=class=N: N p= only rows of that class (doc|config|script|testdata|other) not listed, next= pages to them; d layer=: built-in arch layer (game|infra|render|math|audio|ai|test) from a dir name in p=; d e= its last line (absent=unknown, never 0; l= the name's line) [doc mentions: 4 docs, 2 symbols; doc_mentions=] -->
<!-- root= is the crawl root; p= below is RELATIVE to it (single-root only; absent => p= is ingest's own path, unchanged); at=this commit(+dirty). [budget_bytes= is the default BYTE target this ranked payload was shaped toward: row text shortens toward it, no row of the ranked head is removed for it (sigs past_target=)] [sigs capped=1 with shown=total: rows shrunk, none dropped] [sigs past_target=K: the last K rows are past the budget_bytes target, served because they are rows of the ranked head; none is cut] [sigs next=: one call serving all total= rows uncut] [docs_dropped=N: N shown rows have a doc comment not printed (r>24 always, r5..24 if capped)] [docs_after_code=N: N doc rows of the shown set moved below its code rows; same rows, reordered, none added or removed; a question naming docs keeps score order] [files_first=N: N rows moved so r=1..8 are distinct files' best rows, score order, a repeated name once; same rows; fold, hops keep score order] [cut: doc_mentions_capped="1" doc_mentions_total="14" — an indexing cap dropped content not shown here]; lego/compose collapse to a counted stub by default (a disclosed cut): total= that section's own pre-cap row count, shown="0" capped="1" (nothing rendered here), next= names the sections=lego,compose flag that restores both sections byte-identically in one call est_tokens= prices this bundle in tokens -->
<sigs shown="40" total="40" capped="1" past_target="14" docs_dropped="25" docs_after_code="5" files_first="7" next="--for='pagerank power iteration' --signatures-only --token-budget=6200">
<d l="422" e="422" n="kScoreTieAbsEps" sc="rw" p="src/eval.h" churn="18" amp="51" pure="1" r="1" next="--expand=src/eval.h:kScoreTieAbsEps">
<doc>NodeId order. Renumbering an otherwise-identical graph (the exact &quot;same probe file, different so…</doc>inline constexpr float kScoreTieAbsEps = 1e-6f</d>
<d l="51" e="56" n="RankDisclosure" sc="RankDisclosure" p="src/prconverge.h" churn="3" amp="27" r="2">
<doc>What a ranked document discloses about the power iteration that ordered it. `isPageRank == false…</doc>struct RankDisclosure</d>
<d l="99" e="206" n="pageRankDouble" sc="rw" p="src/pagerank.cpp" cx="19" ccx="34" in="2" churn="14" amp="44" tested="1" r="3">
<doc>The PageRank power iteration itself — the numeric kernel every ranked document&apos;s order comes f…</doc>PageRankRun pageRankDouble( const sparseCsr&lt;float&gt;&amp; inEdges, std::span&lt;const double&gt; weightedOutDegree, std::span&lt;const double&gt; teleport, std::span&lt;double&gt; r … [line truncated: 10 more bytes on this line]
<d l="503" e="549" n="rankByText" sc="rw" p="src/mcpverbs.h" cx="11" ccx="19" in="1" churn="675" amp="692" r="4">inline std::string rankByText( const std::string&amp; root, std::string_view mode, int topK, bool stable = false )</d>
<d l="14610" e="14615" n="RankedGraph" sc="RankedGraph" p="src/graph.h" churn="713" amp="977" r="5">struct RankedGraph</d>
<d l="2568" e="2572" n="kChurnRankLegend" sc="rw" p="src/serialize.h" churn="515" amp="626" pure="1" r="6">inline constexpr const char* kChurnRankLegend = &quot;&lt;!-- rank_by=churn: k= is PageRank re-run with the teleport BIASED by git CHANGE-FREQUENCY over window= &quot; &quot;(a c…</d>
<d l="1372" e="1393" n="sliceRdIterationCeiling" sc="slicev" p="src/slice.h" cx="9" ccx="12" in="1" churn="54" amp="103" r="7">inline std::uint32_t sliceRdIterationCeiling() noexcept</d>
<d l="31" e="44" n="PageRankRun" sc="PageRankRun" p="src/pagerank.h" churn="8" amp="37" r="8">struct PageRankRun</d>
<d l="73" e="144" n="renderDisclosure" sc="rw" p="src/prconverge.h" cx="12" ccx="15" in="14" churn="3" amp="41" r="9">
<doc>Render one form of the disclosure. Empty string whenever there is nothing to say — no power it…</doc>inline std::string renderDisclosure( const RankDisclosure&amp; d, DiscloseAs as )</d>
<d l="17898" e="17907" n="navRelevanceWeight" sc="rw" p="src/graph.h" cx="2" ccx="1" in="2" churn="713" amp="979" r="10">inline std::uint32_t navRelevanceWeight( const Graph&amp; g, NodeId n ) noexcept</d>
<d l="14619" e="14647" n="rankGraphTeleport" sc="rw" p="src/graph.h" cx="5" ccx="8" in="7" churn="713" amp="984" r="11">inline RankedGraph rankGraphTeleport( const Graph&amp; g, const std::vector&lt;float&gt;&amp; p, float alpha = 0.85f )</d>
<d l="1247" e="1247" n="kPowerShellPathPrependScope" sc="rw::oswin" p="src/infra/os_win32_logic.h" layer="infra" churn="20" amp="50" pure="1" r="12">inline constexpr std::string_view kPowerShellPathPrependScope = &quot;in PowerShell, for this window</d>
<!-- demote: a <t> in sigs is a lower same-file sibling past answer row 10, a pointer (p= file, sym= name, r= rank), not the answer -->
<t p="src/infra/os_win32_logic.h" sym="powerShellPathPrependHint" r="13"/>
<d l="1255" e="1255" n="path_prepend_hint" sc="rw::os" p="src/infra/os.h" layer="infra" cx="1" in="1" churn="43" amp="94" r="14">inline std::string path_prepend_hint( std::string_view dir )</d>
<t p="src/infra/os_win32_logic.h" sym="powerShellSingleQuote" r="15"/>
<d l="2198" e="2206" n="dynamic_map::leftmost_leaf" p="src/infra/dynamic_map.hpp" layer="infra" cx="2" ccx="1" in="7" churn="7" amp="38" pure="1" r="16">handle_t leftmost_leaf() const</d>
<d l="58" e="91" n="HOT_FILES" p="scripts/optremarks.py" churn="19" amp="84" r="17">HOT_FILES = ( &quot;src/pagerank.cpp&quot;, # the power-iteration loop — G2&apos;s no-allocation scope &quot;src/infra/radixSort.h&quot;, # LSD radix entry points &quot;src/infra/radixSort.inl&quot;, # the counting … [line truncated: 76 more bytes on this line]
<d l="294" e="299" n="doctorPathPrependLine" p="src/verbs_doctor.h" cx="2" ccx="1" in="2" churn="51" amp="151" r="18">inline std::string doctorPathPrependLine( const std::string&amp; selfPath )</d>
<t p="src/infra/dynamic_map.hpp" sym="reverse_iterator" r="19"/>
<t p="src/verbs_doctor.h" sym="doctorWhichRipwire" r="20"/>
<t p="src/serialize.h" sym="rankByLegendFor" r="21"/>
… [130 more display lines; full output is 19059 bytes on 6 raw line(s)]
`````

## `./build/ripwire . --pack-signatures --top-k=10`

*Body-elided decl skeletons — recounted on this corpus. Measured as element bytes: the <d> signature+doc elements --pack-signatures emits, against the SAME symbols' full <b> bodies from --expand, with the CORPUS-ROOT PREFIX SUBTRACTED FROM BOTH SIDES. That subtraction is the whole methodology and the figure is meaningless without it: the root repeats inside every element's id= and p=, it is not what this verb elides, and counting it makes the headline a function of how deep the checkout happens to sit on disk — on one corpus, three spellings of the same root read 18.6 points apart before the subtraction and agree exactly after it. Root-neutralised on THIS repo: 89.7% fewer bytes at top-10, 88.0% at top-50, 87.8% at top-100 (re-derived 2026-10-10 when the C++ standard-member gate stopped std::vector/std::string calls such as out.push_back() and s.empty() from binding to in-tree namesakes by name: the ranked top-10/50 lost one-line container accessors (svector::push_back, WidePath::c_str, every empty) and gained one-line forwarding helpers and macros (kindIs, ASSUME, formatTo, emitTo) whose signature is nearly the whole body, so less of the set is elidable, from 92.7/88.7/87.6; before that, re-derived 2026-09-20 when the native Windows port landed: src/infra/os_win32.cpp and os_win32_logic.h are ~3,900 lines of new, heavily commented infra that the ranked top-10/50/100 now reach, and their bodies are this ratio's DENOMINATOR, so the figure rises without --pack-signatures eliding anything new, from top-50 87.1. Measured by test/showcasecapturecheck.sh's own recount arm on the combined tree, which is the gate that would otherwise report the drift; before that, re-derived 2026-09-17 at the self-check macro vocabulary rename: VERIFY/VERIFY_TEXT/VERIFY_DEBUG_ONLY/VERIFY_NOT_REACHED/VERIFY_SAME_THREAD/VERIFY_NO_ALIAS*/DYNMAP_VERIFY/DEGRADED_PATH_ALERT renamed to ASSUME/EXPECTS/ENSURES/DASSERT/UNREACHABLE/ASSUME_SAME_THREAD*/ASSUME_NO_ALIAS*/DYNMAP_ASSUME/DISCLOSE (plus new VALIDATE sites) across 839 identifier renames in 179 files, and a hand-written Diagnostics.h/diagnostics.cpp replacing the old ones outright: this moves both WHICH symbols the ranked top-10/50/100 hold and how large their bodies are, from top-50 85.2. A real re-derivation of a corpus that changed, not a tolerance edit; previously re-derived 2026-09-12 when the <d> rows dropped the path-repeating id= for the short sc= scope: the signature side shrank, the bodies did not; before that, 89.5% / 81.8% / 84.3% re-derived 2026-09-10 at the sibs= cap raise: kMaxExpandSibs went 8 -> 100, so --expand's <b> bodies now carry the file context the old cap hid — 89.3% of all sibling names — and the body side is this ratio's DENOMINATOR, so the figure rises without --pack-signatures eliding anything new. Measured on a fixed tree with the top-50 membership and the signature side unchanged: top-50 from 71.0. A real re-derivation of a corpus that changed, not a tolerance edit; previously re-derived 2026-09-09 at the printf-family -> std::print conversion: converting ~1,500 emitter call sites to rw::emitTo/emitRaw/formatTo across 93 files changes how large the ranked symbols' BODIES are, and the body side is this ratio's denominator — top-50 from 72.3. A real re-derivation of a corpus that changed, not a tolerance edit; previously re-derived 2026-09-08 at the confident-zero round, issues #62/#63/#66: that change adds symbols to src/graphlegend.h and the new src/preprocdead.h and re-homes two long comment blocks from call sites onto the helpers they explain, which moves both WHICH symbols the ranked top-50 holds and how large their bodies are — top-50 from 74.0. A real re-derivation of a corpus that changed, not a tolerance edit; previously re-derived 2026-09-06 at the stranger-audit fix round: the doctor, cache-sweep and html-provenance bodies grew this corpus's BODY side, moving top-50 from 75.6 — a real re-derivation, not a tolerance edit; before that, re-derived 2026-09-05 at the capture-audit close: lane L7's P16 caps --expand's sibs= at 8 names, which SHRINKS the body side of this ratio and moved the figure down from 84.5/80.2/80.6 — the V1 2026-08-15 re-center, when sibs=/inc= first grew the body side from 70.0/61.0/63.8, in reverse; both were real re-derivations, not tolerance edits). top-50 is the number to quote, because the sigs payload is top-50 regardless of --top-k and is therefore what THIS command emits. A single small/trivial body can still invert it (signature+doc bigger than the body), like the --format=columnar sibling below. test/showcasecapturecheck.sh (C) re-derives all three from this repo every run, in the same quantity, and fails if the caption and the recount drift apart.*

`````
<ctx schema="ripwire.pack-signatures/v1">
<!-- ripwire pack-signatures schema=ripwire.pack-signatures/v1: the ranked map plus <sigs>
<d l= n= sc= pure=> signature rows. est_tokens=: price as emitted (an upper bound under compact). root=: p= relative to it. pr_iters=N: PageRank iterations. declined=K: K call sites without edges, including inert Elixir quote sites after unquote/unquote_splicing re-entry. external=K: K calls proven  … [line truncated: 1537 more bytes on this line]
<!-- t=modscope=a-file's-MODULE-SCOPE(n=<file-scope>):the-statements-outside-every-named-definition,where-a-top-level-call-and-an-anonymous-callback-body's-calls-live;a-CALLER-never-a-callee(nothing-in-the-source-can-name-it)-with-no-body-to-expand;a-file-with-no-such-call-has-no-such-row -->
<!-- t=type|alias|functype=a-Go-named-type-by-its-written-form:type=a-defined-type-whose-WRITTEN-form-is-not-a-struct/iface/func-literal(type-N-string;type-W-Pair-too,whatever-Pair-is-underneath),alias=type-A=B,functype=type-F-func(...) -->
<!-- t=alias|functype-in-C++-and-.h:alias=using-X=Y(also-templated-or-class-scope)or-namespace-L=lib(defs=X-prints-its-written-target-as-to=),functype=a-typedef-of-a-function-or-function-pointer-type(typedef-void(*F)(int));other-typedefs-read-t=struct -->
<!-- files=4838 symbols=44600 edges=44429 shown=10 est_tokens=5979 ambiguous=3634 unresolved=20069 locality_pinned=14 external=12457 declined=45295 extent_suspect_syms=12 macro_blanked_files=7 skipped_oversize=15 unindexed="txt:85,tsv:54,mod:33,xml:33,jsonl:26,scm:25" unindexed_exts=23 order=important-first -->
<r root="." est_tokens="6774" pr_iters="40">
<f p="src/infra/nodekind.h" layer="infra">
<s t="fn" n="kindIs" sc="rw" k="0.0031">
</s>
</f>
<f p="src/ingest_metrics.h">
<s t="fn" n="nodeTextOf" k="0.0021">
</s>
</f>
<f p="src/infra/namesplit.h" layer="infra">
<s t="fn" n="isIdentChar" sc="namesplit" k="0.0020">
</s>
</f>
<f p="src/model.h">
<s t="fn" n="relForHash" sc="rw" k="0.0019">
</s>
<s t="fn" n="rootRelPath" sc="rw" k="0.0018">
<c n="relForHash"/>
</s>
</f>
<f p="src/infra/Diagnostics.h" layer="infra">
<s t="macro" n="RW_ASSUME_" overloads="2" k="0.0018">
<c n="RW_CHECK_"/>
… [143 more display lines; full output is 14928 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --outline=rankGraphTeleport --top-k=0`

*Control-flow skeleton of one symbol, payload-only via the new --top-k=0.*

`````
<!-- ripwire pack-signatures schema=ripwire.pack-signatures/v1: the ranked map plus <sigs>
<d l= n= sc= pure=> signature rows. est_tokens=: price as emitted (an upper bound under compact). root=: p= relative to it. -->
<ctx schema="ripwire.pack-signatures/v1" root="." est_tokens="327">
<outline>
<o t="fn" l="14619" p="src/graph.h" n="rankGraphTeleport">
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
<o t="fn" l="14619" p="src/graph.h" n="rankGraphTeleport">
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
<ctx schema="ripwire.expand/v1" root="." est_tokens="1227">
<!-- ripwire expand schema=ripwire.expand/v1: full bodies: <bodies shown= total= capped=> of <b t= l= p= n= sibs= sibs_total= sibs_capped= inc=>; <calls>
<c n= l= p=> resolved callees (p= when not the b's file). window: shown= total= capped= (capped=1 cut). sibs_capped=/inc_capped=: 1 = cut. est_tokens=: price as emitted (an upper bound under compact). root=: p= relative to it. inc_total=N: the file's true include/import count; inc= lists the first 2 … [line truncated: 303 more bytes on this line]
<bodies shown="1" total="1" capped="0">
<b t="fn" l="14619" p="src/graph.h" n="rankGraphTeleport" sibs="&lt;file-scope&gt;,DeclinedSiteKind,kNoDeclinedList,ProvenSite,operator&lt;=&gt;,provenSiteCountsFor,Graph,localityKeyAt,ImplementorRow,implementorClosure,LegoClosure,LegoClosureWalk,LegoClosureWalk,take,boundOf,add,expand,legoImplement … [line truncated: 1657 more bytes on this line]
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
}]]><calls total="4"><c n="biasPrior" l="14578">inline std::vector&lt;float&gt; biasPrior( const Graph&amp; g, const std::vector&lt;float&gt;&amp; p )</c><c n="PROFILE_SCOPE_DESCRIBE" l="1282" p="src/infra/profileScope.h">#define PROFILE_SCOPE_DESCRIBE( desc )</c><c n="PROFILE_SCOPE_DESCRIBE" l="129 … [line truncated: 368 more bytes on this line]
`````

## `./build/ripwire . --expand=rankGraphTeleport:1-12 --top-k=0`

*Body SLICE: lines 1..12 of the symbol's own body, with lines="lo-hi/total" marking it partial.*

`````
<ctx schema="ripwire.expand/v1" root="." est_tokens="1066">
<!-- ripwire expand schema=ripwire.expand/v1: full bodies: <bodies shown= total= capped=> of <b t= l= p= n= sibs= sibs_total= sibs_capped= inc=>; <calls>
<c n= l= p=> resolved callees (p= when not the b's file). window: shown= total= capped= (capped=1 cut). sibs_capped=/inc_capped=: 1 = cut. est_tokens=: price as emitted (an upper bound under compact). root=: p= relative to it. inc_total=N: the file's true include/import count; inc= lists the first 2 … [line truncated: 303 more bytes on this line]
<bodies shown="1" total="1" capped="0">
<b t="fn" l="14619" p="src/graph.h" n="rankGraphTeleport" lines="1-12/29" sibs="&lt;file-scope&gt;,DeclinedSiteKind,kNoDeclinedList,ProvenSite,operator&lt;=&gt;,provenSiteCountsFor,Graph,localityKeyAt,ImplementorRow,implementorClosure,LegoClosure,LegoClosureWalk,LegoClosureWalk,take,boundOf,add,expa … [line truncated: 1673 more bytes on this line]
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
        for( const double value : teleport )]]><calls total="4"><c n="biasPrior" l="14578">inline std::vector&lt;float&gt; biasPrior( const Graph&amp; g, const std::vector&lt;float&gt;&amp; p )</c><c n="PROFILE_SCOPE_DESCRIBE" l="1282" p="src/infra/profileScope.h">#define PROFILE_SCOPE_DESCRIBE( des … [line truncated: 411 more bytes on this line]
`````

## `./build/ripwire . --expand=compressBody --top-k=0 --compress`

*Comments stripped + blank runs collapsed — compressBody is the function that implements --compress itself, chosen because it is comment-heavy enough to show a real reduction (the previously captioned symbol had no comments or blank runs, so before/after were byte-identical under a caption promising a difference).*

`````
<ctx schema="ripwire.expand/v1" root="." est_tokens="1920">
<!-- ripwire expand schema=ripwire.expand/v1: full bodies: <bodies shown= total= capped=> of <b t= l= p= n= sibs= sibs_total= sibs_capped= inc=>; <calls>
<c n= l= p=> resolved callees (p= when not the b's file). window: shown= total= capped= (capped=1 cut). sibs_capped=/inc_capped=: 1 = cut. est_tokens=: price as emitted (an upper bound under compact). root=: p= relative to it. inc_total=N: the file's true include/import count; inc= lists the first 2 … [line truncated: 200 more bytes on this line]
<bodies shown="1" total="1" capped="0" compress="1">
<b t="fn" l="4693" p="src/serialize.h" n="compressBody" sibs="&lt;file-scope&gt;,xmlSafeByte,xmlScrubIsLossy,xmlControlCharRef,eraseAbsentClause,spliceClauseAfter,kXmlEscapeByteset,escapeXml,writeMultiRootTable,kMultiRootTableLegend,multiRootTableLegend,xmlCommentText,ctxRootOpen,ctxRootOpenParts,ct … [line truncated: 2007 more bytes on this line]
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
… [170 more display lines; full output is 7331 bytes on 195 raw line(s)]
`````

## `./build/ripwire . --expand=readAckRecords --top-k=0 --no-redact`

*--no-redact: emit bodies verbatim (credential redaction is on by default).*

`````
<ctx schema="ripwire.expand/v1" root="." est_tokens="3086">
<!-- ripwire expand schema=ripwire.expand/v1: full bodies: <bodies shown= total= capped=> of <b t= l= p= n= sibs= sibs_total= sibs_capped= inc=>; <calls>
<c n= l= p=> resolved callees (p= when not the b's file). window: shown= total= capped= (capped=1 cut). sibs_capped=/inc_capped=: 1 = cut. est_tokens=: price as emitted (an upper bound under compact). root=: p= relative to it. <c via="name">: that callee matched by name alone (receiver unproven); it … [line truncated: 410 more bytes on this line]
<bodies shown="3" total="3" capped="0">
<b t="fn" l="9253" p="src/quality.h" n="readAckRecords" sibs="&lt;file-scope&gt;,kBaselineFile,kMinCloneTokens,kCcxBar,kLocBar,kNestBar,kParamBar,kShortHorizonDays,kShortHorizonMinCommits,kReusedHelperMinFanin,kMinorCcxDelta,kMinorLocDelta,kMinorParamDelta,kMaterialGrowthPct,kSubBarGrowthPct,subBarG … [line truncated: 1751 more bytes on this line]
<![CDATA[inline gtl::btree_map<std::string, AckRecord> readAckRecords( const std::string& path, std::size_t& badLines );]]>
</b>
<b t="fn" l="9255" p="src/quality.h" n="readAckRecords" sibs="&lt;file-scope&gt;,kBaselineFile,kMinCloneTokens,kCcxBar,kLocBar,kNestBar,kParamBar,kShortHorizonDays,kShortHorizonMinCommits,kReusedHelperMinFanin,kMinorCcxDelta,kMinorLocDelta,kMinorParamDelta,kMaterialGrowthPct,kSubBarGrowthPct,subBarG … [line truncated: 1751 more bytes on this line]
<![CDATA[inline gtl::btree_map<std::string, AckRecord> readAckRecords( const std::string& path )
{
    std::size_t ignored = 0;
    return readAckRecords( path, ignored );
}]]><calls total="1"><c n="readAckRecords" l="9261">inline gtl::btree_map&lt;std::string, AckRecord&gt; readAckRecords( const std::string&amp; path, std::size_t&amp; badLines )</c></calls></b><b t="fn" l="9261" p="src/quality.h" n="readAckRecords" sibs="&lt;file-scope&gt;,kBaselineFile,kMinCloneToke … [line truncated: 2062 more bytes on this line]
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
… [46 more display lines; full output is 11763 bytes on 68 raw line(s)]
`````

## `./build/ripwire . --pack-top-n=3 --top-k=0`

*Pack the top-3 ranked symbols' full bodies (deprecated verb; see stderr).*

`````
<ctx schema="ripwire.pack-top-n/v1" root="." est_tokens="17442">
<!-- ripwire pack-top-n schema=ripwire.pack-top-n/v1: the ranked map plus <src p=> bodies of the top-N symbols. window: shown= total= capped= (capped=1 cut). est_tokens=: price as emitted (an upper bound under compact). root=: p= relative to it. <src truncated=1 lines=1-K/T>: cut at a line end at the byte budget; K of its T lines. <src_cut shown= total= capped=1 budget_bytes=>: files served of the top-N asked, the rest over the byte ceiling; unreadable=N not readable. -->
<src_cut shown="1" total="3" capped="1" budget_bytes="65536"/>
<src p="./src/graph.h" truncated="1" lines="1-1007/21045">
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
#include "infra/hashutil.h"      // packPair — composite integer keys
#include "pagerank.h"            // double-precision PageRank kernel over float CSR storage
#include "prconverge.h"          // RankDisclosure — the power iteration's own account, carried with its result
#include "smallvec.h"            // rw::SmallVec — THE ONE ALIAS (src/smallvec.h picks the implementation)
#include "resolve.h"             // P2-D one-hop type narrowing (Rule 1: class membership) — applied before the name-based fallback
#include "receiverevidence.h"    // FE-B: typed receivers RESOLVE; a call nothing proves keeps its rows marked via="name"
#include "ifacedispatch.h"       // lane L6: a call on an interface-typed receiver names its implementors' methods (BaseBound)
#include "langfacts.h"           // langFacts(l): the per-language facts the resolver reads instead of a Lang:: compare
#include "scipoverlay.h"         // SCIP precision overlay (data struct only; parser lives in scip.h)
#include "pincensus.h"           // eval-only per-call-site decision census (--pin-census); inert unless armed
… [981 more display lines; full output is 66176 bytes on 1007 raw line(s)]
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
<!-- ripwire metrics schema=ripwire.metrics/v1: the ranked map with per-symbol metrics. est_tokens=: price as emitted (an upper bound under compact). root=: p= relative to it. pr_iters=N: PageRank iterations. <inv listed= unlisted=>: files the ranked rows show / do not (sum = files=), each named or counted below. <entry p= n=>: a program entry by its language's convention (C/Go/Rust main, Java/C# static main, a script main its module scope calls, __main__.py), callees as c rows; manifest entries not read. <ls p= n= f=>: n= unshown files under dir p=; f= names its code files, the rest (tests, docs, config, test/doc/example dirs) counted. declined=K: K call sites without edges, including inert Elixir quote sites after unquote/unquote_splicing re-entry. external=K: K calls proven outside the tree, no edge. locality_pinned=K: K calls pinned by locality alone (a guess). extent_suspect_syms=K: K defs failed containment, corpus-wide. macro_blanked_files=K: K files indexed from a macro-blanked re-parse. prov=scip|binding|import|split|final-segment: how that <c> edge bound (absent: one unique name); split = one arm of an amb= pick; final-segment = a qualified type matched by last name only. files=/symbols=: files and symbols indexed; edges= distinct call edges; shown= symbols printed, a merged row counting each def; ambiguous= calls split over several defs, corpus-wide; unresolved= calls with in-tree evidence and no edge (every def language-filtered or unreachable, or binding refused); order= rows by rank (important-first, important-last; (auto:fill) = flipped past a size threshold) or by path (stable). skipped_oversize=K: K files over a size ceiling, not indexed. unindexed=ext:N: N text files of that extension no grammar reads (6 extensions at most). unindexed_exts=E: E such extensions in all, the list cut. <s tested=1>: a non-test row an indexed test transitively reaches (absent otherwise, never 0). <c via="name">: that callee matched by name alone (receiver unproven); it does NOT mean the edge is false. sc=: enclosing scope; the full id is p::sc::n (p= of the row or its <f>) and selectors take it. amb=K: K calls split over several defs. locals_floor=1: locals= is a floor. role=hub: in= is 8 or more. s in= out= cx= ccx= loc= params= nest= cbo= lcom4= amp=: callers, callees, cyclomatic/cognitive complexity, lines, parameters, nesting depth, coupled types, class cohesion, callers + co-changed files. ev=/ev_why=: essential complexity (2+: jumps block extract-method; absent: 1) / the jumps behind it, tag:count. ev_floor=1: ev= is a FLOOR; noreturn calls, macro-hidden exits and unresolved gotos are unseen. layer=: built-in arch layer (game|infra|render|math|audio|ai|test) from a dir name in p=; absent if none. l=N: start line; only on a same-name overload's row, one row per body (bodyless decls fold into overloads=). f p=: a file; s t= n=: kind, name; c n=: a resolved callee. s k=: rank. -->
<!-- t=modscope=a-file's-MODULE-SCOPE(n=<file-scope>):the-statements-outside-every-named-definition,where-a-top-level-call-and-an-anonymous-callback-body's-calls-live;a-CALLER-never-a-callee(nothing-in-the-source-can-name-it)-with-no-body-to-expand;a-file-with-no-such-call-has-no-such-row -->
<!-- t=type|alias|functype=a-Go-named-type-by-its-written-form:type=a-defined-type-whose-WRITTEN-form-is-not-a-struct/iface/func-literal(type-N-string;type-W-Pair-too,whatever-Pair-is-underneath),alias=type-A=B,functype=type-F-func(...) -->
<!-- t=alias|functype-in-C++-and-.h:alias=using-X=Y(also-templated-or-class-scope)or-namespace-L=lib(defs=X-prints-its-written-target-as-to=),functype=a-typedef-of-a-function-or-function-pointer-type(typedef-void(*F)(int));other-typedefs-read-t=struct -->
<!-- files=4838 symbols=44600 edges=44429 shown=10 est_tokens=5162 ambiguous=3634 unresolved=20069 locality_pinned=14 external=12457 declined=45295 extent_suspect_syms=12 macro_blanked_files=7 skipped_oversize=15 unindexed="txt:85,tsv:54,mod:33,xml:33,jsonl:26,scm:25" unindexed_exts=23 order=important-first -->
<r schema="ripwire.metrics/v1" root="." est_tokens="5162" pr_iters="40">
<f p="src/infra/nodekind.h" layer="infra">
<s t="fn" n="kindIs" sc="rw" in="441" out="0" cx="3" ccx="3" role="hub" loc="11" params="2" nest="2" locals="0" locals_floor="1" cbo="0" amp="454" tested="1" k="0.0031" ev="3" ev_floor="1" ev_why="guard-return:1">
</s>
</f>
<f p="src/ingest_metrics.h">
<s t="fn" n="nodeTextOf" in="207" out="0" cx="4" ccx="3" role="hub" loc="9" params="2" nest="1" locals="2" locals_floor="1" cbo="0" amp="351" tested="1" k="0.0021" ev="2" ev_floor="1" ev_why="guard-return:1">
</s>
</f>
<f p="src/infra/namesplit.h" layer="infra">
<s t="fn" n="isIdentChar" sc="namesplit" in="113" out="0" cx="7" ccx="4" role="hub" loc="4" params="1" nest="0" locals="0" locals_floor="1" cbo="0" amp="153" tested="1" k="0.0020">
</s>
</f>
<f p="src/model.h">
<s t="fn" n="relForHash" sc="rw" in="54" out="0" cx="17" ccx="13" role="hub" loc="35" params="2" nest="2" locals="2" locals_floor="1" cbo="0" amp="624" tested="1" k="0.0019">
</s>
<s t="fn" n="rootRelPath" sc="rw" in="246" out="1" cx="2" ccx="1" role="hub" loc="5" params="2" nest="1" locals="1" locals_floor="1" cbo="1" amp="816" tested="1" k="0.0018">
<c n="relForHash"/>
</s>
</f>
<f p="src/infra/Diagnostics.h" layer="infra">
<s t="macro" n="RW_ASSUME_" l="328" in="3" out="1" cx="0" ccx="0" loc="2" cbo="1" amp="74" tested="1" k="0.0018">
<c n="RW_CHECK_"/>
</s>
<s t="macro" n="RW_ASSUME_" l="370" in="3" out="3" cx="0" ccx="0" loc="7" cbo="3" amp="74" tested="1" amb="1" k="0.0018">
… [108 more display lines; full output is 12814 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --deps`

*File->file dependency graph (god-files, cycles).*

`````
<!-- ripwire deps schema=ripwire.deps/v1: file-to-file include/import view, heaviest cone first: <f p= afferent= includes= instab= transitive=>, <health>, <godfiles>, <cycles>. window: shown= total= capped= has_more= next_offset= offset= limit= (capped=1 cut; next_offset= pastes as offset=). graph_partial=1: measured over resolved edges; unresolved imports could add, merge or remove cycles and change ratios. no_file_edges=LANGS: this build resolves almost none of these languages' imports to files (Go only across go.mod replace); counts over them (ca/ce and violations= of the arch verb) are floors over the resolved edges only, and a coupling number absent beside it is unknown, not zero. unmeasured_files=N: files in the no_file_edges= languages; an edge to or from them is in a count only where this build resolved it. masked_files=N: no_file_edges= files, left out of dep_files=/ccd/nccd/shape and propagation_cost (an edgeless one would count as a cone of one; one with an edge has only a floor). health cyclic_files=N: dep_files= files inside an include cycle (all cycles, not only the listed ones); absent at 0. health containment_edges=N: Rust mod x; pairs whose only directive is the declaration, out of transitive=/cycles/ccd/shape, in Ca/Ce. root=: p= relative to it. files=N: files with at least one include/import directive; this listing's denominator (health files= = corpus). violations=N: edges into a file more unstable by over 0.05 (Martin I); only the worst 12 are listed. from=: the including file of a stable-deps violation; it depends on the more unstable to=. gap=: instab of to= minus instab of from=, project includes only; worst first. godfiles f layer=: built-in arch layer (game|infra|render|math|audio|ai|test) from a dir name in p=; absent if none. layer=test only for a file under a test directory whose dependents are all test paths, by path. health dep_files=N: dependency-capable files (dep_langs=), the ccd/acd/nccd denominator. health dep_langs=: the languages dep_files= counts; compare its numbers across builds only when equal. ccd=/acd=/nccd=: Lakos: sum of per-file transitive cones (self incl) / per file / over a balanced tree's. health shape=: tangled when cyclic_files= is 1 in 20 of dep_files= or more, else nccd= below 1 horizontal, from 1 vertical (a heuristic). health lazy_edges=N: in-closure (lazy) include pairs kept OUT of cones, cycles and ccd; absent at 0. cycle size=/cost=: files in that include cycle / size squared, the cycle's share of ccd=. cycle cut=/cutrefs=: SUGGESTED edge to break it (fewest directives) / that edge's directive count; nothing cut. inc t=: one include/import target as written; one with no edge did not resolve to an indexed file. -->
<deps schema="ripwire.deps/v1" files="1863" shown="40" capped="1" total="1863" has_more="1" next_offset="40" offset="0" limit="0" root="." no_file_edges="go,swift,java,cs,php,dart,kt,gd,clj" unmeasured_files="407" graph_partial="1">
<health files="4838" dep_files="3795" ccd="22697" acd="6.0" nccd="0.55" shape="horizontal" cyclic_files="15" masked_files="393" lazy_edges="82" containment_edges="147" dep_langs="cpp,py,ts,go,rs,swift,objc,js,sh,java,rb,cs,c,php,lua,ex,kt"/>
<godfiles total="951" shown="12" capped="1">
<f p="test/lib/clean-env.sh" afferent="283" layer="test"/>
<f p="src/model.h" afferent="144"/>
<f p="src/infra/emit.h" afferent="101" layer="infra"/>
<f p="src/infra/sortutil.h" afferent="89" layer="infra"/>
<f p="src/infra/Diagnostics.h" afferent="78" layer="infra"/>
<f p="src/serialize.h" afferent="75"/>
<f p="src/graph.h" afferent="74"/>
<f p="src/nextverb.h" afferent="43"/>
<f p="src/infra/os.h" afferent="41" layer="infra"/>
<f p="src/filter.h" afferent="40"/>
<f p="src/infra/namesplit.h" afferent="36" layer="infra"/>
<f p="scripts/cxxstd.sh" afferent="34"/>
</godfiles>
<stabledeps violations="85">
<v from="src/graph.h" to="src/ifacedispatch.h" gap="0.56"/>
<v from="src/graph.h" to="src/argtypepick.h" gap="0.54"/>
<v from="src/graph.h" to="src/pincensus.h" gap="0.54"/>
<v from="src/graph.h" to="src/restlinks.h" gap="0.54"/>
<v from="src/graph.h" to="src/pyscopepin.h" gap="0.50"/>
<v from="test/declinedsitefix/rb/lib/rake/task.rb" to="test/legotransitivefix/rb/task.rb" gap="0.50"/>
<v from="src/gitstamp.h" to="src/quality.h" gap="0.48"/>
<v from="test/ifacedispatchfix/rs/src/render/mod.rs" to="test/ifacedispatchfix/rs/src/render/impls.rs" gap="0.47"/>
<v from="src/docparse.h" to="src/htmldoc.h" gap="0.46"/>
<v from="src/serialize.h" to="src/countfloor.h" gap="0.37"/>
<v from="src/serialize.h" to="src/mapinventory.h" gap="0.36"/>
<v from="src/model.h" to="src/refnames.h" gap="0.28"/>
… [913 more display lines; full output is 26179 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --hotspots`

*Complexity x recent git churn (maintenance pain).*

**wall time: 2.86s**

`````
<!-- ripwire hotspots schema=ripwire.hotspots/v1: maintenance pain = churn x ccx over window=: <f p= churn= ccx= score= top= top_ccx= top_l=>; unranked_*= no churn/complexity. window: shown= total= capped= has_more= next_offset= offset= limit= (capped=1 cut; next_offset= pastes as offset=). at=: commit+dirty+shallow. root=: p= relative to it. files=/ranked=: files in the window / those with both churn and complexity; ranked + unranked_no_churn + unranked_no_complexity = files. unranked_no_churn=/unranked_no_complexity=: files left out for no commit in window= / no measured complexity. -->
<!-- extent_suspect_syms=K on a row = K of the file's functions failed an extent/scope containment check (the map, the bundles and the skipped verb mark each one, reasons and all) and are LEFT OUT of that row's ccx=, score= and top=, so its ccx= is a FLOOR of the file's true sum rather than a total. unranked_extent_suspect= counts files with commits whose every scorable function was left out that way (or whose trusted remainder scores 0), so ranked= + unranked_no_churn= + unranked_no_complexity= + unranked_extent_suspect= = files= exactly. Absent = nothing excluded. -->
<hotspots schema="ripwire.hotspots/v1" window="12mo@HEAD" files="4838" ranked="1115" unranked_no_churn="0" unranked_no_complexity="3721" unranked_extent_suspect="2" shown="40" capped="1" total="1115" has_more="1" next_offset="40" offset="0" limit="0" root="." at="6ace381eb">
<f p="src/graph.h" churn="713" ccx="6649" score="4740737" top="buildGraph" top_ccx="1979" top_l="10549"/>
<f p="src/quality.h" churn="684" ccx="2631" score="1799604" top="computeDelta" top_ccx="316" top_l="11886"/>
<f p="src/serialize.h" churn="515" ccx="2718" score="1399770" top="serialize" top_ccx="319" top_l="3317"/>
<f p="src/mcpverbs.h" churn="675" ccx="1369" score="924075" top="runBatchSub" top_ccx="142" top_l="6334"/>
<f p="src/main.cpp" churn="509" ccx="1356" score="690204" top="dispatchMainBody" top_ccx="513" top_l="4653"/>
<f p="src/verbs_for.h" churn="422" ccx="1358" score="573076" top="runForLensPass" top_ccx="706" top_l="3606"/>
<f p="src/resolve.h" churn="218" ccx="2562" score="558516" top="buildPreciseIncludeAdjWithContext" top_ccx="103" top_l="5571"/>
<f p="src/cli.h" churn="650" ccx="682" score="443300" top="parseArgs" top_ccx="214" top_l="5740"/>
<f p="src/ingest_binds.h" churn="150" ccx="2603" score="390450" top="bindsVisitNode" top_ccx="102" top_l="7832"/>
<f p="src/verbs_navigate.h" churn="340" ccx="1038" score="352920" top="runVerify" top_ccx="144" top_l="2297"/>
<f p="src/verbs_quality.h" churn="198" ccx="995" score="197010" top="runQualityDelta" top_ccx="323" top_l="2638"/>
<f p="src/mcp.h" churn="189" ccx="991" score="187299" top="dispatchMcpLine" top_ccx="794" top_l="1151"/>
<f p="src/ingest_sidecap.h" churn="181" ccx="1021" score="184801" top="captureTagsFacts" top_ccx="568" top_l="1902"/>
<f p="src/compactlegend.h" churn="541" ccx="328" score="177448" top="applyCompactDialectOnce" top_ccx="49" top_l="2662"/>
<f p="src/receiverevidence.h" churn="109" ccx="1556" score="169604" top="bareClassAt" top_ccx="77" top_l="739"/>
<f p="src/ingest_cache.h" churn="389" ccx="398" score="154822" top="saveCache" top_ccx="113" top_l="3681"/>
<f p="src/verbs_report.h" churn="117" ccx="1199" score="140283" top="runStructureText" top_ccx="270" top_l="3358"/>
<f p="src/crossref.h" churn="111" ccx="1147" score="127317" top="mergeBasesByOneWalk" top_ccx="45" top_l="1626"/>
<f p="src/ingest_valuerefs.h" churn="83" ccx="1502" score="124666" top="classify" top_ccx="119" top_l="2479"/>
<f p="src/forliteral.h" churn="65" ccx="1795" score="116675" top="renderForLiteral" top_ccx="277" top_l="4210"/>
<f p="src/lexical.h" churn="92" ccx="911" score="83812" top="lexicalScoresTiered" top_ccx="509" top_l="538"/>
<f p="src/ingest_names.h" churn="86" ccx="965" score="82990" top="braceBlockHoldsStatement" top_ccx="33" top_l="2779"/>
<f p="src/gitmine.h" churn="106" ccx="747" score="79182" top="applyCoChangeBoost" top_ccx="95" top_l="3620"/>
<f p="src/ingest_relations.h" churn="95" ccx="733" score="69635" top="captureFields" top_ccx="99" top_l="1409"/>
<f p="src/model.h" churn="338" ccx="186" score="62868" top="shadowSuppressedSite" top_ccx="14" top_l="3046"/>
<f p="src/valuerefindex.h" churn="70" ccx="897" score="62790" top="resolveName" top_ccx="47" top_l="1944"/>
<f p="src/defectshape.h" churn="22" ccx="2485" score="54670" top="lexCpp" top_ccx="107" top_l="299"/>
… [14 more display lines; full output is 5825 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --clones`

*Token-normalized duplicate bodies.*

**wall time: 1.57s**

`````
<!-- ripwire clones schema=ripwire.clones/v1: similar normalized-token bodies: <group type=2|3 gid= tokens= n= similarity=> of <f n= p=>; dup_loc=/dup_pct=. window: shown= total= capped= has_more= next_offset= offset= limit= (capped=1 cut; next_offset= pastes as offset=). root=: p= relative to it. groups=/type3=: Type-2 and Type-3 group totals over all groups; total= is their sum. exempt_groups=N: groups whose members all sit on fixture/shell-runner paths quality-delta duplication ignores. idiom_groups=/demoted_groups=: groups of one recognized idiom / those quality-delta demotes to minor; floors. clone_groups=N: clusters after merging pairs (rows sharing gid=); a floor under type3_capped=1. total_loc=N: lines of every function body the detector considered; dup_pct= is dup_loc= over it. group exempt=fixture|shell-runner: every member is on such a path; quality-delta duplication ignores it. group idiom=: the recognized shape every member spells: threshold-ladder, switch-name-table, builder-chain, one-statement, call-sequence. -->
<clones schema="ripwire.clones/v1" groups="173" type3="935" exempt_groups="750" idiom_groups="61" demoted_groups="30" clone_groups="463" dup_loc="8950" total_loc="332920" dup_pct="2.7" shown="80" capped="1" total="1108" has_more="1" next_offset="80" offset="0" limit="0" root=".">
<group type="2" gid="50" tokens="338" n="3">
<f n="rw_is_ripwire_call" p="hooks/ripwire-claude-route.sh:187"/>
<f n="rw_is_ripwire_call" p="hooks/ripwire-codex-route.sh:104"/>
<f n="rw_is_ripwire_call" p="hooks/ripwire-nudge.sh:623"/>
</group>
<group type="2" gid="287" tokens="213" n="2" exempt="shell-runner">
<f n="call_sites" p="test/declinecheck.sh:116"/>
<f n="call_sites" p="test/usesselectorcheck.sh:55"/>
</group>
<group type="2" gid="387" tokens="211" n="4" exempt="shell-runner">
<f n="batch_sub" p="test/mcpclidiffcheck.sh:64"/>
<f n="batch_sub" p="test/mcptranchecheck.sh:55"/>
<f n="batch_sub" p="test/mcpw2fixcheck.sh:52"/>
<f n="batch_sub" p="test/mcpw3fixcheck.sh:51"/>
</group>
<group type="2" gid="240" tokens="210" n="2" exempt="shell-runner">
<f n="mcpfor" p="test/anchorhonestycheck.sh:37"/>
<f n="mcpfor" p="test/foranchornscheck.sh:29"/>
</group>
<group type="2" gid="409" tokens="198" n="2" exempt="shell-runner">
<f n="classify" p="test/preludevetocheck.sh:41"/>
<f n="classify" p="test/rustmacropathcheck.sh:53"/>
</group>
<group type="2" gid="282" tokens="175" n="2" exempt="shell-runner">
<f n="mcp" p="test/pathfewestcheck.sh:320"/>
<f n="mcp" p="test/pathroutecheck.sh:468"/>
</group>
<group type="2" gid="49" tokens="163" n="3">
… [309 more display lines; full output is 16374 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --cochange`

*Files that change together in git (hidden coupling).*

**wall time: 1.82s**

`````
<!-- ripwire cochange schema=ripwire.cochange/v1: files that change together in git: <pair a= b= together= deg= conf_ab= conf_ba= surprising=>, or for of= <f p= together= conf_rev=>. window: shown= total= capped= has_more= next_offset= offset= limit= (capped=1 cut; next_offset= pastes as offset=). at=: commit+dirty+shallow. root=: p= relative to it. pairs=N: file pairs with 3+ shared commits in window= (after min_recur), surprising or not. sub_windows=N: equal-commit-count slices of window=; the denominator of recur=. driver=a|b: the side whose changes best imply the other's, look there first; absent on a tie. recur=K: slices of sub_windows= the pair co-changed in; 1 = one burst, not a standing coupling. -->
<cochange schema="ripwire.cochange/v1" pairs="5677" window="18mo@HEAD" sub_windows="3" shown="30" capped="1" total="5677" has_more="1" next_offset="30" offset="0" limit="0" root="." at="6ace381eb">
<pair a="test/headsnapcachecheck.sh" b="test/qsnapcachecheck.sh" together="5" deg="1.00" conf_ab="1.00" conf_ba="0.83" driver="a" recur="3" surprising="1"/>
<pair a="src/aliasdef.h" b="src/ingest_sidecap.h" together="5" deg="1.00" conf_ab="1.00" conf_ba="0.03" driver="a" recur="1" surprising="1"/>
<pair a="src/main.cpp" b="src/warmsnap_model.h" together="4" deg="1.00" conf_ab="0.01" conf_ba="1.00" driver="b" recur="1" surprising="1"/>
<pair a="src/foraliashop.h" b="src/verbs_navigate.h" together="4" deg="1.00" conf_ab="1.00" conf_ba="0.01" driver="a" recur="1" surprising="1"/>
<pair a="src/layout.h" b="test/layoutfix/attrfields.h" together="4" deg="1.00" conf_ab="0.11" conf_ba="1.00" driver="b" recur="1" surprising="1"/>
<pair a="src/cli.h" b="src/handoffwindow.h" together="4" deg="1.00" conf_ab="0.01" conf_ba="1.00" driver="b" recur="1" surprising="1"/>
<pair a="src/verbs_report.h" b="test/fileset_unit.cpp" together="3" deg="1.00" conf_ab="0.03" conf_ba="1.00" driver="b" recur="1" surprising="1"/>
<pair a="src/binstale.h" b="src/crossref.h" together="3" deg="1.00" conf_ab="1.00" conf_ba="0.03" driver="a" recur="2" surprising="1"/>
<pair a="test/qschemetripcheck.sh" b="test/rubyrequirecheck.sh" together="3" deg="1.00" conf_ab="0.01" conf_ba="1.00" driver="b" recur="1" surprising="1"/>
<pair a="src/accessshape.h" b="test/accessshapefix/walks.cpp" together="3" deg="1.00" conf_ab="0.60" conf_ba="1.00" driver="b" recur="1" surprising="1"/>
<pair a="test/cachesplitcheck.sh" b="test/portablecachecheck.sh" together="3" deg="1.00" conf_ab="0.75" conf_ba="1.00" driver="b" recur="3" surprising="1"/>
<pair a="src/graph.h" b="test/fileset_unit.cpp" together="3" deg="1.00" conf_ab="0.00" conf_ba="1.00" driver="b" recur="1" surprising="1"/>
<pair a="test/lib/sweeproot.sh" b="test/substrfiltercheck.sh" together="3" deg="1.00" conf_ab="1.00" conf_ba="0.27" driver="a" recur="1" surprising="1"/>
<pair a="src/arch.h" b="test/fileset_unit.cpp" together="3" deg="1.00" conf_ab="0.07" conf_ba="1.00" driver="b" recur="1" surprising="1"/>
<pair a="src/ingest_valuerefs.h" b="src/pydottedpath.h" together="3" deg="1.00" conf_ab="0.04" conf_ba="1.00" driver="b" recur="1" surprising="1"/>
<pair a="test/elixircheck.sh" b="test/elixirsemanticcheck.sh" together="3" deg="1.00" conf_ab="0.13" conf_ba="1.00" driver="b" recur="2" surprising="1"/>
<pair a="test/fnslotcpp2/dep.cc" b="test/fnslotcpp2/use_bnd.cc" together="3" deg="1.00" conf_ab="1.00" conf_ba="0.75" driver="a" recur="1" surprising="1"/>
<pair a="src/ingest_cache.h" b="src/refnames.h" together="3" deg="1.00" conf_ab="0.01" conf_ba="1.00" driver="b" recur="1" surprising="1"/>
<pair a="test/mcpslicecheck.sh" b="test/mcpverbscheck.sh" together="3" deg="1.00" conf_ab="1.00" conf_ba="0.16" driver="a" recur="2" surprising="1"/>
<pair a="test/pincensuscheck.sh" b="test/scipjoincheck.sh" together="3" deg="1.00" conf_ab="0.38" conf_ba="1.00" driver="b" recur="2" surprising="1"/>
<pair a="test/rubyrecvcheck.sh" b="test/rubyrequirecheck.sh" together="3" deg="1.00" conf_ab="0.50" conf_ba="1.00" driver="b" recur="1" surprising="1"/>
<pair a="test/luacheck.sh" b="test/phpcheck.sh" together="3" deg="1.00" conf_ab="0.75" conf_ba="1.00" driver="b" recur="2" surprising="1"/>
<pair a="test/grepcheck.sh" b="test/grepcontextcheck.sh" together="3" deg="1.00" conf_ab="0.50" conf_ba="1.00" driver="b" recur="1" surprising="1"/>
<pair a="test/grepcheck.sh" b="test/grepscancheck.sh" together="3" deg="1.00" conf_ab="0.50" conf_ba="1.00" driver="b" recur="1" surprising="1"/>
<pair a="src/compactlegend.h" b="src/similarargs.h" together="3" deg="1.00" conf_ab="0.01" conf_ba="1.00" driver="b" recur="1" surprising="1"/>
<pair a="test/grepcontextcheck.sh" b="test/grepscancheck.sh" together="3" deg="1.00" conf_ab="1.00" conf_ba="1.00" recur="1" surprising="1"/>
<pair a="test/cloneoperandcheck.sh" b="test/repeateddecisioncheck.sh" together="3" deg="1.00" conf_ab="1.00" conf_ba="0.75" driver="a" recur="1" surprising="1"/>
<pair a="test/gatecountcheck.sh" b="test/regression.sh" together="3" deg="1.00" conf_ab="1.00" conf_ba="0.00" driver="a" recur="2" surprising="1"/>
<pair a="test/gatecountcheck.sh" b="test/manifestcheck.sh" together="3" deg="1.00" conf_ab="1.00" conf_ba="0.23" driver="a" recur="2" surprising="1"/>
<pair a="src/fieldaffinity.h" b="test/accessshapefix/walks.cpp" together="3" deg="1.00" conf_ab="0.33" conf_ba="1.00" driver="b" recur="1" surprising="1"/>
</cochange>
`````

## `./build/ripwire . --hotspots --since="2 weeks ago"`

*Hotspots scoped to RECENT churn (the regression lens).*

**wall time: 1.68s**

`````
<!-- ripwire hotspots schema=ripwire.hotspots/v1: maintenance pain = churn x ccx over window=: <f p= churn= ccx= score= top= top_ccx= top_l=>; unranked_*= no churn/complexity. window: shown= total= capped= has_more= next_offset= offset= limit= (capped=1 cut; next_offset= pastes as offset=). at=: commit+dirty+shallow. root=: p= relative to it. files=/ranked=: files in the window / those with both churn and complexity; ranked + unranked_no_churn + unranked_no_complexity = files. unranked_no_churn=/unranked_no_complexity=: files left out for no commit in window= / no measured complexity. -->
<hotspots schema="ripwire.hotspots/v1" window="2 weeks ago" files="4838" ranked="437" unranked_no_churn="3954" unranked_no_complexity="447" shown="40" capped="1" total="437" has_more="1" next_offset="40" offset="0" limit="0" root="." at="6ace381eb">
<f p="src/graph.h" churn="107" ccx="6649" score="711443" top="buildGraph" top_ccx="1979" top_l="10549"/>
<f p="src/quality.h" churn="98" ccx="2631" score="257838" top="computeDelta" top_ccx="316" top_l="11886"/>
<f p="src/serialize.h" churn="60" ccx="2718" score="163080" top="serialize" top_ccx="319" top_l="3317"/>
<f p="src/mcpverbs.h" churn="107" ccx="1369" score="146483" top="runBatchSub" top_ccx="142" top_l="6334"/>
<f p="src/verbs_for.h" churn="94" ccx="1358" score="127652" top="runForLensPass" top_ccx="706" top_l="3606"/>
<f p="src/resolve.h" churn="29" ccx="2562" score="74298" top="buildPreciseIncludeAdjWithContext" top_ccx="103" top_l="5571"/>
<f p="src/cli.h" churn="91" ccx="682" score="62062" top="parseArgs" top_ccx="214" top_l="5740"/>
<f p="src/verbs_quality.h" churn="61" ccx="995" score="60695" top="runQualityDelta" top_ccx="323" top_l="2638"/>
<f p="src/main.cpp" churn="40" ccx="1356" score="54240" top="dispatchMainBody" top_ccx="513" top_l="4653"/>
<f p="src/ingest_binds.h" churn="18" ccx="2603" score="46854" top="bindsVisitNode" top_ccx="102" top_l="7832"/>
<f p="src/verbs_navigate.h" churn="45" ccx="1038" score="46710" top="runVerify" top_ccx="144" top_l="2297"/>
<f p="src/receiverevidence.h" churn="24" ccx="1556" score="37344" top="bareClassAt" top_ccx="77" top_l="739"/>
<f p="src/compactlegend.h" churn="103" ccx="328" score="33784" top="applyCompactDialectOnce" top_ccx="49" top_l="2662"/>
<f p="src/defectshape.h" churn="13" ccx="2485" score="32305" top="lexCpp" top_ccx="107" top_l="299"/>
<f p="src/forliteral.h" churn="13" ccx="1795" score="23335" top="renderForLiteral" top_ccx="277" top_l="4210"/>
<f p="src/ingest_sidecap.h" churn="20" ccx="1021" score="20420" top="captureTagsFacts" top_ccx="568" top_l="1902"/>
<f p="src/ingest_cache.h" churn="51" ccx="398" score="20298" top="saveCache" top_ccx="113" top_l="3681"/>
<f p="src/ingest_names.h" churn="20" ccx="965" score="19300" top="braceBlockHoldsStatement" top_ccx="33" top_l="2779"/>
<f p="src/ingest_valuerefs.h" churn="12" ccx="1502" score="18024" top="classify" top_ccx="119" top_l="2479"/>
<f p="src/crossref.h" churn="14" ccx="1147" score="16058" top="mergeBasesByOneWalk" top_ccx="45" top_l="1626"/>
<f p="src/exemplarfamily.h" churn="21" ccx="735" score="15435" top="openSpanAfter" top_ccx="37" top_l="1294"/>
<f p="src/darkflags.h" churn="16" ccx="959" score="15344" top="shellExpansionAt" top_ccx="61" top_l="1138"/>
<f p="src/forfilesyms.h" churn="32" ccx="478" score="15296" top="shownRows" top_ccx="34" top_l="368"/>
<f p="src/layout.h" churn="14" ccx="1051" score="14714" top="resolveStdType" top_ccx="47" top_l="2063"/>
<f p="src/subjectanchor.h" churn="27" ccx="452" score="12204" top="sentenceReaskInvocation" top_ccx="46" top_l="1153"/>
<f p="src/lexical.h" churn="13" ccx="911" score="11843" top="lexicalScoresTiered" top_ccx="509" top_l="538"/>
<f p="src/ingest_astquery.h" churn="15" ccx="751" score="11265" top="astQueryGrouped" top_ccx="214" top_l="842"/>
<f p="src/forreexport.h" churn="12" ccx="931" score="11172" top="genPathOf" top_ccx="92" top_l="2298"/>
… [13 more display lines; full output is 5195 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --arch=test/archfix/rules.txt`

*Enforce layering rules (exit 2 on violation) — run against the repo's own test fixture rules.*

`````
<!-- ripwire arch schema=ripwire.arch/v1: layering rules fit: v from= fromLayer= to= toLayer=: a file-to-file include/import a rule denies, with each end's layer (fromLayer=path: a regex path-rule, toLayer= that rule); layers= rules= pathRules= declared; violations= the v rows; baselined= those the baseline sidecar accepts, baselined=1 on the row (under baseline-update: every hash it now holds); a row without it is NEW, exit 2 if any; rules match root-relative paths. graph_partial=1: measured over resolved edges; unresolved imports could add, merge or remove cycles and change ratios. no_file_edges=LANGS: this build resolves almost none of these languages' imports to files (Go only across go.mod replace); counts over them (ca/ce and violations= of the arch verb) are floors over the resolved edges only, and a coupling number absent beside it is unknown, not zero. unmeasured_files=N: files in the no_file_edges= languages; an edge to or from them is in a count only where this build resolved it. masked_files=N: no_file_edges= files, left out of dep_files=/ccd/nccd/shape and propagation_cost (an edgeless one would count as a cone of one; one with an edge has only a floor). root=: from=/to=/path= relative to it. metrics: Martin metrics per directory, estimated from name-based deps; descriptive, never a gate. modules= the m rows, typed_modules= those with types>0; zone_pain= zone_useless= zone_ok= zone_na= partition modules=: the two main-sequence corners (a heuristic with no outcome-based validation: folklore, not proof), typed modules in neither, types=0 modules (no abstractness score). zone_unknown=: modules holding a file in a no_file_edges= language: zone and coupling unknown, not zero; a fifth part of the partition. propagation_cost=: density of the file-dep transitive closure (MacCormack): the fraction of files reachable from an average file. m path= ca= ce= types= abstract= I= A= D= zone= reachable=: a directory module: ca= modules depending on it, ce= modules it depends on, types= declared, abstract= abstract ones, I=ce/(ca+ce), A=abstract/types, D=|A+I-1| (distance from the main sequence), zone=pain|useless: D past 0.5 with A+I below|not below 1, else ok; n/a at types=0; reachable=0: no main and no module nothing depends on reaches it; isolated=1: ca=ce=0; leaf=1: ce=0 under ca>0. -->
<arch schema="ripwire.arch/v1" layers="2" rules="1" pathRules="0" violations="0" baselined="0" no_file_edges="go,swift,java,cs,php,dart,kt,gd,clj" unmeasured_files="407" graph_partial="1" root=".">
<metrics modules="1417" typed_modules="704" zone_pain="385" zone_useless="3" zone_ok="145" zone_na="639" zone_unknown="245" propagation_cost="0.002" masked_files="393">
<m path="." ca="0" ce="0" types="0" abstract="0" I="0.00" A="0.00" D="1.00" zone="n/a" reachable="1" isolated="1"/>
<m path=".codex-plugin" ca="0" ce="0" types="0" abstract="0" I="0.00" A="0.00" D="1.00" zone="n/a" reachable="1" isolated="1"/>
<m path=".github" ca="0" ce="0" types="0" abstract="0" I="0.00" A="0.00" D="1.00" zone="n/a" reachable="1" isolated="1"/>
<m path=".github/workflows" ca="0" ce="0" types="0" abstract="0" I="0.00" A="0.00" D="1.00" zone="n/a" reachable="1" isolated="1"/>
<m path="bench" ca="0" ce="1" types="24" abstract="2" I="1.00" A="0.08" D="0.08" zone="ok" reachable="1"/>
<m path="bench/agentloop" ca="0" ce="0" types="0" abstract="0" I="0.00" A="0.00" D="1.00" zone="n/a" reachable="1" isolated="1"/>
<m path="bench/agentloop/editsuite" ca="0" ce="0" types="0" abstract="0" I="0.00" A="0.00" D="1.00" zone="n/a" reachable="1" isolated="1"/>
<m path="bench/agentloop/editsuite/fixture" ca="0" ce="0" types="2" abstract="0" I="0.00" A="0.00" D="1.00" zone="pain" reachable="1" isolated="1"/>
<m path="bench/agentloop/editsuite/fixture/test" ca="0" ce="0" types="0" abstract="0" I="0.00" A="0.00" D="1.00" zone="n/a" reachable="1" isolated="1"/>
<m path="bench/agentloop/fixtures/grader" ca="0" ce="0" types="0" abstract="0" I="0.00" A="0.00" D="1.00" zone="n/a" reachable="1" isolated="1"/>
<m path="bench/agentloop/results" ca="0" ce="0" types="0" abstract="0" I="0.00" A="0.00" D="1.00" zone="n/a" reachable="1" isolated="1"/>
<m path="bench/arb" ca="0" ce="0" types="0" abstract="0" I="0.00" A="0.00" D="1.00" zone="n/a" reachable="1" isolated="1"/>
<m path="bench/arise-h2h" ca="0" ce="0" types="0" abstract="0" I="0.00" A="0.00" D="1.00" zone="n/a" reachable="1" isolated="1"/>
<m path="bench/arise-h2h/swe_agent_bundle_ripwire" ca="0" ce="0" types="0" abstract="0" I="0.00" A="0.00" D="1.00" zone="n/a" reachable="1" isolated="1"/>
<m path="bench/capsweep" ca="0" ce="0" types="0" abstract="0" I="0.00" A="0.00" D="1.00" zone="n/a" reachable="1" isolated="1"/>
<m path="bench/cppbench" ca="0" ce="0" types="1" abstract="0" I="0.00" A="0.00" D="1.00" zone="pain" reachable="1" isolated="1"/>
<m path="bench/cppbench/results" ca="0" ce="0" types="0" abstract="0" I="0.00" A="0.00" D="1.00" zone="n/a" reachable="1" isolated="1"/>
<m path="bench/ensemblecal" ca="0" ce="0" types="0" abstract="0" I="0.00" A="0.00" D="1.00" zone="n/a" reachable="1" isolated="1"/>
<m path="bench/fixround" ca="0" ce="0" types="0" abstract="0" I="0.00" A="0.00" D="1.00" zone="n/a" reachable="1" isolated="1"/>
<m path="bench/graft-h2h" ca="0" ce="0" types="0" abstract="0" I="0.00" A="0.00" D="1.00" zone="n/a" reachable="1" isolated="1"/>
<m path="bench/h4fixtures/bash" ca="0" ce="0" types="0" abstract="0" I="0.00" A="0.00" D="1.00" zone="n/a" reachable="1" isolated="1"/>
<m path="bench/h4fixtures/c" ca="0" ce="0" types="1" abstract="0" I="0.00" A="0.00" D="1.00" zone="pain" reachable="1" isolated="1"/>
<m path="bench/h4fixtures/cpp" ca="0" ce="0" types="2" abstract="1" I="0.00" A="0.50" D="0.50" zone="ok" reachable="1" isolated="1"/>
<m path="bench/h4fixtures/cppvex" ca="0" ce="0" types="0" abstract="0" I="0.00" A="0.00" D="1.00" zone="n/a" reachable="1" isolated="1"/>
<m path="bench/h4fixtures/csharp" types="3" abstract="0" A="0.00" zone="unknown" no_file_edges="cs"/>
<m path="bench/h4fixtures/go" types="1" abstract="0" A="0.00" zone="unknown" no_file_edges="go"/>
<m path="bench/h4fixtures/go2" types="1" abstract="0" A="0.00" zone="unknown" no_file_edges="go"/>
… [1392 more display lines; full output is 194260 bytes on 1 raw line(s)]
`````

stderr:

`````
ripwire arch: 407 file(s) in go,swift,java,cs,php,dart,kt,gd,clj: this build resolves almost none of their imports to files, so an edge through one was mostly never judged: violations= is a floor
`````

## `./build/ripwire . --lint`

*Built-in AST checks (c-cast, goto, unsafe-c-fn, ...).*

**wall time: 2.46s**

`````
<!-- ripwire lint schema=ripwire.lint/v1: AST-only checks, facts not gates: <rule name= count= shown_rows= rows_capped= count_capped=> of <f rule= p= in=>. window: shown= total= capped= has_more= next_offset= offset= limit= (capped=1 cut; next_offset= pastes as offset=). findings_capped=/rows_capped=/count_capped=: 1 = cut. counts_floor=1: every count is a FLOOR, never a total. root=: p= relative to it. findings=N: findings over the printed rules; a floor when findings_capped=1. findings_next=: the call counting the floored rules' rest (count_capped=1 rules only, 10x per-rule budget). -->
<lint schema="ripwire.lint/v1" findings="8608" shown="667" capped="1" total="8608" has_more="1" next_offset="667" offset="0" limit="0" counts_floor="1" findings_capped="1" findings_next="--lint --lint-select=magic-number --lint-max-per-rule=50000" root=".">
<rule name="c-style-cast" count="756" shown_rows="80" rows_capped="1"/>
<rule name="goto" count="17" shown_rows="0" rows_capped="1"/>
<rule name="do-while" count="20" shown_rows="0" rows_capped="1"/>
<rule name="unsafe-c-fn" count="0" shown_rows="0" rows_capped="0"/>
<rule name="weak-crypto" count="0" shown_rows="0" rows_capped="0"/>
<rule name="redundant-parens" count="0" shown_rows="0" rows_capped="0"/>
<rule name="suspicious-semicolon" count="0" shown_rows="0" rows_capped="0"/>
<rule name="typedef-over-using" count="50" shown_rows="0" rows_capped="1"/>
<rule name="magic-number" count="372" shown_rows="235" rows_capped="1" count_capped="1"/>
<rule name="empty-catch" count="1" shown_rows="0" rows_capped="1"/>
<rule name="self-assign" count="3" shown_rows="0" rows_capped="1"/>
<rule name="large-function" count="378" shown_rows="34" rows_capped="1"/>
<rule name="deep-nesting" count="553" shown_rows="42" rows_capped="1"/>
<rule name="inconsistent-return" count="2" shown_rows="0" rows_capped="1"/>
<rule name="unreachable-code" count="5" shown_rows="0" rows_capped="1"/>
<rule name="naming-short" count="2266" shown_rows="81" rows_capped="1"/>
<rule name="naming-wordy" count="191" shown_rows="7" rows_capped="1"/>
<rule name="naming-series" count="983" shown_rows="0" rows_capped="1"/>
<rule name="naming-underscore" count="2" shown_rows="0" rows_capped="1"/>
<rule name="naming-case" count="102" shown_rows="0" rows_capped="1"/>
<rule name="naming-predicate" count="1" shown_rows="0" rows_capped="1"/>
<rule name="naming-setter" count="4" shown_rows="0" rows_capped="1"/>
<rule name="naming-confusable" count="1139" shown_rows="33" rows_capped="1"/>
<rule name="naming-uninformative" count="0" shown_rows="0" rows_capped="0"/>
<rule name="atom-comma-operator" count="5" shown_rows="0" rows_capped="1"/>
<rule name="atom-embedded-crement" count="255" shown_rows="17" rows_capped="1"/>
<rule name="atom-assign-as-value" count="108" shown_rows="11" rows_capped="1"/>
<rule name="atom-nested-ternary" count="374" shown_rows="26" rows_capped="1"/>
… [679 more display lines; full output is 70968 bytes on 1 raw line(s)]
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
[math degraded] lint-rules: malformed rule file skipped  (lintrules.h:494, auto rw::parseLintRuleFile(const std::string &, std::string_view, std::vector<LintRule> &)::(anonymous class)::operator()(std::size_t, const char *) const — logged once per site)
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
<communities schema="ripwire.communities/v1" drill="--community=ID" modules="5170" shown_modules="30" modules_capped="1" bridges="8510" shown_bridges="12" bridges_capped="1" isolated="20969" isolated_decl="5783" isolated_header="3540" isolated_source="4581" isolated_doc="7065" connected_singletons=" … [line truncated: 193 more bytes on this line]
<community id="6902" size="1774" dir="src" label="src::emitTo@infra/emit.h:53:2760 [write,run,emit]" shown="5" capped="1">
<member t="fn" n="relForHash" p="src/model.h:2722"/>
<member t="macro" n="EXPECTS" p="src/infra/Diagnostics.h:393"/>
<member t="fn" n="escapeXml" p="src/serialize.h:185"/>
<member t="fn" n="formatTo" p="src/infra/emit.h:141"/>
<member t="fn" n="emitTo" p="src/infra/emit.h:53"/>
</community>
<community id="6947" size="719" dir="src" label="src::kindIs@infra/nodekind.h:46:3271 [push,emit,read]" shown="5" capped="1">
<member t="fn" n="kindIs" p="src/infra/nodekind.h:46"/>
<member t="fn" n="nodeTextOf" p="src/ingest_metrics.h:161"/>
<member t="fn" n="fieldChild" p="src/infra/fieldid.h:223"/>
<member t="fn" n="forEachChild" p="src/infra/tschildren.h:89"/>
<member t="fn" n="parentOf" p="src/infra/tsparent.h:158"/>
</community>
<community id="6961" size="386" dir="src" label="src::DISCLOSE@infra/Diagnostics.h:622:43913 [read,scan,collect]" shown="5" capped="1">
<member t="macro" n="DISCLOSE" p="src/infra/Diagnostics.h:622"/>
<member t="fn" n="isStructOrNamedType" p="src/model.h:147"/>
<member t="fn" n="tokText" p="src/defectshape.h:160"/>
<member t="macro" n="VALIDATE" p="src/infra/Diagnostics.h:423"/>
<member t="fn" n="tokIs" p="src/defectshape.h:170"/>
</community>
<community id="6977" size="148" dir="src" label="src::str@infra/internedtext.h:323:16987 [resolve,find,add]" shown="5" capped="1">
<member t="method" n="appendUint" p="src/resolve.h:8130"/>
<member t="fn" n="fileNameKey" p="src/graph.h:3220"/>
<member t="fn" n="lexicalNormalize" p="src/resolve.h:179"/>
<member t="method" n="fieldName" p="src/model.h:1447"/>
<member t="method" n="str" p="src/warmsnap.h:162"/>
</community>
… [190 more display lines; full output is 16663 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --zoom`

*Nested module hierarchy (multi-level Louvain) + cross-module bridges — shown_levels="2" of levels= BY DEFAULT over the 40 largest top modules (~8 KB, where the whole tree is ~220 KB); a module AT the cut carries children=.*

`````
<!-- ripwire zoom schema=ripwire.zoom/v1: nested module hierarchy: <module level= id= size= dir= shown= capped=> of <member t= n= p=>; symbols= = isolated= + size= of all top_modules=. window: shown= total= capped= has_more= next_offset= offset= limit= (capped=1 cut; next_offset= pastes as offset=). levels_capped=: 1 = cut. counts_floor=1: every count is a FLOOR, never a total. graph_ambiguous=/graph_unresolved=: resolver gauge. graph_unindexed=N: N files no grammar could read (the map header's unindexed=); their calls raise neither gauge. pr_iters=N: PageRank iterations. shown_levels=N: of levels= printed; levels_capped=1 deeper ones unprinted. children=K: K child modules below the shown_levels= cut, unprinted. next=: the one pasteable follow-up. -->
<zoom schema="ripwire.zoom/v1" levels="5" shown_levels="2" levels_capped="1" top_modules="1688" symbols="44601" isolated="20969" shown="40" capped="1" total="1688" has_more="1" next_offset="40" offset="0" limit="0" pr_iters="40" graph_ambiguous="3634" graph_unresolved="20069" graph_unindexed="313" c … [line truncated: 42 more bytes on this line]
<module level="4" id="1818" size="11301" dir="./src">
<module level="3" id="1819" size="10661" dir="./src" children="33">
</module>
<module level="3" id="1831" size="640" dir="./src/infra" children="4">
</module>
</module>
<module level="4" id="6307" size="2936" dir="./test">
<module level="3" id="6309" size="2936" dir="./test" children="12">
</module>
</module>
<module level="4" id="1572" size="569" dir="./bench/agentloop">
<module level="3" id="1635" size="421" dir="./test" children="7">
</module>
<module level="3" id="1572" size="148" dir="./bench/agentloop" children="3">
</module>
</module>
<module level="4" id="740" size="321" dir="./docs">
<module level="3" id="740" size="321" dir="./docs" children="1">
</module>
</module>
<module level="4" id="19565" size="106" dir="./test/ownerhopfix/py/pkg">
<module level="3" id="19567" size="106" dir="./test/ownerhopfix/py/pkg" children="1">
</module>
</module>
<module level="4" id="5745" size="76" dir="./docs">
<module level="3" id="5747" size="76" dir="./docs" children="2">
</module>
</module>
… [137 more display lines; full output is 7641 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --zoom --zoom-levels=3`

*The restoring knob: --zoom-levels=N prints N levels (0 = the whole tree); here three, ~11 KB.*

`````
<!-- ripwire zoom schema=ripwire.zoom/v1: nested module hierarchy: <module level= id= size= dir= shown= capped=> of <member t= n= p=>; symbols= = isolated= + size= of all top_modules=. window: shown= total= capped= has_more= next_offset= offset= limit= (capped=1 cut; next_offset= pastes as offset=). levels_capped=: 1 = cut. counts_floor=1: every count is a FLOOR, never a total. graph_ambiguous=/graph_unresolved=: resolver gauge. graph_unindexed=N: N files no grammar could read (the map header's unindexed=); their calls raise neither gauge. pr_iters=N: PageRank iterations. shown_levels=N: of levels= printed; levels_capped=1 deeper ones unprinted. children=K: K child modules below the shown_levels= cut, unprinted. next=: the one pasteable follow-up. -->
<zoom schema="ripwire.zoom/v1" levels="5" shown_levels="3" levels_capped="1" top_modules="1688" symbols="44601" isolated="20969" shown="40" capped="1" total="1688" has_more="1" next_offset="40" offset="0" limit="0" pr_iters="40" graph_ambiguous="3634" graph_unresolved="20069" graph_unindexed="313" c … [line truncated: 58 more bytes on this line]
<module level="4" id="1818" size="11301" dir="./src">
<module level="3" id="1819" size="10661" dir="./src">
<module level="2" id="1825" size="8890" dir="./src" children="112">
</module>
<module level="2" id="6549" size="267" dir="./src" children="13">
</module>
<module level="2" id="7040" size="249" dir="./src" children="9">
</module>
<module level="2" id="8704" size="58" dir="./src/infra" children="5">
</module>
<module level="2" id="6625" size="102" dir="./src" children="6">
</module>
<module level="2" id="6791" size="100" dir="./src" children="8">
</module>
<module level="2" id="6729" size="96" dir="./src" children="5">
</module>
<module level="2" id="8824" size="104" dir="./src/infra" children="3">
</module>
<module level="2" id="6973" size="76" dir="./src" children="5">
</module>
<module level="2" id="1821" size="111" dir="./src/infra" children="3">
</module>
<module level="2" id="8197" size="58" dir="./src" children="3">
</module>
<module level="2" id="7287" size="58" dir="./src" children="6">
</module>
<module level="2" id="10079" size="53" dir="./src" children="2">
</module>
… [335 more display lines; full output is 15007 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --report`

*Architecture summary (modules, god-files, cycles) as markdown.*

`````
<!-- ripwire markdown: no run of 4-or-more backticks in this output — safe to embed inside a wider fence -->

# ripwire architecture report

4838 files · 44601 symbols · 44429 edges · 5170 modules (20969 call-graph isolated)

Root: `.`

Call-graph isolate provenance: 5783 declaration, 3540 header, 4581 source, 7065 document; 0 connected Louvain singletons

## Modules (call-graph clusters; showing 12 of 5170)
- **src::emitTo@infra/emit.h:53:2760 [write,run,emit]** — 1774 symbols
- **src::kindIs@infra/nodekind.h:46:3271 [push,emit,read]** — 719 symbols
- **src::DISCLOSE@infra/Diagnostics.h:622:43913 [read,scan,collect]** — 386 symbols
- **docs::`--top-k=N`@COMMANDS.md:59:9303 [pack,allow,insert]** — 185 symbols
- **src::str@infra/internedtext.h:323:16987 [resolve,find,add]** — 148 symbols
- **src/infra::fail@os_win32.cpp:63:2553 [open,get,close]** — 109 symbols
- **test/ownerhopfix/py/pkg::big_handler_001@broadcast.py:3:72** — 106 symbols
- **src::text@ingest_valuerefs.h:804:41690 [emit,open,mark]** — 91 symbols
- **src::sortUnique@infra/sortutil.h:55:2725 [connect,collect,compute]** — 87 symbols
- **src::shSingleQuote@infra/shquote.h:19:960 [resolve,run,read]** — 79 symbols
- **src::unq@shstatus.h:164:6384 [visit,call,bind]** — 77 symbols
- **src::isIdentChar@infra/namesplit.h:35:1884 [call,split,parse]** — 70 symbols

Not measured: 407 files in go,swift,java,cs,php,dart,kt,gd,clj (imports almost never resolved to files), so the god files and cycles below cover the resolved edges only.

## God files (most depended-on; showing 10 of 313)
- `src/model.h` — 144 dependents
- `src/infra/emit.h` — 101 dependents
- `src/infra/sortutil.h` — 89 dependents
… [38 more lines, 4346 bytes total]
`````

## `./build/ripwire . --seams`

*Cross-module call seams no test reaches. NOW carries seam_pairs/shown/capped.*

`````
<!-- ripwire seams schema=ripwire.seams/v1: cross-directory call edges NO test reaches: <seam from= to= untested= shown= capped=> of <edge caller= p= callee= cp=>. window: shown= total= capped= has_more= next_offset= offset= limit= (capped=1 cut; next_offset= pastes as offset=). counts_floor=1: every count is a FLOOR, never a total. graph_ambiguous=/graph_unresolved=: resolver gauge. graph_unindexed=N: N files no grammar could read (the map header's unindexed=); their calls raise neither gauge. root=: p= relative to it. pr_iters=N: PageRank iterations. modules=N: directories holding indexed symbols (a module = parent dir). bridges=N: cross-directory call edges, tested or not; untested= is those no test reaches. test_files=N: test files whose calls seed the reach; 0 means every seam reads untested. seam_pairs=N: directed dir pairs with an untested edge (the seam rows' total). doc_links=N: cross-directory links between two document sections, not in bridges= or untested= (no test exercises a document link); absent at 0. <file-scope> (t=modscope): a file's MODULE SCOPE — where a top-level call and an anonymous callback body's calls live; a CALLER, never a callee, with no body to expand. -->
<seams schema="ripwire.seams/v1" modules="1411" bridges="5837" untested="2955" doc_links="90" test_files="3932" seam_pairs="45" shown="20" capped="1" total="45" has_more="1" next_offset="20" offset="0" limit="0" pr_iters="40" root="." graph_ambiguous="3634" graph_unresolved="20069" graph_unindexed=" … [line truncated: 22 more bytes on this line]
<seam from="src" to="src/infra" untested="2766" shown="5" capped="1">
<edge caller="jsonStr" p="src/serialize.h:11022" callee="escapeMcp" cp="src/infra/jsonesc.h:247"/>
<edge caller="baseNameOf" p="src/mention.h:338" callee="afterLast" cp="src/infra/namesplit.h:158"/>
<edge caller="appendNextValueXml" p="src/nextverb.h:50" callee="utf8SeqLen" cp="src/infra/jsonesc.h:59"/>
<edge caller="jsonEscape" p="src/mcpjson.h:865" callee="escapeMcp" cp="src/infra/jsonesc.h:247"/>
<edge caller="tokensForEmittedBytes" p="src/serialize.h:1315" callee="ASSUME" cp="src/infra/Diagnostics.h:392"/>
</seam>
<seam from="bench" to="src/infra" untested="78" shown="5" capped="1">
<edge caller="infraSortSmall" p="bench/bench_radix_ab.cpp:73" callee="sortKeySmall" cp="src/infra/radixSort.h:91"/>
<edge caller="isSorted" p="bench/bench_sort_large.cpp:42" callee="lessByFromTo" cp="src/infra/sortutil.h:180"/>
<edge caller="benchScores" p="bench/bench_radix_ab.cpp:133" callee="nonNegativeFloatDescKey" cp="src/infra/sortutil.h:83"/>
<edge caller="benchScores" p="bench/bench_radix_ab.cpp:133" callee="lessByScoreDescId" cp="src/infra/sortutil.h:62"/>
<edge caller="benchAdaptive" p="bench/bench_radix_ab.cpp:157" callee="nonNegativeFloatDescKey" cp="src/infra/sortutil.h:83"/>
</seam>
<seam from="src/infra" to="src" untested="9" shown="5" capped="1">
<edge caller="RW_SAME_THREAD_" p="src/infra/Diagnostics.h:448" callee="load" cp="src/clones.h:986"/>
<edge caller="claimOrCheck" p="src/infra/Diagnostics.h:250" callee="load" cp="src/clones.h:986"/>
<edge caller="stopping" p="src/infra/pipefields.h:59" callee="load" cp="src/clones.h:986"/>
<edge caller="addEvents" p="src/infra/profileScope.h:323" callee="load" cp="src/clones.h:986"/>
<edge caller="liveThreadCount" p="src/infra/os.h:606" callee="increment" cp="src/ingest_crawl.h:1817"/>
</seam>
<seam from="bench/multiswe" to="bench/locbench" untested="8" shown="5" capped="1">
<edge caller="main" p="bench/multiswe/run_multiswe.py:301" callee="run_ctx" cp="bench/locbench/run_locbench.py:166"/>
<edge caller="main" p="bench/multiswe/run_multiswe.py:301" callee="parse_candidates" cp="bench/locbench/run_locbench.py:223"/>
<edge caller="main" p="bench/multiswe/run_multiswe.py:301" callee="norm_path" cp="bench/locbench/run_locbench.py:241"/>
<edge caller="main" p="bench/multiswe/run_multiswe.py:301" callee="ranked_files_from_candidates" cp="bench/locbench/run_locbench.py:245"/>
<edge caller="main" p="bench/multiswe/run_multiswe.py:301" callee="file_ranks" cp="bench/locbench/run_locbench.py:251"/>
</seam>
… [90 more display lines; full output is 12768 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --mermaid`

*Module (directory) dependency graph as a Mermaid diagram.*

`````
%% ripwire --mermaid: module (directory) dependency graph — node = dir (symbol count), edge = inter-module calls (>= 3). Render at mermaid.live.
flowchart LR
  subgraph sg0 ["src"]
    n105["src<br/>14852"]
    n106["src/infra<br/>1684"]
  end
  subgraph sg1 ["test"]
    n107["test<br/>6983"]
    n750["test/legochargefix<br/>546"]
    n472["test/fixtures/recallpassage<br/>314"]
    n491["test/fnslotcpp2<br/>285"]
    n913["test/lib<br/>253"]
    n712["test/ifacepeelfix/cpp<br/>206"]
    n1260["test/slotjoinfix<br/>182"]
    n1017["test/ownerhopfix/py/pkg<br/>158"]
    n408["test/expandmodefix<br/>151"]
    n410["test/expandsibsfix<br/>149"]
    n1223["test/rubyschemafix<br/>99"]
    n527["test/forbodyfoldfix/py<br/>98"]
  end
  n77["docs<br/>1266"]
  subgraph sg3 ["bench"]
    n63["bench/sectionfront<br/>1033"]
    n4["bench<br/>558"]
    n5["bench/agentloop<br/>331"]
    n50["bench/locbench/results/r5_pooling<br/>237"]
    n51["bench/locbench/results/r6_expansion<br/>187"]
    n60["bench/recalleval<br/>113"]
    n44["bench/locbench<br/>107"]
    n38["bench/headtohead/r3-headroom-2026-08-03<br/>102"]
… [23 more lines, 1626 bytes total]
`````

## `./build/ripwire . --owners`

*Bus-factor: recency-weighted author ownership per file.*

**wall time: 1.53s**

`````
<!-- ripwire owners schema=ripwire.owners/v1: recency-weighted author ownership (half-life 6mo): <f p= authors= bf= top= share=>; bf=1 = one person holds it. at=: commit+dirty+shallow. root=: p= relative to it. files=N: files analysed. files=N: single-author files folded into this one row; detail=1 lists each. -->
<owners schema="ripwire.owners/v1" files="4838" root="." at="6ace381eb">
<uniform authors="1" bf="1" share="1.00" files="3751"/>
<f p=".coderabbit.yaml" authors="2" bf="0" top="<author>" share="0.59"/>
<f p=".github/pargates-shard-weights.json" authors="3" bf="0" top="<author>" share="0.49"/>
<f p=".github/workflows/ci.yml" authors="6" bf="0" top="<author>" share="0.41"/>
<f p=".github/workflows/nightly.yml" authors="3" bf="0" top="<author>" share="0.73"/>
<f p=".github/workflows/release.yml" authors="3" bf="0" top="<author>" share="0.59"/>
<f p=".github/workflows/windows-package.yml" authors="2" bf="1" top="<author>" share="0.89"/>
<f p="AGENTS.md" authors="2" bf="0" top="<author>" share="0.71"/>
<f p="CHANGELOG.md" authors="18" bf="0" top="<author>" share="0.51"/>
<f p="CLAUDE.md" authors="5" bf="0" top="<author>" share="0.41"/>
<f p="CONTRIBUTING.md" authors="8" bf="0" top="<author>" share="0.36"/>
<f p="INSTALL.md" authors="3" bf="0" top="<author>" share="0.77"/>
<f p="README.md" authors="23" bf="0" top="<author>" share="0.50"/>
<f p="SECURITY.md" authors="3" bf="0" top="<author>" share="0.46"/>
<f p="THIRD_PARTY.md" authors="8" bf="0" top="<author>" share="0.41"/>
<f p="bench/ANSWERQUALITY.md" authors="2" bf="0" top="<author>" share="0.72"/>
<f p="bench/PROFILE.md" authors="5" bf="0" top="<author>" share="0.78"/>
<f p="bench/agentloop/README.md" authors="2" bf="1" top="<author>" share="0.89"/>
<f p="bench/agentloop/grade_answers.py" authors="4" bf="0" top="<author>" share="0.39"/>
<f p="bench/agentloop/run_agentloop.py" authors="3" bf="1" top="<author>" share="0.90"/>
<f p="bench/agentloop/run_editsuite.py" authors="2" bf="0" top="<author>" share="0.80"/>
<f p="bench/arb/run_arb.py" authors="2" bf="0" top="<author>" share="0.65"/>
<f p="bench/capsweep/capsweep.py" authors="3" bf="0" top="<author>" share="0.78"/>
<f p="bench/mine_traces.py" authors="2" bf="0" top="<author>" share="0.72"/>
<f p="bench/representative_perfgate.sh" authors="3" bf="0" top="<author>" share="0.68"/>
<f p="bench/roundc-h2h/derive_questions.py" authors="2" bf="0" top="<author>" share="0.56"/>
<f p="bench/routing_ab_report.py" authors="2" bf="0" top="<author>" share="0.63"/>
<f p="bench/scip_match_diag.py" authors="2" bf="0" top="<author>" share="0.51"/>
… [1061 more display lines; full output is 118826 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --dead-code=src`

*Internal functions with no caller found in the index — a name-based graph reading, not a confidence score. NOTE the filter is a path-COMPONENT match: 'src' matches any .../src/... segment; use ./src to pin the root directory.*

**wall time: 2.36s**

`````
<!-- ripwire dead-code schema=ripwire.dead-code/v1: internal-linkage functions with no caller found in the index (not a confidence score): <d n= t= p= l=>; filter= path component. window: shown= total= (capped=1 cut). counts_floor=1: every count is a FLOOR, never a total. graph_ambiguous=/graph_unresolved=: resolver gauge. graph_unindexed=N: N files no grammar could read (the map header's unindexed=); their calls raise neither gauge. value-ref-excluded=N: internal functions kept off because a table, field or argument in another function or at file scope holds them (matched by name, not a proven call); a floor. root=: p= relative to it. evidence=: the rule every row met, internal linkage and no caller in the index; verify before deleting. register-macro-excluded=N: symbols skipped as self-registering test/bench macros (TEST, BENCHMARK...) or Rust #[test]; a floor. exported linkage=exported evidence=no-non-test-caller: PUBLIC free functions of the filtered files with no non-test caller in the graph, <e> rows after d/to; not dead, not in count=, code outside the tree may call them (zero means none found here); total= found, shown= printed (capped=1 rows cut), files= read of files_total= filtered files holding a non-internal free function with no non-test caller (first by path; total=0 can follow), unseen=N a floor on text files unread, unseen_by= the cap or failure behind each, extra=skipped verdicts fixed by indexed files so unindexed ones unread (counts, at= are floors). e n= t= p= l= v=unused no mention in any text file under the root outside its def (prose docs not read)|test-only only tests|file-only same-file words only|unknown why= names what may reach it: string (__all__, getattr, a registry key)|value|framework (decorator, hook)|import (re-export)|barrel|api|name|by-name|declined|built-name|dispatch|members|manifest|in-file|unimported|unseen; tests= text= str= imp= same= word counts, defs= overloads, at= sites to read. count=N: candidates meeting evidence= (a floor). -->
<dead-code schema="ripwire.dead-code/v1" count="1" evidence="internal-linkage+zero-callers" register-macro-excluded="0" value-ref-excluded="10" filter="src" root="." graph_ambiguous="3634" graph_unresolved="20069" graph_unindexed="313" counts_floor="1">
<d n="unused_helper" t="fn" p="test/archmetricsfix/src/orphan/util.cpp" l="1"/>
<exported linkage="exported" evidence="no-non-test-caller" total="85" shown="85" files="1" files_total="1" unseen="1" unseen_by="size=1,total=0,files=0,read=0,walk=0">
<e n="Unique" t="cls" p="src/infra/os_win32.cpp" l="85" v="unknown" defs="3" why="name,members,unseen" text="7" same="13" at="src/pincensus.h:57,src/pincensus.h:83"/>
<e n="StreamLock" t="cls" p="src/infra/os_win32.cpp" l="205" v="unknown" defs="2" why="unseen" same="6"/>
<e n="NativePath" t="cls" p="src/infra/os_win32.cpp" l="370" v="unknown" defs="2" why="members,unseen" tests="1" same="14"/>
<e n="SocketTable" t="cls" p="src/infra/os_win32.cpp" l="425" v="unknown" defs="2" why="unseen" same="5"/>
<e n="WinsockSession" t="cls" p="src/infra/os_win32.cpp" l="439" v="unknown" defs="2" why="members,unseen" same="6"/>
<e n="open" t="fn" p="src/infra/os_win32.cpp" l="1003" v="unknown" defs="2" why="name,declined,string,manifest,unseen" tests="2295" text="1337" str="62" at=".coderabbit.yaml:4,.coderabbit.yaml:15"/>
<e n="openat" t="fn" p="src/infra/os_win32.cpp" l="1023" v="unknown" why="name,unseen" tests="12" text="5" at="src/infra/os.h:180,src/infra/os.h:180"/>
<e n="read" t="fn" p="src/infra/os_win32.cpp" l="1075" v="unknown" why="name,string,manifest,unseen" tests="3305" text="2731" str="136" same="2" at=".coderabbit.yaml:32,.github/workflows/ci.yml:71"/>
<e n="pread" t="fn" p="src/infra/os_win32.cpp" l="1087" v="unknown" why="name,built-name,unseen" tests="1" text="5" at="src/infra/os.h:184,src/infra/os.h:184"/>
<e n="fstat" t="fn" p="src/infra/os_win32.cpp" l="1106" v="unknown" why="name,unseen" tests="13" text="14" at="src/docparse.h:3,src/docparse.h:341"/>
<e n="stat" t="fn" p="src/infra/os_win32.cpp" l="1122" v="unknown" why="name,string,unseen" tests="101" text="170" str="5" at=".github/workflows/ci.yml:868,bench/agentloop/run_agentloop.py:640"/>
<e n="lstat" t="fn" p="src/infra/os_win32.cpp" l="1126" v="unknown" why="name,unseen" tests="11" text="11" at="src/editplan.h:5,src/editplan.h:258"/>
<e n="dup" t="fn" p="src/infra/os_win32.cpp" l="1170" v="unknown" why="name,string,unseen" tests="300" text="45" str="3" at="bench/capsweep/capsweep.py:862,bench/capsweep/capsweep.py:865"/>
<e n="dup_cloexec" t="fn" p="src/infra/os_win32.cpp" l="1171" v="unknown" why="name,unseen" text="3" at="src/infra/os.h:192,src/infra/os.h:1213"/>
<e n="write_nosigpipe" t="fn" p="src/infra/os_win32.cpp" l="1172" v="unknown" why="name,unseen" text="3" at="src/helpdeadline.h:532,src/infra/os.h:196"/>
<e n="dup2" t="fn" p="src/infra/os_win32.cpp" l="1173" v="unknown" why="name,unseen" tests="11" text="14" at="src/helpdeadline.h:392,src/helpdeadline.h:393"/>
<e n="ftruncate" t="fn" p="src/infra/os_win32.cpp" l="1175" v="unknown" why="name,string,unseen" tests="3" text="3" str="1" at="src/defectshape.h:4108,src/infra/os.h:204"/>
<e n="fsync" t="fn" p="src/infra/os_win32.cpp" l="1181" v="unknown" why="name,unseen" tests="1" text="8" at="present/deck5_ripwire_build.js:1629,present/ripwire-showcase.pptx:692"/>
<e n="fchmod" t="fn" p="src/infra/os_win32.cpp" l="1184" v="unknown" why="name,unseen" tests="2" text="4" at="src/infra/os.h:206,src/infra/os.h:206"/>
<e n="flock" t="fn" p="src/infra/os_win32.cpp" l="1206" v="unknown" why="name,string,unseen" tests="13" text="12" str="1" at="src/helpdeadline.h:250,src/helpdeadline.h:329"/>
<e n="pipe_cloexec" t="fn" p="src/infra/os_win32.cpp" l="1229" v="unknown" why="name,unseen" tests="4" text="4" at="src/helpdeadline.h:371,src/infra/os.h:212"/>
<e n="poll" t="fn" p="src/infra/os_win32.cpp" l="1234" v="unknown" why="name,unseen" tests="82" text="69" at="bench/recalleval/run_depthinvariance.py:134,bench/recalleval/run_depthinvariance.py:135"/>
<e n="fdopen" t="fn" p="src/infra/os_win32.cpp" l="1269" v="unknown" why="name,string,unseen" tests="22" text="17" str="1" at="src/defectshape.h:4239,src/docparse.h:3"/>
<e n="fileno" t="fn" p="src/infra/os_win32.cpp" l="1270" v="unknown" why="name,unseen" tests="4" text="9" at="src/docparse.h:341,src/infra/os.h:230"/>
<e n="getline" t="fn" p="src/infra/os_win32.cpp" l="1276" v="unknown" why="name,string,unseen" tests="14" text="20" str="1" at="bench/bench_fixedstr.cpp:16,src/arch.h:520"/>
<e n="memoryStreamMutex" t="fn" p="src/infra/os_win32.cpp" l="1330" v="unknown" why="unseen" same="3"/>
… [61 more display lines; full output is 16552 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --exercises=test/regression.sh`

*Which symbols a TEST FILE exercises — the reverse direction of --affected.*

`````
<!-- ripwire exercises schema=ripwire.exercises/v1: NON-TEST symbols this test transitively calls (what it covers): <t p= run=>; the inverse of affected. window: shown= capped= (capped=1 cut). seed_files_capped=: 1 = cut. counts_floor=1: every count is a FLOOR, never a total. graph_ambiguous=/graph_unresolved=: resolver gauge. graph_unindexed=N: N files no grammar could read (the map header's unindexed=); their calls raise neither gauge. root=: p= relative to it. pr_iters=N: PageRank iterations. seed_files=N: test files the pattern matched. shown_seed_files=N: of those, printed as t rows (at most 20). test_symbols=N: symbols in those test files, the walk's seeds. reaches=N: non-test symbols the tests transitively call (the s rows' total). harness=script|mixed: seeds include shell gates, whose subprocess coverage is unseen; note= says so. of=: the test file pattern given. -->
<exercises schema="ripwire.exercises/v1" of="test/regression.sh" seed_files="1" shown_seed_files="1" seed_files_capped="0" test_symbols="4" reaches="0" harness="script" note="a shell gate invokes the compiled binary as a subprocess; script-to-binary edges are not modelled, so reaches= counts call-gr … [line truncated: 189 more bytes on this line]
<t p="test/regression.sh" run="bash test/regression.sh"/>
</exercises>
`````

## `./build/ripwire . --community=0`

*Drill into ONE call-graph community by id — the drill= the --communities output itself advertises.*

`````
<!-- ripwire community schema=ripwire.community/v1: ONE module id=: <member t= n= p=> ranked members, its <bridge> edges; size= the TRUE count; dir= its members' most common directory (a top-level file's own path); label= dir::name@file:line:byte of its top fan-in member (non-accessors first) [up to 3 top name verbs]; bridges= modules a call edge joins to it; partition= module count incl. singletons (ids 0..partition-1); modules= those of 2+ symbols; shown_bridges= <bridge> rows listed. window: shown= capped= (capped=1 cut). bridges_capped=: 1 = cut. counts_floor=1: every count is a FLOOR, never a total. graph_ambiguous=/graph_unresolved=: resolver gauge. graph_unindexed=N: N files no grammar could read (the map header's unindexed=); their calls raise neither gauge. root=: p= relative to it. pr_iters=N: PageRank iterations. -->
<community schema="ripwire.community/v1" id="0" size="1" dir=".coderabbit.yaml" label=".coderabbit.yaml::reviews@.coderabbit.yaml:12:928" bridges="0" shown_bridges="0" bridges_capped="0" partition="26139" modules="5170" shown="1" capped="0" pr_iters="40" root="." graph_ambiguous="3634" graph_unresol … [line truncated: 51 more bytes on this line]
<member t="sec" n="reviews" p=".coderabbit.yaml:12"/>
</community>
`````

## `./build/ripwire . --quality-delta`

*The regression-free answer on a clone whose ledger holds stale acknowledgements (its HEAD's own history plus one demo row keyed to a finding that no longer measures as worse): the verdict-only document, every stale row collapsed to stale= and stale_by_kind=, with stale_next= naming the call below. Recorded in a throwaway clean clone so the contrast is structural — not a race with the release checkout's drift — and every regeneration on every machine sees the same pair.*

**wall time: 32.56s**

`````
<!-- ripwire quality-delta schema=ripwire.quality-delta/v1: only what the change made WORSE vs baseline=: regressions= minor= gating=; <r kind= sym= p= was= now= gating= bar=>, <sa> acked. value-ref-excluded=N: internal functions kept off because a table, field or argument in another function or at file scope holds them (matched by name, not a proven call); a floor. at=: commit+dirty+shallow. stale=N: ack ledger rows whose target no longer applies (sa rows); never gating. stale_by_kind=: stale= split by ack kind (kind:N,...); the sa rows are collapsed. stale_next=: the call printing the sa rows and the full header. preexisting-worse=N: regressions on symbols that existed at baseline; they gate when major. new-symbol=N: NEW code; new-symbol rows never gate, except defect-shape format-arity or a ceiling= row. register-macro-excluded=N: symbols skipped: self-registering test/bench macros or Rust #[test]; a floor. declined-call-excluded=N: symbols kept out of dead-code only because a declined call may mean them; a floor. api-new-surface=N: new PUBLIC symbols; a count, never gates, not in regressions=. renames=/rename_window_commits=: git rename pairs read over that many commits, to re-file baseline and acks. acked_by_rename=/acked_by_content=: acked= suppressions matched via git renames / an equal body hash. renames_window_truncated=1: history is deeper than the rename window, older renames unread. acked=N: findings suppressed by the ack ledger, listed as sa rows; never gating. -->
<quality-delta schema="ripwire.quality-delta/v1" baseline="git-HEAD" regressions="0" minor="0" acked="0" stale="196" preexisting-worse="0" new-symbol="0" gating="0" register-macro-excluded="63" api-new-surface="0" at="6ace381eb+dirty" renames="68" rename_window_commits="400" acked_by_rename="0" acke … [line truncated: 298 more bytes on this line]
</quality-delta>
`````

stderr:

`````
ripwire: no ./.ripwire_quality_baseline — auto-comparing the working tree vs git HEAD (commit the baseline with --quality-baseline to pin it)
`````

## `./build/ripwire . --quality-delta --show-stale`

*The same run, the same clone, the folded rows printed back: each stale acknowledgement as an <sa kind= key= why=> row under the full header — the demo row included, and no quarter of the bytes saved by silence. Refused without --quality-delta.*

**wall time: 17.39s**

`````
<!-- ripwire quality-delta schema=ripwire.quality-delta/v1: only what the change made WORSE vs baseline=: regressions= minor= gating=; <r kind= sym= p= was= now= gating= bar=>, <sa> acked. value-ref-excluded=N: internal functions kept off because a table, field or argument in another function or at file scope holds them (matched by name, not a proven call); a floor. at=: commit+dirty+shallow. stale=N: ack ledger rows whose target no longer applies (sa rows); never gating. preexisting-worse=N: regressions on symbols that existed at baseline; they gate when major. new-symbol=N: NEW code; new-symbol rows never gate, except defect-shape format-arity or a ceiling= row. register-macro-excluded=N: symbols skipped: self-registering test/bench macros or Rust #[test]; a floor. declined-call-excluded=N: symbols kept out of dead-code only because a declined call may mean them; a floor. api-new-surface=N: new PUBLIC symbols; a count, never gates, not in regressions=. renames=/rename_window_commits=: git rename pairs read over that many commits, to re-file baseline and acks. acked_by_rename=/acked_by_content=: acked= suppressions matched via git renames / an equal body hash. renames_window_truncated=1: history is deeper than the rename window, older renames unread. acked=N: findings suppressed by the ack ledger, listed as sa rows; never gating. sa key=/why=: the stale ack's ledger hash / target-gone (names nothing now) or finding-gone (no longer fires). -->
<quality-delta schema="ripwire.quality-delta/v1" baseline="git-HEAD" regressions="0" minor="0" acked="0" stale="196" preexisting-worse="0" new-symbol="0" gating="0" register-macro-excluded="63" api-new-surface="0" at="6ace381eb+dirty" renames="68" rename_window_commits="400" acked_by_rename="0" acke … [line truncated: 99 more bytes on this line]
<sa kind="api-surface" key="0123456789abcdef" why="target-gone"/>
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
<sa kind="api-surface:new-symbol" key="26e3f9a6bff9ea57" why="target-gone"/>
<sa kind="api-surface:new-symbol" key="36e39c7ab0fc1686" why="target-gone"/>
<sa kind="api-surface:new-symbol" key="4bce64bd920de0c3" why="target-gone"/>
<sa kind="api-surface:new-symbol" key="61f0e361ef7dee27" why="target-gone"/>
<sa kind="api-surface:new-symbol" key="79625906f9f71ad0" why="target-gone"/>
<sa kind="api-surface:new-symbol" key="8ecb190954dce18a" why="target-gone"/>
<sa kind="api-surface:new-symbol" key="995375dfa4e63104" why="target-gone"/>
<sa kind="api-surface:new-symbol" key="ee71e4fffa361902" why="target-gone"/>
<sa kind="complexity" key="0001f7edbff929e5" why="finding-gone" sym="src/cli.h::rw::validateLegendModifier" p="src/cli.h:4828"/>
<sa kind="complexity" key="1aec4199f183ce56" why="finding-gone" sym="runLint" p="src/verbs_lint.h:2353"/>
… [169 more display lines; full output is 18801 bytes on 1 raw line(s)]
`````

stderr:

`````
ripwire: no ./.ripwire_quality_baseline — auto-comparing the working tree vs git HEAD (commit the baseline with --quality-baseline to pin it)
`````

## `./build/ripwire . --edit-check=rankGraphTeleport`

*Fast per-symbol post-edit contract check vs git HEAD (unchanged on a clean tree).*

**wall time: 19.14s**

`````
<!-- ripwire edit-check schema=ripwire.edit-check/v1: sym='s contract NOW vs HEAD: status=unchanged|new-symbol|contract-change; <c n= p= incompatible=1 sites_l=> callers. counts_floor=1: every count is a FLOOR, never a total. graph_ambiguous=/graph_unresolved=: resolver gauge. graph_unindexed=N: N files no grammar could read (the map header's unindexed=); their calls raise neither gauge. est_tokens=: price as emitted (an upper bound under compact). at=: commit+dirty+shallow. root=: p= relative to it. next=: the one pasteable follow-up. defs=N: overloads at this site (same file, scope, name) folded into one contract; params compared by MAX. callers=N: callers of sym= (the c rows' total; a floor). t=: sym='s kind (fn|cls|...). -->
<edit-check schema="ripwire.edit-check/v1" sym="rankGraphTeleport" t="fn" p="src/graph.h:14619" status="unchanged" defs="1" callers="7" incompatible="0" at="6ace381eb" graph_ambiguous="3634" graph_unresolved="20069" graph_unindexed="313" counts_floor="1" root="." next="--test-gate=src/graph.h" est_t … [line truncated: 12 more bytes on this line]
<c n="runEval" p="src/eval.h:171"/>
<c n="rankGraph" p="src/graph.h:14662"/>
<c n="anchoredLexicalRank" p="src/graph.h:15331"/>
<c n="churnDecayRanking" p="src/main.cpp:1432"/>
<c n="churnRankedGraph" p="src/main.cpp:1471"/>
<c n="runDefaultMap" p="src/main.cpp:1758"/>
<c n="getIndex" p="src/mcpindex.h:1224"/>
</edit-check>
`````

stderr:

`````
ripwire: cache <tmp>: over its 2048 MiB budget — evicted 87 blob(s) of other roots or other ripwire builds (this build's blobs for this root are kept)
`````

## `./build/ripwire . --pr-context`

*No-LLM review-evidence bundle for the working-tree diff (clean tree = empty).*

`````
<!-- ripwire pr-context schema=ripwire.pr-context/v1: review bundle per changed file vs base=: symbols, callers, blast radius, tests, owners. counts_floor=1: every count is a FLOOR, never a total. graph_ambiguous=/graph_unresolved=: resolver gauge. graph_unindexed=N: N files no grammar could read (the map header's unindexed=); their calls raise neither gauge. est_tokens=: price as emitted (an upper bound under compact). at=: commit+dirty+shallow. root=: p= relative to it. truncated=: what the trim ladder dropped to fit budget_tokens= (budget-floor-exceeded: still over). direction=: side reviewed: worktree-since-head, head-since-fork or head-since-ref-tip. skipped_mode_only=N: mode-only (chmod) diffs left out of the changed files; renames stay in. trim_level=0-4: trim ladder step taken to fit budget_tokens= (0 none, 4 counts only); raise token-budget. budget_default=1: the default 8000-token budget applied (no token-budget or max-tokens given). files=N: changed files in the diff (shown= of them listed). -->
<pr-context schema="ripwire.pr-context/v1" base="working-tree" root="." direction="worktree-since-head" files="0" skipped_mode_only="0" budget_tokens="8000" est_tokens="584" trim_level="0" truncated="none" budget_default="1" at="6ace381eb" graph_ambiguous="3634" graph_unresolved="20069" graph_uninde … [line truncated: 27 more bytes on this line]
<!-- no changed files in the index (clean tree, or the diff touched only non-indexed files) -->
</pr-context>
`````

## `./build/ripwire . --pr-context=HEAD~1`

*The BASEREF form: diffed against merge-base(BASEREF, HEAD), never the ref tip — here the previous commit on the current line (a ref with NO merge base falls back to a disclosed two-dot diff: anchor="ref-tip-two-dot").*

**wall time: 2.77s**

`````
<!-- ripwire pr-context schema=ripwire.pr-context/v1: review bundle per changed file vs base=: symbols, callers, blast radius, tests, owners. window: shown= capped= (capped=1 cut). counts_floor=1: every count is a FLOOR, never a total. graph_ambiguous=/graph_unresolved=: resolver gauge. graph_unindexed=N: N files no grammar could read (the map header's unindexed=); their calls raise neither gauge. est_tokens=: price as emitted (an upper bound under compact). at=: commit+dirty+shallow. root=: p= relative to it. truncated=: what the trim ladder dropped to fit budget_tokens= (budget-floor-exceeded: still over). anchor=merge-base: diffed from merge base(base, HEAD); ref-tip-two-dot = no merge base, two-dot view. base_sha=: the merge-base commit (9 hex) the diff is anchored at. base_moved=N: paths the base ref changed since the fork that this work never touched; excluded. direction=: side reviewed: worktree-since-head, head-since-fork or head-since-ref-tip. skipped_mode_only=N: mode-only (chmod) diffs left out of the changed files; renames stay in. trim_level=0-4: trim ladder step taken to fit budget_tokens= (0 none, 4 counts only); raise token-budget. budget_default=1: the default 8000-token budget applied (no token-budget or max-tokens given). commits=N: this file's commits in window=; 0 = the window could not look, not no partners. partners=N: co-change partners NOT in the diff; rows are its top shown= (the cochange verb lists all). dependents=N: distinct symbols transitively calling this file's symbols (reach set, a FLOOR). files_other=N: non-changed files among those reached; the f rows are its top shown=. authors=N: distinct authors of this file (0 = no git data). bf=1: one author holds over 80% of recency-weighted commits (bus-factor risk). no-ref-work note=: the base ref's tip is the merge base, so it has no work of its own; rows are HEAD's. files=N: changed files in the diff (shown= of them listed). file symbols=: indexed symbols in that changed file. changed-symbols count= / tests count=: that section's full count (shown= of it listed). tests count=: test files reaching this file (shown= of them listed). impact files=: files holding the transitive callers (dependents=). impactf deps=: transitive callers in that file. author email=/share=: a committer of this file / its fraction of the recency-weighted commits. partner deg=: of this file's commits in window=, the fraction that partner shares. partner surprising=1: co-changes with no transitive static dependency either way (hidden coupling). partner dep_capable=0: a side cannot carry a static dependency, so surprising= is undefined. s callers=N: direct callers of that changed symbol; caller rows are its top shown= (callers verb: all). changed-symbols sections=N: doc headings folded into count=, no row each; count minus sections = rows. s t= n= / caller t= n=: a changed symbol's / one of its callers' kind and name. <file-scope> (t=modscope): a file's MODULE SCOPE — where a top-level call and an anonymous callback body's calls live; a CALLER, never a callee, with no body to expand. -->
<pr-context schema="ripwire.pr-context/v1" base="HEAD~1" root="." anchor="merge-base" base_sha="c263353bd" base_moved="0" direction="head-since-fork" files="4" skipped_mode_only="0" budget_tokens="8000" est_tokens="4347" trim_level="0" truncated="none" budget_default="1" at="6ace381eb" graph_ambiguo … [line truncated: 74 more bytes on this line]
<no-ref-work note="HEAD~1 tip == merge-base, so that ref has no divergent work of its own; this bundle is HEAD's work since the fork. For the ref's OWN diff see merge-scout or stray-content"/>
<file p="docs/COMMANDS.md" symbols="197">
<impact dependents="7" files="5" files_other="5" shown="5" capped="0">
<f p="README.md" deps="3"/>
<f p="docs/LINEAGE.md" deps="1"/>
<f p="docs/QUALITY_PANEL.md" deps="1"/>
<f p="docs/README.md" deps="1"/>
<f p="docs/REFERENCE_GUIDE.md" deps="1"/>
</impact>
<tests count="0" shown="0" capped="0">
</tests>
<changed-symbols count="197" sections="197">
</changed-symbols>
<cochange window="18mo@HEAD" commits="871" partners="223" shown="12" capped="1">
<partner p="src/cli.h" deg="0.47" dep_capable="0"/>
<partner p="README.md" deg="0.28" dep_capable="0"/>
<partner p="test/regression.sh" deg="0.26" dep_capable="0"/>
<partner p="docs/EVALS.md" deg="0.22" dep_capable="0"/>
<partner p="src/compactlegend.h" deg="0.20" dep_capable="0"/>
<partner p="CHANGELOG.md" deg="0.19" dep_capable="0"/>
<partner p="src/main.cpp" deg="0.16" dep_capable="0"/>
<partner p="src/mcpverbs.h" deg="0.14" dep_capable="0"/>
<partner p="present/deck5_ripwire_build.js" deg="0.13" dep_capable="0"/>
<partner p="src/serialize.h" deg="0.10" dep_capable="0"/>
<partner p="src/quality.h" deg="0.09" dep_capable="0"/>
<partner p="docs/LIMITS.md" deg="0.09" dep_capable="0"/>
</cochange>
<owners authors="23" bf="0" shown="5" capped="1">
… [122 more display lines; full output is 10866 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --merge-scout=HEAD~2,HEAD~1`

*Pairwise cross-arm conflict sites + suggested landing order (any committish sharing a merge base with HEAD works as an arm; one that does not is reported ok="0", never compared).*

**wall time: 23.62s**

`````
<!-- ripwire merge-scout schema=ripwire.merge-scout/v1: cross-branch overlap of arms= refs: <arm ref= base= changed= head_conflicts=>, <pair a= b= conflicts= risks=>, <landing order=>. at=: commit+dirty+shallow. head=: the HEAD commit, bare 9-hex sha (at= adds +dirty). ok=1 on an arm row means the comparison RAN, so changed=/head_conflicts= are real and may legitimately be 0 (an empty but materialized tree is a real index); ok=0 means it did not run at all. no-work note=: arm compared and has no divergent work vs its merge base, so no landing slot. -->
<merge-scout schema="ripwire.merge-scout/v1" arms="2" head="6ace381eb" at="6ace381eb">
<arm ref="HEAD~2" base="156bedf9a" ok="1" changed="0" head_conflicts="0">
<no-work note="no divergent work vs merge-base — see --stray-content"/>
</arm>
<arm ref="HEAD~1" base="c263353bd" ok="1" changed="0" head_conflicts="0">
<no-work note="no divergent work vs merge-base — see --stray-content"/>
</arm>
<pair a="HEAD~2" b="HEAD~1" conflicts="0" risks="0"/>
<landing order=""/>
</merge-scout>
`````

## `./build/ripwire . --stray-content=lane/`

*Which refs of the `lane/` ref family still hold divergent authored work vs HEAD, with verdicts.*

**wall time: 16.63s**

`````
<!-- ripwire stray-content schema=ripwire.stray-content/v1: per local ref, lines/symbols NOT in HEAD: <ref ok= v= base= stray=>; v=unknown = no merge base. at=: commit+dirty+shallow. head=: the HEAD commit, bare 9-hex sha (at= adds +dirty). head_ref=: HEAD's branch (HEAD when detached); that branch itself is not scanned. refs=N: local branches scanned (refs/heads only); unmerged + superseded + merged + unknown = refs. blobs=N: distinct git blobs read for the sweep. unmerged=N: refs whose authored work the live line genuinely lacks. superseded=N: refs whose work the live line re-implemented (removed the same base code). merged=N: refs whose work HEAD already has; omitted from the rows. name=: the local branch. tip=: the branch tip commit (9 hex). date=: the tip's committer date, YYYY-MM-DD. files=N: files with stray lines; rows capped at 12, a more element counts the rest (detail=1 lists all). ref superseded=N>: of this ref's stray= lines, those in files the live line re-implemented. authored=N: lines this ref authored in the file vs its merge base. del=N: base lines this ref removed (0 = pure addition). redone=N: of del=, the base lines HEAD removed too (the supersession evidence). sim=: minhash containment, 0 to 1, of the ref's blob in HEAD's (pure-addition evidence). head-touched=1: the live line changed this path since the merge base. more files=N: N more file rows of this ref withheld; shown + N = the ref's files=; detail=1 lists all. unknown=N: refs that could not be analysed (v=unknown, e.g. no merge base); never counted merged. file p=: the stray file, repo-relative. -->
<stray-content schema="ripwire.stray-content/v1" head="6ace381eb" head_ref="integration/train-ge2" refs="490" blobs="2126" unmerged="61" superseded="24" merged="405" unknown="0" filter="lane/" at="6ace381eb">
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
<file p="src/slice.h" v="unmerged" stray="132" authored="172" del="6" redone="0" sim="0.96" head-touched="1"/>
<file p="bench/slice/results/arise_line_rank_prereg/RESULTS.md" v="unmerged" stray="126" authored="126" del="0" redone="0" sim="0.00" head-touched="0"/>
<file p="bench/slice/results/arise_line_rank_prereg/scorer-summary.json" v="unmerged" stray="82" authored="82" del="0" redone="0" sim="0.00" head-touched="0"/>
<more files="6"/>
</ref>
<ref name="lane/margin-rescore" tip="9ffd3628c" date="2026-09-23" base="755f9026f" ok="1" v="unmerged" stray="13921" files="13" superseded="1">
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
… [792 more display lines; full output is 90101 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --stray-content=fix/`

*A second selection, the `fix/` ref family, picked at capture time from the refs this checkout really has and never the selection above: merged refs are OMITTED from the rows and counted in merged=; refs sharing no merge base with HEAD (a shallow clone, or a pre-rewrite history) land in unknown= with ok="0" — the counters always reconcile against refs=.*

**wall time: 1.63s**

`````
<!-- ripwire stray-content schema=ripwire.stray-content/v1: per local ref, lines/symbols NOT in HEAD: <ref ok= v= base= stray=>; v=unknown = no merge base. at=: commit+dirty+shallow. head=: the HEAD commit, bare 9-hex sha (at= adds +dirty). head_ref=: HEAD's branch (HEAD when detached); that branch itself is not scanned. refs=N: local branches scanned (refs/heads only); unmerged + superseded + merged + unknown = refs. blobs=N: distinct git blobs read for the sweep. unmerged=N: refs whose authored work the live line genuinely lacks. superseded=N: refs whose work the live line re-implemented (removed the same base code). merged=N: refs whose work HEAD already has; omitted from the rows. unknown=N: refs that could not be analysed (v=unknown, e.g. no merge base); never counted merged. -->
<stray-content schema="ripwire.stray-content/v1" head="6ace381eb" head_ref="integration/train-ge2" refs="1" blobs="0" unmerged="0" superseded="0" merged="1" unknown="0" filter="fix/" at="6ace381eb">
</stray-content>
`````

## `./build/ripwire . --stray-content=lane/ --plan`

*Select the genuinely-unmerged refs of the `lane/` ref family and feed them to merge-scout for a landing order (a fully merged selection yields an empty landing set — still a measurement, disclosed on the root).*

**wall time: 52.68s**

`````
<!-- ripwire landing-plan schema=ripwire.landing-plan/v1: stranded-work landing order across refs, fewest conflicts first. at=: commit+dirty+shallow. -->
<landing-plan schema="ripwire.landing-plan/v1" head="6ace381eb" refs="490" unmerged="61" superseded="24" merged="405" undetermined="0" scouted="1" bounded="60" scout-ok="1" at="6ace381eb">
<ref name="lane/arise-result" v="unmerged" stray="16331" files="18" scouted="1"/>
<ref name="lane/margin-rescore" v="unmerged" stray="13921" files="13" scouted="0"/>
<ref name="lane/recv-xfile" v="unmerged" stray="9249" files="34" scouted="0"/>
<ref name="lane/py-local-bind" v="unmerged" stray="7079" files="8" scouted="0"/>
<ref name="lane/served-syms-result" v="unmerged" stray="6346" files="9" scouted="0"/>
<ref name="lane/qual-ns-call-bind" v="unmerged" stray="3360" files="36" scouted="0"/>
<ref name="lane/orient-narrow-v3" v="unmerged" stray="3273" files="46" scouted="0"/>
<ref name="lane/for-howitworks-067" v="unmerged" stray="3247" files="39" scouted="0"/>
<ref name="lane/m1-lookback-harness" v="unmerged" stray="3164" files="14" scouted="0"/>
<ref name="lane/import-proved-splits" v="unmerged" stray="2718" files="31" scouted="0"/>
<ref name="lane/orient-map-067" v="unmerged" stray="2475" files="40" scouted="0"/>
<ref name="lane/parse-budget-det" v="unmerged" stray="2395" files="64" scouted="0"/>
<ref name="lane/xs-1119-d2-pin" v="unmerged" stray="2250" files="27" scouted="0"/>
<ref name="lane/small-edges-1118" v="unmerged" stray="2181" files="6" scouted="0"/>
<ref name="lane/go-cpp-edges" v="unmerged" stray="2146" files="6" scouted="0"/>
<ref name="lane/served-syms-prereg" v="unmerged" stray="2135" files="5" scouted="0"/>
<ref name="lane/edge-strays-1118" v="unmerged" stray="2094" files="17" scouted="0"/>
<ref name="lane/crossctx-external-prereg" v="unmerged" stray="2055" files="7" scouted="0"/>
<ref name="lane/no-skip-ingest" v="unmerged" stray="1860" files="52" scouted="0"/>
<ref name="lane/for-noise" v="unmerged" stray="1820" files="47" scouted="0"/>
<ref name="lane/std-namesake" v="unmerged" stray="1753" files="9" scouted="0"/>
<ref name="lane/for-tonly" v="unmerged" stray="1728" files="11" scouted="0"/>
<ref name="lane/arise-line-ranking" v="unmerged" stray="1538" files="7" scouted="0"/>
<ref name="lane/for-noise-body-slot" v="unmerged" stray="1524" files="39" scouted="0"/>
<ref name="lane/row-features-2" v="unmerged" stray="1218" files="11" scouted="0"/>
<ref name="lane/research-abstention" v="unmerged" stray="899" files="3" scouted="0"/>
<ref name="lane/agent-trap" v="unmerged" stray="859" files="13" scouted="0"/>
<ref name="lane/row-features" v="unmerged" stray="840" files="10" scouted="0"/>
… [281 more display lines; full output is 31015 bytes on 1 raw line(s)]
`````

stderr:

`````
ripwire: warning: --plan scouted 1 of 61 unmerged branches for conflicts and landing order (limit: 12 arms, and 8192 indexed files across the arms); pass --detail=1 to scout every unmerged branch
`````

## `./build/ripwire . --stray-content=zzzz-no-such-ref --plan`

*A --plan filter that selects NO ref REFUSES (exit 1) naming the substring — before the wave-3 close this fell through to the '>512 refs match' sentence, and --abi under the same filter answered an empty measurement at exit 0.*

**exit code: 1** — **wall time: 6.94s**

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

**exit code: 2** — **wall time: 60.29s**

`````
<!-- ripwire abi schema=ripwire.abi/v1: cross-branch ABI-break gate: each local branch's structs on paths it authored (its diff from its merge base with HEAD), laid out lexically, compared with HEAD's; a match is omitted; exit 2 on a drift. head_ref= HEAD's branch, refs= branches read, candidates= structs HEAD declares and locates, compared= sites modelled on both sides, blobs= git blobs read; dropped= listed rows past the 12-per-ref cap; head_only= sites on paths only HEAD changed (out of scope); unmodelable= sites skipped: HEAD's copy has no model; unrelated= refs with no merge base, never compared, also in quiet=; broken_refs= refs with a drift; quiet= refs with no row (none differed or none compared); excluded_refs= refs with unlisted kinds only. window: shown= capped= (capped=1 cut). at=: commit+dirty+shallow. root=: p= relative to it. ref name= tip= date=: a branch with rows, its tip commit and date; shown=/capped=/head_only= and kind counts are its own. struct n= p= l= kind= head_size=: a struct, its file and line at HEAD, sizeof there. kind=drift: the byte contract differs (the kind that exits 2); unknown: the ref's copy could not be modelled, never read as same; absent: the ref does not define it at that path. drift= unknown= absent= count them on abi and ref; each row is on one kind count (absent at 0): their sum is the row total. ref_size= size_delta=: sizeof on the ref and its distance from head_size=, only where the ref's copy was sized; size_delta=0 is the same size, not the same layout. d n= a= b=: a differing field as type@offset at HEAD (a=) and on the ref (b=), or absent. ref_caveat k= d=: why the ref's copy is unmodelled: kind, detail. head_caveat k= d=: a limit of HEAD's own model of the struct: kind, detail. head-moved=N: the ref's copy equals its merge base's, so HEAD changed; counted, listed under detail=1. -->
<abi schema="ripwire.abi/v1" head_ref="integration/train-ge2" refs="490" candidates="3024" compared="11685" blobs="868" shown="45" capped="0" dropped="0" head_only="1083318" unmodelable="4087" unrelated="0" broken_refs="20" quiet="414" excluded_refs="49" at="6ace381eb" drift="33" unknown="9" absent= … [line truncated: 31 more bytes on this line]
<ref name="lane/for-tonly" tip="07f6c870d" date="2026-10-29" shown="4" capped="0" head_only="2245" drift="4" head-moved="38">
<struct n="ForLensJsonInputs" p="src/verbs_for.h" l="464" kind="drift" head_size="232" ref_size="216" size_delta="16">
<d n="graph" a="const rw::Graph*@208" b="absent"/>
<d n="signaturesOnly" a="bool@216" b="absent"/>
<d n="tailTermTieRank" a="const std::vector&lt;float&gt;*@224" b="absent"/>
<d n="testOnlyCallers" a="absent" b="const std::vector&lt;std::uint8_t&gt;*@208"/>
<head_caveat k="reference-member" d="ing: a reference member&apos;s storage is unspecified"/>
<ref_caveat k="reference-member" d="ing: a reference member&apos;s storage is unspecified"/>
</struct>
<struct n="SigRowSpelling" p="src/serialize.h" l="6170" kind="drift" head_size="2" ref_size="16" size_delta="14">
<d n="foldRepeatedText" a="bool@1" b="absent"/>
<d n="testOnlyCallers" a="absent" b="const std::vector&lt;std::uint8_t&gt;*@8"/>
</struct>
<struct n="ForLensHeaderParts" p="src/verbs_for.h" l="573" kind="drift" head_size="280" ref_size="272" size_delta="8">
<d n="tailCodeFirst" a="bool@260" b="absent"/>
<d n="tailWide" a="bool@261" b="absent"/>
<d n="hopsCallsNextPresent" a="bool@262" b="bool@260"/>
<d n="bodyFoldPresent" a="bool@263" b="bool@261"/>
<d n="foldFollowPresent" a="bool@264" b="bool@262"/>
<d n="memberNamesPresent" a="bool@265" b="bool@263"/>
<d n="initSlotsPresent" a="bool@266" b="bool@264"/>
<d n="regPresent" a="bool@267" b="absent"/>
<d n="slotJoinPresent" a="bool@268" b="bool@265"/>
<d n="slotNamePresent" a="bool@269" b="bool@266"/>
<d n="ctorHopPresent" a="bool@270" b="bool@267"/>
<d n="callerHopPresent" a="bool@271" b="bool@268"/>
<d n="callerHopRanked" a="bool@272" b="bool@269"/>
<d n="callerHopSubject" a="bool@273" b="absent"/>
… [552 more display lines; full output is 43119 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --whereis=rankGraphTeleport`

*Which ref's tree defines or mentions SYM — HEAD first, then every local branch. The default lists the kind="def" rows (here the first 60, most on branches, each carrying tip= and date=) and counts the references in <refs count= next=>: on this symbol HEAD's references would fill the 60-row cap before the branch definitions arrive, so the whole list (below) shows fewer definitions, and the default serves the page that shows more of them, whatever its bytes.*

**wall time: 44.93s**

`````
<!-- ripwire whereis schema=ripwire.whereis/v1: every LOCAL ref whose tree holds sym= (refs_scanned=, blobs=), HEAD first: <hit ref= tip= date= p= l= kind= t=>. window: shown= total= capped= has_more= next_offset= offset= limit= (capped=1 cut; next_offset= pastes as offset=). at=: commit+dirty+shallow. next=: the one pasteable follow-up. refs_omitted=K: past the ref window (512 refs; whereis: 2097152 tree entries) the newest refs by committer date were read; K older local branches were not, in no count or row (a ref-name SUBSTR filter picks which; detail=1 reads all). hits=N: occurrences in HEAD plus every scanned local ref's full tree (the total rows). on-head=1|0: whether HEAD's tree holds it; 0 beside hits = it lives only on a branch. head_labels=index: HEAD kind= from the parsed index; lexical: text heuristic. ref_labels=parsed: another ref's kind= from the index's own tags parse of its blob (one per blob and path; HEAD's own blob takes HEAD's labels); a blob with no line a loose lexical test calls worth parsing is not parsed and its rows read ref; kind=text: such a line no parse read, never a def. unparsed blobs=N: other refs' blobs holding a line worth parsing that no parse read (past the runaway guard, or the parser could not finish); those lines read kind=text; next= lifts the guard. unparsed rows=N: the kind=text rows those blobs gave. hit t_bytes=N: t= previews an N-byte line (over 300 B): 200 B at most, its first bytes cut on a UTF-8 boundary plus an ellipsis. t_cut rows=N: rows of this page whose t= is a preview (each carries t_bytes=); next= replays this page (same listing, window, rows) with every line whole. more hits=N: rows after this page; page on with offset=next_offset. head_date=: a hit without tip= date= has tip= at=, date= this. -->
<whereis schema="ripwire.whereis/v1" sym="rankGraphTeleport" on-head="1" refs_scanned="374" blobs="10127" hits="2645952" head_labels="index" refs_omitted="267" shown="60" capped="1" total="2645952" has_more="1" next_offset="60" offset="0" limit="0" ref_labels="parsed" head_date="2026-11-20" at="6ace … [line truncated: 7 more bytes on this line]
<unparsed blobs="402" rows="1927" next="--whereis=rankGraphTeleport --detail=1"/>
<t_cut rows="4" next="--whereis=rankGraphTeleport --whereis-listing=all --whereis-full-text"/>
<hit ref="HEAD" p="src/graph.h" l="14619" kind="def" t="inline RankedGraph rankGraphTeleport( const Graph&amp; g, const std::vector&lt;float&gt;&amp; p, float alpha = 0.85f )"/>
<hit ref="HEAD" p="present/deck5_ripwire_build.js" l="1269" kind="ref" t="s.addText(&quot;$ ripwire . --callers=rankGraphTeleport&quot;, { x: 8.68, y: 2.1, w: 3.8, h: 0.3, fontFace: MONO, fontSize: 10, color: MUTED, margin: 0 });"/>
<hit ref="HEAD" p="present/deck5_ripwire_build.js" l="1271" kind="ref" t="{ text: &quot;&lt;callers of=\&quot;rankGraphTeleport\&quot;\n  defs=\&quot;1\&quot; count=\&quot;7\&quot; &quot;, options: { color: TEXT } },"/>
<hit ref="HEAD" p="present/deck5_ripwire_build.js" l="1285" kind="ref" t_bytes="478" t="&quot;- The --callers example: `ripwire . --callers=rankGraphTeleport` answered defs=\&quot;1\&quot; count=\&quot;6\&quot; counts_floor=\&quot;1\&quot;, with runEval and rankGraph as its first two rows, on main 4 … [line truncated: 26 more bytes on this line]
<hit ref="HEAD" p="src/cli.h" l="121" kind="ref" t="// tokens on --around=rankGraphTeleport vs 5,860 B at depth 1; the root&apos;s"/>
<hit ref="HEAD" p="src/crossref.h" l="4240" kind="ref" t="// code above the real definition: `--whereis=rankGraphTeleport` opened with three kind=&quot;def&quot; rows into"/>
<hit ref="HEAD" p="src/didyoumean.h" l="238" kind="ref" t="// `--path=rankGraphTeleport,` printed &quot;endpoint not found:  (did you mean &apos;A&apos;?)&quot;. Guarded at the shared walk"/>
<hit ref="HEAD" p="src/eval.h" l="328" kind="ref" t="const std::vector&lt;float&gt; r = rankGraphTeleport( g, diffTeleport( ing, seedMask ) ).rank;"/>
<hit ref="HEAD" p="src/graph.h" l="285" kind="ref" t="// renormalized to Σ=1 in rankGraphTeleport — so every teleport-based"/>
<hit ref="HEAD" p="src/graph.h" l="14550" kind="ref" t="// prior (never the edges) and renormalized in rankGraphTeleport. Every symbol whose name is missing from"/>
<hit ref="HEAD" p="src/graph.h" l="14607" kind="ref" t="// discard out. That is what this used to be: rankGraphTeleport called pageRankDouble, threw away its return,"/>
<hit ref="HEAD" p="src/graph.h" l="14652" kind="ref" t="// `rank = takeRank( rankGraphTeleport( … ), d )` is the only spelling, and it fills both or neither."/>
<hit ref="HEAD" p="src/graph.h" l="14666" kind="ref" t="return rankGraphTeleport( g, std::vector&lt;float&gt;( N, ranked ? 1.0f / float( ranked ) : 0.f ), alpha );"/>
<hit ref="HEAD" p="src/graph.h" l="15312" kind="ref" t="// the anchor-count is not a cliff), run the EXISTING PPR machinery (rankGraphTeleport — the same"/>
<hit ref="HEAD" p="src/graph.h" l="15382" kind="ref" t="const std::vector&lt;float&gt; ppr = rankGraphTeleport( g, p ).rank;"/>
<hit ref="HEAD" p="src/main.cpp" l="1446" kind="ref" t="rw::RankedGraph ranked  = stubbed ? rw::RankedGraph{} : rankGraphTeleport( d.g, churnPriorFromDecayed( d.ing, mined.weights, mined.anyHistory ) );"/>
<hit ref="HEAD" p="src/main.cpp" l="1485" kind="ref" t="rw::RankedGraph    ranked = isDecay ? rankGraphTeleport( d.g, churnDecayTeleportWorkspace( rootDirs, d.ing, &amp;hasChurnEvidence ) )"/>
<hit ref="HEAD" p="src/main.cpp" l="1486" kind="ref" t=": rankGraphTeleport( d.g, churnTeleportWorkspace( rootDirs, d.ing, &quot;18 months ago&quot;, &amp;hasChurnEvidence ) );"/>
<hit ref="HEAD" p="src/main.cpp" l="1500" kind="ref" t="rw::RankedGraph    ranked = rankGraphTeleport( d.g, churnTeleport( d.root, d.ing, &quot;18 months ago&quot;, d.cfg.since.empty() ? nullptr : &amp;sinceScope, &amp;hasChurnEvidence ) );"/>
<hit ref="HEAD" p="src/main.cpp" l="1878" kind="ref" t="rank = rw::takeRank( rankGraphTeleport( g, diffTeleport( ing, changed ) ), rankDisclosure );"/>
<hit ref="HEAD" p="src/mcp.h" l="2837" kind="ref" t="//   queries:[&quot;callers:rankGraphTeleport&quot;, {&quot;verb&quot;:&quot;slice&quot;,&quot;symbol&quot;:&quot;…&quot;}]"/>
<hit ref="HEAD" p="src/mcpindex.h" l="1304" kind="ref" t="// symbols, the rest uniform, then rankGraphTeleport (which also applies the name-quality biasPrior"/>
<hit ref="HEAD" p="src/mcpindex.h" l="1340" kind="ref" t="const auto [ wsRank, wsIters, wsConverged ] = rankGraphTeleport( ix.g, diffTeleport( ix.ing, changed ) );"/>
<hit ref="HEAD" p="src/mcpverbs.h" l="6237" kind="ref" t="// the colon is a SEPARATOR, and `callers: rankGraphTeleport` is how a human writes one. Untrimmed, the"/>
<hit ref="HEAD" p="src/mcpverbs.h" l="6239" kind="ref" t="//   symbol not found: &apos; rankGraphTeleport&apos; (did you mean &apos;rankGraphTeleport&apos;?)"/>
<hit ref="HEAD" p="src/selectorrefuse.h" l="7" kind="ref" t="// (&quot;that file defines no &apos;rankGraphTeleport&apos;&quot;), names the files that DO define the name, and hands back a"/>
… [36 more display lines; full output is 13459 bytes on 1 raw line(s)]
`````

stderr:

`````
ripwire: warning: --whereis read the newest 374 of 641 local branches; 267 older were not read (limit: 2097152 tree entries across all refs, 375 refs with HEAD at this tree's size); pass --detail=1 to read every branch, or narrow the branches with a ref-name filter
ripwire: warning: --whereis left 402 branch blobs unparsed, their rows kind=text (limit: 256 blobs or 64 MB per answer); pass --detail=1 to parse every one
`````

## `./build/ripwire . --whereis=rankGraphTeleport --whereis-listing=all`

*The whole hit list asked for by name: under the same 60-row cap HEAD's references fill the list, so it shows far fewer definitions (here HEAD's one) than the default above (here 60). The default serves the all page only when it shows the same definitions as the defs page in strictly fewer bytes (a tie serves it too).*

**wall time: 31.86s**

`````
<!-- ripwire whereis schema=ripwire.whereis/v1: every LOCAL ref whose tree holds sym= (refs_scanned=, blobs=), HEAD first: <hit ref= tip= date= p= l= kind= t=>. window: shown= total= capped= has_more= next_offset= offset= limit= (capped=1 cut; next_offset= pastes as offset=). at=: commit+dirty+shallow. next=: the one pasteable follow-up. refs_omitted=K: past the ref window (512 refs; whereis: 2097152 tree entries) the newest refs by committer date were read; K older local branches were not, in no count or row (a ref-name SUBSTR filter picks which; detail=1 reads all). hits=N: occurrences in HEAD plus every scanned local ref's full tree (the total rows). on-head=1|0: whether HEAD's tree holds it; 0 beside hits = it lives only on a branch. head_labels=index: HEAD kind= from the parsed index; lexical: text heuristic. ref_labels=parsed: another ref's kind= from the index's own tags parse of its blob (one per blob and path; HEAD's own blob takes HEAD's labels); a blob with no line a loose lexical test calls worth parsing is not parsed and its rows read ref; kind=text: such a line no parse read, never a def. unparsed blobs=N: other refs' blobs holding a line worth parsing that no parse read (past the runaway guard, or the parser could not finish); those lines read kind=text; next= lifts the guard. unparsed rows=N: the kind=text rows those blobs gave. hit t_bytes=N: t= previews an N-byte line (over 300 B): 200 B at most, its first bytes cut on a UTF-8 boundary plus an ellipsis. t_cut rows=N: rows of this page whose t= is a preview (each carries t_bytes=); next= replays this page (same listing, window, rows) with every line whole. more hits=N: rows after this page; page on with offset=next_offset. head_date=: a hit without tip= date= has tip= at=, date= this. -->
<whereis schema="ripwire.whereis/v1" sym="rankGraphTeleport" on-head="1" refs_scanned="374" blobs="10127" hits="2645952" head_labels="index" refs_omitted="267" shown="60" capped="1" total="2645952" has_more="1" next_offset="60" offset="0" limit="0" ref_labels="parsed" head_date="2026-11-20" at="6ace … [line truncated: 7 more bytes on this line]
<unparsed blobs="402" rows="1927" next="--whereis=rankGraphTeleport --whereis-listing=all --detail=1"/>
<t_cut rows="4" next="--whereis=rankGraphTeleport --whereis-listing=all --whereis-full-text"/>
<hit ref="HEAD" p="src/graph.h" l="14619" kind="def" t="inline RankedGraph rankGraphTeleport( const Graph&amp; g, const std::vector&lt;float&gt;&amp; p, float alpha = 0.85f )"/>
<hit ref="HEAD" p="present/deck5_ripwire_build.js" l="1269" kind="ref" t="s.addText(&quot;$ ripwire . --callers=rankGraphTeleport&quot;, { x: 8.68, y: 2.1, w: 3.8, h: 0.3, fontFace: MONO, fontSize: 10, color: MUTED, margin: 0 });"/>
<hit ref="HEAD" p="present/deck5_ripwire_build.js" l="1271" kind="ref" t="{ text: &quot;&lt;callers of=\&quot;rankGraphTeleport\&quot;\n  defs=\&quot;1\&quot; count=\&quot;7\&quot; &quot;, options: { color: TEXT } },"/>
<hit ref="HEAD" p="present/deck5_ripwire_build.js" l="1285" kind="ref" t_bytes="478" t="&quot;- The --callers example: `ripwire . --callers=rankGraphTeleport` answered defs=\&quot;1\&quot; count=\&quot;6\&quot; counts_floor=\&quot;1\&quot;, with runEval and rankGraph as its first two rows, on main 4 … [line truncated: 26 more bytes on this line]
<hit ref="HEAD" p="src/cli.h" l="121" kind="ref" t="// tokens on --around=rankGraphTeleport vs 5,860 B at depth 1; the root&apos;s"/>
<hit ref="HEAD" p="src/crossref.h" l="4240" kind="ref" t="// code above the real definition: `--whereis=rankGraphTeleport` opened with three kind=&quot;def&quot; rows into"/>
<hit ref="HEAD" p="src/didyoumean.h" l="238" kind="ref" t="// `--path=rankGraphTeleport,` printed &quot;endpoint not found:  (did you mean &apos;A&apos;?)&quot;. Guarded at the shared walk"/>
<hit ref="HEAD" p="src/eval.h" l="328" kind="ref" t="const std::vector&lt;float&gt; r = rankGraphTeleport( g, diffTeleport( ing, seedMask ) ).rank;"/>
<hit ref="HEAD" p="src/graph.h" l="285" kind="ref" t="// renormalized to Σ=1 in rankGraphTeleport — so every teleport-based"/>
<hit ref="HEAD" p="src/graph.h" l="14550" kind="ref" t="// prior (never the edges) and renormalized in rankGraphTeleport. Every symbol whose name is missing from"/>
<hit ref="HEAD" p="src/graph.h" l="14607" kind="ref" t="// discard out. That is what this used to be: rankGraphTeleport called pageRankDouble, threw away its return,"/>
<hit ref="HEAD" p="src/graph.h" l="14652" kind="ref" t="// `rank = takeRank( rankGraphTeleport( … ), d )` is the only spelling, and it fills both or neither."/>
<hit ref="HEAD" p="src/graph.h" l="14666" kind="ref" t="return rankGraphTeleport( g, std::vector&lt;float&gt;( N, ranked ? 1.0f / float( ranked ) : 0.f ), alpha );"/>
<hit ref="HEAD" p="src/graph.h" l="15312" kind="ref" t="// the anchor-count is not a cliff), run the EXISTING PPR machinery (rankGraphTeleport — the same"/>
<hit ref="HEAD" p="src/graph.h" l="15382" kind="ref" t="const std::vector&lt;float&gt; ppr = rankGraphTeleport( g, p ).rank;"/>
<hit ref="HEAD" p="src/main.cpp" l="1446" kind="ref" t="rw::RankedGraph ranked  = stubbed ? rw::RankedGraph{} : rankGraphTeleport( d.g, churnPriorFromDecayed( d.ing, mined.weights, mined.anyHistory ) );"/>
<hit ref="HEAD" p="src/main.cpp" l="1485" kind="ref" t="rw::RankedGraph    ranked = isDecay ? rankGraphTeleport( d.g, churnDecayTeleportWorkspace( rootDirs, d.ing, &amp;hasChurnEvidence ) )"/>
<hit ref="HEAD" p="src/main.cpp" l="1486" kind="ref" t=": rankGraphTeleport( d.g, churnTeleportWorkspace( rootDirs, d.ing, &quot;18 months ago&quot;, &amp;hasChurnEvidence ) );"/>
<hit ref="HEAD" p="src/main.cpp" l="1500" kind="ref" t="rw::RankedGraph    ranked = rankGraphTeleport( d.g, churnTeleport( d.root, d.ing, &quot;18 months ago&quot;, d.cfg.since.empty() ? nullptr : &amp;sinceScope, &amp;hasChurnEvidence ) );"/>
<hit ref="HEAD" p="src/main.cpp" l="1878" kind="ref" t="rank = rw::takeRank( rankGraphTeleport( g, diffTeleport( ing, changed ) ), rankDisclosure );"/>
<hit ref="HEAD" p="src/mcp.h" l="2837" kind="ref" t="//   queries:[&quot;callers:rankGraphTeleport&quot;, {&quot;verb&quot;:&quot;slice&quot;,&quot;symbol&quot;:&quot;…&quot;}]"/>
<hit ref="HEAD" p="src/mcpindex.h" l="1304" kind="ref" t="// symbols, the rest uniform, then rankGraphTeleport (which also applies the name-quality biasPrior"/>
<hit ref="HEAD" p="src/mcpindex.h" l="1340" kind="ref" t="const auto [ wsRank, wsIters, wsConverged ] = rankGraphTeleport( ix.g, diffTeleport( ix.ing, changed ) );"/>
<hit ref="HEAD" p="src/mcpverbs.h" l="6237" kind="ref" t="// the colon is a SEPARATOR, and `callers: rankGraphTeleport` is how a human writes one. Untrimmed, the"/>
<hit ref="HEAD" p="src/mcpverbs.h" l="6239" kind="ref" t="//   symbol not found: &apos; rankGraphTeleport&apos; (did you mean &apos;rankGraphTeleport&apos;?)"/>
<hit ref="HEAD" p="src/selectorrefuse.h" l="7" kind="ref" t="// (&quot;that file defines no &apos;rankGraphTeleport&apos;&quot;), names the files that DO define the name, and hands back a"/>
… [36 more display lines; full output is 13481 bytes on 1 raw line(s)]
`````

stderr:

`````
ripwire: warning: --whereis read the newest 374 of 641 local branches; 267 older were not read (limit: 2097152 tree entries across all refs, 375 refs with HEAD at this tree's size); pass --detail=1 to read every branch, or narrow the branches with a ref-name filter
ripwire: warning: --whereis left 402 branch blobs unparsed, their rows kind=text (limit: 256 blobs or 64 MB per answer); pass --detail=1 to parse every one
`````

## `./build/ripwire . --quality-delta=HEAD~1..HEAD --quality-kinds=complexity,dead-code`

*A ref range run for two of the thirteen kinds only: the named kinds' rows are exactly their rows in the full answer, the header names the others (kinds_skipped=, skipped_why="selector"), and a pass no named kind needs does not run. The replay a memory-stopped range answer hands back (kinds_next=) is this flag. Refused without --quality-delta=A..B.*

**wall time: 29.74s**

`````
<!-- ripwire quality-delta schema=ripwire.quality-delta/v1: only what the change made WORSE vs baseline=: regressions= minor= gating=; <r kind= sym= p= was= now= gating= bar=>, <sa> acked. value-ref-excluded=N: internal functions kept off because a table, field or argument in another function or at file scope holds them (matched by name, not a proven call); a floor. stale=N: ack ledger rows whose target no longer applies (sa rows); never gating. stale_by_kind=: stale= split by ack kind (kind:N,...); the sa rows are collapsed. stale_next=: the call printing the sa rows and the full header. preexisting-worse=N: regressions on symbols that existed at baseline; they gate when major. new-symbol=N: NEW code; new-symbol rows never gate, except defect-shape format-arity or a ceiling= row. register-macro-excluded=N: symbols skipped: self-registering test/bench macros or Rust #[test]; a floor. declined-call-excluded=N: symbols kept out of dead-code only because a declined call may mean them; a floor. api-new-surface=N: new PUBLIC symbols; a count, never gates, not in regressions=. renames=/rename_window_commits=: git rename pairs read over that many commits, to re-file baseline and acks. acked_by_rename=/acked_by_content=: acked= suppressions matched via git renames / an equal body hash. kinds_skipped=: kinds NOT run, so none of their rows is here and every count covers the rest; a count only they feed is absent. skipped_why=selector (the caller chose; stale acks judged for those kinds only) | memory (see ingest_scope=) | selector,memory (both). acked=N: findings suppressed by the ack ledger, listed as sa rows; never gating. base_ref=/target_ref=: the two resolved full shas a range compared (committed trees; at= omitted). churn=unavailable: range form; short-horizon-churn cannot be measured, so its silence is not no churn. -->
<quality-delta schema="ripwire.quality-delta/v1" baseline="ref-pair" regressions="0" minor="0" acked="0" stale="24" preexisting-worse="0" new-symbol="0" gating="0" register-macro-excluded="63" api-new-surface="0" base_ref="c263353bd8634245218fbca4ed03b9caca5e0f30" target_ref="6ace381eb32faf95711c423 … [line truncated: 449 more bytes on this line]
</quality-delta>
`````

## `./build/ripwire . --whereis=rankGraphTeleport --whereis-listing=all --whereis-full-text`

*The same page with every t= line whole: the page above previews each line over 300 B (200 B and t_bytes=, the <t_cut rows= next=> naming this call), and --whereis-full-text replays it with the same listing, window, rows and labels. MCP: full_text=true.*

**wall time: 30.78s**

`````
<!-- ripwire whereis schema=ripwire.whereis/v1: every LOCAL ref whose tree holds sym= (refs_scanned=, blobs=), HEAD first: <hit ref= tip= date= p= l= kind= t=>. window: shown= total= capped= has_more= next_offset= offset= limit= (capped=1 cut; next_offset= pastes as offset=). at=: commit+dirty+shallow. next=: the one pasteable follow-up. refs_omitted=K: past the ref window (512 refs; whereis: 2097152 tree entries) the newest refs by committer date were read; K older local branches were not, in no count or row (a ref-name SUBSTR filter picks which; detail=1 reads all). hits=N: occurrences in HEAD plus every scanned local ref's full tree (the total rows). on-head=1|0: whether HEAD's tree holds it; 0 beside hits = it lives only on a branch. head_labels=index: HEAD kind= from the parsed index; lexical: text heuristic. ref_labels=parsed: another ref's kind= from the index's own tags parse of its blob (one per blob and path; HEAD's own blob takes HEAD's labels); a blob with no line a loose lexical test calls worth parsing is not parsed and its rows read ref; kind=text: such a line no parse read, never a def. unparsed blobs=N: other refs' blobs holding a line worth parsing that no parse read (past the runaway guard, or the parser could not finish); those lines read kind=text; next= lifts the guard. unparsed rows=N: the kind=text rows those blobs gave. more hits=N: rows after this page; page on with offset=next_offset. head_date=: a hit without tip= date= has tip= at=, date= this. -->
<whereis schema="ripwire.whereis/v1" sym="rankGraphTeleport" on-head="1" refs_scanned="374" blobs="10127" hits="2645952" head_labels="index" refs_omitted="267" shown="60" capped="1" total="2645952" has_more="1" next_offset="60" offset="0" limit="0" ref_labels="parsed" head_date="2026-11-20" at="6ace … [line truncated: 7 more bytes on this line]
<unparsed blobs="402" rows="1927" next="--whereis=rankGraphTeleport --whereis-listing=all --detail=1"/>
<hit ref="HEAD" p="src/graph.h" l="14619" kind="def" t="inline RankedGraph rankGraphTeleport( const Graph&amp; g, const std::vector&lt;float&gt;&amp; p, float alpha = 0.85f )"/>
<hit ref="HEAD" p="present/deck5_ripwire_build.js" l="1269" kind="ref" t="s.addText(&quot;$ ripwire . --callers=rankGraphTeleport&quot;, { x: 8.68, y: 2.1, w: 3.8, h: 0.3, fontFace: MONO, fontSize: 10, color: MUTED, margin: 0 });"/>
<hit ref="HEAD" p="present/deck5_ripwire_build.js" l="1271" kind="ref" t="{ text: &quot;&lt;callers of=\&quot;rankGraphTeleport\&quot;\n  defs=\&quot;1\&quot; count=\&quot;7\&quot; &quot;, options: { color: TEXT } },"/>
<hit ref="HEAD" p="present/deck5_ripwire_build.js" l="1285" kind="ref" t="&quot;- The --callers example: `ripwire . --callers=rankGraphTeleport` answered defs=\&quot;1\&quot; count=\&quot;6\&quot; counts_floor=\&quot;1\&quot;, with runEval and rankGraph as its first two rows, on main 40a1895b. On ma … [line truncated: 355 more bytes on this line]
<hit ref="HEAD" p="src/cli.h" l="121" kind="ref" t="// tokens on --around=rankGraphTeleport vs 5,860 B at depth 1; the root&apos;s"/>
<hit ref="HEAD" p="src/crossref.h" l="4240" kind="ref" t="// code above the real definition: `--whereis=rankGraphTeleport` opened with three kind=&quot;def&quot; rows into"/>
<hit ref="HEAD" p="src/didyoumean.h" l="238" kind="ref" t="// `--path=rankGraphTeleport,` printed &quot;endpoint not found:  (did you mean &apos;A&apos;?)&quot;. Guarded at the shared walk"/>
<hit ref="HEAD" p="src/eval.h" l="328" kind="ref" t="const std::vector&lt;float&gt; r = rankGraphTeleport( g, diffTeleport( ing, seedMask ) ).rank;"/>
<hit ref="HEAD" p="src/graph.h" l="285" kind="ref" t="// renormalized to Σ=1 in rankGraphTeleport — so every teleport-based"/>
<hit ref="HEAD" p="src/graph.h" l="14550" kind="ref" t="// prior (never the edges) and renormalized in rankGraphTeleport. Every symbol whose name is missing from"/>
<hit ref="HEAD" p="src/graph.h" l="14607" kind="ref" t="// discard out. That is what this used to be: rankGraphTeleport called pageRankDouble, threw away its return,"/>
<hit ref="HEAD" p="src/graph.h" l="14652" kind="ref" t="// `rank = takeRank( rankGraphTeleport( … ), d )` is the only spelling, and it fills both or neither."/>
<hit ref="HEAD" p="src/graph.h" l="14666" kind="ref" t="return rankGraphTeleport( g, std::vector&lt;float&gt;( N, ranked ? 1.0f / float( ranked ) : 0.f ), alpha );"/>
<hit ref="HEAD" p="src/graph.h" l="15312" kind="ref" t="// the anchor-count is not a cliff), run the EXISTING PPR machinery (rankGraphTeleport — the same"/>
<hit ref="HEAD" p="src/graph.h" l="15382" kind="ref" t="const std::vector&lt;float&gt; ppr = rankGraphTeleport( g, p ).rank;"/>
<hit ref="HEAD" p="src/main.cpp" l="1446" kind="ref" t="rw::RankedGraph ranked  = stubbed ? rw::RankedGraph{} : rankGraphTeleport( d.g, churnPriorFromDecayed( d.ing, mined.weights, mined.anyHistory ) );"/>
<hit ref="HEAD" p="src/main.cpp" l="1485" kind="ref" t="rw::RankedGraph    ranked = isDecay ? rankGraphTeleport( d.g, churnDecayTeleportWorkspace( rootDirs, d.ing, &amp;hasChurnEvidence ) )"/>
<hit ref="HEAD" p="src/main.cpp" l="1486" kind="ref" t=": rankGraphTeleport( d.g, churnTeleportWorkspace( rootDirs, d.ing, &quot;18 months ago&quot;, &amp;hasChurnEvidence ) );"/>
<hit ref="HEAD" p="src/main.cpp" l="1500" kind="ref" t="rw::RankedGraph    ranked = rankGraphTeleport( d.g, churnTeleport( d.root, d.ing, &quot;18 months ago&quot;, d.cfg.since.empty() ? nullptr : &amp;sinceScope, &amp;hasChurnEvidence ) );"/>
<hit ref="HEAD" p="src/main.cpp" l="1878" kind="ref" t="rank = rw::takeRank( rankGraphTeleport( g, diffTeleport( ing, changed ) ), rankDisclosure );"/>
<hit ref="HEAD" p="src/mcp.h" l="2837" kind="ref" t="//   queries:[&quot;callers:rankGraphTeleport&quot;, {&quot;verb&quot;:&quot;slice&quot;,&quot;symbol&quot;:&quot;…&quot;}]"/>
<hit ref="HEAD" p="src/mcpindex.h" l="1304" kind="ref" t="// symbols, the rest uniform, then rankGraphTeleport (which also applies the name-quality biasPrior"/>
<hit ref="HEAD" p="src/mcpindex.h" l="1340" kind="ref" t="const auto [ wsRank, wsIters, wsConverged ] = rankGraphTeleport( ix.g, diffTeleport( ix.ing, changed ) );"/>
<hit ref="HEAD" p="src/mcpverbs.h" l="6237" kind="ref" t="// the colon is a SEPARATOR, and `callers: rankGraphTeleport` is how a human writes one. Untrimmed, the"/>
<hit ref="HEAD" p="src/mcpverbs.h" l="6239" kind="ref" t="//   symbol not found: &apos; rankGraphTeleport&apos; (did you mean &apos;rankGraphTeleport&apos;?)"/>
<hit ref="HEAD" p="src/selectorrefuse.h" l="7" kind="ref" t="// (&quot;that file defines no &apos;rankGraphTeleport&apos;&quot;), names the files that DO define the name, and hands back a"/>
<hit ref="HEAD" p="bench/capsweep/capsweep.py" l="173" kind="ref" t="# all and passes through untouched — `. --pattern=\&apos;rankGraphTeleport($A, $B, $C)\&apos;` is a tree-sitter pattern"/>
… [35 more display lines; full output is 13988 bytes on 1 raw line(s)]
`````

stderr:

`````
ripwire: warning: --whereis read the newest 374 of 641 local branches; 267 older were not read (limit: 2097152 tree entries across all refs, 375 refs with HEAD at this tree's size); pass --detail=1 to read every branch, or narrow the branches with a ref-name filter
ripwire: warning: --whereis left 402 branch blobs unparsed, their rows kind=text (limit: 256 blobs or 64 MB per answer); pass --detail=1 to parse every one
`````

## `./build/ripwire . --whereis=computeOnePairOverlap --with-history`

*Same, plus a git-history <fate> row (never / removed-by-commit) for names no tree carries.*

**wall time: 27.45s**

`````
<!-- ripwire whereis schema=ripwire.whereis/v1: every LOCAL ref whose tree holds sym= (refs_scanned=, blobs=), HEAD first: <hit ref= tip= date= p= l= kind= t=>. window: shown= capped= (capped=1 cut). at=: commit+dirty+shallow. next=: the one pasteable follow-up. refs_omitted=K: past the ref window (512 refs; whereis: 2097152 tree entries) the newest refs by committer date were read; K older local branches were not, in no count or row (a ref-name SUBSTR filter picks which; detail=1 reads all). hits=N: occurrences in HEAD plus every scanned local ref's full tree (the total rows). on-head=1|0: whether HEAD's tree holds it; 0 beside hits = it lives only on a branch. head_labels=index: HEAD kind= from the parsed index; lexical: text heuristic. ref_labels=parsed: another ref's kind= from the index's own tags parse of its blob (one per blob and path; HEAD's own blob takes HEAD's labels); a blob with no line a loose lexical test calls worth parsing is not parsed and its rows read ref; kind=text: such a line no parse read, never a def. hit refs=N: N scanned refs hold this same definition (or kind=text) line (path + text); printed once for the first by name, whose ref= tip= date= l= it carries; defs page only, absent = one ref; hits= counts every copy, listing=all prints each. folded=N: def (or text) rows of other refs a listed row's refs= stands for; shown + more + folded + refs count = hits on the first page. listing=defs|refs: only those kind= rows listed (defs: def and text); under defs <refs count=N next=> counts the kind=ref rows and next= lists them; the window counts listed rows; default: defs if it lists more defs than all, else if shorter; a def the parser does not model (define_method, setattr, assignment) is a counted ref. head_date=: a hit without tip= date= has tip= at=, date= this. -->
<whereis schema="ripwire.whereis/v1" sym="computeOnePairOverlap" on-head="1" refs_scanned="374" blobs="10127" hits="162559" head_labels="index" refs_omitted="267" shown="2" capped="0" listing="defs" folded="373" ref_labels="parsed" head_date="2026-11-20" at="6ace381eb">
<history probed="1" head="6ace381eb" commits="7313" removed-names="58797"/>
<hit ref="HEAD" p="src/mergescout.h" l="696" kind="def" t="inline PairOverlap computeOnePairOverlap( std::size_t a, std::size_t b, const Arm&amp; armA, const Arm&amp; armB )"/>
<hit ref="community/pr433" tip="fafb3f267" date="2026-10-29" p="src/mergescout.h" l="696" kind="def" refs="374" t="inline PairOverlap computeOnePairOverlap( std::size_t a, std::size_t b, const Arm&amp; armA, const Arm&amp; armB )"/>
<refs count="162184" next="--whereis=computeOnePairOverlap --whereis-listing=refs"/>
</whereis>
`````

stderr:

`````
ripwire: warning: --whereis read the newest 374 of 641 local branches; 267 older were not read (limit: 2097152 tree entries across all refs, 375 refs with HEAD at this tree's size); pass --detail=1 to read every branch, or narrow the branches with a ref-name filter
`````

## `./build/ripwire . --flags`

*The dark-content dashboard: gates BUILT but OFF. CHANGED: no longer invents gates from comments/heredocs, so the count only reflects real ifndef/define, CMake option(), and getenv gates.*

**wall time: 3.44s**

`````
<!-- ripwire flags schema=ripwire.flags/v1: BUILT but DARK: <gate name= kind=compile|cmake|env default= dark= regions=/loc=(#if only) reads= p= l=> with <read p= l=> sites. writes_capped=/reads_capped=: 1 = cut. next=: the one pasteable follow-up. gates=/dark_gates=: gate rows (never cut) / those whose default keeps the guarded code out of the build. compile=/cmake=/env=: gates by kind: ifndef/define header gate, CMake option(), getenv read. files=N: files this verb scanned for gates (source + CMakeLists), wider than the map's corpus. -->
<!-- BASH: a parameter expansion in a .sh/.bash/.zsh file is an env read (kind="env") unless the same file assigned that name before it (lexical order in one file: no flow, no source following). An assignment takes effect where its command ends, so X="${X:-d}" or a quoted value spanning lines still reads the caller's X. Each Bash read row carries form= (required for :? and ?, default for :-, unset-default for -, settest for + and :+ and a -n/-z operand of [, [[ or test, assign for := and =, plain for $X and ${X}); colon="1" when the colon spelling makes an EMPTY value count as unset (colon="0" when not, absent when the expansion has no operator); default= the literal default word, possibly empty; test="n" or "z" when the read is the operand of that test. writes= on a gate counts, and write rows list, every Bash assignment of the name anywhere in the repo (X=, export X=, local, declare, readonly, read, for, mapfile, getopts, printf -v, := expansions, and the REPLY, OPTARG or MAPFILE that read, select, getopts and mapfile set themselves; not a prefix X=v cmd, which reaches only that command). A local, or a declare inside a function, hides reads only to the end of that function; a write inside $( ) or ( ) only to that subshell's end; an element write X[i]= hides only subscripted ${X[i]} reads, never the scalar $X. Write rows are paged like the reads (shown_writes= writes_capped= and more writes= as for reads). ambient="1": a name Bash or the login always sets (BASH_*, PWD, HOME, PATH, RANDOM and the like), never unsupplied. generated_skipped=N on the root: shell files this verb read but did not harvest because a GENERATED and DO NOT EDIT banner opens them. nesting_cut=N on the root: shell files where an expansion nested more than 32 deep inside another's word (${A:-${B:-…}}) was not read past that depth, so a read there may be missing. -->
<!-- ROWS AND WHAT IS NEVER CUT: the gate rows ARE the answer this verb was asked for and are never windowed, capped or paged, and gates/dark_gates/compile/cmake/env/files on the root plus regions/loc/reads/dark on every gate are counted over the FULL set before any cap exists. What pages is the read SITES under one gate, at 8 a gate by default: a gate whose sites were cut says shown_reads= (the rows this run printed) with reads_capped="1", against the reads= total already on the same element, and the more reads= child keeps naming the remainder. The pair is emitted ONLY on a gate that was cut, never as a capped="0" on the gates that fit. limit=N raises the per gate cap (offset=M skips that many sites in every gate), detail lifts it entirely, and next= on the root is the exact pasteable invocation that shows every site this run dropped. -->
<flags schema="ripwire.flags/v1" gates="492" dark_gates="483" compile="13" cmake="13" env="466" files="4847" generated_skipped="1" next="--flags --limit=876">
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
<gate name="FIXTURE_CMAKE_DARK" kind="cmake" default="unset" dark="1" regions="1" loc="1" reads="3" p="test/flagsfix/CMakeLists.txt" l="4">
<alias-of name="OFF"/>
… [2398 more display lines; full output is 150827 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --flags --flip=RIPWIRE_ASAN`

*Blast radius of turning ONE gate on: live code, symbols, transitive reach, covering tests.*

**wall time: 2.43s**

`````
<!-- ripwire flip schema=ripwire.flip/v1: the blast radius of flipping one build gate: the regions and symbols it toggles. root=: p= relative to it. -->
<flip schema="ripwire.flip/v1" gate="RIPWIRE_ASAN" kind="cmake" default="unset" dark="1" runtime="0" p="CMakeLists.txt" l="14" family="1" regions="0" loc="0" branches="0" bindings="0" hosts="0" filescope="0" downstream="0" dependents="0" tests="0" untested="0" files="4847" root=".">
<parent name="OFF" siblings="9"/>
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

**exit code: 1**

`````
(empty)
`````

stderr:

`````
ripwire: --flip: no gate named 'RIPWIRE_ASA' in . (did you mean 'RIPWIRE_ASAN', 'RIPWIRE_ASAN_BIN', 'RIPWIRE_ASAN_PROBE_SEC', 'RIPWIRE_ASAN_PROBE_WHY'?)
ripwire: run `ripwire . --flags` for the gate table
`````

## `./build/ripwire . --plan-lanes=3 --task="add a --since filter to the doc-drift verb and cover it with tests"`

*NEW VERB: pre-hoc lane plan — which of 3 parallel worktrees would COLLIDE, before a line is written. JSON on stdout.*

**wall time: 3.09s**

`````
{"v":1,"verb":"plan-lanes","at":"6ace381eb","root":".","task":"add a --since filter to the doc-drift verb and cover it with tests","source":"partition","requested":3,"lane_count":3,"claim_key":"path+scope+name","on_conflict":"producing-lane-rebases","corpus":{"files":4838,"symbols":44601,"edges":444 … [line truncated: 338 more bytes on this line]
"symbols":[{"p":"./src/docdrift.h","n":"DriftResult","scope":"DriftResult","l":286,"id":"./src/docdrift.h::DriftResult::DriftResult"},
{"p":"./src/docdrift.h","n":"computeDocDrift","scope":"docdrift","l":2441,"id":"./src/docdrift.h::docdrift::computeDocDrift"},
{"p":"./src/docdrift.h","n":"kDocDriftLegend","scope":"docdrift","l":2739,"id":"./src/docdrift.h::docdrift::kDocDriftLegend"},
{"p":"./src/docdrift.h","n":"writeDocDriftPage","scope":"docdrift","l":2909,"id":"./src/docdrift.h::docdrift::writeDocDriftPage"},
{"p":"./src/mcpverbs.h","n":"docDriftText","scope":"rw","l":689,"id":"./src/mcpverbs.h::rw::docDriftText"},
{"p":"./src/verbs_change.h","n":"runDocDrift","scope":"","l":1688,"id":null}]},"lanes":[{"id":"lane-0","task":"add a --since filter to the doc-drift verb and cover it with tests","claims":{"symbols":[{"p":"./src/editcheck.h","n":"editCheckPriceRoot","scope":"rw","key":"33219bb04158a6a8","id":"./src/ … [line truncated: 158 more bytes on this line]
{"p":"./src/docdrift.h","n":"writeGateability","scope":"docdrift","key":"42c456dfb55faee4","id":"./src/docdrift.h::docdrift::writeGateability","id_addressable":true,"id_collides_with":0,"l":2685,"ord":0,"overloads":1,"amb":2,"cx":6,"ccx":6,"churn":37,"tested":0},
{"p":"./src/docdrift.h","n":"docDriftNextAttr","scope":"docdrift","key":"7723ed789a1c9c09","id":"./src/docdrift.h::docdrift::docDriftNextAttr","id_addressable":true,"id_collides_with":0,"l":2864,"ord":0,"overloads":1,"amb":0,"cx":6,"ccx":5,"churn":37,"tested":0},
{"p":"./src/docdrift.h","n":"writeWeakDisclosures","scope":"docdrift","key":"7d760d428aab46d1","id":"./src/docdrift.h::docdrift::writeWeakDisclosures","id_addressable":true,"id_collides_with":0,"l":2839,"ord":0,"overloads":1,"amb":2,"cx":4,"ccx":5,"churn":37,"tested":0},
{"p":"./src/docdrift.h","n":"recordWeakDisclosures","scope":"docdrift","key":"972779210e49c0cf","id":"./src/docdrift.h::docdrift::recordWeakDisclosures","id_addressable":true,"id_collides_with":0,"l":2430,"ord":0,"overloads":1,"amb":0,"cx":2,"ccx":1,"churn":37,"tested":0},
{"p":"./src/testmap.h","n":"scriptGatesUnmodelledCount","scope":"rw","key":"98c4487e2e9e08bc","id":"./src/testmap.h::rw::scriptGatesUnmodelledCount","id_addressable":true,"id_collides_with":0,"l":2016,"ord":0,"overloads":1,"amb":0,"cx":4,"ccx":4,"churn":77,"tested":0},
{"p":"./src/main.cpp","n":"scanReportVerbPrecedence","scope":"","key":"9ab981e987e8108e","id":null,"id_addressable":false,"id_collides_with":0,"l":3038,"ord":0,"overloads":1,"amb":0,"cx":8,"ccx":11,"churn":509,"tested":0},
{"p":"./src/graphlegend.h","n":"impactTestedPartitionLegend","scope":"rw","key":"9ca0ff23a3b8620e","id":"./src/graphlegend.h::rw::impactTestedPartitionLegend","id_addressable":true,"id_collides_with":0,"l":567,"ord":0,"overloads":1,"amb":0,"cx":4,"ccx":4,"churn":241,"tested":0},
{"p":"./src/pageview.h","n":"secondaryCutAttrs","scope":"rw","key":"a10ea8d3bdca1dfb","id":"./src/pageview.h::rw::secondaryCutAttrs","id_addressable":true,"id_collides_with":0,"l":404,"ord":0,"overloads":1,"amb":0,"cx":3,"ccx":2,"churn":29,"tested":0},
{"p":"./src/main.cpp","n":"emitNoteAddUnprovenDefs","scope":"","key":"a950332ccfce6b8d","id":null,"id_addressable":false,"id_collides_with":0,"l":695,"ord":0,"overloads":1,"amb":1,"cx":2,"ccx":1,"churn":509,"tested":0},
{"p":"./src/docdrift.h","n":"sortDocsByLiveDrift","scope":"docdrift","key":"d5de682411b9a9a9","id":"./src/docdrift.h::docdrift::sortDocsByLiveDrift","id_addressable":true,"id_collides_with":0,"l":2390,"ord":0,"overloads":1,"amb":0,"cx":2,"ccx":2,"churn":37,"tested":0},
{"p":"./src/mcpverbs.h","n":"unknownSubVerbRefusal","scope":"rw","key":"e336d39b0a6addea","id":"./src/mcpverbs.h::rw::unknownSubVerbRefusal","id_addressable":true,"id_collides_with":0,"l":6305,"ord":0,"overloads":1,"amb":0,"cx":3,"ccx":2,"churn":675,"tested":0}],
"files":[{"p":"./src/docdrift.h","symbols":5,"churn":37,"ccx":19,"hotspot_rank":51},
{"p":"./src/editcheck.h","symbols":1,"churn":70,"ccx":10,"hotspot_rank":54},
{"p":"./src/graphlegend.h","symbols":1,"churn":241,"ccx":4,"hotspot_rank":34},
{"p":"./src/main.cpp","symbols":2,"churn":509,"ccx":12,"hotspot_rank":5},
{"p":"./src/mcpverbs.h","symbols":1,"churn":675,"ccx":2,"hotspot_rank":4},
{"p":"./src/pageview.h","symbols":1,"churn":29,"ccx":2,"hotspot_rank":173},
{"p":"./src/testmap.h","symbols":1,"churn":77,"ccx":4,"hotspot_rank":37}]},"blast_radius":{"reaches":53,"files_total":17,"capped":false,"files":["./src/darkflags.h","./src/docdrift.h","./src/editcheck.h","./src/editplan.h","./src/editpreview.h","./src/flipimpact.h","./src/main.cpp","./src/mcp.h","./ … [line truncated: 202 more bytes on this line]
"tests_total":0,"tests_capped":false,"tests_granularity":"claimed-symbols","untested":53,"module_span":1,"notes":[],
"execution":{"policy":"codex-lane/v1","model":"gpt-5.6-sol","reasoning":"high","rule":"complex-or-wide","basis":"structural-only","signals":{"claims":12,"files":7,"module_span":1,"max_ccx":11,"sum_ccx":53,"ambiguous_calls":5,"blast_reaches":53,"contract_touches":0,"conflicts":0,"untested":53,"tests_ … [line truncated: 134 more bytes on this line]
{"id":"lane-1","task":"add a --since filter to the doc-drift verb and cover it with tests","claims":{"symbols":[{"p":"./src/taskroute.h","n":"classifyRoutesUncapped","scope":"rw::taskroute","key":"0c5e6053e914484d","id":"./src/taskroute.h::rw::taskroute::classifyRoutesUncapped","id_addressable":true … [line truncated: 101 more bytes on this line]
{"p":"./src/gitmine.h","n":"gitWindowBoundarySha","scope":"rw","key":"18627516699d7062","id":"./src/gitmine.h::rw::gitWindowBoundarySha","id_addressable":true,"id_collides_with":0,"l":2179,"ord":0,"overloads":1,"amb":1,"cx":4,"ccx":3,"churn":106,"tested":0},
{"p":"./src/jsrunner.h","n":"matchesDefaultInclude","scope":"rw::jsrunner","key":"1e885c432f6da6bb","id":"./src/jsrunner.h::rw::jsrunner::matchesDefaultInclude","id_addressable":true,"id_collides_with":0,"l":549,"ord":0,"overloads":1,"amb":0,"cx":11,"ccx":11,"churn":22,"tested":0},
… [70 more display lines; full output is 20713 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --plan-lanes --brief=<scratch>/aux/lanes_brief.txt`

*NEW VERB, explicit form: one line per lane, lane boundaries are the ones you wrote (the defensible mode).*

**wall time: 3.07s**

Input file:

`````
add a --since filter to the doc-drift verb
add the CLI parse arm and help text for the new filter
write regression tests for the new filter
`````

`````
{"v":1,"verb":"plan-lanes","at":"6ace381eb","root":".","task":null,"source":"brief","requested":3,"lane_count":3,"claim_key":"path+scope+name","on_conflict":"producing-lane-rebases","corpus":{"files":4838,"symbols":44601,"edges":44429,"ambiguous":3634,"unresolved":20069},"carve":null,"core":{"files" … [line truncated: 4 more bytes on this line]
"symbols":[]},"lanes":[{"id":"lane-0","task":"add a --since filter to the doc-drift verb","claims":{"symbols":[{"p":"./src/docdrift.h","n":"recordUnchecked","scope":"docdrift","key":"12641dab14abc8fd","id":"./src/docdrift.h::docdrift::recordUnchecked","id_addressable":true,"id_collides_with":0,"l":2 … [line truncated: 72 more bytes on this line]
{"p":"./src/docdrift.h","n":"sortWeakGroupsByPath","scope":"docdrift","key":"1944ba506280ff80","id":"./src/docdrift.h::docdrift::sortWeakGroupsByPath","id_addressable":true,"id_collides_with":0,"l":2401,"ord":0,"overloads":1,"amb":0,"cx":1,"ccx":0,"churn":37,"tested":0},
{"p":"./src/mcpverbs.h","n":"docDriftText","scope":"rw","key":"1fa68e8d93c05a59","id":"./src/mcpverbs.h::rw::docDriftText","id_addressable":true,"id_collides_with":0,"l":689,"ord":0,"overloads":1,"amb":0,"cx":1,"ccx":0,"churn":675,"tested":0},
{"p":"./src/recall.h","n":"docFileMask","scope":"rw","key":"3149a219f599664c","id":"./src/recall.h::rw::docFileMask","id_addressable":true,"id_collides_with":0,"l":113,"ord":0,"overloads":1,"amb":0,"cx":4,"ccx":4,"churn":49,"tested":0},
{"p":"./src/docdrift.h","n":"writeDocDriftPage","scope":"docdrift","key":"380b7de5df1cfd73","id":"./src/docdrift.h::docdrift::writeDocDriftPage","id_addressable":true,"id_collides_with":0,"l":2909,"ord":0,"overloads":1,"amb":10,"cx":14,"ccx":15,"churn":37,"tested":0},
{"p":"./src/docdrift.h","n":"computeDocDrift","scope":"docdrift","key":"3b19cc3d8996c3b2","id":"./src/docdrift.h::docdrift::computeDocDrift","id_addressable":true,"id_collides_with":0,"l":2441,"ord":0,"overloads":1,"amb":1,"cx":26,"ccx":38,"churn":37,"tested":0},
{"p":"./src/docdrift.h","n":"DriftResult","scope":"DriftResult","key":"422ab39546b6e0bd","id":"./src/docdrift.h::DriftResult::DriftResult","id_addressable":true,"id_collides_with":0,"l":286,"ord":0,"overloads":1,"amb":0,"cx":0,"ccx":0,"churn":37,"tested":0},
{"p":"./src/docdrift.h","n":"writeGateability","scope":"docdrift","key":"42c456dfb55faee4","id":"./src/docdrift.h::docdrift::writeGateability","id_addressable":true,"id_collides_with":0,"l":2685,"ord":0,"overloads":1,"amb":2,"cx":6,"ccx":6,"churn":37,"tested":0},
{"p":"./src/verbs_change.h","n":"runDocDrift","scope":"","key":"904831e5c0f66b39","id":null,"id_addressable":false,"id_collides_with":0,"l":1688,"ord":0,"overloads":1,"amb":1,"cx":5,"ccx":4,"churn":92,"tested":0},
{"p":"./src/ensemble.h","n":"kEnsembleChurnSince","scope":"ensemble","key":"a34fc78c05bf56a8","id":"./src/ensemble.h::ensemble::kEnsembleChurnSince","id_addressable":true,"id_collides_with":0,"l":121,"ord":0,"overloads":1,"amb":0,"cx":0,"ccx":0,"churn":24,"tested":0},
{"p":"./src/mcpverbs.h","n":"unknownSubVerbRefusal","scope":"rw","key":"e336d39b0a6addea","id":"./src/mcpverbs.h::rw::unknownSubVerbRefusal","id_addressable":true,"id_collides_with":0,"l":6305,"ord":0,"overloads":1,"amb":0,"cx":3,"ccx":2,"churn":675,"tested":0},
{"p":"./src/docdrift.h","n":"kDocDriftLegend","scope":"docdrift","key":"ff2ba74637bbbebf","id":"./src/docdrift.h::docdrift::kDocDriftLegend","id_addressable":true,"id_collides_with":0,"l":2739,"ord":0,"overloads":1,"amb":0,"cx":0,"ccx":0,"churn":37,"tested":0}],
"files":[{"p":"./src/docdrift.h","symbols":7,"churn":37,"ccx":60,"hotspot_rank":51},
{"p":"./src/ensemble.h","symbols":1,"churn":24,"ccx":0,"hotspot_rank":131},
{"p":"./src/mcpverbs.h","symbols":2,"churn":675,"ccx":2,"hotspot_rank":4},
{"p":"./src/recall.h","symbols":1,"churn":49,"ccx":4,"hotspot_rank":48},
{"p":"./src/verbs_change.h","symbols":1,"churn":92,"ccx":4,"hotspot_rank":35}],
"symbols_total":4272,"symbols_capped":true},"blast_radius":{"reaches":27,"files_total":8,"capped":false,"files":["./src/docdrift.h","./src/fordocbody.h","./src/main.cpp","./src/mcp.h","./src/mcpserver.h","./src/mcpverbs.h","./src/recall.h","./src/verbs_for.h"]},"tests_to_run":[],
"tests_total":0,"tests_capped":false,"tests_granularity":"claimed-symbols","untested":27,"module_span":5,"notes":[],
"execution":{"policy":"codex-lane/v1","model":"gpt-5.6-sol","reasoning":"xhigh","rule":"wide-contract-work","basis":"structural-only","signals":{"claims":12,"files":5,"module_span":5,"max_ccx":38,"sum_ccx":70,"ambiguous_calls":14,"blast_reaches":27,"contract_touches":1,"conflicts":0,"untested":27,"t … [line truncated: 139 more bytes on this line]
{"id":"lane-1","task":"add the CLI parse arm and help text for the new filter","claims":{"symbols":[{"p":"./scripts/optremarks.py","n":"main","scope":"","key":"01b3b880f77d1512","id":null,"id_addressable":false,"id_collides_with":188,"l":286,"ord":0,"overloads":1,"amb":0,"cx":23,"ccx":31,"churn":19, … [line truncated: 12 more bytes on this line]
{"p":"./scripts/merge_resolve.py","n":"main","scope":"","key":"0618162fab697309","id":null,"id_addressable":false,"id_collides_with":188,"l":208,"ord":0,"overloads":1,"amb":0,"cx":17,"ccx":34,"churn":4,"tested":0},
{"p":"./src/cli.h","n":"HelpLine","scope":"rw","key":"1489844dbc310b82","id":"./src/cli.h::rw::HelpLine","id_addressable":true,"id_collides_with":0,"l":3148,"ord":0,"overloads":1,"amb":0,"cx":0,"ccx":0,"churn":650,"tested":0},
{"p":"./src/cli.h","n":"HelpFilter","scope":"HelpFilter","key":"3103a5e8bfc33d38","id":"./src/cli.h::HelpFilter::HelpFilter","id_addressable":true,"id_collides_with":0,"l":3227,"ord":0,"overloads":1,"amb":0,"cx":0,"ccx":0,"churn":650,"tested":0},
{"p":"./docs/docs_commands_build.py","n":"main","scope":"","key":"4015853681ded3bc","id":null,"id_addressable":false,"id_collides_with":188,"l":900,"ord":0,"overloads":1,"amb":0,"cx":19,"ccx":28,"churn":19,"tested":0},
{"p":"./src/mcprefusal.h","n":"kMcpValueFields","scope":"rw::mcprefuse","key":"4a7106e488a2aa80","id":"./src/mcprefusal.h::rw::mcprefuse::kMcpValueFields","id_addressable":true,"id_collides_with":0,"l":304,"ord":0,"overloads":1,"amb":0,"cx":0,"ccx":0,"churn":51,"tested":0},
{"p":"./src/query.h","n":"tryParsePredicateOnAll","scope":"query","key":"786acc4dbfec612b","id":"./src/query.h::query::tryParsePredicateOnAll","id_addressable":false,"id_collides_with":1,"l":114,"ord":0,"overloads":2,"amb":0,"cx":1,"ccx":0,"churn":22,"tested":0},
{"p":"./src/cli.h","n":"printUsageTier","scope":"rw","key":"82b7af67acdca479","id":"./src/cli.h::rw::printUsageTier","id_addressable":true,"id_collides_with":0,"l":3278,"ord":0,"overloads":1,"amb":0,"cx":2,"ccx":1,"churn":650,"tested":0},
{"p":"./src/crossref.h","n":"writeWhereisTextCut","scope":"crossref","key":"9a3ef6403f53ce21","id":"./src/crossref.h::crossref::writeWhereisTextCut","id_addressable":true,"id_collides_with":0,"l":5163,"ord":0,"overloads":1,"amb":1,"cx":3,"ccx":3,"churn":111,"tested":0},
… [59 more display lines; full output is 18377 bytes on 1 raw line(s)]
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
<!-- ripwire layout schema=ripwire.layout/v1: struct field layout vs cache lines: offsets, padding, hot/cold split candidates. root=: p= relative to it. sym=: the aggregate name asked for. found=1: a C-family struct/class/union body was located for sym=. defs=N: same-name aggregate defs found; a more element counts any not shown. mirror=: single|match|mismatch (byte drift, exits nonzero)|stub|spelling, over same-name defs. asserts=N: static_assert tripwires in indexed files that mention sym=. conflicts=N: asserts contradicting the computed size (agree=0 rows); nonzero exits nonzero. scanned=N: indexed C-family files read for asserts. agg=: struct, class or union. fields=N: member rows listed. modeled=0: size/align/tail pad not computed; off= only up to the first unknown. ty=: the field type as written, before macro expansion (as= gives the expansion). sz=N: field bytes incl. array extent (LP64 model); sized=0 instead when unknown. al=N: field alignment in bytes (LP64 model). off=N: computed byte offset; absent after an earlier field of unknown size. bits=N bit=B: a bitfield N bits wide from bit B of its 1-byte unit at off=. std_abi=: the C++ standard library (libc++|libstdc++) whose std:: member sizes were used: the one this binary was built against. def size=/align=/tail_pad=: computed bytes, alignment, trailing padding (modeled=1 only). -->
<layout schema="ripwire.layout/v1" sym="Symbol" found="1" defs="1" mirror="single" asserts="3" conflicts="0" scanned="1127" std_abi="libc++" root=".">
<def p="src/model.h" l="912" agg="struct" modeled="1" fields="31" size="112" align="8" tail_pad="0">
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
<f n="locals" ty="std::uint16_t" sz="2" al="2" off="40"/>
<f n="steer" ty="std::uint8_t" sz="1" al="1" off="42"/>
<f n="dispatchShare" ty="std::uint8_t" sz="1" al="1" off="43"/>
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
<assert p="src/model.h" l="1136" kind="mention" t="static_assert( sizeof( Symbol ) == 64 + 2 * sizeof( std::string ), &quot;Symbol size changed — verify the new field uses the smallest type + is grouped (SoA); see model.h&quot; )"/>
<assert p="src/renamemine.h" l="617" kind="mention" t="static_assert( kRuleCount &lt;= std::numeric_limits&lt;decltype( firedRuleMask( std::declval&lt;const Symbol&amp;&gt;(), std::string_view() ) )&gt;::digits, &quot;firedRuleMask holds one bit per naming rule — widen it before kRuleCount outgro" … [line truncated: 2 more bytes on this line]
<assert p="src/warmsnap_model.h" l="35" kind="mention" t="static_assert( sizeof( IngestResult ) == 1144 &amp;&amp; sizeof( Symbol ) == 112 &amp;&amp; sizeof( Reference ) == 64 &amp;&amp; sizeof( Binding ) == 36 &amp;&amp; sizeof( RefColdText ) == 20, &quot;the model changed shape: store and load the … [line truncated: 18 more bytes on this line]
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
<doc-drift schema="ripwire.doc-drift/v1" docs="351" clean="317" anchors="8233" checked="3894" unchecked="4339" drift="88" dated="135" prose="26" corpus="5004" at="6ace381eb" next="--doc-drift --detail=1">
<doc p="docs/research/answer-completeness.md" anchors="187" checked="84" drift="16" dated="0" shown_failed="12" failed_capped="1" failed_total="16">
<a k="file-line" l="341" c="25" why="line-moved" ref="src/pageview.h:292" sym="pageDisclosure" got="(file scope)" tgt="src/pageview.h:351"/>
<a k="file-line" l="349" c="99" why="line-moved" ref="src/serialize.h:4169" sym="kForLensDefaultTopN" got="serialize" tgt="src/serialize.h:1101"/>
<a k="file-line" l="353" c="89" why="line-moved" ref="src/serialize.h:4435" sym="kForPayloadBudgetBytes" got="packSource" tgt="src/serialize.h:990"/>
<a k="file-line" l="356" c="42" why="line-moved" ref="src/serialize.h:1010" sym="kForFileTailShownCap" got="forRunawayGuardNote" tgt="src/serialize.h:1178"/>
<a k="file-line" l="358" c="89" why="line-moved" ref="src/serialize.h:5481" sym="kForAnchorBodyBudgetBytes" got="(file scope)" tgt="src/serialize.h:1154"/>
<a k="file-line" l="360" c="88" why="line-moved" ref="src/serialize.h:5800" sym="kForCompactSurfaceBudgetBytes" got="SigsCutReport" tgt="src/serialize.h:1273"/>
<a k="file-line" l="366" c="43" why="line-moved" ref="src/serialize.h:6534" sym="kWithGraphNodeCap" got="packSignatures" tgt="src/serialize.h:9754"/>
<a k="file-line" l="367" c="51" why="line-moved" ref="src/forpage.h:287" sym="kForPageRowsDefault" got="forCandidatePageDoc" tgt="src/forpage.h:75"/>
<a k="file-line" l="380" c="44" why="line-moved" ref="src/serialize.h:2460" sym="kFillOrderThreshold" got="writeRecentRows" tgt="src/serialize.h:1645"/>
<a k="file-line" l="382" c="62" why="line-moved" ref="src/main.cpp:1283" sym="kRecentRows" got="(file scope)" tgt="src/main.cpp:1229"/>
<a k="file-line" l="399" c="48" why="line-moved" ref="src/serialize.h:5317" sym="kMaxExpandSibs" got="shownDocsAboveCode" tgt="src/serialize.h:7853"/>
<a k="file-line" l="400" c="50" why="line-moved" ref="src/serialize.h:5342" sym="kMaxExpandIncludes" got="(file scope)" tgt="src/serialize.h:7862"/>
<more drift="4"/>
</doc>
<doc p="prompts/help-wanted/graph-unit-tests.md" anchors="164" checked="95" drift="8" dated="0">
<a k="file-line" l="96" c="6" why="range-straddles" ref="src/infra/Diagnostics.h:265-321" got="RW_CHECK_" tgt="src/infra/Diagnostics.h:321"/>
<a k="file-line" l="99" c="57" why="line-moved" ref="Diagnostics.h:543-550" sym="DISCLOSE" got="(file scope)" tgt="src/infra/Diagnostics.h:622"/>
<a k="file-line" l="132" c="18" why="range-straddles" ref="src/graph.h:2742-2755" sym="buildGraph" got="(file scope)" tgt="src/graph.h:2755"/>
<a k="file-line" l="155" c="17" why="line-moved" ref="src/graph.h:3228" sym="biasPrior" got="(file scope)" tgt="src/graph.h:14578"/>
<a k="file-line" l="170" c="3" why="line-moved" ref="src/graph.h:3915" sym="computeImpure" got="jsMemberRootWritten" tgt="src/graph.h:17765"/>
<a k="const" l="301" c="421" why="const-value" ref="maxIterationCount = 90" want="90" got="400" tgt="test/verify_pagerank.cpp:59"/>
<a k="const" l="301" c="510" why="const-value" ref="maxIterationCount = 89" want="89" got="400" tgt="test/verify_pagerank.cpp:59"/>
<a k="const" l="303" c="18" why="const-value" ref="maxIterationCount = 1" want="1" got="400" tgt="test/verify_pagerank.cpp:59"/>
</doc>
<doc p="CHANGELOG.md" anchors="1948" checked="805" drift="7" dated="15" shown_failed="12" failed_capped="1" failed_total="22">
<a k="file-line" l="1300" c="5" why="missing-file" kind="dated-record" rec="block" ref="cmd-split-window.c:58"/>
<a k="file-line" l="1432" c="43" why="missing-file" kind="dated-record" rec="block" ref="cmd-queue.c:625"/>
… [255 more display lines; full output is 25495 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --doc-drift --gateability`

*The finishable to-do list: docs whose LIVE failing anchors a date-stamp would reclassify.*

**wall time: 1.01s**

`````
<!-- ripwire doc-drift schema=ripwire.doc-drift/v1: markdown anchors that no longer hold: <doc p=> of <a k= l= c= why= ref= want= got= tgt=>; unchecked/dated rows disclose the rest. failed_capped=/weak_capped=: 1 = cut. at=: commit+dirty+shallow. next=: the one pasteable follow-up. docs=N: markdown docs scanned for anchors; docs minus clean = the doc rows. clean=N: docs with no failed anchor (drift and dated 0); not proof every anchor was checked. checked=N: anchors verified against the index; checked + unchecked = anchors. prose=N: value anchors dropped as prose (name not in code); subtracted from anchors=, never checked. corpus=N: files the anchors were checked against (index + config/build exts); 0 = no anchor shape, no scan. drift=/dated=: anchors that no longer hold / anchors skipped as dated (unverifiable by date). unchecked=N: anchors not proved (the unchecked rows give each reason); checked + unchecked = anchors. doc shown_failed=/failed_total=: a rows printed / all failed anchors (drift+dated); cut at 12, detail=1 lifts. a kind=/rec=: dated-record, an author-dated failed anchor in dated= / its evidence: line|block|title|stamp. a sym=: the symbol the doc names on that file:line; line-moved = that symbol no longer spans the line. more weak=N: w rows of this group withheld; shown_weak + N = its n=; detail=1 lists all. shown_weak=N: w rows printed of n= (cut at 12 a doc, weak_capped=1); detail=1 lists all. w resolves-to=: the indexed symbol spanning that line; not proof it is the one the doc meant. unchecked r=/note=: why n= anchors were not proved, and what was still checked for them. dated r=/note=: the dating mark that moved n= failed anchors into dated= instead of drift=. -->
<doc-drift schema="ripwire.doc-drift/v1" docs="351" clean="317" anchors="8233" checked="3894" unchecked="4339" drift="88" dated="135" prose="26" corpus="5004" at="6ace381eb" next="--doc-drift --detail=1">
<doc p="docs/research/answer-completeness.md" anchors="187" checked="84" drift="16" dated="0" shown_failed="12" failed_capped="1" failed_total="16">
<a k="file-line" l="341" c="25" why="line-moved" ref="src/pageview.h:292" sym="pageDisclosure" got="(file scope)" tgt="src/pageview.h:351"/>
<a k="file-line" l="349" c="99" why="line-moved" ref="src/serialize.h:4169" sym="kForLensDefaultTopN" got="serialize" tgt="src/serialize.h:1101"/>
<a k="file-line" l="353" c="89" why="line-moved" ref="src/serialize.h:4435" sym="kForPayloadBudgetBytes" got="packSource" tgt="src/serialize.h:990"/>
<a k="file-line" l="356" c="42" why="line-moved" ref="src/serialize.h:1010" sym="kForFileTailShownCap" got="forRunawayGuardNote" tgt="src/serialize.h:1178"/>
<a k="file-line" l="358" c="89" why="line-moved" ref="src/serialize.h:5481" sym="kForAnchorBodyBudgetBytes" got="(file scope)" tgt="src/serialize.h:1154"/>
<a k="file-line" l="360" c="88" why="line-moved" ref="src/serialize.h:5800" sym="kForCompactSurfaceBudgetBytes" got="SigsCutReport" tgt="src/serialize.h:1273"/>
<a k="file-line" l="366" c="43" why="line-moved" ref="src/serialize.h:6534" sym="kWithGraphNodeCap" got="packSignatures" tgt="src/serialize.h:9754"/>
<a k="file-line" l="367" c="51" why="line-moved" ref="src/forpage.h:287" sym="kForPageRowsDefault" got="forCandidatePageDoc" tgt="src/forpage.h:75"/>
<a k="file-line" l="380" c="44" why="line-moved" ref="src/serialize.h:2460" sym="kFillOrderThreshold" got="writeRecentRows" tgt="src/serialize.h:1645"/>
<a k="file-line" l="382" c="62" why="line-moved" ref="src/main.cpp:1283" sym="kRecentRows" got="(file scope)" tgt="src/main.cpp:1229"/>
<a k="file-line" l="399" c="48" why="line-moved" ref="src/serialize.h:5317" sym="kMaxExpandSibs" got="shownDocsAboveCode" tgt="src/serialize.h:7853"/>
<a k="file-line" l="400" c="50" why="line-moved" ref="src/serialize.h:5342" sym="kMaxExpandIncludes" got="(file scope)" tgt="src/serialize.h:7862"/>
<more drift="4"/>
</doc>
<doc p="prompts/help-wanted/graph-unit-tests.md" anchors="164" checked="95" drift="8" dated="0">
<a k="file-line" l="96" c="6" why="range-straddles" ref="src/infra/Diagnostics.h:265-321" got="RW_CHECK_" tgt="src/infra/Diagnostics.h:321"/>
<a k="file-line" l="99" c="57" why="line-moved" ref="Diagnostics.h:543-550" sym="DISCLOSE" got="(file scope)" tgt="src/infra/Diagnostics.h:622"/>
<a k="file-line" l="132" c="18" why="range-straddles" ref="src/graph.h:2742-2755" sym="buildGraph" got="(file scope)" tgt="src/graph.h:2755"/>
<a k="file-line" l="155" c="17" why="line-moved" ref="src/graph.h:3228" sym="biasPrior" got="(file scope)" tgt="src/graph.h:14578"/>
<a k="file-line" l="170" c="3" why="line-moved" ref="src/graph.h:3915" sym="computeImpure" got="jsMemberRootWritten" tgt="src/graph.h:17765"/>
<a k="const" l="301" c="421" why="const-value" ref="maxIterationCount = 90" want="90" got="400" tgt="test/verify_pagerank.cpp:59"/>
<a k="const" l="301" c="510" why="const-value" ref="maxIterationCount = 89" want="89" got="400" tgt="test/verify_pagerank.cpp:59"/>
<a k="const" l="303" c="18" why="const-value" ref="maxIterationCount = 1" want="1" got="400" tgt="test/verify_pagerank.cpp:59"/>
</doc>
<doc p="CHANGELOG.md" anchors="1948" checked="805" drift="7" dated="15" shown_failed="12" failed_capped="1" failed_total="22">
<a k="file-line" l="1300" c="5" why="missing-file" kind="dated-record" rec="block" ref="cmd-split-window.c:58"/>
<a k="file-line" l="1432" c="43" why="missing-file" kind="dated-record" rec="block" ref="cmd-queue.c:625"/>
… [286 more display lines; full output is 26922 bytes on 1 raw line(s)]
`````

Tail of the same output — the `<gateability>` section:

`````
<gateability docs="29" projected_drift="0">
<fix p="docs/research/answer-completeness.md" live="16"/>
<fix p="prompts/help-wanted/graph-unit-tests.md" live="8"/>
<fix p="CHANGELOG.md" live="7"/>
<fix p="test/docdriftfix/NOTES.md" live="7"/>
<fix p="THIRD_PARTY.md" live="6"/>
<fix p="changelog.d/uses-unarmed.md" live="4"/>
<fix p="docs/LSP.md" live="4"/>
<fix p="docs/QUALITY_PANEL.md" live="4"/>
<fix p="prompts/help-wanted/kotlin-scope-functions.md" live="4"/>
<fix p="changelog.d/touch-sym.md" live="3"/>
<fix p="CONTRIBUTING.md" live="2"/>
<fix p="changelog.d/callee-row-file.md" live="2"/>
<fix p="docs/COMMANDS.md" live="2"/>
<fix p="prompts/help-wanted/uses-qualified-selector.md" live="2"/>
<fix p="test/docdriftfix/live_notes.md" live="2"/>
<fix p="test/gateabilityfix/UNDATED.md" live="2"/>
<fix p="README.md" live="1"/>
<fix p="bench/nestcal/r1-2026-08-07/REPORT.md" live="1"/>
<fix p="changelog.d/qd-lessons-1.md" live="1"/>
<fix p="docs/EVALS.md" live="1"/>
<fix p="docs/LINEAGE.md" live="1"/>
<fix p="docs/OPTREMARKS.md" live="1"/>
<fix p="prompts/help-wanted/nesting-refusals-visible.md" live="1"/>
<fix p="prompts/help-wanted/scala-jvm-bridge.md" live="1"/>
`````

## `./build/ripwire . --doc-drift --with-history`

*Same report, with git history splitting stale mentions into deleted-by-commit vs never-existed.*

**wall time: 1.73s**

`````
<!-- ripwire doc-drift schema=ripwire.doc-drift/v1: markdown anchors that no longer hold: <doc p=> of <a k= l= c= why= ref= want= got= tgt=>; unchecked/dated rows disclose the rest. failed_capped=/weak_capped=: 1 = cut. at=: commit+dirty+shallow. next=: the one pasteable follow-up. docs=N: markdown docs scanned for anchors; docs minus clean = the doc rows. clean=N: docs with no failed anchor (drift and dated 0); not proof every anchor was checked. checked=N: anchors verified against the index; checked + unchecked = anchors. prose=N: value anchors dropped as prose (name not in code); subtracted from anchors=, never checked. corpus=N: files the anchors were checked against (index + config/build exts); 0 = no anchor shape, no scan. drift=/dated=: anchors that no longer hold / anchors skipped as dated (unverifiable by date). unchecked=N: anchors not proved (the unchecked rows give each reason); checked + unchecked = anchors. doc shown_failed=/failed_total=: a rows printed / all failed anchors (drift+dated); cut at 12, detail=1 lifts. a kind=/rec=: dated-record, an author-dated failed anchor in dated= / its evidence: line|block|title|stamp. a sym=: the symbol the doc names on that file:line; line-moved = that symbol no longer spans the line. more weak=N: w rows of this group withheld; shown_weak + N = its n=; detail=1 lists all. shown_weak=N: w rows printed of n= (cut at 12 a doc, weak_capped=1); detail=1 lists all. w resolves-to=: the indexed symbol spanning that line; not proof it is the one the doc meant. unchecked r=/note=: why n= anchors were not proved, and what was still checked for them. dated r=/note=: the dating mark that moved n= failed anchors into dated= instead of drift=. -->
<doc-drift schema="ripwire.doc-drift/v1" docs="351" clean="323" anchors="8233" checked="3874" unchecked="4359" drift="77" dated="126" prose="26" corpus="5004" at="6ace381eb" next="--doc-drift --detail=1">
<history probed="1" head="6ace381eb" commits="7313" removed-names="58797"/>
<doc p="docs/research/answer-completeness.md" anchors="187" checked="84" drift="16" dated="0" shown_failed="12" failed_capped="1" failed_total="16">
<a k="file-line" l="341" c="25" why="line-moved" ref="src/pageview.h:292" sym="pageDisclosure" got="(file scope)" tgt="src/pageview.h:351"/>
<a k="file-line" l="349" c="99" why="line-moved" ref="src/serialize.h:4169" sym="kForLensDefaultTopN" got="serialize" tgt="src/serialize.h:1101"/>
<a k="file-line" l="353" c="89" why="line-moved" ref="src/serialize.h:4435" sym="kForPayloadBudgetBytes" got="packSource" tgt="src/serialize.h:990"/>
<a k="file-line" l="356" c="42" why="line-moved" ref="src/serialize.h:1010" sym="kForFileTailShownCap" got="forRunawayGuardNote" tgt="src/serialize.h:1178"/>
<a k="file-line" l="358" c="89" why="line-moved" ref="src/serialize.h:5481" sym="kForAnchorBodyBudgetBytes" got="(file scope)" tgt="src/serialize.h:1154"/>
<a k="file-line" l="360" c="88" why="line-moved" ref="src/serialize.h:5800" sym="kForCompactSurfaceBudgetBytes" got="SigsCutReport" tgt="src/serialize.h:1273"/>
<a k="file-line" l="366" c="43" why="line-moved" ref="src/serialize.h:6534" sym="kWithGraphNodeCap" got="packSignatures" tgt="src/serialize.h:9754"/>
<a k="file-line" l="367" c="51" why="line-moved" ref="src/forpage.h:287" sym="kForPageRowsDefault" got="forCandidatePageDoc" tgt="src/forpage.h:75"/>
<a k="file-line" l="380" c="44" why="line-moved" ref="src/serialize.h:2460" sym="kFillOrderThreshold" got="writeRecentRows" tgt="src/serialize.h:1645"/>
<a k="file-line" l="382" c="62" why="line-moved" ref="src/main.cpp:1283" sym="kRecentRows" got="(file scope)" tgt="src/main.cpp:1229"/>
<a k="file-line" l="399" c="48" why="line-moved" ref="src/serialize.h:5317" sym="kMaxExpandSibs" got="shownDocsAboveCode" tgt="src/serialize.h:7853"/>
<a k="file-line" l="400" c="50" why="line-moved" ref="src/serialize.h:5342" sym="kMaxExpandIncludes" got="(file scope)" tgt="src/serialize.h:7862"/>
<more drift="4"/>
</doc>
<doc p="prompts/help-wanted/graph-unit-tests.md" anchors="164" checked="95" drift="8" dated="0">
<a k="file-line" l="96" c="6" why="range-straddles" ref="src/infra/Diagnostics.h:265-321" got="RW_CHECK_" tgt="src/infra/Diagnostics.h:321"/>
<a k="file-line" l="99" c="57" why="line-moved" ref="Diagnostics.h:543-550" sym="DISCLOSE" got="(file scope)" tgt="src/infra/Diagnostics.h:622"/>
<a k="file-line" l="132" c="18" why="range-straddles" ref="src/graph.h:2742-2755" sym="buildGraph" got="(file scope)" tgt="src/graph.h:2755"/>
<a k="file-line" l="155" c="17" why="line-moved" ref="src/graph.h:3228" sym="biasPrior" got="(file scope)" tgt="src/graph.h:14578"/>
<a k="file-line" l="170" c="3" why="line-moved" ref="src/graph.h:3915" sym="computeImpure" got="jsMemberRootWritten" tgt="src/graph.h:17765"/>
<a k="const" l="301" c="421" why="const-value" ref="maxIterationCount = 90" want="90" got="400" tgt="test/verify_pagerank.cpp:59"/>
<a k="const" l="301" c="510" why="const-value" ref="maxIterationCount = 89" want="89" got="400" tgt="test/verify_pagerank.cpp:59"/>
<a k="const" l="303" c="18" why="const-value" ref="maxIterationCount = 1" want="1" got="400" tgt="test/verify_pagerank.cpp:59"/>
</doc>
<doc p="test/docdriftfix/NOTES.md" anchors="30" checked="21" drift="7" dated="0">
<a k="file-line" l="9" c="64" why="line-moved" ref="code.h:23" sym="stableHelper" got="movedHelper" tgt="test/docdriftfix/code.h:17"/>
… [231 more display lines; full output is 25545 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --from-trace=-`

*Map a pasted stack trace onto indexed symbols. CHANGED: in_corpus= now reports the real count (was 0).*

Input file:

`````
AddressSanitizer:DEADLYSIGNAL
=================================================================
==41337==ERROR: AddressSanitizer: SEGV on unknown address 0x000000000018 (pc 0x000102f4a1c8 bp 0x00016d2f1a40 sp 0x00016d2f19e0 T0)
    #0 0x102f4a1c8 in rw::rankGraphTeleport(Graph const&, std::vector<float> const&, float) src/graph.h:14621
    #1 0x102f3e884 in rw::rankGraph(Graph const&, float) src/graph.h:14664
    #2 0x102e11f30 in runDefaultMap(MainDispatch const&) src/main.cpp:1760
    #3 0x102e01a44 in main src/main.cpp:4511
    #4 0x1a2b3c0dc in start+0x9dc (dyld:arm64e+0x60dc)
==41337==ABORTING
`````

`````
<ctx schema="ripwire.from-trace/v1" task="&lt;stdin&gt;" next="--slice=@src/graph.h:14621" est_tokens="2112">
<!-- ripwire from-trace schema=ripwire.from-trace/v1: trace frames mapped to indexed symbols, innermost first; the innermost in-corpus body included. window: shown= total= capped= (capped=1 cut). est_tokens=: price as emitted (an upper bound under compact). <d r=N>: rank N in this ranking, rows in r= order. <d cx= ccx=>: cyclomatic/cognitive complexity. <d in=N>: N callers in the index (absent: not measured). sc=: enclosing scope; the full id is p::sc::n (p= of the row or its <f>) and selectors take it. next=: the one pasteable follow-up. task=: the trace source this bundle maps, verbatim (a file path, stdin, or an MCP label). src=/format=: the trace read and its dominant frame format, python|asan|node|compiler|generic. frame_lines=/parsed=: frame-shaped input lines / those yielding a path:line; the rest matched no format. in_corpus=: parsed frames in indexed files; always suspects= + merged= + unresolved=. suspects=/merged=/unresolved=: frame rows / folded into a claimed symbol / unresolved rows (indexed file, no def). skipped=N: frames outside every root, listed as skipped rows, never ranked. rank=N: frame order, innermost in-corpus first; p= is the trace's own path:line, defs are sigs l=. resolved_by=name|line: bound by the frame's own name, else by the def enclosing its line. innermost=1: the innermost in-corpus frame (rank 1); its full body is served. frame n= t=: the bound symbol's name and kind (fn|cls|...); d, b and c n=: a ranked row's, a body's, a callee's name. -->
<!-- ledger: budget=7500 bytes (allowance 9583 bytes = ceiling + the single-entry overshoot a whole first signature costs) -->
<trace src="&lt;stdin&gt;" format="asan" frame_lines="5" parsed="4" in_corpus="4" skipped="0" merged="0" unresolved="0" suspects="4">
<frame rank="1" n="rankGraphTeleport" t="fn" p="src/graph.h:14621" resolved_by="name" innermost="1"/>
<frame rank="2" n="rankGraph" t="fn" p="src/graph.h:14664" resolved_by="name"/>
<frame rank="3" n="runDefaultMap" t="fn" p="src/main.cpp:1760" resolved_by="name"/>
<frame rank="4" n="main" t="fn" p="src/main.cpp:4511" resolved_by="name"/>
</trace>
<sigs>
<d l="14619" n="rankGraphTeleport" sc="rw" p="src/graph.h" cx="5" ccx="8" in="7" r="1" next="--expand=src/graph.h:rankGraphTeleport">
<doc>PageRank with an explicit teleport / personalization vector p (Σp = 1). The prior is name-quality-biased through biasPrior() so all rank modes share one weighting seam; the transition matrix (edges</doc>inline RankedGraph rankGraphTeleport( const Graph&amp; g, const std::vector&lt;float&gt;&am … [line truncated: 31 more bytes on this line]
<d l="14662" n="rankGraph" sc="rw" p="src/graph.h" cx="2" ccx="1" in="13" r="2">
<doc>uniform-teleport PageRank (the default). A kRankFlagNotNamed unit (model.h) has no edge and a 0 prior weight, so the uniform share is over the ranked nodes: every other node&apos;s teleport is the value it</doc>inline RankedGraph rankGraph( const Graph&amp; g, float alpha = 0.85f )</d>
<d l="1758" n="runDefaultMap" p="src/main.cpp" cx="224" ccx="313" in="1" r="3">int runDefaultMap( const MainDispatch&amp; d )</d>
<d l="4509" n="main" p="src/main.cpp" cx="13" ccx="10" in="0" r="4">int main( int argc, char** argv )</d>
</sigs>
<bodies shown="1" total="1" capped="0">
<b t="fn" l="14619" p="src/graph.h" n="rankGraphTeleport">
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
… [18 more display lines; full output is 5279 bytes on 29 raw line(s)]
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
<ctx schema="ripwire.pack-task/v1" task="add a new output format flag to the CLI" route="subtoken+body:declined(add;205-carriers,69-defs)" root="." est_tokens="3150" budget_tokens="6000">
<!-- ripwire pack-task schema=ripwire.pack-task/v1: one-call task bundle for task= under budget_tokens=: <sigs>
<d n= sc= l= p=> ranking, <far>
<s t= n= p=> ranked but over 1 hop out (of_top= ranked rows) > <bodies>
<b t= n= p= l=> with <calls>
<c n= l= p=> callees > <callers>
<s rel=caller|callee shared=> 1-hop from the bodies (of_top= bodies; shared= bodies reached, absent at 1) > notes > <tests>
<test p= run=> (run= when derivable). window: shown= total= capped= (capped=1 cut). est_tokens=: price as emitted (an upper bound under compact). root=: p= relative to it. <d r=N>: rank N in this ranking, rows in r= order. <d cx= ccx=>: cyclomatic/cognitive complexity. <d in=N>: N callers in the ind … [line truncated: 485 more bytes on this line]
<!-- ledger: budget=12744 bytes (6000-token target, ceiling 14160) | ranking: full | bodies: kept 5 of 6 (capped) | callers: 11 of 11 | notes: none | tests: none | far: 6 of 6 -->
<sigs>
<d l="3288" n="printUsage" sc="rw" p="src/cli.h" cx="1" ccx="0" in="1" r="1" next="--expand=src/cli.h:printUsage">
<doc>Print the authoritative CLI usage and flag catalog to the caller-provided output stream</doc>inline void printUsage( std::FILE* out ) noexcept</d>
<d l="490" n="wrapCliAddPost" sc="rw" p="src/wrap.h" cx="4" ccx="2" in="1" r="2">
<doc>claude&apos;s `mcp add … -- ripwire --mcp`: the flag goes on the end of that command line, ahead of its newline</doc>inline std::string wrapCliAddPost( const AgentTarget&amp; row, std::string_view toolsArg )</d>
<d l="111" n="AgentTarget" sc="AgentTarget" p="src/wrap.h" cx="0" ccx="0" in="0" r="3">struct AgentTarget</d>
<d l="746" n="wrapEmitCliFirst" sc="rw" p="src/wrap.h" cx="10" ccx="5" in="1" r="4">
<doc>ONE recipe path for every agent that can shell out, and the point is that the RECOMMENDATION does not vary by agent — only the MCP alternative does. Before this there were four near-identical CLI-fi</doc>inline void wrapEmitCliFirst( const AgentTarget&amp; row, const std::string&amp; token, c … [line truncated: 83 more bytes on this line]
<d l="473" n="wrapWritesToolsArg" sc="rw" p="src/wrap.h" cx="6" ccx="1" in="3" r="5">
<doc>mcp-tools pass-through. Written into the server command only where its argument shape is known to be one more plain argument: the JSON args arrays (cursor/windsurf/gemini), opencode&apos;s command array</doc>inline bool wrapWritesToolsArg( const AgentTarget&amp; row ) noexcept</d>
<d l="3592" n="kJsonShapeModifiers" p="src/main.cpp" cx="0" ccx="0" in="0" pure="1" r="6">
<doc>B1.4: the output-SHAPE members of the list above, as a table rather than a second if-chain. A flag in here selects an ENCODING for rows some verb already produced, so &quot;--json is not supported for X</doc>inline constexpr std::string_view kJsonShapeModifiers[] =</d>
<far of_top="12" shown="6" total="6" capped="0">
<s t="fn" n="classNewGroupXml" p="src/testmap.h:2051"/>
<s t="fn" n="cliRefusesFileList" p="src/situ.h:213"/>
<s t="fn" n="callHierarchyPageNext" p="src/nextverb.h:216"/>
<s t="fn" n="fileSubjectNote" p="src/forfilepage.h:711"/>
<s t="fn" n="toUint" p="src/tracein.h:103"/>
<s t="cls" n="McpValueSpec" p="src/mcprefusal.h:268"/>
</far>
</sigs>
… [54 more display lines; full output is 9043 bytes on 46 raw line(s)]
`````

## `./build/ripwire . --pack-task="add a new output format flag to the CLI" --partition=3`

*Fan-out form: one shared core + 3 per-agent slices carved along call-graph communities.*

**wall time: 1.27s**

`````
<ctx-partitions schema="ripwire.pack-task/v1" partitions="3" requested="3" core_symbols="6" surface="42" modules="19" split="0" budget_per_agent_tokens="6000" core_budget_tokens="2040" partition_budget_tokens="3960" total_bytes="21985" overlap_mean="0.006" overlap_max="0.017" shared_symbols="1" unio … [line truncated: 36 more bytes on this line]
<!-- ripwire pack-task schema=ripwire.pack-task/v1: N minimally overlapping agent bundles carved along call-graph communities plus one shared core; each <bundle> wraps a <ctx>; bundle role=core|partition i= symbols= modules= bytes= tokens=: one agent's ctx, symbols= ids assigned, bytes= its size; tokens= = est_tokens= = bytes/2.36 (flat, the densest rate; the inner ctx est_tokens= is language-weighted). Inner ctx task= root= budget_tokens= dropped_positive=: the task, p= base, the slice's token target, ranked candidates its budget cut. of_top=: rows ranked (far) / bodies (callers); s rel=caller|callee shared=: 1-hop edge, bodies reached (absent at 1). window: shown= total= capped= (capped=1 cut). run_unknown=1: no runner derivable (a guess would be worse). est_tokens=: price as emitted (an upper bound under compact). <d r=N>: rank N in this ranking, rows in r= order. <d cx= ccx=>: cyclomatic/cognitive complexity. <d in=N>: N callers in the index (absent: not measured). route=: the ranker: name-exact(X) = the task names symbol X (anchors: its evidence), subtoken+body = conceptual BM25 (:broad = 1-2 plain words, plain rg may also win; :declined(...) = a name hit refused as a common name). sc=: enclosing scope; the full id is p::sc::n (p= of the row or its <f>) and selectors take it. next=: the one pasteable follow-up. pure=1: const/constexpr signature (Swift: non-mutating) and no transitive side effect found; a hint. partitions=/requested=: partitions carved / asked for. modules=/split=: call-graph groups found / cuts forced to split one. core_symbols=/surface=: ids in the shared core / core plus the assignable remainder. budget_per_agent_tokens=: one agent's budget, core_budget_tokens= plus partition_budget_tokens=. total_bytes=N: bytes of all bundles together. overlap_mean=/overlap_max=: pairwise Jaccard over the ids partitions name, before trimming. shared_symbols=/union_symbols=: ids two or more partitions name / ids any partition names. core_overlap=: share of the core surface a partition reaches anyway. c p=: the file a body callee's l= is in, printed when it is not the b row's own (no p=: the b's file). -->
<bundle role="core" symbols="6" bytes="2738" tokens="1160" est_tokens="1160">
<ctx task="add a new output format flag to the CLI" route="subtoken+body:declined(add;205-carriers,69-defs)" root="." dropped_positive="2" est_tokens="938" budget_tokens="2040">
<!-- slice budget=4332 bytes (2040-token target, ceiling 4814) | ranking: capped | bodies: kept 2 of 6 (capped) | callers: kept 1 of 11 | notes: none | tests: none | far: none -->
<sigs shown="4" total="6" capped="1">
<d l="3288" n="printUsage" sc="rw" p="src/cli.h" cx="1" ccx="0" in="1" r="1" next="--expand=src/cli.h:printUsage">
<doc>Print the authoritative CLI usage and flag catalog to the caller-provided output stream</doc>inline void printUsage( std::FILE* out ) noexcept</d>
<d l="490" n="wrapCliAddPost" sc="rw" p="src/wrap.h" cx="4" ccx="2" in="1" r="2">
<doc>claude&apos;s `mcp add … -- ripwire --mcp`: the flag goes on the end of that command line, ahead of…</doc>inline std::string wrapCliAddPost( const AgentTarget&amp; row, std::string_view toolsArg )</d>
<d l="111" n="AgentTarget" sc="AgentTarget" p="src/wrap.h" cx="0" ccx="0" in="0" r="3">struct AgentTarget</d>
<d l="746" n="wrapEmitCliFirst" sc="rw" p="src/wrap.h" cx="10" ccx="5" in="1" r="4">
<doc>ONE recipe path for every agent that can shell out, and the point is that the RECOMMENDATION doe…</doc>inline void wrapEmitCliFirst( const AgentTarget&amp; row, const std::string&amp; token, const std::string_view executablePath, const WrapListing&amp; listing ) noexcept</d>
</sigs>
<bodies shown="2" total="6" capped="1">
<b t="fn" l="3288" p="src/cli.h" n="printUsage">
<![CDATA[inline void printUsage( std::FILE* out ) noexcept { printUsageTier( out, HelpTier::Full, {} ); }]]>
<calls total="1">
<c n="printUsageTier" l="3278">inline bool printUsageTier( std::FILE* out, HelpTier tier, std::string_view want ) noexcept</c>
</calls>
</b>
<b t="fn" l="490" p="src/wrap.h" n="wrapCliAddPost">
<![CDATA[inline std::string wrapCliAddPost( const AgentTarget& row, std::string_view toolsArg )
{
    std::string post( row.mcpAddPost );
    if( !toolsArg.empty() && wrapWritesToolsArg( row ) && post.ends_with( '\n' ) )
    {
        post.insert( post.size() - 1, " " + std::string( toolsArg ) );
    }
    return post;
… [128 more display lines; full output is 24903 bytes on 136 raw line(s)]
`````

## `./build/ripwire . --for="pagerank power iteration" --with-graph`

*Task lens + a compact Mermaid flowchart of the top anchors' 1-hop edges.*

**wall time: 1.66s**

`````
<ctx task="pagerank power iteration" route="subtoken+body" root="." confidence="high" margin_pct="22" at="6ace381eb" doc_mentions="4" schema="ripwire.for/v1" bundle="compact" bodies="0" reason="compact-route" budget_bytes="7500" doc_mentions_capped="1" doc_mentions_total="14" est_tokens="8305">
<!-- ripwire for schema=ripwire.for/v1: bundle=/bodies=/reason= the body posture; d: cx= ccx= complexity, in= callers (absent cx/ccx/in = 0), churn= amp= change, clone= tested= 1, sc= scope, id=p::sc::n; total= shown= capped=1 if cut; task= the query; d pure=1 const/constexpr sig, next= the follow-up to paste; d same_as=N: doc+sig text as row n=N (not repeated); route= name-exact(X)|subtoken+body[:broad|:declined]; confidence=/margin_pct= head score drop (low=flat); h l= p= n=, c n= l= p= (p= if not h's; same-named joined, shown= counts them), noedge= no callee resolved; fold kind=bodies: b t= n= p= l= top ranked rows' whole bodies, not the answer; served= of total= in budget_bytes=; slice/skip p= n= l=; skip bytes= next=; a skip makes sigs next= it, sigs_next= the signatures-only re-call; d mem= an owner's direct member names only, by the index (question words first, then owner's file, path, line, name), mem_more= names cut; t p= file outside sigs (weaker), t sym= its top symbols not in sigs/syms (a pointer, not the answer), r= rank (gap = trimmed); t tsym= up to 2 more file symbols named by a task word (a name match); t order: code files first, then doc files (a code question); t page rows go on to file-page row 160 (code question: 160 code rows, docs within row 160); past page 0 (code question: past 40 code rows, a doc past row 40) listed last, head files skipped; past 120 of those p= only, p_only= counts them; t folded=class=N: N p= only rows of that class (doc|config|script|testdata|other) not listed, next= pages to them; d layer=: built-in arch layer (game|infra|render|math|audio|ai|test) from a dir name in p=; d e= its last line (absent=unknown, never 0; l= the name's line); c prov=split: a resolver split arm; may be another arm's (NOT a claim the edge is false) [doc mentions: 4 docs, 2 symbols; doc_mentions=] -->
<!-- root= is the crawl root; p= below is RELATIVE to it (single-root only; absent => p= is ingest's own path, unchanged); at=this commit(+dirty). [budget_bytes= is the default BYTE target this ranked payload was shaped toward: row text shortens toward it, no row of the ranked head is removed for it (sigs past_target=)] [sigs capped=1 with shown=total: rows shrunk, none dropped] [sigs past_target=K: the last K rows are past the budget_bytes target, served because they are rows of the ranked head; none is cut] [sigs sigs_next=: one call serving all total= rows uncut] [docs_dropped=N: N shown rows have a doc comment not printed (r>24 always, r5..24 if capped)] [docs_after_code=N: N doc rows of the shown set moved below its code rows; same rows, reordered, none added or removed; a question naming docs keeps score order] [files_first=N: N rows moved so r=1..8 are distinct files' best rows, score order, a repeated name once; same rows; fold, hops keep score order] [cut: doc_mentions_capped="1" doc_mentions_total="14" — an indexing cap dropped content not shown here]; lego/compose collapse to a counted stub by default (a disclosed cut): total= that section's own pre-cap row count, shown="0" capped="1" (nothing rendered here), next= names the sections=lego,compose flag that restores both sections byte-identically in one call est_tokens= prices this bundle in tokens -->
<sigs shown="40" total="40" capped="1" past_target="14" docs_dropped="25" docs_after_code="5" files_first="7" sigs_next="--for='pagerank power iteration' --signatures-only --token-budget=6200" next="--expand=src/prconverge.h:73:renderDisclosure">
<d l="422" e="422" n="kScoreTieAbsEps" sc="rw" p="src/eval.h" churn="18" amp="51" pure="1" r="1" next="--expand=src/eval.h:kScoreTieAbsEps">
<doc>NodeId order. Renumbering an otherwise-identical graph (the exact &quot;same probe file, different so…</doc>inline constexpr float kScoreTieAbsEps = 1e-6f</d>
<d l="51" e="56" n="RankDisclosure" sc="RankDisclosure" p="src/prconverge.h" churn="3" amp="27" r="2">
<doc>What a ranked document discloses about the power iteration that ordered it. `isPageRank == false…</doc>struct RankDisclosure</d>
<d l="99" e="206" n="pageRankDouble" sc="rw" p="src/pagerank.cpp" cx="19" ccx="34" in="2" churn="14" amp="44" tested="1" r="3">
<doc>The PageRank power iteration itself — the numeric kernel every ranked document&apos;s order comes f…</doc>PageRankRun pageRankDouble( const sparseCsr&lt;float&gt;&amp; inEdges, std::span&lt;const double&gt; weightedOutDegree, std::span&lt;const double&gt; teleport, std::span&lt;double&gt; r … [line truncated: 10 more bytes on this line]
<d l="503" e="549" n="rankByText" sc="rw" p="src/mcpverbs.h" cx="11" ccx="19" in="1" churn="675" amp="692" r="4">inline std::string rankByText( const std::string&amp; root, std::string_view mode, int topK, bool stable = false )</d>
<d l="14610" e="14615" n="RankedGraph" sc="RankedGraph" p="src/graph.h" churn="713" amp="977" r="5">struct RankedGraph</d>
<d l="2568" e="2572" n="kChurnRankLegend" sc="rw" p="src/serialize.h" churn="515" amp="626" pure="1" r="6">inline constexpr const char* kChurnRankLegend = &quot;&lt;!-- rank_by=churn: k= is PageRank re-run with the teleport BIASED by git CHANGE-FREQUENCY over window= &quot; &quot;(a c…</d>
<d l="1372" e="1393" n="sliceRdIterationCeiling" sc="slicev" p="src/slice.h" cx="9" ccx="12" in="1" churn="54" amp="103" r="7">inline std::uint32_t sliceRdIterationCeiling() noexcept</d>
<d l="31" e="44" n="PageRankRun" sc="PageRankRun" p="src/pagerank.h" churn="8" amp="37" r="8" mem="disclose">struct PageRankRun</d>
<d l="73" e="144" n="renderDisclosure" sc="rw" p="src/prconverge.h" cx="12" ccx="15" in="14" churn="3" amp="41" r="9">
<doc>Render one form of the disclosure. Empty string whenever there is nothing to say — no power it…</doc>inline std::string renderDisclosure( const RankDisclosure&amp; d, DiscloseAs as )</d>
<d l="17898" e="17907" n="navRelevanceWeight" sc="rw" p="src/graph.h" cx="2" ccx="1" in="2" churn="713" amp="979" r="10">inline std::uint32_t navRelevanceWeight( const Graph&amp; g, NodeId n ) noexcept</d>
<d l="14619" e="14647" n="rankGraphTeleport" sc="rw" p="src/graph.h" cx="5" ccx="8" in="7" churn="713" amp="984" r="11">inline RankedGraph rankGraphTeleport( const Graph&amp; g, const std::vector&lt;float&gt;&amp; p, float alpha = 0.85f )</d>
<d l="1247" e="1247" n="kPowerShellPathPrependScope" sc="rw::oswin" p="src/infra/os_win32_logic.h" layer="infra" churn="20" amp="50" pure="1" r="12">inline constexpr std::string_view kPowerShellPathPrependScope = &quot;in PowerShell, for this window</d>
<!-- demote: a <t> in sigs is a lower same-file sibling past answer row 10, a pointer (p= file, sym= name, r= rank), not the answer -->
<t p="src/infra/os_win32_logic.h" sym="powerShellPathPrependHint" r="13"/>
<d l="1255" e="1255" n="path_prepend_hint" sc="rw::os" p="src/infra/os.h" layer="infra" cx="1" in="1" churn="43" amp="94" r="14">inline std::string path_prepend_hint( std::string_view dir )</d>
<t p="src/infra/os_win32_logic.h" sym="powerShellSingleQuote" r="15"/>
<d l="2198" e="2206" n="dynamic_map::leftmost_leaf" p="src/infra/dynamic_map.hpp" layer="infra" cx="2" ccx="1" in="7" churn="7" amp="38" pure="1" r="16">handle_t leftmost_leaf() const</d>
<d l="58" e="91" n="HOT_FILES" p="scripts/optremarks.py" churn="19" amp="84" r="17">HOT_FILES = ( &quot;src/pagerank.cpp&quot;, # the power-iteration loop — G2&apos;s no-allocation scope &quot;src/infra/radixSort.h&quot;, # LSD radix entry points &quot;src/infra/radixSort.inl&quot;, # the counting … [line truncated: 76 more bytes on this line]
<d l="294" e="299" n="doctorPathPrependLine" p="src/verbs_doctor.h" cx="2" ccx="1" in="2" churn="51" amp="151" r="18">inline std::string doctorPathPrependLine( const std::string&amp; selfPath )</d>
<t p="src/infra/dynamic_map.hpp" sym="reverse_iterator" r="19"/>
<t p="src/verbs_doctor.h" sym="doctorWhichRipwire" r="20"/>
<t p="src/serialize.h" sym="rankByLegendFor" r="21"/>
… [166 more display lines; full output is 20878 bytes on 15 raw line(s)]
`````

## `./build/ripwire . --export=cc.json:<scratch>/aux/ripwire2.cc.json`

*Per-file metrics as CodeCharta cc.json.*

**wall time: 1.81s**

`````
(empty)
`````

Artifact written:

`````
  739992 <scratch>/aux/ripwire2.cc.json
{"projectName":"project","apiVersion":"1.3","attributeDescriptors":{"loc":{"title":"Lines of Code","description":"Physical line count","direction":-1},"symbols":{"title":"Symbols","description":"Definitions in the file","direction":-1},"cx":{"title":"Cyclomatic Complexity","description":"Sum of per-symbol cyclomatic complexity","direction":-1},"cognitive_cx":{"title":"Cognitive Complexity","descri
`````

## `./build/ripwire . --batch=<scratch>/aux/batch2.txt`

*One-turn sweep: 4 newline-delimited verb:arg sub-queries answered in ONE deduped <batch>.*

**wall time: 3.51s**

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
<![CDATA[<ctx task="incremental cache invalidation" route="subtoken+body" root="." confidence="low" margin_pct="0" at="6ace381eb" doc_mentions="3" bundle="sigs" lens="churn,amp,tested" budget_bytes="7500" est_tokens="9864">
<!-- ripwire lens for "incremental cache invalidation" [doc mentions: 3 docs discussing 2 top-ranked symbols surfaced; doc_mentions= on the root repeats the doc count]: reusable building blocks (cx=complexity, in=reuse-count; an absent cx/ccx/in is 0) — prefer composing/reusing these over reimplementing; sc=scope (full id p::sc::n); route= name-exact(X)|subtoken+body[:broad|:declined]; bundle=sigs: signatures only in this bundle, no inline bodies — fetch a symbol's full body with the fetch_body verb [confidence= derives from the ranked head's largest relative score drop (margin_pct=, whole percent, 0 = none; the same gap the adaptive flag cuts at). low = flat ranking: treat the set as a starting point, not an answer]; lens="churn,amp,tested": the three per-row quality columns the CLI for lens carries and this dialect does NOT (they need a git and a quality pass this server does not run per request); an absent column here means NOT MEASURED, never measured-and-zero; est_tokens= prices this bundle in tokens; tail: file-grain rows, WEAKER evidence than the ranked rows: first the positive-score files NOT among the shown sigs rows, the files of trimmed rows first, best-symbol rank order; then the file page's first 40 rows not listed above, file-first (the IDF share of the query's subtokens its top 8 symbols cover); sym= its top symbols by lens rank, minus names a sigs row or the syms block shows (a pointer, not the answer); total=every positive-score file, shown=printed, capped=1 when they differ, next= the page from its first unprinted row. r= on a ranked row is its 1-based rank in this lens ranking, rows in r= order, p= the file (a gap = a budget-trimmed row); tail order on this code question: every code file of both parts first, each part in the order above, then the doc files (.md, .rst, a Sphinx .txt page) in that order; tail walk: the page rows go on to the file page's first 160 rows (a code question: its first 160 code rows, plus the doc rows within its first 160 rows); a row past page 0 (a code question: past its first 40 code rows, a doc past row 40) comes after every page 0 row, skips files the head shows and carries sym= too; past 120 such rows p= only, p_only= counts them; tail folded=class=N: on a code question, N rows past page 0 of that file class (doc, config, script, testdata, other) are not listed, unless the task names the class (adding a new X, or a quoted message, keeps doc and config); next= pages from the first one; e= on a d row: the 1-based line where that definition ends, body-inclusive; absent when the extent is not known (extent_suspect, docs, config), never 0; l= is the line of the definition's name, so a definition can start above l=; lego/compose collapse to a counted stub by default (a disclosed cut): total= that section's own pre-cap row count, shown="0" capped="1" (nothing rendered here), next= names the sections=lego,compose flag that restores both sections byte-identically in one call -->
<!-- root= is the crawl root; p= below is RELATIVE to it (single-root only; absent => p= is ingest's own path, unchanged); at=this commit(+dirty). [budget_bytes= is the default BYTE target this ranked payload was shaped toward: row text shortens toward it, no row of the ranked head is removed for it (sigs past_target=)] [sigs capped=1 with shown=total: rows shrunk, none dropped] [sigs past_target=K: the last K rows are past the budget_bytes target, served because they are rows of the ranked head; none is cut] [sigs next_budget_tokens=: call this tool again with that budget_tokens to get all total= rows uncut] [docs_dropped=N: N shown rows have a doc comment not printed (r>24 always, r5..24 if capped)] [docs_after_code=N: N doc rows of the shown set moved below its code rows; same rows, reordered, none added or removed; a question naming docs keeps score order] [files_first=N: N rows moved so r=1..8 are distinct files' best rows, score order, a repeated name once; same rows; fold, hops keep score order] -->
<!-- <d cx= ccx=>: cyclomatic/cognitive complexity. layer=: built-in arch layer (game|infra|render|math|audio|ai|test) from a dir name in p=; absent if none. task=: the query. d n= l=: the symbol's name and def line. d pure=1: const/constexpr signature (Swift: non-mutating) and no transitive side effect found; a hint. -->
<sigs shown="40" total="40" capped="1" past_target="10" docs_dropped="14" docs_after_code="1" files_first="9" next_budget_tokens="5700">
<d l="153" e="153" n="kCacheMagic" p="src/ingest_cache.h" pure="1" r="1" next="--expand=src/ingest_cache.h:kCacheMagic">
<doc>incremental cache (--cache): per-file content hash + raw facts so a re-run re-parses ONLY      c…</doc>constexpr std::uint32_t kCacheMagic = 0x4b505443</d>
<d l="1588" e="1593" n="spanTierMemoPath" sc="rw" p="src/ingest_astquery.h" cx="1" in="3" r="2">
<doc>Composed exactly the way every OTHER blob family is (quality.h): one fixed-width identity hex pe…</doc>inline std::string spanTierMemoPath( const std::string&amp; diskPath )</d>
<d l="906" e="909" n="mcpRefreshedThisRequest" sc="rw" p="src/mcpindex.h" cx="1" in="2" r="3">
<doc>P1-15 — the `_reingest` envelope field for a response whose handling ran an INCREMENTAL pass, …</doc>inline bool mcpRefreshedThisRequest( std::uint64_t passesAtEntry )</d>
<d l="277" e="306" n="ingestCommitTree" sc="rw::dmm" p="src/dmm.h" cx="6" ccx="5" in="1" r="4">
<doc>Ingest the tree at `sha`, materialized out of `root`&apos;s object store. The HEAD side reuses the SA…</doc>inline bool ingestCommitTree( const std::string&amp; root, const std::string&amp; sha, const std::vector&lt;std::string&gt;&amp; excludes, std::size_t maxFileBytes, IngestResult&amp;… … [line truncated: 4 more bytes on this line]
<d l="2495" e="2510" n="FileHealth" sc="FileHealth" p="src/model.h" r="5">struct FileHealth</d>
<d l="10002" e="10033" n="legoImplementorsOnSurface" sc="rw" p="src/serialize.h" cx="10" ccx="13" in="2" r="6">inline std::vector&lt;std::vector&lt;NodeId&gt;&gt; legoImplementorsOnSurface( const IngestResult&amp; ing, const std::vector&lt;std::vector&lt;NodeId&gt;&gt;&amp; implementors, const std:: … [line truncated: 10 more bytes on this line]
<d l="5383" e="5493" n="computeHeadSnapshot" sc="quality" p="src/quality.h" cx="19" ccx="21" in="3" r="7">inline std::pair&lt;Snapshot, bool&gt; computeHeadSnapshot( const std::string&amp; root, const std::string_view* cacheNever = nullptr, std::size_t maxFileBytes = kDefault…</d>
<d l="1006" e="1212" n="runParsePool" p="src/ingest_parsepool.h" cx="25" ccx="54" in="1" r="8">inline RawFacts runParsePool( IngestResult&amp; result, const char* rootDir, std::string_view cacheFile, bool captureValueUses, CacheRecords&amp; cache, const CacheLoadStats&amp; cacheStats, IngestFileScan … [line truncated: 62 more bytes on this line]
<d l="779" e="786" n="mcpRebuildBaseline" sc="rw" p="src/mcpindex.h" cx="2" ccx="1" in="1" r="9">inline McpRebuildBaseline mcpRebuildBaseline( const McpIndex&amp; ix, bool isIncrementalPass )</d>
<d l="938" e="945" n="mcpFreshFields" sc="rw" p="src/mcpindex.h" cx="2" ccx="1" in="1" r="10">inline std::string mcpFreshFields( std::uint64_t passesAtEntry )</d>
<!-- demote: a <t> in sigs is a lower same-file sibling past answer row 10, a pointer (p= file, sym= name, r= rank), not the answer -->
<t p="src/mcpindex.h" sym="getIndex" r="11"/>
<t p="src/mcpindex.h" sym="McpIndex" r="12"/>
<d l="1102" e="1115" n="receiptNextFor" sc="mcpedit" p="src/mcpedit.h" cx="4" ccx="3" in="1" r="13">inline std::string receiptNextFor( const std::string&amp; fileIdentity, const std::string&amp; symbolName, const std::string&amp; foldJson, const std::string&amp; firstTestRun )</d>
<d l="177" e="186" n="AncestorCacheScope::AncestorCacheScope" p="src/infra/tsparent.h" layer="infra" cx="2" ccx="1" r="14">AncestorCacheScope( TSNode root, bool enabled ) : previous( tAncestorCache )</d>
<t p="src/infra/tsparent.h" sym="AncestorCacheScope" r="15"/>
<d l="240" e="243" n="cacheArtifactVerdict" sc="rw" p="src/ingest.cpp" cx="1" in="1" r="16">const char* cacheArtifactVerdict( const std::string&amp; path, bool captureValueUses )</d>
<d l="27" e="31" n="parentCacheOn" p="src/ingest_sidecap.h" cx="1" r="17">inline bool parentCacheOn()</d>
… [236 more display lines; full output is 60649 bytes on 1 raw line(s)]
`````


---

# self-diagnosis

## `./build/ripwire . --doctor`

*Environment self-check: binary staleness, grammars, cache dir, git, tracked-binary staleness — exit 1 when any check fails (here: the PATH install is older than ./build).*

**exit code: 1** — **wall time: 11.23s**

`````
<!-- ripwire doctor schema=ripwire.doctor/v1: setup health: <c n= ok=> checks; exit 1 when one fails. at=: commit+dirty+shallow. n=: the check's name (binary-path, grammars, cache-dir, git, tree-sitter, index-cache, layout ...). loaded=/expected=: grammars whose tags query compiled / grammars compiled in; a shortfall fails the row. dir=: the per-user cache directory scanned (TMPDIR/XDG_CACHE_HOME ladder); unwritable fails the row. blobs=N: ripwire cache blobs in dir=; the scan stops at 4096 (blobs_floor=1 then). bytes=N: total size in bytes of the blobs counted (short when truncated=1). many=1: more than 50 blobs; an eviction-sanity flag, informational, never fails the row. truncated=1: cache-dir, blob scan cut (cap or I/O error); tracked-binaries, scan SKIPPED, stale=0 unmeasured. locks=N: advisory edit-lock files under locks/; unheld ones over a day old are swept on a cache write. volatile=: this row's attributes that read LIVE machine state; a determinism diff strips them, never the row. git=0|1: git runs from PATH; 0 fails the row (churn verbs need it). repo=0|1: the root is inside a git work tree; 0 is a diagnosis, not a failure. history=0|1: the repo has at least one commit; head= prints only when it does. head=: HEAD's short sha (9 hex, the at= width). core_abi=/cpp_grammar_abi=: tree-sitter core language ABI / the C++ grammar's ABI; informational. languages=N: distinct compiled-in grammars (the grammars row's expected=). tracked=N: git ls-files count, printed even when truncated=1 (over 20000 files skips the scan). binaries=N: tracked paths that sniff as binary content. non_git=1: no git history to compare; the row passes unscanned. stale=N: tracked binaries committed before a same-dir same-stem source changed; any fails the row. cache_version=/parser_ver_lean=/parser_ver_rich=/artifact_arch=: index identity; reuse needs all four. rich_verbs=: the verbs that consume the rich artifact (rich=); every other verb reads the lean one. source=: auto (per-root blob), cache-flag (named by the cache flag) or disabled (no-cache: nothing read). lean_path=/rich_path=: the artifact files checked; one path when the cache flag named it. lean=/rich=: can THIS binary open that artifact (ok, absent, parser-version ...); format, never freshness. fsmonitor=: the checkout's core.fsmonitor at startup: unset, builtin, off, or hook (a command git runs). neutralised=1: a hook fsmonitor was overridden to false for this run; 0 when none was needed. filter_drivers=N: filter drivers the repository's own config defines; filter_scope= local|all, filter_pinned= 1 (run with an empty command) or refused. state=: layout records agree, disagree (mixed binary: rebuild clean-first), not-checked or no-records. checked=1: the cross-unit layout comparison ran; 0 = under two comparable records. units=N: translation units that registered a layout record. types=N: layout types recorded (only those registered in src/model.h); omitted on state=disagree. checks=/passed=: checks run / how many passed; exit 1 when passed= is below checks=. built_from=: the commit this binary was built from; at= is the tree HEAD now, a mismatch is normal. self=/which=: this binary's path and the one which ripwire finds on PATH; which_version= is the version line that one prints when they differ. on_path=0|1: whether a ripwire is on PATH; 0 fails the row and hint= carries the export line. same_file=1: the PATH copy is this very file (same device and inode). same_bytes=1: a different file with identical content, a copied install (ok); 0 fails the row; unknown: a file was unreadable; the row fails unverified (hint= names it). self_mtime=/self_size=/which_mtime=/which_size=: epoch mtime and byte size of each binary. hint=: the row's verdict and fix in plain text (which binary is stale, what to run). -->
<doctor schema="ripwire.doctor/v1" checks="9" passed="8" at="6ace381eb" built_from="6ace381eb">
<c n="binary-path" ok="0" self="./build/ripwire" which="<path>" on_path="1" same_file="0" same_bytes="0" self_mtime="1795216845" self_size="65703608" which_mtime="1793517843" which_size="58197960" which_version="ripw … [line truncated: 525 more bytes on this line]
<c n="grammars" ok="1" loaded="27" expected="27"/>
<c n="cache-dir" ok="1" dir="<tmp>" blobs="245" bytes="2185434781" many="1" truncated="0" locks="275" volatile="blobs,blobs_floor,bytes,many,truncated,locks"/>
<c n="git" ok="1" git="1" repo="1" history="1" head="6ace381eb"/>
<c n="tree-sitter" ok="1" core_abi="15" cpp_grammar_abi="14" languages="27"/>
<c n="tracked-binaries" ok="1" tracked="5582" binaries="33" non_git="0" truncated="0" stale="0"/>
<c n="index-cache" ok="1" cache_version="54" parser_ver_lean="333" parser_ver_rich="334" artifact_arch="16" rich_verbs="for,uses,metrics,exemplar,context-ratio,nonlocal-state,quality-panel,verify,eval-retrieval,eval-mined,eval-skills" source="auto" lean_path="<tmp> … [line truncated: 219 more bytes on this line]
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

**wall time: 2.32s**

`````
<!-- ripwire map schema=ripwire.map/v1: ranked symbol map: <f p= layer=> groups <s t= n= sc= k= amb=> rows (k= rank), <c n=> resolved callees; the header comment is data. est_tokens=: price as emitted (an upper bound under compact). at=: commit+dirty+shallow. root=: p= relative to it. pr_iters=N: PageRank iterations. rank_by=: the ranker behind k=. window=: the git span mined. declined=K: K call sites without edges, including inert Elixir quote sites after unquote/unquote_splicing re-entry. external=K: K calls proven outside the tree, no edge. locality_pinned=K: K calls pinned by locality alone (a guess). extent_suspect_syms=K: K defs failed containment, corpus-wide. macro_blanked_files=K: K files indexed from a macro-blanked re-parse. overloads=N: N same-name defs merged in this row; shown= counts each. files=/symbols=: files and symbols indexed; edges= distinct call edges; shown= symbols printed, a merged row counting each def; ambiguous= calls split over several defs, corpus-wide; unresolved= calls with in-tree evidence and no edge (every def language-filtered or unreachable, or binding refused); order= rows by rank (important-first, important-last; (auto:fill) = flipped past a size threshold) or by path (stable). skipped_oversize=K: K files over a size ceiling, not indexed. unindexed=ext:N: N text files of that extension no grammar reads (6 extensions at most). unindexed_exts=E: E such extensions in all, the list cut. sc=: enclosing scope; the full id is p::sc::n (p= of the row or its <f>) and selectors take it. -->
<!-- t=modscope=a-file's-MODULE-SCOPE(n=<file-scope>):the-statements-outside-every-named-definition,where-a-top-level-call-and-an-anonymous-callback-body's-calls-live;a-CALLER-never-a-callee(nothing-in-the-source-can-name-it)-with-no-body-to-expand;a-file-with-no-such-call-has-no-such-row -->
<!-- t=type|alias|functype=a-Go-named-type-by-its-written-form:type=a-defined-type-whose-WRITTEN-form-is-not-a-struct/iface/func-literal(type-N-string;type-W-Pair-too,whatever-Pair-is-underneath),alias=type-A=B,functype=type-F-func(...) -->
<!-- t=alias|functype-in-C++-and-.h:alias=using-X=Y(also-templated-or-class-scope)or-namespace-L=lib(defs=X-prints-its-written-target-as-to=),functype=a-typedef-of-a-function-or-function-pointer-type(typedef-void(*F)(int));other-typedefs-read-t=struct -->
<!-- files=4838 symbols=44600 edges=44429 shown=5 est_tokens=1268 ambiguous=3634 unresolved=20069 locality_pinned=14 external=12457 declined=45295 extent_suspect_syms=12 macro_blanked_files=7 skipped_oversize=15 unindexed="txt:85,tsv:54,mod:33,xml:33,jsonl:26,scm:25" unindexed_exts=23 order=important-first -->
<r schema="ripwire.map/v1" at="6ace381eb" root="." rank_by="churn" window="18mo@HEAD" est_tokens="1268" pr_iters="36">
<f p="src/resolve.h">
<s t="method" n="appendUint" sc="Narrower" k="0.0040">
</s>
</f>
<f p="src/infra/Diagnostics.h" layer="infra">
<s t="macro" n="RW_ASSUME_" overloads="2" k="0.0033">
<c n="RW_CHECK_"/>
</s>
</f>
<f p="src/model.h">
<s t="fn" n="relForHash" sc="rw" k="0.0032">
</s>
</f>
<f p="src/infra/enumcount.h" layer="infra">
<s t="fn" n="enumTableAt" sc="rw" k="0.0031">
</s>
</f>
</r>
`````

## `./build/ripwire . --rank-by=churn-decay --since=HEAD~5 --exclude=test --exclude=docs --exclude=skills --exclude=changelog.d --in=src --limit=3`

*Scope the recent-changes answer to ONE directory. The global <recent> block stays byte-identical, a second <recent scope="src"> page follows it — n=/of= are its counts (of= IS the total, so the paging half carries no total=), capped="1" has_more="1" next_offset= offset= limit= page it, and next= replays THIS run's own corpus flags (--since/--exclude) so the page it names is a page of the same answer. The symbol map collapses to a disclosed <symbols stubbed="1" would_show= next=/> stub — the map was not asked for and was not ranked at all, which is why the header carries no pr_iters=. merge_bombs_skipped= stays on the global block: it counts the window's skipped commits, not the directory's.*

**wall time: 3.23s**

`````
<!-- ripwire map schema=ripwire.map/v1: ranked symbol map: <f p= layer=> groups <s t= n= sc= k= amb=> rows (k= rank), <c n=> resolved callees; the header comment is data. window: capped= has_more= next_offset= (capped=1 cut; next_offset= pastes as offset=). est_tokens=: price as emitted (an upper bound under compact). at=: commit+dirty+shallow. root=: p= relative to it. rank_by=: the ranker behind k=. window=: the git span mined. declined=K: K calls left unbound (no evidence chose one def). external=K: K calls proven outside the tree, no edge. locality_pinned=K: K calls pinned by locality alone (a guess). <recent n= of=>: the n= newest-touched of of= touched files; <rc age_d=> days since its last commit, w= decayed weight. merge_bombs_skipped=N: N commits touching more than 100 INDEXED files skipped, uncounted; a file only they touched is absent; the window's count, so the global block only. <recent scope=DIR>: a second block riding when the global one does, DIR's files only (p= root-relative); of= is its total; capped=/has_more=/next_offset=/offset=/limit= page it, next= is that page. <symbols stubbed=1 would_show=N next=>: the symbol map in= did not ask for was not rendered; N is that run's own shown= — definitions counted individually as shown= counts them, so its rows follow from rows+sum(overloads-1)=shown (not the header's symbols= corpus count); next= fetches it. files=/symbols=: files and symbols indexed; edges= distinct call edges; shown= symbols printed, a merged row counting each def; ambiguous= calls split over several defs, corpus-wide; unresolved= calls with in-tree evidence and no edge (every def language-filtered or unreachable, or binding refused); order= rows by rank (important-first, important-last; (auto:fill) = flipped past a size threshold) or by path (stable). skipped_oversize=K: K files over a size ceiling, not indexed. unindexed=ext:N: N text files of that extension no grammar reads (6 extensions at most). unindexed_exts=E: E such extensions in all, the list cut. next=: the one pasteable follow-up. -->
<!-- t=modscope=a-file's-MODULE-SCOPE(n=<file-scope>):the-statements-outside-every-named-definition,where-a-top-level-call-and-an-anonymous-callback-body's-calls-live;a-CALLER-never-a-callee(nothing-in-the-source-can-name-it)-with-no-body-to-expand;a-file-with-no-such-call-has-no-such-row -->
<!-- t=alias|functype-in-C++-and-.h:alias=using-X=Y(also-templated-or-class-scope)or-namespace-L=lib(defs=X-prints-its-written-target-as-to=),functype=a-typedef-of-a-function-or-function-pointer-type(typedef-void(*F)(int));other-typedefs-read-t=struct -->
<!-- files=645 symbols=22695 edges=30224 shown=0 est_tokens=1499 ambiguous=2414 unresolved=5523 locality_pinned=9 external=8321 declined=39998 skipped_oversize=15 unindexed="tsv:43,txt:26,scm:25,jsonl:23,expected:15,lock:7" unindexed_exts=12 order=important-first -->
<r schema="ripwire.map/v1" at="6ace381eb" root="." rank_by="churn-decay" window="HEAD~5 half-life=90d" est_tokens="1499">
<recent n="4" of="4" merge_bombs_skipped="0">
<rc p="src/cli.h" age_d="0" w="1"/>
<rc p="src/defectshape.h" age_d="0" w="1"/>
<rc p="src/ingest_astquery.h" age_d="0" w="1"/>
<rc p="src/quality.h" age_d="0" w="1"/>
</recent>
<recent scope="src" n="3" of="4" capped="1" has_more="1" next_offset="3" offset="0" limit="3" next="--rank-by=churn-decay --since=HEAD~5 --exclude=test --exclude=docs --exclude=skills --exclude=changelog.d --in=src --offset=3 --limit=3">
<rc p="src/cli.h" age_d="0" w="1"/>
<rc p="src/defectshape.h" age_d="0" w="1"/>
<rc p="src/ingest_astquery.h" age_d="0" w="1"/>
</recent>
<symbols stubbed="1" would_show="200" next="--rank-by=churn-decay --since=HEAD~5 --exclude=test --exclude=docs --exclude=skills --exclude=changelog.d"/>
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
<!-- ripwire callers schema=ripwire.callers/v1: 1-hop CALLERS of of= (defs= matched, count= distinct symbols): <s t= n= p=>; hop_tested=/hop_untested=. counts_floor=1: every count is a FLOOR, never a total. graph_ambiguous=/graph_unresolved=: resolver gauge. graph_unindexed=N: N files no grammar could read (the map header's unindexed=); their calls raise neither gauge. root=: p= relative to it. format=columnar: parallel arrays, not row attributes: <paths> maps I=path, each <cols> array holds n= comma-separated values in one row order, fields= naming them (the path column indexes <paths>; &#44; is a comma). <tested> column: 1 = a non-test row an indexed test transitively reaches; 0 = none found, or a test row. <sites_at> column: each row's leaf-name calls not proven elsewhere, as [file:]line (default: its path), space-separated; not proof each binds. next=: the one pasteable follow-up. -->
<callers schema="ripwire.callers/v1" of="rankGraphTeleport" defs="1" count="7" hop_tested="0" hop_untested="7" root="." graph_ambiguous="3634" graph_unresolved="20069" graph_unindexed="313" counts_floor="1" next="--uses=rankGraphTeleport" format="columnar">
<paths>0=src/mcpindex.h 1=src/graph.h 2=src/eval.h 3=src/main.cpp</paths>
<cols n="7" fields="path,name,line,kind,tested,sites_at">
<path>0,1,1,2,3,3,3</path>
<name>getIndex,rankGraph,anchoredLexicalRank,runEval,churnDecayRanking,churnRankedGraph,runDefaultMap</name>
<line>1224,14662,15331,171,1432,1471,1758</line>
<kind>fn,fn,fn,fn,fn,fn,fn</kind>
<tested>0,0,0,0,0,0,0</tested>
<sites_at>1340,14666,15382,328,1446,1485 1486 1500,1878</sites_at>
</cols>
</callers>
`````

## `./build/ripwire . --for="cache invalidation" --format=candidates --top-k=5`

*Flat top-K export for an external reranker.*

**wall time: 1.53s**

`````
<!-- ripwire candidates: flat top K export for an external reranker. r=rank(1 based) s=SCORE n=name id=canonical k=KIND-tag p=path l=line. Note k= is the kind here and the PageRank score in the ranked map; on this row the score is s=. Root: count= rows exported of total= RANKED CORPUS symbols (total is the corpus size, never a match count), capped="1" means the top-k cut dropped some; route= names the ranker (s= is comparable only within one route); anchored= counts query-mention lifts (0 = the anchor ran and moved nothing); weak="1" means the top raw lexical score is below the confidence bar, so these rows rest on thin textual evidence; doc_tier= names the query SHAPE (a pasted trace, a pasted bug-report form) that scored documents down for this run, absent when none did. -->
<candidates count="5" total="44601" capped="1" route="subtoken+body" anchored="0">
<cand r="1" s="14.7644" n="spanTierMemoPath" id="src/ingest_astquery.h::rw::spanTierMemoPath" k="fn" p="src/ingest_astquery.h" l="1588">
<sig>inline std::string spanTierMemoPath( const std::string&amp; diskPath )</sig>
</cand>
<cand r="2" s="9.39564" n="legoImplementorsOnSurface" id="src/serialize.h::rw::legoImplementorsOnSurface" k="fn" p="src/serialize.h" l="10002">
<sig>inline std::vector&lt;std::vector&lt;NodeId&gt;&gt; legoImplementorsOnSurface( const IngestResult&amp; ing, const std::vector&lt;std::vector&lt;NodeId&gt;&gt;&amp; implementors, const std::vector&lt;NodeId&gt;&amp; surfaceIds )</sig>
</cand>
<cand r="3" s="8.12042" n="See the map — not just the numbers" id="README.md::Rip&apos;n Fast. Fewer Tokens. Better Code.::See the map — not just the numbers" k="sec" p="README.md" l="426">
<sig>### See the map — not just the numbers</sig>
</cand>
<cand r="4" s="7.13865" n="receiptNextFor" id="src/mcpedit.h::mcpedit::receiptNextFor" k="fn" p="src/mcpedit.h" l="1102">
<sig>inline std::string receiptNextFor( const std::string&amp; fileIdentity, const std::string&amp; symbolName, const std::string&amp; foldJson, const std::string&amp; firstTestRun )</sig>
</cand>
<cand r="5" s="6.94803" n="AncestorCacheScope" id="src/infra/tsparent.h::AncestorCacheScope::AncestorCacheScope" k="fn" p="src/infra/tsparent.h" l="177">
<sig>AncestorCacheScope( TSNode root, bool enabled ) : previous( tAncestorCache )</sig>
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
{"of":"rankGraphTeleport","defs":1,"count":7,"root":".","hop_tested":0,"hop_untested":7,"graph_ambiguous":3634,"graph_unresolved":20069,"graph_unindexed":313,"counts_floor":true,"callers":[{"t":"fn","n":"getIndex","p":"src/mcpindex.h:1224","sites_at":["1340"]},
{"t":"fn","n":"rankGraph","p":"src/graph.h:14662","sites_at":["14666"]},
{"t":"fn","n":"anchoredLexicalRank","p":"src/graph.h:15331","sites_at":["15382"]},
{"t":"fn","n":"runEval","p":"src/eval.h:171","sites_at":["328"]},
{"t":"fn","n":"churnDecayRanking","p":"src/main.cpp:1432","sites_at":["1446"]},
{"t":"fn","n":"churnRankedGraph","p":"src/main.cpp:1471","sites_at":["1485","1486","1500"]},
{"t":"fn","n":"runDefaultMap","p":"src/main.cpp:1758","sites_at":["1878"]}]}
`````

## `./build/ripwire . --hotspots --json`

*JSON refusal shape: an unsupported verb refuses loudly instead of silently falling back to XML.*

**exit code: 1**

`````
(empty)
`````

stderr:

`````
ripwire: --json is not yet supported for --hotspots — supported: the default map, --for, --pack-task, --callers/--callees, --impact, --quality-delta, --test-gate, --metrics, --defs, --flags, and --plan-lanes which is JSON-native (e.g. ripwire <dir> --callers=SYM --json)
`````

## `./build/ripwire . --hotspots --limit=3 --offset=3`

*Pagination: 3 items, skipping the first 3 (deterministic seams).*

**wall time: 2.72s**

`````
<!-- ripwire hotspots schema=ripwire.hotspots/v1: maintenance pain = churn x ccx over window=: <f p= churn= ccx= score= top= top_ccx= top_l=>; unranked_*= no churn/complexity. window: shown= total= capped= has_more= next_offset= offset= limit= (capped=1 cut; next_offset= pastes as offset=). at=: commit+dirty+shallow. root=: p= relative to it. files=/ranked=: files in the window / those with both churn and complexity; ranked + unranked_no_churn + unranked_no_complexity = files. unranked_no_churn=/unranked_no_complexity=: files left out for no commit in window= / no measured complexity. -->
<!-- extent_suspect_syms=K on a row = K of the file's functions failed an extent/scope containment check (the map, the bundles and the skipped verb mark each one, reasons and all) and are LEFT OUT of that row's ccx=, score= and top=, so its ccx= is a FLOOR of the file's true sum rather than a total. unranked_extent_suspect= counts files with commits whose every scorable function was left out that way (or whose trusted remainder scores 0), so ranked= + unranked_no_churn= + unranked_no_complexity= + unranked_extent_suspect= = files= exactly. Absent = nothing excluded. -->
<hotspots schema="ripwire.hotspots/v1" window="12mo@HEAD" files="4838" ranked="1115" unranked_no_churn="0" unranked_no_complexity="3721" unranked_extent_suspect="2" shown="3" capped="1" total="1115" has_more="1" next_offset="6" offset="3" limit="3" root="." at="6ace381eb">
<f p="src/mcpverbs.h" churn="675" ccx="1369" score="924075" top="runBatchSub" top_ccx="142" top_l="6334"/>
<f p="src/main.cpp" churn="509" ccx="1356" score="690204" top="dispatchMainBody" top_ccx="513" top_l="4653"/>
<f p="src/verbs_for.h" churn="422" ccx="1358" score="573076" top="runForLensPass" top_ccx="706" top_l="3606"/>
</hotspots>
`````

## `./build/ripwire . --ignore-tests --top-k=5`

*Drop test paths from the corpus before ranking.*

**wall time: 1.19s**

`````
<!-- ripwire map schema=ripwire.map/v1: ranked symbol map: <f p= layer=> groups <s t= n= sc= k= amb=> rows (k= rank), <c n=> resolved callees; the header comment is data. est_tokens=: price as emitted (an upper bound under compact). root=: p= relative to it. pr_iters=N: PageRank iterations. <inv listed= unlisted=>: files the ranked rows show / do not (sum = files=), each named or counted below. <entry p= n=>: a program entry by its language's convention (C/Go/Rust main, Java/C# static main, a script main its module scope calls, __main__.py), callees as c rows; manifest entries not read. <ls p= n= f=>: n= unshown files under dir p=; f= names its code files, the rest (tests, docs, config, test/doc/example dirs) counted. declined=K: K calls left unbound (no evidence chose one def). external=K: K calls proven outside the tree, no edge. locality_pinned=K: K calls pinned by locality alone (a guess). macro_blanked_files=K: K files indexed from a macro-blanked re-parse. prov=scip|binding|import|split|final-segment: how that <c> edge bound (absent: one unique name); split = one arm of an amb= pick; final-segment = a qualified type matched by last name only. files=/symbols=: files and symbols indexed; edges= distinct call edges; shown= symbols printed, a merged row counting each def; ambiguous= calls split over several defs, corpus-wide; unresolved= calls with in-tree evidence and no edge (every def language-filtered or unreachable, or binding refused); order= rows by rank (important-first, important-last; (auto:fill) = flipped past a size threshold) or by path (stable). skipped_oversize=K: K files over a size ceiling, not indexed. unindexed=ext:N: N text files of that extension no grammar reads (6 extensions at most). unindexed_exts=E: E such extensions in all, the list cut. sc=: enclosing scope; the full id is p::sc::n (p= of the row or its <f>) and selectors take it. -->
<!-- t=modscope=a-file's-MODULE-SCOPE(n=<file-scope>):the-statements-outside-every-named-definition,where-a-top-level-call-and-an-anonymous-callback-body's-calls-live;a-CALLER-never-a-callee(nothing-in-the-source-can-name-it)-with-no-body-to-expand;a-file-with-no-such-call-has-no-such-row -->
<!-- t=alias|functype-in-C++-and-.h:alias=using-X=Y(also-templated-or-class-scope)or-namespace-L=lib(defs=X-prints-its-written-target-as-to=),functype=a-typedef-of-a-function-or-function-pointer-type(typedef-void(*F)(int));other-typedefs-read-t=struct -->
<!-- files=4838 symbols=24671 edges=31074 shown=5 est_tokens=3957 ambiguous=2432 unresolved=5684 locality_pinned=9 external=8615 declined=40561 macro_blanked_files=7 skipped_oversize=15 unindexed="txt:85,tsv:54,mod:33,xml:33,jsonl:26,scm:25" unindexed_exts=23 order=important-first -->
<r schema="ripwire.map/v1" root="." est_tokens="3957" pr_iters="39">
<f p="src/infra/nodekind.h" layer="infra">
<s t="fn" n="kindIs" sc="rw" k="0.0046">
</s>
</f>
<f p="src/ingest_metrics.h">
<s t="fn" n="nodeTextOf" k="0.0030">
</s>
</f>
<f p="src/infra/namesplit.h" layer="infra">
<s t="fn" n="isIdentChar" sc="namesplit" k="0.0029">
</s>
</f>
<f p="src/model.h">
<s t="fn" n="relForHash" sc="rw" k="0.0028">
</s>
</f>
<f p="src/infra/Diagnostics.h" layer="infra">
<s t="macro" n="RW_ASSUME_" k="0.0026">
<c n="RW_CHECK_"/>
</s>
</f>
<inv listed="5" unlisted="4833">
<entry p="scripts/changelog_assemble.py" n="main">
<c n="repoRoot"/>
<c n="fragmentNames"/>
… [88 more display lines; full output is 9866 bytes on 1 raw line(s)]
`````

stderr:

`````
[validate] symbolCount == N && fileCount == ing.files.size() && referenceCount == ing.references.size() is false — warmsnap: the graph section describes another model  (warmsnap_graph.h:274, std::optional<Graph> rw::warmsnap::readGraph(Session &, const IngestResult &) — logged once per site)
`````

## `./build/ripwire . --exclude=present --exclude=bench --top-k=5`

*Drop matching paths (repeatable) before ranking.*

**wall time: 1.53s**

`````
<!-- ripwire map schema=ripwire.map/v1: ranked symbol map: <f p= layer=> groups <s t= n= sc= k= amb=> rows (k= rank), <c n=> resolved callees; the header comment is data. est_tokens=: price as emitted (an upper bound under compact). root=: p= relative to it. pr_iters=N: PageRank iterations. <inv listed= unlisted=>: files the ranked rows show / do not (sum = files=), each named or counted below. <entry p= n=>: a program entry by its language's convention (C/Go/Rust main, Java/C# static main, a script main its module scope calls, __main__.py), callees as c rows; manifest entries not read. <ls p= n= f=>: n= unshown files under dir p=; f= names its code files, the rest (tests, docs, config, test/doc/example dirs) counted. declined=K: K call sites without edges, including inert Elixir quote sites after unquote/unquote_splicing re-entry. external=K: K calls proven outside the tree, no edge. locality_pinned=K: K calls pinned by locality alone (a guess). extent_suspect_syms=K: K defs failed containment, corpus-wide. macro_blanked_files=K: K files indexed from a macro-blanked re-parse. prov=scip|binding|import|split|final-segment: how that <c> edge bound (absent: one unique name); split = one arm of an amb= pick; final-segment = a qualified type matched by last name only. files=/symbols=: files and symbols indexed; edges= distinct call edges; shown= symbols printed, a merged row counting each def; ambiguous= calls split over several defs, corpus-wide; unresolved= calls with in-tree evidence and no edge (every def language-filtered or unreachable, or binding refused); order= rows by rank (important-first, important-last; (auto:fill) = flipped past a size threshold) or by path (stable). unindexed=ext:N: N text files of that extension no grammar reads (6 extensions at most). unindexed_exts=E: E such extensions in all, the list cut. sc=: enclosing scope; the full id is p::sc::n (p= of the row or its <f>) and selectors take it. -->
<!-- t=modscope=a-file's-MODULE-SCOPE(n=<file-scope>):the-statements-outside-every-named-definition,where-a-top-level-call-and-an-anonymous-callback-body's-calls-live;a-CALLER-never-a-callee(nothing-in-the-source-can-name-it)-with-no-body-to-expand;a-file-with-no-such-call-has-no-such-row -->
<!-- t=type|alias|functype=a-Go-named-type-by-its-written-form:type=a-defined-type-whose-WRITTEN-form-is-not-a-struct/iface/func-literal(type-N-string;type-W-Pair-too,whatever-Pair-is-underneath),alias=type-A=B,functype=type-F-func(...) -->
<!-- t=alias|functype-in-C++-and-.h:alias=using-X=Y(also-templated-or-class-scope)or-namespace-L=lib(defs=X-prints-its-written-target-as-to=),functype=a-typedef-of-a-function-or-function-pointer-type(typedef-void(*F)(int));other-typedefs-read-t=struct -->
<!-- files=4567 symbols=40241 edges=42900 shown=5 est_tokens=4048 ambiguous=3581 unresolved=19114 locality_pinned=14 external=9814 declined=42908 extent_suspect_syms=12 macro_blanked_files=7 unindexed="txt:64,mod:33,xml:33,scm:25,tsv:11,cmake:5" unindexed_exts=18 order=important-first -->
<r schema="ripwire.map/v1" root="." est_tokens="4048" pr_iters="40">
<f p="src/infra/nodekind.h" layer="infra">
<s t="fn" n="kindIs" sc="rw" k="0.0034">
</s>
</f>
<f p="src/ingest_metrics.h">
<s t="fn" n="nodeTextOf" k="0.0022">
</s>
</f>
<f p="src/infra/namesplit.h" layer="infra">
<s t="fn" n="isIdentChar" sc="namesplit" k="0.0022">
</s>
</f>
<f p="src/model.h">
<s t="fn" n="relForHash" sc="rw" k="0.0020">
</s>
</f>
<f p="src/infra/Diagnostics.h" layer="infra">
<s t="macro" n="RW_ASSUME_" k="0.0019">
<c n="RW_CHECK_"/>
</s>
</f>
<inv listed="5" unlisted="4562">
<entry p="scripts/changelog_assemble.py" n="main">
<c n="repoRoot"/>
… [87 more display lines; full output is 10092 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --map-diff --top-k=5`

*Full map re-ranked with teleport toward git-changed files — clean tree, so changed=0 and it degrades to the plain map.*

**wall time: 2.50s**

`````
<!-- ripwire map-diff schema=ripwire.map-diff/v1: the ranked map anchored at at=: what the diff touched, the map's row vocabulary. est_tokens=: price as emitted (an upper bound under compact). at=: commit+dirty+shallow. root=: p= relative to it. pr_iters=N: PageRank iterations. declined=K: K call sites without edges, including inert Elixir quote sites after unquote/unquote_splicing re-entry. external=K: K calls proven outside the tree, no edge. locality_pinned=K: K calls pinned by locality alone (a guess). extent_suspect_syms=K: K defs failed containment, corpus-wide. macro_blanked_files=K: K files indexed from a macro-blanked re-parse. files=/symbols=: files and symbols indexed; edges= distinct call edges; shown= symbols printed, a merged row counting each def; ambiguous= calls split over several defs, corpus-wide; unresolved= calls with in-tree evidence and no edge (every def language-filtered or unreachable, or binding refused); order= rows by rank (important-first, important-last; (auto:fill) = flipped past a size threshold) or by path (stable). changed=K: K indexed git-changed files seed the PageRank teleport (0: uniform, incl. no git). skipped_oversize=K: K files over a size ceiling, not indexed. unindexed=ext:N: N text files of that extension no grammar reads (6 extensions at most). unindexed_exts=E: E such extensions in all, the list cut. sc=: enclosing scope; the full id is p::sc::n (p= of the row or its <f>) and selectors take it. layer=: built-in arch layer (game|infra|render|math|audio|ai|test) from a dir name in p=; absent if none. f p=: a file; s t= n=: kind, name; c n=: a resolved callee. s k=: rank. -->
<!-- t=modscope=a-file's-MODULE-SCOPE(n=<file-scope>):the-statements-outside-every-named-definition,where-a-top-level-call-and-an-anonymous-callback-body's-calls-live;a-CALLER-never-a-callee(nothing-in-the-source-can-name-it)-with-no-body-to-expand;a-file-with-no-such-call-has-no-such-row -->
<!-- t=type|alias|functype=a-Go-named-type-by-its-written-form:type=a-defined-type-whose-WRITTEN-form-is-not-a-struct/iface/func-literal(type-N-string;type-W-Pair-too,whatever-Pair-is-underneath),alias=type-A=B,functype=type-F-func(...) -->
<!-- t=alias|functype-in-C++-and-.h:alias=using-X=Y(also-templated-or-class-scope)or-namespace-L=lib(defs=X-prints-its-written-target-as-to=),functype=a-typedef-of-a-function-or-function-pointer-type(typedef-void(*F)(int));other-typedefs-read-t=struct -->
<!-- files=4838 symbols=44600 edges=44429 shown=5 est_tokens=1322 ambiguous=3634 unresolved=20069 locality_pinned=14 external=12457 declined=45295 extent_suspect_syms=12 macro_blanked_files=7 changed=0 skipped_oversize=15 unindexed="txt:85,tsv:54,mod:33,xml:33,jsonl:26,scm:25" unindexed_exts=23 order=important-first -->
<r schema="ripwire.map-diff/v1" at="6ace381eb" root="." est_tokens="1322" pr_iters="40">
<f p="src/infra/nodekind.h" layer="infra">
<s t="fn" n="kindIs" sc="rw" k="0.0031">
</s>
</f>
<f p="src/ingest_metrics.h">
<s t="fn" n="nodeTextOf" k="0.0021">
</s>
</f>
<f p="src/infra/namesplit.h" layer="infra">
<s t="fn" n="isIdentChar" sc="namesplit" k="0.0020">
</s>
</f>
<f p="src/model.h">
<s t="fn" n="relForHash" sc="rw" k="0.0019">
</s>
</f>
<f p="src/infra/Diagnostics.h" layer="infra">
<s t="macro" n="RW_ASSUME_" k="0.0018">
<c n="RW_CHECK_"/>
</s>
</f>
</r>
`````

stderr:

`````
[validate] symbolCount == N && fileCount == ing.files.size() && referenceCount == ing.references.size() is false — warmsnap: the graph section describes another model  (warmsnap_graph.h:274, std::optional<Graph> rw::warmsnap::readGraph(Session &, const IngestResult &) — logged once per site)
`````

## `./build/ripwire . --no-cache --top-k=3`

*Force a cold parse (bypass the warm TMPDIR cache) — shows the cold-vs-warm cost.*

**wall time: 6.13s**

`````
<!-- ripwire map schema=ripwire.map/v1: ranked symbol map: <f p= layer=> groups <s t= n= sc= k= amb=> rows (k= rank), <c n=> resolved callees; the header comment is data. est_tokens=: price as emitted (an upper bound under compact). root=: p= relative to it. pr_iters=N: PageRank iterations. <inv listed= unlisted=>: files the ranked rows show / do not (sum = files=), each named or counted below. <entry p= n=>: a program entry by its language's convention (C/Go/Rust main, Java/C# static main, a script main its module scope calls, __main__.py), callees as c rows; manifest entries not read. <ls p= n= f=>: n= unshown files under dir p=; f= names its code files, the rest (tests, docs, config, test/doc/example dirs) counted. declined=K: K call sites without edges, including inert Elixir quote sites after unquote/unquote_splicing re-entry. external=K: K calls proven outside the tree, no edge. locality_pinned=K: K calls pinned by locality alone (a guess). extent_suspect_syms=K: K defs failed containment, corpus-wide. macro_blanked_files=K: K files indexed from a macro-blanked re-parse. prov=scip|binding|import|split|final-segment: how that <c> edge bound (absent: one unique name); split = one arm of an amb= pick; final-segment = a qualified type matched by last name only. files=/symbols=: files and symbols indexed; edges= distinct call edges; shown= symbols printed, a merged row counting each def; ambiguous= calls split over several defs, corpus-wide; unresolved= calls with in-tree evidence and no edge (every def language-filtered or unreachable, or binding refused); order= rows by rank (important-first, important-last; (auto:fill) = flipped past a size threshold) or by path (stable). skipped_oversize=K: K files over a size ceiling, not indexed. unindexed=ext:N: N text files of that extension no grammar reads (6 extensions at most). unindexed_exts=E: E such extensions in all, the list cut. sc=: enclosing scope; the full id is p::sc::n (p= of the row or its <f>) and selectors take it. -->
<!-- t=modscope=a-file's-MODULE-SCOPE(n=<file-scope>):the-statements-outside-every-named-definition,where-a-top-level-call-and-an-anonymous-callback-body's-calls-live;a-CALLER-never-a-callee(nothing-in-the-source-can-name-it)-with-no-body-to-expand;a-file-with-no-such-call-has-no-such-row -->
<!-- t=type|alias|functype=a-Go-named-type-by-its-written-form:type=a-defined-type-whose-WRITTEN-form-is-not-a-struct/iface/func-literal(type-N-string;type-W-Pair-too,whatever-Pair-is-underneath),alias=type-A=B,functype=type-F-func(...) -->
<!-- t=alias|functype-in-C++-and-.h:alias=using-X=Y(also-templated-or-class-scope)or-namespace-L=lib(defs=X-prints-its-written-target-as-to=),functype=a-typedef-of-a-function-or-function-pointer-type(typedef-void(*F)(int));other-typedefs-read-t=struct -->
<!-- files=4838 symbols=44600 edges=44429 shown=3 est_tokens=4041 ambiguous=3634 unresolved=20069 locality_pinned=14 external=12457 declined=45295 extent_suspect_syms=12 macro_blanked_files=7 skipped_oversize=15 unindexed="txt:85,tsv:54,mod:33,xml:33,jsonl:26,scm:25" unindexed_exts=23 order=important-first -->
<r schema="ripwire.map/v1" root="." est_tokens="4041" pr_iters="40">
<f p="src/infra/nodekind.h" layer="infra">
<s t="fn" n="kindIs" sc="rw" k="0.0031">
</s>
</f>
<f p="src/ingest_metrics.h">
<s t="fn" n="nodeTextOf" k="0.0021">
</s>
</f>
<f p="src/infra/namesplit.h" layer="infra">
<s t="fn" n="isIdentChar" sc="namesplit" k="0.0020">
</s>
</f>
<inv listed="3" unlisted="4835">
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
… [80 more display lines; full output is 10090 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --cache=<scratch>/aux/warm2.ripwirecache --top-k=3`

*Explicit incremental cache at a path OUTSIDE the repo (first call writes it).*

**wall time: 6.50s**

`````
<!-- ripwire map schema=ripwire.map/v1: ranked symbol map: <f p= layer=> groups <s t= n= sc= k= amb=> rows (k= rank), <c n=> resolved callees; the header comment is data. est_tokens=: price as emitted (an upper bound under compact). root=: p= relative to it. pr_iters=N: PageRank iterations. <inv listed= unlisted=>: files the ranked rows show / do not (sum = files=), each named or counted below. <entry p= n=>: a program entry by its language's convention (C/Go/Rust main, Java/C# static main, a script main its module scope calls, __main__.py), callees as c rows; manifest entries not read. <ls p= n= f=>: n= unshown files under dir p=; f= names its code files, the rest (tests, docs, config, test/doc/example dirs) counted. declined=K: K call sites without edges, including inert Elixir quote sites after unquote/unquote_splicing re-entry. external=K: K calls proven outside the tree, no edge. locality_pinned=K: K calls pinned by locality alone (a guess). extent_suspect_syms=K: K defs failed containment, corpus-wide. macro_blanked_files=K: K files indexed from a macro-blanked re-parse. prov=scip|binding|import|split|final-segment: how that <c> edge bound (absent: one unique name); split = one arm of an amb= pick; final-segment = a qualified type matched by last name only. files=/symbols=: files and symbols indexed; edges= distinct call edges; shown= symbols printed, a merged row counting each def; ambiguous= calls split over several defs, corpus-wide; unresolved= calls with in-tree evidence and no edge (every def language-filtered or unreachable, or binding refused); order= rows by rank (important-first, important-last; (auto:fill) = flipped past a size threshold) or by path (stable). skipped_oversize=K: K files over a size ceiling, not indexed. unindexed=ext:N: N text files of that extension no grammar reads (6 extensions at most). unindexed_exts=E: E such extensions in all, the list cut. sc=: enclosing scope; the full id is p::sc::n (p= of the row or its <f>) and selectors take it. -->
<!-- t=modscope=a-file's-MODULE-SCOPE(n=<file-scope>):the-statements-outside-every-named-definition,where-a-top-level-call-and-an-anonymous-callback-body's-calls-live;a-CALLER-never-a-callee(nothing-in-the-source-can-name-it)-with-no-body-to-expand;a-file-with-no-such-call-has-no-such-row -->
<!-- t=type|alias|functype=a-Go-named-type-by-its-written-form:type=a-defined-type-whose-WRITTEN-form-is-not-a-struct/iface/func-literal(type-N-string;type-W-Pair-too,whatever-Pair-is-underneath),alias=type-A=B,functype=type-F-func(...) -->
<!-- t=alias|functype-in-C++-and-.h:alias=using-X=Y(also-templated-or-class-scope)or-namespace-L=lib(defs=X-prints-its-written-target-as-to=),functype=a-typedef-of-a-function-or-function-pointer-type(typedef-void(*F)(int));other-typedefs-read-t=struct -->
<!-- files=4838 symbols=44600 edges=44429 shown=3 est_tokens=4041 ambiguous=3634 unresolved=20069 locality_pinned=14 external=12457 declined=45295 extent_suspect_syms=12 macro_blanked_files=7 skipped_oversize=15 unindexed="txt:85,tsv:54,mod:33,xml:33,jsonl:26,scm:25" unindexed_exts=23 order=important-first -->
<r schema="ripwire.map/v1" root="." est_tokens="4041" pr_iters="40">
<f p="src/infra/nodekind.h" layer="infra">
<s t="fn" n="kindIs" sc="rw" k="0.0031">
</s>
</f>
<f p="src/ingest_metrics.h">
<s t="fn" n="nodeTextOf" k="0.0021">
</s>
</f>
<f p="src/infra/namesplit.h" layer="infra">
<s t="fn" n="isIdentChar" sc="namesplit" k="0.0020">
</s>
</f>
<inv listed="3" unlisted="4835">
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
… [80 more display lines; full output is 10090 bytes on 1 raw line(s)]
`````

Artifact written:

`````
 40617339 <scratch>/aux/warm2.ripwirecache
`````

## `./build/ripwire . --max-file-size=8K --top-k=3`

*Skip files above a size bound before parsing (note the corpus shrink in the header).*

**wall time: 1.36s**

`````
<!-- ripwire map schema=ripwire.map/v1: ranked symbol map: <f p= layer=> groups <s t= n= sc= k= amb=> rows (k= rank), <c n=> resolved callees; the header comment is data. est_tokens=: price as emitted (an upper bound under compact). root=: p= relative to it. pr_iters=N: PageRank iterations. <inv listed= unlisted=>: files the ranked rows show / do not (sum = files=), each named or counted below. <entry p= n=>: a program entry by its language's convention (C/Go/Rust main, Java/C# static main, a script main its module scope calls, __main__.py), callees as c rows; manifest entries not read. <ls p= n= f=>: n= unshown files under dir p=; f= names its code files, the rest (tests, docs, config, test/doc/example dirs) counted. declined=K: K call sites without edges, including inert Elixir quote sites after unquote/unquote_splicing re-entry. external=K: K calls proven outside the tree, no edge. locality_pinned=K: K calls pinned by locality alone (a guess). extent_suspect_syms=K: K defs failed containment, corpus-wide. macro_blanked_files=K: K files indexed from a macro-blanked re-parse. files=/symbols=: files and symbols indexed; edges= distinct call edges; shown= symbols printed, a merged row counting each def; ambiguous= calls split over several defs, corpus-wide; unresolved= calls with in-tree evidence and no edge (every def language-filtered or unreachable, or binding refused); order= rows by rank (important-first, important-last; (auto:fill) = flipped past a size threshold) or by path (stable). skipped_oversize=K: K files over a size ceiling, not indexed. unindexed=ext:N: N text files of that extension no grammar reads (6 extensions at most). unindexed_exts=E: E such extensions in all, the list cut. sc=: enclosing scope; the full id is p::sc::n (p= of the row or its <f>) and selectors take it. -->
<!-- t=modscope=a-file's-MODULE-SCOPE(n=<file-scope>):the-statements-outside-every-named-definition,where-a-top-level-call-and-an-anonymous-callback-body's-calls-live;a-CALLER-never-a-callee(nothing-in-the-source-can-name-it)-with-no-body-to-expand;a-file-with-no-such-call-has-no-such-row -->
<!-- t=type|alias|functype=a-Go-named-type-by-its-written-form:type=a-defined-type-whose-WRITTEN-form-is-not-a-struct/iface/func-literal(type-N-string;type-W-Pair-too,whatever-Pair-is-underneath),alias=type-A=B,functype=type-F-func(...) -->
<!-- t=alias|functype-in-C++-and-.h:alias=using-X=Y(also-templated-or-class-scope)or-namespace-L=lib(defs=X-prints-its-written-target-as-to=),functype=a-typedef-of-a-function-or-function-pointer-type(typedef-void(*F)(int));other-typedefs-read-t=struct -->
<!-- files=3578 symbols=14047 edges=4628 shown=3 est_tokens=2003 ambiguous=387 unresolved=1203 locality_pinned=5 external=1256 declined=1474 extent_suspect_syms=12 macro_blanked_files=7 skipped_oversize=1275 unindexed="txt:85,tsv:54,mod:33,xml:33,jsonl:26,scm:25" unindexed_exts=23 order=important-first -->
<r schema="ripwire.map/v1" root="." est_tokens="2003" pr_iters="38">
<f p="test/forcallerhopfix/d2inherit/pycap/m.py" layer="test">
<s t="fn" n="post_entry" sc="Ledger" k="0.0017">
</s>
</f>
<f p="test/forcallerhopfix/c/fan.c" layer="test">
<s t="fn" n="fan_target" k="0.0017">
</s>
</f>
<f p="test/stdnamesakefix/tree/rs/lib.rs" layer="test">
<s t="method" n="map" sc="Shelf" k="0.0013">
</s>
</f>
<inv listed="3" unlisted="3575">
<entry p="src/tsprobe.cpp" n="main">
<c n="langIndex"/>
<c n="kindIndex"/>
<c n="langName"/>
</entry>
<ls p="." n="6"/>
<ls p=".codex-plugin" n="1"/>
<ls p="bench" n="140"/>
<ls p="changelog.d" n="109"/>
<ls p="docs" n="4"/>
<ls p="hooks" n="1"/>
… [20 more display lines; full output is 4972 bytes on 1 raw line(s)]
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

**wall time: 5.54s**

`````
<!-- ripwire map schema=ripwire.map/v1: ranked symbol map: <f p= layer=> groups <s t= n= sc= k= amb=> rows (k= rank), <c n=> resolved callees; the header comment is data. est_tokens=: price as emitted (an upper bound under compact). <root label= p=>: a workspace root; label= prefixes every p=/id=. pr_iters=N: PageRank iterations. declined=K: K call sites without edges, including inert Elixir quote sites after unquote/unquote_splicing re-entry. external=K: K calls proven outside the tree, no edge. locality_pinned=K: K calls pinned by locality alone (a guess). extent_suspect_syms=K: K defs failed containment, corpus-wide. macro_blanked_files=K: K files indexed from a macro-blanked re-parse. files=/symbols=: files and symbols indexed; edges= distinct call edges; shown= symbols printed, a merged row counting each def; ambiguous= calls split over several defs, corpus-wide; unresolved= calls with in-tree evidence and no edge (every def language-filtered or unreachable, or binding refused); order= rows by rank (important-first, important-last; (auto:fill) = flipped past a size threshold) or by path (stable). roots=N: N workspace roots. unindexed=ext:N: N text files of that extension no grammar reads (6 extensions at most). unindexed_exts=E: E such extensions in all, the list cut. sc=: enclosing scope; the full id is p::sc::n (p= of the row or its <f>) and selectors take it. -->
<!-- t=modscope=a-file's-MODULE-SCOPE(n=<file-scope>):the-statements-outside-every-named-definition,where-a-top-level-call-and-an-anonymous-callback-body's-calls-live;a-CALLER-never-a-callee(nothing-in-the-source-can-name-it)-with-no-body-to-expand;a-file-with-no-such-call-has-no-such-row -->
<!-- t=type|alias|functype=a-Go-named-type-by-its-written-form:type=a-defined-type-whose-WRITTEN-form-is-not-a-struct/iface/func-literal(type-N-string;type-W-Pair-too,whatever-Pair-is-underneath),alias=type-A=B,functype=type-F-func(...) -->
<!-- t=alias|functype-in-C++-and-.h:alias=using-X=Y(also-templated-or-class-scope)or-namespace-L=lib(defs=X-prints-its-written-target-as-to=),functype=a-typedef-of-a-function-or-function-pointer-type(typedef-void(*F)(int));other-typedefs-read-t=struct -->
<!-- files=4324 symbols=36417 edges=41770 shown=5 est_tokens=1220 ambiguous=3468 unresolved=13742 locality_pinned=14 external=7865 declined=42433 extent_suspect_syms=12 macro_blanked_files=7 roots=2 unindexed="txt:59,mod:33,xml:33,tsv:8,am:4,cfg:4" unindexed_exts=16 order=important-first -->
<r schema="ripwire.map/v1" est_tokens="1220" pr_iters="41">
<root label="src" p="src"/>
<root label="test" p="test"/>
<f p="src/infra/nodekind.h" layer="infra">
<s t="fn" n="kindIs" sc="rw" k="0.0037">
</s>
</f>
<f p="src/ingest_metrics.h">
<s t="fn" n="nodeTextOf" k="0.0024">
</s>
</f>
<f p="src/infra/namesplit.h" layer="infra">
<s t="fn" n="isIdentChar" sc="namesplit" k="0.0024">
</s>
</f>
<f p="src/model.h">
<s t="fn" n="relForHash" sc="rw" k="0.0022">
</s>
</f>
<f p="src/infra/Diagnostics.h" layer="infra">
<s t="macro" n="RW_ASSUME_" k="0.0021">
<c n="RW_CHECK_"/>
</s>
</f>
</r>
`````

## `./build/ripwire . --eval`

*Self-eval: co-change recall vs BM25.*

**wall time: 28.47s**

`````
ripwire --eval  (co-change recovery, averaged over 80 historical commits)
  ranker     recall@5  recall@10  recall@20
  ripwire        8.4%       8.5%      15.9%
  BM25           8.6%       9.4%      11.2%
  BM25sub        8.3%      10.2%      13.2%
  BM25body       6.8%       9.5%      18.2%
  fused          5.7%       7.0%      18.2%
  anchored       6.8%       9.5%      16.4%
  same-dir       0.0%       0.1%       1.2%
  random         0.1%       0.2%       0.4%   <- floor (random ranking over F=4838 files)
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

**wall time: 249.76s**

`````
ripwire --eval-retrieval  (known-item, 4000 doc-commented symbols; gold is in-corpus by construction)
  sample: population=12113 scored=4000 rule=smallest-key CAPPED — a SUBSET, not the population
          (smallest fnv1a64(scope::name) over the population, cut on the key so an identity is never split;
           path- and order-independent, but a corpus this size is NOT graded exhaustively — say so when citing it)
  ingest: lex=rich (persisted subtoken stats; no per-query corpus re-tokenize)
  ranker    query-mode     MRR  recall@1  recall@5 recall@10
  subtoken  name         0.660     52.7%     82.3%     87.5%
  subtoken  doc-phrase   0.882     85.9%     90.3%     91.4%
  name-exact name         0.876     79.6%     93.8%     96.1%
  name-exact doc-phrase   0.008      0.3%      1.1%      1.6%
  anchored  name         0.664     53.9%     81.1%     86.1%
  anchored  doc-phrase   0.875     85.0%     89.9%     90.7%
  routed    name         0.878     79.8%     94.0%     96.3%
  routed    doc-phrase   0.880     85.9%     90.0%     91.2%
  note: routing chose name-exact on 3989/4000 NAME queries (a NAME query is always identifier-shaped);
        the confidence gate routes doc-phrase queries to name-exact ONLY when EVERY content word names a symbol
        (or an explicit camel/snake token appears) AND every matched name is specific enough to anchor on —
        a common name (many definitions, or a subtoken carried by many symbol names) declines the route — so
        conceptual prose falls back to subtoken+body; routed tracks the better ranker on BOTH modes
        (routed==name-exact on name, ~=subtoken+body on doc-phrase).
`````

## `./build/ripwire . --eval-stray=<scratch>/aux/stray_labels2.tsv`

*Labelled verdict-accuracy eval for --stray-content — three labels over REAL local refs (names resolved at capture time); exit 3 when accuracy is under the floor. Read got= against v= in the stray-content run: a ref the verb could not analyse (unknown) must never be credited as a merged hit.*

**exit code: 3** — **wall time: 19.65s**

Input file:

`````
# ref<TAB>verdict labels for --eval-stray (the first three local branches, resolved at capture time; a missing branch is padded with a nonexistent name on purpose)
arm/for-howitworks-067-f2add	merged
arm/for-howitworks-067-placebo	unmerged
arm/orient-map-067-narrow	merged
`````

`````
<!-- ripwire stray-content eval: labelled verdict accuracy. Each row is one branch whose true state was established by hand; want= is the label, got= is what the classifier said. A branch absent from the report scores as merged ONLY when it is a real ref this repo has (merged refs are omitted by design); a label naming a ref that does not exist is refused, not scored (see badRefs on refusal). unknown= on the root counts cases whose verdict is unknown (no merge-base / unrelated history); its own bucket, never folded into merged. labels_omitted= (present only when non-zero) counts labelled refs past the sweep's 512-ref window (it keeps every labelled ref first, so only more than 512 labels leave any out): never scored. Use this to MEASURE a threshold change instead of eyeballing it. -->
<stray-eval cases="3" correct="1" unknown="0" accuracy="33.3">
<case ref="arm/for-howitworks-067-f2add" want="merged" got="unmerged" hit="0" reported="1"/>
<case ref="arm/for-howitworks-067-placebo" want="unmerged" got="unmerged" hit="1" reported="1"/>
<case ref="arm/orient-map-067-narrow" want="merged" got="unmerged" hit="0" reported="1"/>
</stray-eval>
`````

stderr:

`````
ripwire: warning: --stray-content read the newest 512 of 641 local branches; 129 older were not read (limit: 512 refs); pass --detail=1 to read every branch, or narrow the branches with a ref-name filter
`````

## `./build/ripwire skills --eval-skills=<scratch>/aux/skills_labels2.tsv`

*Labelled skill-ROUTING eval over the repo's own skills/ directory (4 hand-labelled prompts).*

**wall time: 1.09s**

Input file:

`````
orient in an unfamiliar codebase fast	ripwire-orient	judged
who calls this function and what is the blast radius	ripwire-navigate	judged
plan parallel worktrees so the lanes do not collide	ripwire-change-check	judged
what is the weather in Paris	none	neg
`````

`````
ripwire --eval-skills  (skill routing over K=16 candidate skills [ripwire-router excluded]; 3 positive + 1 negative prompts; corpus '<scratch>/aux/skills_labels2.tsv'; split test=4 … [line truncated: 7 more bytes on this line]
  arm           hit@1   hit@2     mrr   sep-auc   fire/abstain@ORACLE-th (upper bound)
  overlap       66.7%   66.7%   0.689     0.000    50.0% (th=-1.000)
  name          33.3%   66.7%   0.537     0.667    50.0% (th=0.000)
  bm25-desc     66.7%   66.7%   0.689     0.667    75.0% (th=2.867)
  bm25-full     33.3%   66.7%   0.611     1.000    50.0% (th=0.427)
  for-routed    33.3%   33.3%   0.556     1.000    50.0% (th=0.703)
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
… [19 more lines, 3720 bytes total]
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
… [13 more lines, 4536 bytes total]
`````

## `./build/ripwire --version`

*Version + short build info.*

`````
ripwire 0.6.10-dev.139+g6ace381eb (dev, AppleClang 21.0.0.21000101, emit=std::print, built_from=6ace381eb)
`````


---

# navigate — seeds, claims, slices, shapes

## `./build/ripwire . --at=src/graph.h:14621`

*Hold a LOCATION, not a name: the enclosing-definition chain at FILE:LINE (a compiler error, a diff hunk, a stack frame), outermost -> innermost.*

`````
<!-- ripwire at schema=ripwire.at/v1: enclosing-definition chain at p=:l=: sym= innermost, chain= outermost-first, <s n= t= l= el=> spans. root=: p= relative to it. -->
<at schema="ripwire.at/v1" p="src/graph.h" l="14621" sym="rankGraphTeleport" chain="1" root=".">
<s n="rankGraphTeleport" t="fn" l="14619" el="14647"/>
</at>
`````

## `./build/ripwire . --callers=@src/graph.h:14621`

*The same seed in a SELECTOR position: @FILE:LINE resolves to the innermost enclosing definition, then --callers runs on it.*

`````
<!-- ripwire callers schema=ripwire.callers/v1: 1-hop CALLERS of of= (defs= matched, count= distinct symbols): <s t= n= p=>; hop_tested=/hop_untested=. counts_floor=1: every count is a FLOOR, never a total. graph_ambiguous=/graph_unresolved=: resolver gauge. graph_unindexed=N: N files no grammar could read (the map header's unindexed=); their calls raise neither gauge. root=: p= relative to it. <s sites_at=>: its leaf-name calls not proven elsewhere, as [file:]line (p=: def line, default file); not proof each binds. next=: the one pasteable follow-up. -->
<callers schema="ripwire.callers/v1" of="@src/graph.h:14621" defs="1" count="7" root="." hop_tested="0" hop_untested="7" graph_ambiguous="3634" graph_unresolved="20069" graph_unindexed="313" counts_floor="1" next="--uses=@src/graph.h:14621">
<s t="fn" n="getIndex" p="src/mcpindex.h:1224" sites_at="1340"/>
<s t="fn" n="rankGraph" p="src/graph.h:14662" sites_at="14666"/>
<s t="fn" n="anchoredLexicalRank" p="src/graph.h:15331" sites_at="15382"/>
<s t="fn" n="runEval" p="src/eval.h:171" sites_at="328"/>
<s t="fn" n="churnDecayRanking" p="src/main.cpp:1432" sites_at="1446"/>
<s t="fn" n="churnRankedGraph" p="src/main.cpp:1471" sites_at="1485 1486 1500"/>
<s t="fn" n="runDefaultMap" p="src/main.cpp:1758" sites_at="1878"/>
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
ripwire: the at flag's seed 'src/graph.h:999999' named no location (./src/graph.h has only 21045 lines — the seed asked for line 999999)
`````

## `./build/ripwire . --verify="calls(runDefaultMap, rankGraphTeleport)"`

*VERIFY a closed claim in one call: three-valued verdict (confirmed / refuted / not-established) with the evidence rows inline.*

**wall time: 2.59s**

`````
<!-- ripwire verify schema=ripwire.verify/v1: ONE structured claim, verdict=confirmed|refuted|unknown, its witness rows <s t= n= p=> inline. window: shown= capped= (capped=1 cut). counts_floor=1: every count is a FLOOR, never a total. graph_ambiguous=/graph_unresolved=: resolver gauge. graph_unindexed=N: N files no grammar could read (the map header's unindexed=); their calls raise neither gauge. root=: p= relative to it. claim=/shape=: the claim as given and its shape; from_defs=/to_defs=: defs each name resolved to. hops=N: call edges on the witness path (a confirmed reach claim only). -->
<verify schema="ripwire.verify/v1" claim="calls(runDefaultMap, rankGraphTeleport)" shape="calls" verdict="confirmed" from_defs="1" to_defs="1" hops="1" root="." graph_ambiguous="3634" graph_unresolved="20069" graph_unindexed="313" counts_floor="1" shown="2" capped="0">
<s t="fn" n="runDefaultMap" p="src/main.cpp:1758"/>
<s t="fn" n="rankGraphTeleport" p="src/graph.h:14619"/>
</verify>
`````

## `./build/ripwire . --verify="unused(rankGraphTeleport)"`

*A claim that is FALSE — the refuted shape, with the references that refute it.*

`````
<!-- ripwire verify schema=ripwire.verify/v1: ONE structured claim, verdict=confirmed|refuted|unknown, its witness rows <s t= n= p=> inline. window: shown= capped= (capped=1 cut). counts_floor=1: every count is a FLOOR, never a total. graph_ambiguous=/graph_unresolved=: resolver gauge. graph_unindexed=N: N files no grammar could read (the map header's unindexed=); their calls raise neither gauge. root=: p= relative to it. claim=/shape=: the claim as given and its shape; from_defs=/to_defs=: defs each name resolved to. -->
<verify schema="ripwire.verify/v1" claim="unused(rankGraphTeleport)" shape="unused" verdict="refuted" defs="1" external="0" count="9" root="." graph_ambiguous="3634" graph_unresolved="20069" graph_unindexed="313" counts_floor="1" shown="9" capped="0">
<u role="call" p="src/eval.h:328" in_id="src/eval.h::rw::runEval"/>
<u role="call" p="src/graph.h:14666" in_id="src/graph.h::rw::rankGraph"/>
<u role="call" p="src/graph.h:15382" in_id="src/graph.h::rw::anchoredLexicalRank"/>
<u role="call" p="src/main.cpp:1446" in_id="churnDecayRanking"/>
<u role="call" p="src/main.cpp:1485" in_id="churnRankedGraph"/>
<u role="call" p="src/main.cpp:1486" in_id="churnRankedGraph"/>
<u role="call" p="src/main.cpp:1500" in_id="churnRankedGraph"/>
<u role="call" p="src/main.cpp:1878" in_id="runDefaultMap"/>
<u role="call" p="src/mcpindex.h:1340" in_id="src/mcpindex.h::rw::getIndex"/>
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

**wall time: 2.54s**

`````
<!-- ripwire slice schema=ripwire.slice/v1: name-based def-use rows of one variable in one definition: <s l= k=def|use|both|scope t= [b= pp= rd=]> (rd= reaching-def lines per reach=cfg|linear), <v n= l= t=> inventory; steps=/depth= flow. at=: commit+dirty+shallow. root=: p= relative to it. sym=/lang=: the sliced definition's name and language; p= is its file:line. vars=N: sliceable local bindings in the definition, one v row each; name one to slice it. counts=as-classified: defs=/uses=/vars=/steps= count what the name classifier rowed; neither floors nor totals. -->
<slice sym="rankGraphTeleport" p="src/graph.h:14619" t="fn" lang="cpp" schema="ripwire.slice/v1" vars="14" at="6ace381eb" root="." counts="as-classified">
<v n="alpha" l="14619" t="param"/>
<v n="g" l="14619" t="param"/>
<v n="p" l="14619" t="param"/>
<v n="pw" l="14622" t="decl"/>
<v n="N" l="14623" t="decl"/>
<v n="teleport" l="14624" t="decl"/>
<v n="rankDouble" l="14625" t="decl"/>
<v n="run" l="14626" t="decl"/>
<v n="teleportMass" l="14629" t="decl"/>
<v n="value" l="14630" t="decl"/>
<v n="inverseMass" l="14636" t="decl"/>
<v n="value" l="14637" t="decl"/>
<v n="r" l="14644" t="decl"/>
<v n="value" l="14645" t="param"/>
</slice>
`````

## `./build/ripwire . --slice=rankGraphTeleport:teleport`

*Intra-procedural def-use slice of ONE variable: one <s> row per line touching it, k=def|use|both, reaching definitions flow-sensitive (reach=cfg).*

**wall time: 2.99s**

`````
<!-- ripwire slice schema=ripwire.slice/v1: name-based def-use rows of one variable in one definition: <s l= k=def|use|both|scope t= [b= pp= rd=]> (rd= reaching-def lines per reach=cfg|linear), <v n= l= t=> inventory; steps=/depth= flow. at=: commit+dirty+shallow. root=: p= relative to it. sym=/lang=: the sliced definition's name and language; p= is its file:line. order=defuse: seed s rows (no v=) ranked among these rows by def-use coverage (distinct local names on the line) desc, then line; not source order, not a whole-function ranking (measured at chance — docs/EVALS.md) — flow s rows (v=) keep their (d=,l=,v=) order. counts=as-classified: defs=/uses=/vars=/steps= count what the name classifier rowed; neither floors nor totals. -->
<slice sym="rankGraphTeleport" p="src/graph.h:14619" t="fn" lang="cpp" schema="ripwire.slice/v1" var="teleport" defs="1" uses="3" reach="cfg" order="defuse" at="6ace381eb" root="." counts="as-classified">
<s l="14642" k="use" t="call-arg" rd="14624">
<![CDATA[run = pageRankDouble( g.inEdges, g.wOutDeg, teleport, rankDouble, PageRankConfig{ .alpha = double( alpha ) } );]]>
</s>
<s l="14624" k="def" t="decl">
<![CDATA[std::vector<double> teleport( pw.begin(), pw.end() );]]>
</s>
<s l="14630" k="use" t="read" rd="14624">
<![CDATA[for( const double value : teleport )]]>
</s>
<s l="14637" k="use" t="read" rd="14624">
<![CDATA[for( double& value : teleport )]]>
</s>
</slice>
`````

## `./build/ripwire . --slice=rankGraphTeleport:teleport --slice-flow=back --slice-depth=3`

*TRANSITIVE backward value-flow from the seed variable, bounded BFS (depth= disclosed; a cut frontier says flow_truncated=1).*

**wall time: 3.46s**

`````
<!-- ripwire slice schema=ripwire.slice/v1: name-based def-use rows of one variable in one definition: <s l= k=def|use|both|scope t= [b= pp= rd=]> (rd= reaching-def lines per reach=cfg|linear), <v n= l= t=> inventory; steps=/depth= flow. at=: commit+dirty+shallow. root=: p= relative to it. sym=/lang=: the sliced definition's name and language; p= is its file:line. order=defuse: seed s rows (no v=) ranked among these rows by def-use coverage (distinct local names on the line) desc, then line; not source order, not a whole-function ranking (measured at chance — docs/EVALS.md) — flow s rows (v=) keep their (d=,l=,v=) order. counts=as-classified: defs=/uses=/vars=/steps= count what the name classifier rowed; neither floors nor totals. -->
<slice sym="rankGraphTeleport" p="src/graph.h:14619" t="fn" lang="cpp" schema="ripwire.slice/v1" var="teleport" defs="1" uses="3" reach="cfg" flow="back" depth="3" steps="3" order="defuse" at="6ace381eb" root="." counts="as-classified">
<s l="14642" k="use" t="call-arg" rd="14624">
<![CDATA[run = pageRankDouble( g.inEdges, g.wOutDeg, teleport, rankDouble, PageRankConfig{ .alpha = double( alpha ) } );]]>
</s>
<s l="14624" k="def" t="decl">
<![CDATA[std::vector<double> teleport( pw.begin(), pw.end() );]]>
</s>
<s l="14630" k="use" t="read" rd="14624">
<![CDATA[for( const double value : teleport )]]>
</s>
<s l="14637" k="use" t="read" rd="14624">
<![CDATA[for( double& value : teleport )]]>
</s>
<s l="14622" k="def" t="decl" v="pw" d="1" f="14624">
<![CDATA[const std::vector<float> pw = biasPrior( g, p );]]>
</s>
<s l="14619" k="def" t="param" v="g" d="2" f="14622">
<![CDATA[inline RankedGraph rankGraphTeleport( const Graph& g, const std::vector<float>& p, float alpha = 0.85f )]]>
</s>
<s l="14619" k="def" t="param" v="p" d="2" f="14622">
<![CDATA[inline RankedGraph rankGraphTeleport( const Graph& g, const std::vector<float>& p, float alpha = 0.85f )]]>
</s>
</slice>
`````

## `./build/ripwire . --slice=rankGraphTeleport:teleport --slice-flow=fwd`

*Forward flow: which statements the seed's value reaches, at the default depth bound.*

**wall time: 2.82s**

`````
<!-- ripwire slice schema=ripwire.slice/v1: name-based def-use rows of one variable in one definition: <s l= k=def|use|both|scope t= [b= pp= rd=]> (rd= reaching-def lines per reach=cfg|linear), <v n= l= t=> inventory; steps=/depth= flow. at=: commit+dirty+shallow. root=: p= relative to it. sym=/lang=: the sliced definition's name and language; p= is its file:line. order=defuse: seed s rows (no v=) ranked among these rows by def-use coverage (distinct local names on the line) desc, then line; not source order, not a whole-function ranking (measured at chance — docs/EVALS.md) — flow s rows (v=) keep their (d=,l=,v=) order. counts=as-classified: defs=/uses=/vars=/steps= count what the name classifier rowed; neither floors nor totals. -->
<slice sym="rankGraphTeleport" p="src/graph.h:14619" t="fn" lang="cpp" schema="ripwire.slice/v1" var="teleport" defs="1" uses="3" reach="cfg" flow="fwd" depth="8" steps="7" order="defuse" at="6ace381eb" root="." counts="as-classified">
<s l="14642" k="use" t="call-arg" rd="14624">
<![CDATA[run = pageRankDouble( g.inEdges, g.wOutDeg, teleport, rankDouble, PageRankConfig{ .alpha = double( alpha ) } );]]>
</s>
<s l="14624" k="def" t="decl">
<![CDATA[std::vector<double> teleport( pw.begin(), pw.end() );]]>
</s>
<s l="14630" k="use" t="read" rd="14624">
<![CDATA[for( const double value : teleport )]]>
</s>
<s l="14637" k="use" t="read" rd="14624">
<![CDATA[for( double& value : teleport )]]>
</s>
<s l="14632" k="use" t="read" v="value" d="2" f="14630" b="14630">
<![CDATA[teleportMass += value;]]>
</s>
<s l="14639" k="both" t="assign" v="value" d="2" f="14637" b="14637">
<![CDATA[value *= inverseMass;]]>
</s>
<s l="14646" k="use" t="read" v="run" d="2" f="14642">
<![CDATA[return { std::move( r ), run.iterationCount, run.hasConverged };]]>
</s>
<s l="14632" k="both" t="assign" v="teleportMass" d="3" f="14632">
<![CDATA[teleportMass += value;]]>
</s>
<s l="14634" k="use" t="read" v="teleportMass" d="3" f="14632">
<![CDATA[if( teleportMass > 0.0 )]]>
</s>
<s l="14636" k="use" t="read" v="teleportMass" d="3" f="14632">
<![CDATA[const double inverseMass = 1.0 / teleportMass;]]>
</s>
<s l="14639" k="use" t="read" v="inverseMass" d="4" f="14636">
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

**wall time: 3.39s**

`````
<!-- ripwire slice schema=ripwire.slice/v1: name-based def-use rows of one variable in one definition: <s l= k=def|use|both|scope t= [b= pp= rd=]> (rd= reaching-def lines per reach=cfg|linear), <v n= l= t=> inventory; steps=/depth= flow. at=: commit+dirty+shallow. root=: p= relative to it. sym=/lang=: the sliced definition's name and language; p= is its file:line. order=defuse: seed s rows (no v=) ranked among these rows by def-use coverage (distinct local names on the line) desc, then line; not source order, not a whole-function ranking (measured at chance — docs/EVALS.md) — flow s rows (v=) keep their (d=,l=,v=) order. counts=as-classified: defs=/uses=/vars=/steps= count what the name classifier rowed; neither floors nor totals. -->
<slice sym="rankGraphTeleport" p="src/graph.h:14619" t="fn" lang="cpp" schema="ripwire.slice/v1" var="teleport" defs="1" uses="3" reach="cfg" order="defuse" at="6ace381eb" root="." counts="as-classified">
<s l="14642" k="use" t="call-arg" rd="14624">
<![CDATA[run = pageRankDouble( g.inEdges, g.wOutDeg, teleport, rankDouble, PageRankConfig{ .alpha = double( alpha ) } );]]>
</s>
<s l="14624" k="def" t="decl">
<![CDATA[std::vector<double> teleport( pw.begin(), pw.end() );]]>
</s>
<s l="14630" k="use" t="read" rd="14624">
<![CDATA[for( const double value : teleport )]]>
</s>
<s l="14637" k="use" t="read" rd="14624">
<![CDATA[for( double& value : teleport )]]>
</s>
</slice>
`````

## `./build/ripwire . --pattern='rankGraphTeleport($A, $B, $C)'`

*Structural search written in CODE: $NAME binds one node; grammars=/shapes= disclose what the pattern became per grammar (a 3-argument call shape — the 2-argument spelling has no call site in this repo and correctly reports hits=0).*

**wall time: 2.04s**

`````
<!-- ripwire pattern schema=ripwire.pattern/v1: structural pattern hits with their enclosing symbol. window: shown= capped= (capped=1 cut). hits_capped=1: hits= is a floor. root=: p= relative to it. q=: the pattern as given; grammars=/shapes=: grammars it resolved for and the node kind it became in each; unsupported=: families this verb never serves. eligible_files=/skipped_files=/of_files=: files scanned / served-language files it did not resolve for, never read / all indexed. m p= in=: the hit's file:line and its enclosing symbol; the text is the matched node. -->
<pattern schema="ripwire.pattern/v1" hits="1" shown="1" capped="0" hits_capped="0" q="rankGraphTeleport($A, $B, $C)" grammars="cpp,cpp/cu,c,python,go,rust,typescript,tsx,swift,objc,javascript,java,csharp" shapes="cpp:call_expression,cpp/cu:call_expression,c:call_expression,python:call,go:call_expres … [line truncated: 309 more bytes on this line]
<m p="src/graph.h:14666" in="rankGraph">rankGraphTeleport( g, std::vector&lt;float&gt;( N, ranked ? 1.0f / float( ranked ) : 0.f ), alpha )</m>
</pattern>
`````

## `./build/ripwire . --pattern='DISCLOSE(...)'`

*The ellipsis form over a macro-shaped call site; unsupported= names the families this verb does not serve.*

**wall time: 1.78s**

`````
<!-- ripwire pattern schema=ripwire.pattern/v1: structural pattern hits with their enclosing symbol. window: shown= total= capped= has_more= next_offset= offset= limit= (capped=1 cut; next_offset= pastes as offset=). ellipsis_capped=: 1 = cut. hits_capped=1: hits= is a floor. root=: p= relative to it. q=: the pattern as given; grammars=/shapes=: grammars it resolved for and the node kind it became in each; unsupported=: families this verb never serves. eligible_files=/skipped_files=/of_files=: files scanned / served-language files it did not resolve for, never read / all indexed. ellipsis=first-match: one first-match-wins probe, not exhaustive; ellipsis_bound= its sibling cap; ellipsis_skipped= nodes abandoned over it (a floor). m p= in=: the hit's file:line and its enclosing symbol; the text is the matched node. -->
<pattern schema="ripwire.pattern/v1" hits="369" shown="100" capped="1" total="369" has_more="1" next_offset="100" offset="0" limit="0" hits_capped="0" q="DISCLOSE(...)" grammars="cpp,cpp/cu,c,python,go,rust,typescript,tsx,swift,objc,javascript,java,csharp" shapes="cpp:call_expression,cpp/cu:call_exp … [line truncated: 446 more bytes on this line]
<m p="src/abicheck.h:517" in="collectAuthoredSites">DISCLOSE( result, AbiResult::DisclosureWhy::NoMergeBase, "abi: no merge-base for a ref (unrelated history?) — that ref</m>
<m p="src/arch.h:512" in="parseArchRules">DISCLOSE( Diagnostics::answerRefused, "--arch exits 1 with path:line and the reason on stderr; no report is printed",   </m>
<m p="src/arch.h:846" in="readArchBaselineSidecar">DISCLOSE( baseline, ArchBaselineRead::DisclosureWhy::SymlinkRefused, "arch: refusing to read the arch baseline sidecar t</m>
<m p="src/arch.h:897" in="openArchBaselineSidecar">DISCLOSE( Diagnostics::answerRefused, "--baseline exits 1: pathguard names the refused link on stderr and the verb says </m>
<m p="src/atoms.h:372" in="collectExclusions">DISCLOSE( ex, Exclusions::DisclosureWhy::ForHeaderSaturated, "atoms: the for-header exclusion stream spent its whole bud</m>
<m p="src/atoms.h:376" in="collectExclusions">DISCLOSE( ex, Exclusions::DisclosureWhy::StmtCrementSaturated, "atoms: the statement-crement exclusion stream spent its </m>
<m p="src/atoms.h:380" in="collectExclusions">DISCLOSE( ex, Exclusions::DisclosureWhy::StmtAssignSaturated, "atoms: the statement-assign exclusion stream spent its wh</m>
<m p="src/atoms.h:384" in="collectExclusions">DISCLOSE( ex, Exclusions::DisclosureWhy::InnerCommaSaturated, "atoms: the inner-comma exclusion stream spent its whole b</m>
<m p="src/clones.h:1321" in="walkByBucket">DISCLOSE( st_, Type3Stats::DisclosureWhy::PairCapHit, "clones: Type-3 pair cap hit — first N compared (both-gate-survi</m>
<m p="src/commentcoherence.h:216" in="computeCommentCoherence">DISCLOSE( scan, CommentCoherenceScan::DisclosureWhy::UnreadableFile, "comment-coherence: an indexed file could not be re</m>
<m p="src/crossref.h:603" in="streamOversizeInPieces">DISCLOSE( st, StreamBlobStats::DisclosureWhy::StreamEndedMidBlob,                   "crossref: git cat-file stream ended</m>
<m p="src/crossref.h:640" in="streamBlobs">DISCLOSE( st, StreamBlobStats::DisclosureWhy::ListUnwritable, "crossref: cannot write the blob-batch list — cross-bran</m>
<m p="src/crossref.h:656" in="streamBlobs">DISCLOSE( st, StreamBlobStats::DisclosureWhy::BatchNotStarted, "crossref: git cat-file --batch failed to start — cross</m>
<m p="src/crossref.h:710" in="streamBlobs">DISCLOSE( st, StreamBlobStats::DisclosureWhy::StreamEndedMidBlob,                       "crossref: git cat-file stream e</m>
<m p="src/crossref.h:977" in="refCommitTime">DISCLOSE( sink, RefEnumeration::DisclosureWhy::DateUnreadable, "crossref: for-each-ref yielded a ref with no readable co</m>
<m p="src/crossref.h:1013" in="enumerateRefs">DISCLOSE( dropSink, RefEnumeration::DisclosureWhy::TipNotObjectName, "crossref: for-each-ref yielded a ref whose tip is </m>
<m p="src/crossref.h:1111" in="diffRaw">DISCLOSE( "crossref: refusing a diff whose revision arguments are not resolved object names" )</m>
<m p="src/crossref.h:1197" in="parallelIndexed">DISCLOSE( sweep, ParallelSweep::DisclosureWhy::WorkerThrew, "crossref: a git worker threw — this shard of the sweep is</m>
<m p="src/crossref.h:1265" in="streamBlobsInSlices">DISCLOSE( stats, StreamBlobStats::DisclosureWhy::BatchNotStarted, "crossref: a blob-stream slice was never read — comp</m>
<m p="src/crossref.h:1581" in="probeRefBase">DISCLOSE( plumb, RefPlumbing::DisclosureWhy::RevisionNotObjectName, "crossref: ref tip or HEAD is not a resolved object </m>
<m p="src/crossref.h:1592" in="probeRefBase">DISCLOSE( plumb, RefPlumbing::DisclosureWhy::MergeBaseNotObjectName, "crossref: merge-base returned something that is no</m>
<m p="src/crossref.h:1599" in="probeRefBase">DISCLOSE( plumb, RefPlumbing::DisclosureWhy::NoMergeBase, "crossref: no merge-base for ref (shallow clone or unrelated h</m>
<m p="src/crossref.h:1751" in="probeRefBases">DISCLOSE( plumbing[ i ], RefPlumbing::DisclosureWhy::NoMergeBase, "crossref: no merge-base for ref (shallow clone or unr</m>
<m p="src/crossref.h:2772" in="lsTree">DISCLOSE( "crossref: refusing to list a tree whose revision argument is not a resolved object name" )</m>
<m p="src/crossref.h:3166" in="relabelHeadHitsFromIndex">DISCLOSE( "whereis: the index's def sites match no HEAD row (working tree drifted from HEAD?) — keeping the lexical la</m>
<m p="src/crossref.h:3439" in="readBranchParseBatch">DISCLOSE( reads[ k ], BranchBlobReadBack::DisclosureWhy::NotReadBackWhole,                       "whereis: a blob the pa</m>
<m p="src/crossref.h:3688" in="scanWorktree">DISCLOSE( scan, WorktreeScan::DisclosureWhy::ListingFailed, "whereis: git could not list the working tree's changes — </m>
<m p="src/crossref.h:3698" in="scanWorktree">DISCLOSE( scan, WorktreeScan::DisclosureWhy::OverPathCap, "whereis: more changed paths than the overlay reads — the re</m>
… [73 more display lines; full output is 18272 bytes on 1 raw line(s)]
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
<hit l= in=>CDATA text</hit> (<b>/<a> context around it); complete=1 only for an exhaustive literal scan (beside pattern_meta=, of the literal reading only); <unindexed> = off-index. window: shown= capped= (capped=1 cut). hits_capped=1: hits= is a floor. root=: p= relative to it. parse_degraded=1: E … [line truncated: 1693 more bytes on this line]
<grep pattern="DISCLOSE" schema="ripwire.grep/v1" root="." terms="DISCLOSE +cache" scope="line" terms_suppressed="1139" files="10" hits="31" shown="31" capped="0" hits_capped="0" suppressed_comment="2" suppressed_string="8" tier_parsed="14" tier_unclassified="0" corpus_oversize="15" corpus_pruned_di … [line truncated: 121 more bytes on this line]
<f p="src/ingest_cache.h">
<hit l="2314" in="openCacheFrame" n="6">
<![CDATA[            DISCLOSE( Diagnostics::answerUnchanged, "a rejected cache is rebuilt from source: this run parses and answers byte-identically",]]>
<at l="2322" in="openCacheFrame"/>
<at l="2330" in="openCacheFrame"/>
<at l="2402" in="openCacheFrame"/>
<at l="2568" in="ByteR::fitsBelow"/>
<at l="3001" in="readFileRecord"/>
</hit>
<hit l="2362" in="openCacheFrame" n="6">
<![CDATA[        DISCLOSE( Diagnostics::answerUnchanged, "a rejected cache is rebuilt from source: this run parses and answers byte-identically",]]>
<at l="2380" in="openCacheFrame"/>
<at l="2744" in="readRefQualifier"/>
<at l="2813" in="readDef"/>
<at l="2823" in="readDef"/>
<at l="3010" in="readFileRecord"/>
</hit>
<hit l="3047" in="readFileRecord" n="2">
<![CDATA[                DISCLOSE( Diagnostics::answerUnchanged, "a rejected cache is rebuilt from source: this run parses and answers byte-identically",]]>
<at l="3443" in="loadCache"/>
</hit>
<hit l="4023" in="saveCache">
<![CDATA[        DISCLOSE( Diagnostics::answerUnchanged, "this answer is already computed in memory: only the next run starts cold", "ingest: saveCache rename(tmp -> cache) failed — old cache preserved" );]]>
</hit>
</f>
<f p="src/ingest_crawl.h" parse_degraded="1">
<hit l="2349" in="isReadableCacheBlob">
… [139 more display lines; full output is 11580 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --grep=DISCLOSE --not=test --grep-scope=file`

*Drop every hit in a file that ALSO contains the --not literal anywhere (file scope).*

`````
<!-- ripwire grep schema=ripwire.grep/v1: literal/regex scan grouped by file: <f p=>
<hit l= in=>CDATA text</hit> (<b>/<a> context around it); complete=1 only for an exhaustive literal scan (beside pattern_meta=, of the literal reading only); <unindexed> = off-index. window: shown= capped= (capped=1 cut). hits_capped=1: hits= is a floor. root=: p= relative to it. parse_degraded=1: E … [line truncated: 1589 more bytes on this line]
<grep pattern="DISCLOSE" schema="ripwire.grep/v1" root="." terms="DISCLOSE -test" scope="file" terms_suppressed="1129" files="6" hits="18" shown="18" capped="0" hits_capped="0" suppressed_comment="31" suppressed_string="3" tier_parsed="25" tier_unclassified="0" corpus_oversize="15" corpus_pruned_dir … [line truncated: 123 more bytes on this line]
<f p="src/commentcoherence.h" parse_degraded="1">
<hit l="216" in="rw::computeCommentCoherence">
<![CDATA[                DISCLOSE( scan, CommentCoherenceScan::DisclosureWhy::UnreadableFile, "comment-coherence: an indexed file could not be read — its functions are absent from the report" );]]>
</hit>
</f>
<f p="src/forctorhop.h">
<hit l="167" in="rw::spliceCtorHop">
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
… [106 more display lines; full output is 8783 bytes on 1 raw line(s)]
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

**wall time: 1.07s**

`````
<!-- ripwire grep schema=ripwire.grep/v1: literal/regex scan grouped by file: <f p=>
<hit l= in=>CDATA text</hit> (<b>/<a> context around it); complete=1 only for an exhaustive literal scan (beside pattern_meta=, of the literal reading only); <unindexed> = off-index. window: shown= total= capped= has_more= next_offset= offset= limit= (capped=1 cut; next_offset= pastes as offset=). h … [line truncated: 1741 more bytes on this line]
<grep pattern="DISCLOSE" schema="ripwire.grep/v1" root="." files="314" hits="1151" shown="100" capped="1" total="1151" has_more="1" next_offset="100" offset="0" limit="0" hits_capped="0" corpus_oversize="15" corpus_pruned_dirs="7" unindexed_hits="15" unindexed_files_scanned="327" unindexed_files_ski … [line truncated: 62 more bytes on this line]
<f p=".coderabbit.yaml">
<hit l="33" in="path_instructions" occ="2">
<![CDATA[        A degrade path uses DISCLOSE( sink, why ), never ASSUME(false): a one-argument DISCLOSE( msg ) is a debug trace]]>
</hit>
</f>
<f p=".github/workflows/ci.yml">
<hit l="389" in="release">
<![CDATA[    #   Release — defines NDEBUG, which compiles the DISCLOSE( msg ) trace out; the optimizer-visible build.]]>
</hit>
<hit l="390" in="release">
<![CDATA[    #   plain   — NDEBUG off, so the DISCLOSE( msg ) trace compiles in and the degrade-path gates can observe]]>
</hit>
</f>
<f p="docs/limits_build.py">
<hit l="3">
<![CDATA[# whether the file it lives in DISCLOSES a truncation when it fires.]]>
</hit>
</f>
<f p="scripts/optremarks.py">
<hit l="153" in="COLD_FILES">
<![CDATA[      "the ASSUME / DISCLOSE handlers. They run on a degrade path: once, after something has already gone wrong." ),]]>
</hit>
</f>
<f p="src/abicheck.h" parse_degraded="1">
<hit l="111">
<![CDATA[#include "infra/Diagnostics.h"  // ASSUME / DISCLOSE]]>
</hit>
… [437 more display lines; full output is 27699 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --grep=deterministic`

*A literal whose classified hits are all prose: the answer serves tier="comment+string" rather than an empty code tier, and tier_unclassified= says how many hits the fixed parse budget never classified.*

`````
<!-- ripwire grep schema=ripwire.grep/v1: literal/regex scan grouped by file: <f p=>
<hit l= in=>CDATA text</hit> (<b>/<a> context around it); complete=1 only for an exhaustive literal scan (beside pattern_meta=, of the literal reading only); <unindexed> = off-index. window: shown= total= capped= has_more= next_offset= offset= limit= (capped=1 cut; next_offset= pastes as offset=). c … [line truncated: 2311 more bytes on this line]
<grep pattern="deterministic" schema="ripwire.grep/v1" root="." files="590" hits="1388" shown="100" capped="1" total="1388" has_more="1" next_offset="100" offset="0" limit="0" hits_capped="0" suppressed_comment="226" tier="code+string" tier_partial="1" tier_parsed="68" tier_unclassified="1503" tier_ … [line truncated: 230 more bytes on this line]
<f p=".github/workflows/ci.yml">
<hit l="1007" in="windows">
<![CDATA[          # on the machine is not one deterministic build step (G3). Read it back rather than assume it took.]]>
</hit>
<hit l="1044" in="windows">
<![CDATA[          # 951-byte legend plus one bare <r>, is deterministic across two runs, and parses as well-formed]]>
</hit>
</f>
<f p="present/deck5_ripwire_build.js">
<hit l="127">
<![CDATA[  s.addText("A zero-runtime-dependency C++23 CLI that maps any codebase into a ranked, deterministic call graph for coding agents — and puts a tripwire on every claim it emits.",]]>
</hit>
<hit l="505">
<![CDATA[    ["Kotlin", "by @xCatG: calls resolve between Kotlin and Java, both ways; no sanitizer finding across 501 real .kt files, deterministic on ~9,500 more (#126)", CYAN],]]>
</hit>
<hit l="531" line_bytes="574">
<![CDATA[    "- Kotlin — merged: #126, merge commit 1ad9184a (2026-09-11); PR body, PR author xCatG: “vendored fwcd/tree-sitter-kotlin grammar … a JVM interop bridge that resolves Kotlin↔Java calls bidirectionally”; “Zero ASan/UBSan/LSan findings across 501 real .kt files (8 local Androi … [line truncated: 224 more bytes on this line]
</hit>
<hit l="601" line_bytes="532">
<![CDATA[    "FOOTER (the instruments). From the release notes' Highlights: 'Three readouts, all registered before the work began, and none of them a model's opinion. A frozen bank of 30 retrieval questions, each answered in ONE call on a 2,066-file C++ corpus pinned at one commit, scored on the gol … [line truncated: 224 more bytes on this line]
</hit>
<hit l="1467">
<![CDATA[  foot(s, "the MCP server exposes the same deterministic engine — one index, shared with the CLI, staleness-checked");]]>
</hit>
<hit l="1664">
<![CDATA[    ["2009", "Reciprocal Rank Fusion — Cormack et al.", "deterministic signal fusion (--rank-by=rrf)"],]]>
</hit>
… [674 more display lines; full output is 40263 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --grep=DISCLOSE --handles`

*h= on each editable enclosing-symbol row: a freshness-pinned identity an edit verb can target and must refuse on after any file change.*

`````
<!-- ripwire grep schema=ripwire.grep/v1: literal/regex scan grouped by file: <f p=>
<hit l= in=>CDATA text</hit> (<b>/<a> context around it); complete=1 only for an exhaustive literal scan (beside pattern_meta=, of the literal reading only); <unindexed> = off-index. window: shown= total= capped= has_more= next_offset= offset= limit= (capped=1 cut; next_offset= pastes as offset=). c … [line truncated: 2417 more bytes on this line]
<grep pattern="DISCLOSE" schema="ripwire.grep/v1" root="." files="291" hits="991" shown="100" capped="1" total="991" has_more="1" next_offset="100" offset="0" limit="0" hits_capped="0" suppressed_comment="159" suppressed_string="4" tier_parsed="77" tier_unclassified="770" tier_budget="bytes" tier_fi … [line truncated: 202 more bytes on this line]
<f p=".coderabbit.yaml">
<hit l="33" in="path_instructions" occ="2">
<![CDATA[        A degrade path uses DISCLOSE( sink, why ), never ASSUME(false): a one-argument DISCLOSE( msg ) is a debug trace]]>
</hit>
</f>
<f p="src/abicheck.h" parse_degraded="1">
<hit l="517" in="abicheck::collectAuthoredSites">
<![CDATA[            DISCLOSE( result, AbiResult::DisclosureWhy::NoMergeBase, "abi: no merge-base for a ref (unrelated history?) — that ref is counted, not compared" );]]>
</hit>
</f>
<f p="src/arch.h">
<hit l="512" in="rw::parseArchRules">
<![CDATA[        DISCLOSE( Diagnostics::answerRefused, "--arch exits 1 with path:line and the reason on stderr; no report is printed",]]>
</hit>
<hit l="846" in="rw::readArchBaselineSidecar">
<![CDATA[    if( sidecar.refused ) { DISCLOSE( baseline, ArchBaselineRead::DisclosureWhy::SymlinkRefused, "arch: refusing to read the arch baseline sidecar through a symlink" ); }]]>
</hit>
<hit l="897" in="rw::openArchBaselineSidecar">
<![CDATA[        DISCLOSE( Diagnostics::answerRefused, "--baseline exits 1: pathguard names the refused link on stderr and the verb says it cannot write the sidecar",]]>
</hit>
</f>
<f p="src/atoms.h">
<hit l="372" in="atomdetail::collectExclusions">
<![CDATA[        DISCLOSE( ex, Exclusions::DisclosureWhy::ForHeaderSaturated, "atoms: the for-header exclusion stream spent its whole budget; the rules reading it are suppressed this run" );]]>
</hit>
<hit l="376" in="atomdetail::collectExclusions">
<![CDATA[        DISCLOSE( ex, Exclusions::DisclosureWhy::StmtCrementSaturated, "atoms: the statement-crement exclusion stream spent its whole budget; the rules reading it are suppressed this run" );]]>
… [463 more display lines; full output is 33298 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --grep=DISCLOSE --legend=compact`

*The grep compact legend (ripwire.grep/v1).*

`````
<!-- ripwire grep schema=ripwire.grep/v1: literal/regex scan grouped by file: <f p=>
<hit l= in=>CDATA text</hit> (<b>/<a> context around it); complete=1 only for an exhaustive literal scan (beside pattern_meta=, of the literal reading only); <unindexed> = off-index. window: shown= total= capped= has_more= next_offset= offset= limit= (capped=1 cut; next_offset= pastes as offset=). c … [line truncated: 2304 more bytes on this line]
<grep pattern="DISCLOSE" schema="ripwire.grep/v1" root="." files="291" hits="991" shown="100" capped="1" total="991" has_more="1" next_offset="100" offset="0" limit="0" hits_capped="0" suppressed_comment="159" suppressed_string="4" tier_parsed="77" tier_unclassified="770" tier_budget="bytes" tier_fi … [line truncated: 202 more bytes on this line]
<f p=".coderabbit.yaml">
<hit l="33" in="path_instructions" occ="2">
<![CDATA[        A degrade path uses DISCLOSE( sink, why ), never ASSUME(false): a one-argument DISCLOSE( msg ) is a debug trace]]>
</hit>
</f>
<f p="src/abicheck.h" parse_degraded="1">
<hit l="517" in="abicheck::collectAuthoredSites">
<![CDATA[            DISCLOSE( result, AbiResult::DisclosureWhy::NoMergeBase, "abi: no merge-base for a ref (unrelated history?) — that ref is counted, not compared" );]]>
</hit>
</f>
<f p="src/arch.h">
<hit l="512" in="rw::parseArchRules">
<![CDATA[        DISCLOSE( Diagnostics::answerRefused, "--arch exits 1 with path:line and the reason on stderr; no report is printed",]]>
</hit>
<hit l="846" in="rw::readArchBaselineSidecar">
<![CDATA[    if( sidecar.refused ) { DISCLOSE( baseline, ArchBaselineRead::DisclosureWhy::SymlinkRefused, "arch: refusing to read the arch baseline sidecar through a symlink" ); }]]>
</hit>
<hit l="897" in="rw::openArchBaselineSidecar">
<![CDATA[        DISCLOSE( Diagnostics::answerRefused, "--baseline exits 1: pathguard names the refused link on stderr and the verb says it cannot write the sidecar",]]>
</hit>
</f>
<f p="src/atoms.h">
<hit l="372" in="atomdetail::collectExclusions">
<![CDATA[        DISCLOSE( ex, Exclusions::DisclosureWhy::ForHeaderSaturated, "atoms: the for-header exclusion stream spent its whole budget; the rules reading it are suppressed this run" );]]>
</hit>
<hit l="376" in="atomdetail::collectExclusions">
<![CDATA[        DISCLOSE( ex, Exclusions::DisclosureWhy::StmtCrementSaturated, "atoms: the statement-crement exclusion stream spent its whole budget; the rules reading it are suppressed this run" );]]>
… [463 more display lines; full output is 30177 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --for="tree-sitter parse of a source file" --legend=compact`

*The --for compact legend (ripwire.for/v1) — every data/completeness attribute kept.*

**wall time: 5.06s**

`````
<ctx task="tree-sitter parse of a source file" route="subtoken+body" root="." confidence="low" margin_pct="0" at="6ace381eb" doc_mentions="1" schema="ripwire.for/v1" bundle="compact" bodies="0" reason="compact-route" budget_bytes="7500" est_tokens="10141">
<!-- ripwire for schema=ripwire.for/v1: bundle=/bodies=/reason= the body posture; d: cx= ccx= complexity, in= callers (absent cx/ccx/in = 0), churn= amp= change, clone= tested= 1, sc= scope, id=p::sc::n; total= shown= capped=1 if cut; task= the query; d pure=1 const/constexpr sig, next= the follow-up to paste; d same_as=N: doc+sig text as row n=N (not repeated); route= name-exact(X)|subtoken+body[:broad|:declined]; confidence=/margin_pct= head score drop (low=flat); h l= p= n=, c n= l= p= (p= if not h's; same-named joined, shown= counts them), noedge= no callee resolved; fold kind=bodies: b t= n= p= l= top ranked rows' whole bodies, not the answer; served= of total= in budget_bytes=; slice/skip p= n= l=; skip bytes= next=; a skip makes sigs next= it, sigs_next= the signatures-only re-call; d mem= an owner's direct member names only, by the index (question words first, then owner's file, path, line, name), mem_more= names cut; t p= file outside sigs (weaker), t sym= its top symbols not in sigs/syms (a pointer, not the answer), r= rank (gap = trimmed); t order: code files first, then doc files (a code question); t page rows go on to file-page row 160 (code question: 160 code rows, docs within row 160); past page 0 (code question: past 40 code rows, a doc past row 40) listed last, head files skipped; past 120 of those p= only, p_only= counts them; t folded=class=N: N p= only rows of that class (doc|config|script|testdata|other) not listed, next= pages to them; d layer=: built-in arch layer (game|infra|render|math|audio|ai|test) from a dir name in p=; d e= its last line (absent=unknown, never 0; l= the name's line) [doc mentions: 1 doc, 1 symbol; doc_mentions=] -->
<!-- root= is the crawl root; p= below is RELATIVE to it (single-root only; absent => p= is ingest's own path, unchanged); at=this commit(+dirty). [budget_bytes= is the default BYTE target this ranked payload was shaped toward: row text shortens toward it, no row of the ranked head is removed for it (sigs past_target=)] [sigs capped=1 with shown=total: rows shrunk, none dropped] [sigs past_target=K: the last K rows are past the budget_bytes target, served because they are rows of the ranked head; none is cut] [sigs next=: one call serving all total= rows uncut] [docs_dropped=N: N shown rows have a doc comment not printed (r>24 always, r5..24 if capped)] [files_first=N: N rows moved so r=1..8 are distinct files' best rows, score order, a repeated name once; same rows; fold, hops keep score order]; lego/compose collapse to a counted stub by default (a disclosed cut): total= that section's own pre-cap row count, shown="0" capped="1" (nothing rendered here), next= names the sections=lego,compose flag that restores both sections byte-identically in one call est_tokens= prices this bundle in tokens -->
<sigs shown="40" total="40" capped="1" past_target="7" docs_dropped="25" files_first="7" next="--for='tree-sitter parse of a source file' --signatures-only --token-budget=5500">
<d l="28" e="63" n="topLevelEvidence" sc="rw::pythonrunner" p="src/pythonrunner.h" cx="4" ccx="3" in="2" churn="5" amp="15" r="1" next="--expand=src/pythonrunner.h:topLevelEvidence">inline bool topLevelEvidence( std::string_view source, const TSLanguage* language, const Predicate&amp; predicate )</d … [line truncated: 1 more bytes on this line]
<d l="45" e="45" n="kDefaultMaxFileBytes" sc="rw" p="src/ingest.h" churn="72" amp="185" pure="1" r="2">
<doc>The crawl&apos;s per-file byte ceiling. A text file larger than this is skipped: at this size it is o…</doc>constexpr std::size_t kDefaultMaxFileBytes = 4u * 1024u * 1024u</d>
<d l="1247" e="1255" n="parseTree" p="src/ingest_sidecap.h" cx="1" in="4" churn="181" amp="364" tested="1" r="3">TSTree* parseTree( TSParser* parser, std::string_view src )</d>
<d l="594" e="669" n="doctorProbeGrammars" p="src/verbs_doctor.h" cx="7" ccx="17" in="1" churn="51" amp="150" r="4">
<doc>Exercise every registered grammar and its embedded query, reporting loaded and expected totals</doc>inline DoctorGrammarProbe doctorProbeGrammars()</d>
<d l="527" e="565" n="SourceReader" sc="SourceReader" p="src/forselfhook.h" churn="9" amp="8" r="5" mem="parsed">class SourceReader</d>
<d l="104" e="238" n="kLangTable" p="src/ingest_crawl.h" churn="90" amp="225" pure="1" r="6">constexpr std::array&lt;LangEntry, 58&gt; kLangTable =</d>
<d l="2495" e="2510" n="FileHealth" sc="FileHealth" p="src/model.h" churn="338" amp="570" r="7" mem="operator==">struct FileHealth</d>
<d l="308" e="343" n="SliceScan" sc="SliceScan" p="src/slice.h" churn="54" amp="102" r="8" mem="disclose">struct SliceScan</d>
<d l="138" e="152" n="ParsedFile::ParsedFile" p="src/forselfhook.h" cx="2" ccx="1" churn="9" amp="8" r="9">explicit ParsedFile( std::string bytes ) : m_bytes( std::move( bytes ) )</d>
<d l="135" e="177" n="ParsedFile" sc="ParsedFile" p="src/forselfhook.h" churn="9" amp="8" r="10" mem="operator=,usable,root,text">class ParsedFile</d>
<!-- demote: a <t> in sigs is a lower same-file sibling past answer row 10, a pointer (p= file, sym= name, r= rank), not the answer -->
<t p="src/ingest.h" sym="AstWalk" r="11"/>
<t p="src/ingest_sidecap.h" sym="astroFenceTailIsBlank" r="12"/>
<d l="386" e="459" n="sliceAtRev" sc="slicediff" p="src/slicediff.h" cx="14" ccx="15" in="1" churn="14" amp="76" r="13">inline RevSide sliceAtRev( const std::string&amp; root, const std::string&amp; sha, const std::string&amp; rel, const Symbol&amp; sym, SliceFam fam, const ::TSLanguage* grammar, st … [line truncated: 77 more bytes on this line]
<d l="2075" e="2104" n="collectGatedLocalNames" sc="rw" p="src/ingest_astquery.h" cx="6" ccx="5" in="1" churn="61" amp="178" r="14">std::vector&lt;LocalNameFact&gt; collectGatedLocalNames( std::string_view defBytes, std::uint32_t defStartLine, Lang lang )</d>
<d l="927" e="978" n="scanModule" sc="detail" p="src/jsrunner.h" cx="16" ccx="15" in="3" churn="22" amp="109" r="15">inline ModuleScan scanModule( std::string_view source, std::string_view path )</d>
<t p="src/ingest.h" sym="kMaxKotlinStringNestDepth" r="16"/>
<d l="87" e="97" n="hasMainGuard" sc="rw::pythonrunner" p="src/pythonrunner.h" cx="2" ccx="2" in="1" churn="5" amp="14" r="17">inline bool hasMainGuard( std::string_view source )</d>
<d l="255" e="259" n="hasPhantomScopeSeparator" p="src/ingest_names.h" cx="2" ccx="1" in="2" churn="86" amp="248" tested="1" r="18">inline bool hasPhantomScopeSeparator( TSNode qualified ) noexcept</d>
<t p="src/ingest_crawl.h" sym="jsonNestsTooDeep" r="19"/>
<t p="src/slice.h" sym="DisclosureWhy" r="20"/>
<t p="src/ingest.h" sym="kMaxYamlNestDepth" r="21"/>
<t p="src/ingest_astquery.h" sym="spanTiersOfFiles" r="22"/>
<t p="src/slice.h" sym="sliceScanDefinition" r="23"/>
… [242 more display lines; full output is 26711 bytes on 44 raw line(s)]
`````

## `./build/ripwire . --for="tree-sitter parse of a source file" --sections=lego,compose`

*Restore the <lego>/<compose> sections the --for bundle collapses to a counted stub by default (this is the stub's own next= spelling).*

**wall time: 6.35s**

`````
<ctx task="tree-sitter parse of a source file" route="subtoken+body" root="." confidence="low" margin_pct="0" at="6ace381eb" doc_mentions="1" schema="ripwire.for/v1" bundle="compact" bodies="0" reason="compact-route" budget_bytes="7500" est_tokens="10689">
<!-- ripwire for schema=ripwire.for/v1: bundle=/bodies=/reason= the body posture; d: cx= ccx= complexity, in= callers (absent cx/ccx/in = 0), churn= amp= change, clone= tested= 1, sc= scope, id=p::sc::n; total= shown= capped=1 if cut; task= the query; d pure=1 const/constexpr sig, next= the follow-up to paste; d same_as=N: doc+sig text as row n=N (not repeated); route= name-exact(X)|subtoken+body[:broad|:declined]; confidence=/margin_pct= head score drop (low=flat); h l= p= n=, c n= l= p= (p= if not h's; same-named joined, shown= counts them), noedge= no callee resolved; fold kind=bodies: b t= n= p= l= top ranked rows' whole bodies, not the answer; served= of total= in budget_bytes=; slice/skip p= n= l=; skip bytes= next=; a skip makes sigs next= it, sigs_next= the signatures-only re-call; d mem= an owner's direct member names only, by the index (question words first, then owner's file, path, line, name), mem_more= names cut; t p= file outside sigs (weaker), t sym= its top symbols not in sigs/syms (a pointer, not the answer), r= rank (gap = trimmed); t order: code files first, then doc files (a code question); t page rows go on to file-page row 160 (code question: 160 code rows, docs within row 160); past page 0 (code question: past 40 code rows, a doc past row 40) listed last, head files skipped; past 120 of those p= only, p_only= counts them; t folded=class=N: N p= only rows of that class (doc|config|script|testdata|other) not listed, next= pages to them; field name= type= owner= rel=: a member of owner=, rel=creates held by value, uses by reference/pointer; iface implementors=N: types implementing it, m= its method contract; d layer=: built-in arch layer (game|infra|render|math|audio|ai|test) from a dir name in p=; d e= its last line (absent=unknown, never 0; l= the name's line) [doc mentions: 1 doc, 1 symbol; doc_mentions=] -->
<!-- root= is the crawl root; p= below is RELATIVE to it (single-root only; absent => p= is ingest's own path, unchanged); at=this commit(+dirty). [budget_bytes= is the default BYTE target this ranked payload was shaped toward: row text shortens toward it, no row of the ranked head is removed for it (sigs past_target=)] [sigs capped=1 with shown=total: rows shrunk, none dropped] [sigs past_target=K: the last K rows are past the budget_bytes target, served because they are rows of the ranked head; none is cut] [sigs next=: one call serving all total= rows uncut] [docs_dropped=N: N shown rows have a doc comment not printed (r>24 always, r5..24 if capped)] [files_first=N: N rows moved so r=1..8 are distinct files' best rows, score order, a repeated name once; same rows; fold, hops keep score order]; iface implementors=N counts every type an extends/implements clause binds to it (the lego verb's count), never the rows listed: shown_implementors=K only K impl rows here (implementors_capped=1), implementors_next= lists all; implementors_floor=1 an extends clause spelled like it bound nowhere, so N may be short (not proof of another), floor_next= lists every extends site est_tokens= prices this bundle in tokens -->
<sigs shown="40" total="40" capped="1" past_target="7" docs_dropped="25" files_first="7" next="--for='tree-sitter parse of a source file' --signatures-only --token-budget=5500">
<d l="28" e="63" n="topLevelEvidence" sc="rw::pythonrunner" p="src/pythonrunner.h" cx="4" ccx="3" in="2" churn="5" amp="15" r="1" next="--expand=src/pythonrunner.h:topLevelEvidence">inline bool topLevelEvidence( std::string_view source, const TSLanguage* language, const Predicate&amp; predicate )</d … [line truncated: 1 more bytes on this line]
<d l="45" e="45" n="kDefaultMaxFileBytes" sc="rw" p="src/ingest.h" churn="72" amp="185" pure="1" r="2">
<doc>The crawl&apos;s per-file byte ceiling. A text file larger than this is skipped: at this size it is o…</doc>constexpr std::size_t kDefaultMaxFileBytes = 4u * 1024u * 1024u</d>
<d l="1247" e="1255" n="parseTree" p="src/ingest_sidecap.h" cx="1" in="4" churn="181" amp="364" tested="1" r="3">TSTree* parseTree( TSParser* parser, std::string_view src )</d>
<d l="594" e="669" n="doctorProbeGrammars" p="src/verbs_doctor.h" cx="7" ccx="17" in="1" churn="51" amp="150" r="4">
<doc>Exercise every registered grammar and its embedded query, reporting loaded and expected totals</doc>inline DoctorGrammarProbe doctorProbeGrammars()</d>
<d l="527" e="565" n="SourceReader" sc="SourceReader" p="src/forselfhook.h" churn="9" amp="8" r="5" mem="parsed">class SourceReader</d>
<d l="104" e="238" n="kLangTable" p="src/ingest_crawl.h" churn="90" amp="225" pure="1" r="6">constexpr std::array&lt;LangEntry, 58&gt; kLangTable =</d>
<d l="2495" e="2510" n="FileHealth" sc="FileHealth" p="src/model.h" churn="338" amp="570" r="7" mem="operator==">struct FileHealth</d>
<d l="308" e="343" n="SliceScan" sc="SliceScan" p="src/slice.h" churn="54" amp="102" r="8" mem="disclose">struct SliceScan</d>
<d l="138" e="152" n="ParsedFile::ParsedFile" p="src/forselfhook.h" cx="2" ccx="1" churn="9" amp="8" r="9">explicit ParsedFile( std::string bytes ) : m_bytes( std::move( bytes ) )</d>
<d l="135" e="177" n="ParsedFile" sc="ParsedFile" p="src/forselfhook.h" churn="9" amp="8" r="10" mem="operator=,usable,root,text">class ParsedFile</d>
<!-- demote: a <t> in sigs is a lower same-file sibling past answer row 10, a pointer (p= file, sym= name, r= rank), not the answer -->
<t p="src/ingest.h" sym="AstWalk" r="11"/>
<t p="src/ingest_sidecap.h" sym="astroFenceTailIsBlank" r="12"/>
<d l="386" e="459" n="sliceAtRev" sc="slicediff" p="src/slicediff.h" cx="14" ccx="15" in="1" churn="14" amp="76" r="13">inline RevSide sliceAtRev( const std::string&amp; root, const std::string&amp; sha, const std::string&amp; rel, const Symbol&amp; sym, SliceFam fam, const ::TSLanguage* grammar, st … [line truncated: 77 more bytes on this line]
<d l="2075" e="2104" n="collectGatedLocalNames" sc="rw" p="src/ingest_astquery.h" cx="6" ccx="5" in="1" churn="61" amp="178" r="14">std::vector&lt;LocalNameFact&gt; collectGatedLocalNames( std::string_view defBytes, std::uint32_t defStartLine, Lang lang )</d>
<d l="927" e="978" n="scanModule" sc="detail" p="src/jsrunner.h" cx="16" ccx="15" in="3" churn="22" amp="109" r="15">inline ModuleScan scanModule( std::string_view source, std::string_view path )</d>
<t p="src/ingest.h" sym="kMaxKotlinStringNestDepth" r="16"/>
<d l="87" e="97" n="hasMainGuard" sc="rw::pythonrunner" p="src/pythonrunner.h" cx="2" ccx="2" in="1" churn="5" amp="14" r="17">inline bool hasMainGuard( std::string_view source )</d>
<d l="255" e="259" n="hasPhantomScopeSeparator" p="src/ingest_names.h" cx="2" ccx="1" in="2" churn="86" amp="248" tested="1" r="18">inline bool hasPhantomScopeSeparator( TSNode qualified ) noexcept</d>
<t p="src/ingest_crawl.h" sym="jsonNestsTooDeep" r="19"/>
<t p="src/slice.h" sym="DisclosureWhy" r="20"/>
<t p="src/ingest.h" sym="kMaxYamlNestDepth" r="21"/>
<t p="src/ingest_astquery.h" sym="spanTiersOfFiles" r="22"/>
<t p="src/slice.h" sym="sliceScanDefinition" r="23"/>
… [264 more display lines; full output is 28081 bytes on 44 raw line(s)]
`````

## `./build/ripwire . --for="tree-sitter parse of a source file" --auto-bodies`

*Opt OUT of compact conceptual serving: restore the rank-first auto <bodies> walk (bundle="auto").*

**wall time: 5.30s**

`````
<ctx task="tree-sitter parse of a source file" route="subtoken+body" root="." confidence="low" margin_pct="0" at="6ace381eb" doc_mentions="1" schema="ripwire.for/v1" bundle="auto" bodies="5" budget_bytes="7500" est_tokens="10394">
<!-- ripwire for schema=ripwire.for/v1: bundle=/bodies=/reason= the body posture; d: cx= ccx= complexity, in= callers (absent cx/ccx/in = 0), churn= amp= change, clone= tested= 1, sc= scope, id=p::sc::n; total= shown= capped=1 if cut; task= the query; d pure=1 const/constexpr sig, next= the follow-up to paste; d same_as=N: doc+sig text as row n=N (not repeated); route= name-exact(X)|subtoken+body[:broad|:declined]; confidence=/margin_pct= head score drop (low=flat); b t= n= p= l= full bodies, c n= l= p= callee signatures (p= if not b's); t p= file outside sigs (weaker), t sym= its top symbols not in sigs/syms (a pointer, not the answer), r= rank (gap = trimmed); t order: code files first, then doc files (a code question); t page rows go on to file-page row 160 (code question: 160 code rows, docs within row 160); past page 0 (code question: past 40 code rows, a doc past row 40) listed last, head files skipped; past 120 of those p= only, p_only= counts them; t folded=class=N: N p= only rows of that class (doc|config|script|testdata|other) not listed, next= pages to them; d layer=: built-in arch layer (game|infra|render|math|audio|ai|test) from a dir name in p=; d e= its last line (absent=unknown, never 0; l= the name's line) [doc mentions: 1 doc, 1 symbol; doc_mentions=] -->
<!-- root= is the crawl root; p= below is RELATIVE to it (single-root only; absent => p= is ingest's own path, unchanged); at=this commit(+dirty). [budget_bytes= is the default BYTE target this ranked payload was shaped toward: row text shortens toward it, no row of the ranked head is removed for it (sigs past_target=)] [sigs capped=1 with shown=total: rows shrunk, none dropped] [sigs past_target=K: the last K rows are past the budget_bytes target, served because they are rows of the ranked head; none is cut] [sigs next=: one call serving all total= rows uncut] [docs_dropped=N: N shown rows have a doc comment not printed (r>24 always, r5..24 if capped)] [files_first=N: N rows moved so r=1..8 are distinct files' best rows, score order, a repeated name once; same rows; fold, hops keep score order]; lego/compose collapse to a counted stub by default (a disclosed cut): total= that section's own pre-cap row count, shown="0" capped="1" (nothing rendered here), next= names the sections=lego,compose flag that restores both sections byte-identically in one call est_tokens= prices this bundle in tokens -->
<sigs shown="40" total="40" capped="1" past_target="7" docs_dropped="25" files_first="7" next="--for='tree-sitter parse of a source file' --signatures-only --token-budget=5500">
<d l="28" e="63" n="topLevelEvidence" sc="rw::pythonrunner" p="src/pythonrunner.h" cx="4" ccx="3" in="2" churn="5" amp="15" r="1" next="--expand=src/pythonrunner.h:topLevelEvidence">inline bool topLevelEvidence( std::string_view source, const TSLanguage* language, const Predicate&amp; predicate )</d … [line truncated: 1 more bytes on this line]
<d l="45" e="45" n="kDefaultMaxFileBytes" sc="rw" p="src/ingest.h" churn="72" amp="185" pure="1" r="2">
<doc>The crawl&apos;s per-file byte ceiling. A text file larger than this is skipped: at this size it is o…</doc>constexpr std::size_t kDefaultMaxFileBytes = 4u * 1024u * 1024u</d>
<d l="1247" e="1255" n="parseTree" p="src/ingest_sidecap.h" cx="1" in="4" churn="181" amp="364" tested="1" r="3">TSTree* parseTree( TSParser* parser, std::string_view src )</d>
<d l="594" e="669" n="doctorProbeGrammars" p="src/verbs_doctor.h" cx="7" ccx="17" in="1" churn="51" amp="150" r="4">
<doc>Exercise every registered grammar and its embedded query, reporting loaded and expected totals</doc>inline DoctorGrammarProbe doctorProbeGrammars()</d>
<d l="527" e="565" n="SourceReader" sc="SourceReader" p="src/forselfhook.h" churn="9" amp="8" r="5">class SourceReader</d>
<d l="104" e="238" n="kLangTable" p="src/ingest_crawl.h" churn="90" amp="225" pure="1" r="6">constexpr std::array&lt;LangEntry, 58&gt; kLangTable =</d>
<d l="2495" e="2510" n="FileHealth" sc="FileHealth" p="src/model.h" churn="338" amp="570" r="7">struct FileHealth</d>
<d l="308" e="343" n="SliceScan" sc="SliceScan" p="src/slice.h" churn="54" amp="102" r="8">struct SliceScan</d>
<d l="138" e="152" n="ParsedFile::ParsedFile" p="src/forselfhook.h" cx="2" ccx="1" churn="9" amp="8" r="9">explicit ParsedFile( std::string bytes ) : m_bytes( std::move( bytes ) )</d>
<d l="135" e="177" n="ParsedFile" sc="ParsedFile" p="src/forselfhook.h" churn="9" amp="8" r="10">class ParsedFile</d>
<!-- demote: a <t> in sigs is a lower same-file sibling past answer row 10, a pointer (p= file, sym= name, r= rank), not the answer -->
<t p="src/ingest.h" sym="AstWalk" r="11"/>
<t p="src/ingest_sidecap.h" sym="astroFenceTailIsBlank" r="12"/>
<d l="386" e="459" n="sliceAtRev" sc="slicediff" p="src/slicediff.h" cx="14" ccx="15" in="1" churn="14" amp="76" r="13">inline RevSide sliceAtRev( const std::string&amp; root, const std::string&amp; sha, const std::string&amp; rel, const Symbol&amp; sym, SliceFam fam, const ::TSLanguage* grammar, st … [line truncated: 77 more bytes on this line]
<d l="2075" e="2104" n="collectGatedLocalNames" sc="rw" p="src/ingest_astquery.h" cx="6" ccx="5" in="1" churn="61" amp="178" r="14">std::vector&lt;LocalNameFact&gt; collectGatedLocalNames( std::string_view defBytes, std::uint32_t defStartLine, Lang lang )</d>
<d l="927" e="978" n="scanModule" sc="detail" p="src/jsrunner.h" cx="16" ccx="15" in="3" churn="22" amp="109" r="15">inline ModuleScan scanModule( std::string_view source, std::string_view path )</d>
<t p="src/ingest.h" sym="kMaxKotlinStringNestDepth" r="16"/>
<d l="87" e="97" n="hasMainGuard" sc="rw::pythonrunner" p="src/pythonrunner.h" cx="2" ccx="2" in="1" churn="5" amp="14" r="17">inline bool hasMainGuard( std::string_view source )</d>
<d l="255" e="259" n="hasPhantomScopeSeparator" p="src/ingest_names.h" cx="2" ccx="1" in="2" churn="86" amp="248" tested="1" r="18">inline bool hasPhantomScopeSeparator( TSNode qualified ) noexcept</d>
<t p="src/ingest_crawl.h" sym="jsonNestsTooDeep" r="19"/>
<t p="src/slice.h" sym="DisclosureWhy" r="20"/>
<t p="src/ingest.h" sym="kMaxYamlNestDepth" r="21"/>
<t p="src/ingest_astquery.h" sym="spanTiersOfFiles" r="22"/>
<t p="src/slice.h" sym="sliceScanDefinition" r="23"/>
… [272 more display lines; full output is 28497 bytes on 96 raw line(s)]
`````

## `./build/ripwire . --for="quality delta acks ledger rubber stamp"`

*Doc-mention surfacing (default ON): a markdown doc naming a top-resolved symbol in a backtick rides in below that symbol — the legend's [doc mentions: …] clause says it fired.*

**wall time: 5.66s**

`````
<ctx task="quality delta acks ledger rubber stamp" route="subtoken+body" root="." confidence="low" margin_pct="0" at="6ace381eb" doc_mentions="1" schema="ripwire.for/v1" bundle="compact" bodies="0" reason="compact-route" budget_bytes="7500" est_tokens="11819">
<!-- ripwire for schema=ripwire.for/v1: bundle=/bodies=/reason= the body posture; d: cx= ccx= complexity, in= callers (absent cx/ccx/in = 0), churn= amp= change, clone= tested= 1, sc= scope, id=p::sc::n; total= shown= capped=1 if cut; task= the query; d pure=1 const/constexpr sig, next= the follow-up to paste; route= name-exact(X)|subtoken+body[:broad|:declined]; confidence=/margin_pct= head score drop (low=flat); h l= p= n=, c n= l= p= (p= if not h's; same-named joined, shown= counts them), noedge= no callee resolved; h calls capped=1 next= the call listing every callee; fold kind=bodies: b t= n= p= l= top ranked rows' whole bodies, not the answer; served= of total= in budget_bytes=; slice/skip p= n= l=; skip bytes= next=; a skip makes sigs next= it, sigs_next= the signatures-only re-call; t p= file outside sigs (weaker), t sym= its top symbols not in sigs/syms (a pointer, not the answer), r= rank (gap = trimmed); t order: code files first, then doc files (a code question); t page rows go on to file-page row 160 (code question: 160 code rows, docs within row 160); past page 0 (code question: past 40 code rows, a doc past row 40) listed last, head files skipped; past 120 of those p= only, p_only= counts them; t folded=class=N: N p= only rows of that class (doc|config|script|testdata|other) not listed, next= pages to them; d e= its last line (absent=unknown, never 0; l= the name's line); c via=name: that callee matched by name alone, receiver unproven (NOT a claim the edge is false); c prov=split: a resolver split arm; may be another arm's (NOT a claim the edge is false) [doc mentions: 1 doc, 1 symbol; doc_mentions=] -->
<!-- root= is the crawl root; p= below is RELATIVE to it (single-root only; absent => p= is ingest's own path, unchanged); at=this commit(+dirty). [budget_bytes= is the default BYTE target this ranked payload was shaped toward: row text shortens toward it, no row of the ranked head is removed for it (sigs past_target=)] [sigs capped=1 with shown=total: rows shrunk, none dropped] [sigs past_target=K: the last K rows are past the budget_bytes target, served because they are rows of the ranked head; none is cut] [sigs sigs_next=: one call serving all total= rows uncut] [docs_dropped=N: N shown rows have a doc comment not printed (r>24 always, r5..24 if capped)] [docs_after_code=N: N doc rows of the shown set moved below its code rows; same rows, reordered, none added or removed; a question naming docs keeps score order] [files_first=N: N rows moved so r=1..8 are distinct files' best rows, score order, a repeated name once; same rows; fold, hops keep score order]; lego/compose collapse to a counted stub by default (a disclosed cut): total= that section's own pre-cap row count, shown="0" capped="1" (nothing rendered here), next= names the sections=lego,compose flag that restores both sections byte-identically in one call est_tokens= prices this bundle in tokens -->
<sigs shown="40" total="40" capped="1" past_target="12" docs_dropped="26" docs_after_code="1" files_first="28" sigs_next="--for='quality delta acks ledger rubber stamp' --signatures-only --token-budget=6100" next="--expand=src/mcpverbs.h:4905:computeQualityDelta">
<d l="2437" e="2458" n="refPairStaleAcks" p="src/verbs_quality.h" cx="6" ccx="6" in="1" churn="198" amp="309" r="1" next="--expand=src/verbs_quality.h:refPairStaleAcks">
<doc>L2 stale acks in the range form. A changed-files answer holds no whole target tree to check the …</doc>std::vector&lt;rw::quality::StaleAck&gt; refPairStaleAcks( const gtl::btree_map&lt;std::string, rw::quality::AckRecord&gt;&amp; acks, const RefPairDelta&amp; refs )</d>
<d l="4905" e="4984" n="computeQualityDelta" sc="rw" p="src/mcpverbs.h" cx="5" ccx="5" in="1" churn="675" amp="692" r="2">inline QualityDeltaOutcome computeQualityDelta( const std::string&amp; root )</d>
<d l="10776" e="10791" n="staleByKindValue" sc="quality" p="src/quality.h" cx="5" ccx="7" in="2" churn="684" amp="869" r="3">inline std::string staleByKindValue( const std::vector&lt;StaleAck&gt;&amp; staleAcks )</d>
<d l="2529" e="2531" n="kAtStampLegend" sc="rw" p="src/serialize.h" churn="515" amp="626" pure="1" r="4">inline constexpr const char* kAtStampLegend = &quot;&lt;!-- at= is the git commit these numbers were computed at</d>
<d l="5801" e="5811" n="runForLensPosture" p="src/verbs_for.h" cx="5" ccx="3" in="3" churn="422" amp="505" r="5">std::optional&lt;int&gt; runForLensPosture( const MainDispatch&amp; d, rw::ForAnswerLedger* ledger )</d>
<d l="314" e="371" n="computeDmm" sc="rw::dmm" p="src/dmm.h" cx="9" ccx="6" in="1" churn="16" amp="77" r="6">inline Result computeDmm( const std::string&amp; root, std::string_view spec, const IngestResult&amp; wo…</d>
<d l="67" e="67" n="kNotesFile" sc="rw::notes" p="src/notes.h" churn="20" amp="81" r="7">inline const char* kNotesFile = &quot;.ripwire_notes&quot;</d>
<d l="325" e="365" n="openRegularFileStream" sc="detail" p="src/docparse.h" cx="7" ccx="8" in="2" churn="40" amp="105" tested="1" r="8">inline rw::pathguard::NoFollowRead openRegularFileStream( std::string_view what, const std::stri…</d>
<d l="1106" e="1132" n="refPairBasis" p="src/verbs_quality.h" cx="4" ccx="3" in="1" churn="198" amp="309" r="9">
<doc>The REF-PAIR floor&apos;s comparison, once loadRefPairDelta has both sides: the base snapshot is the …</doc>void refPairBasis( const rw::Config&amp; cfg, const std::string&amp; root, RefPairDelta&amp; refs, DeltaBasis&amp; out )</d>
<d l="1401" e="1436" n="refuseForeignAckSelection" p="src/verbs_quality.h" cx="9" ccx="12" in="1" churn="198" amp="309" r="10">std::optional&lt;int&gt; refuseForeignAckSelection( const rw::Config&amp; cfg, const rw::quality::Scope&amp; scope, const std::vector&lt;rw::quality::Regression&gt;&amp; out … [line truncated: 18 more bytes on this line]
<d l="2638" e="3381" n="runQualityDelta" p="src/verbs_quality.h" cx="146" ccx="323" in="2" churn="198" amp="310" r="11">std::optional&lt;int&gt; runQualityDelta( const MainDispatch&amp; d )</d>
<d l="2259" e="2284" n="ackNothingToAccept" p="src/verbs_quality.h" cx="6" ccx="7" in="1" churn="198" amp="309" r="12">int ackNothingToAccept( const std::string&amp; acksFile, const gtl::btree_map&lt;std::string, rw::quality::AckRecord&gt;&amp; acks, const rw::quality::Scope&amp; scope, std::size… … [line truncated: 4 more bytes on this line]
<!-- demote: a <t> in sigs is a lower same-file sibling past answer row 10, a pointer (p= file, sym= name, r= rank), not the answer -->
<t p="src/verbs_quality.h" sym="DeltaBasis" r="13"/>
<t p="src/quality.h" sym="kAcksFile" r="14"/>
<t p="src/verbs_quality.h" sym="inspectDirtyBaselinePin" r="15"/>
<t p="src/quality.h" sym="IdentityHealing" r="16"/>
<d l="9509" e="9522" n="writeAckRecords" sc="quality" p="src/quality.h" cx="2" ccx="1" in="2" churn="684" amp="869" r="17">inline bool writeAckRecords( const std::string&amp; path, const gtl::btree_map&lt;std::string, AckRecord&gt;&amp; acks )</d>
<d l="5004" e="5136" n="qualityDeltaJson" sc="rw" p="src/mcpverbs.h" cx="30" ccx="48" in="1" churn="675" amp="692" r="18">inline std::pair&lt;std::string, std::string&gt; qualityDeltaJson( const std::string&amp; root, bool showStale = false )</d>
<d l="4793" e="4793" n="qualityAcksPath" sc="rw" p="src/mcpverbs.h" cx="1" in="1" churn="675" amp="692" r="19">inline std::string qualityAcksPath( const std::string&amp; root )</d>
<d l="10732" e="10770" n="staleAcksXml" sc="quality" p="src/quality.h" cx="5" ccx="8" in="1" churn="684" amp="868" r="20">inline std::string staleAcksXml( const std::vector&lt;StaleAck&gt;&amp; staleAcks, EscapeFn esc )</d>
<t p="src/mcpverbs.h" sym="QualityDeltaOutcome" r="21"/>
<d l="2937" e="2940" n="gitHeadSha" sc="quality" p="src/quality.h" cx="1" in="16" churn="684" amp="883" r="22">inline std::string gitHeadSha( const std::string&amp; root )</d>
<t p="src/quality.h" sym="atomicWriteFile" r="23"/>
… [322 more display lines; full output is 31542 bytes on 48 raw line(s)]
`````

## `./build/ripwire . --for="quality delta acks ledger rubber stamp" --no-doc-mention`

*The same task with doc-mention surfacing OFF — the contrast the flag exists for (no [doc mentions] clause, one fewer row).*

**wall time: 6.59s**

`````
<ctx task="quality delta acks ledger rubber stamp" route="subtoken+body" root="." confidence="low" margin_pct="0" at="6ace381eb" schema="ripwire.for/v1" bundle="compact" bodies="0" reason="compact-route" budget_bytes="7500" est_tokens="11733">
<!-- ripwire for schema=ripwire.for/v1: bundle=/bodies=/reason= the body posture; d: cx= ccx= complexity, in= callers (absent cx/ccx/in = 0), churn= amp= change, clone= tested= 1, sc= scope, id=p::sc::n; total= shown= capped=1 if cut; task= the query; d pure=1 const/constexpr sig, next= the follow-up to paste; route= name-exact(X)|subtoken+body[:broad|:declined]; confidence=/margin_pct= head score drop (low=flat); h l= p= n=, c n= l= p= (p= if not h's; same-named joined, shown= counts them), noedge= no callee resolved; h calls capped=1 next= the call listing every callee; fold kind=bodies: b t= n= p= l= top ranked rows' whole bodies, not the answer; served= of total= in budget_bytes=; slice/skip p= n= l=; skip bytes= next=; a skip makes sigs next= it, sigs_next= the signatures-only re-call; t p= file outside sigs (weaker), t sym= its top symbols not in sigs/syms (a pointer, not the answer), r= rank (gap = trimmed); t order: code files first, then doc files (a code question); t page rows go on to file-page row 160 (code question: 160 code rows, docs within row 160); past page 0 (code question: past 40 code rows, a doc past row 40) listed last, head files skipped; past 120 of those p= only, p_only= counts them; t folded=class=N: N p= only rows of that class (doc|config|script|testdata|other) not listed, next= pages to them; d e= its last line (absent=unknown, never 0; l= the name's line); c via=name: that callee matched by name alone, receiver unproven (NOT a claim the edge is false); c prov=split: a resolver split arm; may be another arm's (NOT a claim the edge is false) -->
<!-- root= is the crawl root; p= below is RELATIVE to it (single-root only; absent => p= is ingest's own path, unchanged); at=this commit(+dirty). [budget_bytes= is the default BYTE target this ranked payload was shaped toward: row text shortens toward it, no row of the ranked head is removed for it (sigs past_target=)] [sigs capped=1 with shown=total: rows shrunk, none dropped] [sigs past_target=K: the last K rows are past the budget_bytes target, served because they are rows of the ranked head; none is cut] [sigs sigs_next=: one call serving all total= rows uncut] [docs_dropped=N: N shown rows have a doc comment not printed (r>24 always, r5..24 if capped)] [files_first=N: N rows moved so r=1..8 are distinct files' best rows, score order, a repeated name once; same rows; fold, hops keep score order]; lego/compose collapse to a counted stub by default (a disclosed cut): total= that section's own pre-cap row count, shown="0" capped="1" (nothing rendered here), next= names the sections=lego,compose flag that restores both sections byte-identically in one call est_tokens= prices this bundle in tokens -->
<sigs shown="40" total="40" capped="1" past_target="11" docs_dropped="26" files_first="28" sigs_next="--for='quality delta acks ledger rubber stamp' --signatures-only --no-doc-mention --token-budget=6000" next="--expand=src/mcpverbs.h:4905:computeQualityDelta">
<d l="2437" e="2458" n="refPairStaleAcks" p="src/verbs_quality.h" cx="6" ccx="6" in="1" churn="198" amp="309" r="1" next="--expand=src/verbs_quality.h:refPairStaleAcks">
<doc>L2 stale acks in the range form. A changed-files answer holds no whole target tree to check the …</doc>std::vector&lt;rw::quality::StaleAck&gt; refPairStaleAcks( const gtl::btree_map&lt;std::string, rw::quality::AckRecord&gt;&amp; acks, const RefPairDelta&amp; refs )</d>
<d l="4905" e="4984" n="computeQualityDelta" sc="rw" p="src/mcpverbs.h" cx="5" ccx="5" in="1" churn="675" amp="692" r="2">inline QualityDeltaOutcome computeQualityDelta( const std::string&amp; root )</d>
<d l="10776" e="10791" n="staleByKindValue" sc="quality" p="src/quality.h" cx="5" ccx="7" in="2" churn="684" amp="869" r="3">inline std::string staleByKindValue( const std::vector&lt;StaleAck&gt;&amp; staleAcks )</d>
<d l="2529" e="2531" n="kAtStampLegend" sc="rw" p="src/serialize.h" churn="515" amp="626" pure="1" r="4">inline constexpr const char* kAtStampLegend = &quot;&lt;!-- at= is the git commit these numbers were computed at</d>
<d l="5801" e="5811" n="runForLensPosture" p="src/verbs_for.h" cx="5" ccx="3" in="3" churn="422" amp="505" r="5">std::optional&lt;int&gt; runForLensPosture( const MainDispatch&amp; d, rw::ForAnswerLedger* ledger )</d>
<d l="314" e="371" n="computeDmm" sc="rw::dmm" p="src/dmm.h" cx="9" ccx="6" in="1" churn="16" amp="77" r="6">inline Result computeDmm( const std::string&amp; root, std::string_view spec, const IngestResult&amp; wo…</d>
<d l="67" e="67" n="kNotesFile" sc="rw::notes" p="src/notes.h" churn="20" amp="81" r="7">inline const char* kNotesFile = &quot;.ripwire_notes&quot;</d>
<d l="325" e="365" n="openRegularFileStream" sc="detail" p="src/docparse.h" cx="7" ccx="8" in="2" churn="40" amp="105" tested="1" r="8">inline rw::pathguard::NoFollowRead openRegularFileStream( std::string_view what, const std::stri…</d>
<d l="1106" e="1132" n="refPairBasis" p="src/verbs_quality.h" cx="4" ccx="3" in="1" churn="198" amp="309" r="9">
<doc>The REF-PAIR floor&apos;s comparison, once loadRefPairDelta has both sides: the base snapshot is the …</doc>void refPairBasis( const rw::Config&amp; cfg, const std::string&amp; root, RefPairDelta&amp; refs, DeltaBasis&amp; out )</d>
<d l="1401" e="1436" n="refuseForeignAckSelection" p="src/verbs_quality.h" cx="9" ccx="12" in="1" churn="198" amp="309" r="10">std::optional&lt;int&gt; refuseForeignAckSelection( const rw::Config&amp; cfg, const rw::quality::Scope&amp; scope, const std::vector&lt;rw::quality::Regression&gt;&amp; out … [line truncated: 18 more bytes on this line]
<d l="2638" e="3381" n="runQualityDelta" p="src/verbs_quality.h" cx="146" ccx="323" in="2" churn="198" amp="310" r="11">std::optional&lt;int&gt; runQualityDelta( const MainDispatch&amp; d )</d>
<d l="2259" e="2284" n="ackNothingToAccept" p="src/verbs_quality.h" cx="6" ccx="7" in="1" churn="198" amp="309" r="12">int ackNothingToAccept( const std::string&amp; acksFile, const gtl::btree_map&lt;std::string, rw::quality::AckRecord&gt;&amp; acks, const rw::quality::Scope&amp; scope, std::size… … [line truncated: 4 more bytes on this line]
<!-- demote: a <t> in sigs is a lower same-file sibling past answer row 10, a pointer (p= file, sym= name, r= rank), not the answer -->
<t p="src/verbs_quality.h" sym="DeltaBasis" r="13"/>
<t p="src/quality.h" sym="kAcksFile" r="14"/>
<t p="src/verbs_quality.h" sym="inspectDirtyBaselinePin" r="15"/>
<t p="src/quality.h" sym="IdentityHealing" r="16"/>
<d l="9509" e="9522" n="writeAckRecords" sc="quality" p="src/quality.h" cx="2" ccx="1" in="2" churn="684" amp="869" r="17">inline bool writeAckRecords( const std::string&amp; path, const gtl::btree_map&lt;std::string, AckRecord&gt;&amp; acks )</d>
<d l="5004" e="5136" n="qualityDeltaJson" sc="rw" p="src/mcpverbs.h" cx="30" ccx="48" in="1" churn="675" amp="692" r="18">inline std::pair&lt;std::string, std::string&gt; qualityDeltaJson( const std::string&amp; root, bool showStale = false )</d>
<d l="4793" e="4793" n="qualityAcksPath" sc="rw" p="src/mcpverbs.h" cx="1" in="1" churn="675" amp="692" r="19">inline std::string qualityAcksPath( const std::string&amp; root )</d>
<d l="10732" e="10770" n="staleAcksXml" sc="quality" p="src/quality.h" cx="5" ccx="8" in="1" churn="684" amp="868" r="20">inline std::string staleAcksXml( const std::vector&lt;StaleAck&gt;&amp; staleAcks, EscapeFn esc )</d>
<t p="src/mcpverbs.h" sym="QualityDeltaOutcome" r="21"/>
<d l="2937" e="2940" n="gitHeadSha" sc="quality" p="src/quality.h" cx="1" in="16" churn="684" amp="883" r="22">inline std::string gitHeadSha( const std::string&amp; root )</d>
<t p="src/quality.h" sym="atomicWriteFile" r="23"/>
… [321 more display lines; full output is 31328 bytes on 48 raw line(s)]
`````

## `./build/ripwire . --safe-delete=rankGraphTeleport`

*"Can I delete this?" — callers + transitive impact + every use site + how much of the radius is tested, composed in ONE call; risk= names what was found, never a verdict.*

`````
<!-- ripwire safe-delete schema=ripwire.safe-delete/v1: can sym= go, a READ never a verdict: callers= impact_reaches= uses= tested_self= risk=; <c n= p= amb=>; radius_tested= non-tests of impact_reaches= an indexed test reaches, radius_untested= the rest; t= p= its tower-front match's kind and file:line; defs= matched; ambiguous_callers= callers with a call split over several defs; dead_code_candidate=1 only at defs=1 with no caller, for a t=fn with a body, outside .h/.hpp/.hh/.hxx, whose signature spells static (0 never means in use). window: shown= capped= (capped=1 cut). counts_floor=1: every count is a FLOOR, never a total. graph_ambiguous=/graph_unresolved=: resolver gauge. graph_unindexed=N: N files no grammar could read (the map header's unindexed=); their calls raise neither gauge. root=: p= relative to it. amb=K: K calls split over several defs. c sites_at=: its leaf-name calls not proven elsewhere, as [file:]line (p=: def line, default file); not proof each binds. -->
<safe-delete schema="ripwire.safe-delete/v1" sym="rankGraphTeleport" t="fn" p="src/graph.h:14619" defs="1" callers="7" ambiguous_callers="2" impact_reaches="80" uses="9" tested_self="0" radius_tested="0" radius_untested="80" dead_code_candidate="0" risk="untested-radius" shown="7" capped="0" graph_a … [line truncated: 89 more bytes on this line]
<c n="runEval" p="src/eval.h:171" sites_at="328" amb="4"/>
<c n="rankGraph" p="src/graph.h:14662" sites_at="14666"/>
<c n="anchoredLexicalRank" p="src/graph.h:15331" sites_at="15382"/>
<c n="churnDecayRanking" p="src/main.cpp:1432" sites_at="1446"/>
<c n="churnRankedGraph" p="src/main.cpp:1471" sites_at="1485 1486 1500"/>
<c n="runDefaultMap" p="src/main.cpp:1758" sites_at="1878" amb="15"/>
<c n="getIndex" p="src/mcpindex.h:1224" sites_at="1340"/>
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
ripwire: --safe-delete symbol not found: DoesNotExist (note: the lexical definition scan stopped at its budget, 4096 files or 16 MiB, before reading every file, so this miss is not proof the bytes define nothing; --grep=DoesNotExist lists its text uses)
`````

## `./build/ripwire . --handoff`

*The continuation packet for the NEXT session: <verified> disk truth (branch/sha, changed symbols, blast radius, tests) + <heuristic> labeled suggestions. Recorded against a CLEAN tree.*

**wall time: 9.12s**

`````
<!-- ripwire handoff schema=ripwire.handoff/v1: continuation packet for the NEXT session: <verified changed= blast_files=>, <tests n=>, <heuristic n= candidates=>, <note>, <doc p=>. window: capped= (capped=1 cut). est_tokens=: price as emitted (an upper bound under compact). at=: commit+dirty+shallow. root=: p= relative to it. branch=/subject=: the checked out branch and HEAD commit subject; gitok=0: the git diff probe failed, changed counts are floors. cochange_window=/cochange_commits=: the git window the cochange rows were mined in and the commits it held (0: could not look). doc s=: lexical score of that plan/design doc for the branch+subject query. note target=/txt=: a committed notes row on this work (symbol id or path) and its text; a suggestion. -->
<handoff schema="ripwire.handoff/v1" at="6ace381eb" root="." branch="integration/train-ge2" subject="train ge2 on f79a94e21 (#706): cachefuzzcheck reads the v54 def record; pins follow the composed build" gitok="1" est_tokens="910">
<verified changed="0" blast_files="0">
<tests n="0">
</tests>
</verified>
<heuristic n="6" candidates="338" capped="1" cochange_window="18mo@HEAD" cochange_commits="7913">
<note target="src/infra/Diagnostics.h" txt="ASSUME_NO_ALIAS is an optimizer fact in release (separate_storage) only where the compiler consumes it: clang 18+ by default, LLVM 17/AppleClang 16 via the CMake -mllvm flag (scalars only), GCC never (debug check only); never on two members of one object;  … [line truncated: 57 more bytes on this line]
<note target="test/manifestcheck.sh" txt="README.md&apos;s single &apos;&lt;N&gt; gate scripts&apos; claim (~line 1305) is NOT enforced — the derived-vs-stated sibling loop here covers docs/EVALS.md only. It drifted 407→451 unnoticed (fixed 2026-08-23). To close: grep both files (&apos;file:line … [line truncated: 47 more bytes on this line]
<doc p="CHANGELOG.md" s="9.295"/>
<doc p="bench/locbench/results/r5_nameboost/PREREG.md" s="7.912"/>
<doc p="bench/locbench/results/vt2_pooling_freestat/FREESTAT.md" s="7.860"/>
<doc p="bench/locbench/results/r1cpp_anchorhop/GATE_DECISION_r1cpp.md" s="7.812"/>
</heuristic>
</handoff>
`````

## `./build/ripwire . --handoff --token-budget=1200`

*The same packet under a hard ceiling: heuristic rows drop tail-first (withheld= disclosed), verified rows never drop.*

**wall time: 8.93s**

`````
<!-- ripwire handoff schema=ripwire.handoff/v1: continuation packet for the NEXT session: <verified changed= blast_files=>, <tests n=>, <heuristic n= candidates=>, <note>, <doc p=>. window: capped= (capped=1 cut). est_tokens=: price as emitted (an upper bound under compact). over_ceiling=1: budget not met. withheld=: rows the budget cut. at=: commit+dirty+shallow. root=: p= relative to it. branch=/subject=: the checked out branch and HEAD commit subject; gitok=0: the git diff probe failed, changed counts are floors. cochange_window=/cochange_commits=: the git window the cochange rows were mined in and the commits it held (0: could not look). note target=/txt=: a committed notes row on this work (symbol id or path) and its text; a suggestion. budget=: the token-budget cap this packet was fitted to; est_tokens= prices what it delivers. withheld_rows=N: heuristic rows the budget dropped (withheld=1 says so); verified rows are never dropped. -->
<handoff schema="ripwire.handoff/v1" at="6ace381eb" root="." branch="integration/train-ge2" subject="train ge2 on f79a94e21 (#706): cachefuzzcheck reads the v54 def record; pins follow the composed build" gitok="1" budget="1200" withheld="1" withheld_rows="4" est_tokens="900" over_ceiling="1">
<verified changed="0" blast_files="0">
<tests n="0">
</tests>
</verified>
<heuristic n="2" candidates="338" capped="1" cochange_window="18mo@HEAD" cochange_commits="7913">
<note target="src/infra/Diagnostics.h" txt="ASSUME_NO_ALIAS is an optimizer fact in release (separate_storage) only where the compiler consumes it: clang 18+ by default, LLVM 17/AppleClang 16 via the CMake -mllvm flag (scalars only), GCC never (debug check only); never on two members of one object;  … [line truncated: 57 more bytes on this line]
<note target="test/manifestcheck.sh" txt="README.md&apos;s single &apos;&lt;N&gt; gate scripts&apos; claim (~line 1305) is NOT enforced — the derived-vs-stated sibling loop here covers docs/EVALS.md only. It drifted 407→451 unnoticed (fixed 2026-08-23). To close: grep both files (&apos;file:line … [line truncated: 47 more bytes on this line]
</heuristic>
</handoff>
`````

## `./build/ripwire . --skipped`

*WHY a file is not in the index (oversize / excluded / unsupported-ext / gitignored) and which indexed files it cannot vouch for (degraded-parse, minified-suspect), plus the per-language census.*

`````
<ctx schema="ripwire.skipped/v1">
<!-- ripwire skipped schema=ripwire.skipped/v1: why the index lacks a file <f p= why= bytes= limit= ext=>; indexed but unvouched <h p= why= err= err_ratio=>; <lang> census. root=: p= relative to it. indexed=N: the map's files=; indexed= + oversize= + excluded= + ignored= = every file the crawl enumerated. oversize=N: files dropped for exceeding a size ceiling (row limit= names which). excluded=N: files dropped by an exclude substring you passed. unsupported_ext=N: source/text files no grammar reads; binary assets and excluded/ignored files not counted. excluded_dirs=N: subtrees an exclude pruned; their files are UNKNOWN, not zero, and in no count here. pruned_dirs=N: subtrees pruned by built-in policy (vendor/build, CMakeCache.txt dirs); contents UNKNOWN. ignored=/ignored_dirs=: files / subtrees git ignore rules hid (else indexed); subtree contents UNKNOWN. ignore_mode=: git (rules applied), off (no-ignore flag), unavailable/root-ignored (not consulted, full walk). degraded_parse=/minified_suspect=: counts of the h rows of each why=; those files stay indexed. unmeasured=N: indexed files never parsed (doc pass, binary sniff, nest guard, read error); not health-counted. max_file_size=B: the effective per-file size ceiling in bytes (the max-file-size flag raises it). json_ceiling=/yaml_ceiling=: fixed .json/.yaml byte ceilings the max-file-size flag does NOT raise. ws_freq=R: whitespace share of the leading 4096 bytes; under 0.070 = minified-suspect (never under 256 B). x=/files=: an unindexed extension and its file count (full list; the map's unindexed= is the top 6). files=/symbols=: per language, files with its symbols (FLOOR: symbol-less files uncounted) / symbols (exact). lang n=: a language this build extracted symbols from; files=/symbols= its counts. -->
<!-- why=extent-suspect on an <h> row = the file holds extent_suspect_syms= definitions whose extent, scope or kind FAILED a containment check (the map and bundle rows carry the reasons as extent_suspect=: name, head, scope, error); joined to the parse-health reasons comma-separated, and rowed even when the parse itself is clean. extent_suspect_files= on the root counts such rows. Nothing is dropped. -->
<!-- why=macro-blanked on an <h> row = this file's symbols come from a SECOND parse. Its first parse held error bytes, so macro_blanked= semicolon-less ALL-CAPS function-like macro invocations, each alone on its line directly inside a class/struct/union body (a shape the C-family grammars misread as a field missing its semicolon, letting one body swallow what follows it), were replaced by spaces with every offset and line unchanged, and that re-parse was adopted because it held STRICTLY FEWER error bytes; names, spans and bodies still read the original bytes. err=, err_ratio= and degraded-parse on such a row describe the ADOPTED parse: a row without degraded-parse parsed clean once blanked. A blanked invocation stays a use of the macro name for the uses verb (role=type, as the unrepaired parse recorded it) but is no call edge, and identifiers inside its parentheses are not recorded. macro_blanked_files= on the root counts such rows. Nothing is dropped. -->
<!-- why=use-bounds-blanked on an <h> row = this Rust file's symbols come from a SECOND parse. Its first parse held error bytes, so use_bounds_blanked= precise-capturing bounds (a use<..> list on an impl Trait, which this build's Rust grammar predates) were replaced by spaces with every offset and line unchanged, and that re-parse was adopted because it held STRICTLY FEWER error bytes; names, spans and bodies still read the original bytes. A use<..> list names only generic parameters and lifetimes already in scope, so no definition, call or type use is lost. err=, err_ratio= and degraded-parse on such a row describe the ADOPTED parse. use_bounds_blanked_files= on the root counts such rows. Nothing is dropped. -->
<skipped indexed="4838" oversize="15" excluded="0" unsupported_ext="313" excluded_dirs="0" pruned_dirs="7" ignored="0" ignored_dirs="0" ignore_mode="git" degraded_parse="190" minified_suspect="4" extent_suspect_files="4" macro_blanked_files="7" use_bounds_blanked_files="2" unmeasured="41" max_file_s … [line truncated: 67 more bytes on this line]
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
<f p=".clang-tidy-baseline.txt" why="unsupported-ext" bytes="143081" ext=".txt"/>
<f p=".github/pargates-load-timing.txt" why="unsupported-ext" bytes="1614" ext=".txt"/>
<f p=".github/pargates-macos-plain-skip.txt" why="unsupported-ext" bytes="986" ext=".txt"/>
<f p="CMakeLists.txt" why="unsupported-ext" bytes="112342" ext=".txt"/>
<f p="bench/agentloop/editsuite/expected/i1/stats.py.expected" why="unsupported-ext" bytes="603" ext=".expected"/>
<f p="bench/agentloop/editsuite/expected/i2/matrix.cpp.expected" why="unsupported-ext" bytes="973" ext=".expected"/>
<f p="bench/agentloop/editsuite/expected/i3/text.py.expected" why="unsupported-ext" bytes="338" ext=".expected"/>
<f p="bench/agentloop/editsuite/expected/p1/geometry.cpp.expected" why="unsupported-ext" bytes="723" ext=".expected"/>
<f p="bench/agentloop/editsuite/expected/p2/stats.py.expected" why="unsupported-ext" bytes="575" ext=".expected"/>
… [564 more display lines; full output is 59716 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --no-ignore --top-k=3`

*Crawl paths the repo's own .gitignore covers (default honours it and discloses ignored_files=/ignored_dirs= only when it dropped anything — this repo's crawl drops nothing, so the header is identical to the default map's; --skipped's ignore_mode= says which rule applied).*

**wall time: 2.03s**

`````
<!-- ripwire map schema=ripwire.map/v1: ranked symbol map: <f p= layer=> groups <s t= n= sc= k= amb=> rows (k= rank), <c n=> resolved callees; the header comment is data. est_tokens=: price as emitted (an upper bound under compact). root=: p= relative to it. pr_iters=N: PageRank iterations. <inv listed= unlisted=>: files the ranked rows show / do not (sum = files=), each named or counted below. <entry p= n=>: a program entry by its language's convention (C/Go/Rust main, Java/C# static main, a script main its module scope calls, __main__.py), callees as c rows; manifest entries not read. <ls p= n= f=>: n= unshown files under dir p=; f= names its code files, the rest (tests, docs, config, test/doc/example dirs) counted. declined=K: K call sites without edges, including inert Elixir quote sites after unquote/unquote_splicing re-entry. external=K: K calls proven outside the tree, no edge. locality_pinned=K: K calls pinned by locality alone (a guess). extent_suspect_syms=K: K defs failed containment, corpus-wide. macro_blanked_files=K: K files indexed from a macro-blanked re-parse. prov=scip|binding|import|split|final-segment: how that <c> edge bound (absent: one unique name); split = one arm of an amb= pick; final-segment = a qualified type matched by last name only. files=/symbols=: files and symbols indexed; edges= distinct call edges; shown= symbols printed, a merged row counting each def; ambiguous= calls split over several defs, corpus-wide; unresolved= calls with in-tree evidence and no edge (every def language-filtered or unreachable, or binding refused); order= rows by rank (important-first, important-last; (auto:fill) = flipped past a size threshold) or by path (stable). skipped_oversize=K: K files over a size ceiling, not indexed. unindexed=ext:N: N text files of that extension no grammar reads (6 extensions at most). unindexed_exts=E: E such extensions in all, the list cut. sc=: enclosing scope; the full id is p::sc::n (p= of the row or its <f>) and selectors take it. -->
<!-- t=modscope=a-file's-MODULE-SCOPE(n=<file-scope>):the-statements-outside-every-named-definition,where-a-top-level-call-and-an-anonymous-callback-body's-calls-live;a-CALLER-never-a-callee(nothing-in-the-source-can-name-it)-with-no-body-to-expand;a-file-with-no-such-call-has-no-such-row -->
<!-- t=type|alias|functype=a-Go-named-type-by-its-written-form:type=a-defined-type-whose-WRITTEN-form-is-not-a-struct/iface/func-literal(type-N-string;type-W-Pair-too,whatever-Pair-is-underneath),alias=type-A=B,functype=type-F-func(...) -->
<!-- t=alias|functype-in-C++-and-.h:alias=using-X=Y(also-templated-or-class-scope)or-namespace-L=lib(defs=X-prints-its-written-target-as-to=),functype=a-typedef-of-a-function-or-function-pointer-type(typedef-void(*F)(int));other-typedefs-read-t=struct -->
<!-- files=4838 symbols=44600 edges=44429 shown=3 est_tokens=4041 ambiguous=3634 unresolved=20069 locality_pinned=14 external=12457 declined=45295 extent_suspect_syms=12 macro_blanked_files=7 skipped_oversize=15 unindexed="txt:85,tsv:54,mod:33,xml:33,jsonl:26,scm:25" unindexed_exts=23 order=important-first -->
<r schema="ripwire.map/v1" root="." est_tokens="4041" pr_iters="40">
<f p="src/infra/nodekind.h" layer="infra">
<s t="fn" n="kindIs" sc="rw" k="0.0031">
</s>
</f>
<f p="src/ingest_metrics.h">
<s t="fn" n="nodeTextOf" k="0.0021">
</s>
</f>
<f p="src/infra/namesplit.h" layer="infra">
<s t="fn" n="isIdentChar" sc="namesplit" k="0.0020">
</s>
</f>
<inv listed="3" unlisted="4835">
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
… [80 more display lines; full output is 10090 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --no-stable --top-k=3`

*--no-stable outside --mcp: what the flag does (or says) when there is no stable-by-default ordering to opt out of.*

**wall time: 1.75s**

`````
<!-- ripwire map schema=ripwire.map/v1: ranked symbol map: <f p= layer=> groups <s t= n= sc= k= amb=> rows (k= rank), <c n=> resolved callees; the header comment is data. est_tokens=: price as emitted (an upper bound under compact). root=: p= relative to it. pr_iters=N: PageRank iterations. <inv listed= unlisted=>: files the ranked rows show / do not (sum = files=), each named or counted below. <entry p= n=>: a program entry by its language's convention (C/Go/Rust main, Java/C# static main, a script main its module scope calls, __main__.py), callees as c rows; manifest entries not read. <ls p= n= f=>: n= unshown files under dir p=; f= names its code files, the rest (tests, docs, config, test/doc/example dirs) counted. declined=K: K call sites without edges, including inert Elixir quote sites after unquote/unquote_splicing re-entry. external=K: K calls proven outside the tree, no edge. locality_pinned=K: K calls pinned by locality alone (a guess). extent_suspect_syms=K: K defs failed containment, corpus-wide. macro_blanked_files=K: K files indexed from a macro-blanked re-parse. prov=scip|binding|import|split|final-segment: how that <c> edge bound (absent: one unique name); split = one arm of an amb= pick; final-segment = a qualified type matched by last name only. files=/symbols=: files and symbols indexed; edges= distinct call edges; shown= symbols printed, a merged row counting each def; ambiguous= calls split over several defs, corpus-wide; unresolved= calls with in-tree evidence and no edge (every def language-filtered or unreachable, or binding refused); order= rows by rank (important-first, important-last; (auto:fill) = flipped past a size threshold) or by path (stable). skipped_oversize=K: K files over a size ceiling, not indexed. unindexed=ext:N: N text files of that extension no grammar reads (6 extensions at most). unindexed_exts=E: E such extensions in all, the list cut. sc=: enclosing scope; the full id is p::sc::n (p= of the row or its <f>) and selectors take it. -->
<!-- t=modscope=a-file's-MODULE-SCOPE(n=<file-scope>):the-statements-outside-every-named-definition,where-a-top-level-call-and-an-anonymous-callback-body's-calls-live;a-CALLER-never-a-callee(nothing-in-the-source-can-name-it)-with-no-body-to-expand;a-file-with-no-such-call-has-no-such-row -->
<!-- t=type|alias|functype=a-Go-named-type-by-its-written-form:type=a-defined-type-whose-WRITTEN-form-is-not-a-struct/iface/func-literal(type-N-string;type-W-Pair-too,whatever-Pair-is-underneath),alias=type-A=B,functype=type-F-func(...) -->
<!-- t=alias|functype-in-C++-and-.h:alias=using-X=Y(also-templated-or-class-scope)or-namespace-L=lib(defs=X-prints-its-written-target-as-to=),functype=a-typedef-of-a-function-or-function-pointer-type(typedef-void(*F)(int));other-typedefs-read-t=struct -->
<!-- files=4838 symbols=44600 edges=44429 shown=3 est_tokens=4041 ambiguous=3634 unresolved=20069 locality_pinned=14 external=12457 declined=45295 extent_suspect_syms=12 macro_blanked_files=7 skipped_oversize=15 unindexed="txt:85,tsv:54,mod:33,xml:33,jsonl:26,scm:25" unindexed_exts=23 order=important-first -->
<r schema="ripwire.map/v1" root="." est_tokens="4041" pr_iters="40">
<f p="src/infra/nodekind.h" layer="infra">
<s t="fn" n="kindIs" sc="rw" k="0.0031">
</s>
</f>
<f p="src/ingest_metrics.h">
<s t="fn" n="nodeTextOf" k="0.0021">
</s>
</f>
<f p="src/infra/namesplit.h" layer="infra">
<s t="fn" n="isIdentChar" sc="namesplit" k="0.0020">
</s>
</f>
<inv listed="3" unlisted="4835">
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
… [80 more display lines; full output is 10090 bytes on 1 raw line(s)]
`````

stderr:

`````
ripwire: --no-stable is read only by --mcp/--listen (it opts out of the stable ordering the server turns on) — it changed nothing here; the CLI map orders important-first unless you pass --order=stable
`````

## `./build/ripwire . --run-trace="cat <scratch>/aux/asan_trace_now.txt; exit 1"`

*EXEC-MODE --from-trace: run a command, and on a non-zero exit map its captured output onto indexed symbols in the same call — the whole fix-loop entry. ripwire exits 4 here because the wrapped command failed, which is the signal, not an incident.*

**exit code: 4** — **wall time: 1.57s**

`````
<ctx schema="ripwire.from-trace/v1" task="run-trace: cat <scratch>/aux/asan_trace_now.txt; exit 1" next="--slice=@src/graph.h:14621" est_tokens="2727">
<!-- ripwire from-trace schema=ripwire.from-trace/v1: trace frames mapped to indexed symbols, innermost first; the innermost in-corpus body included. window: shown= total= capped= (capped=1 cut). est_tokens=: price as emitted (an upper bound under compact). <d r=N>: rank N in this ranking, rows in r= order. <d cx= ccx=>: cyclomatic/cognitive complexity. <d in=N>: N callers in the index (absent: not measured). sc=: enclosing scope; the full id is p::sc::n (p= of the row or its <f>) and selectors take it. next=: the one pasteable follow-up. task=: the trace source this bundle maps, verbatim (a file path, stdin, or an MCP label). src=/format=: the trace read and its dominant frame format, python|asan|node|compiler|generic. frame_lines=/parsed=: frame-shaped input lines / those yielding a path:line; the rest matched no format. in_corpus=: parsed frames in indexed files; always suspects= + merged= + unresolved=. suspects=/merged=/unresolved=: frame rows / folded into a claimed symbol / unresolved rows (indexed file, no def). skipped=N: frames outside every root, listed as skipped rows, never ranked. rank=N: frame order, innermost in-corpus first; p= is the trace's own path:line, defs are sigs l=. resolved_by=name|line: bound by the frame's own name, else by the def enclosing its line. innermost=1: the innermost in-corpus frame (rank 1); its full body is served. run exit=: the command's OWN exit code; signal=: the signal that killed it; timed_out=1: the timeout_s= cap did. run duration_ms=: wall clock, MEASURED, not deterministic; timeout_s=: the cap it ran under. run lines=: non-empty captured lines; bytes=: the whole capture; dropped_bytes=: middle bytes the cap dropped. lines view=tail: the last shown= of total= output lines; view=relevant: shown= of relevant= error/frame-shaped ones. lines relevant=N: captured lines that are error-marked or frame-shaped; the relevant view picks from these. frame n= t=: the bound symbol's name and kind (fn|cls|...); d, b and c n=: a ranked row's, a body's, a callee's name. -->
<!-- ledger: budget=7500 bytes (allowance 9583 bytes = ceiling + the single-entry overshoot a whole first signature costs) -->
<run exit="1" duration_ms="1205" timeout_s="600" lines="9" bytes="606"/>
<lines view="relevant" shown="7" relevant="7" total="9">
<![CDATA[AddressSanitizer:DEADLYSIGNAL
==41337==ERROR: AddressSanitizer: SEGV on unknown address 0x000000000018 (pc 0x000102f4a1c8 bp 0x00016d2f1a40 sp 0x00016d2f19e0 T0)
    #0 0x102f4a1c8 in rw::rankGraphTeleport(Graph const&, std::vector<float> const&, float) src/graph.h:14621
    #1 0x102f3e884 in rw::rankGraph(Graph const&, float) src/graph.h:14664
    #2 0x102e11f30 in runDefaultMap(MainDispatch const&) src/main.cpp:1760
    #3 0x102e01a44 in main src/main.cpp:4511
    #4 0x1a2b3c0dc in start+0x9dc (dyld:arm64e+0x60dc)]]></lines><trace src="run-trace: cat <tmp>; exit 1" format="asan" frame_lines="5" parsed="4" in_cor … [line truncated: 1696 more bytes on this line]
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
}]]><calls total="4"><c n="biasPrior" l="14578">inline std::vector&lt;float&gt; biasPrior( const Graph&amp; g, const std::vector&lt;float&gt;&amp; p )</c><c n="PROFILE_SCOPE_DESCRIBE" l="1282" p="src/infra/profileScope.h">#define PROFILE_SCOPE_DESCRIBE( desc )</c><c n="PROFILE_SCOPE_DESCRIBE" l="129 … [line truncated: 368 more bytes on this line]
`````

## `./build/ripwire . --run-trace="true"`

*A command that exits 0: a minimal success record (exit, measured duration, disclosed output tail) and NO bundle — nothing failed, nothing to map.*

`````
<ctx schema="ripwire.from-trace/v1" task="run-trace: true">
<!-- ripwire from-trace schema=ripwire.from-trace/v1: trace frames mapped to indexed symbols, innermost first; the innermost in-corpus body included. task=: the trace source this bundle maps, verbatim (a file path, stdin, or an MCP label). run exit=: the command's OWN exit code; signal=: the signal that killed it; timed_out=1: the timeout_s= cap did. run duration_ms=: wall clock, MEASURED, not deterministic; timeout_s=: the cap it ran under. run lines=: non-empty captured lines; bytes=: the whole capture; dropped_bytes=: middle bytes the cap dropped. -->
<run exit="0" duration_ms="344" timeout_s="600" lines="0" bytes="0"/>
</ctx>
`````

## `./build/ripwire . --run-trace="sleep 30" --run-timeout=2`

*A command still running at the cap: its process group is killed and the run reports timed_out=1 — an honest timeout, never an empty success.*

**exit code: 4** — **wall time: 3.07s**

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

**wall time: 8.00s**

`````
<!-- ripwire quality-panel schema=ripwire.quality-panel/v1: every quality family in ONE report, ranked by distinct families fired: <s p= n= fam= of= fired= join=>; bar_*= thresholds. window: shown= total= capped= has_more= next_offset= offset= limit= (capped=1 cut; next_offset= pastes as offset=). at=: commit+dirty+shallow. root=: p= relative to it. preset=: strict (5 stable families, cut 2), default (6, cut 2), lenient (6, cut 1); selects, never weights. families=6: evidence families: structural lexical confusion historical colocation state. enabled=/enabled_n=: the families this preset COUNTS, and how many. cut=N: distinct enabled families that must fire for a row to rank. cut_reachable=0: cut= exceeds the evaluable families (of=); a corpus fact, never a clean bill of health. eligible=N: functions/methods with a body; ranked= + below_cut= + no_family= = eligible=, always. ranked=N: rows that met the cut (total=); only shown= print, page with offset=. below_cut=N: fired at least one enabled family, but fewer than cut=. no_family=N: no enabled family fired; unavailable= families were never measured. bar_ccx=/bar_loc=/bar_nest=/bar_params=: absolute bars: cognitive complexity, lines, nesting, params. rcut=/rmeasured=: readability decile width (rrank= under it fires) / functions measured. hcut=/hranked=: file churn decile width / files with an in-window commit (hranked=0 voids historical). window=: the git churn window hrank= and churn= are counted over (RELATIVE to this corpus). ccut=/cranked=: colocation decile width / functions reading any outside definition (0 voids it). cfiles=/cscope=: files the confusion atom rules read / eligible symbols in them. lscope=N: symbols the lexical naming rules read. sfiles=/sscope=: files the state lens reads / symbols in them. cells=N: non-local mutable cells the state lens found. tested_scope=N: symbols an indexed test reaches; at 0 no row can carry join=deep+untested. deep_untested=N: rows carrying join=deep+untested across the WHOLE set, not just this page. e f=: the fired family this evidence row belongs to. counted=1: this preset counts the family toward fam=; 0 = fired, not counted. why=: the measurements that crossed (rule*N fired N times; hrank=/churn= are the file's, inherited). -->
<quality_panel schema="ripwire.quality-panel/v1" preset="default" families="6" enabled="structural,lexical,confusion,historical,colocation,state" enabled_n="6" cut="2" cut_reachable="1" eligible="24997" ranked="1409" below_cut="8248" no_family="15340" bar_ccx="15" bar_loc="60" bar_nest="4" bar_param … [line truncated: 335 more bytes on this line]
<s p="src/gitmine.h:1797" n="addRootFilesToGitPathIndex" fam="4" of="6" fired="structural,lexical,confusion,historical">
<e f="structural" counted="1" why="ccx=25 ev=6"/>
<e f="lexical" counted="1" why="naming-wordy"/>
<e f="confusion" counted="1" why="atom-embedded-crement*2"/>
<e f="historical" counted="1" why="hrank=35 churn=106"/>
</s>
<s p="src/graph.h:10549" n="buildGraph" fam="4" of="6" fired="structural,confusion,historical,colocation">
<e f="structural" counted="1" why="ccx=1979 loc=4021 nest=8 humps=99 deep=667 ev=252 rrank=0"/>
<e f="confusion" counted="1" why="atom-embedded-crement*6 atom-nested-ternary*2"/>
<e f="historical" counted="1" why="hrank=5 churn=713"/>
<e f="colocation" counted="1" why="crank=18"/>
</s>
<s p="src/graphlegend.h:837" n="declinedSitesLegend" fam="4" of="6" fired="structural,lexical,confusion,historical">
<e f="structural" counted="1" why="ccx=24 ev=2"/>
<e f="lexical" counted="1" why="naming-confusable"/>
<e f="confusion" counted="1" why="atom-nested-ternary*4"/>
<e f="historical" counted="1" why="hrank=19 churn=241"/>
</s>
<s p="src/ingest.cpp:415" n="ingest" fam="4" of="6" fired="structural,historical,colocation,state">
<e f="structural" counted="1" why="ccx=41 loc=298 params=8 ev=3"/>
<e f="historical" counted="1" why="hrank=20 churn=229"/>
<e f="colocation" counted="1" why="crank=23"/>
<e f="state" counted="1" why="reads=1"/>
</s>
<s p="src/ingest_relations.h:320" n="lookupInScope" fam="4" of="6" fired="structural,confusion,historical,state">
<e f="structural" counted="1" why="params=5 ev=6"/>
<e f="confusion" counted="1" why="atom-embedded-crement"/>
<e f="historical" counted="1" why="hrank=37 churn=95"/>
… [190 more display lines; full output is 15658 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --biggest-first --limit=8`

*Per-function size ranking, largest Halstead volume/token entropy/lines first — a size proxy, not a readability order (withdrawn, docs/EVALS.md §8) — a RANKING lens, not a grade.*

`````
<!-- ripwire readability schema=ripwire.readability/v1: Posnett/Hindle/Devanbu lens, largest Halstead volume first (a size proxy): <fn p= n= lines= toks= ops= vocab= vol= ent= posnett=>. window: shown= total= capped= has_more= next_offset= offset= limit= (capped=1 cut; next_offset= pastes as offset=). root=: p= relative to it. functions=N: functions and methods measured (bodyless declarations are not). -->
<readability schema="ripwire.readability/v1" functions="24997" shown="8" capped="1" total="24997" has_more="1" next_offset="8" offset="0" limit="8" root=".">
<fn p="src/graph.h:10549" n="buildGraph" lines="4021" toks="24918" ops="15940" vocab="1315" vol="258171.6" ent="6.82" posnett="0.000"/>
<fn p="src/verbs_for.h:3606" n="runForLensPass" lines="1984" toks="12389" ops="7572" vocab="925" vol="122072.7" ent="6.60" posnett="0.000"/>
<fn p="src/mcp.h:1151" n="dispatchMcpLine" lines="1852" toks="9460" ops="6010" vocab="832" vol="91766.2" ent="6.57" posnett="0.000"/>
<fn p="src/main.cpp:4653" n="dispatchMainBody" lines="1610" toks="8076" ops="5175" vocab="751" vol="77147.4" ent="6.43" posnett="0.000"/>
<fn p="test/forbodyslotfix/src/c/render.c:7" n="render_screen" lines="176" toks="9485" ops="6322" vocab="181" vol="71136.0" ent="4.54" posnett="0.000"/>
<fn p="src/main.cpp:1758" n="runDefaultMap" lines="1187" toks="6552" ops="4029" vocab="528" vol="59258.9" ent="6.46" posnett="0.000"/>
<fn p="src/lexical.h:538" n="lexicalScoresTiered" lines="1045" toks="6320" ops="4015" vocab="389" vol="54374.9" ent="6.36" posnett="0.000"/>
<fn p="src/packtask.h:1448" n="packTaskBundleText" lines="841" toks="5926" ops="3619" vocab="534" vol="53693.7" ent="6.57" posnett="0.000"/>
</readability>
`````

## `./build/ripwire . --comment-coherence --limit=8`

*Functions WITH a doc comment, most name-restating first: c_coeff (high = the comment repeats the name) and cic (Jaccard of comment vs identifier vocabulary), both reported, never collapsed.*

`````
<!-- ripwire comment-coherence schema=ripwire.comment-coherence/v1: two comment/name content measures per documented function, most name-restating first: <fn p= n= c_coeff= cic=>. window: shown= total= capped= has_more= next_offset= offset= limit= (capped=1 cut; next_offset= pastes as offset=). root=: p= relative to it. documented=N: functions with a doc comment, measured (the rows); a FLOOR when unreadable_files= shows. no_comment=N: eligible symbols with no measurable comment; UNAVAILABLE, never scored as zero. words=/restate=: comment word count (c_coeff= denominator, stopwords kept) / words matching a name word. c_terms=/i_terms=/shared=: comment term set / identifiers the body uses / overlap; cic= shared over union. -->
<comment_coherence schema="ripwire.comment-coherence/v1" documented="7612" no_comment="17385" shown="8" capped="1" total="7612" has_more="1" next_offset="8" offset="0" limit="8" root=".">
<fn p="src/infra/os.h:637" n="socket" c_coeff="1.000" words="1" restate="1" cic="0.000" c_terms="1" i_terms="5" shared="0"/>
<fn p="src/lsp.h:540" n="lspLocationJson" c_coeff="1.000" words="1" restate="1" cic="0.000" c_terms="1" i_terms="26" shared="0"/>
<fn p="src/query.h:262" n="sourceAll" c_coeff="1.000" words="1" restate="1" cic="0.000" c_terms="1" i_terms="12" shared="0"/>
<fn p="src/warmsnap.h:791" n="recordTree" c_coeff="1.000" words="2" restate="2" cic="0.023" c_terms="2" i_terms="88" shared="2"/>
<fn p="src/warmsnap.h:847" n="replayTree" c_coeff="1.000" words="2" restate="2" cic="0.028" c_terms="2" i_terms="71" shared="2"/>
<fn p="src/verbs_quality.h:3418" n="runDmm" c_coeff="1.000" words="1" restate="1" cic="0.029" c_terms="1" i_terms="35" shared="1"/>
<fn p="src/infra/dynamic_map.hpp:1955" n="erase_rec" c_coeff="1.000" words="1" restate="1" cic="0.048" c_terms="1" i_terms="21" shared="1"/>
<fn p="test/verify_os_win32_logic.cpp:249" n="WidePath: separators, the Git Bash drive spelling, and nothing else rewritten" c_coeff="1.000" words="2" restate="2" cic="0.133" c_terms="2" i_terms="15" shared="2"/>
</comment_coherence>
`````

## `./build/ripwire . --context-ratio --limit=8`

*The local-reasoning lens: to understand this symbol, how much must you know that is NOT in front of you (ent_ratio= edge share, read_ratio= token-weighted).*

`````
<!-- ripwire context-ratio schema=ripwire.context-ratio/v1: LOCAL-REASONING lens: the share of a unit's context outside its file: <s p= n= sites= ents_out= ent_ratio= read_ratio=>. window: total= has_more= next_offset= offset= limit= (capped=1 cut; next_offset= pastes as offset=). syms_capped=/files_capped=/defs_capped=: 1 = cut. counts_floor=1: every count is a FLOOR, never a total. root=: p= relative to it. units=N: symbols measured (the s row population). file_units=N: files measured (the f row population). defs_per_name_cap=N: most defs one name adds (lowest ids); defs_capped=1 = cut, ents=/rtok= floors. body_bytes_per_token=: the bytes-per-token rate rtok= is estimated at. shown_syms=N: symbol rows printed; the rest page with offset=next_offset. shown_files=N: file rows printed (fixed cap 40, not paged); files_capped=1 = rows dropped. ents=N: distinct in-corpus defs its reference sites resolve to, by name (a FLOOR). files=N: distinct files holding those defs (a FLOOR). files_out=N: of files=, those other than the unit's own file. rtok=N: est. tokens of every resolved def, what a reader must read. rtok_out=N: the part of rtok= defined outside the unit's own file. ext=N: referenced names with no in-corpus def; mostly locals/params, NOT external deps; in neither ratio. amb_names=N: referenced names with 2+ defs, each counted (per name; not the map's per-call amb=). ents=N: distinct in-corpus defs the file's sites resolve to (a FLOOR; a union, not the sum of s rows). files=N: distinct files holding those defs (a FLOOR). files_out=N: of files=, those other than this file. rtok=N: est. tokens of every resolved def, what a reader must read. rtok_out=N: the part of rtok= defined outside this file. ext=N: referenced names with no in-corpus def; mostly locals/params, NOT external deps; in neither ratio. amb_names=N: referenced names with 2+ defs, each counted (per name; not the map's per-call amb=). s t=: the unit's kind (fn|cls|...). -->
<contextratio schema="ripwire.context-ratio/v1" units="37152" file_units="4105" defs_per_name_cap="8" body_bytes_per_token="3.80" shown_syms="8" syms_capped="1" shown_files="40" files_capped="1" total="37152" has_more="1" next_offset="8" offset="0" limit="8" defs_capped="1" counts_floor="1" root="." … [line truncated: 1 more bytes on this line]
<s p="src/main.cpp:4653" n="dispatchMainBody" t="fn" sites="1195" ents="272" ents_out="246" ent_ratio="0.904" files="82" files_out="81" rtok="272471" rtok_out="236201" read_ratio="0.867" ext="133" amb_names="33"/>
<s p="src/mcpverbs.h:4905" n="computeQualityDelta" t="fn" sites="78" ents="47" ents_out="43" ent_ratio="0.915" files="20" files_out="19" rtok="97838" rtok_out="96967" read_ratio="0.991" ext="10" amb_names="8"/>
<s p="src/mcp.h:1151" n="dispatchMcpLine" t="fn" sites="1368" ents="248" ents_out="222" ent_ratio="0.895" files="52" files_out="51" rtok="93870" rtok_out="88764" read_ratio="0.946" ext="167" amb_names="22"/>
<s p="src/mcpverbs.h:5432" n="editCheckText" t="fn" sites="37" ents="44" ents_out="44" ent_ratio="1.000" files="28" files_out="28" rtok="86156" rtok_out="86156" read_ratio="1.000" ext="4" amb_names="8"/>
<s p="src/main.cpp:1758" n="runDefaultMap" t="fn" sites="1101" ents="155" ents_out="143" ent_ratio="0.923" files="47" files_out="46" rtok="89698" rtok_out="84999" read_ratio="0.948" ext="148" amb_names="18"/>
<s p="src/editpreview.h:342" n="run" t="fn" sites="127" ents="67" ents_out="63" ent_ratio="0.940" files="31" files_out="30" rtok="82280" rtok_out="79957" read_ratio="0.972" ext="31" amb_names="9"/>
<s p="src/mcpindex.h:1224" n="getIndex" t="fn" sites="174" ents="89" ents_out="70" ent_ratio="0.787" files="24" files_out="23" rtok="82015" rtok_out="78257" read_ratio="0.954" ext="20" amb_names="12"/>
<s p="src/mcpverbs.h:5142" n="qualityBaselineJson" t="fn" sites="32" ents="46" ents_out="45" ent_ratio="0.978" files="28" files_out="27" rtok="76552" rtok_out="76523" read_ratio="1.000" ext="4" amb_names="10"/>
<f p="src/main.cpp" sites="4293" ents="630" ents_out="534" ent_ratio="0.848" files="135" files_out="134" rtok="483035" rtok_out="404403" read_ratio="0.837" ext="583" amb_names="66"/>
<f p="src/mcpverbs.h" sites="5742" ents="830" ents_out="742" ent_ratio="0.894" files="149" files_out="148" rtok="430585" rtok_out="358268" read_ratio="0.832" ext="714" amb_names="60"/>
<f p="src/graph.h" sites="15069" ents="1366" ents_out="744" ent_ratio="0.545" files="171" files_out="170" rtok="327785" rtok_out="194551" read_ratio="0.594" ext="1320" amb_names="153"/>
<f p="src/verbs_for.h" sites="5275" ents="675" ents_out="529" ent_ratio="0.784" files="156" files_out="155" rtok="271480" rtok_out="184375" read_ratio="0.679" ext="579" amb_names="58"/>
<f p="src/quality.h" sites="7090" ents="873" ents_out="494" ent_ratio="0.566" files="145" files_out="144" rtok="212218" rtok_out="136352" read_ratio="0.643" ext="785" amb_names="98"/>
<f p="src/verbs_navigate.h" sites="4392" ents="574" ents_out="520" ent_ratio="0.906" files="108" files_out="107" rtok="159043" rtok_out="134916" read_ratio="0.848" ext="429" amb_names="45"/>
<f p="src/mcpindex.h" sites="747" ents="259" ents_out="219" ent_ratio="0.846" files="68" files_out="67" rtok="116889" rtok_out="109583" read_ratio="0.937" ext="125" amb_names="41"/>
<f p="src/mcp.h" sites="1930" ents="326" ents_out="269" ent_ratio="0.825" files="65" files_out="64" rtok="145388" rtok_out="94206" read_ratio="0.648" ext="240" amb_names="29"/>
<f p="src/legenddict.h" sites="1026" ents="248" ents_out="187" ent_ratio="0.754" files="60" files_out="59" rtok="98579" rtok_out="90176" read_ratio="0.915" ext="88" amb_names="28"/>
<f p="src/editpreview.h" sites="446" ents="136" ents_out="130" ent_ratio="0.956" files="45" files_out="44" rtok="90734" rtok_out="88283" read_ratio="0.973" ext="71" amb_names="21"/>
<f p="src/verbs_quality.h" sites="3290" ents="549" ents_out="419" ent_ratio="0.763" files="108" files_out="107" rtok="139553" rtok_out="86967" read_ratio="0.623" ext="316" amb_names="55"/>
<f p="src/verbs_change.h" sites="1317" ents="274" ents_out="247" ent_ratio="0.901" files="77" files_out="76" rtok="89988" rtok_out="84405" read_ratio="0.938" ext="130" amb_names="32"/>
<f p="src/warmsnap_graph.h" sites="451" ents="192" ents_out="185" ent_ratio="0.964" files="53" files_out="52" rtok="83971" rtok_out="81979" read_ratio="0.976" ext="32" amb_names="34"/>
<f p="test/verify_csr.cpp" sites="184" ents="63" ents_out="60" ent_ratio="0.952" files="30" files_out="29" rtok="75043" rtok_out="74298" read_ratio="0.990" ext="30" amb_names="16"/>
<f p="src/forpage.h" sites="1244" ents="272" ents_out="217" ent_ratio="0.798" files="86" files_out="85" rtok="77043" rtok_out="68942" read_ratio="0.895" ext="183" amb_names="31"/>
<f p="src/ingest_sidecap.h" sites="1958" ents="385" ents_out="318" ent_ratio="0.826" files="88" files_out="87" rtok="74846" rtok_out="61255" read_ratio="0.818" ext="251" amb_names="43"/>
<f p="src/verbs_report.h" sites="3992" ents="341" ents_out="290" ent_ratio="0.850" files="80" files_out="79" rtok="80799" rtok_out="56712" read_ratio="0.702" ext="431" amb_names="31"/>
<f p="src/mcpserver.h" sites="459" ents="130" ents_out="114" ent_ratio="0.877" files="40" files_out="39" rtok="54688" rtok_out="51963" read_ratio="0.950" ext="64" amb_names="22"/>
<f p="src/backhops.h" sites="1291" ents="368" ents_out="274" ent_ratio="0.745" files="88" files_out="87" rtok="67735" rtok_out="50143" read_ratio="0.740" ext="151" amb_names="63"/>
<f p="src/packtask.h" sites="1524" ents="243" ents_out="191" ent_ratio="0.786" files="56" files_out="55" rtok="62434" rtok_out="49866" read_ratio="0.799" ext="218" amb_names="28"/>
… [21 more display lines; full output is 11236 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --nonlocal-state --limit=8`

*Per function, the non-local MUTABLE state it can reach (transitively), most writes first — unsound by construction, and the legend says where.*

**wall time: 2.68s**

`````
<!-- ripwire nonlocal-state schema=ripwire.nonlocal-state/v1: per function, the non-local MUTABLE state it reaches: <fn p= n= writes= reads=> over <cell n= p= dir= via=> rows. window: shown= total= capped= has_more= next_offset= offset= limit= (capped=1 cut; next_offset= pastes as offset=). cells_capped=: 1 = cut. counts_floor=1: every count is a FLOOR, never a total. graph_ambiguous=/graph_unresolved=: resolver gauge. graph_unindexed=N: N files no grammar could read (the map header's unindexed=); their calls raise neither gauge. root=: p= relative to it. cells=N: mutable non-local cells found in the corpus (globals, statics, Python module globals; FLOOR). functions=N: functions reaching at least one cell, directly or via callees (all rows, before paging). direct_writes=/direct_reads=: the writes=/reads= cells this function's OWN body writes/reads. cells_total=N: distinct cells reached (read and written counts once); at most 12 cell rows print. at=/at_dir=: one own-body use site (may be more) and what own-body sites do (can be narrower than dir=). shown_cells=N: cell rows printed of cells_total= (cap 12); cells_capped=1 on the row is the cut. unanalyzed_langs=/unanalyzed_files=: indexed languages (and their files) this lens skips; NOT zero cells. -->
<nonlocal_state schema="ripwire.nonlocal-state/v1" cells="1163" functions="1445" shown="8" capped="1" total="1445" has_more="1" next_offset="8" offset="0" limit="8" graph_ambiguous="3634" graph_unresolved="20069" graph_unindexed="313" counts_floor="1" unanalyzed_langs="c,go,rust,javascript,typescrip … [line truncated: 108 more bytes on this line]
<fn p="bench/bench_svector_wave.cpp:346" n="main" writes="8" reads="14" direct_writes="0" direct_reads="4" cells_total="14" shown_cells="12" cells_capped="1">
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
<fn p="bench/bench_svector_wave.cpp:295" n="sweep" writes="6" reads="13" direct_writes="4" direct_reads="1" cells_total="13" shown_cells="12" cells_capped="1">
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
… [53 more display lines; full output is 8279 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --ensemble --limit=8`

*The family join: per function, which of four orthogonal evidence families fire, ranked by how many agree.*

**wall time: 6.44s**

`````
<!-- ripwire ensemble schema=ripwire.ensemble/v1: four orthogonal evidence families joined, ranked by DISTINCT families fired (no composite score): <s p= n= fam= of= fired=>. window: total= has_more= next_offset= offset= limit= (capped=1 cut; next_offset= pastes as offset=). syms_capped=/files_capped=: 1 = cut. at=: commit+dirty+shallow. root=: p= relative to it. eligible=N: functions and methods with a body, the denominator; ranked + no_family = eligible. no_family=N: eligible symbols where no family fired. bar_ccx=/bar_loc=/bar_nest=/bar_params=: absolute structural bars: cognitive cx, lines, nesting, params. rcut=N: ranks the worst readability decile covers (1 to 40); rrank= inside it fires structural. rmeasured=N: functions the readability lens measured. hcut=N: file ranks the worst churn decile covers (1 to 40); hrank= inside it fires historical. hranked=N: files with any in-window commit; 0 = historical family unavailable. cfiles=N: indexed files the confusion (atom) pack can read: C/C++/ObjC/CUDA. cscope=N: eligible symbols in those files; 0 = confusion family unavailable. lscope=N: eligible symbols in a language the naming pack reads; 0 = lexical family unavailable. shown_syms=N: symbol rows printed; the rest page with offset=next_offset. shown_files=N: file rows printed (fixed cap 20, not paged); files_capped=1 = rows dropped. e f=: the fired family: structural, lexical, confusion or historical. why=: the measurements that crossed, space separated; rule*N = that rule fired N times. top=: the file's most corroborated symbol (most families on one symbol). top_l=: that symbol's line. top_fam=N: families fired on top=, the stronger claim; file rows rank by it. union_fam=N: distinct families firing anywhere in the file (weaker: may be different symbols). union=: the names of those families. syms=N: symbols in the file where at least one family fired. families=N: evidence families joined; ranked=N: symbols at least one fired on; window=: the git span the historical family read. -->
<ensemble schema="ripwire.ensemble/v1" families="4" eligible="24997" ranked="9230" no_family="15767" bar_ccx="15" bar_loc="60" bar_nest="4" bar_params="5" rcut="40" rmeasured="24997" hcut="40" hranked="4838" window="12mo" cfiles="1127" cscope="13846" lscope="24997" shown_syms="8" syms_capped="1" sho … [line truncated: 118 more bytes on this line]
<s p="src/gitmine.h:1797" n="addRootFilesToGitPathIndex" fam="4" of="4" fired="structural,lexical,confusion,historical">
<e f="structural" why="ccx=25 ev=6"/>
<e f="lexical" why="naming-wordy"/>
<e f="confusion" why="atom-embedded-crement*2"/>
<e f="historical" why="hrank=35 churn=106"/>
</s>
<s p="src/graphlegend.h:837" n="declinedSitesLegend" fam="4" of="4" fired="structural,lexical,confusion,historical">
<e f="structural" why="ccx=24 ev=2"/>
<e f="lexical" why="naming-confusable"/>
<e f="confusion" why="atom-nested-ternary*4"/>
<e f="historical" why="hrank=19 churn=241"/>
</s>
<s p="src/serialize.h:10619" n="packDeps" fam="4" of="4" fired="structural,lexical,confusion,historical">
<e f="structural" why="ccx=125 loc=360 nest=5 params=16 humps=4 deep=14 ev=5 rrank=21"/>
<e f="lexical" why="naming-confusable"/>
<e f="confusion" why="atom-nested-ternary"/>
<e f="historical" why="hrank=11 churn=515"/>
</s>
<s p="src/compactlegend.h:2063" n="payloadSubCapAttrs" fam="3" of="4" fired="structural,confusion,historical">
<e f="structural" why="ccx=45 nest=6 humps=2 deep=11"/>
<e f="confusion" why="atom-assign-as-value"/>
<e f="historical" why="hrank=10 churn=541"/>
</s>
<s p="src/compactlegend.h:2662" n="applyCompactDialectOnce" fam="3" of="4" fired="structural,confusion,historical">
<e f="structural" why="ccx=49 loc=120 nest=4 humps=1 deep=1 ev=3"/>
<e f="confusion" why="atom-nested-ternary"/>
<e f="historical" why="hrank=10 churn=541"/>
</s>
… [36 more display lines; full output is 7516 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --field-affinity`

*The cache-locality lens over every aggregate: fields READ TOGETHER but declared FAR APART (split-line / straddle findings, Chilimbi separation weight) — advice only, never a rewrite.*

**wall time: 1.87s**

`````
<!-- ripwire field-affinity schema=ripwire.field-affinity/v1: fields read together but declared far apart vs 64-byte lines: <s n= p=> structs, <pair a= b= fns= dist=>, <finding k= f= g=>. window: shown= capped= (capped=1 cut). counts_floor=1: every count is a FLOOR, never a total. root=: p= relative to it. block=64: ASSUMED cache-line bytes; all geometry (dist= wt= ln= lines= findings) is against it. model=lp64-approx: sizes/offsets are the layout verb's LP64 standard-layout MODEL, not the real ABI. weighting=fanin-floor: w= sums 1 + fan-in per co-accessing fn; a reachability proxy, not a frequency. aggregates=N: C-family structs/classes the layout model located a body for (the scanned universe). files=N: C-family files declaring at least one struct/class the modelling pass visited. fns_scanned=N: C-family functions/methods with a readable body scanned for dot/arrow member accesses. accesses=N: member-access sites tied to one aggregate field (FLOOR: bare in-method names uncounted). amb_skipped=N: access sites REFUSED, not guessed: 2+ aggregates declare that field name; in no count here. structs=N: aggregates with 1+ attributed access; the top 20 by sepcost= print (shown=/capped=). findings=N: split-line + straddle findings over ALL structs=, not just the printed rows. min_fns=2: a pair fires split-line only when co-accessed by this many distinct functions. as_loops=N: for-loops the static advance-shape pass classified corpus-wide; report-only, never ranks. as_index=/as_chase=/as_mixed=/as_unknown=: as_loops= by advance shape (chase = pointer chase). agg=: the aggregate keyword (struct, class ...). modeled=1: layout model placed the fields; 0 = affinity only, no geometry, no finding (why= says why). fields=N: fields declared (before the touched-only filter). touched=N: fields with 1+ attributed access; at most 32 f rows print. pairs=N: co-accessed field pairs in all; at most 12 pair rows print (most fns= first). sepcost=: sum over measured pairs of fns x (1 - wt); the struct ranking key. findings=N: this struct's findings, every one printed. size=/align=/lines=: modeled sizeof, alignment, cache lines spanned (modeled=1 only). acc=N: member-access sites attributed to this field (FLOOR). sz=B: the field's modeled size in bytes (absent when the model could not size it). off=/ln=: modeled byte offset and its cache line (off/64); placed=0 instead when the model refused. w=: sum of 1 + fan-in over the co-accessing functions; a static reachability proxy, never a frequency. wt=: separation weight (64 - dist)/64, 0.00 = the two can never share a line; measured=0 instead when unplaced. wt=0.00: split-line fires only when the pair can never share a 64-byte line. w=: the split-line pair's 1 + fan-in weight sum (proxy); straddle rows carry none. off=/sz=/crosses=: straddle field offset, size, and the line its last byte lands on (lines start at off/64). fanin=N: this function's caller count (the w= proxy input). touched=N: distinct fields of this struct the function touches (named in f=); at most 8 fn rows of fns= print. scope=: the function's PROFILE_SCOPE description (first 120 chars), a counter to confirm with. scopes=N: distinct PROFILE_SCOPEs among the co-accessing functions (the scope children). status=: instrumented (a scope exists to measure) or uninstrumented (no witness yet). counter=: the hardware counter to compare across the two layouts. hint=: how to add the missing instrumentation (uninstrumented only). as_stem_ambiguous=/as_stem_unowned=/as_stem_nonptr=: chase names REFUSED - 2+ owners / no owner / owner type has no pointer marker. -->
<fieldaffinity schema="ripwire.field-affinity/v1" block="64" model="lp64-approx" counts_floor="1" weighting="fanin-floor" aggregates="3024" files="609" fns_scanned="14872" accesses="15563" amb_skipped="51377" structs="1130" shown="20" capped="1" findings="1126" min_fns="2" as_loops="4582" as_index=" … [line truncated: 78 more bytes on this line]
<s n="Graph" p="src/graph.h" l="100" agg="struct" modeled="1" fields="48" touched="40" fns="168" pairs="780" sepcost="2307.62" findings="641" size="1536" align="8" lines="24">
<f n="inEdges" acc="136" fns="61" sz="48" off="0" ln="0"/>
<f n="wOutDeg" acc="36" fns="31" sz="24" off="48" ln="0"/>
<f n="outVals" acc="9" fns="6" sz="24" off="120" ln="1"/>
<f n="outAnchorMiss" acc="30" fns="19" sz="24" off="192" ln="3"/>
<f n="scipDocsSeen" acc="1" fns="1" sz="8" off="216" ln="3"/>
<f n="scipEdgesPinned" acc="1" fns="1" sz="8" off="224" ln="3"/>
<f n="baseOutsideClauses" acc="13" fns="8" sz="24" off="280" ln="4"/>
<f n="rubyMainMixins" acc="5" fns="5" sz="24" off="304" ln="4"/>
<f n="ambOut" acc="29" fns="16" sz="24" off="352" ln="5"/>
<f n="unresolvedOut" acc="28" fns="15" sz="24" off="376" ln="5"/>
<f n="locPinOut" acc="13" fns="7" sz="24" off="400" ln="6"/>
<f n="unindexedFiles" acc="8" fns="8" sz="8" off="424" ln="6"/>
<f n="rubyBasesUnscoped" acc="7" fns="7" sz="8" off="432" ln="6"/>
<f n="importAdj" acc="7" fns="5" sz="48" off="440" ln="6"/>
<f n="externalCalls" acc="11" fns="7" sz="8" off="488" ln="7"/>
<f n="declinedOut" acc="22" fns="12" sz="24" off="496" ln="7"/>
<f n="inertDeclinedCalls" acc="9" fns="7" sz="8" off="520" ln="8"/>
<f n="inertDeclinedCaller" acc="6" fns="4" sz="24" off="528" ln="8"/>
<f n="declinedListOff" acc="43" fns="15" sz="24" off="552" ln="8"/>
<f n="declinedListCand" acc="21" fns="13" sz="24" off="576" ln="9"/>
<f n="declinedListCallCount" acc="18" fns="8" sz="24" off="600" ln="9"/>
<f n="declinedSiteCaller" acc="29" fns="16" sz="24" off="624" ln="9"/>
<f n="declinedSiteList" acc="21" fns="15" sz="24" off="648" ln="10"/>
<f n="declinedSiteRef" acc="25" fns="13" sz="24" off="672" ln="10"/>
<f n="declinedSiteKind" acc="9" fns="6" sz="24" off="696" ln="10"/>
<f n="declinedSiteBound" acc="5" fns="4" sz="24" off="720" ln="11"/>
<f n="gateDeclinedTarget" acc="10" fns="4" sz="24" off="744" ln="11"/>
… [1638 more display lines; full output is 154991 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --field-affinity=Symbol`

*The same lens narrowed to ONE struct — the one --layout=Symbol shows the offsets for.*

**wall time: 1.95s**

`````
<!-- ripwire field-affinity schema=ripwire.field-affinity/v1: fields read together but declared far apart vs 64-byte lines: <s n= p=> structs, <pair a= b= fns= dist=>, <finding k= f= g=>. window: shown= capped= (capped=1 cut). counts_floor=1: every count is a FLOOR, never a total. root=: p= relative to it. sym=: the struct asked for; only its own fields and pairs are reported. block=64: ASSUMED cache-line bytes; all geometry (dist= wt= ln= lines= findings) is against it. model=lp64-approx: sizes/offsets are the layout verb's LP64 standard-layout MODEL, not the real ABI. weighting=fanin-floor: w= sums 1 + fan-in per co-accessing fn; a reachability proxy, not a frequency. aggregates=N: C-family structs/classes the layout model located a body for (the scanned universe). files=N: C-family files declaring at least one struct/class the modelling pass visited. fns_scanned=N: C-family functions/methods with a readable body scanned for dot/arrow member accesses. accesses=N: member-access sites tied to one aggregate field (FLOOR: bare in-method names uncounted). amb_skipped=N: access sites REFUSED, not guessed: 2+ aggregates declare that field name; in no count here. structs=N: aggregates with 1+ attributed access; the top 20 by sepcost= print (shown=/capped=). findings=N: split-line + straddle findings over ALL structs=, not just the printed rows. min_fns=2: a pair fires split-line only when co-accessed by this many distinct functions. as_loops=N: for-loops the static advance-shape pass classified corpus-wide; report-only, never ranks. as_index=/as_chase=/as_mixed=/as_unknown=: as_loops= by advance shape (chase = pointer chase). agg=: the aggregate keyword (struct, class ...). modeled=1: layout model placed the fields; 0 = affinity only, no geometry, no finding (why= says why). fields=N: fields declared (before the touched-only filter). touched=N: fields with 1+ attributed access; at most 32 f rows print. pairs=N: co-accessed field pairs in all; at most 12 pair rows print (most fns= first). sepcost=: sum over measured pairs of fns x (1 - wt); the struct ranking key. findings=N: this struct's findings, every one printed. size=/align=/lines=: modeled sizeof, alignment, cache lines spanned (modeled=1 only). acc=N: member-access sites attributed to this field (FLOOR). sz=B: the field's modeled size in bytes (absent when the model could not size it). off=/ln=: modeled byte offset and its cache line (off/64); placed=0 instead when the model refused. fanin=N: this function's caller count (the w= proxy input). touched=N: distinct fields of this struct the function touches (named in f=); at most 8 fn rows of fns= print. scopes=N: distinct PROFILE_SCOPEs among the co-accessing functions (the scope children). status=: instrumented (a scope exists to measure) or uninstrumented (no witness yet). counter=: the hardware counter to compare across the two layouts. as_stem_ambiguous=/as_stem_unowned=/as_stem_nonptr=: chase names REFUSED - 2+ owners / no owner / owner type has no pointer marker. -->
<fieldaffinity schema="ripwire.field-affinity/v1" block="64" model="lp64-approx" counts_floor="1" weighting="fanin-floor" aggregates="3024" files="609" fns_scanned="14872" accesses="15563" amb_skipped="51377" structs="1" shown="1" capped="0" findings="0" min_fns="2" as_loops="4582" as_index="9" as_c … [line truncated: 84 more bytes on this line]
<s n="Symbol" p="src/model.h" l="912" agg="struct" modeled="1" fields="31" touched="1" fns="15" pairs="0" sepcost="0.00" findings="0" size="112" align="8" lines="2">
<f n="fnLocal" acc="15" fns="15" sz="1" off="62" ln="0"/>
<fn n="fileDefsInLineOrder" p="src/forfilepage.h" l="418" fanin="0" touched="1" f="fnLocal"/>
<fn n="renderForFilePage" p="src/forfilepage.h" l="616" fanin="0" touched="1" f="fnLocal"/>
<fn n="applyFileSubjectLift" p="src/forfilepage.h" l="722" fanin="0" touched="1" f="fnLocal"/>
<fn n="receiverOf" p="src/forselfhook.h" l="927" fanin="0" touched="1" f="fnLocal"/>
<fn n="withTaskNamedMembers" p="src/forselfhook.h" l="1043" fanin="0" touched="1" f="fnLocal"/>
<fn n="coneDefsOf" p="src/forselfhook.h" l="1100" fanin="0" touched="1" f="fnLocal"/>
<fn n="renderForSelfHooks" p="src/forselfhook.h" l="1291" fanin="0" touched="1" f="fnLocal"/>
<fn n="localDefOutOfReach" p="src/graph.h" l="2046" fanin="0" touched="1" f="fnLocal"/>
<validate scopes="2" status="instrumented" counter="l1d-cache-misses">
<scope n="buildGraph/8: HTTP-route edges"/>
<scope n="ingest/build-model: lex stats CSR + file signatures (B0)"/>
</validate>
</s>
</fieldaffinity>
`````

## `./build/ripwire . --naming-consistency --limit=8`

*The corpus's OWN case-convention vote per (language, kind) group; off-convention names get a mechanical propose= (a suggestion, never a blind rename).*

`````
<!-- ripwire naming-consistency schema=ripwire.naming-consistency/v1: the corpus's case-convention vote per (language, kind): <g lang= kind= style= agree= total=>, <f p= n= propose=> outliers. window: shown= total= capped= has_more= next_offset= offset= limit= (capped=1 cut; next_offset= pastes as offset=). root=: p= relative to it. component_exempt=N: PascalCase .tsx/.jsx functions (read as JSX components by extension alone), kept out of voting and flagging. groups=N: (language, kind) groups with at least one styled name. candidates=N: multi-token styled names scanned. decided=N: groups whose leading style cleared both the sample and agreement floors. flagged=N: off-convention names in decided groups (the f rows). g why=insufficient-sample|no-clear-convention: which bar a style=UNAVAILABLE group missed. -->
<naming-consistency schema="ripwire.naming-consistency/v1" groups="32" candidates="19247" decided="11" flagged="794" component_exempt="8" shown="8" capped="1" total="794" has_more="1" next_offset="8" offset="0" limit="8" root=".">
<g lang="cpp" kind="fn" style="camel" agree="10526" total="11147"/>
<g lang="cpp" kind="var" style="camel" agree="2385" total="2406"/>
<g lang="py" kind="fn" style="snake" agree="1436" total="1486"/>
<g lang="py" kind="var" style="UNAVAILABLE" why="no-clear-convention" total="552"/>
<g lang="ts" kind="fn" style="camel" agree="302" total="313"/>
<g lang="ts" kind="var" style="UNAVAILABLE" why="insufficient-sample" total="5"/>
<g lang="go" kind="fn" style="UNAVAILABLE" why="no-clear-convention" total="113"/>
<g lang="go" kind="var" style="UNAVAILABLE" why="insufficient-sample" total="13"/>
<g lang="rs" kind="fn" style="snake" agree="311" total="322"/>
<g lang="rs" kind="var" style="UNAVAILABLE" why="insufficient-sample" total="13"/>
<g lang="swift" kind="fn" style="UNAVAILABLE" why="no-clear-convention" total="50"/>
<g lang="swift" kind="var" style="UNAVAILABLE" why="insufficient-sample" total="17"/>
<g lang="objc" kind="fn" style="UNAVAILABLE" why="insufficient-sample" total="18"/>
<g lang="js" kind="fn" style="camel" agree="167" total="169"/>
<g lang="js" kind="var" style="UNAVAILABLE" why="insufficient-sample" total="3"/>
<g lang="sh" kind="fn" style="UNAVAILABLE" why="no-clear-convention" total="1615"/>
<g lang="java" kind="fn" style="camel" agree="112" total="112"/>
<g lang="java" kind="var" style="UNAVAILABLE" why="insufficient-sample" total="1"/>
<g lang="rb" kind="fn" style="snake" agree="55" total="55"/>
<g lang="rb" kind="var" style="UNAVAILABLE" why="insufficient-sample" total="17"/>
<g lang="cs" kind="fn" style="pascal" agree="39" total="39"/>
<g lang="cs" kind="var" style="UNAVAILABLE" why="insufficient-sample" total="3"/>
<g lang="c" kind="fn" style="UNAVAILABLE" why="no-clear-convention" total="506"/>
<g lang="c" kind="var" style="UNAVAILABLE" why="no-clear-convention" total="20"/>
<g lang="php" kind="fn" style="UNAVAILABLE" why="insufficient-sample" total="9"/>
<g lang="php" kind="var" style="UNAVAILABLE" why="insufficient-sample" total="1"/>
<g lang="lua" kind="fn" style="UNAVAILABLE" why="insufficient-sample" total="15"/>
<g lang="ex" kind="fn" style="snake" agree="23" total="23"/>
… [13 more display lines; full output is 4390 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --naming-calibration`

*Score the naming-* rules against this repo's own rename history: proxy=old/(old+new) per rule, 0.50 = chance; read pairs= (sample size) first.*

**wall time: 20.04s**

`````
<!-- ripwire naming-calibration schema=ripwire.naming-calibration/v1: naming lint rules scored against this repo's OWN rename history (a noisy proxy): <r n= old= new= fired= proxy=>. at=: commit+dirty+shallow. probed=0: no history to mine, nothing scored (r= says why); 1 = the git walk ran. pairs=N: labelled rename pairs that survived the join, the SAMPLE SIZE; a small one means nothing. candidates=N: raw substitutions mined from the patch stream before the join; FLOOR when truncated=1. commits=N: non-merge commits walked (the walk stops at 40000). hunks=N: diff hunks with content on both sides. wide_hunks=N: hunks DROPPED for exceeding the 24-line per-side pairing cap; never mined. drop_old_alive=N: candidates dropped: the old spelling is still an indexed name. drop_new_absent=N: candidates dropped: the new spelling is no eligible indexed symbol at HEAD. drop_ambiguous=N: candidates dropped: a name on both sides of several (split, rework, revert). drop_old_skipped=N: candidates dropped: the lens skips the old spelling, no rule could fire. scope=group-rule: the rule judges co-visible names, which one pair cannot evidence; unscored, not 0/0. o=/n=: one labelled pair's old (abandoned) and new (chosen) spelling. sup=N: distinct hunks that showed this substitution. p at=: path:line of the symbol the pair joined to, not a commit (the root at= is). old_fires=: rules that fired on the old spelling; absent when none. new_fires=: rules that fired on the new spelling; absent when none. -->
<naming-calibration schema="ripwire.naming-calibration/v1" probed="1" pairs="212" candidates="3088" commits="7313" hunks="145100" wide_hunks="1520" drop_old_alive="886" drop_new_absent="1801" drop_ambiguous="189" drop_old_skipped="0" at="6ace381eb">
<r n="naming-short" old="2" new="4" fired="6" proxy="0.333"/>
<r n="naming-wordy" old="1" new="0" fired="1" proxy="1.000"/>
<r n="naming-series" scope="group-rule"/>
<r n="naming-underscore" old="0" new="0" fired="0"/>
<r n="naming-case" old="0" new="1" fired="1" proxy="0.000"/>
<r n="naming-predicate" old="0" new="0" fired="0"/>
<r n="naming-setter" old="0" new="0" fired="0"/>
<r n="naming-confusable" scope="group-rule"/>
<!-- 4 rename rows withheld: the project's own rebrand, which names a private pre-release identifier -->
<p o="ATTR" n="ATTR_RE" sup="1" at="./bench/recalleval/run_recalleval.py:84"/>
<p o="DEGRADED_PATH_ALERT" n="DISCLOSE" sup="329" at="./test/showcase_coverage_check.py:154"/>
<p o="InRepoImportCounter" n="ImportResolver" sup="1" at="./src/resolve.h:4810"/>
<p o="RunEval" n="DriveEval" sup="2" at="./test/attribmultideffix/cpp/eval_user.cc:4"/>
<p o="RunPiece" n="DrivePiece" sup="3" at="./test/attribmultideffix/cpp/piece_user.cc:4"/>
<p o="Rust" n="Go" sup="1" at="./test/fnslotcpp/src/twin_a.cc:1" new_fires="naming-short"/>
<p o="Subtoken" n="Member" sup="1" at="./test/callformfix/csharp/Main.cs:9"/>
<p o="TTCA" n="answer" sup="1" at="./src/ifacedispatch.h:309"/>
<p o="_famBIsFamily" n="_famBKind" sup="1" at="./test/showcase_capture.py:493"/>
<p o="above" n="below" sup="1" at="./src/pathgaps.h:645"/>
<p o="answerWords" n="answerTokens" sup="1" at="./src/forfilesyms.h:248"/>
<p o="appendSubjectGraphVerb" n="appendSubjectGraphVerbBlock" sup="4" at="./src/verbs_for.h:3461"/>
<p o="atomicWriteQSnap" n="atomicWriteFile" sup="4" at="./src/quality.h:5039"/>
<p o="bodyXml" n="xml" sup="2" at="./src/fordocbody.h:964"/>
<p o="brought" n="proven" sup="1" at="./test/receiverevidencecheck.sh:509"/>
<p o="captureCppScopeFact" n="captureScopeFact" sup="2" at="./src/ingest_binds.h:4953"/>
… [193 more display lines; full output is 18744 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --lint --naming-locals`

*The opt-in --lint modifier: naming predicates over LOCAL variable names too, C/C++ only, only inside functions already past a size/complexity gate.*

**wall time: 3.14s**

`````
<!-- ripwire lint schema=ripwire.lint/v1: AST-only checks, facts not gates: <rule name= count= shown_rows= rows_capped= count_capped=> of <f rule= p= in=>. window: shown= total= capped= has_more= next_offset= offset= limit= (capped=1 cut; next_offset= pastes as offset=). findings_capped=/rows_capped=/count_capped=: 1 = cut. counts_floor=1: every count is a FLOOR, never a total. root=: p= relative to it. findings=N: findings over the printed rules; a floor when findings_capped=1. findings_next=: the call counting the floored rules' rest (count_capped=1 rules only, 10x per-rule budget). -->
<lint schema="ripwire.lint/v1" findings="10489" shown="628" capped="1" total="10489" has_more="1" next_offset="628" offset="0" limit="0" counts_floor="1" findings_capped="1" findings_next="--lint --naming-locals --lint-select=magic-number --lint-max-per-rule=50000" naming_locals="1" root=".">
<rule name="c-style-cast" count="756" shown_rows="28" rows_capped="1"/>
<rule name="goto" count="17" shown_rows="0" rows_capped="1"/>
<rule name="do-while" count="20" shown_rows="0" rows_capped="1"/>
<rule name="unsafe-c-fn" count="0" shown_rows="0" rows_capped="0"/>
<rule name="weak-crypto" count="0" shown_rows="0" rows_capped="0"/>
<rule name="redundant-parens" count="0" shown_rows="0" rows_capped="0"/>
<rule name="suspicious-semicolon" count="0" shown_rows="0" rows_capped="0"/>
<rule name="typedef-over-using" count="50" shown_rows="0" rows_capped="1"/>
<rule name="magic-number" count="372" shown_rows="202" rows_capped="1" count_capped="1"/>
<rule name="empty-catch" count="1" shown_rows="0" rows_capped="1"/>
<rule name="self-assign" count="3" shown_rows="0" rows_capped="1"/>
<rule name="large-function" count="378" shown_rows="25" rows_capped="1"/>
<rule name="deep-nesting" count="553" shown_rows="35" rows_capped="1"/>
<rule name="inconsistent-return" count="2" shown_rows="0" rows_capped="1"/>
<rule name="unreachable-code" count="5" shown_rows="0" rows_capped="1"/>
<rule name="naming-short" count="4142" shown_rows="204" rows_capped="1"/>
<rule name="naming-wordy" count="196" shown_rows="7" rows_capped="1"/>
<rule name="naming-series" count="983" shown_rows="0" rows_capped="1"/>
<rule name="naming-underscore" count="2" shown_rows="0" rows_capped="1"/>
<rule name="naming-case" count="102" shown_rows="0" rows_capped="1"/>
<rule name="naming-predicate" count="1" shown_rows="0" rows_capped="1"/>
<rule name="naming-setter" count="4" shown_rows="0" rows_capped="1"/>
<rule name="naming-confusable" count="1139" shown_rows="28" rows_capped="1"/>
<rule name="naming-uninformative" count="0" shown_rows="0" rows_capped="0"/>
<rule name="atom-comma-operator" count="5" shown_rows="0" rows_capped="1"/>
<rule name="atom-embedded-crement" count="255" shown_rows="7" rows_capped="1"/>
<rule name="atom-assign-as-value" count="108" shown_rows="8" rows_capped="1"/>
<rule name="atom-nested-ternary" count="374" shown_rows="15" rows_capped="1"/>
… [640 more display lines; full output is 72767 bytes on 1 raw line(s)]
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
<rule name="naming-short" sev="info" cat="naming" lang="cpp,c,objc,py,ts,js,go,rs,swift,java,cs,rb,sh,php,lua,ex,dart,kt,gd,clj" since="v0.2.2">a 1-2 letter Function/Method/Var name — visible far beyond any tiny scope [Beniamini/Hofmeister]</rule>
<rule name="naming-wordy" sev="info" cat="naming" lang="cpp,c,objc,py,ts,js,go,rs,swift,java,cs,rb,sh,php,lua,ex,dart,kt,gd,clj" since="v0.2.2">more than 5 words in one name; a k or C-family g_/m_/s_ marker prefix is not a word [Butler; AlSuhaibani]</rule>
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
… [12 more display lines; full output is 7847 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --legend-dict`

*The session legend dictionary the MCP server serves as ripwire://legend-dict/full — one definition per line, headed by its dictv= version; no corpus needed. =roster lists the completeness attributes it defines.*

`````
ripwire legend dictionary ripwire.dict/v1 dictv=f068f81fdac8104f entries=1178
<about legend="ref" dict= dictv=>: this LAST child is only the legend pointer; the root keeps every attribute it carries inline, unchanged (schema=, each count, cut and floor); rows follow it; legend="ref": a definition is sent once per session (this dictionary's core, or the first answer that needs … [line truncated: 80 more bytes on this line]
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
ripwire.expand/v1 <ctx>: full bodies: <bodies shown= total= capped=> of <b t= l= p= n= sibs= sibs_total= sibs_capped= inc=>; <calls><c n= l= p=> resolved callees (p= when not the b's file)
ripwire.expand-file/v1 <ctx>: the file's own text: <src p= sym=>; <s n= sc= l=/> per scoped symbol; full id = p::sc::n
ripwire.candidate-page/v1 <sigs>: budgeted-bundle candidate page: a resumable window over the ranked candidate set the bundle cuts, for task= under budget_tokens=, one tier per page, ranks global across pages
ripwire.pack-task/v1 <ctx>: one-call task bundle for task= under budget_tokens=: <sigs><d n= sc= l= p=> ranking, <far><s t= n= p=> ranked but over 1 hop out (of_top= ranked rows) > <bodies><b t= n= p= l=> with <calls><c n= l= p=> callees > <callers><s rel=caller|callee shared=> 1-hop from the bodies … [line truncated: 108 more bytes on this line]
ripwire.from-trace/v1 <ctx>: trace frames mapped to indexed symbols, innermost first; the innermost in-corpus body included
ripwire.exemplar/v1 <ctx>: the best-in-class instance of kind= for the task, chosen by role: <exemplar n= p= in= ccx= tested=>, <bodies><b> to imitate
ripwire.pack-task/v1 <ctx-partitions>: N minimally overlapping agent bundles carved along call-graph communities plus one shared core; each <bundle> wraps a <ctx>; bundle role=core|partition i= symbols= modules= bytes= tokens=: one agent's ctx, symbols= ids assigned, bytes= its size; tokens= = est_t … [line truncated: 345 more bytes on this line]
ripwire.callers/v1 <callers>: 1-hop CALLERS of of= (defs= matched, count= distinct symbols): <s t= n= p=>; hop_tested=/hop_untested=
ripwire.callees/v1 <callees>: 1-hop CALLEES of of= (defs= matched, count= distinct symbols): <s t= n= p= role= tested=>
ripwire.uses/v1 <uses>: resolvable use-sites of of=: <u role=call|macro|read|write|import|extends|type p=file:line in_id=>
ripwire.impact/v1 <impact>: transitive blast radius of of=: <s t= n= p=> reach set, <f via= p=> importers; defs= matched, reaches= their transitive callers, radius_tested= non-tests an indexed test reaches, radius_untested= the rest; importers= files that #include/import a def's file
ripwire.defs/v1 <defs>: per <name q= defs=> the parsed definitions the name binds (defs= groups; a prototype with its definition is one): <d n= t= p= sel= lang= class=source|test in=>, sel= binds that one alone in any SYM verb, in= distinct callers (a floor); source first, then in=, then path
ripwire.path/v1 <path>: one DIRECTED call path from= to to=, each <s t= n= p=> a hop; reachable=0 hops=0 when none shown
… [1148 more display lines; full output is 135086 bytes on 1178 raw line(s)]
`````

## `./build/ripwire . --lint --lint-select=cache-`

*Run ONLY one rule family; the root carries selected="K of N" so a filtered zero is never confusable with an unfiltered one.*

**wall time: 2.66s**

`````
<!-- ripwire lint schema=ripwire.lint/v1: AST-only checks, facts not gates: <rule name= count= shown_rows= rows_capped= count_capped=> of <f rule= p= in=>. window: shown= total= capped= has_more= next_offset= offset= limit= (capped=1 cut; next_offset= pastes as offset=). rows_capped=: 1 = cut. root=: p= relative to it. findings=N: findings over the printed rules; a floor when findings_capped=1. -->
<lint schema="ripwire.lint/v1" findings="973" shown="631" capped="1" total="973" has_more="1" next_offset="631" offset="0" limit="0" selected="8 of 39" select="cache-" root=".">
<rule name="cache-node-container" count="54" shown_rows="31" rows_capped="1"/>
<rule name="cache-vector-of-raw-ptr" count="169" shown_rows="112" rows_capped="1"/>
<rule name="cache-vector-of-indirect" count="296" shown_rows="188" rows_capped="1"/>
<rule name="cache-heap-alloc-in-loop" count="6" shown_rows="2" rows_capped="1"/>
<rule name="cache-pointer-chase-loop" count="8" shown_rows="1" rows_capped="1"/>
<rule name="cache-gather-subscript" count="418" shown_rows="297" rows_capped="1"/>
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
… [612 more display lines; full output is 72910 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --lint --lint-ignore=naming-,cache-`

*DROP two families, applied after selection; the raw select=/ignore= you passed rides on the root.*

**wall time: 2.84s**

`````
<!-- ripwire lint schema=ripwire.lint/v1: AST-only checks, facts not gates: <rule name= count= shown_rows= rows_capped= count_capped=> of <f rule= p= in=>. window: shown= total= capped= has_more= next_offset= offset= limit= (capped=1 cut; next_offset= pastes as offset=). findings_capped=/rows_capped=/count_capped=: 1 = cut. counts_floor=1: every count is a FLOOR, never a total. root=: p= relative to it. findings=N: findings over the printed rules; a floor when findings_capped=1. findings_next=: the call counting the floored rules' rest (count_capped=1 rules only, 10x per-rule budget). -->
<lint schema="ripwire.lint/v1" findings="2947" shown="713" capped="1" total="2947" has_more="1" next_offset="713" offset="0" limit="0" counts_floor="1" findings_capped="1" findings_next="--lint --lint-select=magic-number --lint-max-per-rule=50000" selected="22 of 39" ignore="naming-,cache-" root="." … [line truncated: 1 more bytes on this line]
<rule name="c-style-cast" count="756" shown_rows="127" rows_capped="1"/>
<rule name="goto" count="17" shown_rows="0" rows_capped="1"/>
<rule name="do-while" count="20" shown_rows="0" rows_capped="1"/>
<rule name="unsafe-c-fn" count="0" shown_rows="0" rows_capped="0"/>
<rule name="weak-crypto" count="0" shown_rows="0" rows_capped="0"/>
<rule name="redundant-parens" count="0" shown_rows="0" rows_capped="0"/>
<rule name="suspicious-semicolon" count="0" shown_rows="0" rows_capped="0"/>
<rule name="typedef-over-using" count="50" shown_rows="0" rows_capped="1"/>
<rule name="magic-number" count="372" shown_rows="368" rows_capped="1" count_capped="1"/>
<rule name="empty-catch" count="1" shown_rows="0" rows_capped="1"/>
<rule name="self-assign" count="3" shown_rows="0" rows_capped="1"/>
<rule name="large-function" count="378" shown_rows="47" rows_capped="1"/>
<rule name="deep-nesting" count="553" shown_rows="78" rows_capped="1"/>
<rule name="inconsistent-return" count="2" shown_rows="0" rows_capped="1"/>
<rule name="unreachable-code" count="5" shown_rows="0" rows_capped="1"/>
<rule name="atom-comma-operator" count="5" shown_rows="1" rows_capped="1"/>
<rule name="atom-embedded-crement" count="255" shown_rows="25" rows_capped="1"/>
<rule name="atom-assign-as-value" count="108" shown_rows="17" rows_capped="1"/>
<rule name="atom-nested-ternary" count="374" shown_rows="48" rows_capped="1"/>
<rule name="atom-implicit-predicate" count="3" shown_rows="2" rows_capped="1"/>
<rule name="atom-octal-literal" count="45" shown_rows="0" rows_capped="1"/>
<rule name="atom-reversed-subscript" count="0" shown_rows="0" rows_capped="0"/>
<f rule="magic-number" p="bench/agentloop/editsuite/fixture/geometry.cpp:7" in="area_of_triangle">0.5</f>
<f rule="magic-number" p="bench/bench_chase_ab.cpp:100" in="linkChain">1023u</f>
<f rule="large-function" p="bench/bench_chase_ab.cpp:161" in="main">main (90 lines)</f>
<f rule="magic-number" p="bench/bench_chase_ab.cpp:167" in="main">20</f>
<f rule="atom-implicit-predicate" p="bench/bench_chase_ab.cpp:234" in="main">delta &lt; 0.02 &amp;&amp; delta &gt; -0.02</f>
<f rule="magic-number" p="bench/bench_chase_ab.cpp:234" in="main">0.02</f>
… [708 more display lines; full output is 67272 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --lint --lint-select=goto --lint-max-per-rule=4`

*A rule that spends its own match budget (here 4, set BELOW the default 5000 so the floor shows on this repo): goto carries count_capped="1", its count= is a FLOOR, and the root names the call that counts the rest — findings_next= re-runs only the floored rules under a 10x budget.*

**wall time: 2.98s**

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

**wall time: 2.75s**

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

**exit code: 1** — **wall time: 3.20s**

`````
(empty)
`````

stderr:

`````
ripwire: --lint-select: 'cach-' matches no rule or family (did you mean 'cache-'?) — see --lint-catalog for the full registry
`````

## `./build/ripwire . --lint --lint-select=nosuchfamily`

*A PREFIX with no near miss at all: the refusal points at --lint-catalog instead of guessing.*

**exit code: 1** — **wall time: 2.61s**

`````
(empty)
`````

stderr:

`````
ripwire: --lint-select: 'nosuchfamily' matches no rule or family — see --lint-catalog for the full registry
`````

## `./build/ripwire . --lint --sarif`

*The SAME findings as SARIF 2.1.0 (what github/codeql-action/upload-sarif consumes) — pure re-serialization, results count == the native run's.*

**wall time: 3.31s**

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
… [17225 more display lines; full output is 2445850 bytes on 1 raw line(s)]
`````

Parsed summary of the same SARIF (past the display cut):

`````
sarif 2.1.0 rules= 39 results= 8608
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

**wall time: 10.35s**

`````
<!-- ripwire dmm schema=ripwire.dmm/v1: Delta Maintainability Model base=→target=: dmm= good/(good+bad) units by size_metric=; <p k= dmm= good= bad= d_low= d_high=>. at=: commit+dirty+shallow. available=0: no score at all (dmm=UNAVAILABLE, reason= says why); never read as 1.000 or 0.000. combine=pooled: root dmm= is summed good over summed good+bad of the 3 properties (ripwire's own). low_loc=/low_cx=/low_params=: a unit is LOW risk at or under these lines / cyclomatic / params. base_units=/base_volume=/target_units=/target_volume=: units with a body and their line span per side. reason=: why no score (no unit's size, complexity or params moved; a tree failed to parse ...). -->
<dmm schema="ripwire.dmm/v1" base="6ace381eb32faf95711c423d65f82ffba22046c0" target="working-tree" at="6ace381eb" available="0" combine="pooled" size_metric="physical-loc" low_loc="15" low_cx="5" low_params="2" dmm="UNAVAILABLE" good="0" bad="0" base_units="24997" base_volume="332920" target_units=" … [line truncated: 147 more bytes on this line]
<p k="size" dmm="UNAVAILABLE" good="0" bad="0" d_low="0" d_high="0"/>
<p k="complexity" dmm="UNAVAILABLE" good="0" bad="0" d_low="0" d_high="0"/>
<p k="interfacing" dmm="UNAVAILABLE" good="0" bad="0" d_low="0" d_high="0"/>
</dmm>
`````

## `./build/ripwire . --dmm=HEAD`

*The per-commit scalar: HEAD vs its first parent, with the three separately actionable sub-scores.*

**wall time: 20.81s**

`````
<!-- ripwire dmm schema=ripwire.dmm/v1: Delta Maintainability Model base=→target=: dmm= good/(good+bad) units by size_metric=; <p k= dmm= good= bad= d_low= d_high=>. at=: commit+dirty+shallow. available=0: no score at all (dmm=UNAVAILABLE, reason= says why); never read as 1.000 or 0.000. combine=pooled: root dmm= is summed good over summed good+bad of the 3 properties (ripwire's own). low_loc=/low_cx=/low_params=: a unit is LOW risk at or under these lines / cyclomatic / params. base_units=/base_volume=/target_units=/target_volume=: units with a body and their line span per side. reason=: why no score (no unit's size, complexity or params moved; a tree failed to parse ...). -->
<dmm schema="ripwire.dmm/v1" base="c263353bd8634245218fbca4ed03b9caca5e0f30" target="6ace381eb32faf95711c423d65f82ffba22046c0" at="6ace381eb" available="0" combine="pooled" size_metric="physical-loc" low_loc="15" low_cx="5" low_params="2" dmm="UNAVAILABLE" good="0" bad="0" base_units="24997" base_vo … [line truncated: 175 more bytes on this line]
<p k="size" dmm="UNAVAILABLE" good="0" bad="0" d_low="0" d_high="0"/>
<p k="complexity" dmm="UNAVAILABLE" good="0" bad="0" d_low="0" d_high="0"/>
<p k="interfacing" dmm="UNAVAILABLE" good="0" bad="0" d_low="0" d_high="0"/>
</dmm>
`````

## `./build/ripwire . --dmm=HEAD~3..HEAD`

*The range form: tree HEAD vs tree HEAD~3.*

**wall time: 22.90s**

`````
<!-- ripwire dmm schema=ripwire.dmm/v1: Delta Maintainability Model base=→target=: dmm= good/(good+bad) units by size_metric=; <p k= dmm= good= bad= d_low= d_high=>. at=: commit+dirty+shallow. available=0: no score at all (dmm=UNAVAILABLE, reason= says why); never read as 1.000 or 0.000. combine=pooled: root dmm= is summed good over summed good+bad of the 3 properties (ripwire's own). low_loc=/low_cx=/low_params=: a unit is LOW risk at or under these lines / cyclomatic / params. base_units=/base_volume=/target_units=/target_volume=: units with a body and their line span per side. reason=: why no score (no unit's size, complexity or params moved; a tree failed to parse ...). -->
<dmm schema="ripwire.dmm/v1" base="a20a5a07064c1c787f8ca043282e3bed3df58b85" target="6ace381eb32faf95711c423d65f82ffba22046c0" at="6ace381eb" available="0" combine="pooled" size_metric="physical-loc" low_loc="15" low_cx="5" low_params="2" dmm="UNAVAILABLE" good="0" bad="0" base_units="24997" base_vo … [line truncated: 175 more bytes on this line]
<p k="size" dmm="UNAVAILABLE" good="0" bad="0" d_low="0" d_high="0"/>
<p k="complexity" dmm="UNAVAILABLE" good="0" bad="0" d_low="0" d_high="0"/>
<p k="interfacing" dmm="UNAVAILABLE" good="0" bad="0" d_low="0" d_high="0"/>
</dmm>
`````

## `./build/ripwire . --cochange --cochange-groups`

*Modularity-violation GROUPS instead of pairs: "X co-changes with {A,B,C}, none of which it depends on" — a greedy cover, disclosed as greedy.*

**wall time: 5.52s**

`````
<!-- ripwire cochange schema=ripwire.cochange/v1: files that change together in git: <pair a= b= together= deg= conf_ab= conf_ba= surprising=>, or for of= <f p= together= conf_rev=>. window: shown= total= capped= has_more= next_offset= offset= limit= (capped=1 cut; next_offset= pastes as offset=). no_file_edges=LANGS: this build resolves almost none of these languages' imports to files (Go only across go.mod replace); counts over them (ca/ce and violations= of the arch verb) are floors over the resolved edges only, and a coupling number absent beside it is unknown, not zero. unknown_pairs=N: pairs left out of groups= because surprising= is unknown for them, not 0; drop the cochange-groups flag to list them. at=: commit+dirty+shallow. root=: p= relative to it. sub_windows=N: equal-commit-count slices of window=; the denominator of recur=. recur=K: slices of sub_windows= the pair co-changed in; 1 = one burst, not a standing coupling. no_file_edges=LANGS: with unknown_pairs=N, pairs whose side imports are almost never resolved to files and none links them are in no group; groups= may be low. -->
<cochange schema="ripwire.cochange/v1" groups="156" pairs_covered="1305" cover="greedy" window="18mo@HEAD" sub_windows="3" no_file_edges="java" unknown_pairs="1" shown="30" capped="1" total="156" has_more="1" next_offset="30" offset="0" limit="0" root="." at="6ace381eb">
<group core="src/cli.h" partners="84">
<f p="src/abicheck.h" together="5" recur="3" conf_core="0.01"/>
<f p="src/arch.h" together="7" recur="3" conf_core="0.01"/>
<f p="src/clones.h" together="7" recur="3" conf_core="0.01"/>
<f p="src/codexdoctor.h" together="3" recur="2" conf_core="0.00"/>
<f p="src/columnar.h" together="5" recur="3" conf_core="0.01"/>
<f p="src/commentcoherence.h" together="3" recur="1" conf_core="0.00"/>
<f p="src/compactlegend.h" together="151" recur="3" conf_core="0.24"/>
<f p="src/contextratio.h" together="4" recur="1" conf_core="0.01"/>
<f p="src/countfloor.h" together="4" recur="2" conf_core="0.01"/>
<f p="src/crossref.h" together="25" recur="3" conf_core="0.04"/>
<f p="src/darkflags.h" together="9" recur="3" conf_core="0.01"/>
<f p="src/defectshape.h" together="4" recur="2" conf_core="0.01"/>
<f p="src/didyoumean.h" together="3" recur="1" conf_core="0.00"/>
<f p="src/dmm.h" together="4" recur="1" conf_core="0.01"/>
<f p="src/docparse.h" together="4" recur="1" conf_core="0.01"/>
<f p="src/editcheck.h" together="12" recur="3" conf_core="0.02"/>
<f p="src/editplan.h" together="9" recur="1" conf_core="0.01"/>
<f p="src/editpreview.h" together="6" recur="2" conf_core="0.01"/>
<f p="src/ensemble.h" together="7" recur="2" conf_core="0.01"/>
<f p="src/eval.h" together="3" recur="1" conf_core="0.00"/>
<f p="src/filter.h" together="4" recur="1" conf_core="0.01"/>
<f p="src/flipimpact.h" together="5" recur="3" conf_core="0.01"/>
<f p="src/gitcmd.h" together="3" recur="3" conf_core="0.00"/>
<f p="src/githarden.h" together="5" recur="2" conf_core="0.01"/>
<f p="src/gitmine.h" together="13" recur="3" conf_core="0.02"/>
<f p="src/graph.h" together="62" recur="3" conf_core="0.10"/>
<f p="src/graphlegend.h" together="63" recur="3" conf_core="0.10"/>
… [1004 more display lines; full output is 67677 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --cochange --cochange-recur=2`

*Only pairs whose co-change RECURS in 2+ sub-windows of the mined window (sub_windows= is the denominator) — a one-off sprint stops reading like a structural defect.*

**wall time: 5.46s**

`````
<!-- ripwire cochange schema=ripwire.cochange/v1: files that change together in git: <pair a= b= together= deg= conf_ab= conf_ba= surprising=>, or for of= <f p= together= conf_rev=>. window: shown= total= capped= has_more= next_offset= offset= limit= (capped=1 cut; next_offset= pastes as offset=). at=: commit+dirty+shallow. root=: p= relative to it. pairs=N: file pairs with 3+ shared commits in window= (after min_recur), surprising or not. sub_windows=N: equal-commit-count slices of window=; the denominator of recur=. driver=a|b: the side whose changes best imply the other's, look there first; absent on a tie. recur=K: slices of sub_windows= the pair co-changed in; 1 = one burst, not a standing coupling. -->
<cochange schema="ripwire.cochange/v1" pairs="3650" window="18mo@HEAD" sub_windows="3" min_recur="2" shown="30" capped="1" total="3650" has_more="1" next_offset="30" offset="0" limit="0" root="." at="6ace381eb">
<pair a="test/headsnapcachecheck.sh" b="test/qsnapcachecheck.sh" together="5" deg="1.00" conf_ab="1.00" conf_ba="0.83" driver="a" recur="3" surprising="1"/>
<pair a="test/cachesplitcheck.sh" b="test/portablecachecheck.sh" together="3" deg="1.00" conf_ab="0.75" conf_ba="1.00" driver="b" recur="3" surprising="1"/>
<pair a="test/pincensuscheck.sh" b="test/scipjoincheck.sh" together="3" deg="1.00" conf_ab="0.38" conf_ba="1.00" driver="b" recur="2" surprising="1"/>
<pair a="test/gatecountcheck.sh" b="test/regression.sh" together="3" deg="1.00" conf_ab="1.00" conf_ba="0.00" driver="a" recur="2" surprising="1"/>
<pair a="src/binstale.h" b="src/crossref.h" together="3" deg="1.00" conf_ab="1.00" conf_ba="0.03" driver="a" recur="2" surprising="1"/>
<pair a="test/luacheck.sh" b="test/phpcheck.sh" together="3" deg="1.00" conf_ab="0.75" conf_ba="1.00" driver="b" recur="2" surprising="1"/>
<pair a="test/elixircheck.sh" b="test/elixirsemanticcheck.sh" together="3" deg="1.00" conf_ab="0.13" conf_ba="1.00" driver="b" recur="2" surprising="1"/>
<pair a="test/mcpslicecheck.sh" b="test/mcpverbscheck.sh" together="3" deg="1.00" conf_ab="1.00" conf_ba="0.16" driver="a" recur="2" surprising="1"/>
<pair a="test/gatecountcheck.sh" b="test/manifestcheck.sh" together="3" deg="1.00" conf_ab="1.00" conf_ba="0.23" driver="a" recur="2" surprising="1"/>
<pair a="src/cli.h" b="src/sarif.h" together="6" deg="0.86" conf_ab="0.01" conf_ba="0.86" driver="b" recur="2" surprising="1"/>
<pair a="src/abicheck.h" b="src/landingplan.h" together="6" deg="0.86" conf_ab="0.40" conf_ba="0.86" driver="b" recur="3" surprising="1"/>
<pair a="hooks/ripwire-claude-route.sh" b="hooks/ripwire-codex-route.sh" together="20" deg="0.83" conf_ab="0.83" conf_ba="0.83" recur="3" surprising="1"/>
<pair a="src/serialize.h" b="src/verify.h" together="5" deg="0.83" conf_ab="0.01" conf_ba="0.83" driver="b" recur="2" surprising="1"/>
<pair a="test/headsnapcachecheck.sh" b="test/qsnapprefetchcheck.sh" together="4" deg="0.80" conf_ab="0.80" conf_ba="0.67" driver="a" recur="2" surprising="1"/>
<pair a="test/anchorcheck.sh" b="test/routecheck.sh" together="15" deg="0.79" conf_ab="0.79" conf_ba="0.71" driver="a" recur="3" surprising="1"/>
<pair a="src/ingest_cache.h" b="src/quality.h" together="288" deg="0.77" conf_ab="0.77" conf_ba="0.44" driver="a" recur="3" surprising="1"/>
<pair a="hooks/ripwire-claude-route.sh" b="hooks/ripwire-claude-toolroute.sh" together="6" deg="0.75" conf_ab="0.25" conf_ba="0.75" driver="b" recur="2" surprising="1"/>
<pair a="test/estchargecheck.sh" b="test/tracecheck.sh" together="3" deg="0.75" conf_ab="0.04" conf_ba="0.75" driver="b" recur="2" surprising="1"/>
<pair a="test/cachesplitcheck.sh" b="test/evictioncheck.sh" together="3" deg="0.75" conf_ab="0.75" conf_ba="0.23" driver="a" recur="2" surprising="1"/>
<pair a="test/tracecheck.sh" b="test/w3fixbudgetcheck.sh" together="3" deg="0.75" conf_ab="0.75" conf_ba="0.75" recur="2" surprising="1"/>
<pair a="test/dartcheck.sh" b="test/elixircheck.sh" together="3" deg="0.75" conf_ab="0.75" conf_ba="0.13" driver="a" recur="2" surprising="1"/>
<pair a="test/estchargecheck.sh" b="test/w3fixbudgetcheck.sh" together="3" deg="0.75" conf_ab="0.04" conf_ba="0.75" driver="b" recur="2" surprising="1"/>
<pair a="src/infra/diagnostics.cpp" b="test/diagnotice_harness.cpp" together="3" deg="0.75" conf_ab="0.30" conf_ba="0.75" driver="b" recur="2" surprising="1"/>
<pair a="hooks/ripwire-claude-route.sh" b="test/routehookcheck.sh" together="14" deg="0.74" conf_ab="0.58" conf_ba="0.74" driver="b" recur="2" surprising="1"/>
<pair a="src/ingest_model.h" b="src/model.h" together="53" deg="0.74" conf_ab="0.74" conf_ba="0.16" driver="a" recur="3" surprising="1"/>
<pair a="src/quality.h" b="src/tsprobe.cpp" together="8" deg="0.73" conf_ab="0.01" conf_ba="0.73" driver="b" recur="3" surprising="1"/>
<pair a="src/commentcoherence.h" b="src/readability.h" together="5" deg="0.71" conf_ab="0.71" conf_ba="0.42" driver="a" recur="2" surprising="1"/>
<pair a="src/ingest_ruby.h" b="src/model.h" together="7" deg="0.70" conf_ab="0.70" conf_ba="0.02" driver="a" recur="2" surprising="1"/>
<pair a="src/ingest_cache.h" b="src/ingest_ruby.h" together="7" deg="0.70" conf_ab="0.02" conf_ba="0.70" driver="b" recur="2" surprising="1"/>
<pair a="src/ingest_relations.h" b="src/ingest_ruby.h" together="7" deg="0.70" conf_ab="0.08" conf_ba="0.70" driver="b" recur="2" surprising="1"/>
</cochange>
`````

## `./build/ripwire . --html=<scratch>/aux/map2.html --color-by=community`

*The HTML graph with the initial colour mode set to community (the page embeds all five modes and keeps a live selector).*

**wall time: 5.11s**

`````
(empty)
`````

Artifact written:

`````
  155370 <scratch>/aux/map2.html
`````

## `./build/ripwire . --index-out=<scratch>/aux/ci_index`

*CI generate-and-exit: cold-parse and write BOTH committable cache families (lean + rich), no map on stdout.*

**wall time: 7.94s**

`````
(empty)
`````

stderr:

`````
ripwire: --index-out wrote <scratch>/aux/ci_index.lean.ripwirecache (40617339 bytes, lean family)
ripwire: --index-out wrote <scratch>/aux/ci_index.rich.ripwirecache (81815328 bytes, rich family)
`````

Artifact written:

`````
 40617339 <scratch>/aux/ci_index.lean.ripwirecache
 81815328 <scratch>/aux/ci_index.rich.ripwirecache
 122432667 total
`````

## `./build/ripwire . --cache=<scratch>/aux/ci_index.lean.ripwirecache --top-k=3`

*Consume the lean artifact in a PR job: restore-equivalence, never blob-byte-identity.*

**wall time: 3.66s**

`````
<!-- ripwire map schema=ripwire.map/v1: ranked symbol map: <f p= layer=> groups <s t= n= sc= k= amb=> rows (k= rank), <c n=> resolved callees; the header comment is data. est_tokens=: price as emitted (an upper bound under compact). root=: p= relative to it. pr_iters=N: PageRank iterations. <inv listed= unlisted=>: files the ranked rows show / do not (sum = files=), each named or counted below. <entry p= n=>: a program entry by its language's convention (C/Go/Rust main, Java/C# static main, a script main its module scope calls, __main__.py), callees as c rows; manifest entries not read. <ls p= n= f=>: n= unshown files under dir p=; f= names its code files, the rest (tests, docs, config, test/doc/example dirs) counted. declined=K: K call sites without edges, including inert Elixir quote sites after unquote/unquote_splicing re-entry. external=K: K calls proven outside the tree, no edge. locality_pinned=K: K calls pinned by locality alone (a guess). extent_suspect_syms=K: K defs failed containment, corpus-wide. macro_blanked_files=K: K files indexed from a macro-blanked re-parse. prov=scip|binding|import|split|final-segment: how that <c> edge bound (absent: one unique name); split = one arm of an amb= pick; final-segment = a qualified type matched by last name only. files=/symbols=: files and symbols indexed; edges= distinct call edges; shown= symbols printed, a merged row counting each def; ambiguous= calls split over several defs, corpus-wide; unresolved= calls with in-tree evidence and no edge (every def language-filtered or unreachable, or binding refused); order= rows by rank (important-first, important-last; (auto:fill) = flipped past a size threshold) or by path (stable). skipped_oversize=K: K files over a size ceiling, not indexed. unindexed=ext:N: N text files of that extension no grammar reads (6 extensions at most). unindexed_exts=E: E such extensions in all, the list cut. sc=: enclosing scope; the full id is p::sc::n (p= of the row or its <f>) and selectors take it. -->
<!-- t=modscope=a-file's-MODULE-SCOPE(n=<file-scope>):the-statements-outside-every-named-definition,where-a-top-level-call-and-an-anonymous-callback-body's-calls-live;a-CALLER-never-a-callee(nothing-in-the-source-can-name-it)-with-no-body-to-expand;a-file-with-no-such-call-has-no-such-row -->
<!-- t=type|alias|functype=a-Go-named-type-by-its-written-form:type=a-defined-type-whose-WRITTEN-form-is-not-a-struct/iface/func-literal(type-N-string;type-W-Pair-too,whatever-Pair-is-underneath),alias=type-A=B,functype=type-F-func(...) -->
<!-- t=alias|functype-in-C++-and-.h:alias=using-X=Y(also-templated-or-class-scope)or-namespace-L=lib(defs=X-prints-its-written-target-as-to=),functype=a-typedef-of-a-function-or-function-pointer-type(typedef-void(*F)(int));other-typedefs-read-t=struct -->
<!-- files=4838 symbols=44600 edges=44429 shown=3 est_tokens=4041 ambiguous=3634 unresolved=20069 locality_pinned=14 external=12457 declined=45295 extent_suspect_syms=12 macro_blanked_files=7 skipped_oversize=15 unindexed="txt:85,tsv:54,mod:33,xml:33,jsonl:26,scm:25" unindexed_exts=23 order=important-first -->
<r schema="ripwire.map/v1" root="." est_tokens="4041" pr_iters="40">
<f p="src/infra/nodekind.h" layer="infra">
<s t="fn" n="kindIs" sc="rw" k="0.0031">
</s>
</f>
<f p="src/ingest_metrics.h">
<s t="fn" n="nodeTextOf" k="0.0021">
</s>
</f>
<f p="src/infra/namesplit.h" layer="infra">
<s t="fn" n="isIdentChar" sc="namesplit" k="0.0020">
</s>
</f>
<inv listed="3" unlisted="4835">
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
… [80 more display lines; full output is 10090 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --pin-census=<scratch>/aux/pin_census.tsv --top-k=3`

*Eval-only: a per-call-site census of WHICH mechanism resolved each call, and the canonical id of every surviving target.*

**wall time: 2.71s**

`````
<!-- ripwire map schema=ripwire.map/v1: ranked symbol map: <f p= layer=> groups <s t= n= sc= k= amb=> rows (k= rank), <c n=> resolved callees; the header comment is data. est_tokens=: price as emitted (an upper bound under compact). root=: p= relative to it. pr_iters=N: PageRank iterations. <inv listed= unlisted=>: files the ranked rows show / do not (sum = files=), each named or counted below. <entry p= n=>: a program entry by its language's convention (C/Go/Rust main, Java/C# static main, a script main its module scope calls, __main__.py), callees as c rows; manifest entries not read. <ls p= n= f=>: n= unshown files under dir p=; f= names its code files, the rest (tests, docs, config, test/doc/example dirs) counted. declined=K: K call sites without edges, including inert Elixir quote sites after unquote/unquote_splicing re-entry. external=K: K calls proven outside the tree, no edge. locality_pinned=K: K calls pinned by locality alone (a guess). extent_suspect_syms=K: K defs failed containment, corpus-wide. macro_blanked_files=K: K files indexed from a macro-blanked re-parse. prov=scip|binding|import|split|final-segment: how that <c> edge bound (absent: one unique name); split = one arm of an amb= pick; final-segment = a qualified type matched by last name only. files=/symbols=: files and symbols indexed; edges= distinct call edges; shown= symbols printed, a merged row counting each def; ambiguous= calls split over several defs, corpus-wide; unresolved= calls with in-tree evidence and no edge (every def language-filtered or unreachable, or binding refused); order= rows by rank (important-first, important-last; (auto:fill) = flipped past a size threshold) or by path (stable). skipped_oversize=K: K files over a size ceiling, not indexed. unindexed=ext:N: N text files of that extension no grammar reads (6 extensions at most). unindexed_exts=E: E such extensions in all, the list cut. sc=: enclosing scope; the full id is p::sc::n (p= of the row or its <f>) and selectors take it. -->
<!-- t=modscope=a-file's-MODULE-SCOPE(n=<file-scope>):the-statements-outside-every-named-definition,where-a-top-level-call-and-an-anonymous-callback-body's-calls-live;a-CALLER-never-a-callee(nothing-in-the-source-can-name-it)-with-no-body-to-expand;a-file-with-no-such-call-has-no-such-row -->
<!-- t=type|alias|functype=a-Go-named-type-by-its-written-form:type=a-defined-type-whose-WRITTEN-form-is-not-a-struct/iface/func-literal(type-N-string;type-W-Pair-too,whatever-Pair-is-underneath),alias=type-A=B,functype=type-F-func(...) -->
<!-- t=alias|functype-in-C++-and-.h:alias=using-X=Y(also-templated-or-class-scope)or-namespace-L=lib(defs=X-prints-its-written-target-as-to=),functype=a-typedef-of-a-function-or-function-pointer-type(typedef-void(*F)(int));other-typedefs-read-t=struct -->
<!-- files=4838 symbols=44600 edges=44429 shown=3 est_tokens=4041 ambiguous=3634 unresolved=20069 locality_pinned=14 external=12457 declined=45295 extent_suspect_syms=12 macro_blanked_files=7 skipped_oversize=15 unindexed="txt:85,tsv:54,mod:33,xml:33,jsonl:26,scm:25" unindexed_exts=23 order=important-first -->
<r schema="ripwire.map/v1" root="." est_tokens="4041" pr_iters="40">
<f p="src/infra/nodekind.h" layer="infra">
<s t="fn" n="kindIs" sc="rw" k="0.0031">
</s>
</f>
<f p="src/ingest_metrics.h">
<s t="fn" n="nodeTextOf" k="0.0021">
</s>
</f>
<f p="src/infra/namesplit.h" layer="infra">
<s t="fn" n="isIdentChar" sc="namesplit" k="0.0020">
</s>
</f>
<inv listed="3" unlisted="4835">
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
… [80 more display lines; full output is 10090 bytes on 1 raw line(s)]
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
  181226 <scratch>/aux/pin_census.tsv
`````

## `./build/ripwire . --plan-lint=test/planlintfix/wave.md`

*The house PLAN/DESIGN format's STRUCTURE check — never semantics; exit 2 when a card or ledger row gates.*

**exit code: 2** — **wall time: 5.64s**

`````
<!-- ripwire plan-lint schema=ripwire.plan-lint/v1: structural lint of a plan document: each finding names the section and the rule. at=: commit+dirty+shallow. file=/dialect=: the plan read and whether the PLAN dialect was detected (dialect=0: nothing to lint). cards=/ledger=: card rows found / whether the doc carries a ledger (ledger_line= names its line). git=1: git was available, so the staleness read ran; stale_commits=N: a waiting card N commits behind HEAD is stale. gating=N: findings that fail the plan (exit 2); the rest are advisory. -->
<plan-lint schema="ripwire.plan-lint/v1" file="test/planlintfix/wave.md" dialect="1" cards="3" ledger="1" ledger_line="21" at="6ace381eb" git="1" stale_commits="20" gating="3">
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

**exit code: 2** — **wall time: 2.82s**

`````
<!-- ripwire plan-lint schema=ripwire.plan-lint/v1: structural lint of a plan document: each finding names the section and the rule. at=: commit+dirty+shallow. file=/dialect=: the plan read and whether the PLAN dialect was detected (dialect=0: nothing to lint). cards=/ledger=: card rows found / whether the doc carries a ledger (ledger_line= names its line). git=1: git was available, so the staleness read ran; stale_commits=N: a waiting card N commits behind HEAD is stale. gating=N: findings that fail the plan (exit 2); the rest are advisory. -->
<plan-lint schema="ripwire.plan-lint/v1" file="test/planlintfix/wave_ledger.md" dialect="1" cards="4" ledger="1" ledger_line="17" at="6ace381eb" git="1" stale_commits="20" gating="1">
<card id="T1" line="4" status="check" tline="6"/>
<card id="T2" line="8" status="check" tline="18" src="ledger"/>
<card id="T5" line="11" status="missing" tline="12" why="unlaunched" gating="1"/>
<card id="T7" line="14" status="check" tline="20" src="ledger"/>
</plan-lint>
`````

## `./build/ripwire . --doctor --agent=claude`

*--doctor plus a LIVE integration inspection for one agent: PATH binary, installed-skill manifest parity, hook executability, MCP wiring — read-only, fixed repair commands, never config contents; exit 1 when any check fails.*

**exit code: 1** — **wall time: 37.48s**

`````
<!-- ripwire doctor schema=ripwire.doctor/v1: setup health: <c n= ok=> checks; exit 1 when one fails. at=: commit+dirty+shallow. n=: the check's name (binary-path, grammars, cache-dir, git, tree-sitter, index-cache, layout ...). agent=: the agent named by the agent flag; its live-integration c rows follow the built-in checks. loaded=/expected=: grammars whose tags query compiled / grammars compiled in; a shortfall fails the row. dir=: the per-user cache directory scanned (TMPDIR/XDG_CACHE_HOME ladder); unwritable fails the row. blobs=N: ripwire cache blobs in dir=; the scan stops at 4096 (blobs_floor=1 then). bytes=N: total size in bytes of the blobs counted (short when truncated=1). many=1: more than 50 blobs; an eviction-sanity flag, informational, never fails the row. truncated=1: cache-dir, blob scan cut (cap or I/O error); tracked-binaries, scan SKIPPED, stale=0 unmeasured. locks=N: advisory edit-lock files under locks/; unheld ones over a day old are swept on a cache write. volatile=: this row's attributes that read LIVE machine state; a determinism diff strips them, never the row. git=0|1: git runs from PATH; 0 fails the row (churn verbs need it). repo=0|1: the root is inside a git work tree; 0 is a diagnosis, not a failure. history=0|1: the repo has at least one commit; head= prints only when it does. head=: HEAD's short sha (9 hex, the at= width). core_abi=/cpp_grammar_abi=: tree-sitter core language ABI / the C++ grammar's ABI; informational. languages=N: distinct compiled-in grammars (the grammars row's expected=). tracked=N: git ls-files count, printed even when truncated=1 (over 20000 files skips the scan). binaries=N: tracked paths that sniff as binary content. non_git=1: no git history to compare; the row passes unscanned. stale=N: tracked binaries committed before a same-dir same-stem source changed; any fails the row. cache_version=/parser_ver_lean=/parser_ver_rich=/artifact_arch=: index identity; reuse needs all four. rich_verbs=: the verbs that consume the rich artifact (rich=); every other verb reads the lean one. source=: auto (per-root blob), cache-flag (named by the cache flag) or disabled (no-cache: nothing read). lean_path=/rich_path=: the artifact files checked; one path when the cache flag named it. lean=/rich=: can THIS binary open that artifact (ok, absent, parser-version ...); format, never freshness. fsmonitor=: the checkout's core.fsmonitor at startup: unset, builtin, off, or hook (a command git runs). neutralised=1: a hook fsmonitor was overridden to false for this run; 0 when none was needed. filter_drivers=N: filter drivers the repository's own config defines; filter_scope= local|all, filter_pinned= 1 (run with an empty command) or refused. state=: layout records agree, disagree (mixed binary: rebuild clean-first), not-checked or no-records. checked=1: the cross-unit layout comparison ran; 0 = under two comparable records. units=N: translation units that registered a layout record. types=N: layout types recorded (only those registered in src/model.h); omitted on state=disagree. checks=/passed=: checks run / how many passed; exit 1 when passed= is below checks=. built_from=: the commit this binary was built from; at= is the tree HEAD now, a mismatch is normal. self=/which=: this binary's path and the one which ripwire finds on PATH; which_version= is the version line that one prints when they differ. on_path=0|1: whether a ripwire is on PATH; 0 fails the row and hint= carries the export line. same_file=1: the PATH copy is this very file (same device and inode). same_bytes=1: a different file with identical content, a copied install (ok); 0 fails the row; unknown: a file was unreadable; the row fails unverified (hint= names it). self_mtime=/self_size=/which_mtime=/which_size=: epoch mtime and byte size of each binary. hint=: the row's verdict and fix in plain text (which binary is stale, what to run). -->
<doctor schema="ripwire.doctor/v1" checks="12" passed="10" agent="claude" at="6ace381eb" built_from="6ace381eb">
<c n="binary-path" ok="0" self="./build/ripwire" which="<path>" on_path="1" same_file="0" same_bytes="0" self_mtime="1795216845" self_size="65703608" which_mtime="1793517843" which_size="58197960" which_version="ripw … [line truncated: 525 more bytes on this line]
<c n="grammars" ok="1" loaded="27" expected="27"/>
<c n="cache-dir" ok="1" dir="<tmp>" blobs="270" bytes="2404961172" many="1" truncated="0" locks="275" volatile="blobs,blobs_floor,bytes,many,truncated,locks"/>
<c n="git" ok="1" git="1" repo="1" history="1" head="6ace381eb"/>
<c n="tree-sitter" ok="1" core_abi="15" cpp_grammar_abi="14" languages="27"/>
<c n="tracked-binaries" ok="1" tracked="5582" binaries="33" non_git="0" truncated="0" stale="0"/>
<c n="index-cache" ok="1" cache_version="54" parser_ver_lean="333" parser_ver_rich="334" artifact_arch="16" rich_verbs="for,uses,metrics,exemplar,context-ratio,nonlocal-state,quality-panel,verify,eval-retrieval,eval-mined,eval-skills" source="auto" lean_path="<tmp> … [line truncated: 219 more bytes on this line]
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

**wall time: 17.63s**

`````
ripwire situational-awareness — 1 changed file(s), 14 symbols in them
root: .
at: 6ace381eb+dirty
  change_set: granularity=file changed_symbols=14 file_symbols=14 files_narrowed=0 files_file_granular=1 diff_hunks=7 diff_hunks_located=6 diff_hunks_unlocated=1 — seeds = symbols a diff -U0-vs-HEAD hunk overlaps (function/method body spans only); an unlocated hunk (module-level, deletion, rename) … [line truncated: 34 more bytes on this line]
  [1] blast radius: 1024 symbols across 148 files transitively depend on these changes (showing 8 of 148 files — shown=8 total=148 capped=1 prcontext_cap=20 (--pr-context's own per-file list is cut at 20 too); next: --situ --limit=148)
        counts_floor=1 graph_ambiguous=3634 graph_unresolved=20069 graph_unindexed=313 (files no grammar in this build could read at all) (the map header's own gauges) — every count above is a FLOOR, never a total: call edges are name-based, so dynamic dispatch, callbacks and macros can be missing … [line truncated: 45 more bytes on this line]
        src/graph.h  (59 dependent symbols)
        src/quality.h  (43 dependent symbols)
        src/mcpverbs.h  (41 dependent symbols)
        src/verbs_for.h  (33 dependent symbols)
        src/backhops.h  (31 dependent symbols)
        src/slice.h  (31 dependent symbols)
        src/resolve.h  (26 dependent symbols)
        src/defectshape.h  (25 dependent symbols)
  [2] tests to run (12) order=evidence: [changed] you edited it, [partner] named after a changed file, then hops asc (1 = direct); "(n): a, b" = n runner-less files sharing that evidence; a (run: …) is relative to root:
        test/verify_radix.cpp [hops=1]   (run: bash test/greptiercheck.sh)
        test/adaptivecutshapefix/adaptive_cut_shape_test.cpp [hops=2]   (run: bash test/adaptivecutshapecheck.sh)
        test/connectcore_harness.cpp [hops=2]   (run: bash test/connectcorecheck.sh)
        test/forrowfeatures_unit.cpp [hops=2]   (run: bash test/forrowfeaturescheck.sh)
        test/fuzz/readers/readers_domain.cpp [hops=2]   (run: not derivable)
        test/verify_csr.cpp [hops=2]   (run: bash test/a9disclosurecheck.sh)
        test/cloneband_harness.cpp [hops=3]   (run: bash test/clonebandcheck.sh)
        test/shstatus_harness.cpp [hops=3]   (run: bash test/gateexitcheck.sh)
        test/type3clone_harness.cpp [hops=3]   (run: bash test/type3clonecheck.sh)
        test/includeprecise_unit.cpp [hops=4]   (run: bash test/includeprecisecheck.sh)
        test/rustimport_unit.cpp [hops=4]   (run: bash test/rustimportprecisecheck.sh)
        test/fuzz/readers/readers_light.cpp [hops=5]   (run: not derivable)
        script_gates_unmodelled=946 — test/*.sh gates never appear above: script-to-binary edges are not call edges (a path count)
  [3] co-change — usually edited with these but NOT in your diff (0) window="18mo@HEAD" commits="7913":
        (none — 7913 commits were mined and none co-edited a file outside your diff)
  next: --test-gate
`````

## `./build/ripwire . --test-gate`

*The pre-PR gate with real obligations — exit 4 when tests-to-run or untested blast radius is non-empty.*

**exit code: 4** — **wall time: 14.58s**

`````
<!-- ripwire test-gate schema=ripwire.test-gate/v1: tests <t p= changed= partner= hops= run=> + untested blast radius <u sym= p= l= ccx=>; exit 4 while either exists. window: total= has_more= next_offset= offset= limit= (capped=1 cut; next_offset= pastes as offset=). tests_capped=/untested_capped=: 1 = cut. counts_floor=1: every count is a FLOOR, never a total. graph_ambiguous=/graph_unresolved=: resolver gauge. graph_unindexed=N: N files no grammar could read (the map header's unindexed=); their calls raise neither gauge. declined_calls=K: K call sites left unbound (no evidence chose one def), in no count or row. run_unknown=1: no runner derivable (a guess would be worse). at=: commit+dirty+shallow. root=: p= relative to it. next=: the one pasteable follow-up. impacted=N: symbols that transitively call the change (changed symbols excluded). shown_tests=/shown_untested=: t rows and u rows printed, two independent counts. script_gates_unmodelled=N: test/*.sh runners in the corpus, a path count; not call-graph modelled. run_first=N: the first N t rows have the most direct evidence (changed/partner/hops=1, else nearest hops=); not a skip list. script_gates_registered=N: shell gates test/regression.sh registers as suite members. script_gates_mapped=N: registered gates with exact dependency evidence (literal paths or RIPWIRE_TEST_DEPS). script_gates_unresolved_dynamic=N: registered gates with no mappable deps; they may cover the change unlisted. ccx_bar=N: the cognitive-complexity bar a u row's ccx= is read against. change_granularity=: how the change set seeded — symbol = only symbols a git hunk (diff -U0 vs HEAD) locates inside a function/method body; file = whole changed files (an unlocated hunk — module-level, deletion, rename — returns its file to file-granular); mixed = both. changed_symbols=/file_symbols=: the seeds the walk used vs all symbols of the changed files. files_narrowed=/files_file_granular=: changed files under each treatment. diff_hunks=/diff_hunks_located=/diff_hunks_unlocated=: the hunk tally; an unlocated hunk is WHY a file went file-granular. untested_modscope=N: <file-scope> owners excluded from untested= (#324, uncallable); still in impacted=. tests=/untested=: tests to run (t total) / impacted symbols no test reaches (u total). -->
<test-gate schema="ripwire.test-gate/v1" changed="1" impacted="1024" tests="12" untested="854" untested_modscope="1" shown_tests="12" tests_capped="0" shown_untested="25" untested_capped="1" script_gates_unmodelled="946" script_gates_registered="881" script_gates_mapped="290" script_gates_unresolved … [line truncated: 447 more bytes on this line]
<t p="test/verify_radix.cpp" hops="1" run="bash test/greptiercheck.sh"/>
<t p="test/adaptivecutshapefix/adaptive_cut_shape_test.cpp" hops="2" run="bash test/adaptivecutshapecheck.sh"/>
<t p="test/connectcore_harness.cpp" hops="2" run="bash test/connectcorecheck.sh"/>
<t p="test/forrowfeatures_unit.cpp" hops="2" run="bash test/forrowfeaturescheck.sh"/>
<t p="test/fuzz/readers/readers_domain.cpp" hops="2" run_unknown="1"/>
<t p="test/verify_csr.cpp" hops="2" run="bash test/a9disclosurecheck.sh"/>
<t p="test/cloneband_harness.cpp" hops="3" run="bash test/clonebandcheck.sh"/>
<t p="test/shstatus_harness.cpp" hops="3" run="bash test/gateexitcheck.sh"/>
<t p="test/type3clone_harness.cpp" hops="3" run="bash test/type3clonecheck.sh"/>
<t p="test/includeprecise_unit.cpp" hops="4" run="bash test/includeprecisecheck.sh"/>
<t p="test/rustimport_unit.cpp" hops="4" run="bash test/rustimportprecisecheck.sh"/>
<t p="test/fuzz/readers/readers_light.cpp" hops="5" run_unknown="1"/>
<u sym="dispatchMcpLine" p="src/mcp.h" l="1151" ccx="794"/>
<u sym="runForLensPass" p="src/verbs_for.h" l="3606" ccx="706"/>
<u sym="dispatchMainBody" p="src/main.cpp" l="4653" ccx="513"/>
<u sym="runQualityDelta" p="src/verbs_quality.h" l="2638" ccx="323"/>
<u sym="serialize" p="src/serialize.h" l="3317" ccx="319"/>
<u sym="computeDelta" p="src/quality.h" l="11886" ccx="316"/>
<u sym="runDefaultMap" p="src/main.cpp" l="1758" ccx="313"/>
<u sym="renderForLiteral" p="src/forliteral.h" l="4210" ccx="277"/>
<u sym="runStructureText" p="src/verbs_report.h" l="3358" ccx="270"/>
<u sym="runMaintenanceViews" p="src/verbs_report.h" l="1359" ccx="242"/>
<u sym="packSignatures" p="src/serialize.h" l="6206" ccx="235"/>
<u sym="packTaskBundleText" p="src/packtask.h" l="1448" ccx="226"/>
<u sym="astQueryGrouped" p="src/ingest_astquery.h" l="842" ccx="214"/>
<u sym="writePrContext" p="src/prcontext.h" l="1078" ccx="176"/>
<u sym="runChangeViews" p="src/verbs_change.h" l="245" ccx="163"/>
<u sym="runZoom" p="src/verbs_report.h" l="3027" ccx="160"/>
<u sym="renderForAliasHops" p="src/foraliashop.h" l="125" ccx="154"/>
<u sym="runVerify" p="src/verbs_navigate.h" l="2297" ccx="144"/>
<u sym="resolveAllByWrittenSpelling" p="src/graph.h" l="16615" ccx="142"/>
<u sym="runBatchSub" p="src/mcpverbs.h" l="6334" ccx="142"/>
<u sym="pathBridge" p="src/pathgaps.h" l="1262" ccx="139"/>
<u sym="spliceSlotJoinRows" p="src/forslots.h" l="323" ccx="137"/>
<u sym="runArchViews" p="src/verbs_report.h" l="503" ccx="130"/>
<u sym="pathNearSink" p="src/pathgaps.h" l="778" ccx="127"/>
<u sym="packLego" p="src/serialize.h" l="10315" ccx="124"/>
</test-gate>
`````

## `./build/ripwire . --quality-delta`

*Every row carries p="file:line", the gating rows are marked gating="1" and now bar= (the threshold each numeric row is judged against), and the exit-2 refusal prints a naming line on stderr; a gating row carries a pasteable next=.*

**exit code: 2** — **wall time: 71.00s**

`````
<!-- ripwire quality-delta schema=ripwire.quality-delta/v1: only what the change made WORSE vs baseline=: regressions= minor= gating=; <r kind= sym= p= was= now= gating= bar=>, <sa> acked. value-ref-excluded=N: internal functions kept off because a table, field or argument in another function or at file scope holds them (matched by name, not a proven call); a floor. at=: commit+dirty+shallow. next=: the one pasteable follow-up. stale=N: ack ledger rows whose target no longer applies (sa rows); never gating. preexisting-worse=N: regressions on symbols that existed at baseline; they gate when major. new-symbol=N: NEW code; new-symbol rows never gate, except defect-shape format-arity or a ceiling= row. register-macro-excluded=N: symbols skipped: self-registering test/bench macros or Rust #[test]; a floor. declined-call-excluded=N: symbols kept out of dead-code only because a declined call may mean them; a floor. api-new-surface=N: new PUBLIC symbols; a count, never gates, not in regressions=. renames=/rename_window_commits=: git rename pairs read over that many commits, to re-file baseline and acks. acked_by_rename=/acked_by_content=: acked= suppressions matched via git renames / an equal body hash. renames_window_truncated=1: history is deeper than the rename window, older renames unread. r surface=: the api-surface tier, new-symbol or contract-change. acked=N: findings suppressed by the ack ledger, listed as sa rows; never gating. r sev=minor: a small numeric delta, counted in minor=, never gating (absent: major). r origin=new-symbol: a finding on NEW code; moved: its body left another name or file, never gating (absent: preexisting-worse). sa key=/why=: the stale ack's ledger hash / target-gone (names nothing now) or finding-gone (no longer fires). r members=/tokens=: a duplication row's clone group (member ids) / their shared normalized-token count. -->
<quality-delta schema="ripwire.quality-delta/v1" baseline="git-HEAD" regressions="9" minor="1" acked="0" stale="195" preexisting-worse="6" new-symbol="3" gating="5" register-macro-excluded="63" api-new-surface="2" at="6ace381eb+dirty" renames="68" rename_window_commits="400" acked_by_rename="0" acke … [line truncated: 99 more bytes on this line]
<r kind="api-surface" sym="src/infra/sortutil.h::rw::sortutil::nonNegativeFloatDescKey" was="1" now="2" surface="contract-change" p="src/infra/sortutil.h:122" gating="1" next="--expand=src/infra/sortutil.h:nonNegativeFloatDescKey"/>
<r kind="complexity" sym="src/infra/sortutil.h::rw::sortutil::lessByScoreDescId" was="1" now="67" bar="15" p="src/infra/sortutil.h:62" gating="1" next="--expand=src/infra/sortutil.h:lessByScoreDescId"/>
<r kind="dead-code" sym="src/infra/sortutil.h::rw::sortutil::nonNegativeFloatAscKeyCopy" origin="new-symbol" p="src/infra/sortutil.h:132"/>
<r kind="dead-code" sym="src/infra/sortutil.h::rw::sortutil::sortScoredIdsWithOptions" origin="new-symbol" p="src/infra/sortutil.h:142"/>
<r kind="duplication" members="src/infra/sortutil.h::rw::sortutil::nonNegativeFloatAscKeyCopy | src/infra/sortutil.h::rw::sortutil::nonNegativeFloatDescKey" tokens="59" p="src/infra/sortutil.h:132" gating="1"/>
<r kind="nesting" sym="src/infra/sortutil.h::rw::sortutil::lessByScoreDescId" was="1" now="6" bar="4" p="src/infra/sortutil.h:62" gating="1" next="--expand=src/infra/sortutil.h:lessByScoreDescId"/>
<r kind="new-clone-of-reused-helper" sym="src/infra/sortutil.h::rw::sortutil::nonNegativeFloatAscKeyCopy | src/infra/sortutil.h::rw::sortutil::nonNegativeFloatDescKey" was="0" now="4" p="src/infra/sortutil.h:132" gating="1" next="--expand=src/infra/sortutil.h:nonNegativeFloatDescKey"/>
<r kind="params" sym="src/infra/sortutil.h::rw::sortutil::sortScoredIdsWithOptions" was="0" now="8" bar="5" origin="new-symbol" p="src/infra/sortutil.h:142"/>
<r kind="verbosity" sym="src/infra/sortutil.h::rw::sortutil::lessByScoreDescId" was="8" now="47" bar="60" sev="minor" p="src/infra/sortutil.h:62"/>
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
<sa kind="api-surface:new-symbol" key="26e3f9a6bff9ea57" why="target-gone"/>
<sa kind="api-surface:new-symbol" key="36e39c7ab0fc1686" why="target-gone"/>
… [177 more display lines; full output is 20863 bytes on 1 raw line(s)]
`````

stderr:

`````
ripwire: no ./.ripwire_quality_baseline — auto-comparing the working tree vs git HEAD (commit the baseline with --quality-baseline to pin it)
ripwire: --quality-delta gating: 5 preexisting-worse major finding(s); first: api-surface src/infra/sortutil.h::rw::sortutil::nonNegativeFloatDescKey at src/infra/sortutil.h:122 (was=1 now=2)
`````

## `./build/ripwire . --quality-delta --legend=full`

*The same gating report under --legend=full — same rows, same exit 2; the default compact comment (schema="ripwire.quality-delta/v1", the shape an agent's edit loop should run) becomes ~4 KB of prose legend.*

**exit code: 2** — **wall time: 56.27s**

`````
<!-- ripwire quality-delta: only what a change made WORSE against the floor baseline= names below. Descriptive: weigh and fix the real ones, do not game the number (a wrong abstraction beats a low score). THIRTEEN KINDS, and kind= on every row names which one: complexity over the ccx bar, verbosity (LOC), nesting, params, duplication, dead-code, api-surface (new public contract drift), error-masking, short-horizon-churn, new-clone-of-reused-helper, placeholder (added stub/TODO), defect-shape (defect= names it), tangle (a long function's nesting, deep share and steering locals; report-only). THREE independent axes, in this order: (1) acked findings are suppressed entirely (acked= counts them); (2) ORIGIN — a finding on a symbol that EXISTED at the baseline is preexisting-worse (no origin attribute), one that exists only because the code is NEW carries origin="new-symbol"; (3) MATERIALITY — a small numeric delta is sev="minor", and minor= counts them. EXIT 2 fires only on preexisting-worse AND major, the gating= count; new-symbol rows never gate, except defect-shape format-arity and a new function at the ceiling, so exit 0 is NOT a verdict on them — nothing that existed got worse, but the new debt is yours: read them. Clone kinds are new-symbol only when EVERY member is new; short-horizon-churn is preexisting by construction. preexisting-worse= and new-symbol= partition regressions=. stale= is a FOURTH axis, never gating and never counted in regressions=: rows in the .ripwire_quality_acks ledger whose target no longer applies. api-new-surface= COUNTS the new PUBLIC symbols (never gates, not in regressions=, printed even at zero). register-macro-excluded= is a FLOOR, not a finding: symbols this run excluded from the dead-code kind because their own definition is a registered self-registering test/benchmark macro call. Never gates, never counted in regressions=, printed even at zero (zero: none excluded, not a skipped check). A gating row's next= is the one pasteable follow-up: expand on FILE:NAME, the body to fix (a duplication row names a SET and carries none). bar= on a complexity/verbosity/nesting/params row is the threshold now= is judged against (ccx 15, loc 60, nest 4, params 5). baseline="git-HEAD" means no sidecar existed, so the working tree was auto-compared against the HEAD tree — anything already committed cannot appear. at= is the git commit (plus a dirty marker when the working tree differs) this list was computed at. The registered families are doctest/Catch2 TEST_CASE, GoogleTest TEST/TEST_F/TEST_P, Google Benchmark BENCHMARK, plus any name a .ripwire_config register_macros= line adds; each registers itself through a static initializer the call graph cannot see, so zero in-edges on one is not evidence of anything. Rust #[test] and #[tokio::test] functions count too: the test harness calls them, and no call in the tree names them. declined-call-excluded= is a FLOOR, not a finding: symbols this run kept out of the dead-code kind only because a call the resolver declined to bind (the map's declined=) could have meant them. Never gates; absent at zero. value-ref-excluded= is a FLOOR, not a finding: symbols this run kept out of the dead-code kind only because a table, field, argument or registering decorator holds them as a VALUE (matched by name; it is not a proven call; the callers verb lists the sites; @classmethod-style wrappers do not count), the --dead-code verb's own rule. Never gates; absent at zero. IDENTITY across a rename or a move: a finding is keyed path::scope::name, which a rename would destroy, so the baseline and the .ripwire_quality_acks ledger are both re-filed into the CURRENT tree's identity before either is read, by two EXACT mechanisms — git's own rename record, and equality of a whitespace-and-name-scrubbed body hash — never a similarity heuristic. renames= is how many rename pairs were read (with no ledger, only the uncommitted renames or the A..B range, and the family appears only when one was read), rename_window_commits= how deep the commit window went, acked_by_rename= and acked_by_content= how many of the acked= suppressions each mechanism is responsible for. Three appear ONLY when true, so an absent one is not a silent no: renames_window_truncated= (history is deeper than the window), renames_truncated= (the pair cap was hit), renames_ambiguous= (an ancestor two current symbols both claim — refused rather than guessed). ORIGIN reads the re-filed baseline too, so a regression carried in with a rename is judged preexisting-worse and GATES instead of slipping through as new-symbol. FLOORS, stated because silence here would read as a guarantee: the two clone kinds key on a member-SET hash and are NOT re-filed, so a clone ack still dies on a rename (a clone group itself is held across a file rename git recorded); ORIGIN follows the rename record and an unchanged body (whitespace and its own name aside): a function keeps its identity across a rename or move git recorded no rename for when its body did not change; one whose body also changed reads as new-symbol, or as moved (never gating) when it is over a bar and nearly unchanged. Each sa row carries key= (the ack identity as stored) and why=, which is target-gone (the key names no symbol or group any more) or finding-gone (the target survived, this kind just does not fire on it). sym= and p=path:line name WHICH ack it is, and are present exactly when the key still names a live symbol: on every finding-gone row, on none of the target-gone rows (there is nothing left to name), and on neither clone kind — a clone key hashes a member SET that no single symbol carries, so those rows are unnameable by construction rather than guessed at. Hygiene disclosure only — the ledger file is never auto-edited. ROWS: sym= is the canonical id the finding regressed on; was= and now= carry the before/after value for the numeric kinds; p="path:line" is the locator (root-relative; the first-sorting member for the clone kinds; omitted, never faked, when none resolves). churn= and surface= are per-kind classification facets (short-horizon-churn's self/ambient split; api-surface's new-symbol/contract-change tier). churn= facets never gate alone: the kind gates only on 2+ COMMITTED in-window rewrites of the edited lines. Every row the header's gating= counter counts also carries a gating attribute set to 1 — marked positively, never by the ABSENCE of sev or origin. CLONE ROWS name the whole group rather than one symbol: members= is the member list and tokens= its shared normalized-token count (the same per-group pair the clones verb reports). idiom= names a RECOGNIZED BODY SHAPE every member spells, from a closed set of five (threshold-ladder, switch-name-table, builder-chain, one-statement, call-sequence). idiom= alone changes nothing; a group that ALSO shares no non-keyword identifier between any two members, sits in pairwise-distinct enclosing contexts, and stays under 80 normalized tokens is an idiom COLLISION rather than a copy, and is reported minor instead of gating. Break any one of those and it gates as before, idiom= and all: two bucketing ladders over the SAME enum are a copy. The shape is read off the body's token stream and not a parse tree, so a macro-assembled body classifies as whatever its raw tokens spell — the name is printed so a reader can overrule it. -->
<quality-delta baseline="git-HEAD" regressions="9" minor="1" acked="0" stale="195" preexisting-worse="6" new-symbol="3" gating="5" register-macro-excluded="63" api-new-surface="2" at="6ace381eb+dirty" renames="68" rename_window_commits="400" acked_by_rename="0" acked_by_content="0" renames_window_tr … [line truncated: 65 more bytes on this line]
<r kind="api-surface" sym="src/infra/sortutil.h::rw::sortutil::nonNegativeFloatDescKey" was="1" now="2" surface="contract-change" p="src/infra/sortutil.h:122" gating="1" next="--expand=src/infra/sortutil.h:nonNegativeFloatDescKey"/>
<r kind="complexity" sym="src/infra/sortutil.h::rw::sortutil::lessByScoreDescId" was="1" now="67" bar="15" p="src/infra/sortutil.h:62" gating="1" next="--expand=src/infra/sortutil.h:lessByScoreDescId"/>
<r kind="dead-code" sym="src/infra/sortutil.h::rw::sortutil::nonNegativeFloatAscKeyCopy" origin="new-symbol" p="src/infra/sortutil.h:132"/>
<r kind="dead-code" sym="src/infra/sortutil.h::rw::sortutil::sortScoredIdsWithOptions" origin="new-symbol" p="src/infra/sortutil.h:142"/>
<r kind="duplication" members="src/infra/sortutil.h::rw::sortutil::nonNegativeFloatAscKeyCopy | src/infra/sortutil.h::rw::sortutil::nonNegativeFloatDescKey" tokens="59" p="src/infra/sortutil.h:132" gating="1"/>
<r kind="nesting" sym="src/infra/sortutil.h::rw::sortutil::lessByScoreDescId" was="1" now="6" bar="4" p="src/infra/sortutil.h:62" gating="1" next="--expand=src/infra/sortutil.h:lessByScoreDescId"/>
<r kind="new-clone-of-reused-helper" sym="src/infra/sortutil.h::rw::sortutil::nonNegativeFloatAscKeyCopy | src/infra/sortutil.h::rw::sortutil::nonNegativeFloatDescKey" was="0" now="4" p="src/infra/sortutil.h:132" gating="1" next="--expand=src/infra/sortutil.h:nonNegativeFloatDescKey"/>
<r kind="params" sym="src/infra/sortutil.h::rw::sortutil::sortScoredIdsWithOptions" was="0" now="8" bar="5" origin="new-symbol" p="src/infra/sortutil.h:142"/>
<r kind="verbosity" sym="src/infra/sortutil.h::rw::sortutil::lessByScoreDescId" was="8" now="47" bar="60" sev="minor" p="src/infra/sortutil.h:62"/>
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
<sa kind="api-surface:new-symbol" key="26e3f9a6bff9ea57" why="target-gone"/>
<sa kind="api-surface:new-symbol" key="36e39c7ab0fc1686" why="target-gone"/>
… [177 more display lines; full output is 26339 bytes on 1 raw line(s)]
`````

stderr:

`````
ripwire: no ./.ripwire_quality_baseline — auto-comparing the working tree vs git HEAD (commit the baseline with --quality-baseline to pin it)
ripwire: --quality-delta gating: 5 preexisting-worse major finding(s); first: api-surface src/infra/sortutil.h::rw::sortutil::nonNegativeFloatDescKey at src/infra/sortutil.h:122 (was=1 now=2)
`````

## `./build/ripwire . --quality-delta --json`

*The same findings as JSON (one of the CI/scripting verbs --json supports) — same exit 2 as the XML form.*

**exit code: 2** — **wall time: 41.11s**

`````
{"baseline":"git-HEAD","regressions":9,"minor":1,"acked":0,"stale":195,"preexisting-worse":6,"new-symbol":3,"gating":5,"register-macro-excluded":63,"api-new-surface":2,"at":"6ace381eb+dirty","renames":68,"rename_window_commits":400,"acked_by_rename":0,"acked_by_content":0,"renames_window_truncated": … [line truncated: 240 more bytes on this line]
{"kind":"complexity","sym":"src/infra/sortutil.h::rw::sortutil::lessByScoreDescId","was":1,"now":67,"p":"src/infra/sortutil.h:62","gating":true},
{"kind":"dead-code","sym":"src/infra/sortutil.h::rw::sortutil::nonNegativeFloatAscKeyCopy","p":"src/infra/sortutil.h:132","origin":"new-symbol"},
{"kind":"dead-code","sym":"src/infra/sortutil.h::rw::sortutil::sortScoredIdsWithOptions","p":"src/infra/sortutil.h:142","origin":"new-symbol"},
{"kind":"duplication","members":"src/infra/sortutil.h::rw::sortutil::nonNegativeFloatAscKeyCopy | src/infra/sortutil.h::rw::sortutil::nonNegativeFloatDescKey","tokens":59,"p":"src/infra/sortutil.h:132","gating":true},
{"kind":"nesting","sym":"src/infra/sortutil.h::rw::sortutil::lessByScoreDescId","was":1,"now":6,"p":"src/infra/sortutil.h:62","gating":true},
{"kind":"new-clone-of-reused-helper","sym":"src/infra/sortutil.h::rw::sortutil::nonNegativeFloatAscKeyCopy | src/infra/sortutil.h::rw::sortutil::nonNegativeFloatDescKey","was":0,"now":4,"p":"src/infra/sortutil.h:132","gating":true},
{"kind":"params","sym":"src/infra/sortutil.h::rw::sortutil::sortScoredIdsWithOptions","was":0,"now":8,"p":"src/infra/sortutil.h:142","origin":"new-symbol"},
{"kind":"verbosity","sym":"src/infra/sortutil.h::rw::sortutil::lessByScoreDescId","was":8,"now":47,"p":"src/infra/sortutil.h:62","sev":"minor"}],
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
{"kind":"api-surface:new-symbol","key":"26e3f9a6bff9ea57","why":"target-gone"},
{"kind":"api-surface:new-symbol","key":"36e39c7ab0fc1686","why":"target-gone"},
{"kind":"api-surface:new-symbol","key":"4bce64bd920de0c3","why":"target-gone"},
{"kind":"api-surface:new-symbol","key":"61f0e361ef7dee27","why":"target-gone"},
… [174 more display lines; full output is 19534 bytes on 1 raw line(s)]
`````

stderr:

`````
ripwire: no ./.ripwire_quality_baseline — auto-comparing the working tree vs git HEAD (commit the baseline with --quality-baseline to pin it)
ripwire: --quality-delta gating: 5 preexisting-worse major finding(s); first: api-surface src/infra/sortutil.h::rw::sortutil::nonNegativeFloatDescKey at src/infra/sortutil.h:122 (was=1 now=2)
`````

## `./build/ripwire . --quality-delta --quality-ack --ack-only=zzznope`

*NEW FLAG: --ack-only matching nothing REFUSES rather than falling back to acking everything.*

**exit code: 1** — **wall time: 25.24s**

`````
(empty)
`````

stderr:

`````
ripwire: no ./.ripwire_quality_baseline — auto-comparing the working tree vs git HEAD (commit the baseline with --quality-baseline to pin it)
ripwire: ack provenance backfill — 0 clone row(s) reconstructed from the current tree, 196 re-derived, 39 left UNVERIFIED (their group was not found here — a floor, not proof it is gone), 55 left legacy (member set not found cloning here — a floor, not proof it is gone), 1297 ineligible (no cu … [line truncated: 200 more bytes on this line]
ripwire: --ack-only=zzznope matched none of the 9 finding(s) — nothing written
`````

## `./build/ripwire . --quality-delta --quality-ack --ack-only=api-surface`

*NEW FLAG: ack only the api-surface findings — a per-finding ratchet instead of a rubber stamp.*

**wall time: 25.07s**

`````
(empty)
`````

stderr:

`````
ripwire: no ./.ripwire_quality_baseline — auto-comparing the working tree vs git HEAD (commit the baseline with --quality-baseline to pin it)
ripwire: ack provenance backfill — 0 clone row(s) reconstructed from the current tree, 196 re-derived, 39 left UNVERIFIED (their group was not found here — a floor, not proof it is gone), 55 left legacy (member set not found cloning here — a floor, not proof it is gone), 1297 ineligible (no cu … [line truncated: 200 more bytes on this line]
ripwire: acknowledged 1 of 9 finding(s) (8 left UNACKED by --ack-only, 0 already acked) → ./.ripwire_quality_acks
`````

## `./build/ripwire . --quality-delta`

*Re-run after the partial ack: acked=3, the rest still gate (exit 2).*

**exit code: 2** — **wall time: 30.41s**

`````
<!-- ripwire quality-delta schema=ripwire.quality-delta/v1: only what the change made WORSE vs baseline=: regressions= minor= gating=; <r kind= sym= p= was= now= gating= bar=>, <sa> acked. value-ref-excluded=N: internal functions kept off because a table, field or argument in another function or at file scope holds them (matched by name, not a proven call); a floor. at=: commit+dirty+shallow. next=: the one pasteable follow-up. stale=N: ack ledger rows whose target no longer applies (sa rows); never gating. preexisting-worse=N: regressions on symbols that existed at baseline; they gate when major. new-symbol=N: NEW code; new-symbol rows never gate, except defect-shape format-arity or a ceiling= row. register-macro-excluded=N: symbols skipped: self-registering test/bench macros or Rust #[test]; a floor. declined-call-excluded=N: symbols kept out of dead-code only because a declined call may mean them; a floor. api-new-surface=N: new PUBLIC symbols; a count, never gates, not in regressions=. renames=/rename_window_commits=: git rename pairs read over that many commits, to re-file baseline and acks. acked_by_rename=/acked_by_content=: acked= suppressions matched via git renames / an equal body hash. renames_window_truncated=1: history is deeper than the rename window, older renames unread. acked=N: findings suppressed by the ack ledger, listed as sa rows; never gating. r sev=minor: a small numeric delta, counted in minor=, never gating (absent: major). r origin=new-symbol: a finding on NEW code; moved: its body left another name or file, never gating (absent: preexisting-worse). sa key=/why=: the stale ack's ledger hash / target-gone (names nothing now) or finding-gone (no longer fires). r members=/tokens=: a duplication row's clone group (member ids) / their shared normalized-token count. -->
<quality-delta schema="ripwire.quality-delta/v1" baseline="git-HEAD" regressions="8" minor="1" acked="1" stale="195" preexisting-worse="5" new-symbol="3" gating="4" register-macro-excluded="63" api-new-surface="2" at="6ace381eb+dirty" renames="68" rename_window_commits="400" acked_by_rename="0" acke … [line truncated: 99 more bytes on this line]
<r kind="complexity" sym="src/infra/sortutil.h::rw::sortutil::lessByScoreDescId" was="1" now="67" bar="15" p="src/infra/sortutil.h:62" gating="1" next="--expand=src/infra/sortutil.h:lessByScoreDescId"/>
<r kind="dead-code" sym="src/infra/sortutil.h::rw::sortutil::nonNegativeFloatAscKeyCopy" origin="new-symbol" p="src/infra/sortutil.h:132"/>
<r kind="dead-code" sym="src/infra/sortutil.h::rw::sortutil::sortScoredIdsWithOptions" origin="new-symbol" p="src/infra/sortutil.h:142"/>
<r kind="duplication" members="src/infra/sortutil.h::rw::sortutil::nonNegativeFloatAscKeyCopy | src/infra/sortutil.h::rw::sortutil::nonNegativeFloatDescKey" tokens="59" p="src/infra/sortutil.h:132" gating="1"/>
<r kind="nesting" sym="src/infra/sortutil.h::rw::sortutil::lessByScoreDescId" was="1" now="6" bar="4" p="src/infra/sortutil.h:62" gating="1" next="--expand=src/infra/sortutil.h:lessByScoreDescId"/>
<r kind="new-clone-of-reused-helper" sym="src/infra/sortutil.h::rw::sortutil::nonNegativeFloatAscKeyCopy | src/infra/sortutil.h::rw::sortutil::nonNegativeFloatDescKey" was="0" now="4" p="src/infra/sortutil.h:132" gating="1" next="--expand=src/infra/sortutil.h:nonNegativeFloatDescKey"/>
<r kind="params" sym="src/infra/sortutil.h::rw::sortutil::sortScoredIdsWithOptions" was="0" now="8" bar="5" origin="new-symbol" p="src/infra/sortutil.h:142"/>
<r kind="verbosity" sym="src/infra/sortutil.h::rw::sortutil::lessByScoreDescId" was="8" now="47" bar="60" sev="minor" p="src/infra/sortutil.h:62"/>
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
<sa kind="api-surface:new-symbol" key="26e3f9a6bff9ea57" why="target-gone"/>
<sa kind="api-surface:new-symbol" key="36e39c7ab0fc1686" why="target-gone"/>
<sa kind="api-surface:new-symbol" key="4bce64bd920de0c3" why="target-gone"/>
… [176 more display lines; full output is 20566 bytes on 1 raw line(s)]
`````

stderr:

`````
ripwire: no ./.ripwire_quality_baseline — auto-comparing the working tree vs git HEAD (commit the baseline with --quality-baseline to pin it)
ripwire: --quality-delta gating: 4 preexisting-worse major finding(s); first: complexity src/infra/sortutil.h::rw::sortutil::lessByScoreDescId at src/infra/sortutil.h:62 (was=1 now=67)
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

**wall time: 10.09s**

`````
<!-- ripwire edit-check schema=ripwire.edit-check/v1: sym='s contract NOW vs HEAD: status=unchanged|new-symbol|contract-change; <c n= p= incompatible=1 sites_l=> callers. counts_floor=1: every count is a FLOOR, never a total. graph_ambiguous=/graph_unresolved=: resolver gauge. graph_unindexed=N: N files no grammar could read (the map header's unindexed=); their calls raise neither gauge. est_tokens=: price as emitted (an upper bound under compact). at=: commit+dirty+shallow. root=: p= relative to it. next=: the one pasteable follow-up. defs=N: overloads at this site (same file, scope, name) folded into one contract; params compared by MAX. callers=N: callers of sym= (the c rows' total; a floor). t=: sym='s kind (fn|cls|...). -->
<edit-check schema="ripwire.edit-check/v1" sym="nonNegativeFloatDescKey" t="fn" p="src/infra/sortutil.h:122" status="contract-change" defs="1" params_was="1" params_now="2" public_was="1" public_now="1" defs_was="1" defs_now="1" change="params,broken-callers" callers="4" incompatible="4" at="6ace381 … [line truncated: 161 more bytes on this line]
<c n="benchScores" p="bench/bench_radix_ab.cpp:133" incompatible="1" sites_l="146,152"/>
<c n="benchAdaptive" p="bench/bench_radix_ab.cpp:157" incompatible="1" sites_l="162"/>
<c n="radixSortNonNegativeFloatsDesc" p="src/infra/sortutil.h:151" incompatible="1" sites_l="160"/>
<c n="radixSortByScoreDescId" p="src/infra/sortutil.h:166" incompatible="1" sites_l="226"/>
</edit-check>
`````

## `./build/ripwire . --edit-check=nonNegativeFloatDescKey --legend=full`

*The same verdict under --legend=full: the default's one compact comment (the post-edit reflex at its cheapest) becomes ~5.7 KB of prose legend, every <c incompatible=> row identical.*

**wall time: 5.63s**

`````
<!-- ripwire edit-check: SYM's contract (param count + publicness) NOW vs git HEAD — unchanged/new-symbol/contract-change, or no-baseline when the root has no git HEAD to compare against (not a repository, or no commit yet): then NOTHING is claimed about the contract, and a symbol is never called new for want of a baseline — plus its 1-hop callers. A caller is flagged incompatible="1" when its argument count was reliably counted and NO definition in the folded set could accept it: every one has a FIXED arity that disagrees. A variadic, defaulted or implicit-receiver definition (a Python/Ruby method, whose params counts the self/cls the call site never writes) has no fixed arity and is never flagged. That makes the ARITY half one-sided — a call the compared definitions could accept is never flagged — but it is NOT a proof that the call site binds to THIS definition. Call edges are matched by NAME, so a receiver-qualified call to a same-named callee this tool does not index (a standard-library or third-party method) is measured against the one definition it does index; a clean, compiling tree can therefore carry a nonzero incompatible= with nothing edited at all, and on a widely-shared name it can be most of that name's callers. Read incompatible= as a fact about the tree as it stands — call sites worth OPENING, not a verdict — and status= as a fact about the edit. Warm path hits the qheadsnap/qsnap cache — never a full quality-delta style recompute. defs= is how many DEFINITIONS at this site (same file, same scope, same name — the overload set) are folded into this one contract; a selector matching more than one SITE is refused instead, so defs= only ever counts overloads. params_was and params_now are the MAX over that set on each side (the same MAX the baseline snapshot stores), and publicness is the OR. That MAX has TWO consequences, in opposite directions. It can read like a break and not be one: adding a WIDER overload beside an unchanged one raises params_now with no existing definition altered, so it reports status="contract-change" with incompatible="0" and a def row still carrying the old parameter count — no seen caller breaks. And it can read like safety and not be: REMOVING an overload whose parameter count is BELOW the MAX moves neither number, because the MAX survives on both sides, while the call site that used the removed definition no longer binds. defs_was=/defs_now= is what closes that: the count of definitions sharing this symbol's DEFINITION SITE — same file, same scope, same name — on each side. That is the population the baseline snapshot buckets by, so the two numbers answer the same question and are equal on an unedited tree. A same-named definition in ANOTHER FILE is a different contract and is counted on neither side, so defs_now= agrees with the root's defs= by construction and only defs_was= can move it. status is therefore the join of THREE was-vs-now facts — the params MAX, publicness, and the definition COUNT — and change= names which of them carried it. change= adds broken-callers when a seen caller is also flagged, but never on its own — for the reason stated at the top: incompatible= describes the TREE and status= describes the EDIT, so a headline must not turn on it. RESIDUAL: an overload whose arity changes BELOW the MAX while the COUNT stays the same moves none of the three. The root's incompatible= is the COUNT of flagged callers (a c row's incompatible="1" is the per-caller flag). sites_l= rides on a flagged row only: a c row's p= is where that CALLER is DEFINED, and sites_l= is the ascending LINE list of its call-role reference sites to this name — the lines to open, the same rows the uses verb prints, including the ones whose argument count could not be counted (so sites_l= can be wider than the evidence the flag rests on). Two calls on one line are ONE site. p= is the definition the selector resolved to; when defs is above 1 EVERY folded definition is listed as its own def row (p=, t=, params=), which is what tells a widened single definition apart from an added overload. At defs="1" no def row is emitted: the root's own p=/t= is that definition, and params_now is its parameter count. next= is the one pasteable follow-up: on a contract-change the uses verb on SYM (the call sites), otherwise the test gate on the definition's file. est_tokens= prices THIS document, through the tool's ONE emitted-bytes estimator. counts_floor="1" means every count here is a FLOOR, never a total: edges are extracted from source TEXT by NAME. Missing: dynamic dispatch (virtual/interface/duck-typed), a most-vexing-parse declaration with no call expression, a function-pointer/callback bound to more than one function in scope (reassigned, table-indexed, lambda-bound, or address-taken/reference-bound), and a plain-name binding (fp=handler) whose variable type is not PROVABLY a function pointer (a same-file typedef/declarator; a HEADER typedef is missed; auto/template types are read as unpinned, so KEPT). A macro-generated call site is role="macro" only when its name uniquely names an indexed function-like #define (C-family, t="macro"); a shared name stays a plain call, an unindexed macro is no edge. Read a zero as "none found", never as "none exists". graph_ambiguous=/graph_unresolved= are the whole graph's resolver gauge (calls split over several defs / calls whose in-repo defs were all language-filtered), the map header's ambiguous=/unresolved=. graph_unindexed=N is a third gauge: files no grammar could read (the map header's unindexed=), whose calls raise neither gauge above; absent when zero, and so is this sentence. COUNTING UNIT differs by verb: callers, callees, edit-check, graph-query and pr-context counts are DISTINCT SYMBOLS (repeated calls from one caller, and calls to two overloads, collapse into ONE row; multiplicity survives only in the call graph's edge weight). The reach counts (impact's reaches=, pr-context's dependents=) are the size of a transitive reach SET, each symbol counted once. The uses verb counts call SITES, one row per occurrence — a larger count there for the same symbol is these units agreeing, not disagreeing. The map header's edges= is a unit again different — distinct (caller,callee) PAIRS — and that document carries neither this marker nor this clause. -->
<edit-check sym="nonNegativeFloatDescKey" t="fn" p="src/infra/sortutil.h:122" status="contract-change" defs="1" params_was="1" params_now="2" public_was="1" public_now="1" defs_was="1" defs_now="1" change="params,broken-callers" callers="4" incompatible="4" at="6ace381eb+dirty" graph_ambiguous="3634 … [line truncated: 131 more bytes on this line]
<c n="benchScores" p="bench/bench_radix_ab.cpp:133" incompatible="1" sites_l="146,152"/>
<c n="benchAdaptive" p="bench/bench_radix_ab.cpp:157" incompatible="1" sites_l="162"/>
<c n="radixSortNonNegativeFloatsDesc" p="src/infra/sortutil.h:151" incompatible="1" sites_l="160"/>
<c n="radixSortByScoreDescId" p="src/infra/sortutil.h:166" incompatible="1" sites_l="226"/>
</edit-check>
`````

## `./build/ripwire . --pr-context`

*The review-evidence bundle with an actual changed file.*

**wall time: 13.55s**

`````
<!-- ripwire pr-context schema=ripwire.pr-context/v1: review bundle per changed file vs base=: symbols, callers, blast radius, tests, owners. window: shown= capped= (capped=1 cut). counts_floor=1: every count is a FLOOR, never a total. graph_ambiguous=/graph_unresolved=: resolver gauge. graph_unindexed=N: N files no grammar could read (the map header's unindexed=); their calls raise neither gauge. run_unknown=1: no runner derivable (a guess would be worse). <g n= p=a,b,c>: n runner-less rows with equal attrs as ONE row, paths verbatim; a path holding ',' is never grouped, so p= splits into exactly n=; shown=/total= over these rows counts test FILES. est_tokens=: price as emitted (an upper bound under compact). at=: commit+dirty+shallow. root=: p= relative to it. truncated=: what the trim ladder dropped to fit budget_tokens= (budget-floor-exceeded: still over). direction=: side reviewed: worktree-since-head, head-since-fork or head-since-ref-tip. skipped_mode_only=N: mode-only (chmod) diffs left out of the changed files; renames stay in. trim_level=0-4: trim ladder step taken to fit budget_tokens= (0 none, 4 counts only); raise token-budget. budget_default=1: the default 8000-token budget applied (no token-budget or max-tokens given). commits=N: this file's commits in window=; 0 = the window could not look, not no partners. partners=N: co-change partners NOT in the diff; rows are its top shown= (the cochange verb lists all). dependents=N: distinct symbols transitively calling this file's symbols (reach set, a FLOOR). files_other=N: non-changed files among those reached; the f rows are its top shown=. authors=N: distinct authors of this file (0 = no git data). bf=1: one author holds over 80% of recency-weighted commits (bus-factor risk). files=N: changed files in the diff (shown= of them listed). file symbols=: indexed symbols in that changed file. changed-symbols count= / tests count=: that section's full count (shown= of it listed). tests count=: test files reaching this file (shown= of them listed). impact files=: files holding the transitive callers (dependents=). impactf deps=: transitive callers in that file. test run=: the command that runs that test file (run_unknown=1: none derivable). author email=/share=: a committer of this file / its fraction of the recency-weighted commits. s callers=N: direct callers of that changed symbol; caller rows are its top shown= (callers verb: all). s t= n= / caller t= n=: a changed symbol's / one of its callers' kind and name. -->
<pr-context schema="ripwire.pr-context/v1" base="working-tree" root="." direction="worktree-since-head" files="1" skipped_mode_only="0" budget_tokens="8000" est_tokens="4090" trim_level="0" truncated="none" budget_default="1" at="6ace381eb+dirty" graph_ambiguous="3634" graph_unresolved="20069" graph … [line truncated: 34 more bytes on this line]
<file p="src/infra/sortutil.h" symbols="14">
<impact dependents="1024" files="148" files_other="148" shown="20" capped="1">
<f p="src/graph.h" deps="59"/>
<f p="src/quality.h" deps="43"/>
<f p="src/mcpverbs.h" deps="41"/>
<f p="src/verbs_for.h" deps="33"/>
<f p="src/backhops.h" deps="31"/>
<f p="src/slice.h" deps="31"/>
<f p="src/resolve.h" deps="26"/>
<f p="src/defectshape.h" deps="25"/>
<f p="src/verbs_quality.h" deps="24"/>
<f p="src/verbs_navigate.h" deps="23"/>
<f p="src/crossref.h" deps="21"/>
<f p="src/layout.h" deps="21"/>
<f p="src/forreexport.h" deps="20"/>
<f p="src/main.cpp" deps="20"/>
<f p="src/search.h" deps="20"/>
<f p="src/valuerefindex.h" deps="20"/>
<f p="src/editcheck.h" deps="16"/>
<f p="src/exemplarfamily.h" deps="16"/>
<f p="src/forfilesyms.h" deps="16"/>
<f p="src/shstatus.h" deps="16"/>
</impact>
<tests count="12" shown="12" capped="0">
<test p="test/adaptivecutshapefix/adaptive_cut_shape_test.cpp" run="bash test/adaptivecutshapecheck.sh"/>
<test p="test/cloneband_harness.cpp" run="bash test/clonebandcheck.sh"/>
<test p="test/connectcore_harness.cpp" run="bash test/connectcorecheck.sh"/>
<test p="test/forrowfeatures_unit.cpp" run="bash test/forrowfeaturescheck.sh"/>
… [107 more display lines; full output is 10223 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --map-diff --top-k=5`

*The map re-ranked with a teleport toward the changed file (changed=1 here, not 0).*

**wall time: 8.20s**

`````
<!-- ripwire map-diff schema=ripwire.map-diff/v1: the ranked map anchored at at=: what the diff touched, the map's row vocabulary. est_tokens=: price as emitted (an upper bound under compact). at=: commit+dirty+shallow. root=: p= relative to it. pr_iters=N: PageRank iterations. declined=K: K call sites without edges, including inert Elixir quote sites after unquote/unquote_splicing re-entry. external=K: K calls proven outside the tree, no edge. locality_pinned=K: K calls pinned by locality alone (a guess). extent_suspect_syms=K: K defs failed containment, corpus-wide. macro_blanked_files=K: K files indexed from a macro-blanked re-parse. files=/symbols=: files and symbols indexed; edges= distinct call edges; shown= symbols printed, a merged row counting each def; ambiguous= calls split over several defs, corpus-wide; unresolved= calls with in-tree evidence and no edge (every def language-filtered or unreachable, or binding refused); order= rows by rank (important-first, important-last; (auto:fill) = flipped past a size threshold) or by path (stable). changed=K: K indexed git-changed files seed the PageRank teleport (0: uniform, incl. no git). skipped_oversize=K: K files over a size ceiling, not indexed. unindexed=ext:N: N text files of that extension no grammar reads (6 extensions at most). unindexed_exts=E: E such extensions in all, the list cut. sc=: enclosing scope; the full id is p::sc::n (p= of the row or its <f>) and selectors take it. layer=: built-in arch layer (game|infra|render|math|audio|ai|test) from a dir name in p=; absent if none. f p=: a file; s t= n=: kind, name; c n=: a resolved callee. s k=: rank. -->
<!-- t=modscope=a-file's-MODULE-SCOPE(n=<file-scope>):the-statements-outside-every-named-definition,where-a-top-level-call-and-an-anonymous-callback-body's-calls-live;a-CALLER-never-a-callee(nothing-in-the-source-can-name-it)-with-no-body-to-expand;a-file-with-no-such-call-has-no-such-row -->
<!-- t=type|alias|functype=a-Go-named-type-by-its-written-form:type=a-defined-type-whose-WRITTEN-form-is-not-a-struct/iface/func-literal(type-N-string;type-W-Pair-too,whatever-Pair-is-underneath),alias=type-A=B,functype=type-F-func(...) -->
<!-- t=alias|functype-in-C++-and-.h:alias=using-X=Y(also-templated-or-class-scope)or-namespace-L=lib(defs=X-prints-its-written-target-as-to=),functype=a-typedef-of-a-function-or-function-pointer-type(typedef-void(*F)(int));other-typedefs-read-t=struct -->
<!-- files=4838 symbols=44602 edges=44430 shown=5 est_tokens=1352 ambiguous=3634 unresolved=20069 locality_pinned=14 external=12457 declined=45298 extent_suspect_syms=12 macro_blanked_files=7 changed=1 skipped_oversize=15 unindexed="txt:85,tsv:54,mod:33,xml:33,jsonl:26,scm:25" unindexed_exts=23 order=important-first -->
<r schema="ripwire.map-diff/v1" at="6ace381eb+dirty" root="." est_tokens="1352" pr_iters="31">
<f p="src/infra/sortutil.h" layer="infra">
<s t="fn" n="radixSortByScoreDescId" sc="rw::sortutil" k="0.0914">
<c n="lessByScoreDescId"/>
<c n="radixSortUint32ByKey"/>
<c n="nonNegativeFloatDescKey"/>
</s>
<s t="fn" n="nonNegativeFloatDescKey" sc="rw::sortutil" k="0.0718">
</s>
<s t="fn" n="lessByScoreDescId" sc="rw::sortutil" k="0.0663">
</s>
<s t="fn" n="lessByFromTo" sc="rw::sortutil" k="0.0650">
</s>
</f>
<f p="src/infra/radixSort.h" layer="infra">
<s t="fn" n="sortKeySmall" sc="radix" k="0.0830">
</s>
</f>
</r>
`````

## `./build/ripwire . --clones`

*The duplicated helper the sandbox edit introduced shows up as a clone group.*

**wall time: 2.53s**

`````
<!-- ripwire clones schema=ripwire.clones/v1: similar normalized-token bodies: <group type=2|3 gid= tokens= n= similarity=> of <f n= p=>; dup_loc=/dup_pct=. window: shown= total= capped= has_more= next_offset= offset= limit= (capped=1 cut; next_offset= pastes as offset=). root=: p= relative to it. groups=/type3=: Type-2 and Type-3 group totals over all groups; total= is their sum. exempt_groups=N: groups whose members all sit on fixture/shell-runner paths quality-delta duplication ignores. idiom_groups=/demoted_groups=: groups of one recognized idiom / those quality-delta demotes to minor; floors. clone_groups=N: clusters after merging pairs (rows sharing gid=); a floor under type3_capped=1. total_loc=N: lines of every function body the detector considered; dup_pct= is dup_loc= over it. group exempt=fixture|shell-runner: every member is on such a path; quality-delta duplication ignores it. group idiom=: the recognized shape every member spells: threshold-ladder, switch-name-table, builder-chain, one-statement, call-sequence. -->
<clones schema="ripwire.clones/v1" groups="174" type3="935" exempt_groups="750" idiom_groups="61" demoted_groups="30" clone_groups="464" dup_loc="8959" total_loc="332974" dup_pct="2.7" shown="80" capped="1" total="1109" has_more="1" next_offset="80" offset="0" limit="0" root=".">
<group type="2" gid="50" tokens="338" n="3">
<f n="rw_is_ripwire_call" p="hooks/ripwire-claude-route.sh:187"/>
<f n="rw_is_ripwire_call" p="hooks/ripwire-codex-route.sh:104"/>
<f n="rw_is_ripwire_call" p="hooks/ripwire-nudge.sh:623"/>
</group>
<group type="2" gid="288" tokens="213" n="2" exempt="shell-runner">
<f n="call_sites" p="test/declinecheck.sh:116"/>
<f n="call_sites" p="test/usesselectorcheck.sh:55"/>
</group>
<group type="2" gid="388" tokens="211" n="4" exempt="shell-runner">
<f n="batch_sub" p="test/mcpclidiffcheck.sh:64"/>
<f n="batch_sub" p="test/mcptranchecheck.sh:55"/>
<f n="batch_sub" p="test/mcpw2fixcheck.sh:52"/>
<f n="batch_sub" p="test/mcpw3fixcheck.sh:51"/>
</group>
<group type="2" gid="241" tokens="210" n="2" exempt="shell-runner">
<f n="mcpfor" p="test/anchorhonestycheck.sh:37"/>
<f n="mcpfor" p="test/foranchornscheck.sh:29"/>
</group>
<group type="2" gid="410" tokens="198" n="2" exempt="shell-runner">
<f n="classify" p="test/preludevetocheck.sh:41"/>
<f n="classify" p="test/rustmacropathcheck.sh:53"/>
</group>
<group type="2" gid="283" tokens="175" n="2" exempt="shell-runner">
<f n="mcp" p="test/pathfewestcheck.sh:320"/>
<f n="mcp" p="test/pathroutecheck.sh:468"/>
</group>
<group type="2" gid="49" tokens="163" n="3">
… [309 more display lines; full output is 16374 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --stray-content=zz-orphan`

*CHANGED: a ref with NO merge base with HEAD now reports v="unknown" ok="0" in its own bucket — the absence of an answer, never a claim it is merged. (The sandbox carries a deliberately parentless branch built with `git commit-tree`; a shallow CI clone puts every ref here.)*

**wall time: 8.45s**

`````
<!-- ripwire stray-content schema=ripwire.stray-content/v1: per local ref, lines/symbols NOT in HEAD: <ref ok= v= base= stray=>; v=unknown = no merge base. at=: commit+dirty+shallow. head=: the HEAD commit, bare 9-hex sha (at= adds +dirty). head_ref=: HEAD's branch (HEAD when detached); that branch itself is not scanned. refs=N: local branches scanned (refs/heads only); unmerged + superseded + merged + unknown = refs. blobs=N: distinct git blobs read for the sweep. unmerged=N: refs whose authored work the live line genuinely lacks. superseded=N: refs whose work the live line re-implemented (removed the same base code). merged=N: refs whose work HEAD already has; omitted from the rows. name=: the local branch. tip=: the branch tip commit (9 hex). date=: the tip's committer date, YYYY-MM-DD. files=N: files with stray lines; rows capped at 12, a more element counts the rest (detail=1 lists all). ref superseded=N>: of this ref's stray= lines, those in files the live line re-implemented. unknown=N: refs that could not be analysed (v=unknown, e.g. no merge base); never counted merged. -->
<stray-content schema="ripwire.stray-content/v1" head="6ace381eb" head_ref="integration/train-ge2" refs="1" blobs="0" unmerged="0" superseded="0" merged="0" unknown="1" filter="zz-orphan" at="6ace381eb+dirty">
<ref name="zz-orphan-lane" tip="ca288e70e" date="2026-11-20" base="" ok="0" v="unknown" stray="0" files="0" superseded="0">
</ref>
</stray-content>
`````

stderr:

`````
[math degraded] crossref: no merge-base for ref (shallow clone or unrelated history?) — verdict is unknown, not merged  (crossref.h:1751, std::vector<RefPlumbing> rw::crossref::probeRefBases(const std::string &, const std::vector<RefInfo> &, const std::string &) — logged once per site)
`````

## `./build/ripwire . --stray-content=zz-orphan --plan`

*CHANGED: --plan surfaces those same refs as an <undetermined> row rather than silently dropping them.*

**wall time: 12.02s**

`````
<!-- ripwire landing-plan schema=ripwire.landing-plan/v1: stranded-work landing order across refs, fewest conflicts first. at=: commit+dirty+shallow. -->
<landing-plan schema="ripwire.landing-plan/v1" head="6ace381eb" refs="1" unmerged="0" superseded="0" merged="0" undetermined="1" scouted="0" bounded="0" scout-ok="1" at="6ace381eb+dirty">
<undetermined name="zz-orphan-lane" v="unknown" reason="no merge base with HEAD (shallow clone or unrelated history) — this ref could not be analysed, it is NOT known to be merged; deepen the clone and re-run"/>
</landing-plan>
`````

stderr:

`````
[math degraded] crossref: no merge-base for ref (shallow clone or unrelated history?) — verdict is unknown, not merged  (crossref.h:1751, std::vector<RefPlumbing> rw::crossref::probeRefBases(const std::string &, const std::vector<RefInfo> &, const std::string &) — logged once per site)
`````

## `./build/ripwire . --dmm`

*The DMM scalar on a REAL delta: the sandbox edit grew one unit past the nesting/complexity thresholds and added an 8-parameter one, so dmm is low and the three sub-scores say which property moved.*

**wall time: 13.79s**

`````
<!-- ripwire dmm schema=ripwire.dmm/v1: Delta Maintainability Model base=→target=: dmm= good/(good+bad) units by size_metric=; <p k= dmm= good= bad= d_low= d_high=>. at=: commit+dirty+shallow. available=0: no score at all (dmm=UNAVAILABLE, reason= says why); never read as 1.000 or 0.000. combine=pooled: root dmm= is summed good over summed good+bad of the 3 properties (ripwire's own). low_loc=/low_cx=/low_params=: a unit is LOW risk at or under these lines / cyclomatic / params. base_units=/base_volume=/target_units=/target_volume=: units with a body and their line span per side. -->
<dmm schema="ripwire.dmm/v1" base="6ace381eb32faf95711c423d65f82ffba22046c0" target="working-tree" at="6ace381eb+dirty" available="1" combine="pooled" size_metric="physical-loc" low_loc="15" low_cx="5" low_params="2" dmm="0.142" good="23" bad="139" base_units="24997" base_volume="332920" target_unit … [line truncated: 33 more bytes on this line]
<p k="size" dmm="0.130" good="7" bad="47" d_low="7" d_high="47"/>
<p k="complexity" dmm="0.130" good="7" bad="47" d_low="7" d_high="47"/>
<p k="interfacing" dmm="0.167" good="9" bad="45" d_low="9" d_high="45"/>
</dmm>
`````

## `./build/ripwire . --quality-delta --scope=src/graph.h`

*OWNERSHIP partition for a shared tree: every regression here lives in src/infra/, so under a scope naming src/graph.h they ALL print under <out-of-scope> with a do-not-ack banner and never gate — scoped-out-gating= says how many would have.*

**wall time: 40.69s**

`````
<!-- ripwire quality-delta schema=ripwire.quality-delta/v1: only what the change made WORSE vs baseline=: regressions= minor= gating=; <r kind= sym= p= was= now= gating= bar=>, <sa> acked. value-ref-excluded=N: internal functions kept off because a table, field or argument in another function or at file scope holds them (matched by name, not a proven call); a floor. at=: commit+dirty+shallow. stale=N: ack ledger rows whose target no longer applies (sa rows); never gating. preexisting-worse=N: regressions on symbols that existed at baseline; they gate when major. new-symbol=N: NEW code; new-symbol rows never gate, except defect-shape format-arity or a ceiling= row. register-macro-excluded=N: symbols skipped: self-registering test/bench macros or Rust #[test]; a floor. declined-call-excluded=N: symbols kept out of dead-code only because a declined call may mean them; a floor. api-new-surface=N: new PUBLIC symbols; a count, never gates, not in regressions=. renames=/rename_window_commits=: git rename pairs read over that many commits, to re-file baseline and acks. acked_by_rename=/acked_by_content=: acked= suppressions matched via git renames / an equal body hash. renames_window_truncated=1: history is deeper than the rename window, older renames unread. r surface=: the api-surface tier, new-symbol or contract-change. acked=N: findings suppressed by the ack ledger, listed as sa rows; never gating. r sev=minor: a small numeric delta, counted in minor=, never gating (absent: major). r origin=new-symbol: a finding on NEW code; moved: its body left another name or file, never gating (absent: preexisting-worse). sa key=/why=: the stale ack's ledger hash / target-gone (names nothing now) or finding-gone (no longer fires). r members=/tokens=: a duplication row's clone group (member ids) / their shared normalized-token count. -->
<quality-delta schema="ripwire.quality-delta/v1" baseline="git-HEAD" regressions="0" minor="0" acked="0" stale="195" preexisting-worse="0" new-symbol="0" gating="0" register-macro-excluded="63" api-new-surface="2" at="6ace381eb+dirty" renames="68" rename_window_commits="400" acked_by_rename="0" acke … [line truncated: 156 more bytes on this line]
<out-of-scope n="9" would-gate="4" note="not yours - do not ack: these rows lie outside the scope this run named. They are disclosed rather than hidden, they never gate this exit code, and the ack refuses to write them.">
<r kind="api-surface" sym="src/infra/sortutil.h::rw::sortutil::nonNegativeFloatDescKey" was="1" now="2" surface="contract-change" p="src/infra/sortutil.h:122"/>
<r kind="complexity" sym="src/infra/sortutil.h::rw::sortutil::lessByScoreDescId" was="1" now="67" bar="15" p="src/infra/sortutil.h:62"/>
<r kind="dead-code" sym="src/infra/sortutil.h::rw::sortutil::nonNegativeFloatAscKeyCopy" origin="new-symbol" p="src/infra/sortutil.h:132"/>
<r kind="dead-code" sym="src/infra/sortutil.h::rw::sortutil::sortScoredIdsWithOptions" origin="new-symbol" p="src/infra/sortutil.h:142"/>
<r kind="duplication" members="src/infra/sortutil.h::rw::sortutil::nonNegativeFloatAscKeyCopy | src/infra/sortutil.h::rw::sortutil::nonNegativeFloatDescKey" tokens="59" p="src/infra/sortutil.h:132"/>
<r kind="nesting" sym="src/infra/sortutil.h::rw::sortutil::lessByScoreDescId" was="1" now="6" bar="4" p="src/infra/sortutil.h:62"/>
<r kind="new-clone-of-reused-helper" sym="src/infra/sortutil.h::rw::sortutil::nonNegativeFloatAscKeyCopy | src/infra/sortutil.h::rw::sortutil::nonNegativeFloatDescKey" was="0" now="4" p="src/infra/sortutil.h:132"/>
<r kind="params" sym="src/infra/sortutil.h::rw::sortutil::sortScoredIdsWithOptions" was="0" now="8" bar="5" origin="new-symbol" p="src/infra/sortutil.h:142"/>
<r kind="verbosity" sym="src/infra/sortutil.h::rw::sortutil::lessByScoreDescId" was="8" now="47" bar="60" sev="minor" p="src/infra/sortutil.h:62"/>
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
… [179 more display lines; full output is 20833 bytes on 1 raw line(s)]
`````

stderr:

`````
ripwire: no ./.ripwire_quality_baseline — auto-comparing the working tree vs git HEAD (commit the baseline with --quality-baseline to pin it)
`````

## `./build/ripwire . --quality-delta --quality-ack --scope=src/graph.h --ack-only=api-surface`

*The rubber-stamp guard: an --ack-only that names an OUT-OF-SCOPE row refuses (exit 1) and writes nothing.*

**exit code: 1** — **wall time: 24.47s**

`````
(empty)
`````

stderr:

`````
ripwire: no ./.ripwire_quality_baseline — auto-comparing the working tree vs git HEAD (commit the baseline with --quality-baseline to pin it)
ripwire: --ack-only=api-surface selects 1 finding(s) OUT OF SCOPE for --scope=src/graph.h — refusing, and writing nothing at all:
    api-surface src/infra/sortutil.h::rw::sortutil::nonNegativeFloatDescKey at src/infra/sortutil.h:122
  those rows belong to whoever is editing those paths. Acking them here writes their debt into a committed ledger under YOUR
  reason string, which is how a per-finding ratchet becomes a rubber stamp. Narrow the pattern, or widen the scope if they really are yours.
`````

## `./build/ripwire . --handoff`

*The continuation packet with a REAL diff: verified changed symbols + blast radius + tests-to-run, then the heuristic rows.*

**wall time: 21.99s**

`````
<!-- ripwire handoff schema=ripwire.handoff/v1: continuation packet for the NEXT session: <verified changed= blast_files=>, <tests n=>, <heuristic n= candidates=>, <note>, <doc p=>. window: capped= (capped=1 cut). run_unknown=1: no runner derivable (a guess would be worse). est_tokens=: price as emitted (an upper bound under compact). at=: commit+dirty+shallow. root=: p= relative to it. branch=/subject=: the checked out branch and HEAD commit subject; gitok=0: the git diff probe failed, changed counts are floors. cochange_window=/cochange_commits=: the git window the cochange rows were mined in and the commits it held (0: could not look). doc s=: lexical score of that plan/design doc for the branch+subject query. t run=: the command that runs that test (run_unknown=1: none derivable). -->
<handoff schema="ripwire.handoff/v1" at="6ace381eb+dirty" root="." branch="integration/train-ge2" subject="train ge2 on f79a94e21 (#706): cachefuzzcheck reads the v54 def record; pins follow the composed build" gitok="1" est_tokens="1166">
<verified changed="1" blast_files="148">
<f p="src/infra/sortutil.h">
<s n="svCompare"/>
<s n="svLess"/>
<s n="sortUnique"/>
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
<tests n="12">
<t p="test/verify_radix.cpp" run="bash test/greptiercheck.sh"/>
<t p="test/adaptivecutshapefix/adaptive_cut_shape_test.cpp" run="bash test/adaptivecutshapecheck.sh"/>
<t p="test/connectcore_harness.cpp" run="bash test/connectcorecheck.sh"/>
<t p="test/forrowfeatures_unit.cpp" run="bash test/forrowfeaturescheck.sh"/>
<t p="test/fuzz/readers/readers_domain.cpp" run_unknown="1"/>
<t p="test/verify_csr.cpp" run="bash test/a9disclosurecheck.sh"/>
<t p="test/cloneband_harness.cpp" run="bash test/clonebandcheck.sh"/>
<t p="test/shstatus_harness.cpp" run="bash test/gateexitcheck.sh"/>
<t p="test/type3clone_harness.cpp" run="bash test/type3clonecheck.sh"/>
<t p="test/includeprecise_unit.cpp" run="bash test/includeprecisecheck.sh"/>
… [11 more display lines; full output is 2759 bytes on 1 raw line(s)]
`````

## `./build/ripwire . --note-add="lessByScoreDescId: keep this branch-free — it sits inside the PageRank sort comparator"`

*Pin a field note (write-side memory) to a symbol; committed to .ripwire_notes in the sandbox. The BARE name is resolved through the same resolver the read verbs use and stored as the canonical id — the rewrite is echoed on stderr, because a silent one is not a disclosure.*

**wall time: 7.29s**

`````
src/infra/sortutil.h::rw::sortutil::lessByScoreDescId	2026-11-20	keep this branch-free — it sits inside the PageRank sort comparator	6ace381eb32faf95711c423d65f82ffba22046c0	integration/train-ge2
`````

stderr:

`````
ripwire: --note-add: tip: notes that say "chose X over Y because Z" surface better — consider adding the why
ripwire: --note-add: target 'lessByScoreDescId' canonicalised to 'src/infra/sortutil.h::rw::sortutil::lessByScoreDescId' — that is the id --for/--expand key notes by
`````

## `./build/ripwire . --notes`

*The note is listed under the canonical id, dangling="0" — i.e. it will actually surface. (Before the H1 fix the bare name was stored verbatim and read dangling="1": recorded, and surfaced nowhere.)*

**wall time: 3.39s**

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
<note d="2026-11-20" sha="6ace381" branch="integration/train-ge2">
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

**exit code: 1** — **wall time: 5.64s**

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
ripwire: --note-add: target not found: lessByScoreDescIdd (did you mean 'lessByScoreDescId'?) (note: the lexical definition scan stopped at its budget, 4096 files or 16 MiB, before reading every file, so this miss is not proof the bytes define nothing; --grep=lessByScoreDescIdd lists its text uses)  … [line truncated: 170 more bytes on this line]
`````

## `./build/ripwire . --note-add="src/infra/sortutil.h::rw::sortutil::lessByScoreDescId: chose the flat two-branch compare over the nested ladder because the comparator sits inside the PageRank sort"`

*The same symbol addressed by its CANONICAL id: already canonical, so nothing is rewritten and both notes land on ONE target.*

**wall time: 5.94s**

`````
src/infra/sortutil.h::rw::sortutil::lessByScoreDescId	2026-11-20	chose the flat two-branch compare over the nested ladder because the comparator sits inside the PageRank sort	6ace381eb32faf95711c423d65f82ffba22046c0	integration/train-ge2
`````

## `./build/ripwire . --expand=lessByScoreDescId --top-k=0`

*Both notes riding along with the symbol's body — the <note> elements follow the body, past the display cut, so they are extracted below.*

**wall time: 4.10s**

`````
<ctx schema="ripwire.expand/v1" root="." est_tokens="804">
<!-- ripwire expand schema=ripwire.expand/v1: full bodies: <bodies shown= total= capped=> of <b t= l= p= n= sibs= sibs_total= sibs_capped= inc=>; <calls>
<c n= l= p=> resolved callees (p= when not the b's file). window: shown= total= capped= (capped=1 cut). est_tokens=: price as emitted (an upper bound under compact). root=: p= relative to it. inc_total=N: the file's true include/import count; inc= lists the first 24, inc_capped=1 when cut. -->
<bodies shown="1" total="1" capped="0">
<b t="fn" l="62" p="src/infra/sortutil.h" n="lessByScoreDescId" sibs="svCompare,svLess,sortUnique,radixSortUint32ByKey,nonNegativeFloatDescKey,nonNegativeFloatAscKeyCopy,sortScoredIdsWithOptions,radixSortNonNegativeFloatsDesc,radixSortByScoreDescId,radixSortByScoreDescId,lessByFromTo,radixSortByFrom … [line truncated: 145 more bytes on this line]
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
… [22 more display lines; full output is 3086 bytes on 47 raw line(s)]
`````

The <note> element on the same output — past the 30-line display cut above:

`````
<note d="2026-11-20" sha="6ace381" branch="integration/train-ge2">
<![CDATA[chose the flat two-branch compare over the nested ladder because the comparator sits inside the PageRank sort]]>
</note>
<note d="2026-11-20" sha="6ace381" branch="integration/train-ge2">
<![CDATA[keep this branch-free — it sits inside the PageRank sort comparator]]>
</note>
`````

## `./build/ripwire . --replace-symbol-body=lessByScoreDescId --edit-payload=<scratch>/aux/empty_payload.h`

*An EMPTY payload refuses — it never implies deletion.*

**exit code: 1** — **wall time: 1.35s**

`````
(empty)
`````

stderr:

`````
ripwire: --edit-payload is empty; empty never means delete
`````

## `./build/ripwire . --replace-symbol-body=lessByScoreDescId --edit-payload=<scratch>/aux/payload_lessByScoreDescId.h`

*Whole-symbol replace without a whole-file read: the payload is the ORIGINAL flat body, so this edit undoes the sandbox's deep-nesting regression. The receipt's span is the POST-edit byte range; replaced_bytes counts the old bytes overwritten.*

**wall time: 25.97s**

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
{"applied":"replace_symbol_body","symbol":"lessByScoreDescId","file":"src/infra/sortutil.h","span":{"start":2923,"end":3136},"lines":{"start":62,"end":69},"replaced_bytes":1718,"old_file_bytes":10679,"new_file_bytes":9174,"file_eol":"lf","eol_normalized":false,"trailing_newline_folded":true,"separat … [line truncated: 725 more bytes on this line]
"graph_ambiguous":3634,"graph_unresolved":20069,"graph_unindexed":313,"counts_floor":true},"tests_to_run":[{"p":"test/verify_radix.cpp","hops":1,"run":"bash test/greptiercheck.sh"},
{"p":"test/adaptivecutshapefix/adaptive_cut_shape_test.cpp","hops":2,"run":"bash test/adaptivecutshapecheck.sh"},
{"p":"test/connectcore_harness.cpp","hops":2,"run":"bash test/connectcorecheck.sh"},
{"p":"test/forrowfeatures_unit.cpp","hops":2,"run":"bash test/forrowfeaturescheck.sh"},
{"p":"test/fuzz/readers/readers_domain.cpp","hops":2,"run_unknown":true},
{"p":"test/verify_csr.cpp","hops":2,"run":"bash test/a9disclosurecheck.sh"},
{"p":"test/cloneband_harness.cpp","hops":3,"run":"bash test/clonebandcheck.sh"},
{"p":"test/shstatus_harness.cpp","hops":3,"run":"bash test/gateexitcheck.sh"},
{"p":"test/type3clone_harness.cpp","hops":3,"run":"bash test/type3clonecheck.sh"},
{"p":"test/includeprecise_unit.cpp","hops":4,"run":"bash test/includeprecisecheck.sh"},
{"p":"test/rustimport_unit.cpp","hops":4,"run":"bash test/rustimportprecisecheck.sh"},
{"p":"test/fuzz/readers/readers_light.cpp","hops":5,"run_unknown":true}],
"order":"evidence","partners":0,"run_first":1,"tests":12,"script_gates_unmodelled":946,"graph_ambiguous":3634,"graph_unresolved":20069,"graph_unindexed":313,"counts_floor":true,"next":"bash test/greptiercheck.sh"}
`````

stderr:

`````
ripwire: cache <tmp>: over its 2048 MiB budget — evicted 102 blob(s) of other roots or other ripwire builds (this build's blobs for this root are kept)
ripwire edit: applied atomically; receipt carries region, blob_sha, edit_check, tests_to_run; next: bash test/greptiercheck.sh
`````

## `./build/ripwire . --edit-check=lessByScoreDescId`

*The closed loop: contract unchanged (same params, same publicness) after the replace — nothing provably incompatible.*

**wall time: 9.39s**

`````
<!-- ripwire edit-check schema=ripwire.edit-check/v1: sym='s contract NOW vs HEAD: status=unchanged|new-symbol|contract-change; <c n= p= incompatible=1 sites_l=> callers. counts_floor=1: every count is a FLOOR, never a total. graph_ambiguous=/graph_unresolved=: resolver gauge. graph_unindexed=N: N files no grammar could read (the map header's unindexed=); their calls raise neither gauge. est_tokens=: price as emitted (an upper bound under compact). at=: commit+dirty+shallow. root=: p= relative to it. next=: the one pasteable follow-up. defs=N: overloads at this site (same file, scope, name) folded into one contract; params compared by MAX. callers=N: callers of sym= (the c rows' total; a floor). t=: sym='s kind (fn|cls|...). -->
<edit-check schema="ripwire.edit-check/v1" sym="lessByScoreDescId" t="fn" p="src/infra/sortutil.h:62" status="unchanged" defs="1" callers="4" incompatible="0" at="6ace381eb+dirty" graph_ambiguous="3634" graph_unresolved="20069" graph_unindexed="313" counts_floor="1" root="." next="--test-gate=src/in … [line truncated: 33 more bytes on this line]
<note d="2026-11-20" sha="6ace381" branch="integration/train-ge2">
<![CDATA[chose the flat two-branch compare over the nested ladder because the comparator sits inside the PageRank sort]]>
</note>
<note d="2026-11-20" sha="6ace381" branch="integration/train-ge2">
<![CDATA[keep this branch-free — it sits inside the PageRank sort comparator]]>
</note>
<c n="benchScores" p="bench/bench_radix_ab.cpp:133"/>
<c n="benchScoreCase" p="bench/bench_sort_large.cpp:230"/>
<c n="radixSortByScoreDescId" p="src/infra/sortutil.h:127"/>
<c n="verifyRipwireWrappers" p="test/verify_radix.cpp:249"/>
</edit-check>
`````

## `./build/ripwire . --insert-after-symbol=lessByScoreDescId --edit-payload=<scratch>/aux/payload_note.h`

*Insert immediately AFTER one uniquely-resolved definition; replaced_bytes=0 because the insert verbs never overwrite. The receipt carries the folded post-edit verification (lines=, edit_check, tests_to_run) so the loop closes in one call.*

**wall time: 16.34s**

`````
{"applied":"insert_after_symbol","symbol":"lessByScoreDescId","file":"src/infra/sortutil.h","span":{"start":3136,"end":3224},"lines":{"start":69,"end":71},"replaced_bytes":0,"old_file_bytes":9174,"new_file_bytes":9262,"file_eol":"lf","eol_normalized":false,"trailing_newline_folded":true,"separator_p … [line truncated: 650 more bytes on this line]
"graph_ambiguous":3634,"graph_unresolved":20069,"graph_unindexed":313,"counts_floor":true},"tests_to_run":[{"p":"test/verify_radix.cpp","hops":1,"run":"bash test/greptiercheck.sh"},
{"p":"test/adaptivecutshapefix/adaptive_cut_shape_test.cpp","hops":2,"run":"bash test/adaptivecutshapecheck.sh"},
{"p":"test/connectcore_harness.cpp","hops":2,"run":"bash test/connectcorecheck.sh"},
{"p":"test/forrowfeatures_unit.cpp","hops":2,"run":"bash test/forrowfeaturescheck.sh"},
{"p":"test/fuzz/readers/readers_domain.cpp","hops":2,"run_unknown":true},
{"p":"test/verify_csr.cpp","hops":2,"run":"bash test/a9disclosurecheck.sh"},
{"p":"test/cloneband_harness.cpp","hops":3,"run":"bash test/clonebandcheck.sh"},
{"p":"test/shstatus_harness.cpp","hops":3,"run":"bash test/gateexitcheck.sh"},
{"p":"test/type3clone_harness.cpp","hops":3,"run":"bash test/type3clonecheck.sh"},
{"p":"test/includeprecise_unit.cpp","hops":4,"run":"bash test/includeprecisecheck.sh"},
{"p":"test/rustimport_unit.cpp","hops":4,"run":"bash test/rustimportprecisecheck.sh"},
{"p":"test/fuzz/readers/readers_light.cpp","hops":5,"run_unknown":true}],
"order":"evidence","partners":0,"run_first":1,"tests":12,"script_gates_unmodelled":946,"graph_ambiguous":3634,"graph_unresolved":20069,"graph_unindexed":313,"counts_floor":true,"next":"bash test/greptiercheck.sh"}
`````

stderr:

`````
ripwire edit: applied atomically; receipt carries region, blob_sha, edit_check, tests_to_run; next: bash test/greptiercheck.sh
`````

## `./build/ripwire . --insert-after-symbol=lessByScoreDescId --edit-payload=<scratch>/aux/payload_note.h --no-post-check`

*The opt-out: the same insert with the folded verification skipped — lines= still rides (it is free), edit_check/tests_to_run do not, and the two pasteable commands stay on stderr.*

**wall time: 6.57s**

`````
{"applied":"insert_after_symbol","symbol":"lessByScoreDescId","file":"src/infra/sortutil.h","span":{"start":3136,"end":3224},"lines":{"start":69,"end":71},"replaced_bytes":0,"old_file_bytes":9262,"new_file_bytes":9350,"file_eol":"lf","eol_normalized":false,"trailing_newline_folded":true,"separator_p … [line truncated: 570 more bytes on this line]
`````

stderr:

`````
ripwire edit: applied atomically; receipt carries region, blob_sha (post-check skipped); next: --edit-check=src/infra/sortutil.h:lessByScoreDescId
`````

## `./build/ripwire . --insert-before-symbol=nonNegativeFloatDescKey --edit-payload=<scratch>/aux/payload_note.h --edit-target-file=src/infra/sortutil.h`

*Insert BEFORE, with --edit-target-file pinning which same-named definition (here unambiguous — the disambiguator is simply honoured).*

**wall time: 10.39s**

`````
{"applied":"insert_before_symbol","symbol":"nonNegativeFloatDescKey","file":"src/infra/sortutil.h","span":{"start":3656,"end":3744},"lines":{"start":87,"end":88},"replaced_bytes":0,"old_file_bytes":9350,"new_file_bytes":9438,"file_eol":"lf","eol_normalized":false,"trailing_newline_folded":false,"sep … [line truncated: 753 more bytes on this line]
{"n":"benchAdaptive","p":"bench/bench_radix_ab.cpp:157","l":[162]},
{"n":"radixSortNonNegativeFloatsDesc","p":"src/infra/sortutil.h:118","l":[127]},
{"n":"radixSortByScoreDescId","p":"src/infra/sortutil.h:133","l":[193]}],
"graph_ambiguous":3634,"graph_unresolved":20069,"graph_unindexed":313,"counts_floor":true},"tests_to_run":[{"p":"test/verify_radix.cpp","hops":1,"run":"bash test/greptiercheck.sh"},
{"p":"test/adaptivecutshapefix/adaptive_cut_shape_test.cpp","hops":2,"run":"bash test/adaptivecutshapecheck.sh"},
{"p":"test/connectcore_harness.cpp","hops":2,"run":"bash test/connectcorecheck.sh"},
{"p":"test/forrowfeatures_unit.cpp","hops":2,"run":"bash test/forrowfeaturescheck.sh"},
{"p":"test/fuzz/readers/readers_domain.cpp","hops":2,"run_unknown":true},
{"p":"test/verify_csr.cpp","hops":2,"run":"bash test/a9disclosurecheck.sh"},
{"p":"test/cloneband_harness.cpp","hops":3,"run":"bash test/clonebandcheck.sh"},
{"p":"test/shstatus_harness.cpp","hops":3,"run":"bash test/gateexitcheck.sh"},
{"p":"test/type3clone_harness.cpp","hops":3,"run":"bash test/type3clonecheck.sh"},
{"p":"test/includeprecise_unit.cpp","hops":4,"run":"bash test/includeprecisecheck.sh"},
{"p":"test/rustimport_unit.cpp","hops":4,"run":"bash test/rustimportprecisecheck.sh"},
{"p":"test/fuzz/readers/readers_light.cpp","hops":5,"run_unknown":true}],
"order":"evidence","partners":0,"run_first":1,"tests":12,"script_gates_unmodelled":946,"graph_ambiguous":3634,"graph_unresolved":20069,"graph_unindexed":313,"counts_floor":true,"next":"--uses=src/infra/sortutil.h:nonNegativeFloatDescKey"}
`````

stderr:

`````
ripwire edit: applied atomically; receipt carries region, blob_sha, edit_check, tests_to_run; next: --uses=src/infra/sortutil.h:nonNegativeFloatDescKey
`````

## `./build/ripwire . --replace-symbol-body=DoesNotExist --edit-payload=<scratch>/aux/payload_note.h`

*An unknown TARGET refuses and leaves every file byte-identical.*

**exit code: 1** — **wall time: 4.32s**

`````
(empty)
`````

stderr:

`````
ripwire: --replace-symbol-body: symbol 'DoesNotExist' not found
`````

## `./build/ripwire . --edit-plan=<scratch>/aux/edit_plan.json --dry-run`

*A versioned multi-edit TRANSACTION preflighted without writing: the receipt shows what each op would read and touch.*

**wall time: 4.53s**

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
{"schema":"ripwire.edit-plan/v1","mode":"dry-run","edits":1,"files":1,"callers_union":4,"graph_ambiguous":3634,"graph_unresolved":20069,"graph_unindexed":313,"counts_floor":true,"atomic_scope":"per-file","rollback_on_write_error":true,"recheck_before_each_write":true,"multifile_crash_atomic":false," … [line truncated: 400 more bytes on this line]
`````

## `./build/ripwire . --edit-plan=<scratch>/aux/edit_plan.json --apply`

*The same plan committed: per-file locks, re-verify-before-write, atomic rename, rollback on a later failure.*

**wall time: 10.26s**

`````
{"schema":"ripwire.edit-plan/v1","mode":"apply","edits":1,"files":1,"callers_union":4,"graph_ambiguous":3634,"graph_unresolved":20069,"graph_unindexed":313,"counts_floor":true,"applied":1,"atomic_files":1,"atomic_scope":"per-file","rollback_on_write_error":true,"recheck_before_each_write":true,"mult … [line truncated: 584 more bytes on this line]
{"n":"benchAdaptive","p":"bench/bench_radix_ab.cpp:157","l":[162]},
{"n":"radixSortNonNegativeFloatsDesc","p":"src/infra/sortutil.h:120","l":[129]},
{"n":"radixSortByScoreDescId","p":"src/infra/sortutil.h:135","l":[195]}],
"graph_ambiguous":3634,"graph_unresolved":20069,"graph_unindexed":313,"counts_floor":true}}]}
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

**exit code: 2** — **wall time: 28.75s**

`````
<!-- ripwire quality-delta schema=ripwire.quality-delta/v1: only what the change made WORSE vs baseline=: regressions= minor= gating=; <r kind= sym= p= was= now= gating= bar=>, <sa> acked. value-ref-excluded=N: internal functions kept off because a table, field or argument in another function or at file scope holds them (matched by name, not a proven call); a floor. at=: commit+dirty+shallow. next=: the one pasteable follow-up. stale=N: ack ledger rows whose target no longer applies (sa rows); never gating. preexisting-worse=N: regressions on symbols that existed at baseline; they gate when major. new-symbol=N: NEW code; new-symbol rows never gate, except defect-shape format-arity or a ceiling= row. register-macro-excluded=N: symbols skipped: self-registering test/bench macros or Rust #[test]; a floor. declined-call-excluded=N: symbols kept out of dead-code only because a declined call may mean them; a floor. api-new-surface=N: new PUBLIC symbols; a count, never gates, not in regressions=. renames=/rename_window_commits=: git rename pairs read over that many commits, to re-file baseline and acks. acked_by_rename=/acked_by_content=: acked= suppressions matched via git renames / an equal body hash. renames_window_truncated=1: history is deeper than the rename window, older renames unread. acked=N: findings suppressed by the ack ledger, listed as sa rows; never gating. r origin=new-symbol: a finding on NEW code; moved: its body left another name or file, never gating (absent: preexisting-worse). sa key=/why=: the stale ack's ledger hash / target-gone (names nothing now) or finding-gone (no longer fires). r members=/tokens=: a duplication row's clone group (member ids) / their shared normalized-token count. -->
<quality-delta schema="ripwire.quality-delta/v1" baseline="git-HEAD" regressions="5" minor="0" acked="1" stale="195" preexisting-worse="2" new-symbol="3" gating="2" register-macro-excluded="63" api-new-surface="2" at="6ace381eb+dirty" renames="68" rename_window_commits="400" acked_by_rename="0" acke … [line truncated: 99 more bytes on this line]
<r kind="dead-code" sym="src/infra/sortutil.h::rw::sortutil::nonNegativeFloatAscKeyCopy" origin="new-symbol" p="src/infra/sortutil.h:101"/>
<r kind="dead-code" sym="src/infra/sortutil.h::rw::sortutil::sortScoredIdsWithOptions" origin="new-symbol" p="src/infra/sortutil.h:111"/>
<r kind="duplication" members="src/infra/sortutil.h::rw::sortutil::nonNegativeFloatAscKeyCopy | src/infra/sortutil.h::rw::sortutil::nonNegativeFloatDescKey" tokens="59" p="src/infra/sortutil.h:101" gating="1"/>
<r kind="new-clone-of-reused-helper" sym="src/infra/sortutil.h::rw::sortutil::nonNegativeFloatAscKeyCopy | src/infra/sortutil.h::rw::sortutil::nonNegativeFloatDescKey" was="0" now="4" p="src/infra/sortutil.h:101" gating="1" next="--expand=src/infra/sortutil.h:nonNegativeFloatDescKey"/>
<r kind="params" sym="src/infra/sortutil.h::rw::sortutil::sortScoredIdsWithOptions" was="0" now="8" bar="5" origin="new-symbol" p="src/infra/sortutil.h:111"/>
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
<sa kind="api-surface:new-symbol" key="26e3f9a6bff9ea57" why="target-gone"/>
<sa kind="api-surface:new-symbol" key="36e39c7ab0fc1686" why="target-gone"/>
<sa kind="api-surface:new-symbol" key="4bce64bd920de0c3" why="target-gone"/>
<sa kind="api-surface:new-symbol" key="61f0e361ef7dee27" why="target-gone"/>
<sa kind="api-surface:new-symbol" key="79625906f9f71ad0" why="target-gone"/>
<sa kind="api-surface:new-symbol" key="8ecb190954dce18a" why="target-gone"/>
… [173 more display lines; full output is 19935 bytes on 1 raw line(s)]
`````

stderr:

`````
ripwire: no ./.ripwire_quality_baseline — auto-comparing the working tree vs git HEAD (commit the baseline with --quality-baseline to pin it)
ripwire: --quality-delta gating: 2 preexisting-worse major finding(s); first: duplication src/infra/sortutil.h::rw::sortutil::nonNegativeFloatAscKeyCopy | src/infra/sortutil.h::rw::sortutil::nonNegativeFloatDescKey at src/infra/sortutil.h:101 (was=0 now=59)
`````

## `./build/ripwire . --quality-baseline`

*REFUSES, exit 1: this sandbox tree is already regressed, and pinning here would swallow that debt into the floor so every later delta read clean. It names how many gating findings it would absorb, the first of them, and the way forward.*

**exit code: 1** — **wall time: 35.27s**

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

**wall time: 45.76s**

`````
(empty)
`````

stderr:

`````
ripwire: --quality-baseline --allow-dirty: pinned with 2 gating finding(s) ABSORBED into the floor (stamped in the sidecar; every --quality-delta against it carries baseline_absorbed="2")
ripwire: wrote ./.ripwire_quality_baseline (snapshot of 42445 per-symbol rows, 44603 indexed symbols total)
`````

Artifact written:

`````
 8879937 .ripwire_quality_baseline
# ripwire quality baseline v6 — regenerate with --quality-baseline; do not hand-edit
producer 9460e9fde0f124e9ad0165a82cd5d3705866099cd7a25d7454aff2665ecd6244
head 6ace381eb32faf95711c423d65f82ffba22046c0
dirty 1
absorbed 2
ccx 67c15011ee8b 0
ccx d19d7c13cbc7 2
ccx 1f7edbff929e5 12
ccx 6a732f6699b
`````

## `./build/ripwire . --quality-delta`

*Against that sidecar the same tree reads regressions=0 — but baseline_absorbed= is on the root, so this green means clean SINCE THE PIN, never clean. A baseline is a floor YOU chose, and it belongs BEFORE the change.*

**wall time: 29.50s**

`````
<!-- ripwire quality-delta schema=ripwire.quality-delta/v1: only what the change made WORSE vs baseline=: regressions= minor= gating=; <r kind= sym= p= was= now= gating= bar=>, <sa> acked. value-ref-excluded=N: internal functions kept off because a table, field or argument in another function or at file scope holds them (matched by name, not a proven call); a floor. at=: commit+dirty+shallow. stale=N: ack ledger rows whose target no longer applies (sa rows); never gating. stale_by_kind=: stale= split by ack kind (kind:N,...); the sa rows are collapsed. stale_next=: the call printing the sa rows and the full header. preexisting-worse=N: regressions on symbols that existed at baseline; they gate when major. new-symbol=N: NEW code; new-symbol rows never gate, except defect-shape format-arity or a ceiling= row. register-macro-excluded=N: symbols skipped: self-registering test/bench macros or Rust #[test]; a floor. declined-call-excluded=N: symbols kept out of dead-code only because a declined call may mean them; a floor. api-new-surface=N: new PUBLIC symbols; a count, never gates, not in regressions=. renames=/rename_window_commits=: git rename pairs read over that many commits, to re-file baseline and acks. acked_by_rename=/acked_by_content=: acked= suppressions matched via git renames / an equal body hash. renames_window_truncated=1: history is deeper than the rename window, older renames unread. acked=N: findings suppressed by the ack ledger, listed as sa rows; never gating. -->
<quality-delta schema="ripwire.quality-delta/v1" baseline="sidecar" regressions="0" minor="0" acked="0" stale="195" preexisting-worse="0" new-symbol="0" gating="0" register-macro-excluded="63" api-new-surface="0" at="6ace381eb+dirty" renames="68" rename_window_commits="400" acked_by_rename="0" acked … [line truncated: 319 more bytes on this line]
</quality-delta>
`````


---

# the MCP dialect — the same verbs over stdio JSON-RPC (one-shot exchange, not a persistent server)

## `printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize"}' '{"jsonrpc":"2.0","id":2,"method":"tools/list"}' | ./build/ripwire --mcp`

*initialize + tools/list: the manifest an agent host loads at session start — every verb's name, description and input schema.*

`````
{"jsonrpc":"2.0","id":1,"result":{"protocolVersion":"2025-11-25","serverInfo":{"name":"ripwire","version":"0.6.10-dev.139+g6ace381eb"},"capabilities":{"tools":{},"resources":{}},"instructions":"Map before reading files. Start a new task with explore; use from_trace for an error; use impact plus uses … [line truncated: 760 more bytes on this line]
{"jsonrpc":"2.0","id":2,"result":{"tools":[{"name":"analyze","description":"Architecture map for a directory: signatures and the call graph for the top symbols. Use when landing cold in a repo or subdir, before reading files; for a task-scoped inventory use 'for', for one symbol's neighborhood find_ … [line truncated: 742 more bytes on this line]
{"name":"rank_by","description":"The SAME architecture map 'analyze' serves, ranked by a different signal instead of plain PageRank. rank_by = pagerank (default, omit it — the CLI's own unbiased --rank-by=pagerank; 'analyze' can rank differently on a tree with uncommitted changes, where it biases  … [line truncated: 1077 more bytes on this line]
{"name":"find_symbol","description":"A symbol's 1-hop neighborhood: the symbol (with a fetch_body handle) plus direct callers (calledBy) and callees (calls). Full transitive reach: 'impact'. Read/write/import sites, not just calls: 'uses'. JSON {symbol, calledBy, calls, defs, count, hop_tested, hop_ … [line truncated: 1181 more bytes on this line]
{"name":"find_referencing_symbols","description":"Direct (1-hop) callers of a symbol, each with a fetch_body handle. For the full transitive blast radius use 'impact', for read/write/import sites 'uses'. JSON {symbol, calledBy, defs, count, hop_tested, hop_untested, declined_calls, counts_floor}; ca … [line truncated: 945 more bytes on this line]
{"name":"grep","description":"Trigram literal search; each hit annotated with its enclosing symbol (which function/class it is in). Hits carry text; enclosing rows a fetch_body handle. pattern = the literal; in=any lifts the span tiering (default: tightest non-empty tier; rest rides as suppressed_co … [line truncated: 837 more bytes on this line]
{"name":"cochange","description":"Files that historically change together with this file — the co-edit partners. Fowler's Shotgun Surgery as change coupling. dep_capable=false (sh/md/json/binary) or no_file_edges (Go, Java: imports not resolved) makes surprising undefined, not a finding. file = th … [line truncated: 705 more bytes on this line]
{"name":"memory_recall","description":"Most relevant memory notes / docs for a task, full text — the few that matter, not the whole corpus. path = docs/memory dir; task = what you're working on; top_k = docs to return, 1..1000 (default 6), refused outside that band, never clamped; budget_tokens =  … [line truncated: 790 more bytes on this line]
{"name":"situational_awareness","description":"The 5 things to know about a diff, as JSON: blast_radius, tests_to_run, forgotten (usual co-change partners missing from this diff), hotspot_alert, modules_touched. forgotten = the Shotgun Surgery check. diff/files optional — defaults to 'git diff HEA … [line truncated: 1296 more bytes on this line]
{"name":"mentions","description":"Docs (markdown plans/designs) that name a code symbol in a backtick. symbol = the code symbol name; limit/offset page the files. An @FILE:LINE line-seed rebinds to the innermost definition enclosing that line and answers for it, disclosing the rebound name as 'sym'  … [line truncated: 625 more bytes on this line]
{"name":"for","description":"Task-lens ranked, signatures-only inventory of the building blocks most relevant to a task (cx=complexity, in=reuse-count). task = the task in plain words; budget_tokens = an optional soft row target (the CLI --for --token-budget). The header carries route= (which ranker … [line truncated: 1061 more bytes on this line]
{"name":"lego","description":"Interface-to-impls view for ONE named interface/base: its method contract plus EVERY implementor (own-language only), each with file path. Use when implementing against a KNOWN interface (contrast 'for', which sprays top interfaces for a task). type = interface/base nam … [line truncated: 841 more bytes on this line]
{"name":"owners","description":"Bus-factor: recency-weighted (6-month half-life) author ownership per file. symbol = optional, restricts to the file that defines it; limit/offset page the rows. at= is the commit these numbers were computed at (+dirty = the working tree differed). An @FILE:LINE line- … [line truncated: 879 more bytes on this line]
{"name":"replace_symbol_body","description":"Replace a symbol's ENTIRE definition (signature through closing brace) with new_body — splices over the full def span, preserving every byte outside it verbatim; new_body must be a complete, well-formed definition. One trailing newline folds (trailing_n … [line truncated: 1323 more bytes on this line]
{"name":"insert_before_symbol","description":"Insert text immediately BEFORE a symbol's definition (its first byte); padded to the file's own blank-line seam (separator_padded=N). Same refusal contract as replace_symbol_body (not found / ambiguous / stale index / symlink / concurrent write, file unc … [line truncated: 877 more bytes on this line]
{"name":"insert_after_symbol","description":"Insert text immediately AFTER a symbol's definition (past its final byte, which is preserved exactly); padded to the file's own blank-line seam (separator_padded=N); one trailing newline folds (trailing_newline_folded). Same refusal contract as replace_sy … [line truncated: 878 more bytes on this line]
{"name":"fetch_body","description":"Full (or partial-range) source of a symbol's definition, addressed by the stable `handle` a read verb attached to it (bodies on request, not by default). start_line/end_line are optional, 1-based, INCLUSIVE and BODY-RELATIVE (line 1 = the def's first line), clampe … [line truncated: 1049 more bytes on this line]
{"name":"exemplar","description":"BEFORE writing a function / method / class / struct / interface / variable, get the repo's single best-in-class instance of that kind to imitate — signature AND full body. chosen by ROLE, NEVER by text similarity to your task: candidates are first filtered to cogn … [line truncated: 1372 more bytes on this line]
{"name":"quality_delta","description":"Your PR self-check, run every time you think a change is DONE — pairs with the CLI-only --test-gate (names the tests to run + the untested blast radius; not MCP-exposed) to form the two-step pre-PR gate. Reports ONLY what your tree made WORSE vs baseline, acr … [line truncated: 870 more bytes on this line]
{"name":"quality_baseline","description":"PIN the quality floor: writes .ripwire_quality_baseline stamped with the current git HEAD sha, snapshotting complexity / duplication / dead-code / API surface. Call once at the start of non-trivial work, then quality_delta compares against this pinned floor  … [line truncated: 445 more bytes on this line]
{"name":"impact","description":"IS IT SAFE TO CHANGE X? — the TRANSITIVE blast radius of a symbol via calls, nearest first (d= hop depth), then PageRank. Use before modifying or deleting a symbol; it beats find_referencing_symbols (direct callers only), and 'uses' catches the read/write/import sit … [line truncated: 1325 more bytes on this line]
{"name":"uses","description":"The STATICALLY RESOLVABLE use-sites of a symbol, not just calls: role (call | read | write | import | extends), file:line, and enclosing symbol. Use to see the footprint before renaming or changing a name — find_referencing_symbols and impact follow only calls. extern … [line truncated: 1146 more bytes on this line]
{"name":"affected","description":"WHICH TESTS TO RUN for a change — test files that transitively reach the changed files/symbols, ranked by evidence (edited > partner-named > hop distance). files = changed files and/or symbols, comma-separated: each item is tried as an indexed PATH pattern first,  … [line truncated: 1238 more bytes on this line]
{"name":"path_between","description":"Does A REACH B, and HOW? — the shortest directed CALL path between two symbols, hop-by-hop. reachable=\"0\" hops=\"0\" is a valid 'not reachable' answer — call edges are name-based, so a missing dynamic/callback edge can hide a real path. Named path_between  … [line truncated: 709 more bytes on this line]
{"name":"connect","description":"When a task touches 2..16 named symbols, returns the minimal subgraph RELATING them - terminals, the fewest joining intermediaries (with signatures), and call edges in true direction - finding the shared-caller joins a directed path_between cannot; unrelated symbols  … [line truncated: 950 more bytes on this line]
{"name":"explore","description":"ONE-call task orientation: the routed+anchored ranking, full bodies of the top hits, their 1-hop callers, field notes, and tests_to_run — ALL under one deterministic byte budget, in a fixed section order (ranking > bodies > callers > notes > tests) that degrades gr … [line truncated: 2134 more bytes on this line]
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
tools= 33  manifest_bytes= 47453  (~tokens at 4 bytes/token: 11863 )
explore                      desc_bytes= 1339 schema_bytes=  958 required=['task']
batch                        desc_bytes= 1235 schema_bytes=  962 required=['queries']
edit_check                   desc_bytes= 1180 schema_bytes=  889 required=['symbol']
slice                        desc_bytes=  953 schema_bytes=  932 required=['symbol']
whereis                      desc_bytes=  701 schema_bytes=  941 required=['symbol']
flags                        desc_bytes=  881 schema_bytes=  720 required=[]
exemplar                     desc_bytes=  951 schema_bytes=  591 required=[]
replace_symbol_body          desc_bytes=  865 schema_bytes=  610 required=['symbol', 'new_body']
impact                       desc_bytes=  821 schema_bytes=  666 required=['symbol']
situational_awareness        desc_bytes=  864 schema_bytes=  581 required=[]
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
quality_delta                desc_bytes=  750 schema_bytes=  279 required=[]
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

`````
{"jsonrpc":"2.0","id":1,"result":{"protocolVersion":"2025-11-25","serverInfo":{"name":"ripwire","version":"0.6.10-dev.139+g6ace381eb"},"capabilities":{"tools":{},"resources":{}},"instructions":"Map before reading files. Start a new task with explore; use from_trace for an error; use impact plus uses … [line truncated: 977 more bytes on this line]
{"jsonrpc":"2.0","id":2,"result":{"tools":[{"name":"fetch_body","description":"Full (or partial-range) source of a symbol's definition, addressed by the stable `handle` a read verb attached to it (bodies on request, not by default). start_line/end_line are optional, 1-based, INCLUSIVE and BODY-RELAT … [line truncated: 1092 more bytes on this line]
{"name":"quality_delta","description":"Your PR self-check, run every time you think a change is DONE — pairs with the CLI-only --test-gate (names the tests to run + the untested blast radius; not MCP-exposed) to form the two-step pre-PR gate. Reports ONLY what your tree made WORSE vs baseline, acr … [line truncated: 870 more bytes on this line]
{"name":"impact","description":"IS IT SAFE TO CHANGE X? — the TRANSITIVE blast radius of a symbol via calls, nearest first (d= hop depth), then PageRank. Use before modifying or deleting a symbol; it beats find_referencing_symbols (direct callers only), and 'uses' catches the read/write/import sit … [line truncated: 1325 more bytes on this line]
{"name":"uses","description":"The STATICALLY RESOLVABLE use-sites of a symbol, not just calls: role (call | read | write | import | extends), file:line, and enclosing symbol. Use to see the footprint before renaming or changing a name — find_referencing_symbols and impact follow only calls. extern … [line truncated: 1146 more bytes on this line]
{"name":"explore","description":"ONE-call task orientation: the routed+anchored ranking, full bodies of the top hits, their 1-hop callers, field notes, and tests_to_run — ALL under one deterministic byte budget, in a fixed section order (ranking > bodies > callers > notes > tests) that degrades gr … [line truncated: 2134 more bytes on this line]
{"name":"from_trace","description":"Paste a stack trace / sanitizer report / compiler error and get it mapped onto indexed symbols, ranked INNERMOST-first: the parsed <trace> frame map, the ranked suspects' signatures, and the innermost in-corpus symbol's FULL body. Out-of-corpus frames are listed a … [line truncated: 1233 more bytes on this line]
{"name":"edit_check","description":"Just edited a symbol? Did its CONTRACT (param count + publicness) change vs git HEAD, and which 1-hop callers are NOW INCOMPATIBLE with the new arity by fixed-arity evidence (not a guess — every folded definition disagrees)? This is call sites worth OPENING, not … [line truncated: 1908 more bytes on this line]
{"name":"batch","description":"ONE-TURN CONTEXT SWEEP: answer up to 16 heterogeneous READ sub-queries in a single call (the deterministic $0 counterpart of a parallel-search agent). queries = array over the SAME path, in EITHER grammar: {verb, ...args} objects, or the CLI --batch file's own \"verb:a … [line truncated: 2040 more bytes on this line]
`````

The core manifest, summarised (name / description bytes / required args):

`````
tools= 8  manifest_bytes= 14193  (~tokens at 4 bytes/token: 3548 )
explore                      desc_bytes= 1339 schema_bytes=  958 required=['task']
batch                        desc_bytes= 1235 schema_bytes=  962 required=['queries']
edit_check                   desc_bytes= 1180 schema_bytes=  889 required=['symbol']
impact                       desc_bytes=  821 schema_bytes=  666 required=['symbol']
from_trace                   desc_bytes=  836 schema_bytes=  559 required=['trace']
uses                         desc_bytes=  626 schema_bytes=  682 required=['symbol']
fetch_body                   desc_bytes=  623 schema_bytes=  588 required=['handle']
quality_delta                desc_bytes=  750 schema_bytes=  279 required=[]
`````

## `printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize"}' '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"for","arguments":{"path":".","task":"pagerank power iteration"}}}' | ./build/ripwire --mcp`

*MCP `for`: always bundle=sigs (never the CLI's compact route), the same ranked signatures as --for.*

**wall time: 5.21s**

`````
{"jsonrpc":"2.0","id":1,"result":{"protocolVersion":"2025-11-25","serverInfo":{"name":"ripwire","version":"0.6.10-dev.139+g6ace381eb"},"capabilities":{"tools":{},"resources":{}},"instructions":"Map before reading files. Start a new task with explore; use from_trace for an error; use impact plus uses … [line truncated: 760 more bytes on this line]
{"jsonrpc":"2.0","id":2,"result":{"content":[{"type":"text","text":"<ctx task=\"pagerank power iteration\" route=\"subtoken+body\" root=\".\" confidence=\"high\" margin_pct=\"22\" at=\"6ace381eb\" doc_mentions=\"4\" doc_mentions_capped=\"1\" doc_mentions_total=\"14\" bundle=\"sigs\" lens=\"churn,amp … [line truncated: 21223 more bytes on this line]
"_index":"[index: files=4838 symbols=44601 hash=c9f4119c]","_fresh":"ok"}}
`````

## `printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize"}' '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"whereis","arguments":{"path":".","symbol":"rankGraphTeleport"}}}' '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"whereis","arguments":{"path":".","symbol":"computeOnePairOverlap"}}}' | ./build/ripwire --mcp --mcp-legend=inline`

*--mcp-legend=inline: every answer of the stdio session carries its own legend (the default, session, sends each definition once per session after the first answer).*

**wall time: 47.79s**

`````
{"jsonrpc":"2.0","id":1,"result":{"protocolVersion":"2025-11-25","serverInfo":{"name":"ripwire","version":"0.6.10-dev.139+g6ace381eb"},"capabilities":{"tools":{},"resources":{}},"instructions":"Map before reading files. Start a new task with explore; use from_trace for an error; use impact plus uses … [line truncated: 757 more bytes on this line]
{"jsonrpc":"2.0","id":2,"result":{"content":[{"type":"text","text":"<!-- ripwire whereis schema=ripwire.whereis/v1: every LOCAL ref whose tree holds sym= (refs_scanned=, blobs=), HEAD first: <hit ref= tip= date= p= l= kind= t=>. window: shown= total= capped= has_more= next_offset= offset= limit= (ca … [line truncated: 13902 more bytes on this line]
"_index":"[index: files=4838 symbols=44601 hash=c9f4119c]","_fresh":"ok"}}
{"jsonrpc":"2.0","id":3,"result":{"content":[{"type":"text","text":"<!-- ripwire whereis schema=ripwire.whereis/v1: every LOCAL ref whose tree holds sym= (refs_scanned=, blobs=), HEAD first: <hit ref= tip= date= p= l= kind= t=>. window: shown= capped= (capped=1 cut). at=: commit+dirty+shallow. next= … [line truncated: 2425 more bytes on this line]
"_index":"[index: files=4838 symbols=44601 hash=c9f4119c]","_fresh":"ok"}}
`````

stderr:

`````
ripwire: warning: --whereis read the newest 374 of 641 local branches; 267 older were not read (limit: 2097152 tree entries across all refs, 375 refs with HEAD at this tree's size); pass --detail=1 to read every branch, or narrow the branches with a ref-name filter
ripwire: warning: --whereis left 404 branch blobs unparsed, their rows kind=text (limit: 256 blobs or 64 MB per answer); pass --detail=1 to parse every one
ripwire: warning: --whereis read the newest 374 of 641 local branches; 267 older were not read (limit: 2097152 tree entries across all refs, 375 refs with HEAD at this tree's size); pass --detail=1 to read every branch, or narrow the branches with a ref-name filter
`````

## `printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize"}' '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"explore","arguments":{"path":".","task":"add a new output format flag to the CLI","budget_tokens":2000}}}' | ./build/ripwire --mcp`

*MCP `explore` = --pack-task under a token budget, one call.*

**wall time: 3.68s**

`````
{"jsonrpc":"2.0","id":1,"result":{"protocolVersion":"2025-11-25","serverInfo":{"name":"ripwire","version":"0.6.10-dev.139+g6ace381eb"},"capabilities":{"tools":{},"resources":{}},"instructions":"Map before reading files. Start a new task with explore; use from_trace for an error; use impact plus uses … [line truncated: 760 more bytes on this line]
{"jsonrpc":"2.0","id":2,"result":{"content":[{"type":"text","text":"<ctx schema=\"ripwire.pack-task/v1\" task=\"add a new output format flag to the CLI\" route=\"subtoken+body:declined(add;205-carriers,69-defs)\" root=\".\" dropped_positive=\"2\" est_tokens=\"1432\" budget_tokens=\"2000\"><!-- ripwi … [line truncated: 3842 more bytes on this line]
"_index":"[index: files=4838 symbols=44601 hash=c9f4119c]","_fresh":"ok"}}
`````

## `printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize"}' '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"fetch_body","arguments":{"path":".","handle":"rankGraphTeleport"}}}' | ./build/ripwire --mcp`

*MCP `fetch_body`: the lazy-body handle posture — bodies only after ranked retrieval, by bare name here.*

**wall time: 3.96s**

`````
{"jsonrpc":"2.0","id":1,"result":{"protocolVersion":"2025-11-25","serverInfo":{"name":"ripwire","version":"0.6.10-dev.139+g6ace381eb"},"capabilities":{"tools":{},"resources":{}},"instructions":"Map before reading files. Start a new task with explore; use from_trace for an error; use impact plus uses … [line truncated: 760 more bytes on this line]
{"jsonrpc":"2.0","id":2,"result":{"content":[{"type":"text","text":"{\"resolved_from_name\":\"rankGraphTeleport\",\"handle\":\"sym#cfb3dc25a9d1fa2c@dcae20d4cac29524\",\"name\":\"rankGraphTeleport\",\"kind\":\"fn\",\"file\":\"src/graph.h\",\"line\":14619,\"start_line\":1,\"end_line\":29,\"total_lines … [line truncated: 1330 more bytes on this line]
"_index":"[index: files=4838 symbols=44601 hash=c9f4119c]","_fresh":"ok"}}
`````

## `printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize"}' '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"grep","arguments":{"path":".","pattern":"DISCLOSE","limit":3}}}' | ./build/ripwire --mcp`

*MCP `grep` with paging args.*

**wall time: 4.62s**

`````
{"jsonrpc":"2.0","id":1,"result":{"protocolVersion":"2025-11-25","serverInfo":{"name":"ripwire","version":"0.6.10-dev.139+g6ace381eb"},"capabilities":{"tools":{},"resources":{}},"instructions":"Map before reading files. Start a new task with explore; use from_trace for an error; use impact plus uses … [line truncated: 760 more bytes on this line]
{"jsonrpc":"2.0","id":2,"result":{"content":[{"type":"text","text":"{\"pattern\":\"DISCLOSE\",\"root\":\".\",\"files\":291,\"shown\":3,\"capped\":true,\"total\":991,\"has_more\":true,\"next_offset\":3,\"offset\":0,\"limit\":3,\"hits_capped\":false,\"next\":\"--grep=DISCLOSE --offset=3 --legend=compa … [line truncated: 609 more bytes on this line]
{\"file\":\"src/abicheck.h\",\"line\":517,\"in\":\"abicheck::collectAuthoredSites\",\"parse_degraded\":true,\"text\":\"            DISCLOSE( result, AbiResult::DisclosureWhy::NoMergeBase, \\\"abi: no merge-base for a ref (unrelated history?) — that ref is counted, not compared\\\" );\"},
{\"file\":\"src/arch.h\",\"line\":512,\"in\":\"rw::parseArchRules\",\"text\":\"        DISCLOSE( Diagnostics::answerRefused, \\\"--arch exits 1 with path:line and the reason on stderr; no report is printed\\\",\"}],\"parse_degraded_note\":\"a hit carrying parse_degraded:true sits in a file whose par … [line truncated: 465 more bytes on this line]
{\"file\":\"CMakeLists.txt\",\"line\":347},
{\"file\":\"CMakeLists.txt\",\"line\":894}]},\"enclosing\":[{\"n\":\"path_instructions\",\"callers\":0,\"handle_omitted\":\"non-code\"},
{\"n\":\"abicheck::collectAuthoredSites\",\"callers\":1,\"cx\":9,\"handle\":\"sym#1ab32951dcc2d860@336bb5738da2ef84\"},
{\"n\":\"rw::parseArchRules\",\"callers\":2,\"cx\":33,\"handle\":\"sym#f5dd171cfba47899@8ee26f354c3d783f\"}]}"}],
"_index":"[index: files=4838 symbols=44601 hash=c9f4119c]","_fresh":"ok"}}
`````

## `printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize"}' '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"slice","arguments":{"path":".","symbol":"rankGraphTeleport","var":"teleport","flow":"back","depth":3}}}' | ./build/ripwire --mcp`

*MCP `slice` — the CLI's --slice/--slice-flow/--slice-depth as one verb.*

**wall time: 9.05s**

`````
{"jsonrpc":"2.0","id":1,"result":{"protocolVersion":"2025-11-25","serverInfo":{"name":"ripwire","version":"0.6.10-dev.139+g6ace381eb"},"capabilities":{"tools":{},"resources":{}},"instructions":"Map before reading files. Start a new task with explore; use from_trace for an error; use impact plus uses … [line truncated: 760 more bytes on this line]
{"jsonrpc":"2.0","id":2,"result":{"content":[{"type":"text","text":"<!-- ripwire slice schema=ripwire.slice/v1: name-based def-use rows of one variable in one definition: <s l= k=def|use|both|scope t= [b= pp= rd=]> (rd= reaching-def lines per reach=cfg|linear), <v n= l= t=> inventory; steps=/depth=  … [line truncated: 1777 more bytes on this line]
"_index":"[index: files=4838 symbols=44601 hash=c9f4119c]","_fresh":"ok"}}
`````

## `printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize"}' '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"find_symbol","arguments":{"path":".","symbol":"DoesNotExist"}}}' | ./build/ripwire --mcp`

*MCP error shape: an unknown symbol comes back as a JSON-RPC error/refusal, not an empty success.*

**wall time: 7.46s**

`````
{"jsonrpc":"2.0","id":1,"result":{"protocolVersion":"2025-11-25","serverInfo":{"name":"ripwire","version":"0.6.10-dev.139+g6ace381eb"},"capabilities":{"tools":{},"resources":{}},"instructions":"Map before reading files. Start a new task with explore; use from_trace for an error; use impact plus uses … [line truncated: 760 more bytes on this line]
{"jsonrpc":"2.0","id":2,"error":{"code":-32602,"message":"symbol not found: 'DoesNotExist' — pass the final name segment; add scope to disambiguate — or @FILE:LINE when you hold a location — note: the lexical definition scan stopped at its budget, 4096 files or 16 MiB, before reading every fil … [line truncated: 165 more bytes on this line]
`````

## `printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize"}' '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"batch","arguments":{"path":".","queries":[{"verb":"for","task":"incremental cache invalidation"},{"verb":"find_referencing_symbols","symbol":"rankGraphTeleport"},{"verb":"grep","pattern":"DISCLOSE","limit":2}]}}}' | ./build/ripwire --mcp`

*MCP `batch`: three independent read queries answered in ONE round-trip — NOTE the sub-query grammar is {verb, ...args} objects with MCP verb names, not the CLI --batch file's verb:arg lines.*

**wall time: 5.48s**

`````
{"jsonrpc":"2.0","id":1,"result":{"protocolVersion":"2025-11-25","serverInfo":{"name":"ripwire","version":"0.6.10-dev.139+g6ace381eb"},"capabilities":{"tools":{},"resources":{}},"instructions":"Map before reading files. Start a new task with explore; use from_trace for an error; use impact plus uses … [line truncated: 760 more bytes on this line]
{"jsonrpc":"2.0","id":2,"result":{"content":[{"type":"text","text":"<batch schema=\"ripwire.batch/v1\" n=\"3\" requested=\"3\" cap=\"16\"><!-- ripwire batch schema=ripwire.batch/v1: n= read sub-queries in one sweep (requested=, cap=): each <q> wraps one sub-answer verbatim in CDATA. i=/verb=/ok=: su … [line truncated: 27908 more bytes on this line]
{\"name\":\"rankGraph\",\"kind\":\"fn\",\"file\":\"src/graph.h\",\"line\":14662,\"handle\":\"sym#b90da690b120eeb3@dcae20d4cac29524\",\"sites_at\":[\"14666\"]},
{\"name\":\"anchoredLexicalRank\",\"kind\":\"fn\",\"file\":\"src/graph.h\",\"line\":15331,\"handle\":\"sym#b3a5ca7873636567@dcae20d4cac29524\",\"sites_at\":[\"15382\"]},
{\"name\":\"runEval\",\"kind\":\"fn\",\"file\":\"src/eval.h\",\"line\":171,\"handle\":\"sym#358fe2cb69804698@1f9d26ff6c500240\",\"sites_at\":[\"328\"]},
{\"name\":\"churnDecayRanking\",\"kind\":\"fn\",\"file\":\"src/main.cpp\",\"line\":1432,\"handle\":\"sym#f43b7580f05a651a@86d62bcf68f60549\",\"sites_at\":[\"1446\"]},
{\"name\":\"churnRankedGraph\",\"kind\":\"fn\",\"file\":\"src/main.cpp\",\"line\":1471,\"handle\":\"sym#4b5b63d3932ca0ff@86d62bcf68f60549\",\"sites_at\":[\"1485\",\"1486\",\"1500\"]},
{\"name\":\"runDefaultMap\",\"kind\":\"fn\",\"file\":\"src/main.cpp\",\"line\":1758,\"handle\":\"sym#6e2725cb96590ec8@86d62bcf68f60549\",\"sites_at\":[\"1878\"]}],\"sites_note\":\"sites_at= on a caller row: its calls of the called LEAF name, bar ones proven elsewhere, as [file:]line (space-separated … [line truncated: 1237 more bytes on this line]
{\"file\":\"src/abicheck.h\",\"line\":517,\"in\":\"abicheck::collectAuthoredSites\",\"parse_degraded\":true,\"text\":\"            DISCLOSE( result, AbiResult::DisclosureWhy::NoMergeBase, \\\"abi: no merge-base for a ref (unrelated history?) — that ref is counted, not compared\\\" );\"}],\"parse_d … [line truncated: 541 more bytes on this line]
{\"file\":\"CMakeLists.txt\",\"line\":347}]},\"enclosing\":[{\"n\":\"path_instructions\",\"callers\":0,\"handle_omitted\":\"non-code\"},
{\"n\":\"abicheck::collectAuthoredSites\",\"callers\":1,\"cx\":9,\"handle\":\"sym#1ab32951dcc2d860@336bb5738da2ef84\"}]}]]></q></batch>"}],
"_index":"[index: files=4838 symbols=44601 hash=c9f4119c]","_fresh":"ok"}}
`````

## `printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize"}' '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"batch","arguments":{"path":".","queries":["for:incremental cache invalidation","callers:rankGraphTeleport"]}}}' | ./build/ripwire --mcp`

*The CLI --batch spelling handed to MCP `batch`: refused, with the accepted shape named.*

**wall time: 19.28s**

`````
{"jsonrpc":"2.0","id":1,"result":{"protocolVersion":"2025-11-25","serverInfo":{"name":"ripwire","version":"0.6.10-dev.139+g6ace381eb"},"capabilities":{"tools":{},"resources":{}},"instructions":"Map before reading files. Start a new task with explore; use from_trace for an error; use impact plus uses … [line truncated: 760 more bytes on this line]
{"jsonrpc":"2.0","id":2,"result":{"content":[{"type":"text","text":"<batch schema=\"ripwire.batch/v1\" n=\"2\" requested=\"2\" cap=\"16\"><!-- ripwire batch schema=ripwire.batch/v1: n= read sub-queries in one sweep (requested=, cap=): each <q> wraps one sub-answer verbatim in CDATA. i=/verb=/ok=: su … [line truncated: 27891 more bytes on this line]
{\"name\":\"rankGraph\",\"kind\":\"fn\",\"file\":\"src/graph.h\",\"line\":14662,\"handle\":\"sym#b90da690b120eeb3@dcae20d4cac29524\",\"sites_at\":[\"14666\"]},
{\"name\":\"anchoredLexicalRank\",\"kind\":\"fn\",\"file\":\"src/graph.h\",\"line\":15331,\"handle\":\"sym#b3a5ca7873636567@dcae20d4cac29524\",\"sites_at\":[\"15382\"]},
{\"name\":\"runEval\",\"kind\":\"fn\",\"file\":\"src/eval.h\",\"line\":171,\"handle\":\"sym#358fe2cb69804698@1f9d26ff6c500240\",\"sites_at\":[\"328\"]},
{\"name\":\"churnDecayRanking\",\"kind\":\"fn\",\"file\":\"src/main.cpp\",\"line\":1432,\"handle\":\"sym#f43b7580f05a651a@86d62bcf68f60549\",\"sites_at\":[\"1446\"]},
{\"name\":\"churnRankedGraph\",\"kind\":\"fn\",\"file\":\"src/main.cpp\",\"line\":1471,\"handle\":\"sym#4b5b63d3932ca0ff@86d62bcf68f60549\",\"sites_at\":[\"1485\",\"1486\",\"1500\"]},
{\"name\":\"runDefaultMap\",\"kind\":\"fn\",\"file\":\"src/main.cpp\",\"line\":1758,\"handle\":\"sym#6e2725cb96590ec8@86d62bcf68f60549\",\"sites_at\":[\"1878\"]}],\"sites_note\":\"sites_at= on a caller row: its calls of the called LEAF name, bar ones proven elsewhere, as [file:]line (space-separated … [line truncated: 365 more bytes on this line]
"_index":"[index: files=4838 symbols=44601 hash=c9f4119c]","_fresh":"ok"}}
`````

## `printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize"}' '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"edit_check","arguments":{"path":".","symbol":"rankGraphTeleport"}}}' | ./build/ripwire --mcp`

*MCP `edit_check` on a CLEAN tree.*

**wall time: 26.28s**

`````
{"jsonrpc":"2.0","id":1,"result":{"protocolVersion":"2025-11-25","serverInfo":{"name":"ripwire","version":"0.6.10-dev.139+g6ace381eb"},"capabilities":{"tools":{},"resources":{}},"instructions":"Map before reading files. Start a new task with explore; use from_trace for an error; use impact plus uses … [line truncated: 760 more bytes on this line]
{"jsonrpc":"2.0","id":2,"result":{"content":[{"type":"text","text":"<!-- ripwire edit-check schema=ripwire.edit-check/v1: sym='s contract NOW vs HEAD: status=unchanged|new-symbol|contract-change; <c n= p= incompatible=1 sites_l=> callers. counts_floor=1: every count is a FLOOR, never a total. graph_ … [line truncated: 1200 more bytes on this line]
"_index":"[index: files=4838 symbols=44601 hash=c9f4119c]","_fresh":"ok"}}
`````

## `printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize"}' '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"edit_check","arguments":{"path":".","symbol":"rankGraphTeleport","legend":"compact"}}}' | ./build/ripwire --mcp`

*The same MCP `edit_check` with legend:"compact" — the CLI --legend=compact dialect on the MCP side (declared on the 16 XML verbs): ~5.5 KB of legend down to ~600 B, rows identical; an unknown or empty legend value is refused, never read as the default.*

**wall time: 25.14s**

`````
{"jsonrpc":"2.0","id":1,"result":{"protocolVersion":"2025-11-25","serverInfo":{"name":"ripwire","version":"0.6.10-dev.139+g6ace381eb"},"capabilities":{"tools":{},"resources":{}},"instructions":"Map before reading files. Start a new task with explore; use from_trace for an error; use impact plus uses … [line truncated: 760 more bytes on this line]
{"jsonrpc":"2.0","id":2,"result":{"content":[{"type":"text","text":"<!-- ripwire edit-check schema=ripwire.edit-check/v1: sym='s contract NOW vs HEAD: status=unchanged|new-symbol|contract-change; <c n= p= incompatible=1 sites_l=> callers. counts_floor=1: every count is a FLOOR, never a total. graph_ … [line truncated: 1200 more bytes on this line]
"_index":"[index: files=4838 symbols=44601 hash=c9f4119c]","_fresh":"ok"}}
`````

## `printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize"}' '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"nosuchverb","arguments":{"path":"."}}}' | ./build/ripwire --mcp`

*An unknown verb name — the JSON-RPC error shape.*

`````
{"jsonrpc":"2.0","id":1,"result":{"protocolVersion":"2025-11-25","serverInfo":{"name":"ripwire","version":"0.6.10-dev.139+g6ace381eb"},"capabilities":{"tools":{},"resources":{}},"instructions":"Map before reading files. Start a new task with explore; use from_trace for an error; use impact plus uses … [line truncated: 760 more bytes on this line]
{"jsonrpc":"2.0","id":2,"error":{"code":-32602,"message":"unknown tool: 'nosuchverb' — call tools/list for the 33 available tools"}}
`````
