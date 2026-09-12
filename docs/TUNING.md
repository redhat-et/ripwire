# Cap sensitivity — measured

**Generated — do not edit.** `python3 bench/capsweep/capsweep.py prepare|screen|sweep|emit`.

The measurements it is generated from live in `bench/capsweep/*.tsv` rather than json because
ripwire indexes `.json` as config keys while `.tsv` is unindexed prose (`kUnindexedProseExts` in
`src/docparse.h`) — a harness must not enter the index it measures.

What each compile-time cap actually COSTS, per verb. `docs/LIMITS.md` says a cap exists;
this says what it does. Measured by patching a SCRATCH copy of the tree so the caps read an
env var — production keeps its `constexpr` and is never patched — then running real
invocations at the default value and at a probe value. The tunable binary is byte-identical
to production at defaults; that control is what makes these numbers mean anything.

| cap declarations | distinct names | tunable | must stay `constexpr` | move >= 1 invocation | move nothing measurable |
| --- | --- | --- | --- | --- | --- |
| 126 | 125 | 112 | 12 | **37** | 75 |

The first two columns are not the same number, and the gap is not a rounding: `src/` holds
**126 cap declarations** under **125 distinct names** (`kRowCap` declared in more than one file). The
sweep patches by NAME, so `112 + 12` accounts for the 125 NAMES — not the 126 declarations. Quoting
"113 of 126" would be wrong in both halves at once, which is exactly the shape of error a
generated table exists to prevent.

## Read this ratio before the tables

**37 of 112 tunable caps move any invocation at all. 75 move nothing measurable.** That is the
finding, and it says what NOT to do: this is not a 126-cap audit. Most of these constants are
inert on real invocations and should be left alone. The work worth doing is the small set below,
plus the caps that fire SILENTLY — a cap that bites without disclosing is a defect independent of
whether its value is right, and that fix is both cheaper and larger than any retuning.

## What this instrument CANNOT see

This measures output **size**. A cap that makes an answer WRONG rather than shorter is invisible
to it: a truncated complexity walk emits a `cx=` that is simply too low, a truncated parameter
walk emits an arity that is simply wrong, and both produce bytes that look perfectly fine. A
wrong number with `capped="1"` beside it is still a wrong number. That class needs
**re-derivation** as its instrument — recompute the value without the bound and compare — and it
cannot be folded into this sweep. Do not read a cap's absence from these tables as safety.

Two caps have been through that second instrument. Both came back inert, and `docs/LIMITS.md`
records them under "Refuted by re-derivation" so neither is proposed again.

## Provenance

Sizes were measured against `da7af625`, on a corpus frozen with `git archive HEAD` at that commit.
The cap names, values and files below are re-read from `src/` on every run of `emit`, so a
retuned or renamed cap makes `test/capsweepcheck.sh` fail rather than leaving a stale number
standing. The **byte deltas are frozen** and do not re-measure themselves: they are only as
current as the commit above, and a change to what a verb emits can age them without any cap
moving. Re-run `prepare|screen|sweep` to refresh them.

### `kForLensDefaultTopN` = `40`

`src/serialize.h` — discloses: `calls_capped`, `inc_capped`, `sibs_capped` — probe value `320` — **12 verb(s) respond**

| invocation | default | at probe | delta |
| --- | --- | --- | --- |
| `. --for="pagerank power iteration" --detail=2` | 14560 B | 14142 B | -418 B |
| `. --for="pagerank power iteration" --with-graph` | 10078 B | 9660 B | -418 B |
| `. --for="why does src/lexical.h chooseForRanker pick name-exact BM25"` | 10268 B | 10038 B | -230 B |
| `. --for="rankGraphTeleport" --no-route` | 15900 B | 16075 B | +175 B |
| `. --for="quality delta acks ledger rubber stamp" --no-doc-mention` | 10119 B | 9984 B | -135 B |
| `. --for="incremental cache invalidation when a file content hash chang` | 9903 B | 9828 B | -75 B |
| `. --for="tree-sitter parse of a source file" --adaptive` | 9897 B | 9948 B | +51 B |
| `. --for="tree-sitter parse of a source file" --auto-bodies` | 15916 B | 15965 B | +49 B |
| `. --for="quality delta acks ledger rubber stamp"` | 10055 B | 10103 B | +48 B |
| `. --for="tree-sitter parse of a source file" --legend=compact` | 9566 B | 9569 B | +3 B |
| `. --for="rankGraphTeleport"` | 5491 B | 5493 B | +2 B |
| `. --for="rankGraphTeleport" --signatures-only` | 2813 B | 2815 B | +2 B |

### `kSpecificMinLen` = `8`

`src/graph.h` — discloses: `importers_capped` — probe value `64` — **12 verb(s) respond**

| invocation | default | at probe | delta |
| --- | --- | --- | --- |
| `.` | 24372 B | 24676 B | +304 B |
| `. --map-diff --top-k=5` | 2684 B | 2925 B | +241 B |
| `. --zoom --zoom-levels=3` | 12093 B | 12264 B | +171 B |
| `. --zoom` | 8411 B | 8525 B | +114 B |
| `. --no-cache --top-k=3` | 1920 B | 1825 B | -95 B |
| `. --no-ignore --top-k=3` | 1920 B | 1825 B | -95 B |
| `. --no-stable --top-k=3` | 1920 B | 1825 B | -95 B |
| `. --tree` | 11760 B | 11675 B | -85 B |
| `. --pack-top-n=3 --top-k=0` | 65670 B | 65748 B | +78 B |
| `. --communities` | 17674 B | 17600 B | -74 B |
| `. --impact=rankGraphTeleport` | 7860 B | 7823 B | -37 B |
| `. --seams` | 13085 B | 13108 B | +23 B |

### `kDocMentionMaxAnchors` = `8`

`src/mention.h` — discloses: `doc_mentions_capped`, `mention_files_capped`, `mention_syms_capped`, `mention_tokens_capped` — probe value `64` — **11 verb(s) respond**

| invocation | default | at probe | delta |
| --- | --- | --- | --- |
| `. --pack-task="add a new output format flag to the CLI" --partition=3` | 24028 B | 22287 B | -1741 B |
| `. --for="incremental cache invalidation when a file content hash chang` | 9903 B | 10059 B | +156 B |
| `. --pack-task="add a new output format flag to the CLI"` | 9480 B | 9593 B | +113 B |
| `. --for="tree-sitter parse of a source file" --adaptive` | 9897 B | 9810 B | -87 B |
| `. --for="tree-sitter parse of a source file" --auto-bodies` | 15916 B | 15829 B | -87 B |
| `. --for="tree-sitter parse of a source file" --legend=compact` | 9566 B | 9484 B | -82 B |
| `. --for="pagerank power iteration" --detail=2` | 14560 B | 14562 B | +2 B |
| `. --for="pagerank power iteration" --with-graph` | 10078 B | 10080 B | +2 B |
| `. --for="quality delta acks ledger rubber stamp"` | 10055 B | 10057 B | +2 B |
| `. --for="rankGraphTeleport" --no-route` | 15900 B | 15902 B | +2 B |
| `. --for="why does src/lexical.h chooseForRanker pick name-exact BM25"` | 10268 B | 10266 B | -2 B |

### `kForFileTailShownCap` = `24`

`src/serialize.h` — discloses: `calls_capped`, `inc_capped`, `sibs_capped` — probe value `192` — **10 verb(s) respond**

| invocation | default | at probe | delta |
| --- | --- | --- | --- |
| `. --for="quality delta acks ledger rubber stamp" --no-doc-mention` | 10119 B | 15684 B | +5565 B |
| `. --for="quality delta acks ledger rubber stamp"` | 10055 B | 15611 B | +5556 B |
| `. --for="rankGraphTeleport" --no-route` | 15900 B | 21436 B | +5536 B |
| `. --for="why does src/lexical.h chooseForRanker pick name-exact BM25"` | 10268 B | 15148 B | +4880 B |
| `. --for="incremental cache invalidation when a file content hash chang` | 9903 B | 14704 B | +4801 B |
| `. --for="tree-sitter parse of a source file" --legend=compact` | 9566 B | 14333 B | +4767 B |
| `. --for="tree-sitter parse of a source file" --adaptive` | 9897 B | 14662 B | +4765 B |
| `. --for="tree-sitter parse of a source file" --auto-bodies` | 15916 B | 20681 B | +4765 B |
| `. --for="pagerank power iteration" --detail=2` | 14560 B | 16231 B | +1671 B |
| `. --for="pagerank power iteration" --with-graph` | 10078 B | 11749 B | +1671 B |

### `kForPayloadBudgetBytes` = `7500`

`src/serialize.h` — discloses: `calls_capped`, `inc_capped`, `sibs_capped` — probe value `60000` — **10 verb(s) respond**

| invocation | default | at probe | delta |
| --- | --- | --- | --- |
| `. --for="tree-sitter parse of a source file" --auto-bodies` | 15916 B | 32067 B | +16151 B |
| `. --for="rankGraphTeleport" --no-route` | 15900 B | 30265 B | +14365 B |
| `. --for="incremental cache invalidation when a file content hash chang` | 9903 B | 18389 B | +8486 B |
| `. --for="why does src/lexical.h chooseForRanker pick name-exact BM25"` | 10268 B | 16466 B | +6198 B |
| `. --for="pagerank power iteration" --detail=2` | 14560 B | 20545 B | +5985 B |
| `. --for="pagerank power iteration" --with-graph` | 10078 B | 16063 B | +5985 B |
| `. --for="quality delta acks ledger rubber stamp"` | 10055 B | 15996 B | +5941 B |
| `. --for="quality delta acks ledger rubber stamp" --no-doc-mention` | 10119 B | 15859 B | +5740 B |
| `. --for="tree-sitter parse of a source file" --adaptive` | 9897 B | 14781 B | +4884 B |
| `. --for="tree-sitter parse of a source file" --legend=compact` | 9566 B | 13971 B | +4405 B |

### `kForCapTailSigBytes` = `96`

`src/serialize.h` — discloses: `calls_capped`, `inc_capped`, `sibs_capped` — probe value `768` — **8 verb(s) respond**

| invocation | default | at probe | delta |
| --- | --- | --- | --- |
| `. --for="quality delta acks ledger rubber stamp"` | 10055 B | 9843 B | -212 B |
| `. --for="tree-sitter parse of a source file" --adaptive` | 9897 B | 9765 B | -132 B |
| `. --for="tree-sitter parse of a source file" --auto-bodies` | 15916 B | 15784 B | -132 B |
| `. --for="quality delta acks ledger rubber stamp" --no-doc-mention` | 10119 B | 10006 B | -113 B |
| `. --pack-task="add a new output format flag to the CLI" --partition=3` | 24028 B | 24137 B | +109 B |
| `. --pack-task="add a new output format flag to the CLI"` | 9480 B | 9544 B | +64 B |
| `. --for="why does src/lexical.h chooseForRanker pick name-exact BM25"` | 10268 B | 10296 B | +28 B |
| `. --for="tree-sitter parse of a source file" --legend=compact` | 9566 B | 9558 B | -8 B |

### `kMaxExpandSibs` = `100`

`src/serialize.h` — discloses: `calls_capped`, `inc_capped`, `sibs_capped` — probe value `800` — **5 verb(s) respond**

| invocation | default | at probe | delta |
| --- | --- | --- | --- |
| `. --expand=readAckRecords --top-k=0 --no-redact` | 11317 B | 16612 B | +5295 B |
| `. --expand=compressBody --top-k=0 --compress` | 8077 B | 9675 B | +1598 B |
| `. --expand=rankGraphTeleport --top-k=0` | 4926 B | 6033 B | +1107 B |
| `. --expand=rankGraphTeleport:1-12 --top-k=0` | 4314 B | 5421 B | +1107 B |
| `. --top-k=0 --expand=rankGraphTeleport` | 4926 B | 6033 B | +1107 B |

### `kCommonNameDefThreshold` = `5`

`src/graph.h` — discloses: `importers_capped` — probe value `40` — **4 verb(s) respond**

| invocation | default | at probe | delta |
| --- | --- | --- | --- |
| `. --zoom --zoom-levels=3` | 12093 B | 12165 B | +72 B |
| `. --zoom` | 8411 B | 8459 B | +48 B |
| `. --tree` | 11760 B | 11735 B | -25 B |
| `. --communities` | 17674 B | 17669 B | -5 B |

### `kLintMaxPerRule` = `5000`

`src/lintrules.h` — discloses: **none** — probe value `40000` — **4 verb(s) respond**

| invocation | default | at probe | delta |
| --- | --- | --- | --- |
| `. --lint --sarif` | 1162929 B | 1675848 B | +512919 B |
| `. --lint` | 71025 B | 70972 B | -53 B |
| `. --lint --lint-ignore=naming-,cache-` | 66983 B | 66930 B | -53 B |
| `. --lint --naming-locals` | 73708 B | 73655 B | -53 B |

### `kDocMentionMaxDocsPerAnchor` = `2`

`src/mention.h` — discloses: `doc_mentions_capped`, `mention_files_capped`, `mention_syms_capped`, `mention_tokens_capped` — probe value `34` — **3 verb(s) respond**

| invocation | default | at probe | delta |
| --- | --- | --- | --- |
| `. --for="why does src/lexical.h chooseForRanker pick name-exact BM25"` | 10268 B | 10111 B | -157 B |
| `. --for="pagerank power iteration" --detail=2` | 14560 B | 14408 B | -152 B |
| `. --for="pagerank power iteration" --with-graph` | 10078 B | 9926 B | -152 B |

### `kExternalSurfaceRowCap` = `100`

`src/pageview.h` — discloses: `count_capped`, `findings_capped`, `hits_capped`, `importers_capped`, `modules_capped` — probe value `800` — **2 verb(s) respond**

| invocation | default | at probe | delta |
| --- | --- | --- | --- |
| `. --external-surface --include-builtins` | 5553 B | 38663 B | +33110 B |
| `. --external-surface` | 5611 B | 38720 B | +33109 B |

### `kForAutoBodyBudgetBytes` = `6000`

`src/serialize.h` — discloses: `calls_capped`, `inc_capped`, `sibs_capped` — probe value `48000` — **2 verb(s) respond**

| invocation | default | at probe | delta |
| --- | --- | --- | --- |
| `. --for="tree-sitter parse of a source file" --auto-bodies` | 15916 B | 27182 B | +11266 B |
| `. --for="rankGraphTeleport" --no-route` | 15900 B | 22181 B | +6281 B |

### `kHandoffDocRows` = `4`

`src/handoff.h` — discloses: `syms_capped` — probe value `36` — **2 verb(s) respond**

| invocation | default | at probe | delta |
| --- | --- | --- | --- |
| `. --handoff` | 5044 B | 6529 B | +1485 B |
| `. --handoff --token-budget=1200` | 4955 B | 4956 B | +1 B |

### `kHandoffSymbolsPerCodeFile` = `50`

`src/handoff.h` — discloses: `syms_capped` — probe value `400` — **2 verb(s) respond**

| invocation | default | at probe | delta |
| --- | --- | --- | --- |
| `. --handoff` | 5044 B | 5045 B | +1 B |
| `. --handoff --token-budget=1200` | 4955 B | 4956 B | +1 B |

### `kHandoffSymbolsPerDocFile` = `12`

`src/handoff.h` — discloses: `syms_capped` — probe value `96` — **2 verb(s) respond**

| invocation | default | at probe | delta |
| --- | --- | --- | --- |
| `. --handoff` | 5044 B | 12377 B | +7333 B |
| `. --handoff --token-budget=1200` | 4955 B | 12288 B | +7333 B |

### `kOrdinalWindowCap` = `40`

`src/ensemble.h` — discloses: `files_capped`, `findings_capped`, `syms_capped` — probe value `320` — **2 verb(s) respond**

| invocation | default | at probe | delta |
| --- | --- | --- | --- |
| `. --quality-panel` | 15454 B | 16072 B | +618 B |
| `. --ensemble --limit=8` | 10499 B | 10786 B | +287 B |

### `kPrDefaultBudgetTokens` = `8000`

`src/prcontext.h` — discloses: **none** — probe value `64000` — **2 verb(s) respond**

| invocation | default | at probe | delta |
| --- | --- | --- | --- |
| `. --pr-context` | 7947 B | 7948 B | +1 B |
| `. --pr-context=HEAD~1` | 8729 B | 8730 B | +1 B |

### `kUnitComplexityLowRiskMax` = `5`

`src/dmm.h` — discloses: **none** — probe value `40` — **2 verb(s) respond**

| invocation | default | at probe | delta |
| --- | --- | --- | --- |
| `. --dmm` | 3045 B | 3046 B | +1 B |
| `. --dmm=HEAD` | 3073 B | 3074 B | +1 B |

### `kUnitInterfacingLowRiskMax` = `2`

`src/dmm.h` — discloses: **none** — probe value `34` — **2 verb(s) respond**

| invocation | default | at probe | delta |
| --- | --- | --- | --- |
| `. --dmm` | 3045 B | 3046 B | +1 B |
| `. --dmm=HEAD` | 3073 B | 3074 B | +1 B |

### `kUnitSizeLowRiskMax` = `15`

`src/dmm.h` — discloses: **none** — probe value `120` — **2 verb(s) respond**

| invocation | default | at probe | delta |
| --- | --- | --- | --- |
| `. --dmm` | 3045 B | 3046 B | +1 B |
| `. --dmm=HEAD` | 3073 B | 3074 B | +1 B |

### `kZoomTopModuleCap` = `40`

`src/pageview.h` — discloses: `count_capped`, `findings_capped`, `hits_capped`, `importers_capped`, `modules_capped` — probe value `320` — **2 verb(s) respond**

| invocation | default | at probe | delta |
| --- | --- | --- | --- |
| `. --zoom --zoom-levels=3` | 12093 B | 71914 B | +59821 B |
| `. --zoom` | 8411 B | 49506 B | +41095 B |

### `kBatchCap` = `16`

`src/mcpverbs.h` — discloses: `blast_radius_capped`, `coboost_commits_capped`, `forgotten_capped`, `hits_capped`, `unindexed_candidates_capped` — probe value `128` — **1 verb(s) respond**

| invocation | default | at probe | delta |
| --- | --- | --- | --- |
| `. --batch=$RIPWIRE_CAPSWEEP_TMP` | 408 B | 409 B | +1 B |

### `kCallHierarchyRowCap` = `40`

`src/pageview.h` — discloses: `count_capped`, `findings_capped`, `hits_capped`, `importers_capped`, `modules_capped` — probe value `320` — **1 verb(s) respond**

| invocation | default | at probe | delta |
| --- | --- | --- | --- |
| `. --impact=rankGraphTeleport` | 7860 B | 8975 B | +1115 B |

### `kCellsPerRowCap` = `12`

`src/nonlocalstate.h` — discloses: `cells_capped`, `decls_capped` — probe value `96` — **1 verb(s) respond**

| invocation | default | at probe | delta |
| --- | --- | --- | --- |
| `. --nonlocal-state --limit=8` | 9819 B | 9993 B | +174 B |

### `kDefaultRecallMaxTokens` = `8000`

`src/recall.h` — discloses: **none** — probe value `64000` — **1 verb(s) respond**

| invocation | default | at probe | delta |
| --- | --- | --- | --- |
| `. --recall="quality delta gating exit codes"` | 13196 B | 132377 B | +119181 B |

### `kDefsPerNameCap` = `8`

`src/contextratio.h` — discloses: `defs_capped`, `files_capped`, `syms_capped` — probe value `64` — **1 verb(s) respond**

| invocation | default | at probe | delta |
| --- | --- | --- | --- |
| `. --context-ratio --limit=8` | 13314 B | 13702 B | +388 B |

### `kEnsembleFileRowCap` = `20`

`src/ensemble.h` — discloses: `files_capped`, `findings_capped`, `syms_capped` — probe value `160` — **1 verb(s) respond**

| invocation | default | at probe | delta |
| --- | --- | --- | --- |
| `. --ensemble --limit=8` | 10499 B | 27791 B | +17292 B |

### `kFileRowCap` = `40`

`src/contextratio.h` — discloses: `defs_capped`, `files_capped`, `syms_capped` — probe value `320` — **1 verb(s) respond**

| invocation | default | at probe | delta |
| --- | --- | --- | --- |
| `. --context-ratio --limit=8` | 13314 B | 64465 B | +51151 B |

### `kGrepMatchedLineMaxBytes` = `512`

`src/search.h` — discloses: `hits_capped` — probe value `4096` — **1 verb(s) respond**

| invocation | default | at probe | delta |
| --- | --- | --- | --- |
| `. --grep=deterministic` | 44699 B | 63891 B | +19192 B |

### `kMaxExpandIncludes` = `24`

`src/serialize.h` — discloses: `calls_capped`, `inc_capped`, `sibs_capped` — probe value `192` — **1 verb(s) respond**

| invocation | default | at probe | delta |
| --- | --- | --- | --- |
| `. --expand=readAckRecords --top-k=0 --no-redact` | 11317 B | 11632 B | +315 B |

### `kMentionMaxSymbolsPerFile` = `3`

`src/mention.h` — discloses: `doc_mentions_capped`, `mention_files_capped`, `mention_syms_capped`, `mention_tokens_capped` — probe value `35` — **1 verb(s) respond**

| invocation | default | at probe | delta |
| --- | --- | --- | --- |
| `. --for="why does src/lexical.h chooseForRanker pick name-exact BM25"` | 10268 B | 10187 B | -81 B |

### `kPanelRowCap` = `40`

`src/qualitypanel.h` — discloses: `findings_capped` — probe value `320` — **1 verb(s) respond**

| invocation | default | at probe | delta |
| --- | --- | --- | --- |
| `. --quality-panel` | 15454 B | 66476 B | +51022 B |

### `kSituBlastFilesShown` = `8`

`src/situ.h` — discloses: `tests_capped`, `untested_capped` — probe value `64` — **1 verb(s) respond**

| invocation | default | at probe | delta |
| --- | --- | --- | --- |
| `. --situ` | 1705 B | 1679 B | -26 B |

### `kSliceFlowDefaultDepth` = `8`

`src/slice.h` — discloses: **none** — probe value `64` — **1 verb(s) respond**

| invocation | default | at probe | delta |
| --- | --- | --- | --- |
| `. --slice=rankGraphTeleport:teleport --slice-flow=fwd` | 7224 B | 7225 B | +1 B |

### `kSymbolRowCap` = `40`

`src/contextratio.h` — discloses: `defs_capped`, `files_capped`, `syms_capped` — probe value `320` — **1 verb(s) respond**

| invocation | default | at probe | delta |
| --- | --- | --- | --- |
| `. --quality-panel` | 15454 B | 16795 B | +1341 B |

### `kTreeRowCap` = `80`

`src/pageview.h` — discloses: `count_capped`, `findings_capped`, `hits_capped`, `importers_capped`, `modules_capped` — probe value `640` — **1 verb(s) respond**

| invocation | default | at probe | delta |
| --- | --- | --- | --- |
| `. --tree` | 11760 B | 92860 B | +81100 B |

### `kWithGraphNodeCap` = `8`

`src/serialize.h` — discloses: `calls_capped`, `inc_capped`, `sibs_capped` — probe value `64` — **1 verb(s) respond**

| invocation | default | at probe | delta |
| --- | --- | --- | --- |
| `. --for="pagerank power iteration" --with-graph` | 10078 B | 13134 B | +3056 B |

